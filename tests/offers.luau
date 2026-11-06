--!nocheck
-- The result screen's offers (UI/UIRules.result_offers, shown by UI/GameOver): the next unlock and
-- 2x Stars, said truthfully.
-- Run: .bin/lune run tests/offers.luau
require("./prelude")
local UIRules = require("../src/client/UI/UIRules")
local Arsenal = require("../src/shared/Data/Arsenal")

local fails, total = 0, 0
local function expect(cond: any, what: string)
	total += 1
	if cond then
		print("  ok   " .. what)
	else
		fails += 1
		print("FAIL " .. what)
	end
end

local award = { lines = {}, total = 1440, balance = 4560 }
local function inv(unlocks, stars)
	return { stars = stars or 4560, unlocks = unlocks or {}, loaded = true }
end

local o = UIRules.result_offers(award, inv(), Arsenal)
expect(
	o.goal ~= nil and o.goal.key == "mega" and o.goal.ready == false and o.goal.text == "SIEGEBREAKER  4,560 / 20,000",
	"a new player: the Siegebreaker, with the Stars they have and its price"
)
expect(o.x2 == nil, "and what this match would have paid with 2x Stars")

o = UIRules.result_offers({ lines = {}, total = 900, balance = 40000 }, inv(), Arsenal)
expect(o.goal.ready == true and o.goal.text == "UNLOCK SIEGEBREAKER", "with the Credits for it: UNLOCK")

o = UIRules.result_offers(award, inv({ reinforce = true, stars2x = true }), Arsenal)
expect(o.goal.key == "mega" and o.x2 == nil, "skip owned equipment; no retired 2x offer")

-- the balance: the payout's own, or the one handed in (the inventory's after a purchase)
o = UIRules.result_offers(award, inv({}, 99999), Arsenal)
expect(o.goal.text == "SIEGEBREAKER  4,560 / 20,000", "the payout's balance counts, not a stale inventory")
o = UIRules.result_offers(award, inv({}, 560), Arsenal, 560)
expect(o.goal.text == "SIEGEBREAKER  560 / 20,000", "after an unlock: the inventory's Credits")

local all = {}
for _, it in Arsenal.ITEMS do
	all[it.key] = true
end
o = UIRules.result_offers(award, inv(all), Arsenal)
expect(o.goal == nil and o.x2 == nil, "everything owned: nothing is offered")

expect(next(UIRules.result_offers(nil, inv(), Arsenal)) == nil, "no payout: no offers")
expect(next(UIRules.result_offers({ lines = {}, total = 0, balance = 5 }, inv(), Arsenal)) == nil, "a payout of nothing: no offers")
expect(
	next(UIRules.result_offers(award, { stars = 0, unlocks = {}, loaded = false }, Arsenal)) == nil,
	"the record not loaded yet: no offers (what is owned is unknown)"
)

print(("offers: %d/%d passed"):format(total - fails, total))
if fails > 0 then
	error(("offers: %d failures"):format(fails))
end
