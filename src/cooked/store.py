"""
Adaptateur Supabase partagé (GSC + DFS ingest).

C7 — une couture store injectable : prod via from_env(), FakeStore en test.
"""
from __future__ import annotations

import os
import sys
from dataclasses import dataclass, field
from typing import Any, Protocol

from supabase import Client, create_client

DEFAULT_SUPABASE_URL = "https://mxycmjkeotrycyneacje.supabase.co"
DEFAULT_BATCH_SIZE = 1000


class RpcResponse(Protocol):
    data: list[dict] | None


class CookedStore(Protocol):
    def upsert_batches(
        self,
        table: str,
        rows: list[dict],
        on_conflict: str,
        batch_size: int = DEFAULT_BATCH_SIZE,
    ) -> None: ...

    def rpc(self, name: str, params: dict[str, Any]) -> RpcResponse: ...


@dataclass
class UpsertCall:
    table: str
    rows: list[dict]
    on_conflict: str


@dataclass
class FakeStore:
    """Store en mémoire pour tests d'orchestration sans credentials."""

    rpc_handlers: dict[str, Any] = field(default_factory=dict)
    upserts: list[UpsertCall] = field(default_factory=list)

    def upsert_batches(
        self,
        table: str,
        rows: list[dict],
        on_conflict: str,
        batch_size: int = DEFAULT_BATCH_SIZE,
    ) -> None:
        for i in range(0, len(rows), batch_size):
            chunk = rows[i : i + batch_size]
            if chunk:
                self.upserts.append(UpsertCall(table, chunk, on_conflict))

    def rpc(self, name: str, params: dict[str, Any]) -> RpcResponse:
        handler = self.rpc_handlers.get(name)
        if callable(handler):
            data = handler(params)
        else:
            data = handler
        return _FakeRpcResponse(data)


@dataclass
class _FakeRpcResponse:
    data: list[dict] | None


class SupabaseStore:
    def __init__(self, client: Client) -> None:
        self._client = client

    @property
    def client(self) -> Client:
        return self._client

    @classmethod
    def from_env(cls) -> SupabaseStore:
        url = os.environ.get("SUPABASE_URL", DEFAULT_SUPABASE_URL)
        key = os.environ.get("SUPABASE_SECRET_KEY")
        if not key:
            sys.exit("ERROR: SUPABASE_SECRET_KEY env var manquante")
        return cls(create_client(url, key))

    def upsert_batches(
        self,
        table: str,
        rows: list[dict],
        on_conflict: str,
        batch_size: int = DEFAULT_BATCH_SIZE,
    ) -> None:
        if not rows:
            return
        for i in range(0, len(rows), batch_size):
            self._client.table(table).upsert(
                rows[i : i + batch_size], on_conflict=on_conflict
            ).execute()

    def rpc(self, name: str, params: dict[str, Any]) -> RpcResponse:
        return self._client.rpc(name, params).execute()
