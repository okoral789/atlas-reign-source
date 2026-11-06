require("./prelude")
local Colors=require("../src/shared/Data/ProfileStyle")
local Country=require("../src/shared/Data/CountryStyle")
local SimColors=require("../src/shared/Core/SimColors")
local f32=require("../src/shared/Core/Defs").f32b
local Cosmetics=require("../src/shared/Data/Cosmetics")
local Styles=require("../src/shared/Data/FleetStyles")
assert(#Colors.colors==21 and Colors.colors[2].rgb==0x53A9FF,"preserve purchased classic colors")
assert(Colors.badge(0)=="\u{25C6} RECRUIT" and Colors.badge(100)=="\u{2605} LEGEND","preserve UTF-8 rank badges")
local premium=Colors.shop_indices();assert(#premium==15)
for _,index in premium do
 assert(index>=7 and Colors.colors[index].premium)
 assert(not Country.allowed(index,{}) and Country.allowed(index,{[Colors.item_id(index)]=true}))
 local rgba=Country.rgba(index)
 local target=SimColors.oklab(rgba)
 local nearest=math.huge
 for _,normal in SimColors.human_palette() do
  local lab=SimColors.oklab(normal)
  local x,y,z=f32(lab.x-target.x),f32(lab.y-target.y),f32(lab.z-target.z)
  assert(SimColors.dist(lab,target)==f32(math.sqrt(f32(f32(f32(x*x)+f32(y*y))+f32(z*z)))),
   "vector distance retains the original float32 rounding")
  nearest=math.min(nearest,math.sqrt((lab.x-target.x)^2+(lab.y-target.y)^2+(lab.z-target.z)^2))
 end
 assert(nearest>.04,"premium color must visibly differ from the random player palette")
end
assert(#Styles==14 and Styles[1].id=="fleet_copper" and Styles[3].id=="fleet_obsidian")
local masks,originals={},0
for _,style in Styles do
 local item=Cosmetics.item(style.id);assert(item and item.shop and item.kind=="skin")
 assert(item.border==true,"existing paid style is now an independent border accent")
 if style.premium and string.sub(style.id,1,7)~="border_" then
  local mask,w,h=Cosmetics.mask(item);local signature=buffer.tostring(mask)
  assert(not masks[signature] and #style.colors>=2 and w==16 and h==16)
  masks[signature]=true;originals+=1
  for i=0,buffer.len(mask)-1 do assert(buffer.readu8(mask,i)<=#style.colors) end
 end
 for _,outcome in Cosmetics.outcomes({}) do assert(outcome.item.id~=style.id,"direct-sale pattern never leaks into random cases") end
end
assert(originals==6)
print("PASS premium styles: distinct paid colors, preserved old entitlements and cosmetic effects outside random cases")
