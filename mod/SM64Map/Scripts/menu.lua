-- SM64Map boot flow: empty-map boot (no city, no campaign), SM64 sky + lighting, and the 4-file "SELECT FILE" menu.
local lib = require("lib")
local M = {}

local OFFSET = lib.OFFSET
local log = lib.log
local pad = require("pad")
local okT, TITLE = pcall(require, "title")
if not okT then log("the title screen did not load: %s", tostring(TITLE)); TITLE = nil end
local okF, FILM = pcall(require, "film")
if not okF then log("the film did not load: %s", tostring(FILM)); FILM = nil end
local okE, ENDING = pcall(require, "ending")
if not okE then lib.log("the ending did not load: %s", tostring(ENDING)); ENDING = nil end
local okI, INTRO = pcall(require, "intro")
if not okI then log("the opening for a new file did not load: %s", tostring(INTRO)); INTRO = nil end
local okL, LOGO = pcall(require, "logo")
if not okL then log("the opening logo did not load: %s", tostring(LOGO)); LOGO = nil end
local okS, SFX = pcall(require, "sfx")
if not okS then log("the sound effects did not load: %s", tostring(SFX)); SFX = nil end

-- the file select's sounds, as menu/file_select.c plays them (rendered from the player's ROM, see sfx.lua)
local function sound(name) if SFX then pcall(SFX.play, name) end end

