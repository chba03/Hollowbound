--[[
	Local-only ability feedback. Everything created here exists on this client only.

	Echo pulse: an expanding ring sphere, plus a highlight and label on each relic the
	server reported. Marks attach to the relic's world part, so a relic someone claims
	disappears together with its mark. Marks clear when the pulse expires or when the
	server says the lens was unequipped (EchoLensEnd).
	Windhook: switches the local humanoid into a jump so ground friction does not fight
	the server's push, and gives the camera a brief field-of-view kick.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))

local AbilityFx = {}

local marks: { Instance } = {}
local markToken = 0

local function clearMarks()
	for _, mark in marks do
		mark:Destroy()
	end
	marks = {}
end

local function worldPartFor(specimenId: string): BasePart?
	for _, part in CollectionService:GetTagged(Config.Tags.WorldRelic) do
		if part:IsA("BasePart") and part:GetAttribute("SpecimenId") == specimenId then
			return part
		end
	end
	return nil
end

local function pulse(origin: Vector3, radius: number)
	local sphere = Instance.new("Part")
	sphere.Name = "HB_EchoPulse"
	sphere.Shape = Enum.PartType.Ball
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.CastShadow = false
	sphere.Material = Enum.Material.ForceField
	sphere.Color = Color3.fromRGB(120, 220, 255)
	sphere.Transparency = 0.2
	sphere.Size = Vector3.one * 2
	sphere.Position = origin
	sphere.Parent = workspace
	local tween = TweenService:Create(sphere, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 2,
		Transparency = 1,
	})
	tween.Completed:Connect(function()
		sphere:Destroy()
	end)
	tween:Play()
end

local function mark(part: BasePart, text: string)
	local highlight = Instance.new("Highlight")
	highlight.Name = "HB_EchoMark"
	highlight.FillColor = Color3.fromRGB(120, 220, 255)
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.4
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Adornee = part
	highlight.Parent = part
	table.insert(marks, highlight)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HB_EchoLabel"
	billboard.Size = UDim2.fromOffset(180, 30)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part
	local labelText = Instance.new("TextLabel")
	labelText.Size = UDim2.fromScale(1, 1)
	labelText.BackgroundTransparency = 1
	labelText.Text = text
	labelText.TextColor3 = Color3.fromRGB(180, 240, 255)
	labelText.TextStrokeTransparency = 0.3
	labelText.Font = Enum.Font.GothamBold
	labelText.TextSize = 16
	labelText.Parent = billboard
	table.insert(marks, billboard)
end

local function windhook()
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
	local camera = workspace.CurrentCamera
	if camera then
		local base = camera.FieldOfView
		local kick = TweenService:Create(camera, TweenInfo.new(0.12), { FieldOfView = base + 8 })
		kick.Completed:Connect(function()
			TweenService:Create(camera, TweenInfo.new(0.35), { FieldOfView = base }):Play()
		end)
		kick:Play()
	end
end

function AbilityFx.start(remote: RemoteEvent)
	remote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.kind == "Windhook" then
			windhook()
		elseif payload.kind == "EchoLens" then
			clearMarks()
			markToken += 1
			local token = markToken
			if typeof(payload.origin) == "Vector3" and typeof(payload.radius) == "number" then
				pulse(payload.origin, payload.radius)
			end
			for _, target in payload.targets or {} do
				local part = typeof(target.id) == "string" and worldPartFor(target.id)
				if part then
					mark(part, tostring(target.label))
				end
			end
			task.delay(tonumber(payload.duration) or 5, function()
				if markToken == token then
					clearMarks()
				end
			end)
		elseif payload.kind == "EchoLensEnd" then
			markToken += 1
			clearMarks()
		end
	end)
end

return AbilityFx
