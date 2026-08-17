#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTING_PATH="$SCRIPT_DIR/lbwc-routing.sh"
. "$SCRIPT_DIR/lib/compose-model-catalog.sh"
LOCK_DIR=""
TEMPORARY=""
HELP_TEMP=""
MODELS_TEMP=""
REASONING_TEMP=""
ASSOCIATIONS_TEMP=""
HOST_ENUM_TEMP=""
COMPOSED_MODELS_TEMP=""

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf '%s\n' \
    'Usage: claude-capabilities.sh <refresh planning-dir|validate catalog-path>' \
    '       claude-capabilities.sh refresh-from-binary <binary-path>' \
    '       claude-capabilities.sh map-agent-model <binary-or-catalog> <selector>' >&2
}

require_tools() {
  local tool
  for tool in awk date grep jq mktemp mv realpath shasum; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
  done
}

cleanup() {
  local path
  if [ -n "$TEMPORARY" ] && [ -f "$TEMPORARY" ]; then
    rm -f "$TEMPORARY"
  fi
  for path in "$HELP_TEMP" "$MODELS_TEMP" "$REASONING_TEMP" "$ASSOCIATIONS_TEMP" "$HOST_ENUM_TEMP" "$COMPOSED_MODELS_TEMP"; do
    if [ -n "$path" ]; then
      rm -f "$path" "${path}.array"
    fi
  done
  if [ -n "$LOCK_DIR" ] && [ -d "$LOCK_DIR" ]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}

