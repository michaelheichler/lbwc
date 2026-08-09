# Orchestration and Flow

Source: About Face: The Essentials of Interaction Design, 4th Edition (Cooper, Reimann, Cronin, Noessel, 2014), Chapter 11.

## In one line

Design the whole interaction, not isolated screens or dialogs, so the product stays out of the user's way and lets her sink into flow, the state of deep, productive concentration.

## Core ideas

**Flow is the target state.** Borrowed from Mihaly Csikszentmihalyi, flow is a nearly meditative absorption in an activity where peripheral distractions disappear and productivity peaks. Software that interrupts, questions, or nags breaks flow. The design goal is to protect and extend that state, not to showcase the interface.

**Transparency beats cleverness.** Users are almost never in software for the software's own sake, they want to reach a goal. A good interface disappears the way good prose does, a reader forgets they are reading and just sees the story. If a user notices the interface, something has probably gone wrong. Corollary: no matter how appealing an interaction pattern looks, less of it is usually better, because attention spent on the tool is attention stolen from the goal.

**Orchestration is holistic, not rule-based.** Just as no formula defines a "good" sentence outside its story, no fixed rule (like "4 buttons good, 6 bad") defines a well-behaved interface outside its context of use. What matters is whether every element works in coherent service of the user's current goal. The designer's job is to hear the "sour note", the control or step that doesn't fit the moment, and remove or relocate it.

