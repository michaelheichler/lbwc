"""Demonstrates: Avoid technical debt by making 3rd-party components replaceable.

The chapter lists "not easy to replace a 3rd-party component" as a top source of
technical debt. The fix is the adapter pattern + dependency injection: code
against a Protocol your team owns, not against a vendor's concrete API. Swapping
the vendor then means writing one new adapter class, not editing call sites
scattered across the codebase.

Here the "vendor SDKs" are stubbed so the file runs with no install.
"""

from __future__ import annotations

from typing import Protocol


# --- The seam your team OWNS: domain-level interface, vendor-agnostic --------
class ObjectStore(Protocol):
    """What our app needs from blob storage, nothing vendor-specific."""

    def put(self, key: str, data: bytes) -> None: ...

    def get(self, key: str) -> bytes: ...


# --- Stand-in vendor SDKs (imagine: boto3, google-cloud-storage) ------------
class _FakeS3Client:
    def __init__(self) -> None:
        self._store: dict[str, dict[str, bytes]] = {}

    def upload(self, bucket: str, name: str, body: bytes) -> None:
        self._store.setdefault(bucket, {})[name] = body

    def download(self, bucket: str, name: str) -> bytes:
        return self._store[bucket][name]


class _FakeGcsClient:
    def __init__(self) -> None:
        self._blobs: dict[str, bytes] = {}

    def write_object(self, path: str, content: bytes) -> None:
        self._blobs[path] = content

    def read_object(self, path: str) -> bytes:
        return self._blobs[path]


# --- Adapters: one thin class per vendor, isolating its API quirks ----------
class S3Store:
    """Adapts the S3 SDK to ``ObjectStore``."""

    def __init__(self, client: _FakeS3Client, bucket: str) -> None:
        self._client = client
        self._bucket = bucket

    def put(self, key: str, data: bytes) -> None:
        self._client.upload(self._bucket, key, data)

    def get(self, key: str) -> bytes:
        return self._client.download(self._bucket, key)


class GcsStore:
    """Adapts the GCS SDK to ``ObjectStore``, the ONLY file that changes
    when migrating clouds. No business code below the seam is touched."""

    def __init__(self, client: _FakeGcsClient, prefix: str) -> None:
        self._client = client
        self._prefix = prefix

    def put(self, key: str, data: bytes) -> None:
        self._client.write_object(f"{self._prefix}/{key}", data)

    def get(self, key: str) -> bytes:
        return self._client.read_object(f"{self._prefix}/{key}")


# --- Business logic: depends on the Protocol, injected, never on a vendor ----
def archive_report(store: ObjectStore, report_id: str, body: bytes) -> str:
    """Persist a report and return its storage key. Cloud-agnostic by design."""
    key = f"reports/{report_id}.bin"
    store.put(key, body)
    return key


if __name__ == "__main__":
    # Swapping vendors = swapping the injected adapter, logic is unchanged.
    on_s3: ObjectStore = S3Store(_FakeS3Client(), bucket="prod")
    on_gcs: ObjectStore = GcsStore(_FakeGcsClient(), prefix="prod")

    for store in (on_s3, on_gcs):
        key = archive_report(store, "q3", b"...payload...")
        assert store.get(key) == b"...payload..."
        print(f"{type(store).__name__}: stored at {key}")
