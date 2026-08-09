#!/usr/bin/env bash
set -euo pipefail

TASK_CONTRACT_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
export TASK_CONTRACT_SCRIPT_DIR
exec python3 - "$@" <<'PY'
import hashlib
import json
import os
import re
import sys
import tempfile
import time
from pathlib import Path
from xml.etree import ElementTree as ET

USAGE = (
    "Usage: task-contract.sh "
    "<open PLAN.md project-root task-name [options]|"
    "issue project-root task-name --command NAME --role ROLE --team solo|pair|trio --job TEXT [options]|"
    "verify contract-path project-root [--job TEXT]|"
    "read project-root task-id|state project-root task-id STATE>"
)
LEGAL = {
    "planned": {"dispatched", "cancelled"},
    "dispatched": {"running", "cancelled", "blocked"},
    "running": {"awaiting_review", "blocked", "cancelled"},
    "awaiting_review": {"verified", "blocked"},
    "blocked": {"dispatched", "cancelled"},
    "verified": set(),
    "cancelled": set(),
}
STATES = set(LEGAL)
SCHEMA_KEYS = {
    "contract_id", "schema_version", "created_by", "project_root",
    "source_kind", "source_path", "source_sha256", "command_name",
    "phase", "task_name", "task_identity", "group_name", "team_mode",
    "role", "roles", "test_dev", "plan_files", "files",
    "write_allowances", "allowances_by_role", "job_sha256", "action",
    "verify", "done", "strategy", "state", "contract_digest",
}


def fail(message):
    print("Error: " + message, file=sys.stderr)
    raise SystemExit(1)


def canonical_root(value):
    root = Path(value).resolve()
    if not root.is_dir():
        fail("project root is unavailable")
    return root


def safe_token(value, label):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", value or "") or ".." in value:
        fail(f"invalid {label}")
    return value


def safe_path(value):
    if (
        not value
        or value.startswith("/")
        or "\\" in value
        or "\n" in value
        or "\r" in value
        or any(part in ("", ".", "..") for part in value.split("/"))
    ):
        fail("files must be repo-relative paths")
    return value


def protected_worker_path(value):
    if value in {
        "config/subagent-critical-execution.txt",
        "config/destructive-commands.txt",
        "scripts/task-contract.sh",
        "scripts/agent-lifecycle.sh",
        ".lbwc-planning/.agent-manifest.json",
        ".lbwc-planning/.contracts",
        ".claude/agents",
    }:
        return True
    if value.startswith(".lbwc-planning/.contracts/") or value.startswith(".claude/agents/"):
        return True
    return value.startswith("scripts/") and "guard" in Path(value).name


def safe_id(*parts):
    raw = "-".join(parts)
    result = re.sub(r"[^A-Za-z0-9._-]+", "-", raw).strip(".-")
    if not result or ".." in result:
        fail("invalid task name")
    return result


def role_defaults():
    path = Path(os.environ["TASK_CONTRACT_SCRIPT_DIR"]) / ".." / "templates" / "agent-roles" / "defaults.json"
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        fail("role configuration is unavailable")
    if not isinstance(data, dict):
        fail("role configuration is malformed")
    return data


def configured_team(role, mode):
    safe_token(role, "role")
    defaults = role_defaults()
    if role not in defaults or not isinstance(defaults[role], dict):
        fail("unknown role")
    if mode == "solo":
        roles = [role]
    elif mode == "pair":
        critic = defaults[role].get("pairsWith")
        if not isinstance(critic, str) or not critic:
            fail("role has no configured pair")
        roles = [role, critic]
    elif mode == "trio":
        roles = defaults.get("trios", {}).get(role)
        if not isinstance(roles, list) or len(roles) < 2 or any(not isinstance(item, str) for item in roles):
            fail("role has no configured trio")
    else:
        fail("invalid team mode")
    if len(roles) != len(set(roles)):
        fail("role configuration is malformed")
    return roles


def default_team_mode(role):
    defaults = role_defaults()
    entry = defaults.get(role)
    if isinstance(entry, dict) and isinstance(entry.get("pairsWith"), str):
        return "pair"
    return "solo"


