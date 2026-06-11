local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local RuntimeTools = {}
RuntimeTools.__index = RuntimeTools

local SCREENSHOT_FUNCTIONS = {
	"getscreenshot",
	"capture_screenshot",
	"screenshot",
}

local function nowMillis()
	return DateTime.now().UnixTimestampMillis
end

local function lowerContains(value, needle)
	if needle == nil or needle == "" then
		return true
	end
	return string.find(string.lower(tostring(value)), string.lower(tostring(needle)), 1, true) ~= nil
end

local function appendSample(samples, value, maxSamples)
	table.insert(samples, value)
	if #samples > maxSamples then
		table.remove(samples, 1)
	end
end

local function average(samples)
	if #samples == 0 then
		return nil
	end
	local total = 0
	for _, sample in ipairs(samples) do
		total += sample
	end
	return total / #samples
end

function RuntimeTools.new(handles, serializer, sessionInfo, import)
	local self = setmetatable({
		handles = handles,
		serializer = serializer,
		sessionInfo = sessionInfo,
		Instances = import("Core/Instances"),
		PropertyCatalog = import("Core/PropertyCatalog"),
		Result = import("Core/Result"),
		RingBuffer = import("Core/RingBuffer"),
		ScriptSupport = import("Core/ScriptSupport"),
		logBuffer = import("Core/RingBuffer").new(1000),
		heartbeatSamples = {},
		renderSamples = {},
	}, RuntimeTools)
	self:_seedLogs()
	self:_attachSamplers()
	return self
end

function RuntimeTools:_global(name)
	return self.ScriptSupport.global(name)
end

function RuntimeTools:_seedLogs()
	local function pushLog(message, messageType)
		local level = "info"
		local enumText = tostring(messageType)
		if string.find(enumText, "Warning", 1, true) then
			level = "warning"
		elseif string.find(enumText, "Error", 1, true) then
			level = "error"
		elseif string.find(enumText, "Output", 1, true) then
			level = "info"
		end
		self.logBuffer:push({
			ts = nowMillis(),
			level = level,
			message = tostring(message),
			message_type = enumText,
		})
	end

	local ok, history = pcall(function()
		return LogService:GetLogHistory()
	end)
	if ok and type(history) == "table" then
		for _, entry in ipairs(history) do
			pushLog(entry.message or entry.Message or "", entry.messageType or entry.MessageType or "history")
		end
	end

	LogService.MessageOut:Connect(pushLog)
end

function RuntimeTools:_attachSamplers()
	RunService.Heartbeat:Connect(function(dt)
		appendSample(self.heartbeatSamples, dt, 120)
	end)
	if RunService.RenderStepped then
		RunService.RenderStepped:Connect(function(dt)
			appendSample(self.renderSamples, dt, 120)
		end)
	end
end

function RuntimeTools:_fps(samples)
	local avg = average(samples)
	if avg == nil or avg <= 0 then
		return nil
	end
	return math.floor((1 / avg) * 10 + 0.5) / 10
end

function RuntimeTools:_resolveRoot(params, refKey, pathKey)
	local root = self.handles:resolve(params[refKey])
		or self.Instances.resolvePath(params[pathKey])
		or game
	return root
end

function RuntimeTools:_matchLogEntry(entry, params)
	if params.level and params.level ~= "" and entry.level ~= params.level then
		return false
	end
	if not lowerContains(entry.message, params.filter_text) then
		return false
	end
	local since = tonumber(params.since)
	if since and entry.ts < since then
		return false
	end
	return true
end

function RuntimeTools:_formatLogEntries(entries)
	local output = {}
	local nextSince = 0
	for _, entry in ipairs(entries) do
		table.insert(output, {
			seq = entry.seq,
			ts = entry.item.ts,
			level = entry.item.level,
			message = entry.item.message,
			message_type = entry.item.message_type,
		})
		nextSince = math.max(nextSince, entry.item.ts)
	end
	return output, nextSince
end

