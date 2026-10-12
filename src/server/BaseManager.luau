--[[
	Base management at each player's plot: relic displays, passive income, and upgrades.

	Display pipeline: carry a relic home -> register it at the plot's terminal -> use an
	empty pedestal to display your best registered relic. Only registered relics can be
	displayed, so a display never holds an unsecured find. "Take back" returns it to the
	pack. Relics on display earn cash every tick from type, rarity, and the layer they
	came from (Progression.incomeFor), never from hidden traits.

	Upgrades (rope length, climb speed, display slots) are bought by clicking the plot's upgrade
	prompts. All checks run on the server; prompts only start the request.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Perks = require(Shared:WaitForChild("Perks"))
local Progression = require(Shared:WaitForChild("Progression"))
local Characters = require(script.Parent.Characters)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local RelicModels = require(script.Parent.RelicModels)
local ServerNet = require(script.Parent.ServerNet)

local BaseManager = {}

local store
local UPGRADE_PARTS = {
	RopeLength = "UpgradeRopeLength",
	RopeSpeed = "UpgradeRopeSpeed",
	BaseSlots = "UpgradeBaseSlots",
}

local PLACE_REJECTIONS = {
	Unregistered = "Register that relic at your terminal before displaying it.",
	SlotLocked = "That pedestal is locked. Upgrade your display slots.",
	SlotTaken = "That pedestal already holds a relic.",
}

local function pedestal(plot: Model, slot: number): BasePart?
	local part = plot:FindFirstChild("Pedestal" .. slot)
	return if part and part:IsA("BasePart") then part else nil
end

local function promptOn(part: BasePart, name: string): ProximityPrompt
	local prompt = part:FindFirstChild(name)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = name
		prompt.MaxActivationDistance = 10
		prompt.HoldDuration = 0.25
		prompt.RequiresLineOfSight = false
		prompt.Parent = part
	end
	return prompt
end

-- Server check that the player owns this plot and stands close to the part.
local function canUse(player: Player, plot: Model, part: BasePart, maxDistance: number?): boolean
	if Plots.get(player) ~= plot then
		ServerNet.notify(player, "This isn't your base.", "error")
		return false
	end
	local root = Characters.liveRoot(player)
	if not root or (root.Position - part.Position).Magnitude > (maxDistance or Config.Base.InteractMaxDistance) then
		ServerNet.notify(player, "Move closer.", "error")
		return false
	end
	if not PlayerData.get(player) then
		ServerNet.notify(player, "Your data is still loading.", "error")
		return false
	end
	return true
end

-- Display visuals ---------------------------------------------------------------------

local function clearDisplay(part: BasePart)
	local existing = part:FindFirstChild("Display")
	if existing then
		existing:Destroy()
	end
end

local function showDisplay(part: BasePart, specimen)
	clearDisplay(part)

	local tier = Config.RarityById[specimen.rarity]
	local scale = (if tier then tier.scale else 1) * math.min(specimen.size or 1, Config.Sizes.MaxDisplayScale)
	local height = part.Size.Y / 2 + 1.1 * scale
	local model = RelicModels.build(specimen.typeId, specimen.rarity, CFrame.new(part.Position + Vector3.new(0, height, 0)), false, math.min(specimen.size or 1, Config.Sizes.MaxDisplayScale))
	model.Name = "Display"
	local core = model.PrimaryPart :: BasePart

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 40)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.MaxDistance = 60
	gui.Parent = core
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = if tier then tier.color:Lerp(Color3.new(1, 1, 1), 0.35) else Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	local income = Progression.incomeOf(specimen)
	label.Text = `{Progression.relicName(specimen.typeId, specimen.size)} ({specimen.rarity})\n+{Progression.formatCash(income)}/s`
	label.Parent = gui

	model.Parent = part
end

-- Updates every pedestal and upgrade prompt on a plot for its current owner.
local function refreshPlot(plot: Model)
	local owner = Plots.ownerOf(plot)
	local data = owner and PlayerData.get(owner)
	local placed = if owner then store:placed(owner.UserId) else {}
	local capacity = if data then Progression.value("BaseSlots", data.BaseSlotsLevel) else 0

	for slot = 1, Config.Base.PedestalCount do
		local part = pedestal(plot, slot)
		if not part then
			continue
		end
		local prompt = promptOn(part, "PedestalPrompt")
		local specimen = placed[slot]
		if specimen then
			showDisplay(part, specimen)
			prompt.ActionText = "Take back"
			prompt.ObjectText = Progression.relicName(specimen.typeId, specimen.size)
			prompt.Enabled = true
		else
			clearDisplay(part)
			prompt.ActionText = "Display best relic"
			prompt.ObjectText = `Pedestal {slot}`
			prompt.Enabled = data ~= nil and slot <= capacity
		end
		part.Transparency = if data and slot > capacity then 0.7 else 0
		for _, child in part:GetChildren() do
			if child:IsA("BasePart") then
				child.Transparency = part.Transparency
			end
		end
	end

	-- Upgrade boards are clickable panels drawn by the owner's client (UpgradeBoards);
	-- they read the level attributes PlayerData publishes.
end

-- Display pipeline ------------------------------------------------------------------

-- Picks the registered, carried relic with the highest income.
local function bestDisplayable(player: Player)
	local best, bestIncome = nil, -1
	for _, specimen in store:carried(player.UserId) do
		if specimen.registered then
			local income = Progression.incomeOf(specimen)
			if income > bestIncome then
				best, bestIncome = specimen, income
			end
		end
	end
	return best
end

local function hasUnregistered(player: Player): boolean
	for _, specimen in store:carried(player.UserId) do
		if not specimen.registered then
			return true
		end
	end
	return false
end

function BaseManager.usePedestal(player: Player, plot: Model, slot: number)
	local part = pedestal(plot, slot)
	if not part or not canUse(player, plot, part) then
		return
	end
	local data = PlayerData.get(player)

	local occupant = store:placed(player.UserId)[slot]
	if occupant then
		store:unplace(player.UserId, slot)
		PlayerData.setPlaced(player, slot, nil)
		ServerNet.notify(player, `Took back {Progression.relicName(occupant.typeId, occupant.size)}.`, "info")
	else
		local specimen = bestDisplayable(player)
		if not specimen then
			local text = if hasUnregistered(player)
				then "Register your relics at the terminal first. Only registered relics can be displayed."
				else "You have no relics to display. Find some in the Hollow."
			ServerNet.notify(player, text, "error")
			return
		end
		local capacity = Progression.value("BaseSlots", data.BaseSlotsLevel)
		local ok, reason = store:place(player.UserId, specimen.id, slot, capacity)
		if not ok then
			ServerNet.notify(player, PLACE_REJECTIONS[reason :: string] or "You can't display that here.", "error")
			return
		end
		PlayerData.setPlaced(player, slot, specimen.id)
		local income = Progression.incomeOf(specimen)
		ServerNet.notify(
			player,
			`Displaying {Progression.relicName(specimen.typeId, specimen.size)} (+{Progression.formatCash(income)}/s).`,
			"success"
		)
	end

	refreshPlot(plot)
	ServerNet.pushInventory(player)
end

-- Upgrades --------------------------------------------------------------------------

function BaseManager.buyUpgrade(player: Player, plot: Model, kind: string)
	local upgrade = Progression.Upgrades[kind]
	local part = plot:FindFirstChild(UPGRADE_PARTS[kind] or "")
	if not upgrade or not (part and part:IsA("BasePart")) or not canUse(player, plot, part, Config.Base.UpgradeClickDistance) then
		return
	end
	local data = PlayerData.get(player)
	local level = data[upgrade.field]
	local nextDef, nextLevel = Progression.next(kind, level)
	if not nextDef then
		ServerNet.notify(player, `{upgrade.label} is already at max level.`, "info")
		return
	end
	if not PlayerData.trySpend(player, nextDef.cost) then
		ServerNet.notify(player, `Not enough cash: {upgrade.label} costs {Progression.formatCash(nextDef.cost)}.`, "error")
		return
	end
	data[upgrade.field] = nextLevel
	PlayerData.publish(player)
	refreshPlot(plot)
	ServerNet.notify(player, `{upgrade.label} upgraded to {nextDef.value}{upgrade.unit}.`, "success")
	print(`[Hollowbound] {player.Name} bought {kind} level {nextLevel}`)
end

-- Income ----------------------------------------------------------------------------

function BaseManager.incomePerSecond(player: Player): number
	local total = 0
	for _, specimen in store:placed(player.UserId) do
		total += Progression.incomeOf(specimen)
	end
	return total * Perks.income(player) -- Double Income pass, income boost
end

local function runIncome()
	local last = os.clock()
	while true do
		task.wait(Config.Income.TickSeconds)
		local now = os.clock()
		local elapsed = now - last
		last = now
		for _, player in Players:GetPlayers() do
			if not PlayerData.get(player) then
				continue
			end
			local rate = BaseManager.incomePerSecond(player)
			player:SetAttribute("HB_Income", rate)
			if rate > 0 then
				PlayerData.addCash(player, rate * elapsed)
				PlayerData.publish(player)
			end
		end
	end
end

-- Wiring ----------------------------------------------------------------------------

local function wirePlot(plot: Model)
	for slot = 1, Config.Base.PedestalCount do
		local part = pedestal(plot, slot)
		if part then
			promptOn(part, "PedestalPrompt").Triggered:Connect(function(player)
				BaseManager.usePedestal(player, plot, slot)
			end)
		end
	end
	refreshPlot(plot)
end

function BaseManager.start(theStore)
	store = theStore

	for _, plot in Plots.all() do
		wirePlot(plot)
	end

	-- Clicks on the upgrade panels. A short cooldown absorbs double clicks.
	local lastBuy: { [Player]: number } = {}
	ServerNet.on(Net.BuyUpgrade, function(player: Player, kind: any)
		if typeof(kind) ~= "string" or not UPGRADE_PARTS[kind] then
			return
		end
		local now = os.clock()
		if now - (lastBuy[player] or 0) < 0.2 then
			return
		end
		lastBuy[player] = now
		local plot = Plots.get(player)
		if plot then
			BaseManager.buyUpgrade(player, plot, kind)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastBuy[player] = nil
	end)

	PlayerData.onLoaded(function(player)
		local plot = Plots.get(player)
		if plot then
			refreshPlot(plot)
		end
		ServerNet.pushInventory(player)
	end)

	Plots.onReleased(function(_, plot)
		-- The leaving player's relics are gone from the store; clear their visuals.
		refreshPlot(plot)
	end)

	ServerNet.on(Net.DevGrantCash, function(player)
		if PlayerData.get(player) then
			PlayerData.addCash(player, Config.Dev.CashGrant)
			PlayerData.publish(player)
			ServerNet.notify(player, `Dev: +{Progression.formatCash(Config.Dev.CashGrant)}`, "info")
		end
	end)

	task.spawn(runIncome)
end

-- Other modules call this after relic state changes that affect displays.
function BaseManager.refreshFor(player: Player)
	local plot = Plots.get(player)
	if plot then
		refreshPlot(plot)
	end
end

return BaseManager
