# Understanding the Problem: Design Research

Source: About Face: The Essentials of Interaction Design, 4th Edition (Cooper, Reimann, Cronin, Noessel), Chapter 2.

## In one line

Good design decisions come from qualitative research into what users are trying to do and why, not from quantitative data alone, and Goal-Directed research runs through a specific sequence: kickoff, literature review, product/competitive audit, stakeholder interviews, SME interviews, then ethnographic user and customer interviews.

## Core ideas

**Qualitative beats quantitative for design questions, but each has a job.** Quantitative data (surveys, analytics, market sizing) tells you how much or how many. Qualitative data tells you what, how, and why. Human behavior is too variable and context-dependent to reduce to statistics without losing the nuance that actually drives design decisions. Use quantitative research to size a market or validate a business case, and quantitative analytics to spot where a redesign is needed, but use qualitative research to explain the root cause and generate the solution. Design decisions traceable to qualitative research also give the design team credibility with stakeholders and reduce arguments driven by personal opinion.

**Market segmentation is not a user model.** Knowing who will buy something (market segmentation, demographics, psychographics) is a different question from knowing what they will do with it once they have it. Treat market research as a tool for sizing opportunity and picking interview candidates, not as a substitute for behavioral research.

**Research direction runs both ways between qualitative and quantitative.** Market research can help fund a design initiative and select interview targets. Once personas exist (see chapter 3), a market-sizing survey can quantify how many people match each persona, which helps prioritize which user type to design for first.

**The research sequence matters and should mostly happen before design starts.** Kickoff meeting, literature review, and product/competitive audits happen first or in parallel, then stakeholder interviews, then SME interviews, then user and customer interviews and observation. Each phase informs the next. What you learn from stakeholders shapes how you interview users, and what you learn from SMEs shapes your interview topics list.

**Interview stakeholders one-on-one, not as a group.** Group settings suppress candor and let one voice dominate. Individual interviews reveal whether the organization actually shares one vision of the product or is working from conflicting mental models, which is itself a critical finding: a serious split in stakeholder vision is a flag to track and resolve early.

**Stakeholders and SMEs will hand you solutions, not problems.** Treat proposed features and fixes as clues, not requirements. Ask "what problem would that solve" or "how would that help you" to get underneath the suggestion to the real need. The same discipline applies to customers and users: their solutions are usually narrow, biased by personal experience, and lack the tradeoff view a designer brings.

**SMEs carry a skewed, invested view of the current system.** They know the domain deeply but they are often expert users or ex-users who have adapted to existing quirks, so they may push for expert-level controls rather than interfaces suited to intermittent or new users. Use them for domain facts, regulations, and reality checks, not for interface decisions.

**Customers and users are frequently different people with different questions to answer.** In consumer products they often overlap, but in enterprise, medical, or technical products the buyer (executive, IT manager) and the user rarely match. Interview both, but ask them different things: customers about purchase drivers, decision process, and ownership responsibilities, users about goals, context, mental model, and daily frustration.

**Watching beats asking.** People are bad at self-reporting their own behavior, especially once removed from the situation, and they may hide behaviors that make them look incompetent. Combining live observation with interviewing, so you can ask clarifying questions about what you just watched, produces far better data than interviews alone.

**Build a persona hypothesis before you schedule interviews.** Before talking to users, form a working guess at the different user types, how their needs and behaviors likely differ, and what range of contexts need covering. This hypothesis is provisional and gets corrected as interviews reveal user types you didn't anticipate. In business domains, job roles are a solid first cut. In consumer domains, roles don't exist in the same way, so lean on behavioral variables (frequency, motivation, attitude), then demographic variables, to differentiate user types, since consumer behavior crosses roles and lifestyle stages.

**Two more variables shape the hypothesis: domain expertise and technical expertise, and environment.** These are independent axes, a user can be domain-expert and technology-naive or the reverse, and the interface must support whichever is true of your real audience. Environmental variables (company size, IT strictness, security posture, industry, geography) matter especially for business products because they change what's normal and acceptable in an interface.

**Interview volume scales with hypothesis complexity, not with statistical significance.** Roughly four to six interviews per hypothesized role or behavioral, demographic, or environmental variable for enterprise products, double that (eight to twelve) for consumer products, since consumer behavior varies more. Interviews can cover multiple variables at once if you pick interviewees cleverly (one small company in one country covers size, industry, and geography together).

**Interviews sequence from broad to narrow across the project.** Early interviews explore domain knowledge broadly with open questions. Middle interviews test emerging patterns and get more domain-specific. Late interviews confirm patterns and close gaps with closed-ended questions. Schedule your most patient, articulate subjects early, and consider re-interviewing them late to fill gaps you didn't know to ask about at the start.

**Team of two per interview, sequential not parallel.** One person moderates and takes light notes, the other takes detailed notes and watches for gaps, and they can swap roles partway. Keeping the same small team (two or three designers) across all interviews, done one after another rather than farmed out in parallel, means the whole team builds shared, first-hand understanding instead of relying on secondhand debrief summaries. Cap interviews at about six per day to leave time for debrief and avoid interviewer fatigue.

**Debrief after every interview and code the whole set at the end.** Compare notes right after each interview to catch emerging trends and flag unanswered questions for the next one. After the full cycle, review everything and mark recurring patterns, this becomes the raw material for building personas.

## Named patterns and principles

