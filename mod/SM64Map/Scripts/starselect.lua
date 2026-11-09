-- SM64Map star select: Mario 64's act selector (src/menu/star_select.c, levels/menu script level_main_menu_entry_2),
-- between a painting and its course. A white screen; a row of stars, gold for each one won and see-through for those
-- not, the one picked a third bigger and turning; its number over each, the picked act's name under them, MY SCORE
-- and the coins (when there are any), the wooden COURSE plaque with the number and the course's name at the foot.
-- Left and right pick among the stars won and the first not yet won (handle_menu_scrolling); A or Start chooses, to
-- "Let's-a go!". The course is then entered at that act. Before, the first star not won was taken without asking.
--
-- The stars are the game's own models in front of a camera of this screen's own, far from the levels (as the title
-- screen's head is); the words are pictures of the game's font (exporter/starselx.py), laid out on Mario 64's
-- 320 x 240 screen, made as tall as ours and set in its middle.
local lib = require("lib")
local pad = require("pad")
local log = lib.log
local M = { active = false }

local BASE = { X = 2000000.0, Y = -600000.0, Z = lib.OFFSET.Z }      -- nowhere near the levels, the title or the menus
local U = 0.75                      -- cm a Mario 64 unit (the models are made at it)
local K = 4                         -- the word pictures' pixels to one of Mario 64's
local st = nil

local function valid(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end
local function sound(name) local S = package.loaded["sfx"]; if S then pcall(S.play, name) end end

-- which stars of the course are won: Mario 64's star flags for it, as menu.lua keeps them ("bob:0" .. "bob:5")
local function won(scene)
    local MN = _G.MENU
    local out = {}
    for i = 0, 5 do
        local got = false
        if MN and MN.has_star then
            for _, p in ipairs({ scene, scene .. "_2", scene .. "_3", scene .. "_4" }) do
                if MN.has_star(p .. ":" .. i) then got = true end
            end
        end
        out[i + 1] = got
    end
    return out
end

-- (bhv_act_selector_init) how many stars show, which act is offered first
local function lay_out(stars)
    local obtained = 0
    for i = 1, 6 do if stars[i] then obtained = obtained + 1 end end
    local visible, init, sel = 0, 0, 0
    local i = 0
    while i ~= obtained do
        if stars[visible + 1] then i = i + 1
        elseif init == 0 then init, sel = visible + 1, visible end
        visible = visible + 1
    end
    if visible == obtained and visible ~= 6 then
        init, sel = visible + 1, visible
        visible = visible + 1
    end
    if obtained == 6 then init = visible end
    if obtained == 0 then init = 1 end
    return visible, init, sel, obtained
end

-- how many stars there are to pick from (and the extra one, game.lua G.EXTRA_STARS)
local function selectable_count(s) return ((s.obtained == 6) and s.visible or (s.obtained + 1)) + (s.extra and 1 or 0) end

-- (bhv_act_selector_loop) the act behind the `sel`-th selectable star
local function act_of(s, sel)
    -- (the course's extra star - game.lua G.EXTRA_STARS - last of all)
    if s.extra and sel == selectable_count(s) - 1 then return s.extra.act end
    if s.obtained == 6 then return sel + 1 end
    local n = sel
    for i = 1, s.visible do
        if s.stars[i] or i == s.init then
            if n == 0 then return i end
            n = n - 1
        end
    end
    return s.init
end


-- the athlete's controls held while the screen is up (A is STORROR's jump: its parkour inputs have their own switch)
local LOCK = "SM64StarSelect"
local function lock(on)
    local pc, pawn = lib.controller(), lib.pawn()
    if not (pc and pawn) then return end
    pcall(function() pc:SetIgnoreMoveInput(on) end)
    pcall(function() if on then pawn:DisableInput(pc) else pawn:EnableInput(pc) end end)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetClass():GetFName():ToString() == "ParkourComponent" then
                o:ClearInputQueue()
                o:EnableAllParkourInputs(FName(LOCK), not on)
            end
        end
    end)
end

-- STORROR's action wheel kept shut while the screen is up: D-pad Right, the press that picks the next star, opened it
-- over the stars ("make sure the storror wheel doesnt pop up in the star select menu (right d-pad)", 2026-11-05). The
-- lock above does not reach it (pause.lua has the same): a hook turns its show into a hide while the screen is up
-- (M.active), and one open all the same is shut each tick through the same function.
pcall(function()
    if _G.SM64_STARSEL_WHEEL_HOOK then return end
    _G.SM64_STARSEL_WHEEL_HOOK = true
    RegisterHook("/Script/SPP.ActionWheelComponent:ShowActionWheelCallback", function(_, show)
        local S = package.loaded["starselect"]
        if not (S and S.active) then return end
        local was = nil
        pcall(function() was = show:get() end)
        if was then
            pcall(function() show:set(false) end)
            log("star select: STORROR's action wheel kept shut")
        end
    end)
end)

-- (his action wheel: found once as the screen goes up, its widget asked each tick whether it is open)
local function wheel_of(pawn)
    local found = nil
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetClass():GetFName():ToString() == "ActionWheelComponent" then found = o end
        end
    end)
    return found
