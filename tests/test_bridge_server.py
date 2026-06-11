import asyncio
import os
import unittest

from robloxliveinstance_mcp.bridge import BridgeServer, SessionRegistry
from robloxliveinstance_mcp.config import Config


@unittest.skipUnless(
    os.getenv("RUN_NETWORK_TESTS") == "1", "set RUN_NETWORK_TESTS=1"
)
class BridgeServerTests(unittest.IsolatedAsyncioTestCase):
    async def test_loopback_health_endpoint(self) -> None:
        config = Config(
            host="127.0.0.1",
            port=0,
            token="test-token",
            allowed_place_ids=frozenset(),
            allowed_user_ids=frozenset(),
            request_timeout_seconds=1,
            session_stale_seconds=45,
        )
        server = BridgeServer(config, SessionRegistry())
        await server.start()
        self.addAsyncCleanup(server.close)

        reader, writer = await asyncio.open_connection(
            config.host, server.bound_port
        )
        writer.write(
            b"GET /health HTTP/1.1\r\n"
            b"Host: 127.0.0.1\r\n"
            b"Connection: close\r\n\r\n"
        )
        await writer.drain()
        response = await reader.read()
        writer.close()
        await writer.wait_closed()

        self.assertIn(b"200 OK", response)
        self.assertIn(b'"sessions":[]', response)
