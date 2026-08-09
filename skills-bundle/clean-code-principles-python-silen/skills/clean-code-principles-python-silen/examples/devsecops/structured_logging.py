"""Structured logging to stdout (DevSecOps: Monitor / Logging).

Demonstrates principles:
- Log to stdout as machine-parseable JSON, not free-form prose.
- Emit one standardized schema across every service (OpenTelemetry-flavored).
- Carry trace/span correlation IDs so logs join distributed traces.
- Inject service identity (Resource) once via a contextual filter, not per call.
- Never put secrets in log records.

Run:  python structured_logging.py
The handler writes to sys.stdout, a log shipper (Fluent Bit, etc.) forwards it.
"""

from __future__ import annotations

import json
import logging
import os
import sys
import time
from typing import Any

# OpenTelemetry SeverityNumber mapping (subset). Querying by number is robust
# across services that disagree on severity *text* casing.
_SEVERITY_NUMBER: dict[int, int] = {
    logging.DEBUG: 5,
    logging.INFO: 9,
    logging.WARNING: 13,
    logging.ERROR: 17,
    logging.CRITICAL: 21,
}

# Keys never serialized into log output, even if passed via `extra`.
_REDACTED_KEYS: frozenset[str] = frozenset(
    {"password", "token", "secret", "authorization", "encryption_key", "api_key"}
)


class ServiceResourceFilter(logging.Filter):
    """Attach service identity to every record once, from the environment.

    These map to the OpenTelemetry `Resource` fields. Reading them from env
    (set by the Deployment manifest's `fieldRef`) keeps the code env-agnostic.
    """

    def __init__(self) -> None:
        super().__init__()
        self._resource: dict[str, str] = {
            "service.name": os.getenv("MICROSERVICE_NAME", "unknown"),
            "service.namespace": os.getenv("MICROSERVICE_NAMESPACE", "default"),
            "service.instance.id": os.getenv("MICROSERVICE_INSTANCE_ID", "local"),
            "service.version": os.getenv("SERVICE_VERSION", "0.0.0"),
        }

    def filter(self, record: logging.LogRecord) -> bool:
        record.resource = self._resource  # type: ignore[attr-defined]
        return True


class OpenTelemetryJsonFormatter(logging.Formatter):
    """Render a LogRecord as a single-line OpenTelemetry-style JSON object."""

    def format(self, record: logging.LogRecord) -> str:
        entry: dict[str, Any] = {
            "Timestamp": int(record.created * 1_000_000_000),  # ns since epoch
            "SeverityText": record.levelname,
            "SeverityNumber": _SEVERITY_NUMBER.get(record.levelno, 0),
            "Body": record.getMessage(),
            "Resource": getattr(record, "resource", {}),
        }
        trace_id = getattr(record, "trace_id", None)
        if trace_id is not None:
            entry["TraceId"] = trace_id
        span_id = getattr(record, "span_id", None)
        if span_id is not None:
            entry["SpanId"] = span_id

        attributes = _collect_attributes(record)
        if attributes:
            entry["Attributes"] = attributes
        if record.exc_info:
            entry["Attributes"] = entry.get("Attributes", {}) | {
                "exception": self.formatException(record.exc_info)
            }
        return json.dumps(entry, default=str)


# LogRecord attributes that are framework-internal, not user attributes.
_RESERVED: frozenset[str] = frozenset(vars(logging.makeLogRecord({})).keys()) | {
    "resource",
    "trace_id",
    "span_id",
    "message",
    "asctime",
}


def _collect_attributes(record: logging.LogRecord) -> dict[str, Any]:
    """Lift caller-supplied `extra=` fields into Attributes, with redaction."""
    return {
        key: ("***" if key.lower() in _REDACTED_KEYS else value)
        for key, value in vars(record).items()
        if key not in _RESERVED
    }


def configure_logging(level: int = logging.INFO) -> logging.Logger:
    """Configure root logging once at process start, return the app logger."""
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(OpenTelemetryJsonFormatter())
    handler.addFilter(ServiceResourceFilter())

    root = logging.getLogger()
    root.handlers.clear()  # drop any default handler to avoid duplicate lines
    root.addHandler(handler)
    root.setLevel(level)
    return logging.getLogger("app")


def main() -> None:
    log = configure_logging()
    # Correlation IDs and structured fields flow through `extra=`, not f-strings.
    log.info(
        "request handled",
        extra={
            "trace_id": "f4dbb3edd765f620",
            "span_id": "43222c2d51a7abe3",
            "http.method": "GET",
            "http.status_code": 200,
            "duration_ms": 12,
            "password": "hunter2",  # redacted by _collect_attributes
        },
    )
    try:
        time.strptime("not-a-date", "%Y")
    except ValueError:
        log.error("date parse failed", extra={"trace_id": "f4dbb3edd765f620"}, exc_info=True)


if __name__ == "__main__":
    main()
