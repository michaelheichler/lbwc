from __future__ import annotations

import hashlib
import json
import os
import re
import secrets
import shlex
import sys
import tempfile
import time
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import Any, cast

ASK_TOOL = "AskUserQuestion"
INSPECTION_TOOLS = {"Read", "Glob", "Grep"}
TECHNICAL_TERMS = re.compile(
    r"\b(api|binary|cli|filesystem|hook|json|regex|runtime|schema|token)\b",
    re.IGNORECASE,
)
SESSION_PATTERN = re.compile(r"[A-Za-z0-9._-]{1,128}")
MIN_QUESTION_LENGTH = 16
MAX_QUESTION_LENGTH = 500
MIN_HEADER_LENGTH = 2
MAX_HEADER_LENGTH = 80
MIN_OPTIONS = 2
MAX_OPTIONS = 4
MIN_DESCRIPTION_LENGTH = 8
MAX_DESCRIPTION_LENGTH = 240
LOCK_ATTEMPTS = 100
LOCK_DELAY_SECONDS = 0.01
DECISION_SCHEMA_VERSION = 2
DIGEST_LENGTH = 64
READ_DECISION_ARGUMENTS = 3
PROTECTED_MARKERS = (
    "pending-decision.sh",
    "user_question_guard.py",
    ".lbwc-planning/.runtime",
    ".runtime/decisions",
    ".hook-transitions",
)
PLUGIN_ROOT = Path(__file__).resolve().parent.parent
PROTECTED_FILES = {
    (PLUGIN_ROOT / "scripts" / "pending-decision.sh").resolve(),
    (PLUGIN_ROOT / "hooks" / "user_question_guard.py").resolve(),
}


class DecisionStateError(RuntimeError):
    pass


class PendingDecisionError(DecisionStateError):
    pass


def _pretool_denial(reason: str) -> str:
    return json.dumps(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        }
    )


def _stop_block(reason: str) -> str:
    return json.dumps({"decision": "block", "reason": reason})


def _write_output(payload: str) -> None:
    sys.stdout.write(f"{payload}\n")


def _event(stdin_text: str) -> tuple[dict[str, Any] | None, str | None]:
    try:
        data = json.loads(stdin_text)
    except json.JSONDecodeError:
        return None, "Hook error: malformed hook JSON input."
    if not isinstance(data, dict):
        return None, "Hook error: malformed hook JSON input."
    return data, None


def _planning_directory(cwd: object) -> Path | None:
    if not isinstance(cwd, str) or not cwd:
        return None
    current = Path(cwd).resolve()
    while current != current.parent:
        candidate = current / ".lbwc-planning"
        if candidate.exists() or candidate.is_symlink():
            if candidate.is_dir() and not candidate.is_symlink():
                return candidate
            raise DecisionStateError("The pending user decision state is invalid.")
        current = current.parent
    return None


def _current_directory(cwd: object) -> Path | None:
    return Path(cwd).resolve() if isinstance(cwd, str) and cwd else None


def _session_id(data: dict[str, Any]) -> str | None:
    value = data.get("session_id")
    if isinstance(value, str) and SESSION_PATTERN.fullmatch(value):
        return value
    return None


def _require(condition: object, message: str) -> None:
    if not condition:
        raise DecisionStateError(message)


def _is_physical_directory(path: Path) -> bool:
    return (
        path.is_dir()
        and not path.is_symlink()
        and all(not parent.is_symlink() for parent in path.parents)
    )


def _has_technical_language(value: str) -> bool:
    return bool(TECHNICAL_TERMS.search(value)) or "\n" in value or "`" in value


