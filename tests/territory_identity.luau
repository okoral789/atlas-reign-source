--!nocheck
local roblox=require("./prelude")
getfenv().Instance=roblox.Instance;getfenv().Enum=roblox.Enum;getfenv().task=require("@lune/task");getfenv().warn=function() end
local Surface=require("../src/client/Map/MapSurface")
local Country=require("../src/shared/Data/CountryStyle")
local Colors=require("../src/shared/Data/ProfileStyle")
local C=require("../src/shared/Data/Cosmetics")
local W,H=80,80
local terrain=buffer.create(W*H);buffer.fill(terrain,0,128)
local st={owner=buffer.create(W*H*4),flags=buffer.create(W*H),owners={[1]={spawn_tile=40*W+40}},cosmetics={},alliances={},fallout_count=0,map={k_lin=1}}
function st:owner_color() return Color3.fromRGB(229,252,255) end
function st:are_allies() return false end
for y=5,74 do for x=5,74 do buffer.writei32(st.owner,(y*W+x)*4,1) end end
local surface=Surface.new(nil);surface:set_map({W=W,H=H,tile_bytes=terrain});surface:bind(st)
local function drain()
 local n=0;while surface._rebuild_active or surface:repaint_pending()>0 do surface:step();n+=1;assert(n<100) end
end
drain()
for i=7,11 do
 st.cosmetics[1]={color=Country.rgba(i),skin="pattern_circuit",flag="shop_lion_crest",flag_fill=false}
 surface:on_cosmetics_changed({1});drain()
 local a,b=surface:tile_pixel(20*W+20),surface:tile_pixel(60*W+60)
 assert(a~=b and a//16777216==240,"actual territory uses the paid gradient")
 assert(not surface._skins[1],"border styles do not paint an old territory mask")
 local edge=surface:tile_pixel(5*W+20)
 local item=C.item("pattern_circuit");local tint=item.fleet_tint
 assert(edge%256==tint//65536%256 and edge//256%256==tint//256%256,"border follows its chosen accent")
 st.cosmetics[1].flag_fill=true;surface:on_cosmetics_changed({1});drain()
 assert(surface._skins[1].blend and surface:tile_pixel(20*W+20)~=a,"flag overlay combines with gradient and border")
 local before=buffer.tostring(surface.comp);surface:rebuild_all();drain()
 assert(before==buffer.tostring(surface.comp),"incremental and full composite agree")
end
assert(Country.clean({color=7,flag_fill=true},true).flag_fill)
assert(not Country.clean({color=7,flag_fill="true"},true) and not Country.clean({color=7},false))
assert(not Country.clean({color=0/0},true) and not Country.clean({color=1},true))
for i=7,11 do
 assert(Country.index(Country.rgba(i))==i and #Colors.colors[i].gradient==3)
 local r,g,b=Country.sample(i,0);local a,c,d=Country.sample(i,1)
 assert(r~=a or g~=c or b~=d)
end
print("PASS territory identity: live gradients, flag mix, independent borders, repaint parity and checked settings")
