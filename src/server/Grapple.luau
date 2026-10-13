--[[
	The grappling hook (Config.Grapple, project owner). Server side.

	Bought once at the Forge (Arsenal handles the purchase and gives the tool). Using it
	in the Hollow fires the hook at the ledge ring (an "inner circle") just above you and
	hauls you up onto it, for when you fall below the end of your rope.

	One use per BandMeters of depth: the depth is split into bands (0-100 m, 100-200 m,
	...), and each band's grapple is spent once you use it there. Bands come back when
	you return to town or respawn.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Progression = require(Shared:WaitForChild("Progression"))
local Characters = require(script.Parent.Characters)
local Ground = require(script.Parent.Ground)
local Hollow = require(script.Parent.Hollow)
local ServerNet = require(script.Parent.ServerNet)

local Grapple = {}

local H = Config.Hollow
local G = Config.Grapple
local spent: { [Player]: { [number]: boolean } } = {}
local busy: { [Player]: boolean } = {}

-- The deepest ledge top (studs below the rim) that is above `depth` by at least MinRise.
local function ledgeAbove(depth: number): number?
	local best: number? = nil
	for layer = 1, #Config.Layers do
		for _, offset in H.LedgeDepths do
			local ledge = (layer - 1) * H.LayerHeight + offset
			if ledge <= depth - G.MinRise and (best == nil or ledge > best) then
				best = ledge
			end
		end
	end
	return best
end

local function band(depth: number): number
	return math.floor(depth * Config.Display.MetersPerStud / G.BandMeters)
end

-- Fires the hook to `target` and hauls the character there over PullSeconds.
local function haul(player: Player, root: BasePart, target: Vector3)
	local character = player.Character :: Model
	local start = root.Position
	local outward = Vector3.new(target.X - start.X, 0, target.Z - start.Z)
	local facing = if outward.Magnitude > 0.1 then outward.Unit else root.CFrame.LookVector

	-- The hook stuck in the ledge, and the line from it to the climber.
	local hook = Instance.new("Part")
	hook.Name = "HB_GrappleHook"
	hook.Size = Vector3.new(0.6, 0.6, 0.6)
	hook.Shape = Enum.PartType.Ball
	hook.Color = Color3.fromRGB(96, 96, 104)
	hook.Material = Enum.Material.Metal
	hook.Anchored = true
	hook.CanCollide = false
	hook.CanQuery = false
	hook.CFrame = CFrame.new(target)
	hook.Parent = workspace
	local a0 = Instance.new("Attachment")
	a0.Parent = hook
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 1, 0)
	a1.Parent = root
	local line = Instance.new("Beam")
	line.Attachment0 = a0
	line.Attachment1 = a1
	line.Width0 = 0.2
	line.Width1 = 0.2
	line.FaceCamera = true
	line.Segments = 1
	line.Color = ColorSequence.new(Color3.fromRGB(196, 160, 106))
	line.Parent = hook

	root.Anchored = true
	local elapsed = 0
	while elapsed < G.PullSeconds and character.Parent and root.Parent do
		elapsed += RunService.Heartbeat:Wait()
		local t = math.min(elapsed / G.PullSeconds, 1)
		local eased = t * t * (3 - 2 * t)
		local position = start:Lerp(target, eased) + Vector3.new(0, math.sin(t * math.pi) * 4, 0)
		character:PivotTo(CFrame.lookAt(position, position + facing))
	end
	if root.Parent then
		root.Anchored = false
		root.AssemblyLinearVelocity = Vector3.zero
	end
	a1:Destroy()
	task.delay(0.6, function()
		hook:Destroy()
	end)
end

function Grapple.use(player: Player)
	if busy[player] then
		return
	end
	local root = Characters.liveRoot(player)
	local center = Hollow.center()
	if not root or not center then
		return
	end
	if player:GetAttribute("HB_OnRope") then
		ServerNet.notify(player, "Let go of the rope before using the grapple.", "error")
		return
	end
	local depth, _, inPit = Hollow.measure(root.Position)
	if not depth or not inPit or depth < H.LedgeDepths[1] then
		ServerNet.notify(player, "The grapple only works down in the Hollow.", "error")
		return
	end
	local ledge = ledgeAbove(depth)
	if not ledge then
		ServerNet.notify(player, "There's no ledge above to hook onto.", "error")
		return
	end
	local used = spent[player]
	local here = band(depth)
	if used[here] then
		local from = here * G.BandMeters
		ServerNet.notify(player, `Your grapple is spent for {from}-{from + G.BandMeters} m. One use per {G.BandMeters} m of depth; it resets in town.`, "error")
		return
	end

	-- A spot on the ledge ring above, straight out from where you are.
	local offset = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
	local angleDir = if offset.Magnitude > 0.1 then offset.Unit else Vector3.xAxis
	local radius = (H.LedgeInnerRadius + Progression.pitRadiusAt(ledge)) / 2
	local spot = Vector3.new(center.X, center.Y - ledge, center.Z) + angleDir * radius
	local groundY = Ground.below(spot + Vector3.new(0, 4, 0)) or spot.Y
	local target = Vector3.new(spot.X, groundY + 3, spot.Z)

	used[here] = true
	busy[player] = true
	haul(player, root, target)
	busy[player] = nil
	local meters = math.floor((depth - ledge) * Config.Display.MetersPerStud)
	ServerNet.notify(player, `Grappled up {meters} m. Next grapple: in another {G.BandMeters} m band of depth, or after a trip to town.`, "success")
end

function Grapple.start()
	local function track(player: Player)
		spent[player] = {}
		player.CharacterAdded:Connect(function()
			spent[player] = {} -- respawns are at base
			busy[player] = nil
		end)
		player:GetAttributeChangedSignal("HB_Zone"):Connect(function()
			if player:GetAttribute("HB_Zone") == "Town" then
				spent[player] = {}
			end
		end)
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		spent[player] = nil
		busy[player] = nil
	end)
end

return Grapple
