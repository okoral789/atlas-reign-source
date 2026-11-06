--!strict
-- A new player's first match (2026-10-04: an updated tutorial for new players, designed for phones
-- first, since 90% of the players are on a phone, with its steps drawn from the analytics funnels).
-- The onboarding funnel of the 28 days before it (202,158 new players):
--
--   Joined 100% -> Title 99% -> Match Started 85% -> Spawned 81% -> First Attack 66%
--   -> Survived 3 Min 32% -> Survived 10 Min 24% -> Second Match 21%
--
--   * 14% never start a match: the first match starts by itself, on this device, at once;
--   * 5% never pick a start: a spot is pointed out, and taken for them after AUTO_SPAWN_S;
--   * 19% spawn and never attack: the first step is the first tap, with the place to tap marked;
--   * half of those who attack are gone within 3 minutes, while the AI may not even attack them
--     yet (Rules.HUMAN_GRACE_TICKS): they leave with nothing to do. So the first minutes are a list
--     of small goals with a reward at the end, on a match with fewer tribes in the way (TRIBES)
--     and the gentlest AI (DIFFICULTY).
--
-- The match is an ordinary solo match otherwise: it goes on after the last step. client/UI/Tutorial
-- runs the steps; server/Analytics logs them as the "Tutorial" funnel (FUNNEL); the Stars are paid
-- once per player (server/Purchases.tutorial_bonus).
local Tutorial = {}

--- Stars for finishing it (5% of the cheapest Arsenal unlock: the bar on its card moves).
Tutorial.STARS = 1000
--- Tribes on the tutorial's map (a normal match has Rules.DEFAULT_TRIBES, 400): room to grow fast.
Tutorial.TRIBES = 60
Tutorial.DIFFICULTY = 0
--- Ticks (10 a second) from placing the capital to the match starting. A solo match waits 50, but
--- (2026-10-04) a 5 s wait after placing the capital confused new players, so the tutorial's round
--- starts much sooner.
Tutorial.COUNTDOWN_TICKS = 10
-- The tutorial teaches a default ratio without restricting how much the player can send.
Tutorial.RATIO_CAP = 1.0
--- Seconds on the spawn step before a start is picked for the player.
Tutorial.AUTO_SPAWN_S = 12
--- Let the troops recover before the next order. The bar shows progress toward this training goal.
Tutorial.GROW_READY = 0.3
Tutorial.GROW_MIN_S = 1.5
--- The hostile attack is optional. The spawn can leave the player far from an enemy.
Tutorial.CONTACT_WAIT_S = 8
--- The Attack bar's step asks for one stop of it, RATIO_GOAL (the next one up from where the bar
--- starts), left there for RATIO_HOLD_S: one tap on the stop the mark points at. Never more: since
--- 2026-10-04 the tutorial never encourages a 100% attack (an attack with everything leaves the
--- nation empty). Above RATIO_HIGH the card says to go back.
---   * Until 2026-10-08 it asked for 27% to 45% of a slider that ran from 1% to 100%, held for half
---     a second: on a phone that was 17 px of a 96 px track. 19.4% of the players who reached the
---     step left on it, the most of any step (Tutorial funnel, 2026-10-07), so the
---     step was made easier.
---   * Nobody waits on it past RATIO_MAX_S (the other steps: STEP_MAX_S).
Tutorial.RATIO_GOAL = 0.35
Tutorial.RATIO_LOW = 0.3
Tutorial.RATIO_HIGH = 0.4
Tutorial.RATIO_HOLD_S = 0.2
Tutorial.RATIO_MAX_S = 30
Tutorial.RATIO_TOO_MUCH = "Try 35% to keep more troops"
--- Required steps that time out end training without reporting a completion.
Tutorial.STEP_MAX_S = 75

--- One action or observation per step. Funnel names stay stable for historical analytics.
Tutorial.STEPS = {
	{ id = "spawn", touch = "Tap open land to place your capital", desktop = "Click open land to place your capital" },
	{ id = "expand", touch = "Tap unclaimed land beside you", desktop = "Click unclaimed land beside you" },
	{
		id = "grow",
		touch = "Watch your troops refill",
		desktop = "Watch your troops refill",
		bar = true,
	},
	-- (the neighbour before the slider: a first attack at the slider's 20% leaves an army at home; in
	-- the first order of steps a new player dragged it to 100% and sent everything)
	{
		id = "attack",
		touch = "Tap enemy land on your border",
		desktop = "Click enemy land on your border",
		confirm_touch = "Tap enemy land twice to attack",
		confirm_desktop = "Click enemy land twice to attack",
		optional = true,
		max_s = 30,
	},
	{
		id = "ratio",
		touch = "Tap 35% to set your attack share",
		desktop = "Click 35% to set your attack share",
		max_s = Tutorial.RATIO_MAX_S,
	},
	{
		id = "city",
		touch = "BUILD → City → your land → ✓",
		desktop = "City (1) → click your land",
	},
}

function Tutorial.prompt(step: any, touch: boolean, confirm: boolean): string
	return if touch then (confirm and step.confirm_touch) or step.touch
		else (confirm and step.confirm_desktop) or step.desktop
end

--- The "Tutorial" funnel's steps (Creator Dashboard): 1 is the match starting, then one a step,
--- then finishing. A step passed over is not logged.
Tutorial.FUNNEL = { "Started", "Spawned", "First Tap", "Grew", "Attacked", "Used Slider", "Built City", "Completed" }

--- The funnel step of finishing step `id` (2..7), or nil.
function Tutorial.funnel_step(id: string): number?
	for i, s in Tutorial.STEPS do
		if s.id == id then
			return i + 1
		end
	end
	return nil
end

--- True for a player who has never played: no tutorial state, no match counted, no tip seen.
--- `ui` is the saved [ui] settings, `stats` the saved [stats] ({ matches }).
function Tutorial.is_new(ui: any, stats: any): boolean
	local u = if type(ui) == "table" then ui else {}
	local s = if type(stats) == "table" then stats else {}
	if type(u.tutorial) == "string" and u.tutorial ~= "" then
		return false
	end
	if (tonumber(s.matches) or 0) > 0 then
		return false
	end
	if type(u.tips_seen) == "table" and next(u.tips_seen) ~= nil then
		return false
	end
	return true
end

--- Current progress toward GROW_READY of the troop cap (0..1).
function Tutorial.refill(troops: number, cap: number): number
	local need = Tutorial.GROW_READY * cap
	return if need > 0 then math.clamp(troops / need, 0, 1) else 1
end

--- Where step `id` is in STEPS, or nil.
function Tutorial.step_index(id: string): number?
	for i, s in Tutorial.STEPS do
		if s.id == id then
			return i
		end
	end
	return nil
end

return Tutorial
