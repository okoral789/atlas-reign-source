--!nocheck
-- The new player's tutorial: who counts as new, the steps and their funnel, the Stars paid once, and
-- Staging's reset. Run: .bin/lune run tests/tutorial.luau
require("./prelude")
local Tutorial = require("../src/shared/Data/Tutorial")
local Purchases = require("../src/server/Purchases")
local Analytics = require("../src/server/Analytics")

local fails = 0
local function expect(c: any, w: string)
	if c then
		print("  ok   " .. w)
	else
		fails += 1
		print("FAIL " .. w)
	end
end

-- who is new
expect(Tutorial.is_new({}, {}), "nothing saved: new")
expect(Tutorial.is_new(nil, nil), "no settings at all: new")
expect(Tutorial.is_new({ tutorial = "" }, { matches = 0 }), "Staging's reset: new again")
expect(not Tutorial.is_new({ tutorial = "started" }, {}), "the tutorial was started once: not new")
expect(not Tutorial.is_new({ tutorial = "done" }, {}), "done: not new")
expect(not Tutorial.is_new({}, { matches = 3 }), "matches played before the tutorial existed: not new")
expect(not Tutorial.is_new({ tips_seen = { expand = true } }, {}), "tips seen before it existed: not new")
expect(Tutorial.is_new({ tips_seen = {} }, { matches = "x" }), "junk counts as nothing")

