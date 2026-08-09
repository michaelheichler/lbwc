"""Unit tests for ResourceFetcher. Demonstrates mocking at the boundary.

Principles shown:
- Mock the SEAM you own (`Transport`), not the 3rd-party library deep internals.
- `unittest.mock.create_autospec` so the mock rejects calls that don't match the
  real signature -- a plain Mock() would silently pass a renamed method.
- `side_effect` to simulate each failure scenario.
- A `pytest` fixture removes setup duplication (the chapter's `__set_up`).
- A shared assertion helper checks the call contract once.
- Verify the timeout is actually passed -- a common silently-dropped kwarg.

Run: pytest test_resource_fetcher.py
"""

from __future__ import annotations

from typing import Any
from unittest.mock import Mock, create_autospec

import pytest
from resource_fetcher import ResourceFetcher, Response, Transport, TransportError

URL = "https://example.test/data"
PAYLOAD = {"id": 1, "name": "widget"}


@pytest.fixture
def transport() -> Mock:
    """Autospecced mock of the boundary -- signature-checked, no real network."""
    return create_autospec(Transport, instance=True)


def make_response(*, status_code: int = 200, json: dict[str, Any] | None = None) -> Mock:
    response = create_autospec(Response, instance=True)
    response.status_code = status_code
    response.json.return_value = {} if json is None else json
    return response


def assert_called_with_timeout(transport: Mock, *, timeout: float = 30.0) -> None:
    """One place that pins the call contract for every happy/sad path."""
    transport.get.assert_called_once_with(URL, timeout=timeout)


def test_fetch__when_response_ok__returns_payload(transport: Mock) -> None:
    # Given
    transport.get.return_value = make_response(json=PAYLOAD)
    fetcher = ResourceFetcher(transport)
    # When
    result = fetcher.fetch(URL)
    # Then
    assert result == PAYLOAD
    assert_called_with_timeout(transport)


def test_fetch__when_transport_raises__wraps_in_fetch_error(transport: Mock) -> None:
    # Given (connection failure scenario)
    transport.get.side_effect = TransportError("connection refused")
    fetcher = ResourceFetcher(transport)
    # When / Then -- the original cause is preserved via `raise ... from`.
    with pytest.raises(ResourceFetcher.FetchError) as exc_info:
        fetcher.fetch(URL)
    assert isinstance(exc_info.value.__cause__, TransportError)


def test_fetch__when_status_is_error__raises_fetch_error(transport: Mock) -> None:
    # Given (HTTP error scenario)
    transport.get.return_value = make_response(status_code=503)
    fetcher = ResourceFetcher(transport)
    # When / Then
    with pytest.raises(ResourceFetcher.FetchError, match="HTTP 503"):
        fetcher.fetch(URL)
    assert_called_with_timeout(transport)


def test_fetch__when_json_invalid__raises_fetch_error(transport: Mock) -> None:
    # Given (decode failure scenario)
    response = make_response()
    response.json.side_effect = ValueError("not json")
    transport.get.return_value = response
    fetcher = ResourceFetcher(transport)
    # When / Then
    with pytest.raises(ResourceFetcher.FetchError, match="invalid JSON"):
        fetcher.fetch(URL)


def test_fetch__uses_configured_timeout(transport: Mock) -> None:
    # Given (the timeout kwarg must reach the transport, not be dropped)
    transport.get.return_value = make_response(json=PAYLOAD)
    fetcher = ResourceFetcher(transport, timeout=5.0)
    # When
    fetcher.fetch(URL)
    # Then
    assert_called_with_timeout(transport, timeout=5.0)
