--!nonstrict
-- Isolated 2D demonstrations; no Session, intents, purchases or saved data.
local T=require("./UITheme")
local L=require("./Look")
local Rules=T.core("Rules")
local Defs=T.core("Defs")
local Demo={};Demo.__index=Demo
local BLUE=Color3.fromRGB(81,163,240)
local RED=Color3.fromRGB(217,108,88)
local BURN=Color3.fromRGB(109,83,69)
function Demo.spec(key)
 if Rules.SUPPORT[key] then
  local s=Rules.SUPPORT[key]
  return {title="FLEET REPAIR",cost=s.cost,cooldown=s.cooldown/Defs.TICK_RATE,
   summary="Repair your damaged warships in one area.",
   details=T.fmt_cost(s.cost).." GOLD / CALL  ·  "..tostring(s.cooldown/10).."s COOLDOWN  ·  PORT",
   facts={"Own living warships in the area gain up to 30% of maximum HP; capped at full hull.","Range: 180 tiles from a finished Port. Area radius: 45 tiles. Choose open water.","No new ships, bonus maximum HP, or repairs to trade, landing or enemy ships."}}
 end
 if key=="reinforce" then
  return {title="REINFORCEMENTS",cost=Rules.REINFORCE_COST,
   cooldown=Rules.REINFORCE_COOLDOWN_TICKS/Defs.TICK_RATE,
   summary="Call in extra troops when you need them.",details="100K GOLD / CALL  ·  +20% OF CAPACITY  ·  30s COOLDOWN",
   facts={"Adds up to 20% of your existing troop capacity. Respects your current cap.",
    T.fmt_cost(Rules.REINFORCE_COST).." match Gold per call. Ready again after "..Rules.REINFORCE_COOLDOWN_TICKS/Defs.TICK_RATE.." seconds.",
    "Permanent account unlock. Available in every match after unlocking."}}
 end
 local kind=({atom=Defs.N_ATOM,hydrogen=Defs.N_HYDROGEN,mirv=Defs.N_MIRV,mega=Defs.N_MEGA,scatter=Defs.N_SCATTER})[key]
 if kind==nil then return nil end
 local title=Defs.NUKE_TITLES[kind]:upper()
 local facts=if key=="mirv" then {
  "One carrier releases "..Rules.MIRV_WARHEADS.." warheads across enemy territory.",
  "First launch: "..T.fmt_cost(Rules.nuke_cost(key,0)).." Gold. Each previous MIRV adds "..T.fmt_cost(Rules.MIRV_COST_STEP).." Gold to the next.",
  "Requires a Missile Silo. This animation shows representative impacts."}
 else {
  if key=="atom" then "Focused blast against troops, land and structures." else "A much wider blast against troops, land and structures.",
  "Requires a Missile Silo. Enemy SAMs can intercept the missile.",
  (if key=="mega" or key=="scatter" then "Permanent unlock. " else "Included for everyone. ").."Each launch costs "..T.fmt_cost(Rules.nuke_cost(key,0)).." match Gold."}
 return {title=title,kind=kind,cost=Rules.nuke_cost(key,0),summary=({atom="One focused blast.",hydrogen="A much wider blast.",mirv="350 warheads across enemy territory.",mega="4× the blast area of an Atom Bomb.",scatter="A central blast with 4–6 extra warheads."})[key],
  details=T.fmt_cost(Rules.nuke_cost(key,0)).." GOLD  ·  MISSILE SILO  ·  "..(if key=="mirv" then "+15M GOLD EACH LAUNCH · SAMs CAN HIT WARHEADS" else "SAMs CAN INTERCEPT"),facts=facts}
end
function Demo.reinforcement_example(before,cap)
 local gain=Rules.reinforce_troops(before,cap)
 return {before=before,after=before+gain,cap=cap,gain=gain}
