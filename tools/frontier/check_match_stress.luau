-- Headless full-match stress. Transport is in-process and the image writes use the Roblox engine.
assert(game.GameId == 10774039150 and game.PlaceId == 129521354706128)
local Shared = game:GetService("ReplicatedStorage").Airfront
local Client = game:GetService("StarterPlayer").StarterPlayerScripts.AirfrontClient
local Server = game:GetService("ServerScriptService").AirfrontServer
local Match = require(Server.MatchServer)
local LobbyRules = require(Server.Lobbies.LobbyRules)
local LobbyStore = require(Server.Lobbies.LobbyStore)
local MatchHost = require(Server.Lobbies.MatchHost)
local Sim = require(Shared.Core.Sim)
local Defs = require(Shared.Core.Defs)
local World = require(Shared.Core.WorldMap)
local Protocol = require(Shared.Net.Protocol)
local Cosmetics = require(Shared.Data.Cosmetics)
local Colors = require(Shared.Data.ProfileStyle)
local Country = require(Shared.Data.CountryStyle)
local Strokes = require(Shared.Data.BorderStrokes)
local Surface = require(Client.Map.MapSurface)
local MapView = require(Client.Map.MapView)
local FX = require(Client.Map.TerritoryEffects)
local Session = require(Client.Session)
local OP = Protocol.OP
local players, ticks = STRESS_PLAYERS or 50, STRESS_TICKS or 360
assert(players >= 1 and players <= 50)
local expectedAI = if players >= 20 then 0 else 50 - players
math.randomseed(STRESS_SEED or 1106)
local vp = Vector2.new(STRESS_WIDTH or 1920, STRESS_HEIGHT or 1080)
local map = World.get(LobbyRules.match_map_id("world"))
local dt, now = 1 / 60, 0
local function clockSeconds() return now end
local store = LobbyStore.localstore(clockSeconds)
store.put({ id = "stress", map = "world", map_name = "World", mode = "world", max = 50,
	starts = 0, created = 0, players = players, status = "open", psid = "stress" }, 900)
store.bind_psid("stress", "stress", 900)
local queue = MatchHost.new({ store = store, psid = "stress", now = clockSeconds })
assert(queue:lookup())
local host = Instance.new("ScreenGui")
local rig = { scale = vp.X / map.W, x = 0, y = 0, version = 0, _vp = vp }
function rig:viewport_size() return vp end
function rig:screen_to_map(x, y) return (x - self.x) / self.scale, (y - self.y) / self.scale end
function rig:map_to_screen(x, y) return x * self.scale + self.x, y * self.scale + self.y end
local surface = Surface.new(host)
local view = setmetatable({ rig = rig, surface = surface, _map = map, _conns = {},
	layers = {}, _layer_order = { "territory_fx" } }, MapView)
local fx = FX.new(host, view)
view.layers.territory_fx = fx
surface:set_map(map)
assert(surface.ok)
if vp.X <= 1000 then surface.budget_s = Surface.STEP_BUDGET_MOBILE_S end

local styles, flags = {}, {}
for _, item in require(Shared.Data.FleetStyles) do
	if item.border then table.insert(styles, item.id) end
end
for _, item in Cosmetics.shop_items() do
	if Cosmetics.banner_for(item.id) then table.insert(flags, item.id) end
