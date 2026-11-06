require("./fixtures/fixture_maps")
local Util = require("./net_util")
local Defs = require("../src/shared/Core/Defs")
local Sim = require("../src/shared/Core/Sim")
local Teams = require("../src/shared/Core/Teams")
local WorldMap = require("../src/shared/Core/WorldMap")
local Protocol = require("../src/shared/Net/Protocol")
local MatchServer = require("../src/server/MatchServer")
local MatchHost = require("../src/server/Lobbies/MatchHost")
local LobbyRules = require("../src/server/Lobbies/LobbyRules")
local LobbyStore = require("../src/server/Lobbies/LobbyStore")
local BotRoster = require("../src/shared/Data/BotRoster")
local Rules = require("../src/shared/Core/Rules")
Util.use_zstd(Protocol)
local map = WorldMap.get("onion")

do
	local now = 1000
	local clock = function() return now end
	local store = LobbyStore.localstore(clock)
	store.put({ id = "open", map = "world", map_name = "World", max = 50, starts = now + 90,
		created = now, players = 3, status = "open", psid = "test", code = "code",
		seats = { actual = now, pending = now, expired = now - 60 } }, 900)
	store.bind_psid("test", "open", 900)
	local host = MatchHost.new({ store = store, psid = "test", now = clock })
	assert(host:lookup())
	assert(host:start(0) == 0 and not host.started)
	host:set_present(1)
	host:set_roster({ "actual" })
	assert(host:starts_in() == 15)
	host:tick(1)
	assert(store.get("open").starts == now + 15, "hubs see the shortened countdown")
	assert(host:bot_fill(1) == 48, "one fresh reservation has a real seat held")
	store.update("open", function(lobby)
		lobby.seats.new = now
		lobby.players += 1
		return lobby
	end)
	host:tick(3)
	assert(host:bot_fill(1) == 47, "a read-only sync sees a new reservation")
	assert(host:start(1) == 47 and store.get("open").players == 1)
	assert(host:bot_fill(19) == 29, "mixed World keeps two pending seats open")
	assert(host:bot_fill(20) == 0 and host:bot_fill(50) == 0, "a busy World starts without AI")
	assert(LobbyRules.bot_fill({ map = "world", mode = "team", max = 48 }, 20) == 28,
		"the World FFA threshold does not change team matches")
end

local function make(max: number, fill: number, teams: string?, party: { [string]: string }?, world: boolean?)
	local now = 0
	local stats = { starts = 0, results = 0, wins = 0, practice = false, result_ids = {}, winner_ids = {}, bots = {}, seats = {}, setups = {} }
	local log = {}
	local lobby = { map = if world then "world" else "onion", max = max,
		mode = if teams then "team" elseif world then "world" else nil, teams = teams }
	local match = MatchServer.new({
		make_sim = function(config)
			if world then
				table.insert(stats.setups, config.nations == false and config.tribes == 0)
				coroutine.yield()
			end
			config.tribes = 0
			config.nations = false
			config.spawn_ticks = 10
			return Sim.new(map, config)
		end,
		send = function(_, op, message)
			if op == Protocol.OP.NOTICE and type(message) == "string" and string.find(message, "No Credits or ranked wins", 1, true) then
				stats.practice = true
			end
		end,
		peers = function() return {} end,
		log = function(message) table.insert(log, message) end,
		now_ms = function() return now end,
		reward_entitlements = function() return { double = true, general = true } end,
		on_result = function(peer, _, uid, match_id, entitlements)
			stats.results += 1
			stats.result_ids[uid] = { peer = peer, match = match_id, entitlements = entitlements }
		end,
		on_win = function(peer, _, uid, match_id)
			stats.wins += 1
			stats.winner_ids[uid] = { peer = peer, match = match_id }
		end,
		on_bot_results = function(match_id, results)
			table.insert(stats.bots, { match = match_id, results = results })
		end,
		lobby = {
			info = function() return { map_id = LobbyRules.match_map_id(lobby.map), max = max, mode = lobby.mode, teams = teams } end,
			countdown = function() return math.max(0, (1000 - now) / 1000) end,
			party_of = function(uid) return if party then party[uid] else nil end,
			on_start = function(humans)
				stats.starts += 1
				return if world then LobbyRules.bot_fill(lobby, humans) else fill
			end,
			estimate_bots = function() return fill end,
			on_resume_seat = function(uid, match_id) stats.seats[uid] = match_id end,
			on_over = function() end,
		},
	})
	local function run(stage: string)
		for _ = 1, 100 do
			if match:stage() == stage then return end
			now += 100
			match:process(0.1)
		end
		error("match never entered " .. stage .. "\n" .. table.concat(log, "\n"))
	end
	local function join(uid: string, spectate: boolean?)
		local peer = {}
		match:join(peer, { uid = uid, name = uid, spectate = spectate })
		return peer
	end
	return match, stats, run, join
end

