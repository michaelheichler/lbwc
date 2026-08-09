"""Domain entities & value objects, the stable core (Silen ch02 / book ch4.12).

Tactical DDD vocabulary, made concrete:

- Value object (``Money``): no identity, compared by value -> frozen dataclass.
- Entity (``OrderItem``): has identity (an id) and lives inside an aggregate.
- Aggregate root (``Order``): the ONLY entry point to its OrderItems. Callers
  never touch order items directly. They tell the Order, which protects the
  aggregate's invariants (e.g. total == sum of line totals).

This module imports nothing from outer layers. Entities are the centre of the
dependency graph and change the least often.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True, slots=True)
class Money:
    """Value object: amount in minor units (cents) + currency, no identity."""

    cents: int
    currency: str = "EUR"

    def __post_init__(self) -> None:
        if self.cents < 0:
            raise ValueError("Money cannot be negative")

    def __add__(self, other: Money) -> Money:
        if self.currency != other.currency:
            raise ValueError("currency mismatch")
        return Money(self.cents + other.cents, self.currency)

    def times(self, quantity: int) -> Money:
        return Money(self.cents * quantity, self.currency)


@dataclass(slots=True)
class OrderItem:
    """Entity inside the Order aggregate. Identity = (order_id, id)."""

    id: int
    sales_item_id: int
    quantity: int
    unit_price: Money

    def __post_init__(self) -> None:
        if self.quantity <= 0:
            raise ValueError("quantity must be positive")

    def line_total(self) -> Money:
        return self.unit_price.times(self.quantity)


@dataclass(slots=True)
class Order:
    """Aggregate ROOT. All mutation goes through its methods so the aggregate
    enforces its own invariants (don't-ask-tell + Law of Demeter)."""

    id: int
    user_id: int
    _items: list[OrderItem] = field(default_factory=list)

    def add_item(self, item: OrderItem) -> None:
        # Behavior lives on the root, not in a service reaching into _items.
        self._items.append(item)

    def total(self) -> Money:
        running = Money(0)
        for item in self._items:
            running += item.line_total()
        return running

    @property
    def items(self) -> tuple[OrderItem, ...]:
        # Read-only view: returning the list would let callers mutate the
        # aggregate behind its back (don't-leak-internal-state).
        return tuple(self._items)
