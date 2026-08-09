"""Encapsulation, Tell-Don't-Ask, and the Law of Demeter (Silen ch02 / book
ch4.10, 4.14, 4.15).

Three related rules, one example domain (a bank account):

- Encapsulation: state is private (``__`` name-mangled), no auto-generated
  getters/setters. Behavior lives WITH the data it guards.
- Tell, don't ask: callers TELL the account to ``withdraw``, they do not ASK
  for the balance and do the arithmetic themselves (the *feature envy* smell).
- Law of Demeter: ``user.account.withdraw(...)`` reaches through one object to
  poke another. The User acts as a facade: ``user.purchase(item)``.

Also shown: returning a *copy* of a mutable attribute so callers cannot mutate
internal state behind the object's back (don't-leak-internal-state).

Run: python encapsulation_tell_dont_ask.py
"""

from __future__ import annotations

from dataclasses import dataclass


class InsufficientFundsError(Exception):
    pass


@dataclass(frozen=True, slots=True)
class SalesItem:
    name: str
    price: int  # cents


class Account:
    def __init__(self, balance: int) -> None:
        self.__balance = balance  # private: no public setter exists
        self.__transactions: list[int] = []

    # The business rule (enough funds?) lives WITH the balance it protects,
    # not in a service that asks for the balance and decides for itself.
    def withdraw(self, amount: int) -> None:
        if amount > self.__balance:
            raise InsufficientFundsError(f"need {amount}, have {self.__balance}")
        self.__balance -= amount
        self.__transactions.append(-amount)

    def can_afford(self, amount: int) -> bool:
        return amount <= self.__balance

    @property
    def balance(self) -> int:  # read-only view, no setter
        return self.__balance

    @property
    def transactions(self) -> list[int]:
        # Return a COPY: a caller appending to this list must not corrupt
        # our ledger. Returning self.__transactions would leak mutable state.
        return self.__transactions.copy()


class User:
    """Facade over Account: callers never touch the account directly, so the
    chain ``user.get_account().withdraw(...)`` (a Demeter violation) is
    impossible by construction."""

    def __init__(self, account: Account) -> None:
        self.__account = account

    def purchase(self, item: SalesItem) -> bool:
        if self.__account.can_afford(item.price):
            self.__account.withdraw(item.price)
            return True
        return False


def main() -> None:
    user = User(Account(balance=1000))
    print("bought book:", user.purchase(SalesItem("book", 750)))
    print("bought car :", user.purchase(SalesItem("car", 999_999)))


if __name__ == "__main__":
    main()
