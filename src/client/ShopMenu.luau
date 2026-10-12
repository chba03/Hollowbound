--[[
	The store menu (the Emporium), styled to the game: a brass-framed walnut cabinet
	with a riveted leather header, turning gears, a copper valve close button, parchment
	section ribbons, and leather-and-brass item cards with 3D items (ShopIcons) lit by a
	lantern glow and light rays, green patina buy buttons, and brass category tabs.

	Cards are live: cash packs show what they pay at your current income, upgrades show
	your level (or MAXED), passes show OWNED, boosts and the Lucky Lantern show time left,
	and the weekly offer shows its stock and countdown. Clicking a price asks the server
	(Net.ShopBuy), which checks and prompts the Roblox purchase. Presentation only.
]]

local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Perks = require(Shared:WaitForChild("Perks"))
local Progression = require(Shared:WaitForChild("Progression"))
local ShopIcons = require(script.Parent.ShopIcons)
local Theme = require(script.Parent.UiTheme)

local ShopMenu = {}

local C = Theme.Colors
local shop = Config.Shop
local WINDOW = Vector2.new(940, 620)
local TAB_COLUMN = 150
local CARD_HEIGHT = 262
local ALCOVE_Y = 72 -- centre of the item display area
local OPEN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.25)
local GREY = { Color3.fromRGB(120, 112, 100), Color3.fromRGB(70, 64, 56) }

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local d, h, m, s = seconds // 86400, seconds // 3600 % 24, seconds // 60 % 60, seconds % 60
	if d > 0 then
		return string.format("%dd %dh %dm", d, h, m)
	elseif h > 0 then
		return string.format("%dh %02dm", h, m)
	end
	return string.format("%d:%02d", m, s)
end

local function duration(minutes: number): string
	return if minutes >= 60 then `{minutes // 60} hr` else `{minutes} min`
end

-- Light rays and a soft glow behind the item, fading out before the card's edges.
local function alcove(parent: Instance)
	local center = UDim2.new(0.5, 0, 0, ALCOVE_Y)
	local rays = Theme.frame(parent, { name = "Rays", size = UDim2.fromOffset(1, 1), position = center, anchor = Vector2.new(0.5, 0.5), transparency = 1, z = 3 })
	for i = 0, 9 do
		local ray = Theme.frame(rays, { size = UDim2.fromOffset(16, 170), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), color = C.ember, z = 3 })
		ray.Rotation = i * 18
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.82),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = ray
	end
	for _, ring in { { 150, 0.94 }, { 112, 0.92 }, { 78, 0.9 }, { 46, 0.88 } } do
		local glow = Theme.frame(parent, { size = UDim2.fromOffset(ring[1], ring[1]), position = center, anchor = Vector2.new(0.5, 0.5), color = C.ember, transparency = ring[2], z = 3 })
		Theme.corner(glow, ring[1])
	end
end

local function setButton(button: TextButton, text: string, enabled: boolean)
	local label = button:FindFirstChild("Label") :: TextLabel
	label.Text = text
	local gradient = button:FindFirstChildOfClass("UIGradient") :: UIGradient
	gradient.Color = if enabled then ColorSequence.new(C.patina, C.patinaDark) else ColorSequence.new(GREY[1], GREY[2])
	button.Active = enabled
	button.AutoButtonColor = false
end

type Card = { refresh: () -> () }

