--!strict
-- Selene: allow test globals
--# selene: allow(global_usage, undefined_variable)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local MathUtils = require(MiningGame:WaitForChild("MathUtils"))

return function()
    describe("MathUtils.nonNegative", function()
        it("clamps negatives to 0", function()
            expect(MathUtils.nonNegative(-5)).to.equal(0)
        end)

        it("passes positives through", function()
            expect(MathUtils.nonNegative(3.2)).to.equal(3.2)
        end)
    end)

    describe("MathUtils.saturatingSub", function()
        it("never goes below 0", function()
            expect(MathUtils.saturatingSub(3, 10)).to.equal(0)
        end)

        it("subtracts when positive", function()
            expect(MathUtils.saturatingSub(10, 3)).to.equal(7)
        end)
    end)

    describe("MathUtils.clampRange", function()
        it("clamps below min", function()
            expect(MathUtils.clampRange(-1, 0, 5)).to.equal(0)
        end)

        it("clamps above max", function()
            expect(MathUtils.clampRange(10, 0, 5)).to.equal(5)
        end)

        it("passes through within range", function()
            expect(MathUtils.clampRange(3, 0, 5)).to.equal(3)
        end)
    end)

    describe("MathUtils.clamp01", function()
        it("clamps to 0..1", function()
            expect(MathUtils.clamp01(-0.25)).to.equal(0)
            expect(MathUtils.clamp01(1.25)).to.equal(1)
        end)
    end)
end

