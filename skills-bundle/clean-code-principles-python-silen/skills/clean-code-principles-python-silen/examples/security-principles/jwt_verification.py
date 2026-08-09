"""Demonstrates: JWT verification done right + deny-by-default authorization
(ch05 §7.4.1, adapted from the book's FastAPI JwtAuthorizer).

Principles shown:
- VERIFY the signature against the IdP's JWKS, pin the algorithm allow-list
  (never trust the token's own `alg`, never accept `alg: none`).
- Require and validate audience + issuer + expiry. PyJWT does this when asked.
- Authorization is a separate step: a verified identity is not permission.
  Default-deny. Check ownership (IDOR prevention) and roles explicitly.

Run: uv run --with pyjwt python jwt_verification.py   (offline demo, HS256)
Production uses RS256 + PyJWKClient against the IdP's jwks_uri.
"""

from __future__ import annotations

import base64
import json
import os
import secrets
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, Final

import jwt
from jwt import InvalidTokenError

# Pin exactly the algorithms you expect. An open allow-list (or letting the
# token pick) enables alg-confusion and `alg: none` forgery.
_ALLOWED_ALGS: Final[list[str]] = ["RS256"]


class AuthenticationError(Exception):
    """No / invalid token: 401."""


class AuthorizationError(Exception):
    """Valid token but not permitted: 403."""


@dataclass(frozen=True, slots=True)
class VerifiedClaims:
    subject: str
    user_id: int
    roles: frozenset[str]


def verify_token(
    token: str,
    *,
    signing_key: Any,
    audience: str,
    issuer: str,
    algorithms: list[str] = _ALLOWED_ALGS,
) -> VerifiedClaims:
    """Decode AND verify. `verify_signature`/exp/aud/iss are on by default in
    PyJWT, we make them explicit so the intent is auditable."""
    try:
        claims = jwt.decode(
            token,
            signing_key,
            algorithms=algorithms,
            audience=audience,
            issuer=issuer,
            options={
                "require": ["exp", "iat", "aud", "iss", "sub"],
                "verify_signature": True,
                "verify_exp": True,
                "verify_aud": True,
            },
        )
    except InvalidTokenError as exc:
        # Do not leak which check failed to the client.
        raise AuthenticationError("invalid token") from exc
    return VerifiedClaims(
        subject=str(claims["sub"]),
        user_id=int(claims["user_id"]),
        roles=frozenset(claims.get("roles", [])),
    )


def require_role(claims: VerifiedClaims, *, allowed: frozenset[str]) -> None:
    """Deny by default: only proceed if a required role is present."""
    if claims.roles.isdisjoint(allowed):
        raise AuthorizationError("missing required role")


def require_owner(
    claims: VerifiedClaims,
    resource_id: int,
    *,
    owner_of: Callable[[int], int | None],
) -> None:
    """IDOR prevention: the caller may only touch resources they own.
    A missing record is reported as 403, not 404, so existence isn't leaked."""
    owner = owner_of(resource_id)
    if owner is None or owner != claims.user_id:
        raise AuthorizationError("not the resource owner")


def _b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def main() -> None:
    # Offline demo only: a per-run random HS256 key so it runs without a network
    # IdP. Production verifies RS256 against the IdP's JWKS, never a local secret.
    secret = os.environ.get("DEMO_JWT_SECRET") or secrets.token_urlsafe(32)
    good = jwt.encode(
        {
            "sub": "u-1",
            "user_id": 1,
            "roles": ["user"],
            "aud": "orders-api",
            "iss": "https://iam.example",
            "iat": 1_500_000_000,  # 2017: safely in the past
            "exp": 9_999_999_999,  # year 2286: safely in the future
        },
        secret,
        algorithm="HS256",
    )
    claims = verify_token(
        good,
        signing_key=secret,
        audience="orders-api",
        issuer="https://iam.example",
        algorithms=["HS256"],
    )
    print("verified:", claims)

    orders = {10: 1, 11: 2}  # order_id -> owner user_id
    require_owner(claims, 10, owner_of=orders.get)  # ok: user 1 owns order 10
    print("owner check passed for own order")
    try:
        require_owner(claims, 11, owner_of=orders.get)  # order 11 belongs to user 2
    except AuthorizationError as exc:
        print("blocked IDOR:", exc)
    try:
        require_role(claims, allowed=frozenset({"admin"}))
    except AuthorizationError as exc:
        print("blocked non-admin:", exc)

    # A forged unsigned token must be rejected outright. We craft it by hand
    # (header {"alg":"none"} + empty signature) rather than via the library,
    # because no honest code path should ever emit an unsigned JWT.
    header = _b64url(json.dumps({"alg": "none", "typ": "JWT"}).encode())
    payload = _b64url(json.dumps({"sub": "x", "user_id": 9}).encode())
    forged = f"{header}.{payload}."
    try:
        verify_token(
            forged,
            signing_key=secret,
            audience="orders-api",
            issuer="https://iam.example",
            algorithms=["HS256"],
        )
    except AuthenticationError as exc:
        print("rejected forged token:", exc)


if __name__ == "__main__":
    main()
