# ch08: Concurrent Programming Principles

> When this governs: any time code runs work in more than one thread, process, or coroutine, choosing a concurrency model, sharing data between workers, or making writes correct under retries and races.

## Principle index

- **Choose the right model:** asyncio for I/O, processes for CPU, threads only when forced.
- **Scale out, not up:** prefer more stateless processes over more threads.
- **Async before threads:** reach for `asyncio` before manual threading for I/O concurrency.
- **Threads only for blocking I/O:** justify each thread by a synchronous call you can't make async.
- **Processes for CPU-bound work:** the GIL serialises Python threads, use `ProcessPoolExecutor`.
- **Prefer executors over raw threads:** let a pool own thread/process lifecycle.
- **Thread safety is not assumed:** never assume a library or collection is thread-safe.
- **Guard shared mutable state with a lock:** make read-modify-write atomic with `with lock`.
- **Hold locks briefly:** lock only the critical section, never do I/O under a lock.
- **Avoid shared mutable state:** pass inputs, return results, share nothing.
- **Name the contract:** if a class is thread-safe, say so in its name.
- **Signal, don't poll:** use `Condition`/`Event`/`queue.Queue`, not `sleep` loops.
- **Idempotent handlers:** make retried or duplicated work converge to one end state.
- **Optimistic locking for writers:** use version compare-and-set, retry on conflict.

## Principles

### Choose the right concurrency model

- **Rule:** Match the model to the bottleneck: asyncio for I/O, processes for CPU, threads only for blocking I/O you can't make async.
- **Why:** The GIL means Python threads give *no* CPU parallelism for pure-Python work. Using them for CPU-bound tasks adds lock complexity for zero speedup. Conversely, spawning processes for thousands of network calls wastes memory where one async event loop would do.
- **Python:**
  ```python
  # CPU-bound -> processes (real parallelism, GIL sidestepped)
  with ProcessPoolExecutor() as pool:
      results = list(pool.map(cpu_heavy, items))

  # I/O-bound, blocking client -> threads
  with ThreadPoolExecutor(max_workers=8) as pool:
      results = list(pool.map(blocking_fetch, urls))

  # I/O-bound, async client available -> asyncio, zero threads
  async with asyncio.TaskGroup() as group:           # 3.11+
      tasks = [group.create_task(async_fetch(u)) for u in urls]
  ```
- **Anti-slop:** Reaching for `threading.Thread` to "speed up" a CPU-bound loop. Under the GIL it runs no faster and is now race-prone.
- **See also:** `examples/concurrent-programming-principles/choose_concurrency_model.py`, fluent-python ch19 (GIL & models), ch20 (executors), ch21 (asyncio).

### Scale out, not up

- **Rule:** In cloud-native services, add stateless process instances to handle load before adding threads.
- **Why:** Stateless single-threaded instances scale horizontally (Kubernetes HPA, more replicas) without thread-safety bugs, and their vCPU request is predictable. Threading couples vCPU sizing to thread count and reintroduces synchronization hazards.
- **Python:** Keep the request handler single-threaded and idempotent, and let the orchestrator run N replicas. Put background/scheduled chores in a *separate* service (a CronJob), not a daemon thread inside the request service. That keeps single-responsibility intact.
- **Anti-slop:** Adding a `threading.Thread(daemon=True)` housekeeping loop inside a web service "so it cleans up periodically." That ties cleanup lifecycle to request-handler lifecycle and hides a second responsibility.

### Async before threads for I/O concurrency

- **Rule:** For concurrent I/O, prefer an async client and one event loop over a thread pool.
- **Why:** A single thread running `asyncio` serves thousands of in-flight I/O operations with far less memory and no lock hazards, because nothing preempts a coroutine mid-statement. Switches happen only at `await`.
- **Python:** Use `aiohttp`/`httpx`, `asyncpg`, `aiofiles` instead of their blocking counterparts. If only blocking calls exist, wrap them with `asyncio.to_thread(...)` so the loop stays responsive.
  ```python
  result = await asyncio.to_thread(blocking_legacy_call, arg)  # offload, don't block the loop
  ```
