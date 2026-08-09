## Chapter 21: Asynchronous Programming
### Core Ideas
- `async def` creates native coroutine functions. Calling one returns a coroutine object that runs only when awaited, scheduled, or driven by an event loop.
- `await` works on awaitables: commonly native coroutine objects and `asyncio.Task` instances, plus lower-level objects that implement the await protocol.
- Async code is cooperative: each awaited operation gives the event loop a chance to run other pending work, so concurrency depends on avoiding blocking calls in the loop thread.
- Async-capable libraries expose coroutine APIs and async resource protocols, such as HTTP clients, database drivers, async context managers, and async iterables.
- `asyncio.gather` waits for a batch of awaitables and preserves submission order, while `asyncio.as_completed` lets callers process results as work finishes.
- `async with`, `async for`, async generators, async comprehensions, and async generator expressions extend normal context and iteration patterns to awaitable setup, cleanup, and item retrieval.
- Python's async syntax is not exclusive to `asyncio`. Frameworks such as Curio and Trio-style designs show that the language constructs can be driven by different runtimes.
- Async performance gains come from hiding I/O latency, but real systems still contain CPU-heavy or blocking sections that must be isolated, rewritten, or delegated.

### Practitioner Guidance
- Make the top-level script boundary plain and small: build a coroutine such as `main`, then run it with `asyncio.run` from synchronous startup code.
- Use coroutine-friendly libraries end to end. Once a path uses async I/O, upstream callers often need to become async too.
- Prefer `await`-based sequencing over callback chains when multiple asynchronous operations share local state.
- Use `asyncio.create_task` when work should start independently, `await` when the current coroutine needs the result now, and `gather` or `as_completed` for batches.
- Throttle outbound clients with `asyncio.Semaphore` or similar controls. Hold semaphores and locks only around the operation that needs the limit.
- Offload blocking file I/O or legacy synchronous calls with `asyncio.to_thread` or an executor, and use process pools or external workers for CPU-bound Python work.
- In server code, distinguish buffered operations from real I/O: some stream methods are plain functions, while flush, read, close, or receive operations may need `await`.
- Annotate coroutine return values as the awaited result type, using `collections.abc.AsyncIterator`, `AsyncIterable`, `Awaitable`, and related async ABCs on modern Python.

### Pitfalls
- Calling synchronous network, filesystem, database, or CPU-heavy code inside a coroutine can stall every task on the same event loop.
- Assuming all APIs in an async object are awaitable leads to both missed awaits and invalid awaits. Check each method's contract.
- Treating async generators like ordinary iterables fails because they are consumed with `async for`, not regular `for`.
- Expecting executor cancellation to stop the underlying thread can produce shutdown hangs or work continuing after the coroutine was cancelled.
- Launching unbounded requests can overload remote services or distort benchmarks. Async clients can generate pressure fast.
- Believing an entire application is purely I/O-bound hides the CPU-bound parsing, serialization, validation, and glue work that can dominate under load.

### Skill Hooks
- `async def`, native coroutine, coroutine object, awaitable, `await`
- `asyncio.run`, event loop, `get_running_loop`, task scheduling
- `asyncio.create_task`, `asyncio.gather`, `asyncio.as_completed`, task result order
- `httpx.AsyncClient`, async HTTP clients, async database drivers, ASGI, FastAPI
- `async with`, async context manager, `__aenter__`, `__aexit__`, `contextlib.asynccontextmanager`
- `async for`, async iterable, async iterator, `__aiter__`, `__anext__`, async generator
- async comprehensions, async generator expressions, top-level async REPL experiments
- `asyncio.Semaphore`, throttling, rate limiting, progress over completed tasks
- `asyncio.to_thread`, `run_in_executor`, blocking file I/O, process pools, task queues
- event-loop blocking, CPU-bound traps, structured concurrency, Curio, Trio

### Cross-Links
- Chapter 17: generators, `yield from`, classic coroutines, iterator foundations, and generator typing.
- Chapter 18: `with`, context managers, `contextlib`, and the sync forms behind `async with`.
- Chapter 19: concurrency models, event loops, coroutines, task cancellation, and blocking hazards.
- Chapter 20: futures, executors, concurrent downloads, progress handling, and process pools.
- Chapter 4: Unicode database material used by the asynchronous server examples.
