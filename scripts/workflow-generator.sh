#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PLUGIN_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
. "$SCRIPT_DIR/lib/agent-manifest.sh"
. "$SCRIPT_DIR/lib/workflow-manifest.sh"

fail() {
  printf 'workflow-generator: %s\n' "$1" >&2
  exit 1
}

assert_workflow_capability() {
  local control_root="$1" config_path catalog_path reasons
  config_path="$control_root/config.json"
  catalog_path="$control_root/claude-capabilities.json"
  [ -z "${CLAUDE_CODE_DISABLE_WORKFLOWS:-}" ] || fail 'workflow backend is unavailable: CLAUDE_CODE_DISABLE_WORKFLOWS is set in this session'
  [ -z "${CLAUDE_CODE_SUBAGENT_MODEL:-}" ] || fail 'workflow backend is unavailable: CLAUDE_CODE_SUBAGENT_MODEL is set in this session, which overrides both the session model and any model a workflow script routes'
  [ -f "$config_path" ] && [ ! -L "$config_path" ] || fail "workflow backend is unavailable: no configuration at $config_path"
  jq -e '.workflow_execution.enabled == true' "$config_path" >/dev/null 2>&1 || fail 'workflow backend is disabled in configuration'
  [ -f "$catalog_path" ] && [ ! -L "$catalog_path" ] || fail "workflow backend is unavailable: no capability catalog at $catalog_path, run scripts/claude-capabilities.sh refresh first"
  jq -e '.workflow | type == "object"' "$catalog_path" >/dev/null 2>&1 || fail "workflow backend is unavailable: capability catalog carries no workflow probe: $catalog_path"
  jq -e '.workflow.available == true' "$catalog_path" >/dev/null 2>&1 && return 0
  reasons=$(jq -r '.workflow.unavailable_reasons | join(" ")' "$catalog_path" 2>/dev/null)
  fail "workflow backend is unavailable: $reasons"
}

usage() {
  printf 'Usage: workflow-generator.sh solo <role> --job TEXT --contract PATH --task-id ID --name NAME [--control-root PATH]\n' >&2
  printf '       workflow-generator.sh pair <role> --job TEXT --contract PATH --task-id ID --autonomy VALUE --engineer-name NAME --critic-name NAME [--pair-role ROLE] [--control-root PATH]\n' >&2
  printf '       workflow-generator.sh trio <role> --job TEXT --contract PATH --task-id ID --autonomy VALUE --engineer-name NAME --critic-name NAME --testdev-name NAME [--control-root PATH]\n' >&2
  exit 1
}

ROLE_DEFAULTS_PATH="$PLUGIN_ROOT/templates/agent-roles/defaults.json"
[ -f "$ROLE_DEFAULTS_PATH" ] || fail "role defaults not found: $ROLE_DEFAULTS_PATH"
is_valid_role() { jq -e --arg role "$1" 'has($role)' "$ROLE_DEFAULTS_PATH" >/dev/null 2>&1; }

SHAPE="${1:-}"
case "$SHAPE" in
  solo|pair|trio) ;;
  *) usage ;;
esac
shift
ROLE="${1:-}"
[ -n "$ROLE" ] || usage
shift
is_valid_role "$ROLE" || fail "invalid role '$ROLE'"

JOB=""
CONTRACT_PATH=""
TASK_ID=""
CONTROL_ROOT_ARG=""
AUTONOMY=""
NAME=""
ENGINEER_NAME=""
CRITIC_NAME=""
TESTDEV_NAME=""
PAIR_ROLE_ARG=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --job) JOB="${2:-}"; shift 2 ;;
    --contract) CONTRACT_PATH="${2:-}"; shift 2 ;;
    --task-id) TASK_ID="${2:-}"; shift 2 ;;
    --control-root) CONTROL_ROOT_ARG="${2:-}"; shift 2 ;;
    --autonomy) AUTONOMY="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --engineer-name) ENGINEER_NAME="${2:-}"; shift 2 ;;
    --critic-name) CRITIC_NAME="${2:-}"; shift 2 ;;
    --testdev-name) TESTDEV_NAME="${2:-}"; shift 2 ;;
    --pair-role) PAIR_ROLE_ARG="${2:-}"; shift 2 ;;
    *) fail "unknown option '$1'" ;;
  esac
done

[ -n "$JOB" ] || fail "--job is required"
[ -n "$CONTRACT_PATH" ] || fail "--contract is required"
[ -n "$TASK_ID" ] || fail "--task-id is required"

