--[[
	Which world is active, and facts about it at runtime (milestone 5). Server only.

	resolve() runs once at startup, before any service binds:
	  - Config.World.Mode = "Vertical" and Workspace.HollowboundWorld is installed (it has
	    the HB_LayoutVersion attribute): the vertical world is active.
	  - "Vertical" but not installed: in Studio with LegacyFallbackInStudio, the legacy
	    runtime dev map is used instead, with a loud warning. Otherwise nothing is bound
	    and an error is logged (a live server must have the world saved in the place).
	  - "Legacy": the milestone 1-4 dev map and fixtures.
	The installed world is never rebuilt here.

	Depth is measured from the installed origin (the rim surface), only inside the world's
	bounds, so places outside the world never get a depth or region.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Markers = require(script.Parent.Markers)

local WorldInfo = {}

local mode = "Legacy"
local root: Model? = nil
local origin = Vector3.new(Config.World.Origin.X, Config.World.Origin.Y, Config.World.Origin.Z)

function WorldInfo.resolve(): string
	local cfg = Config.World
	local candidate = workspace:FindFirstChild(cfg.ModelName)
	local installed = candidate ~= nil and candidate:IsA("Model") and candidate:GetAttribute("HB_LayoutVersion") ~= nil
	if cfg.Mode == "Vertical" and installed then
		mode = "Vertical"
		root = candidate :: Model
		local x, y, z = candidate:GetAttribute("HB_OriginX"), candidate:GetAttribute("HB_OriginY"), candidate:GetAttribute("HB_OriginZ")
		if typeof(x) == "number" and typeof(y) == "number" and typeof(z) == "number" then
			origin = Vector3.new(x, y, z)
			if (origin - Vector3.new(cfg.Origin.X, cfg.Origin.Y, cfg.Origin.Z)).Magnitude > 0.01 then
				warn("[Hollowbound] The installed world's origin differs from Config.World.Origin. Re-run the installer to match.")
			end
		end
		if candidate:GetAttribute("HB_LayoutVersion") ~= cfg.LayoutVersion then
			warn(`[Hollowbound] Installed world layout {candidate:GetAttribute("HB_LayoutVersion")} differs from {cfg.LayoutVersion}. Re-run the installer and save the place.`)
		end
	elseif cfg.Mode == "Vertical" then
		if RunService:IsStudio() and cfg.LegacyFallbackInStudio then
			mode = "Legacy"
			warn("[Hollowbound] The vertical world is not installed in this place. Using the LEGACY dev map for this Studio test. Install it with the command in README (World installation), then save the place.")
		else
			mode = "Vertical"
			warn("[Hollowbound] Config.World.Mode is Vertical but Workspace." .. cfg.ModelName .. " is not installed; no world markers are available.")
		end
	else
		mode = "Legacy"
	end
	Markers.setScope(mode, root)
	print(`[Hollowbound] World mode: {mode}{if root then " (installed " .. tostring(root:GetAttribute("HB_LayoutVersion")) .. ")" else ""}`)
	return mode
end

function WorldInfo.mode(): string
	return mode
end

function WorldInfo.root(): Model?
	return root
end

function WorldInfo.origin(): Vector3
	return origin
end

local function inBounds(position: Vector3): boolean
	if mode ~= "Vertical" or not root then
		return false
	end
	local flat = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z).Magnitude
	return flat <= Config.World.BoundaryRadius + 80 and position.Y <= origin.Y + 250 and position.Y >= origin.Y - Config.World.KillDepth - 200
end

-- Studs below the rim surface (0 or more), or nil outside the vertical world.
function WorldInfo.depthAt(position: Vector3): number?
	if not inBounds(position) then
		return nil
	end
	return math.max(0, origin.Y - position.Y)
end

-- The absolute Y of the kill plane, or nil when not in the vertical world.
function WorldInfo.killY(): number?
	if mode ~= "Vertical" or not root then
		return nil
	end
	return origin.Y - Config.World.KillDepth
end

-- True if the position is inside the world's footprint and below the kill plane: the
-- character has fallen into the dark (or past the floor) and is lost.
function WorldInfo.belowKillPlane(position: Vector3): boolean
	local killY = WorldInfo.killY()
	if not killY then
		return false
	end
	local flat = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z).Magnitude
	return flat <= Config.World.BoundaryRadius + 200 and position.Y < killY
end

-- Readable place name for the HUD: town and camp first, then named regions, then the
-- depth band. Never exposes coordinates.
function WorldInfo.regionAt(position: Vector3, zone: string): string?
	if zone == "Town" then
		return "Rim Town"
	end
	local depth = WorldInfo.depthAt(position)
	if not depth then
		return if zone == "Camp" then "Camp" else nil
	end
	local best, bestPriority = nil, -math.huge
	for _, marker in Markers.tagged(Config.Tags.Region) do
		if marker:IsA("BasePart") then
			local radius = marker:GetAttribute("Radius") or 0
			local height = marker:GetAttribute("Height") or 0
			local offset = position - marker.Position
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius and math.abs(offset.Y) <= height / 2 then
				local priority = marker:GetAttribute("Priority") or 0
				if priority > bestPriority then
					best, bestPriority = marker:GetAttribute("RegionName"), priority
				end
			end
		end
	end
	if zone == "Camp" then
		return "Mistfall Camp"
	end
	if best then
		return best
	end
	local name = nil
	for _, band in Config.World.DepthBands do
		if depth >= band.from then
			name = band.name
		end
	end
	return name
end

-- Depth for the HUD, in rounded meters (no studs or coordinates).
function WorldInfo.displayDepth(position: Vector3): number?
	local depth = WorldInfo.depthAt(position)
	if not depth or depth < 2 then
		return nil
	end
	return math.floor(depth * Config.World.MetersPerStud / 5 + 0.5) * 5
end

return WorldInfo
