--[[
	Tracks which zone each player is in: "Town", "Camp", or "Depths".
	Sets the player attribute HB_Zone, which the client displays.

	A camp is a refuge only (Decided). Entering one never changes relic state. This
	module reads the store for log messages and never writes to it.
	Camp protection rules such as aggression timers come with PvP later.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Characters = require(script.Parent.Characters)
local ServerNet = require(script.Parent.ServerNet)

local Zones = {}

local ZONE_TAGS = {
	{ tag = Config.Tags.TownZone, zone = "Town" },
	{ tag = Config.Tags.CampZone, zone = "Camp" },
}

local function inside(part: BasePart, position: Vector3): boolean
	local localPos = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end

function Zones.zoneAt(position: Vector3): string
	for _, entry in ZONE_TAGS do
		for _, part in CollectionService:GetTagged(entry.tag) do
			if part:IsA("BasePart") and inside(part, position) then
				return entry.zone
			end
		end
	end
	return "Depths"
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

function Zones.start(store)
	task.spawn(function()
		while true do
			task.wait(Config.Zones.CheckInterval)
			for _, player in Players:GetPlayers() do
				local root = Characters.liveRoot(player)
				if not root then
					continue
				end
				local zone = Zones.zoneAt(root.Position)
				if player:GetAttribute("HB_Zone") == zone then
					continue
				end
				player:SetAttribute("HB_Zone", zone)

				local unsecured = unsecuredCount(store, player)
				if zone == "Camp" then
					ServerNet.notify(player, "Camp: a refuge. Relics you carry stay unsecured until registered in town.", "info")
					print(`[Hollowbound] {player.Name} entered camp; {unsecured} unsecured relic(s) unchanged`)
				elseif zone == "Town" and unsecured > 0 then
					ServerNet.notify(player, "Town: use the Registry Terminal to secure your fresh relics.", "info")
				end
			end
		end
	end)
end

return Zones
