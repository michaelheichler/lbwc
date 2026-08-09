#!/usr/bin/env python3
"""Build references/deviq-corpus/index.json from the vendored DevIQ articles."""
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
CORPUS_DIR = REPO_ROOT / "references" / "deviq-corpus"


def strip_quotes(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def frontmatter_span(lines):
    if not lines or lines[0].strip() != "---":
        return None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return lines[1:i]
    return None


def parse_inline_aliases(rest):
    inner = rest.strip("[]")
    return [strip_quotes(x) for x in inner.split(",") if x.strip()]


def parse_block_aliases(fm_lines, start):
    items = []
    j = start
    while j < len(fm_lines) and fm_lines[j].strip().startswith("-"):
        items.append(strip_quotes(fm_lines[j].strip()[1:]))
        j += 1
    return items, j


def apply_key(result, key, rest, fm_lines, index):
    if key == "title":
        result["title"] = strip_quotes(rest)
        return index
    if key == "description":
        result["description"] = strip_quotes(rest)
        return index
    if key == "aliases":
        if rest.startswith("["):
            result["aliases"] = parse_inline_aliases(rest)
            return index
        result["aliases"], next_index = parse_block_aliases(fm_lines, index + 1)
        return next_index - 1
    return index


def parse_frontmatter(text):
    result = {"title": "", "description": "", "aliases": []}
    fm_lines = frontmatter_span(text.splitlines())
    if fm_lines is None:
        return result

    i = 0
    while i < len(fm_lines):
        line = fm_lines[i]
        if line.strip() and not line.startswith((" ", "\t")) and ":" in line:
            key, _, rest = line.partition(":")
            i = apply_key(result, key.strip(), rest.strip(), fm_lines, i)
        i += 1
    return result


def build_index():
    entries = []
    for md_path in sorted(CORPUS_DIR.glob("*/*.md")):
        category = md_path.parent.name
        slug = md_path.stem
        text = md_path.read_text(encoding="utf-8", errors="ignore")
        frontmatter = parse_frontmatter(text)
        entries.append({
            "id": f"{category}/{slug}",
            "category": category,
            "title": frontmatter["title"],
            "description": frontmatter["description"],
            "aliases": frontmatter["aliases"],
        })
    entries.sort(key=lambda e: e["id"])
    return entries


def main():
    if not CORPUS_DIR.is_dir():
        print(f"deviq-index: corpus dir not found: {CORPUS_DIR}", file=sys.stderr)
        return 1
    entries = build_index()
    out_path = CORPUS_DIR / "index.json"
    out_path.write_text(json.dumps(entries, indent=2) + "\n", encoding="utf-8")
    print(f"deviq-index: wrote {len(entries)} entries to {out_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
