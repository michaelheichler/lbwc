"""Unit tests for ConfigParser. Demonstrates the unit-testing principles.

Principles shown:
- Test only the PUBLIC method (`try_parse`), the private `_parse_line` is
  covered indirectly.
- Naming: ``test_<method>__<scenario>`` so a failure name pinpoints the case.
- Arrange-Act-Assert (Given/When/Then) structure, one logical assert per test.
- Isolation via a stub injected through the `LineReader` seam -- no filesystem.
- Cover happy path, failure scenario, and edge cases (empty / blank lines).
- Parametrization for table-style edge cases instead of copy-pasted tests.

Run: pytest test_config_parser.py
"""

from __future__ import annotations

import pytest
from config_parser import ConfigParser, Configuration, LineReader


class StubReader(LineReader):
    """Hand-written stub: returns canned lines, records nothing.

    A stub is enough here because the test asserts on the RESULT, not on how the
    reader was called. Reach for unittest.mock only when you must verify calls.
    """

    def __init__(self, lines: list[str]) -> None:
        self._lines = lines

    def read_lines(self, source: str) -> list[str]:
        return self._lines


def make_parser(lines: list[str]) -> ConfigParser:
    return ConfigParser(StubReader(lines))


def test_try_parse__when_single_property__returns_value() -> None:
    # Given
    parser = make_parser(["host=localhost"])
    # When
    config = parser.try_parse("ignored")
    # Then
    assert config.get("host") == "localhost"


def test_try_parse__when_multiple_properties__returns_all() -> None:
    # Given
    parser = make_parser(["host=localhost", "port=8080"])
    # When
    config = parser.try_parse("ignored")
    # Then
    assert config == Configuration({"host": "localhost", "port": "8080"})


def test_try_parse__when_blank_lines_present__skips_them() -> None:
    # Given (edge case: empty + whitespace-only lines must be ignored)
    parser = make_parser(["host=localhost", "", "   "])
    # When
    config = parser.try_parse("ignored")
    # Then
    assert config.properties == {"host": "localhost"}


def test_try_parse__when_line_has_no_equals__raises_parse_error() -> None:
    # Given (failure scenario)
    parser = make_parser(["not-a-pair"])
    # When / Then -- assert on the concrete exception TYPE, not just "raises".
    with pytest.raises(ConfigParser.ParseError, match="Invalid config line"):
        parser.try_parse("ignored")


@pytest.mark.parametrize(
    "line",
    [
        pytest.param("=value", id="empty-name"),
        pytest.param("   =value", id="whitespace-name"),
    ],
)
def test_try_parse__when_name_is_blank__raises_parse_error(line: str) -> None:
    # Given (edge cases gathered in one parametrized test, not duplicated)
    parser = make_parser([line])
    # When / Then
    with pytest.raises(ConfigParser.ParseError):
        parser.try_parse("ignored")


def test_try_parse__when_value_contains_equals__keeps_full_value() -> None:
    # Given (edge case: only the first '=' splits name from value)
    parser = make_parser(["dsn=user=admin;pwd=secret"])
    # When
    config = parser.try_parse("ignored")
    # Then
    assert config.get("dsn") == "user=admin;pwd=secret"
