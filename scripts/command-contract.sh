#!/usr/bin/env bash
# Cross-file command contracts need this gate because Claude Code validates each Markdown file in isolation.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"

if [ "$#" -gt 0 ]; then
  if [ "$#" -ne 2 ] || [ "$1" != "--root" ]; then
    printf '%s\n' \
      'Usage: command-contract.sh [--root PATH]' \
      'Input: a plugin checkout. Default: the checkout containing this script.' \
      'Output: validation errors or one passing summary. The checkout is never modified.' \
      'Exit 0: pass. Exit 1: contract violation. Exit 2: invalid invocation or unavailable tooling.' >&2
    exit 2
  fi
  ROOT=$2
fi

if ! command -v python3 >/dev/null 2>&1; then
  printf 'command-contract: python3 is required\n' >&2
  exit 2
fi

exec python3 - "$ROOT" <<'PY'
import glob
import json
import re
import sys
from pathlib import Path

REQUIRED_FIELDS = (
    "category",
    "description",
    "argument-hint",
    "allowed-tools",
    "disable-model-invocation",
)
REQUIRED_CONTRACTS = ("interaction", "guards", "recovery", "output", "next_up")
SCAN_DIRECTORIES = ("commands", "references", "templates", "scripts", "hooks", "config", ".claude-plugin")
SCAN_FILES = ("README.md", "PUBLIC-ARCHITECTURE.md")
REFERENCE_PATTERN = re.compile(
    r"(?<![A-Za-z0-9_.-])((?:scripts|references|templates)/[A-Za-z0-9_./${}*?+-]+)"
)
LEGACY_PATTERN = re.compile(r"vbw", re.IGNORECASE)


def fail_setup(message):
    """Report an invocation or repository setup failure that prevents validation."""
    print(f"command-contract: {message}", file=sys.stderr)
    raise SystemExit(2)


def load_json(path):
    """Load a required JSON object or stop before reporting partial contract results."""
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except OSError:
        fail_setup(f"required file is unavailable: {path}")
    except json.JSONDecodeError as error:
        fail_setup(f"invalid JSON in {path}: {error}")
    if not isinstance(value, dict):
        fail_setup(f"JSON root must be an object: {path}")
    return value


def parse_frontmatter(text):
    """Return top-level scalar fields and duplicate keys from a Markdown header."""
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        return {}, []
    fields = {}
    duplicates = []
    for line in lines[1:]:
        if line == "---":
            return fields, duplicates
        if not line or line[0].isspace() or ":" not in line:
            continue
        key, value = line.split(":", 1)
        if key in fields:
            duplicates.append(key)
        fields[key] = value.strip()
    return {}, duplicates


def scalar_is_empty(value):
    """Treat empty YAML scalar spellings as empty without requiring a YAML dependency."""
    return value.strip() in {"", "''", '""', "[]", "{}", "null", "~"}


def section_has_body(text, heading):
    """Require content below an exact level-two heading before the next peer heading."""
    marker = f"## {heading}"
    lines = text.splitlines()
    try:
        start = lines.index(marker) + 1
    except ValueError:
        return False
    for line in lines[start:]:
        if line.startswith("## "):
            break
        if line.strip():
            return True
    return False


def referenced_paths(text):
    """Extract static or glob-like release paths from command prose and shell snippets."""
    return sorted({match.group(1).rstrip(".,:;)'\"`") for match in REFERENCE_PATTERN.finditer(text)})


def reference_exists(root, reference):
    """Resolve documented placeholders as globs while keeping checks inside the repository."""
    if ".." in Path(reference).parts:
        return False
    pattern = re.sub(r"\$?\{[^}/]+\}", "*", reference)
    if pattern == reference and not any(token in reference for token in "*?["):
        return (root / reference).exists()
    return bool(glob.glob(str(root / pattern)))


def load_allowlist(root, path):
    """Load exact repo-relative file exemptions and reject unsafe or stale entries."""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        fail_setup(f"required file is unavailable: {path}")
    allowed = set()
    for number, raw in enumerate(lines, 1):
        entry = raw.strip()
        if not entry or entry.startswith("#"):
            continue
        relative = Path(entry)
        if relative.is_absolute() or ".." in relative.parts:
            fail_setup(f"unsafe allowlist entry at line {number}: {entry}")
        if not (root / relative).is_file():
            fail_setup(f"stale allowlist entry at line {number}: {entry}")
        allowed.add(relative.as_posix())
    return allowed


def release_files(root):
    """Yield shipped plugin files while excluding test fixtures and planning history."""
    seen = set()
    for directory in SCAN_DIRECTORIES:
        base = root / directory
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*")):
            if path.is_file():
                relative = path.relative_to(root).as_posix()
                if relative not in seen:
                    seen.add(relative)
                    yield path
    for filename in SCAN_FILES:
        path = root / filename
        if path.is_file() and filename not in seen:
            yield path


