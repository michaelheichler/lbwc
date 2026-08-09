"""Threading Principle: pick the model that matches the workload.

Decision order this file demonstrates:
  1. I/O-bound, many connections  -> asyncio (one thread, cooperative)
  2. I/O-bound, blocking library  -> threads (ThreadPoolExecutor)
  3. CPU-bound, pure Python       -> processes (ProcessPoolExecutor),
                                     because the GIL serialises threads
  4. Background schedule          -> a separate process/CronJob, not a
                                     daemon thread inside the service

The point is NOT to add threads by reflex. Reach for asyncio first for
I/O concurrency, reach for processes for CPU parallelism. Threads are the
middle option, justified by blocking I/O in a library you cannot make async.

See also: fluent-python ch19 (concurrency models / GIL), ch20 (executors),
ch21 (asyncio).
"""

from __future__ import annotations

import asyncio
import math
import time
from collections.abc import Sequence
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor


# --- 3. CPU-bound: use PROCESSES, never threads -----------------------------
# Pure-Python CPU work cannot run in parallel across threads because only one
# thread holds the GIL at a time. ProcessPoolExecutor sidesteps the GIL by
# running each task in its own interpreter.
def _is_prime(n: int) -> bool:
    if n < 2:
        return False
    return all(n % divisor != 0 for divisor in range(2, math.isqrt(n) + 1))


def count_primes_parallel(numbers: Sequence[int]) -> int:
    # ProcessPoolExecutor: real parallelism for CPU-bound work.
    with ProcessPoolExecutor() as pool:
        return sum(pool.map(_is_prime, numbers))


# --- 2. I/O-bound with a BLOCKING library: use THREADS ----------------------
# When the I/O call is synchronous (a legacy SDK, a blocking driver) threads
# let the program do other work while one thread waits on the kernel.
def _blocking_fetch(url: str) -> int:
    time.sleep(0.05)  # stand-in for a blocking network read
    return len(url)


def fetch_all_blocking(urls: Sequence[str]) -> list[int]:
    with ThreadPoolExecutor(max_workers=8) as pool:
        return list(pool.map(_blocking_fetch, urls))


# --- 1. I/O-bound, async-capable: use ASYNCIO (no threads at all) -----------
# Prefer this when an async client exists (aiohttp, asyncpg, aiofiles...).
# One thread serves thousands of in-flight operations cooperatively.
async def _async_fetch(url: str) -> int:
    await asyncio.sleep(0.05)  # stand-in for an awaitable network read
    return len(url)


async def fetch_all_async(urls: Sequence[str]) -> list[int]:
    async with asyncio.TaskGroup() as group:  # 3.11+ structured concurrency
        tasks = [group.create_task(_async_fetch(u)) for u in urls]
    return [t.result() for t in tasks]


if __name__ == "__main__":
    print("primes:", count_primes_parallel(range(2, 50)))
    print("blocking:", fetch_all_blocking(["a", "bb", "ccc"]))
    print("async:", asyncio.run(fetch_all_async(["a", "bb", "ccc"])))
