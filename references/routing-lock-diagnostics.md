# Routing lock token diagnostics

Tracked record for two limitations in the `acquire_config_lock` diagnostics
added to `scripts/lbwc-routing.sh`. Referenced from `FOLLOW_UP.md`.

## Token flake: hypothesis, not a proven root cause

`acquire_config_lock` occasionally fails to generate its owner token during
`tests/lbwc-execution-config.bats` and `tests/self-check.sh`. Fork exhaustion
in the test host was proposed as the cause, but that is not proven. A
synthetic `ulimit -u` harness showed fork exhaustion CAN break the `od`/`env`
subprocess construct used there, but the one captured run landed the failure
at a different fork point than the one under test, so it demonstrates a
possible mechanism, not the observed flake.

What actually changed: `acquire_config_lock` now captures `od`'s stdout and
the enclosing group's stderr on separate descriptors (the stderr capture
lands in a `mktemp` file scoped to `TMPDIR`, never the planning directory),
and surfaces both through `fail` as `token_status`, `token_detail` (od's
stdout) and `shell_detail` (captured stderr, which includes od's own stderr
plus any shell-level error from the group) when token generation or
validation fails. This is diagnostics only. No root-cause fix landed.

A bounded reproduction attempt (16 concurrent runs of both suites under a
constrained `ulimit -u`) did not reproduce the flake. A more aggressive limit
broke the harness itself with `fork failed: resource temporarily unavailable`
before reaching the target script, which is suggestive but not conclusive
either way.

Status: HYPOTHESIS. Do not describe fork exhaustion as the confirmed root
cause until a real occurrence is captured with `token_status`,
`token_detail`, and `shell_detail` in hand. The next flake must be diagnosed
from that captured text, not re-guessed.

## The diagnostic itself adds a fork to a fork-sensitive path

`token_diag_file=$(mktemp ...)` runs on every `acquire_config_lock` call,
including read-only operations such as `resolve` and `check`, not only on
operations that go on to mutate config. The hypothesised cause of the flake
this diagnostic instruments is fork exhaustion, so the diagnostic adds one
more fork to the exact path whose suspected failure mode is running out of
forks. It also makes a writable `TMPDIR` a new precondition for every
routing operation, where previously none was needed.

This is accepted as a deliberate tradeoff. A `mktemp` failure produces its
own distinct `fail` message ("could not create routing lock diagnostic
file") rather than failing silently, so the added fork stays diagnostic
rather than opaque. When the flake above is next analyzed, do not mistake
this added fork for a neutral change. It is itself a candidate to rule in
or out.

## Render-workflow-template test split: equivalence is asserted, not proven

`tests/render-workflow-template.bats` (23 tests) and
`tests/render-workflow-template-gate-loop.bats` (9 tests) replaced a single
combined file that was never committed. The after-split state is
verifiable: 32 tests total, no duplicate test names, both files under 400
lines, all green. The before-split count cannot be recovered because the
original file has no commit to diff against. Treat the split as a pure move
by assertion, not as something this repository can independently confirm.

## Routing-lock test split: a provable pure move

`tests/lbwc-routing.bats` grew to 972 lines while adding the diagnostic
tests above, past the file length threshold. It split into
`tests/lbwc-routing.bats` (routing command behavior, 26 tests) and
`tests/lbwc-routing-lock.bats` (lock and token mechanics, 17 tests). Unlike
the render-workflow-template split, this one is independently checkable
against git. `git show HEAD:tests/lbwc-routing.bats` has 40 tests. The
working tree before the split had 41 (one test added earlier in this
line of work). The two split files together hold 43 tests with no
duplicate names, which is exactly 41 plus the two new od diagnostic cases
above. Both files pass in full: `bats tests/lbwc-routing.bats` (26/26) and
`bats tests/lbwc-routing-lock.bats` (17/17).
