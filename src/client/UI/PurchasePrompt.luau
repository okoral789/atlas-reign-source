local Release = if typeof(game) == "Instance"
	then require(game:GetService("ReplicatedStorage").Airfront.Data.ReleaseConfig)
	else require("../../shared/Data/ReleaseConfig")
local Prompt = {}
function Prompt.product(id)
	assert(Release.can_purchase(), "Robux purchases are disabled in the test sandbox.")
	game:GetService("MarketplaceService"):PromptProductPurchase(game:GetService("Players").LocalPlayer, id)
end
function Prompt.subscription(id)
	assert(Release.can_purchase(), "Subscriptions are disabled in the test sandbox.")
	game:GetService("MarketplaceService"):PromptSubscriptionPurchase(game:GetService("Players").LocalPlayer, id)
end
return Prompt
