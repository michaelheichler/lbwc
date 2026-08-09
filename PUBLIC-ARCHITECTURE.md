# LBWC Public Architecture

LBWC is a Claude Code plugin for disciplined software delivery. The human owns direction. The main session owns orchestration. Generated agents receive only shell-issued work contracts.

## One user route

```text
/lbwc:init once
    |
/lbwc:vibe for every next step
    |
LBWC routes the active phase through planning, build, QA, and UAT
```

`/lbwc:vibe` reads the project state, identifies one missing artifact, asks for confirmation, and dispatches the route that owns that work. Users do not have to manage the pipeline stages themselves.

## System shape

```text
Human
  -> scope, priorities, acceptance, and release decisions
Main Claude Code session
  -> routing, contracts, artifact persistence, and Git
Shell control plane
  -> contract, capability, lifecycle, and artifact checks
Generated agents
  -> one bounded task and structured evidence
Project artifacts
  -> durable plans, results, and decisions
```

The control plane uses local files, small scripts, hooks, JSON, Markdown artifacts, and local locks. It does not require a server, queue, database, or remote telemetry service.

## Ownership model

| Owner | Owns | Does not own |
| --- | --- | --- |
| Human | Scope, priorities, approvals, UAT, release decisions | Routine orchestration work |
| Main session | Routing, contracts, artifact persistence, commits, Git | Worker implementation scope |
| Generated agent | One assigned task and its evidence | Planning authority, contract changes, Git, release actions |
| Shell guards | Validation and admission decisions | Product direction or autonomous planning |

Agent output is evidence, not authority. The framework protects the human from agent drift.

## Durable project state

LBWC stores workflow state under `.lbwc-planning/` in the target project.

| Artifact | Purpose |
| --- | --- |
| `PROJECT.md` | Project identity and operating context |
| `REQUIREMENTS.md` | Accepted requirements |
| `ROADMAP.md` | Phases and completion state |
| `STATE.md` | Compact current-state summary |
| `phases/<phase>/PLAN.md` | Reviewed phase plan |
| `phases/<phase>/SUMMARY.md` | Build result and evidence |
| `phases/<phase>/VERIFICATION.md` | Main-session QA result |
| `phases/<phase>/UAT.md` | Human acceptance record |

`/lbwc:vibe` reads these artifacts in order. It stops at the first missing or invalid stage. It does not mark work complete from an agent claim alone.

## Task contracts

Before an agent starts, the main session creates a shell-owned contract. The contract binds:

- task identity and source plan digest
- selected role, team shape, and job
- exact repository-relative write paths for each writable role
- allowed lifecycle transitions
- primary workspace

The generator validates the contract before it renders an agent definition or registers the agent. The spawn guard validates it again before work starts. The file guard validates it before every write reaches the workspace.

```text
planned -> dispatched -> running -> awaiting_review -> verified
                                      |
                                      -> blocked or cancelled
```

Invalid transitions fail closed. A worker cannot add paths, change roles, edit contract records, or promote its own result.

## Team boundaries

LBWC uses the smallest team that matches the work:

- A solo specialist handles a bounded planning, research, QA, debug, or documentation task.
- An engineer and critic pair handles implementation and independent review.
- A trio adds `test-dev` when the task has separate test-path ownership.

Only one generated grouping is active at a time. The next grouping waits until every current member is `used` or `expired`. Critics have no write allowance. Test owners receive test paths only. The main session owns commits and final artifact writes.

## Enforcement

| Boundary | Protects | Enforcement |
| --- | --- | --- |
| Contract validation | Task, role, team, path, and plan identity | Contract writer, generator, spawn guard |
| File capability | Exact writes in the primary workspace | File guard on Write, Edit, and NotebookEdit |
| Test ownership | Product code and test-path separation | Test scope guard and contracts |
| Worker lifecycle | Active work, idle expiry, exclusive admission | Manifest lock and lifecycle script |
| Command admission | Git, shell evaluation, critical commands, control paths | Bash guard |
| Main-session persistence | Verification and remediation artifacts | Deterministic writers and locked state scripts |

Command admission is not an operating-system sandbox. It blocks recognized generated-agent command routes and protected control paths. LBWC does not claim that a lexical shell check can confine every arbitrary executable or child process.

## Quality and evidence

Agents return typed handoffs and evidence. The main session validates that material before it changes durable state.

- Plans are reviewed before build work begins.
- Build summaries identify completed task evidence.
- QA returns a structured verdict. The main session writes `VERIFICATION.md`.
- UAT remains a human checkpoint.
- Failed QA or UAT opens a bounded remediation round with explicit stage state.

The DevIQ ledger records local decisions, evidence, and blocks in append-only hash-chained JSONL files. It is advisory. It does not route work, grant permissions, or accept a phase.

## Status and telemetry

The statusline is read-only. It reads Claude Code supplied fields when available and combines them with local project state. It shows phase progress, team status, QA or UAT state, and telemetry health. It does not call an API or read credentials.

An idle teammate is observed for 120 seconds. LBWC then revalidates the manifest, contract, and idle token before returning native stop guidance. It does not send process signals, delete output, or clear ownership without a valid state transition.

Session telemetry is local and advisory. The main session writes bounded, hash-chained events. Events never contain prompts, transcripts, tool payloads, secrets, or uploaded data.

## Distribution and release

The repository is a Claude Code marketplace. Its `.claude-plugin/` manifest declares LBWC and remains versioned.

Release metadata stays synchronized across `VERSION`, plugin metadata, marketplace metadata, and `CHANGELOG.md`. `scripts/release-verify.sh` checks local release readiness. Publishing, tagging, history changes, and repository visibility remain explicit maintainer actions.

## Verification

Run the local checks with:

```bash
claude plugin validate .
rtk bats tests/
bash scripts/release-verify.sh
```

These checks verify the local plugin and control plane. They do not claim a hosted service, a remote execution environment, or a universal process sandbox.