end
local palette = Colors.shop_indices()
assert(#styles > 0 and #flags > 0 and #palette > 0)
local peers, inbox, snapshots, deltas = {}, {}, 0, 0
local snapBytes, deltaBytes, peakTiles, allianceChanges = 0, 0, 0, 0
local function warnTest(message) error(message) end
local receive
local session = Session.new({
	now = function() return now end, mobile = vp.X <= 1000, defer = task.defer,
	require_core = function(name) return require(Shared.Core[name]) end,
	warn = warnTest, net = { send = warnTest, listen = function(fn) receive = fn end },
})
session.mode = Session.MODE_MULTI
session.state_ready:Connect(function(state)
	view:bind_state(state)
	view:_connect(state.tiles_changed, function(changes)
		peakTiles = math.max(peakTiles, #changes)
	end)
	view:_connect(state.alliance_changed, function() allianceChanges += 1 end)
end)
local match = Match.new({
	make_sim = function(config)
		config.spawn_ticks = 30 -- Shorten the countdown while preserving the normal spawn flow.
		return Sim.new(map, config)
	end,
	seed = function() return STRESS_SEED or 1106 end,
	peers = function() return peers end,
	now_ms = function() return math.floor(now * 1000) end,
	cosmetics_of = function(peer)
		return { skin = styles[(peer - 1) % #styles + 1], flag = flags[(peer - 1) % #flags + 1],
			color = Country.rgba(palette[(peer - 1) % #palette + 1]), flag_fill = true }
	end,
	lobby = {
		info = function() return { map_id = map.id, max = 50, mode = "world" } end,
		countdown = function() return queue:starts_in() end,
		estimate_bots = function(n) return queue:bot_fill(n) end,
		on_start = function(n) assert(n == players); return queue:start(n) end,
		on_over = warnTest,
	},
	send = function(peer, op, a, b)
		if op == OP.SNAPSHOT then snapshots += 1; snapBytes += buffer.len(b) end
		if op == OP.DELTA then deltas += 1; deltaBytes += buffer.len(a) + (if b then buffer.len(b) else 0) end
		if op == OP.MATCH_CLOSED then error(a) end
		if peer == 1 and (op == OP.SNAPSHOT or op == OP.DELTA or op == OP.COSMETICS) then
			table.insert(inbox, { op, a, b })
		end
	end,
})
local function issue(peer, kind, tile, ratio)
	assert(match:intent(peer, Protocol.encode_intent({ type = kind, tile = tile, ratio = ratio })))
end
local function spawn(sim)
	local starts = {}
	local distance = math.max(28, sim.R.SPAWN_RADIUS * 5)
	for i = 1, players do
		for attempt = 1, 250 do
			local tile = map:land_tile((i * 13007 + attempt * 7919) % map.land_count)
			if not sim:claimable(tile) or not sim:_area_free(tile, sim.R.SPAWN_RADIUS + 2) then continue end
			local x, y = tile % map.W, tile // map.W
			local spaced = true
			for _, other in starts do
				if (x - other % map.W)^2 + (y - other // map.W)^2 < distance^2 then spaced = false; break end
			end
			if spaced then starts[i] = tile; issue(i, "spawn", tile); break end
		end
		assert(starts[i], "missing simultaneous spawn location")
	end
end
local function expand(sim)
	local issued = 0
	for peer = 1, players do
		local id = match:participant(peer).owner
		if sim.o_alive[id] ~= 1 or sim.o_troops[id] < 100 then continue end
		sim:scan_border(id, 384)
		local tile = sim.sc_neutral_tile
		if tile < 0 then
			for _, other in sim.sc_list do
				if not sim:allied(id, other) then tile = sim.sc_tile[other]; break end
			end
		end
		if tile and tile >= 0 then issue(peer, "attack", tile, .48); issued += 1 end
	end
	return issued
end
local function metrics(values)
	local sum, slow = 0, 0
	table.sort(values)
	for _, value in values do sum += value; if value > 16.67 then slow += 1 end end
	local n = #values
	assert(n > 0)
	return { n = n, mean_ms = sum / n, p95_ms = values[math.ceil(n * .95)],
		p99_ms = values[math.ceil(n * .99)], max_ms = values[n], over_16ms = slow }
end
local function clock() return os.clock() * 1000 end
local function client(frame)
	local t = clock()
	for _, packet in inbox do receive(packet[1], packet[2], packet[3]) end
	table.clear(inbox)
	session:process(dt)
	local ready = session.state ~= nil
	if not ready then
		local elapsed = clock() - t
		return elapsed, 0, 0, elapsed
	end
	rig.scale = (vp.X / map.W) * (1.3 + .5 * math.sin(frame * .11))
	rig.x = vp.X / 2 - map.W * (.5 + .25 * math.sin(frame * .07)) * rig.scale
	rig.y = vp.Y / 2 - map.H * (.5 + .2 * math.cos(frame * .09)) * rig.scale
	rig.version += 1
	local t1 = clock()
	view._map_image_slot = if fx.image_waiting then fx else nil
	surface:step(nil, nil, view._map_image_slot ~= nil); surface:layout(rig)
	view._map_image_written = surface.uploaded
	local t2 = clock()
	fx:tick(dt)
	assert(not (surface.uploaded and fx.uploaded), "competing map uploads")
	local t3 = clock()
	return t1 - t, t2 - t1, t3 - t2, t3 - t
end

local t0 = clock()
local uids = {}
for i = 1, players do
	peers[i] = i
	uids[i] = tostring(800000 + i)
	match:join(i, { uid = uids[i], name = "Stress " .. i })
end
queue:set_present(players)
queue:set_roster(uids)
local joinMs = clock() - t0
assert(match:lobby_info(1).ai_commanders == expectedAI)
local started, wave, waves, maxOrders = false, -1, 0, 0
local build, server, apply, mapTimes, borderTimes, total = {}, {}, {}, {}, {}, {}
local opening, firstSpawn, claimSpawn = {}, 0, 0
local expanded, peakAttacks = {}, 0
local peak = { ms = 0 }
local lastYield, frame = clock(), 0
while true do
	frame += 1
	now += dt
	local sim = match:sim()
	if sim and not started then spawn(sim); started = true end
	local playing = sim and sim.phase == Defs.PHASE_PLAYING
	if playing and sim.tick > sim.playing_since and sim.tick ~= wave and (sim.tick - sim.playing_since - 1) % 20 == 0 then
		local orders = expand(sim)
		wave, waves, maxOrders = sim.tick, waves + 1, math.max(maxOrders, orders)
		if waves == 1 then assert(orders == players, "every commander orders first expansion") end
	end
	local t = clock()
	local tick = sim and sim.tick
	match:process(dt)
	local elapsed = clock() - t
	if not started then table.insert(build, elapsed) end
	if sim and sim.tick ~= tick then
		table.insert(server, elapsed)
		if sim.tick == 1 then firstSpawn = elapsed end
		if sim.tick == 2 then claimSpawn = elapsed end
		peakAttacks = math.max(peakAttacks, #sim.attacks)
		for _, id in sim.humans do
			local initial = sim._human_disk[id]
			if initial and sim.o_tiles[id] > #initial then expanded[id] = true end
		end
	end
	local a, s, f, all = client(frame)
	if playing then
		table.insert(apply, a); table.insert(mapTimes, s); table.insert(borderTimes, f); table.insert(total, all)
		if all > peak.ms then peak = { ms = all, apply_ms = a, surface_ms = s, borders_ms = f, tick = sim.tick } end
	else
		table.insert(opening, all)
	end
	if playing and sim.tick - sim.playing_since >= ticks then break end
	assert(frame <= (ticks + 200) * 6 and match._step_failures == 0, "match did not advance normally")
	if clock() - lastYield >= 18 then task.wait(); lastYield = clock() end
end
local sim, state = match:sim(), session.state
assert(snapshots == players and deltas == sim.tick * players and state.tick == sim.tick)
assert(maxOrders == players and buffer.tostring(state.owner) == buffer.tostring(sim.owner))
local aiCount, aiGrew, aiSpawned, aiTiers = 0, 0, 0, {}
local aiIds, aiNames = {}, {}
local appearances = match:cosmetics_map()
for _, owner in sim.humans do
	if sim.o_bot[owner] ~= 1 then continue end
	local identity = appearances[owner]
	local name = sim.o_name[owner]
	assert(identity and identity.bot and not identity.user_id and not aiIds[identity.bot_id] and not aiNames[name])
	aiIds[identity.bot_id], aiNames[name] = true, true
	aiCount += 1
	if sim.o_spawned[owner] == 1 then aiSpawned += 1 end
	if expanded[owner] then aiGrew += 1 end
	aiTiers[sim.o_skill[owner] + 1] = (aiTiers[sim.o_skill[owner] + 1] or 0) + 1
end
assert(queue.started and aiCount == expectedAI and #sim.humans == players + expectedAI)
if expectedAI == 0 then
	assert(sim.owner_total == players and sim.tribe_count == 0 and sim.nation_count == 0)
else
	assert(aiTiers[1] and aiTiers[2] and aiTiers[3], "mixed difficulties missing")
	assert(aiSpawned == expectedAI and aiGrew >= math.floor(expectedAI * .8), "AI did not play actively")
end
local grew, alive, claimed, largest, spawned = 0, 0, 0, 0, 0
for i = 1, players do
	local id = match:participant(i).owner
	local land = sim.o_tiles[id]
	if sim.o_spawned[id] == 1 then spawned += 1 end
	if expanded[id] then grew += 1 end
	if sim.o_alive[id] == 1 then alive += 1 end
	claimed += land
	largest = math.max(largest, land)
end
assert(spawned == players and grew >= math.floor(players * .8), "commanders did not expand")
local render = { total = metrics(total), apply = metrics(apply), surface = metrics(mapTimes), borders = metrics(borderTimes), peak = peak }
local settled = 0
while surface._rebuild_active or surface._queue_n > 0 or surface._pend_n > 0 or #surface._sweeps > 0
	or (fx.cache and (fx.cache.pending > 0 or fx.cache.job ~= nil)) or fx.image_waiting
	or (fx.dirty_chunks and next(fx.dirty_chunks) ~= nil) or fx.paint_scale ~= rig.scale do
	view._map_image_slot = if fx.image_waiting then fx else nil
	surface:step(nil, nil, view._map_image_slot ~= nil)
	view._map_image_written = surface.uploaded
	fx:tick(dt)
	settled += 1
	assert(settled <= 900, "render backlog did not settle")
	if settled % 4 == 0 then task.wait() end
end
assert(fx.field and fx.field.live > 0)
Strokes.animate(fx.field, .4)
local fresh = Strokes.prepare(fx.w, fx.h, fx.styles, nil, buffer.create(fx.w * fx.h * 4), .4)
fresh.x, fresh.y = fx.field.x, fx.field.y
local bounds, cache = fx.paint_bounds, fx.cache
for y = bounds[2], bounds[4] do
	for x = bounds[1], bounds[3] do
		Strokes.project(fresh, cache.chunks[y * cache.cols + x], fx.paint_detail)
	end
end
assert(buffer.tostring(fx.pixels) == buffer.tostring(fresh.output), "incomplete border repaint")
local mapPixels = buffer.tostring(surface.comp)
surface:rebuild_all()
local rebuild = 0
while surface._rebuild_active do
	surface:step(nil, nil, true)
	rebuild += 1
	assert(rebuild <= 2000, "full map repaint did not finish")
	if rebuild % 8 == 0 then task.wait() end
end
assert(mapPixels == buffer.tostring(surface.comp), "map repaint differs from full redraw")
for _, connection in view._conns do connection:Disconnect() end
fx:destroy(); surface:destroy(); host:Destroy()
return {
	version = game.PlaceVersion, map = map.id, players = players, live_clients = 0, gpu_fps_measured = false,
	width = vp.X, height = vp.Y, ticks = sim.tick, nations = sim.owner_total,
	ai_commanders = aiCount, ai_spawned = aiSpawned, ai_grew = aiGrew, ai_tiers = aiTiers,
	ambient_nations = sim.nation_count, ambient_tribes = sim.tribe_count,
	spawned = spawned, grew = grew, alive = alive, player_tiles = claimed, largest = largest,
	waves = waves, simultaneous_orders = maxOrders, peak_delta_tiles = peakTiles, peak_attacks = peakAttacks,
	alliance_changes = allianceChanges, settled_frames = settled,
	mirror_exact = true, map_pixels_exact = true, border_pixels_exact = true,
	snapshot_recipients = snapshots, snapshot_bytes = snapBytes,
	delta_messages = deltas, delta_bytes = deltaBytes, join_burst_ms = joinMs, build = metrics(build),
	first_spawn_ms = firstSpawn, spawn_claim_ms = claimSpawn, client_opening = metrics(opening),
	server = metrics(server), server_stats = match:take_stats(), render = render,
}
