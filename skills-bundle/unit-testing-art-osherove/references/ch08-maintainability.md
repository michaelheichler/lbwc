# Chapter 8: Maintainability

## Key Concepts

- **Maintainability**: A measure of how often tests are forced to change. The fewer times we're forced to touch a passing test suite as production code evolves, the more the tests are helping rather than costing. Unmaintainable tests get abandoned first when schedules tighten, because developers stop fixing tests that break for reasons unrelated to actual bugs.

- **True Failure**: A test failure that surfaces a genuine bug in production code. This is the failure we write tests to find.

- **False Failure**: A test failure caused by anything other than a real bug: a stale assumption, a changed API signature, a leaked shared state, an internal refactor that didn't change behavior. False failures are the enemy of maintainability. Tracking the count and cause of false failures over time is a concrete way to measure whether a suite's maintainability is improving or rotting.

- **Overspecification**: A test that encodes assumptions about *how* the unit does its work (internal calls, private state, exact collection order, exact string contents) rather than only checking the *observable* result (the exit point). Overspecified tests break whenever an implementation detail changes, even though the behavior a caller depends on stayed correct.

- **Exit Point**: The one place a unit of work's result becomes observable from outside: a returned value, a change to a sibling property or state visible at the same scope as the entry point, or a call made to a third-party dependency (fire-and-forget). Tests should assert against exit points, never against intermediate calculations or private helper calls that only feed into the exit point.

- **Factory Function**: A small function whose only job is to construct and preconfigure the object under test (or a fake it depends on). Centralizes construction so that when a constructor signature changes, only the factory function needs editing, not every test that instantiates the object.

- **Test Isolation / Constrained Test Order**: A test suite is isolated when each test can run alone, in any order, and still pass. A "constrained test order" bug happens when test B secretly depends on test A having run first (because A mutated some shared singleton or external resource that B reads). Test runners don't guarantee ordering, so this kind of coupling is a ticking time bomb. Running a single test with `test.only` is a fast way to expose it.

- **Setup Method (`beforeEach`)**: Code that runs automatically before every test in a block. Osherove argues against relying on it: it can't take parameters or return values, it tends to accumulate object initialization that only some tests actually need, and it hides arrange-section logic outside the test body, hurting readability. Prefer explicit helper functions called from within each test.

