"""Distributed Transaction / Saga Orchestration pattern.

A distributed transaction spans several services, so there is no shared ACID
rollback. The saga pattern replaces rollback with *compensation*: every forward
step declares an inverse step, and on failure the orchestrator runs the inverses
for the steps that already ran, in reverse order.

Two correctness rules the chapter stresses, encoded here:

- Compensations must be **idempotent**: a compensation may itself fail and be
  retried after it already succeeded, so running it twice must be a no-op the
  second time. We key forward effects by ``saga_id`` to achieve that.
- A timed-out forward step has **unknown** outcome, so it must be compensated
  anyway (conditional compensation): undoing something that never happened is
  safe precisely because compensation is idempotent.

This is an original, self-contained model of the book's money-transfer saga.
See fluent-python ch08 (Protocol/Callable) for the step typing.

Run:  python saga_orchestration.py
"""

from __future__ import annotations

import asyncio
import uuid
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from functools import partial

SagaStep = Callable[[str], Awaitable[None]]


class StepFailedError(Exception):
    """Raised by a forward step, outcome may be unknown (e.g. a timeout)."""


@dataclass(slots=True)
class SagaAction:
    name: str
    forward: SagaStep
    compensate: SagaStep  # MUST be idempotent


@dataclass(slots=True)
class Saga:
    saga_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    _actions: list[SagaAction] = field(default_factory=list)

    def add(self, action: SagaAction) -> None:
        self._actions.append(action)

    async def run(self) -> None:
        """Execute forward steps, on any failure compensate completed ones."""
        completed: list[SagaAction] = []
        try:
            for action in self._actions:
                await action.forward(self.saga_id)
                completed.append(action)
        except StepFailedError as exc:
            await self._compensate(completed)
            raise StepFailedError(f"saga {self.saga_id} rolled back after {exc}") from exc

    async def _compensate(self, completed: list[SagaAction]) -> None:
        # Reverse order. Each compensation is retried until it succeeds because
        # downstream state must not be left half-rolled-back.
        for action in reversed(completed):
            # functools.partial binds ``action`` per iteration, so each closure
            # compensates its own step instead of the final loop value.
            await _retry(partial(action.compensate, self.saga_id))


async def _retry(op: Callable[[], Awaitable[None]], *, attempts: int = 5) -> None:
    for attempt in range(1, attempts + 1):
        try:
            await op()
        except StepFailedError:
            if attempt == attempts:
                raise
            await asyncio.sleep(0)  # back-off elided for the example
        else:
            return


# --- Demo services: an idempotent in-memory balance + transaction store ------
class _BalanceService:
    def __init__(self, balance_cents: int) -> None:
        self._balance = balance_cents
        self._withdrawn: set[str] = set()  # saga_ids already applied

    async def withdraw(self, saga_id: str, amount: int) -> None:
        if saga_id in self._withdrawn:
            return  # idempotent forward
        if amount > self._balance:
            raise StepFailedError("insufficient funds")
        self._balance -= amount
        self._withdrawn.add(saga_id)

    async def undo_withdraw(self, saga_id: str, amount: int) -> None:
        if saga_id not in self._withdrawn:
            return  # idempotent: nothing to undo
        self._balance += amount
        self._withdrawn.discard(saga_id)


async def _main() -> None:
    balance = _BalanceService(balance_cents=2000)
    saga = Saga()
    saga.add(
        SagaAction(
            name="withdraw",
            forward=lambda sid: balance.withdraw(sid, 2510),  # exceeds funds -> fails
            compensate=lambda sid: balance.undo_withdraw(sid, 2510),
        )
    )
    try:
        await saga.run()
    except StepFailedError as exc:
        print(exc)


if __name__ == "__main__":
    asyncio.run(_main())
