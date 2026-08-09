"""Uniform variable naming principle (Silen ch03 / book ch5.1).

A name should communicate purpose AND type, because Python infers types and
the annotation is not always visible at the call site. Conventions shown:

- counts: ``<thing>_count`` / ``number_of_<thing>`` (not a bare plural, which
  reads like a collection)
- collections: plural noun (``customers``), no ``_list`` / ``_set`` suffix
- dicts: ``key_to_value`` so iteration and lookup read like prose
- booleans: form a yes/no statement (``pool_is_full``), avoid passive nouns
  (``inserted_field``) that read as objects, not predicates
- strings holding non-strings: ``<value>_as_string``
- units when not self-evident: ``..._in_ms``, ``..._percent``

Run: python naming.py
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class Customer:
    customer_id: int
    name: str


# --- counts: name says "this is a number", not "this is a collection" -------
def active_count(customers: list[Customer]) -> int:
    # The function name reads as an integer (count), not a collection -- prefer
    # ``active_count`` / ``number_of_active`` over a bare plural like ``actives``.
    return sum(1 for customer in customers if customer.customer_id > 0)


# --- collections: plural noun, no type suffix ------------------------------
def matching_customers(customers: list[Customer], substring: str) -> list[Customer]:
    # The plural noun says "collection", no ``_list`` / ``_set`` type suffix.
    return [customer for customer in customers if substring in customer.name]


# --- dict: key_to_value names make both access and iteration self-documenting
def order_counts_by_name(
    customer_name_to_order_count: dict[str, int],
) -> int:
    total_order_count = 0
    for order_count in customer_name_to_order_count.values():
        total_order_count += order_count
    return total_order_count


# --- boolean: reads as a yes/no statement, unit baked into the name ---------
def should_flush(pending_count: int, max_pending: int, idle_ms: int) -> bool:
    # GOOD vs e.g. ``flush`` (ambiguous) or ``not_full`` (double negative).
    buffer_is_full = pending_count >= max_pending
    waited_long_enough = idle_ms >= 500
    return buffer_is_full or waited_long_enough


# --- string holding a number: name flags the format mismatch ---------------
def parse_year(year_as_string: str) -> int | None:
    try:
        return int(year_as_string)
    except ValueError:
        return None


if __name__ == "__main__":
    people = [Customer(1, "Ada"), Customer(2, "Alan"), Customer(-1, "ghost")]
    print("active_count:", active_count(people))
    print("matching:", [c.name for c in matching_customers(people, "Al")])
    print("total_orders:", order_counts_by_name({"Ada": 10, "Alan": 5}))
    print("should_flush:", should_flush(pending_count=3, max_pending=8, idle_ms=600))
    print("parse_year('2026'):", parse_year("2026"))
