--!strict
-- AssetRegistry.lua
-- Handles loading and caching of models from asset packs for PCG system

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local Timeout = require(Shared:WaitForChild("Timeout"))
local LoadCfg = require(Shared:WaitForChild("LoadingConstants"))
local log = Logger.new("AssetRegistry")

-- Get PCGConfig if available (safe for strict mode)
local PCGConfig = nil
local ok, config = pcall(function()
    local pcgConfigModule = script.Parent:FindFirstChild("PCGConfig")
    if pcgConfigModule then
        return require(pcgConfigModule)
    end
    return nil
end)
if ok and config then
    PCGConfig = config
end

local AssetRegistry = {}

-- Cache for loaded assets
local assetCache: {[string]: Model?} = {}
local packsLoaded = false

-- Asset pack locations
local ASSET_ROOT = ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("Assets")

-- Helper: preload assets with timeout and retry
local function preloadWithTimeout(instances: {Instance}): boolean
    -- Only preload on client (no-op on server)
    if not RunService:IsClient() then
        return true
    end
    
    local t = LoadCfg.TIMEOUTS.AssetPreload
    local retry = LoadCfg.RETRY.AssetPreload
    
    local ok = Timeout.runWithRetry(function()
        ContentProvider:PreloadAsync(instances)
    end, t, retry.attempts, retry.backoff)
    
    if not ok then
        log:warn("Preload timeout after %.2fs on %d assets", t, #instances)
        return false
    end
    return true
end

-- Helper to count dictionary entries
local function dictCount(t: {[string]: any}): number
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

-- Helper to index all models in a pack (including nested)
local function indexPack(pack: Instance, prefix: string)
    for _, child in ipairs(pack:GetDescendants()) do
        if child:IsA("Model") and child ~= pack then
            -- Avoid duplicates by checking if already cached
            local key = prefix .. child.Name
            if not assetCache[key] then
                assetCache[key] = child
                
                -- Debug: Analyze model contents
                local partCount = 0
                local surfaceAppearances = 0
                local textures = 0
                local decals = 0
                
                for _, desc in ipairs(child:GetDescendants()) do
                    if desc:IsA("BasePart") then
                        partCount = partCount + 1
                    elseif desc:IsA("SurfaceAppearance") then
                        surfaceAppearances = surfaceAppearances + 1
                    elseif desc:IsA("Texture") then
                        textures = textures + 1
                    elseif desc:IsA("Decal") then
                        decals = decals + 1
                    end
                end
                
                log:debug("Indexed %s: %s - %d parts, %d SurfaceAppearances, %d Textures, %d Decals", 
                    prefix:sub(1, -2), child.Name, partCount, surfaceAppearances, textures, decals)
            end
        end
    end
end

-- Initialize and index all assets from packs
local function loadPacks()
    if packsLoaded then return end
    packsLoaded = true
    
    -- Load tree models (including nested)
    local treePack = ASSET_ROOT:FindFirstChild("Trees")
    if treePack then
        indexPack(treePack, "tree_")
    end
    
    -- Load rock models (including nested)
    local rockPack = ASSET_ROOT:FindFirstChild("Rocks")
    if rockPack then
        indexPack(rockPack, "rock_")
    end
    
    -- Load foliage models (including nested)
    local foliagePack = ASSET_ROOT:FindFirstChild("Foliage")
    if foliagePack then
        indexPack(foliagePack, "foliage_")
    end
    
    log:info("Loaded %d assets from packs", dictCount(assetCache))
    
    -- Batch preload assets with timeout (small batches to reduce blocking)
    local batch, bucket = {}, 0
    for key, model in pairs(assetCache) do
        table.insert(batch, model)
        bucket = bucket + 1
        if bucket == 25 then  -- Small batches reduce blocked time
            preloadWithTimeout(batch)
            batch, bucket = {}, 0
        end
    end
    if bucket > 0 then 
        preloadWithTimeout(batch)
    end
end

-- Helper to check if a texture ID is valid (not empty, not 0, not placeholder)
local function isValidAssetId(str: string?): boolean
    if not str or str == "" then return false end
    
    -- Extract numeric ID from various URL formats
    local id = str:match("^rbxassetid://(%d+)$")
            or str:match("^rbxasset://.-%?id=(%d+)$")
            or str:match("[?&]id=(%d+)$")
            or str:match("/(%d+)$")  -- last path segment
    
    local numId = tonumber(id or "")
    return numId ~= nil and numId > 0
end

-- Helper to sort variant lists for determinism
local function sorted(list: {string}): {string}
    table.sort(list, function(a, b) return a < b end)
    return list
end

-- Get all available tree variants (sorted for determinism)
function AssetRegistry.GetTreeVariants(): {string}
    loadPacks()
    local variants = {}
    for key, _ in pairs(assetCache) do
        if string.sub(key, 1, 5) == "tree_" then
            table.insert(variants, string.sub(key, 6))
        end
    end
    return sorted(variants)
end

-- Get all available rock variants (sorted for determinism)
function AssetRegistry.GetRockVariants(): {string}
    loadPacks()
    local variants = {}
    for key, _ in pairs(assetCache) do
        if string.sub(key, 1, 5) == "rock_" then
            table.insert(variants, string.sub(key, 6))
        end
    end
    return sorted(variants)
end

-- Get all available foliage variants (sorted for determinism)
function AssetRegistry.GetFoliageVariants(): {string}
    loadPacks()
    local variants = {}
    for key, _ in pairs(assetCache) do
        if string.sub(key, 1, 8) == "foliage_" then
            table.insert(variants, string.sub(key, 9))
        end
    end
    return sorted(variants)
end

-- Get a tree model by name
function AssetRegistry.GetTree(name: string): Model?
    loadPacks()
    return assetCache["tree_" .. name]
end

-- Get a rock model by name
function AssetRegistry.GetRock(name: string): Model?
    loadPacks()
    return assetCache["rock_" .. name]
end

-- Get a foliage model by name
function AssetRegistry.GetFoliage(name: string): Model?
    loadPacks()
    return assetCache["foliage_" .. name]
end

-- Get any decoration by type and name
function AssetRegistry.GetDecoration(decorationType: string, name: string): Model?
    loadPacks()
    
    if decorationType == "tree" then
        return AssetRegistry.GetTree(name)
    elseif decorationType == "rock" then
        return AssetRegistry.GetRock(name)
    elseif decorationType == "foliage" then
        return AssetRegistry.GetFoliage(name)
    end
    
    -- Try generic lookup
    return assetCache[decorationType .. "_" .. name]
end

-- Clone and prepare a model for placement
function AssetRegistry.PrepareModel(template: Model, position: Vector3, scale: number, yaw: number?, decorationType: string?): Model?
    local model = template:Clone()
    
    -- Set category on the clone (not the template)
    if decorationType then
        model:SetAttribute("Category", decorationType)
    end
    
    -- Ensure model has a primary part for positioning
    if not model.PrimaryPart then
        -- Try to find a suitable primary part
        local largestPart: BasePart? = nil
        local largestSize = 0
        
        for _, desc in ipairs(model:GetDescendants()) do
            if desc:IsA("BasePart") then
                local size = desc.Size.Magnitude
                if size > largestSize then
                    largestSize = size
                    largestPart = desc
                end
            end
        end
        
        if largestPart then
            model.PrimaryPart = largestPart
        else
            log:warn("Model %s has no suitable parts for PrimaryPart", template.Name)
            model:Destroy()
            return nil
        end
    end
    
    -- Debug: Log model information
    log:debug("PrepareModel: %s, scale=%f, parts=%d", 
        template.Name, scale, #model:GetDescendants())
    
    -- Apply scale
    if scale ~= 1 then
        log:debug("Scaling model %s to %f", template.Name, scale)
        model:ScaleTo(scale)
    end
    
    -- Position and rotate (use provided yaw for determinism)
    local angle = yaw or 0
    model:PivotTo(CFrame.new(position) * CFrame.Angles(0, angle, 0))
    
    -- Normalize materials and optimize collisions
    local partCount = 0
    local normalizedCount = 0
    local skippedFX = 0
    local skippedTextured = 0
    local textureCount = 0
    local surfaceAppearanceCount = 0
    local materials = {}
    
    -- Get model category from attribute or use decoration type parameter
    local category = model:GetAttribute("Category") or decorationType or ""
    local isTreeModel = category == "tree"
    local isFoliageModel = category == "foliage"
    
    -- Check for model-specific normalization override
    local normalizeMode = tostring(model:GetAttribute("NormalizeMode") or "")
    local forceOff = normalizeMode == "off"
    local forceAggressive = normalizeMode == "aggressive"
    
    -- Determine if we should use aggressive normalization (with safe config access)
    local aggressiveConfig = PCGConfig and PCGConfig.AssetRegistry and PCGConfig.AssetRegistry.AGGRESSIVE_TREE_NORMALIZE
    local useAggressiveMode = forceAggressive or ((isTreeModel or isFoliageModel) and aggressiveConfig == true)
    
    -- Log normalization mode once per model
    if useAggressiveMode then
        log:debug("Model %s: Aggressive normalization enabled (category=%s, mode=%s)", 
            template.Name, category, normalizeMode)
    elseif forceOff then
        log:debug("Model %s: Normalization disabled (NormalizeMode=off)", template.Name)
    else
        log:debug("Model %s: Standard normalization (category=%s)", template.Name, category)
    end
    
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") then
            desc.Anchored = true
            partCount = partCount + 1
            
            -- Classify part by name
            local name = desc.Name:lower()
            local isLeaf = name:find("leaf") or name:find("leaves") or name:find("needle") or name:find("pine") or 
                          name:find("foliage") or name:find("canopy")
            local isTrunk = name:find("trunk") or name:find("bark") or name:find("stem") or name:find("log") or 
                           name:find("branch") or name:find("wood")
            
            -- For trees/foliage, FX is opt-in only. For other models, check names too
            local isFX
            if isTreeModel or isFoliageModel then
                isFX = desc:GetAttribute("KeepMaterial") == true
                if isFX then
                    log:debug("  Part %s marked as FX (KeepMaterial=true)", desc.Name)
                end
            else
                local isFXByName = name:find("fx") or name:find("glow") or name:find("light")
                isFX = isFXByName or desc:GetAttribute("KeepMaterial") == true
            end
            
            -- Optional explicit role attribute
            local roleAttr = desc:GetAttribute("Role")
            if roleAttr == "leaf" then isLeaf = true end
            if roleAttr == "trunk" then isTrunk = true end
            
            -- Use shape heuristic if names don't help (for trees/foliage)
            if (not isLeaf and not isTrunk) and (isTreeModel or isFoliageModel) then
                local s = desc.Size
                local slender = s.Y > math.max(s.X, s.Z) * 2.0  -- tall & thin = trunk
                if slender then 
                    isTrunk = true
                else 
                    isLeaf = true  -- broad parts are likely canopy/leaves
                end
            end
            
            -- Check if part has textures/PBR we should respect
            local hasPBR = false
            local hasSpecialMeshTex = false
            
            if isTreeModel or isFoliageModel then
                -- For trees/foliage, only respect real texture IDs (not placeholders)
                if desc:IsA("MeshPart") and isValidAssetId(desc.TextureID) then
                    hasPBR = true
                    log:debug("  Part %s has valid TextureID: %s", desc.Name, desc.TextureID)
                end
                
                local sm = desc:FindFirstChildOfClass("SpecialMesh")
                if sm and isValidAssetId(sm.TextureId) then
                    hasSpecialMeshTex = true
                    log:debug("  Part %s has valid SpecialMesh.TextureId: %s", desc.Name, sm.TextureId)
                end
            else
                -- For non-tree models, be more permissive
                hasPBR = (desc:IsA("MeshPart") and desc.TextureID ~= "" and desc.TextureID ~= nil)
                local sm = desc:FindFirstChildOfClass("SpecialMesh")
                hasSpecialMeshTex = (sm and sm.TextureId ~= "" and sm.TextureId ~= nil)
            end
            
            local hasSurfaceAppearance = desc:FindFirstChildOfClass("SurfaceAppearance") ~= nil
            local hasDecal = desc:FindFirstChildOfClass("Decal") ~= nil
            local hasTextureObj = desc:FindFirstChildOfClass("Texture") ~= nil
            
            local isTextured = hasPBR or hasSurfaceAppearance or hasSpecialMeshTex or hasDecal or hasTextureObj
            
            -- Track skipped reasons for debugging with more detail
            if isFX then 
                skippedFX = skippedFX + 1
                log:debug("  Part %s skipped - marked as FX", desc.Name)
            end
            if isTextured then 
                skippedTextured = skippedTextured + 1
                log:debug("  Part %s skipped - textures detected (PBR:%s, SA:%s, SM:%s, Decal:%s, Tex:%s)", 
                    desc.Name, 
                    tostring(hasPBR), 
                    tostring(hasSurfaceAppearance),
                    tostring(hasSpecialMeshTex),
                    tostring(hasDecal),
                    tostring(hasTextureObj))
            end
            
            -- Track original material before normalization
            local mat = desc.Material
            materials[tostring(mat)] = (materials[tostring(mat)] or 0) + 1
            
            -- Handle normalization based on mode and settings
            if forceOff then
                -- Skip all normalization for this model
                log:debug("  Part %s: normalization disabled (NormalizeMode=off)", desc.Name)
            elseif not isFX then
                local shouldNormalize = false
                local wasTextured = isTextured
                
                -- Determine if we should normalize this part
                if useAggressiveMode then
                    -- Aggressive mode: normalize even if textured (for trees/foliage)
                    if mat == Enum.Material.Neon or mat == Enum.Material.ForceField or 
                       mat == Enum.Material.Fabric or mat == Enum.Material.Glass or
                       mat == Enum.Material.Ice then
                        shouldNormalize = true
                    end
                elseif not isTextured then
                    -- Safe mode: only normalize if not textured
                    if (isTreeModel or isFoliageModel) then
                        if mat == Enum.Material.Neon or mat == Enum.Material.ForceField or 
                           mat == Enum.Material.Fabric or mat == Enum.Material.Glass or
                           mat == Enum.Material.Ice then
                            shouldNormalize = true
                        end
                    elseif mat == Enum.Material.Neon or mat == Enum.Material.ForceField then
                        -- Only normalize obviously wrong materials for non-tree models
                        shouldNormalize = true
                    end
                end
                
                -- Apply normalization
                if shouldNormalize then
                    local oldMat = mat
                    if isTreeModel or isFoliageModel then
                        -- Use appropriate materials for trees/foliage
                        if isLeaf then
                            desc.Material = Enum.Material.SmoothPlastic -- Cleaner for leaves than Grass
                        else
                            desc.Material = Enum.Material.Wood -- Wood for trunks and branches
                        end
                    else
                        -- Generic normalization for other models
                        desc.Material = Enum.Material.Plastic
                    end
                    normalizedCount = normalizedCount + 1
                    
                    -- Enhanced logging to show when aggressive mode overrode texture detection
                    if wasTextured and useAggressiveMode then
                        log:debug("  Normalized %s from %s to %s (AGGRESSIVE: was textured, classified: %s)", 
                            desc.Name, tostring(oldMat), tostring(desc.Material),
                            isLeaf and "leaf" or isTrunk and "trunk" or "part")
                    else
                        log:debug("  Normalized %s from %s to %s (classified: %s)", 
                            desc.Name, tostring(oldMat), tostring(desc.Material),
                            isLeaf and "leaf" or isTrunk and "trunk" or "part")
                    end
                end
            end
            
            -- Optimize leaf collision and shadows (including guessed leaves)
            if isLeaf then
                desc.CanCollide = false
                desc.CanTouch = false
                desc.CanQuery = false
                desc.CastShadow = false -- Better performance for leaves
            end
        elseif desc:IsA("Texture") or desc:IsA("Decal") then
            textureCount = textureCount + 1
            log:debug("  Found %s: %s on %s", desc.ClassName, desc.Name, desc.Parent.Name)
        elseif desc:IsA("SurfaceAppearance") then
            surfaceAppearanceCount = surfaceAppearanceCount + 1
            log:debug("  SurfaceAppearance on %s: ColorMap=%s, NormalMap=%s", 
                desc.Parent.Name, 
                tostring(desc.ColorMap), 
                tostring(desc.NormalMap))
        end
    end
    
    -- Log summary
    log:debug("Model %s: %d parts (%d normalized), %d textures, %d surface appearances", 
        template.Name, partCount, normalizedCount, textureCount, surfaceAppearanceCount)
    log:debug("  Skipped: FX=%d, Textured=%d", skippedFX, skippedTextured)
    
    -- Log materials used
    for mat, count in pairs(materials) do
        log:debug("  Material %s: %d parts", mat, count)
    end
    
    return model
end

-- Get a random variant from available assets
function AssetRegistry.GetRandomVariant(decorationType: string, rng: Random?): string?
    local variants
    if decorationType == "tree" then
        variants = AssetRegistry.GetTreeVariants()
    elseif decorationType == "rock" then
        variants = AssetRegistry.GetRockVariants()
    elseif decorationType == "foliage" then
        variants = AssetRegistry.GetFoliageVariants()
    else
        return nil
    end
    
    if #variants == 0 then
        return nil
    end
    
    if rng then
        return variants[rng:NextInteger(1, #variants)]
    else
        return variants[Random.new():NextInteger(1, #variants)]
    end
end

-- Initialize on first require
loadPacks()

return AssetRegistry
