-- SM64Map: the secret unlocks, opened by beating Final Bowser (the fourth Bowser) - "after the player beats final bowser
-- the player unlocks a secret unlock. I want it to be the ghost runner skin", then "a secret unlock for iron man mode a
-- crown after completing final bowser, and a secret unlock for human mode a new setting in the settings that allows the
-- player to be gored in any mode just without the one tap ... last secret unlock will be a rainbow skin for beating
-- ironman mode and human mode together. all unlocks only open after beating 4th bowser", 2026-11-04:
--   ghost_runner  Final Bowser beaten in any file: the GHOST RUNNER skin (charmenu.lua SKIN, caps.lua M.skin)
--   crown         ... in an IRONMAN file: the CROWN (charmenu.lua HAT, caps.lua M.hat)
--   gore          ... in a HUMAN file: GORE in MARIO SETTINGS - a gruesome death in any mode, no one-hit death
--                 (msettings.lua, health.lua / game.lua / gore.lua through M.gore_any)
--   rainbow_skin  ... in a file both HUMAN and IRONMAN: the RAINBOW skin
-- For every file, kept "no matter what even if player deletes the save files": not in saves.lua but in a file of its
-- own beside it, and a second copy in the game's own Saved folder; either is read, both written.
local lib = require("lib")
local log = lib.log

local M = {}
M.NAMES = { "ghost_runner", "crown", "gore", "rainbow_skin" }
M.LABEL = { ghost_runner = "GHOST RUNNER skin", crown = "CROWN", gore = "GORE setting", rainbow_skin = "RAINBOW skin" }
-- (each one's message, by the modes the file was finished with - "you've unlocked "Example" for finishing the game with
-- "gamemodes". then explain where to find the setting or skin", 2026-11-04: tools/race_dialogs.py; told by ending.lua
-- once THE END is left or the credits skipped)
M.MSG = { ghost_runner = { [""] = 9014, iron = 9018, human = 9019, both = 9020 }, crown = { iron = 9015, both = 9021 },
          gore = { human = 9016, both = 9022 }, rainbow_skin = { both = 9017 } }
function M.msg_for(name, human, ironman)
    local k = (human and ironman) and "both" or (ironman and "iron") or (human and "human") or ""
    local t = M.MSG[name]
    return t and (t[k] or t[""] or t.both) or nil
end

local function paths()
    local out = { lib.MOD_DIR .. "secrets_unlocked.lua" }
    local base = os.getenv("LOCALAPPDATA")
    if base then out[#out + 1] = base .. "\\STORRORParkourPRO\\Saved\\SM64Map_secrets.lua" end
    return out
end

local state = nil           -- { open = { name = true }, gore_any = bool }
local function read_one(p)
    local f = io.open(p, "r")
    if not f then return nil end
    local src = f:read("a")
    f:close()
    local fn = load(src or "", "secrets", "t", {})
    local ok, t = pcall(fn or function() end)
    return (ok and type(t) == "table") and t or nil
end
local function load_state()
    if state then return state end
    state = { open = {}, gore_any = false }
    for _, p in ipairs(paths()) do
        local t = read_one(p)
        if t then
            for _, n in ipairs(M.NAMES) do if t[n] == true then state.open[n] = true end end
            if t.gore_any == true then state.gore_any = true end
        end
    end
    return state
end
local function write_state()
    local s = load_state()
    local parts = {}
    for _, n in ipairs(M.NAMES) do parts[#parts + 1] = string.format("%s = %s", n, tostring(s.open[n] == true)) end
    parts[#parts + 1] = "gore_any = " .. tostring(s.gore_any == true)
    local text = "-- SM64Map: the secrets unlocked by beating Final Bowser, for every save file (written by the mod)\nreturn { "
        .. table.concat(parts, ", ") .. " }\n"
    for _, p in ipairs(paths()) do
        local f = io.open(p, "w")
        if f then f:write(text); f:close() else log("secrets: could not write %s", p) end
    end
end

function M.has(name) return load_state().open[name] == true end
-- (opened now: true if it was not before)
function M.unlock(name)
    local s = load_state()
    if s.open[name] then return false end
    s.open[name] = true
    write_state()
    log("secrets: %s unlocked", tostring(M.LABEL[name] or name))
    return true
end

-- Final Bowser beaten (ending.lua E.start, as his rainbow star is taken) in a file that is `human`, `ironman` or both:
-- the secrets it opens, those new in a list, in the order to tell them
function M.final_beaten(human, ironman)
    local new = {}
    local function add(n) if M.unlock(n) then new[#new + 1] = n end end
    add("ghost_runner")
    if ironman then add("crown") end
    if human then add("gore") end
    if human and ironman then add("rainbow_skin") end
    return new
end

-- GORE (MARIO SETTINGS, once the HUMAN secret is open): a gruesome death in any mode - only when the power runs out,
-- not at the first hit
function M.gore_any() local s = load_state(); return s.open.gore == true and s.gore_any == true end
function M.gore_setting() return load_state().gore_any == true end
function M.set_gore_any(on)
    local s = load_state()
    on = on and true or false
    if s.gore_any == on then return end
    s.gore_any = on
    write_state()
    log("secrets: GORE %s", on and "on" or "off")
end

function M.reload() state = nil; return load_state() end
return M
