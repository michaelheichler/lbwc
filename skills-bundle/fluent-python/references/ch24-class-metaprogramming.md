## Chapter 24: Class Metaprogramming
### Core Ideas
- Python classes are runtime objects with metadata such as `__bases__`, `__qualname__`, `__subclasses__()`, and `mro()`, so code can inspect class relationships directly.
- `type(name, bases, namespace)` is the underlying class builder. The normal `class` statement ultimately feeds a name, base tuple, and namespace mapping into class construction.
- Class factory functions can generate simple families of classes dynamically, but they must handle naming, initialization, representation, attribute layout, and serialization concerns explicitly.
- `__init_subclass__` lets a base class customize each newly declared subclass after the subclass object has been created. It is well suited to registration, validation, and descriptor injection.
- Class decorators transform an already-created class and can add descriptors or methods without requiring inheritance from a framework base class.
- Class creation order matters: class body execution, descriptor `__set_name__`, base-class `__init_subclass__`, and class decorators happen at different points.
- Metaclasses are subclasses of `type` whose instances are classes. They can customize class creation before `type.__new__` finishes, including the namespace used to build the class.
- Modern Python features such as class decorators, `__set_name__`, `__init_subclass__`, and ordered dictionaries remove many older reasons to write metaclasses.

### Practitioner Guidance
- Prefer ordinary classes, `dataclass`, `NamedTuple`, or a small explicit helper before adding custom class metaprogramming to application code.
- Use a class factory when classes must be created from runtime data and the generated API is small, predictable, and easy to test.
- Use `__init_subclass__` when subclasses of a known base need automatic setup. Call `super().__init_subclass__()` so multiple inheritance remains cooperative.
- Use a class decorator for opt-in class enhancement when forcing a base class or metaclass would create unnecessary coupling.
- Use a metaclass only when the solution must affect the pre-creation namespace, configure `__slots__`, provide `__prepare__`, alter class-level special methods, or otherwise work before the class exists.
- Hide metaclasses behind a normal base class so user code depends on a stable public abstraction rather than the metaclass itself.
- Review import-time behavior carefully: class bodies, descriptors, decorators, and metaclass hooks can all run while a module is imported.
- For runtime validation from annotations, distinguish simple constructors from rich static type hints. Not every type hint can be enforced by a small runtime checker.

### Pitfalls
- Adding `__slots__` in `__init_subclass__` or a class decorator is too late. It must be present in the namespace passed into class creation.
- Metaclass conflicts are easy to trigger because a class can have only one effective metaclass, and ABCs already use `ABCMeta`.
- Overriding `__setattr__` can interfere with descriptor behavior unless descriptor assignment is deliberately delegated.
- Generated methods and injected attributes can collide with user-defined names. Private-ish helper naming only reduces that risk.
- Import-time metaprogramming can hide expensive work or side effects behind an innocent-looking import.
- A metaclass written to meet a narrow deadline can leave subtle maintenance debt even when it appears to work.

### Skill Hooks
- class metaprogramming, runtime class creation, class factory, `type(name, bases, namespace)`
- `__init_subclass__`, subclass registration, subclass validation, automatic descriptor injection
- class decorators, dataclass-like builder, `NamedTuple`-like builder, generated `__init__` or `__repr__`
- descriptors with `__set_name__`, overriding descriptors, runtime annotation validation
- dynamic `__slots__`, memory optimization for many instances, blocking undeclared attributes
- metaclass, `type` subclass, `__prepare__`, custom class namespace, class-level special methods
- import time versus runtime, class body execution order, descriptor/decorator/metaclass timing
- `ABCMeta` conflict, multiple inheritance with metaclasses, framework base class design

### Cross-Links
- Chapter 5: data class builders, `typing.NamedTuple`, `@dataclass`, and type-hint-driven class APIs.
- Descriptor material: `Field` descriptors, `__set_name__`, overriding descriptors, and methods as descriptors.
- Runtime annotation material: `get_type_hints`, `__annotations__`, and problems with evaluating annotations dynamically.
- `__slots__` material: memory savings, attribute restrictions, and tradeoffs for large numbers of instances.
- Object construction material: `__new__`, factory behavior, and object/class creation flow.
- Multiple inheritance and ABC material: cooperative `super()`, MRO, `ABCMeta`, and metaclass conflict handling.
