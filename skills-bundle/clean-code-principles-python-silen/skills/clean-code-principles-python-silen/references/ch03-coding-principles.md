# ch03: Coding Principles

> When this governs: writing or reviewing any production Python, choosing names, structuring a repo/package, deciding whether to comment, shaping function returns, adding type hints, refactoring smells, handling errors, picking data structures, and optimizing. This is the "write correct, readable Python" layer. Language mechanics live in the `fluent-python` skill.

## Principle index

- **Uniform naming**, Name should reveal purpose and type, infer-able at the call site.
- **Repo structure**, Use one uniform repo layout per tech stack.
- **Domain-based source tree**, Group modules by domain, not by technical role.
- **Avoid comments**, Encode intent in names, types, constants, functions, not comments.
- **Single return**, Return one named value at the end, communicate primitive meaning.
- **Type annotations for production**, Annotate all production code, untyped only for throwaway tests.
- **Refactoring**, Budget time to refactor, never ship first-draft structure.
- **Static analysis**, Run multiple linters/formatters/type checkers in CI.
- **Error vs exception**, Errors are expected and handled, exceptions are bugs caught at boundaries.
- **`try_` prefix**, Prefix any function that can raise or propagate an error.
- **Avoid off-by-one**, Iterate collections directly, use negative indices, not length arithmetic.
- **Be critical of web/AI code**, Treat copied/LLM code as draft, add error handling and tests.
- **One change at a time**, Make one isolated change, never mix feature and refactor.
- **Appropriate data structure**, Pick the structure by access pattern, not habit.
- **Optimization**, Measure first, optimize only busy loops, avoid premature optimization.

## Principles

### Uniform naming

- **Rule:** Make every name communicate the variable's purpose and its type.
- **Why:** Python infers types and the annotation is invisible at most call sites. A name like `failures` reads as a list, so a count silently confuses readers and reviewers.
- **Python:**
  ```python
  # ✗ bare plural reads as a collection, passive noun reads as an object
  failures = count_failures(log)          # int? list?
  inserted_field = insert(field)          # a field, or a yes/no?

  # ✓ name carries the type and the predicate
  failure_count: int = count_failures(log)
  field_was_inserted: bool = insert(field)
  customer_name_to_order_count: dict[str, int] = {}   # key_to_value
  tooltip_delay_in_ms: int = 250                        # unit when not obvious
  year = int(year_as_string)                            # string holding a number
  ```
  Conventions: counts → `<thing>_count` / `number_of_<thing>`, collections → plural noun (no `_list`/`_set`), dicts → `key_to_value`, booleans → a yes/no statement (`pool_is_full`, not `is_pool_full` when the `if` reads better inverted), strings holding non-strings → `<value>_as_string`, units → `_in_ms`, `_percent`. Pick one domain term and use it everywhere (not message/report/record/data for one thing).
- **Anti-slop:** LLMs emit `data`, `result`, `temp`, `items`, single-letter loop vars, and `is_x` booleans even when the surrounding `if` reads worse for it. Prefer `_` for unused loop vars.
- **See also:** `examples/coding-principles/naming.py`, fluent-python ch05 (dataclasses/NamedTuple for grouping named values).

### Repo structure

- **Rule:** Keep a single uniform repository layout per technology stack.
- **Why:** A predictable tree lets any developer find CI/CD, docker, helm, env, and `src` instantly. Divergent layouts waste onboarding time and hide files.
- **Python:** Top-level dirs like `cicd/`, `docker/`, `docs/`, `env/`, `helm/`, `integration-tests/`, `scripts/`, `src/`, plus `.gitignore`, linter config, `README`. Keep unit-test modules beside the code they test (or in a parallel `tests/`). Seed it from a starter-project template repo so every service matches.
- **Anti-slop:** Do not invent ad-hoc top-level folders per project. Reuse the team template.

### Domain-based source tree

- **Rule:** Structure the source tree primarily by domain, with each directory having one responsibility at its level.
- **Why:** Grouping by technical role (`controllers/`, `entities/`, `repositories/`) scatters one feature across six folders. Grouping by domain co-locates everything for a change and keeps each directory to ~2-5 files (max 5-7) so it is scannable.
- **Python:**
  ```
  # ✗ by technical role            ✓ by domain
  src/controllers/AController.py    src/domain_a/controller.py
  src/entities/AEntity.py           src/domain_a/entity.py
  src/repositories/ARepository.py   src/domain_a/repository.py
  ```
  For clean-architecture style, split a domain into `businesslogic/` (entities, services, ports) and `ifadapters/` (Flask/SQL/Kafka adapters) so swapping an adapter never touches business logic.
