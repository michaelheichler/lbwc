"""Avoid primitive obsession with semantic value types (Silen ch02 / book
ch4.16).

Two raw ``int`` parameters can be swapped silently: ``Rectangle(50, 20)`` may
mean (width, height) or (height, width), the type checker cannot tell. Worse,
an ``int`` port lets ``99999`` through even though valid ports are 1..65535,
and that validation gets copy-pasted everywhere a port appears.

Fix: wrap primitives in NewType / frozen value objects that (a) make argument
order type-checked and (b) centralize validation in one factory.

Run: python primitive_obsession.py  (and: mypy primitive_obsession.py)
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import NewType, Self

# --- cheap version: NewType gives zero-cost distinct types for type checking -
Width = NewType("Width", int)
Height = NewType("Height", int)


@dataclass(frozen=True, slots=True)
class Rectangle:
    width: Width
    height: Height

    def area(self) -> int:
        return self.width * self.height


# --- richer version: a validated value object that cannot hold a bad value ---
@dataclass(frozen=True, slots=True)
class Port:
    value: int

    @classmethod
    def create(cls, value: int) -> Self:
        # Validation lives here ONCE. Every Port in the system is valid.
        if not 1 <= value <= 65535:
            raise ValueError(f"port out of range: {value}")
        return cls(value)


def connect(host: str, port: Port) -> str:
    return f"connecting to {host}:{port.value}"


def main() -> None:
    rect = Rectangle(Width(50), Height(20))  # order is type-checked
    print("area:", rect.area())
    print(connect("db.internal", Port.create(5432)))
    try:
        Port.create(99_999)
    except ValueError as err:
        print("rejected:", err)


if __name__ == "__main__":
    main()
