#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
STATE_DIR="${LBWC_RTK_DIR:-$ROOT/.lbwc-planning/tools/rtk}"
RTK_BINARY="${LBWC_RTK_BINARY:-$STATE_DIR/rtk}"
RECEIPT_FILE="${LBWC_RTK_RECEIPT:-$STATE_DIR/rtk-install.json}"
BACKUP_DIR="${LBWC_RTK_BACKUPS:-$STATE_DIR/backups}"
RTK_REPO_API="${RTK_REPO_API:-https://api.github.com/repos/rtk-ai/rtk/releases/latest}"
RTK_CURL_MAX_TIME="${RTK_CURL_MAX_TIME:-15}"
CLAUDE_BINARY="${CLAUDE_BINARY:-claude}"
TEMP_DIR=""
STAGED_BINARY=""

cleanup() {
  [ -z "$TEMP_DIR" ] || rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: rtk-manager.sh <command> [options]

Commands:
  status [--json] [--check-updates]
  install --yes [--dry-run]
  update --yes [--dry-run]
  verify [--json]
  uninstall --yes [--dry-run]

Installs are project-local. This script never changes Claude Code settings or
global RTK configuration. Mutating commands require --yes. Use --dry-run to
validate the planned release without changing the project.
EOF
}

die() {
  printf 'rtk-manager: %s\n' "$*" >&2
  exit 2
}

path_is_within() {
  local path="$1" parent="$2"
  case "$path" in
    "$parent"/*) ;;
    *) return 1 ;;
  esac
  case "$path" in
    ../*|*/../*|*/..) return 1 ;;
  esac
}

validate_configured_paths() {
  path_is_within "$STATE_DIR" "$ROOT" || die 'RTK state must stay inside this project'
  path_is_within "$RTK_BINARY" "$STATE_DIR" || die 'RTK binary must stay inside the project-local state directory'
  path_is_within "$RECEIPT_FILE" "$STATE_DIR" || die 'RTK receipt must stay inside the project-local state directory'
  path_is_within "$BACKUP_DIR" "$STATE_DIR" || die 'RTK backups must stay inside the project-local state directory'
}

reject_symlink_components() {
  local path="$1" relative component current="$ROOT" IFS=/
  relative="${path#"$ROOT"/}"
  read -r -a components <<< "$relative"
  for component in "${components[@]}"; do
    current="$current/$component"
    [ ! -e "$current" ] || [ ! -L "$current" ] || die 'RTK paths may not traverse symbolic links'
  done
}

assert_safe_state() {
  local physical_state
  validate_configured_paths
  reject_symlink_components "$STATE_DIR"
  reject_symlink_components "$RTK_BINARY"
  reject_symlink_components "$RECEIPT_FILE"
  reject_symlink_components "$BACKUP_DIR"
  if [ -e "$STATE_DIR" ]; then
    [ -d "$STATE_DIR" ] || die 'RTK state path is not a directory'
    physical_state="$(cd "$STATE_DIR" && pwd -P)" || die 'RTK state directory cannot be resolved'
    path_is_within "$physical_state" "$ROOT" || die 'RTK state resolves outside this project'
  fi
  [ ! -L "$RTK_BINARY" ] || die 'RTK binary may not be a symbolic link'
  [ ! -L "$RECEIPT_FILE" ] || die 'RTK receipt may not be a symbolic link'
  [ ! -L "$BACKUP_DIR" ] || die 'RTK backup directory may not be a symbolic link'
}

ensure_state_dir() {
  assert_safe_state
  mkdir -p "$STATE_DIR" || die 'could not create project-local RTK state directory'
  assert_safe_state
}

sha256_value() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    die 'sha256 utility is required'
  fi
}

os_arch_target() {
  case "$(uname -s):$(uname -m)" in
    Darwin:arm64|Darwin:aarch64) printf '%s\n' 'aarch64-apple-darwin' ;;
    Darwin:x86_64) printf '%s\n' 'x86_64-apple-darwin' ;;
    Linux:arm64|Linux:aarch64) printf '%s\n' 'aarch64-unknown-linux-gnu' ;;
    Linux:x86_64) printf '%s\n' 'x86_64-unknown-linux-musl' ;;
    *) die "unsupported platform $(uname -s)/$(uname -m)" ;;
  esac
}

