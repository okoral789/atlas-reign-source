--!nonstrict
-- Read-only match profile; appearance is equipped through the Style Shop.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local L=require("./Look")
local Style=require(RS.Airfront.Data.ProfileStyle)
local Cosmetics=require(RS.Airfront.Data.Cosmetics)
local Preview=require("./PatternPreview")
local Locker=require("./Locker")
local Board=require("./WinsBoard")
local Profile={};Profile.__index=Profile
local function rgb(v) return Color3.fromRGB(v//65536%256,v//256%256,v%256) end
function Profile.fit_scale(vp,scale)
 return math.min(math.clamp(scale,1,1.4),(vp.X-28)/820,(vp.Y-28)/520)
end
function Profile.new(player,session,changed,_open_locker,open_style)
 local self=setmetatable({player=player,session=session,changed=changed,request=0},Profile)
 local gui,p=L.modal(player,"AtlasCommander","PLAYER PROFILE","Your identity on the world map.",Vector2.new(820,520))
 self.gui,self.panel=gui,p;p.Size=UDim2.fromOffset(820,520)
 self.scale=L.make("UIScale",{Scale=1},p)
 L.button(p,"×",UDim2.new(1,-56,0,12),UDim2.fromOffset(36,36),function() self:close() end)
 self.body=L.make("Frame",{Name="ProfileBody",Position=UDim2.fromOffset(24,88),Size=UDim2.new(1,-48,1,-112),BackgroundTransparency=1},p)
 local b=self.body
 self.avatar=L.make("ImageLabel",{Name="Avatar",BackgroundColor3=L.RAISED,BorderSizePixel=0,Position=UDim2.fromOffset(2,2),Size=UDim2.fromOffset(108,108)},b);L.round(self.avatar,18)
 self.avatar_ring=L.outline(self.avatar,L.ACCENT,2)
 self.name=L.label(b,"Commander",30,UDim2.fromOffset(130,10),UDim2.new(.66,-142,0,40),L.INK,900)
 self.subtitle=L.label(b,"",14,UDim2.fromOffset(130,56),UDim2.new(.66,-142,0,28),L.ACCENT,700)
 local function stat(name,x,title,icon)
  local tile=L.card(b,name,UDim2.new(x,0,0,128),UDim2.new(.32,-8,0,76),L.BG)
  L.icon(tile,icon,UDim2.fromOffset(10,24),UDim2.fromOffset(28,28),L.GOLD)
  local heading=L.label(tile,title,10,UDim2.fromOffset(48,10),UDim2.new(1,-56,0,18),L.MUTED,800)
  return L.label(tile,"—",23,UDim2.fromOffset(48,31),UDim2.new(1,-56,0,32),L.INK,900),heading
 end
 self.stats,self.statsHeading=stat("Wins",0,"MULTIPLAYER WINS","leaderboard")
 self.rank,self.rankHeading=stat("GlobalRank",.33,"WORLD RANK","crown");self.rank.TextSize=18
 self.identity={}
 for i,title in {"FLAG","NATION COLOR","BORDER / STYLE"} do
  local card=L.card(b,title,UDim2.new((i-1)*.22,0,0,220),UDim2.new(.22,-8,0,116))
  L.label(card,title,10,UDim2.fromOffset(10,7),UDim2.new(1,-20,0,20),L.MUTED,800)
  self.identity[i]={root=card,name=L.label(card,"",11,UDim2.new(0,10,1,-27),UDim2.new(1,-20,0,20),L.INK,700)}
 end
 self.flag=L.make("ImageLabel",{BackgroundTransparency=1,Position=UDim2.fromOffset(10,31),Size=UDim2.new(1,-20,0,50),ScaleType=Enum.ScaleType.Fit},self.identity[1].root)
 self.color=L.make("Frame",{Name="ColorSwatch",BackgroundColor3=L.ACCENT,BorderSizePixel=0,Position=UDim2.fromOffset(10,31),Size=UDim2.new(1,-20,0,50)},self.identity[2].root);L.round(self.color,7)
 self.preview,self.tiles=Preview.country(b,UDim2.new(.67,0,0,0),UDim2.new(.33,0,0,336))
 local cap=L.label(self.preview,"COUNTRY PREVIEW",12,UDim2.fromOffset(12,10),UDim2.new(1,-24,0,24),L.INK,800);cap.ZIndex=self.preview.ZIndex+3
 self.shop=L.button(b,"CUSTOMIZE COUNTRY",UDim2.fromOffset(0,356),UDim2.new(1,0,0,42),function() self:close();open_style() end,true)
 self.report=L.button(b,"REPORT PLAYER",UDim2.fromOffset(0,356),UDim2.new(1,0,0,42),function()
  local id,name=self.target,self.name.Text;self:close();if self.on_report then self.on_report(id,name) end
 end)
 local camera=workspace.CurrentCamera
 if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(function() self:fit() end) end
 self:fit();return self
end
function Profile.fit(self)
 local camera=workspace.CurrentCamera
 local size=if camera then camera.ViewportSize else Vector2.new(1600,900)
 self.scale.Scale=Profile.fit_scale(size,require("./UITheme").scale)
end
function Profile.close(self)
 if self.gui.Enabled then self.gui.Enabled=false;self.request+=1;self.changed(false) end
end
function Profile.show_style(self,cosmetics,mine,player)
 local skin=cosmetics and Cosmetics.item(cosmetics.skin)
 local flag=cosmetics and Cosmetics.item(cosmetics.flag)
 local index=if mine then self.player:GetAttribute("AtlasCountryColor") or self.session:load_settings("frontier_country").color or 0 else player and player:GetAttribute("AtlasCountryColor") or 0
 local color=if Style.valid(index) and index>1 then rgb(Style.colors[index].rgb) else L.ACCENT
 if cosmetics and type(cosmetics.color)=="number" and cosmetics.color>=0 and cosmetics.color<=4294967295 then color=rgb(math.floor(cosmetics.color/256)) end
 if cosmetics and cosmetics.color then index=require(RS.Airfront.Data.CountryStyle).index(cosmetics.color) or index end
 local colorName=if Style.valid(index) and index>1 then Style.colors[index].name else "Match color"
 self.color.BackgroundColor3=color;self.avatar_ring.Color=color
 self.identity[1].name.Text=flag and flag.name or "No flag"
 self.identity[2].name.Text=colorName
 self.identity[3].name.Text=skin and skin.name or "Standard border"
 self.flag.Visible=flag~=nil
 if flag then Locker.show_item(self.flag,flag) end
 if self.pattern then self.pattern:Destroy() end
 local look={color=index,flag=cosmetics and cosmetics.flag,flag_fill=if cosmetics and type(cosmetics.flag_fill)=="boolean" then cosmetics.flag_fill else mine and self.player:GetAttribute("AtlasFlagFill")==true}
 self.pattern=Preview.new(self.identity[3].root,skin,color,UDim2.fromOffset(10,31),UDim2.new(1,-20,0,50),look)
 Preview.update(self.tiles,skin,color,look)
 local old=self.color:FindFirstChildWhichIsA("UIGradient");if old then old:Destroy() end
 if Style.valid(index) and Style.colors[index].gradient then
  self.color.BackgroundColor3=Color3.new(1,1,1);local stops={}
  for i,value in Style.colors[index].gradient do stops[i]=ColorSequenceKeypoint.new((i-1)/2,rgb(value)) end
  L.make("UIGradient",{Color=ColorSequence.new(stops),Rotation=35},self.color)
 end
end
function Profile.open(self,user_id,name,wins,cosmetics,bot)
 local player=if type(user_id)=="number" then Players:GetPlayerByUserId(user_id) else nil
 if cosmetics==nil and user_id and self.session.state then
  for _,entry in self.session.state.cosmetics or {} do if entry.user_id==user_id then cosmetics=entry;break end end
 end
 local mine=user_id==self.player.UserId
 local commander=bot and cosmetics and cosmetics.bot_id~=nil
 self.target=user_id;self.request+=1;local token=self.request
 self.name.Text=tostring(name or (player and player.DisplayName) or "AI nation")
 self.subtitle.Text=if commander then "AI COMMANDER" elseif bot or not user_id then "AI NATION" elseif player then "@"..player.Name else "ROBLOX PLAYER"
 self.avatar.Image=if type(user_id)=="number" and user_id>0 then Cosmetics.face_image(user_id) else require(RS.Airfront.Assets.Design).emblem
 self.stats.Text=if type(wins)=="number" then tostring(wins) else "…"
 self.rank.Text=if bot or not user_id then "—" else "…"
 self.statsHeading.Text=if commander then "BOT WINS" else "MULTIPLAYER WINS"
 self.rankHeading.Text=if commander then "BOT MATCHES" else "WORLD RANK"
 self.shop.Visible=mine
 self.report.Visible=not mine and not bot and type(user_id)=="number" and user_id>0
 self:show_style(cosmetics,mine,player)
 self:fit();self.gui.Enabled=true;self.changed(true)
 if commander then
  self.stats.Text=if cosmetics.bot_wins~=nil then tostring(cosmetics.bot_wins) else "—"
  self.rank.Text=if cosmetics.bot_matches~=nil then tostring(cosmetics.bot_matches) else "—"
  return
 end
 if bot or not user_id then self.stats.Text="—";return end
 task.spawn(function()
  local net=RS:WaitForChild("AirfrontNet",8);local remote=net and net:WaitForChild("WinsRanking",4)
  local ok,data=pcall(function() return Board.fetch(remote,"profile",user_id) end)
  if token~=self.request or not self.gui.Enabled then return end
  if not ok or type(data)~="table" or not data.ok then self.rank.Text="UNAVAILABLE";return end
  self.stats.Text=tostring(data.wins or 0);self.rank.Text=Board.place(data)
 end)
end
function Profile.open_self(self) self:open(self.player.UserId,self.player.DisplayName,nil,self.session.inventory.equipped,false) end
function Profile.open_owner(self,owner_id)
 local state=self.session.state;local owner=state and state:get_owner(owner_id)
 if not owner then return end
 local c=state.cosmetics and state.cosmetics[owner_id]
 self:open(c and c.user_id,owner.name,nil,c,c and c.bot==true)
end
return Profile
