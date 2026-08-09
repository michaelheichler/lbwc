"""Repository pattern: hide persistence behind a Protocol the domain owns.

Principles shown:
- Use a repository to isolate domain logic from the storage engine.
- The repository returns/accepts domain objects, never driver cursors or rows.
- Swapping SQLite -> Postgres -> Mongo touches one class, not the callers.

The domain depends on `SalesItemRepository` (a Protocol). Any concrete
backend (SQLAlchemy here) satisfies it structurally - no ABC inheritance
required. See fluent-python ch13 for Protocol vs ABC.

Run: python repository_pattern.py
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol

from sqlalchemy import String, create_engine, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import (
    DeclarativeBase,
    Mapped,
    Session,
    mapped_column,
    sessionmaker,
)


# --- Domain DTOs (what callers see, no ORM types leak out) ------------------
@dataclass(frozen=True, slots=True)
class NewSalesItem:
    """Input DTO: a sales item the caller wants to create."""

    name: str
    price_in_cents: int


@dataclass(slots=True)
class SalesItem:
    """Domain entity returned to callers - decoupled from ORM rows."""

    id: int
    name: str
    price_in_cents: int


# --- Repository Protocol: the seam the domain owns --------------------------
class SalesItemRepository(Protocol):
    """Storage-agnostic contract. Domain code imports THIS, not SQLAlchemy."""

    def save(self, item: NewSalesItem) -> SalesItem: ...
    def find(self, item_id: int) -> SalesItem | None: ...
    def find_all(self) -> list[SalesItem]: ...
    def delete(self, item_id: int) -> None: ...


# --- A domain-specific error so callers never catch driver exceptions -------
class RepositoryError(Exception):
    """Raised instead of leaking SQLAlchemyError / driver errors upward."""


# --- SQLAlchemy implementation ---------------------------------------------
class Base(DeclarativeBase):
    pass


class SalesItemRow(Base):
    __tablename__ = "sales_items"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(256))
    price_in_cents: Mapped[int] = mapped_column(index=True)


class OrmSalesItemRepository:
    """Concrete repository. Translates rows <-> domain entities and
    converts every driver failure into a RepositoryError."""

    def __init__(self, database_url: str) -> None:
        engine = create_engine(database_url)
        Base.metadata.create_all(engine)
        # One sessionmaker per repository, sessions are created per call.
        self._session_factory: sessionmaker[Session] = sessionmaker(bind=engine)

    @staticmethod
    def _to_entity(row: SalesItemRow) -> SalesItem:
        return SalesItem(id=row.id, name=row.name, price_in_cents=row.price_in_cents)

    def save(self, item: NewSalesItem) -> SalesItem:
        try:
            with self._session_factory() as session:
                row = SalesItemRow(name=item.name, price_in_cents=item.price_in_cents)
                session.add(row)
                session.commit()
                session.refresh(row)  # populate DB-generated id before detaching
                return self._to_entity(row)
        except SQLAlchemyError as error:
            raise RepositoryError("save failed") from error

    def find(self, item_id: int) -> SalesItem | None:
        try:
            with self._session_factory() as session:
                row = session.get(SalesItemRow, item_id)
                return None if row is None else self._to_entity(row)
        except SQLAlchemyError as error:
            raise RepositoryError("find failed") from error

    def find_all(self) -> list[SalesItem]:
        try:
            with self._session_factory() as session:
                rows = session.scalars(select(SalesItemRow)).all()
                return [self._to_entity(row) for row in rows]
        except SQLAlchemyError as error:
            raise RepositoryError("find_all failed") from error

    def delete(self, item_id: int) -> None:
        try:
            with self._session_factory() as session:
                row = session.get(SalesItemRow, item_id)
                if row is not None:
                    session.delete(row)
                    session.commit()
        except SQLAlchemyError as error:
            raise RepositoryError("delete failed") from error


# --- Domain service depends ONLY on the Protocol ----------------------------
@dataclass(slots=True)
class Catalog:
    """Pure domain logic - testable with an in-memory fake repository."""

    repository: SalesItemRepository
    audit_log: list[str] = field(default_factory=list)

    def add_item(self, name: str, price_in_cents: int) -> SalesItem:
        saved = self.repository.save(NewSalesItem(name=name, price_in_cents=price_in_cents))
        self.audit_log.append(f"added {saved.id}")
        return saved


def _demo() -> None:
    repo = OrmSalesItemRepository("sqlite://")  # in-memory
    catalog = Catalog(repository=repo)
    drill = catalog.add_item("Cordless drill", 9_999)
    assert repo.find(drill.id) == drill
    assert len(repo.find_all()) == 1
    repo.delete(drill.id)
    assert repo.find(drill.id) is None
    print("repository_pattern OK", catalog.audit_log)


if __name__ == "__main__":
    _demo()