require_jq() {
  command -v jq >/dev/null 2>&1 || die 'jq is required'
}

fetch_release() {
  local release_json tag target asset_name asset_url checksums_url
  require_jq
  release_json="$(curl -fsSL --max-time "$RTK_CURL_MAX_TIME" "$RTK_REPO_API")" || die 'could not fetch RTK release metadata'
  tag="$(printf '%s' "$release_json" | jq -r '.tag_name // empty')"
  target="$(os_arch_target)"
  asset_name="$(printf '%s' "$release_json" | jq -r --arg target "$target" '[.assets[]? | select((.name | contains($target)) and (.name | endswith(".tar.gz")))][0].name // empty')"
  asset_url="$(printf '%s' "$release_json" | jq -r --arg name "$asset_name" '[.assets[]? | select(.name == $name)][0].browser_download_url // empty')"
  checksums_url="$(printf '%s' "$release_json" | jq -r '[.assets[]? | select(.name == "checksums.txt")][0].browser_download_url // empty')"
  [ -n "$tag" ] || die 'release metadata has no tag'
  [ -n "$asset_name" ] && [ -n "$asset_url" ] || die "release metadata has no archive for $target"
  [ -n "$checksums_url" ] || die 'release metadata has no checksums.txt asset'
  jq -cn --arg tag "$tag" --arg target "$target" --arg asset_name "$asset_name" --arg asset_url "$asset_url" --arg checksums_url "$checksums_url" '{tag:$tag,target:$target,asset_name:$asset_name,asset_url:$asset_url,checksums_url:$checksums_url}'
}

archive_paths_are_safe() {
  tar -tzf "$1" | awk '
    /^\// || /(^|\/)\.\.([\/]|$)/ { unsafe=1; exit }
    { seen=1 }
    END { exit (seen && !unsafe) ? 0 : 1 }
  '
}

stage_release() {
  local metadata="$1" archive checksums asset_name asset_url checksums_url expected actual binary
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lbwc-rtk.XXXXXX")"
  archive="$TEMP_DIR/release.tar.gz"
  checksums="$TEMP_DIR/checksums.txt"
  asset_name="$(printf '%s' "$metadata" | jq -r '.asset_name')"
  asset_url="$(printf '%s' "$metadata" | jq -r '.asset_url')"
  checksums_url="$(printf '%s' "$metadata" | jq -r '.checksums_url')"
  curl -fsSL --max-time "$RTK_CURL_MAX_TIME" "$asset_url" -o "$archive" || die 'could not download RTK archive'
  curl -fsSL --max-time "$RTK_CURL_MAX_TIME" "$checksums_url" -o "$checksums" || die 'could not download RTK checksums'
  expected="$(awk -v asset="$asset_name" '$2 == asset || $2 == "*" asset { print $1; exit }' "$checksums")"
  [[ "$expected" =~ ^[A-Fa-f0-9]{64}$ ]] || die "checksums.txt has no sha256 for $asset_name"
  actual="$(sha256_value "$archive")"
  [ "$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')" ] || die "checksum mismatch for $asset_name"
  archive_paths_are_safe "$archive" || die 'RTK archive has unsafe or empty paths'
  mkdir "$TEMP_DIR/extract"
  tar -xzf "$archive" -C "$TEMP_DIR/extract"
  binary="$(find "$TEMP_DIR/extract" -type f -name rtk -perm -u+x -print -quit)"
  [ -n "$binary" ] || die 'RTK archive has no executable rtk binary'
  STAGED_BINARY="$binary"
}

backup_existing() {
  local backup
  [ ! -e "$RTK_BINARY" ] && [ ! -e "$RECEIPT_FILE" ] && return 0
  mkdir -p "$BACKUP_DIR" || return 1
  backup="$(mktemp -d "$BACKUP_DIR/rtk-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")" || return 1
  [ ! -e "$RTK_BINARY" ] || cp -p "$RTK_BINARY" "$backup/rtk" || return 1
  [ ! -e "$RECEIPT_FILE" ] || cp -p "$RECEIPT_FILE" "$backup/rtk-install.json" || return 1
  printf '%s\n' "$backup"
}

