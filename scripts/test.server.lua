--!strict
-- scripts/test.server.lua
-- Headless TestEZ bootstrap for run-in-roblox

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function findModuleInPackages(packages: Instance, targetName: string): ModuleScript?
	local direct = packages:FindFirstChild(targetName)
	if direct and direct:IsA("ModuleScript") then
		return direct
	end
	local index = packages:FindFirstChild("_Index")
	if index then
		for _, scope in ipairs(index:GetChildren()) do
			for _, desc in ipairs(scope:GetDescendants()) do
				if desc:IsA("ModuleScript") and desc.Name == targetName then
					return desc
				end
			end
		end
	end
	return nil
end

type TestEZModule = {
	TestBootstrap: { run: (modules: { Instance }, reporter: any) -> { failureCount: number } },
	Reporters: { TextReporter: any },
}

local function getTestEZ(): TestEZModule
	local packages = ReplicatedStorage:FindFirstChild("Packages")
	assert(
		packages,
		"Packages folder not found. Run `wally install` and ensure Rojo maps Packages -> ReplicatedStorage/Packages."
	)
	local mod = findModuleInPackages(packages, "TestEZ")
	assert(mod, "Could not locate TestEZ in Packages. Did you run `wally install`?")
	return require(mod)
end

local function run()
	local TestEZ = getTestEZ()
	local testsFolder = ReplicatedStorage:FindFirstChild("Tests")
	assert(testsFolder, "ReplicatedStorage.Tests folder not found")

	local TextReporter = TestEZ.Reporters.TextReporter
	local results = TestEZ.TestBootstrap.run({ testsFolder }, TextReporter)

	if results.failureCount > 0 then
		error(string.format("Test failures: %d", results.failureCount))
	end
	print("All tests passed")
end

run()
