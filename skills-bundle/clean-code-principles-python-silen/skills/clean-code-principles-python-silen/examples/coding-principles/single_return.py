"""Function single-return principle (Silen ch03 / book ch5.5).

Prefer one ``return`` of a *named* value at the end of a function. The name
communicates what a primitive return (bool/int) means, and single-exit code
is trivially refactorable (you can extract-method without a mid-function
return breaking the control flow).

Sanctioned exceptions (still idiomatic):
- short guard-style functions where the name/return type already says it all
  and forcing a single return would exceed ~9 statements
- factories that ``return`` a different subtype per branch (``match``)

Run: python single_return.py
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


# --- Single named return: the name reveals the bool's meaning ---------------
@dataclass(slots=True)
class TransformResult:
    was_transformed: bool
    is_kept: bool


def was_message_routed(result: TransformResult, sink: list[str], payload: str) -> bool:
    # Decide, act, then return one named value at the end -- instead of
    # scattering two primitive ``return`` points through the branches.
    if result.was_transformed and result.is_kept:
        sink.append(payload)
    return result.was_transformed


# --- Sanctioned exception 1: factory returns subtypes via match -------------
class CarType(Enum):
    AUDI = "audi"
    BMW = "bmw"
    MERCEDES = "mercedes"


class Car:
    brand = "generic"


class Audi(Car):
    brand = "audi"


class Bmw(Car):
    brand = "bmw"


class Mercedes(Car):
    brand = "mercedes"


def create_car(car_type: CarType) -> Car:
    # Multiple returns are fine here: the factory name + return type make the
    # meaning obvious, and a single-return version would be longer/worse.
    match car_type:
        case CarType.AUDI:
            return Audi()
        case CarType.BMW:
            return Bmw()
        case CarType.MERCEDES:
            return Mercedes()
        case _:
            # Always raise in the default branch so a new enum member that
            # nobody handled fails loudly instead of returning None.
            raise ValueError(f"unhandled car type: {car_type}")


if __name__ == "__main__":
    sink: list[str] = []
    result = TransformResult(was_transformed=True, is_kept=True)
    routed = was_message_routed(result, sink, "payload")
    print("routed:", routed, "sink:", sink)
    print("created:", create_car(CarType.BMW).brand)
