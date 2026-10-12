--[[
	Tracks where each player is. Sets player attributes the client displays:
	  HB_Zone  - "Town", "Camp", or "Depths"
	  HB_Layer - 0 in town, otherwise the Hollow layer 1..7
	  HB_Depth - studs below rim height (rounded)

	Tagged zone volumes (Tags.TownZone, Tags.CampZone) win. Otherwise the Hollow's
	geometry decides: near rim height and outside the pit is town; inside the pit and
	below the rim is the depths.

	A camp is a refuge only (Decided). Entering one never changes relic state. This
	module reads the store for log messages and never writes to it.
	Camp protection rules such as aggression timers come with PvP later.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Progression = require(Shared:WaitForChild("Progression"))
local Characters = require(script.Parent.Characters)
local Ground = require(script.Parent.Ground)
local Hollow = require(script.Parent.Hollow)
local ServerNet = require(script.Parent.ServerNet)

local Zones = {}

local ZONE_TAGS = {
	{ tag = Config.Tags.TownZone, zone = "Town" },
	{ tag = Config.Tags.CampZone, zone = "Camp" },
}

-- Camps are round: a part with a Radius attribute is a vertical cylinder of that
-- radius and the part's height. Other zone parts are boxes.
local function inside(part: BasePart, position: Vector3): boolean
	local localPos = part.CFrame:PointToObjectSpace(position)
	local radius = part:GetAttribute("Radius")
	if typeof(radius) == "number" then
		return Vector2.new(localPos.X, localPos.Z).Magnitude <= radius and math.abs(localPos.Y) <= part.Size.Y / 2
	end
	local half = part.Size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end

-- Returns (zone, layer, depth). depth is 0 when there is no Hollow.
function Zones.zoneAt(position: Vector3): (string, number, number)
	local depth, _, inPit = Hollow.measure(position)
	local layer = if depth and inPit then Progression.layerForDepth(depth) else 0

	for _, entry in ZONE_TAGS do
		for _, part in CollectionService:GetTagged(entry.tag) do
			if part:IsA("BasePart") and inside(part, position) then
				return entry.zone, layer, depth or 0
			end
		end
	end

	if not depth then
		return "Depths", 0, 0
	end
	if depth < Config.Hollow.TownDepthTolerance and (not inPit or depth <= 0) then
		return "Town", 0, depth
	end
	return "Depths", layer, depth
end

local function unsecuredCount(store, player: Player): number
	local count = 0
	for _, specimen in store:carried(player.UserId) do
		if not specimen.registered then
			count += 1
		end
	end
	return count
end

-- A glowing yellow ring on the ground around a round camp, so players can see how far
-- the refuge reaches, plus a faint fill. About 30 non-colliding parts per camp.
local function drawCampRing(zone: BasePart, folder: Instance)
	local radius = zone:GetAttribute("Radius")
	if typeof(radius) ~= "number" then
		return
	end
	local camps = Config.Camps
	local floor = zone.CFrame * CFrame.new(0, -zone.Size.Y / 2, 0)
	-- Each piece sits on the real ground below it, so the ring follows uneven terrain.
	local function onGround(cframe: CFrame, lift: number): CFrame
		local groundY = Ground.below(cframe.Position)
		return if groundY then cframe + Vector3.new(0, groundY + lift - cframe.Position.Y, 0) else cframe + Vector3.new(0, lift, 0)
	end
	local function piece(name: string, size: Vector3, cframe: CFrame, transparency: number, shape: Enum.PartType?)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = camps.RingColor
		p.Transparency = transparency
		p.Size = size
		p.CFrame = cframe
		if shape then
			p.Shape = shape
		end
		p.Parent = folder
	end
	local segments = camps.RingSegments
	local length = 2 * math.pi * radius / segments * 1.08
	for i = 0, segments - 1 do
		local angle = i / segments * 2 * math.pi
		piece("CampRing", Vector3.new(0.5, 0.35, length), onGround(floor * CFrame.Angles(0, angle, 0) * CFrame.new(radius, 0, 0), 0.4), 0.15)
	end
	piece("CampArea", Vector3.new(0.1, radius * 2, radius * 2), onGround(floor, 0.35) * CFrame.Angles(0, 0, math.pi / 2), 0.88, Enum.PartType.Cylinder)
end

function Zones.start(store)
	local rings = Instance.new("Folder")
	rings.Name = "HollowboundCampRings"
	rings.Parent = workspace
	for _, zone in CollectionService:GetTagged(Config.Tags.CampZone) do
		if zone:IsA("BasePart") then
			drawCampRing(zone, rings)
		end
	end

	task.spawn(function()
		while true do
			task.wait(Config.Zones.CheckInterval)
			for _, player in Players:GetPlayers() do
				local root = Characters.liveRoot(player)
				if not root then
					continue
				end
				local zone, layer, depth = Zones.zoneAt(root.Position)
				player:SetAttribute("HB_Depth", math.max(0, math.floor(depth)))
				player:SetAttribute("HB_Layer", layer)
				if player:GetAttribute("HB_Zone") == zone then
					continue
				end
				player:SetAttribute("HB_Zone", zone)

				local unsecured = unsecuredCount(store, player)
				if zone == "Camp" then
					ServerNet.notify(player, "Camp: a refuge. Relics you carry stay unsecured until registered in town.", "info")
					print(`[Hollowbound] {player.Name} entered camp; {unsecured} unsecured relic(s) unchanged`)
				elseif zone == "Town" and unsecured > 0 then
					ServerNet.notify(player, "Town: use your base's Registry Terminal to secure your fresh relics.", "info")
				end
			end
		end
	end)
end

return Zones
