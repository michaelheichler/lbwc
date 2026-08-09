"""Cross-cutting concerns as general-purpose decorators
(Silen ch06 / book ch8.1.2.11).

Principles shown:

- Audit logging, metrics, and authorization are CROSS-CUTTING. Inlining them in
  every handler buries the business call in boilerplate and guarantees drift.
- Each decorator is GENERAL-PURPOSE (knows nothing about sales items) and
  reusable across every endpoint. ``functools.wraps`` preserves the wrapped
  function's identity so framework introspection (FastAPI signature parsing,
  OpenAPI) still works.
- They read the request from a documented place rather than guessing arg
  positions, so they compose in any order.

See fluent-python ch09 for the closure/decorator mechanics this relies on.

Run: python cross_cutting_decorators.py
"""

from __future__ import annotations

from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from functools import wraps
from typing import Any


@dataclass
class RequestInfo:
    """The slice of an HTTP request that cross-cutting code needs. Passing this
    instead of a framework request object keeps decorators framework-neutral."""

    method: str
    path: str
    client_host: str
    roles: frozenset[str] = frozenset()


@dataclass
class Counter:
    """Stand-in for a real metrics counter (e.g. prometheus_client.Counter)."""

    samples: list[tuple[int, Mapping[str, str]]] = field(default_factory=list)

    def increment(self, amount: int, labels: Mapping[str, str]) -> None:
        self.samples.append((amount, labels))


def _request_of(args: tuple[Any, ...], kwargs: dict[str, Any]) -> RequestInfo:
    info = kwargs.get("request")
    if info is None:
        info = next((a for a in args if isinstance(a, RequestInfo)), None)
    if info is None:
        raise LookupError("handler must receive a RequestInfo as 'request'")
    return info


def audit_log[**P, R](handler: Callable[P, R]) -> Callable[P, R]:
    @wraps(handler)
    def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
        info = _request_of(args, kwargs)
        # Real code writes to the audit sink, print stands in here.
        print(f"AUDIT {info.method} {info.path} from {info.client_host}")
        return handler(*args, **kwargs)

    return wrapper


def increment_counter[**P, R](
    counter: Counter,
) -> Callable[[Callable[P, R]], Callable[P, R]]:
    def decorate(handler: Callable[P, R]) -> Callable[P, R]:
        @wraps(handler)
        def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
            info = _request_of(args, kwargs)
            counter.increment(1, {"endpoint": f"{info.method} {info.path}"})
            return handler(*args, **kwargs)

        return wrapper

    return decorate


def allow_for_roles[**P, R](
    required: set[str],
) -> Callable[[Callable[P, R]], Callable[P, R]]:
    def decorate(handler: Callable[P, R]) -> Callable[P, R]:
        @wraps(handler)
        def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
            info = _request_of(args, kwargs)
            if not (required & info.roles):
                raise PermissionError(f"requires one of {sorted(required)}")
            return handler(*args, **kwargs)

        return wrapper

    return decorate


if __name__ == "__main__":
    attempts = Counter()

    @allow_for_roles({"admin"})
    @audit_log
    @increment_counter(attempts)
    def create_sales_item(name: str, *, request: RequestInfo) -> str:
        return f"created {name} via {request.method} {request.path}"

    req = RequestInfo("POST", "/sales-items", "10.0.0.1", frozenset({"admin"}))
    print(create_sales_item("Widget", request=req))
    print("metric samples:", attempts.samples)

    denied = RequestInfo("POST", "/sales-items", "10.0.0.1", frozenset({"guest"}))
    try:
        create_sales_item("Widget", request=denied)
    except PermissionError as exc:
        print("blocked:", exc)
