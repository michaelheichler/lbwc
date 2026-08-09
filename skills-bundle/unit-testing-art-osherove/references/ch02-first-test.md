# Chapter 2: A first unit test

## Key Concepts

- **Jest**: An open source JavaScript test framework, originally built at Facebook for React component testing, now used broadly for frontend and backend code. It is one of a handful of frameworks that is "all in one": it plays the role of test library, assertion library, test runner, and test reporter at once. It also ships isolation facilities (mocks, stubs, spies) covered in later chapters. It supports two syntaxes side by side: a flat `test()` style and a nested, Jasmine-derived `describe()`/`it()` style.

- **The four framework roles (library, assert, runner, reporter)**: Most languages bundle all four into one xUnit-style framework. JavaScript's ecosystem is more fragmented, many tools cover only one or two roles and get combined by hand. Jest's appeal for learning unit testing patterns is that it covers all four, so the tooling stays out of the way of the patterns being taught.
  - *Library*: the functions used to declare a test (`test`, `describe`, `it`).
  - *Assert*: the expectation API (`expect(...).toEqual(...)`, `.toContain(...)`, etc.).
  - *Runner*: the process that discovers test files, executes them, and tracks pass/fail.
  - *Reporter*: the human-facing (or CI-facing) summary of what ran, what failed, and why.

- **What a framework buys you over hand-rolling one**: structure (every test starts from the same recognizable shape), repeatability (writing and running new tests is cheap and fast, so more of the risky, boring code gets tested instead of skipped under time pressure), confidence (a mature, widely used framework has far fewer bugs than a framework you just wrote), and shared understanding (a green test suite is a legible signal to the whole team, not just the author).

- **xUnit lineage and TAP**: The "xUnit" family (JUnit, NUnit, CppUnit, HUnit, and others) traces back to SUnit for Smalltalk and standardized both test structure and an XML report format that build tools like Jenkins still consume natively. TAP (Test Anything Protocol) is a separate, older reporting convention from the Perl world with implementations across many languages. Jest follows neither convention by default. When a project's CI expects xUnit or TAP output, an extra reporter package (for example `jest-xunit` or `jest-tap-reporter`) has to be wired in through `jest.config.js`.

- **Arrange-Act-Assert (AAA)**: The default shape of a unit test. Arrange sets up the inputs and any fakes or doubles the scenario needs. Act invokes the one entry point being tested. Assert checks the single exit point of interest. Naming these three parts out loud ("the arrange part is too complicated," "where's the act?") is a fast way to critique a test's structure in review.

- **USE naming**: A mnemonic for test names: **U**nit under test, **S**cenario (the input or condition), **E**xpectation (the resulting behavior). A well-named test lets a reader diagnose a CI failure from the test name alone, without opening the file, because build output typically shows only the name, not the body or any comments.

- **String assertions and brittleness**: Prefer `toContain()` or a partial regex match (`toMatch(/fake reason/)`) over exact string equality when the assertion target is user-facing text. Strings act as a UI: their edges tend to shift over time (extra whitespace, punctuation, prefixes) even when the core meaning hasn't changed. An exact-match test fails on cosmetic edits that have nothing to do with a real regression, which erodes trust in the suite.

- **describe() as structural sugar**: `describe()` groups related tests, nests to express "unit -> scenario -> expectation" as levels of the tree, and produces cleaner CLI reports. `it()` is a plain alias for `test()`, kept distinct only because it reads more naturally as a sentence continuation of the enclosing `describe()` blocks ("describe verifyPassword... it returns errors"). Neither syntax is objectively superior. Mixing them by feel across a codebase is normal.

- **Scroll fatigue**: The cost of extracting shared state into `beforeEach()` blocks, especially nested ones. A reader of an `it()` block can no longer tell where a variable was created or what it was configured with without scrolling up through one or more enclosing `beforeEach()`s. As the number of scenarios grows, `beforeEach()` blocks accumulate unrelated setup from many contributors and become "the garbage bin of the test file."

