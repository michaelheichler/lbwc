#!/usr/bin/env bash
set -uo pipefail

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPTS_DIR=$(cd "$TESTS_DIR/.." && pwd)
RECORDER="$SCRIPTS_DIR/lib/deviq-record.py"
DIGEST="$SCRIPTS_DIR/lib/deviq-digest.sh"
GATE="$SCRIPTS_DIR/deviq-build-gate.sh"

PASS=0
FAIL=0

check() {
  local description="$1" condition="$2"
  if [ "$condition" -eq 0 ]; then
    printf 'PASS: %s\n' "$description"
    PASS=$((PASS + 1))
  else
    printf 'FAIL: %s\n' "$description"
    FAIL=$((FAIL + 1))
  fi
}

record() {
  local kind="$1" root="$2" phase="$3" role="$4"
  shift 4
  python3 "$RECORDER" "$kind" --phase "$phase" --role "$role" --root "$root" "$@" >/dev/null
}

EMPTY_ROOT=$(mktemp -d)
OUT=$(bash "$DIGEST" --root "$EMPTY_ROOT/deviq" 2>&1)
RC=$?
[ "$RC" -eq 0 ]; check "digest on absent files exits 0" "$?"
[ -z "$OUT" ]; check "digest on absent files prints nothing" "$?"
rm -rf "$EMPTY_ROOT"

DIGEST_ROOT=$(mktemp -d)
DEVIQ="$DIGEST_ROOT/deviq"
for i in 1 2 3 4 5 6 7; do
  record decision "$DEVIQ" p1 roleA --field summary="decision-$i"
done
record block "$DEVIQ" p1 roleA --field trigger=stale-issue --field consequence=c --field fix=f --field status=open
record block "$DEVIQ" p1 roleA --field trigger=fixed-issue --field consequence=c --field fix=f --field status=open
record block "$DEVIQ" p1 roleA --field trigger=fixed-issue --field consequence=c --field fix=f --field status=resolved
record block "$DEVIQ" p1 roleA --field trigger=open-1 --field consequence=c1 --field fix=f1 --field status=open
record block "$DEVIQ" p1 roleA --field trigger=open-2 --field consequence=c2 --field fix=f2 --field status=open

OUT=$(bash "$DIGEST" --root "$DEVIQ")
EXPECTED=$(cat <<'EOF'
## Recent open issues
- [p1] open-2 (fix: f2)
- [p1] open-1 (fix: f1)
- [p1] stale-issue (fix: f)

## Recent decisions
- [p1] decision-7
- [p1] decision-6
- [p1] decision-5
- [p1] decision-4
- [p1] decision-3
EOF
)
[ "$OUT" = "$EXPECTED" ]; check "digest shows newest 5 decisions and only open blocks, newest first" "$?"
grep -qv 'fixed-issue' <<< "$OUT"; check "digest does not list a resolved block as still open" "$?"
rm -rf "$DIGEST_ROOT"

NUDGE_ROOT=$(mktemp -d)
NUDGE_DEVIQ="$NUDGE_ROOT/deviq"
record block "$NUDGE_DEVIQ" p1 roleA --field trigger="massive duplicate code across services" --field consequence=c --field fix=f --field status=open
record block "$NUDGE_DEVIQ" p1 roleA --field trigger="unrelated flaky ci" --field consequence=c --field fix=f --field status=open
OUT=$(bash "$DIGEST" --root "$NUDGE_DEVIQ")
grep -q 'duplicate code across services (fix: f) (see: antipatterns/copy-paste-programming)' <<< "$OUT"
check "digest appends the matching nudge article id to a block whose trigger matches a known pattern" "$?"
grep -q 'unrelated flaky ci (fix: f)$' <<< "$OUT"
check "digest leaves a non-matching trigger's line unchanged" "$?"
rm -rf "$NUDGE_ROOT"

GATE_ROOT_1=$(mktemp -d)
DEVIQ1="$GATE_ROOT_1/deviq"
record decision "$DEVIQ1" p1 roleA --field summary=unrelated
OUT=$(bash "$GATE" p1 --root "$DEVIQ1" 2>&1)
RC=$?
[ "$RC" -eq 0 ]; check "gate exits 0 when no blocks recorded for phase" "$?"
[ -z "$OUT" ]; check "gate prints no stderr when no blocks recorded for phase" "$?"
rm -rf "$GATE_ROOT_1"

GATE_ROOT_2=$(mktemp -d)
DEVIQ2="$GATE_ROOT_2/deviq"
record block "$DEVIQ2" p1 roleA --field trigger=missing-config --field consequence=broken-build --field fix=add-config --field status=open
ERR=$(bash "$GATE" p1 --root "$DEVIQ2" 2>&1 1>/dev/null)
RC=$?
[ "$RC" -eq 2 ]; check "gate exits 2 for a single open block" "$?"
grep -q 'missing-config' <<< "$ERR"; check "gate stderr names the open block's trigger" "$?"
rm -rf "$GATE_ROOT_2"

GATE_ROOT_3=$(mktemp -d)
DEVIQ3="$GATE_ROOT_3/deviq"
record block "$DEVIQ3" p1 roleA --field trigger=flaky-test --field consequence=ci-red --field fix=retry-logic --field status=open
record block "$DEVIQ3" p1 roleB --field trigger=flaky-test --field consequence=ci-red --field fix=retry-logic --field status=resolved
ERR=$(bash "$GATE" p1 --root "$DEVIQ3" 2>&1 1>/dev/null)
RC=$?
[ "$RC" -eq 0 ]; check "gate exits 0 when the only trigger's latest record is resolved" "$?"
[ -z "$ERR" ]; check "gate prints no stderr when the only trigger's latest record is resolved" "$?"
rm -rf "$GATE_ROOT_3"

GATE_ROOT_4=$(mktemp -d)
DEVIQ4="$GATE_ROOT_4/deviq"
record block "$DEVIQ4" p1 roleA --field trigger=trigger-a --field consequence=ca --field fix=fa --field status=open
record block "$DEVIQ4" p1 roleA --field trigger=trigger-a --field consequence=ca --field fix=fa --field status=resolved
record block "$DEVIQ4" p1 roleB --field trigger=trigger-b --field consequence=cb --field fix=fb --field status=open
ERR=$(bash "$GATE" p1 --root "$DEVIQ4" 2>&1 1>/dev/null)
RC=$?
[ "$RC" -eq 2 ]; check "gate exits 2 when one of two triggers is still open" "$?"
grep -q 'trigger-b' <<< "$ERR"; check "gate stderr names the still-open trigger" "$?"
grep -qv 'trigger-a' <<< "$ERR"; check "gate stderr does not name the resolved trigger" "$?"
rm -rf "$GATE_ROOT_4"

GATE_ROOT_5=$(mktemp -d)
DEVIQ5="$GATE_ROOT_5/deviq"
record block "$DEVIQ5" p01 roleA --field trigger=other-phase-issue --field consequence=c --field fix=f --field status=open
OUT=$(bash "$GATE" p02 --root "$DEVIQ5" 2>&1)
RC=$?
[ "$RC" -eq 0 ]; check "gate exits 0 for a phase with no blocks of its own, even if another phase has open ones" "$?"
[ -z "$OUT" ]; check "gate prints nothing for the unaffected phase" "$?"
rm -rf "$GATE_ROOT_5"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
