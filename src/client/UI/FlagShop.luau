--!nonstrict
-- Frontier modifications, 2026-10-31; see NOTICE.md.
-- The flag shop (2026-10-22: a daily rotating shop of flags for sale; Data/Shop,
-- docs/flag-shop.md): a modal from the title's shop button. A running limited set first (Halloween:
-- the whole set, ENDS IN its clock), then today's flags (Data/Shop.daily, NEW IN the clock to 00:00 UTC).
-- Each card: the flag, its name and rarity, and its button: the price (Roblox's for this player:
-- UI/Prices), WEAR for one owned, WEARING for the one on. A purchase goes like the Locker's: Roblox's
-- prompt, the server stores the flag and puts it on (server/Purchases), the card turns to WEARING.
-- 2026-10-24 (from the analytics suggestions): a section's Legendary gets a FEATURED card two
-- cards wide and two tall, and a set with a bundle (Data/Shop.SETS `bundle`) a banner under its head:
-- all of it for one price, what that saves, flags already owned paying back Stars.
-- Signals: closed.
local UITheme = require("./UITheme")
local W = require("./Widgets")
local GlassPanel = require("./GlassPanel")
local UICtx = require("./UICtx")
local Prices = require("./Prices")
local PurchasePrompt = require("./PurchasePrompt")
local Signal = UITheme.core("Signal")

local IS_ROBLOX = typeof(game) == "Instance"
local function shared(name: string): any
	if IS_ROBLOX then
		return require((game :: any):GetService("ReplicatedStorage"):WaitForChild("Airfront").Data[name]) :: any
	end
	return (require :: any)("../../shared/Data/" .. name)
end
local Shop = shared("Shop")
local Cosmetics = shared("Cosmetics")
local ShopLayout = require("./ShopLayout")
local Products = shared("Products")
local ProfileStyle = shared("ProfileStyle")
local CountryStyle = shared("CountryStyle")

local FlagShop = W.class(W.Control)

--- A card, logical px (phones: CARD_PHONE).
FlagShop.CARD = Vector2.new(150, 178)
FlagShop.CARD_PHONE = Vector2.new(124, 152)
FlagShop.GAP = 10
--- Cards in a row on desktop (the window is as wide as that).
FlagShop.COLS = 4
--- After a purchase, how long the card waits for the server's word before saying it's on its way.
FlagShop.GRANT_WAIT_S = 30
--- The bundle banner's height (logical px).
FlagShop.BANNER_H = 46

local FONT = Font.fromId(UITheme.FONT_ID, Enum.FontWeight.Bold)
local FONT_H = Font.fromId(UITheme.FONT_ID, Enum.FontWeight.Heavy)
local FONT_M = Font.fromId(UITheme.FONT_ID, Enum.FontWeight.Medium)
local ROBUX = "rbxasset://textures/ui/common/robux@3x.png"
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 200, 61)
local PUMPKIN = Color3.fromRGB(255, 140, 40)
local MUTED = UITheme.TEXT_2

