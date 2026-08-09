## Chapter 3: Dictionaries and Sets
### Core Ideas
- `dict`, `set`, and `frozenset` are hash-table based containers. Their speed depends on keys or elements being hashable and equality-consistent.
- Modern mapping construction includes dict comprehensions, repeated `**` unpacking in literals and calls, and Python 3.9 `|` / `|=` merge operators.
- Mapping patterns in `match` work against `Mapping` objects, match required keys without caring about key order, and can ignore or capture extra items.
- `collections.abc.Mapping` and `MutableMapping` define the broad mapping protocol. Prefer them over concrete `dict` checks when alternative mappings should work.
- Missing-key behavior has several tools: `get` for read defaults, `setdefault` for mutating values in place, `defaultdict` for generated entries, and `__missing__` for custom lookup semantics.
- The standard library offers specialized mappings: `OrderedDict` for reordering-sensitive cases, `ChainMap` for layered scopes, `Counter` for tallies, `Shelf` for simple persistent string-key storage, and `UserDict` for custom mapping classes.
- Dictionary views are dynamic projections. `keys()` and `items()` can participate in set-style comparisons and combinations without first copying to lists.
- Sets express uniqueness, membership tests, and relational operations directly. Set algebra often replaces nested loops with clearer and faster code.

### Practitioner Guidance
- Use dict or set comprehensions when deriving containers from iterables and the transformation is local and readable.
- For merging mappings, use `left | right` when producing a new mapping and `target |= source` when mutating in place. Remember later values win on duplicate keys.
- For semi-structured records, use mapping pattern matching when the shape is important, and include explicit cases for invalid known record types plus a catch-all.
- Accept `Mapping` or `MutableMapping` when reviewing APIs that do not require a concrete `dict`. This keeps `OrderedDict`, `ChainMap`, proxies, and user-defined mappings viable.
- Use `setdefault` only when the existing or new value will be immediately mutated, such as appending to a per-key list.
- Use `defaultdict(factory)` when missing entries should be created through `d[key]`. Do not expect `get` or membership checks to create them.
- Prefer subclassing `collections.UserDict` over subclassing `dict` for custom mappings, especially when normalizing keys or coordinating `__missing__`, `get`, `update`, and `__contains__`.
- Use `MappingProxyType` when callers need live read access to a mapping but should not mutate it through the public API.

### Pitfalls
- `{}` creates an empty dict, not an empty set. Use `set()` for the empty set.
- Hash values are process-local implementation details. Do not persist them or depend on stable set ordering.
- Mutable objects, or tuples containing mutable objects, cannot safely serve as dict keys or set elements.
- `defaultdict` only calls its factory from `__getitem__`. `dd.get(k)` and `k in dd` behave like ordinary missing-key checks.
- Mapping pattern matching reads existing keys with `get`-style logic, so it does not trigger automatic missing-key insertion.
- `dict_items` behaves like a set only when all values are hashable. Unhashable values make set operations fail.

### Skill Hooks
- Python dict review, mapping API design, `Mapping` vs `dict`
- Missing key handling, `KeyError`, `get`, `setdefault`, `defaultdict`, `__missing__`
- Custom dictionary type, key normalization, subclass `UserDict`
- Dict merge syntax, unpacking mappings, `|`, `|=`, `**`
- Mapping pattern matching, JSON-like records, schema-version dispatch
- `OrderedDict`, `ChainMap`, `Counter`, `MappingProxyType`, `shelve`
- Set membership, deduplication, intersection, union, difference, symmetric difference
- Dict views, `keys()` set operations, `items()` set operations, dynamic views

### Cross-Links
- Chapter 2: sequence patterns and destructuring, extended here with mapping patterns.
- Chapter 7: passing functions such as sort keys as first-class objects.
- Chapter 13: abstract base classes and broader interface checks.
- Chapter 16: operator overloading behind mapping and set operators.
- Chapter 18: `ChainMap` applied to nested-scope interpretation.
- Later object-model material: memory effects of instance `__dict__`, `__slots__`, and the hazards of subclassing built-in containers directly.
