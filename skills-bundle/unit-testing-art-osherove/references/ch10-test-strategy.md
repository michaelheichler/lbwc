# Chapter 10: Developing a testing strategy

## Key Concepts

- **Testing Strategy**: An organizational answer to a set of questions that go beyond any single test: at what level to test a given feature, whether to test it at more than one level, how to balance E2E coverage against unit coverage, how to keep the suite fast without losing trust in it, and who owns writing which kind of test. A strategy is a framework for making these calls consistently, not a fixed rulebook.

- **Test Pyramid (six levels)**: A layered model of test types, ordered from cheapest and fastest at the bottom to most confidence inducing but slowest at the top: unit tests (in memory), component tests (in memory, larger unit of work), integration tests (in memory, real dependencies substituted in), API tests (out of process, over the network), E2E/UI isolated tests (own app only, third parties faked), E2E/UI system tests (nothing faked, closest to production). Moving up the pyramid trades speed and maintainability for confidence.

- **Unit vs. Component Test**: Both run in memory with zero uncontrolled dependencies (no files, network, database, config). The only difference is scope: a unit test exercises one small piece (a button object), a component test exercises a larger assembly that includes several units (a form that contains the button). Whether something counts as unit/component depends on its dependency profile, not on how many objects or how much abstraction it touches.

- **Integration Test**: Same invocation style as a unit test (instantiate a production object, call an entry point directly), but at least one real dependency is left in, such as a live database, real config, or real filesystem. Confidence rises because you are exercising something you don't fully control, at the cost of speed and determinism.

- **API Test**: The first out-of-process level. The system under test must actually be deployed (at least partially) and is invoked over a network rather than instantiated in memory. This introduces both a new dependency (the network) and new setup cost (deployment, possibly schema validation).

- **E2E/UI Isolated Test**: Drives the application the way a user would, but fakes everything outside the application's own boundary: third-party auth, other teams' APIs, sibling services. "Isolated" describes the boundary of what's real, not the technique.

- **E2E/UI System Test**: The same user-facing drive, but nothing is faked. All dependency services are real (possibly reconfigured for the test scenario). This is as close to production as testing gets, and pays for that in speed, flakiness, and maintenance cost.

- **Five-Criterion Scorecard**: A rating framework (1 to 5 per axis) for comparing test types. The five axes are complexity (lower better), flakiness, meaning how often a test fails for reasons outside its control such as network or shared state (lower better), confidence when passing (higher better), maintainability (higher better), and execution speed (higher better). Every level on the pyramid is a different trade-off across these five axes, roughly: unit and component tests score 1 on complexity and flakiness, 1 on confidence, 5 on maintainability and speed. E2E system tests invert almost every number. Use the scorecard, not intuition alone, to justify where a scenario belongs.

- **Test-Level Antipattern**: A pattern that is organizational, not a technical bug in any single test. It emerges from how a whole team distributes its testing effort across levels, and it is diagnosed by looking at the shape of the pyramid the org has actually built, not the one on the whiteboard.

- **Build Whisperer**: A person, often a QA lead, whose actual job has become manually triaging a chronically red, flaky high-level suite to decide whether "red" actually means "broken." A symptom, not a role anyone should need to formalize, and its presence signals the end-to-end-only antipattern.

- **Delivery-Blocking Test**: A test whose failure must stop a release: unit, E2E, system, and security tests. Feedback is binary, pass means ship-safe, fail means fix first.

- **Good-to-know Test**: A test built for discovery and KPI monitoring rather than as a release gate, such as static analysis, complexity scanning, load and performance testing, or other long-running nonfunctional checks. Feedback is non-binary. A failure becomes a backlog item, not a blocked release.

- **Delivery Pipeline**: The pipeline that runs delivery-blocking tests, triggered automatically on every commit, optimized for fast feedback, and treated as the actual go/no-go gate for shipping.

