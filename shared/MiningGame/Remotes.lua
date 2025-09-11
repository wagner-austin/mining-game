--!strict
-- Remotes.lua (Accessor)
-- Dynamically discovers RemoteEvents and RemoteFunctions for client/server
-- This ensures any new remotes added to the server are automatically available

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Use canonical path: ReplicatedStorage.MiningGame.Remotes
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local folder = MiningGame:WaitForChild("Remotes")

export type RemotesIndex = {
    RF: {[string]: RemoteFunction},
    RE: {[string]: RemoteEvent},
    Folder: Folder,
}

local RF: {[string]: RemoteFunction} = {}
local RE: {[string]: RemoteEvent} = {}

local function indexChild(inst: Instance)
    if inst:IsA("RemoteFunction") then
        RF[inst.Name] = inst
    elseif inst:IsA("RemoteEvent") then
        RE[inst.Name] = inst
    end
end

-- Initial population - index all existing remotes
for _, child in ipairs(folder:GetChildren()) do
    indexChild(child)
end

-- Watch for new remotes added at runtime (future-proof)
folder.ChildAdded:Connect(indexChild)

-- Also handle removal in case remotes are destroyed
folder.ChildRemoved:Connect(function(inst: Instance)
    if inst:IsA("RemoteFunction") then
        RF[inst.Name] = nil
    elseif inst:IsA("RemoteEvent") then
        RE[inst.Name] = nil
    end
end)

return {
    RF = RF,
    RE = RE,
    Folder = folder,
} :: RemotesIndex
