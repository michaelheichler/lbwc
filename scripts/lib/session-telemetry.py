#!/usr/bin/env python3
"""Bounded, local, append-only telemetry for the sole main session."""
from __future__ import annotations

import argparse, fcntl, hashlib, json, math, os, sys, time
from datetime import datetime, timezone
from pathlib import Path

EVENTS = {"session_start", "session_stop", "phase_start", "phase_end", "command", "tool_call"}
OUTCOMES = {"success", "failure", "partial", "blocked"}
FIELDS = {"ts", "session_id", "actor", "event", "outcome", "duration_ms", "tokens_in", "tokens_out", "model", "phase", "prev_sha256", "sha256"}
RAW = {"transcript", "prompt", "tool", "tool_input", "tool_output", "payload", "content", "message"}
MAX_VALUE = 256
MAX_LINE = 4096
LOCK_TIMEOUT = 0.25

class TelemetryError(Exception): pass

def planning_root(raw: str | None = None) -> Path:
    value = raw or os.environ.get("LBWC_PLANNING_DIR", ".lbwc-planning")
    if not value or "\x00" in value:
        raise TelemetryError("invalid planning root")
    return Path(value).expanduser().resolve()

def target(root: str | None = None) -> Path:
    return planning_root(root) / "telemetry" / "session.jsonl"

def digest(record: dict) -> str:
    body = {k: v for k, v in record.items() if k != "sha256"}
    return hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":")).encode()).hexdigest()

def validate(record: dict, *, chain_prev=None) -> None:
    if not isinstance(record, dict) or set(record) - FIELDS or FIELDS - set(record):
        raise TelemetryError("record schema rejected")
    if any(k in record for k in RAW): raise TelemetryError("raw payload key rejected")
    if record.get("actor") != "main": raise TelemetryError("actor must be main")
    if record.get("event") not in EVENTS: raise TelemetryError("invalid event")
    if record.get("outcome") not in OUTCOMES: raise TelemetryError("invalid outcome")
    if chain_prev is not None and record.get("prev_sha256") != chain_prev: raise TelemetryError("hash chain mismatch")
    if digest(record) != record.get("sha256"): raise TelemetryError("sha256 mismatch")
    for key, value in record.items():
        if isinstance(value, str) and len(value) > MAX_VALUE: raise TelemetryError("value exceeds limit")
    duration = record.get("duration_ms")
    if duration is not None and (not isinstance(duration, (int, float)) or isinstance(duration, bool) or not math.isfinite(duration) or duration < 0): raise TelemetryError("invalid duration")

def read_chain(path: Path) -> list[dict]:
    if not path.exists(): return []
    rows=[]; prev=None
    with path.open(encoding="utf-8") as fh:
        for no, line in enumerate(fh, 1):
            if not line.strip(): continue
            if len(line.encode()) > MAX_LINE: raise TelemetryError(f"record line {no} exceeds limit")
            try: record=json.loads(line)
            except json.JSONDecodeError as exc: raise TelemetryError(f"malformed prior record at line {no}") from exc
            validate(record, chain_prev=prev)
            if prev is None and record.get("prev_sha256") is not None:
                raise TelemetryError(f"genesis record at line {no} must have null prev_sha256")
            prev=record["sha256"]; rows.append(record)
    return rows

def acquire(fd: int) -> None:
    try: configured = float(os.environ.get("LBWC_TELEMETRY_LOCK_TIMEOUT", LOCK_TIMEOUT))
    except ValueError: configured = LOCK_TIMEOUT
    if not math.isfinite(configured): configured = LOCK_TIMEOUT
    deadline=time.monotonic()+min(max(configured, 0.0), 1.0)
    while True:
        try: fcntl.flock(fd, fcntl.LOCK_EX|fcntl.LOCK_NB); return
        except BlockingIOError:
            if time.monotonic() >= deadline: raise TelemetryError("timed out waiting for telemetry lock")
            time.sleep(.01)

def record(args) -> int:
    path=target(args.root); path.parent.mkdir(parents=True, exist_ok=True)
    fd=os.open(path, os.O_CREAT|os.O_RDWR, 0o644)
    try:
        acquire(fd); rows=read_chain(path); prev=rows[-1]["sha256"] if rows else None
        rec={"ts":datetime.now(timezone.utc).isoformat(), "session_id":args.session_id, "actor":"main", "event":args.event, "outcome":args.outcome, "duration_ms":args.duration_ms, "tokens_in":args.tokens_in, "tokens_out":args.tokens_out, "model":args.model, "phase":args.phase, "prev_sha256":prev}
        rec["sha256"]=digest(rec); encoded=json.dumps(rec, sort_keys=True, separators=(",", ":"))
        validate(rec, chain_prev=prev)
        if len(encoded.encode()) > MAX_LINE: raise TelemetryError("record exceeds size limit")
        with os.fdopen(fd, "a", closefd=False) as fh: fh.write(encoded+"\n"); fh.flush(); os.fsync(fh.fileno())
        print(rec["sha256"]); return 0
    except (TelemetryError, ValueError, OSError) as exc: print(f"telemetry: {exc}", file=sys.stderr); return 2
    finally: os.close(fd)

def report(args) -> int:
    try: rows=read_chain(target(args.root))
    except TelemetryError as exc: print(f"telemetry: tamper detected: {exc}"); return 2
    durations=sorted(r["duration_ms"] for r in rows if isinstance(r.get("duration_ms"), (int,float)))
    def pct(p):
        if not durations: return None
        return durations[min(len(durations)-1, max(0, math.ceil(p*len(durations))-1))]
    counts={"events":{},"outcomes":{}}
    for r in rows:
        counts["events"][r["event"]]=counts["events"].get(r["event"],0)+1; counts["outcomes"][r["outcome"]]=counts["outcomes"].get(r["outcome"],0)+1
    print(json.dumps({"total":len(rows), **counts, "p50_ms":pct(.5), "p95_ms":pct(.95)}, sort_keys=True, separators=(",", ":"))); return 0

def main(argv=None):
    p=argparse.ArgumentParser(); sub=p.add_subparsers(dest="command", required=True)
    r=sub.add_parser("record"); r.add_argument("--event", required=True); r.add_argument("--outcome", required=True); r.add_argument("--duration-ms", type=float, default=None); r.add_argument("--tokens-in", type=int, default=None); r.add_argument("--tokens-out", type=int, default=None); r.add_argument("--model", default=None); r.add_argument("--phase", default=None); r.add_argument("--session-id", default=None); r.add_argument("--root"); r.set_defaults(func=record)
    q=sub.add_parser("report"); q.add_argument("--root"); q.set_defaults(func=report)
    args=p.parse_args(argv)
    if args.command == "record" and (args.event not in EVENTS or args.outcome not in OUTCOMES): print("telemetry: invalid enum", file=sys.stderr); return 2
    return args.func(args)
if __name__ == "__main__": raise SystemExit(main())
