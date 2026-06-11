from __future__ import annotations

from typing import Any

from mcp.server.fastmcp import FastMCP

from ..bridge import SessionRegistry
from .common import call


def register(mcp: FastMCP[Any], registry: SessionRegistry) -> None:
    @mcp.tool()
    async def execute_luau(
        code: str,
        chunk_name: str = "codex_live_eval",
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Execute arbitrary Luau in an authorized live client and capture output."""
        return await call(
            registry,
            "execute_luau",
            {"code": code, "chunk_name": chunk_name},
            session_id,
        )
