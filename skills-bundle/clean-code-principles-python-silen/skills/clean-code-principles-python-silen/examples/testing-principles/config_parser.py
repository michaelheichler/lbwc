"""System under test for the testing-principles examples.

Demonstrates (as the *implementation* side):
- Unit testing principle: one public method (`try_parse`) backed by private
  helpers (`_parse_line`) that are tested *indirectly*.
- Mocking seams: the parser depends on an injected `LineReader` Protocol, so a
  unit test can substitute a stub/mock instead of touching the filesystem.
- Failure scenarios as named exceptions (`ParseError`) rather than returning
  None, so tests can assert on a concrete type.

The matching tests live in `test_config_parser.py`.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


class LineReader(Protocol):
    """Dependency seam: anything that yields config lines.

    A unit test injects a fake, an integration test injects a real file reader.
    """

    def read_lines(self, source: str) -> list[str]: ...


@dataclass(frozen=True, slots=True)
class Configuration:
    """Immutable result object. Frozen so tests can compare by value."""

    properties: dict[str, str]

    def get(self, name: str) -> str | None:
        return self.properties.get(name)


class ConfigParser:
    """Parses ``name=value`` lines into a Configuration.

    `try_parse` is the single public method (one feature). `_parse_line` is a
    private helper exercised only through `try_parse` -- never tested directly.
    """

    class ParseError(ValueError):
        """Raised when a line is not a valid ``name=value`` pair."""

    def __init__(self, reader: LineReader) -> None:
        self._reader = reader

    def try_parse(self, source: str) -> Configuration:
        lines = self._reader.read_lines(source)
        properties = dict(self._parse_line(line) for line in lines if line.strip())
        return Configuration(properties)

    def _parse_line(self, line: str) -> tuple[str, str]:
        name, sep, value = line.partition("=")
        if not sep or not name.strip():
            raise self.ParseError(f"Invalid config line: {line!r}")
        return name.strip(), value.strip()
