-- Change only for a reviewed release; private test progress must never enter the live economy.
local Release = { CHANNEL = "live", TESTERS = {} }

function Release.is_sandbox(): boolean
	return Release.CHANNEL == "private"
end

function Release.store_name(base: string, studio: boolean?): string
	if studio then return base .. "_studio" end
	if Release.is_sandbox() then return base end
	assert(Release.CHANNEL == "beta" or Release.CHANNEL == "live", "Unknown release channel")
	return base .. "_live_v1"
end

function Release.allowed(user: number, creator: number, studio: boolean): boolean
	if studio then return true end
	if creator <= 0 or user <= 0 then return false end
	if Release.CHANNEL == "live" then return true end
	if Release.CHANNEL == "private" then return user == creator end
	if Release.CHANNEL == "beta" then return user == creator or Release.TESTERS[user] == true end
	return false
end

function Release.can_purchase(): boolean
	return Release.CHANNEL == "beta" or Release.CHANNEL == "live"
end

return Release
