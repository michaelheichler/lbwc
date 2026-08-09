# ch02: Object-Oriented Design Principles

> When this governs: designing or reviewing any non-trivial OO Python, class/protocol boundaries, service/repository/controller layering, SOLID, DDD aggregates, dependency wiring, and naming of types and methods.

Two focused sub-references extend this index:
- [`ch02-design-patterns.md`](ch02-design-patterns.md), the 25 GoF-style patterns, Pythonically.
- [`ch02-tactical-ddd.md`](ch02-tactical-ddd.md), entities, value objects, aggregates, repositories, services, event storming.

This skill is the architecture/design layer. For language mechanics (Protocols vs ABCs, dataclasses, dunder methods, decorators) cross-link to **fluent-python**. Do not re-derive them here.

## Principle index

- **Multi-paradigm**, design with OOP, implement methods with pure functions.
- **Single Responsibility (SRP)**, one class = one reason to change, one function = one thing.
- **Open/Closed (OCP)**, add a new class, never edit a working one.
- **Liskov Substitution (LSP)**, a subtype must honor the supertype's full contract.
- **Interface Segregation (ISP)**, split fat protocols into single-capability microprotocols.
- **Dependency Inversion / Program against interfaces**, depend on a `Protocol`, never a concrete class.
- **Clean microservice design**, layer controller → service → repository → entities, arrows inward.
- **Vertical slice design**, one feature per directory so adding a feature adds files, not edits.
- **Class organization**, attributes, then constructor, public, protected, private, accessors last.
- **Uniform naming**, classes end in nouns, capability interfaces end in -able/-ing, no `I` prefix.
- **Encapsulation**, private state, behavior beside data, no auto getters/setters, prefer immutable.
- **Don't leak internal state**, return a copy or read-only view of mutable attributes.
- **Composition over inheritance**, model has-a with injected collaborators, not is-a chains.
- **Tactical DDD**, name code after the domain, mutate aggregates only through their root.
- **Use design patterns**, apply the catalog to stay open/closed, don't name classes after patterns.
- **Don't ask, tell**, tell an object to act, don't pull its state and compute for it.
- **Law of Demeter**, don't call a method on an object returned by another method call.
- **Avoid primitive obsession**, wrap meaningful primitives in semantic value types.
- **Dependency injection**, inject collaborators, name concretes only at the composition root.
- **Avoid duplication**, lift shared code into a base class (often a template method).

## Principles

### Multi-paradigm programming
- **Rule:** Use OOP/DDD to shape classes and interfaces. Implement their methods with pure, side-effect-free functions and immutable data.
- **Why:** Imperative mutation breeds race conditions and bugs you cannot reason about locally. Pure functions are testable and composable. Neither paradigm alone is enough.
- **Python:** A class method built from a comprehension, not an accumulating loop.
  ```python
  # ✓ pure expression inside an OO method
  def doubled_evens(self, numbers: list[int]) -> list[int]:
      return [n * n for n in numbers if n % 2 == 0]
  ```
- **See also:** fluent-python ch07 (first-class functions), ch17 (generators).

### Single Responsibility Principle (SRP)
- **Rule:** A class represents one thing or provides one capability. A function does one thing at one abstraction level.
- **Why:** A class with two reasons to change forces edits for unrelated requirements, multiplying regression risk. The word *and* in a function name is the tell.
- **Python:** Reading config and parsing config are two concerns → two protocols (`ConfigReader`, `ConfigParser`), not one `delete_page_and_all_references` god-function.
- **Anti-slop:** Don't pile `load`, `validate`, `transform`, and `persist` into one `process()` method because it "feels cohesive."
- **See also:** `examples/object-oriented-design-principles/solid_principles.py`.

