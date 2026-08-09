# Digital Etiquette

Source: *About Face: The Essentials of Interaction Design*, 4th Edition (Cooper, Reimann, Cronin, Noessel, 2014), Chapter 8, "Digital Etiquette."

## In one line

People unconsciously treat interactive software like a social actor, so design it to behave like a considerate, smart, socially fluent human colleague rather than a rude, forgetful, or intrusive machine.

## Core ideas

**Software is a social actor, whether you intend it or not.** Research (Nass and Reeves, *The Media Equation*) found that people apply the same instincts for judging other people to anything that behaves interactively enough, including software. This reaction is unconscious and automatic. The design implication: the "personality" a product projects (competent and helpful, or nagging and evasive) is not incidental, it directly shapes whether users like and trust the product.

**Division of labor: the computer does the work, the person does the thinking.** Humans excel at pattern recognition, judgment, and creative problem solving. Computers excel at storing, retrieving, and processing information tirelessly. Design should route drudge work (remembering, computing, watching for patterns) to the software and preserve decisions and judgment calls for the human. Chasing "artificial intelligence" that tries to think for the user is usually the wrong ambition, the more useful and shippable ambition is software that works harder on the user's behalf.

**Considerate beats merely polite.** Politeness is surface courtesy ("please," "thank you"). Considerate software looks out for the user's goals and needs, even when that means restructuring how it behaves, not just how it phrases things. A product can be cute and polite while still being stingy with information, opaque about its processes, and quick to blame the user, and that combination still produces a bad experience.

**Remembering is a core act of consideration.** Software has far greater capacity to retain detail than a human, yet most products discard everything between sessions, treating user input as disposable query parameters rather than durable facts about a person. Every fact a user bothered to establish is worth persisting. Forgetting things the user already told the system is one of the most common and avoidable ways products act inconsiderate.

**Deference means the user outranks the software.** The system can advise, warn, and explain consequences, but final authority belongs to the person, not the interface. A product that blocks, judges, or overrides a user's explicit choice is stepping out of its proper role. The word "submit" itself signals a broken power relationship: users should not have to submit to their tools.

**Forthcoming means volunteering relevant adjacent information, not just answering the literal question asked**, the way a good salesperson mentions a better-priced alternative unasked. The challenge is calibrating this without becoming Clippy-style intrusive: know when to volunteer help and when to stay out of the way, the way a good waiter refills a glass without interrupting conversation.

**Common sense means not placing rarely-used, high-risk controls next to safe, frequent ones**, and means noticing when output looks absurd (a bill for $957 million) rather than mechanically processing it. Considerate systems have a baseline plausibility check on their own output.

**Discretion means some information should NOT be remembered by default** (credit card numbers, passwords, tax IDs) unless the user explicitly opts in, and the product should proactively help protect what it does hold (secure password guidance, alerts on suspicious access).

**Anticipating needs means using idle time productively**, for example a browser preloading visible links while the user is still reading, so that the eventual request feels instant. It's cheap to discard an unneeded speculative result, but expensive to make the user wait for one requested cold.

**Conscientiousness means seeing the larger goal behind a task, not just the literal instruction.** A conscientious assistant handling a file-naming collision resolves the underlying ambiguity (renaming both files sensibly) rather than mechanically completing the narrow action (just filing it, or forcing an overwrite or discard choice). Software that only offers "overwrite or cancel" on a naming collision is less capable than even a mediocre human assistant would be.

**Don't burden users with the system's internal problems.** Users don't want status reports about disk cleanup uncertainty, save confirmations that state the obvious ("Document Successfully Saved!"), or other machine-centric noise. The system should resolve its own operational uncertainty quietly and only surface what matters to the user's goals.

**Keep users informed via passive, ambient (modeless) feedback, not interruption.** The bartender who posts prices on a chalkboard rather than announcing them to every customer is the model: information sits in plain view for whoever needs it, without demanding attention.

**Perceptiveness means noticing patterns across time and updating behavior**, for example if a user checked inventory once, they will likely want it again soon, so keep watching and surface changes proactively rather than only answering discrete queries in isolation.

**Self-confidence means not asking "Are you sure?" for actions the user just explicitly requested.** If uncertainty is warranted, the correct response is to make the action safely reversible (offer undo) rather than interrogate the user's intent before letting them proceed.

