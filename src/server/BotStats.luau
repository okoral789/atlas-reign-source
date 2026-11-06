-- Completed server matches only. These counters never enter the human ranking.
local BotStats = {}
BotStats.__index = BotStats
local KEY = "roster"
local MAX_RECEIPTS = 512

function BotStats.new(store)
	return setmetatable({ store = store, current = nil }, BotStats)
end

function BotStats.load(self)
	local saved = self.store:GetAsync(KEY)
	if self.current == nil then
		self.current = if type(saved) == "table" then saved else {}
	end
end

function BotStats.get(self, id)
	if self.current == nil then return nil end
	local totals = self.current.totals
	local entry = if type(totals) == "table" then totals[tostring(id)] else nil
	return if type(entry) == "table" then entry else { matches = 0, wins = 0 }
end

function BotStats.record(self, matchId, results)
	if type(matchId) ~= "string" or matchId == "" or #results == 0 then return end
	local stored = self.store:UpdateAsync(KEY, function(previous)
		local old = if type(previous) == "table" then previous else {}
		local receipts = if type(old.receipts) == "table" then table.clone(old.receipts) else {}
		-- shortcut: recent receipts cover immediate retry, not historical backfills.
		if table.find(receipts, matchId) then return old end
		local totals = if type(old.totals) == "table" then table.clone(old.totals) else {}
		local seen = {}
		for _, result in results do
			local id = tostring(result.id)
			if not seen[id] then
				seen[id] = true
				local prior = if type(totals[id]) == "table" then totals[id] else {}
				totals[id] = { matches = (prior.matches or 0) + 1, wins = (prior.wins or 0) + (if result.won then 1 else 0) }
			end
		end
		table.insert(receipts, matchId)
		if #receipts > MAX_RECEIPTS then table.remove(receipts, 1) end
		return { totals = totals, receipts = receipts }
	end)
	if type(stored) == "table" then self.current = stored end
end

return BotStats