rollback_install() {
  local backup="$1" had_binary="$2" had_receipt="$3" current_hash backup_hash
  if [ "$had_binary" = true ]; then
    [ -n "$backup" ] && [ -f "$backup/rtk" ] || return 1
    cp -p "$backup/rtk" "$RTK_BINARY" || return 1
    current_hash="$(sha256_value "$RTK_BINARY")" || return 1
    backup_hash="$(sha256_value "$backup/rtk")" || return 1
    [ "$current_hash" = "$backup_hash" ] || return 1
  else
    rm -f "$RTK_BINARY" || return 1
  fi
  if [ "$had_receipt" = true ]; then
    [ -n "$backup" ] && [ -f "$backup/rtk-install.json" ] || return 1
    cp -p "$backup/rtk-install.json" "$RECEIPT_FILE" || return 1
    cmp -s "$RECEIPT_FILE" "$backup/rtk-install.json" || return 1
  else
    rm -f "$RECEIPT_FILE" || return 1
  fi
}

fail_after_replacement() {
  local message="$1" backup="$2" had_binary="$3" had_receipt="$4"
  rollback_install "$backup" "$had_binary" "$had_receipt" || die "$message; rollback failed"
  die "$message"
}

smoke() {
  local claude_state='not-found'
  [ -x "$RTK_BINARY" ] || return 1
  "$RTK_BINARY" --version >/dev/null 2>&1 || return 1
  "$RTK_BINARY" proxy printf '%s' lbwc-rtk-smoke >/dev/null 2>&1 || return 1
  if command -v "$CLAUDE_BINARY" >/dev/null 2>&1; then
    "$CLAUDE_BINARY" --version >/dev/null 2>&1 || return 1
    claude_state='available'
  fi
  printf '%s\n' "$claude_state"
}

receipt_json() {
  local metadata="$1" binary_sha256="$2" smoke_state="$3"
  jq -cn \
    --arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg binary "$RTK_BINARY" \
    --arg binary_sha256 "$binary_sha256" \
    --arg claude_smoke "$smoke_state" \
    --argjson release "$metadata" \
    '{installed_at:$installed_at,binary:$binary,binary_sha256:$binary_sha256,claude_code_smoke:$claude_smoke,release:$release}'
}

install_release() {
  local action="$1" dry_run="$2" metadata staged backup smoke_state receipt_tmp binary_hash had_binary=false had_receipt=false
  if [ "$action" = update ] && [ ! -x "$RTK_BINARY" ]; then
    die 'update requires an existing project-local RTK install'
  fi
  metadata="$(fetch_release)"
  stage_release "$metadata"
  staged="$STAGED_BINARY"
  if [ "$dry_run" = true ]; then
    printf 'dry-run: %s RTK %s for %s at %s\n' "$action" "$(printf '%s' "$metadata" | jq -r '.tag')" "$(printf '%s' "$metadata" | jq -r '.target')" "$RTK_BINARY"
    return 0
  fi
  ensure_state_dir
  [ ! -e "$RTK_BINARY" ] || had_binary=true
  [ ! -e "$RECEIPT_FILE" ] || had_receipt=true
  if ! backup="$(backup_existing)"; then
    die 'could not create a backup before replacing RTK'
  fi
  if ! install -m 755 "$staged" "$RTK_BINARY"; then
    fail_after_replacement 'could not replace project-local RTK binary' "$backup" "$had_binary" "$had_receipt"
  fi
  if ! smoke_state="$(smoke)"; then
    fail_after_replacement 'installed RTK failed the local Claude Code compatibility smoke check' "$backup" "$had_binary" "$had_receipt"
  fi
  if ! binary_hash="$(sha256_value "$RTK_BINARY")"; then
    fail_after_replacement 'could not hash installed RTK binary' "$backup" "$had_binary" "$had_receipt"
  fi
  if ! receipt_tmp="$(mktemp "$STATE_DIR/.rtk-receipt.XXXXXX")"; then
    fail_after_replacement 'could not create RTK receipt' "$backup" "$had_binary" "$had_receipt"
  fi
  if ! receipt_json "$metadata" "$binary_hash" "$smoke_state" > "$receipt_tmp" || ! chmod 600 "$receipt_tmp" || ! mv "$receipt_tmp" "$RECEIPT_FILE"; then
    rm -f "${receipt_tmp:-}"
    fail_after_replacement 'could not write RTK receipt' "$backup" "$had_binary" "$had_receipt"
  fi
  printf '%s: installed %s at %s\n' "$action" "$(printf '%s' "$metadata" | jq -r '.tag')" "$RTK_BINARY"
  [ -z "$backup" ] || printf 'backup: %s\n' "$backup"
}

