local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local WatchTools = {}
WatchTools.__index = WatchTools

local function nowMillis()
	return DateTime.now().UnixTimestampMillis
end

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(connections)
end

local function deepEqual(left, right)
	if typeof(left) ~= typeof(right) then
		return false
	end
	if type(left) ~= "table" then
		return left == right
	end
	for key, value in pairs(left) do
		if not deepEqual(value, right[key]) then
			return false
		end
	end
	for key in pairs(right) do
		if left[key] == nil then
			return false
		end
	end
	return true
end

function WatchTools.new(handles, serializer, import)
	return setmetatable({
		handles = handles,
		serializer = serializer,
		import = import,
		Instances = import("Core/Instances"),
		PropertyCatalog = import("Core/PropertyCatalog"),
		Result = import("Core/Result"),
		RingBuffer = import("Core/RingBuffer"),
		SignalResolver = import("Core/SignalResolver"),
		ScriptSupport = import("Core/ScriptSupport"),
		watches = {},
		snapshots = {},
		outgoingNamecallOriginal = nil,
	}, WatchTools)
end

function WatchTools:_global(name)
	return self.ScriptSupport.global(name)
end

function WatchTools:_newWatch(kind, capacity, ttlSeconds)
	return {
		id = "watch:" .. HttpService:GenerateGUID(false),
		kind = kind,
		buffer = self.RingBuffer.new(capacity or 200),
		connections = {},
		cursor = 0,
		started_at = nowMillis(),
		expires_at = nowMillis() + math.max(tonumber(ttlSeconds) or 120, 1) * 1000,
		active = true,
	}
end

function WatchTools:_storeWatch(watch)
	self.watches[watch.id] = watch
	return watch
end

function WatchTools:_getWatch(id, kind)
	local watch = self.watches[tostring(id or "")]
	if not watch or (kind and watch.kind ~= kind) then
		return nil, self.Result.error("unknown_watch", "watch_id was not found.")
	end
	if watch.active and nowMillis() >= watch.expires_at then
		self:_deactivateWatch(watch)
	end
	return watch
end

function WatchTools:_deactivateWatch(watch)
	if not watch.active then
		return
	end
	watch.active = false
	disconnectAll(watch.connections)
	if watch.cleanup then
		pcall(watch.cleanup)
	end
end

function WatchTools:_removeWatch(id)
	local watch = self.watches[id]
	if watch then
		self:_deactivateWatch(watch)
		self.watches[id] = nil
	end
end

function WatchTools:_drainWatch(watch, limit)
	local entries = watch.buffer:afterSeq(watch.cursor, math.max(tonumber(limit) or 100, 1))
	local output = {}
	for _, entry in ipairs(entries) do
		table.insert(output, entry.item)
		watch.cursor = entry.seq
	end
	return output
end

function WatchTools:_watchEnvelope(watch, events, extra)
	local data = {
		watch_id = watch.id,
		kind = watch.kind,
		active = watch.active,
		started_at = watch.started_at,
		expires_at = watch.expires_at,
		events = events,
		count = #events,
	}
	if extra then
		for key, value in pairs(extra) do
			data[key] = value
		end
	end
	return self.Result.ok(data)
end

function WatchTools:_push(watch, event)
	event.ts = event.ts or nowMillis()
	watch.buffer:push(event)
end

function WatchTools:_propertyValue(instance, propertyName)
	local ok, value = pcall(function()
		return instance[propertyName]
	end)
	if not ok then
		return {
			type = "error",
			message = tostring(value),
		}
	end
	return self.serializer:serialize(value)
end

function WatchTools:_resolveTarget(params)
	local instance = self.Instances.resolve(params, self.handles)
	if not instance then
		return nil, self.Result.error("instance_not_found", "Instance ref or path was not found.")
	end
	return instance
end

