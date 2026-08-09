## Chapter 14: Inheritance: For Better or for Worse
### Core Ideas
- `super()` should be the normal way to delegate from an overriding method, especially in `__init__`, because it follows the active method resolution order instead of naming one parent class.
- Direct subclasses of built-in types such as `dict`, `list`, and `str` can behave unexpectedly: built-in C-level methods may bypass overrides in the subclass.
- `collections.UserDict`, `UserList`, and `UserString` are safer extension bases when the goal is to customize built-in container behavior.
- Multiple inheritance depends on both `__mro__` and whether each method cooperates by calling `super()`. A single non-cooperative override can stop the chain.
- The order of base classes in a class declaration affects method lookup, so changing it can change behavior even when class bodies stay unchanged.
- Mixins are implementation helpers meant to be combined with real base classes. They add narrow behavior without claiming a new domain type.
- ABCs can serve both as interface declarations and as providers of reusable concrete methods.
- Modern Python design should treat inheritance as a tool for framework contracts or carefully bounded reuse, not as the default way to share code.

### Practitioner Guidance
- Prefer composition or delegation when the relationship is "uses" or "has behavior from." Reserve subclassing for true subtype relationships or framework extension points.
- When overriding a method in a class hierarchy, call `super().method(...)` unless the method is intentionally terminal and documented as such.
- Keep cooperative methods signature-compatible across sibling classes. In multiple inheritance, the next method may not be the parent you pictured.
- For custom mappings, sequences, or strings, start from `collections` wrappers or `collections.abc` instead of subclassing the concrete built-ins directly.
- Name mixins with a `Mixin` suffix, keep them focused, avoid instance state, and place them before concrete bases when their methods must intercept calls.
- Use ABCs or `typing.Protocol` to make interfaces explicit. Avoid using concrete classes as broad interface definitions.
- Provide aggregate classes for common, correct combinations of bases and mixins so callers do not have to discover base ordering themselves.
- Before subclassing a complex third-party or standard-library class, check whether its documentation identifies safe override points.

### Pitfalls
- Hard-coding `BaseClass.method(self, ...)` creates fragile code when bases change or when multiple inheritance is introduced.
- Subclassing `dict` or similar built-ins can produce partial customization where assignment uses an override but initialization, update, or lookup helpers do not.
- Mixins that rely on undeclared sibling behavior are easy to break if base ordering changes or if required methods have incompatible signatures.
- Deep hierarchies hide where behavior comes from and can expose huge, noisy APIs to users of leaf classes.
- Inheritance used only for code sharing couples classes more tightly than equivalent composition and can make small changes ripple through a system.

### Skill Hooks
- inheritance design review
- `super()` usage, cooperative methods, or parent delegation
- method resolution order, `__mro__`, diamond inheritance
- multiple inheritance, mixins, aggregate classes
- subclassing `dict`, `list`, `str`, `Counter`, or other built-ins
- `UserDict`, `UserList`, `UserString`, `collections.abc`
- ABC versus concrete base class decisions
- composition over inheritance refactors
- framework extension points, class-based views, GUI/widget hierarchies

### Cross-Links
- Chapter 3: custom mappings, `__missing__`, and `StrKeyDict` behavior.
- Chapter 13: interfaces, protocols, ABCs, and subtype thinking.
- Chapter 23: descriptors, because deeper `super()` mechanics connect to descriptor binding.
- Earlier function-focused chapters: consider functions or single-dispatch designs before building class hierarchies.
