-- Native proportional cropping: works when Roblox serves a lower-resolution copy of an image.
local L=require("./Look")
local Artwork={}
function Artwork.new(parent,image,source,rect,pos,size)
 local outer=L.make("Frame",{Name="Artwork",BackgroundTransparency=1,Position=pos,Size=size},parent)
 local crop=L.make("Frame",{Name="Crop",BackgroundTransparency=1,ClipsDescendants=true,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(1,1)},outer)
 L.make("UIAspectRatioConstraint",{AspectRatio=rect[3]/rect[4],AspectType=Enum.AspectType.FitWithinMaxSize},crop)
 L.make("ImageLabel",{Name="Image",BackgroundTransparency=1,Image=image,ScaleType=Enum.ScaleType.Stretch,
  Position=UDim2.fromScale(-rect[1]/rect[3],-rect[2]/rect[4]),Size=UDim2.fromScale(source[1]/rect[3],source[2]/rect[4])},crop)
 return outer
end
return Artwork
