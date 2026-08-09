## Chapter 1: The Python Data Model
### Core Ideas
- The data model is Python's protocol layer: user objects join core syntax and built-ins by implementing documented special methods.
- Special methods are normally invoked indirectly through operations such as `len(x)`, `x[i]`, `iter(x)`, `repr(x)`, `bool(x)`, `abs(x)`, and `x + y`.
- A small protocol can unlock broad behavior. For a sequence-like object, `__len__` plus `__getitem__` enables length, indexing, slicing, iteration fallback, reverse iteration, membership fallback, sorting, and standard-library helpers.
- Composition is a strong implementation pattern: wrap or delegate to built-in containers instead of recreating their mechanics.
- Operator methods let domain objects behave like numeric values, but ordinary infix operators should usually return new objects and leave operands unchanged.
- `__repr__` is for inspection, debugging, and logs, while `__str__` is for user-facing display. If only one is implemented, prioritize `__repr__`.
- Truth value testing checks `__bool__`, then `__len__`, and otherwise treats custom instances as truthy.
- Collection behavior is organized around protocols such as iterable, sized, container, sequence, mapping, and set. ABC inheritance can document intent, but the key behavior comes from the methods.

### Practitioner Guidance
- Prefer calling the relevant built-in or using syntax instead of invoking dunder methods directly: use `len(obj)`, not `obj.__len__()`.
- In design and review, ask which Python protocol the class should satisfy, then implement the smallest coherent set of special methods.
- For collection wrappers, delegate `__len__`, `__getitem__`, and related methods to an internal list, dict, or set when that preserves the intended semantics.
- Implement `__repr__` with enough type and field detail to distinguish similar-looking values, especially strings versus numbers.
- Add `__str__` only when the audience-facing representation should differ from the diagnostic one.
- For Boolean behavior, make `__bool__` explicit when emptiness or zero-ness is not the right rule, and always return an actual `bool`.
- For operators like `+` or `*`, validate the operand model and consider whether reversed or augmented forms are also needed.
- Use collection ABC names as review vocabulary: `Iterable`, `Sized`, `Container`, `Sequence`, `Mapping`, and `Set` help identify missing behavior.

### Pitfalls
- Calling special methods directly can miss built-in optimizations or helper behavior and makes code less idiomatic.
- Inventing undocumented double-underscore names can collide with future Python features.
- Implementing `__str__` while leaving the inherited `__repr__` often produces weak logs and debugger output.
- Membership via iteration fallback may be correct but can become a linear scan. Add `__contains__` when lookup cost matters.
- A sequence-like wrapper without `__setitem__` cannot support mutation-oriented tools such as shuffling.
- Normal binary operators that mutate operands surprise callers unless the operation is clearly an augmented assignment path.

### Skill Hooks
- `python data model`, `special methods`, `dunder methods`, `magic methods`
- `__len__`, `__getitem__`, `__iter__`, `__contains__`, `__repr__`, `__str__`, `__bool__`
- Custom collection, sequence wrapper, iterable object, membership behavior, slicing behavior
- Operator overloading, numeric protocol, vector-like object, reversed operator, augmented assignment
- Truthiness, object representation, `repr` versus `str`, `len` as a built-in
- Collection ABCs, `collections.abc`, `Iterable`, `Sized`, `Container`, `Sequence`, `Mapping`, `Set`

### Cross-Links
- Chapter 2: built-in and standard-library sequence types.
- Chapter 12: implementing custom sequences and expanding the vector example.
- Chapter 13: abstract base classes, collection interfaces, and mutable sequence behavior such as assignment by index.
- Chapter 16: operator overloading, reversed operators, and augmented assignment.
- Chapter 17: iteration details and callable-based `iter` usage.
