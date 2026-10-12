--[[
	Presentation only: the pack (inventory) panel, zone label, and messages.
	It renders whatever the server sends and holds no game state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))

local COLORS = {
	panel = Color3.fromRGB(20, 22, 28),
	row = Color3.fromRGB(34, 37, 46),
	text = Color3.fromRGB(235, 235, 240),
	muted = Color3.fromRGB(150, 155, 170),
	unsecured = Color3.fromRGB(240, 150, 60),
	registered = Color3.fromRGB(90, 200, 120),
	info = Color3.fromRGB(60, 65, 80),
	success = Color3.fromRGB(40, 110, 70),
	error = Color3.fromRGB(130, 45, 45),
}

local ZONE_TEXT = {
	Town = "Town",
	Camp = "Camp: refuge (relics stay unsecured)",
	Depths = "Depths",
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
	label(panel, { text = "PACK: RELICS", font = Enum.Font.GothamBold, size = 14, order = 0 })

	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, 0, 0, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.LayoutOrder = 1
	list.Parent = panel
	vlist(list, 6)
	self.list = list

	-- Zone label (top center)
	self.zoneLabel = label(gui, {
		text = "",
		font = Enum.Font.GothamBold,
		size = 18,
		align = Enum.TextXAlignment.Center,
		dims = UDim2.new(0, 420, 0, 28),
	})
	self.zoneLabel.AnchorPoint = Vector2.new(0.5, 0)
	self.zoneLabel.Position = UDim2.new(0.5, 0, 0, 12)
	self.zoneLabel.TextStrokeTransparency = 0.4

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

function Hud:setInventory(items)
	for _, child in self.list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	if #items == 0 then
		label(self.list, { text = "No relics carried.", color = COLORS.muted, order = 1 })
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
		label(row, { text = string.upper(item.security), font = Enum.Font.GothamBold, size = 12, color = securityColor, order = 2 })
		label(row, { text = `{item.appraisal}  ·  {item.activation}`, size = 12, color = COLORS.muted, order = 3 })

		if item.traits then
			for i, trait in item.traits do
				label(row, { text = `{trait.label}: {trait.value} {trait.unit}`, size = 12, order = 3 + i })
			end
		end

		label(row, { text = "ID " .. string.sub(item.id, 1, 8), size = 11, color = COLORS.muted, order = 100 })
	end
end

function Hud:setZone(zone: string?)
	self.zoneLabel.Text = if zone then (ZONE_TEXT[zone] or zone) else ""
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

function Hud:showDevHint(text: string)
	local hint = label(self.gui, { text = text, size = 12, color = COLORS.muted, dims = UDim2.new(0, 460, 0, 16) })
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.new(0, 12, 1, -8)
	hint.TextStrokeTransparency = 0.5
end

return Hud
