--!nocheck
require("./prelude")
local Country=require("../src/shared/Data/CountryStyle")
local Colors=require("../src/shared/Data/ProfileStyle")
local F=require("./simsys_fixture")
local State=require("../src/shared/Core/GameState")
assert(Country.allowed(0,{}) and not Country.allowed(1,{}))
assert(not Country.allowed(2,{}) and Country.allowed(2,{[Colors.item_id(2)]=true}))
for _,bad in {false,"2",-1,1.5,99,math.huge,0/0} do assert(not Country.allowed(bad,{})) end
assert(Country.rgba(0)==nil)
local sim=F.new_sim(25)
local id=F.owner(sim,"Commander",F.Defs.KIND_HUMAN,0,20000)
local st=State.new();st.owners[id]={color=Color3.fromRGB(90,100,110)}
local original=st:owner_color(id)
st:set_cosmetics({[id]={user_id=7,color=Country.rgba(2)}},true)
local c=st:owner_color(id)
assert(math.abs(c.B-(Colors.colors[2].rgb%256)/255)<.001,"owned country color reaches rendering")
st:set_cosmetics({[id]={user_id=7,color=math.huge}},true)
assert(st:owner_color(id)==original,"invalid network color cannot corrupt rendering")
st:set_cosmetics({[id]={user_id=7}},true)
assert(st:owner_color(id)==original,"random preference restores native owner color")
print("PASS country style: permanent entitlement checks, hostile inputs, actual map color and random reset")
local Match=require("../src/server/MatchServer")
local peer={};local color=Country.rgba(2);local fill=false
local host={deps={cosmetics_of=function() return {color=color,flag_fill=fill} end},_participants={[peer]={owner=1,uid=7}},_match_seats={}}
assert(Match.cosmetics_map(host)[1].color==color)
color=Country.rgba(3)
fill=true
assert(Match.cosmetics_map(host)[1].color~=color,"mid-match settings keep identity stable")
assert(Match.cosmetics_map(host)[1].flag_fill==false,"flag blend is fixed during a match too")
host._participants={[{}]={owner=1,uid=7}}
assert(Match.cosmetics_map(host)[1].color~=color,"reconnecting does not bypass color freeze")
host._country_colors={}
host._country_flags={}
assert(Match.cosmetics_map(host)[1].color==color,"next match uses the latest saved style")
assert(Match.cosmetics_map(host)[1].flag_fill==true)
st:set_cosmetics({[id]={user_id=7,flag="shop_lion_crest",flag_fill=true}},true)
assert(st.cosmetics[id].flag_fill,"flag blend reaches clients independently of the border skin")
print("PASS multiplayer style: fixed during match and reconnect; refreshed for next match")
