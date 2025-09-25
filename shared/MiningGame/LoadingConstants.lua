--!strict
-- LoadingConstants.lua
-- Centralized configuration for loading timeouts and retry policies

return table.freeze({
    TIMEOUTS = {
        AssetPreload    = 3.0,  -- Batch asset preloading
        ModuleRequire   = 8.0,  -- Dynamic module loading (allow for first-load hitches)
        CosmeticClient  = 1.0,  -- Client cosmetic assets
        ServiceInit     = 5.0,  -- Service initialization
        ServiceStart    = 0.0,  -- Disable soft timeout on Start by default
        RemoteCall      = 10.0, -- Remote function calls
        DataStoreOp     = 8.0,  -- DataStore Get/Set/Update operations
        MemoryStoreOp   = 4.0,  -- MemoryStore operations
        SpawnFinalize   = 5.0,  -- Wait for client streaming + ready handshake
    },
    
    RETRY = {
        AssetPreload = { 
            attempts = 2,      -- Try twice for critical assets
            backoff = 0.25     -- Quarter second between attempts
        },
        ModuleRequire = {
            attempts = 2,      -- Retry once in case of transient startup stalls
            backoff = 0.25
        },
        DataStore = {
            attempts = 3,      -- Retry a few times to ride out transient DS failures
            backoff = 0.5
        },
        MemoryStore = {
            attempts = 2,
            backoff = 0.25
        },
        CosmeticClient = {
            attempts = 1,      -- No retry (show placeholder)
            backoff = 0
        }
    },
    
    -- Poll intervals for timeout checks (0 = next frame)
    POLL_INTERVALS = {
        Default = 0,           -- Check every frame
        Coarse = 0.1,         -- Less frequent checks for non-critical
        Fine = 0.03,          -- More responsive for UX-critical
    }
})
