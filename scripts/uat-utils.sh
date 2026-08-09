#!/usr/bin/env bash

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "Error: uat-utils.sh must be sourced, not executed directly" >&2
  exit 1
fi

normalize_uat_status() {
  local raw="${1:-}"
  case "$raw" in
    all_pass|passed|pass|all_passed|verified|no_issues) echo "complete" ;;
    failed) echo "issues_found" ;;
    *) echo "$raw" ;;
  esac
}

_uat_ascii_lower() {
  local input="${1:-}"
  local output=""
  local idx=0
  local char

  while [ "$idx" -lt "${#input}" ]; do
    char="${input:$idx:1}"
    case "$char" in
      A) char=a ;;
      B) char=b ;;
      C) char=c ;;
      D) char=d ;;
      E) char=e ;;
      F) char=f ;;
      G) char=g ;;
      H) char=h ;;
      I) char=i ;;
      J) char=j ;;
      K) char=k ;;
      L) char=l ;;
      M) char=m ;;
      N) char=n ;;
      O) char=o ;;
      P) char=p ;;
      Q) char=q ;;
      R) char=r ;;
      S) char=s ;;
      T) char=t ;;
      U) char=u ;;
      V) char=v ;;
      W) char=w ;;
      X) char=x ;;
      Y) char=y ;;
      Z) char=z ;;
    esac
    output="${output}${char}"
    idx=$((idx + 1))
  done

  printf '%s' "$output"
}

_uat_trim_ws() {
  local value="${1:-}"
  value="${value%$'\r'}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

_uat_strip_matching_quotes() {
  local value="${1:-}"
  case "$value" in
    \"*\")
      value="${value#\"}"
      value="${value%\"}"
      ;;
    \'*\')
      value="${value#\'}"
      value="${value%\'}"
      ;;
  esac
  printf '%s' "$value"
}

_uat_is_frontmatter_delimiter() {
  local line
  line="${1:-}"
  line="${line%$'\r'}"
  line="${line%"${line##*[![:space:]]}"}"
  [ "$line" = "---" ]
}

_uat_status_value_from_line() {
  local line="${1:-}"
  local key value

  case "$line" in
    *:*) ;;
    *) return 1 ;;
  esac

  key=${line%%:*}
  key=$(_uat_trim_ws "$key")
  key=$(_uat_ascii_lower "$key")
  [ "$key" = "status" ] || return 1

  value=${line#*:}
  value=$(_uat_trim_ws "$value")
  value=$(_uat_strip_matching_quotes "$value")
  value=$(_uat_ascii_lower "$value")
  printf '%s' "$value"
  return 0
}

_uat_status_value_known_for_body_fallback() {
  case "${1:-}" in
    issues_found|complete|passed|in_progress|pending|failed|aborted|all_pass|all_passed|pass|verified|no_issues)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_extract_uat_status_value() {
  local file="$1"
  local line line_num=0 result

  while IFS= read -r line || [ -n "$line" ]; do
    line_num=$((line_num + 1))
    line="${line%$'\r'}"
    if [ "$line_num" -eq 1 ]; then
      _uat_is_frontmatter_delimiter "$line" || break
      continue
    fi
    _uat_is_frontmatter_delimiter "$line" && break
    if result=$(_uat_status_value_from_line "$line"); then
      printf '%s' "$result"
      return 0
    fi
  done < "$file"

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      [[:space:]]*) continue ;;
    esac
    if result=$(_uat_status_value_from_line "$line") && _uat_status_value_known_for_body_fallback "$result"; then
      printf '%s' "$result"
      return 0
    fi
  done < "$file"

  printf '%s' ""
}

extract_status_value() {
  local file="$1" result
  result=$(_extract_uat_status_value "$file")
  result=$(normalize_uat_status "$result")
  printf '%s' "$result"
}

uat_status_class() {
  local status
  status=$(normalize_uat_status "${1:-}")
  case "$status" in
    "")
      printf '%s\n' "none"
      ;;
    complete)
      printf '%s\n' "complete"
      ;;
    issues_found)
      printf '%s\n' "issues_found"
      ;;
    *)
      printf '%s\n' "active"
      ;;
  esac
}

uat_file_status_value() {
  local file="$1" result
  [ -f "$file" ] || return 1
  result=$(_extract_uat_status_value "$file")
  result=$(normalize_uat_status "$result")
  printf '%s' "$result"
}

uat_file_has_frontmatter_status_key() {
  local file="$1"
  local line line_num=0
  [ -f "$file" ] || return 1

  while IFS= read -r line || [ -n "$line" ]; do
    line_num=$((line_num + 1))
    line="${line%$'\r'}"
    if [ "$line_num" -eq 1 ]; then
      _uat_is_frontmatter_delimiter "$line" || return 1
      continue
    fi
    _uat_is_frontmatter_delimiter "$line" && return 1
    if _uat_status_value_from_line "$line" >/dev/null; then
      return 0
    fi
  done < "$file"

  return 1
}

