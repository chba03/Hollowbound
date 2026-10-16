--[[
	Revive and self-rescue for downed explorers (milestone 4). Server only.

	Revive: a "Revive" ProximityPrompt appears on a downed character. Its hold bar is only
	a visual: when a helper starts holding, the server starts its own timed action
	(Busy) and completes it purely by the server clock. Every frame it re-checks: helper
	standing and in range with line of sight, the target still in the same down
	(charId and downToken), the session still loaded. Releasing the prompt, moving away,
	or anything going wrong cancels it. RescueCore allows one helper per down, so
	several helpers cannot complete several revives or heal twice.

	Self-rescue: a downed player spends one carried self-rescue kit through a timed
	action. The kit is consumed exactly once, at completion, together with one use of the
	run's allowance (Config.SelfRescue.PerExpedition). The allowance belongs to the run,
	so swapping items, a new character in the same run, or a camp visit cannot reset it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))
local Busy = require(script.Parent.Busy)
local Characters = require(script.Parent.Characters)
local Expedition = require(script.Parent.Expedition)
local Gear = require(script.Parent.Gear)
local Guard = require(script.Parent.Guard)
local RescueCore = require(script.Parent.RescueCore)
local ServerNet = require(script.Parent.ServerNet)
local Vitals = require(script.Parent.Vitals)

local Rescue = {}

local core = RescueCore.new()
local prompts: { [Player]: ProximityPrompt } = {}

local function clearProgress(target: Player)
	if target.Parent then
		target:SetAttribute("HB_RescueEndsAt", nil)
		target:SetAttribute("HB_RescueBy", nil)
	end
end

local function lineOfSight(fromPart: BasePart, toPart: BasePart): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	local direction = toPart.Position - fromPart.Position
	return workspace:Raycast(fromPart.Position, direction, params) == nil
end

local markers: { [Player]: BillboardGui } = {}

local function removePrompt(target: Player)
	local prompt = prompts[target]
	if prompt then
		prompt:Destroy()
		prompts[target] = nil
	end
	local marker = markers[target]
	if marker then
		marker:Destroy()
		markers[target] = nil
	end
end

-- Starts a revive when a helper begins holding the prompt.
function Rescue.beginRevive(helper: Player, target: Player)
	local allowed, blocked = Guard.checkActive(helper)
	if not allowed then
		ServerNet.notify(helper, blocked :: string, "error")
		return
	end
	local record = Vitals.record(target)
	if not record or record.core.condition ~= "Downed" then
		return
	end
	local charId, token = record.core.charId, record.core.downToken
	local claimed, reason = RescueCore.claim(core, target, helper, token)
	if not claimed then
		ServerNet.notify(helper, if reason == "AlreadyBeingRevived" then "Someone is already reviving them." else "You cannot do that now.", "error")
		return
	end

	local function stillValid(): (boolean, string?)
		if not helper.Parent or not target.Parent then
			return false, "The revive was interrupted."
		end
		if Vitals.condition(helper) ~= "Alive" then
			return false, "You can no longer help."
		end
		local current = Vitals.record(target)
		if not current or current.core.charId ~= charId or current.core.downToken ~= token or current.core.condition ~= "Downed" then
			return false, "They no longer need reviving."
		end
		local a, b = Characters.liveRoot(helper), Characters.liveRoot(target)
		if not a or not b or (a.Position - b.Position).Magnitude > Config.Revive.MaxDistance then
			return false, "Stay close to revive them."
		end
		if not lineOfSight(a, b) then
			return false, "Something is in the way."
		end
		return true
	end

	local ok, why = stillValid()
	if not ok then
		RescueCore.release(core, target)
		ServerNet.notify(helper, why :: string, "error")
		return
	end

	local started = Busy.begin(helper, {
		kind = "Revive",
		duration = Config.Revive.Duration,
		interruptible = true,
		validate = stillValid,
		complete = function()
			RescueCore.release(core, target)
			clearProgress(target)
			if Vitals.revive(target, charId, token, Config.Revive.HealthRestored, helper.Name) then
				ServerNet.notify(helper, `You revived {target.Name}.`, "success")
				ServerNet.notify(target, `{helper.Name} revived you.`, "success")
			end
		end,
		cancelled = function(cancelReason)
			RescueCore.release(core, target)
			clearProgress(target)
			ServerNet.notify(helper, cancelReason, "error")
		end,
	})
	if not started then
		RescueCore.release(core, target)
		ServerNet.notify(helper, "You are busy.", "error")
		return
	end
	target:SetAttribute("HB_RescueBy", helper.Name)
	target:SetAttribute("HB_RescueEndsAt", workspace:GetServerTimeNow() + Config.Revive.Duration)
