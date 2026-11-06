local Field=if game~=nil then require(script.Parent.BorderField) else require('./BorderField')
local LOD=if game~=nil then require(script.Parent.BorderLOD) else require('./BorderLOD')
local Cache={SIZE=64}
Cache.LOD_EDGES=768
local SCAN_SLICE=4096
local clock=os.clock
function Cache.new(w,h,owner,owners)
 local cols,rows=math.ceil(w/Cache.SIZE),math.ceil(h/Cache.SIZE)
 local watched=if owners then table.clone(owners) else nil
 local cache={w=w,h=h,cols=cols,rows=rows,owner=owner,watched=watched,chunks={},dirty={},pending=cols*rows,cursor=0,changed={},reads=0}
 for id=0,cols*rows-1 do cache.dirty[id]=true end
 return cache
end
local function dirty(cache,id)
 if not cache.dirty[id] then cache.dirty[id]=true;cache.pending+=1 end
end
function Cache.watch(cache,owners)
 local watched=cache.watched
 if not watched then return end
 local added=false
 for id in owners do
  if not watched[id] then watched[id]=true;added=true end
 end
 -- The retained chunks still have valid contours for previously watched owners.
 if added then for id=0,cache.cols*cache.rows-1 do dirty(cache,id) end end
end
function Cache.invalidate(cache,changes,old)
 local w,size=cache.w,Cache.SIZE
 local watched=cache.watched
 for i,packed in changes do
  -- An untracked-to-untracked transfer cannot change an edge of a watched owner.
  if watched and old and old[i]~=nil and not (watched[old[i]] or watched[packed%1024]) then continue end
  local t=packed//1024;local x,y=t%w,t//w
  local cx,cy=x//size,y//size;local id=cy*cache.cols+cx
  dirty(cache,id)
  -- A changed tile is also in its neighbour chunk's one-tile contour halo.
  if x%size==0 and cx>0 then dirty(cache,id-1) end
  if x%size==size-1 and cx+1<cache.cols then dirty(cache,id+1) end
  if y%size==0 and cy>0 then dirty(cache,id-cache.cols) end
  if y%size==size-1 and cy+1<cache.rows then dirty(cache,id+cache.cols) end
 end
end
function Cache.range(cache,x0,y0,x1,y1)
 local s=Cache.SIZE
 return math.max(0,math.floor(x0/s)),math.max(0,math.floor(y0/s)),math.min(cache.cols-1,math.floor(x1/s)),math.min(cache.rows-1,math.floor(y1/s))
end
local function pick(cache,rect)
 if cache.pending==0 then return nil end
 local x0,y0,x1,y1=Cache.range(cache,rect[1],rect[2],rect[3],rect[4])
 local mx,my=(x0+x1)/2,(y0+y1)/2
 local best,distance=nil,math.huge
 for y=y0,y1 do for x=x0,x1 do
  local id=y*cache.cols+x
  if cache.dirty[id] then
   local d=(x-mx)^2+(y-my)^2
   if d<distance then best,distance=id,d end
  end
 end end
 if best~=nil then return best end
 local count=cache.cols*cache.rows
 for _=1,count do
  local id=cache.cursor;cache.cursor=(id+1)%count
  if cache.dirty[id] then return id end
 end
 return nil
end
function Cache.step(cache,budget,rect,deadline)
 table.clear(cache.changed)
 local used,lod_edges=0,0
 while used<budget and (not deadline or used==0 or clock()<deadline) do
  local job=cache.job
  if not job then
   local id=pick(cache,rect)
   if id==nil then break end
   cache.dirty[id]=nil;cache.pending-=1
   local ox,oy=id%cache.cols*Cache.SIZE,id//cache.cols*Cache.SIZE
   local source=if typeof(cache.owner)=="buffer" then cache.owner else nil
   local sample=if source then nil else function(x,y)
    local mx,my=x+ox,y+oy
    return if mx<0 or my<0 or mx>=cache.w or my>=cache.h then 0 else cache.owner(my*cache.w+mx)
   end
   job=Field.begin(math.min(Cache.SIZE,cache.w-ox),math.min(Cache.SIZE,cache.h-oy),sample,cache.watched)
   job.owner_buffer,job.world_w,job.world_h=source,cache.w,cache.h
   job.id,job.ox,job.oy=id,ox,oy;cache.job=job
  end
  local before=job.cursor
  local slice=if deadline then math.min(SCAN_SLICE,budget-used) else budget-used
  local done,work=Field.step(job,slice)
  cache.reads+=job.cursor-before;used+=work
  if not done then continue end
  -- Fixed eight bytes per merged edge, rather than two growing Luau number tables.
  if not job.packed then job.count=#job.segments;job.packed=buffer.create(job.count*8);job.pack_cursor=0;job.owners={} end
  local stride=job.w*job.h*4
  while job.pack_cursor<job.count and used<budget do
   local p=job.pack_cursor;local i=p+1
   buffer.writeu32(job.packed,p*8,job.segments[i]);buffer.writeu32(job.packed,p*8+4,job.ends[i])
   job.owners[job.segments[i]//stride]=true
   job.pack_cursor+=1;used+=1
   if deadline and job.pack_cursor%256==0 and clock()>=deadline then break end
  end
  if job.pack_cursor<job.count then break end
  -- A capture during an incremental scan can invalidate its sampled owners.
  if not cache.dirty[job.id] then
   -- shortcut: dense chunks keep exact contours to cap simplification work and storage.
   if job.count>=8 and job.count<=Cache.LOD_EDGES then
    if lod_edges+job.count>Cache.LOD_EDGES or (deadline and clock()>=deadline) then break end
    LOD.build(job);lod_edges+=job.count
   end
   job.segments=nil;job.ends=nil
   local previous=cache.chunks[job.id]
   cache.chunks[job.id]=job
   if not cache.watched or job.count>0 or (previous and previous.count>0) then table.insert(cache.changed,job.id) end
  end
  cache.job=nil
 end
 cache.lod_edges=lod_edges
 return used
end
return Cache
