"""DTO / entity split + validate-at-the-boundary (Silen ch06 / book ch8.1.2).

Principles shown:

- Input and output DTOs are SEPARATE types. An input DTO carries only what a
  client may set. An output DTO adds server-assigned fields (``id``,
  ``created_at_ms``). Sharing one class for both leaks writable internals and
  forces optional fields that are never really optional in one direction.
- Validate EVERY field at the boundary, including output. Bounded ``str`` /
  ``list`` lengths are a denial-of-service control, not cosmetics: an
  unbounded ``name`` or 10_000-element ``images`` is an attack surface.
- DTOs are pydantic (parse + validate at the edge), domain entities are plain
  ``@dataclass`` (no framework in the core). The mapping between them is
  explicit, so the web/validation library never reaches the domain layer.

Field names use camelCase on the wire via ``alias`` while staying snake_case
in Python. The JSON shape is an API contract, the Python name is internal.

Run: python dtos.py
"""

from __future__ import annotations

from dataclasses import dataclass, field

from pydantic import BaseModel, ConfigDict, Field, HttpUrl

_MAX_NAME = 256
_MAX_IMAGES = 25


# --- wire DTOs: pydantic, fully bounded ------------------------------------
class _CamelModel(BaseModel):
    # populate_by_name lets Python code use snake_case while the JSON contract
    # stays camelCase. alias_generator would scale this to every field.
    model_config = ConfigDict(populate_by_name=True)


class SalesItemImageDTO(_CamelModel):
    rank: int = Field(ge=0)
    url: HttpUrl


class InputSalesItem(_CamelModel):
    """What a client is ALLOWED to send. No id, no timestamp."""

    name: str = Field(max_length=_MAX_NAME)
    # Negative prices are intentional (discount line items), so no ge=0 here,
    # but the field is still typed and length-free ints cannot blow up memory.
    price_in_cents: int = Field(alias="priceInCents")
    images: list[SalesItemImageDTO] = Field(max_length=_MAX_IMAGES)


class OutputSalesItem(_CamelModel):
    """What the server returns. Adds server-assigned fields and validates them
    on the way OUT too, so a corrupted row cannot reshape the response."""

    id: str
    created_at_ms: int = Field(alias="createdAtTimestampInMs", ge=0)
    name: str = Field(max_length=_MAX_NAME)
    price_in_cents: int = Field(alias="priceInCents")
    images: list[SalesItemImageDTO] = Field(max_length=_MAX_IMAGES)


# --- domain entities: plain dataclasses, no framework ----------------------
@dataclass(frozen=True, slots=True)
class SalesItemImage:
    image_id: int
    rank: int
    url: str


@dataclass(frozen=True, slots=True)
class SalesItem:
    sales_item_id: int
    created_at_ms: int
    name: str
    price_in_cents: int
    images: list[SalesItemImage] = field(default_factory=list)


# --- explicit boundary mapping (entity -> output DTO) ----------------------
def to_output(entity: SalesItem) -> OutputSalesItem:
    return OutputSalesItem(
        id=str(entity.sales_item_id),
        createdAtTimestampInMs=entity.created_at_ms,
        name=entity.name,
        priceInCents=entity.price_in_cents,
        images=[SalesItemImageDTO(rank=img.rank, url=HttpUrl(img.url)) for img in entity.images],
    )


if __name__ == "__main__":
    item = SalesItem(
        sales_item_id=1,
        created_at_ms=1_700_000_000_000,
        name="Sample",
        price_in_cents=2000,
        images=[SalesItemImage(image_id=9, rank=0, url="https://cdn/x.jpg")],
    )
    dto = to_output(item)
    # by_alias=True emits the camelCase contract clients expect.
    print(dto.model_dump_json(by_alias=True))
