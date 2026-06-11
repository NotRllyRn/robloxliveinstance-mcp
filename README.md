# Roblox Live Instance MCP

A client-only runtime debugger that connects Codex to an authorized live Roblox
development client. It exposes the client-visible DataModel, readable instance
properties, runtime logs, watches, script/executor inspection APIs, and
explicit live Luau execution.

This project is intended only for private development games and authorized team
members. `execute_luau` is arbitrary code execution in the attached client.

## Architecture

```text
Codex <-- stdio MCP --> Python server <-- WebSocket/HTTP --> Luau client
```

- `src/robloxliveinstance_mcp/tools/`: one module per MCP tooling surface.
- `src/robloxliveinstance_mcp/bridge/`: session routing and loopback transports.
- `luau/Services/`: instance, property, script, and execution behavior.
- `luau/Transport/`: WebSocket primary transport and HTTP polling fallback.
- `luau/Router.lua`: action registration boundary for new runtime features.
- `.codex/skills/roblox-live-debugger/`: Codex workflow guidance.

## Install

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -e .
```

Choose a long random token and the development place IDs that may attach:

```bash
export ROBLOX_LIVE_MCP_TOKEN="replace-with-a-long-random-token"
```

Register the stdio server with Codex:

```bash
codex mcp add roblox-live \
  --env ROBLOX_LIVE_MCP_TOKEN="$ROBLOX_LIVE_MCP_TOKEN" \
  --env ROBLOX_LIVE_MCP_PORT="8766" \
  -- /absolute/path/to/robloxliveinstance-mcp/.venv/bin/robloxliveinstance-mcp
```

The bridge listens on `127.0.0.1:8766` by default. Override it with
`ROBLOX_LIVE_MCP_HOST` and `ROBLOX_LIVE_MCP_PORT`.

## Start The Luau Client

The requested script APIs are executor APIs, not normal Roblox APIs. Copy the
`luau/` directory into the executor's accessible filesystem, then run:

```luau
getgenv().ROBLOX_LIVE_MCP_ROOT = "luau"
getgenv().ROBLOX_LIVE_MCP_CONFIG = {
	token = "replace-with-the-same-token",
	port = 8766,
}

loadfile("luau/Bootstrap.lua")()
```

The client attempts `WebSocket.connect` first and falls back to executor
`request` or `HttpService:RequestAsync` polling. Use
`preferredTransport = "http"` in `ROBLOX_LIVE_MCP_CONFIG` to reverse that order.

## MCP Tools

- Sessions: `list_live_sessions`, `get_runtime_capabilities`
- Instances and properties: `get_instance_tree`, `get_instance_children`,
  `find_instances`, `get_instance_properties`, `read_instance_property`
- Runtime diagnostics: `get_runtime_logs`, `tail_runtime_logs`,
  `get_client_snapshot`, `get_memory_stats`, `get_remote_overview`,
  `get_tagged_instances`, `get_streaming_diagnostics`,
  `get_service_overview`, `capture_screenshot`
- Watches and traces: `watch_instance_changes`, `trace_signal_activity`,
  `trace_remote_traffic`, `watch_tagged_instances`, `diff_instance_snapshot`
- Scripts and executor inspection: `list_scripts`, `get_script_bytecode`,
  `decompile_script`, `get_script_hash`, `get_script_environment`, `get_script_closure_info`,
  `get_calling_script`, `get_script_constants`, `get_script_upvalues`,
  `get_script_stack`, `search_gc_objects`, `list_signal_connections`,
  `read_hidden_property`, `is_property_scriptable`, `find_nil_instances`
- Execution: `execute_luau`

Instance responses include a session-scoped `ref` and a readable `path`. Prefer
`ref` for follow-up calls. Paths use `game/Workspace/Part`; legacy
`game.Workspace.Part` input is also accepted for simple names.

Bytecode and hash tools intentionally reject `Script` and permit only
`LocalScript` and `ModuleScript`. `get_runtime_capabilities` tells Codex which
sUNC functions the current executor actually supports.
`decompile_script` is separate from bytecode and returns executor-produced
source text for a client-visible script instance when the executor exposes
`decompile`.

Stateful tools return an id on the first call, then use the same tool name to
poll or stop that watch or snapshot. `capture_screenshot` is best-effort and
depends on executor-specific screenshot APIs because it is not part of the
standard sUNC surface.

## Add A Tool

1. Add an MCP wrapper in the appropriate `src/.../tools/` module, or create a
   new module and register it in `tools/__init__.py`.
2. Add the runtime implementation to a focused module under `luau/Services/`.
3. Register the action in `luau/Router.lua`.
4. Use JSON-safe values or pass results through `Core/Serializer.lua`.
5. Add Python protocol tests and validate the action in a development client.

The MCP wrapper should only validate arguments and route the request. Roblox
logic belongs in Luau; transport logic belongs under `bridge/` or
`luau/Transport/`.

## Development

```bash
PYTHONPATH=src python3 -m unittest discover -s tests -v
PYTHONPATH=src python3 -m compileall -q src tests
RUN_NETWORK_TESTS=1 .venv/bin/python -m unittest tests.test_bridge_server -v
RUN_MCP_TESTS=1 .venv/bin/python -m unittest tests.test_mcp_stdio -v
```

There is no hard preemption for arbitrary Luau. An infinite loop submitted to
`execute_luau` can stall the attached client and require a reconnect.
