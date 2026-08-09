---
description: Scientific-method investigation of a single reported bug. Spawns debugger solo.
argument-hint: "<bug report, error message, or failing command>"
---

Required first step: read `skills-bundle/ponytail/SKILL.md` under the plugin root (`${CLAUDE_PLUGIN_ROOT}`) and apply the ponytail discipline at level full for the whole task.

One bug per session. If $ARGUMENTS names more than one unrelated problem, run this command once per problem rather than handing `debugger` a bundle.

1. Create `.lbwc-planning/DEBUG-SESSION-{slug}.md` from `templates/DEBUG-SESSION.md`: `session_id` timestamped, `title` a one-line description of the bug, `status: investigating`. Record the bug report, error messages, and reproduction steps from $ARGUMENTS verbatim under Issue, do not paraphrase away details that might matter to reproduction.
2. Build the brief from the Issue section plus `scripts/lib/deviq-digest.sh`. If the issue already names every exact fix path, issue a solo `/debug` command contract with those paths and spawn `debugger`. Otherwise issue a read-only solo `/debug` contract named `debug-{slug}-diagnose`. The first agent may reproduce and diagnose, but it cannot write a fix. Pass the same brief, contract path, and task id to the generator. Advance the contract to `dispatched` before spawning per `@references/agent-spawn-protocol.md`.
3. The diagnostic path returns a causal chain and exact proposed fix paths. The main session checks those paths against the reproduction evidence. It then issues a new solo `/debug` contract named `debug-{slug}-fix` with only those paths, and spawns a fresh debugger with the diagnosis as its brief. The fix agent reproduces, fixes, and verifies. A report with no reproduction or root cause is unfinished.

## Record and hand off

4. Update the session status to `fixed` or `blocked`, then record the main-session commit hash.
   - Record the root cause with `deviq-record.py block` under the phase or session id. Record the fix with `deviq-record.py decision`.
   - Keep each stable block id. Resolve an earlier block by appending a new `status=resolved` record with that id. Never edit the original record.
   - A blocked debugger may use a solo `deviq` advisor. Issue a read-only solo `/debug` command contract named `deviq-debug-{slug}` from the exact question. Advance it to `dispatched` before generation.
5. Tell the user to run `/qa <phase>` if the bug was inside an already-planned phase, otherwise report the fix and the session file path directly.
6. After the main session observes the debugger's causal report and verifies the fixed or blocked session outcome, record one telemetry event with `session-telemetry.py record --event command --outcome success|failure|blocked --phase <phase-or-session-id>`. The debugger never writes telemetry. A report alone is not an observed outcome until the main session checks it.
