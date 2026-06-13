# Roblox Live Debugger Tool Guide

## Start Here

1. Use `list_live_sessions` to discover attached clients.
2. Use `get_runtime_capabilities` before any executor-specific script call.
3. Prefer structured reads before raw evaluation.

## Choose The Smallest Tool

- Use `get_instance_tree` for a bounded overview.
- Use `get_instance_children` to expand one node.
- Use `find_instances` when you already know part of the name or path.
- Use `get_instance_properties` for a compact property bundle.
- Use `read_instance_property` when you need one value only.

## Diagnostics Before Eval

- Use `get_runtime_logs` or `tail_runtime_logs` for console-oriented issues.
- Use `get_client_snapshot` for a broad runtime summary.
- Use `get_memory_stats` for memory pressure and allocation questions.
- Use `get_remote_overview` or `trace_remote_traffic` for remotes.
- Use `get_service_overview` for high-level service state.

## Watches

- `watch_instance_changes` for ancestry, property, or lifecycle changes.
- `trace_signal_activity` for event-focused debugging.
- `trace_remote_traffic` for RemoteEvent and RemoteFunction activity.
- `watch_tagged_instances` for CollectionService-driven systems.
- `diff_instance_snapshot` for repeated structural comparisons.

## Script Tools

- Bytecode and hash calls only work on `LocalScript` and `ModuleScript`.
- `decompile_script` is separate from bytecode and depends on executor support.
- `get_calling_script` is usually nil because MCP requests originate from the
  executor request thread, not from an in-game script call chain.

## Live Eval

- Use compact snippets.
- Return structured values.
- Resolve refs inside eval rather than reparsing paths repeatedly.
- Avoid long-running loops or waits.
