## Chapter 11: A Pythonic Object
### Core Ideas
- User-defined classes can feel like built-in Python types by implementing only the data-model methods their real use cases require.
- Object representation has several channels: `__repr__` for developer-facing reconstruction/debugging, `__str__` for friendly display, `__bytes__` for binary form, and `__format__` for f-strings and `format`.
- A class method is the natural tool for an alternate constructor because it receives the actual class and can preserve subclass behavior.
- Custom `__format__` methods can define type-specific presentation codes while delegating ordinary numeric formatting to component values.
- Hashable value objects need equality and a stable hash based on the same logical state. Making the exposed state read-only reduces accidental hash corruption.
- `__match_args__` lets class patterns use positional matching by mapping positions to public attribute names.
- Double-underscore attributes are name-mangled to avoid subclass collisions, while single-underscore attributes rely on convention. Neither is real access control.
- `__slots__` can greatly reduce per-instance memory by removing the normal instance dictionary, but it changes attribute flexibility and subclass behavior.

### Practitioner Guidance
- Implement special methods only when callers benefit from the protocol: representation, unpacking, comparison, truth testing, formatting, hashing, binary conversion, or pattern matching.
- Make `repr(obj)` precise enough for debugging and, when practical, constructor-like. Derive the class name dynamically so subclasses inherit a useful representation.
- Use `@classmethod` for deserialization and named constructors such as `frombytes`. Prefer a module-level helper over `@staticmethod` unless class-local grouping is clearly helpful.
- When defining `__format__`, separate any custom suffix or code from the rest of the format spec, then pass the remaining spec to the underlying values.
- For hashable classes, pair `__eq__` with `__hash__`, base both on the same immutable fields, and expose read-only properties when mutation would break set or dict behavior.
- Add `__match_args__` only for attributes that make sense as positional patterns, usually required constructor-like fields rather than every public attribute.
- Start with public attributes when simple access is enough. Convert to properties later if validation, read-only access, or computed behavior becomes necessary.
- Reach for `__slots__` when profiling shows many instances dominate memory, and explicitly decide whether dynamic attributes, cached properties, or weak references must still work.

### Pitfalls
- Building a class with every possible dunder method just to look Pythonic. Application objects should stay as small as their behavior allows.
- Returning equality for unrelated iterable types because `__eq__` blindly compares tuples of values.
- Treating double-underscore names as security. Mangled names are still reachable and writable by code that knows the generated spelling.
- Assuming `__slots__` automatically applies cleanly to subclasses. Subclasses need their own slots declaration to avoid getting an instance dictionary.
- Adding `__dict__` to `__slots__` without measuring, which can erase the memory win that motivated slots.
- Shadowing a class attribute through an instance assignment when the intent was to change the default for the whole class.

### Skill Hooks
- Pythonic object, data model, special methods, dunder methods
- `__repr__`, `__str__`, `__bytes__`, `__format__`, object display, f-string formatting
- alternate constructor, `@classmethod`, `@staticmethod`, `frombytes`, deserialization
- hashable object, immutable value object, `__eq__`, `__hash__`, set key, dict key
- read-only property, `@property`, private attribute, protected attribute, name mangling
- structural pattern matching, class pattern, positional pattern, `__match_args__`
- `__slots__`, memory optimization, many instances, missing `__dict__`, weak references
- class attribute override, instance shadowing, subclass default customization

### Cross-Links
- Chapter 1: data model overview and the first vector example.
- Chapter 2: arrays and memory views used for compact binary conversion.
- Chapter 3: dictionary memory costs that motivate `__slots__`.
- Chapter 5: data class builders, generated methods, and class pattern behavior.
- Chapter 12: the next vector iteration, indexing, slicing, and additional representation protocols.
- Chapter 16: operator overloading, including stricter equality behavior.
- Chapter 17: iteration and generators behind unpacking and `__iter__`.
- Chapter 22: deeper treatment of properties and managed attributes.
