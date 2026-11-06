local fs = require("@lune/fs")
local luau = require("@lune/luau")
local PrivateTest = require("../src/shared/Data/PrivateTest")
local Release = require("../src/shared/Data/ReleaseConfig")
Release.CHANNEL = "private"

local loadedPacks = 0
local played = {}
local function sound(asset: number)
	return { id = "rbxassetid://" .. asset }
end

local unloaded = { [sound(22).id] = true }
local assets = {
	Audio = { sfx = { ui_click = sound(11), ui_open = sound(12), victory = sound(13),
		nuke_launch = sound(14), nuke_explosion = sound(15), boat_launch = sound(16) } },
	UIAudioEvaluation = {
		cozy = { ui_click = sound(21), ui_open = sound(22), victory = sound(23), ui_error = sound(24),
			eliminate = sound(25), build = sound(26), nuke_launch = sound(27) },
		cartoon = { ui_click = sound(31) },
		boom = { ui_click = sound(41) },
	}
}
function assets:FindFirstChild(name)
	return self[name]
end

local shared = { Assets = assets, Core = { Signal = { new = function() return {} end } }, Data = { PrivateTest = PrivateTest, ReleaseConfig = Release } }
function shared:FindFirstChild(name)
	return self[name]
end

local signal = { Connect = function() end }
local services = {
	ReplicatedStorage = { WaitForChild = function() return shared end },
	Players = { LocalPlayer = { UserId = PrivateTest.OWNER } },
	RunService = { Heartbeat = signal },
	SoundService = {},
	ContentProvider = { PreloadAsync = function() end },
}
local game = { CreatorId = PrivateTest.OWNER, GameId = PrivateTest.UNIVERSE }
function game:GetService(name)
	return services[name]
end

local loadDirector = luau.load(fs.readFile("src/client/Audio/AudioDirector.luau"))
setfenv(loadDirector, setmetatable({
	game = game,
	script = { Parent = { WaitForChild = function() return {} end } },
	task = { spawn = function() end },
	require = function(module)
		if module == assets.UIAudioEvaluation then
			loadedPacks += 1
		end
		return module
	end,
	Instance = { new = function()
		return setmetatable({
			Ended = signal,
			Stop = function(self) self.IsPlaying = false end,
			Play = function(self)
				self.IsPlaying = true
				table.insert(played, self.SoundId)
			end,
		}, { __index = function(self, key)
			if key == "IsLoaded" then
				return not unloaded[self.SoundId]
			end
		end })
	end },
}, { __index = getfenv() }))
local AudioDirector = loadDirector()
local owner = AudioDirector.new("")
assert(owner:ui_audio_pack() == "cozy", "the owner starts with Cute & Cozy")
owner:play_sfx("ui_click")
assert(played[#played] == sound(21).id, "the normal click uses the selected pack")
owner:play_sfx("ui_open")
assert(played[#played] == sound(12).id, "an unloaded replacement falls back to the original")
assert(owner:has_sfx("ui_error"), "a loaded replacement can supply a cue missing from the original")
owner:play_sfx("victory", nil, nil, nil, true)
assert(played[#played] == sound(23).id, "preview uses the real victory cue")
assert(owner._last_full_ms.victory == nil and owner._duck_hold_s == 0, "preview does not consume match cooldowns or duck music")
owner:play_sfx("victory")
assert(owner._last_full_ms.victory ~= nil, "a real victory can still play after the preview")
for cue, asset in { eliminate = 25, build = 26 } do
	owner:play_sfx(cue, nil, nil, nil, true)
	assert(played[#played] == sound(asset).id, "match cue uses its licensed replacement: " .. cue)
	local volume = owner._pool["cozy:" .. cue][1].sound.Volume
	assert(math.abs(volume - 10 ^ ((owner.sfx_volume_db + AudioDirector.TRIM_DB[cue]) / 20)) < 1e-6,
		"the softer mix applies to both previews and gameplay")
end
for cue, asset in { nuke_launch = 14, nuke_explosion = 15, boat_launch = 16 } do
	owner:play_sfx(cue, nil, nil, nil, true)
	assert(played[#played] == sound(asset).id, "battle recordings are independent of the UI pack: " .. cue)
	assert(owner:_ui_audio_stream_name(cue) == cue)
	local volume = owner._pool[cue][1].sound.Volume
	assert(math.abs(volume - 10 ^ ((owner.sfx_volume_db + AudioDirector.TRIM_DB[cue]) / 20)) < 1e-6)
end

assert(owner:cycle_ui_audio_pack() == "original")
owner:play_sfx("ui_click", nil, nil, nil, true)
assert(played[#played] == sound(11).id, "Original restores the real click immediately")
assert(owner:cycle_ui_audio_pack() == "cartoon" and owner:cycle_ui_audio_pack() == "boom")
assert(owner:cycle_ui_audio_pack() == "cozy")

services.Players.LocalPlayer.UserId = 42
assert(AudioDirector.new(""):ui_audio_pack() == nil)
services.Players.LocalPlayer.UserId = PrivateTest.OWNER
game.GameId = 42
assert(AudioDirector.new(""):ui_audio_pack() == nil)
game.GameId = PrivateTest.UNIVERSE
game.CreatorId = 42
assert(AudioDirector.new(""):ui_audio_pack() == nil)
assert(loadedPacks == 1, "outside the private owner session the manifest is never loaded")

game.CreatorId = PrivateTest.OWNER
services.Players.LocalPlayer.UserId = 42
for _,channel in {"beta","live"} do
	Release.CHANNEL = channel
	local published = AudioDirector.new("")
	assert(published:ui_audio_pack() == nil, "public settings do not expose the private audition selector")
	published:play_sfx("ui_click")
	assert(played[#played] == sound(21).id, "licensed Cute & Cozy audio plays for ordinary users")
	assert(published._sfx_streams["boom:ui_click"] == nil and published._sfx_streams["cartoon:ui_click"] == nil,
		"private-only demo recordings never enter a release")
end
Release.CHANNEL = "private"
services.Players.LocalPlayer.UserId = PrivateTest.OWNER
assets.UIAudioEvaluation = { cozy = { ui_click = { id = "" } } }
assert(AudioDirector.new(""):ui_audio_pack() == nil, "an empty or invalid pack leaves the selector hidden")
luau.load(fs.readFile("src/client/UI/PauseMenu.luau"))
print("ui_audio_evaluation: owner, selector, voice routing, fallback and preview passed")
