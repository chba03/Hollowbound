--[[
	The Forge: the pickaxe menu, in the Emporium's style (brass cabinet, leather header
	with gears, parchment ribbon, leather-and-brass cards). One card per pickaxe
	(Config.Pickaxes), each with a 3D preview, its layer, and its stats. The button reads:

	  Reach layer N   locked: you haven't been that deep yet
	  $price          buy it (green when you can afford it, red when you can't)
	  Equip           owned: make it your tool
	  Equipped        your current pickaxe

	Opened from the Forge button on the left. Buy and equip go to the server (Net.ForgeBuy,
	Net.ForgeEquip), which checks everything. Presentation only.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local GrappleModel = require(Shared:WaitForChild("GrappleModel"))
local Net = require(Shared:WaitForChild("Net"))
local PickaxeModels = require(Shared:WaitForChild("PickaxeModels"))
local Progression = require(Shared:WaitForChild("Progression"))
local ShopIcons = require(script.Parent.ShopIcons)
local Theme = require(script.Parent.UiTheme)

local ForgeMenu = {}

local C = Theme.Colors
local WINDOW = Vector2.new(860, 620)
local CARD_HEIGHT = 326
local OPEN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.25)
local BUTTON = {
	buy = { C.patina, C.patinaDark },
	poor = { Color3.fromRGB(170, 60, 50), Color3.fromRGB(100, 30, 26) },
	brass = { C.brassLight, C.brassDark },
	off = { Color3.fromRGB(120, 112, 100), Color3.fromRGB(70, 64, 56) },
}

-- A pickaxe model leaning diagonally, head up, for previews.
local function preview(parent: Instance, def, size: UDim2, position: UDim2, z: number): ViewportFrame
	local model = PickaxeModels.build(def, false)
	model:PivotTo(CFrame.Angles(0, 0, math.rad(-35)) * CFrame.Angles(-math.pi / 2, 0, 0))
	local view = ShopIcons.fromModel(parent, model, size, position, z, Vector3.new(0.1, 0.15, -1))
	view.Ambient = Color3.fromRGB(200, 186, 170) -- brighter: dark woods and metals read clearly
	view.LightColor = Color3.fromRGB(255, 244, 220)
	return view
end

-- The grappling hook's preview, posed like the pickaxes.
local function grapplePreview(parent: Instance, size: UDim2, position: UDim2, z: number): ViewportFrame
	local model = GrappleModel.build(false)
	model:PivotTo(CFrame.Angles(0, 0, math.rad(-35)) * CFrame.Angles(-math.pi / 2, 0, 0))
	local view = ShopIcons.fromModel(parent, model, size, position, z, Vector3.new(0.1, 0.15, -1))
	view.Ambient = Color3.fromRGB(200, 186, 170)
	view.LightColor = Color3.fromRGB(255, 244, 220)
	return view
end

local function setButton(button: TextButton, text: string, style: string, enabled: boolean)
	local label = button:FindFirstChild("Label") :: TextLabel
	label.Text = text
	label.TextColor3 = if style == "brass" then C.ink else C.text
	local gradient = button:FindFirstChildOfClass("UIGradient") :: UIGradient
	gradient.Color = ColorSequence.new(BUTTON[style][1], BUTTON[style][2])
	button.Active = enabled
end

function ForgeMenu.start(remotes: Instance)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local buyRemote = remotes:WaitForChild(Net.ForgeBuy)
	local equipRemote = remotes:WaitForChild(Net.ForgeEquip)

	local gui = Instance.new("ScreenGui")
	gui.Name = "HollowboundForge"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 11
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	-- Forge button on the left, under the Shop button.
	local openOuter, openInner = Theme.brassPanel(gui, {
		name = "ForgeButton",
		size = UDim2.fromOffset(176, 66),
		position = UDim2.new(0, 16, 0.42, 78),
		inner = C.leather,
		border = 5,
		radius = 10,
	})
	preview(openInner, Config.Pickaxes.List[3], UDim2.fromOffset(54, 54), UDim2.new(0, 33, 0.5, 0), 4)
	Theme.text(openInner, {
		text = "Forge",
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
	openScale.Parent = openInner
	openClick.MouseEnter:Connect(function()
		TweenService:Create(openScale, TweenInfo.new(0.1), { Scale = 1.05 }):Play()
	end)
	openClick.MouseLeave:Connect(function()
		TweenService:Create(openScale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)

	local shade = Instance.new("TextButton")
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

	-- Header with gears, the title, and a copper valve close button.
	local header = Theme.frame(inner, { name = "Header", size = UDim2.new(1, 0, 0, 76), color = C.leather, z = 32 })
	Theme.corner(header, 10)
	Theme.gradient(header, C.leather, C.leatherDark)
	Theme.frame(header, { size = UDim2.new(1, 0, 0, 4), color = C.brass, z = 33 })
	Theme.frame(header, { size = UDim2.new(1, 0, 0, 4), position = UDim2.new(0, 0, 1, -4), color = C.brass, z = 33 })
	for x = 0, 12 do
		Theme.rivet(header, UDim2.new(x / 12, if x == 0 then 12 elseif x == 12 then -12 else 0, 1, -11), 7)
	end
	Theme.spin(Theme.gear(header, 58, UDim2.fromOffset(42, 36), C.copper), 10)
	Theme.spin(Theme.gear(header, 36, UDim2.fromOffset(86, 48), C.brass), -6)
	Theme.text(header, {
		text = "Forge",
		font = Theme.TitleFont,
		size = UDim2.new(0.4, 0, 0, 50),
		position = UDim2.new(0, 120, 0.5, -3),
		anchor = Vector2.new(0, 0.5),
		align = Enum.TextXAlignment.Left,
		color = C.parchment,
		stroke = 3,
		z = 34,
	})
	local equippedLabel = Theme.text(header, {
		size = UDim2.fromOffset(330, 22),
		position = UDim2.new(1, -84, 0.5, -3),
		anchor = Vector2.new(1, 0.5),
		align = Enum.TextXAlignment.Right,
		color = C.brassLight,
		z = 34,
	})
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

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(10, 86)
	scroll.Size = UDim2.new(1, -20, 1, -96)
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

	Theme.ribbon(scroll, "~ Pickaxes of the Hollow ~", 1)
	local row = Theme.frame(scroll, { name = "Cards", size = UDim2.new(1, 0, 0, 0), transparency = 1, order = 2, z = 32 })
	row.AutomaticSize = Enum.AutomaticSize.Y
	local flow = Instance.new("UIListLayout")
	flow.FillDirection = Enum.FillDirection.Horizontal
	flow.Wraps = true
	flow.Padding = UDim.new(0, 10)
	flow.HorizontalAlignment = Enum.HorizontalAlignment.Center
	flow.SortOrder = Enum.SortOrder.LayoutOrder
	flow.Parent = row

	local refreshers: { () -> () } = {}
	for index, def in Config.Pickaxes.List do
		local outer, card = Theme.brassPanel(row, {
			name = def.id,
			size = UDim2.new(1 / 3, -10, 0, CARD_HEIGHT),
			inner = C.leatherDark,
			border = 5,
			radius = 10,
			order = index,
			z = 33,
		})
		local stroke = outer:FindFirstChildOfClass("UIStroke") :: UIStroke
		local lift = Instance.new("UIScale")
		lift.Parent = card
		outer.MouseEnter:Connect(function()
			TweenService:Create(lift, TweenInfo.new(0.12), { Scale = 1.02 }):Play()
			stroke.Color = C.ember
		end)
		outer.MouseLeave:Connect(function()
			TweenService:Create(lift, TweenInfo.new(0.12), { Scale = 1 }):Play()
			stroke.Color = C.outline
		end)

		-- Forge glow behind the pickaxe.
		for _, ring in { { 150, 0.93 }, { 104, 0.9 }, { 60, 0.87 } } do
			local glow = Theme.frame(card, { size = UDim2.fromOffset(ring[1], ring[1]), position = UDim2.new(0.5, 0, 0, 74), anchor = Vector2.new(0.5, 0.5), color = def.accent or C.ember, transparency = ring[2], z = 34 })
			Theme.corner(glow, ring[1])
		end
		local view = preview(card, def, UDim2.fromOffset(170, 140), UDim2.new(0.5, 0, 0, 74), 35)

		Theme.text(card, { text = def.name, font = Theme.TitleFont, size = UDim2.new(0.94, 0, 0, 30), position = UDim2.new(0.5, 0, 0, 146), anchor = Vector2.new(0.5, 0), color = C.parchment, stroke = 2.5, z = 36 })
		Theme.text(card, { text = `Layer {def.layer}: {Config.Layers[def.layer].name}`, size = UDim2.new(0.92, 0, 0, 18), position = UDim2.new(0.5, 0, 0, 178), anchor = Vector2.new(0.5, 0), color = C.brassLight, stroke = 1.5, z = 36 })

		-- Stats plaque: damage, swings per second, reach (clear of the button below).
		local plaque = Theme.frame(card, { size = UDim2.new(1, -20, 0, 52), position = UDim2.new(0.5, 0, 0, 204), anchor = Vector2.new(0.5, 0), color = C.outline, transparency = 0.45, z = 36 })
		Theme.corner(plaque, 6)
		local stats = {
			{ "DAMAGE", Progression.formatNumber(def.damage) },
			{ "SWINGS/S", string.format("%.1f", 1 / def.cooldown) },
			{ "REACH", tostring(def.reach) },
		}
		for i, stat in stats do
			local x = (i - 0.5) / #stats
			Theme.text(plaque, { text = stat[1], size = UDim2.new(1 / #stats, -8, 0, 14), position = UDim2.new(x, 0, 0, 6), anchor = Vector2.new(0.5, 0), color = C.parchmentDark, strokeless = true, z = 37 })
			Theme.text(plaque, { text = stat[2], size = UDim2.new(1 / #stats, -8, 0, 24), position = UDim2.new(x, 0, 0, 23), anchor = Vector2.new(0.5, 0), color = C.text, stroke = 1.5, z = 37 })
		end

		local button = Theme.button(card, {
			name = "Action",
			style = "buy",
			text = "",
			size = UDim2.new(1, -24, 0, 40),
			position = UDim2.new(0.5, 0, 1, -10),
			anchor = Vector2.new(0.5, 1),
			z = 37,
		})
		local action: string? = nil
		button.Activated:Connect(function()
			if action == "buy" then
				buyRemote:FireServer(def.id)
			elseif action == "equip" then
				equipRemote:FireServer(def.id)
			end
		end)

		table.insert(refreshers, function()
			local owned = string.find("," .. (player:GetAttribute("HB_PickaxesOwned") or "") .. ",", "," .. def.id .. ",", 1, true) ~= nil
			local equipped = player:GetAttribute("HB_Pickaxe") == def.id
			local deepest = player:GetAttribute("HB_Deepest")
			local unlocked = def.layer <= 1 or (typeof(deepest) == "number" and deepest > (def.layer - 1) * Config.Hollow.LayerHeight)
			local cash = player:GetAttribute("HB_Cash")
			cash = if typeof(cash) == "number" then cash else 0
			view.ImageTransparency = if unlocked or owned then 0 else 0.55
			if equipped then
				action = nil
				setButton(button, "Equipped", "off", false)
			elseif owned then
				action = "equip"
				setButton(button, "Equip", "brass", true)
			elseif not unlocked then
				action = nil
				setButton(button, `Reach layer {def.layer}`, "off", false)
			else
				action = "buy"
				setButton(button, Progression.formatCash(def.cost), if cash >= def.cost then "buy" else "poor", true)
			end
		end)
	end

	-- Climbing gear: the grappling hook, one wide card.
	Theme.ribbon(scroll, "~ Climbing Gear ~", 3)
	do
		local def = Config.Grapple
		local _, card = Theme.brassPanel(scroll, {
			name = "Grapple",
			size = UDim2.new(1, -10, 0, 170),
			inner = C.leatherDark,
			border = 5,
			radius = 10,
			order = 4,
			z = 33,
		})
		local glow = Theme.frame(card, { size = UDim2.fromOffset(130, 130), position = UDim2.new(0, 90, 0.5, 0), anchor = Vector2.new(0.5, 0.5), color = C.ember, transparency = 0.9, z = 34 })
		Theme.corner(glow, 130)
		grapplePreview(card, UDim2.fromOffset(160, 140), UDim2.new(0, 90, 0.5, 0), 35)
		Theme.text(card, { text = def.name, font = Theme.TitleFont, size = UDim2.new(1, -200, 0, 30), position = UDim2.new(0, 180, 0, 14), color = C.parchment, stroke = 2.5, z = 36 })
		local about = Theme.text(card, {
			text = `Fell below the end of your rope? Fire the hook at the ledge ring above you and haul yourself up onto it. One use per {def.BandMeters} m of depth; it resets back in town.`,
			size = UDim2.new(1, -200, 0, 64),
			position = UDim2.new(0, 180, 0, 48),
			color = C.brassLight,
			stroke = 1.5,
			z = 36,
		})
		about.TextWrapped = true
		about.TextXAlignment = Enum.TextXAlignment.Left
		local button = Theme.button(card, {
			name = "Action",
			style = "buy",
			text = "",
			size = UDim2.new(0, 220, 0, 40),
			position = UDim2.new(1, -14, 1, -12),
			anchor = Vector2.new(1, 1),
			z = 37,
		})
		local canBuy = false
		button.Activated:Connect(function()
			if canBuy then
				buyRemote:FireServer(def.id)
			end
		end)
		table.insert(refreshers, function()
			local cash = player:GetAttribute("HB_Cash")
			cash = if typeof(cash) == "number" then cash else 0
			if player:GetAttribute("HB_HasGrapple") then
				canBuy = false
				setButton(button, "Owned", "off", false)
			else
				canBuy = true
				setButton(button, Progression.formatCash(def.cost), if cash >= def.cost then "buy" else "poor", true)
			end
		end)
	end

	local function refresh()
		for _, refreshCard in refreshers do
			refreshCard()
		end
		local def = Config.PickaxeById[player:GetAttribute("HB_Pickaxe") or ""]
		equippedLabel.Text = if def then `Wielding: {def.name} ({Progression.formatNumber(def.damage)} damage)` else ""
	end
	for _, name in { "HB_Cash", "HB_Deepest", "HB_Pickaxe", "HB_PickaxesOwned", "HB_HasGrapple" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end

	local function fit(): number
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		return math.min(1, (viewport.X - 40) / WINDOW.X, (viewport.Y - 60) / WINDOW.Y)
	end
	local blur = Instance.new("BlurEffect")
	blur.Name = "HB_ForgeBlur"
	blur.Size = 0
	blur.Parent = Lighting

	local isOpen = false
	local function setOpen(open: boolean)
		if open == isOpen then
			return
		end
		isOpen = open
		if open then
			refresh()
			shade.Visible = true
			holder.Visible = true
			scale.Scale = fit() * 0.85
			TweenService:Create(scale, OPEN, { Scale = fit() }):Play()
			TweenService:Create(shade, FADE, { BackgroundTransparency = 0.55 }):Play()
			TweenService:Create(blur, FADE, { Size = 14 }):Play()
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
	refresh()
end

return ForgeMenu
