# Chapter 1: The basics of unit testing

## Key Concepts

- **Unit of Work**: All the actions that happen between triggering an entry point and reaching one or more noticeable end results (exit points). A unit of work can be a single function, several functions, or a whole module or component chain. Its boundary is defined by behavior, not by file or class layout.

- **Entry Point**: The thing a test triggers from the outside, usually a public function's signature. A unit of work can have more than one entry point (for example a setter and a separate getter), each exercised by different tests.

- **Exit Point**: A publicly noticeable result of a unit of work, something a caller (test or other production code) can observe without reaching into private state. If a piece of code produces nothing observable, it is dead weight and should be removed. Each exit point should generally get its own test rather than cramming multiple assertions about unrelated outcomes into one.

- **SUT (subject/system/suite under test)**: The thing you are testing, sometimes also called CUT (component/class/code under test). Both terms just name "the code this test is about."

- **Dependency**: Something a test cannot fully or easily control, or that would be miserable to control, and that is not fast or in-memory. Examples: a logger writing to a file, a network call, code owned by another team, a database, a thread. Rule of thumb: if you can fully control it, it runs in memory, and it is fast, it is not a dependency for testing purposes.

- **Query vs Command**: Query actions return a value without changing anything. Command actions change state without returning a value. Keeping the two separate (command-query separation) makes exit points cleaner and easier to test individually, though real code often mixes them.

- **Regression**: A previously working unit of work that has broken. Fast, comprehensive unit tests catch regressions within minutes of introducing them instead of weeks later.

- **Legacy Code**: Several definitions coexist, but the one this book leans on (via Michael Feathers) is simply "code that has no tests." That framing matters because it means untested new code is legacy code the moment it ships.

- **Control Flow Code**: Any code containing an `if`, a loop, a calculation, or any other decision point. This is what a unit test's definition ultimately targets. Plain getters/setters or properties without logic do not need direct tests, they will be exercised incidentally as part of testing the units that use them. The moment logic creeps into a getter or setter, it needs its own coverage.

- **Refactoring**: Changing code's internal structure without changing its observable behavior (renaming, splitting a function, and so on). Refactoring steps should be small, with the full test suite rerun after each step to confirm nothing broke.

---

## Exit Point Types

Three kinds of exit point, and each tends to need a different testing technique.

1. **Return value (or error)**: The function returns something directly usable. Easiest to test: call it, capture what comes back, assert on it.
2. **State change**: Some observable state, reachable without touching private internals, differs before and after the call. Testing this usually means calling the entry point, then calling a second accessor (or the same one again) to check the new state.
3. **Third-party call**: The unit of work calls out to something external (logger, database client, message queue) whose own return value is irrelevant or absent. Verifying this kind of exit point is the most work: it typically needs a mock or spy standing in for the real dependency, and it is the type of test most prone to becoming brittle.

A short JS sketch of the same function acquiring exit points one at a time:

```js
// return-value exit point only
const sum = (numbers) => {
  const [a, b] = numbers.split(',');
  return parseInt(a) + parseInt(b);
};

// return value + state-change exit point
let total = 0;
const sum2 = (numbers) => {
  const [a, b] = numbers.split(',');
  const result = parseInt(a) + parseInt(b);
  total += result;
  return result;
};
const totalSoFar = () => total;

// return value + state change + third-party call exit point
const sum3 = (numbers) => {
  const [a, b] = numbers.split(',');
  logger.info('summing', { a, b }); // third-party exit point
  const result = parseInt(a) + parseInt(b);
  total += result;
  return result;
};
```

Rule of thumb from the chapter: prefer return-value and state-based tests, and try to keep mock-object-based (third-party) tests to a small minority of the suite (the author aims for roughly 5 percent), since they add the most maintenance friction.

---

## What Counts as a Good Test

Every good automated test, not only unit tests, should be:

- Easy to understand the intent behind
- Easy to read and write
- Automated
- Consistent (same result every run, given no code change)
- Useful, with actionable results when it fails
- Runnable at the push of a button, by anyone
- Clear about what was expected versus what happened, when it fails

A good **unit** test additionally should:

- Run quickly
- Have full control over the code under test
- Be fully isolated from other tests
- Run in memory, no filesystem, network, or database
- Be as synchronous and linear as possible (no incidental parallelism)

This list is functionally the same territory other sources cover as FIRST (Fast, Isolated, Repeatable, Self-validating, Timely). The chapter does not use that acronym, it arrives at the same properties from first principles: speed, isolation, consistency, and observable pass/fail.

**Checklist for telling a real unit test from something else.** A "no" to any of these is a sign you are looking at an integration test, not a unit test:

- Can you run a test from months ago and trust the result, and can any teammate run it too
- Can the whole suite finish in a couple of minutes, at the push of a button
- Can a new basic test be written in a few minutes
- Does it still pass when another team's code has a bug (it does not depend on out-of-scope correctness)
- Does it give the same result on any machine, and does it keep working with no database or network available
- Does deleting or reordering one test leave the others unaffected

These checklist answers boil down to three criteria: **readability** (can you tell what broke), **maintainability** (is keeping the test alive painful), and **trust** (do you believe a pass and investigate a fail, or do you shrug at either).

---

## Integration Tests

An integration test is any test that fails to meet one or more of the good-unit-test conditions above, typically because it touches a real dependency: real network, real database, real filesystem, real system clock. Using `new Date()` directly in test code, for instance, makes the test's outcome depend on when it runs, which breaks consistency.

