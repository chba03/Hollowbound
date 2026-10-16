--[[
	Presentation only: save badge, zone label, compact pack list, loadout bar, relic
	menu, and messages. It renders whatever the server sends (RelicView.state) and asks
	the server to act through the request function given to Hud.new. It never decides
	game state; buttons that look available can still be refused by the server, which
	then explains why.

	Input: buttons work with mouse, touch, and controller selection; keys and controller
	buttons reach the same handlers through Actions.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Actions = require(script.Parent.Actions)

local COLORS = {
	panel = Color3.fromRGB(20, 22, 28),
	row = Color3.fromRGB(34, 37, 46),
	text = Color3.fromRGB(235, 235, 240),
	muted = Color3.fromRGB(150, 155, 170),
	unsecured = Color3.fromRGB(240, 150, 60),
	registered = Color3.fromRGB(90, 200, 120),
	needsService = Color3.fromRGB(235, 90, 90),
	button = Color3.fromRGB(58, 64, 82),
	buttonPrimary = Color3.fromRGB(60, 110, 170),
	slot = Color3.fromRGB(30, 33, 42),
	mock = Color3.fromRGB(150, 80, 190),
	info = Color3.fromRGB(60, 65, 80),
	success = Color3.fromRGB(40, 110, 70),
	error = Color3.fromRGB(130, 45, 45),
}

local SAVE_COLORS = {
	Saved = COLORS.registered,
	Saving = COLORS.unsecured,
	Pending = COLORS.muted,
	Retrying = COLORS.needsService,
	Loading = COLORS.muted,
	Lost = COLORS.needsService,
	Failed = COLORS.needsService,
	None = COLORS.muted,
}

local ZONE_TEXT = {
	Town = "Town",
	Camp = "Camp: refuge (relics stay unsecured)",
	Depths = "Exploring",
}

local SLOT_ACTIONS = { "UseSlot1", "UseSlot2", "UseSlot3" }

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
	l.TextWrapped = props.wrap == true
	l.Text = props.text or ""
	l.Size = props.dims or UDim2.new(1, 0, 0, (props.size or 14) + 4)
	if props.wrap then
		l.AutomaticSize = Enum.AutomaticSize.Y
	end
	l.LayoutOrder = props.order or 0
	l.Name = props.name or "Label"
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

local function list(parent: Instance, gap: number, horizontal: boolean?)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	if horizontal then
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	layout.Parent = parent
	return layout
end

-- Buttons are at least 40 px tall (before scaling) so they are usable by touch.
local function button(parent: Instance, name: string, text: string, onActivated: () -> (), props): TextButton
	props = props or {}
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextSize = props.size or 14
	b.TextColor3 = COLORS.text
	b.BackgroundColor3 = props.color or COLORS.button
	b.AutoButtonColor = true
	b.Selectable = true
	b.Size = props.dims or UDim2.fromOffset(110, 40)
	b.AutomaticSize = props.autoX and Enum.AutomaticSize.X or Enum.AutomaticSize.None
	b.LayoutOrder = props.order or 0
	b.TextTransparency = if props.dim then 0.45 else 0
	b.BackgroundTransparency = if props.dim then 0.4 else 0
	b.Parent = parent
	corner(b, 6)
	if props.autoX then
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, 12)
		p.PaddingRight = UDim.new(0, 12)
		p.Parent = b
	end
	b.Activated:Connect(onActivated)
	return b
end

function Hud.new(playerGui: PlayerGui, request: (string, ...any) -> ())
	local self = setmetatable({}, Hud)
	self.request = request
	self.state = { relics = {}, slots = {}, cooldowns = {}, save = { state = "Loading", text = "Loading...", mode = "" } }
	self.cooldownEnds = {}
	self.cooldownTotals = {}
	self.menuOpen = false
	self.pickingFor = nil
	self.scales = {}

	local gui = Instance.new("ScreenGui")
	gui.Name = "HollowboundHud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	self.gui = gui

	local function scaled(object: GuiObject)
		local s = Instance.new("UIScale")
		s.Parent = object
		table.insert(self.scales, s)
	end

	-- Save badge (top left)
	local badge = Instance.new("Frame")
	badge.Name = "SaveBadge"
	badge.Position = UDim2.fromOffset(16, 16)
	badge.Size = UDim2.fromOffset(0, 30)
	badge.AutomaticSize = Enum.AutomaticSize.X
	badge.BackgroundColor3 = COLORS.panel
	badge.BackgroundTransparency = 0.15
	badge.Parent = gui
	corner(badge, 15)
	local badgePad = Instance.new("UIPadding")
	badgePad.PaddingLeft = UDim.new(0, 12)
	badgePad.PaddingRight = UDim.new(0, 12)
	badgePad.Parent = badge
	self.saveLabel = label(badge, { text = "Loading...", font = Enum.Font.GothamBold, size = 14, dims = UDim2.new(0, 0, 1, 0) })
	self.saveLabel.AutomaticSize = Enum.AutomaticSize.X
	scaled(badge)
	self.badge = badge

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

	-- Compact pack list (top right), the status view used since milestone 1.
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
	list(panel, 6)
	label(panel, { text = "PACK: RELICS", font = Enum.Font.GothamBold, size = 14, order = 0 })
	local packList = Instance.new("Frame")
	packList.Name = "List"
	packList.BackgroundTransparency = 1
	packList.Size = UDim2.new(1, 0, 0, 0)
	packList.AutomaticSize = Enum.AutomaticSize.Y
	packList.LayoutOrder = 1
	packList.Parent = panel
	list(packList, 6)
	scaled(panel)
	self.pack = panel
	self.packList = packList

	-- Loadout bar (bottom center)
	local bar = Instance.new("Frame")
	bar.Name = "Loadout"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -16)
	bar.Size = UDim2.fromOffset(0, 96)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.BackgroundTransparency = 1
	bar.Parent = gui
	list(bar, 8, true)
	scaled(bar)
	self.slotButtons = {}
	for slot = 1, Config.Loadout.Slots do
		self.slotButtons[slot] = self:_makeSlot(bar, slot)
	end
	self.relicsButton = button(bar, "RelicsButton", "Relics", function()
		Actions.run("ToggleRelics")
	end, { dims = UDim2.fromOffset(96, 96), order = 100, color = COLORS.buttonPrimary })
	self.bar = bar

	-- Relic menu (center), hidden until opened
	local menu = Instance.new("Frame")
	menu.Name = "RelicMenu"
	menu.AnchorPoint = Vector2.new(0.5, 0.5)
	menu.Position = UDim2.fromScale(0.5, 0.48)
	menu.Size = UDim2.fromOffset(480, 520)
	menu.BackgroundColor3 = COLORS.panel
	menu.BackgroundTransparency = 0.05
	menu.Visible = false
	menu.Parent = gui
	corner(menu, 10)
	padding(menu, 12)
	scaled(menu)
	self.menu = menu

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 40)
	header.Parent = menu
	label(header, { text = "RELICS", font = Enum.Font.GothamBold, size = 18, dims = UDim2.new(1, -120, 1, 0) })
	self.closeButton = button(header, "CloseMenu", "Close", function()
		self:setMenuOpen(false)
	end, { dims = UDim2.fromOffset(110, 40) })
	self.closeButton.AnchorPoint = Vector2.new(1, 0)
	self.closeButton.Position = UDim2.new(1, 0, 0, 0)

	self.menuInfo = label(menu, { text = "", size = 13, color = COLORS.muted, wrap = true })
	self.menuInfo.Position = UDim2.fromOffset(0, 44)
	self.menuInfo.Size = UDim2.new(1, 0, 0, 0)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Cards"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 104)
	scroll.Size = UDim2.new(1, 0, 1, -104)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 8
	scroll.Selectable = false
	scroll.Parent = menu
	list(scroll, 8)
	self.cards = scroll

	-- Message toast (above the loadout bar)
	local toast = label(gui, {
		text = "",
		size = 16,
		align = Enum.TextXAlignment.Center,
		dims = UDim2.new(0, 520, 0, 0),
	})
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 1, -130)
	toast.AutomaticSize = Enum.AutomaticSize.Y
	toast.TextWrapped = true
	toast.BackgroundTransparency = 1
	toast.TextTransparency = 1
	toast.BackgroundColor3 = COLORS.info
	toast.ZIndex = 10
	corner(toast, 8)
	padding(toast, 10)
	scaled(toast)
	self.toastLabel = toast
	self.toastToken = 0

	-- Readable scaling for small and large screens.
	local function rescale()
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		local s = math.clamp(viewport.Y / 720, 0.75, 1.35)
		for _, uiScale in self.scales do
			uiScale.Scale = s
		end
		local menuHeight = math.clamp((viewport.Y * 0.78) / s, 300, 640)
		local menuWidth = math.min(480, (viewport.X * 0.94) / s)
		menu.Size = UDim2.fromOffset(menuWidth, menuHeight)
	end
	rescale()
	local function watchCamera()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
		end
	end
	watchCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		watchCamera()
		rescale()
	end)

	Actions.inputChanged:Connect(function()
		self:_refreshHints()
	end)
	RunService.RenderStepped:Connect(function()
		self:_updateCooldowns()
	end)

	self:setState(self.state)
	return self
