local Capabilities = {}

local NAMES = {
	"getscriptbytecode",
	"getscripthash",
	"getscriptclosure",
	"decompile",
	"getsenv",
	"getscripts",
	"getrunningscripts",
	"getloadedmodules",
	"getcallingscript",
	"getconnections",
	"gethiddenproperty",
	"isscriptable",
	"getnilinstances",
	"getgc",
	"filtergc",
	"getfunctionhash",
	"hookmetamethod",
	"getnamecallmethod",
	"checkcaller",
	"base64encode",
	"loadstring",
	"setfenv",
	"getgenv",
	"request",
	"WebSocket",
}

function Capabilities.detect()
	local environment = getgenv and getgenv() or _G
	local capabilities = {}
	for _, name in ipairs(NAMES) do
		local value = rawget(environment, name)
		if name == "loadstring" and value == nil then
			value = loadstring
		elseif name == "setfenv" and value == nil then
			value = setfenv
		elseif name == "WebSocket" and value == nil then
			value = WebSocket
		end
		capabilities[name] = value ~= nil
	end
	capabilities["debug.getconstants"] = debug ~= nil and type(debug.getconstants) == "function"
	capabilities["debug.getupvalues"] = debug ~= nil and type(debug.getupvalues) == "function"
	capabilities["debug.getstack"] = debug ~= nil and type(debug.getstack) == "function"
	return capabilities
end

return Capabilities
