# Chapter 4: Interaction testing using mock objects

## Key Concepts

- **Interaction Testing**: Checking how a unit of work talks to a dependency it does not control, that is, what calls it makes and what arguments it sends. This targets the third kind of exit point a unit of work can have: a call out to a third-party function, module, or object. (The other two kinds, covered in earlier chapters, are a returned value and a state change.) Interaction testing matters because third-party functions rarely expose a way to check "was I called correctly," so the only way in is to intercept the call itself.

- **Mock vs. Stub (the core distinction)**: The difference is about the direction data flows and what you do with the fake afterward.
  - **Mock**: A fake module, object, or function that stands in for an *outgoing* dependency, one your unit of work calls to produce a result. A mock is meaningful only if the test asserts against it at the end. If nothing checks that the mock was called correctly, it was never a mock at all, just an unused stand-in. A mock represents an exit point in the test.
  - **Stub**: A fake that stands in for an *incoming* dependency, one that feeds data or behavior into the code under test. Stubs are never asserted against directly. They are waypoints the data passes through on its way to the real outcome, not the outcome itself.
  - Rule of thumb: many stubs per test is fine, but keep it to one mock per test. Multiple mocks in a single test usually means the test is checking more than one requirement at once.

- **Why the mock/stub naming discipline matters**: Conflating the two produces tests that are harder to read (the test name stops telling you everything that happens), harder to maintain (you might accidentally assert against a stub, coupling the test to an implementation detail instead of an observable outcome), and less trustworthy under failure. Most test frameworks stop executing a test at the first failed assertion. If you stuffed several mock verifications into one test, an early failure hides whether the later ones would also have failed. Gerard Meszaros calls this **assertion roulette**: you are gambling on which assertion happens to fail first, and you lose visibility into the rest.

- **"Fake" as the umbrella term**: Use "fake" (or "test double") for any stand-in object regardless of role. Name a specific instance `mockXxx` only when the test will assert against it, and `stubXxx` (or nothing special) when it merely feeds input. A class meant to be reused as either a stub in one test and a mock in another is best named `FakeXxx`, not `MockXxx` or `StubXxx`, since the name should describe the class's nature, not its role in one particular test.

- **Seams for injecting fakes**: A seam is a place in the code where two pieces meet and can be redirected without editing the code at that point. The chapter categorizes the standard injection techniques into four styles, listed in the table below.

| Style | Technique |
|---|---|
| Standard | Introduce a parameter |
| Functional | Currying, or converting to a higher-order function |
| Modular | Abstract the module dependency behind an indirection object |
| Object-oriented | Inject an untyped object, or inject a typed interface |

- **Standard style (introduce parameter)**: Add the dependency (for example a `logger`) as a plain function parameter instead of importing it directly inside the function body. This removes the hard `require`/`import` coupling and lets the test pass in whatever object satisfies the shape the function actually uses (duck typing). The fake need not implement the full real interface, only the methods the code under test calls.

```js
const verifyPassword = (input, rules, logger) => {
  const failed = rules.map(r => r(input)).filter(r => r === false);
  logger.info(failed.length === 0 ? 'PASSED' : 'FAIL');
  return failed.length === 0;
};
```

- **Modular style**: When a module hard-imports its dependencies at the top of the file, wrap those dependencies in an internal indirection object (for example `dependencies`), and export two extra functions from the module: one to override entries in that object (`injectDependencies`) and one to restore the originals (`resetDependencies`). Tests inject fakes before running and must call the reset function afterward (typically in `afterEach`), or state leaks between tests. This approach adds real production code complexity purely to make the module testable, which is the trade-off to weigh against simply switching to parameter injection.

- **Functional style, currying**: Reorder a function's parameters so the dependencies come first, then wrap it in a curry helper (such as lodash's `_.curry`). Calling the function with only the dependencies returns a partially applied function that closes over them, and the caller (production code or test) later supplies the remaining argument(s). This documents, in the call itself, both how the function is meant to be used and what its dependencies are.

