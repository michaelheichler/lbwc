---
category: supporting
description: Inspect and configure detected Claude Code models through lbwc-model.
argument-hint: '[--json] <refresh|show|activate|set|copy|validate|catalog> [arguments]'
allowed-tools: Bash, AskUserQuestion
disable-model-invocation: true
---

## Context

Use `${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-model` as the only model and routing interface. Do not edit `.lbwc-planning/config.json` or `.lbwc-planning/claude-capabilities.json`, and do not read model, provider, alias, pricing, or reasoning lists from static configuration. Interactive decisions happen only in the main session through the native question tool.

@${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md

## Guard

Require `lbwc-model` and `.lbwc-planning` to be available. Stop on any nonzero `lbwc-model` result and report its exact error. Do not substitute another model, routing, profile, catalog, configuration, or static data source.

## Steps

When `$ARGUMENTS` is empty, run the interactive main-session flow in this order:

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-model" refresh .lbwc-planning`. Stop and report its exact error on failure.
2. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-model" show .lbwc-planning` and present the complete output before asking for a change.
3. Use native AskUserQuestion for each bounded decision. Build model and reasoning choices only from the refreshed display. Offer no more than three detected choices at once and let the native Other path accept an exact displayed value.
4. Apply the answer with exactly one supported CLI form:
   - `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-model" activate .lbwc-planning <profile>`
   - `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-model" set .lbwc-planning <profile> <role> <selector> <reasoning-json>`
   - `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-model" copy .lbwc-planning <source-profile> <destination-profile>`
5. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-model" validate .lbwc-planning`, then show the updated table.

For reasoning, pass JSON `null` for the Claude Code default. A detected value named `default` is distinct and must be passed as JSON string `"default"`. Encode every other detected reasoning value as a JSON string without changing its spelling.

When `$ARGUMENTS` is present, do not ask questions. Treat it as a deterministic operation and insert `.lbwc-planning` immediately after the operation name. Supported forms are:

- `/lbwc:models [--json] refresh`
- `/lbwc:models [--json] show`
- `/lbwc:models [--json] activate <profile>`
- `/lbwc:models [--json] set <profile> <role> <selector> <reasoning-json>`
- `/lbwc:models [--json] copy <source-profile> <destination-profile>`
- `/lbwc:models [--json] validate`
- `/lbwc:models [--json] catalog`

Pass `--json` before the CLI operation. Return its output unchanged in machine mode.

## Failure and recovery

On refresh, show, activate, set, copy, validate, or catalog failure, show the exact `lbwc-model` error and stop. Do not edit state files, retry through another interface, infer a replacement value, or treat a failed validation as success. After the cause is fixed, rerun the same `lbwc-model` operation.

## Output Format

Interactive mode shows the complete refreshed or updated `lbwc-model show` table and the chosen operation result. Machine mode returns the CLI output unchanged. State the operation and whether validation passed.

## Next Up

After a successful configuration change, end with `Next: continue your current LBWC workflow.` After a failure, end with `Next: fix the reported lbwc-model error, then rerun the same command.`
