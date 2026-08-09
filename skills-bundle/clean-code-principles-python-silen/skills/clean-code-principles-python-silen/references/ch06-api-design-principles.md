# ch06: API Design Principles

> When this governs: designing or reviewing any service boundary, including REST/JSON-RPC/GraphQL/gRPC controllers, the DTOs crossing them, the service/repository layers behind them, and how errors become wire responses.

## Principle index

- **Pick the protocol for the traffic:** RPC for actions, REST for CRUD-on-resources, GraphQL for nested/client-shaped reads, gRPC for binary/high-volume.
- **Model resources as nouns, plural, CRUD-by-verb:** `POST/GET/PUT/DELETE /sales-items[/{id}]`, not `getSalesItems`.
- **Use HTTP status codes by their meaning:** 201 create, 204 update/delete, 404 read-miss, 409 version conflict, 503 transient.
- **Split input and output DTOs:** clients send less than the server returns. Never share one writable class.
- **Validate every field at the boundary, output included:** bound string/list lengths to kill denial-of-service and shape attacks.
- **Keep the web framework out of the core:** dependency points web → service → repository, never back.
- **Raise domain errors, map them to HTTP at one boundary:** one envelope, one handler, not `HTTPException` in business logic.
- **Hide internals in error responses:** stable `errorCode`, no stack trace in production.
- **Depend on a repository abstraction:** `Protocol` interface, injected implementation, returns entities not DTOs.
- **Parameterize all SQL, allow-list identifiers:** placeholders for values, allow-lists for column names you must interpolate.
- **Make DELETE idempotent:** already-deleted returns 204, never 404.
- **Prevent duplicate creates:** unique column or client `creationUuid`, and retried timeouts must not double-insert.
- **Cross-cutting concerns are decorators:** audit/metrics/authz wrap handlers, general-purpose, `functools.wraps`.
- **Version in the URL path:** `/v2/sales-items`, additive changes preferred over breaking ones.
- **camelCase on the wire, snake_case in Python:** the JSON shape is a contract. The Python name is internal.

## Principles

### Pick the protocol for the traffic

- **Rule:** Choose RPC for single actions, REST for resource CRUD, GraphQL for nested/client-selected fields, gRPC for binary or high-volume.
- **Why:** A square-peg protocol forces awkward endpoints (`POST /get-things`) or over/under-fetching. Matching the protocol to the access pattern makes the whole API self-documenting.
- **Python:** FastAPI for REST/RPC, Strawberry/Ariadne for GraphQL, and `grpcio` for gRPC. One service layer can sit behind all of them. Only the controller changes.
- **Anti-slop:** Defaulting to REST for an action API and ending up with `POST /process/start` + `POST /process/stop` instead of modelling a `process` resource you create/delete, or reaching for GraphQL when there is no nesting and no field-selection need.

### Model resources as nouns, plural, CRUD-by-verb

- **Rule:** Name endpoints after the resource (plural noun). Express the operation with the HTTP verb, not the path.
- **Why:** `getSalesItems`/`deleteSalesItem` in the path duplicates what the method already says and fragments the URL space. Nouns + verbs give a small, predictable surface.

```python
# ✗ verb in the path, singular, inconsistent
@app.post("/get-sales-item-by-id")
@app.post("/delete-sales-item")

# ✓ noun resource, verb = HTTP method
@app.get("/sales-items/{item_id}")
@app.delete("/sales-items/{item_id}", status_code=204)
```

- **Anti-slop:** RPC-style verb paths under a "REST" label. Non-CRUD actions are the exception: `POST /accounts/{id}/deposit` is fine when there is genuinely no resource to model.
- **See also:** `examples/api-design-principles/rest_controller.py`

### Use HTTP status codes by their meaning

