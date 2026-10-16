--[[
	Melee rules without world access. Pure; positions are any tables with X, Y, Z
	(Roblox Vector3 works). Server only.

	The client never chooses targets or damage. The server takes the attacker's own
	position and facing, the weapon's range and arc, and a list of candidates whose
	line of sight it already checked, and returns each valid target at most once.
]]

local MeleeRules = {}

local function finite(n): boolean
	return typeof(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function finiteVector(v): boolean
	return v ~= nil and finite(v.X) and finite(v.Y) and finite(v.Z)
end

MeleeRules.finiteVector = finiteVector

-- Cooldown gate. swing = { lastSwingAt }. Returns (true) or (false, "Cooldown").
function MeleeRules.canSwing(swing, now: number, weapon): (boolean, string?)
	if swing.lastSwingAt and now - swing.lastSwingAt < weapon.cooldown then
		return false, "Cooldown"
	end
	return true, nil
end

--[[
	origin, look: attacker position and facing (look need not be unit length).
	candidates: { { id, position, radius, visible } }
	weapon: { range, arcDegrees }
	Returns a list of ids, each at most once.
]]
function MeleeRules.selectHits(origin, look, candidates, weapon, tolerance: number)
	local hits = {}
	if not (finiteVector(origin) and finiteVector(look)) then
		return hits
	end
	local lookLength = math.sqrt(look.X * look.X + look.Z * look.Z)
	if lookLength < 1e-6 then
		return hits
	end
	local lx, lz = look.X / lookLength, look.Z / lookLength
	local cosHalfArc = math.cos(math.rad(weapon.arcDegrees / 2))
	local seen = {}
	for _, candidate in candidates do
		local p = candidate.position
		if seen[candidate.id] or not candidate.visible or not finiteVector(p) then
			continue
		end
		local dx, dy, dz = p.X - origin.X, p.Y - origin.Y, p.Z - origin.Z
		local flat = math.sqrt(dx * dx + dz * dz)
		local radius = if finite(candidate.radius) then candidate.radius else 0
		if flat - radius > weapon.range + tolerance or math.abs(dy) > weapon.range + radius then
			continue
		end
		-- Facing: inside the arc, or so close that the arc does not matter.
		if flat > radius + 0.5 then
			local dot = (dx * lx + dz * lz) / flat
			if dot < cosHalfArc then
				continue
			end
		end
		seen[candidate.id] = true
		table.insert(hits, candidate.id)
	end
	return hits
end

return MeleeRules