- **Anti-slop:** LLMs default to the role-based layout (`models/`, `views/`, `services/`). Prefer domain folders unless the project already uses role-based.

### Avoid comments

- **Rule:** Replace comments with better names, type hints, named constants, and extracted functions. Reserve docstrings for library public APIs.
- **Why:** Comments are not checked by the compiler/tests and rot independently of the code. Readers trust the code, so a stale comment actively misleads. Only generated library API docs justify them.
- **Python:**
  ```python
  # ✗ comment patches a vague name and a magic check
  def write(self, m: Message) -> bool:   # False if buffer full
      if len(self._msgs) < 200:          # buffer not full
          ...

  # ✓ name + named constant carry the meaning
  def write_if_not_full(self, message: Message) -> bool:
      buffer_has_room = len(self._msgs) < self._max_length
      ...
  ```
  Other moves: magic number → `IntEnum`, "# now do X" block → extracted well-named function, complex boolean → named constant, complex regex → compose from named sub-patterns.
- **Anti-slop:** LLMs sprinkle restating comments (`# increment counter`, `# loop over items`) and TODO/placeholder comments. Delete them. Never comment out dead code (git keeps it).
- **See also:** `examples/coding-principles/avoid_comments.py`.

### Single return

- **Rule:** Prefer one `return` of a named value at the end of a function.
- **Why:** A primitive return (`bool`/`int`) is meaningless until named. A single exit also makes IDE extract-method safe, since a mid-function `return`/`break`/`continue` blocks automated refactoring.
- **Python:**
  ```python
  # ✓ decide, act, then return one named value
  def route_message(result, sink, payload) -> bool:
      if result.was_transformed and result.is_kept:
          sink.append(payload)
      message_was_routed = result.was_transformed
      return message_was_routed
  ```
  Sanctioned exceptions: short guard functions where the name/return type already says it all (and single-return would exceed ~9 statements), and factories returning different subtypes per `match` branch, always with a `case _: raise` default.
- **Anti-slop:** LLMs love early `return`/guard clauses everywhere. They are fine for short, self-describing functions, but for primitive returns prefer one named exit. Keep functions ~5-9 statements so nested ifs never pile up.
- **See also:** `examples/coding-principles/single_return.py`, fluent-python ch02 (`match`).

### Type annotations for production

- **Rule:** Annotate all production code. Leave untyped Python only for throwaway integration/E2E test scripts.
- **Why:** Without hints, callers pass args in the wrong order or wrong type, return types get misread, refactoring is manual, and you are forced to write API comments, and unit tests miss these because mocks hide real signatures. Type errors then escape to production.
- **Python:** Use modern forms: `list[str]`, `dict[str, int]`, `X | None`, `Final`, type aliases for opaque primitives (`type CounterIndex = int`). Run a type checker (mypy/pyright) in CI, not just at edit time.
  ```python
  type CounterIndex = int           # alias makes a bare int self-documenting
  def add_counter(family: str, labels: dict[str, str]) -> CounterIndex: ...
  ```
- **Anti-slop:** Do not use bare `dict`/`list`/`Any` or legacy `typing.List`/`Optional[X]` in new code. Do not annotate `-> None` functions as `-> Any`.
- **See also:** fluent-python ch08 (function type hints), ch15 (generics/TypedDict/overload).

### Refactoring

- **Rule:** Reserve time to refactor. No one writes the perfect structure first try.
- **Why:** Skipping refactoring lets technical debt compound, making every later feature slower and buggier. Refactoring changes structure without changing behavior, so most tests stay green.
- **Python:** Smell → fix table, non-descriptive name → rename, long method → extract method, large class → extract class (strategy), complex expression → extract constant, long if/elif on a type → replace conditionals with polymorphism, >5-7 params → introduce parameter object (frozen dataclass), negated condition → invert if, anemic data-bag → rich object (move behavior in, drop getters/setters).
  ```python
  # introduce parameter object
  @dataclass(frozen=True, slots=True)
  class TlsOptions:
      is_used: bool; verify_cert: bool; ca_path: str; cert_path: str; key_path: str
  def connect(brokers: list[str], tls: TlsOptions) -> Conn: ...
  ```
- **Anti-slop:** Do not bundle refactoring with a feature in one diff (see "one change at a time").
- **See also:** `examples/coding-principles/refactoring.py`, fluent-python ch10 (strategy with first-class functions), ch11 (Pythonic object).

### Static analysis

