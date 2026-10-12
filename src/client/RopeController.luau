--[[
	Client half of rope climbing. Presentation and input only.

	The server decides when the player is on the rope (HB_OnRope) and validates every
	position. While on the rope, this module moves the local character along the rope
	line with an AlignPosition so climbing feels immediate, at the HB_RopeSpeed the
	server published. Keys: W / Up to climb, S / Down to descend, Space to let go.
	Off the rope, F grabs your own rope when you are close to it.
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

-- Rope line x/z, top Y, bottom Y from server-published attributes.
local function ropeSpan(): (Vector3?, number, number)
	local point = player:GetAttribute("HB_RopePoint")
	if typeof(point) ~= "Vector3" then
		return nil, 0, 0
	end
	local length = player:GetAttribute("HB_RopeLength") or 0
	return point, point.Y + Config.Rope.TopOffset, point.Y - length
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
		return "W / S: climb   Space: let go"
	end
	if not player:GetAttribute("HB_RopeDeployed") then
		return nil
	end
	local root = character()
	local point, topY, bottomY = ropeSpan()
	if not root or not point then
		return nil
	end
	local position = root.Position
	local horizontal = Vector2.new(position.X - point.X, position.Z - point.Z).Magnitude
	if horizontal <= Config.Rope.GrabRadius and position.Y >= bottomY - 2 and position.Y <= topY + 2 then
		return "F: grab your rope"
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
		local speed = player:GetAttribute("HB_RopeSpeed") or 16
		local rate = if direction < 0 then speed * Config.Rope.DescendMultiplier else speed
		-- If the server moved us (snap-back or harness catch), climb on from there
		-- instead of dragging the character back to the old target.
		if root and math.abs(root.Position.Y - targetY) > 10 then
			targetY = root.Position.Y
		end
		targetY = math.clamp(targetY + direction * rate * dt, bottomY, topY)
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
