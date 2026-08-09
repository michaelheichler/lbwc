"""Demonstrates: SQL injection prevention (ch05 §7.4.6).

Principles shown:
- Never concatenate/f-string user *data* into SQL. Use bound parameters ('?').
- Identifiers (table/column names) and sort order cannot be parameter-bound, so
  resolve them to a *fully pre-written literal query* via an allow-list dict.
  No user-influenced string is ever assembled into the SQL text at runtime.
- Cap the number of returned rows to prevent mass disclosure.

Uses stdlib sqlite3 so it runs with zero dependencies.
Run: python parameterized_sql.py
"""

from __future__ import annotations

import sqlite3
from typing import Final

# Identifiers/ORDER BY can't be bound -> map caller input to a COMPLETE literal
# query that we authored. The user string only ever selects a dict key.
_LIST_QUERIES: Final[dict[str, str]] = {
    "id": "SELECT id, name FROM users ORDER BY id LIMIT ?",
    "name": "SELECT id, name FROM users ORDER BY name LIMIT ?",
    "created_at": "SELECT id, name FROM users ORDER BY created_at LIMIT ?",
}
_MAX_PAGE_SIZE: Final[int] = 100


def find_user_by_name(conn: sqlite3.Connection, name: str) -> list[tuple[object, ...]]:
    # GOOD: '?' placeholder. The driver sends value and SQL separately, so
    # `name = "x'; DROP TABLE users; --"` is treated as a literal string.
    cur = conn.execute("SELECT id, name FROM users WHERE name = ?", (name,))
    return cur.fetchall()


def find_two_users(conn: sqlite3.Connection, first: str, second: str) -> list[tuple[object, ...]]:
    # Fixed-arity IN with literal placeholders, values stay in the params tuple.
    cur = conn.execute("SELECT id, name FROM users WHERE name IN (?, ?)", (first, second))
    return cur.fetchall()


def list_users(
    conn: sqlite3.Connection, *, sort_by: str, page_size: int
) -> list[tuple[object, ...]]:
    # `sort_by` selects a fixed, pre-written query -> no user text reaches SQL.
    query = _LIST_QUERIES.get(sort_by)
    if query is None:
        raise ValueError(f"illegal sort column: {sort_by!r}")
    # LIMIT is bound as a parameter, the value is also clamped to bound cost.
    safe_limit = max(1, min(page_size, _MAX_PAGE_SIZE))
    return conn.execute(query, (safe_limit,)).fetchall()


# --- The mistake this file refuses to make -----------------------------------
def find_user_INSECURE(conn: sqlite3.Connection, name: str) -> None:  # noqa: N802
    """NEVER DO THIS. Shown only as the anti-pattern to recognize.

    The forbidden form interpolates user text into the SQL string, e.g.
    execute("... WHERE name = '" + name + "'"):
    - name = "x' OR '1'='1"             -> returns every row
    - name = "x'; DROP TABLE users; --" -> destroys the table
    Use find_user_by_name (bound '?') instead.
    """
    raise NotImplementedError("string-built SQL is forbidden, use find_user_by_name")


def main() -> None:
    conn = sqlite3.connect(":memory:")
    conn.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, created_at TEXT)")
    conn.executemany(
        "INSERT INTO users (name, created_at) VALUES (?, ?)",
        [("alice", "2025-01-01"), ("bob", "2025-02-01")],
    )
    # Injection payload is harmlessly treated as a literal -> no rows.
    print("injection attempt:", find_user_by_name(conn, "x' OR '1'='1"))
    print("legit lookup:", find_user_by_name(conn, "alice"))
    print("in clause:", find_two_users(conn, "alice", "bob"))
    print("sorted page:", list_users(conn, sort_by="name", page_size=10))
    try:
        list_users(conn, sort_by="name; DROP TABLE users", page_size=10)
    except ValueError as exc:
        print("blocked bad sort column:", exc)


if __name__ == "__main__":
    main()
