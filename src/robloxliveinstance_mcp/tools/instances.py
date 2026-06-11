from __future__ import annotations

from typing import Any

from mcp.server.fastmcp import FastMCP

from ..bridge import SessionRegistry
from .common import call


def register(mcp: FastMCP[Any], registry: SessionRegistry) -> None:
    @mcp.tool()
    async def get_instance_tree(
        ref: str | None = None,
        path: str | None = None,
        max_depth: int = 2,
        max_children: int = 100,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Read a bounded tree from the client-visible Roblox DataModel."""
        return await call(
            registry,
            "get_instance_tree",
            {
                "ref": ref,
                "path": path or "game",
                "max_depth": max(0, min(max_depth, 8)),
                "max_children": max(1, min(max_children, 500)),
            },
            session_id,
        )

    @mcp.tool()
    async def get_instance_children(
        ref: str | None = None,
        path: str | None = None,
        offset: int = 0,
        limit: int = 100,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """List direct children of one instance with pagination."""
        return await call(
            registry,
            "get_instance_children",
            {
                "ref": ref,
                "path": path,
                "offset": max(0, offset),
                "limit": max(1, min(limit, 500)),
            },
            session_id,
        )

    @mcp.tool()
    async def find_instances(
        query: str,
        root_ref: str | None = None,
        root_path: str | None = None,
        class_name: str | None = None,
        limit: int = 100,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Find client-visible instances by case-insensitive name or path text."""
        return await call(
            registry,
            "find_instances",
            {
                "query": query,
                "root_ref": root_ref,
                "root_path": root_path,
                "class_name": class_name,
                "limit": max(1, min(limit, 500)),
            },
            session_id,
        )

    @mcp.tool()
    async def get_instance_properties(
        ref: str | None = None,
        path: str | None = None,
        property_names: list[str] | None = None,
        include_attributes: bool = True,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Read requested properties or a useful default property set."""
        return await call(
            registry,
            "get_instance_properties",
            {
                "ref": ref,
                "path": path,
                "property_names": property_names,
                "include_attributes": include_attributes,
            },
            session_id,
        )

    @mcp.tool()
    async def read_instance_property(
        property_name: str,
        ref: str | None = None,
        path: str | None = None,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Read one property from a client-visible instance."""
        return await call(
            registry,
            "read_instance_property",
            {"ref": ref, "path": path, "property_name": property_name},
            session_id,
        )
