-- Owner-only local sandbox controls. Session obtains server permission before starting.
local L=require("./Look")
local Panel={};Panel.__index=Panel
function Panel.new(player,session,changed)
 local self=setmetatable({session=session,changed=changed},Panel)
 local gui,p=L.modal(player,"AtlasTestingTools","TESTING SANDBOX","Owner tools · no match rewards or ranked wins",Vector2.new(540,380))
 self.gui,self.panel=gui,p
 p.Size=UDim2.fromOffset(540,380)
 self.scale=L.make("UIScale",{Scale=1},p)
 L.button(p,"×",UDim2.new(1,-56,0,12),UDim2.fromOffset(36,36),function() self:close() end)
 self.stats=L.label(p,"Place your capital to receive test resources.",15,UDim2.fromOffset(24,94),UDim2.new(1,-48,0,65),L.GOLD,800);self.stats.TextWrapped=true
 local function action(title,key,y)
  L.button(p,title,UDim2.fromOffset(24,y),UDim2.new(1,-48,0,42),function()
   if session:testing_action(key) then self:close() else self.stats.Text="Place your capital first, then try again." end
  end,key=="refill")
 end
 action("REFILL · 1B GOLD + 5M TROOPS","refill",168)
 action("RESET MY WEAPON COOLDOWNS","cooldowns",222)
 action("FINISH MY CONSTRUCTION","build",276)
 self.hud=L.make("ScreenGui",{Name="AtlasTestingBadge",IgnoreGuiInset=true,ResetOnSpawn=false,DisplayOrder=61,Enabled=false},player:WaitForChild("PlayerGui"))
 L.button(self.hud,"TESTING · OPEN TOOLS",UDim2.fromOffset(16,74),UDim2.fromOffset(224,36),function() self:open() end,true)
 self.connections={session.mode_changed:Connect(function() self:refresh() end),session.state_ready:Connect(function() self:refresh() end)}
 self:refresh();return self
end
function Panel.refresh(self)
 local on=self.session.testing==true and self.session.mode==1
 self.hud.Enabled=on
 if not on then self:close() end
 local state=self.session.state;local me=state and state.owners[state.local_owner]
 if me then self.stats.Text=string.format("TEST RESOURCES\nGold: %.0f  ·  Troops: %.0f / %.0f",me.gold or 0,me.troops or 0,me.max_troops or 0) end
end
function Panel.open(self)
 if not self.session.testing then return end
 self:refresh();local camera=workspace.CurrentCamera;local vp=if camera then camera.ViewportSize else Vector2.new(1280,720)
 self.scale.Scale=math.min(1,(vp.X-24)/540,(vp.Y-24)/380)
 self.gui.Enabled=true;self.changed(true)
end
function Panel.close(self) if self.gui.Enabled then self.gui.Enabled=false;self.changed(false) end end
function Panel.destroy(self) self:close();for _,c in self.connections do c:Disconnect() end;self.gui:Destroy();self.hud:Destroy() end
return Panel