case "$SHAPE" in
  solo)
    [ -n "$NAME" ] || fail "--name is required for solo"
    ;;
  pair)
    [ -n "$ENGINEER_NAME" ] || fail "--engineer-name is required for pair"
    [ -n "$CRITIC_NAME" ] || fail "--critic-name is required for pair"
    case "$AUTONOMY" in
      cautious|standard|confident|pure-vibe) ;;
      *) fail "invalid --autonomy '$AUTONOMY'" ;;
    esac
    ;;
  trio)
    [ -n "$ENGINEER_NAME" ] || fail "--engineer-name is required for trio"
    [ -n "$CRITIC_NAME" ] || fail "--critic-name is required for trio"
    [ -n "$TESTDEV_NAME" ] || fail "--testdev-name is required for trio"
    case "$AUTONOMY" in
      cautious|standard|confident|pure-vibe) ;;
      *) fail "invalid --autonomy '$AUTONOMY'" ;;
    esac
    ;;
esac

if [ "${CONTRACT_PATH:0:1}" != "/" ]; then
  CONTRACT_PATH="$PWD/$CONTRACT_PATH"
fi
CONTRACT_PATH=$(cd "$(dirname "$CONTRACT_PATH")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "$CONTRACT_PATH")") || fail "contract path is unavailable"
[ -f "$CONTRACT_PATH" ] || fail "contract not found: $CONTRACT_PATH"

PROJECT_ROOT=$(jq -r '.project_root // empty' "$CONTRACT_PATH" 2>/dev/null) || fail "invalid contract"
[ -n "$PROJECT_ROOT" ] || fail "contract project root is required"
PROJECT_ROOT=$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P) || fail "contract project root is unavailable"

CONTRACT_SCHEMA_PREVIEW=$(jq -r '.schema_version // empty' "$CONTRACT_PATH" 2>/dev/null) || fail "invalid contract"
[ "$CONTRACT_SCHEMA_PREVIEW" = "3" ] || fail "workflow generation requires a schema 3 contract"

CONTRACT_CONTROL_ROOT_RAW=$(jq -r '.control_root // empty' "$CONTRACT_PATH" 2>/dev/null) || fail "invalid contract"
[ -n "$CONTROL_ROOT_ARG" ] || CONTROL_ROOT_ARG="$CONTRACT_CONTROL_ROOT_RAW"
CONTROL_ROOT=$(lbwc_control_root_validate "$CONTROL_ROOT_ARG" 0) || fail "control root is unavailable or invalid"
CONTRACT_CONTROL_ROOT=$(lbwc_control_root_validate "$CONTRACT_CONTROL_ROOT_RAW" 0) || fail "contract control root is unavailable"
[ "$CONTROL_ROOT" = "$CONTRACT_CONTROL_ROOT" ] || fail "contract control root mismatch"

assert_workflow_capability "$CONTROL_ROOT"

CONTRACT_JSON=$(bash "$SCRIPT_DIR/task-contract.sh" verify "$CONTRACT_PATH" "$PROJECT_ROOT" --job "$JOB" 2>&1) || fail "$CONTRACT_JSON"
CONTRACT_JSON=$(jq -ce 'select(type == "object")' <<< "$CONTRACT_JSON" 2>/dev/null) || fail "invalid contract"

jq -e '.schema_version == 3 and .created_by == "main" and .state == "planned"' <<< "$CONTRACT_JSON" >/dev/null \
  || fail "contract must be a planned schema 3 main-session contract"

CONTRACT_ROOT=$(jq -r '.project_root // empty' <<< "$CONTRACT_JSON")
[ "$CONTRACT_ROOT" = "$PROJECT_ROOT" ] || fail "contract project root mismatch"

CONTRACT_ID=$(jq -r '.contract_id // empty' <<< "$CONTRACT_JSON")
[ -n "$CONTRACT_ID" ] || fail "contract id is required"

CONTRACT_TASK_IDENTITY=$(jq -r '.task_identity // empty' <<< "$CONTRACT_JSON")
[ -n "$CONTRACT_TASK_IDENTITY" ] || fail "contract task identity is required"
[ "$TASK_ID" = "$CONTRACT_TASK_IDENTITY" ] || fail "contract task identity mismatch"
workflow_manifest_safe_contract_id "$CONTRACT_ID" || fail "contract id is not safe for a workflow manifest key"

CONTRACT_ROLE=$(jq -r '.role // empty' <<< "$CONTRACT_JSON")
[ "$CONTRACT_ROLE" = "$ROLE" ] || fail "contract role mismatch"

