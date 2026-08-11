---
name: lbwc:config
category: supporting
disable-model-invocation: true
description: View and modify LBWC configuration including effort profile, verification tier, and skill-hook wiring.
argument-hint: "[setting value]"
allowed-tools: Read, Write, Edit, Bash, Glob, AskUserQuestion
---

# LBWC Config $ARGUMENTS

## Context

Plugin root:

```
!`L="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; R="$L/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || { echo "LBWC: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; bash "$R" >/dev/null || exit 1; echo "$L"`
```

Store the plugin root path output above as `{plugin-root}` for use in script and config lookups below. Replace `{plugin-root}` with the literal `Plugin root` value from Context whenever a step below references a script or file in the installed plugin.

@${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md

Config:

```
!`cat .lbwc-planning/config.json 2>/dev/null || echo "No config found -- run /lbwc:init first"`
```

## Guard

If no .lbwc-planning/ dir: STOP "Run /lbwc:init first." (check `.lbwc-planning/config.json`)

## Behavior

Every ordinary setting mutation runs `bash "{plugin-root}/scripts/lbwc-config.sh" set .lbwc-planning <setting> <value-json>`, followed by `lbwc-config.sh validate`. The only routing setting exposed here is `routing.active_profile`, which mutates through `lbwc-model activate`, not through direct JSON writes.

### Step 0 (always): validate and migrate configuration

Run `bash "{plugin-root}/scripts/lbwc-config.sh" migrate .lbwc-planning`, then `bash "{plugin-root}/scripts/lbwc-config.sh" validate .lbwc-planning`. A nonzero result stops the command and leaves the invalid file for explicit repair. Do not silently replace it with defaults. Validate routing profiles separately with `bash "{plugin-root}/scripts/lbwc-model" validate .lbwc-planning`.

### No arguments: Interactive configuration

**Step 1:** Display current settings in single-line box table (setting, value, description) + skill-hook mappings.

Before any presentation, run `bash "{plugin-root}/scripts/lbwc-model" --json refresh .lbwc-planning`.

Present the detected routing state by running `bash "{plugin-root}/scripts/lbwc-model" --json show .lbwc-planning`. Render its active profile and each supported role's selector, reasoning value, and turn limit. Mark custom profiles as custom. Do not resolve roles through static profile files or assign cost weights.

**Step 2:** AskUserQuestion with 1 question:

- header: `Config`
- question: `What would you like to adjust?`
- options:
  - `Core settings`: Effort, autonomy, planning tracking, auto push
  - `Model profile`: Preset profile or per-agent overrides
  - `Exit`: Leave config unchanged

Store selection in variable `CONFIG_SECTION`.

Every bounded AskUserQuestion branch below follows `references/ask-user-question.md`: accept direct option intent, accept unambiguous visible option-by-number replies (for example `#1`, `option 2`, or `2`), accept hybrid replies anchored to one visible option number (for example `#2 please`), re-ask only when the reply is ambiguous or invalid for that same question, and do not add an extra visible `Other` option.

If `CONFIG_SECTION = "Exit"`:

- Display `✓ No changes made.`
- Run `bash "{plugin-root}/scripts/suggest-next.sh" config` and display.
- STOP.

**Step 2.5:** If `CONFIG_SECTION = "Core settings"`, AskUserQuestion with 1 question:

- header: `Core`
- question: `Which core setting do you want to change?`
- options:
  - `Effort`: current: {effort value}  (thorough | balanced | fast | turbo)
  - `Autonomy`: current: {autonomy value}  (cautious | standard | confident | pure-vibe)
  - `Planning tracking`: current: {tracking value}  (manual | ignore | commit)
  - `Auto push`: current: {auto_push value}  (never | after_phase | always)

Store selection in variable `SETTING_GROUP`.

Map:

- `Effort` → `SETTING=effort`
- `Autonomy` → `SETTING=autonomy`
- `Planning tracking` → `SETTING=planning_tracking`
- `Auto push` → `SETTING=auto_push`

**Step 2.6:** Ask the bounded value question for the selected core setting.

If `SETTING=effort`, AskUserQuestion with 1 question:

- header: `Effort`
- question: `Choose effort level.`
- options:
  - `thorough`: Maximum planning and verification depth
  - `balanced`: Default depth for most work
  - `fast`: Lighter planning, quicker verification
  - `turbo`: Minimal ceremony, fastest path

If `SETTING=autonomy`, AskUserQuestion with 1 question:

- header: `Autonomy`
- question: `Choose autonomy level.`
- options:
  - `cautious`: Confirm more often
  - `standard`: Default phase-by-phase flow
  - `confident`: Fewer confirmations
  - `pure-vibe`: Full auto loop through phases

If `SETTING=planning_tracking`, AskUserQuestion with 1 question:

- header: `Tracking`
- question: `How should planning artifacts be tracked?`
- options:
  - `manual`: Leave planning files for manual git handling
  - `ignore`: Keep `.lbwc-planning/` out of git
  - `commit`: Auto-commit planning artifacts

If `SETTING=auto_push`, AskUserQuestion with 1 question:

- header: `Auto push`
- question: `When should LBWC push automatically?`
- options:
  - `never`: Never push automatically
  - `after_phase`: Push once after each phase
  - `always`: Push after every commit

Store the selected value in variable `VALUE`.

After a core setting value is chosen, continue to Step 3 and apply it there with the same validation, write behavior, and side effects as the `/lbwc:config <setting> <value>` path below. Step 4 remains the no-args tail behavior after that shared apply step.

**Step 2.7:** If `CONFIG_SECTION = "Model profile"`, AskUserQuestion with 1 question:

- header: `Models`
- question: `How do you want to configure model behavior?`
- options:
  - `Use preset profile`: quality, balanced, or budget
  - `Configure each agent individually`: 6 per-agent model questions
  - `Model matrix`: Re-detect available models and rebuild the agent x effort matrix

Store selection in variable `PROFILE_METHOD`.

**Branching:**

- If `PROFILE_METHOD = "Use preset profile"`: AskUserQuestion with 1 question and 3 options (`quality`, `balanced`, `budget`). Store the selected preset in `PROFILE`, then continue to Step 3 and apply it there using the `Model profile switching` logic below.
- If `PROFILE_METHOD = "Configure each agent individually"`: Proceed to individual agent configuration flow (Round 1 below).
- If `PROFILE_METHOD = "Model matrix"`: run the model matrix flow below, then continue to Step 4.

**Detected model configuration:**

Run `bash "{plugin-root}/scripts/lbwc-model" --json refresh .lbwc-planning`, then `bash "{plugin-root}/scripts/lbwc-model" --json show .lbwc-planning`. The detected Claude catalog, accepted reasoning values, built-in profiles, active profile, and custom profiles in that output are authoritative. Do not read or write a static model-price, alias, matrix, or reasoning file.

- **Use preset profile:** Show only built-in profile names from the `show` result. Confirm one bounded choice, then run `lbwc-model activate .lbwc-planning <profile>`.
- **Configure each agent individually:** Read the active profile and catalog from `show` and `catalog`. Ask one bounded question at a time for each supported role. Every selector and reasoning value must appear in the detected catalog. Apply each accepted cell through `lbwc-model set .lbwc-planning <profile> <role> <selector> <reasoning-json>`.
- **Model matrix:** Copy the active profile to a user-named custom profile with `lbwc-model copy`, edit its role cells through `lbwc-model set`, validate it, then activate it. Do not create a parallel matrix schema.

Native Other text may name a detected selector or profile. Reject an unknown value with the exact validation error and keep the current profile unchanged. Every mutation must end with `lbwc-model validate .lbwc-planning` and a fresh `lbwc-model show .lbwc-planning`. On Cancel, make no model mutation and return to Step 2.7.

**Step 3:** Apply changes to config.json. This is the shared apply step for no-args core-setting changes and preset-model-profile changes. Display ✓ per changed setting with ➜. No changes: "✓ No changes made."

**Step 4: Profile drift detection**: if effort/autonomy/verification_tier changed:

- Compare against active profile's expected values
- If mismatch: AskUserQuestion "Settings no longer match '{profile}'. Save as new profile?" → "Save" (route to /lbwc:profile save) or "No" (set active_profile to "custom")
- Skip if no profile-tracked settings changed or already "custom"

Run `bash "{plugin-root}/scripts/suggest-next.sh" config` and display.

### With arguments: `<setting> <value>`

Validate setting + value. Update config.json. Display ✓ with ➜.

If `setting=max_uat_remediation_rounds`, validate the value before writing:

```bash
CANONICAL_VALUE=$(bash "{plugin-root}/scripts/resolve-uat-remediation-round-limit.sh" --validate-input "$2" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "${CANONICAL_VALUE:-}" ]; then
  echo "⚠ Invalid max_uat_remediation_rounds '$2'. Valid values: false, 0, or a positive integer"
  exit 0
fi

jq ".max_uat_remediation_rounds = ${CANONICAL_VALUE}" .lbwc-planning/config.json > .lbwc-planning/config.json.tmp && mv .lbwc-planning/config.json.tmp .lbwc-planning/config.json
echo "✓ max_uat_remediation_rounds ➜ ${CANONICAL_VALUE}"
exit 0
```

If `setting=planning_tracking`, after writing config run:

```bash
  PG_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
  if [ -f "$PG_SCRIPT" ]; then
    bash "$PG_SCRIPT" sync-ignore .lbwc-planning/config.json
  else
    echo "⚠ LBWC: planning-git.sh unavailable. Skipping .gitignore sync." >&2
  fi
```

This applies any mode-specific root `.gitignore` behavior and keeps `.lbwc-planning/.gitignore` current for transient runtime files in every tracking mode.

### Skill-hook wiring: `skill_hook <skill> <event> <tools>`

- `config skill_hook lint-fix PostToolUse Write|Edit`
- `config skill_hook test-runner PostToolUse Bash`
- `config skill_hook remove <skill>`

Stored in config.json `skill_hooks`:

```json
{"skill_hooks": {"lint-fix": {"event": "PostToolUse", "tools": "Write|Edit"}}}
```

### Model profile switching: `model_profile <profile>`

Run `bash "{plugin-root}/scripts/lbwc-model" activate .lbwc-planning "$PROFILE"`, then validate and show the result. The helper accepts built-in and valid custom profiles from the detected catalog. An unknown profile exits nonzero and leaves the active profile unchanged.

### Per-agent route: `model_override <role> <selector> [reasoning-json]`

Read the active profile with `lbwc-model --json show`. Validate the role, selector, and optional reasoning value against `lbwc-model --json catalog`. Apply the cell through `lbwc-model set .lbwc-planning <active-profile> <role> <selector> <reasoning-json>`, then run `lbwc-model validate`. Never write model routing fields directly with jq.

## Settings Reference

Note: `auto_commit` controls source-task commits during Execute mode. Planning artifact commit behavior is controlled by `planning_tracking`.

| Setting | Type | Values | Default |
| ------- | ---- | ------ | ------- |
| effort | string | thorough/balanced/fast/turbo | balanced |
| autonomy | string | cautious/standard/confident/pure-vibe | standard |
| auto_commit | boolean | true/false | true |
| planning_tracking | string | manual/ignore/commit | manual |
| auto_push | string | never/after_phase/always | never |
| verification_tier | string | quick/standard/deep | standard |
| skill_suggestions | boolean | true/false | true |
| auto_install_skills | boolean | true/false | false |
| discovery_questions | boolean | true/false | true |
| discussion_mode | string | questions/assumptions/auto | questions |
| visual_format | string | unicode/ascii | unicode |
| max_tasks_per_plan | number | 1-7 | 5 |
| prefer_teams | string | always/auto/never | auto |
| pipeline_research | boolean | true/false | false |
| branch_per_milestone | boolean | true/false | false |
| plain_summary | boolean | true/false | true |
| active_profile | string | profile name or "custom" | default |
| custom_profiles | object | user-defined profiles | {} |
| agent_max_turns | object | per-agent turns (number), 0/false = unlimited | scout=15, qa=25, architect=30, debugger=80, lead=50, dev=75 |
| qa_skip_agents | array | array of agent role names | ["docs"] |
| context_compiler | boolean | true/false | true |
| metrics | boolean | true/false | true |
| token_budgets | boolean | true/false; validated and persisted as the token-budget flag | true |
| two_phase_completion | boolean | true/false; validated and persisted as the two-phase completion flag | true |
| smart_routing | boolean | true/false; validated and persisted as the smart-routing flag | true |
| validation_gates | boolean | true/false; validated and persisted as the validation-gates flag | true |
| snapshot_resume | boolean | true/false; validated and persisted as the snapshot/resume flag | true |
| lease_locks | boolean | true/false; validated and persisted as the lease-lock flag | true |
| event_recovery | boolean | true/false; validated and persisted as the event-recovery flag | true |
| worktree_isolation | string | off/on | off |
| monorepo_routing | boolean | true/false; validated and persisted as the monorepo-routing flag | true |
| require_phase_discussion | boolean | true/false | false |
| auto_uat | boolean | true/false | false |
| max_uat_remediation_rounds | boolean/number | false, 0, or positive integer | false |
| rolling_summary | boolean | true/false | false |
| debug_logging | boolean | true/false | false |
| statusline_hide_limits | boolean | true/false | false |
| statusline_hide_limits_for_api_key | boolean | true/false | false |
| statusline_hide_agent_in_tmux | boolean | true/false | false |
| statusline_collapse_agent_in_tmux | boolean | true/false | false |
| caveman_style | string | none/lite/full/ultra/auto | none |
| caveman_commit | boolean | true/false | false |
| caveman_review | boolean | true/false | false |

### Statusline switches

Four flags control what the LBWC statusline shows:

- **`statusline_hide_limits`**: Suppress the Limits line (L3) unconditionally. Use this if you never want to see token limit information in the statusline.

- **`statusline_hide_limits_for_api_key`**: Suppress the Limits line only when authenticated via an API key (not via Claude.ai OAuth). Useful when you find the usage display redundant in API-key sessions. Has no effect when `statusline_hide_limits` is also `true` (the broader flag takes precedence).

- **`statusline_hide_agent_in_tmux`**: Suppress the Build/agent progress line (L1) while inside a tmux session. Has no effect outside tmux or when no build is running. Use this to reduce statusline noise in tmux-based workflows.

- **`statusline_collapse_agent_in_tmux`**: Collapse the full 4-line statusline into a single summary line in agent/worktree panes (not the orchestrator). Only applies inside tmux, only when running in a git worktree. Has no effect outside tmux or in the main repo pane.

### agent_max_turns

Controls the generated agent definition's internal turn limit. `scripts/resolve-agent-settings.sh` resolves and validates the value before generation. The Agent call itself receives no unsupported turn-limit field.

Set a per-agent value to `false` or `0` for no generated turn limit:

```json
{
  "agent_max_turns": {
    "dev": false,
    "debugger": 0
  }
}
```

You can also provide per-effort overrides using an object instead of a number:

```json
{
  "agent_max_turns": {
    "dev": { "thorough": 120, "balanced": 75, "fast": 50, "turbo": false }
  }
}
```

### max_uat_remediation_rounds

Controls only the UAT remediation auto-continuation loop after re-verification finds issues. It does **not** apply to QA remediation.

Accepted values:

- `false`: unlimited UAT remediation rounds
- `0`: unlimited UAT remediation rounds
- positive integer: finite UAT remediation round cap

Injected default is `false`, and runtime fallback is also unlimited when the persisted value is absent or malformed. `/lbwc:config` rejects malformed interactive input instead of writing it.

Finite cap example:

```json
{
  "max_uat_remediation_rounds": 3
}
```

Unlimited example:

```json
{
  "max_uat_remediation_rounds": false
}
```

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/lbwc-brand-essentials.md: single-line box, ✓ success, ⚠ invalid, ➜ transitions, no ANSI.

## Next Up

After a successful mutation, show the validated current value and suggest `/lbwc:config` to review all settings. Stop after one suggestion.
