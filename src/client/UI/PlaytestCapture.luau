--!nonstrict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Data = ReplicatedStorage.Airfront.Data
local Metrics = require(Data.PlaytestMetrics)
local Cosmetics = require(Data.Cosmetics)
local Defs = require(ReplicatedStorage.Airfront.Core.Defs)
local UICtx = require("./UICtx")

local Capture = {}

function Capture.new(player, ctx, notice)
	local running = false
	return function()
		if running then
			notice("Performance test already running.", 6)
			return
		end
		local state, session = ctx.state, ctx.session
		local rig = ctx.world and ctx.world.rig
		local net = ReplicatedStorage:FindFirstChild("AirfrontNet")
		local remote = net and net:FindFirstChild("AtlasPlaytest")
		if not (state and session and rig) or not ctx:in_match() or session.testing then
			notice("Start a normal match to run the performance test.", 8)
			return
		end
		if not remote or not remote:IsA("RemoteFunction") then
			notice("Performance testing is unavailable. Rejoin the latest private server.", 8)
			return
		end
		local mode = ctx:mode()
		local online = mode == UICtx.MODE_MULTI
		local frames, pings = table.create(5400), {}
		local elapsed, next_ping, changed, peak = 0, 1, 0, 0
		local moving_frames, tile_frames, camera_hitches, tile_hitches = 0, 0, 0, 0
		local x, y, scale = rig.cu, rig.cv, rig.scale
		local render, focus, tiles
		local function stop()
			if render then render:Disconnect() end
			if tiles then tiles:Disconnect() end
			focus:Disconnect()
		end
		local function cancel()
			stop()
			running = false
			notice("Performance test interrupted. Stay in the match and try again.", 8)
		end
		running = true
		focus = UIS.WindowFocusReleased:Connect(cancel)
		notice("Recording for 90s. Pan, zoom and expand your territory.", 9)
		task.delay(1, function()
			if not focus.Connected then return end
			tiles = state.tiles_changed:Connect(function(changes)
				changed += #changes
			end)
			render = RunService.PreRender:Connect(function(dt)
				if ctx.state ~= state or ctx:mode() ~= mode or state.phase == Defs.PHASE_OVER
					or dt > 30 or #frames >= Metrics.MAX_FRAMES then
					cancel()
					return
				end
				if dt <= 0 then return end
				local ms = dt * 1000
				elapsed += dt
				frames[#frames + 1] = ms
				local moving = math.abs(x - rig.cu) + math.abs(y - rig.cv) > .01 or math.abs(scale - rig.scale) > .001
				x, y, scale = rig.cu, rig.cv, rig.scale
				if moving then
					moving_frames += 1
					if ms > Metrics.HITCH_MS then camera_hitches += 1 end
				end
				if changed > 0 then
					tile_frames += 1
					peak = math.max(peak, changed)
					if ms > Metrics.HITCH_MS then tile_hitches += 1 end
					changed = 0
				end
				if online and elapsed >= next_ping then
					next_ping = math.floor(elapsed) + 1
					local ping = player:GetNetworkPing() * 1000
					if ping > 0 and ping <= 60000 then pings[#pings + 1] = ping end
				end
				if elapsed < Metrics.SECONDS then return end
				stop()
				task.defer(function()
					local report = Metrics.summarize(frames, elapsed, pings)
					local style = state.cosmetics[state.local_owner] or {}
					report.device = if UIS.TouchEnabled and not UIS.KeyboardEnabled then "phone" else "desktop"
					report.mode = if online then "online" else "solo"
					report.map = state.map_id
					report.countryColor = style.color or 0
					report.skin = style.skin or ""
					report.flagFill = style.flag_fill == true and Cosmetics.banner_for(style.flag) ~= nil
					report.movingFrames, report.tileFrames = moving_frames, tile_frames
					report.cameraOver33, report.territoryOver33, report.peakChangedTiles = camera_hitches, tile_hitches, peak
					local ok, saved = pcall(remote.InvokeServer, remote, report)
					running = false
					notice(string.format("%s · %.1f FPS · P99 %.1f ms · %d slow frames",
						if ok and saved then "Test saved" else "Test save failed", report.fps, report.p99Ms, report.over33), 15)
				end)
			end)
		end)
	end
end

return Capture
