--[[
	Environmental falls and the void (milestone 5, provisional). Server only.

	Falls: while a character is airborne the server tracks its fastest downward speed
	(the replicated root velocity); on landing, an impact above Config.Falls.SafeSpeed deals
	damage through the central interface (Vitals.damagePlayer, source kind "Fall"), so a
	lethal fall downs the explorer rather than killing outright. Climbing (trusses) and
	walking down ramps never reach the threshold. FallMath is pure and tested.

	Void: in the vertical world, a character below the kill plane (Config.World.KillDepth)
	has fallen into the dark. The engine kill goes through the existing final-death path
	once; drops use the last safe ground position (Defeat), never background scenery.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local FallMath = require(script.Parent.FallMath)
local Vitals = require(script.Parent.Vitals)
local WorldInfo = require(script.Parent.WorldInfo)

local Falls = {}

Falls.damageFor = FallMath.damageFor

local tracking: { [Player]: { airborne: boolean, fastest: number, character: Model? } } = {}

local function step()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
			tracking[player] = nil
			continue
		end
		-- The dark below the first depth.
		if WorldInfo.belowKillPlane(root.Position) then
			tracking[player] = nil
			print(`[Hollowbound] {player.Name} fell into the dark`)
			humanoid.Health = 0
			continue
		end
		if not Config.Falls.Enabled then
			continue
		end
		local state = tracking[player]
		if not state or state.character ~= character then
			state = { airborne = false, fastest = 0, character = character }
			tracking[player] = state
		end
		local airborne = humanoid.FloorMaterial == Enum.Material.Air
		local climbing = humanoid:GetState() == Enum.HumanoidStateType.Climbing
		local downward = -root.AssemblyLinearVelocity.Y
		if airborne and not climbing then
			state.airborne = true
			state.fastest = math.max(state.fastest, downward)
		elseif state.airborne then
			local damage = Falls.damageFor(state.fastest, Config.Falls)
			state.airborne = false
			state.fastest = 0
			if damage > 0 and Vitals.condition(player) == "Alive" then
				Vitals.damagePlayer(player, damage, { kind = "Fall", name = "a fall" })
			end
		else
			state.fastest = 0
		end
	end
end

function Falls.start()
	RunService.Heartbeat:Connect(step)
	Players.PlayerRemoving:Connect(function(player)
		tracking[player] = nil
	end)
end

return Falls
