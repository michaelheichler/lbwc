---
description: Dashboard. Reports current phase, in-flight pair or trio work, and what /vibe would do next. No spawn.
argument-hint: ""
---

No ponytail preamble here: this command only reads and reports, there is nothing to build.

1. Read `.lbwc-planning/.agent-manifest.json`. List every entry whose `pair_id` is set and not every member has reached `used` or `expired`: name, role, state, for each open pair or trio. If none, say so plainly.
2. Read `.lbwc-planning/STATE.md` and `.lbwc-planning/ROADMAP.md`'s Progress table. Report the current phase, its `Done/Total` plan count, and its status.
3. For the current phase, check which of `PLAN.md`, `SUMMARY.md`, `VERIFICATION.md`, `UAT.md` exist under `.lbwc-planning/phases/{NN}-{slug}/` and their status fields, the same check `/vibe` itself runs.
4. State in one line what `/vibe` would do if run right now: which command it would dispatch to, or that a pair or trio needs to finish first. Do not run that command yourself, this is a read-only report.
5. Include the read-only telemetry summary by running `bash "${CLAUDE_PLUGIN_ROOT}/scripts/telemetry-report.sh" --root .lbwc-planning`. Do not record telemetry or mutate state from `/status`. Report a telemetry error as an error, not as an empty report.
