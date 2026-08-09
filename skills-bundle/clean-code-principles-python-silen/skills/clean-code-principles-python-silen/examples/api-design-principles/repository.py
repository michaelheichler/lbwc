"""Repository interface + parameterized-SQL implementation
(Silen ch06 / book ch8.1.2.11, 8.1.2.2).

Principles shown:

- The repository is a ``Protocol`` (structural interface). The service depends
  on the abstraction, the SQL / Mongo / ORM implementation is injected. You can
  swap storage engines without touching business logic, and tests use a fake.
- ALWAYS parameterize SQL. User-supplied filter/sort/pagination values reach
  the query, so string-built SQL is a direct injection hole. Placeholders +
  a values tuple are the only safe form.
- Validate identifiers that cannot be parameterized (column names for
  ``fields`` / ``sort-by``) against an allow-list, cap ``limit`` so a client
  cannot request a million rows (a cheap denial-of-service).
- The repository returns domain ENTITIES, never DTOs and never raw rows.

This uses sqlite3 so it runs with no external services.

Run: python repository.py
"""

from __future__ import annotations

import sqlite3
from typing import Protocol

from dtos import InputSalesItem, SalesItem, SalesItemImage
from errors import DatabaseError, EntityNotFoundError

# Identifiers can't be bound as SQL parameters. The strongest defence is to map
# each allowed sort key to a FULLY STATIC query string: no client text ever
# reaches the SQL text, so there is nothing to inject and nothing for a scanner
# to flag. (An allow-list + f-string also works, but a static map is safer by
# construction and clearer to reviewers.)
_SELECT_BY_SORT_KEY: dict[str, str] = {
    "created_at_ms": (
        "SELECT id, created_at_ms, name, price_in_cents "
        "FROM sales_items ORDER BY created_at_ms LIMIT ?"
    ),
    "name": (
        "SELECT id, created_at_ms, name, price_in_cents FROM sales_items ORDER BY name LIMIT ?"
    ),
    "price_in_cents": (
        "SELECT id, created_at_ms, name, price_in_cents "
        "FROM sales_items ORDER BY price_in_cents LIMIT ?"
    ),
}
_DEFAULT_SORT_KEY = "created_at_ms"
_MAX_LIMIT = 100


class SalesItemRepository(Protocol):
    def save(self, item: InputSalesItem) -> SalesItem: ...
    def find_all(self, *, sort_by: str, limit: int) -> list[SalesItem]: ...
    def find(self, item_id: str) -> SalesItem | None: ...
    def update(self, item_id: str, item: InputSalesItem) -> None: ...
    def delete(self, item_id: str) -> None: ...


class SqliteSalesItemRepository(SalesItemRepository):
    def __init__(self, connection: sqlite3.Connection) -> None:
        self._conn = connection
        self._create_schema()

    def _create_schema(self) -> None:
        self._conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS sales_items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at_ms INTEGER NOT NULL,
                name TEXT NOT NULL,
                price_in_cents INTEGER NOT NULL
            );
            """
        )

    def save(self, item: InputSalesItem) -> SalesItem:
        try:
            cursor = self._conn.execute(
                # Placeholders, not f-strings: the values are never trusted.
                "INSERT INTO sales_items (created_at_ms, name, price_in_cents) VALUES (?, ?, ?)",
                (1_700_000_000_000, item.name, item.price_in_cents),
            )
            self._conn.commit()
        except sqlite3.Error as error:
            raise DatabaseError(error) from error

        new_id = cursor.lastrowid
        assert new_id is not None
        return SalesItem(
            sales_item_id=new_id,
            created_at_ms=1_700_000_000_000,
            name=item.name,
            price_in_cents=item.price_in_cents,
            images=[
                SalesItemImage(image_id=i, rank=img.rank, url=str(img.url))
                for i, img in enumerate(item.images)
            ],
        )

    def find_all(
        self, *, sort_by: str = _DEFAULT_SORT_KEY, limit: int = _MAX_LIMIT
    ) -> list[SalesItem]:
        # Look up a pre-written static query by the client's sort key. An
        # unknown key falls back to the default. No client text reaches SQL,
        # and the limit is capped so a client can't pull the whole table.
        query = _SELECT_BY_SORT_KEY.get(sort_by, _SELECT_BY_SORT_KEY[_DEFAULT_SORT_KEY])
        safe_limit = max(1, min(limit, _MAX_LIMIT))
        try:
            rows = self._conn.execute(query, (safe_limit,)).fetchall()
        except sqlite3.Error as error:
            raise DatabaseError(error) from error
        return [self._row_to_entity(row) for row in rows]

    def find(self, item_id: str) -> SalesItem | None:
        if not item_id.isdigit():
            return None
        try:
            row = self._conn.execute(
                "SELECT id, created_at_ms, name, price_in_cents FROM sales_items WHERE id = ?",
                (int(item_id),),
            ).fetchone()
        except sqlite3.Error as error:
            raise DatabaseError(error) from error
        return self._row_to_entity(row) if row else None

    def update(self, item_id: str, item: InputSalesItem) -> None:
        if not item_id.isdigit():
            raise EntityNotFoundError("Sales item", item_id)
        try:
            self._conn.execute(
                "UPDATE sales_items SET name = ?, price_in_cents = ? WHERE id = ?",
                (item.name, item.price_in_cents, int(item_id)),
            )
            self._conn.commit()
        except sqlite3.Error as error:
            raise DatabaseError(error) from error

    def delete(self, item_id: str) -> None:
        # Idempotent: deleting a missing row is a success, not a 404.
        if not item_id.isdigit():
            return
        try:
            self._conn.execute("DELETE FROM sales_items WHERE id = ?", (int(item_id),))
            self._conn.commit()
        except sqlite3.Error as error:
            raise DatabaseError(error) from error

    @staticmethod
    def _row_to_entity(row: tuple[int, int, str, int]) -> SalesItem:
        item_id, created_at_ms, name, price_in_cents = row
        return SalesItem(
            sales_item_id=item_id,
            created_at_ms=created_at_ms,
            name=name,
            price_in_cents=price_in_cents,
        )


if __name__ == "__main__":
    repo = SqliteSalesItemRepository(sqlite3.connect(":memory:"))
    saved = repo.save(InputSalesItem(name="Widget", priceInCents=999, images=[]))
    print("saved id:", saved.sales_item_id)
    print("find_all:", repo.find_all())
    print("missing find:", repo.find("999"))
    repo.delete("999")  # no error: idempotent
