# Roblox Live Instance MCP Implementation Plan

## Goal And Boundaries

Build a modular MCP server that lets AI coding clients inspect and debug an authorized live
Roblox development client. The implementation is client-only: it can inspect the
full client-visible DataModel and executor-visible scripts, but it cannot reveal
authoritative server-only instances or state.

The Luau client uses sUNC executor APIs. It is not a normal published LocalScript
and must never be shipped as a general-purpose production backdoor.

## Implemented Architecture

### MCP server

- Python package using the stable `mcp` 1.x SDK and stdio transport.
- FastMCP server instructions explain session routing, client-only scope,
  instance refs, script exclusions, and raw execution guidance.
- Tool registration is split by domain under `tools/`.
- Tool wrappers validate bounded arguments and dispatch named bridge actions.
- Tool responses consistently use `{ok, data}` or `{ok: false, error}`.

### Local bridge

- Binds to loopback by default.
- Authenticates WebSocket and HTTP requests with one shared bearer token.
- Optionally rejects clients whose `place_id` is not allowlisted.
- Optionally rejects clients whose local player `user_id` is not allowlisted.
- Maintains independently addressable client sessions.
- Routes requests by `session_id`; omitting the ID works only when one session
  is connected.
- Correlates responses with UUID request IDs and applies request timeouts.
- Serializes `execute_luau` requests per session to avoid overlapping mutable
  evaluations.
- Removes sessions that stop heartbeating.

### Luau runtime

- `Bootstrap.lua` supplies a small cached module loader over executor `loadfile`.
- `Client.lua` constructs service dependencies and runtime metadata.
- `Router.lua` maps protocol actions to focused service handlers.
- `Core/HandleRegistry.lua` assigns opaque session-scoped instance refs.
- `Core/Serializer.lua` converts Roblox values into JSON-safe tagged values.
- Services own instance traversal, property reads, script APIs, and execution.
- Transports share the same router callback and can be replaced independently.

## Tooling Surface

### Session tools

- `list_live_sessions`: session, place, job, player, executor, transport, and
  heartbeat metadata.
- `get_runtime_capabilities`: reports all requested Scripts library functions,
  `loadstring`, transport support, and known scope restrictions.

### Instance tools

- `get_instance_tree`: bounded recursive tree with depth and child limits.
- `get_instance_children`: paginated direct-child expansion.
- `find_instances`: bounded name/path search with optional class filtering.
- Every instance result contains `ref`, `path`, `name`, and `class_name`.

### Property tools

- `get_instance_properties`: requested properties or useful class-based defaults.
- `read_instance_property`: focused one-property lookup.
- Reads use `pcall`, return per-property errors, and serialize Roblox datatypes.
- Attributes are returned by default.

### Script tools

- `list_scripts` selects `getscripts`, `getrunningscripts`, or
  `getloadedmodules`.
- `get_script_bytecode` calls `getscriptbytecode` and returns base64.
- `get_script_hash` calls `getscripthash`.
- `get_script_environment` summarizes `getsenv` entries with limits.
- `get_script_closure_info` calls `getscriptclosure` and returns serializable
  closure/debug metadata.
- `get_calling_script` exposes `getcallingscript` while documenting that an
  executor request thread normally has no calling game script.
- Bytecode and hash operations reject server `Script` instances.

### Execution tool

- `execute_luau` compiles with `loadstring` and a caller-provided chunk name.
- Compile and runtime failures use distinct structured error codes.
- `print` and `warn` are captured when `setfenv` is available.
- Return values are serialized, including multiple return values.
- Eval receives `resolve_ref`, `serialize`, and `session_info` helpers when
  environment injection is available.

## Protocol

WebSocket messages:

- `hello`: proposed session ID and runtime metadata.
- `hello_ack`: accepted session ID and heartbeat interval.
- `heartbeat`: keeps the session alive.
- `request`: request ID, action, and parameters.
- `response`: request ID and action result.

HTTP fallback endpoints:

- `POST /bridge/hello`
- `POST /bridge/poll`
- `POST /bridge/respond`
- `GET /health`

The WebSocket implementation supports text, close, ping, masked client frames,
and extended payload lengths. HTTP polling uses the same action payloads.

## Security Model

- Default listener is `127.0.0.1`, not a public interface.
- A long explicit token should be set in both the MCP client configuration and the
  Luau bootstrap configuration.
- `ROBLOX_LIVE_MCP_PLACE_IDS` should contain only development place IDs.
- `ROBLOX_LIVE_MCP_USER_IDS` can restrict attachment to development team users.
- Production places should not contain or launch the client.
- All authenticated users receive full execution access, matching the selected
  project requirement.
- The protocol does not claim to sandbox arbitrary Luau.

## Extension Contract

To add a feature:

1. Define one action with JSON-safe request and response fields.
2. Implement Roblox behavior in a focused `luau/Services/` module.
3. Register the handler in `luau/Router.lua`.
4. Expose a thin typed MCP wrapper under `src/.../tools/`.
5. Register new tool modules in `tools/__init__.py`.
6. Add unit coverage for validation/routing and a live-client smoke test.

Transport modules must not contain domain behavior. MCP wrappers must not
contain Roblox behavior. Services must not know about MCP.

## Verification

- Python syntax compilation.
- Unit tests for configuration parsing, session routing, ambiguity errors,
  request correlation, duplicate client IDs, WebSocket accept keys, masked
  frames, and extended frames.
- Installed editable package against stable MCP SDK `1.27.2`.
- Verified all 14 MCP tools register with FastMCP.
- Live executor validation remains environment-specific and should be performed
  in the allowlisted development place.

## Known Limitations

- Client-only scope cannot inspect server-only services or server Scripts.
- Generic Roblox reflection does not provide a runtime list of every class
  property, so property reads use explicit names or useful defaults.
- Instance refs expire on reconnect and should not be persisted.
- Arbitrary Luau cannot be safely interrupted; infinite loops can stall a client.
- Bytecode payloads can be large and are returned as a single base64 value.
