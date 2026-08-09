# ch01: Architectural Principles and Patterns

> When this governs: designing or reviewing the boundaries *between* Python services/packages, how a system splits into microservices, how they name, encapsulate, configure, communicate, version, and recover. Not intra-class design (that is ch02 OO design).

## Principle index

- **Single Responsibility (system→component):** Give every service, library, and module one dedicated purpose at its abstraction level.
- **Uniform Naming:** Name components by a type postfix (`-service`, `-client`, `-job`, `-lib`).
- **Encapsulation:** A service hides its datastore behind a public API. No shared DB.
- **Service Aggregation:** A higher-level facade fans out to lower-level single-purpose services.
- **High Cohesion / Low Coupling:** Group what changes together. Let services not know each other.
- **Library Composition:** Build higher-level libraries from focused lower-level ones.
- **Avoid Duplication:** Extract shared functionality to one service or library, not copies.
- **Externalized Configuration:** Read all deploy-varying values from the environment, fail fast on missing ones.
- **Service Substitution:** Address dependencies by configurable host/port so they swap without code change.
- **Stateless Services:** Store state outside the process so instances are interchangeable.
- **Resilient Services:** Handle SIGTERM gracefully. Let the orchestrator restart you.
- **Observable Services:** Emit metrics, logs, and traces so failures alert, not hide.
- **Inter-Service Communication:** Pick sync, async, or shared-data per response need.
- **Strategic DDD:** Split the domain into subdomains/bounded contexts top-down, one team per context.
- **Semantic Versioning / No Major Bump:** Version `MAJOR.MINOR.PATCH`, and ship a new name instead of breaking.
- **Trunk-Based Git:** Short feature branches into main, and gate features with toggles.
- **Event Sourcing:** Store state as an append-only event log. Current state is a fold.
- **CQRS:** Separate the write (command) model from a read-optimized query model.
- **Saga / Distributed Transaction:** Replace rollback with idempotent compensating actions.

## Principles

### Single Responsibility Principle (architecture scale)

- **Rule:** Give every software entity (system, application, service, library, module) exactly one responsibility at its level of abstraction.
- **Why:** A service that owns orders *and* sales items cannot scale, deploy, or be replaced independently. The two grow tangled and every change risks the other. At module scale, a 2000-line `models.py` or `utils.py` defeats discovery and review.
- **Python:** Express the boundary as a focused module, not a grab-bag. One public class or one public function per module. Private helpers may share it.
  ```python
  # ✗ utils.py, everything unfindable, untestable in isolation
  def parse_yaml(...): ...
  def send_email(...): ...
  def normalize_phone(...): ...

  # ✓ a package whose layout *is* the responsibility map
  # email/send_email.py        -> def send_email(msg: EmailMessage) -> None: ...
  # text/normalize_phone.py    -> def normalize_phone(raw: str) -> str: ...
  ```
- **Anti-slop:** LLMs default to one fat module and a kitchen-sink `Manager`/`Service` class that does CRUD + email + reporting. Split by reason-to-change, not by convenience.
- **See also:** fluent-python ch05 (dataclasses for focused entities).

### Uniform Naming Principle

- **Rule:** Name each component with a postfix that reveals its *type*: `-service`/`-svc`, `-client`/`-ui`/`-app`, `-job`, `-cronjob`, `-operator`, `-cli`, `-lib`/`-library`.
- **Why:** The kind of a repo/deployment is then readable at a glance, with no need to open it. A name like `purchase-service` also asserts single responsibility. `shopping-cart-and-order-service` advertises a violation.
- **Python:** Make the package/distribution name carry the postfix, and combine subdomains under a higher abstraction noun rather than `and`.
  ```python
  # ✗ shopping_cart_and_order_service/   (two responsibilities in the name)
  # ✓ purchase_service/                  (one purpose at a higher abstraction)
  #     purchase_service/shoppingcart/   (subdomain dirs, ready to extract later)
  #     purchase_service/order/
  ```
- **Anti-slop:** Don't invent `MicroserviceManager`, `data_service_handler_impl`, or postfix-free repo names. The postfix is the contract.

### Encapsulation Principle

