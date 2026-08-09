# ch07, Databases and Database Principles

> When this governs: any time Python code reads from or writes to a database (picking a store, declaring schema/entities, writing queries, managing transactions and connections, or caching) across SQL (relational), document, key-value, wide-column, and search-engine backends.

## Principle index

- **Match store to access pattern.** Choose relational when requirements are unknown. Specialize only with reason.
- **Prefer an ORM.** Map rows to objects, get parameterization and serialization for free.
- **Parameterize every query.** Bind values. Never f-string user data into SQL.
- **Allow-list non-bindable SQL parts.** Map client-chosen columns/sort to fixed identifiers, never raw text.
- **Repository pattern.** Hide the store behind a Protocol that traffics in domain objects.
- **Translate driver errors at the boundary.** Wrap `SQLAlchemyError`/driver errors in domain errors.
- **One transaction per operation.** Use a unit-of-work context manager. Commit once or roll back all.
- **Avoid N+1 queries.** Eager-load relationships instead of lazy-loading in a loop.
- **Index the columns you filter and sort on.** Unindexed WHERE/ORDER BY forces full table scans.
- **Pool connections and build the engine once.** Reuse a singleton engine, never connect per request.
- **Config from the environment.** Read `DATABASE_URL` from env. Never hard-code credentials.
- **Normalize relational schemas (1NF/2NF/3NF).** Atomic cells, full-key and non-transitive dependencies.
- **Design wide-column tables query-first.** One table per query, partition key always in the WHERE.
- **Cache with a key-value store and a TTL.** Read-through cache. Every entry must expire.
- **Keep cross-aggregate relations out of one service.** No foreign keys spanning microservice boundaries.

## Principles

### Match store to access pattern
- **Rule:** Default to a relational database. Reach for NoSQL only when a concrete access pattern demands it.
- **Why:** Relational engines handle ad-hoc joins and unforeseen queries. Picking a specialized store early locks you into its query shape. Document stores fit whole-document read/write, key-value fits keyed real-time lookups, wide-column fits known high-volume queries, search engines fit free-text. Choosing wrong means rewriting the data layer when requirements shift.
- **Python:** Selection is a design decision, not code. The rest of this reference assumes the store is chosen. See the wide-column and cache principles for the specialized cases.
- **Anti-slop:** Don't reach for MongoDB/Redis by reflex when the data is relational and the queries are unknown.

### Prefer an ORM
- **Rule:** Use an ORM (SQLAlchemy) to map rows to typed objects and to parameterize SQL automatically.
- **Why:** The ORM generates parameterized SQL (no injection), maps rows to objects you can serialize to JSON, and creates tables from entity definitions. Hand-written SQL is error-prone and re-implements all of this.
- **Python:**
  ```python
  from sqlalchemy import String
  from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

  class Base(DeclarativeBase): ...

  class SalesItem(Base):
      __tablename__ = "sales_items"  # plural table, singular entity
      id: Mapped[int] = mapped_column(primary_key=True)  # always a PK
      name: Mapped[str] = mapped_column(String(256))
      price_in_cents: Mapped[int] = mapped_column(index=True)  # filtered -> index
      description: Mapped[str | None] = mapped_column(String(1024))  # nullable
  ```
  Use `Mapped[str | None]` for nullable columns and modern `Mapped[]` typing, not the legacy `Column(...)` form.
- **See also:** `examples/databases-and-database-principles/repository_pattern.py`, fluent-python ch05 (dataclasses for DTOs), ch11 (Pythonic object design).

### Parameterize every query
- **Rule:** Pass values as bound parameters via `execute(sql, params)` or the expression language. Never interpolate them.
- **Why:** Building a SQL string by splicing in user data is the canonical SQL-injection vector. A `name` of `x' OR '1'='1` turns an equality predicate into a tautology that dumps the table. Bound parameters travel separately from the statement and cannot change its structure.
- **Python:**
  ```python
  # ✗ NEVER: place a value into the SQL text via f-string / % / .format() / +
  #          (the value can rewrite the statement -> injection)
  # ✓ DB-API: placeholder in the SQL, value in a params tuple
  cursor.execute("SELECT id FROM sales_items WHERE name = ?", (name,))   # sqlite
  cursor.execute("SELECT id FROM sales_items WHERE name = %s", (name,))  # mysql/psycopg
  # ✓ SQLAlchemy Core: comparison compiles to a bound parameter
  select(sales_items).where(sales_items.c.name == name)
  ```
  For a variable-length `IN`, use `.in_(ids)` (Core) or generate one placeholder per id and bind the tuple. Never join the values themselves.