- **Discovery Pipeline**: A separate, continuously running pipeline for good-to-know tests. It runs in parallel with delivery, is allowed to be slow, and never blocks a release. It just reports KPIs to a dashboard and files follow-up work.

- **Test Recipe**: An informal, five-to-twenty-line plan, written just before coding starts, that lists the scenarios (happy path plus meaningful edge cases) needed for a feature and assigns each one to a test level. It lives as a comment on the ticket, not as a separate test-management artifact, and it is the actual definition of done for the feature.

## Test-Level Antipatterns

- **End-to-end-only**: The suite is almost entirely E2E (isolated and/or system) tests. Diagnosis: the first E2E test for a scenario buys a lot of confidence because it exercises everything, but every subsequent E2E variation on the same scenario buys only a sliver of extra confidence while costing just as much to write, run, and maintain as the first one. That mismatch is what "diminishing returns" means here: value drops per test, cost per test stays flat. Root causes cited: a separate QA org running its own pipeline and defaulting to what it knows, an "it's working, don't touch it" inertia, and sunk-cost thinking about tests already written. Consequence: build whisperers and a "throw it over the wall" split where developers don't feel ownership of a red build that QA maintains. Fix direction: keep a small number of E2E tests for the scenarios that truly need full-system confidence, and push variations down to a lower, cheaper level.

- **Low-level-only**: The suite is almost entirely unit and component tests, with no real E2E presence. Passing unit tests alone don't produce enough confidence to ship without manual poking around, unless the artifact is a library consumed exactly the way the unit tests exercise it. Root cause: a team only comfortable writing (or only responsible for writing) low-level tests, expecting someone else to cover the rest. Fix direction: keep unit tests as the bulk of the suite, but add higher-level coverage for the scenarios that need it.

- **Disconnected low-level and high-level tests**: Looks healthy from a distance (you have both ends of the pyramid) but is actually two separate test suites written by two groups who don't talk to each other, often duplicating the same scenarios at multiple levels and running in separate pipelines that nobody watches together. Result is the worst of both worlds: still pay the E2E costs (slow, flaky, hard to maintain), still don't get the E2E confidence benefit reliably communicated, and don't get the low-level speed payoff either, because the same scenarios are redundantly retested at the top. Root cause: structurally separate dev and test organizations with different goals, metrics, and even repos.

## Test Recipes as a Strategy

A test recipe answers one question per feature: which scenarios, tested at which level, would leave you comfortable saying "if all of these pass, I believe this feature works"? It is written by at least two people (ideally a developer and a tester, or two developers) right before coding starts, because a second perspective catches implicit assumptions the first person doesn't notice.

