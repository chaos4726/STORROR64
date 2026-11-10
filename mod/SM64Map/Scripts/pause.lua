-- SM64Map: Mario 64's pause screen, in place of STORROR's pause menu.
--
-- Start (Escape on the keyboard) shades the picture and stops the athlete where he is, as Mario 64's pause does
-- (only him: the music plays on, quieter, as in Mario 64). In a course it shows the course's number and name, the
-- star being played for and MY SCORE (the course's stars and best coin count), and the choices CONTINUE, EXIT
-- COURSE and SET CAMERA ANGLE WITH R; in the castle, PAUSE and a box going through the courses' stars and coin
-- scores (up and down). It is reached from STORROR's pause menu, which is what Start opens (asked 2026-10-14):
-- STORROR's menu opens on its CHARACTER tab, and the tab left of that, where SPOTS was, is the Mario tab, which
-- brings this screen up. (Earlier versions put this screen on Start and had a SWITCH MENU choice to go over to
-- STORROR's; the user had that taken out.) (Asked 2026-10-14: "replace the main storror
-- menu ... one more option to toggle between the two menus ... the game should boot with sm64 menu".)
--
-- Layout: Mario 64's own (game/ingame_menu.c), in its 320x240 screen's pixels, the screen's height filling the
-- window's and its middle kept in the middle, as its widescreen versions do. The words are the game's own
-- lettering (exporter/pausex.py -> textures/pause_t_*.png, data/pause.lua). SET CAMERA ANGLE WITH R has no
-- Lakitu to set here. It used to switch the first-person view; since 2026-10-14 each save file keeps the
-- perspective it was started in ("that save will only work in first person"), so it only buzzes.
local lib = require("lib")
local log = lib.log
local PAD = require("pad")
local M = { open = false, mode = "sm64" }

local OPEN_KEYS = { "Escape", "Gamepad_Special_Right", "Enter" }       -- (and, while it is open, choose: A or Start)
local OK_KEYS = { "Gamepad_FaceButton_Bottom", "SpaceBar" }

local BACK_KEYS = { "Gamepad_FaceButton_Right", "BackSpace" }
local UP_KEYS = { "Gamepad_DPad_Up", "Up", "W" }
local DOWN_KEYS = { "Gamepad_DPad_Down", "Down", "S" }
local LEFT_KEYS = { "Gamepad_DPad_Left", "Left", "A" }
local RIGHT_KEYS = { "Gamepad_DPad_Right", "Right", "D" }
local HUBS = { grounds = true, castle = true, castle2 = true, castle3 = true, courtyard = true }
local SHADE = 110 / 255          -- shade_screen's black
local BOX = 105 / 255            -- the castle box's
local MUSIC_DOWN = 0.4           -- (Mario 64 turns the level's music down while paused)
local HOLD_FIRST, HOLD_NEXT = 10 / 30, 2 / 30      -- handle_menu_scrolling: a held stick moves again after 10 frames, then every 2

local DATA = nil
local function data()
    if DATA == nil then DATA = lib.load_data("data.pause") or false end
    return DATA or nil
end

local function sound(name)
    local SFX = package.loaded["sfx"]
    if SFX then pcall(SFX.play, name) end
end

local function down(pc, keys)
    for _, k in ipairs(keys) do
        local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(k) }) end)
        if ok and v then return true end
    end
    return false
end

-- each list of keys: true on the tick one of them goes down
local held = {}
local function pressed(pc, name, keys)
    local d = down(pc, keys)
    local was = held[name]
    held[name] = d
    return d and not was
end

local function here()
    local a = nil
    pcall(function() a = lib.world():GetAddress() end)
    return a
end

-- ------------------------------------------------------------------ courses and stars
-- The course a scene belongs to (1-15 the courses, 16 on the bonus stages), or nil in the castle.
function M.course_of(scene)
    local d = data()
    if not (d and scene) or HUBS[scene] then return nil end
    return d.courses[scene] or d.courses[(scene:gsub("_%d+$", ""))]
end

-- the course's stars in the file: Mario 64's star flags (bit n = star n + 1) and how many
-- (every course's at once, made again only when the file or its count of stars changes: each course went through all
-- the file's stars - 120 of them, a pattern match each - for every course on the screen, each time it was drawn, some
-- 12 ms a frame: "lag when going from menu to menu", 2026-11-05)
local flags_memo = { file = nil, n = -1, by = {} }
local function course_flags(n)
    local MN = _G.MENU
    if not (MN and MN.stars_got) then return 0, 0 end
    local total = (MN.star_count and MN.star_count()) or 0
    local got = MN.stars_got()
    local nkeys = 0
    if flags_memo.file ~= MN.file or flags_memo.n ~= total or flags_memo.got ~= got then
        local by = {}
        for key in pairs(got) do
            nkeys = nkeys + 1
            local scene, id = tostring(key):match("^(.-):(%d+)$")
            id = tonumber(id)
            local c = scene and id and id <= 6 and M.course_of(scene)
            if c then
                local e = by[c] or { 0, 0 }
                by[c] = e
                local bit = 1 << id
                if e[1] & bit == 0 then e[1], e[2] = e[1] | bit, e[2] + 1 end
            end
        end
        flags_memo.file, flags_memo.n, flags_memo.got, flags_memo.by = MN.file, total, got, by
    end
    local e = flags_memo.by[n]
    if not e then return 0, 0 end
    return e[1], e[2]
end

local function coin_score(n)
    local MN = _G.MENU
    return (MN and MN.coin_score) and MN.coin_score(n) or 0
end

