-- Stable AI identities. Numeric roster IDs are private to this catalog, never Roblox user IDs.
local BotRoster = {}
local regions = { "Amber", "Ash", "Cloud", "Frost", "Iron", "Jade", "Moss", "Silver" }
local forms = { "Reach", "March", "Harbor", "Guard", "Vale", "Crest", "Ridge", "Watch" }

BotRoster.COUNT = #regions * #forms

function BotRoster.profile(id: number)
	if type(id) ~= "number" or id % 1 ~= 0 or id < 1 or id > BotRoster.COUNT then
		return nil
	end
	local index = id - 1
	local tier = index % 10
	return {
		id = id,
		name = regions[index // #forms + 1] .. " " .. forms[index % #forms + 1],
		skill = if tier == 9 then 2 elseif tier >= 6 then 1 else 0,
	}
end

return BotRoster
