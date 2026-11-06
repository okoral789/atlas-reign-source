--!nonstrict
-- The Locker (2026-09-29: cosmetic loot boxes of territory skins and flags to unlock):
-- a modal from the title with the crate card on the left and what you own on the right.
--   crate card  the crate art, "a territory skin or a flag you don't own yet", the player's own odds
--               per rarity (Cosmetics.odds, shown before every purchase: Roblox's paid random items
--               rules), how many items they own, and the button: 15 Robux for the first crate, 49
--               after (Data/Products), "Open" while a bought crate waits; under it three crates for
--               less (Data/Products crate3, _pack_saving). Hidden where paid random
--               items are restricted (Session.inventory.crates_allowed, PolicyService on the server).
--   grid        Skins / Flags tabs: every item (owned bright, the rest dimmed as a preview of what a
--               crate can give); press an owned one to wear it, "None" to wear nothing. An exclusive
--               skin (Cosmetics.exclusives) shows only to its owner, first, "EXCLUSIVE" in pink.
--   reveal      after a crate opens: the item in its rarity's colour, Equip / Open another / Done.
-- The purchase goes like the takeover's (Takeover.luau): Roblox's prompt, the server stores the crate
-- (server/Purchases), the client opens it (Session.open_crate), the server rolls it.
-- Signals: closed.
local UITheme = require("./UITheme")
local W = require("./Widgets")
local GlassPanel = require("./GlassPanel")
local L=require("./Look")
local Art=require(game:GetService("ReplicatedStorage").Airfront.Assets.Design)
local CrateOdds = require("./CrateOdds")
local UICtx = require("./UICtx")
local Signal = UITheme.core("Signal")

local IS_ROBLOX = typeof(game) == "Instance"
local function shared(name: string): any
	if IS_ROBLOX then
		return require((game :: any):GetService("ReplicatedStorage"):WaitForChild("Airfront").Data[name]) :: any
	end
	return (require :: any)("../../shared/Data/" .. name)
end
local Cosmetics = shared("Cosmetics")
local Products = shared("Products")
local Prices = require("./Prices")
local SkinPreviews: any = (function()
	local ok, m = pcall(function()
		if IS_ROBLOX then
			return require((game :: any):GetService("ReplicatedStorage"):WaitForChild("Airfront").Assets.SkinPreviews)
		end
		return (require :: any)("../../shared/Assets/SkinPreviews")
	end)
	return if ok and type(m) == "table" then m else {}
end)()

local Locker = W.class(W.Control)

