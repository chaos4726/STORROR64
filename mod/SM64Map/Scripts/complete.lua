-- SM64Map: Mario 64's course-complete screen (game/ingame_menu.c render_course_complete_screen), shown when he is
-- back in the castle after a star has taken him out of a course: he lands out of the painting (or up through the
-- trap door, after Bowser's key), time stops, and over the picture come COURSE <n> and the star's name with a star
-- by it, and the coins he had, counted up from nought one every other frame (every frame past 70) with a tick, a
-- life at 50, 100 and 150; HI SCORE flashes when the course's best was beaten; the star's fanfare plays once the
-- count is done if the star is a new one. A Bowser course says "<NAME> CLEAR" and CONGRATULATIONS instead; a castle
-- secret star "ONE OF THE CASTLE'S SECRET STARS!". After 100 frames, once the count is done, the picture is shaded,
-- and A goes on. (Mario 64 asks then whether to save: the mod's file is saved as each star is taken, so
-- the screen just goes on.)
--
-- The lettering is the pause screen's (exporter/pausex.py: textures/pause_t_*.png, hud_*.png, data/pause.lua), at
-- Mario 64's own places on its 320 x 240 screen, the screen's height filling the window's.
local lib = require("lib")
local pad = require("pad")
local log = lib.log
local M = { active = false }

local LOCK = "SM64Complete"
local SHADE = 110 / 255
local OPEN_AFTER = 100          -- frames: gCourseCompleteScreenTimer > 100 (and the count done) -> shaded
local GO_AFTER = 110            -- frames: A or Start goes on after this

local DATA = nil
local function data()
    if DATA == nil then DATA = lib.load_data("data.pause") or false end
    return DATA or nil
end

local function sound(name)
    local S = package.loaded["sfx"]
    if S then pcall(S.play, name) end
end

local function hold(name)
    local S = package.loaded["sfx"]
    if S and S.hold then pcall(S.hold, name, 1.0) end
end

-- the athlete held, as a message holds him (dialog.lua's lock: his controls, his parkour and his running)
local function lock(on, again)
    local pc, pawn = lib.controller(), lib.pawn()
    if not (pc and pawn) then return end
    if not again then pcall(function() pc:SetIgnoreMoveInput(on) end) end
    pcall(function() if on then pawn:DisableInput(pc) else pawn:EnableInput(pc) end end)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            local cname = o:GetClass():GetFName():ToString()
            if cname == "ParkourComponent" then
                o:ClearInputQueue()
                o:EnableAllParkourInputs(FName(LOCK), not on)
            elseif cname == "LocomotionComponent" then
                o:EnableLocomotionInputCallback(FName(LOCK), not on)
                o:EnableAdvancedLocomotionInput(FName(LOCK), not on)
            end
        end
    end)
    if on then pcall(function() pawn.CharacterMovement:StopMovementImmediately() end) end
end

-- ------------------------------------------------------------------ on the screen
local serial = 0

local function unit(world)
    local WLL = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    local u = 4.5
    pcall(function()
        local size = WLL:GetViewportSize(world)
        local scale = WLL:GetViewportScale(world)
        if size and scale and scale > 0 and size.Y > 0 then u = size.Y / scale / 240.0 end
    end)
    return u
end

local function begin()
    local world, pc = lib.world(), lib.controller()
    if not (world and pc) then return nil end
    local function cls(p) return StaticFindObject(p) end
    serial = serial + 1
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("SM64CompleteScreen" .. serial))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("SM64CompleteTree" .. serial))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SM64CompleteCanvas" .. serial))
    tree.RootWidget = canvas
    return { widget = w, world = world:GetAddress(), wobj = world, canvas = canvas, U = unit(world), n = 0, cls = cls }
end

local function image(b, file, color)
    b.n = b.n + 1
    local img = StaticConstructObject(b.cls("/Script/UMG.Image"), b.canvas, FName("SM64CompleteImg" .. serial .. "_" .. b.n))
    local tex = file and lib.texture(b.wobj, file)
    if tex then img:SetBrushFromTexture(tex, false) end
    if color then pcall(function() img:SetColorAndOpacity(color) end) end
    return img, b.canvas:AddChildToCanvas(img)
end

-- a picture with its top left at Mario 64's (x, top), top down, w x h of its pixels
local function pic(b, file, x, top, w, h, color)
    local img, slot = image(b, file, color)
    slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.0 }, Maximum = { X = 0.5, Y = 0.0 } })
    slot:SetAlignment({ X = 0.0, Y = 0.0 })
    slot:SetSize({ X = w * b.U, Y = h * b.U })
    slot:SetPosition({ X = (x - 160.0) * b.U, Y = top * b.U })
    return img, slot
end

local BLACK = { R = 0.0, G = 0.0, B = 0.0, A = 1.0 }

