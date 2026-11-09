-- SM64Map opening: SUPER STORROR 64.
--
-- From the moment the game can draw anything, this covers the screen in black and plays Mario 64's own
-- opening on it: the logo bounces in, the line under it and the TM fade in, and it shrinks away again
-- just before the game moves to the map the mod plays in. STORROR's own start-up logos play out unseen
-- underneath. After the move only the black is put back, until the game's loading screen has cleared
-- and the title screen can open.
--
-- The logo is one picture (textures/title_logo.png): the game's 3D SUPER and 64 drawn from the player's
-- copy, with the STORROR wordmark in place of MARIO. The bounce is the game's: its table of the logo's
-- width and height on each of its frames, 30 a second (data/title_logo.lua).
--
-- The game is still loading when it first draws, and stumbles: a frame can take a tenth of a second or
-- more. Played by the clock, the opening would lose whatever fell inside such a frame (the fade-in of the
-- line under the logo lasts a third of a second, and was simply there after one stumble). So it is not
-- played by the clock. It waits, on black, until the game is drawing evenly, and then moves on by no
-- more than one of Mario 64's frames for every frame the game draws: a stumble makes it pause, not skip.
--
-- Laid out for a 16:9 screen, in pixels of a 1920x1080 one.
local lib = require("lib")
local pad = require("pad")
local log = lib.log

local L = { done = false, gone = false }     -- gone: the logo has left; done: the black can go too
L.leaves_unasked = false                -- set by the menu while a change of map is waiting on the logo: it then
                                        -- leaves when it has had its time, without the game behind being ready

local W, H = 1920.0, 1080.0
local DROP = 85.0                       -- the logo sits this much lower than the game draws it (see make_logo.py)
local PIVOT_Y = (H / 2 + DROP) / H      -- it grows and shrinks about its own middle, not the screen's
-- the game's 320x240 screen sits in the middle 4:3 of this one, 4.5 pixels to each of its own
local function n64(x, y) return 240.0 + x * 4.5 - W / 2, (H - y * 4.5) - H / 2 end

local STEP = 1.0 / 30.0                 -- the most the opening moves on in one drawn frame: one frame of Mario 64's
local EVEN = 0.040                      -- a frame no longer than this (seconds) counts as drawn evenly
local EVEN_FRAMES = 8                   -- this many of them in a row and the opening starts
local HOLD = 2.6                        -- seconds of the opening before the logo shrinks away again. (Mario 64
                                        -- gives it 2.5. It was 1.6 for a while; once STORROR's tips no longer
                                        -- followed it, the user wanted more ("it ends pretty quick"), then tried
                                        -- 3.1 and asked for "a little shorter". About 4 s in all with the wait.)
local MAX_WAIT = 3.0                    -- it starts anyway after this long on black

local anim = nil
local ui, serial = nil, 0
local clock, out_t = nil, nil           -- how far the opening has played (seconds), and where in it the logo began to leave
local waited, even = 0.0, 0
local trace = { dts = {}, alphas = 0, stumbles = {} }     -- (how it went, for the log)
L.trace = trace
local last_now = nil

local function ui_ok()
    if not ui then return false end
    local ok, v = pcall(function() return ui.world == lib.world():GetAddress() and ui.widget:IsValid() end)
    return ok and v
end

