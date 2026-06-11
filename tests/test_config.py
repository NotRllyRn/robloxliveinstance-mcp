import os
import unittest
from unittest.mock import patch

from robloxliveinstance_mcp.config import Config


class ConfigTests(unittest.TestCase):
    def test_reads_allowlist_and_explicit_token(self) -> None:
        environment = {
            "ROBLOX_LIVE_MCP_TOKEN": "test-token",
            "ROBLOX_LIVE_MCP_PLACE_IDS": "123, 456",
            "ROBLOX_LIVE_MCP_USER_IDS": "10, 20",
            "ROBLOX_LIVE_MCP_PORT": "9000",
        }
        with patch.dict(os.environ, environment, clear=True):
            config = Config.from_env()

        self.assertEqual(config.token, "test-token")
        self.assertEqual(config.port, 9000)
        self.assertEqual(config.allowed_place_ids, frozenset({123, 456}))
        self.assertEqual(config.allowed_user_ids, frozenset({10, 20}))