def parse_options(arguments, require_command=False):
    options = {
        "role": "",
        "team": "",
        "group": "",
        "job": "",
        "command": "",
        "write_allowances": [],
        "role_write_allowances": [],
    }
    value_options = {
        "--role": "role",
        "--team": "team",
        "--group": "group",
        "--job": "job",
        "--command": "command",
    }
    index = 0
    while index < len(arguments):
        flag = arguments[index]
        index += 1
        if index >= len(arguments):
            fail(USAGE)
        value = arguments[index]
        index += 1
        if flag in value_options:
            key = value_options[flag]
            if options[key]:
                fail(f"duplicate {flag}")
            options[key] = value
        elif flag == "--write-allowance":
            options["write_allowances"].append(value)
        elif flag == "--role-write-allowance":
            options["role_write_allowances"].append(value)
        else:
            fail(USAGE)
    if require_command and not options["command"]:
        fail("--command is required")
    return options


def parse_plan(path, requested):
    try:
        text = path.read_text()
    except OSError:
        fail("PLAN is not readable")
    phase_match = re.search(r"(?m)^phase:\s*([0-9]+)\s*$", text)
    if not phase_match:
        fail("malformed PLAN: missing phase")
    phase = f"{int(phase_match.group(1)):02d}"
    if len(re.findall(r"<tasks\b", text)) != 1 or len(re.findall(r"</tasks>", text)) != 1:
        fail("duplicate tasks blocks")
    block = re.search(r"<tasks>(.*?)</tasks>", text, re.S)
    if not block or re.search(r"<tasks>|</tasks>", block.group(1)):
        fail("malformed PLAN task structure")
    records = re.findall(r"<task\b[^>]*>(.*?)</task>", block.group(1), re.S)
    if not records or len(records) != len(re.findall(r"<task\b", block.group(1))):
        fail("malformed PLAN task structure")
    selected = None
    for body in records:
        try:
            node = ET.fromstring("<task>" + body + "</task>")
        except ET.ParseError:
            fail("malformed PLAN task structure")
        values = {child.tag: (child.text or "").strip() for child in node}
        if values.get("name") == requested:
            if selected is not None:
                fail("duplicate task name")
            selected = values
    if selected is None:
        fail("unknown task")
    required = ("name", "action", "verify", "done", "strategy")
    if any(not selected.get(key) for key in required):
        fail("malformed PLAN task: required field missing")
    files = [item.strip() for item in re.split(r"[\n,]", selected.get("files", "")) if item.strip()]
    if not files:
        fail("malformed PLAN task: files is required")
    for item in files:
        safe_path(item)
    return text, phase, selected, files


def build_allowances(roles, primary, primary_paths, role_specs, allowed_paths=None):
    allowances = {role: [] for role in roles}
    for path in primary_paths:
        safe_path(path)
        if protected_worker_path(path):
            fail("protected path cannot be granted to a generated worker")
        allowances[primary].append(path)
    for spec in role_specs:
        if ":" not in spec:
            fail("invalid role write allowance")
        role, path = spec.split(":", 1)
        if role not in roles:
            fail("allowance role is not in contract team")
        safe_path(path)
        if protected_worker_path(path):
            fail("protected path cannot be granted to a generated worker")
        allowances[role].append(path)
    flattened = []
    for role in roles:
        for path in allowances[role]:
            if path in flattened:
                fail("duplicate contract allowance")
            if allowed_paths is not None and path not in allowed_paths:
                fail("allowance is not declared by PLAN")
            flattened.append(path)
    return allowances, flattened


def digest_contract(contract):
    immutable = {key: value for key, value in contract.items() if key not in ("contract_digest", "state")}
    canonical = json.dumps(immutable, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode()).hexdigest()


def with_digest(contract):
    contract["contract_digest"] = digest_contract(contract)
    return contract


def command_contract(root, task_name, options):
    role = safe_token(options["role"], "role")
    command = safe_token(options["command"], "command")
    group = safe_token(options["group"] or f"run-{time.time_ns()}", "group")
    if not options["team"]:
        fail("--team is required")
    if not options["job"]:
        fail("--job is required")
    roles = configured_team(role, options["team"])
    allowances, files = build_allowances(
        roles, role, options["write_allowances"], options["role_write_allowances"]
    )
    contract_id = safe_id("cmd", command, task_name, group)
    return with_digest({
        "contract_id": contract_id,
        "schema_version": 2,
        "created_by": "main",
        "project_root": str(root),
        "source_kind": "command",
        "source_path": "",
        "source_sha256": "",
        "command_name": command,
        "phase": "",
        "task_name": task_name,
        "task_identity": contract_id,
        "group_name": group,
        "team_mode": options["team"],
        "role": role,
        "roles": roles,
        "test_dev": "test-dev" in roles,
        "plan_files": [],
        "files": files,
        "write_allowances": allowances[role],
        "allowances_by_role": allowances,
        "job_sha256": hashlib.sha256(options["job"].encode()).hexdigest(),
        "action": options["job"],
        "verify": "",
        "done": "",
        "strategy": "command",
        "state": "planned",
        "contract_digest": "",
    })


