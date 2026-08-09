---
name: clean-code-principles-python-silen
description: >-
  Apply AND enforce the clean-code principles, design patterns, and architecture from Petri Silen's
  "Clean Code: Principles and Patterns, Python Edition" (2024) whenever writing, reviewing, refactoring,
  or designing Python. Use this for ANY non-trivial Python work (naming, functions, classes,
  encapsulation, SOLID, DDD, design patterns, microservice/architecture boundaries, error and exception
  handling, REST/GraphQL/gRPC API design, databases and repositories, concurrency, testing strategy,
  security, and DevSecOps), even when the user never says "clean code". Trigger when asked to write a
  Python module/class/service, review or refactor Python, fix code smells, design an API or data layer,
  structure a project, or make Python "production-quality", "idiomatic", or "maintainable". Ships an
  automatic checker (ruff + mypy + custom AST rules mapped to the book). Run it on every Python change
  and fix until clean so code ships defect-free. Pair with the fluent-python skill for language-idiom depth.
---

# Clean Code: Principles and Patterns (Python), Silen

## Purpose

This skill is the **architecture / design / principles layer** for Python. It distils Petri Silen's
*Clean Code: Principles and Patterns, Python Edition* (2024) into agent-facing references, planted
best-practice example code, and an **automatic enforcement engine**.

It pairs with the **`fluent-python`** skill, which is the **language-idiom layer**:

- *What/why* (this skill): SRP, encapsulation, program-against-interfaces, DDD, error handling across
  layers, API/DB/concurrency/security/test/DevSecOps principles.
- *How in Python* (`fluent-python`): the data model, `Protocol` vs ABC, dataclasses, decorators,
  generators, `asyncio`, descriptors, type-hint mechanics.

When both apply, decide the design here, then reach into `fluent-python` for the exact idiom. Do not
re-derive language mechanics in this skill.

## Source boundary