local function build()
    local world, pc = lib.world(), lib.controller()
    if not (world and pc) then return end
    local function cls(p) return StaticFindObject(p) end
    serial = serial + 1
    local n = tostring(serial)
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("SM64Logo" .. n))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("SM64LogoTree" .. n))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SM64LogoCanvas" .. n))
    tree.RootWidget = canvas
    local count = 0
    local function image(file)
        count = count + 1
        local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("SM64LogoImg" .. n .. "_" .. count))
        local tex = lib.texture(world, file)
        if tex then img:SetBrushFromTexture(tex, false) end
        return img, canvas:AddChildToCanvas(img)
    end
    -- centre (x, y) from the middle of the screen, y down
    local function placed(file, x, y, w_, h_)
        local img, slot = image(file)
        slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
        slot:SetAlignment({ X = 0.5, Y = 0.5 })
        slot:SetSize({ X = w_, Y = h_ })
        slot:SetPosition({ X = x, Y = y })
        return img
    end
    -- black from edge to edge, whatever shape the screen is
    local _, bslot = image("menu_black")
    bslot:SetAnchors({ Minimum = { X = 0.0, Y = 0.0 }, Maximum = { X = 1.0, Y = 1.0 } })
    bslot:SetOffsets({ Left = 0.0, Top = 0.0, Right = 0.0, Bottom = 0.0 })

    local logo = placed("title_logo", 0.0, 0.0, W, H)
    pcall(function() logo:SetRenderTransformPivot({ X = 0.5, Y = PIVOT_Y }) end)
    local x0, y0 = n64(96, 58)                  -- the line under the logo: 128x16 of the game's pixels
    local copy = placed("title_copyright", x0 + 288.0, y0 + 36.0, 576.0, 72.0)
    local x1, y1 = n64(268, 196)                -- the TM: 16x16
    local tm = placed("title_tm", x1 + 36.0, y1 + 36.0 + DROP, 72.0, 72.0)
    if L.gone then
        for _, img in ipairs({ logo, copy, tm }) do img:SetVisibility(1) end
    else
        -- nothing of it shows until it starts to play
        pcall(function()
            logo:SetRenderScale({ X = 0.0, Y = 0.0 })
            copy:SetRenderOpacity(0.0)
            tm:SetRenderOpacity(0.0)
        end)
    end
    w:AddToViewport(30000)
    ui = { widget = w, world = world:GetAddress(), logo = logo, copy = copy, tm = tm, built = os.clock() }
end

