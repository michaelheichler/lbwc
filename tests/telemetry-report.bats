#!/usr/bin/env bats
load test_helper
setup() { setup_temp_dir; cd "$TEST_TEMP_DIR"; }
teardown() { cd "$PROJECT_ROOT"; teardown_temp_dir; }

@test "report computes deterministic counts and percentiles" {
  python3 "$PROJECT_ROOT/scripts/lib/session-telemetry.py" record --event command --outcome success --duration-ms 10 >/dev/null
  python3 "$PROJECT_ROOT/scripts/lib/session-telemetry.py" record --event command --outcome success --duration-ms 20 >/dev/null
  python3 "$PROJECT_ROOT/scripts/lib/session-telemetry.py" record --event command --outcome failure --duration-ms 30 >/dev/null
  run bash "$PROJECT_ROOT/scripts/telemetry-report.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"total":3'* ]]
  [[ "$output" == *'"p50_ms":20'* ]]
  [[ "$output" == *'"p95_ms":30'* ]]
}

@test "report detects tampering" {
  python3 "$PROJECT_ROOT/scripts/lib/session-telemetry.py" record --event command --outcome success --duration-ms 10 >/dev/null
  python3 - <<'PY'
from pathlib import Path
p = Path('.lbwc-planning/telemetry/session.jsonl')
p.write_text(p.read_text().replace('"duration_ms":10.0', '"duration_ms":99.0'))
PY
  run bash "$PROJECT_ROOT/scripts/telemetry-report.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *'tamper'* || "$output" == *'sha256'* ]]
}
