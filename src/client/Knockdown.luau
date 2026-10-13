--[[
	Being knocked down by another player's pickaxe (server Arsenal, Config.Pickaxes.Pvp).

	The server ragdolls the character (loose joints, visible to everyone) and sends
	Net.Knockback with the shove and how long it lasts. This client owns its
	character's physics, so it applies the shove and keeps the humanoid limp until the
	server stands the body back up. Presentation and physics only: the server decides
	who gets knocked down.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Net"))

local Knockdown = {}

local player = Players.LocalPlayer
local downUntil = 0

function Knockdown.start(remotes: Instance)
	local remote = remotes:WaitForChild(Net.Knockback) :: RemoteEvent
	remote.OnClientEvent:Connect(function(velocity: any, seconds: any)
		if typeof(velocity) ~= "Vector3" or typeof(seconds) ~= "number" then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (humanoid and root and root:IsA("BasePart")) or humanoid.Health <= 0 then
			return
		end
		humanoid:UnequipTools()
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		for _, part in (character :: Model):GetDescendants() do
			if part:IsA("BasePart") then
				part.AssemblyLinearVelocity = velocity
			end
		end
		-- A little spin so the fall looks like a hit, not a slide.
		local axis = Vector3.new(velocity.Z, 0, -velocity.X)
		if axis.Magnitude > 0.1 then
			root.AssemblyAngularVelocity = axis.Unit * 6
		end

		local untilTime = os.clock() + seconds
		downUntil = untilTime
		task.delay(seconds + 0.05, function()
			if downUntil ~= untilTime or humanoid.Health <= 0 or not humanoid.Parent then
				return -- hit again meanwhile, or dead
			end
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
	end)
end

return Knockdown
