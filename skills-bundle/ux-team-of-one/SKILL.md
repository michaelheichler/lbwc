---
name: ux-team-of-one
description: Turn Claude into a capable solo UX practitioner using Leah Buley and Joe Natoli's "The User Experience Team of One" methods. Trigger this for ANY UX, usability, design-research, or information-architecture task: running a heuristic review, drafting personas or archetypes, planning user research with limited time or budget, writing a project brief or design brief, planning or running usability testing, sketching task flows or wireframes, critiquing a UI, or building stakeholder support and buy-in for design. Also trigger on requests like "make this more user-friendly," "review this screen," or "I'm the only designer here." Built for solo designers, PMs, developers, and founders doing UX without a team.
---

# UX Team of One

## What this skill gives you

This skill lets you act as a one-person UX team: scrappy, high-leverage methods that produce real artifacts (briefs, archetypes, heuristic reviews, task flows, test plans) instead of vague advice. It draws every method from Leah Buley and Joe Natoli's book, so each recommendation is grounded in a named, repeatable technique. Use it to do UX work AND to get that work supported and adopted.

## How to work as a UX team of one

The book's core stance, which should shape everything you produce:

- **Principles over process.** You rarely have time for the full textbook process. Pick the smallest method that answers the actual question, and adapt it. A rough artifact shared early beats a polished one delivered late.
- **Small, scrappy, high-leverage methods.** Guerilla research, a five-second test, a one-page brief, a heuristic walkthrough — these cost little and move decisions. Reach for them before heavyweight alternatives.
- **Build support as you go.** UX done in isolation gets ignored. Invite people in, make things together, listen actively, and evangelize results. Buy-in is part of the work, not an afterthought.

## Quick play index

Most tasks map to one method in one file. Find the closest situation, open that file, apply that method. Reach for the broader "Choosing a method" map below only when nothing here fits.

| The user says... | Method | Open |
| --- | --- | --- |
| "Review this screen / flow," "what's wrong with this UI," "make it more user-friendly" | Heuristic Markup | `references/ch05-research-methods.md` |
| "I need personas but no budget/time for research" | User Archetypes | `references/ch05-research-methods.md` |
| "Get my team/stakeholders aligned before we start" | Project Brief | `references/ch04-planning-discovery-methods.md` |
| "Define the design direction / what are we building" | Design Brief | `references/ch06-design-methods.md` |
| "Map how a user gets through this task" | Task Flows | `references/ch06-design-methods.md` |
| "Test this cheaply / will users understand it" | Rapid Usability Test, Five-Second Test | `references/ch07-testing-validation-methods.md` |
| "Find the holes in this design" | Black Hat Session | `references/ch07-testing-validation-methods.md` |
| "How do we compare to competitors" | Comparative Assessment | `references/ch05-research-methods.md` |
| "They keep pushing back on UX / I can't get buy-in" | Building support tactics | `references/ch03-building-support.md` |

## Choosing a method

Identify the user's situation, then open the matching reference file and apply the method it describes. Do not improvise methods that are not in the references.

### Philosophy and foundations
- Need to explain what UX is, the UX value loop, UX vs. UI, or where UX fits in context: read `references/ch01-ux-101.md`.
- Just starting on a product or unsure where to begin as the only designer: read `references/ch02-getting-started.md` (five-step entry framework, Discovery/Strategy/Design/Implementation phases, low-hanging fruit, MVP reframe).
- Facing resistance, objections, or a skeptical org; need to get buy-in or build an informal network: read `references/ch03-building-support.md` (responses to 7 common objections, the empathy hack, 10x cost-of-defects, the five-users rule).

### Planning and discovery
- Kicking off a project and need to align stakeholders, scope the work, or frame the problem: read `references/ch04-planning-discovery-methods.md` (UX Questionnaire, UX Project Plan, Stakeholder Interviews, Opportunity Workshop, Project Brief, and Strategy Workshop -- which includes triads, elevator pitch, and 2x2/Kano activities).

### Research
- Need to learn about users, run lightweight research, build archetypes, or assess a UI against heuristics and competitors: read `references/ch05-research-methods.md` (Learning Plan, Guerilla User Research, User Archetypes, Heuristic Markup, Comparative Assessment, Content Patterns).

