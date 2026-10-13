--[[
	Presentation only: the pack (inventory) panel, base stats, zone label, rope hint,
	layer banner, and messages. It renders whatever the server sends and holds no game
	state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Progression = require(Shared:WaitForChild("Progression"))

local COLORS = {
	panel = Color3.fromRGB(20, 22, 28),
	row = Color3.fromRGB(34, 37, 46),
	text = Color3.fromRGB(235, 235, 240),
	muted = Color3.fromRGB(150, 155, 170),
	unsecured = Color3.fromRGB(240, 150, 60),
	registered = Color3.fromRGB(90, 200, 120),
	displayed = Color3.fromRGB(230, 200, 90),
	info = Color3.fromRGB(60, 65, 80),
	success = Color3.fromRGB(40, 110, 70),
	error = Color3.fromRGB(130, 45, 45),
}

local ZONE_TEXT = {
	Town = "Town",
	Camp = "Camp: refuge (relics stay unsecured)",
	Depths = "Depths",
}

local STAMINA_COLORS = {
	normal = Color3.fromRGB(120, 210, 120),
	sprinting = Color3.fromRGB(240, 210, 90),
	exhausted = Color3.fromRGB(220, 80, 70),
}

local Hud = {}
Hud.__index = Hud

local function rarityColor(rarityId: string): Color3
	for _, tier in Config.Rarities do
		if tier.id == rarityId then
			return tier.color
		end
	end
	return COLORS.text
end

local function label(parent: Instance, props): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = props.font or Enum.Font.Gotham
	l.TextSize = props.size or 14
	l.TextColor3 = props.color or COLORS.text
	l.TextXAlignment = props.align or Enum.TextXAlignment.Left
	l.Text = props.text or ""
	l.Size = props.dims or UDim2.new(1, 0, 0, (props.size or 14) + 4)
	l.LayoutOrder = props.order or 0
	l.Parent = parent
	return l
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
end

local function vlist(parent: Instance, gap: number)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = parent
end

function Hud.new(playerGui: PlayerGui)
	local self = setmetatable({}, Hud)

	local gui = Instance.new("ScreenGui")
	gui.Name = "HollowboundHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = playerGui

	-- Pack panel (top right)
	local panel = Instance.new("Frame")
	panel.Name = "Pack"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -16, 0, 16)
	panel.Size = UDim2.fromOffset(280, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = COLORS.panel
	panel.BackgroundTransparency = 0.15
	panel.Parent = gui
	corner(panel, 8)
	padding(panel, 10)
	vlist(panel, 6)
	-- Header: click to collapse or expand the list.
	local header = Instance.new("TextButton")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.AutoButtonColor = false
	header.Font = Enum.Font.GothamBold
	header.TextSize = 14
	header.TextColor3 = COLORS.text
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Size = UDim2.new(1, 0, 0, 18)
	header.LayoutOrder = 0
	header.Parent = panel
	self.header = header
	self.relicCount = 0
	self.collapsed = false

	-- The list scrolls once it is taller than 55% of the screen.
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.new(1, 0, 0, 0)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 5
	list.ScrollBarImageColor3 = COLORS.muted
	list.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	list.LayoutOrder = 1
	list.Parent = panel
	vlist(list, 6)
	self.list = list

	local layout = list:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	local function fit()
		local maxHeight = math.max(120, gui.AbsoluteSize.Y * 0.55)
		list.Size = UDim2.new(1, 0, 0, math.min(layout.AbsoluteContentSize.Y, maxHeight))
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	header.Activated:Connect(function()
		self.collapsed = not self.collapsed
		list.Visible = not self.collapsed
		self:refreshHeader()
	end)
	self:refreshHeader()

	-- Base stats (top left, below the Roblox buttons)
	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.Position = UDim2.new(0, 16, 0, 16)
	stats.Size = UDim2.fromOffset(230, 0)
	stats.AutomaticSize = Enum.AutomaticSize.Y
	stats.BackgroundColor3 = COLORS.panel
	stats.BackgroundTransparency = 0.15
	stats.Parent = gui
	corner(stats, 8)
	padding(stats, 10)
	vlist(stats, 4)
	self.cashLabel = label(stats, { font = Enum.Font.GothamBold, size = 20, color = COLORS.displayed, order = 1 })
	self.incomeLabel = label(stats, { size = 13, color = COLORS.muted, order = 2 })
	self.speedLabel = label(stats, { font = Enum.Font.GothamBold, size = 15, color = Color3.fromRGB(120, 220, 255), order = 3 })
	self.ropeLabel = label(stats, { size = 13, order = 3 })
	self.slotsLabel = label(stats, { size = 13, order = 4 })
	self.depthLabel = label(stats, { size = 13, order = 5 })

	-- Rope hint (bottom center, above the toast)
	self.hintLabel = label(gui, {
		text = "",
		font = Enum.Font.GothamBold,
		size = 16,
		align = Enum.TextXAlignment.Center,
		dims = UDim2.new(0, 420, 0, 22),
	})
	self.hintLabel.AnchorPoint = Vector2.new(0.5, 1)
	self.hintLabel.Position = UDim2.new(0.5, 0, 1, -170)
	self.hintLabel.TextStrokeTransparency = 0.4

	-- Layer banner (upper center)
	local banner = label(gui, {
		text = "",
		font = Enum.Font.Garamond,
		size = 40,
		align = Enum.TextXAlignment.Center,
		dims = UDim2.new(0, 600, 0, 90),
	})
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0.18, 0)
	banner.TextWrapped = true
	banner.TextTransparency = 1
	banner.TextStrokeTransparency = 1
	self.bannerLabel = banner
	self.bannerToken = 0

	-- Depth meter (top center, above the zone label)
	self.depthMeter = label(gui, {
		text = "SURFACE",
		font = Enum.Font.GothamBlack,
		size = 30,
		align = Enum.TextXAlignment.Center,
		dims = UDim2.new(0, 300, 0, 36),
	})
	self.depthMeter.AnchorPoint = Vector2.new(0.5, 0)
	self.depthMeter.Position = UDim2.new(0.5, 0, 0, 10)
	self.depthMeter.TextStrokeTransparency = 0.3

	-- Zone label (top center)
	self.zoneLabel = label(gui, {
		text = "",
		font = Enum.Font.GothamBold,
		size = 18,
		align = Enum.TextXAlignment.Center,
		dims = UDim2.new(0, 420, 0, 28),
	})
	self.zoneLabel.AnchorPoint = Vector2.new(0.5, 0)
	self.zoneLabel.Position = UDim2.new(0.5, 0, 0, 52)
	self.zoneLabel.TextStrokeTransparency = 0.4

	-- Night timer (top center, under the zone label)
	self.nightLabel = label(gui, {
		text = "",
		size = 14,
		color = COLORS.muted,
		align = Enum.TextXAlignment.Center,
		dims = UDim2.new(0, 420, 0, 20),
	})
	self.nightLabel.AnchorPoint = Vector2.new(0.5, 0)
	self.nightLabel.Position = UDim2.new(0.5, 0, 0, 80)
	self.nightLabel.TextStrokeTransparency = 0.5

	-- Stamina bar (bottom center, above the hints). Fades out while full.
	local staminaFrame = Instance.new("Frame")
	staminaFrame.Name = "Stamina"
	staminaFrame.AnchorPoint = Vector2.new(0.5, 1)
	staminaFrame.Position = UDim2.new(0.5, 0, 1, -200)
	staminaFrame.Size = UDim2.fromOffset(260, 12)
	staminaFrame.BackgroundColor3 = COLORS.panel
	staminaFrame.BackgroundTransparency = 1
	staminaFrame.Parent = gui
	corner(staminaFrame, 6)
	local staminaStroke = Instance.new("UIStroke")
	staminaStroke.Color = Color3.fromRGB(20, 20, 24)
	staminaStroke.Thickness = 1.5
	staminaStroke.Transparency = 1
	staminaStroke.Parent = staminaFrame
	local staminaFill = Instance.new("Frame")
	staminaFill.Name = "Fill"
	staminaFill.Size = UDim2.fromScale(1, 1)
	staminaFill.BackgroundColor3 = STAMINA_COLORS.normal
	staminaFill.BackgroundTransparency = 1
	staminaFill.BorderSizePixel = 0
	staminaFill.Parent = staminaFrame
	corner(staminaFill, 6)
	self.staminaFrame = staminaFrame
	self.staminaStroke = staminaStroke
	self.staminaFill = staminaFill
	self.staminaVisible = false

	-- Server-wide announcements (stacked, upper center)
	local announcements = Instance.new("Frame")
	announcements.Name = "Announcements"
	announcements.AnchorPoint = Vector2.new(0.5, 0)
	announcements.Position = UDim2.new(0.5, 0, 0, 106)
	announcements.Size = UDim2.fromOffset(640, 0)
	announcements.AutomaticSize = Enum.AutomaticSize.Y
	announcements.BackgroundTransparency = 1
	announcements.Parent = gui
	vlist(announcements, 6)
	self.announcements = announcements
	self.announceCount = 0

	-- Message toast (bottom center)
	local toast = label(gui, {
		text = "",
		size = 16,
		align = Enum.TextXAlignment.Center,
		dims = UDim2.new(0, 520, 0, 0),
	})
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 1, -110)
	toast.AutomaticSize = Enum.AutomaticSize.Y
	toast.TextWrapped = true
	toast.BackgroundTransparency = 1
	toast.TextTransparency = 1
	toast.BackgroundColor3 = COLORS.info
	corner(toast, 8)
	padding(toast, 10)
	self.toastLabel = toast
	self.toastToken = 0

	self.gui = gui
	self:setInventory({})
	return self