- **Anti-slop:** Refuse to assemble SQL with f-strings/`%`/`.format()`/`+` around any value. Static scanners flag it even when "it's just a constant".
- **See also:** `examples/databases-and-database-principles/parameterized_queries.py`.

### Allow-list non-bindable SQL parts
- **Rule:** Column names, sort direction, and `LIMIT`/`OFFSET` can't be bound. Map the client's choice to a fixed, developer-defined value or raise.
- **Why:** Placeholders only work for values, not identifiers. Concatenating a client-supplied column name (even after a charset check) still lets through valid-but-unintended columns (e.g. `password_hash`) and injection in dialects with quoting quirks. A dict lookup that returns a real `Column` (or a pre-written clause) admits exactly the intended set.
- **Python:**
  ```python
  _SORTABLE: dict[str, Column[object]] = {
      "id": t.c.id, "name": t.c.name, "price_in_cents": t.c.price_in_cents,
  }
  def order_by(column_key: str):
      column = _SORTABLE.get(column_key)
      if column is None:
          raise InvalidSortError(column_key)  # off the map -> rejected
      return column
  ```
  Validate `LIMIT`/`OFFSET` as integers in a bounded range. Never let a client pass an arbitrary huge value.
- **Anti-slop:** A regex like `^[A-Za-z0-9_]+$` is NOT a substitute for an allow-list of actual column names.
- **See also:** `examples/databases-and-database-principles/parameterized_queries.py`.

### Repository pattern
- **Rule:** Put all persistence behind a repository class that accepts and returns domain objects, fronted by a `Protocol`.
- **Why:** Domain/business code that imports SQLAlchemy (or PyMongo) is welded to that engine. Swapping or testing it means touching every caller. A repository confines the engine to one class, lets you supply an in-memory fake in tests, and keeps cursors/rows from leaking upward.
- **Python:**
  ```python
  class SalesItemRepository(Protocol):
      def save(self, item: NewSalesItem) -> SalesItem: ...
      def find(self, item_id: int) -> SalesItem | None: ...
      def find_all(self) -> list[SalesItem]: ...
      def delete(self, item_id: int) -> None: ...
  ```
  Concrete `OrmSalesItemRepository` / `MongoDbSalesItemRepository` satisfy it structurally. The domain depends only on the Protocol. Return a domain `SalesItem` dataclass, not a `SalesItemRow` ORM instance.
- **Anti-slop:** Don't return ORM-mapped instances or `dict` rows from repository methods, and don't import the driver in service/handler code.
- **See also:** `examples/databases-and-database-principles/repository_pattern.py`, fluent-python ch13 (Protocols vs ABCs), ch08 (typing the seam).

### Translate driver errors at the boundary
- **Rule:** Catch `SQLAlchemyError`/`PyMongoError`/DB-API `Error` inside the repository and re-raise a domain error.
- **Why:** Letting driver exceptions propagate couples upper layers to the storage technology and leaks connection details into logs/responses. A `DatabaseError`/`EntityNotFoundError` gives callers a stable contract regardless of backend.
- **Python:**
  ```python
  try:
      with self._session_factory() as session:
          session.add(row); session.commit(); session.refresh(row)
          return self._to_entity(row)
  except SQLAlchemyError as error:
      raise RepositoryError("save failed") from error  # chain with `from`
  ```
  Use `raise ... from error` so the original cause is preserved for debugging.
- **Anti-slop:** Don't `except Exception: pass` around DB calls, and don't let a bare `SQLAlchemyError` escape the repository.

### One transaction per operation
- **Rule:** Wrap all writes of a single business operation in one transaction via a unit-of-work context manager. Commit once at the end or roll back everything.
- **Why:** Multiple independent commits can leave the database in a half-applied state (money debited, never credited, or order saved, items lost). A context manager guarantees commit-on-success and rollback-on-exception without try/except/finally at every call site.
- **Python:**
  ```python
  def transfer(uow: UnitOfWork, src: int, dst: int, cents: int) -> None:
      with uow as u:                       # __enter__ opens the transaction
          source, target = fetch_locked(u.session, src, dst)
          if source.balance_in_cents < cents:
              raise InsufficientFundsError(src)  # escapes -> __exit__ rolls back
          source.balance_in_cents -= cents
          target.balance_in_cents += cents
      # __exit__ commits iff no exception escaped, no manual commit() in the body
  ```
- **Anti-slop:** Don't call `session.commit()` after each write inside one logical operation. Don't forget rollback on the error path.
- **See also:** `examples/databases-and-database-principles/unit_of_work.py`, fluent-python ch18 (context managers, `__enter__`/`__exit__`).

