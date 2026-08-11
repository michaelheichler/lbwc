#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -gt 1 ]; then
  echo "QA-VERIFIED ITEMS (do NOT generate UAT checkpoints for these):"
  for phase_dir in "$@"; do
    printf '  Phase: %s\n' "$(basename "$phase_dir")"
    if ! LBWC_EXTRACT_SUPPRESS_HEADER=1 bash "$0" "$phase_dir"; then
      printf '  WARNING: failed to extract verified items for %s\n' "$phase_dir" >&2
    fi
  done
  exit 0
fi

phase_dir="${1:-}"
if [[ -z "$phase_dir" || ! -d "$phase_dir" ]]; then
  exit 0
fi

verif_files=()
append_verif_file() {
  local candidate="$1"
  local existing
  [ -n "$candidate" ] || return 0
  [ -f "$candidate" ] || return 0
  if [[ ${#verif_files[@]} -gt 0 ]]; then
    for existing in "${verif_files[@]}"; do
      [ "$existing" = "$candidate" ] && return 0
    done
  fi
  verif_files+=("$candidate")
}

phase_verif=$(bash "$SCRIPT_DIR/resolve-verification-path.sh" phase "$phase_dir" 2>/dev/null || true)
authoritative_verif=$(bash "$SCRIPT_DIR/resolve-verification-path.sh" authoritative "$phase_dir" 2>/dev/null || true)

if [ -n "$authoritative_verif" ] && [ "$authoritative_verif" != "$phase_verif" ]; then
  append_verif_file "$authoritative_verif"
  if [[ ${#verif_files[@]} -eq 0 ]]; then
    exit 0
  fi
else
  while IFS= read -r f; do
    append_verif_file "$f"
  done < <(ls "$phase_dir"/*-VERIFICATION*.md 2>/dev/null)
  append_verif_file "$phase_dir/VERIFICATION.md"

  if [ -n "$authoritative_verif" ] && [ -f "$authoritative_verif" ]; then
    verif_files=()
  fi
  append_verif_file "$authoritative_verif"
fi

if [[ ${#verif_files[@]} -eq 0 ]]; then
  exit 0
fi

if [ "${LBWC_EXTRACT_SUPPRESS_HEADER:-0}" != 1 ]; then
  echo "QA-VERIFIED ITEMS (do NOT generate UAT checkpoints for these):"
fi

for vf in "${verif_files[@]}"; do
  result=""
  passed=""
  failed=""
  total=""
  tier=""
  in_frontmatter=false
  fm_count=0

  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      fm_count=$((fm_count + 1))
      if [[ $fm_count -eq 1 ]]; then
        in_frontmatter=true
        continue
      elif [[ $fm_count -eq 2 ]]; then
        in_frontmatter=false
        break
      fi
    fi
    if [[ "$in_frontmatter" == true ]]; then
      case "$line" in
        result:*) result=$(echo "$line" | sed 's/^result: *//') ;;
        passed:*) passed=$(echo "$line" | sed 's/^passed: *//') ;;
        failed:*) failed=$(echo "$line" | sed 's/^failed: *//') ;;
        total:*)  total=$(echo "$line" | sed 's/^total: *//') ;;
        tier:*)   tier=$(echo "$line" | sed 's/^tier: *//') ;;
      esac
    fi
  done < "$vf"

  deterministic=false
  if grep -qE '^## (Must-Have Checks|Artifact Checks|Key Link Checks|Anti-Pattern Scan|Convention Compliance|Requirement Mapping|Skill-Augmented Checks|Other Checks)' "$vf" 2>/dev/null; then
    if grep -q '| # | ID |' "$vf" 2>/dev/null; then
      deterministic=true
    fi
  fi

  if [[ "$deterministic" == true ]]; then
    current_section=""
    while IFS= read -r line; do
      case "$line" in
        "## Must-Have Checks"*) current_section="must_have" ;;
        "## Artifact Checks"*) current_section="artifact" ;;
        "## Key Link Checks"*) current_section="key_link" ;;
        "## Anti-Pattern Scan"*) current_section="anti_pattern" ;;
        "## Convention Compliance"*) current_section="convention" ;;
        "## Requirement Mapping"*) current_section="requirement" ;;
        "## Skill-Augmented Checks"*) current_section="skill_augmented" ;;
        "## Other Checks"*) current_section="other" ;;
        "## Pre-existing"*|"## Summary"*) current_section="" ;;
        "| "*)
          if [[ "$line" == *"---|"* ]] || [[ "$line" == *"| # |"* ]] || [[ "$line" == *"| ID |"* ]]; then
            continue
          fi
          if [[ -n "$current_section" ]]; then
            safe_line=$(echo "$line" | sed 's/\&#124;/__PIPE__/g')
            check_id=$(echo "$safe_line" | awk -F'|' '{gsub(/^ +| +$/, "", $3); print $3}')
            description=$(echo "$safe_line" | awk -F'|' '{gsub(/^ +| +$/, "", $4); print $4}' | sed 's/__PIPE__/|/g')
            col_count=$(echo "$safe_line" | tr -cd '|' | wc -c | tr -d ' ')
            if [[ "$col_count" -eq 7 ]]; then
              case "$current_section" in
                convention)
                  status=$(echo "$safe_line" | awk -F'|' '{gsub(/^ +| +$/, "", $6); print $6}') ;;
                *)
                  status=$(echo "$safe_line" | awk -F'|' '{gsub(/^ +| +$/, "", $7); print $7}') ;;
              esac
            else
              status=$(echo "$safe_line" | awk -F'|' '{gsub(/^ +| +$/, "", $5); print $5}')
            fi
            status=$(echo "$status" | sed 's/\*\*//g')
            if [[ -n "$check_id" && -n "$status" ]]; then
              echo "  $status $check_id: $description"
            fi
          fi
          ;;
      esac
    done < "$vf"
  else
    if grep -qE '^✓ \*\*|^⚠ \*\*' "$vf" 2>/dev/null; then
      grep -E '^✓ \*\*' "$vf" 2>/dev/null | sed 's/\*\*//g; s/ \xE2\x80\x94 .*//' | while IFS= read -r line; do
        echo "  $line"
      done || true
      grep -E '^⚠ \*\*' "$vf" 2>/dev/null | sed 's/\*\*//g; s/ \xE2\x80\x94 .*//' | while IFS= read -r line; do
        echo "  $line"
      done || true
    fi

    total_line=$(grep -E '^\| \*\*Total\*\*' "$vf" 2>/dev/null | head -1 || true)
    if [[ -n "$total_line" ]]; then
      old_passed=$(echo "$total_line" | sed 's/\*\*//g' | awk -F'|' '{print $3}' | tr -d ' ')
      old_failed=$(echo "$total_line" | sed 's/\*\*//g' | awk -F'|' '{print $4}' | tr -d ' ')
      old_warned=$(echo "$total_line" | sed 's/\*\*//g' | awk -F'|' '{print $5}' | tr -d ' ')
      echo "  QA totals: ${old_passed} passed, ${old_failed} failed, ${old_warned} warned"
    fi
  fi

  if [[ -n "$result" && -n "$total" ]]; then
    echo ""
    echo "  QA: $result (${passed:-0}/${total} passed${failed:+, ${failed} failed}${tier:+, tier: $tier})"
  else
    verdict=$(grep -i 'Verdict' "$vf" 2>/dev/null | sed 's/^#* *//; s/\*\*//g' | head -1 || true)
    if [[ -n "$verdict" ]]; then
      echo ""
      echo "  $verdict"
    fi
  fi
done
