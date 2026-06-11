local Result = {}

function Result.ok(data)
	return { ok = true, data = data }
end

function Result.error(code, message, details)
	local value = {
		ok = false,
		error = {
			code = code,
			message = message,
		},
	}
	if details ~= nil then
		value.error.details = details
	end
	return value
end

function Result.try(callback)
	local ok, value = xpcall(callback, function(err)
		if debug and debug.traceback then
			return debug.traceback(tostring(err), 2)
		end
		return tostring(err)
	end)
	if ok then
		return Result.ok(value)
	end
	return Result.error("runtime_error", tostring(value))
end

return Result
