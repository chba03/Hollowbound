--[[
	Scoped access to world markers (CollectionService tags) for the active world
	(milestone 5). Server only.

	Vertical mode: only markers inside Workspace.HollowboundWorld count.
	Legacy mode: only markers outside it count (the runtime dev map and fixtures).
	So a place that contains both an installed world and a saved legacy map never binds
	two spawns, two terminals, or two sets of creatures.

	Runtime-created tags (WorldRelic, WorldLoot, Creature) are not scoped: use
	CollectionService directly for those.
]]

local CollectionService = game:GetService("CollectionService")

local Markers = {}

local scopeMode = "Legacy"
local scopeRoot: Instance? = nil

function Markers.setScope(mode: string, root: Instance?)
	scopeMode = mode
	scopeRoot = root
end

-- Pure rule, also used by tests: does `instance` belong to the active world?
function Markers.inScopeFor(instance: Instance, mode: string, root: Instance?): boolean
	if mode == "Vertical" then
		return root ~= nil and instance:IsDescendantOf(root)
	end
	return root == nil or not instance:IsDescendantOf(root)
end

function Markers.inScope(instance: Instance): boolean
	-- In legacy mode, also ignore an installed world that is present but not active.
	local root = scopeRoot
	if scopeMode == "Legacy" and root == nil then
		local candidate = workspace:FindFirstChild("HollowboundWorld")
		root = candidate
	end
	return Markers.inScopeFor(instance, scopeMode, root)
end

function Markers.tagged(tag: string): { Instance }
	local list = {}
	for _, instance in CollectionService:GetTagged(tag) do
		if Markers.inScope(instance) then
			table.insert(list, instance)
		end
	end
	return list
end

-- Calls fn for tagged instances added later (in scope only).
function Markers.onAdded(tag: string, fn: (Instance) -> ())
	return CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
		if Markers.inScope(instance) then
			fn(instance)
		end
	end)
end

return Markers
