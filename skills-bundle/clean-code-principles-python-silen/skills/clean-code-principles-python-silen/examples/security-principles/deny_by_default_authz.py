"""Demonstrates: deny-by-default authorization via decorators + a startup check
(ch05 §7.4.1, adapted from the book's allow_* decorators and the
ensure_request_handlers_have_auth_decor scanner).

Principles shown:
- Every route must declare an authorization intent. A route with no decorator is
  a bug, not "public by accident". A startup scan fails the build if one is missing.
- An explicit `@allow_any_user` marks intentionally public routes, so "I forgot"
  and "I meant it" are distinguishable.
- Authorizer is a Protocol -> the policy is swappable and testable.

This is framework-agnostic (plain callables) so it runs standalone.
Run: python deny_by_default_authz.py
"""

from __future__ import annotations

import ast
from collections.abc import Awaitable, Callable
from functools import wraps
from pathlib import Path
from typing import Protocol, runtime_checkable

Handler = Callable[..., Awaitable[object]]

# Marker attribute every authorization decorator stamps onto the handler.
_AUTHZ_ATTR = "__authz_declared__"


@runtime_checkable
class Authorizer(Protocol):
    def authorize(self, *, token: str | None) -> str: ...
    def require_role(self, *, token: str | None, role: str) -> None: ...


class AuthorizationError(Exception): ...


def allow_any_user(handler: Handler) -> Handler:
    """Intentionally public. Explicit so it is not confused with a forgotten one."""
    setattr(handler, _AUTHZ_ATTR, True)
    return handler


def allow_authenticated(authorizer: Authorizer) -> Callable[[Handler], Handler]:
    def decorate(handler: Handler) -> Handler:
        @wraps(handler)
        async def wrapper(*args: object, token: str | None = None, **kwargs: object) -> object:
            authorizer.authorize(token=token)  # raises if no/invalid identity
            return await handler(*args, token=token, **kwargs)

        setattr(wrapper, _AUTHZ_ATTR, True)
        return wrapper

    return decorate


def allow_role(authorizer: Authorizer, role: str) -> Callable[[Handler], Handler]:
    def decorate(handler: Handler) -> Handler:
        @wraps(handler)
        async def wrapper(*args: object, token: str | None = None, **kwargs: object) -> object:
            authorizer.require_role(token=token, role=role)
            return await handler(*args, token=token, **kwargs)

        setattr(wrapper, _AUTHZ_ATTR, True)
        return wrapper

    return decorate


# --- Build-time guard: refuse to ship a route with no authorization intent ----
_ROUTE_DECORATORS = {"get", "post", "put", "patch", "delete"}
_AUTHZ_DECORATORS = {"allow_any_user", "allow_authenticated", "allow_role"}


def _decorator_names(node: ast.AST) -> list[str]:
    names: list[str] = []
    for dec in getattr(node, "decorator_list", []):
        target = dec.func if isinstance(dec, ast.Call) else dec
        if isinstance(target, ast.Attribute):
            names.append(target.attr)
        elif isinstance(target, ast.Name):
            names.append(target.id)
    return names


def find_unprotected_routes(source: str) -> list[str]:
    """Static check: any function decorated with an app route but no allow_*
    decorator is reported. Wire this into CI / startup to fail closed."""
    tree = ast.parse(source)
    offenders: list[str] = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.AsyncFunctionDef | ast.FunctionDef):
            continue
        names = _decorator_names(node)
        is_route = any(n in _ROUTE_DECORATORS for n in names)
        has_authz = any(n in _AUTHZ_DECORATORS for n in names)
        if is_route and not has_authz:
            offenders.append(node.name)
    return offenders


def scan_project(root: Path) -> dict[str, list[str]]:
    return {
        str(path): offenders
        for path in root.rglob("*.py")
        if (offenders := find_unprotected_routes(path.read_text(encoding="utf-8")))
    }


def main() -> None:
    sample = (
        "import app\n"
        "@app.get('/public')\n"
        "@allow_any_user\n"
        "async def public(): ...\n"
        "@app.delete('/orders/{id}')\n"  # <-- no allow_* decorator: a bug
        "async def delete_order(id): ...\n"
    )
    print("unprotected routes:", find_unprotected_routes(sample))


if __name__ == "__main__":
    main()