local function c3(hex: number): Color3
	return Color3.fromRGB((hex // 65536) % 256, (hex // 256) % 256, hex % 256)
end

local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(class)
	for k, v in props do
		(i :: any)[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end

-- The same native card surface is used by cosmetics, equipment and ladder rewards.
function FlagShop.card_surface(parent,name,pos,size,accent,selected,scale)
	local s=scale or UITheme.scale
	local card=new("Frame",{Name=name,BackgroundColor3=WHITE,Position=UDim2.fromOffset(math.floor(pos.X*s),math.floor(pos.Y*s)),Size=UDim2.fromOffset(math.floor(size.X*s),math.floor(size.Y*s)),ZIndex=41},parent)
	new("UICorner",{CornerRadius=UDim.new(0,10*s)},card)
	local stroke=new("UIStroke",{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Color=accent or GOLD,Thickness=if selected then 2 else 1},card)
	new("UIGradient",{Color=ColorSequence.new(Color3.fromRGB(59,38,96),UITheme.GLASS_SOLID.color),Rotation=90},card)
	return card,stroke
end

--- "5:12:09" under a day, "3d 4h" past it.
function FlagShop.clock(s: number): string
	s = math.max(0, math.floor(s))
	if s >= 86400 then
		return string.format("%dd %dh", s // 86400, (s % 86400) // 3600)
	end
	return string.format("%d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60)
end

--- Unix time as the server has it (every client agrees on the day).
function FlagShop.now(): number
	if IS_ROBLOX then
		local ok, t = pcall(function()
			return workspace:GetServerTimeNow()
		end)
		if ok and type(t) == "number" then
			return t
		end
	end
	return os.time()
end

--- What the shop shows at `t`: { day, sets = Shop.sets(t), daily = { keys } }.
function FlagShop.contents(t: number): any
	return { day = Shop.day(t), sets = Shop.sets(t), daily = Shop.daily(Shop.day(t)) }
end

--- The shop has something to sell here: a flag whose product exists (Studio: always).
function FlagShop.on_sale(): boolean
	return #Shop.flags() > 0
end

function FlagShop.new(c: any, armory: any?)
	local self = setmetatable({}, FlagShop.__mt)
	W.Control._init(self)
	self.ctx = c
	self.armory = armory
	self.closed = Signal.new()
	self.is_open = false
	self._cards = {}
	self._clocks = {}
	self._pending = nil
	self._filter = "featured"
	self._filters = {}
	self._filter_icons={}
	self._day = -1
	self._bound_conns = {}
	self:_connect(self.tree_exiting:Connect(function()
		self:bind(nil)
	end))
	self:_connect(Prices.changed:Connect(function()
		if self.is_open then
			self:_rebuild()
		end
	end))
	self:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	self:set_mouse_filter(W.MOUSE_STOP)
	self:set_visible(false)
	self._dim = W.ColorRect.new(UITheme.rgba(.06,.05,.04,.85))
	self._dim:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	self._dim.gui_input:Connect(function(e)
		-- (a press on the window's own ground reaches the dim too: only one outside it closes)
		if e.pressed and not self._panel:has_global_point(e.global_position) then
			self:close()
		end
	end)
	self:add_child(self._dim)
	self._panel = GlassPanel.new(22.0, 18.0, 18, true, 34)
	self._panel:set_tint(UITheme.GLASS_SOLID)
	self:add_child(self._panel)
	local v = UITheme.vbox(10)
	self._v = v
	self._panel:add_child(v)
	local head = UITheme.hbox(12)
	local art=require(game:GetService("ReplicatedStorage").Airfront.Assets.Design)
	local brand=Instance.new("Frame");brand.BackgroundTransparency=1
	require("./Artwork").new(brand,art.wordmark,art.wordmark_size,art.wordmark_rect,UDim2.new(),UDim2.fromScale(1,1))
	self._brand=W.wrap(brand);self._brand:set_min_size(Vector2.new(250,44));head:add_child(self._brand)
	local title = UITheme.label(if armory then "ARMORY" else "STYLE SHOP", 26, 900, UITheme.TEXT, 1)
	title.size_flags_vertical = W.SHRINK_CENTER
	title.size_flags_horizontal = W.EXPAND_FILL
	head:add_child(title)
	local close = W.Button.new("", "GhostButton")
	close:set_icon("close")
	close.expand_icon = true
	close:set_min_size(Vector2.new(34, 34))
	close:add_theme_constant_override("icon_max_width", 13)
	close:add_theme_stylebox_override("normal", UITheme.empty_box(8, 8))
	close:add_theme_stylebox_override("hover", UITheme.flat(UITheme.FILL, 8, UITheme.CLEAR, 0, 8, 8))
	close.size_flags_vertical = W.SHRINK_CENTER
	close.pressed:Connect(function()
		self:close()
	end)
	head:add_child(close)
	v:add_child(head)
	self._sub = UITheme.label("Preview, buy and equip in one place.",12,600,UITheme.TEXT_2)
	v:add_child(self._sub)
	local tabs=UITheme.hbox(8)
	for _,row in (if armory then {{"featured","ALL","globe"},{"strikes","STRIKES","atom"},{"support","SUPPORT","reinforce"},{"included","INCLUDED","check"}} else {{"featured","FEATURED","globe"},{"flags","FLAGS","layers"},{"colors","COLORS","settings"},{"patterns","BORDERS","layers"},{"owned","OWNED","check"}}) do
	 local b=UITheme.button(row[2],"GlassButton",row[3],36)
	 b.size_flags_horizontal=W.EXPAND_FILL;b:set_font_size(12)
	 b.pressed:Connect(function() self._filter=row[1];self._sf.CanvasPosition=Vector2.zero;self:apply_layout() end)
	 self._filters[row[1]]=b;tabs:add_child(b)
	 self._filter_icons[row[1]]=row[3]
	end
	v:add_child(tabs)
	local host = W.Control.new()
	host:set_mouse_filter(W.MOUSE_PASS)
	self._host = host
	v:add_child(host)
	local sf = Instance.new("ScrollingFrame")
	sf.Name = "FlagShopList"
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0
	sf.Size = UDim2.fromScale(1, 1)
	sf.ScrollBarThickness = 6
	sf.ScrollBarImageColor3 = WHITE
	sf.ScrollBarImageTransparency = 0.6
	sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sf.CanvasSize = UDim2.new(0, 0, 0, 0)
	sf.ScrollingDirection = Enum.ScrollingDirection.Y
	sf.ZIndex = 40
	sf.Parent = host.gui
	host:_part(sf, "ScrollBarImageTransparency", 0.4)
	self._sf = sf
	self._list = new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, sf)
	new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2) }, sf)
	if IS_ROBLOX then
		self:_connect(game:GetService("MarketplaceService").PromptProductPurchaseFinished:Connect(function(_u, product_id, purchased)
			self:_on_prompt_done(product_id, purchased)
		end))
		local player = game:GetService("Players").LocalPlayer
		if player then
			for _, attribute in { "AtlasCountryColor", "AtlasFlagFill" } do
				self:_connect(player:GetAttributeChangedSignal(attribute):Connect(function()
					if self:confirm_preview() and self.is_open then self:_rebuild() end
				end))
			end
		end
	end
	return self
end

--- The session's inventory (UIRoot.setup, when the session exists).
function FlagShop.bind(self, s: any)
	if self._bound == s and s ~= nil then
		return
	end
	self._applying = nil
	for _, connection in self._bound_conns do
		connection:Disconnect()
	end
	table.clear(self._bound_conns)
	self._bound = s
	if s == nil then
		return
	end
	if s.inventory_changed then
		table.insert(self._bound_conns, s.inventory_changed:Connect(function()
			self:_on_inventory()
		end))
	end
	if s.settings_loaded then
		table.insert(self._bound_conns, s.settings_loaded:Connect(function()
			if self.is_open then self:_rebuild() end
		end))
	end
end

--- A short notice (UIRoot sets this to its toasts).
function FlagShop._toast(_self, _text: string) end

function FlagShop._report(self, a: string, b: any?)
	local s = self.ctx.session
	if s ~= nil and type(s.report) == "function" then
		s:report("flag_shop", a, b)
	end
end

function FlagShop._inv(self): any
	local s = self.ctx.session
	return if s ~= nil and s.inventory ~= nil then s.inventory else { owned = {}, equipped = {} }
end

-- ---------------------------------------------------------------------------------------------
-- Buying and wearing
-- ---------------------------------------------------------------------------------------------

function FlagShop._pressed(self, key: string)
	if not self:ready() then self:_toast("Loading your saved inventory…");return end
	local id = Shop.item_id(key)
	local inv = self:_inv()
	local se = self.ctx.session
	if inv.owned[id] == true then
		if inv.equipped.flag ~= id and se ~= nil then
			self.ctx:sfx("click")
			se:equip("flag", id)
		end
		return
	end
	if self._pending ~= nil then
		return
	end
	local p = Products["shop_" .. key]
	if p == nil or p.id == 0 or not IS_ROBLOX then
		self.ctx:sfx("deny", -6.0)
		return
	end
	self:_report("clicked", key)
	self.ctx:sfx("click")
	self._pending = { key = key, product = p.id, phase = "prompt", since = os.clock() }
	self:_rebuild()
	local ok = pcall(function()
		PurchasePrompt.product(p.id)
	end)
	if not ok then
		self:_cancel("Purchases aren't available right now.")
	end
end

function FlagShop._pressed_color(self, index: number)
	if not self:ready() then self:_toast("Loading your saved style…");return end
	local session = self.ctx.session
	if session and (session.mode==1 or session.mode==2) then self:_toast("Return to the main menu to change your country color.");return end
	if not ProfileStyle.valid(index) then return end
	if not ProfileStyle.colors[index].premium and not ProfileStyle.allowed(index,self:_inv().owned) then return end
	if ProfileStyle.allowed(index, self:_inv().owned) then
		self:preview_item("color",index)
		return
	end
	if self._pending ~= nil then return end
	local product = Products[ProfileStyle.item_id(index)]
	if not IS_ROBLOX or product == nil or product.id == 0 then return end
	self._pending = { color = index, product = product.id, phase = "prompt", since = os.clock() }
	self:_rebuild()
	local ok = pcall(function()
		PurchasePrompt.product(product.id)
	end)
	if not ok then self:_cancel("Purchases aren't available right now.") end
end

--- A set's bundle (Products "shopset_<id>").
function FlagShop._pressed_set(self, sid: string)
	if self._pending ~= nil then
		return
	end
	local p = Products["shopset_" .. sid]
	if p == nil or p.id == 0 or not IS_ROBLOX then
		self.ctx:sfx("deny", -6.0)
		return
	end
	self:_report("clicked_pack", sid)
	self.ctx:sfx("click")
	self._pending = { set = sid, product = p.id, phase = "prompt", since = os.clock() }
	self:_rebuild()
	local ok = pcall(function()
		PurchasePrompt.product(p.id)
	end)
	if not ok then
		self:_cancel("Purchases aren't available right now.")
	end
end

--- How many of set `sid`'s flags the player owns, of how many.
function FlagShop._set_owned(self, sid: string): (number, number)
	local inv = self:_inv()
	local keys = Shop.set_keys(sid)
	local n = 0
	for _, k in keys do
		if inv.owned[Shop.item_id(k)] == true then
			n += 1
		end
	end
	return n, #keys
end

function FlagShop._cancel(self, message: string?)
	self._pending = nil
	if message then
		self:_toast(message)
	end
	if self.is_open then
		self:_rebuild()
	end
end

function FlagShop._on_prompt_done(self, product_id: number, purchased: boolean)
	local p = self._pending
	if p == nil or p.phase ~= "prompt" or product_id ~= p.product then
		return
	end
	if not purchased then
		self:_cancel(nil)
		return
	end
	-- bought: the server stores the flag and says so (the inventory)
	p.phase = "grant"
	p.since = os.clock()
	self:_on_inventory()
end

function FlagShop._on_inventory(self)
	self:confirm_preview()
	local p = self._pending
	if p and p.phase=="grant" and p.skin and self:_inv().owned[p.skin] then
  self._pending=nil;self:_toast("Fleet livery unlocked and equipped.")
 elseif p ~= nil and p.phase == "grant" and p.color ~= nil and ProfileStyle.allowed(p.color, self:_inv().owned) then
		self._pending = nil
		self:preview_item("color",p.color)
		self.ctx:sfx("confirm")
		self:_toast("Gradient unlocked. Preview it, then equip your complete look.")
	elseif p ~= nil and p.phase == "grant" and p.set ~= nil then
		local n, of = self:_set_owned(p.set)
		if n >= of then
			self._pending = nil
			local set = Shop.SETS[p.set]
			self.ctx:sfx("confirm")
			self:_toast(string.format("All %d %s flags are yours.", of, if set then set.name else ""))
		end
	elseif p ~= nil and p.key ~= nil and p.phase == "grant" and self:_inv().owned[Shop.item_id(p.key)] == true then
		self._pending = nil
		local f = Shop.flag(p.key)
		self.ctx:sfx("confirm")
		self:_toast((if f then f.name else "Your flag") .. " is yours: you're wearing it now.")
	end
	if self.is_open then
		self:_rebuild()
	end
end

function FlagShop.tick(self)
	local p = self._pending
	if p ~= nil then
		local limit = if p.phase == "prompt" then 180 else FlagShop.GRANT_WAIT_S
		if os.clock() - p.since > limit then
			self:_cancel(if p.phase == "prompt" then nil else "Your cosmetic is on its way: it shows up in a moment.")
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- The list
-- ---------------------------------------------------------------------------------------------

function FlagShop._card_size(self): Vector2
	if self.armory then return if self.ctx.compact then Vector2.new(164,244) else Vector2.new(224,280) end
	return if self.ctx.compact then FlagShop.CARD_PHONE else FlagShop.CARD
end

function FlagShop._section(self, order: number, title: string, color: Color3, ends: number, label: string)
	local s = UITheme.scale
	local row = new("Frame", {
		Name = "Head",
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Size = UDim2.new(1, -math.floor(12 * s), 0, math.floor(30 * s)),
		ZIndex = 41,
	}, self._sf)
	local t = new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = FONT_H,
		Text = title,
		TextColor3 = color,
		TextSize = math.floor(15 * s),
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(0.62, 1),
		ZIndex = 42,
	}, row)
	local clock = new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = FONT,
		Text = "",
		TextColor3 = MUTED,
		TextSize = math.floor(12 * s),
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.38, 1),
		ZIndex = 42,
	}, row)
	table.insert(self._clocks, { label = clock, ends = ends, prefix = label })
	self._host:_part(t, "TextTransparency", 1.0)
	self._host:_part(clock, "TextTransparency", 1.0)
	table.insert(self._cards, row)
