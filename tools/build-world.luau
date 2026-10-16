--[[
	Builds the vertical world OFFLINE with the same installer used in Studio, into an
	isolated DataModel, then:
	  - writes build/HollowboundWorld.rbxm (git-ignored), a model file you can inspect or
	    insert into a place (File > Insert / right-click Workspace > Insert from File);
	  - prints plan problems, part counts, and the absolute coordinates of key markers.

	    lune run tools/build-world

	This never touches a real place. The Studio Command Bar installer remains the way to
	put the world into your place (see README, "World installation").
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local env = {
	Color3 = roblox.Color3,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	UDim2 = roblox.UDim2,
	NumberRange = roblox.NumberRange,
	NumberSequence = roblox.NumberSequence,
	ColorSequence = roblox.ColorSequence,
	Instance = roblox.Instance,
	Enum = roblox.Enum,
	Font = roblox.Font,
	warn = function(...)
		print("WARN", ...)
	end,
}

local loaded = {}
local function load(path: string, scriptStub)
	if loaded[path] then
		return loaded[path]
	end
	local localEnv = table.clone(env)
	localEnv.script = scriptStub
	local result = luau.load(fs.readFile(path), { debugName = path, environment = localEnv })()
	loaded[path] = result
	return result
end

local worldDir = "src/server/World/"
local Geometry = load(worldDir .. "Geometry.luau", {})
local siblings = { Geometry = Geometry }
local folderStub = setmetatable({}, {
	__index = function(_, name)
		return siblings[name]
	end,
})
local function requireStub(module)
	return module
end
env.require = requireStub
local Layout = load(worldDir .. "Layout.luau", {})
local Planner = load(worldDir .. "Planner.luau", { Parent = folderStub })
local Validate = load(worldDir .. "Validate.luau", { Parent = folderStub })
local Installer = load(worldDir .. "Installer.luau", {})
local Config = load("src/shared/Config.luau", {})

local game = roblox.Instance.new("DataModel")
local workspace = game:GetService("Workspace")
local lighting = game:GetService("Lighting")

local report = Installer.installInto({
	workspace = workspace,
	lighting = lighting,
	config = Config,
	layout = Layout,
	planner = Planner,
	validate = Validate,
	fallenPartsDestroyHeight = -500,
})

print(`parts {report.parts}, groups {report.groups}, problems {#report.problems}`)
for _, problem in report.problems do
	print("  PROBLEM " .. problem)
end

local root = report.root
local function at(instance)
	local p = instance.CFrame.Position
	return string.format("(%.0f, %.0f, %.0f)", p.X, p.Y, p.Z)
end
print("key markers (absolute Workspace coordinates):")
for _, descendant in root:GetDescendants() do
	if descendant:IsA("BasePart") then
		local tags = descendant:GetTags()
		local interesting = false
		for _, tag in tags do
			if tag ~= "HB_TownZone" and tag ~= "HB_CampZone" and tag ~= "HB_Region" then
				interesting = true
			end
		end
		if interesting then
			print(string.format("  %-22s %-26s %s", descendant.Name, table.concat(tags, ","), at(descendant)))
		end
	end
end

fs.writeDir("build")
fs.writeFile("build/HollowboundWorld.rbxm", roblox.serializeModel({ root }))
print("wrote build/HollowboundWorld.rbxm")
