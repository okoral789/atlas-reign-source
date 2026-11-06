--!nocheck
-- 2D map renderer maths (src/client/Map): MapCamera projection / clamping / zoom anchoring /
-- focus, and MapSurface colours against the expected ones (terrain colour by type and magnitude,
-- shorelines and the background; the border colour is the owner's colour darkened in HSL).
require("./prelude")
local MapCamera = require("../src/client/Map/MapCamera")
local MapSurface = require("../src/client/Map/MapSurface")

local fails = 0
local function expect(cond: any, what: string)
	if cond then
		print("  ok   " .. what)
	else
		fails += 1
		print("FAIL " .. what)
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end
local function rgba(c: number): (number, number, number, number)
	return c % 256, (c // 256) % 256, (c // 65536) % 256, c // 16777216
end
local function is_rgb(c: number, r: number, g: number, b: number): boolean
	local cr, cg, cb, ca = rgba(c)
	return cr == r and cg == g and cb == b and ca == 255
end

-- ---------------------------------------------------------------------------------------------
-- MapCamera (headless: viewport 1600 x 900)
-- ---------------------------------------------------------------------------------------------
local cam = MapCamera.new(nil, { W = 2000, H = 1000 })
expect(
	near(cam:min_scale(), math.min(1600 / 2000, 900 / 1000) * MapCamera.FIT_MARGIN),
	"farthest zoom fits the map with a margin"
)
expect(
	near(cam.scale, cam:min_scale()) and near(cam.cu, 1000) and near(cam.cv, 500),
	"starts centred at the farthest zoom"
)

cam:set_scale_immediate(3.0)
cam:look_at(500, 400)
local sx, sy = cam:map_to_screen(512.25, 407.5)
local u, v = cam:screen_to_map(sx, sy)
expect(near(u, 512.25, 1e-9) and near(v, 407.5, 1e-9), "map_to_screen / screen_to_map round trip")
expect(cam:tile_at_screen(Vector2.new(sx, sy)) == 407 * 2000 + 512, "tile_at_screen picks the tile under the point")
local tx, ty = cam:tile_to_screen(407 * 2000 + 512)
expect(near(tx, sx + 0.25 * 3.0, 1e-9) and near(ty, sy, 1e-9), "tile_to_screen is the tile centre")

-- clamp: a map bigger than the view pans until an edge reaches the view anchor (the centre)
cam:look_at(-500, -500)
local lx, ly = cam:map_to_screen(0, 0)
expect(near(lx, 800, 1e-9) and near(ly, 450, 1e-9), "top-left edge can come to the view's centre, no further")
cam:look_at(1e9, 1e9)
local rx, ry = cam:map_to_screen(2000, 1000)
expect(near(rx, 800, 1e-6) and near(ry, 450, 1e-6), "bottom-right edge can come to the view's centre, no further")
-- a map smaller than the view stays centred
cam:set_scale_immediate(0.1)
cam:look_at(0, 0)
local cx, cy = cam:map_to_screen(1000, 500)
expect(near(cx, 800, 1e-6) and near(cy, 450, 1e-6), "a map smaller than the view is centred")
expect(cam:tile_at_screen(Vector2.new(5, 5)) == -1, "off the map -> -1")
-- zoomed out, the clamp's two ends meet at the centre; in floating point the upper one could land a hair
-- below the lower and math.clamp threw (v82: 9% of zoomed-out views, half a million errors a day)
do
	local ok, threw = true, 0
	for i = 1, 20000 do
		local before = 400 + (i % 997) * 0.731
		local after = 380 + (i % 613) * 0.917
		local good = pcall(MapCamera._clamp_axis, (i % 101) * 13.7, 1000, before, after)
		if not good then
			ok = false
			threw += 1
		end
	end
	expect(ok, "the clamp never throws zoomed out (" .. threw .. " of 20000 threw)")
	expect(MapCamera._clamp_axis(10, 1000, math.huge, math.huge) == 500, "a zero scale centres the map")
	expect(MapCamera._clamp_axis(10, 1000, 0 / 0, 1) == 500, "a scale not known yet centres the map")
end

-- wheel zoom glides and keeps the anchor under the pointer
cam:set_scale_immediate(2.0)
cam:look_at(1000, 500)
local pointer = Vector2.new(1100, 380)
local hit_x, hit_y = cam:screen_to_map(pointer.X, pointer.Y)
cam:zoom_by(2.0, pointer)
for _ = 1, 120 do
	cam:tick(1 / 60)
end
local ax, ay = cam:map_to_screen(hit_x, hit_y)
expect(near(cam.scale, 4.0, 1e-3), "zoom reaches its target")
expect(near(ax, pointer.X, 0.5) and near(ay, pointer.Y, 0.5), "the anchor stays under the pointer")

-- focus animation arrives at the point and zoom
cam:focus(1500, 700, 5.0, 1.0)
for _ = 1, 80 do
	cam:tick(1 / 60)
end
expect(near(cam.cu, 1500, 1e-6) and near(cam.cv, 700, 1e-6) and near(cam.scale, 5.0, 1e-6), "focus arrives")

-- drag moves the map with the pointer
cam:halt()
local before_u = cam.cu
cam:begin_drag()
cam:drag_by(Vector2.new(-50, 0))
cam:end_drag()
expect(near(cam.cu, before_u + 50 / cam.scale, 1e-9), "drag pans by pointer px / scale")

-- ---------------------------------------------------------------------------------------------
-- MapSurface terrain (colour by terrain type and magnitude, shorelines)
-- ---------------------------------------------------------------------------------------------
local tp = MapSurface.terrain_pixel
local LAND, SHORE = 128, 64
expect(is_rgb(tp(LAND + 5), 170, 191, 154), "plains mag 5: sage with elevation shading")
expect(is_rgb(tp(LAND + 12), 213, 197, 166), "highland mag 12: warm relief")
expect(is_rgb(tp(LAND + 25), 233, 243, 244), "mountain mag 25: cool snow")
expect(is_rgb(tp(LAND + 31), 13, 28, 41), "impassable: deep navy background")
expect(is_rgb(tp(LAND + SHORE + 3), 216, 204, 169), "shoreline land: sand")
expect(is_rgb(tp(SHORE + 32), 107, 154, 172), "shoreline water: round(0.7 * ocean + 76.5)")
expect(is_rgb(tp(32 + 3), 41, 109, 134), "water near shore has a gentle depth gradient")
expect(is_rgb(tp(32 + 15), 35, 99, 124), "deep water is darker and blue")
expect(is_rgb(tp(32 + 31), 30, 92, 115) and tp(32 + 31) == tp(32 + 24), "depth shading caps at magnitude 24")
local br, bg, bb = rgba(tp(LAND + 31))
expect(near(MapSurface.BACKGROUND.R * 255, br, 1e-4) and near(MapSurface.BACKGROUND.G * 255, bg, 1e-4) and near(MapSurface.BACKGROUND.B * 255, bb, 1e-4), "background matches impassable terrain")

-- The darken helper reduces HSL lightness while keeping hue and saturation.
local r, g, b = MapSurface.darken(1, 0, 0, 0.125)
expect(near(r, 0.75, 1e-9) and near(g, 0, 1e-9) and near(b, 0, 1e-9), "darken #ff0000 -> l 0.375")
r, g, b = MapSurface.darken(0.2, 0.6, 1.0, 0.125)
-- #3399ff: h 210, s 1, l 0.6 -> l 0.475: (0, 0.475, 0.95)
expect(near(r, 0, 1e-6) and near(g, 0.475, 1e-6) and near(b, 0.95, 1e-6), "darken #3399ff keeps hue and saturation")

print(if fails == 0 then "map2d_render: all passed" else string.format("map2d_render: %d FAILED", fails))
if fails > 0 then
	error("map2d_render failed")
end
