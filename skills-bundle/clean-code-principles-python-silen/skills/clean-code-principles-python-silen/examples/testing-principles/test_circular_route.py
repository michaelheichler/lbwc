"""Tests for CircularRoute. Demonstrates edge-case + property-based testing.

Principles shown:
- List the scenarios first, then test the SPECIALIZED ones (empty, single,
  wrap-around) before the general one -- the TDD ordering from the chapter.
- The wrap-around case (last -> first) is the off-by-one trap, it gets its own
  named test, not a buried assertion.
- Property-based test (Hypothesis) asserts an invariant that holds for ANY
  route, catching inputs you never hand-picked. Skipped cleanly if Hypothesis
  is not installed, so the file still runs under plain pytest.

Run: pytest test_circular_route.py
"""

from __future__ import annotations

import pytest
from circular_route import CircularRoute


def test_init__when_no_stops__raises_value_error() -> None:
    # Failure scenario (most specialized -> tested first)
    with pytest.raises(ValueError, match="at least one stop"):
        CircularRoute([])


def test_next_stop__when_single_stop__returns_itself() -> None:
    # Edge case: a ring of one always loops back to itself.
    route = CircularRoute(["a"])
    assert route.next_stop("a") == "a"


def test_next_stop__when_middle_stop__returns_following_stop() -> None:
    # Happy path
    route = CircularRoute(["a", "b", "c"])
    assert route.next_stop("b") == "c"


def test_next_stop__when_last_stop__wraps_to_first() -> None:
    # The off-by-one trap gets its own named test.
    route = CircularRoute(["a", "b", "c"])
    assert route.next_stop("c") == "a"


def test_next_stop__when_stop_not_on_route__raises_value_error() -> None:
    route = CircularRoute(["a", "b"])
    with pytest.raises(ValueError, match="not on this route"):
        route.next_stop("z")


def test_init__copies_input__caller_mutation_does_not_leak() -> None:
    # Defensive-copy edge case: mutating the caller's list must not affect us.
    stops = ["a", "b"]
    route = CircularRoute(stops)
    stops.append("c")
    assert route.next_stop("b") == "a"  # still a 2-stop ring


# --- Property-based: an invariant true for EVERY non-empty route -------------
hypothesis = pytest.importorskip("hypothesis")
from hypothesis import given  # noqa: E402
from hypothesis import strategies as st  # noqa: E402


@given(st.lists(st.integers(), min_size=1, unique=True))
def test_next_stop__applied_n_times_returns_to_start(stops: list[int]) -> None:
    # Property: walking len(stops) steps from any stop returns to that stop.
    route = CircularRoute(stops)
    current = stops[0]
    for _ in range(len(stops)):
        current = route.next_stop(current)
    assert current == stops[0]
