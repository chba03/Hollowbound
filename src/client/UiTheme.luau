--[[
	The steampunk / medieval look for menus: brass frames with rivets, dark walnut
	panels, a riveted leather header, parchment ribbons, verdigris (green patina) buy
	buttons, and turning gears. Pure presentation helpers; no game state.

	Fonts: Fondamento (calligraphic) for titles, bold Merriweather (a book serif) for
	labels and numbers.
]]

local TweenService = game:GetService("TweenService")

local Theme = {}

Theme.Colors = {
	brassLight = Color3.fromRGB(236, 196, 112),
	brass = Color3.fromRGB(196, 150, 68),
	brassDark = Color3.fromRGB(116, 80, 34),
	copper = Color3.fromRGB(178, 104, 58),
	copperDark = Color3.fromRGB(104, 54, 28),
	walnut = Color3.fromRGB(48, 32, 22),
	walnutLight = Color3.fromRGB(68, 46, 30),
	leather = Color3.fromRGB(84, 48, 30),
	leatherDark = Color3.fromRGB(52, 28, 18),
	parchment = Color3.fromRGB(236, 218, 172),
	parchmentDark = Color3.fromRGB(196, 168, 112),
	ink = Color3.fromRGB(46, 30, 18),
	patina = Color3.fromRGB(78, 160, 116),
	patinaDark = Color3.fromRGB(36, 92, 66),
	ember = Color3.fromRGB(255, 170, 70),
	outline = Color3.fromRGB(24, 14, 8),
	text = Color3.fromRGB(250, 238, 210),
}
local C = Theme.Colors

Theme.TitleFont = Font.fromEnum(Enum.Font.Fondamento)
Theme.BodyFont = Font.new(Font.fromEnum(Enum.Font.Merriweather).Family, Enum.FontWeight.Bold)

Theme.ROBUX = utf8.char(0xE002) -- Roblox's own Robux symbol

function Theme.corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

function Theme.stroke(parent: Instance, thickness: number, color: Color3?, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or C.outline
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

-- A vertical gradient from `top` to `bottom`.
function Theme.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

-- Polished brass: light band near the top, darker below.
function Theme.brassGradient(parent: Instance)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.brassLight),
		ColorSequenceKeypoint.new(0.35, C.brass),
		ColorSequenceKeypoint.new(1, C.brassDark),
	})
	g.Rotation = 90
	g.Parent = parent
	return g
end

-- Wood grain: faint light and dark streaks across the panel.
function Theme.woodGradient(parent: Instance, base: Color3)
	local keys = {}
	local streaks = { 0, 0.08, 0.14, 0.27, 0.33, 0.48, 0.55, 0.69, 0.74, 0.88, 1 }
	for i, t in streaks do
		local shade = if i % 2 == 0 then base:Lerp(Color3.new(1, 1, 1), 0.05) else base:Lerp(Color3.new(0, 0, 0), 0.12)
		table.insert(keys, ColorSequenceKeypoint.new(t, shade))
	end
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(keys)
	g.Rotation = 4
	g.Parent = parent
	return g
end

function Theme.frame(parent: Instance, props): Frame
	local f = Instance.new("Frame")
	f.Name = props.name or "Frame"
	f.BackgroundColor3 = props.color or C.walnut
	f.BackgroundTransparency = props.transparency or 0
	f.BorderSizePixel = 0
	f.Size = props.size or UDim2.fromScale(1, 1)
	f.Position = props.position or UDim2.new()
	f.AnchorPoint = props.anchor or Vector2.zero
	f.ZIndex = props.z or 1
	f.LayoutOrder = props.order or 0
	f.Parent = parent
	return f
end

