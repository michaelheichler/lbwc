"""Unit of Work: one transaction per business operation, commit or roll back.

Principles shown:
- Group all writes of one operation in a single transaction, partial commits
  corrupt invariants (e.g. money debited but never credited).
- A context manager owns the lifecycle: commit on clean exit, rollback on any
  exception, always close. No manual try/except/finally at every call site.

See fluent-python ch18 for context-manager mechanics (__enter__/__exit__,
contextlib). This file shows the DATABASE discipline, not the syntax.

Run: python unit_of_work.py
"""

from __future__ import annotations

import contextlib
from types import TracebackType
from typing import Self

from sqlalchemy import create_engine, select
from sqlalchemy.orm import (
    DeclarativeBase,
    Mapped,
    Session,
    mapped_column,
    sessionmaker,
)


class Base(DeclarativeBase):
    pass


class Account(Base):
    __tablename__ = "accounts"

    id: Mapped[int] = mapped_column(primary_key=True)
    balance_in_cents: Mapped[int]


class InsufficientFundsError(Exception):
    """Raised mid-transaction so the whole transfer rolls back."""


class UnitOfWork:
    """Wraps one Session as one transaction. Enter -> begin, exit -> commit
    on success, rollback on exception. Callers never call commit/rollback."""

    def __init__(self, session_factory: sessionmaker[Session]) -> None:
        self._session_factory = session_factory
        self.session: Session | None = None

    def __enter__(self) -> Self:
        self.session = self._session_factory()
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        assert self.session is not None
        try:
            if exc_type is None:
                self.session.commit()  # clean exit -> persist atomically
            else:
                self.session.rollback()  # any error -> undo everything
        finally:
            self.session.close()
            self.session = None


def transfer(
    unit_of_work: UnitOfWork,
    from_id: int,
    to_id: int,
    amount_in_cents: int,
) -> None:
    """Debit and credit in ONE transaction. If the credit row is missing or
    funds are short, the debit is rolled back - never half-applied."""
    with unit_of_work as uow:
        session = uow.session
        assert session is not None
        source = session.get(Account, from_id, with_for_update=True)
        target = session.get(Account, to_id, with_for_update=True)
        if source is None or target is None:
            raise LookupError("account not found")
        if source.balance_in_cents < amount_in_cents:
            raise InsufficientFundsError(from_id)
        source.balance_in_cents -= amount_in_cents
        target.balance_in_cents += amount_in_cents
        # No explicit commit: __exit__ commits iff no exception escapes.


def _demo() -> None:
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    factory: sessionmaker[Session] = sessionmaker(bind=engine)
    with factory() as setup:
        setup.add_all([Account(id=1, balance_in_cents=10_000), Account(id=2, balance_in_cents=0)])
        setup.commit()

    transfer(UnitOfWork(factory), from_id=1, to_id=2, amount_in_cents=3_000)

    # Failed transfer must leave balances untouched (atomic rollback).
    with contextlib.suppress(InsufficientFundsError):
        transfer(UnitOfWork(factory), from_id=1, to_id=2, amount_in_cents=999_999)

    with factory() as check:
        balances = {a.id: a.balance_in_cents for a in check.scalars(select(Account)).all()}
    assert balances == {1: 7_000, 2: 3_000}, balances
    print("unit_of_work OK", balances)


if __name__ == "__main__":
    _demo()
