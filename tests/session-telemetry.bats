#!/usr/bin/env bats

load test_helper

setup() { setup_temp_dir; cd "$TEST_TEMP_DIR"; }
teardown() { cd "$PROJECT_ROOT"; teardown_temp_dir; }

writer() { python3 "$PROJECT_ROOT/scripts/lib/session-telemetry.py" "$@"; }

@test "writer records a canonical main-session event with a hash chain" {
  run writer record --event session_start --outcome success --duration-ms 12 --session-id s1
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.lbwc-planning/telemetry/session.jsonl" ]
  run python3 -c 'import json,sys; r=json.loads(open(sys.argv[1]).readline()); assert r["actor"]=="main"; assert r["prev_sha256"] is None; assert len(r["sha256"])==64' "$TEST_TEMP_DIR/.lbwc-planning/telemetry/session.jsonl"
  [ "$status" -eq 0 ]
}

@test "writer rejects agent actors, arbitrary fields, and raw payload keys" {
  run writer record --event session_start --outcome success --actor agent
  [ "$status" -ne 0 ]
  run writer record --event session_start --outcome success --field transcript=secret
  [ "$status" -ne 0 ]
}

@test "writer rejects malformed prior records" {
  mkdir -p .lbwc-planning/telemetry
  echo '{"not":"a record"}' > .lbwc-planning/telemetry/session.jsonl
  run writer record --event session_start --outcome success
  [ "$status" -ne 0 ]
}

@test "writer rejects a forged non-null genesis prev hash" {
  mkdir -p .lbwc-planning/telemetry
  python3 - <<'PY'
import hashlib, json
r = {"ts":"2026-01-01T00:00:00+00:00","session_id":None,"actor":"main","event":"session_start","outcome":"success","duration_ms":None,"tokens_in":None,"tokens_out":None,"model":None,"phase":None,"prev_sha256":"forged"}
r["sha256"] = hashlib.sha256(json.dumps(r, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
open('.lbwc-planning/telemetry/session.jsonl','w').write(json.dumps(r, sort_keys=True, separators=(",", ":"))+'\n')
PY
  run writer record --event command --outcome success
  [ "$status" -ne 0 ]
}

@test "writer rejects oversized privacy-sensitive values" {
  run writer record --event command --outcome success --session-id "$(printf 'x%.0s' {1..257})"
  [ "$status" -ne 0 ]
}

@test "writer uses the canonical planning root when addressed through an alias" {
  mkdir -p canonical
  ln -s canonical alias
  run env LBWC_PLANNING_DIR="$TEST_TEMP_DIR/alias" python3 "$PROJECT_ROOT/scripts/lib/session-telemetry.py" record --event session_start --outcome success
  [ "$status" -eq 0 ]
  [ -f canonical/telemetry/session.jsonl ]
}

@test "writer fails closed on lock contention" {
  mkdir -p .lbwc-planning/telemetry
  python3 -c 'import fcntl,sys,time; f=open(sys.argv[1],"a"); fcntl.flock(f,fcntl.LOCK_EX); time.sleep(1)' .lbwc-planning/telemetry/session.jsonl &
  local locker=$!
  sleep 0.05
  run env LBWC_TELEMETRY_LOCK_TIMEOUT=0.05 python3 "$PROJECT_ROOT/scripts/lib/session-telemetry.py" record --event command --outcome success
  kill "$locker" 2>/dev/null || true
  wait "$locker" 2>/dev/null || true
  [ "$status" -ne 0 ]
}

@test "nonfinite lock timeout falls back to bounded default" {
  mkdir -p .lbwc-planning/telemetry
  python3 -c 'import fcntl,sys,time; f=open(sys.argv[1],"a"); fcntl.flock(f,fcntl.LOCK_EX); time.sleep(1)' .lbwc-planning/telemetry/session.jsonl &
  local locker=$!
  sleep 0.05
  run env LBWC_TELEMETRY_LOCK_TIMEOUT=nan python3 "$PROJECT_ROOT/scripts/lib/session-telemetry.py" record --event command --outcome success
  kill "$locker" 2>/dev/null || true
  wait "$locker" 2>/dev/null || true
  [ "$status" -ne 0 ]
}
