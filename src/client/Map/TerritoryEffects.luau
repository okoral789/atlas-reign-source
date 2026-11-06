local IS_ROBLOX = game ~= nil
local Data = if IS_ROBLOX then game:GetService("ReplicatedStorage").Airfront.Data else nil
local C = if IS_ROBLOX then require(Data.Cosmetics) else require("../../shared/Data/Cosmetics")
local Strokes = if IS_ROBLOX then require(Data.BorderStrokes) else require("../../shared/Data/BorderStrokes")
local LOD = if IS_ROBLOX then require(Data.BorderLOD) else require("../../shared/Data/BorderLOD")
local Cache = if IS_ROBLOX then require(Data.BorderContourCache) else require("../../shared/Data/BorderContourCache")
local FX={};FX.__index=FX
FX.MAX_W=512;FX.MAX_H=320
FX.SAMPLE_BUDGET=16384
FX.SAMPLE_TIME_S=.0015
FX.PAINT_INTERVAL=Strokes.PAINT_INTERVAL
FX.REUSE_PX=.95
FX.PAD=64 -- physical viewport pixels, outside the HUD's logical UIScale
function FX.new(parent,view)
 local root=Instance.new("ImageLabel");root.Name="TerritoryEffects";root.BackgroundTransparency=1;root.Size=UDim2.fromScale(1,1);root.ZIndex=5;root.Active=false;root.Visible=false;root.Parent=parent
 return setmetatable({root=root,view=view,paint_elapsed=1,conns={}},FX)
end
function FX.bind(self,state)
 self:unbind();self.state=state;self.style_dirty=true
 if state.tiles_changed then table.insert(self.conns,state.tiles_changed:Connect(function(changes,old)
  if self.cache then Cache.invalidate(self.cache,changes,old) end
 end)) end
 if state.cosmetics_changed then table.insert(self.conns,state.cosmetics_changed:Connect(function() self.style_dirty=true end)) end
 if state.snapshot_loaded then table.insert(self.conns,state.snapshot_loaded:Connect(function()
  self.cache=nil;self.field=nil;self.paint_scale=nil;self.last_scale=nil;self.dirty_chunks=nil;self.image_waiting=false;self.style_dirty=true;self.root.Visible=false
 end)) end
end
function FX.unbind(self)
 for _,conn in self.conns do conn:Disconnect() end;table.clear(self.conns)
 self.state=nil;self.cache=nil;self.field=nil;self.paint_scale=nil;self.last_scale=nil;self.dirty_chunks=nil;self.image_waiting=false;self.root.Visible=false
end
function FX.destroy(self) self:unbind();if self.image then self.image:Destroy() end;self.root:Destroy() end
function FX._styles(self)
 local previous=self.styles
 local styles={}
 for id,style in self.state.cosmetics or {} do local item=C.item(style.skin);if item and item.border then styles[id]=item end end
 local changed=previous==nil
 for id,item in styles do if not previous or previous[id]~=item then changed=true;break end end
 for id,item in previous or {} do if styles[id]~=item then changed=true;break end end
 if changed then
  self.styles=styles
  if self.cache then Cache.watch(self.cache,styles) end
 end
 self.style_dirty=false;self.redraw=self.redraw or changed
end
function FX._image(self,w,h)
 if self.w==w and self.h==h and self.image then return true end
 if os.clock()<(self.retry_at or 0) then return false end
 self.field=nil
 if self.image then self.image:Destroy();self.image=nil end
 local ok,img=pcall(function() return game:GetService("AssetService"):CreateEditableImage({Size=Vector2.new(w,h)}) end)
 if not ok or not img then self.root.Visible=false;self.retry_at=os.clock()+5;return false end
 self.w,self.h=w,h;self.pixels=buffer.create(w*h*4);self.image=img;self.root.ImageContent=Content.fromObject(img)
 return true
end
-- Keep the displayed bitmap anchored while reusing it or waiting for an upload slot.
function FX._follow(self,cam,vp)
 if not self.paint_scale then return 0,0,0,0 end
 local x,y=cam:map_to_screen(self.paint_mx,self.paint_my)
 local scale=cam.scale/self.paint_scale
 local w,h=self.paint_w*scale,self.paint_h*scale
 local pos,size=UDim2.fromOffset(x,y),UDim2.fromOffset(w,h)
 if self.root.Position~=pos then self.root.Position=pos end
 if self.root.Size~=size then self.root.Size=size end
 self.root.Visible=self.field~=nil and self.field.live>0 and x<vp.X and y<vp.Y and x+w>0 and y+h>0
 return x,y,w,h
end

-- Reproject neighboring edges too, so shared pixels keep their original draw order.
function FX._patch(self,cache,id)
 local chunk=cache.chunks[id]
 local field=self.field
 local sx,sy=self.paint_scale*self.w/self.paint_w,self.paint_scale*self.h/self.paint_h
 local left=math.max(0,math.floor((chunk.ox-self.paint_mx)*sx)-2)
 local top=math.max(0,math.floor((chunk.oy-self.paint_my)*sy)-2)
 local right=math.min(self.w-1,math.ceil((chunk.ox+chunk.w-self.paint_mx)*sx)+1)
 local bottom=math.min(self.h-1,math.ceil((chunk.oy+chunk.h-self.paint_my)*sy)+1)
 if left>right or top>bottom then return end
 local clip={left,top,right,bottom}
 Strokes.clear_rect(field,clip)
 local x0,y0,x1,y1=Cache.range(cache,self.paint_mx+(left-2)/sx,self.paint_my+(top-2)/sy,
    self.paint_mx+(right+3)/sx,self.paint_my+(bottom+3)/sy)
 local bounds=self.paint_bounds
 for y=math.max(y0,bounds[2]),math.min(y1,bounds[4]) do
  for x=math.max(x0,bounds[1]),math.min(x1,bounds[3]) do
   local neighbor=cache.chunks[y*cache.cols+x]
   if neighbor then Strokes.project(field,neighbor,self.paint_detail,clip) end
  end
 end
 self.patches=(self.patches or 0)+1
