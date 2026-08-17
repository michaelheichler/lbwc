# AskUserQuestion Contract

Use this contract whenever the main session asks the user to choose the next step. It applies to `/lbwc:*` commands, `.lbwc-planning` workflows, and `commands/teach.md`.

## Main-session decision boundary

Only the main session may call AskUserQuestion. Keep at most one request pending and send exactly one question in that request. A pending question pauses its workflow. Do not spawn follow-on agents, run a decision-dependent trusted shell transition, write a decision artifact, or advance the workflow until the user responds.

Use AskUserQuestion only for a real bounded decision. Use plain text when the answer must name, search, number, or describe something outside a short fixed list.

A generated agent that needs a user choice returns the `user_decision_required` payload in `references/subagent-contracts.md`. It does not ask the user or mutate decision state.

## Write for quick decisions

- Use plain words and explain technical terms before using them.
- State one decision in the question. Include the answer-critical context in the question because a dialog can hide nearby prose.
- Use a concrete header and a short question.
- Supply 2 to 4 visible options. Set `multiSelect` to `false`.
- Give every option a concrete 1 to 5 word label and a one-sentence description.
- Mark one option recommended only when there is a concrete reason.
- Do not hedge, lecture, repeat known context, or turn one decision into a wall of text.

## Other, freeform, and cancellation

Claude Code adds native `Other` to every bounded question. Do not duplicate it in the visible options. The completed tool response returns the user's typed text in the answer map. Process that text directly. Do not expect a literal `Other` or `__other__` answer, and do not ask a second freeform question.

Add a visible cancel or defer option when that is a meaningful workflow outcome. Killing or dismissing the dialog clears the pending decision. The session continues normally. Do not keep the pending-decision lock and do not force a re-ask.

## Tool shape

For an interactive call, send `questions` containing exactly one question with a short `header`, complete `question`, 2 to 4 `options`, and `multiSelect: false`. Each option has a `label` and `description`. Option-level `preview` is optional.

Do not use `answers`, `annotations`, or `metadata` to compose an interactive question. They are response or host-integration fields. Do not set a question-level `preview` or assume a `metadata.source` value or per-question `annotations` shape.

## Examples

### Structured single-select

Header: Continue

Question: Start implementation for phase 03 now?

Options:

- Start now. Begin the approved work. (Recommended)
- Review plans. Inspect the plan before implementation.
- Cancel workflow. Leave the current work unchanged.

### Intentional freeform

Prompt: Tell me which todo to act on. Use its number or describe the item in your own words.

This stays plain text because the possible answers are not a short fixed list.

## Final check

Keep one decision pending, make the freeform boundary explicit, and resume workflow only from the main session after a user response.
