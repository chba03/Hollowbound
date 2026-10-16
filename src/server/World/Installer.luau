--[[
	Installs the vertical world into the place in EDIT mode, so it is visible in Studio,
	saved with the place, and never rebuilt at runtime.

	Studio Command Bar (View > Command Bar), with Rojo connected, exactly one line:

	    require(game:GetService("ServerScriptService").HollowboundServer.World.Installer:Clone()).install()

	(":Clone()" makes Studio load the newest code instead of a cached copy.) Then save the
	place. Other entry points with the same pattern: .uninstall(), .restoreLighting(),
	.report() (validate without changing anything).

	What it does (idempotent; running it again gives the same result):
	  - Workspace.HollowboundWorld (Model) holds the world. Children marked with the
	    attribute HB_Generated are removed and rebuilt; nothing else is touched.
	  - Workspace.HollowboundWorld.AuthoredDecor (Folder) is created once and never changed:
	    put hand-made decorations there and they survive every reinstall.
	  - Nothing outside HollowboundWorld is modified, except Lighting when
	    Config.World.ApplyLightingPreset is on: the first install saves the previous Lighting
	    properties and any Atmosphere into Lighting.HollowboundLightingBackup; reinstalls
	    keep that first backup; restoreLighting() puts everything back.
	  - Global Terrain is never written. Workspace is never cleared.
	  - Reports plan problems (World/Validate) and parts outside the world that block the
	    shaft, and warns about FallenPartsDestroyHeight. It changes neither.

	Also usable from tests: Installer.installInto(deps) with an explicit workspace, lighting,
	config, layout, planner, and validate (see Tests/WorldTests).
]]

local Installer = {}

local GENERATED = "HB_Generated"
local BACKUP_NAME = "HollowboundLightingBackup"
local EFFECTS = { Atmosphere = "HB_Atmosphere", BloomEffect = "HB_Bloom", ColorCorrectionEffect = "HB_ColorCorrection", SunRaysEffect = "HB_SunRays" }

