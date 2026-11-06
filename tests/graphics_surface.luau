--!nocheck
-- A small map checks the new palette through both full and incremental rendering.
local roblox = require("./prelude")
getfenv().Instance = roblox.Instance
getfenv().Enum = roblox.Enum
getfenv().task = require("@lune/task")
getfenv().warn = function() end
local Surface = require("../src/client/Map/MapSurface")

local W, H = 9, 5
local terrain = buffer.create(W * H)
buffer.fill(terrain, 0, 128)
local state = {
	owner = buffer.create(W * H * 4),
	flags = buffer.create(W * H),
	owners = {
		[1] = { color = Color3.fromRGB(220, 120, 70) },
		[2] = { color = Color3.fromRGB(75, 150, 220) },
	},
	alliances = {},
	fallout_count = 0,
}
function state:are_allies(a, b)
	return self.alliances[math.min(a, b) * 1024 + math.max(a, b)] == true
end
function state:owner_color(id) return self.owners[id].color end
for y = 1, 3 do
	for x = 1, 6 do
		buffer.writei32(state.owner, (y * W + x) * 4, if x <= 3 then 1 else 2)
	end
end

local surface = Surface.new(nil)
surface:set_map({ W = W, H = H, tile_bytes = terrain })
surface:bind(state)
local function drain()
	local steps = 0
	while surface._rebuild_active or surface:repaint_pending() > 0 do
		surface:step()
		steps += 1
		assert(steps < 100, "repaint should finish")
	end
end
local function same_as_full_redraw()
	drain()
	local before = buffer.tostring(surface.comp)
	surface:rebuild_all()
	drain()
	assert(buffer.tostring(surface.comp) == before, "incremental render must match a full redraw")
end
drain()
local inner, edge = 2 * W + 2, 2 * W + 3
assert(surface:tile_pixel(inner) // 16777216 == Surface.TERRITORY_ALPHA, "interior uses territory alpha")
assert(buffer.readu32(surface.comp, edge * 4) == buffer.readu32(surface.pal_border, 4), "border stays opaque")
assert(buffer.readu32(surface.comp, 0) == Surface.terrain_pixel(128), "unowned land keeps terrain")

buffer.writei32(state.owner, edge * 4, 2)
surface:on_tiles_changed({ edge * 1024 + 2 }, { 1 })
same_as_full_redraw()
local enemy_border = buffer.readu32(surface.comp, inner * 4)
state.alliances[1024 + 2] = true
surface:refresh_palette()
surface:repaint_between(1, 2)
drain()
assert(buffer.readu32(surface.comp, inner * 4) ~= enemy_border, "allied border changes colour")
same_as_full_redraw()

local Country = require("../src/shared/Data/CountryStyle")
state.cosmetics = {
	[1] = { color = Country.rgba(7), flag = "shop_lion_crest", flag_fill = true },
	[2] = { color = Country.rgba(8), flag = "shop_lion_crest", flag_fill = true },
}
surface:on_cosmetics_changed({ 1, 2 })
same_as_full_redraw()
local unaffected = surface._gradients[2]
state.owners[1].spawn_tile = inner
surface:refresh_palette({ 1 })
surface:repaint_owner(1)
assert(surface._gradients[1].x == inner % W and surface._gradients[1].y == inner // W)
assert(surface._gradients[2] == unaffected, "a spawn only refreshes that owner's palette")
same_as_full_redraw()
local otherInterior = 2 * W + 5
surface:set_hover(2)
same_as_full_redraw()
local withFlag = surface:tile_pixel(otherInterior)
state.cosmetics[2].flag_fill = false
surface:on_cosmetics_changed({ 2 })
same_as_full_redraw()
assert(surface:tile_pixel(otherInterior) ~= withFlag, "disabling the flag removes the highlighted blend")
local tile = surface.tiles[1]
local oldImage, writes = tile.img, 0
tile.img = { WritePixelsBuffer = function() writes += 1 end }
surface:mark_all()
surface:step(nil, nil, true)
assert(tile.dirty and writes == 0 and not surface.uploaded, "a reserved slot preserves dirty bands")
surface:step()
assert(not tile.dirty and writes > 0 and surface.uploaded, "the next free slot publishes the deferred map image")
tile.img = oldImage
surface:destroy()
print("graphics_surface ok")