CONTRACT_TEAM_MODE=$(jq -r '.team_mode // empty' <<< "$CONTRACT_JSON")
[ "$CONTRACT_TEAM_MODE" = "$SHAPE" ] || fail "contract team mode mismatch"

CONTRACT_REQUESTED_BACKEND=$(jq -r '.requested_backend // empty' <<< "$CONTRACT_JSON")
CONTRACT_RESOLVED_BACKEND=$(jq -r '.resolved_backend // empty' <<< "$CONTRACT_JSON")
[ "$CONTRACT_REQUESTED_BACKEND" = "workflow" ] || fail "contract requested backend is not workflow"
[ "$CONTRACT_RESOLVED_BACKEND" = "workflow" ] || fail "contract resolved backend is not workflow"

PAIR_ROLE=""
TRIO_ROLES=()
case "$SHAPE" in
  pair)
    if [ -n "$PAIR_ROLE_ARG" ]; then
      PAIR_ROLE="$PAIR_ROLE_ARG"
    else
      PAIR_ROLE=$(jq -r --arg r "$ROLE" '.[$r].pairsWith // empty' "$ROLE_DEFAULTS_PATH")
    fi
    [ -n "$PAIR_ROLE" ] || fail "pair requires defaults.json's '$ROLE.pairsWith' or an explicit --pair-role"
    is_valid_role "$PAIR_ROLE" || fail "invalid pair role '$PAIR_ROLE'"
    ;;
  trio)
    mapfile -t TRIO_ROLES < <(jq -r --arg r "$ROLE" '.trios[$r] // [] | .[]' "$ROLE_DEFAULTS_PATH")
    [ "${#TRIO_ROLES[@]}" -eq 3 ] || fail "trio requires defaults.json's 'trios.$ROLE' to list exactly 3 roles"
    for trio_role in "${TRIO_ROLES[@]}"; do
      is_valid_role "$trio_role" || fail "invalid trio role '$trio_role'"
    done
    ;;
esac

AGENT_MANIFEST_JSON=$(agent_manifest_read "$CONTROL_ROOT") || fail "invalid agent manifest"

CHECKED_MODEL=""
CHECKED_EFFORT=""
check_named_agent() {
  local name="$1" expected_role="$2" entry def_path def_digest
  entry=$(jq -c --arg n "$name" '.agents[$n] // empty' <<< "$AGENT_MANIFEST_JSON") || fail "invalid agent manifest"
  [ -n "$entry" ] || fail "agent name is not registered in the manifest: $name"
  [ "$(jq -r '.role // empty' <<< "$entry")" = "$expected_role" ] || fail "manifest role mismatch for '$name'"
  [ "$(jq -r '.contract_id // empty' <<< "$entry")" = "$CONTRACT_ID" ] || fail "manifest contract id mismatch for '$name'"
  [ "$(jq -r '.task_identity // empty' <<< "$entry")" = "$TASK_ID" ] || fail "manifest task identity mismatch for '$name'"
  def_path=$(agent_manifest_definition_path "$CONTROL_ROOT" "$name") || fail "invalid agent name: $name"
  [ -f "$def_path" ] || fail "agent definition file is missing: $def_path"
  def_digest=$(shasum -a 256 "$def_path" | awk '{print $1}')
  [ "$def_digest" = "$(jq -r '.definition_sha256 // empty' <<< "$entry")" ] || fail "manifest definition digest mismatch for '$name'"
  CHECKED_MODEL=$(grep -m1 '^model:' "$def_path" | sed 's/^model: "//; s/"$//') || true
  CHECKED_EFFORT=$(grep -m1 '^effort:' "$def_path" | sed 's/^effort: "//; s/"$//') || true
  [ -n "$CHECKED_MODEL" ] || fail "definition file for '$name' has no resolved model"
}

