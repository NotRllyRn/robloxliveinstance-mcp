local HttpService = game:GetService("HttpService")

local HttpPollingTransport = {}
HttpPollingTransport.__index = HttpPollingTransport

function HttpPollingTransport.new(config, metadata, import)
	return setmetatable({
		config = config,
		metadata = metadata,
		http = import("Transport/HttpClient"),
		sessionId = HttpService:GenerateGUID(false),
		closed = false,
	}, HttpPollingTransport)
end

function HttpPollingTransport:run(onRequest)
	self.closed = false
	local hello = self.http.request(self.config, "POST", "/bridge/hello", {
		token = self.config.token,
		session_id = self.sessionId,
		metadata = self.metadata,
	})
	if hello.ok ~= true then
		error("Bridge rejected HTTP hello: " .. HttpService:JSONEncode(hello))
	end
	self.sessionId = hello.session_id

	while not self.closed do
		local ok, message = pcall(self.http.request, self.config, "POST", "/bridge/poll", {
			token = self.config.token,
			session_id = self.sessionId,
		})
		if ok and type(message) == "table" and message.type == "request" then
			local payload = onRequest(message.action, message.params or {})
			self.http.request(self.config, "POST", "/bridge/respond", {
				token = self.config.token,
				session_id = self.sessionId,
				request_id = message.request_id,
				payload = payload,
			})
		elseif not ok then
			task.wait(self.config.pollRetrySeconds or 1)
		end
	end
end

function HttpPollingTransport:close()
	self.closed = true
end

return HttpPollingTransport
