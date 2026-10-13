--[[
	Client half of rope climbing. Presentation and input only.

	The server decides when the player is on the rope (HB_OnRope) and validates every
	position. While on the rope, this module moves the local character along the rope
	line with an AlignPosition so climbing feels immediate, at the HB_RopeSpeed the
	server published. Keys: W / Up to climb, S / Down to descend, Space to let go.
	Off the rope, F grabs the nearest rope: your own, or anyone else's (HB_ClimbOwner
	is then their UserId, and you can only climb up on it).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local RopeController = {}

local player = Players.LocalPlayer

local grip: Attachment? = nil
local align: AlignPosition? = nil
local orient: AlignOrientation? = nil
local targetY = 0
local holdOutward = Vector3.zero -- horizontal direction from the pit centre to the rope
local topRequestedAt = 0

local function character()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then
		return root :: BasePart, humanoid :: Humanoid
	end
	return nil, nil
end

-- Whose rope you are climbing: someone else's while HB_ClimbOwner is set, else yours.
local function ropeOwner(): Player
	local id = player:GetAttribute("HB_ClimbOwner")
	local owner = if typeof(id) == "number" then Players:GetPlayerByUserId(id) else nil
	return owner or player
end

-- A player's rope line x/z, top Y, bottom Y from their server-published attributes.
local function spanOf(owner: Player): (Vector3?, number, number)
	local point = owner:GetAttribute("HB_RopePoint")
	if typeof(point) ~= "Vector3" then
		return nil, 0, 0
	end
	local length = owner:GetAttribute("HB_RopeLength") or 0
	return point, point.Y + Config.Rope.TopOffset, point.Y - length
end

local function ropeSpan(): (Vector3?, number, number)
	return spanOf(ropeOwner())
end

-- Is `position` close enough to `owner`'s deployed rope to grab it?
local function canGrab(owner: Player, position: Vector3): boolean
	if not owner:GetAttribute("HB_RopeDeployed") then
		return false
	end
	local point, topY, bottomY = spanOf(owner)
	if not point then
		return false
	end
	local horizontal = Vector2.new(position.X - point.X, position.Z - point.Z).Magnitude
	return horizontal <= Config.Rope.GrabRadius and position.Y >= bottomY - 2 and position.Y <= topY + 2
end

local function heldDirection(): number
	if UserInputService:GetFocusedTextBox() then
		return 0
	end
	local up = UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up)
	local down = UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down)
	if up and not down then
		return 1
	elseif down and not up then
		return -1
	end
	return 0
end

local function detach()
	for _, instance in { align, orient, grip } do
		if instance then
			instance:Destroy()
		end
	end
	grip, align, orient = nil, nil, nil
	local _, humanoid = character()
	if humanoid then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

local function attach()
	detach()
	local root, humanoid = character()
	local point = ropeSpan()
	if not root or not humanoid or not point then
		return
	end
	humanoid.PlatformStand = true
	humanoid:UnequipTools() -- both hands on the rope

	local newGrip = Instance.new("Attachment")
	newGrip.Name = "HB_RopeGrip"
	newGrip.Parent = root

	local newAlign = Instance.new("AlignPosition")
	newAlign.Mode = Enum.PositionAlignmentMode.OneAttachment
	newAlign.Attachment0 = newGrip
	newAlign.MaxForce = math.huge
	newAlign.Responsiveness = 60
	newAlign.Position = root.Position
	newAlign.Parent = root

	-- Face the pit wall, the way the server placed the character.
	local center = workspace:GetAttribute("HB_HollowCenter")
	local outward = if typeof(center) == "Vector3"
		then Vector3.new(point.X - center.X, 0, point.Z - center.Z)
		else root.CFrame.LookVector
	outward = if outward.Magnitude > 0.01 then outward.Unit else Vector3.zAxis

	local newOrient = Instance.new("AlignOrientation")
	newOrient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	newOrient.Attachment0 = newGrip
	newOrient.RigidityEnabled = true
	newOrient.CFrame = CFrame.lookAt(Vector3.zero, outward)
	newOrient.Parent = root

	grip, align, orient = newGrip, newAlign, newOrient
	holdOutward = outward

	targetY = root.Position.Y
	topRequestedAt = 0