function RuntimeTools:getRuntimeLogs(params)
	local matched = {}
	for _, entry in ipairs(self.logBuffer:all()) do
		if self:_matchLogEntry(entry.item, params) then
			table.insert(matched, entry)
		end
	end
	local tail = math.max(tonumber(params.tail) or 100, 1)
	if #matched > tail then
		local trimmed = {}
		for index = #matched - tail + 1, #matched do
			table.insert(trimmed, matched[index])
		end
		matched = trimmed
	end
	local entries, nextSince = self:_formatLogEntries(matched)
	return self.Result.ok({
		entries = entries,
		count = #entries,
		next_since = nextSince,
		next_cursor = self.logBuffer:latestSeq(),
	})
end

function RuntimeTools:tailRuntimeLogs(params)
	local cursor = tonumber(params.cursor)
	local limit = math.max(tonumber(params.limit) or 100, 1)
	local candidates = cursor and self.logBuffer:afterSeq(cursor, limit * 4) or self.logBuffer:tail(limit)
	local matched = {}
	for _, entry in ipairs(candidates) do
		if self:_matchLogEntry(entry.item, params) then
			table.insert(matched, entry)
			if #matched >= limit then
				break
			end
		end
	end
	local entries, nextSince = self:_formatLogEntries(matched)
	return self.Result.ok({
		cursor = self.logBuffer:latestSeq(),
		entries = entries,
		count = #entries,
		next_since = nextSince,
	})
end

function RuntimeTools:_instanceSummary(instance)
	return instance and self.Instances.describe(instance, self.handles) or nil
end

function RuntimeTools:_propertySnapshot(instance, propertyNames)
	local properties = {}
	for _, propertyName in ipairs(propertyNames) do
		local ok, value = pcall(function()
			return instance[propertyName]
		end)
		properties[propertyName] = ok and self.serializer:serialize(value) or {
			type = "error",
			message = tostring(value),
		}
	end
	return properties
end

function RuntimeTools:_visibleScreenGuis(playerGui)
	local results = {}
	if not playerGui then
		return results
	end
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") and child.Enabled then
			table.insert(results, {
				ref = self.handles:get(child),
				name = child.Name,
				path = self.Instances.path(child),
				display_order = child.DisplayOrder,
				ignore_gui_inset = child.IgnoreGuiInset,
				descendant_count = #child:GetDescendants(),
			})
		end
	end
	table.sort(results, function(a, b)
		if a.display_order == b.display_order then
			return a.name < b.name
		end
		return a.display_order > b.display_order
	end)
	return results
end

