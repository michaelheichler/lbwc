"""Structural & behavioral design patterns, Pythonically (Silen ch02 / book
ch4.13.2-3).

Patterns that earn their keep in real Python services:

- Strategy : inject a behavior object, swap it to change behavior at runtime.
- Adapter  : wrap a foreign (3rd-party) object behind YOUR protocol so the core
             never imports the vendor type.
- Decorator: wrap an object in another implementing the same protocol to add
             cross-cutting behavior (logging, timing) without editing it,
             this is the open/closed principle in action.

Naming note (book ch4.9): do NOT bake the pattern name into the class. A
caching proxy data store is ``CachingDataStore``, not ``CachingProxyDataStore``.

Run: python design_patterns_structural.py
"""

from __future__ import annotations

import json
import time
from typing import Protocol


# ============================================================================
# STRATEGY: ConfigReader's behavior changes by swapping the parser it holds.
# ============================================================================
class ConfigParser(Protocol):
    def parse(self, raw: str) -> dict[str, str]: ...


class JsonConfigParser:
    def parse(self, raw: str) -> dict[str, str]:
        return json.loads(raw)


class IniConfigParser:
    def parse(self, raw: str) -> dict[str, str]:
        return dict(line.split("=", 1) for line in raw.splitlines() if line)


class ConfigReader:
    # Default strategy is JSON, pass another to change behavior, no subclassing.
    def __init__(self, parser: ConfigParser | None = None) -> None:
        self._parser = parser or JsonConfigParser()

    def read(self, raw: str) -> dict[str, str]:
        return self._parser.parse(raw)


# ============================================================================
# ADAPTER: a vendor "raw" message is wrapped behind our Message protocol so
# the business core depends on Message, never on the Kafka/Pulsar client type.
# ============================================================================
class Message(Protocol):
    def data(self) -> bytes: ...
    def length(self) -> int: ...


class _VendorRawMessage:  # stand-in for a 3rd-party library object we can't edit
    def __init__(self, payload: bytes) -> None:
        self.payload = payload


class KafkaMessage:
    def __init__(self, raw: _VendorRawMessage) -> None:
        self._raw = raw

    def data(self) -> bytes:
        return self._raw.payload

    def length(self) -> int:
        return len(self._raw.payload)


# ============================================================================
# DECORATOR: same protocol in, same protocol out, behavior augmented. Stack
# them: timing(logging(real)). No executor class is modified.
# ============================================================================
class StatementExecutor(Protocol):
    def execute(self, sql: str) -> int: ...


class RealStatementExecutor:
    def execute(self, sql: str) -> int:
        return len(sql)  # pretend rows affected


class LoggingStatementExecutor:
    def __init__(self, wrapped: StatementExecutor) -> None:
        self._wrapped = wrapped

    def execute(self, sql: str) -> int:
        print(f"[log] executing: {sql}")
        return self._wrapped.execute(sql)


class TimingStatementExecutor:
    def __init__(self, wrapped: StatementExecutor) -> None:
        self._wrapped = wrapped

    def execute(self, sql: str) -> int:
        start = time.perf_counter_ns()
        result = self._wrapped.execute(sql)
        print(f"[time] {(time.perf_counter_ns() - start)} ns")
        return result


def main() -> None:
    reader = ConfigReader(IniConfigParser())  # strategy swapped from default
    print("strategy:", reader.read("host=localhost\nport=5432"))

    msg: Message = KafkaMessage(_VendorRawMessage(b"hello"))
    print("adapter length:", msg.length())

    executor: StatementExecutor = TimingStatementExecutor(
        LoggingStatementExecutor(RealStatementExecutor())
    )
    print("decorator rows:", executor.execute("SELECT 1"))


if __name__ == "__main__":
    main()
