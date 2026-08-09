# ch05: Security Principles

> When this governs: any code that crosses a trust boundary, including HTTP handlers, DB access, deserialization, subprocess/shell calls, auth/authz, secret handling, file uploads, or anything touching user/network/env/file input.

## Principle index
- **Shift security left:** design and build security features first, not last.
- **Threat-model before coding:** enumerate threats (STRIDE/ASF), rank by risk, build countermeasures.
- **Authenticate via a 3rd-party IdP:** never hand-roll credential storage or token issuance.
- **Verify JWTs, don't just decode:** check signature, alg allow-list, aud, iss, exp.
- **Deny by default:** every route declares authz intent, missing authz is a build failure.
- **Prevent IDOR:** check resource ownership, not just authentication. UUIDs are not access control.
- **Validate all untrusted input:** types, ranges, lengths, length-bound strings before regex.
- **DTOs in, DTOs out:** never accept/return entities, allow-list crossing fields.
- **Parameterize SQL:** bind values, allow-list identifiers, cap row counts.
- **No shell for user data:** argument lists with `shell=False`, or stdlib calls.
- **Never deserialize untrusted bytes unsafely:** JSON+validate, never `pickle`/`yaml.load`.
- **Secrets from env/store, fail closed:** validate strength at startup, refuse weak defaults in prod.
- **Hash passwords with a memory-hard KDF:** Argon2id/bcrypt, never md5/sha256/plaintext.
- **Strong, passphrase-friendly password policy:** length first, allow Unicode, block weak patterns.
- **Use modern crypto, encrypt PII at rest/in transit:** AES-256/SHA-256/TLS, rotate keys.
- **Least privilege:** minimal DB grants, non-root containers, dropped capabilities, read-only FS.
- **Don't leak details in errors/logs:** no stack traces, secrets, tokens, or PII to clients/logs.
- **Audit-log security events:** logins, failures, unauthorized requests, high-value actions.
- **Scan dependencies & pin by digest:** vulnerability scans + image SHA pinning.

## Principles

### Shift security left
- **Rule:** Implement security features first in the project, not as a late add-on.
- **Why:** Security deferred to the end gets cut under deadline pressure or forgotten, leaving exploitable gaps in production. Retrofitting auth/validation into a built system is far costlier than designing it in.
- **Python:** This is process, not code: derive a backlog of security stories from threat modeling and prioritize the high-risk ones before feature work. The code-level principles below are the concrete countermeasures.

### Threat-model before coding
- **Rule:** Decompose the system, enumerate threats by category, rank by risk, then build countermeasures.
- **Why:** Without a structured pass you protect what you happen to remember and miss the rest. STRIDE (Spoofing, Tampering, Repudiation, Information disclosure, Denial of service, Elevation of privilege) and ASF (Audit/Logging, AuthN, AuthZ, Config mgmt, Data protection, Data validation, Exception mgmt) are complementary checklists. Using both finds more (e.g. ASF surfaces secret-storage threats STRIDE misses).
- **Python:** Output is a ranked story list (risk High=3 / Medium=2 / Low=1), each mapped to a concrete control: parameterized SQL, JWT authz, rate limiting, input validation, etc. Implement everything above your risk cutoff before first production release.

### Authenticate via a 3rd-party IdP
- **Rule:** Use a battle-tested identity provider (Keycloak, Auth0, Cognito). Never build your own credential store or token issuer.
- **Why:** Rolling your own means handling plaintext credentials, getting password storage/rotation/MFA/lockout wrong, and inheriting every CVE you didn't know about. A mature IdP has fixed the bugs you'd be writing.
- **Python:** Your service is a *resource server*: it receives a bearer token and verifies it. It never sees passwords. See JWT verification below.
- **See also:** fluent-python ch08 (Protocol typing for swappable authorizers).

