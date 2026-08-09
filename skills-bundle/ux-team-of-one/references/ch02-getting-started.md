# Getting Started

This chapter gives you a five-step entry framework for beginning UX work in any organization -- especially when you are crossing over from another field or operating without formal UX authority. It maps the full landscape of UX activities (discovery through implementation) so you know what options exist, then narrows to the practical starting moves that create real momentum. The core message: something is almost always better than nothing, and even a little user research generates its own momentum.

---

## The Five-Step Entry Framework

The chapter's structure is itself the framework. Apply it in order when beginning a new product engagement or taking on UX responsibility without a mandate:

1. Get to know the UX improvement process
2. Establish a point of view on what can be improved
3. Get to know your users and customers
4. Explore required information architecture
5. Start designing

These steps are not a rigid waterfall -- they orient you and help you pick where to invest limited time.

---

## Step 1: Get to Know the UX Improvement Process

### Key concept: processes are starting points, not recipes

Multiple process models exist (triple-diamond, Scrum+UX overlay, Lean UX + Agile hybrid). What they share is a common set of activities grouped into four phases: **Discovery, Strategy, Design, and Implementation**. No single process is universally correct; all must flex to fit company culture, existing team dynamics, and project constraints.

**When operating as a team of one:** You will rarely execute the full process. You will do smaller parts, in less depth, without a complete work plan. This is acceptable. Any amount of research is better than guessing.

### The four phases -- activities to know and draw from

**Discovery** -- Understanding the problem before designing anything:
- Stakeholder Interviews: surface each stakeholder's definition of success (personal, political, and business-level -- these differ and cause friction if ignored)
- Competitive Analysis: SWOT across direct and indirect competitors
- Primary User Research: interviews, observation, usability testing, field studies, surveys
- Secondary User Research: existing data -- analytics, marketing segmentation, published reports; marketing segmentation is especially valuable if your org has done it
- Personas, Mental Models, and User Stories: synthesize research into memorable profiles and narratives that keep the team user-focused
- User Journey Mapping: visualize emotions, actions, and pain points across the full arc of product use
- Requirements Generation: translate user needs and business goals into feature candidates
- Scope and Constraints: define what is in and out of scope; prevent scope creep early

**Strategy** -- Defining the vision for the experience:
- Design Principles: a small set of attributes (simplicity, consistency, accessibility, etc.) that serve as a shared decision-making compass for the whole team
- Vision Artifacts: low-fidelity storyboards, diagrams, or "vision movies" that convey how the experience should feel
- MVP (Minimum Valuable Product): the chapter explicitly reframes MVP -- the "V" should stand for "valuable," not merely "viable." A feature set so minimal it delivers no real value teaches you nothing about demand. Teams frequently stress the minimum and omit the viable
- Accessibility and Inclusivity Guidelines: addressed in strategy, not as an afterthought
- Usability Testing Plan: embed testing plans into strategy so they inform design from the start
- Measurement and KPIs: Task Success Rate, Time on Task, Error Rate, SUS/CSAT scores, Conversion Rate, Retention Rate

**Design** -- Defining moment-to-moment user interactions:
- Information Architecture (IA)
- Process and Task Diagrams (User Flow, System Flow, Task Analysis)
- Low-Fidelity Prototypes: test and iterate before investing in high-fidelity work; changing direction in low-fidelity is far less costly
- UI Design and Specification (Figma, Axure RP)
- Design and Pattern Libraries / Design Systems

Key definition from the chapter: **"intuitive" means single-trial learning** -- not that users magically know what to do, but that after one pass they can do it again. This reframes what you are designing toward.

**Implementation** -- Making it real and keeping it right:
- Front-End Development collaboration
- Implementation Collaboration: your job does not end at handoff; clarify design intent, provide additional components, answer developer questions
- Usability Testing continues through implementation -- the window to make significant improvements narrows here
- Metrics and Analytics Tracking

---

## Step 2: Establish a Point of View on What Can Be Improved

### Principle: you do not need permission to start

When transitioning to UX or building UX credibility, starting with under-the-radar activities in your current role is more effective than requesting a wholesale role change upfront. Build momentum through small, visible wins first.

**Two foundational moves:**

**Find the low-hanging fruit.** Identify parts of the product that everyone knows need improvement. Connect any proposed improvement to business outcomes -- specifically, money made or money saved. Use a Heuristic Markup (Chapter 5) to do this solo, or a Black Hat Session (Chapter 7) with a group.

**Make a plan.** Sketch out a UX project approach: which activities, when, and why. Work backward from the big questions that need answering. Then ask: "Do I need permission for this, or can I start now?" Often you can start immediately.

### Tip: bypass the permission trap

When you need buy-in, avoid yes/no framing. Instead of "Can we do research?" offer: "We could do a research study, or a small informal evaluation -- which would work better here?" This shifts the conversation from whether to how. When a manager insists on their design solution, deliver two options: their version, and your version with a rationale for why yours better achieves the outcome they want.

---

## Step 3: Get to Know Your Users and Customers

### Principle: direct exposure to users is the single highest-leverage activity

Jared Spool's research (cited in the chapter) shows that the amount of face time a team has with end users directly impacts product quality. This is not negotiable in principle, even if it is sometimes constrained in practice.

