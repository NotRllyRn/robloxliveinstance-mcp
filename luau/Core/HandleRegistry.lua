local HttpService = game:GetService("HttpService")

local HandleRegistry = {}
HandleRegistry.__index = HandleRegistry

function HandleRegistry.new()
	return setmetatable({
		byRef = {},
		byInstance = setmetatable({}, { __mode = "k" }),
	}, HandleRegistry)
end

function HandleRegistry:get(instance)
	if typeof(instance) ~= "Instance" then
		return nil
	end
	local existing = self.byInstance[instance]
	if existing then
		return existing
	end
	local ref = "instance:" .. HttpService:GenerateGUID(false)
	self.byRef[ref] = instance
	self.byInstance[instance] = ref
	return ref
end

function HandleRegistry:resolve(ref)
	if type(ref) ~= "string" then
		return nil
	end
	local instance = self.byRef[ref]
	if instance and instance.Parent ~= nil then
		return instance
	end
	self.byRef[ref] = nil
	return nil
end

return HandleRegistry
