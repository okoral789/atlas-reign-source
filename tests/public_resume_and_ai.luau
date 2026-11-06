local BotStats = require("../src/server/BotStats")
local LobbyDirectory = require("../src/server/Lobbies/LobbyDirectory")
local LobbyRules = require("../src/server/Lobbies/LobbyRules")
local LobbyStore = require("../src/server/Lobbies/LobbyStore")
local ResumeSeats = require("../src/server/Lobbies/ResumeSeats")

do
	local now = 1000
	local function clock() return now end
	local records = {}
	local index = {
		GetAsync = function(_, key) return records[key] end,
		UpdateAsync = function(_, key, transform)
			records[key] = transform(records[key]) or records[key]
		end,
	}
	local store = LobbyStore.localstore(clock)
	local lobby = {
		id = "playing", map = "world", map_name = "World", max = 50, starts = now - 20,
		created = now - 90, players = 2, status = "started", psid = "private", code = "server-only", beat = now,
	}
	store.put(lobby, 60 * 60)
	local seats = ResumeSeats.new(index, store, clock)
	local sent = {}
	local directory = LobbyDirectory.new({
		store = store,
		now = clock,
		resume_seats = seats,
		teleport = {
			send = function(players, code, data)
				table.insert(sent, { players = players, code = code, data = data })
				return true
			end,
		},
	})
	seats:remember("123", lobby, "job:1", now)
	assert(records["123"].code == nil and records["123"].match == "job:1")
	assert(not directory:resume("other player", "456") and #sent == 0)
	assert(directory:resume("seat owner", "123") and #sent == 1)
	assert(sent[1].players[1] == "seat owner" and sent[1].code == "server-only")
	assert(sent[1].data.code == nil and sent[1].data.psid == nil and sent[1].data.resume == "job:1")
	assert(sent[1].data.resume_at == now)
	now += 1
	seats:remember("123", lobby, "job:2", now)
	seats:consume("123", "job:1", now - 1)
	seats:remember("123", lobby, "job:old", now - 1)
	assert(select(2, seats:find("123")) == "job:2")
	seats:consume("123", "job:2", now - 1)
	assert(select(2, seats:find("123")) == "job:2", "an older teleport cannot consume a newer seat in the same match")
	seats:consume("123", "job:2", now)
	assert(seats:find("123") == nil)
	now += 1
	seats:remember("123", lobby, "job:3", now)
	store.update(lobby.id, function(v) v.psid = "other"; return v end)
	assert(seats:find("123") == nil, "different reserved server")
	store.update(lobby.id, function(v) v.psid = lobby.psid; return v end)
	now += LobbyRules.LIVE_STALE_S + 1
	assert(seats:find("123") == nil, "stale match heartbeat")
	store.update(lobby.id, function(v) v.beat = now; return v end)
	assert(seats:find("123") ~= nil)
	now += ResumeSeats.TTL_S
	store.update(lobby.id, function(v) v.beat = now; return v end)
	assert(seats:find("123") == nil, "expired account seat even with a live server")
end

do
	local saved
	local store = {
		GetAsync = function() return saved end,
		UpdateAsync = function(_, _, apply)
			saved = apply(saved)
			return saved
		end,
	}
	local first, second = BotStats.new(store), BotStats.new(store)
	assert(first:get(7) == nil)
	first:load()
	assert(first:get(7).wins == 0 and first:get(7).matches == 0)
	first:record("server1:1", { { id = 7, won = true }, { id = 8, won = false } })
	second:record("server2:1", { { id = 7, won = false }, { id = 8, won = true } })
	first:record("server1:1", { { id = 7, won = true }, { id = 8, won = false } })
	assert(first:get(7).wins == 1 and first:get(7).matches == 2)
	assert(first:get(8).wins == 1 and first:get(8).matches == 2)
end

print("public_resume_and_ai: account-bound resume, private teleport, stale/expired seats, actual bot stat dedupe passed")