- **Parameterized Test**: A single test body driven by a table of input/expected-output pairs (Jest's `test.each` / `it.each`). Removes duplication between near-identical tests without resorting to a setup method, by folding the varying data into the test's own arrange section rather than hiding it upstream.

- **Value-Based Test**: Asserts on a function's return value. The default and preferred exit point to test when a function returns something meaningful.

- **State-Based Test**: Asserts on a sibling property or function's observable state after calling the entry point, used when the entry point itself has no useful return value but changes state visible at the same scope.

- **Third-Party Test**: Uses a mock to verify a call was made to an external dependency, appropriate only when that call is the exit point (a fire-and-forget side effect with no return value to check), not when the "external" call is an internal implementation detail feeding back into the same function's own return value.

---

## Root Causes of False Failures (Section 8.1)

### Cause 1: The test is no longer relevant
New requirements can directly conflict with an existing test's expectations. If a new passing test now covers the correct behavior, the old failing test is probably obsolete and should be deleted, not patched. Exception: with feature toggles, both the old and new behavior may need to coexist under different flags.

### Cause 2: Changes in the production code's API
Code that lives for years will have its constructors and signatures reshaped. If tests instantiate the object under test directly and repeatedly, every signature change forces edits across the whole suite.

```js
// fragile: every test constructs PasswordVerifier directly
const verifier = new PasswordVerifier([], { info: jest.fn() });

// resilient: one factory absorbs the constructor's shape
const makePasswordVerifier = (rules, logger = makeFakeLogger()) =>
  new PasswordVerifier(rules, logger);
```

When the constructor signature changes later, only `makePasswordVerifier` needs an edit. The tests that call it stay untouched. The same idea applies to fakes and mocks: give each one its own factory (`makeFakeLogger`) rather than inlining its shape everywhere it's used.

### Cause 3: Leakage from other tests (lack of isolation)
A shared singleton (a cache, a global config object, an in-memory store) read and written by multiple tests creates order dependence. One test needs the cache empty. Another needs it pre-populated by a sibling test that happened to run earlier. This works by accident until the runner's order changes. Then tests fail unpredictably and get dismissed as "flaky" instead of fixed.

Fix in three steps:
1. Extract a helper function for any shared setup action (e.g., `addDefaultUser()`).
2. Reuse that helper explicitly inside each test that needs the precondition, rather than depending on another test having already run.
3. Reset shared state between tests, typically with `beforeEach(() => sharedResource.reset())`.

After the fix, every test builds its own precondition from a known-empty starting state and none of them care what order the runner picks.

---

## Refactoring to Increase Maintainability (Section 8.2)

These are changes made by choice, not forced by a failure, to reduce future pain.

### Avoid testing private or protected methods
A private method is an internal contract that can change shape during refactors without the observable behavior of the class changing. Testing it directly couples the test to that internal contract, so tests break on refactors that introduce no real bugs. Instead:

- Find the public method (or chain of public calls) that exercises the private method and test through that path. Every private method eventually gets triggered by some public entry point. That entry point's return value, state change, or third-party call is the correct thing to assert on.
- If a private method has enough independent logic or state to deserve its own tests, that's often a sign it belongs in its own class or module, testable through its own public surface (see Feathers, *Working Effectively with Legacy Code*, and Martin, *Clean Code*, for extraction guidance).
- If the method is stateless and genuinely useful as a utility, making it public (or public and static) is a legitimate design choice, not a violation of encapsulation for its own sake. It means declaring the contract officially instead of hiding it.

### Keep tests DRY
Duplicated arrange/assert logic multiplies the cost of any change to the thing under test, and duplication is exactly what tempts developers to delete or skip a failing test rather than fix every copy. Use helper functions to centralize repeated setup and assertion logic, the same discipline used for factory functions above. Caveat: pushing DRY too far can hurt a test's readability, since a reader may need to jump between the test and its helpers to understand what's being verified.

### Avoid setup methods (`beforeEach`)
Setup blocks tend to accumulate objects only a subset of the file's tests actually need, can't accept parameters or return values, and hide the arrange step outside the test itself. Prefer plain helper functions called explicitly from within each test:

```js
const addDefaultUser = () => getUserCache().addUser({ key: "a", password: "abc" });
const makeSpecialApp = () => new SpecialApp();

test("login succeeds", () => {
  addDefaultUser();
  const app = makeSpecialApp();
  expect(app.loginUser("a", "abc")).toBe(true);
});
```

A `beforeEach` is still appropriate for one narrow job: resetting shared state that genuinely applies to every test in the block (the reset-the-cache case above), not for constructing objects some tests don't use.

### Use parameterized tests to remove duplication
When multiple tests are structurally identical and differ only in input/expected-output, `test.each` (Jest) collapses them into one test body driven by a data table, which removes duplication without hiding logic in a setup block:

```js
test.each([
  ["1", 1],
  ["2", 2],
])("sum(%s) returns %i", (input, expected) => {
  expect(sum(input)).toBe(expected);
});
```

Use this only when the scenario is truly the same and only the data varies. Forcing dissimilar tests into one parameterized shape hurts readability more than it saves.

---

## Avoiding Overspecification (Section 8.3)

An overspecified test encodes assumptions about the unit's internal implementation instead of only checking its observable behavior. Common forms: asserting purely internal state, mocking and verifying an internal function call, using a stub as if it were a mock, or asserting an exact order or exact string when only part of the result actually matters.

### Don't verify calls to internal helper functions
If a private/protected helper's result flows back into the calling function's own return value, that helper call is not an exit point. Mocking it and asserting `toHaveBeenCalled()` proves nothing about correctness and couples the test to an implementation detail that can change freely without any real behavior changing.

```js
// overspecified: couples the test to an internal helper's existence
pv4["findFailedRules"] = jest.fn(() => []);
pv4.verify("abc");
expect(findFailedRulesMock).toHaveBeenCalled();

// correct: assert on the actual exit point, the return value
expect(pv4.verify("abc")).toBe(true);
```

To find the right thing to assert on, classify the exit point. Value-based tests check the return value, the preferred exit point whenever one exists. State-based tests check a sibling property or function affected by the call. Third-party tests mock a genuine external dependency being fired and forgotten. A helper method that only feeds a calculation back into the same function's return value is none of these, so it shouldn't be mocked or verified at all.

### Don't overspecify order or schema of a returned collection
Asserting the entire returned array structure, in exact order, with every property, means the test breaks whenever the schema gains a field or the order shifts. This happens even if the actual computed values a caller cares about are unaffected.

```js
// overspecified: breaks if a field is added or order changes
expect(results).toEqual([
  { input: "a", result: false },
  { input: "abc", result: true },
]);

// looser: check only the values that matter, order-independent
expect(results.length).toBe(4);
expect(findResultFor(results, "a")).toBe(false);
expect(findResultFor(results, "abc")).toBe(true);
```

### Don't overspecify exact string content
Asserting exact string equality on a user-facing message ties the test to wording, punctuation, and phrasing that changes for cosmetic reasons unrelated to the logic being tested. Assert on the substantive part only:

```js
// overspecified: breaks on any wording tweak
expect(msg).toBe("you have 2 failed rules.");

// future-proof: checks the number that actually matters
expect(msg).toMatch(/2 failed/);
```

The general heuristic: before writing an assertion, ask whether it can fail for a reason unrelated to the behavior under test. If yes, narrow it until only the behavior that matters can break it.

---

## Common Pitfalls

- **Instantiating the object under test directly in every test**: any constructor signature change then forces edits across the whole file. Route construction through one factory function per type.

- **Depending on execution order between tests**: a test that only passes because a sibling test happened to run first (and mutated shared state) will fail unpredictably once the runner's order changes. Reset shared resources in `beforeEach` and make every test build its own preconditions explicitly.

- **Testing a private method directly**: locks the test to an internal contract that's meant to be free to change. Test through the public entry point that eventually calls it, or extract the method to its own testable unit if it deserves independent coverage.

- **Mocking an internal helper and asserting it was called**: proves nothing about correctness if the helper's result already flows into the function's real exit point (its return value). Assert on the exit point instead.

- **Asserting an entire collection's exact order and schema**: breaks on any unrelated schema addition or ordering change. Assert only the specific values relevant to the test, order-independent where order isn't part of the contract.

- **Asserting exact string equality on user-facing messages**: breaks on cosmetic wording changes. Use a substring/regex match on the substantive part of the message.

- **Overusing `beforeEach` as a dumping ground**: initializing objects some tests don't need, or burying arrange-section logic outside the test body, both hurt readability and invite accidental coupling between tests. Reserve it for resetting genuinely shared state, and use helper functions for everything else.

- **Removing duplication so aggressively that readability suffers**: DRY helper functions are good until a reader has to jump between several files to reconstruct what a single test actually does.

---

## Connections to Other Chapters

- **Chapter 7**: Introduces "a test that contains a bug" as one root cause of false failures, extended in this chapter with the broader true-failure/false-failure framing and additional root causes (API changes, test coupling).

- **Chapter 2**: Referenced as an earlier example of the `beforeEach`-to-helper-function refactor also demonstrated here with the shared user cache.

- **Chapter 9 (Readability)**: Flags that removing duplication (DRY) can be taken too far and start to hurt a test's readability, a tradeoff picked up in the next chapter.

- **Chapter 10**: Feature toggles, mentioned here as an exception to "delete the no-longer-relevant test," get fuller treatment when testing strategies are discussed.

- **External reference**: Vladimir Khorikov's *Unit Testing Principles, Practices, and Patterns* (Manning, 2020), chapter 5, is cited for a deeper treatment of mocks and their relationship to test fragility, directly underpinning the overspecification-with-mocks discussion in this chapter.
