"""Off-by-one avoidance + appropriate data structures + optimization
(Silen ch03 / book ch5.10, 5.13, 5.14).

Off-by-one:
- Iterate the collection directly. Never ``range(len(...))`` with a hand-rolled
  comparison.
- Use negative indexing/slices (``values[-1]``, ``values[:-1]``) instead of
  ``values[len(values) - 1]`` arithmetic that invites +/-1 mistakes.

Data structures (pick by access pattern, not habit):
- membership test -> ``set`` (O(1)) not ``list`` (O(n))
- both-ends queue -> ``collections.deque`` (O(1)) not ``list.pop(0)`` (O(n))
- counting -> ``collections.Counter`` (no KeyError)

Optimization:
- generator expression instead of a list when you only stream values once
- ``functools.cache`` for an expensive pure function

Run: python off_by_one_and_structures.py
"""

from __future__ import annotations

from collections import Counter, deque
from collections.abc import Iterator
from functools import cache


# --- Off-by-one: direct iteration + negative indexing -----------------------
def last_and_rest(values: list[int]) -> tuple[int, list[int]]:
    # ✗ BAD: values[len(values) - 1] and values[:len(values) - 1]
    # ✓ GOOD: negative indices can't drift off the end.
    return values[-1], values[:-1]


def total(values: list[int]) -> int:
    running_total = 0
    for value in values:  # not range(len(values))
        running_total += value
    return running_total


# --- Right structure for membership: set, not list --------------------------
def has_target(values: set[int], target: int) -> bool:
    return target in values  # O(1) hash lookup


# --- deque for FIFO: popleft is O(1) ---------------------------------------
def drain_fifo(items: list[str]) -> list[str]:
    queue: deque[str] = deque(items)
    drained: list[str] = []
    while queue:
        drained.append(queue.popleft())
    return drained


# --- Counter for tallies: missing key yields 0, not KeyError ---------------
def word_frequencies(words: list[str]) -> Counter[str]:
    return Counter(words)


# --- Generator: stream, don't materialize 20k items -------------------------
def squares(stop: int) -> Iterator[int]:
    return (value * value for value in range(stop))


# --- cache: expensive pure function, memoized -------------------------------
@cache
def fib(n: int) -> int:
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)


if __name__ == "__main__":
    print("last_and_rest:", last_and_rest([10, 20, 30]))
    print("total:", total([1, 2, 3, 4]))
    print("has_target:", has_target({1, 2, 3}, 2))
    print("drain_fifo:", drain_fifo(["a", "b", "c"]))
    print("frequencies:", dict(word_frequencies(["a", "b", "a"])))
    print("squares:", list(squares(5)))
    print("fib(30):", fib(30))
