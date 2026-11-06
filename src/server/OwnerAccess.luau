local Release = if typeof(game) == "Instance"
	then require(game:GetService("ReplicatedStorage").Airfront.Data.ReleaseConfig)
	else require("../shared/Data/ReleaseConfig")
local OwnerAccess = {}

function OwnerAccess.allowed(user_id: number, creator_id: number, studio: boolean): boolean
	return Release.allowed(user_id, creator_id, studio)
end

return OwnerAccess