def _validate_question(tool_input: object) -> dict[str, Any]:
    _require(isinstance(tool_input, dict), "AskUserQuestion input is malformed.")
    question_input = cast(dict[str, Any], tool_input)
    questions = question_input.get("questions")
    _require(
        isinstance(questions, list)
        and len(questions) == 1
        and isinstance(questions[0], dict),
        "AskUserQuestion must present one decision at a time.",
    )
    questions = cast(list[dict[str, Any]], questions)
    question = questions[0]
    wording = question.get("question")
    _require(
        isinstance(wording, str)
        and wording.endswith("?")
        and MIN_QUESTION_LENGTH <= len(wording) <= MAX_QUESTION_LENGTH,
        "AskUserQuestion needs one clear, self-contained question.",
    )
    wording = cast(str, wording)
    _require(
        not _has_technical_language(wording),
        "AskUserQuestion must use plain language for the user.",
    )
    header = question.get("header")
    _require(
        header is None
        or (
            isinstance(header, str)
            and MIN_HEADER_LENGTH <= len(header) <= MAX_HEADER_LENGTH
            and not _has_technical_language(header)
        ),
        "AskUserQuestion header is invalid.",
    )
    _require(
        question.get("multiSelect") in (None, False),
        "AskUserQuestion must ask for one decision.",
    )
    options = question.get("options")
    _require(
        isinstance(options, list) and MIN_OPTIONS <= len(options) <= MAX_OPTIONS,
        "AskUserQuestion needs two to four choices.",
    )
    options = cast(list[dict[str, Any]], options)
    labels: list[str] = []
    for option in options:
        _require(isinstance(option, dict), "AskUserQuestion options are invalid.")
        label = option.get("label")
        description = option.get("description")
        _require(
            isinstance(label, str) and 1 <= len(label) <= MAX_HEADER_LENGTH,
            "AskUserQuestion option labels are invalid.",
        )
        _require(
            isinstance(description, str)
            and MIN_DESCRIPTION_LENGTH <= len(description) <= MAX_DESCRIPTION_LENGTH,
            "AskUserQuestion options need clear descriptions.",
        )
        label = cast(str, label)
        description = cast(str, description)
        _require(
            not _has_technical_language(label)
            and not _has_technical_language(description),
            "AskUserQuestion options must use plain language for the user.",
        )
        labels.append(label)
    _require(
        len(labels) == len(set(labels)), "AskUserQuestion option labels must be unique."
    )
    _require(
        not any(label.strip().lower() == "other" for label in labels),
        "AskUserQuestion must not duplicate the native Other option.",
    )
    return {
        "question": wording,
        "options": labels,
        "allows_freeform": True,
    }


def _fingerprint(question: dict[str, Any], planning_dir: Path) -> str:
    state: dict[str, str] = {"cwd": str(planning_dir.parent)}
    for filename in ("config.json", "capabilities.json", "routing.json"):
        path = planning_dir / filename
        if path.exists() or path.is_symlink():
            _require(
                path.is_file() and not path.is_symlink(),
                "The pending user decision state is invalid.",
            )
            state[filename] = hashlib.sha256(path.read_bytes()).hexdigest()
    payload = {"command": ASK_TOOL, "question": question, "state": state}
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


