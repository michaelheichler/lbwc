# Chapter 3: Breaking dependencies with stubs

## Key Concepts

- **Dependency**: Anything external to the unit of work that the test cannot fully control: time, the filesystem, the network, random values, a database, another module. Dependencies make tests hard to write, hard to repeat, and prone to flakiness.

- **Outgoing dependency**: A dependency the unit of work calls as an exit point (calling a logger, saving to a database, sending an email, notifying a webhook). These are verbs, "calling," "sending," "notifying." The flow moves outward and ends there. Outgoing dependencies are broken with mocks, and a test should assert against at most one mock.

- **Incoming dependency**: A dependency that flows data or behavior inward to the unit of work (a query result, file contents, a network response) without being an exit point itself. Incoming dependencies are broken with stubs. A test can use many stubs, and stubs are never asserted against.

- **Test double**: The umbrella term (also called "fake") for any non-production stand-in used in a test. xUnit Test Patterns splits doubles into five named patterns, but for daily use two categories matter most.

  - **Dummy object**: A value passed only because a signature requires it, irrelevant to the test's outcome.
  - **Test stub**: Configured to return a canned value or behavior so the test can control an incoming dependency.
  - **Test spy / mock object**: A fake that records how it was called so the test can verify an outgoing dependency was invoked correctly.

- **Stub vs. mock, the short version**: Stubs break incoming dependencies and are never asserted on. Mocks break outgoing dependencies and are asserted on. The same fake object can act as a stub in one test and a mock in another, depending on which role the test cares about. Calling everything "a mock" is a common but confusing habit worth resisting.

- **Control**: The ability of a test to dictate how a dependency behaves before the code under test runs. Direct calls to a real dependency (like calling `moment()` inside the function) take control away from the test.

- **Inversion of control**: Restructuring code so that creating or fetching a dependency is no longer the unit of work's own responsibility, moving that responsibility outward to a caller.

- **Dependency injection**: Passing a dependency through a defined interface (parameter, constructor, factory) so the code under test uses whatever it's given rather than reaching out and grabbing it itself.

- **Seam**: A place in the code where a different behavior can be substituted without editing the code at that point, a term from Michael Feathers's *Working Effectively with Legacy Code*. Parameters, constructors, module loaders, and interfaces are all seams. More seams, and easier ones, make tests easier to write and maintain.

- **Flaky test**: A test whose result depends on something the test doesn't control (current date, network state, server load) so it passes or fails inconsistently without any code change. A test that only runs, or only asserts meaningfully, on weekends is a textbook flaky test.

- **Duck typing**: JavaScript's permissive typing lets any object with the right method names stand in for another, whether or not they share a formal type. A fake object and a real object both exposing `getDay()` are interchangeable at runtime with no shared base class required.

## Techniques for Breaking a Dependency

The chapter walks one running example, a password verifier that must reject weekend input, through the same fix expressed in progressively more structured styles. Every version does the same job: stop the unit of work from reaching out to `moment()` (or any real dependency) directly, and let the caller hand in a substitute instead.

### 1. Parameter injection (the baseline move)

Add a plain parameter carrying the value the dependency would have produced.

```js
const verify = (input, rules, currentDay) => {
  if ([SATURDAY, SUNDAY].includes(currentDay)) throw Error("weekend");
  return [];
};
```

The caller (the test) now owns the value and can hardcode any day it wants. This is the simplest seam available and technically already dependency injection: the "stub" here is just a dummy integer, which is fine, a stub doesn't need behavior to qualify, it just needs to be under the test's control.

### 2. Functional injection techniques

- **Function as parameter**: inject a function instead of a value, so the code calls `getDayFn()` instead of receiving a day directly. This keeps the door open for more complex fake behavior later (throwing, returning different values on successive calls) without changing the function's shape again.

- **Partial application / factory functions**: a higher-order function that closes over the fixed context (rules, the day function) and returns a smaller function that only needs the remaining input. The factory call becomes the test's arrange step, and the returned function becomes the act step.

```js
const makeVerifier = (rules, dayOfWeekFn) => (input) => {
  if ([SATURDAY, SUNDAY].includes(dayOfWeekFn())) throw Error("weekend");
};
```

- **Constructor functions**: the same idea with `new`, returning an object carrying methods instead of a bare function. A stepping stone toward class-based design without committing to `class` syntax.

### 3. Modular injection techniques

When the dependency is a direct `require`/`import` inside the module, there's no parameter to intercept. The workaround is to wrap the import in a swappable registry:

```js
const originalDependencies = { moment: require('moment') };
let dependencies = { ...originalDependencies };
const inject = (fakes) => {
  Object.assign(dependencies, fakes);
  return () => { dependencies = { ...originalDependencies }; }; // reset
};
```

Production code reads from `dependencies.moment()` instead of `moment()` directly. Tests call `inject({ moment: fakeImpl })`, run their assertions, then call the returned reset function to restore the real dependency.

This works, but it ties every test to the exact API shape of the thing being faked. When a third-party API changes (a logger, a date library), every test that hand-rolled a fake of its API has to change too, potentially hundreds of files. Two ways to limit the damage: wrap third-party dependencies behind an interim abstraction you own (Ports and Adapters / Hexagonal / Onion architecture, so only the adapter needs updating), or skip module injection altogether and prefer the parameter-based and constructor-based techniques instead.

### 4. Moving toward objects with constructor functions

A constructor function (`function Verifier(rules, dayOfWeekFn) { this.verify = ... }`, invoked with `new`) achieves the same injection as the factory function but returns a stateful object with a method, which some teams find a more natural fit for an object-oriented codebase.

