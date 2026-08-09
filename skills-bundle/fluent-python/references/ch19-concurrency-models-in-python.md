## Chapter 19: Concurrency Models in Python
### Core Ideas
- Concurrency is about organizing several pending activities so each can make progress. Parallelism is simultaneous execution and requires multiple cores, processors, GPUs, or machines.
- Python's native concurrency units are processes, threads, and coroutines, each with different costs, scheduling behavior, memory sharing, and communication needs.
- Threads share memory within one process, which makes data exchange easy but creates race risks. The GIL prevents multiple Python threads from running Python bytecode at the same instant in CPython.
- Processes bypass the GIL because each interpreter process has its own runtime state, but process boundaries require serialization, queues, pipes, sockets, or other explicit communication.
- Native coroutines run cooperatively under an event loop, usually in one thread. They are lightweight and predictable at suspension points, but any blocking operation stalls the loop.
- I/O-bound work can perform well with threads or async coroutines because waiting libraries can release the GIL or yield to the event loop.
- CPU-bound Python code should use processes, native extensions that release the GIL, data-science runtimes, task queues, or distributed systems rather than relying on many threads.
- Python scales in practice through architecture as much as language features: application servers, worker processes, message queues, numeric libraries, GPUs, clusters, and horizontal deployment all matter.

### Practitioner Guidance
- Choose `threading` for simple concurrent I/O or background coordination when shared memory is useful and the code can protect mutable shared state.
- Choose `multiprocessing` or `concurrent.futures.ProcessPoolExecutor` for CPU-heavy pure Python work that should use multiple cores.
- Choose `asyncio` when many tasks mostly wait on nonblocking I/O and the libraries involved provide coroutine-friendly APIs.
- In async code, replace blocking waits with awaitable equivalents. A tiny `await asyncio.sleep(0)` can yield temporarily, but offloading CPU work is the better design.
- Use queues to send jobs, results, errors, and shutdown signals between workers. Include enough identity in result messages to match them with submitted work.
- Use explicit lifecycle coordination: `Event` plus `join()` for threads, sentinels for worker loops, process joins or pools for multiprocessing, and cancellation handling for tasks.
- Benchmark worker counts instead of assuming "more workers" is faster. CPU contention, process startup, serialization, and context switching can erase expected gains.
- For web services, keep request handlers fast and delegate long jobs to task queues. Let WSGI/ASGI servers and workers provide process-level scaling.

### Pitfalls
- Treating threads as a way to speed up CPU-bound Python loops. GIL contention and context switching can make them slower than sequential code.
- Calling blocking functions inside coroutines, which freezes all coroutines managed by the same event loop.
- Forgetting that multiprocessing cannot freely share Python objects. Values crossing process boundaries need serialization or special shared-memory support.
- Assuming worker results arrive in submission order. Concurrent workers complete according to runtime cost and scheduling.
- Terminating workers abruptly instead of sending a clean shutdown message, which can leave partial work and confusing errors.
- Adding distributed or web-scale architecture before the workload actually needs it.

### Skill Hooks
- Python concurrency model selection: threads vs processes vs `asyncio`
- CPython GIL impact, CPU-bound vs I/O-bound work
- `threading.Thread`, `threading.Event`, `join`, locks, shared mutable state
- `multiprocessing.Process`, queues, sentinels, worker loops, process pools
- `asyncio.run`, `asyncio.create_task`, `await`, `Task.cancel`, event loop blocking
- replacing `time.sleep` in async code, nonblocking I/O review
- race conditions, cancellation, worker shutdown, result collection order
- WSGI/ASGI servers, Gunicorn/uWSGI/mod_wsgi/NGINX Unit, Celery/RQ, Redis/RabbitMQ
- horizontal scaling, background jobs, distributed task queues

### Cross-Links
- Chapter 17: generator-based coroutines and iterator foundations behind coroutine concepts.
- Chapter 20: higher-level thread and process orchestration with `concurrent.futures`.
- Chapter 21: deeper async programming, async I/O, executors, and event-loop patterns.
