--!nonstrict
-- Atlas Reign's global competition ladder, 2026-10-31.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local L=require("./Look")
local Cosmetics=require(RS.Airfront.Data.Cosmetics)
local Art=require(RS.Airfront.Assets.Design)
local Preview=require(RS.Airfront.Data.PrivateTest)
local Board={};Board.__index=Board
function Board.career(wins)
 wins=math.max(0,math.floor(tonumber(wins) or 0))
 local tiers={{0,"RECRUIT"},{1,"SCOUT"},{10,"CAPTAIN"},{50,"CONQUEROR"},{200,"LEGEND"}}
 for i=#tiers,1,-1 do
  if wins>=tiers[i][1] then
   local nextTier=tiers[i+1]
   return tiers[i][2],if nextTier then nextTier[1]-wins else 0,if nextTier then nextTier[2] else "LEGEND",if nextTier then (wins-tiers[i][1])/(nextTier[1]-tiers[i][1]) else 1
  end
 end
end
local function place(data)
 if data==nil or data.ok~=true then return "Rank unavailable" end
 if (data.wins or 0)==0 then return "UNRANKED" end
 if data.rank==nil then return "Rank updating" end
 return "#"..tostring(data.rank)..(if data.exact==false then "+" else "")
end
-- Both screens share the server's requester budget; retry a quick navigation collision once.
function Board.fetch(remote,action,target,pause)
 local data=remote:InvokeServer(action,target)
 if type(data)=="table" and data.ok==false and data.message=="Please wait a moment." then
  (pause or task.wait)(1.05)
  data=remote:InvokeServer(action,target)
 end
 return data
end
function Board.new(player,changed,profile)
 local self=setmetatable({player=player,changed=changed,profile=profile,is_open=false,request=0,view="ranking"},Board)
 local gui,p=L.modal(player,"AtlasLadder","WORLD LADDER","Earn your place among the best.",Vector2.new(930,760))
 self.gui,self.panel=gui,p
 p:FindFirstChildWhichIsA("UIStroke").Color=Color3.fromRGB(201,165,255)
 p:FindFirstChildWhichIsA("UIGradient").Color=ColorSequence.new(Color3.fromRGB(111,75,163),Color3.fromRGB(130,168,190))
 L.button(p,"×",UDim2.new(1,-60,0,18),UDim2.fromOffset(36,36),function() self:close() end)
 self.demo_button=L.button(p,"DEMO",UDim2.new(1,-158,0,18),UDim2.fromOffset(86,36),function()
  if self.view=="demo" then self:close();self:open(true) else self.request+=1;self:show_demo() end
 end)
 self.demo_button.Visible=Preview.allowed(player.UserId,game.CreatorId,game.GameId)
 self.banner=L.card(p,"CompetitionHeader",UDim2.fromOffset(24,86),UDim2.new(1,-48,0,78))
 L.badge(self.banner,"ladder",UDim2.fromOffset(10,2),UDim2.fromOffset(68,72))
 L.label(self.banner,"THE WORLD IS WATCHING",19,UDim2.fromOffset(88,7),UDim2.new(1,-100,0,28),L.GOLD,900)
 self.status=L.label(self.banner,"Server-confirmed multiplayer victories",12,UDim2.fromOffset(88,37),UDim2.new(1,-100,0,26),L.INK)
 local mine=L.card(p,"YourRank",UDim2.new(0,24,1,-150),UDim2.new(1,-48,0,86))
 L.make("ImageLabel",{BackgroundTransparency=1,Image=Cosmetics.face_image(player.UserId),Position=UDim2.fromOffset(12,8),Size=UDim2.fromOffset(44,44)},mine)
 self.mine=L.label(mine,player.DisplayName.."  /  UNRANKED",18,UDim2.fromOffset(70,5),UDim2.new(1,-82,0,26),L.ACCENT,800)
 self.mine_wins=L.label(mine,"0 MULTIPLAYER WINS",12,UDim2.fromOffset(70,32),UDim2.new(1,-82,0,20),L.MUTED)
 self.career_text=L.label(mine,"",10,UDim2.fromOffset(70,55),UDim2.new(1,-82,0,20),L.GOLD,800)
 local track=L.make("Frame",{Name="CareerProgress",BackgroundColor3=L.BG,BorderSizePixel=0,Position=UDim2.new(0,70,1,-8),Size=UDim2.new(1,-82,0,3)},mine);L.round(track,2)
 self.career_bar=L.make("Frame",{BackgroundColor3=L.GOLD,BorderSizePixel=0,Size=UDim2.fromScale(0,1)},track);L.round(self.career_bar,2)
 self.columns=L.label(p,"RANK          COMMANDER",11,UDim2.fromOffset(30,177),UDim2.new(1,-120,0,20),L.MUTED,800)
 self.wins_column=L.label(p,"WINS",11,UDim2.new(1,-87,0,177),UDim2.fromOffset(60,20),L.GOLD,800)
 self.list=L.make("ScrollingFrame",{Name="Rows",BackgroundTransparency=1,BorderSizePixel=0,Position=UDim2.fromOffset(24,204),Size=UDim2.new(1,-48,1,-364),CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=3,ScrollBarImageColor3=L.ACCENT},p)
 L.make("UIListLayout",{Padding=UDim.new(0,4),SortOrder=Enum.SortOrder.LayoutOrder},self.list)
 self.switch=L.button(p,"PLAYERS IN SERVER",UDim2.new(0,24,1,-52),UDim2.new(.5,-30,0,36),function() if self.view~="players" then self:show_players() else self:close();self:open(true) end end)
 L.button(p,"MY PROFILE",UDim2.new(.5,6,1,-52),UDim2.new(.5,-30,0,36),function() self:close();profile(nil,nil,nil) end,true)
 self.mine_card=mine
 p:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
  local short=p.AbsoluteSize.Y<440
  mine.Visible=not short;self.banner.Visible=not short
  self.columns.Position=UDim2.fromOffset(30,if short then 86 else 177)
  self.wins_column.Position=UDim2.new(1,-87,0,if short then 86 else 177)
  self.list.Position=UDim2.fromOffset(24,if short then 112 else 204)
  self.list.Size=UDim2.new(1,-48,1,if short then -172 else -364)
 end)
 UIS.InputBegan:Connect(function(input,used) if self.is_open and not used and input.KeyCode==Enum.KeyCode.X and UIS:GetFocusedTextBox()==nil then self:close() end end)
 return self
