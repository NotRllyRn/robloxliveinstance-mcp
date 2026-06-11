local AdvancedInspector = {}
AdvancedInspector.__index = AdvancedInspector

local function lowerContains(value, needle)
	if needle == nil or needle == "" then
		return true
	end
	return string.find(string.lower(tostring(value)), string.lower(tostring(needle)), 1, true) ~= nil
end

function AdvancedInspector.new(handles, serializer, import)
	return setmetatable({
		handles = handles,
		serializer = serializer,
		import = import,
		Instances = import("Core/Instances"),
		Result = import("Core/Result"),
		SignalResolver = import("Core/SignalResolver"),
		ScriptSupport = import("Core/ScriptSupport"),
	}, AdvancedInspector)
end

function AdvancedInspector:_global(name)
	return self.ScriptSupport.global(name)
end

function AdvancedInspector:_getClosure(params, allowServerScript)
	return self.ScriptSupport.getClosure(params, self.handles, self.import, allowServerScript)
end

function AdvancedInspector:_functionInfo(func)
	if debug == nil or type(debug.info) ~= "function" then
		return {
			type = typeof(func),
			display = tostring(func),
		}
	end
	local info = {
		type = typeof(func),
		display = tostring(func),
	}
	local okName, name = pcall(debug.info, func, "n")
	if okName and name ~= nil then
		info.name = tostring(name)
	end
	local okSource, source = pcall(debug.info, func, "s")
	if okSource and source ~= nil then
		info.source = tostring(source)
	end
	local okLine, line = pcall(debug.info, func, "l")
	if okLine and line ~= nil then
		info.line = line
	end
	return info
end

function AdvancedInspector:getScriptConstants(params)
	local instance, closure, err = self:_getClosure(params, true)
	if not instance then
		return err
	end
	if debug == nil or type(debug.getconstants) ~= "function" then
		return self.Result.error("capability_unavailable", "debug.getconstants is unavailable.")
	end
	local ok, constants = pcall(debug.getconstants, closure)
	if not ok or type(constants) ~= "table" then
		return self.Result.error("constants_failed", tostring(constants))
	end
	local limit = math.max(tonumber(params.limit) or 200, 1)
	local entries = {}
	for index, value in pairs(constants) do
		table.insert(entries, {
			index = tonumber(index) or index,
			value = self.serializer:serialize(value),
			value_type = typeof(value),
		})
		if #entries >= limit then
			break
		end
	end
	table.sort(entries, function(a, b)
		return tostring(a.index) < tostring(b.index)
	end)
	return self.Result.ok({
		script = self.Instances.describe(instance, self.handles),
		entries = entries,
		count = #entries,
	})
end

function AdvancedInspector:getScriptUpvalues(params)
	local instance, closure, err = self:_getClosure(params, true)
	if not instance then
		return err
	end
	if debug == nil or type(debug.getupvalues) ~= "function" then
		return self.Result.error("capability_unavailable", "debug.getupvalues is unavailable.")
	end
	local ok, upvalues = pcall(debug.getupvalues, closure)
	if not ok or type(upvalues) ~= "table" then
		return self.Result.error("upvalues_failed", tostring(upvalues))
	end
	local limit = math.max(tonumber(params.limit) or 100, 1)
	local entries = {}
	for index, value in pairs(upvalues) do
		table.insert(entries, {
			index = tonumber(index) or index,
			value = self.serializer:serialize(value),
			value_type = typeof(value),
		})
		if #entries >= limit then
			break
		end
	end
	table.sort(entries, function(a, b)
		return tostring(a.index) < tostring(b.index)
	end)
	return self.Result.ok({
		script = self.Instances.describe(instance, self.handles),
		entries = entries,
		count = #entries,
	})
end

