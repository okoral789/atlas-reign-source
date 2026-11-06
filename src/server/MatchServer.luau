--!strict
-- Port of the server half of scripts/net/session.gd: the shared multiplayer match.
-- LOBBY (countdown after the first player queues) → SPAWN → PLAYING → OVER (results) → LOBBY/IDLE,
-- one Sim, per-tick deltas to participants only, a cached compressed snapshot for late joiners,
-- intent sanitising + rate limits, idle drop between matches.
--
-- Pure logic with injected dependencies so it runs headless in Lune (tests/net_server.luau) and on a
-- Roblox server (ServerMain.luau wires Players/RemoteEvents/Heartbeat). Peers are opaque keys (Player
-- instances on Roblox, tables in tests).
--
--   deps = {
--     make_sim = function(config) -> Sim,          -- Sim.new(WorldMap.get(config.map_id), config)
--     pick_map = function() -> string?,          -- optional: map id of the next match (default
--                                                -- MatchServer.MP_MAP_ID, else the default map)
--     send = function(peer, op, ...),             -- one ordered reliable message to a peer
--     peers = function() -> { peer },             -- connected peers that are listening (lobby info)
--     now_ms = function() -> number,              -- monotonic milliseconds
--     log = function(text)?,
--     seed = function() -> number?,
--     lobby = {                                   -- optional: a public-lobby match server
--       countdown = function() -> number?,        --   seconds to the lobby's start (nil = unknown yet)
--       info = function() -> {map_id, max}?,      --   the lobby's map and player cap
--       on_start = function(humans, voted) -> number, -- AI commanders to add;
--                                                 --   voted: started by the players' vote
--       on_resume_seat = function(uid, match_id),
--       estimate_bots = function(humans) -> number?, -- planned fill after pending arrivals
--       on_over = function(peers),                --   the match is over: send them back to a hub
--       on_closed = function()?,                  --   everyone left mid-match: it is gone
--       on_vote_start = function(seconds)?,       --   the waiting players voted to start early
--     },
--   }

-- Roblox: ReplicatedStorage.Airfront.Net; Lune: the source tree.
local Net: any = if (game :: any) ~= nil then (game :: any):GetService("ReplicatedStorage").Airfront.Net else nil
local Protocol = if Net then require(Net.Protocol) else require("../shared/Net/Protocol")
local Coop = if Net then require(Net.Coop) else require("../shared/Net/Coop")
local LobbyRules = require("./Lobbies/LobbyRules")
local BotRoster = if Net then require(Net.Parent.Data.BotRoster) else require("../shared/Data/BotRoster")
local Stars: any = if Net then require(Net.Parent.Data.Stars) else require("../shared/Data/Stars")
local Defs = if Net then require(Net.Parent.Core.Defs) else require("../shared/Core/Defs")


local MatchServer = {}
MatchServer.__index = MatchServer
MatchServer.STAGE_IDLE = "idle"
MatchServer.STAGE_LOBBY = "lobby"
MatchServer.STAGE_SPAWN = "spawn"
MatchServer.STAGE_PLAYING = "playing"
MatchServer.STAGE_OVER = "over"