- **Functional style, higher-order functions (no currying)**: Write an explicit factory function that takes the dependencies and returns a new function closing over them, without relying on a currying library. The test calls the factory once to get a preconfigured function, then invokes that function with the remaining input.

```js
const makeVerifier = (rules, logger) => (input) => {
  const failed = rules.map(r => r(input)).filter(r => r === false);
  logger.info(failed.length === 0 ? 'PASSED' : 'FAIL');
  return failed.length === 0;
};
```

- **Object-oriented style, untyped object injection**: Pass dependencies through a class constructor and store them on the instance. The constructor makes the dependency mandatory (as opposed to an optional property set after construction), which is a deliberate design signal: "you cannot use this object correctly without providing this." In plain JavaScript, the fake just needs the methods that get called, nothing more, thanks to duck typing.

- **Object-oriented style, typed interface injection**: In TypeScript, define an interface (for example `ILogger`) as part of production code, have the real implementation implement it, and have the class under test depend only on the interface type, not the concrete class. The class under test never references the real implementation, so tests can supply a hand-written class implementing the same interface. Convention: prefix an interface name with `I` only when it exists to support polymorphism (multiple implementations expected). An interface used purely as a typed parameter bag does not need the prefix.

- **Dealing with complicated interfaces**: A dependency interface with many methods and many parameters per method turns every test's fake into a wall of boilerplate, since a typed fake must implement every member of the interface even if the test only cares about one. This gets worse the larger and more third-party the interface is. Two downsides beyond boilerplate: verifying arguments across many methods gets cumbersome, and depending on a large or third-party interface makes tests brittle to changes you do not control. Guidance: only build fake interfaces you (a) control and (b) have shaped to the exact needs of the unit of work, not to the shape of some external API.

- **Interface Segregation Principle (ISP)**: When forced to depend on a large interface, define a small adapter interface containing only the subset of functionality your code actually needs, with better names and fewer parameters, and have production code depend on that narrow interface instead. Changes to the underlying complicated dependency then only ripple into one adapter implementation, not into every test.

- **Partial Mocks**: Instead of building a fake from scratch, take a real object and override just the specific method(s) you need to intercept. In JavaScript this can be as simple as reassigning a method on an instance. The rest of the object keeps its real behavior and real dependencies. This produces a hybrid: some behavior is genuine, some is faked. It is more brittle and can make a test harder to reason about, but it is a pragmatic tool for legacy code where extracting a clean seam is not (yet) feasible.

```js
const testableLog = new RealLogger();
let logged = '';
testableLog.info = (text) => { logged = text; };
```

- **Partial mock via inheritance (Extract and Override)**: Create a subclass of the real dependency class purely for test purposes, override only the method(s) under scrutiny, and leave the rest inherited and real. Name such a class `TestableXxx` (not `MockXxx` or `FakeXxx`) to flag that it is a real/fake hybrid rather than a pure fake, and keep it living next to the tests, not in production code. This is Michael Feathers' Extract and Override technique from *Working Effectively with Legacy Code*. It requires the target class and method to actually be overridable, an explicit design constraint in class-based OO languages like Java or C#, less of an issue in JavaScript.

```js
class TestableLogger extends RealLogger {
  logged = '';
  info(text) { this.logged = text; }
}
```

---

## Patterns

- **Pattern: Name the fake after its role, not just its type.** `mockLog` tells the reader an assertion is coming, `stubLog` or a plain descriptive name tells the reader it is only feeding data in. Reserve `FakeXxx` class names for a fake reused as either role across different tests, and `TestableXxx` for a real/fake hybrid built via inheritance or property override. Consistent naming lets a reader understand a test's full contract from its variable names alone, without reading the test body.

- **Pattern: One mock per test.** If a test setup wants to assert against more than one collaborator's calls, that is a signal the test (or the unit of work) is doing more than one job. Split the test, or reconsider whether the second "mock" is actually just an incidental side effect that should be a stub instead.

