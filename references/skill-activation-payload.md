# Skill Activation Payload Rendering

Use this file only while constructing a child prompt. Render exactly one branch. Do not paste this template, its variable names, or an unresolved `@` include into the child prompt.

Inputs:

- `skill_calls`: ordered `Call Skill(...)` lines. Empty when no skills were preselected.
- `no_skill_reason`: brief task-specific reason used only when `skill_calls` is empty.
- `follow_up_files_block`: complete helper-emitted `<skill_follow_up_files>` block. Empty when the helper emits nothing.

## Selected skills

When `skill_calls` is non-empty, render:

```text
<skill_activation>
{skill_calls}
</skill_activation>
After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
{follow_up_files_block}
```

Omit the final line when `follow_up_files_block` is empty.

## No selected skills

When `skill_calls` is empty, render:

```text
<skill_no_activation>
Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {no_skill_reason}.
</skill_no_activation>
After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
```