- **Anti-slop:** Spinning up a `ThreadPoolExecutor` for HTTP fan-out when an async HTTP client exists. The async path is simpler and avoids the GIL contention threads add.
- **See also:** fluent-python ch21.

### Threads only for blocking I/O

- **Rule:** Justify every thread by a synchronous call (legacy SDK, blocking driver) you cannot make async.
- **Why:** Threads earn their keep only when one thread can do useful work while another blocks in the kernel on I/O. For CPU work the GIL nullifies the benefit. For async-capable I/O, coroutines are cheaper.
- **Python:** A blocking database driver with no async variant is a legitimate `ThreadPoolExecutor` case. Bound `max_workers` to a sane number. Unbounded threads exhaust memory and thrash.
- **See also:** `examples/concurrent-programming-principles/choose_concurrency_model.py`.

### Processes for CPU-bound work

- **Rule:** Parallelise CPU-bound Python with processes, not threads.
- **Why:** Only one thread holds the GIL at a time, so CPU-bound threads run serially. Separate processes each get their own interpreter and run truly in parallel across cores.
- **Python:**
  ```python
  # ✗ no speedup: threads serialise on the GIL for CPU work
  with ThreadPoolExecutor() as pool:
      list(pool.map(is_prime, big_range))
  # ✓ real parallelism
  with ProcessPoolExecutor() as pool:
      list(pool.map(is_prime, big_range))
  ```
  Guard process-pool entry points with `if __name__ == "__main__":` (the `spawn` start method re-imports the module, and an unguarded pool creation recurses).
- **Anti-slop:** Forgetting the `__main__` guard around `ProcessPoolExecutor`/`multiprocessing.Pool`, causing a spawn import loop.
- **See also:** fluent-python ch20.

### Prefer executors over raw threads

- **Rule:** Use `concurrent.futures` pools instead of manually creating, starting, and joining threads.
- **Why:** Executors own worker lifecycle, propagate exceptions through `Future.result()`, bound concurrency, and clean up on context exit. Hand-rolled `Thread` + `join()` loops drop exceptions silently and leak threads on error.
- **Python:**
  ```python
  with ThreadPoolExecutor(max_workers=4) as pool:
      futures = [pool.submit(task, x) for x in items]
      results = [f.result() for f in futures]   # re-raises worker exceptions here
  ```
- **Anti-slop:** Storing results by appending to a shared list from inside `Thread` targets and never observing exceptions (a swallowed-failure bug). Return values and read them via `Future.result()`.
- **See also:** fluent-python ch20.

### Thread safety is not assumed

- **Rule:** Treat a data structure or library as thread-unsafe unless its docs explicitly guarantee otherwise.
- **Why:** Most Python objects are not safe for concurrent mutation. Assuming safety produces intermittent, load-dependent corruption that is nearly impossible to reproduce in tests.
- **Python:** `dict`, `list`, and `set` are not contracts for concurrent multi-step use even though individual ops happen to be GIL-atomic today. For shared queues, use `queue.Queue` (documented thread-safe). Wrap anything else in a lock.
- **Anti-slop:** "`list.append` is atomic so I don't need a lock." Single appends may be, but `if x not in lst: lst.append(x)` is two operations with a race between them.

### Guard shared mutable state with a lock

- **Rule:** Wrap every read-modify-write of shared state in `with self._lock:`.
- **Why:** `count += 1` is read, add, store (three steps with a window where another thread reads the same old value, so increments are silently lost). The lock makes the sequence indivisible and releases even on exception.
- **Python:**
  ```python
  class ThreadSafeCounter:                       # ✓
      def __init__(self) -> None:
          self._lock = threading.Lock()
          self._count = 0
      def increment(self) -> None:
          with self._lock:                       # atomic critical section
              self._count += 1
      @property
      def value(self) -> int:
          with self._lock:                       # reads need the lock too
              return self._count
  ```
  Python has no atomic integer type, a lock is the primary tool. Reads of shared state also take the lock so callers see a consistent value.
