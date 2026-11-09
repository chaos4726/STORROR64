-- SM64Map health and HUD: Mario 64's power meter, the rules behind it, and the lives, coin and star counters.
--
-- Health is Mario 64's own number: 0x880 when full, 0x100 a wedge, eight wedges on the meter, and
-- Mario is out when it drops under one wedge. Damage and healing are not applied at once: they are
-- counted out a quarter-wedge per Mario 64 frame (30 a second), which is what makes the meter tick
-- down. After a hit Mario cannot be hurt again for a second.
--
-- The pictures (textures/hud_*.png) were read out of the player's own Mario 64 ROM.
local lib = require("lib")
local M = {}

M.MAX = 0x880
M.START_LIVES = 4
M.HIT_GRACE = 1.0                   -- seconds of invulnerability after a hit (30 Mario 64 frames)
M.SCALE = 0.75                      -- the mod builds Mario 64's levels at this many cm per Mario unit
M.FALL = 1150 * M.SCALE             -- a drop past this hurts,
M.FALL_FAR = 3000 * M.SCALE         -- and past this hurts badly
-- wedges lost to each thing, as in Mario 64
M.DAMAGE = { goomba_tiny = 0, goomba = 1, goomba_huge = 2, bobomb = 2, bowser = 3, fire = 3, fall = 2, fall_far = 4 }

M.health, M.hurt, M.mend, M.grace, M.lives = M.MAX, 0, 0, 0.0, M.START_LIVES
M.coins, M.stars = 0, 0             -- what the counters show; the game sets these
M.dead_t = nil                      -- seconds since the power ran out, while it has
M.hud_off = false                   -- set while the opening scene of a new file plays
local acc = 0.0
local full_t = 99.0
local hurt_at = nil                 -- os.clock() of the last hit that counted (the blink after it)
local blink = nil                   -- while he is blinked out: { pawn, parts = { { comp, was } } }

function M.wedges() return math.max(0, math.min(8, M.health >> 8)) end

-- The blink after a hit (Mario 64 draws Mario only every other frame while his invincTimer runs): his body and all on
-- it - the Mario look's pieces, the feet's copy of him, the cloth - hidden every other Mario 64 frame for the second he
-- cannot be hurt, so it shows. By each part's hidden-in-game flag, each one's own put back after (the look hides his
-- hair that way, the squish his cloth), not his actor's - STORROR shows that again every frame. The camera and the
-- lights are not on his body and are left alone. ("adding upgrading and improving", 2026-10-18.)
local PRIM = nil
local function unblink()
    local b = blink
    blink = nil
    if not b then return end
    for _, pt in ipairs(b.parts) do
        pcall(function() if pt[1]:IsValid() then pt[1]:SetHiddenInGame(pt[2], false) end end)
    end