uat_file_is_remediation_round_uat() {
  case "$1" in
    */remediation/uat/round-*/R*-UAT.md|*/remediation/round-*/R*-UAT.md)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

uat_file_status_class() {
  local file="$1" status
  [ -f "$file" ] || { printf '%s\n' "none"; return 0; }
  status=$(uat_file_status_value "$file")
  if [ -n "$status" ]; then
    uat_status_class "$status"
  elif uat_file_has_frontmatter_status_key "$file" || uat_file_is_remediation_round_uat "$file"; then
    printf '%s\n' "active"
  else
    printf '%s\n' "none"
  fi
}

uat_status_class_blocks_completion() {
  case "${1:-none}" in
    issues_found|active) return 0 ;;
    *) return 1 ;;
  esac
}

latest_non_source_uat() {
  local dir="$1"
  local latest=""
  local latest_num=-1

  case "$dir" in
    */) ;;
    *) dir="$dir/" ;;
  esac

  for f in "${dir}"[0-9]*-UAT.md; do
    [ -f "$f" ] || continue
    case "$f" in *SOURCE-UAT.md) continue ;; esac
    local bname num
    bname=$(basename "$f")
    num=$(echo "$bname" | sed 's/^\([0-9]*\).*/\1/' | sed 's/^0*//')
    num=${num:-0}
    if [ "$num" -gt "$latest_num" ] 2>/dev/null; then
      latest_num=$num
      latest="$f"
    fi
  done

  if [ -n "$latest" ]; then
    printf '%s\n' "$latest"
  fi
  return 0
}

count_uat_rounds() {
  local dir="$1"
  local phase_num="$2"
  local max_round=0

  case "$dir" in
    */) ;;
    *) dir="$dir/" ;;
  esac

  for rf in "${dir}${phase_num}"-UAT-round-*.md; do
    [ -f "$rf" ] || continue
    local round_num
    round_num=$(basename "$rf" | sed "s/^${phase_num}-UAT-round-0*\\([0-9]*\\)\\.md$/\\1/")
    if [ -n "$round_num" ] && echo "$round_num" | grep -qE '^[0-9]+$'; then
      if [ "$round_num" -gt "$max_round" ] 2>/dev/null; then
        max_round="$round_num"
      fi
    fi
  done

  for rf in "${dir}"remediation/uat/round-*/R*-UAT.md; do
    [ -f "$rf" ] || continue
    local rr_num
    rr_num=$(basename "$rf" | sed 's/^R0*\([0-9]*\)-UAT\.md$/\1/')
    if [ -n "$rr_num" ] && echo "$rr_num" | grep -qE '^[0-9]+$'; then
      if [ "$rr_num" -gt "$max_round" ] 2>/dev/null; then
        max_round="$rr_num"
      fi
    fi
  done

  printf '%d' "$max_round"
}

uat_phase_num_for_dir() {
  local phase_dir="$1" phase_basename phase_num

  phase_basename=$(basename "$phase_dir")
  phase_num=$(printf '%s\n' "$phase_basename" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')
  printf '%s' "$phase_num"
}

uat_infer_legacy_current_round() {
  local phase_dir="$1" phase_num archived_rounds current_round

  phase_num=$(uat_phase_num_for_dir "$phase_dir")
  if [ -z "$phase_num" ]; then
    echo "01"
    return 0
  fi

  archived_rounds=$(count_uat_rounds "$phase_dir" "$phase_num")
  if [[ "$archived_rounds" =~ ^[0-9]+$ ]] && [ "$archived_rounds" -gt 0 ] 2>/dev/null; then
    current_round=$((archived_rounds + 1))
    printf '%02d\n' "$current_round"
    return 0
  fi

  echo "01"
}

uat_resolve_legacy_round() {
  local phase_dir="$1" stored_round="${2:-}" stored_num

  stored_num=$(printf '%s\n' "$stored_round" | sed 's/^0*//')
  stored_num="${stored_num:-0}"

  if [ "$stored_num" -gt 1 ] 2>/dev/null; then
    printf '%02d\n' "$stored_num"
    return 0
  fi

  uat_infer_legacy_current_round "$phase_dir"
}

extract_round_issue_ids() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk '
    function tolower_str(s,    i, c, out, upper, lower, pos) {
      upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
      lower = "abcdefghijklmnopqrstuvwxyz"
      out = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        pos = index(upper, c)
        if (pos > 0)
          c = substr(lower, pos, 1)
        out = out c
      }
      return out
    }
    /^### (P[0-9]+(-T[0-9]+)?|PR[0-9]+-T[0-9]+|D[0-9]+)(:|[[:space:]])/ {
      id = $2
      sub(/:$/, "", id)
      has_issue = 0
      next
    }
    /^- \*\*Result:\*\*/ {
      val = $0
      sub(/^- \*\*Result:\*\*[[:space:]]*/, "", val)
      gsub(/[[:space:]]+$/, "", val)
      lval = tolower_str(val)
      if (lval ~ /^(issue|fail|failed|partial)/) {
        print id
      }
    }
  ' "$file"
}

