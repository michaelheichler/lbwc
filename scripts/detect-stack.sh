#!/bin/bash

set -euo pipefail
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)"}' >&2
  exit 1
fi

PROJECT_DIR="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAPPINGS="$SCRIPT_DIR/../config/stack-mappings.json"

if [ ! -f "$MAPPINGS" ]; then
  echo '{"error":"stack-mappings.json not found"}' >&2
  exit 1
fi

INSTALLED_GLOBAL=""
INSTALLED_PROJECT=""
. "$(dirname "$0")/resolve-claude-dir.sh"
if [ -d "$CLAUDE_DIR/skills" ]; then
  INSTALLED_GLOBAL=$(ls -1 "$CLAUDE_DIR/skills/" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
fi
if [ -d "$PROJECT_DIR/.claude/skills" ]; then
  INSTALLED_PROJECT=$(ls -1 "$PROJECT_DIR/.claude/skills/" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
fi

read_manifest() {
  local filename="$1"
  local content=""
  if [ -f "$PROJECT_DIR/$filename" ]; then
    content=$(cat "$PROJECT_DIR/$filename" 2>/dev/null)
  fi
  while IFS= read -r subfile; do
    [ -z "$subfile" ] && continue
    content="$content"$'\n'"$(cat "$subfile" 2>/dev/null)"
  done < <(find "$PROJECT_DIR" -maxdepth 3 -name "$filename" \
    -not -path '*/node_modules/*' -not -path '*/.git/*' \
    -not -path '*/vendor/*' -not -path '*/target/*' \
    -not -path "$PROJECT_DIR/$filename" 2>/dev/null | head -10)
  echo "$content"
}

PKG_JSON=$(read_manifest "package.json")
REQUIREMENTS_TXT=$(read_manifest "requirements.txt")
PYPROJECT_TOML=$(read_manifest "pyproject.toml")
GEMFILE=$(read_manifest "Gemfile")
CARGO_TOML=$(read_manifest "Cargo.toml")
GO_MOD=$(read_manifest "go.mod")
COMPOSER_JSON=$(read_manifest "composer.json")
MIX_EXS=$(read_manifest "mix.exs")
POM_XML=$(read_manifest "pom.xml")
BUILD_GRADLE=$(read_manifest "build.gradle")

manifest_content() {
  case "$1" in
    package.json)      printf '%s' "$PKG_JSON" ;;
    requirements.txt) printf '%s' "$REQUIREMENTS_TXT" ;;
    pyproject.toml)    printf '%s' "$PYPROJECT_TOML" ;;
    Gemfile)           printf '%s' "$GEMFILE" ;;
    Cargo.toml)        printf '%s' "$CARGO_TOML" ;;
    go.mod)            printf '%s' "$GO_MOD" ;;
    composer.json)     printf '%s' "$COMPOSER_JSON" ;;
    mix.exs)           printf '%s' "$MIX_EXS" ;;
    pom.xml)           printf '%s' "$POM_XML" ;;
    build.gradle)      printf '%s' "$BUILD_GRADLE" ;;
  esac
}

check_dependency_pattern() {
  local pattern="$1"
  local file dep content
  file="${pattern%%:*}"
  dep="${pattern#*:}"
  content=$(manifest_content "$file")

  if [ -n "$content" ] && echo "$content" | grep -qF "\"$dep\""; then
    return 0
  fi
  if [[ "$file" != *.json ]] && [ -n "$content" ] && echo "$content" | grep -qiw "$dep"; then
    return 0
  fi
  return 1
}

check_file_pattern() {
  local pattern="$1"

  if [ -e "$PROJECT_DIR/$pattern" ]; then
    return 0
  fi
  if find "$PROJECT_DIR" -maxdepth 4 -name "$(basename "$pattern")" -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi
  return 1
}

check_pattern() {
  local pattern="$1"

  if [[ "$pattern" == *:* ]]; then
    check_dependency_pattern "$pattern"
  else
    check_file_pattern "$pattern"
  fi
}

DETECTED=""
RECOMMENDED_SKILLS=""

ENTRIES=$(jq -r '
  to_entries[] |
  select(.key | startswith("_") | not) |
  .key as $cat |
  .value | to_entries[] |
  [$cat, .key, (.value.description // .key), (.value.skills | join(";")), (.value.detect | join(";"))] |
  join("|")
' "$MAPPINGS" 2>/dev/null)

while IFS='|' read -r _category name _description skills_csv detect_csv; do
  [ -z "$name" ] && continue

  matched=false
  IFS=';' read -ra patterns <<< "$detect_csv"
  for pattern in "${patterns[@]}"; do
    if check_pattern "$pattern"; then
      matched=true
      break
    fi
  done

  if [ "$matched" = true ]; then
    if [ -n "$DETECTED" ]; then
      DETECTED="$DETECTED,$name"
    else
      DETECTED="$name"
    fi

    IFS=';' read -ra skill_list <<< "$skills_csv"
    for skill in "${skill_list[@]}"; do
      if ! echo ",$RECOMMENDED_SKILLS," | grep -qF ",$skill,"; then
        if [ -n "$RECOMMENDED_SKILLS" ]; then
          RECOMMENDED_SKILLS="$RECOMMENDED_SKILLS,$skill"
        else
          RECOMMENDED_SKILLS="$skill"
        fi
      fi
    done
  fi
done <<< "$ENTRIES"

SUGGESTIONS=""
IFS=',' read -ra rec_arr <<< "$RECOMMENDED_SKILLS"
# Invariant: processed suggestions equal project-missing recommendations (variant: unprocessed count).
for skill in "${rec_arr[@]}"; do
  [ -z "$skill" ] && continue
  if ! echo ",$INSTALLED_PROJECT," | grep -qF ",$skill,"; then
    if [ -n "$SUGGESTIONS" ]; then
      SUGGESTIONS="$SUGGESTIONS,$skill"
    else
      SUGGESTIONS="$skill"
    fi
  fi
done

jq -n \
  --arg detected "$DETECTED" \
  --arg installed_global "$INSTALLED_GLOBAL" \
  --arg installed_project "$INSTALLED_PROJECT" \
  --arg recommended "$RECOMMENDED_SKILLS" \
  --arg suggestions "$SUGGESTIONS" \
  --arg global_skills_dir "$CLAUDE_DIR/skills" \
  '{
    detected_stack: ($detected | split(",") | map(select(. != ""))),
    installed: {
      global: ($installed_global | split(",") | map(select(. != ""))),
      project: ($installed_project | split(",") | map(select(. != "")))
    },
    recommended_skills: ($recommended | split(",") | map(select(. != ""))),
    suggestions: ($suggestions | split(",") | map(select(. != ""))),
    global_skills_dir: $global_skills_dir
  }'