end

local function onRopeChanged()
	if player:GetAttribute("HB_OnRope") then
		attach()
	else
		detach()
	end
end

-- Hint text for the HUD, or nil.
local function hint(): string?
	if player:GetAttribute("HB_OnRope") then
		local ceiling = player:GetAttribute("HB_AscentCeiling")
		local root = character()
		local point = ropeSpan()
		if typeof(ceiling) == "number" and root and point then
			local left = math.max(0, (point.Y - ceiling) - root.Position.Y) -- studs below the ceiling
			if left < 2 then
				return "The rare relic weighs you down: rest at a camp to climb higher."
			end
			return string.format("W / S: climb   Space: let go   (%d m of climbing before you must rest)", math.floor(left * Config.Display.MetersPerStud))
		end
		local owner = ropeOwner()
		if owner ~= player then
			return `W: climb   Space: let go   ({owner.DisplayName}'s rope: up only)`
		end
		return "W / S: climb   Space: let go"
	end
	local root = character()
	if not root then
		return nil
	end
	if canGrab(player, root.Position) then
		return "F: grab your rope"
	end
	for _, other in Players:GetPlayers() do
		if other ~= player and canGrab(other, root.Position) then
			return `F: grab {other.DisplayName}'s rope (climb up only)`
		end
	end
	return nil
end

function RopeController.start(remotes: Instance, hud)
	local grabRemote = remotes:WaitForChild(Net.RopeGrab)
	local releaseRemote = remotes:WaitForChild(Net.RopeRelease)

	player:GetAttributeChangedSignal("HB_OnRope"):Connect(onRopeChanged)
	player.CharacterAdded:Connect(function()
		grip, align, orient = nil, nil, nil
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space and align then
			releaseRemote:FireServer(false)
			detach()
			-- Hop toward the wall so letting go at ledge height lands on the ledge.
			local root = character()
			local point = ropeSpan()
			local center = workspace:GetAttribute("HB_HollowCenter")
			if root and point and typeof(center) == "Vector3" then
				local outward = Vector3.new(point.X - center.X, 0, point.Z - center.Z)
				if outward.Magnitude > 0.01 then
					root.AssemblyLinearVelocity = outward.Unit * 26 + Vector3.new(0, 32, 0)
				end
			end
		elseif input.KeyCode == Enum.KeyCode.F and not align and hint() then
			grabRemote:FireServer()
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		hud:setHint(hint())
		if not align then
			return
		end
		local point, topY, bottomY = ropeSpan()
		if not point then
			return
		end
		local root = character()
		local direction = heldDirection()
		if ropeOwner() ~= player then
			direction = math.max(direction, 0) -- someone else's rope: up only
		end
		local speed = player:GetAttribute("HB_RopeSpeed") or 16
		local rate = if direction < 0 then speed * Config.Rope.DescendMultiplier else speed
		-- If the server moved us (snap-back or harness catch), climb on from there
		-- instead of dragging the character back to the old target.
		if root and math.abs(root.Position.Y - targetY) > 10 then
			targetY = root.Position.Y
		end
		-- Climbing fatigue: no higher than the ascent ceiling until you rest (server Ascent).
		local ceiling = player:GetAttribute("HB_AscentCeiling")
		local maxY = if typeof(ceiling) == "number" then math.max(bottomY, math.min(topY, point.Y - ceiling)) else topY
		targetY = math.clamp(targetY + direction * rate * dt, bottomY, maxY)
		align.MaxVelocity = speed * Config.Rope.DescendMultiplier * 1.2
		-- Hang just off the rope (toward the pit centre) so it runs in front of the chest.
		align.Position = Vector3.new(point.X, targetY, point.Z) - holdOutward * Config.Rope.HoldOffset

		-- Ask to climb off once the character itself (not just the target) is at the top.
		-- The server also dismounts climbers who reach the top; this is the fast path.
		local atTop = root ~= nil and root.Position.Y >= topY - Config.Rope.TopReach
		if direction > 0 and atTop and os.clock() >= topRequestedAt + 1 then
			topRequestedAt = os.clock()
			releaseRemote:FireServer(true)
		end
	end)

	onRopeChanged()
end

return RopeController