function WatchTools:watchInstanceChanges(params)
	if params.watch_id then
		local watch, err = self:_getWatch(params.watch_id, "instance_changes")
		if not watch then
			return err
		end
		if params.stop then
			local events = self:_drainWatch(watch, params.limit)
			self:_removeWatch(watch.id)
			return self:_watchEnvelope(watch, events, { stopped = true, target = watch.target })
		end
		return self:_watchEnvelope(watch, self:_drainWatch(watch, params.limit), {
			target = watch.target,
			property_names = watch.property_names,
		})
	end

	local instance, err = self:_resolveTarget(params)
	if not instance then
		return err
	end

	local watch = self:_newWatch("instance_changes", params.capacity, params.ttl_seconds)
	watch.instance = instance
	watch.target = self.Instances.describe(instance, self.handles)
	watch.property_names = type(params.property_names) == "table"
		and params.property_names
		or self.PropertyCatalog.defaultsFor(instance)
	local includeDescendants = params.include_descendants == true

	local function record(event)
		self:_push(watch, event)
	end

	table.insert(watch.connections, instance.AncestryChanged:Connect(function(child, parent)
		record({
			event = "ancestry_changed",
			instance = self.Instances.describe(child, self.handles),
			parent = parent and self.Instances.describe(parent, self.handles) or nil,
		})
	end))
	table.insert(watch.connections, instance.ChildAdded:Connect(function(child)
		record({
			event = "child_added",
			child = self.Instances.describe(child, self.handles),
		})
	end))
	table.insert(watch.connections, instance.ChildRemoved:Connect(function(child)
		record({
			event = "child_removed",
			child = self.Instances.describe(child, self.handles),
		})
	end))
	if instance.Destroying then
		table.insert(watch.connections, instance.Destroying:Connect(function()
			record({
				event = "destroying",
				target = watch.target,
			})
			self:_deactivateWatch(watch)
		end))
	end
	if includeDescendants then
		table.insert(watch.connections, instance.DescendantAdded:Connect(function(descendant)
			record({
				event = "descendant_added",
				descendant = self.Instances.describe(descendant, self.handles),
			})
		end))
		table.insert(watch.connections, instance.DescendantRemoving:Connect(function(descendant)
			record({
				event = "descendant_removing",
				descendant = self.Instances.describe(descendant, self.handles),
			})
		end))
	end
	for _, propertyName in ipairs(watch.property_names) do
		local ok, signal = pcall(function()
			return instance:GetPropertyChangedSignal(propertyName)
		end)
		if ok and signal then
			table.insert(watch.connections, signal:Connect(function()
				record({
					event = "property_changed",
					property_name = propertyName,
					value = self:_propertyValue(instance, propertyName),
				})
			end))
		end
	end

	self:_storeWatch(watch)
	return self:_watchEnvelope(watch, {}, {
		target = watch.target,
		property_names = watch.property_names,
	})
end

function WatchTools:traceSignalActivity(params)
	if params.watch_id then
		local watch, err = self:_getWatch(params.watch_id, "signal_activity")
		if not watch then
			return err
		end
		if params.stop then
			local events = self:_drainWatch(watch, params.limit)
			self:_removeWatch(watch.id)
			return self:_watchEnvelope(watch, events, { stopped = true, signal = watch.signal_info })
		end
		return self:_watchEnvelope(watch, self:_drainWatch(watch, params.limit), {
			signal = watch.signal_info,
		})
	end

	local signal, signalInfo, err = self.SignalResolver.resolve(params, self.handles, self.import)
	if not signal then
		return err
	end

	local watch = self:_newWatch("signal_activity", params.capacity, params.ttl_seconds)
	watch.signal_info = signalInfo
	local maxArgs = math.max(tonumber(params.max_args) or 8, 0)
	table.insert(watch.connections, signal:Connect(function(...)
		local serialized = {}
		local argCount = math.min(select("#", ...), maxArgs)
		for index = 1, argCount do
			serialized[index] = self.serializer:serialize(select(index, ...))
		end
		self:_push(watch, {
			event = "signal_fired",
			signal = signalInfo,
			arg_count = select("#", ...),
			args = serialized,
		})
	end))

	self:_storeWatch(watch)
	return self:_watchEnvelope(watch, {}, { signal = signalInfo })