- **Anti-slop:** Locking writes but not reads, or assuming `+=` is atomic. Both leak inconsistent state.
- **See also:** `examples/concurrent-programming-principles/thread_safety_lock.py`, fluent-python ch19.

### Hold locks briefly

- **Rule:** Lock only the smallest critical section, never perform I/O or call out to unknown code while holding a lock.
- **Why:** A lock held during a network call serialises every thread behind that I/O, destroying the concurrency you added, and increases deadlock risk if the callee grabs another lock. Long-held locks turn a fast service into a single-threaded one.
- **Python:**
  ```python
  # ✗ network call inside the lock: every thread queues behind one slow request
  with self._lock:
      data = http_get(url)              # blocks all other threads
      self._cache[url] = data
  # ✓ do slow work outside, lock only the swap
  data = http_get(url)
  with self._lock:
      self._cache[url] = data
  ```
- **Anti-slop:** Wrapping an entire method body in `with self._lock:` when only one assignment touches shared state.

### Avoid shared mutable state

- **Rule:** Prefer pure workers that take inputs and return results over workers that mutate a shared object.
- **Why:** The safest concurrent code has nothing to synchronise. If each task owns its data and returns a value, there is no lock to forget and no race to debug. Add locks only where sharing is genuinely required.
- **Python:**
  ```python
  # ✗ workers mutate one shared list (lock-prone, order nondeterministic)
  def work(s: str) -> None: results.append(quote(s))
  # ✓ pure worker, the pool collects ordered results, no lock
  def quote(s: str) -> PriceQuote: return PriceQuote(s, price_of(s))
  results = list(pool.map(quote, symbols))
  ```
  Make objects shared *by reference* immutable: `@dataclass(frozen=True)` is safe to hand across threads because nobody can mutate it.
- **Anti-slop:** Building results by `append` from multiple worker threads instead of returning values and letting `executor.map` collect them in order.
- **See also:** `examples/concurrent-programming-principles/avoid_shared_mutable_state.py`, fluent-python ch06 (mutability/aliasing).

### Name the thread-safety contract

- **Rule:** Encode "safe to share across threads" in the type name (`ThreadSafeQueue`, `AtomicInt`).
- **Why:** Thread safety is invisible at the call site. A name is the cheapest, most durable way to tell the next developer that an object may be shared, far more reliable than a comment.
- **Python:** `ThreadSafeCounter`, `ThreadSafeList`, `AtomicInt`. Conversely, do not name something `ThreadSafe*` unless every public method actually holds the lock.
- **Anti-slop:** A class named `Cache` that callers assume is shareable but whose methods take no lock.

### Signal state changes, don't poll

- **Rule:** Use a `Condition`, `Event`, or `queue.Queue` to wait for shared-state changes, never a `sleep` loop.
- **Why:** Polling with `sleep` is a guess: too short burns CPU, too long adds latency. A condition variable wakes the waiter the instant the state changes and consumes zero CPU while blocked.
- **Python:**
  ```python
  # producer
  with self._not_empty:
      self._items.append(item)
      self._not_empty.notify()
  # consumer (wait_for re-checks the predicate, immune to spurious/lost wakeups)
  with self._not_empty:
      self._not_empty.wait_for(lambda: self._items or self._closed)
  ```
  Always use `Condition.wait_for(predicate)` (not bare `wait()`), and always re-test state after waking. In most cases just use `queue.Queue`, which implements this pattern, tested, internally.
- **Anti-slop:** `while not ready: time.sleep(0.1)` busy-wait loops, and using `Condition.wait()` without a predicate (vulnerable to spurious wakeups and missed notifications).
- **See also:** `examples/concurrent-programming-principles/pubsub_condition_queue.py`, fluent-python ch19.

