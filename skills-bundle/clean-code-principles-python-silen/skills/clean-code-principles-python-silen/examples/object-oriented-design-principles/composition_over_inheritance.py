"""Prefer composition over inheritance (Silen ch02 / book ch4.11).

Inheritance encodes every combination of behavior as a class, so the class
count (and the name length) explodes:
``HatchbackFourWheelDriveAutomaticTransmissionCombustionEngineCar``. Worse, to
fix one chart type you must walk a deep base-class chain to find where the
behavior actually lives.

Composition models the real ``has-a`` relationship: a Car HAS an engine, HAS a
transmission. Behaviors are injected as collaborators (the *strategy pattern*),
so N behaviors combine without N-factorial subclasses, and each collaborator
has a single responsibility.

Run: python composition_over_inheritance.py
"""

from __future__ import annotations

from typing import Protocol


# --- collaborators: each is one small, swappable strategy --------------------
class Engine(Protocol):
    def start(self) -> str: ...


class Transmission(Protocol):
    def shift(self) -> str: ...


class CombustionEngine:
    def start(self) -> str:
        return "ignite cylinders"


class ElectricEngine:
    def start(self) -> str:
        return "energize inverter"


class ManualTransmission:
    def shift(self) -> str:
        return "press clutch, change gear"


class AutomaticTransmission:
    def shift(self) -> str:
        return "auto-shift"


class Drivable(Protocol):
    def drive(self) -> str: ...


# --- the composed object delegates to its parts, it does not inherit them ----
class Car:
    def __init__(self, engine: Engine, transmission: Transmission) -> None:
        self._engine = engine
        self._transmission = transmission

    def drive(self) -> str:
        return f"{self._engine.start()} -> {self._transmission.shift()}"


def main() -> None:
    # Any engine x any transmission, zero new classes per combination.
    ev_auto = Car(ElectricEngine(), AutomaticTransmission())
    classic = Car(CombustionEngine(), ManualTransmission())
    print("EV  :", ev_auto.drive())
    print("ICE :", classic.drive())


if __name__ == "__main__":
    main()