- **Rule:** 200 read, 201 create (+ body), 204 update/delete (no body), 400 bad input, 404 read of a missing resource, 409 version conflict, 413 payload too large, 429 rate-limited, 500 bug, 503 dependency down.
- **Why:** Clients (and gateways, retries, caches) branch on status. Returning 200 for everything forces clients to parse bodies to learn success/failure, and breaks automatic retry on 503.
- **Python:** Set `status_code=` per route in FastAPI. Do not hand-roll responses for the happy path.
- **Anti-slop:** 200 for a create instead of 201, 404 on DELETE of an already-gone item, using 400 for a transient DB outage that should be 503-and-retry.

### Split input and output DTOs

- **Rule:** Give input and output their own DTO classes. The input carries only client-settable fields.
- **Why:** A shared class either exposes server-assigned fields (`id`, `createdAt`) as client-writable, or litters the model with `Optional` fields that are only optional in one direction. Two classes make the contract unambiguous.

```python
class InputSalesItem(BaseModel):       # what a client may send
    name: str = Field(max_length=256)
    price_in_cents: int

class OutputSalesItem(BaseModel):      # adds server-assigned fields
    id: str
    created_at_ms: int
    name: str = Field(max_length=256)
    price_in_cents: int
```

- **Anti-slop:** One `SalesItem(BaseModel)` reused as request body and response, with `id: int | None = None` so the same class can pretend to be both.
- **See also:** `examples/api-design-principles/dtos.py` and fluent-python ch05 (dataclasses) / ch15 (advanced typing).

### Validate every field at the boundary, output included

- **Rule:** Constrain every DTO field. Cap the length of every `str` and every `list`, on output as well as input.
- **Why:** An unbounded `name` or a 10_000-element `images` list is a memory/DoS vector. Output validation catches a corrupted row before it reshapes the response (an injection/exfiltration guard).
- **Python:** `Field(max_length=...)` on strings and lists, `ge=`/`le=` on numbers, `HttpUrl`/`EmailStr` for formats. pydantic validates at construction, so the controller body stays empty.
- **Anti-slop:** `name: str` with no bound, validating the request but returning `response_model=dict`, assuming the database can only contain valid data.
- **See also:** `examples/api-design-principles/dtos.py`

### Keep the web framework out of the core

- **Rule:** Import FastAPI/Strawberry only in controllers. The service and repository know nothing about HTTP.
- **Why:** If business logic raises `HTTPException` or types its returns as `Response`, you cannot reuse it behind GraphQL/gRPC and cannot migrate frameworks without rewriting the core. The dependency must point web → service → repository.
- **Python:** Controller calls `service.get(id)`. The service raises `EntityNotFoundError` (a plain domain exception). The controller's framework boundary turns it into a response.
- **Anti-slop:** `raise HTTPException(404)` inside a service method, returning `JSONResponse` from a repository, importing `fastapi` in a file under `service/` or `repositories/`.
- **See also:** `examples/api-design-principles/rest_controller.py`, `errors.py`

### Raise domain errors, map them to HTTP at one boundary

- **Rule:** Define a base `ApiError` carrying status + machine `code` + message + `cause`. Register one handler that maps any `ApiError` to the shared envelope.
- **Why:** Per-endpoint try/except produces inconsistent responses and scatters logging/metrics. One boundary gives every endpoint the same envelope, one place to log `cause`, one place to bump a failure counter labelled by `code`.

```python
@app.exception_handler(ApiError)
def handle_api_error(_req: Request, error: ApiError) -> JSONResponse:
    return JSONResponse(error.status_code, content=to_error_envelope(error))
```

- **Python:** GraphQL has no per-error HTTP status (always 200), so map the same `ApiError` into the response `errors[].extensions` via an error formatter, same hierarchy, different boundary.
- **See also:** `examples/api-design-principles/errors.py`, `rest_controller.py`

### Hide internals in error responses

- **Rule:** Return a stable `errorCode` and human message. Include a stack trace only outside production.
- **Why:** A stack trace or raw exception string in a prod response leaks file paths, library versions, and query structure to attackers. The `errorCode` is the contract clients branch on and the label metrics aggregate by. Keep its wording frozen.

