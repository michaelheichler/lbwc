# ch02: Tactical Domain-Driven Design (sub-reference)

> When this governs: implementing a single bounded context (microservice), modeling entities/value objects/aggregates, and laying out repositories, services, and controllers. Linked from [`ch02-object-oriented-design-principles.md`](ch02-object-oriented-design-principles.md) ("Tactical DDD" + "Clean microservice design").

Strategic DDD splits a system into subdomains/bounded contexts. **Tactical** DDD implements one context: code structure and every name (class, method, variable) must match the domain's *ubiquitous language*. In a payment service you write `Account`, `withdraw`, `deposit`, `make_payment`, not `DataManager.process()`.

## Building-block index

- **Entity**, domain object *with identity* (an id). Mutable. Behavior operates on its own state.
- **Value object**, domain object *without identity*, compared by value, immutable.
- **Aggregate**, an entity composed of child entities and value objects.
- **Aggregate root**, the aggregate's single entry point. Protects invariants. Acts as a facade.
- **Factory**, creates domain objects (see `ch02-design-patterns.md`).
- **Repository**, persists/retrieves aggregate roots, one per aggregate root.
- **Service**, implements use cases, orchestrates operations on aggregate roots.
- **Event**, an operation forming a use case (create/update/cancel an order).
- **Actor**, who issues a command (an end-user, or a service).

## The building blocks in Python

### Entity vs value object
- **Entity:** identity matters, so `@dataclass(slots=True)` (mutable) with an `id`. Equality is by id, not by field values.
- **Value object:** no identity, so `@dataclass(frozen=True, slots=True)`. Equality and hashing come free and it can't be mutated.
```python
@dataclass(frozen=True, slots=True)
class Money:               # value object
    cents: int
    currency: str = "EUR"

@dataclass(slots=True)
class OrderItem:           # entity (identity = (order_id, id))
    id: int
    sales_item_id: int
    quantity: int
    unit_price: Money
```
- **See also:** `examples/object-oriented-design-principles/orderservice/entities.py`, fluent-python ch05 (dataclasses), ch11 (`__slots__`).

### Aggregate root protects invariants
- **Rule:** all reads/writes go through the root. Never touch child entities directly. The root is a facade (Law of Demeter) and the guardian of invariants (e.g. `total == sum of line totals`).
- **Why:** if any service could append order items directly, the invariant could break and distributed transactions would scatter. One root = one transactional boundary.
```python
@dataclass(slots=True)
class Order:               # aggregate root
    id: int
    user_id: int
    _items: list[OrderItem] = field(default_factory=list)

    def add_item(self, item: OrderItem) -> None:   # tell the root
        self._items.append(item)

    def total(self) -> Money:
        running = Money(0)
        for item in self._items:
            running += item.line_total()
        return running

    @property
    def items(self) -> tuple[OrderItem, ...]:      # read-only view
        return tuple(self._items)
```
- **Anti-slop:** never expose or return the live `_items` list. Never compute the total in a service by reaching into items (feature envy).

### Repository
- **Rule:** a `Protocol` named for the aggregate (`OrderRepository`), abstract over storage. One implementation per backend (SQL, Mongo, file, in-memory).
- **Why:** the word *repository* says nothing about a database. The service depends only on the protocol, so switching storage adds a class (open/closed + dependency inversion).
```python
class OrderRepository(Protocol):
    def save(self, order: Order) -> Order: ...
    def find(self, order_id: int) -> Order | None: ...
```
- **See also:** `orderservice/repository.py`.

### Service (use case)
- **Rule:** one method per use case (per domain event). Orchestrate aggregate roots. Depend on the repository protocol via constructor injection.
- **Why:** services hold logic that isn't on a single entity, and being protocol-injected makes them unit-testable with a fake repo and storage-agnostic in production.
```python
class OrderServiceImpl:
    def __init__(self, repository: OrderRepository) -> None:
        self._repository = repository           # injected protocol

    def create_order(self, input_order: InputOrder) -> OutputOrder: ...
    def get_order(self, order_id: int) -> OutputOrder: ...
```
- **See also:** `orderservice/service.py`.

### DTOs at the boundary
- DTOs (input/output) decouple the wire shape from entities and are the **only** behaviorless data classes the *program against interfaces* rule exempts. Define ids as strings on DTOs so 64-bit ids survive JavaScript clients.
- **See also:** `orderservice/dtos.py`.

## Clean microservice layering

```
client → controller (input adapter) → service (use case) → repository (output adapter) → entities (core)
              REST/GraphQL/CLI              one method/event        SQL/Mongo/memory        domain
```
- Dependency arrows point **inward**. Every layer depends on the next layer's **protocol**, never its concrete class.
- The volatile parts (API tech, DB) live at the edge. The stable parts (entities) live at the centre, so outer change never forces a core edit.
- The **composition root** (`container.py` / `DiContainer`) is the only place concrete classes are named.
- The same principle applies to non-API services (e.g. a data-exporter pipeline: consume → decode → transform → encode → produce), where each consumer/decoder/encoder/producer is an interface adapter.
- **See also:** `examples/object-oriented-design-principles/orderservice/` (runnable: `python -m orderservice.app`).

## Event storming (discovery)

Lightweight team workshop to surface the building blocks, in order:
1. **Domain events** (past tense): *order was created*, *message was consumed*.
2. **Commands** that cause each event: *create order*, *consume message*.
3. **Actors/services** that execute commands.
4. **Entities/value objects/aggregates** the commands touch.

This is object-oriented analysis: commands become service methods, actors/services become singletons, entities/value objects become classes. Group related notes (actor + command + entity) per event. The output is an initial class diagram you then refine with dependency inversion.

## Anti-slop checklist (tactical DDD)

- Don't model a value object as a mutable class. Freeze it (no identity ⇒ no setters).
- Don't give an entity value-based equality, and don't give a value object an id.
- Don't let a service (or any outside object) mutate child entities directly. Go through the aggregate root.
- Don't return the live internal collection from an aggregate. Return a copy or read-only view.
- Don't make the repository protocol mention SQL/Mongo. Keep it storage-neutral.
- Don't let a service import a concrete DB driver or a controller import business rules. Depend on protocols.
- Don't name classes generically (`Manager`, `Helper`, `DataProcessor`). Use the domain's ubiquitous language.
- Don't scatter the composition wiring. Concentrate concrete-class selection in one root.
