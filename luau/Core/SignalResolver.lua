local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local SignalResolver = {}

function SignalResolver.resolve(params, handles, import)
	local Instances = import("Core/Instances")
	local Result = import("Core/Result")
	local signalName = tostring(params.signal_name or "")
	if signalName == "" then
		return nil, nil, Result.error("invalid_signal", "signal_name is required.")
	end

	if signalName == "Heartbeat" then
		return RunService.Heartbeat, {
			signal_name = signalName,
			source = { type = "service", name = "RunService" },
		}
	end
	if signalName == "RenderStepped" and RunService.RenderStepped then
		return RunService.RenderStepped, {
			signal_name = signalName,
			source = { type = "service", name = "RunService" },
		}
	end
	if signalName == "Stepped" then
		return RunService.Stepped, {
			signal_name = signalName,
			source = { type = "service", name = "RunService" },
		}
	end

	local localPlayer = Players.LocalPlayer
	if localPlayer and (params.ref == nil and params.path == nil) then
		if signalName == "CharacterAdded" then
			return localPlayer.CharacterAdded, {
				signal_name = signalName,
				source = Instances.describe(localPlayer, handles),
			}
		end
		if signalName == "CharacterRemoving" then
			return localPlayer.CharacterRemoving, {
				signal_name = signalName,
				source = Instances.describe(localPlayer, handles),
			}
		end
	end

	if params.ref == nil and params.path == nil then
		if signalName == "InputBegan" then
			return UserInputService.InputBegan, {
				signal_name = signalName,
				source = { type = "service", name = "UserInputService" },
			}
		end
		if signalName == "InputEnded" then
			return UserInputService.InputEnded, {
				signal_name = signalName,
				source = { type = "service", name = "UserInputService" },
			}
		end
		if signalName == "InputChanged" then
			return UserInputService.InputChanged, {
				signal_name = signalName,
				source = { type = "service", name = "UserInputService" },
			}
		end
	end

	local instance = Instances.resolve(params, handles)
	if not instance then
		return nil, nil, Result.error("instance_not_found", "Instance ref or path was not found.")
	end
	local ok, signal = pcall(function()
		return instance[signalName]
	end)
	if not ok or typeof(signal) ~= "RBXScriptSignal" then
		return nil, nil, Result.error(
			"signal_not_found",
			("Signal %q was not found on the target instance."):format(signalName)
		)
	end
	return signal, {
		signal_name = signalName,
		source = Instances.describe(instance, handles),
	}
end

return SignalResolver
