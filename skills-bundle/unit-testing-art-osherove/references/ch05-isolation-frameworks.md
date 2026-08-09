# Chapter 5: Isolation frameworks

## Key Concepts

- **Isolation Framework**: A set of programmable APIs that create, configure, and verify mocks and stubs at run time, either as functions or as objects. The point is to replace the hand-written fakes from earlier chapters (custom variables, custom classes) with a library that generates the same behavior in a few lines. Definition to hold onto: "a reusable library that can create and configure fake objects at run time," producing what the book calls dynamic stubs and dynamic mocks.

- **Why "isolation" and not "mocking"**: The term "mocking framework" is common but misleading, since these libraries build both stubs and mocks. "Isolation framework" names the actual purpose: cutting the unit of work off from its dependencies so the test exercises only that unit.

- **Loose vs. Typed Frameworks**: Two flavors split along JavaScript's multi-paradigm nature.
  - *Loose (vanilla JS) frameworks*, Jest and Sinon, favor a functional style. Less ceremony, less boilerplate, good for module and function dependencies.
  - *Typed (TypeScript-friendly, object-oriented) frameworks*, such as substitute.js, generate fakes from an interface or class shape. Good for full objects and object hierarchies.
  Choice of flavor should follow the shape of what you are faking, not personal taste alone: modules and simple functions point to Jest, whole interfaces and class hierarchies point to something like substitute.js.

- **jest.mock(modulePath)**: Replaces an entire module with an auto-faked version. Must sit at the top of the spec file (JavaScript hoisting requires it) before requiring the module under test. After mocking, requiring the module returns fake functions you can configure or assert on.

- **jest.fn()**: Produces a single tracked fake function. Attach it to an object literal's methods to fake a small interface without writing a class. Every call is recorded so you can later assert with matchers like `toHaveBeenCalledWith`.

- **jest.spyOn**: Not shown in this chapter's listings but part of the same family conceptually, wraps an existing method so calls are tracked while (optionally) still invoking the original implementation. The chapter's own examples rely on `jest.fn()` and `jest.mock()`, which cover the two core needs: faking a whole module and faking one function.

- **Matcher**: A utility, such as `stringMatching`, that asserts on the shape of an argument rather than requiring an exact value. Lets a mock verification tolerate small changes in wording while still checking intent (for example, checking a logged string contains "PASS" rather than equals an exact sentence).

- **Substitute.for<T>()**: The substitute.js entry point. Generates a fake object that implements interface `T` without you writing any implementation. Configure return values with `.returns(...)`, verify calls with `.received()`, and match arguments loosely with `Arg.is(predicate)`.

