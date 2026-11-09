-- SM64Map title screen: Mario's head, to be pulled about, as on Mario 64's own title screen.
--
-- The head is the game's: six shapes and the joints its skin hangs on, read from the player's copy by the
-- exporter (data/mario_head.lua). A hand cursor moves with either stick, the d-pad or the arrow keys.
-- Holding the grab button near part of the face takes hold of the nearest joint; dragging pulls that
-- joint, and every point of skin tied to it follows by its weight. Let go and the joint springs back,
-- overshooting and wobbling to rest. Left alone, the head turns to keep the hand in view, its eyes follow
-- it, and it blinks. Behind it plays STORROR's own start film, and the head nods to the beat of the film's
-- music. Start goes on to the file select.
--
-- Laid out for a 16:9 screen: positions are in pixels of a 1920x1080 screen, centre (0, 0), y up.
local lib = require("lib")
local pad = require("pad")
local log = lib.log

local T = { active = false }

-- Mario 64's face screen sounds (rendered from the player's ROM, see sfx.lua): "Hello!" as the face comes up, a
-- pinch on taking hold, the snap of letting go, and the star sound for Start
local okS, SFX = pcall(require, "sfx")
if not okS then SFX = nil end
local function sound(name) if SFX then pcall(SFX.play, name) end end

local sin, cos, tan, atan, sqrt, floor, abs, rad, deg, pi = math.sin, math.cos, math.tan, math.atan, math.sqrt, math.floor, math.abs, math.rad, math.deg, math.pi
local max, min = math.max, math.min

-- ------------------------------------------------------------ the stage
local BASE = { X = 2000000.0, Y = 600000.0, Z = lib.OFFSET.Z }      -- nowhere near the levels or the file select
local FOV = 34.0                    -- a long lens, as the original has: little bulging of the nose
local K = tan(rad(FOV / 2.0))
local D = 4000.0                    -- camera to the middle of the head
local PX = D * K / 960.0            -- world units to a screen pixel, at the head
local HEAD_PX = 800.0               -- how tall the head stands on the screen
local HEAD_UP = 26.0                -- and how far above the middle of the screen its middle is
local HEAD_H, HEAD_MID = 1152.0, 194.0      -- its height in its own units, and the height of its middle
local S = HEAD_PX * PX / HEAD_H     -- head units -> world units
local HAND_D = D - 900.0            -- the hand floats in front of the head
local HAND_PX = HAND_D * K / 960.0
local HAND_SIZE = 120.0             -- pixels across

-- how it handles
local CURSOR_SPEED = 1100.0         -- pixels a second at full stick
local KEY_SPEED = 700.0
local REACH = 130.0                 -- how near (pixels) the hand has to be to a part to take hold of it
local MAX_PULL = 430.0              -- furthest a joint can be dragged, in head units
local SPRING, DAMP = 250.0, 7.0     -- pulls a let-go joint home, and how fast its wobble dies
local TURN_YAW, TURN_PITCH = 20.0, 13.0     -- how far the head turns to follow the hand (degrees)
local EYE_YAW, EYE_PITCH = 9.0, 7.0
local BLINK_ANGLE = 21.0
local NOT_FOR_GRABBING = { eyelid_r = true, eyelid_l = true, left_eye_joint_1 = true }
local LIGHT = { 0.30, 0.52, 0.80 }  -- where the light comes from, in the head's own space
local AMBIENT, DIFFUSE = 0.58, 0.52
local EXPOSURE = -0.3               -- fixed, so a dark backdrop does not make the game brighten the head to white

local st = nil                      -- everything built for the open screen