-- One item card. Returns a refresher that updates its live text.
local function card(parent: Instance, itemId: string, item, width: number, order: number, onBuy: (string) -> ()): Card
	local player = Players.LocalPlayer
	local outer, inner = Theme.brassPanel(parent, {
		name = itemId,
		size = UDim2.new(width, -10, 0, CARD_HEIGHT),
		inner = C.leatherDark,
		border = 5,
		radius = 10,
		order = order,
		z = 2,
	})
	local outerStroke = outer:FindFirstChildOfClass("UIStroke") :: UIStroke
	-- Hover lifts the contents inside the frame. The card itself never changes size, so
	-- its row never re-flows (a bigger card would wrap onto the next line).
	local hover = Instance.new("UIScale")
	hover.Parent = inner

	alcove(inner)
	ShopIcons.make(inner, item.icon, UDim2.fromOffset(160, 124), UDim2.new(0.5, 0, 0, ALCOVE_Y), 4)

	Theme.text(inner, {
		text = item.name,
		font = Theme.TitleFont,
		size = UDim2.new(0.94, 0, 0, 30),
		position = UDim2.new(0.5, 0, 0, 140),
		anchor = Vector2.new(0.5, 0),
		color = C.parchment,
		stroke = 2.5,
		z = 5,
	})
	-- Detail on a small dark plaque between the name and the button.
	local plaque = Theme.frame(inner, { size = UDim2.new(1, -24, 0, 26), position = UDim2.new(0.5, 0, 0, 174), anchor = Vector2.new(0.5, 0), color = C.outline, transparency = 0.45, z = 5 })
	Theme.corner(plaque, 6)
	local detail = Theme.text(plaque, {
		text = item.detail or "",
		size = UDim2.new(0.94, 0, 0.72, 0),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = C.brassLight,
		stroke = 1.5,
		z = 6,
	})

	local buy = Theme.button(inner, {
		name = "Buy",
		style = "buy",
		text = `{Theme.ROBUX} {item.price}`,
		size = UDim2.new(1, -24, 0, 42),
		position = UDim2.new(0.5, 0, 1, -10),
		anchor = Vector2.new(0.5, 1),
		z = 6,
	})
	-- A light edge along the top of the button, like polished metal.
	local shine = Theme.frame(buy, { size = UDim2.new(1, -12, 0, 3), position = UDim2.new(0.5, 0, 0, 4), anchor = Vector2.new(0.5, 0), color = Color3.new(1, 1, 1), transparency = 0.7, z = 7 })
	Theme.corner(shine, 2)
	buy.Activated:Connect(function()
		if buy.Active then
			onBuy(itemId)
		end
	end)

	local function tag(text: string, color: Color3)
		local t = Theme.frame(outer, { size = UDim2.fromOffset(132, 30), position = UDim2.new(1, -6, 0, 14), anchor = Vector2.new(1, 0.5), color = C.parchment, z = 9 })
		t.Rotation = 9
		Theme.gradient(t, C.parchment, C.parchmentDark)
		Theme.stroke(t, 2, C.outline)
		Theme.text(t, { text = text, font = Theme.TitleFont, size = UDim2.fromScale(0.86, 0.78), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), color = color, strokeless = true, z = 10 })
		Theme.rivet(t, UDim2.new(0, 9, 0.5, 0), 8)
	end
	if item.limited then
		tag("LIMITED", Color3.fromRGB(150, 40, 30))
	elseif item.tag then
		tag(item.tag, Color3.fromRGB(150, 40, 30))
	end

	-- Weekly offers: stock and countdown in the alcove's corners.
	local stockLabel, timerLabel
	if item.limited then
		stockLabel = Theme.text(inner, { size = UDim2.fromOffset(150, 22), position = UDim2.fromOffset(10, 8), color = C.ember, align = Enum.TextXAlignment.Left, z = 6 })
		timerLabel = Theme.text(inner, { size = UDim2.fromOffset(170, 20), position = UDim2.new(1, -10, 0, 40), anchor = Vector2.new(1, 0), color = C.parchment, align = Enum.TextXAlignment.Right, z = 6 })
	end

	-- Real price from Roblox once the item has an id.
	local id = item.productId or item.passId or 0
	if id > 0 then
		task.spawn(function()
			local infoType = if item.kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
			if ok and info and info.PriceInRobux then
				item.price = info.PriceInRobux
			end
		end)
	end

	outer.MouseEnter:Connect(function()
		TweenService:Create(hover, TweenInfo.new(0.12), { Scale = 1.02 }):Play()
		outerStroke.Color = C.ember
	end)
	outer.MouseLeave:Connect(function()
		TweenService:Create(hover, TweenInfo.new(0.12), { Scale = 1 }):Play()
		outerStroke.Color = C.outline
	end)

	local function refresh()
		local price = `{Theme.ROBUX} {item.price}`
		local text, enabled = price, true
		if item.kind == "cash" then
			detail.Text = `+{Progression.formatCash(Perks.cashFor(player, item.minutes, item.minimum))}  ({duration(item.minutes)} of income)`
		elseif item.kind == "level" then
			local upgrade = Progression.Upgrades[item.upgrade]
			local level = player:GetAttribute("HB_" .. upgrade.field)
			level = if typeof(level) == "number" then level else 1
			local nextDef, nextLevel = Progression.next(item.upgrade, level)
			if nextDef then
				detail.Text = `{upgrade.label}: Lv {level} > {nextLevel} ({nextDef.value}{upgrade.unit})`
			else
				detail.Text = `{upgrade.label}: Lv {level}`
				text, enabled = "MAXED", false
			end
		elseif item.kind == "pass" then
			if Perks.hasPass(player, item.perk) then
				text, enabled = "OWNED", false
			end
		elseif item.kind == "boost" then
			local left = Perks.boostLeft(player, item.boost)
			detail.Text = if left > 0 then `Active: {clock(left)} left (buy to add time)` else item.detail
		elseif item.kind == "serverLuck" then
			local left = Perks.serverLuckLeft()
			detail.Text = if left > 0 then `Lit for the server: {clock(left)} left` else item.detail
		end
		if item.limited and stockLabel and timerLabel then
			local _, rotatesIn = Perks.weeklyOffer()
			local bought = player:GetAttribute("HB_LimitedBought")
			local left = shop.Limited.Stock - (if typeof(bought) == "number" then bought else 0)
			stockLabel.Text = `Stock: {math.max(left, 0)}/{shop.Limited.Stock}`
			timerLabel.Text = `Restocks in {clock(rotatesIn)}`
			if left <= 0 then
				text, enabled = "SOLD OUT", false
			end
		end
		setButton(buy, text, enabled)
	end
	refresh()
	return { refresh = refresh }