end
function Board.clear(self)
 for _,child in self.list:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
 self.podium=nil
end
function Board.add_row(self,i,row,ranked)
 local function inspect()
  if row.demo then self.status.Text="Example entry only. Live profiles are available in LIVE LADDER.";return end
  self:close();self.profile(row.user_id,row.name,row.wins)
 end
 local place=row.rank or i
 if ranked and i<=3 then
  if not self.podium then self.podium=L.make("Frame",{Name="TopThree",BackgroundTransparency=1,Size=UDim2.new(1,-5,0,184),LayoutOrder=0},self.list) end
  local color=({L.GOLD,Color3.fromRGB(184,218,237),Color3.fromRGB(237,160,106)})[i]
  local b=L.button(self.podium,"",UDim2.new((i-1)/3,4,0,if i==1 then 0 else 12),UDim2.new(1/3,-8,0,if i==1 then 178 else 166),inspect)
  b.BackgroundColor3=Color3.new(1,1,1);b:FindFirstChildWhichIsA("UIGradient").Color=ColorSequence.new(color:Lerp(Color3.fromRGB(69,35,111),.68),Color3.fromRGB(14,29,48))
  b.Name="Podium"..i;b:FindFirstChildWhichIsA("UIStroke").Color=color
  local ribbon=L.label(b,"#"..place.." WORLD",13,UDim2.fromOffset(6,4),UDim2.new(1,-12,0,26),color,900);ribbon.TextXAlignment=Enum.TextXAlignment.Center
  if row.demo then
   local avatar=L.label(b,row.name:sub(1,1),30,UDim2.new(.5,-24,0,36),UDim2.fromOffset(48,48),color,900);avatar.BackgroundColor3=L.BG;avatar.BackgroundTransparency=0;avatar.TextXAlignment=Enum.TextXAlignment.Center;L.round(avatar,24)
  else L.make("ImageLabel",{Name="Avatar",BackgroundTransparency=1,Image=Cosmetics.face_image(row.user_id),Position=UDim2.new(.5,-24,0,36),Size=UDim2.fromOffset(48,48)},b) end
  local name=L.label(b,tostring(row.name or "Commander"),16,UDim2.fromOffset(8,91),UDim2.new(1,-16,0,25),L.INK,800);name.TextXAlignment=Enum.TextXAlignment.Center
  local wins=L.label(b,tostring(row.wins or 0).." WINS",18,UDim2.fromOffset(8,119),UDim2.new(1,-16,0,28),color,900);wins.TextXAlignment=Enum.TextXAlignment.Center
  if i==1 then L.badge(b,"ladder",UDim2.new(1,-49,0,25),UDim2.fromOffset(45,55)) end
  local tier=Board.career(row.wins)
  local ribbon=L.label(b,tier,9,UDim2.new(0,8,1,-20),UDim2.new(1,-16,0,16),color,900);ribbon.TextXAlignment=Enum.TextXAlignment.Center
  return
 end
 local b=L.button(self.list,"",UDim2.new(),UDim2.new(1,-5,0,54),inspect)
 b.BackgroundColor3=Color3.new(1,1,1);b:FindFirstChildWhichIsA("UIGradient").Color=ColorSequence.new(Color3.fromRGB(57,37,94),Color3.fromRGB(10,28,47))
 if row.user_id==self.player.UserId then b:FindFirstChildWhichIsA("UIStroke").Color=L.GOLD end
 b.LayoutOrder=i;b.Name="RankRow"..i
 local rank=if ranked then "#"..tostring(row.rank or i) else "•"
 L.label(b,rank,16,UDim2.fromOffset(12,0),UDim2.fromOffset(55,54),L.MUTED,800)
 if row.demo then
  local avatar=L.label(b,row.name:sub(1,1),18,UDim2.fromOffset(70,9),UDim2.fromOffset(36,36),L.ACCENT,800);avatar.TextXAlignment=Enum.TextXAlignment.Center;avatar.BackgroundTransparency=0;avatar.BackgroundColor3=L.BG;L.round(avatar,8)
 else L.make("ImageLabel",{BackgroundTransparency=1,Image=Cosmetics.face_image(row.user_id),Position=UDim2.fromOffset(70,9),Size=UDim2.fromOffset(36,36)},b) end
 L.label(b,tostring(row.name or "Commander"),15,UDim2.fromOffset(115,0),UDim2.new(1,-196,1,0),L.INK,700)
 local w=L.label(b,tostring(row.wins or 0),17,UDim2.new(1,-76,0,0),UDim2.fromOffset(64,54),L.GOLD,800);w.TextXAlignment=Enum.TextXAlignment.Right
