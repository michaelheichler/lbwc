"""Optimistic locking + idempotency for concurrent writers and at-least-once
delivery.

Two patterns that make distributed/concurrent updates correct without long
held locks:

1. Optimistic locking (version / compare-and-set): read a row with its
   version, write back only if the version is unchanged. A concurrent writer
   that slipped in between bumps the version, your update fails, you retry on
   fresh data. Avoids lost updates without blocking other writers.

2. Idempotency: a handler that can run twice (retries, at-least-once message
   delivery, duplicate webhooks) must produce the same end state. Key the
   side effect on a stable id and no-op on replay.

These are simulated in-memory here. In production the version check is a
`WHERE version = ?` in SQL and the idempotency set is a unique constraint.

See also: ch07 databases (optimistic concurrency control), fluent-python ch19.
"""

from __future__ import annotations

import threading
from dataclasses import dataclass, replace


# --- 1. Optimistic locking --------------------------------------------------
class StaleVersionError(Exception):
    """Raised when a compare-and-set finds the row changed underneath us."""


@dataclass(frozen=True)
class Account:
    id: str
    balance: int
    version: int  # bumped on every successful write


class AccountStore:
    """Compare-and-set store: a write succeeds only against the version read."""

    def __init__(self, account: Account) -> None:
        self._lock = threading.Lock()  # protects the swap itself, held briefly
        self._account = account

    def read(self) -> Account:
        with self._lock:
            return self._account  # frozen -> safe to hand out

    def compare_and_set(self, expected_version: int, new_balance: int) -> Account:
        with self._lock:
            if self._account.version != expected_version:
                raise StaleVersionError(
                    f"expected v{expected_version}, found v{self._account.version}"
                )
            self._account = replace(
                self._account, balance=new_balance, version=expected_version + 1
            )
            return self._account


def deposit_with_retry(store: AccountStore, amount: int, *, attempts: int = 5) -> Account:
    for _ in range(attempts):
        current = store.read()
        try:
            return store.compare_and_set(current.version, current.balance + amount)
        except StaleVersionError:
            continue  # someone else won the race, re-read and retry
    raise StaleVersionError("gave up after too many concurrent conflicts")


# --- 2. Idempotency ---------------------------------------------------------
class IdempotentProcessor:
    """Processes each request id at most once even if delivered repeatedly."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._seen: set[str] = set()
        self.applied = 0  # observable side-effect count

    def handle(self, request_id: str) -> bool:
        with self._lock:
            if request_id in self._seen:
                return False  # replay: no-op, same end state
            self._seen.add(request_id)
            self.applied += 1
            return True  # first time: side effect performed


if __name__ == "__main__":
    store = AccountStore(Account(id="acct-1", balance=0, version=0))
    final = deposit_with_retry(store, 100)
    print("balance:", final.balance, "version:", final.version)

    proc = IdempotentProcessor()
    for _ in range(3):
        proc.handle("evt-42")  # duplicate delivery
    print("applied:", proc.applied)  # 1, not 3
