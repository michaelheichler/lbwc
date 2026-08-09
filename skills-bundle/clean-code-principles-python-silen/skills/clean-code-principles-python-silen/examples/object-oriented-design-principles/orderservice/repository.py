"""Output interface adapter: repository (Silen ch02 / book ch4.6, 4.12).

``OrderRepository`` is a PROTOCOL, an abstract "place where order aggregates
live". The word *repository* deliberately says nothing about SQL: a concrete
implementation can be a relational DB, a document store, a file, or (here) an
in-memory dict. The service depends only on this protocol, so switching storage
is adding a class, never editing the use case (open/closed + dependency
inversion).
"""

from __future__ import annotations

from itertools import count
from typing import Protocol

from .entities import Order


class OrderRepository(Protocol):
    def save(self, order: Order) -> Order: ...
    def find(self, order_id: int) -> Order | None: ...
    def find_by_user_id(self, user_id: int) -> Order | None: ...


class InMemoryOrderRepository:
    """One concrete output adapter. Swap for SqlOrderRepository /
    MongoOrderRepository without touching the service layer."""

    def __init__(self) -> None:
        self._orders: dict[int, Order] = {}
        self._ids = count(1)

    def save(self, order: Order) -> Order:
        if order.id == 0:  # 0 == "unsaved", assign an id on first save
            order.id = next(self._ids)
        self._orders[order.id] = order
        return order

    def find(self, order_id: int) -> Order | None:
        return self._orders.get(order_id)

    def find_by_user_id(self, user_id: int) -> Order | None:
        return next((o for o in self._orders.values() if o.user_id == user_id), None)
