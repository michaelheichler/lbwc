#!/usr/bin/env python3
"""DevIQ-lite append-only hash-chained JSONL recorder."""

import argparse
import fcntl
import hashlib
import json
import math
import os
import sys
import time
from datetime import datetime, timezone

KIND_TO_FILE = {
    "decision": "decisions.jsonl",
    "evidence": "evidence.jsonl",
    "block": "blocks.jsonl",
}

# ponytail: fixed cap, configurable only if a real project needs more than 8
MAX_OPEN_BLOCKS_PER_PHASE = 8
DEFAULT_LOCK_TIMEOUT_SECONDS = 0.25
MAX_LOCK_TIMEOUT_SECONDS = 1.0
LOCK_POLL_SECONDS = 0.01
LOCK_TIMEOUT_EXIT_CODE = 2


class RecordLockTimeoutError(TimeoutError):
    pass


def parse_field(raw: str) -> tuple[str, str]:
    if "=" not in raw:
        raise ValueError(f"malformed --field (expected key=value): {raw!r}")
    key, _, value = raw.partition("=")
    if not key:
        raise ValueError(f"malformed --field (empty key): {raw!r}")
    return key, value


def record_sha256(record: dict) -> str:
    payload = {k: v for k, v in record.items() if k != "sha256"}
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def last_sha256(fileobj) -> str | None:
    fileobj.seek(0)
    last_line = None
    for line in fileobj:
        line = line.strip()
        if line:
            last_line = line
    if last_line is None:
        return None
    return json.loads(last_line)["sha256"]


def _write_chained_line(fileobj, record: dict) -> str:
    record["prev_sha256"] = last_sha256(fileobj)
    record["sha256"] = record_sha256(record)
    fileobj.seek(0, os.SEEK_END)
    fileobj.write(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n")
    fileobj.flush()
    os.fsync(fileobj.fileno())
    return record["sha256"]


def lock_timeout_seconds() -> float:
    raw_timeout = os.environ.get("LBWC_DEVIQ_RECORD_LOCK_TIMEOUT")
    if raw_timeout is None:
        return DEFAULT_LOCK_TIMEOUT_SECONDS
    try:
        timeout = float(raw_timeout)
    except ValueError:
        return DEFAULT_LOCK_TIMEOUT_SECONDS
    if not math.isfinite(timeout):
        return DEFAULT_LOCK_TIMEOUT_SECONDS
    return min(max(timeout, 0.0), MAX_LOCK_TIMEOUT_SECONDS)


def acquire_record_lock(fd: int) -> None:
    deadline = time.monotonic() + lock_timeout_seconds()
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pass
        else:
            return
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise RecordLockTimeoutError
        time.sleep(min(LOCK_POLL_SECONDS, remaining))


def append_record(target_path: str, record: dict) -> str:
    os.makedirs(os.path.dirname(target_path), exist_ok=True)
    fd = os.open(target_path, os.O_CREAT | os.O_RDWR, 0o644)
    try:
        acquire_record_lock(fd)
        with os.fdopen(fd, "r+", closefd=False) as fileobj:
            return _write_chained_line(fileobj, record)
    finally:
        os.close(fd)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="deviq-record.py")
    parser.add_argument("kind", choices=sorted(KIND_TO_FILE))
    parser.add_argument("--phase", required=True)
    parser.add_argument("--role", required=True)
    parser.add_argument("--field", action="append", default=[], dest="fields")
    parser.add_argument(
        "--root",
        default=".lbwc-planning/deviq",
        help="directory holding the jsonl files (default: .lbwc-planning/deviq)",
    )
    return parser.parse_args(argv)


def build_record(args: argparse.Namespace, extra_fields: dict) -> dict:
    return {
        "ts": datetime.now(timezone.utc).isoformat(),
        "phase": args.phase,
        "role": args.role,
        "kind": args.kind,
        **extra_fields,
    }


def normalize_trigger(trigger: str) -> str:
    return " ".join(trigger.lower().split())


def compute_block_id(phase: str, trigger: str) -> str:
    payload = f"{phase}\n{normalize_trigger(trigger)}"
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:12]