verify_install() {
  local json="$1" current_hash receipt_hash smoke_state version
  assert_safe_state
  if [ ! -x "$RTK_BINARY" ] || [ ! -f "$RECEIPT_FILE" ]; then
    if [ "$json" = true ]; then
      printf '%s\n' '{"verified":false,"reason":"missing_install_or_receipt"}'
    else
      printf 'verify: project-local RTK install or receipt is missing\n' >&2
    fi
    return 1
  fi
  require_jq
  jq -e 'type == "object" and (.binary_sha256 | type == "string") and (.release | type == "object")' "$RECEIPT_FILE" >/dev/null || die 'receipt is malformed'
  current_hash="$(sha256_value "$RTK_BINARY")"
  receipt_hash="$(jq -r '.binary_sha256' "$RECEIPT_FILE")"
  [ "$current_hash" = "$receipt_hash" ] || die 'installed binary hash differs from receipt'
  smoke_state="$(smoke)" || die 'RTK failed the local Claude Code compatibility smoke check'
  version="$("$RTK_BINARY" --version 2>/dev/null || true)"
  if [ "$json" = true ]; then
    jq -cn --arg version "$version" --arg claude_smoke "$smoke_state" '{verified:true,version:$version,claude_code_smoke:$claude_smoke}'
  else
    printf 'verify: %s (Claude Code smoke: %s)\n' "$version" "$smoke_state"
  fi
}

status() {
  local json="$1" check_updates="$2" installed=false receipt=false version='' latest=''
  assert_safe_state
  [ ! -x "$RTK_BINARY" ] || installed=true
  [ ! -f "$RECEIPT_FILE" ] || receipt=true
  [ "$installed" = false ] || version="$("$RTK_BINARY" --version 2>/dev/null || true)"
  if [ "$check_updates" = true ]; then
    latest="$(fetch_release | jq -r '.tag')"
  fi
  if [ "$json" = true ]; then
    jq -cn --arg binary "$RTK_BINARY" --arg version "$version" --arg latest "$latest" --argjson installed "$installed" --argjson receipt "$receipt" '{binary:$binary,installed:$installed,receipt_present:$receipt,version:$version,latest:$latest}'
  else
    printf 'project binary: %s\ninstalled: %s\nreceipt: %s\nversion: %s\n' "$RTK_BINARY" "$installed" "$receipt" "${version:-none}"
    [ -z "$latest" ] || printf 'latest: %s\n' "$latest"
  fi
}

uninstall_release() {
  local dry_run="$1" backup
  assert_safe_state
  [ -e "$RTK_BINARY" ] || [ -e "$RECEIPT_FILE" ] || die 'no project-local RTK install exists'
  if [ "$dry_run" = true ]; then
    printf 'dry-run: remove %s and %s after creating a backup\n' "$RTK_BINARY" "$RECEIPT_FILE"
    return 0
  fi
  if ! backup="$(backup_existing)"; then
    die 'could not create a backup before uninstalling RTK'
  fi
  rm -f "$RTK_BINARY" "$RECEIPT_FILE"
  printf 'uninstall: removed project-local RTK install\nbackup: %s\n' "$backup"
}

command_name="${1:-}"
[ -n "$command_name" ] || { usage >&2; exit 2; }
shift || true
json=false
check_updates=false
dry_run=false
yes=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json) json=true ;;
    --check-updates) check_updates=true ;;
    --dry-run) dry_run=true ;;
    --yes) yes=true ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown option $1" ;;
  esac
  shift
done

validate_configured_paths

case "$command_name" in
  status) status "$json" "$check_updates" ;;
  verify) verify_install "$json" ;;
  install|update)
    [ "$yes" = true ] || die "$command_name requires --yes"
    install_release "$command_name" "$dry_run"
    ;;
  uninstall)
    [ "$yes" = true ] || die 'uninstall requires --yes'
    uninstall_release "$dry_run"
    ;;
  --help|-h|help) usage ;;
  *) die "unknown command $command_name" ;;
esac
