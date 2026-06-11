import unittest

from robloxliveinstance_mcp.bridge import BridgeServer, SessionRegistry
from robloxliveinstance_mcp.config import Config
from robloxliveinstance_mcp.protocol import BridgeError


class AuthorizationTests(unittest.TestCase):
    def setUp(self) -> None:
        config = Config(
            host="127.0.0.1",
            port=0,
            token="token",
            allowed_place_ids=frozenset({100}),
            allowed_user_ids=frozenset({200}),
            request_timeout_seconds=1,
            session_stale_seconds=45,
        )
        self.server = BridgeServer(config, SessionRegistry())

    def test_accepts_allowed_place_and_user(self) -> None:
        metadata = self.server._validate_metadata(
            {"place_id": 100, "user_id": 200}
        )
        self.assertEqual(metadata["place_id"], 100)

    def test_rejects_unknown_user(self) -> None:
        with self.assertRaises(BridgeError) as raised:
            self.server._validate_metadata({"place_id": 100, "user_id": 999})
        self.assertEqual(raised.exception.code, "user_not_allowed")
