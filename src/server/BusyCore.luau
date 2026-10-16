--[[
	Timed actions ("channels") such as bandaging, reviving, and self-rescue. Pure; the
	clock is passed in. Server only.

	One channel per key (player) at a time. Each channel is server-timed: completion
	depends only on the server clock, never on how long a client says it held a button.
	validate() runs on every step and cancels the channel the moment its conditions
	stop holding (distance, line of sight, character state, items).

	spec = {
		kind = string,
		duration = number,
		interruptible = boolean,          -- cancelled by interrupt() (taking damage)
		validate = () -> (boolean, string?),
		complete = () -> (),              -- called once, after the channel is removed
		cancelled = (reason: string) -> (),
	}
]]

local BusyCore = {}

function BusyCore.new()
	return { active = {}, nextToken = 0 }
end

function BusyCore.kind(b, key): string?
	local entry = b.active[key]
	return entry and entry.spec.kind
end

function BusyCore.entry(b, key)
	return b.active[key]
end

-- Returns (token) or (nil, "Busy").
function BusyCore.begin(b, key, spec, now: number): (number?, string?)
	if b.active[key] then
		return nil, "Busy"
	end
	b.nextToken += 1
	b.active[key] = { token = b.nextToken, spec = spec, startedAt = now, endsAt = now + spec.duration }
	return b.nextToken, nil
end

-- Cancels whatever the key is doing. Returns true if something was cancelled.
function BusyCore.cancel(b, key, reason: string): boolean
	local entry = b.active[key]
	if not entry then
		return false
	end
	b.active[key] = nil
	if entry.spec.cancelled then
		entry.spec.cancelled(reason)
	end
	return true
end

-- Cancels only interruptible channels (for example, when the player takes damage).
function BusyCore.interrupt(b, key, reason: string): boolean
	local entry = b.active[key]
	if entry and entry.spec.interruptible then
		return BusyCore.cancel(b, key, reason)
	end
	return false
end

-- Advances every channel: cancel the invalid ones, complete the finished ones.
function BusyCore.step(b, now: number)
	for key, entry in b.active do
		if b.active[key] ~= entry then
			continue -- replaced or cancelled by an earlier callback in this step
		end
		local ok, reason = true, nil
		if entry.spec.validate then
			ok, reason = entry.spec.validate()
		end
		if b.active[key] ~= entry then
			continue
		end
		if not ok then
			BusyCore.cancel(b, key, reason or "Invalid")
		elseif now >= entry.endsAt then
			b.active[key] = nil
			entry.spec.complete()
		end
	end
end

return BusyCore
