--[[
	Marks rare-relic carriers. Server side.

	Anyone carrying an unsecured relic of rank Config.RelicMark.MarkRank or higher
	(Divine, Godly) glows red for every player, through walls, until they register it at
	their base or lose it. Their character stays streamed in for everyone while marked.
	The pickup announcement itself is in WorldRelics.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HollowboundShared"):WaitForChild("Config"))

local RelicMarks = {}

local MARK_NAME = "HB_RelicMark"

local function carriesRare(store, player: Player): boolean
	for _, specimen in store:carried(player.UserId) do
		local tier = Config.RarityById[specimen.rarity]
		if not specimen.registered and tier and tier.rank >= Config.RelicMark.MarkRank then
			return true
		end
	end
	return false
end

local function setMark(player: Player, on: boolean)
	local character = player.Character
	player:SetAttribute("HB_Marked", on)
	if not character then
		return
	end
	local mark = character:FindFirstChild(MARK_NAME)
	if on and not mark then
		local highlight = Instance.new("Highlight")
		highlight.Name = MARK_NAME
		highlight.FillColor = Config.RelicMark.Color
		highlight.OutlineColor = Config.RelicMark.Color
		highlight.FillTransparency = 0.45
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = character
		pcall(function()
			character.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		end)
	elseif not on and mark then
		mark:Destroy()
		pcall(function()
			character.ModelStreamingMode = Enum.ModelStreamingMode.Default
		end)
	end
end

function RelicMarks.start(store)
	task.spawn(function()
		while true do
			task.wait(Config.RelicMark.CheckInterval)
			for _, player in Players:GetPlayers() do
				setMark(player, carriesRare(store, player))
			end
		end
	end)
end

return RelicMarks