- **Pattern: Prefer the narrowest seam that solves the problem.** Standard parameter injection is the simplest and should be the default. Reach for modular indirection objects only when a hard `require` cannot be avoided some other way. Reach for a full class-based interface only when the target language and its typed guarantees are already central to the design. Reach for partial mocks and Extract and Override only when working with legacy code that resists cleaner seams.

- **Pattern: Shrink dependencies to what you need, not what exists.** Under the interface segregation principle, define the fake's contract from the consumer's actual usage, not by copying a third-party or legacy interface wholesale. A four-method logger interface your code calls once should be adapted down to the one method you need before it reaches your tests.

- **When to recognize interaction testing is needed**: The unit of work's meaningful outcome is a call to something external (an email sender, a logger, a payment gateway, an event bus) rather than a return value or an observable state change. If you cannot express "did this happen correctly" as an assertion on a return value, you need a mock at that exit point.

- **When mocking is the wrong tool**: If the dependency's result flows back into the unit of work and affects its return value or state, that dependency is an *incoming* one and calls for a stub, not a mock, even if it is also technically "faked." Asserting against a stub (checking that a database query happened, for instance, rather than checking how the application's output changed given the data returned) couples the test to internals and produces little value.

---

## Common Pitfalls

- **Asserting against a stub.** If a fake exists only to feed data into the code under test, do not add an expectation against it. That conflates a waypoint with an exit point and increases coupling between the test and internal implementation.

- **More than one mock in a test.** This is usually a sign of testing multiple requirements at once, and it opens the door to assertion roulette: a failure in the first mock's assertion hides whether the second would have failed too, since most frameworks halt the test at the first thrown assertion.

- **Calling everything "mock."** Frameworks and casual usage often label any fake a "mock," including things that are functionally stubs. This blurs the mock/stub distinction the chapter treats as central to test readability and trustworthiness. Prefer precise naming, and note that newer JavaScript tools (Sinon, testdouble) and .NET tools (NSubstitute, FakeItEasy) push back against the historical sloppiness of frameworks like Mockito and jMock.

- **Depending on a large, external interface directly in tests.** Doing so drags in a pile of boilerplate to satisfy methods you never call and makes tests brittle to changes in an interface you do not own. Segregate down to a small, purpose-built interface instead.

- **Forgetting to reset injected modular dependencies.** In the modular injection style, skipping the reset step (typically wired into `afterEach`) after a test lets an injected fake leak into later tests, producing order-dependent failures that are hard to trace back to their cause.

- **Reaching for partial mocks or Extract and Override as a first choice.** Both techniques mix real and fake behavior in one object, which is more brittle and harder to reason about than a clean fake built through parameter, functional, modular, or interface injection. They are legitimate tools for legacy code that resists a cleaner seam, not a default habit.

---

## Connections to Other Chapters

- **Chapter 3**: Established stubs, the incoming-dependency counterpart to this chapter's mocks, and introduced the seam-based injection techniques (parameter, currying, modular abstraction) that this chapter reapplies to mocks. The refactoring moves for extracting a stub dependency and extracting a mock dependency are treated as essentially the same maneuver.

- **Chapter 1**: Defined the three types of exit points a unit of work can have (return value, state change, third-party call), of which this chapter covers the third.

- **Chapter 5 (Isolation frameworks)**: Picks up where the boilerplate of hand-written fakes for complicated interfaces becomes painful, and introduces frameworks that automate fake and mock creation. Also promises a fuller example of the interface segregation principle in action.

- **Chapter 12 (Legacy code)**: Where partial mocks and the Extract and Override technique see their heaviest real-world use, isolating existing, hard-to-seam code from its dependencies without a full rewrite.

- **General theme**: This chapter completes the isolation toolkit started with stubs. Stubs handle data flowing in, mocks handle calls and their arguments flowing out, and both rely on the same family of seams (parameter, functional, modular, object-oriented) to get a fake into the code under test.
