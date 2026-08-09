"""Avoid shared mutable state: the cheapest concurrency bug is the one you
never create.

The most reliable way to be thread-safe is to have nothing to synchronise:
each task owns its inputs, returns a result, and never mutates a shared
object. Then add locks only where sharing is genuinely required.

Contrast:
  ✗ workers append to one shared list (needs a lock, easy to forget)
  ✓ workers are pure functions, the pool collects returned values

See also: fluent-python ch06 (mutability/aliasing), ch20 (executor.map
returns results in order).
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass


@dataclass(frozen=True)  # immutable: safe to share by reference across threads
class PriceQuote:
    symbol: str
    cents: int


# --- bad: every worker mutates one shared list ------------------------------
def collect_shared(symbols: list[str]) -> list[PriceQuote]:
    results: list[PriceQuote] = []  # shared mutable state

    def work(symbol: str) -> None:
        # list.append happens to be GIL-protected today, but RELYING on that
        # is fragile: any compound update (sort-then-append, dedupe) races.
        results.append(PriceQuote(symbol, len(symbol) * 100))

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(work, symbols))  # order is nondeterministic
    return results


# --- good: pure worker returns a value, no shared mutable state -------------
def _quote(symbol: str) -> PriceQuote:
    return PriceQuote(symbol, len(symbol) * 100)  # touches only its argument


def collect_pure(symbols: list[str]) -> list[PriceQuote]:
    with ThreadPoolExecutor(max_workers=4) as pool:
        # map preserves input order and needs no lock: each call is isolated.
        return list(pool.map(_quote, symbols))


if __name__ == "__main__":
    symbols = ["AAPL", "MSFT", "GOOG", "AMZN"]
    print("pure (ordered, lock-free):", collect_pure(symbols))
