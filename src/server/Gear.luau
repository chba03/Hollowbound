--[[
	Ordinary items (milestone 4): starter weapon, bandages, self-rescue kits. Server only.
	Built on GearStore (pure rules: capacity, bounded refill, unique drops, atomic claims).

	- Session-only: ordinary items are never registered, protected, or saved. Leaving the
	  game loses them (prototype limitation, documented). Registered relic saving is
	  unchanged.
	- Free town supply station (any BasePart tagged Tags.SupplyStation, inside a town
	  zone) tops items up to their townRefill amounts.
	- Bandage: a server-timed, interruptible action (Busy). Taking damage cancels it and
	  consumes nothing; the bandage is consumed only when it completes.
	- Final death drops everything carried as one world-loot crate with a unique drop id,
	  placed with the same safe-ground logic as relic drops.
	- The carried weapon shows as a simple blade welded to the right hand; Combat swings it.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Busy = require(script.Parent.Busy)
local Characters = require(script.Parent.Characters)
local GearStore = require(script.Parent.GearStore)
local Guard = require(script.Parent.Guard)
local ServerNet = require(script.Parent.ServerNet)
local Vitals = require(script.Parent.Vitals)
local Zones = require(script.Parent.Zones)

local Gear = {}

local store = GearStore.new(Config.Items, Config.ItemOrder)
local lootFolder: Folder
local lootParts: { [string]: BasePart } = {}
local lootExpiry: { [string]: number } = {}
local weapons: { [Player]: { model: Model, weld: Weld, baseC0: CFrame } } = {}

function Gear.store()
	return store
end

function Gear.contents(player: Player)
	return store:contents(player.UserId)
end

-- (itemId, def) of the carried weapon, or nil.
function Gear.weapon(player: Player)
	local itemId = store:weapon(player.UserId)
	return itemId, itemId and Config.Items[itemId]
end

function Gear.weaponVisual(player: Player)
	return weapons[player]
end

local function describe(items): string
	local parts = {}
	for _, itemId in Config.ItemOrder do
		local count = items[itemId]
		if count and count > 0 then
			table.insert(parts, `{Config.Items[itemId].displayName} x{count}`)
		end
	end
	return table.concat(parts, ", ")
end

-- Weapon visual -------------------------------------------------------------------------

local function removeWeapon(player: Player)
	local visual = weapons[player]
	if visual then
		visual.model:Destroy()
		weapons[player] = nil
	end
end

function Gear.refreshWeapon(player: Player)
	local character = player.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	local carries = store:weapon(player.UserId) ~= nil
	local visual = weapons[player]
	if visual and (not carries or not hand or visual.weld.Part0 ~= hand or not visual.model.Parent) then
		removeWeapon(player)
		visual = nil
	end
	if visual or not carries or not hand or not hand:IsA("BasePart") then
		return
	end

	local model = Instance.new("Model")
	model.Name = "HB_Weapon"
	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = Vector3.new(0.25, 0.4, 3.4)
	blade.Color = Color3.fromRGB(190, 195, 205)
	blade.Material = Enum.Material.Metal
	blade.CanCollide = false
	blade.CanQuery = false
	blade.CanTouch = false
	blade.Massless = true
	blade.Parent = model
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0, -1.6)
	a0.Parent = blade
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 0, 1.2)
	a1.Parent = blade
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.15
	trail.Color = ColorSequence.new(Color3.fromRGB(230, 240, 255))
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Enabled = false
	trail.Parent = blade

	local baseC0 = CFrame.new(0, -hand.Size.Y / 2, -1.4)
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = blade
	weld.C0 = baseC0
	weld.Parent = blade
	model.Parent = character
	weapons[player] = { model = model, weld = weld, baseC0 = baseC0, trail = trail }
end

-- Supply station --------------------------------------------------------------------------