-- Text with a dark outline. font: Theme.TitleFont or Theme.BodyFont.
function Theme.text(parent: Instance, props): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = props.name or "Text"
	l.BackgroundTransparency = 1
	l.FontFace = props.font or Theme.BodyFont
	l.Text = props.text or ""
	l.TextColor3 = props.color or C.text
	l.TextScaled = props.scaled ~= false
	l.TextSize = props.textSize or 18
	l.TextXAlignment = props.align or Enum.TextXAlignment.Center
	l.Size = props.size or UDim2.fromScale(1, 1)
	l.Position = props.position or UDim2.new()
	l.AnchorPoint = props.anchor or Vector2.zero
	l.ZIndex = props.z or 2
	l.LayoutOrder = props.order or 0
	l.Parent = parent
	if props.strokeless ~= true then
		local s = Instance.new("UIStroke")
		s.Thickness = props.stroke or 2
		s.Color = props.strokeColor or C.outline
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.Parent = l
	end
	return l
end

-- A small brass rivet centred at `position`.
function Theme.rivet(parent: Instance, position: UDim2, size: number?)
	local d = size or 10
	local r = Theme.frame(parent, { name = "Rivet", size = UDim2.fromOffset(d, d), position = position, anchor = Vector2.new(0.5, 0.5), color = C.brass, z = 6 })
	Theme.corner(r, d)
	Theme.gradient(r, C.brassLight, C.brassDark, 135)
	Theme.stroke(r, 1, C.outline, 0.3)
	return r
end

-- Rivets in the four corners of `parent`, `inset` pixels in.
function Theme.cornerRivets(parent: Instance, inset: number, size: number?)
	for _, corner in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		local x = UDim.new(corner[1], if corner[1] == 0 then inset else -inset)
		local y = UDim.new(corner[2], if corner[2] == 0 then inset else -inset)
		Theme.rivet(parent, UDim2.new(x, y), size)
	end
end

-- A brass-framed panel: returns (outer frame, inner panel). The inner panel is where
-- content goes. `inner` is the panel colour (walnut by default) with wood grain.
function Theme.brassPanel(parent: Instance, props): (Frame, Frame)
	local border = props.border or 8
	local outer = Theme.frame(parent, { name = props.name or "Panel", size = props.size, position = props.position, anchor = props.anchor, color = C.brass, z = props.z, order = props.order })
	Theme.corner(outer, props.radius or 12)
	Theme.brassGradient(outer)
	Theme.stroke(outer, 3, C.outline)
	local inner = Theme.frame(outer, {
		name = "Inner",
		size = UDim2.new(1, -border * 2, 1, -border * 2),
		position = UDim2.fromOffset(border, border),
		color = props.inner or C.walnut,
		z = (props.z or 1) + 1,
	})
	Theme.corner(inner, math.max((props.radius or 12) - 4, 2))
	Theme.woodGradient(inner, props.inner or C.walnut)
	Theme.stroke(inner, 2, C.outline, 0.2)
	if props.rivets ~= false then
		Theme.cornerRivets(outer, border / 2 + 1, math.max(border - 1, 6))
	end
	return outer, inner
end

-- A turning gear, `size` pixels across. Returns the gear frame; call :spin() on the
-- returned table to keep it turning.
function Theme.gear(parent: Instance, size: number, position: UDim2, color: Color3?)
	local holder = Theme.frame(parent, { name = "Gear", size = UDim2.fromOffset(size, size), position = position, anchor = Vector2.new(0.5, 0.5), transparency = 1, z = 7 })
	local body = color or C.brass
	local teeth = 10
	for i = 0, teeth - 1 do
		local arm = Theme.frame(holder, { name = "Tooth", size = UDim2.new(0.2, 0, 1, 0), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), transparency = 1, z = 7 })
		arm.Rotation = i * 360 / teeth
		local tooth = Theme.frame(arm, { size = UDim2.fromScale(1, 0.22), color = body, z = 7 })
		Theme.corner(tooth, 2)
		Theme.stroke(tooth, 1, C.outline, 0.3)
	end
	local disc = Theme.frame(holder, { name = "Disc", size = UDim2.fromScale(0.8, 0.8), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), color = body, z = 8 })
	Theme.corner(disc, size)
	Theme.gradient(disc, body:Lerp(Color3.new(1, 1, 1), 0.25), body:Lerp(Color3.new(0, 0, 0), 0.35), 135)
	Theme.stroke(disc, 1.5, C.outline, 0.2)
	local hub = Theme.frame(holder, { name = "Hub", size = UDim2.fromScale(0.3, 0.3), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), color = C.walnut, z = 9 })
	Theme.corner(hub, size)
	Theme.stroke(hub, 1.5, C.brassDark)
	return holder