current_uat() {
  local dir="$1"

  case "$dir" in
    */) ;;
    *) dir="$dir/" ;;
  esac

  local state_file=""
  if [ -f "${dir}remediation/uat/.uat-remediation-stage" ]; then
    state_file="${dir}remediation/uat/.uat-remediation-stage"
  elif [ -f "${dir}remediation/.uat-remediation-stage" ]; then
    state_file="${dir}remediation/.uat-remediation-stage"
  elif [ -f "${dir}.uat-remediation-stage" ]; then
    state_file="${dir}.uat-remediation-stage"
  fi
  if [ -f "$state_file" ]; then
    local layout round rr
    layout=$(grep '^layout=' "$state_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    round=$(grep '^round=' "$state_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    case "$state_file" in
      */remediation/.uat-remediation-stage|*/.uat-remediation-stage)
        layout="${layout:-legacy}"
        round="${round:-01}"
        ;;
    esac
    if [ "$layout" = "round-dir" ] && [ -n "$round" ]; then
      rr=$(printf '%02d' "$round" 2>/dev/null) || rr="$round"
      local round_uat="${dir}remediation/uat/round-${rr}/R${rr}-UAT.md"
      if [ -f "$round_uat" ]; then
        printf '%s\n' "$round_uat"
        return 0
      fi
      local _prev_best="" _prev_best_num=-1
      for _ruat in "${dir}"remediation/uat/round-*/R*-UAT.md; do
        [ -f "$_ruat" ] || continue
        local _rnum
        _rnum=$(basename "$_ruat" | sed 's/^R0*\([0-9]*\)-UAT\.md$/\1/')
        if [ -n "$_rnum" ] && echo "$_rnum" | grep -qE '^[0-9]+$'; then
          if [ "$_rnum" -gt "$_prev_best_num" ] 2>/dev/null; then
            _prev_best_num=$_rnum
            _prev_best="$_ruat"
          fi
        fi
      done
      if [ -n "$_prev_best" ]; then
        printf '%s\n' "$_prev_best"
        return 0
      fi
    elif [ "$layout" = "legacy" ] && [ -n "$round" ]; then
      rr=$(printf '%02d' "$round" 2>/dev/null) || rr="$round"
      local legacy_round_uat="${dir}remediation/round-${rr}/R${rr}-UAT.md"
      if [ -f "$legacy_round_uat" ]; then
        printf '%s\n' "$legacy_round_uat"
        return 0
      fi
      local _legacy_best="" _legacy_best_num=-1
      for _legacy_uat in "${dir}"remediation/round-*/R*-UAT.md; do
        [ -f "$_legacy_uat" ] || continue
        local _legacy_num
        _legacy_num=$(basename "$_legacy_uat" | sed 's/^R0*\([0-9]*\)-UAT\.md$/\1/')
        if [ -n "$_legacy_num" ] && echo "$_legacy_num" | grep -qE '^[0-9]+$'; then
          if [ "$_legacy_num" -gt "$_legacy_best_num" ] 2>/dev/null; then
            _legacy_best_num=$_legacy_num
            _legacy_best="$_legacy_uat"
          fi
        fi
      done
      if [ -n "$_legacy_best" ]; then
        printf '%s\n' "$_legacy_best"
        return 0
      fi
    fi
  fi

  latest_non_source_uat "${dir%/}"
}

current_uat_status_class() {
  local dir="$1" uat_file
  uat_file=$(current_uat "$dir")
  [ -n "$uat_file" ] && [ -f "$uat_file" ] || { printf '%s\n' "none"; return 0; }
  uat_file_status_class "$uat_file"
}

current_uat_blocks_phase_completion() {
  local class
  class=$(current_uat_status_class "$1" 2>/dev/null || printf '%s\n' "none")
  uat_status_class_blocks_completion "$class"
}

current_uat_needs_remediation() {
  [ "$(current_uat_status_class "$1" 2>/dev/null || printf '%s\n' "none")" = "issues_found" ]
}

current_uat_needs_verification() {
  [ "$(current_uat_status_class "$1" 2>/dev/null || printf '%s\n' "none")" = "active" ]
}