-- the steps and the funnel
expect(#Tutorial.FUNNEL == #Tutorial.STEPS + 2, "the funnel is Started, a step each, Completed")
local seen = {}
for i, s in Tutorial.STEPS do
	expect(type(s.touch) == "string" and #s.touch <= 40, s.id .. ": a phone line of at most 40 characters")
	expect(#s.desktop <= 40, s.id .. ": a concise desktop line")
	expect(Tutorial.funnel_step(s.id) == i + 1 and not seen[s.id], s.id .. ": its own funnel step")
	seen[s.id] = true
end
expect(Tutorial.funnel_step("nope") == nil, "an unknown step has none")

-- Onboarding allows every stop and uses the same 75% per-order cap as the full game.
expect(Tutorial.RATIO_CAP == 1, "tutorial allows the full attack range")
expect(Tutorial.COUNTDOWN_TICKS <= 15, "the tutorial's match starts within 1.5 s")
do
 local UICtx=require("../src/client/UI/UICtx")
 local me={troops=1,max_troops=100000}
 local c={ratio=1,troop_floor=.25,my=function() return me end}
 expect(UICtx.order_ratio(c)==.75,"a stale reserve field cannot reduce the chosen order")
 local sent={}
 c.sent_log={};c.session={send_intent=function(_,it) table.insert(sent,it) end}
 UICtx.send(c,{type="attack",tile=1,ratio=1})
 UICtx.send(c,{type="boat",tile=2,ratio=1})
 expect(#sent==2 and sent[1].ratio==.75 and sent[2].ratio==.75,"low army attacks and landings are capped per order")
 UICtx.send(c,{type="build",kind="city",tile=1})
 expect(#sent==3,"other orders still pass through")
end

-- Growing is observed directly and reflects the current troops.
do
	local g = Tutorial.STEPS[Tutorial.step_index("grow")]
	expect(g.bar and string.find(g.touch, "refill"), "the refill has one concise objective and a progress bar")
	expect(Tutorial.GROW_READY > 0.15 and Tutorial.GROW_READY < 0.5, "the lesson waits for a partial refill")
	local need = Tutorial.GROW_READY * 100000
	expect(Tutorial.refill(need * 0.5, 100000) == 0.5, "the bar: half way to ready")
	expect(Tutorial.refill(need * 2, 100000) == 1, "full at ready and past it")
	expect(Tutorial.refill(0, 100000) == 0 and Tutorial.refill(-5, 100000) == 0, "empty with no troops")
	expect(Tutorial.refill(need * 0.5, 200000) == 0.25, "the bar reflects the new cap")
	expect(Tutorial.refill(need * 0.25, 100000) == 0.25, "orders can spend part of the refill")
	expect(Tutorial.refill(10, 0) == 1, "no cap yet: nothing to wait for")
end

do
	local Telemetry = require("../src/client/UI/Telemetry")
	local saved = { matches = 3 }
	local tel = Telemetry.new({ session = { load_settings = function(_, section)
		return if section == "stats" then saved else {}
	end } })
	expect(tel:matches_before() == 3, "matches before: the server's count")
	tel.matches_started = 1
	tel._match = { ended = false }
	expect(tel:matches_before() == 3, "the match being played is not one before it")
	tel._match.ended = true
	expect(tel:matches_before() == 4, "once it is over, it is")
	tel:new_player()
	expect(tel:matches_before() == 0, "replaying as a new player: none")
end

-- the Stars, once
local store = {}
local sent = {}
Purchases.configure({
	datastore = {
		UpdateAsync = function(_, k, fn)
			local v = fn(store[k])
			if v ~= nil then
				store[k] = v
			end
		end,
		GetAsync = function(_, k)
			return store[k]
		end,
	},
	inventory = function(player, inv)
		table.insert(sent, inv)
	end,
	log = function() end,
})
local p = { UserId = 7, Name = "P" }
expect(Purchases.tutorial_bonus(p, Tutorial.STARS) == true, "the tutorial's Stars are paid")
expect(Purchases.stars(p) == Tutorial.STARS, "to the balance")
expect(Purchases.tutorial_bonus(p, Tutorial.STARS) == false, "and not a second time")
expect(Purchases.stars(p) == Tutorial.STARS, "the balance stays")
expect(Purchases.tutorial_bonus(p, 0) == false and Purchases.tutorial_bonus(p, 0 / 0) == false, "nothing for no amount")
-- Staging: a new player again
store["u7"].crates_bought = 4
expect(Purchases.reset_new_player(p) == true, "Staging's reset goes through")
expect(store["u7"].crates_bought == 0 and store["u7"].tutorial_paid == nil, "no crate bought, no bonus paid")
expect(store["u7"].stars == Tutorial.STARS, "what is owned stays")
expect(Purchases.tutorial_bonus(p, Tutorial.STARS) == true and Purchases.stars(p) == 2 * Tutorial.STARS, "the bonus can be earned again")

-- the funnel on the server: each step once a match, in a match only
local logged = {}
local events = {}
Analytics.configure({
	onboarding = function() end,
	funnel = function(player, funnel, key, step, name)
		table.insert(logged, funnel .. ":" .. step .. ":" .. name)
	end,
	custom = function(player, name, value, f)
		table.insert(events, name .. ":" .. tostring(f[#f]))
	end,
	guid = function()
		return "k"
	end,
	tutorial_steps = Tutorial.FUNNEL,
})
local a = { UserId = 9, Name = "A" }
Analytics.joined(a)
Analytics.report(a, "tutorial", 1)
expect(#logged == 0, "a step outside a match is not logged")
Analytics.report(a, "match_start", "solo0", "world")
local before = #logged
Analytics.report(a, "tutorial", 1)
Analytics.report(a, "tutorial", 1)
Analytics.report(a, "tutorial", 3)
Analytics.report(a, "tutorial", 99)
Analytics.report(a, "tutorial", "x")
expect(#logged == before + 2, "each real step once")
expect(logged[#logged] == "Tutorial:3:First Tap" and logged[#logged - 1] == "Tutorial:1:Started", "under its name")
Analytics.report(a, "tutorial_skip", 3)
expect(events[#events] == "Tutorial Skipped:Grew", "a skip names the step it was on")
expect(Tutorial.funnel_step("attack") < Tutorial.funnel_step("ratio"), "the neighbour comes before the slider")
expect(Tutorial.RATIO_HIGH <= 0.5 and Tutorial.RATIO_LOW > 0.2, "the slider step asks for a moderate share, never everything")
do
	-- the step asks for one stop of the Attack bar: the next one up from where the bar starts, so a
	-- single tap passes it, and no other stop does
	local UICtx = require("../src/client/UI/UICtx")
	local passing, goal_i, start_i = 0, 0, 0
	for i, stop in UICtx.RATIO_STOPS do
		if stop >= Tutorial.RATIO_LOW and stop <= Tutorial.RATIO_HIGH then
			passing += 1
		end
		if stop == Tutorial.RATIO_GOAL then
			goal_i = i
		end
		if stop == UICtx.DEFAULT_RATIO then
			start_i = i
		end
	end
	expect(passing == 1 and goal_i > 0, "exactly one stop passes the step, and it is the one asked for")
	expect(Tutorial.RATIO_GOAL >= Tutorial.RATIO_LOW and Tutorial.RATIO_GOAL <= Tutorial.RATIO_HIGH, "RATIO_GOAL is inside what passes")
	expect(goal_i == start_i + 1, "it is the next stop up from where the bar starts")
	expect(Tutorial.RATIO_GOAL <= Tutorial.RATIO_CAP, "and under the tutorial's cap")
	expect(Tutorial.RATIO_HOLD_S <= 0.25 and Tutorial.RATIO_MAX_S < Tutorial.STEP_MAX_S, "it passes at once, and nobody waits on it as long as on the others")
	local pct = string.format("%d%%", Tutorial.RATIO_GOAL * 100 + 0.5)
	for _, s in Tutorial.STEPS do
		if s.id == "ratio" then
			expect(string.find(s.touch, pct, 1, true) ~= nil and string.find(s.desktop, pct, 1, true) ~= nil, "the card names the stop")
			expect(#s.touch <= 40, "the phone line fits the card")
			expect(s.max_s == Tutorial.RATIO_MAX_S, "the step has its own wait")
		end
	end
	expect(string.find(Tutorial.RATIO_TOO_MUCH, pct, 1, true) ~= nil, "so does the line for too much")
end
for _, s in Tutorial.STEPS do
	expect(not string.find(string.lower(s.touch .. s.desktop), "100%", 1, true), s.id .. ": no step speaks of 100%")
end

-- Exercise the real controller in a solo match with lightweight widget doubles.
do
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")
	local roblox = require("@lune/roblox")
	local UICtx = require("../src/client/UI/UICtx")
	local Defs = require("../src/shared/Core/Defs")
	local source = luau.load(fs.readFile("src/client/UI/Tutorial.luau"))
	setfenv(source, setmetatable({
		Vector2 = roblox.Vector2,
		UDim2 = roblox.UDim2,
		require = function(path)
			if path == "./Widgets" then return { class = function() return {} end } end
			if path == "./UICtx" then return UICtx end
			return { core = function() end }
		end,
	}, { __index = getfenv() }))
	local Controller = source()
	local function widget()
		return {
			text = "", visible = false,
			set_text = function(self, text) self.text = text end,
			set_visible = function(self, visible) self.visible = visible end,
		}
	end
	local function run(touch, skip_contact)
		local milestones, outcome = {}, nil
		local owner = { alive = true, spawned = false, troops = 1000, max_troops = 10000 }
		local state = { phase = Defs.PHASE_SPAWN, structures = {}, tile_owner = function() return 0 end }
		local ctx = {
			touch = touch, state = state, ratio = UICtx.DEFAULT_RATIO,
			mode = function() return UICtx.MODE_SOLO end, in_match = function() return true end,
			me = function() return 1 end, my = function() return owner end,
			alive_player = function() return owner.alive end, sfx = function() end,
			set_ratio = function(self, ratio) self.ratio = ratio end,
			set_ratio_max = function(self, ratio) self.ratio_max = ratio end,
			session_call = function() return nil end, rules = { cost = function() return 125000 end },
		}
		local card = setmetatable({
			ctx = ctx, ui = { bar = { button = function() end }, interact = { confirm_orders = function() return touch end } },
			completed = {}, _t = 0, _ending = 0, _mark = {}, _fill = {},
			_count = widget(), _card = widget(), _text = widget(), _bar = widget(), _skip = widget(),
			step_done = { Fire = function(_, step) table.insert(milestones, step) end },
			finished = { Fire = function(_, how) outcome = how end },
			closed = { Fire = function() end },
			_find_spot = function() return nil end, _tint = function() end, _place = function() end,
			_draw_mark = function() end,
			_frontier_point = function(self, hostile)
				self._hint_tile = if hostile and skip_contact then nil else 7
				return roblox.Vector2.zero
			end,
		}, { __index = Controller })
		local function step(dt) card:_process(dt or 0.6) end
		card:begin()
		step()
		assert(card._card.visible and card._skip.text == "Skip" and card._i == 1)
		owner.spawned, state.phase = true, Defs.PHASE_PLAYING
		step()
		step()
		assert(card._i == 2 and card._text.text:sub(1, if touch then 3 else 5) == (if touch then "Tap" else "Click"))
		ctx.sent_log = table.create(64, { intent = { type = "attack", tile = 7 } })
		card:on_attack_started({ attacker = 2, target = 0 })
		step()
		assert(card._i == 2, "raw clicks and AI attacks never advance expansion")
		card.ui._modal_open = true
		step(Tutorial.STEP_MAX_S + 1)
		assert(card._i == 2 and card.active, "reading the guide pauses the lesson timer")
		card.ui._modal_open = false
		card:on_attack_started({ attacker = 1, target = 0 })
		step()
		step(Tutorial.GROW_MIN_S + 0.6)
		assert(card._i == 3 and card._fill.Size.X.Scale < 1, "wait for real refill")
		owner.troops = owner.max_troops * Tutorial.GROW_READY
		step()
		step()
		if skip_contact then
			step(Tutorial.CONTACT_WAIT_S + 0.1)
			assert(not card.completed.attack and not table.find(milestones, Tutorial.funnel_step("attack")))
		else
			assert(card._text.text == "Tap enemy land twice to attack")
			card:on_attack_started({ attacker = 1, target = 2 })
			step()
			step()
			assert(card.completed.attack)
		end
		assert(card._i == Tutorial.step_index("ratio"))
		ctx.ratio = Tutorial.RATIO_GOAL
		step()
		step()
		assert(outcome == nil and card._i == Tutorial.step_index("city"), "no completion before a city exists")
		state.structures[1] = { owner = 1, kind = Defs.S_CITY }
		step()
		assert(outcome == "done" and milestones[#milestones] == #Tutorial.FUNNEL)
		card:begin()
		state.structures = {}
		outcome = nil
		table.clear(milestones)
		step()
		step(Tutorial.STEP_MAX_S + 1)
		assert(outcome == "incomplete" and not table.find(milestones, #Tutorial.FUNNEL),
			"a required step timeout never reports completion or credits")
		card:begin()
		card:stop("skipped")
		assert(outcome == "skipped" and not card._card.visible and not card.active)
	end
	run(false, true)
	run(true, false)
	print("  ok   desktop and touch controller progression, optional contact, timeout, skip and replay")
end

if fails > 0 then
	error(fails .. " failures")
end
print("tutorial: all passed")
