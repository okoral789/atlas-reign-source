local Cache=require('../src/shared/Data/BorderContourCache')
local Field=require('../src/shared/Data/BorderField')
local reads=0
local W,H=2000,1000
local cache=Cache.new(W,H,function(t)
 reads+=1;local x,y=t%W,t//W
 if (x//71+y//67)%7==0 then return 0 end
 return if x<1000+120*math.sin(y*.021) then 1 else 2
end)
local rect={800,350,1100,600}
local steps,work,peak,segments=0,0,0,0
local firstContour
local start=os.clock()
repeat
 local at=os.clock();local used=Cache.step(cache,16384,rect)
 peak=math.max(peak,os.clock()-at);steps+=1;work+=used
 assert(used<=16384)
 if steps==1 then assert(#cache.changed>=1,'a visible chunk is ready in the first frame') end
 for _,id in cache.changed do if cache.chunks[id].count>0 and not firstContour then firstContour=steps end end
 assert(steps<1000)
until cache.pending==0 and not cache.job
for _,chunk in cache.chunks do segments+=chunk.count;assert(not chunk.ids and not chunk.owner,'completed caches retain only packed contours') end
local before=reads
for i=1,240 do assert(Cache.step(cache,16384,{i*31%1900,i*19%900,i*31%1900+100,i*19%900+100})==0) end
assert(reads==before,'warm pans and teleports cannot sample ownership')
assert(segments<150000,'representative 2M map contour storage is bounded')
Cache.invalidate(cache,{(64*W+64)*1024+2})
assert(cache.pending==3 and cache.dirty[0*cache.cols+1] and cache.dirty[1*cache.cols+0] and cache.dirty[1*cache.cols+1],'boundary capture invalidates own and both adjacent halos')
for _=1,100 do Cache.invalidate(cache,{(64*W+64)*1024+2}) end
assert(cache.pending==3,'duplicate captures cannot grow the queue')
while cache.pending>0 or cache.job do Cache.step(cache,16384,rect) end
print(string.format('PASS 2M map cache: %d chunks, %d packed segments (~%.2f MiB packed buffers), %d owner reads; %d bounded steps / %d work, %.2fms total, %.3fms peak; first visible chunk in step 1, first nonempty contour in step %d; 240 warm views read zero owners',cache.cols*cache.rows,segments,segments*8/1048576,before,steps,work,(os.clock()-start)*1000,peak*1000,firstContour))
-- Warm cache contains every owner; styles are projection filters, with no owner reads.
local owners={};for t=0,127*64-1 do owners[t]=if t%127<64 then 1 else 2 end
local small=Cache.new(127,64,function(t) return owners[t] end)
while small.pending>0 or small.job do Cache.step(small,16384,{0,0,127,64}) end
local style={effect='neon'}
local function render(styles)
 local field=Field.prepare(127,64,styles)
 for _,chunk in small.chunks do Field.project(chunk,1,chunk.ox,chunk.oy,1,1,5,field) end
 return field
end
assert(#render({[1]=style}).pixels>0 and #render({[2]=style}).pixels>0)
assert(#render({}).pixels==0,'removing a style clears all old halos')
local changes={}
for t,owner in owners do if owner==1 then owners[t]=2;table.insert(changes,t*1024+2) end end
Cache.invalidate(small,changes)
while small.pending>0 or small.job do Cache.step(small,16384,{0,0,127,64}) end
assert(#render({[1]=style}).pixels==0,'captured/dead owner has no stale contours')
print('PASS chunk delta halos, deduplication, style addition/removal, dead owner cleanup')

-- A capture that lands between sampling frames invalidates the in-progress chunk.
local captured=false
local streaming=Cache.new(64,64,function(t) return if captured and t==0 then 2 else 1 end)
local visible={0,0,63,63}
local sampled=68 -- first halo row, then the left halo and tile (0, 0)
Cache.step(streaming,sampled,visible)
captured=true
Cache.invalidate(streaming,{2}) -- tile 0 packed with new owner 2
local finish=66*66-sampled+64*64+4 -- remaining sample/scan work and the old outline's four edges
Cache.step(streaming,finish,visible)
assert(streaming.pending==1 and not streaming.chunks[0] and #streaming.changed==0,
 'an invalidated job cannot publish a stale outline')
Cache.step(streaming,16384,visible)
local has_capture=false
local current=streaming.chunks[0]
for i=0,current.count-1 do
 if buffer.readu32(current.packed,i*8)//(64*64*4)==2 then has_capture=true;break end
end
assert(has_capture and streaming.pending==0 and #streaming.changed==1,'the next complete scan publishes the capture')
print('PASS an in-flight capture never publishes a stale border')

-- Compare incremental i32 row copies with individual owner reads, including partial outer chunks.
local bw,bh=131,67
local source=buffer.create(bw*bh*4)
local function ownerAt(tile) return buffer.readi32(source,tile*4) end
for tile=0,bw*bh-1 do buffer.writei32(source,tile*4,(tile%bw//9+tile//bw//11)%4) end
local bulk,callback=Cache.new(bw,bh,source),Cache.new(bw,bh,ownerAt)
local whole={0,0,bw,bh}
local function compareOwners()
 for _,cache in {bulk,callback} do
  while cache.pending>0 or cache.job do assert(Cache.step(cache,257,whole)<=257) end
 end
 assert(bulk.reads==callback.reads)
 for id,chunk in bulk.chunks do
  local expected=callback.chunks[id]
  assert(buffer.tostring(chunk.packed)==buffer.tostring(expected.packed),'row copies preserve the contour and its halo')
 end
end
compareOwners()
local tile=64*bw+64
for _,cache in {bulk,callback} do
 Cache.invalidate(cache,{tile*1024+7})
 Cache.step(cache,257,whole)
end
buffer.writei32(source,tile*4,8)
for _,cache in {bulk,callback} do Cache.invalidate(cache,{tile*1024+8}) end
compareOwners()
print('PASS chunked i32 owner reads match callback contours, even after an in-flight capture')

local watchGrid=buffer.create(64*4)
buffer.writei32(watchGrid,0,1)
buffer.writei32(watchGrid,4,2)
local watched=Cache.new(64,1,watchGrid,{[1]=true})
local function warmWatch()
 while watched.pending>0 or watched.job do Cache.step(watched,16384,{0,0,63,1}) end
 return watched.chunks[0]
end
assert(warmWatch().owners[1] and not watched.chunks[0].owners[2])
buffer.writei32(watchGrid,4,3)
Cache.invalidate(watched,{1024+3},{2})
assert(watched.pending==0,'unwatched neighbors leave the styled outline alone')
Cache.watch(watched,{[3]=true})
assert(warmWatch().owners[3],'equipping a new owner scans its current territory')
buffer.writei32(watchGrid,4,2)
Cache.invalidate(watched,{1024+2},{3})
assert(not warmWatch().owners[3] and #watched.changed==1,'capture erases the last tracked edges')
Cache.watch(watched,{[1]=true,[3]=true})
assert(watched.pending==0,'a style change for a watched owner reuses the contour')

-- Even a pathological checkerboard is capped at four eight-byte records per tile.
local check=Cache.new(64,64,function(t) return 1+(t%64+t//64)%2 end)
local n=0
repeat local used=Cache.step(check,16384,{0,0,64,64});assert(used<=16384);n+=1 until not check.job and check.pending==0
assert(check.chunks[0].count==64*64*4 and buffer.len(check.chunks[0].packed)==64*64*32)
assert(not check.chunks[0].segments and n<=2,'packing is incremental and temporary edge tables are released')
print('PASS worst-case cache storage: <=32 bytes/tile = 61.04 MiB for 2M tiles, plus <=one temporary 64x64 job; packing shares the work budget')
