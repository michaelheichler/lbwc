"""Publish/Subscribe Shared State Change: signal with a Condition, not sleep.

A consumer that polls `if queue: ...; time.sleep(0.1)` either burns CPU
(sleep too short) or adds latency (sleep too long). A Condition lets the
producer notify waiters the instant an item arrives, the consumer blocks
with zero CPU until then.

Two versions:
  - ConditionQueue: the chapter's hand-rolled Condition pattern, shown so you
    understand the mechanics (wait_for re-checks the predicate, immune to
    spurious wakeups and lost notifications).
  - The __main__ note: in real code prefer queue.Queue, which already
    implements exactly this with a Condition internally.

See also: fluent-python ch19 (threading primitives), stdlib queue.Queue.
"""

from __future__ import annotations

import threading
from collections import deque
from concurrent.futures import ThreadPoolExecutor


class ConditionQueue[T]:
    """Bounded-unaware FIFO that signals consumers via a Condition."""

    def __init__(self) -> None:
        # The Condition owns its own RLock, everything mutating _items must
        # run while holding it, so we never need a second lock.
        self._not_empty = threading.Condition()
        self._items: deque[T] = deque()
        self._closed = False

    def put(self, item: T) -> None:
        with self._not_empty:
            self._items.append(item)
            self._not_empty.notify()  # wake exactly one waiting consumer

    def close(self) -> None:
        with self._not_empty:
            self._closed = True
            self._not_empty.notify_all()  # let every waiter re-check and exit

    def get(self) -> T | None:
        with self._not_empty:
            # wait_for releases the lock while blocked and re-acquires it on
            # wake, then re-tests the predicate -> no lost/spurious wakeups.
            self._not_empty.wait_for(lambda: self._items or self._closed)
            if self._items:
                return self._items.popleft()
            return None  # queue closed and drained: signal end-of-stream


def _producer(queue: ConditionQueue[int], count: int) -> None:
    for i in range(count):
        queue.put(i)
    queue.close()


def _consumer(queue: ConditionQueue[int]) -> int:
    total = 0
    while (item := queue.get()) is not None:
        total += item
    return total


if __name__ == "__main__":
    queue: ConditionQueue[int] = ConditionQueue()
    with ThreadPoolExecutor(max_workers=2) as pool:
        pool.submit(_producer, queue, 100)
        result = pool.submit(_consumer, queue)
    print("sum:", result.result())  # 4950

    # In production: `import queue; q = queue.Queue()` gives you this pattern,
    # tested and bounded, for free. Hand-roll a Condition only when the
    # stdlib queue does not fit (custom predicate, multi-condition waits).
