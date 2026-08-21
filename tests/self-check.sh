#!/usr/bin/env bash
# Self-check for lbwc agent-spawn-guard.sh and agent-lifecycle.sh.
# Run directly: bash tests/self-check.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
LBWC_ROOT="$(cd "$HERE/.." && pwd)"
FAIL=0

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; FAIL=1; }

setup_fixture() {
  local work="$1"
  mkdir -p "$work/scripts/lib" "$work/.lbwc-planning" "$work/templates/agent-roles"
  cp "$LBWC_ROOT/scripts/agent-spawn-guard.sh" "$work/scripts/agent-spawn-guard.sh"
  cp "$LBWC_ROOT/scripts/agent-lifecycle.sh" "$work/scripts/agent-lifecycle.sh"
  cp "$LBWC_ROOT/scripts/task-contract.sh" "$work/scripts/task-contract.sh"
  cp "$LBWC_ROOT/scripts/claude-capabilities.sh" "$work/scripts/claude-capabilities.sh"
  cp "$LBWC_ROOT/scripts/lib/lbwc-control-root.sh" "$work/scripts/lib/lbwc-control-root.sh"
  cp "$LBWC_ROOT/scripts/lib/compose-model-catalog.sh" "$work/scripts/lib/compose-model-catalog.sh"
  cp "$LBWC_ROOT/scripts/lib/compose-model-catalog.jq" "$work/scripts/lib/compose-model-catalog.jq"
  cp "$LBWC_ROOT/scripts/lib/capability-catalog.jq" "$work/scripts/lib/capability-catalog.jq"
  cp "$LBWC_ROOT/templates/agent-roles/defaults.json" "$work/templates/agent-roles/defaults.json"
  cp "$HERE/fixture-agent-manifest.sh" "$work/scripts/lib/agent-manifest.sh"
  chmod +x "$work/scripts/agent-spawn-guard.sh" "$work/scripts/agent-lifecycle.sh" "$work/scripts/task-contract.sh"
}

test_pairing_block_and_allow() {
  local work rc state outfile errfile pair_contract pair_id pair_digest solo_contract solo_id solo_digest
  work=$(mktemp -d) || { fail "pairing: mktemp"; return; }
  work=$(cd "$work" && pwd -P)
  outfile=$(mktemp) errfile=$(mktemp)
  setup_fixture "$work"

  pair_contract=$(bash "$work/scripts/task-contract.sh" issue "$work" pair-fixture --command build --role python-engineer --team pair --job "pair fixture")
  pair_id=$(jq -r '.contract_id' "$pair_contract")
  bash "$work/scripts/task-contract.sh" state "$work" "$pair_id" dispatched >/dev/null
  pair_digest=$(jq -r '.contract_digest' "$pair_contract")
  solo_contract=$(bash "$work/scripts/task-contract.sh" issue "$work" scout-fixture --command research --role scout --team solo --job "scout fixture")
  solo_id=$(jq -r '.contract_id' "$solo_contract")
  bash "$work/scripts/task-contract.sh" state "$work" "$solo_id" dispatched >/dev/null
  solo_digest=$(jq -r '.contract_digest' "$solo_contract")

  jq -n --arg root "$work" --arg pair_contract "$pair_contract" --arg pair_id "$pair_id" --arg pair_digest "$pair_digest" --arg solo_contract "$solo_contract" --arg solo_id "$solo_id" --arg solo_digest "$solo_digest" '{
    agents: {
      "lbwc-dev-a": {name:"lbwc-dev-a", role:"python-engineer", state:"registered", pair_id:"p1", pair_role:"engineer", project_root:$root, write_allowances:[], contract_enabled:true, contract_path:$pair_contract, contract_id:$pair_id, contract_digest:$pair_digest, task_identity:$pair_id, model:"sonnet", maxTurns:40, permissionMode:"default", created_at:"2026-08-06T00:00:00Z"},
      "lbwc-critic-a": {name:"lbwc-critic-a", role:"python-critic", state:"registered", pair_id:"p1", pair_role:"critic", project_root:$root, write_allowances:[], contract_enabled:true, contract_path:$pair_contract, contract_id:$pair_id, contract_digest:$pair_digest, task_identity:$pair_id, model:"sonnet", maxTurns:40, permissionMode:"default", created_at:"2026-08-06T00:00:00Z"},
      "lbwc-scout-x": {name:"lbwc-scout-x", role:"scout", state:"registered", pair_id:null, pair_role:null, project_root:$root, write_allowances:[], contract_enabled:true, contract_path:$solo_contract, contract_id:$solo_id, contract_digest:$solo_digest, task_identity:$solo_id, created_at:"2026-08-06T00:00:00Z"}
    }
  }' > "$work/.lbwc-planning/.agent-manifest.json"

  ( cd "$work" && echo '{"tool_name":"Agent","tool_input":{"subagent_type":"lbwc-scout-x"}}' | bash scripts/agent-spawn-guard.sh > "$outfile" 2> "$errfile" )
  rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "spawn guard blocks unrelated role while pair is open"
  else
    fail "spawn guard should block unrelated role while pair open (rc=$rc)"
  fi

  ( cd "$work" && echo '{"tool_name":"Agent","tool_input":{"subagent_type":"lbwc-dev-a"}}' | bash scripts/agent-spawn-guard.sh > "$outfile" 2> "$errfile" )
  rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "spawn guard allows the paired name itself"
  else
    fail "spawn guard should allow paired name (rc=$rc)"
  fi

  state=$(jq -r '.agents["lbwc-dev-a"].state' "$work/.lbwc-planning/.agent-manifest.json")
  if [ "$state" = "running" ]; then
    pass "claimed entry flips to running"
  else
    fail "claimed entry did not flip to running (state=$state)"
  fi

  rm -rf "$work" "$outfile" "$errfile" 2>/dev/null
}

