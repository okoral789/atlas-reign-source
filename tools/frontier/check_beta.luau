-- Run in a headless task on the private Atlas Reign place. All test keys have a unique QA scope.
assert(game.GameId == 10774039150 and game.PlaceId == 129521354706128)
assert(#game:GetService("Players"):GetPlayers() == 0)

local shared = game:GetService("ReplicatedStorage").Airfront
local server = game:GetService("ServerScriptService").AirfrontServer
local Release = require(shared.Data.ReleaseConfig)
local Access = require(server.OwnerAccess)
local PrivateTest = require(shared.Data.PrivateTest)
local LobbyRules = require(server.Lobbies.LobbyRules)
local MatchHost = require(server.Lobbies.MatchHost)
local MatchServer = require(server.MatchServer)
local Rewards = require(server.Rewards)
local WinsStore = require(server.WinsStore)
local Purchases = require(server.Purchases)
local Defs = require(shared.Core.Defs)
local Sim = require(shared.Core.Sim)
local WorldMap = require(shared.Core.WorldMap)
assert(Release.CHANNEL == "private")

local scope = game:GetService("HttpService"):GenerateGUID(false)
local data = game:GetService("DataStoreService")
local accounts = data:GetDataStore("AtlasQAAccounts", scope)
local ranks = data:GetDataStore("AtlasQAWins", scope)
local order = data:GetOrderedDataStore("AtlasQAOrderedWins", scope)
local memory = game:GetService("MemoryStoreService")
local rooms = memory:GetSortedMap("AtlasQA:" .. scope .. ":rooms")
local reservations = memory:GetHashMap("AtlasQA:" .. scope .. ":servers")
local locks = memory:GetSortedMap("AtlasQA:" .. scope .. ":locks")
local first = { UserId = 900000001, Name = "Beta A" }
local second = { UserId = 900000002, Name = "Beta B" }
local people = { first, second }
local lobbyId, psid = "test-world", "test-server"

local ok, result = xpcall(function()
	Release.CHANNEL = "beta"
	for _, p in people do
		Release.TESTERS[p.UserId] = true
		assert(Access.allowed(p.UserId, game.CreatorId, false))
	end
	assert(not Access.allowed(900000003, game.CreatorId, false))
	assert(not PrivateTest.allowed(game.CreatorId, game.CreatorId, game.GameId) and Release.can_purchase())
	assert(Release.store_name(Purchases.STORE) == Purchases.STORE .. "_live_v1")
	assert(not Purchases.grant_test_cosmetics({ UserId = game.CreatorId }))

	local elapsed, startAt = 0, os.time()
	local function now() return startAt + math.floor(elapsed) end
	local store = require(server.Lobbies.LobbyStore).memory_with(rooms, reservations, locks, scope, now)
	store.put({ id = lobbyId, map = "world", map_name = "World", max = 50, mode = "world", status = "open",
		players = 0, starts = now() + 30, created = now(), psid = psid, code = "qa-transport" }, 120)
	store.bind_psid(psid, lobbyId, 120)
	store.lock = function() return false end -- Another hub owns the scheduler in this scenario.
	local failTeleport, sent = true, 0
	local directory = require(server.Lobbies.LobbyDirectory).new({
		store = store, now = now,
		teleport = { send = function(peers, code, destination)
			assert(#peers == 1 and code == "qa-transport" and destination.lobby == lobbyId)
			if failTeleport then return false, "QA transport failure" end
			sent += 1
			return true
		end },
	})
	directory:refresh()
	local joined, failure = directory:join_public({ first }, "world")
	assert(not joined and failure == "QA transport failure" and store.get(lobbyId).players == 0)
	failTeleport = false
	for _, p in people do assert(directory:join_public({ p }, "world")) end
	assert(sent == 2 and store.get(lobbyId).players == 2)
	local returned = 0
	local host = MatchHost.new({ store = store, psid = psid, now = now,
		to_hub = function(peers) returned += #peers; return true end })
	assert(host:lookup())
	host:set_present(2)
	host:set_roster({ tostring(first.UserId), tostring(second.UserId) })
	assert(host:starts_in() == MatchHost.MAX_WAIT_AFTER_FIRST_S and host:bot_fill(2) == 48)

	local blocked = false
	Purchases.configure({ datastore = {
		GetAsync = function(_, ...) return accounts:GetAsync(...) end,
		UpdateAsync = function(_, ...)
			if blocked then error("QA store unavailable") end
			return accounts:UpdateAsync(...)
		end,
	}, players = { GetPlayerByUserId = function(_, id)
		return if id == first.UserId then first elseif id == second.UserId then second else nil
	end } })
	for _, p in people do Purchases.load(p) end
	local wins = WinsStore.new(ranks, order)
	local writer = Rewards.writer({
		now = os.clock, wall_time = os.time, spawn = task.spawn, wait = task.wait,
		save = Purchases.record_match_reward,
		sync_win = function(id, sequence) return wins:sync(id, sequence) end,
	})
	local map = WorldMap.get(LobbyRules.match_map_id("world"))
	local matchId = "beta-" .. scope
	local match = MatchServer.new({
		now_ms = function() return math.floor(elapsed * 1000) end,
		send = function() end,
		peers = function() return people end,
		match_id = function() return matchId end,
		make_sim = function(config)
			config.spawn_ticks = 10
			return Sim.new(map, config)
		end,
		on_result = function(p, report, id, key)
			writer:enqueue(tonumber(id), key, Rewards.public_payload(p, report), false)
		end,
		on_win = function(_, _, id, key) writer:enqueue(tonumber(id), key, nil, true) end,
		lobby = {
			info = function() return { map_id = map.id, mode = "world", max = 50 } end,
			countdown = function() return host:starts_in() end,
			on_start = function(n) return host:start(n) end,
			on_over = function(peers) host:finish(); assert(host:return_to_hub(peers)) end,
		},
	})
	local function advance_until(stage)
		for _ = 1, 600 do
			if match:stage() == stage then return end
			elapsed += .1
			match:process(.1)
		end
		error("The beta simulation did not reach " .. stage)
	end
	for _, p in people do match:join(p, { uid = tostring(p.UserId), name = p.Name }) end
	advance_until("playing")
	match:process(.1)
	local sim = match:sim()
	assert(match._ranked and #sim.humans == 50 and match:lobby_info(first).ai_commanders == 48)
	sim:_game_over(match:participant(first).owner, Defs.OVER_DOMINATION)
	advance_until("over")
	assert(writer:flush(os.clock() + 20))
	local before = accounts:GetAsync("u" .. first.UserId)
	assert(before.stars > 0 and before.match_win_sequence == 1)
	assert(wins:rank(first.UserId).rank == 1 and wins:rank(second.UserId).wins == 0)
	match:process(MatchServer.RESULTS_SEC + 1)
	assert(returned == 2 and store.get(lobbyId) == nil)

	local offer = require(shared.Data.Products).profile_color_20
	assert(offer.id > 0 and offer.robux == 29)
	local receipt = { PlayerId = first.UserId, ProductId = offer.id, PurchaseId = scope, CurrencySpent = offer.robux }
	blocked = true
	assert(Purchases.process_receipt(receipt) == "not_processed")
	blocked = false
	assert(Purchases.process_receipt(receipt) == "granted" and Purchases.process_receipt(receipt) == "granted")
	Purchases.release(first)
	Purchases.load(first)
	assert(Purchases.has_country_color(first, 20) and Purchases.stars(first) == before.stars)
	local saved = accounts:GetAsync("u" .. first.UserId)
	assert(#saved.receipts == 1 and saved.match_win_sequence == 1)

	local client = game:GetService("StarterPlayer").StarterPlayerScripts.AirfrontClient
	local audio = require(client.Audio.AudioDirector).new()
	assert(audio._ui_audio_pack == "cozy" and audio:ui_audio_pack() == nil,
		"beta must select the licensed sounds and keep the owner audition picker hidden")
	local sounds, seen = {}, {}
	for _, stream in require(shared.Assets.UIAudioEvaluation).cozy do
		if not seen[stream.id] then
			seen[stream.id] = true
			local sound = Instance.new("Sound")
			sound.SoundId = stream.id
			sound.Parent = game:GetService("SoundService")
			table.insert(sounds, sound)
		end
	end
	assert(#sounds > 0)
	game:GetService("ContentProvider"):PreloadAsync(sounds)
	for _, sound in sounds do
		assert(sound.IsLoaded and sound.TimeLength > 0, "beta sound failed to load")
		sound:Destroy()
	end
	audio:destroy()
	return { testers = 2, aiCommanders = 48, savedWins = saved.match_win_sequence,
		savedCredits = before.stars, receiptCount = #saved.receipts, audioAssets = #sounds,
		failedTeleportSeatRecovered = true, returnedToHub = returned }
end, debug.traceback)

Release.CHANNEL = "private"
local cleaned = true
local function remove(store, key)
	cleaned = pcall(store.RemoveAsync, store, key) and cleaned
end
for _, p in people do
	Release.TESTERS[p.UserId] = nil
	remove(accounts, "u" .. p.UserId)
	remove(ranks, tostring(p.UserId))
	remove(order, tostring(p.UserId))
end
remove(rooms, lobbyId)
remove(reservations, psid)
assert(cleaned, "QA scope cleanup failed: " .. scope)
assert(ok, result)
result.qaRecordsRemoved = true
return result
