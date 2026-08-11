#!/usr/bin/env bash
set -euo pipefail

JSON_OUTPUT=0
LOCK_DIR=""
LOCK_HELD=0
TEMP_PATH=""

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit "${2:-2}"
}

usage() {
  printf '%s\n' 'Usage: lbwc-conventions.sh [--json] <list|group|add|remove|reconcile|refresh> <planning-dir> [arguments]' >&2
  exit 2
}

cleanup() {
  [ -z "$TEMP_PATH" ] || rm -f -- "$TEMP_PATH" 2>/dev/null || true
  [ "$LOCK_HELD" -eq 0 ] || rmdir "$LOCK_DIR" 2>/dev/null || true
}

require_tools() {
  local tool
  for tool in chmod date dirname jq mktemp mkdir mv pwd readlink rm rmdir; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
  done
}

resolve_known_system_alias() {
  local current="$1" target
  case "$current" in
    /var|/var/*)
      if [ -L /var ]; then
        target=$(readlink /var) || fail 'could not resolve the macOS /var alias'
        if [ "$target" = 'private/var' ]; then
          printf '/private/var%s\n' "${current#/var}"
          return 0
        fi
      fi
      ;;
  esac
  printf '%s\n' "$current"
}

assert_no_symbolic_links() {
  local current="$1" parent
  current=$(resolve_known_system_alias "$current")
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

resolve_planning_dir() {
  local input="$1" trimmed parent physical_parent
  case "/$input/" in
    */../*|*/./*) fail "planning directory traversal is not allowed: $input" ;;
  esac
  trimmed="$input"
  while [ "$trimmed" != "/" ] && [ "${trimmed%/}" != "$trimmed" ]; do
    trimmed=${trimmed%/}
  done
  [ ! -L "$trimmed" ] || fail "planning directory boundary must not be a symbolic link: $input"
  [ "${trimmed##*/}" = '.lbwc-planning' ] || fail "planning directory must end with .lbwc-planning: $input"
  assert_no_symbolic_links "$trimmed"
  [ -d "$trimmed" ] || fail "planning directory does not exist: $input"
  case "$trimmed" in
    */*) parent=${trimmed%/*}; [ -n "$parent" ] || parent=/ ;;
    *) parent=. ;;
  esac
  physical_parent=$(cd -P -- "$parent" 2>/dev/null && pwd -P) \
    || fail "could not resolve planning directory: $input"
  assert_no_symbolic_links "$physical_parent"
  printf '%s/.lbwc-planning\n' "$physical_parent"
}

empty_artifact() {
  printf '%s\n' '{"conventions":[],"schema_version":1}'
}

normalize_artifact() {
  local value="$1" today
  today=$(date -u +%Y-%m-%d) || fail 'could not determine the current date'
  jq -ceS --arg today "$today" '
    def category: IN("file-structure", "naming", "testing", "style", "tooling", "patterns", "other");
    def valid_text: type == "string" and length > 0 and (test("[[:cntrl:]]") | not);
    def legacy_artifact:
      (has("schema_version") | not)
      and ((keys_unsorted | sort) == ["conventions"])
      and all(.conventions[];
        type == "object" and ((keys_unsorted | sort) == ["rule", "tag"])
      );
    if type == "object"
      and (.conventions | type == "array")
      and ((has("schema_version") and .schema_version == 1) or legacy_artifact)
      and all(.conventions[]; (.rule | valid_text) and (.tag | valid_text))
    then . else error("invalid conventions artifact") end
    |
    .conventions as $entries
    | reduce range(0; $entries | length) as $index (
        {schema_version: 1, conventions: []};
        $entries[$index] as $entry
        | ($entry.category // ($entry.tag | ascii_downcase)) as $raw_category
        | (if ($raw_category | category) then $raw_category else "other" end) as $category
        | ($entry.source // "user-defined") as $source
        | .conventions += [
            $entry + {
              id: ($entry.id // ("CONV-" + (($index + 1) | tostring | ("000" + .)[-3:]))),
              tag: $entry.tag,
              rule: $entry.rule,
              source: (if $source == "auto-detected" then $source else "user-defined" end),
              category: $category,
              confidence: (if $source == "auto-detected" then ($entry.confidence // "medium") else null end),
              detected_from: (if $source == "auto-detected" then ($entry.detected_from // "legacy") else null end),
              added: ($entry.added // $today)
            }
          ]
      )
    | if ([.conventions[].id] | length) != ([.conventions[].id] | unique | length)
      then error("duplicate convention id") else . end
    | if all(.conventions[];
        (.id | type == "string" and test("^CONV-[0-9]{3,}$"))
        and (.category | category)
        and (.source | IN("user-defined", "auto-detected"))
        and (.added | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))
        and (if .source == "auto-detected"
          then (.confidence | IN("high", "medium", "low")) and (.detected_from | type == "string" and length > 0)
          else .confidence == null and .detected_from == null end)
      ) then . else error("invalid convention entry") end
    | .conventions |= sort_by(.id)
  ' <<< "$value" 2>/dev/null || fail 'invalid conventions artifact'
}

read_artifact() {
  local planning_dir="$1" path value
  path="$planning_dir/conventions.json"
  [ ! -L "$path" ] || fail "symbolic link artifacts are not allowed: $path"
  if [ ! -e "$path" ]; then
    empty_artifact
    return 0
  fi
  [ -f "$path" ] || fail "conventions artifact is not a regular file: $path"
  value=$(<"$path") || fail "could not read conventions artifact: $path"
  normalize_artifact "$value"
}

validate_candidates() {
  local value="$1"
  jq -ceS '
    def category: IN("file-structure", "naming", "testing", "style", "tooling", "patterns", "other");
    def source_file: IN("PATTERNS.md", "ARCHITECTURE.md", "STACK.md", "CONCERNS.md");
    def valid_text: type == "string" and length > 0 and (test("[[:cntrl:]]") | not);
    if type != "object" or .schema_version != 1 or (.conventions | type != "array") or (.conventions | length > 15)
      then error("invalid candidate set") else . end
    | if all(.conventions[];
        (.rule | valid_text)
        and (.category | category)
        and (.confidence | IN("high", "medium", "low"))
        and (.detected_from | source_file)
        and ((.conflicts_with // []) | type == "array" and all(.[]; type == "string" and test("^CONV-[0-9]{3,}$")))
      ) then . else error("invalid candidate") end
  ' <<< "$value" 2>/dev/null || fail 'invalid convention candidates'
}

read_candidates() {
  local source="$1" value
  if [ "$source" = '-' ]; then
    value=$(</dev/stdin) || fail 'could not read convention candidates from stdin'
  else
    [ ! -L "$source" ] || fail "symbolic link candidate files are not allowed: $source"
    [ -f "$source" ] || fail "candidate file is not readable: $source"
    value=$(<"$source") || fail "could not read candidate file: $source"
  fi
  validate_candidates "$value"
}

acquire_lock() {
  local planning_dir="$1"
  LOCK_DIR="$planning_dir/.conventions.lock"
  [ ! -L "$LOCK_DIR" ] || fail "symbolic link locks are not allowed: $LOCK_DIR"
  mkdir "$LOCK_DIR" 2>/dev/null || fail "could not acquire conventions lock: $LOCK_DIR"
  LOCK_HELD=1
  [ -d "$LOCK_DIR" ] && [ ! -L "$LOCK_DIR" ] || fail "invalid conventions lock: $LOCK_DIR"
}

write_artifact() {
  local planning_dir="$1" value="$2" path
  path="$planning_dir/conventions.json"
  [ ! -L "$path" ] || fail "symbolic link artifacts are not allowed: $path"
  TEMP_PATH=$(mktemp "$planning_dir/.conventions.json.tmp.XXXXXXXXXXXX") \
    || fail 'could not create conventions temporary file'
  chmod 600 "$TEMP_PATH" || fail 'could not protect conventions temporary file'
  jq -ceS '.conventions |= sort_by(.id)' <<< "$value" > "$TEMP_PATH" \
    || fail 'could not serialize conventions artifact'
  [ ! -L "$path" ] || fail "symbolic link artifacts are not allowed: $path"
  mv -f -- "$TEMP_PATH" "$path" || fail 'could not replace conventions artifact'
  TEMP_PATH=""
}

compact_json() {
  jq -cS '.' <<< "$1"
}

render_next() {
  printf '\n%s\n' 'Next: continue your current LBWC workflow.'
}

render_table() {
  local value="$1" count
  count=$(jq '.conventions | length' <<< "$value")
  printf 'Project conventions (%s)\n\n' "$count"
  if [ "$count" -eq 0 ]; then
    printf '%s\n' 'No conventions are saved.'
    render_next
    return 0
  fi
  printf '%-10s  %-16s  %-13s  %-10s  %s\n' 'ID' 'Category' 'Source' 'Confidence' 'Rule'
  printf '%-10s  %-16s  %-13s  %-10s  %s\n' '----------' '----------------' '-------------' '----------' '----'
  jq -r '.conventions[] | [.id, .category, .source, (.confidence // "user"), .rule] | @tsv' <<< "$value" |
    while IFS=$'\t' read -r id category source confidence rule; do
      printf '%-10s  %-16s  %-13s  %-10s  %s\n' "$id" "$category" "$source" "$confidence" "$rule"
    done
  render_next
}

render_grouped() {
  local value="$1" category
  while IFS= read -r category; do
    printf '%s\n' "[$category]"
    jq -r --arg category "$category" '.conventions[] | select(.category == $category) | "  \(.id)  \(.rule)  [\(.source)]"' <<< "$value"
    printf '\n'
  done < <(jq -r '[.conventions[].category] | unique[]' <<< "$value")
}

group_json() {
  jq -ceS 'reduce .conventions[] as $item ({}; .[$item.category] = ((.[$item.category] // []) + [$item]))' <<< "$1"
}

next_id_number() {
  jq '[.conventions[].id | capture("^CONV-(?<n>[0-9]+)$").n | tonumber] | max // 0 | . + 1' <<< "$1"
}

format_id() {
  printf 'CONV-%03d\n' "$1"
}

normalized_rule() {
  jq -nr --arg rule "$1" '$rule | ascii_downcase | gsub("[[:space:]]+"; " ") | sub("^ "; "") | sub(" $"; "")'
}

validate_rule_text() {
  jq -ne --arg value "$1" '$value | type == "string" and length > 0 and (test("[[:cntrl:]]") | not)' >/dev/null 2>&1
}

add_convention() {
  local planning_dir="$1" category="$2" rule="$3"
  shift 3
  local conflict_id="" replace_id="" keep_both=0 current normalized duplicate next id tag today result
  case "$category" in
    file-structure|naming|testing|style|tooling|patterns|other) ;;
    *) fail "unknown convention category: $category" ;;
  esac
  validate_rule_text "$rule" || fail 'convention rule must be one non-empty line'
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --conflicts-with) [ "$#" -ge 2 ] || usage; conflict_id="$2"; shift 2 ;;
      --replace) [ "$#" -ge 2 ] || usage; replace_id="$2"; shift 2 ;;
      --keep-both) keep_both=1; shift ;;
      *) usage ;;
    esac
  done
  [ -z "$replace_id" ] || [ "$keep_both" -eq 0 ] || fail 'choose either --replace or --keep-both'
  acquire_lock "$planning_dir"
  current=$(read_artifact "$planning_dir")
  if [ -n "$conflict_id" ]; then
    jq -e --arg id "$conflict_id" '.conventions | any(.id == $id)' <<< "$current" >/dev/null \
      || fail "conflicting convention not found: $conflict_id"
    if [ -z "$replace_id" ] && [ "$keep_both" -eq 0 ]; then
      fail "conflict with $conflict_id requires --replace or --keep-both" 4
    fi
    [ -z "$replace_id" ] || [ "$replace_id" = "$conflict_id" ] \
      || fail 'replacement id must match the declared conflict'
  fi
  if [ -n "$replace_id" ]; then
    jq -e --arg id "$replace_id" '.conventions | any(.id == $id)' <<< "$current" >/dev/null \
      || fail "replacement convention not found: $replace_id"
  fi
  normalized=$(normalized_rule "$rule")
  duplicate=$(jq -r --arg normalized "$normalized" --arg replace "$replace_id" '
    def norm: ascii_downcase | gsub("[[:space:]]+"; " ") | sub("^ "; "") | sub(" $"; "");
    [.conventions[] | select(.id != $replace and (.rule | norm) == $normalized) | .id][0] // empty
  ' <<< "$current")
  [ -z "$duplicate" ] || fail "convention is redundant with $duplicate" 3
  next=$(next_id_number "$current")
  id=$(format_id "$next")
  tag=$(jq -nr --arg category "$category" '$category | ascii_upcase')
  today=$(date -u +%Y-%m-%d)
  result=$(jq -ceS --arg id "$id" --arg rule "$rule" --arg category "$category" \
    --arg tag "$tag" --arg today "$today" --arg replace "$replace_id" '
      .conventions |= map(select(.id != $replace))
      | .conventions += [{
          id: $id, tag: $tag, rule: $rule, source: "user-defined", category: $category,
          confidence: null, detected_from: null, added: $today
        }]
      | .conventions |= sort_by(.id)
    ' <<< "$current") || fail 'could not add convention'
  write_artifact "$planning_dir" "$result"
  if [ "$JSON_OUTPUT" -eq 1 ]; then compact_json "$result"; else printf 'Added %s: %s [%s]\n' "$id" "$rule" "$category"; render_next; fi
}

remove_convention() {
  local planning_dir="$1" id="$2" confirmation="${3:-}" current rule result
  [ "$confirmation" = '--yes' ] || fail "removing $id requires --yes" 4
  acquire_lock "$planning_dir"
  current=$(read_artifact "$planning_dir")
  rule=$(jq -r --arg id "$id" '.conventions[] | select(.id == $id) | .rule' <<< "$current")
  [ -n "$rule" ] || fail "convention not found: $id"
  result=$(jq -ceS --arg id "$id" '.conventions |= map(select(.id != $id))' <<< "$current")
  write_artifact "$planning_dir" "$result"
  if [ "$JSON_OUTPUT" -eq 1 ]; then compact_json "$result"; else printf 'Removed %s: %s\n' "$id" "$rule"; render_next; fi
}

reconciled_artifact() {
  local current="$1" candidates="$2" today
  today=$(date -u +%Y-%m-%d)
  jq -nceS --argjson current "$current" --argjson candidates "$candidates" --arg today "$today" '
    def norm: ascii_downcase | gsub("[[:space:]]+"; " ") | sub("^ "; "") | sub(" $"; "");
    def rank: if . == "high" then 0 elif . == "medium" then 1 else 2 end;
    ($current.conventions | map(select(.source == "user-defined"))) as $users
    | ($current.conventions | map(select(.source == "auto-detected"))) as $old_auto
    | ([ $current.conventions[].id | capture("^CONV-(?<n>[0-9]+)$").n | tonumber ] | max // 0) as $max_id
    | ($candidates.conventions
        | map(. as $candidate | select(
            ($candidate.conflicts_with // []) as $conflicts
            | all($users[];
                . as $user
                | (($conflicts | index($user.id)) == null)
                  and (($user.rule | norm) != ($candidate.rule | norm))
              )
          ))) as $conflict_filtered
    | ($conflict_filtered
        | map(. as $candidate | select(all($users[]; (.rule | norm) != ($candidate.rule | norm))))
        | map(. as $candidate | select(
            $candidate.confidence != "low"
            or ([$conflict_filtered[] | select(.category == $candidate.category and .confidence != "low")] | length == 0)
          ))
        | sort_by((.confidence | rank), .category, (.rule | norm))
        | unique_by(.rule | norm)
      ) as $accepted
    | reduce $accepted[] as $candidate (
        {next: $max_id, conventions: $users};
        ($old_auto | map(select((.rule | norm) == ($candidate.rule | norm)))[0]) as $old
        | if $old then
            .conventions += [$old + $candidate + {
              tag: ($candidate.category | ascii_upcase), source: "auto-detected",
              conflicts_with: ($candidate.conflicts_with // [])
            }]
          else
            .next += 1
            | .conventions += [$candidate + {
              id: ("CONV-" + ((.next | tostring | ("000" + .)[-3:]))),
              tag: ($candidate.category | ascii_upcase), source: "auto-detected",
              added: $today, conflicts_with: ($candidate.conflicts_with // [])
            }]
          end
      )
    | {schema_version: 1, conventions: (.conventions | sort_by(.id))}
  ' 2>/dev/null || fail 'could not reconcile convention candidates'
}

unknown_conflict_reference() {
  local current="$1" candidates="$2"
  jq -nr --argjson current "$current" --argjson candidates "$candidates" '
    ([ $current.conventions[].id ] | unique) as $known
    | [ $candidates.conventions[].conflicts_with[]? | select(($known | index(.)) == null) ]
    | unique
    | .[0] // empty
  '
}

render_change_counts() {
  local current="$1" result="$2"
  jq -nr --argjson current "$current" --argjson result "$result" '
    ($current.conventions | map({key: .id, value: .}) | from_entries) as $before
    | ($result.conventions | map({key: .id, value: .}) | from_entries) as $after
    | ([ $after | keys[] | select($before[.] == null) ] | length) as $added
    | ([ $before | keys[] | select($after[.] == null) ] | length) as $removed
    | ([ $after | keys[] | select($before[.] != null and $before[.] != $after[.]) ] | length) as $updated
    | ([ $after | keys[] | select($before[.] == $after[.]) ] | length) as $kept
    | "Added: \($added) | Updated: \($updated) | Removed: \($removed) | Kept: \($kept)"
  '
}

run_reconcile() {
  local planning_dir="$1" source="$2" persist="$3" current candidates unknown result counts
  if [ "$persist" -eq 1 ]; then acquire_lock "$planning_dir"; fi
  current=$(read_artifact "$planning_dir")
  candidates=$(read_candidates "$source")
  unknown=$(unknown_conflict_reference "$current" "$candidates")
  [ -z "$unknown" ] || fail "unknown conflict reference: $unknown"
  result=$(reconciled_artifact "$current" "$candidates")
  normalize_artifact "$result" >/dev/null
  counts=$(render_change_counts "$current" "$result")
  if [ "$persist" -eq 1 ]; then write_artifact "$planning_dir" "$result"; fi
  if [ "$JSON_OUTPUT" -eq 1 ]; then
    compact_json "$result"
  elif [ "$persist" -eq 1 ]; then
    printf 'Refreshed conventions.\n%s\n\n' "$counts"
    render_table "$result"
  else
    printf 'Convention reconciliation preview. No files changed.\n%s\n\n' "$counts"
    render_table "$result"
  fi
}

main() {
  local operation planning_dir value
  require_tools
  if [ "${1:-}" = '--json' ]; then JSON_OUTPUT=1; shift; fi
  operation="${1:-}"
  [ -n "$operation" ] || usage
  shift
  [ "$#" -ge 1 ] || usage
  planning_dir=$(resolve_planning_dir "$1")
  shift
  case "$operation" in
    list)
      [ "$#" -eq 0 ] || usage
      value=$(read_artifact "$planning_dir")
      if [ "$JSON_OUTPUT" -eq 1 ]; then compact_json "$value"; else render_table "$value"; fi
      ;;
    group)
      [ "$#" -eq 0 ] || usage
      value=$(read_artifact "$planning_dir")
      if [ "$JSON_OUTPUT" -eq 1 ]; then group_json "$value"; else render_grouped "$value"; render_next; fi
      ;;
    add) [ "$#" -ge 2 ] || usage; add_convention "$planning_dir" "$@" ;;
    remove) [ "$#" -ge 1 ] || usage; remove_convention "$planning_dir" "$@" ;;
    reconcile) [ "$#" -eq 1 ] || usage; run_reconcile "$planning_dir" "$1" 0 ;;
    refresh) [ "$#" -eq 1 ] || usage; run_reconcile "$planning_dir" "$1" 1 ;;
    *) usage ;;
  esac
}

trap cleanup EXIT HUP INT TERM
main "$@"
