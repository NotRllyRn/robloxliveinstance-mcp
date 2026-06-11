local ScriptInspector = {}
ScriptInspector.__index = ScriptInspector

local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64Encode(data)
	local output = {}
	for index = 1, #data, 3 do
		local a = string.byte(data, index) or 0
		local b = string.byte(data, index + 1) or 0
		local c = string.byte(data, index + 2) or 0
		local value = a * 65536 + b * 256 + c
		local remaining = #data - index + 1
		table.insert(output, string.sub(BASE64_ALPHABET, bit32.extract(value, 18, 6) + 1, bit32.extract(value, 18, 6) + 1))
		table.insert(output, string.sub(BASE64_ALPHABET, bit32.extract(value, 12, 6) + 1, bit32.extract(value, 12, 6) + 1))
		table.insert(output, remaining >= 2
			and string.sub(BASE64_ALPHABET, bit32.extract(value, 6, 6) + 1, bit32.extract(value, 6, 6) + 1)
			or "=")
		table.insert(output, remaining >= 3
			and string.sub(BASE64_ALPHABET, bit32.extract(value, 0, 6) + 1, bit32.extract(value, 0, 6) + 1)
			or "=")
	end
	return table.concat(output)
end

function ScriptInspector.new(handles, serializer, import)
	return setmetatable({
		handles = handles,
		serializer = serializer,
		import = import,
		Instances = import("Core/Instances"),
		Result = import("Core/Result"),
		Capabilities = import("Core/Capabilities"),
		ScriptSupport = import("Core/ScriptSupport"),
	}, ScriptInspector)
end

function ScriptInspector:_global(name)
	return self.ScriptSupport.global(name)
end

function ScriptInspector:_script(params, allowServerScript)
	return self.ScriptSupport.resolveScript(params, self.handles, self.import, allowServerScript)
end

function ScriptInspector:capabilities()
	return self.Result.ok({
		capabilities = self.Capabilities.detect(),
		notes = {
			client_only = true,
			server_script_bytecode = false,
			getcallingscript_executor_thread_normally_nil = true,
		},
	})
end

function ScriptInspector:list(params)
	local mode = params.mode or "all"
	local fnName = mode == "running" and "getrunningscripts"
		or mode == "loaded_modules" and "getloadedmodules"
		or "getscripts"
	local fn = self:_global(fnName)
	if type(fn) ~= "function" then
		return self.Result.error("capability_unavailable", fnName .. " is unavailable.")
	end
	local ok, scripts = pcall(fn)
	if not ok then
		return self.Result.error("script_enumeration_failed", tostring(scripts))
	end

	local results = {}
	local limit = tonumber(params.limit) or 500
	for _, instance in ipairs(scripts) do
		if typeof(instance) == "Instance"
			and (params.class_name == nil or instance.ClassName == params.class_name) then
			table.insert(results, self.Instances.describe(instance, self.handles))
			if #results >= limit then
				break
			end
		end
	end
	return self.Result.ok({
		mode = mode,
		results = results,
		count = #results,
		truncated = #results >= limit,
	})
end

function ScriptInspector:bytecode(params)
	local instance, err = self:_script(params, false)
	if not instance then
		return err
	end
	local fn = self:_global("getscriptbytecode")
	if type(fn) ~= "function" then
		return self.Result.error("capability_unavailable", "getscriptbytecode is unavailable.")
	end
	local ok, bytecode = pcall(fn, instance)
	if not ok or type(bytecode) ~= "string" then
		return self.Result.error("bytecode_failed", tostring(bytecode))
	end
	return self.Result.ok({
		script = self.Instances.describe(instance, self.handles),
		encoding = "base64",
		byte_length = #bytecode,
		bytecode = base64Encode(bytecode),
	})
end

function ScriptInspector:decompile(params)
	local instance, err = self:_script(params, true)
	if not instance then
		return err
	end
	local fn = self:_global("decompile")
	if type(fn) ~= "function" then
		return self.Result.error("capability_unavailable", "decompile is unavailable.")
	end
	local ok, source = pcall(fn, instance)
	if not ok or type(source) ~= "string" then
		return self.Result.error("decompile_failed", tostring(source))
	end
	return self.Result.ok({
		script = self.Instances.describe(instance, self.handles),
		source = source,
		line_count = select(2, string.gsub(source, "\n", "\n")) + 1,
	})
end

function ScriptInspector:hash(params)
	local instance, err = self:_script(params, false)
	if not instance then
		return err
	end
	local fn = self:_global("getscripthash")
	if type(fn) ~= "function" then
		return self.Result.error("capability_unavailable", "getscripthash is unavailable.")
	end
	local ok, hash = pcall(fn, instance)
	if not ok or type(hash) ~= "string" then
		return self.Result.error("hash_failed", tostring(hash))
	end
	return self.Result.ok({
		script = self.Instances.describe(instance, self.handles),
		hash = hash,
	})
end

function ScriptInspector:environment(params)
	local instance, err = self:_script(params, true)
	if not instance then
		return err
	end
	local fn = self:_global("getsenv")
	if type(fn) ~= "function" then
		return self.Result.error("capability_unavailable", "getsenv is unavailable.")
	end
	local ok, environment = pcall(fn, instance)
	if not ok or type(environment) ~= "table" then
		return self.Result.error("environment_failed", tostring(environment))
	end

	local entries = {}
	local count = 0
	local maxEntries = tonumber(params.max_entries) or 200
	for key, value in pairs(environment) do
		count += 1
		if count > maxEntries then
			break
		end
		table.insert(entries, {
			key = tostring(key),
			value_type = typeof(value),
			value = self.serializer:serialize(value),
		})
	end
	table.sort(entries, function(a, b)
		return a.key < b.key
	end)
	return self.Result.ok({
		script = self.Instances.describe(instance, self.handles),
		entries = entries,
		count = #entries,
		truncated = count > maxEntries,
	})
end

function ScriptInspector:closureInfo(params)
	local instance, err = self:_script(params, true)
	if not instance then
		return err
	end
	local fn = self:_global("getscriptclosure")
	if type(fn) ~= "function" then
		return self.Result.error("capability_unavailable", "getscriptclosure is unavailable.")
	end
	local ok, closure = pcall(fn, instance)
	if not ok or type(closure) ~= "function" then
		return self.Result.error("closure_failed", tostring(closure))
	end
	local info
	if debug and type(debug.getinfo) == "function" then
		local infoOk, infoValue = pcall(debug.getinfo, closure)
		if infoOk then
			info = self.serializer:serialize(infoValue)
		end
	end
	return self.Result.ok({
		script = self.Instances.describe(instance, self.handles),
		closure_type = typeof(closure),
		debug_info = info,
	})
end

function ScriptInspector:callingScript()
	local fn = self:_global("getcallingscript")
	if type(fn) ~= "function" then
		return self.Result.error("capability_unavailable", "getcallingscript is unavailable.")
	end
	local ok, instance = pcall(fn)
	if not ok then
		return self.Result.error("getcallingscript_failed", tostring(instance))
	end
	return self.Result.ok({
		script = typeof(instance) == "Instance"
			and self.Instances.describe(instance, self.handles)
			or nil,
	})
end

return ScriptInspector