end

function WatchTools:_traceMatches(trace, remote)
	if trace.root ~= game and remote ~= trace.root and not remote:IsDescendantOf(trace.root) then
		return false
	end
	if trace.remote_name_query and trace.remote_name_query ~= "" then
		if string.find(string.lower(remote.Name), string.lower(trace.remote_name_query), 1, true) == nil then
			return false
		end
	end
	return remote:IsA("RemoteEvent")
		or remote:IsA("UnreliableRemoteEvent")
		or remote:IsA("RemoteFunction")
end

function WatchTools:_recordRemote(trace, payload)
	self:_push(trace, payload)
end

function WatchTools:_attachIncomingRemote(trace, remote)
	if not self:_traceMatches(trace, remote) then
		return
	end
	if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
		table.insert(trace.connections, remote.OnClientEvent:Connect(function(...)
			local args = {}
			local argCount = math.min(select("#", ...), trace.max_args)
			for index = 1, argCount do
				args[index] = self.serializer:serialize(select(index, ...))
			end
			self:_recordRemote(trace, {
				event = "remote_event",
				direction = "server_to_client",
				method = "OnClientEvent",
				remote = self.Instances.describe(remote, self.handles),
				arg_count = select("#", ...),
				args = args,
			})
		end))
	end
end

function WatchTools:_ensureOutgoingHook()
	if self.outgoingNamecallOriginal ~= nil then
		return true
	end
	local hookmetamethod = self:_global("hookmetamethod")
	local getnamecallmethod = self:_global("getnamecallmethod")
	local checkcaller = self:_global("checkcaller")
	if type(hookmetamethod) ~= "function"
		or type(getnamecallmethod) ~= "function"
		or type(checkcaller) ~= "function" then
		return false
	end
	local original
	original = hookmetamethod(game, "__namecall", function(...)
		local method = getnamecallmethod()
		local object = select(1, ...)
		local shouldTrace = not checkcaller()
			and typeof(object) == "Instance"
			and (method == "FireServer" or method == "InvokeServer")
		local args = shouldTrace and table.pack(select(2, ...)) or nil
		local results = table.pack(pcall(original, ...))

		if shouldTrace then
			-- Keep tracing isolated so the original remote call always runs,
			-- even if serialization or watch bookkeeping fails.
			pcall(function()
				for _, watch in pairs(self.watches) do
					if watch.kind == "remote_traffic" and watch.active and watch.include_outgoing then
						if self:_traceMatches(watch, object) then
							local serialized = {}
							for index = 1, math.min(args.n, watch.max_args) do
								serialized[index] = self.serializer:serialize(args[index])
							end
							self:_recordRemote(watch, {
								event = "remote_call",
								direction = "client_to_server",
								method = method,
								remote = self.Instances.describe(object, self.handles),
								arg_count = args.n,
								args = serialized,
							})
						end
					end
				end
			end)
		end
		if not results[1] then
			return
		end
		return table.unpack(results, 2, results.n)
	end)
	self.outgoingNamecallOriginal = original
	return true
end

function WatchTools:_restoreOutgoingHookIfIdle()
	if self.outgoingNamecallOriginal == nil then
		return
	end
	for _, watch in pairs(self.watches) do
		if watch.kind == "remote_traffic" and watch.active and watch.include_outgoing then
			return
		end
	end
	local hookmetamethod = self:_global("hookmetamethod")
	if type(hookmetamethod) == "function" then
		pcall(hookmetamethod, game, "__namecall", self.outgoingNamecallOriginal)
	end
	self.outgoingNamecallOriginal = nil
