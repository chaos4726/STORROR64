-- Melty's test runs (its test_release): only while %LOCALAPPDATA%\Melty\test\super-storror-64.json is there - players
-- never have that file, and for them this does nothing at all. In a test run the mod plays its own way in by itself:
-- the title screen, the file select, a game on a file of its own (never written - not one of the player's four), the
-- castle grounds, then Bob-omb Battlefield. A line per check goes to the file Melty names in the JSON ("checks"):
-- "pass <name>" or "fail <name>: why". The game is never closed from here: Melty closes it when the run ends.
local M = {}
M.SLUG = "super-storror-64"

local lib = require("lib")
local log = lib.log

local st = nil          -- the test: { checks = path, run = n, stage = name, t = seconds in the stage, said = {} }

local function unescape(s)
    return (s:gsub("\\(.)", function(c)
        if c == "n" then return "\n" elseif c == "t" then return "\t" end
        return c
    end))
end

local function read_test(path)
    if not path then
        local base = os.getenv("LOCALAPPDATA")
        if not base or base == "" then return nil end
        path = base .. "\\Melty\\test\\" .. M.SLUG .. ".json"
    end
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("a") or ""
    f:close()
    local checks = s:match('"checks"%s*:%s*"(.-[^\\])"')
    if not checks then log("melty test: no checks file named in its JSON"); return nil end
    return { checks = unescape(checks), run = tonumber(s:match('"run"%s*:%s*(%d+)')) or 1,
             stage = "start", t = 0.0, said = {} }
end

local function report(name, ok, why)
    if not st or st.said[name] then return end
    st.said[name] = true
    local line = ok and ("pass " .. name) or ("fail " .. name .. ": " .. tostring(why or "no reason given"))
    local f = io.open(st.checks, "a")
    if f then f:write(line, "\n"); f:close() else log("melty test: could not write %s", st.checks) end
    log("melty test: %s", line)
end

local function stage(name)
    st.stage, st.t, st.held = name, 0.0, 0.0
    log("melty test: %s", name)
end

-- (and every check not reported yet failed with the same reason: the run stops there)
local function give_up(why)
    for _, n in ipairs({ "castle-grounds", "course-loads" }) do report(n, false, why) end
    stage("done")
end

-- (path: a test file somewhere else, for a dry run from the dev channel; left out, Melty's own)
function M.init(path)
    st = read_test(path)
    if st then log("melty test run %d: checks to %s", st.run, st.checks) end
end

function M.active() return st ~= nil and st.stage ~= "done" end

function M.tick(dt)
    if not M.active() then return end
    st.t = st.t + dt
    local MENU, G = _G.MENU, package.loaded["game"]
    if st.stage == "start" then
        if MENU and G then report("mod-loaded", true); stage("title")
        elseif st.t > 60 then report("mod-loaded", false, "the menus or the game script did not load"); give_up("the mod did not load") end
    elseif st.stage == "title" then
        -- the title screen up a few seconds: Start, as a player would
        if MENU.state == "title" then
            st.held = st.held + dt
            if st.held > 4.0 and MENU.title_start and MENU.title_start() then stage("file select") end
        elseif MENU.state == "menu" then stage("file select")
        elseif st.t > 180 then give_up("the title screen never came up (menus: " .. tostring(MENU.state) .. ")") end
    elseif st.stage == "file select" then
        if MENU.state == "menu" then
            st.held = st.held + dt
            if st.held > 2.0 then
                local ok, r = pcall(MENU.start_test_file)
                if ok and r then stage("grounds") else give_up("the game did not start (" .. tostring(r) .. ")") end
            end
        elseif MENU.state == "game" then stage("grounds")
        elseif st.t > 60 then give_up("the file select never opened (menus: " .. tostring(MENU.state) .. ")") end
    elseif st.stage == "grounds" then
        if G.name == "grounds" and lib.pawn() then
            st.held = st.held + dt
            if st.held > 8.0 then
                report("castle-grounds", true)
                stage("course")
                local ok, r = pcall(G.load_scene, "bob")
                if not (ok and r) then report("course-loads", false, "Bob-omb Battlefield did not load (" .. tostring(r) .. ")"); stage("done") end
            end
        elseif st.t > 120 then give_up("no castle grounds after 2 minutes (scene: " .. tostring(G.name) .. ")") end
    elseif st.stage == "course" then
        if G.name == "bob" and lib.pawn() then
            st.held = st.held + dt
            if st.held > 5.0 then
                local enemies = #(G.goombas or {})
                if enemies > 0 then report("course-loads", true)
                else report("course-loads", false, "Bob-omb Battlefield has no enemies in it") end
                stage("done")
            end
        elseif st.t > 120 then report("course-loads", false, "no Bob-omb Battlefield after 2 minutes (scene: " .. tostring(G.name) .. ")"); stage("done") end
    end
end

return M
