--[[
	Offline test runner: `lune run tests/run` from the repository root.
	Runs every tests/specs/*.spec.luau file. Exits non-zero on failure.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local Test = require("./harness/Test")

local filter = process.args[1]
local files = fs.readDir("tests/specs")
table.sort(files)
for _, file in files do
	if string.match(file, "%.spec%.luau$") and (not filter or string.find(file, filter, 1, true)) then
		local spec = require("./specs/" .. string.gsub(file, "%.luau$", ""))
		if type(spec) == "function" then
			spec(Test)
		end
	end
end

local results = Test.results()
for _, failure in results.failures do
	print("✗ " .. failure)
end
print(string.format("\n%d passed, %d failed", results.passed, results.failed))
if results.failed > 0 then
	process.exit(1)
end
