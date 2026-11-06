--!nonstrict
-- Atlas Reign, 2026-10-31. Moderation evidence stays server-side.
local RS=game:GetService("ReplicatedStorage")
local L=require("./Look")
local Reports={};Reports.__index=Reports
function Reports.new(player,changed)
 local self=setmetatable({player=player,changed=changed,request=0},Reports)
 local gui,p=L.modal(player,"AtlasReports","FAIR PLAY","Protect the match.",Vector2.new(700,540))
 self.gui,self.panel=gui,p
 L.button(p,"×",UDim2.new(1,-60,0,18),UDim2.fromOffset(36,36),function() self:close() end)
 self.note=L.label(p,"",14,UDim2.fromOffset(24,90),UDim2.new(1,-48,0,64),L.MUTED);self.note.TextWrapped=true
 self.body=L.make("ScrollingFrame",{BackgroundTransparency=1,BorderSizePixel=0,Position=UDim2.fromOffset(24,164),Size=UDim2.new(1,-48,1,-190),AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),ScrollBarThickness=3,ScrollBarImageColor3=L.GOLD},p)
 L.make("UIListLayout",{Padding=UDim.new(0,10),SortOrder=Enum.SortOrder.LayoutOrder},self.body)
 return self
end
function Reports.call(self,action,target,reason,callback)
 if self.busy then return end;self.busy=true
 self.request+=1;local token=self.request
 task.spawn(function()
  local net=RS:WaitForChild("AirfrontNet",8);local remote=net and net:WaitForChild("PlayerReports",4)
  local ok,data=pcall(function() return remote:InvokeServer(action,target,reason) end)
  self.busy=false
  if token~=self.request or not self.gui.Enabled then return end
  callback(if ok and type(data)=="table" then data else {ok=false,message="Service unavailable. Please retry."})
 end)
end
function Reports.open(self,target,name)
 self.gui.Enabled=true;self.changed(true);self.request+=1
 for _,c in self.body:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
 if target then
  self.note.Text="Report "..tostring(name or target).." in your current match. Suspected premade teaming is reviewed; a report alone never causes a ban."
  for i,row in {{"teaming","PREMADE TEAMING  ·  FREE FOR ALL"},{"exploiting","EXPLOITING / CHEATING"},{"harassment","HARASSMENT"}} do
   local b=L.button(self.body,row[2],UDim2.new(),UDim2.new(1,-5,0,52),function()
    self.note.Text="Saving report…"
    self:call("submit",target,row[1],function(data) self.note.Text=data.message or "Please retry." end)
   end);b.LayoutOrder=i
  end
 else
  self.note.Text="Owner review inbox · recent reports with match context. No automatic penalties."
  self:call("inbox",nil,nil,function(data)
   if not data.ok then self.note.Text="Inbox unavailable.";return end
   self.note.Text=tostring(#(data.rows or {})).." recent reports · select a pending report to mark reviewed"
   for i,row in data.rows or {} do
    local c=row.context or {}
    local b
    b=L.button(self.body,"",UDim2.new(),UDim2.new(1,-5,0,92),function()
     if row.status=="reviewed" then return end
     self:call("review",row.id,nil,function(result) if result.ok then row.status="reviewed";self.note.Text="Report marked reviewed. No automatic penalty was applied.";for _,d in b:GetChildren() do if d:IsA("TextLabel") then d.Text=string.gsub(d.Text,"pending","reviewed") end end else self.note.Text="Could not save review. Wait a moment and retry." end end)
    end);b.LayoutOrder=i
    L.label(b,string.upper(row.reason).."  /  "..row.status,12,UDim2.fromOffset(12,6),UDim2.new(1,-24,0,22),L.GOLD,800)
    L.label(b,tostring(c.reporter_name or row.reporter).." → "..tostring(c.target_name or row.target),15,UDim2.fromOffset(12,29),UDim2.new(1,-24,0,24))
    L.label(b,tostring(c.map).." · "..tostring(c.mode).." · tick "..tostring(c.tick).." · "..os.date("!%d %b %H:%M",row.created),12,UDim2.fromOffset(12,57),UDim2.new(1,-24,0,22),L.MUTED)
   end
  end)
 end
end
function Reports.close(self)
 if self.gui.Enabled then self.gui.Enabled=false;self.request+=1;self.changed(false) end
end
return Reports
