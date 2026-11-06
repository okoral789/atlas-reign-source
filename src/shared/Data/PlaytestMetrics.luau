--!strict
local Metrics = { SECONDS = 90, STORE = "AtlasPlaytestV1", MAX_FRAMES = 36000, HITCH_MS = 1000 / 30 }

local function percentile(sorted: { number }, fraction: number): number
	return sorted[math.ceil(#sorted * fraction)]
end

function Metrics.summarize(frames: { number }, seconds: number, ping: { number }): { [string]: number }
	table.sort(frames)
	table.sort(ping)
	local hitches, stalls = 0, 0
	for _, ms in frames do
		if ms > Metrics.HITCH_MS then hitches += 1 end
		if ms > 50 then stalls += 1 end
	end
	return {
		seconds = seconds, frames = #frames, fps = #frames / seconds,
		p95Ms = percentile(frames, .95), p99Ms = percentile(frames, .99), worstMs = frames[#frames],
		over33 = hitches, over50 = stalls, pingSamples = #ping, ping95Ms = percentile(ping, .95) or 0,
	}
end

local maxima = {
	seconds = Metrics.SECONDS + 30, frames = Metrics.MAX_FRAMES, fps = Metrics.MAX_FRAMES / Metrics.SECONDS,
	p95Ms = 30000, p99Ms = 30000, worstMs = 30000, over33 = Metrics.MAX_FRAMES, over50 = Metrics.MAX_FRAMES,
	cameraOver33 = Metrics.MAX_FRAMES, territoryOver33 = Metrics.MAX_FRAMES, movingFrames = Metrics.MAX_FRAMES,
	tileFrames = Metrics.MAX_FRAMES, peakChangedTiles = 1e8, pingSamples = 120, ping95Ms = 60000,
	countryColor = 1000,
}

function Metrics.clean(raw: any): any
	if type(raw) ~= "table" or (raw.device ~= "phone" and raw.device ~= "desktop")
		or (raw.mode ~= "online" and raw.mode ~= "solo") or type(raw.flagFill) ~= "boolean"
		or type(raw.map) ~= "string" or #raw.map > 32 or not string.match(raw.map, "^%w+@?%d*$")
		or type(raw.skin) ~= "string" or #raw.skin > 48 or not string.match(raw.skin, "^[%w_%-]*$") then
		return nil
	end
	local report: { [string]: any } = {
		device = raw.device, mode = raw.mode, map = raw.map, skin = raw.skin, flagFill = raw.flagFill,
	}
	for field, max in maxima do
		local n = raw[field]
		if type(n) ~= "number" or not (n >= 0 and n <= max) then return nil end
		report[field] = n
	end
	if report.seconds < Metrics.SECONDS or report.frames < 1 or report.p95Ms <= 0
		or report.p95Ms > report.p99Ms or report.p99Ms > report.worstMs
		or report.over50 > report.over33 or report.over33 > report.frames
		or report.movingFrames > report.frames or report.tileFrames > report.frames
		or report.cameraOver33 > math.min(report.over33, report.movingFrames)
		or report.territoryOver33 > math.min(report.over33, report.tileFrames)
		or math.abs(report.fps - report.frames / report.seconds) > .01
		or (report.mode == "solo" and report.pingSamples ~= 0) then
		return nil
	end
	return report
end

return Metrics
