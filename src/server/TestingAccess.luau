-- Owner-only sandbox handshake; never grants resources to a multiplayer simulation.
local Test=if typeof(game)=="Instance" then require(game:GetService("ReplicatedStorage").Airfront.Data.PrivateTest) else require("../shared/Data/PrivateTest")
local Gate={};Gate.__index=Gate
function Gate.new(creator,universe) return setmetatable({creator=creator,universe=universe,players={}},Gate) end
function Gate.request(self,player,on)
 if type(on)~="boolean" or not Test.allowed(player.UserId,self.creator,self.universe) then return {ok=false} end
 self.players[player]=if on then true else nil
 return {ok=true,active=on}
end
function Gate.active(self,player) return self.players[player]==true end
function Gate.release(self,player) self.players[player]=nil end
return Gate
