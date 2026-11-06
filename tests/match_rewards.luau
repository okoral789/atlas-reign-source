--!nocheck
require("./prelude")
local Purchases = require("../src/server/Purchases")
local Rewards = require("../src/server/Rewards")
local WinsStore = require("../src/server/WinsStore")

local user_id = 42
local player = { UserId = user_id }
local account = WinsStore.memory()
local rank, index = WinsStore.memory()
account:UpdateAsync("u42", function()
	return { stars = 5000, stars_earned = 2000, unlocks = { mega = true }, receipts = { "prior-purchase" } }
end)
rank:UpdateAsync("42", function() return { wins = 7, recent = { "legacy-win" } } end)
local original_update = account.UpdateAsync
local original_index_update = index.UpdateAsync
local index_down = false
function index:UpdateAsync(key, transform)
	if index_down then error("ordered index unavailable") end
	return original_index_update(self, key, transform)
end
local ambiguous = true
local account_down = false
function account:UpdateAsync(key, transform)
	if account_down then error("store unavailable before commit") end
	local stored = original_update(self, key, transform)
	if ambiguous then
		ambiguous = false
		error("committed, but response lost")
	end
	return stored
end
Purchases.configure({ datastore = account, players = { GetPlayerByUserId = function(_, id) return if id == user_id then player else nil end } })
Purchases.load(player)
local wins = WinsStore.new(rank, index)
local clock, failures, active_tasks, max_tasks = 0, 0, 0, 0
local wall_time = os.time()
local rank_down = true
local notifications = {}
local callbacks = {}
local deps = {
	now = function() return clock end,
	wall_time = function() return wall_time end,
	wait = function(seconds)
		clock += seconds
		local pending = callbacks
		callbacks = {}
		for _, callback in pending do callback() end
	end,
	spawn = function(callback)
		active_tasks += 1
		max_tasks = math.max(max_tasks, active_tasks)
		table.insert(callbacks, function()
			callback()
			active_tasks -= 1
		end)
	end,
	save = Purchases.record_match_reward,
	sync_win = function(id, sequence)
		if rank_down then return false end
		return wins:sync(id, sequence)
	end,
	on_credits = function(id, _payload, balance) notifications[id] = balance end,
	on_retry = function() failures += 1 end,
}

local writer = Rewards.writer(deps)
writer:enqueue(user_id, "match-a", { total = 250 }, false)
writer:step()
writer:enqueue(user_id, "match-a", { total = 250 }, true)
writer:enqueue(user_id, "match-a", { total = 250 }, true)
writer:step()
assert(active_tasks == 1, "a user can have only one in-flight write")
deps.wait(0)
assert(failures == 1 and account:GetAsync("u42").stars == 5250, "failed response can follow a committed result")
assert(not writer:flush(clock + 0.5), "a shutdown deadline reports unresolved ranking")
local stored = account:GetAsync("u42")
assert(stored.stars == 5250 and stored.stars_earned == 2250 and stored.match_win_sequence == 1)
assert(stored.unlocks.mega and table.find(stored.receipts, "prior-purchase"), "old purchases and balances survive the retry")
assert(Purchases.stars(player) == 5250 and rank:GetAsync("42").wins == 7)

-- A different server can restore the durable win after an exhausted shutdown deadline.
rank_down = false
Purchases.release(player)
Purchases.load(player)
local rejoined = Rewards.writer(deps)
rejoined:restore(user_id, Purchases.match_win_sequence(player))
rejoined:enqueue(user_id, "match-a", { total = 250 }, true)
assert(rejoined:flush(clock + 2))
assert(account:GetAsync("u42").stars == 5250 and rank:GetAsync("42").wins == 8)
assert(not notifications[user_id], "replayed outcomes never display a second payout")

-- Win and Credits can arrive separately, including in the reverse order.
rejoined:enqueue(user_id, "match-b", nil, true)
assert(rejoined:flush(clock + 2))
rejoined:enqueue(user_id, "match-b", { total = 100 }, false)
assert(rejoined:flush(clock + 2))
assert(notifications[user_id] == 5350 and rank:GetAsync("42").wins == 9)
assert(wins:sync(user_id, 1) and rank:GetAsync("42").wins == 9, "out-of-order win sequence cannot count twice")
assert(wins:record(user_id, "manual-test") and wins:sync(user_id, 2) and rank:GetAsync("42").wins == 10,
	"the existing win ledger preserves the new reconciled sequence")

account_down = true
rejoined:enqueue(user_id, "match-during-outage", { total = 50 }, false)
rejoined:step()
deps.wait(0)
assert(account:GetAsync("u42").stars == 5350, "failed first account write leaves the payout pending")
account_down = false
assert(rejoined:flush(clock + 2) and account:GetAsync("u42").stars == 5400,
	"close retries an unwritten payout as well as an ambiguous commit")

for id = 100, 150 do rejoined:enqueue(id, "match-c", { total = 5 }, false) end
assert(rejoined:flush(clock + 2) and max_tasks == 8, "bulk payout flush keeps concurrent store writes bounded")
assert(account:GetAsync("u150").stars == 5, "departed participants can be paid by user ID")

index_down = true
rejoined:enqueue(user_id, "match-index-retry", nil, true)
assert(not rejoined:flush(clock + 0.5), "an index-only failure keeps the earned sequence pending")
assert(rank:GetAsync("42").wins == 11, "the authoritative result was saved")
index_down = false
assert(rejoined:flush(clock + 2) and index:GetSortedAsync(false, 1):GetCurrentPage()[1].value == 11,
	"the writer repairs the ordered index without counting another win")

Rewards.configure({ double = function(p) return p == player end, general = function(p) return p == player end })
local result = { spawned = true, left = false, won = true, minutes = 2, shares = 0, kills = 0, place = 1, field = 2 }
local connected = Rewards.public_payload(player, result)
local departed = Rewards.public_payload(nil, result, Rewards.entitlements(player))
assert(connected.total == departed.total and departed.total > Rewards.public_payload(nil, result).total)
assert(departed.lines[#departed.lines - 1][1] == "double" and departed.lines[#departed.lines][1] == "general")
print("PASS match rewards: ambiguous commit, durable win recovery, concurrent deduplication, preserved purchases and bounded shutdown")
