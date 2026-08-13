#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage: check-markdown-format.sh [--root PATH]' \
    'Input: a repository root containing a commands directory.' \
    'Output: whitespace violations or one passing summary. The repository is never modified.' \
    'Exit 0: pass. Exit 1: whitespace violation. Exit 2: invalid invocation or repository setup.' >&2
}

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"

if [ "$#" -gt 0 ]; then
  if [ "$#" -ne 2 ] || [ "$1" != '--root' ]; then
    usage
    exit 2
  fi
  ROOT="$2"
fi

if [ ! -d "$ROOT/commands" ]; then
  printf 'check-markdown-format: commands directory is unavailable: %s\n' "$ROOT/commands" >&2
  exit 2
fi

shopt -s nullglob
command_files=("$ROOT"/commands/*.md)
if [ "${#command_files[@]}" -eq 0 ]; then
  printf 'check-markdown-format: no command Markdown files found: %s\n' "$ROOT/commands" >&2
  exit 2
fi

violation_count=0

for file_path in "${command_files[@]}"; do
  relative_path="${file_path#"$ROOT/"}"
  line_number=0

  while IFS= read -r line || [ -n "$line" ]; do
    line_number=$((line_number + 1))

    case "$line" in
      *$'\t'*)
        printf '%s:%d: literal tab character\n' "$relative_path" "$line_number" >&2
        violation_count=$((violation_count + 1))
        ;;
    esac

    case "$line" in
      *$'\r')
        printf '%s:%d: CRLF line ending\n' "$relative_path" "$line_number" >&2
        violation_count=$((violation_count + 1))
        ;;
    esac

    case "$line" in
      *[[:blank:]])
        printf '%s:%d: trailing whitespace\n' "$relative_path" "$line_number" >&2
        violation_count=$((violation_count + 1))
        ;;
    esac
  done < "$file_path"

  if [ -s "$file_path" ]; then
    last_byte="$(tail -c 1 "$file_path" | od -An -t x1 | tr -d '[:space:]')"
    if [ "$last_byte" != '0a' ]; then
      printf '%s: missing final newline\n' "$relative_path" >&2
      violation_count=$((violation_count + 1))
    fi
  fi
done

if [ "$violation_count" -gt 0 ]; then
  printf 'Markdown format failed: %d violation(s)\n' "$violation_count" >&2
  exit 1
fi

printf 'Markdown format passed: %d command files\n' "${#command_files[@]}"