The references are **paraphrased guidance written fresh** (not the book's prose, and not for quoting).
The examples are **original or substantially rewritten** Python (3.12+, fully type-hinted, linted clean).
When you produce code for a user, write your own fresh code, and cite a principle by name, never paste book
text. See `../../NOTICE.md`.

## The core loop: never ship a Python defect

The reason this skill exists: an agent that *applies* a principle but never *verifies* still ships
defects. So every Python change goes through this loop:

1. **Classify** the task and load the 1-3 relevant references (see Routing).
2. **Apply** the smallest change that satisfies the principle, explain the *why*, don't cargo-cult.
3. **Verify** by running the checker on what you wrote, and **fix until it reports clean**:

   ```bash
   python skills/clean-code-principles-python-silen/scripts/clean_check.py path/to/your_file.py
   ```

   It runs **ruff** (a rule selection mapped to the book) + **mypy** + **custom AST rules** that catch
   the distinctive Silen principles generic linters miss (predicate naming, encapsulation leaks,
   inconsistent return contracts). Every finding names the principle it maps to. `clean` is true only at
   **zero errors and zero warnings**.

   If the MCP server (`mcp-server/`) is connected, call the `check_python` tool instead (same engine).

Treat a non-clean result as unfinished work, not as advice. This loop is what turns "knows the
principles" into "produces clean code every time".

## How to use the references

1. Match the task to a chapter using the Routing table.
2. Read that chapter's **Principle index** first (the scannable map at the top of each reference), then
   only the principle blocks you need.
3. Apply the smallest idiomatic change. Prefer the planted example as a template (see Bundled examples).
4. Run the checker. Fix. Repeat.

References live in `references/`. Each follows the same shape: a *When this governs* line, a
**Principle index**, then per-principle blocks (`Rule` / `Why` / `Python` (✗→✓) / `Anti-slop` /
`See also`), an **Anti-slop checklist**, and a **Bundled examples** table.

## Routing

Load the reference(s) whose *governs* line matches the task. When several match, start with the most
concrete (code/task) chapter, then add the broader ones.

| Chapter | Governs (load it when…) | Reference(s) |
|---|---|---|
| **ch01: Architecture** | splitting a system into services/packages, boundaries, config, comms, versioning, resilience, distributed transactions (saga/CQRS/event sourcing) | `ch01-architectural-principles-and-patterns.md` |
| **ch02: OO Design** | designing OO Python: SOLID, layering (controller→service→repository), DDD aggregates, design-pattern choice, DI, type/method naming | `ch02-object-oriented-design-principles.md` (+ `ch02-design-patterns.md`, `ch02-tactical-ddd.md`) |
| **ch03: Coding** | writing/reviewing production Python: naming, package structure, comments, returns, type hints, refactoring smells, error vs exception, data structures, optimization | `ch03-coding-principles.md` |
| **ch04: Testing** | writing/structuring tests: unit vs integration vs E2E, test naming/AAA, mocking seams, what to assert, refusing untestable designs | `ch04-testing-principles.md` |
| **ch05: Security** | code crossing a trust boundary: HTTP, DB, deserialization, subprocess, auth/authz, secrets, passwords, uploads, input validation | `ch05-security-principles.md` |
| **ch06: API Design** | a service boundary: REST/GraphQL/gRPC controllers, DTOs, the service/repository layers behind them, error→wire mapping | `ch06-api-design-principles.md` |
| **ch07: Databases** | reading/writing a database: store choice, schema/entities, queries, transactions, connections, caching | `ch07-databases-and-database-principles.md` |
| **ch08: Concurrency** | work across threads/processes/coroutines: model choice, shared data, correctness under races/retries/dup delivery | `ch08-concurrent-programming-principles.md` |
| **ch09: Teamwork** | code others read: PRs/reviews, definition of done, docs, dependency wrapping, structuring for parallel work | `ch09-teamwork-principles.md` |
| **ch10: DevSecOps** | shipping a containerized service: CI/CD, Dockerfile, K8s/Helm, health probes, structured logging, metrics/SLIs, scanning | `ch10-devsecops.md` |

## Priority ladder

You can rarely apply everything. The author's own ranking of what pays off most (Conclusion), weight
in this order when trading off:

1. **Readable code**: code is read far more than written. Lean on uniform naming and avoid-comments.
2. **Composition over inheritance**: use inheritance only for a true *is-a*, otherwise inject collaborators.
3. **Encapsulation**: no reflexive getters/setters, behavior beside data, prefer immutability, don't leak state.
4. **Single Responsibility**: one reason to change, at each level (service, class, function).
5. **Program against interfaces**: depend on a `Protocol`/ABC, the prerequisite for the next item.
6. **Open/Closed**: add new classes, don't edit working ones.
7. **TDD (or use-case-driven dev)**: write the test first so edge/failure cases aren't forgotten.
8. **Threat modeling**: surface security failure modes before they ship.
9. **Integration tests as acceptance tests** (BDD/ATDD): specify features so they aren't left untested.

Two design patterns are worth knowing first: **(Abstract) Factory** and **Adapter**. Then Strategy,
Decorator, Proxy, Command, State, Template Method (see `ch02-design-patterns.md`).

## Anti-slop: the Python mistakes to refuse

LLMs (including you) emit these by reflex. Refuse them, the checker flags most. Per-chapter
*Anti-slop checklist* sections hold the full set, this is the high-frequency core:

**Naming & readability**
- Vague names: `data`, `result`, `temp`, `info`, `obj`, `items`, single-letter non-index vars. Name the purpose *and* the type.
- Restating-the-code comments and docstrings that paraphrase the signature. Encode intent in names/types instead.
- Leaving commented-out code in place.

**Functions & types**
- Missing type hints on production code, `Any` as a shrug.
- Boolean functions not phrased as a question (`paid()` → `is_paid()`), boolean flag parameters (use keyword-only or split the function).
- Functions that sometimes `return value` and sometimes fall through to `None` without a `-> X | None` contract.
- Mutable default arguments (`def f(x=[])`, `={}`).

**Objects & encapsulation**
- Auto-generating getters/setters for every attribute (anemic class), pulling state out to compute on it (feature envy) instead of *tell-don't-ask*.
- Returning an internal `list`/`dict`/`set` by reference, assigning a mutable parameter straight onto `self`. Copy at the boundary or expose a read-only view.
- Mutable class attributes shared across instances.
- Subclassing for code reuse where there is no *is-a*, deep inheritance instead of composition/Strategy.

**Errors & boundaries**
- `except:` / `except Exception: pass` / printing the error and continuing. Catch specific exceptions at a boundary. Let bugs surface.
- Leaking stack traces or internals in API responses, no domain exception → HTTP status mapping.

**Security & data**
- SQL/command built by string concatenation or f-strings: parameterize.
- Secrets/hosts/ports hardcoded or defaulted to dev values instead of read from typed, fail-fast config.
- `pickle`/`yaml.load`/`eval` on untrusted input, plaintext or fast-hash passwords (use argon2/bcrypt).
- Serializing entities with `fields="__all__"` / `{**obj.__dict__}` instead of a whitelisted DTO, two services sharing a database.

**Concurrency & ops**
- Shared mutable state without synchronization, assuming the GIL makes compound ops atomic.
- `print()` for diagnostics in a service, awaiting independent calls sequentially instead of `asyncio.gather`.
- Non-idempotent retries/saga compensations.

## Bundled examples

`examples/<chapter-slug>/` holds runnable, type-hinted, lint-clean Python. Use them as templates.
Crown jewels:

- `examples/object-oriented-design-principles/orderservice/`: a layered DDD service (entities, value
  objects, repository `Protocol` + impl, service, DI) demonstrating SOLID + tactical DDD end-to-end.
- `examples/api-design-principles/`: a clean REST controller → service → repository slice with DTO↔entity
  split and domain-error→status mapping.
- `examples/security-principles/`: parameterized queries, password hashing, input validation, safe deserialization.
- `examples/coding-principles/`: naming, returns, error-vs-exception, data-structure choice.

List them programmatically with the MCP `list_examples` tool, or browse `examples/`.

## Enforcement & MCP

- **CLI / skill:** `scripts/clean_check.py <file-or-dir> [--json] [--no-mypy]`: ruff + mypy + custom AST
  rules, principle-linked. Custom rules live in `scripts/ast_rules.py` (e.g. `CCP001` predicate naming,
  `CCP002` leaky getter, `CCP003` mutable-param aliasing, `CCP004` mixed-return contract).
- **MCP server:** `mcp-server/` exposes `check_python`, `search_principles`, `get_principle`,
  `list_principles`, `list_examples`, `get_example`. Connect it (see `mcp-server/README.md`) so the
  verify step is one tool call, and the agent can retrieve a principle mid-task.

The agent contract in one line: **before presenting any Python you wrote or edited, run the checker and
fix every error and warning. When a design choice is non-obvious, consult the relevant principle and say
which one you applied.**