class DecisionStore:
    def __init__(self, planning_dir: Path) -> None:
        planning_dir = planning_dir.resolve()
        _require(
            _is_physical_directory(planning_dir),
            "The pending user decision state is invalid.",
        )
        self.planning_dir = planning_dir

    def _ensure_directory(self, path: Path) -> Path:
        if path.exists() or path.is_symlink():
            _require(
                _is_physical_directory(path),
                "The pending user decision state is invalid.",
            )
        else:
            path.mkdir(mode=0o700)
        return path

    def _decisions_directory(self, create: object) -> Path | None:
        runtime = self.planning_dir / ".runtime"
        decisions = runtime / "decisions"
        if not create and not runtime.exists() and not runtime.is_symlink():
            return None
        self._ensure_directory(runtime)
        if not create and not decisions.exists() and not decisions.is_symlink():
            return None
        return self._ensure_directory(decisions)

    def _record_path(self, session_id: str, create: object) -> Path | None:
        _require(
            bool(SESSION_PATTERN.fullmatch(session_id)),
            "The pending user decision record is invalid.",
        )
        decisions = self._decisions_directory(create)
        return None if decisions is None else decisions / f"{session_id}.json"

    def _authority_path(
        self, session_id: str, transition_id: str, create: object
    ) -> Path | None:
        decisions = self._decisions_directory(create)
        if decisions is None:
            return None
        authority = decisions / ".hook-transitions"
        session = authority / session_id
        if create:
            self._ensure_directory(authority)
            self._ensure_directory(session)
        elif (
            not authority.exists()
            or authority.is_symlink()
            or not session.exists()
            or session.is_symlink()
        ):
            return None
        else:
            _require(
                _is_physical_directory(authority),
                "The pending user decision record is invalid.",
            )
            _require(
                _is_physical_directory(session),
                "The pending user decision record is invalid.",
            )
        return session / f"{transition_id}.json"

    @staticmethod
    def _digest(record: dict[str, Any]) -> str:
        unsigned = {
            key: value for key, value in record.items() if key != "record_digest"
        }
        payload = json.dumps(unsigned, sort_keys=True, separators=(",", ":")).encode(
            "utf-8"
        )
        return hashlib.sha256(payload).hexdigest()

    @staticmethod
    def _validate_shape(shape: object) -> dict[str, Any]:
        _require(
            isinstance(shape, dict), "The pending user decision record is invalid."
        )
        shape = cast(dict[str, Any], shape)
        expected = {"allows_freeform", "mode", "options", "question"}
        _require(
            set(shape) == expected and shape.get("mode") == "bounded",
            "The pending user decision record is invalid.",
        )
        question = shape.get("question")
        options = shape.get("options")
        allows_freeform = shape.get("allows_freeform")
        _require(
            isinstance(question, str), "The pending user decision record is invalid."
        )
        _require(
            isinstance(options, list), "The pending user decision record is invalid."
        )
        options = cast(list[Any], options)
        _require(
            MIN_OPTIONS <= len(options) <= MAX_OPTIONS,
            "The pending user decision record is invalid.",
        )
        _require(
            all(isinstance(option, str) and option for option in options),
            "The pending user decision record is invalid.",
        )
        _require(
            len(options) == len(set(options)),
            "The pending user decision record is invalid.",
        )
        _require(
            isinstance(allows_freeform, bool),
            "The pending user decision record is invalid.",
        )
        return shape

    def _load_json(self, path: Path) -> dict[str, Any]:
        _require(
            path.is_file() and not path.is_symlink(),
            "The pending user decision record is invalid.",
        )
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise DecisionStateError(
                "The pending user decision record is invalid."
            ) from error
        _require(
            isinstance(payload, dict), "The pending user decision record is invalid."
        )
        return cast(dict[str, Any], payload)

    def _validate_record(self, record: dict[str, Any]) -> None:
        expected = {
            "command",
            "created_at",
            "record_digest",
            "resolved_at",
            "response",
            "response_received_at",
            "response_shape",
            "schema_version",
            "session_id",
            "state_fingerprint",
            "status",
            "transition_id",
        }
        _require(
            set(record) == expected, "The pending user decision record is invalid."
        )
        _require(
            record.get("schema_version") == DECISION_SCHEMA_VERSION,
            "The pending user decision record is invalid.",
        )
        session_id = record.get("session_id")
        fingerprint = record.get("state_fingerprint")
        transition_id = record.get("transition_id")
        digest = record.get("record_digest")
        _require(
            isinstance(session_id, str) and bool(SESSION_PATTERN.fullmatch(session_id)),
            "The pending user decision record is invalid.",
        )
        _require(
            isinstance(fingerprint, str) and len(fingerprint) == DIGEST_LENGTH,
            "The pending user decision record is invalid.",
        )
        _require(
            isinstance(transition_id, str) and bool(transition_id),
            "The pending user decision record is invalid.",
        )
        _require(
            isinstance(digest, str) and digest == self._digest(record),
            "The pending user decision record integrity check failed.",
        )
        self._validate_shape(record.get("response_shape"))
        _require(
            record.get("status") in {"pending", "awaiting_freeform", "resolved"},
            "The pending user decision record is invalid.",
        )
        authority = self._authority_path(
            cast(str, session_id), cast(str, transition_id), create=False
        )
        _require(
            authority is not None,
            "The pending user decision record integrity check failed.",
        )
        authority_data = self._load_json(cast(Path, authority))
        _require(
            authority_data
            == {
                "record_digest": digest,
                "session_id": session_id,
                "transition_id": transition_id,
            },
            "The pending user decision record integrity check failed.",
        )

    def _read_record(self, session_id: str) -> dict[str, Any] | None:
        path = self._record_path(session_id, create=False)
        if path is None or not path.exists():
            return None
        record = self._load_json(path)
        self._validate_record(record)
        return record

    @contextmanager
    def _lock(self, session_id: str) -> Iterator[None]:
        path = self._record_path(session_id, create=True)
        _require(path is not None, "The pending user decision state is invalid.")
        lock_path = Path(f"{path}.lock")
        for _ in range(LOCK_ATTEMPTS):
            try:
                lock_path.mkdir(mode=0o700)
                break
            except FileExistsError:
                time.sleep(LOCK_DELAY_SECONDS)
        else:
            raise DecisionStateError("The pending user decision record is locked.")
        try:
            yield
        finally:
            lock_path.rmdir()

    @staticmethod
    def _write_json(path: Path, payload: dict[str, Any]) -> None:
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=".decision-", dir=path.parent
        )
        temporary_path = Path(temporary_name)
        try:
            os.fchmod(descriptor, 0o600)
            os.close(descriptor)
            descriptor = -1
            temporary_path.write_text(
                json.dumps(payload, sort_keys=True, separators=(",", ":")),
                encoding="utf-8",
            )
            temporary_path.replace(path)
        finally:
            if descriptor >= 0:
                os.close(descriptor)
            temporary_path.unlink(missing_ok=True)

    def _persist(self, path: Path, record: dict[str, Any]) -> None:
        session_id = record["session_id"]
        _require(
            isinstance(session_id, str), "The pending user decision record is invalid."
        )
        record["transition_id"] = secrets.token_urlsafe(32)
        record["record_digest"] = ""
        record["record_digest"] = self._digest(record)
        transition_id = record["transition_id"]
        digest = record["record_digest"]
        _require(
            isinstance(transition_id, str) and isinstance(digest, str),
            "The pending user decision record is invalid.",
        )
        authority = self._authority_path(session_id, transition_id, create=True)
        _require(authority is not None, "The pending user decision state is invalid.")
        self._write_json(
            cast(Path, authority),
            {
                "record_digest": digest,
                "session_id": session_id,
                "transition_id": transition_id,
            },
        )
        self._write_json(path, record)

    def state(self, session_id: str) -> str:
        record = self._read_record(session_id)
        return "none" if record is None else str(record["status"])

    def record(self, session_id: str) -> dict[str, Any]:
        record = self._read_record(session_id)
        _require(record is not None, "The pending user decision record is unavailable.")
        return cast(dict[str, Any], record)

    def open(self, session_id: str, fingerprint: str, shape: dict[str, Any]) -> None:
        self._validate_shape(shape)
        with self._lock(session_id):
            current = self._read_record(session_id)
            if current and current["status"] in {"pending", "awaiting_freeform"}:
                _require(
                    current["state_fingerprint"] != fingerprint,
                    "A user decision is already pending.",
                )
            record = {
                "schema_version": DECISION_SCHEMA_VERSION,
                "session_id": session_id,
                "command": ASK_TOOL,
                "state_fingerprint": fingerprint,
                "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "response_shape": shape,
                "status": "pending",
                "response": None,
                "response_received_at": None,
                "resolved_at": None,
                "transition_id": "",
                "record_digest": "",
            }
            path = self._record_path(session_id, create=True)
            _require(path is not None, "The pending user decision state is invalid.")
            self._persist(cast(Path, path), record)

    def answer(self, session_id: str, answer: str, fingerprint: str) -> None:
        with self._lock(session_id):
            record = self.record(session_id)
            _require(
                record["state_fingerprint"] == fingerprint,
                "The user decision state changed. Present a new decision.",
            )
            _require(
                record["status"] == "pending",
                "The pending user decision record is invalid.",
            )
            shape = self._validate_shape(record["response_shape"])
            options = shape["options"]
            _require(
                isinstance(options, list),
                "The pending user decision record is invalid.",
            )
            timestamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            if answer in options:
                record["status"] = "resolved"
                record["response"] = answer
                record["resolved_at"] = timestamp
            else:
                record["status"] = "resolved"
                record["response"] = {"kind": "freeform", "received": True}
                record["response_received_at"] = timestamp
                record["resolved_at"] = timestamp
            path = self._record_path(session_id, create=True)
            _require(path is not None, "The pending user decision state is invalid.")
            self._persist(cast(Path, path), record)

    def resolve_freeform(self, session_id: str, fingerprint: str) -> None:
        with self._lock(session_id):
            record = self.record(session_id)
            _require(
                record["state_fingerprint"] == fingerprint,
                "The user decision state changed. Present a new decision.",
            )
            _require(
                record["status"] == "awaiting_freeform",
                "The pending user decision record is invalid.",
            )
            timestamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            record["status"] = "resolved"
            record["response"] = {"kind": "freeform", "received": True}
            record["response_received_at"] = timestamp
            record["resolved_at"] = timestamp
            path = self._record_path(session_id, create=True)
            _require(path is not None, "The pending user decision state is invalid.")
            self._persist(cast(Path, path), record)


