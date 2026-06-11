local Players = game:GetService("Players")

local Client = {}
Client.__index = Client

local function executorInfo()
	local environment = getgenv and getgenv() or _G
	local identify = rawget(environment, "identifyexecutor")
	if type(identify) ~= "function" then
		return { name = "unknown", version = "unknown" }
	end
	local ok, name, version = pcall(identify)
	if not ok then
		return { name = "unknown", version = "unknown" }
	end
	return { name = tostring(name), version = tostring(version or "") }
end

function Client.new(config, import)
	local handles = import("Core/HandleRegistry").new()
	local serializer = import("Core/Serializer").new(handles, import)
	local localPlayer = Players.LocalPlayer
	local metadata = {
		place_id = game.PlaceId,
		game_id = game.GameId,
		job_id = game.JobId,
		user_id = localPlayer and localPlayer.UserId or 0,
		username = localPlayer and localPlayer.Name or "",
		executor = executorInfo(),
		client_version = "0.1.0",
	}

	local services = {
		instances = import("Services/InstanceExplorer").new(handles, serializer, import),
		properties = import("Services/PropertyReader").new(handles, serializer, import),
		scripts = import("Services/ScriptInspector").new(handles, serializer, import),
		advanced = import("Services/AdvancedInspector").new(handles, serializer, import),
		runtime = import("Services/RuntimeTools").new(handles, serializer, metadata, import),
		watches = import("Services/WatchTools").new(handles, serializer, import),
		executor = import("Services/LiveExecutor").new(handles, serializer, metadata, import),
	}

	return setmetatable({
		config = config,
		metadata = metadata,
		router = import("Router").new(services, import),
		transport = import("Transport/Manager").new(config, metadata, import),
	}, Client)
end

function Client:run()
	print(string.format(
		"[robloxliveinstance-mcp] connecting to %s:%d",
		self.config.host,
		self.config.port
	))
	self.transport:run(function(action, params)
		return self.router:dispatch(action, params)
	end)
end

function Client:close()
	self.transport:close()
end

return Client
