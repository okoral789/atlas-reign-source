-- Exact geometry and composition regression; no quantization or renderer tolerance.
local Field=require('../src/shared/Data/BorderField')
local Cache=require('../src/shared/Data/BorderContourCache')
local Cosmetics=require('../src/shared/Data/Cosmetics')
local pool={};for _,item in Cosmetics.shop_items() do if item.border then pool[#pool+1]=item end end
assert(#pool>0)
local styles={};for i=1,50 do styles[i]=pool[1+(i-1)%#pool] end
local W,H=128,64
local captured=false
local function owner(t)
 local x,y=t%W,t//W
 if (x*13+y*7)%41<3 then return 0 end
 if captured and x>=60 and x<68 then return 3 end
 return if x<64 then 1+(y//3)%25 else 26+(y//3)%25
end
local cache=Cache.new(W,H,owner)
local function drain()
 repeat Cache.step(cache,16384,{0,0,W,H}) until cache.pending==0 and not cache.job
end
drain()
-- Frozen pre-optimization segment and animation algorithms from 5028574, used only as an oracle.
local function referenceProject(contour,scale,tx,ty,pixelX,pixelY,radius,field,scaleY)
 scaleY=scaleY or scale
 local w,h=field.w,field.h
 local cw,ch=contour.w,contour.h
 local rx,ry=radius/pixelX+.5,radius/pixelY+.5
 local edgeStride=cw*ch*4
 for segment=1,contour.count or #contour.segments do
  local key=if contour.packed then buffer.readu32(contour.packed,(segment-1)*8) else contour.segments[segment]
  local last=if contour.packed then buffer.readu32(contour.packed,(segment-1)*8+4) else contour.ends[segment]
  local id=key//edgeStride;local p=(key%edgeStride)//4;local side=key%4
  if not field.styles[id] then continue end
  local x,y=p%cw,p//cw
  local ax,ay=x+(if side==1 then 1 else 0),y+(if side==3 then 1 else 0)
  local length=(last-key)/(if side<2 then cw*4 else 4)+1
  local bx,by=ax+(if side>=2 then length else 0),ay+(if side<2 then length else 0)
  local x0,y0=ax*scale+tx-.5,ay*scaleY+ty-.5
  local x1,y1=bx*scale+tx-.5,by*scaleY+ty-.5
  local left,right=math.max(0,math.ceil(x0-rx)),math.min(w-1,math.floor(x1+rx))
  local top,bottom=math.max(0,math.ceil(y0-ry)),math.min(h-1,math.floor(y1+ry))
  for y=top,bottom do
   -- Integrate the pixel footprint: a subpixel core must survive a high-DPI downsample.
   local dy=math.max(0,math.abs(y-math.clamp(y,y0,y1))*pixelY-pixelY*.5)
   for x=left,right do
    local dx=math.max(0,math.abs(x-math.clamp(x,x0,x1))*pixelX-pixelX*.5)
    local d=math.floor(dx*dx+dy*dy)
    if d<=radius*radius then
     local p=y*w+x;local old=buffer.readu8(field.distance,p)
     if d<old then
      field.active_styles[id]=true
      if old==255 then table.insert(field.pixels,p) end
      local phase=((math.floor((x-tx+.5)/scale)+(contour.ox or 0))*3+(math.floor((y-ty+.5)/scaleY)+(contour.oy or 0))*2)%128
      buffer.writeu8(field.distance,p,d);buffer.writeu16(field.source,p*2,id);buffer.writeu8(field.phase,p,phase)
     end
    end
   end
  end
 end
 return field
end

local glow={}
for d=0,Field.RADIUS_PX^2 do glow[d]=math.exp(-d*.38) end
local function color(r,g,b,a)
 return math.floor(r+(255-r)*a)+math.floor(g+(255-g)*a)*256+math.floor(b+(255-b)*a)*65536
end
local function referenceRender(field,t,out)
 out=out or buffer.create(field.w*field.h*4);buffer.fill(out,0,0)
 local palettes=field.palettes
 -- Trigonometry and color extraction happen per style/phase, not per halo pixel.
 for id in field.active_styles do
  local style=field.styles[id]
  local rgb=style.fleet_tint or 0x72FFF0
  local r,g,b=bit32.extract(rgb,16,8),bit32.extract(rgb,8,8),bit32.extract(rgb,0,8)
  local entries=palettes[id] or {};palettes[id]=entries
  for phaseIndex=0,127 do
   local phase=phaseIndex*math.pi/32;local wave=.5+.5*math.sin(phase-t*3)
   local white,core,alpha=wave*.14,.35+wave*.5,.52+wave*.35
   local kind=style.effect or "neon"
   if kind=="flame" then alpha=.65+.3*math.sin(phase*2+t*9)^2;white=.02;core=.65
   elseif kind=="electric" then white=if wave>.94 then 1 else white*.4;core=if wave>.94 then 1 else core*.4
   elseif kind=="royal" then white=.22+wave*.3;core=white;alpha=.65+wave*.2
   elseif kind=="frost" then white=.4+.5*math.sin(phase*3-t*4)^8;core=white
   elseif kind=="scan" then alpha=.3+.65*wave^6
   elseif kind=="eclipse" then alpha=.35+.6*wave^3
   elseif kind=="tide" then white=wave*.65;core=white;alpha=.5+wave*.4
   elseif kind=="nebula" or kind=="aurora" then white=.15+wave*.35;core=white end
   local entry=entries[phaseIndex] or {};entries[phaseIndex]=entry
   entry[1],entry[2]=color(r,g,b,white),color(r,g,b,core)
   entry[3],entry[4]=if kind=="electric" then .55+white*.4 else alpha,if kind=="electric" then .55+core*.4 else alpha
  end
 end
 for _,p in field.pixels do
  local c=palettes[buffer.readu16(field.source,p*2)][buffer.readu8(field.phase,p)]
  local d=buffer.readu8(field.distance,p);local core=d==0
  local alpha=math.clamp(math.floor(glow[d]*(if core then c[4] else c[3])*255),0,255)
  buffer.writeu32(out,p*4,(if core then c[2] else c[1])+alpha*16777216)
 end
 return out
end
local compared=0
for _,pixelSize in {1,2,4,7.75,9.1} do
 for _,zoom in {.31,1,3.7} do
  for _,pan in {0,.13,.49,.83} do
   local w,h=96,64;local tx,ty=pan-10,pan-4
   local f=Field.prepare(w,h,styles)
   for id=0,cache.cols*cache.rows-1 do
    local c=cache.chunks[id]
    Field.project(c,zoom/pixelSize,c.ox*zoom/pixelSize+tx,c.oy*zoom/pixelSize+ty,pixelSize,pixelSize,5,f)
   end
   local reference=Field.prepare(w,h,styles)
   for id=0,cache.cols*cache.rows-1 do
    local c=cache.chunks[id]
    referenceProject(c,zoom/pixelSize,c.ox*zoom/pixelSize+tx,c.oy*zoom/pixelSize+ty,pixelSize,pixelSize,5,reference)
   end
   for _,key in {'distance','source','phase'} do
    assert(buffer.tostring(f[key])==buffer.tostring(reference[key]),'exact optimization changed '..key)
   end
   for _,time in {0,.4,3.7} do
    assert(buffer.tostring(Field.render(f,time))==buffer.tostring(referenceRender(reference,time)),'palette sharing changed RGBA composition')
   end
   compared+=w*h
   local first=buffer.tostring(Field.render(f,.4))
   local repeated=Field.prepare(w,h,styles,f)
   for id=0,cache.cols*cache.rows-1 do local c=cache.chunks[id];Field.project(c,zoom/pixelSize,c.ox*zoom/pixelSize+tx,c.oy*zoom/pixelSize+ty,pixelSize,pixelSize,5,repeated) end
   assert(buffer.tostring(Field.render(repeated,.4))==first,'unchanged camera/owner traversal must be deterministic')
  end
 end
end
-- Shared chunk seam: exact same line must keep first-owner tie order, including captures.
local seam=Cache.new(128,64,function(t) return if t%128<64 then 1 else 2 end)
repeat Cache.step(seam,16384,{0,0,128,64}) until not seam.job and seam.pending==0
local f=Field.prepare(128,64,styles)
for id=0,1 do local c=seam.chunks[id];Field.project(c,1,c.ox,c.oy,1,1,5,f) end
assert(buffer.readu16(f.source,(32*128+63)*2)==1,'first contour owns the exact shared edge tie')
captured=true;local changes={}
for y=0,63 do for x=60,67 do changes[#changes+1]=(y*W+x)*1024+owner(y*W+x) end end
Cache.invalidate(cache,changes);drain()
local after=Field.prepare(128,64,styles)
for id=0,1 do local c=cache.chunks[id];Field.project(c,1,c.ox,c.oy,1,1,5,after) end
assert(after.active_styles[3],'captured seam is projected with its new owner')
print(string.format('PASS exact border optimization: %d byte-identical distance/source/phase pixels and RGBA at 3 phases; 50 owners sharing actual catalog styles, coast holes, chunk seam, pans/zooms and capture',compared))
