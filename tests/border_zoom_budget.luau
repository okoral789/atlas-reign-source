local F=require('../src/shared/Data/BorderField')
local FX=require('../src/client/Map/TerritoryEffects')
local style={[1]={effect='electric',fleet_tint=0x72FFF0},[2]={effect='flame',fleet_tint=0xFF9814}}
local reads=0
local job=F.begin(512,320,function(x,y)
 reads+=1
 -- Long fronts mixed with ragged coastlines and small enclaves.
 if x<0 or y<0 or x>=512 or y>=320 then return 0 end
 local edge=230+35*math.sin(y*.07)+9*math.sin(y*.71)
 if (x//23+y//19)%9==0 then return 0 end
 return if x<edge then 1 else 2
end,style)
local peak,steps=0,0
local start=os.clock()
repeat
 local before=reads;local at=os.clock();local done,work=F.step(job,FX.SAMPLE_BUDGET)
 peak=math.max(peak,os.clock()-at);steps+=1
 assert(work<=FX.SAMPLE_BUDGET and reads-before<=FX.SAMPLE_BUDGET,'bounded work per render step')
 if done then break end
 assert(steps<100,'the job completes under continuous camera movement')
until false
assert(reads==514*322,'one haloed owner snapshot, no repeated screen projection')
assert(#job.segments<20000,'coalesced contour, no GUI object per edge')
local buildTime=os.clock()-start
local savedReads=reads
local raster,paint=0,0
local field,pixels
for i=1,30 do
 local zoom=1+i*.03
 local at=os.clock()
 field=F.raster(job,zoom,-80*(zoom-1),-60*(zoom-1),5,5,5,field)
 raster+=os.clock()-at
 at=os.clock();pixels=F.render(field,i/15,pixels);paint+=os.clock()-at
end
assert(reads==savedReads,'zoom raster never samples map ownership')
-- A straight frontier stays at the same screen x while its map scale changes.
local line=F.begin(128,80,function(x) return if x>=64 then 1 else 0 end,{[1]=style[1]})
while not F.step(line,1024) do end
for _,pixelSize in {1,2,5,7.5,8} do
 local widths={}
 for _,zoom in {1,1.03,1.5,2,4} do
  local f=F.raster(line,zoom,64*(1-zoom),0,pixelSize,pixelSize,5)
  local output=F.render(f,.4);local count,maxAlpha=0,0
  for x=0,127 do
   local alpha=buffer.readu8(output,(35*128+x)*4+3)
   if alpha>0 then count+=1 end
   maxAlpha=math.max(maxAlpha,alpha)
  end
  assert(maxAlpha>120,'visible bright core including a 3840/512 = 7.5px sample')
  assert(count*pixelSize<=10+2*pixelSize,'halo width includes at most a raster pixel per side')
  widths[#widths+1]=count
 end
 for _,count in widths do assert(count==widths[1],'screen width is invariant through smooth zoom') end
end
-- Drive the layer with a cheap fake uploader; only the renderer primitive is mocked.
require('./prelude')
local C=require('../src/shared/Data/Cosmetics')
local skin
for _,item in C.shop_items() do if item.border then skin=item.id;break end end
assert(skin,'a premium border fixture exists')
local function signal()
 local callbacks={}
 return {Connect=function(_,fn) callbacks[#callbacks+1]=fn;return {Disconnect=function() end} end,Fire=function(_,...) for _,fn in callbacks do fn(...) end end}
end
local rig={scale=1,version=1}
function rig:viewport_size() return {X=256,Y=160} end
function rig:screen_to_map(x,y) return x/self.scale,y/self.scale end
function rig:map_to_screen(x,y) return x*self.scale,y*self.scale end
local ownerReads=0
local st={W=256,H=160,cosmetics={[1]={skin=skin}},tiles_changed=signal(),cosmetics_changed=signal(),snapshot_loaded=signal()}
function st:tile_owner(i) ownerReads+=1;return if i%256>=64 then 1 else 0 end
local fx=setmetatable({root={},view={rig=rig},conns={},revision=0,elapsed=1,paint_elapsed=0},FX)
function fx:_image(w,h)
 self.w,self.h=w,h;self.pixels=buffer.create(w*h*4)
 self.image={WritePixelsBuffer=function() self.uploads=(self.uploads or 0)+1 end}
 return true
end
fx:bind(st)
for _=1,120 do rig.scale+=.001;rig.version+=1;fx:tick(1/60);assert(fx.sample_work<=FX.SAMPLE_BUDGET) end
assert(fx.samples==1,'camera changes cannot schedule additional map caches')
assert(fx.field and fx.field.live>0 and fx.cache.pending==0 and not fx.cache.job,'zoom does not starve pending chunks')
local before=ownerReads
for _=1,60 do fx:tick(1/60) end
assert(ownerReads==before,'idle animation does not resample ownership')
st.tiles_changed:Fire({64*1024+1});fx:tick(1/60)
assert(ownerReads>before,'captures invalidate the cached frontier')
while fx.cache.pending>0 or fx.cache.job do fx:tick(1/60) end
local warmReads=ownerReads
local cosmeticRasters=fx.rasters
st.cosmetics[1].flag='flag_us';st.cosmetics[1].face=123;fx.paint_elapsed=0
st.cosmetics_changed:Fire();fx:tick(1/60)
assert(fx.rasters==cosmeticRasters and ownerReads==warmReads,'unrelated flag/face changes cannot invalidate border geometry')
st.cosmetics={};st.cosmetics_changed:Fire();fx:tick(1/60)
assert(not fx.root.Visible and ownerReads==warmReads,'removing cosmetics hides the old image without a map scan')
st.cosmetics={[1]={skin=skin}};st.cosmetics_changed:Fire();fx:tick(1/60)
assert(fx.root.Visible and ownerReads==warmReads,'re-equipping a cached owner needs no ownership reads')
st.snapshot_loaded:Fire();fx:tick(1/60)
assert(ownerReads>warmReads and fx.samples==2,'a new snapshot replaces stale map contours')
fx:unbind()
assert(not fx.cache and not fx.field and not fx.root.Visible,'unbind releases pending state')
print(string.format('PASS border budgets: %d owner reads over %d steps, peak step %.3fms; %d merged segments; helper build %.2fms, moving raster %.2fms, animate %.2fms average; 1x..4x zoom width and 4K core stable',reads,steps,peak*1000,#job.segments,buildTime*1000,raster/30*1000,paint/30*1000))

-- The map texture keeps its normal border; premium color lives only in the screen-space layer.
require('./prelude')
local Surface=require('../src/client/Map/MapSurface')
local host=setmetatable({W=12,N=144,hover=0,_own=buffer.create(144*4),_flags=buffer.create(144),defended=buffer.create(144),_skins={},_gradients={},_paint_details={}},Surface)
for _,key in {'pal_fill','pal_fill_hi','pal_border','pal_border_hi','pal_border_ally','pal_border_ally_hi'} do host[key]=buffer.create(8) end
host._state={owners={[1]={rgba=0x668899FF}},cosmetics={},owner_color=function() return nil end,are_allies=function() return false end}
for y=3,8 do for x=3,8 do buffer.writei32(host._own,(y*12+x)*4,1) end end
host:refresh_palette()
local before={}
for x=3,6 do before[x]=host:tile_pixel(5*12+x) end
host._state.cosmetics[1]={skin=skin};host:_load_skins();host:refresh_palette()
for x=3,6 do assert(host:tile_pixel(5*12+x)==before[x],'premium glow cannot bake a zoom-scaled border/rim into map tiles') end
assert(not host._paint_details[1],'premium-only owners keep the fast fill repaint path')
print('PASS premium border surface: no duplicated tile rim, ordinary border and fast repaint retained')
