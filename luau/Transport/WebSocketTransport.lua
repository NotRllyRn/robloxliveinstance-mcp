local HttpService = game:GetService("HttpService")

local WebSocketTransport = {}
WebSocketTransport.__index = WebSocketTransport

function WebSocketTransport.new(config, metadata, import)
	return setmetatable({
		config = config,
		metadata = metadata,
		sessionId = HttpService:GenerateGUID(false),
		closed = false,
		socket = nil,
	}, WebSocketTransport)
end

function WebSocketTransport:_connect()
	local environment = getgenv and getgenv() or _G
	local websocket = rawget(environment, "WebSocket") or WebSocket
	if type(websocket) ~= "table" or type(websocket.connect) ~= "function" then
		error("WebSocket.connect is unavailable")
	end
	local url = string.format(
		"ws://%s:%d/bridge/ws?token=%s",
		self.config.host,
		self.config.port,
		HttpService:UrlEncode(self.config.token)
	)
	return websocket.connect(url)
end

function WebSocketTransport:run(onRequest)
	self.closed = false
	self.socket = self:_connect()

	self.socket.OnMessage:Connect(function(rawMessage)
		local ok, message = pcall(HttpService.JSONDecode, HttpService, rawMessage)
		if not ok or type(message) ~= "table" then
			return
		end
		if message.type == "hello_ack" then
			self.sessionId = message.session_id or self.sessionId
		elseif message.type == "request" then
			task.spawn(function()
				local payload = onRequest(message.action, message.params or {})
				self.socket:Send(HttpService:JSONEncode({
					type = "response",
					request_id = message.request_id,
					payload = payload,
				}))
			end)
		end
	end)
	self.socket.OnClose:Connect(function()
		self.closed = true
	end)

	self.socket:Send(HttpService:JSONEncode({
		type = "hello",
		session_id = self.sessionId,
		metadata = self.metadata,
	}))

	while not self.closed do
		task.wait(10)
		if not self.closed then
			self.socket:Send(HttpService:JSONEncode({
				type = "heartbeat",
				session_id = self.sessionId,
			}))
		end
	end
end

function WebSocketTransport:close()
	self.closed = true
	if self.socket then
		pcall(function()
			self.socket:Close()
		end)
	end
end

return WebSocketTransport