def plan_contract(path, root, task_name, options):
    text, phase, selected, plan_files = parse_plan(path, task_name)
    role = options["role"] or selected.get("role", "")
    if not role:
        fail("task role is required; pass --role ROLE")
    team = options["team"] or default_team_mode(role)
    group = safe_token(options["group"] or "task", "group")
    job = options["job"] or selected["action"]
    roles = configured_team(role, team)
    primary_paths = options["write_allowances"] or plan_files
    allowances, files = build_allowances(
        roles, role, primary_paths, options["role_write_allowances"], plan_files
    )
    contract_id = safe_id(phase, path.stem, task_name, *([] if group == "task" else [group]))
    return with_digest({
        "contract_id": contract_id,
        "schema_version": 2,
        "created_by": "main",
        "project_root": str(root),
        "source_kind": "plan",
        "source_path": str(path),
        "source_sha256": hashlib.sha256(text.encode()).hexdigest(),
        "command_name": "build",
        "phase": phase,
        "task_name": task_name,
        "task_identity": contract_id,
        "group_name": group,
        "team_mode": team,
        "role": role,
        "roles": roles,
        "test_dev": "test-dev" in roles,
        "plan_files": plan_files,
        "files": files,
        "write_allowances": allowances[role],
        "allowances_by_role": allowances,
        "job_sha256": hashlib.sha256(job.encode()).hexdigest(),
        "action": selected["action"],
        "verify": selected["verify"],
        "done": selected["done"],
        "strategy": selected["strategy"],
        "state": "planned",
        "contract_digest": "",
    })


def validate_contract(contract, root, expected_id=None, expected_job=None):
    if not isinstance(contract, dict) or set(contract) != SCHEMA_KEYS:
        fail("invalid contract")
    if contract.get("schema_version") != 2:
        fail("invalid contract")
    if contract.get("contract_digest") != digest_contract(contract):
        fail("contract digest mismatch")
    if expected_id and contract.get("contract_id") != expected_id:
        fail("invalid contract")
    if contract.get("created_by") != "main" or contract.get("project_root") != str(root):
        fail("invalid contract")
    contract_id = safe_token(contract.get("contract_id"), "contract id")
    if contract.get("task_identity") != contract_id:
        fail("invalid contract")
    role = contract.get("role")
    roles = configured_team(role, contract.get("team_mode"))
    if contract.get("roles") != roles or contract.get("test_dev") != ("test-dev" in roles):
        fail("invalid contract")
    allowances = contract.get("allowances_by_role")
    if not isinstance(allowances, dict) or set(allowances) != set(roles):
        fail("invalid contract")
    flattened = []
    for team_role in roles:
        paths = allowances.get(team_role)
        if not isinstance(paths, list) or any(not isinstance(path, str) for path in paths):
            fail("invalid contract")
        for path in paths:
            safe_path(path)
            if path in flattened:
                fail("invalid contract")
            flattened.append(path)
    if contract.get("write_allowances") != allowances[role] or contract.get("files") != flattened:
        fail("invalid contract")
    plan_files = contract.get("plan_files")
    if not isinstance(plan_files, list) or any(not isinstance(path, str) for path in plan_files):
        fail("invalid contract")
    for path in plan_files:
        safe_path(path)
    source_kind = contract.get("source_kind")
    if source_kind == "plan":
        source = Path(contract.get("source_path", "")).resolve()
        try:
            source.relative_to(root)
        except ValueError:
            fail("invalid contract: PLAN escapes project root")
        try:
            source_digest = hashlib.sha256(source.read_bytes()).hexdigest()
        except OSError:
            fail("invalid contract: PLAN is unavailable")
        if source_digest != contract.get("source_sha256"):
            fail("invalid contract: PLAN digest mismatch")
        if any(path not in plan_files for path in flattened):
            fail("invalid contract")
    elif source_kind == "command":
        if contract.get("source_path") or contract.get("source_sha256") or plan_files:
            fail("invalid contract")
    else:
        fail("invalid contract")
    if contract.get("state") not in STATES:
        fail("invalid contract")
    if expected_job is not None:
        actual = hashlib.sha256(expected_job.encode()).hexdigest()
        if actual != contract.get("job_sha256"):
            fail("job digest mismatch")