```python
def stack_trace_of(error: Exception | None) -> str | None:
    if error is None or os.environ.get("ENV") == "production":
        return None
    return "".join(traceback.format_exception(error))
```

- **Anti-slop:** `{"detail": str(exc)}` returned to the client, changing `errorCode` text and breaking client branching, logging nothing because the message was already returned.
- **See also:** `examples/api-design-principles/errors.py`

### Depend on a repository abstraction

- **Rule:** Define the repository as a `Protocol`. Inject the concrete (SQL/ORM/Mongo) implementation. Return domain entities.
- **Why:** The service coupling to a `Protocol` (not a concrete class) lets you swap storage engines and unit-test with a fake. No database in tests. Returning entities (not DTOs, not raw rows) keeps the boundary mapping explicit.

```python
class SalesItemRepository(Protocol):
    def save(self, item: InputSalesItem) -> SalesItem: ...
    def find(self, item_id: str) -> SalesItem | None: ...
```

- **Anti-slop:** Service instantiates `SqliteRepository()` directly, repository returns `OutputSalesItem` (a wire DTO) or `sqlite3.Row`, "interface" is a concrete base class with real query code.
- **See also:** `examples/api-design-principles/repository.py` and fluent-python ch13 (Protocols/ABCs).

### Parameterize all SQL, allow-list identifiers

- **Rule:** Bind values with placeholders. For column names you must interpolate (`fields`, `sort-by`), validate against a fixed allow-list.
- **Why:** Query/filter/sort parameters arrive from the client. String-built SQL is a direct injection path. Values can be parameterized. Identifiers cannot, so they need an allow-list. There is no safe interpolation of arbitrary client text.

```python
# ✗ injection: client controls the value AND the column
cur.execute(f"SELECT * FROM items WHERE name = '{name}' ORDER BY {sort}")

# ✓ value bound, sort key selects a PRE-WRITTEN static query (no client
#   text touches SQL at all, safer than allow-list + f-string)
query = _SELECT_BY_SORT_KEY.get(sort_by, _SELECT_BY_SORT_KEY["created_at_ms"])
cur.execute(query, (min(limit, 100),))
```

- **Anti-slop:** f-string-built `WHERE`, trusting `sort-by`/`fields` because "it's just a column name", uncapped `limit` letting a client pull the whole table.
- **See also:** `examples/api-design-principles/repository.py` and databases-and-database-principles examples.

### Make DELETE idempotent

- **Rule:** Deleting an already-absent resource succeeds with 204. Never 404.
- **Why:** Clients retry on timeout. If the first DELETE succeeded but the response was lost, the retry must not error. The desired end state (gone) is achieved either way.
- **Python:** Repository `delete` is a no-op when the id is absent. Controller still returns 204.
- **Anti-slop:** Raising `EntityNotFoundError` from `delete` so a retried DELETE returns 404 and confuses idempotent clients.
- **See also:** `examples/api-design-principles/repository.py`, `rest_controller.py`

### Prevent duplicate creates

- **Rule:** Enforce uniqueness on a natural key (e.g. email as a unique column), or require a client-supplied `creationUuid` checked server-side.
- **Why:** A create can succeed on the server while the client times out. The retried request would otherwise insert a second copy with a new id. A unique constraint or idempotency key makes the retry safe.
- **Python:** `UNIQUE` column for natural keys, otherwise store and check the `creationUuid` before insert, returning the existing resource on a repeat.
- **Anti-slop:** Treating POST as if networks never drop responses, assuming "the client will dedupe."

### Cross-cutting concerns are decorators

- **Rule:** Implement audit logging, metrics, and authorization as general-purpose decorators wrapping handlers.
- **Why:** Inlined cross-cutting code buries the one business call in boilerplate and drifts between endpoints. A decorator written once applies uniformly and keeps handlers one line.

