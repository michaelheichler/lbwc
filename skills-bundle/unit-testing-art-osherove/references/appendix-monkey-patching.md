# Appendix: Monkey-patching functions and modules

## Key Concepts

- **Monkey-patching**: Changing the behavior of a running program instance at run time by reassigning a function, a global, or a module's exported members to something other than their original implementation. In JavaScript this is trivial because functions are just properties of objects, so `Date.now = () => fixedTime` works anywhere `Date` is reachable. The appendix treats this as a last resort technique, not a first choice, because it degrades the maintainability and readability that the book's "accepted" stubbing techniques (parameters, dependency injection, seams) protect.

- **Why it is dangerous**: A monkey-patched global is shared, mutable state. Any test that patches it can leak the patch into other tests if cleanup does not run, and cleanup is easy to skip because a failed assertion throws and can abort the test before a manual restore line executes. Patching also blocks safe test parallelism, since two tests racing to set and read the same global can interleave and corrupt each other's expectations. Jest mitigates this by isolating each test file's module registry, but the risk returns the moment another framework or another Jest process shares state.

- **When it is a legitimate necessity**: Faking a dependency you cannot change (vendored code, a third-party module exposing bare functions instead of an injectable object), or dealing with code that runs immediately on import/require and offers no seam to inject a replacement. Outside of these cases, prefer parameterizing the function or restructuring the code so the dependency can be passed in explicitly.

- **Cleanup discipline**: Any manual monkey-patch needs a guaranteed restore step. Saving the original reference in a `beforeEach` and restoring it in `afterEach` is safer than doing it inline in the test body, because `afterEach` still runs even when an assertion inside the test throws. This does not fix cross-file parallelism risk, only within-file ordering.