### Verify JWTs, don't just decode
- **Rule:** Verify the signature against the IdP's JWKS, pin the algorithm allow-list, and require `aud`/`iss`/`exp`.
- **Why:** `jwt.decode(token, options={"verify_signature": False})` or trusting the token's own `alg` lets an attacker forge any identity. The classic kills: `alg: none` (unsigned) and RS256→HS256 alg-confusion (signing with the public key as an HMAC secret).
- **Python:**
  ```python
  import jwt
  # ✗ forgeable: no verification, attacker controls everything
  claims = jwt.decode(token, options={"verify_signature": False})

  # ✓ verify against IdP keys, pin alg, require standard claims
  signing_key = jwks_client.get_signing_key_from_jwt(token).key  # PyJWKClient
  claims = jwt.decode(
      token, signing_key, algorithms=["RS256"],   # NEVER include "none"
      audience="orders-api", issuer="https://iam.example",
      options={"require": ["exp", "iat", "aud", "iss", "sub"]},
  )
  ```
- **Anti-slop:** Generating `jwt.decode(token, key, algorithms=["HS256", "RS256", "none"])` or omitting `audience`/`issuer`. Pin exactly the one algorithm your IdP uses.
- **See also:** `examples/security-principles/jwt_verification.py`

### Deny by default
- **Rule:** Every endpoint must declare an authorization intent. A route with no decorator is a build failure, not an open door.
- **Why:** "Forgot to add `@requires_auth`" is the most common way an endpoint ships unprotected. If absence of a decision means *open*, every omission is a vulnerability. Make absence mean *closed* (or *error*).
- **Python:** Mark intentionally-public routes with an explicit `@allow_any_user`, then scan the AST at startup/CI and raise if any route lacks an `allow_*` decorator. Distinguishing "I meant public" from "I forgot" is the whole point.
- **Anti-slop:** Leaving a FastAPI/Flask handler with no auth dependency and assuming a global middleware covers it. Verify with a static check.
- **See also:** `examples/security-principles/deny_by_default_authz.py`, and fluent-python ch09 (decorators), ch24 (AST is not metaclasses but same static-introspection spirit).

### Prevent IDOR (Insecure Direct Object Reference)
- **Rule:** Authorization must check that the caller *owns* (or has a role for) the specific resource. Authentication alone is not authorization.
- **Why:** Broken access control is OWASP #1. A logged-in user fetching `/orders/{id}` for someone else's `id` is the canonical breach. UUIDs do not help: if the URL leaks, the object is exposed unless ownership is enforced.
- **Python:** Resolve the owner of the resource and compare to the token's `user_id`. Report a non-owned (or missing) record as 403, not 404, so existence isn't leaked.
  ```python
  def require_owner(claims, resource_id, *, owner_of):
      owner = owner_of(resource_id)
      if owner is None or owner != claims.user_id:
          raise AuthorizationError("not the resource owner")
  ```
- **Anti-slop:** Writing `get_order(id)` that authenticates the request but queries by `id` alone. Query by `(id, user_id)` or check ownership explicitly.
- **See also:** `examples/security-principles/jwt_verification.py`

### Validate all untrusted input
- **Rule:** Validate every value from an untrusted source: correct type, numeric range, string max-length (first!), allowed set.
- **Why:** Unvalidated numbers drive DoS (a giant loop bound), unbounded strings drive memory exhaustion and ReDoS, missing type checks crash handlers. Untrusted = CLI args, env vars, stdin, files, sockets, UI. Validate at the boundary before passing inward.
- **Python:** Use pydantic v2 `Field(ge=, le=, min_length=, max_length=, pattern=)` and `model_config = ConfigDict(extra="forbid")`. Length-check strings *before* any regex to avoid ReDoS. Avoid hand-rolled regex, and prefer vetted validators or Google RE2.
  ```python
  class InputOrder(BaseModel):
      model_config = ConfigDict(extra="forbid", str_max_length=200)
      quantity: int = Field(ge=1, le=1000)         # range-bound: no DoS
      product_code: str = Field(max_length=32, pattern=r"^[A-Z0-9-]+$")
  ```
- **Anti-slop:** `quantity: int` with no bounds, trusting `os.environ["X"]` directly all over the code instead of one validating accessor, regex applied before a length cap.
- **See also:** `examples/security-principles/input_validation_dtos.py`, and fluent-python ch05 (dataclasses vs pydantic models).