end

local function shut_wheel(s)
    local c = s.wheel
    if not valid(c) then return end
    pcall(function()
        local w = c.ActionWheelWidget
        if w and w:IsValid() and w.bWheelOpened then
            c:ShowActionWheelCallback(false)
            log("star select: STORROR's action wheel shut")
        end
    end)
end

-- ------------------------------------------------------------ the words
local function make_ui(s, world, pc)
    local function cls(p) return StaticFindObject(p) end
    _G.SM64_STARSEL_SERIAL = (_G.SM64_STARSEL_SERIAL or 0) + 1
    local n = tostring(_G.SM64_STARSEL_SERIAL)
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("SM64StarSel" .. n))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("SM64StarSelTree" .. n))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SM64StarSelCanvas" .. n))
    tree.RootWidget = canvas
    local size = { X = 1920.0, Y = 1080.0 }
    pcall(function()
        local WLL = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        local vs, sc = WLL:GetViewportSize(world), WLL:GetViewportScale(world)
        if vs and sc and sc > 0 then size = { X = vs.X / sc, Y = vs.Y / sc } end
    end)
    local px = size.Y / 240.0                      -- slate units to one of Mario 64's pixels
    local x0 = (size.X - 320.0 * px) / 2.0
    local count = 0
    -- a picture at (x, y) in Mario 64's pixels (its top left), `w` x `h` of them
    local function pic(file, x, y, wpx, hpx)
        count = count + 1
        local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("SM64StarSelImg" .. n .. "_" .. count))
        local tex = lib.texture(world, file)
        if not tex then return nil end
        img:SetBrushFromTexture(tex, false)
        local slot = canvas:AddChildToCanvas(img)
        slot:SetAnchors({ Minimum = { X = 0.0, Y = 0.0 }, Maximum = { X = 0.0, Y = 0.0 } })
        slot:SetPosition({ X = x0 + x * px, Y = y * px })
        slot:SetSize({ X = wpx * px, Y = hpx * px })
        return img, slot
    end
    -- a word picture's own size, in Mario 64's pixels
    local function wsize(file)
        local tex = lib.texture(world, file)
        local w2, h2 = 0, 16
        pcall(function() w2, h2 = tex:Blueprint_GetSizeX() / K, tex:Blueprint_GetSizeY() / K end)
        return w2, h2
    end
    local ui = { widget = w, pic = pic, wsize = wsize }
    -- the numbers over the stars (print_menu_generic_string at 122 - (n - 1) * 17 + i * 34, 38)
    for i = 1, s.visible do
        local f = "starsel_num_" .. i
        local ww, hh = wsize(f)
        pic(f, 122 - ((s.row or s.visible) - 1) * 17 + i * 34, 38 - 4, ww, hh)
    end
    if s.extra then
        local f = "starsel_num_" .. s.extra.act
        local ww, hh = wsize(f)
        pic(f, 122 - ((s.row or s.visible) - 1) * 17 + s.xi * 34, 38 - 4, ww, hh)
    end
    -- MY SCORE and the coins (print_hud_my_score_coins at 155, 106), when there is a score
    if (s.score or 0) > 0 then
        local ww, hh = wsize("starsel_myscore")
        pic("starsel_myscore", 102, 240 - 118 - 16, ww, hh)
        pic("hud_coin", 155, 106, 16, 16)
        pic("hud_x", 155 + 16, 106, 16, 16)
        local digits = tostring(s.score)
        for k = 1, #digits do pic("hud_" .. digits:sub(k, k), 155 + 32 + (k - 1) * 12, 106, 16, 16) end
    end
    -- the course's extra star's best finish (race.lua M.best, seconds), over the COURSE plaque - Mario 64's race time,
    -- M'SS"CC in the HUD's digits; none yet, its noughts faint. Shown only with that star picked (show_act): "but only
    -- show it when hovering over the 7th star", then "I want it above the course thing actually", 2026-10-27. (The
    -- plaque and the course's name down 16 to make room under MY SCORE.)
    local drop = s.extra and 16 or 0
    if s.extra then
        local R = package.loaded["race"]
        local best = R and R.best and R.best(s.scene)
        local cs = math.floor((best or 0) * 100.0 + 0.5)
        local text = string.format("%d'%02d\"%02d", cs // 6000, (cs // 100) % 60, cs % 100)
        local x = 158 - #text * 6
        ui.timer = { imgs = {}, opacity = best and 1.0 or 0.35 }
        for k = 1, #text do
            local c = text:sub(k, k)
            local f = (c == "'" and "hud_apos") or (c == '"' and "hud_quote") or ("hud_" .. c)
            local img = pic(f, x + (k - 1) * 12, 125, 16, 16)
            if img then
                pcall(function() img:SetRenderOpacity(0.0) end)
                ui.timer.imgs[#ui.timer.imgs + 1] = img
            end
        end
    end
    -- the plaque (dl_menu_rgba16_wood_course about (158, 81) from the foot, 64 x 64) and the number on it
    pic("menu_course_plaque", 158 - 32, 240 - 81 - 32 + drop, 64, 64)
    local num = tostring(s.course.num)
    local nx = (#num == 1) and 152 or 143
    for k = 1, #num do pic("hud_" .. num:sub(k, k), nx + (k - 1) * 12, 158 + drop, 16, 16) end
    -- the course's name, centred at 160, 33 from the foot
    local cf = "starsel_course_" .. s.course.num
    local cw, ch = wsize(cf)
    pic(cf, 160 - cw / 2.0, 240 - 33 - 16 + drop, cw, ch)
    -- the picked act's name, centred at 163, 81 down: one picture per act, shown in turn
    ui.acts = {}
    for i = 1, s.visible do
        local f = "starsel_act_" .. s.course.num .. "_" .. i
        local aw, ah = wsize(f)
        local img = pic(f, 163 - aw / 2.0, 81 - 4, aw, ah)
        if img then pcall(function() img:SetRenderOpacity(0.0) end) end
        ui.acts[i] = img
    end
    if s.extra then
        local f = "starsel_act_" .. s.course.num .. "_" .. s.extra.act
        local aw, ah = wsize(f)
        local img = pic(f, 163 - aw / 2.0, 81 - 4, aw, ah)
        if img then pcall(function() img:SetRenderOpacity(0.0) end) end
        ui.acts[s.extra.act] = img
    end
    w:AddToViewport(60)
    return ui
end

local function show_act(s)
    for i, img in pairs(s.ui and s.ui.acts or {}) do
        pcall(function() img:SetRenderOpacity(i == s.act and 1.0 or 0.0) end)
    end
    local tm = s.ui and s.ui.timer
    if tm then
        local o = (s.extra and s.act == s.extra.act) and tm.opacity or 0.0
        for _, img in ipairs(tm.imgs) do pcall(function() img:SetRenderOpacity(o) end) end
    end
end

-- its tune (SEQ_MENU_STAR_SELECT)
function M.play_music()
    local MU = package.loaded["music"]
    if MU and MU.play then pcall(MU.play, "menu_star_select") end
end

-- ------------------------------------------------------------ open, tick, close
-- `scene` the course entered; `done(act)` once an act is chosen (the screen is then white, and closed by the caller)
function M.open(scene, done)
    local data = lib.load_data("data.starselect")
    local course = data and data.courses and data.courses[scene]
    local world, pc = lib.world(), lib.controller()
    if not (course and world and pc) then return false end
    M.close()
    local stars = won(scene)
    local visible, init, sel, obtained = lay_out(stars)
    local MN = _G.MENU
    local score = 0
    -- (the files keep each course's coin score by its number - menu.lua note_coins: [1] for Bob-omb Battlefield - not by
    -- its scene's name, which always read 0: MY SCORE never showed, and the 100-coin star stood alone)
    pcall(function() score = MN.coin_score(course.num) or MN.coin_score(scene) or 0 end)
    if score == 0 then pcall(function() score = MN.coin_score(scene) or 0 end) end
    -- (the 100-coin star won: Mario 64's seventh star beside MY SCORE - put in the row for a while, then "apparently I
    -- was wrong about the star placement", 2026-10-17)
    local coin_won = false
    pcall(function()
        for _, p in ipairs({ scene, scene .. "_2", scene .. "_3", scene .. "_4" }) do
            if MN and MN.has_star and MN.has_star(p .. ":6") then coin_won = true end
        end
    end)
    -- (and its extra star past the six, if it has one - game.lua G.EXTRA_STARS: last in the row, always to be picked)
    local G = package.loaded["game"]
    local extra = G and G.EXTRA_STARS and G.EXTRA_STARS[scene]
    local extra_won = false
    if extra and MN and MN.has_star then pcall(function() extra_won = MN.has_star(scene .. ":" .. extra.star) end) end
    -- (to be seen only once every star before it is won - the six and the 100 coins' - or once it is itself: "should
    -- only be able to see the 7th race star if you completed all stars before it", 2026-10-27)
    if extra and not extra_won and not (obtained == 6 and coin_won) then extra = nil end
    local s = { world = world:GetAddress(), scene = scene, course = course, stars = stars, visible = visible,
                row = visible + (extra and 1 or 0), coin_won = coin_won, extra = extra, xi = visible + 1,
                init = init, sel = sel, obtained = obtained, score = score, done = done, t = 0.0, models = {},
                repeat_t = 0.0 }
    s.act = act_of(s, s.sel)

    -- the white
    local back = lib.spawn_actor(world, { X = BASE.X + 4000.0, Y = BASE.Y, Z = BASE.Z }, 0.0)
    local bpmc = back and lib.add_pmc(back)
    if bpmc then
        pcall(function() bpmc:SetCollisionEnabled(0) end)
        local n = { X = -1.0, Y = 0.0, Z = 0.0 }
        local white = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
        local uv = { X = 0.5, Y = 0.5 }
        local q = { { X = 0.0, Y = -8000.0, Z = -5000.0 }, { X = 0.0, Y = 8000.0, Z = -5000.0 },
                    { X = 0.0, Y = 8000.0, Z = 5000.0 }, { X = 0.0, Y = -8000.0, Z = 5000.0 } }
        lib.create_section(bpmc, 0, q, { 0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2 }, { n, n, n, n }, { uv, uv, uv, uv },
            { white, white, white, white }, false)
        local mid = lib.get_mid(world, "opaque", "white")
        if mid then bpmc:SetMaterial(0, mid) end
    end
    s.back = back

    -- the stars ((n - 1) * -75 + i * 152 across, 248 up, 1300 from the camera, in Mario 64's units)
    local gold, clear = lib.load_data("data.actor_star"), lib.load_data("data.actor_transparent_star")
    for i = 1, visible do
        local model = (stars[i] and gold) or clear or gold
        local x = ((s.row - 1) * -75 + (i - 1) * 152) * U
        local loc = { X = BASE.X + 1300.0 * U, Y = BASE.Y + x, Z = BASE.Z + 248.0 * U }
        local inst = model and lib.make_instance(world, model, loc, 0.0, 1.0)
        s.models[i] = { inst = inst, loc = loc, size = 1.0, yaw = 0.0 }
    end
    if extra then
        local model = (extra_won and gold) or clear or gold
        local x = ((s.row - 1) * -75 + (s.xi - 1) * 152) * U
        local loc = { X = BASE.X + 1300.0 * U, Y = BASE.Y + x, Z = BASE.Z + 248.0 * U }
        local inst = model and lib.make_instance(world, model, loc, 0.0, 1.0)
        s.models[s.xi] = { inst = inst, loc = loc, size = 1.0, yaw = 0.0, act = extra.act }
    end
    -- the 100-coin star, won: right of MY SCORE's coins, a little smaller and always turning (Mario 64's
    -- render_100_coin_star: at 370, 24 in the stars' own space, size 0.8, STAR_SELECTOR_100_COINS turns 0x800 a
    -- frame - "where's the 7th star for 100 coins?", 2026-10-17); not one to pick
    if s.coin_won and gold then
        local loc = { X = BASE.X + 1300.0 * U, Y = BASE.Y + 370.0 * U, Z = BASE.Z + 24.0 * U }
        local inst = lib.make_instance(world, gold, loc, 0.0, 0.8)
        if inst then s.coin_star = { inst = inst, loc = loc, yaw = 0.0 } end
    end

    -- the camera (45 degrees high, as Mario 64's: across, as wide as the screen makes it)
    local cam = lib.camera(world, "star_select", BASE, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
    if valid(cam) then
        local aspect = 16.0 / 9.0
        pcall(function()
            local WLL = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
            local vs = WLL:GetViewportSize(world)
            if vs and vs.Y > 0 then aspect = vs.X / vs.Y end
        end)
        pcall(function() cam.CameraComponent:SetFieldOfView(2.0 * math.deg(math.atan(math.tan(math.rad(22.5)) * aspect))) end)
        pcall(function()
            local pp = cam.CameraComponent.PostProcessSettings
            pp.bOverride_AutoExposureMinBrightness, pp.bOverride_AutoExposureMaxBrightness = true, true
            pp.AutoExposureMinBrightness, pp.AutoExposureMaxBrightness = -3.5, -3.5      -- (white comes out white)
            pp.bOverride_AutoExposureBias, pp.AutoExposureBias = true, 0.0
        end)
        pcall(function() pc:SetViewTargetWithBlend(cam, 0.0, 0, 0.0, false) end)
        s.cam = cam
    end
    local okui, ui = pcall(make_ui, s, world, pc)
    if okui then s.ui = ui else log("star select: words failed: %s", tostring(ui)) end
    show_act(s)
    if _G.HEALTH then _G.HEALTH.hud_off = true end
    lock(true)
    s.locked = true
    s.wheel = wheel_of(lib.pawn())
    shut_wheel(s)
    M.play_music()
    pad.reset()
    st = s
    M.active = true
    log("star select: %s, %d stars shown, act %d offered", scene, visible, s.act)
    return true
end

function M.close()
    local s = st
    st = nil
    M.active = false
    if not s then return end
    local same = false
    pcall(function() same = lib.world():GetAddress() == s.world end)
    if not same then return end
    if s.ui then pcall(function() s.ui.widget:RemoveFromParent() end) end
    for _, m in ipairs(s.models) do if m.inst then lib.destroy(m.inst.actor) end end
    if s.coin_star and s.coin_star.inst then lib.destroy(s.coin_star.inst.actor) end
    lib.destroy(s.back)
    local pc, pawn = lib.controller(), lib.pawn()
    if pc and pawn then pcall(function() pc:SetViewTargetWithBlend(pawn, 0.0, 0, 0.0, false) end) end
    -- (its camera stays: lib.camera)
    if _G.HEALTH then _G.HEALTH.hud_off = false end
    if s.locked then lock(false) end
end

-- the map went: its things with it, forget them untouched
function M.forget() st = nil; M.active = false end

function M.tick(dt)
    local s = st
    if not s then return end
    local here = nil
    pcall(function() here = lib.world():GetAddress() end)
    if here ~= s.world then st = nil; M.active = false; return end
    s.t = s.t + dt
    shut_wheel(s)
    if s.chosen then return end
    -- left and right (the stick too, repeating while held, as handle_menu_scrolling does)
    local sx = pad.sticks()
    local step = 0
    if pad.pressed("left") then step = -1 elseif pad.pressed("right") then step = 1 end
    if step == 0 and math.abs(sx) > 0.5 then
        s.repeat_t = s.repeat_t - dt
        if s.repeat_t <= 0.0 then step = sx > 0 and 1 or -1; s.repeat_t = s.stick_held and 0.2 or 0.4 end
        s.stick_held = true
    elseif math.abs(sx) <= 0.5 then
        s.stick_held, s.repeat_t = false, 0.0
    end
    if step ~= 0 then
        local n = selectable_count(s)
        local new = math.max(0, math.min(n - 1, s.sel + step))
        if new ~= s.sel then
            s.sel = new
            s.act = act_of(s, s.sel)
            show_act(s)
            sound("menu_change_select")
        end
    end
    -- the stars: the picked one grows to 1.3 and turns 0x800 a frame; the others shrink back and face ahead
    local frames = dt * 30.0
    for i, m in ipairs(s.models) do
        if m.inst then
            if (m.act or i) == s.act then
                m.size = math.min(1.3, m.size + 0.1 * frames)
                m.yaw = (m.yaw + 11.25 * frames) % 360.0
            else
                m.size = math.max(1.0, m.size - 0.1 * frames)
                m.yaw = 0.0
            end
            pcall(function()
                m.inst.actor:K2_TeleportTo(m.loc, { Pitch = 0.0, Yaw = m.yaw, Roll = 0.0 })
                m.inst.actor:SetActorScale3D({ X = m.size, Y = m.size, Z = m.size })
            end)
        end
    end
    local cs = s.coin_star
    if cs and cs.inst then
        cs.yaw = (cs.yaw + 11.25 * frames) % 360.0
        pcall(function() cs.inst.actor:K2_TeleportTo(cs.loc, { Pitch = 0.0, Yaw = cs.yaw, Roll = 0.0 }) end)
    end
    if s.t > 0.4 and (pad.pressed("ok") or pad.pressed("start")) then
        s.chosen = true
        sound("menu_lets_a_go")
        log("star select: act %d chosen", s.act)
        if s.done then pcall(s.done, s.act) end
    end
end

return M
