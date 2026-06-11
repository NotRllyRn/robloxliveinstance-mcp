import asyncio
import unittest

from robloxliveinstance_mcp.bridge.registry import SessionRegistry
from robloxliveinstance_mcp.protocol import BridgeError


class RegistryTests(unittest.IsolatedAsyncioTestCase):
    async def test_routes_request_and_completes_response(self) -> None:
        registry = SessionRegistry(request_timeout=1)
        sent: list[dict[str, object]] = []

        async def send(message: dict[str, object]) -> None:
            sent.append(message)
            asyncio.get_running_loop().call_soon(
                registry.complete, str(message["request_id"]), {"value": 42}
            )

        session = await registry.register({"place_id": 123}, "test", send)
        response = await registry.request("example", {"x": 1}, session.session_id)

        self.assertEqual(response, {"value": 42})
        self.assertEqual(sent[0]["action"], "example")

    async def test_requires_session_id_when_ambiguous(self) -> None:
        registry = SessionRegistry()

        async def send(_: dict[str, object]) -> None:
            return None

        await registry.register({}, "test", send)
        await registry.register({}, "test", send)

        with self.assertRaises(BridgeError) as raised:
            registry.resolve()
        self.assertEqual(raised.exception.code, "ambiguous_session")

    async def test_duplicate_client_id_gets_new_server_id(self) -> None:
        registry = SessionRegistry()

        async def send(_: dict[str, object]) -> None:
            return None

        first = await registry.register({}, "test", send, "client-id")
        second = await registry.register({}, "test", send, "client-id")
        self.assertEqual(first.session_id, "client-id")
        self.assertNotEqual(second.session_id, "client-id")