test_lifecycle_touch_stop() {
  local work state deffile
  work=$(mktemp -d) || { fail "lifecycle: mktemp"; return; }
  setup_fixture "$work"

  jq -n '{
    agents: {
      "lbwc-dev-random-suffix": {name:"lbwc-dev-random-suffix", role:"engineer", state:"running", created_at:"2026-08-06T00:00:00Z", last_activity_at:"2026-08-06T00:00:00Z"}
    }
  }' > "$work/.lbwc-planning/.agent-manifest.json"

  mkdir -p "$work/.claude/agents"
  deffile="$work/.claude/agents/lbwc-dev-random-suffix.md"
  printf 'placeholder\n' > "$deffile"

  ( cd "$work" && echo '{"hook_event_name":"SubagentStop","agent_type":"lbwc-dev-random-suffix"}' | bash scripts/agent-lifecycle.sh touch stop )

  state=$(jq -r '.agents["lbwc-dev-random-suffix"].state' "$work/.lbwc-planning/.agent-manifest.json")
  if [ "$state" = "used" ]; then
    pass "touch stop flips state to used regardless of matcher regex, looked up by exact name"
  else
    fail "touch stop did not flip state to used (state=$state)"
  fi

  if [ -f "$deffile" ]; then
    pass "touch stop preserves the rendered agent definition file"
  else
    fail "touch stop removed the rendered agent definition file"
  fi

  rm -rf "$work" 2>/dev/null
}

test_sweep_expires_stale_registered() {
  local work state deffile
  work=$(mktemp -d) || { fail "sweep: mktemp"; return; }
  setup_fixture "$work"

  jq -n '{
    agents: {
      "lbwc-scout-stale": {name:"lbwc-scout-stale", role:"scout", state:"registered", created_at:"2020-01-01T00:00:00Z"}
    }
  }' > "$work/.lbwc-planning/.agent-manifest.json"
  mkdir -p "$work/.claude/agents"
  deffile="$work/.claude/agents/lbwc-scout-stale.md"
  printf 'placeholder\n' > "$deffile"

  ( cd "$work" && bash scripts/agent-lifecycle.sh sweep )

  state=$(jq -r '.agents["lbwc-scout-stale"].state' "$work/.lbwc-planning/.agent-manifest.json")
  if [ "$state" = "expired" ]; then
    pass "sweep expires a registered entry older than 1 hour"
  else
    fail "sweep did not expire the stale registered entry (state=$state)"
  fi

  if [ -f "$deffile" ]; then
    pass "sweep preserves the rendered agent definition file"
  else
    fail "sweep removed the rendered agent definition file"
  fi

  rm -rf "$work" 2>/dev/null
}

test_pairing_block_and_allow
test_lifecycle_touch_stop
test_sweep_expires_stale_registered

if [ "$FAIL" -eq 0 ]; then
  printf 'all lbwc self-checks passed\n'
else
  printf 'lbwc self-checks FAILED\n' >&2
fi
exit "$FAIL"