def _iter_json_records(path: str):
    if not os.path.isfile(path):
        return
    with open(path) as fileobj:
        for line in fileobj:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def latest_open_block_ids(path: str, phase: str) -> set[str]:
    latest_status: dict[str, str] = {}
    for record in _iter_json_records(path):
        if record.get("phase") != phase:
            continue
        record_id = record.get("id") or record.get("trigger")
        if record_id is None:
            continue
        latest_status[record_id] = record.get("status")
    return {record_id for record_id, status in latest_status.items() if status == "open"}


def apply_block_id(args: argparse.Namespace, extra_fields: dict) -> str:
    block_id = extra_fields.get("id") or compute_block_id(
        args.phase, extra_fields.get("trigger", "")
    )
    extra_fields["id"] = block_id
    return block_id


def check_block_open_limits(
    args: argparse.Namespace, extra_fields: dict, target_path: str, block_id: str
) -> "int | None":
    if extra_fields.get("status") != "open":
        return None
    open_ids = latest_open_block_ids(target_path, args.phase)
    if block_id in open_ids:
        print(block_id)
        return 0
    if len(open_ids) < MAX_OPEN_BLOCKS_PER_PHASE:
        return None
    listed = ", ".join(sorted(open_ids))
    print(
        f"deviq-record: phase {args.phase!r} already has "
        f"{MAX_OPEN_BLOCKS_PER_PHASE} open blocks: {listed}",
        file=sys.stderr,
    )
    return 1


def _verify_line(path: str, line_no: int, line: str, prev_sha256: "str | None") -> "str | None":
    try:
        record = json.loads(line)
        stored_sha256 = record["sha256"]
    except (json.JSONDecodeError, KeyError) as error:
        return f"{path}:{line_no}: {error}"
    if record.get("prev_sha256") != prev_sha256:
        return f"{path}:{line_no}: prev_sha256 does not match prior record"
    if record_sha256(record) != stored_sha256:
        return f"{path}:{line_no}: sha256 does not match record contents"
    return None


def _verify_file(path: str) -> "str | None":
    prev_sha256 = None
    with open(path) as fileobj:
        for line_no, raw_line in enumerate(fileobj, start=1):
            line = raw_line.strip()
            if not line:
                continue
            error = _verify_line(path, line_no, line, prev_sha256)
            if error is not None:
                return error
            prev_sha256 = json.loads(line)["sha256"]
    return None


def verify_chain(root: str) -> int:
    for filename in KIND_TO_FILE.values():
        path = os.path.join(root, filename)
        if not os.path.isfile(path):
            continue
        error = _verify_file(path)
        if error is not None:
            print(f"deviq-record: verify failed at {error}", file=sys.stderr)
            return 1
    return 0


def parse_verify_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="deviq-record.py verify")
    parser.add_argument(
        "--root",
        default=".lbwc-planning/deviq",
        help="directory holding the jsonl files (default: .lbwc-planning/deviq)",
    )
    return parser.parse_args(argv)


def _prepare_block(args: argparse.Namespace, extra_fields: dict, target_path: str) -> "int | None":
    block_id = apply_block_id(args, extra_fields)
    return check_block_open_limits(args, extra_fields, target_path, block_id)


def _write_record(args: argparse.Namespace, extra_fields: dict, target_path: str) -> int:
    record = build_record(args, extra_fields)
    try:
        digest = append_record(target_path, record)
    except RecordLockTimeoutError:
        sys.stderr.write("deviq-record: timed out waiting for record lock\n")
        return LOCK_TIMEOUT_EXIT_CODE
    except Exception as error:  # noqa: BLE001 - fail-fast CLI, report and exit non-zero
        print(f"deviq-record: failed to write record: {error}", file=sys.stderr)
        return 1
    print(extra_fields.get("id", digest) if args.kind == "block" else digest)
    return 0


def main(argv: list[str]) -> int:
    if argv and argv[0] == "verify":
        verify_args = parse_verify_args(argv[1:])
        return verify_chain(verify_args.root)

    args = parse_args(argv)

    try:
        extra_fields = dict(parse_field(raw) for raw in args.fields)
    except ValueError as error:
        print(f"deviq-record: {error}", file=sys.stderr)
        return 1

    target_path = os.path.join(args.root, KIND_TO_FILE[args.kind])

    if args.kind == "block":
        early_exit = _prepare_block(args, extra_fields, target_path)
        if early_exit is not None:
            return early_exit

    return _write_record(args, extra_fields, target_path)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