### DTOs in, DTOs out
- **Rule:** Never accept or return ORM entities. Use input/output DTOs that allow-list exactly the fields allowed to cross the boundary.
- **Why:** Accepting an entity lets a client set `is_admin`/`id`/timestamps (mass-assignment / privilege escalation). Returning an entity leaks `password_hash` and internal flags. With `extra="forbid"`, unknown keys are rejected so junk can't reach a schemaless store.
- **Python:** `InputUser` simply has no `is_admin` field, so a client cannot set it even by sending the key. `OutputUser` has no `password_hash` field, so it cannot leak. Add a new sensitive entity attribute later and it stays internal automatically.
- **Anti-slop:** `return user_entity` from a handler, or `Order(**request.json())` straight into the model. Map through an explicit DTO.
- **See also:** `examples/security-principles/input_validation_dtos.py`

### Parameterize SQL
- **Rule:** Bind values as parameters. Never concatenate/f-string user data into SQL. Allow-list identifiers. Clamp row limits.
- **Why:** Concatenating user text into a WHERE clause lets a payload like `x' OR '1'='1` return every row, and a payload ending the statement then issuing a DROP can destroy the table. Identifiers (column/table/sort) can't be bound, so they need an allow-list, not interpolation of raw input.
- **Python:**
  ```python
  # ✗ injection: building the query by concatenating `name` into the SQL text,
  #   i.e. cur.execute("... WHERE name = " + repr(name)), never do this.
  # ✓ bound parameter (driver separates SQL from data)
  cur.execute("SELECT id, name FROM users WHERE name = ?", (name,))
  # ✓ identifier via allow-list mapping to a pre-written query, never raw input
  query = {"name": "SELECT id FROM users ORDER BY name LIMIT ?"}[sort_by]
  cur.execute(query, (min(page_size, 100),))   # also cap rows: no mass disclosure
  ```
- **Anti-slop:** Building any query with `f"... {value} ..."` and passing it to `execute()`. Prefer an ORM or bound parameters. Map sort/identifier inputs to fixed literal queries.
- **See also:** `examples/security-principles/parameterized_sql.py`

### No shell for user data
- **Rule:** Never pass untrusted data through a shell. Use argument lists with `shell=False`, or a dedicated stdlib function.
- **Why:** `os.system(f"mkdir {dir}")` with a value like `x && <destructive-shell-command>` runs the attacker's chained command. The shell interprets metacharacters (`&&`, `;`, `|`, backticks). An argument list does not.
- **Python:**
  ```python
  os.system(f"mkdir {user_dir}")            # ✗ shell injection
  subprocess.run(["mkdir", user_dir], shell=False, check=True)  # ✓ one opaque arg
  os.mkdir(user_dir)                        # ✓ better: no process at all
  ```
- **Anti-slop:** `subprocess.run(cmd, shell=True)` with an interpolated string, or `os.system`/`os.popen` on anything user-derived. Confine file paths with `Path.is_relative_to` to stop traversal.
- **See also:** `examples/security-principles/safe_deserialization_and_subprocess.py`

### Never deserialize untrusted bytes unsafely
- **Rule:** Deserialize untrusted data as JSON (data-only) then validate into a typed model. Never `pickle.loads`/`yaml.load`/`marshal` on it.
- **Why:** `pickle.loads` executes arbitrary code during unpickling via `__reduce__`. `yaml.load` without `SafeLoader` instantiates arbitrary Python. Both are remote code execution if the bytes are attacker-controlled.
- **Python:**
  ```python
  data = pickle.loads(raw)                  # ✗ RCE on untrusted bytes
  data = yaml.load(raw)                     # ✗ RCE (use yaml.safe_load)
  data = WebhookEvent.model_validate(json.loads(raw))  # ✓ data-only + validated
  ```
- **Anti-slop:** Reaching for `pickle` to "serialize an object" that crosses a network/file boundary. Pickle is for trusted, internal data only.
- **See also:** `examples/security-principles/safe_deserialization_and_subprocess.py`, and fluent-python ch04 (bytes/text handling).

