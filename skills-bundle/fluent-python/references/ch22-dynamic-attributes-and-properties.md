## Chapter 22: Dynamic Attributes and Properties
### Core Ideas
- Python can present stored data and computed values through the same `obj.attr` syntax, which supports APIs that can evolve from public fields to managed access.
- `__getattr__` is the lightweight hook for virtual attributes: it runs after normal lookup fails, so it is well suited for lazy lookup, JSON-style exploration, and fallback computation.
- Data-driven attribute objects can wrap mappings recursively, but keys may collide with methods, keywords, invalid identifiers, or existing attributes.
- `__new__` is the actual object-construction hook. It can return an instance of the class, a different type, or an existing object, while `__init__` only initializes objects that were actually created for that class.
- `@property` turns method logic into attribute access for computed values, linked-record dereferencing, validation, and compatibility-preserving API changes.
- Properties live on the class and take precedence over same-named instance entries, which is why property getters/setters often read or write `instance.__dict__` directly to avoid recursion.
- Property caching has several forms: manual cache attributes, `functools.cached_property`, or `@property` stacked over `functools.cache`, each with different behavior around overriding, memory, and existing attributes.
- Repeated property patterns can be abstracted with a property factory that closes over a storage name. Descriptors are the broader next step for reusable managed attributes.

### Practitioner Guidance
- Prefer ordinary public attributes first when no validation or computation is needed. Python lets you later replace them with properties without changing client syntax.
- Use `__getattr__` for missing-name behavior, not broad interception. Reach for `__getattribute__` only when every lookup must be controlled and recursion risks are understood.
- When generating attributes from external data, sanitize Python keywords, reject or route invalid identifiers, and audit for collisions with class methods such as `fetch`, `keys`, or domain methods.
- If a property needs access to raw same-named data, read from `self.__dict__` or another private storage slot instead of calling `self.name` inside the getter.
- For linked objects or lazy computations, make the property cost clear in code review. Attribute syntax can hide database, network, or expensive CPU work.
- Use `cached_property` when a computed value has no preexisting same-named instance attribute and the class has a normal `__dict__`. Delete the attribute when invalidation should recompute it.
- Stack `@property` above `@cache` when the property must override an existing instance attribute name, but review cache lifetime because it keys on the instance.
- Use the classic `property(getter, setter, deleter, doc)` form when generating properties in factories or when decorator syntax obscures the abstraction.

### Pitfalls
- Raising the wrong exception from `__getattr__` breaks normal attribute expectations. Missing attributes should normally end in `AttributeError`.
- Creating attributes from arbitrary mappings can shadow methods, overwrite data, or make values inaccessible through dot notation.
- Calling `self.attr` inside the getter for property `attr` causes recursive lookup unless the getter uses raw storage.
- Manual lazy caches can waste memory by disabling key-sharing dictionaries and may have race conditions in threaded code.
- `cached_property` is not a drop-in replacement for `property`: writes can override it, it needs an instance `__dict__`, and it creates cache storage after initialization.
- Implementing `__getattribute__`, `__setattr__`, or `__delattr__` changes core object behavior. Properties or descriptors are usually easier to review.

### Skill Hooks
- `@property`, property getter/setter/deleter, validating public attributes, read-only attributes
- `__getattr__`, virtual attributes, lazy attribute lookup, JSON or mapping wrappers, dot-access data exploration
- `__new__`, flexible factories, constructors returning alternate object types
- `__dict__.update`, data-driven attributes, `types.SimpleNamespace`, bunch-style records
- `functools.cached_property`, `@property` plus `@cache`, cached computed attributes, cache invalidation
- Attribute shadowing, class property precedence, instance `__dict__`, `__slots__`, key-sharing dictionaries
- `getattr`, `setattr`, `hasattr`, `dir`, `vars`, `__dir__`, autocomplete-friendly dynamic objects
- Property factories, closure-backed validation, repetitive getter/setter removal

### Cross-Links
- Chapter 9: decorator stacking, closures, and `functools.cache`/memoization.
- Chapter 11: object internals such as `__dict__`, private names, `__slots__`, and earlier property use.
- Chapter 13: ABC-based mapping and sequence checks used when wrapping JSON-like structures.
- Chapter 17: abstraction pressure from repeated code patterns before introducing property factories.
- Chapter 23: descriptors, including why regular properties override instance attributes and why `cached_property` behaves differently.
