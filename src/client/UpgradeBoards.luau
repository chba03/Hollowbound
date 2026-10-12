--[[
	Clickable upgrade panels on your own base's three upgrade boards (rope length, climb
	speed, display slots). Presentation and input only: each panel shows the upgrade,
	"Level N > Level N+1", a price button, and what the next level gives. Clicking the
	button asks the server (Net.BuyUpgrade), which checks ownership, distance, and cash.

	Panels are SurfaceGuis in this player's PlayerGui adorned to the board parts, so
	they take clicks and only exist for the base's owner.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Progression = require(Shared:WaitForChild("Progression"))

local UpgradeBoards = {}

local BOARDS = {
	{ kind = "RopeLength", part = "UpgradeRopeLength", title = "ROPE LENGTH", accent = Color3.fromRGB(255, 176, 80) },
	{ kind = "RopeSpeed", part = "UpgradeRopeSpeed", title = "CLIMB SPEED", accent = Color3.fromRGB(110, 200, 255) },
	{ kind = "BaseSlots", part = "UpgradeBaseSlots", title = "DISPLAY SLOTS", accent = Color3.fromRGB(220, 150, 255) },
}

local COLORS = {
	board = Color3.fromRGB(28, 40, 70),
	boardEdge = Color3.fromRGB(12, 16, 30),
	level = Color3.fromRGB(120, 255, 110),
	buy = Color3.fromRGB(70, 200, 70), -- you can afford it
	buyPoor = Color3.fromRGB(120, 40, 40), -- not enough cash yet
	maxed = Color3.fromRGB(90, 90, 100),
	gain = Color3.fromRGB(176, 40, 220),
	outline = Color3.fromRGB(0, 0, 0),
}

local function round(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function outline(parent: Instance, thickness: number, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or COLORS.outline
	s.Parent = parent
	return s
end

-- Text with a thick black outline, like the reference panel.
local function text(parent: Instance, props): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = props.color or Color3.new(1, 1, 1)
	l.Text = props.text or ""
	l.Size = props.size
	l.Position = props.position
	l.AnchorPoint = props.anchor or Vector2.zero
	l.ZIndex = props.z or 2
	l.Parent = parent
	local stroke = outline(l, props.stroke or 3)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	return l
end

local function buildPanel(playerGui: PlayerGui, board, part: BasePart, onBuy: () -> ())
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Upgrade_" .. board.kind
	gui.Adornee = part
	gui.Face = Enum.NormalId.Left -- the side facing the middle of the base
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = COLORS.board
	frame.Parent = gui
	round(frame, 18)
	outline(frame, 6, COLORS.boardEdge)

	text(frame, { text = board.title, size = UDim2.fromScale(0.9, 0.13), position = UDim2.fromScale(0.5, 0.05), anchor = Vector2.new(0.5, 0), color = board.accent, stroke = 3 })
	text(frame, { text = "Upgrade", size = UDim2.fromScale(0.8, 0.2), position = UDim2.fromScale(0.5, 0.19), anchor = Vector2.new(0.5, 0), stroke = 4 })
	local levelLabel = text(frame, { size = UDim2.fromScale(0.94, 0.15), position = UDim2.fromScale(0.5, 0.41), anchor = Vector2.new(0.5, 0), color = COLORS.level, stroke = 4 })

	-- Price button (left, big) and what you get (right, purple).
	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.AutoButtonColor = false
	buy.Text = ""
	buy.Size = UDim2.fromScale(0.6, 0.3)
	buy.Position = UDim2.fromScale(0.04, 0.63)
	buy.BackgroundColor3 = COLORS.buy
	buy.Parent = frame
	round(buy, 10)
	outline(buy, 5)
	local scale = Instance.new("UIScale")
	scale.Parent = buy
	local price = text(buy, { size = UDim2.fromScale(0.86, 0.7), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), stroke = 4 })

	local gainBox = Instance.new("Frame")
	gainBox.Size = UDim2.fromScale(0.3, 0.24)
	gainBox.Position = UDim2.fromScale(0.67, 0.66)
	gainBox.BackgroundColor3 = COLORS.gain
	gainBox.Parent = frame
	round(gainBox, 10)
	outline(gainBox, 5)
	local gain = text(gainBox, { size = UDim2.fromScale(0.88, 0.7), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), stroke = 3 })

	buy.Activated:Connect(function()
		scale.Scale = 0.9
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		onBuy()
	end)
	buy.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.05 }):Play()
	end)
	buy.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)

	-- Refreshes the panel from the player's levels and cash.
	return function(player: Player)
		local upgrade = Progression.Upgrades[board.kind]
		local level = player:GetAttribute("HB_" .. upgrade.field)
		level = if typeof(level) == "number" then level else 1
		local cash = player:GetAttribute("HB_Cash")
		cash = if typeof(cash) == "number" then cash else 0
		local nextDef, nextLevel = Progression.next(board.kind, level)
		if nextDef then
			levelLabel.Text = `Level {level} > Level {nextLevel}`
			price.Text = Progression.formatCash(nextDef.cost)
			gain.Text = `{nextDef.value}{upgrade.unit}`
			local affordable = cash >= nextDef.cost
			buy.BackgroundColor3 = if affordable then COLORS.buy else COLORS.buyPoor
			buy.Active = true
		else
			levelLabel.Text = `Level {level} (MAX)`
			price.Text = "MAXED"
			gain.Text = `{Progression.value(board.kind, level)}{upgrade.unit}`
			buy.BackgroundColor3 = COLORS.maxed
			buy.Active = false
		end
	end
end

function UpgradeBoards.start(remotes: Instance)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	local buyRemote = remotes:WaitForChild(Net.BuyUpgrade)
	local refreshers: { (Player) -> () } = {}
	local built: Model? = nil

	local function refresh()
		for _, refreshPanel in refreshers do
			refreshPanel(player)
		end
	end

	local function findPlot(): Model?
		local index = player:GetAttribute("HB_PlotIndex")
		for _, plot in CollectionService:GetTagged(Config.Tags.Plot) do
			if plot:IsA("Model") and plot:GetAttribute("PlotIndex") == index then
				return plot
			end
		end
		return nil
	end

	local function build()
		local plot = findPlot()
		if not plot or plot == built then
			return
		end
		built = plot
		for _, old in playerGui:GetChildren() do
			if old:IsA("SurfaceGui") and string.sub(old.Name, 1, 8) == "Upgrade_" then
				old:Destroy()
			end
		end
		refreshers = {}
		for _, board in BOARDS do
			local part = plot:WaitForChild(board.part, 10)
			if part and part:IsA("BasePart") then
				-- The panel names the upgrade; hide the floating label on your own boards.
				local label = part:FindFirstChildOfClass("BillboardGui")
				if label then
					label.Enabled = false
				end
				table.insert(refreshers, buildPanel(playerGui, board, part, function()
					buyRemote:FireServer(board.kind)
				end))
			end
		end
		refresh()
	end

	for _, name in { "HB_Cash", "HB_RopeLengthLevel", "HB_RopeSpeedLevel", "HB_BaseSlotsLevel" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	player:GetAttributeChangedSignal("HB_PlotIndex"):Connect(build)
	CollectionService:GetInstanceAddedSignal(Config.Tags.Plot):Connect(build)
	build()
end

return UpgradeBoards
