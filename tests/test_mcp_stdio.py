import os
import unittest

try:
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client
except ImportError:
    ClientSession = None


@unittest.skipUnless(
    os.getenv("RUN_MCP_TESTS") == "1" and ClientSession is not None,
    "set RUN_MCP_TESTS=1 with the mcp package installed",
)
class McpStdioTests(unittest.IsolatedAsyncioTestCase):
    async def test_initializes_and_lists_tools(self) -> None:
        environment = os.environ.copy()
        environment.update(
            {
                "ROBLOX_LIVE_MCP_PORT": "0",
                "ROBLOX_LIVE_MCP_TOKEN": "test-token",
            }
        )
        parameters = StdioServerParameters(
            command=os.path.abspath(".venv/bin/robloxliveinstance-mcp"),
            env=environment,
        )

        async with stdio_client(parameters) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                result = await session.list_tools()

        names = {tool.name for tool in result.tools}
        self.assertEqual(len(names), 37)
        self.assertIn("get_instance_tree", names)
        self.assertIn("get_runtime_logs", names)
        self.assertIn("watch_instance_changes", names)
        self.assertIn("get_memory_stats", names)
        self.assertIn("get_script_constants", names)
        self.assertIn("decompile_script", names)
        self.assertIn("get_script_bytecode", names)
        self.assertIn("execute_luau", names)
