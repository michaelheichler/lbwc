"""PreToolUse hook: denies a teammate's first file write until it has done its required reading."""
import json
import os
import sys
import tempfile
import time

TEAM_ROLES = {
    "coding-dijkstra",
    "coding-dijkstra-critic",
    "python-engineer",
    "python-critic",
    "web-engineer",
    "web-code-critic",
    "test-dev",
}
PLAN_ROLES = {"lead", "architect", "lead-critic"}
WRITE_TOOLS = ("Write", "Edit", "NotebookEdit")
BUNDLE_MARKER = "skills-bundle"
ARCHITECTURE_FILENAME = "ARCHITECTURE.md"
STATE_TTL_SECONDS = 6 * 60 * 60

CANDIDATE_ID_PATHS = (
    ("agent_id",), ("agentId",), ("agent_type",), ("agentType",),
    ("subagent_type",), ("subagentType",), ("name",),
    ("tool_input", "subagent_type"), ("tool_input", "agent_type"),
    ("tool_input", "name"), ("tool_input", "agent_name"),
)
MALFORMED_PRETOOL_INPUT = "Hook error: malformed PreToolUse JSON input."


def _parse_pretool_input(stdin_text):
    try:
        data = json.loads(stdin_text)
    except json.JSONDecodeError:
        return None, MALFORMED_PRETOOL_INPUT
    if (not isinstance(data, dict)
            or not isinstance(data.get("tool_name"), str)
            or not data["tool_name"]
            or "tool_input" not in data
            or not isinstance(data["tool_input"], dict)):
        return None, MALFORMED_PRETOOL_INPUT
    return data, None


def emit_pretool_denial(reason) -> None:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))


def _dig(data, path):
    node = data
    for key in path:
        if not isinstance(node, dict):
            return None
        node = node.get(key)
    return node if isinstance(node, str) and node else None


def _agent_identifier(data) -> "str | None":
    for path in CANDIDATE_ID_PATHS:
        value = _dig(data, path)
        if value:
            return value
    return None


def _state_path(key):
    safe = "".join(char if char.isalnum() or char in "-_" else "_" for char in (key or "no-session"))
    return os.path.join(tempfile.gettempdir(), f"lbwc-skillgate-{safe}.json")


def _load_agent_state(key):
    try:
        with open(_state_path(key)) as state_file:
            state = json.load(state_file)
    except (OSError, ValueError):
        return {}
    if time.time() - state.get("updated", 0) > STATE_TTL_SECONDS:
        return {}
    return state.get("agents", {})


def _save_agent_state(key, agents):
    with open(_state_path(key), "w") as state_file:
        json.dump({"updated": time.time(), "agents": agents}, state_file)


def _mark_satisfied(key, identifier, requirement):
    agents = _load_agent_state(key)
    entry = dict(agents.get(identifier) or {})
    entry[requirement] = True
    agents[identifier] = entry
    _save_agent_state(key, agents)


def _has_satisfied(key, identifier, requirement):
    agents = _load_agent_state(key)
    return bool((agents.get(identifier) or {}).get(requirement))


def _find_project_root(start):
    current = os.path.abspath(start or os.getcwd())
    while True:
        if os.path.isdir(os.path.join(current, ".lbwc-planning")):
            return current
        parent = os.path.dirname(current)
        if parent == current:
            return None
        current = parent


def _manifest_entry_for_identifier(identifier, cwd) -> "dict | None":
    root = _find_project_root(cwd)
    if not root:
        return None
    manifest_path = os.path.join(root, ".lbwc-planning", ".agent-manifest.json")
    try:
        with open(manifest_path) as manifest_file:
            manifest = json.load(manifest_file)
    except (OSError, ValueError):
        return None
    entry = manifest.get("agents", {}).get(identifier)
    return entry if isinstance(entry, dict) else None


def _role_for_identifier(identifier, cwd) -> "str | None":
    entry = _manifest_entry_for_identifier(identifier, cwd)
    return entry.get("role") if entry else None


def _pair_id_for_identifier(identifier, cwd) -> "str | None":
    entry = _manifest_entry_for_identifier(identifier, cwd)
    return entry.get("pair_id") if entry else None


def _is_bundle_read(tool_name, tool_input):
    if tool_name == "Read":
        return BUNDLE_MARKER in str(tool_input.get("file_path", ""))
    if tool_name == "Glob":
        haystack = str(tool_input.get("pattern", "")) + str(tool_input.get("path", ""))
        return BUNDLE_MARKER in haystack
    return False


def _is_architecture_read(tool_name, tool_input):
    if tool_name != "Read":
        return False
    return os.path.basename(str(tool_input.get("file_path", ""))) == ARCHITECTURE_FILENAME


def blocked(requirement) -> str:
    if requirement == "architecture":
        return ("File writes are blocked until this planning agent reads "
                "ARCHITECTURE.md. Read the ARCHITECTURE.md file at the repo "
                "root, then retry this write.")
    return ("File writes are blocked until this teammate finishes its required "
            "reading. Read the SKILL.md files named in your 'Required reading "
            "first' section under the skills-bundle base, then retry this write.")


def _record_read(state_key, identifier, tool_name, tool_input):
    is_bundle_read = _is_bundle_read(tool_name, tool_input)
    is_architecture_read = _is_architecture_read(tool_name, tool_input)
    if is_bundle_read:
        _mark_satisfied(state_key, identifier, "bundle")
    if is_architecture_read:
        _mark_satisfied(state_key, identifier, "architecture")
    return is_bundle_read or is_architecture_read


def _required_reading(role) -> "str | None":
    if role in TEAM_ROLES:
        return "bundle"
    if role in PLAN_ROLES:
        return "architecture"
    return None


def verdict(stdin_text, cwd=None) -> "str | None":
    data, error = _parse_pretool_input(stdin_text)
    if error:
        return error
    assert data is not None
    identifier = _agent_identifier(data)
    if not identifier:
        return None
    state_key = data.get("session_id") or identifier
    tool_name = data.get("tool_name") or ""
    tool_input = data.get("tool_input") or {}

    if _record_read(state_key, identifier, tool_name, tool_input):
        return None
    if tool_name not in WRITE_TOOLS:
        return None

    role = _role_for_identifier(identifier, cwd or data.get("cwd"))
    requirement = _required_reading(role)
    if requirement is None or _has_satisfied(state_key, identifier, requirement):
        return None
    return blocked(requirement)


def main() -> None:
    reason = verdict(sys.stdin.read())
    if reason is None:
        sys.exit(0)
    emit_pretool_denial(reason)
    sys.exit(0)


if __name__ == "__main__":
    main()
