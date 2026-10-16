--[[
	Milestone 5 world checks: plan validity and determinism, geometry against real CFrame
	math, three-dimensional zones, and installation into an ISOLATED workspace (never the
	real one): no duplicates on reinstall, authored decorations and unrelated models kept,
	lighting backup and restore (Lune only, where a separate Lighting can be created).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Geometry = require(Server.World.Geometry)
local Installer = require(Server.World.Installer)
local Layout = require(Server.World.Layout)
local Planner = require(Server.World.Planner)
local Validate = require(Server.World.Validate)
local TestKit = require(script.Parent.TestKit)

local function countTagged(root: Instance, tag: string): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:HasTag(tag) then
			n += 1
		end
	end
	return n
end

return function()
	local t = TestKit.suite("World")
	local check = t.check
	local world = Config.World
	local leash = { Regular = Config.Creatures.Variants.Regular.leashRadius, Guardian = Config.Creatures.Variants.Guardian.leashRadius }

	-- Plan validity and determinism.
	local plan = Planner.plan(Layout, world)
	local problems = Validate.check(plan, world, { fallenPartsDestroyHeight = -500, leash = leash })
	for _, problem in problems do
		warn("    world plan: " .. problem)
	end
	check(#problems == 0, "the world plan passes every validation check")
	local again = Planner.plan(Layout, world)
	local s1, s2 = Planner.stats(plan), Planner.stats(again)
	check(s1.parts == s2.parts and s1.parts > 500, "the plan is deterministic and non-trivial")
	local a1 = plan.groups[plan.groupOrder[1]].parts[1].pos
	local a2 = again.groups[again.groupOrder[1]].parts[1].pos
	check(a1.X == a2.X and a1.Y == a2.Y and a1.Z == a2.Z, "the same layout gives the same positions")
	check(s1.lights <= 24, "the world keeps a small light budget")

	-- Geometry matches Roblox CFrame math (fromOrientation order).
	local worst = 0
	for _, angles in { { 30, 0, 0 }, { 0, 45, 0 }, { 10, -70, 25 }, { -35, 160, 90 } } do
		local p = Geometry.v(1.5, -2, 3.25)
		local mine = Geometry.rotate(p, angles[1], angles[2], angles[3])
		local cf = CFrame.fromOrientation(math.rad(angles[1]), math.rad(angles[2]), math.rad(angles[3]))
		local theirs = cf * Vector3.new(p.X, p.Y, p.Z)
		worst = math.max(worst, math.abs(mine.X - theirs.X), math.abs(mine.Y - theirs.Y), math.abs(mine.Z - theirs.Z))
		local back = Geometry.unrotate(mine, angles[1], angles[2], angles[3])
		worst = math.max(worst, math.abs(back.X - p.X), math.abs(back.Y - p.Y), math.abs(back.Z - p.Z))
	end
	check(worst < 1e-6, "pure rotations match CFrame.fromOrientation")
	local yaw = Geometry.yawFacing(1, 0)
	local look = CFrame.fromOrientation(0, math.rad(yaw), 0).LookVector
	check(math.abs(look.X - 1) < 1e-6 and math.abs(look.Z) < 1e-6, "yawFacing points a part's front where intended")

	-- Three-dimensional zones (beyond the validator's own checks).
	local townZones, campZones = Validate.tagged(plan, "HB_TownZone"), Validate.tagged(plan, "HB_CampZone")
	local terminal = Validate.tagged(plan, "HB_RegistrationTerminal")[1]
	check(Validate.zoneContains(townZones, Geometry.add(terminal.pos, Geometry.v(0, 1, 0))), "beside the terminal is town")
	check(not Validate.zoneContains(townZones, Geometry.add(terminal.pos, Geometry.v(0, -12, 0))), "under the terminal (through the floor) is not town")
	check(not Validate.zoneContains(townZones, Geometry.v(0, -40, 0)), "the open shaft below town is not town")
	check(not Validate.zoneContains(townZones, Geometry.polar(world.OpeningRadius - 15, 70, -6)), "a ledge just below the rim is not town")
	check(Validate.zoneContains(townZones, Geometry.polar(world.TownOuterRadius - 10, 135, 3)), "walking behind the lodges is still town")
	local camp = campZones[1]
	check(Validate.zoneContains(campZones, Geometry.v(camp.pos.X, -plan.info.campDepth + 3, camp.pos.Z)), "standing in camp is camp")
	check(not Validate.zoneContains(campZones, Geometry.v(camp.pos.X, -plan.info.campDepth - 10, camp.pos.Z)), "beneath the camp shelf is not camp")
	check(not Validate.zoneContains(campZones, Geometry.v(camp.pos.X, -plan.info.campDepth + 40, camp.pos.Z)), "far above the camp is not camp")

	-- Installation into an isolated workspace.
	local okModel, fakeWorkspace = pcall(function()
		return Instance.new("Folder")
	end)
	if not okModel then
		check(false, "Instance.new is available for the install test")
		return t
	end
	fakeWorkspace.Name = "TestWorkspace"
	local unrelated = Instance.new("Model")
	unrelated.Name = "SomeoneElsesModel"
	local unrelatedPart = Instance.new("Part")
	unrelatedPart.Name = "Keep"
	unrelatedPart.Parent = unrelated
	unrelated.Parent = fakeWorkspace

	local deps = {
		workspace = fakeWorkspace,
		lighting = nil,
		config = Config,
		layout = Layout,
		planner = Planner,
		validate = Validate,
		log = function() end,
		warn = function() end,
		fallenPartsDestroyHeight = -500,
	}
	-- Lighting only where a separate Lighting can exist (Lune); never the real one.
	local dataModel = nil
	pcall(function()
		dataModel = Instance.new("DataModel")
	end)
	local lighting = dataModel and dataModel:GetService("Lighting")
	if lighting then
		deps.lighting = lighting
		lighting.ClockTime = 9
		local mine = Instance.new("Atmosphere")
		mine.Name = "MyAtmosphere"
		mine.Density = 0.1
		mine.Parent = lighting
	end

	local first = Installer.installInto(deps)
	local root = fakeWorkspace:FindFirstChild(world.ModelName)
	check(root ~= nil and first.parts == s1.parts and #first.problems == 0, "install builds the whole planned world")
	local authored = root:FindFirstChild(world.AuthoredFolderName)
	local decorationPart = Instance.new("Part")
	decorationPart.Name = "HandMadeStatue"
	decorationPart.Parent = authored
	local descendantsAfterFirst = #root:GetDescendants()
	local spawnsAfterFirst = countTagged(root, "HB_TownSpawn")

	local second = Installer.installInto(deps)
	check(second.parts == first.parts, "a reinstall builds the same number of parts")
	check(#root:GetDescendants() == descendantsAfterFirst, "a reinstall leaves no duplicates")
	check(countTagged(root, "HB_TownSpawn") == 1 and spawnsAfterFirst == 1, "exactly one town spawn after reinstalling")
	check(countTagged(root, "HB_RegistrationTerminal") == 1 and countTagged(root, "HB_CreatureSpawn") == 3, "services and dens are not duplicated")
	check(decorationPart.Parent == authored and authored.Parent == root, "authored decorations survive a reinstall")
	check(second.preservedAuthored == 1, "the installer reports the kept authored item")
	check(unrelatedPart.Parent == unrelated and unrelated.Parent == fakeWorkspace, "unrelated models are untouched")
	local worldRoots = 0
	for _, child in fakeWorkspace:GetChildren() do
		if child.Name == world.ModelName then
			worldRoots += 1
		end
	end
	check(worldRoots == 1, "there is one world model")

	if lighting then
		local backups = 0
		for _, child in lighting:GetChildren() do
			if child.Name == "HollowboundLightingBackup" then
				backups += 1
			end
		end
		check(backups == 1, "one lighting backup after two installs")
		check(math.abs(lighting.ClockTime - world.LightingPresets[world.LightingPreset].Lighting.ClockTime) < 1e-3, "the lighting preset is applied")
		check(lighting:FindFirstChild("MyAtmosphere") == nil and lighting:FindFirstChild("HB_Atmosphere") ~= nil, "the existing Atmosphere is set aside, not deleted")
		check(Installer.restoreLightingIn(lighting) == true, "lighting can be restored")
		check(math.abs(lighting.ClockTime - 9) < 1e-3 and lighting:FindFirstChild("MyAtmosphere") ~= nil, "restore brings back the original lighting and Atmosphere")
		check(lighting:FindFirstChild("HB_Atmosphere") == nil and lighting:FindFirstChild("HollowboundLightingBackup") == nil, "restore removes the preset effects and the backup")
	end

	local removed = Installer.uninstallFrom(fakeWorkspace, world)
	check(removed == first.groups and authored.Parent == root and decorationPart.Parent == authored, "uninstall removes generated groups only")
	fakeWorkspace:Destroy()
	return t
end
