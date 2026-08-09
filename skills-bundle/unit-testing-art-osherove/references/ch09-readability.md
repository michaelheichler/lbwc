# Chapter 9: Readability

## Key Concepts

- **Readability**: The property that lets a developer who did not write a test understand what it does and why it failed, without reading the test's internal code. A test suite is executable documentation. If a newcomer cannot infer how a component behaves purely from reading its test names and bodies, the suite has a readability problem.

- **Test Name as Contract**: A well-formed test name carries three pieces of information: the entry point (unit of work or feature under test), the scenario (the input or condition being exercised), and the expected exit behavior (what should happen). Missing any one of the three forces the reader to open the test body to answer a question the name should have answered. This matters most in CI logs, where a failed build often shows only the test name, not its source or comments.

- **Naming Structure Options**: The three pieces of information can be encoded several ways: a single flat name joined by underscores (`entryPoint_scenario_expectedBehavior`), a comma-separated sentence inside one `test()` call, or nested `describe` blocks (outer for entry point, inner for scenario, `it` for expected behavior). The mechanism does not matter, only the presence of all three pieces does.

- **Magic Value**: A hardcoded literal (number, string, empty collection) whose meaning is not obvious from context and requires the reader to open the called function's signature or implementation to decode. Magic values are a readability tax paid by every future reader. They also propagate: once a reader copies a magic value into a new test out of caution, the meaningless value spreads through the suite.

- **Naming a Magic Value**: Replace a bare literal with a well-named constant (`const SUNDAY = 0`) when the value's specific identity matters to the test. When the value's specific identity does *not* matter (any string would do), rename it to say so explicitly (e.g. `"anything"`) rather than leaving a suspiciously specific-looking placeholder. Naming is not only about explaining what matters, it is also about telling the reader what they may safely ignore.

- **Act/Assert Separation**: Calling the method under test and asserting on its result in a single expression (`expect(fn()[0]).toContain(x)`) compresses two ideas (the action and the check) into one line. It is harder to read, and harder to debug because there is no intermediate variable to inspect when the assertion fails. Splitting the call from the assertion (`const result = fn(); expect(result[0]).toContain(x)`) costs one extra line and buys clarity and debuggability.

- **Setup (beforeEach) Overuse**: Placing mock or stub creation inside a `beforeEach` hides the existence and configuration of test doubles from anyone reading an individual test further down the file. The reader must scroll back to the top of the file, find the hook, and mentally merge its state with the test body. As a file accumulates tests, the shared setup hook tends to accumulate unrelated state for different tests, becoming a dumping ground that is hard to reason about.

- **Inline Construction Over Shared Setup**: Creating mocks, stubs, and the object under test directly inside each test body keeps every fact a reader needs local to that test. The cost is some duplication across tests.

- **Helper-Function Extraction**: When inline construction becomes repetitive, extract a plain helper function (e.g. `makeMockLogger()`) and call it explicitly from each test. This keeps the readability benefit of "everything relevant is visible in the test, one function call away" while removing duplication, in contrast to a `beforeEach` hook, which hides the construction from the test entirely rather than just naming it.

## Techniques

- **Technique 1 (Three-Part Test Names)**: For every test, verify the name states what is being tested, under what condition, and what the expected result is. If a reader would have to open the test body to answer "what is this testing," rewrite the name.

```js
// vague, missing scenario and expectation
test("verifyPassword", () => { ... });

// carries entry point, scenario, expected behavior
test("verifyPassword, with a failing rule, returns error from rule.reason", () => { ... });
```

- **Technique 2 (Kill Magic Values)**: Scan a test for bare literals passed as arguments. For each one, ask whether its specific value matters to the scenario. If yes, bind it to a well-named constant. If no, replace it with a value whose name announces its irrelevance.

```js
// reader must guess what 0 and [] mean
verifyPassword("jhGGu78!", [], 0);

// reader sees day-of-week and rule-count intent immediately
const SUNDAY = 0, NO_RULES = [];
verifyPassword("anything", NO_RULES, SUNDAY);
```

- **Technique 3 (Split Act From Assert)**: Never chain the call under test directly into the assertion expression. Assign the result to a local variable first, then assert on the variable. This also gives you a natural breakpoint target when debugging a failing test.

```js
// act and assert fused, no place to inspect the intermediate value
expect(verifier.verify("x")[0]).toContain("fake reason");

// act and assert separated
const result = verifier.verify("x");
expect(result[0]).toContain("fake reason");
```

- **Technique 4 (Prefer No Shared Setup)**: Default to constructing mocks and the unit under test inside each test body. Reach for `beforeEach` only when the state is truly identical and trivial across every test in the file, and be ready to abandon it the moment tests start needing different flavors of the same mock. If duplication grows painful, extract a named helper function and call it explicitly per test rather than hiding it in a hook.

## Common Pitfalls

- **Trusting the Test Body to Explain the Name**: Writing a short, vague test name on the assumption the reader will just read the code. This fails exactly when it matters most, when a CI pipeline reports a failure and shows only the name.

- **Reusing a Magic Value "to Be Safe"**: Once one test uses a suspiciously specific literal, later tests copy it verbatim without knowing why, because the reader assumes the specific value must matter. This is how magic values spread through a suite.

- **Long Fused Act/Assert Lines**: A single line that both invokes the unit of work and asserts on a nested piece of its return value is hard to scan and offers no intermediate value to inspect under a debugger.

- **Dumping-Ground beforeEach**: A `beforeEach` that grows over time to hold mocks and state for many unrelated tests becomes a shared mutable blob nobody fully understands, and readers lose the ability to reason about a single test in isolation.

## Connections to Other Chapters

- The chapter's guidance on splitting act from assert echoes the general Arrange-Act-Assert test structure used throughout the book. Readability here means making the AAA boundaries visually explicit, not collapsing them.

- The recommendation against shared `beforeEach` setup interacts with test isolation concerns covered elsewhere in the book, isolated tests are also more readable tests, because nothing about a test's behavior depends on state assembled outside its own body.

## Summary

- Name every test with its entry point, its scenario, and its expected exit behavior. All three, every time.
- Never leave an unexplained literal in a test. Either name it, or name its irrelevance.
- Keep the action and the assertion on separate lines.
- Avoid `beforeEach` setup for mocks and stubs. Construct them in the test, or in a helper function called from the test, so nothing relevant is hidden from the reader.
