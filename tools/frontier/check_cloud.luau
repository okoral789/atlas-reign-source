-- Headless Open Cloud validation: scripts do not auto-run; no player purchases or saved data writes.
assert(game.GameId == 10774039150 and game.PlaceId == 129521354706128)
-- Native widget geometry, running without a live player or RenderStepped.
do
	local client = game:GetService("StarterPlayer").StarterPlayerScripts.AirfrontClient
	local W = require(client.UI.Widgets)
	local UICtx = require(client.UI.UICtx)
	local T = require(client.UI.UITheme)
	local CommandBar = require(client.UI.CommandBar)
	local Tooltip = require(client.UI.Tooltip)
	local startDriver, minFont = W.start_driver, T.min_font_size
	W.start_driver = function() end

	local host = Instance.new("ScreenGui")
	local root = W.Root.new(host, { scale = 1 })
	local ctx = UICtx.new()
	ctx.root = root
	ctx.rules = require(client.UI.UIRules).new(ctx)
	ctx.reserved_top_left = Rect.new(0, 0, 300, 58)
	local unlocked = false
	ctx.session = { has_unlock = function() return unlocked end }
	local bar = CommandBar.new(ctx)
	root:add_child(bar)
	local tooltip = Tooltip.new(ctx)
	root:add_child(tooltip)
	tooltip.follow_bottom = function() return bar:top_edge() end
	tooltip._panel:set_min_size(Vector2.new(250, 92))

	local function within(inner, outer, what)
		assert(inner.Width > 0 and inner.Height > 0
			and inner.Min.X >= outer.Min.X and inner.Max.X <= outer.Max.X
			and inner.Min.Y >= outer.Min.Y and inner.Max.Y <= outer.Max.Y, what)
	end

	local function layout()
		bar:apply_layout()
	end
	bar.slots_changed:Connect(layout)
	bar.footprint_changed:Connect(layout)

	local function check(view, insets, expectedFlow, enableUnlocks, scale)
		root:set_viewport(view, scale)
		ctx.vp, ctx.insets = root.vp, insets
		ctx.compact = expectedFlow == CommandBar.Flow.COMPACT
		ctx.touch = ctx.compact
		T.min_font_size = if ctx.touch then 12 else 0
		unlocked = enableUnlocks
		layout()
		bar:update(0.6)
		local dock = bar.panel:get_global_rect()
		local safeRight = ctx.vp.X - insets.z
		assert(bar._flow == expectedFlow, string.format("unexpected dock flow %d for view %s (logical %s), dock=%s",
			bar._flow, tostring(view), tostring(ctx.vp), tostring(dock)))
		assert(math.abs(dock.Max.Y - (ctx.vp.Y - insets.w - 12)) < 0.01 and dock.Min.X >= insets.x + 11.99
			and dock.Max.X <= safeRight - 11.99, string.format("dock clips safe area at %s (logical %s): %s",
				tostring(view), tostring(ctx.vp), tostring(dock)))
		assert(math.abs(dock.Min.X + dock.Max.X - (insets.x + safeRight)) < 0.01, "dock must center in safe area")
		assert(math.abs(dock.Width - bar.panel:get_combined_minimum_size().X) < 0.01
			and math.abs(dock.Height - bar.panel:get_combined_minimum_size().Y) < 0.01,
			"floating dock must fit its content without spanning the map")
		assert(bar.panel.radius > 0 and math.abs(bar.panel._bg.Size.X.Offset - dock.Width * T.scale) <= 1
			and bar.panel._bg.BackgroundTransparency > 0.05 and bar.panel._bg.BackgroundTransparency < 0.10,
			"the rounded dock's glass must be readable and slightly translucent")
		if expectedFlow == CommandBar.Flow.WIDE then
			assert(dock.Height <= 90, "wide dock should fit the HUD into one slim row")
		end
		assert(bar:base_edge() == dock.Min.Y)
		local actionArea = dock
		if ctx.compact then
			within(bar._m_stats:get_global_rect(), dock, "mobile stats clip")
			within(bar._slider:get_global_rect(), dock, "mobile attack slider clips")
			within(bar._tray_btn:get_global_rect(), dock, "Build toggle clips")
			bar:set_tray(true)
			actionArea = bar.tray:get_global_rect()
			local safeAboveDock = Rect.new(insets.x, insets.y, safeRight, dock.Min.Y)
			within(actionArea, safeAboveDock, string.format(
				"build tray clips: view=%s dock=%s tray=%s safe=%s min=%s layout=%s rows=%d",
				tostring(view), tostring(dock), tostring(actionArea), tostring(safeAboveDock),
				tostring(bar.tray:get_combined_minimum_size()), tostring(bar.tray.offset_top), bar._tray_v:get_child_count()))
			assert(bar:base_edge() == dock.Min.Y, "opening the tray should not move the map")
		end
		within(bar._shop:get_global_rect(), actionArea, "shop slot clips")
		local actionCount = 0
		for _, button in pairs(bar.buttons) do
			if button:is_visible_in_tree() then
				within(button:get_global_rect(), actionArea, button.kind .. " clips")
				actionCount += 1
			end
		end
		assert(actionCount == (if unlocked then 14 else 10), "a layout lost an action slot")

		ctx.debug_mouse = Vector2.new(dock.Max.X - 24, dock.Min.Y - 2)
		tooltip.place = Tooltip.Place.FOLLOW
		local tipHeight = tooltip._panel:get_combined_minimum_size().Y
		if bar:top_edge() - insets.y >= tipHeight + 16 then
			assert(tooltip:_compute_target().Y + tipHeight <= bar:top_edge() - 8,
				"map hover card overlaps the open tray")
		end
		bar:set_tray(false)
		assert(tooltip:_compute_target().Y + tipHeight <= dock.Min.Y - 8,
			"map hover card overlaps the command dock")
	end

	check(Vector2.new(1600, 900), { x = 32, y = 14, z = 8, w = 18 }, CommandBar.Flow.WIDE, false)
	local desktop = Vector2.new(2536, 1360)
	check(desktop, { x = 0, y = 0, z = 0, w = 0 }, CommandBar.Flow.WIDE, true, T.ui_scale(desktop, false))
	check(Vector2.new(980, 640), { x = 20, y = 10, z = 12, w = 10 }, CommandBar.Flow.STACKED, true)
	check(Vector2.new(844, 390), { x = 47, y = 12, z = 12, w = 21 }, CommandBar.Flow.COMPACT, true)
	check(Vector2.new(568, 320), { x = 46, y = 10, z = 14, w = 16 }, CommandBar.Flow.COMPACT, true)

	local Pause = require(client.UI.PauseMenu)
	local Defs = UICtx.core("Defs")
	local ownerStarted = false
	local menu = Pause.new(ctx, function() ownerStarted = true end)
	assert(Pause.new(ctx)._measure == nil, "ordinary users have no test button")
	root:add_child(menu)
	ctx.session.mode, ctx.state_mode = UICtx.MODE_MULTI, UICtx.MODE_MULTI
	ctx.state = { phase = Defs.PHASE_PLAYING, local_owner = 0, get_owner = function() return nil end }
	local phone = Vector2.new(844, 390)
	root:set_viewport(phone, T.ui_scale(phone, true))
	ctx.vp, ctx.insets = root.vp, { x = 47, y = 12, z = 12, w = 21 }
	menu:open(true)
	assert(menu._measure:is_visible_in_tree(), "the owner's performance test is visible in a match")
	within(menu._measure:get_global_rect(), ctx:clear_rect(), "performance test is clipped on phone")
	menu._measure.pressed:Fire()
	assert(ownerStarted and not menu.is_open, "test resumes play before recording")
	ctx.session.testing = true
	menu:open(true)
	assert(not menu._measure:is_visible_in_tree(), "cheat sandbox excluded from measurements")

	bar:destroy()
	root:destroy()
	host:Destroy()
	W.start_driver = startDriver
	T.min_font_size = minFont
	print("hud_dock: five content-fit layouts, action slots, mobile stats, and map-hover clearance")
end