end
M.unblink = unblink
local function blink_out(pawn)
    local parts = {}
    local mesh = nil
    pcall(function() mesh = pawn.Mesh end)
    if not (mesh and mesh:IsValid()) then return end
    PRIM = PRIM or StaticFindObject("/Script/Engine.PrimitiveComponent")
    local list = { mesh }
    pcall(function()
        local kids = {}
        mesh:GetChildrenComponents(true, kids)
        for _, k in ipairs(kids) do
            local c = k.get and k:get() or k
            if c and c:IsValid() and c:IsA(PRIM) then list[#list + 1] = c end
        end
    end)
    for _, c in ipairs(list) do
        local was = false
        pcall(function() was = c.bHiddenInGame and true or false end)
        if not was then
            parts[#parts + 1] = { c, was }
            pcall(function() c:SetHiddenInGame(true, false) end)
        end
    end
    blink = { pawn = pawn:GetAddress(), parts = parts }
end
local function blink_tick()
    local want = false
    if hurt_at and not M.dead_t and M.grace > 0 and os.clock() - hurt_at < M.HIT_GRACE + 0.1 then
        local G = package.loaded["game"]
        local C = package.loaded["caps"]
        local SQ = package.loaded["squish"]
        local MN = _G.MENU
        local busy = (G and (G.cutscene or G.dying or G.pending)) or (C and C.on and C.on("vanish"))
            or (SQ and SQ.active and SQ.active()) or (MN and MN.state and MN.state ~= "game")
        -- (shown the first frames of it - invincTimer >= 3 - then every other frame out)
        want = not busy and os.clock() - hurt_at > 2 / 30 and math.floor(os.clock() * 30) % 2 == 1
    end
    local pawn = want and lib.pawn() or nil
    if blink and (not want or not pawn or pawn:GetAddress() ~= blink.pawn) then unblink() end
    if want and pawn and not blink then pcall(blink_out, pawn) end
end

function M.reset()
    unblink()
    M.health, M.hurt, M.mend, M.grace, M.dead_t = M.MAX, 0, 0, 0.0, nil
    M.gruesome = nil
end

-- Take `wedges` of damage. False when it did not count (still flashing from the last hit, already out).
-- `fall`: a long drop's - not held off by the moment of grace the scene built again round him gives (G.safe_until: for
-- the creatures put back round him), only by a hit's flashing. A jump off the level just after it hurt nothing - "just
-- fell from a high height took no damage", 2026-11-02, a 39 m drop in Bowser in the Sky
-- (hurts that drain him as ever in HUMAN MODE, not kill him at once: HMC's poison gas, a wedge every two seconds or so
-- - it took him in one breath: "make sure the player cant die in the toxic fog to a 1 tap", 2026-11-07. And a treasure
-- chest opened out of order - Jolly Roger Bay's and Dire, Dire Docks' puzzles: its shock a wedge, as ever, not his
-- death; no way to know the order but by trying - "yeah fix that though", 2026-11-08)
M.HUMAN_SPARE = { ["poison gas"] = true, ["a treasure chest's shock"] = true }
function M.damage(wedges, why, fall)
    local G = package.loaded["game"]
    local rebuilt = fall and G and os.clock() < (G.safe_until or 0.0) and not (hurt_at and os.clock() - hurt_at < M.HIT_GRACE) or false
    if wedges <= 0 or (M.grace > 0 and not rebuilt) or M.dead_t then return false end
    if G and G.intangible and G.intangible(rebuilt) then return false end    -- (in a cannon: nothing reaches him)
    local C = package.loaded["caps"]
    if C and C.shield and C.shield(why) then return false end         -- (the metal or vanish cap: not hurt but by falls)
    -- (HUMAN MODE: whatever hurts him kills him, there and then, gruesomely - menu.lua M.human_on, game.lua's death. The
    -- water's slow drain never comes here: drowning and the cold go as before)
    local MN = _G.MENU
    if MN and MN.human_on and MN.human_on() and not M.HUMAN_SPARE[why or ""] then
        M.human_death(why)
        return true
    end
    -- (without his cap, half as bad again: take_damage_from_interact_object - mariocap.lua)
    local MC = package.loaded["mariocap"]
    if MC and MC.damage then wedges = MC.damage(wedges) or wedges end
    M.hurt = M.hurt + wedges * 4
    M.grace = M.HIT_GRACE
    hurt_at = os.clock()
    M.last_hurt = hurt_at       -- (when a hit last counted: bowser_fight.lua drops Bowser's tail at one)
    lib.log("hurt by %s: %d wedge(s), %d left", tostring(why), wedges, math.max(0, M.wedges() - wedges))
    -- (Mario's cry as he is hurt, Mario 64's SOUND_MARIO_ATTACKED rendered from the ROM: "add audio for when you take
    -- damage as mario", 2026-10-14)
    local SX = package.loaded["sfx"]
    if SX and SX.play then pcall(SX.play, "mario_attacked", 1.0) end
    -- (the camera shaken with it: take_damage_from_interact_object's SHAKE_SMALL / MED / LARGE_DAMAGE by the hurt,
    -- check_fall_damage's SHAKE_FALL_DAMAGE for a drop)
    if G and G.shake_camera then pcall(G.shake_camera, (wedges >= 4 and 2.2) or (wedges >= 2 and 1.4) or 0.8) end
    return true
end

function M.heal(wedges)
    if not M.dead_t then M.mend = M.mend + wedges * 4 end
end

-- HUMAN MODE's death: out of power at once, the death to be a gruesome one (M.gruesome: game.lua)
function M.human_death(why)
    if M.dead_t then return end
    M.hurt, M.mend, M.health, M.grace = 0, 0, 0x80, 0.0
    M.gruesome = { why = why, t = os.clock() }
    lib.log("HUMAN MODE: %s - dead", tostring(why))
end

-- Out of power at once (quicksand that swallows whole).
function M.kill(why)
    if M.dead_t then return end
    lib.log("%s: out of power", tostring(why))
    M.hurt, M.mend, M.health = 0, 0, 0x80
end

-- One tick. `water`: nil out of the water, "surface" within reach of the surface, where Mario 64 tops the meter
-- back up (0x1A a frame), or "under", deeper, where it runs down a unit a frame (a full meter lasts about 70 s)
-- until he drowns. (While he swims the meter stays on the screen, as Mario 64's does.)
-- Returns true on the tick the power runs out.
-- Cold water: Mario 64's snow courses (TERRAIN_SNOW: Cool, Cool Mountain, Snowman's Land and its igloo, Wing Mario Over
-- the Rainbow) drain 3 a frame wherever he swims, and never mend him at the surface (update_mario_health) - "swimming
-- in cold water should do damage", 2026-10-26: a full meter in about 23 s.
M.COLD_WATER = { ccm = true, sl = true, sl_2 = true, wmotr = true }
function M.tick(dt, water)
    -- (a death's gruesome mark kept only for that death: left on from one with GORE on - or a HUMAN file's - every death
    -- after it was gruesome, GORE off and HUMAN off alike: "gore mode still on even though its off", 2026-11-05. HUMAN
    -- MODE's own is set the moment it kills him, M.human_death, so it is fresh)
    if M.gruesome and not M.dead_t and os.clock() - (M.gruesome.t or 0.0) > 2.0 then M.gruesome = nil end
    local G = package.loaded["game"]
    if water and G and M.COLD_WATER[G.name or ""] then water = "cold" end
    M.in_water = water ~= nil
    if M.grace > 0 then M.grace = M.grace - dt end
    blink_tick()
    acc = math.min(acc + dt, 0.5)
    local died = false
    while acc >= 1 / 30 do
        acc = acc - 1 / 30
        if M.hurt > 0 then M.health = M.health - 0x40; M.hurt = M.hurt - 1 end
        if M.mend > 0 then M.health = M.health + 0x40; M.mend = M.mend - 1 end
        if water == "surface" and not M.dead_t then M.health = M.health + 0x1A end
        if water == "under" and not M.dead_t then M.health = M.health - 1 end
        if water == "cold" and not M.dead_t then M.health = M.health - 3 end
        if M.health > M.MAX then M.health, M.mend = M.MAX, 0 end
        if M.health < 0x100 and not M.dead_t then
            M.health, M.hurt, M.mend = 0xFF, 0, 0
            M.dead_t = 0.0
            died = true
        end
    end
    M.hud_update(dt)
    return died
end

-- ------------------------------------------------------------------ on screen
-- Sizes and positions are in Mario 64 screen pixels times UNIT. The power meter sits top middle, under
-- STORROR's compass; lives are top left, coins just right of the meter, stars top right, as on Mario 64's
-- own screen (a 16x16 picture, a "x", then the number). The speedrun timer, when it is on, is under the stars.
-- (2026-10-14, "put all the mario hud in the correct areas": everything at Mario 64's own places, from game/hud.c,
-- in its 320x240 screen's pixels; the counters keep to the screen's edges and middle as the game's widescreen
-- versions do. At Mario 64's own size, 4.5 units a pixel on a 1080-high screen, the user found it too big:
-- "make mario hud smaller again", so it is drawn at 2.3, about half)
local UNIT = 2.3
-- (BOWSER 3 CLEAR TIME: at the top in the middle, a little over the HUD's own size - "put the timer at the top middle and
-- make it say bowser 3 clear time make it smaller too", 2026-11-02; it stood big in the middle of the screen)
local CLEAR_SIZE, CLEAR_STEP, CLEAR_LABEL_Y, CLEAR_TIME_Y = 20.0, 16.0, 30.0, 52.0
local SHOWN_Y, HIDDEN_Y = 40.0, -40.0  -- the power meter's middle: Mario 64's y 200 on screen, and above the top
local EMPH_Y = 74.0                     -- where it drops in when damage first shows (y 166), easing up from there
local METER_X = -20.0                   -- its middle, from the middle of the screen (x 140)
local ROW_Y = 23.0                      -- the counters' middles (HUD_TOP_Y 209)
-- (the lives were lower for a while, under STORROR's stamina meter; the meter is hidden now, so they are back
-- where Mario 64 has them)
local LIVES_Y = ROW_Y
local TIME_X = -166.0               -- the T of TIME when the minutes have three digits (one digit: R-150)
-- (the race's timer and checkpoint count: under the power meter's place - its bottom at y 72 - one row each)
local RACE_TIME_Y, RACE_FLAGS_Y = 84.0, 102.0
local hud = nil
local hud_serial = 0
local hud_wait = 0.0
local hud_on = true

local function hud_ok()
    if not hud then return false end
    -- (the map first: the widget of a map that has gone may already be freed, and asking it brings the game down)
    local ok, valid = pcall(function() return hud.world == lib.world():GetAddress() and hud.widget:IsValid() end)
    return ok and valid
end

-- RENDER 96 turned (game.lua lib.on_r96): the HUD made again, its pictures Render96's or Mario 64's own as the switch now
-- stands - made once, it kept the ones it was made with ("also turning off render 96 mode should give the old UI",
-- 2026-11-01). Taken down here (its map's, still up), put up again by M.hud_update a second later.
function M.refresh_hud()
    local h = hud
    hud = nil
    if h and h.widget then
        pcall(function()
            if h.world == lib.world():GetAddress() and h.widget:IsValid() then h.widget:RemoveFromParent() end
        end)
    end
end

local function hud_build()
    local world, pc = lib.world(), lib.controller()
    if not (world and pc) then return end
    local function cls(path) return StaticFindObject(path) end
    hud_serial = hud_serial + 1
    local widget = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("SM64Hud" .. hud_serial))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), widget, FName("SM64HudTree" .. hud_serial))
    widget.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SM64HudCanvas" .. hud_serial))
    tree.RootWidget = canvas
    local h = { widget = widget, world = world:GetAddress(), y = HIDDEN_Y, shown = 8, parts = {}, pies = {}, counters = {} }
    local count = 0
    -- anchor: 0 = left edge, 0.5 = middle, 1 = right edge of the screen; x, y = centre of the picture from there
    local function image(file, anchor, x, y, w, hgt)
        count = count + 1
        local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("SM64HudImg" .. hud_serial .. "_" .. count))
        local tex = lib.texture(world, file)
        if tex then img:SetBrushFromTexture(tex, false) end
        local slot = canvas:AddChildToCanvas(img)
        slot:SetAnchors({ Minimum = { X = anchor, Y = 0.0 }, Maximum = { X = anchor, Y = 0.0 } })
        slot:SetAlignment({ X = 0.5, Y = 0.5 })
        slot:SetSize({ X = w * UNIT, Y = hgt * UNIT })
        slot:SetPosition({ X = x * UNIT, Y = y * UNIT })
        return img, slot
    end
    local function meter_part(file, dx, w, hgt)
        local img, slot = image(file, 0.5, METER_X + dx, HIDDEN_Y, w, hgt)
        h.parts[#h.parts + 1] = { img = img, slot = slot, dx = METER_X + dx }
        return img
    end
    meter_part("hud_power_left", -16.0, 32, 64)
    meter_part("hud_power_right", 16.0, 32, 64)
    -- one picture per wedge count, all made now; showing a different one later is only a visibility change
    for n = 1, 8 do
        h.pies[n] = meter_part("hud_power_" .. n, 0.0, 32, 32)
        h.pies[n]:SetVisibility((n == 8) and 4 or 1)
    end
    -- a counter: its picture, the "x", and room for `digits` digits
    -- (`num`: how far the number starts from the picture's middle; Mario 64 has the lives' 2 further out)
    local function counter(name, icon, anchor, x, digits, y, num)
        y, num = y or ROW_Y, num or 30.0
        local c = { imgs = {}, digits = {}, value = -1 }
        c.imgs[1] = image(icon, anchor, x, y, 16, 16)
        c.imgs[2] = image("hud_x", anchor, x + 16, y, 16, 16)
        for i = 1, digits do
            c.digits[i] = image("hud_0", anchor, x + num + (i - 1) * 12, y, 16, 16)
            c.imgs[#c.imgs + 1] = c.digits[i]
        end
        h.counters[name] = c
    end
    -- (three places: Mario 64 counts up to 100 lives, and 100 showed as "10" - "yea fix the counter", 2026-10-14)
    counter("lives", "hud_mario", 0.0, 30.0, 3, LIVES_Y, 32.0)     -- head at 22 from the left edge
    counter("coins", "hud_coin", 0.5, 16.0, 3)                      -- coin at 168: just right of the middle
    counter("stars", "hud_star", 1.0, -70.0, 3)                     -- star at 78 from the right edge
    -- The speedrun timer, under the stars, as Mario 64 draws the clock of its races: TIME 1'23"45. Every
    -- digit of every place is made now; showing a time later is only a matter of which ones are visible.
    local function speed_row(ty)
        local tm = { label = {}, marks = {}, places = {}, on = false, wide = 3 }
        for i, ch in ipairs({ "T", "I", "M", "E" }) do
            local img, slot = image("hud_" .. ch, 1.0, TIME_X + (i - 1) * 12.0, ty, 16, 16)
            tm.label[i] = { img = img, slot = slot, x = TIME_X + (i - 1) * 12.0 }
            img:SetVisibility(1)
        end
        for _, m in ipairs({ { "hud_apos", -73.0 }, { "hud_quote", -38.0 } }) do
            local img = image(m[1], 1.0, m[2], ty - 7.0, 16, 16)
            tm.marks[#tm.marks + 1] = img
            img:SetVisibility(1)
        end
        -- ten-thousands to units of minutes; tens and units of seconds; tenths and hundredths
        for p, x in ipairs({ -131.0, -119.0, -107.0, -95.0, -83.0, -63.0, -51.0, -29.0, -17.0 }) do
            local place = { shown = nil }
            for d = 0, 9 do
                place[d] = image("hud_" .. d, 1.0, x, ty, 16, 16)
                place[d]:SetVisibility(1)
            end
            tm.places[p] = place
        end
        tm.y = ty
        return tm
    end
    h.timer = speed_row(47.0)               -- (the race clock's line: y 185)
    -- The run's time as the Grand Star was taken (M.grand_time, ending.lua), big in the middle of the screen while he
    -- holds it up - the ending's outro - with CLEAR TIME over it: "it didnt show the full time", then "you need to fix the
    -- timer that shows up when you beat bowser 3" - in the middle, the outro only - "you must also label it", 2026-11-02.
    -- Twice the HUD's size; its places laid out when it is shown, the row centred on what it holds.
    local function mid_image(file, x, y, w, hgt)
        count = count + 1
        local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("SM64HudImg" .. hud_serial .. "_" .. count))
        local tex = lib.texture(world, file)
        if tex then img:SetBrushFromTexture(tex, false) end
        local slot = canvas:AddChildToCanvas(img)
        slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.0 }, Maximum = { X = 0.5, Y = 0.0 } })
        slot:SetAlignment({ X = 0.5, Y = 0.5 })
        slot:SetSize({ X = w * UNIT, Y = hgt * UNIT })
        slot:SetPosition({ X = x * UNIT, Y = y * UNIT })
        img:SetVisibility(1)
        return img, slot
    end
    local gt = { label = {}, places = {}, marks = {}, value = nil }
    -- (the level's own name - "Our Level should be called Final Bowser", 2026-11-03; its F: textures/hud_F.png)
    local word = "FINAL BOWSER CLEAR TIME"
    for i = 1, #word do
        local ch = word:sub(i, i)
        if ch ~= " " then
            gt.label[#gt.label + 1] = (mid_image("hud_" .. ch, (i - 1 - (#word - 1) / 2) * CLEAR_STEP, CLEAR_LABEL_Y, CLEAR_SIZE, CLEAR_SIZE))
        end
    end
    for _, m in ipairs({ "hud_apos", "hud_quote" }) do
        local img, slot = mid_image(m, 0.0, CLEAR_TIME_Y - CLEAR_SIZE * 7.0 / 16.0, CLEAR_SIZE, CLEAR_SIZE)
        gt.marks[#gt.marks + 1] = { img = img, slot = slot }
    end
    -- five places for the minutes, two for the seconds, two for the hundredths
    for p = 1, 9 do
        local place = { shown = nil, slots = {} }
        for d = 0, 9 do
            place[d], place.slots[d] = mid_image("hud_" .. d, 0.0, CLEAR_TIME_Y, CLEAR_SIZE, CLEAR_SIZE)
        end
        gt.places[p] = place
    end
    h.clear_time = gt
    -- The race's own timer, right under the power meter, apart from the speedrun timer: TIME 0'12"34, two places
    -- for the minutes, laid out as that one is and centred under the meter ("make a timer right below the power of the
    -- player or " health. seperated from our original timer", 2026-10-27). M.race_clock: its seconds, or nil.
    local rt = { label = {}, marks = {}, places = {}, on = false, wide = 3 }
    local RX = METER_X + 65.5           -- (the speedrun timer's places moved from the right edge to under the meter)
    for i, ch in ipairs({ "T", "I", "M", "E" }) do
        local x = TIME_X + RX + (i - 1) * 12.0
        local img, slot = image("hud_" .. ch, 0.5, x, RACE_TIME_Y, 16, 16)
        rt.label[i] = { img = img, slot = slot, x = x }
        img:SetVisibility(1)
    end
    for _, m in ipairs({ { "hud_apos", -73.0 }, { "hud_quote", -38.0 } }) do
        local img = image(m[1], 0.5, m[2] + RX, RACE_TIME_Y - 7.0, 16, 16)
        rt.marks[#rt.marks + 1] = img
        img:SetVisibility(1)
    end
    for p, x in ipairs({ -95.0, -83.0, -63.0, -51.0, -29.0, -17.0 }) do
        local place = { shown = nil }
        for d = 0, 9 do
            place[d] = image("hud_" .. d, 0.5, x + RX, RACE_TIME_Y, 16, 16)
            place[d]:SetVisibility(1)
        end
        rt.places[p] = place
    end
    rt.y = RACE_TIME_Y
    h.race_timer = rt
    -- and under it the checkpoints: the flag, "x", taken/all - 3/7 ("also add a checkpoint number counter",
    -- 2026-10-27). M.race_flags and M.race_of: taken and all, or nil. Five places for the number and its slash.
    local fc = { imgs = {}, glyphs = {}, text = nil }
    fc.icon = { image("hud_flag", 0.5, 0.0, RACE_FLAGS_Y, 16, 16) }
    fc.cross = { image("hud_x", 0.5, 0.0, RACE_FLAGS_Y, 16, 16) }
    for i = 1, 5 do fc.glyphs[i] = { image("hud_0", 0.5, 0.0, RACE_FLAGS_Y, 16, 16) } end
    for _, g in ipairs({ fc.icon, fc.cross }) do g[1]:SetVisibility(1) end
    for _, g in ipairs(fc.glyphs) do g[1]:SetVisibility(1) end
    h.race_flags = fc
    widget:AddToViewport(50)
    hud = h
end

local function show_number(c, value)
    if c.value == value then return end
    c.value = value
    local text = tostring(math.max(0, math.min(999, math.floor(value))))
    for i, img in ipairs(c.digits) do
        local ch = text:sub(i, i)
        if ch ~= "" then
            local tex = lib.texture(lib.world(), "hud_" .. ch)
            if tex then img:SetBrushFromTexture(tex, false) end
            img:SetVisibility(4)
        else
            img:SetVisibility(1)
        end
    end
end

-- Show `seconds` on the timer (nil: no timer). Only what has changed since the last call is touched.
local function show_time(tm, seconds)
    if not tm then return end
    local on = seconds ~= nil
    if on ~= tm.on then
        tm.on = on
        local vis = on and 4 or 1
        for _, l in ipairs(tm.label) do l.img:SetVisibility(vis) end
        for _, img in ipairs(tm.marks) do img:SetVisibility(vis) end
        if not on then
            for _, place in ipairs(tm.places) do
                if place.shown then place[place.shown]:SetVisibility(1); place.shown = nil end
            end
        end
    end
    if not on then return end
    -- (as many places for the minutes as the HUD has - five: up to 99999 minutes; it stopped at 999, "the timer only
    -- goes to 999minutes increase it please", 2026-10-22 - leading zeros not shown)
    local cs = math.floor(seconds * 100.0)
    local mplaces = #tm.places - 4
    local mins = math.min(math.floor(10 ^ mplaces) - 1, cs // 6000)
    local secs = (cs // 100) % 60
    local digits, wide = {}, 1
    for k = mplaces, 1, -1 do
        local unit = math.floor(10 ^ (k - 1))
        if k == 1 or mins >= unit then
            digits[#digits + 1] = (mins // unit) % 10
            if k > wide then wide = k end
        else
            digits[#digits + 1] = false
        end
    end
    for _, d in ipairs({ secs // 10, secs % 10, (cs // 10) % 10, cs % 10 }) do digits[#digits + 1] = d end
    for p, place in ipairs(tm.places) do
        local d = digits[p] or nil
        if d ~= place.shown then
            if place.shown then place[place.shown]:SetVisibility(1) end
            if d then place[d]:SetVisibility(4) end
            place.shown = d
        end
    end
    -- the word TIME keeps next to the minutes, however many digits they have
    if wide ~= tm.wide then
        tm.wide = wide
        for _, l in ipairs(tm.label) do
            l.slot:SetPosition({ X = (l.x + (3 - wide) * 12.0) * UNIT, Y = tm.y * UNIT })
        end
    end
end

-- The checkpoint count: `taken` of `all` (nil: none shown) - the flag, "x", then 3/7, centred under the meter. Only
-- touched when it changes.
-- CLEAR TIME and `seconds` big in the middle (nil: none): built in hud_build (h.clear_time), laid out here once a time
-- is given - the minutes as many places as they need, the row centred
local function show_clear(gt, seconds)
    if not gt then return end
    if seconds == gt.value then return end
    gt.value = seconds
    local function hide_all()
        for _, img in ipairs(gt.label) do img:SetVisibility(1) end
        for _, m in ipairs(gt.marks) do m.img:SetVisibility(1) end
        for _, place in ipairs(gt.places) do
            if place.shown then place[place.shown]:SetVisibility(1); place.shown = nil end
        end
    end
    hide_all()
    if seconds == nil then return end
    local cs = math.floor(seconds * 100.0)
    local mins = math.min(99999, cs // 6000)
    local secs = (cs // 100) % 60
    -- the glyphs in order: minutes, ', seconds, ", hundredths
    local glyphs = {}
    local mstr = tostring(mins)
    for i = 1, #mstr do glyphs[#glyphs + 1] = { place = i, d = tonumber(mstr:sub(i, i)) } end
    glyphs[#glyphs + 1] = { mark = 1 }
    glyphs[#glyphs + 1] = { place = 6, d = secs // 10 }
    glyphs[#glyphs + 1] = { place = 7, d = secs % 10 }
    glyphs[#glyphs + 1] = { mark = 2 }
    glyphs[#glyphs + 1] = { place = 8, d = (cs // 10) % 10 }
    glyphs[#glyphs + 1] = { place = 9, d = cs % 10 }
    -- (the marks are narrow: half a step each)
    local width = 0.0
    for _, g in ipairs(glyphs) do width = width + (g.mark and 0.5 or 1.0) * CLEAR_STEP end
    local x = -width / 2.0
    for _, g in ipairs(glyphs) do
        local adv = (g.mark and 0.5 or 1.0) * CLEAR_STEP
        local cx = x + adv / 2.0
        if g.mark then
            local m = gt.marks[g.mark]
            m.slot:SetPosition({ X = cx * UNIT, Y = (CLEAR_TIME_Y - CLEAR_SIZE * 7.0 / 16.0) * UNIT })
            m.img:SetVisibility(4)
        else
            local place = gt.places[g.place]
            place.slots[g.d]:SetPosition({ X = cx * UNIT, Y = CLEAR_TIME_Y * UNIT })
            place[g.d]:SetVisibility(4)
            place.shown = g.d
        end
        x = x + adv
    end
    for _, img in ipairs(gt.label) do img:SetVisibility(4) end
end

local function show_flags(fc, taken, all)
    if not fc then return end
    local text = (taken and all) and (tostring(math.min(99, taken)) .. "/" .. tostring(math.min(99, all))) or nil
    if text == fc.text then return end
    fc.text = text
    if not text then
        fc.icon[1]:SetVisibility(1)
        fc.cross[1]:SetVisibility(1)
        for _, g in ipairs(fc.glyphs) do g[1]:SetVisibility(1) end
        return
    end
    -- (as a counter: the picture, the "x" 16 on, the number from 30 on, 12 a place - its whole width centred)
    local width = 30.0 + (#text - 1) * 12.0 + 16.0
    local x0 = METER_X - width / 2.0 + 8.0
    local world = lib.world()
    fc.icon[2]:SetPosition({ X = x0 * UNIT, Y = RACE_FLAGS_Y * UNIT })
    fc.cross[2]:SetPosition({ X = (x0 + 16.0) * UNIT, Y = RACE_FLAGS_Y * UNIT })
    fc.icon[1]:SetVisibility(4)
    fc.cross[1]:SetVisibility(4)
    for i, g in ipairs(fc.glyphs) do
        local ch = text:sub(i, i)
        if ch ~= "" then
            local tex = lib.texture(world, ch == "/" and "hud_slash" or ("hud_" .. ch))
            if tex then g[1]:SetBrushFromTexture(tex, false) end
            g[2]:SetPosition({ X = (x0 + 30.0 + (i - 1) * 12.0) * UNIT, Y = RACE_FLAGS_Y * UNIT })
            g[1]:SetVisibility(4)
        else
            g[1]:SetVisibility(1)
        end
    end
end

-- The star counter's star rainbow, its colours running, once Final Bowser's rainbow star is the file's
-- (menu.lua M.has_rainbow_star): hud_star_rb_0..11, tools/hud_star_rainbow_tex.py, a picture every `step` s - "after
-- the player collects the rainbow star make the star counter star in hud rainbow", 2026-11-04
M.STAR_RB = { n = 12, step = 0.08 }
function M.star_rainbow_tick(hud)
    local c = hud and hud.counters and hud.counters.stars
    local img = c and c.imgs[1]
    if not img then return end
    local menu = _G.MENU
    local on = menu and menu.has_rainbow_star and menu.has_rainbow_star()
    local k = on and (math.floor(os.clock() / M.STAR_RB.step) % M.STAR_RB.n) or -1
    if k == hud.star_rb then return end
    hud.star_rb = k
    local tex = lib.texture(lib.world(), k >= 0 and ("hud_star_rb_" .. k) or "hud_star")
    if tex then img:SetBrushFromTexture(tex, false) end
end

function M.hud_update(dt)
    if not hud_ok() then
        hud = nil
        hud_wait = hud_wait + dt
        if hud_wait < 1.0 then return end        -- let a freshly loaded scene settle before putting widgets up
        hud_wait = 0.0
        pcall(hud_build)
        if not hud then return end
        hud_on = true
    end
    if M.hud_off then
        M.hud_hide()                                    -- (a scene is playing: nothing over the picture)
        -- (but the ending after the Grand Star: the run's clock going on at the top, and while he holds the star up - its
        -- outro - CLEAR TIME in the middle, the time it stood at as he took it: M.grand_time, ending.lua; with the timer
        -- switched on)
        local menu = _G.MENU
        if M.grand_time and menu and menu.timer_on and menu.timer_on() then
            local EN = package.loaded["ending"]
            local st = EN and EN.active and EN.state and EN.state()
            -- (and through Peach's scene: "after beating final bowser have the speedrun timer show the time", 2026-11-04)
            local outro = st and (st.phase == "outro" or st.phase == "peach")
            pcall(function()
                show_time(hud.timer, M.clock or (menu.state == "game" and menu.run_time() or nil))
                show_clear(hud.clear_time, outro and M.grand_time or nil)
            end)
        end
        return
    end
    local w = M.wedges()
    -- Mario 64 drops the meter in whenever it is not full and lifts it away a moment after it fills
    if w < 8 or M.in_water then full_t = 0.0 else full_t = full_t + dt end
    local target = (full_t < 1.5) and SHOWN_Y or HIDDEN_Y
    -- (Mario 64 drops it in low, emphasised, and eases it up into place; it leaves straight up)
    if target == SHOWN_Y and not hud.meter_up then hud.meter_up, hud.y = true, EMPH_Y end
    if target == HIDDEN_Y then hud.meter_up = false end
    hud.y = hud.y + (target - hud.y) * math.min(1.0, dt * 9.0)
    pcall(function()
        if not hud_on then
            hud_on = true
            for _, c in pairs(hud.counters) do for _, img in ipairs(c.imgs) do img:SetRenderOpacity(1.0) end; c.value = -1 end
        end
        if math.abs(hud.y - (hud.drawn_y or -999.0)) > 0.02 then
            hud.drawn_y = hud.y
            for _, p in ipairs(hud.parts) do p.slot:SetPosition({ X = p.dx * UNIT, Y = hud.y * UNIT }) end
        end
        if w ~= hud.shown then
            if hud.pies[hud.shown] then hud.pies[hud.shown]:SetVisibility(1) end
            if hud.pies[w] then hud.pies[w]:SetVisibility(4) end      -- none at all: just the empty meter
            hud.shown = w
        end
        show_number(hud.counters.lives, M.lives)
        show_number(hud.counters.coins, M.coins)
        show_number(hud.counters.stars, M.stars)
        if M.star_rainbow_tick then pcall(M.star_rainbow_tick, hud) end
        -- (gHudFlash: after the course-complete screen's fanfare the star counter blinks, out every 8 frames - complete.lua
        -- sets M.star_flash while it is up)
        local blink = M.star_flash and (math.floor(os.clock() * 30.0) & 8) ~= 0 or false
        if blink ~= (hud.star_blink or false) then
            hud.star_blink = blink
            for _, img in ipairs(hud.counters.stars.imgs) do img:SetRenderOpacity(blink and 0.0 or 1.0) end
        end
        local menu = _G.MENU
        show_time(hud.timer, M.clock or ((menu and menu.timer_on and menu.timer_on() and menu.state == "game") and menu.run_time() or nil))
        -- (Final Bowser beaten: his clear time up from that moment - M.final_clear, bowser_fight M.finale_step - as he
        -- floats in the wind, on into the ending)
        show_clear(hud.clear_time, (M.final_clear and M.grand_time and menu and menu.timer_on and menu.timer_on()) and M.grand_time or nil)
        -- (the race's own, under the meter: race.lua sets them)
        show_time(hud.race_timer, M.race_clock)
        show_flags(hud.race_flags, M.race_flags, M.race_of)
    end)
end

-- The timers alone, while the game is paused (game.lua's pause holds the rest of the HUD with it, and this file's
-- tick): the speedrun timer's and the race's go on, as their clocks do - "the only thing that should still be going
-- when you pause is the actual timer", 2026-10-27. (race.lua calls it: its update is ahead of game.lua's pause.)
function M.timers_tick()
    if not (hud_ok() and hud_on) then return end
    pcall(function()
        local menu = _G.MENU
        show_time(hud.timer, M.clock or ((menu and menu.timer_on and menu.timer_on() and menu.state == "game") and menu.run_time() or nil))
        show_time(hud.race_timer, M.race_clock)
    end)
end

-- Off screen at once (the file select, a scene being torn down).
function M.hud_hide()
    if hud_ok() and hud_on then
        hud.y, hud.drawn_y = HIDDEN_Y, HIDDEN_Y
        hud_on = false
        pcall(function()
            for _, p in ipairs(hud.parts) do p.slot:SetPosition({ X = p.dx * UNIT, Y = HIDDEN_Y * UNIT }) end
            for _, c in pairs(hud.counters) do for _, img in ipairs(c.imgs) do img:SetRenderOpacity(0.0) end end
            show_time(hud.timer, nil)
            show_time(hud.race_timer, nil)
            show_clear(hud.clear_time, nil)
            show_flags(hud.race_flags, nil, nil)
        end)
    end
    full_t = 99.0
end

-- (the map gone - STORROR reloaded it with its menu up: what this keeps of it dropped untouched, main.lua's watch on the
-- map - "crash" twice, 2026-11-03, a moment into the game after that reload: an object of the gone map reached for)
-- (his blink: its parts were the gone athlete's)
function M.forget() blink = nil end

return M
