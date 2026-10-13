--[[
	Reads what a player has bought and turns it into multipliers. Shared by server and
	client so both always agree. The server's Store sets the attributes; nothing here
	writes state.

	  HB_Pass_<perk>    true when the player owns that game pass perk
	  HB_Boost_<boost>  server time (workspace:GetServerTimeNow) the boost runs until
	  workspace HB_ServerLuckUntil  server time the Lucky Lantern runs until
]]

local Config = require(script.Parent.Config)

local Perks = {}

local shop = Config.Shop

function Perks.now(): number
	return workspace:GetServerTimeNow()
end

function Perks.hasPass(player: Player, perk: string): boolean
	return player:GetAttribute("HB_Pass_" .. perk) == true
end

-- Seconds left on a timed boost (0 when not active).
function Perks.boostLeft(player: Player, boost: string): number
	local untilTime = player:GetAttribute("HB_Boost_" .. boost)
	return if typeof(untilTime) == "number" then math.max(0, untilTime - Perks.now()) else 0
end

local function multiply(player: Player, field: string): number
	local m = 1
	for perkId, perk in shop.Perks do
		if perk[field] and Perks.hasPass(player, perkId) then
			m *= perk[field]
		end
	end
	for boostId, boost in shop.Boosts do
		if boost[field] and Perks.boostLeft(player, boostId) > 0 then
			m *= boost[field]
		end
	end
	return m
end

-- Display income multiplier (passes x boosts).
function Perks.income(player: Player): number
	return multiply(player, "income")
end

-- Climb speed multiplier.
function Perks.climb(player: Player): number
	return multiply(player, "climb")
end

function Perks.staminaDrain(player: Player): number
	return multiply(player, "staminaDrain")
end

function Perks.staminaRegen(player: Player): number
	return multiply(player, "staminaRegen")
end

-- Speed gained per pull on the Hauling Rig (no perk changes it yet).
function Perks.speedGain(player: Player): number
	return multiply(player, "speedGain")
end

-- Scales the safe and fatal fall heights.
function Perks.fall(player: Player): number
	return multiply(player, "fall")
end

-- Seconds left on the server-wide Lucky Lantern (0 when not lit).
function Perks.serverLuckLeft(): number
	local untilTime = workspace:GetAttribute("HB_ServerLuckUntil")
	return if typeof(untilTime) == "number" then math.max(0, untilTime - Perks.now()) else 0
end

-- The weekly offer's index into Config.Shop.Limited.Offers, and seconds until it rotates.
function Perks.weeklyOffer(): (number, number, number)
	local limited = shop.Limited
	local t = Perks.now() + limited.WeekOffset
	local week = math.floor(t / limited.WeekSeconds)
	local index = week % #limited.Offers + 1
	local left = (week + 1) * limited.WeekSeconds - t
	return index, left, week
end

-- Cash a "cash" item pays this player now: income x minutes, at least the minimum.
function Perks.cashFor(player: Player, minutes: number, minimum: number): number
	local income = player:GetAttribute("HB_Income")
	local rate = if typeof(income) == "number" then income else 0
	return math.max(minimum, math.floor(rate * 60 * minutes))
end

return Perks
