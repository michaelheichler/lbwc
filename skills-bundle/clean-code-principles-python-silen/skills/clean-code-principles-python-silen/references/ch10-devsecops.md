# ch10: DevSecOps

> When this governs: writing/reviewing Python that ships as a containerized service, its CI/CD pipeline, Dockerfile, Kubernetes/Helm deploy config, health probes, structured logging, metrics/SLI instrumentation, and security scanning.

## Principle index
- **One CI pipeline per component, triggered on push.** Each component owns a pipeline run on every main-branch commit.
- **Pipeline fails the build, not just reports.** Gate merges on tests, SAST, lint, and high-severity scan findings.
- **Shift security left.** Run SAST/DAST/SCA/SBOM/image scans inside the pipeline, not after release.
- **Distroless, multi-stage, non-root images.** Build deps in one stage, ship a minimal runtime that runs as a non-root user.
- **Harden the container securityContext by default.** Drop all caps, read-only root FS, no privilege escalation.
- **Pin everything, never `:latest`.** Pin base images, actions, and deploy by image digest.
- **Three distinct health probes.** Startup, liveness (process-local), readiness (deps + drain) are not aliases.
- **Log structured JSON to stdout.** One schema across services, parseable by the log shipper.
- **Carry trace/span correlation IDs.** Every log and request joins the distributed trace.
- **Never log secrets.** Redact credentials before serialization.
- **Instrument the four golden SLIs.** Errors, latency, throughput, saturation with the right instrument type.
- **Keep metric labels low-cardinality.** Route templates and error classes, never ids or raw paths.
- **Alert on SLOs, auto-resolve.** Base alert rules on objectives, and cancel when the SLO recovers.
- **Keep secrets out of source.** Inject via env/secretKeyRef, reference CI secrets, never hardcode.

## Principles

### One CI pipeline per component, triggered on push
- **Rule:** Give each deployable component its own pipeline that runs automatically on every push to main.
- **Why:** Shared or manual pipelines let regressions reach production untested. Per-component automation keeps the feedback loop short and the blame surface small.
- **Python:** The trigger and the canonical step order, declarative in `.github/workflows/`:
  ```yaml
  on:
    push:
      branches: [main]
  jobs:
    build:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - uses: actions/setup-python@v5
          with: { python-version: "3.12", cache: pip }
        - run: pip install -r requirements.txt
        - run: ruff check src tests          # lint (replaces pylint here)
        - run: python -m coverage run -m pytest
        - run: python -m coverage xml         # feeds SonarCloud / Codecov
  ```
- **Anti-slop:** Don't invent a `cron`/manual-only trigger or a monolithic "deploy everything" job. The unit of CI is the component, triggered on push.
- **See also:** modern-devops-practices (CI with GitHub Actions), the-kubernetes-book.

### Pipeline fails the build, not just reports
- **Rule:** Make tests, linting, and high-severity findings hard-fail the pipeline before merge/release.
- **Why:** A scan that only annotates is noise. Humans ignore green-with-warnings. The gate is what actually keeps defects out of `main`.
- **Python:** Wire fail conditions explicitly, `fail_action: true` for ZAP, `severity-cutoff` for image scans, non-zero exit for coverage floors:
  ```yaml
  - run: python -m coverage report --fail-under=85   # exit 2 below threshold
  - uses: zaproxy/action-api-scan@v0.9.0
    with: { target: http://localhost:8080/openapi.json, fail_action: true }
  ```
- **Anti-slop:** Don't set `soft_fail: true` / `fail-build: false` on the checks the chapter relies on for the gate, then call the pipeline "secured". A reported-but-passing finding is an ungated finding.

### Shift security left (SAST, DAST, SCA, SBOM, image scan)
- **Rule:** Run static analysis, dynamic API scanning, dependency/license checks, an SBOM, and an image vulnerability scan inside CI/CD.
- **Why:** Vulnerabilities found in production cost orders of magnitude more than ones caught at commit time, and unscanned dependencies are the most common real-world breach vector.
- **Python:** Stack the security stages after tests pass:
  ```yaml
  - uses: sonarsource/sonarqube-scan-action@v3   # SAST + coverage
  - uses: zaproxy/action-api-scan@v0.9.0          # DAST against the live API
  - uses: fossas/fossa-action@v1                   # SCA + 3rd-party license check
  - uses: anchore/scan-action@v5                   # image CVE scan (severity-cutoff: high)
  - uses: anchore/sbom-action@v0                    # SBOM (SPDX/CycloneDX)
  ```