- **Rule:** Let tools find bugs and smells. Run several, because each catches different issues.
- **Why:** Automated checks free human review for design concerns and catch issues testing cannot (broad excepts, mutable-arg leaks, dead code). Infra code (Dockerfile, Helm, Terraform) needs linting too.
- **Python:** Ruff (lint + format), mypy/pyright (types), plus optionally pylint/Sonar. Lint infra with hadolint (Dockerfile), `helm lint`, checkov (Terraform/K8s). Common flagged smells to fix on sight: chain of `isinstance` checks (→ polymorphism), assignment to a function argument, commented-out code, missing `match` default branch, overly broad `except`, returning a mutable internal field, public mutable fields.
- **Anti-slop:** Never silence a linter with a blanket `# noqa`. Fix the cause or suppress the specific rule with justification.

### Error vs exception

- **Rule:** Treat errors as expected outcomes you handle. Treat exceptions as bugs caught only at boundaries.
- **Why:** Mixing the two (catching `Exception`/`BaseException` broadly) swallows real bugs like `MemoryError`/`KeyError` and hides them from the caller. A per-component error hierarchy lets callers catch broad or narrow by intent.
- **Python:**
  ```python
  class DataExporterError(Exception): ...          # component base
  class FileReader:
      class ReadError(DataExporterError): ...       # inferable from method name
      def try_read(self, path: str) -> str:
          try:
              return self._files[path]
          except KeyError as e:
              raise self.ReadError(path) from e     # re-raise as YOUR type
  ```
  Catch broad (`except DataExporterError`) for one handler over several calls. Catch `BaseException` only in `main()`/request loop, then log + exit/continue. Returning errors (bool flag, `T | None`, error object, `(value, error)` tuple, or a `Failable`/`Either`) is a valid alternative when raising would force nested ifs.
- **Anti-slop:** LLMs write bare `except:` / `except Exception: pass`, drop `from e` chaining, and re-raise without context. Always chain and use the narrowest type.
- **See also:** `examples/coding-principles/error_handling.py`, fluent-python ch18 (`with`/`match`/`else`).

### `try_` prefix

- **Rule:** Prefix any function that can raise or propagate an error with `try_`.
- **Why:** Nothing in a signature reveals that a call can raise. The prefix makes the risk visible at the call site so callers cannot silently forget a try/except. A function that calls a `try_*` outside a try/except also propagates and must be `try_`-named.
- **Python:**
  ```python
  def try_fetch(self, path: str) -> dict[str, Any]:   # propagates -> try_ prefix
      config_string = self._reader.try_read(path)     # both calls can raise
      return self._parser.try_parse(config_string)
  ```
  Wrap a non-conforming third-party call in a `try_*` adapter that re-raises your error type. Opt out when a web framework's error handler catches everything anyway.
- **Anti-slop:** Do not name a raising function `get_config`/`load`. Reserve plain names for non-raising functions and adapters that return `T | None`.

### Avoid off-by-one

- **Rule:** Iterate collections directly and use negative indices. Never hand-roll index arithmetic over `len`.
- **Why:** `range` is zero-based and half-open and slices are exclusive at the end, so `values[len(values)-1]` and `index <= len` style loops are classic +/-1 bugs. Edge-case unit tests catch the rest.
- **Python:**
  ```python
  last = values[-1]            # not values[len(values) - 1]
  body = values[:-1]           # all but last, no arithmetic
  for value in values: ...     # not range(len(values))
  ```
- **Anti-slop:** LLMs emit `for i in range(len(x)): x[i]` and `x[len(x)-1]`. Prefer direct iteration, `enumerate`, and negative indexing.
- **See also:** `examples/coding-principles/off_by_one_and_structures.py`, fluent-python ch02 (slicing/unpacking).

### Be critical of web/AI code

- **Rule:** Treat code copied from the web or generated by an LLM as a draft to verify, not authority.
- **Why:** Snippets and AI output skip error handling, target stale library versions, and can be subtly reordered/wrong. Pasted "happy path" code reaches production without the failure handling it needs.
- **Python:** After pasting, walk each line and ask what error it can raise (network, parse, key, index), add handling, and write unit tests for timeout/error-status/parse-failure scenarios (TDD is the durable fix). Verify the library version matches your `pyproject`.
- **Anti-slop:** Do not reproduce a library README's happy-path call (`r = requests.get(url); r.json()`) without `raise_for_status()` and except blocks.

### One change at a time

