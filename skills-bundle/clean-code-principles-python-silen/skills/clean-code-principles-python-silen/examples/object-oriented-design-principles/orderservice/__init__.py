"""Clean microservice design + tactical DDD, runnable (Silen ch02 / book ch4.6,
4.12).

Adapted from the book's FastAPI/SQLAlchemy/dependency-injector ``orderservice``.
Framework and database dependencies are replaced with an in-memory repository
and a hand-rolled composition root so the package runs with the stdlib alone,
while preserving the layering that is the actual lesson:

    controller (input adapter)  ->  service (use case)  ->  repository (output
    adapter)  ->  entities (domain core)

Dependency arrows all point INWARD toward the entities. Every layer depends on
the PROTOCOL of the next layer, never its concrete class, so swapping REST for
GraphQL or SQL for Mongo means adding a class, not editing the core
(open/closed). The only place that names concrete classes is the composition
root in ``container.py``.

Layout:
    entities.py    - Order aggregate root, OrderItem entity, Money value object
    dtos.py        - input/output data carriers crossing the API boundary
    errors.py      - domain error hierarchy mapped to HTTP status codes
    repository.py  - OrderRepository protocol + in-memory implementation
    service.py     - OrderService protocol + use-case implementation
    controller.py  - input adapter translating calls to service use cases
    container.py   - composition root wiring concrete classes together
    app.py         - entry point: `python -m orderservice.app`
"""
