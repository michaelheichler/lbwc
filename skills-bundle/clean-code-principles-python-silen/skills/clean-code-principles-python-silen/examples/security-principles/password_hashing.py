"""Demonstrates: password storage + password policy (ch05 §7.4.2, §7.4.3).

Principles shown:
- Hash passwords with a memory-hard, salted KDF (Argon2id). Never store plaintext,
  never use a fast/general hash (md5/sha256) for passwords.
- Verify with the library's constant-time check, transparently rehash on upgrade.
- Enforce a passphrase-friendly policy: length first, allow Unicode, block
  the username and common weak patterns.

Run: uv run --with argon2-cffi python password_hashing.py
"""

from __future__ import annotations

import unicodedata
from typing import Final

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError

# A single shared, configured hasher (tune time/memory cost to your hardware).
_HASHER: Final[PasswordHasher] = PasswordHasher()
_MIN_LEN: Final[int] = 12
# A tiny illustrative deny-list, load a real one (e.g. SecLists) in production.
_WEAK: Final[frozenset[str]] = frozenset({"password", "qwerty", "123456", "passphrase"})


class WeakPasswordError(ValueError):
    """Raised when a candidate password fails policy."""


def _normalize(password: str) -> str:
    # NFC-normalize so visually identical Unicode passphrases compare equal.
    return unicodedata.normalize("NFC", password)


def check_policy(password: str, *, username: str) -> None:
    pw = _normalize(password)
    if len(pw) < _MIN_LEN:
        raise WeakPasswordError(f"password must be at least {_MIN_LEN} characters")
    lowered = pw.casefold()
    if username.casefold() in lowered:
        raise WeakPasswordError("password must not contain the username")
    if lowered in _WEAK:
        raise WeakPasswordError("password is on the common-password deny-list")
    if any(lowered.count(ch) > len(lowered) // 2 for ch in set(lowered)):
        raise WeakPasswordError("password has too many repeated characters")


def hash_password(password: str, *, username: str) -> str:
    check_policy(password, username=username)
    # Argon2 embeds a random salt + parameters in the returned string.
    return _HASHER.hash(_normalize(password))


def verify_password(stored_hash: str, password: str) -> tuple[bool, str | None]:
    """Return (is_valid, new_hash_if_rehash_needed)."""
    try:
        _HASHER.verify(stored_hash, _normalize(password))
    except (VerifyMismatchError, InvalidHashError):
        return (False, None)
    # If cost parameters changed since this hash was made, upgrade it now.
    if _HASHER.check_needs_rehash(stored_hash):
        return (True, _HASHER.hash(_normalize(password)))
    return (True, None)


def main() -> None:
    try:
        hash_password("short", username="alice")
    except WeakPasswordError as exc:
        print("rejected weak password:", exc)

    # Passphrase with Unicode is allowed and encouraged.
    stored = hash_password("Grüne Würfel-Tänzer-2025!", username="alice")
    print("stored hash starts with:", stored[:24], "...")

    ok, rehash = verify_password(stored, "Grüne Würfel-Tänzer-2025!")
    print("correct passphrase ->", ok, "rehash needed:", rehash is not None)
    bad, _ = verify_password(stored, "wrong")
    print("wrong passphrase ->", bad)


if __name__ == "__main__":
    main()