end

-- The helper let go of the prompt.
function Rescue.stopRevive(helper: Player)
	if RescueCore.targetOf(core, helper) ~= nil and Busy.kind(helper) == "Revive" then
		Busy.cancel(helper, "You let go. The revive stopped.")
	end
end

-- A downed player uses a self-rescue kit. Returns (ok, message).
function Rescue.beginSelfRescue(player: Player): (boolean, string)
	local allowed, blocked = Guard.check(player)
	if not allowed then
		return false, blocked :: string
	end
	local record = Vitals.record(player)
	if not record or record.core.condition ~= "Downed" then
		return false, "Self-rescue kits are used while downed."
	end
	if Gear.count(player, "RescueKit") < 1 then
		return false, "You have no self-rescue kit."
	end
	local runId = Expedition.runId(player)
	if not runId or Expedition.selfRescuesLeft(player) < 1 then
		return false, "You already used your self-rescue for this expedition."
	end
	if Busy.kind(player) then
		return false, "Already rescuing."
	end
	local charId, token = record.core.charId, record.core.downToken

	local started = Busy.begin(player, {
		kind = "SelfRescue",
		duration = Config.SelfRescue.Duration,
		interruptible = true,
		validate = function()
			local current = Vitals.record(player)
			if not current or current.core.charId ~= charId or current.core.downToken ~= token or current.core.condition ~= "Downed" then
				return false, "Self-rescue stopped."
			end
			if Gear.count(player, "RescueKit") < 1 then
				return false, "Your kit is gone."
			end
			if Expedition.runId(player) ~= runId then
				return false, "Self-rescue stopped."
			end
			return true
		end,
		complete = function()
			-- One non-yielding step: check, spend the allowance, the kit, then revive.
			local current = Vitals.record(player)
			if not current or current.core.downToken ~= token or current.core.condition ~= "Downed" then
				return
			end
			if Gear.count(player, "RescueKit") < 1 or not Expedition.useSelfRescue(player, runId) then
				ServerNet.notify(player, "Self-rescue failed.", "error")
				return
			end
			Gear.consume(player, "RescueKit", 1)
			Vitals.revive(player, charId, token, Config.SelfRescue.HealthRestored, "self-rescue kit")
			ServerNet.notify(player, "You got back on your feet. That was this expedition's self-rescue.", "success")
			ServerNet.pushState(player)
		end,
		cancelled = function(reason)
			ServerNet.notify(player, `{reason} The kit was not used.`, "error")
		end,
	})
	if not started then
		return false, "You are busy."
	end
	return true, "Using a self-rescue kit..."
end

local function onDowned(target: Player, record)
	removePrompt(target)
	local root = record.character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HB_RevivePrompt"
	prompt.ActionText = "Revive"
	prompt.ObjectText = target.DisplayName
	prompt.HoldDuration = Config.Revive.Duration -- visual only; the server times the revive
	prompt.MaxActivationDistance = Config.Revive.PromptDistance
	prompt.RequiresLineOfSight = true
	prompt.Parent = root
	prompts[target] = prompt

	-- Visible from a distance so other explorers can find them.
	local marker = Instance.new("BillboardGui")
	marker.Name = "HB_DownedMarker"
	marker.Size = UDim2.fromOffset(140, 28)
	marker.StudsOffset = Vector3.new(0, 4, 0)
	marker.AlwaysOnTop = true
	marker.MaxDistance = 150
	marker.Parent = root
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "DOWNED"
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 90, 80)
	label.TextStrokeTransparency = 0.2
	label.Parent = marker
	markers[target] = marker
	prompt.PromptButtonHoldBegan:Connect(function(helper)
		if helper ~= target then
			Rescue.beginRevive(helper, target)
		end
	end)
	prompt.PromptButtonHoldEnded:Connect(function(helper)
		Rescue.stopRevive(helper)
	end)
	ServerNet.notify(target, "You are down. Wait for a revive, or use a self-rescue kit.", "error")
end

local function onNoLongerDowned(target: Player)
	removePrompt(target)
	local entry = RescueCore.entry(core, target)
	if entry then
		Busy.cancel(entry.helper, "They no longer need reviving.")
		RescueCore.release(core, target)
	end
	clearProgress(target)
end

function Rescue.start()
	Vitals.onDowned(onDowned)
	Vitals.onRevived(onNoLongerDowned)
	Vitals.onDead(onNoLongerDowned)
	Players.PlayerRemoving:Connect(function(player)
		onNoLongerDowned(player)
		RescueCore.releaseHelper(core, player)
	end)
end

return Rescue
