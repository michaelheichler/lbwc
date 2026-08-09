"""Service Aggregation + High Cohesion / Low Coupling principles.

A higher-level (aggregating) service is a *facade* over several lower-level,
single-responsibility services. Clients talk only to the facade. The lower-level
services stay decoupled from each other and from the client. The facade fans out
the independent calls concurrently with ``asyncio.gather`` so latency is the
slowest dependency, not the sum.

This is an original, runnable rewrite of the book's Ariadne GraphQL aggregator
with the framework stripped away: the architecture (concurrent fan-out behind a
typed facade) is the point, not GraphQL. The lower-level "services" are Protocols
so the aggregator depends on an interface, not a concrete transport, which is
exactly what lets you substitute an HTTP client for the in-memory stubs here.

See fluent-python ch08 (Protocol) and ch21 (asyncio) for the language mechanics.

Run:  python service_aggregation.py
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True, slots=True)
class UserAccount:
    id: int
    user_name: str


@dataclass(frozen=True, slots=True)
class SalesItem:
    id: int
    name: str


@dataclass(frozen=True, slots=True)
class Order:
    id: int
    user_id: int


@dataclass(frozen=True, slots=True)
class User:
    """The aggregated view the facade returns to clients."""

    account: UserAccount
    sales_items: list[SalesItem]
    orders: list[Order]


# Each lower-level service is one responsibility, expressed as an interface.
class UserAccountService(Protocol):
    async def get_account(self, user_id: int) -> UserAccount: ...


class SalesItemService(Protocol):
    async def list_for_user(self, user_id: int) -> list[SalesItem]: ...


class OrderService(Protocol):
    async def list_for_user(self, user_id: int) -> list[Order]: ...


class EcommerceService:
    """Higher-level facade aggregating three lower-level services.

    Coupling stays low: the three injected services do not know about each other,
    and the client does not know about them at all. Swapping any one of them is a
    constructor change here, nothing else.
    """

    def __init__(
        self,
        accounts: UserAccountService,
        sales_items: SalesItemService,
        orders: OrderService,
    ) -> None:
        self._accounts = accounts
        self._sales_items = sales_items
        self._orders = orders

    async def get_user(self, user_id: int) -> User:
        # ✓ Independent calls run concurrently, total latency ≈ the slowest one.
        #   ✗ Awaiting them one-by-one would serialize three remote round-trips.
        account, sales_items, orders = await asyncio.gather(
            self._accounts.get_account(user_id),
            self._sales_items.list_for_user(user_id),
            self._orders.list_for_user(user_id),
        )
        return User(account=account, sales_items=sales_items, orders=orders)


# --- In-memory stubs standing in for remote microservices --------------------
class _StubAccounts:
    async def get_account(self, user_id: int) -> UserAccount:
        return UserAccount(id=user_id, user_name="pksilen")


class _StubSalesItems:
    async def list_for_user(self, user_id: int) -> list[SalesItem]:
        return [SalesItem(id=user_id, name=f"sales item for user {user_id}")]


class _StubOrders:
    async def list_for_user(self, user_id: int) -> list[Order]:
        return [Order(id=1, user_id=user_id)]


async def _main() -> None:
    service = EcommerceService(_StubAccounts(), _StubSalesItems(), _StubOrders())
    user = await service.get_user(user_id=2)
    print(user)


if __name__ == "__main__":
    asyncio.run(_main())
