---
name: roblox-live-debugger
description: Inspect and debug an authorized live Roblox development client through the roblox-live MCP server. Use when tracing client runtime state, exploring instances, reading properties, inspecting LocalScript or ModuleScript bytecode, checking sUNC script APIs, or executing diagnostic Luau.
---

# Roblox Live Debugger

## Workflow

1. Call `list_live_sessions`.
2. If multiple sessions exist, retain the intended `session_id` on every call.
3. Call `get_runtime_capabilities` before using executor-specific script APIs.
4. Explore with `get_instance_tree`, then narrow with
   `get_instance_children` or `find_instances`.
5. Reuse returned instance `ref` values for property, script, and watch calls.
6. Prefer `get_runtime_logs`, `get_client_snapshot`, `get_memory_stats`,
   `get_remote_overview`, and other structured diagnostics before `execute_luau`.
7. Use watch tools for time-based bugs: `watch_instance_changes`,
   `trace_signal_activity`, `trace_remote_traffic`,
   `watch_tagged_instances`, `diff_instance_snapshot`.
8. Use `execute_luau` for state that the structured tools cannot express.

## Scope

- Treat the runtime as client-only. Do not claim visibility into server-only
  services, Scripts, or authoritative server state.
- Bytecode and hash tools support `LocalScript` and `ModuleScript`; they
  intentionally reject `Script`.
- `decompile_script` is different from bytecode and returns executor-produced
  source text when the runtime exposes `decompile`.
- Instance refs are session-scoped and expire when the client reconnects.
- Watch and snapshot ids are also session-scoped and should be treated as
  ephemeral.
- `capture_screenshot` is best-effort only and depends on executor-specific
  screenshot support.

## Live Luau

- Keep diagnostics bounded and return compact serializable values.
- Use `resolve_ref("instance:...")` inside eval to recover an instance.
- `print` and `warn` output is returned with the result when environment
  injection is supported.
- Avoid unbounded loops, waits, or destructive mutations. There is no reliable
  hard timeout inside arbitrary Luau.
- Explain any state-changing eval before running it when the user did not
  explicitly request mutation.

## Recovery

- `no_live_sessions`: ask the user to start the Luau bootstrap in the dev client.
- `ambiguous_session`: choose a session from the returned list and retry.
- `capability_unavailable`: report the missing executor API; do not invent data.
- `instance_not_found`: refresh the tree because the ref may be stale.
- `unknown_watch` or `unknown_snapshot`: the stateful helper expired or the
  client reconnected; recreate it.
- `request_timeout`: check that the client is responsive and reconnect if needed.

Read [references/tool-guide.md](references/tool-guide.md) when choosing between
similar tools or constructing an eval.
