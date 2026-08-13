# LBWC Smoke Matrix

This matrix separates automated local proof from scenarios that require a clean interactive Claude Code consumer session.

## Automated

| Scenario | Evidence | Result |
| --- | --- | --- |
| Flat command files omit `name` and custom help derives one namespace | `tests/command-contract.bats`, `tests/help-output.bats`, strict plugin validation | PASS |
| Schema 2 contracts remain valid | `tests/task-contract.bats`, generator and guard suites | PASS |
| Schema 3 typed capabilities and temporary control roots fail closed | `tests/control-root.bats`, `tests/qa-file-guard.bats`, `tests/qa-agent-spawn-guard.bats` | PASS |
| Native task creation binds one pending contract and completion requires verification | `tests/task-hooks.bats` | PASS |
| Generated definition owns model, effort, maxTurns, tools, and role instructions | `tests/agent-generator.bats`, spawn override rejection | PASS |
| Authoritative context discovery avoids `.lbwc-planning` creation | `tests/team-context-index.bats` | PASS |
| Import staging preserves source and canonical artifacts until explicit promotion | `tests/plan-import.bats`, import command tests | PASS |
| Full local suite | `bats tests/` | PASS, 1,189 of 1,189 |

## Interactive Claude Code

| Scenario | Required evidence | Status |
| --- | --- | --- |
| Clean Claude Code 2.1.231 session loads the inline plugin command set | Debug log reports `Loaded 33 commands from plugin lbwc default directory`, matching 33 command files | PASS |
| Clean interactive help exposes `/lbwc:team` and `/lbwc:import` without `/lbwc:lbwc:*` aliases | Rendered command discovery output from a fresh consumer session | PENDING |
| First generated teammate forms a session-named native team in in-process mode | Native roster and task list, with no pre-authored config | PENDING |
| Split-pane teammate payload resolves the same generated identity | Hook payload identity and manifest claim evidence | PENDING |
| Runtime model and reasoning match generated frontmatter | Agent routing evidence plus teammate runtime transcript metadata | PENDING |
| Teammates use native peer and lead messaging | Native inbox messages and message-scope hook evidence | PENDING |
| Source-less `/lbwc:team` shows at most three newest candidates and creates no run before confirmation | Interactive proposal and filesystem check | PENDING |
| `/lbwc:import` cancel and failed promotion preserve canonical artifact digests | Before and after digest evidence in a consumer project | PENDING |

Pending means the repository has no honest interactive runtime evidence yet. It is not a passing claim.