- **Rule:** Make a single isolated change. Never mix two features or a feature and a refactor.
- **Why:** Bundled changes obscure which one introduced a bug, multiplying debugging effort. Small isolated diffs localize blame and review.
- **Python:** Refactor first in its own commit if it eases the feature, then implement the feature in a second commit. Park unrelated ideas in a TODO/backlog rather than doing them inline.
- **Anti-slop:** Do not "while I'm here" tidy unrelated code inside a feature change.

### Appropriate data structure

- **Rule:** Pick the data structure by its access pattern and cost, not by habit.
- **Why:** Using a `list` for membership tests is O(n) per check and `list.pop(0)` is O(n). The right structure turns these into O(1) and removes whole classes of bugs (e.g. `Counter` returns 0, not `KeyError`).
- **Python:** list = ordered, duplicates, index access, dict = O(1) key lookup, set/frozenset = O(1) membership, dedup, tuple = immutable ordered, `collections.deque` = O(1) both-ends queue/stack, `Counter` = tallies, `OrderedDict` = explicit insertion-order semantics, `queue.Queue`/`PriorityQueue` = thread-safe, numpy = numeric crunching. Subclass `UserList`/`UserDict`/`UserString` to customize a builtin.
  ```python
  if target in candidate_set: ...        # O(1), not `in some_list`
  queue: deque[str] = deque(items); queue.popleft()   # O(1) FIFO
  Counter(words)["missing"]               # -> 0, never KeyError
  ```
- **Anti-slop:** LLMs default to `list` for everything and `list.pop(0)` for queues. Reach for `set`/`deque`/`Counter`.
- **See also:** `examples/coding-principles/off_by_one_and_structures.py`, fluent-python ch03 (dicts/sets), ch01/ch12 (sequence protocol).

### Optimization

- **Rule:** Measure first. Optimize only proven hotspots (busy loops). Avoid premature optimization.
- **Why:** Premature optimization distorts the object-oriented design for no measured gain. Shaving 100ms off once-per-startup config parsing is wasted effort, while a busy loop running thousands of times per second is where it counts.
- **Python:** Measure, then apply the cheapest applicable pattern: remove unnecessary work, generator expression instead of a materialized list when streaming once, `functools.cache`/`lru_cache` for expensive pure functions, object pool to reduce GC churn in hot loops, lower algorithmic complexity (set membership over list scan), buffered file I/O for large files, flyweight to share identical sub-objects, numpy for number crunching.
  ```python
  values = (v * v for v in range(20_000))   # generator: O(1) memory, streamed

  @cache
  def fib(n: int) -> int: ...               # memoize a pure function
  ```
- **Anti-slop:** Do not micro-optimize cold paths or replace clear code with cryptic tricks before profiling.
- **See also:** `examples/coding-principles/off_by_one_and_structures.py`, fluent-python ch17 (generators), ch07 (`functools`).

## Anti-slop checklist

- No vague names (`data`, `result`, `temp`, `items`, single letters). Counts are `*_count`, booleans state yes/no, dicts are `key_to_value`.
- No restating or placeholder comments, no commented-out code. Encode intent in names/types/constants/functions. Docstrings only for library public APIs.
- No bare `except:` / `except Exception: pass`. Catch the narrowest type, chain with `from e`, re-raise as your component's error type.
- No `range(len(x))` indexing or `x[len(x)-1]`. Iterate directly, use `enumerate` and negative indices/slices.
- No `list` for membership tests or `list.pop(0)` queues. Use `set`/`deque`/`Counter`.
- No legacy typing (`typing.List`, `Optional[X]`) or bare `dict`/`list`/`Any` in new code. Use `list[str]`, `X | None`, aliases.
- No premature optimization or cryptic one-liners. No micro-optimizing cold paths.
- No mixing a feature with an unrelated refactor in one diff.
- No reproducing library happy-path snippets without `raise_for_status()` / error handling.
- No raising function named like a plain getter. Prefix with `try_`.
- Factories and `match` statements always have a `case _: raise` default.

## Bundled examples

| Example file | Principle(s) demonstrated |
|---|---|
| `examples/coding-principles/naming.py` | Uniform naming (counts, collections, dicts, booleans, string-as-number, units) |
| `examples/coding-principles/avoid_comments.py` | Avoid comments (rename, named constant, IntEnum, extract function) |
| `examples/coding-principles/single_return.py` | Single named return, sanctioned factory/`match` exception |
| `examples/coding-principles/error_handling.py` | Error hierarchy, `try_` prefix, narrow catch + chaining, library-error wrapping |
| `examples/coding-principles/refactoring.py` | Replace conditionals with polymorphism, parameter object, invert if |
| `examples/coding-principles/off_by_one_and_structures.py` | Off-by-one avoidance, appropriate data structures, generator/cache optimization |
