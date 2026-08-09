#!/usr/bin/env bash
# Dev-time script: vendor the DevIQ corpus markdown into references/deviq-corpus/.
# Copies content/<category>/<slug>.md from the source corpus (skipping _index.md),
# writes references/deviq-corpus/MANIFEST.json, then verifies every vendored
# file's sha256 against that manifest.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE="${DEVIQ_CORPUS_SOURCE:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --source)
      SOURCE="${2:?--source requires a value}"
      shift 2
      ;;
    *)
      echo "deviq-vendor: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "deviq-vendor: jq is required" >&2; exit 1; }

MANIFEST_SRC="$SOURCE/manifest.json"
[ -f "$MANIFEST_SRC" ] || { echo "deviq-vendor: manifest not found at $MANIFEST_SRC" >&2; exit 1; }

DEST="$REPO_ROOT/references/deviq-corpus"
rm -rf "$DEST"
mkdir -p "$DEST"

UPSTREAM_COMMIT=$(jq -r '.upstream_commit' "$MANIFEST_SRC")
[ -n "$UPSTREAM_COMMIT" ] && [ "$UPSTREAM_COMMIT" != "null" ] || {
  echo "deviq-vendor: source manifest has no upstream_commit" >&2
  exit 1
}

# Vendorable entries: content/<category>/<slug>.md, excluding _index.md files.
FILTERED=$(jq -c '
  .files
  | map(select(.[0] | test("^content/[^/]+/[^/]+\\.md$")))
  | map(select(.[0] | endswith("/_index.md") | not))
  | sort_by(.[0])
' "$MANIFEST_SRC")

COUNT=$(jq 'length' <<< "$FILTERED")
[ "$COUNT" -gt 0 ] || { echo "deviq-vendor: no vendorable articles found in manifest" >&2; exit 1; }

while IFS=$'\t' read -r oldpath _hash; do
  newrel="${oldpath#content/}"
  mkdir -p "$DEST/$(dirname "$newrel")"
  cp "$SOURCE/$oldpath" "$DEST/$newrel"
done < <(jq -r '.[] | "\(.[0])\t\(.[1])"' <<< "$FILTERED")

jq -n --arg commit "$UPSTREAM_COMMIT" --argjson files "$(jq '[.[] | [(.[0] | sub("^content/"; "")), .[1]]]' <<< "$FILTERED")" '
  {upstream_repo: "github.com/NimblePros/DevIQ-Hugo", upstream_commit: $commit, files: $files}
' > "$DEST/MANIFEST.json"

echo "deviq-vendor: vendored $COUNT articles to $DEST" >&2

# Verify: recompute sha256 of every vendored file and diff against the manifest.
FAILED=0
while IFS=$'\t' read -r relpath expected; do
  if [ ! -f "$DEST/$relpath" ]; then
    echo "deviq-vendor: missing vendored file: $relpath" >&2
    FAILED=1
    continue
  fi
  actual=$(shasum -a 256 "$DEST/$relpath" | awk '{print $1}')
  if [ "$actual" != "$expected" ]; then
    echo "deviq-vendor: sha256 mismatch for $relpath (expected $expected, got $actual)" >&2
    FAILED=1
  fi
done < <(jq -r '.files[] | "\(.[0])\t\(.[1])"' "$DEST/MANIFEST.json")

if [ "$FAILED" -ne 0 ]; then
  echo "deviq-vendor: verification failed" >&2
  exit 1
fi

echo "deviq-vendor: verified $(jq '.files | length' "$DEST/MANIFEST.json") files" >&2
