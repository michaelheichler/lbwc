# Agent Spawn Protocol

This document defines how an LBWC command mints and starts a teammate. Every spawning command follows it. This includes `/lbwc:vibe`, `/lbwc:plan`, `/lbwc:build`, `/lbwc:fix`, `/lbwc:qa`, `/lbwc:research`, `/lbwc:debug`, `/lbwc:docs`, and `/lbwc:map`. Do not duplicate this mechanic at a call site. Cite this file instead.

## Roles

Solo-only: `architect`, `debugger`, `qa`, `scout`.
Pair-capable (each has a `pairsWith` critic in `templates/agent-roles/defaults.json`): `coding-dijkstra` / `coding-dijkstra-critic`, `python-engineer` / `python-critic`, `web-engineer` / `web-code-critic`, `lead` / `lead-critic`.
Trio-capable (`--trio` anchor with a `trios.<role>` entry): `coding-dijkstra`, `python-engineer`, `web-engineer`, each trio adding `test-dev` as the third member.
Oracle-attached (each has an `oracles` entry in `templates/agent-roles/defaults.json` naming a consultative teammate, never a pair or trio member): `web-engineer` → `ux-oracle`. See "Oracle Role Pattern" below.

## Run the generator

Resolve `task-contract.sh` and `agent-generator.sh` from the plugin root. Every generated name requires a shell-issued contract before the generator can render an agent definition or mutate the manifest. Use `issue` for command work and `open` for a PLAN task. Pass the same job text and per-role paths to both scripts.

```bash
w="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts/agent-generator.sh}"
c="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts/task-contract.sh}"
if [ ! -f "$w" ] || [ ! -f "$c" ]
then
  printf '%s\n' 'Unable to resolve LBWC contract or generator script: CLAUDE_PLUGIN_ROOT is not set or incomplete' >&2
  exit 1
fi
CONTRACT_PATH=$(bash "$c" issue "$PROJECT_ROOT" "<task-slug>" --command "<command>" --role "<role>" --team solo --job "$BRIEF" --write-allowance "<exact-path>")
TASK_ID=$(basename "$CONTRACT_PATH" .json)
bash "$w" <role> --job "$BRIEF" --contract "$CONTRACT_PATH" --task-id "$TASK_ID" --write-allowance "<exact-path>"
bash "$c" state "$PROJECT_ROOT" "$TASK_ID" dispatched >/dev/null
```

For a pair, pass `--team pair` to `issue` and `--pair` to the generator. For a trio, pass `--team trio` to `issue` and `--trio` to the generator. Repeat every anchor `--write-allowance` and every `--role-write-allowance role:path` on both calls. A read-only role still needs a contract, with no allowance flags. The writer stores contracts under `.lbwc-planning/.contracts/tasks/` and rejects protected framework paths. Do not hand-author or edit contract JSON.

`issue` assigns a unique shell-owned run group when `--group` is omitted. This lets a command run again without reopening a terminal contract. Pass `--group <exact-group>` only when the calling command already owns a stable grouping identity.

Read every `Agent-call parameters:` block and the `SPAWN_READY <name>` line that follows it. On any `agent-generator:` stderr failure, stop and report the error verbatim. Do not spawn anything.

The spawn guard accepts only a contract that the main session advanced to `dispatched`. It revalidates the source digest, immutable contract digest, task identity, project root, team, role, and per-role allowance. Only then does it change the manifest entry to `running`. A missing, planned, stale, or tampered contract blocks the spawn. The file guard repeats that validation on writes and accepts only `dispatched` or `running` contract state.

`--write-allowance` remains the anchor role's exact allowance. Use `--role-write-allowance <role>:<exact-path>` only for a named member of the generated pair or trio. In a testing trio, give each test path to `test-dev`. The critic gets no write allowance. For a TDD red stage, generate `qa-author` solo with its test paths through `--write-allowance`. `qa-author` is that task's only test owner.

## Admit one task team at a time

Every `/lbwc:build` generator call includes the standalone `--exclusive` option after the role and its other options. This applies to a solo such as `bash "$w" qa-author --job "<brief>" --write-allowance <test-path> --exclusive`, a pair such as `bash "$w" --pair <role> --job "<brief>" --exclusive`, and a trio such as `bash "$w" --trio <role> --job "<brief>" --exclusive`.

Generate one build grouping just in time. A grouping is a solo red stage, a pair, or a trio. Do not call the generator for the next grouping until every manifest member of the current grouping is `used` or `expired`. A TDD `qa-author` must reach `used` or `expired` after its `tests_ready` report and red-stage commit before `/lbwc:build` generates the engineer pair with `--exclusive`. Within a dependency wave, the calling command preserves PLAN order and completes this admission cycle once per grouping. Dependency-wave ordering remains unchanged.

Do not generate the next task's pair or trio until every manifest member of the current task team is `used` or `expired`.

The generator's exclusive admission check, live-agent capacity check, and the spawn guard are failure boundaries, not a scheduler. With `--exclusive`, the generator rejects a new grouping while any manifest entry is `registered` or `running`. Entries in `used` or `expired` do not block exclusive admission. The generator also rejects a grouping that would exceed capacity. If a second group has nevertheless been generated without exclusive admission while an earlier group is still unclaimed, the spawn guard rejects the attempted spawn because another group has not reached `running`, `used`, or `expired`. Stop and report any rejection verbatim instead of retrying around it.

