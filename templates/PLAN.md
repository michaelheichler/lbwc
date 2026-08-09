---
phase: {NN} # Bare integer. No quotes.
plan: {plan-number}
title: {plan-title}
type: execute
wave: {wave-number}

depends_on: [{deps}] # Ids of plans in this phase that must land first.
cross_phase_deps: [{phase: {NN}, plan: "{NN-MM}", artifact: "{path}", reason: "{why}"}] # Deps on earlier phases only.

autonomous: {true|false}
effort_override: {thorough|balanced|fast|turbo}

strategy_rationale: "" # One line. Why this plan's delivery strategy fits the work.
validation:
  riskiest_assumption: "" # Fill for new-product or uncertain-market phases. Leave empty otherwise.
  mvp_slice: ""
  metric: ""
  decision_rule: ""

skills_used: [{skill}]
files_modified: [{path}]
files_touched: [{path}] # Repo-relative paths. Example: [scripts/foo.sh, tests/foo.bats]
forbidden_commands: []

must_haves:
  truths: ["{invariant}"]
  artifacts: [{path: "{file}", provides: "{what}", contains: "{string}"}]
  key_links: [{from: "{src}", to: "{tgt}", via: "{rel}"}]
---
<objective>
{objective-description}
</objective>
<context>
@{context-file}
</context>
<tasks>
<task type="auto">
  <name>{task-name}</name>
  <files>
    {file-1}
  </files>
  <strategy>{tdd|refactor|spike}</strategy>
  <estimate>{low}-{high}{unit}</estimate> <!-- A range. Never a single number. -->
  <depends_on>[{task-name}]</depends_on> <!-- Other task names in this plan. Empty list when none. -->
  <craft_gate>{code-review|simplification|unit-testing}</craft_gate> <!-- Coding tasks only. -->
  <action>
{what-to-do}
  </action>
  <verify>
{how-to-verify}
  </verify>
  <done>
{completion-criteria}
  </done>
</task>
</tasks>
<verification>
1. {check}
</verification>
<success_criteria>
- {criterion}
</success_criteria>
<output>
{plan-number}-SUMMARY.md
</output>