function Gear.tryRefill(player: Player, station: BasePart)
	local allowed, blocked = Guard.checkActive(player)
	if not allowed then
		ServerNet.notify(player, blocked :: string, "error")
		return
	end
	local root = Characters.liveRoot(player)
	if not root then
		return
	end
	if Zones.zoneAt(root.Position) ~= "Town" then
		ServerNet.notify(player, "Supplies are only handed out in town.", "error")
		return
	end
	if (root.Position - station.Position).Magnitude > Config.Supply.ServerMaxDistance then
		ServerNet.notify(player, "Move closer to the supply station.", "error")
		return
	end
	local added = store:refill(player.UserId)
	if next(added) == nil then
		ServerNet.notify(player, "You already carry the basic loadout.", "info")
	else
		ServerNet.notify(player, `Supplied: {describe(added)}. Ordinary items are lost on final death.`, "success")
		print(`[Hollowbound] {player.Name} refilled: {describe(added)}`)
	end
	Gear.refreshWeapon(player)
	ServerNet.pushState(player)
end

-- Bandage -----------------------------------------------------------------------------------

-- Starts a bandage. Returns (ok, message).
function Gear.useBandage(player: Player): (boolean, string)
	local allowed, blocked = Guard.checkActive(player)
	if not allowed then
		return false, blocked :: string
	end
	local def = Config.Items.Bandage
	if store:count(player.UserId, "Bandage") < 1 then
		return false, "You have no bandages. Refill in town."
	end
	local record = Vitals.record(player)
	if not record or record.core.health >= record.core.maxHealth then
		return false, "You are already at full health."
	end
	if Busy.kind(player) then
		return false, "You are busy."
	end
	local charId = record.core.charId
	local token = Busy.begin(player, {
		kind = "Bandage",
		duration = def.useTime,
		interruptible = true,
		validate = function()
			if Vitals.charId(player) ~= charId or Vitals.condition(player) ~= "Alive" then
				return false, "Bandaging stopped."
			end
			if store:count(player.UserId, "Bandage") < 1 then
				return false, "You have no bandages."
			end
			return true
		end,
		complete = function()
			if store:consume(player.UserId, "Bandage", 1) then
				local healed = Vitals.heal(player, def.heal)
				ServerNet.notify(player, string.format("Bandaged: +%d health.", math.floor(healed + 0.5)), "success")
				ServerNet.pushState(player)
			end
		end,
		cancelled = function(reason)
			ServerNet.notify(player, `{reason} The bandage was not used.`, "error")
		end,
	})
	if not token then
		return false, "You are busy."
	end
	return true, "Bandaging... (taking damage interrupts it)"
end

-- Self-rescue kits are spent by Rescue, through this.
function Gear.consume(player: Player, itemId: string, amount: number): boolean
	return store:consume(player.UserId, itemId, amount)
end

function Gear.count(player: Player, itemId: string): number
	return store:count(player.UserId, itemId)
end

-- World loot ----------------------------------------------------------------------------------

local function removeLoot(dropId: string)
	local part = lootParts[dropId]
	if part then
		part:Destroy()
	end
	lootParts[dropId] = nil
	lootExpiry[dropId] = nil
	store:removeDrop(dropId)
end

local function refreshLootLabel(dropId: string)
	local part = lootParts[dropId]
	local contents = store:dropContents(dropId)
	if part and contents then
		local label = part:FindFirstChild("Label", true)
		if label and label:IsA("TextLabel") then
			label.Text = describe(contents)
		end
	end
end