end

function FlagShop._grid(self, order: number, keys: { string })
	local s = UITheme.scale
	local cs = self:_card_size()
	local gap = FlagShop.GAP
	local list = ShopLayout.order(keys)
	local hero = false
	local cells, rows = ShopLayout.place(#list, hero, self._cols or FlagShop.COLS)
	local g = new("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Size = UDim2.new(1, -math.floor(12 * s), 0, math.floor((rows * cs.Y + (rows - 1) * gap + 14) * s)),
		ZIndex = 41,
	}, self._sf)
	for i, key in list do
		local c = cells[i]
		local big = hero and i == 1
		local size = if big then Vector2.new(cs.X * 2 + gap, cs.Y * 2 + gap) else cs
		self:_card(g, key, Vector2.new(c[1] * (cs.X + gap), c[2] * (cs.Y + gap)), size, big)
	end
	table.insert(self._cards, g)
end

function FlagShop._color_grid(self, order: number)
 local s,cs=UITheme.scale,self:_card_size()
 local indices=ProfileStyle.shop_indices();local cols=self._cols or FlagShop.COLS
 local grid=new("Frame",{Name="ProfileColors",BackgroundTransparency=1,LayoutOrder=order,Size=UDim2.new(1,0,0,(34+math.ceil(#indices/cols)*(cs.Y+FlagShop.GAP))*s),ZIndex=41},self._sf)
 local head=new("TextLabel",{BackgroundTransparency=1,Text="EXCLUSIVE COUNTRY COLORS",FontFace=FONT_H,TextSize=14*s,TextColor3=GOLD,TextXAlignment=Enum.TextXAlignment.Left,Size=UDim2.new(1,0,0,26*s),ZIndex=42},grid)
 self._host:_part(head,"TextTransparency",1)
 for n,index in indices do
  self:_card(grid,ProfileStyle.item_id(index),Vector2.new((n-1)%cols*(cs.X+FlagShop.GAP),34+math.floor((n-1)/cols)*(cs.Y+FlagShop.GAP)),cs,false,{kind="color",index=index})
 end
 table.insert(self._cards,grid)
end

--- A set's bundle under its head: ALL 6 HALLOWEEN FLAGS, what it saves at this player's prices, and
--- its price (shown while the player is missing any of the set and its product exists here).
--- Set `sid`'s bundle banner shows: it has a bundle, its product exists here (Studio: always), and the
--- player is missing some of the set.
function FlagShop._bundle_shown(self, sid: string): boolean
	local set = Shop.SETS[sid]
	local p = Products["shopset_" .. sid]
	if set == nil or set.bundle == nil or p == nil then
		return false
	end
	if p.id == 0 and not (IS_ROBLOX and game:GetService("RunService"):IsStudio()) then
		return false
	end
	local have, of = self:_set_owned(sid)
	return have < of
end

function FlagShop._bundle(self, order: number, sid: string)
	if not self:_bundle_shown(sid) then
		return
	end
	local set = Shop.SETS[sid]
	local key = "shopset_" .. sid
	local have, of = self:_set_owned(sid)
	local s = UITheme.scale
	local px = function(v: number): number
		return math.floor(v * s + 0.5)
	end
	local each = 0
	for _, k in Shop.set_keys(sid) do
		each += Prices.robux("shop_" .. k)
	end
	local price = Prices.robux(key)
	local off = if each > 0 then math.floor((1 - price / each) * 100 + 0.5) else 0
	local pending = self._pending ~= nil and self._pending.set == sid
	local h = FlagShop.BANNER_H
	local row = new("Frame", {
		Name = "Bundle",
		BackgroundColor3 = WHITE,
		LayoutOrder = order,
		Size = UDim2.new(1, -px(12), 0, px(h + 10)),
		BackgroundTransparency = 1,
		ZIndex = 41,
	}, self._sf)
	local box = new("Frame", {
		Name = "Box",
		BackgroundColor3 = WHITE,
		Size = UDim2.new(1, 0, 0, px(h)),
		ZIndex = 41,
	}, row)
	new("UICorner", { CornerRadius = UDim.new(0, px(10)) }, box)
	new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(120, 52, 10), Color3.fromRGB(40, 18, 60)),
		Rotation = 0,
	}, box)
	local stroke =
		new("UIStroke", { Color = PUMPKIN, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, box)
	local title = new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = FONT_H,
		Text = string.format("ALL %d %s FLAGS", of, string.upper(set.name)),
		TextColor3 = WHITE,
		TextSize = px(14),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(px(14), px(6)),
		Size = UDim2.new(1, -px(150), 0, px(18)),
		ZIndex = 42,
	}, box)
	local sub = new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = FONT,
		Text = (if off > 0 then string.format("Save %d%%", off) else "One price")
			.. (if have > 0 then "  ·  ones you own pay back Credits" else ""),
		TextColor3 = Color3.fromRGB(120, 230, 150),
		TextSize = px(11),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(px(14), px(25)),
		Size = UDim2.new(1, -px(150), 0, px(14)),
		ZIndex = 42,
	}, box)
	local btn = new("TextButton", {
		Name = "BuyAll",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = UITheme.AMBER,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -px(8), 0.5, 0),
		Size = UDim2.fromOffset(px(124), px(h - 14)),
		ZIndex = 43,
	}, box)
	new("UICorner", { CornerRadius = UDim.new(0, px(8)) }, btn)
	local inner = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 44 }, btn)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, px(4)),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, inner)
	local icon = new("ImageLabel", {
		BackgroundTransparency = 1,
		Image = ROBUX,
		Size = UDim2.fromOffset(px(15), px(15)),
		LayoutOrder = 1,
		Visible = not pending,
		ZIndex = 45,
	}, inner)
	local label = new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = FONT_H,
		Text = if pending then "..." else tostring(price),
		TextColor3 = WHITE,
		TextSize = px(15),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, px(h - 14)),
		LayoutOrder = 2,
		ZIndex = 45,
	}, inner)
	local host = self._host
	host:_part(box, "BackgroundTransparency", 1.0)
	host:_part(stroke, "Transparency", 0.8)
	host:_part(title, "TextTransparency", 1.0)
	host:_part(sub, "TextTransparency", 1.0)
	host:_part(btn, "BackgroundTransparency", 1.0)
	host:_part(icon, "ImageTransparency", 1.0)
	host:_part(label, "TextTransparency", 1.0)
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = UITheme.AMBER_HI
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = UITheme.AMBER
	end)
	btn.Activated:Connect(function()
		self:_pressed_set(sid)
	end)
	table.insert(self._cards, row)
