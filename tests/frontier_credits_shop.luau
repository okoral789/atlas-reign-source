--!nocheck
require("./prelude")
local Purchases = require("../src/server/Purchases")
local Shop = require("../src/shared/Data/Shop")
local Arsenal = require("../src/shared/Data/Arsenal")
local Style = require("../src/shared/Data/ProfileStyle")
local Products = require("../src/shared/Data/Products")
local Cosmetics = require("../src/shared/Data/Cosmetics")
local rows = {u42={stars=60000, stars_earned=70000, owned={shop_cat=true}, equipped={flag="shop_cat"}, unlocks={airfield=true,emp=true}}}
local player = {UserId=42}
local down,retry=false,false
local store={}
function store:GetAsync(key) return rows[key] end
function store:UpdateAsync(key,fn)
 if down then error("store outage") end
 if retry then fn(rows[key]) end
 local result=fn(rows[key]); if result ~= nil then rows[key]=result end
 return result
end
Purchases.reset()
Purchases.configure({datastore=store,players={GetPlayerByUserId=function(_,id) return if id==42 then player else nil end}})
Purchases.load(player)
assert(Purchases.stars(player)==60000 and rows.u42.unlocks.airfield and not Purchases.has_unlock(player,"airfield"),"preserve existing wallet and unlocks")
assert(Purchases.inventory(player).equipped.flag=="shop_cat","preserve existing cosmetic")
assert(#Arsenal.BASE_BOMBS==3 and Arsenal.BASE_BOMBS[1]=="atom" and Arsenal.BASE_BOMBS[2]=="hydrogen" and Arsenal.BASE_BOMBS[3]=="mirv")
for _,kind in Arsenal.BASE_BOMBS do assert(Arsenal.item_for(kind)==nil,"base bombs never require an account unlock") end
for _,it in Arsenal.DISPLAY_ITEMS do assert(not Arsenal.FREE_UNLOCKS[it.key] and it.stars>0) end
assert(not Purchases.has_unlock(player,"reinforce"),"advanced bombs start locked")
retry=true
assert(Purchases.buy_unlock(player,"reinforce"))
assert(rows.u42.stars==20000 and rows.u42.stars_earned==70000 and Purchases.has_unlock(player,"reinforce"),"one atomic unlock debit despite retry")
assert(not Purchases.buy_unlock(player,"reinforce") and rows.u42.stars==20000,"owned unlock cannot be charged again")
assert(Purchases.buy_unlock(player,"mega") and Purchases.has_unlock(player,"mega") and rows.u42.stars==0,"bonus bomb unlock spends its exact price once")
assert(not Purchases.buy_unlock(player,"mega") and rows.u42.stars==0,"bonus bomb double-click never charges again")
assert(not Purchases.buy_unlock(player,"artillery"),"server rejects insufficient funds")
assert(not Purchases.buy_unlock(player,{}) and not Purchases.buy_unlock(player,"bogus"),"validate client input")
rows.u42.stars=900000
local chosen=Shop.daily(Shop.day(1793404800))[1]
local ok,why=Purchases.buy_flag(player,chosen)
assert(not ok and why=="Robux only" and rows.u42.stars==900000,"cosmetics never consume Credits, even for a rich or old client")
assert(not rows.u42.owned[Shop.item_id(chosen)] or chosen=="cat")
down=true
assert(not Purchases.buy_unlock(player,"scatter") and rows.u42.stars==900000,"store failure cannot spend or unlock")
down=false
local OwnProducts=require("../src/shared/Data/FrontierProducts")
Products.unlock_scatter.id=OwnProducts.unlock_scatter
assert(Purchases.process_receipt({PlayerId=42,ProductId=OwnProducts.unlock_scatter,PurchaseId="unlock1"})=="granted")
assert(rows.u42.unlocks.scatter and Purchases.has_unlock(player,"scatter"))
local balance=Purchases.stars(player)
assert(Purchases.process_receipt({PlayerId=42,ProductId=OwnProducts.unlock_scatter,PurchaseId="unlock1"})=="granted")
assert(Purchases.stars(player)==balance,"Robux receipt retries must not compensate twice")
assert(Purchases.has_profile_color(player,1) and not Purchases.has_profile_color(player,2),"default color free; premium color requires ownership")
local color_id=Style.item_id(2)
Products[color_id].id=OwnProducts[color_id]
assert(Purchases.process_receipt({PlayerId=42,ProductId=OwnProducts[color_id],PurchaseId="color1"})=="granted")
assert(Purchases.has_profile_color(player,2) and rows.u42.owned[color_id])
assert(not Purchases.has_profile_color({UserId=99},2) and not Purchases.has_profile_color(player,0/0))
assert(Purchases.inventory(player).equipped.flag=="shop_cat","profile color never overwrites map flag")
assert(Purchases.process_receipt({PlayerId=42,ProductId=OwnProducts[color_id],PurchaseId="color1"})=="granted" and Purchases.stars(player)==balance)
assert(Purchases.grant(42,"profilecolor:99","invalid") == "not_processed")
for _,entry in Cosmetics.outcomes({}) do assert(entry.item.kind~="profile_color","paid colors stay out of random crates") end
local count=0
for key,id in OwnProducts do assert(Products[key] and id>0); count+=1 end
assert(count==80)
local before=Purchases.stars(player)
local repair=Arsenal.item("fleet_repair")
assert(Purchases.buy_unlock(player,repair.key) and Purchases.stars(player)==before-repair.stars)
assert(not Purchases.buy_unlock(player,repair.key) and Purchases.stars(player)==before-repair.stars,"support unlock is charged exactly once")

local buyer=1000
local function verify_receipt(key, field, item)
 buyer+=1
 local id=assert(OwnProducts[key],key)
 Products[key].id=id
 local receipt={PlayerId=buyer,ProductId=id,PurchaseId="sale-"..key}
 assert(Purchases.process_receipt(receipt)=="granted",key)
 local record=rows["u"..buyer]
 assert(record[field][item]==true,"wrong entitlement for "..key)
 local credits=record.stars
 assert(Purchases.process_receipt(receipt)=="granted" and rows["u"..buyer].stars==credits, "replayed "..key)
end
for _,flag in Shop.flags() do verify_receipt(Shop.item_id(flag.key),"owned",Shop.item_id(flag.key)) end
for _,index in Style.shop_indices() do local id=Style.item_id(index);verify_receipt(id,"owned",id) end
for _,style in require("../src/shared/Data/FleetStyles") do verify_receipt("skin_"..style.id,"owned",style.id) end
for _,item in Arsenal.DISPLAY_ITEMS do verify_receipt(item.product,"unlocks",item.key) end
assert(buyer==1071)

assert(rows.u42.unlocks.emp and not Purchases.has_unlock(player,"emp") and not Purchases.buy_unlock(player,"emp"))
Products.unlock_emp.id=OwnProducts.unlock_emp
local oldEmp={PlayerId=42,ProductId=OwnProducts.unlock_emp,PurchaseId="legacy-emp",CurrencySpent=99}
local afterRepair=Purchases.stars(player)
down=true
assert(Purchases.process_receipt(oldEmp)=="not_processed" and Purchases.stars(player)==afterRepair)
down=false
assert(Purchases.process_receipt(oldEmp)=="granted" and Purchases.process_receipt(oldEmp)=="granted")
assert(Purchases.stars(player)==afterRepair+49500 and rows.u42.unlocks.emp and not Purchases.has_unlock(player,"emp"))
local legacy = {UserId=99}
assert(Purchases.keep_legacy_color(legacy,3) and Purchases.has_profile_color(legacy,3))
assert(not rows.u99.paid and #rows.u99.receipts==0, "keeping an old selected color must not create a payment")
assert(not Purchases.keep_legacy_color(legacy,99) and not Purchases.keep_legacy_color(legacy,1))
Purchases.release(player)
Purchases.load(player)
assert(Purchases.has_profile_color(player,2) and Purchases.has_unlock(player,"reinforce") and Purchases.has_unlock(player,"mega") and Purchases.has_unlock(player,"scatter"))
assert(Purchases.inventory(player).equipped.flag=="shop_cat", "unlock and cosmetic ownership survives rejoining")
print("PASS economy: 3 base bombs; Credits/Robux advanced unlocks; Robux-only flags/colors; preserved ownership; atomic debits and receipt retries")
