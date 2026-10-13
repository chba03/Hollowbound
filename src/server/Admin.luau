--[[
	Admin chat commands for playtesting on live servers (project owner). Server side.

	Type "/hb <command> [args]" in chat. Only admins can use them: the experience's
	owner (or rank 255 in the owning group), anyone in Config.Admin.UserIds, and anyone
	in Studio. Everyone else's "/hb" does nothing. The command text is never shown in
	chat. Results come back as toasts.

	Most commands take an optional player name at the end (start of the name or display
	name is enough); without one they act on you. "/hb help" lists them.

	Amounts accept plain numbers, 1e18, or suffixes: 10k, 5m, 2b, 3t, 250qa, 5qi, 1sx.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("HollowboundShared")
local Config = require(Shared:WaitForChild("Config"))
local Progression = require(Shared:WaitForChild("Progression"))
local Arsenal = require(script.Parent.Arsenal)
local Characters = require(script.Parent.Characters)
local Ground = require(script.Parent.Ground)
local Hollow = require(script.Parent.Hollow)
local NightCycle = require(script.Parent.NightCycle)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local RelicSpawner = require(script.Parent.RelicSpawner)
local RopeService = require(script.Parent.RopeService)
local ServerNet = require(script.Parent.ServerNet)

local Admin = {}

local SUFFIXES = { k = 1e3, m = 1e6, b = 1e9, t = 1e12, qa = 1e15, qi = 1e18, sx = 1e21, sp = 1e24, oc = 1e27, no = 1e30, dc = 1e33 }

function Admin.isAdmin(player: Player): boolean
	if RunService:IsStudio() or table.find(Config.Admin.UserIds, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(player.GetRankInGroupAsync, player, game.CreatorId)
	return ok and rank >= 255
end

-- "250qa" -> 2.5e17, "1e18" -> 1e18. Nil if it isn't a number.
local function amount(text: string?): number?
	if not text then
		return nil
	end
	local plain = tonumber(text)
	if plain then
		return plain
	end
	local number, suffix = string.match(string.lower(text), "^([%d%.]+)(%a+)$")
	local scale = suffix and SUFFIXES[suffix]
	local value = number and tonumber(number)
	return if value and scale then value * scale else nil
end

-- A player by the start of their name or display name, or nil.
local function findPlayer(text: string): Player?
	local lower = string.lower(text)
	for _, player in Players:GetPlayers() do
		if string.sub(string.lower(player.Name), 1, #lower) == lower or string.sub(string.lower(player.DisplayName), 1, #lower) == lower then
			return player
		end
	end
	return nil
end

local function setLevel(target: Player, kind: string, level: number): string
	local data = PlayerData.get(target)
	local upgrade = Progression.Upgrades[kind]
	if not data then
		return "no data loaded"
	end
	level = math.clamp(math.floor(level), 1, #upgrade.levels)
	data[upgrade.field] = level
	PlayerData.publish(target)
	return `{upgrade.label} level {level} ({Progression.value(kind, level)}{upgrade.unit})`
end

-- Puts a player on the first ledge of `layer`, out from their rope, and counts the
-- depth as reached (so the Forge unlocks that layer's pickaxe).
local function toLayer(target: Player, layer: number): string
	local root = Characters.liveRoot(target)
	local center = Hollow.center()
	local point = target:GetAttribute("HB_RopePoint")
	if not root or not center then
		return "no character"
	end
	layer = math.clamp(math.floor(layer), 1, #Config.Layers)
	local H = Config.Hollow
	local depth = (layer - 1) * H.LayerHeight + H.LedgeDepths[1]
	local out = if typeof(point) == "Vector3" then Vector3.new(point.X - center.X, 0, point.Z - center.Z) else Vector3.xAxis
	out = if out.Magnitude > 0.1 then out.Unit else Vector3.xAxis
	local spot = Vector3.new(center.X, center.Y - depth, center.Z) + out * (H.LedgeInnerRadius + 8)
	local groundY = Ground.below(spot + Vector3.new(0, 4, 0)) or spot.Y
	RopeService.detach(target)
	root.AssemblyLinearVelocity = Vector3.zero
	local character = target.Character :: Model
	character:PivotTo(CFrame.lookAt(Vector3.new(spot.X, groundY + 4, spot.Z), Vector3.new(spot.X, groundY + 4, spot.Z) + out))
	PlayerData.recordDepth(target, depth + 1)
	RopeService.deploy(target, false)
	return `layer {layer}: {Config.Layers[layer].name}`
end

type Command = { usage: string, run: (admin: Player, args: { string }, target: Player) -> string }

local COMMANDS: { [string]: Command } = {
	cash = { usage = "cash <amount> [player]  add cash", run = function(_, args, target)
		local value = amount(args[1])
		if not value then
			return "usage: /hb cash 1e18"
		end
		PlayerData.addCash(target, value)
		PlayerData.publish(target)
		return `+{Progression.formatCash(value)}`
	end },
	setcash = { usage = "setcash <amount> [player]  set cash exactly", run = function(_, args, target)
		local value = amount(args[1])
		local data = PlayerData.get(target)
		if not value or not data then
			return "usage: /hb setcash 0"
		end
		data.Cash = math.max(value, 0)
		PlayerData.publish(target)
		return `cash set to {Progression.formatCash(data.Cash)}`
	end },
	rope = { usage = "rope <level 1-14> [player]  rope length level", run = function(_, args, target)
		return setLevel(target, "RopeLength", amount(args[1]) or #Config.Rope.LengthLevels)
	end },
	climb = { usage = "climb <level> [player]  climb speed upgrade level", run = function(_, args, target)
		return setLevel(target, "RopeSpeed", amount(args[1]) or #Config.Rope.SpeedLevels)
	end },
	slots = { usage = "slots <level> [player]  display slot level", run = function(_, args, target)
		return setLevel(target, "BaseSlots", amount(args[1]) or #Config.Base.SlotLevels)
	end },
	speed = { usage = "speed <amount> [player]  set the Speed stat", run = function(_, args, target)
		local value = amount(args[1])
		local data = PlayerData.get(target)
		if not value or not data then
			return "usage: /hb speed 1m"
		end
		data.Speed = math.max(value, 0)
		PlayerData.publishSpeed(target)
		return `Speed {Progression.formatNumber(data.Speed)}`
	end },
	max = { usage = "max [player]  every upgrade maxed, all gear, lots of cash", run = function(_, _, target)
		local data = PlayerData.get(target)
		if not data then
			return "no data loaded"
		end
		data.RopeLengthLevel = #Config.Rope.LengthLevels
		data.RopeSpeedLevel = #Config.Rope.SpeedLevels
		data.BaseSlotsLevel = #Config.Base.SlotLevels
		data.Cash += 1e21
		data.Stats.DeepestDepth = math.max(data.Stats.DeepestDepth, #Config.Layers * Config.Hollow.LayerHeight)
		for _, def in Config.Pickaxes.List do
			data.Pickaxes.Owned[def.id] = true
		end
		data.Gear.Grapple = true
		PlayerData.publish(target)
		Arsenal.refresh(target)
		return "maxed upgrades, all pickaxes and the grapple, +$1.0Sx"
	end },
	gear = { usage = "gear [player]  all pickaxes and the grapple", run = function(_, _, target)
		local data = PlayerData.get(target)
		if not data then
			return "no data loaded"
		end
		for _, def in Config.Pickaxes.List do
			data.Pickaxes.Owned[def.id] = true
		end
		data.Gear.Grapple = true
		Arsenal.refresh(target)
		return "all pickaxes and the grapple (equip in the Forge)"
	end },
	layer = { usage = "layer <1-10> [player]  teleport to that layer's first ledge", run = function(_, args, target)
		return toLayer(target, amount(args[1]) or 1)
	end },
	home = { usage = "home [player]  back to base", run = function(_, _, target)
		RopeService.detach(target)
		Plots.sendHome(target)
		return "sent home"
	end },
	heal = { usage = "heal [player]  full health", run = function(_, _, target)
		local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = humanoid.MaxHealth
		end
		return "healed"
	end },
	rare = { usage = "rare <Divine|Eternal|Godly>  spawn one now (announced)", run = function(_, args)
		local wanted = string.lower(args[1] or "godly")
		for _, tier in Config.Rarities do
			if string.lower(tier.id) == wanted then
				local layer = RelicSpawner.spawnRare(tier.id)
				return if layer then `{tier.id} spawned in layer {layer}` else `no free spot for {tier.id}`
			end
		end
		return "usage: /hb rare godly"
	end },
	night = { usage = "night  nightfall now", run = function()
		NightCycle.forceNight()
		return "night falls"
	end },
	dawn = { usage = "dawn  dawn now (fresh relics)", run = function()
		NightCycle.forceDawn()
		return "dawn breaks"
	end },
}
local ORDER = { "cash", "setcash", "rope", "climb", "slots", "speed", "max", "gear", "layer", "home", "heal", "rare", "night", "dawn" }
-- Commands whose last argument may be a player name, and how many arguments come before it.
local TARGET_AFTER = { cash = 1, setcash = 1, rope = 1, climb = 1, slots = 1, speed = 1, max = 0, gear = 0, layer = 1, home = 0, heal = 0 }

local function run(player: Player, text: string)
	if not Admin.isAdmin(player) then
		return
	end
	local words = string.split(string.gsub(text, "^%s*/hb%s*", ""), " ")
	local args = {}
	for _, word in words do
		if word ~= "" then
			table.insert(args, word)
		end
	end
	local name = string.lower(table.remove(args, 1) or "help")
	local command = COMMANDS[name]
	if not command then
		local lines = {}
		for _, id in ORDER do
			table.insert(lines, "/hb " .. COMMANDS[id].usage)
		end
		ServerNet.notify(player, "Admin commands:\n" .. table.concat(lines, "\n"), "info")
		print("[Hollowbound] Admin commands:\n" .. table.concat(lines, "\n"))
		return
	end
	local target = player
	local before = TARGET_AFTER[name]
	if before and #args > before then
		local found = findPlayer(args[#args])
		if not found then
			ServerNet.notify(player, `No player named "{args[#args]}".`, "error")
			return
		end
		target = found
		table.remove(args)
	end
	local ok, result = pcall(command.run, player, args, target)
	local message = if ok then result else `failed: {result}`
	local who = if target == player then "" else ` ({target.DisplayName})`
	ServerNet.notify(player, `Admin {name}{who}: {message}`, if ok then "success" else "error")
	if target ~= player and ok then
		ServerNet.notify(target, `An admin used {name} on you: {message}`, "info")
	end
	print(`[Hollowbound] Admin {player.Name} ran "{text}" -> {message}`)
end

function Admin.start()
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		-- A server-side chat command: it fires here, and its text never shows in chat.
		local command = Instance.new("TextChatCommand")
		command.Name = "HollowboundAdmin"
		command.PrimaryAlias = "/hb"
		command.Parent = TextChatService
		command.Triggered:Connect(function(source: TextSource, text: string)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player then
				run(player, text)
			end
		end)
	else
		local function watch(player: Player)
			player.Chatted:Connect(function(message)
				if string.sub(string.lower(message), 1, 3) == "/hb" then
					run(player, message)
				end
			end)
		end
		Players.PlayerAdded:Connect(watch)
		for _, player in Players:GetPlayers() do
			watch(player)
		end
	end
end

return Admin