```python
@allow_for_roles({"admin"})
@audit_log
@increment_counter(attempts)
def create_sales_item(item: InputSalesItem, *, request: RequestInfo) -> ...:
    return service.create(item)
```

- **Python:** `functools.wraps` preserves the signature so FastAPI's introspection/OpenAPI still works. Pass a small `RequestInfo` rather than the framework request object to keep decorators framework-neutral.
- **Anti-slop:** Copy-pasted `logger.info(...)` / `counter.inc()` lines in every endpoint, a decorator that hardcodes sales-item specifics and so can't be reused.
- **See also:** `examples/api-design-principles/cross_cutting_decorators.py` and fluent-python ch09 (decorators & closures).

### Version in the URL path

- **Rule:** Introduce breaking changes under a new path segment (`/v2/...`). Prefer additive, backward-compatible changes.
- **Why:** Existing clients keep calling `/v1` while new ones adopt `/v2`. Mutating a live endpoint's contract breaks deployed clients you do not control.
- **Anti-slop:** Silently adding a required field to an existing endpoint, versioning via undocumented header magic when a path segment is clearer.

### camelCase on the wire, snake_case in Python

- **Rule:** Expose camelCase JSON (the API de-facto standard) while keeping snake_case Python names.
- **Why:** camelCase is what JS/mobile clients expect, and it hides that the backend is Python. Renaming Python identifiers to camelCase to "match" the JSON fights PEP 8 and pollutes the core.
- **Python:** pydantic `Field(alias="priceInCents")` with `populate_by_name=True`, or a model-wide `alias_generator`, and dump with `by_alias=True`.
- **Anti-slop:** `priceInCents: int` as the actual Python attribute name throughout the codebase, or leaking snake_case keys into the public JSON contract.
- **See also:** `examples/api-design-principles/dtos.py`

## Anti-slop checklist

- Verb-in-path "REST" endpoints (`/get-x`, `/delete-x`) instead of noun + HTTP method.
- 200 for everything, 200 on create instead of 201, 404 on DELETE of an absent resource.
- One DTO class reused for request and response, with `id: int | None` to bridge both.
- Unbounded `str`/`list` DTO fields, validating input but not output.
- `raise HTTPException(...)` or `return JSONResponse(...)` inside a service/repository.
- `importing fastapi` (or any web framework) in a `service/` or `repositories/` module.
- Per-endpoint try/except with ad-hoc error JSON instead of one `ApiError` handler + shared envelope.
- `str(exception)` or a stack trace returned to clients in production.
- f-string-built SQL, trusting `sort-by`/`fields`/`limit` from the client without allow-list + cap.
- Service constructing its repository directly instead of receiving an injected `Protocol`.
- Copy-pasted logging/metrics/authz in handlers instead of `functools.wraps`-based decorators.
- Treating POST as inherently safe to retry (no idempotency key, no unique constraint).
- Mutating a live endpoint's contract instead of adding a `/v2` path.
- Renaming Python attributes to camelCase to match JSON instead of using pydantic aliases.

## Bundled examples

| File | Principle(s) demonstrated |
|---|---|
| `examples/api-design-principles/dtos.py` | Input/output DTO split, validate-at-boundary incl. output, DTO (pydantic) vs entity (dataclass), camelCase aliasing |
| `examples/api-design-principles/errors.py` | Framework-agnostic `ApiError` hierarchy, stable `errorCode`, consistent envelope, no stack trace in prod |
| `examples/api-design-principles/repository.py` | Repository `Protocol` + injected impl, parameterized SQL, allow-listed sort column, capped limit, idempotent delete |
| `examples/api-design-principles/rest_controller.py` | Thin controller, noun/verb routing + status codes, DI composition root, single error-to-HTTP boundary, web→service→repo direction |
| `examples/api-design-principles/cross_cutting_decorators.py` | Audit/metrics/authz as reusable decorators, `functools.wraps`, framework-neutral `RequestInfo` |
