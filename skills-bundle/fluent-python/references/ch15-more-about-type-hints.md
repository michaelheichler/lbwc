## Chapter 15: More About Type Hints
### Core Ideas
- Python's gradual type system can describe flexible APIs, but highly dynamic call patterns often require several overloads to model one simple runtime function.
- `@overload` lets a checker connect argument combinations to precise return types. The overload declarations sit above a single implementation or live in stub files.
- `TypedDict` describes dicts used as records with fixed string keys and per-key value types, but it creates plain dicts and adds no runtime validation.
- `typing.cast` is a checker directive, not a conversion. It is useful when the checker lacks information or dependency hints are wrong, but it should be rare and justified.
- Runtime annotation access is fragile because annotations may be stored as objects or strings, so use `inspect.get_annotations` or `typing.get_type_hints` behind a local wrapper.
- Generic classes bind type variables across constructor parameters, method arguments, and return values so checkers can preserve relationships such as "this picker returns the item type it was loaded with."
- Variance controls whether generic types follow, reverse, or ignore subtype relationships. Mutable producer-and-consumer containers are normally invariant.
- Generic protocols combine structural typing with type parameters, allowing protocols such as "has `__abs__` returning float-like values" or "picks a value of T."

### Practitioner Guidance
- Use overloads when the return type genuinely depends on which arguments are supplied, and otherwise prefer one readable signature.
- Keep overload declarations narrow, ordered, and consistent with the implementation, then test them with representative calls and `reveal_type` when needed.
- Treat `TypedDict` as a static aid for code that already controls the record shape, and validate JSON, API responses, and untrusted mappings at runtime.
- Prefer runtime validators or domain objects when record data must be trusted, defaulted, transformed, or accessed with attributes.
- Reach for `cast` only after checking whether the code, the dependency stub, or the checker configuration is the real problem, and document the reasoning near non-obvious casts.
- Hide runtime annotation introspection behind one helper so future annotation semantics or Python-version differences do not leak through a codebase.
- When designing generics, start invariant. Make a type variable covariant only for output-only positions and contravariant only for input-only sink positions.
- For callback and protocol APIs, reason from data flow: parameter types are accepted inputs, return types are produced outputs.

### Pitfalls
- Chasing complete annotation coverage can create noisy hints or distorted APIs with little practical value.
- Assuming a `TypedDict` constructor checks keys or values, when in fact at runtime it behaves like `dict`.
- Letting `Any`, broad casts, or `# type: ignore` spread until the checker can no longer protect nearby code.
- Reading `__annotations__` directly and then breaking on forward references, postponed annotations, nested definitions, or Python-version changes.
- Marking mutable containers covariant because their element type hierarchy looks compatible, when mutation can make that unsound.
- Importing obscure implementation-detail classes solely for perfect hints may cost more than a targeted ignore or narrower annotation is worth.

### Skill Hooks
- advanced Python type hints, gradual typing beyond basics
- `@overload`, overloaded signatures, precise return type by argument shape
- annotating `sum`, `max`, `min`, positional-only overloads, variadic overloads
- `TypedDict`, dict-as-record, fixed keys, JSON record typing
- runtime validation versus static checking, pydantic mention, untrusted API payloads
- `typing.cast`, `# type: ignore`, `Any`, incorrect stubs, typeshed mismatch
- runtime annotations, `__annotations__`, `get_type_hints`, `inspect.get_annotations`, forward references
- generic class, `Generic[T]`, parameterized type, formal type parameter, actual type parameter
- variance, invariant, covariant, contravariant, mutable collections, producer versus consumer
- generic protocol, `Protocol[T]`, `SupportsAbs`, `runtime_checkable`

### Cross-Links
- Chapter 5: `NamedTuple`, data classes, and other class builders provide runtime objects, unlike `TypedDict`.
- Chapter 8: function annotations, `TypeVar`, bounded type variables, protocols, callables, `Any`, and positional-only parameters are the foundation for this chapter.
- Chapter 13: protocols, ABCs, structural typing, and the original non-generic `RandomPicker` are extended here.
- Chapter 17: iterators, generators, classic coroutines, and their generic/variance-sensitive type hints continue the same data-flow reasoning.
- Chapter 21: async objects, coroutine types, and the `asyncio` example connect to casts and asynchronous type hints.
- Chapter 24: class metaprogramming uses runtime annotation inspection through a wrapper around type-hint introspection.
