--!strict
-- Creates a ClothSimulator tool in StarterPack for testing
-- The tool spawns/destroys cloth when equipped/unequipped

local StarterPack = game:GetService("StarterPack")

local tool = Instance.new("Tool")
tool.Name = "ClothSimulator"
tool.RequiresHandle = false
tool.CanBeDropped = false
tool.Parent = StarterPack

print("[CreateClothTool] ClothSimulator tool created in StarterPack")