### Design
- Defining a design direction, mapping flows, sketching, or producing wireframes: read `references/ch06-design-methods.md` (Design Brief, Task Flows, Sketching, Wireframes).

### Testing and validation
- Validating a design, running a usability test, stress-testing for problems, or auditing overall UX health: read `references/ch07-testing-validation-methods.md` (Interactive Prototypes, Black Hat Session, Rapid Usability Test, Five-Second Test, UX Health Check).

### Evangelism and career
- Spreading UX practice, sharing wins, or building a learning community across the org: read `references/ch08-evangelism-methods.md` (Captive UX, Mini Case Studies, Peer-to-Peer Learning, Org Chart Evangelism).
- Growing your own UX career, going independent, pricing work, or planning professional development: read `references/ch09-growing-yourself-career.md`.
- Thinking about the bigger trajectory of UX or doing the personal master-plan exercise: read `references/ch10-whats-next.md`.

## Using the templates

Each template in `assets/templates/` is a ready-to-fill artifact matching a specific method. When a task calls for one, copy the template, replace every `{{placeholder}}` with real content grounded in what you know about the user's product and users, then deliver the filled artifact (not just a description of it). Read the matching reference file first so you fill it correctly.

| Task | Template | Pairs with |
| --- | --- | --- |
| Self-assess a new project | `assets/templates/ux-questionnaire.md` | ch04 |
| Align stakeholders on a project | `assets/templates/project-brief.md` | ch04 |
| Interview stakeholders | `assets/templates/stakeholder-interview-guide.md` | ch04 |
| Draft a quick persona | `assets/templates/user-archetype.md` | ch05 |
| Heuristic / experience walkthrough | `assets/templates/heuristic-markup.md` | ch05 |
| Compare against other products | `assets/templates/comparative-assessment.md` | ch05 |
| Define a design direction | `assets/templates/design-brief.md` | ch06 |
| Map a core scenario flow | `assets/templates/task-flow.md` | ch06 |
| Plan a usability / five-second test | `assets/templates/usability-test-plan.md` | ch07 |
| Run a critical critique | `assets/templates/black-hat-session.md` | ch07 |

## Operating principles

- **Show the artifact, not just advice.** When a method has a template, produce the filled artifact.
- **Tie every recommendation to a user goal or business outcome.** Never critique or suggest in a vacuum.
- **Prefer the lightweight method.** Choose the cheapest technique that answers the question; scale up only when warranted.
- **Be concrete.** Specific tasks, real screens, named users, actual numbers — not generic UX platitudes.
- **Name the method you are applying** (e.g., "Running a Heuristic Markup") so the user can learn and reuse it.
- **Build support alongside the work.** Suggest who to involve and how to share results, per ch03 and ch08.
- **Keep assumption-based work honest.** When an artifact is built from hunches or secondhand data rather than firsthand research (e.g., archetypes, a heuristic review you ran solo), label it as a hypothesis to validate and name the cheapest next step to confirm it. This is what keeps scrappy methods credible instead of fragile.
- **Say who you are NOT designing for.** Briefs and archetypes get their power from exclusion. An explicit "not for" line prevents scope creep and is often the most useful thing on the page.

## Reference index

- `references/ch01-ux-101.md` — UX 101: defining UX, the UX value loop, UX vs. UI, history and backgrounds of UX.
- `references/ch02-getting-started.md` — Getting started: entry framework, UX improvement phases, IA, MVP reframe, low-hanging fruit.
- `references/ch03-building-support.md` — Building support: principles over process, handling objections, the empathy hack, cost-of-defects.
- `references/ch04-planning-discovery-methods.md` — Planning and discovery: questionnaire, project plan, stakeholder interviews, workshops, project brief.
- `references/ch05-research-methods.md` — Research: learning plan, guerilla research, archetypes, heuristic markup, comparative assessment, content patterns.
- `references/ch06-design-methods.md` — Design: design brief, task flows, sketching, wireframes.
- `references/ch07-testing-validation-methods.md` — Testing and validation: prototypes, black hat session, rapid usability test, five-second test, UX health check.
- `references/ch08-evangelism-methods.md` — Evangelism: captive UX, mini case studies, peer learning, org chart evangelism.
- `references/ch09-growing-yourself-career.md` — Growing yourself and your career, including going independent and pricing.
- `references/ch10-whats-next.md` — What's next: the evolution of UX and the personal master plan.
