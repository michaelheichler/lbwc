"""Externalized Service Configuration + Service Substitution principles.

A service must read everything that varies between deployments (hosts, ports,
credentials, log levels, feature toggles) from the *environment*, never from
hardcoded literals. Because the dependency address is a config value, swapping a
local MongoDB for MongoDB Atlas (or a stub for a real service) is a config
change, not a code change. That is the Service Substitution principle: keep
dependencies transparent (host + port) and inject them via config.

Why a typed, fail-fast loader instead of scattered ``os.environ.get`` calls:
- A bare ``os.environ.get("PORT")`` returns ``str | None``, and forgetting the cast
  or the None-check is the classic production crash.
- Hardcoded defaults silently ship a dev value (e.g. ``localhost``) to prod.
  Required settings must raise at startup, not 200ms into the first request.

Run:  MONGODB_HOST=db.internal MONGODB_PORT=27017 python externalized_config.py
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from enum import StrEnum


class LogLevel(StrEnum):
    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"


class ConfigError(RuntimeError):
    """Raised at startup when a required setting is missing or malformed."""


def _require(name: str) -> str:
    """Read a mandatory env var, fail loudly and immediately if absent."""
    value = os.environ.get(name)
    if not value:
        raise ConfigError(f"required environment variable {name!r} is not set")
    return value


def _require_int(name: str) -> int:
    raw = _require(name)
    try:
        return int(raw)
    except ValueError as exc:
        raise ConfigError(f"{name!r} must be an integer, got {raw!r}") from exc


@dataclass(frozen=True, slots=True)
class MongoConfig:
    """A dependency exposed transparently as host + port (+ credentials)."""

    host: str
    port: int
    user: str
    password: str

    @property
    def uri(self) -> str:
        return f"mongodb://{self.user}:***@{self.host}:{self.port}"


@dataclass(frozen=True, slots=True)
class ServiceConfig:
    log_level: LogLevel
    mongo: MongoConfig

    @classmethod
    def from_env(cls) -> ServiceConfig:
        """Build the whole config from the environment once, at boot.

        Required values raise. Only the log level has a deliberate, safe
        default. Credentials are never defaulted: a missing password must crash
        rather than connect to the wrong store.
        """
        return cls(
            log_level=LogLevel(os.environ.get("LOG_LEVEL", LogLevel.INFO)),
            mongo=MongoConfig(
                host=_require("MONGODB_HOST"),
                port=_require_int("MONGODB_PORT"),
                user=_require("MONGODB_USER"),
                password=_require("MONGODB_PASSWORD"),
            ),
        )


# Anti-pattern (do NOT do this): giving os.environ.get a hardcoded fallback (a
# "localhost" default for MONGODB_HOST) bakes a dev value into source. Deploy to
# prod, forget to set the var, and the service quietly talks to localhost. The
# ``_require`` helper above fails loudly at startup instead.


if __name__ == "__main__":
    config = ServiceConfig.from_env()
    print(f"log_level={config.log_level}")
    print(f"connecting to {config.mongo.uri}")
