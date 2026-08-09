"""System under test for TDD / edge-case / property-based examples.

`CircularRoute.next_stop` is the kind of small, index-driven function where TDD
shines: the modulo wrap is exactly where off-by-one bugs hide. The chapter's
"test the last loop counter / wrap-around" guidance maps directly here.

Tests live in `test_circular_route.py`.
"""

from __future__ import annotations

from typing import TypeVar

T = TypeVar("T")


class CircularRoute[T]:
    """An ordered ring of stops, `next_stop` wraps from the last back to first."""

    def __init__(self, stops: list[T]) -> None:
        if not stops:
            raise ValueError("route must have at least one stop")
        self._stops = stops.copy()  # defensive copy: caller can't mutate us

    def next_stop(self, current: T) -> T:
        try:
            index = self._stops.index(current)
        except ValueError as error:
            raise ValueError("stop is not on this route") from error
        return self._stops[(index + 1) % len(self._stops)]
