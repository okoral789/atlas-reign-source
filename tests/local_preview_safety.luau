local Products = require("../src/shared/Data/Products")
local Subscription = require("../src/shared/Data/Subscription")
local Purchases = require("../src/server/Purchases")

local count = 0
for _, product in Products do
	count += 1
	assert(product.id == 0 and product.staging == 0, "preview exposes a paid product")
end
assert(count > 10, "product catalogue was not loaded")
assert(Subscription.ID == "" and Subscription.STAGING == "" and Subscription.id() == "", "preview exposes a subscription")
assert(Purchases.kind_of(3715363250) == nil, "original product receipt was accepted")
print("PASS: paid products and subscriptions are disabled in the local preview")