- **Anti-slop:** Don't claim "the pipeline is secure" with only a linter. SAST ≠ DAST ≠ SCA ≠ image scan. Each catches a different class. Also scan the registry on a schedule, not only at push (new CVEs land against unchanged images).

### Distroless, multi-stage, non-root images
- **Rule:** Install build deps in an early stage. Copy only the app into a minimal distroless runtime that runs as a non-root UID.
- **Why:** A fat base image carries a shell, package manager, and OS packages, all attack surface and all CVE churn. Multi-stage keeps build tooling out of the shipped layer.
- **Python:**
  ```dockerfile
  FROM python:3.12-slim AS deps
  WORKDIR /app
  COPY requirements.txt .
  RUN pip install --no-cache-dir -r requirements.txt
  COPY ./app ./app

  FROM gcr.io/distroless/python3-debian12:nonroot AS final
  WORKDIR /app
  COPY --from=deps /app /app
  COPY --from=deps /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
  USER nonroot
  EXPOSE 8080
  CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
  ```
- **Anti-slop:** Don't `RUN pip install` in the final stage, leave the default root user, or stuff tests + linters into the runtime image. Lint the Dockerfile (hadolint) in CI.
- **See also:** modern-devops-practices (Docker images, multi-stage).

### Harden the container securityContext by default
- **Rule:** Default to non-privileged, all capabilities dropped, read-only root filesystem, non-root user, no privilege escalation. Relax only with a documented reason.
- **Why:** A compromised container with write access and Linux capabilities is a foothold for escape and lateral movement. The secure default contains the blast radius.
- **Python:** In `values.yaml` for the Helm chart:
  ```yaml
  securityContext:
    privileged: false
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    runAsNonRoot: true
    runAsUser: 65532
    runAsGroup: 65532
    capabilities:
      drop: ["ALL"]
  ```
- **Anti-slop:** Don't emit a Deployment with no `securityContext`. If the app must write, mount an `emptyDir` for the temp path rather than dropping `readOnlyRootFilesystem`.
- **See also:** the-kubernetes-book (security, threat modeling).

### Pin everything, never `:latest`
- **Rule:** Pin base image tags, GitHub Action versions, and deploy by image digest, not a floating tag.
- **Why:** `:latest` makes builds non-reproducible and lets an upstream change (or a poisoned tag) ship silently. Digest-pinning makes the deployed artifact verifiable.
- **Python:** Resolve a concrete version/digest in CI and write it into `values.yaml`:
  ```yaml
  imageTag: 1.4.2@sha256:9b2c...e10   # version for humans, digest for the kubelet
  imagePullPolicy: Always
  ```
- **Anti-slop:** Don't scan `myimage:latest` then deploy a different freshly-built `latest`. You scanned an artifact you may not be running. Pin the scan target and the deploy to the same digest.

### Three distinct health probes
- **Rule:** Implement startup, liveness, and readiness as separate handlers with separate semantics.
- **Why:** Aliasing them breaks the cluster's self-healing. A liveness probe that checks the database restarts every pod during a DB outage. A readiness probe that ignores shutdown drops in-flight requests on deploy.
  - startup: "did slow init finish", gates the other two, never restarts.
  - liveness: "should the kubelet restart me", process-local ONLY, no dependency checks.
  - readiness: "should the Service route to me", includes deps, and flips to DOWN during graceful shutdown so traffic drains.
- **Python:**
  ```python
  async def check_liveness(state: HealthState) -> tuple[Status, int]:
      # No DB/broker checks here. A dependency outage must not restart the pod.
      return (Status.UP, 200) if not state.shutting_down else (Status.DOWN, 503)

  async def check_readiness(state: HealthState) -> tuple[Status, int]:
      if state.shutting_down or not state.started:
          return (Status.DOWN, 503)            # drain before exit
      for check in state.readiness_checks.values():
          if not await check():
              return (Status.DOWN, 503)         # shed traffic, don't restart
      return (Status.UP, 200)
  ```
