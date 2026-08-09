## Chapter 13: Interfaces, Protocols, and ABCs
### Core Ideas
- Modern Python supports four complementary interface styles: ordinary duck typing, ABC-based runtime checks, nominal static typing, and static structural protocols.
- Dynamic protocols are convention-based interfaces: an object can often satisfy only the methods a context needs, such as indexing enough to allow iteration.
- Static protocols use `typing.Protocol` to describe required operations for type checkers without forcing inheritance from the protocol class.
- ABCs make an interface explicit at runtime. Subclassing or registration lets `isinstance` and `issubclass` express an API contract.
- `collections.abc` formalizes common container roles such as iterable, sized, sequence, mapping, set, mutable variants, callable, and hashable.
- ABCs may provide concrete mixin methods, but those methods should depend only on the public operations promised by the ABC.
- Virtual subclass registration is a promise, not validation: it affects runtime type checks but does not add inherited behavior.
- Runtime structural checks can be shallow. They usually detect method names, not semantic correctness or annotated return types.

### Practitioner Guidance
- Prefer duck typing when the code only needs to perform an operation. Call the operation early and let invalid inputs fail near the source.
- Convert inputs at boundaries when appropriate, for example building an internal list from any finite iterable to gain flexibility and avoid caller-owned mutation.
- Use `isinstance(x, SomeABC)` sparingly, mainly for framework boundaries, plugin contracts, or cases where copying or probing would be wrong.
- When checking runtime interfaces, use ABCs or protocols rather than concrete implementation classes.
- Subclass an existing standard-library ABC when it matches the behavior you are implementing. Expect to implement every abstract method it requires.
- Override ABC-provided concrete methods when the inherited version is correct but inefficient for your storage strategy.
- Design static protocols narrowly, often around one role or one operation. Derive a larger protocol later instead of inflating the first one.
- Put small client-side protocols near the code that consumes them when that improves testing, mocks, or extension points.

### Pitfalls
- A positive `Hashable` check can still fail at actual hashing time if contained values are unhashable.
- A negative `Iterable` ABC check does not prove Python cannot iterate the object. `iter(obj)` is the reliable runtime probe.
- Monkey patching can retrofit a protocol, but it couples the patch to private details and can conflict with other patches.
- ABC registration does not verify method presence, signatures, or behavior, and registered classes do not receive ABC mixin methods.
- `@runtime_checkable` protocols ignore most type-hint detail at runtime, so `isinstance` can report support even when the operation later raises.
- Numeric ABCs work for runtime checks, while numeric `typing.Supports*` protocols are better for static typing. Complex-number conversions expose edge cases.

### Skill Hooks
- duck typing, goose typing, static duck typing, structural typing, nominal typing
- `collections.abc`, `abc.ABC`, `@abstractmethod`, abstract base class design
- `typing.Protocol`, `@runtime_checkable`, protocol design, protocol extension
- `isinstance` review, `issubclass` review, replacing concrete type checks
- sequence protocol, iterable protocol, mutable sequence, `__getitem__`, `__iter__`, `__contains__`
- virtual subclass registration, `register`, `__subclasshook__`, mixin methods
- fail fast, EAFP, boundary validation, defensive iterable handling
- numeric type hints, `SupportsFloat`, `SupportsComplex`, `numbers.Number`

### Cross-Links
- Chapter 1: sequence behavior and the original deck example.
- Chapter 3: mapping and set ABC relationships.
- Chapter 6: mutable argument aliasing and defensive copies.
- Chapter 8: type hints, static protocols, and type consistency.
- Chapter 11: special methods and vector conversion examples.
- Chapter 14: multiple inheritance and method resolution order.
- Chapter 15: deeper static typing coverage.
- Chapter 16: operator overloading and multiplication-compatible objects.
- Chapter 17: iterators and why sequences can be iterable.
- Chapter 24: metaclasses and lower-level ABC machinery.
