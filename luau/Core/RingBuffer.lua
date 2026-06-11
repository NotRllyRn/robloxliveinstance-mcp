local RingBuffer = {}
RingBuffer.__index = RingBuffer

function RingBuffer.new(capacity)
	return setmetatable({
		capacity = math.max(tonumber(capacity) or 200, 1),
		items = {},
		nextSeq = 1,
	}, RingBuffer)
end

function RingBuffer:push(item)
	local entry = {
		seq = self.nextSeq,
		item = item,
	}
	self.nextSeq += 1
	table.insert(self.items, entry)
	if #self.items > self.capacity then
		table.remove(self.items, 1)
	end
	return entry.seq
end

function RingBuffer:latestSeq()
	return self.nextSeq - 1
end

function RingBuffer:tail(limit)
	limit = math.max(tonumber(limit) or self.capacity, 0)
	local startIndex = math.max(#self.items - limit + 1, 1)
	local results = {}
	for index = startIndex, #self.items do
		table.insert(results, self.items[index])
	end
	return results
end

function RingBuffer:afterSeq(seq, limit)
	limit = math.max(tonumber(limit) or self.capacity, 0)
	local results = {}
	for _, entry in ipairs(self.items) do
		if entry.seq > (tonumber(seq) or 0) then
			table.insert(results, entry)
			if #results >= limit then
				break
			end
		end
	end
	return results
end

function RingBuffer:all()
	return table.clone(self.items)
end

return RingBuffer
