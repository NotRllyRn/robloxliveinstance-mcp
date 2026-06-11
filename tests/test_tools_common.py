import unittest

from robloxliveinstance_mcp.tools.common import call


class FakeRegistry:
    def __init__(self, payload: object):
        self.payload = payload

    async def request(
        self, action: str, params: object, session_id: str | None
    ) -> object:
        return self.payload


class ToolCommonTests(unittest.IsolatedAsyncioTestCase):
    async def test_preserves_bridge_envelope(self) -> None:
        payload = {"ok": True, "data": {"value": 42}}
        result = await call(FakeRegistry(payload), "example")
        self.assertEqual(result, payload)

    async def test_wraps_unstructured_payload(self) -> None:
        result = await call(FakeRegistry({"value": 42}), "example")
        self.assertEqual(result, {"ok": True, "data": {"value": 42}})