**Questions disempower, choices don't.** Being asked a question implies the asker has authority over the person answering (subordinate answering to a superior), which is why interrogation-style dialogs feel demeaning even when the content is trivial. Being offered a choice (browsing a store) feels empowering by contrast. Excess questions also signal the product is ignorant, forgetful, weak, fretful, lacking initiative, and overly demanding, traits nobody wants in a colleague either.

**Fail gracefully instead of destructively.** When something goes wrong, considerate software preserves what it can (writing incoming data to local disk before acknowledging receipt to a remote source, using an undo cache to survive crashes) rather than discarding valid user work along with the failure. On the web, rejecting a form because of one bad field should never also discard the other correctly-filled fields.

**Know when to bend the rules (fudgeability).** Manual, human-run systems have an unspoken intermediate state, "suspense," where a transaction is accepted before it's fully complete, and a human can quietly patch gaps later. Automated systems typically only recognize two states: nonexistent or fully compliant, with no fudge room. This rigidity turns the system into an adversary of the humans who must work around it, and paradoxically increases the chance of catastrophic failures because minor accommodations that would have prevented bigger problems are disallowed.

**Take responsibility for the full chain of an action**, including work handed off to subordinate hardware or services. If a user cancels a print job, the application should ensure that cancellation is honored downstream (in the printer buffer), not just claim success while pages keep printing. Passing blame to "the hardware" or another component is not acceptable from the user's point of view, since the user only sees one system.

**Help users avoid awkward, hard-to-undo social mistakes**, like replying to the wrong group or forgetting a mentioned attachment, through gentle, modeless, in-context feedback (highlighting an empty attachment area) rather than a blocking, scolding modal error.

**"Smart" for a shippable product means working harder with available cycles, not general intelligence.** CPUs sit idle almost all the time between user actions (a user "thinking" for a few seconds wastes roughly a billion CPU instructions). The old objection "we can't assume, the assumption might be wrong" is now largely moot: modern hardware has power to spare to compute several speculative answers and discard the wrong ones once the user's real choice is known.

