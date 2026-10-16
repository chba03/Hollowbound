--[[
	DEVELOPMENT ONLY. Runs the automated logic tests at server start in Studio and
	prints one summary line per suite (failures print as warnings).

	Storage: these tests use MockBackend, an isolated in-memory TEST-ONLY backend. They
	never call ProfileStore or DataStores, so they cannot touch saved player data. They
	check the game's rules, not real DataStore behaviour (see docs/TESTING.md).
]]

local Tests = script.Parent.Tests

local SelfTest = {}

local SUITES = {
	Tests.StoreTests,
	Tests.AbilityTests,
	Tests.PersistenceTests,
	Tests.SurvivalTests,
	Tests.CreatureTests,
	Tests.WorldTests,
}

function SelfTest.run(): boolean
	print("[Hollowbound] Self-test (mock storage only):")
	local total, failures = 0, 0
	for _, module in SUITES do
		local ok, result = pcall(function()
			return require(module)()
		end)
		if ok then
			total += result.total
			failures += result.failures
			print(`  {result.name}: {result.total - result.failures}/{result.total} passed`)
		else
			failures += 1
			total += 1
			warn(`  FAIL [{module.Name}] suite crashed: {result}`)
		end
	end
	print(`[Hollowbound] Self-test finished: {total - failures}/{total} passed`)
	return failures == 0
end

return SelfTest
