--!nocheck
require("./prelude")
local M=require("../src/client/UI/MenuLayout")
local Ctx=require("../src/client/UI/UICtx")
local function overlap(a,b) return a.x<b.x+b.w and b.x<a.x+a.w and a.y<b.y+b.h and b.y<a.y+a.h end
local checked=0
for _,size in {{2560,1360},{1920,1080},{1600,900},{1280,720},{1280,600},{1100,600},{844,390},{740,360},{568,320}} do
 local vp=Vector2.new(size[1],size[2])
 for _,count in {6,7,8} do
  local plan=M.make(vp,{x=0,y=0,z=0,w=0},Rect.new(0,0,270,58),vp.X<1000,count)
  local p=plan.panel
  assert(p.x>=0 and p.y>=58 and p.x+p.w<=vp.X and p.y+p.h<=vp.Y-20,"menu outside viewport")
  assert(not overlap(plan.coin,plan.wallet),"Credits coin covers the balance")
  assert(not overlap(plan.logo,plan.coin) and not overlap(plan.logo,plan.wallet),"logo covers Credits")
  if plan.owner then
   assert(not overlap(plan.owner,plan.coin) and not overlap(plan.owner,plan.wallet),"profile badge covers Credits")
   assert(not overlap(plan.owner,plan.logo),"profile badge covers wordmark")
  end
  for i=1,count do
   local row=assert(plan.nav[i],"navigation row is missing")
   assert(row.x>=0 and row.y>=0 and row.x+row.w<=p.w and row.y+row.h<=p.h)
   assert(not overlap(row,plan.wallet) and not overlap(row,plan.logo),"menu controls cover the logo/wallet")
   for j=1,i-1 do assert(not overlap(row,plan.nav[j]),"navigation overlaps") end
  end
  if not plan.compact then
   for i=2,5 do assert(plan.nav[i].x==plan.nav[1].x and plan.nav[i].y>=plan.nav[i-1].y+plan.nav[i-1].h+8,"right navigation stays a spaced vertical column") end
   assert(plan.logo.x>p.w*.15 and plan.logo.x+plan.logo.w<p.w*.85,"wordmark stays centered")
   local popup=M.party(plan,vp,220)
   for _,r in plan.nav do assert(not overlap({x=p.x+r.x,y=p.y+r.y,w=r.w,h=r.h},popup),"party covers menu buttons") end
  end
  checked+=1
 end
end
local ctx=Ctx.new();ctx:set_ratio(1);assert(ctx.ratio==.75 and ctx:order_ratio()==.75)
local F=require("./simsys_fixture")
local sim=F.new_sim(91)
local A=F.owner(sim,"Player",F.Defs.KIND_HUMAN,0,20000)
F.claim(sim,A,690,100,12)
local target=-1
for t=0,sim.N-1 do
 if buffer.readi32(sim.owner,t*4)==0 and buffer.readu8(sim.land,t)==1 then
  local x,y=t%sim.W,t//sim.W
  if math.abs(x-690)<16 and math.abs(y-100)<16 then target=t;break end
 end
end
assert(target>=0)
for _=1,4 do assert(sim:intent_attack(A,target,ctx:order_ratio()),"repeated 75% expansion") end
assert(sim.o_troops[A]>0 and sim.o_troops[A]<=100,"20K can fall below 100 without a mandatory reserve")
print("PASS: "..checked.." menu geometries; Credits/nav separation; Party placement; 75%-per-click client and repeated server orders")
