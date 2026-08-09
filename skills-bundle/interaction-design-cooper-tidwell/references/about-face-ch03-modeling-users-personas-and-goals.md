# Modeling Users: Personas and Goals

Source: About Face: The Essentials of Interaction Design, 4th Edition (Cooper, Reimann, Cronin, Noessel, 2014), Chapter 3, "Modeling Users: Personas and Goals."

## In one line

Turn messy field research into personas, composite archetypes built from clustered behavior patterns and driven by explicit goals, so design decisions have a specific, prioritized human target instead of a vague, elastic "user."

## Core ideas

**Models exist to simplify, not to flatter.** A persona is a descriptive model, like an economist's market model, that keeps the salient behavior patterns and drops the noise. Notebooks full of interview transcripts are unusable directly. A model makes them actionable.

**Designing for everyone satisfies no one.** Broadening scope to please every constituency raises cognitive load and navigational overhead for all users, and features that please one group often annoy another. Pick specific individuals whose needs represent the needs of a larger group, then prioritize whose needs win when they conflict. This is why personas exist, to give the team a concrete, arguable target instead of an abstract mass market.

**Personas fix three recurring team failures:**
- The elastic user: without a specific persona, "the user" silently morphs to justify whatever the team already wants to build (a power user when convenient, a novice when convenient). Precision closes this loophole.
- Self-referential design: designers and developers unconsciously design for themselves or for people who think like them (including implementation-model thinking, where the interface just mirrors the internal data structure). A persona forces the design toward someone else's mental model.
- Edge cases: rare situations get overweighted because someone can imagine them. A persona lets you ask "would Julie ever actually do this?" and deprioritize accordingly.

**Personas work because they trigger empathy.** People engage with other people, not with feature lists or flowcharts. Treating a synthesized archetype as a specific named individual (a technique the authors compare to Method acting) makes designers and stakeholders care about a real experience, not an abstract spec. This is also why personas double as consensus and communication tools across a team, and why they get reused by marketing, sales, and support once built.

**Goals, not tasks, are the causal core of a persona.** Tasks are just the current means to an end, goals are the end. Understanding why someone does something lets you redesign or eliminate the task while still satisfying the goal. A "persona" with no goals attached is not a persona, it is a demographic profile wearing a costume.

**Goals must be inferred, not asked for.** People can't reliably self-report their own goals: they either can't articulate them, or answer inaccurately, or answer what they think sounds good. Reconstruct goals from observed behavior, incidental answers, nonverbal cues, and environmental clues, then state each goal as one simple sentence.

