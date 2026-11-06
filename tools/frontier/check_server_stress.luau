-- Headless server simulation stress: 50 AI commander slots, not connected clients or measured client FPS.

assert(game.GameId==10774039150 and game.PlaceId==129521354706128)
local Shared=game:GetService("ReplicatedStorage").Airfront
local Core=Shared.Core
local Sim=require(Core.Sim);local State=require(Core.GameState);local World=require(Core.WorldMap);local Defs=require(Core.Defs)
local map=World.get("world")
local start=os.clock()
local sim=Sim.new(map,{seed=1106,difficulty=0,max_humans=50,spawn_ticks=50,public_commander_ai=true})
local Roster=require(Shared.Data.BotRoster)
local names,skills={},{}
for i=1,50 do local bot=Roster.profile(i);names[i],skills[i]=bot.name,bot.skill end
local bots=sim:add_bot_players(50,names,skills)
assert(#bots==50)
local state=State.new(map);state:load_snapshot(sim:snapshot())
local setup_ms=(os.clock()-start)*1000
local times,apply={},{}
local lastYield=os.clock();local maxUnits,maxStructs=0,0
for i=1,1800 do
 local t=os.clock();local d=sim:step();local t1=os.clock();state:apply_delta(d)
 times[#times+1]=(t1-t)*1000;apply[#apply+1]=(os.clock()-t1)*1000
 maxUnits=math.max(maxUnits,sim:unit_total());maxStructs=math.max(maxStructs,sim:struct_total())
 if sim.phase==Defs.PHASE_OVER then break end
 if os.clock()-lastYield>.02 then task.wait();lastYield=os.clock() end
end
local function stats(a)
 table.sort(a);local sum=0;for _,v in a do sum+=v end
 return {n=#a,p95_ms=a[math.ceil(#a*.95)],p99_ms=a[math.ceil(#a*.99)],max_ms=a[#a],mean_ms=sum/#a}
end
local alive,claimed=0,0
for id=1,sim.owner_total do
 if sim.o_alive[id]==1 then alive+=1;claimed+=sim.o_tiles[id] end
end
assert(#times==1800 or sim.phase==Defs.PHASE_OVER)
return {native_server_simulation=true,real_connected_clients=0,setup_ms=setup_ms,ai_commander_slots=50,nations_including_tribes=sim.owner_total,alive=alive,claimed=claimed,map_land=map.land_count,max_units=maxUnits,max_structures=maxStructs,step=stats(times),apply_delta_in_server_engine=stats(apply)}
