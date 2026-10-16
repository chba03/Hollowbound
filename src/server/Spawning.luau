--[[
	Where players spawn, and camera limits (milestone 5). Server only.

	Vertical mode: every player's RespawnLocation is the SpawnLocation tagged
	HB_TownSpawn inside the installed world (the rim town plaza). Other SpawnLocations in
	the place (for example the Baseplate template's) are never used for our players.
	Legacy mode: DevMap keeps doing this for the legacy dev map.

	Camera: player-controlled third person with Config.Camera zoom limits and the default
	"Zoom" occlusion (the camera moves in front of walls). No cinematic camera moves.
	These properties are set per player at join, which needs no Studio setting.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Markers = require(script.Parent.Markers)

local Spawning = {}

local townSpawn: SpawnLocation? = nil

function Spawning.townSpawn(): SpawnLocation?
	return townSpawn
end

local function setup(player: Player)
	player.CameraMinZoomDistance = Config.Camera.MinZoom
	player.CameraMaxZoomDistance = Config.Camera.MaxZoom
	player.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Zoom
	if townSpawn then
		player.RespawnLocation = townSpawn
	end
end

-- mode: WorldInfo.mode()
function Spawning.start(mode: string)
	if mode == "Vertical" then
		local spawns = Markers.tagged(Config.Tags.TownSpawn)
		for _, candidate in spawns do
			if candidate:IsA("SpawnLocation") then
				townSpawn = candidate
				break
			end
		end
		if not townSpawn then
			warn("[Hollowbound] No SpawnLocation tagged " .. Config.Tags.TownSpawn .. " in the installed world; players spawn at the place default.")
		elseif #spawns > 1 then
			warn("[Hollowbound] More than one town spawn in the installed world; using " .. townSpawn:GetFullName())
		end
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
		-- A player who joined before this ran spawned elsewhere: respawn them in town once.
		if townSpawn and player.Character then
			player:LoadCharacter()
		end
	end
end

return Spawning
