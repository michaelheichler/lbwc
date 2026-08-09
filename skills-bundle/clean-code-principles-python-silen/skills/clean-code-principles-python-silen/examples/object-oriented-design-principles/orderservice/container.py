"""Composition root: the only place concrete classes are named (Silen ch02 /
book ch4.6, 4.17).

The book uses the ``dependency-injector`` library and a ``DiContainer``. The
principle survives without the library: a composition root is simply the single
location that knows which concrete implementation satisfies each protocol and
wires the object graph together. Everywhere else, code sees only protocols.

To change behavior (in-memory -> SQL repo, REST -> GraphQL controller), edit
THIS file only, every other module is closed for modification.
"""

from __future__ import annotations

from .controller import OrderController
from .repository import InMemoryOrderRepository, OrderRepository
from .service import OrderService, OrderServiceImpl


def build_controller() -> OrderController:
    # Wire inner-to-outer: repository -> service -> controller.
    repository: OrderRepository = InMemoryOrderRepository()
    service: OrderService = OrderServiceImpl(repository)
    return OrderController(service)