### Secrets from env/store, fail closed
- **Rule:** Load secrets from environment/secret store (never source). Validate strength at startup and refuse to run on weak/default values in production.
- **Why:** Hard-coded secrets leak via VCS, logs, and tracebacks. A service that starts with `DB_PASSWORD=changeme` in prod is pre-breached. Failing closed (exit non-zero) turns a silent misconfiguration into a loud, blocking one.
- **Python:** One validating accessor wraps secrets in a type whose `repr` masks the value so it never lands in a log line or traceback.
  ```python
  @dataclass(frozen=True, slots=True)
  class Secret:
      _value: str
      def reveal(self) -> str: return self._value
      def __repr__(self) -> str: return "Secret(***)"
  ```
- **Anti-slop:** `SECRET_KEY = "sk-1234..."` in code, `os.environ.get("DB_PASSWORD", "changeme")` (a default secret that ships), logging a config object that prints raw secrets.
- **See also:** `examples/security-principles/secrets_and_config.py`

### Hash passwords with a memory-hard KDF
- **Rule:** Hash passwords with Argon2id (or bcrypt/scrypt). Never store plaintext or use a fast general-purpose hash.
- **Why:** md5/sha256 are designed to be *fast*, which means billions of guesses per second on a leaked DB. Argon2id is memory-hard and salted (salt + params embedded in the output), making offline cracking economically infeasible. Verify with the library's constant-time check and rehash transparently when cost parameters increase.
- **Python:**
  ```python
  from argon2 import PasswordHasher
  ph = PasswordHasher()
  stored = ph.hash(password)                # salted, parameterized
  ph.verify(stored, password)               # constant-time, raises on mismatch
  if ph.check_needs_rehash(stored): stored = ph.hash(password)
  ```
- **Anti-slop:** `hashlib.sha256(password.encode()).hexdigest()`, an unsalted hash, or `==` comparison of hashes (timing leak). Use the KDF's own verify.
- **See also:** `examples/security-principles/password_hashing.py`

### Strong, passphrase-friendly password policy
- **Rule:** Require length first (≥12), allow Unicode passphrases, and block common/weak patterns. Generate long random machine-to-machine secrets.
- **Why:** Passphrases are both stronger and more memorable than mangled short passwords. Unicode lets users use their own language. Length dominates entropy. Checking length first also avoids running expensive checks on huge inputs.
- **Python:** NFC-normalize before comparing/hashing so visually identical passphrases match. Reject passwords containing the username or appearing on a deny-list. DB/service passwords should be `secrets.token_urlsafe(32)`, generated per environment, never reused.
- **Anti-slop:** A regex demanding exactly "1 upper, 1 digit, 1 symbol" while capping at 16 chars and rejecting spaces. That *weakens* security by blocking passphrases.
- **See also:** `examples/security-principles/password_hashing.py`

