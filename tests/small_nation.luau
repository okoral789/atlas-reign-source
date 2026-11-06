local F=require("./simsys_fixture")
local D=F.Defs
local function scenario(troops)
 local sim=F.new_sim(44)
 local a=F.owner(sim,"Attacker",D.KIND_HUMAN,1000000,3000000)
 local b=F.owner(sim,"Defender",D.KIND_HUMAN,1000000,1000000)
 F.claim(sim,a,690,100,12);F.claim(sim,b,690,100,1.5)
 assert(sim.o_tiles[b]>1 and sim.o_tiles[b]<100)
 local before=sim.o_tiles[b]
 local attack=sim:start_attack(a,b,troops,-1)
 assert(attack)
 for _=1,30 do F.advance(sim,1);sim:attacks_tick() end
 return sim,b,before
end
local weak,b,before=scenario(1000)
assert(weak.o_tiles[b]>0 and weak.o_tiles[b]>=before-2,"a tiny attack cannot annex a much stronger small human country")
local strong,c=scenario(3000000)
assert(strong.o_tiles[c]==0,"a surviving attack stronger than the home army can annex a small country")
print("PASS small human nations: weak invasions cannot annex a stronger army; strong invasions still can")