function AdvancedInspector:getScriptStack(params)
	if debug == nil or type(debug.getstack) ~= "function" then
		return self.Result.error("capability_unavailable", "debug.getstack is unavailable.")
	end
	local startLevel = math.max(tonumber(params.start_level) or 1, 1)
	local maxLevels = math.max(math.min(tonumber(params.max_levels) or 3, 20), 1)
	local index = params.index and tonumber(params.index) or nil
	local frames = {}
	for level = startLevel, startLevel + maxLevels - 1 do
		local ok, value
		if index ~= nil then
			ok, value = pcall(debug.getstack, level, index)
		else
			ok, value = pcall(debug.getstack, level)
		end
		if not ok then
			table.insert(frames, {
				level = level,
				error = tostring(value),
			})
			break
		end
		table.insert(frames, {
			level = level,
			value = self.serializer:serialize(value),
			value_type = typeof(value),
		})
	end
	return self.Result.ok({
		frames = frames,
		count = #frames,
	})
end

function AdvancedInspector:_matchesGc(value, params, getConstants, getFunctionHash)
	local objectType = params.object_type and tostring(params.object_type) or nil
	if objectType ~= nil and typeof(value) ~= objectType and type(value) ~= objectType then
		return false
	end
	if params.table_key ~= nil then
		if type(value) ~= "table" or rawget(value, params.table_key) == nil then
			return false
		end
	end
	if params.function_hash ~= nil then
		if type(value) ~= "function" or type(getFunctionHash) ~= "function" then
			return false
		end
		local ok, hash = pcall(getFunctionHash, value)
		if not ok or hash ~= params.function_hash then
			return false
		end
	end
	if params.constant ~= nil then
		if type(value) ~= "function" or type(getConstants) ~= "function" then
			return false
		end
		local ok, constants = pcall(getConstants, value)
		if not ok or type(constants) ~= "table" then
			return false
		end
		local matched = false
		for _, constant in pairs(constants) do
			if constant == params.constant then
				matched = true
				break
			end
		end
		if not matched then
			return false
		end
	end
	if params.query ~= nil and params.query ~= "" then
		if type(value) == "function" then
			local info = self:_functionInfo(value)
			if not lowerContains(info.name or info.source or info.display, params.query) then
				return false
			end
		elseif type(value) == "table" then
			local found = false
			for key, item in pairs(value) do
				if lowerContains(key, params.query) or lowerContains(item, params.query) then
					found = true
					break
				end
			end
			if not found then
				return false
			end
		else
			if not lowerContains(value, params.query) then
				return false
			end
		end
	end
	return true
end

function AdvancedInspector:_summarizeGc(value)
	local valueType = typeof(value)
	if valueType == "Instance" then
		return {
			value_type = valueType,
			value = self.Instances.describe(value, self.handles),
		}
	end
	if type(value) == "function" then
		return {
			value_type = valueType,
			function_info = self:_functionInfo(value),
		}
	end
	if type(value) == "table" then
		local keys = {}
		local count = 0
		for key in pairs(value) do
			count += 1
			table.insert(keys, tostring(key))
			if #keys >= 10 then
				break
			end
		end
		table.sort(keys)
		return {
			value_type = valueType,
			key_count = count,
			keys = keys,
			preview = self.serializer:serialize(value),
		}
	end
	return {
		value_type = valueType,
		value = self.serializer:serialize(value),
	}
end

function AdvancedInspector:searchGcObjects(params)
	local getgc = self:_global("getgc")
	if type(getgc) ~= "function" then
		return self.Result.error("capability_unavailable", "getgc is unavailable.")
	end
	local getConstants = debug and debug.getconstants or nil
	local getFunctionHash = self:_global("getfunctionhash")
	local includeTables = params.include_tables ~= false
	local ok, values = pcall(getgc, includeTables)
	if not ok or type(values) ~= "table" then
		return self.Result.error("gc_search_failed", tostring(values))
	end
	local scanLimit = math.max(math.min(tonumber(params.scan_limit) or 5000, 20000), 1)
	local limit = math.max(math.min(tonumber(params.limit) or 100, 500), 1)
	local results = {}
	local scanned = 0
	for _, value in ipairs(values) do
		scanned += 1
		if scanned > scanLimit then
			break
		end
		if self:_matchesGc(value, params, getConstants, getFunctionHash) then
			table.insert(results, self:_summarizeGc(value))
			if #results >= limit then
				break
			end
		end
	end
	return self.Result.ok({
		results = results,
		count = #results,
		scanned = scanned,
	})
