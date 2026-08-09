#!/usr/bin/env bats

load test_helper

@test "role templates do not require agents to self-report file scope" {
  run rg -n -i 'name every file you touched|work inside the scope your brief names|files you (will|will not) touch' \
    "$PROJECT_ROOT/templates/agent-roles"

  [ "$status" -eq 1 ]
}

@test "spawn protocol requires a manifest-backed task-derived write capability" {
  run rg -n 'manifest-backed task-derived write capability' \
    "$PROJECT_ROOT/references/agent-spawn-protocol.md"

  [ "$status" -eq 0 ]
}

@test "spawn protocol routes hook repairs through an exact enforced allowance" {
  run rg -n 'hook repair.*exact path.*allowance' \
    "$PROJECT_ROOT/references/agent-spawn-protocol.md"

  [ "$status" -eq 0 ]
}

@test "role templates route missing role requests to the sole main-session orchestrator" {
  local template
  local role_templates=(
    coding-dijkstra.md.tpl
    coding-dijkstra-critic.md.tpl
    lead-critic.md.tpl
    python-critic.md.tpl
    python-engineer.md.tpl
    test-dev.md.tpl
    ux-oracle.md.tpl
    web-code-critic.md.tpl
    web-engineer.md.tpl
  )

  for template in "${role_templates[@]}"; do
    run rg -n -F 'sole main-session orchestrator' \
      "$PROJECT_ROOT/templates/agent-roles/$template"

    [ "$status" -eq 0 ]
  done

  run rg -n -F 'let the lead spawn it' "$PROJECT_ROOT/templates/agent-roles"

  [ "$status" -eq 1 ]
}

@test "worker templates do not delegate exploratory work to an Explore subagent" {
  run rg -n -i 'delegate .*`Explore` subagent' \
    "$PROJECT_ROOT/templates/agent-roles/python-engineer.md.tpl" \
    "$PROJECT_ROOT/templates/agent-roles/web-engineer.md.tpl"

  [ "$status" -eq 1 ]
}

@test "planning-only lead does not direct spawned teammates" {
  run rg -n -i 'directly delegates task execution to spawned' \
    "$PROJECT_ROOT/templates/agent-roles/lead.md.tpl"

  [ "$status" -eq 1 ]
}

@test "QA returns structured evidence while the main session persists VERIFICATION.md" {
  run rg -n -F 'Return structured `qa_verdict` evidence only' \
    "$PROJECT_ROOT/templates/agent-roles/qa.md.tpl"

  [ "$status" -eq 0 ]

  run rg -n -e 'bash .*write-verification|write-verification.*bash' \
    "$PROJECT_ROOT/templates/agent-roles/qa.md.tpl"

  [ "$status" -eq 1 ]

  run rg -n -F 'sole main-session orchestrator persists VERIFICATION.md' \
    "$PROJECT_ROOT/commands/qa.md"

  [ "$status" -eq 0 ]

  run rg -n -F 'scripts/write-verification.sh' "$PROJECT_ROOT/commands/qa.md"

  [ "$status" -eq 0 ]

  run rg -n -i 'qa writes .*.VERIFICATION' "$PROJECT_ROOT/commands/qa.md"

  [ "$status" -eq 1 ]
}
