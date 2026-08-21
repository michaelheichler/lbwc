# Structural decay assessment

An automated reviewer claimed god-function structure in `scripts/lbwc-config.sh`,
`scripts/agent-generator.sh`, `scripts/task-contract.sh`, and
`scripts/command-contract.sh`. Two of its supporting claims were already
found false. It called `task-contract.sh` a Python script when its entry
point is bash. It wraps an embedded Python body, same as
`command-contract.sh`. It also claimed missing test suites for all four
files when each has one.

This assessment re-judges each file on its own evidence: current size, the
size and shape of the diff this plan's workflow-backend work actually made to
it, and whether any function or file mixes concerns that do not belong
together. It is a judgment record, not a refactor. No file below was
restructured as part of producing it.

## Method

For each file: `git diff HEAD -- <file>` to isolate what this plan changed,
and a function-span scan (Python `def` blocks for the two Python-bodied
files, `name() {` blocks for the two pure-bash files) to find the largest
units and whether this plan's lines landed inside them.

## `scripts/task-contract.sh` (867 lines)

**Diff from this plan:** +20/-2 lines. One new `EXECUTION_BACKENDS` member
(`workflow`), one new five-line helper (`role_write_capable`), a new
`--read-only-role` CLI flag, and an eight-line validation block inside
`command_contract` that rejects a read-only role receiving a write
capability.

**Largest functions, pre- and post-plan:** `validate_contract` is 106 lines
both before and after this plan, untouched by it. `command_contract` grew
from 87 to 95 lines. `parse_options` grew from 65 to 68. Both of the large
functions predate this plan by multiple prior releases, visible in `git log`
back to `f8351da`.

**Judgment:** the plan's addition is small and single-purpose. It lands
inside a function whose job already is "validate everything about one task
contract request." The new `role_write_capable` helper is a clean,
independently testable predicate. It is not a fifth thing bolted onto an
unrelated function.
`validate_contract` and `command_contract` were already large before this
plan and stayed large. This plan did not make them worse. The 106-line
`validate_contract` is the one pre-existing function in this file worth
watching. It validates schema shape, capability equivalence, runtime-kind
and communication-policy pairing, and backend-resolution equality in one
pass, but that predates this plan and is out of scope here.

**Recommendation:** no action from this plan. If `validate_contract` keeps
growing, it is a reasonable extraction candidate (split schema-shape checks
from capability and backend-equivalence checks), but that is a separate,
deliberate task with its own tests, not a byproduct of this one.

## `scripts/agent-generator.sh` (741 lines)

**Diff from this plan:** +3/-3 lines. Two `case` patterns gained a
`workflow` arm alongside the existing `in_process|tmux` arms. Net line count
is unchanged.

**Judgment:** this is the smallest possible diff that could add a third
backend value to an existing enum check. It touches no function structure,
adds no new concern, and does not change any function's size. There is
nothing here for this plan to have made worse.

**Recommendation:** none. Not revisited further.

## `scripts/lbwc-config.sh` (741 lines)

**Diff from this plan:** +10/-4 lines, entirely inside `validate_config_json`,
`migrate_config_json`, `setting_is_writable`, and
`execution_setting_is_frozen`. Each change is one more clause in an existing
enumeration: one more `jq` schema key (`workflow_execution`) and its typed
sub-schema, one more accepted `agent_execution_mode` value, one more
writable-setting token, one more frozen-setting case arm.

**Largest function:** `validate_config_json` is 143 lines, the largest
function in any of the four files. It is a single `jq` filter that asserts
the shape of every key in `config.json`, roughly one `and (...)` clause per
key. This plan's four added lines are one more such clause, in the same
declarative style as the roughly 39 clauses already there.

**Judgment:** the size is real but not the classic god-function shape, one
function doing several unrelated jobs. It is one job, "assert the full
config schema," repeated once per config key, and LBWC's config surface
genuinely has around forty keys. The plan's change is a single clause added
in the existing pattern. It did not introduce a new responsibility or a new
shape of complexity to the function.