end
function Demo.new(parent,key)
 local self=setmetatable({key=key,cells={},parts={},impacts={},painted=nil,spec=assert(Demo.spec(key),"Unknown Armory preview")},Demo)
 self.root=L.make("Frame",{Name="ArmoryPreview",Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(14,55,79),BorderSizePixel=0,ClipsDescendants=true},parent);L.round(self.root,10)
 local map=T.core("WorldMap").get("world")
 for y=0,25 do for x=0,47 do
  local tx=math.clamp(math.floor(map.W*(.43+x/48*.30)),0,map.W-1)
  local ty=math.clamp(math.floor(map.H*(.14+y/26*.38)),0,map.H-1)
  local tile=ty*map.W+tx
  if buffer.readu8(map.land,tile)==1 and (key~="fleet_repair" or x<16) then
   local ours=x<25+math.floor(math.sin(y*.5)*3)
   local base=if ours then BLUE else RED
   local shade=buffer.readu8(map.tile_bytes,tile)%32
   local color=base:Lerp(Color3.fromRGB(230,218,158),shade/100)
   local cell=L.make("Frame",{BackgroundColor3=color,BorderSizePixel=0,Position=UDim2.fromScale(x/48,y/26),Size=UDim2.new(1/48,1,1/26,1)},self.root)
   self.cells[#self.cells+1]={gui=cell,x=x,y=y,color=color}
  end
 end end
 L.icon(self.root,"city",UDim2.fromScale(.32,.55),UDim2.fromOffset(22,22),L.INK)
 self.target=L.icon(self.root,"city",UDim2.fromScale(.78,.45),UDim2.fromOffset(28,28),L.INK)
 local tag=L.label(self.root,"PREVIEW",10,UDim2.fromOffset(12,8),UDim2.fromOffset(74,22),L.INK,800);tag.BackgroundColor3=L.BG;tag.BackgroundTransparency=.1;tag.TextXAlignment=Enum.TextXAlignment.Center;L.round(tag,6)
 self.status=L.label(self.root,"",14,UDim2.new(0,14,1,-40),UDim2.new(1,-28,0,28),L.INK,800)
 self.status.BackgroundColor3=L.BG;self.status.BackgroundTransparency=.15;self.status.TextXAlignment=Enum.TextXAlignment.Center;L.round(self.status,7)
 if Rules.SUPPORT[key] then
  self.support=true
  self.target.Image=T.icon("warship") or ""
  self.target.Position=UDim2.fromScale(.73,.43)
  self.target.Size=UDim2.fromOffset(38,38)
  self.target.ImageColor3=BLUE
  self.support_ring=L.make("Frame",{Name="SupportArea",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.76,.49),Size=UDim2.fromOffset(120,120),BackgroundColor3=L.ACCENT,BackgroundTransparency=.88,BorderSizePixel=0},self.root);L.round(self.support_ring,999);L.outline(self.support_ring,L.ACCENT,2)
  self.support_bar=L.make("Frame",{Position=UDim2.fromScale(.67,.70),Size=UDim2.new(.2,0,0,8),BackgroundColor3=L.BG,BorderSizePixel=0},self.root);L.round(self.support_bar,4)
  self.support_fill=L.make("Frame",{Size=UDim2.fromScale(.4,1),BackgroundColor3=L.ACCENT,BorderSizePixel=0},self.support_bar);L.round(self.support_fill,4)
  local art=require(game:GetService("ReplicatedStorage").Airfront.Assets.SupportArt)
  L.make("ImageLabel",{Image=art[key],BackgroundTransparency=1,Position=UDim2.fromScale(.08,.1),Size=UDim2.fromOffset(90,90),ScaleType=Enum.ScaleType.Fit},self.root)
 elseif key=="reinforce" then
  self.example=Demo.reinforcement_example(60000,100000)
  self.bar_bg=L.make("Frame",{Position=UDim2.new(.18,0,1,-62),Size=UDim2.new(.65,0,0,8),BackgroundColor3=L.BG,BorderSizePixel=0},self.root);L.round(self.bar_bg,4)
  self.bar=L.make("Frame",{Size=UDim2.fromScale(.6,1),BackgroundColor3=L.ACCENT,BorderSizePixel=0},self.bar_bg);L.round(self.bar,4)
  for i=1,3 do
   local f=L.make("Frame",{Size=UDim2.fromOffset(26,40),BackgroundTransparency=1},self.root)
   local canopy=L.make("Frame",{Size=UDim2.fromOffset(26,14),BackgroundColor3=L.INK,BorderSizePixel=0},f);L.round(canopy,13)
   for _,x in {5,20} do L.make("Frame",{Position=UDim2.fromOffset(x,12),Size=UDim2.fromOffset(1,18),BackgroundColor3=L.INK,BorderSizePixel=0},f) end
   local crate=L.make("Frame",{Position=UDim2.fromOffset(7,28),Size=UDim2.fromOffset(13,10),BackgroundColor3=L.GOLD,BorderSizePixel=0},f);L.round(crate,2)
   self.parts[i]=f
  end
 else
  local art=require(game:GetService("ReplicatedStorage").Airfront.Assets.NukeMarkers)
  self.missile=L.make("ImageLabel",{Name="EquipmentMissile",Image=art[key],BackgroundTransparency=1,Size=UDim2.fromOffset(54,54),ScaleType=Enum.ScaleType.Fit},self.root)
  local count=if key=="mirv" then 12 elseif key=="scatter" then 6 else 1
  for i=1,count do
   local x,y=37,12
   if key=="mirv" then x=29+(i*7%16);y=5+(i*5%17)
   elseif key=="scatter" and i>1 then local a=(i-2)/5*math.pi*2;x=37+math.cos(a)*6;y=12+math.sin(a)*6 end
   local radius=if key=="mirv" or (key=="scatter" and i>1) then 1.5 else Rules.NUKE_OUTER_FULL[self.spec.kind]*.13
   local ring=L.make("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale((x+.5)/48,(y+.5)/26),Size=UDim2.new(),BackgroundColor3=Color3.fromRGB(255,151,57),BackgroundTransparency=.5,BorderSizePixel=0},self.root);L.round(ring,999)
   L.outline(ring,L.GOLD,2)
   self.impacts[i]={gui=ring,x=x,y=y,radius=radius,
    warhead=if key=="mirv" or (key=="scatter" and i>1) then L.icon(self.root,"atom",UDim2.new(),UDim2.fromOffset(12,12),L.GOLD) else nil}
  end
 end
 self:update(0);return self
end
function Demo.update(self,t)
 if self.support then
  local time=math.max(0,t)%9
  local done=time>=3 and time<6
  self.support_ring.BackgroundTransparency=.88+math.sin(time*5)*.04
  self.support_fill.Size=UDim2.fromScale(if done then .7 else .4,1)
  self.status.Text=if done then "+30% HULL  ·  70 / 100 HP" else "DAMAGED WARSHIP  ·  40 / 100 HP"
  return
 end
 local time=math.max(0,t)%7
 local done=time>=2.4 and time<6
 local p=math.clamp((time-.3)/2.1,0,1)
 if self.key=="reinforce" then
  for i,f in self.parts do f.Visible=not done and time<2.4;f.Position=UDim2.fromScale(.23+(i-1)*.12,-.15+.75*p) end
  if self.painted~=done then
   self.bar.Size=UDim2.fromScale((if done then self.example.after else self.example.before)/self.example.cap,1)
   local e=self.example
   self.status.Text=if done then "+"..T.fmt_cost(e.gain).." TROOPS  ·  "..T.fmt_cost(e.after).." / "..T.fmt_cost(e.cap).." CAP" else "BEFORE THE CALL  ·  "..T.fmt_cost(e.before).." / "..T.fmt_cost(e.cap).." CAP"
  end
 else
  self.missile.Visible=time<(if self.key=="mirv" then 1.25 else 2.4)
  self.missile.Position=UDim2.fromScale(.22+.59*p,.64-.14*p-math.sin(p*math.pi)*.32)
  self.missile.Rotation=-40+40*p
  for _,impact in self.impacts do
   if impact.warhead then
    local q=math.clamp((time-1.25)/1.15,0,1)
    local x,y=(impact.x+.5)/48,(impact.y+.5)/26
    impact.warhead.Visible=time>=1.25 and time<2.4
    impact.warhead.Position=UDim2.fromScale(.49+(x-.49)*q,.26+(y-.26)*q)
    impact.warhead.Rotation=90+math.deg(math.atan2(y-.26,x-.49))
   end
   impact.gui.Visible=done
   local width=if self.root.AbsoluteSize.X>0 then self.root.AbsoluteSize.X else 600
   local size=impact.radius*2/48*width*math.clamp((time-2.4)*3,0,1)
   impact.gui.Size=UDim2.fromOffset(size,size)
   impact.gui.BackgroundTransparency=.55+math.clamp((time-3)/3,0,1)*.4
  end
  if self.painted~=done then
   self.target.Visible=not done
   for _,cell in self.cells do
    local hit=false
    if done then for _,impact in self.impacts do if (cell.x-impact.x)^2+(cell.y-impact.y)^2<=impact.radius^2 then hit=true;break end end end
    cell.gui.BackgroundColor3=if hit then BURN else cell.color
   end
   self.status.Text=if done then ({mirv="350 WARHEADS · ILLUSTRATIVE IMPACTS",mega="4× ATOM BLAST AREA",scatter="CENTRAL BLAST + EXTRA WARHEADS"})[self.key] or "IMPACT" else "MISSILE INBOUND"
  end
 end
 self.painted=done
end
function Demo.destroy(self) self.root:Destroy() end
return Demo
