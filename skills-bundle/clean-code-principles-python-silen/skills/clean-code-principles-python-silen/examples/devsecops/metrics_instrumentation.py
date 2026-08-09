"""SLI metric instrumentation (DevSecOps: Monitor / Metrics).

Demonstrates principles:
- Pick the right instrument type: Counter (monotonic events) vs Gauge
  (current value, up/down) vs Histogram (latency distribution for quantiles).
- Use BOUNDED, low-cardinality labels (error class, route template). Never put
  user ids, request ids, or raw paths in labels: each combo is a new series.
- Cover the four golden SLI categories: errors, latency, throughput, saturation.
- Define metric names once as module constants, instrument with a context
  manager / decorator, not copy-pasted try/finally.

This mirrors prometheus_client's API with a tiny local shim so the file runs
without the dependency. In production, replace _Counter/_Histogram/_Gauge with:
    from prometheus_client import Counter, Histogram, Gauge

Run:  python metrics_instrumentation.py
"""

from __future__ import annotations

import contextlib
import functools
import time
from collections import defaultdict
from collections.abc import Callable
from typing import ParamSpec, TypeVar

P = ParamSpec("P")
R = TypeVar("R")


# --- Minimal Prometheus-style shims (replace with prometheus_client) ---------
class _Counter:
    def __init__(self, name: str, doc: str, labelnames: tuple[str, ...] = ()) -> None:
        self.name, self.doc, self.labelnames = name, doc, labelnames
        self._values: dict[tuple[str, ...], float] = defaultdict(float)

    def labels(self, *values: str) -> _Bound:
        return _Bound(self._values, values)

    def inc(self, amount: float = 1.0) -> None:
        self._values[()] += amount

    def snapshot(self) -> dict[tuple[str, ...], float]:
        """Public read of the current series (the real client uses /metrics)."""
        return dict(self._values)


class _Gauge(_Counter):
    def dec(self, amount: float = 1.0) -> None:
        self._values[()] -= amount

    def set(self, value: float) -> None:
        self._values[()] = value


class _Histogram(_Counter):
    def observe(self, value: float) -> None:
        self._values[()] += value


class _Bound:
    def __init__(self, store: dict[tuple[str, ...], float], key: tuple[str, ...]) -> None:
        self._store, self._key = store, key

    def inc(self, amount: float = 1.0) -> None:
        self._store[self._key] += amount

    def observe(self, value: float) -> None:
        self._store[self._key] += value


# --- Metric definitions: declared once, named consistently -------------------
# Counter: throughput + error rate. Label is the route TEMPLATE, not the path.
REQUESTS = _Counter("http_requests_total", "Requests handled", ("method", "route"))
# Counter: error rate, labeled by a bounded error CLASS (golden signal: errors).
ERRORS = _Counter("request_errors_total", "Request errors", ("route", "error_class"))
# Histogram: latency distribution -> drives p50/p95/p99 SLOs (golden: latency).
LATENCY = _Histogram("request_duration_seconds", "Request duration", ("route",))
# Gauge: saturation, in-flight work right now (golden: saturation).
IN_FLIGHT = _Gauge("requests_in_flight", "Concurrent requests being served")


def instrument(route: str, method: str = "GET") -> Callable[[Callable[P, R]], Callable[P, R]]:
    """Decorator that records throughput, latency, errors, and saturation.

    `route` is a low-cardinality template like "/users/{id}", NEVER the live
    path "/users/8e1f...": the latter explodes Prometheus series cardinality.
    """

    def decorate(func: Callable[P, R]) -> Callable[P, R]:
        @functools.wraps(func)
        def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
            REQUESTS.labels(method, route).inc()
            IN_FLIGHT.inc()
            start = time.perf_counter()
            try:
                return func(*args, **kwargs)
            except Exception as exc:
                # Label by the EXCEPTION TYPE name (bounded set), not its message.
                ERRORS.labels(route, type(exc).__name__).inc()
                raise
            finally:
                LATENCY.labels(route).observe(time.perf_counter() - start)
                IN_FLIGHT.dec()

        return wrapper

    return decorate


@instrument(route="/widgets/{id}")
def get_widget(widget_id: int) -> dict[str, int]:
    if widget_id < 0:
        raise ValueError("negative id")
    return {"id": widget_id}


def main() -> None:
    get_widget(1)
    with contextlib.suppress(ValueError):
        get_widget(-1)
    print("requests:", REQUESTS.snapshot())
    print("errors:  ", ERRORS.snapshot())
    print("latency: ", LATENCY.snapshot())
    print("in_flight:", IN_FLIGHT.snapshot())


if __name__ == "__main__":
    main()
