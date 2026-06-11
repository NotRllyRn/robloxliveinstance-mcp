from __future__ import annotations

from typing import TYPE_CHECKING, Any

from ..bridge import SessionRegistry

if TYPE_CHECKING:
    from mcp.server.fastmcp import FastMCP


def register_all(mcp: "FastMCP[Any]", registry: SessionRegistry) -> None:
    from . import advanced, execution, instances, runtime, scripts, sessions, watches

    sessions.register(mcp, registry)
    instances.register(mcp, registry)
    scripts.register(mcp, registry)
    advanced.register(mcp, registry)
    runtime.register(mcp, registry)
    watches.register(mcp, registry)
    execution.register(mcp, registry)