**Ethnographic interview** (adapted from Beyer and Holtzblatt's contextual inquiry): a hybrid of live observation and directed interviewing conducted in the user's actual environment. Use it as the primary technique for gathering behavioral and goal data. It works because removing the user from context strips out the physical and situational cues (papers on the desk, cheat sheets, workarounds) that reveal unstated needs.

**Contextual inquiry** (Beyer and Holtzblatt): the source method, built on a master-apprentice model where the interviewer treats the user as the expert. Its four founding principles, still adopted here:
- *Context*: observe and question users in their real environment, not a lab, because artifacts and surroundings surface details people won't think to mention.
- *Partnership*: run the session as a collaborative exploration, alternating between watching work and discussing it, not an interrogation.
- *Interpretation*: the designer's job is to read between the lines of what's said and observed, but check interpretations against the user rather than assuming.
- *Focus*: subtly steer the conversation toward design-relevant territory instead of letting it wander or running a rigid script.

**About Face's modifications to contextual inquiry**, adopted because the original method is heavier than most projects need: shorten sessions to about an hour instead of a full day (with more interviewees to compensate), use small sequential teams instead of large parallel teams with group debriefs (so everyone has firsthand exposure to every user), identify goals before tasks (contextual inquiry is task-first, Goal-Directed Design is goal-first), and extend the method beyond corporate contexts into consumer domains.

**Persona hypothesis**: a provisional, pre-research sketch of the distinct user types likely to exist, built from stakeholder input, SME input, and literature review, used to plan who to interview. It exists because you cannot design a representative interview plan without some starting theory of who the different users are, and it explicitly gets revised as real interviews surface unexpected user types. It is the direct predecessor to personas (chapter 3).

**Man-on-the-street observation**: casually watching people use a product-relevant behavior in public spaces (retail, mobile use, public venues) without formal interview setup. Use it when the product or its analog is used in public and a formal sit-down interview would be impractical or would distort behavior.

**Open-ended vs. closed-ended questioning**: open questions ("why," "how," "what") draw out detail and are the default. Closed questions ("did you," "do you," "would you") wind down an unproductive thread or return focus, then hand off into a fresh open question. This works because the interview needs both expansion and steering. An unmanaged open interview wanders, an all-closed interview yields shallow yes/no data.

**Leading question** (named pitfall): a question that implies the answer or suggests a solution the designer already favors ("wouldn't feature X help you," "you like X, don't you"). Avoid these because, like a leading question in a courtroom, they bias the subject toward confirming what the interviewer already believes rather than revealing what's actually true.

**Coding** (borrowed from ethnography): organizing marked-up interview notes into topic groups after the interview cycle ends. Reserve for particularly complex or nuanced domains, since About Face considers full formal coding overkill for most projects but the basic pass of marking trends and patterns is always worth doing.

## How to apply

- Before drafting any requirements or UI, run (or request) qualitative research: stakeholder interviews first, then SME interviews if the domain is technical or regulated, then ethnographic interviews with actual users and, where different, customers.
- Interview stakeholders one at a time. Ask about product vision, budget and schedule, technical constraints, business drivers, and their perception of users. Flag any major disagreement in vision among stakeholders as a risk to resolve early.
- Build a persona hypothesis before scheduling user interviews: list plausible roles (business) or behavioral and demographic variables (consumer), and use it to decide who and how many people to talk to (roughly 4-6 per variable for enterprise, 8-12 for consumer).
- Combine observation with interviewing. Do not rely on self-reported behavior alone, go watch the task happen in its real environment and treat the surrounding artifacts (notes, cheat sheets, workarounds) as data.
- Sequence interviews broad-to-narrow: open exploratory questions early, pattern-confirming and detail questions later.
- When a user, customer, stakeholder, or SME proposes a solution, don't record the solution at face value, ask what problem it solves and record that instead.
- Prioritize understanding goals over tasks. Record tasks faithfully, but expect to redesign the task structure around the goal, not preserve the existing task flow.
- Treat usability testing as a late-stage validation tool against a real design artifact, not a discovery tool for early requirements. If budget allows only one round, spend it validating a candidate design rather than probing the old one.
- Be skeptical of focus groups and card sorting as primary design inputs. Use them for narrow, specific sub-questions (initial reaction to visual form, one view of a user's information categories) rather than as a stand-in for behavioral research.

## Watch out for

- Don't mistake market segmentation or demographic data for a behavioral model of users, it answers "who will buy" not "what will they do with it."
- Don't let SME input pass unquestioned. Their long familiarity with the current system biases them toward preserving current interaction patterns and expert-level controls.
- Don't conflate customers with users on enterprise, technical, or medical products, they usually have different goals and almost never use the product the same way.
- Don't run a rigid, fixed questionnaire in ethnographic interviews. It signals lack of interest, and it forecloses discovery of things you didn't know to ask about.
- Don't ask leading questions that hint at a preferred feature or answer.
- Focus groups tend to converge on the loudest or majority opinion, which suppresses exactly the behavioral diversity a designer needs to see. Don't use them to decide interaction design questions.
- Card sorting assumes the subject has strong organizational skills and that their card-sort logic will predict their actual product usage, which often does not hold. Treat it as a supplement to interviews, not a replacement.
- Task analysis documents how people work around today's obsolete systems, it rarely reveals what they actually want or need. Use it for pain points and process detail, not as the source of user goals.
