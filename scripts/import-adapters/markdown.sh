#!/usr/bin/env bash

import_adapter_markdown_read_heading() {
  local path="$1"
  awk '
    /^[[:space:]]*#[[:space:]]+/ {
      sub(/^[[:space:]]*#[[:space:]]+/, "")
      sub(/[[:space:]]+#+[[:space:]]*$/, "")
      print
      exit
    }
  ' "$path"
}

import_adapter_markdown_normalize() {
  local source="$1" output="$2" plans='[]' provenance='[]' warnings='["unverified generic Markdown adapter"]' skipped='[]' selected=0 total_selected_bytes=0 path relative size title plan_json
  local max_files=64 max_file_bytes=1048576 max_total_bytes=8388608
  local total_markdown=0 oversized=0 total_capped=0

  [ -d "$source" ] || import_fail "Markdown source is not a directory: $source"
  import_source_metadata "$source"

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    relative=${path#"$source"/}
    size=$(import_file_size "$path") || import_fail "could not read Markdown file size: $path"
    total_markdown=$((total_markdown + 1))
    if [ "$size" -gt "$max_file_bytes" ]; then
      oversized=$((oversized + 1))
      skipped=$(jq -c --arg path "$relative" --arg reason file-size-cap '. + [{path:$path,reason:$reason}]' <<< "$skipped")
      continue
    fi
    if [ "$selected" -ge "$max_files" ]; then
      skipped=$(jq -c --arg path "$relative" --arg reason file-count-cap '. + [{path:$path,reason:$reason}]' <<< "$skipped")
      continue
    fi
    if [ $((total_selected_bytes + size)) -gt "$max_total_bytes" ]; then
      total_capped=$((total_capped + 1))
      skipped=$(jq -c --arg path "$relative" --arg reason total-byte-cap '. + [{path:$path,reason:$reason}]' <<< "$skipped")
      continue
    fi
    title=$(import_adapter_markdown_read_heading "$path")
    [ -n "$title" ] || title=null
    plan_json=$(jq -n --arg path "$relative" --arg title "$title" \
      '{source_path:$path,title:(if $title == "null" then null else $title end),status:null,depends_on:null}')
    plans=$(jq -c --argjson plan "$plan_json" '. + [$plan]' <<< "$plans")
    if [ "$title" != null ]; then
      provenance=$(jq -c --arg field "plans[$selected].title" --arg path "$relative" --arg value "$title" \
        '. + [{field:$field,source_path:$path,extraction_method:"markdown-heading",value:$value}]' <<< "$provenance")
    fi
    selected=$((selected + 1))
    total_selected_bytes=$((total_selected_bytes + size))
  done < <(find "$source" -type f -name '*.md' -print 2>/dev/null | LC_ALL=C sort)

  [ "$oversized" -eq 0 ] || warnings=$(jq -c --arg message "file-size-cap: skipped $oversized Markdown file(s) larger than $max_file_bytes bytes" '. + [$message]' <<< "$warnings")
  if [ "$total_markdown" -gt "$max_files" ]; then
    warnings=$(jq -c --arg message "file-count-cap: selected at most $max_files Markdown files" '. + [$message]' <<< "$warnings")
  fi
  [ "$total_capped" -eq 0 ] || warnings=$(jq -c --arg message "total-byte-cap: skipped $total_capped Markdown file(s) after selecting $max_total_bytes bytes" '. + [$message]' <<< "$warnings")

  jq -n \
    --arg system markdown --arg trust unverified-markdown --arg root "$(basename "$source")" --arg digest "$SOURCE_DIGEST" \
    --argjson plans "$plans" --argjson provenance "$provenance" --argjson warnings "$warnings" --argjson skipped "$skipped" \
    --argjson file_count "$SOURCE_FILE_COUNT" --argjson total_bytes "$SOURCE_TOTAL_BYTES" \
    --argjson max_files "$max_files" --argjson max_file_bytes "$max_file_bytes" --argjson max_total_bytes "$max_total_bytes" \
    '{schema_version:1,source:{system:$system,trust_tier:$trust,root:$root,digest:$digest,file_count:$file_count,total_bytes:$total_bytes,limits:{max_files:$max_files,max_file_bytes:$max_file_bytes,max_total_bytes:$max_total_bytes},skipped_files:$skipped},project:{name:null,description:null},requirements:[],milestones:[],phases:[],plans:$plans,decisions:[],warnings:$warnings,conflicts:[],provenance:$provenance}' > "$output"
}
