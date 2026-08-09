"""Demonstrates: "You write code for other people" + Software-component documentation.

A public function written for a future reader: a precise, type-hinted signature,
a docstring that states *intent and contract* (not a restatement of the body),
and an explicit, named exception instead of a silent failure.

The point is not "add a docstring", it is: the next maintainer should understand
WHEN to call this, WHAT it guarantees, and HOW it fails, without reading the body.

Run the doctest with:  python -m doctest documented_function.py -v
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal


class RefundError(ValueError):
    """Raised when a refund request violates an invariant (over-refund, etc.)."""


@dataclass(frozen=True, slots=True)
class Payment:
    """A captured payment. ``refunded`` never exceeds ``amount``."""

    amount: Decimal
    refunded: Decimal = Decimal("0")


def refund(payment: Payment, requested: Decimal) -> Payment:
    """Return a new ``Payment`` with ``requested`` added to the refunded total.

    The contract a caller needs (and the part a machine cannot infer):

    - Refunds are cumulative, the returned ``refunded`` is the running total.
    - You may never refund more than was captured. Doing so is a programming
      error, not a recoverable condition, so it raises rather than clamping.
    - ``payment`` is never mutated (it is frozen), a new value is returned.

    Args:
        payment: The captured payment to refund against.
        requested: A positive amount to refund in this call.

    Returns:
        A new ``Payment`` reflecting the cumulative refund.

    Raises:
        RefundError: If ``requested`` is non-positive, or if it would push the
            cumulative refund above the captured ``amount``.

    >>> p = Payment(amount=Decimal("100"))
    >>> refund(p, Decimal("30")).refunded
    Decimal('30')
    >>> refund(refund(p, Decimal("30")), Decimal("80"))
    Traceback (most recent call last):
        ...
    documented_function.RefundError: over-refund: 110 > 100
    """
    if requested <= 0:
        raise RefundError(f"refund amount must be positive, got {requested}")
    new_total = payment.refunded + requested
    if new_total > payment.amount:
        raise RefundError(f"over-refund: {new_total} > {payment.amount}")
    return Payment(amount=payment.amount, refunded=new_total)


if __name__ == "__main__":
    captured = Payment(amount=Decimal("100"))
    partial = refund(captured, Decimal("40"))
    print(f"refunded so far: {partial.refunded} of {partial.amount}")
