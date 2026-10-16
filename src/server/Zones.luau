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
local Markers = require(script.Parent.Markers)
local Reach = require(script.Parent.Reach)
local WorldInfo = require(script.Parent.WorldInfo)
local ServerNet = require(script.Parent.ServerNet)

local Zones = {}

local tickListeners: { (Player, string, BasePart) -> () } = {}

-- fn(player, zone, root) runs on every zone check for each living character.
-- Expedition uses it to follow Town / Exploring / AtCamp without a require cycle.
function Zones.onTick(fn: (Player, string, BasePart) -> ())
	table.insert(tickListeners, fn)
end

-- True if the point is in a zone where milestone 4 combat damage cannot happen.
function Zones.isProtected(position: Vector3): boolean
	return Config.ProtectedZones[Zones.zoneAt(position)] == true
end

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
		for _, part in Markers.tagged(entry.tag) do
			if part:IsA("BasePart") and inside(part, position) then
				return entry.zone
			end
		end
	end
	return "Depths"
end

-- Town desk: inside a town zone and able to reach a registry terminal or service
-- station (distance, same level, clear line; milestone 5). Appraisal and activation need
-- this; it is always computed fresh on the server.
function Zones.atDesk(root: BasePart): boolean
	if Zones.zoneAt(root.Position) ~= "Town" then
		return false
	end
	for _, tag in { Config.Tags.RegistrationTerminal, Config.Tags.ServiceStation } do
		for _, part in Markers.tagged(tag) do
			if part:IsA("BasePart") and Reach.check(root, part, Config.TownDesk.ServerMaxDistance) then
				return true
			end
		end
	end
	return false
end

function Zones.playerAtDesk(player: Player): boolean
	local root = Characters.liveRoot(player)
	return root ~= nil and Zones.atDesk(root)
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
				-- The HUD enables Appraise/Activate buttons from this; the server re-checks.
				local atDesk = Zones.atDesk(root)
				if player:GetAttribute("HB_AtDesk") ~= atDesk then
					player:SetAttribute("HB_AtDesk", atDesk)
					ServerNet.pushState(player)
				end

				local zone = Zones.zoneAt(root.Position)
				-- Region name and depth for the HUD (vertical world only; no coordinates).
				local region = WorldInfo.regionAt(root.Position, zone)
				if player:GetAttribute("HB_Region") ~= region then
					player:SetAttribute("HB_Region", region)
				end
				local depth = WorldInfo.displayDepth(root.Position)
				if player:GetAttribute("HB_Depth") ~= depth then
					player:SetAttribute("HB_Depth", depth)
				end
				for _, listener in tickListeners do
					listener(player, zone, root)
				end
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
