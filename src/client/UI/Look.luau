--!nonstrict
-- Shared native styling for Atlas Reign's actual game screens, 2026-10-31.
local T=require("./UITheme")
local Look={}
Look.BG=Color3.fromRGB(5,19,33)
Look.PANEL=Color3.fromRGB(8,29,47)
Look.RAISED=Color3.fromRGB(15,44,64)
Look.INK=Color3.fromRGB(240,249,255)
Look.MUTED=Color3.fromRGB(160,190,207)
Look.GOLD=Color3.fromRGB(255,207,86)
Look.ACCENT=Color3.fromRGB(54,236,219)
Look.LINE=Color3.fromRGB(42,113,144)
function Look.make(class,props,parent)
	local o=Instance.new(class)
	if props.ZIndex==nil and parent and parent:IsA("GuiObject") and o:IsA("GuiObject") then props.ZIndex=parent.ZIndex+1 end
	for k,v in props do o[k]=v end;o.Parent=parent;return o
end
function Look.round(o,r)
	Look.make("UICorner",{CornerRadius=UDim.new(0,r or 10)},o)
end
function Look.outline(o,color,thickness)
	return Look.make("UIStroke",{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Color=color or Look.LINE,Thickness=thickness or 1,Transparency=.12},o)
end
function Look.card(parent,name,pos,size,color)
	local card=Look.make("Frame",{Name=name,Position=pos,Size=size,BackgroundColor3=color or Look.RAISED,BorderSizePixel=0},parent)
	Look.round(card,12);Look.outline(card)
	Look.make("UIGradient",{Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(170,200,225)),Rotation=90},card)
	return card
end
function Look.icon(parent,name,pos,size,color)
	return Look.make("ImageLabel",{Name="Icon_"..name,BackgroundTransparency=1,Image=T.icon(name) or "",ImageColor3=color or Look.ACCENT,Position=pos,Size=size,ScaleType=Enum.ScaleType.Fit},parent)
end
function Look.badge(parent,name,pos,size)
	local art=require(game:GetService("ReplicatedStorage").Airfront.Assets.DesignExtras)
	return require("./Artwork").new(parent,art.image,art.size,assert(art.rects[name]),pos,size)
end
function Look.label(parent,text,size,pos,dim,color,weight)
return Look.make("TextLabel",{BackgroundTransparency=1,Text=text,TextSize=size or 15,FontFace=T.font(weight or 600),
		TextColor3=color or Look.INK,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd,
		Position=pos or UDim2.new(),Size=dim or UDim2.fromScale(1,1)},parent)
end
function Look.button(parent,text,pos,dim,fn,primary)
	local b=Look.make("TextButton",{Text=text,FontFace=T.font(700),TextSize=14,AutoButtonColor=false,BorderSizePixel=0,
		TextColor3=if primary then Look.BG else Look.INK,BackgroundColor3=if primary then Look.ACCENT else Look.RAISED,
		Position=pos,Size=dim},parent);Look.round(b,10);Look.outline(b,if primary then Look.ACCENT else Look.LINE)
	Look.make("UIGradient",{Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(185,220,235)),Rotation=90},b)
	b.MouseEnter:Connect(function() b.BackgroundTransparency=.15;local sound=require("./Widgets").button_sound;if sound then sound("hover",b) end end)
	b.MouseLeave:Connect(function() b.BackgroundTransparency=0 end)
	b.Activated:Connect(function() local sound=require("./Widgets").button_sound;if sound then sound("click",b) end;fn() end);return b
end
function Look.surface(parent,title,subtitle,max)
	local panel=Look.make("Frame",{Name="Panel",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),
		Size=UDim2.new(1,-24,1,-30),BackgroundColor3=Look.PANEL,BorderSizePixel=0},parent)
	Look.make("UISizeConstraint",{MaxSize=max or Vector2.new(820,580)},panel);Look.round(panel,14)
	Look.outline(panel,Look.ACCENT)
	Look.make("UIGradient",{Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(140,175,205)),Rotation=90},panel)
	Look.label(panel,title,26,UDim2.fromOffset(24,15),UDim2.new(1,-110,0,34),Look.INK,900).Name="Section"
	Look.label(panel,subtitle,13,UDim2.fromOffset(24,53),UDim2.new(1,-110,0,24),Look.MUTED,600).Name="Heading"
	return panel
end
function Look.modal(player,name,title,subtitle,max)
	local gui=Look.make("ScreenGui",{Name=name,Enabled=false,IgnoreGuiInset=true,ScreenInsets=Enum.ScreenInsets.DeviceSafeInsets,
		ResetOnSpawn=false,DisplayOrder=70,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},nil)
	gui.Parent=player:WaitForChild("PlayerGui")
	local dim=Look.make("TextButton",{Name="Dim",Text="",Modal=true,AutoButtonColor=false,Size=UDim2.fromScale(1,1),
		BackgroundColor3=Look.BG,BackgroundTransparency=.28},gui)
	local panel=Look.surface(dim,title,subtitle,max)
	return gui,panel
end
return Look
