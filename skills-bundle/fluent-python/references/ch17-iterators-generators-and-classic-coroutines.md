## Chapter 17: Iterators, Generators, and Classic Coroutines
### Core Ideas
- Python iteration is protocol-driven: `iter(x)` first asks for `__iter__`, can fall back to indexed `__getitem__`, and otherwise raises `TypeError`.
- Iterables and iterators are different roles. An iterable should create a fresh iterator. An iterator implements `__next__` and returns itself from `__iter__`.
- Exhaustion is represented by `StopIteration`. Once an iterator is drained, it is not reset by calling `iter()` on that same iterator.
- Generator functions and generator expressions are compiler-built iterators, letting code replace manual iterator state machines with `yield` or a short expression.
- Laziness is central: functions such as `re.finditer`, generator expressions, and many `itertools` helpers produce values only when consumed.
- Standard-library iterator tools cover filtering, mapping, merging, expanding, rearranging, and reducing streams. Many can be chained into memory-efficient pipelines.
- `yield from` delegates a generator's output to another iterable or subgenerator and can also receive a subgenerator's final return value.
- Classic coroutines are generator objects driven with `.send()`, `.close()`, and sometimes `yield from`. They share mechanics with generators but serve a different design purpose.

### Practitioner Guidance
- When reviewing iterable classes, check that `__iter__` returns a new independent iterator unless the object is explicitly an iterator.
- Prefer a generator function for custom traversal logic. Use a generator expression only when the transformation is short and readable.
- Reach for `itertools`, built-ins like `zip`, `enumerate`, `map`, `filter`, `all`, `any`, and `sum`, or file/object iteration before writing custom loop machinery.
- Use lazy regex/file/data iteration when the input may be large or when callers may only consume a prefix.
- Bound infinite iterators with tools such as `islice`, `takewhile`, a sentinel iterator, or an explicit break before collecting or reducing.
- Annotate inputs broadly as `Iterable[T]` when a function only loops over values. Use `Iterator[T]` or `Generator[...]` only when the consumed object semantics matter.
- Treat `Generator[Y, S, R]` as coroutine-level detail: `Y` is yielded, `S` is sent in, and `R` is returned through generator termination.
- Prefer native coroutines and `async`/`await` for modern async code. Keep classic coroutine usage localized to legacy code, frameworks, or teaching/debugging of generator mechanics.

### Pitfalls
- Making a collection object its own iterator breaks repeated or nested traversal because all consumers share one cursor.
- Testing only with `isinstance(x, Iterable)` can miss legacy sequence-like objects. Calling `iter(x)` is the operational check.
- Calling `list()`, `sorted()`, `sum()`, or similar reducers on an unbounded iterator can hang or exhaust memory.
- `groupby` groups adjacent runs, not all equal keys globally. Sort or cluster first when global grouping is intended.
- Sending a non-`None` value to a coroutine before it reaches its first `yield` fails. It must be primed first.
- Mixing iterator-style generators and coroutine-style `.send()` protocols makes control flow and type hints hard to reason about.

### Skill Hooks
- iterator protocol, iterable protocol, `iter()`, `next()`, `StopIteration`
- `__iter__`, `__next__`, `__getitem__` fallback, custom iterable review
- generator function, generator expression, lazy evaluation
- streaming files, regex matches, large datasets, memory-efficient pipelines
- `itertools`, `functools.reduce`, `zip(strict=True)`, `enumerate`, `all`, `any`
- infinite iterators, sentinel iterators, `iter(callable, sentinel)`
- `yield from`, subgenerator delegation, recursive generator traversal
- classic coroutine, `.send()`, `.close()`, coroutine priming, `Generator[Y, S, R]`

### Cross-Links
- Chapter 1: special methods and why sequence-like objects participate in iteration.
- Chapter 2: sequence behavior, comprehensions, generator expressions, and tuple typing contrasts.
- Chapter 8: function annotations and `Iterable`-oriented API signatures.
- Chapter 9: closures versus coroutine-local state for accumulating values.
- Chapter 12: generator expressions in vector operations and custom sequence behavior.
- Chapter 13: ABCs, structural checks, and `collections.abc.Iterable` / `Iterator`.
- Chapter 15: variance in generic types, especially coroutine `Generator` parameters.
- Chapter 21: native coroutines and `async` / `await`, the modern successor to classic coroutine patterns.
