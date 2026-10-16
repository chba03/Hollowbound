--[[
	Can a player interact with a station, desk, or pickup from where they stand?
	(milestone 5). Server only.

	Three conditions: within the distance, within Config.Reach.MaxHeightDifference
	vertically, and a clear line between the character and the target (only world
	geometry blocks it). Standing beneath a terminal or camp, or on another floor, never
	counts. withinReach is pure and tested.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))

local Reach = {}

local REASONS = {
	Far = "Move closer.",
	Level = "You need to be on the same level.",
	Blocked = "Something is in the way.",
}
Reach.REASONS = REASONS

-- Pure: positions are anything with X, Y, Z.
function Reach.withinReach(from, to, maxDistance: number, maxHeight: number): (boolean, string?)
	local dx, dy, dz = to.X - from.X, to.Y - from.Y, to.Z - from.Z
	if math.sqrt(dx * dx + dy * dy + dz * dz) > maxDistance then
		return false, "Far"
	end
	if math.abs(dy) > maxHeight then
		return false, "Level"
	end
	return true, nil
end

-- root: the player's HumanoidRootPart; target: the station or pickup part.
-- ignore: extra instances to ignore (for example, the target's model).
function Reach.check(root: BasePart, target: BasePart, maxDistance: number, ignore: { Instance }?): (boolean, string?)
	local ok, reason = Reach.withinReach(root.Position, target.Position, maxDistance, Config.Reach.MaxHeightDifference)
	if not ok then
		return false, reason
	end
	local exclude: { Instance } = { target }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	for _, instance in ignore or {} do
		table.insert(exclude, instance)
	end
	for _, name in { "HollowboundWorldRelics", "HollowboundWorldLoot", "HollowboundCreatures" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(exclude, folder)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	if workspace:Raycast(root.Position, target.Position - root.Position, params) ~= nil then
		return false, "Blocked"
	end
	return true, nil
end

-- Player-facing message for a failed check.
function Reach.message(reason: string?): string
	return REASONS[reason or ""] or "You cannot reach that from here."
end

return Reach
