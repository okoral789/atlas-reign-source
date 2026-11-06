-- Isolated local sandbox tools. No account currency, receipts or ranking writes.
local Defs=require("./Defs")
local Tools={GOLD=1000000000,TROOPS=5000000,CAP=10000000}
function Tools.refill(sim,id)
 if sim.testing_owner~=id or sim.o_kind[id]~=Defs.KIND_HUMAN or sim.o_alive[id]~=1 or sim.o_spawned[id]~=1 then return false end
 sim.o_gold[id]=Tools.GOLD;sim.o_troops[id]=Tools.TROOPS;sim.o_cap[id]=Tools.CAP;sim._force_stats=true
 return true
end
function Tools.cooldowns(sim,id)
 if sim.testing_owner~=id then return false end
 for _,s in sim.struct_list do
  if s.owner==id and not s.dead then s.shots={};s.next_fire=sim.tick end
 end
 for _,ready in sim.support_ready do ready[id]=0 end
 sim.o_reinforce_tick[id]=-100000;sim._force_stats=true
 return true
end
function Tools.build(sim,id)
 if sim.testing_owner~=id then return false end
 for _,s in sim.building do if s.owner==id and not s.dead then s.active_tick=sim.tick end end
 sim:construction_tick();sim._force_stats=true;return true
end
return Tools