- **Anti-slop:** Don't point `livenessProbe`, `readinessProbe`, and `startupProbe` at the same `/health` that pings the DB. Don't run migrations or heavy I/O in a probe. Probes must be cheap and side-effect free.
- **See also:** `examples/devsecops/health_probes.py`, the-kubernetes-book (probes), fluent-python ch21 (asyncio).

### Log structured JSON to stdout
- **Rule:** Emit one machine-parseable JSON schema to stdout from every service, and let the platform ship and index it.
- **Why:** Free-form text logs are unqueryable at scale and force per-service parsers. A shared schema (OpenTelemetry Log Data Model) lets one query span all microservices.
- **Python:** Configure a `logging.Formatter` that serializes the record, and pass structured fields via `extra=`, never f-string interpolation:
  ```python
  log.info("request handled", extra={"http.status_code": 200, "duration_ms": 12})
  # -> {"Timestamp": ..., "SeverityText": "INFO", "Body": "request handled",
  #     "Resource": {"service.name": ...}, "Attributes": {"http.status_code": 200, ...}}
  ```
- **Anti-slop:** Don't write to a file inside the container (lost on restart, fights read-only FS), don't use `print()`, and don't build messages with `logging.info(f"...{x}...")`. That destroys the queryable fields and re-triggers string formatting even when the level is disabled.
- **See also:** `examples/devsecops/structured_logging.py`.

### Carry trace/span correlation IDs
- **Rule:** Propagate and log `TraceId`/`SpanId` so a single request is traceable across services.
- **Why:** Without correlation IDs, debugging a cross-service failure means manually guessing which log lines belong together. Distributed tracing collapses that to one query.
- **Python:** Stamp IDs onto the record (here via `extra=`, in production via an OpenTelemetry logging integration / `contextvars`):
  ```python
  log.info("downstream call", extra={"trace_id": trace_id, "span_id": span_id})
  ```
- **Anti-slop:** Don't generate a fresh random ID per log line. The trace ID must come from the inbound request context and stay constant for the whole request.
- **See also:** `examples/devsecops/structured_logging.py`, fluent-python ch21 (asyncio context).

### Never log secrets
- **Rule:** Redact passwords, tokens, keys, and auth headers before a record is serialized.
- **Why:** Logs are aggregated, retained, and widely readable. A leaked credential in ElasticSearch is a breach with a long tail.
- **Python:** Centralize redaction in the formatter so no call site can forget it:
  ```python
  _REDACTED = frozenset({"password", "token", "secret", "authorization", "api_key"})
  value = "***" if key.lower() in _REDACTED else value
  ```
- **Anti-slop:** Don't log the full request object, headers dict, or env. Don't rely on developers remembering to scrub. Enforce it once in the formatter.
- **See also:** `examples/devsecops/structured_logging.py`.

### Instrument the four golden SLIs with the right instrument type
- **Rule:** Track errors, latency, throughput, and saturation. Use Counter for monotonic events, Gauge for up/down values, Histogram for latency distributions.
- **Why:** The wrong instrument gives the wrong answer. A Gauge for request count loses history on scrape gaps, and a Counter for in-flight work can't go down. Histograms (not averages) are what SLO quantiles need.
- **Python:**
  ```python
  REQUESTS  = Counter("http_requests_total", "...", ("method", "route"))   # throughput
  ERRORS    = Counter("request_errors_total", "...", ("route", "error_class"))
  LATENCY   = Histogram("request_duration_seconds", "...", ("route",))     # p50/p95/p99
  IN_FLIGHT = Gauge("requests_in_flight", "...")                            # saturation
  ```
- **Anti-slop:** Don't compute an average latency in app code and export it as a Gauge. You can't aggregate averages across pods or recover percentiles. Use a Histogram and let Prometheus compute quantiles.
- **See also:** `examples/devsecops/metrics_instrumentation.py`, fluent-python ch09 (decorators).

