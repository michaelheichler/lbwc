<p align="center">
  <img src="assets/lbwc.png" alt="LBWC, written with love and guarded by contracts" width="720">
</p>

<p align="center">
  <a href="https://code.claude.com/docs/en/plugins"><img src="https://img.shields.io/badge/Claude%20Code-2.1.226%2B-D97757?logo=anthropic&logoColor=white" alt="Claude Code 2.1.226 or newer verified"></a>
  <img src="https://img.shields.io/badge/tests-706%20passing-2EA44F" alt="706 local tests passing">
  <img src="https://img.shields.io/badge/release-local%20verification%20passed-2EA44F" alt="Local release verification passed">
</p>

<h1 align="center">Love Better With Claude</h1>

LBWC is a Claude Code plugin for planning, building, QA, and UAT with one clear rule: the human owns the direction, the main session owns orchestration, and generated agents get only the work they were issued.

LBWC keeps the useful parts of a multi-agent workflow without asking you to become a full-time air traffic controller. It turns a project into a small, visible sequence of artifacts, contracts, checks, and decisions. Workers help with bounded tasks. They do not get to rewrite the plan, mint broader permissions, commit changes, or wander into a spare worktree for a little unsupervised character growth.

## Quick start

LBWC is verified with Claude Code 2.1.226 and up until Anthropic (or myself at 3 after midnight) breaks something. Add the marketplace:

```bash
claude plugin marketplace add michaelheichler/lbwc
```

...then install it:

```bash
claude plugin install lbwc@lbwc-marketplace
```

For a project-wide install, add `--scope project` to either command. Confirm the install with:

```bash
claude plugin list
```

Open Claude Code in the project you want to work on. Run setup once, then use `/lbwc:vibe` for the rest of the project:

```text
/lbwc:init
/lbwc:vibe
```

`/lbwc:init` creates LBWC planning state. After that, `/lbwc:vibe` is the **only** LBWC command you need to drive the work. It reads the actual state, names the next missing artifact, asks for confirmation, and dispatches to the command that owns that step. Use `claude plugin marketplace update lbwc-marketplace` and `claude plugin update lbwc@lbwc-marketplace` to update. Use `claude plugin uninstall lbwc@lbwc-marketplace` to remove it.

## One command after setup

The user-facing loop is small:

```text
/lbwc:init once
   |
/lbwc:vibe for every next step
   |
LBWC routes /lbwc:plan -> /lbwc:build -> /lbwc:qa -> /lbwc:uat
```

You use `/lbwc:vibe` whenever you want the next step. It reads the actual artifacts and does not invent a new project plan because a worker had an exciting thought at 02:17.

For a feature, the interaction is usually this:

1. Run `/lbwc:init` once in a new project.
2. Run `/lbwc:vibe`, review the proposed next action, and approve it when it matches your intent.
3. Run `/lbwc:vibe` again when the current step ends.
4. Accept the phase after LBWC has routed it through planning, build, QA, and UAT.

Give `/lbwc:vibe` a focused brief when you have one:

```text
/lbwc:vibe Fix expired coupon checkout.
/lbwc:vibe Research payment retry behavior.
/lbwc:vibe Document CLI configuration.
```

## What `/lbwc:vibe` routes to

`/lbwc:vibe` is the user entry point. The routes below are the internal LBWC stages it dispatches after state detection and confirmation. You can recognize them in status and handoffs, but you do not need to steer the pipeline yourself.

| Route | When `/lbwc:vibe` chooses it | What comes back |
| --- | --- | --- |
| `/lbwc:discuss` | A phase needs context before planning | A human-facing context artifact |
| `/lbwc:research` | A decision needs evidence | Focused research notes |
| `/lbwc:map` | A codebase needs a map | A structured codebase map |
| `/lbwc:plan` | A phase needs a reviewed plan | A bounded plan with verification criteria |
| `/lbwc:build` | An accepted plan needs execution | Contracted task execution and summaries |
| `/lbwc:qa` | A completed build needs plan-based checks | PASS, FAIL, or PARTIAL evidence |
| `/lbwc:uat` | QA has passed and acceptance needs a human | Completed UAT or a concrete issue list |
| `/lbwc:debug` | The brief describes a defect | Root cause, fix evidence, and a focused record |
| `/lbwc:fix` | The work is a known-small repair | A narrow repair path |
| `/lbwc:docs` | The work is documentation scoped | Documentation scoped to the request |

