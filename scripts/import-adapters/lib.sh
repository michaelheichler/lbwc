#!/usr/bin/env bash

# Shared helpers for scripts/import-adapters/*.sh. Expects the caller to have
# sourced plan-import.sh first so import_sha256 and import_fail exist.

IMPORT_ADAPTER_FILE_CAP=1048576

import_adapter_read_heading() {
  local path="$1"
  if [ "$path" = - ]; then
    awk '
      /^[[:space:]]*#[[:space:]]+/ {
        sub(/^[[:space:]]*#[[:space:]]+/, "")
        sub(/[[:space:]]+#+[[:space:]]*$/, "")
        print
        exit
      }
    '
    return 0
  fi
  [ -f "$path" ] || return 0
  awk '
    /^[[:space:]]*#[[:space:]]+/ {
      sub(/^[[:space:]]*#[[:space:]]+/, "")
      sub(/[[:space:]]+#+[[:space:]]*$/, "")
      print
      exit
    }
  ' "$path"
}

import_adapter_bounded_content() {
  local path="$1" size
  size=$(import_file_size "$path") || import_fail "could not read source file size: $path"
  if [ "$size" -gt "$IMPORT_ADAPTER_FILE_CAP" ]; then
    printf '\n'
    return 0
  fi
  cat -- "$path"
}

import_adapter_plan_json() {
  local source_path="$1" title="$2" status="$3" content="$4" phase="$5" number="$6" summary_present="$7" raw
  raw=$(jq -n \
    --arg source_path "$source_path" \
    --arg title "$title" \
    --arg status "$status" \
    --arg content "$content" \
    --arg phase "$phase" \
    --arg number "$number" \
    --arg summary_present "$summary_present" \
    '{source_path:$source_path,
      title:(if $title == "" then null else $title end),
      status:(if $status == "" then null else $status end),
      content:(if $content == "" then null else $content end),
      phase:(if $phase == "" then null else ($phase|tonumber) end),
      number:(if $number == "" then null else ($number|tonumber) end),
      summary_present:(if $summary_present == "" then null else ($summary_present == "true") end),
      depends_on:null}')
  IMPORT_ADAPTER_PLAN_DIGEST=$(import_sha256 - <<< "$raw") || import_fail 'could not digest normalized plan entry'
  printf '%s\n' "$raw"
}
