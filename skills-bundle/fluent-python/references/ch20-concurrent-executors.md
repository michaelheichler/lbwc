## Chapter 20: Concurrent Executors
### Core Ideas
- `concurrent.futures` provides high-level executors for running independent callables without manually managing worker threads, processes, or queues.
- For network I/O, a thread pool can make many waits overlap. The chapter's HTTP flag downloader is much faster when requests are launched concurrently.
- `ThreadPoolExecutor.map` is the simplest path when the same callable is applied to many inputs and results should be consumed in input order.
- A `Future` represents scheduled work whose result, exception, or completion state will become available later. Application code usually receives futures from an executor instead of creating them.
- `Executor.submit` plus `futures.as_completed` exposes futures directly and yields them as tasks finish, which is useful when completion order matters.
- `ProcessPoolExecutor` uses separate Python processes, making it appropriate for CPU-heavy, easily partitioned work that needs multiple cores despite the GIL.
- Executor context managers call shutdown on exit, so the main thread waits for submitted work to finish before leaving the block.
- Progress bars and per-task status reporting work best when futures are consumed as they complete, often with a mapping from each future back to its input metadata.

### Practitioner Guidance
- Refactor the body of a sequential loop into a small function before moving to an executor. Each worker should get one independent unit of work.
- Use `ThreadPoolExecutor` for I/O-bound tasks such as HTTP calls, file waits, or remote service requests, and use `ProcessPoolExecutor` for CPU-bound tasks that can be split cleanly.
- Start with `executor.map` for uniform tasks when ordered results are acceptable. Switch to `submit` and `as_completed` for progress, mixed callables, multiple executors, or out-of-order handling.
- Always set practical network timeouts and surface HTTP failures instead of silently treating bad responses as successful work.
- Cap concurrency explicitly when calling remote services. Keep public-server tests small or run against a local test server.
- When using `as_completed`, store `{future: context}` so error messages and follow-up work can identify the original input.
- Expect `Future.result()` to raise the worker exception. Wrap result collection, not just task submission, when adding error handling.
- Pass `total=` to progress helpers when wrapping `as_completed`, because the completion iterator may not advertise its length.

### Pitfalls
- `executor.map` can make a program look stalled because it yields results in submission order, even when later tasks already finished.
- Calling `.result()` on an unfinished `concurrent.futures.Future` blocks the caller unless a timeout is used.
- Too many threads can waste memory and stress remote services. The chapter uses explicit maximum request limits for this reason.
- Process pools add startup and memory overhead, so they are a poor fit for ordinary I/O-bound downloads.
- Interleaved printing from worker threads can produce surprising output order. Do not infer task sequencing from console text alone.
- Handling only 404-like cases inside a worker is not enough. Other request and HTTP errors still need collection-side handling.

### Skill Hooks
- `concurrent.futures`, `ThreadPoolExecutor`, `ProcessPoolExecutor`, `Executor.map`, `Executor.submit`, `Future`, `as_completed`
- Converting a sequential loop into concurrent worker calls
- Threaded HTTP downloads, request fan-out, progress bars, `tqdm` with futures
- Choosing threads versus processes for I/O-bound and CPU-bound Python work
- Handling exceptions from futures and preserving input context for completed tasks
- Reviewing concurrency limits, timeouts, shutdown behavior, and result ordering
- Diagnosing blocked-looking executor code where ordered result consumption hides completed work

### Cross-Links
- Chapter 19: concurrency models, the GIL, threads/processes, and the earlier multicore prime-checker example.
- Chapter 21: `asyncio`, coroutine-based HTTP clients, and the related `asyncio.Future` model.
