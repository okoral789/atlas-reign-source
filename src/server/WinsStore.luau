--!strict
-- Server-confirmed multiplayer wins. A match id makes a retried write idempotent;
-- the ordered index only moves upwards, even when different servers finish out of order.
local WinsStore = {}
WinsStore.__index = WinsStore
WinsStore.RECENT = 100
WinsStore.MAX_WINS = 1000000000

local function count(value: any): number
	local n = tonumber(value)
	return if n == nil or n ~= n or n < 0 or n == math.huge then 0 else math.min(math.floor(n), WinsStore.MAX_WINS)
end

function WinsStore.new(records: any, ordered: any, opts: any?)
	local self = setmetatable({}, WinsStore) :: any
	self.records = records
	self.ordered = ordered
	self.opts = opts or {}
	return self
end

function WinsStore._try(self: any, fn: () -> any): (boolean, any)
	local ok, value = false, nil
	for attempt = 1, 3 do
		ok, value = pcall(fn)
		if ok then
			return true, value
		end
		if attempt < 3 and self.opts.wait then
			self.opts.wait(2 ^ (attempt - 1))
		end
	end
	return false, value
end

function WinsStore._index(self: any, userId: number, wins: number): boolean
	if wins <= 0 then
		return true
	end
	local ok = self:_try(function()
		return self.ordered:UpdateAsync(tostring(userId), function(old: any)
			return math.max(count(old), wins)
		end)
	end)
	return ok
end

function WinsStore.load(self: any, userId: number): (boolean, number, boolean, number)
	local ok, record = self:_try(function()
		return self.records:GetAsync(tostring(userId))
	end)
	if not ok then
		return false, 0, false, 0
	end
	local wins = if type(record) == "table" then count(record.wins) else 0
	local sequence = if type(record) == "table" then count(record.match_win_sequence) else 0
	return true, wins, self:_index(userId, wins), sequence -- repairs an index write that failed after the win was saved
end

function WinsStore.record(self: any, userId: number, matchId: string): (boolean, number, boolean)
	if type(userId) ~= "number" or userId ~= userId or userId == 0 or userId % 1 ~= 0
		or type(matchId) ~= "string" or #matchId == 0 or #matchId > 128 then
		return false, 0, false
	end
	local ok, record = self:_try(function()
		return self.records:UpdateAsync(tostring(userId), function(old: any)
			local wins = if type(old) == "table" then count(old.wins) else 0
			local recent = {}
			local found = false
			for _, id in (if type(old) == "table" and type(old.recent) == "table" then old.recent else {}) do
				if type(id) == "string" and #id <= 128 then
					table.insert(recent, id)
					found = found or id == matchId
				end
			end
			if not found then
				wins = math.min(wins + 1, WinsStore.MAX_WINS)
				table.insert(recent, matchId)
			end
			-- shortcut: retain 100 match ids; expand if a win can retry after 100 newer wins.
			while #recent > WinsStore.RECENT do
				table.remove(recent, 1)
			end
			return { wins = wins, recent = recent, match_win_sequence = if type(old) == "table" then count(old.match_win_sequence) else 0 }
		end)
	end)
	if not ok or type(record) ~= "table" then
		return false, 0, false
	end
	local wins = count(record.wins)
	return true, wins, self:_index(userId, wins)
end

--- Reconcile the lifetime sequence earned in the account store. Older and repeated snapshots add nothing.
function WinsStore.sync(self: any, userId: number, sequence: number): (boolean, number, boolean)
	local total = 0
	local target = count(sequence)
	local ok = self:_try(function()
		return self.records:UpdateAsync(tostring(userId), function(old: any)
			local record = if type(old) == "table" then table.clone(old) else {}
			local seen = count(record.match_win_sequence)
			total = count(record.wins)
			if target <= seen then return nil end
			total = math.min(total + target - seen, WinsStore.MAX_WINS)
			record.wins = total
			record.match_win_sequence = target
			return record
		end)
	end)
	if not ok then return false, 0, false end
	return true, total, self:_index(userId, total)
end

function WinsStore.top(self: any): (boolean, { any })
	local ok, rows = self:_try(function()
		return self.ordered:GetSortedAsync(false, 50):GetCurrentPage()
	end)
	if not ok or type(rows) ~= "table" then
		return false, {}
	end
	local out = {}
	for _, row in rows do
		local userId = tonumber(row.key)
		local wins = count(row.value)
		if userId ~= nil and userId ~= 0 and userId % 1 == 0 and wins > 0 then
			local name = "Player " .. tostring(userId)
			if self.opts.name then
				local found, result = pcall(self.opts.name, userId)
				if found and type(result) == "string" and #result > 0 then
					name = result
				end
			end
			table.insert(out, { user_id = userId, name = name, wins = wins })
		end
	end
	return true, out
end

-- Competition rank: equal win totals share a place. Bounded reads protect DataStore budgets.
function WinsStore.rank(self: any, userId: number): any
 local ok, wins, indexed = self:load(userId)
 if not ok then return {ok=false} end
 if indexed == false then return {ok=true,wins=wins,rank=nil,exact=false} end
 if wins == 0 then return {ok=true,wins=0,rank=nil,exact=true} end
 local ahead = 0
 local success,exact = self:_try(function()
  ahead = 0
  local pages = self.ordered:GetSortedAsync(false,100,wins+1)
  for page=1,25 do
   ahead += #pages:GetCurrentPage()
   if pages.IsFinished then return true end
   if page == 25 then return false end
   pages:AdvanceToNextPageAsync()
  end
  return false
 end)
 -- shortcut: show #2501+ when more than 2500 winners are ahead; use an aggregate index before scaling beyond that.
 if not success then return {ok=false,wins=wins} end
 return {ok=true,wins=wins,rank=ahead+1,exact=exact==true}
end

-- Studio uses isolated memory, never the user's live DataStores.
function WinsStore.memory(): (any, any)
	local records, index = {}, {}
	local store, ordered = {}, {}
	function store:GetAsync(key: string): any
		return records[key]
	end
	function store:UpdateAsync(key: string, transform: (any) -> any): any
		local next = transform(records[key])
		if next ~= nil then records[key] = next end
		return records[key]
	end
	function ordered:UpdateAsync(key: string, transform: (any) -> any): any
		index[key] = transform(index[key])
		return index[key]
	end
 function ordered:GetSortedAsync(_ascending: boolean, limit: number, minimum: number?): any
  local rows = {}
  for key,value in index do
   if minimum == nil or value >= minimum then table.insert(rows,{key=key,value=value}) end
  end
  table.sort(rows,function(a,b) return if a.value==b.value then a.key<b.key else a.value>b.value end)
  local cursor = 1
  local pages = {IsFinished=#rows<=limit}
  function pages:GetCurrentPage()
   local out={}
   for i=cursor,math.min(cursor+limit-1,#rows) do table.insert(out,rows[i]) end
   return out
  end
  function pages:AdvanceToNextPageAsync()
   cursor+=limit; self.IsFinished=cursor+limit-1>=#rows
  end
  return pages
 end

	return store, ordered
end

return WinsStore
