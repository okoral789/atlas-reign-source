local Field = if game ~= nil then require(script.Parent.BorderField) else require("./BorderField")
local Strokes = {}

local EMPTY = 0xffffffff
-- Keep cleared pixels in the sparse list until compaction, so patches can reuse their slots.
local REMOVED = EMPTY - 1
local HIGH_BYTE = 0x1000000
Strokes.PAINT_INTERVAL = 1 / 15

function Strokes.prepare(w, h, styles, reuse, output, time)
	local field = reuse
	if not field or field.w ~= w or field.h ~= h then
		field = { w = w, h = h, pixels = {}, palettes = {}, strokes = buffer.create(w * h * 4) }
	end
	field.output = output
	table.clear(field.pixels)
	field.live = 0
	buffer.fill(field.strokes, 0, 255)
	buffer.fill(output, 0, 0)
	if field.styles ~= styles then
		field.styles = styles
		field.palette_at = nil
		table.clear(field.palettes)
	end
	local at = field.palette_at
	if at == nil or time < at or time - at >= Strokes.PAINT_INTERVAL then
		Field.update_palettes(field, time, styles)
		field.palette_at = time
	end
	return field
end

-- Two weighted rows or columns keep a newly projected stroke narrow at any zoom.
local function axis(info, scale, origin, low, high, size)
	info = info or { start = {}, finish = {}, base = {}, fraction = {} }
	local start, finish, base, fraction = info.start, info.finish, info.base, info.fraction
	for tile = low, high do
		local p = tile * scale + origin
		start[tile] = math.max(0, math.floor(p))
		finish[tile] = math.min(size - 1, math.ceil(p) - 1)
		local b = math.floor(p - .5)
		base[tile] = b
		fraction[tile] = math.floor((p - .5 - b) * 255 + .5)
	end
	return info
end

function Strokes.transform(field, scaleX, scaleY, tx, ty, x0, y0, x1, y1)
	field.x = axis(field.x, scaleX, tx, x0, x1, field.w)
	field.y = axis(field.y, scaleY, ty, y0, y1, field.h)
end

function Strokes.project(field, contour, detail, clip)
	local w, h = field.w, field.h
	local axisX, axisY = field.x, field.y
	local ox, oy = contour.ox, contour.oy
	local cw, ch = contour.w, contour.h
	local edgeStride = cw * ch * 4
	local simplified = if detail == 4 then contour.lod4 or contour.lod2 elseif detail == 2 then contour.lod2 else nil
	local packed, count = if simplified then simplified.packed else contour.packed, if simplified then simplified.count else contour.count
	local strokes, output, palettes, pixels = field.strokes, field.output, field.palettes, field.pixels
	if contour.owners then
		local styled = false
		for owner in contour.owners do
			if palettes[owner] then styled = true; break end
		end
		if not styled then return end
	end
	local append, live = #pixels, field.live
	local stride = if simplified then 4 else 8
	local ownerStride = if simplified then 2097152 else edgeStride
	for i = 0, count - 1 do
		local key = buffer.readu32(packed, i * stride)
		local owner = key // ownerStride
		local palette = palettes[owner]
		if not palette then continue end
		local x, y, side, horizontal, length
		if simplified then
			x, y, side = bit32.extract(key, 0, 7) + ox, bit32.extract(key, 7, 7) + oy, 0
			horizontal = bit32.btest(key, 1048576)
			length = bit32.extract(key, 14, 6) + 1
		else
			local tile = key % edgeStride // 4
			x, y, side = tile % cw + ox, tile // cw + oy, key % 4
			horizontal = side >= 2
			local last = buffer.readu32(packed, i * 8 + 4)
			length = (last - key) / (if horizontal then 4 else cw * 4) + 1
		end
		local major = if horizontal then axisX else axisY
		local minor = if horizontal then axisY else axisX
		local from = if horizontal then x else y
		local along = if simplified then (if horizontal then y else x) elseif horizontal then y + side - 2 else x + side
		local across = if horizontal then h else w
		local first, final = major.start[from], major.finish[from + length]
		local minorFirst, minorLast = 0, across - 1
		if clip then
			first = math.max(first, if horizontal then clip[1] else clip[2])
			final = math.min(final, if horizontal then clip[3] else clip[4])
			minorFirst, minorLast = if horizontal then clip[2] else clip[1], if horizontal then clip[4] else clip[3]
		end
		if final < first then continue end
		local base, fraction = minor.base[along], minor.fraction[along]
		if base < -1 or base >= across then continue end
		local increment, rowStride = if horizontal then 4 else w * 4, if horizontal then w * 4 else 4
		local phase = (x * 3 + y * 2) % 128
		local color = palette[phase]
		for neighbor = 0, 1 do
			local line = base + neighbor
			local distance = if neighbor == 0 then fraction else 255 - fraction
			if line < minorFirst or line > minorLast or distance >= 232 then continue end
			-- High byte is coverage rank, low bits store the owner and animation phase.
			local rank = distance * HIGH_BYTE
			local threshold = rank + HIGH_BYTE - 1
			local tag = rank + owner * 128 + phase
			local rgba = color[2] + math.floor((255 - distance) * color[4]) * HIGH_BYTE
			local offset = line * rowStride + first * increment
			for _ = first, final do
				local previous = buffer.readu32(strokes, offset)
				if previous > threshold then
					if previous >= REMOVED then live += 1 end
					if previous == EMPTY then
						append += 1
						pixels[append] = offset
					end
					buffer.writeu32(strokes, offset, tag)
					buffer.writeu32(output, offset, rgba)
				end
				offset += increment
			end
		end
	end
	field.live = live
end

function Strokes.clear_rect(field, clip)
	local w, strokes, output = field.w, field.strokes, field.output
	local x0, y0, x1, y1 = clip[1], clip[2], clip[3], clip[4]
	local live = field.live
	local bytes = (x1 - x0 + 1) * 4
	for y = y0, y1 do
		local first = (y * w + x0) * 4
		buffer.fill(output, first, 0, bytes)
		for offset = first, first + bytes - 4, 4 do
			if buffer.readu32(strokes, offset) < REMOVED then
				buffer.writeu32(strokes, offset, REMOVED)
				live -= 1
			end
		end
	end
	field.live = live
end

function Strokes.animate(field, time)
	Field.update_palettes(field, time, field.styles)
	field.palette_at = time
	local strokes, palettes, output = field.strokes, field.palettes, field.output
	local pixels = field.pixels
	local count = #pixels
	local compact = count > field.live * 2 + 1024
	local keep = 0
	for i = 1, count do
		local offset = pixels[i]
		local entry = buffer.readu32(strokes, offset)
		if entry >= REMOVED then
			if compact then buffer.writeu32(strokes, offset, EMPTY) end
			continue
		end
		if compact then keep += 1; pixels[keep] = offset end
		local color = palettes[bit32.extract(entry, 7, 16)][entry % 128]
		local alpha = math.floor((255 - entry // HIGH_BYTE) * color[4])
		buffer.writeu32(output, offset, color[2] + alpha * HIGH_BYTE)
	end
	if compact then for i = count, keep + 1, -1 do pixels[i] = nil end end
end

return Strokes
