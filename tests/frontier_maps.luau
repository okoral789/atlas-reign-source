--!nocheck
require("./prelude")
local MapList = require("../src/shared/Data/MapList")
local WorldMap = require("../src/shared/Core/WorldMap")
for _, id in { "twin_straits", "iron_archipelago" } do
	local row = assert(MapList.get(id))
	local map = WorldMap.get(id)
	assert(map.ok and map.W == 960 and map.H == 640 and map.land_count == row.land_tiles)
	assert(map.coast_count > 1000 and map.water_body_count >= 1)
	assert(#map.nations == 24)
	local used = {}
	for _, nation in map.nations do
		assert(map:is_contestable(nation.tile), "country spawns on land")
		assert(not used[nation.tile], "unique spawn")
		used[nation.tile] = true
	end
	for i = 0, map.N-1 do
		assert(buffer.readu8(map.tile_bytes,i) == buffer.readu8(map.tile_bytes,map.N-1-i), "rotational terrain symmetry")
	end
	local small = WorldMap.get(id .. "@50")
	assert(small.W == 480 and small.H == 320 and small.land_count > 60000)
	print("PASS map", id, map.land_count, "land tiles; 24 valid spawns; symmetric; scaled variant")
end
