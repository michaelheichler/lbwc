#!/usr/bin/env bash
set -euo pipefail

LBWC_COMPOSE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

lbwc_extract_model_records() {
  local binary="$1" output="$2" entries metadata entry remainder selector_id group display_name
  entries=$(mktemp "${TMPDIR:-/tmp}/lbwc-claude-model-entries.XXXXXX") || return 1
  metadata=$(mktemp "${TMPDIR:-/tmp}/lbwc-claude-model-metadata.XXXXXX") || {
    rm -f "$entries"
    return 1
  }
  LC_ALL=C grep -aoE 'id:"claude-[a-zA-Z0-9._-]+",family:"[a-zA-Z0-9_]+",display_name:"[^"[:cntrl:]]+"' "$binary" > "$entries" 2>/dev/null || true
  : > "$metadata"
  while IFS= read -r entry; do
    remainder="${entry#id:\"}"
    selector_id="${remainder%%\",family:\"*}"
    remainder="${entry#*,family:\"}"
    group="${remainder%%\",display_name:\"*}"
    remainder="${entry#*,display_name:\"}"
    display_name="${remainder%\"}"
    jq -cn --arg selector "$selector_id" --arg label "$display_name" --arg group "$group" \
      '{selector:$selector,label:$label,description:$label,group:$group}' >> "$metadata"
  done < "$entries"
  jq -s '
    reduce .[] as $record ([];
      if any(.[]; .selector == $record.selector) then . else . + [$record] end
    )
  ' "$metadata" > "$output"
  rm -f "$entries" "$metadata"
  jq -e 'length > 0' "$output" >/dev/null
}

lbwc_extract_host_enum_candidates() {
  local binary="$1" output="$2"
  LC_ALL=C grep -aoE '\["[A-Za-z0-9][A-Za-z0-9._:-]*"(,"[A-Za-z0-9][A-Za-z0-9._:-]*"){1,80}\]' "$binary" > "$output" 2>/dev/null || true
}

lbwc_compose_model_catalog() {
  local records_path="$1" candidates_path="$2" output="$3" lines_json filter
  filter="$LBWC_COMPOSE_LIB_DIR/compose-model-catalog.jq"
  lines_json=$(jq -Rsc 'split("\n")' "$candidates_path") || return 1
  jq -n --slurpfile records "$records_path" --argjson lines "$lines_json" -f "$filter" > "$output"
}

