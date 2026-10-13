--[[
	Pure progression math shared by server and client: stat values from levels, next
	upgrade costs, layer lookup by depth, relic income, and number formatting.
	No Roblox services, so the self-test can check it directly.
]]

local Config = require(script.Parent.Config)

local Progression = {}

-- Upgrade kinds and the level tables they read from.
Progression.Upgrades = {
	RopeLength = { levels = Config.Rope.LengthLevels, field = "RopeLengthLevel", label = "Rope length", unit = " studs" },
	RopeSpeed = { levels = Config.Rope.SpeedLevels, field = "RopeSpeedLevel", label = "Climb speed", unit = "x per pull" },
	BaseSlots = { levels = Config.Base.SlotLevels, field = "BaseSlotsLevel", label = "Display slots", unit = "" },
}

function Progression.value(kind: string, level: number): number
	local levels = Progression.Upgrades[kind].levels
	return levels[math.clamp(level, 1, #levels)].value
end

-- Returns the next level's definition and number, or nil at max level.
function Progression.next(kind: string, level: number)
	local levels = Progression.Upgrades[kind].levels
	local nextLevel = level + 1
	if nextLevel > #levels then
		return nil, nil
	end
	return levels[nextLevel], nextLevel
end

-- Layer index for a depth in studs below rim height: 0 at or above the rim, then 1..10.
function Progression.layerForDepth(depth: number): number
	if depth <= 0 then
		return 0
	end
	return math.clamp(math.ceil(depth / Config.Hollow.LayerHeight), 1, #Config.Layers)
end

-- Pit radius at a depth below rim height. Each layer's radius applies at its centre and
-- blends smoothly (cosine) into the next, so the chasm bulges and narrows without steps.
function Progression.pitRadiusAt(depth: number): number
	local layers = Config.Layers
	local height = Config.Hollow.LayerHeight
	local position = depth / height - 0.5 -- 0 at layer 1's centre, 1 at layer 2's, ...
	if position <= 0 then
		return layers[1].radius
	end
	if position >= #layers - 1 then
		return layers[#layers].radius
	end
	local index = math.floor(position) + 1
	local t = position - (index - 1)
	local s = (1 - math.cos(math.pi * t)) / 2
	return layers[index].radius + (layers[index + 1].radius - layers[index].radius) * s
end

-- Cash per second for one displayed relic, rounded to whole cash. Uses only
-- pre-appraisal information: tier income x type value x the depth multiplier of the
-- relic's home layer x size ^ Config.Sizes.IncomePower.
function Progression.incomeFor(typeId: string, rarity: string, layer: number, size: number?): number
	local tier = Config.RarityById[rarity]
	local base = if tier then tier.income else 0
	local relicType = Config.RelicTypes[typeId]
	local typeMultiplier = if relicType then relicType.valueMultiplier else 1
	local home = if relicType then relicType.layer else layer
	local layerDef = Config.Layers[math.clamp(home, 1, #Config.Layers)]
	local sizeMultiplier = (size or 1) ^ Config.Sizes.IncomePower
	return math.max(math.floor(base * typeMultiplier * layerDef.incomeMultiplier * sizeMultiplier + 0.5), if base > 0 then 1 else 0)
end

-- Income for a specimen (or a client view of one with typeId, rarity, layer, size).
function Progression.incomeOf(specimen): number
	return Progression.incomeFor(specimen.typeId, specimen.rarity, specimen.layer, specimen.size)
end

-- Size word for a specimen size ("" for ordinary sizes).
function Progression.sizeLabel(size: number?): string
	local label = ""
	for _, band in Config.Sizes.Bands do
		if (size or 1) >= band.min then
			label = band.label
		end
	end
	return label
end

-- Display name with the size word, e.g. "Huge Frost Shard".
function Progression.relicName(typeId: string, size: number?): string
	local relicType = Config.RelicTypes[typeId]
	local name = if relicType then relicType.displayName else typeId
	local label = Progression.sizeLabel(size)
	return if label == "" then name else `{label} {name}`
end

-- Climb speed in studs/s for a Speed stat (Config.Speed): diminishing returns, capped.
function Progression.climbSpeed(speed: number): number
	local s = Config.Speed
	return math.min(s.MaxClimb, s.BaseClimb + s.ClimbPerDecade * math.log10(1 + math.max(speed, 0)))
end

-- Climb speed above BaseClimb with no cap (studs/s): Speed's log curve times the climb
-- perk multiplier. Drives the small walk and stamina bonuses in Config.Speed.
function Progression.uncappedClimbGain(speed: number, perkMultiplier: number): number
	local s = Config.Speed
	local climb = (s.BaseClimb + s.ClimbPerDecade * math.log10(1 + math.max(speed, 0))) * perkMultiplier
	return math.max(0, climb - s.BaseClimb)
end

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Progression.formatCash(amount: number): string
	amount = math.floor(amount)
	local index = 1
	local scaled = amount
	while math.abs(scaled) >= 1000 and index < #SUFFIXES do
		scaled /= 1000
		index += 1
	end
	if index == 1 then
		return "$" .. tostring(amount)
	end
	return string.format("$%.1f%s", scaled, SUFFIXES[index])
end

-- A big number without the $, e.g. 1.2M.
function Progression.formatNumber(amount: number): string
	return string.sub(Progression.formatCash(amount), 2)
end

return Progression
