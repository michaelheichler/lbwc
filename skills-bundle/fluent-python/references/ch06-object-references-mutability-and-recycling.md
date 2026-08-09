## Chapter 6: Object References, Mutability, and Recycling
### Core Ideas
- Python variables are bindings to objects. Assignment copies a reference, not the referred value.
- Object identity is distinct from equality: `is` checks sameness, while `==` asks whether values compare equivalent.
- Aliasing is normal in Python: two names can reach the same mutable object, so mutation through either name is visible through both.
- Container immutability is shallow. A tuple cannot swap its item references, but mutable objects inside it may still change.
- Common copy operations on built-in containers are shallow. Nested mutable objects remain shared unless copied separately.
- Function calls use call by sharing: parameters receive references to argument objects, so in-place changes can affect caller-owned mutables.
- Object cleanup follows reachability, not explicit destruction. `del` removes a binding, and garbage collection handles unreachable objects.
- Some immutable values may be reused by the interpreter, but that is an optimization detail, not a semantic promise.

### Practitioner Guidance
- In code review, treat assignment as rebinding or alias creation. Check whether later mutations assume a fresh object.
- Use `is None`, `is not None`, and identity checks for private sentinel objects, and use `==` for ordinary value comparisons.
- Never use a mutable object as a default parameter value. Use `None`, then allocate inside the function or method.
- When storing a caller-provided mutable argument on an instance, copy it unless the API explicitly promises shared ownership.
- Choose shallow copy, deep copy, or no copy deliberately. Shallow copy is fine for immutable members, and deep copy may be excessive for resources or shared singletons.
- Prefer immutable inputs, local copies, or clear mutation contracts at API boundaries, especially for constructors, caches, and shared state.
- Use `with` or explicit cleanup for external resources. Do not rely on CPython reference-count timing or `__del__`.
- When printed values look identical but behavior differs, inspect identity or aliasing paths during debugging.

### Pitfalls
- Assuming `b = a` creates an independent object.
- Comparing strings, integers, tuples, or other values with `is` because interning or copy elision happened once.
- Forgetting that a tuple containing a list can have an effectively changing value.
- Letting a mutable default collect state across calls or instances.
- Mutating a list, dict, set, or other mutable object received from the caller without documenting that side effect.
- Believing `del name` destroys the object even when other references still exist.

### Skill Hooks
- object references, variable binding, aliasing, identity vs equality
- `is` vs `==`, `None` checks, sentinel object patterns
- shallow copy, deep copy, `copy.copy`, `copy.deepcopy`, custom copy behavior
- mutable defaults, default argument bugs, shared state across calls
- defensive copying, constructor argument copying, mutation side effects
- tuple immutability, mutable objects inside immutable containers, hashability surprises
- `del`, garbage collection, weak references, finalizers, object lifetime
- CPython interning, immutable reuse, misleading identity comparisons

### Cross-Links
- Chapter 1 / Data Model: object identity, value, type, equality methods, and finalization behavior.
- Chapter 2 / Sequences: tuple behavior, augmented assignment, and list copying patterns.
- Chapter 3 / Dictionaries and Sets: hashability and why mutable contents break hash assumptions.
- Part III / Functions as Objects: function defaults, call semantics, and function objects holding default values.
