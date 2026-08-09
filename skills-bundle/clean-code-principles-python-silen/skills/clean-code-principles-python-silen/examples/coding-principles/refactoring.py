"""Refactoring techniques (Silen ch03 / book ch5.7).

Three high-leverage refactorings. Each is shown below as the clean ("after")
form. The messy ("before") form it replaces is described here so the contrast
stays readable without keeping defective code in the module.

1. Replace conditionals with polymorphism. A growing ``if/elif`` on a type tag
   becomes one ``render()`` call dispatched by subclass. Adding a case = adding
   a class (open/closed), not editing every ``elif`` (shotgun surgery)::

       # before: dispatch on a string tag, every new chart edits this function
       def render(chart_type: str) -> str:
           if chart_type == "column":
               return "drawing columns"
           elif chart_type == "pie":
               return "drawing slices"
           ...
           raise ValueError(chart_type)

2. Introduce parameter object. Collapse a long, error-orderable parameter list
   (``brokers, tls_is_used, verify_cert, ca_path, cert_path, key_path``) into a
   cohesive frozen dataclass so two same-typed strings can no longer be swapped.

3. Invert if-statement. Remove a negated / double-negative condition by swapping
   the branches so the simple case (``folder is None``) is handled first and the
   positive path reads cleanly, instead of ``if folder is not None: ... else: ...``.

Run: python refactoring.py
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


# === 1. Replace conditionals with polymorphism ==============================
# Each chart owns its behaviour. render() never changes again.
class Chart(Protocol):
    def render(self) -> str: ...


class ColumnChart:
    def render(self) -> str:
        return "drawing columns"


class PieChart:
    def render(self) -> str:
        return "drawing slices"


class MapChart:
    def render(self) -> str:
        return "drawing regions"


def render(chart: Chart) -> str:
    return chart.render()


# === 2. Introduce parameter object =========================================
# Cohesive options grouped, named fields prevent ordering bugs.
@dataclass(frozen=True, slots=True)
class TlsOptions:
    is_used: bool
    verify_cert: bool
    ca_path: str
    cert_path: str
    key_path: str


def connect(brokers: list[str], tls: TlsOptions) -> str:
    return f"connect brokers={len(brokers)} tls={tls.is_used} verify={tls.verify_cert}"


# === 3. Invert if-statement (kill the negated condition) ====================
# Handle the simple/None case first, then the positive path reads cleanly.
def resolve(folder: str | None) -> str:
    if folder is None:
        return "cwd/tests"
    return folder.removeprefix("/mnt") + "/tests"


if __name__ == "__main__":
    print(render(PieChart()))
    options = TlsOptions(
        is_used=True,
        verify_cert=True,
        ca_path="ca",
        cert_path="cert",
        key_path="key",
    )
    print(connect(["b1"], options))
    print(resolve(None), "|", resolve("/mnt/data"))
