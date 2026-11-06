--!nonstrict
local CrateOdds = {}

local function make(class, props, parent)
	local object = Instance.new(class)
	for k, v in props do object[k] = v end
	object.Parent = parent
	return object
end

function CrateOdds.show(owned, cosmetics, theme)
	local player = game:GetService("Players").LocalPlayer
	local old = player.PlayerGui:FindFirstChild("FrontierCrateOdds")
	if old then old:Destroy() end
	local gui = make("ScreenGui", { Name = "FrontierCrateOdds", ResetOnSpawn = false, IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets, DisplayOrder = 80, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player.PlayerGui)
	local dim = make("TextButton", { Text = "", Modal = true, AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(2, 8, 15),
		BackgroundTransparency = 0.2, Size = UDim2.fromScale(1, 1) }, gui)
	local panel = make("Frame", { BackgroundColor3 = theme.GLASS_SOLID.color, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -24, 1, -24) }, dim)
	make("UISizeConstraint", { MaxSize = Vector2.new(520, 440) }, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, panel)
	make("UIStroke", { Color = theme.AMBER, Transparency = 0.4 }, panel)
	make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -75, 0, 25),
		FontFace = theme.font(800), TextSize = 17, TextColor3 = theme.TEXT, TextXAlignment = Enum.TextXAlignment.Left,
		Text = "CRATE DETAILS · YOUR ODDS" }, panel)
	local close = make("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 7), Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = theme.GLASS_RAISED.color, Text = "×", TextColor3 = theme.TEXT, TextSize = 25, FontFace = theme.font(700) }, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, close)
	close.Activated:Connect(function() gui:Destroy() end)
	make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 40), Size = UDim2.new(1, -32, 0, 36),
		FontFace = theme.font(500), TextSize = 13, TextColor3 = theme.TEXT_2, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
		Text = "One item per crate. Rounded percentages may not add to exactly 100%. Odds change after each unlock." }, panel)
	local list = make("ScrollingFrame", { Name = "Outcomes", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(14, 80),
		Size = UDim2.new(1, -28, 1, -90), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 5, ScrollBarImageColor3 = theme.AMBER }, panel)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }, list)
	for i, outcome in ipairs(cosmetics.outcomes(owned)) do
		local item = outcome.item
		make("TextLabel", { LayoutOrder = i, BackgroundColor3 = theme.GLASS_RAISED.color, BackgroundTransparency = 0.15,
			BorderSizePixel = 0, Size = UDim2.new(1, -8, 0, 34), FontFace = theme.font(600), TextSize = 14,
			TextColor3 = theme.TEXT, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
			Text = string.format("  %s · %s   —   %.8f%%", item.name, item.kind, outcome.odds * 100) }, list)
	end
end

return CrateOdds