### Avoid N+1 queries
- **Rule:** When you read parents and then their children, eager-load the relationship instead of touching it lazily in a loop.
- **Why:** Lazy loading fires one query for the parents plus one per parent for its children (N+1 round trips that dominate latency as N grows). Eager loading (`selectinload` for one-to-many, `joined`/`lazy='joined'` for many-to-one) fetches everything in one or two queries.
- **Python:**
  ```python
  # ✗ N+1: each order.items access is a separate SELECT
  for order in session.scalars(select(Order)).all():
      process(order.items)
  # ✓ 2 queries total regardless of N
  stmt = select(Order).options(selectinload(Order.items))
  for order in session.scalars(stmt).all():
      process(order.items)  # already in memory
  ```
  Turn on `echo=True` while developing to count the statements you actually emit.
- **Anti-slop:** Don't iterate a query result and dereference a relationship per row without an eager-load option.
- **See also:** `examples/databases-and-database-principles/avoid_n_plus_one.py`.

### Index the columns you filter and sort on
- **Rule:** Add an index to any column that regularly appears in a WHERE, JOIN, or ORDER BY (beyond the primary key).
- **Why:** A query whose predicate isn't on an indexed column forces a full table scan (fine on 100 rows, fatal on 10 million). The fix is `index=True` on the mapped column (or `create_index` for document stores).
- **Python:**
  ```python
  price_in_cents: Mapped[int] = mapped_column(index=True)  # WHERE price < ?
  # MongoDB equivalent for a frequently-filtered field:
  collection.create_index([("category", 1), ("average_rating", -1)])
  ```
  Index compound queries in the order they're filtered/sorted (here: filter `category`, then sort `average_rating` desc).
- **Anti-slop:** Don't index every column (writes slow down, storage grows). Index the ones queries actually use.

### Pool connections and build the engine once
- **Rule:** Create one pooled engine per process and reuse it. Never open a new connection or engine per request.
- **Why:** TCP + auth handshakes are expensive, and the database has a hard connection cap. Per-request connections exhaust it under load and add latency. A pooled engine hands out and recycles a bounded set of connections.
- **Python:**
  ```python
  @lru_cache(maxsize=1)               # lazy singleton: one engine per process
  def get_engine() -> Engine:
      return create_engine(
          database_url(),
          pool_size=10, max_overflow=5,   # QueuePool tuning (networked DBs)
          pool_pre_ping=True,             # drop dead connections silently
          pool_recycle=1800,              # recycle before the server times them out
      )
  ```
  Note SQLite uses a single-thread pool that rejects `pool_size`/`max_overflow`. Gate those args on a non-sqlite scheme.
- **Anti-slop:** Don't call `create_engine`/`connect` inside a request handler or repository method. Build the engine at startup.
- **See also:** `examples/databases-and-database-principles/connection_url_from_env.py`.

### Config from the environment
- **Rule:** Read the database URL/credentials from environment variables. Parse the URL with `urllib.parse`, not `str.split` chains.
- **Why:** Hard-coded hosts/passwords leak through version control and can't differ per environment. Hand-rolled `split('@')[0].split(':')` parsing breaks on `@`/`:` inside a password. `urlparse` handles escaping, ports, and missing parts correctly.
- **Python:**
  ```python
  url = os.environ.get("DATABASE_URL")
  if not url:
      raise MissingDatabaseUrlError("DATABASE_URL is not set")  # fail fast at boot
  parts = urlparse(url)   # .hostname .port .username .password .path
  ```
  Fail fast at startup if the variable is missing, rather than at the first query. Never log `parts.password`.
- **Anti-slop:** Don't default credentials in code, and don't parse a connection URL by splitting on `/`, `@`, `:` manually.
- **See also:** `examples/databases-and-database-principles/connection_url_from_env.py`.

### Normalize relational schemas (1NF/2NF/3NF)
- **Rule:** 1NF, one atomic value per cell. 2NF, every non-key column depends on the whole composite key. 3NF, no non-key column depends on another non-key column.
- **Why:** Denormalized schemas create update anomalies: a list packed into one cell can't be indexed or joined. A column that depends on part of the key or on another non-key column gets out of sync when its source changes.
- **Python:** (entity-level expression of the rules)
  ```python
  # ✗ 1NF: tags = "power,cordless,sale"  -> can't index/filter a single tag
  # ✓ 1NF: a ProductTag child row per tag
  # ✗ 3NF: Product.discount when discount is determined by category
  # ✓ 3NF: discount on Category, Product holds category_id (FK) only
  category_id: Mapped[int] = mapped_column(ForeignKey("categories.id"))
  ```
  For 2NF, a column like `order_state` that depends only on `order_id` (part of a `(order_id, line_no)` key) belongs on the `orders` table, not `order_lines`.