local boot=game:GetService("ReplicatedFirst"):FindFirstChild("AtlasBoot")
assert(boot and boot:IsA("LocalScript"),"early boot must ship outside StarterPlayerScripts")
assert(not game:GetService("Players").CharacterAutoLoads)
local shared = game:GetService("ReplicatedStorage").Airfront
local Products = require(shared.Data.Products)
local own = require(shared.Data.FrontierProducts)
local count = 0
for key, product in Products do
	if own[key] then
		assert(product.id == own[key] and product.id > 0)
		if string.sub(key,1,5) == "shop_" then
			assert(product.grants == "shopflag:" .. string.sub(key,6))
		elseif string.sub(key,1,7) == "unlock_" then
			assert(product.grants == "unlock:" .. string.sub(key,8))
		elseif string.sub(key,1,5)=="skin_" then
   assert(product.grants=="skin:"..string.sub(key,6))
  else
			assert(product.grants == "profilecolor:" .. string.match(key,"(%d+)$"))
		end
		count += 1
	else
		assert(product.id == 0, "legacy/non-cosmetic product enabled")
	end
end
assert(count == 80)
assert(require(shared.Data.ProfileStyle).badge(0)=="\u{25C6} RECRUIT","UTF-8 rank glyphs preserved")
local Arsenal = require(shared.Data.Arsenal)
assert(#Arsenal.DISPLAY_ITEMS==4 and Arsenal.DISPLAY_ITEMS[1].key=="mega")
assert(Arsenal.mask({mega=true,scatter=true,airfield=true,railgun=true,artillery=true,emp=true})==Arsenal.item("mega").bit+Arsenal.item("scatter").bit)
local Purchases = require(game:GetService("ServerScriptService").AirfrontServer.Purchases)
local player = {UserId=8318659852}
for _, kind in Arsenal.BASE_BOMBS do assert(Arsenal.item_for(kind) == nil) end
for _, item in Arsenal.DISPLAY_ITEMS do assert(not Purchases.has_unlock(player,item.key) and item.stars > 0) end
assert(select(2,Purchases.buy_flag(player,"cat")) == "Robux only")
assert(Purchases.has_profile_color(player,1) and not Purchases.has_profile_color(player,2))
assert(not Purchases.has_unlock(player,"reload2x"))
local access = require(game:GetService("ServerScriptService").AirfrontServer.OwnerAccess)
assert(access.allowed(8318659852,8318659852,false) and not access.allowed(1,8318659852,false))
local ShopUI = require(game:GetService("StarterPlayer").StarterPlayerScripts.AirfrontClient.UI.FlagShop)
local frame = Instance.new("Frame")
local emptyInventory = {owned={},equipped={}}
local ui = {
	_sf=frame, _cards={}, _cols=4,
	ctx={compact=false,session={load_settings=function() return {color=1} end}},
	_host={_part=function() end},
	_inv=function() return emptyInventory end,
	_card_size=function() return Vector2.new(150,178) end,
}
setmetatable(ui,{__index=ShopUI})
ShopUI._color_grid(ui,1)
local colorButtons = 0
for _, child in frame:GetDescendants() do
	if child:IsA("TextLabel") and child.Text == "R$ 29" then colorButtons += 1 end
end
assert(colorButtons == 15)
local gradientCard=frame:FindFirstChild("profile_color_7",true):FindFirstChild("PremiumColorPreview",true)
assert(#gradientCard:FindFirstChildWhichIsA("UIGradient").Color.Keypoints==3,"premium cards show their real gradient")
assert(not frame:FindFirstChild("profile_color_2",true) and frame:FindFirstChild("profile_color_7",true),"only premium colors are advertised; historical colors stay owned")
assert(frame:FindFirstChild("profile_color_20",true) and frame:FindFirstChild("profile_color_21",true),"new gradients appear in the shop")
ShopUI._fleet_grid(ui,2)
assert(frame:FindFirstChild("pattern_circuit",true) and frame:FindFirstChild("border_prism",true),"new borders use the same shop cards as flags and colors")
ShopUI._card(ui,frame,"cat",Vector2.zero,Vector2.new(150,178),false)
local flagPrice = false
for _, child in frame:GetDescendants() do
	if child:IsA("TextLabel") and child.Text == "R$ 49" then flagPrice = true end
	assert(child.Name ~= "RobuxBuy", "cosmetics should have one Robux purchase button")
end
assert(flagPrice)
frame:Destroy()
local WorldMap = require(shared.Core.WorldMap)
local Surface = require(game:GetService("StarterPlayer").StarterPlayerScripts.AirfrontClient.Map.MapSurface)
local rendered = {}
for _, id in {"world","twin_straits","iron_archipelago"} do
	local map = WorldMap.get(id)
	local surface = Surface.new(nil)
	surface:set_map(map)
	assert(surface.ok and surface.ready and #surface.tiles > 0, id .. " image surface unavailable")
	for _ = 1, #surface.tiles do surface:step() end
	local samples = 0
	for _, tile in surface.tiles do
		assert(tile.img and not tile.dirty)
		for _, point in {Vector2.zero,Vector2.new(tile.w-1,tile.h-1),Vector2.new(tile.w//2,tile.h//2)} do
			local pixels = tile.img:ReadPixelsBuffer(point,Vector2.new(1,1))
			local offset = ((tile.y0+point.Y)*surface.W+tile.x0+point.X)*4
			assert(buffer.readu32(pixels,0)==buffer.readu32(surface.comp,offset))
			samples += 1
		end
	end
	table.insert(rendered,{id=id,width=map.W,height=map.H,land=map.land_count,samples=samples})
	surface:destroy()
end
local icons = require(shared.Assets.UiIcons)
local previews = require(shared.Assets.MapThumbs)
local loaded = 0
local images = {}
for _, id in icons do table.insert(images,id) end
for _, id in previews do table.insert(images,id) end
assert(#images == 57)
for _, id in images do
	local image = game:GetService("AssetService"):CreateEditableImageAsync(Content.fromUri(id))
	assert(image and image.Size.X > 0, "replacement image could not load")
	local pixels = image:ReadPixelsBuffer(Vector2.zero,Vector2.one)
	assert(buffer.len(pixels)==4)
	image:Destroy()
	loaded += 1
end
-- Construct the actual new widgets in Roblox's engine. Only the render driver is disabled
-- because this execution environment is a server without a client RenderStepped signal.
local client=game:GetService("StarterPlayer").StarterPlayerScripts.AirfrontClient
local W=require(client.UI.Widgets);W.start_driver=function() end
local Signal=require(shared.Core.Signal)
local session={inventory={stars=1000,owned={},equipped={},unlocks={},loaded=true},credits={},
 inventory_changed=Signal.new(),credits_changed=Signal.new(),crate_result=Signal.new(),unlock_result=Signal.new(),unlocked=Signal.new(),
 load_settings=function() return {} end,settings_loaded=Signal.new(),settings_ready=true,env={net={connected=true}},has_unlock=function() return false end}
local ctx=require(client.UI.UICtx).new();ctx.session=session
session.has_unlock=function() return true end
local command=require(client.UI.CommandBar).new(ctx)
command:_arrange_slots(true,true)
assert(command.buttons.emp==nil and command.buttons.fleet_repair.parent==command._builds3 and command._builds3:get_child_count()==3)
command:_arrange_slots(false)
assert(command.buttons.fleet_repair.parent==command._builds and command._builds3:get_child_count()==0,"reflow detaches support slots without duplicates")
command:destroy();session.has_unlock=function() return false end
local Root=require(client.UI.UIRoot)
local routed,profileOpened=nil,false
local mapSignals={tile_hovered=Signal.new(),tile_clicked=Signal.new(),tile_context=Signal.new(),layers={labels={owner_at_label=function() return 5 end}}}
local probe=setmetatable({ctx={borders={},world_call=function() return nil end,to_logical=function(_,p) return p end,open_profile=function() profileOpened=true end},
 interact={on_context=function(_,tile,pos) routed={tile,pos} end,on_click=function() end,on_hover=function() end},
 labels_on=true,_sconns={},hud_controls=function() return {} end,_request_apply=function() end},Root)
probe:setup(nil,mapSignals,nil)
mapSignals.tile_context:Fire(77,Vector2.new(300,240))
assert(routed and routed[1]==77 and not profileOpened,"right-click over a nation label must reach the wheel, not open a profile")
local screens={}
for _,name in {"Arsenal","Locker"} do
 local ui=require(client.UI[name]).new(ctx);ui:bind(session);ui:open();ui:apply_layout()
 if name=="Arsenal" then
  assert(ui.support_icon and ui.support_icon:FindFirstChildWhichIsA("ImageLabel",true))
  for i=1,3 do assert(ui.body:FindFirstChild("BaseBomb"..i,true):FindFirstChildWhichIsA("ImageLabel",true)) end
  for _,key in {"atom","hydrogen","mirv","mega","scatter","reinforce","fleet_repair"} do
   ui:show_demo(key);assert(ui.demo and ui.demo.key==key and ui.demo_overlay.Visible)
   assert(#ui.demo.cells>100 and #ui.demo_panel.Heading.Text<65 and not ui.demo_facts.Text:find("-1M"),"concise demo uses actual map geography and positive costs")
   ui.demo:update(0)
   if key=="reinforce" then assert(math.abs(ui.demo.bar.Size.X.Scale-.6)<.000001,"sample starts at 60% of the existing cap") end
   if key=="mirv" then ui.demo:update(1.7);assert(not ui.demo.missile.Visible and ui.demo.impacts[1].warhead.Visible,"MIRV visually splits before impact") end
   if key=="scatter" then ui.demo:update(1.7);assert(#ui.demo.impacts==6 and ui.demo.impacts[2].warhead.Visible,"bonus warheads are visible") end
   ui.demo:update(3)
   if key=="fleet_repair" then assert(math.abs(ui.demo.support_fill.Size.X.Scale-.7)<.000001 and ui.demo.status.Text:find("70 / 100")) end
   if key=="reinforce" then assert(math.abs(ui.demo.bar.Size.X.Scale-.8)<.000001 and ui.demo.status.Text:find("20K"),"sample ends at 80% without raising capacity") end
   ui:frame(.1)
   assert(session.inventory.stars==1000 and ui.pending==nil,"watching demos never spends currency")
   ui:hide_demo();assert(ui.demo==nil and not ui.demo_overlay.Visible)
  end
  assert(ui.cards.mega and ui.cards.scatter and ui.cards.reinforce and not ui.cards.emp and ui.cards.fleet_repair and ui.progress.Text=="0 / 4 UNLOCKED")
  assert(ui.browser.armory==ui and ui.browser._filters.strikes and ui.browser._filters.support,"Armory uses the actual Style Shop window")
  for _,filter in {"strikes","support","included","featured"} do
   ui.browser._filter=filter;ui:apply_layout()
   if filter=="strikes" then assert(ui.cards.mega and ui.cards.scatter and not ui.cards.fleet_repair)
   elseif filter=="support" then assert(ui.cards.reinforce and ui.cards.fleet_repair and not ui.cards.mega)
   elseif filter=="included" then assert(ui.body:FindFirstChild("BaseBomb1",true) and not ui.cards.mega) end
  end
  for _,key in {"fleet_repair","scatter"} do ui:select_equipment(key);assert(ui.demo.key==key);ui:hide_demo() end
  ui:select_equipment("emp");assert(ui.demo==nil,"retired EMP cannot open a demo")
  local oldVp,oldCompact=ctx.vp,ctx.compact
  ctx.vp=Vector2.new(568,320);ctx.compact=true;ui:apply_layout()
  assert(ui.browser._panel:get_combined_minimum_size().X<568,"phone equipment shop stays inside the screen")
  ctx.vp=oldVp;ctx.compact=oldCompact;ui:apply_layout()
  ui:_buy("mega",false);assert(ui.pending==nil and ui.note.Text:find("more Credits"),"insufficient funds never send a purchase")
  local sent={};session.inventory.stars=50000;session.buy_unlock=function(_,key) table.insert(sent,key);return false end
  ui:_buy("mega",false);assert(#sent==0 and ui.confirm.key=="mega")
  ui:_buy("scatter",false);assert(#sent==0 and ui.confirm.key=="scatter","confirmation belongs to the selected item")
  ui:_buy("scatter",false);assert(#sent==1 and sent[1]=="scatter" and not ui.pending,"failed delivery allows retry without claiming ownership")
  session.inventory.stars=1000;session.buy_unlock=nil
 end
 table.insert(screens,name);ui:close();ui.gui:Destroy()
end
local folder=Instance.new("Folder");folder.Name="HeadlessPlayerGui";folder.Parent=game:GetService("StarterGui")
local fake={UserId=8318659852,DisplayName="Commander",WaitForChild=function() return folder end,
 GetAttribute=function(_,key) return folder:GetAttribute(key) end,GetAttributeChangedSignal=function(_,key) return folder:GetAttributeChangedSignal(key) end}
local profile=require(client.UI.PlayerProfile).new(fake,session,function() end,function() end,function() end)
folder:SetAttribute("AtlasCountryColor",2)
profile:show_style({skin="hex",flag="shop_lion_crest"},true,nil)
assert(#profile.tiles>200 and profile.flag.Image~="" and profile.identity[2].name.Text=="Blue")
assert(profile.pattern and profile.pattern:FindFirstChildWhichIsA("Frame"),"profile renders the real pattern")
for _,d in profile.panel:GetDescendants() do if d:IsA("TextButton") then assert(d.Text~="R$","profile is not a checkout wall") end end
assert(profile.body:FindFirstChild("Wins") and profile.body:FindFirstChild("GlobalRank"))
for _,vp in {Vector2.new(2560,1360),Vector2.new(1600,900),Vector2.new(844,390),Vector2.new(568,320)} do
 local scale=require(client.UI.PlayerProfile).fit_scale(vp,1.52)
 assert(820*scale<=vp.X-27 and 520*scale<=vp.Y-27)
end
profile.gui:Destroy();table.insert(screens,"CompactPlayerProfile")
local Names=require(client.Map.NameLayer)
assert(Names.role({user_id=8318659852},false)=="ADMIN" and Names.role({user_id=7},false)=="" and Names.role({user_id=8318659852,bot=true},false)=="","admin identity comes from a real owner id")
local RankUI=require(client.UI.WinsBoard)
for _,sample in {{0,"RECRUIT",1},{1,"SCOUT",9},{10,"CAPTAIN",40},{50,"CONQUEROR",150},{200,"LEGEND",0}} do
 local tier,left,_,progress=RankUI.career(sample[1]);assert(tier==sample[2] and left==sample[3] and progress>=0 and progress<=1)
end
local calls,pauses=0,0
local stub={InvokeServer=function(_,action,id)
 calls+=1;assert(action=="profile" and id==8318659852)
 return if calls==1 then {ok=false,message="Please wait a moment."} else {ok=true,wins=3,rank=2}
end}
local fetched=RankUI.fetch(stub,"profile",8318659852,function(seconds) assert(seconds>=1);pauses+=1 end)
assert(fetched.ok and fetched.wins==3 and calls==2 and pauses==1,"ranking navigation retry")
local immediate=RankUI.fetch({InvokeServer=function() return {ok=true,wins=1} end},nil,nil,function() error("unneeded wait") end)
assert(immediate.ok)
local board=require(client.UI.WinsBoard).new(fake,function() end,function() end);assert(board.panel and board.list)
board:open();assert(board.view=="demo" and board.podium and board.podium:FindFirstChild("Podium3") and #board.list:GetChildren()>=11 and board.status.Text:find("DEMO"));board:close();board.gui:Destroy();table.insert(screens,"WinsBoard")
local reports=require(client.UI.ReportsPanel).new(fake,function() end);assert(reports.body);reports.gui:Destroy();table.insert(screens,"ReportsPanel")
local opening=require(client.UI.CrateOpening).new(ctx)
opening:_layout();opening:_apply_pose();assert(opening._case_image.Image==require(shared.Assets.Design).collection)
opening.gui:Destroy();table.insert(screens,"FieldCaseReveal")
local theme=require(client.UI.UITheme)
local title=require(client.UI.TitleScreen).new(ctx)
ctx.reserved_top_left=Rect.new(0,0,270,58)
local layoutChecks=0
for _,sample in {{Vector2.new(2560/1.52,1360/1.52),1.52,false},{Vector2.new(1600,900),1,false},{Vector2.new(1100,600),1,false},{Vector2.new(844,390),1,true},{Vector2.new(568,320),1,true}} do
 ctx.vp=sample[1];theme.set_scale(sample[2]);ctx.compact=sample[3]
 title:apply_layout()
 local plan=title.menu_layout;local s=theme.scale
 title._shop_btn:refresh();assert(not title._shop_btn.visible,"legacy flag-shop promotion must stay suppressed after refresh")
 assert(title.logo:FindFirstChildWhichIsA("ImageLabel",true).Image==require(shared.Assets.Design).wordmark and not title._head.visible)
 for _,backdrop in {title._vignette,title._top_shade,title._bottom_shade,title._fade} do assert(title.identity.ZIndex>backdrop.gui.ZIndex,"menu dimmed by background layers") end
 assert(title.wallet_icon.Position.X.Offset+title.wallet_icon.Size.X.Offset<=title.wallet_text.Position.X.Offset+.1,"scaled Credits overlap")
 assert(title.wallet_icon:IsA("ImageLabel") and title.wallet_icon.Image==require(shared.Assets.Design).credits,"Credits never depend on a missing font glyph")
 assert(title.identity.Size.X.Offset<=ctx.vp.X*s)
 assert(title._party._pill.visible==false and title._party._panel.visible==false,"party must be closed initially")
 title._party:toggle();assert(title._party._panel.visible)
 if not plan.compact then assert(title._party._panel.offset_left>=16,"party stays inside viewport") end
 title._party:toggle();assert(not title._party._panel.visible)
 layoutChecks+=1
end
title.gui:Destroy();theme.set_scale(1);table.insert(screens,"MenuLayersDpiAndParty")
local sprites=require(shared.Assets.MapSprites)
local Units=require(client.Map.UnitLayer)
local ownerColor=Color3.fromRGB(55,135,210)
local unitHost=setmetatable({_sprites={},_pool={},root=Instance.new("Frame"),_state={owner_color=function() return ownerColor end,cosmetics={}}},Units)
Units._sprite(unitHost,16,0,1,80,90,26,{})
local ship=unitHost._sprites[16]
local fleetArt=require(shared.Assets.FleetMarkers)
assert((ship.fill.Image=="" or ship.fill.Image==fleetArt[1]) and ship.glyph)
assert(ship.fill.ImageColor3==ownerColor)
assert(ship.frame.Size==UDim2.fromOffset(26,26) and ship.frame.Rotation==0 and ship.pennant==nil,"ship should have no oversized art or flag")
unitHost._state.cosmetics[1]={skin="fleet_copper"};Units._sprite(unitHost,16,0,1,80,90,26,{})
assert(ship.rim.ImageColor3==Color3.fromRGB(241,191,134),"saved fleet livery remains available as trim")
unitHost.root:Destroy();table.insert(screens,"ClassicPixelShips")
local warHost=setmetatable({_sprites={},_pool={},root=Instance.new("Frame"),_state={owner_color=function() return ownerColor end,cosmetics={}}},Units)
Units._sprite(warHost,32,2,1,80,90,26,{})
local marker=warHost._sprites[32]
assert((marker.fill.Image=="" or marker.fill.Image==fleetArt[3]) and marker.glyph and marker.glyph.Hull.BackgroundColor3==ownerColor)
Units._sprite(warHost,32,0,1,80,90,26,{})
assert((marker.glyph.Visible or marker.fill.Image==fleetArt[1]) and not marker.glyph.Bow.Visible and not marker.glyph.Bridge.Visible,"pool restores landing shape")
warHost.root:Destroy();table.insert(screens,"FlatWarshipMarker")
-- Exercise full redraws with actual GameState-style path records: units have no `tile` field.
local rig={viewport_size=function() return Vector2.new(1024,768) end,screen_to_map=function(_,x,y) return x/2,y/2 end,scale=2,version=1,_vp=Vector2.new(1024,768),on_screen=function() return true end,map_to_screen=function(_,x,y) return x*2,y*2 end,
 tile_to_screen=function(_,tile) return (tile%64+.5)*2,(math.floor(tile/64)+.5)*2 end}
local motion=Units.new(Instance.new("Frame"),{rig=rig})
local D=require(shared.Core.Defs)
do
local FX=require(client.Map.TerritoryEffects)
local Field=require(shared.Data.BorderField)
local Strokes=require(shared.Data.BorderStrokes)
local Signal=require(shared.Core.Signal)
local fxRig={scale=2,version=1}
function fxRig:viewport_size() return Vector2.new(1024,768) end
function fxRig:screen_to_map(x,y) return x/self.scale,y/self.scale end
function fxRig:map_to_screen(x,y) return x*self.scale,y*self.scale end
local fxState={W=64,H=64,cosmetics={[1]={skin="pattern_circuit"}},tile_owner=function() return 1 end,tiles_changed=Signal.new(),cosmetics_changed=Signal.new(),snapshot_loaded=Signal.new()}
local fx=FX.new(Instance.new("Frame"),{rig=fxRig});fx:bind(fxState)
local function finishBorderJob()
 for _=1,64 do
  fx:tick(1/60)
  assert(fx.sample_work<=FX.SAMPLE_BUDGET,"bounded contour work per frame")
  if fx.image and fx.field and fx.cache.pending==0 and not fx.cache.job then return end
 end
 error("border sampling did not complete")
end
finishBorderJob()
assert(fx.image and fx.field and fx.field.live>0,"continuous border image created")
assert(fx.w<=FX.MAX_W and fx.h<=FX.MAX_H and fx.reads<=66*66,"VFX image and haloed ownership reads are bounded")
assert(#fx.root:GetChildren()==0,"no icon sprites or per-tile GUI objects")
Strokes.animate(fx.field,0);local first=buffer.tostring(fx.pixels)
Strokes.animate(fx.field,1)
assert(first~=buffer.tostring(fx.pixels),"the perimeter glow animates")
local samples,rasters=fx.samples,fx.rasters
for _=1,120 do
 fxRig.scale*=1.003;fxRig.version+=1;fx:tick(1/60)
 local drift=math.abs(fxRig.scale/fx.paint_scale-1)*math.max(fx.paint_w/fx.w,fx.paint_h/fx.h)
 assert(fx.sample_work<=FX.SAMPLE_BUDGET and drift<=FX.REUSE_PX)
end
assert(fx.samples==samples,"smooth zoom does not resample the whole mask every frame")
assert(fx.rasters-rasters<60,"subpixel zoom reuses the stroke texture")
fx:tick(1/60)
assert(fx.paint_scale==fxRig.scale,"settled zoom has the exact projection")
-- Device-pixel footprint preserves a bright core even at 4K downsampling; zoom cannot widen it.
local line=Field.begin(128,80,function(x) return if x>=64 then 1 else 0 end,{[1]={effect="electric",fleet_tint=0x72FFF0}})
while not Field.step(line,FX.SAMPLE_BUDGET) do end
for _,px in {1,2,5,7.5} do
 local expected
 for _,zoom in {1,1.03,1.5,2,4} do
  local f=Field.raster(line,zoom,64*(1-zoom),0,px,px,Field.RADIUS_PX)
  local out=Field.render(f,.4);local width,bright=0,0
  for x=0,127 do local a=buffer.readu8(out,(35*128+x)*4+3);if a>0 then width+=1 end;bright=math.max(bright,a) end
  assert(bright>120 and width*px<=10+2*px,"visible bounded screen-space core at 4K")
  if expected then assert(width==expected,"premium border width stays constant through zoom") else expected=width end
 end
end
-- Let the in-flight old job finish, then signal the capture and await its replacement.
finishBorderJob()
fxState.tile_owner=function() return 2 end;local changes={}
for t=0,64*64-1 do changes[#changes+1]=t*1024+2 end
fxState.tiles_changed:Fire(changes)
for _=1,64 do fx:tick(1/60) end
assert(fx.field.live==0 and not fx.root.Visible,"capture removes the previous owner's glow")
fx:destroy();table.insert(screens,"ContinuousTerritoryVFX")

end
-- Additional native regression for MapView ordering and 60Hz camera-following overlays.
do
 local View=require(client.Map.MapView)
 local rig={version=0,scale=1,x=0,_vp=Vector2.new(800,600)}
 function rig:viewport_size() return self._vp end
 function rig:tick() self.x+=30;self.version+=1 end
 function rig:tile_to_screen(tile) return tile*self.scale+self.x,200 end
 local v=setmetatable({rig=rig,_marker_on={},_marker_stroke={},layers={},_layer_order={},surface={step=function() end},_perf_add=function() end,_update_selected_rings=function() end},View)
 for _,key in {"_spawn_ring","_aim_ring","_aim_inner"} do
  local frame=Instance.new("Frame");local stroke=Instance.new("UIStroke");stroke.Parent=frame;v[key]=frame
 end
 local inputFrame=0
 v.input={tick=function()
  rig.x+=9;inputFrame+=1
  v._aim={kind="nuke",tile=inputFrame,outer=5,inner=2,valid=true}
 end}
 v.aim_sams=function() return 0 end
 v.surface.layout=function()
  assert(inputFrame==rig.version,"camera and input settle before map layout")
 end
 v.layers.check={tick=function()
  local expected=rig:tile_to_screen(inputFrame)
  assert(v._aim_ring.Position.X.Offset==expected,"yellow aim ring uses current-frame hover and camera")
  assert(v._aim_inner.Position.X.Offset==expected,"inner blast radius follows the same frame")
 end}
 v._layer_order={"check"}
 for frame=1,60 do
  v:update(1/60)
  -- UIInteract's touch ghost runs later in the same RenderStep cycle.
  local lateTile=600+frame
  v:set_aim("nuke",lateTile,5,true,"atom")
  assert(v._aim_ring.Position.X.Offset==rig:tile_to_screen(lateTile),"late touch aim paints in the same camera frame")
 end
 assert(inputFrame==60)
 function rig:map_to_screen(x,y) return self.x+x*self.scale,y*self.scale end
 local writes={map=0,border=0,glow=0}
 local Glow=require(client.Map.FalloutGlow)
 v.layers.glow=setmetatable({view=v,label={},_state={map={W=64,H=32}},_img={},_hot={[1]=true},_skipped=0,
  _follow_view=function() return false end,_draw=function()
   assert(not v._map_image_written,"fallout cannot overwrite a busy upload slot")
   writes.glow+=1
  end},Glow)
 v.layers.territory_fx={tick=function(self)
  self.image_waiting=v._map_image_written or (v._map_image_slot~=nil and v._map_image_slot~=self)
  if not self.image_waiting then writes.border+=1;v._map_image_written=true end
 end}
 v.surface.step=function(self,_,_,skip)
  self.uploaded=not skip
  if self.uploaded then writes.map+=1 end
 end
 v._layer_order={"glow","territory_fx"}
 for frame=1,24 do
  v.layers.glow._next=0
  v:update(1/60)
  assert(writes.map+writes.border+writes.glow==frame,"only one map texture writes in a frame")
 end
 assert(writes.map>0 and writes.border>0 and writes.glow>0,"every writer gets a slot under continuous load")
 v:set_aim("",-1,0)
 assert(not v._aim_ring.Visible and not v._aim_inner.Visible,"late cancel hides both aim rings immediately")
 for _,key in {"_spawn_ring","_aim_ring","_aim_inner"} do v[key]:Destroy() end
 table.insert(screens,"MapCameraInputOrdering")
 table.insert(screens,"MapTextureUploadScheduling")
end

do
local FX=require(client.Map.TerritoryEffects)
local Cache=require(shared.Data.BorderContourCache)
local rig={scale=1,version=1,x=0,y=0,w=256,h=160}
function rig:viewport_size() return Vector2.new(self.w,self.h) end
function rig:screen_to_map(x,y) return (x-self.x)/self.scale,(y-self.y)/self.scale end
function rig:map_to_screen(x,y) return x*self.scale+self.x,y*self.scale+self.y end
local reads=0
local state={W=2048,H=512}
function state:tile_owner(t) reads+=1;return if t%2048%160>=80 then 1 else 0 end
local cache=Cache.new(state.W,state.H,function(t) return state:tile_owner(t) end)
while cache.pending>0 or cache.job do Cache.step(cache,16384,{0,0,256,160}) end
local beforeReads=reads
local parent=Instance.new('Frame')
local fx=FX.new(parent,{rig=rig,ui_scale=.6})
fx.state=state;fx.cache=cache;fx.styles={[1]={effect='neon',fleet_tint=0x72FFF0}}
local function borderAt(mx,my)
 local sx,sy=rig:map_to_screen(mx,my)
 local rootX,rootY=fx.root.Position.X.Offset,fx.root.Position.Y.Offset
 local scale=rig.scale/fx.paint_scale
 local px,py=fx.paint_w/fx.w*scale,fx.paint_h/fx.h*scale
 local ix,iy=math.floor((sx-rootX)/px),math.floor((sy-rootY)/py)
 assert(ix>=0 and iy>=0 and ix<fx.w and iy<fx.h,'visible border is inside the cached image')
 assert(buffer.readu8(fx.pixels,(iy*fx.w+ix)*4+3)>6,'newly exposed border exists in the CURRENT frame')
end
fx:tick(1/60);borderAt(80,60)
local count=fx.rasters;local framesWithoutUpload=0
for frame=1,60 do
 rig.x-=7.25;rig.y=-25;rig.version+=1
 local before=fx.rasters;fx:tick(1/60)
 local x,y=rig:map_to_screen(fx.paint_mx,fx.paint_my)
 assert(math.abs(fx.root.Position.X.Offset-x)<1 and math.abs(fx.root.Position.Y.Offset-y)<1,'pan image anchor follows every 60Hz camera frame')
 assert(fx.root.Size.X.Offset==rig.w+128 and fx.root.Size.Y.Offset==rig.h+128,'pan never stretches a cached stroke')
 if before==fx.rasters then framesWithoutUpload+=1 end
 local left=rig:screen_to_map(0,0);borderAt(math.ceil((left+10)/80)*80,70)
end
assert(framesWithoutUpload>=40 and fx.rasters-count<=15,'pan follows without waiting for image uploads')
assert(reads==beforeReads and fx.sample_work==0,'warm camera movements read zero map ownership')
-- A teleport beyond the overscan must render the new map chunks in this same frame.
rig.x,rig.y=-1560,-20;rig.version+=1;fx.paint_elapsed=0
local before=fx.rasters;fx:tick(1/60)
assert(fx.rasters==before+1,'teleport bypasses the animation interval')
borderAt(1680,70)
-- Far outside the world has no old on-screen ghosts.
rig.x=10000;rig.version+=1;fx.paint_elapsed=0;fx:tick(1/60)
assert(not fx.root.Visible)
rig.x,rig.y=0,0;rig.version+=1;fx:tick(1/60)
local beforeZoom=fx.rasters
for i=1,60 do
 rig.scale*=1.005;rig.x-=.4;rig.version+=1
 fx.view.ui_scale=if i%2==0 then .6 else 1.8
 fx:tick(1/60)
 local ratio=rig.scale/fx.paint_scale
 local x,y=rig:map_to_screen(fx.paint_mx,fx.paint_my)
 assert(math.abs(ratio-1)*math.max(fx.paint_w/fx.w,fx.paint_h/fx.h)<=FX.REUSE_PX)
 assert(math.abs(fx.root.Position.X.Offset-x)<1 and math.abs(fx.root.Position.Y.Offset-y)<1)
 assert(math.abs(fx.root.Size.X.Offset-fx.paint_w*ratio)<1,'cached projection remains physical at every HUD scale')
 borderAt(80,60)
end
assert(fx.rasters-beforeZoom<30,'subpixel zoom reuses the stroke texture')
fx:tick(1/60)
assert(fx.paint_scale==rig.scale,'stopping zoom refreshes the exact projection')
rig.w,rig.h=320,180;rig.version+=1;fx:tick(1/60)
assert(fx.root.Size.X.Offset==448 and fx.root.Size.Y.Offset==308,'resize replaces geometry immediately')
assert(reads==beforeReads,'zoom, teleport and resize reuse map contours')
fx:destroy();parent:Destroy();table.insert(screens,'BorderMapCacheFollow60Hz')
end

local Preview=require(client.UI.PatternPreview)
local previewParent=Instance.new("Frame");local root,cells=Preview.country(previewParent,UDim2.new(),UDim2.fromOffset(300,210))
Preview.add_effect(root,"electric",cells,Color3.fromRGB(135,202,255))
assert(root:FindFirstChild("ContinuousBorderPreview"),"shop preview uses the same continuous field renderer")
Preview.animate(root,2);previewParent:Destroy()
local baseSim=require(shared.Core.Sim)
local supportSim=setmetatable({},baseSim)
supportSim.rng=require(shared.Core.Rng).new(919);supportSim.difficulty=1;supportSim.max_humans=1
supportSim:_init_state(WorldMap.get("world"));supportSim:_init_attacks();supportSim:_init_structures();supportSim:_init_naval();supportSim:_init_warships();supportSim:_init_nukes();supportSim:_init_arsenal()
supportSim.team_names={};supportSim.winner_team=0;supportSim.phase=D.PHASE_PLAYING;supportSim.playing_since=0;supportSim.tick=1
local commander=supportSim:add_owner("Test commander",0x54AAFFFF,D.KIND_HUMAN)
local enemy=supportSim:add_owner("Test enemy",0xFF8877FF,D.KIND_HUMAN)
supportSim.o_spawned[commander]=1;supportSim.o_gold[commander]=1000000
local point=supportSim.map:land_tile(200)
supportSim:add_struct(D.S_SILO,commander,point)
local sam=supportSim:add_struct(D.S_SAM,enemy,point)
supportSim.tick=500;supportSim:construction_tick();sam.shots={}
supportSim:set_unlocks(commander,D.UNLOCK.emp)
local wire=require(shared.Net.Protocol)
assert(not supportSim:call_support(commander,"emp",point))
supportSim:_apply_intent(commander,wire.decode_intent(wire.encode_intent({type="emp",tile=point})))
assert(supportSim.o_gold[commander]==1000000 and #supportSim.support_effects==0 and supportSim:ready_missiles(sam,300)>0)
local supportArt=require(shared.Assets.SupportArt)
for key,id in supportArt do
 local ok=false;game:GetService("ContentProvider"):PreloadAsync({id},function(_,status) ok=status==Enum.AssetFetchStatus.Success end)
 assert(ok,"support equipment art unavailable: "..key)
end
local supportState={tick=120,render_tick=120,support_effects={
 [1]={1,"emp",1,200,10,40,150,40,610},[2]={2,"fleet_repair",1,200,120,120,150,45,570}}}
local supportLayer=require(client.Map.SupportLayer).new(Instance.new("Frame"),{rig=rig})
supportLayer:bind(supportState);supportLayer:tick(.016)
assert(supportLayer.gui[1]==nil and supportLayer.gui[2].label.Text=="FLEET REPAIRED")
supportState.tick=150;supportLayer:tick(.016)
assert(supportLayer.gui[2]==nil,"effect ends at the server's end tick")
supportLayer:destroy();table.insert(screens,"TimedTacticalSupport")
local movingState={map={W=64,H=64,N=4096,k_lin=1},render_tick=.2,tick=0,cosmetics={},nukes={},shells={},sam_missiles={},units={
 [1]={uid=1,kind=D.U_TRADE,owner=1,path={200,201,202,203,204},start_tick=0,ticks_per_tile_x100=100,prev_tile=-1},
 [2]={uid=2,kind=D.U_WARSHIP,owner=1,path={50,51,115,179,178},prev_tile=-1,move_tick=0,start_tick=0,ticks_per_tile_x100=100},
 [3]={uid=3,kind=D.U_TRANSPORT,owner=1,path={300,301,302,303,304},prev_tile=-1,start_tick=0,ticks_per_tile_x100=100}},owner_color=function() return ownerColor end}
motion:bind(movingState);motion:set_selected(2);motion:tick(.016)
assert(motion._sprites[32].frame.Rotation==0,"warship starts facing its full UNIT_PATH")
local beforeTrade=motion._sprites[16].frame.Position;local beforeLanding=motion._sprites[48].frame.Position
movingState.render_tick=1.2;motion:tick(.016)
assert(motion._sprites[32].frame.Rotation==90,"current warship route turns south")
movingState.render_tick=3.2;motion:tick(.016)
assert(motion._sprites[16].frame.Position~=beforeTrade and motion._sprites[48].frame.Position~=beforeLanding,"warship must not freeze moving trade/landing units")
assert(motion._sprites[32].frame.Rotation==180 and motion._sel_ring.Visible,"warship turns west and keeps selection")
for _,key in {16,32,48} do assert(motion._sprites[key].fill.ImageColor3==ownerColor,"turning must preserve nation tint") end
for i,id in fleetArt do
 local probe=Instance.new("ImageLabel");probe.Image=id
 local ok=false;game:GetService("ContentProvider"):PreloadAsync({probe},function(_,status) ok=status==Enum.AssetFetchStatus.Success end)
 probe:Destroy();assert(ok,"new fleet mask unavailable")
end
local deadline=os.clock()+8
repeat task.wait(.1);motion:tick(.016) until motion._sprites[32].fill.Image==fleetArt[3] or os.clock()>deadline
assert(motion._sprites[16].fill.Image==fleetArt[2] and motion._sprites[48].fill.Image==fleetArt[1] and motion._sprites[32].fill.Image==fleetArt[3],"three distinct live fleet silhouettes")
ownerColor=Color3.fromRGB(212,86,115);motion:tick(.016)
for _,key in {16,32,48} do assert(motion._sprites[key].fill.ImageColor3==ownerColor,"cached sprites refresh nation color") end
movingState.cosmetics[1]={skin="fleet_copper"};motion:tick(.016)
assert(motion._sprites[32].stripe.Visible and motion._sprites[32].stripe.BackgroundColor3==Color3.fromRGB(241,191,134),"owned fleet accent is retained")
local nukeArt=require(shared.Assets.NukeMarkers)
for key,id in nukeArt do
 local ok=false;game:GetService("ContentProvider"):PreloadAsync({id},function(_,status) ok=status==Enum.AssetFetchStatus.Success end)
 assert(ok,"new missile image unavailable: "..key)
end
movingState.tile_owner=function() return 0 end
for i,key in {"atom","hydrogen","mirv","mega","scatter","warhead"} do
 movingState.nukes[100+i]={uid=100+i,kind=D.nuke_kind_from_name(key),owner=1,from_tile=50,to_tile=2300,launch_tick=0,flight_ticks=10}
end
local deadline=os.clock()+8
repeat task.wait(.1);motion:tick(.016) until motion._sprites[101*16+8].fill.Image==nukeArt.atom or os.clock()>deadline
for i,key in {"atom","hydrogen","mirv","mega","scatter","warhead"} do
 local missile=motion._sprites[(100+i)*16+8]
 assert(missile and missile.fill.Image==nukeArt[key] and missile.fill.ImageColor3==Color3.new(1,1,1),"equipment color stays distinct from nation tint")
 assert(missile.stripe.Visible and missile.stripe.BackgroundColor3==ownerColor and missile.frame.Rotation~=0,"missile rotates along its arc and retains the owner band")
end
motion:destroy();table.insert(screens,"WarshipWithMovingTraffic")
folder:SetAttribute("AtlasCountryColor",0)
local testPack=require(shared.Data.PrivateTest)
local C=require(shared.Data.Cosmetics)
for _,id in testPack.COSMETICS do
 session.inventory.owned[id]=true
 local banner=C.banner_for(id);if banner then session.inventory.owned[banner.id]=true end
end
session.inventory.owned.pattern_circuit=true;session.inventory.owned.pattern_lava=true
local store=ShopUI.new(ctx);store:bind(session)
for _,filter in {"featured","flags","colors","patterns","owned"} do
 store:open(filter);store:apply_layout();assert(#store._cards>0 and store._pending==nil)
 assert(store.preview_map and #store.preview_cells>200,"one shop includes the country loadout preview")
 store:close()
end
store:open("owned");assert(store._filter=="owned" and store._sf:FindFirstChild("shop_lion_crest",true) and not store._sf:FindFirstChild("banner_lion_crest",true),"flag overlay is an option on the flag, not a duplicate product")
store:preview_item("skin","pattern_circuit");assert(store.preview_map:GetAttribute("TerritoryEffect")=="neon")
store:preview_item("skin","pattern_lava");store:_process(.1);assert(store.preview_map:GetAttribute("TerritoryEffect")=="flame")
store:preview_item("color",7);store:preview_item("flag","shop_lion_crest")
assert(store.preview_pick.skin=="pattern_lava" and store.preview_pick.flag_fill,"gradient, flag and border coexist")
local shades={};local edges=0
for _,cell in store.preview_cells do
 if cell.edge then edges+=1;assert(cell.gui.BackgroundColor3==Color3.fromRGB(255,172,70)) else shades[tostring(cell.gui.BackgroundColor3)]=true end
end
local shadeCount=0;for _ in shades do shadeCount+=1 end;assert(edges>30 and shadeCount>20)
local actions={};session.save_settings=function(_,section,value) table.insert(actions,{section,value}) end
session.equip=function(_,slot,id) table.insert(actions,{slot,id}) end
session.mode=1;assert(not store:apply_preview() and #actions==0,"full identity remains fixed during a match")
session.mode=0;session.inventory.loaded=false;assert(not store:apply_preview() and #actions==0,"cold inventory cannot overwrite a saved look")
session.inventory.loaded=true;store.preview_pick={color=0,flag="shop_lion_crest",skin="pattern_lava",flag_fill=true}
assert(store:apply_preview() and #actions==3 and actions[1][1]=="frontier_country","one loadout applies through the existing checked settings and equip paths")
assert(actions[1][2].flag_fill and actions[2][2]=="pattern_lava","saving a flag overlay never replaces a chosen border")
assert(not store:apply_preview() and #actions==3,"pending save cannot be double-submitted")
store._applying=nil;session.save_settings=nil;session.equip=nil
store._applying=nil
for _,list in {C.all(),C.shop_items()} do for _,item in list do session.inventory.owned[item.id]=true end end
store:open("owned");local page=store._sf:FindFirstChild("OwnedStyles");local cards=0
for _,child in page:GetChildren() do if child:IsA("Frame") then cards+=1 end end
assert(cards<=24 and #page:GetChildren()<=29,"full owner catalogue is paginated")
store:close();store.gui:Destroy();table.insert(screens,"UnifiedStyleShopAndCustomize")
local Gate=require(game:GetService("ServerScriptService").AirfrontServer.TestingAccess)
local g=Gate.new(8318659852,game.GameId);assert(not g:request({UserId=7},true).ok and g:request(fake,true).active)
assert(g:request(fake,false).ok and not g:active(fake))
local sandboxSession={mode=1,testing=true,state={owners={[1]={gold=1000000000,troops=5000000,max_troops=10000000}},local_owner=1},mode_changed=Signal.new(),state_ready=Signal.new()}
local toolsPanel=require(client.UI.TestingPanel).new(fake,sandboxSession,function() end)
toolsPanel:open();assert(toolsPanel.hud.Enabled and toolsPanel.gui.Enabled and toolsPanel.stats.Text:find("1000000000"))
sandboxSession.testing=false;toolsPanel:refresh();assert(not toolsPanel.hud.Enabled and not toolsPanel.gui.Enabled);toolsPanel:destroy();table.insert(screens,"OwnerTestingSandbox")
session.inventory.owned={}
local spawn=require(client.UI.SpawnOverlay).new(ctx);spawn:apply_layout();assert(spawn._wordmark and spawn._mode_card);spawn.gui:Destroy();table.insert(screens,"StartingLocation")
local result=require(client.UI.GameOver).new(ctx);result:apply_layout();assert(result._result_panel);result.gui:Destroy();table.insert(screens,"MatchResult")
local input=require(client.UI.UICtx)
local sent={};local c={ratio=1,troop_floor=.25,sent_log={},session={send_intent=function(_,it) table.insert(sent,it) end}}
input.send(c,{type="attack",ratio=1,tile=1});input.send(c,{type="boat",ratio=1,tile=2})
assert(input.order_ratio(c)==.75 and #sent==2 and sent[1].ratio==.75 and sent[2].ratio==.75,"75% per order without a home reserve")
assert(input.RATIO_STOPS[#input.RATIO_STOPS]==.75)
folder:Destroy()
local design=require(shared.Assets.Design)
for _,name in {"wordmark","emblem","credits","collection","fleet"} do
 if name=="wordmark" then
  local loaded=false;game:GetService("ContentProvider"):PreloadAsync({design.wordmark},function(_,status) loaded=status==Enum.AssetFetchStatus.Success end);assert(loaded,"new wordmark could not load")
  continue
 end
 local img=game:GetService("AssetService"):CreateEditableImageAsync(Content.fromUri(design[name]))
 assert(img and img.Size.X>0)
 if name=="fleet" then assert(img.Size==Vector2.new(1023,341) and design.fleet_cell==341) end
 img:Destroy()
end
local armoryLoaded=false;game:GetService("ContentProvider"):PreloadAsync({design.armory},function(_,status) armoryLoaded=status==Enum.AssetFetchStatus.Success end);assert(armoryLoaded,"new armory artwork could not load")
local extras=require(shared.Assets.DesignExtras)
local badgeLoaded=false;game:GetService("ContentProvider"):PreloadAsync({extras.image},function(_,status) badgeLoaded=status==Enum.AssetFetchStatus.Success end);assert(badgeLoaded,"illustrated menu and bonus bomb icons load")
local flagImages=0
for _,entry in require(shared.Assets.FrontierFlags) do
 local img=game:GetService("AssetService"):CreateEditableImageAsync(Content.fromUri(entry.image))
 assert(img and img.Size.X>0,"owner flag image unavailable: "..entry.image);img:Destroy();flagImages+=1
end
assert(flagImages==38)
for _,id in require(shared.Assets.Flags).atlases do
 local ok=false;game:GetService("ContentProvider"):PreloadAsync({id},function(_,status) ok=status==Enum.AssetFetchStatus.Success end);assert(ok,"classic flag atlas unavailable")
end
local audioSeen={};local audioCount=0
for _,entry in require(shared.Assets.BattleAudio).sfx do if not audioSeen[entry.id] then
 audioSeen[entry.id]=true;local sound=Instance.new("Sound");sound.SoundId=entry.id;sound.Parent=game:GetService("SoundService")
 local ok=false;game:GetService("ContentProvider"):PreloadAsync({sound},function(_,status) ok=status==Enum.AssetFetchStatus.Success end)
 assert(ok and sound.IsLoaded and sound.TimeLength>0,"new tactical audio unavailable: "..entry.id);sound:Destroy();audioCount+=1
end end
assert(audioCount==18)
-- Native Open Cloud validation. The local simulation has no network or saved data.
do
	local shared = game:GetService("ReplicatedStorage").Airfront
	local Sim = require(shared.Core.Sim)
	local Defs = require(shared.Core.Defs)
	local map = require(shared.Core.WorldMap).get("twin_straits")
	local Protocol = require(shared.Net.Protocol)
	local W, H = map.W, map.H
	local center
	for index = 0, map.land_count - 1 do
		local tile = map:land_tile(index)
		local x, y = tile % W, tile // W
		if x < 4 or x >= W - 4 or y < 4 or y >= H - 4 then
			continue
		end
		local found = true
		for dy = -2, 2 do
			for dx = -2, 4 do
				if not map:is_contestable(tile + dx + dy * W) then
					found = false
					break
				end
			end
			if not found then break end
		end
		if found then
			center = tile
			break
		end
	end
	assert(center, "the map provides a test pocket")
	local sim = Sim.new(map, { seed = 53, nations = false, tribes = 0, max_humans = 2 })
	local attacker = sim:add_human("test-attacker", "Attacker")
	local victim = sim:add_human("test-defender", "Defender")
	assert(attacker > 0 and victim > 0)
	sim.o_spawned[attacker], sim.o_spawned[victim] = 1, 1
	sim.phase = Defs.PHASE_PLAYING
	for dy = -2, 2 do
		for dx = -2, 2 do
			local border = math.abs(dx) == 2 or math.abs(dy) == 2
			sim:set_owner(center + dx + dy * W, if border then attacker else victim)
		end
	end
	local remote = center + 4
	sim:set_owner(remote, victim)
	local wire = assert(Protocol.encode_intent({ type = "attack", tile = center, ratio = 0 }))
	local intent = assert(Protocol.decode_intent(wire))
	assert(intent.ratio == 0 and intent.tile == center)
	local gap = center - 2 * W
	sim:set_owner(gap, 0)
	sim.o_troops[attacker], sim.o_troops[victim] = 5000, 9000
	sim:_apply_intent(attacker, intent)
	assert(sim.o_tiles[victim] == 10 and sim.o_troops[attacker] == 5000, "an open ring never spends troops")
	sim:set_owner(gap, attacker)
	sim.o_troops[attacker] = 0
	sim:_apply_intent(attacker, intent)
	assert(sim.o_tiles[victim] == 1 and sim.o_troops[attacker] == 0 and sim.o_troops[victim] == 9000)
	assert(buffer.readi32(sim.owner, center * 4) == attacker and buffer.readi32(sim.owner, remote * 4) == victim)
	assert(sim:attack_between(attacker, victim) == nil, "annexation never starts an army")
	print("cozy_ui_annex: real map and simulation, wire ratio, open ring safety, zero-troop capture, remote land preserved")
end

-- Native widgets only. No match start, Analytics call or inventory write.
do
	local client = game:GetService("StarterPlayer").StarterPlayerScripts.AirfrontClient
	local W = require(client.UI.Widgets)
	local UICtx = require(client.UI.UICtx)
	local Tutorial = require(client.UI.Tutorial)
	local HelpOverlay = require(client.UI.HelpOverlay)
	local startDriver = W.start_driver
	W.start_driver = function() end

	local host = Instance.new("ScreenGui")
	local root = W.Root.new(host, { scale = 1 })
	local ctx = UICtx.new()
	ctx.root = root
	ctx.airship_bar = Rect.new(0, 0, 300, 58)
	ctx.reserved_top_left = ctx.airship_bar
	local status = W.Control.new()
	status:set_offsets(140, 60, 440, 108)
	root:add_child(status)
	local tutorial = Tutorial.new(ctx, {
		top = { panel = status },
		interact = { confirm_orders = function() return ctx.touch end },
	})
	root:add_child(tutorial)
	for _, view in { Vector2.new(1600, 900), Vector2.new(844, 390), Vector2.new(568, 320) } do
		root:set_viewport(view)
		ctx.vp = root.vp
		ctx.touch = view.X < 900
		ctx.compact = ctx.touch
		ctx.insets = if ctx.touch then { x = 38, y = 10, z = 12, w = 16 } else { x = 0, y = 0, z = 0, w = 0 }
		tutorial:begin()
		tutorial:_say(1)
		local card = tutorial._card:get_global_rect()
		assert(card.Min.Y >= status:get_global_rect().Max.Y + 6 and card.Max.Y < view.Y - ctx.insets.w,
			"tutorial card overlaps status or safe bottom: " .. tostring(card))
		assert(card.Min.X >= ctx.insets.x and card.Max.X <= view.X - ctx.insets.z, "tutorial card clips at safe edges")
		assert(tutorial._skip:is_visible_in_tree() and tutorial._skip:get_global_rect().Height >= 44)
		tutorial:_draw_mark((card.Min + card.Max) * 0.5)
		assert(not tutorial._mark.Visible, "the map hint may not point through the lesson card")
		tutorial._skip.pressed:Fire()
		assert(not tutorial.active and not tutorial._card.visible)
	end

	local help = HelpOverlay.new(ctx)
	root:add_child(help)
	local replays = 0
	help.replay_requested:Connect(function() replays += 1 end)
	help:open()
	local body = help._scroll:get_child(0):get_child(0)
	local replay = body:get_child(0)
	assert(replay.text == "REPLAY TUTORIAL" and replay:is_visible_in_tree())
	replay.pressed:Fire()
	assert(replays == 1 and not help.is_open)
	root:destroy()
	host:Destroy()
	W.start_driver = startDriver
	print("tutorial: desktop and two phone layouts, unobstructed skip and replay button")
end

table.insert(screens,"ActionTutorialAndReplay")

-- Native bot fill smoke. The match and peer objects are local to this script.
do
	local shared = game:GetService("ReplicatedStorage").Airfront
	local Defs = require(shared.Core.Defs)
	local Sim = require(shared.Core.Sim)
	local map = require(shared.Core.WorldMap).get("world")
	local Protocol = require(shared.Net.Protocol)
	local server = game:GetService("ServerScriptService").AirfrontServer
	local MatchServer = require(server.MatchServer)
	local BotRoster = require(shared.Data.BotRoster)
	local stored
	local BotStats = require(server.BotStats).new({
		GetAsync = function() return stored end,
		UpdateAsync = function(_, _, update) stored = update(stored); return stored end,
	})
	BotStats:load()
	local now, awards, wins, practice = 0, 0, 0, false
	local match = MatchServer.new({
		make_sim = function(config)
			config.tribes, config.nations, config.spawn_ticks = 0, false, 10
			return Sim.new(map, config)
		end,
		now_ms = function() return now end,
		send = function(_, op, message)
			if op == Protocol.OP.NOTICE and type(message) == "string"
				and string.find(message, "No Credits or ranked wins", 1, true) then
				practice = true
			end
		end,
		peers = function() return {} end,
		on_result = function() awards += 1 end,
		on_win = function() wins += 1 end,
		bot_stats = function(id) return BotStats:get(id) end,
		on_bot_results = function(id, results)
			BotStats:record(id, results)
			BotStats:record(id, results)
		end,
		lobby = {
			info = function() return { map_id = map.id, max = 50 } end,
			countdown = function() return math.max(0, (1000 - now) / 1000) end,
			estimate_bots = function() return 999 end,
			on_start = function() return 999 end,
			on_over = function() end,
		},
	})
	local function reach(stage)
		for _ = 1, 100 do
			if match:stage() == stage then return end
			now += 100
			match:process(0.1)
		end
		error("Native practice match never reached " .. stage)
	end

	match:join({}, { uid = "watcher", name = "Watcher", spectate = true })
	match:process(0.1)
	assert(match:stage() == "idle" and match:sim() == nil, "spectator started a bot-only match")
	local player = {}
	match:join(player, { uid = "123", name = "Tester" })
	local lobby = match:lobby_info(player)
	assert(#lobby.players == 1 and lobby.ai_commanders == 49, "lobby counts humans and AI separately")
	reach("spawn")
	local sim = match:sim()
	assert(#sim.humans == 50 and match:lobby_info(player).ai_commanders == 49, "bot fill respects lobby cap")
	local identities = match:cosmetics_map()
	for _, owner in sim.humans do
		if sim.o_bot[owner] == 1 then
			local identity = identities[owner]
			local bot = BotRoster.profile(identity.bot_id)
			assert(bot.name == sim.o_name[owner] and identity.bot and not identity.user_id)
			assert(sim.o_skill[owner] == bot.skill and identity.bot_matches == 0)
		end
	end
	reach("playing")
	match:process(0.1)
	assert(not practice and not match._ranked, "AI fill stays quiet and cannot create a ranked match")
	sim:_game_over(sim.human_keys["123"], Defs.OVER_DOMINATION)
	reach("over")
	assert(awards == 0 and wins == 0, "AI practice granted competitive rewards")
	local recorded = 0
	for owner, identity in identities do
		if identity.bot and sim.o_spawned[owner] == 1 then
			local stats = BotStats:get(identity.bot_id)
			assert(stats.matches == 1 and stats.wins == 0)
			recorded += 1
		end
	end
	assert(recorded > 0)
	print("Native bot fill OK: 1 human, 49 AI seats, isolated and idempotent AI stats")
end

table.insert(screens,"PublicAIPractice")

do
	local server = game:GetService("ServerScriptService").AirfrontServer
	local Release = require(shared.Data.ReleaseConfig)
	local Access = require(server.OwnerAccess)
	local Gate = require(server.TestingAccess)
	local Test = require(shared.Data.PrivateTest)
	local Metrics = require(shared.Data.PlaytestMetrics)
	local player = { UserId = Test.OWNER }
	assert(Release.CHANNEL == "private" and not Release.can_purchase())
	assert(Access.allowed(Test.OWNER, Test.OWNER, false) and not Access.allowed(42, Test.OWNER, false))
	assert(Release.store_name("RofrontPurchases_v1") == "RofrontPurchases_v1")
	Release.CHANNEL = "live"
	assert(Access.allowed(42, Test.OWNER, false) and Release.can_purchase())
	assert(not Test.allowed(Test.OWNER, Test.OWNER, Test.UNIVERSE))
	assert(Release.store_name("RofrontPurchases_v1") == "RofrontPurchases_v1_live_v1")
	assert(not Gate.new(Test.OWNER, Test.UNIVERSE):request(player, true).ok)
	Release.CHANNEL = "private"
	assert(require(server.ServerMain).start ~= nil, "server entry point loads")
	assert(require(client.UI.PlaytestCapture).new ~= nil, "performance capture entry point loads")
	assert(Test.allowed(Test.OWNER, Test.OWNER, Test.UNIVERSE) and not Test.allowed(42, Test.OWNER, Test.UNIVERSE))
	local frames = table.create(5339, 1000 / 60)
	for _ = 1, 60 do frames[#frames + 1] = 40 end
	frames[#frames + 1] = 60
	local report = Metrics.summarize(frames, 5339 / 60 + 2.46, { 47, 52 })
	assert(report.p95Ms < 17 and report.p99Ms == 40 and report.worstMs == 60)
	assert(report.over33 == 61 and report.over50 == 1 and report.ping95Ms == 52)
	report.device, report.mode, report.map, report.skin = "phone", "online", "world", "neon"
	report.flagFill, report.countryColor, report.peakChangedTiles = true, 2, 5363
	report.movingFrames, report.tileFrames, report.cameraOver33, report.territoryOver33 = 500, 700, 18, 21
	report.placeVersion = -1
	assert(Metrics.clean(report).placeVersion == nil, "client cannot stamp server fields")
	report.p99Ms = 0 / 0
	assert(Metrics.clean(report) == nil, "reject non-finite reports")
	print("Native release channels OK: isolated stores and sandbox authorization")
end

return {contentFitDockCases=5,cameraFollow60Hz=true,mapContourCache=true,actionTutorial=true,publicAIPractice=true,encircledAnnex=true,borderZoomBudget=true,menuLayoutCases=layoutChecks,noHomeReserve=true,maxOrderShare=.75,pixelShips=true,newScreens=screens,atlasImagesLoaded=5,newAudioLoaded=audioCount,classicFlagAtlasesLoaded=5,version=game.PlaceVersion,privateGuard=true,productCount=count,baseBombs=Arsenal.BASE_BOMBS,advancedEquipmentLocked=true,cosmeticsRobuxOnly=true,colorShopButtons=colorButtons,nativeFlagPriceLabel=flagPrice,rendered=rendered,replacementImagesLoaded=loaded}
