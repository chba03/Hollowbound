--[[
	Pickaxes: the weapons (Config.Pickaxes). Server side.

	  - The Forge (client ForgeMenu) asks to buy (Net.ForgeBuy) or equip
	    (Net.ForgeEquip). Buying needs the pickaxe's layer reached (your deepest depth)
	    and the cash; the first pickaxe is free and owned from the start.
	  - Your equipped pickaxe is a Tool in your backpack, given on every spawn.
	  - Swinging (the Tool's Activated, which reaches the server) is checked here: a
	    cooldown per pickaxe; HB_SwingAt tells clients to play the swing (SwingFx);
	    then after HitDelay every model tagged Tags.Enemy within
	    reach and in front of you takes the pickaxe's damage (up to MaxTargets). The
	    swinger sees damage numbers (Net.HitShown).
	  - Training dummies (Tags.Enemy with a Dummy attribute) heal straight back.
	  - Other players in reach are knocked down instead of damaged
	    (Config.Pickaxes.Pvp): a short ragdoll (FallDamage.ragdoll) and a shove away
	    from the swinger. The victim's client applies the shove (Net.Knockback), since
	    it owns its character's physics. Not in safe zones, not on a rope, and not
	    again until a short immunity after getting up.

	The Forge also sells the grappling hook (Config.Grapple): bought once, given as a
	second tool on every spawn, used through Grapple.

	Published for the client: HB_Pickaxe (equipped id), HB_PickaxesOwned (ids, comma
	separated), and HB_HasGrapple.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local PickaxeModels = require(Shared:WaitForChild("PickaxeModels"))
local Progression = require(Shared:WaitForChild("Progression"))
local Characters = require(script.Parent.Characters)
local FallDamage = require(script.Parent.FallDamage)
local Grapple = require(script.Parent.Grapple)
local GrappleModel = require(Shared:WaitForChild("GrappleModel"))
local PlayerData = require(script.Parent.PlayerData)
local ServerNet = require(script.Parent.ServerNet)

local Arsenal = {}

local TOOL_ATTRIBUTE = "HB_PickaxeTool"
local GRAPPLE_ATTRIBUTE = "HB_GrappleTool"
local lastSwing: { [Player]: number } = {}
local hitRemote: RemoteEvent
local knockRemote: RemoteEvent
local immuneUntil: { [Player]: number } = {}

-- Has the player been down to this pickaxe's layer?
function Arsenal.unlocked(player: Player, def): boolean
	local data = PlayerData.get(player)
	local deepest = if data then data.Stats.DeepestDepth else 0
	return def.layer <= 1 or deepest > (def.layer - 1) * Config.Hollow.LayerHeight
end

local function publish(player: Player)
	local data = PlayerData.get(player)
	if not data then
		return
	end
	local owned = {}
	for _, def in Config.Pickaxes.List do
		if data.Pickaxes.Owned[def.id] then
			table.insert(owned, def.id)
		end
	end
	player:SetAttribute("HB_Pickaxe", data.Pickaxes.Equipped)
	player:SetAttribute("HB_PickaxesOwned", table.concat(owned, ","))
	player:SetAttribute("HB_HasGrapple", data.Gear.Grapple == true)
end

local function safe(player: Player): boolean
	return table.find(Config.Pickaxes.Pvp.SafeZones, player:GetAttribute("HB_Zone")) ~= nil
end

-- Ragdolls `victim` and shoves them along `away` (flat, unit), then stands them up.
local function knockDown(victim: Player, character: Model, away: Vector3, def)
	local pvp = Config.Pickaxes.Pvp
	local now = os.clock()
	immuneUntil[victim] = now + pvp.RagdollSeconds + pvp.ImmuneSeconds
	local velocity = away * (pvp.Knockback + pvp.KnockbackPerLayer * (def.layer - 1)) + Vector3.new(0, pvp.Lift, 0)
	FallDamage.ragdoll(character, true)
	knockRemote:FireClient(victim, velocity, pvp.RagdollSeconds)
	task.delay(pvp.RagdollSeconds, function()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if character.Parent and humanoid and humanoid.Health > 0 then
			FallDamage.unragdoll(character)
		end
	end)
end

-- Knocks down other players in front of the swinger. Returns how many were hit.
local function strikePlayers(player: Player, def, root: BasePart, look: Vector3, budget: number): number
	local pvp = Config.Pickaxes.Pvp
	if not pvp.Enabled or budget <= 0 or safe(player) then
		return 0
	end
	local hits = 0
	local now = os.clock()
	for _, victim in Players:GetPlayers() do
		if hits >= budget then
			break
		end
		local character = victim.Character
		local target = Characters.liveRoot(victim)
		if victim == player or not character or not target then
			continue
		end
		if safe(victim) or victim:GetAttribute("HB_OnRope") or character:GetAttribute("HB_Ragdolled") or now < (immuneUntil[victim] or 0) then
			continue
		end
		local offset = target.Position - root.Position
		local flat = offset * Vector3.new(1, 0, 1)
		if offset.Magnitude > def.reach + 1 or (flat.Magnitude > 0.5 and look:Dot(flat.Unit) < Config.Pickaxes.FacingDot) then
			continue
		end
		local away = if flat.Magnitude > 0.5 then flat.Unit else look
		knockDown(victim, character, away, def)
		hits += 1
		print(`[Hollowbound] {player.Name} knocked down {victim.Name}`)
	end
	return hits
end

-- Hits everything in front of the swinger within reach.
local function strike(player: Player, def)
	local root = Characters.liveRoot(player)
	if not root then
		return
	end
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.zAxis
	local hits = strikePlayers(player, def, root, look, Config.Pickaxes.MaxTargets)
	for _, enemy in CollectionService:GetTagged(Config.Tags.Enemy) do
		if hits >= Config.Pickaxes.MaxTargets then
			break
		end
		if not enemy:IsA("Model") or enemy == player.Character then
			continue
		end
		local humanoid = enemy:FindFirstChildOfClass("Humanoid")
		local target = enemy:FindFirstChild("HumanoidRootPart")
		if not (humanoid and humanoid.Health > 0 and target and target:IsA("BasePart")) then
			continue
		end
		local offset = target.Position - root.Position
		local flat = offset * Vector3.new(1, 0, 1)
		local reach = def.reach + math.max(target.Size.X, target.Size.Z) / 2
		if offset.Magnitude > reach or (flat.Magnitude > 0.5 and look:Dot(flat.Unit) < Config.Pickaxes.FacingDot) then
			continue
		end
		enemy:SetAttribute("LastHitBy", player.UserId) -- the kill reward goes to the last hitter
		humanoid:TakeDamage(def.damage)
		hits += 1
		hitRemote:FireClient(player, target.Position + Vector3.new(0, 2.5, 0), def.damage)
	end
end

local function onSwing(player: Player, tool: Tool)
	local def = Config.PickaxeById[tool:GetAttribute(TOOL_ATTRIBUTE) or ""]
	if not def or tool.Parent ~= player.Character or (player.Character :: Model):GetAttribute("HB_Ragdolled") then
		return
	end
	local now = os.clock()
	if now - (lastSwing[player] or 0) < def.cooldown then
		return
	end
	lastSwing[player] = now
	-- Every client plays the swing (SwingAnimation) on this character when this changes.
	player:SetAttribute("HB_SwingAt", workspace:GetServerTimeNow())
	task.delay(Config.Pickaxes.HitDelay, strike, player, def)
end

-- Replaces the player's pickaxe tool with their equipped one.
function Arsenal.giveTool(player: Player)
	local data = PlayerData.get(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not data or not backpack then
		return
	end
	for _, holder in { backpack, player.Character } do
		if holder then
			for _, item in holder:GetChildren() do
				if item:IsA("Tool") and (item:GetAttribute(TOOL_ATTRIBUTE) or item:GetAttribute(GRAPPLE_ATTRIBUTE)) then
					item:Destroy()
				end
			end
		end
	end
	local def = Config.PickaxeById[data.Pickaxes.Equipped] or Config.Pickaxes.List[1]
	local tool = Instance.new("Tool")
	tool.Name = def.name
	tool.ToolTip = `{def.damage} damage`
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute(TOOL_ATTRIBUTE, def.id)
	local grip = PickaxeModels.Grip
	tool.GripPos = grip.Pos
	tool.GripForward = grip.Forward
	tool.GripRight = grip.Right
	tool.GripUp = grip.Up
	local model = PickaxeModels.build(def, true)
	for _, part in model:GetChildren() do
		part.Parent = tool
	end
	model:Destroy()
	tool.Activated:Connect(function()
		onSwing(player, tool)
	end)
	tool.Parent = backpack

	if data.Gear.Grapple then
		local grapple = Instance.new("Tool")
		grapple.Name = Config.Grapple.name
		grapple.ToolTip = `Hook the ledge above. One use per {Config.Grapple.BandMeters} m.`
		grapple.CanBeDropped = false
		grapple.RequiresHandle = true
		grapple:SetAttribute(GRAPPLE_ATTRIBUTE, true)
		grapple.GripPos = grip.Pos
		grapple.GripForward = grip.Forward
		grapple.GripRight = grip.Right
		grapple.GripUp = grip.Up
		local hookModel = GrappleModel.build(true)
		for _, part in hookModel:GetChildren() do
			part.Parent = grapple
		end
		hookModel:Destroy()
		grapple.Activated:Connect(function()
			if grapple.Parent == player.Character then
				Grapple.use(player)
			end
		end)
		grapple.Parent = backpack
	end
end

-- Republishes owned gear and rebuilds the tools (admin commands).
function Arsenal.refresh(player: Player)
	publish(player)
	Arsenal.giveTool(player)
end

local function buyGrapple(player: Player, data)
	local def = Config.Grapple
	if data.Gear.Grapple then
		ServerNet.notify(player, `You already own the {def.name}.`, "info")
		return
	end
	if not PlayerData.trySpend(player, def.cost) then
		ServerNet.notify(player, `Not enough cash: the {def.name} costs {Progression.formatCash(def.cost)}.`, "error")
		return
	end
	data.Gear.Grapple = true
	PlayerData.publish(player)
	publish(player)
	Arsenal.giveTool(player)
	ServerNet.notify(player, `Bought the {def.name}. It's in your hotbar: use it to climb to the ledge above.`, "success")
	print(`[Hollowbound] {player.Name} bought the grapple`)
end

local function onBuy(player: Player, id: any)
	local data = PlayerData.get(player)
	if data and id == Config.Grapple.id then
		buyGrapple(player, data)
		return
	end
	local def = typeof(id) == "string" and Config.PickaxeById[id]
	if not data or not def then
		return
	end
	if data.Pickaxes.Owned[def.id] then
		ServerNet.notify(player, `You already own the {def.name}.`, "info")
		return
	end
	if not Arsenal.unlocked(player, def) then
		ServerNet.notify(player, `Reach layer {def.layer} ({Config.Layers[def.layer].name}) to unlock the {def.name}.`, "error")
		return
	end
	if not PlayerData.trySpend(player, def.cost) then
		ServerNet.notify(player, `Not enough cash: the {def.name} costs {Progression.formatCash(def.cost)}.`, "error")
		return
	end
	data.Pickaxes.Owned[def.id] = true
	data.Pickaxes.Equipped = def.id
	PlayerData.publish(player)
	publish(player)
	Arsenal.giveTool(player)
	ServerNet.notify(player, `Forged the {def.name}: {def.damage} damage. It's in your hotbar.`, "success")
	print(`[Hollowbound] {player.Name} bought pickaxe {def.id}`)
end

local function onEquip(player: Player, id: any)
	local data = PlayerData.get(player)
	local def = typeof(id) == "string" and Config.PickaxeById[id]
	if not data or not def or not data.Pickaxes.Owned[def.id] then
		return
	end
	data.Pickaxes.Equipped = def.id
	publish(player)
	Arsenal.giveTool(player)
end

-- Dummies heal straight back after each hit.
local function watchDummy(model: Instance)
	if not model:IsA("Model") or not model:GetAttribute("Dummy") then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.HealthChanged:Connect(function(health)
		if health < humanoid.MaxHealth then
			task.delay(0.4, function()
				humanoid.Health = humanoid.MaxHealth
			end)
		end
	end)
end

function Arsenal.start()
	hitRemote = ServerNet.remote(Net.HitShown) :: RemoteEvent
	knockRemote = ServerNet.remote(Net.Knockback) :: RemoteEvent
	ServerNet.on(Net.ForgeBuy, onBuy)
	ServerNet.on(Net.ForgeEquip, onEquip)

	PlayerData.onLoaded(function(player)
		publish(player)
		if player.Character then
			Arsenal.giveTool(player)
		end
	end)
	local function track(player: Player)
		player.CharacterAdded:Connect(function()
			task.defer(Arsenal.giveTool, player) -- the backpack is replaced on spawn
		end)
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
		immuneUntil[player] = nil
	end)

	for _, model in CollectionService:GetTagged(Config.Tags.Enemy) do
		watchDummy(model)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.Enemy):Connect(watchDummy)
end

return Arsenal
