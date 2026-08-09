"""DTOs crossing the API boundary (Silen ch02 / book ch4.6 + Appendix A).

DTOs are the only place where a plain data class with no behavior is correct,
the *program against interfaces* rule explicitly exempts behaviorless data
classes. They keep the wire shape (what a client sends/receives) decoupled from
the domain entities (what the core manipulates), so the API can evolve without
touching the aggregate.

The book defines ids as strings on DTOs so 64-bit ids survive JavaScript
clients. That convention is kept here.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class InputOrderItem:
    sales_item_id: int
    quantity: int
    unit_price_cents: int


@dataclass(frozen=True, slots=True)
class InputOrder:
    user_id: int
    items: list[InputOrderItem]


@dataclass(frozen=True, slots=True)
class OutputOrderItem:
    id: str
    sales_item_id: str
    quantity: int


@dataclass(frozen=True, slots=True)
class OutputOrder:
    id: str  # string id: safe for JS clients (book convention)
    user_id: str
    items: list[OutputOrderItem]
    total_cents: int