MatchServer.TICK_SEC = 1.0 / 10
MatchServer.LOBBY_COUNTDOWN_SEC = 15.0
MatchServer.REMATCH_COUNTDOWN_SEC = 12.0
MatchServer.RESULTS_SEC = 18.0
--- Once VOTE_SHARE of the waiting players voted to start, the match starts this soon.
MatchServer.VOTE_SHARE = 2 / 3 -- (2026-09-27; was more than half)
MatchServer.VOTE_START_S = 10.0
--- Vote start needs at least this many players waiting (2026-09-26)...
MatchServer.VOTE_MIN_PLAYERS = 2
--- ...except a player who has waited alone in a public match's waiting room this long (2026-09-27).
MatchServer.VOTE_SOLO_AFTER_S = 30.0
--- Ambient nations stay Easy. Public player-slot commanders have their own roster skill.
MatchServer.MP_DIFFICULTY = 1
--- Core/Teams.HVN (a lobby's `teams` for Humans Vs Nations).
MatchServer.HVN = "Humans Vs Nations"
--- Tribes per match (nil: Sim.default_tribes, 400).
MatchServer.MP_TRIBES = nil :: number?
--- Map of the multiplayer matches when deps.pick_map is not given (nil: MapList.DEFAULT).
MatchServer.MP_MAP_ID = nil :: string?
--- (LobbyRules.MAX_PLAYERS: a public lobby seats up to 50 since 2026-10-19; it was 32 over 30-seat lobbies)
MatchServer.MP_MAX_HUMANS = 50
MatchServer.MP_SPAWN_TICKS = 200
MatchServer.MP_TIME_LIMIT_S = 40 * 60
MatchServer.NOTICE_INFO = 0
MatchServer.NOTICE_WARNING = 1
MatchServer.NOTICE_ERROR = 2
MatchServer.MAX_INTENTS_PER_SEC = 30
MatchServer.JOIN_COOLDOWN_MSEC = 2000
--- A peer may ask for a fresh snapshot (RESYNC, after its mirror failed a delta) this often.
MatchServer.RESYNC_COOLDOWN_MSEC = 10000
--- A failing Sim step / encode ends the match after this many failures in a row, or this many in one
--- match (each failure is followed by a snapshot resync of every participant).
MatchServer.MAX_STEP_FAILURES_IN_ROW = 3
MatchServer.MAX_STEP_FAILURES = 10
MatchServer.STEP_FAILED_NOTICE = "The match ran into a problem. You're back at the title screen."
--- Participants idle this long are not carried into the next match.
MatchServer.IDLE_DROP_MSEC = 5 * 60 * 1000
--- Catch-up cap: at most this many ticks are stepped after a server hitch.
MatchServer.MAX_CATCHUP_TICKS = 6
--- Match construction runs as a Coop job with this budget per server frame (never a long hitch
--- for the players already connected, as long as the Core loops call Coop.check()).
MatchServer.BUILD_BUDGET_S = 0.012

-- Wire constants mirrored from Core (kept local so this module has no Sim dependency).
local EV_MSG = 19
local EV_BONUS = 34
local PHASE_PLAYING = 1
local PHASE_OVER = 2

local OP = Protocol.OP
local STAGE_IDLE, STAGE_LOBBY, STAGE_SPAWN, STAGE_PLAYING, STAGE_OVER = "idle", "lobby", "spawn", "playing", "over"

--- `spectator`: watching only (arrived through a hub's Watch): no nation, never counted as a player,
--- gets the snapshot and the public deltas. `voted`: wants the waiting match to start now.
export type Participant = {
	uid: string,
	key: string,
	name: string,
	owner: number,
	active_msec: number,
	spectator: boolean,
	voted: boolean,
	win_recorded: boolean?,
	paid: boolean?,
	peer: any?,
	left: boolean?,
	appearance: any?,
	reward_entitlements: any?,
}

local function is_private(e: any): number?
	if e[1] == EV_MSG and e[2] ~= -1 then
		return e[2]
	end
	-- gold a player earned at a tile (a train's stop): their own map shows it, nobody else's
	if e[1] == EV_BONUS then
		return e[2]
	end
	return nil
end

function MatchServer.new(deps: { [string]: any })
	local self = setmetatable({}, MatchServer)
	self.deps = deps
	self.lobby_countdown_sec = MatchServer.LOBBY_COUNTDOWN_SEC
	self._stage = STAGE_IDLE
	self._stage_time = 0.0
	self._mp_sim = nil :: any
	self._mp_acc = 0.0
	self._mp_started_msec = 0
	self._match_serial = 0
	self._match_id = ""
	self._match_seats = {} :: { [string]: Participant }
	self._capacity = MatchServer.MP_MAX_HUMANS
	self._occupied = 0
	self._bot_count = 0
	self._ranked = deps.lobby == nil
	self._ranking_locked = false
	self._paid_owners = {} :: { [number]: boolean }
	-- peer -> participant; `_order` keeps insertion order (GDScript Dictionary order)
	self._participants = {} :: { [any]: Participant }
	self._order = {} :: { any }
	self._intent_budget = {} :: { [any]: number }
	--- Troops promised to each donation recipient this Sim tick (cap_donation).
	self._donated = {} :: { [any]: number }
	self._last_join_msec = {} :: { [any]: number }
	--- JOINs that arrived inside the cooldown: admitted when it expires instead of being dropped
	--- (a quick "Leave queue" → "Queue" would otherwise strand the client on its queue card).
	self._pending_join = {} :: { [any]: { uid: string, name: string, key: string? } }
	self._last_resync_msec = {} :: { [any]: number }
	self._step_failures_row = 0
	self._step_failures = 0
	self._step_errors_seen = {} :: { [string]: boolean }
	self._resync_all = false
	self._snap_tick = -1
	self._snap = nil :: buffer?
	self._budget_time = 0.0
	self._lobby_broadcast_time = 0.0
	self._closed = false
	--- a public-lobby match that has been played (lobby mode): later joiners go back to a hub
	self._finished = false
	--- ms (now_ms clock) at which a vote-started lobby begins (nil: no vote passed)
	self._vote_start_at = nil :: number?
	--- public waiting room: since when exactly one player is waiting (VOTE_SOLO_AFTER_S)
	self._alone_since = nil :: number?
	self._start_job = nil :: any
	self._start_world_pvp = nil :: boolean?
	--- Map id of the running match, or of the next one while no match runs (lobby info carries it
	--- so clients can download the map before the snapshot arrives). nil = the default map.
	self._map_id = self:_pick_map()
	-- instrumentation (read by ServerMain / tests)
	self.stats = {
		steps = 0,
		step_ms_total = 0.0,
		step_ms_max = 0.0,
		step_ms = {} :: { number },
		encode_ms_total = 0.0,
		bytes_sent = 0,
		deltas_sent = 0,
		delta_bytes_max = 0,
		snapshots_sent = 0,
		snapshot_bytes = 0,
		intents_ok = 0,
		intents_dropped = 0,
	}
	return self
end

function MatchServer._pick_map(self: any): string?
	local pick = self.deps.pick_map
	if pick ~= nil then
		local ok, id = pcall(pick)
		if ok and type(id) == "string" then
			return id
		end
	end
	return MatchServer.MP_MAP_ID
end

function MatchServer._log(self: any, text: string)
	local log = self.deps.log
	if log then
		log(text)
	end
end

function MatchServer._now(self: any): number
	return self.deps.now_ms()
end

function MatchServer._send(self: any, peer: any, op: number, ...: any)
	self.deps.send(peer, op, ...)
end

function MatchServer.stage(self: any): string
	return self._stage
end

function MatchServer.participant(self: any, peer: any): Participant?
	return self._participants[peer]
end

function MatchServer.participant_count(self: any): number
	return #self._order
end

function MatchServer.sim(self: any): any
	return self._mp_sim
end

function MatchServer.can_resume(self: any, uid: string, match_id: string): boolean
	local seat = self._match_seats[uid]
	local sim = self._mp_sim
	return match_id ~= "" and match_id == self._match_id and self._stage == STAGE_PLAYING
		and seat ~= nil and seat.peer == nil and seat.left ~= true and seat.owner > 0
		and sim ~= nil and sim.o_alive[seat.owner] == 1 and sim.o_spawned[seat.owner] == 1
end

-- =============================================================================================
-- Client requests
-- =============================================================================================

--- A peer asks to queue for / join the match. `info = {uid = account id, name = display name}`.
function MatchServer.join(self: any, peer: any, info: { uid: string, name: string, key: string?, spectate: boolean? })
	if self._closed then
		return
	end
	local now = self:_now()
	local last = self._last_join_msec[peer]
	if last ~= nil and now - last < MatchServer.JOIN_COOLDOWN_MSEC then
		if self._participants[peer] == nil then
			self._pending_join[peer] = info
		end
		return
	end
	self._pending_join[peer] = nil
	self._last_join_msec[peer] = now
	if self._participants[peer] ~= nil then
		-- Double-tapped JOIN: already queued or already playing. Nothing to rebuild.
		self:broadcast_lobby()
		return
	end
	local seat = self._match_seats[info.uid]
	if seat and seat.peer ~= nil and seat.peer ~= peer then return end
	if self.deps.lobby and seat and seat.left and not info.spectate then
		self:_send(peer, OP.NOTICE, "You left this match. Queue for the next one or watch.", MatchServer.NOTICE_INFO)
		return
	end
	local nice = string.gsub(tostring(info.name or ""), "^%s*(.-)%s*$", "%1")
	-- at most 20 characters (UTF-8 safe; invalid UTF-8 is dropped)
	if utf8.len(nice) == nil then
		nice = ""
	else
		local cut = utf8.offset(nice, 21)
		if cut ~= nil then
			nice = string.sub(nice, 1, cut - 1)
		end
	end
	if nice == "" then
		nice = "Commander"
	end
	-- Keyed by account so a dropped player reconnects to their own nation.
	local key = info.key or info.uid
	local spectator = info.spectate == true
	self._participants[peer] = {
		uid = info.uid,
		key = key,
		name = nice,
		owner = 0,
		active_msec = now,
		spectator = spectator,
		voted = false,
	}
	table.insert(self._order, peer)
	self:_log(string.format("[Session] %s joined multiplayer, stage=%s", nice, self._stage))
	if self._finished then
		-- a public match that already ended: straight back to a hub
		local lobby = self.deps.lobby
		if lobby then
			lobby.on_over({ peer })
		end
		return
	end
	if self._stage == STAGE_IDLE then
		if not spectator then
			self:_set_stage(STAGE_LOBBY, self:_lobby_countdown())
		end
	elseif self._stage == STAGE_SPAWN or self._stage == STAGE_PLAYING or (spectator and self._stage == STAGE_OVER) then
		self:_admit(peer)
	end
	self:broadcast_lobby()
end

--- Seconds until the match starts from the lobby stage: the public lobby's own start time on a
--- match server (a long wait while it is still unknown), else the fixed countdown.
function MatchServer._lobby_countdown(self: any): number
	local lobby = self.deps.lobby
	local cd = self.lobby_countdown_sec
	if lobby ~= nil then
		local ok, v = pcall(lobby.countdown)
		cd = if ok and type(v) == "number" then math.max(v, 0.0) else 3600.0
	end
	if self._vote_start_at ~= nil then
		cd = math.min(cd, math.max(0.0, (self._vote_start_at - self:_now()) / 1000.0))
	end
	return cd
end

--- Players waiting in the lobby who voted to start, and how many votes start the match (two thirds
--- of the players here, rounded up; watchers don't vote).
function MatchServer.vote_counts(self: any): (number, number, number)
	local players, votes = 0, 0
	for _, p in self._order do
		local part = self._participants[p]
		if part ~= nil and not part.spectator then
			players += 1
			if part.voted then
				votes += 1
			end
		end
	end
	return votes, math.max(1, math.ceil(players * MatchServer.VOTE_SHARE - 1e-9)), players
end

--- Players needed before a vote can start the match: VOTE_MIN_PLAYERS, or 1 once a player has waited
--- alone in a public waiting room for VOTE_SOLO_AFTER_S.
function MatchServer.vote_min_players(self: any): number
	if self.deps.lobby ~= nil and self._alone_since ~= nil and self:_now() - self._alone_since >= MatchServer.VOTE_SOLO_AFTER_S * 1000 then
		return 1
	end
	return MatchServer.VOTE_MIN_PLAYERS
end

--- A player toggles their vote to start the waiting match early; once VOTE_SHARE of the players
--- here voted (and at least vote_min_players are here), it starts in VOTE_START_S (locked in: later
--- joiners or unvotes don't cancel it).
function MatchServer.vote_start(self: any, peer: any)
	local part = self._participants[peer]
	if part == nil or part.spectator or self._stage ~= STAGE_LOBBY or self._start_job ~= nil then
		return
	end
	part.voted = not part.voted
	self:_check_votes()
	self:broadcast_lobby()
end

function MatchServer._check_votes(self: any)
	if self._vote_start_at ~= nil or self._stage ~= STAGE_LOBBY then
		return
	end
	local votes, need, players = self:vote_counts()
	if players >= self:vote_min_players() and votes >= need then
		self._vote_start_at = self:_now() + MatchServer.VOTE_START_S * 1000
		if self.deps.lobby == nil then
			self._stage_time = math.min(self._stage_time, MatchServer.VOTE_START_S)
		elseif self.deps.lobby.on_vote_start then
			pcall(self.deps.lobby.on_vote_start, MatchServer.VOTE_START_S)
		end
		self:_log(string.format("[Session] %d of %d players voted to start", votes, players))
	end
end

function MatchServer.leave(self: any, peer: any)
	self._pending_join[peer] = nil
	self:_drop_participant(peer)
	-- fewer players waiting: the others' votes may now be enough
	self:_check_votes()
end

--- The peer's mirror failed a delta: resend the full state (rate-limited per peer).
function MatchServer.resync(self: any, peer: any)
	local part = self._participants[peer]
	if self._mp_sim == nil or part == nil or (part.owner == 0 and not part.spectator) then
		return
	end
	local now = self:_now()
	local last = self._last_resync_msec[peer]
	if last ~= nil and now - last < MatchServer.RESYNC_COOLDOWN_MSEC then
		return
	end
	self._last_resync_msec[peer] = now
	self:_log(string.format("[Session] resync requested by %s", part.name))
	self:_send_snapshot(peer)
end

--- A fallen player may pay to take over the AI nation that eliminated them.
function MatchServer.can_take_over(self: any, peer: any, target: number): boolean
	local sim = self._mp_sim
	local part = self._participants[peer]
	if sim == nil or part == nil or part.owner == 0 or part.spectator or self._stage ~= STAGE_PLAYING then
		return false
	end
	if type(target) ~= "number" or sim.o_killer[part.owner] ~= target then
		return false
	end
	return sim:can_take_over(part.owner, target)
end

--- The takeover itself (after its credit was spent): the peer commands `target` from now on.
function MatchServer.take_over(self: any, peer: any, target: number): boolean
	if not self:can_take_over(peer, target) then
		return false
	end
	local part = self._participants[peer]
	local old = part.owner
	if not self._mp_sim:take_over(old, target) then
		return false
	end
	part.owner = target
	part.active_msec = self:_now()
	-- a new life: its Stars are counted from here (the first life was paid when it fell)
	if self._tracker ~= nil then
		self._tracker:adopt(old, target)
	end
	part.paid = false
	self:_send(peer, OP.OWNER_CHANGED, target)
	-- the nation wears its new commander's cosmetics
	self:_broadcast_cosmetics()
	self:_log(string.format("[Takeover] %s took over %s", part.name, tostring(self._mp_sim.o_name[target])))
	return true
end

--- An encoded intent from a peer (untrusted). Returns true when it reached the Sim.
function MatchServer.intent(self: any, peer: any, payload: any): boolean
	local sim = self._mp_sim
	if sim == nil then
		return false
	end
	local part = self._participants[peer]
	if part == nil or part.owner == 0 then
		return false
	end
	local used = self._intent_budget[peer] or 0
	if used >= MatchServer.MAX_INTENTS_PER_SEC then
		self.stats.intents_dropped += 1
		return false
	end
	self._intent_budget[peer] = used + 1
	local clean = Protocol.decode_intent(payload)
	if clean == nil then
		self.stats.intents_dropped += 1
		return false
	end
	part.active_msec = self:_now()
	if clean.type == "donate" then
		MatchServer.cap_donation(sim, clean, self._donated)
	end
	sim:submit(part.owner, clean)
	self.stats.intents_ok += 1
	return true
end

--- Server-side twin of the UI's donation cap (UIRules.donate_plan): a donation never exceeds what
--- tick already promised it). The Sim itself accepts any amount (that rule stays as it is on
--- purpose), but troops far above the cap make Rules.troop_growth subtract more than the nation
--- original), but troops far above the cap make Rules.troop_growth subtract more than the nation
--- has (review_gameplay R2-8): a huge gift could push a small ally's troops negative.
--- `pending` = {tick = n, [target] = troops promised this tick} (reset when the Sim tick moves).
function MatchServer.cap_donation(sim: any, it: { [string]: any }, pending: { [any]: number }?)
	local target = tonumber(it.target) or 0
	local caps, troops = sim.o_cap, sim.o_troops
	if target <= 0 or type(caps) ~= "table" or type(troops) ~= "table" then
		return
	end
	local cap = tonumber(caps[target]) or 0
	if cap <= 0 then
		return
	end
	local promised = 0
	if pending ~= nil then
		local tick = tonumber(sim.tick) or 0
		if pending.tick ~= tick then
			table.clear(pending)
			pending.tick = tick
		end
		promised = pending[target] or 0
	end
	local room = math.max(0, math.floor(cap - (tonumber(troops[target]) or 0) - promised))
	local amount = math.clamp(tonumber(it.troops) or 0, 0, room)
	it.troops = amount
	if pending ~= nil and amount > 0 then
		pending[target] = promised + amount
	end
end

--- Dispatches one client → server message (after the transport checked `op` is a number).
--- `who = {uid = account key, name = display name}` comes from the trusted server-side Player.
function MatchServer.on_client(self: any, peer: any, who: { uid: string, name: string }, op: number, ...: any)
	-- Someone is at the controls: intents, a (re)queue, or ACTIVE (the client reports user input at
	-- most every 30 s, so a player watching the end of a match is not idle-dropped at the rematch;
	-- session.gd only counted intents).
	local part = self._participants[peer]
	if part ~= nil and (op == OP.INTENT or op == OP.ACTIVE or op == OP.JOIN) then
		part.active_msec = self:_now()
	end
	if op == OP.INTENT then
		self:intent(peer, (...))
	elseif op == OP.JOIN then
		self:join(peer, who)
	elseif op == OP.LEAVE then
		self:leave(peer)
	elseif op == OP.RESYNC then
		self:resync(peer)
	elseif op == OP.VOTE_START then
		self:vote_start(peer)
	end
end

--- The peer's connection went away (Roblox PlayerRemoving).
function MatchServer.peer_disconnected(self: any, peer: any)
	self._pending_join[peer] = nil
	self:_drop_participant(peer, true)
	self._last_join_msec[peer] = nil
	self._last_resync_msec[peer] = nil
	self:_check_votes()
end

-- =============================================================================================
-- Frame processing
-- =============================================================================================

function MatchServer.process(self: any, delta: number)
	if self._closed then
		return
	end
	self._budget_time += delta
	if self._budget_time >= 1.0 then
		self._budget_time = 0.0
		table.clear(self._intent_budget)
	end
	self._lobby_broadcast_time += delta
	if self._lobby_broadcast_time >= 1.0 then
		self._lobby_broadcast_time = 0.0
		self:broadcast_lobby()
	end
	if next(self._pending_join) ~= nil then
		self:_admit_pending_joins()
	end

	local stage = self._stage
	if stage == STAGE_LOBBY then
		if self.deps.lobby ~= nil and self._start_job == nil then
			self._stage_time = self:_lobby_countdown()
			self:_public_waiting_room()
		else
			self._stage_time -= delta
		end
		local _, _, humans = self:vote_counts()
		if humans == 0 then
			self._start_job = nil
			self:_set_stage(STAGE_IDLE, 0.0)
		elseif self._start_job ~= nil then
			self:_continue_start()
		elseif self._stage_time <= 0.0 then
			self:_start_match(humans)
		end
	elseif stage == STAGE_SPAWN or stage == STAGE_PLAYING then
		local tick_sec = MatchServer.TICK_SEC
		self._mp_acc = math.min(self._mp_acc + delta, tick_sec * MatchServer.MAX_CATCHUP_TICKS)
		while self._mp_acc >= tick_sec and self._mp_sim ~= nil do
			self._mp_acc -= tick_sec
			self:_server_step()
		end
	elseif stage == STAGE_OVER then
		self._stage_time -= delta
		if self._stage_time <= 0.0 and self.deps.lobby ~= nil then
			-- a public match is played once: everyone back to a hub
			self._finished = true
			local peers = table.clone(self._order)
			self:_close_match()
			table.clear(self._participants)
			table.clear(self._order)
			self:_set_stage(STAGE_IDLE, 0.0)
			self.deps.lobby.on_over(peers)
			return
		end
		if self._stage_time <= 0.0 then
			self:_close_match()
			self:_drop_idle_participants()
			if #self._order == 0 then
				self:_set_stage(STAGE_IDLE, 0.0)
			else
				self:_set_stage(STAGE_LOBBY, MatchServer.REMATCH_COUNTDOWN_SEC)
			end
		end
	end
end

--- A lone player may vote once their waiting period has elapsed.
function MatchServer._public_waiting_room(self: any)
	local _, _, players = self:vote_counts()
	if players == 1 then
		if self._alone_since == nil then
			self._alone_since = self:_now()
		end
		self:_check_votes()
	else
		self._alone_since = nil
	end
end

--- JOINs held back by the cooldown are admitted once it has passed (in arrival order is not needed:
--- each peer has at most one pending JOIN).
function MatchServer._admit_pending_joins(self: any)
	local now = self:_now()
	for peer, info in table.clone(self._pending_join) do
		local last = self._last_join_msec[peer]
		if last == nil or now - last >= MatchServer.JOIN_COOLDOWN_MSEC then
			self._pending_join[peer] = nil
			self:join(peer, info)
		end
	end
end

function MatchServer._start_match(self: any, humans: number)
	local seed = if self.deps.seed then self.deps.seed() else math.random(0, 2 ^ 31 - 2)
	local config = {
		seed = seed,
		difficulty = MatchServer.MP_DIFFICULTY,
		tribes = MatchServer.MP_TRIBES,
		max_humans = MatchServer.MP_MAX_HUMANS,
		time_limit_s = MatchServer.MP_TIME_LIMIT_S,
		spawn_ticks = MatchServer.MP_SPAWN_TICKS,
		map_id = self._map_id,
		public_commander_ai = self.deps.lobby ~= nil,
	}
	local lobby = self.deps.lobby
	local world_pvp: boolean? = nil
	if lobby ~= nil then
		local ok, info = pcall(lobby.info)
		if ok and type(info) == "table" then
			if type(info.map_id) == "string" then
				config.map_id = info.map_id
				self._map_id = info.map_id
			end
			if type(info.max) == "number" and Defs.is_finite(info.max) then
				config.max_humans = math.clamp(math.floor(info.max), 1, MatchServer.MP_MAX_HUMANS)
			end
			world_pvp = LobbyRules.world_humans_only(config.map_id, info.mode, humans)
			if world_pvp then
				config.nations = false
				config.tribes = 0
			end
			-- a team game (Core/Teams; staging only for now): no nations in public team
			-- games, except Humans Vs Nations, which has as many as the match has player slots
			if info.mode == "team" and info.teams ~= nil then
				config.teams = info.teams
				if info.teams == MatchServer.HVN then
					config.nation_limit = if type(info.max) == "number" then info.max else nil
				else
					config.nations = false
				end
			end
		end
	end
	self._capacity = config.max_humans
	self._stage_time = 0.0
	self._start_world_pvp = world_pvp
	self._start_job = Coop.job(self.deps.make_sim, config)
	self:_continue_start()
end

function MatchServer._continue_start(self: any)
	local job = self._start_job
	if not job:step(MatchServer.BUILD_BUDGET_S) then
		return
	end
	self._start_job = nil
	local ok, sim_or_err = job.ok, if job.ok then job.result else job.err
	if not ok or sim_or_err == nil then
		-- The match could not be created (should never happen); send everyone back to the title.
		self:_log("[Session] could not start the match: " .. tostring(sim_or_err))
		for _, peer in table.clone(self._order) do
			self:_send(peer, OP.MATCH_CLOSED, "Multiplayer is unavailable right now. Try again in a moment.")
		end
		table.clear(self._participants)
		table.clear(self._order)
		self:_set_stage(STAGE_IDLE, 0.0)
		return
	end
	local world_pvp = self._start_world_pvp
	self._start_world_pvp = nil
	if world_pvp ~= nil then
		-- Players can arrive or leave while the map is being built across frames.
		local _, _, humans = self:vote_counts()
		if world_pvp ~= (humans >= LobbyRules.WORLD_HUMANS_ONLY) then
			self:_start_match(humans)
			return
		end
	end
	self._mp_sim = sim_or_err
	self._country_colors={}
	self._country_flags={}
	self._match_serial += 1
	self._match_id = if self.deps.match_id then self.deps.match_id(self._match_serial) else tostring(self._match_serial)
	table.clear(self._match_seats)
	self._occupied = 0
	self._bot_count = 0
	self._bot_results_recorded = false
	self._bot_cosmetics = {}
	self._ranked = self.deps.lobby == nil
	self._ranking_locked = false
	table.clear(self._paid_owners)
	--- the match's results, for Stars (Data/Stars)
	-- (a stand-in Sim in tests has no owner tables to follow)
	self._tracker = if type(sim_or_err.o_tiles) == "table" and type(sim_or_err.o_kind) == "table"
		then Stars.Tracker.new(sim_or_err)
		else nil
	self._mp_acc = 0.0
	self._snap_tick = -1
	self._snap = nil
	self._step_failures_row = 0
	self._step_failures = 0
	self._resync_all = false
	self._mp_started_msec = self:_now()
	-- (the players voted to start it, or its timer ran out: reported with the start)
	local voted = self._vote_start_at ~= nil
	self._vote_start_at = nil
	for _, part in self._participants do
		part.voted = false
		part.win_recorded = false
	end
	self:_set_stage(STAGE_SPAWN, 0.0)
	local now = self:_now()
	-- Every commander's nation first, then ONE snapshot for all of them: each participant's own nation
	-- is in the state it starts from (admitting one by one gave players 2..N a snapshot without their
	-- own row until the next delta, i.e. state_ready / joined_owner fired with local_info() == nil).
	local order = table.clone(self._order)
	local humans = 0
	for _, peer in order do
		local part = self._participants[peer]
		if part and not part.spectator then
			part.owner = 0
			part.active_msec = now
			if self:_ensure_owner(peer) ~= 0 then
				humans += 1
			else
				part.spectator = true
			end
		end
	end
	if humans == 0 then
		self:_abort_match("No players are ready. Join another match when you're ready to play.")
		return
	end
	-- AI commanders join after humans so player colours are assigned first.
	local lobby = self.deps.lobby
	if lobby ~= nil then
		local ok, n = pcall(lobby.on_start, humans, voted)
		n = if ok and type(n) == "number" and Defs.is_finite(n)
			then math.clamp(math.floor(n), 0, self._capacity - self._occupied)
			else 0
		if not world_pvp and n > 0 then
			local taken = {}
			for _, peer in order do
				local part = self._participants[peer]
				if part then
					taken[string.lower(part.name)] = true
				end
			end
			local names, skills, roster = table.create(n), table.create(n), table.create(n)
			local choices = table.create(BotRoster.COUNT)
			for id = 1, BotRoster.COUNT do choices[id] = id end
			for i = 1, BotRoster.COUNT do
				local j = math.random(i, BotRoster.COUNT)
				choices[i], choices[j] = choices[j], choices[i]
				local bot = BotRoster.profile(choices[i])
				if bot ~= nil and not taken[string.lower(bot.name)] then
					table.insert(names, bot.name)
					table.insert(skills, bot.skill)
					table.insert(roster, bot.id)
					if #names == n then break end
				end
			end
			local bots = self._mp_sim:add_bot_players(#names, names, skills)
			self._bot_count = if type(bots) == "table" then #bots else #names
			self._occupied += self._bot_count
			if type(bots) == "table" then
				for i, id in bots do self._bot_cosmetics[id] = { bot = true, bot_id = roster[i] } end
			end
			self._snap = nil
			self._snap_tick = -1
			self:_log(string.format("[Session] %d bot players fill the lobby", self._bot_count))
		end
	end
	-- a team game: the teams, once everyone (bot players too) is in; a party stays together
	local sim = self._mp_sim
	if sim.team_mode and type(sim.assign_teams) == "function" then
		local groups = {}
		for _, peer in order do
			local part = self._participants[peer]
			if part and part.owner ~= 0 then
				groups[part.owner] = self:_party_of(part)
			end
		end
		sim:assign_teams(groups, if lobby then self._capacity else nil)
		self._snap = nil
		self._snap_tick = -1
		self:_log(string.format("[Session] %d teams: %s", #sim.team_names, table.concat(sim.team_names, ", ")))
	end
	local cosmetics = self:cosmetics_map()
	for _, peer in order do
		local part = self._participants[peer]
		if part and (part.owner ~= 0 or part.spectator) then
			self:_send_snapshot(peer, cosmetics)
		end
	end
	self:_log(string.format("[Session] match started with %d commanders", humans))
end

--- The match's equipped cosmetics by owner id. Only humans carry a Roblox account or avatar.
function MatchServer.cosmetics_map(self: any): { [number]: any }
	local map = table.clone(self._bot_cosmetics or {})
	if self.deps.bot_stats then
		for owner, identity in map do
			local stats = self.deps.bot_stats(identity.bot_id)
			if stats ~= nil then
				map[owner] = { bot = true, bot_id = identity.bot_id, bot_matches = stats.matches, bot_wins = stats.wins }
			end
		end
	end
	local of = self.deps.cosmetics_of
	for peer, part in self._participants do
		if part.owner ~= 0 then
			local c: any = nil
			if of ~= nil then
				local ok, v = pcall(of, peer)
				c = if ok and type(v) == "table" then v else nil
			end
			local uid = tonumber(part.uid)
			local face = if uid ~= nil and uid > 0 then uid else nil
			local skin, flag = if c ~= nil then c.skin else nil, if c ~= nil then c.flag else nil
			-- Freeze the saved color for this match; changing a menu preference cannot change identity mid-fight.
			self._country_colors=self._country_colors or {}
			self._country_flags=self._country_flags or {}
			if self._country_colors[part.owner]==nil then self._country_colors[part.owner]=if c and c.color then c.color else 0 end
			if self._country_flags[part.owner]==nil then self._country_flags[part.owner]=c~=nil and c.flag_fill==true end
			if skin ~= nil or flag ~= nil or uid ~= nil then
				part.appearance = { skin = skin, flag = flag, face = face, user_id = uid, flag_fill=self._country_flags[part.owner], color=if self._country_colors[part.owner]~=0 then self._country_colors[part.owner] else nil }
				map[part.owner] = part.appearance
			end
		end
	end
	for _, part in self._match_seats do
		if part.peer == nil and part.appearance ~= nil and map[part.owner] == nil then
			map[part.owner] = part.appearance
		end
	end
	return map
end

--- Everyone (and every watcher) gets the whole map again.
function MatchServer._broadcast_cosmetics(self: any)
	if self._mp_sim == nil then
		return
	end
	local map = self:cosmetics_map()
	for _, peer in self._order do
		self:_send(peer, OP.COSMETICS, map)
	end
end

--- The Arsenal a participant plays with (deps.unlocks_of: a Defs.UNLOCK mask; server/Purchases).
function MatchServer._apply_unlocks(self: any, peer: any)
	local sim = self._mp_sim
	local part = self._participants[peer]
	local of = self.deps.unlocks_of
	if sim == nil or part == nil or part.owner == 0 or of == nil or sim.set_unlocks == nil then
		return
	end
	local ok, mask = pcall(of, peer)
	if ok and type(mask) == "number" then
		sim:set_unlocks(part.owner, mask)
	end
end

--- A player unlocked something mid-match: it works from the next tick.
function MatchServer.unlocks_changed(self: any, peer: any)
	self:_apply_unlocks(peer)
end

--- A public game earns rewards only if real opponents spawn before play begins.
function MatchServer._has_human_rivals(self: any): boolean
	local sim = self._mp_sim
	if sim.o_spawned == nil or sim.o_ai == nil then
		return false
	end
	local first_side = nil
	local seen = {}
	for _, peer in self._order do
		local part = self._participants[peer]
		local owner = part.owner
		if not part.spectator and not seen[part.uid] and owner > 0 and sim.o_spawned[owner] == 1
			and sim.o_alive[owner] == 1 and sim.o_ai[owner] == 0 and sim.o_kind[owner] == Defs.KIND_HUMAN then
			seen[part.uid] = true
			local side = if sim.team_mode then sim.o_team[owner] else owner
			if side > 0 then
				if first_side ~= nil and first_side ~= side then
					return true
				end
				first_side = side
			end
		end
	end
	return false
end

--- Pays a participant's Credits once (deps.on_result, server/Rewards):
--- when their nation falls, when the match ends, or — `left` — when they walk away from it.
function MatchServer._pay(self: any, part: Participant, left: boolean)
	local tracker = self._tracker
	if not self._ranked or tracker == nil or part.owner == 0 or part.paid
		or self._paid_owners[part.owner] or self.deps.on_result == nil then
		return
	end
	part.paid = true
	self._paid_owners[part.owner] = true
	pcall(self.deps.on_result, part.peer, tracker:result(part.owner, left), part.uid, self._match_id, part.reward_entitlements)
end

--- Count the server's final result, including an eliminated member of a winning team.
function MatchServer._record_winners(self: any)
	local tracker, on_win = self._tracker, self.deps.on_win
	if not self._ranked or tracker == nil or on_win == nil or self._mp_sim == nil or self._mp_sim.phase ~= PHASE_OVER then
		return
	end
	for _, part in self._match_seats do
		if not part.left and part.owner ~= 0 and not part.win_recorded then
			local ok, result = pcall(tracker.result, tracker, part.owner, false)
			if ok and type(result) == "table" and result.spawned == true and result.won == true then
				part.win_recorded = true
				pcall(on_win, part.peer, self._match_serial, part.uid, self._match_id)
			end
		end
	end
end

function MatchServer._record_bot_results(self: any)
	local sim, record = self._mp_sim, self.deps.on_bot_results
	if record == nil or self._bot_results_recorded or sim.phase ~= PHASE_OVER then return end
	self._bot_results_recorded = true
	local had_human = false
	for _, part in self._match_seats do
		if sim.o_spawned[part.owner] == 1 then had_human = true; break end
	end
	if not had_human then return end
	local results = {}
	for owner, identity in self._bot_cosmetics do
		if sim.o_spawned[owner] == 1 and sim.o_bot[owner] == 1 then
			local won = owner == sim.winner or (sim.winner_team ~= 0 and sim.o_team[owner] == sim.winner_team)
			table.insert(results, { id = identity.bot_id, won = won })
		end
	end
	if #results > 0 then pcall(record, self._match_id, results) end
end

--- The party a participant came with (the hub's teleport data, via the lobby hooks), or nil.
function MatchServer._party_of(self: any, part: any): string?
	local lobby = self.deps.lobby
	if lobby == nil or type(lobby.party_of) ~= "function" or part.uid == nil then
		return nil
	end
	local ok, key = pcall(lobby.party_of, part.uid)
	return if ok and type(key) == "string" then key else nil
end

--- Gives a participant a nation in the running match (or tells them the match is full). A new
--- nation invalidates the cached snapshot, so every snapshot sent contains its receiver's nation.
function MatchServer._ensure_owner(self: any, peer: any): number
	local sim = self._mp_sim
	local part = self._participants[peer]
	if sim == nil or part == nil or part.spectator then
		return 0
	end
	if part.owner == 0 then
		local mates = {}
		if sim.team_mode and #sim.team_names > 0 then
			local key = self:_party_of(part)
			if key ~= nil then
				for _, other in self._participants do
					if other ~= part and other.owner ~= 0 and self:_party_of(other) == key then
						table.insert(mates, other.owner)
					end
				end
			end
		end
		local known = if type(sim.human_keys) == "table" then sim.human_keys[part.key] else nil
		local spare = self._occupied < self._capacity
		if known == nil and self._stage == STAGE_SPAWN and self._bot_count > 0
			and (not spare or #mates > 0) and type(sim.join_waiting_bot) == "function" then
			part.owner = sim:join_waiting_bot(part.key, part.name, mates, spare)
			if part.owner ~= 0 then
				self._bot_count -= 1
				self._bot_cosmetics[part.owner] = nil
			end
		end
		if known ~= nil and sim.o_alive[known] == 0 and sim.o_spawned[known] == 1 then
			-- A reconnect to an eliminated nation retains its result instead of taking a second seat.
			part.owner = known
		elseif part.owner == 0 and (known ~= nil or spare) then
			part.owner = sim:add_human(part.key, part.name) or 0
			if part.owner ~= 0 and known == nil then
				self._occupied += 1
			end
		end
		if part.owner ~= 0 then
			local seat = self._match_seats[part.uid]
			part.peer = peer
			part.win_recorded = seat and seat.win_recorded
			self._match_seats[part.uid] = part
			self._snap = nil
			self._snap_tick = -1
			-- a team game already under way: onto its party's team, else the smallest
			if sim.team_mode and type(sim.join_team) == "function" and #sim.team_names > 0 then
				sim:join_team(part.owner, mates)
			end
			-- the Arsenal the player has unlocked, and their Stars for this match
			self:_apply_unlocks(peer)
			part.paid = self._paid_owners[part.owner] == true
			if self._tracker ~= nil then
				self._tracker:watch(part.owner)
			end
		else
			self:_send(
				peer,
				OP.NOTICE,
				"This match is full. You can watch or queue for the next match.",
				MatchServer.NOTICE_INFO
			)
		end
	end
	return part.owner
end

--- Sends a participant the full state. Snapshots are built at most once per tick (and state) and
--- shared by every admission / resync in that tick.
function MatchServer._send_snapshot(self: any, peer: any, cosmetics: { [number]: any }?)
	local sim = self._mp_sim
	local part = self._participants[peer]
	if sim == nil or part == nil or (part.owner == 0 and not part.spectator) then
		return
	end
	if self._snap_tick ~= sim.tick or self._snap == nil then
		local t0 = os.clock()
		self._snap = Protocol.compress(Protocol.encode_snapshot(sim:snapshot()))
		self._snap_tick = sim.tick
		self.stats.snapshot_ms = (os.clock() - t0) * 1000
	end
	local snap = self._snap :: buffer
	self.stats.snapshots_sent += 1
	self.stats.snapshot_bytes = buffer.len(snap)
	self.stats.bytes_sent += buffer.len(snap)
	self:_send(peer, OP.SNAPSHOT, part.owner, snap)
	-- (outside the Sim: who wears what, for this mirror)
	self:_send(peer, OP.COSMETICS, cosmetics or self:cosmetics_map())
end

--- Adds a participant to the running match and sends them the full state (late join). Joiners added
--- after another snapshot was sent this tick get their OWNER_ADD in the next delta (GameState handles
--- that idempotently).
function MatchServer._admit(self: any, peer: any)
	local part = self._participants[peer]
	if part == nil then
		return
	end
	if not part.spectator and self:_ensure_owner(peer) == 0 then
		part.spectator = true
	end
	self:_send_snapshot(peer)
	self:_broadcast_cosmetics()
end

--- One server tick, guarded: a Sim or encoder error never escapes into the Heartbeat. After a failure
--- every mirror is resynced with a snapshot (a tick whose delta was not sent, or a half-applied step,
--- leaves the clients behind); repeated failures end the match with a notice instead of freezing it.
function MatchServer._server_step(self: any)
	local ok, err = xpcall(self._step_once, debug.traceback, self)
	if ok and self._resync_all then
		ok, err = xpcall(self._resync_everyone, debug.traceback, self)
	end
	if ok then
		self._step_failures_row = 0
		return
	end
	self._step_failures_row += 1
	self._step_failures += 1
	local key = string.match(tostring(err), "^[^\n]*") or "?"
	if not self._step_errors_seen[key] then
		self._step_errors_seen[key] = true
		self:_log("[Session] match step failed: " .. tostring(err))
	end
	if
		self._step_failures_row >= MatchServer.MAX_STEP_FAILURES_IN_ROW
		or self._step_failures >= MatchServer.MAX_STEP_FAILURES
	then
		self:_abort_match(MatchServer.STEP_FAILED_NOTICE)
	else
		self._resync_all = true
	end
end

function MatchServer._resync_everyone(self: any)
	self._resync_all = false
	self._snap = nil
	self._snap_tick = -1
	local cosmetics = self:cosmetics_map()
	for _, peer in self._order do
		self:_send_snapshot(peer, cosmetics)
	end
end

--- Ends the running match for good: everyone goes back to the title with `reason`.
function MatchServer._abort_match(self: any, reason: string)
	self:_log(string.format("[Session] match aborted: %s", reason))
	for _, peer in table.clone(self._order) do
		self:_send(peer, OP.MATCH_CLOSED, reason)
	end
	self:_close_match()
	table.clear(self._participants)
	table.clear(self._order)
	table.clear(self._intent_budget)
	self._resync_all = false
	self:_set_stage(STAGE_IDLE, 0.0)
end

function MatchServer._step_once(self: any)
	local sim = self._mp_sim
	local was_playing = sim.phase == PHASE_PLAYING
	local t0 = os.clock()
	local d = sim:step()
	local t1 = os.clock()
	-- Automatic placements queued on the transition land at the start of this tick.
	if self.deps.lobby ~= nil and not self._ranking_locked and was_playing then
		self._ranking_locked = true
		self._ranked = self:_has_human_rivals()
	end
	local tracker = self._tracker
	if tracker ~= nil then
		tracker:step(d.ev)
		for _, part in self._match_seats do
			if part.owner ~= 0 and not part.paid and tracker:final(part.owner) then
				self:_pay(part, part.left == true)
			end
		end
	end
	local public, privates = Protocol.split_events(d.ev, is_private)
	local shared = Protocol.compress(Protocol.encode_delta(d, public, sim.W))
	local t2 = os.clock()
	local st = self.stats
	local step_ms = (t1 - t0) * 1000
	st.steps += 1
	st.step_ms_total += step_ms
	st.step_ms_max = math.max(st.step_ms_max, step_ms)
	table.insert(st.step_ms, step_ms)
	st.encode_ms_total += (t2 - t1) * 1000
	local shared_len = buffer.len(shared)
	st.delta_bytes_max = math.max(st.delta_bytes_max, shared_len)
	for _, peer in self._order do
		local part = self._participants[peer]
		local owner = part.owner
		if owner ~= 0 or part.spectator then
			local mine = owner ~= 0 and privates and privates[owner]
			if mine then
				local tail = Protocol.encode_tail(mine, sim.W)
				st.bytes_sent += shared_len + buffer.len(tail)
				self:_send(peer, OP.DELTA, shared, tail)
			else
				st.bytes_sent += shared_len
				self:_send(peer, OP.DELTA, shared)
			end
			st.deltas_sent += 1
		end
	end
	if self._stage == STAGE_SPAWN and sim.phase == PHASE_PLAYING then
		self:_set_stage(STAGE_PLAYING, 0.0)
	end
	if sim.phase == PHASE_OVER and self._stage ~= STAGE_OVER then
		self:_set_stage(STAGE_OVER, MatchServer.RESULTS_SEC)
		self:_record_winners()
		self:_record_bot_results()
	end
end

function MatchServer._close_match(self: any)
	self._mp_sim = nil
	self._tracker = nil
	self._bot_cosmetics = {}
	self._bot_count = 0
	self._snap_tick = -1
	self._snap = nil
	table.clear(self._match_seats)
	for _, part in self._participants do
		part.owner = 0
	end
	-- the next match's map (announced in the lobby info from now on)
	self._map_id = self:_pick_map()
end

--- Players who walked away are not auto-entered into the next match.
function MatchServer._drop_idle_participants(self: any)
	local now = self:_now()
	for _, peer in table.clone(self._order) do
		local part = self._participants[peer]
		if part and now - part.active_msec > MatchServer.IDLE_DROP_MSEC then
			self:_remove(peer)
			self:_send(peer, OP.MATCH_CLOSED, "You were away, so you weren't entered in the next match.")
		end
	end
end

function MatchServer._remove(self: any, peer: any)
	self._participants[peer] = nil
	local i = table.find(self._order, peer)
	if i then
		table.remove(self._order, i)
	end
	self._intent_budget[peer] = nil
end

function MatchServer._drop_participant(self: any, peer: any, disconnected: boolean?)
	local part = self._participants[peer]
	if part == nil then
		return
	end
	local owner = part.owner
	local sim = self._mp_sim
	local lobby = self.deps.lobby
	local retained = disconnected and lobby ~= nil and self._stage == STAGE_PLAYING
		and sim ~= nil and owner > 0 and sim.o_spawned[owner] == 1
	local held = retained and sim.o_alive[owner] == 1
	if retained and self.deps.reward_entitlements ~= nil then
		local ok, value = pcall(self.deps.reward_entitlements, peer)
		if ok then part.reward_entitlements = value end
	elseif not retained then
		part.left = true
		self:_pay(part, true)
	end
	part.peer = nil
	self:_remove(peer)
	if sim ~= nil and owner ~= 0 then
		sim:remove_human(owner)
	end
	local st = self._stage
	if #self._order == 0 and (st == STAGE_SPAWN or st == STAGE_PLAYING or st == STAGE_OVER) then
		for _, seat in self._match_seats do
			self:_pay(seat, true)
		end
		self:_close_match()
		self:_set_stage(STAGE_IDLE, 0.0)
		if lobby ~= nil then
			-- a public match everyone left is over for good (nothing left to watch either)
			self._finished = true
			if lobby.on_closed then
				pcall(lobby.on_closed)
			end
		end
	elseif held and lobby ~= nil and lobby.on_resume_seat ~= nil then
		pcall(lobby.on_resume_seat, part.uid, self._match_id)
	end
	self:broadcast_lobby()
end

function MatchServer._set_stage(self: any, stage: string, timer: number)
	if stage == STAGE_IDLE or stage == STAGE_LOBBY then
		self._vote_start_at = nil -- a new wait: nobody has voted yet
	end
	if stage ~= STAGE_LOBBY or self._stage ~= STAGE_LOBBY then
		self._alone_since = nil
	end
	self._stage = stage
	self._stage_time = timer
	self:_log("[Session] stage -> " .. stage)
	self:broadcast_lobby()
end

local function lobby_solo_wait(self: any, voters: number): boolean
	return self.deps.lobby ~= nil and voters == 1 and self._alone_since ~= nil and self._stage == STAGE_LOBBY
end

--- Lobby info for one peer (session.gd _broadcast_lobby's dictionary).
local function lobby_for(info: { [string]: any }, part: Participant?): { [string]: any }
	info.voted = part ~= nil and part.voted
	info.in_match = part ~= nil
	info.spectating = part ~= nil and part.spectator
	return info
end

function MatchServer.lobby_info(self: any, peer: any): { [string]: any }
	local names = table.create(#self._order)
	local watchers = 0
	for _, p in self._order do
		local part = self._participants[p]
		if part.spectator then
			watchers += 1
		else
			table.insert(names, part.name)
		end
	end
	local humans = #names
	local votes, votes_needed, voters = self:vote_counts()
	local vote_min = self:vote_min_players()
	local solo_in = nil
	if lobby_solo_wait(self, voters) then
		solo_in = math.max(0.0, MatchServer.VOTE_SOLO_AFTER_S - (self:_now() - self._alone_since) / 1000.0)
	end
	local elapsed = 0.0
	if self._mp_sim ~= nil then
		elapsed = (self:_now() - self._mp_started_msec) / 1000.0
	end
	local lobby = self.deps.lobby
	local max = nil
	local lobby_map = nil
	local teams = nil
	local bots = self._bot_count
	if lobby ~= nil then
		local ok, info = pcall(lobby.info)
		if ok and type(info) == "table" then
			if type(info.max) == "number" and Defs.is_finite(info.max) then
				max = math.clamp(math.floor(info.max), 1, MatchServer.MP_MAX_HUMANS)
			end
			lobby_map = info.map_id
			teams = if info.mode == "team" then info.teams else nil
		end
		if self._stage == STAGE_LOBBY and humans > 0 then
			local estimate_ok, estimate = pcall(lobby.estimate_bots, humans)
			bots = if estimate_ok and type(estimate) == "number" and Defs.is_finite(estimate)
				then math.clamp(math.floor(estimate), 0, math.max(0, (max or self._capacity) - humans))
				else 0
		end
	end
	return lobby_for({
		available = true,
		-- a team game's teams (a number of teams, "Duos", ...; nil: free for all)
		teams = teams,
		-- "match": a public lobby's own server (clients join at once); "hub": the shared queue
		kind = if lobby ~= nil then "match" else "hub",
		max = max,
		stage = self._stage,
		countdown_s = math.max(self._stage_time, 0.0),
		elapsed_s = elapsed,
		players = names,
		ai_commanders = bots,
		watchers = watchers,
		votes = votes,
		votes_needed = math.max(votes_needed, vote_min),
		vote_players = humans,
		vote_min_players = vote_min,
		--- alone in a public waiting room: seconds until a lone vote may start the match
		vote_solo_in = solo_in,
		vote_started = self._vote_start_at ~= nil,
		map_id = if self._mp_sim ~= nil then self._mp_sim.map_id else (lobby_map or self._map_id),
	}, self._participants[peer])
end

function MatchServer.broadcast_lobby(self: any)
	if self._closed then
		return
	end
	local peers = self.deps.peers()
	if next(peers) == nil then return end
	local info = self:lobby_info(nil)
	for _, peer in peers do
		self:_send(peer, OP.LOBBY, lobby_for(table.clone(info), self._participants[peer]))
	end
end

--- The server is going away (Roblox BindToClose): tell everyone, stop the match.
function MatchServer.shutdown(self: any, reason: string?)
	if self._closed then
		return
	end
	for _, peer in table.clone(self._order) do
		self:_send(peer, OP.MATCH_CLOSED, reason or "The game server is restarting. You're back at the title screen.")
	end
	self:_close_match()
	table.clear(self._participants)
	table.clear(self._order)
	self._stage = STAGE_IDLE
	self._stage_time = 0.0
	self:broadcast_lobby()
	for _, peer in self.deps.peers() do
		local info = self:lobby_info(peer)
		info.available = false
		self:_send(peer, OP.LOBBY, info)
	end
	self._closed = true
end

--- Instrumentation summary since the last call (and resets the window).
function MatchServer.take_stats(self: any): { [string]: number }
	local st = self.stats
	local list = st.step_ms
	table.sort(list)
	local p50 = list[math.max(1, math.floor(#list * 0.5))] or 0
	local p99 = list[math.max(1, math.floor(#list * 0.99))] or 0
	local out = {
		steps = st.steps,
		step_ms_avg = if st.steps > 0 then st.step_ms_total / st.steps else 0,
		step_ms_p50 = p50,
		step_ms_p99 = p99,
		step_ms_max = st.step_ms_max,
		encode_ms_avg = if st.steps > 0 then st.encode_ms_total / st.steps else 0,
		bytes_sent = st.bytes_sent,
		deltas_sent = st.deltas_sent,
		delta_bytes_max = st.delta_bytes_max,
		snapshots_sent = st.snapshots_sent,
		snapshot_bytes = st.snapshot_bytes,
		snapshot_ms = st.snapshot_ms or 0,
		intents_ok = st.intents_ok,
		intents_dropped = st.intents_dropped,
	}
	st.steps, st.step_ms_total, st.step_ms_max, st.encode_ms_total = 0, 0, 0, 0
	st.bytes_sent, st.deltas_sent, st.delta_bytes_max, st.snapshots_sent = 0, 0, 0, 0
	st.intents_ok, st.intents_dropped = 0, 0
	table.clear(list)
	return out
end

return MatchServer
