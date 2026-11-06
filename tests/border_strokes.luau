local Cache = require("../src/shared/Data/BorderContourCache")
local Strokes = require("../src/shared/Data/BorderStrokes")
local LOD = require("../src/shared/Data/BorderLOD")

local function warm(w, h, owner)
	local cache = Cache.new(w, h, owner)
	while cache.pending > 0 or cache.job do
		Cache.step(cache, 16384, { 0, 0, w, h })
		assert(cache.lod_edges <= Cache.LOD_EDGES)
	end
	return cache
end

local w, h = 84, 72
local styles = {
	[1] = { effect = "tide", fleet_tint = 0x72FFF0 },
	[2] = { effect = "flame", fleet_tint = 0xFF613C },
}
local output = buffer.create(w * h * 4)
local field
local function project(cache, scale, tx, ty, detail)
	field = Strokes.prepare(w, h, styles, field, output, .4)
	Strokes.transform(field, scale, scale, tx, ty, 0, 0, cache.w, cache.h)
	for y = 0, cache.rows - 1 do
		for x = 0, cache.cols - 1 do
			local chunk = cache.chunks[y * cache.cols + x]
			Strokes.project(field, chunk, detail)
		end
	end
end
local function alpha(x, y)
	return buffer.readu8(output, (y * w + x) * 4 + 3)
end

-- The same edge remains at the same physical position and coverage through a zoom.
local border = warm(128, 128, function(tile) return if tile % 128 >= 64 then 1 else 0 end)
for _, offset in { .25, .5, .9 } do
	local reference
	for _, scale in { .38, .51, .87, 1.24, 3.5 } do
		project(border, scale, 40 + offset - 64 * scale, 36 - 32 * scale)
		local coverage, columns = 0, 0
		for x = 37, 43 do
			local a = alpha(x, 35)
			coverage += a
			if a > 0 then columns += 1 end
		end
		assert(coverage > 100 and columns <= 2, "the core stays bright and narrow")
		reference = reference or coverage
		assert(math.abs(coverage - reference) <= 1, "zoom changed physical edge coverage")
	end
end

-- Islands still get a pixel at distant zoom, including a cell on each side of a chunk seam.
local islands = warm(128, 64, function(tile)
	local x, y = tile % 128, tile // 128
	return if x == 63 and y == 16 then 1 elseif x == 64 and y == 32 then 2 else 0
end)
project(islands, .28, 11, 12)
local seen = {}
for _, offset in field.pixels do
	seen[bit32.extract(buffer.readu32(field.strokes, offset), 7, 16)] = true
end
assert(seen[1] and seen[2], "distant islands retain both owners' borders")
local before = buffer.tostring(output)
Strokes.animate(field, 1.7)
assert(before ~= buffer.tostring(output), "the cached strokes still animate")
project(islands, .28, -150, -150)
assert(#field.pixels == 0 and buffer.tostring(output) == string.rep("\0", w * h * 4), "off-screen borders leave no ghosts")
local small = warm(64, 64, function(tile)
	local x, y = tile % 64, tile // 64
	return if x == 8 and y == 8 then 1 elseif x == 24 and y == 24 then 2 elseif x == 40 and y == 40 then 1 else 0
end)
assert(small.chunks[0].count == 12 and small.chunks[0].lod4.count == 3)
assert(LOD.choose(.8, 3, 3) == 4 and LOD.choose(3, 8, 8) == 1)
project(small, .26, 10, 10, 4)
for _, tile in {8, 24, 40} do
	local x, y = math.floor(10 + tile * .26), math.floor(10 + tile * .26)
	assert(alpha(x, y) > 30, "each isolated island survives overview simplification")
end
local checker = warm(64, 64, function(tile) return 1 + (tile % 64 + tile // 64) % 2 end)
project(checker, 1, 0, 0)
local live = field.live
assert(live > 1024)
local snapshot = buffer.tostring(output)
Strokes.clear_rect(field, {0, 0, w - 1, h - 1})
Strokes.animate(field, .4)
assert(field.live == 0 and #field.pixels == 0, "animation discards cleared offsets")
Strokes.project(field, checker.chunks[0])
assert(field.live == live and #field.pixels == live and buffer.tostring(output) == snapshot,
	"discarded offsets can be appended again without losing strokes")
print("PASS projected border strokes: constant zoom coverage, tiny islands, chunk seams, animated cache and clipping")
