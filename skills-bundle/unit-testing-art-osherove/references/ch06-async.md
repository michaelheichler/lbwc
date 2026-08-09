# Chapter 6: Unit testing asynchronous code

## Key Concepts

- **Synchronous vs. asynchronous waiting**: With synchronous code, waiting for a result is implicit, the caller just gets the return value. With async code, waiting becomes an explicit activity the test has to manage itself (a callback, a `done()` call, an `await`). This explicitness is what makes async code, and its tests, trickier.

- **Entry point vs. exit point**: The entry point is where a test calls into the code under test. The exit point is where the result comes back out, a return value, a thrown error, an invoked callback, or an emitted event. Synchronous code usually has one entry point that is also its exit point. Callback-based async code splits these: the function call is the entry point, but the callback invocation is a separate exit point that the test must wait for.

- **`done()` callback (Jest)**: A special argument Jest injects into a test function when the test needs to wait for something outside the normal return flow. The test only completes when `done()` is called. If it's never called, Jest times the test out (5 seconds by default, configurable) and fails it. Needed whenever the exit point is a callback or an event rather than a return value.

- **Integration test (in this chapter's sense)**: Any test that exercises the real asynchronous path end to end, including a real network call, a real timer, or a real DOM event loop. Async/await syntax can make such a test *read* like a plain value-based test, but it is still an integration test underneath, because real asynchronous machinery still runs.

- **Extract Entry Point pattern**: Split a function that mixes async orchestration with logic into (1) the async part, left intact, and (2) the logic that processes the async result, pulled out into its own plainly-invokable function. The extracted function becomes a new unit-test entry point that needs no waiting, no network, and no timers, because it's just a value-in/value-out (or value-in/callback-out) function.

- **Extract Adapter pattern**: The mirror image. Instead of pulling logic out of the async function, wrap the async dependency itself (fetch, a DB client, a timer) behind a small adapter with an interface shaped for the consumer's needs. In tests, inject or fake the adapter so the async dependency never actually runs. This is the same "treat it like any other dependency" idea used for DB or filesystem access elsewhere in the book, applied to anything asynchronous.

- **Interface segregation for adapters**: An adapter's interface should expose only what the consuming code actually needs, in the consumer's own vocabulary, not the full surface of the underlying library. A network adapter for a website checker might expose one method, `fetchUrlText(url)`, hiding away status codes, headers, and the rest of `fetch`'s API.

- **Three adapter injection styles**: the pattern is the same, the mechanics differ.
  - *Modular*: import the adapter module directly in production code. In tests, replace the whole module with `jest.mock()` and reset it between tests (`jest.resetAllMocks`).
  - *Functional*: pass the adapter in as a parameter (dependency passed, not imported). Tests build a small stub object and pass it in directly, no mocking framework, no reset step.
  - *Object-oriented*: define an interface, inject an implementation through the constructor. Tests build a stub class or fake that implements the interface.

  Each removes boilerplate progressively. Functional and OO injection remove the need for a mocking library and its reset lifecycle entirely.

- **Monkey-patching**: Reassigning a global function (like `setTimeout`) at runtime to a fake implementation, then restoring the original afterward. Works because JavaScript lets you reassign almost anything at runtime. Straightforward but manual: you own saving the original (`beforeEach`) and restoring it (`afterEach`), and a forgotten restore leaks a fake timer into later tests.

- **Jest fake timers**: `jest.useFakeTimers()` swaps out `setTimeout`/`setInterval`/etc. with controllable stand-ins. `jest.advanceTimersToNextTimer()` fires the next pending timer's callback synchronously. `jest.resetAllTimers()` (or `clearAllTimers`) clears any that were scheduled. This gives the same effect as monkey-patching without hand-rolled save/restore bookkeeping.

- **Event emitters**: Objects (in Node, subclasses of `EventEmitter`) that broadcast named events with data to any subscriber. Testing one means subscribing to the event *inside* the test, then asserting the callback ran with the expected payload, using `done()` since the assertion happens inside an async callback.

- **Click/UI events**: DOM events are best treated as an entry point whose real exit point is an observable change in the page, not the firing of the event itself. Subscribing to a click event just to prove it fired provides no confidence about what the click was supposed to do.

- **jsdom test environment**: A Jest annotation (`/** @jest-environment jsdom */`) that provides a simulated `window`/`document` so DOM APIs work inside a Node test process without a real browser.

- **DOM Testing Library**: A library (Kent C. Dodds) that queries elements by visible text rather than by ID, and wraps event dispatching (`fireEvent.click(...)`) and text-appearance waiting (`findByText`) in a friendlier API. Framework-agnostic core with bindings for React, Angular, Vue. Using `{ exact: false }` in text queries keeps tests resilient to minor copy changes.

## Techniques and Examples

### Prefer async/await tests over callback/`.then()` tests

Both work, but a test using bare callbacks or `.then()` chains is harder to read than one written with `async`/`await` on the test function itself:

```js
// noisier
test("fetch ok", (done) => {
  checkSite().then((r) => { expect(r.ok).toBe(true); done(); });
});

// cleaner
test("fetch ok", async () => {
  const r = await checkSite();
  expect(r.ok).toBe(true);
});
```

Both are still integration tests if `checkSite` hits the network. The syntax sugar doesn't change what's happening underneath, it just makes the test read closer to plain synchronous code.

### Extract Entry Point: pull the logic out, leave the plumbing

Before: one function does fetch, error-check, and content-check all inline, so testing any branch means running the real fetch. After: split the branches into small standalone functions the production code calls, and test *those* directly.

```js
const processFetchSuccess = (text) => text.includes("ok-marker")
  ? { success: true }
  : { success: false, status: "missing text" };

test("bad content -> false", () => {
  expect(processFetchSuccess("nope").success).toBe(false);
});
```

No network, no timer, no `done()`. The original orchestrating function still exists and still deserves one or two integration tests to prove the wiring holds together, but every branch of logic gets covered fast and deterministically through the extracted functions.

### Extract Adapter: replace the async dependency, not the logic

Wrap the raw dependency (`fetch`, a DB driver, a timer) in a small module or class with a narrow interface, then inject a fake of that interface in tests:

```js
const makeStubNetwork = (result) => ({ fetchUrlText: () => result });

test("bad content -> false", async () => {
  const stub = makeStubNetwork({ ok: true, text: "nope" });
  const r = await isWebsiteAlive(stub);
  expect(r.success).toBe(false);
});
```

`isWebsiteAlive` still runs its real logic (error handling, content check), only the actual network call is swapped out. Functional injection (parameter) needs the least ceremony. Module-mocking (`jest.mock`) needs the most (mock setup, `resetAllMocks` between tests).

### Fake timers instead of hand-rolled monkey-patching

```js
describe("with jest fake timers", () => {
  beforeEach(jest.useFakeTimers);
  test("calculate1 resolves synchronously", () => {
    let out;
    calculate1(1, 2, (r) => (out = r));
    jest.advanceTimersToNextTimer();
    expect(out).toBe(3);
  });
});
```

No `done()` needed because everything now resolves synchronously inside the test. Without `advanceTimersToNextTimer`, a fake `setTimeout` never fires and the callback never runs, so the test would pass or hang without checking anything useful, depending on how the assertion is written.

### Assert an observable effect for events and clicks, not just that they fired

```js
button.click();
expect(resultDiv.innerText).toBe("Clicked!");
```

Subscribing to the click event and asserting the subscription callback ran proves the wiring exists but says nothing about what the click was supposed to accomplish. Assert the state change the click was supposed to cause.

## Pitfalls

- **Missing `done()` producing a false pass**: If a test's assertions live inside a callback and the test forgets to call `done()` (or never invokes the callback path being tested), Jest may finish the test before the callback runs, and a test with zero executed assertions reports green. Always pair callback-based exit points with `done()`, and make sure every code path under test actually reaches an assertion.

- **Forgetting to restore a monkey-patched global**: If `afterEach` doesn't restore the original `setTimeout` (or the process throws before restoration runs), the fake leaks into unrelated later tests, causing confusing failures far from the real cause. This is exactly the bookkeeping Jest's fake timers exist to remove.

- **Forgetting `jest.advanceTimersToNextTimer()`**: With fake timers active but never advanced, a scheduled callback simply never runs. A poorly written test can then pass for the wrong reason (no assertion ever executed) rather than failing loudly.

- **Testing that an event fired instead of testing its effect**: Subscribing to a custom or DOM event purely to prove it was emitted is a weak test. It passes even if the event handler's actual logic is broken, as long as the event itself still fires. Assert the resulting state instead.

- **Treating async/await tests as unit tests when they still hit the network or a timer**: `await service.fetch()` inside a test reads exactly like a synchronous value-based test, but if `service.fetch` is the real network call, it's still slow, flaky, and hard to fully control (can't simulate a dropped connection or malformed response easily). The syntax hides, but doesn't remove, the integration-test cost.

