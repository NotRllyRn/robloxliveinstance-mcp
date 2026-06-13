# Roblox MCP Implementation Plan

## Goal
Build an in-game Roblox MCP tool for debugging a live development game. It should allow approved dev team members to attach securely, explore instance structure, read instance properties, inspect script bytecode, and execute dynamic Luau code.

## Architecture
- `MCPCore`: core module handling connection, authentication, and message routing.
- `InstanceExplorer`: module for traversing game hierarchy and returning structured instance data.
- `PropertyReader`: module for reading selected instance properties safely.
- `ScriptInspector`: module for script-specific operations using the Scripts library.
- `LiveExecutor`: module for running live Luau code via `loadstring` and returning results.
- `Transport`: abstract layer supporting WebSocket and HttpService-based comms.

## Connection
1. Support WebSocket connection using docs.sunc.su WebSocket parameters.
2. Provide fallback or alternative transport using HttpService for polling/request-response if WebSocket is unavailable.
3. Authenticate clients using an allowlist for the dev game and simple token or key exchange.
4. Only enable MCP in the authorized dev game environment.

## Features
### Instance structure access
- Enumerate game hierarchy starting from `game` and optionally `workspace`, `ReplicatedStorage`, etc.
- Return instance metadata: class name, name, path, children count, parent path.
- Allow selective subtree expansion on demand to avoid huge payloads.

### Property reading
- Read safe properties from any instance in the accessible path.
- Return property name, type, and value (with truncation for large values if needed).
- Ignore or safely handle inaccessible properties.

### Script inspection
- Enumerate scripts using: `getscripts`, `getrunningscripts`, `getloadedmodules`.
- For non-server scripts, expose `getscriptbytecode` and return compiled bytecode metadata or hex/base64 payload.
- Support `getscripthash`, `getscriptclosure`, `getsenv`, and `getcallingscript` where applicable.
- Provide a safe summary view for server scripts without exposing forbidden data.

### Live code execution
- Use `loadstring` from docs.sunc.su/Closures/loadstring/ to execute submitted Luau snippets.
- Restrict execution to allowed contexts and safe sandboxing patterns if possible.
- Return execution output, error, and stack trace.

## Modular design
- Keep each feature in its own module for maintainability.
- Export clear APIs from each module:
  - `MCPCore.connect()`
  - `InstanceExplorer.getTree(path)`
  - `PropertyReader.read(instance, propertyName)`
  - `ScriptInspector.getBytecode(script)`
  - `LiveExecutor.execute(code)`
- Use a shared message schema for transport.

## Message protocol
- Define JSON actions:
  - `listInstances`
  - `getProperties`
  - `getScriptBytecode`
  - `getScriptHash`
  - `getScriptClosure`
  - `getScriptEnv`
  - `runCode`
- Include `requestId`, `action`, `params`, and `auth` fields.
- Send responses with `status`, `data`, and `error`.

## Security and access control
- Only allow access in the dev game and for authorized users.
- Keep the tool off in production and public games.
- Validate inputs to avoid abuse.
- Restrict live execution to the MCP request channel.

## References
- Use `reference/robloxstudio-mcp` as inspiration for feature set and modular structure.
- Follow the Scripts library documentation from docs.sunc.su for supported APIs.

## Implementation steps
1. Create `Transport` module with WebSocket and HttpService options.
2. Build `MCPCore` to initialize transport and authenticate clients.
3. Implement `InstanceExplorer` for traversing instances and returning JSON-friendly trees.
4. Implement `PropertyReader` with safe property access and type handling.
5. Implement `ScriptInspector` with `getscripts`, `getrunningscripts`, `getloadedmodules`, `getscriptbytecode`, `getscripthash`, `getscriptclosure`, `getsenv`, `getcallingscript`.
6. Implement `LiveExecutor` using `loadstring`.
7. Wire message handling in `MCPCore` and expose actions.
8. Test in the dev game with approved team access.
9. Document usage and keep the plan modular for future extension.