- **Record-Replay vs. Arrange-Act-Assert**: Historical note. Early isolation frameworks (Java and C#, mid-2000s) used Record-Replay: put the fake into "record mode," call the methods you expect production code to call, switch to "replay mode," then run the real code. This was confusing and costly to read. Modern frameworks (Jest, substitute.js) fit naturally into Arrange-Act-Assert: build the fake, run the code, check what happened, in that order.

- **Command/Query Separation**: A design lens for reading dependency diagrams. An outgoing arrow that asks for data (a query, like `getLogLevel()`) is a candidate for a stub. An outgoing arrow that triggers an action with no return value used by the caller (a command, like `logger.info()`) is a candidate for a mock.

## Mocks vs. Stubs, Restated Through the Framework

- A **stub** simulates an incoming value so the unit of work under test can proceed down a particular path. You configure it, but you never assert against it directly.
- A **mock** verifies that an outgoing call happened correctly. You assert against it at the end of the test.
- The distinction does not change when a framework is introduced. What changes is only the cost of building the fake. Confusing the two (verifying calls on a stub, or configuring return values you then never check on a mock) is still a mistake, framework or not.

## Faking Modules Dynamically

When code has a hard-coded `require`/`import` on a module (rather than an injected dependency), you cannot hand it a fake object through a constructor or parameter. `jest.mock(path)` solves this by intercepting the module system itself.

```js
jest.mock("./complicated-logger");
jest.mock("./configuration-service");

const mockLoggerModule = require("./complicated-logger");
const stubConfigModule = require("./configuration-service");

test("info level logs PASSED", () => {
  stubConfigModule.getLogLevel.mockReturnValue("info");
  verifyPassword("anything", []);
  expect(mockLoggerModule.info).toHaveBeenCalledWith(/PASS/);
});
```

Two details matter here. First, `jest.mock` calls must be hoisted above any `require` of the module under test, or the fake will not be in place in time. Second, call `jest.resetAllMocks` (commonly in `afterEach`) so a stubbed return value or mock call history from one test does not leak into the next.

This approach is most valuable in legacy code, where the dependency cannot easily be refactored into an injected parameter. In code you control, faking the whole module glues your test to that module's exact API. When the third-party API changes, every test faking it directly breaks. The better long-term fix is to wrap the dependency behind a small internal adapter (ports and adapters, also called hexagonal or onion architecture) and fake the adapter instead. A breaking upgrade in, say, a logging library then touches one file rather than hundreds of tests.

## Functional Dynamic Mocks and Stubs

For a single injected function dependency, hand-rolling a mock means declaring a variable to capture the call, writing a fake function that assigns to it, then asserting on the variable:

```js
let logged = "";
const mockLog = { info: (text) => (logged = text) };
```

`jest.fn()` collapses this into one line and gives you a queryable call history for free:

```js
const mockLog = { info: jest.fn() };
verify("any input", mockLog);
expect(mockLog.info).toHaveBeenCalledWith(/PASS/);
```

This is the sweet spot for loose frameworks: one function, one line, no bookkeeping variables.

## Object-Oriented Dynamic Mocks and Stubs

A multi-method interface is where hand-written fakes get painful, since every method needs its own captured value and its own field on a fake class. `jest.fn()` still works here by attaching a tracked function to every method of an object literal:

```js
const mockLog = {
  info: jest.fn(),
  warn: jest.fn(),
  debug: jest.fn(),
  error: jest.fn(),
};
```

The tradeoff is that this object must be kept in sync with the interface by hand. Add a method to the interface and every test object needs the same addition, or code under test that calls the missing method will fail in confusing ways. Pushing this construction into a shared factory function reduces the blast radius to one place.

A typed framework removes the sync burden entirely. `Substitute.for<IComplicatedLogger>()` reads the TypeScript interface and builds a matching fake automatically:

```js
const mockLog = Substitute.for<IComplicatedLogger>();
verifier.verify("anything");
mockLog.received().info(Arg.is((x) => x.includes("PASSED")), "verify");
```

Because the fake is generated from the type, an interface change does not require touching every test that uses it, so long as the test only interacts with the methods it cares about.

## Stubbing Behavior Dynamically

Jest's stubbing API centers on a handful of chainable configuration calls on `jest.fn()`:

- `mockReturnValue(x)`: every call returns `x`. Preferred when one value covers the whole test, since it reads simplest.
- `mockReturnValueOnce(x)`: queues a value for exactly one call, chainable for a sequence (`mockReturnValueOnce("a").mockReturnValueOnce("b")`). Calls beyond the queued sequence fall back to `undefined` or to the persistent `mockReturnValue`, if one was also set.
- `mockImplementation(fn)` / `mockImplementationOnce(fn)`: replace the whole function body, needed when a return value alone will not do, most commonly to throw an error and exercise an error path.

```js
const stub = jest.fn().mockReturnValueOnce("a").mockReturnValueOnce("b");
stub(); // "a"
stub(); // "b"
stub(); // undefined
```

substitute.js mirrors this with `.returns(...)` on a stubbed call:

```js
const stubMaintWindow = Substitute.for<MaintenanceWindow>();
stubMaintWindow.isUnderMaintenance().returns(true);
```

A combined stub-and-mock test wires a stubbed incoming dependency (`MaintenanceWindow`, a query) together with a mocked outgoing dependency (`IComplicatedLogger`, a command), configuring the stub in Arrange, running the unit in Act, and verifying the mock in Assert. This is the same command/query split as section 5.2, just carried through to a richer example with a third collaborator.

## Advantages of Isolation Frameworks

- **Less modular boilerplate**: `jest.mock` removes the manual work of faking an entire module by hand.
- **Easier value and error simulation**: `mockReturnValue`/`mockImplementation` and substitute.js's `.returns` replace hand-written conditional fakes.
- **Easier fake creation generally**: both stubs and mocks get built with the same small API instead of bespoke classes.

## Traps of Isolation Frameworks

- **Reaching for mocks by default**: A unit of work has three possible exit points: a return value, a state change, or a call to a third-party dependency. Only the third benefits from a mock. Osherove reports mocks in roughly 2 to 5 percent of his own tests, with functional code trending toward near zero mock usage. Before writing a mock, ask whether the same behavior can be proven with a return value or an observable state change instead.

- **Unreadable tests from mock overload**: A single mock is still readable. A test with many mocks or many `.received()` assertions stops reading like a specification and starts reading like an implementation trace. When this happens, cut mocks you do not need or split the test.

- **Verifying the wrong thing**: Common misuses include asserting that one internal function called another internal function (not a real exit point), asserting on a stub instead of only configuring it (the overspecification trap below), or verifying a call just because "someone said to write a test" without confirming the requirement first.

- **More than one mock per test**: Each mock corresponds to one exit point, and testing more than one exit point in a single test conflates more than one requirement. Prefer one test per exit point so test names stay specific and failures stay easy to localize.

- **Overspecification**: Piling up `.received()` (or `toHaveBeenCalledWith`) checks makes a test brittle: it starts failing on production code changes that do not actually break behavior, because too many incidental interactions were pinned down. Two concrete countermeasures: keep mocks to a small share of the suite (the same 5 percent guideline as above) and never use a stub as a mock, meaning never assert that a stubbed method was called. A stub exists purely to feed a value in, not to be verified.

## Rule of Thumb: Which Kind of Fake, Which Kind of Framework

| Dependency shape | Framework flavor | Fake kind to reach for |
|---|---|---|
| Whole module (`require`/`import`) | Jest / Sinon | `jest.mock(path)` |
| Single function parameter | Jest / Sinon | `jest.fn()` |
| Multi-method interface, JS | Jest / Sinon | object literal of `jest.fn()` per method |
| Multi-method interface, TypeScript | substitute.js | `Substitute.for<T>()` |
| Incoming dependency (feeds a value in) | either | stub, configure only, never assert |
| Outgoing dependency (the exit point) | either | mock, assert with `.received()` / `toHaveBeenCalledWith` |

## Connections to Other Chapters

- **Earlier chapters (manual mocks and stubs)**: This chapter's every example is a direct rewrite of a hand-coded fake from before, showing the same test made shorter and less error-prone by a framework, not a new testing concept.

- **Chapter 6 of Khorikov's separate book, "Unit Testing Principles, Practices, and Patterns"**: Cited directly for a deeper treatment of converting interaction-based (mock-heavy) tests into simpler return-value or state-based tests.

- **Chapter 12 (legacy code, referenced ahead)**: Framework-based whole-module faking is flagged as most justified in legacy situations where refactoring toward dependency injection is not yet possible.

- **Part 3 of the book (referenced ahead)**: Promises deeper guidance on the dos and don'ts of isolation frameworks and on refactoring fake-object creation into shared helper functions, both only introduced briefly here.
