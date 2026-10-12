--[[
	DEVELOPMENT ONLY. Builds the placeholder world: the rim town on an island with
	Config.Plots.Count player plots, and the Hollow below it, a 7-layer chasm styled
	after the reference chart (see DevDecor for each layer's look).

	  DevTerrain  island, forest bowl, pit walls, ledges, floor (Smooth Terrain)
	  DevBackdrop mountain ring, sea, and distant islands (persistent parts)
	  DevBase     each base's look, its scaffold tower, and the town around the bases
	  DevDecor    lamps and vines on the pit lip, and each layer's props
	  this file   gameplay geometry: the rim marker, plots, relic spawn points, camps

	It only adds Workspace.HollowboundDevMap and terrain inside the Hollow's own region.
	It never edits or removes other Workspace content. It builds nothing when a part
	tagged Tags.HollowRim exists outside the dev map (a hand-built map). It builds the
	parts only if HollowboundDevMap is missing, and the terrain only if the pit wall has
	no terrain yet, so a map built in edit mode is kept as is.

	To bake the map into a place (so playtests start instantly and you can edit it), run
	this once in Studio's command bar in edit mode, then save:
	  require(game.ServerScriptService.HollowboundServer.DevMap).ensure()

	The map sits high above the Baseplate template (rim at Y = 1300). Plots move players
	up on spawn.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Progression = require(Shared:WaitForChild("Progression"))
local DevBackdrop = require(script.Parent.DevBackdrop)
local DevBase = require(script.Parent.DevBase)
local DevDecor = require(script.Parent.DevDecor)
local DevTerrain = require(script.Parent.DevTerrain)
local Ground = require(script.Parent.Ground)
local Tags = Config.Tags
local H = Config.Hollow

local DevMap = {}

local MAP_NAME = "HollowboundDevMap"
local CENTER = Vector3.new(0, 1300, 0)
local RIM_Y = CENTER.Y
local BOARD_Y = 6.5 -- centre height of the upgrade boards above the plot floor
local MARKER_RADIUS = H.LedgeInnerRadius + 7 -- relic orbs sit near the ledge edge, easy to spot from the rope

local PLOT_COLORS = {
	Color3.fromRGB(176, 140, 100),
	Color3.fromRGB(130, 150, 110),
	Color3.fromRGB(150, 120, 140),
	Color3.fromRGB(110, 140, 160),
	Color3.fromRGB(170, 150, 90),
	Color3.fromRGB(150, 110, 100),
	Color3.fromRGB(110, 150, 140),
	Color3.fromRGB(140, 130, 170),
}

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function hidden(p: BasePart)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
end

local function billboard(p: BasePart, text: string, height: number, width: number?)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(width or 220, 48)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.MaxDistance = 120
	gui.Parent = p

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

-- Point on the ring at `radius` and `angle` (radians), at height y.
local function polar(radius: number, angle: number, y: number): Vector3
	return Vector3.new(CENTER.X + math.cos(angle) * radius, y, CENTER.Z + math.sin(angle) * radius)
end

-- CFrame whose local X axis points away from the pit centre at `angle`.
local function radialCFrame(position: Vector3, angle: number): CFrame
	return CFrame.new(position) * CFrame.Angles(0, -angle, 0)
end

-- The rim marker, relic spawn points on every ledge, and a camp on each layer from 2 down.
local function buildHollow(map: Model)
	local hollow = Instance.new("Model")
	hollow.Name = "Hollow"
	hollow.Parent = map

	local rim = part(hollow, "HollowRim", Vector3.new(1, 1, 1), CFrame.new(CENTER), Color3.new(1, 1, 1))
	hidden(rim)
	CollectionService:AddTag(rim, Tags.HollowRim)

	for layer = 1, #Config.Layers do
		local folder = Instance.new("Folder")
		folder.Name = "Layer" .. layer
		folder.Parent = hollow
		local layerTop = (layer - 1) * H.LayerHeight

		for ledgeIndex, offset in H.LedgeDepths do
			local ledgeTop = RIM_Y - (layerTop + offset)
			for i = 0, 4 do
				local angle = math.rad(i * 72 + layer * 23 + ledgeIndex * 36)
				local marker = part(folder, "RelicSpawn", Vector3.new(2, 0.4, 2), radialCFrame(polar(MARKER_RADIUS, angle, ledgeTop + 0.2), angle), Color3.new(1, 1, 1))
				hidden(marker)
				marker:SetAttribute("Layer", layer)
				CollectionService:AddTag(marker, Tags.RelicSpawn)
			end
		end

		if layer >= 2 then
			local depth = layerTop + H.LedgeDepths[1]
			local ledgeTop = RIM_Y - depth
			local angle = math.rad(layer * 45 + 22.5)
			local campRadius = (H.LedgeInnerRadius + Progression.pitRadiusAt(depth)) / 2
			local campPos = polar(campRadius, angle, ledgeTop)
			local camps = Config.Camps
			local zone = part(folder, "CampZone", Vector3.new(camps.Radius * 2, camps.Height, camps.Radius * 2), radialCFrame(campPos + Vector3.new(0, camps.Height / 2, 0), angle), Color3.new(1, 1, 1))
			hidden(zone)
			zone:SetAttribute("Radius", camps.Radius) -- round refuge; Zones draws its ring
			zone:SetAttribute("HB_Settle", -1) -- bottom 1 stud below the ground
			CollectionService:AddTag(zone, Tags.CampZone)

			local fire = part(folder, "Campfire", Vector3.new(3, 1, 3), radialCFrame(campPos + Vector3.new(0, 0.5, 0), angle), Color3.fromRGB(80, 50, 30), Enum.Material.Wood)
			fire:SetAttribute("HB_Settle", 0)
			Instance.new("Fire").Parent = fire
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 170, 90)
			light.Range = 24
			light.Parent = fire
			billboard(fire, "CAMP: refuge", 6, 160)

			local tent = Instance.new("WedgePart")
			tent.Name = "Tent"
			tent.Anchored = true
			tent.CanCollide = false
			tent.Size = Vector3.new(6, 5, 7)
			tent.CFrame = radialCFrame(campPos + Vector3.new(4, 2.5, 4), angle)
			tent.Color = Color3.fromRGB(170, 120, 80)
			tent.Material = Enum.Material.Fabric
			tent:SetAttribute("HB_Settle", 0)
			tent.Parent = folder
		end
	end
end

local function buildPlot(map: Model, index: number)
	local angle = (index - 1) / Config.Plots.Count * 2 * math.pi
	local center = polar(Config.Plots.Radius, angle, RIM_Y)
	-- Local -Z faces the pit.
	local plotCF = CFrame.lookAt(center, Vector3.new(CENTER.X, RIM_Y, CENTER.Z))
	local function at(x: number, y: number, z: number): CFrame
		return plotCF * CFrame.new(x, y, z)
	end
	local size = Config.Plots.Size

	local plot = Instance.new("Model")
	plot.Name = "Plot" .. index
	plot:SetAttribute("PlotIndex", index)
	-- Keep the plot and its rope loaded for clients deep in the Hollow.
	plot.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	-- Grassy cliff-top ground; the plot colour shows on the display rug (DevBase).
	local floor = part(plot, "Floor", Vector3.new(size, 1, size), at(0, 0.5, 0), Color3.fromRGB(96, 138, 68), Enum.Material.Grass)
	plot.PrimaryPart = floor

	local stand = part(plot, "Stand", Vector3.new(4, 1, 4), at(0, 1.5, -10), Color3.new(1, 1, 1))
	hidden(stand)

	-- Rope rig: the winch at the edge and the crane arm reaching over the pit. DevBase adds
	-- the crane frame, pulleys, and gear around these.
	local reach = Config.Plots.Radius - H.RopeRadius
	part(plot, "RopeMount", Vector3.new(4, 3, 2), at(0, 2.5, -22), Color3.fromRGB(110, 80, 50), Enum.Material.WoodPlanks)
	local arm = part(plot, "Arm", Vector3.new(1.5, 1.5, reach - 23), at(0, 12.5, -(25 + reach) / 2 + 0.5), Color3.fromRGB(120, 86, 56), Enum.Material.Wood)
	arm.CanCollide = false
	part(plot, "RopeAnchor", Vector3.new(1.2, 1.2, 1.2), at(0, 11.5, -reach), Color3.fromRGB(90, 70, 55), Enum.Material.CorrodedMetal)

	-- Registry desk: a timber booth with a glowing ledger screen and a small roof.
	local terminal = part(plot, "Terminal", Vector3.new(4, 7, 2), at(-18, 4.5, -12), Color3.fromRGB(110, 78, 50), Enum.Material.WoodPlanks)
	part(plot, "TerminalScreen", Vector3.new(3, 2, 0.2), at(-18, 6, -13.1), Color3.fromRGB(120, 255, 230), Enum.Material.Neon)
	part(plot, "TerminalRoof", Vector3.new(5.5, 0.5, 3.6), at(-18, 8.3, -12.6) * CFrame.Angles(-0.25, 0, 0), Color3.fromRGB(64, 130, 128), Enum.Material.Slate)
	CollectionService:AddTag(terminal, Tags.RegistrationTerminal)
	billboard(terminal, "Registry Terminal", 6, 180)

	local boards = {
		{ name = "UpgradeRopeLength", label = "Rope length", z = -16, color = Color3.fromRGB(200, 150, 80) },
		{ name = "UpgradeRopeSpeed", label = "Climb speed", z = -9, color = Color3.fromRGB(90, 170, 220) },
		{ name = "UpgradeBaseSlots", label = "Display slots", z = -2, color = Color3.fromRGB(160, 110, 210) },
	}
	for _, board in boards do
		-- Timber notice board with a coloured banner, so each upgrade keeps its colour.
		-- Wide enough for the clickable upgrade panel on its inner face (client UpgradeBoards).
		-- Raised on two legs so the panel sits clear of the grass.
		local p = part(plot, board.name, Vector3.new(1, 4.6, 6.2), at(18, BOARD_Y, board.z), Color3.fromRGB(140, 104, 68), Enum.Material.WoodPlanks)
		local banner = part(plot, board.name .. "Banner", Vector3.new(1.2, 0.8, 6.4), at(18, BOARD_Y + 2.7, board.z), board.color:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.SmoothPlastic)
		banner.CastShadow = false
		for _, side in { -2.6, 2.6 } do
			local legHeight = BOARD_Y - 2.3 - 1
			part(plot, board.name .. "Leg", Vector3.new(0.6, legHeight, 0.6), at(18.2, 1 + legHeight / 2, board.z + side), Color3.fromRGB(90, 64, 42), Enum.Material.Wood)
		end
		billboard(p, board.label, 4, 150)
	end

	-- Rows of five on the deck; a shorter last row is centred.
	local columns = { -16, -8, 0, 8, 16 }
	local rows = math.ceil(Config.Base.PedestalCount / #columns)
	for slot = 1, Config.Base.PedestalCount do
		local row = math.floor((slot - 1) / #columns)
		local inRow = math.min(#columns, Config.Base.PedestalCount - row * #columns)
		local x = ((slot - 1) % #columns - (inRow - 1) / 2) * 8
		local z = 4 + row * (16 / math.max(rows - 1, 1))
		-- Stone pedestal with a softly lit top plate (BaseManager fades both when locked).
		local pedestalPart = part(plot, "Pedestal" .. slot, Vector3.new(2.6, 3, 2.6), at(x, 2.5, z), Color3.fromRGB(176, 172, 162), Enum.Material.Slate)
		local glow = part(pedestalPart, "Glow", Vector3.new(2.2, 0.2, 2.2), at(x, 4.05, z), Color3.fromRGB(70, 110, 125), Enum.Material.Neon)
		glow.CanCollide = false
		glow.CanQuery = false
		part(pedestalPart, "Base", Vector3.new(3.2, 0.6, 3.2), at(x, 1.3, z), Color3.fromRGB(150, 146, 138), Enum.Material.Slate)
	end

	local sign = part(plot, "Sign", Vector3.new(6, 1.6, 0.4), at(0, 3.2, size / 2 - 2), Color3.fromRGB(150, 110, 70), Enum.Material.WoodPlanks)
	for _, x in { -2.6, 2.6 } do
		part(plot, "SignPost", Vector3.new(0.5, 3.4, 0.5), at(x, 2.2, size / 2 - 2), Color3.fromRGB(90, 64, 42), Enum.Material.Wood)
	end
	billboard(sign, `Plot {index}: vacant`, 9, 260)

	CollectionService:AddTag(plot, Tags.Plot)
	plot.Parent = map
	DevBase.dress(map, at, index, PLOT_COLORS[(index - 1) % #PLOT_COLORS + 1])
end

local function build(): Model
	local map = Instance.new("Model")
	map.Name = MAP_NAME

	buildHollow(map)
	for index = 1, Config.Plots.Count do
		buildPlot(map, index)
	end
	DevDecor.build(map, CENTER)
	DevBackdrop.build(map, CENTER)

	map.Parent = workspace
	return map
end

-- Warm, hazy late-afternoon light like the base reference image. Studio only, and
-- only with Config.Dev.SurfaceLighting. Each layer's own mood is applied on top by the
-- client (LayerEffects), which restores this surface look when you climb out.
local function applySurfaceLighting()
	if not Config.Dev.SurfaceLighting then
		return
	end
	Lighting.ClockTime = 16.2
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(96, 88, 78)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 138, 120)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 224, 180)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.6

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.24 -- light enough to see the mountain ring
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(226, 214, 192)
	atmosphere.Decay = Color3.fromRGB(150, 130, 105)
	atmosphere.Glare = 0.5
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting

	if not Lighting:FindFirstChild("HB_SunRays") then
		local rays = Instance.new("SunRaysEffect")
		rays.Name = "HB_SunRays"
		rays.Intensity = 0.07
		rays.Spread = 0.6
		rays.Parent = Lighting
	end
	if not Lighting:FindFirstChild("HB_Bloom") then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "HB_Bloom"
		bloom.Intensity = 0.4
		bloom.Size = 30
		bloom.Threshold = 1.6
		bloom.Parent = Lighting
	end
end

-- Moves parts marked HB_Settle (a number) so their bottom sits that many studs above
-- the real ground. Runs after the terrain exists; the attribute is removed so a baked
-- map is not moved twice.
local function settle(map: Instance?)
	if not map then
		return
	end
	for _, item in map:GetDescendants() do
		local offset = item:GetAttribute("HB_Settle")
		if typeof(offset) ~= "number" or not item:IsA("BasePart") then
			continue
		end
		local groundY = Ground.below(item.Position)
		if groundY then
			local bottom = item.Position.Y - item.Size.Y / 2
			item.CFrame += Vector3.new(0, groundY + offset - bottom, 0)
		end
		item:SetAttribute("HB_Settle", nil)
	end
end

function DevMap.ensure()
	applySurfaceLighting()
	local map = workspace:FindFirstChild(MAP_NAME)
	if not map then
		if #CollectionService:GetTagged(Tags.HollowRim) > 0 then
			print("[Hollowbound] Hand-built map detected; skipping placeholder map.")
			return
		end
		local started = os.clock()
		build()
		print(string.format("[Hollowbound] Built dev map parts in %.2fs: %d plots at Y=%d.", os.clock() - started, Config.Plots.Count, RIM_Y))
	end

	-- Terrain is scenery: if it fails, warn and let the rest of the server start.
	local ok, err = pcall(function()
		if not DevTerrain.exists(CENTER) then
			local started = os.clock()
			DevTerrain.build(CENTER)
			print(string.format("[Hollowbound] Built dev map terrain in %.2fs: island, sea, %d-layer Hollow.", os.clock() - started, #Config.Layers))
		end
	end)
	if not ok then
		warn("[Hollowbound] Dev map terrain failed: " .. tostring(err))
	end
	settle(workspace:FindFirstChild(MAP_NAME))
end

return DevMap
