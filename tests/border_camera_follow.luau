local FX=require('../src/client/Map/TerritoryEffects')
local Cache=require('../src/shared/Data/BorderContourCache')
local Strokes=require('../src/shared/Data/BorderStrokes')
require('./prelude')
local rig={scale=1,version=1,x=0,y=0,w=256,h=160}
function rig:viewport_size() return Vector2.new(self.w,self.h) end
function rig:screen_to_map(x,y) return (x-self.x)/self.scale,(y-self.y)/self.scale end
function rig:map_to_screen(x,y) return x*self.scale+self.x,y*self.scale+self.y end
local reads=0
local edits={}
local state={W=2048,H=512}
function state:tile_owner(t) reads+=1;return edits[t] or (if t%2048%160>=80 then 1 else 0) end
local cache=Cache.new(state.W,state.H,function(t) return state:tile_owner(t) end)
while cache.pending>0 or cache.job do Cache.step(cache,16384,{0,0,256,160}) end
local beforeReads=reads
local uploads=0
local fx=setmetatable({root={},view={rig=rig,ui_scale=.6},state=state,cache=cache,styles={[1]={effect='neon',fleet_tint=0x72FFF0}},paint_elapsed=1},FX)
function fx:_image(w,h)
 if self.w==w and self.h==h and self.image then return true end
 self.w,self.h=w,h;self.pixels=buffer.create(w*h*4)
 self.image={WritePixelsBuffer=function() uploads+=1 end};return true
end
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
local cachedRasters,cachedUploads=fx.rasters,uploads
for frame=1,180 do
 rig.x=12*math.sin(frame*.07);rig.y=9*math.cos(frame*.05);rig.version+=1
 fx:tick(1/60)
 local x,y=rig:map_to_screen(fx.paint_mx,fx.paint_my)
 assert(math.abs(fx.root.Position.X.Offset-x)<1 and math.abs(fx.root.Position.Y.Offset-y)<1,'animation keeps the original translated map anchor')
 borderAt(80,60)
end
assert(fx.rasters==cachedRasters and uploads-cachedUploads==45,'covered pan animates at 15Hz without reprojecting cached geometry')
rig.x,rig.y=0,0
local count=uploads;local framesWithoutUpload=0
for frame=1,60 do
 rig.x-=7.25;rig.y=-25;rig.version+=1
 local before=uploads;fx:tick(1/60)
 local x,y=rig:map_to_screen(fx.paint_mx,fx.paint_my)
 assert(math.abs(fx.root.Position.X.Offset-x)<1 and math.abs(fx.root.Position.Y.Offset-y)<1,'pan image anchor follows every 60Hz camera frame')
 assert(fx.root.Size.X.Offset==rig.w+128 and fx.root.Size.Y.Offset==rig.h+128,'pan never stretches a cached stroke')
 if before==uploads then framesWithoutUpload+=1 end
 local left=rig:screen_to_map(0,0);borderAt(math.ceil((left+10)/80)*80,70)
end
assert(framesWithoutUpload>=35 and uploads-count<=22,'covered pan is throttled; newly uncovered geometry may upload immediately')
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
-- A competing upload keeps the previous bitmap anchored until the next slot.
local previousRasters, previousScale = fx.rasters, fx.paint_scale
rig.scale*=1.2;rig.x-=12;rig.version+=1
fx.view._map_image_written=true;fx:tick(1/60)
assert(fx.image_waiting and fx.rasters==previousRasters and fx.paint_scale==previousScale)
local worldX,worldY=rig:map_to_screen(fx.paint_mx,fx.paint_my)
assert(math.abs(fx.root.Position.X.Offset-worldX)<1 and math.abs(fx.root.Position.Y.Offset-worldY)<1)
assert(math.abs(fx.root.Size.X.Offset-448*1.2)<1)
fx.view._map_image_written=false;fx.view._map_image_slot=fx;fx:tick(1/60)
assert(not fx.image_waiting and fx.view._map_image_written and fx.rasters==previousRasters+1)
assert(fx.paint_scale==rig.scale and fx.root.Size.X.Offset==448)
print(string.format('PASS border cache camera: %d pan frames without upload; immediate teleport and resize; anchored subpixel zoom and exact settled zoom',framesWithoutUpload))

fx.view._map_image_written=nil;fx.view._map_image_slot=nil
for _,zoom in {.72,3} do
 rig.scale=zoom
 rig.x,rig.y=if zoom<1 then 7 else -140,if zoom<1 then 3 else -140
 fx:tick(1/60)
 local rasters=fx.rasters
 local patches=fx.patches or 0
 local changes={}
 for _,tile in {63*state.W+63,64*state.W+64,127*state.W+127,128*state.W+128} do
  local owner=1-state:tile_owner(tile)
  edits[tile]=owner
  table.insert(changes,tile*1024+owner)
 end
 Cache.invalidate(cache,changes)
 repeat fx:tick(1/60) until cache.pending==0 and not cache.job
 assert(fx.rasters==rasters and fx.patches>patches,'capture redraws only the affected areas')
 Strokes.animate(fx.field,.4)
 local patched=buffer.tostring(fx.pixels)
 local offsets={}
 for _,offset in fx.field.pixels do
  assert(not offsets[offset],'a cleared pixel reuses its sparse offset')
  offsets[offset]=true
 end
 local live=fx.field.live
 fx.redraw=true;fx:tick(1/60);Strokes.animate(fx.field,.4)
 assert(fx.field.live==live and patched==buffer.tostring(fx.pixels),'patched seams match a full repaint')
end
print('PASS incremental border patches match full projection at overview and close zoom')