- **Over-relying on integration tests for every branch**: Because simulating negative paths (bad response, missing content, network failure) is awkward with a real dependency, teams are tempted to skip those branches rather than write more integration tests for them. That's a signal to extract an entry point or adapter so those branches become trivial to hit with plain unit tests.

- **Naming that hides synchronous vs. asynchronous fakes**: A stub named just `network` or `fake` doesn't tell a reader whether invoking it is instant or still goes through a promise microtask queue. Naming it something like `stubSyncNetwork` documents that the fake resolves immediately, which matters when reasoning about test ordering.

## Connections to Other Chapters

- **Dependency injection chapters (earlier in the book)**: Extract Adapter is the same dependency-isolation idea applied elsewhere in the book (databases, filesystems, clocks), specialized for anything that is asynchronous by nature. Modular, functional, and object-oriented injection styles mirror the general injection techniques covered for synchronous dependencies.

- **Chapter 7 (Trustworthy tests)**: This chapter flags that integration test failures are harder to trust (a failure might be an external issue, not a real bug), a theme picked up and expanded in the next chapter's discussion of what makes a test result trustworthy.

- **Chapter 10 (Test strategy)**: The balance struck here, a small number of integration tests for orchestration confidence plus a larger base of fast unit tests for logic and branches, is the specific instance of the broader test-mix strategy discussed at length in chapter 10.