- **Factory methods vs. beforeEach()**: A factory function (e.g. `makeVerifierWithFailedRule(reason)`) builds a fully configured object in one call, expressed inline inside each `it()`. This trades a small amount of literal duplication (one factory call per test) for a large gain in locality: everything relevant to a given test is visible in that test, with no need to hunt through ancestor `beforeEach()` blocks. The author's stated preference is factory methods over `beforeEach()` once a scenario list grows past a couple of cases.

- **Assertion roulette**: A term from Gerard Meszaros's *xUnit Test Patterns* for the failure mode where multiple assertions live in one test and the first failure hides whether the later ones would have passed. The fix is not to comment assertions out to test the rest one at a time. The fix is to split them into separate, independently named tests that each check one exit point.

- **Parallel test execution and shared state**: Jest runs test files in parallel by default. A value hoisted to a shared, mutable variable at a high `describe()` scope (rather than freshly created per test) risks cross-contamination between concurrently running tests. Frameworks in other ecosystems that default to single-threaded execution don't have this hazard the same way, so Jest users have to design setup with parallelism in mind from the start.

- **Parameterized tests (`test.each` / `it.each`)**: Jest's built-in mechanism for running one test body against a table of inputs (and optionally expected outputs), avoiding copy-pasted near-identical test cases. Takes an array of values, or an array of arrays for multiple parameters per row, and interpolates them into the test name via `%s`-style placeholders. A hand-rolled equivalent is not hard to write in plain JavaScript (loop over an object of input/expected pairs and call `test()` inside the loop). Jest's version is a convenience, not a unique capability.

- **Parameterization discipline**: Parameterize only the *input* values for a single scenario, not different scenarios with different expected outcomes crammed into one table. A table mixing "no uppercase -> fails" with "has uppercase -> passes" is two distinct scenarios and should be two tests (or two separate `test.each` tables). Collapsing them saves lines but costs readability and makes the intent of each row harder to see at a glance.

- **Testing thrown errors**: Wrapping a call in `try/catch` and manually failing the test if no exception was thrown works but is verbose. Jest's `expect(() => fn()).toThrowError(/pattern/)` is the built-in, terser equivalent, and using a regex (rather than an exact string) keeps the assertion resilient to minor message wording changes, the same brittleness argument as `toContain()` for strings.

## Practical Setup Notes

- A Jest project needs Node.js and npm (or Yarn), a `package.json` (Jest reads config from it or from `jest.config.js`), and `npm install --save-dev jest`. A global install (`npm install -g jest`) is convenient for ad hoc runs but real projects invoke Jest through an npm script.
- Jest auto-discovers tests in a `__tests__` folder (any filename) or any `*.test.js` / `*.spec.js` file anywhere under the project root. No `require()` is needed for `test`, `describe`, `it`, or `expect`. Jest injects them as globals.
- `jest --watch` reruns tests affected by filesystem changes without a full reinitialize each time. `--watchAll` is the fallback when the project isn't a git repo, since watch mode relies on git to determine what changed.
- Jest has no built-in notion of test categories (unit vs. integration, etc.). The workaround is either the `--testPathPattern` CLI flag or multiple `jest.config.js` files (each with its own `testRegex`), invoked through separate npm scripts.

## Example: the Password Verifier

The book's running example across the rest of part 1 is a small password verification library. Version 0 is a single function that takes an input and a list of rule functions, each returning `{ passed: boolean, reason: string }`, and collects error messages for every failed rule:

```js
const verifyPassword = (input, rules) => {
  const errors = [];
  rules.forEach(rule => {
    const result = rule(input);
    if (!result.passed) errors.push(`error ${result.reason}`);
  });
  return errors;
};
```

A minimal first test, before any structure or naming discipline is applied:

```js
test('badly named test', () => {
  const fakeRule = input => ({ passed: false, reason: 'fake reason' });
  const errors = verifyPassword('any value', [fakeRule]);
  expect(errors[0]).toContain('fake reason');
});
```

Applying USE naming and `describe()` nesting turns this into something closer to what a team would keep in a codebase long term:

