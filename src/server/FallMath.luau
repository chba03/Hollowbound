-- Fall damage from impact speed (milestone 5, provisional). Pure; tested.

local FallMath = {}

-- cfg = Config.Falls. Returns whole damage points (0 for a safe landing).
function FallMath.damageFor(speed: number, cfg): number
	if typeof(speed) ~= "number" or speed ~= speed or speed <= cfg.SafeSpeed then
		return 0
	end
	local t = math.clamp((speed - cfg.SafeSpeed) / (cfg.LethalSpeed - cfg.SafeSpeed), 0, 1)
	return math.ceil(t * cfg.MaxDamage)
end

-- Impact speed after falling `height` studs with Roblox's default gravity.
function FallMath.speedAfter(height: number, gravity: number?): number
	return math.sqrt(2 * (gravity or 196.2) * math.max(0, height))
end

return FallMath
