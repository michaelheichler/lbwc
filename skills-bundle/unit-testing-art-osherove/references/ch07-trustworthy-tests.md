# Chapter 7: Trustworthy tests

## Key Concepts

- **Trust (defined behaviorally)**: You trust a test if a failure makes you genuinely worried something broke (you don't shrug it off as noise), and a pass lets you relax without manually re-checking the feature. You distrust a test if a failure leaves you unworried (suspected false positive), a pass leaves you still worried (suspected false negative), or you feel free to ignore its result altogether.

- **Three pillars of a good test suite**: trustworthiness, maintainability, readability. They reinforce each other. Unreadable tests become unmaintainable, and both erode trust, since you can no longer tell whether a red or green result means anything.

- **The one good reason a test fails**: a real bug was uncovered in production code. Every other cause for failure is the test telling you not to trust it in its current form.

- **False positive vs false negative (test framing)**: a false positive is a failing test that isn't reporting a real problem (buggy test, stale test, conflicting test, flakiness). A false negative is a passing test that should have failed, usually because it asserts too little or nothing at all.

- **Logic in tests**: any `if`/`else`/`switch`, loop (`for`, `while`, `forEach`), string concatenation used to build an expected value, or `try`/`catch` inside a test body. Logic is a vector for bugs, and a bug in a test is worse than no test, because it hides behind a green (or wrongly red) result.

- **Repeating the algorithm under test**: when the test computes its expected value using the same formula the production code uses (e.g. `expect(result).toBe("hello" + name)` against `return "hello" + name`), a bug in the formula appears identically on both sides and the test can never catch it. The fix is a hardcoded expected value, not a derived one.

- **Exit point / concern**: a single observable result of a unit of work, a return value, a state change, or a call to a collaborator (from chapter 1's vocabulary). A test that asserts on more than one concern is testing more than one thing at once.

- **Assert-and-stop semantics**: most test frameworks throw on the first failed assertion and abort the test method there. If a test checks concern A then concern B, and A fails, you never learn whether B also failed. Multiple concerns in one test hide symptoms you need for diagnosis.

- **False-trust smell**: a passing test that shouldn't be trusted, and you don't yet know it. Distinct from an outright bug, it is a structural weakness (no assert, unreadable, mixed with flaky tests, multi-concern, constantly edited) that undermines confidence even while green.

- **Safe green zone**: a test area (folder, project, CI stage) that contains only fast, non-flaky tests, so that any red result there is treated as a real signal. Achieved by physically separating unit tests from integration/E2E tests, not by trusting developers to mentally filter out "the flaky ones."

- **Flakiness**: a test that returns inconsistent results with no change to the code under test. Caused by moving parts the test doesn't fully control: time, randomness, threads/concurrency, shared memory or shared external resources, network, filesystem, configuration, environment, or ordering dependence between tests. The higher a test sits on the test-level ladder (unit, component, integration, API, full end-to-end), the more real dependencies it drags in, and the more likely it is to flake, even though higher-level tests also buy more end-to-end confidence when green.

- **Fix, convert, or kill**: the triage loop for a flaky test once it's quarantined. Fix it by taking control of its dependencies (seed the database instead of hoping data exists). Convert it into a lower-level test by stubbing out the dependency that caused the flakiness. Kill it if the maintenance cost now exceeds the value it provides, resisting the sunk-cost instinct to keep it "because we already wrote it."

## Why tests fail (five causes, one legitimate)

1. **Real bug in production code.** Working as intended, this is the entire point of the test.
2. **Buggy test, false failure.** Wrong assertion, wrong exit point, wrong input to the entry point, or misuse of the system under test. Danger: the same bug class can also cause a false pass, which is worse because nobody investigates a green test.
3. **Test out of date.** Functionality changed underneath it (e.g. login moved from password to two-factor). Either update the test for the new behavior or delete it and write a fresh one. Don't leave a test asserting a contract the product no longer has.
4. **Test conflicts with another test.** Two tests can't both be right at once (one expects `f(2)` to be `3`, another expects it to be `4`). This isn't a bug to silently patch, it's a product decision: ask whoever owns the behavior which expectation is correct, then delete the other test.
5. **Flaky test.** Fails and passes with no code change. Treated separately (see below) because the fix is architectural, not a one-line correction.

Only cause 1 is good news. The rest are the test telling you, in the only language it has (red or wrong-green), that it can't currently be trusted.

### Recognizing and fixing a buggy test

When you can't find the bug in production code after real effort, suspect the test. Once you fix the test, don't stop at "it's green now." Verify the test can actually fail: deliberately break the production code (flip a boolean, off-by-one a comparison) and confirm the test goes red. Then revert the break and confirm it goes green again. Only trust the test once you've watched it fail for the right reason and pass for the right reason. This is exactly the red-green discipline TDD gives you for free, since you see both states by construction instead of having to manufacture them after the fact.

## Avoiding logic in unit tests

Logic sneaks into tests through four doors: conditionals, loops, string building for an expected value, and exception handling. Each one is a place a test author can introduce a bug that the test itself will never surface, because the test's grader (the logic) shares the same blind spot as the thing being graded.

**Dynamic expected values.** Building the expected value with the same operation the code under test performs duplicates the algorithm into the test:

```js
// smell: test recomputes the algorithm
expect(makeGreeting("abc")).toBe("hello" + "abc") // missing space bug survives

// trustworthy: hardcoded expectation
expect(makeGreeting("abc")).toBe("hello abc")
```

If the production code has a bug (missing separator, off-by-one, wrong operator), a dynamically-built expectation reproduces the same bug and the test stays green. Hardcode the expected value instead, even if that means the literal appears in two places (input and expectation). Trust outranks avoiding duplication. A DRY test you can't trust is worse than a repetitive one you can.

**Loops and branches over multiple inputs.** Looping over a table of inputs and branching on which assertion applies to each one packs several scenarios into a single test:

```js
// smell: one test doing three tests' jobs
["firstOnly", "first second", ""].forEach((name) => {
  const result = isName(name)
  if (name.includes(" ")) expect(result).toBe(true)
  else expect(result).toBe(false)
})
```

This has all the same problems as dynamic expected values, since the `if` mirrors the production logic. It adds new ones too. The test can't get a meaningful name because it covers multiple scenarios. A failure only tells you "something in the loop failed" rather than which case. Loops and conditionals are themselves code that can carry bugs. Split it into one small test per scenario, with a hardcoded input and a hardcoded expectation each.

**Logic in helpers.** The same risk applies to test utilities, hand-rolled fakes, and shared setup helpers, since a bug there silently corrupts every test that uses it. If a helper has any real logic, it earns its own tests.

**When some logic is unavoidable**, keep it out of unit tests specifically. Put dynamic, multi-path, or otherwise heavyweight tests in an integration-test area, name that area so it's obviously not the unit-test suite, and keep such tests to a deliberate minimum. A heavyweight test should be an addition alongside simpler unit tests, never a replacement for them.

## Smelling a false sense of trust in passing tests

A green suite isn't automatically a trustworthy one. Review passing tests for:

- **No asserts.** A test that runs code but checks nothing is closer to a smoke test than a unit test. If the intent is "doesn't throw," say so in the name and use the framework's explicit support for it (`expect(() => fn()).not.toThrow()` in Jest) rather than leaving an assert-free test that reads as an oversight. Keep this pattern rare. Watch for tests that exist purely to satisfy a coverage number. A coverage percentage is not a quality metric, and chasing it produces tests with no diagnostic value.

- **You can't understand the test.** Covered in depth later in the book (readability), but the symptom list is: bad names, long or convoluted bodies, confusing variable names, hidden assumptions, inconclusive results, unhelpful failure messages. If you can't read what a test checks, you can't judge whether its pass or fail means anything.

- **Unit tests mixed with flaky integration tests.** One rotten apple spoils trust in the whole run. When a failing test could plausibly be blamed on flakiness instead of a real bug, people under time pressure will take that excuse, especially when flaky and reliable tests share a folder or a single test command. The structural fix is a safe green zone: keep unit tests (fast, fully in-memory, deterministic) physically separate from integration/E2E tests, so a red result in the unit suite always means something. As a side benefit, developers run the faster, isolated suite more often.

- **Testing multiple exit points / concerns at once.**

```js
// smell: two concerns, one test
it("works", () => {
  const callback = jest.fn()
  const result = trigger(1, 2, callback)
  expect(result).toBe(3)
  expect(callback).toHaveBeenCalledWith("I'm triggered")
})

// trustworthy: one concern per test
it("triggers a given callback", () => {
  const callback = jest.fn()
  trigger(1, 2, callback)
  expect(callback).toHaveBeenCalledWith("I'm triggered")
})
it("sums up given values", () => {
  expect(trigger(1, 2, jest.fn())).toBe(3)
})
```

  Two costs follow. Naming gets harder, since a test covering multiple concerns can only get a generic name. And because most frameworks throw on the first failed assert and abort, a failure on the first concern hides whatever the second concern would have told you. Treat each failed assert as a diagnostic symptom. More symptoms make the underlying disease easier to find, but only if every relevant assert actually gets to run.

  This is not a ban on multiple asserts, only on multiple concerns. Asserting on several fields of the same constructed object (`result.name`, `result.age` from one `makePerson()` call) is fine, they're facets of one exit point. Rule of thumb: if the first assert fails, do you still care about the next one? If yes, keep them together. If no, split the test.

- **Tests that keep changing.** A test whose behavior depends on the current date/time, a random number, the machine name, or anything else pulled from outside the test's own environment is effectively a different test on every run. Beyond flakiness, dynamically generated inputs force you to also compute the expected output dynamically, reintroducing the "test repeats the algorithm" trust problem from the logic section above.

## Dealing with flaky tests

**Where flakiness comes from.** As tests move up the ladder from unit, to component, to integration, to API, to full end-to-end, they trade determinism for real-world confidence. Lower-level tests run in memory against fakes/stubs with fully predetermined state, so their execution path is close to static. A wrong result usually means the production logic actually changed. Higher-level tests pull in real databases, networks, configuration, and third-party services, each of which is a moving part outside the test's control, and each of which is a route to a false failure.

Common causes, roughly by level:
- **Unit/component level**: shared memory, threads, random values, dynamically generated inputs, wall-clock time, plain logic bugs in the test.
- **Integration/end-to-end level**: shared external resources, network issues, configuration drift, permission issues, load/timing issues, security layers, other systems being down, order dependence between tests.

Even isolated unit tests can flake if they secretly reach outside themselves, current date/time, machine name, filesystem, network, so the discipline of controlling every dependency applies at every level, not just at the top.

Flakiness also has a cost beyond wrong signals: dependencies like network, disk, and threads slow the run down, and diagnosing a flaky failure (trawling logs for a problem that won't reliably reproduce) burns disproportionate time.

**Handling flaky tests.**

1. **Define "flaky" for your team.** A concrete operational definition works well: run the suite N times (e.g. 10) with no production code changes. Any test that isn't consistently all-pass or all-fail across those runs is flaky.
2. **Quarantine.** Move flaky tests out of the main delivery build into their own pipeline/folder so they stop eroding the safe green zone, while you decide what to do with each one.
3. **Fix, convert, or kill each one:**
   - *Fix*: bring the dependency under the test's control (seed the exact data the test needs instead of assuming it's there).
   - *Convert*: drop the test to a lower level by replacing a real dependency with a stub or fake (simulate the network endpoint instead of calling it).
   - *Kill*: if a test's maintenance cost now exceeds its value, or newer tests already cover the behavior, delete it. Resist the sunk-cost instinct that treats "we already wrote it" as a reason to keep paying for it.

**Preventing flakiness in higher-level tests.** Make the test's effect on the world repeatable. Roll back any state changes it made to shared external resources. Never depend on another test having changed shared state first (order independence). Get real control over external dependencies, through infrastructure-as-code, dedicated test doubles, or isolated test accounts. Where an external dependency genuinely can't be controlled, consider removing higher-level tests already covered by lower-level ones, converting some to lower-level tests, or adopting a pipeline-friendly test-recipe strategy for new tests.

## Practical checklist

- Would a failure here worry you, and would a pass let you stop worrying? If not, the test needs work before its result means anything.
- Grep test bodies for `if`, `for`/`while`/`forEach`, string concatenation feeding an assertion, and `try`/`catch`. Each hit is a candidate for hardcoding or splitting.
- Does every assertion in the test cover the same exit point? If not, split by concern.
- Does the test read its input from the wall clock, `Math.random`, a hostname, the network, or the filesystem? If so, either fake that dependency or move the test out of the unit-test folder.
- Are unit and integration tests runnable, and reportable, separately? If a single command or folder mixes them, you don't have a safe green zone yet.
- For any flaky test found: define what counts as flaky for your team, quarantine it, then apply fix, convert, or kill. Don't leave it mixed into the trusted suite for now.