def _record_for_current_state(
    store: DecisionStore, session_id: str
) -> tuple[dict[str, Any] | None, str | None]:
    try:
        record = store.record(session_id)
        shape = record["response_shape"]
        _require(
            isinstance(shape, dict), "The pending user decision record is invalid."
        )
        question = {
            "question": shape["question"],
            "options": shape["options"],
            "allows_freeform": shape["allows_freeform"],
        }
        fingerprint = _fingerprint(question, store.planning_dir)
        _require(
            record["state_fingerprint"] == fingerprint,
            "The user decision state changed. Present a new decision.",
        )
    except (DecisionStateError, KeyError) as error:
        return None, str(error)
    else:
        return record, None


def _agent_identifier(data: dict[str, Any]) -> str | None:
    keys = (
        "agent_id",
        "agentId",
        "agent_type",
        "agentType",
        "subagent_type",
        "subagentType",
    )
    for key in keys:
        value = data.get(key)
        if isinstance(value, str) and value:
            return value
    tool_input = data.get("tool_input")
    if isinstance(tool_input, dict):
        for key in (*keys, "name"):
            value = tool_input.get(key)
            if isinstance(value, str) and value:
                return value
    return None


def _has_shell_expansion(value: str) -> bool:
    return any(marker in value for marker in ("$", "`", "*", "?", "[", "~"))


