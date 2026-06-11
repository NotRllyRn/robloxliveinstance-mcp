local Manager = {}
Manager.__index = Manager

function Manager.new(config, metadata, import)
	return setmetatable({
		config = config,
		metadata = metadata,
		import = import,
		active = nil,
		stopped = false,
	}, Manager)
end

function Manager:_construct(name)
	if name == "websocket" then
		return self.import("Transport/WebSocketTransport").new(
			self.config,
			self.metadata,
			self.import
		)
	end
	return self.import("Transport/HttpPollingTransport").new(
		self.config,
		self.metadata,
		self.import
	)
end

function Manager:run(onRequest)
	local preferred = self.config.preferredTransport == "http" and "http" or "websocket"
	local fallback = preferred == "websocket" and "http" or "websocket"

	while not self.stopped do
		local connected = false
		for _, transportName in ipairs({ preferred, fallback }) do
			if self.stopped then
				break
			end
			local transport = self:_construct(transportName)
			self.active = transport
			local ok, err = pcall(function()
				transport:run(onRequest)
			end)
			if ok then
				connected = true
				break
			end
			warn(string.format("[robloxliveinstance-mcp] %s transport failed: %s", transportName, tostring(err)))
		end
		if not connected and not self.stopped then
			task.wait(self.config.reconnectDelaySeconds or 3)
		end
	end
end

function Manager:close()
	self.stopped = true
	if self.active then
		self.active:close()
	end
end

return Manager