### Keep metric labels low-cardinality
- **Rule:** Label metrics with bounded values, route templates (`/users/{id}`), HTTP method, error class, never user ids, request ids, or raw paths.
- **Why:** Every distinct label combination is a separate time series. High-cardinality labels exhaust Prometheus memory and bankrupt the metrics bill, the single most common observability outage.
- **Python:**
  ```python
  # ✗ explodes cardinality: one series per user, per path, per message
  ERRORS.labels(f"/users/{user_id}", str(exc)).inc()
  # ✓ bounded label set
  ERRORS.labels("/users/{id}", type(exc).__name__).inc()
  ```
- **Anti-slop:** Don't put the exception *message*, full URL, or timestamp in a label. Bucket and template anything unbounded before it becomes a label.
- **See also:** `examples/devsecops/metrics_instrumentation.py`.

### Alert on SLOs and auto-resolve
- **Rule:** Derive alert rules from service level objectives. Fire when the SLO is breached, auto-cancel when it recovers.
- **Why:** Alerting on raw thresholds instead of objectives produces pages that don't map to user impact. Non-self-resolving alerts train operators to ignore them.
- **Python:** A `PrometheusRule` keyed on an SLI quantile, with a `for:` window to avoid flapping:
  ```yaml
  - alert: HighRequestLatency
    expr: histogram_quantile(0.5, rate(request_duration_seconds_bucket[5m])) > 1
    for: 10m
    labels: { severity: major, class: latency }
    annotations:
      summary: "p50 latency above 1s on {{ $labels.instance }}"
  ```
- **Anti-slop:** Don't alert without a `for:` window (a single slow scrape pages someone) and don't write alerts with no path to auto-resolution.
- **See also:** `examples/devsecops/metrics_instrumentation.py`, modern-devops-practices (SLOs/SRE).

### Keep secrets out of source
- **Rule:** Inject secrets via env vars sourced from `secretKeyRef`, reference CI secrets by name, and keep credentials out of code, values files, and logs.
- **Why:** A committed credential is permanently in git history and instantly harvested by scrapers. Externalized secrets can be rotated without a code change.
- **Python:** Read from env at startup. The manifest wires the env from a Secret:
  ```python
  encryption_key = os.environ["ENCRYPTION_KEY"]  # set via secretKeyRef, not literal
  ```
  ```yaml
  env:
    - name: ENCRYPTION_KEY
      valueFrom: { secretKeyRef: { name: my-svc, key: encryptionKey } }
  ```
- **Anti-slop:** Don't hardcode an API key/password, don't echo `${{ secrets.X }}` into a log line, and don't put real secret values in `values.yaml`.
- **See also:** `examples/devsecops/structured_logging.py` (secret redaction).

## Anti-slop checklist
- No `:latest` base image, action, or deploy tag. Pin versions and deploy by digest.
- No `pip install` or root user in the final Docker stage. Multi-stage + distroless + non-root.
- No Deployment without a hardened `securityContext` (drop ALL caps, read-only FS, non-root, no priv-esc).
- No single `/health` aliased across startup/liveness/readiness. Liveness is dependency-free, readiness drains on shutdown.
- No dependency checks in the liveness probe. No migrations or heavy I/O in any probe.
- No free-form / `print()` logging. Structured JSON to stdout with a shared schema.
- No f-string log messages where structured `extra=` fields belong.
- No secrets in logs, code, or values files. Redact in the formatter, inject via `secretKeyRef`.
- No high-cardinality metric labels (user/request ids, raw paths, exception messages, timestamps).
- No average-latency Gauge. Use a Histogram so Prometheus computes quantiles.
- No security claim backed by a linter alone. SAST, DAST, SCA, SBOM, and image scan are distinct gates.
- No `soft_fail`/`fail-build:false` on the checks meant to gate the pipeline.
- No alert without a `for:` window or an auto-resolution path.

## Bundled examples
| File | Principle(s) demonstrated |
|---|---|
| `examples/devsecops/structured_logging.py` | Structured JSON logging to stdout, trace/span correlation, secret redaction, shared OpenTelemetry schema. |
| `examples/devsecops/health_probes.py` | Three distinct probe semantics, dependency-free liveness, readiness draining on shutdown. |
| `examples/devsecops/metrics_instrumentation.py` | Four golden SLIs, Counter vs Gauge vs Histogram, low-cardinality labels via a decorator. |
