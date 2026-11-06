--!nocheck
require("./prelude")
local Release=require("../src/shared/Data/ReleaseConfig")
Release.CHANNEL="private"
local Test=require("../src/shared/Data/PrivateTest")
local Purchases=require("../src/server/Purchases")
local Cosmetics=require("../src/shared/Data/Cosmetics")
assert(Test.allowed(Test.OWNER,Test.OWNER,Test.UNIVERSE))
assert(not Test.allowed(7,Test.OWNER,Test.UNIVERSE) and not Test.allowed(Test.OWNER,7,Test.UNIVERSE) and not Test.allowed(Test.OWNER,Test.OWNER,7))
for _,id in Test.COSMETICS do assert(Cosmetics.may_own(id,Test.OWNER),id) end
local rows={u8318659852={stars=1234,owned={shop_cat=true},equipped={flag="shop_cat"},receipts={"real-receipt"}}}
local store={GetAsync=function(_,k) return rows[k] end,UpdateAsync=function(_,k,fn) local value=fn(rows[k]);if value then rows[k]=value end;return rows[k] end}
local player={UserId=Test.OWNER}
Purchases.reset();Purchases.configure({datastore=store});Purchases.load(player)
assert(Purchases.grant_test_cosmetics(player))
for _,id in Test.COSMETICS do assert(rows.u8318659852.owned[id],id) end
assert(rows.u8318659852.stars==1001234 and rows.u8318659852.equipped.flag=="shop_cat" and #rows.u8318659852.receipts==1)
assert(Purchases.grant_test_cosmetics(player) and rows.u8318659852.stars==1001234 and #rows.u8318659852.receipts==1,"repeat login grants no duplicate compensation or fake receipt")
assert(not Purchases.grant_test_cosmetics({UserId=7}),"other accounts cannot receive owner grants")
for _,item in Cosmetics.shop_items() do assert(rows.u8318659852.owned[item.id],item.id) end
for _,item in require("../src/shared/Data/Arsenal").DISPLAY_ITEMS do assert(rows.u8318659852.unlocks[item.key]) end
for _,row in Test.LADDER do assert(row.wins>0 and row.user_id==nil,"demo entries are not real accounts") end
print("PASS private preview: owner-only full catalogue, active arsenal, one-time 1M Credits, unchanged equipment/receipts, idempotence and isolated ranking")