def _literal_command_paths(command: str, cwd: Path) -> tuple[Path, ...]:
    try:
        arguments = shlex.split(command)
    except ValueError:
        return ()
    if any(_has_shell_expansion(argument) for argument in arguments):
        return ()
    return tuple((cwd / argument).resolve(strict=False) for argument in arguments)


def _is_protected_path(path: Path, planning_dir: Path | None) -> bool:
    if path in PROTECTED_FILES:
        return True
    return planning_dir is not None and path.is_relative_to(planning_dir / ".runtime")


def _has_protected_decision_path(
    tool_input: object, cwd: Path | None, planning_dir: Path | None
) -> bool:
    if not isinstance(tool_input, dict):
        return False
    command = tool_input.get("command")
    file_paths = (tool_input.get("file_path"), tool_input.get("notebook_path"))
    values = (command, *file_paths)
    if any(
        isinstance(value, str) and any(marker in value for marker in PROTECTED_MARKERS)
        for value in values
    ):
        return True
    if cwd is None:
        return False
    literal_paths = (
        _literal_command_paths(command, cwd) if isinstance(command, str) else ()
    )
    direct_paths = tuple(
        (cwd / value).resolve(strict=False)
        for value in file_paths
        if isinstance(value, str) and not _has_shell_expansion(value)
    )
    return any(
        _is_protected_path(path, planning_dir)
        for path in (*literal_paths, *direct_paths)
    )


