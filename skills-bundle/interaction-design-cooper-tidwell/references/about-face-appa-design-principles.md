# Appendix A: Design Principles (the collected principle list)

Source: About Face: The Essentials of Interaction Design, 4th Edition (Cooper, Reimann, Cronin, Noessel, 2014), Appendix A, the book's full roster of named design principles gathered from every chapter.

## In one line

Appendix A is the book's own index of every named design principle it states along the way, grouped by the chapter that introduced it, meant to work as a quick-reference checklist for critique and design review.

## Core ideas

- This appendix exists because the book scatters dozens of terse, quotable rules across 21 chapters. Collecting them in one place turns them into a checklist a designer or reviewer can scan fast, rather than something buried in narrative.
- The principles are not independent trivia. They cluster around a small number of recurring commitments the whole book argues for: design from the user's mental model, protect the user's dignity and time, make software behave considerately, match rigor of visual and interaction design to the platform, strip out unnecessary effort (excise), give rich and honest feedback, and make errors hard to trigger and easy to recover from.
- Treat this list as an audit tool. When reviewing a design, agents should check candidate decisions against the relevant cluster below rather than trying to recall the whole book.
- Because chapter numbers map to specific topics in About Face (personas, platform posture, excise, idioms, visual design, mobile, web, controls), the grouping below preserves that routing so an agent can jump to the right cluster for the problem at hand.

## Named patterns and principles

Grouped by topic cluster, each entry names the principle (near-verbatim, one sentence, as the book states it) and then the reasoning behind it in one added sentence.

### Foundations: mental models and process (Ch 1, 3, 4, 5)

- **"User interfaces should be based on user mental models rather than implementation models."** Users reason about a product in terms of what they think is happening, not the internal architecture, so interfaces that mirror the code's structure force users to think like programmers.
- **"Goal-directed interactions reflect user mental models."** Designing around what the user is trying to accomplish, not around the system's inner workings, is what keeps an interface aligned with how users already think.
- **"Interaction design is not guesswork."** Design decisions should trace back to research and reasoning about users and their goals, not personal taste or unexamined assumption.
- **"Don't make the user feel stupid."** Interfaces that expose internal complexity or blame the user for predictable mistakes erode trust and confidence, so design should absorb the complexity instead.
- **"Focus the design for each interface on a single primary persona."** Designing to please everyone at once produces a design that serves no one well, so pick one representative user whose needs anchor every decision.
- **"Define what the product will do before you design how the product will do it."** Behavior decisions belong upstream of visual and interaction detail, otherwise superficial choices lock in behavior that hasn't been thought through.
- **"In the early stages of design, pretend the interface is magic."** Imagining an ideal, friction-free response first (before worrying about feasibility) prevents technical constraints from prematurely shrinking the design's ambition.
- **"Never show a design approach you're unhappy with, stakeholders just might like it."** Presenting a weak option risks it getting chosen for the wrong reasons, so only bring forward work that meets the bar.
- **"There is only one user experience: form and behavior must be designed in concert."** Visual design and interaction design are not separable phases handed off in sequence, because a user experiences them as one thing at once.

### Product behavior and software manners (Ch 8)

- **"The computer does the work, and the person does the thinking."** Software should absorb repetitive, mechanical burden so the human's attention stays on judgment and decisions the machine cannot make.
- **"Software should behave like a considerate human being."** Politeness, deference, and taking responsibility for mistakes are traits users already expect from good assistants, and software that violates them feels hostile even if it is technically correct.
- **"If it's worth it to the user to do it, it's worth it to the application to remember it."** Forcing users to re-enter or re-configure things the system already learned wastes their effort for no benefit to them.

### Platform posture (Ch 9)

- **"Decisions about technical platform are best made in concert with interaction design efforts."** Platform choice shapes what interactions are even possible, so it cannot be settled purely as an engineering decision made before design starts.
- **"Optimize sovereign applications for full-screen use."** Sovereign apps (used continuously, all day) reward giving over the whole screen because users live in them for extended sessions.
- **"Sovereign interfaces should feature a conservative visual style."** Loud or novel visual styling becomes fatiguing and distracting across the long sessions sovereign apps are used for.
- **"Sovereign applications should exploit rich input."** Users of sovereign apps justify learning richer input methods (shortcuts, gestures, multi-step tools) because they will use them constantly.
- **"Maximize document views within sovereign applications."** The user's content, not chrome, is what deserves the screen real estate in an app used all day.
- **"Transient applications must be simple, clear, and to the point."** Transient apps are consulted briefly and infrequently, so users have no patience or memory investment for complexity.
- **"Transient applications should be limited to a single window and view."** Extra windows demand navigation and memory work disproportionate to the brief, occasional use transient apps get.
- **"A transient application should launch to its previous position and configuration."** Since sessions are brief and infrequent, resuming exactly where the user left off avoids re-orientation cost every time.
- **"Kiosks should be optimized for first-time use."** Every kiosk user is effectively a first-time user, so kiosks cannot rely on the learning curve that sovereign or daily-use software can.

