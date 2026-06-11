local InstanceExplorer = {}
InstanceExplorer.__index = InstanceExplorer

function InstanceExplorer.new(handles, serializer, import)
	return setmetatable({
		handles = handles,
		serializer = serializer,
		Instances = import("Core/Instances"),
		Result = import("Core/Result"),
	}, InstanceExplorer)
end

function InstanceExplorer:_resolve(params)
	local instance = self.Instances.resolve(params, self.handles)
	if not instance then
		return nil, self.Result.error(
			"instance_not_found",
			"Instance ref or path was not found.",
			{ ref = params.ref, path = params.path }
		)
	end
	return instance
end

function InstanceExplorer:_tree(instance, depth, maxDepth, maxChildren)
	local node = self.Instances.describe(instance, self.handles)
	local children = instance:GetChildren()
	node.child_count = #children
	if depth >= maxDepth then
		node.has_more = #children > 0
		return node
	end

	node.children = {}
	local childLimit = math.min(#children, maxChildren)
	for index = 1, childLimit do
		table.insert(node.children, self:_tree(children[index], depth + 1, maxDepth, maxChildren))
	end
	if #children > childLimit then
		node.truncated_children = #children - childLimit
	end
	return node
end

function InstanceExplorer:getTree(params)
	local instance, err = self:_resolve(params)
	if not instance then
		return err
	end
	return self.Result.ok(self:_tree(
		instance,
		0,
		tonumber(params.max_depth) or 2,
		tonumber(params.max_children) or 100
	))
end

function InstanceExplorer:getChildren(params)
	local instance, err = self:_resolve(params)
	if not instance then
		return err
	end
	local children = instance:GetChildren()
	local offset = math.max(tonumber(params.offset) or 0, 0)
	local limit = math.max(tonumber(params.limit) or 100, 1)
	local output = {}
	for index = offset + 1, math.min(offset + limit, #children) do
		table.insert(output, self.Instances.describe(children[index], self.handles))
	end
	return self.Result.ok({
		parent = self.Instances.describe(instance, self.handles),
		children = output,
		total = #children,
		offset = offset,
		limit = limit,
	})
end

function InstanceExplorer:find(params)
	local root = self.handles:resolve(params.root_ref)
		or self.Instances.resolvePath(params.root_path)
		or game
	local query = string.lower(tostring(params.query or ""))
	local className = params.class_name
	local limit = math.max(tonumber(params.limit) or 100, 1)
	local results = {}

	local candidates = { root }
	for _, descendant in ipairs(root:GetDescendants()) do
		table.insert(candidates, descendant)
	end
	for _, instance in ipairs(candidates) do
		local path = self.Instances.path(instance)
		local matchesText = query == ""
			or string.find(string.lower(instance.Name), query, 1, true)
			or string.find(string.lower(path), query, 1, true)
		local matchesClass = className == nil or instance.ClassName == className
		if matchesText and matchesClass then
			table.insert(results, self.Instances.describe(instance, self.handles))
			if #results >= limit then
				break
			end
		end
	end
	return self.Result.ok({ results = results, count = #results, limit = limit })
end

return InstanceExplorer
