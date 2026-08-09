"""Avoid comments principle (Silen ch03 / book ch5.4).

Comments drift out of sync with code, so only the code is trustworthy. Each
technique below removes a comment by making the code say the same thing:

- rename a function so its name carries the doc, so a ``-> bool`` method becomes a
  predicate (``did_write``) so the bool's meaning needs no comment
- extract a named constant for a boolean expression (kills the inline note)
- replace a magic number with an IntEnum (self-describing exit codes)
- extract a well-named function instead of a "# now do X" comment

The one sanctioned exception is the public API of a *library*, where a
docstring feeds generated reference docs. Internal code relies on names,
type hints, and tests instead.

Run: python avoid_comments.py
"""

from __future__ import annotations

import sys
from enum import IntEnum


class MessageBuffer:
    """A bounded buffer. Method names replace would-be comments."""

    def __init__(self, max_length: int) -> None:
        self._messages: list[str] = []
        self._max_length = max_length

    # A predicate name answers "what does the bool mean?" without a comment --
    # instead of ``write(...) -> bool  # returns False if full, True if written``.
    def did_write(self, message: str) -> bool:
        # Extracted constant replaces a "# buffer has room" comment.
        buffer_has_room = len(self._messages) < self._max_length
        if buffer_has_room:
            self._messages.append(message)
        return buffer_has_room

    # Extract-function replaces a "# write everything that fits" block.
    def write_fitting(self, messages: list[str]) -> None:
        all_messages_fit = len(self._messages) + len(messages) <= self._max_length
        if all_messages_fit:
            self._write_all(messages)
        else:
            self._write_only_fitting(messages)

    def _write_all(self, messages: list[str]) -> None:
        self._messages.extend(messages)
        messages.clear()

    def _write_only_fitting(self, messages: list[str]) -> None:
        free_slot_count = self._max_length - len(self._messages)
        self._messages.extend(messages[:free_slot_count])
        del messages[:free_slot_count]


# Replace magic numbers (0 / 1) with a self-describing enum.
class ExitCode(IntEnum):
    SUCCESS = 0
    FAILURE = 1


def run_application(*, should_fail: bool) -> ExitCode:
    return ExitCode.FAILURE if should_fail else ExitCode.SUCCESS


if __name__ == "__main__":
    buffer = MessageBuffer(max_length=2)
    print("write 1:", buffer.did_write("a"))
    print("write 2:", buffer.did_write("b"))
    print("write 3 (full):", buffer.did_write("c"))

    overflow = ["x", "y", "z"]
    fresh = MessageBuffer(max_length=2)
    fresh.write_fitting(overflow)
    print("left over after write_fitting:", overflow)

    code = run_application(should_fail=False)
    print("exit code:", code, int(code))
    sys.exit(int(code))
