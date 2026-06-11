from __future__ import annotations

from typing import Any

from mcp.server.fastmcp import FastMCP

from ..bridge import SessionRegistry
from .common import call


def register(mcp: FastMCP[Any], registry: SessionRegistry) -> None:
    @mcp.tool()
    async def watch_instance_changes(
        watch_id: str | None = None,
        ref: str | None = None,
        path: str | None = None,
        property_names: list[str] | None = None,
        include_descendants: bool = False,
        limit: int = 100,
        capacity: int = 200,
        ttl_seconds: int = 120,
        stop: bool = False,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Start or poll a bounded watch for property, ancestry, child, and destroy events."""
        return await call(
            registry,
            "watch_instance_changes",
            {
                "watch_id": watch_id,
                "ref": ref,
                "path": path,
                "property_names": property_names,
                "include_descendants": include_descendants,
                "limit": max(1, min(limit, 500)),
                "capacity": max(1, min(capacity, 2000)),
                "ttl_seconds": max(1, min(ttl_seconds, 3600)),
                "stop": stop,
            },
            session_id,
        )

    @mcp.tool()
    async def trace_signal_activity(
        signal_name: str,
        watch_id: str | None = None,
        ref: str | None = None,
        path: str | None = None,
        max_args: int = 8,
        limit: int = 100,
        capacity: int = 200,
        ttl_seconds: int = 120,
        stop: bool = False,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Start or poll a bounded watch over one RBXScriptSignal."""
        return await call(
            registry,
            "trace_signal_activity",
            {
                "signal_name": signal_name,
                "watch_id": watch_id,
                "ref": ref,
                "path": path,
                "max_args": max(0, min(max_args, 32)),
                "limit": max(1, min(limit, 500)),
                "capacity": max(1, min(capacity, 2000)),
                "ttl_seconds": max(1, min(ttl_seconds, 3600)),
                "stop": stop,
            },
            session_id,
        )

    @mcp.tool()
    async def trace_remote_traffic(
        watch_id: str | None = None,
        root_ref: str | None = None,
        root_path: str | None = None,
        query: str | None = None,
        include_incoming: bool = True,
        include_outgoing: bool = True,
        max_args: int = 8,
        limit: int = 100,
        capacity: int = 200,
        duration_seconds: int = 120,
        stop: bool = False,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Start or poll a bounded remote traffic trace for visible client remotes."""
        return await call(
            registry,
            "trace_remote_traffic",
            {
                "watch_id": watch_id,
                "root_ref": root_ref,
                "root_path": root_path,
                "query": query,
                "include_incoming": include_incoming,
                "include_outgoing": include_outgoing,
                "max_args": max(0, min(max_args, 32)),
                "limit": max(1, min(limit, 500)),
                "capacity": max(1, min(capacity, 2000)),
                "duration_seconds": max(1, min(duration_seconds, 3600)),
                "stop": stop,
            },
            session_id,
        )

    @mcp.tool()
    async def watch_tagged_instances(
        tags: list[str] | None = None,
        tag: str | None = None,
        watch_id: str | None = None,
        include_existing: bool = False,
        limit: int = 100,
        capacity: int = 200,
        ttl_seconds: int = 120,
        stop: bool = False,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Start or poll a bounded watch over CollectionService tag add/remove activity."""
        return await call(
            registry,
            "watch_tagged_instances",
            {
                "tags": tags,
                "tag": tag,
                "watch_id": watch_id,
                "include_existing": include_existing,
                "limit": max(1, min(limit, 500)),
                "capacity": max(1, min(capacity, 2000)),
                "ttl_seconds": max(1, min(ttl_seconds, 3600)),
                "stop": stop,
            },
            session_id,
        )

    @mcp.tool()
    async def diff_instance_snapshot(
        snapshot_id: str | None = None,
        ref: str | None = None,
        path: str | None = None,
        property_names: list[str] | None = None,
        max_depth: int = 2,
        max_children: int = 100,
        update_baseline: bool = False,
        stop: bool = False,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Capture a bounded subtree twice and report added, removed, and changed properties."""
        return await call(
            registry,
            "diff_instance_snapshot",
            {
                "snapshot_id": snapshot_id,
                "ref": ref,
                "path": path,
                "property_names": property_names,
                "max_depth": max(0, min(max_depth, 8)),
                "max_children": max(1, min(max_children, 500)),
                "update_baseline": update_baseline,
                "stop": stop,
            },
            session_id,
        )