end

function WatchTools:_deactivateWatch(watch)
	if not watch.active then
		return
	end
	watch.active = false
	disconnectAll(watch.connections)
	if watch.cleanup then
		pcall(watch.cleanup)
	end
	if watch.kind == "remote_traffic" then
		self:_restoreOutgoingHookIfIdle()
	end
end

function WatchTools:traceRemoteTraffic(params)
	if params.watch_id then
		local watch, err = self:_getWatch(params.watch_id, "remote_traffic")
		if not watch then
			return err
		end
		if params.stop then
			local events = self:_drainWatch(watch, params.limit)
			self:_removeWatch(watch.id)
			return self:_watchEnvelope(watch, events, { stopped = true, root = self.Instances.describe(watch.root, self.handles) })
		end
		return self:_watchEnvelope(watch, self:_drainWatch(watch, params.limit), {
			root = self.Instances.describe(watch.root, self.handles),
		})
	end

	local watch = self:_newWatch("remote_traffic", params.capacity, params.ttl_seconds or params.duration_seconds)
	watch.root = self:_resolveRoot(params)
	watch.include_incoming = params.include_incoming ~= false
	watch.include_outgoing = params.include_outgoing ~= false
	watch.max_args = math.max(tonumber(params.max_args) or 8, 0)
	watch.remote_name_query = params.query and tostring(params.query) or nil

	if watch.include_incoming then
		local candidates = { watch.root }
		for _, descendant in ipairs(watch.root:GetDescendants()) do
			table.insert(candidates, descendant)
		end
		for _, instance in ipairs(candidates) do
			self:_attachIncomingRemote(watch, instance)
		end
		table.insert(watch.connections, watch.root.DescendantAdded:Connect(function(descendant)
			self:_attachIncomingRemote(watch, descendant)
		end))
	end
	if watch.include_outgoing and not self:_ensureOutgoingHook() then
		disconnectAll(watch.connections)
		return self.Result.error(
			"capability_unavailable",
			"trace_remote_traffic outgoing capture requires hookmetamethod, getnamecallmethod, and checkcaller."
		)
	end

	self:_storeWatch(watch)
	return self:_watchEnvelope(watch, {}, {
		root = self.Instances.describe(watch.root, self.handles),
	})
end

function WatchTools:_resolveRoot(params)
	return self.handles:resolve(params.root_ref)
		or self.Instances.resolvePath(params.root_path)
		or game
end

function WatchTools:watchTaggedInstances(params)
	if params.watch_id then
		local watch, err = self:_getWatch(params.watch_id, "tagged_instances")
		if not watch then
			return err
		end
		if params.stop then
			local events = self:_drainWatch(watch, params.limit)
			self:_removeWatch(watch.id)
			return self:_watchEnvelope(watch, events, { stopped = true, tags = watch.tags })
		end
		return self:_watchEnvelope(watch, self:_drainWatch(watch, params.limit), { tags = watch.tags })
	end

	local tags = {}
	if type(params.tags) == "table" then
		for _, tag in ipairs(params.tags) do
			table.insert(tags, tostring(tag))
		end
	elseif params.tag then
		table.insert(tags, tostring(params.tag))
	end
	if #tags == 0 then
		return self.Result.error("invalid_tags", "Provide tag or tags.")
	end

	local watch = self:_newWatch("tagged_instances", params.capacity, params.ttl_seconds)
	watch.tags = tags
	for _, tag in ipairs(tags) do
		table.insert(watch.connections, CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
			self:_push(watch, {
				event = "tag_added",
				tag = tag,
				instance = self.Instances.describe(instance, self.handles),
			})
		end))
		table.insert(watch.connections, CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
			self:_push(watch, {
				event = "tag_removed",
				tag = tag,
				instance = self.Instances.describe(instance, self.handles),
			})
		end))
		if params.include_existing then
			for _, instance in ipairs(CollectionService:GetTagged(tag)) do
				self:_push(watch, {
					event = "tag_present",
					tag = tag,
					instance = self.Instances.describe(instance, self.handles),
				})
			end
		end
	end

	self:_storeWatch(watch)
	return self:_watchEnvelope(watch, {}, { tags = tags })
