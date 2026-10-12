--[[
	Slowly turns and bobs relic models near the camera. Presentation only: the server
	places each model at rest (attribute HB_Base) and this client moves its own copy.
	Models beyond SPIN_DISTANCE stay still, so the cost stays small.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))

local RelicSpin = {}

local SPIN_DISTANCE = 140
local TURN_SPEED = 0.7 -- radians per second
local BOB_HEIGHT = 0.25
local BOB_SPEED = 1.6

function RelicSpin.start()
	local models: { [Model]: number } = {} -- model -> phase

	local function add(instance: Instance)
		if instance:IsA("Model") then
			models[instance] = math.random() * 2 * math.pi
		end
	end
	for _, instance in CollectionService:GetTagged(Config.Tags.Spin) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.Spin):Connect(add)
	CollectionService:GetInstanceRemovedSignal(Config.Tags.Spin):Connect(function(instance)
		models[instance :: Model] = nil
	end)

	RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		local t = os.clock()
		for model, phase in models do
			local base = model:GetAttribute("HB_Base")
			if typeof(base) ~= "CFrame" or not model.PrimaryPart then
				continue
			end
			if (base.Position - eye).Magnitude > SPIN_DISTANCE then
				continue
			end
			local bob = math.sin(t * BOB_SPEED + phase) * BOB_HEIGHT
			model:PivotTo(base * CFrame.new(0, bob, 0) * CFrame.Angles(0, t * TURN_SPEED + phase, 0))
		end
	end)
end

return RelicSpin