end

function Hud:refreshHeader()
	local arrow = if self.collapsed then "\u{25B8}" else "\u{25BE}"
	self.header.Text = `{arrow}  RELICS ({self.relicCount})`
end

function Hud:setInventory(items)
	self.relicCount = #items
	self:refreshHeader()
	for _, child in self.list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	if #items == 0 then
		label(self.list, { text = "No relics yet. Find some in the Hollow.", color = COLORS.muted, order = 1 })
		return
	end

	for index, item in items do
		local row = Instance.new("Frame")
		row.Name = "Relic_" .. item.id
		row.BackgroundColor3 = COLORS.row
		row.Size = UDim2.new(1, 0, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.LayoutOrder = index
		row.Parent = self.list
		corner(row, 6)
		padding(row, 8)
		vlist(row, 2)

		local title = label(row, { text = item.name, font = Enum.Font.GothamBold, size = 15, order = 1 })
		label(title, {
			text = item.rarity,
			font = Enum.Font.GothamBold,
			size = 13,
			color = rarityColor(item.rarity),
			align = Enum.TextXAlignment.Right,
			dims = UDim2.fromScale(1, 1),
		})

		local securityColor = if item.security == "Registered" then COLORS.registered else COLORS.unsecured
		local status = string.upper(item.security)
		if item.placed then
			status = "ON DISPLAY"
			securityColor = COLORS.displayed
		end
		label(row, { text = status, font = Enum.Font.GothamBold, size = 12, color = securityColor, order = 2 })
		local incomeText = `Layer {item.layer}  ·  size {string.format("%.2f", item.size or 1)}x  ·  {Progression.formatCash(item.income)}/s`
		if not item.placed then
			incomeText ..= " on display"
		end
		label(row, { text = incomeText, size = 12, color = COLORS.muted, order = 3 })
		label(row, { text = `{item.appraisal}  ·  {item.activation}`, size = 12, color = COLORS.muted, order = 4 })

		if item.traits then
			for i, trait in item.traits do
				label(row, { text = `{trait.label}: {trait.value} {trait.unit}`, size = 12, order = 4 + i })
			end
		end

		label(row, { text = "ID " .. string.sub(item.id, 1, 8), size = 11, color = COLORS.muted, order = 100 })
	end
end

function Hud:setZone(zone: string?, layer: number?)
	local text = if zone then (ZONE_TEXT[zone] or zone) else ""
	local def = layer and Config.Layers[layer]
	if zone == "Depths" and def then
		text = `Layer {layer}: {def.name}`
	elseif zone == "Camp" and def then
		text ..= `  ·  Layer {layer}`
	end
	self.zoneLabel.Text = text
end

-- stats: attributes read from the player (see client init).
function Hud:setStats(stats)
	local slotsUsed = stats.slotsUsed or 0
	self.cashLabel.Text = Progression.formatCash(stats.cash or 0)
	self.incomeLabel.Text = `+{Progression.formatCash(stats.income or 0)}/s from displays`
	self.speedLabel.Text = `Speed: {Progression.formatNumber(stats.speed or 0)}`
	self.ropeLabel.Text = `Rope: {stats.ropeLength or 0} studs  ·  climb {math.floor(stats.ropeSpeed or 0)} studs/s`
	self.slotsLabel.Text = `Displays: {slotsUsed}/{stats.slots or 0}`
	local deepest = math.floor((stats.deepest or 0) * Config.Display.MetersPerStud)
	self.depthLabel.Text = if deepest > 0 then `Deepest: {deepest} m` else "Deepest: surface"
end

-- The big depth readout. depthStuds: studs below rim height (0 or less = surface).
function Hud:setDepth(depthStuds: number)
	local meters = math.floor(depthStuds * Config.Display.MetersPerStud)
	local text = if meters > 0 then `{meters} m` else "SURFACE"
	if self.depthMeter.Text ~= text then
		self.depthMeter.Text = text
	end
end

-- The Hauling Rig hint (its own line, so the rope hint never overwrites it).
function Hud:setHaulHint(text: string?)
	if not self.haulLabel then
		local l = label(self.gui, {
			text = "",
			font = Enum.Font.GothamBold,
			size = 16,
			color = Color3.fromRGB(120, 220, 255),
			align = Enum.TextXAlignment.Center,
			dims = UDim2.new(0, 520, 0, 22),
		})
		l.AnchorPoint = Vector2.new(0.5, 1)
		l.Position = UDim2.new(0.5, 0, 1, -232)
		l.TextStrokeTransparency = 0.4
		self.haulLabel = l
	end
	self.haulLabel.Text = text or ""
end

-- A "Stop hauling" button (for touch screens and anyone who prefers clicking).
function Hud:setHaulStop(visible: boolean, onStop: () -> ())
	if not self.haulStop then
		local button = Instance.new("TextButton")
		button.Name = "StopHauling"
		button.AnchorPoint = Vector2.new(0.5, 1)
		button.Position = UDim2.new(0.5, 0, 1, -262)
		button.Size = UDim2.fromOffset(180, 40)
		button.BackgroundColor3 = Color3.fromRGB(150, 60, 40)
		button.TextColor3 = Color3.new(1, 1, 1)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 18
		button.Text = "Stop hauling"
		button.Visible = false
		button.Parent = self.gui
		corner(button, 8)
		self.haulStop = button
	end
	self.haulStopHandler = onStop
	if not self.haulStopWired then
		self.haulStopWired = true
		self.haulStop.Activated:Connect(function()
			if self.haulStopHandler then
				self.haulStopHandler()
			end
		end)
	end
	self.haulStop.Visible = visible
end

function Hud:setHint(text: string?)
	text = text or ""
	if self.hintLabel.Text ~= text then
		self.hintLabel.Text = text
	end
end

function Hud:banner(title: string, subtitle: string)
	self.bannerToken += 1
	local token = self.bannerToken
	local banner = self.bannerLabel
	banner.Text = title .. "\n" .. subtitle
	banner.TextTransparency = 0
	banner.TextStrokeTransparency = 0.5
	task.delay(3, function()
		if self.bannerToken ~= token then
			return
		end
		TweenService:Create(banner, TweenInfo.new(1), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end

function Hud:toast(text: string, kind: string?)
	self.toastToken += 1
	local token = self.toastToken
	local toast = self.toastLabel
	toast.Text = text
	toast.BackgroundColor3 = COLORS[kind or "info"] or COLORS.info
	toast.BackgroundTransparency = 0.1
	toast.TextTransparency = 0

	task.delay(4, function()
		if self.toastToken ~= token then
			return
		end
		local info = TweenInfo.new(0.6)
		TweenService:Create(toast, info, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
	end)
end

-- A big, coloured message every player sees (rare spawns, nightfall, dawn).
function Hud:announce(title: string, subtitle: string, rarity: string?)
	self.announceCount += 1
	local tier = rarity and Config.RarityById[rarity]
	local color = if tier then tier.color else Color3.fromRGB(255, 214, 120)

	local card = Instance.new("Frame")
	card.Name = "Announcement"
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = COLORS.panel
	card.BackgroundTransparency = 0.2
	card.LayoutOrder = -self.announceCount -- newest on top
	card.Parent = self.announcements
	corner(card, 8)
	padding(card, 8)
	vlist(card, 2)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Parent = card

	local titleLabel = label(card, { text = title, font = Enum.Font.GothamBlack, size = 22, color = color, align = Enum.TextXAlignment.Center, order = 1 })
	titleLabel.TextStrokeTransparency = 0.4
	local subtitleLabel = label(card, { text = subtitle, font = Enum.Font.GothamBold, size = 16, align = Enum.TextXAlignment.Center, order = 2 })
	subtitleLabel.TextWrapped = true
	subtitleLabel.AutomaticSize = Enum.AutomaticSize.Y

	-- Keep at most three on screen.
	local cards = {}
	for _, child in self.announcements:GetChildren() do
		if child:IsA("Frame") then
			table.insert(cards, child)
		end
	end
	table.sort(cards, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for index = 4, #cards do
		cards[index]:Destroy()
	end

	task.delay(Config.Announce.Seconds, function()
		if not card.Parent then
			return
		end
		local info = TweenInfo.new(0.8)
		TweenService:Create(card, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		TweenService:Create(titleLabel, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(subtitleLabel, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.8)
		card:Destroy()
	end)
end

-- fraction 0..1; sprinting and exhausted change the colour. Hidden while full and idle.
function Hud:setStamina(fraction: number, sprinting: boolean, exhausted: boolean)
	fraction = math.clamp(fraction, 0, 1)
	local fill = self.staminaFill :: Frame
	TweenService:Create(fill, TweenInfo.new(0.12), { Size = UDim2.fromScale(fraction, 1) }):Play()
	fill.BackgroundColor3 = if exhausted
		then STAMINA_COLORS.exhausted
		elseif sprinting then STAMINA_COLORS.sprinting
		else STAMINA_COLORS.normal

	local visible = sprinting or fraction < 0.999
	if visible == self.staminaVisible then
		return
	end
	self.staminaVisible = visible
	local info = TweenInfo.new(if visible then 0.15 else 0.8)
	TweenService:Create(self.staminaFrame, info, { BackgroundTransparency = if visible then 0.35 else 1 }):Play()
	TweenService:Create(self.staminaStroke, info, { Transparency = if visible then 0.2 else 1 }):Play()
	TweenService:Create(fill, info, { BackgroundTransparency = if visible then 0 else 1 }):Play()
end

function Hud:setNightTimer(text: string, urgent: boolean)
	self.nightLabel.Text = text
	self.nightLabel.TextColor3 = if urgent then Color3.fromRGB(255, 200, 90) else COLORS.muted
end

function Hud:showDevHint(text: string)
	local hint = label(self.gui, { text = text, size = 12, color = COLORS.muted, dims = UDim2.new(0, 460, 0, 16) })
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.new(0, 12, 1, -8)
	hint.TextStrokeTransparency = 0.5
end

return Hud
