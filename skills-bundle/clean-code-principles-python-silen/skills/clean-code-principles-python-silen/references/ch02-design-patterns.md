# ch02: Design Patterns (sub-reference)

> When this governs: choosing a pattern to add behavior without editing working code, and applying it the Pythonic way. Linked from [`ch02-object-oriented-design-principles.md`](ch02-object-oriented-design-principles.md) ("Use the design patterns").

Patterns are the concrete mechanics of *open/closed* and *composition over inheritance*. Apply them to extend by adding classes. Two cross-cutting rules:
- **Don't name classes after patterns**, `CachingDataStore`, not `CachingDataStoreProxy`. A seasoned reader infers the pattern from the structure.
- **In Python, a function or module often replaces a pattern.** Strategy can be a plain callable. Singleton is a module-level instance. Iterator is a generator. Reach for a class only when state or a richer contract justifies it.

## Pattern index

**Creational**, factory · abstract factory · static factory method · builder · singleton · prototype · object pool
**Structural**, composite · facade · bridge · strategy · adapter · proxy · decorator · flyweight
**Behavioral**, chain of responsibility · observer · command · iterator · state · mediator · template method · memento · visitor · null object

## Creational

### Factory / Abstract factory
- **Use when:** the concrete type to create is decided at runtime (config, input format).
- **Pythonic form:** abstract factory = a `Protocol` with a `create` method + concrete factory classes, and inject the factory via DI. The factory body is the one acceptable place for a long `match` over a type enum, guarded with a `case _: raise ValueError`.
- **Why over plain factory:** the abstract version is mockable in tests and swappable by DI. Prefer it.
```python
class ConfigParserFactory(Protocol):
    def create(self, fmt: ConfigFormat) -> ConfigParser: ...
```
- **See also:** `examples/object-oriented-design-principles/design_patterns_creational.py`.

### Static factory method
- **Use when:** you need more than one "constructor" (Python allows one `__init__`), or construction can fail. `__init__` cannot return `None` or cleanly signal failure.
- **Pythonic form:** `@classmethod` named constructors (`Money.of`, `HttpUrl.localhost`) plus a `try_create` that raises. Private-constructor metaclass tricks exist but are rarely worth it. A frozen dataclass with classmethods reads better.
- **See also:** `design_patterns_creational.py` (`HttpUrl.try_create`, `HttpUrl.localhost`).

### Builder
- **Use when:** an object has many optional parts with no inherent order (a house: kitchen, bedrooms, garage).
- **Pythonic form:** chained `add_*` methods returning `self`, then `build_*`. Validate in `build`. Raise from `try_build_*`. For ordered/typed params a factory method with defaults or a `@dataclass` params object is usually simpler and shows defaults in the signature.

### Singleton
- **Use when:** exactly one stateless collaborator is needed.
- **Pythonic form:** a module-level instance (importers share it) **or** a DI container's singleton provider (`providers.ThreadSafeSingleton`). Don't hand-roll `__new__`/metaclass singletons. They are hard to mock and easy to get wrong under threads.

### Prototype
- **Use when:** copying an existing configured object is cheaper/clearer than rebuilding it.
- **Pythonic form:** a `clone(...)` method, or `copy.copy` / `copy.deepcopy`. (JS prototypal inheritance is irrelevant to Python. Ignore.)

### Object pool
- **Use when:** many short-lived expensive objects churn the allocator/GC.
- **Pythonic form:** acquire/return methods over a bounded `list`. Clear objects on return (`Clearable` protocol). Measure first. Pooling is an optimization, not a default.

## Structural

### Strategy
- **Use when:** an object's behavior should be swappable at runtime.
- **Pythonic form:** inject a behavior object (or a plain callable) and delegate to it. A default can be set in the signature.
```python
class ConfigReader:
    def __init__(self, parser: ConfigParser | None = None) -> None:
        self._parser = parser or JsonConfigParser()
```
- **See also:** `examples/object-oriented-design-principles/design_patterns_structural.py`, `composition_over_inheritance.py`.

### Adapter
- **Use when:** a 3rd-party/foreign object must satisfy *your* interface.
- **Pythonic form:** wrap the vendor object behind your `Protocol` so the core never imports the vendor type (`KafkaMessage` wraps a raw client message, exposes `data()`/`length()`). This is what makes a clean microservice storage/transport-agnostic.
- **See also:** `design_patterns_structural.py`, `orderservice/repository.py`.

