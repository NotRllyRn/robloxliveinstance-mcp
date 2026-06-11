local LiveExecutor = {}
LiveExecutor.__index = LiveExecutor

function LiveExecutor.new(handles, serializer, sessionInfo, import)
	return setmetatable({
		handles = handles,
		serializer = serializer,
		sessionInfo = sessionInfo,
		Result = import("Core/Result"),
	}, LiveExecutor)
end

function LiveExecutor:execute(params)
	local code = tostring(params.code or "")
	if code == "" then
		return self.Result.error("empty_code", "code is required.")
	end

	local compiler = loadstring
	if type(compiler) ~= "function" then
		return self.Result.error("capability_unavailable", "loadstring is unavailable.")
	end

	local chunkName = tostring(params.chunk_name or "codex_live_eval")
	local chunk, compileError = compiler(code, chunkName)
	if not chunk then
		return self.Result.error("compile_error", tostring(compileError))
	end

	local output = {}
	local function capture(prefix, ...)
		local parts = table.create(select("#", ...))
		for index = 1, select("#", ...) do
			parts[index] = tostring(select(index, ...))
		end
		table.insert(output, prefix .. table.concat(parts, "\t"))
	end

	if type(setfenv) == "function" then
		local base = getgenv and getgenv() or _G
		local environment = setmetatable({
			print = function(...)
				capture("", ...)
			end,
			warn = function(...)
				capture("[warn] ", ...)
			end,
			resolve_ref = function(ref)
				return self.handles:resolve(ref)
			end,
			serialize = function(value)
				return self.serializer:serialize(value)
			end,
			session_info = self.sessionInfo,
		}, { __index = base })
		setfenv(chunk, environment)
	end

	local packed
	local ok, runtimeError = xpcall(function()
		packed = table.pack(chunk())
	end, function(err)
		if debug and debug.traceback then
			return debug.traceback(tostring(err), 2)
		end
		return tostring(err)
	end)

	if not ok then
		return {
			ok = false,
			error = {
				code = "runtime_error",
				message = tostring(runtimeError),
			},
			output = output,
		}
	end

	local values = {}
	for index = 1, packed.n do
		values[index] = self.serializer:serialize(packed[index])
	end
	return self.Result.ok({
		return_values = values,
		return_count = packed.n,
		output = output,
	})
end

return LiveExecutor