end

function ShopMenu.start(remotes: Instance)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local buyRemote = remotes:WaitForChild(Net.ShopBuy)

	local gui = Instance.new("ScreenGui")
	gui.Name = "HollowboundShop"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	-- Shop button on the left edge.
	local openOuter, openInner = Theme.brassPanel(gui, {
		name = "ShopButton",
		size = UDim2.fromOffset(176, 66),
		position = UDim2.new(0, 16, 0.42, 0),
		inner = C.leather,
		border = 5,
		radius = 10,
	})
	ShopIcons.make(openInner, "coins", UDim2.fromOffset(58, 52), UDim2.new(0, 33, 0.5, 0), 4)
	Theme.text(openInner, {
		text = "Shop",
		font = Theme.TitleFont,
		size = UDim2.new(1, -72, 0.78, 0),
		position = UDim2.new(0, 66, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		color = C.parchment,
		stroke = 2.5,
		z = 5,
	})
	local openClick = Instance.new("TextButton")
	openClick.Text = ""
	openClick.BackgroundTransparency = 1
	openClick.Size = UDim2.fromScale(1, 1)
	openClick.ZIndex = 10
	openClick.Parent = openOuter
	local openScale = Instance.new("UIScale")
	openScale.Parent = openOuter
	openClick.MouseEnter:Connect(function()
		TweenService:Create(openScale, TweenInfo.new(0.1), { Scale = 1.06 }):Play()
	end)
	openClick.MouseLeave:Connect(function()
		TweenService:Create(openScale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)

	-- Dimmed backdrop (click to close) and the window.
	local shade = Instance.new("TextButton")
	shade.Name = "Shade"
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 1
	shade.Size = UDim2.fromScale(1, 1)
	shade.Visible = false
	shade.ZIndex = 20
	shade.Parent = gui

	local holder = Theme.frame(gui, { name = "Window", size = UDim2.fromOffset(WINDOW.X, WINDOW.Y), position = UDim2.fromScale(0.5, 0.52), anchor = Vector2.new(0.5, 0.5), transparency = 1, z = 30 })
	holder.Visible = false
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	local _, inner = Theme.brassPanel(holder, { name = "Cabinet", size = UDim2.fromScale(1, 1), border = 12, radius = 16, z = 30 })

	-- Header: riveted leather strip with gears and the title.
	local header = Theme.frame(inner, { name = "Header", size = UDim2.new(1, 0, 0, 76), color = C.leather, z = 32 })
	Theme.corner(header, 10)
	Theme.gradient(header, C.leather, C.leatherDark)
	Theme.frame(header, { size = UDim2.new(1, 0, 0, 4), color = C.brass, z = 33 })
	Theme.frame(header, { size = UDim2.new(1, 0, 0, 4), position = UDim2.new(0, 0, 1, -4), color = C.brass, z = 33 })
	for x = 0, 14 do
		Theme.rivet(header, UDim2.new(x / 14, if x == 0 then 12 elseif x == 14 then -12 else 0, 1, -11), 7)
	end
	-- Gears sit inside the header, meshing at the left.
	local bigGear = Theme.gear(header, 58, UDim2.fromOffset(42, 36), C.brass)
	local smallGear = Theme.gear(header, 36, UDim2.fromOffset(86, 48), C.copper)
	Theme.spin(bigGear, 12)
	Theme.spin(smallGear, -7.5)
	Theme.text(header, {
		text = shop.Title,
		font = Theme.TitleFont,
		size = UDim2.new(0.5, 0, 0, 50),
		position = UDim2.new(0, 120, 0.5, -3),
		anchor = Vector2.new(0, 0.5),
		align = Enum.TextXAlignment.Left,
		color = C.parchment,
		stroke = 3,
		z = 34,
	})
	local luckLabel = Theme.text(header, {
		size = UDim2.fromOffset(300, 22),
		position = UDim2.new(1, -84, 0.5, -3),
		anchor = Vector2.new(1, 0.5),
		align = Enum.TextXAlignment.Right,
		color = C.ember,
		z = 34,
	})

	-- Close: a copper valve wheel.
	local close = Theme.button(header, {
		name = "Close",
		style = "copper",
		text = "X",
		font = Theme.TitleFont,
		size = UDim2.fromOffset(52, 52),
		position = UDim2.new(1, -14, 0.5, -2),
		anchor = Vector2.new(1, 0.5),
		radius = 26,
		z = 35,
	})
	for i = 0, 3 do
		local spoke = Theme.frame(close, { size = UDim2.new(0, 4, 1, -6), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), color = C.copperDark, transparency = 0.35, z = 35 })
		spoke.Rotation = i * 45
	end
	close.MouseEnter:Connect(function()
		TweenService:Create(close, TweenInfo.new(0.25), { Rotation = 45 }):Play()
	end)
	close.MouseLeave:Connect(function()
		TweenService:Create(close, TweenInfo.new(0.25), { Rotation = 0 }):Play()
	end)

	-- Scrolling content.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Content"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(10, 86)
	scroll.Size = UDim2.new(1, -20 - TAB_COLUMN, 1, -96)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = C.brass
	scroll.ZIndex = 32
	scroll.Parent = inner
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 18)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = scroll

	local function onBuy(itemId: string)
		buyRemote:FireServer(itemId)
	end

	local cards: { Card } = {}
	local sections: { { id: string, anchor: GuiObject } } = {}
	for index, category in shop.Categories do
		local ribbon = Theme.ribbon(scroll, `~ {category.label} ~`, index * 2 - 1)
		table.insert(sections, { id = category.id, anchor = ribbon })
		local row = Theme.frame(scroll, { name = category.id, size = UDim2.new(1, 0, 0, 0), transparency = 1, order = index * 2, z = 32 })
		row.AutomaticSize = Enum.AutomaticSize.Y
		local flow = Instance.new("UIListLayout")
		flow.FillDirection = Enum.FillDirection.Horizontal
		flow.Wraps = true
		flow.Padding = UDim.new(0, 10)
		flow.HorizontalAlignment = Enum.HorizontalAlignment.Center
		flow.SortOrder = Enum.SortOrder.LayoutOrder
		flow.Parent = row
		for i, itemId in category.items do
			if itemId == "LIMITED" then
				local offer = shop.Limited.Offers[Perks.weeklyOffer()]
				table.insert(cards, card(row, offer.id, offer, 0.5, i, onBuy))
			else
				local item = shop.Items[itemId]
				if item then
					table.insert(cards, card(row, itemId, item, if item.wide then 0.5 else 1 / 3, i, onBuy))
				end
			end
		end
	end

	-- Category tabs down the right side.
	local tabs = Theme.frame(inner, { name = "Tabs", size = UDim2.new(0, TAB_COLUMN - 12, 1, -96), position = UDim2.new(1, -TAB_COLUMN + 2, 0, 86), transparency = 1, z = 32 })
	local tabList = Instance.new("UIListLayout")
	tabList.Padding = UDim.new(0, 6)
	tabList.SortOrder = Enum.SortOrder.LayoutOrder
	tabList.Parent = tabs
	local tabStrokes: { [string]: UIStroke } = {}
	local tabHeight = math.floor((WINDOW.Y - 96 - 12 - 6 * (#shop.Categories - 1)) / #shop.Categories)
	for index, category in shop.Categories do
		local tabOuter, tabInner = Theme.brassPanel(tabs, { name = category.id, size = UDim2.new(1, 0, 0, tabHeight), inner = C.leather, border = 5, radius = 10, order = index, z = 33 })
		ShopIcons.make(tabInner, category.icon, UDim2.fromOffset(64, 48), UDim2.new(0.5, 0, 0, 28), 36)
		Theme.text(tabInner, {
			text = category.label,
			font = Theme.TitleFont,
			size = UDim2.new(0.94, 0, 0, 22),
			position = UDim2.new(0.5, 0, 1, -4),
			anchor = Vector2.new(0.5, 1),
			color = C.parchment,
			z = 37,
		})
		tabStrokes[category.id] = tabOuter:FindFirstChildOfClass("UIStroke") :: UIStroke
		local click = Instance.new("TextButton")
		click.Text = ""
		click.BackgroundTransparency = 1
		click.Size = UDim2.fromScale(1, 1)
		click.ZIndex = 40
		click.Parent = tabOuter
		local tabScale = Instance.new("UIScale")
		tabScale.Parent = tabInner -- inside the frame, so the tab column never shifts
		click.MouseEnter:Connect(function()
			TweenService:Create(tabScale, TweenInfo.new(0.1), { Scale = 1.04 }):Play()
		end)
		click.MouseLeave:Connect(function()
			TweenService:Create(tabScale, TweenInfo.new(0.1), { Scale = 1 }):Play()
		end)
		click.Activated:Connect(function()
			for _, section in sections do
				if section.id == category.id then
					local target = section.anchor.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
					TweenService:Create(scroll, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { CanvasPosition = Vector2.new(0, math.max(target, 0)) }):Play()
				end
			end
		end)
	end

	local function highlight()
		local current = sections[1] and sections[1].id
		for _, section in sections do
			if section.anchor.AbsolutePosition.Y - scroll.AbsolutePosition.Y <= 60 then
				current = section.id
			end
		end
		for id, stroke in tabStrokes do
			stroke.Color = if id == current then C.ember else C.outline
			stroke.Thickness = if id == current then 4 else 3
		end
	end
	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(highlight)

	local function refreshAll()
		for _, c in cards do
			c.refresh()
		end
		local luck = Perks.serverLuckLeft()
		luckLabel.Text = if luck > 0 then `Lucky Lantern lit: {clock(luck)}` else ""
	end

	local function fit(): number
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		return math.min(1, (viewport.X - 40) / WINDOW.X, (viewport.Y - 60) / WINDOW.Y)
	end

	local blur = Instance.new("BlurEffect")
	blur.Name = "HB_ShopBlur"
	blur.Size = 0
	blur.Parent = Lighting

	local isOpen = false
	local function setOpen(open: boolean)
		if open == isOpen then
			return
		end
		isOpen = open
		if open then
			refreshAll()
			shade.Visible = true
			holder.Visible = true
			scale.Scale = fit() * 0.85
			TweenService:Create(scale, OPEN, { Scale = fit() }):Play()
			TweenService:Create(shade, FADE, { BackgroundTransparency = 0.55 }):Play()
			TweenService:Create(blur, FADE, { Size = 14 }):Play()
			highlight()
		else
			TweenService:Create(shade, FADE, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(blur, FADE, { Size = 0 }):Play()
			local shrink = TweenService:Create(scale, TweenInfo.new(0.15), { Scale = fit() * 0.85 })
			shrink:Play()
			shrink.Completed:Connect(function()
				if not isOpen then
					holder.Visible = false
					shade.Visible = false
				end
			end)
		end
	end

	openClick.Activated:Connect(function()
		setOpen(not isOpen)
	end)
	close.Activated:Connect(function()
		setOpen(false)
	end)
	shade.Activated:Connect(function()
		setOpen(false)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Escape then
			setOpen(false)
		end
	end)

	-- Live text while open: timers every second, levels and cash as they change.
	task.spawn(function()
		while true do
			task.wait(1)
			if isOpen then
				refreshAll()
			end
		end
	end)
	for _, name in { "HB_Income", "HB_RopeLengthLevel", "HB_RopeSpeedLevel", "HB_BaseSlotsLevel", "HB_LimitedBought" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			if isOpen then
				refreshAll()
			end
		end)
	end
end

return ShopMenu
