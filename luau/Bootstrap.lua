local root = "luau"
local configuredRoot = rawget(getgenv and getgenv() or _G, "ROBLOX_LIVE_MCP_ROOT")
if type(configuredRoot) == "string" and configuredRoot ~= "" then
	root = configuredRoot
end

local cache = {}

local function import(modulePath)
	if cache[modulePath] ~= nil then
		return cache[modulePath]
	end

	local filePath = string.format("%s/%s.lua", root, modulePath)
	local chunk, loadError = loadfile(filePath)
	if not chunk then
		error(string.format("Failed to load %s: %s", filePath, tostring(loadError)), 2)
	end

	local module = chunk()
	cache[modulePath] = module
	return module
end

local Config = import("Config")
local overrides = rawget(getgenv and getgenv() or _G, "ROBLOX_LIVE_MCP_CONFIG")
if type(overrides) == "table" then
	for key, value in pairs(overrides) do
		Config[key] = value
	end
end
if Config.moduleRoot and Config.moduleRoot ~= root then
	root = Config.moduleRoot
	cache = { Config = Config }
end

local Client = import("Client")
Client.new(Config, import):run()
