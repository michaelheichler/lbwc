"""Input interface adapter: controller (Silen ch02 / book ch4.6).

A controller adapts an input technology (REST, GraphQL, gRPC, CLI...) to the
service's use cases. The book ships FastAPI and Flask versions of exactly this
class. The lesson is that the controller depends only on the ``OrderService``
protocol, so the API technology is a swappable outer-layer detail.

This minimal version exposes plain methods (a CLI/in-process adapter). A REST
controller would map the same calls to HTTP routes, and translating
``OrderServiceError.status_code`` to a response is the controller's job, not
the core's.
"""

from __future__ import annotations

from .dtos import InputOrder, OutputOrder
from .service import OrderService


class OrderController:
    def __init__(self, service: OrderService) -> None:
        self._service = service  # injected protocol, not OrderServiceImpl

    def create_order(self, input_order: InputOrder) -> OutputOrder:
        return self._service.create_order(input_order)

    def get_order(self, order_id: int) -> OutputOrder:
        return self._service.get_order(order_id)
