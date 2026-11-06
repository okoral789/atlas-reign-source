--!strict
-- Stars for a match (shared/Data/Stars; spent in the Arsenal, shared/Data/Arsenal).
--
-- A public match runs on this server: MatchServer follows it (Stars.Tracker) and its results are paid
-- through the writer below. Solo results run on the player's device and can only pay into the
-- owner-only private test economy. A reported result is typed and bounded (Stars.sanitize), can't be longer than the
-- match really lasted on this server's clock (counted from the client's "match_start" report), and
-- never pays more than Stars.solo_cap of that real time. So a made-up report earns no faster than a
-- good player, and nothing at all without the time passing.
--
--   Rewards.configure(deps)          { add_stars = fn(player, n) -> (ok, balance), double = fn(player)
--                                      -> boolean, general = fn(player) -> boolean, send = fn(player,
--                                      payload), now = fn() -> s, log? }
-- A RoWorld General (Data/Subscription) gets Subscription.STARS_BONUS of the match's Stars on top
-- (before 2x Stars doubles: the "general" line).
--   Rewards.solo_started(player, mode)   the client's match_start ("solo0" / "solo1" / "solo2")
--   Rewards.solo_result(player, report)  OP.SOLO_RESULT (yields)
--   Rewards.pay(player, result, mode)    a result this server measured itself (yields)
--   Rewards.release(player)              PlayerRemoving
-- The payload sent to the client (OP.STARS): { lines = { { key, amount } }, total, balance, mode }.
local IS_ROBLOX = typeof(game) == "Instance"
local Stars: any = if IS_ROBLOX
	then require((game :: any):GetService("ReplicatedStorage"):WaitForChild("Airfront").Data.Stars)
	else require("../shared/Data/Stars")
local Subscription: any = if IS_ROBLOX
	then require((game :: any):GetService("ReplicatedStorage"):WaitForChild("Airfront").Data.Subscription)
	else require("../shared/Data/Subscription")

local Rewards = {}

--- Results one solo match may be paid for: its end, and one more for each life a takeover gave it.
Rewards.MAX_SOLO_PAYOUTS = 4
--- Slack on the real time a solo result may claim (the report's trip, the clock's grain), minutes.
Rewards.SLACK_MIN = 0.25

type Solo = { mode: string, paid_at: number, payouts: number }

local deps: { [string]: any } = {}
local solo: { [any]: Solo } = {}

function Rewards.configure(d: { [string]: any })
	for k, v in d do
		deps[k] = v
	end
end

--- Tests: forget everyone.
function Rewards.reset()
	table.clear(solo)
end

local function now(): number
	return if deps.now then deps.now() else os.clock()
end

local function deliver(player: any, lines: { { any } }, total: number, mode: string): number
	if total <= 0 then
		return 0
	end
	local ok, balance = deps.add_stars(player, total)
	if not ok then
		return 0
	end
	if deps.send then
		pcall(deps.send, player, { lines = lines, total = total, balance = balance, mode = mode })
	end
	if deps.log then
		deps.log(string.format("[Rewards] %s +%d Stars (%s)", tostring(player.UserId), total, mode))
	end
	return total
end

function Rewards.entitlements(player: any): any
	return {
		double = player ~= nil and deps.double ~= nil and deps.double(player) == true,
		general = player ~= nil and deps.general ~= nil and deps.general(player) == true,
	}
end

local function with_double(player: any, lines: { { any } }, total: number, entitlements: any?): ({ { any } }, number)
	if total <= 0 then return lines, total end
	local perks = entitlements or Rewards.entitlements(player)
	local base = total
	if perks.double then
		table.insert(lines, { "double", total })
		total *= 2
	end
	if perks.general then
		local extra = Subscription.bonus(base, Stars.QUANTUM)
		if extra > 0 then
			table.insert(lines, { "general", extra })
			total += extra
		end
	end
	return lines, total
end

--- A result this server measured itself (a public match). Returns the Stars paid.
function Rewards.pay(player: any, result: any, mode: string?): number
	local m = mode or "public"
	local p = Stars.payout(result, m, false)
	local lines, total = with_double(player, p.lines, p.total)
	return deliver(player, lines, total, m)
end

function Rewards.public_payload(player: any, result: any, entitlements: any?): any
	local p = Stars.payout(result, "public", false)
	local lines, total = with_double(player, p.lines, p.total, entitlements)
	return { lines = lines, total = total, mode = "public" }
end

local Writer = {}
Writer.__index = Writer
local MAX_WRITES = 8

