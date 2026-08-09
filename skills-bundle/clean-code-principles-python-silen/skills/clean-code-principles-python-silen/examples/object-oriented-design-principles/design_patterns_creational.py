"""Creational design patterns, Pythonically (Silen ch02 / book ch4.13.1).

- Abstract factory: program against a factory PROTOCOL so the concrete factory
  (and thus the family of objects it builds) is chosen by DI / config. The
  factory is the *one* place an extensive ``match`` over a type enum is allowed.
- Static factory method: a private constructor plus named class-methods. Solves
  Python's "only one ``__init__``" limit and lets a constructor signal failure
  (return ``None`` / raise), which ``__init__`` cannot do cleanly. A ``try_``
  prefix names the raising variant.
- Singleton: in Python a module-level instance IS a singleton. Prefer that (or
  a DI container's singleton provider) over reinventing ``__new__`` tricks.

Run: python design_patterns_creational.py
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from enum import Enum, auto
from typing import Protocol, Self


# ============================================================================
# ABSTRACT FACTORY
# ============================================================================
class ConfigFormat(Enum):
    JSON = auto()
    YAML = auto()


class ConfigParser(Protocol):
    def parse(self, raw: str) -> dict[str, str]: ...


class JsonConfigParser:
    def parse(self, raw: str) -> dict[str, str]:
        return json.loads(raw)


class YamlConfigParser:
    def parse(self, raw: str) -> dict[str, str]:
        return dict(line.split(": ", 1) for line in raw.splitlines() if line)


class ConfigParserFactory(Protocol):
    def create(self, fmt: ConfigFormat) -> ConfigParser: ...


class ConfigParserFactoryImpl:
    def create(self, fmt: ConfigFormat) -> ConfigParser:
        match fmt:  # factories may hold the match, business logic may not
            case ConfigFormat.JSON:
                return JsonConfigParser()
            case ConfigFormat.YAML:
                return YamlConfigParser()
            case _:  # safeguard a new enum member that was forgotten here
                raise ValueError(f"unsupported format: {fmt}")


# ============================================================================
# STATIC FACTORY METHOD: named constructors + a failable creator.
# ============================================================================
@dataclass(frozen=True, slots=True)
class HttpUrl:
    scheme: str
    host: str
    port: int

    @classmethod
    def try_create(cls, scheme: str, host: str, port: int) -> Self:
        # Validation a plain __init__ could not signal cleanly.
        if scheme not in {"http", "https"}:
            raise ValueError(f"bad scheme: {scheme}")
        if not 1 <= port <= 65535:
            raise ValueError(f"bad port: {port}")
        return cls(scheme, host, port)

    @classmethod
    def localhost(cls, port: int) -> Self:  # descriptive named constructor
        return cls.try_create("http", "localhost", port)


def main() -> None:
    factory: ConfigParserFactory = ConfigParserFactoryImpl()
    parser = factory.create(ConfigFormat.YAML)
    print("factory:", parser.parse("host: localhost\nport: 5432"))

    print("named ctor:", HttpUrl.localhost(8080))
    try:
        HttpUrl.try_create("ftp", "x", 21)
    except ValueError as err:
        print("rejected:", err)


if __name__ == "__main__":
    main()
