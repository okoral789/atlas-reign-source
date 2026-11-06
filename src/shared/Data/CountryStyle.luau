--!strict
-- Approved style v1. Reuse existing permanent color entitlements; zero means random.
local Style: any = if typeof(game)=="Instance" then require(script.Parent.ProfileStyle) else require("./ProfileStyle")
local CountryStyle = {}
CountryStyle.FLAG_MIX=.60
function CountryStyle.allowed(index: any, owned: any): boolean
	return index==0 or (Style.valid(index) and index>1 and Style.allowed(index,owned))
end
function CountryStyle.rgba(index: any): number?
	if not Style.valid(index) then return nil end
	return Style.colors[index].rgb * 256 + 255
end

function CountryStyle.index(rgba: any): number?
	if type(rgba)~="number" then return nil end
	for i,color in Style.colors do if color.rgb*256+255==rgba then return i end end
	return nil
end

-- Shared by map pixels and shop previews; the original color remains the fleet/identity tint.
function CountryStyle.sample(index: any,t: number): (number,number,number)
	local entry=Style.colors[index];local stops=entry.gradient or {entry.rgb,entry.rgb}
	local p=math.clamp(t,0,1)*(#stops-1);local k=math.min(math.floor(p)+1,#stops-1);local f=p-(k-1)
	local a,b=stops[k],stops[k+1]
	return (a//65536%256)*(1-f)+(b//65536%256)*f,(a//256%256)*(1-f)+(b//256%256)*f,(a%256)*(1-f)+(b%256)*f
end

function CountryStyle.clean(values: any,ownsColor: boolean): any
	if type(values)~="table" or ownsColor~=true then return nil end
	if values.color~=0 and not (Style.valid(values.color) and values.color>1) then return nil end
	if values.flag_fill~=nil and type(values.flag_fill)~="boolean" then return nil end
	return {color=values.color,flag_fill=values.flag_fill==true}
end
return CountryStyle
