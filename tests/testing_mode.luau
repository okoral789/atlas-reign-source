require("./prelude")
local Gate=require("../src/server/TestingAccess")
local T=require("../src/shared/Data/PrivateTest")
local Tools=require("../src/shared/Core/Testing")
local F=require("./simsys_fixture")
local Session=require("../src/client/Session")
local gate=Gate.new(T.OWNER,T.UNIVERSE);local player={UserId=T.OWNER};local stranger={UserId=7}
for _,bad in {"true",{},1} do assert(not gate:request(player,bad).ok) end
assert(not gate:request(stranger,true).ok and not gate:active(stranger))
assert(not Gate.new(7,T.UNIVERSE):request(player,true).ok)
assert(gate:request(player,true).active and gate:active(player))
assert(gate:request(player,false).ok and not gate:active(player));gate:request(player,true);gate:release(player);assert(not gate:active(player))
local sim=F.new_sim(123)
local a=F.owner(sim,"Owner",F.Defs.KIND_HUMAN,0)
local b=F.owner(sim,"Other",F.Defs.KIND_HUMAN,0)
local home=F.claim(sim,a,690,100,10)
assert(not Tools.refill(sim,a),"no simulation is a sandbox by default")
sim.testing_owner=a
assert(Tools.refill(sim,a) and sim.o_troops[a]==5000000 and sim.o_gold[a]==1000000000)
assert(not Tools.refill(sim,b) and sim.o_gold[b]==0,"only the local testing owner is boosted")
require("../src/shared/Core/Sim")._economy_tick(sim)
assert(sim.o_cap[a]==Tools.CAP and sim.o_cap[b]~=Tools.CAP,"sandbox capacity never leaks to another nation")
local silo=sim:add_struct(F.Defs.S_SILO,a,home);local enemy=sim:add_struct(F.Defs.S_SILO,b,home+1)
assert(Tools.build(sim,a) and silo.active and not enemy.active,"finish only own construction")
silo.shots={sim.tick};enemy.shots={sim.tick};sim.support_ready.fleet_repair[a]=100000;sim.o_reinforce_tick[a]=sim.tick
assert(Tools.cooldowns(sim,a) and #silo.shots==0 and #enemy.shots==1 and sim.support_ready.fleet_repair[a]==0 and sim:reinforce_wait(a)==0)
local sent=0
Session._solo_report({testing=true,env={net={send=function() sent+=1 end}}},true)
assert(sent==0,"sandbox never submits a solo reward report")
local started=false
local session=setmetatable({mode=0,env={testing=function() return {ok=false} end},is_building=function() return false end,start_solo=function() started=true end},Session)
assert(not session:start_testing(1) and not started,"permission denial cannot start testing")
session.env.testing=function(on) assert(on);return {ok=true,active=true} end
session.start_solo=function(self,_,_,opts) assert(opts.testing and self._testing_ticket);started=true end
assert(session:start_testing(1) and started)
-- Real solo lifecycle: permission, spawning, initial resources, tool resync and multiplayer exit.
local core={}
for _,name in Session.WARM_MODULES do core[name]=require("../src/shared/Core/"..name) end
core.Testing=Tools
local reports,ended=0,false
local live=Session.new({now=os.clock,display_name=function() return "Owner" end,user_id=function() return T.OWNER end,
 require_core=function(name) return core[name] or require("../src/shared/Core/"..name) end,
 testing=function(on) ended=not on;return gate:request(player,on) end,
 net={connected=true,listen=function() end,send=function(op) if op==require("../src/shared/Net/Protocol").OP.SOLO_RESULT then reports+=1 end end}})
live.threaded=false;assert(live:start_testing(1,"world") and live.testing and not live._tracker)
local sim2=live._sim;local id=live.state.local_owner;local spawn
for i=0,F.N-1 do if F.map:is_land(i) and buffer.readi32(sim2.owner,i*4)==0 and sim2:_intent_spawn(id,i) then spawn=i;break end end
assert(spawn)
for _=1,15 do live:process(.1) end
assert(sim2.o_troops[id]>=Tools.TROOPS and sim2.o_gold[id]>=Tools.GOLD,"real solo spawn receives the testing grant")
sim2.o_gold[id]=1;assert(live:testing_action("refill") and live.state.owners[id].gold==Tools.GOLD,"tool resync reaches the real HUD mirror")
live:_set_mode(2);assert(not live.testing and ended and not gate:active(player) and reports==0)
print("PASS testing: owner authorization, isolated resources, own construction/cooldowns, denial and no reward reports")
