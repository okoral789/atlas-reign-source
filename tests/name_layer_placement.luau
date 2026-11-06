local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Defs = require("../src/shared/Core/Defs")
local Coop = require("../src/shared/Net/Coop")

-- Run the production placement methods without constructing Roblox GUI instances.
local modules = {}
function modules:WaitForChild(name)
	return if name == "Defs" or name == "Coop" then name else self
end
local loadLayer = luau.load(fs.readFile("src/client/Map/NameLayer.luau"))
setfenv(loadLayer, setmetatable({
	game = { GetService = function() return modules end }, script = { Parent = modules },
	Font = { fromId = function() end }, Enum = { FontWeight = {} },
	require = function(key) return if key == "Defs" then Defs elseif key == "Coop" then Coop else {} end,
}, { __index = getfenv() }))
local NameLayer = loadLayer()
NameLayer.BUDGET_S = 0 -- Every explicit checkpoint yields, independent of the machine's speed.

local side, total = 16, 6
local width = side * total
local owners, seeds = {}, {}
local owner = buffer.create(width * side * 4)
for id = 1, total do
	local start = (id - 1) * side
	owners[id] = { name = "Nation " .. id, tiles = side * side, spawn_tile = start }
	seeds[id] = start
	for y = 0, side - 1 do
		for x = start, start + side - 1 do buffer.writei32(owner, (y * width + x) * 4, id) end
	end
end
local state = { owners = owners, owner = owner, flags = buffer.create(width * side), phase = Defs.PHASE_PLAYING,
	map = { W = width, H = side, k_lin = 1 }, tick = 0, local_owner = 1 }
function state:get_owner(id) return owners[id] end
function state:label_tile(id) return seeds[id] end
local layer = setmetatable({ view = {}, _plates = {}, _targets = {}, _queue = {}, _crown = {},
	_visit = buffer.create(0), _visit_gen = 0 }, NameLayer)
layer:bind(state)
layer:_placement_step(state)
local victim = assert(layer._queue[1])
assert(layer._job and layer._targets[victim], "owner waits in the job with its provisional capital")
local capital = owners[victim].spawn_tile
buffer.writei32(owner, capital * 4, if victim == 1 then 2 else 1)
owners[victim].tiles -= 1
seeds[victim] = capital + width + 1

local frames = 0
while layer._job do
	state.tick += NameLayer.REPLACE_TICKS
	layer:_placement_step(state)
	frames += 1
	assert(frames < 160, "a refresh must not refill the unfinished queue and starve owners")
end
assert(#layer._queue == 0)
for id = 1, total do
	local target, exact = layer._targets[id], layer:_place(state, id)
	assert(target and exact and target[1] == exact[1] and target[2] == exact[2] and target[3] == exact[3],
		"owner " .. id .. " did not receive its accurate post-capture target")
end
assert(math.floor(layer._targets[victim][1]) ~= capital % width)
print("PASS name placement: capture of a provisional capital, surviving owner and full queue despite tick advances")
