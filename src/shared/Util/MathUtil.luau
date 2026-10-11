--!strict
local MathUtil = {}

function MathUtil.clamp01(x: number): number
	return if x < 0 then 0 elseif x > 1 then 1 else x
end

function MathUtil.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Frame-rate independent exponential approach toward `target`.
function MathUtil.approach(current: number, target: number, rate: number, dt: number): number
	return target + (current - target) * math.exp(-rate * dt)
end

function MathUtil.inverseLerp(a: number, b: number, value: number): number
	if a == b then
		return 0
	end
	return MathUtil.clamp01((value - a) / (b - a))
end

-- Minutes after midnight (may be negative for the previous evening) to "HH:MM".
function MathUtil.formatClock(minutes: number, withSeconds: boolean?): string
	local total = math.floor(minutes * 60) % (24 * 3600)
	local h = total // 3600
	local m = (total // 60) % 60
	local s = total % 60
	if withSeconds then
		return string.format("%02d:%02d:%02d", h, m, s)
	end
	return string.format("%02d:%02d", h, m)
end

return MathUtil
