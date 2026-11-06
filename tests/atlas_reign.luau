--!nocheck
require("./prelude")
local Wins=require("../src/server/WinsStore")
local Reports=require("../src/server/PlayerReports")
local Arsenal=require("../src/shared/Data/Arsenal")
local Cosmetics=require("../src/shared/Data/Cosmetics")
local Purchases=require("../src/server/Purchases")
local Products=require("../src/shared/Data/Products")
local styles=require("../src/shared/Data/FleetStyles")
local records,index=Wins.memory();local wins=Wins.new(records,index)
for id=1,210 do
 records:UpdateAsync(tostring(id),function() return {wins=if id<=103 then 9 elseif id<=205 then 5 else 2} end)
 index:UpdateAsync(tostring(id),function() return if id<=103 then 9 elseif id<=205 then 5 else 2 end)
end
assert(wins:rank(1).rank==1 and wins:rank(104).rank==104 and wins:rank(210).rank==206,"pagination and tied scores")
assert(wins:rank(999).rank==nil and wins:rank(999).wins==0)
assert(#select(2,wins:top())==50)
for id=211,2600 do index:UpdateAsync(tostring(id),function() return 99 end) end
local far=wins:rank(210);assert(far.rank==2501 and far.exact==false,"bounded rank must visibly say 2501+")
local now,seq,mode=100,0,"ffa"
local store=select(1,Wins.memory());local author={UserId=1}
local reports=Reports.new(store,{now=function() return now end,id=function() seq+=1;return "report-"..seq end,context=function(_,target) return if target==2 or target==3 then {match_id="match-a",mode=mode} else nil end})
assert(not reports:submit(author,1,"teaming").ok and not reports:submit(author,99,"teaming").ok)
mode="team";assert(not reports:submit(author,2,"teaming").ok);mode="ffa"
assert(reports:submit(author,2,"teaming").ok and #reports:inbox().rows==1)
assert(reports:submit(author,2,"teaming").ok and #reports:inbox().rows==1,"duplicate reports are idempotent")
assert(not reports:submit(author,3,"teaming").ok,"cooldown")
now+=31;assert(reports:submit(author,3,"exploiting").ok)
assert(reports:review("report-1").ok and reports:inbox().rows[2].status=="reviewed")
assert(not reports:review({}).ok)
local fail=true;local proxy={}
function proxy:GetAsync(k) return store:GetAsync(k) end
function proxy:UpdateAsync(k,fn) if fail and k=="recent" then error("outage after saved record") end;return store:UpdateAsync(k,fn) end
local retry=Reports.new(proxy,{now=function() return 500 end,id=function() seq+=1;return "retry-"..seq end,context=function() return {match_id="retry",mode="ffa"} end})
assert(not retry:submit(author,2,"teaming").ok);fail=false
assert(retry:submit(author,2,"teaming").ok and seq==3,"outage retry reuses record ID")
local display_keys = {}
for _, item in Arsenal.DISPLAY_ITEMS do table.insert(display_keys, item.key) end
assert(table.concat(display_keys, ",") == "mega,scatter,reinforce,fleet_repair", "only active equipment in Armory display order")
assert(table.concat(Arsenal.BASE_BOMBS, ",") == "atom,hydrogen,mirv", "all three standard bombs remain included")
assert(Arsenal.mask({mega=true,airfield=true})==Arsenal.item("mega").bit and Arsenal.mask({reinforce=true})>0)
local rows={};local ps={}
function ps:GetAsync(k) return rows[k] end
function ps:UpdateAsync(k,fn) local v=fn(rows[k]);if v then rows[k]=v end;return rows[k] end
local player={UserId=77}
Purchases.reset();Purchases.configure({datastore=ps,players={GetPlayerByUserId=function() return player end}});Purchases.load(player)
for i,style in styles do
 local key="skin_"..style.id;Products[key].id=100+i
 assert(Purchases.process_receipt({PlayerId=77,ProductId=100+i,PurchaseId="fleet"..i})=="granted")
 assert(rows.u77.owned[style.id] and rows.u77.equipped.skin==style.id)
 local balance=rows.u77.stars
 assert(Purchases.process_receipt({PlayerId=77,ProductId=100+i,PurchaseId="fleet"..i})=="granted" and rows.u77.stars==balance)
 for _,it in Cosmetics.all() do assert(it.id~=style.id,"paid livery stays out of random cases") end
end
assert(Purchases.grant(77,"skin:not-a-style","bad")=="not_processed")
assert(not Purchases.buy_unlock(player,"mega") and not Purchases.has_unlock(player,"mega"))
print("PASS Atlas: ranked ties and pages; bounded global rank; report validation, deduplication and recovery; permanent cosmetic receipt idempotence; retired units")