Shape of a recipe, illustrative (not the book's exact wording):

```
Profile update feature
E2E: sign in, edit email, sign out, sign back in, confirm new email shows
API: call UpdateProfile with a complex payload
Unit: reject malformed email
Unit: no-op when new email equals old email
Unit: serialize/deserialize round-trip
```

Rules for writing one, on process:

- **Write it just in time**, right before the person who will implement the feature starts, not far in advance.
- **Pair on it.** Different people catch different missing scenarios.
- **It's a living list**, revised as coding surfaces new edge cases, not a locked spec.
- **The recipe is done when it produces a "pretty good confidence" feeling**, not when a checklist is exhausted.

Rules for writing one, on content:

- **Prefer the cheapest level that still buys confidence.** Only escalate to a higher level when nothing lower can prove the point.
- **Don't repeat scenarios across features** that already cover the same ground elsewhere.
- **Don't repeat scenarios across levels.** If the happy path is proven at E2E, lower levels should cover variations (different providers, failure modes), not the same happy path again.
- **Aim for roughly a 1:5 to 1:10 ratio** between adjacent levels. For every E2E test, expect five or more tests one level down. A hundred unit tests might justify around ten integration tests and one E2E test.
- **Be pragmatic.** Not every feature needs coverage at every level. Some need only unit tests, some need only an API or E2E check. Judge by whether the recipe, if fully green, produces confidence, then adjust which levels carry the weight.

The payoff of doing this well is threefold. Most of the suite stays fast because it lives at the low level. The handful of scenarios that truly need it still get high-level coverage. Duplication drops because variations are deliberately pushed to lower levels. And if testers are involved in writing recipes, it becomes a forcing function for developer and QA communication instead of a wall between them.

## Managing Delivery Pipelines

Not every test belongs in the same pipeline stage, and treating them as if they do wastes the thing a fast feedback loop is for.

- **Split by consequence, not by test type.** The real question for any test (unit, security scan, load test, linter) is: does a failure here mean "don't ship" or "worth investigating later"? Delivery-blocking tests (unit, E2E, system, security) get a binary gate. Good-to-know tests (complexity scanning, performance and load testing, most static analysis) produce a KPI trend, not a stop-ship verdict.
- **Two pipelines, two cadences.** The delivery pipeline runs on every commit, is kept fast, and its green or red status is the actual release decision. The discovery pipeline runs continuously in the background regardless of commit cadence, can be as slow as it needs to be, and reports to dashboards. Its failures spawn backlog items, not blocked deploys.
- **Parallelize within a pipeline, not just between them.** Run test-level stages (unit, API/E2E, security) concurrently rather than sequentially, wait for all of them, then deploy. The same trick applies inside a stage: split a large E2E suite into parallel batches across dynamically spun-up environments. Money spent on parallel dynamic environments beats money spent on more manual testers, or on people idling while a shared environment is busy. The math is just headcount-waiting-time times build frequency times team size, and it adds up fast.
- **Trigger on commit, not on a clock.** Nightly builds accumulate a full day of changes into one diagnosis problem and delay feedback by up to 24 hours. Running the pipeline continuously (start the next build the moment the previous one finishes, if there's new code) gives the fastest honest signal available.

## Common Pitfalls

- **Judging a test level by its abstraction level instead of its dependencies.** A test that uses a higher-level object graph is still a unit or component test if every dependency is fake and everything runs in memory. What promotes a test to "integration" is a real dependency, not more classes involved.

- **Writing E2E tests for every variation of a scenario instead of just the happy path.** The first E2E test earns its keep. Each additional E2E variant on the same scenario earns a shrinking fraction of confidence for the same fixed cost. Push variations down a level once the glue code is already proven once at the top.

- **Letting a QA org own the whole high-level suite in isolation.** Separate pipelines, separate ownership, and no shared visibility reliably produce either the end-to-end-only pattern or the disconnected-levels pattern, both driven by the same root cause: the people writing tests at one level don't see or care about the other level's results.

- **Treating sunk cost as a reason to keep bad E2E coverage.** "We already wrote all these E2E tests" is not a reason to keep paying their maintenance tax. The ongoing cost of debugging flaky high-level tests usually exceeds the cost of deleting most of them and keeping a few.

- **Putting good-to-know tests in the delivery-blocking gate.** A failing performance or complexity scan that blocks every release trains people to ignore red builds, because the failure often isn't actually release-relevant. Route these to a discovery pipeline instead.

- **Running the full suite only on a nightly schedule.** This turns a same-day bug into a next-day discovery, and if multiple changes land before the nightly run, it also turns a one-line diagnosis into a multi-commit hunt.

## Connections to Other Chapters

- **Chapter 7**: The test-level pyramid figure used here (unit through system E2E) is introduced there first. This chapter builds the decision framework (the scorecard, the recipe, the pipeline split) on top of that vocabulary.

- **General theme**: Earlier chapters in the book focus on writing a single good unit test in isolation. This chapter zooms out to the organizational question those unit tests live inside: how much of the suite should be unit tests at all, and how unit, integration, and E2E tests combine into one coherent, fast, trustworthy release gate instead of duplicating or contradicting each other.
