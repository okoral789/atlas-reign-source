require("./prelude")
local Release = require("../src/shared/Data/ReleaseConfig")
local Access = require("../src/server/OwnerAccess")
local Test = require("../src/shared/Data/PrivateTest")
local Gate = require("../src/server/TestingAccess")
local Prompt = require("../src/client/UI/PurchasePrompt")
local fs = require("@lune/fs")
local owner = {UserId=Test.OWNER}
assert(Release.CHANNEL == "live" and Access.allowed(7, owner.UserId, false), "This release admits ordinary accounts")
assert(Release.can_purchase() and Release.store_name("inventory") == "inventory_live_v1")
Release.CHANNEL = "private"
assert(Release.store_name("inventory") == "inventory", "Preserve existing private progress")
assert(Release.store_name("inventory",true) == "inventory_studio")
assert(Access.allowed(owner.UserId,owner.UserId,false) and not Access.allowed(7,owner.UserId,false))
assert(Gate.new(Test.OWNER,Test.UNIVERSE):request(owner,true).ok)
assert(not Release.can_purchase())
local ok,err = pcall(Prompt.product,123)
assert(not ok and string.find(tostring(err),"disabled in the test sandbox",1,true))
ok,err = pcall(Prompt.subscription,"fake")
assert(not ok and string.find(tostring(err),"disabled in the test sandbox",1,true))
Release.CHANNEL = "beta"
Release.TESTERS[7] = true
assert(Release.store_name("inventory") == "inventory_live_v1")
assert(Release.can_purchase() and Access.allowed(7,owner.UserId,false))
assert(not Access.allowed(8,owner.UserId,false))
assert(not Test.allowed(Test.OWNER,Test.OWNER,Test.UNIVERSE))
assert(not Gate.new(Test.OWNER,Test.UNIVERSE):request(owner,true).ok)
Release.CHANNEL = "live"
assert(Access.allowed(8,owner.UserId,false) and Release.can_purchase())
assert(not Access.allowed(0,0,false) and Access.allowed(-1,0,true))
assert(Release.store_name("inventory") == "inventory_live_v1", "Beta progress carries into release")
assert(not Test.allowed(Test.OWNER,Test.OWNER,Test.UNIVERSE))
Release.CHANNEL = "typo"
assert(not Access.allowed(owner.UserId,owner.UserId,false) and not Release.can_purchase())
assert(not pcall(Release.store_name,"inventory"))
Release.CHANNEL = "private"
table.clear(Release.TESTERS)
for _,name in fs.readDir("src/client/UI") do
	if name ~= "PurchasePrompt.luau" and name:sub(-5)==".luau" then
		local source = fs.readFile("src/client/UI/"..name)
		assert(not source:find(":PromptProductPurchase%("), name.." bypasses sandbox purchase guard")
		assert(not source:find(":PromptSubscriptionPurchase%("), name.." bypasses sandbox purchase guard")
	end
end
print("PASS release channels: isolated stores, owner sandbox, explicit beta testers, no production test grants, guarded Robux prompts")
