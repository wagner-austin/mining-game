--!strict
-- retro.lua
-- Example retro/8-bit sound pack (partial overrides)
-- Using test sound ID for verification - replace with actual retro sounds later

return {
    ui = {
        buttonclick  = "rbxassetid://9120386436",  -- Test click sound
        notification = "rbxassetid://9120386436",
        error        = "rbxassetid://9120386436",
    },
    music = { 
        main = "rbxassetid://9120386436" 
    },
    mining = {
        rock = { 
            hit = "rbxassetid://9120386436", 
            ["break"] = "rbxassetid://9120386436"  -- 'break' is a reserved keyword, need brackets
        }
    },
}