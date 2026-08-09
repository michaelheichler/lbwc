# Reference index

Chapter map for the **clean-code-principles-python-silen** skill. Load the 1-3 references whose scope
matches the task (full routing table + priority ladder live in `../SKILL.md`). Each reference opens with
a *When this governs* line and a scannable **Principle index**. Read that first.

| Reference | Load it when you are… |
|---|---|
| `ch01-architectural-principles-and-patterns.md` | splitting a system into services/packages, boundaries, externalized config, inter-service comms, versioning, resilience, distributed transactions (saga / CQRS / event sourcing) |
| `ch02-object-oriented-design-principles.md` | designing OO Python: SOLID, controller→service→repository layering, DI, type/method naming, *don't-ask-tell*, Law of Demeter, primitive obsession |
| `ch02-design-patterns.md` | choosing a design pattern (creational / structural / behavioral), done Pythonically |
| `ch02-tactical-ddd.md` | modeling a domain: entities, value objects, aggregates + roots, repositories, services, events, event storming |
| `ch03-coding-principles.md` | writing/reviewing production Python: naming, package structure, comments, returns, type hints, refactoring, error-vs-exception, data structures, optimization |
| `ch04-testing-principles.md` | writing/structuring tests: unit vs integration vs E2E, naming/AAA, mocking seams, what to assert, TDD/BDD/ATDD, refusing untestable designs |
| `ch05-security-principles.md` | code crossing a trust boundary: HTTP, DB, deserialization, subprocess, auth/authz, secrets, passwords, uploads, input validation, threat modeling |
| `ch06-api-design-principles.md` | a service boundary: REST/GraphQL/gRPC controllers, DTOs, the service/repository layers behind them, error→wire mapping, versioning |
| `ch07-databases-and-database-principles.md` | reading/writing a database: store choice, schema/entities, queries, transactions, connections, caching, avoiding N+1 |
| `ch08-concurrent-programming-principles.md` | work across threads/processes/coroutines: model choice, shared data, correctness under races/retries/duplicate delivery, idempotency |
| `ch09-teamwork-principles.md` | code others read: PRs/reviews, definition of done, docs, dependency wrapping, structuring for parallel work, technical debt |
| `ch10-devsecops.md` | shipping a containerized service: CI/CD, Dockerfile, K8s/Helm, health probes, structured logging, metrics/SLIs, security scanning |

For language mechanics behind any of these (Protocols vs ABCs, dataclasses, decorators, generators,
`asyncio`, descriptors, type-hint depth), cross-link to the **fluent-python** skill rather than
re-deriving here.