### Decorator
- **Use when:** add cross-cutting behavior (logging, timing, caching) to a method without editing it.
- **Pythonic form:** a class implementing the same protocol that wraps another instance. Stack them (`timing(logging(real))`). For functions, a Python `@decorator` with `functools.wraps` does the same at function granularity.
- **Why:** pure open/closed, the wrapped class is never touched.
- **See also:** `design_patterns_structural.py`, fluent-python ch09 (decorators & closures).

### Composite
- **Use when:** a tree where a node and a leaf share an interface (UI panes containing widgets/panes).
- **Pythonic form:** the container implements the same `Protocol` as its children and recurses on `render`/`size`.

### Facade
- **Use when:** hide a subsystem behind one higher-level object (an aggregate root *is* a facade).
- **Pythonic form:** the facade method orchestrates lower-level objects the caller never sees, directly supports the Law of Demeter.

### Bridge
- **Use when:** decouple an abstraction from its implementation so both vary independently.
- **Pythonic form:** the abstraction holds an implementor object and delegates. The abstraction has little behavior beyond delegation.

### Proxy
- **Use when:** conditionally augment/restrict access to an object (caching, lazy load, an unmodifiable wrapper).
- **Pythonic form:** same protocol as the wrapped object. Intercept selected methods (an `UnmodifiableList` whose mutators raise).

### Flyweight
- **Use when:** many objects share large immutable state. Pool and reuse it.
- **Pythonic form:** intern/cache shared instances (`functools.lru_cache`, a registry dict). An optimization. Measure first.

## Behavioral

### Chain of responsibility
- **Use when:** pass a request along handlers until one handles it (middleware, validators).
- **Pythonic form:** each handler holds the next and either handles or delegates, or a list iterated until handled.

### Observer
- **Use when:** notify subscribers of events on a subject (publish/subscribe).
- **Pythonic form:** subject keeps a list of callbacks/observer objects and calls them on change. Often a plain list of callables suffices.

### Command / Action
- **Use when:** turn an operation into an object to queue, log, undo, or pass for later execution.
- **Pythonic form:** a callable object or closure. First-class functions make this nearly free.
- **See also:** fluent-python ch10 (patterns with first-class functions).

### Iterator
- **Use when:** add traversal to a collection.
- **Pythonic form:** implement `__iter__`/`__next__`, or just write a **generator**, almost always the right Python answer.
- **See also:** fluent-python ch17 (iterators/generators).

### State
- **Use when:** behavior changes with an internal state (a connection: open/closed/error).
- **Pythonic form:** a state object holding behavior. Switch the object to transition. Replaces a sprawling `if state == ...` chain.

### Mediator
- **Use when:** many objects' direct cross-talk creates a coupling mesh. Route it through one mediator.
- **Pythonic form:** components call a mediator that coordinates. Cuts N×N dependencies to N.

### Template method
- **Use when:** a fixed algorithm skeleton with steps subclasses fill in. Lifts duplication across sibling classes.
- **Pythonic form:** a `@final` template method in the base calling `@abstractmethod` hooks. The one place inheritance beats composition: shared mechanics behind an interface.
- **See also:** ch02 main, "Avoid code duplication".

### Memento
- **Use when:** capture/restore an object's internal state (undo) without exposing it.
- **Pythonic form:** the object emits an opaque snapshot object and restores from it.

### Visitor
- **Use when:** add operations to a class hierarchy you can't edit, without modifying it.
- **Pythonic form:** double dispatch via `accept(visitor)`. Python's `functools.singledispatch` is often a lighter alternative.

### Null object
- **Use when:** avoid `None`-checks by supplying a do-nothing implementation of the interface.
- **Pythonic form:** a class whose methods are no-ops (`NullLogger`, `NullXAxisLabelFormatter`), injected where "do nothing" is valid behavior.

## Anti-slop checklist (patterns)

- Don't put the pattern name in the class name (`CachingProxyDataStore` → `CachingDataStore`).
- Don't write a class hierarchy where a generator (iterator), a callable (command/strategy), or a module instance (singleton) is the idiomatic Python form.
- Don't hand-roll a thread-safe singleton with `__new__`. Use a module instance or a DI provider.
- Don't allow a long `match`/`if-elif` over a type outside a factory. Elsewhere it signals missing polymorphism.
- Don't apply a pattern speculatively. Apply it when you actually need to extend without editing.