def _is_blocked_while_pending(tool_name: str) -> bool:
    return tool_name not in INSPECTION_TOOLS and tool_name != ASK_TOOL


def _pretool_context(
    data: dict[str, Any],
) -> tuple[str, dict[str, Any], DecisionStore | None, str | None] | str:
    tool_name = data.get("tool_name")
    tool_input = data.get("tool_input")
    if (
        not isinstance(tool_name, str)
        or not tool_name
        or not isinstance(tool_input, dict)
    ):
        return "Hook error: malformed PreToolUse JSON input."
    cwd = _current_directory(data.get("cwd"))
    try:
        planning_dir = _planning_directory(data.get("cwd"))
    except DecisionStateError as error:
        return str(error)
    if _has_protected_decision_path(tool_input, cwd, planning_dir):
        return "Decision runtime access is reserved for trusted hook transitions."
    return (
        tool_name,
        tool_input,
        DecisionStore(planning_dir) if planning_dir else None,
        _session_id(data),
    )


def _open_question(
    data: dict[str, Any], store: DecisionStore, session_id: str
) -> str | None:
    if _agent_identifier(data):
        return (
            "AskUserQuestion is reserved for the main session. "
            "Return a user_decision_required handoff instead."
        )
    question = _validate_question(data.get("tool_input"))
    shape = {"mode": "bounded", **question}
    store.open(session_id, _fingerprint(question, store.planning_dir), shape)
    return None


def _pretool(data: dict[str, Any]) -> str | None:
    context = _pretool_context(data)
    if isinstance(context, str):
        return context
    tool_name, _, store, session_id = context
    if store is None:
        return None
    if session_id is None:
        return (
            "A valid session id is required for user-decision state."
            if tool_name == ASK_TOOL or _is_blocked_while_pending(tool_name)
            else None
        )
    reason = None
    try:
        status = store.state(session_id)
        if status in {"pending", "awaiting_freeform"} and _is_blocked_while_pending(
            tool_name
        ):
            reason = (
                "A user decision is pending. Inspection may continue, but orchestration "
                "and mutation must wait."
            )
        elif tool_name == ASK_TOOL:
            reason = _open_question(data, store, session_id)
    except DecisionStateError as error:
        reason = str(error)
    return reason


def _answer_map(data: dict[str, Any]) -> dict[str, Any] | None:
    for container in (data.get("tool_response"), data.get("tool_input"), data):
        if isinstance(container, dict) and isinstance(container.get("answers"), dict):
            return container["answers"]
    return None


