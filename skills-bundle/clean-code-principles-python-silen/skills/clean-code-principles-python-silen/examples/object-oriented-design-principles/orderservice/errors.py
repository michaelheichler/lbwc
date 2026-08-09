"""Domain error hierarchy (Silen ch02 / book ch4.6).

A single base error carries an HTTP status so the outer adapter (controller /
app) can map domain failures to responses uniformly, without the core knowing
anything about HTTP. Specific errors set the status in their constructor.
"""

from __future__ import annotations


class OrderServiceError(Exception):
    def __init__(
        self,
        status_code: int,
        message: str,
        cause: Exception | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.message = message
        self.cause = cause


class EntityNotFoundError(OrderServiceError):
    def __init__(self, entity_name: str, entity_id: int) -> None:
        super().__init__(404, f"{entity_name} with id {entity_id} not found")


class RepositoryError(OrderServiceError):
    def __init__(self, cause: Exception) -> None:
        super().__init__(500, "repository error", cause)