**Three types of user goals map to three levels of cognition** (drawing on Don Norman's visceral/behavioral/reflective model in *Emotional Design*):
- Experience goals (visceral, how the user wants to feel). Universal and simple ("feel smart and in control," "have fun," "stay focused") but easy for people to under-articulate, especially in business contexts. These drive visual design, motion, latency, tactile response, and micro-interactions. Violating them tanks satisfaction regardless of how well other goals are met, because the user disengages emotionally before anything else matters.
- End goals (behavioral, what the user wants to do). The outcome someone wants from using the product ("stay connected with friends," "get the best deal"). These are the primary driver of interaction design, information architecture, and functional industrial design, because behavioral processing is the level that both influences and is influenced by the other two.
- Life goals (reflective, who the user wants to be). Long-term aspirations and self-image ("succeed in my ambitions," "be respected by my peers") that explain why someone cares about their end goals at all. These rarely dictate a specific UI element but should shape strategy and brand. A product that visibly advances a life goal earns fanatical loyalty, not just satisfaction.

**Nonuser goals matter but must never override user goals.** Customer goals (the buyer, often not the user, for example an IT procurement manager or a parent), business and organizational goals (profit, retention, market share), and technical goals (browser support, data integrity, dev efficiency) all have to be acknowledged and satisfied, but only in ways that do not come at the user's expense. Technical goals in particular are meaningless as ends in themselves. They only matter insofar as they serve human goals.

**"Don't make the user feel stupid" is the master rule.** Users feel stupid when a product lets them make serious mistakes, blocks them from getting their work done, or bores them. The authors call this "probably the most important interaction design guideline" in the book. Good design satisfies the business and the user simultaneously. User dignity is not negotiable collateral for hitting a business or technical goal.

**Personas are built from a repeatable eight-step process, not improvised:**
1. Group interview subjects by role (job title for enterprise, lifestyle or attitude or family role for consumer).
2. Identify behavioral variables within each role: activities (what, how often), attitudes (toward the domain and technology), aptitudes (training, ability to learn), motivations (why they engage), skills. Typically 15 to 30 variables per role. Demographics are a weak signal here, behavior is the strong one.
3. Map each interviewee onto every behavioral variable as a relative position (precise placement doesn't matter, relative clustering does).
4. Find clusters that recur across roughly six to eight variables at once, that's a candidate persona. A cluster is only valid if there's a logical or causal link between the co-occurring behaviors, not a spurious correlation (people who buy CDs online and also download MP3s, that's logical, people who buy CDs online and are also vegetarian, that's probably noise).
5. Synthesize characteristics and goals for each pattern: behaviors and their motivations, use environment, pain points with current solutions, demographics, skills, attitudes, relevant relationships with other people or products, and existing workarounds. Add a name at this stage (evocative but not stereotype-heavy) and refer to the persona by name from then on. Most personas end up with three to five end goals, zero or one life goal, and zero to two explicit experience goals (generic ones like "don't feel stupid" and "don't waste time" are implicit for every persona and don't need restating).
6. Check completeness and redundancy: fill any behavioral gaps with more research if needed, and merge or differentiate personas that only differ by demographics, not behavior. Every persona must differ from every other by at least one significant behavior.
7. Designate persona types (see named list below), picking exactly one primary persona per interface.
8. Expand into a one-to-two-page third-person narrative that operationalizes the bullet-point characteristics into something a team can empathize with and design against.

**Ranges, not averages.** A persona represents an exemplary point within an observed range of behavior, not a statistical mean. Never assign a persona fractional or averaged demographic values (like "1.5 kids"), those belong to market segments, not to an individual.

**Personas differ from market segments and user profiles.** Market segments are built on demographics, channels, and purchase behavior for the sales process. Personas are built on usage behavior and goals for the product-definition process. Market segments can bound who you interview, but they rarely map one-to-one to personas. A "user profile" that is just a name, photo, and demographic paragraph is not a persona, the giveaway is the absence of goals.

**Stereotypes are the failure mode to avoid, not the goal.** Personas synthesized from thin research or without empathy for interview subjects degrade into caricatures. When data is inconclusive or a trait doesn't matter to the design, default toward demographic diversity (gender, ethnicity, age, geography) rather than toward a convenient stereotype.

## Named patterns and principles

- **The elastic user**: the failure mode where "the user" silently stretches to justify whatever a team already wants to build. Avoid it by naming a specific persona early and holding the team to it.
- **Self-referential design**: designers projecting their own goals, skills, and mental models onto the product. Watch for it whenever a design decision is justified by "well, I would...". Counter it with persona goals drawn from research, not intuition.
- **Implementation-model products**: software shaped by internal data or technical structure rather than user goals, a developer-flavored variant of self-referential design.
- **Edge cases**: rare situations that must be handled but should never drive the primary design. Use the persona as a reality check ("would she ever do this?").
- **"Don't make the user feel stupid"**: the chapter's headline design guideline. Apply it as a veto check on every feature. Does this risk a serious mistake, block productivity, or bore the user?
- **Archetypes vs. stereotypes**: an archetype is a composite of real observed behavior treated with respect. A stereotype is an assumption dressed up as a persona. Use archetypes, and if a trait isn't backed by data, don't invent color for it.
- **User role or role model** (Constantine and Lockwood, also used by Agile and by Holtzblatt and Beyer's contextual design): an abstraction of a class of users as a list of attributes, without narrative or empathy. Cooper's critique: roles neglect goals as an organizing principle, are hard to empathize with in the abstract, and oversimplify real variation (two people with the same job role can behave completely differently, a "car buyer" role tells you nothing useful). Personas are Cooper's answer to this limitation, not a synonym for it.
- **Participatory design (bringing real individual users into the process)**: seems more "true" politically, but is a trap. An individual carries idiosyncratic behavior that isn't representative, so designing straight off one real person risks missing behaviors common across the broader user base. Personas exist precisely to separate the common signal from individual noise.
- **Persona types** (six, roughly in this priority order):
  - Primary: the one persona per interface the design must fully satisfy. A product can have multiple primary personas only if it has multiple distinct interfaces (common in enterprise and technical products). If no clear primary emerges, either split into multiple interfaces or the product's scope is too broad.
  - Secondary: mostly satisfied by the primary's interface, with a few extra needs bolted on without disturbing the primary. More than three or four is a scope-creep warning sign.
  - Supplemental: fully covered by the combination of primary and secondary personas. Often absorbs "political" personas added to satisfy stakeholder assumptions.
  - Customer: represents the buyer rather than the end user (parent, IT procurement). Usually treated like a secondary persona, occasionally primary for its own admin interface.
  - Served: affected by the product without directly using its interface (for example, a radiation-therapy patient). Tracks second-order social and physical consequences, treated like secondary.
  - Negative (anti-persona): explicitly who the product is NOT for (early-adopter power users for a mass-market consumer product, criminals, trolls, IT specialists on a business-user tool). Purely rhetorical, used to keep the team from drifting toward serving the wrong audience.
- **Provisional ("ad hoc") personas** (term from Don Norman): stand-ins used when there's no time or budget for real fieldwork, built from stakeholder or SME knowledge and existing market data. Better than no user model, but must be clearly labeled as provisional (first names only, sketches instead of photos), documented for what data and assumptions back them, and swapped for real personas once research is possible. Risk: locking onto the wrong target, missing differentiating behaviors, or discrediting personas org-wide if the provisional shortcut is later exposed as guesswork.
- **Organizational "personas"**: a lighter parallel construct describing the behavior, rules, and structure of an organization a persona belongs to (a small business versus a multinational), useful when the organization's own norms shape the individual persona's behavior.
- **Persona affinity survey**: an optional quantification method for skeptics who want market-size numbers. Build multiple-choice questions off your behavioral variables, survey a properly sized sample, score each respondent against the persona whose behaviors they match most, then divide by total respondents to get percentage affinity per persona. It's a secondary validation layer, not a replacement for qualitative synthesis.
- **Work flow or sequence models** (per Holtzblatt and Beyer's Contextual Design): flowcharts capturing organizational process goals, triggers, dependencies, roles, decisions, and error handling. Useful supplement to personas for capturing cross-person or organizational flow that a single persona narrative can't hold. Over-relying on workflow alone reproduces the same "implementation model" trap as designing straight from database structure, functionally complete but inhuman.
- **Artifact models**: capture the forms and artifacts (paper or digital) people use in their tasks, useful for extracting best practice, but a straight digital port of a paper artifact without re-applying goal analysis usually creates new usability problems.
- **Physical models**: capture spatial layout of a user's environment (hospital floor, assembly line). Useful when the environment itself constrains frequency-of-use and workflow, beyond what a persona narrative can convey.

## How to apply

- Never ship a "persona" without at least one end goal attached. If it has no goals, treat it as a profile, not a design tool, and go back to research.
- Base personas on direct interviews and observation first, treat stakeholder input, focus groups, market segments, and literature review as supplemental, in that order of trustworthiness.
- Build personas per product, not once for a whole product suite. Behavior in one context does not transfer to another even for closely related products.
- Run the eight-step construction process in order: group by role, list behavioral variables, map interviewees onto them, cluster into patterns, synthesize characteristics and goals, check for gaps and redundancy, assign persona types, then write the narrative.
- Cap each persona at roughly three to five end goals, zero to one life goal, zero to two explicit experience goals. Leave "don't feel stupid" and "don't waste time" implicit.
- Pick exactly one primary persona per distinct interface before designing anything. If you can't, either split the interface or narrow product scope.
- When resources don't allow real research, build clearly labeled provisional personas from best available data rather than skipping user modeling entirely, and replace them with researched personas as soon as possible.
- When a business, technical, or customer requirement conflicts with a primary persona's goal, find a way to satisfy both. Do not silently sacrifice the user's goal.
- Keep the persona narrative to one or two pages, grounded entirely in observed behavior, with no design solutions embedded in it and no invented detail beyond what the research supports.
- Use negative personas explicitly in team discussions to rule out audiences the product should not chase, especially when stakeholders keep pulling scope toward a poor-fit user type.

## Watch out for

- Don't confuse a demographic profile (name, photo, job title, a paragraph of trivia) for a persona. The diagnostic test is whether it has goals.
- Don't let personas with business or social relationships to each other become a straitjacket. It's tempting to bend every scenario to fit one convenient social dynamic, but diverse, independently grounded personas produce better design than a tidy but distorted single dynamic.
- Don't over-embellish with fictional biography, quirky backstory, or lavish photo collages to the point that personas feel like a character-sketch exercise rather than a decision tool. Excess theater invites the "personas are fluffy" critique and undermines their credibility.
- Don't cite ranges or averages as persona details (no "1.5 kids," no salary bands), pick one concrete value if the detail matters at all.
- Don't treat "people don't think in tasks" as a reason to discard personas and goals altogether. The fix is to state the goal correctly (for example, "stay caught up on what's happening"), not to abandon goal-driven design.
- Don't demand that every persona trait trace to one specific interviewee's exact words. Traceability applies to the pattern across research, not to a single quote.
- Don't assume your primary persona must represent the largest market segment. The OXO Good Grips example shows that designing for the most-constrained user (arthritis sufferers) can satisfy the broad market better than designing for the statistical majority.
- Don't let technical or business goals dictate the interface. They must be satisfied in service of user goals, not instead of them.
