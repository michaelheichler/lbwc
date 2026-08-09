"""Entry point exercising the full clean-microservice slice (Silen ch02 / book
ch4.6).

Run from the examples directory:
    python -m orderservice.app

It builds the object graph at the composition root, then drives a use case
end-to-end through every layer, demonstrating that the layers compose without
any of them importing a layer further out.
"""

from __future__ import annotations

from .container import build_controller
from .dtos import InputOrder, InputOrderItem
from .errors import OrderServiceError


def main() -> None:
    controller = build_controller()

    created = controller.create_order(
        InputOrder(
            user_id=42,
            items=[
                InputOrderItem(sales_item_id=1001, quantity=2, unit_price_cents=599),
                InputOrderItem(sales_item_id=1002, quantity=1, unit_price_cents=1299),
            ],
        )
    )
    print("created:", created)

    fetched = controller.get_order(int(created.id))
    print("fetched total cents:", fetched.total_cents)

    try:
        controller.get_order(9999)
    except OrderServiceError as err:
        print(f"error {err.status_code}: {err.message}")


if __name__ == "__main__":
    main()