function Gear.tryPickupLoot(player: Player, dropId: string)
	local allowed, blocked = Guard.checkActive(player)
	if not allowed then
		ServerNet.notify(player, blocked :: string, "error")
		return
	end
	local root = Characters.liveRoot(player)
	local part = lootParts[dropId]
	if not root or not part then
		ServerNet.notify(player, "Those supplies are gone.", "error")
		return
	end
	if (root.Position - part.Position).Magnitude > Config.Loot.ServerMaxDistance then
		ServerNet.notify(player, "Too far away to pick that up.", "error")
		return
	end
	local taken, emptiedOrReason = store:claimDrop(dropId, player.UserId)
	if not taken then
		ServerNet.notify(player, if emptiedOrReason == "NoRoom" then "You cannot carry any more of that." else "Those supplies are gone.", "error")
		return
	end
	if emptiedOrReason == true then
		removeLoot(dropId)
	else
		refreshLootLabel(dropId)
	end
	print(`[Hollowbound] {player.Name} picked up {describe(taken)} from {dropId}`)
	ServerNet.notify(player, `Picked up {describe(taken)}.`, "success")
	Gear.refreshWeapon(player)
	ServerNet.pushState(player)
end

local function spawnLoot(dropId: string, position: Vector3)
	local part = Instance.new("Part")
	part.Name = "Loot_" .. dropId
	part.Size = Vector3.new(1.8, 1.2, 1.8)
	part.Color = Color3.fromRGB(150, 110, 70)
	part.Material = Enum.Material.WoodPlanks
	part.Anchored = true
	part.CanCollide = false
	part.Position = position
	part:SetAttribute("DropId", dropId)

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 26)
	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.MaxDistance = 60
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(240, 220, 170)
	label.TextStrokeTransparency = 0.3
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = gui

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up supplies"
	prompt.ObjectText = "Dropped supplies"
	prompt.MaxActivationDistance = Config.Loot.PromptMaxDistance
	prompt.HoldDuration = Config.Loot.HoldDuration
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		Gear.tryPickupLoot(player, dropId)
	end)

	CollectionService:AddTag(part, Config.Tags.WorldLoot)
	part.Parent = lootFolder
	lootParts[dropId] = part
	lootExpiry[dropId] = os.clock() + Config.Loot.DropLifetime
	refreshLootLabel(dropId)
end

--[[
	Final death: everything carried becomes one world-loot drop at `position` (already
	chosen on safe ground by Defeat). Returns the drop id, or nil if nothing was carried.
]]
function Gear.dropAll(player: Player, position: Vector3): string?
	local items = store:takeAll(player.UserId)
	removeWeapon(player)
	local dropId = store:createDrop(items)
	if dropId then
		spawnLoot(dropId, position)
		print(`[Hollowbound] {player.Name} dropped supplies {dropId}: {describe(items)}`)
	end
	ServerNet.pushState(player)
	return dropId
end

-- Leaving the game in town (or a lost session): ordinary items are session-only and vanish.
function Gear.discard(player: Player)
	store:takeAll(player.UserId)
	removeWeapon(player)
end

local function attachStation(station: Instance)
	if not station:IsA("BasePart") then
		warn(`[Hollowbound] {station:GetFullName()} is tagged as a supply station but is not a BasePart.`)
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take basic supplies"
	prompt.ObjectText = "Supply Station"
	prompt.MaxActivationDistance = Config.Supply.PromptMaxDistance
	prompt.HoldDuration = Config.Supply.HoldDuration
	prompt.RequiresLineOfSight = false
	prompt.Parent = station
	prompt.Triggered:Connect(function(player)
		Gear.tryRefill(player, station)
	end)
end

function Gear.start()
	lootFolder = Instance.new("Folder")
	lootFolder.Name = "HollowboundWorldLoot"
	lootFolder.Parent = workspace

	for _, station in CollectionService:GetTagged(Config.Tags.SupplyStation) do
		attachStation(station)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.SupplyStation):Connect(attachStation)

	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			Gear.refreshWeapon(player)
		end)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		task.defer(function()
			removeWeapon(player)
		end)
	end)

	-- Untouched ordinary-item drops expire, so repeated deaths cannot pile up crates.
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for dropId, expiresAt in lootExpiry do
				if now >= expiresAt then
					print(`[Hollowbound] Supplies {dropId} expired`)
					removeLoot(dropId)
				end
			end
		end
	end)
end

return Gear
