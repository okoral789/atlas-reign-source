do
	local server = game:GetService("ServerScriptService").AirfrontServer
	local copy = server.Purchases:Clone()
	copy.Name = "MatchRewardsSmokePurchases"
	copy.Parent = server
	local Purchases = require(copy)
	local Rewards = require(server.Rewards)
	local WinsStore = require(server.WinsStore)
	local ranks, index = WinsStore.memory()
	local now = os.time()
	local wall = 0
	local userId = 999999999
	local accountKey = "u" .. userId
	local rows = {}
	local archiveReads = 0
	local store = {}
	function store:GetAsync(key, options)
		if string.sub(key, 1, 2) == "r:" then
			assert(typeof(options) == "Instance" and options:IsA("DataStoreGetOptions") and options.UseCache == false)
			archiveReads += 1
		end
		return rows[key]
	end
	function store:UpdateAsync(key, transform)
		local value = transform(rows[key])
		if value ~= nil then rows[key] = value end
		return value
	end
	Purchases.configure({ datastore = store })
	local receipts = {}
	for i = 1, Purchases.RECEIPTS_KEPT do receipts[i] = "prior-" .. i end
	rows[accountKey] = { stars = 300, receipts = receipts, unlocks = { mega = true } }
	assert(Purchases.grant(userId, "takeover", "new") == "granted")
	assert(Purchases.grant(userId, "takeover", "prior-1") == "granted" and rows[accountKey].credits.takeover == 1)
	assert(archiveReads == 1 and #rows[accountKey].receipts == Purchases.RECEIPTS_KEPT)
	local wins = WinsStore.new(ranks, index)
	local rankDown = true
	local services = {
		now = function() return wall end,
		wall_time = function() return now end,
		spawn = function(callback) callback() end,
		wait = function(dt) wall += dt end,
		save = Purchases.record_match_reward,
		sync_win = function(id, sequence)
			if rankDown then return false end
			return wins:sync(id, sequence)
		end,
	}
	local writer = Rewards.writer(services)
	writer:enqueue(userId, "smoke-match", { total = 105 }, true)
	assert(not writer:flush(0.5) and rows[accountKey].stars == 405 and rows[accountKey].match_win_sequence == 1)
	rankDown = false
	local freshWriter = Rewards.writer(services)
	freshWriter:restore(userId, rows[accountKey].match_win_sequence)
	freshWriter:enqueue(userId, "smoke-match", { total = 105 }, true)
	assert(freshWriter:flush(2) and ranks:GetAsync(tostring(userId)).wins == 1 and rows[accountKey].stars == 405)
	assert(rows[accountKey].unlocks.mega and rows[accountKey].credits.takeover == 1)
	copy:Destroy()
	print("PASS native match rewards and receipt archive smoke")
end