-- a width and height from one of the game's tables, at (fractional) frame f
local function at(tbl, f)
    local i = math.floor(f)
    local a, b = tbl[math.min(#tbl, i + 1)], tbl[math.min(#tbl, i + 2)]
    local k = f - i
    return a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k
end

function L.close()
    if ui then pcall(function() ui.widget:RemoveFromParent() end) end
    ui = nil
end

-- how much of the opening has played, in seconds (nil: it has not started)
function L.shown_for() return clock end

-- Send the logo away now (the game is about to change maps). `L.gone` turns true when it has shrunk to nothing.
function L.leave()
    if L.gone or out_t then return end
    if not clock then L.gone = true; return end     -- it never got on screen
    out_t = clock
end

-- Every tick while the game is starting. `ready`: the game behind is ready for the title screen.
-- Returns "done" once the title screen may open (at once, every time after the first).
-- STORROR's own start-up goes on behind the logo, on its start map: of it, only its splash is to be heard
-- (storror_logo_intro, the two whistles) and nothing after - not the map's music, its LED screens, the athlete's wind
-- and sliding, which came in whenever the logo stayed up a while (2026-10-15: "what we want to hear is the two
-- whistles and no audio after that"). Every fifth of a second while the logo is up, every sound playing is turned
-- down to nothing but the splash's own while it plays. Only on that map, while it is there: nothing is kept.
local hush_t, splash_seen, splash_over = 0.0, false, false
local hushed = {}                       -- the names of the players turned down, to be turned back up once the logo is gone
                                        -- (by the player, not its sound: STORROR's songs move on to the next one)
local function hush(dt)
    hush_t = hush_t - dt
    if hush_t > 0.0 then return end
    hush_t = 0.2
    local splash = false
    for _, mp in ipairs(FindAllOf("MediaPlayer") or {}) do
        pcall(function()
            if mp:IsValid() and mp:GetFName():ToString() == "SplashMediaPlayer" and mp:IsPlaying() then splash = true end
        end)
    end
    -- (a film's sound plays through a "synth" of its own: those are left alone until the splash has played and
    -- finished - it might not have started yet when the logo comes up)
    if splash then splash_seen = true elseif splash_seen then splash_over = true end
    for _, ac in ipairs(FindAllOf("AudioComponent") or {}) do
        pcall(function()
            if ac:IsValid() and ac:IsPlaying() then
                local snd = (ac.Sound and ac.Sound:IsValid()) and ac.Sound:GetFName():ToString() or ""
                if not (snd:find("^SynthSound") and not splash_over) then
                    ac:SetVolumeMultiplier(0.0)
                    hushed[ac:GetFName():ToString()] = true
                end
            end
        end)
    end
end

function L.tick(dt, ready)
    if L.done then return "done" end
    if not L.gone then pcall(hush, dt) end
    if not anim then
        anim = lib.load_data("data.title_logo")
        if not anim then L.gone, L.done = true, true; return "done" end
    end
    if not ui_ok() then
        ui = nil
        pcall(build)
        if not ui then return nil end           -- nothing to draw on yet
    end
    local now = os.clock()
    local took = last_now and (now - last_now) or dt        -- how long this frame really took
    last_now = now
    if not trace.from then trace.from = now end
    if took > 0.06 and #trace.stumbles < 40 then
        trace.stumbles[#trace.stumbles + 1] = string.format("%.2f:%.0f", now - trace.from, took * 1000.0)
    end
    if L.gone then
        -- only the black now: wait for the game behind, and for its own loading screen to clear
        if ready and now - ui.built > 1.3 then
            L.done = true
            -- (the logo gone, what was turned down and is still playing - STORROR's songs, which carry on past the
            -- start map - back as it was: the title is not to change, 2026-10-15. Found by name on this map.)
            local back, names = 0, {}
            for name in pairs(hushed) do names[#names + 1] = name end
            pcall(function()
                for _, ac in ipairs(FindAllOf("AudioComponent") or {}) do
                    pcall(function()
                        if ac:IsValid() and hushed[ac:GetFName():ToString()] then ac:SetVolumeMultiplier(1.0); back = back + 1 end
                    end)
                end
            end)
            log("logo: %d of %d sounds turned down behind it back up (%s)", back, #names, table.concat(names, ", "))
            return "done"                       -- (the caller takes the black away once the next screen is up)
        end
        return nil
    end
    if not clock then
        waited = waited + took
        even = (took <= EVEN) and (even + 1) or 0
        if even < EVEN_FRAMES and waited < MAX_WAIT then return nil end
        clock = 0.0
        trace.waited = waited
    else
        clock = clock + math.min(dt, STEP)
        if #trace.dts < 900 then trace.dts[#trace.dts + 1] = took end
    end
    local f = clock * 30.0
    local sx, sy = 1.0, 1.0
    local alpha = math.max(0.0, math.min(1.0, (f - anim.fade_from) * anim.fade_step / 255.0))
    if out_t then
        local g = (clock - out_t) * 30.0
        if g >= #anim.zoom_out - 1 then
            L.gone = true
            local longest, slow = 0.0, 0
            for _, d in ipairs(trace.dts) do
                if d > longest then longest = d end
                if d > 0.05 then slow = slow + 1 end
            end
            log("opening: %.2f s in all; waited %.2f s for the game to draw evenly; played over %d frames (longest %.0f ms, %d over 50 ms); the line faded in over %d",
                now - trace.from, trace.waited or -1.0, #trace.dts, longest * 1000.0, slow, trace.alphas)
            pcall(function() for _, img in ipairs({ ui.logo, ui.copy, ui.tm }) do img:SetVisibility(1) end end)
            return nil
        end
        sx, sy = at(anim.zoom_out, g)
        alpha = alpha * (1.0 - g / (#anim.zoom_out - 1))
    elseif f < #anim.zoom_in - 1 then
        sx, sy = at(anim.zoom_in, f)
    end
    pcall(function()
        ui.logo:SetRenderScale({ X = sx, Y = sy })
        if alpha ~= ui.alpha then
            ui.alpha = alpha
            if not out_t and alpha > 0.0 and alpha < 1.0 then trace.alphas = trace.alphas + 1 end
            ui.copy:SetRenderOpacity(alpha)
            ui.tm:SetRenderOpacity(alpha)
        end
    end)
    -- it leaves once it has had its time (or when Start is pressed)
    local skip = pad.pressed("start")
    if (ready or L.leaves_unasked) and not out_t and (clock >= HOLD or (skip and f >= #anim.zoom_in)) then out_t = clock end
    return nil
end

return L
