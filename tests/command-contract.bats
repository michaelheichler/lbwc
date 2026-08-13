#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CHECKER="$REPO_ROOT/scripts/command-contract.sh"
  TEST_ROOT="$(mktemp -d)"
  FIXTURE="$TEST_ROOT/repo"
  mkdir -p "$FIXTURE/commands" "$FIXTURE/config" "$FIXTURE/references" "$FIXTURE/scripts" "$FIXTURE/templates"
  : > "$FIXTURE/config/legacy-identifier-allowlist.txt"
  write_valid_command alpha
  write_manifest alpha.md
}

teardown() {
  rm -rf "$TEST_ROOT"
}

write_valid_command() {
  local command_name=$1
  cat > "$FIXTURE/commands/$command_name.md" <<EOF
---
category: core
description: Exercise the command contract checker.
argument-hint: '[target]'
allowed-tools: Read, Bash
disable-model-invocation: true
---

## Context

The main session owns the interaction.

## Guard

STOP when required state is unavailable.

## Steps

Read the requested target.

## Failure and recovery

Report the error and leave state unchanged.

## Output Format

Print a bounded result.

## Next Up

End with Next guidance.
EOF
}

write_manifest() {
  local command_files=("$@")
  python3 - "$FIXTURE/config/command-sections.json" "${command_files[@]}" <<'PY'
import json
import sys

path, *commands = sys.argv[1:]
manifest = {
    "schema_version": 1,
    "contract_patterns": {
        "interaction": r"(?m)^## Context$",
        "guards": r"(?m)^## Guard$",
        "recovery": r"(?m)^## Failure and recovery$",
        "output": r"(?m)^## Output Format$",
        "next_up": r"(?m)^## Next Up$",
    },
    "commands": {
        command: {
            "required_headings": [
                "Context",
                "Guard",
                "Steps",
                "Failure and recovery",
                "Output Format",
                "Next Up",
            ]
        }
        for command in commands
    },
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle)
PY
}

run_checker() {
  run bash "$CHECKER" --root "$FIXTURE"
}

@test "command-contract accepts a complete command set" {
  run_checker

  [ "$status" -eq 0 ]
  [[ "$output" == *'Command contract passed: 1 commands'* ]]
}

@test "command-contract rejects missing fields, empty values, and obsolete names" {
  write_valid_command beta
  write_manifest alpha.md beta.md
  python3 - "$FIXTURE/commands/alpha.md" <<'PY'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace("category: core", "category:")
text = text.replace("argument-hint: '[target]'\n", "")
open(path, "w", encoding="utf-8").write(text)
PY
  python3 - "$FIXTURE/commands/beta.md" <<'PY'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read().replace("---\ncategory:", "---\nname: lbwc:beta\ncategory:")
open(path, "w", encoding="utf-8").write(text)
PY

  run_checker

  [ "$status" -eq 1 ]
  [[ "$output" == *'alpha.md: empty frontmatter field: category'* ]]
  [[ "$output" == *'alpha.md: missing frontmatter field: argument-hint'* ]]
  [[ "$output" == *'beta.md: frontmatter must not define name'* ]]
}

@test "command-contract rejects command filenames outside the local slug format" {
  write_valid_command Beta
  write_manifest alpha.md Beta.md

  run_checker

  [ "$status" -eq 1 ]
  [[ "$output" == *'Beta.md: command filename must match [a-z0-9][a-z0-9-]*.md'* ]]
}

@test "command-contract rejects unallowlisted legacy identifiers" {
  printf 'Legacy command: /vbw:plan\n' > "$FIXTURE/references/legacy.md"

  run_checker

  [ "$status" -eq 1 ]
  [[ "$output" == *'references/legacy.md: forbidden legacy identifier'* ]]

  printf 'references/legacy.md\n' > "$FIXTURE/config/legacy-identifier-allowlist.txt"
  run_checker
  [ "$status" -eq 0 ]
}

@test "command-contract rejects missing referenced paths" {
  printf '\nUse `scripts/missing-helper.sh` and `references/missing.md`.\n' >> "$FIXTURE/commands/alpha.md"

  run_checker

  [ "$status" -eq 1 ]
  [[ "$output" == *'alpha.md: missing referenced path: scripts/missing-helper.sh'* ]]
  [[ "$output" == *'alpha.md: missing referenced path: references/missing.md'* ]]
}

@test "command-contract resolves globs and documented placeholders" {
  mkdir -p "$FIXTURE/templates/agent-roles"
  printf 'role\n' > "$FIXTURE/templates/agent-roles/dev.md.tpl"
  printf 'profile\n' > "$FIXTURE/references/effort-profile-balanced.md"
  printf '\nUse `templates/agent-roles/*.md.tpl` and `references/effort-profile-{profile}.md`.\n' >> "$FIXTURE/commands/alpha.md"

  run_checker

  [ "$status" -eq 0 ]
}

@test "command-contract rejects manifest drift and missing required sections" {
  write_valid_command beta

  run_checker

  [ "$status" -eq 1 ]
  [[ "$output" == *'command is missing from section manifest: beta.md'* ]]

  write_manifest alpha.md beta.md
  python3 - "$FIXTURE/commands/beta.md" <<'PY'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read().replace("## Next Up", "## Later")
open(path, "w", encoding="utf-8").write(text)
PY
  run_checker
  [ "$status" -eq 1 ]
  [[ "$output" == *'beta.md: missing required heading: Next Up'* ]]
  [[ "$output" == *'beta.md: missing next_up contract'* ]]
}

@test "repository commands satisfy the tracked command contract" {
  run bash "$CHECKER" --root "$REPO_ROOT"

  [ "$status" -eq 0 ]
}
