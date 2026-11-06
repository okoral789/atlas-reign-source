--!nonstrict
-- Timed, snapshot-backed 2D support areas; never captures map clicks.
local SupportLayer={};SupportLayer.__index=SupportLayer
local GREEN=Color3.fromRGB(88,249,171)
function SupportLayer.new(parent,view)
 local root=Instance.new("Frame");root.Name="TacticalSupport";root.Size=UDim2.fromScale(1,1);root.BackgroundTransparency=1;root.ZIndex=17;root.Parent=parent
 return setmetatable({root=root,view=view,gui={}},SupportLayer)
end
function SupportLayer.bind(self,state) self:unbind();self.state=state end
function SupportLayer.unbind(self)
 self.state=nil;for _,g in self.gui do g.ring:Destroy() end;table.clear(self.gui)
end
function SupportLayer.destroy(self) self:unbind();self.root:Destroy() end
function SupportLayer.tick(self,_dt)
 local st=self.state;if not st then return end
 local tick=math.max(st.tick,st.render_tick or st.tick)
 for uid,g in self.gui do if not st.support_effects[uid] or st.support_effects[uid][7]<=tick then g.ring:Destroy();self.gui[uid]=nil end end
 for uid,e in st.support_effects do
  if e[2]~="fleet_repair" or e[7]<=tick then continue end
  local g=self.gui[uid]
  if not g then
   local ring=Instance.new("Frame");ring.Name="Support_"..e[2];ring.AnchorPoint=Vector2.new(.5,.5);ring.BorderSizePixel=0;ring.ZIndex=17;ring.Parent=self.root
   local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(.5,0);corner.Parent=ring
   local stroke=Instance.new("UIStroke");stroke.Thickness=2;stroke.Parent=ring
   local label=Instance.new("TextLabel");label.Name="Status";label.AnchorPoint=Vector2.new(.5,.5);label.Position=UDim2.fromScale(.5,.5);label.Size=UDim2.fromOffset(170,28);label.BackgroundColor3=Color3.fromRGB(8,28,45);label.BackgroundTransparency=.08;label.BorderSizePixel=0;label.TextSize=12;label.Font=Enum.Font.GothamBold;label.ZIndex=18;label.Parent=ring
   local lc=Instance.new("UICorner");lc.CornerRadius=UDim.new(0,8);lc.Parent=label
   g={ring=ring,stroke=stroke,label=label};self.gui[uid]=g
  end
  local cam=self.view.rig
  local x,y=cam:tile_to_screen(e[4]);local d=e[8]*2*cam.scale
  g.ring.Visible=cam:on_screen(x,y,d/2)
  g.ring.Position=UDim2.fromOffset(x,y);g.ring.Size=UDim2.fromOffset(d,d)
  g.ring.BackgroundColor3=GREEN;g.ring.BackgroundTransparency=.94+math.sin(tick*.5)*.02
  g.stroke.Color=GREEN;g.stroke.Transparency=.1
  g.label.TextColor3=GREEN
  g.label.Text="FLEET REPAIRED"
 end
end
return SupportLayer
