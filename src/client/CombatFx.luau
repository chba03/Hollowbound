--[[
	Damage numbers: when your pickaxe hits something, the server sends where and how
	much (Net.HitShown) and a number pops up there, rises, and fades. Presentation only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Net = require(Shared:WaitForChild("Net"))
local Progression = require(Shared:WaitForChild("Progression"))

local CombatFx = {}

local function popup(position: Vector3, amount: number)
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position + Vector3.new(math.random(-8, 8) / 10, 0, math.random(-8, 8) / 10)
	anchor.Parent = workspace.Terrain

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(140, 48)
	gui.AlwaysOnTop = true
	gui.Adornee = anchor
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 196, 80)
	label.Text = Progression.formatNumber(amount)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 1.5
	scale.Parent = label

	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	local rise = TweenInfo.new(0.8, Enum.EasingStyle.Quad)
	TweenService:Create(anchor, rise, { WorldPosition = anchor.WorldPosition + Vector3.new(0, 2.5, 0) }):Play()
	task.delay(0.35, function()
		local fade = TweenInfo.new(0.45)
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	end)
	task.delay(0.9, function()
		anchor:Destroy()
	end)
end

function CombatFx.start(remotes: Instance)
	local hits = remotes:WaitForChild(Net.HitShown) :: RemoteEvent
	hits.OnClientEvent:Connect(function(position, amount)
		if typeof(position) == "Vector3" and typeof(amount) == "number" then
			popup(position, amount)
		end
	end)
end

return CombatFx
