local cosmeticStressMetrics
do
	local shared = game:GetService("ReplicatedStorage").Airfront
	local client = game:GetService("StarterPlayer").StarterPlayerScripts.AirfrontClient
	local Defs = require(shared.Core.Defs)
	local C = require(shared.Data.Cosmetics)
	local Style = require(shared.Data.ProfileStyle)
	local Fleet = require(shared.Data.FleetStyles)
	local Flags = require(shared.Assets.Flags)
	local Hosted = require(shared.Assets.FrontierFlags)
	local Signal = require(shared.Core.Signal)
	local NameLayer = require(client.Map.NameLayer)

	local function count(map)
		local n = 0
		for _ in map do n += 1 end
		return n
	end
	local function timing(samples)
		table.sort(samples)
		return { n = #samples, medianMs = samples[math.ceil(#samples / 2)], p95Ms = samples[math.ceil(#samples * .95)], maxMs = samples[#samples] }
	end

	local classic, premium = {}, {}
	for _, item in C.all() do if item.kind == "flag" then table.insert(classic, item) end end
	for _, item in C.shop_items() do if item.kind == "flag" then table.insert(premium, item) end end
	assert(#classic == 258 and #premium == 38)
	local assetItems = {}
	for _, flags in { classic, premium } do
		for _, flag in flags do
			local uri = C.flag_image(flag)
			assert(string.match(uri, "^rbxassetid://[1-9]%d*$"), "unresolved flag " .. flag.id)
			local entries = assetItems[uri] or {}
			assetItems[uri] = entries
			table.insert(entries, flag)
			local big = C.flag_big(flag)
			assert(big == uri, "an unintended alternate flag texture was referenced")
		end
	end
	assert(count(assetItems) == 43 and #Flags.atlases == 5 and count(Hosted) == 38)

	local cols, rows, side = 25, 10, 25
	local width, height = cols * side, rows * side
	local owners, centers, cosmetics = {}, {}, {}
	local ownership = buffer.create(width * height * 4)
	for id = 1, cols * rows do
		local x0, y0 = (id - 1) % cols * side, (id - 1) // cols * side
		centers[id] = (y0 + side // 2) * width + x0 + side // 2
		for y = y0, y0 + side - 1 do
			for x = x0, x0 + side - 1 do buffer.writei32(ownership, (y * width + x) * 4, id) end
		end
		owners[id] = { name = (if id <= 50 then "Player " else "Nation ") .. id, kind = if id <= 50 then Defs.KIND_HUMAN else Defs.KIND_NATION, tiles = side * side, alive = true, troops = 40000 + id, spawn_tile = centers[id] }
	end
	local state = { owners = owners, owner = ownership, flags = buffer.create(width * height), cosmetics = cosmetics,
		map = { W = width, H = height, k_lin = 1 }, tick = 0, phase = Defs.PHASE_PLAYING, local_owner = 1 }
	function state:get_owner(id) return self.owners[id] end
	function state:label_tile(id) return centers[id] end
	local function styleFlags(cycle)
		for id = 1, 50 do
			local flag = if id <= #premium then premium[(id + cycle - 2) % #premium + 1] else classic[((id - 39) * 23 + cycle - 1) % #classic + 1]
			local color = Style.colors[7 + (id - 1) % (#Style.colors - 6)]
			cosmetics[id] = { flag = flag.id, face = 8318659852 + id, user_id = 8318659852 + id, color = color.rgb * 256 + 255, skin = Fleet[(id - 1) % #Fleet + 1].id, flag_fill = true }
		end
	end

	local gui = Instance.new("ScreenGui")
	local rig = { scale = 3, _vp = Vector2.new(1920, 1080), offset = 0 }
	function rig:map_to_screen(x,y) return x * self.scale + self.offset, y * self.scale end
	function rig:on_screen(x,y,pad) return x >= -pad and y >= -pad and x <= self._vp.X + pad and y <= self._vp.Y + pad end
	local layer = NameLayer.new(gui, { rig = rig })
	rig.offset = 10000
	layer:bind(state)
	layer:tick(1/60)
	assert(#layer.root:GetDescendants() == 1 and next(layer._plates) == nil, "offscreen owners allocated GUI plates")
	layer:unbind()
	rig.offset = 0
	local cold, warm, changes = {}, {}, {}
	local maxLabelDesc, maxLabelImages, maxVisible, maxVisibleFlags, maxFlagAssets = 0,0,0,0,0
	for cycle = 1, 20 do
		styleFlags(cycle)
		layer:bind(state)
		local start = os.clock()
		layer:tick(1/60)
		cold[#cold + 1] = (os.clock() - start) * 1000
		while layer._job do layer:_placement_step(state) end
		layer:tick(1/60)
		assert(count(layer._plates) == 250)
		local visible, shownFlags = 0, 0
		local used = {}
		for id, plate in layer._plates do
			if plate.frame.Visible then visible += 1 end
			if plate.frame.Visible and plate.flag.Visible then
				shownFlags += 1
				used[plate.flag.Image] = true
			end
			if id <= 50 then
				local flag = C.item(cosmetics[id].flag)
				assert(plate.flag.Image == C.flag_image(flag) and plate.flag.ImageRectOffset == Vector2.new(flag.x,flag.y)
					and plate.flag.ImageRectSize == Vector2.new(flag.w,flag.h), "wrong flag image or atlas crop")
			end
		end
		assert(visible == 250 and shownFlags == 50)
		maxVisible, maxVisibleFlags, maxFlagAssets = math.max(maxVisible, visible), math.max(maxVisibleFlags, shownFlags), math.max(maxFlagAssets, count(used))
		local descendants, images = layer.root:GetDescendants(), 0
		for _, child in descendants do if child:IsA("ImageLabel") then images += 1 end end
		maxLabelDesc, maxLabelImages = math.max(maxLabelDesc, #descendants), math.max(maxLabelImages, images)
		if cycle == 1 then
			for frame = 1, 120 do
				rig.offset = frame % 12
				local at = os.clock()
				layer:tick(1/60)
				warm[#warm + 1] = (os.clock() - at) * 1000
			end
			rig.offset = 0
			rig.offset = 10000
			layer:tick(.26)
			assert(not layer._plates[1].frame.Visible and not layer._crown.Visible)
			cosmetics[1].flag = premium[2].id
			cosmetics[1].face = 8318659852
			rig.offset = 0
			layer:tick(.26)
			assert(layer._plates[1].frame.Visible and layer._crown.Visible and layer.crown_owner == 1)
			assert(layer._plates[1].flag.Image == C.flag_image(premium[2]) and layer._plates[1].face.Image == C.face_image(8318659852))
			owners[1].tiles = 0
			layer:tick(.26)
			assert(layer._plates[1] == nil and layer:name_location(1) == nil and layer.crown_owner == 2)
			owners[1].tiles = side * side
			state.tick += NameLayer.REPLACE_TICKS
			layer:tick(.26)
			while layer._job do layer:_placement_step(state) end
			layer:tick(.26)
		end
		styleFlags(cycle + 1)
		local at = os.clock()
		layer:tick(1/60)
		changes[#changes + 1] = (os.clock() - at) * 1000
		for id = 1,50 do assert(layer._plates[id].flag.Image == C.flag_image(C.item(cosmetics[id].flag))) end
		layer:unbind()
		assert(#layer.root:GetDescendants() == 1 and next(layer._plates) == nil, "map bind retained old plates")
	end
	layer:destroy()

	local W = require(client.UI.Widgets)
	local UICtx = require(client.UI.UICtx)
	local Shop = require(client.UI.FlagShop)
	local Preview = require(client.UI.PatternPreview)
	local Prices = require(client.UI.Prices)
	local startDriver, fetch = W.start_driver, Prices.fetch_keys
	W.start_driver = function() end
	Prices.fetch_keys = function() end -- measure widgets without MarketplaceService network latency
	local root = W.Root.new(gui, { scale = 1 })
	root:set_viewport(Vector2.new(1600,900))
	local ctx = UICtx.new()
	ctx.root, ctx.vp = root, root.vp
	local owned = {}
	for _, flag in premium do owned[flag.id] = true end
	for _, style in Fleet do owned[style.id] = true end
	for index = 7,#Style.colors do owned[Style.item_id(index)] = true end
	local function session()
		return {
			inventory_changed = Signal.new(), settings_loaded = Signal.new(), settings_ready = true,
			inventory = { owned = owned, equipped = { skin = Fleet[1].id, flag = premium[1].id }, loaded = true },
			load_settings = function() return { color = 7, flag_fill = true } end,
		}
	end
	local shop = Shop.new(ctx)
	root:add_child(shop)
	local shopOpen, shopRestyle, shopColor, shopClose = {}, {}, {}, {}
	local sessions, stable = {}, {}
	local maxShopDesc, maxShopImages, maxShopEffects, maxPartRecords = 0,0,0,0
	for cycle = 1, 20 do
		local filter = ({ "patterns", "owned", "flags", "colors", "featured" })[(cycle - 1) % 5 + 1]
		ctx.session = session()
		table.insert(sessions, ctx.session)
		shop:bind(ctx.session)
		local start = os.clock()
		shop:open(filter)
		shopOpen[#shopOpen + 1] = (os.clock() - start) * 1000
		local map, catalog = shop.preview_map, shop._cards[2]
		local at = os.clock()
		local skin = Fleet[if cycle % 2 == 0 then 4 else 5]
		shop:preview_item("skin", skin.id)
		Preview.animate(shop.preview_map, 1)
		for _, preview in shop._animated do Preview.animate(preview, 1) end
		shopRestyle[#shopRestyle + 1] = (os.clock() - at) * 1000
		local effect = assert(shop._showcase_ui.effect_label, "preview border did not load")
		assert(map:GetAttribute("TerritoryEffect") == skin.effect)
		at = os.clock()
		shop:preview_item("color", if cycle % 2 == 0 then 7 else 8)
		shopColor[#shopColor + 1] = (os.clock() - at) * 1000
		assert(shop.preview_map == map and shop._cards[2] == catalog and shop._showcase_ui.effect_label == effect,
			"preview choice replaced the showcase, catalog or unchanged border")
		if cycle == 1 then
			shop:preview_item("skin", false)
			assert(effect.Parent == nil and map:GetAttribute("TerritoryEffect") == nil, "reset retained the old effect")
			shop:preview_item("skin", skin.id)
			assert(shop._showcase_ui.effect_label ~= effect and shop._showcase_ui.effect_label.Parent == map)
		end
		local descendants, images, effects = shop.gui:GetDescendants(), 0, 0
		for _, child in descendants do
			if child:IsA("ImageLabel") then
				images += 1
				if child.Name == "ContinuousBorderPreview" then effects += 1 end
			end
		end
		local parts = count(shop._host._parts)
		local fingerprint = table.concat({ #descendants, images, effects, parts }, "/")
		if stable[filter] then assert(stable[filter] == fingerprint, "reopening " .. filter .. " grew or dropped widget/effect instances") end
		stable[filter] = fingerprint
		maxShopDesc, maxShopImages, maxShopEffects, maxPartRecords = math.max(maxShopDesc,#descendants), math.max(maxShopImages,images), math.max(maxShopEffects,effects), math.max(maxPartRecords,parts)
		at = os.clock()
		shop:close()
		W.step(.3)
		shopClose[#shopClose + 1] = (os.clock() - at) * 1000
		task.wait()
	end
	local function liveHandlers()
		local n = 0
		for _, bound in sessions do
			n += #bound.inventory_changed._handlers + #bound.settings_loaded._handlers
		end
		return n
	end
	local sessionHandlersBound = liveHandlers()
	assert(sessionHandlersBound == 2, "rebound shop retained " .. sessionHandlersBound .. " session listeners")
	shop:queue_free()
	local sessionHandlersDisposed = liveHandlers()
	assert(sessionHandlersDisposed == 0, "destroyed shop retained session listeners")
	assert(#root.children == 0)
	root:destroy()
	gui:Destroy()
	W.start_driver, Prices.fetch_keys = startDriver, fetch

	local downloaded, maxTextureBytes = 0, 0
	local start = os.clock()
	for uri, flags in assetItems do
		local img = game:GetService("AssetService"):CreateEditableImageAsync(Content.fromUri(uri))
		assert(img and img.Size.X > 0, "flag texture unavailable: " .. uri)
		local dimensions = img.Size
		maxTextureBytes += dimensions.X * dimensions.Y * 4
		for _, item in flags do
			assert(item.x >= 0 and item.y >= 0 and item.x+item.w <= dimensions.X and item.y+item.h <= dimensions.Y, "invalid loaded flag crop " .. item.id)
		end
		img:Destroy()
		downloaded += 1
	end
	cosmeticStressMetrics = {
		version = game.PlaceVersion, owners = 250, humanOwners = 50, aiOwners = 200, bindCycles = 20, shopCycles = 20,
		maxVisible = maxVisible, maxVisibleFlags = maxVisibleFlags, maxLabelDesc = maxLabelDesc,
		maxLabelImages = maxLabelImages, maxFlagAssets = maxFlagAssets, classicFlags = #classic, premiumFlags = #premium,
		flagTexturesLoaded = downloaded, decodedTextureRgbaBytes = maxTextureBytes, flagAssetCheckMs = (os.clock() - start) * 1000,
		labelCold = timing(cold), labelWarm = timing(warm), labelRestyle = timing(changes),
		shopOpen = timing(shopOpen), shopRestyle = timing(shopRestyle), shopColor = timing(shopColor), shopClose = timing(shopClose),
		maxShopDesc = maxShopDesc, maxShopImages = maxShopImages, maxShopEffects = maxShopEffects,
		maxPartRecords = maxPartRecords, sessionHandlersBound = sessionHandlersBound, sessionHandlersDisposed = sessionHandlersDisposed,
	}
end
return {cosmetics=cosmeticStressMetrics}