- **Rule:** A service encapsulates its state behind a public API. Its database is private, and no other service touches it directly.
- **Why:** A shared database couples services through schema and load, and silently leaks internal fields to clients. Whitelisting serialized fields and gating all access through a repository keeps the data contract explicit and substitutable.
- **Python:** Serialize an explicit allow-list (DRF: `fields = ["id", ...]`, never `"__all__"`). Reach the store only through a repository interface.
  ```python
  class SalesItemDTO(TypedDict):           # the public shape, enumerated
      id: int
      name: str
      priceCents: int                       # cost_price stays internal, unleaked

  class SalesItemRepository(Protocol):      # the only door to the private store
      def get(self, item_id: int) -> SalesItem | None: ...
  ```
- **Anti-slop:** Avoid `fields = "__all__"`, `return {**entity.__dict__}`, and two services importing the same ORM models. Each leaks or couples.
- **See also:** `examples/architectural-principles-and-patterns/encapsulation_repository.py`, fluent-python ch08 (Protocol).

### Service Aggregation Principle

- **Rule:** A higher-level service aggregates lower-level single-purpose services behind a facade. Clients call only the facade.
- **Why:** Direct client→lower-service calls couple the client to internals and make every lower-service change ripple outward. The facade (a BFF / facade + bridge pattern) localizes orchestration, auth, caching, and audit logging in one place.
- **Python:** Inject the lower services as Protocols, and fan out independent calls concurrently so latency is the slowest call, not their sum.
  ```python
  async def get_user(self, user_id: int) -> User:
      account, items, orders = await asyncio.gather(  # ✓ concurrent fan-out
          self._accounts.get_account(user_id),
          self._sales_items.list_for_user(user_id),
          self._orders.list_for_user(user_id),
      )
      return User(account, items, orders)
  ```
- **Anti-slop:** Don't `await` independent remote calls sequentially, and don't let the facade reach into a lower service's database. Aggregate via its API.
- **See also:** `examples/architectural-principles-and-patterns/service_aggregation.py`, fluent-python ch21 (asyncio), ch08 (Protocol).

### High Cohesion, Low Coupling Principle

- **Rule:** Put functionality that changes together in the same service. Keep services that don't depend on each other unaware of each other.
- **Why:** High *functional* cohesion (shopping cart + order: they change together, share transactions) avoids distributed transactions. Low coupling lets teams build the lower services in parallel and swap one without touching three others.
- **Python:** Depend on abstractions (Protocol / injected callable), never on a concrete sibling service's module. The dependency arrows all point to the facade, not between leaves.
  ```python
  # ✗ order_service imports sales_item_service.client  -> leaf-to-leaf coupling
  # ✓ both depend only on their own Protocols, the facade wires them together
  ```
- **Anti-slop:** Resist `from other_service import ...` between peer services. That single import is the coupling the architecture exists to prevent.

### Library Composition Principle

- **Rule:** Compose higher-level libraries from focused lower-level libraries, each with one responsibility.
- **Why:** A config-parsing lib built on separate `json` and `yaml` libs lets consumers depend only on what they use, no XML code (and no XML CVEs) shipped with a YAML-only need.
- **Python:** Keep the dependency graph layered and acyclic. The top package re-exports, the leaves stay independent and separately testable.
  ```python
  # config_parser_lib/  depends on -> json_parser_lib, yaml_parser_lib
  # consumers import config_parser_lib only, leaves stay swappable & CVE-isolated
  ```
- **Anti-slop:** Don't bundle unrelated formats/concerns into one mega-lib "for convenience." Bundling forces unused code and its patches onto every consumer.

### Avoid Duplication Principle

- **Rule:** Extract functionality duplicated across services into one shared service (preferred) or library.
- **Why:** Two services each re-implementing email sending means two code paths to patch and two places for bugs. A shared library couples versions (every consumer must bump + retest on a security patch). A shared service avoids that coupling.
- **Python:** Prefer a dedicated `email-notification-service` called over the network, and reach for a shared lib only when network overhead is unjustified.
- **Anti-slop:** Don't paste a helper into each service "to keep them independent." That is duplication, not independence. It multiplies the patch surface.

