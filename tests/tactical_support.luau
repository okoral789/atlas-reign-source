require("./prelude")
local F=require("./simsys_fixture")
local D,R=F.Defs,F.Rules
local Protocol=require("../src/shared/Net/Protocol")
local GameState=require("../src/shared/Core/GameState")
local Unit=require("../src/shared/Core/SimStructures").Unit
local sim=F.new_sim(919)
local a=F.owner(sim,"Commander",D.KIND_HUMAN,10000000)
local b=F.owner(sim,"Enemy",D.KIND_HUMAN,10000000)
local home=F.claim(sim,a,690,100,12)
local target=F.claim(sim,b,716,100,14)
sim:add_struct(D.S_SILO,a,home)
local sam=sim:add_struct(D.S_SAM,b,target)
F.advance(sim,500);sim:construction_tick();sam.shots={}
local gold=sim.o_gold[a]
sim:set_unlocks(a,D.UNLOCK.emp+D.UNLOCK.fleet_repair)
assert(R.SUPPORT.emp==nil and not sim:call_support(a,"emp",target),"legacy unlock cannot use EMP")
local legacy=Protocol.decode_intent(Protocol.encode_intent({type="emp",tile=target}))
assert(legacy.type=="emp","retired intent keeps its wire number")
sim:_apply_intent(a,legacy)
assert(sim.o_gold[a]==gold and #sim.support_effects==0 and not sam.jammed_until)
assert(sim:ready_missiles(sam,R.SAM_COOLDOWN_TICKS)>0,"the retired order cannot jam a SAM")
F.clear(sim)
local state=GameState.new(F.map)
state:load_snapshot(Protocol.decode_snapshot(Protocol.encode_snapshot(sim:snapshot())))
for _,tile in {-1,F.N,0/0,math.huge,target+.5} do assert(not sim:call_support(a,"fleet_repair",tile)) end
assert(sim.o_gold[a]==gold and #sim.support_effects==0,"invalid targets cannot spend or queue effects")
local coast=F.map:coast_tile(100)
local sea=-1
for dy=-3,3 do for dx=-3,3 do local t=coast+dy*F.W+dx;if t>=0 and t<F.N and F.map:is_water(t) then sea=t end end end
assert(sea>=0)
local port=sim:add_struct(D.S_PORT,a,coast)
port.active_tick=sim.tick;port.active=true
local function ship(owner,hp,at,kind)
 local u=Unit.new();u.kind=kind or D.U_WARSHIP;u.owner=owner;u.path={at};u.start_tick=sim.tick;u.end_tick=sim.tick;u.tpt=100;u.max_hp=1000;u.hp=hp
 sim:add_unit(u);return u
end
local damaged=ship(a,400,sea)
local capped=ship(a,950,sea)
local enemy=ship(b,400,sea)
local trade=ship(a,400,sea,D.U_TRADE)
local sunk=ship(a,0,sea)
gold=sim.o_gold[a]
sim:_apply_intent(a,Protocol.decode_intent(Protocol.encode_intent({type="fleet_repair",tile=sea})))
assert(damaged.hp==700 and capped.hp==1000 and damaged.max_hp==1000)
assert(enemy.hp==400 and trade.hp==400 and sunk.hp==0,"only living damaged own warships are repaired")
assert(sim.o_gold[a]==gold-R.SUPPORT.fleet_repair.cost)
assert(not sim:call_support(a,"fleet_repair",sea) and sim.o_gold[a]==gold-R.SUPPORT.fleet_repair.cost)
state:apply_delta(Protocol.decode_delta(Protocol.encode_delta({t=sim.tick,ev=sim.d_ev},nil,F.W)))
assert(state.units[damaged.uid].hp==700 and state.support_ready.fleet_repair[a]==sim.support_ready.fleet_repair[a])
F.advance(sim,450);damaged.hp=1000
assert(not sim:call_support(a,"fleet_repair",sea),"full fleet costs nothing")
damaged.hp=500;sim.o_gold[a]=0
assert(not sim:call_support(a,"fleet_repair",sea) and damaged.hp==500,"insufficient gold cannot repair")
assert(R.for_k(2).SUPPORT.fleet_repair.radius==R.SUPPORT.fleet_repair.radius/2
 and R.for_k(2).SUPPORT.fleet_repair.cooldown==450,"map scale affects distances only")
print("PASS tactical support: EMP rejected on the server, capped repair, costs, cooldown, wire and resync")