def _posttool(data: dict[str, Any]) -> str | None:
    if data.get("tool_name") != ASK_TOOL:
        return None
    try:
        planning_dir = _planning_directory(data.get("cwd"))
        session_id = _session_id(data)
        _require(
            planning_dir is not None and session_id is not None,
            "The pending user decision record is invalid.",
        )
        planning_dir = cast(Path, planning_dir)
        session_id = cast(str, session_id)
        answers = _answer_map(data)
        if answers is None:
            return None
        store = DecisionStore(planning_dir)
        record, error = _record_for_current_state(store, session_id)
        if error:
            return error
        _require(record is not None, "The pending user decision record is invalid.")
        record = cast(dict[str, Any], record)
        shape = record["response_shape"]
        _require(
            isinstance(shape, dict), "The pending user decision record is invalid."
        )
        question = shape["question"]
        _require(
            isinstance(question, str), "The pending user decision record is invalid."
        )
        answer = answers.get(question)
        _require(isinstance(answer, str), "AskUserQuestion returned an invalid answer.")
        store.answer(session_id, cast(str, answer), str(record["state_fingerprint"]))
    except DecisionStateError as error:
        return str(error)
    return None


def _prompt(data: dict[str, Any]) -> str | None:
    try:
        planning_dir = _planning_directory(data.get("cwd"))
        session_id = _session_id(data)
        prompt = data.get("prompt")
        if planning_dir is None or not isinstance(prompt, str) or not prompt.strip():
            return None
        _require(session_id is not None, "The pending user decision record is invalid.")
        session_id = cast(str, session_id)
        store = DecisionStore(planning_dir)
        if store.state(session_id) == "awaiting_freeform":
            record, error = _record_for_current_state(store, session_id)
            if error:
                return error
            _require(record is not None, "The pending user decision record is invalid.")
            record = cast(dict[str, Any], record)
            store.resolve_freeform(session_id, str(record["state_fingerprint"]))
    except DecisionStateError as error:
        return str(error)
    return None


def _stop(data: dict[str, Any]) -> str | None:
    try:
        planning_dir = _planning_directory(data.get("cwd"))
        if planning_dir is None:
            return None
        session_id = _session_id(data)
        _require(
            session_id is not None,
            "A valid session id is required for user-decision state. Stop is blocked.",
        )
        session_id = cast(str, session_id)
        store = DecisionStore(planning_dir)
        status = store.state(session_id)
        if status in {"pending", "awaiting_freeform"}:
            _, error = _record_for_current_state(store, session_id)
            if error:
                return error
            return (
                "A required user decision is still pending. Present or resume that decision "
                "before stopping."
            )
    except DecisionStateError as error:
        return (
            "The pending user decision record is invalid: "
            f"{error} Stop is blocked until it is repaired."
        )
    return None


def verdict(stdin_text: str, event_name: str) -> str | None:
    data, error = _event(stdin_text)
    if error:
        return error if event_name in {"pretool", "stop"} else None
    if event_name == "pretool":
        return _pretool(data or {})
    if event_name == "posttool":
        return _posttool(data or {})
    if event_name == "prompt":
        return _prompt(data or {})
    if event_name == "stop":
        return _stop(data or {})
    return None


def _read_decision(args: list[str]) -> int:
    if len(args) != READ_DECISION_ARGUMENTS or args[0] not in {"state", "get"}:
        return 2
    command, planning_text, session_id = args
    try:
        store = DecisionStore(Path(planning_text))
        payload = (
            store.state(session_id) if command == "state" else store.record(session_id)
        )
    except DecisionStateError as error:
        sys.stderr.write(f"pending-decision: {error}\n")
        return 2
    _write_output(
        payload
        if isinstance(payload, str)
        else json.dumps(payload, sort_keys=True, separators=(",", ":"))
    )
    return 0


def main() -> None:
    event_name = sys.argv[1] if len(sys.argv) > 1 else ""
    if event_name == "decision-read":
        raise SystemExit(_read_decision(sys.argv[2:]))
    reason = verdict(sys.stdin.read(), event_name)
    if reason is None:
        return
    if event_name == "pretool":
        _write_output(_pretool_denial(reason))
    elif event_name == "posttool":
        _write_output(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PostToolUse",
                        "additionalContext": reason,
                    }
                }
            )
        )
    elif event_name == "stop":
        _write_output(_stop_block(reason))


if __name__ == "__main__":
    main()
