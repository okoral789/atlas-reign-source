-- Native 2D previews use the same gradient stops, flag mix and border art as the map.
local L=require("./Look")
local RS=game:GetService("ReplicatedStorage")
local C=require(RS.Airfront.Data.Cosmetics)
local Country=require(RS.Airfront.Data.CountryStyle)
local Style=require(RS.Airfront.Data.ProfileStyle)
local Field=require(RS.Airfront.Data.BorderField)
local Preview={}
local effects=setmetatable({},{__mode="k"})
function Preview.clear_effect(root)
 local old=effects[root]
 if old then
  effects[root]=nil
  old.destroying:Disconnect()
  old.label:Destroy()
  old.image:Destroy()
 end
 root:SetAttribute("TerritoryEffect",nil)
end
function Preview.add_effect(root,kind,cells,tint)
 Preview.clear_effect(root)
 root:SetAttribute("TerritoryEffect",kind)
 local w,h=120,84;local owned={}
 for _,cell in cells or {} do owned[cell.y*40+cell.x]=true end
 local field=Field.build(w,h,function(x,y)
  if cells then return if owned[(y//3)*40+x//3] then 1 else 0 end
  return if x>=4 and x<w-4 and y>=4 and y<h-4 then 1 else 0
 end,{[1]={effect=kind,fleet_tint=if tint then math.floor(tint.R*255)*65536+math.floor(tint.G*255)*256+math.floor(tint.B*255) else 0xFFAC46}})
 local ok,image=pcall(function() return game:GetService("AssetService"):CreateEditableImage({Size=Vector2.new(w,h)}) end)
 if not ok or not image then return end
 local label=L.make("ImageLabel",{Name="ContinuousBorderPreview",ImageContent=Content.fromObject(image),BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ZIndex=root.ZIndex+3},root)
 local effect={image=image,label=label,field=field,pixels=buffer.create(w*h*4),last=-1}
 effects[root]=effect
 effect.destroying=root.Destroying:Once(function()
  if effects[root]==effect then effects[root]=nil;image:Destroy() end
 end)
 Preview.animate(root,0)
 return label
end
function Preview.animate(root,t)
 local e=effects[root];if not e or t-e.last<1/12 then return end
 e.last=t;e.image:WritePixelsBuffer(Vector2.zero,Vector2.new(e.field.w,e.field.h),Field.render(e.field,t,e.pixels))
end
local function paint(item,color,look)
 local fill=if look and look.flag_fill then C.banner_for(look.flag) else nil
 local mask,w,h
 if fill then item=fill elseif item and item.border then item=nil end
 if item then mask,w,h=C.mask(item) end
 local index=look and look.color
 local gradient=Style.valid(index) and Style.colors[index].gradient~=nil
 return function(x,y,t)
  local base=color
  if gradient then local r,g,b=Country.sample(index,t);base=Color3.fromRGB(r,g,b) end
  if not item then return base end
  local k=buffer.readu8(mask,(bit32.rshift(y,item.scale or 0)%h)*w+bit32.rshift(x,item.scale or 0)%w)
  if k==0 then return base end
  local r,g,b=C.color(item,k)
  if not r then r,g,b=C.secondary(item,base.R,base.G,base.B) end
  return base:Lerp(Color3.new(r,g,b),if fill then Country.FLAG_MIX else C.skin_alpha(item)/255)
 end
end
function Preview.new(parent,item,color,pos,size,look)
 local root=L.make("Frame",{Name="PatternPreview",BackgroundColor3=color,BorderSizePixel=0,ClipsDescendants=true,Position=pos,Size=size},parent);L.round(root,6)
 local tint=paint(item,color,look)
 local sample=if item and item.premium then 2^(item.scale or 0) else 1
 for y=0,15 do
  local x=0
  while x<32 do
   local first=x;local c=tint(x*sample,y*sample,(x/31+y/15)/2);x+=1
   while x<32 and tint(x*sample,y*sample,(x/31+y/15)/2)==c do x+=1 end
   if c~=color then L.make("Frame",{BackgroundColor3=c,BorderSizePixel=0,Position=UDim2.fromScale(first/32,y/16),Size=UDim2.new((x-first)/32,1,1/16,1)},root) end
  end
 end
 if item and item.border then
  L.outline(root,Color3.fromHex(string.format("%06X",item.fleet_tint)),2)
  if item.effect then Preview.add_effect(root,item.effect,nil,if item.effect~="flame" then Color3.fromHex(string.format("%06X",item.fleet_tint)) else nil) end
 end
 return root
end
function Preview.country(parent,pos,size)
 local root=L.card(parent,"CountryMap",pos,size,Color3.fromRGB(12,59,87));root.ClipsDescendants=true
 local cells,byTile={},{}
 for y=0,27 do for x=0,39 do
  local coast=5+math.floor(2*math.sin(y*.55))
  if x>coast and not (y<4 and x<19) then
   local ours=x>=11+math.floor(2*math.sin(y*.8)) and x<=30+math.floor(2*math.cos(y*.6)) and y>=5+math.floor(math.sin(x)) and y<=23+math.floor(math.sin(x*.7)*2)
   local c=if x<16 then Color3.fromRGB(110,155,86) elseif y<13 then Color3.fromRGB(213,171,79) else Color3.fromRGB(193,113,98)
   local cell=L.make("Frame",{Name=if ours then "TerritoryTile" else "Neighbour",BackgroundColor3=c,BorderSizePixel=0,Position=UDim2.fromScale(x/40,y/28),Size=UDim2.new(1/40,1,1/28,1)},root)
   if ours then local entry={gui=cell,x=x,y=y};cells[#cells+1]=entry;byTile[y*40+x]=true end
  end
 end end
 for _,cell in cells do local t=cell.y*40+cell.x;cell.edge=not byTile[t-1] or not byTile[t+1] or not byTile[t-40] or not byTile[t+40] end
 return root,cells
end
function Preview.update(cells,item,color,look)
 local tint=paint(item,color,look)
 local x0,y0,x1,y1=math.huge,math.huge,0,0
 for _,cell in cells do x0=math.min(x0,cell.x);y0=math.min(y0,cell.y);x1=math.max(x1,cell.x);y1=math.max(y1,cell.y) end
 local banner=if look and look.flag_fill then C.banner_for(look.flag) else item and item.banner and item
 for _,cell in cells do
  local u,v=(cell.x-x0)/(x1-x0+1),(cell.y-y0)/(y1-y0+1)
  local x,y=cell.x,cell.y
  if banner then x=math.floor(u*24)*2^banner.scale;y=math.floor(v*16)*2^banner.scale end
  cell.gui.BackgroundColor3=if cell.edge and item and item.border then Color3.fromHex(string.format("%06X",item.fleet_tint)) else tint(x,y,(u+v)/2)
 end
end
return Preview
