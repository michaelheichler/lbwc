---
name: fluent-python
description: Apply the idioms, design heuristics, and advanced Python guidance from Fluent Python, 2nd edition. Use this skill whenever the user asks to write, review, refactor, debug, or explain nontrivial Python code involving data model protocols, collections, Unicode/text bytes, dataclasses, mutability, first-class functions, decorators, type hints, Pythonic object design, protocols/ABCs, inheritance, operator overloading, iterators/generators, context managers, pattern matching, concurrency, async, properties, descriptors, class decorators, or metaclasses.
---

# Fluent Python

## Purpose

Use this skill to apply Fluent Python-style thinking to practical Python coding and review tasks. The bundled references are chapter-separated paraphrased briefs derived from Fluent Python, 2nd edition, excluding the preface, afterword, and index.

## Source Boundary

Use the references as implementation guidance, not as material to quote. Do not reproduce book prose or copied code listings. When giving examples, write fresh minimal examples tailored to the user's code or question.

Prefer current project constraints and runtime version over any book-era default. The book targets Python 3.10-era features; verify newer typing, concurrency, packaging, or standard-library behavior when version details matter.

## Workflow

1. Classify the Python task by topic.
2. Open `references/index.md` only when you need the chapter map.
3. Load the one to three most relevant chapter reference files.
4. Inspect the user's actual code, tests, traceback, or API contract before recommending changes.
5. Apply the smallest idiomatic improvement that fits the codebase, not the most advanced feature available.
6. Explain tradeoffs in concrete Python terms: protocol behavior, mutability, type-checker surface, performance cost, API ergonomics, and failure modes.

When several chapters match, start with the concrete code/task chapter first, then add typing, concurrency, or metaprogramming references only when the user's question or the inspected code requires them.

## Chapter Routing

Load these references as needed:

- Data model, dunder methods, object protocols, `repr`, truthiness: `references/ch01-the-python-data-model.md`
- Sequence types, comprehensions, unpacking, slicing, pattern matching, `deque`, arrays: `references/ch02-an-array-of-sequences.md`
- Dictionaries, sets, missing keys, mapping patterns, `Counter`, `ChainMap`: `references/ch03-dictionaries-and-sets.md`
- Unicode, encodings, `str` versus `bytes`, normalization, collation: `references/ch04-unicode-text-versus-bytes.md`
- `namedtuple`, `NamedTuple`, `dataclass`, field options, class patterns: `references/ch05-data-class-builders.md`
- References, identity, equality, mutability, copying, mutable defaults: `references/ch06-object-references-mutability-and-recycling.md`
- First-class functions, callables, lambdas, `operator`, `functools.partial`: `references/ch07-functions-as-first-class-objects.md`
- Function type hints, `Any`, `object`, `Protocol`, `Callable`, `TypeVar`: `references/ch08-type-hints-in-functions.md`
- Decorators, closures, `nonlocal`, caches, `singledispatch`: `references/ch09-decorators-and-closures.md`
- Strategy/Command simplification with functions and callbacks: `references/ch10-design-patterns-with-first-class-functions.md`
- Pythonic object design, formatting, hashing, `__slots__`, class methods: `references/ch11-a-pythonic-object.md`
- Custom sequences, slicing, dynamic attributes, aggregate hashing: `references/ch12-special-methods-for-sequences.md`
- Interfaces, duck typing, runtime protocols, ABCs: `references/ch13-interfaces-protocols-and-abcs.md`
- Inheritance, mixins, MRO, `super`, subclassing built-ins: `references/ch14-inheritance-for-better-or-for-worse.md`
- Advanced type hints, generics, variance, overloads, casts, `TypedDict`: `references/ch15-more-about-type-hints.md`
- Operator overloading, reversed operators, augmented assignment, comparisons: `references/ch16-operator-overloading.md`
- Iterators, generators, lazy pipelines, classic coroutines: `references/ch17-iterators-generators-and-classic-coroutines.md`
- `with`, context managers, `else` blocks, structural pattern matching: `references/ch18-with-match-and-else-blocks.md`
- Concurrency models, GIL, threads, processes, async architecture choices: `references/ch19-concurrency-models-in-python.md`
- `concurrent.futures`, executors, futures, process pools, progress: `references/ch20-concurrent-executors.md`
- `asyncio`, `async`/`await`, async context managers, async iterators: `references/ch21-asynchronous-programming.md`
- Dynamic attributes, properties, validation, cached properties: `references/ch22-dynamic-attributes-and-properties.md`
- Descriptors, managed attributes, methods as descriptors: `references/ch23-attribute-descriptors.md`
- Class factories, `__init_subclass__`, class decorators, metaclasses: `references/ch24-class-metaprogramming.md`

## Review Heuristics

- Prefer protocol-based designs over ad hoc method names when Python syntax or built-ins already define the contract.
- Prefer composition and existing standard-library tools before custom containers, custom ABCs, descriptors, or metaclasses.
- Treat mutability and aliasing as API design issues. Copy defensively only when ownership should not be shared.
- Use advanced typing to clarify relationships that matter to callers; avoid hints that force needless rigidity or spread `Any`.
- Reach for decorators, descriptors, and metaprogramming only when they remove repeated, error-prone code or match a clear framework pattern.
- Choose concurrency by workload and integration model: threads for blocking I/O, processes for CPU-bound parallelism, async for high-concurrency I/O with compatible libraries.

## Output Style

When reviewing code, lead with concrete findings and file/line references. When explaining concepts, tie them to a practical example. When refactoring, preserve behavior unless the user explicitly asks for a redesign.
