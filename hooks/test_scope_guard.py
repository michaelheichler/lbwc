"""PreToolUse hook: bars an engineer role from writing into the test directory, test-dev's territory."""
import re
import sys

from skill_gate import (
    _agent_identifier,
    _parse_pretool_input,
    _role_for_identifier,
    emit_pretool_denial,
)

ENGINEER_ROLES = {"coding-dijkstra", "python-engineer", "web-engineer"}
WRITE_TOOLS = ("Write", "Edit", "NotebookEdit")
TEST_PATH_PATTERN = re.compile(r"(^|/)tests?/")
TEST_FILENAME_PATTERN = re.compile(r"\.(test|spec)\.")


def _is_test_path(file_path: str) -> bool:
    if TEST_PATH_PATTERN.search(file_path):
        return True
    basename = file_path.rsplit("/", 1)[-1]
    return bool(TEST_FILENAME_PATTERN.search(basename))


def blocked() -> str:
    return ("The test directory belongs to your test-dev teammate. Hand the "
            "function off and let test-dev write the test, do not write it "
            "yourself.")


def verdict(stdin_text, cwd=None) -> "str | None":
    data, error = _parse_pretool_input(stdin_text)
    if error:
        return error
    assert data is not None
    tool_name = data.get("tool_name") or ""
    if tool_name not in WRITE_TOOLS:
        return None
    file_path = str((data.get("tool_input") or {}).get("file_path", ""))
    if not file_path or not _is_test_path(file_path):
        return None
    identifier = _agent_identifier(data)
    if not identifier:
        return None
    role = _role_for_identifier(identifier, cwd or data.get("cwd"))
    if role not in ENGINEER_ROLES:
        return None
    return blocked()


def main() -> None:
    reason = verdict(sys.stdin.read())
    if reason is None:
        sys.exit(0)
    emit_pretool_denial(reason)
    sys.exit(0)


if __name__ == "__main__":
    main()
