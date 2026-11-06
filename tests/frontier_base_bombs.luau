--!nocheck
local F = require("./simsys_fixture")
local Arsenal = require("../src/shared/Data/Arsenal")
for index, kind in Arsenal.BASE_BOMBS do
	local sim = F.new_sim(100 + index)
	local a = F.owner(sim, "Alpha", F.Defs.KIND_HUMAN, 100000000, 100000)
	local b = F.owner(sim, "Bravo", F.Defs.KIND_HUMAN, 100000000, 400000)
	F.claim(sim, a, 690, 100, 12)
	F.claim(sim, b, 716, 100, 14)
	local own, enemy = F.tile(690,100), F.tile(716,100)
	sim:add_struct(F.Defs.S_SILO,a,own)
	F.advance(sim,400)
	sim:construction_tick()
	sim:set_unlocks(a,0)
	assert(sim:launch_nuke(a,kind,enemy), kind .. " must launch without a purchased account unlock")
	assert(#sim.nukes == 1)
	print("PASS base bomb",kind)
end
