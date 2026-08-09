---
name: interaction-design-cooper-tidwell
description: The interaction-design grounding for planning and building UI, grounded in About Face 4th Edition (Cooper, Reimann, Cronin, Noessel) and Designing Interfaces 3rd Edition (Tidwell, Brewer, Valencia). Use this skill whenever the task is designing or building a UI, a website, a web app, a screen, a flow, a form, navigation, a dashboard, a list, a data display, or a design system, whenever you review or critique an interface, whenever you choose UI patterns, or whenever you plan interaction-design work such as research, personas, scenarios, requirements, framework, or visual design. Trigger it even when the user never says "design" but is clearly shaping how a product looks or behaves.
---

# Interaction Design (Cooper and Tidwell)

## Purpose

Use this skill to design and build interfaces two ways that reinforce each
other. About Face gives you the Goal-Directed Design process, the reasoning
that decides what a product should do and how it should behave before a pixel
is placed. Designing Interfaces gives you the pattern catalog, the proven
solutions for navigation, layout, lists, forms, data, and mobile once you know
what you are building. Reach for the process when the task is fuzzy or new, and
for the catalog when you need a concrete, named solution to a concrete screen.

The bundled references are paraphrased chapter briefs of two books:

- About Face 4th Edition (Cooper, Reimann, Cronin, Noessel): research,
  personas, scenarios, requirements, framework, behavior, posture, flow,
  excise, affordances, errors, visual design, and per-platform detail.
- Designing Interfaces 3rd Edition (Tidwell, Brewer, Valencia): information
  architecture, navigation, layout, visual style, mobile, lists, actions,
  data displays, forms, and design systems.

## Source boundary

