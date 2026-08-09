"""Parameterized queries + allow-list mapping for non-bindable SQL parts.

Principles shown:
- Never interpolate user data into SQL, bind it or pass it through the
  expression language so the driver parameterizes it for you.
- Identifiers (column to sort by, direction) cannot be bound - map the
  client's choice to a pre-approved Column object, never to raw text.

This uses SQLAlchemy Core (not the ORM): `table.c.price >= bindparam`
compiles to a parameterized statement, and `select().order_by(column)`
takes a real Column, so a client can never inject an identifier.

Run: python parameterized_queries.py
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Final

from sqlalchemy import (
    Column,
    Integer,
    MetaData,
    String,
    Table,
    asc,
    create_engine,
    desc,
    select,
)
from sqlalchemy.engine import Engine, Row

_metadata = MetaData()
sales_items = Table(
    "sales_items",
    _metadata,
    Column("id", Integer, primary_key=True),
    Column("name", String(256), nullable=False),
    Column("price_in_cents", Integer, nullable=False, index=True),
)

# Map the client's free-text choice to a real Column object. The client never
# supplies an identifier string that reaches SQL - only a dict key. Anything
# off the map raises, so `name; DROP TABLE ...` simply misses.
_SORTABLE: Final[dict[str, Column[object]]] = {
    "id": sales_items.c.id,
    "name": sales_items.c.name,
    "price_in_cents": sales_items.c.price_in_cents,
}


class InvalidSortError(ValueError):
    """Raised when a client-supplied sort column is not allow-listed."""


def find_above_price(engine: Engine, min_price_in_cents: int) -> list[Row[object]]:
    """✓ The value is BOUND by the expression language, never formatted in."""
    statement = select(sales_items).where(sales_items.c.price_in_cents >= min_price_in_cents)
    with engine.connect() as connection:
        return list(connection.execute(statement).all())


def find_sorted(engine: Engine, sort_column: str, *, descending: bool) -> list[Row[object]]:
    """Identifiers can't be bound, so resolve to a real Column via the map."""
    column = _SORTABLE.get(sort_column)
    if column is None:
        raise InvalidSortError(sort_column)
    order = desc(column) if descending else asc(column)
    statement = select(sales_items).order_by(order)
    with engine.connect() as connection:
        return list(connection.execute(statement).all())


def find_by_ids(engine: Engine, ids: Sequence[int]) -> list[Row[object]]:
    """Variable-length IN clause via `.in_()` - the driver binds every id."""
    if not ids:
        return []
    statement = select(sales_items.c.id, sales_items.c.name).where(sales_items.c.id.in_(ids))
    with engine.connect() as connection:
        return list(connection.execute(statement).all())


def _demo() -> None:
    engine = create_engine("sqlite://")
    _metadata.create_all(engine)
    with engine.begin() as connection:
        connection.execute(
            sales_items.insert(),
            [
                {"name": "drill", "price_in_cents": 9_999},
                {"name": "saw", "price_in_cents": 4_500},
                {"name": "hammer", "price_in_cents": 1_200},
            ],
        )

    assert len(find_above_price(engine, 4_000)) == 2
    assert find_sorted(engine, "price_in_cents", descending=False)[0].name == "hammer"
    assert len(find_by_ids(engine, [1, 3])) == 2

    try:
        find_sorted(engine, "password_hash; DROP TABLE sales_items", descending=False)
    except InvalidSortError:
        pass
    else:  # pragma: no cover
        raise AssertionError("allow-list failed to reject injection attempt")

    print("parameterized_queries OK")


if __name__ == "__main__":
    _demo()