### Use modern crypto, encrypt PII at rest and in transit
- **Rule:** Use AES-256 / SHA-256 / TLS, encrypt PII before storing, and rotate keys on a cryptoperiod or suspected compromise.
- **Why:** Legacy/weak algorithms and plaintext transport leak PII to network sniffers and DB-dump attackers. Identify what counts as sensitive under privacy law/regulation/business need, encrypt it, and never cache or log it.
- **Python:** Use vetted libraries (`cryptography`'s Fernet/AES-GCM), never hand-rolled crypto. Store a key-id per encrypted row to support gradual rotation (decrypt-with-old, re-encrypt-with-new, then destroy old). Terminate TLS at the gateway and mTLS between services (e.g. Istio) rather than reimplementing TLS per service.
- **Anti-slop:** `from Crypto.Cipher import DES`, ECB mode, a static IV, or inventing your own encryption. Reach for `cryptography` with an authenticated mode (AES-GCM).

### Least privilege
- **Rule:** Grant the minimum rights everywhere: scoped DB users, non-root read-only containers, dropped capabilities.
- **Why:** When (not if) a component is compromised, least privilege bounds the blast radius. A web DB user with only SELECT/INSERT/UPDATE/DELETE cannot DROP your tables even through a missed injection. A non-root container can't tamper with the host.
- **Python/deploy:** Separate admin vs runtime DB accounts with distinct passwords and minimal grants. Containers: `privileged: false`, drop all capabilities, read-only root FS, non-root user/group, no privilege escalation, distroless base. (DevSecOps chapter covers the Dockerfile.)
- **Anti-slop:** App connecting as the DB superuser, `USER root` (or no USER) in a Dockerfile, granting `ALL PRIVILEGES`.

### Don't leak details in errors or logs
- **Rule:** Keep stack traces, secrets, tokens, PII, connection strings, and component versions out of client responses and logs.
- **Why:** A stack trace or "Keycloak 18.06 connection failed" message hands an attacker a map of your stack and its known CVEs. Logging tokens/PII turns your log store into a secondary breach target and may violate privacy law.
- **Python:** Return abstract errors (`{"error": "IAM system error"}`) with a stable status. Log a correlation id, not the secret. Use a custom exception handler that strips internals and audit-logs 401/403 separately.
- **Anti-slop:** `return {"error": str(exc)}` (which may embed a query or path), `logger.info(f"token={access_token}")`, or `debug=True` in production.

### Audit-log security events
- **Rule:** Log security-relevant events (logins, failed logins, unauthorized/invalid requests, high-value transactions) to a tamper-resistant store.
- **Why:** Without an audit trail you can't detect or investigate an attack (repudiation), and you can't alert on suspicious patterns. Audit logs are distinct from app logs and must never contain the secrets listed above.
- **Python:** In the framework's exception handler, emit a structured audit event on 403/401 with actor, action, resource, and outcome, not the token.

### Scan dependencies and pin by digest
- **Rule:** Run vulnerability scanning in CI / the registry, and pin container images by SHA digest from trusted sources.
- **Why:** Most code in a service is third-party. A tag-pinned image can be silently replaced by a malicious one with the same tag. A digest pin can't. Daily scans catch newly disclosed CVEs in dependencies you already shipped.
- **Python/deploy:** Pin `pip`/`uv` deps with hashes, pull from PyPI or an internal mirror, reference images as `image@sha256:...`, and require code review for all source/deploy/infra changes.

## Anti-slop checklist
- Refuse `jwt.decode(..., options={"verify_signature": False})` and refuse `"none"` (or an over-broad list) in `algorithms=`.
- Refuse f-string / `+` / `%` / `.format()` SQL built from variables passed to `execute()`. Bind parameters, allow-list identifiers.
- Refuse `subprocess.run(..., shell=True)` and `os.system`/`os.popen` on user-derived strings. Use arg lists or stdlib calls.
- Refuse `pickle.loads`, `yaml.load` (no SafeLoader), `marshal.loads`, and `eval`/`exec` on untrusted input.
- Refuse `hashlib.{md5,sha1,sha256}` for password storage. Use Argon2id/bcrypt and the library's verify, not `==`.
- Refuse hard-coded secrets/keys/tokens and `os.environ.get(secret, "<default>")` defaults. Load from env/store and fail closed in prod.
- Refuse returning ORM entities or `str(exc)`/stack traces to clients. Map through output DTOs and abstract error messages.
- Refuse unbounded `int`/`str` fields on input models. Set `ge/le`, `max_length`, and `extra="forbid"`.
- Refuse authenticating without authorizing: every handler checks ownership/role. No route lacks an explicit authz decision.
- Refuse logging tokens, passwords, PII, connection strings, or encryption keys.

## Bundled examples
| File | Principle(s) demonstrated |
|---|---|
| `examples/security-principles/input_validation_dtos.py` | Input validation, DTOs-in/DTOs-out boundary, reject unknown fields |
| `examples/security-principles/parameterized_sql.py` | SQL injection prevention, identifier allow-listing, row-count caps |
| `examples/security-principles/secrets_and_config.py` | Secrets from env, fail-closed strength validation, masked-repr `Secret` |
| `examples/security-principles/password_hashing.py` | Argon2id hashing, verify + rehash, passphrase-friendly policy |
| `examples/security-principles/jwt_verification.py` | JWT signature/alg/aud/iss verification, deny-by-default, IDOR prevention |
| `examples/security-principles/safe_deserialization_and_subprocess.py` | Safe JSON deserialization, OS command-injection / path-traversal prevention |
| `examples/security-principles/deny_by_default_authz.py` | Deny-by-default authz decorators + AST startup scan for unprotected routes |
