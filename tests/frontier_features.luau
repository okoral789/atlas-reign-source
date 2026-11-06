--!nocheck
require("./prelude")
local WinsStore = require("../src/server/WinsStore")
local MatchServer = require("../src/server/MatchServer")
local Stars = require("../src/shared/Data/Stars")
local Arsenal = require("../src/shared/Data/Arsenal")
local Defs = require("../src/shared/Core/Defs")
local Session = require("../src/client/Session")
local Protocol = require("../src/shared/Net/Protocol")
local Purchases = require("../src/server/Purchases")

local records, ordered = WinsStore.memory()
local wins = WinsStore.new(records, ordered, { name = function(id) return "Player" .. id end })
assert(select(1, wins:record(1, "match-a")))
assert(select(2, wins:record(1, "match-a")) == 1, "a retry must not count a win twice")
assert(select(2, wins:record(1, "match-b")) == 2)
assert(select(2, wins:record(2, "match-a")) == 1)
local ok, top = wins:top()
assert(ok and #top == 2 and top[1].name == "Player1" and top[1].wins == 2 and top[2].wins == 1)
assert(not wins:record(0, "match") and not wins:record(1, ""), "bad identifiers are rejected")

-- A write can succeed remotely and still return an error: retry must keep one win.
local base, index = WinsStore.memory()
local uncertain = true
local proxy = {}
function proxy:UpdateAsync(key, fn)
	local result = base:UpdateAsync(key, fn)
	if uncertain then uncertain = false; error("response lost") end
	return result
end
function proxy:GetAsync(key) return base:GetAsync(key) end
local retry = WinsStore.new(proxy, index)
assert(select(2, retry:record(5, "one-match")) == 1)
assert(select(2, retry:record(5, "one-match")) == 1)

-- A failed ordered-index write is repaired on the player's next load.
local actualRecords, actualIndex = WinsStore.memory()
local broken = true
local indexProxy = {}
function indexProxy:UpdateAsync(key, fn)
	if broken then error("index unavailable") end
	return actualIndex:UpdateAsync(key, fn)
end
function indexProxy:GetSortedAsync(ascending, limit) return actualIndex:GetSortedAsync(ascending, limit) end
local repair = WinsStore.new(actualRecords, indexProxy)
local saved, n, indexed = repair:record(8, "round")
assert(saved and n == 1 and not indexed)
broken = false
assert(select(2, repair:load(8)) == 1)
assert(select(2, repair:top())[1].wins == 1)
assert(select(2, repair:record(8, "next-round")) == 2)
assert(repair:_index(8, 1) and select(2, repair:top())[1].wins == 2, "older counts never lower rank")

-- Only spawned, connected participants on the winning side count, once per match.
local sim = {
	phase = Defs.PHASE_OVER, tick = 1000, winner = 1, winner_team = 7, owner_total = 4,
	o_spawned = { 1, 1, 1, 0 }, o_team = { 7, 7, 8, 7 }, o_tiles = { 10, 0, 5, 0 },
	o_kind = { Defs.KIND_HUMAN, Defs.KIND_HUMAN, Defs.KIND_HUMAN, Defs.KIND_HUMAN },
	o_alive = { 1, 0, 1, 0 }, map = { land_count = 100 },
}
local tracker = Stars.Tracker.new(sim)
tracker._counted, tracker.field = true, 4
for id = 1, 4 do
	tracker.seats[id] = { start = 0, peak = 1, kills = 0, place = 1, out_tick = if id == 2 then 500 else nil }
end
local a, teammate, loser, spectator, unspawned = {}, {}, {}, {}, {}
local credited = {}
local server = MatchServer.new({ now_ms = function() return 0 end, on_win = function(peer, match)
	table.insert(credited, { peer, match })
end })
server._tracker, server._match_serial = tracker, 17
server._mp_sim = sim
server._order = { a, teammate, loser, spectator, unspawned }
server._participants = {
	[a] = { owner = 1 }, [teammate] = { owner = 2 }, [loser] = { owner = 3 },
	[spectator] = { owner = 1, spectator = true }, [unspawned] = { owner = 4 },
}
for i, peer in server._order do
	local part = server._participants[peer]
	if not part.spectator then
		part.peer, part.uid = peer, tostring(i)
		server._match_seats[part.uid] = part
	end
end
sim.phase = Defs.PHASE_PLAYING
server:_record_winners()
assert(#credited == 0, "an unfinished match never grants a win")
sim.phase = Defs.PHASE_OVER
server:_record_winners()
server:_record_winners()
assert(#credited == 2 and credited[1][2] == 17 and credited[2][2] == 17)
assert((credited[1][1] == a and credited[2][1] == teammate) or (credited[1][1] == teammate and credited[2][1] == a))

local session = Session.new({ mobile = false, now = function() return 0 end })
assert(not session:has_unlock("mega") and not session:has_unlock("artillery"), "advanced equipment starts locked")
session:_on_net(Protocol.OP.INVENTORY, { unlocks = { "mega", "artillery" } })
assert(session.inventory.unlocks.mega and session:has_unlock("mega"), "the active Mega Nuke unlock enables gameplay")
assert(session.inventory.unlocks.artillery and not session:has_unlock("artillery"),
	"retired entitlements stay recorded but do not enable gameplay")
assert(Arsenal.mask(Arsenal.FREE_UNLOCKS) == 0)
for _,kind in Arsenal.BASE_BOMBS do assert(Arsenal.item_for(kind)==nil) end
print("frontier_features ok")
