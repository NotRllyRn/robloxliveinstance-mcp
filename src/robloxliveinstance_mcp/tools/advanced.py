from __future__ import annotations

from typing import Any

from mcp.server.fastmcp import FastMCP

from ..bridge import SessionRegistry
from .common import call


def register(mcp: FastMCP[Any], registry: SessionRegistry) -> None:
    @mcp.tool()
    async def get_script_constants(
        ref: str | None = None,
        path: str | None = None,
        limit: int = 200,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Read structured debug constants for a script closure."""
        return await call(
            registry,
            "get_script_constants",
            {"ref": ref, "path": path, "limit": max(1, min(limit, 1000))},
            session_id,
        )

    @mcp.tool()
    async def get_script_upvalues(
        ref: str | None = None,
        path: str | None = None,
        limit: int = 100,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Read structured debug upvalues for a script closure."""
        return await call(
            registry,
            "get_script_upvalues",
            {"ref": ref, "path": path, "limit": max(1, min(limit, 1000))},
            session_id,
        )

    @mcp.tool()
    async def get_script_stack(
        start_level: int = 1,
        max_levels: int = 3,
        index: int | None = None,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Read bounded debug.getstack frames from the current executor request thread."""
        return await call(
            registry,
            "get_script_stack",
            {
                "start_level": max(1, min(start_level, 100)),
                "max_levels": max(1, min(max_levels, 20)),
                "index": index,
            },
            session_id,
        )

    @mcp.tool()
    async def search_gc_objects(
        object_type: str | None = None,
        query: str | None = None,
        table_key: str | None = None,
        constant: str | int | float | bool | None = None,
        function_hash: str | None = None,
        include_tables: bool = True,
        scan_limit: int = 5000,
        limit: int = 100,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Search GC-visible runtime objects with bounded filters over getgc results."""
        return await call(
            registry,
            "search_gc_objects",
            {
                "object_type": object_type,
                "query": query,
                "table_key": table_key,
                "constant": constant,
                "function_hash": function_hash,
                "include_tables": include_tables,
                "scan_limit": max(1, min(scan_limit, 20000)),
                "limit": max(1, min(limit, 500)),
            },
            session_id,
        )

    @mcp.tool()
    async def list_signal_connections(
        signal_name: str,
        ref: str | None = None,
        path: str | None = None,
        limit: int = 100,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """List lightweight connection metadata for one RBXScriptSignal."""
        return await call(
            registry,
            "list_signal_connections",
            {
                "signal_name": signal_name,
                "ref": ref,
                "path": path,
                "limit": max(1, min(limit, 500)),
            },
            session_id,
        )

    @mcp.tool()
    async def read_hidden_property(
        property_name: str,
        ref: str | None = None,
        path: str | None = None,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Read a hidden or non-scriptable property when the executor exposes gethiddenproperty."""
        return await call(
            registry,
            "read_hidden_property",
            {"property_name": property_name, "ref": ref, "path": path},
            session_id,
        )

    @mcp.tool()
    async def is_property_scriptable(
        property_name: str,
        ref: str | None = None,
        path: str | None = None,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Check whether a property is scriptable when the executor exposes isscriptable."""
        return await call(
            registry,
            "is_property_scriptable",
            {"property_name": property_name, "ref": ref, "path": path},
            session_id,
        )

    @mcp.tool()
    async def find_nil_instances(
        query: str | None = None,
        class_name: str | None = None,
        limit: int = 100,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """List nil-parented live instances when the executor exposes getnilinstances."""
        return await call(
            registry,
            "find_nil_instances",
            {
                "query": query,
                "class_name": class_name,
                "limit": max(1, min(limit, 500)),
            },
            session_id,
        )