-- The course's star past Mario 64's seven (game.lua G.EXTRA_STARS: Bob-omb Battlefield's race against the ghost): nil
-- for a course without one, else whether the file has it. Shown one more, white, in the pause screens where the race's
-- time is - empty until won, filled after ("in mario pause menu show the 7th star only after collecting it", then "you
-- didnt add a 7th white star in the mario menu", "in the same pause menu where you put the timer add 1 more star for
-- the race", 2026-10-27)
local function extra_star(n)
    local G = package.loaded["game"]
    local MN = _G.MENU
    if not (G and G.EXTRA_STARS and MN and MN.has_star) then return nil end
    for name, x in pairs(G.EXTRA_STARS) do
        if M.course_of(name) == n then
            if MN.has_star(name .. ":" .. tostring(x.star)) then return true end
            -- (not shown at all until every star before it is won - the six and the 100 coins': "should only be able to
            -- see the 7th race star if you completed all stars before it", 2026-10-27)
            local flags = course_flags(n)
            if flags & 0x7F == 0x7F then return false end
            return nil
        end
    end
    return nil
end
local function extra_won(n) return extra_star(n) == true end

-- and its race's best time in the file (race.lua M.best: the file's best run), or nil - under the coin score ("also add
-- the time under the coin score", 2026-10-27)
local function race_best(n)
    local G = package.loaded["game"]
    local RC = package.loaded["race"]
    if not (G and G.EXTRA_STARS and RC and RC.best) then return nil end
    for name in pairs(G.EXTRA_STARS) do
        if M.course_of(name) == n then
            local ok, t = pcall(RC.best, name)
            if ok and t then return t end
        end
    end
    return nil
end

-- ------------------------------------------------------------------ on the screen
local ui = nil
local serial = 0

local function ui_ok()
    if not ui then return false end
    -- (the map first: a widget of a map that has gone may be freed already, and asking it brings the game down)
    local ok, v = pcall(function() return ui.world == lib.world():GetAddress() and ui.widget:IsValid() end)
    return ok and v
end

local function remove_ui()
    if ui_ok() then pcall(function() ui.widget:RemoveFromParent() end) end
    ui = nil
end

-- Slate units to one of Mario 64's pixels: the window's height is its 240
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
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("SM64PauseScreen" .. serial))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("SM64PauseTree" .. serial))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SM64PauseCanvas" .. serial))
    tree.RootWidget = canvas
    return { widget = w, world = world:GetAddress(), wobj = world, canvas = canvas, U = unit(world), n = 0, cls = cls }
end

local function image(b, file, color)
    b.n = b.n + 1
    local img = StaticConstructObject(b.cls("/Script/UMG.Image"), b.canvas, FName("SM64PauseImg" .. serial .. "_" .. b.n))
    local tex = lib.texture(b.wobj, file)
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

local function place(b, slot, x, top)
    pcall(function() slot:SetPosition({ X = (x - 160.0) * b.U, Y = top * b.U }) end)
end

-- a word where print_generic_string(x, y) puts it (y up from the bottom, the letters' 16-pixel cells above it)
local function text(b, key, x, y)
    local wd = data().widths[key]
    if not wd then return nil end
    pic(b, "pause_t_" .. key, x, 240 - y - 16, wd[2], 16)
    return x + wd[1]
end

local function adv(key)
    local wd = data().widths[key]
    return wd and wd[1] or 0
end

-- a number in the menu's lettering, from x
local function number(b, n, x, y)
    for c in tostring(n):gmatch("%d") do x = text(b, "d_" .. c, x, y) or x end
    return x
end

-- the counters' lettering (print_hud_lut_string: 16x16 pictures, 12 pixels apart), top down
local function hud(b, chars, x, top)
    for i = 1, #chars do
        local c = chars:sub(i, i)
        local file = (c == "*") and "hud_star" or (c == "$") and "hud_coin" or (c == "x") and "hud_x" or ("hud_" .. c)
        pic(b, file, x, top, 16, 16)
        x = x + 12
    end
end

-- a time as Mario 64's race clock draws it - TIME 1'23"45 - in the counters' lettering `s` pixels high (theirs 16), from
-- x, top down: its marks set as the HUD's own race timer sets them (health.lua)
local function hud_time(b, secs, x, top, s)
    local k = s / 16.0
    for _, ch in ipairs({ "T", "I", "M", "E" }) do pic(b, "hud_" .. ch, x, top, s, s); x = x + 12.0 * k end
    x = x + 6.0 * k
    local cs = math.floor(secs * 100.0 + 0.5)
    local mins, sec = math.min(99, cs // 6000), (cs // 100) % 60
    for c in tostring(mins):gmatch("%d") do pic(b, "hud_" .. c, x, top, s, s); x = x + 12.0 * k end
    local m = x - 12.0 * k                     -- (the minutes' last place: the rest from it, as the HUD's)
    pic(b, "hud_apos", m + 10.0 * k, top - 7.0 * k, s, s)
    pic(b, "hud_" .. (sec // 10), m + 20.0 * k, top, s, s)
    pic(b, "hud_" .. (sec % 10), m + 32.0 * k, top, s, s)
    pic(b, "hud_quote", m + 45.0 * k, top - 7.0 * k, s, s)
    pic(b, "hud_" .. ((cs // 10) % 10), m + 54.0 * k, top, s, s)
    pic(b, "hud_" .. (cs % 10), m + 66.0 * k, top, s, s)
end

-- how wide hud_time draws a time (its first mark's left edge to its last's right), `s` pixels high
local function hud_time_width(secs, s)
    local k = s / 16.0
    local cs = math.floor(secs * 100.0 + 0.5)
    local nd = #tostring(math.min(99, cs // 6000))
    return (124.0 + 12.0 * nd) * k
end

local function shade(b)
    local _, slot = image(b, "pause_white", { R = 0.0, G = 0.0, B = 0.0, A = SHADE })
    slot:SetAnchors({ Minimum = { X = 0.0, Y = 0.0 }, Maximum = { X = 1.0, Y = 1.0 } })
    slot:SetOffsets({ Left = 0.0, Top = 0.0, Right = 0.0, Bottom = 0.0 })
end

local st = nil          -- what the open screen shows: { kind = "course"|"castle", n, act, sel, line, options }

-- render_pause_my_score_coins + render_pause_course_options
local function draw_course(b)
    local n = st.n
    local flags, count = course_flags(n)
    if extra_won(n) then count = count + 1 end
    if n <= 15 then
        text(b, "course", 63, 157)
        text(b, "num_" .. n, 100, 157)
        text(b, "cname_" .. n, 117, 157)
        -- (the 7th: the extra star's own, filled once won - its bit 6 is the 100 coins' star)
        local won = (st.act == 7 and extra_won(n)) or (st.act <= 6 and flags & (1 << (st.act - 1)) ~= 0)
        text(b, won and "star" or "star_open", 98, 140)
        text(b, "act_" .. n .. "_" .. st.act, 116, 140)
        if count > 0 then
            text(b, "my_score", 62, 121)
            pic(b, "hud_star", 118, 103, 16, 16)
            pic(b, "hud_x", 134, 103, 16, 16)
            hud(b, tostring(count), 150, 103)
        end
        local coins = coin_score(n)
        if coins > 0 then
            pic(b, "hud_coin", 178, 103, 16, 16)
            pic(b, "hud_x", 194, 103, 16, 16)
            hud(b, tostring(coins), 210, 103)
        end
        -- (the race's star - empty until won - and its best time, smaller, under the coin score, above CONTINUE)
        -- (the race's best time alone: its star is the act line's own now, the 7th star picked - a second one here, by
        -- the time, was a star out of nowhere under the score: "random star in menu", "still a random star in menu I
        -- drew an arrow so you could see it", 2026-11-05)
        local e = extra_star(n)
        local best = (e ~= nil) and race_best(n) or nil
        if best then hud_time(b, best, 150, 121, 11) end
    else
        -- (the Bowser run's level and its last fight: FINAL BOWSER, in the same lettering - exporter/pausex.py's, made
        -- for it: "Our Level should be called Final Bowser", 2026-11-03)
        local G = package.loaded["game"]
        local final = G and (G.name == "bowser_3" or (G.gauntlet and G.GAUNTLET and G.GAUNTLET.scenes[G.name or ""]))
        if not (final and text(b, "cname_final", 94, 157)) then text(b, "cname_" .. n, 94, 157) end
    end
    -- the choices, 99 + 10 across and from 93 - 2 down, the pointer 4 left of 99
    for i, o in ipairs(st.options) do text(b, o.key, 109, o.y) end
    local _, slot = pic(b, "pause_pointer", 95, 0, 8, 16)
    ui.pointer = slot
end

local function pointer_course(b)
    local py = 91 - 15 * (st.sel - 1)
    place(b, ui.pointer, 95, 240 - py - 16)
end

-- render_pause_castle_course_stars: the stars it has, empty ones where one is missing, one empty one more
local function star_line(flags, count)
    local out = {}
    if flags & (1 << 6) ~= 0 then count = count - 1 end
    local has, nxt = 0, 0
    while has ~= count and nxt < 7 do
        if flags & (1 << nxt) ~= 0 then out[#out + 1] = "star"; has = has + 1 else out[#out + 1] = "star_open" end
        nxt = nxt + 1
    end
    if count == nxt and count ~= 6 then out[#out + 1] = "star_open" end
    return out
end

-- print_hud_pause_colorful_str + render_pause_castle_menu_box + render_pause_castle_main_strings
local function draw_castle(b)
    hud(b, "PAUSE", 123, 81)
    local best = st.line <= 15 and race_best(st.line) or nil
    local tall = best and 16 or 0               -- (room for the race's time under the coins)
    pic(b, "pause_white", 82, 129, 156, 64 + tall, { R = 0.0, G = 0.0, B = 0.0, A = BOX })
    pic(b, "pause_arrow_up", 150, 117, 16, 8)
    pic(b, "pause_arrow_down", 151, 198 + tall, 16, 8)
    local x, y = 104, 60
    if st.line <= 15 then
        local flags, count = course_flags(st.line)
        if flags & (1 << 6) ~= 0 then text(b, "star", x + 89, y - 5) end
        local sx = x + 14
        for _, key in ipairs(star_line(flags, count)) do sx = (text(b, key, sx, y + 13) or sx) + data().space end
        -- (and its race's star, one more after the rest: empty until won)
        local e = extra_star(st.line)
        if e ~= nil then text(b, e and "star" or "star_open", sx, y + 13) end
        text(b, "coin_x", x + 34, y - 5)
        number(b, coin_score(st.line), x + 54, y - 5)
        -- (the race's time centred in the box - it stood off to the right: "center the time a bit more", 2026-11-01)
        if best then hud_time(b, best, 160.0 - hud_time_width(best, 12) / 2.0, 240 - (y - 5) + 1, 12) end
        text(b, "cfull_" .. st.line, x - 9, y + 30)
    else
        local total = 0
        for c = 16, 24 do total = total + select(2, course_flags(c)) end
        -- (and the castle's own: the Toads' and Mips' stars, "castle:<n>" - save_file_get_total_star_count's
        -- castle secret stars)
        local MN = _G.MENU
        for key in pairs((MN and MN.stars_got and MN.stars_got()) or {}) do
            if tostring(key):match("^castle:%d+$") then total = total + 1 end
        end
        text(b, "star_x", x + 40, y + 13)
        number(b, total, x + 60, y + 13)
        text(b, "secret", x - 9, y + 30)
    end
    ui.pointer = nil
end

local function pointer_castle(b) end

-- STORROR's tab row over Mario 64's screen, where STORROR's menu has it, MARIO 64 lit: the screen shown as the MARIO 64
-- tab's page, not as a menu of its own ("I should still be able to see the settings and all", 2026-11-01). Its names,
-- their look and its place are as msettings.lua last saw STORROR's (_G.SM64_TABROW); the same names, the same gaps,
-- scaled to the same box. LT/RT (Z/C) step to the tabs beside it (M.tick).
local function tab_row(b)
    local R = _G.SM64_TABROW
    if not (R and R.names and R.textcls and R.w and R.w > 1.0) then return end
    local TB = R.textcls
    -- (STORROR's layout is 1920x1080, scaled to fit the window and centred: the same here)
    local x, y, w, h = R.x, R.y, R.w, R.h
    if R.design then
        local WLL = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        local VW, VH = 1920.0, 1080.0
        pcall(function()
            local size = WLL:GetViewportSize(b.wobj)
            local scale = WLL:GetViewportScale(b.wobj)
            if size and scale and scale > 0 then VW, VH = size.X / scale, size.Y / scale end
        end)
        local k = math.min(VW / 1920.0, VH / 1080.0)
        local ox, oy = (VW - 1920.0 * k) / 2.0, (VH - 1080.0 * k) / 2.0
        x, y, w, h = ox + R.x * k, oy + R.y * k, R.w * k, R.h * k
    end
    local box = StaticConstructObject(b.cls("/Script/UMG.SizeBox"), b.canvas, FName("SM64PauseTabBox" .. serial))
    local slot = b.canvas:AddChildToCanvas(box)
    slot:SetAnchors({ Minimum = { X = 0.0, Y = 0.0 }, Maximum = { X = 0.0, Y = 0.0 } })
    slot:SetAlignment({ X = 0.0, Y = 0.0 })
    slot:SetPosition({ X = x, Y = y })
    slot:SetSize({ X = w, Y = h })
    local sbox = StaticConstructObject(b.cls("/Script/UMG.ScaleBox"), box, FName("SM64PauseTabScale" .. serial))
    pcall(function() sbox:SetStretch(2) end)                                   -- (scale to fit)
    box:AddChild(sbox)
    local hb = StaticConstructObject(b.cls("/Script/UMG.HorizontalBox"), sbox, FName("SM64PauseTabRow" .. serial))
    sbox:AddChild(hb)
    local on = R.on_col or { R = 0.9, G = 1.0, B = 0.15, A = 1.0 }
    local off = { R = 1.0, G = 1.0, B = 1.0, A = 0.75 }
    for i, e in ipairs(R.names) do
        local t = StaticConstructObject(TB, hb, FName("SM64PauseTabName" .. serial .. "_" .. i))
        if R.style then pcall(function() t:SetStyle(R.style) end) end
        pcall(function() t:SetText(FText(e.title)) end)
        pcall(function() t:SetColorAndOpacity({ SpecifiedColor = (e.id == "SPOTS") and on or off, ColorUseRule = 0 }) end)
        b.tabnames = b.tabnames or {}
        b.tabnames[#b.tabnames + 1] = { w = t, col = (e.id == "SPOTS") and on or off }
        local hs = hb:AddChildToHorizontalBox(t)
        pcall(function() hs:SetPadding({ Left = R.gap or 18.0, Top = 0.0, Right = R.gap or 18.0, Bottom = 0.0 }) end)
        pcall(function() hs:SetVerticalAlignment(2) end)
    end
end

-- Mario 64's screen drawn in STORROR's SPOTS tab (emb): under STORROR's menu, so that its tab row stays over it
local emb = false
local EMB_Z = -5
local function render()
    local old = ui
    local b = begin()
    if not b then return end
    ui = { widget = b.widget, world = b.world, b = b }
    local ok, err = pcall(function()
        shade(b)
        if st.kind == "course" then draw_course(b); pointer_course(b) else draw_castle(b); pointer_castle(b) end
    end)
    if not ok then log("pause screen: %s", tostring(err)) end
    if not emb then
        local okt, errt = pcall(tab_row, b)
        if not okt then log("pause screen: tab row: %s", tostring(errt)) end
    end
    b.widget:AddToViewport(emb and EMB_Z or 9500)
    -- (the tab row's colours again once it is on the screen: STORROR's text look, put on as it is built, set them back -
    -- MARIO 64 was not lit: "the setting isnt highlighted yellow", 2026-11-01)
    for _, e in ipairs(b.tabnames or {}) do
        pcall(function() e.w:SetColorAndOpacity({ SpecifiedColor = e.col, ColorUseRule = 0 }) end)
    end
    if old then
        local o = ui
        ui = old
        remove_ui()
        ui = o
    end
end

local function move_pointer()
    if not ui_ok() then return end
    if st.kind == "course" then pointer_course(ui.b) else pointer_castle(ui.b) end
end

-- ------------------------------------------------------------------ stopping the athlete
local frozen = nil

-- STORROR's own parts that take buttons (the tool wheel on the d-pad, emotes, drone, camera, tools...) listen
-- whatever the athlete's input is doing: each is switched off under a lock of the mod's own while the screen is
-- up (2026-10-14: "when using dpad the tool wheel shows up").
local LOCK = "SM64Pause"
local function lock_parts(pawn, on)
    if on then
        local parts = {}
        local ok, cs = pcall(FindAllOf, "HITSActorComponentWithInput")
        local mine = pawn:GetAddress()
        for i = 1, (ok and cs and #cs or 0) do
            pcall(function()
                local c = cs[i]
                if c:IsValid() and c:GetOwner():GetAddress() == mine then
                    c:EnableComponentInput(FName(LOCK), false)
                    parts[#parts + 1] = c
                end
            end)
        end
        return parts
    end
    for _, c in ipairs(frozen and frozen.parts or {}) do
        pcall(function() if c:IsValid() then c:EnableComponentInput(FName(LOCK), true) end end)
    end
end

local function relock()
    if not (frozen and frozen.world == here()) then return end
    for _, c in ipairs(frozen.parts or {}) do
        pcall(function() if c:IsValid() then c:EnableComponentInput(FName(LOCK), false) end end)
    end
end

-- STORROR's action wheel (its emotes on D-pad right, its tools) is not stopped by that lock (2026-10-14: "the
-- dpad thing is still happening"). It is opened through ActionWheelComponent:ShowActionWheelCallback(bShow):
-- while the screen is up a hook turns a show into a hide, and if the wheel is open all the same
-- (ActionWheelWidget.bWheelOpened) it is shut through the same function.
pcall(function()
    if _G.SM64_PAUSE_WHEEL_HOOK then return end
    _G.SM64_PAUSE_WHEEL_HOOK = true
    RegisterHook("/Script/SPP.ActionWheelComponent:ShowActionWheelCallback", function(_, show)
        if not M.open then return end
        local was = nil
        pcall(function() was = show:get() end)
        if was then
            pcall(function() show:set(false) end)
            log("STORROR's action wheel kept shut under the pause screen")
        end
    end)
end)

local function shut_wheel()
    if not (frozen and frozen.world == here()) then return end
    for _, c in ipairs(frozen.parts or {}) do
        pcall(function()
            if c:IsValid() and c:GetClass():GetFName():ToString() == "ActionWheelComponent" then
                local w = c.ActionWheelWidget
                if w and w:IsValid() and w.bWheelOpened then
                    c:ShowActionWheelCallback(false)
                    log("STORROR's action wheel shut under the pause screen")
                end
            end
        end)
    end
end

-- His body as STORROR's ragdoll has it - simulated - held still too: the time dilation in freeze holds his moves, not
-- the physics, and the body went on falling under the menu - "when players ragdolled and hits pause the body keeps
-- falling", 2026-11-02. Its bodies put to sleep (kept so each frame while it is up - M.tick), their speed kept for after.
local function body_hold(pawn)
    local sim = false
    pcall(function() sim = pawn.Mesh:IsSimulatingPhysics(FName("None")) end)
    if not sim then
        local R = package.loaded["ragdoll"]
        sim = (R and R.limp and R.limp()) or false
    end
    if not sim then return nil end
    local v = nil
    pcall(function() local q = pawn.Mesh:GetPhysicsLinearVelocity(FName("None")); v = { X = q.X, Y = q.Y, Z = q.Z } end)
    pcall(function() pawn.Mesh:PutAllRigidBodiesToSleep() end)
    log("pause: his ragdolled body held still")
    return { v = v }
end
local function body_go(pawn, h)
    pcall(function() pawn.Mesh:WakeAllRigidBodies() end)
    if h.v then pcall(function() pawn.Mesh:SetAllPhysicsLinearVelocity(h.v, false) end) end
end

-- In multiplayer - in a Steam lobby, mp.lua - the game never stands still for a pause: Mario 64's pause screen and
-- STORROR's menu come up over it and take his keys, so he stands where he is, but his body, the creatures, the platforms
-- and the music all go on, as the other players' games do ("for multiplayer mode make sure when you pause the game
-- continues in the backround no matter what", 2026-11-03). M.halted: paused, and the game held for it.
function M.online()
    local MP = package.loaded["mp"]
    local ok, on = pcall(function() return MP and MP.in_lobby and MP.in_lobby() end)
    if ok and on == true then return true end
    -- (and while the FIRST PERSON tab is the one shown - fpextra.lua's settings, seen live on the game behind as they
    -- change: "the game has to unpause when on the first person tab because you cant see changes live", 2026-11-10.
    -- His keys stay the menu's, as online; another tab and the game is held again - M.tick)
    local FPM = _G.FP_MENU
    return FPM ~= nil and FPM.active == true and FPM.tab_open == true
end
function M.halted() return (M.open == true or (M.menu_up ~= nil and M.menu_up() == true)) and not M.online() end
local function freeze(on)
    local pc = lib.controller()
    if on then
        local pawn = lib.pawn()
        if not (pawn and pc) then return end
        frozen = { pawn = pawn, world = here() }
        -- (online: his keys to the menus alone, nothing held)
        if M.online() then
            frozen.online = true
            pcall(function() pawn:DisableInput(pc) end)
            log("pause: online - the game goes on under it")
            return
        end
        pcall(function() pawn.CustomTimeDilation = 0.0 end)
        pcall(function() pawn:DisableInput(pc) end)
        frozen.parts = lock_parts(pawn, true)
        frozen.sim = body_hold(pawn)
        local MUSIC = package.loaded["music"]
        if MUSIC and MUSIC.set_volume then frozen.volume = MUSIC.volume; pcall(MUSIC.set_volume, MUSIC.volume * MUSIC_DOWN) end
    elseif frozen and frozen.online then
        if frozen.world == here() then pcall(function() frozen.pawn:EnableInput(pc) end) end
        frozen = nil
    elseif frozen then
        if frozen.world == here() then
            pcall(function() frozen.pawn.CustomTimeDilation = 1.0 end)
            pcall(function() frozen.pawn:EnableInput(pc) end)
            lock_parts(frozen.pawn, false)
            if frozen.sim then body_go(frozen.pawn, frozen.sim) end
        end
        local MUSIC = package.loaded["music"]
        if MUSIC and MUSIC.set_volume and frozen.volume then pcall(MUSIC.set_volume, frozen.volume) end
        frozen = nil
    end
end

-- ------------------------------------------------------------------ STORROR's own pause menu
-- Start is STORROR's pause button too. While Mario 64's is the one in use, STORROR's menu is shut again the
-- moment it shows (it is a CommonUI "presenter"; shutting it gives the controls and the view back), and its
-- opening and closing sounds are taken out of it.
local PRESENTER = "/SPP/UI/PauseMenu/MenuPresenterBP.MenuPresenterBP_C"
local PRESENTER_CDO = "/SPP/UI/PauseMenu/MenuPresenterBP.Default__MenuPresenterBP_C"
local quiet = nil       -- STORROR's own sounds, kept while they are taken out

-- (The sounds are kept by their asset paths, never as objects: once the menu no longer holds them the engine
-- frees them at its next clean-up, and putting a freed sound back crashed the game as STORROR's menu opened
-- and played it, 2026-10-14. They are loaded again from their paths when they go back.)
local SOUND_PATHS = { open = "/SPP/Sounds/SFX/UI/PresentPauseMenuSound.PresentPauseMenuSound",
                      close = "/SPP/Sounds/SFX/UI/ClosePauseMenuSound.ClosePauseMenuSound" }

local function path_of(o)
    local p = nil
    pcall(function() if o and o:IsValid() then p = o:GetFullName():match("^%S+%s+(.+)$") end end)
    return p
end

local function load_sound(path)
    if not path then return nil end
    local o = StaticFindObject(path)
    if o and o:IsValid() then return o end
    local ok, loaded = pcall(LoadAsset, path)
    if ok and loaded and loaded:IsValid() then return loaded end
    return nil
end

local function storror_sounds(on)
    local cdo = StaticFindObject(PRESENTER_CDO)
    if not (cdo and cdo:IsValid()) then return end
    if not on and not quiet then
        quiet = { open = path_of(cdo.OpenMenuSound) or SOUND_PATHS.open, close = path_of(cdo.CloseMenuSound) or SOUND_PATHS.close }
        pcall(function() cdo.OpenMenuSound = nil; cdo.CloseMenuSound = nil end)
    elseif on and quiet then
        local open, close = load_sound(quiet.open), load_sound(quiet.close)
        pcall(function() cdo.OpenMenuSound = open; cdo.CloseMenuSound = close end)
        log("STORROR's menu sounds back (%s, %s)", tostring(open ~= nil), tostring(close ~= nil))
        quiet = nil
    end
end

-- (STORROR's menu made unseen from the start - its template's opacity - while Start is blocked: opened by the press and
-- shut a moment later, it flashed on the screen, its open sound heard - "pause sound and something flashing on screen
-- when jumping and pausing", 2026-11-02. Back as Start is free again: M.tick)
local cdo_hidden = false
local function storror_unseen(on)
    if on == cdo_hidden then return end
    local cdo = StaticFindObject(PRESENTER_CDO)
    if not (cdo and cdo:IsValid()) then return end
    pcall(function() cdo.RenderOpacity = on and 0.0 or 1.0 end)
    cdo_hidden = on
end

local unveil = nil                     -- (STORROR's menu kept unseen as it opens: { t0, on } - M.tick)
-- STORROR's menu stack is the player controller's only while its menu is up: a cheap sign of the menu, read every tick
local function menu_stack_up()
    local up = false
    pcall(function()
        local h = lib.controller().MenuStack
        up = (h ~= nil) and h:IsValid()
    end)
    return up
end
local function storror_menus()
    local out = {}
    local ok, ws = pcall(FindAllOf, "MenuPresenterBP_C")
    if not (ok and ws) then return out end
    for i = 1, #ws do
        pcall(function()
            local w = ws[i]
            if w:IsValid() and w:GetFullName():find("Transient", 1, true) and w:IsActivated() then out[#out + 1] = w end
        end)
    end
    return out
end

local function controls_to_game()
    local pc = lib.controller()
    if not pc then return end
    pcall(function() StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):SetInputMode_GameOnly(pc, false) end)
    pcall(function() pc.bShowMouseCursor = false end)
end

local function shut_storror()
    local n = 0
    for _, w in ipairs(storror_menus()) do
        -- (out of sight first: shut, it fades out over about a second, which showed it under Mario 64's screen,
        -- 2026-10-14 "when entering the pause menu the storror menu shows for a second")
        pcall(function() w:SetRenderOpacity(0.0) end)
        pcall(function() w:SetVisibility(1) end)                       -- (collapsed)
        pcall(function()
            local bg = w.Background
            if bg and bg:IsValid() then bg:SetRenderOpacity(0.0); bg:SetVisibility(1) end
        end)
        if pcall(function() w:DeactivateWidget() end) then n = n + 1 end
    end
    if n > 0 then controls_to_game() end
    return n
end

-- Open STORROR's pause menu, as its Start does: the presenter pushed on the player controller's menu stack.
local function open_storror()
    local pc = lib.controller()
    if not pc then return false end
    local ok, err = pcall(function()
        local holder = nil
        pcall(function() holder = pc.MenuStack end)
        -- (the player controller's, else the game's own: once, coming back from Mario 64's screen, the controller had
        -- none - "no menu stack", 2026-11-01)
        if not (holder and pcall(function() return holder:IsValid() end) and holder:IsValid()) then
            -- (STORROR's menu stack is the controller's only while its menu is up: shut, the stack is taken off the
            -- screen and the controller lets it go - pushed on then, the menu never showed, 2026-11-01. As its Start
            -- does: the stack - its last - back on the screen, the controller's again, and the menu pushed on it)
            holder = nil
            for _, w in ipairs(FindAllOf("MenuStackBP_C") or {}) do
                if w:IsValid() and not w:GetFName():ToString():find("^Default__") then holder = w end
            end
            if holder then
                if not holder:IsInViewport() then holder:AddToViewport(0) end
                pcall(function() pc.MenuStack = holder end)
            end
        end
        if not (holder and holder:IsValid()) then error("no menu stack") end
        local stack = holder.MenuStack
        if not (stack and stack:IsValid()) then error("no inner stack") end
        local cls = StaticFindObject(PRESENTER)
        if not (cls and cls:IsValid()) then error("no presenter class") end
        stack:BP_AddWidget(cls)
    end)
    if not ok then log("could not open STORROR's pause menu: %s", tostring(err)) end
    return ok
end

-- ------------------------------------------------------------------ SWITCH MENU in STORROR's menu
-- STORROR's top tabs (ADVENTURE, SPOTS, CHARACTER, ONLINE, CONTROLS, SETTINGS) come from the Tabs list of the tab
-- bar in its menu's template (MenuPresenterBP's MenuTabBar: Name, Title, ButtonClass, ContentClass, Icon). SPOTS
-- (STORROR's map and travel, of no use in the mod) gets the title SWITCH MENU and Mario's head as its icon: in the
-- template, for menus built from now on, and on the tab buttons of menus already built (TitleBarButtonIcon_C:
-- ButtonTextLabel and Icon). Whether the player is on it is asked of the tab list itself (GetSelectedTabId):
-- an earlier SWITCH MENU row on the system page could not work, as A on it reached nothing the mod could see.
local TAB_ID = "SPOTS"
local TAB_TITLE = "MARIO 64"
-- The Mario tab taken out (2026-11-01: "lets just try this from the beginning mario 64 menu used to be something
-- different locations or something like that? switch it back to how it originally was and remove the mario 64 menu"):
-- STORROR's SPOTS tab is its own again - its name, its icon, its travel page - and nothing on it puts up Mario 64's pause
-- screen. MARIO_TAB true brings the Mario tab back as it was.
local MARIO_TAB = false
-- Mario 64's pause screen in SPOTS, in STORROR's menu (embed_open; msettings.lua SPOTS_M64)
local M64_IN_SPOTS = true
local TAB_TEMPLATE = "/SPP/UI/PauseMenu/MenuPresenterBP.MenuPresenterBP_C:WidgetTree.MenuTabBar"
local TAB_DWELL = 0.25               -- seconds on the tab before it switches (going past it does not; 0.5 showed STORROR's
                                     -- page for it too long, and LT/RT bring the menu back now)
local HIDDEN_TAB = "ADVENTURE"       -- taken out of STORROR's menu on request
-- (and its ONLINE tab, multiplayer - hidden, not taken away: "next we have to hide the multiplayer option dont remove
-- it just hide it", 2026-10-18)
local ONLINE_TAB = "ONLINE"
-- (shown again, with the mod's own multiplayer screen on it - peer to peer through Steam: mpmenu.lua, "Inside STORROR's
-- ONLINE tab", 2026-11-01. MP_ONLINE false hides it as before.)
local MP_ONLINE = true
local HIDE_TABS = MP_ONLINE and { HIDDEN_TAB } or { HIDDEN_TAB, ONLINE_TAB }
local tab_icon = nil                 -- { obj, name }: made once; STORROR's template keeps it for the session
local template_done = false
local relabelled = {}                -- tab bars already relabelled, by name
local tab_seen, tab_since, gone_since = nil, nil, nil

local function icon()
    if tab_icon then
        local ok, same = pcall(function() return tab_icon.obj:GetFName():ToString() == tab_icon.name end)
        if ok and same then return tab_icon.obj end
    end
    local world = lib.world()
    if not world then return nil end
    local tex = nil
    pcall(function()
        tex = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary"):ImportFileAsTexture2D(world, lib.MOD_DIR .. "textures\\pause_tab_icon.png")
    end)
    if not (tex and tex:IsValid()) then return nil end
    tab_icon = { obj = tex, name = tex:GetFName():ToString() }
    return tex
end

-- the SPOTS entry of a tab bar's Tabs list: title and icon
local function relabel_entry(bar)
    local done = false
    pcall(function()
        local tabs = bar.Tabs
        for i = 1, #tabs do
            local e = tabs[i]
            if e.Name:ToString() == TAB_ID then
                e.Title = FText(TAB_TITLE)
                local tex = icon()
                if tex then e.Icon = tex end
                done = true
            end
        end
    end)
    return done
end

-- the template, once, before STORROR builds its menu (called every tick, from the menus too, until it is done)
function M.prepare()
    if template_done then return end
    local t = StaticFindObject(TAB_TEMPLATE)
    if not (t and t:IsValid()) then return end
    template_done = true
    if MARIO_TAB then
        log("STORROR's menu template: %s tab %s", TAB_ID, relabel_entry(t) and ("is " .. TAB_TITLE) or "not found")
    end
    -- (and the menu opens on the tab right of the Mario tab: its own InitialTab was CONTROLS)
    pcall(function()
        local cdo = StaticFindObject("/SPP/UI/PauseMenu/MenuPresenterBP.Default__MenuPresenterBP_C")
        if cdo and cdo:IsValid() then cdo.InitialTab = FName("Character") end
    end)
end

-- a tab bar of a menu already built: its list entry, and its tab button's label and icon
local function relabel_bar(bar)
    local key = nil
    pcall(function() key = bar:GetFName():ToString() .. "@" .. tostring(bar:GetAddress()) end)
    if not key or relabelled[key] then return end
    relabelled[key] = true
    if MARIO_TAB then relabel_entry(bar) end
    pcall(function()
        if not MARIO_TAB then return end
        local btn = bar:GetTabButtonBaseByID(FName(TAB_ID))
        if not (btn and btn:IsValid()) then return end
        pcall(function() btn["Button Text"] = TAB_TITLE end)
        pcall(function() btn.ButtonTextLabel:SetText(FText(TAB_TITLE)) end)
        local tex = icon()
        if tex then pcall(function() btn.Icon:SetBrushFromTexture(tex, false) end) end
    end)
    for _, tid in ipairs(HIDE_TABS) do
        pcall(function()
            bar:SetTabVisibility(FName(tid), 1)                        -- (collapsed)
            bar:SetTabEnabled(FName(tid), false)
        end)
    end
    log("STORROR's menu: %s, %s hidden (%s)", MARIO_TAB and ("SPOTS tab relabelled " .. TAB_TITLE) or "SPOTS its own",
        table.concat(HIDE_TABS, " and "), key)
end

-- the hidden tab, hidden still (every look while the menu is up: STORROR can show it again)
local function keep_hidden(bar)
    for _, tid in ipairs(HIDE_TABS) do
        pcall(function()
            local btn = bar:GetTabButtonBaseByID(FName(tid))
            if btn and btn:IsValid() and btn:IsVisible() then
                bar:SetTabVisibility(FName(tid), 1)                    -- (collapsed)
                bar:SetTabEnabled(FName(tid), false)
                log("STORROR's menu: %s hidden again", tid)
            end
        end)
    end
end

-- STORROR's menu backdrop (the dark, scratched, darkened picture behind its tabs) is a post-process volume it puts
-- in the level, HITSBackgroudActorBP (sic), with a material its menu animates. Switched off while the menu is up,
-- so that the game shows behind it (asked 2026-10-14: "remove the background so you can see the game" - "on the
-- storror menu"). Only the current map's: an actor of a map that has gone is not touched.
-- (and the CHARACTER screen's: its preview figure, PlayerMannequinBP, stands in a set built into it - a concrete
-- stairwell, weeds, graffiti decals, a spray can, a backdrop mesh, a cone - all hidden, the figure and its spotlights
-- kept, the level's sky behind it: "fix charater screen backround", 2026-10-18)
local SET_PIECES = { "/Script/Engine.StaticMeshComponent", "/Script/Engine.DecalComponent" }
local function clear_figure_set()
    local ok, list = pcall(FindAllOf, "PlayerMannequinBP_C")
    if not (ok and list) then return end
    local addr = here()
    for i = 1, #list do
        pcall(function()
            local a = list[i]
            if a:GetOuter():GetOuter():GetAddress() ~= addr then return end
            for _, path in ipairs(SET_PIECES) do
                for _, c in ipairs(a:K2_GetComponentsByClass(StaticFindObject(path))) do
                    local o = c:get()
                    if o:IsVisible() then o:SetVisibility(false, false) end
                end
            end
        end)
    end
end

-- (and the figure brought to where he stands, its camera with it - a part of it - so that the level is behind it, not
-- the sky 300 m over the map's middle: "the backround still isnt invisabe", 2026-10-18. He, and what rides on him -
-- the mod's look and copy of him, STORROR's flashlight; not its camera - hidden meanwhile; all put back after.)
local fig = nil                       -- { obj, addr, world, loc, rot, hid = { actors hidden } }
local function figure_back()
    local f = fig
    fig = nil
    if not f or f.world ~= here() then return end
    pcall(function() if f.obj:IsValid() then f.obj:K2_SetActorLocationAndRotation(f.loc, f.rot, false, {}, true) end end)
    for _, a in ipairs(f.hid) do pcall(function() if a:IsValid() then a:SetActorHiddenInGame(false) end end) end
    for _, c in ipairs(f.parts or {}) do pcall(function() if c:IsValid() then c:SetVisibility(true, false) end end) end
    -- (and he put back where he stood as it came up, if anything moved him meanwhile: the game stands still under the
    -- menu, so nothing of his own did. Up in a race's countdown it took him 61 cm on, past the ghost beside him - "the
    -- ghost is further back then the player is on start", 2026-10-30.)
    if f.home then
        pcall(function()
            local pawn = lib.pawn()
            if not (pawn and pawn:IsValid()) then return end
            local l = pawn:K2_GetActorLocation()
            local d = math.sqrt((l.X - f.home.X) ^ 2 + (l.Y - f.home.Y) ^ 2 + (l.Z - f.home.Z) ^ 2)
            if d > 15.0 then
                pawn:K2_TeleportTo(f.home, f.home_rot)
                pawn.CharacterMovement.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
                local G = package.loaded["game"]
                if G and G.reset_cloth then pcall(G.reset_cloth, pawn) end
                log("CHARACTER screen: he had been moved %.0f cm while it was up - put back", d)
            end
        end)
    end
    log("CHARACTER screen: its figure back, he shown again")
end
-- The game seen live behind every tab ("when switching through the menus can you make the backround always be live, I
-- noticed when switching to charater it changes the camera angle and spawns another mario", 2026-11-01): STORROR's
-- CHARACTER screen puts the view on its figure's camera - the view put back on him at once (each tick, live_view), and
-- the figure, with what rides on it, hidden. He stays as he stands; nothing is moved.
local LIVE_BG = true
-- (STORROR's figure stood in his place on CHARACTER: off - he is shown himself, held as he is till a pick, charhold.lua;
-- the figure, far off under the map, hidden)
local FIG_STANDIN = false
local live_fig = nil                  -- (STORROR's figure the CHARACTER screen last put the view on)
local figure_place                    -- (below: the figure stood where he is, he hidden)
local function live_view()
    local pc, pawn = lib.controller(), lib.pawn()
    if not (pc and pawn) then return end
    local vt = nil
    pcall(function() vt = pc:GetViewTarget() end)
    if vt and pcall(function() return vt:IsValid() end) and vt:IsValid()
        and vt:GetClass():GetFName():ToString() == "PlayerMannequinBP_C" then
        -- (the view back on him: the camera as it was, the game behind)
        pc:SetViewTargetWithBlend(pawn, 0.0, 0, 0.0, false)
        if not (live_fig and live_fig:IsValid() and live_fig:GetAddress() == vt:GetAddress()) then
            live_fig = vt
            log("CHARACTER screen: the view kept on him")
        end
    end
    -- (on CHARACTER: STORROR dresses him as the face and clothes picked out - its figure, wearing them and the Mario
    -- look, stood where he stands, as he faces, and he hidden: one of him, in his place. Off it, all put back.)
    -- (M.tab: storror_open and tab_seen are declared further down - here they would be globals, always nil)
    local on_char = M.tab and M.tab() == "Character"
    if FIG_STANDIN and on_char and live_fig and live_fig:IsValid() then
        pcall(figure_place, live_fig, pawn)
    elseif fig then
        figure_back()
    end
    if not FIG_STANDIN and on_char and live_fig and live_fig:IsValid() then
        pcall(function()
            if not live_fig.bHidden then live_fig:SetActorHiddenInGame(true) end
            local list = {}
            live_fig:GetAttachedActors(list, true, true)
            for i = 1, #list do
                local a = list[i]
                pcall(function() if a.get then a = a:get() end end)
                pcall(function() if a:IsValid() and not a.bHidden then a:SetActorHiddenInGame(true) end end)
            end
        end)
    end
end

figure_place = function(vt, pawn)
    if vt.bHidden then vt:SetActorHiddenInGame(false) end
    local addr = vt:GetAddress()
    if fig and fig.addr ~= addr then figure_back() end
    if not fig then
        fig = { obj = vt, addr = addr, world = here(), loc = vt:K2_GetActorLocation(), rot = vt:K2_GetActorRotation(), hid = {} }
        -- (where he stands as it comes up: the figure kept there, not brought after him each frame, and he put back
        -- there as it goes - figure_back)
        pcall(function()
            local l0, r0 = pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation()
            fig.home, fig.home_rot = { X = l0.X, Y = l0.Y, Z = l0.Z }, { Pitch = 0.0, Yaw = r0.Yaw, Roll = 0.0 }
        end)
        local function hide(a)
            pcall(function() if not a.bHidden then a:SetActorHiddenInGame(true); fig.hid[#fig.hid + 1] = a end end)
        end
        hide(pawn)
        local list = {}
        pcall(function() pawn:GetAttachedActors(list, true, true) end)
        for i = 1, #list do
            local a = list[i]
            pcall(function() if a.get then a = a:get() end end)
            local cn = ""
            pcall(function() cn = a:GetClass():GetFName():ToString() end)
            if cn ~= "" and not cn:find("Camera") then hide(a) end
        end
        log("CHARACTER screen: its figure brought to him, %d of his hidden", #fig.hid)
    end
    -- (STORROR shows him again as it changes the face, and his parts draw on though he is hidden - the game held still:
    -- each of his parts that shows hidden itself, and kept to be shown again)
    pcall(function()
        if not pawn.bHidden then pawn:SetActorHiddenInGame(true) end
        fig.parts = fig.parts or {}
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.PrimitiveComponent"))) do
            local o = c:get()
            if o:IsVisible() then o:SetVisibility(false, false); fig.parts[#fig.parts + 1] = o end
        end
    end)
    local G = package.loaded["game"]
    local l, r = fig.home or pawn:K2_GetActorLocation(), fig.home_rot or pawn:K2_GetActorRotation()
    local to = { X = l.X, Y = l.Y, Z = l.Z - ((G and G.half) or 90.0) }
    -- (held where he stands and as he faces, every tick: STORROR turns its figure round on its CHARACTER screen, and in
    -- his place it spun - "remove whatever function you just added to spin the charater", 2026-11-01)
    local cur = vt:K2_GetActorLocation()
    local cr = vt:K2_GetActorRotation()
    local dyaw = math.abs(((cr.Yaw - r.Yaw) + 180.0) % 360.0 - 180.0)
    if (cur.X - to.X) ^ 2 + (cur.Y - to.Y) ^ 2 + (cur.Z - to.Z) ^ 2 > 25.0 or dyaw > 0.5 or math.abs(cr.Pitch) > 0.5 or math.abs(cr.Roll) > 0.5 then
        pcall(function() vt:K2_SetActorLocationAndRotation(to, { Pitch = 0.0, Yaw = r.Yaw, Roll = 0.0 }, false, {}, true) end)
    end
end
local function figure_here()
    if LIVE_BG then pcall(live_view); return end
    local pc, pawn = lib.controller(), lib.pawn()
    if not (pc and pawn) then return end
    local vt, is_fig = nil, false
    pcall(function() vt = pc:GetViewTarget(); is_fig = vt:GetClass():GetFName():ToString() == "PlayerMannequinBP_C" end)
    if not is_fig then if fig then figure_back() end; return end
    figure_place(vt, pawn)
end

local function clear_backdrop()
    pcall(clear_figure_set)
    pcall(figure_here)
    local ok, list = pcall(FindAllOf, "HITSBackgroudActorBP_C")
    if not (ok and list) then return end
    local addr = here()
    for i = 1, #list do
        pcall(function()
            local a = list[i]
            local world = a:GetOuter():GetOuter()                  -- (actor -> level -> world)
            if world:GetAddress() ~= addr then return end
            if a.bEnabled then a.bEnabled = false end
            if a.BlendWeight ~= 0.0 then a.BlendWeight = 0.0 end
        end)
    end
end

-- the tab selected in the open STORROR menu (and its tab bar), or nil
local function current_tab()
    for _, w in ipairs(storror_menus()) do
        local bar, id = nil, nil
        pcall(function()
            bar = w.MenuTabBar
            if bar and bar:IsValid() then id = bar:GetSelectedTabId():ToString() end
        end)
        if id then return id, bar end
    end
    return nil, nil
end

-- ------------------------------------------------------------------ opening and choosing
local look_t, burst, storror_open, closed_t = 0.0, 0.0, false, nil   -- (when to look for STORROR's menu: M.tick)
local menu_hold = false         -- the game held still because STORROR's menu is up (game.lua stops while it is)
function M.menu_up() return menu_hold end

-- The star being played for, as Mario 64's pause shows it: the one picked at the star select (game.lua G.course_act) -
-- its 7th the course's extra star, the race against its ghost (G.EXTRA_STARS) - in this course; else nil. The first
-- star not yet won was shown whatever was picked: every star won, its first one - "SLIP SLIDIN' AWAY" over Cool, Cool
-- Mountain's race - "in mario 64 menu the 7th star name doesnt show correclty please fix for all levels", 2026-11-05.
-- (Its name's picture: tools/pause_extra_acts.py.)
function M.shown_act(n)
    local G = package.loaded["game"]
    local ca = G and G.course_act
    if not (ca and ca.act and G.name and n and n <= 15 and M.course_of(G.name) == n) then return nil end
    local x = G.EXTRA_STARS and G.EXTRA_STARS[ca.course]
    if x and ca.act == x.act then return 7 end
    if ca.act >= 1 and ca.act <= 6 then return ca.act end
    return nil
end
local function first_act(n)
    if n > 15 then return 1 end
    local flags = course_flags(n)
    for a = 1, 6 do if flags & (1 << (a - 1)) == 0 then return a end end
    return 1
end

local function castle_line(start, dir)
    -- handle_menu_scrolling on gMenuLineNum: the 15 courses, then the castle's secret stars, round again. (Mario
    -- 64 skips the courses with no stars yet; with none collected that left only the secret stars, and the user
    -- asked to "be able to look through the stars in the mario pause menu" (2026-10-14), so every course is shown.)
    local line = start + (dir or 0)
    if line > 16 then line = 1 end
    if line < 1 then line = 16 end
    return line
end

local function open_screen(ctx)
    local n = M.course_of(ctx.scene)
    if n then
        local opts = { { key = "continue", y = 91, act = "continue" } }
        if ctx.can_exit then opts[#opts + 1] = { key = "exit_course", y = 76, act = "exit" } end
        -- (the mod's own, under EXIT COURSE - which puts him outside the course's painting: EXIT TO CASTLE, to the
        -- entrance hall, Mario 64's own way out; "exit to castle I mean", 2026-10-18)
        if ctx.can_exit and ctx.castle then opts[#opts + 1] = { key = "exit_castle", y = 61, act = "castle" } end
        opts[#opts + 1] = { key = "camera_r", y = ({ 76, 60, 46 })[#opts], act = "camera" }
        st = { kind = "course", n = n, act = M.shown_act(n) or first_act(n), sel = 1, options = opts }
    else
        -- (Mario 64's castle pause has no choices: A or Start goes back to the game)
        st = { kind = "castle", line = castle_line(M.last_line or 1, 0), sel = 1, options = { { key = "continue", act = "continue" } } }
    end
    st.exit, st.castle = ctx.exit, ctx.castle
    M.open = true
    -- (from STORROR's menu: the game is held already, and stays so)
    if menu_hold then menu_hold = false else freeze(true) end
    render()
    sound("menu_pause")
    log("pause screen open (%s%s)", st.kind, n and (" " .. n) or "")
end

-- Mario 64's pause screen in STORROR's SPOTS tab, STORROR's menu up the while (msettings.lua m64_spots): as Start on
-- Mario 64 brings it up - its sound, its looks - with Up and Down from STORROR's rows (msettings M.spots_input), Right
-- as its A, and Start - which shuts STORROR's menu - taking the choice the hand points at (M.tick, the menu gone)
local emb_choice = nil
local function embed_open(ctx)
    local n = M.course_of(ctx.scene)
    if n then
        local opts = { { key = "continue", y = 91, act = "continue" } }
        if ctx.can_exit then opts[#opts + 1] = { key = "exit_course", y = 76, act = "exit" } end
        if ctx.can_exit and ctx.castle then opts[#opts + 1] = { key = "exit_castle", y = 61, act = "castle" } end
        opts[#opts + 1] = { key = "camera_r", y = ({ 76, 60, 46 })[#opts], act = "camera" }
        st = { kind = "course", n = n, act = M.shown_act(n) or first_act(n), sel = 1, options = opts }
    else
        st = { kind = "castle", line = castle_line(M.last_line or 1, 0), sel = 1, options = { { key = "continue", act = "continue" } } }
    end
    st.exit, st.castle = ctx.exit, ctx.castle
    emb, emb_choice = true, nil
    render()
    sound("menu_pause")
    log("pause screen in SPOTS (%s%s)", st.kind, n and (" " .. n) or "")
end
local function embed_close()
    if not emb then return end
    emb = false
    if st and st.kind == "castle" then M.last_line = st.line end
    remove_ui()
end

local function close_screen(play)
    if not M.open then return end
    M.open = false
    if st and st.kind == "castle" then M.last_line = st.line end
    remove_ui()
    freeze(false)
    if play ~= false then sound("menu_pause_2") end
end

local function choose(act)
    if act == "exit" then
        local leave = st.exit
        close_screen()
        log("exit course")
        if leave then leave() end
    elseif act == "castle" then
        local leave = st.castle
        close_screen()
        log("exit to castle")
        if leave then leave() end
    elseif act == "camera" then
        sound("menu_buzz")              -- (the file's perspective is its own, for good)
    elseif act == "switch" then
        close_screen()
        M.mode = "storror"
        storror_sounds(true)
        log("pause menu: STORROR's")
        burst = 0.6
    else
        close_screen()
    end
end

-- the stick (either) and the d-pad: -1 up/left, +1 down/right, with Mario 64's hold-to-repeat
local reps = { v = { dir = 0, t = 0.0 }, h = { dir = 0, t = 0.0 } }
local function scroll(pc, dt, vertical)
    local rep = reps[vertical and "v" or "h"]
    local x, y = PAD.sticks()
    local dir = 0
    if vertical then
        if y > 0.5 or down(pc, UP_KEYS) then dir = -1 elseif y < -0.5 or down(pc, DOWN_KEYS) then dir = 1 end
    else
        if x < -0.5 or down(pc, LEFT_KEYS) then dir = -1 elseif x > 0.5 or down(pc, RIGHT_KEYS) then dir = 1 end
    end
    if dir == 0 then rep.dir = 0; return 0 end
    if dir ~= rep.dir then rep.dir, rep.t = dir, HOLD_FIRST; return dir end
    rep.t = rep.t - dt
    if rep.t <= 0 then rep.t = HOLD_NEXT; return dir end
    return 0
end

local function screen_tick(pc, dt)
    if not ui_ok() then render() end
    if st.kind == "course" then
        local d = scroll(pc, dt, true)
        if d > 0 then
            if st.sel == #st.options then st.sel = 1 else st.sel = st.sel + 1; sound("menu_change_select") end
            move_pointer()
        elseif d < 0 and st.sel > 1 then
            st.sel = st.sel - 1
            sound("menu_change_select")
            move_pointer()
        end
    else
        local d = scroll(pc, dt, true)
        if d ~= 0 then
            local line = castle_line(st.line, d)
            if line ~= st.line then st.line = line; sound("menu_change_select"); render() end
        end
        local h = scroll(pc, dt, false)
        if h ~= 0 then
            local sel = math.max(1, math.min(#st.options, st.sel + h))
            if sel ~= st.sel then st.sel = sel; sound("menu_change_select"); move_pointer() end
        end
    end
    if pressed(pc, "ok", OK_KEYS) then
        choose(st.options[st.sel].act)
    elseif pressed(pc, "back", BACK_KEYS) then
        choose("continue")
    end
end

-- a step of Mario 64's screen in SPOTS: its Up, Down and A from STORROR's rows
local function embed_tick()
    if not ui_ok() then render() end
    local ev = MSET_INPUT and MSET_INPUT()
    if not ev then return end
    for _ = 1, ev.down do
        if st.kind == "course" then
            if st.sel == #st.options then st.sel = 1 else st.sel = st.sel + 1 end
            sound("menu_change_select"); move_pointer()
        else
            local line = castle_line(st.line, 1)
            if line ~= st.line then st.line = line; sound("menu_change_select"); render() end
        end
    end
    for _ = 1, ev.up do
        if st.kind == "course" then
            if st.sel > 1 then st.sel = st.sel - 1; sound("menu_change_select"); move_pointer() end
        else
            local line = castle_line(st.line, -1)
            if line ~= st.line then st.line = line; sound("menu_change_select"); render() end
        end
    end
    if ev.ok > 0 then
        local act = st.options[st.sel].act
        if act == "camera" then
            sound("menu_buzz")
        else
            -- (A: as Start - the menu shut, the choice taken as it goes: M.tick)
            emb_choice = act
            shut_storror()
        end
    end
end

-- ------------------------------------------------------------------ every tick of the game
-- `ctx`: { scene, can_pause, can_exit, exit } from game.lua.
-- STORROR's menu is looked for (a search of every object, so not every tick) closely for a moment after each
-- Start, every 2 seconds otherwise, and every tenth of a second while it is open.
local START_TAB = "Character"         -- the tab right of the Mario tabs (and what the menu opens on without ours)
-- The tab STORROR's menu opens on: MARIO SETTINGS (msettings.lua) - "make opening the menu always start on mario menu
-- as well", 2026-11-01 (it opened on CHARACTER). CHARACTER where ours is not there.
-- (SPOTS - Mario 64's pause screen in it, as Start on Mario 64: "also make it so when you press pause you start in the
-- spot menu", 2026-11-01; it opened on MARIO SETTINGS before)
local OPEN_TAB = "SPOTS"
local open_tab = START_TAB
-- Mario 64's screen is one of STORROR's menu's tabs (MARIO 64), but it shut STORROR's menu to show: from it, LT and RT
-- (Z and C) did nothing - "it completely takes you out of storrors menu when you switch to mario menu which is the
-- problem", 2026-11-01. They now go back into STORROR's menu, on the tab beside MARIO 64 the way pressed: RT to MARIO
-- SETTINGS (CHARACTER without it), LT round to SETTINGS. The game held all the while.
local TAB_PREV_KEYS = { "Gamepad_LeftTrigger", "Z" }
local TAB_NEXT_KEYS = { "Gamepad_RightTrigger", "C" }
local want_tab = nil                  -- (the tab STORROR's menu is to open on, when come back to from Mario 64's)
local wheel_until = 0.0               -- (and STORROR's action wheel kept shut a moment after: the same LT opened it)
-- (STORROR's menu put up a moment after LT/RT, not at once: the same press opened STORROR's action wheel in the game,
-- and the wheel took the menu's place - it showed and went again: "menu still closes when you try to switch back to
-- mario settings", 2026-11-01. The wheel shut first, then the menu)
local REOPEN_AFTER = 0.2
local reopen_at = nil
local FIRST_TAB = "ADVENTURE"          -- the tab STORROR itself opens it on
local opened_t = -10.0
local shut_until = 0.0                 -- (STORROR's menus opened by the Start that closed Mario 64's are shut too)
local relock_t = 0.0

local okMS, MSET = pcall(require, "msettings")         -- (the mod's own row in STORROR's Settings > Audio)
if not okMS then MSET = nil end
MSET_INPUT = function() return MSET and MSET.spots_input and MSET.spots_input() end
local okCP, CPICK = pcall(require, "charpick")         -- (the Mario face on STORROR's CHARACTER screen)
if not okCP then CPICK = nil end
local okCL, CLPICK = pcall(require, "clothpick")      -- (our clothes on it: JEANS)
if not okCL then CLPICK = nil end

-- (and the view kept off STORROR's figure meanwhile: its menu, up the moment till it is shut, puts the view on its
-- CHARACTER figure - STORROR's own man - and nothing put it back; in the ending, Start pressed or held to skip it showed
-- him - "when pressing pause to skip the storror charater pops up", 2026-11-02. The view put back on what it was on - the
-- ending's camera, the intro's - else on him.)
local block_vt = nil
local block_until = 0.0                -- (Start pressed while it is blocked: blocked a little longer - block)
local function is_figure(o)
    local cn = ""
    pcall(function() cn = o:GetClass():GetFName():ToString() end)
    return cn == "PlayerMannequinBP_C"
end
local function block_view(pc)
    local vt = nil
    pcall(function() vt = pc:GetViewTarget() end)
    if not vt then return end
    local okv, valid = pcall(function() return vt:IsValid() end)
    if not (okv and valid) then return end
    -- (and the one the view is blending to: STORROR's menu blends it over to its figure, and GetViewTarget gives the old
    -- one till the blend is done - the CHARACTER screen swung into sight first: "storror charater screen shows when
    -- pausing in the air", 2026-11-02)
    local pend = nil
    pcall(function()
        local p = pc.PlayerCameraManager.PendingViewTarget.Target
        if p and p:IsValid() then pend = p end
    end)
    local fig = is_figure(vt) or (pend ~= nil and is_figure(pend))
    if not fig then block_vt = vt; return end
    if not is_figure(vt) then block_vt = vt end
    local to = nil
    if block_vt then
        local okb, bvalid = pcall(function() return block_vt:IsValid() end)
        if okb and bvalid then to = block_vt end
    end
    to = to or lib.pawn()
    if to then pcall(function() pc:SetViewTargetWithBlend(to, 0.0, 0, 0.0, false) end) end
    log("pause blocked: the view taken off STORROR's figure")
end

-- (and STORROR's turn of the view to its figure stopped as it is asked for, while Start is blocked: the view handed the
-- one it is on instead. Turned back a tick later, the figure's room still showed for a frame - "something still flashing
-- on screen", 2026-11-02. M.blocking: set by M.tick.)
M.blocking = false
pcall(function()
    if _G.SM64_PAUSE_VIEW_HOOK then return end
    _G.SM64_PAUSE_VIEW_HOOK = true
    RegisterHook("/Script/Engine.PlayerController:SetViewTargetWithBlend", function(ctx, target)
        local P = package.loaded["pause"]
        if not (P and P.blocking) then return end
        local t = nil
        pcall(function() t = target:get() end)
        if not (t and is_figure(t)) then return end
        local keep = nil
        pcall(function() keep = ctx:get():GetViewTarget() end)
        if keep and not is_figure(keep) then
            pcall(function() target:set(keep) end)
            log("pause blocked: STORROR's turn to its figure kept off")
        end
    end)
end)

-- No pause (game.lua G.pause_blocked: a death under way): Start does nothing - STORROR's menu shut as soon as it comes
-- up, the game not held for it, Mario 64's screen not offered
-- A purple veil over the screen as Start is pressed in the air, to take out the yellow of STORROR's menu that flashes up
-- then (opened by its own code all the same, and shut a moment later): "okay lets counter the yellow flash with some
-- purple", 2026-11-02. Its colour, strength (render opacity), how long it is held and how long it fades.
M.PURPLE = { R = 0.55, G = 0.0, B = 1.0, alpha = 0.04, hold = 0.7, fade = 0.3 }   -- (0.35 "way too strong", 0.12 "still too strong")
local purple = nil                     -- { widget, img, t }
-- (and the screen brightened while it is up - his camera's exposure raised `ev` stops, faded with the veil: "lets also
-- crank the brightness of the screen during", 2026-11-02)
M.BRIGHT = { ev = 1.6 }                 -- (1.0: "a tiny bit brighter"; 1.3: "little brighter")
local bright = nil                     -- { cam, over, bias }: his camera's own exposure, to put back
local function bright_set(k)
    if k <= 0.0 then
        if bright then
            local b = bright
            bright = nil
            pcall(function()
                local pp = b.cam.PostProcessSettings
                pp.AutoExposureBias = b.bias or 0.0
                pp.bOverride_AutoExposureBias = b.over or false
            end)
        end
        return
    end
    pcall(function()
        if not bright then
            local c = lib.pawn():GetComponentByClass(StaticFindObject("/Script/Engine.CameraComponent"))
            local pp = c.PostProcessSettings
            bright = { cam = c, over = pp.bOverride_AutoExposureBias, bias = pp.AutoExposureBias }
        end
        local pp = bright.cam.PostProcessSettings
        pp.bOverride_AutoExposureBias = true
        pp.AutoExposureBias = (bright.bias or 0.0) + M.BRIGHT.ev * k
    end)
end
local function purple_show()
    if purple then purple.t = 0.0; return end
    local pc = lib.controller()
    if not pc then return end
    local ok = pcall(function()
        local function cls(p) return StaticFindObject(p) end
        _G.SM64_PURPLE_N = (_G.SM64_PURPLE_N or 0) + 1
        local n = "SM64Purple" .. _G.SM64_PURPLE_N
        local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName(n))
        local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName(n .. "Tree"))
        w.WidgetTree = tree
        local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName(n .. "Canvas"))
        tree.RootWidget = canvas
        local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName(n .. "Img"))
        local C = M.PURPLE
        img:SetColorAndOpacity({ R = C.R, G = C.G, B = C.B, A = 1.0 })
        local slot = canvas:AddChildToCanvas(img)
        slot:SetAnchors({ Minimum = { X = 0.0, Y = 0.0 }, Maximum = { X = 1.0, Y = 1.0 } })
        slot:SetOffsets({ Left = 0.0, Top = 0.0, Right = 0.0, Bottom = 0.0 })
        img:SetRenderOpacity(C.alpha)
        w:AddToViewport(100)
        purple = { widget = w, img = img, t = 0.0 }
    end)
    if not ok then purple = nil end
end
local function purple_tick(dt)
    local v = purple
    if not v then return end
    v.t = v.t + math.min(dt, 0.1)
    local C = M.PURPLE
    local a = C.alpha
    if v.t > C.hold then a = C.alpha * math.max(0.0, 1.0 - (v.t - C.hold) / C.fade) end
    pcall(function() v.img:SetRenderOpacity(a) end)
    bright_set(C.alpha > 0.0 and a / C.alpha or 0.0)
    if a <= 0.0 then
        pcall(function() v.widget:RemoveFromParent() end)
        purple = nil
        bright_set(0.0)
    end
end

local function block(pc, dt, real)
    -- (a fresh Start once he is down - only the hold after a blocked press left - pauses: the hold ended, the press
    -- left to the pause screen's own way - "also cant pause when on the ground", 2026-11-02)
    local start = pressed(pc, "open", OPEN_KEYS)
    if start and not real then
        block_until, burst = 0.0, 0.6
        return "free"
    end
    pcall(storror_sounds, false)
    pcall(storror_unseen, true)
    pcall(block_view, pc)
    -- (STORROR's menu can come up a moment after the press - built the first time it opens - and by then he may have
    -- landed: blocked on that long after a press)
    if start then burst = 0.6; block_until = os.clock() + 1.5; if real then pcall(purple_show) end end
    burst = burst - dt
    if burst > 0 or storror_open or menu_hold then
        local id = current_tab()
        if id ~= nil or storror_open then shut_storror() end
        storror_open = false
        tab_seen, tab_since = nil, nil
        if menu_hold then menu_hold = false; freeze(false) end
    end
end

function M.tick(dt, ctx)
    -- (in a lobby since the game was held - hosted or joined from the ONLINE tab with the menu up: let go at once, his
    -- keys still the menu's)
    if frozen and not frozen.online and M.online() then
        local f = frozen
        if f.world == here() then
            pcall(function() f.pawn.CustomTimeDilation = 1.0 end)
            lock_parts(f.pawn, false)
            if f.sim then body_go(f.pawn, f.sim) end
        end
        local MUSIC = package.loaded["music"]
        if MUSIC and MUSIC.set_volume and f.volume then pcall(MUSIC.set_volume, f.volume) end
        frozen = { pawn = f.pawn, world = f.world, online = true }
        log("pause: online now - the game goes on under it")
    end
    -- (and back: no longer going on - the FIRST PERSON tab left for another with STORROR's menu still up - held again,
    -- as any pause)
    if frozen and frozen.online and menu_hold and not M.online() then
        freeze(false)
        freeze(true)
        log("pause: held again")
    end
    -- (his ragdolled body kept asleep while the game stands still: body_hold)
    if frozen and frozen.sim and frozen.world == here() then pcall(function() frozen.pawn.Mesh:PutAllRigidBodiesToSleep() end) end
    local pc = lib.controller()
    if not pc then return end
    pcall(purple_tick, dt)
    local real = ctx and ctx.blocked and true or false
    M.blocking = ((real or os.clock() < block_until) and not M.open) and true or false
    if M.blocking then
        if block(pc, dt, real) ~= "free" then return end
        M.blocking = false
    end
    -- (the menus' pages - MARIO SETTINGS, CHARACTER, ONLINE - read 60 times a second, not every frame: their rows read at
    -- 130 a second were most of a pause's cost in multiplayer, where the game goes on under them - "it still loses
    -- about 40fps", 2026-11-04. Each given the time since it last ran)
    M.menu_acc = (M.menu_acc or 0.0) + dt
    if M.menu_acc >= (M.MENU_EVERY or 1.0 / 60.0) then
        local md = M.menu_acc
        M.menu_acc = 0.0
        if MSET then pcall(MSET.tick, md) end
        if CPICK then pcall(CPICK.tick, md, storror_open or menu_hold) end
        if CLPICK then pcall(CLPICK.tick, md, storror_open or menu_hold) end
    end
    -- (the skins picked in the CHARACTER tab put on him while the game stands still for the menu - caps.lua; online the
    -- game's own tick does it)
    if (M.open or storror_open or menu_hold) and not M.online() then
        local C = package.loaded["caps"]
        if C and C.skin_tick then pcall(C.skin_tick, dt, lib.pawn()) end
    end
    local start = pressed(pc, "open", OPEN_KEYS)
    if start then burst = 0.6 end
    burst = burst - dt
    look_t = look_t - dt
    -- (the 2-second look for STORROR's menu - a search of every object, a 20 ms hitch - only when its menu stack is up,
    -- which is one property read: "next we have to do major optimization", 2026-11-01)
    -- (out of the menu: a look every 10 s, not 2 - and no longer by reading the controller's MenuStack: in this
    -- engine a destroyed menu leaves that property pointing at freed memory, and reading it at a level change crashed
    -- the game - 14:07 and 15:35, 2026-11-01)
    local look = burst > 0 or look_t <= -8.0 or ((storror_open or menu_hold) and look_t <= 1.9)
    if look then look_t = 2.0 end
    M.prepare()
    local now = os.clock()

    -- Mario 64's screen is up: it has the buttons, and STORROR's menu (Start opens it too) is shut again unheard
    if M.open then
        relock_t = relock_t - dt
        if relock_t <= 0 then relock_t = 0.1; relock() end
        shut_wheel()
        storror_sounds(false)
        if look then shut_storror() end
        -- (the tab row's colours kept: MARIO 64 lit)
        pcall(function()
            for _, e in ipairs((ui and ui.b and ui.b.tabnames) or {}) do
                local c = e.w.ColorAndOpacity.SpecifiedColor
                if math.abs(c.R - e.col.R) + math.abs(c.G - e.col.G) + math.abs(c.B - e.col.B) > 0.02 then
                    e.w:SetColorAndOpacity({ SpecifiedColor = e.col, ColorUseRule = 0 })
                end
            end
        end)
        local tprev, tnext = pressed(pc, "tab_prev", TAB_PREV_KEYS), pressed(pc, "tab_next", TAB_NEXT_KEYS)
        if (tprev or tnext) and not start then
            -- (back into STORROR's menu: Mario 64's screen away, the game still held - the hold handed to STORROR's
            -- menu, as it is handed the other way in open_screen)
            want_tab = tnext and OPEN_TAB or "Settings"
            M.open = false
            if st and st.kind == "castle" then M.last_line = st.line end
            remove_ui()
            menu_hold = true
            tab_seen, tab_since, gone_since = nil, nil, nil
            burst = 0.6
            sound("menu_pause_2")
            log("Mario 64's pause screen: %s - back to STORROR's menu, on %s", tnext and "RT" or "LT", want_tab)
            reopen_at = now + REOPEN_AFTER
            wheel_until = now + REOPEN_AFTER + 1.2
            shut_wheel()
            return
        end
        if start then
            shut_until = now + 0.6
            choose(st.options[st.sel].act)
        else
            screen_tick(pc, dt)
        end
        return
    end
    if now < shut_until then
        if look then shut_storror() end
        return
    end
    -- (just come back from Mario 64's screen by LT/RT: STORROR's action wheel, opened by the same press, shut; then
    -- STORROR's menu up)
    if now < wheel_until then shut_wheel() end
    if reopen_at and now >= reopen_at then
        reopen_at = nil
        shut_wheel()
        open_storror()
    end
    storror_sounds(true)
    storror_unseen(false)
    if emb then pcall(embed_tick) end
    -- (the live view, every tick STORROR's menu is up: its CHARACTER screen's camera never shown)
    if LIVE_BG and (storror_open or menu_hold) then pcall(live_view) end

    -- (STORROR's menu shown once it has stood on the tab it opened on for a moment - 0.25 s, 0.3 s at least after it
    -- came up, 1.2 s at most; looked at every tick till then)
    if unveil then
        local id = current_tab()
        if not id then
            unveil = nil
        else
            if id == open_tab then unveil.on = unveil.on or now else unveil.on = nil end
            if (now - unveil.t0 > 0.3 and unveil.on and now - unveil.on > 0.25) or now - unveil.t0 > 1.2 then
                for _, w in ipairs(storror_menus()) do pcall(function() w:SetRenderOpacity(1.0) end) end
                unveil = nil
            end
        end
    end

    -- STORROR's menu: opened by Start as STORROR does, put on its start tab, watched for the Mario tab
    if look then
        local id, bar = current_tab()
        storror_open = id ~= nil
        -- (the view back on him in the same tick the menu is first seen, not the next: STORROR's camera on its
        -- CHARACTER figure's room showed meanwhile - "we have to make sure ... that fucking charater screen" doesn't
        -- show, 2026-11-01)
        if storror_open and LIVE_BG then pcall(live_view) end
        if not storror_open and fig then pcall(figure_back) end
        if bar then relabel_bar(bar); keep_hidden(bar); clear_backdrop() end
        -- (the game held still while STORROR's menu is up, let go once it has really gone)
        if storror_open and not menu_hold then
            menu_hold = true
            freeze(true)
            log("STORROR's menu up: the game stands still")
        elseif not storror_open and menu_hold and gone_since and now - gone_since > 0.3 and not reopen_at
            and now > wheel_until then
            -- (shut with Mario 64's screen up in SPOTS: Start - or A - takes the choice the hand points at)
            local act = nil
            if emb then
                act = emb_choice or (st and st.options[st.sel] and st.options[st.sel].act)
                embed_close()
                sound("menu_pause_2")
            end
            emb_choice = nil
            menu_hold = false
            freeze(false)
            if act == "exit" or act == "castle" then
                local leave = (act == "exit") and st.exit or st.castle
                log("pause screen in SPOTS: %s", act == "exit" and "exit course" or "exit to castle")
                if leave then pcall(leave) end
            end
        end
        if id then
            gone_since = nil
            if tab_seen == nil then
                -- (a new opening: on to MARIO SETTINGS - put in first, if it is not yet - whichever tab STORROR
                -- opened on; CHARACTER without it)
                open_tab = START_TAB
                if MSET and MSET.ensure_tab then
                    local ok, there = pcall(MSET.ensure_tab, bar)
                    if ok and there then open_tab = OPEN_TAB end
                end
                -- (come back to from Mario 64's screen: the tab beside it, the way LT or RT was pressed)
                if want_tab then
                    pcall(function()
                        local b = bar:GetTabButtonBaseByID(FName(want_tab))
                        if b and b:IsValid() then open_tab = want_tab end
                    end)
                    want_tab = nil
                end
                if id ~= open_tab then pcall(function() bar:SelectTabByID(FName(open_tab), true) end) end
                tab_seen, tab_since, opened_t = open_tab, nil, now
                -- (STORROR's menu unseen as it opens - its own first tab, its switch to ours, its jump back to its
                -- first tab - till it has stood on the tab it opens on a moment: "make sure storrors own menu doesnt
                -- show", 2026-11-01. Mario 64's screen in SPOTS is under it, seen from the start.)
                for _, w in ipairs(storror_menus()) do pcall(function() w:SetRenderOpacity(0.0) end) end
                unveil = { t0 = now, on = nil }
            elseif (id == FIRST_TAB and now - opened_t < 1.0) or (id == TAB_ID and id ~= open_tab and now - opened_t < 0.8) then
                -- (STORROR puts its menu back on its own first tab a moment after it opens: moved on again. The
                -- player cannot get to that tab from the one it opened on that fast, so it is not theirs. Opened with
                -- the pad, its first tab - ADVENTURE hidden - came out as MARIO 64, and that put up Mario 64's screen
                -- and shut the menu every time: "it completely takes you out of storrors menu", 2026-11-01.)
                pcall(function() bar:SelectTabByID(FName(open_tab), true) end)
            elseif id == HIDDEN_TAB then
                -- (the bumpers can still land on the hidden tab: on past it, the way the player was going. From
                -- the Mario tab that is round to SETTINGS; from SETTINGS, round to the Mario tab.)
                local to = (tab_seen == TAB_ID) and "Settings" or TAB_ID
                pcall(function() bar:SelectTabByID(FName(to), true) end)
            elseif id == ONLINE_TAB and not MP_ONLINE then
                -- (ONLINE, between CHARACTER and CONTROLS: on past it the way the player was going)
                local to = (tab_seen == "Controls") and START_TAB or "Controls"
                pcall(function() bar:SelectTabByID(FName(to), true) end)
            elseif id ~= tab_seen then
                tab_seen = id
                tab_since = (MARIO_TAB and id == TAB_ID) and now or nil
                if tab_since then log("STORROR's menu: on the Mario tab") end
            end
            -- (Mario 64's screen in SPOTS: up while SPOTS is the tab on, away when another is)
            if M64_IN_SPOTS and ctx and ctx.can_pause then
                if id == TAB_ID and not emb then pcall(embed_open, ctx)
                elseif id ~= TAB_ID and emb then embed_close() end
            end
            if tab_since and id == TAB_ID and now - tab_since >= TAB_DWELL and ctx and ctx.can_pause then
                tab_seen, tab_since = nil, nil
                -- (off the Mario tab before it shuts, so that it does not open there)
                pcall(function() bar:SelectTabByID(FName(START_TAB), true) end)
                storror_open = false
                shut_storror()
                log("Mario tab: Mario 64's pause screen")
                held.ok, held.back = true, true
                open_screen(ctx)
            end
        else
            -- (between two of its own screens STORROR's menu is not there for a moment: only a real while away
            -- makes the next one a new opening)
            gone_since = gone_since or now
            if now - gone_since > 1.0 then tab_seen, tab_since = nil, nil end
        end
    end
end

-- STORROR's menu up, or about to be (msettings.lua: its searches only then)
function M.menu_maybe()
    return storror_open or menu_hold or burst > 0 or reopen_at ~= nil or M.open
end

-- the tab STORROR's menu is on, while it is up (charpick.lua: his hair shown on CHARACTER only)
function M.tab() return storror_open and tab_seen or nil end

-- (for trying it over the dev channel: the screen opened, a choice made, a step of the cursor, without buttons)
M.debug = {
    open = function(ctx) open_screen(ctx) end, choose = function(a) choose(a) end,
    state = function() return st end, step = function(d)
        if st.kind == "course" then st.sel = math.max(1, math.min(#st.options, st.sel + d)); move_pointer()
        else local l = castle_line(st.line, d); if l ~= st.line then st.line = l; render() end end
    end,
    storror = function() return #storror_menus(), open_storror() end,
    storror_open = function() return storror_open end,
}

-- The map went (quit to the menu, a reload): forget the screen without touching it.
function M.forget()
    -- (the music's volume put back as the pause found it: quit from the pause menu to the file select - the map going
    -- under it - left it at MUSIC_DOWN, and the next new file's opening played that quiet: "music doesnt play during
    -- lakito's entrance", "still no music", 2026-11-09)
    if frozen and frozen.volume then
        local MUSIC = package.loaded["music"]
        if MUSIC and MUSIC.set_volume then pcall(MUSIC.set_volume, frozen.volume) end
    end
    fig = nil
    ui, frozen, M.open, storror_open, closed_t = nil, nil, false, false, nil
    menu_hold = false
    tab_seen, tab_since, gone_since, relabelled = nil, nil, nil, {}
    -- (the purple veil's widget and the camera it brightened: the gone map's)
    purple, bright = nil, nil
end

return M