-- ------------------------------------------------------------ the film behind the head
-- STORROR plays a film behind its own start screen. The same film plays behind Mario's head here, with
-- its music, and goes on into the file select (film.lua has the playing of it).
local okF, FILM = pcall(require, "film")
if not okF then log("the film did not load: %s", tostring(FILM)); FILM = nil end
local FILM_DIM = 0.55               -- the film is shown this bright, so the head stands out from it
-- The film fills the screen, except while the word STORROR is on it: the film opens with that word across
-- half its width for two seconds and closes with it for four. For those spells (which run together when
-- the film goes round) it draws back behind the head, to the largest size at which the head, facing
-- forward, still covers the word (see fit_film.py: 0.616 of the screen's width; a little under, for the bob).
local FILM_FULL = 1.08              -- its width as a share of the screen's, when it fills it
local FILM_SMALL = 0.60             -- and while the word is up
local FILM_DELAY = 2.4              -- seconds before it starts: the head's arrival (1.4 s) and his "Hello!" over first
local HELLO_AT = 0.8                -- seconds (of the title's own clock) before his "Hello!": the sound players under way
                                    -- by then (sfx.warm), a second or so after they were made

-- Nodding to the music. The beats of the film's music are found ahead of time by the exporter
-- (data/title_beats.lua: when each one falls, and how hard it hits). The head comes down on every beat
-- and lifts between them: slowly up, quickly down, the way a head is banged.
local BANG_PITCH = 18.0             -- degrees the head comes down on the hardest beats
local BANG_SOFT = 0.55              -- the softest beats get this share of it
local BANG_DROP = 14.0              -- pixels the head dips as it comes down
local BANG_UP = 0.6                 -- share of the time between beats spent lifting; the rest is the drop
local BANG_REST = 0.3               -- how far down (0..1) the head's own level is: it lifts above it too
local BANG_LEAD = 0.02              -- seconds the head runs ahead of the film's clock
local BANG_QUIET = 0.35             -- while the film is drawn back behind the head, it nods only this much
local LOOK_RIGHT = 5.0              -- degrees the head is turned toward the right of the screen
-- (and still while the film's music stops for its people to talk - 28.4 to 35.4 s and 52.7 to 60.6 s, where its beat drops
-- out under the voices and comes back - its head rolling over onto its top as they start, and on round to upright as the
-- music comes back. "during the song when people start talking and the music stops make mario stop head banging",
-- "during that time make marios head spin upside down then back to the upright position", 2026-10-20; placed by ear:
-- "the first time mario goes upside down needs removed as there is music playing during. marios second upside down
-- function triggers late then resets early. third is early then resets at perfect". The quiet at the film's end is left
-- as it was: "no leave the ending".)
local FILM_TALK = { { 28.4, 35.4 }, { 52.7, 60.55 } }
local function talk_at(at)
    for _, q in ipairs(FILM_TALK) do if at >= q[1] and at < q[2] then return q end end
    return nil
end
local function film_quiet(at) return talk_at(at) ~= nil end
local function talk_roll(at)
    local q = at and talk_at(at)
    if not q then return 0.0 end
    local u, L = at - q[1], q[2] - q[1]
    local rt = math.min(1.2, L / 3.0)
    local function smooth(x) x = math.max(0.0, math.min(1.0, x)); return x * x * (3.0 - 2.0 * x) end
    if u < rt then return 180.0 * smooth(u / rt) end
    if u < L - rt then return 180.0 end
    return 180.0 + 180.0 * smooth((u - (L - rt)) / rt)
end

-- How far down the head is (0 up, 1 right down) at `at` seconds into the film, and how hard that beat hits.
local function beat_nod(b, at)
    local times, hit = b.times, b.hit
    local n = #times
    if n < 2 then return 0.0, 0.0 end
    local i = b.i or 1                              -- the beat just gone: looked for from where it was last time
    if i > n or times[i] > at then i = 1 end
    while i < n and times[i + 1] <= at do i = i + 1 end
    b.i = i
    local t0, t1, h0, h1
    if at < times[1] then
        t0, t1, h0, h1 = times[1] - (times[2] - times[1]), times[1], hit[n], hit[1]
    elseif i == n then
        t0, t1, h0, h1 = times[n], times[n] + (times[n] - times[n - 1]), hit[n], hit[1]
    else
        t0, t1, h0, h1 = times[i], times[i + 1], hit[i], hit[i + 1]
    end
    local p = ((at - t0) / (t1 - t0)) % 1.0
    local up
    if p < BANG_UP then up = sin(p / BANG_UP * pi / 2.0)
    else up = cos((p - BANG_UP) / (1.0 - BANG_UP) * pi / 2.0) end
    return 1.0 - up, h0 + (h1 - h0) * p
end

-- ------------------------------------------------------------ mesh sections
local update_section = lib.update_section

-- head space (x right, y up, z toward the viewer) -> the head actor's own space
local function to_local(x, y, z)
    return { X = -z * S, Y = x * S, Z = (y - HEAD_MID) * S }
end

-- ------------------------------------------------------------ the head's data, made ready
local SECTION = { face = 0, eye_r = 1, eye_l = 2, brow_r = 3, brow_l = 4, mustache = 5 }

local function prepare(data)
    local shapes = {}
    for name, s in pairs(data.shapes) do
        local V, F = s.verts, s.faces
        local nv, nf = #V // 3, #F // 4
        -- a normal for every point: the average of the faces round it
        local nx, ny, nz = {}, {}, {}
        for i = 1, nv do nx[i], ny[i], nz[i] = 0.0, 0.0, 0.0 end
        local out = 0.0
        local cx, cy, cz = 0.0, HEAD_MID, 0.0
        if data.eye_pivots[name] then cx, cy, cz = data.eye_pivots[name][1], data.eye_pivots[name][2], data.eye_pivots[name][3] end
        for f = 0, nf - 1 do
            local a, b, c = F[f * 4 + 2], F[f * 4 + 3], F[f * 4 + 4]
            local ax, ay, az = V[a * 3 + 1], V[a * 3 + 2], V[a * 3 + 3]
            local ux, uy, uz = V[b * 3 + 1] - ax, V[b * 3 + 2] - ay, V[b * 3 + 3] - az
            local vx, vy, vz = V[c * 3 + 1] - ax, V[c * 3 + 2] - ay, V[c * 3 + 3] - az
            local fx, fy, fz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            out = out + fx * (ax - cx) + fy * (ay - cy) + fz * (az - cz)
            for _, i in ipairs({ a, b, c }) do
                nx[i + 1], ny[i + 1], nz[i + 1] = nx[i + 1] + fx, ny[i + 1] + fy, nz[i + 1] + fz
            end
        end
        local sign = (out < 0) and -1.0 or 1.0          -- whichever way the faces are wound, normals point outward
        -- one drawn point for every (point, material) pair in use, so each material keeps its own colour
        local of, src, cols, idx = {}, {}, {}, {}
        for f = 0, nf - 1 do
            local m = F[f * 4 + 1]
            local mc = s.mtls[m] or { 1.0, 0.0, 1.0 }
            local tri = {}
            for k = 2, 4 do
                local v = F[f * 4 + k]
                local key = v * 32 + m
                local r = of[key]
                if not r then
                    r = #src + 1
                    of[key] = r
                    src[r] = v
                    local x, y, z = nx[v + 1] * sign, ny[v + 1] * sign, nz[v + 1] * sign
                    local len = sqrt(x * x + y * y + z * z)
                    local lit = 0.0
                    if len > 1e-9 then lit = max(0.0, (x * LIGHT[1] + y * LIGHT[2] + z * LIGHT[3]) / len) end
                    local shade = AMBIENT + DIFFUSE * lit
                    cols[r] = { R = min(1.0, mc[1] * shade) ^ 2.2, G = min(1.0, mc[2] * shade) ^ 2.2, B = min(1.0, mc[3] * shade) ^ 2.2, A = 1.0 }
                end
                tri[#tri + 1] = r - 1
            end
            idx[#idx + 1] = tri[1]; idx[#idx + 1] = tri[2]; idx[#idx + 1] = tri[3]
            idx[#idx + 1] = tri[1]; idx[#idx + 1] = tri[3]; idx[#idx + 1] = tri[2]      -- seen from either side
        end
        shapes[name] = { name = name, id = SECTION[name], rest = V, nv = nv, src = src, cols = cols, idx = idx, dirty = true, moved = false }
    end
    local joints = {}
    for _, j in ipairs(data.joints) do
        local sh = shapes[j.shape]
        if sh then
            local W, tot, hx, hy, hz = j.weights, 0.0, 0.0, 0.0, 0.0
            for i = 1, #W, 2 do
                local v, w = W[i], W[i + 1]
                tot = tot + w
                hx, hy, hz = hx + sh.rest[v * 3 + 1] * w, hy + sh.rest[v * 3 + 2] * w, hz + sh.rest[v * 3 + 3] * w
            end
            if tot > 0 then
                -- (the cap carries extra pieces at its front; it is still taken hold of by its middle)
                if j.handle then hx, hy, hz, tot = j.handle[1], j.handle[2], j.handle[3], 1.0 end
                joints[#joints + 1] = {
                    name = j.name, shape = sh, weights = W, pivot = j.pivot,
                    hx = hx / tot, hy = hy / tot, hz = hz / tot,        -- where on the skin this joint is felt most
                    dx = 0.0, dy = 0.0, dz = 0.0, vx = 0.0, vy = 0.0, vz = 0.0,
                    grab = not NOT_FOR_GRABBING[j.name], lid = (j.name == "eyelid_r" or j.name == "eyelid_l"),
                }
            end
        end
    end
    return shapes, joints
end

-- ------------------------------------------------------------ building the screen
local function valid(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

local function plain_actor(world, loc)
    local actor = lib.spawn_actor(world, loc, 0.0)
    if not actor then return nil end
    local pmc = lib.add_pmc(actor)
    if not pmc then lib.destroy(actor); return nil end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    return actor, pmc
end

local function shape_verts(sh, off)
    local out, R = {}, sh.rest
    for r, v in ipairs(sh.src) do
        local x, y, z = R[v * 3 + 1], R[v * 3 + 2], R[v * 3 + 3]
        local o = off and off[v]
        if o then x, y, z = x + o[1], y + o[2], z + o[3] end
        out[r] = to_local(x, y, z)
    end
    return out
end

local text_serial = 0
local function build_text(pc)
    local function cls(p) return StaticFindObject(p) end
    text_serial = text_serial + 1
    local n = tostring(text_serial)
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("SM64Title" .. n))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("SM64TitleTree" .. n))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SM64TitleCanvas" .. n))
    tree.RootWidget = canvas
    local function line(name, text, y, scale, r, g, b)
        local t = StaticConstructObject(cls("/Script/UMG.TextBlock"), canvas, FName(name .. n))
        t:SetText(FText(text))
        local slot = canvas:AddChildToCanvas(t)
        slot:SetAnchors({ Minimum = { X = 0.5, Y = 1.0 }, Maximum = { X = 0.5, Y = 1.0 } })
        slot:SetAlignment({ X = 0.5, Y = 0.5 })
        slot:SetAutoSize(true)
        slot:SetPosition({ X = 0.0, Y = y })
        pcall(function() t:SetColorAndOpacity({ SpecifiedColor = { R = r, G = g, B = b, A = 1.0 }, ColorUseRule = 0 }) end)
        pcall(function() t:SetShadowOffset({ X = 3.0, Y = 3.0 }); t:SetShadowColorAndOpacity({ R = 0.0, G = 0.0, B = 0.0, A = 0.9 }) end)
        pcall(function() t:SetRenderScale({ X = scale, Y = scale }) end)
        return t
    end
    local press = line("SM64TitlePress", "PRESS START", -84.0, 1.5, 1.0, 0.85, 0.1)
    w:AddToViewport(8000)
    return w, press
end

-- Mario 64's GAME OVER screen (levels/intro/script.c level_intro_mario_head_dizzy, intro_geo.c
-- geo_intro_gameover_backdrop): the head over a wall of "GAME OVER" tiles (title_screen_bg's second picture, 80 x 80
-- each), which after 180 frames turn one by one, every other frame, round the screen and then into the middle, to
-- "SUPER MARIO 64". The tiles stay square here: three rows, as many columns as the screen's width takes.
local TILE_ROWS = 3
local function tile_order(cols, rows)
    local order, seen = {}, {}
    local top, bot, left, right = 0, rows - 1, 0, cols - 1
    while top <= bot and left <= right do
        for c = left, right do order[#order + 1] = top * cols + c end
        for r = top + 1, bot do order[#order + 1] = r * cols + right end
        if top < bot then for c = right - 1, left, -1 do order[#order + 1] = bot * cols + c end end
        if left < right then for r = bot - 1, top + 1, -1 do order[#order + 1] = r * cols + left end end
        top, bot, left, right = top + 1, bot - 1, left + 1, right - 1
    end
    local out = {}
    for _, i in ipairs(order) do if not seen[i] then seen[i] = true; out[#out + 1] = i end end
    return out
end
local function build_tiles(world, bpmc, bw, bh)
    local size = 2.0 * bh / TILE_ROWS
    local cols = math.ceil(2.0 * bw / size)
    if cols % 2 == 1 then cols = cols + 1 end
    local x0 = -cols * size / 2.0
    local n = { X = -1.0, Y = 0.0, Z = 0.0 }
    local white = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
    local over = lib.get_mid(world, "opaque", "title_tile_gameover")
    local id = 0
    for r = 0, TILE_ROWS - 1 do
        for c = 0, cols - 1 do
            local y0, z1 = x0 + c * size, bh - r * size
            local q = { { X = 0.0, Y = y0, Z = z1 - size }, { X = 0.0, Y = y0 + size, Z = z1 - size },
                        { X = 0.0, Y = y0 + size, Z = z1 }, { X = 0.0, Y = y0, Z = z1 } }
            local uv = { { X = 0.0, Y = 1.0 }, { X = 1.0, Y = 1.0 }, { X = 1.0, Y = 0.0 }, { X = 0.0, Y = 0.0 } }
            lib.create_section(bpmc, id, q, { 0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2 }, { n, n, n, n }, uv,
                { white, white, white, white }, false)
            if over then pcall(function() bpmc:SetMaterial(id, over) end) end
            id = id + 1
        end
    end
    return { pmc = bpmc, n = id, order = tile_order(cols, TILE_ROWS), next = 1, t = 0.0, step = 0.0,
             mario = lib.get_mid(world, "opaque", "title_tile_mario") }
end

-- (`dry`: only the workings, nothing built or shown; for tests. `opt.game_over`: the GAME OVER screen)
function T.open(dry, opt)
    opt = opt or {}
    local world, pc = lib.world(), lib.controller()
    if not (world and pc) then return false end
    T.close()
    local data = lib.load_data("data.mario_head")
    if not data then return false end
    local shapes, joints = prepare(data)
    local s = { world = world:GetAddress(), shapes = shapes, joints = joints, data = data, t = 0.0,
        beats = lib.load_data("data.title_beats"), bang = 0.0, nod = 0.0, drop = 0.0,
        cx = 260.0, cy = -120.0, yaw = 0.0, pitch = 0.0, held = nil, blink = 2.0, blink_p = nil, eye_x = 0.0, eye_y = 0.0 }

    if dry then
        pad.reset()
        st = s
        T.active = true
        return true
    end

    -- the backdrop: STORROR's own start film, or failing that a plain deep blue
    local bd = D + 2600.0
    local bw, bh = bd * K * 1.08, bd * K * 1.08 * 9.0 / 16.0
    local fw, fh = bd * K * FILM_FULL, bd * K * FILM_FULL * 9.0 / 16.0
    local back, bpmc = plain_actor(world, { X = BASE.X + bd, Y = BASE.Y, Z = BASE.Z })
    if back then
        local n = { X = -1.0, Y = 0.0, Z = 0.0 }
        local corners = { { X = 0.0, Y = -bw, Z = -bh }, { X = 0.0, Y = bw, Z = -bh }, { X = 0.0, Y = bw, Z = bh }, { X = 0.0, Y = -bw, Z = bh } }
        local filmed = (not opt.game_over) and FILM and FILM.start(world, FILM_DELAY) and FILM.material(world) or nil
        if opt.game_over then
            local okt, tiles = pcall(build_tiles, world, bpmc, bw, bh)
            if okt then s.tiles = tiles else log("game over tiles: %s", tostring(tiles)) end
        elseif filmed then
            -- the film in the middle of the screen, black all round it
            local c = { R = FILM_DIM, G = FILM_DIM, B = FILM_DIM, A = 1.0 }
            local frame = { { X = 0.0, Y = -fw, Z = -fh }, { X = 0.0, Y = fw, Z = -fh }, { X = 0.0, Y = fw, Z = fh }, { X = 0.0, Y = -fw, Z = fh } }
            local screen, spmc = plain_actor(world, { X = BASE.X + bd, Y = BASE.Y, Z = BASE.Z })
            if screen then
                lib.create_section(spmc, 0, frame, { 0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2 }, { n, n, n, n },
                    { { X = 0.0, Y = 1.0 }, { X = 1.0, Y = 1.0 }, { X = 1.0, Y = 0.0 }, { X = 0.0, Y = 0.0 } }, { c, c, c, c }, false)
                spmc:SetMaterial(0, filmed)
                local k = FILM_SMALL / FILM_FULL
                pcall(function() screen:SetActorScale3D({ X = 1.0, Y = k, Z = k }) end)
                s.screen, s.screen_k = screen, k
            end
            local k = { R = 0.0, G = 0.0, B = 0.0, A = 1.0 }
            local uv = { X = 0.5, Y = 0.5 }
            local far = {}
            for i, v in ipairs(corners) do far[i] = { X = 60.0, Y = v.Y, Z = v.Z } end
            lib.create_section(bpmc, 1, far, { 0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2 }, { n, n, n, n }, { uv, uv, uv, uv }, { k, k, k, k }, false)
            local black = lib.get_mid(world, "opaque", "white")
            if black then bpmc:SetMaterial(1, black) end
            -- and its sound
            FILM.speaker(world, { X = BASE.X + bd, Y = BASE.Y, Z = BASE.Z })
        else
            -- no film to be had: deep blue at the top running to near black
            local top, bot = { R = 0.012, G = 0.035, B = 0.30, A = 1.0 }, { R = 0.0, G = 0.002, B = 0.03, A = 1.0 }
            local uv = { X = 0.5, Y = 0.5 }
            lib.create_section(bpmc, 0, corners, { 0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2 }, { n, n, n, n }, { uv, uv, uv, uv }, { bot, bot, top, top }, false)
            local mid = lib.get_mid(world, "opaque", "white")
            if mid then bpmc:SetMaterial(0, mid) end
        end
    end
    s.back = back

    -- the head
    local head, pmc = plain_actor(world, { X = BASE.X + D, Y = BASE.Y, Z = BASE.Z })
    if not head then return false end
    s.head, s.pmc = head, pmc
    local mid = lib.get_mid(world, "opaque", "white")
    for _, sh in pairs(shapes) do
        local verts = shape_verts(sh)
        local nrm, uv = {}, {}
        for r = 1, #verts do nrm[r] = { X = -1.0, Y = 0.0, Z = 0.0 }; uv[r] = { X = 0.5, Y = 0.5 } end
        local ok, err = pcall(lib.create_section, pmc, sh.id, verts, sh.idx, nrm, uv, sh.cols, false)
        if not ok then log("title: %s failed: %s", sh.name, tostring(err)) end
        if mid then pcall(function() pmc:SetMaterial(sh.id, mid) end) end
        sh.dirty = false
    end

    -- the hand, open and closed
    local half = HAND_SIZE * HAND_PX / 2.0
    s.hand_open = lib.quad_actor(world, { X = BASE.X + HAND_D, Y = BASE.Y, Z = BASE.Z }, half, "title_hand_open", "translucent")
    s.hand_closed = lib.quad_actor(world, { X = BASE.X + HAND_D, Y = BASE.Y, Z = BASE.Z }, half, "title_hand_closed", "translucent")
    if s.hand_closed then pcall(function() s.hand_closed:SetActorHiddenInGame(true) end) end
    s.closed_shown = false

    -- the camera
    local cam = lib.camera(world, "title", BASE, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
    if valid(cam) then
        pcall(function() cam.CameraComponent:SetFieldOfView(FOV) end)
        pcall(function()
            local pp = cam.CameraComponent.PostProcessSettings
            pp.bOverride_AutoExposureMinBrightness, pp.bOverride_AutoExposureMaxBrightness = true, true
            pp.AutoExposureMinBrightness, pp.AutoExposureMaxBrightness = EXPOSURE, EXPOSURE
            pp.bOverride_AutoExposureBias, pp.AutoExposureBias = true, 0.0
        end)
        pcall(function() pc:SetViewTargetWithBlend(cam, 0.0, 0, 0.0, false) end)
        s.cam = cam
    end
    if not opt.game_over then
        local okw, w, press = pcall(build_text, pc)
        if okw then s.widget, s.press = w, press end
    end
    s.game_over = opt.game_over
    pad.reset()
    st = s
    T.active = true
    log("%s open (%d joints)", opt.game_over and "game over screen" or "title screen", #joints)
    -- (his "Hello!" a moment on, the sound players made first: the first sound in the new map, played the frame they were
    -- made - and the frame before the map's loading hitch - lost its start: "menu 2's Helloo gets cut out when booting
    -- the game", 2026-10-20)
    if not opt.game_over then
        s.hello = true
        if SFX and SFX.warm then pcall(SFX.warm) end
    end
    return true
end

-- Running smoothly since it opened: a moment gone, and its last 8 frames under 40 ms each (menu.lua takes the opening's
-- black away then)
function T.settled()
    local fr = st and st.fr
    return fr ~= nil and (fr.steady or 0) >= 8 and os.clock() - fr.c >= 0.15
end

-- (`keep_film`: the film and its music are to carry on, into the file select)
function T.close(keep_film)
    T.active = false
    if FILM and not keep_film then FILM.stop() end
    if not st then return end
    for _, a in ipairs({ st.head, st.back, st.screen, st.hand_open, st.hand_closed }) do lib.destroy(a) end   -- (not its camera: lib.camera)
    if st.widget then pcall(function() st.widget:RemoveFromParent() end) end
    st = nil
end

-- ------------------------------------------------------------ every tick
-- where a point of the head (head space) is on the screen, with the head turned as it is
local function on_screen(s, x, y, z)
    local lx, ly, lz = -z * S, x * S, (y - HEAD_MID) * S
    -- (its roll first, as the engine turns it: positive tips its right side down - upside down while they talk)
    local r = rad(s.roll or 0.0)
    ly, lz = ly * cos(r) + lz * sin(r), -ly * sin(r) + lz * cos(r)
    local pitch = s.pitch + s.nod
    local cp, sp, cy_, sy = cos(rad(pitch)), sin(rad(pitch)), cos(rad(s.yaw)), sin(rad(s.yaw))
    local wx = lx * cp * cy_ - ly * sy - lz * sp * cy_
    local wy = lx * cp * sy + ly * cy_ - lz * sp * sy
    local wz = lx * sp + lz * cp + HEAD_UP * PX
    local depth = D + wx
    return wy / depth * 960.0 / K, wz / depth * 960.0 / K
end

-- The pull across the head's face (head units, x and y) that puts point j - resting where it does on the head as the
-- head is now - at screen point (tx, ty): the head's own projection, linear about the point (each head unit across
-- it, on the screen), solved. Also where the point rests on the screen, and that per-unit move, for the way back.
local function pull_for(s, j, tx, ty)
    local rx, ry = on_screen(s, j.hx, j.hy, j.hz)
    local ax, ay = on_screen(s, j.hx + 1.0, j.hy, j.hz)
    local bx, by = on_screen(s, j.hx, j.hy + 1.0, j.hz)
    local a, b, c, d = ax - rx, bx - rx, ay - ry, by - ry
    local det = a * d - b * c
    if abs(det) < 1e-9 then return 0.0, 0.0, rx, ry, a, b, c, d end
    local ex, ey = tx - rx, ty - ry
    return (d * ex - b * ey) / det, (-c * ex + a * ey) / det, rx, ry, a, b, c, d
end

local function place_hand(s)
    local grabbing = s.held ~= nil
    if grabbing ~= s.closed_shown then
        s.closed_shown = grabbing
        pcall(function() s.hand_closed:SetActorHiddenInGame(not grabbing) end)
        pcall(function() s.hand_open:SetActorHiddenInGame(grabbing) end)
    end
    local a = grabbing and s.hand_closed or s.hand_open
    if a then
        -- the hand is drawn with its fingertips on the spot it points at
        local y, z = (s.cx + HAND_SIZE * 0.22) * HAND_PX, (s.cy - HAND_SIZE * 0.30) * HAND_PX
        pcall(function() a:K2_TeleportTo({ X = BASE.X + HAND_D, Y = BASE.Y + y, Z = BASE.Z + z }, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }) end)
    end
end

-- Returns "start" on the tick Start is pressed; the caller moves on to the file select.
function T.tick(dt)
    local s = st
    if not (s and T.active) then return nil end
    local world = lib.world()
    if not world or world:GetAddress() ~= s.world then st = nil; T.active = false; return nil end
    if not T.covered then s.t = s.t + dt end          -- (held while the opening's black is still over it: menu.lua)
    s.ticks = (s.ticks or 0) + 1
    -- (how smoothly it opened: its first 3 s of frames, logged once)
    do
        local now = os.clock()
        if not s.fr then s.fr = { c = now, last = now, n = 0, long = 0.0, at = 0.0, over = {} } end
        local fr = s.fr
        if not fr.done then
            local took = now - fr.last
            fr.last, fr.n = now, fr.n + 1
            if took > fr.long then fr.long, fr.at = took, now - fr.c end
            fr.steady = (took < 0.04) and ((fr.steady or 0) + 1) or 0
            if took > 0.05 and #fr.over < 12 then fr.over[#fr.over + 1] = string.format("%.2f:%.0f", now - fr.c, took * 1000.0) end
            if now - fr.c >= 3.0 then
                fr.done = true
                log("title: first 3 s - %d frames, longest %.0f ms at %.2f s; over 50 ms: %s", fr.n, fr.long * 1000.0, fr.at,
                    #fr.over > 0 and table.concat(fr.over, " ") or "none")
            end
        end
    end
    if SFX and SFX.prime_tick and s.ticks >= 2 then pcall(SFX.prime_tick) end
    if s.hello and s.t >= HELLO_AT and s.ticks >= 10 then
        s.hello = nil
        sound("title_hello")
        s.hello_c, s.hello_rows, s.hello_long = os.clock(), {}, 0.0
        s.hello_p = SFX and SFX.player_of and SFX.player_of("title_hello")
    end
    -- (how far his "Hello!" really got, and the longest frame meanwhile: logged once, 1.6 s on)
    if s.hello_c then
        local now = os.clock()
        local took = now - (s.hello_last or now)
        s.hello_last = now
        if took > s.hello_long then s.hello_long = took end
        local p, el = s.hello_p, now - s.hello_c
        if p and el < 1.6 then
            pcall(function()
                local r = string.format("%.2f:%s%.2f", el, p.mp:IsPlaying() and "" or "-", (p.mp:GetTime().Ticks or 0) / 1e7)
                local prev = s.hello_rows[#s.hello_rows]
                if not prev or prev:sub(6) ~= r:sub(6) then s.hello_rows[#s.hello_rows + 1] = r end
            end)
        elseif el >= 1.6 then
            log("title: hello played (longest frame %.0f ms; %s)", s.hello_long * 1000.0, table.concat(s.hello_rows, " "))
            s.hello_c, s.hello_rows = nil, nil
        end
    end
    if pad.pressed("start") and s.t > 0.6 then sound("title_start"); return "start" end
    -- (the GAME OVER tiles: after 6 s one turns to SUPER MARIO 64 every other frame)
    local tl = s.tiles
    if tl and tl.next <= #tl.order then
        tl.t = tl.t + dt
        if tl.t > 6.0 then
            tl.step = tl.step + dt
            while tl.step >= 2.0 / 30.0 and tl.next <= #tl.order do
                tl.step = tl.step - 2.0 / 30.0
                local i = tl.order[tl.next]
                tl.next = tl.next + 1
                if tl.mario then pcall(function() tl.pmc:SetMaterial(i, tl.mario) end) end
            end
        end
    end

    -- the hand
    local sx, sy = pad.sticks()
    local kx = (pad.down("right") and 1.0 or 0.0) - (pad.down("left") and 1.0 or 0.0)
    local ky = (pad.down("up") and 1.0 or 0.0) - (pad.down("down") and 1.0 or 0.0)
    s.cx = max(-930.0, min(930.0, s.cx + (sx * CURSOR_SPEED + kx * KEY_SPEED) * dt))
    s.cy = max(-510.0, min(510.0, s.cy + (sy * CURSOR_SPEED + ky * KEY_SPEED) * dt))
    if s.held then
        -- skin only stretches so far: the hand cannot leave what it is holding behind - measured from where that point
        -- rests on the head as it is now (rolled over, nodding), so the hand is drawn along with it
        local j = s.held
        local ox, oy = j.ox or 0.0, j.oy or 0.0
        local nx, ny, rx, ry, a, b, c, d = pull_for(s, j, s.cx - ox, s.cy - oy)
        local len = sqrt(nx * nx + ny * ny)
        if len > MAX_PULL then
            nx, ny = nx * MAX_PULL / len, ny * MAX_PULL / len
            s.cx, s.cy = rx + a * nx + b * ny + ox, ry + c * nx + d * ny + oy
        end
    end

    -- taking hold and letting go
    local want = pad.down("grab")
    if T.script then want = T.script(s, dt, want) end        -- (tests: something else working the hand)
    if want and not s.held and not s.was_grab then
        local best, bd, bx, by = nil, REACH, 0.0, 0.0
        for _, j in ipairs(s.joints) do
            if j.grab then
                local px, py = on_screen(s, j.hx + j.dx, j.hy + j.dy, j.hz + j.dz)
                local d = sqrt((px - s.cx) ^ 2 + (py - s.cy) ^ 2)
                if d < bd then best, bd, bx, by = j, d, px, py end
            end
        end
        if best then
            s.held = best
            best.gx, best.gy, best.sx, best.sy, best.sz = s.cx, s.cy, best.dx, best.dy, best.dz
            best.ox, best.oy = s.cx - bx, s.cy - by          -- (the hand's place off the point it took)
            sound("title_pinch")
        end
    elseif not want and s.held then
        s.held = nil
        sound("title_let_go")
    end
    s.was_grab = want

    -- the head turns to the hand, the eyes a little further (while something is being pulled, it keeps its way)
    local growth = FILM and FILM.growth() or 0.0
    if s.screen then
        local k = (FILM_SMALL + (FILM_FULL - FILM_SMALL) * growth) / FILM_FULL
        if math.abs(k - s.screen_k) > 0.0005 then
            s.screen_k = k
            pcall(function() s.screen:SetActorScale3D({ X = 1.0, Y = k, Z = k }) end)
        end
    end
    local ty, tp = s.yaw, s.pitch
    -- (it turns to the hand only as far as the film has grown: drawn back, the word needs the whole head)
    local free = s.screen and growth or 1.0
    local sway_y, sway_p = sin(s.t * 0.9) * 1.2 * free, sin(s.t * 1.3) * 0.8 * free
    if not s.held then
        ty = (-(s.cx / 960.0) * TURN_YAW - LOOK_RIGHT) * free + sway_y
        tp = (-(s.cy / 540.0) * TURN_PITCH) * free + sway_p
        s.look_y, s.look_p = ty - sway_y, tp - sway_p
    else
        -- (held, it keeps looking where it was - the skin stays under the hand - but sways, nods to the music and rolls
        -- on as ever: "also make him keep moving when you grab him", 2026-10-20)
        ty, tp = (s.look_y or s.yaw) + sway_y, (s.look_p or s.pitch) + sway_p
    end
    local k = min(1.0, dt * 5.0)
    s.yaw, s.pitch = s.yaw + (ty - s.yaw) * k, s.pitch + (tp - s.pitch) * k
    -- and it nods to the music (held or not)
    local at = s.beats and FILM and FILM.time()
    local music = at and not film_quiet((at + BANG_LEAD) % FILM.LENGTH)
    s.roll = at and talk_roll(at % FILM.LENGTH) or 0.0
    s.bang = s.bang + ((music and 1.0 or 0.0) - s.bang) * min(1.0, dt * 6.0)
    if at and s.bang > 0.001 then
        local down, hard = beat_nod(s.beats, (at + BANG_LEAD) % FILM.LENGTH)
        local a = (BANG_SOFT + (1.0 - BANG_SOFT) * hard) * s.bang * (BANG_QUIET + (1.0 - BANG_QUIET) * (s.screen and growth or 1.0))
        s.nod, s.drop = (down - BANG_REST) * a * BANG_PITCH, down * a * BANG_DROP
    else
        s.nod, s.drop = 0.0, 0.0
    end
    local ex, ey = (s.cx / 960.0) * EYE_YAW, (s.cy / 540.0) * EYE_PITCH
    if abs(ex - s.eye_x) > 0.05 or abs(ey - s.eye_y) > 0.05 then
        s.eye_x, s.eye_y = s.eye_x + (ex - s.eye_x) * min(1.0, dt * 9.0), s.eye_y + (ey - s.eye_y) * min(1.0, dt * 9.0)
        s.shapes.eye_r.dirty, s.shapes.eye_l.dirty = true, true
    end

    -- joints: the held one follows the hand, the others spring home
    for _, j in ipairs(s.joints) do
        if j == s.held then
            -- (pulled to stay under the hand, wherever the head has turned or rolled: from where the point rests as the
            -- head is now, to the hand - "when he flips upsidedown and your grabbin the part example the nose it doesnt
            -- stay on the cursor", 2026-10-20)
            local nx, ny = pull_for(s, j, s.cx - (j.ox or 0.0), s.cy - (j.oy or 0.0))
            local len = sqrt(nx * nx + ny * ny)
            if len > MAX_PULL then nx, ny = nx * MAX_PULL / len, ny * MAX_PULL / len end
            local nz = j.sz + len * 0.25                -- and comes a little toward the viewer, as skin does
            j.vx, j.vy, j.vz = (nx - j.dx) / max(dt, 0.001), (ny - j.dy) / max(dt, 0.001), (nz - j.dz) / max(dt, 0.001)
            j.dx, j.dy, j.dz = nx, ny, nz
            j.shape.dirty = true
        elseif j.dx ~= 0.0 or j.dy ~= 0.0 or j.dz ~= 0.0 or j.vx ~= 0.0 or j.vy ~= 0.0 or j.vz ~= 0.0 then
            local left = dt
            while left > 0.0 do
                local h = min(left, 1.0 / 120.0)
                left = left - h
                j.vx = j.vx + (-SPRING * j.dx - DAMP * j.vx) * h
                j.vy = j.vy + (-SPRING * j.dy - DAMP * j.vy) * h
                j.vz = j.vz + (-SPRING * j.dz - DAMP * j.vz) * h
                j.dx, j.dy, j.dz = j.dx + j.vx * h, j.dy + j.vy * h, j.dz + j.vz * h
            end
            if abs(j.dx) + abs(j.dy) + abs(j.dz) < 0.4 and abs(j.vx) + abs(j.vy) + abs(j.vz) < 4.0 then
                j.dx, j.dy, j.dz, j.vx, j.vy, j.vz = 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
            end
            j.shape.dirty = true
        end
    end

    if FILM then FILM.tick() end

    -- blinking
    s.blink = s.blink - dt
    local lid = 0.0
    if s.blink <= 0.0 then
        s.blink_p = (s.blink_p or 0.0) + dt / 0.24
        if s.blink_p >= 1.0 then
            s.blink_p, s.blink = nil, 2.2 + math.random() * 3.5
        else
            lid = sin(s.blink_p * pi) * BLINK_ANGLE
        end
        s.shapes.face.dirty = true
    end

    -- skin: every point moves with the joints it hangs on, by its weight
    for _, sh in pairs(s.shapes) do
        if sh.dirty then
            sh.dirty = false
            local off = {}
            for _, j in ipairs(s.joints) do
                if j.shape == sh then
                    local W = j.weights
                    if j.lid then
                        if lid ~= 0.0 then
                            -- an eyelid turns about the line through its joint, the way a real one hinges
                            local c, sn = cos(rad(lid)), sin(rad(lid))
                            local R = sh.rest
                            for i = 1, #W, 2 do
                                local v, w = W[i], W[i + 1] / 100.0
                                local ry, rz = R[v * 3 + 2] - j.pivot[2], R[v * 3 + 3] - j.pivot[3]
                                local o = off[v]
                                if not o then o = { 0.0, 0.0, 0.0 }; off[v] = o end
                                o[2] = o[2] + (ry * c - rz * sn - ry) * w
                                o[3] = o[3] + (ry * sn + rz * c - rz) * w
                            end
                        end
                    elseif j.dx ~= 0.0 or j.dy ~= 0.0 or j.dz ~= 0.0 then
                        for i = 1, #W, 2 do
                            local v, w = W[i], W[i + 1] / 100.0
                            local o = off[v]
                            if not o then o = { 0.0, 0.0, 0.0 }; off[v] = o end
                            o[1], o[2], o[3] = o[1] + j.dx * w, o[2] + j.dy * w, o[3] + j.dz * w
                        end
                    end
                end
            end
            local pv = s.data.eye_pivots[sh.name]
            if pv then
                -- an eye is a cap on a ball: it turns about the ball's middle to look at the hand
                local ca, sa = cos(rad(s.eye_x)), sin(rad(s.eye_x))
                local cb, sb = cos(rad(s.eye_y)), sin(rad(s.eye_y))
                local R = sh.rest
                for v = 0, sh.nv - 1 do
                    local x, y, z = R[v * 3 + 1] - pv[1], R[v * 3 + 2] - pv[2], R[v * 3 + 3] - pv[3]
                    local x2, z2 = x * ca + z * sa, -x * sa + z * ca
                    local y3, z3 = y * cb + z2 * sb, -y * sb + z2 * cb
                    off[v] = { x2 - x, y3 - y, z3 - z }
                end
            end
            s.last_off = off
            if s.pmc then
                local ok, err = pcall(update_section, s.pmc, sh.id, shape_verts(sh, off))
                if not ok and not s.warned then s.warned = true; log("title: update failed: %s", tostring(err)) end
            end
        end
    end

    -- the head itself: it arrives spinning from far away, then turns with the hand
    local arrive = min(1.0, s.t / 1.4)
    local ease = 1.0 - (1.0 - arrive) ^ 3
    local scale = 0.02 + 0.98 * ease
    local spin = (1.0 - ease) * 540.0
    pcall(function()
        if s.scale ~= scale then
            s.scale = scale
            s.head:SetActorScale3D({ X = scale, Y = scale, Z = scale })
        end
        s.head:K2_TeleportTo({ X = BASE.X + D, Y = BASE.Y, Z = BASE.Z + (HEAD_UP + sin(s.t * 1.7) * 4.0 - s.drop) * PX },
            { Pitch = s.pitch + s.nod, Yaw = s.yaw + spin, Roll = s.roll or 0.0 })
    end)
    place_hand(s)
    if s.press then
        local on = (s.t * 1.1) % 1.0 < 0.72
        if on ~= s.press_on then
            s.press_on = on
            pcall(function() s.press:SetRenderOpacity(on and 1.0 or 0.0) end)
        end
    end
    return nil
end

function T.state() return st end
function T.film() return FILM and FILM.state() end      -- (tests)

return T