end
function Board.update_career(self,wins)
 local tier,left,nextTier,progress=Board.career(wins)
 self.career_text.Text=tier..(if left>0 then " · "..left.." WINS TO "..nextTier else " · TOP WIN MILESTONE")
 self.career_bar.Size=UDim2.fromScale(progress,1)
end
function Board.show_players(self)
 self.request+=1;self.view="players";self.switch.Text="WORLD LADDER";self:clear()
 local players=Players:GetPlayers();table.sort(players,function(a,b) return a.Name:lower()<b.Name:lower() end)
 self.status.Text=tostring(#players).." commanders connected · select one to view or report"
 for i,p in players do
  local f=p:FindFirstChild("leaderstats");local w=f and f:FindFirstChild("Wins")
  self:add_row(i,{user_id=p.UserId,name=p.DisplayName,wins=w and w.Value or 0},false)
 end
end
function Board.show_demo(self)
 self.view="demo";self:clear();self.demo_button.Text="LIVE"
 local wins=self.player:GetAttribute("AtlasWins") or 0
 local rank=self.player:GetAttribute("AtlasWorldRank")
 self.mine.Text=self.player.DisplayName.."  /  "..place({ok=true,wins=wins,rank=rank,exact=self.player:GetAttribute("AtlasRankExact")})
 self.mine_wins.Text=tostring(wins).." MULTIPLAYER WINS · Your real score"
 self:update_career(wins)
 self.status.Text="DEMO DATA  ·  Switch to LIVE to see real multiplayer standings."
 for i,row in Preview.LADDER do self:add_row(i,{name=row.name,wins=row.wins,rank=i,demo=true},true) end
end
function Board.open(self,live_only)
 if self.is_open then return end
 self.is_open=true;self.gui.Enabled=true;self.changed(true);self.view="ranking";self.switch.Text="PLAYERS IN SERVER"
 self.request+=1;local token=self.request;self:clear();self.status.Text="Loading the world ladder…"
 self.demo_button.Text="DEMO"
 if not live_only and self.demo_button.Visible then self:show_demo();return end
 task.spawn(function()
  local net=RS:WaitForChild("AirfrontNet",8);local remote=net and net:WaitForChild("WinsRanking",4)
  local ok,data=pcall(function() return Board.fetch(remote) end)
  if not self.is_open or token~=self.request then return end
  if not ok or type(data)~="table" or not data.ok then self.status.Text="Ladder unavailable. Reopen to retry.";return end
  local me=data.me or {};self.mine.Text="YOUR PLACE  "..place(me)
  self.mine_wins.Text=tostring(me.wins or 0).." MULTIPLAYER WINS  ·  Global competition rank"
  self:update_career(me.wins or 0)
  self.status.Text=if data.studio then "Isolated Studio session" else "All-time multiplayer wins · equal wins share a rank"
  local rows=data.rows or {}
  for i,row in rows do self:add_row(i,row,true) end
  if #rows==0 then
   local empty=L.label(self.list,"The first chapter is yours.\nWin a multiplayer match to claim a place here.",18,UDim2.new(),UDim2.new(1,-10,0,110),L.MUTED)
   empty.TextWrapped=true;empty.TextXAlignment=Enum.TextXAlignment.Center
  end
 end)
end
function Board.close(self) if self.is_open then self.is_open=false;self.gui.Enabled=false;self.request+=1;self.changed(false) end end
function Board.toggle(self) if self.is_open then self:close() else self:open() end end
Board.place=place
return Board
