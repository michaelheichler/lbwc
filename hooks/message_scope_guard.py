"""PreToolUse hook: a subagent's own final return to main isn't a tool call, so only its explicit mid-task SendMessage("main") calls are interceptable here."""
import sys

from skill_gate import (
    _agent_identifier,
    _pair_id_for_identifier,
    _parse_pretool_input,
    _role_for_identifier,
    emit_pretool_denial,
)

MAIN_RECIPIENT = "main"


def _is_critic_role(role: "str | None") -> bool:
    return bool(role) and role.endswith("-critic")


def blocked() -> str:
    return ("Only the critic reports to the main session. Message your teammates "
            "instead, and let the critic relay the trio's verdict.")


def verdict(stdin_text, cwd=None) -> "str | None":
    data, error = _parse_pretool_input(stdin_text)
    if error:
        return error
    assert data is not None
    if (data.get("tool_name") or "") != "SendMessage":
        return None
    recipient = str((data.get("tool_input") or {}).get("to", ""))
    if recipient != MAIN_RECIPIENT:
        return None
    identifier = _agent_identifier(data)
    if not identifier:
        return None
    role = _role_for_identifier(identifier, cwd or data.get("cwd"))
    if role is None or _is_critic_role(role):
        return None
    pair_id = _pair_id_for_identifier(identifier, cwd or data.get("cwd"))
    if not pair_id:
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