**Why complexity creeps in.** Enterprise and professional software often ends up complex but not powerful: each feature lives in its own silo (dialog, window, menu) with no thought to how tasks actually chain together. This isn't usually deliberate, it results from ad hoc growth or disconnected teams each solving their own slice (the book's example: a phone whose address book and calendar used two different text-entry systems because two teams built them separately). The fix is a minimalist stance driven by a clear sense of user purpose, cutting elements without cutting capability or adding effort (Google's original search page and the iPod Shuffle are held up as purposeful, minimal designs). Watch the failure mode too: extreme minimalism can trade visual simplicity for cognitive complexity if it breaks users' existing mental models (the iPod Shuffle's overloaded power/pause button confused people coming from CD players).

**Response time shapes what users feel, not just what they measure.** Long-standing research (Miller, 1968) breaks perceived latency into bands: under 0.1s feels instantaneous and like direct manipulation, under about 1s feels responsive with an uninterrupted train of thought, up to about 10s feels slow and needs a progress bar to hold attention, beyond 10s the user mentally checks out and should be given a background task, a cancel option, and a time estimate instead of a frozen screen. Design (and negotiate with engineering) to keep operations inside the faster bands, and gracefully degrade communication as latency grows.

**Motion earns its place only by serving flow.** Animation and transitions (pioneered on the original Macintosh, matured on iPhone) are powerful for showing spatial and causal relationships between views, but they cost attention. Use them sparingly and only when they help: too much motion confuses, irritates, or (documented after iOS 7's launch) can make some users physically ill.

## Named patterns and principles

- **Flow**: Csikszentmihalyi's state of deep, absorbed, productive concentration. Aim every design decision at preserving it, because disruption (dialogs, unnecessary questions, latency) knocks users out of it and costs real productivity.
- **Orchestration**: "harmonious organization" of all interface elements toward a single goal, with no universal rule set. Apply it by judging each element against the current task context, not against abstract style rules.
- **"No matter how cool your interface is, less of it would be better"**: named reminder that interaction mechanics are overhead relative to the user's actual goal, so celebrate the goal reached, not the cleverness of the UI on the way there.
- **Follow users' mental models**: organize data and navigation around how the user already thinks about the domain (patients by name for clinicians, bills by days-overdue for billing clerks), not around the system's internal structure. It works because it maps the interface onto a model the user already carries.
- **Less is more**: keep the interface as small as possible without cutting capability or adding user effort. Prevents the "complex but not powerful" trap of siloed, feature-scattered UI.
- **Let users direct rather than discuss**: design interaction as tool use (hammer, steering wheel), not as a two-way conversation. Users want to give direction and get direct feedback, not be interrogated. Direct manipulation is the primary mechanism for this.
- **Provide choices rather than ask questions**: prefer always-available, modeless toolbars and palettes over modal dialogs that block progress until answered. Choice-offering respects user control, question-asking removes it.
- **Keep necessary tools close at hand**: put tools where they're visible and reachable with a single click or keystroke (palettes/toolbars for less expert users, keyboard shortcuts for experts), and never force the user to go hunting or to explicitly put a tool away. Distance and disappearance both break concentration.
- **Provide modeless feedback**: surface status and results inside the ongoing interface (status bars, inline indicators, heads-up style overlays) rather than stopping the user with a dialog. It informs without demanding a response, so flow continues.
- **Design for the probable but anticipate the possible**: build for what will almost certainly happen, and handle rare edge cases without surfacing them as default friction. Developers, thinking in strict Boolean terms, treat a rare possibility as equally worth guarding against as a common one, users don't, and shouldn't be asked to. A near-certain action (like saving) should never require confirmation just because abandoning work is theoretically possible.
- **Contextualize information**: don't just present raw precise numbers, show what they mean relative to something (Tufte's "compared to what?"). A byte count is less useful than a percentage-full bar. Precision without context fails to communicate and forces the user to do interpretive work that breaks flow.
- **Reflect object and application status**: make the state of the system and its objects visible the way a person's posture and expression reveal whether they're busy, asleep, or free. Users should be able to tell at a glance if the app is thinking, idle, or blocked, and whether an object (email, calendar invite) is read, answered, or pending.
- **Avoid unnecessary reporting**: don't surface routine internal events (connections made, records posted) that mean nothing to a normal user, even though they reassure a developer during debugging. Reserve interruption-worthy notification for genuinely abnormal events, use ambient or modeless signals for "all is well." Named rule: "Don't use dialogs to report normalcy."
- **Avoid blank slates**: take a goal-directed first action for the user (reasonable defaults, remembered preferences) rather than demanding a battery of upfront answers before doing anything. Most people would rather correct a good first guess than build one from nothing. Named rule: "Ask for forgiveness, not permission."
- **Differentiate between command and configuration**: separate "just do the common thing" (one click, sane defaults or last-used settings) from "let me tune every parameter" (a distinct, deeper configuration surface). Because users invoke a function far more often than they reconfigure it, optimize the frequent path and push rare, detailed control behind an explicit second step.
- **Hide the ejector seat levers**: keep any irreversible or drastically disruptive action (deleting permanent objects, radically rearranging the workspace) out of casual reach, the way a fighter jet's ejector lever is deliberately hard to trigger by accident. Reversible cosmetic changes are lower risk than actions the user and colleagues will be stuck with, so gate the second kind hardest.
- **Optimize for responsiveness but accommodate latency**: push implementation choices toward low latency where possible, and where latency is unavoidable communicate it clearly (progress, time remaining, cancel option), following the perceived-time bands (0.1s / 1s / 10s) from Miller's research.

## How to apply

- Before adding a dialog, control, or confirmation step, ask what percentage of the time it actually matters, if it's rare, move it out of the default path instead of blocking everyone for the edge case.
- Default every new object or document to the most likely useful state (last used settings, learned preferences) instead of opening a blank canvas or a setup wizard.
- Split every multi-parameter feature into a one-click "just do it with sane defaults" action and a separate, discoverable "configure it" surface, don't force configuration on every invocation.
- Represent status (busy, idle, unread, pending, syncing) continuously and modelessly in the interface, don't make users ask for it.
- When showing a quantity, pair it with context (percentage, comparison, a bar or chart) rather than a bare precise number.
- Gate irreversible or workspace-rearranging actions behind deliberate friction (confirmation, a separate screen, a non-adjacent control), keep everyday actions frictionless.
- Budget and monitor latency against the 0.1s / 1s / 10s perception bands, add a progress indicator past 1s and a cancel plus time estimate past 10s, and push long operations to the background.
- Use motion only when it demonstrably does one of: focuses attention, shows a relationship between objects, preserves context across a transition, signals progress, builds a coherent virtual space, or increases engagement. Keep animations short (under about a second) and physically plausible (inertia, easing) rather than decorative.
- When auditing an existing flow, look for the "sour note", any element that serves the system's internal logic rather than the user's current goal, and cut or relocate it.
- Map information architecture and terminology to how the actual user population already thinks about the domain, not to the system's data model.

## Watch out for

- Treating every logically possible outcome as equally deserving of a confirmation dialog, this is a developer's Boolean mindset leaking into design, not a user need.
- Confusing "showing precise data" with "communicating," raw precision (exact byte counts) can obscure the one thing the user actually needs to know.
- Over-minimizing to the point that visual simplicity creates cognitive complexity, cutting controls only works if it still matches users' mental models (the iPod Shuffle power-button confusion is the cautionary case).
- Using notification-style interruptions to report that everything is fine, save interruptions for genuine exceptions.
- Letting silo-built features (each shipped by a different team or era) coexist without integration, this is how products end up complex without being powerful.
- Overusing motion and animated transitions, beyond usability cost, excessive or poorly designed motion can cause physical discomfort for some users.
- Making irreversible actions and simple visual tweaks equally easy to trigger, irreversible ("ejector seat") actions need real friction, cosmetic ones don't.
