--[[
	The Hauling Rig on this client. Presentation and input only.

	  - The server locks you in at your rig (HB_Hauling) after its "Haul rope" prompt
	    and pulls by itself. Any movement key, jump, or the Stop button lets go
	    (Net.HaulStop).
	  - Only your own rig's prompt shows.
	  - Every rig's crate rises a step with each pull (the plot's HaulCount attribute) and
	    drops back after a full haul, for everyone's rig.
	  - Your pulls float "+N" Speed numbers above the rig.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Progression = require(Shared:WaitForChild("Progression"))

local HaulController = {}

local HOIST = 6 -- studs the crate rises over a full haul

local function myPlot(player: Player): Model?
	local index = player:GetAttribute("HB_PlotIndex")
	for _, plot in CollectionService:GetTagged(Config.Tags.Plot) do
		if plot:IsA("Model") and plot:GetAttribute("PlotIndex") == index then
			return plot
		end
	end
	return nil
end

-- Hoists a plot's crate to match its HaulCount, dropping back after a full haul.
local function watchCrate(plot: Instance)
	if not plot:IsA("Model") then
		return
	end
	local crate = plot:WaitForChild("HaulCrate", 10)
	if not (crate and crate:IsA("BasePart")) then
		return
	end
	local restY = crate:GetAttribute("RestY")
	if typeof(restY) ~= "number" then
		return
	end
	local base = crate.CFrame - crate.Position + Vector3.new(crate.Position.X, restY, crate.Position.Z)
	local steps = Config.Hauling.CrateSteps
	plot:GetAttributeChangedSignal("HaulCount"):Connect(function()
		local count = plot:GetAttribute("HaulCount") or 0
		local step = count % steps
		if step == 0 then
			-- Full haul: up to the top, then let it drop.
			local up = TweenService:Create(crate, TweenInfo.new(0.1), { CFrame = base + Vector3.new(0, HOIST, 0) })
			up:Play()
			up.Completed:Connect(function()
				TweenService:Create(crate, TweenInfo.new(0.35, Enum.EasingStyle.Bounce), { CFrame = base }):Play()
			end)
		else
			TweenService:Create(crate, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { CFrame = base + Vector3.new(0, HOIST * step / steps, 0) }):Play()
		end
	end)
end

-- A "+N" that floats up from the rig and fades.
local function floatGain(handle: BasePart, amount: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(math.random(-10, 10) / 10, 3, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = handle
	gui.Parent = handle
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(120, 220, 255)
	label.Text = `+{Progression.formatNumber(amount)} Speed`
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = label
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad)
	TweenService:Create(gui, info, { StudsOffsetWorldSpace = gui.StudsOffsetWorldSpace + Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	task.delay(1, function()
		gui:Destroy()
	end)
end

-- Keys that let go of the rig: any movement or jump.
local STOP_KEYS = {
	[Enum.KeyCode.W] = true,
	[Enum.KeyCode.A] = true,
	[Enum.KeyCode.S] = true,
	[Enum.KeyCode.D] = true,
	[Enum.KeyCode.Up] = true,
	[Enum.KeyCode.Down] = true,
	[Enum.KeyCode.Left] = true,
	[Enum.KeyCode.Right] = true,
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.ButtonA] = true,
	[Enum.KeyCode.ButtonB] = true,
}

function HaulController.start(remotes: Instance, hud)
	local player = Players.LocalPlayer
	local stopRemote = remotes:WaitForChild(Net.HaulStop)

	-- Only your own rig shows its "Haul rope" prompt (others' are hidden on this client),
	-- and only while you are not already hauling.
	local function updatePrompts()
		local hauling = player:GetAttribute("HB_Hauling") == true
		local index = player:GetAttribute("HB_PlotIndex")
		for _, plot in CollectionService:GetTagged(Config.Tags.Plot) do
			local handle = plot:FindFirstChild("HaulHandle")
			local prompt = handle and handle:FindFirstChild("HaulPrompt")
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.Enabled = plot:GetAttribute("PlotIndex") == index and not hauling
			end
		end
	end

	for _, plot in CollectionService:GetTagged(Config.Tags.Plot) do
		task.spawn(watchCrate, plot)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.Plot):Connect(function(plot)
		task.spawn(watchCrate, plot)
		task.defer(updatePrompts)
	end)
	player:GetAttributeChangedSignal("HB_PlotIndex"):Connect(updatePrompts)
	task.delay(1, updatePrompts) -- prompts are made after the plots; catch them

	local function stop()
		if player:GetAttribute("HB_Hauling") == true then
			stopRemote:FireServer()
		end
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and STOP_KEYS[input.KeyCode] then
			stop()
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick1 and input.Position.Magnitude > 0.6 then
			stop()
		end
	end)

	player:GetAttributeChangedSignal("HB_Hauling"):Connect(function()
		local hauling = player:GetAttribute("HB_Hauling") == true
		hud:setHaulHint(if hauling then "Hauling: Speed builds while you stay. Move or jump to let go." else nil)
		hud:setHaulStop(hauling, stop)
		updatePrompts()
	end)

	-- Floating gains for your own pulls.
	local lastSpeed = player:GetAttribute("HB_Speed")
	player:GetAttributeChangedSignal("HB_Speed"):Connect(function()
		local speed = player:GetAttribute("HB_Speed")
		if typeof(speed) == "number" and typeof(lastSpeed) == "number" and speed > lastSpeed and player:GetAttribute("HB_Hauling") then
			local plot = myPlot(player)
			local handle = plot and plot:FindFirstChild("HaulHandle")
			if handle and handle:IsA("BasePart") then
				floatGain(handle, speed - lastSpeed)
			end
		end
		lastSpeed = speed
	end)
end

return HaulController