**Task coherence: what a user did before predicts what they'll do again.** Human behavior is not random even though it isn't deterministic. This licenses using history as a default rather than re-asking every time (a user who reliably uses 12-point Helvetica shouldn't have to re-specify it).

**"If it's worth it to the user to do it, it's worth it to the application to remember it"** (a directly quotable rule of thumb). Storage cost for remembering user actions is trivial (a year of usage notes might total a couple of megabytes), so the excuse of storage overhead rarely holds.

**Remember more than just file locations, remember locations per file type**, window positions and sizes, and deducible secondary facts like typical size of edits to a file, so anomalies (an unexpected jump in the amount changed) can be flagged for a safety-net backup copy without an interrupting confirmation dialog.

**Multi-session undo**: persisting the undo stack across application restarts (even a week later) rather than discarding it on close is a low-effort, high-value form of memory.

**Mostly right, most of the time beats a redundant dialog every time.** If a prediction from memory is correct 80 percent of the time, asking a confirming question every time annoys users 80 percent of the time to protect against the remaining 20 percent, when a good undo mechanism handles that 20 percent more cheaply and with less friction overall.

**Social software must distinguish social norms from market norms**, and the two must not be mixed. Social norms are the unspoken reciprocity of friends and family. Market norms are the unspoken assurances of fair dealing between businesses and customers. Applying market norms in a social context reads as crude (offering money after a friend's dinner), applying social norms in a market context can be inappropriate or even illegal (thanking a waiter warmly and walking out without paying). A given platform must figure out which norm set its users are operating under, since the same feature (a connection request) can carry different implied obligations depending on context.

**Letting users present their best side matters in identity design.** Real names aren't always unique or compact. Semi-random assigned avatars reduce the designer's burden but add cognitive load (users must now remember who's behind an icon). Letting users choose or upload their own representation removes that burden while adding a moderation cost that opt-in, accountable communities can usually absorb.

**Dynamic profiles (aggregated activity) can substitute for or supplement static self-description**, since actions (what was shared, liked, listened to) often say more about a person than a filled-out bio field, and cost the user nothing to maintain.

**Collaboration features should model how people resolve discussions in practice**, not just bolt commenting onto a document. Threaded replies, an explicit "resolve" action, and the ability to reopen a resolved thread fit real collaborative work better than a flat, easily-tangled comment stream.

**Social products must know when to shut the door.** Even primarily social features embedded in a productivity tool should never overwhelm the primary task with interruption (a blinking alert that a collaborator joined), and users need an explicit, respected way to suspend social visibility while they focus.

**Networks need lifecycle support**, ways for new members to discover and learn norms, gentle correction when norms are violated, tools for established members to mentor and manage, and graceful ways to pause participation, leave, or (soberly) handle a member's death. Ignoring the lifecycle produces networks that are confusing to join and awkward to leave.

**Face-saving mechanisms for one-sided social requests.** When one party doesn't want a connection but doesn't want to signal rejection (an intern requesting to connect with a CEO), routing the decision through neutral community rules, a designated gatekeeper, or a system constraint lets the reluctant party decline without personally delivering the rejection.

**Respect the limits of social network scale.** Privacy, collaboration, and complexity management all need to scale relative to real human social capacity, not just technical capacity.

**Respect user privacy proactively, not just legally.** Businesses whose revenue model depends on exposing more user data have a structural incentive to erode privacy defaults. Considerate design makes any expansion of sharing an explicit, well-explained, opt-in choice, since surprise exposure of previously-private activity is one of the most trust-destroying failures a social product can commit.

**Anti-social behavior (griefing) needs dedicated tooling.** Anonymous, low-accountability large networks attract users who deliberately disrupt transactions or conversations. Products need tools for individual users to silence abusers, tools to exclude them categorically, and tools to escalate to community moderators, while being careful to distinguish deliberate griefing from users who are simply unpopular or disagreeable but acting in good faith.

## Named patterns and principles

- **The considerate product characteristics** (a checklist Cooper treats as load-bearing): takes an interest, is deferential, is forthcoming, uses common sense, uses discretion, anticipates needs, is conscientious, doesn't burden the user with its own problems, keeps the user informed, is perceptive, is self-confident, doesn't ask a lot of questions, fails gracefully, knows when to bend the rules, takes responsibility, helps avoid awkward mistakes. Use this as an audit checklist against any interaction: run a proposed flow through each trait and flag violations.

- **Fudgeability**: the property of manual systems that lets a human accept a transaction before all prerequisites are formally satisfied, using an informal "suspense" state. Use it as a design goal when a rigid required-field or required-sequence rule is fighting real-world workflow, build in an intermediate, provisional state instead of forcing all-or-nothing compliance. It works because it lets small, correctable gaps in, which prevents the bigger failures that arise when users are forced to route around a rigid system entirely.

- **Task coherence**: the principle that a person's goals and how they pursue them are similar day to day, which is why remembering past behavior reliably predicts future behavior. Use it to justify defaulting to the user's prior choice instead of asking again. It works because human behavior, while not deterministic, is rarely random.

- **Decision-set reduction**: people narrow a large space of choices to a small habitual subset without deliberate thought, a handful of favorite restaurants, a handful of driving routes. Use it to design memory that tracks a short list of recent or frequent choices rather than only the last choice made, especially where the working set has exactly two alternating members (remembering only the most recent choice is guaranteed wrong half the time in that case). It works because it matches how people behave in day-to-day life, not an idealized single "the" choice.

- **Preference thresholds**: the observation that of the many decisions embedded in any task, only a few are ones the user cares about, the rest are noise to them. Use it to decide which choices deserve a visible control and which should just be set silently from a sensible default or prior behavior. It works because asking about a decision the user doesn't care about wastes their attention without giving them anything they value.

- **Mostly right, most of the time**: the design rule that when a prediction is right most (but not all) of the time, act on the prediction and provide undo, rather than asking a question every time to guard against the minority of wrong guesses. It works because it trades a small number of undo actions for eliminating a much larger number of interruptions.

- **Social norms vs. market norms**: two distinct, mutually exclusive rule sets governing reciprocity (friends and family) versus commercial fairness (transacting parties). Use it to diagnose which register a given social feature operates in, and to avoid designing interactions that blend the two (a professional network that feels transactional when users expect warmth, or a marketplace that feels exploitative because it borrows social-trust cues without market-level accountability).

- **Dunbar's number**: a cognitive limit (roughly 150) on the number of social relationships a person can maintain in a stable, meaningful way, attributed to anthropologist Robin Dunbar and grounded in neocortex-size research across primates. Use it as a threshold check when designing any social network feature. If the network structure allows a user's connections to exceed this range, it will destabilize under normal use unless the product supplies explicit organizing rules or dedicated tools for managing that complexity.

## How to apply

- Before finalizing any interaction, run it against the considerate-product checklist (interest, deference, forthcomingness, common sense, discretion, anticipation, conscientiousness, self-containment, informativeness, perceptiveness, confidence, few questions, graceful failure, fudgeability, responsibility, mistake prevention) and name which traits it violates.
- Persist every fact a user establishes across sessions by default (last folder used per file type, last format chosen, last window position, past entries) unless it is sensitive (credit cards, passwords, tax IDs), which requires explicit opt-in to remember.
- Replace confirmation dialogs on explicit user commands with reversible actions (undo) instead of "Are you sure?" interrogation.
- Convert generic settings and config screens into learned defaults: track what a user changes and apply their prior choice automatically rather than resetting to a hardwired default or asking again.
- Where a rigid required-field or required-order rule blocks a plausible real-world case, add an explicit provisional or incomplete state rather than forcing full compliance or outright rejection.
- Use idle compute time (between user actions) to precompute or prefetch likely next steps (search indexing, preloading links) instead of leaving the system idle until the next explicit command.
- When a workflow fails partway, preserve everything the user has already validly entered, never let one bad field discard nine good ones.
- Replace blocking modal warnings for likely-but-reversible mistakes with modeless, in-context cues (highlighting a missing attachment) that don't stop the user's flow.
- Give users an explicit way to mute or pause social visibility and interruptions in software that is social but not primarily social.
- Design identity representation to let users supply or choose their own visual or identity marker rather than assigning one, to avoid adding a "who is this icon" memory burden.
- Route one-sided social decisions (someone wants to connect, the other doesn't) through neutral rules or a designated gatekeeper so neither party has to personally deliver a face-losing rejection.
- Check any social feature's target network size and its permission model against real social-cognitive limits (roughly Dunbar's 150), and add explicit grouping, moderation, or role tools once a network can plausibly exceed that scale.
- Treat any policy change that increases exposure of previously-private user data as requiring explicit, well-explained opt-in, never a silent default flip.
- Build layered anti-abuse tooling for any social product with low-friction account creation: user-level silencing, categorical exclusion, and escalation to moderators, with a way to distinguish genuine abuse from unpopular-but-legitimate participation.

## Watch out for

- Don't confuse politeness (saying "please") with actual consideration (restructuring behavior around the user's goals). A cute, polite product that hoards information and blames the user is still a bad product.
- Don't build a Clippy: unsolicited "helpful" interruptions that can't read context (mid-task, mid-conversation) are worse than saying nothing. Know when to withhold and when to volunteer.
- Don't ask users to confirm actions they just explicitly requested, that's the opposite of self-confidence and reads as insecurity, not caution.
- Don't rely on remembering only the single most recent choice when the real decision set alternates between two or more options, that guarantees being wrong at a predictable rate.
- Don't treat "we can't assume, the assumption might be wrong" as a permanent excuse to avoid speculative background work. Modern compute has enough headroom to make several guesses and discard the wrong ones.
- Don't let a component blame another component (app blames hardware, app blames the network) for a failure the user only experiences as one system failing them.
- Don't mix social and market norms on the same feature, users can find market behavior in a social space rude, and social behavior in a market space can carry real (even legal) risk.
- Don't let a social product silently expand what is exposed or shared, unexplained policy shifts toward more exposure are one of the fastest ways to alienate a user base.
- Don't ignore network lifecycle needs (onboarding, norm violation correction, mentoring, graceful exit, handling member death), a network without these mechanisms will be confusing to join and awkward to leave.
- Don't assume moderation tooling only needs to catch bad actors, it must also protect earnest-but-unpopular users from being mistaken for griefers.
