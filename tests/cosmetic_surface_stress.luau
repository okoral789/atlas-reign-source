--!nocheck
-- From the repo root: lune run tests/cosmetic_surface_stress.luau [report-name]
-- CPU compositor, real camera/GUI layout, and real GameState signals. Lune has no EditableImage.
local roblox = require("./prelude")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local clock = os.clock
Instance, Enum, task = roblox.Instance, roblox.Enum, require("@lune/task")
warn = function() end

local GameState = require("../src/shared/Core/GameState")
local MapSurface = require("../src/client/Map/MapSurface")
local Camera = require("../src/client/Map/MapCamera")
local Country = require("../src/shared/Data/CountryStyle")
local Cosmetics = require("../src/shared/Data/Cosmetics")
local ProfileStyle = require("../src/shared/Data/ProfileStyle")

local W, H = 2000, 1000
local N = W * H
local ownerCount, frames, cycles = 50, 240, 3
local map = { id = "stress", W = W, H = H, N = N, k_lin = 1, tile_bytes = buffer.create(N) }
buffer.fill(map.tile_bytes, 0, 0x80)
local flags = {}
for _, item in Cosmetics.shop_items() do
	if Cosmetics.banner_for(item.id) then table.insert(flags, item.id) end
end
local colors = ProfileStyle.shop_indices()
assert(#flags >= 4 and #colors >= 13)

local function cosmetic(id, variant)
	return {
		color = Country.rgba(colors[(id - 1 + variant) % #colors + 1]),
		flag = flags[((id - 1) // #colors + variant) % #flags + 1],
		flag_fill = true,
	}
end

local function metrics(samples)
	table.sort(samples)
	return {
		n = #samples,
		p95_ms = samples[math.ceil(#samples * 0.95)] * 1000,
		p99_ms = samples[math.ceil(#samples * 0.99)] * 1000,
		max_ms = samples[#samples] * 1000,
	}
end

local function settle(surface)
	local steps = 0
	while surface._rebuild_active or surface._queue_n > 0 or surface._pend_n > 0 or #surface._sweeps > 0 do
		surface:step()
		steps += 1
		assert(steps <= 2000, "the surface never finished its repaint backlog")
	end
	return steps
end

local function run(premium, plainPicture)
	local setup, frameTime, stepTime, styleTime, rebuildTime = {}, {}, {}, {}, {}
	local peaks = { queued_tiles = 0, pending_changes = 0, owner_sweeps = 0, settle_frames = 0, labels = 0 }
	local report = { cycles = {}, peaks = peaks }
	local surface, camera = MapSurface.new(nil), Camera.new(nil, map)
	surface.budget_s = MapSurface.STEP_BUDGET_MOBILE_S
	surface:set_map(map)
	local expectedLabels = #surface.tiles
	assert(expectedLabels == #surface.root:GetChildren())

	for cycle = 1, cycles do
		local state = GameState.new(map)
		local loadout, combos = {}, {}
		for id = 1, ownerCount do
			local sx, sy = ((id - 1) % 10) * 200 + 100, ((id - 1) // 10) * 200 + 100
			state.owners[id] = {
				rgba = (0x183A50 + id * 123431) * 256 + 255,
				spawn_tile = sy * W + sx, tiles = 40000,
			}
			if premium then
				local entry = cosmetic(id, cycle)
				local combo = entry.flag .. "/" .. entry.color
				assert(not combos[combo], "duplicate loadout in the 50-player scenario")
				combos[combo], loadout[id] = true, entry
			end
		end
		for y = 0, H - 1 do
			local row, ownerRow = y * W, (y // 200) * 10
			for x = 0, W - 1 do
				buffer.writei32(state.owner, (row + x) * 4, ownerRow + x // 200 + 1)
			end
		end
		state:set_cosmetics(loadout, true)
		local tilesConnection = state.tiles_changed:Connect(function(changed, olds)
			surface:on_tiles_changed(changed, olds)
		end)
		local styleConnection = state.cosmetics_changed:Connect(function(ids)
			surface:on_cosmetics_changed(ids)
		end)
		local t = clock()
		surface:bind(state)
		table.insert(setup, clock() - t)
		while surface._rebuild_active do
			t = clock()
			surface:step()
			table.insert(rebuildTime, clock() - t)
		end
		for frame = 1, frames do
			local start = clock()
			camera:set_scale_immediate(0.8 + ((frame * 13) % 95) / 10)
			camera:look_at((frame * 79) % W, (frame * 43) % H)
			surface:layout(camera)
			if frame % 4 == 0 then
				local changed, old = {}, {}
				local x = 200 * (1 + (frame // 4) % 9) - 10
				local y = (frame * 23) % (H - 120)
				for dy = 0, 119 do
					local row = (y + dy) * W + x
					for dx = 0, 19 do
						local tile = row + dx
						local previous = buffer.readi32(state.owner, tile * 4)
						local left = ((y + dy) // 200) * 10 + x // 200 + 1
						local nextOwner = if previous == left then left + 1 else left
						buffer.writei32(state.owner, tile * 4, nextOwner)
						table.insert(changed, tile * 1024 + nextOwner)
						table.insert(old, previous)
					end
				end
				state.tiles_changed:Fire(changed, old)
			end
			if frame % 12 == 0 then
				local id = 1 + (frame * 7 + cycle) % ownerCount
				local variant = cycle + frame // 12
				local entry = if premium then cosmetic(id, variant) else { color = Country.rgba(2 + variant % 5) }
				t = clock()
				state:set_cosmetics({ [id] = entry })
				table.insert(styleTime, clock() - t)
			end
			t = clock()
			surface:step()
			table.insert(stepTime, clock() - t)
			table.insert(frameTime, clock() - start)
			peaks.queued_tiles = math.max(peaks.queued_tiles, surface._queue_n - surface._queue_head + 1)
			peaks.pending_changes = math.max(peaks.pending_changes, (surface._pend_n - surface._pend_i + 1) // 2)
			peaks.owner_sweeps = math.max(peaks.owner_sweeps, #surface._sweeps)
		end
		local drained = settle(surface)
		peaks.settle_frames = math.max(peaks.settle_frames, drained)
		local live = buffer.tostring(surface.comp)
		surface:rebuild_all()
		settle(surface)
		assert(buffer.tostring(surface.comp) == live, "incremental styles differ from a clean rebuild")
		state:set_cosmetics({}, true)
		settle(surface)
		assert(next(surface._skins) == nil and next(surface._gradients) == nil and next(surface._paint_details) == nil)
		if premium then
			assert(buffer.tostring(surface.comp) == plainPicture[cycle], "removing premium styles left old pixels")
		else
			plainPicture = plainPicture or {}
			plainPicture[cycle] = buffer.tostring(surface.comp)
		end
		table.insert(report.cycles, { settled_in_frames = drained, compared_full_pixels = N })
		state:set_cosmetics({ [1] = cosmetic(1, cycle) })
		assert(#surface._sweeps > 0 and surface._skins[1] and surface._gradients[1])
		surface:unbind()
		surface:clear()
		assert(surface._state == nil and surface._own == nil and surface._flags == nil)
		assert(#surface._sweeps == 0 and surface._queue_n == 0 and surface._pend_n == 0)
		assert(next(surface._skins) == nil and next(surface._gradients) == nil and next(surface._paint_details) == nil)
		assert(buffer.tostring(surface.comp) == buffer.tostring(surface.terrain))
		peaks.labels = math.max(peaks.labels, #surface.root:GetChildren())
		assert(#surface.root:GetChildren() == expectedLabels, "cosmetics or rebind added image labels")
		tilesConnection:Disconnect()
		styleConnection:Disconnect()
	end
	surface:destroy()
	assert(#surface.tiles == 0 and surface.root.Parent == nil)
	report.bind = metrics(setup)
	report.rebuild_step = metrics(rebuildTime)
	report.realtime_frame = metrics(frameTime)
	report.step = metrics(stepTime)
	report.style_signal = metrics(styleTime)
	return report, plainPicture
end

local base, picture = run(false)
local premium = run(true, picture)
local results = {
	tile_count = N, owners = ownerCount, frames_per_cycle = frames, cycles_per_mode = cycles,
	mobile_budget_ms = MapSurface.STEP_BUDGET_MOBILE_S * 1000,
	editable_image = false, base = base, premium = premium,
}
local label = process.args[1] or "surface"
assert(string.match(label, "^[%w_-]+$"), "invalid report name")
local output = "build/cosmetic-stress"
if not fs.isDir(output) then fs.writeDir(output) end
local json = serde.encode("json", results, true)
fs.writeFile(output .. "/" .. label .. ".json", json)
print(json)
