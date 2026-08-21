#!/usr/bin/env bash
set -euo pipefail

TASK_CONTRACT_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
export TASK_CONTRACT_SCRIPT_DIR
exec python3 - "$@" <<'PY'
import hashlib
import json
import os
import re
import subprocess
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
RUNTIME_KINDS = {"native-team"}
COMMUNICATION_POLICIES = {"native-team", "critic-relay"}
EXECUTION_BACKENDS = {"in_process", "tmux", "workflow"}
SCHEMA_2_KEYS = {
    "contract_id", "schema_version", "created_by", "project_root",
    "source_kind", "source_path", "source_sha256", "command_name",
    "phase", "task_name", "task_identity", "group_name", "team_mode",
    "role", "roles", "test_dev", "plan_files", "files",
    "write_allowances", "allowances_by_role", "job_sha256", "action",
    "verify", "done", "strategy", "state", "contract_digest",
}
SCHEMA_3_KEYS = SCHEMA_2_KEYS | {
    "capabilities_by_role", "communication_policy", "control_root", "runtime_kind",
    "requested_backend", "resolved_backend"
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


def safe_capability_path(value, kind):
    if kind == "directory" and value == ".":
        return value
    if kind not in {"file", "directory"}:
        fail("capability kind must be file or directory")
    safe_path(value)
    return value


def resolve_control_root(value, root):
    script = Path(os.environ["TASK_CONTRACT_SCRIPT_DIR"]) / "lib" / "lbwc-control-root.sh"
    if not script.is_file():
        fail("control root resolver is unavailable")
    try:
        result = subprocess.run(
            ["bash", "-c", '. "$1"; lbwc_resolve_control_root "$2" "$3" "$4"',
             "lbwc-control-root", str(script), value, str(root), str(root)],
            check=True, capture_output=True, text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        fail("control root is unavailable or invalid")
    resolved = result.stdout.strip()
    if not resolved:
        fail("control root is unavailable or invalid")
    return Path(resolved)


def protected_worker_path(value):
    if value == ".git" or value.startswith(".git/"):
        return True
    if value == ".temporary-agent-runfiles" or value.startswith(".temporary-agent-runfiles/"):
        return True
    if value == ".env" or value.startswith(".env.") or "/.env" in value:
        return True
    if re.search(r"(^|/)[^/]+\.(pem|key|cert|p12|pfx)(\.[A-Za-z0-9]+)?$", value):
        return True
    if value.endswith("credentials.json") or value.endswith("secrets.json") or value.endswith("service-account.json"):
        return True
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


def role_write_capable(role_name):
    entry = role_defaults().get(role_name, {})
    disallowed = entry.get("disallowedTools", "") if isinstance(entry, dict) else ""
    tokens = {token.strip() for token in disallowed.split(",")}
    return not {"Write", "Edit"}.issubset(tokens)


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
        "control_root": "",
        "capabilities": [],
        "role_capabilities": [],
        "read_only_roles": [],
        "runtime_kind": "",
        "communication_policy": "",
        "requested_backend": "",
        "resolved_backend": "",
        "assert_snapshot": "",
    }
    value_options = {
        "--role": "role",
        "--team": "team",
        "--group": "group",
        "--job": "job",
        "--command": "command",
        "--control-root": "control_root",
        "--runtime-kind": "runtime_kind",
        "--communication-policy": "communication_policy",
        "--requested-backend": "requested_backend",
        "--resolved-backend": "resolved_backend",
        "--assert-snapshot": "assert_snapshot",
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
        elif flag in ("--write-capability", "--capability"):
            if ":" not in value:
                fail("invalid write capability")
            kind, path = value.split(":", 1)
            options["capabilities"].append((kind, path))
        elif flag == "--role-write-capability":
            parts = value.split(":", 2)
            if len(parts) != 3:
                fail("invalid role write capability")
            options["role_capabilities"].append(tuple(parts))
        elif flag == "--read-only-role":
            options["read_only_roles"].append(value)
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


def build_capabilities(roles, primary, primary_capabilities, role_specs):
    capabilities = {role: [] for role in roles}
    for kind, path in primary_capabilities:
        safe_capability_path(path, kind)
        if protected_worker_path(path):
            fail("protected path cannot be granted to a generated worker")
        capabilities[primary].append({"access": "write", "kind": kind, "path": path})
    for role, kind, path in role_specs:
        if role not in roles:
            fail("capability role is not in contract team")
        safe_capability_path(path, kind)
        if protected_worker_path(path):
            fail("protected path cannot be granted to a generated worker")
        capabilities[role].append({"access": "write", "kind": kind, "path": path})
    seen = set()
    for role in roles:
        for capability in capabilities[role]:
            identity = (role, capability["kind"], capability["path"])
            if identity in seen:
                fail("duplicate contract capability")
            seen.add(identity)
    return capabilities


def digest_contract(contract):
    immutable = {key: value for key, value in contract.items() if key not in ("contract_digest", "state")}
    canonical = json.dumps(immutable, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode()).hexdigest()


def with_digest(contract):
    contract["contract_digest"] = digest_contract(contract)
    return contract


def capabilities_from_allowances(allowances):
    return {
        role: [{"access": "write", "kind": "file", "path": path} for path in paths]
        for role, paths in allowances.items()
    }


def schema3_plan_requested(options):
    flags = (
        bool(options["requested_backend"]),
        bool(options["resolved_backend"]),
        bool(options["control_root"]),
    )
    if any(flags) != all(flags):
        fail("schema 3 open requires --requested-backend, --resolved-backend, and --control-root")
    return all(flags)


def plan_schema3_fields(options, root, allowances):
    requested = options["requested_backend"]
    resolved = options["resolved_backend"]
    runtime_kind = options["runtime_kind"] or "native-team"
    communication_policy = options["communication_policy"] or "native-team"
    if requested not in EXECUTION_BACKENDS:
        fail("invalid requested_backend")
    if resolved not in EXECUTION_BACKENDS:
        fail("invalid resolved_backend")
    if requested != resolved:
        fail("requested_backend and resolved_backend must match")
    if runtime_kind not in RUNTIME_KINDS:
        fail("invalid runtime_kind")
    if communication_policy not in COMMUNICATION_POLICIES:
        fail("invalid communication_policy")
    return {
        "capabilities_by_role": capabilities_from_allowances(allowances),
        "communication_policy": communication_policy,
        "control_root": str(resolve_control_root(options["control_root"], root)),
        "runtime_kind": runtime_kind,
        "requested_backend": requested,
        "resolved_backend": resolved,
        "schema_version": 3,
    }


def assert_contract_matches_snapshot(path, contract):
    try:
        snapshot = json.loads(Path(path).read_text())
    except (OSError, json.JSONDecodeError):
        fail("runtime snapshot is malformed")
    if not isinstance(snapshot, dict):
        fail("runtime snapshot is malformed")
    if contract.get("schema_version") != 3:
        fail("snapshot assertion requires a schema 3 contract")
    if (
        snapshot.get("requested_backend") != contract.get("requested_backend")
        or snapshot.get("resolved_backend") != contract.get("resolved_backend")
    ):
        fail("snapshot backend mismatch")
    if "control_root" in snapshot and snapshot.get("control_root") != contract.get("control_root"):
        fail("snapshot backend mismatch")


def command_contract(root, task_name, options):
    role = safe_token(options["role"], "role")
    command = safe_token(options["command"], "command")
    group = safe_token(options["group"] or f"run-{time.time_ns()}", "group")
    if not options["team"]:
        fail("--team is required")
    if not options["job"]:
        fail("--job is required")
    roles = configured_team(role, options["team"])
    capabilities = build_capabilities(roles, role, options["capabilities"], options["role_capabilities"])
    for read_only_role in options["read_only_roles"]:
        safe_token(read_only_role, "role")
        if read_only_role not in roles:
            fail("read-only role is not in contract team")
        if capabilities[read_only_role]:
            fail("role declared read-only cannot also receive a write capability")
    typed = bool(options["capabilities"] or options["role_capabilities"] or options["control_root"])
    if typed:
        allowances = {
            team_role: [item["path"] for item in capabilities[team_role]]
            for team_role in roles
        }
        files = [path for team_role in roles for path in allowances[team_role]]
    else:
        allowances, files = build_allowances(
            roles, role, options["write_allowances"], options["role_write_allowances"]
        )
    if typed and options["write_allowances"]:
        fail("typed capabilities cannot be combined with exact write allowances")
    if typed and not options["capabilities"] and not options["role_capabilities"] and any(
        role_write_capable(team_role) for team_role in roles if team_role not in options["read_only_roles"]
    ):
        fail("typed contract requires at least one capability")
    if typed and "." in [item["path"] for role_caps in capabilities.values() for item in role_caps] and command != "team":
        fail("repository root capability is only valid for team")
    control_root = resolve_control_root(options["control_root"], root) if typed else None
    requested_backend = options["requested_backend"] or "in_process"
    resolved_backend = options["resolved_backend"] or requested_backend
    runtime_kind = options["runtime_kind"] or "native-team"
    communication_policy = options["communication_policy"] or "native-team"
    if not typed and (options["requested_backend"] or options["resolved_backend"]):
        fail("execution backends require a schema 3 contract")
    if typed and runtime_kind not in RUNTIME_KINDS:
        fail("invalid runtime_kind")
    if typed and communication_policy not in COMMUNICATION_POLICIES:
        fail("invalid communication_policy")
    if typed and requested_backend not in EXECUTION_BACKENDS:
        fail("invalid requested_backend")
    if typed and resolved_backend not in EXECUTION_BACKENDS:
        fail("invalid resolved_backend")
    if typed and requested_backend != resolved_backend:
        fail("requested_backend and resolved_backend must match")
    contract_id = safe_id("cmd", command, task_name, group)
    contract = {
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
    }
    if typed:
        contract.update({
            "capabilities_by_role": capabilities,
            "communication_policy": communication_policy,
            "control_root": str(control_root),
            "runtime_kind": runtime_kind,
            "requested_backend": requested_backend,
            "resolved_backend": resolved_backend,
            "schema_version": 3,
        })
    return with_digest(contract)


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
    contract = {
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
    }
    if schema3_plan_requested(options):
        contract.update(plan_schema3_fields(options, root, allowances))
    return with_digest(contract)


def validate_contract(contract, root, expected_id=None, expected_job=None):
    if not isinstance(contract, dict):
        fail("invalid contract")
    schema_version = contract.get("schema_version")
    expected_keys = SCHEMA_2_KEYS if schema_version == 2 else SCHEMA_3_KEYS if schema_version == 3 else set()
    if set(contract) != expected_keys:
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
            if schema_version == 2:
                safe_path(path)
            if path in flattened:
                fail("invalid contract")
            flattened.append(path)
    if schema_version == 3:
        control_root = resolve_control_root(contract.get("control_root", ""), root)
        if str(control_root) != contract.get("control_root"):
            fail("invalid contract")
        capabilities = contract.get("capabilities_by_role")
        if not isinstance(capabilities, dict) or set(capabilities) != set(roles):
            fail("invalid contract")
        capability_paths = {role: [] for role in roles}
        for team_role in roles:
            entries = capabilities[team_role]
            if not isinstance(entries, list):
                fail("invalid contract")
            for entry in entries:
                if not isinstance(entry, dict) or set(entry) != {"access", "kind", "path"} or entry.get("access") != "write":
                    fail("invalid contract")
                kind = entry.get("kind")
                path = entry.get("path")
                safe_capability_path(path, kind)
                if protected_worker_path(path):
                    fail("invalid contract")
                capability_paths[team_role].append(path)
        if contract.get("write_allowances") != capability_paths[contract["role"]]:
            fail("invalid contract")
        if contract.get("files") != [path for team_role in roles for path in capability_paths[team_role]]:
            fail("invalid contract")
        if contract.get("runtime_kind") not in RUNTIME_KINDS:
            fail("invalid contract")
        if contract.get("communication_policy") not in COMMUNICATION_POLICIES:
            fail("invalid contract")
        if contract.get("requested_backend") not in EXECUTION_BACKENDS:
            fail("invalid contract")
        if contract.get("resolved_backend") not in EXECUTION_BACKENDS:
            fail("invalid contract")
        if contract["requested_backend"] != contract["resolved_backend"]:
            fail("invalid contract")
    elif any(key in contract for key in ("capabilities_by_role", "control_root", "runtime_kind", "communication_policy", "requested_backend", "resolved_backend")):
        fail("invalid contract")
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


def contract_path(root, contract_id, control_root=None):
    registry = control_root / "contracts" / "tasks" if control_root and control_root.name != ".lbwc-planning" else (control_root or root / ".lbwc-planning") / ".contracts" / "tasks"
    return registry / f"{contract_id}.json"


def locate_contract_path(root, contract_id):
    active = contract_path(root, contract_id)
    if active.is_file():
        return active
    runs = root / ".temporary-agent-runfiles" / "runs"
    if runs.is_dir():
        for run_root in sorted(runs.iterdir()):
            candidate = contract_path(root, contract_id, run_root)
            if candidate.is_file():
                return candidate
    return active


def control_root_for_contract_path(path, root):
    resolved = path.resolve()
    active_root = (root / ".lbwc-planning").resolve()
    if resolved.parent == active_root / ".contracts" / "tasks":
        return None
    return resolved.parent.parent.parent


def validate_contract_path(path, root):
    resolved = path.resolve()
    expected_parent = (root / ".lbwc-planning" / ".contracts" / "tasks").resolve()
    valid = resolved.parent == expected_parent
    temporary_parent = root / ".temporary-agent-runfiles" / "runs"
    if temporary_parent.is_dir():
        for run_root in temporary_parent.iterdir():
            if run_root.is_dir() and resolved.parent == (run_root / "contracts" / "tasks").resolve():
                valid = True
                break
    if not valid:
        fail("contract path is outside the protected registry")
    return resolved


def lock(root, control_root=None):
    contracts = ((control_root or root / ".lbwc-planning") / ("contracts" if control_root and control_root.name != ".lbwc-planning" else ".contracts"))
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
    keys = SCHEMA_2_KEYS if left.get("schema_version") == 2 else SCHEMA_3_KEYS
    return all(left.get(key) == right.get(key) for key in keys - ignored)


def create_or_reopen(root, contract):
    validate_contract(contract, root)
    control_root = Path(contract["control_root"]) if contract.get("schema_version") == 3 else None
    path = contract_path(root, contract["contract_id"], control_root)
    held = lock(root, control_root)
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
        contract = plan_contract(plan, root, sys.argv[4], options)
        if options["assert_snapshot"]:
            assert_contract_matches_snapshot(options["assert_snapshot"], contract)
        create_or_reopen(root, contract)
        return
    if command == "issue":
        if len(sys.argv) < 5:
            fail(USAGE)
        root = canonical_root(sys.argv[2])
        options = parse_options(sys.argv[4:], require_command=True)
        contract = command_contract(root, sys.argv[3], options)
        if options["assert_snapshot"]:
            assert_contract_matches_snapshot(options["assert_snapshot"], contract)
        create_or_reopen(root, contract)
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
        path = locate_contract_path(root, contract_id)
        if not path.is_file():
            fail("unknown contract")
        control_root = control_root_for_contract_path(path, root)
        held = lock(root, control_root)
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
