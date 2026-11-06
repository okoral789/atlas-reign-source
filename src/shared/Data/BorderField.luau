-- Screen-space contour cache: sampling is incremental; zoom reprojects lines, never a thick image.
local Field = {}
Field.RADIUS = 3
Field.RADIUS_PX = 5

function Field.begin(w, h, owner, styles)
 return {w=w, h=h, owner=owner, styles=styles, ids=buffer.create((w+2)*(h+2)*4), cursor=0, scan=0, segments={},ends={},horizontal={},vertical={}}
end

-- The budget covers both owner reads and contour cells; camera motion cannot restart this job.
function Field.step(job, budget)
 local w,h=job.w,job.h
 local stride=w+2
 local count=stride*(h+2)
 local used=0
 local ids=job.ids
 local source=job.owner_buffer
 if source then
  -- The mirror keeps owners in row-major i32 order. Copy contiguous halo runs.
  local worldW,worldH=job.world_w,job.world_h
  while job.cursor<count and used<budget do
   local p=job.cursor
   local x,y=p%stride,p//stride
   local n=math.min(stride-x,budget-used)
   local mx,my=job.ox+x-1,job.oy+y-1
   if my>=0 and my<worldH then
    local first=math.max(0,-mx)
    local last=math.min(n,worldW-mx)
    if last>first then buffer.copy(ids,(p+first)*4,source,(my*worldW+mx+first)*4,(last-first)*4) end
   end
   job.cursor+=n;used+=n
  end
 else
  while job.cursor<count and used<budget do
   local p=job.cursor
   buffer.writei32(ids,p*4,job.owner(p%stride-1,p//stride-1) or 0)
   job.cursor+=1;used+=1
  end
 end
 if job.cursor<count then return false,used end
 local edgeStride=w*h*4
 local function edge(key,x,side)
  local lookup=if side<2 then job.vertical else job.horizontal
  local slot=if side<2 then x*2+side else side
  local prior=lookup[slot]
  local delta=if side<2 then w*4 else 4
  if prior and job.ends[prior]==key-delta then job.ends[prior]=key
  else
   local i=#job.segments+1;job.segments[i]=key;job.ends[i]=key;lookup[slot]=i
  end
 end
 local styles=job.styles
 local first=job.scan
 local stop=math.min(w*h,first+budget-used)
 local rowBytes=stride*4
 local x=first%w
 local offset=((first//w+1)*stride+x+1)*4
 for p=first,stop-1 do
  local id=buffer.readi32(ids,offset)
  if x==0 then table.clear(job.horizontal) end
  if (styles==nil and id>0) or (styles~=nil and styles[id]) then
   local key=id*edgeStride+p*4
   if buffer.readi32(ids,offset-4)~=id then edge(key,x,0) end
   if buffer.readi32(ids,offset+4)~=id then edge(key+1,x,1) end
   if buffer.readi32(ids,offset-rowBytes)~=id then edge(key+2,x,2) end
   if buffer.readi32(ids,offset+rowBytes)~=id then edge(key+3,x,3) end
  end
  x+=1;offset+=4
  if x==w then x=0;offset+=8 end
 end
 job.scan=stop;used+=stop-first
 if job.scan<w*h then return false,used end
 job.ids=nil;job.owner=nil;job.owner_buffer=nil;job.horizontal=nil;job.vertical=nil
 return true,used
end

function Field.prepare(w,h,styles,reuse)
 local field=reuse
 if not field or field.w~=w or field.h~=h then
  field={w=w,h=h,distance=buffer.create(w*h),source=buffer.create(w*h*2),phase=buffer.create(w*h),pixels={},active_styles={},palettes={},x_distances=table.create(w,0)}
 end
 field.styles=styles
 buffer.fill(field.distance,0,255);table.clear(field.pixels);table.clear(field.active_styles)
 return field
end

-- Append a map contour to a screen-space image; map resolution and image size are independent.
function Field.project(contour,scale,tx,ty,pixelX,pixelY,radius,field,scaleY)
 scaleY=scaleY or scale
 local w,h=field.w,field.h
 local cw,ch=contour.w,contour.h
 local rx,ry=radius/pixelX+.5,radius/pixelY+.5
 local xDistances=field.x_distances;local distances=field.distance;local limit=math.floor(radius*radius)+1
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
  if left>right or top>bottom then continue end
  for x=left,right do
   local dx=math.max(0,(if x<x0 then x0-x elseif x>x1 then x-x1 else 0)*pixelX-pixelX*.5)
   xDistances[x+1]=dx*dx
  end
  for y=top,bottom do
   -- Integrate the pixel footprint: a subpixel core must survive a high-DPI downsample.
   local dy=math.max(0,(if y<y0 then y0-y elseif y>y1 then y-y1 else 0)*pixelY-pixelY*.5)
   local dy2,row=dy*dy,y*w
   for x=left,right do
    local p=row+x;local old=buffer.readu8(distances,p)
    if old==0 then continue end
    local squared=xDistances[x+1]+dy2
    if squared<old and squared<limit then
     local d=math.floor(squared)
      field.active_styles[id]=true
      if old==255 then table.insert(field.pixels,p) end
      local phase=((math.floor((x-tx+.5)/scale)+(contour.ox or 0))*3+(math.floor((y-ty+.5)/scaleY)+(contour.oy or 0))*2)%128
      buffer.writeu8(distances,p,d);buffer.writeu16(field.source,p*2,id);buffer.writeu8(field.phase,p,phase)
    end
   end
  end
 end
 return field
end

-- Preview/test convenience; the live map appends visible map chunks to one bounded image.
function Field.raster(contour,scale,tx,ty,pixelX,pixelY,radius,reuse,scaleY)
 return Field.project(contour,scale,tx,ty,pixelX,pixelY,radius,Field.prepare(contour.w,contour.h,contour.styles,reuse),scaleY)
end

-- Synchronous convenience for tests; the live layer uses begin/step with a per-frame budget.
function Field.build(w,h,owner,styles)
 local job=Field.begin(w,h,owner,styles)
 while not Field.step(job,8192) do end
 return Field.raster(job,1,0,0,1,1,Field.RADIUS)
end

local glow={}
for d=0,Field.RADIUS_PX^2 do glow[d]=math.exp(-d*.38) end
local function color(r,g,b,a)
 return math.floor(r+(255-r)*a)+math.floor(g+(255-g)*a)*256+math.floor(b+(255-b)*a)*65536
end
function Field.update_palettes(field,t,active)
 local palettes=field.palettes
 field.style_palettes=field.style_palettes or {};field.palette_seen=field.palette_seen or {}
 local stylePalettes,seen=field.style_palettes,field.palette_seen;table.clear(seen)
 -- Trigonometry and color extraction happen per style/phase, not per halo pixel.
 for id in active do
  local style=field.styles[id]
  local entries=stylePalettes[style] or {};stylePalettes[style]=entries;palettes[id]=entries
  if seen[style] then continue end
  seen[style]=true
  local rgb=style.fleet_tint or 0x72FFF0
  local r,g,b=bit32.extract(rgb,16,8),bit32.extract(rgb,8,8),bit32.extract(rgb,0,8)
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
end
function Field.render(field,t,out)
 out=out or buffer.create(field.w*field.h*4);buffer.fill(out,0,0)
 Field.update_palettes(field,t,field.active_styles)
 local palettes=field.palettes
 for _,p in field.pixels do
  local c=palettes[buffer.readu16(field.source,p*2)][buffer.readu8(field.phase,p)]
  local d=buffer.readu8(field.distance,p);local core=d==0
  local alpha=math.clamp(math.floor(glow[d]*(if core then c[4] else c[3])*255),0,255)
  buffer.writeu32(out,p*4,(if core then c[2] else c[1])+alpha*16777216)
 end
 return out
end
return Field
