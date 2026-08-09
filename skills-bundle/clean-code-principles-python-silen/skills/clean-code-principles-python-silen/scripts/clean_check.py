#!/usr/bin/env python3
"""clean_check - enforce *Clean Code: Principles and Patterns, Python Edition*
(Petri Silen, 2024) on Python source.

It runs three layers and merges the results into one principle-linked report:

1. **ruff** - a curated rule selection mapped to the book's principles
   (naming, modern Python, exception handling, security, comprehensions, …).
2. **mypy** - static type checking (the book's "prefer statically typed" + the
   contract guarantees behind clean interfaces).
3. **custom AST rules** (``ast_rules.py``) - the distinctive Silen principles
   generic linters miss (predicate naming, encapsulation leaks, …).

Used two ways:
  * Directly by an agent / human: ``python clean_check.py path/to/file.py``
  * Imported by the MCP server (``check_source`` / ``check_path``) so the agent
    can self-verify code before presenting it, the "never ship a Python defect"
    loop.

Tools are resolved as: an explicit env override → a binary on PATH → ``uvx``
(downloads on first use). If a tool is unavailable its layer is reported as
skipped rather than failing the whole check.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Sequence
from dataclasses import asdict, dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ast_rules import Finding as AstFinding  # noqa: E402
from ast_rules import run_ast_rules  # noqa: E402

# ruff selection -> book principle pointer. Prefix match, longest first.
RUFF_PRINCIPLE: dict[str, str] = {
    "N": "ch03 Uniform Naming Principle",
    "ANN": "ch03 Prefer Statically Typed Language Principle",
    "UP": "ch03 Refactoring / modern Python",
    "TRY": "ch03 Error/Exception Handling Principle",
    "BLE": "ch03 Error/Exception Handling Principle (no blind except)",
    "EM": "ch03 Error/Exception Handling Principle",
    "RSE": "ch03 Error/Exception Handling Principle",
    "B": "ch03 Avoid bugs (mutable defaults, loop bugs)",
    "C4": "ch03 Use Appropriate Data Structure Principle",
    "SIM": "ch03 Refactoring Principle",
    "RET": "ch03 Function Single Return Principle",
    "PTH": "ch03 Use Appropriate Data Structure / stdlib",
    "PERF": "ch03 Optimization Principle",
    "ERA": "ch03 Avoid Comments Principle (no commented-out code)",
    "ARG": "ch03 Clean functions (no unused parameters)",
    "FBT": "ch02 Naming Function Parameters (no boolean trap)",
    "PLR09": "ch02 Single Responsibility Principle (too complex/large)",
    "PLR2004": "ch03 Avoid magic values",
    "PLR": "ch02/ch03 Refactoring & SRP",
    "PLW": "ch03 Coding correctness",
    "PLC": "ch03 Coding conventions",
    "RUF012": "ch02 Encapsulation (no mutable class default)",
    "RUF": "ch03 Coding correctness",
    "S": "ch05 Security Principles",
    "DTZ": "ch03 Coding correctness (timezone-aware datetimes)",
    "T20": "ch10 Observability (use logging, not print)",
    "SLF": "ch02 Encapsulation (no private member access)",
    "I": "ch03 Source Code Structure (import order)",
    "E": "ch03 Readable code",
    "W": "ch03 Readable code",
    "F": "ch03 Coding correctness (pyflakes)",
}

DEFAULT_RUFF_SELECT = (
    "E,W,F,I,N,UP,ANN,B,C4,SIM,RET,PTH,PERF,ERA,ARG,FBT,RUF,S,DTZ,T20,SLF,TRY,BLE,EM,RSE,PLR,PLW,PLC"
)
# Pragmatic ignores. These ruff rules are lint *opinions* the book does not teach
# and that actively fight readability, so enforcing them would be cargo-culting:
#   S101   - assert is fine (and required) in tests
#   EM101/EM102 - "assign the exception message to a variable first": noise that
#                 hurts readability, the book wants good messages, not indirection
#   TRY003 - "no long messages outside the exception class": same, over-strict
#   ANN401 - "no typing.Any": Any is occasionally the honest type (opaque keys, etc.)
DEFAULT_RUFF_IGNORE = "S101,EM101,EM102,TRY003,ANN401"

# Opinionated config applied by default (deterministic, project-independent).
DEFAULT_CONFIG = Path(__file__).resolve().parent / "clean_ruff.toml"

MYPY_ARGS = (
    "--ignore-missing-imports",
    "--check-untyped-defs",
    "--warn-redundant-casts",
    "--warn-unused-ignores",
    "--show-error-codes",
    "--no-error-summary",
    "--no-color-output",
    "--show-column-numbers",
)


@dataclass(frozen=True, slots=True)
class Report:
    path: str
    findings: list[dict]
    counts: dict[str, int]
    tools_run: list[str]
    tools_skipped: list[str]
    clean: bool

    def to_json(self) -> str:
        return json.dumps(asdict(self), indent=2)


def _tool_cmd(name: str) -> list[str] | None:
    """Resolve a tool to a command prefix: env override -> PATH -> uvx."""
    override = os.environ.get(f"CLEAN_CHECK_{name.upper()}")
    if override:
        return override.split()
    found = shutil.which(name)
    if found:
        return [found]
    if shutil.which("uvx"):
        return ["uvx", f"{name}@latest"]
    return None


def _principle_for_ruff(code: str) -> str:
    for prefix in sorted(RUFF_PRINCIPLE, key=len, reverse=True):
        if code.startswith(prefix):
            return RUFF_PRINCIPLE[prefix]
    return "ch03 Coding Principles"


def _ruff_rule_args(select: str | None, ignore: str | None, config: Path | None) -> list[str]:
    """Prefer the opinionated config file, fall back to explicit select/ignore."""
    if config is not None and config.is_file():
        return ["--config", str(config)]
    args: list[str] = []
    if select:
        args += ["--select", select]
    if ignore:
        args += ["--ignore", ignore]
    return args


def _run_ruff(target: Path, select: str | None, ignore: str | None,
              config: Path | None) -> tuple[list[dict], bool]:
    cmd = _tool_cmd("ruff")
    if cmd is None:
        return [], False
    proc = subprocess.run(  # noqa: S603
        [*cmd, "check", *_ruff_rule_args(select, ignore, config),
         "--output-format", "json", "--no-cache", str(target)],
        capture_output=True, text=True, check=False,
    )
    findings: list[dict] = []
    try:
        for item in json.loads(proc.stdout or "[]"):
            code = item.get("code") or "RUFF"
            findings.append({
                "tool": "ruff",
                "rule_id": code,
                "severity": "warning",
                "line": (item.get("location") or {}).get("row", 0),
                "col": (item.get("location") or {}).get("column", 0),
                "message": item.get("message", ""),
                "principle": _principle_for_ruff(code),
                "fixable": bool(item.get("fix")),
            })
    except json.JSONDecodeError:
        pass
    return findings, True


def _run_ruff_format_check(target: Path, config: Path | None) -> tuple[list[dict], bool]:
    cmd = _tool_cmd("ruff")
    if cmd is None:
        return [], False
    cfg = ["--config", str(config)] if config is not None and config.is_file() else []
    proc = subprocess.run(  # noqa: S603
        [*cmd, "format", "--check", *cfg, "--no-cache", str(target)],
        capture_output=True, text=True, check=False,
    )
    if proc.returncode != 0 and "would reformat" in (proc.stdout + proc.stderr):
        return [{
            "tool": "ruff-format", "rule_id": "FMT", "severity": "info",
            "line": 1, "col": 1,
            "message": "File is not ruff-formatted. Run `ruff format`.",
            "principle": "ch03 Static Code Analysis Principle", "fixable": True,
        }], True
    return [], True


def _run_mypy(target: Path) -> tuple[list[dict], bool]:
    cmd = _tool_cmd("mypy")
    if cmd is None:
        return [], False
    proc = subprocess.run(  # noqa: S603
        [*cmd, *MYPY_ARGS, str(target)],
        capture_output=True, text=True, check=False,
    )
    findings: list[dict] = []
    for line in proc.stdout.splitlines():
        # path:line:col: severity: message  [code]
        parts = line.split(":", 4)
        if len(parts) < 5 or parts[3].strip() not in {"error", "note", "warning"}:
            continue
        sev = parts[3].strip()
        if sev == "note":
            continue
        msg = parts[4].strip()
        try:
            ln, col = int(parts[1]), int(parts[2])
        except ValueError:
            ln, col = 0, 0
        findings.append({
            "tool": "mypy", "rule_id": "type",
            "severity": "error" if sev == "error" else "warning",
            "line": ln, "col": col, "message": msg,
            "principle": "ch03 Prefer Statically Typed Language Principle", "fixable": False,
        })
    return findings, True


def check_source(source: str, filename: str = "snippet.py", *,
                 ruff_select: str = DEFAULT_RUFF_SELECT,
                 ruff_ignore: str = DEFAULT_RUFF_IGNORE,
                 ruff_config: Path | None = DEFAULT_CONFIG,
                 run_mypy: bool = True) -> Report:
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / Path(filename).name
        p.write_text(source, encoding="utf-8")
        return _check_target(p, display=filename, ruff_select=ruff_select,
                             ruff_ignore=ruff_ignore, ruff_config=ruff_config,
                             run_mypy=run_mypy)


def check_path(path: str | Path, *, ruff_select: str = DEFAULT_RUFF_SELECT,
               ruff_ignore: str = DEFAULT_RUFF_IGNORE,
               ruff_config: Path | None = DEFAULT_CONFIG,
               run_mypy: bool = True) -> Report:
    p = Path(path)
    return _check_target(p, display=str(p), ruff_select=ruff_select,
                         ruff_ignore=ruff_ignore, ruff_config=ruff_config,
                         run_mypy=run_mypy)


def _check_target(target: Path, *, display: str, ruff_select: str,
                  ruff_ignore: str, ruff_config: Path | None, run_mypy: bool) -> Report:
    findings: list[dict] = []
    tools_run: list[str] = []
    tools_skipped: list[str] = []

    rf, ok = _run_ruff(target, ruff_select, ruff_ignore, ruff_config)
    (tools_run if ok else tools_skipped).append("ruff")
    findings += rf
    fmt, ok = _run_ruff_format_check(target, ruff_config)
    if ok:
        findings += fmt

    if run_mypy:
        mf, ok = _run_mypy(target)
        (tools_run if ok else tools_skipped).append("mypy")
        findings += mf

    # custom AST rules (one file or every .py under a dir)
    py_files = [target] if target.is_file() else sorted(target.rglob("*.py"))
    for f in py_files:
        try:
            src = f.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for af in run_ast_rules(src, str(f)):
            d = _finding_to_dict(af)
            if target.is_dir():
                d["message"] = f"{f}: {d['message']}"
            findings.append(d)
    tools_run.append("clean-ast")

    findings.sort(key=lambda d: (d["line"], d["col"], d["rule_id"]))
    counts = {"error": 0, "warning": 0, "info": 0}
    for d in findings:
        counts[d["severity"]] = counts.get(d["severity"], 0) + 1
    clean = counts["error"] == 0 and counts["warning"] == 0
    return Report(display, findings, counts, tools_run, tools_skipped, clean)


def _finding_to_dict(f: AstFinding) -> dict:
    return {
        "tool": f.tool, "rule_id": f.rule_id, "severity": f.severity,
        "line": f.line, "col": f.col, "message": f.message,
        "principle": f.principle, "fixable": False,
    }


def _format_text(report: Report) -> str:
    lines = [f"clean_check: {report.path}"]
    if not report.findings:
        lines.append("  ✓ clean, no findings")
    else:
        for d in report.findings:
            mark = {"error": "✗", "warning": "▲", "info": "·"}.get(d["severity"], "-")
            lines.append(
                f"  {mark} {d['line']}:{d['col']} [{d['tool']}:{d['rule_id']}] "
                f"{d['message']}  →  {d['principle']}"
            )
    c = report.counts
    lines.append(f"  {c['error']} errors, {c['warning']} warnings, {c['info']} info")
    if report.tools_skipped:
        lines.append(f"  (skipped: {', '.join(report.tools_skipped)})")
    return "\n".join(lines)


def main(argv: Sequence[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Enforce Silen's clean-code principles on Python.")
    ap.add_argument("path", help="Python file or directory to check")
    ap.add_argument("--json", action="store_true", help="emit JSON")
    ap.add_argument("--no-mypy", action="store_true", help="skip type checking")
    ap.add_argument("--select", default=None,
                    help="override ruff rule selection (disables the opinionated config)")
    ap.add_argument("--ignore", default=None, help="override ruff rule ignores")
    args = ap.parse_args(argv)

    # An explicit --select/--ignore opts out of the bundled config.
    if args.select or args.ignore:
        config: Path | None = None
        select = args.select or DEFAULT_RUFF_SELECT
        ignore = args.ignore or DEFAULT_RUFF_IGNORE
    else:
        config = DEFAULT_CONFIG
        select, ignore = DEFAULT_RUFF_SELECT, DEFAULT_RUFF_IGNORE

    report = check_path(args.path, ruff_select=select, ruff_ignore=ignore,
                        ruff_config=config, run_mypy=not args.no_mypy)
    print(report.to_json() if args.json else _format_text(report))
    return 1 if not report.clean else 0


if __name__ == "__main__":
    raise SystemExit(main())
