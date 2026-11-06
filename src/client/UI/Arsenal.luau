--!nonstrict
-- Extra equipment is an account unlock; the three standard bombs are always in the match HUD.
local T=require("./UITheme")
local W=require("./Widgets")
local L=require("./Look")
local Signal=T.core("Signal")
local IS_ROBLOX=typeof(game)=="Instance"
local function shared(n) return if IS_ROBLOX then require(game:GetService("ReplicatedStorage").Airfront.Data[n]) else require("../../shared/Data/"..n) end
local Catalog=shared("Arsenal")
local Products=shared("Products")
local Prices=require("./Prices")
local PurchasePrompt=require("./PurchasePrompt")
local Rules=T.core("Rules")
local Art=if IS_ROBLOX then require(game:GetService("ReplicatedStorage").Airfront.Assets.Design) else require("../../shared/Assets/Design")
local Artwork=require("./Artwork")
local Demo=require("./ArsenalDemo")
local Shop=require("./FlagShop")
local NukeArt=if IS_ROBLOX then require(game:GetService("ReplicatedStorage").Airfront.Assets.NukeMarkers) else require("../../shared/Assets/NukeMarkers")
local SupportArt=if IS_ROBLOX then require(game:GetService("ReplicatedStorage").Airfront.Assets.SupportArt) else require("../../shared/Assets/SupportArt")
local Arsenal=W.class(W.Control)
Arsenal.SUBTITLE="Earn it. Unlock it. Bring it to battle."
Arsenal.CONFIRM_S=3
function Arsenal.commas(n)
 local s=tostring(math.floor(math.abs(n)+.5));local out=string.reverse((string.gsub(string.reverse(s),"(%d%d%d)","%1,")))
 if out:sub(1,1)=="," then out=out:sub(2) end
 return if n<0 then "-"..out else out
end
function Arsenal.short(n) return if n>=10000 and n%1000==0 then Arsenal.commas(n/1000).."K" else Arsenal.commas(n) end
function Arsenal.pick(inv,focus)
 if focus and not Catalog.RETIRED[focus] and Catalog.item(focus) then return focus end
 local unlocks=inv.unlocks or {}
 for _,it in Catalog.DISPLAY_ITEMS do if not unlocks[it.key] and it.stars and (inv.stars or 0)>=it.stars then return it.key end end
 for _,it in Catalog.DISPLAY_ITEMS do if not unlocks[it.key] then return it.key end end
 return Catalog.DISPLAY_ITEMS[1].key
end
local function basic_art(parent,index,pos,size)
 if index<=3 then
  local root=L.make("Frame",{Name="BombArt",BackgroundTransparency=1,Position=pos,Size=size},parent)
  L.make("ImageLabel",{Image=NukeArt[Catalog.BASE_BOMBS[index]],BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ScaleType=Enum.ScaleType.Fit},root)
  return root
 end
 return Artwork.new(parent,Art.armory,Art.armory_size,Art.armory_rects[index],pos,size)
end
local function equipment_art(parent,key,pos,size)
 return L.make("ImageLabel",{Name="EquipmentArt",Image=SupportArt[key] or NukeArt[key],BackgroundTransparency=1,Position=pos,Size=size,ScaleType=Enum.ScaleType.Fit},parent)
end
function Arsenal.new(c)
 local self=setmetatable({},Arsenal.__mt);W.Control._init(self)
 self.ctx=c;self.closed=Signal.new();self.is_open=false;self.cards={}
 self:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT);self:set_mouse_filter(W.MOUSE_STOP);self:set_visible(false);self.gui.ZIndex=35
 self.browser=Shop.new(c,self);self:add_child(self.browser)
 self.browser.closed:Connect(function() self:close() end)
 if IS_ROBLOX then
  game:GetService("MarketplaceService").PromptProductPurchaseFinished:Connect(function(uid,id,bought)
   if uid~=game:GetService("Players").LocalPlayer.UserId or not self.pending or self.pending.id~=id then return end
   if not bought then self.pending=nil else self.pending.since=os.clock();self.note.Text="Payment received. Saving your unlock…" end
   self:_refresh()
  end)
 end
 Prices.changed:Connect(function() if self.is_open then self:_refresh() end end)
 return self