### Externalized Service Configuration Principle

- **Rule:** Read every value that varies between deployments from the environment. Never hardcode defaults that suit only dev.
- **Why:** A hardcoded `os.environ.get("MONGODB_HOST", "localhost")` ships a dev default to prod the day someone forgets to set the var. The service connects to nothing, or worse, to the wrong store, and you find out at request time, not boot time.
- **Python:** Load once at startup into a frozen, typed config, and cast and require explicitly so a missing/bad var raises immediately.
  ```python
  def _require_int(name: str) -> int:
      raw = os.environ.get(name)
      if not raw:
          raise ConfigError(f"{name!r} is not set")  # ✓ fail at boot
      return int(raw)  # ✗ os.environ["PORT"] used as int without cast => TypeError later
  ```
  Inline, the env/Helm side is just: `LOG_LEVEL=INFO`, `MONGODB_PORT=27017` → injected via Deployment `env:`/`secretKeyRef`. Secrets come from the environment, never the repo.
- **Anti-slop:** Don't sprinkle `os.environ.get(...)` (returns `str | None`) across the codebase, and don't default credentials. Centralize, type, and fail fast.
- **See also:** `examples/architectural-principles-and-patterns/externalized_config.py`.

### Service Substitution Principle

- **Rule:** Expose dependencies transparently by host/port (or a connection config) so any one can be swapped via configuration alone.
- **Why:** If the MongoDB address is config, switching localhost → in-cluster Service → Atlas is an env change. If it's a literal, it's a code change + redeploy + retest.
- **Python:** Pass the dependency's address through the typed config object. Never bake an address or build a client from literals.
  ```python
  # ✗ AsyncIOMotorClient("mongodb://localhost:27017")
  # ✓ AsyncIOMotorClient(f"mongodb://{cfg.mongo.host}:{cfg.mongo.port}")
  ```
- **Anti-slop:** Don't construct DB/HTTP clients from string literals in the module body. That literal is a deployment lock-in.
- **See also:** `examples/architectural-principles-and-patterns/externalized_config.py`.

### Stateless Microservices Principle

- **Rule:** Keep no client state in the process. Store it in a shared datastore or cache so instances are interchangeable.
- **Why:** In-process state defeats horizontal scaling and rolling restarts. A request routed to a different replica loses its context, and SIGTERM drops live sessions.
- **Python:** No module-level mutable session dicts. Persist to Redis/DB keyed by request identity.
  ```python
  # ✗ SESSIONS: dict[str, Cart] = {}   # lost on restart, wrong on the next replica
  # ✓ await redis.set(f"cart:{user_id}", cart.to_json())
  ```
- **Anti-slop:** Avoid module-level mutable caches/counters that pretend to be per-user state. They are per-*instance* and break under more than one replica.

### Resilient Microservices Principle

- **Rule:** Catch SIGTERM and shut down gracefully (drain in-flight work, requeue, close connections) within the grace period.
- **Why:** Orchestrators send SIGTERM, then SIGKILL after ~30s. Ignore SIGTERM and you drop requests, corrupt half-done work, and leak connections on every rollout.
- **Python:** Register a handler. For asyncio, hook the loop's signal handler and await cleanup.
  ```python
  import asyncio, signal
  async def _serve() -> None:
      stop = asyncio.Event()
      loop = asyncio.get_running_loop()
      loop.add_signal_handler(signal.SIGTERM, stop.set)  # ✓ graceful drain
      await stop.wait()
      await _drain_and_close()
  ```
- **Anti-slop:** Don't leave SIGTERM to default (instant exit) in a long-running server, and don't `signal.signal` from a non-main thread (it raises). Use the loop API in asyncio.
- **See also:** fluent-python ch21 (asyncio), ch18 (context managers for cleanup).

### Observable Microservices Principle

- **Rule:** Emit metrics, structured logs (at least errors+warnings), and distributed traces. Abnormal conditions must alert.
- **Why:** No one tails the logs of 100 instances by hand. Without metrics-driven alerts and trace correlation, a failure is invisible until a customer reports it.
- **Python:** Use structured logging with a correlation/trace id. Never `print` for diagnostics in a service.
  ```python
  logger.error("withdraw failed", extra={"saga_id": saga_id, "account": acct})
  ```