lbwc_lookup_agent_model_id() {
  local composed="$1" selector="$2" mapped
  mapped=$(jq -r --arg selector "$selector" '
    if (.agent_model_ids | type == "object")
       and (.agent_model_ids[$selector] != null)
       and (.agent_model_ids[$selector] != "")
    then .agent_model_ids[$selector]
    elif ((.host_agent_enum | type) != "array" or (.host_agent_enum | length) == 0)
         and any(.models[]; .selector == $selector)
    then $selector
    else empty
    end
  ' "$composed") || return 1
  [ -n "$mapped" ] || return 1
  printf '%s\n' "$mapped"
}

lbwc_build_catalog() {
  local binary="$1" output="$2" before after version detected_at help_path models_path reasoning_path associations_path host_enum_path composed_path envelope
  envelope="$LBWC_COMPOSE_LIB_DIR/capability-catalog.jq"
  help_path=$(mktemp "${TMPDIR:-/tmp}/lbwc-claude-help.XXXXXX") || fail 'could not create help temporary file'
  HELP_TEMP="$help_path"
  models_path=$(mktemp "${TMPDIR:-/tmp}/lbwc-claude-models.XXXXXX") || {
    rm -f "$help_path"
    fail 'could not create model temporary file'
  }
  MODELS_TEMP="$models_path"
  reasoning_path=$(mktemp "${TMPDIR:-/tmp}/lbwc-claude-reasoning.XXXXXX") || {
    rm -f "$help_path" "$models_path"
    fail 'could not create reasoning temporary file'
  }
  REASONING_TEMP="$reasoning_path"
  associations_path=$(mktemp "${TMPDIR:-/tmp}/lbwc-claude-model-associations.XXXXXX") || {
    rm -f "$help_path" "$models_path" "$reasoning_path"
    fail 'could not create model-association temporary file'
  }
  ASSOCIATIONS_TEMP="$associations_path"
  host_enum_path=$(mktemp "${TMPDIR:-/tmp}/lbwc-claude-host-enum.XXXXXX") || {
    rm -f "$help_path" "$models_path" "$reasoning_path" "$associations_path"
    fail 'could not create host-enum temporary file'
  }
  HOST_ENUM_TEMP="$host_enum_path"
  composed_path=$(mktemp "${TMPDIR:-/tmp}/lbwc-claude-composed-models.XXXXXX") || {
    rm -f "$help_path" "$models_path" "$reasoning_path" "$associations_path" "$host_enum_path"
    fail 'could not create composed-model temporary file'
  }
  COMPOSED_MODELS_TEMP="$composed_path"
  before=$(sha256_file "$binary") || fail 'could not fingerprint Claude Code executable'
  version=$(extract_version "$binary")
  extract_help "$binary" "$help_path"
  extract_model_records "$binary" "$models_path"
  lbwc_extract_host_enum_candidates "$binary" "$host_enum_path"
  lbwc_compose_model_catalog "$models_path" "$host_enum_path" "$composed_path" \
    || fail 'could not compose host Agent model catalog'
  extract_reasoning_values "$help_path" "$reasoning_path"
  extract_model_associations "$binary" "$associations_path"
  after=$(sha256_file "$binary") || fail 'could not recheck Claude Code executable fingerprint'
  [ "$before" = "$after" ] || fail 'Claude Code executable changed during capability extraction'
  detected_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  jq -S -n \
    --arg binary_path "$binary" \
    --arg version "$version" \
    --arg sha256 "$after" \
    --arg detected_at "$detected_at" \
    --slurpfile composed "$composed_path" \
    --slurpfile reasoning "$reasoning_path" \
    --slurpfile associations "$associations_path" \
    -f "$envelope" > "$output"
  rm -f "$help_path" "$models_path" "$reasoning_path" "$associations_path" "$host_enum_path" "$composed_path"
}

lbwc_map_agent_model_from_binary() {
  local binary="$1" selector="$2" records_path candidates_path composed_path mapped
  records_path=$(mktemp "${TMPDIR:-/tmp}/lbwc-map-records.XXXXXX") || return 1
  candidates_path=$(mktemp "${TMPDIR:-/tmp}/lbwc-map-enum.XXXXXX") || {
    rm -f "$records_path"
    return 1
  }
  composed_path=$(mktemp "${TMPDIR:-/tmp}/lbwc-map-composed.XXXXXX") || {
    rm -f "$records_path" "$candidates_path"
    return 1
  }
  MODELS_TEMP="$records_path"
  HOST_ENUM_TEMP="$candidates_path"
  COMPOSED_MODELS_TEMP="$composed_path"
  lbwc_extract_model_records "$binary" "$records_path" || {
    rm -f "$records_path" "$candidates_path" "$composed_path"
    return 1
  }
  lbwc_extract_host_enum_candidates "$binary" "$candidates_path"
  lbwc_compose_model_catalog "$records_path" "$candidates_path" "$composed_path" || {
    rm -f "$records_path" "$candidates_path" "$composed_path"
    return 1
  }
  mapped=$(lbwc_lookup_agent_model_id "$composed_path" "$selector") || {
    rm -f "$records_path" "$candidates_path" "$composed_path"
    return 1
  }
  rm -f "$records_path" "$candidates_path" "$composed_path"
  printf '%s\n' "$mapped"
}

lbwc_catalog_fingerprint_matches() {
  local catalog="$1" binary="$2" expected actual
  expected=$(jq -r '.source.sha256' "$catalog") || return 1
  actual=$(sha256_file "$binary") || return 1
  [ "$expected" = "$actual" ]
}

lbwc_map_agent_model() {
  local source="$1" selector="$2" catalog_binary live_binary mapped
  [ -n "$selector" ] || return 1
  if [ -f "$source" ] && jq -e '.schema_version == 1 and .source.sha256' "$source" >/dev/null 2>&1; then
    catalog_binary=$(jq -r '.source.binary_path' "$source")
    live_binary=""
    if [ -n "${CLAUDE_CODE_EXECPATH:-}" ]; then
      live_binary=$(resolve_claude_binary 2>/dev/null || true)
    fi
    if [ -n "$live_binary" ]; then
      if lbwc_catalog_fingerprint_matches "$source" "$live_binary"; then
        mapped=$(lbwc_lookup_agent_model_id "$source" "$selector") || return 1
        printf '%s\n' "$mapped"
        return 0
      fi
      lbwc_map_agent_model_from_binary "$live_binary" "$selector"
      return $?
    fi
    if [ -n "$catalog_binary" ] && [ -f "$catalog_binary" ] && [ -x "$catalog_binary" ]; then
      if lbwc_catalog_fingerprint_matches "$source" "$catalog_binary"; then
        mapped=$(lbwc_lookup_agent_model_id "$source" "$selector") || return 1
        printf '%s\n' "$mapped"
        return 0
      fi
      lbwc_map_agent_model_from_binary "$catalog_binary" "$selector"
      return $?
    fi
    return 1
  fi
  lbwc_map_agent_model_from_binary "$source" "$selector"
}
