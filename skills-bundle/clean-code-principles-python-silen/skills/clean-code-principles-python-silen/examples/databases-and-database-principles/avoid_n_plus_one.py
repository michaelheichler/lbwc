"""Avoiding the N+1 query problem with eager loading.

Principles shown:
- Loading a collection then touching each row's relationship lazily fires 1
  query for the parents + N for the children = N+1 round trips.
- Eager-load the relationship (joined/selectin) so the data arrives in 1-2
  queries regardless of N.

`echo=True` prints every SQL statement so you can SEE the difference: the
naive loop emits one SELECT per order, the eager version emits one.

Run: python avoid_n_plus_one.py
"""

from __future__ import annotations

from sqlalchemy import ForeignKey, create_engine, select
from sqlalchemy.orm import (
    DeclarativeBase,
    Mapped,
    Session,
    mapped_column,
    relationship,
    selectinload,
)


class Base(DeclarativeBase):
    pass


class Order(Base):
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(primary_key=True)
    # Default loading is lazy: each `order.items` access hits the DB.
    items: Mapped[list[OrderItem]] = relationship(back_populates="order")


class OrderItem(Base):
    __tablename__ = "order_items"

    id: Mapped[int] = mapped_column(primary_key=True)
    order_id: Mapped[int] = mapped_column(ForeignKey("orders.id"))
    sku: Mapped[str]
    order: Mapped[Order] = relationship(back_populates="items")


def total_items_naive(session: Session) -> int:
    """✗ N+1: 1 query for orders, then 1 lazy query per order for its items."""
    orders = session.scalars(select(Order)).all()
    return sum(len(order.items) for order in orders)  # each .items = a query


def total_items_eager(session: Session) -> int:
    """✓ Two queries total: orders, then all items in one IN(...) SELECT.

    Use `selectinload` for one-to-many (no row fan-out), use `joined` /
    `lazy='joined'` for many-to-one. Both kill the per-row round trip.
    """
    statement = select(Order).options(selectinload(Order.items))
    orders = session.scalars(statement).all()
    return sum(len(order.items) for order in orders)  # already in memory


def _demo() -> None:
    engine = create_engine("sqlite://", echo=True)  # echo shows the N+1
    Base.metadata.create_all(engine)
    with Session(engine) as session:
        for order_index in range(3):
            order = Order()
            order.items = [OrderItem(sku=f"sku-{order_index}-{i}") for i in range(2)]
            session.add(order)
        session.commit()

    with Session(engine) as session:
        print("--- naive (watch for one SELECT per order) ---")
        assert total_items_naive(session) == 6

    with Session(engine) as session:
        print("--- eager (two SELECTs total) ---")
        assert total_items_eager(session) == 6

    print("avoid_n_plus_one OK")


if __name__ == "__main__":
    _demo()
