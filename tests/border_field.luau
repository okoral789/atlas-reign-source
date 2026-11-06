local F=require("../src/shared/Data/BorderField")
local style={[1]={effect="neon",fleet_tint=0x72FFF0}}
local function territory(x,y) return if x>=10 and x<=49 and y>=10 and y<=29 then 1 else 0 end
local field=F.build(64,40,territory,style)
local a,b=F.render(field,0),F.render(field,.8)
assert(buffer.tostring(a)~=buffer.tostring(b),"the continuous field animates")
for y=10,29 do for x=10,49 do
 local alpha=buffer.readu8(a,(y*64+x)*4+3)
 if x==10 or x==49 or y==10 or y==29 then assert(alpha>100,"no gaps along the complete perimeter") end
end end
assert(buffer.readu8(a,(20*64+30)*4+3)==0,"no effect in country interiors")
assert(buffer.readu8(a,(2*64+2)*4+3)==0,"no scattered decorative particles")
assert(#F.build(64,40,function() return 1 end,style).pixels==0,"viewport edges are not country borders")
assert(#F.build(64,40,function() return 2 end,style).pixels==0,"captured land loses the previous owner's effect")
local hole=F.build(64,40,function(x,y) return if x>=27 and x<=33 and y>=17 and y<=23 then 0 else territory(x,y) end,style)
assert(buffer.readu8(hole.distance,16*64+30)==0,"enclaves have their own exact frontier")
local hashes={}
for _,kind in {"neon","flame","royal","frost","nebula","scan","electric","eclipse","tide","aurora"} do
 style[1].effect=kind;local output=buffer.tostring(F.render(field,1.25))
 -- Aurora and Nebula share the soft plasma treatment; their purchased palettes differ.
 if kind~="aurora" then assert(not hashes[output],"distinct motion signature: "..kind);hashes[output]=true end
end
local start=os.clock()
local large=F.build(512,320,function(x,y) return if x>=100 and x<400 and y>=80 and y<250 then 1 else 0 end,style)
local elapsed=os.clock()-start
assert(#large.pixels<512*320 and buffer.len(F.render(large,2))==512*320*4,"bounded image and sparse animated halo")
print(string.format("PASS continuous border field: complete contour, no false viewport edges/interior icons, capture, enclaves, motion signatures; 512x320 build %.3fs",elapsed))