end

function WatchTools:_captureSnapshotMap(instance, depth, maxDepth, maxChildren, propertyNames, output)
	local path = self.Instances.path(instance)
	local properties = {}
	for _, propertyName in ipairs(propertyNames) do
		properties[propertyName] = self:_propertyValue(instance, propertyName)
	end
	output[path] = {
		name = instance.Name,
		class_name = instance.ClassName,
		properties = properties,
		child_count = #instance:GetChildren(),
	}
	if depth >= maxDepth then
		return
	end
	local children = instance:GetChildren()
	for index = 1, math.min(#children, maxChildren) do
		self:_captureSnapshotMap(children[index], depth + 1, maxDepth, maxChildren, propertyNames, output)
	end
end

function WatchTools:diffInstanceSnapshot(params)
	local maxDepth = math.max(tonumber(params.max_depth) or 2, 0)
	local maxChildren = math.max(tonumber(params.max_children) or 100, 1)
	local propertyNames = type(params.property_names) == "table" and params.property_names or nil

	if not params.snapshot_id then
		local instance, err = self:_resolveTarget(params)
		if not instance then
			return err
		end
		local snapshotId = "snapshot:" .. HttpService:GenerateGUID(false)
		local names = propertyNames or self.PropertyCatalog.defaultsFor(instance)
		local captured = {}
		self:_captureSnapshotMap(instance, 0, maxDepth, maxChildren, names, captured)
		self.snapshots[snapshotId] = {
			target = instance,
			target_info = self.Instances.describe(instance, self.handles),
			property_names = names,
			max_depth = maxDepth,
			max_children = maxChildren,
			map = captured,
			created_at = nowMillis(),
		}
		return self.Result.ok({
			snapshot_id = snapshotId,
			target = self.snapshots[snapshotId].target_info,
			property_names = names,
			entry_count = 0,
			created_at = self.snapshots[snapshotId].created_at,
		})
	end

	local snapshot = self.snapshots[tostring(params.snapshot_id)]
	if not snapshot then
		return self.Result.error("unknown_snapshot", "snapshot_id was not found.")
	end

	local currentTarget = snapshot.target
	if currentTarget.Parent == nil then
		return self.Result.error("instance_not_found", "Snapshot target no longer exists.")
	end

	local fresh = {}
	self:_captureSnapshotMap(
		currentTarget,
		0,
		maxDepth or snapshot.max_depth,
		maxChildren or snapshot.max_children,
		propertyNames or snapshot.property_names,
		fresh
	)

	local added = {}
	local removed = {}
	local changed = {}
	for path, before in pairs(snapshot.map) do
		local after = fresh[path]
		if not after then
			table.insert(removed, path)
		else
			for propertyName, beforeValue in pairs(before.properties) do
				local afterValue = after.properties[propertyName]
				if not deepEqual(beforeValue, afterValue) then
					table.insert(changed, {
						path = path,
						property_name = propertyName,
						before = beforeValue,
						after = afterValue,
					})
				end
			end
		end
	end
	for path in pairs(fresh) do
		if snapshot.map[path] == nil then
			table.insert(added, path)
		end
	end

	if params.update_baseline then
		snapshot.map = fresh
	end
	if params.stop then
		self.snapshots[tostring(params.snapshot_id)] = nil
	end

	return self.Result.ok({
		snapshot_id = params.snapshot_id,
		target = snapshot.target_info,
		added_paths = added,
		removed_paths = removed,
		changed_properties = changed,
		entry_count = #added + #removed + #changed,
	})
end

return WatchTools
