"""Use-case layer: the service (Silen ch02 / book ch4.6, 4.12).

A service orchestrates operations on aggregate ROOTS and uses a repository for
persistence. One method == one use case (one DDD event): create_order,
get_order, ... The service is the facade the controllers talk to.

It depends on the ``OrderRepository`` PROTOCOL (constructor-injected), never a
concrete repository. That inversion is what makes the use case unit-testable
with a fake repo and storage-agnostic in production.
"""

from __future__ import annotations

from typing import Protocol

from .dtos import InputOrder, OutputOrder, OutputOrderItem
from .entities import Money, Order, OrderItem
from .errors import EntityNotFoundError
from .repository import OrderRepository


class OrderService(Protocol):
    def create_order(self, input_order: InputOrder) -> OutputOrder: ...
    def get_order(self, order_id: int) -> OutputOrder: ...


class OrderServiceImpl:
    def __init__(self, repository: OrderRepository) -> None:
        self._repository = repository  # injected protocol, not a concrete DB

    def create_order(self, input_order: InputOrder) -> OutputOrder:
        order = Order(id=0, user_id=input_order.user_id)
        for index, item in enumerate(input_order.items, start=1):
            # Tell the aggregate root to add the item, never poke its list.
            order.add_item(
                OrderItem(
                    id=index,
                    sales_item_id=item.sales_item_id,
                    quantity=item.quantity,
                    unit_price=Money(item.unit_price_cents),
                )
            )
        saved = self._repository.save(order)
        return self._to_output(saved)

    def get_order(self, order_id: int) -> OutputOrder:
        order = self._repository.find(order_id)
        if order is None:
            raise EntityNotFoundError("Order", order_id)
        return self._to_output(order)

    @staticmethod
    def _to_output(order: Order) -> OutputOrder:
        return OutputOrder(
            id=str(order.id),
            user_id=str(order.user_id),
            items=[
                OutputOrderItem(
                    id=str(item.id),
                    sales_item_id=str(item.sales_item_id),
                    quantity=item.quantity,
                )
                for item in order.items
            ],
            total_cents=order.total().cents,
        )
