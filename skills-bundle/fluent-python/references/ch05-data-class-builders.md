## Chapter 5: Data Class Builders
### Core Ideas
- Python offers three standard shortcuts for field-centric classes: `collections.namedtuple`, `typing.NamedTuple`, and `@dataclasses.dataclass`.
- Both named tuple builders produce immutable tuple subclasses with generated construction, representation, equality, field metadata, and tuple compatibility.
- `typing.NamedTuple` adds field annotations and class-statement syntax, making methods and docstrings easier to attach than with classic `namedtuple`.
- `@dataclass` decorates a normal class, reads annotated fields, and can generate `__init__`, `__repr__`, equality, ordering, and hash behavior according to options.
- Type hints guide tools and class builders, but Python does not enforce them while running. Use static analyzers for type checking.
- Variable annotations inside ordinary classes, `NamedTuple`, and dataclasses have different effects on class attributes, instance fields, and descriptors.
- Dataclass field customization covers defaults, default factories, inclusion in init/repr/comparison/hash, and arbitrary metadata.
- Class patterns in `match` can use public attributes. Data class builders also supply `__match_args__` for positional matching.

### Practitioner Guidance
- Use classic `namedtuple` for compact immutable records when tuple API compatibility and low memory use matter.
- Use `typing.NamedTuple` when you want immutable records plus annotations, class syntax, and occasional methods.
- Use `@dataclass` when you need regular class behavior, mutability by default, decorator options, richer field controls, or post-init processing.
- Prefer `frozen=True` for values that should not change after construction, and combine with `eq=True` when hashable value objects are needed.
- Use `field(default_factory=...)` for mutable per-instance defaults such as lists, dicts, or sets, and extend that habit to other mutable objects too.
- Use `ClassVar[...]` for annotated class-level state in dataclasses, otherwise the decorator may treat the name as an instance field.
- Use `InitVar[...]` when constructor input is needed only during initialization and should not become stored object state.
- Treat data classes as temporary scaffolding, boundary records, or value objects. Move behavior into them when external code starts manipulating their internals repeatedly.

### Pitfalls
- An annotated name in a dataclass becomes an instance field unless marked with `ClassVar`, which can accidentally change class-level state into per-instance data.
- Plain type annotations do not validate values at runtime, so bad values can still be constructed unless explicit checks or external tooling are used.
- Literal mutable defaults create shared-state bugs. Dataclasses block common built-ins but cannot detect every mutable object.
- Fields with defaults must come after required fields, because they become generated constructor parameters.
- Data-only objects can become a design smell when behavior is scattered across unrelated functions or classes.
- Pattern matching without call syntax, such as a bare class name in a `case`, may bind a variable instead of testing the type.

### Skill Hooks
- `dataclass`, `data classes`, `namedtuple`, `NamedTuple`
- immutable record, value object, tuple-like record, field-only class
- generated `__init__`, generated `__repr__`, generated equality, dataclass ordering
- `field(default_factory=...)`, mutable default, default field values
- `ClassVar`, `InitVar`, `__post_init__`, dataclass validation
- `dataclasses.asdict`, `_asdict`, `replace`, `_replace`, `fields`
- annotations in class body, runtime type hints, `get_type_hints`, `inspect.get_annotations`
- structural pattern matching, class patterns, `__match_args__`
- data class code smell, anemic object, intermediate representation

### Cross-Links
- Chapter 1: named tuple examples in simple object modeling.
- Chapter 6: mutable defaults and parameter default hazards.
- Chapter 8: function annotations, generics, and broader typing practice.
- Chapter 14: inheritance concerns, especially with concrete data-class hierarchies.
- Chapter 15: `TypedDict`, advanced annotations, and runtime annotation issues.
- Chapter 23: descriptors behind generated read-only named tuple fields.
- Chapter 24: class decorators, metaclasses, and class-building machinery.
