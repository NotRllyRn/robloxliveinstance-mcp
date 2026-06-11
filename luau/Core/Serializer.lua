local Instances

local Serializer = {}
Serializer.__index = Serializer

function Serializer.new(handles, import)
	Instances = Instances or import("Core/Instances")
	return setmetatable({
		handles = handles,
		maxDepth = 5,
		maxEntries = 200,
		maxStringLength = 200000,
	}, Serializer)
end

local function tagged(valueType, fields)
	fields.type = valueType
	return fields
end

function Serializer:serialize(value, depth, seen)
	depth = depth or 0
	seen = seen or {}
	local valueType = typeof(value)

	if value == nil or valueType == "boolean" or valueType == "number" then
		return value
	end
	if valueType == "string" then
		if #value > self.maxStringLength then
			return tagged("truncated_string", {
				value = string.sub(value, 1, self.maxStringLength),
				original_length = #value,
			})
		end
		return value
	end
	if valueType == "Instance" then
		return Instances.describe(value, self.handles)
	end
	if valueType == "Vector2" then
		return tagged("Vector2", { x = value.X, y = value.Y })
	end
	if valueType == "Vector3" then
		return tagged("Vector3", { x = value.X, y = value.Y, z = value.Z })
	end
	if valueType == "Color3" then
		return tagged("Color3", { r = value.R, g = value.G, b = value.B })
	end
	if valueType == "CFrame" then
		return tagged("CFrame", { components = { value:GetComponents() } })
	end
	if valueType == "UDim" then
		return tagged("UDim", { scale = value.Scale, offset = value.Offset })
	end
	if valueType == "UDim2" then
		return tagged("UDim2", {
			x = { scale = value.X.Scale, offset = value.X.Offset },
			y = { scale = value.Y.Scale, offset = value.Y.Offset },
		})
	end
	if valueType == "EnumItem" then
		return tagged("EnumItem", { value = tostring(value) })
	end
	if valueType ~= "table" then
		return tagged(valueType, { value = tostring(value) })
	end

	if depth >= self.maxDepth then
		return tagged("truncated_table", { reason = "max_depth" })
	end
	if seen[value] then
		return tagged("cycle", {})
	end
	seen[value] = true

	local output = {}
	local count = 0
	for key, item in pairs(value) do
		count += 1
		if count > self.maxEntries then
			output.__truncated = true
			break
		end
		output[tostring(key)] = self:serialize(item, depth + 1, seen)
	end
	seen[value] = nil
	return output
end

return Serializer