Integration tests are not bad, they are a necessary counterpart, but they should be kept separate from unit tests so failures in the unit suite stay easy to localize. A useful mental model: a car is a system of subsystems, and driving it down the road is the ultimate integration test. If the car stops, any subsystem (or several) could be at fault, and figuring out which one takes real diagnostic work. Unit tests are the per-subsystem tests that let you rule things out quickly instead of guessing from the symptom of "car does not move."

Working definition offered in the chapter: integration testing is testing a unit of work without full control over its real dependencies (other teams' components, other services, the clock, the network, databases, threads, random number generators, and so on).

---

## The Chapter's Final Definition

The chapter opens with a borrowed, admittedly incomplete definition (paraphrased from Wikipedia): a unit test is an automated check, written by developers, confirming a section of code (the "unit") behaves as designed. It then builds up entry points, exit points, and the good-test properties, and arrives at its own definition:

A unit test is automated code that invokes a unit of work through an entry point and checks exactly one of its exit points. It is almost always written with a unit testing framework, is quick to write and quick to run, and is trustworthy, readable, and maintainable. It stays consistent as long as the production code under test has not changed.

Compared to the chapter's own first-edition definition (which restricted unit tests to control-flow code only), this version is broader. Any code that participates in a unit of work is fair game to be exercised by a test, even with no branching logic of its own, because it still gets pulled through the entry-to-exit path. Only code with zero logic (pure getters/setters) is exempt from needing direct coverage.

---

## Test-Driven Development Basics

TDD (as scoped in this chapter) means test-first development, with design happening incrementally as a side effect, not the reverse. Three-step loop, repeated in small increments:

1. **Write a failing test** for a small piece of missing or wrong functionality. The test is written as though the correct code already existed, so a failure at this stage confirms the code does not exist yet or is wrong, not that the test itself is broken.
2. **Make it pass** with the simplest production code that satisfies the test. Do not touch the test while doing this.
3. **Refactor** production code and/or test code (rename, deduplicate, restructure) while keeping all tests green, then repeat.

```js
// step 1: write the failing test first
test('sum adds two numbers', () => {
  expect(sum('1,2')).toBe(3);
});

// step 2: simplest code to pass
const sum = (numbers) => {
  const [a, b] = numbers.split(',');
  return parseInt(a) + parseInt(b);
};

// step 3: refactor once green, rerun tests after each small change
```

**Why TDD helps beyond "tests exist"**: seeing a test fail first and then pass, without editing the test, is itself a check on the test. If a test you expect to fail instead passes immediately, either the test is wrong or it is not exercising what you think it is. That failing-then-passing cycle is a form of testing the tests, and it is largely unavailable to test-after workflows, where tests usually only pass (since the code they cover is already presumed to work).

**Three separate skills for successful TDD**, called out explicitly so they are not conflated:

- Writing good tests (readable, maintainable, trustworthy). This chapter's and book's actual subject.
- Writing tests first (the "test-first" discipline itself).
- Designing the tests and production code well (a design skill, not a testing skill).

Being strong in one does not imply strength in the others. Writing tests first with no design sense still produces a poorly designed system. Writing readable tests after the code still forfeits the failing-first confidence check. The chapter recommends learning the three incrementally rather than all at once.

**TDD is not a substitute for knowing what a good test looks like.** It is entirely possible to follow the red-green-refactor mechanics faithfully and still end up with unreadable, brittle, or untrustworthy tests if the underlying test-writing skill is weak.

---

## Common Pitfalls

- **Testing multiple exit points in one test**: makes failures ambiguous about which behavior actually broke, and makes tests harder to read and change independently. Give each exit point its own test.

- **Treating in-memory databases or jsdom as a free pass to "unit test"**: these are still dependencies with their own quirks (an in-memory DB can behave differently from the production one, so passing tests are not a real guarantee). Prefer stubs for unit tests, or a real dependency clearly labeled as an integration test, and do not silently mix the two.

- **Depending on the real system clock in a test**: `new Date()` inside test code means every run is technically a different test, breaking the consistency property. Control time explicitly instead.

- **Confusing "I ran some tests" with "I wrote unit tests"**: many teams do integration-style testing and call it unit testing. Run the chapter's checklist questions against your suite before assuming it qualifies.

- **Over-reliance on mock-object-based (third-party) tests**: they are the hardest exit-point type to keep maintainable. If most of the suite is mock-heavy, that is a signal the code's dependencies are not well separated from its logic.

- **Chasing TDD mechanics without the underlying test-writing skill**: red-green-refactor discipline alone does not guarantee readable, maintainable, or trustworthy tests. The mechanics and the skill are separate things to learn.

---

## Connections to Later Chapters

- **Chapter 2**: Moves from the hand-rolled `check`/`assertEquals` helpers in this chapter to writing the same kinds of tests with Jest.
- **Chapter 3**: Expands on "full control of the code under test," the isolation property introduced here.
- **Chapters 7 through 9**: Go deep on trustworthy, readable, and maintainable tests, the three qualities this chapter's final definition leans on but does not fully unpack.
- **Section 8.3**: Dedicated treatment of refactoring, introduced here only as step 3 of the TDD loop.
- **External references named in the chapter**: Vladimir Khorikov's *Unit Testing Principles, Practices, and Patterns* for a deeper take on observable behavior. Gerard Meszaros' *XUnit Test Patterns* for the direct/indirect input-output framing that parallels entry/exit points. Michael Feathers' *Working Effectively with Legacy Code* for the "code with no tests" definition of legacy code. Kent Beck's *Test-Driven Development: By Example* for test-first mechanics in depth. Freeman and Pryce's *Growing Object-Oriented Software, Guided by Tests* and Robert C. Martin's *Clean Code* for the design skill that TDD alone does not teach.