end

function AdvancedInspector:listSignalConnections(params)
	local getconnections = self:_global("getconnections")
	if type(getconnections) ~= "function" then
		return self.Result.error("capability_unavailable", "getconnections is unavailable.")
	end
	local signal, signalInfo, err = self.SignalResolver.resolve(params, self.handles, self.import)
	if not signal then
		return err
	end
	local ok, connections = pcall(getconnections, signal)
	if not ok or type(connections) ~= "table" then
		return self.Result.error("connections_failed", tostring(connections))
	end
	local limit = math.max(tonumber(params.limit) or 100, 1)
	local results = {}
	for _, connection in ipairs(connections) do
		table.insert(results, {
			enabled = connection.Enabled,
			foreign_state = connection.ForeignState,
			lua_connection = connection.LuaConnection,
			function_info = type(connection.Function) == "function" and self:_functionInfo(connection.Function) or nil,
			thread = connection.Thread and tostring(connection.Thread) or nil,
		})
		if #results >= limit then
			break
		end
	end
	return self.Result.ok({
		signal = signalInfo,
		connections = results,
		count = #results,
	})
end

function AdvancedInspector:readHiddenProperty(params)
	local instance = self.Instances.resolve(params, self.handles)
	if not instance then
		return self.Result.error("instance_not_found", "Instance ref or path was not found.")
	end
	local propertyName = tostring(params.property_name or "")
	if propertyName == "" then
		return self.Result.error("invalid_property", "property_name is required.")
	end
	local gethiddenproperty = self:_global("gethiddenproperty")
	if type(gethiddenproperty) ~= "function" then
		return self.Result.error("capability_unavailable", "gethiddenproperty is unavailable.")
	end
	local ok, value, hidden = pcall(gethiddenproperty, instance, propertyName)
	if not ok then
		return self.Result.error("hidden_property_failed", tostring(value))
	end
	return self.Result.ok({
		instance = self.Instances.describe(instance, self.handles),
		property_name = propertyName,
		value = self.serializer:serialize(value),
		value_type = typeof(value),
		was_hidden = hidden == true,
	})
end

function AdvancedInspector:isPropertyScriptable(params)
	local instance = self.Instances.resolve(params, self.handles)
	if not instance then
		return self.Result.error("instance_not_found", "Instance ref or path was not found.")
	end
	local propertyName = tostring(params.property_name or "")
	if propertyName == "" then
		return self.Result.error("invalid_property", "property_name is required.")
	end
	local isscriptable = self:_global("isscriptable")
	if type(isscriptable) ~= "function" then
		return self.Result.error("capability_unavailable", "isscriptable is unavailable.")
	end
	local ok, value = pcall(isscriptable, instance, propertyName)
	if not ok then
		return self.Result.error("isscriptable_failed", tostring(value))
	end
	return self.Result.ok({
		instance = self.Instances.describe(instance, self.handles),
		property_name = propertyName,
		scriptable = value == true,
	})
end

function AdvancedInspector:findNilInstances(params)
	local getnilinstances = self:_global("getnilinstances")
	if type(getnilinstances) ~= "function" then
		return self.Result.error("capability_unavailable", "getnilinstances is unavailable.")
	end
	local ok, instances = pcall(getnilinstances)
	if not ok or type(instances) ~= "table" then
		return self.Result.error("nil_instance_failed", tostring(instances))
	end
	local limit = math.max(tonumber(params.limit) or 100, 1)
	local results = {}
	for _, instance in ipairs(instances) do
		if typeof(instance) == "Instance" then
			local matchesClass = params.class_name == nil or instance.ClassName == params.class_name
			local matchesQuery = lowerContains(instance.Name, params.query)
			if matchesClass and matchesQuery then
				table.insert(results, self.Instances.describe(instance, self.handles))
				if #results >= limit then
					break
				end
			end
		end
	end
	return self.Result.ok({
		results = results,
		count = #results,
	})
end

return AdvancedInspector
