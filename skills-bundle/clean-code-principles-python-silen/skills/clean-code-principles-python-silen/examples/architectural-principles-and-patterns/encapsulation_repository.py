"""Encapsulation principle (microservice owns its state) + explicit DTO mapping.

A microservice encapsulates its data store behind a public API. Nothing outside
the service touches its database. Access goes through a repository whose method
names express the *domain contract*, not table mechanics. Two concrete habits
this enforces, both lifted from the chapter's Django example:

1. Never serialize the whole entity. Listing fields explicitly (the analogue of
   DRF's ``fields = [...]`` instead of ``fields = "__all__"``) means a column you
   add for internal bookkeeping does not silently leak to clients.
2. The repository is the only seam to the store, so swapping the backing store
   (the Encapsulation + Service Substitution combo) never ripples into callers.

This is plain stdlib so it runs anywhere. In a real service the repository body
would issue SQL or a DRF/ORM query. See fluent-python ch05 (dataclasses) and
ch08 (Protocol).

Run:  python encapsulation_repository.py
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol, TypedDict


@dataclass(frozen=True, slots=True)
class SalesItem:
    """Internal entity. ``cost_price`` is private business data, not for clients."""

    id: int
    user_account_id: int
    name: str
    price_cents: int
    cost_price_cents: int  # internal margin data, must never be serialized


class SalesItemDTO(TypedDict):
    """The public shape. Explicitly enumerated, so new entity fields do not leak."""

    id: int
    userAccountId: int
    name: str
    priceCents: int


def to_dto(item: SalesItem) -> SalesItemDTO:
    # ✓ Whitelist the public fields. ✗ {**item.__dict__} would expose cost_price.
    return SalesItemDTO(
        id=item.id,
        userAccountId=item.user_account_id,
        name=item.name,
        priceCents=item.price_cents,
    )


class SalesItemRepository(Protocol):
    """Public contract over the private store, the only door to the data."""

    def get(self, item_id: int) -> SalesItem | None: ...
    def list_for_user(self, user_account_id: int) -> list[SalesItem]: ...


class InMemorySalesItemRepository:
    """One concrete store. A SQL- or ORM-backed one would satisfy the same Protocol."""

    def __init__(self, items: list[SalesItem]) -> None:
        self._items = {item.id: item for item in items}

    def get(self, item_id: int) -> SalesItem | None:
        return self._items.get(item_id)

    def list_for_user(self, user_account_id: int) -> list[SalesItem]:
        return [item for item in self._items.values() if item.user_account_id == user_account_id]


if __name__ == "__main__":
    repo: SalesItemRepository = InMemorySalesItemRepository(
        [
            SalesItem(
                1,
                user_account_id=2,
                name="bike",
                price_cents=29900,
                cost_price_cents=18000,
            ),
            SalesItem(
                2,
                user_account_id=2,
                name="helmet",
                price_cents=4900,
                cost_price_cents=2200,
            ),
        ]
    )
    dtos = [to_dto(item) for item in repo.list_for_user(2)]
    print(dtos)  # cost_price_cents is absent, encapsulation held
