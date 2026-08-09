#!/usr/bin/env bash
set -uo pipefail

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPTS_DIR=$(cd "$TESTS_DIR/.." && pwd)
RECORDER="$SCRIPTS_DIR/lib/deviq-record.py"

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

run_recorder() {
  local root="$1" phase="$2" role="$3"
  shift 3
  python3 "$RECORDER" decision --phase "$phase" --role "$role" --root "$root" "$@"
}

WORK=$(mktemp -d)

SHA1=$(run_recorder "$WORK/deviq" p1 roleA --field summary=one)
SHA2=$(run_recorder "$WORK/deviq" p1 roleB --field summary=two)
SHA3=$(run_recorder "$WORK/deviq" p1 roleC --field summary=three)

FILE="$WORK/deviq/decisions.jsonl"
LINE_COUNT=$(wc -l < "$FILE" | tr -d ' ')
[ "$LINE_COUNT" = "3" ]; check "three records appended" "$?"

PREV1=$(sed -n '1p' "$FILE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["prev_sha256"])')
PREV2=$(sed -n '2p' "$FILE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["prev_sha256"])')
PREV3=$(sed -n '3p' "$FILE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["prev_sha256"])')

[ "$PREV1" = "None" ]; check "first record's prev_sha256 is null" "$?"
[ "$PREV2" = "$SHA1" ]; check "second record chains to first record's sha256" "$?"
[ "$PREV3" = "$SHA2" ]; check "third record chains to second record's sha256" "$?"

rm -rf "$WORK" 2>/dev/null

RACE_ROOT=$(mktemp -d)
RACE_FILE="$RACE_ROOT/deviq/decisions.jsonl"
CLEAN_RACE=1
for i in 1 2 3 4 5; do
  rm -rf "$RACE_ROOT/deviq"
  python3 "$RECORDER" decision --phase race --role a --root "$RACE_ROOT/deviq" --field n="$i-a" >/dev/null &
  python3 "$RECORDER" decision --phase race --role b --root "$RACE_ROOT/deviq" --field n="$i-b" >/dev/null &
  wait
  LINES=$(wc -l < "$RACE_FILE" | tr -d ' ')
  VALID_LINES=$(python3 -c '
import json, sys
ok = 0
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            json.loads(line)
            ok += 1
        except json.JSONDecodeError:
            pass
print(ok)
' "$RACE_FILE")
  if [ "$LINES" != "2" ] || [ "$VALID_LINES" != "2" ]; then
    CLEAN_RACE=0
    break
  fi
done
[ "$CLEAN_RACE" -eq 1 ]; check "concurrent appends under flock yield exactly 2 clean JSON lines (no corruption/loss), checked across 5 races" "$?"
rm -rf "$RACE_ROOT" 2>/dev/null

LOCK_ROOT=$(mktemp -d)
LOCK_FILE="$LOCK_ROOT/deviq/decisions.jsonl"
LOCK_READY="$LOCK_ROOT/lock-ready"
mkdir -p "$(dirname "$LOCK_FILE")"
python3 - "$LOCK_FILE" "$LOCK_READY" <<'PY' &
import fcntl
import os
import sys
import time

path, ready_path = sys.argv[1:3]
with open(path, "a+") as fileobj:
    fcntl.flock(fileobj, fcntl.LOCK_EX)
    open(ready_path, "w").close()
    time.sleep(0.3)
PY
LOCK_PID=$!
for _ in {1..50}; do
  [ -f "$LOCK_READY" ] && break
  sleep 0.01
done
OUT=$(LBWC_DEVIQ_RECORD_LOCK_TIMEOUT=0.05 python3 "$RECORDER" decision --phase lock --role roleA --root "$LOCK_ROOT/deviq" --field summary=blocked 2>&1)
RC=$?
wait "$LOCK_PID"
[ "$RC" -eq 2 ]; check "record lock timeout exits with its distinct status" "$?"
grep -q 'timed out waiting for record lock' <<< "$OUT"; check "record lock timeout names the bounded lock failure" "$?"
[ ! -s "$LOCK_FILE" ]; check "record lock timeout does not append a partial record" "$?"
rm -rf "$LOCK_ROOT" 2>/dev/null

for NONFINITE_TIMEOUT in nan inf; do
  LOCK_ROOT=$(mktemp -d)
  LOCK_FILE="$LOCK_ROOT/deviq/decisions.jsonl"
  LOCK_READY="$LOCK_ROOT/lock-ready"
  mkdir -p "$(dirname "$LOCK_FILE")"
  python3 - "$LOCK_FILE" "$LOCK_READY" <<'PY' &
import fcntl
import os
import sys
import time

path, ready_path = sys.argv[1:3]
with open(path, "a+") as fileobj:
    fcntl.flock(fileobj, fcntl.LOCK_EX)
    open(ready_path, "w").close()
    time.sleep(0.5)
PY
  LOCK_PID=$!
  for _ in {1..50}; do
    [ -f "$LOCK_READY" ] && break
    sleep 0.01
  done
  OUT=$(LBWC_DEVIQ_RECORD_LOCK_TIMEOUT="$NONFINITE_TIMEOUT" python3 "$RECORDER" decision --phase lock --role roleA --root "$LOCK_ROOT/deviq" --field summary=blocked 2>&1)
  RC=$?
  wait "$LOCK_PID"
  if [ "$RC" -eq 2 ]; then
    check "non-finite lock timeout $NONFINITE_TIMEOUT uses the bounded default" 0
  else
    check "non-finite lock timeout $NONFINITE_TIMEOUT uses the bounded default" 1
  fi
  grep -q 'timed out waiting for record lock' <<< "$OUT"; check "non-finite lock timeout $NONFINITE_TIMEOUT preserves timeout diagnostics" "$?"
  if [ ! -s "$LOCK_FILE" ]; then
    check "non-finite lock timeout $NONFINITE_TIMEOUT does not append a partial record" 0
  else
    check "non-finite lock timeout $NONFINITE_TIMEOUT does not append a partial record" 1
  fi
  rm -rf "$LOCK_ROOT" 2>/dev/null
done

MALFORMED_ROOT=$(mktemp -d)
OUT=$(python3 "$RECORDER" decision --phase p --role r --root "$MALFORMED_ROOT/deviq" --field notanequals 2>&1)
RC=$?
[ "$RC" -ne 0 ]; check "malformed --field exits non-zero" "$?"
grep -qi 'notanequals' <<< "$OUT"; check "malformed --field message names the bad argument" "$?"
rm -rf "$MALFORMED_ROOT" 2>/dev/null

INVALID_KIND_ROOT=$(mktemp -d)
OUT=$(python3 "$RECORDER" bogus --phase p --role r --root "$INVALID_KIND_ROOT/deviq" 2>&1)
RC=$?
[ "$RC" -ne 0 ]; check "invalid kind exits non-zero" "$?"
grep -qi 'decision' <<< "$OUT"; check "invalid kind message lists valid kinds" "$?"
rm -rf "$INVALID_KIND_ROOT" 2>/dev/null

VERIFY_ROOT=$(mktemp -d)
VERIFY_DEVIQ="$VERIFY_ROOT/deviq"
run_recorder "$VERIFY_DEVIQ" p1 roleA --field summary=one >/dev/null
run_recorder "$VERIFY_DEVIQ" p1 roleB --field summary=two >/dev/null
run_recorder "$VERIFY_DEVIQ" p1 roleC --field summary=three >/dev/null

python3 "$RECORDER" verify --root "$VERIFY_DEVIQ" >/dev/null 2>&1
[ "$?" -eq 0 ]; check "verify exits 0 on an untampered chain" "$?"

VERIFY_FILE="$VERIFY_ROOT/deviq/decisions.jsonl"
TAMPERED=$(sed -n '2p' "$VERIFY_FILE" | python3 -c 'import json,sys; r=json.load(sys.stdin); r["role"]="tampered"; print(json.dumps(r, sort_keys=True, separators=(",", ":")))')
TMP_FILE=$(mktemp)
awk -v line=2 -v repl="$TAMPERED" 'NR==line{print repl; next}{print}' "$VERIFY_FILE" > "$TMP_FILE"
mv "$TMP_FILE" "$VERIFY_FILE"

ERR=$(python3 "$RECORDER" verify --root "$VERIFY_DEVIQ" 2>&1 1>/dev/null)
RC=$?
[ "$RC" -ne 0 ]; check "verify exits non-zero once a middle record is corrupted" "$?"
grep -q 'decisions.jsonl:2' <<< "$ERR"; check "verify names the corrupted file and line number" "$?"
rm -rf "$VERIFY_ROOT" 2>/dev/null

run_block() {
  local root="$1" phase="$2" role="$3"
  shift 3
  python3 "$RECORDER" block --phase "$phase" --role "$role" --root "$root" "$@"
}

BLOCK_ROOT=$(mktemp -d)
BLOCK_DEVIQ="$BLOCK_ROOT/deviq"

ID_A=$(run_block "$BLOCK_DEVIQ" p1 roleA --field trigger="Stale Cache" --field consequence=c --field fix=f --field status=open)
ID_B=$(run_block "$BLOCK_DEVIQ" p1 roleA --field trigger="  stale   cache  " --field consequence=c --field fix=f --field status=open)
[ "$ID_A" = "$ID_B" ]; check "id is stable across identical triggers with different casing and whitespace" "$?"

LINES_AFTER_DUP=$(wc -l < "$BLOCK_DEVIQ/blocks.jsonl" | tr -d ' ')
[ "$LINES_AFTER_DUP" = "1" ]; check "dedupe: appending an already-open block id is a no-op" "$?"

run_block "$BLOCK_DEVIQ" p1 roleA --field id="$ID_A" --field trigger="stale cache" --field consequence=c --field fix=f --field status=resolved >/dev/null
LINES_AFTER_RESOLVE=$(wc -l < "$BLOCK_DEVIQ/blocks.jsonl" | tr -d ' ')
[ "$LINES_AFTER_RESOLVE" = "2" ]; check "resolve appends a new record referencing the same id" "$?"

ID_C=$(run_block "$BLOCK_DEVIQ" p1 roleA --field trigger="stale cache" --field consequence=c --field fix=f --field status=open)
[ "$ID_C" = "$ID_A" ]; check "resolve then new open succeeds and reuses the same id" "$?"
LINES_AFTER_REOPEN=$(wc -l < "$BLOCK_DEVIQ/blocks.jsonl" | tr -d ' ')
[ "$LINES_AFTER_REOPEN" = "3" ]; check "resolve then new open appends a fresh line" "$?"
rm -rf "$BLOCK_ROOT" 2>/dev/null

CAP_ROOT=$(mktemp -d)
CAP_DEVIQ="$CAP_ROOT/deviq"
for i in 1 2 3 4 5 6 7 8; do
  run_block "$CAP_DEVIQ" p1 roleA --field trigger="issue-$i" --field consequence=c --field fix=f --field status=open >/dev/null
done
OUT=$(run_block "$CAP_DEVIQ" p1 roleA --field trigger="issue-9" --field consequence=c --field fix=f --field status=open 2>&1)
RC=$?
[ "$RC" -eq 1 ]; check "the 9th distinct open block in a phase is refused" "$?"
grep -qi 'open block' <<< "$OUT"; check "cap refusal message lists the open block ids" "$?"
LINES_AFTER_CAP=$(wc -l < "$CAP_DEVIQ/blocks.jsonl" | tr -d ' ')
[ "$LINES_AFTER_CAP" = "8" ]; check "cap refusal does not append a 9th line" "$?"
rm -rf "$CAP_ROOT" 2>/dev/null

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