**Recommendation:** no action from this plan. If this schema keeps growing,
the eventual fix is likely a data-driven schema, a JSON key and type table
walked generically, rather than one hand-written `and` clause per key.
That is an architectural change to the config system, not something to
attempt as a side effect of adding one execution backend.

## `scripts/command-contract.sh` (462 lines)

**Diff from this plan:** +186/-0 lines against a pre-plan file of 276
lines, a 67% single-plan size increase and by far the largest of the four.
This is the one file where "did this plan make it worse" has a real
answer, not a negligible one.

**What was added:** an allowlist loader, `load_gated_tool_prose_allowlist`
(40 lines). A small negation-scope prose scanner, `clause_start`,
`first_unnegated_match`, `has_unnegated_match`, and
`validate_workflow_authoring_ban`, that flags command files instructing the
model to author workflow JavaScript or pass an inline `script` parameter.
A second, independent checker, `_frontmatter_body_start_line`,
`_allowed_tools_line`, `_granted_tool_names`, `_first_unexempted_match`, and
`validate_gated_tool_grants`, that cross-references a command's body text
against its declared `allowed-tools` frontmatter for four gated tool names.

No individual function is oversized. The largest post-plan function is
`main` at 44 lines, and every new function is under 45 lines. The growth
is file-level, not function-level. This file now holds three fairly
distinct validation domains: the original structural checks (manifest
sections, frontmatter shape, legacy predecessor-project identifiers), and two new prose
heuristics (workflow-authoring negation scoping, gated-tool-grant
cross-referencing).

**Judgment:** thematically this is still one job, "every command markdown
file must satisfy the repository's command contract," and the two new
checks are contract rules like any other, not an unrelated concern
smuggled in. But the two new checks are a different kind of check than
the rest of the file. They are heuristic natural-language pattern
matching over free-form prose (negation scope, clause boundaries,
phrase-based exemptions) rather than deterministic structural checks
(does this key exist, does this section match its required pattern). That
is a real difference in complexity class and failure mode. A structural
check is either right or wrong. A prose heuristic can have false positives
and false negatives by design, which is why it needed its own allowlist
file (`config/gated-tool-prose-allowlist.txt`) to carry known-good
exceptions. Mixing a checker with an allowlist-driven escape hatch into
the same file as checkers with no such thing is a genuine, if mild,
cohesion cost, and it is fully attributable to this plan.

**Recommendation:** if command-contract.sh keeps absorbing prose-heuristic
checks, split the two new validators into a sibling module. Their supporting
`WORKFLOW_AUTHOR_PATTERN` and `GATED_TOOL_PATTERNS` machinery would move
with them, for example into `scripts/lib/command-contract-prose.py`.
`command-contract.sh`'s embedded Python body would import that module the
same way the file already imports `parse_frontmatter` and
`validate_manifest` from its own scope.
That would leave `command-contract.sh` doing only deterministic structural
validation, with prose and security-instruction heuristics living where
their different failure mode and allowlist dependency are visible on their
own. This plan does not perform that split. It is future work, sized at
roughly an hour, not a byproduct of adding one execution backend.

## Summary

| File | Size | This plan's diff | Cohesion verdict |
| --- | --- | --- | --- |
| `task-contract.sh` | 867 lines | +20/-2 | Unchanged. Pre-existing large functions untouched, new code is a clean small addition |
| `agent-generator.sh` | 741 lines | +3/-3 (net 0) | Unchanged. Minimal enum-value diff |
| `lbwc-config.sh` | 741 lines | +10/-4 | Unchanged. One more schema clause in an already-long declarative validator |
| `command-contract.sh` | 462 lines | +186/-0 (67% growth) | Worsened. Two new prose-heuristic validators, each internally clean, now share a file with the original structural checks and a different failure mode |

Only `command-contract.sh` shows a cohesion cost this plan actually
introduced. The other three files are unchanged in kind, even where their
pre-existing size (particularly `task-contract.sh`'s `validate_contract`
and `lbwc-config.sh`'s `validate_config_json`) would be worth a future,
separately-scoped look.
