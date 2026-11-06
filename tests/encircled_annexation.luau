local F = require("./simsys_fixture")
local Defs = F.Defs
local Protocol = require("../src/shared/Net/Protocol")

local function pocket(withRemote: boolean)
	local sim = F.new_sim(53)
	local attacker = F.owner(sim, "Attacker", Defs.KIND_HUMAN, 100, 0)
	local victim = F.owner(sim, "Defender", Defs.KIND_HUMAN, 2000, 1000000)
	local center = F.tile(690, 100)
	for y = -7, 7 do
		for x = -7, 7 do
			local tile = center + x + y * F.W
			assert(F.map:is_contestable(tile))
			local border = math.abs(x) == 7 or math.abs(y) == 7
			sim:set_owner(tile, if border then attacker else victim)
		end
	end
	local remote = center + 15
	if withRemote then
		assert(F.map:is_contestable(remote))
		sim:set_owner(remote, victim)
	end
	return sim, attacker, victim, center, remote
end

do
	local sim, attacker, victim, tile, remote = pocket(true)
	local gap = tile - 7 * F.W
	local third = F.owner(sim, "Third", Defs.KIND_HUMAN, 0, 0)
	for _, owner in { 0, third } do
		sim:set_owner(gap, owner)
		assert(not sim:intent_attack(attacker, tile, 0), "wilderness or a third nation breaks the ring")
		assert(sim.o_tiles[victim] == 170 and sim.o_troops[attacker] == 0)
	end
	sim:set_owner(gap, attacker)
	sim.o_team[attacker], sim.o_team[victim] = 1, 1
	assert(not sim:intent_attack(attacker, tile, 0), "team members cannot be annexed")
	sim.o_team[attacker], sim.o_team[victim] = 0, 0
	sim.o_troops[attacker] = 5000
	assert(sim:intent_attack(attacker, tile, 0.75), "a normal click also annexes a closed ring")
	assert(sim.o_troops[attacker] == 5000 and sim:attack_between(attacker, victim) == nil)
	assert(sim.o_tiles[victim] == 1 and buffer.readi32(sim.owner, remote * 4) == victim, "remote land is preserved")
	assert(sim.o_troops[victim] == 1000000 and sim.o_gold[victim] == 2000, "a surviving nation keeps its troops and gold")
end

do
	local sim, attacker, victim, tile = pocket(false)
	local intent = assert(Protocol.decode_intent(Protocol.encode_intent({ type = "attack", tile = tile, ratio = 0 })))
	assert(intent.ratio == 0, "the zero-troop annex order survives the network codec")
	local gap = tile - 7 * F.W
	sim:set_owner(gap, 0)
	sim.o_troops[attacker] = 5000
	sim:_apply_intent(attacker, intent)
	assert(sim.o_tiles[victim] == 169 and sim.o_troops[attacker] == 5000, "a stale annex never spends troops")
	sim:set_owner(gap, attacker)
	sim.o_troops[attacker] = 0
	sim:_apply_intent(attacker, intent)
	assert(sim.o_tiles[victim] == 0 and sim.o_troops[attacker] == 0, "a fully surrounded country falls even with no troops")
	sim:_process_eliminations()
	assert(sim.o_alive[victim] == 0 and sim.o_killer[victim] == attacker)
	assert(sim.o_gold[attacker] == 1100 and #F.events(sim, F.Ev.CONQUEST) == 1)
	local boat = assert(Protocol.decode_intent(Protocol.encode_intent({ type = "boat", tile = tile, ratio = 0 })))
	assert(boat.ratio == 0.01, "the annex sentinel applies only to attack orders")
end

do
	local sim = F.new_sim(54)
	local attacker = F.owner(sim, "Attacker", Defs.KIND_HUMAN, 0, 40000)
	local victim = F.owner(sim, "Defender", Defs.KIND_HUMAN, 0, 20000)
	local tile = F.tile(690, 100)
	for y = 0, 10 do
		for x = 0, 10 do
			sim:set_owner(tile + x + y * F.W, victim)
		end
	end
	sim:set_owner(tile - 1, attacker)
	sim.rng.randi = function() return 0 end
	assert(sim:intent_attack(attacker, tile, 0.5))
	local a = assert(sim:attack_between(attacker, victim))
	assert(a.troops == 20000 and a.front == 1 and sim.o_troops[attacker] == 20000)
	local mag = F.Rules.ATTACK_MAG[buffer.readu8(sim.terr, tile)]
	local defenderDensity = 20000 / 121
	local expectedLoss = mag * (0.463 * F.Rules.large_territory_bonus(1, 0.7) * F.Rules.large_territory_bonus(121, 0.3) + 0.0039 * defenderDensity)
	F.advance(sim, 1)
	sim:attacks_tick()
	assert(sim.o_tiles[victim] == 120 and sim.o_troops[victim] == 20000 - math.floor(defenderDensity))
	assert(math.abs(a.troops - (20000 - expectedLoss)) < 0.000001, "equal armies use the ordinary RoWorld per-tile formula")
end

print("encircled_annexation: all passed")
