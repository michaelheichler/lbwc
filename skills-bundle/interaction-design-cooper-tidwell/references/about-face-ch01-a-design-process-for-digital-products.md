# A Design Process for Digital Products

Source: About Face: The Essentials of Interaction Design, 4th Edition (Cooper, Reimann, Cronin, Noessel, 2014), Chapter 1.

## In one line

Digital products fail users not because of bad technology but because of a missing design discipline, and Goal-Directed Design fixes this by building every decision on a systematic understanding of what users are actually trying to accomplish.

## Core ideas

- Design means using knowledge of user needs, business constraints, and technical constraints to define a product's form, content, and behavior so it is useful, usable, desirable, viable, and feasible. Interactive products are distinct from other design objects because behavior, not just form or content, dominates the user's experience.

- Poorly designed digital products commonly show four failure patterns: they are rude (blaming and interrogating users for the product's own failures), they force people to think like a computer instead of adapting to how people already think, they have sloppy habits (forgetting context, losing state, asking redundant questions), and they push manual busywork onto humans that the software should handle itself. These are symptoms of the same root cause. Design was never a real input to construction.

- Four structural reasons explain why digital products fail. First, misplaced priorities. Marketers hand over feature checklists built from competitive pressure and guesswork rather than real user need, and developers, who make the final calls under deadline pressure, optimize for buildability over usability. Second, ignorance about real users. Demographic and market data does not reveal how people actually behave with a product or why. Third, a structural conflict of interest. The people who build a product are frequently also the people deciding its design, and no one can simultaneously advocate for users, business, and engineering with equal weight. Fourth, the absence of a repeatable process that turns user understanding into design decisions, as opposed to engineering process (which exists) and business process (which exists).

- Feeding customer or domain-expert opinions straight into design is a common but flawed substitute for a real process. Users can describe symptoms of a bad interaction but usually cannot design the fix, just as a patient can describe pain but should not dictate the surgery. Domain knowledge is not design knowledge. Treat user and stakeholder input as diagnostic data, not as proposed solutions to implement literally.

- Three forces must all be satisfied for a product to succeed long-term: capability (what can be built, driven by technology), viability (what sustains the business), and desirability (what people actually want, driven by design). Weakness in any one undermines the whole product, no matter how strong the others are. Companies that neglect desirability (heavy on capability or viability alone) become vulnerable even when otherwise well run.

- There are three distinct "models" at play in any digital product, and confusing them is the core interaction design problem. The implementation model is how the software actually works internally (code, data structures, algorithms). The user's mental model is the simplified, often technically inaccurate picture a person carries in their head of how the thing works, built from experience and intuition, and it stays simple even when reality is complex. The represented model is what the designer chooses to show the user, the "face" put on the underlying implementation. Because software can represent itself as almost anything (unlike physical mechanisms), designers have far more freedom, and far more responsibility, in shaping the represented model than in most other design disciplines.

- Since people naturally form mental models that are simpler than reality, the represented model should also be simpler than the implementation model, not a mirror of it. Interfaces that expose implementation details (a control for every internal variable, a screen for every code module) force users to think like the machine and are unnecessarily hard to learn and use. Interfaces that instead match how the user already thinks about their task drastically reduce the cognitive burden of using the product.

- Goals are not the same as tasks or activities. A goal is a desired end state, while tasks and activities are just the intermediate steps used to get there, and those steps change constantly as technology changes. Goals change slowly, if at all, because they are rooted in stable human motivation. The chapter's own example. a traveler's goals (fast, comfortable, safe travel) stayed the same from covered wagon to jet plane even though every task involved changed completely. Designing to goals lets you strip away tasks that better technology makes unnecessary. Designing to tasks alone locks you into whatever the old technology required.

- Personal goals sit underneath professional or task-level goals and usually dominate them. An accounting clerk's real goal is rarely "process invoices efficiently," that is the employer's goal, it's more likely to feel competent and stay engaged doing repetitive work. Products that serve only business goals and ignore the human's personal goals will underperform, while products that satisfy personal goals tend to deliver the business goals too, as a side effect.

- Ease of learning is not a universal design target. What to optimize for depends on context. who the user is, what they are doing, and their goals. A call-center system used all day by trained employees should optimize for throughput over walkthrough-style hand-holding, while a public information kiosk used once by strangers should optimize hard for first-use learnability. Apply the goal "make users more effective" as the general default for productivity tools, since it captures both the universal goal of not looking or feeling stupid and the situational goals of speed and ease.

- Look past the task to find the goal behind it. A data-entry job well executed still fails the user if the real goal (getting names into a database) could be met without any manual entry at all, for instance by extracting them automatically from another system. Optimizing the task the user was handed can miss a much better solution that removes the task entirely.

- Interaction design is a systematic, teachable discipline, not aesthetic guesswork or a personal creative whim. Because it rests on understanding of users and cognitive principles, it supports a repeatable process of analysis and synthesis, the same way engineering and business planning do. This is what makes the Goal-Directed process possible, and defensible, when explaining design decisions to developers and stakeholders.

- The historical development process (research handled by market analysts, design handled by visual or graphic specialists, with no connection between them) leaves a translation gap. Research output doesn't turn into design decisions on its own. Bridging that gap requires designers to be involved directly in research, not handed a summary afterward. Direct exposure to users builds empathy, an understanding of what users feel, which secondhand research reports cannot substitute for. Isolating designers from users is called out as one of the more damaging practices in product development, because it strips out that empathic knowledge.

## Named patterns and principles

- **Goal-Directed Design**: the overall six-phase process (Research, Modeling, Requirements Definition, Framework Definition, Refinement, Support) that ties user research through to a shipped product by centering every decision on user goals rather than tasks or feature lists. Use it as the top-level process for any product design effort with meaningful behavioral complexity. It works because it makes design a systematic, arguable process instead of ad hoc guesswork, so decisions can be justified to both business and engineering stakeholders.

- **Implementation model, mental model, and represented model**: three distinct pictures of "how the product works" that a designer must keep separate. The implementation model is the actual internal mechanism, the mental model is the user's simplified internal picture, the represented model is what the interface actually shows. Use this distinction whenever deciding how to expose (or hide) internal complexity. It works because the represented model is the only one of the three fully under the designer's control, and closing the gap between it and the user's mental model is most of what makes software feel intuitive.

- **Goals versus tasks and activities** (echoing, and going further than, Donald Norman's Activity-Centered Design): treat goals as the stable "why," and tasks or activities as the volatile "how," which change with available technology. Use this distinction to decide what to keep and what to eliminate. It works because task-based design only ever produces incremental improvement and risks freezing the product around outdated technology, while goal-based design lets new technology eliminate whole categories of task.

- **Capability, viability, desirability** (the product-development triad, credited to Larry Keeley of the Doblin Group): a product needs all three (buildable, sustains a business, and wanted by people) to succeed long-term. Use it as a sanity check on a product strategy. It works because each leg is produced by a different discipline (technology, business, design) and no single discipline can compensate for a collapse in another.

## How to apply

- Before writing specs or code, run (or insist on) the Research through Modeling through Requirements through Framework Definition through Refinement through Support sequence, in that order, don't skip straight to framework or UI decisions.
- When gathering input from users, stakeholders, or domain experts, record it as a description of problems and context, not as a literal solution to implement. Ask "why" until you reach a goal, not just a requested feature.
- For every persona or user type in scope, explicitly separate their personal goals (feel competent, not look stupid, stay engaged) from their task-level and business-level goals, and design first for the personal goals.
- When deciding what an interface should expose, ask what the user's existing mental model of the task is, and represent the product's behavior in those terms rather than in terms of the underlying implementation (data structures, internal states, code modules).
- Before optimizing a given task or workflow, ask whether the task itself is even necessary anymore, given current technology, rather than only making the existing task smoother.
- Set the design target (learnability vs. throughput vs. depth for experts) based on actual usage context (who, how often, how experienced), never as a universal default.
- Keep whoever does design work exposed directly to real users and research, rather than handing them a secondhand research report, to preserve empathic understanding of the user's situation.
- Keep design decision-making structurally separate from the people solely responsible for construction deadlines, to avoid the ease-of-coding vs. ease-of-use conflict of interest.
- When justifying a design decision to engineering or business stakeholders, trace it back to a specific user goal rather than presenting it as aesthetic preference.

## Watch out for

- Do not mistake "ease of learning" for a universal virtue. In some contexts (expert daily-use tools, throughput-critical systems) heavy walkthroughs and hand-holding actively frustrate experienced users.
- Do not treat customer or domain-expert requests as ready-to-build design solutions. They are diagnostic input, and taking them at face value repeats the mistake of confusing domain knowledge with design knowledge (the reason law and medicine software has a bad usability reputation, per the chapter).
- Do not let a represented model creep toward mirroring the implementation model out of engineering convenience (a control per internal variable, a screen per backend transaction). This directly increases the gap to the user's mental model and increases learning difficulty.
- Do not let "design" collapse into a late-stage visual facelift applied after behavior is already locked in by code. If a product's behavior is decided by construction rather than a genuine design phase, no amount of surface polish fixes it, "lipstick on the pig" is the chapter's own phrase for this outcome.
- Do not let the same team or person carry both the design and construction decisions with no check on each other. The chapter compares this to letting a prosecutor also serve as the judge.
- Watch for goals disguised as tasks. if a stated "goal" changes as fast as the surrounding technology does, it's actually a task or activity, not a true goal.
