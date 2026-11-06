--!nocheck
require("./prelude")
local Purchases = require("../src/server/Purchases")
local LobbyRules = require("../src/server/Lobbies/LobbyRules")
local Style = require("../src/shared/Data/ProfileStyle")
local WinsStore = require("../src/server/WinsStore")
local Cosmetics = require("../src/shared/Data/Cosmetics")

local rows = {}
local down = false
local store = {}
function store:GetAsync(k) if down then error("offline") end return rows[k] end
function store:UpdateAsync(k, f)
	if down then error("offline") end
	local updated = f(rows[k])
	if updated ~= nil then rows[k] = updated end
	return updated
end
local player = { UserId = 42 }
Purchases.configure({ datastore = store, rng = { NextNumber = function() return 0 end } })
Purchases.load(player)
assert(select(2, Purchases.reward_win_crates(player, 0)) == 0)
assert(select(2, Purchases.reward_win_crates(player, 1)) == 1)
assert(select(2, Purchases.reward_win_crates(player, 1)) == 0, "retries do not duplicate crates")
assert(select(2, Purchases.reward_win_crates(player, 5)) == 1)
assert(select(2, Purchases.reward_win_crates(player, 10)) == 1)
assert(Purchases.credits(player).free_crate == 3 and rows.u42.paid == false)
assert(Purchases.open_crate(player, false), "free crates work for restricted players")
assert(Purchases.credits(player).free_crate == 2)
rows.u42.credits.free_crate = 0
rows.u42.credits.crate = 1
Purchases.load(player)
assert(not Purchases.open_crate(player, false), "a paid crate is blocked when restricted")
assert(rows.u42.credits.crate == 1, "a blocked crate is kept")
assert(Purchases.open_crate(player, true), "an eligible player can open a paid crate")
down = true
assert(not Purchases.reward_win_crates(player, 20), "a failed award is not counted")
down = false
assert(select(2, Purchases.reward_win_crates(player, 20)) == 1, "the next attempt restores the award")
assert(select(2, Purchases.reward_win_crates(player, 20)) == 0)

assert(LobbyRules.team_slots(50, LobbyRules.DUOS) == 50)
assert(LobbyRules.team_slots(50, LobbyRules.TRIOS) == 48)
assert(LobbyRules.team_slots(50, LobbyRules.QUADS) == 48)
assert(LobbyRules.team_slots(50, LobbyRules.DUOS, 20) == 20, "team seats respect the server capacity")
assert(LobbyRules.team_slots(50, LobbyRules.QUADS, 5) == 5, "small servers are never overbooked")
assert(LobbyRules.team_slots(50, 3, 1) == 1)
local seen = {}
for i = 0, 999 do seen[LobbyRules.team_config("world", 0, i / 1000)] = true end
assert(seen[LobbyRules.DUOS] and seen[LobbyRules.TRIOS] and seen[LobbyRules.QUADS] and seen[LobbyRules.HVN])
assert(Style.valid(1) and Style.valid(#Style.colors) and not Style.valid(0) and not Style.valid(1.5) and not Style.valid("1"))
assert(Style.badge(0) ~= Style.badge(1) and Style.badge(1) ~= Style.badge(5))
local outcomes, sum = Cosmetics.outcomes({}), 0
for _, entry in outcomes do sum += entry.odds end
assert(#outcomes > 0 and math.abs(sum - 1) < 0.000001, "all single-crate odds add to 100%")
local removed = outcomes[1].item.id
local after = Cosmetics.outcomes({ [removed] = true })
sum = 0
for _, entry in after do assert(entry.item.id ~= removed); sum += entry.odds end
assert(#after == #outcomes - 1 and math.abs(sum - 1) < 0.000001, "owned items are removed and odds are recalculated")
local records, index = WinsStore.memory()
local a, b = WinsStore.new(records, index), WinsStore.new(records, index)
assert(a:record(123, "match"))
local _, rank = b:top()
assert(rank[1].user_id == 123 and rank[1].wins == 1, "other servers read the same ranking")
print("frontier_social: all passed")
