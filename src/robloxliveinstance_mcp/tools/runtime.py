from __future__ import annotations

from typing import Any

from mcp.server.fastmcp import FastMCP

from ..bridge import SessionRegistry
from .common import call


def register(mcp: FastMCP[Any], registry: SessionRegistry) -> None:
    @mcp.tool()
    async def get_runtime_logs(
        tail: int = 100,
        since: int | None = None,
        level: str | None = None,
        filter_text: str | None = None,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Read buffered LogService output with optional level, since, and text filters."""
        return await call(
            registry,
            "get_runtime_logs",
            {
                "tail": max(1, min(tail, 1000)),
                "since": since,
                "level": level,
                "filter_text": filter_text,
            },
            session_id,
        )

    @mcp.tool()
    async def tail_runtime_logs(
        cursor: int | None = None,
        limit: int = 100,
        level: str | None = None,
        filter_text: str | None = None,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Poll log entries after a cursor instead of rereading the whole console buffer."""
        return await call(
            registry,
            "tail_runtime_logs",
            {
                "cursor": cursor,
                "limit": max(1, min(limit, 1000)),
                "level": level,
                "filter_text": filter_text,
            },
            session_id,
        )

    @mcp.tool()
    async def get_client_snapshot(session_id: str | None = None) -> dict[str, Any]:
        """Capture a compact one-call snapshot of player, camera, GUI, input, and key client state."""
        return await call(registry, "get_client_snapshot", session_id=session_id)

    @mcp.tool()
    async def get_memory_stats(
        tags: list[str] | None = None,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Read total memory, per-tag memory, and lightweight client perf estimates."""
        return await call(
            registry,
            "get_memory_stats",
            {"tags": tags},
            session_id,
        )

    @mcp.tool()
    async def get_remote_overview(
        root_ref: str | None = None,
        root_path: str | None = None,
        query: str | None = None,
        limit: int = 200,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Enumerate visible RemoteEvent, RemoteFunction, and UnreliableRemoteEvent instances."""
        return await call(
            registry,
            "get_remote_overview",
            {
                "root_ref": root_ref,
                "root_path": root_path,
                "query": query,
                "limit": max(1, min(limit, 1000)),
            },
            session_id,
        )

    @mcp.tool()
    async def get_tagged_instances(
        tags: list[str] | None = None,
        tag: str | None = None,
        class_name: str | None = None,
        limit: int = 200,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """List CollectionService-tagged instances for one or more tags."""
        return await call(
            registry,
            "get_tagged_instances",
            {
                "tags": tags,
                "tag": tag,
                "class_name": class_name,
                "limit": max(1, min(limit, 1000)),
            },
            session_id,
        )

    @mcp.tool()
    async def get_streaming_diagnostics(
        radius: int = 256,
        tags: list[str] | None = None,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Summarize streaming settings and nearby client-visible streamed content."""
        return await call(
            registry,
            "get_streaming_diagnostics",
            {"radius": max(1, min(radius, 5000)), "tags": tags},
            session_id,
        )

    @mcp.tool()
    async def capture_screenshot(
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Capture a screenshot when the attached executor exposes a screenshot API."""
        return await call(registry, "capture_screenshot", session_id=session_id)

    @mcp.tool()
    async def get_service_overview(
        limit: int = 50,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Read a compact summary of top-level client-visible services and counts."""
        return await call(
            registry,
            "get_service_overview",
            {"limit": max(1, min(limit, 200))},
            session_id,
        )