end

function Arsenal.render_shop(self,shop)
 local previous=if self.note then self.note.Text else "Unlock once with Credits OR Robux. Match Gold costs still apply."
 self.cards={};self.body=shop._sf
 local scale=T.scale;local cs=shop:_card_size();local cols=shop._cols or 3
 local wallet=L.make("Frame",{Name="ArmoryWallet",BackgroundTransparency=1,LayoutOrder=0,Size=UDim2.new(1,0,0,66*scale),ZIndex=41},shop._sf)
 L.make("ImageLabel",{Name="CreditsIcon",Image=T.icon("credits"),BackgroundTransparency=1,ScaleType=Enum.ScaleType.Fit,Size=UDim2.fromOffset(28*scale,28*scale)},wallet)
 self.wallet=L.label(wallet,"",20*scale,UDim2.fromOffset(34*scale,0),UDim2.new(.65,-34*scale,0,28*scale),L.GOLD,900)
 self.progress=L.label(wallet,"",12*scale,UDim2.new(.65,0,0,4*scale),UDim2.new(.35,-8*scale,0,24*scale),L.ACCENT,800);self.progress.TextXAlignment=Enum.TextXAlignment.Right
 self.note=L.label(wallet,previous,11*scale,UDim2.fromOffset(0,34*scale),UDim2.new(1,-8*scale,0,25*scale),L.MUTED);self.note.TextWrapped=true
 shop:track_card(wallet);table.insert(shop._cards,wallet)
 shop._sub:set_text("Preview every item. Unlock with Credits or Robux. Keep it forever.")
 local entries={}
 if shop._filter~="included" then for _,it in Catalog.DISPLAY_ITEMS do
  if shop._filter=="featured" or (shop._filter=="strikes" and it.kind=="nuke") or (shop._filter=="support" and it.kind~="nuke") then entries[#entries+1]=it.key end
 end end
 if shop._filter=="featured" or shop._filter=="included" then for _,key in Catalog.BASE_BOMBS do entries[#entries+1]=key end end
 local grid=L.make("Frame",{Name="EquipmentGrid",BackgroundTransparency=1,LayoutOrder=1,Size=UDim2.new(1,0,0,math.ceil(#entries/cols)*(cs.Y+Shop.GAP)*scale),ZIndex=41},shop._sf)
 for i,key in entries do self:_shop_card(grid,key,Vector2.new((i-1)%cols*(cs.X+Shop.GAP),math.floor((i-1)/cols)*(cs.Y+Shop.GAP)),cs) end
 table.insert(shop._cards,grid);self:_refresh()
end

function Arsenal._shop_card(self,parent,key,pos,size)
 local it=Catalog.item(key);local spec=Demo.spec(key);local included=it==nil
 local scale=T.scale;local function px(n) return n*scale end
 local card,stroke=Shop.card_surface(parent,"Equipment_"..key,pos,size,if included then L.ACCENT else L.GOLD,false)
 local base=table.find(Catalog.BASE_BOMBS,key)
 if base then card.Name="BaseBomb"..base end
 local ah=size.Y*.45
 local art=if key=="reinforce" then basic_art(card,4,UDim2.fromOffset(px(16),px(6)),UDim2.fromOffset(px(size.X-32),px(ah))) else equipment_art(card,key,UDim2.fromOffset(px(16),px(6)),UDim2.fromOffset(px(size.X-32),px(ah)))
 if key=="reinforce" then self.support_icon=art end
 local show=L.button(card,"▶ PREVIEW",UDim2.fromOffset(px(8),px(8)),UDim2.fromOffset(px(86),px(22)),function() self:select_equipment(key) end);show.TextSize=px(10)
 local title=L.label(card,spec.title,px(if self.ctx.compact then 13 else 16),UDim2.fromOffset(px(8),px(ah+14)),UDim2.fromOffset(px(size.X-16),px(24)),L.INK,900)
 local status=L.label(card,if included then "STANDARD ISSUE" else it.facts[1],px(10),UDim2.fromOffset(px(8),px(ah+40)),UDim2.fromOffset(px(size.X-16),px(18)),if included then L.ACCENT else L.MUTED,700)
 L.label(card,T.fmt_cost(spec.cost).." MATCH GOLD"..(if spec.cooldown then " · "..spec.cooldown.."s" else ""),px(10),UDim2.fromOffset(px(8),px(size.Y-74)),UDim2.fromOffset(px(size.X-16),px(23)),L.GOLD,800)
 if included then
  local b=L.button(card,"✓ INCLUDED FOR EVERYONE",UDim2.fromOffset(px(8),px(size.Y-40)),UDim2.fromOffset(px(size.X-16),px(30)),function() self:show_demo(key) end,true);b.TextSize=px(10)
 else
  local earned=L.button(card,"",UDim2.fromOffset(px(8),px(size.Y-40)),UDim2.fromOffset(px((size.X-22)*.59),px(30)),function() self:_buy(key,false) end);earned.TextSize=px(10)
  local paid=L.button(card,"",UDim2.fromOffset(px(14+(size.X-22)*.59),px(size.Y-40)),UDim2.fromOffset(px((size.X-22)*.41),px(30)),function() self:_buy(key,true) end,true);paid.TextSize=px(11)
  self.cards[key]={root=card,stroke=stroke,title=title,status=status,art=art,earned=earned,paid=paid}
 end
 self.browser:track_card(card)
end
function Arsenal.bind(self,s)
 if not s or self.bound==s then return end;self.bound=s
 s.inventory_changed:Connect(function()
  if self.pending and s:has_unlock(self.pending.key) then self.pending=nil;self.note.Text="Unlocked! Ready in your next match." end
  if self.is_open then self:_refresh() end
 end)
 s.unlock_result:Connect(function(key,ok,reason)
  if not self.pending or key~=self.pending.key then return end
  if not ok then self.pending=nil;self.note.Text=if reason=="not enough" then "Not enough Credits. Play matches to earn more." else "Could not unlock. Nothing was spent; try again.";self:_refresh() end
 end)
end
function Arsenal._refresh(self)
 if not self.wallet then return end
 local inv=self.ctx.session.inventory;local count=0
 self.wallet.Text=Arsenal.commas(inv.stars or 0).." CREDITS"
 for _,it in Catalog.DISPLAY_ITEMS do
  local owned=inv.unlocks[it.key]==true;if owned then count+=1 end
  local row=self.cards[it.key]
  if row then
   local product=Products[it.product]
   row.stroke.Color=if owned then L.ACCENT elseif self.focus==it.key then L.GOLD else Color3.fromRGB(193,149,255)
   row.earned.Text=if owned then "✓ UNLOCKED" elseif self.pending and self.pending.key==it.key then "PLEASE WAIT…" elseif self.confirm and self.confirm.key==it.key and os.clock()<self.confirm.until_time then "CONFIRM "..Arsenal.short(it.stars) else Arsenal.short(it.stars).." CREDITS"
   row.paid.Text=if owned then "OWNED" elseif not product or product.id==0 then "UNAVAILABLE" else "R$ "..tostring(Prices.robux(it.product))
   row.earned.Active=inv.loaded==true and not owned and not self.pending
   row.paid.Active=row.earned.Active and product~=nil and product.id>0
  end
 end
 self.progress.Text=count.." / "..#Catalog.DISPLAY_ITEMS.." UNLOCKED"
end
function Arsenal.select_equipment(self,key)
 if not Demo.spec(key) then return end
 self.focus=key;self:_refresh();self:show_demo(key)
end
function Arsenal._buy(self,key,robux)
 local it=Catalog.item(key);local inv=self.ctx.session.inventory
 if not it or Catalog.RETIRED[key] or inv.loaded~=true or inv.unlocks[key] or self.pending then return end
 if robux then
  local p=Products[it.product];if not p or p.id==0 then self.note.Text="Robux offer unavailable.";return end
  self.confirm=nil;self.pending={key=key,id=p.id,since=os.clock()};self:_refresh()
  local ok=pcall(PurchasePrompt.product,p.id)
  if not ok then self.pending=nil;self.note.Text="Purchases unavailable. Please retry.";self:_refresh() end
 else
  if (inv.stars or 0)<it.stars then self.note.Text="Earn "..Arsenal.commas(it.stars-(inv.stars or 0)).." more Credits to unlock "..it.title..".";return end
  if not self.confirm or self.confirm.key~=key or os.clock()>self.confirm.until_time then self.confirm={key=key,until_time=os.clock()+Arsenal.CONFIRM_S};self:_refresh();return end
  self.confirm=nil;self.pending={key=key,since=os.clock()}
  if not self.ctx.session:buy_unlock(key) then self.pending=nil;self.note.Text="Could not reach the server." end;self:_refresh()
 end
end
function Arsenal.tick(self)
 if self.pending and os.clock()-self.pending.since>180 then self.pending=nil;self.note.Text="Any completed purchase is saved. Reopen to refresh." end
 if self.is_open then self:_refresh() end
end
function Arsenal.apply_layout(self) self.browser:apply_layout() end
function Arsenal.show_demo(self,key)
 local spec=Demo.spec(key);if not spec then return end
 if not self.demo_overlay then
  self.demo_overlay=L.make("TextButton",{Name="ArmoryDemoOverlay",Text="",AutoButtonColor=false,Active=true,Size=UDim2.fromScale(1,1),BackgroundColor3=L.BG,BackgroundTransparency=.1,ZIndex=80},self.gui)
  local p=L.surface(self.demo_overlay,"","",Vector2.new(850,560));self.demo_panel=p
  p.Section.Size=UDim2.new(1,-210,0,34)
  L.button(p,"×",UDim2.new(1,-60,0,18),UDim2.fromOffset(36,36),function() self:hide_demo() end)
  L.button(p,"REPLAY",UDim2.new(1,-158,0,18),UDim2.fromOffset(86,36),function() self.demo_elapsed=0;if self.demo then self.demo:update(0) end end)
  self.demo_host=L.make("Frame",{Name="DemoScene",BackgroundTransparency=1},p)
  self.demo_facts=L.label(p,"",13,UDim2.new(0,24,1,-94),UDim2.new(1,-48,0,40),L.GOLD,800);self.demo_facts.TextWrapped=true;self.demo_facts.TextXAlignment=Enum.TextXAlignment.Center
  L.button(p,"BACK TO ARMORY",UDim2.new(0,24,1,-48),UDim2.new(1,-48,0,34),function() self:hide_demo() end,true)
  p:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:_layout_demo() end)
 end
 if self.demo then self.demo:destroy() end
 self.demo=Demo.new(self.demo_host,key);self.demo_elapsed=0
 self.demo_panel.Section.Text=spec.title;self.demo_panel.Heading.Text=spec.summary
 self.demo_facts.Text=spec.details
 self.demo_overlay.Visible=true;self:_layout_demo()
end
function Arsenal._layout_demo(self)
 if not self.demo_panel then return end
 self.demo_host.Position=UDim2.fromOffset(24,88);self.demo_host.Size=UDim2.new(1,-48,1,-190)
end
function Arsenal.hide_demo(self)
 if self.demo_overlay then self.demo_overlay.Visible=false end
 if self.demo then self.demo:destroy();self.demo=nil end
end
function Arsenal.frame(self,dt)
 if self.demo and self.is_open and self.demo_overlay.Visible then self.demo_elapsed+=math.min(dt,.2);self.demo:update(self.demo_elapsed)
 elseif self.inline_demo and self.is_open then self.inline_elapsed+=math.min(dt,.2);self.inline_demo:update(self.inline_elapsed) end
end
function Arsenal.open(self,focus,_from)
 self.is_open=true;self:set_visible(true);self.browser:open()
 local keys={};for _,it in Catalog.DISPLAY_ITEMS do keys[#keys+1]=it.product end;Prices.fetch_keys(keys)
 if focus and Demo.spec(focus) then self:select_equipment(focus) end
end
function Arsenal.close(self)
 if self.is_open then self.is_open=false;self:hide_demo();self.browser:close();self:set_visible(false);self.closed:Fire() end
end

return Arsenal