-- a line where print_generic_string(x, y) puts it (y up from the bottom), with its black shadow where Mario 64 prints
-- it first (2 right, 2 down); the pictures go on `list`, to be faded in
local function text(b, key, x, y, list)
    local wd = data().widths[key]
    if not wd then return nil end
    local s = pic(b, "pause_t_" .. key, x + 2, 240 - (y - 2) - 16, wd[2], 16, BLACK)
    local t = pic(b, "pause_t_" .. key, x, 240 - y - 16, wd[2], 16)
    if list then list[#list + 1] = s; list[#list + 1] = t end
    return x + wd[1]
end

-- the counters' lettering (print_hud_lut_string: 16 x 16 pictures 12 apart, a space half that), top down
local function hud(b, chars, x, top, list)
    for i = 1, #chars do
        local c = chars:sub(i, i)
        if c == " " then
            x = x + 6
        else
            local file = (c == "*") and "hud_star" or (c == "$") and "hud_coin" or (c == "x") and "hud_x" or ("hud_" .. c)
            local img = pic(b, file, x, top, 16, 16)
            if list then list[#list + 1] = img end
            x = x + 12
        end
    end
end

local st = nil

-- render_course_complete_lvl_info_and_hud_str
local function build(info)
    local b = begin()
    if not b then return nil end
    local u = { b = b, fade = {}, flash = {}, digits = {} }
    -- (the shade first, under the rest: none till the screen is open)
    local shade, sslot = image(b, "pause_white", { R = 0.0, G = 0.0, B = 0.0, A = SHADE })
    sslot:SetAnchors({ Minimum = { X = 0.0, Y = 0.0 }, Maximum = { X = 1.0, Y = 1.0 } })
    sslot:SetOffsets({ Left = 0.0, Top = 0.0, Right = 0.0, Bottom = 0.0 })
    shade:SetRenderOpacity(0.0)
    u.shade = shade
    local n, star = info.course, info.star
    local cy = 103
    if n == 16 or n == 17 then
        -- (a Bowser course: its name and CLEAR, CONGRATULATIONS over the coins)
        local sp = data().space or 6
        local w = 3 * sp + ((data().widths["cname_" .. n] or { 0 })[1])
        text(b, "cname_" .. n, 69 + 3 * sp, 132, u.fade)
        text(b, "clear", w + 79, 132, u.fade)
        hud(b, "CONGRATULATIONS", 70, 67, u.flash)
        cy = 111
    else
        if n <= 15 then
            text(b, "course", 63, 167, u.fade)
            text(b, "num_" .. n, 102, 167, u.fade)
            if star and star >= 1 and star <= 6 then text(b, "act_" .. n .. "_" .. star, 74, 147, u.fade)
            -- (the course's extra star - "<course>:7", the race against its ghost - its own name, pause_t_act_<n>_7:
            -- tools/pause_extra_acts.py. The 100 coins' star, 7, has none, as in Mario 64)
            elseif star == 8 then text(b, "act_" .. n .. "_7", 74, 147, u.fade) end
        else
            text(b, "secret_got", 74, 147, u.fade)
        end
        hud(b, "*", 55, 77, u.fade)
    end
    -- the coins: their sign, the x, and up to three digits counted up
    pic(b, "hud_coin", 118, cy, 16, 16)
    pic(b, "hud_x", 134, cy, 16, 16)
    for i = 1, 3 do
        local img = pic(b, "hud_0", 150 + (i - 1) * 12, cy, 16, 16)
        img:SetRenderOpacity(i == 1 and 1.0 or 0.0)
        u.digits[i] = img
    end
    -- HI SCORE, flashing, once the count has reached a new best
    u.hi = {}
    if info.hiscore then
        hud(b, "HI SCORE", 109, 36, u.hi)
        for _, img in ipairs(u.hi) do img:SetRenderOpacity(0.0) end
    end
    for _, img in ipairs(u.fade) do img:SetRenderOpacity(0.0) end
    b.widget:AddToViewport(9400)
    return u
end

local function show_count(u, c)
    local s = tostring(math.max(0, math.min(999, c)))
    for i = 1, 3 do
        local d = s:sub(i, i)
        local img = u.digits[i]
        if d ~= "" then
            pcall(function()
                local tex = lib.texture(u.b.wobj, "hud_" .. d)
                if tex then img:SetBrushFromTexture(tex, false) end
                img:SetRenderOpacity(1.0)
            end)
        else
            pcall(function() img:SetRenderOpacity(0.0) end)
        end
    end
end

local function ui_ok(s)
    if not (s and s.ui) then return false end
    local ok, v = pcall(function() return s.world == lib.world():GetAddress() and s.ui.b.widget:IsValid() end)
    return ok and v
end

local function remove(s)
    if ui_ok(s) then pcall(function() s.ui.b.widget:RemoveFromParent() end) end
end

-- Show it: `info` = { course = 1..24, star = 1..7, coins = n, hiscore = true if the course's best was beaten, new =
-- true if the star was not had before }; `done()` once A has been pressed. False if it could not be shown.
function M.open(info, done)
    if st then M.close(true) end
    local world = lib.world()
    if not (world and data() and info and info.course) then return false end
    local ok, u = pcall(build, info)
    if not ok or not u then log("course complete screen: %s", tostring(u)); return false end
    st = { world = world:GetAddress(), ui = u, info = info, done = done, t = 0.0, frame = 0, count = 0,
           equal = (info.coins or 0) <= 0, alpha = 0, open = false, relock = 0.1, fanfare = false }
    lock(true)
    pad.reset()
    M.active = true
    log("course complete: course %d star %s, %d coins%s%s", info.course, tostring(info.star), info.coins or 0,
        info.hiscore and ", hi score" or "", info.new and ", new star" or "")
    return true
end

function M.close(quiet)
    local s = st
    st = nil
    M.active = false
    if _G.HEALTH then _G.HEALTH.star_flash = nil end
    if not s then return end
    local same = false
    pcall(function() same = lib.world():GetAddress() == s.world end)
    if not same then return end
    remove(s)
    lock(false)
    if not quiet and s.done then pcall(s.done) end
end

function M.forget() st = nil; M.active = false; if _G.HEALTH then _G.HEALTH.star_flash = nil end end

-- one of Mario 64's frames
local function frame(s)
    local u, info = s.ui, s.info
    local coins = info.coins or 0
    -- print_hud_course_complete_coins
    if s.count >= coins then
        s.equal = true
        s.count = coins
    else
        if (s.frame % 2 == 1) or coins > 70 then
            s.count = s.count + 1
            show_count(u, s.count)
            if s.count == 50 or s.count == 100 or s.count == 150 then
                sound("oneup")
                local HP = _G.HEALTH
                if HP then HP.lives = HP.lives + 1 end
                log("course complete: a life at %d coins", s.count)
            end
            if s.count == coins and info.hiscore then sound("hiscore") end
        end
    end
    -- play_star_fanfare_and_flash_hud: once the count is done, for a star not had before (and after Bowser)
    if s.equal and not s.fanfare and (info.new or info.course == 16 or info.course == 17) then
        s.fanfare = true
        sound("star_fanfare")
        -- (play_star_fanfare: the music down to a fifth under it)
        local MU = package.loaded["music"]
        if MU and MU.dip then pcall(MU.dip, 2.6) end
        local HP = _G.HEALTH
        if HP then HP.star_flash = true end          -- (gHudFlash: the HUD's star counter blinks)
    end
    -- the words fade in (gMenuTextAlpha + 25 a frame), again when the screen is shaded
    if s.alpha < 250 then
        s.alpha = s.alpha + 25
        local a = math.min(1.0, s.alpha / 255.0)
        for _, img in ipairs(u.fade) do pcall(function() img:SetRenderOpacity(a) end) end
    end
    -- CONGRATULATIONS and HI SCORE: sins(timer) * 50 + 200, the timer 0x1000 a frame
    local c = (math.sin(s.frame * 2.0 * math.pi / 16.0) * 50.0 + 200.0) / 255.0
    for _, img in ipairs(u.flash) do pcall(function() img:SetColorAndOpacity({ R = c, G = c, B = c, A = 1.0 }) end) end
    if s.equal and info.hiscore then
        for _, img in ipairs(u.hi) do
            pcall(function()
                img:SetRenderOpacity(1.0)
                img:SetColorAndOpacity({ R = c, G = c, B = c, A = 1.0 })
            end)
        end
    end
    if not s.open and s.frame > OPEN_AFTER and s.equal then
        s.open = true
        s.alpha = 0
        pcall(function() u.shade:SetRenderOpacity(1.0) end)
        for _, img in ipairs(u.fade) do pcall(function() img:SetRenderOpacity(0.0) end) end
    end
    s.frame = s.frame + 1
end

function M.tick(dt)
    local s = st
    if not s then return end
    local here = nil
    pcall(function() here = lib.world():GetAddress() end)
    if here ~= s.world then st = nil; M.active = false; return end
    s.relock = s.relock - dt
    if s.relock <= 0.0 then s.relock = 0.1; lock(true, true) end
    local HP = _G.HEALTH
    if HP then HP.grace = math.max(HP.grace or 0.0, 0.3) end
    s.t = s.t + math.min(dt, 0.15)
    local n = 0
    while s.frame < s.t * 30.0 and n < 5 do
        frame(s)
        n = n + 1
    end
    -- (the tick, every count: one looping sound of them while it counts - fifteen or thirty a second were too many for
    -- the sound players)
    local coins = s.info.coins or 0
    if s.count < coins then hold(coins > 70 and "loop_coin_count_fast" or "loop_coin_count") end
    -- (A goes on - Mario 64 takes Start too, but here Start is STORROR's own menu, which would open over it)
    local go = pad.pressed("ok")
    if s.open and s.frame > GO_AFTER and go then
        sound("star_sound")
        M.close(false)
    end
end

return M
