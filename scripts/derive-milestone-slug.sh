#!/usr/bin/env bash
set -euo pipefail


PLANNING_DIR="${1:-.lbwc-planning}"
STATE="$PLANNING_DIR/STATE.md"
ROADMAP="$PLANNING_DIR/ROADMAP.md"

if [[ ! -f "$ROADMAP" ]]; then
  echo "Error: ROADMAP.md not found at $ROADMAP" >&2
  exit 1
fi

normalize_slug() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | \
    sed 's/[^a-z0-9 -]//g' | \
    sed 's/  */ /g' | \
    tr ' ' '-' | \
    sed 's/--*/-/g' | \
    sed 's/^-//;s/-$//'
}

derive_slug() {
  local slug=""
  local milestone_name=""

  if [[ -f "$STATE" ]]; then
    milestone_name=$(awk '
      /^\*\*Milestone:\*\*/ {
        sub(/^\*\*Milestone:\*\*[[:space:]]*/, "")
        sub(/[[:space:]]*$/, "")
        if (length > 0) {
          print
          exit
        }
      }
    ' "$STATE")
    if [[ -n "$milestone_name" ]]; then
      normalize_slug "$milestone_name"
      return
    fi
  fi

  local roadmap_content
  roadmap_content=$(cat "$ROADMAP")
  roadmap_content="${roadmap_content//$'\xE2\x80\x94'/-}"
  roadmap_content="${roadmap_content//$'\xE2\x80\x93'/-}"

  local phase_names
  phase_names=$(printf '%s\n' "$roadmap_content" | awk '
    /^## Phase [0-9]+:/ {
      sub(/^## Phase [0-9]+:[[:space:]]*/, "")
      sub(/[[:space:]]*$/, "")
      if (length > 0) print
    }
  ' | head -3)

  if [[ -n "$phase_names" ]]; then
    slug=$(echo "$phase_names" | tr '\n' ' ' | sed 's/ $//')
    slug=$(normalize_slug "$slug")
    if [[ ${#slug} -gt 60 ]]; then
      slug=$(echo "$slug" | head -c 60 | sed 's/-[^-]*$//')
    fi
    echo "$slug"
    return
  fi

  phase_names=$(printf '%s\n' "$roadmap_content" | awk '
    /^[0-9]+\. / {
      sub(/^[0-9]+\.[[:space:]]+/, "")
      gsub(/\*\*/, "")
      sub(/ - .*/, "")
      sub(/[[:space:]]*$/, "")
      if (length > 0) print
    }
  ' | head -3)

  if [[ -n "$phase_names" ]]; then
    slug=$(echo "$phase_names" | tr '\n' ' ' | sed 's/ $//')
    slug=$(normalize_slug "$slug")
    if [[ ${#slug} -gt 60 ]]; then
      slug=$(echo "$slug" | head -c 60 | sed 's/-[^-]*$//')
    fi
    echo "$slug"
    return
  fi

  phase_names=$(printf '%s\n' "$roadmap_content" | awk '
    /^[-*][[:space:]]+(\[[ xX]\][[:space:]]+)?(Phase [0-9]+:[[:space:]]+)?/ {
      sub(/^[-*][[:space:]]+(\[[ xX]\][[:space:]]+)?(Phase [0-9]+:[[:space:]]+)?/, "")
      sub(/ - .*/, "")
      sub(/[[:space:]]*$/, "")
      if (length > 0) print
    }
  ' | head -3)

  if [[ -n "$phase_names" ]]; then
    slug=$(echo "$phase_names" | tr '\n' ' ' | sed 's/ $//')
    slug=$(normalize_slug "$slug")
    if [[ ${#slug} -gt 60 ]]; then
      slug=$(echo "$slug" | head -c 60 | sed 's/-[^-]*$//')
    fi
    echo "$slug"
    return
  fi
  if [[ -d "$PLANNING_DIR/phases" ]]; then
    local dir_names
    dir_names=$(ls -1 "$PLANNING_DIR/phases/" 2>/dev/null | sed 's/^[0-9]*-//' | head -3)
    if [[ -n "$dir_names" ]]; then
      slug=$(echo "$dir_names" | tr '\n' ' ' | sed 's/ $//')
      slug=$(normalize_slug "$slug")
      if [[ ${#slug} -gt 60 ]]; then
        slug=$(echo "$slug" | head -c 60 | sed 's/-[^-]*$//')
      fi
      echo "$slug"
      return
    fi
  fi

  echo "milestone-$(date +%Y%m%d)"
}

milestone_number() {
  local count=0
  if [[ -d "$PLANNING_DIR/milestones" ]]; then
    local d
    for d in "$PLANNING_DIR/milestones"/*/; do
      [[ -d "$d" ]] || continue
      count=$((count + 1))
    done
  fi
  printf "%02d" $((count + 1))
}

slug_name=$(derive_slug)
ms_num=$(milestone_number)

if [[ -z "$slug_name" ]]; then
  slug_name="milestone-$(date +%Y%m%d)"
fi

full_slug="${ms_num}-${slug_name}"

TARGET_DIR="$PLANNING_DIR/milestones/$full_slug"
if [[ -d "$TARGET_DIR" ]]; then
  suffix=1
  while [[ -d "${TARGET_DIR}-${suffix}" ]]; do
    suffix=$((suffix + 1))
    if [[ $suffix -gt 10 ]]; then
      echo "Error: cannot find unique slug (tried $full_slug through $full_slug-10)" >&2
      exit 1
    fi
  done
  full_slug="${full_slug}-${suffix}"
fi

echo "$full_slug"
