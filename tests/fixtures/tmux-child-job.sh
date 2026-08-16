#!/usr/bin/env bash
set -u
set -Eeuo pipefail

BUS="${TMUX_CHILD_BUS:?}"
CONTROL_ROOT="${TMUX_CHILD_CONTROL_ROOT:?}"
AGENT_ID="${TMUX_CHILD_AGENT_ID:?}"
SESSION_ID="${TMUX_CHILD_SESSION_ID:?}"
CAPABILITY="${TMUX_CHILD_CAPABILITY:?}"
TIMEOUT_MS="${TMUX_CHILD_TIMEOUT_MS:-5000}"

deadline=$(( $(perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%.0f\n", clock_gettime(CLOCK_MONOTONIC) * 1000') + TIMEOUT_MS ))
job=''
while :; do
  job=$(bash "$BUS" --control-root "$CONTROL_ROOT" poll --from "$AGENT_ID" --agent-id "$AGENT_ID" --session-id "$SESSION_ID" --role agent --capability "$CAPABILITY" --types job || true)
  [ -n "$job" ] && break
  now=$(perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%.0f\n", clock_gettime(CLOCK_MONOTONIC) * 1000')
  [ "$now" -lt "$deadline" ] || { printf 'tmux-child-job: timed out waiting for job\n' >&2; exit 1; }
  sleep 0.01
done

message_id=$(jq -r '.message_id // empty' <<<"$job")
correlation_id=$(jq -r '.correlation_id // empty' <<<"$job")
main_id=$(jq -r '.from.agent_id // empty' <<<"$job")
[[ "$message_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || exit 1
[ -n "$main_id" ] || exit 1

bash "$BUS" --control-root "$CONTROL_ROOT" claim --agent-id "$AGENT_ID" --session-id "$SESSION_ID" --capability "$CAPABILITY" --type job --lease-ms 5000 >/dev/null
bash "$BUS" --control-root "$CONTROL_ROOT" ack --agent-id "$AGENT_ID" --session-id "$SESSION_ID" --capability "$CAPABILITY" --message-id "$message_id" >/dev/null
bash "$BUS" --control-root "$CONTROL_ROOT" publish --to "$main_id" --from-agent-id "$AGENT_ID" --from-session-id "$SESSION_ID" --from-role agent --capability "$CAPABILITY" --type result --correlation-id "$correlation_id" --payload '{"result":"child-complete"}' >/dev/null