for _, before in { 19, 20 } do
	local match, stats, run, join = make(50, 0, nil, nil, true)
	local peers = {}
	for i = 1, before do peers[i] = join(tostring(i)) end
	match:_start_match(before)
	assert(match:stage() == "lobby" and #stats.setups == 1)
	if before == 19 then
		join("20")
	else
		match:peer_disconnected(peers[20])
	end
	run("spawn")
	local pvp = before == 19
	assert(#stats.setups == 2 and stats.setups[1] ~= pvp and stats.setups[2] == pvp)
	assert(stats.starts == 1 and match:lobby_info(peers[1]).ai_commanders == (if pvp then 0 else 31))
end

math.randomseed(1106)
do
	local match, stats, run, join = make(50, 500)
	join("watcher", true)
	local left = join("left-before-start")
	match:peer_disconnected(left)
	run("idle")
	assert(stats.starts == 0 and match:sim() == nil, "spectators cannot start a bot-only game")
	local player = join("real-human")
	assert(match:lobby_info(player).ai_commanders == 49, "AI count cannot exceed the 50-slot cap")
	run("spawn")
	local sim = match:sim()
	assert(#sim.humans == 50 and match:lobby_info(player).ai_commanders == 49)
	local identities = match:cosmetics_map()
	local seen = {}
	local skills = {}
	for _, id in sim.humans do
		if sim.o_bot[id] == 1 then
			local identity = identities[id]
			local profile = BotRoster.profile(identity.bot_id)
			assert(profile and sim.o_name[id] == profile.name and identity.bot and not identity.face and not identity.user_id)
			assert(not seen[identity.bot_id] and sim.o_skill[id] == profile.skill)
			assert(sim.o_troops[id] == Rules.START_TROOPS_HUMAN)
			seen[identity.bot_id] = true
			skills[profile.skill] = true
		end
	end
	assert(skills[0] and skills[1] and skills[2])
	run("playing")
	match:process(0.1)
	assert(not stats.practice and not match._ranked, "AI fill needs no opening popup")
	local id = sim.human_keys["real-human"]
	sim:_game_over(id, Defs.OVER_DOMINATION)
	run("over")
	assert(stats.wins == 0 and stats.results == 0, "a practice win pays neither Credits nor rank")
	assert(#stats.bots == 1 and #stats.bots[1].results > 0)
	for _, result in stats.bots[1].results do
		assert(seen[result.id] and not result.won)
	end
	match:_record_bot_results()
	assert(#stats.bots == 1, "the actual final simulation result is recorded once")
end

do
	local match, stats, run, join = make(50, 900)
	local first
	for i = 1, 50 do
		local peer = join(tostring(i))
		if i == 1 then first = peer end
	end
	run("spawn")
	local sim = match:sim()
	assert(#sim.humans == 50 and match:lobby_info(first).ai_commanders == 0)
	local spectator = join("late")
	assert(match:lobby_info(spectator).spectating and #sim.humans == 50, "a full match offers spectating")
	run("playing")
	match:process(0.1)
	assert(match._ranked and not stats.practice)
	local original = sim.human_keys["1"]
	match:peer_disconnected(first)
	local match_id = stats.seats["1"]
	assert(match_id and match:can_resume("1", match_id))
	assert(not match:can_resume("2", match_id) and not match:can_resume("1", "wrong match"))
	assert(stats.results == 0 and sim.o_left[original] == 1)
	local returned = join("1")
	assert(match._participants[returned].owner == original and #sim.humans == 50)
	assert(not match:can_resume("1", match_id) and sim.o_left[original] == 0)
	local duplicate = join("1")
	assert(match:participant(duplicate) == nil)
	match:peer_disconnected(returned)
	assert(stats.results == 0)
	sim:_game_over(original, Defs.OVER_DOMINATION)
	run("over")
	assert(stats.result_ids["1"].match == match_id and stats.result_ids["1"].peer == nil)
	assert(stats.result_ids["1"].entitlements.double and stats.result_ids["1"].entitlements.general)
	assert(stats.wins == 1 and stats.winner_ids["1"].match == match_id and stats.winner_ids["1"].peer == nil)
	assert(not match:can_resume("1", match_id), "a completed match is not resumable")
end

do
	local match, stats, run, join = make(6, 500, Teams.TRIOS, { a = "party", b = "party", c = "party" })
	local a, b = join("a"), join("b")
	run("spawn")
	local sim = match:sim()
	local t = sim.o_team[sim.human_keys.a]
	assert(sim.o_team[sim.human_keys.b] == t, "the party starts together")
	local waiting_bot
	for _, owner in sim.humans do
		if sim.o_bot[owner] == 1 and sim.o_team[owner] == t then waiting_bot = owner end
	end
	assert(waiting_bot ~= nil)
	sim:_set_pending(waiting_bot, map:land_tile(0))
	local c = join("c")
	local id = match._participants[c].owner
	assert(id == waiting_bot and sim.o_team[id] == t and sim.o_bot[id] == 0 and #sim.humans == 6)
	assert(sim._pending_spawn[id] == nil and table.find(sim._pending_order, id) == nil,
		"the human does not inherit the AI's queued spawn choice")
	local identity = match:cosmetics_map()[id]
	assert(match:lobby_info(a).ai_commanders == 3 and (identity == nil or identity.bot ~= true))
	local counts = {}
	for _, owner in sim.humans do
		local team = sim.o_team[owner]
		counts[team] = (counts[team] or 0) + 1
	end
	assert(counts[1] == 3 and counts[2] == 3, "the replacement keeps two full trios")
	run("playing")
	match:process(0.1)
	assert(not match._ranked, "three real players on one side is still practice")
	match:leave(a)
	local walkedAway = join("a")
	assert(match:participant(walkedAway) == nil, "explicit leave cannot regain its old seat")
	local full = join("late-playing")
	assert(match:lobby_info(full).spectating and #sim.humans == 6 and #match:lobby_info(b).players == 2)
end

print("public_bot_fill: countdown, reservations, 0/1/19/20/50 humans, threshold races, late join, rejoin, trios, rewards passed")
