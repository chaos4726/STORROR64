-- SM64Map input for the menus: keyboard and gamepad read the same way.
--
-- Everything is polled from the player controller once a tick: buttons with IsInputKeyDown, sticks with
-- GetInputAnalogKeyState. An "action" is a list of keys; `pressed` is true on the tick one of them goes down.
local lib = require("lib")
local M = {}

M.ACTIONS = {
    up = { "Up", "W", "Gamepad_DPad_Up" },
    down = { "Down", "S", "Gamepad_DPad_Down" },
    left = { "Left", "A", "Gamepad_DPad_Left" },
    right = { "Right", "D", "Gamepad_DPad_Right" },
    ok = { "Enter", "SpaceBar", "Gamepad_FaceButton_Bottom" },
    back = { "Escape", "BackSpace", "Gamepad_FaceButton_Right" },
    skip = { "Y", "Gamepad_FaceButton_Top" },            -- (a message skipped whole: dialog.lua)
    start = { "Enter", "Gamepad_Special_Right" },
    grab = { "SpaceBar", "Gamepad_FaceButton_Bottom", "Gamepad_RightTrigger", "Gamepad_LeftTrigger", "LeftMouseButton" },
}
local DEAD = 0.18               -- stick travel below this counts as none

local prev = {}

local function key_down(pc, name)
    local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(name) }) end)
    return ok and v == true
end

local function axis(pc, name)
    local ok, v = pcall(function() return pc:GetInputAnalogKeyState({ KeyName = FName(name) }) end)
    if not ok or type(v) ~= "number" then return 0.0 end
    if v > -DEAD and v < DEAD then return 0.0 end
    return (v > 0) and (v - DEAD) / (1.0 - DEAD) or (v + DEAD) / (1.0 - DEAD)
end

function M.down(action)
    local pc = lib.controller()
    if not pc then return false end
    for _, k in ipairs(M.ACTIONS[action] or {}) do
        if key_down(pc, k) then return true end
    end
    return false
end

-- true on the tick the action's button goes down; call once per tick per action
function M.pressed(action)
    local now = M.down(action)
    local was = prev[action]
    prev[action] = now
    return now and not was
end

-- forget what was held, so a button still down from the last screen does not count as pressed on this one
function M.reset()
    for a in pairs(M.ACTIONS) do prev[a] = M.down(a) end
end

-- Which way the cursor is being pushed: both sticks together, x to the right, y up, each -1..1.
function M.sticks()
    local pc = lib.controller()
    if not pc then return 0.0, 0.0 end
    local x = axis(pc, "Gamepad_LeftX") + axis(pc, "Gamepad_RightX")
    local y = axis(pc, "Gamepad_LeftY") + axis(pc, "Gamepad_RightY")
    return math.max(-1.0, math.min(1.0, x)), math.max(-1.0, math.min(1.0, y))
end

return M
