--!strict
-- LoadingConstants.lua
-- Centralized configuration for loading timeouts and retry policies

return table.freeze({
    TIMEOUTS = {
        AssetPreload    = 3.0,  -- Batch asset preloading
        ModuleRequire   = 2.0,  -- Dynamic module loading
        CosmeticClient  = 1.0,  -- Client cosmetic assets
        ServiceInit     = 5.0,  -- Service initialization
        RemoteCall      = 10.0, -- Remote function calls
        SpawnFinalize   = 5.0,  -- Wait for client streaming + ready handshake
    },
    
    RETRY = {
        AssetPreload = { 
            attempts = 2,      -- Try twice for critical assets
            backoff = 0.25     -- Quarter second between attempts
        },
        ModuleRequire = {
            attempts = 1,      -- No retry for modules (fail fast)
            backoff = 0
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
