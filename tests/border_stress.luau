-- Repeatable CPU benchmark; run from repo root with Lune. No Roblox GPU/upload timings or FPS.
-- Optional --out=build/cosmetic-stress/border-final.json. Ownership and workloads are deterministic.
local fs=require('@lune/fs')
local serde=require('@lune/serde')
local process=require('@lune/process')
local Cache=require('../src/shared/Data/BorderContourCache')
local Field=require('../src/shared/Data/BorderField')
local FX=require('../src/client/Map/TerritoryEffects')
local C=require('../src/shared/Data/Cosmetics')
local WorldMap=require('../src/shared/Core/WorldMap')
-- Load hot modules before the test-only global datatype shim (getfenv deoptimizes later modules).
require('./prelude')
local out='build/cosmetic-stress/border-final.json'
for _,arg in process.args do out=string.match(arg,'^%-%-out=(.+)$') or out end
local report={schema=1,runtime='Lune 0.10.2; CPU only, no native image upload/GPU',fixture_version=1,budget=FX.SAMPLE_BUDGET,viewports={},limitations={'Real World geography, deterministic synthetic ownership and captures; not a live match replay','Native EditableImage upload, Roblox frame scheduling and device GPU are excluded','gcinfo is sampled heap usage; forced collection is unavailable'}}
local function summary(samples)
 local sorted=table.clone(samples);table.sort(sorted);local total=0
 for _,v in samples do total+=v end
 local function pct(p) return sorted[math.max(1,math.ceil(#sorted*p))] or 0 end
 return {n=#samples,mean_ms=if #samples>0 then total/#samples else 0,p95_ms=pct(.95),p99_ms=pct(.99),max_ms=pct(1),total_ms=total}
end
local function cacheSize(cache)
 local bytes,segments,chunks=0,0,0
 for _,chunk in cache.chunks do bytes+=buffer.len(chunk.packed);segments+=chunk.count;chunks+=1 end
 return {packed_bytes=bytes,segments=segments,chunks=chunks,pending=cache.pending+(if cache.job then 1 else 0)}
end
print('SETUP loading actual World')
local map=WorldMap.get('world');local W,H=map.W,map.H
print('SETUP loaded',W,H,map.land_count)
assert(W==2000 and H==1000)
local base=buffer.create(W*H*4);local seeds={};local counts=table.create(50,0)
for i=1,50 do local tile=map:land_tile(math.floor((i-.5)*map.land_count/50));seeds[i]={tile%W,tile//W} end
for k=0,map.land_count-1 do
 local t=map:land_tile(k);local x,y=t%W,t//W;local owner,d=0,math.huge
 for id,seed in seeds do local dx,dy=x-seed[1],y-seed[2];local dd=dx*dx+dy*dy;if dd<d then owner,d=id,dd end end
 buffer.writei32(base,t*4,owner);counts[owner]+=1
end
print('SETUP 50 ownership regions ready')
for _,n in counts do assert(n>0,'all 50 styled countries occupy real land') end
local frontier={}
for t=0,W*H-2 do
 local id=buffer.readi32(base,t*4)
 if id>0 and t%W<W-1 then local other=buffer.readi32(base,(t+1)*4);if other>0 and other~=id then frontier[#frontier+1]=t end end
end
assert(#frontier>=50)
local patches={}
for i=1,50 do
 local t=frontier[math.floor((i-.5)*#frontier/50)+1];local x,y=t%W,t//W;local cells={}
 for dy=-2,1 do for dx=-2,1 do
  local xx,yy=x+dx,y+dy
  if xx>=0 and xx<W and yy>=0 and yy<H then
   local tile=yy*W+xx;local id=buffer.readi32(base,tile*4)
   if id>0 then cells[#cells+1]={tile,id,1+id%50} end
  end
 end end
 patches[i]=cells
end
local skins={}
for _,item in C.shop_items() do if item.border then skins[#skins+1]=item.id end end
table.sort(skins);assert(#skins>0)
local cosmetics={};for i=1,50 do cosmetics[i]={skin=skins[1+(i-1)%#skins]} end
report.map={id='world',w=W,h=H,land=map.land_count,countries=50,distinct_border_styles=#skins,frontier_tiles=#frontier,ownership='50 seeded Voronoi regions on actual land; water stays unowned'}
local function signal()
 local callbacks={}
 return {Connect=function(_,fn) callbacks[fn]=true;return {Disconnect=function() callbacks[fn]=nil end} end,Fire=function(_,...) for fn in callbacks do fn(...) end end}
end
local function make(w,h)
 local owner=buffer.create(buffer.len(base));buffer.copy(owner,0,base)
 local state={W=W,H=H,cosmetics=cosmetics,reads=0,tiles_changed=signal(),cosmetics_changed=signal(),snapshot_loaded=signal()}
 function state:tile_owner(t) self.reads+=1;return buffer.readi32(owner,t*4) end
 local rig={w=w,h=h,x=0,y=0,scale=math.min(w/W,h/H),version=1}
 function rig:viewport_size() return Vector2.new(self.w,self.h) end
 function rig:map_to_screen(x,y) return x*self.scale+self.x,y*self.scale+self.y end
 function rig:screen_to_map(x,y) return (x-self.x)/self.scale,(y-self.y)/self.scale end
 local fx=setmetatable({root={Destroy=function() end},view={rig=rig},conns={},paint_elapsed=1,uploads=0,image_allocations=0},FX)
 function fx:_image(iw,ih)
  if self.w==iw and self.h==ih and self.image then return true end
  if self.image then self.image:Destroy() end
  self.w,self.h=iw,ih;self.pixels=buffer.create(iw*ih*4);self.image_allocations+=1
  self.image={WritePixelsBuffer=function(_,_,_,bytes) assert(buffer.len(bytes)==iw*ih*4);self.uploads+=1 end,Destroy=function() end}
  return true
 end
 fx:bind(state)
 return fx,rig,state,owner
end
local function measure(fx,frames,update)
 local wallStart=os.clock()
 local times,read0,upload0,raster0={},fx.state.reads,fx.uploads,fx.rasters or 0
 local maxWork,maxPending,maxHeap=0,0,gcinfo()
 for frame=1,frames do
  assert(os.clock()-wallStart<60,'one benchmark scenario exceeded its 60s safety limit')
  if update then update(frame) end
  local at=os.clock();fx:tick(1/60);times[#times+1]=(os.clock()-at)*1000
  assert(fx.sample_work<=FX.SAMPLE_BUDGET,'cache work budget exceeded')
  maxWork=math.max(maxWork,fx.sample_work);maxPending=math.max(maxPending,fx.cache.pending+(if fx.cache.job then 1 else 0));maxHeap=math.max(maxHeap,gcinfo())
 end
 local stats=summary(times);stats.owner_reads=fx.state.reads-read0;stats.uploads=fx.uploads-upload0;stats.rasters=(fx.rasters or 0)-raster0;stats.max_work=maxWork;stats.peak_pending=maxPending;stats.heap_peak_kib=maxHeap
 return stats
end
local function drain(fx,limit)
 local times={};local maxWork=0
 repeat
  local at=os.clock();fx:tick(1/60);times[#times+1]=(os.clock()-at)*1000
  maxWork=math.max(maxWork,fx.sample_work);assert(fx.sample_work<=FX.SAMPLE_BUDGET)
  assert(#times<=limit,'cache did not converge after captures stopped')
 until fx.cache.pending==0 and not fx.cache.job
 local stats=summary(times);stats.max_work=maxWork;return stats
end
local weak=setmetatable({},{__mode='v'})
for _,viewport in {{'phone',390,844},{'desktop',1920,1080},{'4k',3840,2160}} do
 local name,w,h=unpack(viewport);local fx,rig,state,owner=make(w,h)
 local result={name=name,width=w,height=h};local initial=gcinfo()
 result.cold=drain(fx,1024);result.cache=cacheSize(fx.cache);result.cold.owner_reads=state.reads
 print(name,"cold",result.cold.n,result.cold.mean_ms,result.cold.max_ms,"segments",result.cache.segments)
 local fit=rig.scale
 result.idle=measure(fx,60)
 result.pan=measure(fx,120,function(i)
  rig.scale=fit*2;rig.x=w*.2*math.sin(i*.06)-w*.3;rig.y=-h*.15+math.cos(i*.03)*h*.07;rig.version+=1
 end)
 result.zoom=measure(fx,120,function(i)
  rig.scale=fit*(1.5+math.sin(i*.035));rig.x=w/2-W*rig.scale/2;rig.y=h/2-H*rig.scale/2;rig.version+=1
 end)
 assert(result.pan.owner_reads==0 and result.zoom.owner_reads==0,'warm camera motions cannot scan map ownership')
 result.teleport=measure(fx,60,function(i)
  rig.scale=fit*8;local seed=seeds[1+(i*17)%50];rig.x=w/2-seed[1]*rig.scale;rig.y=h/2-seed[2]*rig.scale;rig.version+=1
 end)
 assert(result.teleport.owner_reads==0)
 rig.scale=fit;rig.x,rig.y=0,0;rig.version+=1
 local function captures(fronts)
  local batch=0;local changed=0;local invalidations={}
  local stats=measure(fx,120,function(frame)
   if frame%6~=0 then return end
   batch+=1;local changes={}
   for i=1,fronts do
    local patch=patches[1+((i-1)*13)%50]
    for _,cell in patch do
     local tile,id=cell[1],cell[if batch%2==0 then 2 else 3]
     if buffer.readi32(owner,tile*4)~=id then buffer.writei32(owner,tile*4,id);changes[#changes+1]=tile*1024+id end
    end
   end
   changed+=#changes;local at=os.clock();state.tiles_changed:Fire(changes);invalidations[#invalidations+1]=(os.clock()-at)*1000
  end)
  stats.invalidation=summary(invalidations);stats.changed_tiles=changed;stats.fronts=fronts;stats.updates_hz=10;stats.backlog_at_stop=fx.cache.pending+(if fx.cache.job then 1 else 0)
  stats.drain=drain(fx,1024);stats.after=cacheSize(fx.cache)
  return stats
 end
 result.captures_4_fronts=captures(4)
 result.captures_50_fronts=captures(50)
 -- The fully drained cache must be byte-exact against a fresh scan of current ownership.
 local verify=Cache.new(W,H,function(t) return buffer.readi32(owner,t*4) end)
 repeat Cache.step(verify,FX.SAMPLE_BUDGET,{0,0,W,H}) until verify.pending==0 and not verify.job
 for id,chunk in verify.chunks do assert(buffer.tostring(chunk.packed)==buffer.tostring(fx.cache.chunks[id].packed),'capture cache disagrees with fresh ownership') end
 result.image={width=fx.w,height=fx.h,allocations=fx.image_allocations,bytes=buffer.len(fx.pixels)}
 result.heap={before_kib=initial,after_kib=gcinfo()}
 weak[#report.viewports+1]=fx.cache;fx:unbind();assert(not fx.cache and not fx.field and not fx.root.Visible,'unbind retains no map cache or visible image');fx:destroy()
 result.lifecycle_references_cleared=true
 table.insert(report.viewports,result)
 print(string.format('%s: cold %d frames, zoom mean/p95/p99/max %.2f/%.2f/%.2f/%.2f ms; 50-front backlog %d, drain %d frames; cache %.1f KiB',name,result.cold.n,result.zoom.mean_ms,result.zoom.p95_ms,result.zoom.p99_ms,result.zoom.max_ms,result.captures_50_fronts.backlog_at_stop,result.captures_50_fronts.drain.n,result.cache.packed_bytes/1024))
end
-- Strictly bounded pathological control: 128x128, never a full 2M checkerboard.
local dense=Cache.new(128,128,function(t) return 1+(t%128+t//128)%50 end)
local denseTimes={}
repeat local at=os.clock();local work=Cache.step(dense,FX.SAMPLE_BUDGET,{0,0,128,128});denseTimes[#denseTimes+1]=(os.clock()-at)*1000;assert(work<=FX.SAMPLE_BUDGET) until dense.pending==0 and not dense.job
local styles={};for i=1,50 do styles[i]={effect='electric',fleet_tint=0x72FFF0} end
local denseRaster={};local field
for _=1,12 do
 local at=os.clock();field=Field.prepare(256,256,styles,field)
 for _,chunk in dense.chunks do Field.project(chunk,2,chunk.ox*2,chunk.oy*2,1,1,5,field) end
 Field.render(field,.4);denseRaster[#denseRaster+1]=(os.clock()-at)*1000
end
report.fragmentation={width=128,height=128,cache=cacheSize(dense),build=summary(denseTimes),project_and_render=summary(denseRaster),full_2m_upper_bound_bytes=2000000*32}
assert(report.fragmentation.cache.packed_bytes==128*128*32)
-- Encourage ordinary collection without relying on an unsupported forced-GC API.
for _=1,48 do local garbage=buffer.create(1024*1024);buffer.writeu8(garbage,0,1) end
local collected=0;for i=1,3 do if weak[i]==nil then collected+=1 end end
report.lifecycle={released_caches=collected,total_caches=3,heap_final_kib=gcinfo(),forced_gc=false}
fs.writeDir('build/cosmetic-stress');fs.writeFile(out,serde.encode('json',report,true))
print(string.format('PASS border stress; bounded fragmentation mean/max %.2f/%.2f ms; %d/3 discarded map caches collected; %s',report.fragmentation.project_and_render.mean_ms,report.fragmentation.project_and_render.max_ms,collected,out))
