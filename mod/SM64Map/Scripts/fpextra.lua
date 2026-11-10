-- SM64Map: the first person settings - the standalone StorrorFirstPerson mod's FIRST PERSON tab (fpmenu.lua), its rows
-- (fpsettings.lua), the settings themselves (fpconfig.lua, kept in fp_settings.txt), the crosshair, speedometer and
-- bars (fphud.lua), the help panel (fphelp.lua) and the flashlight key (fpkeys.lua) - for the mashup's own first person
-- mode only ("I also want to add this to my sm64 mod", then "the way I want it added to mario is only in the first person
-- mode. should not appear anywhere else", 2026-11-10).
--
-- Active only while a first-person file is being played (menu.lua's first_person(), the game state): then the tab is
-- on the pause menu and its settings, effects and keys work. Otherwise none of it shows: the tab is hidden on every menu
-- bar (and not even put on the list until a first-person file has been played), no crosshair, no speedometer, no keys.
-- The camera itself, fp.lua, reads the settings through _G.FP_CFG; game.lua runs it in first person as it always has.
-- (_G.FP_MASHUP leaves out what is the standalone mod's own: its FIRST PERSON on/off switch and F5 - here a file is
-- first person for good.)
local lib = require("lib")
local log = lib.log
local M = {}

_G.FP_MASHUP = true
local SCRIPT_DIR = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "")
local MOD_DIR = (SCRIPT_DIR:gsub("Scripts[/\\]$", ""))

local function load(name)
    local ok, m = xpcall(require, debug.traceback, name)
    if not ok then log("first person settings: %s failed to load: %s", name, tostring(m)); return nil end
    return m
end

local CFG = load("fpconfig")
if CFG then CFG.load(MOD_DIR .. "fp_settings.txt") end
_G.FP_CFG = CFG
local SET = load("fpsettings")
local FPM = load("fpmenu")
if FPM then FPM.icon_file = MOD_DIR .. "ui\\first_person_icon.png"; FPM.active = false end
_G.FP_MENU = FPM
local HUD = load("fphud")
local HELP = load("fphelp")
_G.FP_HELP = HELP
local KEYS = load("fpkeys")

local ever = false           -- (a first-person file played this session: only then is the tab put on the list)
local errored = {}
local function run(tag, fn, ...)
    if not fn then return end
    local ok, e = pcall(fn, ...)
    if not ok and not errored[tag] then errored[tag] = true; log("first person settings: %s: %s", tag, tostring(e)) end
end

-- every frame (main.lua)
function M.tick(dt)
    local MN = _G.MENU
    local active = false
    pcall(function() active = (MN and MN.first_person and MN.first_person() and MN.state == "game") and true or false end)
    if active then ever = true end
    if FPM then FPM.active = active end
    if CFG then run("config", CFG.tick) end
    if not ever then return end
    if active and SET then run("settings", SET.tick, dt) end
    if FPM then run("menu", FPM.tick, dt) end
    local fp_on = false
    pcall(function() local FPV = package.loaded["fp"]; fp_on = FPV and FPV.on() or false end)
    if HUD then run("hud", HUD.tick, dt, active and fp_on, FPM and FPM.is_menu_up or false) end
    if active and KEYS then run("keys", KEYS.tick, lib.controller()) end
    if HELP then run("help", HELP.tick, dt, active and FPM and FPM.tab_open or false) end
end

-- (a new map: nothing of the old one touched again - main.lua's FORGET_ON_MAP)
function M.forget()
    for _, m in ipairs({ SET, FPM, HUD, HELP }) do
        if m and m.forget then pcall(m.forget) end
    end
end

log("first person settings ready (%s)", CFG and "fp_settings.txt" or "no settings")
return M