end

function FX.tick(self,dt)
 self.image_waiting=false;self.uploaded=false
 if not self.state then return end
 self.paint_elapsed+=dt;self.sample_work=0
 if self.style_dirty or not self.styles then self:_styles() end
 if not next(self.styles) then self.root.Visible=false;return end
 local cam=self.view.rig;local vp=cam:viewport_size()
 if vp.X<1 or vp.Y<1 then return end
 local dx,dy,drawW,drawH=self:_follow(cam,vp)
 local pad=math.clamp(math.floor(vp.X*.05),FX.PAD,192);local spanW,spanH=vp.X+pad*2,vp.Y+pad*2
 local mx0,my0=cam:screen_to_map(-pad,-pad);local mx1,my1=cam:screen_to_map(vp.X+pad,vp.Y+pad)
 local rect={mx0,my0,mx1,my1}
 if not self.cache then
  local st=self.state
  self.cache=Cache.new(st.W,st.H,if typeof(st.owner)=="buffer" then st.owner else function(tile) return st:tile_owner(tile) end,self.styles)
  self.samples=(self.samples or 0)+1
 end
 local cache=self.cache
 self.sample_work=Cache.step(cache,FX.SAMPLE_BUDGET,rect,os.clock()+FX.SAMPLE_TIME_S);self.reads=cache.reads
 local x0,y0,x1,y1=Cache.range(cache,mx0,my0,mx1,my1)
 local dirty=self.dirty_chunks or {};self.dirty_chunks=dirty
 local bounds=self.paint_scale and self.paint_bounds
 if bounds then
  for _,id in cache.changed do
   local x,y=id%cache.cols,id//cache.cols
   if x>=bounds[1] and x<=bounds[3] and y>=bounds[2] and y<=bounds[4] then dirty[id]=true end
  end
 end
 local stopped=self.last_scale==cam.scale
 self.last_scale=cam.scale
 local stretch=if self.paint_scale then math.abs(cam.scale/self.paint_scale-1) else 0
 local texel=if self.paint_scale then math.max(self.paint_w/self.w,self.paint_h/self.h) else 0
 -- Reuse while zooming if the stroke width changes by less than one physical pixel per texel.
 local geometry_changed=not self.paint_scale or self.paint_w~=spanW or self.paint_h~=spanH
  or stretch*texel>math.clamp(texel*.125,.5,FX.REUSE_PX) or (stopped and stretch>0)
 local uncovered=false
 if self.paint_scale then
  local left,top=cam:map_to_screen(0,0)
  local right,bottom=left+cache.w*cam.scale,top+cache.h*cam.scale
  left,top=math.max(0,left-texel),math.max(0,top-texel)
  right,bottom=math.min(vp.X,right+texel),math.min(vp.Y,bottom+texel)
  uncovered=right>left and bottom>top and (dx>left or dy>top or dx+drawW<right or dy+drawH<bottom)
 end
 local rasterize=geometry_changed or uncovered or self.redraw or not self.field
 local animate=self.paint_elapsed>=FX.PAINT_INTERVAL
 if not rasterize and not next(dirty) and (not animate or not self.root.Visible) then return end
 if self.view._map_image_written or (self.view._map_image_slot and self.view._map_image_slot~=self) then
  self.image_waiting=true;return
 end
 local ratio=math.min(1/3,FX.MAX_W/spanW,FX.MAX_H/spanH)
 local w,h=math.max(1,math.floor(spanW*ratio)),math.max(1,math.floor(spanH*ratio))
 if not self:_image(w,h) then return end
 if rasterize then
  self.field=Strokes.prepare(w,h,self.styles,self.field,self.pixels,os.clock())
  local px,py=spanW/w,spanH/h
  local detail=LOD.choose(cam.scale,px,py)
  local originX,originY=cam:map_to_screen(0,0)
  Strokes.transform(self.field,cam.scale/px,cam.scale/py,(originX+pad)/px,(originY+pad)/py,
    x0*Cache.SIZE,y0*Cache.SIZE,(x1+1)*Cache.SIZE,(y1+1)*Cache.SIZE)
  for cy=y0,y1 do for cx=x0,x1 do
   local chunk=cache.chunks[cy*cache.cols+cx]
   if chunk then
    Strokes.project(self.field,chunk,detail)
   end
  end end
  table.clear(dirty)
  self.paint_elapsed=0
  self.paint_bounds={x0,y0,x1,y1};self.paint_detail=detail
  self.rasters=(self.rasters or 0)+1
  self.paint_mx,self.paint_my=mx0,my0;self.paint_scale,self.paint_w,self.paint_h=cam.scale,spanW,spanH
  self.root.Position=UDim2.fromOffset(-pad,-pad);self.root.Size=UDim2.fromOffset(spanW,spanH)
 else
  for id in dirty do self:_patch(cache,id) end
  table.clear(dirty)
  if animate then Strokes.animate(self.field,os.clock());self.paint_elapsed=0 end
 end
 -- Animation can reuse the translated overscan; only a new raster changes its map anchor.
 self.root.Visible=self.field.live>0;self.redraw=false
 if self.root.Visible then
  self.image:WritePixelsBuffer(Vector2.zero,Vector2.new(w,h),self.pixels)
  self.uploaded=true
  if self.view._map_image_written~=nil then self.view._map_image_written=true end
 end
end
return FX
