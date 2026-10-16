-- Minimal test helpers. Failures print as warnings; each suite prints one summary line.

local TestKit = {}

function TestKit.suite(name: string)
	local suite = { name = name, total = 0, failures = 0 }
	function suite.check(condition: any, label: string)
		suite.total += 1
		if not condition then
			suite.failures += 1
			warn(`  FAIL [{name}] {label}`)
		end
	end
	return suite
end

-- Counter-based IDs so test specimens never look like real GUIDs.
function TestKit.idMaker(prefix: string)
	local counter = 0
	return function()
		counter += 1
		return `{prefix}-{counter}`
	end
end

return TestKit
