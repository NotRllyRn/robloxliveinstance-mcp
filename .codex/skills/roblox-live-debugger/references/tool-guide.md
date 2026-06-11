# Tool Guide

## Discovery

Use `get_instance_tree` for orientation with `max_depth` 1-3. Use
`get_instance_children` for precise pagination. Use `find_instances` when a
name, path fragment, or class is known.

## Properties

Use `get_instance_properties` for a compact diagnostic snapshot. Pass
`property_names` when a property is not included in the class defaults. Use
`read_instance_property` for repeated focused checks.

## Runtime

Use `get_runtime_logs` for one-shot console reads and `tail_runtime_logs` when
you need to poll during a repro without rereading the whole buffer.

Use `get_client_snapshot` before eval when the question is about camera,
character, GUI, input mode, or equipped tools. Use `get_memory_stats` and
`get_streaming_diagnostics` before writing custom performance probes. Use
`get_remote_overview`, `get_tagged_instances`, and `get_service_overview` to
discover structure first.

`capture_screenshot` is executor-dependent. Treat `capability_unavailable` as a
normal outcome.

## Watches

`watch_instance_changes`, `trace_signal_activity`, `trace_remote_traffic`, and
`watch_tagged_instances` are stateful. The first call returns a `watch_id`; poll
by calling the same tool again with that id. Pass `stop=true` when done.

`diff_instance_snapshot` is a two-phase snapshot helper. First call creates a
baseline and returns `snapshot_id`; later calls with the same id report added,
removed, and changed properties.

## Scripts

`list_scripts(mode="all")` calls `getscripts`.
`list_scripts(mode="running")` calls `getrunningscripts`.
`list_scripts(mode="loaded_modules")` calls `getloadedmodules`.

Use `get_script_hash` before bytecode when comparing script identity. Bytecode
is base64 and may be large. `decompile_script` is different: it returns
executor-produced decompiled source text for a client-visible script. Use it
when you need readable generated logic rather than raw instructions.
`get_script_environment` returns a bounded summary, not a live table.
`get_script_closure_info` proves closure availability and returns metadata; use
`execute_luau` for deeper executor-specific closure work.

`get_calling_script` is usually nil because MCP requests originate from the
executor bridge thread. It becomes useful only when custom diagnostic code
invokes it from a game-script call path.

Use `get_script_constants` and `get_script_upvalues` before dumping full
bytecode when you are tracing behavior. `get_script_stack` inspects the current
executor request thread, not arbitrary game threads.

Use `search_gc_objects` for bounded GC-visible searches, `list_signal_connections`
for signal wiring, `read_hidden_property` and `is_property_scriptable` for
executor reflection, and `find_nil_instances` to catch detached live instances.

## Eval Examples

Read a non-default property:

```luau
local instance = resolve_ref("instance:replace-me")
return instance and instance:GetDebugId()
```

Return structured runtime state:

```luau
local player = game:GetService("Players").LocalPlayer
return {
	userId = player.UserId,
	character = player.Character,
	camera = workspace.CurrentCamera,
}
```

Inspect available script primitives:

```luau
return {
	getscripts = type(getscripts),
	getscriptbytecode = type(getscriptbytecode),
	getscriptclosure = type(getscriptclosure),
	getsenv = type(getsenv),
}
```
