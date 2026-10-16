--[[
	Milestone 4 field HUD. Presentation only; every value comes from the server (player
	attributes, StateChanged, CombatFx) or the local Humanoid's replicated health.

	Shows: health bar, ordinary supplies and the self-rescue allowance, the current timed
	action with a progress bar, the downed overlay with bleedout countdown and rescue
	progress, creature attack warnings, hit and damage feedback. Adds Attack and Heal
	buttons to the loadout bar for touch and mouse. Hides your own revive prompt.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Actions = require(script.Parent.Actions)

local FieldHud = {}
FieldHud.__index = FieldHud

local player = Players.LocalPlayer

local ACTION_TEXT = {
	Bandage = "Bandaging",
	Revive = "Reviving",
	SelfRescue = "Using self-rescue kit",
}

local function text(parent: Instance, name: string, size: number, props)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = props and props.font or Enum.Font.GothamBold
	l.TextSize = size
	l.TextColor3 = props and props.color or Color3.fromRGB(235, 235, 240)
	l.TextStrokeTransparency = 0.4
	l.TextXAlignment = props and props.align or Enum.TextXAlignment.Left
	l.Size = props and props.dims or UDim2.new(1, 0, 0, size + 4)
	l.Text = ""
	l.Parent = parent
	return l
end

local function bar(parent: Instance, name: string, height: number, color: Color3)
	local back = Instance.new("Frame")
	back.Name = name
	back.Size = UDim2.new(1, 0, 0, height)
	back.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	back.BorderSizePixel = 0
	back.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, height // 2)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	local fillCorner = corner:Clone()
	fillCorner.Parent = fill
	return back, fill
end

function FieldHud.new(hud, request: (string) -> ())
	local self = setmetatable({}, FieldHud)
	self.hud = hud
	self.gear = { items = {}, weapon = "", selfRescuesLeft = 0 }

	local gui = Instance.new("ScreenGui")
	gui.Name = "HollowboundFieldHud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	self.gui = gui
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function rescale()
		local camera = workspace.CurrentCamera
		local y = if camera then camera.ViewportSize.Y else 720
		scale.Scale = math.clamp(y / 720, 0.75, 1.35)
	end
	rescale()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	-- Vitals panel (top left, under the save badge)
	local panel = Instance.new("Frame")
	panel.Name = "Vitals"
	panel.Position = UDim2.fromOffset(16, 56)
	panel.Size = UDim2.fromOffset(250, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	panel.BackgroundTransparency = 0.2
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	pad.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel
	self.healthText = text(panel, "HealthText", 14)
	self.healthText.LayoutOrder = 1
	local healthBack, healthFill = bar(panel, "HealthBar", 12, Color3.fromRGB(90, 200, 110))
	healthBack.LayoutOrder = 2
	self.healthFill = healthFill
	self.suppliesText = text(panel, "Supplies", 13, { font = Enum.Font.Gotham })
	self.suppliesText.LayoutOrder = 3
	self.suppliesText.TextWrapped = true
	self.suppliesText.AutomaticSize = Enum.AutomaticSize.Y

	-- Timed action progress (above the toast)
	local action = Instance.new("Frame")
	action.Name = "Action"
	action.AnchorPoint = Vector2.new(0.5, 1)
	action.Position = UDim2.new(0.5, 0, 1, -200)
	action.Size = UDim2.fromOffset(300, 40)
	action.BackgroundTransparency = 1
	action.Visible = false
	action.Parent = gui
	self.actionText = text(action, "Label", 15, { align = Enum.TextXAlignment.Center })
	local actionBack, actionFill = bar(action, "Bar", 10, Color3.fromRGB(110, 170, 240))
	actionBack.Position = UDim2.fromOffset(0, 22)
	self.actionFrame, self.actionFill = action, actionFill

	-- Downed overlay (center)
	local downed = Instance.new("Frame")
	downed.Name = "Downed"
	downed.AnchorPoint = Vector2.new(0.5, 0.5)
	downed.Position = UDim2.fromScale(0.5, 0.35)
	downed.Size = UDim2.fromOffset(420, 150)
	downed.BackgroundColor3 = Color3.fromRGB(60, 10, 10)
	downed.BackgroundTransparency = 0.35
	downed.Visible = false
	downed.Parent = gui
	local downedCorner = Instance.new("UICorner")
	downedCorner.CornerRadius = UDim.new(0, 10)
	downedCorner.Parent = downed
	self.downedTitle = text(downed, "Title", 28, { align = Enum.TextXAlignment.Center, color = Color3.fromRGB(255, 120, 110) })
	self.downedTitle.Position = UDim2.fromOffset(0, 10)
	self.downedTitle.Text = "DOWNED"
	self.downedTimer = text(downed, "Timer", 18, { align = Enum.TextXAlignment.Center })
	self.downedTimer.Position = UDim2.fromOffset(0, 46)
	self.downedHint = text(downed, "Hint", 14, { align = Enum.TextXAlignment.Center, font = Enum.Font.Gotham })
	self.downedHint.Position = UDim2.fromOffset(10, 74)
	self.downedHint.Size = UDim2.new(1, -20, 0, 36)
	self.downedHint.TextWrapped = true
	local rescueBack, rescueFill = bar(downed, "Rescue", 10, Color3.fromRGB(120, 220, 140))
	rescueBack.Position = UDim2.new(0, 20, 1, -24)
	rescueBack.Size = UDim2.new(1, -40, 0, 10)
	self.rescueBack, self.rescueFill = rescueBack, rescueFill
	self.downedFrame = downed

	-- Creature warning banner (top center, under the zone label)
	self.warning = text(gui, "Warning", 20, {
		align = Enum.TextXAlignment.Center,
		color = Color3.fromRGB(255, 110, 90),
		dims = UDim2.fromOffset(520, 28),
	})
	self.warning.AnchorPoint = Vector2.new(0.5, 0)
	self.warning.Position = UDim2.new(0.5, 0, 0, 44)
	self.warningUntil = 0

	-- Damage taken: a red edge flash
	local flash = Instance.new("Frame")
	flash.Name = "HurtFlash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.fromRGB(200, 20, 20)
	flash.BackgroundTransparency = 1
	flash.Active = false
	flash.ZIndex = 0
	flash.Parent = gui
	self.flash = flash

	-- Touch / mouse buttons on the loadout bar
	self.attackButton = hud:addBarButton("AttackButton", "Attack", 101, function()
		Actions.run("Attack")
	end)
	self.supplyButton = hud:addBarButton("SupplyButton", "Heal", 102, function()
		Actions.run("Supply")
	end)

	-- Your own revive prompt is for others; hide it locally.
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if prompt.Name == "HB_RevivePrompt" and player.Character and prompt:IsDescendantOf(player.Character) then
			prompt.Enabled = false
		end
	end)

	RunService.RenderStepped:Connect(function()
		self:_frame()
	end)
	Actions.inputChanged:Connect(function()
		self:_hints()
	end)
	self:_hints()
	return self
end

function FieldHud:_hints()
	local attack, supply = Actions.hint("Attack"), Actions.hint("Supply")
	local downed = player:GetAttribute("HB_Condition") == "Downed"
	local supplyName = if downed then "Rescue kit" else "Heal"
	self.attackButton.Text = if attack ~= "" then `Attack\n[{attack}]` else "Attack"
	self.supplyButton.Text = if supply ~= "" then `{supplyName}\n[{supply}]` else supplyName
end

function FieldHud:setGear(gear)
	if typeof(gear) ~= "table" then
		return
	end
	self.gear = gear
	local items = gear.items or {}
	local parts = {}
	table.insert(parts, if gear.weapon ~= "" then gear.weapon else "No weapon (take supplies in town)")
	table.insert(parts, `Bandages {items.Bandage or 0}/{Config.Items.Bandage.maxCarry}`)
	table.insert(parts, `Rescue kits {items.RescueKit or 0}/{Config.Items.RescueKit.maxCarry}`)
	local phase = player:GetAttribute("HB_Phase")
	if phase and phase ~= "Town" then
		table.insert(parts, `Self-rescues left this expedition: {player:GetAttribute("HB_SelfRescuesLeft") or 0}`)
	end
	self.suppliesText.Text = table.concat(parts, "\n")
end

function FieldHud:warn(message: string, seconds: number)
	self.warning.Text = message
	self.warningUntil = os.clock() + seconds
end

function FieldHud:hurt()
	self.flash.BackgroundTransparency = 0.6
	TweenService:Create(self.flash, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
end

function FieldHud:_frame()
	local now = workspace:GetServerTimeNow()

	-- Health (replicated from the server's Humanoid)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local health, maxHealth = humanoid.Health, math.max(1, humanoid.MaxHealth)
		self.healthText.Text = string.format("Health %d / %d", math.ceil(health), maxHealth)
		self.healthFill.Size = UDim2.fromScale(math.clamp(health / maxHealth, 0, 1), 1)
	end

	-- Timed action
	local actionKind = player:GetAttribute("HB_Action")
	local endsAt = player:GetAttribute("HB_ActionEndsAt")
	if actionKind and typeof(endsAt) == "number" then
		local duration = if actionKind == "Bandage"
			then Config.Items.Bandage.useTime
			elseif actionKind == "Revive" then Config.Revive.Duration
			else Config.SelfRescue.Duration
		local left = math.max(0, endsAt - now)
		self.actionFrame.Visible = true
		self.actionText.Text = string.format("%s... %.1f s  (press %s to stop)", ACTION_TEXT[actionKind] or actionKind, left, if actionKind == "Revive" then "release" else Actions.hint("Supply"))
		self.actionFill.Size = UDim2.fromScale(math.clamp(1 - left / duration, 0, 1), 1)
	else
		self.actionFrame.Visible = false
	end

	-- Downed overlay
	local condition = player:GetAttribute("HB_Condition")
	local downed = condition == "Downed"
	if downed ~= self.wasDowned then
		self.wasDowned = downed
		if humanoid then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not downed)
		end
		self:_hints()
	end
	self.downedFrame.Visible = downed
	if downed then
		local bleedoutAt = player:GetAttribute("HB_BleedoutAt")
		local left = if typeof(bleedoutAt) == "number" then math.max(0, bleedoutAt - now) else 0
		self.downedTimer.Text = string.format("Bleeding out in %d s", math.ceil(left))
		local rescuer = player:GetAttribute("HB_RescueBy")
		local rescueEnds = player:GetAttribute("HB_RescueEndsAt")
		if rescuer and typeof(rescueEnds) == "number" then
			local remaining = math.max(0, rescueEnds - now)
			self.rescueBack.Visible = true
			self.rescueFill.Size = UDim2.fromScale(math.clamp(1 - remaining / Config.Revive.Duration, 0, 1), 1)
			self.downedHint.Text = `{rescuer} is reviving you...`
		else
			self.rescueBack.Visible = false
			local kits = (self.gear.items or {}).RescueKit or 0
			local left2 = player:GetAttribute("HB_SelfRescuesLeft") or 0
			if kits > 0 and left2 > 0 then
				local hint = Actions.hint("Supply")
				self.downedHint.Text = if hint ~= "" then `Use a self-rescue kit [{hint}], or wait for another explorer.` else "Tap Rescue kit, or wait for another explorer."
			elseif kits > 0 then
				self.downedHint.Text = "Self-rescue already used this expedition. Wait for another explorer."
			else
				self.downedHint.Text = "No self-rescue kit. Wait for another explorer to revive you."
			end
		end
	end

	-- Warning banner
	self.warning.Visible = os.clock() < self.warningUntil
end

-- Server feedback (CombatFx).
function FieldHud:onCombatFx(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.kind == "Telegraph" then
		if payload.targeted then
			self:warn(`! {payload.name} is about to strike you: move away!`, payload.duration or 1)
		else
			self:warn(`! {payload.name} is winding up an attack nearby`, payload.duration or 1)
		end
	elseif payload.kind == "Hurt" then
		self:hurt()
	elseif payload.kind == "Hit" then
		self.hud:toast(if payload.killed then "Creature defeated." else `Hit: {payload.amount}`, "success")
	end
end

return FieldHud
