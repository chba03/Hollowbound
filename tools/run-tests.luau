--[[
	Runs the automated logic tests (src/server/Tests) outside Roblox Studio with Lune:

	    lune run tools/run-tests

	This is a test harness only. It is outside the Rojo mapping, so it never reaches the
	game. It rebuilds the part of the Rojo instance tree the tests need from src/
	(ReplicatedStorage.HollowboundShared and ServerScriptService.HollowboundServer) and
	provides minimal stand-ins for the few Roblox APIs those modules touch: game:GetService,
	script/Parent/WaitForChild, Random, and warn. Roblox datatypes and detached Instances
	(Vector3, CFrame, Color3, Instance, Enum, ...) come from Lune's @lune/roblox, so the
	world installer can be tested on isolated instance trees. Anything else raises an
	error, so a test that starts depending on more of Roblox fails loudly.

	Storage: the suites use MockBackend (in-memory, test-only). Nothing here can reach
	ProfileStore or a DataStore. Passing here proves the game rules, not Roblox behaviour;
	the Studio and real-persistence checks in docs/TESTING.md are still required.

	Exit code: 0 when every check passes, 1 otherwise.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

-- Minimal Roblox stand-ins -------------------------------------------------------------

local failures = 0
local function warnShim(...)
	local parts = table.pack(...)
	for i = 1, parts.n do
		parts[i] = tostring(parts[i])
	end
	print("WARN " .. table.concat(parts, " ", 1, parts.n))
end

-- Deterministic stand-in for Roblox's Random (not the same sequence as Roblox).
local RandomShim = {}
RandomShim.__index = RandomShim
function RandomShim.new(seed: number?)
	local state = math.floor(seed or os.clock() * 1e6) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return setmetatable({ state = state }, RandomShim)
end
function RandomShim:_next(): number
	self.state = (self.state * 48271) % 2147483647
	return self.state / 2147483647
end
function RandomShim:NextNumber(min: number?, max: number?): number
	local lo, hi = min or 0, max or 1
	return lo + (hi - lo) * self:_next()
end
function RandomShim:NextInteger(min: number, max: number): number
	return min + math.floor(self:_next() * (max - min + 1))
end

local Color3Shim = {}
function Color3Shim.new(r: number?, g: number?, b: number?)
	return { R = r or 0, G = g or 0, B = b or 0 }
end
function Color3Shim.fromRGB(r: number?, g: number?, b: number?)
	return Color3Shim.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

-- Instance tree mirroring default.project.json ------------------------------------------

type Node = { name: string, file: string?, children: { [string]: any }, parent: any }

local nodeMethods = {}
local nodeMeta = {}

local function newNode(name: string, file: string?, parent)
	return setmetatable({ _name = name, _file = file, _children = {}, _parent = parent }, nodeMeta)
end

nodeMeta.__index = function(node, key)
	if key == "Name" then
		return rawget(node, "_name")
	elseif key == "Parent" then
		return rawget(node, "_parent")
	elseif nodeMethods[key] then
		return nodeMethods[key]
	end
	local child = rawget(node, "_children")[key]
	if child == nil then
		error(`{rawget(node, "_name")}.{key} does not exist in the test harness tree`, 2)
	end
	return child
end
nodeMeta.__tostring = function(node)
	return rawget(node, "_name")
end

function nodeMethods.WaitForChild(node, name: string)
	local child = rawget(node, "_children")[name]
	assert(child, `{rawget(node, "_name")}:WaitForChild("{name}") would wait forever`)
	return child
end
function nodeMethods.FindFirstChild(node, name: string)
	return rawget(node, "_children")[name]
end
function nodeMethods.GetFullName(node)
	return rawget(node, "_name")
end

-- Mirrors Rojo: a directory is a Folder, or a script when it has init(.server|.client).luau;
-- name.luau is a ModuleScript (name.server.luau / name.client.luau are scripts).
local function scriptName(fileName: string): string?
	if string.sub(fileName, -5) ~= ".luau" then
		return nil
	end
	local base = string.sub(fileName, 1, -6)
	base = string.gsub(base, "%.server$", "")
	base = string.gsub(base, "%.client$", "")
	return base
end

local function buildDir(name: string, dir: string, parent)
	local initFile
	for _, candidate in { "init.luau", "init.server.luau", "init.client.luau" } do
		if fs.isFile(dir .. "/" .. candidate) then
			initFile = dir .. "/" .. candidate
		end
	end
	local node = newNode(name, initFile, parent)
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			rawget(node, "_children")[entry] = buildDir(entry, path, node)
		elseif not string.match(entry, "^init%.") then
			local childName = scriptName(entry)
			if childName then
				rawget(node, "_children")[childName] = newNode(childName, path, node)
			end
		end
	end
	return node
end

local root = newNode("game", nil, nil)
local replicatedStorage = newNode("ReplicatedStorage", nil, root)
local serverScriptService = newNode("ServerScriptService", nil, root)
rawget(replicatedStorage, "_children").HollowboundShared = buildDir("HollowboundShared", "src/shared", replicatedStorage)
rawget(serverScriptService, "_children").HollowboundServer = buildDir("HollowboundServer", "src/server", serverScriptService)

-- Inert stand-ins so modules that read these services can load; tests never rely on them.
local noSignal = { Connect = function() return { Disconnect = function() end } end }
local services = {
	ReplicatedStorage = replicatedStorage,
	ServerScriptService = serverScriptService,
	CollectionService = {
		GetTagged = function() return {} end,
		GetInstanceAddedSignal = function() return noSignal end,
	},
	Players = { GetPlayers = function() return {} end, PlayerAdded = noSignal, PlayerRemoving = noSignal },
}
local gameShim = setmetatable({}, {
	__index = function(_, key)
		if key == "GetService" then
			return function(_, serviceName: string)
				local service = services[serviceName]
				if not service then
					error(`game:GetService("{serviceName}") is not available in the test harness`, 2)
				end
				return service
			end
		end
		error(`game.{key} is not available in the test harness`, 2)
	end,
})

-- Module loader ------------------------------------------------------------------------

local cache: { [any]: any } = {}
local loading: { [any]: boolean } = {}

local function requireNode(node)
	if cache[node] ~= nil then
		return cache[node]
	end
	local file = rawget(node, "_file")
	assert(file, `{rawget(node, "_name")} is not a script`)
	assert(not loading[node], `circular require of {file}`)
	loading[node] = true

	local chunk = luau.load(fs.readFile(file), {
		debugName = file,
		environment = {
			script = node,
			game = gameShim,
			require = requireNode,
			warn = warnShim,
			Random = RandomShim,
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
		},
	})
	local result = chunk()
	loading[node] = nil
	cache[node] = if result == nil then true else result
	return cache[node]
end

-- Run ----------------------------------------------------------------------------------

local server = rawget(serverScriptService, "_children").HollowboundServer
local SelfTest = requireNode(server.SelfTest)
local passed = SelfTest.run()
if not passed then
	failures += 1
end
process.exit(if failures == 0 then 0 else 1)
