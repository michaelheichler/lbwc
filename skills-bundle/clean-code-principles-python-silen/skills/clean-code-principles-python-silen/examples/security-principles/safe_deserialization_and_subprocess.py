"""Demonstrates: safe deserialization + OS command injection prevention
(ch05 §7.4.7, §7.4.14).

Principles shown:
- Never `pickle.loads` / `yaml.load` untrusted bytes -> arbitrary code execution.
  Use JSON (data-only) and validate the result into a typed model.
- Never pass untrusted data through a shell. Use argument lists with shell=False,
  or a dedicated stdlib function (os.mkdir) instead of os.system("mkdir ...").

Run: uv run --with 'pydantic>=2' python safe_deserialization_and_subprocess.py
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from pathlib import Path

from pydantic import BaseModel, Field, ValidationError


class WebhookEvent(BaseModel):
    """The trusted shape we deserialize untrusted JSON *into*."""

    event_id: str = Field(min_length=1, max_length=64, pattern=r"^[a-zA-Z0-9_-]+$")
    kind: str = Field(min_length=1, max_length=32)
    amount: int = Field(ge=0, le=1_000_000)


def parse_event(raw: bytes) -> WebhookEvent:
    # JSON carries data only -> no code execution. Then validate into a model.
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError("malformed JSON") from exc
    if not isinstance(data, dict):
        raise TypeError("expected a JSON object")
    return WebhookEvent.model_validate(data)


# --- The deserialization mistake this file refuses to make -------------------
def parse_event_INSECURE(raw: bytes) -> object:  # noqa: N802
    """NEVER DO THIS. pickle.loads on untrusted bytes runs attacker code during
    unpickling (via __reduce__). Same hazard: yaml.load without SafeLoader."""
    raise NotImplementedError("pickle/yaml.load on untrusted data is forbidden")


def list_directory(name: str, *, base: Path) -> list[str]:
    """Run an external command WITHOUT a shell. The arg list means `name` is one
    opaque argument. A payload like "x; <destructive-shell-command>" cannot break
    out into shell syntax, because no shell ever interprets it."""
    target = (base / name).resolve()
    # Confine to base: stop path-traversal (`../../etc`).
    if not target.is_relative_to(base.resolve()):
        raise ValueError("path escapes the allowed base directory")
    ls = shutil.which("ls")  # resolve a full path, don't trust PATH ordering
    if ls is None:  # pragma: no cover - platform without `ls`
        raise RuntimeError("`ls` not found on PATH")
    result = subprocess.run(  # noqa: S603  # safe: list-form args, shell=False, target confined to base
        [ls, "-1", str(target)],
        capture_output=True,
        text=True,
        check=False,
        timeout=5,
    )
    return result.stdout.splitlines()


def make_directory(name: str, *, base: Path) -> Path:
    """Prefer a stdlib call over spawning a process at all (book §7.4.7)."""
    if "/" in name or name in {"", ".", ".."}:
        raise ValueError("illegal directory name")
    target = base / name
    target.mkdir(parents=False, exist_ok=True)
    return target


def main() -> None:
    event = parse_event(b'{"event_id": "evt_1", "kind": "charge", "amount": 500}')
    print("parsed event:", event)
    try:
        parse_event(b'{"event_id": "bad id!", "kind": "charge", "amount": 500}')
    except ValidationError:
        print("rejected event with illegal id")

    base = Path(tempfile.mkdtemp())
    try:
        # Shell metacharacters are inert because there is no shell.
        list_directory("x; echo pwned", base=base)
    except ValueError as exc:
        print("blocked traversal/injection:", exc)


if __name__ == "__main__":
    main()
