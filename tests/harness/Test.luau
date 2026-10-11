-- Minimal test framework for the offline runner.
local Test = {}

local results = { passed = 0, failed = 0, failures = {} :: { string } }
local currentSuite = ""

local function fmt(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

function Test.describe(name: string, body: () -> ())
	local previous = currentSuite
	currentSuite = if previous == "" then name else previous .. " › " .. name
	body()
	currentSuite = previous
end

function Test.it(name: string, body: () -> ())
	local label = currentSuite .. " › " .. name
	local ok, err = pcall(body)
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, label .. "\n      " .. tostring(err))
	end
end

function Test.expect(actual: any)
	local api = {}
	function api.toBe(expected: any)
		if actual ~= expected then
			error(`expected {fmt(expected)}, got {fmt(actual)}`, 2)
		end
	end
	function api.toBeNear(expected: number, tolerance: number?)
		local tol = tolerance or 1e-6
		if type(actual) ~= "number" or math.abs(actual - expected) > tol then
			error(`expected ~{expected} (±{tol}), got {fmt(actual)}`, 2)
		end
	end
	function api.toBeTruthy()
		if not actual then
			error(`expected truthy, got {fmt(actual)}`, 2)
		end
	end
	function api.toBeFalsy()
		if actual then
			error(`expected falsy, got {fmt(actual)}`, 2)
		end
	end
	function api.toBeGreaterThan(value: number)
		if not (actual > value) then
			error(`expected > {value}, got {fmt(actual)}`, 2)
		end
	end
	function api.toBeLessThan(value: number)
		if not (actual < value) then
			error(`expected < {value}, got {fmt(actual)}`, 2)
		end
	end
	function api.toContain(value: any)
		if type(actual) ~= "table" or not table.find(actual, value) then
			error(`expected list to contain {fmt(value)}`, 2)
		end
	end
	return api
end

function Test.results()
	return results
end

return Test
