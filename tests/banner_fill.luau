require("./prelude")
local C=require("../src/shared/Data/Cosmetics")
local Purchases=require("../src/server/Purchases")
local player={UserId=73}
local rows={u73={owned={shop_cat=true},equipped={flag="shop_cat"},stars=1234,receipts={},paid=false},u74={owned={banner_cat=true},equipped={skin="banner_cat"}}}
local store={GetAsync=function(_,key) return rows[key] end,UpdateAsync=function(_,key,fn) local value=fn(rows[key]);if value then rows[key]=value end;return value end}
Purchases.reset();Purchases.configure({datastore=store})
Purchases.load(player)
local banner=C.banner_for("shop_cat")
assert(banner and banner.id=="banner_cat" and banner.flag_source=="shop_cat" and not C.may_own(banner.id,73))
assert(table.find(Purchases.inventory(player).owned,banner.id),"owning a flag includes its territory fill")
assert(Purchases.equip(player,"skin",banner.id) and rows.u73.equipped.skin==banner.id)
assert(rows.u73.stars==1234 and #rows.u73.receipts==0 and not rows.u73.paid,"using a banner does not create a payment or spend Credits")
Purchases.release(player);Purchases.load(player)
assert(Purchases.inventory(player).equipped.skin==banner.id,"derived entitlement survives reconnect")
local forged={UserId=74};Purchases.load(forged)
assert(not table.find(Purchases.inventory(forged).owned,banner.id) and not Purchases.inventory(forged).equipped.skin)
assert(not Purchases.equip(forged,"skin",banner.id),"a forged banner without its source flag cannot be equipped")
local n=0
for _,it in C.shop_items() do if it.kind=="flag" then
 local b=C.banner_for(it.id);assert(b and b.banner)
 local pixels,w,h=C.mask(b);assert(w==24 and h==16 and buffer.len(pixels)==384)
 for i=0,383 do assert(buffer.readu8(pixels,i)>=1 and buffer.readu8(pixels,i)<=#b.colors) end
 n+=1
end end
assert(n==38 and C.item("pattern_circuit").effect=="neon" and C.item("pattern_lava").effect=="flame")
for _,entry in C.outcomes({}) do assert(not entry.item.banner,"banners never enter random rewards") end
print("PASS 38 flag fills: valid masks, flag-derived access, no charges, reconnect and forged ownership rejection; VFX styles preserve IDs")
