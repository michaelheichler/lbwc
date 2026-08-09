"""Demonstrates: Input Validation + DTO-not-entity boundary (ch05 §7.4.14).

Principles shown:
- Validate every field from an untrusted source (type, range, length, allowed set).
- Bound string length *before* any expensive check (ReDoS / DoS prevention).
- Use distinct input/output DTOs so internal/sensitive fields can never cross
  the trust boundary (no `is_admin`, `id`, `password_hash` accepted from clients).
- Reject unknown fields so junk cannot leak into a schemaless store.

Run: uv run --with 'pydantic>=2' python input_validation_dtos.py
"""

from __future__ import annotations

from datetime import UTC, datetime
from decimal import Decimal
from enum import StrEnum

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator


class OrderStatus(StrEnum):
    PLACED = "placed"
    SHIPPED = "shipped"
    CANCELLED = "cancelled"


# --- INPUT DTO: the only shape accepted from a client -------------------------
class InputOrder(BaseModel):
    """What a client is allowed to send. No id, no user_id-from-body trust,
    no status, no timestamps. Those are server-controlled."""

    # extra='forbid' rejects unknown keys -> stops field injection into the DB.
    model_config = ConfigDict(extra="forbid", str_max_length=200, frozen=True)

    product_code: str = Field(min_length=1, max_length=32, pattern=r"^[A-Z0-9-]+$")
    # Range-bound numbers: an unbounded quantity is a DoS vector.
    quantity: int = Field(ge=1, le=1000)
    unit_price: Decimal = Field(ge=Decimal("0.01"), le=Decimal("1000000"))
    note: str | None = Field(default=None, max_length=500)

    @field_validator("note")
    @classmethod
    def _strip_control_chars(cls, value: str | None) -> str | None:
        if value is None:
            return None
        if any(ch.isprintable() is False and ch not in "\n\t" for ch in value):
            raise ValueError("note contains non-printable characters")
        return value


class InputUser(BaseModel):
    """Same idea for users: `is_admin`/`id` are absent by construction, so a
    client cannot self-promote even if it sends those keys (extra='forbid')."""

    model_config = ConfigDict(extra="forbid", str_max_length=320)

    username: str = Field(min_length=3, max_length=32, pattern=r"^[a-zA-Z0-9_.-]+$")
    email: EmailStr
    display_name: str = Field(min_length=1, max_length=80)


# --- OUTPUT DTO: the only shape returned to a client --------------------------
class OutputUser(BaseModel):
    """Explicit allow-list of fields that may leave the service. `password_hash`,
    internal flags, etc. simply do not exist here, so they cannot leak."""

    id: int
    username: str
    email: EmailStr
    display_name: str
    created_at: datetime


# --- Server-side entity (NEVER serialized directly to a client) ---------------
class UserEntity(BaseModel):
    id: int
    username: str
    email: EmailStr
    display_name: str
    password_hash: str  # sensitive: must never reach OutputUser
    is_admin: bool
    created_at: datetime

    def to_output(self) -> OutputUser:
        return OutputUser(
            id=self.id,
            username=self.username,
            email=self.email,
            display_name=self.display_name,
            created_at=self.created_at,
        )


def main() -> None:
    order = InputOrder(product_code="SKU-12", quantity=3, unit_price=Decimal("9.99"))
    print("valid order:", order)

    # A malicious client tries to inject an internal field:
    try:
        InputUser.model_validate(
            {
                "username": "mallory",
                "email": "m@x.io",
                "display_name": "M",
                "is_admin": True,
            }
        )
    except ValueError as exc:
        print("rejected privilege-escalation attempt:", type(exc).__name__)

    entity = UserEntity(
        id=1,
        username="alice",
        email="alice@example.com",
        display_name="Alice",
        password_hash="argon2$...",  # noqa: S106  # demo hash literal, not a real credential
        is_admin=False,
        created_at=datetime.now(UTC),
    )
    # password_hash / is_admin are structurally absent from the response.
    print("safe response:", entity.to_output().model_dump())


if __name__ == "__main__":
    main()