function RuntimeTools:getClientSnapshot(_params)
	local localPlayer = Players.LocalPlayer
	local character = localPlayer and localPlayer.Character or nil
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") or nil
	local currentCamera = Workspace.CurrentCamera
	local equippedTool = nil
	if character then
		equippedTool = character:FindFirstChildOfClass("Tool")
	end
	local focusedTextBox = UserInputService:GetFocusedTextBox()

	local inputInfo = {
		mouse_enabled = UserInputService.MouseEnabled,
		keyboard_enabled = UserInputService.KeyboardEnabled,
		touch_enabled = UserInputService.TouchEnabled,
		gamepad_enabled = UserInputService.GamepadEnabled,
		preferred_input = UserInputService.PreferredInput and tostring(UserInputService.PreferredInput) or nil,
		last_input_type = tostring(UserInputService:GetLastInputType()),
		focused_text_box = self:_instanceSummary(focusedTextBox),
	}

	return self.Result.ok({
		player = localPlayer and {
			instance = self:_instanceSummary(localPlayer),
			attributes = self.serializer:serialize(localPlayer:GetAttributes()),
			team = self.serializer:serialize(localPlayer.Team),
			neutral = localPlayer.Neutral,
			player_gui = self:_instanceSummary(localPlayer:FindFirstChildOfClass("PlayerGui")),
		} or nil,
		character = character and {
			instance = self:_instanceSummary(character),
			humanoid = humanoid and {
				instance = self:_instanceSummary(humanoid),
				properties = self:_propertySnapshot(humanoid, self.PropertyCatalog.CLASS_PROPERTIES.Humanoid),
			} or nil,
			root_part = rootPart and {
				instance = self:_instanceSummary(rootPart),
				properties = self:_propertySnapshot(rootPart, self.PropertyCatalog.CLASS_PROPERTIES.BasePart),
			} or nil,
			equipped_tool = self:_instanceSummary(equippedTool),
		} or nil,
		camera = currentCamera and {
			instance = self:_instanceSummary(currentCamera),
			properties = self:_propertySnapshot(currentCamera, self.PropertyCatalog.CLASS_PROPERTIES.Camera),
		} or nil,
		active_screen_guis = self:_visibleScreenGuis(localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui") or nil),
		input = inputInfo,
		services = {
			workspace = {
				streaming_enabled = Workspace.StreamingEnabled,
				distributed_game_time = Workspace.DistributedGameTime,
			},
			lighting = {
				brightness = Lighting.Brightness,
				clock_time = Lighting.ClockTime,
				global_shadows = Lighting.GlobalShadows,
			},
			replicated_storage = {
				child_count = #ReplicatedStorage:GetChildren(),
			},
			players = {
				count = #Players:GetPlayers(),
			},
		},
		session = self.sessionInfo,
	})
end

function RuntimeTools:getMemoryStats(params)
	local requestedTags = {}
	if type(params.tags) == "table" then
		for _, name in ipairs(params.tags) do
			requestedTags[tostring(name)] = true
		end
	end

	local categories = {}
	for _, tag in ipairs(Enum.DeveloperMemoryTag:GetEnumItems()) do
		local tagName = tag.Name
		if next(requestedTags) == nil or requestedTags[tagName] then
			local ok, value = pcall(function()
				return Stats:GetMemoryUsageMbForTag(tag)
			end)
			categories[tagName] = ok and value or nil
		end
	end

	local physicsFps = nil
	local physicsOk, physicsValue = pcall(function()
		return Workspace:GetRealPhysicsFPS()
	end)
	if physicsOk then
		physicsFps = physicsValue
	end

	return self.Result.ok({
		total_mb = Stats:GetTotalMemoryUsageMb(),
		categories = categories,
		perf = {
			heartbeat_fps_estimate = self:_fps(self.heartbeatSamples),
			render_fps_estimate = self:_fps(self.renderSamples),
			physics_fps = physicsFps,
		},
		timestamp = nowMillis(),
	})
end

function RuntimeTools:_remoteDetails(instance)
	local details = {
		remote = self.Instances.describe(instance, self.handles),
		parent = instance.Parent and self.Instances.describe(instance.Parent, self.handles) or nil,
		attributes = self.serializer:serialize(instance:GetAttributes()),
	}
	if instance:IsA("RemoteFunction") then
		details.has_on_client_invoke = type(instance.OnClientInvoke) == "function"
	else
		local getconnections = self:_global("getconnections")
		if type(getconnections) == "function" then
			local ok, connections = pcall(getconnections, instance.OnClientEvent)
			if ok and type(connections) == "table" then
				details.on_client_event_connections = #connections
			end
		end
	end
	return details
end

function RuntimeTools:getRemoteOverview(params)
	local root = self:_resolveRoot(params, "root_ref", "root_path")
	local limit = math.max(tonumber(params.limit) or 200, 1)
	local results = {}
	local candidates = { root }
	for _, descendant in ipairs(root:GetDescendants()) do
		table.insert(candidates, descendant)
	end
	for _, instance in ipairs(candidates) do
		if instance:IsA("RemoteEvent")
			or instance:IsA("RemoteFunction")
			or instance:IsA("UnreliableRemoteEvent") then
			if lowerContains(instance.Name, params.query) then
				table.insert(results, self:_remoteDetails(instance))
				if #results >= limit then
					break
				end
			end
		end
	end
	return self.Result.ok({
		root = self.Instances.describe(root, self.handles),
		results = results,
		count = #results,
	})
end

function RuntimeTools:getTaggedInstances(params)
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

	local limit = math.max(tonumber(params.limit) or 200, 1)
	local perTag = {}
	local total = 0
	for _, tag in ipairs(tags) do
		perTag[tag] = {}
		for _, instance in ipairs(CollectionService:GetTagged(tag)) do
			if params.class_name == nil or instance.ClassName == params.class_name then
				table.insert(perTag[tag], self.Instances.describe(instance, self.handles))
				total += 1
				if #perTag[tag] >= limit then
					break
				end
			end
		end
	end
	return self.Result.ok({
		tags = tags,
		results = perTag,
		total = total,
	})
end

function RuntimeTools:getStreamingDiagnostics(params)
	local localPlayer = Players.LocalPlayer
	local character = localPlayer and localPlayer.Character or nil
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") or nil
	local radius = math.max(tonumber(params.radius) or 256, 1)
	local nearbyParts = 0
	local nearbyModels = {}

	if rootPart then
		for _, descendant in ipairs(Workspace:GetDescendants()) do
			if descendant:IsA("BasePart") then
				local distance = (descendant.Position - rootPart.Position).Magnitude
				if distance <= radius then
					nearbyParts += 1
					if descendant.Parent and descendant.Parent:IsA("Model") then
						nearbyModels[descendant.Parent] = true
					end
				end
			end
		end
	end

	local tagVisibility = {}
	if type(params.tags) == "table" then
		for _, tag in ipairs(params.tags) do
			local visible = {}
			for _, instance in ipairs(CollectionService:GetTagged(tag)) do
				table.insert(visible, self.Instances.describe(instance, self.handles))
				if #visible >= 50 then
					break
				end
			end
			tagVisibility[tostring(tag)] = visible
		end
	end

	local nearbyModelCount = 0
	for _ in pairs(nearbyModels) do
		nearbyModelCount += 1
	end

	return self.Result.ok({
		workspace = {
			streaming_enabled = Workspace.StreamingEnabled,
			streaming_min_radius = Workspace.StreamingMinRadius,
			streaming_target_radius = Workspace.StreamingTargetRadius,
			streaming_integrity_mode = tostring(Workspace.StreamingIntegrityMode),
			distributed_game_time = Workspace.DistributedGameTime,
		},
		player_root = self:_instanceSummary(rootPart),
		radius = radius,
		nearby = {
			basepart_count = nearbyParts,
			model_count = nearbyModelCount,
		},
		tag_visibility = tagVisibility,
	})
end

function RuntimeTools:getServiceOverview(params)
	local limit = math.max(tonumber(params.limit) or 50, 1)
	local services = {}
	for _, child in ipairs(game:GetChildren()) do
		table.insert(services, {
			service = self.Instances.describe(child, self.handles),
			child_count = #child:GetChildren(),
			descendant_count = #child:GetDescendants(),
			attributes = self.serializer:serialize(child:GetAttributes()),
		})
	end
	table.sort(services, function(a, b)
		return a.service.name < b.service.name
	end)
	if #services > limit then
		local trimmed = {}
		for index = 1, limit do
			table.insert(trimmed, services[index])
		end
		services = trimmed
	end
	return self.Result.ok({
		services = services,
		count = #services,
	})
end

function RuntimeTools:captureScreenshot(_params)
	local readfile = self:_global("readfile")
	local base64encode = self:_global("base64encode")
	for _, fnName in ipairs(SCREENSHOT_FUNCTIONS) do
		local fn = self:_global(fnName)
		if type(fn) == "function" then
			local ok, result = pcall(fn)
			if not ok then
				return self.Result.error("screenshot_failed", tostring(result))
			end
			if type(result) == "table" then
				return self.Result.ok({
					api = fnName,
					result = self.serializer:serialize(result),
					note = "Executor-specific screenshot response returned without a standard wire format.",
				})
			end
			if type(result) == "string" and type(readfile) == "function" and type(base64encode) == "function" then
				local readOk, bytes = pcall(readfile, result)
				if readOk and type(bytes) == "string" then
					local encodeOk, encoded = pcall(base64encode, bytes)
					if encodeOk and type(encoded) == "string" then
						return self.Result.ok({
							api = fnName,
							path = result,
							encoding = "base64",
							data = encoded,
						})
					end
				end
			end
			return self.Result.ok({
				api = fnName,
				result = self.serializer:serialize(result),
				note = "Screenshot API exists, but this executor did not expose a standardized binary payload.",
			})
		end
	end
	return self.Result.error(
		"capability_unavailable",
		"capture_screenshot requires an executor-specific screenshot API."
	)
end

return RuntimeTools