-- Leaving the file select for a file (Mario 64's timings, 30 frames a second): the picked button has its moment
-- (Mario 64 zooms it up over about 16 frames), the screen fades to white over 16, stays white for 8, and the game
-- fades in from white over 16. The fade is the camera's own, so it carries over into the game.
local LEAVE_WAIT, LEAVE_FADE, LEAVE_HOLD, ARRIVE_FADE = 0.35, 16 / 30, 8 / 30, 16 / 30
local WHITE = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
local function camera_fade(from, to, secs, hold)
    pcall(function()
        lib.controller().PlayerCameraManager:StartCameraFade(from, to, secs, WHITE, false, hold)
    end)
end

M.state = "boot"            -- boot | title | menu | game
M.AUTO_TRAVEL = true        -- if the game still boots into the city map, jump to the empty map
M.EMPTY_MAP = "/SPP/Maps/Multiplayer/DedicatedServerEmptyMap"
M.GAME_MODE = "/SPP/Blueprints/MMGameMode.MMGameMode_C"

-- ------------------------------------------------------------------ saves
local SAVE_PATH = lib.MOD_DIR .. "saves.lua"
local saves = nil

local function default_saves()
    -- (a new player's settings: REMIX MUSIC, REAL TIME SHADOWS and RENDER 96 on - "before even launching into the game these options should be ticked or on", 2026-11-01)
    local s = { last = 1, timer = false, files = {}, mario_music = 1.0, jump_voice = 1.0, enemies_volume = 1.0, general_volume = 1.0, realtime_shadows = 1.0, render96 = 1.0,
                remix_music = 1.0, human_mode = false, ironman = false }
    for i = 1, 4 do s.files[i] = { used = false, stars = 0 } end
    return s
end

local function write_saves()
    -- (his lives kept with his file as they stand, each time it is written - every 15 s of play, and each star: they were
    -- read from it but never put back, and a restart gave him four again - "dont the lives save?", 2026-11-04.
    -- M.lives_file: the file whose lives HEALTH holds, from when it was picked)
    local MM = _G.MENU
    local lf = MM and MM.lives_file
    if lf and saves and saves.files and saves.files[lf] and _G.HEALTH and type(_G.HEALTH.lives) == "number" then
        saves.files[lf].lives = math.floor(_G.HEALTH.lives)
    end
    local f = io.open(SAVE_PATH, "w")
    if not f then log("could not write %s", SAVE_PATH); return end
    f:write("-- SM64Map save files (written by the mod)\nreturn {\n  last = ", tostring(saves.last),
        ",\n  timer = ", tostring(saves.timer and true or false), ",\n  first_person = ",
        tostring(saves.first_person and true or false), ",\n  mario_music = ", string.format("%.2f", saves.mario_music or 1.0),
        ",\n  jump_voice = ", string.format("%.2f", saves.jump_voice or 1.0),
        ",\n  enemies_volume = ", string.format("%.2f", saves.enemies_volume or 1.0),
        ",\n  general_volume = ", string.format("%.2f", saves.general_volume or 1.0),
        ",\n  realtime_shadows = ", string.format("%.0f", saves.realtime_shadows or 1.0),
        ",\n  render96 = ", string.format("%.0f", saves.render96 or 0.0),
        ",\n  remix_music = ", string.format("%.0f", saves.remix_music or 0.0),
        ",\n  human_mode = ", tostring(saves.human_mode == true),
        ",\n  ironman = ", tostring(saves.ironman == true),
        ",\n  files = {\n")
    for i = 1, 4 do
        local s = saves.files[i]
        local got = {}
        for key in pairs(s.got or {}) do got[#got + 1] = string.format("%q", key) end
        table.sort(got)
        local coins = {}
        for course, n in pairs(s.coins or {}) do coins[#coins + 1] = string.format("[%d] = %d", course, n) end
        table.sort(coins)
        f:write(string.format("    { used = %s, stars = %d, time = %.2f, fp = %s, lives = %s, human = %s, ironman = %s, stopped = %s, rainbow_star = %s, got = { %s }, coins = { %s } },\n",
            tostring(s.used and true or false), math.floor(s.stars or 0), s.time or 0.0, tostring(s.fp == true),
            tostring(s.lives), tostring(s.human == true), tostring(s.ironman == true),
            -- (Final Bowser beaten - the clock stopped, the HUD's star rainbow - kept with the file: not written, a
            -- restart had its clock going again, 2026-11-04)
            tostring(s.stopped == true), tostring(s.rainbow_star == true), table.concat(got, ", "),
            table.concat(coins, ", ")))
    end
    f:write("  },\n}\n")
    f:close()
end

local function load_saves()
    saves = default_saves()
    local f = io.open(SAVE_PATH, "r")
    if not f then return end
    local src = f:read("a"); f:close()
    local fn = load(src, "saves", "t", {})
    if not fn then return end
    local ok, data = pcall(fn)
    if not ok or type(data) ~= "table" then return end
    saves.last = tonumber(data.last) or 1
    saves.timer = data.timer == true
    saves.first_person = data.first_person == true
    saves.mario_music = math.max(0.0, math.min(1.0, tonumber(data.mario_music) or 1.0))
    saves.jump_voice = math.max(0.0, math.min(1.0, tonumber(data.jump_voice) or 1.0))
    saves.enemies_volume = math.max(0.0, math.min(1.0, tonumber(data.enemies_volume) or 1.0))
    saves.general_volume = math.max(0.0, math.min(1.0, tonumber(data.general_volume) or 1.0))
    saves.realtime_shadows = ((tonumber(data.realtime_shadows) or 1.0) >= 0.5) and 1.0 or 0.0
    saves.render96 = ((tonumber(data.render96) or 1.0) >= 0.5) and 1.0 or 0.0
    saves.remix_music = ((tonumber(data.remix_music) or 1.0) >= 0.5) and 1.0 or 0.0
    saves.human_mode = data.human_mode == true
    saves.ironman = data.ironman == true
    for i = 1, 4 do
        local s = data.files and data.files[i]
        if s then
            local got = {}
            for _, key in ipairs(type(s.got) == "table" and s.got or {}) do got[tostring(key)] = true end
            local coins = {}
            for course, n in pairs(type(s.coins) == "table" and s.coins or {}) do
                if tonumber(course) and tonumber(n) then coins[math.floor(tonumber(course))] = math.floor(tonumber(n)) end
            end
            -- (files from before files had a perspective of their own keep the one the switch had)
            local fp = s.fp
            if fp == nil then fp = saves.first_person end
            saves.files[i] = { used = s.used and true or false, stars = tonumber(s.stars) or 0, time = tonumber(s.time) or 0.0,
                               got = got, coins = coins, fp = (s.used and fp == true) or nil,
                               lives = tonumber(s.lives), human = (s.used and s.human == true) or nil,
                               ironman = (s.used and s.ironman == true) or nil,
                               stopped = (s.used and s.stopped == true) or nil,
                               rainbow_star = (s.used and s.rainbow_star == true) or nil }
        end
    end
end

-- ------------------------------------------------------------------ stars of the file being played
-- Each star is remembered by "level:number"; a star already in the file does not count again.
function M.has_star(key)
    local f = saves and M.file and saves.files[M.file]
    return f ~= nil and f.got ~= nil and f.got[key] == true
end

function M.add_star(key)
    local f = saves and M.file and saves.files[M.file]
    if not f then return false end
    f.got = f.got or {}
    if f.got[key] then return false end
    f.got[key] = true
    f.stars = (f.stars or 0) + 1
    write_saves()
    if M.on_change then pcall(M.on_change, "star", key) end
    return true
end

-- Other things the file remembers, with its stars as "flag:<name>" (not counted): the cap switches pressed
-- ("cap_wing", "cap_metal", "cap_vanish": Mario 64's SAVE_FLAG_HAVE_WING_CAP and kin)
function M.add_flag(name)
    local f = saves and M.file and saves.files[M.file]
    if not f then return false end
    f.got = f.got or {}
    if f.got["flag:" .. name] then return false end
    f.got["flag:" .. name] = true
    write_saves()
    if M.on_change then pcall(M.on_change, "flag", name) end
    return true
end
function M.has_flag(name) return M.has_star("flag:" .. name) end
-- (and forgotten again: Mario's cap back from whoever had it - mariocap.lua)
function M.remove_flag(name)
    local f = saves and M.file and saves.files[M.file]
    if not (f and f.got and f.got["flag:" .. name]) then return false end
    f.got["flag:" .. name] = nil
    write_saves()
    if M.on_change then pcall(M.on_change, "unflag", name) end
    return true
end

-- Bowser's keys, kept with the file's stars as "key:1", "key:2" (not counted as stars)
function M.add_key(n)
    local f = saves and M.file and saves.files[M.file]
    if not f then return false end
    f.got = f.got or {}
    local k = "key:" .. tostring(n)
    if f.got[k] then return false end
    f.got[k] = true
    write_saves()
    if M.on_change then pcall(M.on_change, "key", n) end
    return true
end
function M.has_key(n) return M.has_star("key:" .. tostring(n)) end

-- The player's setting for Mario 64's music in the game, 0..1 (STORROR's Settings > Audio, MARIO 64 MUSIC:
-- msettings.lua), kept with the files, for every file alike
function M.mario_music()
    if saves == nil then load_saves() end
    return (saves and saves.mario_music) or 1.0
end
function M.set_mario_music(v)
    if saves == nil then load_saves() end
    if not saves then return end
    saves.mario_music = math.max(0.0, math.min(1.0, v))
    write_saves()
end

-- The player's setting for Mario's voice - all of it, sfx.lua M.mario_fx - 0..1, 0 = none (Settings > Audio, MARIO FX,
-- once MARIO JUMP VOICE; asked 2026-10-15: "an option to turn off mario jumping noises"), kept with the files like
-- the music's (as `jump_voice`, its name before)
function M.jump_voice()
    if saves == nil then load_saves() end
    return (saves and saves.jump_voice) or 1.0
end
function M.set_jump_voice(v)
    if saves == nil then load_saves() end
    if not saves then return end
    saves.jump_voice = math.max(0.0, math.min(1.0, v))
    write_saves()
end

-- The player's setting for the enemies' sounds - sfx.lua M.enemy_fx - 0..1, 0 = none (Mario settings, ENEMIES VOLUME:
-- "also in mario settings we need a enemies volume slider", 2026-11-03), kept with the files like the music's
function M.enemies_volume()
    if saves == nil then load_saves() end
    return (saves and saves.enemies_volume) or 1.0
end
function M.set_enemies_volume(v)
    if saves == nil then load_saves() end
    if not saves then return end
    saves.enemies_volume = math.max(0.0, math.min(1.0, v))
    write_saves()
end

-- The player's setting for every other sound - coins, boxes, doors, the menus: sfx.lua M.general_fx - 0..1, 0 = none
-- (Mario settings, GENERAL SOUNDS, 2026-11-03), kept with the files like the music's
function M.general_volume()
    if saves == nil then load_saves() end
    return (saves and saves.general_volume) or 1.0
end
function M.set_general_volume(v)
    if saves == nil then load_saves() end
    if not saves then return end
    saves.general_volume = math.max(0.0, math.min(1.0, v))
    write_saves()
end

-- The player's setting for the shadows: 1 real time, 0 Mario 64's (Settings > Graphics, REAL TIME SHADOWS:
-- msettings.lua, game.lua G.set_realtime_shadows), kept with the files like the music's
function M.realtime_shadows()
    if saves == nil then load_saves() end
    return (saves and saves.realtime_shadows) or 1.0
end
function M.set_realtime_shadows(v)
    if saves == nil then load_saves() end
    if not saves then return end
    saves.realtime_shadows = (v >= 0.5) and 1.0 or 0.0
    write_saves()
end
-- The Render 96 pictures: 1 on, 0 Mario 64's own (Settings > Graphics, RENDER 96: msettings.lua, lib.lua M.set_r96)
function M.render96()
    if saves == nil then load_saves() end
    return (saves and saves.render96) or 1.0
end
function M.set_render96(v)
    if saves == nil then load_saves() end
    if not saves then return end
    saves.render96 = (v >= 0.5) and 1.0 or 0.0
    write_saves()
end

-- The remixes: 1 on, 0 Mario 64's own (Settings > Audio, REMIX MUSIC: msettings.lua, music.lua M.set_remix)
function M.remix_music()
    if saves == nil then load_saves() end
    return (saves and saves.remix_music) or 1.0
end
function M.set_remix_music(v)
    if saves == nil then load_saves() end
    if not saves then return end
    saves.remix_music = (v >= 0.5) and 1.0 or 0.0
    write_saves()
end

function M.star_count()
    local f = saves and M.file and saves.files[M.file]
    return f and (f.stars or 0) or 0
end

-- Every star the file has, as a set of "level:number" (for the pause screen; not to be changed).
function M.stars_got()
    local f = saves and M.file and saves.files[M.file]
    return f and f.got or {}
end

-- A course's best coin count (Mario 64's coin score: kept when a star is collected, if it beats the last).
function M.coin_score(course)
    local f = saves and M.file and saves.files[M.file]
    return f and f.coins and f.coins[course] or 0
end

function M.note_coins(course, n)
    local f = saves and M.file and saves.files[M.file]
    if not (f and course and n) then return false end
    f.coins = f.coins or {}
    if n <= (f.coins[course] or 0) then return false end
    f.coins[course] = n
    write_saves()
    if M.on_change then pcall(M.on_change, "coins", course, n) end
    return true
end

-- ------------------------------------------------------------------ multiplayer: the host's file, shared (mp.lua)
-- "The host players file should be shared between other players", 2026-11-03. In someone else's game his own file is
-- put by and the host's played instead: "mp", the copy the host sends (mp.lua) - never written to his saves (only
-- files 1 to 4 are). What he gets in it (stars, keys, cap switches, coin scores) goes to the host - M.on_change, set by
-- mp.lua - who sends the file back to everyone. His perspective stays his own file's. Out of the game, his own again.
function M.mp_file(t)
    if saves == nil then load_saves() end
    if not (saves and t) then return false end
    local own = (M.file ~= "mp") and M.file or M.own_file
    t.fp = own and saves.files[own] and saves.files[own].fp or false
    t.used = true
    saves.files.mp = t
    if M.file ~= "mp" then
        M.own_file = M.file
        M.file = "mp"
        return true
    end
    return false
end
function M.mp_leave()
    if M.file == "mp" then M.file = M.own_file; M.own_file = nil end
    if saves then saves.files.mp = nil end
end
function M.mp_shared() return M.file == "mp" end
-- the file being played as it stands (to send), or nil
function M.mp_snapshot()
    local f = saves and M.file and saves.files[M.file]
    return f
end

-- ------------------------------------------------------------------ the speedrun timer
-- Every file keeps the time it has been played for: real time, through loading and pauses, the way a run is
-- timed. It starts the moment the player first touches the controls once the athlete is his: not while a
-- new file's opening plays, and not before he has done anything. TIMER on the file select says whether the
-- HUD shows it (health.lua draws it, as Mario 64 draws the clock of its races: TIME 1'23"45).
local run = { last = nil, saved = 0.0, going = false }

-- (any button, either stick, or the keyboard and mouse buttons the athlete is played with)
local TOUCH_KEYS = {
    "Gamepad_FaceButton_Bottom", "Gamepad_FaceButton_Right", "Gamepad_FaceButton_Left", "Gamepad_FaceButton_Top",
    "Gamepad_LeftShoulder", "Gamepad_RightShoulder", "Gamepad_LeftTrigger", "Gamepad_RightTrigger",
    "Gamepad_LeftThumbstick", "Gamepad_RightThumbstick", "Gamepad_Special_Left", "Gamepad_Special_Right",
    "Gamepad_DPad_Up", "Gamepad_DPad_Down", "Gamepad_DPad_Left", "Gamepad_DPad_Right",
    "W", "A", "S", "D", "Up", "Down", "Left", "Right", "SpaceBar", "LeftShift", "LeftControl", "C", "E", "Q",
    "Escape", "LeftMouseButton", "RightMouseButton",
}

local function touched()                -- (what was touched, or nil)
    local x, y = pad.sticks()
    if x ~= 0.0 or y ~= 0.0 then return string.format("stick %.2f,%.2f", x, y) end
    local pc = lib.controller()
    if not pc then return nil end
    for _, k in ipairs(TOUCH_KEYS) do
        local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(k) }) end)
        if ok and v then return k end
    end
    return nil
end

function M.timer_running() return run.going end

function M.timer_on() return saves ~= nil and saves.timer == true end
-- (the same switch as MARIO SETTINGS' TIMER row - msettings.lua - "add a timer off switch in mario settings",
-- 2026-11-01: 1 the HUD shows the time, 0 not; the file select's TIMER shows it too)
function M.timer_setting()
    if saves == nil then load_saves() end
    return (saves ~= nil and saves.timer == true) and 1.0 or 0.0
end
function M.set_timer(v)
    if saves == nil then load_saves() end
    if not saves then return end
    local on = v >= 0.5
    if saves.timer == on then return end
    saves.timer = on
    write_saves()
end
-- HUMAN MODE and IRONMAN MODE (MARIO SETTINGS' rows: msettings.lua) - "in mario menu 3 I want to add two new modes, Human
-- mode take 1 damage to hp and you die gruesomely unless its water. Then IronMan Mode 1 Life if you die it resets your
-- progress and kicks you to the menu", 2026-11-02. Human: any hurt at all is death, a gruesome one (health.lua M.damage,
-- game.lua); the water's slow drain - drowning, the cold - goes as it always did. IronMan: one life, and a death that would
-- cost it wipes the file being played and goes back to the file select (M.ironman_wipe) - the save file kept first, as
-- saves_ironman_backup.lua, should it be wanted back.
-- (each file its own: a file started new takes the switches as they stand at the file select - its HUMAN and IRONMAN
-- buttons - and keeps them for good: "once its on a file it cant be removed unless deleted", 2026-11-02. Only ERASE,
-- which makes it a new file, clears them.)
local function file_now()
    return (M.state == "game" and saves and M.file) and saves.files[M.file] or nil
end
function M.human_on() local f = file_now(); return f ~= nil and f.human == true end
function M.ironman_on() local f = file_now(); return f ~= nil and f.ironman == true end
function M.human_setting()
    if saves == nil then load_saves() end
    if not saves then return 0.0 end
    local f = file_now()
    if f then return f.human and 1.0 or 0.0 end
    return saves.human_mode and 1.0 or 0.0
end
function M.ironman_setting()
    if saves == nil then load_saves() end
    if not saves then return 0.0 end
    local f = file_now()
    if f then return f.ironman and 1.0 or 0.0 end
    return saves.ironman and 1.0 or 0.0
end
-- (what new files get; a file already going is never changed here)
function M.set_human(v)
    if saves == nil then load_saves() end
    if not saves then return end
    local on = v >= 0.5
    if saves.human_mode == on then return end
    saves.human_mode = on
    write_saves()
    log("HUMAN MODE %s for new files", on and "on" or "off")
end
function M.set_ironman(v)
    if saves == nil then load_saves() end
    if not saves then return end
    local on = v >= 0.5
    if saves.ironman == on then return end
    saves.ironman = on
    write_saves()
    log("IRONMAN MODE %s for new files", on and "on" or "off")
end
-- IronMan: the file being played wiped - a new file again, as from ERASE - and back to the file select
function M.ironman_wipe()
    if saves == nil then load_saves() end
    if not (saves and M.file) then return M.back_to_menu() end
    if M.file == "mp" then
        -- (dead in someone else's IRONMAN game: out of the game, his own file kept, to the file select)
        local MP = package.loaded["mp"]
        -- (and that game never joined again: mp.lua M.died_here)
        if MP and MP.died_here then pcall(MP.died_here) end
        if MP and MP.leave then pcall(MP.leave) end
        M.mp_leave()
        log("IRONMAN: out of the shared game - his own file kept, and no way back into it")
        M.file = nil
        M.open()
        return
    end
    local i = M.file
    -- (the saves as they stood kept beside them first)
    pcall(function()
        local src = io.open(SAVE_PATH, "r")
        if src then
            local data = src:read("a")
            src:close()
            local dst = io.open(lib.MOD_DIR .. "saves_ironman_backup.lua", "w")
            if dst then dst:write(data); dst:close() end
        end
    end)
    saves.files[i] = { used = false, stars = 0 }
    write_saves()
    log("IRONMAN: file %d wiped (the saves kept as saves_ironman_backup.lua)", i)
    M.file = nil
    M.open()
end

-- Each file is played in the perspective it was started in, for good (asked 2026-10-14: "force the perspectives
-- on the file so if you open a new save. that save will only work in first person. vice versa for 3rd person").
-- The FIRST PERSON switch on the file select says which a NEW file gets; a copy keeps its file's. The file select
-- writes FIRST PERSON after the name of each first-person file ("we also need an identifer").
-- First person was switched off 2026-10-14 ("please also remove the first person for now") and is back on 2026-10-15
-- ("renable first person"): each file plays in the perspective it was made with, the switch sets it for new files.
-- (FP_OFF = true puts every file in third person again; the files keep their own setting.)
M.FP_OFF = false
function M.first_person()
    if M.FP_OFF then return false end
    local f = saves and M.file and saves.files[M.file]
    return f ~= nil and f.fp == true
end
-- (the switch for new files)
function M.new_files_first_person() return saves ~= nil and saves.first_person == true end
function M.set_first_person(on)
    if not saves then return end
    saves.first_person = on and true or false
    write_saves()
end

function M.run_time()
    local f = saves and M.file and saves.files[M.file]
    return f and (f.time or 0.0) or 0.0
end

-- (Final Bowser beaten - his rainbow star taken: the file's clock stopped there for good, its time the run's - "after
-- final bowser the timer can stop", 2026-11-04; ending.lua E.start)
function M.stop_timer()
    local f = saves and M.file and saves.files[M.file]
    if not f or f.stopped then return end
    local now = os.clock()
    if run.going and run.last then f.time = (f.time or 0.0) + (now - run.last) end
    run.last = now
    f.stopped = true
    write_saves()
    log("timer: stopped at %.2f s - Final Bowser beaten", f.time or 0.0)
end

-- (Final Bowser's rainbow star taken: the file's from then on - the HUD's star counter rainbow, health.lua
-- M.star_rainbow_tick: "after the player collects the rainbow star make the star counter star in hud rainbow",
-- 2026-11-04; ending.lua E.start. A file whose clock was stopped by it has it too)
function M.set_rainbow_star()
    local f = saves and M.file and saves.files[M.file]
    if not f or f.rainbow_star then return end
    f.rainbow_star = true
    write_saves()
    log("file %s: Final Bowser's rainbow star - the HUD's star rainbow", tostring(M.file))
end
function M.has_rainbow_star()
    local f = saves and M.file and saves.files[M.file]
    return f ~= nil and (f.rainbow_star == true or f.stopped == true)
end

-- (every frame while a file is being played)
local function run_clock()
    local f = saves and M.file and saves.files[M.file]
    local now = os.clock()
    if f and f.stopped then run.last = now; return end
    if not run.going then
        run.last = now
        -- (the button still held from picking the file is not a touch: it has to be let go first)
        local t = touched()
        if not t then run.armed = true end
        if not (f and t and run.armed and not (INTRO and INTRO.active)) then return end
        run.going = true
        log("timer: running from %.2f (%s)", f.time or 0.0, t)
        return
    end
    if f and run.last then
        f.time = (f.time or 0.0) + (now - run.last)
        if now - run.saved > 15.0 then          -- kept on disk as it goes, so a crash costs seconds, not the run
            run.saved = now
            write_saves()
        end
    end
    run.last = now
end

-- ------------------------------------------------------------------ boot config (default map = the empty map)
local function install_boot_config()
    local base = os.getenv("LOCALAPPDATA")
    if not base then return end
    local dir = base .. "\\STORRORParkourPRO\\Saved\\Config\\Windows\\"
    local probe = io.open(dir .. "GameUserSettings.ini", "r")
    if not probe then log("boot config: config folder not found, skipping"); return end
    probe:close()
    local path = dir .. "Engine.ini"
    local cur = ""
    local rf = io.open(path, "r")
    if rf then cur = rf:read("a"); rf:close() end
    if cur:find("SM64Map boot", 1, true) or cur:find("GameDefaultMap=" .. M.EMPTY_MAP, 1, true) then return end
    local wf = io.open(path, "w")
    if not wf then log("boot config: cannot write %s", path); return end
    wf:write(cur)
    if #cur > 0 and cur:sub(-1) ~= "\n" then wf:write("\n") end
    wf:write("\n; SM64Map boot map -- delete these three lines to get the normal Storror boot back\n")
    wf:write("[/Script/EngineSettings.GameMapsSettings]\n")
    wf:write("GameDefaultMap=" .. M.EMPTY_MAP .. "." .. M.EMPTY_MAP:match("([^/]+)$") .. "\n")
    wf:close()
    log("boot config installed: the game will start in the empty map next launch")
end

-- ------------------------------------------------------------------ world helpers
local function spawn(world, path, loc, rot)
    local cls = StaticFindObject(path)
    if not (cls and cls:IsValid()) then return nil end
    local a = world:SpawnActor(cls, loc, rot or { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
    if a and a:IsValid() then return a end
    return nil
end

local function valid(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

-- ------------------------------------------------------------------ sky + lights
local env = { sky = nil, lights = {} }
M.env = env           -- (sky.lua changes the sky's picture and the lights with the level)

local function build_sky(world)
    local N, R = 48, 400000.0
    local pos, nrm, uv, col, idx = {}, {}, {}, {}, {}
    local function vert(x, y, z, u, v)
        pos[#pos + 1] = x; pos[#pos + 1] = y; pos[#pos + 1] = z
        nrm[#nrm + 1] = 0; nrm[#nrm + 1] = 0; nrm[#nrm + 1] = 1
        uv[#uv + 1] = u; uv[#uv + 1] = v
        col[#col + 1] = 1; col[#col + 1] = 1; col[#col + 1] = 1; col[#col + 1] = 1
        return #pos // 3 - 1
    end
    local function tri(a, b, c)
        idx[#idx + 1] = a; idx[#idx + 1] = b; idx[#idx + 1] = c
        idx[#idx + 1] = a; idx[#idx + 1] = c; idx[#idx + 1] = b   -- both windings (seen from inside, either side)
    end
    -- A sphere: around it the sky picture twice, its rows from the top of the view to the bottom - Mario 64 scrolls
    -- its sky the same way (skybox.c: two pictures to a turn, the top rows overhead, the bottom ones underfoot). From
    -- CAP degrees up and down, a dome of its own with a picture of the sky as seen straight up / down
    -- (exporter/skycapx.py: sky_<name>_top/_bottom), so that the picture neither ends nor pinches there.
    -- (It was a band to +/-45 degrees, the picture 4 times round, with a flat colour above and below, 2026-10-15:
    -- "we gotta fix the skybox the top and bottom of it for each of the levels".)
    local CAP, RINGS, CAPRINGS = 50.0, 10, 8
    local function dir(e, a)
        local ce = math.cos(math.rad(e))
        return R * ce * math.cos(a), R * ce * math.sin(a), R * math.sin(math.rad(e))
    end
    local band = {}
    for k = 0, RINGS do
        local e = -CAP + 2.0 * CAP * k / RINGS
        band[k] = {}
        for i = 0, N do
            local a = 2 * math.pi * i / N
            local x, y, z = dir(e, a)
            band[k][i] = vert(x, y, z, 2.0 * i / N, 0.5 - e / 180.0)
        end
    end
    for k = 0, RINGS - 1 do
        for i = 0, N - 1 do
            tri(band[k + 1][i], band[k][i], band[k][i + 1])
            tri(band[k + 1][i], band[k][i + 1], band[k + 1][i + 1])
        end
    end
    local sec = { id = 0, layer = "opaque", texture = "sky_water", nverts = #pos // 3, pos = pos, nrm = nrm, uv = uv, col = col, idx = idx }
    -- the domes: rings from CAP to the pole, their picture laid out around its middle
    local function dome(id, sign, texture)
        pos, nrm, uv, col, idx = {}, {}, {}, {}, {}
        local rings = {}
        for k = 0, CAPRINGS do
            local r = 1.0 - k / CAPRINGS                       -- (1 at the dome's edge, 0 at the pole)
            local e = sign * (90.0 - r * (90.0 - CAP))
            rings[k] = {}
            for i = 0, N do
                local a = 2 * math.pi * i / N
                local x, y, z = dir(e, a)
                rings[k][i] = vert(x, y, z, 0.5 + 0.5 * r * math.cos(a), 0.5 + 0.5 * r * math.sin(a))
            end
        end
        for k = 0, CAPRINGS - 1 do
            for i = 0, N - 1 do
                tri(rings[k][i], rings[k + 1][i], rings[k + 1][i + 1])
                tri(rings[k][i], rings[k + 1][i + 1], rings[k][i + 1])
            end
        end
        return { id = id, layer = "opaque", texture = texture, nverts = #pos // 3, pos = pos, nrm = nrm, uv = uv, col = col, idx = idx }
    end
    local top = dome(1, 1.0, "sky_water_top")
    local bottom = dome(2, -1.0, "sky_water_bottom")
    local actor = lib.spawn_actor(world, { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z + 900.0 }, 0.0)
    if not actor then return nil end
    pcall(function() lib.keep[actor:GetAddress()] = true end)
    local pmc = lib.add_pmc(actor)
    if not pmc then return nil end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    lib.add_sections(world, pmc, { sec, top, bottom })
    return actor
end

-- The sun: degrees over the horizon, and round from the scene's +X toward +Y (where it is, not where its light goes) -
-- the one tools/shadowbake.py bakes the levels' shadows with (SUN_ELEVATION, SUN_AZIMUTH): keep them the same.
M.SUN_DEFAULT = { 65.0, 35.0 }
M.SUN = { 65.0, 35.0 }
M.FILL_PITCH = -5.0      -- (low: it lights the walls in shade, and the ground in a shadow hardly more - sky.lua)
-- the soft lights all round (ensure_env): where each shines along - one straight down, three a little upward from under
-- the horizon (19.47 degrees: a tetrahedron's corners, the light even every way round)
M.AMBIENT_ROTS = { { Pitch = -90.0, Yaw = 0.0, Roll = 0.0 }, { Pitch = 19.47, Yaw = 180.0, Roll = 0.0 },
                   { Pitch = 19.47, Yaw = 300.0, Roll = 0.0 }, { Pitch = 19.47, Yaw = 60.0, Roll = 0.0 } }
local function sun_rots()
    local az = math.rad(M.SUN[2])
    local sun_rot = { Pitch = -M.SUN[1], Yaw = math.deg(math.atan(-math.sin(az), -math.cos(az))), Roll = 0.0 }
    return sun_rot, { Pitch = M.FILL_PITCH, Yaw = sun_rot.Yaw + 180.0, Roll = 0.0 }
end
-- the sun put where a level has it (game.lua G.SUN_AT) - its lights turned, if they are this map's
function M.aim_sun(sun)
    if not sun then return end
    M.SUN = { sun[1], sun[2] }
    local here = nil
    pcall(function() here = lib.world():GetAddress() end)
    if env.world ~= here then return end
    local sr, fr = sun_rots()
    for i, l in ipairs(env.lights or {}) do
        if i <= 2 and l and l:IsValid() then pcall(function() l:K2_SetActorRotation(i == 1 and sr or fr, false) end) end
    end
end
function M.ensure_env()
    local world = lib.world()
    if not world then return end
    -- (the sky and lights of a map that has gone went with it: forgotten, never touched, or the game comes down;
    -- seen 2026-10-14 coming back from STORROR's "quit to menu")
    local addr = world:GetAddress()
    if env.world ~= addr then env.sky, env.lights, env.world = nil, {}, addr end
    if valid(env.sky) then return end
    env.sky = build_sky(world)
    for _, l in ipairs(env.lights) do pcall(function() l:K2_DestroyActor() end) end
    env.lights = {}
    -- (the sun along the one the levels' shadows are baked with - tools/shadowbake.py, M.SUN: 65 degrees up, 35 round -
    -- so the level's own shadows the engine casts onto him fall as the baked ones on the ground. Its spawn rotation did
    -- not hold: it lay flat, and the fences' shadows ran across him in stripes - "fences showed shadows on the player",
    -- 2026-10-30. Turned after it is made; the fill from the other side, lower, no shadows.)
    local sun_rot, fill_rot = sun_rots()
    local sun = spawn(world, "/Script/Engine.DirectionalLight", { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z + 5000 }, sun_rot)
    if sun then
        pcall(function() sun.LightComponent:SetMobility(2); sun.LightComponent:SetIntensity(6.0) end)
        -- (its shadows only with real-time shadows on: game.lua G.set_realtime_shadows)
        local G = package.loaded["game"]
        pcall(function() sun.LightComponent:SetCastShadows(not (G and G.LIT_LEVELS == false)) end)
        pcall(function() sun:K2_SetActorRotation(sun_rot, false) end)
        env.lights[#env.lights + 1] = sun
    end
    local fill = spawn(world, "/Script/Engine.DirectionalLight", { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z + 5000 }, fill_rot)
    if fill then
        pcall(function()
            fill.LightComponent:SetMobility(2)
            fill.LightComponent:SetIntensity(2.5)
            fill.LightComponent:SetCastShadows(false)
            -- (no shine of its own: it only lifts the shade. Low and from behind the castle, it shone a white glare on
            -- the castle's edges - "some sort of white thing in the building?", 2026-10-30)
            fill.LightComponent:SetSpecularScale(0.0)
        end)
        pcall(function() fill:K2_SetActorRotation(fill_rot, false) end)
        env.lights[#env.lights + 1] = fill
    end
    -- (the light all round, as a sky gives it: four soft lights - one from straight above, three from a little under the
    -- horizon, a third of the way round from each other (a tetrahedron's corners) - no shadows, no shine. Every face,
    -- whichever way it is turned, takes about the same from them: the shadows on the ground, the walls in shade, the
    -- ceilings - "the shadows are quite dark", "make them less so", and the castle's archway black inside, 2026-10-30.
    -- The engine's own light from the sky and its bounce cannot see the levels' meshes. Their strength is sky.lua's.)
    for _, rot in ipairs(M.AMBIENT_ROTS) do
        local a = spawn(world, "/Script/Engine.DirectionalLight", { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z + 5000 }, rot)
        if a then
            pcall(function()
                a.LightComponent:SetMobility(2)
                a.LightComponent:SetIntensity(0.0)
                a.LightComponent:SetCastShadows(false)
                a.LightComponent:SetSpecularScale(0.0)
            end)
            pcall(function() a:K2_SetActorRotation(rot, false) end)
            env.lights[#env.lights + 1] = a
        end
    end
    log("environment ready (sky %s, %d lights)", tostring(env.sky ~= nil), #env.lights)
end

-- ------------------------------------------------------------------ file select menu
-- Layout data (data/menu_layout.lua) is in pixels of a 1268x925 reference screenshot of SM64's file select.
-- That is a 4:3 picture. Here it is laid out for a 16:9 screen: the same height (925) on a screen 1644
-- wide, with everything spread further apart sideways and the frame's middle drawn wider (menu_bg16).
local BASE = { X = 2000000.0, Y = 0.0, Z = OFFSET.Z }     -- far outside the sky cylinder
local DIST = 960.0                                          -- 1 world unit == 1 pixel at 1920x1080 (90 degree fov)
local SC = 1080.0 / 925.0                                   -- reference px -> menu units
local WIDE_W = 1644.0                                       -- the reference screen's width at 16:9
local SPREAD = 1.3                                          -- how much further apart things sit across it
local sizes, LAY = nil, nil
local ui = { actor = nil, hand = nil, cam = nil, hud = nil, hud_vis = nil }
local menu = { sel = 1, mode = "select", msg = nil, msg_t = 0, t = 0, cx = 0.0, cy = 0.0 }

-- selection: 1-4 files, 5 COPY, 6 ERASE, 7 TIMER, 8 FIRST PERSON, 9 HUMAN, 10 IRONMAN. (Mario 64 has SCORE, COPY,
-- ERASE and a STEREO/MONO switch: TIMER, which turns the speedrun timer on and off, and FIRST PERSON, which puts the
-- camera in the athlete's eyes, take SCORE's and the switch's places, on their blocks. HUMAN and IRONMAN, the two
-- modes, beside them - "right where erase timer on and first person mode is", 2026-11-02: like FIRST PERSON they are
-- what a file started new gets, and a file keeps them for good - "once its on a file it cant be removed unless
-- deleted": ERASE is the only way off.)
local NAV = {
    [1] = { right = 2, down = 3 }, [2] = { left = 1, down = 4 },
    [3] = { up = 1, right = 4, down = 5 }, [4] = { up = 2, left = 3, down = 8 },
    [5] = { up = 3, right = 6 }, [6] = { up = 3, left = 5, right = 7 },
    [7] = { up = 3, left = 6, right = 8 }, [8] = { up = 4, left = 7, right = 9 },
    [9] = { up = 4, left = 8, right = 10 }, [10] = { up = 4, left = 9 },
}
local BTN = { "copy", "erase", "timer", "fp", "human", "ironman" }
-- (across the reference screen: six evenly over the frame's width, where Mario 64 has four)
local BTN_X = { 190.2, 367.8, 545.5, 722.5, 900.2, 1077.8 }
local COPY, ERASE, TIMER, FP, HUMAN, IRONMAN = 5, 6, 7, 8, 9, 10
local ITEMS = 4 + #BTN
-- The start film goes on inside the frame. The inside of the frame in menu_bg16.png, as shares of the
-- picture (left, top, right, bottom; make_timer_assets.py measures it), and how bright the film is
-- shown there: dim, so that the white lettering reads over it.
local BOX = { 0.0609, 0.1024, 0.9420, 0.9034 }
local BOX_DIM = 0.30
local EXPOSURE = -0.3                                     -- the camera's, fixed (the title screen's is the same)
local HAND_Z = 300.0                                      -- the hand floats in front of everything else
local HAND_K = (DIST - HAND_Z) / DIST
local CURSOR_SPEED = 950.0                                -- reference px a second at full stick
local ITEM_HALF_W, ITEM_HALF_H = 88.0, 68.0               -- how near the middle of a block or button counts as on it

-- a position across the 4:3 reference screen -> across the wide one
local function WX(px) return WIDE_W / 2 + (px - LAY.screen.w / 2) * SPREAD end
-- wide reference px -> menu units, centre of the screen at (0, 0)
local function MX(px) return (px - WIDE_W / 2) * SC end
local function MY(py) return (LAY.screen.h / 2 - py) * SC end

-- the middle of a file block (1-4) or button (5-10), in wide reference px
local function sel_center(sel)
    if sel <= 4 then return WX(LAY.blocks[sel][1]), LAY.blocks[sel][2] end
    return WX(BTN_X[sel - 4]), LAY.buttons[1][2]
end

-- which block or button the cursor is on, if any
local function hovered()
    for sel = 1, ITEMS do
        local x, y = sel_center(sel)
        if math.abs(menu.cx - x) < ITEM_HALF_W and math.abs(menu.cy - y) < ITEM_HALF_H then return sel end
    end
    return nil
end

-- The warning about the game modes, before a file is started: "we have to put a warning at the main menu for when a
-- player has different gamemodes selected on an already made file. Say something like Are you sure you cant change this
-- later. or your gamemodes don't match your save some will not active are you sure?", 2026-11-03. A new file with HUMAN,
-- IRONMAN or FIRST PERSON on (they are its for good): "new"; a file already made without one that is on now (it will
-- not have it): "match". A panel over the file select, its lines, YES and NO (NO picked first); the hand on the one picked.
M.CONFIRM_Y = 470.0                 -- (its middle, down the reference screen)
M.CONFIRM_X = 165.0                 -- (YES and NO this far either side of the middle)
function M.need_confirm(sel)
    local f = saves and saves.files[sel]
    if not f then return nil end
    -- (FIRST PERSON too, a file's for good as they are - "also firts person", 2026-11-03 - unless it is off for now)
    local h, i = saves.human_mode == true, saves.ironman == true
    local fp = saves.first_person == true and not M.FP_OFF
    if not f.used then
        if not (h or i or fp) then return nil end
        return "new", "menu_w_on_" .. (h and "h" or "") .. (i and "i" or "") .. (fp and "f" or "")
    end
    if (h and f.human ~= true) or (i and f.ironman ~= true) or (fp and f.fp ~= true) then return "match" end
    return nil
end
function M.confirm_xy(yes)
    return WIDE_W / 2 + (yes and -M.CONFIRM_X or M.CONFIRM_X), M.CONFIRM_Y + 92.0
end

local function build_ui()
    local world = lib.world()
    if not world then return end
    if valid(ui.actor) then pcall(function() ui.actor:K2_DestroyActor() end) end
    ui.actor = nil
    local actor = lib.spawn_actor(world, BASE, 0.0)
    if not actor then return end
    local pmc = lib.add_pmc(actor)
    if not pmc then return end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)

    local secs = {}
    local depth = 0
    -- raw quad: centre (cx,cy) and size (w,h) in menu units; depth grows toward the camera
    local function quad(tex, cx, cy, w, h, layer)
        depth = depth + 3
        local x = DIST - depth
        local k = x / DIST                       -- keep the on-screen size/position exact despite the depth offset
        cx, cy, w, h = cx * k, cy * k, w * k, h * k
        local hw, hh = w / 2, h / 2
        secs[#secs + 1] = {
            id = #secs, layer = layer, texture = tex, nverts = 4,
            pos = { x, cx - hw, cy - hh, x, cx + hw, cy - hh, x, cx + hw, cy + hh, x, cx - hw, cy + hh },
            nrm = { -1, 0, 0, -1, 0, 0, -1, 0, 0, -1, 0, 0 },
            uv = { 0, 1, 1, 1, 1, 0, 0, 0 },
            col = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
            idx = { 0, 1, 2, 0, 2, 3 },
        }
    end
    local function dims(tex, scale)
        local s = sizes[tex] or { 64, 64 }
        return s[1] * SC * (scale or 1), s[2] * SC * (scale or 1)
    end
    -- place by wide-reference-px position; anchor "c" (centre) or "l" (left edge)
    local function put(tex, px, py, anchor, layer, scale)
        local w, h = dims(tex, scale)
        local cx = MX(px)
        if anchor == "l" then cx = cx + w / 2 end
        quad(tex, cx, MY(py), w, h, layer or "translucent")
    end

    quad("menu_black", 0, 0, 5200, 3000, "opaque")
    quad("menu_bg16", 0, 0, WIDE_W * SC, LAY.screen.h * SC, "opaque")       -- the frame, edge to edge of a 16:9 screen
    put("menu_t_title", WX(LAY.title[1]), LAY.title[2], "c")

    for i = 1, 4 do
        local f = saves.files[i]
        local sc = (menu.sel == i) and 1.1 or 1.0
        -- (faded: what cannot be picked at this step of ERASE or COPY)
        local fade = (menu.mode == "erase" and not f.used)
            or (menu.mode == "copy" and not menu.copy_from and not f.used)
            or (menu.mode == "copy" and menu.copy_from and f.used and i ~= menu.copy_from)
        local bt = (f.used and "menu_blk_save" or "menu_blk_new") .. (fade and "_f" or "")
        local bx = WX(LAY.blocks[i][1])
        put(bt, bx, LAY.blocks[i][2], "c", "opaque", sc)
        -- the name and the star count keep their distance from the block they belong to
        local name = "menu_t_mario_" .. string.char(64 + i)
        put(name, bx + LAY.name_left[i] - LAY.blocks[i][1], LAY.name_y[i], "l")
        if f.used and f.fp and not M.FP_OFF then
            -- (the FIRST PERSON button's own label, as small as it is there)
            local nx = bx + LAY.name_left[i] - LAY.blocks[i][1] + (sizes[name] or { 150 })[1] + 18
            put("menu_t_fp", nx, LAY.name_y[i], "l", nil, 0.62)
        end
        if f.used then
            local x, y = bx + LAY.count_left[i] - LAY.blocks[i][1], LAY.count_y[i]
            put("menu_h_star", x, y, "l")
            x = x + LAY.star_pitch
            put("menu_h_x", x, y, "l")
            x = x + LAY.x_pitch + 6
            for ch in tostring(math.floor(f.stars)):gmatch(".") do
                put("menu_h_" .. ch, x, y, "l")
                x = x + LAY.digit_pitch
            end
            -- (its modes, by the star count: HUMAN MODE a heart, IRONMAN MODE a skull - "make an ironman Icon and human
            -- Icon to signify what saves have it on", 2026-11-02)
            x = x + 14
            if f.human then put("menu_icon_human", x, y, "l", nil, 0.8); x = x + 62 end
            if f.ironman then put("menu_icon_ironman", x, y, "l", nil, 0.8) end
        else
            put("menu_t_new", bx + LAY.count_left[i] - LAY.blocks[i][1], LAY.count_y[i], "l")
        end
    end

    for i = 1, #BTN do
        local sc = (menu.sel == 4 + i) and 1.1 or 1.0
        local label = "menu_t_" .. BTN[i]
        if 4 + i == TIMER then label = saves.timer and "menu_t_timer_on" or "menu_t_timer_off" end
        put("menu_btn_" .. BTN[i], WX(BTN_X[i]), LAY.buttons[1][2], "c", "opaque", sc)
        if 4 + i == FP then
            -- (two lines: FIRST PERSON is too long for one under its block)
            put("menu_t_fp", WX(BTN_X[i]), LAY.label_y - 8, "c", nil, 0.62)
            put((saves.first_person and not M.FP_OFF) and "menu_t_fp_on" or "menu_t_fp_off", WX(BTN_X[i]), LAY.label_y + 20, "c", nil, 0.8)
        elseif 4 + i == HUMAN or 4 + i == IRONMAN then
            -- (the same two lines: the mode, and whether a file started new gets it)
            -- (not `a and b or c`: with HUMAN off that gave IRONMAN's switch - HUMAN read ON while it was off)
            local on
            if 4 + i == HUMAN then on = saves.human_mode == true else on = saves.ironman == true end
            put(label, WX(BTN_X[i]), LAY.label_y - 10, "c", nil, 0.75)
            put(on and "menu_t_fp_on" or "menu_t_fp_off", WX(BTN_X[i]), LAY.label_y + 20, "c", nil, 0.8)
        else
            put(label, WX(BTN_X[i]), LAY.label_y, "c", nil, (4 + i == TIMER) and 0.85 or nil)
        end
    end

    if menu.msg then put(menu.msg, WIDE_W / 2, LAY.msg_y, "c") end
    if menu.confirm then
        local C = menu.confirm
        local cx, cy = WIDE_W / 2, M.CONFIRM_Y
        put("menu_w_panel", cx, cy, "c", "alpha", 0.9)
        local lines = (C.kind == "new") and { C.on, "menu_w_later", "menu_w_sure" } or { "menu_w_match", "menu_w_some", "menu_w_sure" }
        for k, t in ipairs(lines) do put(t, cx, cy - 112.0 + (k - 1) * 50.0, "c", nil, 0.78) end
        local yx = M.confirm_xy(true)
        local nx = M.confirm_xy(false)
        put("menu_w_yes", yx, cy + 92.0, "c", nil, C.yes and 1.3 or 0.95)
        put("menu_w_no", nx, cy + 92.0, "c", nil, (not C.yes) and 1.3 or 0.95)
    end

    lib.add_sections(world, pmc, secs)
    ui.actor = actor

    -- the pointing hand is its own actor so it can move/bob every frame
    if not valid(ui.hand) then
        local half = 32 * 3.96 * SC / 2 * HAND_K
        ui.hand = lib.quad_actor(world, { X = BASE.X + DIST - HAND_Z, Y = BASE.Y, Z = BASE.Z }, half, "menu_hand", "translucent")
    end
    -- and the pinching hand Mario 64 shows for a moment at every press (texture_menu_grabbing_hand)
    if not valid(ui.hand_grab) then
        local half = 32 * 3.96 * SC / 2 * HAND_K
        ui.hand_grab = lib.quad_actor(world, { X = BASE.X + DIST - HAND_Z, Y = BASE.Y, Z = BASE.Z }, half, "menu_hand_grab", "translucent")
        if ui.hand_grab then pcall(function() ui.hand_grab:SetActorHiddenInGame(true) end) end
        ui.grab_shown = false
    end
end

-- The film inside the frame: a sheet of its own just in front of the frame's picture, behind everything
-- else, so it can be dimmed and brightened without the rest being made again.
local function build_film(world)
    if valid(ui.film) then pcall(function() ui.film:K2_DestroyActor() end) end
    ui.film, ui.film_pmc, ui.film_b = nil, nil, nil
    if not (FILM and FILM.start(world, 0.0)) then return end
    FILM.speaker(world, { X = BASE.X + 6600.0, Y = BASE.Y, Z = BASE.Z })
    local mat = FILM.material(world)
    if not mat then return end
    local actor = lib.spawn_actor(world, BASE, 0.0)
    local pmc = actor and lib.add_pmc(actor)
    if not pmc then lib.destroy(actor); return end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    local w, h = WIDE_W * SC, LAY.screen.h * SC
    local x = DIST - 7.5
    local k = x / DIST
    local y0, y1 = (BOX[1] - 0.5) * w * k, (BOX[3] - 0.5) * w * k
    local z0, z1 = (0.5 - BOX[4]) * h * k, (0.5 - BOX[2]) * h * k
    -- the inside of the frame is wider than the film: the film fills its width and loses a little top and bottom
    local keep = math.min(1.0, (16.0 / 9.0) / ((y1 - y0) / (z1 - z0)))
    local v0, v1 = 0.5 - keep / 2.0, 0.5 + keep / 2.0
    local verts = { { X = x, Y = y0, Z = z0 }, { X = x, Y = y1, Z = z0 }, { X = x, Y = y1, Z = z1 }, { X = x, Y = y0, Z = z1 } }
    local n = { X = -1.0, Y = 0.0, Z = 0.0 }
    local c = { R = 0.0, G = 0.0, B = 0.0, A = 1.0 }
    local ok, err = pcall(lib.create_section, pmc, 0, verts, { 0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2 }, { n, n, n, n },
        { { X = 0.0, Y = v1 }, { X = 1.0, Y = v1 }, { X = 1.0, Y = v0 }, { X = 0.0, Y = v0 } }, { c, c, c, c }, false)
    if not ok then log("file select: no film (%s)", tostring(err)); lib.destroy(actor); return end
    pcall(function() pmc:SetMaterial(0, mat) end)
    ui.film, ui.film_pmc, ui.film_verts, ui.film_b = actor, pmc, verts, 0.0
end

-- It is shown only while the word STORROR is not on it: for those few seconds where the film goes round,
-- the inside of the frame fades to black and back.
local function light_film()
    if not FILM then return end
    FILM.tick()
    if not ui.film_pmc then return end
    local b = BOX_DIM * FILM.growth()
    if math.abs(b - ui.film_b) > 0.003 then
        ui.film_b = b
        local c = { R = b, G = b, B = b, A = 1.0 }
        pcall(lib.update_section, ui.film_pmc, 0, ui.film_verts, { c, c, c, c })
    end
end

local function place_hand()
    if not valid(ui.hand) then return end
    local px = menu.cx + LAY.hand_off[1] + math.sin(menu.t * 6.0) * 5
    local py = menu.cy + LAY.hand_off[2] + math.cos(menu.t * 6.0) * 4
    -- (Mario 64 shows the pinching hand for 4 frames from the press: sCursorClickingTimer)
    local grab = (ui.grab_t or 0.0) > 0.0 and valid(ui.hand_grab)
    if grab ~= ui.grab_shown then
        ui.grab_shown = grab
        pcall(function() ui.hand:SetActorHiddenInGame(grab) end)
        pcall(function() ui.hand_grab:SetActorHiddenInGame(not grab) end)
    end
    pcall(function()
        local hand = grab and ui.hand_grab or ui.hand
        hand:K2_TeleportTo({ X = BASE.X + DIST - HAND_Z, Y = BASE.Y + MX(px) * HAND_K, Z = BASE.Z + MY(py) * HAND_K },
            { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
    end)
end

-- STORROR's tips: its UI layer manager (kept by the game instance, so it outlives the map change) puts a card
-- of tips over a picture on the screen as each map comes up, and fades it away again. None of it belongs here.
-- The card the layer manager builds them from is made see-through (so every one made from it starts that
-- way), and any that are about are made so too: before the map changes, every frame until the title screen
-- is up, and with each sweep of the game's UI after that. (See-through only: STORROR goes on running them as
-- it would, and only nothing shows.)
local TIP_WIDGETS = { "HITSLoadingScreenWidget", "HintsWidget" }
local function quiet_tips()
    for _, cname in ipairs(TIP_WIDGETS) do
        local ok, ws = pcall(FindAllOf, cname)
        if ok and ws then
            for i = 1, #ws do
                local w = ws[i]
                pcall(function()
                    if not w:IsValid() then return end
                    if w.RenderOpacity ~= 0.0 then
                        if M.state == "boot" then log("tips: made see-through %s", w:GetFName():ToString()) end
                        w.RenderOpacity = 0.0
                    end
                    pcall(function() w:SetRenderOpacity(0.0) end)        -- (the built one too, when there is one)
                end)
            end
        end
    end
end
M.quiet_tips = quiet_tips

-- ------------------------------------------------------------------ open / close
-- Everything of the game's own that is drawn over the picture (its HUD, its hints, its loading tips) is
-- put away while the title screen or the file select is up, and remembered so it can be put back.
local function hide_game_ui()
    pcall(quiet_tips)
    ui.hidden = ui.hidden or {}
    local ok, ws = pcall(function() return FindAllOf("UserWidget") end)
    if not (ok and ws) then return end
    for i = 1, #ws do
        local w = ws[i]
        pcall(function()
            if w:IsValid() and w:IsInViewport() and not w:GetFName():ToString():find("^SM64") then
                local vis = w:GetVisibility()
                if vis ~= 1 then
                    ui.hidden[#ui.hidden + 1] = { w = w, vis = vis }
                    w:SetVisibility(1)
                end
            end
        end)
    end
end

local function show_game_ui()
    for _, h in ipairs(ui.hidden or {}) do
        pcall(function() if h.w:IsValid() then h.w:SetVisibility(h.vis) end end)
    end
    ui.hidden = {}
end

M.hide_game_ui, M.show_game_ui = hide_game_ui, show_game_ui     -- (the opening for a new file clears the screen too)

-- The controls back to the game. STORROR's loading screen handed them back when it finished; with it switched
-- off they stayed with STORROR's menus (its mouse pointer on, the game deaf to the controller and keyboard:
-- 2026-10-14, the file select would not move). Done when the title or the file select opens, and again
-- whenever the game puts its pointer back up while they are on the screen.
local function controls_to_game()
    local pc = lib.controller()
    if not pc then return end
    pcall(function()
        StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):SetInputMode_GameOnly(pc, false)
        pc.bShowMouseCursor = false
    end)
end

-- STORROR's own menus are CommonUI menus, and Start on the title screen is also STORROR's pause button. Its pause
-- menu then opens under the title screen or the file select: unseen (its interface is put away) but taking every
-- button press, while the sticks still work (2026-10-14: "pressing a does nothing"; B, its own back button,
-- closed it). Any of its menus that comes up there is closed again from here, the way its B would.
local MENU_KEYS = { "Gamepad_Special_Right", "Gamepad_FaceButton_Bottom", "Enter", "Escape", "SpaceBar" }
local function close_game_menus()
    local ok, ws = pcall(FindAllOf, "CommonActivatableWidget")
    if not (ok and ws) then return 0 end
    local n = 0
    for i = 1, #ws do
        pcall(function()
            local w = ws[i]
            if w:IsValid() and w:IsActivated() and w:GetFullName():find("Transient", 1, true) then
                -- (out of sight first: shut, it fades out over about a second - STORROR's character page was seen
                -- going from the title screen to the file select, 2026-10-23 "just saw storror charater creator";
                -- pause.lua's shut_storror does the same)
                pcall(function() w:SetRenderOpacity(0.0) end)
                pcall(function() w:SetVisibility(1) end)                       -- (collapsed)
                if w:GetClass():GetFName():ToString() == "MenuPresenterBP_C" then
                    pcall(function()
                        local bg = w.Background
                        if bg and bg:IsValid() then bg:SetRenderOpacity(0.0); bg:SetVisibility(1) end
                    end)
                end
                w:DeactivateWidget()
                n = n + 1
            end
        end)
    end
    if n > 0 then log("closed %d of STORROR's own menus under ours", n) end
    return n
end

-- The athlete out of the way and STORROR's own HUD off the screen, for the title screen and the file select.
local function park()
    local pawn = lib.pawn()
    if not pawn then return end
    local cm = pawn.CharacterMovement
    pcall(function() cm:StopMovementImmediately(); cm:SetMovementMode(0, 0) end)
    pcall(function() pawn:K2_SetActorLocation({ X = BASE.X, Y = BASE.Y + 5000.0, Z = BASE.Z - 3000.0 }, false, {}, true) end)
    pcall(function() pawn:SetActorHiddenInGame(true) end)
    -- (STORROR's own buttons are his while the menus are up: A or Start would make him jump and drop out of
    -- the picture into the empty map below, taking the view with him. They are his again when a file starts.)
    pcall(function() pawn:DisableInput(lib.controller()) end)
    hide_game_ui()
    controls_to_game()
    ui.sweeps, ui.sweep = 0, 0.0
end
M.park = park

function M.open()
    if INTRO then pcall(INTRO.stop) end
    if ENDING then pcall(ENDING.stop) end
    load_saves()
    local world, pc, pawn = lib.world(), lib.controller(), lib.pawn()
    if not (world and pc and pawn) then return false end
    sizes = lib.load_data("data.menu_sizes") or {}
    if SFX then pcall(SFX.prepare) end         -- (so the first click is not late)
    menu.leaving = nil
    pcall(function() lib.controller().PlayerCameraManager:StopCameraFade() end)
    LAY = lib.load_data("data.menu_layout")
    M.state = "menu"
    menu.sel = math.max(1, math.min(4, saves.last or 1))
    menu.mode, menu.msg, menu.msg_t, menu.t = "select", nil, 0, 0
    menu.cx, menu.cy = sel_center(menu.sel)
    pad.reset()                         -- the button that brought us here is not also a choice here

    -- no city/scene while in the menu
    pcall(function() require("game").destroy_scene() end)
    M.ensure_env()
    pcall(function() require("sky").apply("water") end)
    pcall(function() require("music").play("menu_file_select") end)
    park()

    -- fixed camera in front of the menu plane
    ui.cam = lib.camera(world, "menu", BASE, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
    if ui.cam then
        -- a fixed exposure: left to itself the game brightens the whole picture when the film in the frame is
        -- dark, and the frame and the buttons wash out
        pcall(function()
            local pp = ui.cam.CameraComponent.PostProcessSettings
            pp.bOverride_AutoExposureMinBrightness, pp.bOverride_AutoExposureMaxBrightness = true, true
            pp.AutoExposureMinBrightness, pp.AutoExposureMaxBrightness = EXPOSURE, EXPOSURE
            pp.bOverride_AutoExposureBias, pp.AutoExposureBias = true, 0.0
        end)
        pcall(function() pc:SetViewTargetWithBlend(ui.cam, 0.0, 0, 0.0, false) end)
    end

    build_ui()
    local okf, errf = pcall(build_film, world)       -- (the file select does not depend on the film)
    if not okf then log("file select: the film did not go up: %s", tostring(errf)) end
    place_hand()
    log("file select open")
    return true
end

-- The title screen: Mario's head. Start goes on to the file select.
function M.open_title()
    if not TITLE then return M.open() end
    local world, pc, pawn = lib.world(), lib.controller(), lib.pawn()
    if not (world and pc and pawn) then return false end
    pcall(function() require("game").destroy_scene() end)
    M.ensure_env()
    park()
    ui.title_go = nil
    local ok, opened = pcall(TITLE.open)
    if not (ok and opened) then
        log("title screen failed (%s): straight to the file select", tostring(opened))
        return M.open()
    end
    pcall(function() require("music").play("menu_title_screen") end)
    M.state = "title"
    return true
end

-- Mario 64's GAME OVER screen (out of lives): the head over its GAME OVER wall, its own music; Start goes on to the
-- file select as the title screen's does
function M.game_over()
    if not TITLE then return M.open() end
    local world, pc, pawn = lib.world(), lib.controller(), lib.pawn()
    if not (world and pc and pawn) then return false end
    if M.state == "game" and saves then pcall(write_saves) end
    pcall(function() require("game").destroy_scene() end)
    M.ensure_env()
    park()
    ui.title_go = nil
    local ok, opened = pcall(TITLE.open, false, { game_over = true })
    if not (ok and opened) then
        log("game over screen failed (%s): straight to the file select", tostring(opened))
        return M.open()
    end
    pcall(function() require("music").play("menu_game_over") end)
    M.state = "title"
    return true
end

local function close_ui()
    local pc, pawn = lib.controller(), lib.pawn()
    if valid(ui.actor) then pcall(function() ui.actor:K2_DestroyActor() end) end
    if valid(ui.hand) then pcall(function() ui.hand:K2_DestroyActor() end) end
    if valid(ui.hand_grab) then pcall(function() ui.hand_grab:K2_DestroyActor() end) end
    if valid(ui.film) then pcall(function() ui.film:K2_DestroyActor() end) end
    ui.actor, ui.hand, ui.hand_grab, ui.film, ui.film_pmc = nil, nil, nil, nil, nil
    if pc and pawn then pcall(function() pc:SetViewTargetWithBlend(pawn, 0.0, 0, 0.0, false) end) end
    ui.cam = nil                    -- (it stays: lib.camera)
    show_game_ui()
    if pawn then
        pcall(function() pawn:SetActorHiddenInGame(false) end)
        pcall(function() pawn.CharacterMovement:SetMovementMode(3, 0) end)
    end
end

function M.start_game(i)
    -- (started straight from a file select already on its way out - its white held, and the fade back in, which that
    -- way out runs, never run: the screen stayed white, "after reset screen is white", 2026-10-23. That way out dropped,
    -- and the game fades in from the white all the same)
    if menu.leaving then
        local held = menu.leaving.fading
        menu.leaving = nil
        if held then camera_fade(1.0, 0.0, ARRIVE_FADE, false) end
    end
    -- (a file starts with full power and four lives, or the lives its save gives it: file A has 100, "just add 100 lives
    -- to the save then", 2026-10-14)
    local start_lives = saves and saves.files[i] and saves.files[i].lives
    if _G.HEALTH then _G.HEALTH.reset(); _G.HEALTH.lives = start_lives or _G.HEALTH.START_LIVES end
    M.lives_file = i                    -- (from now on its lives are his: write_saves keeps them)
    -- (a new file takes the switches as they stand; IRONMAN MODE: the one life)
    do
        local nf = saves and saves.files[i]
        if nf and not nf.used then nf.human, nf.ironman = saves.human_mode == true or nil, saves.ironman == true or nil end
        if nf and nf.ironman and _G.HEALTH then _G.HEALTH.lives = 1 end
    end
    local f = saves.files[i]
    local fresh = not f.used            -- a brand new file opens with Mario 64's opening scene
    if fresh then f.fp = saves.first_person == true end         -- (its perspective, for good)
    f.used = true
    saves.last = i
    write_saves()
    close_ui()
    if FILM then FILM.stop() end        -- the film's music ends where the game begins
    pcall(function() lib.pawn():EnableInput(lib.controller()) end)
    M.state = "game"
    M.file = i
    run.last, run.saved, run.going, run.armed = os.clock(), os.clock(), false, false
    local G = require("game")
    G.never_entered = fresh             -- (Mario 64's gNeverEnteredCastle: Lakitu on the bridge, Bowser's welcome)
    local ok, err = pcall(G.load_scene, "grounds")
    log("start file %d (%s person) -> grounds (%s %s)", i, f.fp and "first" or "third", tostring(ok), tostring(err))
    if fresh and ok and err and INTRO then
        local oki, on = pcall(INTRO.start)
        if not (oki and on) then log("the opening did not start: %s", tostring(on)) end
    end
end

-- Melty's test runs (melty.lua): a game on a file of its own, never written - not one of the player's four (write_saves
-- writes those alone) - straight to the castle grounds, with no opening scene
function M.start_test_file()
    if saves == nil then load_saves() end
    if menu.leaving then
        local held = menu.leaving.fading
        menu.leaving = nil
        if held then camera_fade(1.0, 0.0, ARRIVE_FADE, false) end
    end
    saves.files.melty = { used = true, stars = 0 }
    if _G.HEALTH then _G.HEALTH.reset(); _G.HEALTH.lives = _G.HEALTH.START_LIVES end
    M.lives_file = nil
    close_ui()
    if FILM then FILM.stop() end
    pcall(function() lib.pawn():EnableInput(lib.controller()) end)
    M.state = "game"
    M.file = "melty"
    run.last, run.saved, run.going, run.armed = os.clock(), os.clock(), false, false
    local G = require("game")
    G.never_entered = false
    local ok, err = pcall(G.load_scene, "grounds")
    log("melty test: a file of its own -> grounds (%s %s)", tostring(ok), tostring(err))
    return ok
end

-- (Melty's test runs: Start on the title screen, as a player would - melty.lua)
function M.title_start()
    if M.state ~= "title" or ui.title_go then return false end
    close_game_menus()
    ui.title_go = 2
    return true
end

function M.back_to_menu()
    if M.state == "menu" then return end
    if M.state == "game" and saves then pcall(write_saves) end       -- (the file's time so far)
    M.open()
end

function M.cursor() return menu.cx, menu.cy, menu.sel end        -- (tests)
-- (tests: the warning shown for file `sel` as if it had been picked, or taken down)
function M.test_confirm(sel)
    if sel then
        local kind, on = M.need_confirm(sel)
        menu.confirm = { sel = sel, kind = kind or "match", on = on, yes = false }
        menu.cx, menu.cy = M.confirm_xy(false)
    else
        menu.confirm = nil
    end
    build_ui()
    place_hand()
    return menu.confirm and menu.confirm.kind
end

-- ------------------------------------------------------------------ per-frame
-- No rumble at all with the mod: STORROR's force feedback off - in the menus ("rumble going off in menu for somereason")
-- and in play too ("controllers rumble goes off randomly completely turn it off for this mod", 2026-11-04) - looked at
-- twice a second (the controller is a new one after a map change, and STORROR may put it back on)
function M.rumble_tick(dt)
    M.ff_t = (M.ff_t or 0.0) + (dt or 0.0)
    if M.ff_t < 0.5 then return end
    M.ff_t = 0.0
    pcall(function()
        local pc = lib.controller()
        if not pc then return end
        if pc.ForceFeedbackScale ~= 0.0 then pc.ForceFeedbackScale = 0.0 end
        if pc.bForceFeedbackEnabled == false then return end
        pc.bForceFeedbackEnabled = false
        pc:ClientStopForceFeedback(nil, FName("None"))
    end)
end

-- STORROR's button pictures by the pad when the pad is in use: its input system (CommonInput) stayed on the keyboard and
-- mouse with the pad in his hands - "storror hud stuck on keyboard", 2026-11-05. A pad's button or stick seen while it
-- says keyboard, it is set to the pad; back to the keyboard it goes by itself, on a key or the mouse.
local PAD_KEYS = { "Gamepad_FaceButton_Bottom", "Gamepad_FaceButton_Right", "Gamepad_FaceButton_Left", "Gamepad_FaceButton_Top",
    "Gamepad_DPad_Up", "Gamepad_DPad_Down", "Gamepad_DPad_Left", "Gamepad_DPad_Right", "Gamepad_LeftShoulder",
    "Gamepad_RightShoulder", "Gamepad_Special_Left", "Gamepad_Special_Right", "Gamepad_LeftThumbstick", "Gamepad_RightThumbstick" }
local PAD_AXES = { "Gamepad_LeftX", "Gamepad_LeftY", "Gamepad_RightX", "Gamepad_RightY", "Gamepad_LeftTriggerAxis",
    "Gamepad_RightTriggerAxis" }
function M.input_type_tick(dt)
    M.it_t = (M.it_t or 0.0) + (dt or 0.0)
    if M.it_t < 0.2 then return end
    M.it_t = 0.0
    local pc = lib.controller()
    if not pc then return end
    local pad = false
    for _, k in ipairs(PAD_KEYS) do
        local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(k) }) end)
        if ok and v then pad = true; break end
    end
    if not pad then
        for _, k in ipairs(PAD_AXES) do
            local ok, v = pcall(function() return pc:GetInputAnalogKeyState({ KeyName = FName(k) }) end)
            if ok and type(v) == "number" and math.abs(v) > 0.35 then pad = true; break end
        end
    end
    if not pad then return end
    local s = M.cis
    if not (s and pcall(function() return s:IsValid() end) and s:IsValid()) then
        s = nil
        pcall(function() s = FindFirstOf("CommonInputSubsystem") end)
        M.cis = s
    end
    if not s then return end
    pcall(function()
        if s:GetCurrentInputType() ~= 1 then
            s:SetCurrentInputType(1)
            lib.log("input: the pad in use - STORROR's button pictures to the pad")
        end
    end)
end

function M.tick(dt)
    pcall(M.rumble_tick, dt)
    pcall(M.input_type_tick, dt)
    -- (STORROR's pause menu template gets its SWITCH MENU tab before STORROR first builds the menu, which Start on
    -- the title screen already does: pause.lua)
    local PA = package.loaded["pause"]
    if PA and PA.prepare then pcall(PA.prepare) end
    if M.state == "boot" then
        quiet_tips()
        -- the opening logo covers the screen until the game behind it is ready for the title screen
        if LOGO then
            local ok, r = pcall(LOGO.tick, dt, M.ready == true)
            if not ok then
                log("opening logo: %s", tostring(r))
                pcall(LOGO.close)
                LOGO = nil
            elseif r == "done" and M.ready then
                M.ready, M.quick, M.quick_since = false, false, nil
                M.open_title()
                -- (its black kept up over the title's first frames till they run smoothly - the game's first sight of
                -- the film and the head stalls a frame for a tenth of a second: "2nd menu starts up laggy", 2026-10-20 -
                -- and the title's clock held meanwhile, so the head comes in after it; a second and a bit at most)
                if M.state == "title" and TITLE and TITLE.settled then
                    M.cover_logo, M.cover_until = LOGO, os.clock() + 1.2
                    TITLE.covered = true
                else
                    pcall(LOGO.close)
                end
            elseif LOGO.gone and M.after_logo then
                local go = M.after_logo
                M.after_logo = nil
                go()
            end
        elseif M.ready then
            M.ready, M.quick, M.quick_since = false, false, nil
            M.open_title()
        end
        return
    end
    if (M.state == "title" or M.state == "menu") and (ui.sweeps or 0) < 5 then
        -- the game brings parts of its interface up late (after its loading screen): they are put away a
        -- few more times over the first seconds, and then left alone. (Looking through every widget the
        -- game has is not something to do for ever: the list can hold ones it is in the middle of discarding.)
        ui.sweep = (ui.sweep or 0.0) + dt
        if ui.sweep > 0.8 then ui.sweep = 0.0; ui.sweeps = (ui.sweeps or 0) + 1; hide_game_ui() end
    end
    if M.state == "title" or M.state == "menu" then
        local pc = lib.controller()
        local up = false
        pcall(function() up = pc.bShowMouseCursor end)
        ui.menu_t = (ui.menu_t or 0.0) + dt
        -- (Start, which is STORROR's pause button, or A or Enter: looked for every frame for a second after, so a
        -- menu of STORROR's that it opens is shut before it has faded in)
        local press = false
        for _, k in ipairs(MENU_KEYS) do
            pcall(function() if pc:IsInputKeyDown({ KeyName = FName(k) }) then press = true end end)
        end
        if press then ui.burst = 1.0 end
        ui.burst = (ui.burst or 0.0) - dt
        if up or ui.menu_t > 0.3 or ui.burst > 0.0 then
            ui.menu_t = 0.0
            close_game_menus()
        end
        if up then
            if not ui.said_controls then ui.said_controls = true; log("the game took the controls for its menus: given back") end
            controls_to_game()
        end
        -- the picture stays the menu's: some of STORROR's own buttons put the view back on the athlete (B on
        -- the file select did, 2026-10-14), and he waits out of sight in the empty space under the menus
        local cam = nil
        if M.state == "menu" then cam = ui.cam elseif TITLE then pcall(function() cam = TITLE.state().cam end) end
        if valid(cam) and pc then
            local same = false
            pcall(function() same = pc:GetViewTarget():GetAddress() == cam:GetAddress() end)
            if not same then
                if not ui.said_view then ui.said_view = true; log("the game moved the view to the athlete: put back on the menu") end
                pcall(function() pc:SetViewTargetWithBlend(cam, 0.0, 0, 0.0, false) end)
            end
        end
        -- and the athlete stays where he waits: if anything set him moving, he is put back and stopped
        local pawn = lib.pawn()
        local mode = 0
        pcall(function() mode = pawn.CharacterMovement.MovementMode end)
        if pawn and mode ~= 0 then
            log("the athlete was moving under the menus (mode %s): parked again", tostring(mode))
            park()
        end
    end
    if M.cover_logo and (M.state ~= "title" or os.clock() >= M.cover_until or (TITLE.settled and TITLE.settled())) then
        pcall(M.cover_logo.close)
        M.cover_logo, M.cover_until, TITLE.covered = nil, nil, false
    end
    if M.state == "title" then
        -- (Start on the title is STORROR's pause button too: its character page is drawn the frame it is pressed and
        -- shut on the next (the burst above) - but the file select, built straight after in that same frame, kept the
        -- last picture on the screen for its 0.4 s: "random character screen showing when going from menu 2 to 3",
        -- 2026-10-24. So a clean frame is drawn first, and the file select is built two frames on.)
        if ui.title_go then
            ui.title_go = ui.title_go - 1
            close_game_menus()
            if ui.title_go <= 0 then
                ui.title_go = nil
                M.open()
                pcall(TITLE.close, true)        -- the film and its music carry on
            end
            return
        end
        local ok, r = pcall(TITLE.tick, dt)
        if not ok then log("title screen: %s", tostring(r)) end
        if not ok or r == "start" or not TITLE.active then
            close_game_menus()
            ui.title_go = 2
        end
        return
    end
    if M.state == "game" then
        run_clock()
        if INTRO then
            local oki, e = pcall(INTRO.tick, dt)
            if not oki then log("the opening: %s", tostring(e)); pcall(INTRO.stop) end
        end
        if ENDING then
            local oke, e = pcall(ENDING.tick, dt)
            if not oke then log("the ending: %s", tostring(e)); pcall(ENDING.stop) end
        end
        return
    end
    if M.state ~= "menu" then return end
    pcall(light_film)
    menu.t = menu.t + dt

    -- leaving for a file, as Mario 64 does (levels/menu/script.c): the music fades and the screen fades to white,
    -- holds a moment, and the game begins behind it and fades in from white
    if menu.leaving then
        local L = menu.leaving
        L.t = L.t + dt
        local k = math.min(1.0, math.max(0.0, (L.t - LEAVE_WAIT) / LEAVE_FADE))
        if FILM and FILM.set_volume then pcall(FILM.set_volume, 1.0 - k) end
        if not L.fading and L.t >= LEAVE_WAIT then
            L.fading = true
            camera_fade(0.0, 1.0, LEAVE_FADE, true)
        end
        if L.t >= LEAVE_WAIT + LEAVE_FADE + LEAVE_HOLD then
            menu.leaving = nil
            local ok, err = pcall(M.start_game, L.sel)
            if not ok then log("starting file %s: %s", tostring(L.sel), tostring(err)) end
            camera_fade(1.0, 0.0, ARRIVE_FADE, false)        -- (whatever happened: never left on white)
            return
        end
        place_hand()
        return
    end
    local dirty = false
    if menu.msg then
        menu.msg_t = menu.msg_t - dt
        if menu.msg_t <= 0 then menu.msg = nil; dirty = true end
    end
    -- (the warning up: left and right - or the stick - pick YES or NO, A takes it, B is NO)
    if menu.confirm then
        local C = menu.confirm
        local sx = pad.sticks()
        local was = C.yes
        if pad.pressed("left") then C.yes = true elseif pad.pressed("right") then C.yes = false end
        if math.abs(sx) > 0.5 and not C.held then C.held = true; C.yes = sx < 0.0
        elseif math.abs(sx) < 0.3 then C.held = false end
        if C.yes ~= was then sound("menu_click"); dirty = true end
        if (ui.grab_t or 0.0) > 0.0 then ui.grab_t = ui.grab_t - dt end
        local ok_now, start_now, back_now = pad.pressed("ok"), pad.pressed("start"), pad.pressed("back")
        if ok_now or start_now or back_now then ui.grab_t = 4.0 / 30.0 end
        if (ok_now or start_now) and C.yes then
            menu.confirm = nil
            log("file select: the warning answered YES - file %d", C.sel)
            sound("menu_file")
            menu.leaving = { sel = C.sel, t = 0.0 }
            build_ui()
            place_hand()
            return
        elseif ok_now or start_now or back_now then
            menu.confirm = nil
            log("file select: the warning answered NO")
            sound("menu_zoom_out")
            menu.sel = C.sel
            menu.cx, menu.cy = sel_center(C.sel)
            dirty = true
        else
            menu.cx, menu.cy = M.confirm_xy(C.yes)
        end
        if dirty then build_ui() end
        place_hand()
        return
    end

    -- the hand: either stick moves it freely; the d-pad and the arrow keys step it from one thing to the next
    local sx, sy = pad.sticks()
    if sx ~= 0.0 or sy ~= 0.0 then
        menu.cx = math.max(30.0, math.min(WIDE_W - 30.0, menu.cx + sx * CURSOR_SPEED * dt))
        menu.cy = math.max(30.0, math.min(LAY.screen.h - 30.0, menu.cy - sy * CURSOR_SPEED * dt))
    end
    for _, dir in ipairs({ "up", "down", "left", "right" }) do
        if pad.pressed(dir) then
            local nxt = NAV[hovered() or menu.sel][dir]
            if nxt then
                menu.cx, menu.cy = sel_center(nxt)
                if nxt ~= menu.sel then menu.sel = nxt; dirty = true end
            end
        end
    end
    local over = hovered()
    if over and over ~= menu.sel then menu.sel = over; dirty = true end

    if (ui.grab_t or 0.0) > 0.0 then ui.grab_t = ui.grab_t - dt end
    local back_now = pad.pressed("back")
    if back_now then
        if menu.mode == "erase" or menu.mode == "copy" then
            menu.mode, menu.msg, menu.copy_from = "select", nil, nil
            dirty = true
            sound("menu_zoom_out")
        end
    end
    local ok_now, start_now = pad.pressed("ok"), pad.pressed("start")
    if ok_now or start_now or back_now then ui.grab_t = 4.0 / 30.0 end
    if (ok_now or start_now) and over then
        local sel = over
        if sel <= 4 and menu.mode == "copy" then
            -- COPY, as Mario 64's: a file to copy, then an empty file to copy it to
            local f = saves.files[sel]
            if not menu.copy_from then
                if f.used then
                    menu.copy_from = sel
                    menu.msg, menu.msg_t = "menu_msg_copy_to", 1e9
                    sound("menu_click")
                else
                    sound("menu_buzz")                  -- nothing in it to copy
                end
            elseif sel == menu.copy_from or f.used then
                sound("menu_buzz")                      -- (Mario 64: "SAVED DATA EXISTS")
            else
                local from = menu.copy_from
                local src = saves.files[from]
                local got = {}
                for key in pairs(src.got or {}) do got[key] = true end
                local coins = {}
                for course, n in pairs(src.coins or {}) do coins[course] = n end
                saves.files[sel] = { used = true, stars = src.stars or 0, time = src.time or 0.0, got = got, coins = coins,
                                     fp = src.fp == true, human = src.human == true or nil, ironman = src.ironman == true or nil }
                write_saves()
                menu.mode, menu.copy_from = "select", nil
                menu.msg, menu.msg_t = "menu_msg_copied", 2.0
                sound("title_start")                   -- (Mario 64's copy plays the star sound)
                log("file %d copied to file %d", from, sel)
            end
            dirty = true
        elseif sel <= 4 then
            if menu.mode == "erase" then
                if saves.files[sel].used then
                    saves.files[sel] = { used = false, stars = 0 }
                    write_saves()
                    menu.mode = "select"
                    menu.msg, menu.msg_t = "menu_msg_erased", 2.0
                    dirty = true
                    sound("menu_erase")             -- Mario's "waaaooow" as his file goes
                else
                    sound("menu_buzz")              -- nothing there to erase
                end
            else
                local kind, on = M.need_confirm(sel)
                if kind then
                    -- (the warning first: M.need_confirm)
                    menu.confirm = { sel = sel, kind = kind, on = on, yes = false }
                    menu.cx, menu.cy = M.confirm_xy(false)
                    log("file select: warning about the game modes (%s) for file %d", kind, sel)
                    sound("menu_zoom_in")
                    dirty = true
                else
                    sound("menu_file")                  -- the star sound and "okey dokey"
                    menu.leaving = { sel = sel, t = 0.0 }       -- (the screen fades first: see the top of the tick)
                    return
                end
            end
        elseif sel == TIMER then
            saves.timer = not saves.timer
            write_saves()
            menu.msg = nil
            dirty = true
            sound("menu_click")
        elseif sel == ERASE then
            menu.copy_from = nil
            if menu.mode == "erase" then
                menu.mode, menu.msg = "select", nil
                sound("menu_zoom_out")
            else
                menu.mode, menu.msg, menu.msg_t = "erase", "menu_msg_erase", 1e9
                sound("menu_zoom_in")
            end
            dirty = true
        elseif sel == COPY then
            if menu.mode == "copy" then
                menu.mode, menu.msg, menu.copy_from = "select", nil, nil
                sound("menu_zoom_out")
            else
                menu.mode, menu.msg, menu.msg_t, menu.copy_from = "copy", "menu_msg_copy", 1e9, nil
                sound("menu_zoom_in")
            end
            dirty = true
        elseif sel == FP and M.FP_OFF then
            sound("menu_buzz")              -- (first person is off for now)
        elseif sel == FP then
            saves.first_person = not saves.first_person
            write_saves()
            menu.msg = nil
            dirty = true
            sound("menu_click")
        elseif sel == HUMAN or sel == IRONMAN then
            -- (for files started from now on; a file already going keeps what it has - M.set_human)
            local now_on
            if sel == HUMAN then
                saves.human_mode = not saves.human_mode; now_on = saves.human_mode
            else
                saves.ironman = not saves.ironman; now_on = saves.ironman
            end
            write_saves()
            log("file select: %s %s for new files", sel == HUMAN and "HUMAN" or "IRONMAN", now_on and "on" or "off")
            menu.msg = nil
            dirty = true
            sound("menu_click")
        end
    end
    if dirty then build_ui() end
    place_hand()
end

-- ------------------------------------------------------------------ boot sequencing (called every ~500 ms)
local travel_at = nil
local first_other_world = nil
local inited_for = nil
local settle = 0
local config_done = false
local last_wname = nil
local logo_armed = false

local function travel_to_empty_map()
    local pc, world = lib.controller(), lib.world()
    if not (pc and world) then return end
    if LOGO and not LOGO.gone and not LOGO.done then
        pcall(LOGO.leave)                       -- it shrinks away first; this is called again in half a second
        return
    end
    -- STORROR's loading screen (its hints over a picture) is not part of this game: it is switched off before
    -- the map changes, with the switch its loading screen plugin has for that, and stays off
    local ok_ls, e_ls = pcall(function()
        StaticFindObject("/Script/HITS_LoadingScreen.Default__HITSLoadingScreenLibrary"):SetEnableLoadingScreen(false)
    end)
    if not ok_ls then log("STORROR's loading screen could not be switched off: %s", tostring(e_ls)) end
    quiet_tips()
    local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    pcall(function()
        ksl:ExecuteConsoleCommand(world, "open " .. M.EMPTY_MAP .. "?game=" .. M.GAME_MODE, pc)
    end)
    travel_at = os.clock()
    log("travelling to the empty map")
end

-- the screen black and STORROR's own interface put away, while a "quit to menu" waits in STORROR's start map
local last_quick_world = nil
local function quick_cover()
    pcall(function()
        lib.controller().PlayerCameraManager:StartCameraFade(1.0, 1.0, 0.0, { R = 0.0, G = 0.0, B = 0.0, A = 1.0 }, false, true)
    end)
    pcall(hide_game_ui)
end

function M.boot_tick()
    if not config_done then
        config_done = true
        pcall(install_boot_config)
    end
    local world = lib.world()
    if not world then return end
    local wname = ""
    pcall(function() wname = world:GetFullName() end)
    local now = os.clock()
    if wname ~= last_wname then
        last_wname = wname
        log("world: %s", wname)
    end
    if wname:find("DedicatedServerEmptyMap", 1, true) then
        local gname = ""
        pcall(function() gname = world.AuthorityGameMode:GetFullName() end)
        if gname:find("MMGameMode_C", 1, true) then
            local addr = nil
            pcall(function() addr = world:GetAddress() end)
            if inited_for ~= addr and lib.pawn() and lib.controller() then
                settle = settle + 1
                if settle >= 4 then            -- ~2 s after the pawn exists
                    inited_for = addr
                    settle = 0
                    M.state = "boot"
                    M.ensure_env()
                    M.ready = true              -- the title screen opens as soon as the opening logo has gone
                end
            end
        elseif not (_G.SM64 and _G.SM64.name) then    -- never pull the map out from under a scene that is running
            if not travel_at or now - travel_at > 30 then travel_to_empty_map() end
        end
        first_other_world = nil
    elseif M.AUTO_TRAVEL and M.state ~= "boot" then
        -- The game went to a map of its own while a file was played or the menus were up: the pause menu's
        -- "quit to menu" (its settings section) loads STORROR's start map. Back to Mario's face (menu 2) the way
        -- the game starts, but without the opening logo, which has been seen: the file's time is kept, and
        -- the move to the empty map starts at once (next look, below).
        log("the game went to a map of its own (%s): back to Mario's face", wname)
        if M.state == "game" and saves then pcall(write_saves) end
        -- (what the menus had in the old map went with it: forgotten, never touched, or the game can come down)
        ui.actor, ui.hand, ui.hand_grab, ui.film, ui.film_pmc, ui.cam = nil, nil, nil, nil, nil, nil
        ui.hidden = {}                  -- (the game's widgets hidden in the old map, to be shown again: gone too)
        if FILM then pcall(FILM.stop) end
        M.state, M.ready, M.file, M.quick, M.quick_since = "boot", false, nil, true, nil
        travel_at, first_other_world, settle, last_quick_world = nil, nil, 0, nil
        quick_cover()
    elseif M.AUTO_TRAVEL and M.state == "boot" then
        -- still in the map the game starts in: leave as soon as the opening logo has had its time and
        -- gone (or, with no logo, after ten seconds). The logo goes by itself, and the move starts on the
        -- very frame it has gone (see M.tick); this look, twice a second, is only the fallback.
        first_other_world = first_other_world or now
        if LOGO and not logo_armed then
            logo_armed = true
            LOGO.leaves_unasked = true
            M.after_logo = function() if not travel_at then travel_to_empty_map() end end
        end
        -- (after a "quit to menu": STORROR's start map gets 3 s to settle first, or it pulls the game back to
        -- itself a moment after the move (seen 2026-10-14); a pull-back is answered after 6 s, not 30; and its
        -- own menu stays out of sight meanwhile)
        if M.quick then
            local waddr = nil
            pcall(function() waddr = world:GetAddress() end)
            if last_quick_world ~= waddr or not M.quick_since then last_quick_world, M.quick_since = waddr, now end
            quick_cover()
        end
        local due
        if M.quick then due = now - M.quick_since > 3.0
        else due = (LOGO ~= nil and LOGO.gone) or (now - first_other_world > 10) end
        if due and (not travel_at or now - travel_at > (M.quick and 6 or 30)) then
            travel_to_empty_map()
        end
    end
end

return M
