## Chapter 23: Attribute Descriptors
### Core Ideas
- Descriptors are protocol objects used as class attributes to manage access to attributes on instances of another class.
- A descriptor may implement `__get__`, `__set__`, `__delete__`, and `__set_name__`. Partial implementations are normal and produce different lookup behavior.
- Descriptor instances live on the managed class, so per-object state must be stored on the managed instance, commonly through its `__dict__`.
- `__set_name__` lets a descriptor learn the attribute name assigned in the class body, avoiding duplicated and error-prone storage-name arguments.
- Validation descriptors can centralize setter logic across many fields and classes. An abstract base descriptor can delegate only the validation step to subclasses.
- Descriptors with `__set__` are overriding/data descriptors. They control assignment and can also dominate reads over same-named instance attributes.
- Descriptors without `__set__` are nonoverriding/nondata descriptors. A same-named instance attribute can shadow them.
- User-defined functions are nonoverriding descriptors, which explains why retrieving a function from an instance returns a bound method.

### Practitioner Guidance
- Prefer `property` for one-off managed attributes or simple read-only fields. Reach for a descriptor when the same access rule should be reused.
- In `__set__`, validate or normalize the incoming value, then write directly to the managed instance storage to avoid recursive attribute access.
- Use `__set_name__(owner, name)` in modern Python when the storage key should match the managed attribute name.
- Return the descriptor itself from `__get__` when access comes through the class, so introspection and class-level access remain useful.
- For read-only descriptor classes, implement both `__get__` and `__set__`. The setter should reject writes instead of letting instance attributes shadow the descriptor.
- For pure validation, a descriptor with only `__set__` may be enough when reads can come straight from the instance dictionary.
- Use a nonoverriding `__get__`-only descriptor for lazy computation that should replace itself with a cached instance value.
- Treat descriptors as framework-level machinery. Keep their public use simple, as in declarative field definitions.

### Pitfalls
- Storing managed values on the descriptor object shares data across all managed instances.
- Calling `setattr(instance, name, value)` inside a descriptor setter can re-enter the same descriptor and recurse.
- A copied descriptor declaration with the wrong storage name can make distinct attributes overwrite each other.
- Nonoverriding descriptors, including ordinary methods, can be shadowed by same-named instance attributes.
- Assigning to the managed class can replace the descriptor object entirely. Instance-level descriptor rules do not protect class attributes.
- Descriptor docstrings document the descriptor class broadly, so per-field help text is harder than with individual properties.

### Skill Hooks
- `descriptor`, descriptor protocol, `__get__`, `__set__`, `__delete__`, `__set_name__`
- Reusable attribute validation, ORM-style fields, declarative model attributes
- Data descriptor versus nondata descriptor, overriding versus nonoverriding descriptor
- Attribute lookup precedence, instance `__dict__`, descriptor shadowing, class attribute overwrite
- Read-only managed attributes, custom fields, validation descriptors, descriptor ABCs
- `property` internals, `cached_property`, lazy attributes, per-instance caching
- Bound methods, function descriptors, `method.__self__`, `method.__func__`

### Cross-Links
- Chapter 22: dynamic attributes, properties, cached properties, and the earlier validation/property examples.
- Chapter 24: class metaprogramming, metaclasses, class creation order, and descriptor naming/configuration.
- Chapter 11: read-only properties and public attribute design.
- Chapter 9: decorators that interact with methods, especially callable class decorators needing descriptor behavior.
- Chapter 6: assignment evaluation order, relevant to why descriptors cannot know their target name before class creation support runs.
