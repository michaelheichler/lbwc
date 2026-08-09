"""Demonstrates: secrets from env/secret store + fail-closed config validation
(ch05 §7.3.6, §7.4.3, §7.4.14).

Principles shown:
- Secrets come from the environment / a secret store, never hard-coded.
- One controlled accessor validates env vars (presence, type, range, strength).
- In production, weak/default secrets must STOP the process, not warn.
- Wrap secrets in a type whose repr() cannot leak the value into logs/tracebacks.

Run: OIDC_CONFIG_URL=https://iam/.well-known/openid-configuration \
     DB_PASSWORD=$(python -c "import secrets;print(secrets.token_urlsafe(32))") \
     APP_ENV=production python secrets_and_config.py
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from enum import StrEnum
from typing import Final

_MIN_PROD_SECRET_LEN: Final[int] = 32
# Refusing known placeholder values closes the "shipped with the default" hole.
_FORBIDDEN_IN_PROD: Final[frozenset[str]] = frozenset(
    {"", "changeme", "password", "secret", "admin", "default"}
)


class AppEnv(StrEnum):
    DEVELOPMENT = "development"
    PRODUCTION = "production"


class ConfigError(RuntimeError):
    """Raised when configuration is missing or insecure. Fail closed."""


@dataclass(frozen=True, slots=True)
class Secret:
    """Holds a secret value but never reveals it via repr/str/logging."""

    _value: str

    def reveal(self) -> str:
        return self._value

    def __repr__(self) -> str:
        return "Secret(***)"

    __str__ = __repr__


@dataclass(frozen=True, slots=True)
class AppConfig:
    env: AppEnv
    oidc_config_url: str
    db_password: Secret


def _require(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise ConfigError(f"required environment variable {name!r} is missing")
    return value


def _require_strong_secret(name: str, env: AppEnv) -> Secret:
    value = _require(name)
    if env is AppEnv.PRODUCTION:
        if value.lower() in _FORBIDDEN_IN_PROD:
            raise ConfigError(f"{name} is a forbidden default value in production")
        if len(value) < _MIN_PROD_SECRET_LEN:
            raise ConfigError(f"{name} must be >= {_MIN_PROD_SECRET_LEN} chars in production")
    return Secret(value)


def load_config() -> AppConfig:
    """Single validated entry point. Anything invalid raises before startup."""
    env = AppEnv(os.environ.get("APP_ENV", "development"))
    return AppConfig(
        env=env,
        oidc_config_url=_require("OIDC_CONFIG_URL"),
        db_password=_require_strong_secret("DB_PASSWORD", env),
    )


def main() -> None:
    try:
        config = load_config()
    except ConfigError as exc:
        # Real services exit non-zero here so a misconfigured pod never serves.
        raise SystemExit(f"refusing to start: {exc}") from exc
    # repr is safe to log: secret value is masked.
    print("loaded:", config)


if __name__ == "__main__":
    main()
