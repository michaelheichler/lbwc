#!/usr/bin/env bash
set -u

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

if [ "$#" -ne 2 ]; then
  fail "usage: plan-task-count.sh <PLAN.md> <project-config.json>"
fi

plan_path=$1
project_config=$2
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
settings_path="$script_dir/../config/settings.json"

[ -r "$plan_path" ] || fail "PLAN is not readable: $plan_path"
[ -r "$project_config" ] || fail "project config is not readable: $project_config"
[ -r "$settings_path" ] || fail "default config is not readable: $settings_path"
command -v jq >/dev/null 2>&1 || fail "jq is required to validate merged config"

jq -e 'type == "object"' "$settings_path" >/dev/null 2>&1 ||
  fail "default config is not valid JSON: $settings_path"
jq -e 'type == "object"' "$project_config" >/dev/null 2>&1 ||
  fail "project config is not valid JSON: $project_config"

merged_config=$(jq -s '.[0] * .[1]' "$settings_path" "$project_config" 2>/dev/null) ||
  fail "could not merge config"
max_tasks=$(jq -er '
  .max_tasks_per_plan
  | select(type == "number" and . > 0 and . == floor)
  | tostring
' <<< "$merged_config" 2>/dev/null) ||
  fail "max_tasks_per_plan must be a positive integer"

task_count=$(awk '
  BEGIN {
    tasks_blocks = 0
    tasks_closes = 0
    in_tasks = 0
    in_task = 0
    count = 0
    malformed = 0
  }
  /^[[:space:]]*<tasks>[[:space:]]*$/ {
    if (in_tasks || in_task || tasks_blocks != 0) malformed = 1
    else {
      tasks_blocks++
      in_tasks = 1
    }
    next
  }
  /^[[:space:]]*<\/tasks>[[:space:]]*$/ {
    if (!in_tasks || in_task) malformed = 1
    else {
      tasks_closes++
      in_tasks = 0
    }
    next
  }
  /^[[:space:]]*<task([[:space:]][^>]*)?>[[:space:]]*$/ {
    if (!in_tasks || in_task) malformed = 1
    else {
      count++
      in_task = 1
    }
    next
  }
  /^[[:space:]]*<\/task>[[:space:]]*$/ {
    if (!in_tasks || !in_task) malformed = 1
    else in_task = 0
    next
  }
  END {
    if (malformed || tasks_blocks != 1 || tasks_closes != 1 || in_tasks || in_task) exit 2
    print count
  }
' "$plan_path") || fail "malformed PLAN task structure"

[ "$task_count" -gt 0 ] || fail "PLAN has no task records"
if ! jq -en \
  --argjson count "$task_count" \
  --argjson max "$max_tasks" \
  '$count <= $max' >/dev/null; then
  fail "PLAN has $task_count tasks, exceeding max_tasks_per_plan=$max_tasks"
fi

printf 'plan_task_count=%s\n' "$task_count"
printf 'max_tasks_per_plan=%s\n' "$max_tasks"