- **Spy (Jest's definition)**: A spy wraps a real function with a tracking layer on its entry and exit points without changing what the function does. It exists purely to record inputs and outputs for later verification. This differs from a stub or a fake, which replace behavior instead of just recording it. A spy that has not been given a replacement implementation still calls the real code underneath.

- **Turning a spy into a stub**: `jest.spyOn(obj, 'method')` alone only observes. Chaining `.mockImplementation(fn)` onto it replaces the underlying behavior, so the pairing `jest.spyOn(...).mockImplementation(...)` is what actually fakes a return value. The naming is a common source of confusion since "mock" in Jest's API is used for both stubbing (returning canned data) and mocking (verifying calls), which blurs a distinction the rest of the book treats as important.

- **Reverting Jest spies**: `jest.restoreAllMocks()` resets every object spied on back to its original, unpatched implementation. It belongs in an `afterEach`, mirroring the manual save-and-restore pattern but without the risk of forgetting to save the original reference.

- **Module caching**: Under CommonJS, `require` loads a module once and caches the result in `require.cache`, keyed by resolved file path. Every subsequent `require` of the same path returns the cached export object rather than re-executing the module. Faking a module's behavior therefore means intercepting or replacing that cache entry before the code under test requires it, not just reassigning a property after the fact.

- **Destructured imports break simple patching**: Code that does `const { getAllMachines } = require('./data-module')` copies a reference to the function out of the module object at require time. Patching a property on the module object afterward has no effect on the already-destructured local binding, because the local variable and the module's property are now two separate references. To fake such code, the module must be faked before the destructuring import runs, which forces tests to delay their `require` of the code under test until after the fake is in place.

## The Clear-Fake-Require-Act (CFRA) pattern

Faking a whole module for a specific test, with custom data per test, requires four ordered steps. Skipping a step, doing them out of order, or doing them at the wrong point in the test lifecycle produces flaky or silently wrong tests.

1. **Clear**: Remove the cached or previously faked module from the test runner's memory before the test sets up its own fake.
2. **Fake**: Replace the module's cache entry, or its exported functions, with a fake implementation that returns the data this test needs.
3. **Require**: Import the code under test only now, after the fake is installed, so its internal `require` call picks up the fake instead of the real module.
4. **Act**: Invoke the entry point of the code under test and assert on the result.

```js
// shape of the pattern, framework-agnostic
function fakeDataFromModule(fakeData) {
  clearCachedModule('./data-module')
  installFakeModule('./data-module', {
    getAllMachines: () => fakeData
  })
}
function requireAndCallUnderTest(...args) {
  const { findRecentlyRebooted } = require('../under-test')
  return findRecentlyRebooted(...args)
}
```

Because each test may want different fake data, Clear and Fake typically happen inside a small per-test helper function invoked from the test body (not from `beforeEach`), while Require and Act happen together right before the assertions.

## Faking modules per module system and framework

- **Vanilla CommonJS via `require.cache`**: Resolve the target module's absolute path with `require.resolve`, delete the cache entry at that key, then write a synthetic module record (`id`, `filename`, `loaded`, `exports`) whose `exports` object holds fake implementations. A subsequent `require(path)` picks up the synthetic record instead of re-executing the real file. This technique works with Node's own `require` and with frameworks like Jasmine that respect `require.cache`. It does not work under Jest, which implements its own module registry and ignores `require.cache` entirely.

- **Jest, ignore-the-whole-module style**: If a test does not care what a dependency returns and just wants it out of the way, `jest.mock('module-path')` at the top of the test file auto-replaces every export with a no-op fake. This is the safest option in the appendix because it never touches the internals of the unit under test, it simply removes a dependency from the picture.

- **Jest, custom data per test**: Three steps, done in this order: require the real module reference at the top of the file, call `jest.mock('module-path')` (also at the top, since Jest hoists it above imports), then inside each test call `moduleRef.someFunction.mockImplementation(() => fakeData)` to control what that call returns for this test. Reset behavior between tests with `beforeEach(jest.resetAllMocks)`, which clears the customized implementation but leaves the module fake in place (calling a reset-but-not-reconfigured mock yields confusing undefined results rather than falling back to real behavior).

- **Jest manual mocks (`__mocks__` folder)**: Jest supports a convention where a hand-written fake module lives in a `__mocks__` directory next to the real one, picked up automatically by name. The appendix advises against this: maintaining fake data means editing a separate file from the test, which raises both the maintenance cost and the reader's cost of jumping between files to understand what a test actually verifies.

- **CommonJS vs ES modules**: The whole CFRA discussion assumes CommonJS `require` semantics, where imports are just function calls that populate a mutable cache the test can intercept. ES modules resolve and bind imports statically at parse time, and the live bindings they create are not simple mutable object properties the way CommonJS exports are. That static, non-configurable nature is why module-level faking is comparatively easy to hack around under CommonJS and comparatively hard to replicate by hand under native ES modules, and why test runners provide dedicated module-mocking APIs (like Jest's own transform-based `jest.mock`) instead of leaving developers to intercept the import mechanism themselves.

- **Sinon.js**: Maps onto the same CFRA shape. Clear and Require happen together in a `beforeEach` that calls a module-reset function and re-requires the fake target. Fake happens via `sinon.stub(moduleObject, 'functionName').returns(fakeData)`, which replaces one property on an already-required module object. This only works because Sinon operates on the object reference directly, so the module must be re-required after each reset for the stub to apply to a fresh, unpatched object.

- **testdouble**: Same shape again, using `td.replace('module-path', { functionName: () => fakeData })` for the Fake step, paired with `jest.resetModules()` plus re-requiring `testdouble` and the `testdouble-jest` adapter for Clear. The adapter is only needed to hook testdouble into Jest's module system. It is unnecessary when testdouble runs under a different test runner.

## Patterns

- **Pattern 1 (Prefer parameters over globals)**: Whenever a function's dependency can be passed in as an argument instead of reached through a global or a required module, do that instead of monkey-patching. It removes the entire class of cleanup-ordering and parallelism bugs that patching introduces.

- **Pattern 2 (Guaranteed cleanup over inline cleanup)**: Put the save-original step in `beforeEach` and the restore step in `afterEach` rather than at the end of the test body, so a thrown assertion cannot skip the restore.

- **Pattern 3 (Spy first, mock implementation only if you must stub)**: Use a bare spy when you only need to observe calls to real code. Add `.mockImplementation()` only when the test genuinely needs to control the return value, since replacing behavior is a bigger commitment to fragility than merely observing it.

- **Pattern 4 (Require late when faking modules)**: Any time a module fake must vary per test, delay the `require` of the code under test until after the fake is installed inside the test itself, instead of requiring it once at the top of the file. A top-of-file require binds to whatever was cached (real or fake) at file-load time and will not pick up a later per-test fake.

## Common Pitfalls

- **Forgetting to restore a patched global**: An assertion failure inside the test body throws before an inline restore line runs, leaving the global patched for every test that follows in the same process.

- **Assuming `jest.spyOn` alone fakes behavior**: `spyOn` only tracks. Without a chained `mockImplementation`, the wrapped function still runs its real code.

- **Assuming `require.cache` tricks work in Jest**: Jest maintains its own internal module registry and does not consult Node's `require.cache`, so cache-patching code that works under plain Node or Jasmine silently fails, or simply does nothing, under Jest.

- **Requiring the code under test too early**: If the module fake is installed after the code under test has already been required and has already destructured the real function out of the dependency, the fake has no effect. The require of the code under test must come after the fake is in place.

- **Treating `jest.resetAllMocks` as a full undo**: Resetting a mock clears its custom implementation but the module stays mocked. Forgetting to give it a new implementation in the next test produces a stub that returns `undefined`, not the real function's behavior.

- **Using manual `__mocks__` files for data that changes per test**: This scatters the fake data away from the test that depends on it, forcing readers to open a second file to understand what a test actually exercises.

## Connections to the rest of the book

- **Chapter 3 (accepted stubbing techniques)**: This appendix is explicitly framed as the fallback for when chapter 3's safer techniques (parameter injection, constructor injection, designed-in seams) are unavailable, most often because the dependency is external code the author does not control.

- **Chapter 4 (mocks vs stubs)**: The spy and stub distinction in this appendix reuses chapter 4's definitions. A spy that is only used to fake a return value, without ever asserting on how it was called, is being used as a stub, not a mock. Calling `mockImplementationOnce` to control call-by-call return sequences edges toward mock-like brittleness (caring about call count and order), which the appendix advises against unless that behavior is actually under test.
