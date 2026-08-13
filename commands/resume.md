---
category: supporting
disable-model-invocation: true
description: Restore project context from .lbwc-planning/ state.
argument-hint: "[session-or-phase]"
allowed-tools: Read, Bash, Glob
---

# LBWC Resume

## Context

Working directory:
```
!`pwd`
```
Plugin root:
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.lbwc-plugin-root-link-${SESSION_KEY}"; R="$L/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || { echo "LBWC: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; bash "$R" >/dev/null || exit 1; bash "$L/scripts/phase-detect.sh" > "/tmp/.lbwc-phase-detect-${SESSION_KEY}.txt" 2>/dev/null || echo "phase_detect_error=true" > "/tmp/.lbwc-phase-detect-${SESSION_KEY}.txt"; echo "$L"`
```

Pre-computed state (via phase-detect.sh):
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"
L="/tmp/.lbwc-plugin-root-link-${SESSION_KEY}"
P="/tmp/.lbwc-phase-detect-${SESSION_KEY}.txt"
PD=""
_refresh_phase_detect() {
  local resolver root
  resolver="$L/scripts/resolve-plugin-root.sh"
  if [ ! -f "$resolver" ]; then
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-plugin-root.sh" ]; then
      resolver="${CLAUDE_PLUGIN_ROOT}/scripts/resolve-plugin-root.sh"
    else
      return 1
    fi
  fi
  root=$(bash "$resolver" --require-script phase-detect.sh 2>/dev/null) || return 1
  PD=$(bash "$root/scripts/phase-detect.sh" 2>/dev/null) || PD=""
  if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]; then
    return 1
  fi
  printf '%s' "$PD" > "$P"
  return 0
}
if ! _refresh_phase_detect
then
  PD="phase_detect_error=true"
  printf '%s\n' "$PD" > "$P"
fi
[ -f "$P" ] && PD=$(cat "$P")
if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]; then
  printf '%s' "$PD"
else
  echo "phase_detect_error=true"
fi`
```

## Guard

1. **Not initialized** (no .lbwc-planning/ dir): STOP "Run /lbwc:init first."
2. **Brownfield normalization:** If Pre-computed state (from Context above) contains `misnamed_plans=true`, normalize all phase directories before proceeding:
   ```bash
   NORM_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
   if [ -f "$NORM_SCRIPT" ]; then
     for pdir in .lbwc-planning/phases/*/; do
       [ -d "$pdir" ] && bash "$NORM_SCRIPT" "$pdir"
     done
   fi
   ```
   Display: "⚠ Renamed misnamed plan files to `{NN}-PLAN.md` convention."
   Then re-run phase-detect.sh to refresh state:
   ```bash
   bash "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/phase-detect.sh" > "/tmp/.lbwc-phase-detect-${CLAUDE_SESSION_ID:-default}.txt"
   ```
   Use the refreshed phase-detect output for all subsequent steps.
3. **No roadmap:** `.lbwc-planning/ROADMAP.md` missing → STOP: "No roadmap found. Run /lbwc:vibe."
4. **Phase-detect error:** If output contains `phase_detect_error=true`, display: "⚠ Phase detection failed. Run phase-detect.sh manually to debug." and STOP.

## Steps

1. **Read ground truth from active planning state only.** Never read archived milestone state.

   Project state:
   - `.lbwc-planning/PROJECT.md`, name and core value
   - `.lbwc-planning/STATE.md`, decisions, todos, and blockers
   - `.lbwc-planning/ROADMAP.md`, phases overview
   - `.lbwc-planning/RESUME.md`, session notes

   Execution evidence:
   - Canonical PLAN and SUMMARY files under `.lbwc-planning/phases/`
   - The most recent terminal SUMMARY
   - Task contracts and generated-agent manifest state when a build may be interrupted

   Skip missing optional files. A missing required PLAN, contract, or terminal summary remains a blocker.
2. **Compute progress from phase-detect.sh output:** Use the pre-computed `phase_count`, `next_phase`, `next_phase_state`, `next_phase_plans`, `next_phase_summaries`, `uat_issues_phase`, `uat_issues_slug`, `uat_issues_phases`, and `uat_issues_count` values. Map `next_phase_state` to display: `needs_uat_remediation` → "⚠ Needs remediation", `needs_verification` → "⏳ Needs UAT verification", `needs_plan_and_execute` → "not started", `needs_execute` → "in progress", `all_done` → "complete". **Per-phase status:** any phase whose number appears in the comma-separated `uat_issues_phases` list has unresolved UAT issues, mark it "⚠ Needs remediation". Only mark a phase as "✓ Done" if its number is NOT in `uat_issues_phases` and it has completed execution (SUMMARY count ≥ PLAN count). Phases not yet executed are "not started".
   **Known issues check:** For each phase directory, run:
   ```bash
   bash "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/track-known-issues.sh" promote-todos "{phase-dir}" 2>/dev/null || true
   bash "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/track-known-issues.sh" status "{phase-dir}" 2>/dev/null
   ```
   Parse `known_issues_count` from the status output. For each phase with `known_issues_count > 0`, include in the dashboard after the phase table: `⚠ Phase {NN}: N known issue(s) deferred, run /lbwc:list-todos to review`. Omit for phases with zero known issues. The `promote-todos` call is a backfill, it ensures any known issues not yet in `STATE.md ## Todos` are promoted on resume.
3. **Detect interrupted builds:** Query task contracts and the generated-agent manifest. A contract in `dispatched`, `running`, `awaiting_review`, or `blocked`, or a generated member still `registered` or `running`, means the build is incomplete. Confirm the corresponding PLAN, commits, verify results, and terminal SUMMARY before choosing recovery.
4. **Present dashboard:** Phase Banner "Context Restored / {project name}" with: core value, phase/progress, overall progress bar, key decisions, todos, blockers (⚠), last completed, build status (✓ completed / ⚠ interrupted), session notes. Run `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh resume`.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/lbwc-brand-essentials.md, double-line box, Metrics Block, ⚠ warnings, ✓ completions, ➜ Next Up, no ANSI.

## Next Up

Run `scripts/suggest-next.sh resume` and display its exact LBWC command. Stop without starting it.