- **Anti-slop:** Don't use bare `except:` that swallows the error silently, and don't `print()` for service diagnostics. A swallowed exception is an unobservable failure.

### Inter-Service Communication Principle

- **Rule:** Choose synchronous (HTTP/gRPC) when you need an immediate response, asynchronous (message broker) for fire-and-forget or event-driven flows, and shared-data when re-storing data is wasteful.
- **Why:** Synchronous calls for fire-and-forget work (email, audit) needlessly couple availability and latency. Async fire-and-forget needs broker acks + reprocessing-on-failure or the request is silently lost.
- **Python:** For async consumers, ack only after the work is durable. On SIGTERM, requeue the in-flight message.
  ```python
  # ✗ await email_service_http.send(...)   # blocks the caller on a no-response op
  # ✓ await broker.publish("email.send", msg)  # then ack on confirmed durability
  ```
- **Anti-slop:** Don't make every interaction a blocking HTTP call. Fire-and-forget over HTTP couples the caller's success to the callee's uptime.

### Strategic Domain-Driven Design Principle

- **Rule:** Decompose top-down, domain → subdomains → bounded contexts (each a service, one team), using a ubiquitous language with no synonyms.
- **Why:** Without bounded contexts, the same word (`flight`, `account`) means different things in different parts and the model collapses into shared mush. One team per context keeps it changeable.
- **Python:** A bounded context = a package. Translate other contexts' models at the edge via DTOs (an anticorruption layer / adapter), and don't import their entities.
  ```python
  # ✓ ticketing/ and cargo/ each define their own Flight, an adapter maps between
  def to_ticketing_flight(cargo_flight: cargo.Flight) -> ticketing.Flight: ...
  ```
- **Anti-slop:** Don't create one shared `models.py` of "universal" entities across contexts. A `Flight` shared across ticketing and maintenance is two different things wearing one name.

### Semantic Versioning & Don't-Increase-Major Principle

- **Rule:** Version `MAJOR.MINOR.PATCH`. Backport security/bug fixes to all majors. Rather than a breaking major bump, publish a new component (`common-ui-lib-2`). Avoid 0.x and non-LTS deps in prod.
- **Why:** Forcing consumers to a new major just to get a security patch creates "upgrade hell." Everyone must refactor to stay safe. A 0.x dep can break its API at any release.
- **Python:** Pin in `pyproject.toml` with compatible-release ranges, and let consumers `pip install --upgrade` safely because no minor/patch breaks.
  ```toml
  dependencies = ["httpx~=0.27"]   # ✗ avoid "ariadne==0.1.0" (0.x, unstable API)
  ```
- **Anti-slop:** Don't propose breaking changes under a minor bump, and don't pin a 0.x library as a production foundation.

### Trunk-Based Git Version Control Principle

- **Rule:** Develop in short-lived feature branches off `main`, merge via reviewed PRs that pass CI, and gate incomplete/cross-team features behind toggles read from config.
- **Why:** Long-lived branches diverge and merge painfully. Feature toggles let unfinished code merge to main safely, disabled until tested.
- **Python:** Read the toggle from externalized config, and keep the branch in one place (open-closed), not scattered `if FLAG` across the codebase.
  ```python
  if config.feature_flags.new_checkout:   # ✓ one decision point, config-driven
      return new_checkout(cart)
  return legacy_checkout(cart)
  ```
- **Anti-slop:** Don't hardcode `FEATURE_X = True` in source, and don't smear the same toggle through ten call sites (shotgun surgery).

### Event Sourcing Pattern

- **Rule:** Persist state as an append-only sequence of immutable events, and derive current state by folding the log. Create and read only, never update or delete an event.
- **Why:** You get a free audit log, time-travel, and reproducible state, at the cost of rebuilding state from events (mitigated by CQRS projections).
- **Python:** Model events as frozen dataclasses under a sealed union, and fold with `reduce`/`match` for exhaustive, type-checked transitions.
  ```python
  OrderEvent = OrderCreated | OrderPaid | OrderShipped | OrderCanceled
  def project(events: list[OrderEvent]) -> OrderView:
      return reduce(_apply, events, None)  # _apply: match over the union
  ```