assert_no_symbolic_links() {
  local current="$1" parent
  if [[ "$current" != /* ]]; then
    current="$(pwd -P)/$current"
  fi
  while [ "$current" != "/" ] && [ "${current%/}" != "$current" ]; do
    current=${current%/}
  done
  while :; do
    [ ! -L "$current" ] || fail "symbolic link paths are not allowed: $current"
    [ "$current" = "/" ] && return 0
    parent=$(dirname "$current")
    [ "$parent" != "$current" ] || return 0
    current="$parent"
  done
}

resolve_planning_directory() {
  local input="$1" trimmed parent physical_parent
  case "/$input/" in
    */../*) fail "planning directory traversal is not allowed: $input" ;;
  esac
  trimmed="$input"
  while [ "$trimmed" != "/" ] && [ "${trimmed%/}" != "$trimmed" ]; do
    trimmed=${trimmed%/}
  done
  [ ! -L "$trimmed" ] || fail "state directory boundary must not be a symbolic link: $input"
  [ "${trimmed##*/}" = '.lbwc-planning' ] || fail "planning directory must end with .lbwc-planning: $input"
  [ -d "$trimmed" ] || fail "planning directory does not exist: $input"
  case "$trimmed" in
    */*)
      parent=${trimmed%/*}
      [ -n "$parent" ] || parent=/
      ;;
    *) parent=. ;;
  esac
  physical_parent=$(cd -P -- "$parent" 2>/dev/null && pwd -P) || fail "could not resolve planning directory: $input"
  printf '%s/%s\n' "$physical_parent" '.lbwc-planning'
}

resolve_claude_binary() {
  local selected resolved
  if [ -n "${CLAUDE_CODE_EXECPATH:-}" ]; then
    selected="$CLAUDE_CODE_EXECPATH"
  else
    selected=$(command -v claude 2>/dev/null || true)
  fi
  [ -n "$selected" ] || fail 'Claude Code executable was not found'
  resolved=$(realpath "$selected" 2>/dev/null) || fail "could not resolve Claude Code executable: $selected"
  [ -f "$resolved" ] || fail "Claude Code executable is not a file: $resolved"
  [ -x "$resolved" ] || fail "Claude Code executable is not executable: $resolved"
  printf '%s\n' "$resolved"
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

extract_version() {
  local binary="$1" version
  version=$("$binary" --version 2>/dev/null) || fail 'Claude Code version inspection failed'
  [ -n "$version" ] || fail 'Claude Code version inspection returned no version'
  printf '%s\n' "$version"
}

extract_help() {
  local binary="$1" output="$2"
  "$binary" --help > "$output" 2>/dev/null || fail 'Claude Code help inspection failed'
  [ -s "$output" ] || fail 'Claude Code help inspection returned no schema'
}

extract_model_records() {
  lbwc_extract_model_records "$1" "$2" || fail 'Claude Code binary exposed no validated model catalog'
}

extract_reasoning_values() {
  local help_path="$1" output="$2"
  awk '
    index($0, "--effort <") { active = 1 }
    active {
      text = text " " $0
      if (match(text, /\([^()]+\)/)) {
        choices = substr(text, RSTART + 1, RLENGTH - 2)
        count = split(choices, values, ",")
        for (position = 1; position <= count; position += 1) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", values[position])
          if (values[position] != "") print values[position]
        }
        exit
      }
    }
  ' "$help_path" | jq -Rsc '
    split("\n")
    | map(select(length > 0))
    | reduce .[] as $value ([]; if index($value) == null then . + [$value] else . end)
  ' > "$output"
  jq -e 'length > 0 and all(.[]; type == "string" and length > 0)' "$output" >/dev/null || fail 'Claude Code exposed no validated reasoning capabilities'
}

extract_model_associations() {
  local binary="$1" output="$2" matches
  matches=$(mktemp "${TMPDIR:-/tmp}/lbwc-claude-associations.XXXXXX") || fail 'could not create association temporary file'
  LC_ALL=C grep -aoE 'modelReasoningEfforts:\{"[^"[:cntrl:]]+":\["[^"[:cntrl:]]+"(,"[^"[:cntrl:]]+")*\](,"[^"[:cntrl:]]+":\["[^"[:cntrl:]]+"(,"[^"[:cntrl:]]+")*\])*\}' "$binary" \
    | sed 's/^modelReasoningEfforts://' > "$matches" 2>/dev/null || true
  if [ ! -s "$matches" ]; then
    # As of Claude Code 2.1.227 this literal no longer occurs in the binary at
    # all, so this is the only live path today, not a rare fallback. See
    # FOLLOW_UP.md "Finish the dynamic routing surface" for the tracked gap.
    printf '{}\n' > "$output"
    rm -f "$matches"
    return 0
  fi
  jq -s '
    reduce .[] as $mapping ({};
      reduce ($mapping | to_entries[]) as $entry (.;
        .[$entry.key] = (
          ((.[$entry.key] // []) + $entry.value)
          | reduce .[] as $value ([]; if index($value) == null then . + [$value] else . end)
        )
      )
    )
  ' "$matches" > "$output" 2>/dev/null || {
    rm -f "$matches"
    fail 'Claude Code exposed malformed model reasoning associations'
  }
  rm -f "$matches"
}

validate_catalog_json() {
  jq -e '
    . as $catalog
    | type == "object"
    and .schema_version == 1
    and (.source | type == "object")
    and (.source.binary_path | type == "string" and startswith("/"))
    and (.source.version | type == "string" and length > 0)
    and (.source.sha256 | type == "string" and test("^[[:xdigit:]]{64}$"))
    and (.source.detected_at | type == "string" and length > 0)
    and (.models | type == "array" and length > 0)
    and (all(.models[];
      type == "object"
      and (keys | sort) == ["description", "label", "selector"]
      and (.selector | type == "string" and length > 0)
      and (
        ((.label | type == "string" and length > 0) and (.description | type == "string" and length > 0))
        or (.label == null and .description == null)
      )
    ))
    and ([.models[].selector] | length == (unique | length))
    and (.reasoning | type == "object")
    and (.reasoning.scope | IN("global", "model_associated"))
    and (.reasoning.accepted_values | type == "array" and length > 0)
    and (all(.reasoning.accepted_values[]; type == "string" and length > 0))
    and (.reasoning.accepted_values | length == (unique | length))
    and (.reasoning.model_associations | type == "object")
    and (all(.reasoning.model_associations | to_entries[];
      (.key as $selector | [$catalog.models[].selector] | index($selector) != null)
      and (.value | type == "array" and length > 0)
      and (all(.value[]; type == "string" and length > 0))
      and (.value | length == (unique | length))
      and (all(.value[]; . as $effort | $catalog.reasoning.accepted_values | index($effort) != null))
    ))
    and (
      (has("host_agent_enum") | not)
      or (
        (.host_agent_enum | type == "array")
        and (all(.host_agent_enum[]; type == "string" and length > 0))
        and (.host_agent_enum | length == (unique | length))
      )
    )
    and (
      (has("agent_model_ids") | not)
      or (
        has("host_agent_enum")
        and (.agent_model_ids | type == "object")
        and (all(.agent_model_ids | to_entries[];
          (.value | type == "string" and length > 0)
          and (.value as $host_id | $catalog.host_agent_enum | index($host_id) != null)
        ))
      )
    )
  ' "$1" >/dev/null 2>&1
}

build_catalog() {
  lbwc_build_catalog "$1" "$2"
}

refresh_catalog() {
  local planning_dir="$1" physical_planning reported_path binary
  physical_planning=$(resolve_planning_directory "$planning_dir")
  reported_path="$planning_dir/claude-capabilities.json"
  binary=$(resolve_claude_binary)
  cd -P -- "$physical_planning" || fail "could not enter planning directory: $planning_dir"
  assert_no_symbolic_links "$(pwd -P)"
  assert_no_symbolic_links 'claude-capabilities.json'
  LOCK_DIR='.claude-capabilities.lock'
  assert_no_symbolic_links "$LOCK_DIR"
  mkdir "$LOCK_DIR" 2>/dev/null || fail "could not acquire capability catalog lock: $LOCK_DIR"
  TEMPORARY=$(mktemp './.claude-capabilities.json.tmp.XXXXXX') || fail 'could not create capability catalog temporary file'
  build_catalog "$binary" "$TEMPORARY"
  validate_catalog_json "$TEMPORARY" || fail 'extracted Claude Code capability catalog is invalid'
  assert_no_symbolic_links 'claude-capabilities.json'
  mv -f "$TEMPORARY" 'claude-capabilities.json' || fail 'could not atomically persist Claude Code capability catalog'
  TEMPORARY=""
  printf '%s\n' "$reported_path"
}

validate_catalog_file() {
  local path="$1"
  assert_no_symbolic_links "$path"
  [ -f "$path" ] || fail "capability catalog is not readable: $path"
  validate_catalog_json "$path" || fail "invalid Claude Code capability catalog: $path"
  printf '%s\n' "$path"
}

refresh_from_binary() {
  local binary="$1" temporary
  binary=$(realpath "$binary" 2>/dev/null) || fail "could not resolve Claude Code executable: $binary"
  [ -f "$binary" ] || fail "Claude Code executable is not a file: $binary"
  [ -x "$binary" ] || fail "Claude Code executable is not executable: $binary"
  temporary=$(mktemp "${TMPDIR:-/tmp}/lbwc-claude-capabilities.XXXXXX") || fail 'could not create capability temporary file'
  TEMPORARY="$temporary"
  build_catalog "$binary" "$temporary"
  validate_catalog_json "$temporary" || fail 'extracted Claude Code capability catalog is invalid'
  cat "$temporary"
  rm -f "$temporary"
  TEMPORARY=""
}

catalog_planning_directory() {
  local path="$1" parent
  [ "${path##*/}" = 'claude-capabilities.json' ] || return 1
  parent=${path%/*}
  [ "$parent" != "$path" ] || parent=.
  [ "${parent##*/}" = '.lbwc-planning' ] || return 1
  resolve_planning_directory "$parent"
}

