--!strict
-- scripts/run-tests.luau
-- Lune test runner — discovers and runs all *.spec.lua(u) files under tests/

local fs = require("@lune/fs")
local process = require("@lune/process")

local TestRunner = require("./testez-lite")

local TESTS_DIR = "tests"

local function discoverSpecs(dir: string): { string }
	local specs: { string } = {}
	if not fs.isDir(dir) then
		return specs
	end
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			for _, nested in discoverSpecs(path) do
				table.insert(specs, nested)
			end
		elseif string.match(entry, "%.spec%.luau?$") then
			table.insert(specs, path)
		end
	end
	return specs
end

local specPaths = discoverSpecs(TESTS_DIR)

if #specPaths == 0 then
	print("No spec files found in " .. TESTS_DIR .. "/")
	process.exit(1)
end

print(string.format("Found %d spec file(s)\n", #specPaths))

local specFiles: { { name: string, fn: () -> () } } = {}

for _, path in specPaths do
	local mod = require("../" .. string.gsub(path, "%.luau?$", ""))
	if type(mod) == "function" then
		table.insert(specFiles, { name = path, fn = mod })
	else
		print("WARN: " .. path .. " did not return a function, skipping")
	end
end

local _, failCount = TestRunner.run(specFiles)

if failCount > 0 then
	process.exit(1)
end