Use the references as method and pattern guidance for design, build, and review
decisions. Do not reproduce book prose or full chapters. Cite the book and the
named pattern or principle so the user can learn and reuse it (for example
"Modal Panel from Designing Interfaces ch03" or "the excise principle from
About Face ch12"). Prefer the user's product language, stack, and existing
conventions over book examples. The patterns are a vocabulary, not a template
to paste.

## Workflow

1. Classify the task. Is it upstream design reasoning (who is this for, what
   must it do, how should it behave, what posture), or is it a concrete screen
   or component that needs a known pattern, or is it a review of an existing
   interface? About Face answers the first, Designing Interfaces answers the
   second, and a review usually pulls from both.
2. Load the one to three most relevant references from the routing tables
   below. Do not load the whole bundle. Match by task shape and by pattern name.
3. Apply the method or pattern to the user's actual product. Ground every
   choice in a user goal, not in taste or in feature convenience.
4. Cite the book and the named pattern or principle you used.

For a genuinely new product, run the About Face phases in order: research
(ch02), personas (ch03), scenarios and requirements (ch04), framework (ch05),
then refine behavior and visual design (ch07 to ch17) and platform detail
(ch18 to ch21). For a single screen or widget, skip straight to the Designing
Interfaces chapter that owns that problem.

## Review heuristics

- Every design choice traces to a persona goal, not to a feature list or an
  implementation model (About Face ch01, ch03).
- Strip excise. Any work the interface imposes that does not advance the user's
  goal is a finding (About Face ch12).
- Match the posture to the attention the product can claim, sovereign,
  transient, or daemonic (About Face ch09).
- Prefer preventing errors and offering undo over error dialogs (About Face
  ch15).
- Name the pattern. A layout, list, or form built from a named pattern is
  easier to defend and reuse than an improvised one (Designing Interfaces).

## Routing: About Face (Goal-Directed Design process)

| Chapter | File | Use when |
| --- | --- | --- |
| 1. A Design Process for Digital Products | `references/about-face-ch01-a-design-process-for-digital-products.md` | Establishing why a systematic, goal-directed process beats feature-driven or implementation-driven design. |
| 2. Understanding the Problem: Design Research | `references/about-face-ch02-understanding-the-problem-design-research.md` | Planning or running stakeholder, SME, and ethnographic user research to ground decisions in real behavior. |
| 3. Modeling Users: Personas and Goals | `references/about-face-ch03-modeling-users-personas-and-goals.md` | Turning research into personas driven by experience, end, and life goals instead of an elastic user. |
| 4. Setting the Vision: Scenarios and Design Requirements | `references/about-face-ch04-setting-the-vision-scenarios-and-design-requirements.md` | Using persona scenarios to discover what a product must do before deciding how. |
| 5. Designing the Product: Framework and Refinement | `references/about-face-ch05-designing-the-product-framework-and-refinement.md` | Building the top-down design framework and refining it with key path and validation scenarios. |
| 6. Creative Teamwork | `references/about-face-ch06-creative-teamwork.md` | Structuring a small core design team and coordinating with the wider product organization. |
| 7. A Basis for Good Product Behavior | `references/about-face-ch07-a-basis-for-good-product-behavior.md` | Grounding behavior in design values, principles, and reusable behavioral patterns. |
| 8. Digital Etiquette | `references/about-face-ch08-digital-etiquette.md` | Making software behave like a considerate, socially fluent colleague rather than a rude machine. |
| 9. Platform and Posture | `references/about-face-ch09-platform-and-posture.md` | Choosing platform and posture (sovereign, transient, daemonic) before detailing screens. |
| 10. Optimizing for Intermediates | `references/about-face-ch10-optimizing-for-intermediates.md` | Designing for the perpetual intermediate rather than splitting into beginner and expert modes. |
| 11. Orchestration and Flow | `references/about-face-ch11-orchestration-and-flow.md` | Keeping the product out of the user's way and preserving flow across the whole interaction. |
| 12. Reducing Work and Eliminating Excise | `references/about-face-ch12-reducing-work-and-eliminating-excise.md` | Finding and cutting cognitive, memory, visual, and physical work that does not serve the goal. |
| 13. Metaphors, Idioms, and Affordances | `references/about-face-ch13-metaphors-idioms-and-affordances.md` | Choosing idiomatic learn-once controls and signaling manipulability with the right affordance. |
| 14. Rethinking Data Entry, Storage, and Retrieval | `references/about-face-ch14-rethinking-data-entry-storage-and-retrieval.md` | Making data entry and retrieval follow the user's mental model, not the database schema. |
| 15. Preventing Errors and Informing Decisions | `references/about-face-ch15-preventing-errors-and-informing-decisions.md` | Replacing error dialogs with modeless feedback, generous undo, and preview before commit. |
| 16. Designing for Different Needs | `references/about-face-ch16-designing-for-different-needs.md` | Serving skill levels, personalization, localization, and accessibility together. |
| 17. Integrating Visual Design | `references/about-face-ch17-integrating-visual-design.md` | Applying goal-directed rigor to hierarchy, color, grid, type, and design language. |
| 18. Designing for the Desktop | `references/about-face-ch18-designing-for-the-desktop.md` | Choosing window, menu, toolbar, and direct-manipulation idioms and their timing details. |
| 19. Designing for Mobile and Other Devices | `references/about-face-ch19-designing-for-mobile-and-other-devices.md` | Designing transient, finger-scale, context-driven mobile and embedded interfaces. |
| 20. Designing for the Web | `references/about-face-ch20-designing-for-the-web.md` | Designing page-and-link navigation, search, scroll, and responsive layout for the web. |
| 21. Design Details: Controls and Dialogs | `references/about-face-ch21-design-details-controls-and-dialogs.md` | Picking the right control and dialog type and engineering away needless confirmations. |
| Appendix A. Design Principles | `references/about-face-appa-design-principles.md` | Running the collected principle checklist over a goal-directed design review. |

## Routing: Designing Interfaces (UI pattern catalog)

| Chapter | File | Use when |
| --- | --- | --- |
| 1. Designing for People | `references/designing-interfaces-ch01-designing-for-people.md` | Grounding design in users' context, goals, and predictable cognitive and behavioral patterns. |
| 2. Organizing the Content: Information Architecture and Application Structure | `references/designing-interfaces-ch02-organizing-the-content-information-architecture-and-applicat.md` | Structuring an app before visual design, choosing among dashboard, wizard, feed, and other structure patterns. |
| 3. Getting Around: Navigation, Signposts, and Wayfinding | `references/designing-interfaces-ch03-getting-around-navigation-signposts-and-wayfinding.md` | Designing navigation so users know where they are, where they can go, and how to get back. |
| 4. Layout of Screen Elements | `references/designing-interfaces-ch04-layout-of-screen-elements.md` | Signaling importance and sequence through hierarchy, flow, grids, and Gestalt grouping. |
| 5. Visual Style and Aesthetics | `references/designing-interfaces-ch05-visual-style-and-aesthetics.md` | Applying color, type, imagery, and a style family as a functional trust-and-readability layer. |
| 6. Mobile Interfaces | `references/designing-interfaces-ch06-mobile-interfaces.md` | Designing for tiny touch screens, distracted users, and unreliable connections. |
| 7. Lists of Things | `references/designing-interfaces-ch07-lists-of-things.md` | Choosing a list-display pattern after deciding the list's use cases and structure. |
| 8. Doing Things: Actions and Commands | `references/designing-interfaces-ch08-doing-things-actions-and-commands.md` | Making commands discoverable, forgiving, and fast to repeat with buttons, undo, and history. |
| 9. Showing Complex Data | `references/designing-interfaces-ch09-showing-complex-data.md` | Designing interactive information graphics for exploring, comparing, and drilling into data. |
| 10. Getting Input from Users: Forms and Controls | `references/designing-interfaces-ch10-getting-input-from-users-forms-and-controls.md` | Shrinking form effort with defaults and forgiving input, then making each control self-explanatory. |
| 11. User Interface Systems and Atomic Design | `references/designing-interfaces-ch11-user-interface-systems-and-atomic-design.md` | Building interfaces as a reusable component system on a UI framework, not one-off screens. |
| 12. Beyond and Behind the Screen | `references/designing-interfaces-ch12-beyond-and-behind-the-screen.md` | Designing sensor, algorithm, and screenless systems that stay legible and low-effort. |

For the full pattern-and-principle map (route by pattern name, not just
chapter), open `references/index.md`.

## Output style

Lead with the user goal and the classification, then name the method or pattern
you are applying and the book it comes from. Give the concrete design, not a
lecture on the theory. When you cut something, say which excise it removes.
When you pick a pattern, name it and one credible alternative you rejected.