### Open/Closed Principle (OCP)
- **Rule:** Add behavior by introducing a new class that implements an existing interface. Leave working classes untouched.
- **Why:** Editing a tested class can silently break it (the book's square-from-rectangle bug). New classes carry no such risk.
- **Python:** Need a square? Add a `Square` class implementing `Shape`, do not bolt a `create_square` flag onto `Rectangle`.
  ```python
  class Shape(Protocol):
      def area(self) -> float: ...

  @dataclass(frozen=True, slots=True)
  class Square:          # ✓ extension
      side: float
      def area(self) -> float:
          return self.side ** 2
  ```
- **Anti-slop:** Don't add a boolean constructor flag (`thread_safe=True`) to switch behavior. Make a new class.
- **See also:** `solid_principles.py`, factories/decorators in `ch02-design-patterns.md`.

### Liskov Substitution Principle (LSP)
- **Rule:** Anywhere the base type is accepted, a subtype must work without surprising the caller.
- **Why:** A `Square(Rectangle)` whose width-setter also mutates height breaks `rect.width = 4; rect.height = 5`. Mathematically a square is a rectangle. Behaviorally, with independent setters, it is not.
- **Python:** Either make value objects frozen (no setters to violate) or only *extend* in the override (`super().draw()` then add). Use `@override` (3.12) on intended overrides so a typo is caught.
- **Anti-slop:** Don't subclass to reuse code when the subtype cannot satisfy the parent's contract. Compose instead.
- **See also:** `solid_principles.py`, fluent-python ch14 (inheritance/MRO).

### Interface Segregation Principle (ISP)
- **Rule:** Prefer many single-capability protocols. Build wide interfaces by inheriting microprotocols.
- **Why:** A fat `Automobile` protocol forces a motorcycle to implement `carry_cargo` as a raising stub, a latent `NotImplementedError`. The stdlib does this right: `Sized`, `Iterable`, `Container` compose into `Collection`.
- **Python:**
  ```python
  class Drivable(Protocol):
      def drive(self) -> None: ...
  class CargoCarrying(Protocol):
      def carry_cargo(self, kg: float) -> None: ...
  class Automobile(Drivable, CargoCarrying, Protocol): ...  # composed
  ```
- **See also:** `solid_principles.py`, fluent-python ch13 (Protocols/ABCs).

### Dependency Inversion / Program against interfaces
- **Rule:** High-level code depends on a `Protocol`. Concrete classes depend on the same protocol. Nothing high-level imports a low-level class.
- **Why:** Coupling a `Canvas` to `Circle | Rectangle | Square` means every new shape edits `Canvas`. Depending on `Shape` makes it accept shapes that don't exist yet. Design the interface *first*, then the implementations, never reverse-engineer a fat interface from concrete classes (the `Animal` with `swim`/`fly`/`bark` mistake).
- **Python:** `Application(reader: ConfigReader, parser: ConfigParser)`, constructor takes protocols. The concrete `FileConfigReader` is chosen at the composition root.
- **Anti-slop:** Don't `import` and instantiate a concrete dependency inside a class. Accept it as a parameter.
- **See also:** `solid_principles.py`, `orderservice/`, fluent-python ch08 (Protocol/Callable).

### Clean microservice design
- **Rule:** Separate business core (entities + use cases) from I/O technology (controllers, repositories) using dependency inversion. Arrows point inward.
- **Why:** When REST→GraphQL, SQL→Mongo, or FastAPI→Flask is a new adapter class rather than a core edit, the volatile outer layers never threaten the stable centre.
- **Python:** `controller → service(Protocol) → repository(Protocol) → entities`. The controller knows HTTP. The service knows use cases. The repository knows storage. Entities know only the domain.
- **Anti-slop:** Don't let a service import SQLAlchemy/`requests`, and don't put business rules in a controller.
- **See also:** `examples/object-oriented-design-principles/orderservice/` (runnable), `ch02-tactical-ddd.md`.

### Vertical slice design
- **Rule:** Put each feature in its own directory (`create/`, `get/`, `update/`, `delete/`), optionally grouped by domain.
- **Why:** Adding a feature adds a folder instead of editing shared CRUD classes, so the open/closed principle holds at the feature level and divergent feature requirements don't collide.
- **Python:** `order/create/{CreateOrderService.py, SqlCreateOrderRepository.py, ...}`. Skip it for tiny CRUD APIs where adding a method to a stateless class is already a safe extension.

### Class organization
- **Rule:** Order members: attributes, `__init__`, public methods, protected, private, getters/properties/setters after other public methods, private methods in call order.
- **Why:** A predictable layout means a reader finds the public API immediately and follows private helpers top-down. Order attributes by logic (`width` before `height`, x before y) or alphabetically when neither importance nor logic ranks them.

### Uniform naming
- **Rule:** Classes/entities end in a noun. Capability interfaces end in `-able`/`-ing`. Actor interfaces derive from their verb (`ConfigParser` ↔ `parse_config`). No `I`/Hungarian prefix. Use `Impl` suffix only when needed to disambiguate. `Abstract` prefix for abstract classes.
- **Why:** Consistent names let a reader infer role and contract without opening the file. `Shape` beats `GeometricalShape`. `CachingDataStore` beats `CachingDataStoreProxy` (pattern names add noise).
- **Python:** Boolean methods read as a statement: `is_empty`, `has_error`, `starts_with`, `should_terminate`. Past tense uses `did_` (`did_start_transaction`), never bare past (`started_transaction` reads as a conditional). Drop a redundant action target when the first parameter names it: `parser.try_parse(config_json)` not `try_parse_config(config_json)`. Factory/conversion verbs may be implicit: `Money.of(...)`, `value.to_string()`.
- **Anti-slop:** Don't prefix interfaces with `I`. Don't name a function `do_x_and_y`. Don't write `does_start_with` (use `starts_with`).
- **See also:** function/variable naming in coding-principles (ch03).

### Encapsulation
- **Rule:** Declare state private (`__name`), put behavior next to the data it guards, and add accessors only when genuinely needed, prefer immutable objects.
- **Why:** Python has no access modifiers, so the `__`/`_` convention plus immutability is the only real guard. A class full of getters signals *feature envy*: another object wants your behavior.
- **Python:** `@dataclass(frozen=True, slots=True)` for value types. For entities, expose intent methods (`withdraw`) not raw `set_balance`.
- **Anti-slop:** Don't reflexively generate a getter and setter for every field. Don't expose mutable internal state through a property.
- **See also:** `encapsulation_tell_dont_ask.py`, fluent-python ch11 (`__slots__`), ch22 (properties).

### Don't leak modifiable internal state
- **Rule:** When a method returns a mutable attribute, return a copy or a read-only view, not the live object.
- **Why:** Returning `self.__items` lets the caller `.append(...)` into your aggregate behind your back, breaking invariants. Primitives, strings, and frozen objects are safe to return directly.
- **Python:**
  ```python
  @property
  def items(self) -> tuple[OrderItem, ...]:
      return tuple(self._items)   # ✓ read-only view, not the live list
  ```
- **See also:** `orderservice/entities.py`, fluent-python ch06 (references/copying).

### Composition over inheritance
- **Rule:** Build complex objects from injected collaborators (has-a), not deep is-a hierarchies.
- **Why:** Inheritance encodes every behavior combination as a class (`HatchbackFourWheelDriveAutomaticTransmissionCombustionEngineCar`) and forces base-class spelunking to find behavior. Composition keeps each part single-responsibility and combines N behaviors without N! classes.
- **Python:** `Car(engine: Engine, transmission: Transmission)` delegates to its parts. Supplying behavior objects is the *strategy pattern*.
- **Anti-slop:** Don't reach for a base class to share a few methods. Inject a collaborator. Multiple inheritance / mixins risk method-name clashes. Prefer composition.
- **See also:** `composition_over_inheritance.py`, strategy/factory in `ch02-design-patterns.md`.

### Tactical domain-driven design
- **Rule:** Make code vocabulary match the domain's ubiquitous language. Expose aggregates only through their root.
- **Why:** When the `Order` root owns its `OrderItem`s and all mutation flows through it, invariants (total == sum of lines) cannot be bypassed and distributed transactions stay simple.
- **Python:** `order.add_item(...)` and `order.total()` on the root. Never reach into `order._items` from a service.
- **See also:** `ch02-tactical-ddd.md`, `orderservice/entities.py`.

### Use the design patterns
- **Rule:** Reach for the catalog (factory, strategy, adapter, decorator, observer, ...) to add behavior without editing working code.
- **Why:** Patterns are the concrete mechanics of open/closed and composition. Factories are the *one* place a large `match`/`if-elif` over a type is acceptable.
- **Anti-slop:** Don't encode the pattern in the class name (`CachingDataStore`, not `CachingProxyDataStore`). Don't apply a pattern where a plain function suffices.
- **See also:** `ch02-design-patterns.md`, `design_patterns_creational.py`, `design_patterns_structural.py`.

### Don't ask, tell
- **Rule:** Tell an object to perform an operation. Don't query its state and do the work in your object.
- **Why:** A `CubeUtils.calculate_total_volume` that reads `cube.width * cube.height * cube.depth` is envious of behavior that belongs on the cube. Move it: `cube.calculate_volume()`, then delete the now-unneeded getters.
- **Python:** Replace `if detector.should_detect(now): detector.detect()` with `detector.detect()` that checks internally.
- **See also:** `encapsulation_tell_dont_ask.py`.

### Law of Demeter
- **Rule:** Don't call a method on an object returned by another method call (`user.get_account().withdraw(...)`).
- **Why:** Chained reach-through couples your code to two objects' internals at once. Move the operation to the right class, or make the middle object a facade.
- **Python:** `user.purchase(item)` (User facades Account) beats `user.get_account().withdraw(item.get_price())`.
- **See also:** `encapsulation_tell_dont_ask.py` (`User` facade over `Account`).

### Avoid primitive obsession
- **Rule:** Replace meaningful primitives in signatures with semantic types (`NewType` or a validated value object).
- **Why:** `Rectangle(50, 20)` can swap width/height silently, and an `int` port lets `99999` through. The validation then gets copy-pasted everywhere. A `Port` value object validates once and is always valid.
- **Python:**
  ```python
  Width = NewType("Width", int)
  Height = NewType("Height", int)
  def make(w: Width, h: Height) -> Rectangle: ...   # order now type-checked
  ```
  Named parameters (`Rectangle(width=50, height=20)`) are a lighter guard against argument-order bugs.
- **See also:** `primitive_obsession.py`, fluent-python ch15 (NewType/advanced typing).

### Dependency injection
- **Rule:** Inject collaborators (constructor args / a DI container). Name concrete implementations only at the composition root.
- **Why:** DI is the prerequisite for open/closed and for unit testing, you inject a fake repo/parser instead of the real one. Static methods on hardcoded classes are hard to swap and hard to mock.
- **Python:** Constructor injection (`OrderServiceImpl(repository)`) wired in one `build_controller()` / `DiContainer`. Read config, then choose which concrete class satisfies each protocol (stdout vs file logger by env var).
- **Anti-slop:** Don't `from x import singleton` and call it deep in business logic. Inject it. Adopt DI early. Retrofitting it later is a large refactor.
- **See also:** `orderservice/container.py`.

### Avoid code duplication
- **Rule:** When two classes implementing the same interface share code, lift it into a common base class, often as a template method.
- **Why:** Duplicated `try_decode` across `AvroBinaryKafkaInputMessage`, `JsonKafkaInputMessage`, ... drifts out of sync. A base `AbstractInputMessage.try_decode` (template) calling abstract `_get_data`/`_get_length` keeps it in one place.
- **Python:** Mark the template method `@final` and the hooks `@abstractmethod`. (This is the one place inheritance beats composition: pure shared mechanics behind an interface.)
- **See also:** template method in `ch02-design-patterns.md`.

## Anti-slop checklist

- Don't import or instantiate a concrete dependency inside a class, accept the protocol as a constructor parameter (DIP/DI).
- Don't reverse-engineer a fat interface from existing concrete classes. Design the abstraction first (the `Animal` with `swim`/`fly`/`bark` mistake).
- Don't subclass to reuse code when the subtype can't satisfy the parent contract (LSP). Compose instead.
- Don't add a boolean flag or extra branch to a working class to vary behavior. Add a new class (OCP).
- Don't force a small implementer to stub-and-raise methods of a fat interface (ISP). Split it.
- Don't auto-generate a getter+setter per field, and don't return a live mutable attribute from a property.
- Don't pull another object's state and compute on it (feature envy). Tell the object to do it.
- Don't chain `a.get_b().do_c()` (Law of Demeter). Facade or relocate.
- Don't pass bare `int`/`str` where order or validity matters. Use `NewType`/value objects or named params.
- Don't prefix interfaces with `I`, don't put `and` in a function name, don't write `does_start_with`/`stopped()` (use `starts_with`/`is_stopped`).
- Don't bake a pattern name into a class name (`CachingProxyDataStore`). Name by purpose (`CachingDataStore`).
- Don't put a long `match`/`if-elif` over a type enum anywhere except a factory. Elsewhere it means a missing polymorphic design (replace conditionals with polymorphism).
- Don't reach for multiple inheritance/mixins for code reuse when composition avoids method-name clashes.

## Bundled examples

| File | Principle(s) demonstrated |
|---|---|
| `examples/object-oriented-design-principles/solid_principles.py` | SRP, OCP, LSP, ISP, DIP |
| `examples/object-oriented-design-principles/composition_over_inheritance.py` | Composition over inheritance, strategy injection |
| `examples/object-oriented-design-principles/encapsulation_tell_dont_ask.py` | Encapsulation, don't-leak-state, tell-don't-ask, Law of Demeter |
| `examples/object-oriented-design-principles/primitive_obsession.py` | Avoid primitive obsession (NewType + validated value object) |
| `examples/object-oriented-design-principles/design_patterns_creational.py` | Abstract factory, static factory method, singleton |
| `examples/object-oriented-design-principles/design_patterns_structural.py` | Strategy, adapter, decorator |
| `examples/object-oriented-design-principles/orderservice/` | Clean microservice design, tactical DDD, DI composition root |
