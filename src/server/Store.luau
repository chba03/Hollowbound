--[[
	The store's server side: purchase requests, Roblox purchase prompts and receipts,
	and granting what was bought (Config.Shop).

	Flow: the client asks to buy an item (Net.ShopBuy). The server checks it can be
	bought (level not maxed, pass not owned, weekly stock left) and then prompts the
	Roblox purchase. When Roblox confirms (ProcessReceipt for developer products,
	PromptGamePassPurchaseFinished for passes), the server grants the item. Receipts are
	remembered in the player's profile so a retried receipt never grants twice.

	Items with no id yet: in Studio (Config.Shop.StudioFreePurchases) they are granted
	free so everything can be tested; in a live server they are "not for sale yet".

	What each kind grants:
	  cash        income x minutes, at least a minimum (Perks.cashFor)
	  level       +1 upgrade level (cash instead if already maxed)
	  crate       a random relic from a layer, already registered and saved
	  boost       a timed personal boost, saved with its end time
	  serverLuck  rarer relic spawns for the whole server for a while
	  bundle      several of the above
	  pass        a permanent perk (HB_Pass_<perk>)
]]

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Perks = require(Shared:WaitForChild("Perks"))
local Progression = require(Shared:WaitForChild("Progression"))
local BaseManager = require(script.Parent.BaseManager)
local PlayerData = require(script.Parent.PlayerData)
local RelicSpawner = require(script.Parent.RelicSpawner)
local ServerNet = require(script.Parent.ServerNet)
local SpecimenFactory = require(script.Parent.SpecimenFactory)

local Store = {}

local shop = Config.Shop
local store -- RelicStore
local rng = Random.new()
local MAX_RECEIPTS = 100
local LEVEL_FALLBACK_MINUTES = 30 -- a maxed level pays this much income instead

local itemByProduct: { [number]: string } = {}
local itemByPass: { [number]: string } = {}
for id, item in shop.Items do
	if item.productId and item.productId > 0 then
		itemByProduct[item.productId] = id
	end
	if item.passId and item.passId > 0 then
		itemByPass[item.passId] = id
	end
end

local function studioFree(): boolean
	return RunService:IsStudio() and shop.StudioFreePurchases
end

-- Weekly stock --------------------------------------------------------------------------

local function syncWeek(player: Player, data)
	local _, _, week = Perks.weeklyOffer()
	if data.Shop.Week ~= week then
		data.Shop.Week = week
		data.Shop.Bought = {}
	end
	local index = Perks.weeklyOffer()
	local offer = shop.Limited.Offers[index]
	player:SetAttribute("HB_LimitedBought", data.Shop.Bought[offer.id] or 0)
end

-- Granting -------------------------------------------------------------------------------

local grant: (Player, any) -> string

local function grantCash(player: Player, minutes: number, minimum: number): string
	local amount = Perks.cashFor(player, minutes, minimum)
	PlayerData.addCash(player, amount)
	return `+{Progression.formatCash(amount)}`
end

local function grantLevel(player: Player, upgradeKind: string): string
	local data = PlayerData.get(player)
	local upgrade = Progression.Upgrades[upgradeKind]
	local nextDef, nextLevel = Progression.next(upgradeKind, data[upgrade.field])
	if not nextDef then
		return grantCash(player, LEVEL_FALLBACK_MINUTES, 50000) .. ` ({upgrade.label} was already maxed)`
	end
	data[upgrade.field] = nextLevel
	return `{upgrade.label} level {nextLevel}`
end

local function grantCrate(player: Player, layer: number, weights): string
	local tier = RelicSpawner.rollRarity(rng, layer, weights or shop.CrateWeights)
	local typeId = RelicSpawner.pickType(layer, tier, rng)
	local band = Config.Layers[layer].quality
	local specimen = SpecimenFactory.create(typeId, band[1], band[2], rng, function()
		return HttpService:GenerateGUID(false)
	end, layer)
	-- Bought relics arrive secured: registered, saved, and in the pack.
	specimen.registered = true
	specimen.registeredAt = os.time()
	store:restore(specimen, player.UserId)
	PlayerData.saveSpecimen(player, specimen)
	ServerNet.pushInventory(player)
	local name = Progression.relicName(specimen.typeId, specimen.size)
	if Config.RarityById[specimen.rarity].rank >= Config.Announce.MinRank then
		ServerNet.announceAll(`{string.upper(specimen.rarity)} RELIC FROM A CRATE`, `{player.DisplayName} opened a crate and found {name}!`, specimen.rarity)
	end
	return `{name} ({specimen.rarity})`
end

local function grantBoost(player: Player, boost: string, minutes: number): string
	local data = PlayerData.get(player)
	local now = Perks.now()
	data.Boosts[boost] = math.max(data.Boosts[boost] or 0, now) + minutes * 60
	player:SetAttribute("HB_Boost_" .. boost, data.Boosts[boost])
	return `{shop.Boosts[boost].label} for {minutes} min`
end

local function grantServerLuck(player: Player, minutes: number): string
	local now = Perks.now()
	local untilTime = math.max(workspace:GetAttribute("HB_ServerLuckUntil") or 0, now) + minutes * 60
	workspace:SetAttribute("HB_ServerLuckUntil", untilTime)
	ServerNet.announceAll("A LUCKY LANTERN IS LIT", `{player.DisplayName} lit a Lucky Lantern: rare relics are twice as likely for {minutes} minutes!`, "Divine")
	return `Lucky Lantern for {minutes} min`
end

