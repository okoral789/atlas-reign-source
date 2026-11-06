require("./prelude")
local MapCamera = require("../src/client/Map/MapCamera")

local cam = MapCamera.new(nil, { W = 2000, H = 1000 })
local pointer = Vector2.new(1100, 380)
local step = 1.16

for _, hz in { 30, 60, 144 } do
	local dt = 1 / hz
	for _, factor in { step, 1 / step } do
		cam:set_scale_immediate(3)
		cam:look_at(1000, 500)
		for _ = 1, 6 do
			cam:zoom_by(factor, pointer)
		end
		cam:tick(dt)
		local before = cam.scale
		cam:zoom_by(1 / factor, pointer)
		cam:tick(dt)
		assert((cam.scale - before) * (1 / factor - 1) > 0, "reverse on the next frame")

		cam:pan(Vector2.new(1, 0), 0.05)
		local u, v = cam:screen_to_map(pointer.X, pointer.Y)
		cam:tick(dt)
		local x, y = cam:map_to_screen(u, v)
		assert(math.abs(x - pointer.X) < 0.001 and math.abs(y - pointer.Y) < 0.001, "zoom preserves simultaneous pan")
	end

	-- Reciprocal inputs in one frame cancel without a zoom or a projection update.
	cam:set_scale_immediate(3)
	local version = cam.version
	for _ = 1, 60 do
		cam:zoom_by(step, pointer)
		cam:zoom_by(1 / step, pointer)
		cam:tick(dt)
	end
	assert(cam.version == version)

	-- Overscroll at either zoom limit cannot create a backlog.
	for _, limit in { cam:min_scale(), cam:max_scale() } do
		cam:set_scale_immediate(limit)
		local outward = if limit == cam:min_scale() then 1 / step else step
		for _ = 1, 20 do
			cam:zoom_by(outward, pointer)
		end
		cam:tick(dt)
		assert(cam.scale == limit)
		cam:zoom_by(1 / outward, pointer)
		cam:tick(dt)
		assert((cam.scale - limit) * (1 / outward - 1) > 0, "reverse immediately at a limit")
	end
end

cam._vel = Vector2.new(200, -100)
cam:zoom_by(1 / step, pointer)
cam:tick(1 / 60)
assert(cam._vel == Vector2.zero, "zoom cancels leftover drag inertia")

print("PASS camera zoom reversals, pan, and limits at 30, 60, and 144 Hz")