def contract_path(root, contract_id):
    return root / ".lbwc-planning" / ".contracts" / "tasks" / f"{contract_id}.json"


def validate_contract_path(path, root):
    resolved = path.resolve()
    expected_parent = (root / ".lbwc-planning" / ".contracts" / "tasks").resolve()
    if resolved.parent != expected_parent:
        fail("contract path is outside the protected registry")
    return resolved


def lock(root):
    contracts = root / ".lbwc-planning" / ".contracts"
    tasks = contracts / "tasks"
    lock_dir = contracts / ".lock"
    if contracts.is_symlink():
        fail("refusing symlinked .contracts directory")
    if tasks.is_symlink():
        fail("refusing symlinked .contracts/tasks directory")
    contracts.mkdir(parents=True, exist_ok=True)
    try:
        timeout = min(1000, max(1, int(os.environ.get("TASK_CONTRACT_LOCK_TIMEOUT_MS", "250"))))
    except ValueError:
        timeout = 250
    deadline = time.monotonic() + timeout / 1000
    while True:
        try:
            lock_dir.mkdir()
            (lock_dir / "pid").write_text(str(os.getpid()))
            return lock_dir
        except FileExistsError:
            if time.monotonic() >= deadline:
                fail("timed out acquiring contract lock")
            time.sleep(0.01)


def unlock(lock_dir):
    try:
        (lock_dir / "pid").unlink(missing_ok=True)
        lock_dir.rmdir()
    except OSError:
        pass


def atomic(path, contract):
    path.parent.mkdir(parents=True, exist_ok=True)
    data = json.dumps(contract, sort_keys=True, indent=2) + "\n"
    descriptor, temporary = tempfile.mkstemp(prefix=path.name + ".tmp.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def load(path):
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        fail("invalid contract")


def immutable_equal(left, right):
    ignored = {"state", "contract_digest"}
    return all(left.get(key) == right.get(key) for key in SCHEMA_KEYS - ignored)


def create_or_reopen(root, contract):
    validate_contract(contract, root)
    path = contract_path(root, contract["contract_id"])
    held = lock(root)
    try:
        if path.exists():
            existing = load(path)
            validate_contract(existing, root, contract["contract_id"])
            if not immutable_equal(existing, contract):
                fail("duplicate contract")
            print(path)
            return
        atomic(path, contract)
        print(path)
    finally:
        unlock(held)


def main():
    if len(sys.argv) < 2:
        fail(USAGE)
    command = sys.argv[1]
    if command == "open":
        if len(sys.argv) < 5:
            fail(USAGE)
        root = canonical_root(sys.argv[3])
        plan = Path(sys.argv[2]).resolve()
        try:
            plan.relative_to(root)
        except ValueError:
            fail("PLAN escapes project root")
        options = parse_options(sys.argv[5:])
        create_or_reopen(root, plan_contract(plan, root, sys.argv[4], options))
        return
    if command == "issue":
        if len(sys.argv) < 5:
            fail(USAGE)
        root = canonical_root(sys.argv[2])
        options = parse_options(sys.argv[4:], require_command=True)
        create_or_reopen(root, command_contract(root, sys.argv[3], options))
        return
    if command == "verify":
        if len(sys.argv) not in (4, 6) or (len(sys.argv) == 6 and sys.argv[4] != "--job"):
            fail(USAGE)
        root = canonical_root(sys.argv[3])
        path = validate_contract_path(Path(sys.argv[2]), root)
        contract = load(path)
        validate_contract(contract, root, path.stem, sys.argv[5] if len(sys.argv) == 6 else None)
        print(json.dumps(contract, sort_keys=True, indent=2))
        return
    if command in ("read", "state"):
        if (command == "read" and len(sys.argv) != 4) or (command == "state" and len(sys.argv) != 5):
            fail(USAGE)
        root = canonical_root(sys.argv[2])
        contract_id = safe_token(sys.argv[3], "task id")
        path = contract_path(root, contract_id)
        if not path.is_file():
            fail("unknown contract")
        held = lock(root)
        try:
            contract = load(path)
            validate_contract(contract, root, contract_id)
            if command == "state":
                new_state = sys.argv[4]
                if new_state not in STATES:
                    fail("invalid state")
                if new_state not in LEGAL.get(contract["state"], set()):
                    fail("illegal state transition")
                contract["state"] = new_state
                contract["contract_digest"] = digest_contract(contract)
                atomic(path, contract)
            print(json.dumps(contract, sort_keys=True, indent=2))
        finally:
            unlock(held)
        return
    fail(USAGE)


main()
PY