end

function Hud:_makeSlot(parent: Instance, slot: number)
	local b = Instance.new("TextButton")
	b.Name = "Slot" .. slot
	b.Text = ""
	b.AutoButtonColor = true
	b.Selectable = true
	b.BackgroundColor3 = COLORS.slot
	b.BackgroundTransparency = 0.1
	b.Size = UDim2.fromOffset(116, 96)
	b.LayoutOrder = slot
	b.ClipsDescendants = true
	b.Parent = parent
	corner(b, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = COLORS.button
	stroke.Parent = b

	local hint = label(b, { text = "", size = 12, color = COLORS.muted, dims = UDim2.new(1, -8, 0, 16), name = "Hint" })
	hint.Position = UDim2.fromOffset(6, 4)
	local nameLabel = label(b, {
		text = "Empty",
		font = Enum.Font.GothamBold,
		size = 13,
		align = Enum.TextXAlignment.Center,
		dims = UDim2.new(1, -8, 0, 32),
		name = "RelicName",
	})
	nameLabel.TextWrapped = true
	nameLabel.Position = UDim2.fromOffset(4, 20)
	local charges = label(b, { text = "", size = 14, align = Enum.TextXAlignment.Center, dims = UDim2.new(1, 0, 0, 18), name = "Charges" })
	charges.Position = UDim2.fromOffset(0, 52)
	local status = label(b, { text = "", size = 11, align = Enum.TextXAlignment.Center, dims = UDim2.new(1, -6, 0, 18), name = "Status" })
	status.Position = UDim2.fromOffset(3, 72)
	status.TextTruncate = Enum.TextTruncate.AtEnd

	local overlay = Instance.new("Frame")
	overlay.Name = "Cooldown"
	overlay.AnchorPoint = Vector2.new(0, 1)
	overlay.Position = UDim2.fromScale(0, 1)
	overlay.Size = UDim2.fromScale(1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.45
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 3
	overlay.Parent = b

	b.Activated:Connect(function()
		Actions.run(SLOT_ACTIONS[slot])
	end)
	return { button = b, stroke = stroke, hint = hint, name = nameLabel, charges = charges, status = status, overlay = overlay }
end

local function chargePips(charges: number, maxCharges: number): string
	if maxCharges <= 0 then
		return ""
	end
	return string.rep("●", charges) .. string.rep("○", math.max(0, maxCharges - charges))
end

function Hud:_relicById(id: string)
	for _, relic in self.state.relics do
		if relic.id == id then
			return relic
		end
	end
	return nil
end

function Hud:_cooldownLeft(abilityId: string): number
	local ends = self.cooldownEnds[abilityId]
	return if ends then math.max(0, ends - os.clock()) else 0
end

function Hud:_updateCooldowns()
	for slot, ui in self.slotButtons do
		local relic = self:_relicById(self.state.slots[slot] or "")
		local left = if relic and relic.abilityId ~= "" then self:_cooldownLeft(relic.abilityId) else 0
		local total = relic and self.cooldownTotals[relic.abilityId] or 0
		ui.overlay.Size = UDim2.fromScale(1, if total > 0 then math.clamp(left / total, 0, 1) else 0)
		if not relic then
			ui.status.Text = ""
		elseif relic.blocker ~= "" then
			ui.status.Text = relic.blocker
			ui.status.TextColor3 = COLORS.needsService
		elseif left > 0 then
			ui.status.Text = string.format("%.1f s", left)
			ui.status.TextColor3 = COLORS.muted
		else
			ui.status.Text = "Ready"
			ui.status.TextColor3 = COLORS.registered
		end
	end
end

function Hud:_refreshHints()
	for slot, ui in self.slotButtons do
		ui.hint.Text = Actions.hint(SLOT_ACTIONS[slot])
	end
	local toggle = Actions.hint("ToggleRelics")
	self.relicsButton.Text = if toggle ~= "" then `Relics\n[{toggle}]` else "Relics"
	local close = Actions.hint("CloseMenu")
	self.closeButton.Text = if close ~= "" and Actions.inputKind() == "Gamepad" then `Close [{close}]` else "Close"
end

function Hud:_renderPack()
	for _, child in self.packList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local relics = self.state.relics
	if #relics == 0 then
		label(self.packList, { text = "No relics carried.", color = COLORS.muted, order = 1 })
		return
	end
	for index, item in relics do
		local row = Instance.new("Frame")
		row.Name = "Relic_" .. item.id
		row.BackgroundColor3 = COLORS.row
		row.Size = UDim2.new(1, 0, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.LayoutOrder = index
		row.Parent = self.packList
		corner(row, 6)
		padding(row, 8)
		list(row, 2)

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
		if item.service == "Needs service" then
			label(row, { text = "NEEDS SERVICE", font = Enum.Font.GothamBold, size = 12, color = COLORS.needsService, order = 4 })
		else
			label(row, { text = item.service, size = 12, color = COLORS.muted, order = 4 })
		end
		local slotText = if item.equippedSlot > 0 then `Slot {item.equippedSlot}` else "Not equipped"
		local chargeText = if item.maxCharges > 0 then `  ·  Charges {item.charges}/{item.maxCharges}` else ""
		label(row, { text = slotText .. chargeText, size = 12, color = COLORS.muted, order = 5 })
		label(row, { text = "ID " .. string.sub(item.id, 1, 8), size = 11, color = COLORS.muted, order = 100 })
	end
end

function Hud:_renderSlots()
	for slot, ui in self.slotButtons do
		local relic = self:_relicById(self.state.slots[slot] or "")
		if relic then
			ui.name.Text = relic.name
			ui.charges.Text = chargePips(relic.charges, relic.maxCharges)
			ui.stroke.Color = rarityColor(relic.rarity)
		else
			ui.name.Text = "Empty"
			ui.charges.Text = ""
			ui.stroke.Color = COLORS.button
		end
	end
	self:_updateCooldowns()
end

function Hud:_slotSummary(slot: number): string
	local relic = self:_relicById(self.state.slots[slot] or "")
	return if relic then `Slot {slot}: {relic.name}` else `Slot {slot}: empty`
end

function Hud:_renderMenu()
	local selected = GuiService.SelectedObject
	local selectedName = if selected and selected:IsDescendantOf(self.menu) then selected.Name else nil

	for _, child in self.cards:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local exceptionalUsed = 0
	for slot = 1, Config.Loadout.Slots do
		local relic = self:_relicById(self.state.slots[slot] or "")
		if relic and relic.slotClass == "Exceptional" then
			exceptionalUsed += 1
		end
	end
	local exceptionalMax = (self.state.maxPerClass or {}).Exceptional or 0
	local deskText = if self.state.atDesk
		then "At a town desk: Appraise and Activate are available."
		else "Appraise and Activate at a registry terminal or service station in town."
	self.menuInfo.Text = `{Config.Loadout.Slots} slots, exceptional {exceptionalUsed}/{exceptionalMax} used. {deskText}`

	if #self.state.relics == 0 then
		label(self.cards, { text = "You are not carrying any relics.", color = COLORS.muted })
	end

	for index, item in self.state.relics do
		local card = Instance.new("Frame")
		card.Name = "Card_" .. item.id
		card.BackgroundColor3 = COLORS.row
		card.Size = UDim2.new(1, -10, 0, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.LayoutOrder = index
		card.Parent = self.cards
		corner(card, 8)
		padding(card, 10)
		list(card, 3)

		local title = label(card, { text = item.name, font = Enum.Font.GothamBold, size = 16, order = 1, dims = UDim2.new(1, 0, 0, 20) })
		label(title, {
			text = `{item.rarity} · {item.slotClass}`,
			font = Enum.Font.GothamBold,
			size = 13,
			color = rarityColor(item.rarity),
			align = Enum.TextXAlignment.Right,
			dims = UDim2.fromScale(1, 1),
		})
		local securityColor = if item.security == "Registered" then COLORS.registered else COLORS.unsecured
		label(card, { text = string.upper(item.security), font = Enum.Font.GothamBold, size = 12, color = securityColor, order = 2 })
		label(card, { text = `{item.appraisal}  ·  {item.activation}`, size = 13, order = 3 })
		label(card, {
			text = `{item.service}  ·  Charges {item.charges}/{item.maxCharges}`,
			size = 13,
			color = if item.service == "Needs service" then COLORS.needsService else COLORS.text,
			order = 4,
		})
		if item.abilityName ~= "" then
			label(card, { text = `{item.abilityName}: {item.abilityText}`, size = 12, color = COLORS.muted, wrap = true, order = 5 })
		end
		if item.blocker ~= "" then
			label(card, { text = "Cannot use: " .. item.blocker, size = 12, color = COLORS.needsService, order = 6 })
		end
		if item.traits then
			for i, trait in item.traits do
				label(card, { text = `{trait.label}: {trait.value} {trait.unit}`, size = 12, order = 10 + i })
			end
		else
			label(card, { text = "Traits hidden until appraised.", size = 12, color = COLORS.muted, order = 10 })
		end
		label(card, {
			text = (if item.equippedSlot > 0 then `Equipped in slot {item.equippedSlot}` else "Not equipped") .. `  ·  ID {string.sub(item.id, 1, 8)}`,
			size = 11,
			color = COLORS.muted,
			order = 40,
		})

		local row = Instance.new("Frame")
		row.Name = "Buttons"
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.LayoutOrder = 50
		row.Parent = card
		local rowLayout = list(row, 6, true)
		rowLayout.Wraps = true

		if self.pickingFor == item.id then
			for slot = 1, Config.Loadout.Slots do
				button(row, `Pick{slot}_{item.id}`, self:_slotSummary(slot), function()
					self.pickingFor = nil
					self.request("Equip", item.id, slot)
				end, { autoX = true, order = slot, color = COLORS.buttonPrimary })
			end
			button(row, `Cancel_{item.id}`, "Cancel", function()
				self.pickingFor = nil
				self:_renderMenu()
			end, { order = 10 })
		else
			if item.equippedSlot > 0 then
				button(row, `Unequip_{item.id}`, "Unequip", function()
					self.request("Unequip", item.equippedSlot)
				end, { order = 1 })
			else
				button(row, `Equip_{item.id}`, "Equip", function()
					self.pickingFor = item.id
					self:_renderMenu()
					local first = self.cards:FindFirstChild(`Pick1_{item.id}`, true)
					if first and Actions.inputKind() == "Gamepad" then
						GuiService.SelectedObject = first
					end
				end, { order = 1, color = COLORS.buttonPrimary })
			end
			if item.appraisal == "Unappraised" then
				button(row, `Appraise_{item.id}`, "Appraise", function()
					self.request("Appraise", item.id)
				end, { order = 2, dim = not self.state.atDesk })
			end
			if item.needsActivation then
				button(row, `Activate_{item.id}`, "Activate", function()
					self.request("Activate", item.id)
				end, { order = 3, dim = not self.state.atDesk })
			end
		end
	end

	-- Keep controller selection on the same button after a refresh.
	if self.menuOpen and selectedName then
		local again = self.menu:FindFirstChild(selectedName, true)
		GuiService.SelectedObject = if again and again:IsA("GuiButton") then again else self.closeButton
	end
end

function Hud:setState(state)
	local previousSave = self.state.save and self.state.save.state
	self.state = state
	state.relics = state.relics or {}
	state.slots = state.slots or {}

	local now = os.clock()
	for abilityId, remaining in state.cooldowns or {} do
		local ends = now + remaining
		local old = self.cooldownEnds[abilityId]
		if not old or ends > old + 0.25 then
			self.cooldownTotals[abilityId] = remaining
		end
		self.cooldownEnds[abilityId] = ends
	end
	for abilityId in self.cooldownEnds do
		if not (state.cooldowns or {})[abilityId] then
			self.cooldownEnds[abilityId] = nil
		end
	end

	local save = state.save or { state = "None", text = "", mode = "" }
	self.saveLabel.Text = "● " .. (save.text or "")
	self.saveLabel.TextColor3 = SAVE_COLORS[save.state] or COLORS.text
	self.badge.BackgroundColor3 = if save.mode == "StudioMock" or save.mode == "TestMock" then COLORS.mock else COLORS.panel
	if previousSave == "Saving" and save.state == "Saved" then
		self:toast("Saved to your profile.", "success")
	end

	if self.pickingFor and not self:_relicById(self.pickingFor) then
		self.pickingFor = nil
	end
	self:_renderPack()
	self:_renderSlots()
	self:_refreshHints()
	if self.menuOpen then
		self:_renderMenu()
	end
end

function Hud:setMenuOpen(open: boolean)
	self.menuOpen = open
	self.menu.Visible = open
	self.pickingFor = nil
	-- While the menu is open, the D-pad navigates the menu instead of using slots.
	for _, name in SLOT_ACTIONS do
		Actions.setBound(name, not open)
	end
	Actions.setBound("CloseMenu", open)
	if open then
		self:_renderMenu()
		if Actions.inputKind() == "Gamepad" then
			local first = self.cards:FindFirstChildWhichIsA("Frame")
			local firstButton = first and first:FindFirstChildWhichIsA("GuiButton", true)
			GuiService.SelectedObject = firstButton or self.closeButton
		end
	elseif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.gui) then
		GuiService.SelectedObject = nil
	end
end

function Hud:toggleMenu()
	self:setMenuOpen(not self.menuOpen)
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

-- Adds a big button to the loadout bar (milestone 4: Attack, Heal). Returns it.
function Hud:addBarButton(name: string, text: string, order: number, onActivated: () -> ()): TextButton
	return button(self.bar, name, text, onActivated, { dims = UDim2.fromOffset(96, 96), order = order, size = 15 })
end

function Hud:showDevHint(text: string)
	local hint = label(self.gui, { text = text, size = 12, color = COLORS.muted, dims = UDim2.new(0, 560, 0, 16) })
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.new(0, 12, 1, -8)
	hint.TextStrokeTransparency = 0.5
end

return Hud
