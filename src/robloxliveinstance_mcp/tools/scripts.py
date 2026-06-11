from __future__ import annotations

from typing import Any, Literal

from mcp.server.fastmcp import FastMCP

from ..bridge import SessionRegistry
from .common import call


def register(mcp: FastMCP[Any], registry: SessionRegistry) -> None:
    @mcp.tool()
    async def list_scripts(
        mode: Literal["all", "running", "loaded_modules"] = "all",
        class_name: str | None = None,
        limit: int = 500,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Enumerate scripts using getscripts, getrunningscripts, or getloadedmodules."""
        return await call(
            registry,
            "list_scripts",
            {"mode": mode, "class_name": class_name, "limit": min(limit, 2000)},
            session_id,
        )

    @mcp.tool()
    async def get_script_bytecode(
        ref: str | None = None,
        path: str | None = None,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Read base64 bytecode from a LocalScript or ModuleScript; server Scripts are rejected."""
        return await call(
            registry, "get_script_bytecode", {"ref": ref, "path": path}, session_id
        )

    @mcp.tool()
    async def decompile_script(
        ref: str | None = None,
        path: str | None = None,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Read executor-decompiled source for a client-visible script instance."""
        return await call(
            registry, "decompile_script", {"ref": ref, "path": path}, session_id
        )

    @mcp.tool()
    async def get_script_hash(
        ref: str | None = None,
        path: str | None = None,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Read the executor-provided bytecode hash for a LocalScript or ModuleScript."""
        return await call(
            registry, "get_script_hash", {"ref": ref, "path": path}, session_id
        )

    @mcp.tool()
    async def get_script_environment(
        ref: str | None = None,
        path: str | None = None,
        max_entries: int = 200,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Summarize a script global environment using getsenv."""
        return await call(
            registry,
            "get_script_environment",
            {"ref": ref, "path": path, "max_entries": min(max_entries, 1000)},
            session_id,
        )

    @mcp.tool()
    async def get_script_closure_info(
        ref: str | None = None,
        path: str | None = None,
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Create a script closure and return serializable debug metadata about it."""
        return await call(
            registry,
            "get_script_closure_info",
            {"ref": ref, "path": path},
            session_id,
        )

    @mcp.tool()
    async def get_calling_script(
        session_id: str | None = None,
    ) -> dict[str, Any]:
        """Call getcallingscript in the bridge thread; it is normally nil for executor-originated requests."""
        return await call(registry, "get_calling_script", session_id=session_id)