ROSTER_JSON='[]'
RENDER_ARGS=(NAME="$TASK_ID" DESCRIPTION="$JOB" JOB="$JOB" TASK_ID="$TASK_ID")
case "$SHAPE" in
  solo)
    check_named_agent "$NAME" "$ROLE"
    RENDER_ARGS+=(ROLE="$ROLE" AGENT_TYPE="$NAME" MODEL="$CHECKED_MODEL" EFFORT="$CHECKED_EFFORT")
    ROSTER_JSON=$(jq -cn --arg n "$NAME" '[$n]')
    ;;
  pair)
    check_named_agent "$ENGINEER_NAME" "$ROLE"
    ENGINEER_MODEL="$CHECKED_MODEL"
    ENGINEER_EFFORT="$CHECKED_EFFORT"
    check_named_agent "$CRITIC_NAME" "$PAIR_ROLE"
    CRITIC_MODEL="$CHECKED_MODEL"
    CRITIC_EFFORT="$CHECKED_EFFORT"
    RENDER_ARGS+=(AUTONOMY="$AUTONOMY" \
      ENGINEER_AGENT_TYPE="$ENGINEER_NAME" ENGINEER_MODEL="$ENGINEER_MODEL" ENGINEER_EFFORT="$ENGINEER_EFFORT" \
      CRITIC_AGENT_TYPE="$CRITIC_NAME" CRITIC_MODEL="$CRITIC_MODEL" CRITIC_EFFORT="$CRITIC_EFFORT")
    ROSTER_JSON=$(jq -cn --arg e "$ENGINEER_NAME" --arg c "$CRITIC_NAME" '[$e, $c]')
    ;;
  trio)
    check_named_agent "$ENGINEER_NAME" "${TRIO_ROLES[0]}"
    ENGINEER_MODEL="$CHECKED_MODEL"
    ENGINEER_EFFORT="$CHECKED_EFFORT"
    check_named_agent "$CRITIC_NAME" "${TRIO_ROLES[1]}"
    CRITIC_MODEL="$CHECKED_MODEL"
    CRITIC_EFFORT="$CHECKED_EFFORT"
    check_named_agent "$TESTDEV_NAME" "${TRIO_ROLES[2]}"
    TESTDEV_MODEL="$CHECKED_MODEL"
    TESTDEV_EFFORT="$CHECKED_EFFORT"
    RENDER_ARGS+=(AUTONOMY="$AUTONOMY" \
      ENGINEER_AGENT_TYPE="$ENGINEER_NAME" ENGINEER_MODEL="$ENGINEER_MODEL" ENGINEER_EFFORT="$ENGINEER_EFFORT" \
      CRITIC_AGENT_TYPE="$CRITIC_NAME" CRITIC_MODEL="$CRITIC_MODEL" CRITIC_EFFORT="$CRITIC_EFFORT" \
      TESTDEV_AGENT_TYPE="$TESTDEV_NAME" TESTDEV_MODEL="$TESTDEV_MODEL" TESTDEV_EFFORT="$TESTDEV_EFFORT")
    ROSTER_JSON=$(jq -cn --arg e "$ENGINEER_NAME" --arg c "$CRITIC_NAME" --arg t "$TESTDEV_NAME" '[$e, $c, $t]')
    ;;
esac

WORKFLOWS_DIR="$CONTROL_ROOT/workflows"
TARGET="$WORKFLOWS_DIR/$CONTRACT_ID.js"

[ ! -e "$TARGET" ] || fail "workflow script already exists: $TARGET"
mkdir -p "$WORKFLOWS_DIR" || fail "could not create workflows directory: $WORKFLOWS_DIR"

WORKFLOW_COMMITTED=""
cleanup_on_failure() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ -z "$WORKFLOW_COMMITTED" ]; then
    rm -f "$TARGET"
  fi
}
trap cleanup_on_failure EXIT

tmp="${TARGET}.tmp.${BASHPID:-$$}"
if ! bash "$SCRIPT_DIR/render-workflow-template.sh" "$SHAPE" "${RENDER_ARGS[@]}" > "$tmp"; then
  rm -f "$tmp"
  fail "could not render workflow script"
fi
mv -f "$tmp" "$TARGET" || { rm -f "$tmp"; fail "could not install workflow script"; }

strip_string_spans() {
  awk '
    BEGIN { instr = 0; quote = ""; esc = 0 }
    {
      out = ""
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (instr) {
          if (esc) { esc = 0 }
          else if (c == "\\") { esc = 1 }
          else if (c == quote) { instr = 0 }
          continue
        }
        if (c == "\"" || c == "`" || c == "'\''") { instr = 1; quote = c; continue }
        out = out c
      }
      print out
    }
  ' "$1"
}
string_spans_unterminated() {
  awk '
    BEGIN { instr = 0; quote = ""; esc = 0 }
    {
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (instr) {
          if (esc) { esc = 0 }
          else if (c == "\\") { esc = 1 }
          else if (c == quote) { instr = 0 }
          continue
        }
        if (c == "\"" || c == "`" || c == "'\''") { instr = 1; quote = c }
      }
    }
    END { exit (instr ? 0 : 1) }
  ' "$1"
}
check_balanced_delimiters() {
  awk '
    BEGIN { p = 0; b = 0; k = 0 }
    {
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (c == "(") p++
        else if (c == ")") { p--; if (p < 0) exit 1 }
        else if (c == "{") b++
        else if (c == "}") { b--; if (b < 0) exit 1 }
        else if (c == "[") k++
        else if (c == "]") { k--; if (k < 0) exit 1 }
      }
    }
    END { exit (p == 0 && b == 0 && k == 0 ? 0 : 1) }
  ' <<< "$1"
}
CODE_OUTSIDE_STRINGS=$(strip_string_spans "$TARGET")