local function rgb(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function colorOf(value, palette)
	if typeof(value) == "string" then
		local entry = palette[value]
		assert(entry, "Unknown palette color " .. value)
		return rgb(entry)
	end
	return rgb(value)
end

-- Converts a plan property value into a Roblox value.
local function convert(value)
	if typeof(value) ~= "table" then
		return value
	end
	if value.rgb then
		return rgb(value.rgb)
	elseif value.udim2 then
		local u = value.udim2
		return UDim2.new(u[1], u[2], u[3], u[4])
	elseif value.v3 then
		return Vector3.new(value.v3[1], value.v3[2], value.v3[3])
	elseif value.v2 then
		return Vector2.new(value.v2[1], value.v2[2])
	elseif value.enum then
		return (Enum :: any)[value.enum][value.name]
	elseif value.font then
		return Font.fromEnum((Enum.Font :: any)[value.font])
	elseif value.nrange then
		return NumberRange.new(value.nrange[1], value.nrange[2])
	elseif value.nseq then
		return NumberSequence.new(value.nseq[1], value.nseq[2])
	elseif value.cseq then
		return ColorSequence.new(rgb(value.cseq))
	end
	error("Unsupported plan property value")
end

local function addExtras(parent: Instance, extras)
	for _, extra in extras or {} do
		local instance = Instance.new(extra.class)
		for property, value in extra.props or {} do
			(instance :: any)[property] = convert(value)
		end
		addExtras(instance, extra.children)
		instance.Parent = parent
	end
end

local function buildPart(spec, origin, palette)
	local part = Instance.new(spec.class)
	part.Name = spec.name
	part.Anchored = true
	part.Size = Vector3.new(spec.size.X, spec.size.Y, spec.size.Z)
	part.CFrame = CFrame.new(origin.X + spec.pos.X, origin.Y + spec.pos.Y, origin.Z + spec.pos.Z)
		* CFrame.fromOrientation(math.rad(spec.rot.x or 0), math.rad(spec.rot.y or 0), math.rad(spec.rot.z or 0))
	part.Material = (Enum.Material :: any)[spec.material]
	part.Color = colorOf(spec.color or "PaleStone", palette)
	part.Transparency = spec.transparency
	part.CanCollide = spec.collide
	part.CanQuery = spec.query
	part.CanTouch = spec.touch
	part.CastShadow = spec.shadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if spec.shape then
		(part :: any).Shape = (Enum.PartType :: any)[spec.shape]
	end
	for property, value in spec.props or {} do
		(part :: any)[property] = convert(value)
	end
	for key, value in spec.attrs or {} do
		part:SetAttribute(key, value)
	end
	for _, tag in spec.tags or {} do
		part:AddTag(tag)
	end
	addExtras(part, spec.extras)
	return part
end

-- Lighting ---------------------------------------------------------------------------------------

local LIGHTING_PROPERTIES = {
	"ClockTime",
	"GeographicLatitude",
	"Brightness",
	"Ambient",
	"OutdoorAmbient",
	"ColorShift_Top",
	"ColorShift_Bottom",
	"EnvironmentDiffuseScale",
	"EnvironmentSpecularScale",
	"ExposureCompensation",
	"GlobalShadows",
}

function Installer.applyLighting(lighting: Instance, preset)
	local backup = lighting:FindFirstChild(BACKUP_NAME)
	if not backup then
		backup = Instance.new("Configuration")
		backup.Name = BACKUP_NAME
		for _, property in LIGHTING_PROPERTIES do
			local ok, value = pcall(function()
				return (lighting :: any)[property]
			end)
			if ok and value ~= nil then
				backup:SetAttribute(property, value)
			end
		end
		-- Only one Atmosphere can be active: keep any existing one safe in the backup.
		for _, child in lighting:GetChildren() do
			if child.ClassName == "Atmosphere" and child.Name ~= EFFECTS.Atmosphere then
				child.Parent = backup
			end
		end
		backup.Parent = lighting
	end
	for property, value in preset.Lighting do
		(lighting :: any)[property] = if typeof(value) == "table" then rgb(value) else value
	end
	local sections = { Atmosphere = preset.Atmosphere, BloomEffect = preset.Bloom, ColorCorrectionEffect = preset.ColorCorrection, SunRaysEffect = preset.SunRays }
	for className, values in sections do
		local name = EFFECTS[className]
		local effect = lighting:FindFirstChild(name)
		if not effect then
			effect = Instance.new(className)
			effect.Name = name
			effect.Parent = lighting
		end
		for property, value in values do
			(effect :: any)[property] = if typeof(value) == "table" then rgb(value) else value
		end
	end
end

function Installer.restoreLightingIn(lighting: Instance): boolean
	local backup = lighting:FindFirstChild(BACKUP_NAME)
	for _, name in EFFECTS do
		local effect = lighting:FindFirstChild(name)
		if effect then
			effect:Destroy()
		end
	end
	if not backup then
		return false
	end
	for _, property in LIGHTING_PROPERTIES do
		local value = backup:GetAttribute(property)
		if value ~= nil then
			(lighting :: any)[property] = value
		end
	end
	for _, child in backup:GetChildren() do
		child.Parent = lighting
	end
	backup:Destroy()
	return true
end

-- Install ---------------------------------------------------------------------------------------

--[[
	deps = {
		workspace, lighting, config (Config table), layout, planner, validate,
		log = (string) -> (), warn = (string) -> (),
		fallenPartsDestroyHeight = number?, scanBlockers = boolean?,
	}
	Returns a report { parts, groups, problems, blockers, preservedAuthored }.
]]
function Installer.installInto(deps)
	local log = deps.log or print
	local warnFn = deps.warn or warn
	local config = deps.config
	local worldConfig = config.World
	local plan = deps.planner.plan(deps.layout, worldConfig)
	local problems = deps.validate.check(plan, worldConfig, {
		fallenPartsDestroyHeight = deps.fallenPartsDestroyHeight,
		leash = { Regular = config.Creatures.Variants.Regular.leashRadius, Guardian = config.Creatures.Variants.Guardian.leashRadius },
	})
	for _, problem in problems do
		warnFn("[Hollowbound] World plan problem: " .. problem)
	end

	local root = deps.workspace:FindFirstChild(worldConfig.ModelName)
	if root and not root:IsA("Model") then
		error(`Workspace.{worldConfig.ModelName} exists but is not a Model; rename it first`)
	end
	if not root then
		root = Instance.new("Model")
		root.Name = worldConfig.ModelName
		root.Parent = deps.workspace
	end
	local authored = root:FindFirstChild(worldConfig.AuthoredFolderName)
	if not authored then
		authored = Instance.new("Folder")
		authored.Name = worldConfig.AuthoredFolderName
		authored.Parent = root
	end
	local preservedAuthored = #authored:GetDescendants()

	-- Remove only what a previous install generated.
	for _, child in root:GetChildren() do
		if child:GetAttribute(GENERATED) then
			child:Destroy()
		end
	end

	local origin = worldConfig.Origin
	local palette = worldConfig.Palette
	local count = 0
	for _, groupName in plan.groupOrder do
		local model = Instance.new("Model")
		model.Name = groupName
		model:SetAttribute(GENERATED, true)
		for _, spec in plan.groups[groupName].parts do
			buildPart(spec, origin, palette).Parent = model
			count += 1
		end
		model.Parent = root
	end
	root:SetAttribute("HB_LayoutVersion", worldConfig.LayoutVersion)
	root:SetAttribute("HB_OriginX", origin.X)
	root:SetAttribute("HB_OriginY", origin.Y)
	root:SetAttribute("HB_OriginZ", origin.Z)
	root:SetAttribute("HB_CampDepth", plan.info.campDepth)
	root:SetAttribute("HB_Parts", count)

	if worldConfig.ApplyLightingPreset and deps.lighting then
		Installer.applyLighting(deps.lighting, worldConfig.LightingPresets[worldConfig.LightingPreset])
	end

	-- Parts outside the world that would block the shaft (for example a Baseplate).
	local blockers = {}
	if deps.scanBlockers then
		local opening = worldConfig.OpeningRadius
		local top, bottom = origin.Y - 2, origin.Y - worldConfig.KillDepth
		for _, descendant in deps.workspace:GetDescendants() do
			if descendant:IsA("BasePart") and not descendant:IsDescendantOf(root) and descendant.CanCollide then
				local p = descendant.Position
				local reach = descendant.Size.Magnitude / 2
				local flat = math.sqrt((p.X - origin.X) ^ 2 + (p.Z - origin.Z) ^ 2)
				if flat - reach < opening and p.Y + reach > bottom and p.Y - reach < top then
					table.insert(blockers, descendant:GetFullName())
				end
			end
		end
		for _, name in blockers do
			warnFn("[Hollowbound] Part outside the world may block the shaft: " .. name)
		end
	end

	log(`[Hollowbound] World installed: {count} parts in {#plan.groupOrder} groups, camp depth {plan.info.campDepth}, {#problems} plan problem(s), {#blockers} shaft blocker(s); {preservedAuthored} authored item(s) kept.`)
	return { parts = count, groups = #plan.groupOrder, problems = problems, blockers = blockers, preservedAuthored = preservedAuthored, root = root }
end

function Installer.uninstallFrom(workspaceRoot: Instance, worldConfig): number
	local root = workspaceRoot:FindFirstChild(worldConfig.ModelName)
	if not root then
		return 0
	end
	local removed = 0
	for _, child in root:GetChildren() do
		if child:GetAttribute(GENERATED) then
			child:Destroy()
			removed += 1
		end
	end
	return removed
end

-- Studio entry points (fresh copies of the synced modules each run) ------------------------------

local function freshDeps()
	local serverFolder = game:GetService("ServerScriptService"):FindFirstChild("HollowboundServer")
	assert(serverFolder, "ServerScriptService.HollowboundServer not found: connect Rojo first")
	local worldFolder = serverFolder:WaitForChild("World"):Clone()
	local shared = game:GetService("ReplicatedStorage"):FindFirstChild("HollowboundShared")
	assert(shared, "ReplicatedStorage.HollowboundShared not found: connect Rojo first")
	return {
		workspace = workspace,
		lighting = game:GetService("Lighting"),
		config = require(shared.Config:Clone()),
		layout = require(worldFolder.Layout),
		planner = require(worldFolder.Planner),
		validate = require(worldFolder.Validate),
		fallenPartsDestroyHeight = workspace.FallenPartsDestroyHeight,
		scanBlockers = true,
	}
end

function Installer.install()
	assert(not game:GetService("RunService"):IsRunning(), "Run the installer in edit mode, not during Play")
	local deps = freshDeps()
	local report = Installer.installInto(deps)
	if #report.problems == 0 and #report.blockers == 0 then
		print("[Hollowbound] Install OK. Now save the place (File > Save).")
	else
		warn("[Hollowbound] Installed with warnings (see above). Fix them, re-run, then save the place.")
	end
	return report
end

function Installer.uninstall()
	assert(not game:GetService("RunService"):IsRunning(), "Run the installer in edit mode, not during Play")
	local deps = freshDeps()
	local removed = Installer.uninstallFrom(deps.workspace, deps.config.World)
	print(`[Hollowbound] Removed {removed} generated group(s); AuthoredDecor and everything else were kept.`)
	return removed
end

function Installer.restoreLighting()
	local restored = Installer.restoreLightingIn(game:GetService("Lighting"))
	print(if restored then "[Hollowbound] Lighting restored from HollowboundLightingBackup." else "[Hollowbound] No lighting backup found; removed HB_ effects only.")
	return restored
end

-- Validate the plan and scan for blockers without changing the place.
function Installer.report()
	local deps = freshDeps()
	local plan = deps.planner.plan(deps.layout, deps.config.World)
	local problems = deps.validate.check(plan, deps.config.World, {
		fallenPartsDestroyHeight = deps.fallenPartsDestroyHeight,
		leash = { Regular = deps.config.Creatures.Variants.Regular.leashRadius, Guardian = deps.config.Creatures.Variants.Guardian.leashRadius },
	})
	local stats = deps.planner.stats(plan)
	print(`[Hollowbound] World plan: {stats.parts} parts, {stats.groups} groups, {stats.lights} lights, {#problems} problem(s).`)
	for _, problem in problems do
		warn("[Hollowbound] " .. problem)
	end
	return problems
end

return Installer
