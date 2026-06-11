local PropertyReader = {}
PropertyReader.__index = PropertyReader

function PropertyReader.new(handles, serializer, import)
	return setmetatable({
		handles = handles,
		serializer = serializer,
		Instances = import("Core/Instances"),
		PropertyCatalog = import("Core/PropertyCatalog"),
		Result = import("Core/Result"),
	}, PropertyReader)
end

function PropertyReader:_resolve(params)
	local instance = self.Instances.resolve(params, self.handles)
	if not instance then
		return nil, self.Result.error("instance_not_found", "Instance ref or path was not found.")
	end
	return instance
end

function PropertyReader:_defaults(instance)
	return self.PropertyCatalog.defaultsFor(instance)
end

function PropertyReader:_read(instance, propertyName)
	local ok, value = pcall(function()
		return instance[propertyName]
	end)
	if not ok then
		return {
			ok = false,
			error = tostring(value),
		}
	end
	return {
		ok = true,
		value = self.serializer:serialize(value),
		value_type = typeof(value),
	}
end

function PropertyReader:getProperties(params)
	local instance, err = self:_resolve(params)
	if not instance then
		return err
	end
	local propertyNames = params.property_names
	if type(propertyNames) ~= "table" or #propertyNames == 0 then
		propertyNames = self:_defaults(instance)
	end

	local properties = {}
	for _, propertyName in ipairs(propertyNames) do
		properties[propertyName] = self:_read(instance, propertyName)
	end

	local data = {
		instance = self.Instances.describe(instance, self.handles),
		properties = properties,
	}
	if params.include_attributes ~= false then
		data.attributes = self.serializer:serialize(instance:GetAttributes())
	end
	return self.Result.ok(data)
end

function PropertyReader:readProperty(params)
	local instance, err = self:_resolve(params)
	if not instance then
		return err
	end
	local propertyName = tostring(params.property_name or "")
	if propertyName == "" then
		return self.Result.error("invalid_property", "property_name is required.")
	end
	return self.Result.ok({
		instance = self.Instances.describe(instance, self.handles),
		property_name = propertyName,
		result = self:_read(instance, propertyName),
	})
end

return PropertyReader