function Rewards.writer(services: any): any
	return setmetatable({ services = services, jobs = {}, active_users = {}, running = 0 }, Writer)
end

function Writer._job(self: any, user_id: number, match_id: string?): any
	local key = tostring(user_id) .. "/" .. (match_id or "restore")
	local job = self.jobs[key]
	if job == nil then
		job = { user_id = user_id, match_id = match_id, at = self.services.wall_time(), due = 0, tries = 0, sequence = 0 }
		self.jobs[key] = job
	end
	return job
end

function Writer.enqueue(self: any, user_id: number, match_id: string, payload: any, won: boolean)
	local pays = payload ~= nil and payload.total > 0
	if not pays and not won then return end
	local job = self:_job(user_id, match_id)
	if pays and not job.credit_saved and job.payload == nil then job.payload = payload end
	if won and not job.win_saved then job.won = true end
end

function Writer.restore(self: any, user_id: number, sequence: number)
	if sequence <= 0 then return end
	local job = self:_job(user_id, nil)
	job.sequence = math.max(job.sequence, sequence)
end

function Writer._write(self: any, job: any): boolean
	local services = self.services
	local payload, won = job.payload, job.won == true
	if payload ~= nil or won then
		local ok, balance, sequence, credited = services.save(job.user_id, job.match_id, job.at, if payload ~= nil then payload.total else nil, won)
		if not ok then return false end
		if won then
			job.won, job.win_saved = nil, true
			job.sequence = math.max(job.sequence, sequence)
		end
		if payload ~= nil then
			job.payload, job.credit_saved = nil, true
			if credited and services.on_credits then pcall(services.on_credits, job.user_id, payload, balance) end
		end
	end
	local sequence = job.sequence
	if sequence > 0 then
		local ok, total, indexed = services.sync_win(job.user_id, sequence)
		if not ok or not indexed then return false end
		if job.sequence == sequence then job.sequence = 0 end
		if services.on_win then pcall(services.on_win, job.user_id, total, indexed) end
	end
	return true
end

function Writer.step(self: any)
	local services = self.services
	local now_s = services.now()
	for key, job in self.jobs do
		if self.running >= MAX_WRITES then break end
		if not self.active_users[job.user_id] and job.due <= now_s then
			self.active_users[job.user_id] = true
			self.running += 1
			services.spawn(function()
				local ran, done = pcall(self._write, self, job)
				self.active_users[job.user_id] = nil
				self.running -= 1
				if ran and done then
					job.tries = 0
					if job.payload == nil and not job.won and job.sequence == 0 then self.jobs[key] = nil end
				else
					job.tries += 1
					job.due = services.now() + math.min(2 ^ math.min(job.tries - 1, 5), 30)
					if job.tries == 1 and services.on_retry then services.on_retry(job.user_id, job.match_id, if ran then nil else done) end
				end
			end)
		end
	end
end

function Writer.flush(self: any, deadline: number): boolean
	local services = self.services
	for _, job in self.jobs do job.due = 0 end
	while next(self.jobs) ~= nil and services.now() < deadline do
		self:step()
		if next(self.jobs) ~= nil then services.wait(0.1) end
	end
	return next(self.jobs) == nil
end

function Rewards.solo_started(player: any, mode: any)
	if type(mode) ~= "string" or Stars.MODE_MULT[mode] == nil or mode == "public" then
		solo[player] = nil
		return
	end
	solo[player] = { mode = mode, paid_at = now(), payouts = 0 }
end

--- The client's result of the solo match it reported starting. Returns the Stars paid.
function Rewards.solo_result(player: any, report: any): number
	local m = solo[player]
	if m == nil or m.payouts >= Rewards.MAX_SOLO_PAYOUTS then
		return 0
	end
	local t = now()
	local real = math.max(0, (t - m.paid_at) / 60)
	local r = Stars.sanitize(report, real + Rewards.SLACK_MIN)
	m.payouts += 1
	m.paid_at = t
	if r.left then
		solo[player] = nil -- the match is over for this player
	end
	local p = Stars.payout(r, m.mode, false)
	local lines, total = p.lines, p.total
	local cap = Stars.solo_cap(real)
	if total > cap then
		-- more than that much real time can pay: every line shrinks alike
		local k = cap / total
		total = 0
		for _, line in lines do
			line[2] = math.floor(line[2] * k / Stars.QUANTUM) * Stars.QUANTUM
			total += line[2]
		end
	end
	lines, total = with_double(player, lines, total)
	return deliver(player, lines, total, m.mode)
end

function Rewards.release(player: any)
	solo[player] = nil
end

return Rewards
