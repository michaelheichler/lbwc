#!/usr/bin/env bash
set -u

migration_collect_rows() {
  local buffer="$1"
  local row

  # Invariant: emitted rows are exactly the eligible table rows seen so far (variant: unread buffer lines).
  while IFS= read -r row; do
    [[ "$row" =~ ^\|\ *Decision ]] && continue
    [[ "$row" =~ ^\|[-[:space:]|]+\|$ ]] && continue
    [[ "$row" =~ _\(No\ decisions\ yet\)_ ]] && continue
    [[ "$row" =~ ^\| ]] || continue
    printf '%s\n' "$row"
  done <<< "$buffer"
}

migration_count_rows() {
  local rows="$1"
  printf '%s\n' "$rows" | awk 'NF { count++ } END { print count + 0 }'
}

migration_collect_unique_rows() {
  local state_path="$1"
  local data_rows="$2"
  local drow

  # Invariant: emitted rows are eligible rows absent from STATE.md among rows seen so far (variant: unread data rows).
  while IFS= read -r drow; do
    [[ -z "$drow" ]] && continue
    if ! tr -s ' ' < "$state_path" | grep -qF "$(printf '%s' "$drow" | tr -s ' ')"; then
      printf '%s\n' "$drow"
    fi
  done <<< "$data_rows"
}

migration_write_unique_rows() {
  printf '%s\n' "$MIGRATION_UNIQUE_ROWS"
}

migration_process_key_decisions_heading() {
  local sline="$1"
  [[ "$sline" == "## Key Decisions" ]] || return 1
  MIGRATION_IN_KD_SECTION=true
  MIGRATION_PAST_SEPARATOR=false
  MIGRATION_ROWS_INSERTED=false
  echo "$sline" >> "$MIGRATION_TMP_STATE"
}

