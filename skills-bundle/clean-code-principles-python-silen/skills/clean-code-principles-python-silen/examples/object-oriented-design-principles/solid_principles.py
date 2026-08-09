"""SOLID principles in idiomatic Python 3.12 (Silen ch02 / book ch4.5).

One runnable file per SOLID letter, written against ``typing.Protocol`` rather
than ``abc.ABC`` because Protocols give structural typing with zero inheritance
boilerplate and no ``@abstractmethod`` noise.

- SRP : one class = one reason to change, split parse vs. read.
- OCP : add a class, never edit a working one (replace conditionals w/ types).
- LSP : a subtype must honor the supertype contract, square IS-NOT-A rectangle
        when width/height are independently settable.
- ISP : segregate fat protocols into single-capability microprotocols.
- DIP : high-level code depends on a Protocol, never a concrete class.

Run: python solid_principles.py
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


# ============================================================================
# S - Single Responsibility: reading config and parsing config are two jobs.
# ============================================================================
class ConfigReader(Protocol):
    def read(self, location: str) -> str: ...


class ConfigParser(Protocol):
    def parse(self, raw: str) -> dict[str, str]: ...


class FileConfigReader:
    def read(self, _location: str) -> str:
        # Real impl: Path(location).read_text(). Kept inert for the demo.
        return "host=localhost\nport=5432"


class IniConfigParser:
    def parse(self, raw: str) -> dict[str, str]:
        return dict(line.split("=", 1) for line in raw.splitlines() if line)


# ============================================================================
# O - Open/Closed: a new shape is a NEW class, not an edit to an existing one.
# A square that mutates a rectangle's setters would be a modification + a bug.
# ============================================================================
class Shape(Protocol):
    def area(self) -> float: ...


@dataclass(frozen=True, slots=True)
class Rectangle:
    width: float
    height: float

    def area(self) -> float:
        return self.width * self.height


@dataclass(frozen=True, slots=True)
class Square:  # extension, not a subclass of Rectangle (see LSP below)
    side: float

    def area(self) -> float:
        return self.side**2


# ============================================================================
# L - Liskov Substitution: Square is NOT a Rectangle because you cannot set
# its width and height independently. Subclassing would break callers that do
# `rect.width = 4; rect.height = 5`. Frozen value objects sidestep the trap
# entirely: there are no setters to violate.
# ============================================================================
def total_area(shapes: list[Shape]) -> float:
    return sum(shape.area() for shape in shapes)


# ============================================================================
# I - Interface Segregation: a vehicle that can only drive should not be
# forced to implement carry_cargo. Compose fat interfaces from microprotocols.
# ============================================================================
class Drivable(Protocol):
    def drive(self) -> None: ...


class CargoCarrying(Protocol):
    def carry_cargo(self, kilograms: float) -> None: ...


class Automobile(Drivable, CargoCarrying, Protocol):
    """Composed protocol, a Truck satisfies this. A Motorcycle satisfies only
    Drivable and is never coerced into a no-op carry_cargo that raises."""


class Motorcycle:
    def drive(self) -> None:
        print("vroom")


class Truck:
    def drive(self) -> None:
        print("rumble")

    def carry_cargo(self, kilograms: float) -> None:
        print(f"hauling {kilograms} kg")


# ============================================================================
# D - Dependency Inversion: the high-level Application depends on the
# ConfigReader / ConfigParser PROTOCOLS, never on FileConfigReader /
# IniConfigParser. Concrete classes are chosen at the composition root.
# ============================================================================
class Application:
    def __init__(self, reader: ConfigReader, parser: ConfigParser) -> None:
        self._reader = reader
        self._parser = parser

    def load_config(self, location: str) -> dict[str, str]:
        return self._parser.parse(self._reader.read(location))


def main() -> None:
    app = Application(FileConfigReader(), IniConfigParser())  # composition root
    print("DIP:", app.load_config("app.ini"))
    print("OCP/LSP total area:", total_area([Rectangle(2, 3), Square(4)]))
    vehicles: list[Drivable] = [Motorcycle(), Truck()]
    for vehicle in vehicles:
        vehicle.drive()
    Truck().carry_cargo(500.0)


if __name__ == "__main__":
    main()
