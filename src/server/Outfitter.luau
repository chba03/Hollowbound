--[[
	Consistent explorer equipment on every avatar (milestone 5). Server only.

	Each player keeps their own avatar (face, hair, skin tone, clothing); the game adds a
	shared explorer kit: backpack with bedroll, chest strap, rope coil, and a hip lantern
	that lights up below Config.Outfit.LanternDepth. All pieces are welded, massless, and
	non-colliding, cannot be hit by raycasts or touches, and cast no shadows, so hitboxes,
	reach, and movement are unchanged. Added once per character on
	CharacterAppearanceLoaded: no character reloads.

	Proxies: the pieces are built-in-material parts (see docs/ASSETS.md), to be swapped for
	reviewed mesh assets later. Body proportions are not changed (Config.Outfit
	SlenderProportions is off and not implemented: scaling would change hitboxes).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local WorldInfo = require(script.Parent.WorldInfo)

local Outfitter = {}

local lanterns: { [Player]: PointLight } = {}

local function rgb(name: string): Color3
	local c = Config.World.Palette[name]
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function piece(model: Model, anchor: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	if shape then
		part.Shape = shape
	end
	part.Color = color
	part.Material = material
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = anchor.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchor
	weld.Part1 = part
	weld.Parent = part
	part.Parent = model
	return part
end

local function dress(player: Player, character: Model)
	if not Config.Outfit.Enabled or character:FindFirstChild("HB_ExplorerGear") then
		return
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local lower = character:FindFirstChild("LowerTorso") or torso
	if not (torso and torso:IsA("BasePart") and lower and lower:IsA("BasePart")) then
		return
	end
	local model = Instance.new("Model")
	model.Name = "HB_ExplorerGear"
	local back = torso.Size.Z / 2
	piece(model, torso, "Backpack", Vector3.new(1.7, 2, 0.9), CFrame.new(0, 0, back + 0.45), rgb("Cloth"), Enum.Material.Fabric)
	piece(model, torso, "Bedroll", Vector3.new(1.9, 0.7, 0.7), CFrame.new(0, 1.25, back + 0.45) * CFrame.Angles(0, 0, math.rad(90)), rgb("Timber"), Enum.Material.Fabric, Enum.PartType.Cylinder)
	piece(model, torso, "Strap", Vector3.new(0.25, 2.3, 0.1), CFrame.new(0, 0, -back - 0.05) * CFrame.Angles(0, 0, math.rad(35)), rgb("RootWood"), Enum.Material.Fabric)
	piece(model, lower, "RopeCoil", Vector3.new(0.35, 1, 1), CFrame.new(-lower.Size.X / 2 - 0.2, 0, 0), rgb("WeatheredWood"), Enum.Material.Fabric, Enum.PartType.Cylinder)
	local lantern = piece(model, lower, "Lantern", Vector3.new(0.5, 0.7, 0.5), CFrame.new(lower.Size.X / 2 + 0.25, -0.1, 0), rgb("WarmLight"), Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = rgb("WarmLight")
	light.Brightness = 0.7
	light.Range = 12
	light.Shadows = false
	light.Enabled = false
	light.Parent = lantern
	model.Parent = character
	lanterns[player] = light
end

function Outfitter.start()
	local function watchPlayer(player: Player)
		player.CharacterAppearanceLoaded:Connect(function(character)
			dress(player, character)
		end)
		if player.Character and player:HasAppearanceLoaded() then
			task.spawn(dress, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lanterns[player] = nil
	end)
	-- Lanterns light up in the shaded depths (one light per explorer at most).
	task.spawn(function()
		while true do
			task.wait(1)
			for player, light in lanterns do
				if not light.Parent then
					lanterns[player] = nil
					continue
				end
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local depth = root and root:IsA("BasePart") and WorldInfo.depthAt(root.Position)
				light.Enabled = depth ~= nil and depth >= Config.Outfit.LanternDepth
			end
		end
	end)
end

return Outfitter