```js
describe('verifyPassword', () => {
  describe('with a failing rule', () => {
    it('returns errors', () => {
      const fakeRule = input => ({ passed: false, reason: 'fake reason' });
      const errors = verifyPassword('any value', [fakeRule]);
      expect(errors[0]).toContain('fake reason');
    });
  });
});
```

The chapter later refactors the function into a stateful `PasswordVerifier` class (`addRule`, `verify`), which widens the unit of work to two coupled methods and motivates the `beforeEach()` vs. factory-method comparison, and adds an `oneUpperCaseRule` example used to demonstrate parameterized tests and thrown-error checks.

## Design Progression Illustrated in the Chapter

The chapter walks through the same small set of scenarios (failing rule, passing rule, mixed rules) through five successive test-organization styles, in this order, each fixing a problem in the previous one while introducing a new cost:

1. **Flat, duplicated `it()` blocks**: correct but repeats the same three or four setup lines in every test.
2. **Nested `beforeEach()`**: removes duplication but forces the reader to scroll up through multiple ancestor blocks to see what state a given `it()` is working with (scroll fatigue), and risks parallel-test interference if shared state is hoisted too high.
3. **`beforeEach()` plus small factory helpers** (`makeFailingRule`, `makePassingRule`): trims the noise inside `beforeEach()` but keeps the scroll-fatigue problem.
4. **Factory methods only, no `beforeEach()`** (`makeVerifierWithFailedRule`, `makeVerifierWithPassingRule`): each `it()` calls a factory inline, so everything relevant to that test is visible without scrolling, at the cost of one repeated factory call per test.
5. **Flat `test()` with long descriptive names, no `describe()` at all**: the leanest form, viable once each test is already self-contained through factories. At that point `describe()` becomes optional structure rather than a load-bearing part of the test.

The chapter does not declare a single winner. It frames the choice as a tradeoff between structure/readability and terseness that should be made per project. It leans toward factory methods over `beforeEach()` as the default preference once a scenario has more than one or two tests attached to it.

## Common Pitfalls

- **Exact string equality on user-facing text**: breaks tests on harmless wording or whitespace changes. Use `toContain()` or a partial regex instead.
- **Cramming multiple assertions into one test (assertion roulette)**: the first failure masks whether later assertions would pass. Split into one test per exit point.
- **Forgetting that Jest runs tests in parallel**: shared mutable state declared at a high `describe()` scope can be clobbered by a concurrently running sibling test. Prefer state created fresh inside each test or its own `beforeEach()`, not shared across scenarios.
- **Letting `beforeEach()` accumulate unrelated setup over time**: without discipline it becomes a dumping ground that nobody wants to prune, since removing a line risks breaking a test nobody remembers depends on it.
- **Parameterizing across different scenarios in one table**: a `test.each` table that mixes distinct expected behaviors (not just distinct inputs to the same expected behavior) hides the fact that two different things are being tested.
- **Reaching for Jest snapshot testing as a default**: `toMatchSnapshot()` is easy to write but tends to assert on far more than the scenario cares about, breaks for unrelated reasons, and can become an excuse to avoid writing a real, readable assertion.
- **Using `try/catch` with a manual `fail()` call to test thrown errors**: works, but `fail()` is an undocumented leftover from Jest's Jasmine ancestry. Prefer `expect(() => fn()).toThrowError(/pattern/)` instead, it is shorter and part of the supported API.

## Connections to Other Chapters

- **Chapter 1 (home-grown framework)**: this chapter's opening motivation is the contrast with a hand-rolled test framework built in chapter 1. Jest is presented as what you get once you stop reinventing structure, running, and reporting yourself.
- **Chapter 3 (breaking dependencies with stubs)**: picks up the Password Verifier project and introduces code with real dependencies, moving from pure functions and fakes into stubs, spies, and mocks.
- **Chapters 7 through 9**: referenced as the place where the deeper question of what makes a test readable, maintainable, and trustworthy gets treated properly. Using a framework does not by itself guarantee any of those properties.