- **Anti-slop:** Don't model events as mutable dicts/objects you later edit, and don't add an `update_event` path. Mutability destroys the audit guarantee.
- **See also:** `examples/architectural-principles-and-patterns/event_sourcing_cqrs.py`, fluent-python ch05 (frozen dataclasses), ch02 (match).

### CQRS Pattern

- **Rule:** Use a different model for commands (writes) than for queries (reads), and maintain a read-optimized materialized view fed from the write model.
- **Why:** Replaying the full event log on every read is slow. A projection indexed for the query (e.g. by customer id) serves reads cheaply while the command side stays the source of truth.
- **Python:** Keep the write-side event types and the read-side `OrderView` as distinct types. The view is derived, never authoritative.
- **Anti-slop:** Don't reuse the write entity as the API read shape, and don't let the read model accept writes. The whole point is two shapes.
- **See also:** `examples/architectural-principles-and-patterns/event_sourcing_cqrs.py`.

### Saga / Distributed Transaction Pattern

- **Rule:** Across services there is no ACID rollback. Give every forward step an *idempotent* compensating action and run compensations in reverse on failure. Compensate timed-out (unknown-outcome) steps conditionally.
- **Why:** A partial multi-service transaction leaves the system inconsistent. Idempotency is non-negotiable: a compensation can fail after it already succeeded and be retried, so re-running it must be a no-op.
- **Python:** Key every effect by a `saga_id` so both the forward and the compensation are idempotent, and retry compensations until they succeed.
  ```python
  async def undo_withdraw(self, saga_id: str, amount: int) -> None:
      if saga_id not in self._withdrawn:   # ✓ idempotent: nothing to undo
          return
      self._balance += amount
      self._withdrawn.discard(saga_id)
  ```
- **Anti-slop:** Don't assume cross-service `try/except` gives rollback, and don't write non-idempotent compensations (double-refund on retry). Non-compensable steps (email) get delayed/queued or run last.
- **See also:** `examples/architectural-principles-and-patterns/saga_orchestration.py`, fluent-python ch08 (Callable/Protocol), ch21 (asyncio).

## Anti-slop checklist

- Don't bundle two responsibilities into one service/module/class or one mega-`utils.py`. Split by reason-to-change.
- Don't let two services share a database or import each other's ORM models/entities. Encapsulate behind an API.
- Don't serialize entities with `fields = "__all__"` or `{**obj.__dict__}`. Whitelist the public shape.
- Don't hardcode hosts, ports, credentials, or feature flags. Read them from typed, fail-fast config.
- Don't default required settings (especially credentials) to dev values. Raise at startup instead.
- Don't `await` independent remote calls sequentially. Fan out with `asyncio.gather`.
- Don't construct DB/HTTP clients from string literals in module bodies.
- Don't keep per-user state in module-level mutables. Stateless services store state externally.
- Don't ignore SIGTERM in a long-running server, and don't `signal.signal` off the main thread under asyncio.
- Don't swallow exceptions with bare `except:` or use `print()` for service diagnostics. Emit structured logs.
- Don't write non-idempotent saga compensations or assume cross-service `try/except` rolls back.
- Don't model events as mutable objects you later edit, or add update/delete paths to an event log.
- Don't pin 0.x or non-LTS dependencies as production foundations. Don't break APIs under a minor bump.

## Bundled examples

| File | Principle(s) demonstrated |
| --- | --- |
| `externalized_config.py` | Externalized Configuration, Service Substitution (typed fail-fast loader) |
| `service_aggregation.py` | Service Aggregation, High Cohesion/Low Coupling (concurrent facade over Protocols) |
| `encapsulation_repository.py` | Encapsulation, explicit DTO whitelisting (repository as the only store seam) |
| `saga_orchestration.py` | Distributed Transaction / Saga, idempotent compensation |
| `event_sourcing_cqrs.py` | Event Sourcing + CQRS (immutable event union folded into a read view) |
