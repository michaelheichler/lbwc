"""Framework-agnostic error hierarchy + consistent error envelope
(Silen ch06 / book ch8.1.2.7, 8.1.2.11).

Principles shown:

- Business logic raises ITS OWN errors, never ``fastapi.HTTPException``. The
  dependency arrow points web -> domain only. If the core imported the web
  framework you could not swap REST for gRPC/GraphQL without rewriting it.
- One base ``ApiError`` carries the HTTP status, a stable machine ``code``
  (used as a metrics label and for client-side branching), a human message,
  and the original ``cause``. Every concrete error subclasses it.
- One error envelope shape across the whole system, so clients write one
  parser. ``stack_trace`` is included ONLY outside production: a stack trace
  in a prod response hands attackers your internals.

Run: python errors.py
"""

from __future__ import annotations

import os
import traceback
from dataclasses import dataclass
from typing import Final


@dataclass(frozen=True, slots=True)
class HttpStatus:
    """The HTTP status code and its text always travel together. Grouping them
    keeps ``ApiError`` below the argument-count threshold and prevents a code
    being paired with the wrong text."""

    code: int
    text: str


class ApiError(Exception):
    """Base for every error the service may surface to a client."""

    def __init__(
        self,
        *,
        status: HttpStatus,
        message: str,
        code: str,
        description: str | None = None,
        cause: Exception | None = None,
    ) -> None:
        super().__init__(message)
        self.status: Final = status
        self.message: Final = message
        # Stable identifier: safe to use as a counter label and to branch on
        # client-side. Unlike the message, it must not change wording over time.
        self.code: Final = code
        self.description: Final = description
        self.cause: Final = cause


class EntityNotFoundError(ApiError):
    def __init__(self, entity_name: str, entity_id: str) -> None:
        super().__init__(
            status=HttpStatus(404, "Not Found"),
            message=f"{entity_name} with id {entity_id} not found",
            code="EntityNotFound",
        )


class DatabaseError(ApiError):
    def __init__(self, cause: Exception) -> None:
        super().__init__(
            status=HttpStatus(503, "Service Unavailable"),  # transient -> retry
            message="Database operation failed",
            code="DatabaseError",
            cause=cause,
        )


def stack_trace_of(error: Exception | None) -> str | None:
    """Return a trace only outside production, None otherwise."""
    if error is None or os.environ.get("ENV") == "production":
        return None
    return "".join(traceback.format_exception(error))


def to_error_envelope(error: ApiError) -> dict[str, object | None]:
    """The single envelope shape every client parses. Keys are camelCase
    because the envelope is part of the public wire contract."""
    return {
        "statusCode": error.status.code,
        "statusText": error.status.text,
        "errorCode": error.code,
        "errorMessage": error.message,
        "errorDescription": error.description,
        "stackTrace": stack_trace_of(error.cause),
    }


if __name__ == "__main__":
    os.environ["ENV"] = "production"
    print(to_error_envelope(EntityNotFoundError("Sales item", "10")))
    # cause is preserved for logging even though it never reaches the client:
    err = DatabaseError(ValueError("connection refused"))
    print(to_error_envelope(err))