grant = function(player: Player, item): string
	if item.kind == "cash" then
		return grantCash(player, item.minutes, item.minimum)
	elseif item.kind == "level" then
		return grantLevel(player, item.upgrade)
	elseif item.kind == "crate" then
		return grantCrate(player, item.layer, item.weights)
	elseif item.kind == "boost" then
		return grantBoost(player, item.boost, item.minutes)
	elseif item.kind == "serverLuck" then
		return grantServerLuck(player, item.minutes)
	elseif item.kind == "bundle" then
		local parts = {}
		for _, content in item.contents do
			table.insert(parts, grant(player, content))
		end
		return table.concat(parts, ", ")
	end
	return ""
end

-- Grants a bought item to a loaded player and records the receipt.
local function fulfil(player: Player, itemId: string, receiptId: string): boolean
	local data = PlayerData.get(player)
	local item = shop.Items[itemId]
	if not data or not item then
		return false
	end
	if table.find(data.Receipts, receiptId) then
		return true -- already granted
	end
	local summary = grant(player, item)
	if item.limited then
		syncWeek(player, data)
		data.Shop.Bought[itemId] = (data.Shop.Bought[itemId] or 0) + 1
		syncWeek(player, data)
	end
	table.insert(data.Receipts, receiptId)
	while #data.Receipts > MAX_RECEIPTS do
		table.remove(data.Receipts, 1)
	end
	PlayerData.publish(player)
	BaseManager.refreshFor(player)
	ServerNet.notify(player, `Purchased {item.name}: {summary}.`, "success")
	print(`[Hollowbound] {player.Name} bought {itemId} ({receiptId}): {summary}`)
	return true
end

local function setPass(player: Player, item)
	player:SetAttribute("HB_Pass_" .. item.perk, true)
	PlayerData.publish(player) -- climb speed may change
end

-- Requests ------------------------------------------------------------------------------

-- Why this player cannot buy the item right now, or nil.
local function blocked(player: Player, itemId: string, item): string?
	local data = PlayerData.get(player)
	if not data then
		return "Your data is still loading."
	end
	if item.kind == "pass" and Perks.hasPass(player, item.perk) then
		return `You already own {item.name}.`
	end
	if item.kind == "level" then
		local upgrade = Progression.Upgrades[item.upgrade]
		if not Progression.next(item.upgrade, data[upgrade.field]) then
			return `{upgrade.label} is already at max level.`
		end
	end
	if item.limited then
		local index = Perks.weeklyOffer()
		if shop.Limited.Offers[index].id ~= itemId then
			return "That offer is no longer available."
		end
		syncWeek(player, data)
		if (data.Shop.Bought[itemId] or 0) >= shop.Limited.Stock then
			return "You've bought all of this week's stock. It restocks next week."
		end
	end
	return nil
end

local function onBuy(player: Player, itemId: any)
	if typeof(itemId) ~= "string" then
		return
	end
	local item = shop.Items[itemId]
	if not item then
		return
	end
	local reason = blocked(player, itemId, item)
	if reason then
		ServerNet.notify(player, reason, "error")
		return
	end

	if item.kind == "pass" then
		if item.passId > 0 then
			MarketplaceService:PromptGamePassPurchase(player, item.passId)
		elseif studioFree() then
			setPass(player, item)
			ServerNet.notify(player, `{item.name} unlocked (Studio test purchase, this session only).`, "success")
		else
			ServerNet.notify(player, `{item.name} isn't for sale yet.`, "error")
		end
		return
	end

	if item.productId > 0 then
		MarketplaceService:PromptProductPurchase(player, item.productId)
	elseif studioFree() then
		fulfil(player, itemId, "studio-" .. HttpService:GenerateGUID(false))
	else
		ServerNet.notify(player, `{item.name} isn't for sale yet.`, "error")
	end
end

-- Roblox calls this for every developer product purchase, retrying until granted.
local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local itemId = itemByProduct[receipt.ProductId]
	if not player or not itemId or not PlayerData.get(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(fulfil, player, itemId, receipt.PurchaseId)
	if ok and granted then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	warn(`[Hollowbound] Receipt {receipt.PurchaseId} for {itemId} failed: {granted}`)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Boost timers ----------------------------------------------------------------------------

local function applySaved(player: Player)
	local data = PlayerData.get(player)
	if not data then
		return
	end
	for boost, untilTime in data.Boosts do
		if untilTime > Perks.now() then
			player:SetAttribute("HB_Boost_" .. boost, untilTime)
		else
			data.Boosts[boost] = nil
		end
	end
	syncWeek(player, data)
	for _, item in shop.Items do
		if item.kind == "pass" and item.passId > 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, item.passId)
			if ok and owns then
				player:SetAttribute("HB_Pass_" .. item.perk, true)
			end
		end
	end
	PlayerData.publish(player)
end

-- Ends boosts whose time is up (so climb speed drops back) and rolls the week over.
local function tick()
	local now = Perks.now()
	for _, player in Players:GetPlayers() do
		local data = PlayerData.get(player)
		if not data then
			continue
		end
		local changed = false
		for boost, untilTime in data.Boosts do
			if untilTime <= now then
				data.Boosts[boost] = nil
				player:SetAttribute("HB_Boost_" .. boost, nil)
				ServerNet.notify(player, `Your {shop.Boosts[boost].label} boost has ended.`, "info")
				changed = true
			end
		end
		if changed then
			PlayerData.publish(player)
		end
		syncWeek(player, data)
	end
end

function Store.start(theStore)
	store = theStore
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local itemId = itemByPass[passId]
		if purchased and itemId then
			local item = shop.Items[itemId]
			setPass(player, item)
			ServerNet.notify(player, `{item.name} unlocked. Thank you!`, "success")
		end
	end)
	ServerNet.on(Net.ShopBuy, onBuy)
	PlayerData.onLoaded(applySaved)
	task.spawn(function()
		while true do
			task.wait(2)
			tick()
		end
	end)
end

return Store
