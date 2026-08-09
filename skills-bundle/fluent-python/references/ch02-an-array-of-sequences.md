## Chapter 2: An Array of Sequences
### Core Ideas
- Python sequences share common operations across many types: iteration, indexing, slicing, concatenation, sorting, and unpacking.
- Sequence choice has two important axes: mutable versus immutable, and container-style references versus flat value storage.
- List comprehensions are for building lists clearly, while generator expressions stream values into constructors, loops, or consumers without materializing an intermediate list.
- Tuples serve both as positional records and as fixed-length sequences. Their immutability only protects the stored references, not mutable objects behind those references.
- Iterable unpacking, starred targets, nested unpacking, and function-call unpacking reduce manual indexing and make record-shaped data easier to read.
- Python 3.10 sequence patterns extend unpacking into `match/case`, adding shape checks, literal checks, type checks, guards, wildcards, and binding with `as`.
- Slices are real `slice` objects under the syntax. Named slices can clarify fixed-width parsing, and slice assignment can edit mutable sequences in place.
- Lists are not always the right structure: `array.array`, `memoryview`, NumPy arrays, `collections.deque`, and queue modules fit specialized numeric, binary, endpoint-access, or concurrency needs.

### Practitioner Guidance
- Choose the sequence type from the workload: `list` for general mutable ordered data, `tuple` for fixed records or fixed collections, `array.array` for homogeneous numeric storage, `deque` for fast endpoint operations, and NumPy for heavy numeric arrays.
- Prefer a list comprehension when the goal is a new list, and prefer a generator expression when a consumer can pull items lazily or when feeding a non-list constructor.
- Review tuple-as-record code for unpacking instead of numeric indexes. Positional fields become safer when names are assigned at the boundary.
- Use `match/case` when code branches by sequence shape, command messages, AST-like data, or protocol records, and include a catch-all case to avoid silent no-ops.
- Treat `_` carefully: it is only a convention in assignment, but it is a real wildcard in pattern matching.
- Use named `slice` instances for fixed-column data or repeated slice boundaries instead of scattering numeric offsets.
- Pick `sorted(iterable, key=...)` when a new list is desired or the input is not a list, and use `list.sort(...)` only for deliberate in-place mutation.
- For large numeric datasets, avoid lists of Python number objects when compact arrays, binary I/O, memory views, memory maps, or vectorized libraries would better match the scale.

### Pitfalls
- `[[...]] * n` duplicates references to one inner list. Use a comprehension when each row or bucket must be independent.
- Tuples containing mutable objects can change in observable value and may fail hashing, so they are risky as dict keys or set elements.
- Augmented assignment on nested mutable items can partially mutate data before raising an error, especially with immutable outer containers.
- `+=` and `*=` may mutate in place for mutable sequences but rebind a new object for immutable ones. Do not assume identity is preserved.
- Sequence patterns do not destructure arbitrary iterators, and `str`, `bytes`, and `bytearray` are treated as atomic subjects unless explicitly converted.
- `list.sort()` returns `None`. Chaining or assigning its result is usually a bug.

### Skill Hooks
- sequence protocol, built-in sequences, `collections.abc.Sequence`, mutable sequence, immutable sequence
- container sequence, flat sequence, memory layout, homogeneous numeric data
- list comprehension, generator expression, comprehension readability, `map` versus comprehension, `filter` versus comprehension
- Cartesian product, nested loops in comprehensions, lazy construction
- tuple records, tuples as immutable lists, tuple hashability, shallow immutability
- iterable unpacking, starred assignment, nested unpacking, function argument unpacking
- `match/case`, sequence patterns, destructuring, wildcard `_`, guard clauses, type patterns, catch-all case
- slicing, `slice()` objects, named slices, stride, negative step, multidimensional slicing, ellipsis
- slice assignment, `del` with slices, sequence concatenation, repeated sequence multiplication
- list-of-lists aliasing, augmented assignment, `__iadd__`, `__imul__`, tuple mutation puzzler
- `sorted`, `list.sort`, stable sort, `key=`, `reverse=`
- `array.array`, `memoryview`, buffer protocol, NumPy array, memory-mapped array
- `collections.deque`, FIFO queue, endpoint operations, thread-safe queue, priority queue, heap queue

### Cross-Links
- Chapter 1: sequence protocol behavior in user-facing objects such as card decks.
- Chapter 3: sets and mappings, especially membership-oriented collections and mapping unpacking.
- Chapter 4: Unicode text, `bytes`, `bytearray`, and binary sequence handling.
- Chapter 5: named tuples, `typing.NamedTuple`, and dataclasses for records with field names.
- Chapter 6: references, aliasing, and mutable object behavior.
- Chapter 7: deeper treatment of `map`, `filter`, and functional tools.
- Chapter 12: implementing custom sequence types and slicing support.
- Chapter 13: sequence ABCs and virtual subclassing.
- Chapter 16: operator special methods behind concatenation and augmented assignment.
- Chapter 17: generators and lazy iteration mechanics.