case "$CODE_OUTSIDE_STRINGS" in
  *"@@"*) fail "unresolved template token survived rendering" ;;
esac

TARGET_CONTENT=$(cat "$TARGET")
case "$TARGET_CONTENT" in
  *$'\x1f'*) fail "unit separator sentinel survived rendering" ;;
esac

META_LINE=$(head -n1 "$TARGET")
case "$META_LINE" in
  "export const meta = "*";") ;;
  *) fail "rendered meta line has an unexpected shape" ;;
esac
META_JSON=${META_LINE#"export const meta = "}
META_JSON=${META_JSON%";"}
jq -e . <<< "$META_JSON" >/dev/null 2>&1 || fail "rendered meta line is not valid JSON"

BODY_PHASE_TITLES=$(tail -n +2 "$TARGET" | grep -oE 'phase\("[^"]*"\)' | sed -E 's/^phase\("//; s/"\)$//') || true
BODY_PHASES_JSON=$(jq -Rcs 'split("\n") | map(select(length > 0))' <<< "$BODY_PHASE_TITLES")
META_PHASES_JSON=$(jq -c '.phases' <<< "$META_JSON")
[ "$BODY_PHASES_JSON" = "$META_PHASES_JSON" ] || fail "phase() calls do not match meta.phases"

for forbidden in import 'require(' 'Date.now' 'Math.random'; do
  case "$CODE_OUTSIDE_STRINGS" in
    *"$forbidden"*) fail "forbidden token '$forbidden' found outside a string literal" ;;
  esac
done
if grep -qE 'new[[:space:]]+Date[[:space:]]*\([[:space:]]*\)' <<< "$CODE_OUTSIDE_STRINGS"; then
  fail "forbidden argless 'new Date()' found outside a string literal"
fi

if command -v node >/dev/null 2>&1; then
  SYNTAX_CHECK_FILE=$(mktemp "${TMPDIR:-/tmp}/lbwc-workflow-syntax.XXXXXX.mjs")
  { printf '(async () => {\n'; tail -n +2 "$TARGET"; printf '\n})\n'; } > "$SYNTAX_CHECK_FILE"
  SYNTAX_ERROR=$(node --check --input-type=module - < "$SYNTAX_CHECK_FILE" 2>&1) || {
    rm -f "$SYNTAX_CHECK_FILE"
    fail "rendered workflow script failed the node syntax check: $SYNTAX_ERROR"
  }
  rm -f "$SYNTAX_CHECK_FILE"
else
  printf 'workflow-generator: node not found, falling back to a best-effort structural check (balanced parentheses, braces, and brackets, plus closed string and template literals). This does not catch unbalanced operators, illegal tokens, or other malformed JavaScript that a real parser would reject.\n' >&2
  string_spans_unterminated "$TARGET" && fail "rendered workflow script has an unterminated string or template literal"
  check_balanced_delimiters "$CODE_OUTSIDE_STRINGS" || fail "rendered workflow script has unbalanced parentheses, braces, or brackets"
fi

SCRIPT_DIGEST=$(shasum -a 256 "$TARGET" | awk '{print $1}')
ARGS_JSON=$(jq -Scn 'null')
ARGS_DIGEST=$(printf '%s' "$ARGS_JSON" | shasum -a 256 | awk '{print $1}')

if ! workflow_manifest_register "$CONTROL_ROOT" "$CONTRACT_ID" "$TARGET" "$SCRIPT_DIGEST" "$ARGS_DIGEST" "$ROSTER_JSON"; then
  fail "could not register generated workflow in manifest"
fi

WORKFLOW_COMMITTED=1

printf 'Workflow-call parameters:\n'
printf '  path: %s\n' "$TARGET"
printf '  name: %s\n' "$TASK_ID"
printf '  digest: %s\n' "$SCRIPT_DIGEST"
printf 'WORKFLOW_READY %s\n' "$TASK_ID"