### Make handlers idempotent

- **Rule:** Design any operation that can be retried or delivered twice so the end state is identical.
- **Why:** At-least-once delivery, client retries, and duplicate webhooks are facts of distributed life. A non-idempotent handler double-charges, double-sends, or double-counts under perfectly normal conditions.
- **Python:** Key the side effect on a stable id and no-op on replay. In a database this is a unique constraint or `INSERT ... ON CONFLICT DO NOTHING`. In memory, it is a "seen ids" set under a lock.
  ```python
  def handle(self, request_id: str) -> bool:
      with self._lock:
          if request_id in self._seen:
              return False           # replay: no second side effect
          self._seen.add(request_id)
          self.apply()
          return True
  ```
- **Anti-slop:** Assuming a message or HTTP request arrives exactly once. Build for duplicates from the start.
- **See also:** `examples/concurrent-programming-principles/optimistic_locking_idempotency.py`, ch07 (databases).

### Use optimistic locking for concurrent writers

- **Rule:** Read a record with its version, write back only if the version is unchanged, retry on conflict.
- **Why:** Compare-and-set prevents lost updates without holding a lock across the whole read-think-write cycle, so writers don't block each other in the common no-conflict case. A pessimistic lock held over user think-time or network round-trips kills throughput.
- **Python:**
  ```python
  def deposit(store, amount, *, attempts=5):
      for _ in range(attempts):
          current = store.read()                       # includes .version
          try:
              return store.compare_and_set(current.version,
                                           current.balance + amount)
          except StaleVersionError:
              continue                                 # someone else won, retry
      raise StaleVersionError("too many conflicts")
  ```
  In SQL this is `UPDATE ... SET balance=?, version=version+1 WHERE id=? AND version=?` and checking `rowcount == 1`.
- **Anti-slop:** A read-modify-write against a database with no version/`WHERE version=?` guard. Two concurrent transactions both read the old balance and one update is lost.
- **See also:** `examples/concurrent-programming-principles/optimistic_locking_idempotency.py`, ch07 (databases).

## Anti-slop checklist

- Do not use `threading.Thread` for CPU-bound Python work, the GIL serialises it. Use `ProcessPoolExecutor`.
- Do not reach for threads when an async client exists, prefer `asyncio` for I/O concurrency.
- Do not create a `ProcessPoolExecutor`/`multiprocessing.Pool` without an `if __name__ == "__main__":` guard.
- Do not assume `+=`, `list.append`, or any compound update on shared state is atomic, guard with a lock.
- Do not lock writes but leave reads of the same shared state unlocked.
- Do not hold a lock across I/O, sleeps, or calls into code you don't control.
- Do not busy-wait with `while not ready: time.sleep(...)`, signal with `Condition`/`Event`/`queue.Queue`.
- Do not call `Condition.wait()` without a predicate, use `wait_for(predicate)` and re-check on wake.
- Do not collect results by appending to a shared list from worker threads, return values via `Future`/`map`.
- Do not name a class `ThreadSafe*` unless every public method actually takes the lock.
- Do not assume exactly-once delivery, make retried/duplicated handlers idempotent.
- Do not do read-modify-write against a store without optimistic version checks or a transaction.
- Do not bury a background/scheduled loop as a daemon thread inside a request service, isolate it.

## Bundled examples

| File | Principle(s) demonstrated |
| --- | --- |
| `choose_concurrency_model.py` | Choose the right model, async before threads, processes for CPU, threads for blocking I/O |
| `thread_safety_lock.py` | Guard shared mutable state with a lock, name the contract, lost-update race |
| `pubsub_condition_queue.py` | Signal state changes don't poll, `Condition.wait_for` predicate pattern |
| `avoid_shared_mutable_state.py` | Avoid shared mutable state, pure workers, frozen dataclasses |
| `optimistic_locking_idempotency.py` | Idempotent handlers, optimistic locking with compare-and-set + retry |
