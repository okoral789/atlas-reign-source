--!strict
-- Frontier modifications, 2026-10-31; see NOTICE.md.
local ProfileStyle = {}
ProfileStyle.ROBUX = 29

ProfileStyle.colors = {
	{ name = "Gold", rgb = 0xE9B949 },
	{ name = "Blue", rgb = 0x53A9FF },
	{ name = "Emerald", rgb = 0x48D09A },
	{ name = "Rose", rgb = 0xF47FA8 },
	{ name = "Violet", rgb = 0xAD8CFF },
	{ name = "Orange", rgb = 0xFF9B54 },
	{ name = "Arctic Pearl", rgb = 0xE5FCFF, premium=true, gradient={0x74CEEE,0xD7F9FF,0x9DCBF4} },
	{ name = "Obsidian", rgb = 0x252A40, premium=true, gradient={0x253D64,0x526FA0,0x9FB6DF} },
	{ name = "Neon Magenta", rgb = 0xFF249F, premium=true, gradient={0xA72981,0xF744A5,0xFF95C6} },
	{ name = "Imperial Gold", rgb = 0xFFCC33, premium=true, gradient={0xCF9236,0xF8CF65,0xFFE8A6} },
	{ name = "Void Violet", rgb = 0x7C3CFF, premium=true, gradient={0x50369C,0x8860DD,0xBEA0F2} },
	{ name = "Solar Flare", rgb = 0xFF5015, premium=true, gradient={0xE54620,0xFF943D,0xFFDE87} },
	{ name = "Tropical Glass", rgb = 0x00E6D7, premium=true, gradient={0x087C9D,0x20E5C8,0xB2FFE5} },
	{ name = "Royal Amethyst", rgb = 0x4A00E0, premium=true, gradient={0x3F2496,0x9365EA,0xE5BEFF} },
	{ name = "Ruby Chrome", rgb = 0xFF124F, premium=true, gradient={0x941F56,0xF43B73,0xFFB2CB} },
	{ name = "Aurora Mint", rgb = 0x00FFAC, premium=true, gradient={0x147C80,0x31DAAF,0xC0FFDC} },
	{ name = "Rose Quartz", rgb = 0xFFD2EE, premium=true, gradient={0xC274AD,0xF8B9E0,0xFFF0F7} },
	{ name = "Electric Glacier", rgb = 0x43E7FF, premium=true, gradient={0x2464BB,0x4DD8F2,0xD1FDFF} },
	{ name = "Acid Alloy", rgb = 0xD6FF00, premium=true, gradient={0x69932B,0xBDE547,0xF3FFB3} },
	{ name = "Icefire", rgb = 0x59CEF7, premium=true, gradient={0x2754A7,0x78DEEC,0xFFE2AA} },
	{ name = "Carbon Rose", rgb = 0xED5180, premium=true, gradient={0x3B306E,0xBE4E82,0xFFC6BB} },
}

function ProfileStyle.valid(value: any): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= 1 and value <= #ProfileStyle.colors
end

function ProfileStyle.item_id(index: number): string
	return "profile_color_" .. tostring(index)
end

function ProfileStyle.shop_indices(): { number }
	local out={}
	for index,color in ProfileStyle.colors do if color.premium then table.insert(out,index) end end
	return out
end

function ProfileStyle.allowed(index: any, owned: any): boolean
	return ProfileStyle.valid(index) and (index == 1
		or (type(owned) == "table" and owned[ProfileStyle.item_id(index)] == true))
end

function ProfileStyle.badge(wins: number): string
	if wins >= 100 then return "★ LEGEND" end
	if wins >= 25 then return "★ VETERAN" end
	if wins >= 5 then return "★ COMMANDER" end
	if wins >= 1 then return "★ FIRST WIN" end
	return "◆ RECRUIT"
end

return ProfileStyle
