# Chapter 12: Working with legacy code

## Key Concepts

- **Legacy Code (in this context)**: Existing production code that was not written with test seams in mind. The core difficulty is not the code's age but its lack of extension or replacement points, which makes both testing and refactoring risky.

- **Seam**: A place in the code where you could plug in a test double or alternate implementation without editing the surrounding code. Legacy systems typically lack seams, so introducing tests forces some amount of restructuring before any test can even be written.

- **Test-Feasibility Table**: A prioritization tool for deciding which components to bring under test first. Score each component 1 to 10 on three factors, then use the scores to rank effort against value.
  - **Logical complexity**: how much branching logic a component has (nested ifs, switch statements, recursion), often measured with cyclomatic complexity tooling.
  - **Dependency level**: how many collaborators a component touches (databases, static loggers, email services, the filesystem). More dependencies means more work to isolate the component in a test.
  - **Priority**: how important the component is to the project right now.

- **Feasibility Mapping**: Plot components on a two-axis chart of logic (value of testing) against dependencies (cost of testing). Components with low logic and low dependencies (pure data holders) are usually not worth testing at all. What remains splits into two groups: logic-heavy components that are cheap to test, and logic-heavy components that are expensive to test because of their dependency count.

- **Easy-First Strategy**: Start with low-dependency, testable components. Tests come quickly at first, but the cost of writing each new test climbs over the life of the project because the hardest, most tangled components are left for last, right when the team has the least slack to deal with them. Good fit for a team new to unit testing since early wins build confidence.

- **Hard-First Strategy**: Start with the most tangled, highest-dependency components. The first tests are expensive and slow to write, sometimes a full day for something trivial elsewhere. But because bringing a high-dependency component under test usually means refactoring it, that refactoring tends to simplify the components around it too, so the cost per test drops quickly afterward. Only workable for a team that already has unit testing experience.

- **Characterization Test (safety-net integration test)**: A test written against the existing, real system (no mocks or stubs) purely to pin down its current behavior before you touch it. It does not assert the code is "correct," only that it does today what it did yesterday. Once in place, it is a tripwire for regressions during refactoring.

## Choosing Where to Start

1. Build the test-feasibility table for the components in scope.
2. Drop anything below a logic threshold (2 or 3 is a reasonable cutoff). Data classes and thin config readers are rarely worth the effort.
3. Decide easy-first or hard-first based on team experience with unit testing, not on what looks more urgent. A team without TDD experience that jumps straight into the hardest, most coupled class first will stall.
4. It is fine to mix: use priority to break ties once the easy/hard split is made, and know up front how much effort each direction implies.

## Writing Integration Tests Before Refactoring

The safety net pattern for legacy code that has no tests at all, and that you cannot isolate into unit tests without first refactoring it:

1. **Write one or more integration tests against the real system** that confirm current behavior. No mocks, no stubs, the real database or file or config on disk. These become your baseline of "what already works."
2. **Add a test for the new behavior you need**, written so it fails until the feature exists. This proves the gap you are closing.
3. **Refactor or add the feature in small steps**, rerunning the full set of integration tests (the baseline ones plus the new one) after each step. Any baseline test that starts failing tells you exactly where you broke existing behavior.
4. Only once the code is safely under this integration-test net do you refactor toward proper seams and replace the slow, broad integration tests with faster, narrower unit tests.

```
// illustrative shape, not a literal transcription
test('existing config save/load still works', () => {
  const cfg = ConfigManager.loadFromDisk(realFixturePath);
  cfg.set('timeout', 30);
  cfg.saveToDisk(realFixturePath);
  expect(ConfigManager.loadFromDisk(realFixturePath).get('timeout')).toBe(30);
});

test('new attribute is not yet supported', () => {
  const cfg = ConfigManager.loadFromDisk(realFixturePath);
  expect(cfg.get('retryCount')).toBeUndefined(); // fails once the feature lands, guiding the fix
});
```

Two practical notes on this approach:
- Integration tests can be quicker to write than unit tests because you do not need to understand the code's internals or find injection points, but making them runnable and repeatable (fixtures, disk state, environment) can itself take real setup time.
- Scope the effort to the part of the system you are actually changing. Do not try to blanket the whole legacy codebase with integration tests before starting. Grow coverage outward from the code you touch, and let the rest wait until you get there.

## Common Pitfalls

- Choosing hard-first without the team having unit testing experience. The upfront cost is real and can kill momentum before the payoff (simplified dependencies) shows up.
- Testing low-value, low-logic classes (pure data holders) just because they are easy. This burns time without reducing real risk.
- Skipping the integration-test baseline and refactoring legacy code directly "carefully." Without a baseline, a regression can go unnoticed until it reaches production.
- Trying to cover the entire legacy system with integration tests up front instead of growing tests around the code you are actually changing.
- Treating integration tests as a permanent replacement for unit tests. They are a scaffold. Once seams exist and the code is refactored, replace most of them with smaller, faster, more maintainable unit tests.

## Further Reading Named in the Chapter

- *Working Effectively with Legacy Code* by Michael Feathers covers seam-finding and dependency-breaking refactoring techniques in far more depth than this chapter attempts.
- *Unit Testing Principles, Practices, and Patterns* by Vladimir Khorikov (chapter 7) walks through a full worked example of refactoring legacy code under an integration-test safety net.
- CodeScene is mentioned as a commercial tool for surfacing technical debt and hidden hotspots in production codebases.
