-- Server-only index. The lobby store supplies the access code at teleport time.
local LobbyRules = require("./LobbyRules")
local ResumeSeats = {}
ResumeSeats.__index = ResumeSeats
ResumeSeats.TTL_S = 45 * 60

function ResumeSeats.new(index, lobbies, now)
	return setmetatable({ index = index, lobbies = lobbies, now = now }, ResumeSeats)
end

function ResumeSeats.remember(self, uid, lobby, matchId, at)
	if lobby == nil or type(lobby.psid) ~= "string" or lobby.psid == "" or matchId == "" then
		return
	end
	self.index:UpdateAsync(uid, function(previous)
		if type(previous) == "table" and type(previous.at) == "number" and previous.at >= at then
			return nil
		end
		return { lobby = lobby.id, psid = lobby.psid, match = matchId, at = at }
	end, ResumeSeats.TTL_S)
end

function ResumeSeats.find(self, uid)
	local seat = self.index:GetAsync(uid)
	local now = self.now()
	if type(seat) ~= "table" or type(seat.lobby) ~= "string" or type(seat.match) ~= "string" or seat.match == ""
		or type(seat.at) ~= "number" or seat.at > now + 5 or seat.at <= now - ResumeSeats.TTL_S then
		return nil
	end
	local lobby = LobbyRules.decode(self.lobbies.get(seat.lobby))
	if lobby == nil or lobby.psid ~= seat.psid or not LobbyRules.watchable(lobby, now) then
		return nil
	end
	return lobby, seat.match, seat.at
end

function ResumeSeats.consume(self, uid, matchId, at)
	self.index:UpdateAsync(uid, function(previous)
		if type(previous) ~= "table" or previous.match ~= matchId or previous.at ~= at then
			return nil
		end
		return { at = math.max(at, self.now()) }
	end, 60)
end

return ResumeSeats
