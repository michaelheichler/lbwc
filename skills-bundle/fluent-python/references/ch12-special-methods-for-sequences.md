## Chapter 12: Special Methods for Sequences
### Core Ideas
- A custom collection can behave like a Python sequence through behavior, not inheritance. The essential runtime protocol starts with `__len__` and `__getitem__`.
- Build sequence-like types by composition when an internal container can do most storage, iteration, and slicing work.
- Constructors for sequence types should normally accept one iterable, matching built-in sequence style.
- Slice syntax reaches `__getitem__` as `slice` objects, while comma-separated indexes arrive as tuples. Decide explicitly which cases your type supports.
- A slice of a sequence-like object should usually return a new object of the same logical type, not leak the internal storage type.
- `__getattr__` can create computed shortcut attributes, but it only runs after normal lookup fails, so assignment behavior must be reviewed too.
- Hashable immutable containers need `__eq__` and `__hash__` to agree across all stored values without unnecessary full-size temporary copies.
- `__format__` may extend Python's formatting mini-language, but custom suffixes should avoid colliding with existing numeric and string codes.

### Practitioner Guidance
- For a flat immutable sequence, implement `__iter__`, `__len__`, `__getitem__`, `__repr__`, `__eq__`, `__hash__`, and only the extra operations the domain actually needs.
- Keep `repr()` safe for large or recursive-ish collections by using bounded display logic such as `reprlib`. Debugging output should not explode logs.
- In `__getitem__`, branch on `slice` for slicing and use `operator.index` for scalar indexes so non-integral values fail correctly.
- Use `type(self)` when building results from slices, so subclasses or alternate concrete classes have a chance to preserve their type.
- If adding dynamic read-only aliases such as coordinate names, pair `__getattr__` with `__setattr__` guards to prevent shadowing bugs.
- Prefer lazy comparisons for large containers: check lengths first, then compare paired elements with `zip` plus `all`. In Python 3.10+, consider `zip(..., strict=True)` where length mismatch should fail loudly.
- Use reducing operations when they express the aggregate clearly. Provide an initializer to `functools.reduce`, especially for possibly empty inputs.
- Keep `__eq__` and `__hash__` near each other in source and review them together, because object identity in sets and dicts depends on their contract.

### Pitfalls
- Delegating slicing blindly can return the wrapped storage object and strip away your custom type's behavior.
- Using `int()` for indexes accepts values like floats by truncation. `operator.index` is the intended index conversion.
- Implementing `__getattr__` alone can let later instance assignments override computed virtual attributes.
- `zip` truncates to the shortest iterable unless strict checking or prior length checks are used.
- A `reduce` call without an initializer fails on empty input and may encode the wrong identity value for the operation.
- A custom `__format__` for huge collections can produce excessive output unless the design intentionally limits or opts into full display.

### Skill Hooks
- custom sequence type, immutable collection, sequence protocol, duck typing
- `__len__`, `__getitem__`, slice-aware indexing, `slice.indices`, multidimensional index rejection
- `operator.index`, `__index__`, NumPy-style integer indexes
- safe `__repr__`, `reprlib`, large collection display
- dynamic attributes, `__getattr__`, `__setattr__`, read-only aliases, `__match_args__`
- hashable container, aggregate hash, `functools.reduce`, `operator.xor`
- efficient equality, `zip`, `zip_longest`, `all`, generator expression comparison
- custom `__format__`, format spec suffix, Cartesian versus spherical display

### Cross-Links
- Chapter 1: `FrenchDeck` and the basic sequence protocol.
- Chapter 11: `Vector2d`, immutability, bytes conversion, `repr`, hashing, and formatted display.
- Chapter 13: dynamic versus static protocols, `typing.Protocol`, and interfaces.
- Chapter 14: organizing related classes with inheritance.
- Chapter 16: infix operators and operator overloading for `Vector`.
- Chapter 17: iterators, generator functions, `__iter__`, and the generator expressions used here.