### Learning curve and skill levels (Ch 10)

- **"Don't weld on training wheels."** Permanent beginner-mode scaffolding (that experienced users can't turn off) punishes the intermediate and expert users who make up most of actual usage over time.
- **"Nobody wants to remain a beginner."** Users move toward competence quickly and resent being treated as perpetual novices, so design for growth, not a fixed skill level.
- **"Optimize for intermediates."** Most usage, most of the time, comes from users who are neither brand new nor expert, so that middle group deserves the primary design investment.
- **"Inflect the interface for typical navigation."** Surface the paths users take most often, rather than treating every path through the interface as equally likely or equally important.
- **"Users make commensurate effort if the rewards justify it."** Users will learn a harder idiom only if the payoff clearly exceeds the learning cost, so complexity must be earned by real benefit.
- **"Imagine users as very intelligent and very busy."** This framing avoids two failure modes at once: condescending, dumbed-down design and design that assumes unlimited patience for reading and exploring.

### Simplicity, flow, and excise (Ch 11, 12)

- **"No matter how cool your interface is, less of it would be better."** Every added element competes for attention and adds potential confusion, so restraint is a design virtue in itself, not a compromise.
- **"Don't use dialogs to report normalcy."** Interrupting the user to confirm something routine succeeded treats a non-event as if it were significant, training users to dismiss dialogs reflexively.
- **"Ask forgiveness, not permission."** Default to letting the user act and offering an undo, rather than blocking action behind a confirmation, because most actions are not actually risky enough to warrant interruption.
- **"Eliminate excise wherever possible."** Excise is any work the interface demands that doesn't directly serve the user's goal, and removing it is close to pure win with little downside.
- **"Don't stop the proceedings with idiocy."** Interruptions the software could have avoided (a preventable error dialog, a needless confirmation) break the user's flow for no good reason.
- **"Don't make users ask for permission."** Requiring explicit authorization for routine, low-risk actions slows users down to guard against a problem that rarely occurs.
- **"Allow input wherever you have output."** If the system displays a value, letting the user edit it directly there avoids sending them elsewhere to make the same change.
- **"Significant change must be significantly better."** A redesign that unlearns established user habits has to deliver a large enough benefit to justify that relearning cost, or it's a net loss.

### Idioms and direct manipulation (Ch 13)

- **"Most people would rather be successful than knowledgeable."** Users care about getting the outcome, not about understanding the mechanism, so design should optimize for successful outcomes over transparency of process.
- **"Never bend your interface to fit a metaphor."** A metaphor is a teaching aid, not a constraint, and stretching real interaction design to preserve a metaphor's logic distorts function to fit form.
- **"All idioms must be learned, good idioms need to be learned only once."** Every interaction convention requires some learning investment, but a well-designed one pays that cost a single time and then generalizes.
- **"Rich visual feedback is the key to successful direct manipulation."** Direct manipulation (dragging, resizing, etc.) only feels direct if the interface visibly tracks and confirms every step of the manipulation in real time.
- **"Visually communicate pliancy whenever possible."** Showing which elements can be acted on, before the user commits to trying, prevents wasted attempts and hidden functionality.

### Errors and data integrity (Ch 14)

- **"An error may not be your application's fault, but it is your application's responsibility."** Regardless of whether the user or an external system caused a problem, the application is the one positioned to handle it gracefully.
- **"Audit, don't edit."** Prefer logging and letting the user review and reverse changes over silently and irreversibly altering their data.
- **"Save documents and settings automatically."** Manual saving is a legacy technical requirement, not a user goal, and users lose real work whenever software makes them responsible for remembering to save.
- **"Put files where users can find them."** File organization schemes that make sense to the underlying system, not the user's own mental model of their work, cause files to become effectively lost.

### Visual design and consistency (Ch 17)

- **"Visually distinguish elements that behave differently."** If two elements act differently, they should look different, otherwise users apply the wrong expectations from one to the other.
- **"Visually communicate function and behavior."** Appearance should hint at what an element does and how it responds, so users can predict behavior before interacting.
- **"Take things away until the design breaks, and then put that last thing back in."** Deliberately over-pruning and then restoring only what turns out essential is a reliable way to find the true minimum a design needs.
- **"Visually show what, textually tell which."** Icons and imagery communicate category or type fast, while text is better suited to naming the specific instance.
- **"Obey standards unless there is a truly superior alternative."** Platform and industry conventions carry learned expectations users bring from elsewhere, so deviating from them needs a real payoff, not novelty for its own sake.
- **"Consistency doesn't imply rigidity."** Following conventions is about matching user expectations, not about mechanically applying identical treatment where context actually differs.

### Menus, toolbars, and pointer idioms (Ch 18)

- **"The utility of any interaction idiom is context-dependent."** No idiom (menu, dialog, gesture) is universally right, its fit depends on the specific task and context it's used in.
- **"A dialog box is another room, have a good reason to go there."** Opening a dialog removes the user from their main context, so it should only happen when the detour is clearly worth the disruption.
- **"Provide functions in the window where they are used."** Keeping a function's controls in the same view as the content it affects avoids the excise of navigating elsewhere to use it.
- **"Use menus to provide a pedagogic vector."** Menus double as a discoverable inventory of what the application can do, teaching users its capabilities as they browse.
- **"Disable menu items when they are not applicable."** Graying out unavailable commands (rather than hiding or leaving them clickable) tells users what exists while preventing errors from invalid choices.
- **"Use consistent visual symbols on related commands."** Shared iconography across related functions helps users transfer recognition from one command to another.
- **"Toolbars give experienced users fast access to frequently used functions."** Toolbars trade discoverability for speed, serving users who already know what they want.
- **"Use ToolTips with all toolbar and iconic controls."** Icon-only controls need a text fallback for users who haven't yet memorized what each icon means.
- **"Support both mouse and keyboard use for navigation and selection tasks."** Different users and different moments favor different input methods, so restricting to one excludes real usage patterns.
- **"Use cursor hinting to show the meanings of metakeys."** Changing the cursor when a modifier key is held previews what effect that modifier will have before the user commits.
- **"Single-clicking selects data or an object or changes the control state."** This is the baseline convention users bring from every other interface, so it should not be repurposed for something else.
- **"Double-clicking means single-clicking plus action."** The second click should build directly on the first's selection, invoking the default action on what was just selected.
- **"Mouse-down over an object or data should select the object or data."** Selection should happen on press, not on release, matching how users expect immediate feedback from a press.
- **"Mouse-down over controls means proposing an action, mouse-up means committing to an action."** Separating propose from commit lets users cancel by dragging off the control before releasing, which is why this convention exists.
- **"The selection state should be visually evident and unambiguous."** Users need to always be able to tell, at a glance, exactly what is currently selected.
- **"Drop candidates must visually indicate their receptivity."** During a drag, valid drop targets should visibly signal that they will accept the dragged item, before the user releases.
- **"The drag cursor must visually identify the source object."** Keeping the dragged item's identity visible under the cursor reassures the user they are moving the thing they intended.
- **"Any scrollable drag-and-drop target must auto-scroll."** If a drop target can scroll, dragging near its edge should trigger automatic scrolling, or destinations outside the visible area become unreachable.
- **"Debounce all drags."** Small, likely accidental mouse movements should not register as a drag, since not every press-and-move is an intended drag gesture.
- **"Any program that demands precise alignment must offer a vernier."** Fine-grained input (snapping, precision adjustment) needs to be available whenever the task genuinely requires exact alignment.

### Mobile (Ch 19)

- **"Most mobile apps have transient posture."** Mobile use is typically brief and interspersed with other tasks, so mobile design should generally follow the transient-app principles, not sovereign-app ones.
- **"Limit the number and direction of animated screen transitions."** Excessive or inconsistent transition animation disorients users about where they are in the app's structure.
- **"Use guided tours to orient first-time users."** A brief, optional walkthrough on first launch can front-load orientation before the user has to rely on trial and error.
- **"Use overlays to explain gestures."** Gestures are invisible affordances, so an overlay hint the first time is often the only way users discover them at all.

### Web (Ch 20)

- **"Use persistent headers to maintain context."** Keeping navigation and identity elements visible while content scrolls or changes helps users stay oriented on a site.
- **"Breadcrumbs with lateral links help speed navigation."** Breadcrumbs that also let users jump sideways to siblings, not just upward to parents, cut down on backtracking.
- **"Auto-complete, auto-suggest, and faceted search help users find things faster."** Anticipating what a user is typing or looking for shortens the path to their goal.
- **"Make scrolling an engaging experience."** Since scrolling is a dominant web interaction, its pacing and feedback deserve deliberate design attention, not default treatment.
- **"Infinite scrolling and site footers are mutually exclusive idioms."** A footer becomes unreachable once content loads endlessly beneath it, so a site must choose one pattern or the other.
- **"If you have only one version of your site, make it responsive."** Maintaining a single, flexible layout that adapts to viewport avoids the cost and drift risk of maintaining separate device-specific versions.

### Controls and dialogs (Ch 21)

- **"Use links for navigation and buttons for action."** Keeping this distinction consistent lets users predict whether clicking something will move them or make something happen.
- **"Distinguish important text items in lists with graphic icons."** Icons let key items stand out from a dense list of text faster than typography alone.
- **"Avoid scrolling text horizontally."** Horizontal scrolling text is hard to read and easy to miss, so it should not be relied on to deliver information.
- **"Use bounded controls for bounded input."** When only a fixed set of values is valid, a control that only offers those values (like a dropdown) prevents invalid entries outright.
- **"Use noneditable (display) controls for output-only text."** Rendering read-only values as plainly not editable stops users from wasting effort trying to change something that can't be changed there.
- **"Put primary interactions in the primary window."** Core, frequent tasks belong in the main window rather than pushed into secondary dialogs that add navigation overhead.
- **"Dialogs are appropriate for functions that are out of the main interaction flow."** Reserve the disruption of a dialog for genuinely secondary or infrequent functions.
- **"Dialogs are appropriate for organizing controls and information about a single domain object or application function."** A dialog works best when it is scoped tightly to one coherent thing, not a grab-bag of unrelated settings.
- **"Use verbs in function dialog title bars."** A dialog that performs an action should be titled by that action, so users know at a glance what it's for.
- **"Use object names in property dialog title bars."** A dialog that edits a thing's properties should be titled by the thing itself, matching what the user is actually editing.
- **"Differentiate modeless dialogs from modal dialogs."** Users need a visual or behavioral cue for whether a dialog blocks the rest of the app or coexists with it, since the two demand different handling.
- **"Do not use terminating button commands for modeless dialogs."** Modeless dialogs stay open alongside other work, so buttons implying finality (like OK/Cancel that close everything) misrepresent how they behave.
- **"Don't dynamically change the labels of terminating buttons."** Buttons whose text changes based on context make it harder for users to build a reliable, automatic response to them.
- **"Inform the user when the application is unresponsive."** Silence during a long operation reads as a hang or crash, so the system should signal that it is still working.
- **"Never use transitory dialogs as error messages, alerts, or confirmations."** Messages that vanish on their own can disappear before the user reads them, so anything requiring the user's attention needs to persist until dismissed.
- **"All interaction idioms have practical limits."** Every idiom (tabs, menus, lists) degrades past some scale or complexity, and knowing that limit is part of choosing the idiom responsibly.
- **"Don't stack tabs."** Multiple rows of tabs are hard to scan and remember, so tab sets that grow that large need a different navigation idiom instead.
- **"Most error dialogs stop the proceedings with idiocy."** The typical error dialog interrupts the user to announce a problem the software could often have prevented or handled itself.
- **"Make errors impossible."** The strongest response to a class of error is to design the interaction so that error cannot occur at all, rather than just message it well after the fact.
- **"Users get humiliated when software tells them they failed."** Framing a problem as the user's failure (rather than the system's limitation) damages confidence for no functional benefit.
- **"Do, don't ask."** Where the intended action is reasonably clear, perform it directly and offer undo, instead of interrupting to ask for confirmation first.
- **"Make all actions reversible."** Reliable undo is what makes it safe to let users act freely and confidently, without needing to interrogate them before every step.
- **"Provide modeless feedback to help users avoid mistakes."** Ongoing, non-blocking feedback (a status message, an inline validation) can prevent an error before it happens, without stopping the user's flow.