end

function FlagShop._card(self, parent: Instance, key: string, pos: Vector2, size: Vector2, hero: boolean,offer: any?)
	local color=offer and offer.kind=="color"
	local pattern=offer and offer.kind=="pattern"
	local ownflag=offer and offer.kind=="flag"
	local entry=if color then ProfileStyle.colors[offer.index] else nil
	local f = if offer then {name=if color then entry.name else offer.item.name,rarity=if color then "legendary" else offer.item.rarity} else Shop.flag(key)
	local it = if color then {id=key} elseif pattern or ownflag then offer.item else Cosmetics.item(Shop.item_id(key))
	if f == nil or it == nil then
		return
	end
	local s = UITheme.scale
	local px = function(v: number): number
		return math.floor(v * s + 0.5)
	end
	local cs = size
	local inv = self:_inv()
	local owned = if color then ProfileStyle.allowed(offer.index,inv.owned) else inv.owned[it.id] == true
	local wearing = if color then self.ctx.session:load_settings("frontier_country").color==offer.index elseif pattern then inv.equipped.skin==it.id else inv.equipped.flag == it.id
	local pending = self._pending ~= nil and (self._pending.key == key or (pattern and self._pending.skin==key) or (color and self._pending.color==offer.index))
	local rar = Cosmetics.rarity(f.rarity)
	local rc = c3(rar.color)
	local card,stroke=FlagShop.card_surface(parent,key,pos,size,if wearing then UITheme.AMBER else rc,wearing or hero)
	local fw = cs.X - 16
	local fh = math.floor(fw * 2 / 3)
	local img = new(if color or pattern then "Frame" else "ImageLabel", {
		Name = "Flag",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(px(8), px(8)),
		Size = UDim2.fromOffset(px(fw), px(fh)),
		ZIndex = 42,
	}, card)
	if not offer or ownflag then
	 local image,x,y,w,h=Cosmetics.flag_big(it);img.Image=image;img.ImageRectOffset=Vector2.new(x,y);img.ImageRectSize=Vector2.new(w,h)
	elseif color then
	 img.Name="PremiumColorPreview";img.BackgroundTransparency=0;img.BackgroundColor3=c3(entry.rgb)
	 img.BackgroundColor3=WHITE
	 local stops={};for i,value in entry.gradient or {entry.rgb,entry.rgb} do stops[#stops+1]=ColorSequenceKeypoint.new((i-1)/(#(entry.gradient or {entry.rgb,entry.rgb})-1),c3(value)) end
	 new("UIGradient",{Color=ColorSequence.new(stops),Rotation=35},img)
	 local emblem=require("./Look").badge(img,"customize",UDim2.new(.5,-px(26),.5,-px(26)),UDim2.fromOffset(px(52),px(52)))
	else
	 img.Name="PremiumPatternPreview"
	 local chosen=self.ctx.session:load_settings("frontier_country").color
	 local color=if ProfileStyle.valid(chosen) and chosen>1 then c3(ProfileStyle.colors[chosen].rgb) else UITheme.CYAN
	 local preview=require("./PatternPreview").new(img,it,color,UDim2.new(),UDim2.fromScale(1,1))
	 if it.effect then self._animated=self._animated or {};table.insert(self._animated,preview) end
	end
	new("UICorner", { CornerRadius = UDim.new(0, px(6)) }, img)
	local name_size = if hero then (if self.ctx.compact then 15 else 18) else (if self.ctx.compact then 11 else 13)
	local name = new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = if hero then FONT_H else FONT,
		Text = f.name,
		TextColor3 = WHITE,
		TextSize = px(name_size),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(px(8), px(8 + fh + 5)),
		Size = UDim2.fromOffset(px(cs.X - 16), px(name_size + 4)),
		ZIndex = 42,
	}, card)
	local sub = new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = FONT_M,
		Text = if color then "PREMIUM GRADIENT" elseif pattern then (if it.banner then "INCLUDED WITH FLAG" elseif it.border then "BORDER + FLEET ACCENT" else "CLASSIC TERRITORY") else (if Cosmetics.banner_for(it.id) then "FLAG + COUNTRY MOTIF" else "CLASSIC NAMEPLATE FLAG"),
		TextColor3 = rc,
		TextSize = px(if hero then 12 else 10),
		Position = UDim2.fromOffset(px(8), px(8 + fh + 9 + name_size)),
		Size = UDim2.fromOffset(px(cs.X - 16), px(14)),
		ZIndex = 42,
	}, card)
	if hero then
		-- the FEATURED chip over the flag's corner
		local chip = new("TextLabel", {
			BackgroundColor3 = GOLD,
			FontFace = FONT_H,
			Text = "FEATURED",
			TextColor3 = Color3.fromRGB(40, 24, 0),
			TextSize = px(11),
			Position = UDim2.fromOffset(px(14), px(14)),
			Size = UDim2.fromOffset(px(78), px(20)),
			ZIndex = 44,
		}, card)
		new("UICorner", { CornerRadius = UDim.new(0, px(6)) }, chip)
		self._host:_part(chip, "BackgroundTransparency", 1.0)
		self._host:_part(chip, "TextTransparency", 1.0)
	end
	-- the button: the price, WEAR / WEARING, or a moment's wait
	local bh = if hero then (if self.ctx.compact then 32 else 38) else (if self.ctx.compact then 26 else 30)
	local btn = new("TextButton", {
		Name = "Buy",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = if owned then UITheme.GLASS_RAISED.color else UITheme.AMBER,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -px(8)),
		Size = UDim2.fromOffset(px(cs.X - 16), px(bh)),
		ZIndex = 43,
	}, card)
	new("UICorner", { CornerRadius = UDim.new(0, px(8)) }, btn)
	local row = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 44,
	}, btn)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, px(4)),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	local text = if wearing then "EQUIPPED" elseif owned then "TRY ON" elseif pending then "..." else nil
	local parts = { btn }
	if text == nil then
		text = "R$ " .. tostring(Prices.robux(if color then key elseif pattern then "skin_"..key else "shop_"..key))
	end
	local label = new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = FONT_H,
		Text = text,
		TextColor3 = if owned then UITheme.AMBER else Color3.fromRGB(5,19,33),
		TextSize = px(if hero then 17 else 14),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, px(bh)),
		LayoutOrder = 2,
		ZIndex = 45,
	}, row)
	local host = self._host
	host:_part(card, "BackgroundTransparency", 1.0)
	host:_part(stroke, "Transparency", if wearing then 1.0 else 0.55)
	if not offer or ownflag then host:_part(img,"ImageTransparency",1) else
	 for _,d in img:GetDescendants() do if d:IsA("ImageLabel") then host:_part(d,"ImageTransparency",1) elseif d:IsA("Frame") and d.BackgroundTransparency==0 then host:_part(d,"BackgroundTransparency",1) end end
	 if color then host:_part(img,"BackgroundTransparency",1) end
	end
	host:_part(name, "TextTransparency", 1.0)
	host:_part(sub, "TextTransparency", 1.0)
	host:_part(label, "TextTransparency", 1.0)
	for _, pt in parts do
		if pt:IsA("ImageLabel") then
			host:_part(pt, "ImageTransparency", 1.0)
		else
			host:_part(pt, "BackgroundTransparency", if wearing then 0.6 else 1.0)
		end
	end
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = if owned then UITheme.GLASS_RAISED.color else UITheme.AMBER_HI
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = if owned then UITheme.GLASS_RAISED.color else UITheme.AMBER
	end)
	btn.Activated:Connect(function()
		if owned then self:preview_item(if color then "color" elseif pattern then "skin" else "flag",if color then offer.index else it.id);return end
		if color then self:_pressed_color(offer.index) elseif pattern then self:_pressed_skin(key) elseif ownflag then self.ctx.session:equip("flag",it.id) else self:_pressed(key) end
	end)
	local inspect=new("TextButton",{Name="Preview",Text="",BackgroundTransparency=1,Position=img.Position,Size=img.Size,ZIndex=44},card)
	inspect.Activated:Connect(function() self:preview_item(if color then "color" elseif pattern then "skin" else "flag",if color then offer.index else it.id) end)
	return card
