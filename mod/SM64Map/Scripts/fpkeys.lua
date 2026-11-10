-- STORROR First Person: a button of the mod's own ("all of it", 2026-11-09 - from a list), with its switch on the FIRST
-- PERSON tab:
--   FIRST/THIRD PERSON BUTTON (on to start): F5, or both sticks clicked together - first person on or off, as the FIRST
--     PERSON switch, without going to the menu. Not while one of STORROR's menus is up.
--   FLASHLIGHT: L turns it on and off (as its switch on the tab), "flashlight", 2026-11-09
-- (QUICK TURN - Q or the right stick, half round in a moment - was here too: "remove the quick turn", 2026-11-09)
local M = {}

local KEYS, was = {}, {}
local function key(name)
    local k = KEYS[name]
    if not k then k = { KeyName = FName(name) }; KEYS[name] = k end
    return k
end
local function down(pc, name)
    local ok, v = pcall(function() return pc:IsInputKeyDown(key(name)) end)
    return ok and v == true
end
-- (pressed this frame, not before)
local function pressed(id, now)
    local p = now and not was[id]
    was[id] = now
    return p
end

function M.tick(pc)
    if not pc then return end
    local C = _G.FP_CFG
    if not C then return end
    local menu = _G.FP_MENU and _G.FP_MENU.is_menu_up
    local both = down(pc, "Gamepad_LeftThumbstick") and down(pc, "Gamepad_RightThumbstick")
    if pressed("view", down(pc, "F5") or both) and not menu and C.num("view_key") >= 0.5 and _G.FP_SETTING then
        _G.FP_SETTING.set(not _G.FP_SETTING.get())
    end
    if pressed("light", down(pc, "L")) and not menu then
        C.set("flashlight", C.num("flashlight") >= 0.5 and 0 or 1)
    end
end

return M
