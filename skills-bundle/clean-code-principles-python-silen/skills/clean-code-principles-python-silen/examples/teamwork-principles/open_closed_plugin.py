"""Demonstrates: Highly-concurrent development via the open-closed principle.

Teamwork angle: when two developers must add export formats to the same
microservice, the naive design forces both to edit one ``if/elif`` dispatcher
in the same file -> guaranteed merge conflict. A registry keyed on a Protocol
lets each developer add a NEW file with a NEW class and touch nothing the other
owns. Open for extension (new exporters), closed for modification (no edits to
the dispatcher or to sibling exporters).

This is the structural reason the chapter's "highly concurrent development"
principle works: design decides how many files a feature has to touch.
"""

from __future__ import annotations

from typing import Protocol, runtime_checkable


@runtime_checkable
class Exporter(Protocol):
    """A format plugin. Each lives in its own file, add new ones freely."""

    name: str

    def render(self, rows: list[dict[str, object]]) -> str: ...


# The registry is the ONLY shared mutable surface, and it is append-only:
# registering does not require editing existing entries, so concurrent adds
# do not collide on the same lines.
_REGISTRY: dict[str, Exporter] = {}


def register(exporter: Exporter) -> Exporter:
    """Register an exporter under its ``name``, reject duplicates loudly."""
    if exporter.name in _REGISTRY:
        raise ValueError(f"exporter {exporter.name!r} already registered")
    _REGISTRY[exporter.name] = exporter
    return exporter


def export(fmt: str, rows: list[dict[str, object]]) -> str:
    """Dispatch to the registered exporter for ``fmt``.

    Adding a format never edits this function, contrast with an if/elif chain,
    which every new format would have to modify (and conflict on).
    """
    try:
        return _REGISTRY[fmt].render(rows)
    except KeyError:
        known = ", ".join(sorted(_REGISTRY)) or "<none>"
        raise ValueError(f"unknown format {fmt!r}, known: {known}") from None


# --- Developer A owns this class (would be its own module in real code) ------
class CsvExporter:
    name = "csv"

    def render(self, rows: list[dict[str, object]]) -> str:
        if not rows:
            return ""
        header = list(rows[0])
        lines = [",".join(header)]
        lines.extend(",".join(str(row[col]) for col in header) for row in rows)
        return "\n".join(lines)


# --- Developer B owns this class (a separate module, separate PR) ------------
class TsvExporter:
    name = "tsv"

    def render(self, rows: list[dict[str, object]]) -> str:
        if not rows:
            return ""
        header = list(rows[0])
        lines = ["\t".join(header)]
        lines.extend("\t".join(str(row[col]) for col in header) for row in rows)
        return "\n".join(lines)


register(CsvExporter())
register(TsvExporter())


if __name__ == "__main__":
    data: list[dict[str, object]] = [
        {"id": 1, "name": "alice"},
        {"id": 2, "name": "bob"},
    ]
    print(export("csv", data))
    print("---")
    print(export("tsv", data))
