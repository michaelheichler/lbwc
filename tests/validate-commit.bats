#!/usr/bin/env bats

load test_helper

@test "passes valid conventional commit" {
  INPUT='{"tool_input":{"command":"git commit -m \"feat(core): add new feature\""}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/validate-commit.sh'"
  [ "$status" -eq 0 ]
}

@test "flags invalid commit format" {
  INPUT='{"tool_input":{"command":"git commit -m \"bad commit message\""}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/validate-commit.sh'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "does not match format"
}

@test "passes non-commit commands" {
  INPUT='{"tool_input":{"command":"git status"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/validate-commit.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validates heredoc-style commits" {
  INPUT=$(printf '{"tool_input":{"command":"git commit -m \\"$(cat <<'"'"'EOF'"'"'\\nfeat(test): valid heredoc commit\\n\\nCo-Authored-By: Test\\nEOF\\n)\\""}}'  )
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/validate-commit.sh'"
  [ "$status" -eq 0 ]
}

@test "finds the conventional-commit line past a leading blank line in the heredoc" {
  INPUT=$(printf '{"tool_input":{"command":"git commit -m \\"$(cat <<'"'"'EOF'"'"'\\n\\nfeat(01-02): add thing\\n\\nCo-Authored-By: Test\\nEOF\\n)\\""}}'  )
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/validate-commit.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "finds the conventional-commit line past a non-blank preamble line in the heredoc" {
  INPUT=$(printf '{"tool_input":{"command":"git commit -m \\"$(cat <<'"'"'EOF'"'"'\\nSome preamble comment line\\nfeat(01-02): add thing\\nEOF\\n)\\""}}'  )
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/validate-commit.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "flags a heredoc body where no line matches conventional-commit format" {
  INPUT=$(printf '{"tool_input":{"command":"git commit -m \\"$(cat <<'"'"'EOF'"'"'\\nfixed a bug\\nEOF\\n)\\""}}'  )
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/validate-commit.sh'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "does not match format"
}