**Why this is hard in practice:** Managers fear confirming problems they already know exist. Other departments guard customer access. Deadlines leave no time. The chapter acknowledges these realities explicitly -- but maintains that when you can do user research, you should.

Good products become "invisible" -- users achieve a state of flow where they are not thinking about the product, just accomplishing their goal. Reaching that requires understanding real people, not abstract statistics. As the chapter puts it: "Data are people, too" (Eric Ries, cited).

### How to start user research -- three orienting questions

1. **What do you know, and what don't you know?** Map gaps between user expectations and actual product behavior. Use existing data: analytics, support tickets, sales data, complaints.
2. **Who do you need to talk to?** Define target user groups by characteristics, behaviors, and job roles. Identify who you have access to, and how to get access if you do not.
3. **What research method fits this context?** Common options: interviews, surveys, usability testing, focus groups, direct observation. Method choice depends on objectives, user access, available time, and participant comfort level.

---

## Step 4: Explore Required Information Architecture

### Principle: most digital problems are information problems

Lou Rosenfeld, Peter Morville, and Jorge Arango (authors of *Information Architecture for the Web and Beyond*, the canonical reference) posit that at any given time, users either have too much information, not enough, or not the right information. IA is the discipline of solving that.

IA sits at the intersection of three factors: **users, content, and context**. Context -- business goals, culture, technology constraints, but also the user's physical environment, device, emotional state, and cultural presuppositions -- is often the most overlooked of the three and has profound influence on how users make sense of what they see.

### The four IA questions to answer before designing structure

1. What do users need to be able to do?
2. What does the organization need them to be able to do?
3. Where do users expect to find information, and what do they expect it to be called? (Navigation labels should follow established conventions or clearly explain the action -- e.g., "sign up," "log in.")
4. How do they expect information to be categorized, organized, and prioritized?

### Validating IA: tree testing

After drafting an IA model, validate it with users via **tree testing** (introduced by Donna Spencer). Tree testing simulates how people browse for specific items and reveals where they get lost, whether labels make sense, and whether categories match user mental models. It is faster and more conclusive than card sorting for validating structure.

Validation goals:
- Can users find specific items without backtracking?
- Can they make choices at each level without excessive deliberation?
- Which parts of the IA work, and which need revision?

---

## Step 5: Start Designing

### Principle: understand needs before reaching for tools

The risk of jumping into design software (Figma, Axure, etc.) immediately is that it encourages focusing on aesthetics before understanding what the design needs to accomplish. Software makes layout easy but does not teach you why certain structures are useful or usable for specific people.

### Three techniques to build design judgment without a formal design background

**Sketch your ideas.** Start with quantity, not quality. The goal of early sketches is to exhaust obvious, already-seen solutions and get to more informed, objective ones. Simple, elegant designs rarely start that way -- they emerge through iteration. Do this on paper or a whiteboard before opening any software tool.

**Enlist colleagues.** Host collaborative sketching sessions to gather diverse points of view and generate more ideas than you would alone. Cross-functional participation (not just designers) produces better coverage of the problem space.

**Learn from other products.** Maintain an inspiration library of UI patterns from apps, sites, and systems you find notable -- both good and bad. When you examine a design, push yourself to articulate *why* it works or fails. Practice verbalizing critique; confident critique language is a marker of strong design judgment and helps non-designers understand what they are looking at.

---

## Best Practices

- Run any amount of user research rather than none -- even a single conversation surfaces insights that cannot be obtained by guessing
- Always connect proposed UX improvements to business outcomes (revenue, cost savings) when making the case to stakeholders
- Use the "alternative close" technique when seeking buy-in: offer two paths for how to do the work, not whether to do it
- Never omit the "valuable" part of an MVP -- a feature set too minimal to be useful teaches you nothing about product-market fit
- Treat context (physical environment, device, culture, emotional state) as a first-class IA variable, not an afterthought
- Start IA work from user mental models (what people expect things to be called and where they expect to find them), not from internal org structures
- Validate IA with tree testing before investing in high-fidelity design
- Sketch in low fidelity before opening design software; changing direction is far cheaper before code is written
- When you cannot get access to users, use existing data (analytics, support tickets, marketing segmentation) as a proxy -- then advocate for direct access

---

## "If You Only Do One Thing"

The chapter's explicit takeaway: **get started with user research**. Establish a point of view on where to start, find a sensible balance of research, IA, and design -- but the most important concept in this chapter and in the field as a whole is to actually talk to or directly observe users. Even a small investment in understanding real user needs produces insights so significant they create their own momentum.

---

## Real-World Application

**When a user asks Claude to audit or improve a product:**
- Begin by asking what is known about current users and their pain points -- if nothing, flag that as the first gap to address
- Map the request to the five-step framework to identify which phase the user is actually in (often they jump to design before discovery is done)
- If no user research exists, recommend the minimum viable research action: even five user interviews or one round of usability observation
- For IA problems (users can't find things, navigation is confusing), apply the four IA questions above before proposing structural changes, then recommend tree testing before finalizing any new structure
- When the user has stakeholder resistance to UX work, coach the "alternative close" framing and the "low-hanging fruit + business outcome" pitch
- For design work, encourage sketching and iteration before committing to high-fidelity output; ask what the design needs to accomplish for specific users before evaluating whether it accomplishes it
