--[[
	One action layer for every input method. Each action has a single handler; keyboard
	keys and controller buttons are bound through ContextActionService, and on-screen
	buttons (mouse, touch, controller selection) call Actions.run with the same name.
	Nothing is keyboard-only: every action also has a controller binding and a button.

	Bindings (provisional):
	  UseSlot1/2/3     1 / 2 / 3        D-pad left / up / right
	  ToggleRelics     B                D-pad down
	  CloseMenu        (B toggles)      B button (only while the relic menu is open)
	  Attack           left click, F    R2            (milestone 4)
	  Supply           H                Y button      bandage / self-rescue kit; again cancels
	Touch uses the on-screen buttons for every action. A left click on UI never attacks.
]]

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Actions = {}

local DEFINITIONS = {
	UseSlot1 = { keys = { Enum.KeyCode.One, Enum.KeyCode.DPadLeft }, keyboard = "1", gamepad = "D-pad left" },
	UseSlot2 = { keys = { Enum.KeyCode.Two, Enum.KeyCode.DPadUp }, keyboard = "2", gamepad = "D-pad up" },
	UseSlot3 = { keys = { Enum.KeyCode.Three, Enum.KeyCode.DPadRight }, keyboard = "3", gamepad = "D-pad right" },
	ToggleRelics = { keys = { Enum.KeyCode.B, Enum.KeyCode.DPadDown }, keyboard = "B", gamepad = "D-pad down" },
	CloseMenu = { keys = { Enum.KeyCode.ButtonB }, keyboard = "B", gamepad = "B button" },
	Attack = { keys = { Enum.KeyCode.F, Enum.KeyCode.ButtonR2 }, keyboard = "F / click", gamepad = "R2", mouse = true },
	Supply = { keys = { Enum.KeyCode.H, Enum.KeyCode.ButtonY }, keyboard = "H", gamepad = "Y" },
}

local handlers: { [string]: (...any) -> () } = {}
local bound: { [string]: boolean } = {}
local inputChanged = Instance.new("BindableEvent")
Actions.inputChanged = inputChanged.Event

local function prefix(name: string): string
	return "Hollowbound_" .. name
end

function Actions.on(name: string, handler: (...any) -> ())
	assert(DEFINITIONS[name], "Unknown action " .. name)
	handlers[name] = handler
end

-- Runs an action as if its key were pressed. Buttons call this.
function Actions.run(name: string, ...)
	local handler = handlers[name]
	if handler then
		handler(...)
	end
end

-- Binds or unbinds an action's keyboard and controller inputs.
function Actions.setBound(name: string, enabled: boolean)
	local def = DEFINITIONS[name]
	if enabled and not bound[name] then
		bound[name] = true
		ContextActionService:BindAction(prefix(name), function(_, state)
			if state == Enum.UserInputState.Begin then
				Actions.run(name)
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, table.unpack(def.keys))
	elseif not enabled and bound[name] then
		bound[name] = nil
		ContextActionService:UnbindAction(prefix(name))
	end
end

-- Left click attacks only when the click was not used by UI or typing.
local mouseBound = false
function Actions.bindMouse()
	if mouseBound then
		return
	end
	mouseBound = true
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		for name, def in DEFINITIONS do
			if def.mouse and bound[name] then
				Actions.run(name)
			end
		end
	end)
end

local function kindOf(inputType: Enum.UserInputType): string?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif string.find(inputType.Name, "Gamepad") then
		return "Gamepad"
	elseif inputType == Enum.UserInputType.Keyboard or string.find(inputType.Name, "Mouse") then
		return "Keyboard"
	end
	return nil
end

local currentKind = kindOf(UserInputService:GetLastInputType())
	or (if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Touch" else "Keyboard")

-- "Keyboard" | "Gamepad" | "Touch"
function Actions.inputKind(): string
	return currentKind
end

-- Short hint for an action under the current input method ("" on touch).
function Actions.hint(name: string): string
	local def = DEFINITIONS[name]
	if currentKind == "Gamepad" then
		return def.gamepad
	elseif currentKind == "Touch" then
		return ""
	end
	return def.keyboard
end

UserInputService.LastInputTypeChanged:Connect(function(inputType)
	local kind = kindOf(inputType)
	if kind and kind ~= currentKind then
		currentKind = kind
		inputChanged:Fire(kind)
	end
end)

return Actions
