#!/usr/bin/env bash
set -euo pipefail


link_path="${1:-}"
target_dir="${2:-}"

if [ -z "$link_path" ] || [ -z "$target_dir" ]; then
  echo "Usage: ensure-plugin-root-link.sh <link-path> <target-dir>" >&2
  exit 1
fi

case "$(basename "$link_path")" in
  .lbwc-plugin-root-link-*) ;;
  *)
    echo "Error: unexpected link path basename: $link_path" >&2
    exit 1
    ;;
esac

if [ ! -d "$target_dir" ]; then
  echo "Error: target directory does not exist: $target_dir" >&2
  exit 1
fi

cleanup_existing() {
  if [ -L "$link_path" ] || [ -f "$link_path" ]; then
    rm -f "$link_path"
  elif [ -d "$link_path" ] || [ -e "$link_path" ]; then
    rm -rf "$link_path"
  fi
}

current_target="$(readlink "$link_path" 2>/dev/null || true)"
if [ -L "$link_path" ] && [ "$current_target" = "$target_dir" ]; then
  exit 0
fi

cleanup_existing

if ln -s "$target_dir" "$link_path" 2>/dev/null; then
  exit 0
fi

current_target="$(readlink "$link_path" 2>/dev/null || true)"
if [ -L "$link_path" ] && [ "$current_target" = "$target_dir" ]; then
  exit 0
fi

cleanup_existing
ln -s "$target_dir" "$link_path"
