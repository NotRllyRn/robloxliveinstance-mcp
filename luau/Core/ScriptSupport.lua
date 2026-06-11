local ScriptSupport = {}

function ScriptSupport.global(name)
	local environment = getgenv and getgenv() or _G
	return rawget(environment, name) or rawget(_G, name)
end

function ScriptSupport.resolveScript(params, handles, import, allowServerScript)
	local Instances = import("Core/Instances")
	local Result = import("Core/Result")
	local instance = Instances.resolve(params, handles)
	if not instance or not (instance:IsA("BaseScript") or instance:IsA("ModuleScript")) then
		return nil, Result.error("script_not_found", "Target is not a script instance.")
	end
	if not allowServerScript and instance:IsA("Script") then
		return nil, Result.error(
			"server_script_excluded",
			"Server Script bytecode inspection is intentionally disabled."
		)
	end
	return instance
end

function ScriptSupport.getClosure(params, handles, import, allowServerScript)
	local Result = import("Core/Result")
	local instance, err = ScriptSupport.resolveScript(params, handles, import, allowServerScript)
	if not instance then
		return nil, nil, err
	end
	local fn = ScriptSupport.global("getscriptclosure")
	if type(fn) ~= "function" then
		return nil, nil, Result.error("capability_unavailable", "getscriptclosure is unavailable.")
	end
	local ok, closure = pcall(fn, instance)
	if not ok or type(closure) ~= "function" then
		return nil, nil, Result.error("closure_failed", tostring(closure))
	end
	return instance, closure
end

return ScriptSupport
