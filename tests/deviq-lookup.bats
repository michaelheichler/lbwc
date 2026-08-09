#!/usr/bin/env bats

load test_helper

@test "search: query matches an id, title, and description hit" {
  run env CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$SCRIPTS_DIR/deviq-lookup.sh" blob

  [ "$status" -eq 0 ]
  [[ "$output" == *"antipatterns/blob | The Blob |"* ]]
}

@test "search: results are capped at 8 lines" {
  run env CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$SCRIPTS_DIR/deviq-lookup.sh" the

  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 8 ]
}

@test "--show prints the vendored article body" {
  run env CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$SCRIPTS_DIR/deviq-lookup.sh" --show antipatterns/blob

  [ "$status" -eq 0 ]
  [[ "$output" == *"title: The Blob"* ]]
}

@test "--show on a missing id reports the error and still exits 0" {
  run env CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$SCRIPTS_DIR/deviq-lookup.sh" --show nope/nope

  [ "$status" -eq 0 ]
  [[ "$output" == *"no article found for id: nope/nope"* ]]
}

@test "--category filters search results to that category" {
  run env CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$SCRIPTS_DIR/deviq-lookup.sh" --category antipatterns blob

  [ "$status" -eq 0 ]
  [[ "$output" == *"antipatterns/blob"* ]]
  [[ "$output" != *"design-patterns/"* ]]
}

@test "--category excludes matches from other categories" {
  run env CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$SCRIPTS_DIR/deviq-lookup.sh" --category design-patterns blob

  [ "$status" -eq 0 ]
  [ "$output" = "no match" ]
}

@test "a query with no hits prints no match and exits 0" {
  run env CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$SCRIPTS_DIR/deviq-lookup.sh" zzzzzznotarealtermxyz

  [ "$status" -eq 0 ]
  [ "$output" = "no match" ]
}

@test "garbage flags and arguments never exit non-zero" {
  run env CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$SCRIPTS_DIR/deviq-lookup.sh" --bogus-flag "; rm -rf /" "$(printf '\xff\xfe')"

  [ "$status" -eq 0 ]
}

@test "--grep finds an article by body text and maps it back through the index" {
  run env CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$SCRIPTS_DIR/deviq-lookup.sh" --grep "God Object"

  [ "$status" -eq 0 ]
  [[ "$output" == *"antipatterns/blob | The Blob |"* ]]
}

@test "vendored corpus matches MANIFEST.json sha256 hashes" {
  local manifest="$PROJECT_ROOT/references/deviq-corpus/MANIFEST.json"
  local corpus_dir="$PROJECT_ROOT/references/deviq-corpus"

  [ -f "$manifest" ]

  run bash -c "
    jq -r '.files[] | \"\(.[0])\t\(.[1])\"' '$manifest' | while IFS=\$'\t' read -r relpath expected; do
      actual=\$(shasum -a 256 \"$corpus_dir/\$relpath\" | awk '{print \$1}')
      [ \"\$actual\" = \"\$expected\" ] || { echo \"mismatch: \$relpath\"; exit 1; }
    done
  "

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
