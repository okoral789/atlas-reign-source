-- Owner-only preview data. Never contributes to real ranking or records fake purchases.
local Release = require("./ReleaseConfig")
local Test={UNIVERSE=10774039150,OWNER=8318659852}
Test.COSMETICS={"profile_color_2","profile_color_3","profile_color_4","profile_color_5","profile_color_6",
 "fleet_copper","fleet_crimson","fleet_obsidian","hex","diagonal","waves","stripes",
 "shop_lion_crest","shop_wolf_pack","shop_kraken","shop_phoenix"}
Test.LADDER={
 {name="Northmark",wins=312},{name="Meridian",wins=284},{name="IronHarbor",wins=251},
 {name="Solstice",wins=229},{name="Valoria",wins=214},{name="AzureUnion",wins=198},
 {name="Drakemoor",wins=184},{name="GoldenCoast",wins=176},{name="Westhaven",wins=162},
 {name="Redwood",wins=151},{name="Tidewatch",wins=145},{name="Highland",wins=132}}
function Test.allowed(user,creator,universe) return Release.is_sandbox() and user==Test.OWNER and creator==Test.OWNER and universe==Test.UNIVERSE end
return Test
