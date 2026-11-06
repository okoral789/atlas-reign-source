-- Native Open Cloud CPU/image-upload stress check. No live players, GPU or device FPS.
assert(game.GameId == 10774039150 and game.PlaceId == 129521354706128)
local shared = game:GetService("ReplicatedStorage").Airfront
local client = game:GetService("StarterPlayer").StarterPlayerScripts.AirfrontClient
local State = require(shared.Core.GameState)
local World = require(shared.Core.WorldMap)
local Cosmetics = require(shared.Data.Cosmetics)
local Colors = require(shared.Data.ProfileStyle)
local Country = require(shared.Data.CountryStyle)
local Surface = require(client.Map.MapSurface)
local FX = require(client.Map.TerritoryEffects)
local Strokes = require(shared.Data.BorderStrokes)
local Stats = game:GetService("Stats")
local map = World.get("world")
assert(map.W == 2000 and map.H == 1000)
local state = State.new(map)
local flags, skins = {}, {}
for _, item in Cosmetics.shop_items() do
	if Cosmetics.banner_for(item.id) then table.insert(flags, item.id) end
end
for _, item in require(shared.Data.FleetStyles) do
	if item.border then table.insert(skins, item.id) end
end
local colors = Colors.shop_indices()
assert(#flags > 0 and #skins > 0 and #colors >= 13)
local function cosmetic(id, shift)
	return { color = Country.rgba(colors[(id + shift - 1) % #colors + 1]),
		flag = flags[(id + shift - 1) % #flags + 1], flag_fill = true,
		skin = skins[(id + shift - 1) % #skins + 1] }
end
for id = 1, 50 do
	local owner = State.new_owner_info(id)
	owner.name, owner.spawned = "Stress " .. id, true
	owner.rgba = Country.rgba(colors[(id - 1) % #colors + 1])
	state.owners[id] = owner
end
-- Fifty contiguous land-list bands, with the real world's coastlines and islands.
for k = 0, map.land_count - 1 do
	local tile = buffer.readi32(map.land_list, k * 4)
	local id = math.min(50, math.floor(k * 50 / map.land_count) + 1)
	buffer.writei32(state.owner, tile * 4, id)
	local owner = state.owners[id]
	owner.tiles += 1
	if owner.spawn_tile < 0 then owner.spawn_tile = tile end
end
local host = Instance.new("ScreenGui")
local rig = { scale = 1, version = 1, x = 0, y = 0, _vp = Vector2.new(1920, 1080) }
function rig:viewport_size() return self._vp end
function rig:screen_to_map(x, y) return (x - self.x) / self.scale, (y - self.y) / self.scale end
function rig:map_to_screen(x, y) return x * self.scale + self.x, y * self.scale + self.y end
local surface = Surface.new(host)
surface:set_map(map)
assert(surface.ok, "native EditableImage creation failed")
local view = { rig = rig, ui_scale = 1 }
local fx = FX.new(host, view)
fx:bind(state)
local connections = {
	state.tiles_changed:Connect(function(changes, old) surface:on_tiles_changed(changes, old) end),
	state.cosmetics_changed:Connect(function(ids) surface:on_cosmetics_changed(ids) end),
}
local function metrics(values)
	table.sort(values)
	local sum = 0
	for _, value in values do sum += value end
	return { n = #values, mean_ms = sum / #values * 1000,
		p95_ms = values[math.ceil(#values * .95)] * 1000,
		p99_ms = values[math.ceil(#values * .99)] * 1000, max_ms = values[#values] * 1000 }
end
local function pending()
	return surface._rebuild_active or surface._queue_n > 0 or surface._pend_n > 0
		or #surface._sweeps > 0 or fx.style_dirty
		or (next(fx.styles or {}) ~= nil and (
			(fx.cache and (fx.cache.pending > 0 or fx.cache.job ~= nil))
			or fx.image_waiting or fx.redraw or fx.paint_scale ~= rig.scale
			or (fx.dirty_chunks and next(fx.dirty_chunks) ~= nil)))
end
local function surface_step()
	view._map_image_slot = if fx.image_waiting then fx else nil
	surface:step(nil, nil, view._map_image_slot ~= nil)
	view._map_image_written = surface.uploaded
end
local function drain()
	local values, steps = {}, 0
	while pending() do
		local t = os.clock()
		surface_step(); fx:tick(1 / 60)
		table.insert(values, os.clock() - t)
		steps += 1
		assert(steps <= 2500, "cosmetic backlog failed to converge")
		task.wait()
	end
	-- Flush the two map-image tiles after the final repaint.
	for _ = 1, #surface.tiles do surface:step(); task.wait() end
	return { frames = steps, cpu = if #values > 0 then metrics(values) else nil }
end
surface:bind(state)
local report = { version = game.PlaceVersion, native_images = true, gpu_or_client_fps = false,
	map_tiles = map.N, owned_land_tiles = map.land_count, owners = 50, viewport_cases = {},
	memory_start_mb = Stats:GetTotalMemoryUsageMb(), base_startup = drain() }
local loadouts = {}
for id = 1, 50 do loadouts[id] = cosmetic(id, 0) end
state:set_cosmetics(loadouts, true)
report.premium_startup = drain()
assert(fx.image ~= nil and fx.cache ~= nil and fx.cache.pending == 0)
local function run(viewport)
	rig._vp = viewport
	surface.budget_s = if viewport.X <= 1000 then Surface.STEP_BUDGET_MOBILE_S else Surface.STEP_BUDGET_S
	local frameTimes, surfaceTimes, borderTimes, styleTimes = {}, {}, {}, {}
	local peakPending, peakWork, maxAnchorError, uploads = 0, 0, 0, 0
	local peakLOD, maxReuseDrift, maxDisplayDrift = 0, 0, 0
	local firstRasters, firstPatches = fx.rasters, fx.patches or 0
	local startReads = fx.cache.reads
	for frame = 1, 120 do
		-- Smooth fast pan plus continuous zoom, followed by scattered ownership changes.
		rig.scale = (viewport.X / map.W) * (1.3 + .5 * math.sin(frame * .11))
		rig.x = viewport.X / 2 - (1000 + 500 * math.sin(frame * .07)) * rig.scale
		rig.y = viewport.Y / 2 - (500 + 200 * math.cos(frame * .09)) * rig.scale
		rig.version += 1
		if frame > 60 and frame % 6 == 0 then
			local changes, old = {}, {}
			for k = 0, 399 do
				local ix = ((frame * 1877) + k * 13) % map.land_count
				local tile = buffer.readi32(map.land_list, ix * 4)
				local previous = buffer.readi32(state.owner, tile * 4)
				local owner = previous % 50 + 1
				buffer.writei32(state.owner, tile * 4, owner)
				table.insert(changes, tile * 1024 + owner); table.insert(old, previous)
			end
			state.tiles_changed:Fire(changes, old)
		end
		local start = os.clock()
		if frame > 60 and frame % 12 == 0 then
			local t = os.clock()
			local id = (frame // 12) % 50 + 1
			state:set_cosmetics({ [id] = cosmetic(id, frame // 12) })
			table.insert(styleTimes, os.clock() - t)
		end
		local t = os.clock()
		surface_step(); surface:layout(rig)
		table.insert(surfaceTimes, os.clock() - t)
		t = os.clock(); fx:tick(1 / 60)
		table.insert(borderTimes, os.clock() - t)
		table.insert(frameTimes, os.clock() - start)
		if surface.uploaded then uploads += 1 end
		peakPending = math.max(peakPending, fx.cache.pending)
		peakWork = math.max(peakWork, fx.sample_work)
		peakLOD = math.max(peakLOD, fx.cache.lod_edges or 0)
		local sx, sy = rig:map_to_screen(fx.paint_mx, fx.paint_my)
		maxAnchorError = math.max(maxAnchorError, math.abs(fx.root.Position.X.Offset - sx), math.abs(fx.root.Position.Y.Offset - sy))
		local ratio = rig.scale / fx.paint_scale
		local drift = math.abs(ratio - 1) * math.max(fx.paint_w / fx.w, fx.paint_h / fx.h)
		maxDisplayDrift = math.max(maxDisplayDrift, drift)
		if not fx.image_waiting then maxReuseDrift = math.max(maxReuseDrift, drift) end
		assert(math.abs(fx.root.Size.X.Offset - fx.paint_w * ratio) < 1)
		assert(not (surface.uploaded and fx.uploaded), "competing map uploads")
		if frame == 60 then assert(fx.cache.reads == startReads, "warm pan/zoom resampled owners") end
		task.wait()
	end
	assert(maxAnchorError < 1 and peakWork <= FX.SAMPLE_BUDGET and peakLOD <= 768)
	assert(maxReuseDrift <= FX.REUSE_PX and maxDisplayDrift < 2, "border stroke changed width too much")
	local convergence = drain()
	local rasters, patches = fx.rasters - firstRasters, (fx.patches or 0) - firstPatches
	assert(fx.paint_scale == rig.scale and patches > 0)
	local incremental = buffer.tostring(surface.comp)
	Strokes.animate(fx.field, .4)
	local full = Strokes.prepare(fx.w, fx.h, fx.styles, nil, buffer.create(fx.w * fx.h * 4), .4)
	full.x, full.y = fx.field.x, fx.field.y
	local bounds, cache = fx.paint_bounds, fx.cache
	for y = bounds[2], bounds[4] do
		for x = bounds[1], bounds[3] do
			Strokes.project(full, cache.chunks[y * cache.cols + x], fx.paint_detail)
		end
	end
	assert(buffer.tostring(full.output) == buffer.tostring(fx.pixels), "incremental border patches differ from full projection")
	surface:rebuild_all(); drain()
	assert(incremental == buffer.tostring(surface.comp), "incremental repaint differs from full rebuild")
	return { width = viewport.X, height = viewport.Y, frames = metrics(frameTimes),
		surface_budget_ms = surface.budget_s * 1000,
		surface = metrics(surfaceTimes), borders = metrics(borderTimes), style_change = metrics(styleTimes),
		peak_border_pending = peakPending, peak_border_work = peakWork, anchor_error_px = maxAnchorError,
		peak_lod_edges = peakLOD, max_reused_texel_drift_px = maxReuseDrift, max_display_texel_drift_px = maxDisplayDrift,
		map_upload_frames = uploads, border_rasters = rasters, border_patches = patches,
		drained = convergence, pixel_correct = true, border_pixel_correct = true,
		memory_mb = Stats:GetTotalMemoryUsageMb() }
end
for _, vp in { Vector2.new(STRESS_WIDTH or 1920, STRESS_HEIGHT or 1080) } do
	table.insert(report.viewport_cases, run(vp))
end
state:set_cosmetics({}, true); drain(); fx:tick(1 / 60)
assert(not fx.root.Visible, "unequipped border still visible")
for _, connection in connections do connection:Disconnect() end
surface:unbind(); fx:destroy(); surface:destroy(); host:Destroy()
report.memory_end_mb = Stats:GetTotalMemoryUsageMb()
report.cleaned_up = #surface.tiles == 0 and #fx.conns == 0 and fx.state == nil
assert(report.cleaned_up)
return report
