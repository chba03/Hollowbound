--[[
	Locates the Hollow through the part tagged Tags.HollowRim, whose position is the pit
	centre at rim height. Publishes it as the workspace attribute HB_HollowCenter so
	clients can read it even when streaming has not loaded the rim part.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Progression = require(Shared:WaitForChild("Progression"))

local Hollow = {}

local center: Vector3? = nil

function Hollow.start()
	local rim = CollectionService:GetTagged(Config.Tags.HollowRim)[1]
	if not (rim and rim:IsA("BasePart")) then
		warn(`[Hollowbound] No part tagged {Config.Tags.HollowRim}; depth, layers, and ropes are disabled.`)
		return
	end
	center = rim.Position
	workspace:SetAttribute("HB_HollowCenter", center)
end

function Hollow.center(): Vector3?
	return center
end

-- Returns (depth below rim height, horizontal distance from the pit centre, inside pit).
-- The pit's radius changes with depth (Progression.pitRadiusAt).
-- Depth is negative above the rim. Returns nil when no Hollow exists.
function Hollow.measure(position: Vector3): (number?, number?, boolean?)
	if not center then
		return nil, nil, nil
	end
	local depth = center.Y - position.Y
	local horizontal = Vector2.new(position.X - center.X, position.Z - center.Z).Magnitude
	return depth, horizontal, horizontal < Progression.pitRadiusAt(math.max(depth, 0))
end

return Hollow
