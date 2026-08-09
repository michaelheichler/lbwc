"""Thread Safety Principle: guard shared mutable state with a lock.

`counter += 1` is read-modify-write: three bytecodes with a window in which
the GIL can switch threads, so concurrent increments lose updates. The lock
makes the whole sequence atomic.

This file contrasts the broken version with a corrected one and proves the
difference with a stress test. It also shows the naming convention from the
chapter: a class whose contract is "safe to share across threads" says so in
its name (ThreadSafeCounter), because thread safety cannot be assumed.

See also: fluent-python ch19 (GIL: why += is not atomic).
"""

from __future__ import annotations

import threading
import time
from concurrent.futures import ThreadPoolExecutor


# --- bad: unsynchronised shared counter -------------------------------------
class RacyCounter:
    def __init__(self) -> None:
        self._count = 0

    def increment(self) -> None:
        # Read-modify-write with no lock: updates are silently lost under load.
        # The bug is in `self._count += 1` too, here we spell out the window
        # (read -> local -> write) and yield inside it with time.sleep(0) so
        # the lost-update race surfaces deterministically instead of depending
        # on the GIL switch interval. In production the yield is implicit: any
        # I/O, allocation, or attribute access between read and write can
        # release the GIL and let another thread clobber the value.
        current = self._count
        time.sleep(0)  # hand the GIL to another thread mid-window
        self._count = current + 1

    @property
    def value(self) -> int:
        return self._count


# --- good: lock makes the critical section atomic ---------------------------
class ThreadSafeCounter:
    """Name advertises the contract: this object is safe to share."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._count = 0

    def increment(self) -> None:
        with self._lock:  # acquire/release even if the body raises
            self._count += 1

    @property
    def value(self) -> int:
        with self._lock:  # reads need the lock too, to see a consistent value
            return self._count


def _hammer(increment: object, times: int) -> None:
    inc = increment  # bound method passed in
    for _ in range(times):
        inc()  # type: ignore[operator]


def _run(counter: RacyCounter | ThreadSafeCounter, *, threads: int, per: int) -> int:
    with ThreadPoolExecutor(max_workers=threads) as pool:
        for _ in range(threads):
            pool.submit(_hammer, counter.increment, per)
    return counter.value


if __name__ == "__main__":
    threads, per = 4, 20_000
    expected = threads * per
    racy = _run(RacyCounter(), threads=threads, per=per)
    safe = _run(ThreadSafeCounter(), threads=threads, per=per)
    print(f"expected={expected} racy={racy} safe={safe}")
    # racy < expected: lost updates can only undercount, never overcount.
    assert racy < expected, "the unlocked counter must demonstrably lose updates"
    assert safe == expected, "locked counter must never lose an update"
