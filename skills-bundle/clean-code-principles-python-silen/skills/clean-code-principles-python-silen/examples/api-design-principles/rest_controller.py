"""REST controller + service + DI + error-to-HTTP mapping
(Silen ch06 / book ch8.1.2, 8.1.2.11).

Principles shown:

- The controller is THIN: it parses/validates input (pydantic does it), calls
  the service, and shapes the HTTP response. No business logic lives here.
- Correct REST verbs/status codes: POST -> 201 + body, GET -> 200,
  PUT -> 204, DELETE -> 204 and idempotent (already-deleted is still 204).
- A SINGLE exception handler maps every ``ApiError`` to the shared error
  envelope. Handlers raise domain errors, the framework boundary translates
  them to HTTP. The service/repository never import FastAPI.
- Dependencies are injected, not constructed inside the controller, so the
  whole stack is testable with fakes.

Requires fastapi. If absent, the module still imports its collaborators and
the ``# noqa`` is unnecessary. Run under uvicorn for a live server.

Run: uvicorn rest_controller:app
"""

from __future__ import annotations

import sqlite3
from typing import Protocol

from dtos import InputSalesItem, OutputSalesItem, to_output
from errors import ApiError, EntityNotFoundError, to_error_envelope
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from repository import SalesItemRepository, SqliteSalesItemRepository


# --- service layer: depends on the repository ABSTRACTION ------------------
class SalesItemService(Protocol):
    def create(self, item: InputSalesItem) -> OutputSalesItem: ...
    def list_all(self) -> list[OutputSalesItem]: ...
    def get(self, item_id: str) -> OutputSalesItem: ...
    def update(self, item_id: str, item: InputSalesItem) -> None: ...
    def delete(self, item_id: str) -> None: ...


class SalesItemServiceImpl(SalesItemService):
    def __init__(self, repository: SalesItemRepository) -> None:
        self._repo = repository

    def create(self, item: InputSalesItem) -> OutputSalesItem:
        return to_output(self._repo.save(item))

    def list_all(self) -> list[OutputSalesItem]:
        return [to_output(e) for e in self._repo.find_all()]

    def get(self, item_id: str) -> OutputSalesItem:
        entity = self._repo.find(item_id)
        if entity is None:
            # Domain error, NOT HTTPException: the web layer maps it later.
            raise EntityNotFoundError("Sales item", item_id)
        return to_output(entity)

    def update(self, item_id: str, item: InputSalesItem) -> None:
        if self._repo.find(item_id) is None:
            raise EntityNotFoundError("Sales item", item_id)
        self._repo.update(item_id, item)

    def delete(self, item_id: str) -> None:
        self._repo.delete(item_id)  # idempotent


# --- composition root: wire concrete dependencies once ---------------------
def build_service() -> SalesItemService:
    repo = SqliteSalesItemRepository(sqlite3.connect(":memory:"))
    return SalesItemServiceImpl(repo)


service = build_service()
app = FastAPI()


# --- single boundary: domain error -> HTTP, once for the whole API ---------
@app.exception_handler(ApiError)
def handle_api_error(_request: Request, error: ApiError) -> JSONResponse:
    # One place to log error.cause and bump a failure counter labelled by
    # error.code. Every endpoint inherits consistent error responses.
    return JSONResponse(status_code=error.status_code, content=to_error_envelope(error))


# --- thin endpoints: verb + status code only ------------------------------
@app.post("/sales-items", status_code=201, response_model=OutputSalesItem)
def create_sales_item(item: InputSalesItem) -> OutputSalesItem:
    return service.create(item)


@app.get("/sales-items", response_model=list[OutputSalesItem])
def get_sales_items() -> list[OutputSalesItem]:
    return service.list_all()


@app.get("/sales-items/{item_id}", response_model=OutputSalesItem)
def get_sales_item(item_id: str) -> OutputSalesItem:
    return service.get(item_id)


@app.put("/sales-items/{item_id}", status_code=204)
def update_sales_item(item_id: str, item: InputSalesItem) -> None:
    service.update(item_id, item)


@app.delete("/sales-items/{item_id}", status_code=204)
def delete_sales_item(item_id: str) -> None:
    # Idempotent: 204 even if the item was already gone (never 404 on delete).
    service.delete(item_id)
