local LOD = {}
local ALL = 0xffffffff
local HORIZONTAL = 2 ^ 20
local OWNER = 2 ^ 21

local function encode(x, y, horizontal, length, owner)
	return x + y * 128 + (length - 1) * 16384 + (if horizontal then HORIZONTAL else 0) + owner * OWNER
end

local function compact(chunk)
	local out = buffer.create(chunk.count * 4)
	local w, stride = chunk.w, chunk.w * chunk.h * 4
	local i, count, islands = 0, 0, chunk.count
	while i < chunk.count do
		local offset = i * 8
		local key, last = buffer.readu32(chunk.packed, offset), buffer.readu32(chunk.packed, offset + 4)
		local owner, tile, side = key // stride, key % stride // 4, key % 4
		-- At overview scale a single isolated tile needs one visible mark. Keep these
		-- apart from the span merging so a small island never gets pulled into a coast.
		if side == 0 and last == key and i + 3 < chunk.count
			and buffer.readu32(chunk.packed, offset + 8) == key + 1 and buffer.readu32(chunk.packed, offset + 12) == key + 1
			and buffer.readu32(chunk.packed, offset + 16) == key + 2 and buffer.readu32(chunk.packed, offset + 20) == key + 2
			and buffer.readu32(chunk.packed, offset + 24) == key + 3 and buffer.readu32(chunk.packed, offset + 28) == key + 3 then
			islands -= 1
			buffer.writeu32(out, islands * 4, encode(tile % w, tile // w, true, 1, owner))
			i += 4
			continue
		end
		local horizontal = side >= 2
		local x = tile % w + (if side == 1 then 1 else 0)
		local y = tile // w + (if side == 3 then 1 else 0)
		local length = (last - key) / (if horizontal then 4 else w * 4) + 1
		buffer.writeu32(out, count * 4, encode(x, y, horizontal, length, owner))
		count += 1
		i += 1
	end
	return out, count, islands
end

local function level(src, count, islands, block)
	local groups, order = {}, {}
	local original = buffer.len(src) // 4
	for i = 0, count - 1 do
		local edge = buffer.readu32(src, i * 4)
		local x, y = bit32.extract(edge, 0, 7), bit32.extract(edge, 7, 7)
		local horizontal, owner = bit32.btest(edge, HORIZONTAL), edge // OWNER
		local start, minor = if horizontal then x else y, if horizontal then y else x
		local length = bit32.extract(edge, 14, 6) + 1
		local key = owner * 256 + (if horizontal then 128 else 0) + minor // block
		local g = groups[key]
		if not g then
			g = { low = 0, high = 0, min = minor, max = minor, owner = owner, horizontal = horizontal, originals = {} }
			groups[key] = g
			order[#order + 1] = g
		end
		g.min, g.max = math.min(g.min, minor), math.max(g.max, minor)
		g.originals[#g.originals + 1] = edge
		-- Union the spans in a 64-cell row/column without filling holes or mixing owners.
		local stop = start + length
		if start < 32 then
			local width = math.min(stop, 32) - start
			g.low = bit32.bor(g.low, bit32.lshift(bit32.rshift(ALL, 32 - width), start))
		end
		if stop > 32 then
			local shift = math.max(0, start - 32)
			g.high = bit32.bor(g.high, bit32.lshift(bit32.rshift(ALL, 64 - stop + shift), shift))
		end
	end
	local island_bytes = (original - islands) * 4
	local out = buffer.create(count * 4 + island_bytes)
	local n = 0
	for _, g in order do
		local before = n
		local minor = math.round((g.min + g.max) * .5)
		for half = 0, 1 do
			local mask = if half == 0 then g.low else g.high
			while mask ~= 0 and n - before < #g.originals do
				local first = bit32.countrz(mask)
				local length = bit32.countrz(bit32.bnot(bit32.rshift(mask, first)))
				local major = first + half * 32
				local x, y = if g.horizontal then major else minor, if g.horizontal then minor else major
				buffer.writeu32(out, n * 4, encode(x, y, g.horizontal, length, g.owner))
				n += 1
				mask = bit32.band(mask, bit32.lshift(ALL, first + length))
			end
		end
		if n - before >= #g.originals then
			n = before
			for _, edge in g.originals do
				buffer.writeu32(out, n * 4, edge)
				n += 1
			end
		end
	end
	if island_bytes > 0 then
		buffer.copy(out, n * 4, src, islands * 4, island_bytes)
		n += island_bytes // 4
	end
	if n == original then return nil end
	return { packed = out, count = n }
end

function LOD.build(chunk)
	local src, count, islands = compact(chunk)
	chunk.lod2, chunk.lod4 = level(src, count, islands, 2), level(src, count, islands, 4)
end

-- Keep the approximation below both a physical-pixel and texture-pixel limit.
function LOD.choose(scale, pixelX, pixelY)
	local limit = math.min(2.5, .58 * math.min(pixelX, pixelY))
	return if scale * 2 <= limit then 4 elseif scale <= limit then 2 else 1
end

return LOD