Locker.TABS = { { "Skins", "skin" }, { "Flags", "flag" } }
Locker.SKIN_CARD = Vector2.new(116, 128)
Locker.FLAG_CARD = Vector2.new(104, 96)
Locker.GRID_SIZE = Vector2.new(560, 430)
Locker.CRATE_W = 250
--- the colour skins are previewed in (the player's own varies by match)
Locker.PREVIEW_COLOR = Color3.fromRGB(64, 132, 230)
Locker.PREVIEW_TILES = 24
Locker.CREDIT_WAIT_S = 30

local FONT = Font.fromId(12187365977, Enum.FontWeight.Bold)
local FONT_M = Font.fromId(12187365977, Enum.FontWeight.Medium)

local function c3(hex: number): Color3
	return Color3.fromRGB((hex // 65536) % 256, (hex // 256) % 256, hex % 256)
end

-- A skin's preview: its pattern in PREVIEW_COLOR over sand, the way the map draws it
-- (MapSurface: fill alpha 150, secondary Cosmetics.SECONDARY_ALPHA, a darker edge). Cached per skin.
local previews: { [string]: any } = {}
local function skin_preview(skin: any): any
	local cached = previews[skin.id]
	if cached ~= nil then
		return cached or nil
	end
	if not IS_ROBLOX then
		return nil
	end
	-- (a skin with several colours shows twice the tiles: its pattern is larger, as in the atlas)
	local n = if skin.colors ~= nil then Locker.PREVIEW_TILES * 2 else Locker.PREVIEW_TILES
	local ok, img = pcall(function()
		return game:GetService("AssetService"):CreateEditableImage({ Size = Vector2.new(n, n) })
	end)
	if not ok or img == nil then
		previews[skin.id] = false
		return nil
	end
	local mask, mw, mh = Cosmetics.mask(skin)
	local c = Locker.PREVIEW_COLOR
	local r, g, b = c.R, c.G, c.B
	local sr, sg, sb = Cosmetics.secondary(skin, r, g, b)
	local tr, tg, tb = 221 / 255, 205 / 255, 160 / 255
	local a1, a2 = 150 / 255, Cosmetics.SECONDARY_ALPHA / 255
	local buf = buffer.create(n * n * 4)
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			local cr, cg, cb, a
			if x == 0 or y == 0 or x == n - 1 or y == n - 1 then
				cr, cg, cb, a = r * 0.875, g * 0.875, b * 0.875, 1
			else
				local mx = bit32.rshift(x, skin.scale or 0) % mw
				local my = bit32.rshift(y, skin.scale or 0) % mh
				local k = buffer.readu8(mask, my * mw + mx)
				local kr, kg, kb
				if skin.colors ~= nil and k ~= 0 then
					kr, kg, kb = Cosmetics.color(skin, k)
				end
				if kr ~= nil then
					cr, cg, cb, a = kr, kg :: number, kb :: number, Cosmetics.skin_alpha(skin) / 255
				elseif k ~= 0 and skin.colors == nil then
					cr, cg, cb, a = sr, sg, sb, a2
				else
					cr, cg, cb, a = r, g, b, a1
				end
			end
			local k = (y * n + x) * 4
			buffer.writeu8(buf, k, math.floor((tr * (1 - a) + cr * a) * 255 + 0.5))
			buffer.writeu8(buf, k + 1, math.floor((tg * (1 - a) + cg * a) * 255 + 0.5))
			buffer.writeu8(buf, k + 2, math.floor((tb * (1 - a) + cb * a) * 255 + 0.5))
			buffer.writeu8(buf, k + 3, 255)
		end
	end
	local wrote = pcall(function()
		img:WritePixelsBuffer(Vector2.zero, Vector2.new(n, n), buf)
	end)
	previews[skin.id] = if wrote then img else false
	return if wrote then img else nil
end

--- Show item `it` in ImageLabel `img` (a skin's preview or a flag from its atlas).
local function show_item(img: ImageLabel, it: any)
	img.ImageRectOffset = Vector2.zero
	img.ImageRectSize = Vector2.zero
	img.ImageContent = Content.none
	img.Image = ""
	if it == nil then
		return
	end
	if it.kind == "flag" then
		img.ResampleMode = Enum.ResamplerMode.Default
		img.Image = Cosmetics.flag_image(it)
		img.ImageRectOffset = Vector2.new(it.x, it.y)
		img.ImageRectSize = Vector2.new(it.w, it.h)
	else
		img.ResampleMode = Enum.ResamplerMode.Pixelated
		-- the uploaded atlas (Assets/SkinPreviews); a runtime EditableImage only without it (phones can
		-- run out of EditableImage budget: an Epic reveal card came out empty live, 2026-09-29)
		local cell = SkinPreviews.cells and SkinPreviews.cells[it.id]
		if cell ~= nil and SkinPreviews.image then
			img.Image = SkinPreviews.image
			img.ImageRectOffset = Vector2.new(cell[1], cell[2])
			img.ImageRectSize = Vector2.new(cell[3], cell[4])
			return
		end
		local ed = skin_preview(it)
		if ed ~= nil then
			img.ImageContent = Content.fromObject(ed)
		end
	end
end
Locker.show_item = show_item

function Locker.new(c)
 local self=setmetatable({},Locker.__mt);W.Control._init(self)
 self.ctx=c;self.closed=Signal.new();self.is_open=false;self._tab="skin"
 self:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT);self:set_mouse_filter(W.MOUSE_STOP);self:set_visible(false)
 self.gui.ZIndex=35
 L.make("Frame",{BackgroundColor3=L.BG,BackgroundTransparency=.12,Size=UDim2.fromScale(1,1),BorderSizePixel=0},self.gui)
 local p=L.surface(self.gui,"COLLECTION","Make the map yours.",Vector2.new(920,650));self.panel=p
 L.button(p,"×",UDim2.new(1,-60,0,18),UDim2.fromOffset(36,36),function() self:close() end)
 self.body=L.make("ScrollingFrame",{Position=UDim2.fromOffset(24,96),Size=UDim2.new(1,-48,1,-116),BackgroundTransparency=1,BorderSizePixel=0,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),ScrollBarThickness=3,ScrollBarImageColor3=L.GOLD},p)
 local hero=L.make("Frame",{BackgroundColor3=L.RAISED,BorderSizePixel=0,Size=UDim2.new(1,-5,0,154)},self.body);L.round(hero,12)
 L.make("ImageLabel",{Image=Art.collection,BackgroundTransparency=1,Position=UDim2.fromOffset(4,0),Size=UDim2.fromOffset(140,150),ScaleType=Enum.ScaleType.Fit},hero)
 L.label(hero,"FIELD CASES",11,UDim2.fromOffset(148,12),UDim2.new(1,-156,0,22),L.GOLD,800)
 self.count=L.label(hero,"",15,UDim2.fromOffset(148,38),UDim2.new(1,-156,0,24))
 self.open_case=L.button(hero,"OPEN REWARD CASE",UDim2.fromOffset(148,78),UDim2.new(1,-160,0,40),function() self:_open() end,true)
 L.label(hero,"Earned from multiplayer victories.",11,UDim2.fromOffset(148,122),UDim2.new(1,-156,0,22),L.MUTED)
 self.tabs={}
 for i,row in {{"skin","TERRITORY & FLEET"},{"flag","FLAGS"}} do
  self.tabs[i]=L.button(self.body,row[2],UDim2.new((i-1)*.5,0,0,168),UDim2.new(.5,-7,0,38),function() self._tab=row[1];self:_rebuild() end)
 end
 self.grid=L.make("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(0,220),Size=UDim2.new(1,-6,0,0),AutomaticSize=Enum.AutomaticSize.Y},self.body)
 self.layout=L.make("UIGridLayout",{CellSize=UDim2.fromOffset(132,128),CellPadding=UDim2.fromOffset(10,10),SortOrder=Enum.SortOrder.LayoutOrder},self.grid)
 self.body:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:apply_layout() end)
 return self
end
function Locker._inv(self) return self.ctx.session.inventory end
function Locker._crates(self)
 local c=self.ctx.session.credits or {};return (c.free_crate or 0)+(if self:_inv().crates_allowed then c.crate or 0 else 0)
end
function Locker._offer(self)
 return {crates=self:_crates(),price=0,can_more=self:_crates()>0,wearing=function(slot) return self:_inv().equipped[slot] end}
end
function Locker.set_opening(self,o)
 self.opening=o;o.preview_of=skin_preview;o.show_item=show_item;o.info_of=function() return self:_offer() end
 o.wear:Connect(function(id) local it=Cosmetics.item(id);if it then self.ctx.session:equip(it.kind,id) end end)
 o.again:Connect(function() self:_open() end)
 o.closed:Connect(function(message) if message and self._toast then self:_toast(message) end;self:_refresh() end)
end
function Locker.bind(self,s)
 if self._bound==s then return end;self._bound=s
 s.inventory_changed:Connect(function() if self.is_open then self:_rebuild() end end)
 s.credits_changed:Connect(function() self:_refresh() end)
 s.crate_result:Connect(function(ok,id)
  if not self._pending then return end;self._pending=nil;self:_refresh()
  if self.opening then if ok then self.opening:resolve(id) else self.opening:fail("Your case is saved. Please retry.") end end
 end)
end
function Locker._open(self)
 if self._pending or self:_crates()<=0 then return end
 self._pending=os.clock();self:_refresh()
 if self.opening then self.opening:play(self:_offer()) end
 if not self.ctx.session:open_crate() then
  self._pending=nil;if self.opening then self.opening:fail("Could not reach the server. Your case is saved.") end;self:_refresh()
 end
end
function Locker._refresh(self)
 self.count.Text=tostring(self:_crates()).." CASES READY"
 self.open_case.Text=if self._pending then "OPENING…" elseif self:_crates()>0 then "OPEN REWARD CASE" else "WIN A MATCH TO EARN A CASE"
 self.open_case.Active=self._pending==nil and self:_crates()>0
 if self.opening and self.opening.is_open then self.opening:refresh_buttons() end
end
function Locker._rebuild(self)
 for _,c in self.grid:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
 local inv=self:_inv();local items={}
 for _,list in {Cosmetics.all(),Cosmetics.exclusives(),Cosmetics.generals(),Cosmetics.shop_items()} do
  for _,it in list do if it.kind==self._tab and inv.owned[it.id] then table.insert(items,it) end end
 end
 table.sort(items,function(a,b) return a.name<b.name end)
 table.insert(items,1,{id=false,name="Standard",kind=self._tab})
 for i,it in items do
  local worn=inv.equipped[self._tab]==it.id or (not it.id and not inv.equipped[self._tab])
  local b=L.button(self.grid,"",UDim2.new(),UDim2.fromOffset(132,128),function() self.ctx.session:equip(self._tab,it.id) end);b.LayoutOrder=i
  local img=L.make("ImageLabel",{BackgroundTransparency=1,Position=UDim2.fromOffset(12,6),Size=UDim2.new(1,-24,0,70),ScaleType=Enum.ScaleType.Fit},b)
  if it.id then show_item(img,it) else img.Image=Art.emblem end
  L.label(b,it.name,12,UDim2.fromOffset(10,78),UDim2.new(1,-20,0,22),L.INK,700)
  L.label(b,if worn then "EQUIPPED" else "EQUIP",10,UDim2.fromOffset(10,103),UDim2.new(1,-20,0,18),if worn then L.GOLD else L.MUTED,800)
 end
 self:_refresh();self:apply_layout()
end
function Locker.tick(self)
 if self._pending and os.clock()-self._pending>30 then
  self._pending=nil;if self.opening then self.opening:fail("Your case is saved. Reopen to retry.") end;self:_refresh()
 end
end
function Locker.open(self)
 if self.is_open then return end;self.is_open=true;self:set_visible(true);self:_rebuild();self.ctx:sfx("open")
end
function Locker.close(self)
 if not self.is_open then return end;self.is_open=false;self:set_visible(false);self.closed:Fire()
end
function Locker.apply_layout(self)
 local width=self.grid.AbsoluteSize.X
 local cols=math.max(2,math.floor((width+10)/142));self.layout.CellSize=UDim2.fromOffset(math.max(80,(width-(cols-1)*10)/cols),128)
end
return Locker
