local Instances = {}

local function escapeSegment(name)
	return (string.gsub(string.gsub(name, "~", "~0"), "/", "~1"))
end

local function unescapeSegment(name)
	return (string.gsub(string.gsub(name, "~1", "/"), "~0", "~"))
end

function Instances.path(instance)
	if instance == game then
		return "game"
	end

	local parts = { "game" }
	local cursor = instance
	while cursor and cursor ~= game do
		table.insert(parts, 2, escapeSegment(cursor.Name))
		cursor = cursor.Parent
	end
	return table.concat(parts, "/")
end

function Instances.resolvePath(path)
	if path == nil or path == "" or path == "game" then
		return game
	end
	if type(path) ~= "string" then
		return nil
	end

	local cursor = game
	if string.sub(path, 1, 5) == "game/" then
		for segment in string.gmatch(string.sub(path, 6), "[^/]+") do
			cursor = cursor:FindFirstChild(unescapeSegment(segment))
			if not cursor then
				return nil
			end
		end
		return cursor
	end
	if string.sub(path, 1, 5) ~= "game." then
		return nil
	end
	for segment in string.gmatch(string.sub(path, 6), "[^%.]+") do
		cursor = cursor:FindFirstChild(segment)
		if not cursor then
			return nil
		end
	end
	return cursor
end

function Instances.resolve(params, handles)
	local instance = handles:resolve(params.ref)
	if instance then
		return instance
	end
	return Instances.resolvePath(params.path)
end

function Instances.describe(instance, handles)
	return {
		type = "Instance",
		ref = handles:get(instance),
		name = instance.Name,
		class_name = instance.ClassName,
		path = Instances.path(instance),
	}
end

return Instances