main() {
  local command="${1:-}" target="${2:-}" state_planning selector mapped
  require_tools
  if [ "$command" = map-agent-model ]; then
    selector="${3:-}"
    [ -n "$target" ] && [ -n "$selector" ] && [ "$#" -eq 3 ] || {
      usage
      exit 1
    }
    umask 077
    trap cleanup EXIT
    mapped=$(lbwc_map_agent_model "$target" "$selector") \
      || fail "model selector is not present in the live host Agent enum: $selector"
    printf '%s\n' "$mapped"
    return 0
  fi
  [ -n "$command" ] && [ -n "$target" ] && [ "$#" -eq 2 ] || {
    usage
    exit 1
  }
  if [ "$command" = refresh ]; then
    [ -f "$ROUTING_PATH" ] || fail "routing transaction script is unavailable: $ROUTING_PATH"
    if [ "${LBWC_CONFIG_TRANSACTION_ACTIVE:-0}" != 1 ]; then
      resolve_planning_directory "$target" >/dev/null
      exec bash "$ROUTING_PATH" transaction "$target" bash "$SCRIPT_DIR/claude-capabilities.sh" "$@"
    fi
    bash "$ROUTING_PATH" assert-transaction "$target" >/dev/null
  fi
  if [ "$command" = validate ] && state_planning=$(catalog_planning_directory "$target")
  then
    [ -f "$ROUTING_PATH" ] || fail "routing transaction script is unavailable: $ROUTING_PATH"
    if [ "${LBWC_CONFIG_TRANSACTION_ACTIVE:-0}" != 1 ]
    then
      exec bash "$ROUTING_PATH" transaction "$state_planning" \
        bash "$SCRIPT_DIR/claude-capabilities.sh" "$@"
    fi
    bash "$ROUTING_PATH" assert-transaction "$state_planning" >/dev/null
  fi
  umask 077
  trap cleanup EXIT
  case "$command" in
    refresh)
      refresh_catalog "$target"
      ;;
    refresh-from-binary)
      refresh_from_binary "$target"
      ;;
    validate)
      validate_catalog_file "$target"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