migration_process_section_boundary() {
  local sline="$1"
  [[ "$MIGRATION_IN_KD_SECTION" == true && "$sline" =~ ^##\  ]] || return 1
  if [[ "$MIGRATION_PAST_SEPARATOR" == true && "$MIGRATION_ROWS_INSERTED" == false ]]; then
    migration_write_unique_rows >> "$MIGRATION_TMP_STATE"
    MIGRATION_ROWS_INSERTED=true
  fi
  echo "" >> "$MIGRATION_TMP_STATE"
  MIGRATION_IN_KD_SECTION=false
  echo "$sline" >> "$MIGRATION_TMP_STATE"
}

migration_process_key_decisions_body() {
  local sline="$1"
  [[ "$MIGRATION_IN_KD_SECTION" == true ]] || return 1
  if [[ "$sline" =~ ^\|[-[:space:]|]+\|$ && ! "$sline" =~ ^\|\ *Decision ]]; then
    MIGRATION_PAST_SEPARATOR=true
    echo "$sline" >> "$MIGRATION_TMP_STATE"
    return 0
  fi
  [[ "$sline" =~ _\(No\ decisions\ yet\)_ ]] && return 0
  [[ "$MIGRATION_PAST_SEPARATOR" == true && -z "$sline" ]] && return 0
  return 1
}

migration_process_state_line() {
  local sline="$1"
  if migration_process_key_decisions_heading "$sline"; then return; fi
  if migration_process_section_boundary "$sline"; then return; fi
  if migration_process_key_decisions_body "$sline"; then return; fi
  echo "$sline" >> "$MIGRATION_TMP_STATE"
}

migration_rewrite_state() {
  local state_path="$1"
  local unique_rows="$2"
  local tmp_state

  tmp_state="$(mktemp)"
  MIGRATION_TMP_STATE="$tmp_state"
  MIGRATION_UNIQUE_ROWS="$unique_rows"
  MIGRATION_IN_KD_SECTION=false
  MIGRATION_PAST_SEPARATOR=false
  MIGRATION_ROWS_INSERTED=false

  # Invariant: the temporary file mirrors processed STATE.md lines and contains new rows only after its separator (variant: unread state lines).
  while IFS= read -r sline || [[ -n "$sline" ]]; do
    migration_process_state_line "$sline"
  done < "$state_path"

  if [[ "$MIGRATION_IN_KD_SECTION" == true && "$MIGRATION_PAST_SEPARATOR" == true && "$MIGRATION_ROWS_INSERTED" == false ]]; then
    migration_write_unique_rows >> "$MIGRATION_TMP_STATE"
    MIGRATION_ROWS_INSERTED=true
  fi
  if [[ "$MIGRATION_PAST_SEPARATOR" == false ]]; then
    rm -f "$tmp_state"
    echo "Warning: Cannot migrate $MIGRATION_UNIQUE_COUNT Key Decisions row(s), STATE.md Key Decisions section has no table" >&2
    return 1
  fi
  mv "$tmp_state" "$state_path"
}

migrate_key_decisions_to_state() {
  local buffer="$1"
  local state_path data_rows row_count unique_rows unique_count

  state_path="$(dirname "$OUTPUT_PATH")/.lbwc-planning/STATE.md"
  data_rows=$(migration_collect_rows "$buffer")
  row_count=$(migration_count_rows "$data_rows")
  [[ "$row_count" -eq 0 ]] && return 0
  if [[ ! -f "$state_path" ]]; then
    echo "Warning: Cannot migrate $row_count Key Decisions row(s), STATE.md not found at $state_path" >&2
    return 1
  fi
  if ! grep -q '^## Key Decisions' "$state_path"; then
    echo "Warning: Cannot migrate $row_count Key Decisions row(s), no ## Key Decisions section in STATE.md" >&2
    return 1
  fi

  unique_rows=$(migration_collect_unique_rows "$state_path" "$data_rows")
  unique_count=$(migration_count_rows "$unique_rows")
  [[ "$unique_count" -eq 0 ]] && {
    echo "Skipped migration, all $row_count Key Decisions row(s) already in STATE.md" >&2
    return 0
  }
  MIGRATION_UNIQUE_COUNT="$unique_count"
  migration_rewrite_state "$state_path" "$unique_rows" || return 1
  echo "Migrated $unique_count Key Decisions row(s) from CLAUDE.md to STATE.md" >&2
}

migration_preserved_deprecated_notes() {
  local buffer="$1"
  local bline first_line=true preserved=""

  # Invariant: preserved contains non-table lines after the section header (variant: unread deprecated-section lines).
  while IFS= read -r bline; do
    if [[ "$first_line" == true ]]; then
      first_line=false
      continue
    fi
    [[ "$bline" =~ ^\|\ *Decision ]] && continue
    [[ "$bline" =~ ^\|[-[:space:]|]+\|$ ]] && continue
    [[ "$bline" =~ ^\| ]] && continue
    preserved+="${bline}"$'\n'
  done <<< "$buffer"
  printf '%s' "$preserved"
}

flush_deprecated_buffer() {
  if [[ "$IN_DEPRECATED_SECTION" != true ]]; then
    return 0
  fi
  if [[ "$DEPRECATED_HAS_USER_CONTENT" == true ]] && ! migrate_key_decisions_to_state "$DEPRECATED_SECTION_BUFFER"; then
    NON_LBWC_CONTENT+="${DEPRECATED_SECTION_BUFFER}"
    FOUND_NON_LBWC=true
    IN_DEPRECATED_SECTION=false
    DEPRECATED_SECTION_BUFFER=""
    DEPRECATED_HAS_USER_CONTENT=false
    return
  fi

  local preserved section_label
  section_label="${DEPRECATED_SECTION_BUFFER%%$'\n'*}"
  section_label="${section_label#\#\# }"
  preserved=$(migration_preserved_deprecated_notes "$DEPRECATED_SECTION_BUFFER")
  if [[ -n "${preserved//[[:space:]]/}" ]]; then
    preserved="$(echo "$preserved" | sed '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
    NON_LBWC_CONTENT+="## ${section_label} (Archived Notes)"$'\n\n'"${preserved}"$'\n\n'
    export FOUND_NON_LBWC=true
  fi

  IN_DEPRECATED_SECTION=false
  DEPRECATED_SECTION_BUFFER=""
  DEPRECATED_HAS_USER_CONTENT=false
}