def validate_manifest(manifest):
    """Validate the section manifest shape before applying its regular expressions."""
    if manifest.get("schema_version") != 1:
        fail_setup("command section manifest schema_version must be 1")
    patterns = manifest.get("contract_patterns")
    commands = manifest.get("commands")
    if not isinstance(patterns, dict) or set(patterns) != set(REQUIRED_CONTRACTS):
        fail_setup("command section manifest must define all contract_patterns")
    if not isinstance(commands, dict):
        fail_setup("command section manifest commands must be an object")
    compiled = {}
    for contract in REQUIRED_CONTRACTS:
        pattern = patterns[contract]
        if not isinstance(pattern, str) or not pattern:
            fail_setup(f"empty contract pattern: {contract}")
        try:
            compiled[contract] = re.compile(pattern)
        except re.error as error:
            fail_setup(f"invalid contract pattern {contract}: {error}")
    for filename, entry in commands.items():
        if not isinstance(filename, str) or not filename.endswith(".md") or not isinstance(entry, dict):
            fail_setup("each command manifest entry must map a Markdown filename to an object")
        headings = entry.get("required_headings")
        if not isinstance(headings, list) or not headings or any(not isinstance(item, str) or not item for item in headings):
            fail_setup(f"required_headings must be a nonempty string array: {filename}")
    return compiled, commands


def validate_command(path, root, entry, patterns):
    """Return every discovery, reference, and section violation for one command."""
    text = path.read_text(encoding="utf-8")
    fields, duplicates = parse_frontmatter(text)
    errors = []
    for key in sorted(set(duplicates)):
        errors.append(f"{path.name}: duplicate frontmatter field: {key}")
    for field in REQUIRED_FIELDS:
        if field not in fields:
            errors.append(f"{path.name}: missing frontmatter field: {field}")
        elif scalar_is_empty(fields[field]):
            errors.append(f"{path.name}: empty frontmatter field: {field}")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*\.md", path.name):
        errors.append(f"{path.name}: command filename must match [a-z0-9][a-z0-9-]*.md")
    if "name" in fields:
        errors.append(f"{path.name}: frontmatter must not define name")
    for reference in referenced_paths(text):
        if not reference_exists(root, reference):
            errors.append(f"{path.name}: missing referenced path: {reference}")
    if entry:
        lines = text.splitlines()
        for heading in entry["required_headings"]:
            marker = f"## {heading}"
            if marker not in lines:
                errors.append(f"{path.name}: missing required heading: {heading}")
            elif not section_has_body(text, heading):
                errors.append(f"{path.name}: empty required section: {heading}")
        for contract, pattern in patterns.items():
            if not pattern.search(text):
                errors.append(f"{path.name}: missing {contract} contract")
    return errors


def validate_legacy_identifiers(root, allowlist, allowlist_path):
    """Return shipped files that retain a legacy identifier without an explicit exemption."""
    errors = []
    allowlist_relative = allowlist_path.relative_to(root).as_posix()
    for path in release_files(root):
        relative = path.relative_to(root).as_posix()
        if relative == allowlist_relative or relative in allowlist:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if LEGACY_PATTERN.search(text):
            errors.append(f"{relative}: forbidden legacy identifier")
    return errors


def main():
    """Validate the repository command contract and return its documented status code."""
    root = Path(sys.argv[1]).resolve()
    if not root.is_dir():
        fail_setup("root is not a directory")
    commands_dir = root / "commands"
    if not commands_dir.is_dir():
        fail_setup("commands directory is unavailable")

    manifest_path = root / "config" / "command-sections.json"
    allowlist_path = root / "config" / "legacy-identifier-allowlist.txt"
    manifest = load_json(manifest_path)
    patterns, section_entries = validate_manifest(manifest)
    allowlist = load_allowlist(root, allowlist_path)
    command_paths = sorted(commands_dir.glob("*.md"))
    command_names = {path.name for path in command_paths}
    errors = []

    for filename in sorted(command_names - set(section_entries)):
        errors.append(f"command is missing from section manifest: {filename}")
    for filename in sorted(set(section_entries) - command_names):
        errors.append(f"section manifest names a missing command: {filename}")

    for path in command_paths:
        errors.extend(validate_command(path, root, section_entries.get(path.name), patterns))

    errors.extend(validate_legacy_identifiers(root, allowlist, allowlist_path))
    unique_errors = sorted(set(errors))
    if unique_errors:
        for error in unique_errors:
            print(error, file=sys.stderr)
        print(f"Command contract failed: {len(unique_errors)} violation(s)", file=sys.stderr)
        return 1
    print(f"Command contract passed: {len(command_paths)} commands")
    return 0


raise SystemExit(main())
PY
