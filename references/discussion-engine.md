# Discussion Engine

One engine, two entry points: `/lbwc:vibe` auto-dispatches here when phase detection reports `needs_discussion`, and `/lbwc:discuss` invokes it directly. The user is the visionary, the orchestrator is the builder. The engine's job is to surface decisions that downstream agents (`lead`, engineers) need so they never ask the user again mid-phase. No agent is spawned for this, the main session runs it inline.

## Shared decision boundary

Follow `references/ask-user-question.md`. The main session asks one bounded, single-select question at a time and pauses the workflow while it is pending. Recommendations guide the user, but do not create a decision. Generated agents return the escalation payload in `references/subagent-contracts.md` instead of asking the user or changing decision state.

## Step 1: Calibrate

Infer user sophistication from conversation signals, never ask: language in prior messages (jargon vs plain), project description complexity, and whether they typed `/lbwc:discuss` explicitly or arrived via `/lbwc:vibe`.

| Mode | Signals | Question style |
| --- | --- | --- |
| **Builder** | Plain language, non-technical framing | Scenario-based, cause-and-effect, no jargon |
| **Architect** | Technical terms, specific requirements | Direct, domain terms, trade-off framing |

## Step 1.5: Detect continuation

Check whether `{NN}-CONTEXT.md` already exists in the target phase directory.

- **No CONTEXT.md:** fresh discussion, proceed normally.
- **CONTEXT.md exists:** continuation discussion. Read it first, load existing `## Decisions Made` subsections as the baseline, and orient only on what is not already covered.

## Step 1.7: Assumptions path (optional)

An alternative to the question-driven flow: read the codebase first, form evidence-backed assumptions, present them for correction. Reduces interaction from many questions to a few corrections.

Activation, first match wins:

1. `--assumptions` in `$ARGUMENTS` → assumptions path
2. `discussion_mode` is `"assumptions"` in `.lbwc-planning/config.json` → assumptions path
3. `discussion_mode` is `"auto"` and `.lbwc-planning/codebase/META.md` exists → assumptions path
4. Otherwise → questions path (Step 2)

If the assumptions path activates but no codebase map exists, say so and fall back to questions: "Assumptions mode works best with codebase context. Run `/lbwc:map` first for evidence-backed assumptions, or falling back to questions mode."

**A1: Codebase analysis.** Read `.lbwc-planning/codebase/ARCHITECTURE.md`, `PATTERNS.md`, and `CONCERNS.md` when present, plus the phase goal from ROADMAP.md. For gray areas needing deeper evidence, read the actual source files, do not form assumptions from summaries alone when the source is readily available.

**A2: Form assumptions.** Identify gray areas the same way Step 2 does, then structure each as:

```
### [Gray Area Title]

**Assumption:** [What you conclude from codebase evidence]
**Evidence:** [File paths + specific code patterns]
**Confidence:** High (90%+) | Medium (60-90%) | Low (<60%)
**Consequence if wrong:** [What breaks or needs rework]
```

**A3: Present for correction.** Present one assumption at a time with its recommendation. High and medium confidence assumptions still need an explicit user confirmation. Low confidence assumptions are genuine questions and follow Step 3.

**A4: Process corrections.** Confirmed: record the assumption as the decision. Corrected: record the user's correction, preserving the original assumption as context. Native Other returns the typed correction directly. Use it to update the assumption, then confirm. A dismissed interaction records no decision and stops the workflow.

## Step 2: Orient

Read the phase goal from ROADMAP.md and think: what decisions about this phase could go multiple ways and would change what gets built? No keyword matching, no predefined templates.

Gray areas must be phase-specific and concrete. Bad: "UI decisions", "Data handling". Good: "Cold-start behavior for a user with no history", "Dietary restrictions as strict filter vs soft preference".

Form a preliminary recommendation per area before asking anything. If a recommendation depends on codebase state, read the relevant files first, do not speculate about code you have not opened. Aim for 3-5 gray areas on a fresh discussion.

**Continuation mode:** exclude areas already covered by existing `## Decisions Made` subsections. Focus on topics not selected last time, second-order effects of decisions already made, and deferred ideas worth revisiting. Continuation selection must always offer an explicit `None: discussion is complete` path.

**Selection:** present one gray area at a time. Use a structured single-select question only when there are 2-4 visible options. For a single fresh area, proceed to that area without a selection question. For 5-6 areas, use a numbered list and ask the user to name the next area in a plain-text reply, with no options array. Split a structured candidate list when adding continuation's explicit `None: discussion is complete` path would exceed four options. After resolving an area, ask whether to choose another area. Fresh discussion copy: "Which area should we discuss first?" Continuation copy: "These topics weren't covered in the previous discussion. Which would you like to explore first?"

## Step 3: Explore

**Early exit:** no selected areas (user chose `None: discussion is complete`) → skip to Step 4, which then writes nothing.

For each selected area, a natural conversation, not a form:

1. Open with your recommendation: state the gray area, give the recommendation with 2-3 sentences of reasoning, ask for confirmation. The first option is the recommended choice with "(Recommended: [brief reason])" in the label, followed by 1-2 alternatives. Claude Code adds native Other.
2. Recommended picked: confirm in one line, move on.
3. Alternative picked: record it. Follow up only if it changes a downstream requirement.
4. Native Other: process the typed answer, adjust, and confirm.
5. Move to the next area.

**Clear-cut decisions:** when a standard practice answer is obvious, state the recommendation and ask one confirmation question for that decision. Do not batch decisions.

**Scope awareness:** if the user mentions something outside the phase boundary, one line: "[Feature] sounds like its own phase. I'll note it." Captured under Deferred Ideas.

**Vague answers:** ask a plain narrowing follow-up ("Fast in what way: page loads, search, or many users at once?").

## Step 4: Capture

Write or update `.lbwc-planning/phases/{NN}-{slug}/{NN}-CONTEXT.md` from `templates/CONTEXT.md`. The `{NN}-` prefix is load-bearing: `phase-detect.sh`'s `needs_discussion` check only counts canonical `[0-9]*-CONTEXT.md` names.

**Continuation mode:** do not overwrite. Merge: new `### [Gray Area]` subsections appended under `## Decisions Made`, new entries appended to Deferred Ideas. Never remove, rewrite, or reorder existing content, the original decisions still stand. If the user selected `None: discussion is complete`, write nothing.

**Assumptions-mode decisions** go under `## Decisions Made` with the evidence block the template's comment describes (`**Evidence:**`, `**Confidence:**`, `**Correction:**` when corrected).

**Fresh discussion:** fill the template's sections from the conversation: User Vision, Essential Features, Technical Preferences, Boundaries, Acceptance Criteria, and one `### [Gray Area]` subsection per decision. Leave a section out only when the discussion genuinely produced nothing for it, do not invent content to fill the template.

## Design principles

- **One engine.** `/lbwc:vibe` dispatch and standalone `/lbwc:discuss` run the same protocol.
- **Calibrate silently.** Never ask "are you technical?".
- **Orient from the phase, not from templates.** Gray areas come from analysis, not predefined lists.
