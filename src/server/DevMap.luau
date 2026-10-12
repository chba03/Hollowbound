--[[
	DEVELOPMENT ONLY. Builds placeholder geometry at runtime during Studio playtests:
	a town with spawn and registry terminal, a camp, and an expedition pickup area,
	connected by walkways.

	This module only adds Workspace.HollowboundDevMap. It never edits or removes other
	Workspace content. It builds nothing when:
	  - Workspace already has a HollowboundDevMap (for example, one you saved), or
	  - a part tagged as a registration terminal already exists (a hand-built map).

	The map is offset on X so it does not overlap the Baseplate template's SpawnLocation.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Tags = Config.Tags

local DevMap = {}

local MAP_NAME = "HollowboundDevMap"
local ORIGIN = Vector3.new(200, 0, 0)

local function block(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = ORIGIN + position
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function zoneVolume(parent: Instance, name: string, size: Vector3, position: Vector3, tag: string)
	local part = block(parent, name, size, position, Color3.new(1, 1, 1))
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	CollectionService:AddTag(part, tag)
	return part
end

local function sign(part: BasePart, text: string, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 56)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.MaxDistance = 150
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = gui
end

local function build(): Model
	local map = Instance.new("Model")
	map.Name = MAP_NAME

	-- Town: z from +45 to -45
	local town = block(map, "TownGround", Vector3.new(90, 1, 90), Vector3.new(0, 0.5, 0), Color3.fromRGB(196, 176, 130), Enum.Material.Cobblestone)
	zoneVolume(map, "TownZone", Vector3.new(90, 40, 90), Vector3.new(0, 20, 0), Tags.TownZone)
	sign(town, "TOWN", 12)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "TownSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = ORIGIN + Vector3.new(0, 1.5, 25)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(120, 160, 120)
	spawn.Parent = map

	local terminal = block(map, "RegistryTerminal", Vector3.new(4, 7, 2), Vector3.new(0, 4.5, -10), Color3.fromRGB(40, 110, 120), Enum.Material.Metal)
	block(map, "TerminalScreen", Vector3.new(3, 2, 0.2), Vector3.new(0, 6, -8.9), Color3.fromRGB(120, 255, 230), Enum.Material.Neon)
	CollectionService:AddTag(terminal, Tags.RegistrationTerminal)
	sign(terminal, "Registry Terminal\nsecures carried relics", 6)

	-- Walkway town -> camp
	block(map, "Walkway1", Vector3.new(10, 1, 45), Vector3.new(0, 0.5, -67.5), Color3.fromRGB(150, 130, 100), Enum.Material.WoodPlanks)

	-- Camp: z from -90 to -134
	local camp = block(map, "CampGround", Vector3.new(44, 1, 44), Vector3.new(0, 0.5, -112), Color3.fromRGB(90, 120, 70), Enum.Material.Grass)
	zoneVolume(map, "CampZone", Vector3.new(44, 40, 44), Vector3.new(0, 20, -112), Tags.CampZone)
	sign(camp, "CAMP: refuge\nrelics stay unsecured", 14)

	local tentLeft = Instance.new("WedgePart")
	tentLeft.Name = "TentLeft"
	tentLeft.Anchored = true
	tentLeft.Size = Vector3.new(8, 6, 4)
	tentLeft.CFrame = CFrame.new(ORIGIN + Vector3.new(10, 4, -120)) * CFrame.Angles(0, math.rad(90), 0)
	tentLeft.Color = Color3.fromRGB(170, 90, 60)
	tentLeft.Parent = map
	local tentRight = tentLeft:Clone()
	tentRight.Name = "TentRight"
	tentRight.CFrame = CFrame.new(ORIGIN + Vector3.new(14, 4, -120)) * CFrame.Angles(0, math.rad(-90), 0)
	tentRight.Parent = map

	local fire = block(map, "Campfire", Vector3.new(3, 1, 3), Vector3.new(-6, 1.5, -112), Color3.fromRGB(80, 50, 30), Enum.Material.Wood)
	Instance.new("Fire").Parent = fire
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 90)
	light.Range = 20
	light.Parent = fire

	-- Walkway camp -> expedition
	block(map, "Walkway2", Vector3.new(10, 1, 46), Vector3.new(0, 0.5, -157), Color3.fromRGB(110, 100, 90), Enum.Material.Slate)

	-- Expedition pickup area: z from -180 to -250
	local expedition = block(map, "ExpeditionGround", Vector3.new(80, 1, 70), Vector3.new(0, 0.5, -215), Color3.fromRGB(70, 75, 85), Enum.Material.Slate)
	sign(expedition, "EXPEDITION AREA", 16)
	block(map, "Rock1", Vector3.new(8, 10, 8), Vector3.new(-28, 6, -235), Color3.fromRGB(90, 90, 95), Enum.Material.Rock)
	block(map, "Rock2", Vector3.new(12, 6, 6), Vector3.new(26, 4, -200), Color3.fromRGB(90, 90, 95), Enum.Material.Rock)
	block(map, "Ruin", Vector3.new(2, 12, 16), Vector3.new(0, 7, -244), Color3.fromRGB(120, 110, 100), Enum.Material.Brick)

	-- Relic spawn pedestals, far enough apart that their prompts do not overlap.
	local spawnA = block(map, "RelicSpawnA", Vector3.new(3, 2, 3), Vector3.new(-15, 2, -225), Color3.fromRGB(60, 60, 70), Enum.Material.Marble)
	local spawnB = block(map, "RelicSpawnB", Vector3.new(3, 2, 3), Vector3.new(15, 2, -225), Color3.fromRGB(60, 60, 70), Enum.Material.Marble)
	CollectionService:AddTag(spawnA, Tags.RelicSpawn)
	CollectionService:AddTag(spawnB, Tags.RelicSpawn)

	map.Parent = workspace
	return map
end

-- Builds the map if needed and sends players to the town spawn.
function DevMap.ensure()
	local map = workspace:FindFirstChild(MAP_NAME)
	if not map then
		if #CollectionService:GetTagged(Tags.RegistrationTerminal) > 0 then
			print("[Hollowbound] Hand-built map detected; skipping placeholder map.")
			return
		end
		map = build()
		print("[Hollowbound] Built development placeholder map at X=200.")
	end

	local spawn = map:FindFirstChild("TownSpawn")
	if not (spawn and spawn:IsA("SpawnLocation")) then
		return
	end
	local function useTownSpawn(player: Player)
		player.RespawnLocation = spawn
	end
	Players.PlayerAdded:Connect(useTownSpawn)
	for _, player in Players:GetPlayers() do
		useTownSpawn(player)
		-- Players who joined before the map existed already spawned somewhere else.
		if player.Character then
			player:LoadCharacter()
		end
	end
end

return DevMap