end

-- Keeps a gear turning (seconds per full turn; negative turns the other way).
function Theme.spin(gear: GuiObject, secondsPerTurn: number)
	task.spawn(function()
		while gear.Parent do
			local start = gear.Rotation
			local tween = TweenService:Create(gear, TweenInfo.new(math.abs(secondsPerTurn), Enum.EasingStyle.Linear), {
				Rotation = start + (if secondsPerTurn > 0 then 360 else -360),
			})
			tween:Play()
			tween.Completed:Wait()
		end
	end)
end

-- A clickable plaque. style: "buy" (verdigris), "brass", or "copper".
function Theme.button(parent: Instance, props): TextButton
	local style = props.style or "brass"
	local button = Instance.new("TextButton")
	button.Name = props.name or "Button"
	button.AutoButtonColor = false
	button.Text = ""
	button.Size = props.size
	button.Position = props.position or UDim2.new()
	button.AnchorPoint = props.anchor or Vector2.zero
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	button.ZIndex = props.z or 3
	button.LayoutOrder = props.order or 0
	button.Parent = parent
	Theme.corner(button, props.radius or 8)
	if style == "buy" then
		Theme.gradient(button, C.patina, C.patinaDark)
		Theme.stroke(button, 3, C.brassDark)
	elseif style == "copper" then
		Theme.gradient(button, C.copper, C.copperDark)
		Theme.stroke(button, 3, C.outline)
	else
		Theme.brassGradient(button)
		Theme.stroke(button, 3, C.outline)
	end
	local label = Theme.text(button, {
		text = props.text,
		font = props.font or Theme.BodyFont,
		size = UDim2.fromScale(0.86, 0.72),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = if style == "brass" then C.ink else C.text,
		strokeless = style == "brass",
		z = (props.z or 3) + 1,
	})
	label.Name = "Label"
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.05 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	button.Activated:Connect(function()
		scale.Scale = 0.92
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
	return button
end

-- A parchment ribbon with a title, used as a section header.
function Theme.ribbon(parent: Instance, title: string, order: number): Frame
	local holder = Theme.frame(parent, { name = "Ribbon", size = UDim2.new(1, 0, 0, 52), transparency = 1, order = order })
	for _, side in { 0, 1 } do
		-- Folded tails behind the banner.
		local tail = Theme.frame(holder, {
			size = UDim2.fromOffset(34, 30),
			position = UDim2.new(side, if side == 0 then 70 else -70, 0.5, 6),
			anchor = Vector2.new(0.5, 0.5),
			color = C.parchmentDark,
			z = 2,
		})
		tail.Rotation = if side == 0 then -8 else 8
		Theme.stroke(tail, 2, C.outline)
	end
	local band = Theme.frame(holder, {
		size = UDim2.new(1, -150, 0, 40),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = C.parchment,
		z = 3,
	})
	Theme.corner(band, 4)
	Theme.gradient(band, C.parchment, C.parchmentDark)
	Theme.stroke(band, 2.5, C.outline)
	Theme.text(band, {
		text = title,
		font = Theme.TitleFont,
		size = UDim2.fromScale(0.9, 0.82),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = C.ink,
		strokeless = true,
		z = 4,
	})
	return holder
end

return Theme
