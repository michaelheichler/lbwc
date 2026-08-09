"""Normalization (1NF/2NF/3NF) expressed as entity design.

Principles shown:
- 1NF: one atomic value per cell - model repeated values as a child table,
  not a comma-joined string column.
- 2NF: every non-key column depends on the WHOLE composite key, not part of it.
- 3NF: no non-key column depends on another non-key column (no transitive
  dependency) - factor the derived attribute into its own table.

These are SQLAlchemy entity sketches contrasting a denormalized (✗) shape
with the normalized (✓) shape. The point is the SCHEMA, so the file just
declares mappings and asserts the relationships compile.

Run: python normalization.py
"""

from __future__ import annotations

from sqlalchemy import ForeignKey, String, create_engine
from sqlalchemy.orm import (
    DeclarativeBase,
    Mapped,
    mapped_column,
    relationship,
)


class Base(DeclarativeBase):
    pass


# --- 1NF: atomic cells ------------------------------------------------------
# ✗ Denormalized: `tags = "power,cordless,sale"` packs a LIST into one cell.
#   You cannot index, filter, or join on an individual tag.
# ✓ Normalized: one row per tag in a child table.
class Product(Base):
    __tablename__ = "products"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(256))
    # categoryid is a FK, not a denormalized category+discount pair (see 3NF).
    category_id: Mapped[int] = mapped_column(ForeignKey("categories.id"))
    tags: Mapped[list[ProductTag]] = relationship(back_populates="product")
    category: Mapped[Category] = relationship(back_populates="products")


class ProductTag(Base):
    __tablename__ = "product_tags"

    product_id: Mapped[int] = mapped_column(ForeignKey("products.id"), primary_key=True)
    tag: Mapped[str] = mapped_column(String(64), primary_key=True)
    product: Mapped[Product] = relationship(back_populates="tags")


# --- 3NF: no transitive dependency -----------------------------------------
# ✗ Putting `discount` on Product when discount is determined by category
#   means a category change forces a discount change - a non-key column
#   depending on another non-key column.
# ✓ `discount` lives on Category, Product references it by FK only.
class Category(Base):
    __tablename__ = "categories"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(128))
    discount_percent: Mapped[int]  # depends only on the category key
    products: Mapped[list[Product]] = relationship(back_populates="category")


# --- 2NF: full-key dependency ----------------------------------------------
# Composite PK (order_id, line_no). `unit_price` depends on the whole line.
# A column like `order_state` would depend only on order_id (part of the key)
# -> it belongs on an Orders table, not here.
class OrderLine(Base):
    __tablename__ = "order_lines"

    order_id: Mapped[int] = mapped_column(primary_key=True)
    line_no: Mapped[int] = mapped_column(primary_key=True)
    sku: Mapped[str] = mapped_column(String(64))
    unit_price_in_cents: Mapped[int]  # depends on (order_id, line_no) together


def _demo() -> None:
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    # Tables created without error => the normalized schema is well-formed.
    table_names = set(Base.metadata.tables)
    assert table_names == {"products", "product_tags", "categories", "order_lines"}
    print("normalization OK", sorted(table_names))


if __name__ == "__main__":
    _demo()