The command files are intentionally readable. If you want the exact workflow or ownership boundary, start with [the public architecture overview](PUBLIC-ARCHITECTURE.md).

## Human-first architecture

LBWC is zero trust in the practical direction: the framework should protect the user from agent drift. Agents do useful work, but they do not become the project manager just because they can produce a convincing paragraph.

| Owner | Responsibility |
| --- | --- |
| You | Scope, priorities, approvals, and release decisions |
| Main session | Orchestration, contract issuance, artifact persistence, and Git |
| Generated agent | One contracted task, exact write paths, and structured evidence |
| Shell guards | Contract, workspace, lifecycle, Git, and critical-command admission |

Before LBWC registers a generated agent, the shell issues an immutable task contract. It binds the task, team shape, job, allowed paths, and lifecycle state. The generator, spawn guard, and file guard verify that contract. A worker cannot widen its scope by writing a more confident handoff, changing the manifest, or editing the contract store.

Template-granted Bash remains available for normal work. The guard blocks generated identities from Git, critical execution, shell evaluation routes, and LBWC control paths. This is command admission, not an operating-system sandbox. The distinction matters, and [the public architecture overview](PUBLIC-ARCHITECTURE.md) describes the boundary plainly.

## Teams, status, and release work

LBWC runs its work through small team shapes: solo specialists, engineer and critic pairs, and test-owner trios where the task needs them. Each member receives only the paths its role owns. Critics receive no write allowance. The main session reviews evidence, persists the approved artifacts, and owns commits.

The statusline is read-only. It shows Claude Code supplied model, context, and rate-limit fields when available, plus project phase, task progress, active team state, QA or UAT status, and telemetry health. It does not call an API or read credentials.

If a teammate becomes idle, LBWC waits exactly 120 seconds, validates the manifest and contract again, and returns Claude Code native stop guidance. It does not send process signals, respawn work, clear ownership, or delete the teammate output. Quietly deleting evidence is a bad debugging strategy with better branding.

For local tool and release work, LBWC includes:

- `scripts/rtk-manager.sh` for confirmed, checksummed, project-local RTK installs with rollback.
- `VERSION` and `CHANGELOG.md` for synchronized release history.
- `scripts/version-bump.sh` to update release metadata together.
- `scripts/release-verify.sh` to run local release checks before a maintainer decides to publish.

## Verify, update, and develop

Validate a checkout before installing or releasing it:

```bash
claude plugin validate .
rtk bats tests/
bash scripts/release-verify.sh
```

After a new LBWC release, update the marketplace entry and the installed plugin:

```bash
claude plugin marketplace update lbwc-marketplace
claude plugin update lbwc@lbwc-marketplace
```

To remove the plugin:

```bash
claude plugin uninstall lbwc@lbwc-marketplace
```

The release scripts verify local state. Publishing, tags, pushes, and history changes remain explicit maintainer decisions.

## Read next

- [Architecture and enforcement boundaries](PUBLIC-ARCHITECTURE.md)
- [Release history](CHANGELOG.md)

## License and maintenance

Huge thanks to VBW, BMAD and other great planning harnesses. This repository is the merging of my old "Agentic Project Love" Framework and VBW, a great script-based planning system. The port is from VBW to LBWC, and many of VBWs source code is taken into LBWC.

LBWC is released under the [GNU General Public License v3.0 only](LICENSE). It is maintained by [Michael Heichler](https://github.com/michaelheichler). Report bugs or propose changes through the [issue tracker](https://github.com/michaelheichler/lbwc/issues).
