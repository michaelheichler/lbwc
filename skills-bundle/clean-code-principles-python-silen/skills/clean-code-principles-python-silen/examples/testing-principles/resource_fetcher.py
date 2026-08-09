"""System under test for mocking-at-the-boundary examples.

Demonstrates:
- Wrapping a 3rd-party dependency (`Transport`) behind your own seam so unit
  tests mock YOUR boundary, not the library's internals.
- Translating every dependency failure into one component-owned exception
  (`FetchError`) so callers handle a single, stable error type.
- BDD-style up-front error handling: connection failure, HTTP error, and decode
  failure are all considered, not just the happy path.

Tests live in `test_resource_fetcher.py`.
"""

from __future__ import annotations

from typing import Any, Protocol


class TransportError(Exception):
    """Stands in for any low-level transport failure (timeout, refused, 5xx)."""


class Response(Protocol):
    status_code: int

    def json(self) -> dict[str, Any]: ...


class Transport(Protocol):
    """The seam. A real impl wraps `requests`/`httpx`, tests inject a mock."""

    def get(self, url: str, *, timeout: float) -> Response: ...


class ResourceFetcher:
    """Fetches a JSON resource and returns it as a dict.

    All failure modes collapse into `FetchError`, so unit tests assert on one
    exception type regardless of which underlying thing broke.
    """

    class FetchError(Exception):
        """Raised when a resource cannot be fetched or decoded."""

    def __init__(self, transport: Transport, *, timeout: float = 30.0) -> None:
        self._transport = transport
        self._timeout = timeout

    def fetch(self, url: str) -> dict[str, Any]:
        try:
            response = self._transport.get(url, timeout=self._timeout)
        except TransportError as error:
            raise self.FetchError(f"transport failed for {url}") from error

        if response.status_code >= 400:
            raise self.FetchError(f"HTTP {response.status_code} for {url}")

        try:
            return response.json()
        except ValueError as error:
            raise self.FetchError(f"invalid JSON from {url}") from error