end

function FlagShop._pressed_skin(self,id)
 if not self:ready() then self:_toast("Loading your saved inventory…");return end
 local item=Cosmetics.item(id);if not item or item.kind~="skin" then return end
 if self:_inv().owned[id] then self.ctx.session:equip("skin",id);return end
 if not item.shop or item.banner then return end
 if self._pending then return end
 local p=Products["skin_"..id];if not p or p.id==0 then return end
 self._pending={skin=id,product=p.id,phase="prompt",since=os.clock()};self:_rebuild()
 local ok=pcall(PurchasePrompt.product,p.id)
 if not ok then self:_cancel("Purchases unavailable. Please retry.") end
end

function FlagShop._fleet_grid(self,order)
 local styles=shared("FleetStyles");local s,cs=UITheme.scale,self:_card_size();local cols=self._cols or FlagShop.COLS
 local row=new("Frame",{Name="FleetLiveries",BackgroundTransparency=1,LayoutOrder=order,Size=UDim2.new(1,0,0,(34+math.ceil(#styles/cols)*(cs.Y+FlagShop.GAP))*s),ZIndex=41},self._sf)
	local head=new("TextLabel",{BackgroundTransparency=1,Text="NEON, FLAME & SIGNATURE BORDERS",FontFace=FONT_H,TextSize=14*s,TextColor3=GOLD,TextXAlignment=Enum.TextXAlignment.Left,Size=UDim2.new(1,0,0,26*s),ZIndex=42},row)
 self._host:_part(head,"TextTransparency",1)
 for i,style in styles do
  self:_card(row,style.id,Vector2.new((i-1)%cols*(cs.X+FlagShop.GAP),34+math.floor((i-1)/cols)*(cs.Y+FlagShop.GAP)),cs,false,{kind="pattern",item=Cosmetics.item(style.id)})
 end
 table.insert(self._cards,row)
end

function FlagShop.track_card(self,root)
	for _,d in root:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then self._host:_part(d,"TextTransparency",1) end
		if d:IsA("ImageLabel") then self._host:_part(d,"ImageTransparency",1) end
		if d:IsA("GuiObject") and d.BackgroundTransparency<1 then self._host:_part(d,"BackgroundTransparency",1-d.BackgroundTransparency) end
	end
	self._host:_part(root,"BackgroundTransparency",1-root.BackgroundTransparency)
end

function FlagShop.current_style(self)
	local inv=self:_inv();local saved=self.ctx.session:load_settings("frontier_country")
	local skin=Cosmetics.item(inv.equipped.skin);local legacy=skin and skin.banner==true
	return {color=if CountryStyle.allowed(saved.color,inv.owned) then saved.color else 0,skin=if legacy then false else inv.equipped.skin or false,flag=inv.equipped.flag or false,flag_fill=saved.flag_fill==true or legacy==true}
end
function FlagShop.ready(self)
	return self:_inv().loaded==true and self.ctx.session.settings_ready==true
end
function FlagShop.preview_item(self,kind,value)
	if not self:ready() then self:_toast("Loading your saved style…");return end
	if self.ctx.sfx then self.ctx:sfx("tab",-5) end
	self.preview_pick=self.preview_pick or self:current_style();self.preview_pick[kind]=value
	if kind=="flag" then self.preview_pick.flag_fill=Cosmetics.banner_for(value)~=nil end
	self:_update_showcase()
end
function FlagShop.apply_preview(self)
	local pick=self.preview_pick;local session=self.ctx.session;local inv=self:_inv()
	if not self:ready() or not pick or self._applying then return false end
	if session.mode==1 or session.mode==2 then self:_toast("Return to the main menu to apply a complete look.");return false end
	if not CountryStyle.allowed(pick.color,inv.owned) or (pick.skin and not inv.owned[pick.skin]) or (pick.flag and not inv.owned[pick.flag]) then self:_toast("Unlock this style before equipping it.");return false end
	if not session.env or not session.env.net or not session.env.net.connected then self:_toast("Could not reach the server. Reconnect and retry.");return false end
	self._applying=table.clone(pick)
	local request=self._applying
	session:save_settings("frontier_country",{color=pick.color,flag_fill=pick.flag_fill==true});session:equip("skin",pick.skin);session:equip("flag",pick.flag)
	self:_toast("Applying your style…")
	task.delay(12,function() if self._applying==request then self._applying=nil;self:_toast("Still waiting for confirmation. Your saved inventory is safe; retry when connected.") end end)
	return true
end
function FlagShop.confirm_preview(self)
	local pick=self._applying;if not pick then return end
	local player=if IS_ROBLOX then game:GetService("Players").LocalPlayer else nil
	local eq=self:_inv().equipped
	if player and player:GetAttribute("AtlasCountryColor")==pick.color and (player:GetAttribute("AtlasFlagFill")==true)==(pick.flag_fill==true) and (eq.skin or false)==pick.skin and (eq.flag or false)==pick.flag then
		self._applying=nil;self.preview_pick=nil;self:_toast("Style saved. Ready for your next match.")
		return true
	end
end
function FlagShop._showcase(self)
	local L=require("./Look");local P=require("./PatternPreview")
	local s=UITheme.scale
	local row=new("Frame",{Name="StyleLoadout",LayoutOrder=0,BackgroundTransparency=1,Size=UDim2.new(1,-12*s,0,216*s),ZIndex=41},self._sf)
	local map,cells=P.country(row,UDim2.new(),UDim2.new(.48,-8*s,1,-8*s))
	self.preview_map=map;self.preview_cells=cells
	local detail=L.make("Frame",{BackgroundTransparency=1,Position=UDim2.new(.5,0,0,0),Size=UDim2.new(.5,0,1,0),ZIndex=42},row)
	local heading=L.label(detail,"",17*s,UDim2.fromOffset(0,4*s),UDim2.new(1,0,0,26*s),GOLD,900)
	local description=L.label(detail,"",11*s,UDim2.fromOffset(0,34*s),UDim2.new(1,0,0,44*s),WHITE,600)
	description.TextWrapped=true
	local use=L.button(detail,"",UDim2.fromOffset(0,86*s),UDim2.new(1,-5*s,0,30*s),function()
		self:apply_preview()
	end,true);use.TextSize=11*s
	local fill=L.button(detail,"",UDim2.fromOffset(0,122*s),UDim2.new(1,-5*s,0,30*s),function()
		if not self:ready() then self:_toast("Loading your saved style…");return end
		local pick=self.preview_pick or self:current_style()
		local banner=Cosmetics.banner_for(pick.flag)
		if banner then
			if not self:_inv().owned[banner.id] then self:_toast("Unlock this flag to use its included territory fill.");return end
			self.preview_pick=table.clone(pick);self.preview_pick.flag_fill=not pick.flag_fill;self:_update_showcase()
		end
	end);fill.TextSize=10*s
	L.button(detail,"RESET LOOK",UDim2.fromOffset(0,158*s),UDim2.new(1,-5*s,0,26*s),function() self.preview_pick={color=0,flag=false,skin=false,flag_fill=false};self:_update_showcase() end).TextSize=10*s
	L.label(detail,"Gradient + flag overlay + border · next match",9*s,UDim2.fromOffset(0,191*s),UDim2.new(1,0,0,18*s),UITheme.TEXT_2)
	self:track_card(row);table.insert(self._cards,row)
	self._showcase_ui={heading=heading,description=description,use=use,fill=fill}
	self:_update_showcase()
end

function FlagShop._update_showcase(self)
	local ui=self._showcase_ui
	if not ui then return end
	local P=require("./PatternPreview")
	local pick=self.preview_pick or self:current_style()
	local color=if ProfileStyle.valid(pick.color) and pick.color>1 then c3(ProfileStyle.colors[pick.color].rgb) else UITheme.CYAN
	local skin=Cosmetics.item(pick.skin);local flag=Cosmetics.item(pick.flag)
	P.update(self.preview_cells,skin,color,pick)
	if ui.skin~=skin or (skin and skin.effect and not ui.effect_label) then
		if ui.effect_label then self._host:_drop_part(ui.effect_label) end
		ui.skin=skin
		if skin and skin.effect then
			ui.effect_label=P.add_effect(self.preview_map,skin.effect,self.preview_cells,if skin.effect~="flame" then c3(skin.fleet_tint) else nil)
			if ui.effect_label then self._host:_part(ui.effect_label,"ImageTransparency",1) end
		else
			P.clear_effect(self.preview_map)
			ui.effect_label=nil
		end
	end
	ui.heading.Text=if self.preview_pick then "TRY YOUR LOOK" else "YOUR COUNTRY"
	ui.description.Text=(skin and skin.name or "Standard border").."\n"..(flag and flag.name or "No flag").." · "..(if pick.color==0 then "Random color" else ProfileStyle.colors[pick.color].name)
	local owned=self:_inv().owned
	local can_equip=(pick.color==0 or ProfileStyle.allowed(pick.color,owned)) and (not pick.skin or owned[pick.skin]) and (not pick.flag or owned[pick.flag])
	ui.use.Text=if self.preview_pick then (if can_equip then "EQUIP THIS LOOK" else "PREVIEW · BUY FROM CARD") else "✓ EQUIPPED LOOK"
	ui.use.Active=self.preview_pick~=nil and can_equip
	ui.fill.Text=if Cosmetics.banner_for(pick.flag) then (if pick.flag_fill then "FLAG ON MAP: ON  ·  TURN OFF" else "FLAG ON MAP: OFF  ·  TURN ON") else "SELECT A FLAG TO SPREAD ON THE MAP"
end

function FlagShop._owned_grid(self,order)
	local entries={};local inv=self:_inv()
	for id in inv.owned do
		local it=Cosmetics.item(id)
		if it and not it.banner and (it.kind=="skin" or it.kind=="flag") then entries[#entries+1]={key=id,item=it,kind=if it.kind=="skin" then "pattern" else "flag"}
		elseif it and it.kind=="profile_color" then
			local index=tonumber(id:match("(%d+)$"));if ProfileStyle.valid(index) then entries[#entries+1]={key=id,kind="color",index=index,item=it} end
		end
	end
	table.sort(entries,function(a,b) return a.item.name<b.item.name end)
	local s,cs=UITheme.scale,self:_card_size();local cols=self._cols or 4
	local pageSize=24;local pages=math.max(1,math.ceil(#entries/pageSize));self._owned_page=math.clamp(self._owned_page or 1,1,pages)
	local first=(self._owned_page-1)*pageSize+1;local last=math.min(#entries,first+pageSize-1);local height=math.max(42,math.ceil((last-first+1)/cols)*(cs.Y+FlagShop.GAP))
	local root=new("Frame",{Name="OwnedStyles",BackgroundTransparency=1,LayoutOrder=order,Size=UDim2.new(1,0,0,(height+(if pages>1 then 44 else 0))*s),ZIndex=41},self._sf)
	for index=first,last do local entry=entries[index];local i=index-first+1;self:_card(root,entry.key,Vector2.new((i-1)%cols*(cs.X+FlagShop.GAP),math.floor((i-1)/cols)*(cs.Y+FlagShop.GAP)),cs,false,entry) end
	if pages>1 then
	 local L=require("./Look")
	 for _,nav in {{"‹ PREVIOUS",-1,0},{"NEXT ›",1,.67}} do
	  L.button(root,nav[1],UDim2.new(nav[3],0,0,height*s),UDim2.new(.33,-4*s,0,34*s),function() self._owned_page=math.clamp(self._owned_page+nav[2],1,pages);self:_rebuild();self._sf.CanvasPosition=Vector2.zero end)
	 end
	 L.label(root,self._owned_page.." / "..pages,12*s,UDim2.new(.34,0,0,height*s),UDim2.new(.32,0,0,34*s),GOLD).TextXAlignment=Enum.TextXAlignment.Center
	 self:track_card(root)
	end
	if #entries==0 then local t=new("TextLabel",{BackgroundTransparency=1,Text="Your collection starts here. Preview any style, or reset to the free default look above.",TextWrapped=true,FontFace=FONT,TextColor3=WHITE,TextSize=12*s,Size=UDim2.fromScale(1,1),ZIndex=42},root);self._host:_part(t,"TextTransparency",1) end
	table.insert(self._cards,root)
end

function FlagShop._rebuild(self)
	self._sub:set_text("Preview, buy and equip here. Permanent cosmetics · no combat advantage.")
	for key,b in self._filters do
	 b:add_theme_stylebox_override("normal",UITheme.flat(if key==self._filter then UITheme.c(UITheme.AMBER,.18) else UITheme.FILL,8,if key==self._filter then UITheme.AMBER else UITheme.LINE,1,12,6))
	end
	for _, b in self._cards do
		self._host:_drop_part(b)
		for _, d in b:GetDescendants() do
			self._host:_drop_part(d)
		end
		b:Destroy()
	end
	table.clear(self._cards)
	table.clear(self._clocks)
	self._showcase_ui=nil
	self.preview_map=nil;self.preview_cells=nil
	self._animated={}
	if self.armory then self._day=Shop.day(FlagShop.now());self.armory:render_shop(self);return end
	self:_showcase()
	if self._filter=="owned" then self:_owned_grid(1);return end
	local t = FlagShop.now()
	local c = FlagShop.contents(t)
	self._day = c.day
	local keys = {}
	local order = 1
 if self._filter=="featured" or self._filter=="flags" then
	for _, set in (if self._filter=="flags" then c.sets else {}) do
		order += 1
		self:_section(order, string.upper(set.name) .. "  ·  LIMITED", PUMPKIN, set.ends, "ENDS IN ")
		order += 1
		self:_bundle(order, set.id)
		order += 1
		self:_grid(order, set.keys)
		for _, k in set.keys do
			table.insert(keys, "shop_" .. k)
		end
		table.insert(keys, "shopset_" .. set.id)
	end
	order += 1
	self:_section(order, if self._filter=="flags" then "CREST COLLECTION + TODAY'S FLAGS" else "TODAY'S FLAGS", WHITE, (c.day + 1) * Shop.DAY_S, "NEW IN ")
	order += 1
	local daily=table.clone(c.daily)
	if self._filter=="flags" then daily={};for _,flag in Shop.flags() do if flag.theme=="Crests" or table.find(c.daily,flag.key) then daily[#daily+1]=flag.key end end end
	if self._filter=="featured" then while #daily>4 do table.remove(daily) end end
	self:_grid(order, daily)
	for _, k in daily do
		table.insert(keys, "shop_" .. k)
	end
	end
	if self._filter=="featured" or self._filter=="colors" then
	order += 1
	self:_color_grid(order)
	for index = 2, #ProfileStyle.colors do table.insert(keys, ProfileStyle.item_id(index)) end
	end
	if self._filter=="featured" or self._filter=="patterns" then
	 order+=1;self:_fleet_grid(order)
	 for _,style in require(game:GetService("ReplicatedStorage").Airfront.Data.FleetStyles) do table.insert(keys,"skin_"..style.id) end
	end
	Prices.fetch_keys(keys)
	self:_tick_clocks(t)
end

function FlagShop._tick_clocks(self, t: number)
	for _, cl in self._clocks do
		cl.label.Text = cl.prefix .. FlagShop.clock(cl.ends - t)
	end
end

function FlagShop._process(self, _dt: number)
	if not self.is_open then
		return
	end
	local t = FlagShop.now()
	if Shop.day(t) ~= self._day then
		self:_rebuild() -- (midnight UTC: the shop turned over)
		return
	end
	self:_tick_clocks(t)
	local preview=require("./PatternPreview")
	local now=os.clock()
	if self.preview_map then preview.animate(self.preview_map,now) end
	for _,root in self._animated or {} do preview.animate(root,now) end
end

-- ---------------------------------------------------------------------------------------------
-- Open / close / layout
-- ---------------------------------------------------------------------------------------------

function FlagShop.open(self, filter: string?)
	if filter and self._filters[filter] then self._filter=filter end
	if self.is_open then
		self:apply_layout()
		return
	end
	self.is_open = true
	self:_report("opened")
	self:set_visible(true)
	self:apply_layout()
	self._panel:set_modulate_a(1.0)
	self._dim:set_modulate_a(0.0)
	W.fade(self._dim, 1.0, 0.2)
	UICtx.pop_in(self._panel, 0.0, 0.94, 0.3)
	self.ctx:sfx("open")
	self:set_process(true)
end

function FlagShop.close(self)
	if not self.is_open then
		return
	end
	self.is_open = false
	self:set_process(false)
	self.ctx:sfx("close")
	local t = self:create_tween():set_parallel(true)
	t:tween_property(self._dim, "modulate:a", 0.0, 0.15)
	t:tween_property(self._panel, "modulate:a", 0.0, 0.15)
	t:chain():tween_callback(function()
		if not self.is_open then
			self:set_visible(false)
		end
	end)
	self.closed:Fire()
end

function FlagShop.apply_layout(self)
	local ctx = self.ctx
	local area = ctx:clear_rect()
	local cs = self:_card_size()
	local cols = if ctx.compact
		then math.max(2, math.floor((area.Width - 90) / (cs.X + FlagShop.GAP)))
		else (if self.armory then 3 else FlagShop.COLS)
	cols = math.min(cols, if ctx.compact then 5 else FlagShop.COLS)
	self._cols = cols
	local gw = cols * cs.X + (cols - 1) * FlagShop.GAP + 14
	-- as tall as everything in it, up to the screen's height less the window's head and edges
	-- (2026-10-22, using more of the screen's height: it stopped at 560, today's flags under
	-- the fold); phones: slimmer edges
	local compact = ctx.compact
	for key,b in self._filters do
		b:set_icon(if compact then nil else self._filter_icons[key]);b:set_font_size(if compact then 10 else 12)
		b:set_text(if compact and key=="featured" then "ALL" elseif compact and key=="patterns" then "EDGE" elseif compact and key=="included" then "BASE" else ({featured="FEATURED",flags="FLAGS",colors="COLORS",patterns="BORDERS",owned="OWNED",strikes="STRIKES",support="SUPPORT",included="INCLUDED"})[key])
	end
	self._panel:set_padding(
		if compact then 14 else 22,
		if compact then 10 else 18,
		if compact then 14 else 22,
		if compact then 10 else 18
	)
	self._v:set_separation(if compact then 6 else 10)
	self._brand:set_visible(not compact)
	local chrome = if compact then 144 else 174
	local gh = math.clamp(area.Height - chrome - 8, 100, 620)
	self._host:set_min_size(Vector2.new(gw, gh))
	self._sub:set_visible(not compact or area.Width > 600)
	if self.is_open then
		self:_rebuild()
	end
	self:_center()
end

--- The list's height (logical px) with `cols` cards a row: each section's head, its rows, the gap
--- under them (as _section / _grid build them).
function FlagShop._content_height(self, cols: number): number
	local cs = self:_card_size()
	local c = FlagShop.contents(FlagShop.now())
	local h = 2
	local function grid(keys: { string })
		local list, hero = ShopLayout.order(keys)
		local _, rows = ShopLayout.place(#list, hero, cols)
		h += 30 + rows * cs.Y + (rows - 1) * FlagShop.GAP + 14
	end
	for _, s in c.sets do
		grid(s.keys)
		if self:_bundle_shown(s.id) then
			h += FlagShop.BANNER_H + 10
		end
	end
	grid(c.daily)
	h += 30 + math.ceil((#ProfileStyle.colors - 1) / cols) * 120
	return h
end

function FlagShop._center(self)
	local area = self.ctx:clear_rect()
	local pn = self._panel
	local sz = pn:get_combined_minimum_size()
	local p = area.Min + (Vector2.new(area.Width, area.Height) - sz) * 0.5
	local y = math.max(p.Y, area.Min.Y + 4.0)
	pn:set_offsets(math.floor(p.X + 0.5), math.floor(y + 0.5), math.floor(p.X + 0.5), math.floor(y + 0.5))
	pn:reset_size()
end

return FlagShop
