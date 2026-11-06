--!nocheck
local roblox = require("./prelude")
Instance, Enum, task = roblox.Instance, roblox.Enum, require("@lune/task")
warn = function() end
local Surface = require("../src/client/Map/MapSurface")
local State = require("../src/shared/Core/GameState")
local Country = require("../src/shared/Data/CountryStyle")
local W, H = 79, 67
local map = { W = W, H = H, N = W * H, tile_bytes = buffer.create(W * H) }
buffer.fill(map.tile_bytes, 0, 128)
local state = State.new(map)
for id = 1, 2 do
	local owner = State.new_owner_info(id)
	owner.spawn_tile, owner.rgba = id * 100, Country.rgba(id + 6)
	state.owners[id] = owner
end
for tile = 0, map.N - 1 do
	buffer.writei32(state.owner, tile * 4, tile % 2 + 1)
end
state:set_cosmetics({
	[1] = { color = Country.rgba(7), flag = "shop_lion_crest", flag_fill = true },
	[2] = { color = Country.rgba(8), flag = "shop_lion_crest", flag_fill = true },
}, true)
local surface = Surface.new(nil)
surface:set_map(map)
surface:bind(state)
surface.budget_s = 0
surface:step()
assert(surface._rebuild_i == Surface.REPAINT_CHUNK, "expired budget must stop after one rebuild slice")
surface:step(17)
assert(surface._rebuild_i == Surface.REPAINT_CHUNK + 17, "explicit tile cap must still apply")
local changed, old = {}, {}
for _, tile in { 3, 129, 300, map.N - 2 } do
	local previous = buffer.readi32(state.owner, tile * 4)
	local owner = previous % 2 + 1
	buffer.writei32(state.owner, tile * 4, owner)
	table.insert(changed, tile * 1024 + owner)
	table.insert(old, previous)
end
surface:on_tiles_changed(changed, old)
local steps = 0
while surface._rebuild_active or surface._queue_n > 0 or surface._pend_n > 0 do
	local before = surface._rebuild_i
	surface:step()
	assert(surface._rebuild_i - before <= Surface.REPAINT_CHUNK, "rebuild exceeded expired budget")
	steps += 1
	assert(steps < 100, "budgeted rebuild must finish even with captures")
end
local expected = Surface.new(nil)
expected:set_map(map)
expected:bind(state)
expected.budget_s = math.huge
expected:step(map.N)
assert(not expected._rebuild_active)
assert(buffer.tostring(surface.comp) == buffer.tostring(expected.comp), "sliced/captured image differs from full rebuild")
surface:rebuild_all()
surface:step(0)
assert(surface._rebuild_i == 0, "zero tile cap must remain a no-op")
surface:destroy(); expected:destroy()
print("PASS cold rebuild budget, explicit tile caps, captures during rebuild, exact final pixels")
