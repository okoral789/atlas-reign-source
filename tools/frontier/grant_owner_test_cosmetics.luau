-- Explicit owner-requested free test inventory; never writes wins or fake purchase receipts.
local Test=require(game:GetService("ReplicatedStorage").Airfront.Data.PrivateTest)
assert(Test.allowed(game.CreatorId,game.CreatorId,game.GameId) and game.PlaceId==129521354706128)
local Purchases=require(game:GetService("ServerScriptService").AirfrontServer.Purchases)
local store=game:GetService("DataStoreService"):GetDataStore(Purchases.STORE)
local player={UserId=Test.OWNER}
Purchases.configure({datastore=store})
Purchases.load(player)
local before=Purchases.inventory(player)
assert(Purchases.grant_test_cosmetics(player),"Could not save owner test inventory")
local after=Purchases.inventory(player)
for _,id in Test.COSMETICS do assert(table.find(after.owned,id),"Missing test cosmetic: "..id) end
local C=require(game:GetService("ReplicatedStorage").Airfront.Data.Cosmetics)
for _,list in {C.all(),C.shop_items()} do for _,item in list do assert(table.find(after.owned,item.id),"Missing catalogue item: "..item.id) end end
for _,item in require(game:GetService("ReplicatedStorage").Airfront.Data.Arsenal).DISPLAY_ITEMS do assert(table.find(after.unlocks,item.key),"Missing equipment: "..item.key) end
for _,id in before.owned do assert(table.find(after.owned,id),"Existing ownership changed") end
assert(after.equipped.skin==before.equipped.skin and after.equipped.flag==before.equipped.flag,"Equipment changed unexpectedly")
assert(after.stars-before.stars==0 or after.stars-before.stars==1000000,"Owner grant must be once only")
return {owner=Test.OWNER,testCosmeticsAvailable=#after.owned,equipmentAvailable=#after.unlocks,creditsAdded=after.stars-before.stars,balance=after.stars,existingItemsPreserved=true,equipmentPreserved=true,realRankingUnchanged=true,version=game.PlaceVersion}
