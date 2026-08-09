"""Error/exception handling principle (Silen ch03 / book ch5.9).

Key rules demonstrated:

- Define a component base error (``DataExporterError``). Per-operation errors
  subclass it, so a caller can catch broad or narrow by the same hierarchy.
- Nest the operation's base error inside the class so the error name is
  inferable from the method name (``read_file`` -> ``FileReader.ReadError``).
- ``try_`` prefix marks any function that can raise/propagate an error, so the
  caller cannot forget a try/except just by reading the call site.
- Never catch ``BaseException``/``Exception`` except at a top-level boundary
  (main loop / request handler) where you log and exit or continue.
- Wrap a third-party error-raising call into a ``try_`` method that re-raises
  *your* error type, so callers depend on your hierarchy, not the library's.

Run: python error_handling.py
"""

from __future__ import annotations

import json
from typing import Any


class DataExporterError(Exception):
    """Base error for this software component. Catch this to catch all."""


class FileReader:
    class ReadError(DataExporterError):
        """Inferable from the ``try_read`` method name."""

    def __init__(self, files: dict[str, str]) -> None:
        self._files = files

    def try_read(self, path: str) -> str:
        try:
            return self._files[path]
        except KeyError as error:
            # Re-raise as our error type. The original is chained for debugging.
            raise self.ReadError(f"no such file: {path}") from error


class ConfigParser:
    class ParseError(DataExporterError):
        """Inferable from the ``try_parse`` method name."""

    def try_parse(self, config_string: str) -> dict[str, Any]:
        try:
            return json.loads(config_string)
        except json.JSONDecodeError as error:
            raise self.ParseError(str(error)) from error


class ConfigFetcher:
    """Propagates errors -> the method itself carries the ``try_`` prefix."""

    def __init__(self, reader: FileReader, parser: ConfigParser) -> None:
        self._reader = reader
        self._parser = parser

    def try_fetch(self, path: str) -> dict[str, Any]:
        # No try/except here: both calls can raise, so this method is named
        # try_fetch and lets the component base error propagate upward.
        config_string = self._reader.try_read(path)
        return self._parser.try_parse(config_string)


def initialize(fetcher: ConfigFetcher, path: str) -> dict[str, Any] | None:
    # Catch the component base error -> handles read AND parse failures, plus
    # any future error subclass, with one except block.
    try:
        return fetcher.try_fetch(path)
    except DataExporterError as error:
        print(f"init failed ({type(error).__name__}): {error}")
        return None


if __name__ == "__main__":
    reader = FileReader({"good.json": '{"port": 8080}', "bad.json": "{not json"})
    fetcher = ConfigFetcher(reader, ConfigParser())

    print("good:", initialize(fetcher, "good.json"))
    print("bad:", initialize(fetcher, "bad.json"))
    print("missing:", initialize(fetcher, "missing.json"))
