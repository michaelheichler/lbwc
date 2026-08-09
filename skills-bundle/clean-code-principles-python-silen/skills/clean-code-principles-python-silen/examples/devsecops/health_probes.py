"""Kubernetes health probes done right (DevSecOps: Deploy / Operate).

Demonstrates principles:
- Distinguish the three probe semantics, do NOT alias them to one handler:
    * startup   -> "process finished slow init" (gates liveness/readiness)
    * liveness  -> "should the kubelet restart me?" (process-local ONLY)
    * readiness -> "should the Service route traffic to me?" (deps included)
- Liveness must not check dependencies: a DB outage must not restart every pod.
- Readiness flips to False during graceful shutdown so traffic drains first.
- Probes are cheap and side-effect free, never run migrations or heavy I/O here.

Framework-agnostic core. The pure functions are unit-testable without a server.

FastAPI wiring (sketch)::

    app = FastAPI()
    state = HealthState(readiness_checks={"db": ping_db, "broker": ping_kafka})

    @app.on_event("startup")
    async def _startup() -> None:
        await open_pools()
        state.mark_started()

    @app.get("/isStarted")   # -> check_startup
    @app.get("/isAlive")     # liveness  -> check_liveness
    @app.get("/isReady")     # readiness -> check_readiness
    # paths match the chapter's Helm deployment.yaml probes.

Run:  python health_probes.py
"""

from __future__ import annotations

import enum
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field


class Status(enum.StrEnum):
    UP = "UP"
    DOWN = "DOWN"


# A dependency check returns True when the dependency is reachable/healthy.
DependencyCheck = Callable[[], Awaitable[bool]]


@dataclass(slots=True)
class HealthState:
    """Mutable process health, owned by the app lifecycle, read by probes."""

    started: bool = False
    shutting_down: bool = False
    readiness_checks: dict[str, DependencyCheck] = field(default_factory=dict)

    def mark_started(self) -> None:
        self.started = True

    def begin_shutdown(self) -> None:
        # Set BEFORE closing pools: readiness goes DOWN, the Service stops
        # sending new requests, in-flight ones finish, then we exit.
        self.shutting_down = True


async def check_startup(state: HealthState) -> tuple[Status, int]:
    """Startup probe: only 'did init complete'. 503 until ready, never restarts."""
    return (Status.UP, 200) if state.started else (Status.DOWN, 503)


async def check_liveness(state: HealthState) -> tuple[Status, int]:
    """Liveness probe: process is responsive. Deliberately dependency-free.

    Returning DOWN here triggers a kubelet restart, so the only legitimate
    DOWN is an unrecoverable in-process condition (deadlock, corrupt state).
    """
    return (Status.UP, 200) if not state.shutting_down else (Status.DOWN, 503)


async def check_readiness(state: HealthState) -> tuple[Status, int]:
    """Readiness probe: can we serve traffic *right now* (deps included)."""
    if state.shutting_down or not state.started:
        return (Status.DOWN, 503)
    for check in state.readiness_checks.values():
        if not await check():
            return (Status.DOWN, 503)
    return (Status.UP, 200)


async def _demo() -> None:
    async def is_db_ok() -> bool:
        return True

    state = HealthState(readiness_checks={"db": is_db_ok})
    print("before start:", await check_readiness(state))  # DOWN, deps not reached
    state.mark_started()
    print("after start: ", await check_readiness(state))  # UP
    print("liveness:    ", await check_liveness(state))  # UP (no dep coupling)
    state.begin_shutdown()
    print("draining:    ", await check_readiness(state))  # DOWN, sheds traffic


if __name__ == "__main__":
    import asyncio

    asyncio.run(_demo())