### 5. Object-oriented injection techniques

- **Class constructor injection**: dependencies are passed into a class's constructor and stored as instance fields, then used by instance methods.

```js
class PasswordVerifier {
  constructor(rules, dayOfWeekFn) { this.rules = rules; this.dayOfWeek = dayOfWeekFn; }
  verify(input) {
    if ([SATURDAY, SUNDAY].includes(this.dayOfWeek())) throw Error("weekend");
    return [];
  }
}
```

A stateful class configured once (rules, dependencies) can be reused for many calls without repeating setup, unlike a pure function that needs every dependency passed on every call. For test maintainability, wrap construction in a small local factory function inside the test file (`const makeVerifier = (rules, dayFn) => new PasswordVerifier(rules, dayFn)`), so a future constructor signature change only requires editing one place instead of every test.

- **Object as parameter (duck typing)**: instead of injecting a bare function, inject an object exposing the needed method (`timeProvider.getDay()`). Production gets a `RealTimeProvider`, tests hand in a `FakeTimeProvider` built with a plain constructor function. Nothing formally links the two, JavaScript accepts the fake because it has the right shape, and any signature mismatch only shows up at runtime.

```js
function FakeTimeProvider(fakeDay) { this.getDay = () => fakeDay; }
const verifier = new PasswordVerifier([], new FakeTimeProvider(SUNDAY));
```

- **Common interface as parameter**: in TypeScript (or another statically typed language), define an interface both the real and fake implementations must satisfy, so the compiler enforces the contract instead of relying on duck typing at runtime.

```ts
export interface TimeProviderInterface { getDay(): number; }
export class RealTimeProvider implements TimeProviderInterface { getDay() { return moment().day(); } }
class FakeTimeProvider implements TimeProviderInterface { fakeDay = 0; getDay() { return this.fakeDay; } }
```

The constructor's parameter type becomes `TimeProviderInterface` rather than a concrete class, so any conforming object, real or fake, is accepted, and the compiler catches drift immediately instead of letting it surface as a runtime failure.

IoC/DI containers (Angular, Spring, Autofac, StructureMap) can wire these dependencies automatically, but the author deliberately skips them in the book. Manual construction through small factory functions is enough to get maintainable tests, and hand-written fakes are sometimes more readable than framework-generated ones.

## Patterns

- **Progression of injection styles**: parameter, then function-as-parameter, then factory/partial application, then constructor function, then class constructor, then object-as-parameter, then interface-as-parameter. Each step trades a bit more ceremony for a bit more structure or type safety. None of them is universally "correct," the right one depends on team background and language.

- **Two-object indirection for time**: rather than injecting a raw day integer everywhere, wrap "get the current day" behind a single-method object (`timeProvider.getDay()`). This groups all time-related fakery behind one seam and keeps the door open for adding more time operations later without touching every call site.

- **Test-side factory functions**: whenever construction takes more than one line or more than a couple of arguments, extract a small factory inside the test file. This is a test-maintainability move distinct from any production-code factory: it centralizes "how do I build a configured instance of the thing under test" so a constructor signature change is a one-line fix instead of a search-and-replace across every test.

- **Reset after inject**: any technique that mutates shared/module state to install a fake (the modular injection registry) must also provide a matching way to restore the original, called at the end of the test, so one test's fake doesn't leak into the next test.

## Common Pitfalls

- **Testing only when the condition happens to be true**: a test that checks the date at the top and skips its body unless it's currently the weekend is not "sometimes passing," it's "usually not running at all." A test that silently doesn't execute is worse than a failing test, because it gives false confidence.

- **Reaching for module injection first**: it looks like the obvious fix for a direct `require`, but it locks every test to the exact shape of the faked API. Prefer a parameter, function, or constructor seam when the design allows it, and reserve module injection (or better, an owned abstraction layer) for dependencies you genuinely cannot restructure around.

- **Confusing "mock" and "stub" in conversation**: saying "we'll mock this out" for what is actually a stub (an incoming dependency you never assert against) muddies communication with teammates. Reserve "mock" for things the test asserts were called, and use "stub," "fake," or "test double" for everything else.

- **Assuming duck-typed fakes are safe**: because JavaScript accepts any object with matching method names, a typo or signature drift between the real and fake implementation is only caught at runtime, if at all. If that risk matters, move to a shared interface in TypeScript so the compiler enforces the match.

- **Skipping the reset step**: forgetting to reset injected fake dependencies after a test leaves the fake installed for whichever test runs next, producing order-dependent failures that are hard to trace back to their source.

## Connections to Other Chapters

- **Chapter 1 (test qualities)**: this chapter's flaky weekend test is a direct violation of the consistency quality introduced earlier, the same test run twice should give the same result absent a code change.

- **Chapter 4 (interaction testing with mock objects)**: this chapter deliberately covers only the incoming-dependency half of test doubles. The next chapter picks up outgoing dependencies and shows how mocks assert on calls rather than just supply data.

- **Chapter 5 (mocking frameworks)**: referenced here as the place where tools like Jasmine, Jest's mock functions, or Sinon will automate the hand-written fakes shown in this chapter, once the underlying concepts are solid.

- **Chapter 8 (design for testability)**: the chapter repeatedly defers deeper architectural discussion (Ports and Adapters, SOLID's Dependency Inversion) to chapter 8, treating this chapter's techniques as the concrete injection mechanics that a later design discussion builds on.
