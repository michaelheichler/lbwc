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
WORKFLOW_AUTHOR_PATTERN = re.compile(
    r"\b(?:author|write|compose|draft|create|build|generate|produce|emit|make|construct)\w*\s+"
    r"(?:a|the|your|an)?\s*(?:workflow(?:\s+script)?|javascript)\b",
    re.IGNORECASE,
)
WORKFLOW_AUTHOR_NEGATION_PATTERN = re.compile(
    r"\b(?:never|not|no|avoid|don't|do not|does not|doesn't|must not|should not|"
    r"cannot|can't|won't|refrain from)\b",
    re.IGNORECASE,
)
WORKFLOW_SCRIPT_PARAM_PATTERN = re.compile(
    r"\bscript\b[^\n.]{0,60}\b(?:parameter|param|argument)\b[^\n.]{0,60}\bWorkflow\b"
    r"|\bWorkflow\b[^\n.]{0,60}\bpass\w*\b[^\n.]{0,60}\bscript\b"
    r"|\bWorkflow\s*\(\s*\{?[^)]{0,2000}?\bscript\s*[:=]"
    r"|\bscript\b[^\n.]{0,60}\b(?:set|field|key)\b[^\n.]{0,60}\bWorkflow\b",
    re.IGNORECASE,
)
GATED_TOOLS = ("AskUserQuestion", "Agent", "Task", "Workflow")
GATED_TOOL_PATTERNS = {tool: re.compile(rf"\b{tool}\b") for tool in GATED_TOOLS}


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


def load_gated_tool_prose_allowlist(root, path):
    """Load exact (command, tool, phrase) exemptions for confirmed prose collisions.

    Each entry names one command file, one gated tool, and the literal phrase
    whose bare mention of the tool is prose, not an invocation, e.g. the
    phrase "Agent Teams" in commands/config.md. The exemption covers only
    text matching that phrase, so an unrelated mention of the same tool
    elsewhere in the same file is still checked.
    """
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        fail_setup(f"required file is unavailable: {path}")
    allowed = {}
    for number, raw in enumerate(lines, 1):
        entry = raw.strip()
        if not entry or entry.startswith("#"):
            continue
        parts = entry.split(":", 2)
        if len(parts) != 3 or not parts[0] or not parts[2]:
            fail_setup(f"malformed gated-tool allowlist entry at line {number}: {entry}")
        relative_text, tool, phrase = parts
        if not relative_text.endswith(".md") or any(char.isspace() for char in relative_text):
            fail_setup(f"malformed gated-tool allowlist entry at line {number}: {entry}")
        relative_path = Path(relative_text)
        if relative_path.is_absolute() or ".." in relative_path.parts:
            fail_setup(f"unsafe gated-tool allowlist entry at line {number}: {entry}")
        if tool not in GATED_TOOLS:
            fail_setup(f"unknown gated tool in allowlist entry at line {number}: {entry}")
        if not GATED_TOOL_PATTERNS[tool].search(phrase):
            fail_setup(f"gated-tool allowlist phrase does not name its own tool at line {number}: {entry}")
        target = root / relative_path
        if not target.is_file():
            fail_setup(f"stale gated-tool allowlist entry at line {number}: {entry}")
        if phrase not in target.read_text(encoding="utf-8"):
            fail_setup(f"stale gated-tool allowlist phrase, not found in file at line {number}: {entry}")
        allowed.setdefault((relative_path.as_posix(), tool), set()).add(phrase)
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


NEGATION_SCOPE_BOUNDARY_PATTERN = re.compile(r"[.;,](?=\s|$)|\n")


def clause_start(text, position, boundary_pattern=NEGATION_SCOPE_BOUNDARY_PATTERN):
    """Return the index just past the nearest clause boundary before position.

    A period only counts as a boundary when followed by whitespace or end of
    string, so a dotted filename such as workflow-generator.sh does not split
    the clause that names it from the words around it.
    """
    boundary = 0
    for match in boundary_pattern.finditer(text, 0, position):
        boundary = match.end()
    return boundary


