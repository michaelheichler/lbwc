"""Connection config from the environment + pooled engine (singleton).

Principles shown:
- Read the database URL from the environment, never hard-code host/user/
  password in source (they leak through git and can't vary per deploy).
- Create ONE pooled engine per process and reuse it, building an engine (or
  raw connection) per request exhausts the DB's connection limit.
- Parse the URL with a real parser (urllib), not string .split() chains.

Run: DATABASE_URL=sqlite:// python connection_url_from_env.py
"""

from __future__ import annotations

import os
from functools import lru_cache
from urllib.parse import urlparse

from sqlalchemy import create_engine
from sqlalchemy.engine import Engine


class MissingDatabaseUrlError(RuntimeError):
    """Raised when DATABASE_URL is not set - fail fast at startup, not mid-request."""


def database_url() -> str:
    url = os.environ.get("DATABASE_URL")
    if not url:
        raise MissingDatabaseUrlError("DATABASE_URL is not set")
    return url


def describe_url(url: str) -> dict[str, str | int | None]:
    """Parse a DB URL safely. urlparse handles credentials/ports/escaping
    that hand-rolled split('@')/split(':') chains get wrong (e.g. '@' or ':'
    inside a password)."""
    parsed = urlparse(url)
    return {
        "scheme": parsed.scheme,
        "host": parsed.hostname,
        "port": parsed.port,
        "database": parsed.path.lstrip("/") or None,
        "user": parsed.username,
        # NOTE: never log parsed.password.
    }


@lru_cache(maxsize=1)
def get_engine() -> Engine:
    """One pooled engine per process. lru_cache makes it a lazy singleton, so
    every caller shares the same connection pool instead of opening new ones.

    pool_pre_ping detects connections dropped by the DB/firewall and replaces
    them, avoiding 'server has gone away' errors after idle periods. The
    QueuePool tuning args only apply to networked DBs, SQLite uses a
    single-thread pool that rejects them, so we pass them conditionally.
    """
    url = database_url()
    if url.startswith("sqlite"):
        return create_engine(url, pool_pre_ping=True)
    return create_engine(
        url,
        pool_size=10,
        max_overflow=5,
        pool_pre_ping=True,
        pool_recycle=1_800,  # recycle connections older than 30 min
    )


def _demo() -> None:
    os.environ.setdefault("DATABASE_URL", "sqlite://")
    info = describe_url("postgresql://app:s3cr3t@db.internal:5432/orders")
    assert info["host"] == "db.internal"
    assert info["port"] == 5432
    assert info["database"] == "orders"
    assert info["user"] == "app"

    engine = get_engine()
    assert get_engine() is engine, "engine must be a reused singleton"
    print("connection_url_from_env OK", info)


if __name__ == "__main__":
    _demo()
