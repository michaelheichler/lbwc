"""Event Sourcing + CQRS architectural patterns.

Event sourcing stores state as an append-only sequence of immutable events
(create + read only, never update or delete). The current state is a *fold* over
the events. CQRS then splits the write side (the event log, the "command" model)
from a read-optimized projection (the "query" model / materialized view) so reads
do not pay the cost of replaying events every time.

Why this shape in Python:
- Events are frozen dataclasses under a sealed union: ``match`` over the union
  gives exhaustive, type-checked state transitions.
- The projection is rebuilt by replaying events, proving the log is the single
  source of truth, the read model is derived, never authoritative.

See fluent-python ch05 (frozen dataclasses) and ch02 (structural ``match``).

Run:  python event_sourcing_cqrs.py
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from functools import reduce


class OrderStatus(StrEnum):
    CREATED = "CREATED"
    PAID = "PAID"
    SHIPPED = "SHIPPED"
    CANCELED = "CANCELED"


# --- Write model: immutable events (the command side) ------------------------
@dataclass(frozen=True, slots=True)
class OrderCreated:
    order_id: int
    at: datetime
    total_cents: int


@dataclass(frozen=True, slots=True)
class OrderPaid:
    order_id: int
    at: datetime


@dataclass(frozen=True, slots=True)
class OrderShipped:
    order_id: int
    at: datetime
    tracking_id: str


@dataclass(frozen=True, slots=True)
class OrderCanceled:
    order_id: int
    at: datetime


OrderEvent = OrderCreated | OrderPaid | OrderShipped | OrderCanceled


# --- Read model: the materialized view (the query side) ----------------------
@dataclass(frozen=True, slots=True)
class OrderView:
    order_id: int
    status: OrderStatus
    total_cents: int
    tracking_id: str | None


def _apply(view: OrderView | None, event: OrderEvent) -> OrderView:
    """Fold one event into the projection. Exhaustive over the event union."""
    match event:
        case OrderCreated(order_id, _, total_cents):
            return OrderView(order_id, OrderStatus.CREATED, total_cents, None)
        case OrderPaid() if view is not None:
            return OrderView(view.order_id, OrderStatus.PAID, view.total_cents, view.tracking_id)
        case OrderShipped(_, _, tracking_id) if view is not None:
            return OrderView(view.order_id, OrderStatus.SHIPPED, view.total_cents, tracking_id)
        case OrderCanceled() if view is not None:
            return OrderView(
                view.order_id, OrderStatus.CANCELED, view.total_cents, view.tracking_id
            )
        case _:
            raise ValueError(f"event {event!r} applied to invalid state {view!r}")


def project(events: list[OrderEvent]) -> OrderView:
    """Rebuild the read model by replaying the immutable log."""
    view = reduce(_apply, events, None)
    if view is None:
        raise ValueError("cannot project an empty event log")
    return view


if __name__ == "__main__":
    now = datetime(2026, 6, 4, 12, 0, 0, tzinfo=UTC)
    log: list[OrderEvent] = [
        OrderCreated(order_id=42, at=now, total_cents=29900),
        OrderPaid(order_id=42, at=now),
        OrderShipped(order_id=42, at=now, tracking_id="TRK-7"),
    ]
    print(project(log))
