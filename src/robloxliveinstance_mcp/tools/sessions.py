from __future__ import annotations

from typing import Any

from mcp.server.fastmcp import FastMCP

from ..bridge import SessionRegistry
from .common import call


def register(mcp: FastMCP[Any], registry: SessionRegistry) -> None:
    @mcp.tool()
    def list_live_sessions() -> dict[str, Any]:
        """List connected Roblox client runtimes and their session IDs."""
        sessions = registry.list_public()
        return {"ok": True, "data": {"sessions": sessions, "count": len(sessions)}}

    @mcp.tool()
    async def get_runtime_capabilities(
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Report available sUNC script, closure, and transport capabilities."""
        return await call(registry, "get_runtime_capabilities", session_id=session_id)
