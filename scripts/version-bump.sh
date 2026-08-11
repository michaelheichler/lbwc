#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VERSION_FILE="$ROOT/VERSION"
CHANGELOG_FILE="$ROOT/CHANGELOG.md"
PLUGIN_FILE="$ROOT/.claude-plugin/plugin.json"
MARKETPLACE_FILE="$ROOT/.claude-plugin/marketplace.json"

usage() {
  cat <<'EOF'
Usage: version-bump.sh --verify
       version-bump.sh --set X.Y.Z --yes [--dry-run]

VERSION is the release source of truth. A requested version must already have
the newest CHANGELOG.md release heading before metadata can change.
EOF
}

die() {
  printf 'version-bump: %s\n' "$*" >&2
  exit 2
}

valid_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]
}

version_value() {
  [ -f "$VERSION_FILE" ] || die 'VERSION is missing'
  tr -d '[:space:]' < "$VERSION_FILE"
}

changelog_version() {
  awk '/^## \[/{ value=$2; gsub(/^\[/, "", value); gsub(/\]$/, "", value); print value; exit }' "$CHANGELOG_FILE"
}

require_changelog_entry() {
  local version="$1"
  [ -f "$CHANGELOG_FILE" ] || die 'CHANGELOG.md is missing'
  grep -Fqx "## [$version] - $(date -u +%Y-%m-%d)" "$CHANGELOG_FILE" || {
    grep -Fq "## [$version]" "$CHANGELOG_FILE" || die "CHANGELOG.md has no entry for $version"
  }
  [ "$(changelog_version)" = "$version" ] || die "CHANGELOG.md newest release is not $version"
}

verify() {
  local version plugin_version marketplace_version marketplace_plugin_version
  command -v jq >/dev/null 2>&1 || die 'jq is required'
  version="$(version_value)"
  valid_version "$version" || die "VERSION is not valid semver: $version"
  [ -f "$PLUGIN_FILE" ] || die '.claude-plugin/plugin.json is missing'
  jq empty "$PLUGIN_FILE" >/dev/null || die '.claude-plugin/plugin.json is invalid JSON'
  plugin_version="$(jq -r '.version // empty' "$PLUGIN_FILE")"
  [ "$plugin_version" = "$version" ] || die "plugin version $plugin_version does not match VERSION $version"
  [ -f "$MARKETPLACE_FILE" ] || die '.claude-plugin/marketplace.json is missing'
  jq empty "$MARKETPLACE_FILE" >/dev/null || die '.claude-plugin/marketplace.json is invalid JSON'
  marketplace_version="$(jq -r '.version // empty' "$MARKETPLACE_FILE")"
  [ "$marketplace_version" = "$version" ] || die "marketplace version $marketplace_version does not match VERSION $version"
  marketplace_plugin_version="$(jq -r '[.plugins[] | select(.name == "lbwc") | .version] | if length == 1 then .[0] else empty end' "$MARKETPLACE_FILE")"
  [ "$marketplace_plugin_version" = "$version" ] || die "marketplace LBWC plugin version $marketplace_plugin_version does not match VERSION $version"
  require_changelog_entry "$version"
  printf 'version verify: %s is synchronized with plugin metadata and CHANGELOG.md\n' "$version"
}

set_version() {
  local version="$1" dry_run="$2" version_tmp plugin_tmp marketplace_tmp
  command -v jq >/dev/null 2>&1 || die 'jq is required'
  valid_version "$version" || die "invalid semver: $version"
  require_changelog_entry "$version"
  if [ "$dry_run" = true ]; then
    printf 'dry-run: write %s to VERSION, plugin.json, and marketplace.json\n' "$version"
    return 0
  fi
  version_tmp="$(mktemp "$ROOT/.VERSION.XXXXXX")"
  plugin_tmp="$(mktemp "$ROOT/.plugin.json.XXXXXX")"
  marketplace_tmp="$(mktemp "$ROOT/.marketplace.json.XXXXXX")"
  printf '%s\n' "$version" > "$version_tmp"
  jq --arg version "$version" '.version = $version' "$PLUGIN_FILE" > "$plugin_tmp"
  jq --arg version "$version" '
    .version = $version
    | .plugins |= map(if .name == "lbwc" then .version = $version else . end)
  ' "$MARKETPLACE_FILE" > "$marketplace_tmp"
  mv "$version_tmp" "$VERSION_FILE"
  mv "$plugin_tmp" "$PLUGIN_FILE"
  mv "$marketplace_tmp" "$MARKETPLACE_FILE"
  printf 'version set: %s\n' "$version"
}

mode="${1:-}"
shift || true
yes=false
dry_run=false
version=''
if [ "$mode" = --set ]; then
  version="${1:-}"
  [ -n "$version" ] || die '--set requires a version'
  shift
fi
while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes) yes=true ;;
    --dry-run) dry_run=true ;;
    *) die "unknown option $1" ;;
  esac
  shift
done

case "$mode" in
  --verify) verify ;;
  --set)
    [ "$yes" = true ] || die 'setting a version requires --yes'
    set_version "$version" "$dry_run"
    ;;
  --help|-h|help|'') usage; [ -n "$mode" ] || exit 2 ;;
  *)
    if [[ "$mode" == --set=* ]]; then
      version="${mode#--set=}"
    else
      die "unknown mode $mode"
    fi
    [ "$yes" = true ] || die 'setting a version requires --yes'
    set_version "$version" "$dry_run"
    ;;
esac
