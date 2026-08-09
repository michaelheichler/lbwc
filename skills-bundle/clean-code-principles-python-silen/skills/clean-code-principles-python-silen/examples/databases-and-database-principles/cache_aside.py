"""Cache-aside with a key-value store (Redis-style), with TTL expiry.

Principles shown:
- Use a key-value store as a read-through cache in front of a slower store.
- ALWAYS set a TTL on cached entries so stale data self-heals, an unbounded
  cache is a memory leak and a staleness bug waiting to happen.
- Cache the value, not the connection: serialize to JSON, store bytes/str.

This file uses an in-memory fake that mimics the Redis API (get/set with ex=)
so it runs with no server. Swap `FakeKeyValueStore` for `redis.Redis` and the
logic is unchanged. See fluent-python ch08 for the Protocol typing here.

Run: python cache_aside.py
"""

from __future__ import annotations

import json
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Protocol


class KeyValueStore(Protocol):
    """Minimal slice of the Redis API we depend on."""

    def get(self, key: str) -> str | None: ...
    def set(self, key: str, value: str, ex: int | None = None) -> None: ...


@dataclass
class FakeKeyValueStore:
    """In-memory stand-in for Redis with TTL support, for tests/demos."""

    _data: dict[str, tuple[str, float | None]] = field(default_factory=dict)

    def get(self, key: str) -> str | None:
        entry = self._data.get(key)
        if entry is None:
            return None
        value, expires_at = entry
        if expires_at is not None and time.monotonic() >= expires_at:
            del self._data[key]  # lazily evict expired entry
            return None
        return value

    def set(self, key: str, value: str, ex: int | None = None) -> None:
        expires_at = None if ex is None else time.monotonic() + ex
        self._data[key] = (value, expires_at)


def get_cached_json[T](
    cache: KeyValueStore,
    key: str,
    loader: Callable[[], T],
    ttl_seconds: int,
) -> T:
    """Read-through: return the cached value, else load, cache with TTL, return.

    `ttl_seconds` is required (not defaulted to None) so callers cannot
    accidentally create entries that never expire.
    """
    cached = cache.get(key)
    if cached is not None:
        return json.loads(cached)
    value = loader()
    cache.set(key, json.dumps(value), ex=ttl_seconds)
    return value


def _demo() -> None:
    cache = FakeKeyValueStore()
    db_hits = 0

    def slow_query() -> dict[str, int]:
        nonlocal db_hits
        db_hits += 1
        return {"count": 42}

    first = get_cached_json(cache, "sales:count", slow_query, ttl_seconds=60)
    second = get_cached_json(cache, "sales:count", slow_query, ttl_seconds=60)
    assert first == second == {"count": 42}
    assert db_hits == 1, "second call must hit the cache, not the DB"

    print("cache_aside OK", first, "db_hits:", db_hits)


if __name__ == "__main__":
    _demo()