- **Anti-slop:** Don't store CSV/JSON-in-a-string for what is really a one-to-many relationship. Don't duplicate a derived attribute across rows.
- **See also:** `examples/databases-and-database-principles/normalization.py`.

### Design wide-column tables query-first
- **Rule:** In Cassandra-style stores, model one table per query, put the partition key in every WHERE, and duplicate data freely.
- **Why:** Wide-column engines have no joins and scan the whole cluster if the partition key is absent. You optimize for known queries by shaping a table per query. Clustering columns give you the sort order for free. Duplication is the accepted trade for fast, scalable reads.
- **Python:** Schema/CQL is the artifact, not Python. The discipline: identify each query first, then create a table whose primary key is `(partition_key, clustering_cols...)` matching that query's WHERE and ORDER BY. A second query against the same data => a second table.
- **Anti-slop:** Don't model a wide-column store like a relational one (no joins, no querying without the partition key, no ad-hoc filters).

### Cache with a key-value store and a TTL
- **Rule:** Use a key-value store (Redis) as a read-through cache and set an expiry on every entry.
- **Why:** A cache speeds repeated reads of slow queries, but an entry with no TTL is both a memory leak and a permanent staleness bug. A required TTL makes stale data self-heal and bounds memory.
- **Python:**
  ```python
  def get_cached_json[T](cache, key: str, loader: Callable[[], T], ttl_seconds: int) -> T:
      cached = cache.get(key)
      if cached is not None:
          return json.loads(cached)
      value = loader()
      cache.set(key, json.dumps(value), ex=ttl_seconds)  # TTL is required, not optional
      return value
  ```
  Cache serialized values (JSON), not connections or ORM objects.
- **Anti-slop:** Don't `set` a cache key without an expiry. Don't cache mutable objects you'll mutate elsewhere.
- **See also:** `examples/databases-and-database-principles/cache_aside.py`, fluent-python ch08 (typing the store as a Protocol).

### Keep cross-aggregate relations out of one service
- **Rule:** Don't create database-level foreign keys or many-to-many tables that span microservice boundaries.
- **Why:** A foreign key between two services' tables couples their schemas and deployments. Store only the other side's id (e.g. `sales_item_id` as a plain column, not a FK to a table in another service) and resolve it via that service's API.
- **Python:**
  ```python
  # within order-service: a reference, not a foreign key into another DB
  sales_item_id: Mapped[int] = mapped_column(BigInteger())  # not ForeignKey(...)
  ```
- **Anti-slop:** Don't add a `ForeignKey` pointing at a table owned by a different service/database.

## Anti-slop checklist

- Never assemble SQL with f-strings, `%`, `.format()`, or `+` around a value. Bind it or use the expression language.
- Never concatenate a client-supplied identifier (column, sort dir) into SQL. Map it through an allow-list to a fixed value.
- A `^[A-Za-z0-9_]+$` charset check is not an allow-list. Enumerate the actual permitted columns.
- Don't return ORM rows, cursors, or raw dicts from a repository. Return domain dataclasses.
- Don't import the DB driver (SQLAlchemy/PyMongo/mysql-connector) in service, handler, or domain code.
- Don't let `SQLAlchemyError`/driver exceptions escape the repository. Wrap and chain with `raise ... from`.
- Don't `commit()` after each write in one logical operation. One transaction, one commit, rollback on error.
- Don't dereference a relationship per row in a loop (N+1). Use `selectinload`/`joined`.
- Don't call `create_engine`/`connect` per request. One pooled engine per process behind `@lru_cache`.
- Don't hard-code DB credentials or parse a connection URL with `str.split`. Read env, parse with `urlparse`.
- Don't `set` a cache entry without a TTL.
- Don't store a list/CSV/JSON-string where a one-to-many child table belongs (1NF).
- Don't add foreign keys that cross microservice/database boundaries.
- Don't reflexively choose NoSQL when the data is relational and future queries are unknown.

## Bundled examples

| File | Principle demonstrated |
| --- | --- |
| `repository_pattern.py` | Repository pattern, translate driver errors, ORM entity vs domain DTO |
| `parameterized_queries.py` | Parameterize every query, allow-list non-bindable SQL parts |
| `unit_of_work.py` | One transaction per operation via a context manager (commit/rollback) |
| `avoid_n_plus_one.py` | Eager loading to avoid the N+1 query problem |
| `connection_url_from_env.py` | Pooled singleton engine, config + URL parsing from the environment |
| `cache_aside.py` | Read-through key-value cache with a required TTL |
| `normalization.py` | 1NF/2NF/3NF expressed as entity/relationship design |