## How to apply

- Use this list as a review checklist, not a spec. When designing or evaluating a screen or flow, scan the relevant cluster (platform posture, excise, errors, controls) and check each principle against the specific decision at hand.
- When a design choice conflicts with one of these principles, require a stated reason grounded in the actual user and context, "it looks better" or "it's technically simpler" is not a sufficient override.
- When naming an interaction pattern in a spec or PR description, use the book's own phrasing where it fits, it is a shared vocabulary other designers and reviewers will recognize.
- Default toward the excise-elimination and forgiveness-over-permission principles whenever a proposed interruption, confirmation, or dialog cannot point to a real, high-cost risk it's guarding against.
- Match interaction richness to platform posture first, decide whether a surface is sovereign, transient, or kiosk-like before deciding how much visual or interaction complexity it can support.
- Treat "make errors impossible" as the priority over "handle errors well", first ask whether the constraint, input control, or flow could remove the error case entirely.

## Watch out for

- These are compressed rules of thumb, several trade off against each other (for example, "less of it would be better" versus giving sovereign apps rich input), so apply judgment about which one dominates in the specific context rather than treating the list as an unconditional ranking.
- A rule stated for one platform posture (sovereign, transient, kiosk) can actively mislead if applied to a different posture, check which posture actually applies before reusing a principle from this list.
- Consistency with standards is a default, not an absolute, the book explicitly pairs "obey standards" with "consistency doesn't imply rigidity" so a genuinely superior alternative can still be worth the deviation.
- Confirmation dialogs and permission prompts are the most common violation pattern the book calls out repeatedly (idiocy, permission, transitory dialogs, dynamic button labels), review any interruption in a design for whether it is solving a real risk or just reflexive caution.
