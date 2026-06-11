from __future__ import annotations

import logging
import sys
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from dataclasses import dataclass
from typing import Any

from mcp.server.fastmcp import FastMCP

from .bridge import BridgeServer, SessionRegistry
from .config import Config
from .tools import register_all

INSTRUCTIONS = """Inspect a live, client-visible Roblox runtime. Start with list_live_sessions when more than one client may be connected. Prefer structured tools before execute_luau: use logs, snapshots, instance/property readers, remote overviews, memory stats, and bounded watches first. Instance refs are session-scoped and preferred over paths. Watch and trace tools are stateful: the first call returns a watch or snapshot id, and follow-up calls poll or stop it. Bytecode and hash tools intentionally accept only LocalScript and ModuleScript, never Script. Decompile is separate from bytecode and returns executor-produced source text when supported. Advanced executor-only primitives are reported by get_runtime_capabilities and may also be used through execute_luau. This is a client-only debugger: server-only state is unavailable."""


@dataclass(slots=True)
class AppContext:
    config: Config
    registry: SessionRegistry
    bridge: BridgeServer


def create_server(config: Config | None = None) -> FastMCP[Any]:
    config = config or Config.from_env()
    registry = SessionRegistry(
        request_timeout=config.request_timeout_seconds,
        stale_after=config.session_stale_seconds,
    )
    bridge = BridgeServer(config, registry)

    @asynccontextmanager
    async def lifespan(_: FastMCP[Any]) -> AsyncIterator[AppContext]:
        await bridge.start()
        print(
            f"Roblox bridge: http://{config.host}:{config.port}",
            file=sys.stderr,
        )
        print(f"Roblox bridge token: {config.token}", file=sys.stderr)
        try:
            yield AppContext(config, registry, bridge)
        finally:
            await bridge.close()

    mcp: FastMCP[Any] = FastMCP(
        "robloxliveinstance-mcp",
        instructions=INSTRUCTIONS,
        lifespan=lifespan,
        json_response=True,
    )
    register_all(mcp, registry)
    return mcp


def main() -> None:
    logging.basicConfig(level=logging.INFO)
    create_server().run()


if __name__ == "__main__":
    main()