## Spawn together, every time

Spawn every generated name for the admitted team in the same turn: one `Agent(...)` call per name, all in one message (parallel tool calls), never sequential, never a subset. `agent-spawn-guard.sh` blocks an unrelated spawn while a pair or trio is open. Open means not every member has reached `running` yet. It also blocks re-spawning a name that is already `used` or `expired`. Pass `subagent_type: <name>`, `name: <name>`, and the `model` the script printed for that name. Use it exactly as printed, do not re-derive it.

## Guardrails already enforced by this plugin's hooks

Build the brief accordingly instead of hitting these blind:

- The orchestrator is the only authority that mints a manifest-backed task-derived write capability. Generated agents do not declare, negotiate, or summarize a file scope. `file-guard.sh` enforces the manifest entry for each write.
- A missing-role request goes only to the sole main-session orchestrator through the agent's permitted report channel. No generated worker or lead spawns a requested role.
- For a hook repair, derive an exact path allowance from the named failing hook path before generation. The hook repair receives its exact path allowance through the manifest, never a broad `hooks/` allowance.

- `skill_gate.py`: each teammate's first `Write`, `Edit`, or `NotebookEdit` is denied until it has read a bundled skill file from `skills-bundle/`. Expect that as their first read, not a stall.
- `message_scope_guard.py`: non-critic generated teammates cannot `SendMessage` the orchestrator (`"main"`) directly. Only the critic, or `test-dev` in a trio, reports back.
- `test_scope_guard.py`: `coding-dijkstra`, `python-engineer`, and `web-engineer` are denied writes under `tests?/` or to `*.test.*` / `*.spec.*` files. In a non-TDD trio that lane belongs to `test-dev`. In a TDD task, it belongs to the solo `qa-author` red stage. Don't ask the engineer role to also write tests.
- `qa`'s own role definition denies it `Write`, `Edit`, `NotebookEdit`, and `ExitPlanMode`. It reports a verdict, it never touches files.
- `scout`'s own role definition denies it `Edit` and `NotebookEdit`. It writes new research files, it never edits existing ones.
- `debugger`'s own role definition denies `TaskCreate`. It works the single bug itself and does not spawn further.

## Oracle Role Pattern

An oracle is a third kind of teammate alongside the pair (engineer plus critic) and the trio (engineer, critic, and `test-dev`): a domain specialist a primary role consults mid-task for a second opinion, not a reviewer waiting at the end. This section is a template for future oracles beyond UX, not a one-off. The first instance is `ux-oracle`, attached to `web-engineer`.

**Consultative, not gating.** A critic reviews finished work and can block it with a binary verdict (BLOCK/PASS, GREENLIGHT/BLOCK). An oracle never reviews finished work and never renders a verdict. It answers one live judgment question with a specific, grounded recommendation, then stops. The primary agent weighs that opinion the way it would weigh a specialist's second opinion: free to act on it, free to disagree and say why in its own final report. Nothing an oracle says is authoritative, and nothing it says can hold up a handback.

**When to spawn one.** An oracle binds to a primary role at generation time. This is how `pairsWith` binds an engineer to its critic and `trios` adds `test-dev`. The `oracles` map in `templates/agent-roles/defaults.json` names each binding. Generate an oracle only when the task has a matching live judgment call. Give each oracle its own solo command contract and generator call. Spawn the primary group and its oracle names together. Skip the oracle when its domain judgment is not needed.

**How the primary agent invokes it.** The primary agent, and in a trio `test-dev` as well, reaches the oracle by name via `SendMessage`. This is the same peer-to-peer channel `web-engineer` already uses to reach `web-code-critic`. It sends the concrete question and enough context to answer it: the flow, the pattern under consideration, the constraint in tension. The oracle replies once with a grounded recommendation. The primary agent is then free to act on it, or state its own reasoning and disagree. `message_scope_guard.py` only blocks a non-critic role's `SendMessage` to `"main"`. Peer-to-peer messages between spawned teammates already pass, so an oracle needs no hook change to receive or answer a message from its paired primary role.

**What an oracle is not.** It carries no write scope at all, so it does not need the carve-out `test_scope_guard.py` gives `test-dev` over test files, an oracle never touches files in the first place. It produces no artifact and runs no ranked-findings review. A task that needs an artifact (a wireframe, a written persona, a filled brief) belongs to a different, artifact-producing role, not an oracle.

## Ownership

The orchestrator owns git. A spawned agent never runs commit, reset, restore, checkout, stash, or push.

Once spawned, restate the calling command's brief for each teammate, and have pair or trio members coordinate by their generated names via `SendMessage` until the critic (or `test-dev`, in a trio) returns a verdict. A solo role (`architect`, `debugger`, `qa`, `scout`, `lead`) reports directly, there is no critic to wait on. Report the deliverable and, where one exists, the verdict, in one message. If a teammate returns a running status instead, resume it rather than accepting that as the result.