def first_unnegated_match(pattern, text):
    """Return the first pattern match whose governing negation is excluded, or None.

    Negation is scoped to the clause containing the match, and a comma ends
    that scope exactly like a period or semicolon. This keeps a comma
    splice such as "Do not wait for the generator, write a workflow script
    yourself." flagged, since its second clause is a new, unnegated
    instruction.
    """
    for match in pattern.finditer(text):
        negation_begin = clause_start(text, match.start())
        negation_clause = text[negation_begin:match.start()]
        if WORKFLOW_AUTHOR_NEGATION_PATTERN.search(negation_clause):
            continue
        return match
    return None


def has_unnegated_match(pattern, text):
    """Return whether a pattern match survives once its governing negation is excluded."""
    return first_unnegated_match(pattern, text) is not None


def validate_workflow_authoring_ban(commands_dir, root):
    """Return commands that instruct the model to author workflow JavaScript or pass an inline script."""
    errors = []
    for path in sorted(commands_dir.glob("*.md")):
        text = path.read_text(encoding="utf-8")
        relative = path.relative_to(root).as_posix()
        if has_unnegated_match(WORKFLOW_AUTHOR_PATTERN, text):
            errors.append(f"{relative}: instructs the model to author a workflow or write JavaScript")
        if has_unnegated_match(WORKFLOW_SCRIPT_PARAM_PATTERN, text):
            errors.append(f"{relative}: instructs passing a script parameter to the Workflow tool")
    return errors


def _frontmatter_body_start_line(lines):
    """Return the 1-indexed line number of the first body line after frontmatter, or 1."""
    if not lines or lines[0] != "---":
        return 1
    for index, line in enumerate(lines[1:], start=1):
        if line == "---":
            return index + 2
    return 1


def _allowed_tools_line(lines, body_start_line):
    """Return the 1-indexed line number of the allowed-tools field, or 1 if absent."""
    for index, line in enumerate(lines[: body_start_line - 1], start=1):
        if line.startswith("allowed-tools:"):
            return index
    return 1


def _granted_tool_names(fields):
    """Return the bare tool names declared in an allowed-tools frontmatter value."""
    value = fields.get("allowed-tools", "")
    return {entry.strip().split("(", 1)[0].strip() for entry in value.split(",")}


def _first_unexempted_match(pattern, body, phrases):
    """Return the first plain match of pattern in body outside every phrase span.

    Matching is intentionally not negation-aware: naming a gated tool at all,
    negated or not, is what a grant audit must surface. A match is exempted
    only when it falls entirely inside one of the literal allowlisted phrases,
    so an unrelated mention elsewhere in the same body is still reported.
    """
    exempt_spans = [
        match.span()
        for phrase in phrases
        for match in re.finditer(re.escape(phrase), body)
    ]
    for candidate in pattern.finditer(body):
        if any(start <= candidate.start() and candidate.end() <= end for start, end in exempt_spans):
            continue
        return candidate
    return None


def validate_gated_tool_grants(commands_dir, root, prose_allowlist):
    """Return commands that name a gated tool in the body without declaring it in allowed-tools."""
    errors = []
    for path in sorted(commands_dir.glob("*.md")):
        text = path.read_text(encoding="utf-8")
        relative = path.relative_to(root).as_posix()
        fields, _ = parse_frontmatter(text)
        granted = _granted_tool_names(fields)
        lines = text.splitlines()
        body_start_line = _frontmatter_body_start_line(lines)
        allowed_line = _allowed_tools_line(lines, body_start_line)
        body = "\n".join(lines[body_start_line - 1 :])
        for tool, pattern in GATED_TOOL_PATTERNS.items():
            if tool in granted:
                continue
            phrases = prose_allowlist.get((relative, tool), ())
            match = _first_unexempted_match(pattern, body, phrases)
            if match is None:
                continue
            body_line = body_start_line + body.count("\n", 0, match.start())
            errors.append(
                f"{relative}: names gated tool {tool} in the body at line {body_line} "
                f"without declaring it in allowed-tools at line {allowed_line}"
            )
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
    gated_tool_allowlist_path = root / "config" / "gated-tool-prose-allowlist.txt"
    manifest = load_json(manifest_path)
    patterns, section_entries = validate_manifest(manifest)
    allowlist = load_allowlist(root, allowlist_path)
    gated_tool_prose_allowlist = load_gated_tool_prose_allowlist(root, gated_tool_allowlist_path)
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
    errors.extend(validate_workflow_authoring_ban(commands_dir, root))
    errors.extend(validate_gated_tool_grants(commands_dir, root, gated_tool_prose_allowlist))
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
