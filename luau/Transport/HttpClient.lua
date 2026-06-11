local HttpService = game:GetService("HttpService")

local HttpClient = {}

local function resolveRequest()
	local environment = getgenv and getgenv() or _G
	local direct = rawget(environment, "request") or rawget(environment, "http_request")
	if type(direct) == "function" then
		return direct
	end
	local synValue = rawget(environment, "syn")
	if type(synValue) == "table" and type(synValue.request) == "function" then
		return synValue.request
	end
	return nil
end

function HttpClient.request(config, method, path, payload)
	local url = string.format("http://%s:%d%s", config.host, config.port, path)
	local body = HttpService:JSONEncode(payload or {})
	local headers = {
		["Content-Type"] = "application/json",
		["Authorization"] = "Bearer " .. config.token,
	}
	local requestFn = resolveRequest()
	if requestFn then
		local response = requestFn({
			Url = url,
			Method = method,
			Headers = headers,
			Body = method == "GET" and nil or body,
		})
		if not response or response.Success == false then
			error("HTTP bridge request failed: " .. tostring(response and response.StatusMessage))
		end
		return HttpService:JSONDecode(response.Body)
	end

	local response = HttpService:RequestAsync({
		Url = url,
		Method = method,
		Headers = headers,
		Body = method == "GET" and nil or body,
	})
	if not response.Success then
		error("HTTP bridge request failed: " .. tostring(response.StatusMessage))
	end
	return HttpService:JSONDecode(response.Body)
end

return HttpClient
