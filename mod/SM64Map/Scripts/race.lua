-- SM64Map: the ghost race's checkpoints - "an experimental star, a 8th star that has the player racing against my
-- ghost", tried first on Bob-omb Battlefield, 2026-10-27. The player is to outpace the ghost, so the way is shown by
-- numbered beacons the user places along it ("I can ask you to place beacons in specific areas also numbering the
-- beacons for each section of the race"). At each a checkpoint flag (Mario 3D World's: Bowser's until he passes it,
-- then his own - "passing it turns it to this"), solid - a round gold pole on its base, its ball on top, the flag a
-- cloth waving off it, turned to face the way he comes ("I see the pole is just a stagnant image", 2026-10-27) - its
-- number over it, and a beam of light up from the next one to reach
-- (and a fainter one from the one after), seen from anywhere on the course. Passed in order: only the next one counts.
-- The beacons are in data/race_beacons.lua, { [scene] = { { x, y, z }, ... } } (scene cm, the ground at his feet),
-- put there with M.place; and `start` there, { x, y, z, yaw }, where the ghost racer stands to be talked to and the
-- race starts ("this is also where you can talk to the ghost racer", 2026-10-27), with M.set_start.
local lib = require("lib")
local log = lib.log

local M = {}

local OFFSET = lib.OFFSET
M.FLAG_H = 220.0                                    -- cm: the flag's height, its ball's top
M.CLOTH = { w = 175.0, h = 114.0, top = 200.0, cols = 14, rows = 2 }   -- cm; its grid ("also flags not long enough": 110 out)
M.DIGIT = 55.0                                      -- cm: half a number digit's height, over the flag
-- (the beam: a pillar of yellow light up from the flag's top into the sky, 120 m, seen from anywhere - "add a yellow
-- beam at the top kinda like how, in cod zombies you can see the mystery box", 2026-10-27)
M.BEAM_W, M.BEAM_FROM, M.BEAM_H = 190.0, 330.0, 12000.0      -- (from just over its number: "raise the beam slightly")
M.REACH, M.BELOW, M.ABOVE = 160.0, 150.0, 350.0     -- cm round a flag that passes it, under and over its foot
-- (the pole bends out of his way as he walks into it - a spring from its foot, wobbling back up once he is past:
-- "I want the pole to bend out of the way of the character when walking into it", 2026-10-27. `r` cm round it he
-- pushes it, `max` the most it leans; `k`, `c` the spring's stiffness and damping)
M.BEND = { r = 85.0, max = 60.0, k = 110.0, c = 7.0 }
-- (and taken: it spins twice round as its cloth turns his, and sparkles fly up and out of it - "I want particles and
-- an fx to play when capturing the flag")
M.SPIN = { turns = 2.0, time = 0.7 }
-- (the Power Star's twinkles swirling up round it, Mario 64's sparkles' six pictures running through: "using the wrong fx
-- lets change it", then "Power Star twinkles", 2026-10-27 - for coin sparkles flying out. `r` cm round the pole, `rise`
-- cm a second, `turn` radians a second round it)
M.TWINKLE = { n = 14, size = 46.0, r = 75.0, rise = 170.0, turn = 2.6, life = 1.4, stagger = 0.05 }
-- (the flags' cloth made again at most this often, whatever the frame rate, within 40 m: each flag every other frame
-- and the start line's every frame was 0.9 ms of every frame with three flags up - and every ms of the mod's is a ms of
-- the frame, "when I entered the level it was 120 fps now its 80", 2026-11-05)
M.CLOTH_STEP = 1.0 / 30.0
M.CLOTH_FAR = 2000.0            -- (and over this many cm from the camera, half as often)
M.on = false                                        -- shown: in the race's own act (game.lua G.extra_act), or M.edit
M.edit = false
-- (kept through a reload of this file in the running game: the race on carries on)
M.next = M.next or 1
M.times = M.times or {}                             -- os.clock() each was passed at

local placed = nil          -- the data file's table
local built_for = nil       -- the scene (its scene actor's address) the beacons were made for
local B = {}                -- this scene's: { x, y, z, yaw, base, pole (its pmc: pole_pmc), digits, beam, dim }

local function data_path() return lib.MOD_DIR .. "Scripts\\data\\race_beacons.lua" end

local function load_placed()
    if placed then return placed end
    local f = io.open(data_path(), "rb")
    if f then
        local src = f:read("a")
        f:close()
        local chunk = load(src, "=race_beacons", "t", {})
        local ok, t = pcall(chunk or function() return nil end)
        if ok and type(t) == "table" then placed = t end
    end
    placed = placed or {}
    return placed
end

local function save_placed()
    local out = { "-- the ghost race's beacons (race.lua): { [scene] = { { x, y, z }, ... } }, scene cm, in order\nreturn {\n" }
    local names = {}
    for name in pairs(placed or {}) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        out[#out + 1] = name:match("^[%a_][%w_]*$") and string.format("  %s = {\n", name) or string.format("  [%q] = {\n", name)
        local st = placed[name].start
        if st then
            out[#out + 1] = string.format("    start = { %.1f, %.1f, %.1f, %.1f },  -- the ghost racer\n", st[1], st[2], st[3], st[4] or 0.0)
        end
        local rc = placed[name].racer
        if rc then
            out[#out + 1] = string.format("    racer = { %.1f, %.1f, %.1f, %.1f },  -- where the racer stands, his way\n", rc[1], rc[2], rc[3], rc[4] or 0.0)
        end
        local ln = placed[name].line
        if ln then
            out[#out + 1] = string.format("    line = { %.1f, %.1f, %.1f, %.1f, %.1f },  -- the start line: its middle, the way run, its width\n",
                ln[1], ln[2], ln[3], ln[4], ln[5] or 700.0)
        end
        local rw = placed[name].reward
        if rw then
            out[#out + 1] = string.format("    reward = { %.1f, %.1f, %.1f },  -- where his star or key comes out\n", rw[1], rw[2], rw[3])
        end
        local fn = placed[name].finish
        if fn then
            out[#out + 1] = string.format("    finish = { %.1f, %.1f, %.1f, %.1f, %.1f },  -- the finish line: its middle, the way run, its width\n",
                fn[1], fn[2], fn[3], fn[4], fn[5] or 700.0)
        end
        for i, b in ipairs(placed[name]) do
            local o = b.on
            if b.ring then
                -- (a ring under the water: M.ring_actor)
                out[#out + 1] = string.format("    { %.1f, %.1f, %.1f, ring = { %.1f, %.1f } },  -- %d, a ring\n",
                    b[1], b[2], b[3], b.ring[1] or 0.0, b.ring[2] or 0.0, i)
            elseif o then
                -- (one riding a platform: M.ride_tick)
                out[#out + 1] = string.format("    { %.1f, %.1f, %.1f, on = { %q, %.1f, %.1f, %.1f, %.2f, %.2f, %.2f } },  -- %d, on the %s\n",
                    b[1], b[2], b[3], o[1], o[2], o[3], o[4], o[5], o[6], o[7], i, o[1])
            else
                out[#out + 1] = string.format("    { %.1f, %.1f, %.1f },  -- %d\n", b[1], b[2], b[3], i)
            end
        end
        out[#out + 1] = "  },\n"
    end
    out[#out + 1] = "}\n"
    local f = io.open(data_path(), "wb")
    if not f then log("race: could not write %s", data_path()); return false end
    f:write(table.concat(out))
    f:close()
    return true
end

-- a picture standing up from (x, y, z): w wide, h tall, from `from` up; `u0` where across it the spot is (0..1). Turned
-- to face the camera each tick. `pics`: one picture, or a list of them side by side (a number's digits)
local function stand(world, x, y, z, w, h, from, u0, pics, layer)
    local a = lib.spawn_actor(world, { X = x + OFFSET.X, Y = y + OFFSET.Y, Z = z + OFFSET.Z }, 0.0)
    if not a then return nil end
    local pmc = lib.add_pmc(a)
    if not pmc then return a end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    if type(pics) ~= "table" then pics = { pics } end
    local secs = {}
    local each = w / #pics
    for i, tex in ipairs(pics) do
        local y0 = -w * u0 + (i - 1) * each
        local y1 = y0 + each
        secs[#secs + 1] = { id = i - 1, layer = layer, texture = tex, nverts = 4, ntris = 2,
            pos = { 0, y0, from, 0, y1, from, 0, y1, from + h, 0, y0, from + h },
            uv = { 0, 1, 1, 1, 1, 0, 0, 0 },
            col = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
            nrm = { -1, 0, 0, -1, 0, 0, -1, 0, 0, -1, 0, 0 },
            idx = { 0, 1, 2, 0, 2, 3 } }
    end
    lib.add_sections(world, pmc, secs)
    return a, pmc
end

-- the pictures turned to face the camera
local function each_actor(b, fn)
    for _, k in ipairs({ "digits", "beam", "dim" }) do
        if b[k] then fn(b[k], k) end
    end
end

local LINE = {}             -- the start line's strip and its two flags (made as B's flags are, never taken)
local function clear()
    for _, b in ipairs(LINE) do
        each_actor(b, function(a) pcall(lib.destroy, a, false) end)
        if b.base then pcall(lib.destroy, b.base, false) end
        if b.pole then pcall(lib.destroy, b.pole, false) end
        if b.strip then pcall(lib.destroy, b.strip, false) end
    end
    LINE = {}
    for _, b in ipairs(B) do
        each_actor(b, function(a) pcall(lib.destroy, a, false) end)
        if b.base then pcall(lib.destroy, b.base, false) end
        if b.pole then pcall(lib.destroy, b.pole, false) end
        if b.ring_actor then pcall(lib.destroy, b.ring_actor, false) end
    end
    B = {}
end

-- ------------------------------------------------------------ the flag, solid
-- Two parts: its base - the gold foot, the white ring, the collar - standing still ("the base shouldnt move",
-- 2026-10-27), and from the collar up the pole, its ball and its cloth: the part that bends and spins. The pole's
-- sections: 0 the pole, 1 its ball, 2 Bowser's cloth, 3 his. Lit from above and to one side in its corners' colours, as
-- the game's own pieces are.
local SEC_POLE, SEC_BALL, SEC_BOWSER, SEC_MARIO = 0, 1, 2, 3
local POLE_Z0, POLE_Z1, POLE_R, POLE_RINGS, POLE_SIDES = 27.0, M.FLAG_H - 22.0, 4.5, 8, 10
local BALL_R, BALL_Z = 12.0, M.FLAG_H - 12.0
local LX, LY, LZ = 0.45, -0.35, 0.82
local function lit(nx, ny, nz) return 0.55 + 0.45 * math.max(0.0, nx * LX + ny * LY + nz * LZ) end
local function new_sec(id, layer, tex) return { id = id, layer = layer, texture = tex, pos = {}, uv = {}, col = {}, nrm = {}, idx = {}, nverts = 0, ntris = 0 } end
local function vert(s, x, y, z, nx, ny, nz, u, v, k)
    local P, N, U, C = s.pos, s.nrm, s.uv, s.col
    P[#P + 1], P[#P + 2], P[#P + 3] = x, y, z
    N[#N + 1], N[#N + 2], N[#N + 3] = nx, ny, nz
    U[#U + 1], U[#U + 2] = u, v
    k = k or 1.0
    C[#C + 1], C[#C + 2], C[#C + 3], C[#C + 4] = k, k, k, 1.0
    s.nverts = s.nverts + 1
    return s.nverts - 1
end
-- a triangle facing the way its corners' normals do (the engine's front: their cross product against the normal, as
-- game.lua's prisms are laid)
local function tri(s, a, b, c)
    local P, N = s.pos, s.nrm
    local function v(i) return P[i * 3 + 1], P[i * 3 + 2], P[i * 3 + 3] end
    local ax, ay, az = v(a); local bx, by, bz = v(b); local cx, cy, cz = v(c)
    local ux, uy, uz, wx, wy, wz = bx - ax, by - ay, bz - az, cx - ax, cy - ay, cz - az
    local nx = N[a * 3 + 1] + N[b * 3 + 1] + N[c * 3 + 1]
    local ny = N[a * 3 + 2] + N[b * 3 + 2] + N[c * 3 + 2]
    local nz = N[a * 3 + 3] + N[b * 3 + 3] + N[c * 3 + 3]
    if (uy * wz - uz * wy) * nx + (uz * wx - ux * wz) * ny + (ux * wy - uy * wx) * nz > 0.0 then b, c = c, b end
    local X = s.idx
    X[#X + 1], X[#X + 2], X[#X + 3] = a, b, c
    s.ntris = s.ntris + 1
end
-- a tube from z0 to z1, `rings` rings up it (to bend), `cap` closed on top
local function tube(s, r, z0, z1, n, rings, cap)
    local first = s.nverts
    for j = 0, rings do
        local z = z0 + (z1 - z0) * j / rings
        for i = 0, n do
            local t = i / n * 2.0 * math.pi
            local nx, ny = math.cos(t), math.sin(t)
            vert(s, nx * r, ny * r, z, nx, ny, 0.0, i / n, 1.0 - j / rings, lit(nx, ny, 0.0))
        end
    end
    for j = 0, rings - 1 do
        for i = 0, n - 1 do
            local a, c = first + j * (n + 1) + i, first + (j + 1) * (n + 1) + i
            tri(s, a, c, c + 1)
            tri(s, a, c + 1, a + 1)
        end
    end
    if cap then
        local c = vert(s, 0.0, 0.0, z1, 0.0, 0.0, 1.0, 0.5, 0.5, lit(0.0, 0.0, 1.0))
        local ring = {}
        for i = 0, n do
            local t = i / n * 2.0 * math.pi
            ring[i] = vert(s, math.cos(t) * r, math.sin(t) * r, z1, 0.0, 0.0, 1.0, 0.5 + 0.5 * math.cos(t), 0.5 + 0.5 * math.sin(t), lit(0.0, 0.0, 1.0))
        end
        for i = 0, n - 1 do tri(s, c, ring[i], ring[i + 1]) end
    end
end
local function sphere(s, r, cz, n, m)
    local first = s.nverts
    for j = 0, m do
        local ph = -math.pi / 2.0 + j / m * math.pi
        for i = 0, n do
            local t = i / n * 2.0 * math.pi
            local nx, ny, nz = math.cos(ph) * math.cos(t), math.cos(ph) * math.sin(t), math.sin(ph)
            vert(s, nx * r, ny * r, cz + nz * r, nx, ny, nz, i / n, 1.0 - j / m, lit(nx, ny, nz))
        end
    end
    for j = 0, m - 1 do
        for i = 0, n - 1 do
            local a, b = first + j * (n + 1) + i, first + (j + 1) * (n + 1) + i
            tri(s, a, b, b + 1)
            tri(s, a, b + 1, a + 1)
        end
    end
end

-- The pole's middle line `h` over the collar, bent: its top out `s` (a sine, the lean) toward (ux, uy), in the pole's
-- own space - a rod held at its foot and pushed at its top, out as f^2 (3 - f) / 2 of the way, coming down as it bends
local function axis(h, s, ux, uy)
    local L = POLE_Z1 - POLE_Z0
    local f = h / L
    local u = L * s * f * f * (3.0 - f) / 2.0
    return ux * u, uy * u, POLE_Z0 + h * (1.0 - 0.35 * s * s * math.min(f, 1.2))
end

-- The cloth: points on a grid, its first column tied along the pole, the rest each held to where it lies on a flat flag
-- by a spring (`k`), weighed down (`g`), stirred by a wind across it (`wind`, more out at its end), slowed (`damp` a
-- step) and kept their distance from their neighbours; spun, it swings back against the turn (`lag`). Verlet, two steps
-- a tick. ("the flag should sway with physix", 2026-10-27)
M.CLOTH.k, M.CLOTH.g, M.CLOTH.wind, M.CLOTH.damp, M.CLOTH.lag, M.CLOTH.iters = 55.0, 120.0, 520.0, 0.985, 0.22, 2
local function cloth_rest(C, i, j, s, ux, uy)
    local ax, ay, az = axis(C.top - C.h + C.h * j / C.rows - POLE_Z0, s, ux, uy)
    return ax + POLE_R + C.w * i / C.cols, ay, az
end
local function cloth(id, tex)
    local C = M.CLOTH
    local s = new_sec(id, "alpha", tex)
    for j = 0, C.rows do
        for i = 0, C.cols do
            local x, y, z = cloth_rest(C, i, j, 0.0, 1.0, 0.0)
            vert(s, x, y, z, 0.0, 1.0, 0.0, i / C.cols, 1.0 - j / C.rows, 1.0)
        end
    end
    for row = 0, C.rows - 1 do
        for i = 0, C.cols - 1 do
            local a, b = row * (C.cols + 1) + i, (row + 1) * (C.cols + 1) + i
            tri(s, a, a + 1, b + 1)
            tri(s, a, b + 1, b)
        end
    end
    return s
end
local function keep_apart(S, a, b, rest, a_fixed, b_fixed)
    if a_fixed and b_fixed then return end
    local dx, dy, dz = S.x[b] - S.x[a], S.y[b] - S.y[a], S.z[b] - S.z[a]
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if d < 1e-4 then return end
    local diff = (d - rest) / d
    local ka, kb = 0.5, 0.5
    if a_fixed then ka, kb = 0.0, 1.0 elseif b_fixed then ka, kb = 1.0, 0.0 end
    S.x[a], S.y[a], S.z[a] = S.x[a] + dx * diff * ka, S.y[a] + dy * diff * ka, S.z[a] + dz * diff * ka
    S.x[b], S.y[b], S.z[b] = S.x[b] - dx * diff * kb, S.y[b] - dy * diff * kb, S.z[b] - dz * diff * kb
end
-- a tick of the cloth (`t` the clock, `omega` the spin, radians a second); its points out, for its section
local function cloth_sim(b, dt, t, omega)
    local C = M.CLOTH
    local cols = C.cols + 1
    local s, ux, uy = b.bs or 0.0, b.bux or 1.0, b.buy or 0.0
    local S = b.cl
    if not S then
        S = { x = {}, y = {}, z = {}, px = {}, py = {}, pz = {} }
        for j = 0, C.rows do
            for i = 0, C.cols do
                local k = j * cols + i + 1
                local x, y, z = cloth_rest(C, i, j, s, ux, uy)
                S.x[k], S.y[k], S.z[k], S.px[k], S.py[k], S.pz[k] = x, y, z, x, y, z
            end
        end
        b.cl = S
    end
    dt = math.min(dt, 1.0 / 20.0)
    local h = dt / 2.0
    local dxr, dzr = C.w / C.cols, C.h / C.rows
    -- (where each point lies on the flat flag: worked out again only when the pole has bent - each point's, each step,
    -- was the most of the race's time in a frame, 2026-11-05)
    local RS = S.rest
    if not RS or S.rs ~= s or S.rux ~= ux or S.ruy ~= uy then
        RS = RS or { x = {}, y = {}, z = {} }
        for j = 0, C.rows do
            for i = 0, C.cols do
                local k = j * cols + i + 1
                RS.x[k], RS.y[k], RS.z[k] = cloth_rest(C, i, j, s, ux, uy)
            end
        end
        S.rest, S.rs, S.rux, S.ruy = RS, s, ux, uy
    end
    local RX, RY, RZ = RS.x, RS.y, RS.z
    for _ = 1, 2 do
        for j = 0, C.rows do
            for i = 0, C.cols do
                local k = j * cols + i + 1
                local rx, ry, rz = RX[k], RY[k], RZ[k]
                local x, y, z = S.x[k], S.y[k], S.z[k]
                if i == 0 then
                    S.px[k], S.py[k], S.pz[k] = x, y, z
                    S.x[k], S.y[k], S.z[k] = rx, ry, rz
                else
                    local f = i / C.cols
                    local ax = C.k * (rx - x)
                    local ay = C.k * (ry - y) + C.wind * f * math.sin(t * 3.2 - i * 0.6 + j * 0.5) - omega * C.lag * (x - POLE_R) * C.k * 0.05
                    local az = C.k * (rz - z) - C.g
                    local px, py, pz = S.px[k], S.py[k], S.pz[k]
                    S.px[k], S.py[k], S.pz[k] = x, y, z
                    S.x[k] = x + (x - px) * C.damp + ax * h * h
                    S.y[k] = y + (y - py) * C.damp + ay * h * h
                    S.z[k] = z + (z - pz) * C.damp + az * h * h
                end
            end
        end
        for _ = 1, C.iters do
            for j = 0, C.rows do
                for i = 0, C.cols do
                    local k = j * cols + i + 1
                    if i < C.cols then keep_apart(S, k, k + 1, dxr, i == 0, false) end
                    if j < C.rows then keep_apart(S, k, k + cols, dzr, i == 0, i == 0) end
                end
            end
        end
    end
    -- (its points handed out in the same tables each time: lib.update_section copies them over at once)
    local out = S.out
    if not out then out = {}; S.out = out end
    for k = 1, #S.x do
        local o = out[k]
        if o then o.X, o.Y, o.Z = S.x[k], S.y[k], S.z[k] else out[k] = { X = S.x[k], Y = S.y[k], Z = S.z[k] } end
    end
    return out
end

local function base_actor(world, x, y, z, yaw)
    local a = lib.spawn_actor(world, { X = x + OFFSET.X, Y = y + OFFSET.Y, Z = z + OFFSET.Z }, yaw)
    if not a then return nil end
    local pmc = lib.add_pmc(a)
    if not pmc then return a end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    local gold, white = new_sec(0, "opaque", "race_gold"), new_sec(1, "opaque", "race_white")
    tube(gold, 40.0, 0.0, 9.0, 16, 1, true)             -- (the foot)
    tube(white, 26.0, 9.0, 21.0, 16, 1, true)           -- (its white ring)
    tube(gold, 12.0, 21.0, POLE_Z0, 12, 1, true)        -- (the collar)
    lib.add_sections(world, pmc, { gold, white })
    return a
end
-- the pole, its ball and cloths; and the pole's and ball's corners as made, to bend them from
local function pole_actor(world, x, y, z, yaw)
    local a = lib.spawn_actor(world, { X = x + OFFSET.X, Y = y + OFFSET.Y, Z = z + OFFSET.Z }, yaw)
    if not a then return nil end
    local pmc = lib.add_pmc(a)
    if not pmc then return a end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    local pole, ball = new_sec(SEC_POLE, "opaque", "race_gold"), new_sec(SEC_BALL, "opaque", "race_gold")
    tube(pole, POLE_R, POLE_Z0, POLE_Z1, POLE_SIDES, POLE_RINGS, false)
    sphere(ball, BALL_R, BALL_Z, 12, 8)
    local rest_pole, rest_ball = {}, {}
    for k, v in ipairs(pole.pos) do rest_pole[k] = v end
    for k, v in ipairs(ball.pos) do rest_ball[k] = v end
    lib.add_sections(world, pmc, { pole, ball, cloth(SEC_BOWSER, "race_cloth_bowser5"), cloth(SEC_MARIO, "race_cloth_mario2") })
    return a, pmc, rest_pole, rest_ball
end
-- the pole and its ball as bent now
local function deform(b)
    local s, ux, uy = b.bs or 0.0, b.bux or 1.0, b.buy or 0.0
    local P, out = b.rest_pole, {}
    for k = 0, #P // 3 - 1 do
        local ax, ay, az = axis(P[k * 3 + 3] - POLE_Z0, s, ux, uy)
        out[k + 1] = { X = ax + P[k * 3 + 1], Y = ay + P[k * 3 + 2], Z = az }
    end
    pcall(lib.update_section, b.pole_pmc, SEC_POLE, out)
    local Q, outb = b.rest_ball, {}
    local cx, cy, cz = axis(BALL_Z - POLE_Z0, s, ux, uy)
    for k = 0, #Q // 3 - 1 do outb[k + 1] = { X = cx + Q[k * 3 + 1], Y = cy + Q[k * 3 + 2], Z = cz + Q[k * 3 + 3] - BALL_Z } end
    pcall(lib.update_section, b.pole_pmc, SEC_BALL, outb)
end

local function show(a, on)
    if not a then return end
    pcall(function()
        -- (never one the scene's teardown has put away - retired, dying or a husk, lib.lua M.retire: a race stopped by
        -- the scene made again round him (race_stop's refresh, on the flags it still had) showed the old set again, and
        -- the teardown, finding them shown, left them standing for good - a second set of flags: "two flags inside
        -- eachother?", "theres duplicating flags again", 2026-11-08)
        if on then
            local K = package.loaded["lib"]
            local k = K and K.keep and K.keep[a:GetAddress()]
            if k == "retired" or k == "dying" or k == "husk" then return end
        end
        a:SetActorHiddenInGame(not on)
    end)
end

-- what is seen of each: its flag Bowser's or his, and the beam over the next one only
-- A course's race through more than one of its areas, in order (its start in the first): run on from one into the
-- next, the clock, the flags taken and the ghost's recording going on with him, the next area's flags numbered on from
-- the last's - "Carry into pyramid", 2026-11-07: Shifting Sand Land out on its sands and on into its pyramid. Its
-- finish in the last; its runs kept under the first's name. Dire, Dire Docks too: from the raft through the tunnel into
-- the sub's pool ("when the next area loaded the race ended", 2026-11-07). Tiny-Huge Island's from the tiny island
-- (game.lua G.STAR_START) on over to the huge one - its third flag there - and back to the tiny one, its eighth.
-- An area come back to has a leg of its own, "<scene>#<n>": its own flags, kept under that name ("8", back on the tiny
-- island, 2026-11-07). M.here is the leg he is on.
M.CHAIN = { ssl = { "ssl", "ssl_2" }, ddd = { "ddd", "ddd_2" }, thi = { "thi_2", "thi", "thi_2#2" } }
function M.leg_scene(k)
    return (type(k) == "string" and k:match("^([^#]+)")) or k
end
-- (the leg he is on, { key, scene } - set as he comes into a scene: M.tick)
M.LEG = nil
function M.here()
    local G = package.loaded["game"]
    local name = G and G.name
    if not name then return nil end
    local L = M.LEG
    if L and L.scene == name then return L.key end
    return name
end
-- (the finish of a course's last leg in its first leg's scene with no finish or line of its own: that start line - a
-- course that comes back round to its start ends over it. Tiny-Huge Island's, back on the tiny island: "also crossed the
-- finish line and the race didnt end", 2026-11-08 - its last leg's one flag taken, nothing ended it)
function M.home_line(leg)
    local ch, i = M.chain_of(leg)
    if not ch or i ~= #ch then return nil end
    local all = load_placed()
    local own = all[leg]
    if own and (own.finish or own.line) then return nil end
    local first = all[ch[1]]
    if first and first.line and M.leg_scene(ch[1]) == M.leg_scene(leg) then return first.line end
    return nil
end
-- (into scene `name` from leg `prev`: the next leg of prev's course in it, else the first leg anywhere in it, else it)
function M.leg_for(name, prev)
    if prev then
        local ch, i = M.chain_of(prev)
        if ch then
            for k = i + 1, #ch do if M.leg_scene(ch[k]) == name then return ch[k] end end
        end
    end
    for _, ch in pairs(M.CHAIN) do
        for _, s in ipairs(ch) do if M.leg_scene(s) == name then return s end end
    end
    return name
end
function M.chain_of(name)
    for _, ch in pairs(M.CHAIN) do
        for i, s in ipairs(ch) do if s == name then return ch, i end end
    end
    return nil
end
function M.course_key(name) local ch = M.chain_of(name); return ch and ch[1] or name end
function M.chain_last(name) local ch, i = M.chain_of(name); return not ch or i == #ch end
-- (the flags in the areas before this one, and in all of them)
function M.flag_base(name)
    local ch, i = M.chain_of(name)
    if not ch then return 0 end
    local n, all = 0, load_placed()
    for k = 1, i - 1 do n = n + #(all[ch[k]] or {}) end
    return n
end
function M.flags_total(name)
    local ch = M.chain_of(name)
    if not ch then return nil end
    local n, all = 0, load_placed()
    for _, s in ipairs(ch) do n = n + #(all[s] or {}) end
    return n
end

local function refresh()
    -- (the start line's beam: the way home, once every flag is taken in the race)
    local R = M.race
    -- (and lit to lead him to the ghost waiting there, the race lost; no flag's then)
    local lost = R ~= nil and (R.state == "lost" or R.state == "gloat" or R.state == "won" or R.state == "thank")
    -- (a flag's beam only while the race is run, from GO: "also before the race even starts the light in the sky is
    -- there", 2026-10-27)
    local running = R ~= nil and R.state == "run"
    -- (a race with a finish of its own and no flags lit for its finish from GO)
    -- (not in an area with more of its course after it: M.CHAIN)
    local Gm = package.loaded["game"]
    local lastarea = not (Gm and Gm.name) or M.chain_last(M.here())
    local home = (R ~= nil and R.state == "run" and lastarea and (#B > 0 or (M.LIST_FINISH and M.LIST_FINISH())) and M.next > #B) or lost
    for _, b in ipairs(LINE) do
        show(b.base, M.on)
        show(b.pole, M.on)
        show(b.strip, M.on)
        if b.home then show(b.beam, M.on and home) end
        -- (a flag of another leg: Mario's cloth once taken - build)
        if b.pole_pmc then
            local tk = b.taken == true
            pcall(function() b.pole_pmc:SetMeshSectionVisible(SEC_MARIO, tk) end)
            if b.taken ~= nil then
                pcall(function() b.pole_pmc:SetMeshSectionVisible(SEC_BOWSER, not tk) end)
                b.cloth_sec = tk and SEC_MARIO or SEC_BOWSER
            end
        end
    end
    for i, b in ipairs(B) do
        local passed = i < M.next
        show(b.base, M.on)
        show(b.pole, M.on)
        if b.pole_pmc then
            pcall(function() b.pole_pmc:SetMeshSectionVisible(SEC_BOWSER, not passed) end)
            pcall(function() b.pole_pmc:SetMeshSectionVisible(SEC_MARIO, passed) end)
        end
        b.cloth_sec = passed and SEC_MARIO or SEC_BOWSER
        -- (a ring: its cloth Bowser's, then Mario's once taken)
        show(b.ring_actor, M.on)
        if b.ring_pmc then
            pcall(function() b.ring_pmc:SetMeshSectionVisible(1, not passed) end)
            pcall(function() b.ring_pmc:SetMeshSectionVisible(2, passed) end)
        end
        show(b.digits, M.on)
        show(b.beam, M.on and running and i == M.next and not lost)
    end
end

-- room for a flag's cloth turned `yaw` at (px, py) on the floor fz: nothing within M.FLAG_CLEAR cm that way at the
-- cloth's height (a line traced at its foot and its top - only whether it meets anything is read)
M.FLAG_CLEAR = 200.0
local FLAG_C0 = { R = 0.0, G = 0.0, B = 0.0, A = 0.0 }
function M.flag_clear(px, py, fz, yaw)
    local ok, clear = pcall(function()
        M.KSL = M.KSL or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        local d = math.rad(yaw)
        local pw = lib.pawn()
        local ign = pw and { pw } or {}
        for _, h in ipairs({ 110.0, 190.0 }) do
            local hit = {}
            local a = { X = px + OFFSET.X, Y = py + OFFSET.Y, Z = fz + h + OFFSET.Z }
            local e = { X = a.X + math.cos(d) * M.FLAG_CLEAR, Y = a.Y + math.sin(d) * M.FLAG_CLEAR, Z = a.Z }
            if M.KSL:LineTraceSingle(lib.world(), a, e, 1, true, ign, 0, hit, true, FLAG_C0, FLAG_C0, 0) then return false end
        end
        return true
    end)
    return (not ok) or clear
end

local function build(world, name)
    clear()
    local list = load_placed()[name]
    if not list then return end
    for i, p in ipairs(list) do
        local x, y, z = p[1], p[2], p[3]
        local b = { x = x, y = y, z = z }
        -- (turned to face the way he comes: from the gate before - the first, the ghost racer's way - its cloth out
        -- to his right)
        local prev = list[i - 1]
        local st = list.start
        local come
        if prev then come = math.deg(math.atan(y - prev[2], x - prev[1]))
        elseif st then come = st[4] or 0.0
        elseif list[i + 1] then come = math.deg(math.atan(list[i + 1][2] - y, list[i + 1][1] - x))
        else come = 0.0 end
        b.yaw = come + 90.0
        if p.ring then
            -- (under the water: a ring to swim through - M.ring_actor)
            b.ring = p.ring
            b.ring_actor, b.ring_pmc = M.ring_actor(world, b)
        else
            b.base = base_actor(world, x, y, z, b.yaw)
            b.pole, b.pole_pmc, b.rest_pole, b.rest_ball = pole_actor(world, x, y, z, b.yaw)
        end
        -- (no number over it: "also you can remove the floating 1", 2026-10-27)
        b.cloth_sec = SEC_BOWSER
        -- (its beam, lit over the next one only - no fainter one over the one after: "only the checkpoint thats next up
        -- should show the light above it", 2026-10-27)
        b.beam = stand(world, x, y, z, M.BEAM_W, M.BEAM_H, M.BEAM_FROM, 0.5, "race_glow", "translucent")
        b.on = p.on                 -- (riding a platform: M.ride_tick)
        B[#B + 1] = b
    end
    -- (the same island's flags of the course's other legs here too - before this one Mario's, taken; after it still
    -- Bowser's - and its start line: back on the tiny island from the huge one, its first two flags and the start were
    -- gone, "Flags 1-2 / start line gone", 2026-11-08. Drawn only: not taken here, not counted, no way home over it)
    local borrowed_line = nil
    do
        local ch, li = M.chain_of(name)
        if ch then
            local sc = M.leg_scene(name)
            local all = load_placed()
            for k, other in ipairs(ch) do
                local ol = all[other]
                if k ~= li and ol and M.leg_scene(other) == sc then
                    if not list.line and ol.line then borrowed_line = ol.line end
                    for j, p in ipairs(ol) do
                        if not p.ring then
                            local prev = ol[j - 1]
                            local come = prev and math.deg(math.atan(p[2] - prev[2], p[1] - prev[1])) or ((ol.start and ol.start[4]) or 0.0)
                            local fb = { x = p[1], y = p[2], z = p[3], yaw = come + 90.0, taken = k < li, other_leg = true }
                            fb.base = base_actor(world, p[1], p[2], p[3], fb.yaw)
                            fb.pole, fb.pole_pmc, fb.rest_pole, fb.rest_ball = pole_actor(world, p[1], p[2], p[3], fb.yaw)
                            LINE[#LINE + 1] = fb
                        end
                    end
                end
            end
        end
    end
    -- (the start line: its checkered strip laid on the ground across the way run, a Bowser flag at each end, their
    -- cloths out to either side)
    -- (and a finish line of its own where it has one - list.finish, M.set_finish: made as the start line is, the way
    -- home lit over it and not over the start - "race end here", 2026-11-06, Bowser 1's)
    local home_by_start = list.line == nil and borrowed_line ~= nil and M.home_line(name) ~= nil
    for _, spec in ipairs({ { list.line or borrowed_line, (list.line ~= nil and not list.finish) or home_by_start }, { list.finish, true } }) do
    local ln, with_home = spec[1], spec[2]
    if ln then
        local G = package.loaded["game"]
        local cx, cy, cz, yaw, w = ln[1], ln[2], ln[3], ln[4], ln[5] or 700.0
        local fx, fy = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))         -- (the way run)
        local ax, ay = -fy, fx                                                  -- (along the line, to his right)
        -- (its checks square, `LINE_CHECK` cm each way, whatever its width - the picture was stretched once across it,
        -- 82 cm checks along it and 11 across on Bowser in the Fire Sea's 6.6 m start - and on under the flags at its
        -- ends, `LINE_UNDER` cm past them: "the checker pattern is streched also it doesnt go under the flags",
        -- 2026-11-07)
        local depth = M.LINE_DEPTH
        local half = w / 2.0 + (M.LINE_UNDER or 75.0)
        -- (corners every 25 cm along it and across it - every 50 along and its two edges only, a ridge of Bowser in the
        -- Sky's cracked rock between them stood up through it: "grounds poking through the floor a bit here", 2026-11-09)
        local cols = math.max(14, math.ceil(half * 2.0 / 25.0))
        local rows = math.max(1, math.ceil(depth / 25.0))
        local tile = (M.LINE_CHECK or 22.5) * 8.0                                -- (the picture: 8 checks a side)
        local s0 = new_sec(0, "opaque", "race_checker")
        -- (each of its corners on the ground under it, from its middle out to either end, each against the one before:
        -- 30 cm off that one - out past the floor's edge, under a flag - it is level with it. Against the middle's own
        -- height, a 7 m line across Tall, Tall Mountain's slope had its ends level - one in the hill, the other over
        -- it: "checker flag is bent and inside floor", 2026-11-07)
        -- (and each corner on the highest ground about it - its own spot and halfway to each corner beside it - so a
        -- ridge between corners stays under the strip)
        local function pos(i, j)
            local along = (i / cols - 0.5) * half * 2.0
            local off = (j / rows - 0.5) * depth
            return cx + ax * along + fx * off, cy + ay * along + fy * off
        end
        local function ground_at(px, py, near)
            local fz = G and G.floor_z and G.floor_z(px, py, near + 60.0)
            if not fz or math.abs(fz - near) > 30.0 then return nil end
            return fz
        end
        local function ground(i, j, near)
            local px, py = pos(i, j)
            local best = ground_at(px, py, near)
            for _, d in ipairs({ { 0.5, 0.0 }, { -0.5, 0.0 }, { 0.0, 0.5 }, { 0.0, -0.5 } }) do
                local qx, qy = pos(i + d[1], j + d[2])
                local q = ground_at(qx, qy, near)
                if q and (not best or q > best) then best = q end
            end
            return best or near
        end
        local zs = {}
        local mid = cols // 2
        for j = 0, rows do
            zs[j] = {}
            zs[j][mid] = ground(mid, j, cz)
            for i = mid + 1, cols do zs[j][i] = ground(i, j, zs[j][i - 1]) end
            for i = mid - 1, 0, -1 do zs[j][i] = ground(i, j, zs[j][i + 1]) end
        end
        for i = 0, cols do
            local along = (i / cols - 0.5) * half * 2.0
            for j = 0, rows do
                local px, py = pos(i, j)
                vert(s0, px - cx, py - cy, zs[j][i] + 2.5 - cz, 0.0, 0.0, 1.0, (along + half) / tile, (1.0 - j / rows) * depth / tile, 1.0)
            end
        end
        local R1 = rows + 1
        for i = 0, cols - 1 do
            for j = 0, rows - 1 do
                local p00 = i * R1 + j
                local p10 = p00 + R1
                tri(s0, p00, p10, p10 + 1)
                tri(s0, p00, p10 + 1, p00 + 1)
            end
        end
        local strip = lib.spawn_actor(world, { X = cx + OFFSET.X, Y = cy + OFFSET.Y, Z = cz + OFFSET.Z }, 0.0)
        if strip then
            local pmc = lib.add_pmc(strip)
            if pmc then
                pcall(function() pmc:SetCollisionEnabled(0) end)
                lib.add_sections(world, pmc, { s0 })
            end
            LINE[#LINE + 1] = { strip = strip }
        end
        for _, side in ipairs({ -1, 1 }) do
            local along = side * (w / 2.0 + 35.0)
            local px, py = cx + ax * along, cy + ay * along
            local fz = (G and G.floor_z and G.floor_z(px, py, cz + 120.0)) or cz
            -- (its cloth out past the line's end - or, with a wall in its way there, back the way run, on ahead, or
            -- in over the line, the first with room: DDD's finish by the dock's wall, "make flag face another way
            -- instead of inside the wall", 2026-11-07)
            local fyaw = yaw + side * 90.0
            for _, cand in ipairs({ yaw + side * 90.0, yaw + 180.0, yaw, yaw - side * 90.0 }) do
                if M.flag_clear(px, py, fz, cand) then fyaw = cand; break end
            end
            local fb = { x = px, y = py, z = fz, yaw = fyaw, cloth_sec = SEC_BOWSER, start_flag = true }
            fb.base = base_actor(world, px, py, fz, fb.yaw)
            fb.pole, fb.pole_pmc, fb.rest_pole, fb.rest_ball = pole_actor(world, px, py, fz, fb.yaw)
            LINE[#LINE + 1] = fb
        end
        -- (the way home: a beam over the line's middle, as a flag's, lit once every flag is taken - he is led back to
        -- the start and finishes over it: "then lead the player back to the start", 2026-10-27)
        if with_home then
            local hz = (G and G.floor_z and G.floor_z(cx, cy, cz + 120.0)) or cz
            local hb = stand(world, cx, cy, hz, M.BEAM_W, M.BEAM_H, M.BEAM_FROM, 0.5, "race_glow", "translucent")
            if hb then LINE[#LINE + 1] = { x = cx, y = cy, z = hz, beam = hb, home = true } end
        end
    end
    end
    refresh()
    pcall(M.sweep_strays, B, LINE)
    log("race: %d beacons in %s%s%s", #B, name, list.line and ", and the start line" or "", list.finish and ", and its finish" or "")
end

-- Flags left standing by an earlier drawing - forgotten, not taken down, when the scene's key changed under them while
-- they still stood (M.tick's `B = {}`) - looked for at every flag's spot after each drawing and taken down: anything of
-- the mod's (a StaticMeshActor, not kept) within 3 cm of a flag's spot that is not this drawing's own. Tick Tock Clock's
-- flags stood twice over, the one taken bent out of the untaken one's pole: "two flags inside eachother?", 2026-11-08
-- (ten pieces - a base and a pole - at five flags).
function M.sweep_strays(Bl, Ll)
    local mine, spots = {}, {}
    local function own(b)
        for _, a in ipairs({ b.base or false, b.pole or false, b.beam or false, b.strip or false, b.ring_actor or false }) do
            if a then pcall(function() mine[a:GetAddress()] = true end) end
        end
    end
    for _, b in ipairs(Bl or {}) do own(b); if b.x then spots[#spots + 1] = { b.x, b.y, b.z } end end
    for _, b in ipairs(Ll or {}) do own(b); if b.x and b.pole then spots[#spots + 1] = { b.x, b.y, b.z } end end
    if #spots == 0 then return 0 end
    local ok, list = pcall(FindAllOf, "StaticMeshActor")
    if not (ok and list) then return 0 end
    local doomed = {}
    for _, a in ipairs(list) do
        pcall(function()
            if a:IsValid() and not mine[a:GetAddress()] and not lib.keep[a:GetAddress()] then
                local l = a:K2_GetActorLocation()
                local x, y, z = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z
                for _, s in ipairs(spots) do
                    if math.abs(x - s[1]) < 3.0 and math.abs(y - s[2]) < 3.0 and math.abs(z - s[3]) < 3.0 then
                        doomed[#doomed + 1] = a
                        break
                    end
                end
            end
        end)
    end
    for _, a in ipairs(doomed) do pcall(lib.destroy, a, false) end
    if #doomed > 0 then lib.log("race: %d stray flag pieces taken down", #doomed) end
    return #doomed
end

-- start again: every flag Bowser's, the first the next
function M.reset()
    M.next, M.times = 1, {}
    refresh()
end

-- ------------------------------------------------------------ the pole bending, the flag taken
-- each tick: pushed by him (x, y his middle across, z his feet), the spring, the spin after a taking; the pole bent to
-- match, and the pole's part turned with the spin
local function bend(b, dt, x, y, z)
    local B2 = M.BEND
    local gx, gy = 0.0, 0.0
    local dx, dy = b.x - x, b.y - y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < B2.r and z < b.z + M.FLAG_H and z + 180.0 > b.z then
        local m = math.sin(math.rad(B2.max)) * math.min(1.0, (B2.r - d) / B2.r * 1.6)
        if d < 1.0 then dx, dy, d = 1.0, 0.0, 1.0 end
        gx, gy = dx / d * m, dy / d * m
    end
    local tx, ty, vx, vy = b.tx or 0.0, b.ty or 0.0, b.vx or 0.0, b.vy or 0.0
    local moving = gx ~= 0.0 or gy ~= 0.0 or math.abs(tx) + math.abs(ty) + math.abs(vx) + math.abs(vy) > 0.002
    local spinning = b.spin_t ~= nil
    b.spin_w = 0.0
    if not (moving or spinning or b.bent) then return end
    local steps = math.max(1, math.ceil(dt * 120.0))
    local h = dt / steps
    for _ = 1, steps do
        vx = vx + (B2.k * (gx - tx) - B2.c * vx) * h
        vy = vy + (B2.k * (gy - ty) - B2.c * vy) * h
        tx, ty = tx + vx * h, ty + vy * h
    end
    local lim = math.sin(math.rad(B2.max))
    local l = math.sqrt(tx * tx + ty * ty)
    if l > lim then tx, ty = tx / l * lim, ty / l * lim end
    if not moving then tx, ty, vx, vy = 0.0, 0.0, 0.0, 0.0 end
    b.tx, b.ty, b.vx, b.vy = tx, ty, vx, vy
    -- (and a springy metal twang as he walks into it, the harder the louder - tools/pole_twang.py: "can you make a
    -- metal bending noise when walking into the pole", then "thats a bad metal bending sound" for the merry-go-round's
    -- creak, 2026-10-27. Once a push, not again for 0.4 s)
    local pushing = gx ~= 0.0 or gy ~= 0.0
    if pushing and not b.pushed and os.clock() - (b.twang_at or 0.0) > 0.4 then
        b.twang_at = os.clock()
        local SFX = package.loaded["sfx"]
        local hit = math.min(1.0, 0.45 + math.sqrt(gx * gx + gy * gy))
        if SFX and SFX.play then pcall(SFX.play, "pole_ting_" .. math.random(1, 3), hit, true) end
    end
    b.pushed = pushing
    if spinning then
        local before = b.spin or 0.0
        b.spin_t = b.spin_t + dt
        local f = math.min(1.0, b.spin_t / M.SPIN.time)
        b.spin = 360.0 * M.SPIN.turns * (1.0 - (1.0 - f) ^ 3)
        b.spin_w = math.rad(b.spin - before) / math.max(dt, 1e-3)
        if f >= 1.0 then b.spin_t, b.spin = nil, 0.0 end
        pcall(function() b.pole:K2_SetActorRotation({ Pitch = 0.0, Yaw = b.yaw + (b.spin or 0.0), Roll = 0.0 }, false) end)
    end
    -- (the lean into the pole's own turned space)
    local a = math.rad(b.yaw + (b.spin or 0.0))
    local lx, ly = tx * math.cos(a) + ty * math.sin(a), -tx * math.sin(a) + ty * math.cos(a)
    local sv = math.sqrt(lx * lx + ly * ly)
    b.bs = sv
    if sv > 1e-4 then b.bux, b.buy = lx / sv, ly / sv end
    if moving or b.bent then deform(b) end
    b.bent = moving
end

-- The Power Star's twinkles round a flag taken: each a square turned to the camera holding all six of the sparkles'
-- pictures (ending_sparkle_0-5, the star's own), one shown at a time - each picture's material kept by its square, never
-- swapped - swirling up round the pole, growing then shrinking away
local FX = { pool = nil, world = nil }
local function twinkle_actor(world)
    local a = lib.spawn_actor(world, { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z - 100000.0 }, 0.0)
    if not a then return nil end
    -- (kept from the scenes' sweep of stale actors: the pool lasts the map, and a twinkle once used lies hidden where it
    -- went out, up among the scene's things - swept with them at the next scene, it was touched freed at the next flag
    -- taken and the game went down, 2026-10-27 19:41)
    pcall(function() lib.keep[a:GetAddress()] = "race fx" end)
    local pmc = lib.add_pmc(a)
    if not pmc then return a end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    local h = M.TWINKLE.size / 2.0
    local secs = {}
    for k = 0, 5 do
        secs[#secs + 1] = { id = k, layer = "alpha", texture = "ending_sparkle_" .. k, nverts = 4, ntris = 2,
            pos = { 0, -h, -h, 0, h, -h, 0, h, h, 0, -h, h },
            uv = { 0, 1, 1, 1, 1, 0, 0, 0 },
            col = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
            nrm = { -1, 0, 0, -1, 0, 0, -1, 0, 0, -1, 0, 0 },
            idx = { 0, 1, 2, 0, 2, 3 } }
    end
    lib.add_sections(world, pmc, secs)
    for k = 1, 5 do pcall(function() pmc:SetMeshSectionVisible(k, false) end) end
    return a, pmc
end
local function fx_pool(world)
    local here = nil
    pcall(function() here = world:GetAddress() end)
    -- (one pool for the map, kept through its scenes: under the height the scenes' sweep takes, a new one made at each
    -- scene left the last standing hidden for good. Made again only if it is gone.)
    if FX.pool and FX.world == here then
        -- (every one of them there still, not only the first: one used and swept had the rest taken for whole)
        local whole = #FX.pool > 0
        for _, p in ipairs(FX.pool) do
            if not (pcall(function() return p.actor:IsValid() end) and p.actor:IsValid()) then whole = false; break end
        end
        if whole then return FX.pool end
        for _, p in ipairs(FX.pool) do pcall(function() lib.keep[p.actor:GetAddress()] = nil end) end
    end
    FX.world, FX.pool = here, {}
    for _ = 1, M.TWINKLE.n do
        local a, pmc = twinkle_actor(world)
        if a then
            pcall(function() a:SetActorHiddenInGame(true) end)
            FX.pool[#FX.pool + 1] = { actor = a, pmc = pmc, t = nil, frame = 0 }
        end
    end
    return FX.pool
end
local function burst(b)
    local world = lib.world()
    if not world then return end
    local pool = fx_pool(world)
    local C = M.TWINKLE
    for i, p in ipairs(pool) do
        p.cx, p.cy = b.x, b.y
        p.a = (i / #pool) * 2.0 * math.pi + math.random() * 0.3
        p.r = C.r * (0.75 + math.random() * 0.5)
        p.z = b.z + 30.0 + ((i - 1) % 4) * 45.0
        p.rise = C.rise * (0.8 + math.random() * 0.4)
        p.t, p.delay, p.life = 0.0, (i - 1) * C.stagger, C.life * (0.8 + math.random() * 0.4)
        p.f0 = math.random(0, 5)
    end
end
local function fx_tick(dt, cx, cy)
    if not FX.pool then return end
    local C = M.TWINKLE
    for _, p in ipairs(FX.pool) do
        if p.t then
            p.t = p.t + dt
            local tt = p.t - p.delay
            if tt >= p.life then
                p.t = nil
                pcall(function() p.actor:SetActorHiddenInGame(true) end)
            elseif tt >= 0.0 then
                local a = p.a + C.turn * tt
                local r = p.r * (1.0 + 0.4 * tt)
                local x, y, z = p.cx + math.cos(a) * r, p.cy + math.sin(a) * r, p.z + p.rise * tt
                -- (its picture: the six in turn, fifteen a second; its size up quickly and away slowly)
                local f = (p.f0 + math.floor(tt * 15.0)) % 6
                if f ~= p.frame and p.pmc then
                    local old = p.frame
                    pcall(function() p.pmc:SetMeshSectionVisible(old, false); p.pmc:SetMeshSectionVisible(f, true) end)
                    p.frame = f
                end
                local u = tt / p.life
                local k = math.max(0.05, math.min(1.0, u / 0.15) * (1.0 - u * u))
                local wx, wy = x + OFFSET.X, y + OFFSET.Y
                local yaw = math.deg(math.atan(wy - cy, wx - cx))
                pcall(function()
                    p.actor:SetActorHiddenInGame(false)
                    p.actor:K2_SetActorLocationAndRotation({ X = wx, Y = wy, Z = z + OFFSET.Z }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false, {}, true)
                    p.actor:SetActorScale3D({ X = k, Y = k, Z = k })
                end)
            end
        end
    end
end

-- ------------------------------------------------------------ the race's start
-- The ghost racer: at the start (`start`), a copy of the athlete as he stood when the course was entered - each of his
-- meshes copied and posed as his were, his own materials - drawn every other frame, half there, as the vanish cap's
-- ghost is (caps.lua: the mod's materials do not take on his skinned meshes). Pushed at, facing him, he asks (DIALOG
-- 9001); "Go!" and the race: the athlete put on the line beside him and held, 3 2 1 in the HUD's digits a second
-- apiece, GO, and he is off - the clock under the stars (health.lua's race time), the first flag taken at the line.
-- The last flag taken, the clock stops there. (The ghost's own run comes with his recording.)
M.RACE_SEED = 6447          -- (chance at every start from this: the creatures' wanderings the same each time)
M.RACE_TALK = { reach = 200.0, facing = 75.0, side = 100.0, ghost_side = -100.0 }   -- (cm to the right of the start: the
-- athlete on the line, the ghost racer - side by side in the line's middle, as close as they go without touching: "also
-- make both players start in the middle of the start line", "at the start of the race push the players as close to the
-- middle as possible without them both touching", 2026-10-27. Measured standing: his bones to 29 cm on his left, 31 on
-- his right; the racer's idle 31 on his right, toward him - 60 cm of bone between their middles, an arm's thickness each
-- side and a little room: 76. They were 140 right and 120 left. Then a metre each side, 2 m apart, once the ghost's start
-- had been eased: "now that the start is smoother you can move the players further from eachother again", 2026-10-27)
M.GHOST_FLICKER = false     -- (true: drawn every other frame, half there - the ghost he was; the metal one is solid)
M.LINE_DEPTH = 90.0         -- cm: the start line's strip, along the way run
M.LINE_CHECK = 22.5         -- cm: each of its checks (4 across the strip)
M.LINE_UNDER = 75.0         -- cm: the strip on past each end of the line, under its flags (35 past it) and all of
                            -- their round bases ("checker start line needs a little bit more", 2026-11-07)
M.RACER_HAIR = false        -- (his hair, brows and beard: none on the metal statue, as the metal cap's)
-- (his idle, looping: STORROR's own standing idle from its locomotion set - "he needs an idle animation", 2026-10-27)
M.RACER_IDLE = "/SPP/SPPCharacter/Animation/Idle/Idle/Idle_116_Drew_131024_Locomotion-001.Idle_116_Drew_131024_Locomotion-001"
-- (and Mario's cap, nose and mustache, and a backpack on his back - "also a hat and backpack": metal both)
M.RACER_CAP, M.RACER_PACK = true, true
-- (in Metal Mario's chrome, laid on by where they face as the camera sees them: "his bag needs the metal texture")
M.CHROME_TEX = "actors__mario__mario_metal.rgba16"
-- (Mario's cap only: his nose and mustache - mariolook.lua's pieces 0 and 1 - left off: "remove the nose and mustashe")
M.RACER_HIDE = { [0] = true, [1] = true }
local RACE = { state = nil }
M.race = RACE
-- (the star he gives up, rainbow as the one in his bag, its colours running: M.tick, while it is in this world)
local RB = nil
local GH = { actor = nil, key = nil, still = 0.0, waited = 0.0, flick = false }
-- the racer taken away, and what is hung on him: Mario's look (mariolook.lua keeps it through a scene's sweep) and his
-- backpack
local function ghost_drop()
    local ML = package.loaded["mariolook"]
    if GH.addr and ML and ML.undress then pcall(ML.undress, GH.addr) end
    if GH.star and GH.star.actor then pcall(lib.destroy, GH.star.actor, false) end
    if GH.pack then pcall(lib.destroy, GH.pack, false) end
    if GH.actor then pcall(lib.destroy, GH.actor, false) end
    GH.actor, GH.pack, GH.addr, GH.star, GH.pack_pmc, GH.pack_sec, GH.chrome_done = nil, nil, nil, nil, nil, nil, nil
    GH.body, GH.idle_src, GH.body_rel, GH.rep, GH.gone = nil, nil, nil, nil, nil
    GH.star_mid = nil           -- (gone with the star: never called on after - a material on no mesh is freed)
end

-- ------------------------------------------------------------ the ghost: a run recorded, and played back on him
local okgr, GR = pcall(require, "raceghost")
if not okgr then log("race: no ghost recording (%s)", tostring(GR)); GR = nil end
-- (s: from where he stands at GO onto the run's own line - an offset from it fading smoothly away. Half a second, he
-- slid across through him to where the run began - "starting positions are awkward", "players in front of the ghost",
-- 2026-10-27)
M.GHOST_EASE = 2.5

-- a save file's best run in this level, if it is that file's (not one left by a file since wiped - its play time
-- more than the file's now)
local function file_ghost(scene)
    local MN = _G.MENU
    local slot = MN and MN.file
    if not (GR and slot) then return nil end
    local g = GR.load(GR.file_path(slot, scene))
    if not g then return nil end
    local played = (MN.run_time and MN.run_time()) or 0.0
    if played + 1.0 < (g.played or 0.0) then return nil end
    return g
end

-- the ghost to race: the level's own, or this file's best if that is the faster
local function ghost_to_race(scene)
    if not GR then return nil end
    local orig = GR.load(GR.original_path(scene))
    local mine = file_ghost(scene)
    if mine and (not orig or mine.final < orig.final) then return mine, "your best" end
    return orig, orig and "the level's" or nil
end

-- a finished run kept: the level's own ghost when it has none yet; else the file's best when it beats that. Which.
local function keep_run(scene, run)
    if not (GR and run) then return nil end
    local orig = GR.load(GR.original_path(scene))
    local MN = _G.MENU
    local slot = MN and MN.file
    if not orig then
        if not GR.save(GR.original_path(scene), run, 0.0) then return nil end
        -- (and the file's best too, so its time shows on the star select)
        if slot then GR.save(GR.file_path(slot, scene), run, (MN.run_time and MN.run_time()) or 0.0) end
        return "the level's ghost"
    end
    if not slot then return nil end
    -- (the maker's runs, while M.MAKER is on - set from the dev channel, never in the file - a faster run is the level's
    -- own ghost from then on: "im gonna improve the time of the ghost, I been going slow so get ready to update it",
    -- 2026-10-27)
    if M.MAKER and run.final < orig.final then
        if not GR.save(GR.original_path(scene), run, 0.0) then return nil end
        if slot then GR.save(GR.file_path(slot, scene), run, (MN.run_time and MN.run_time()) or 0.0) end
        return string.format("the level's ghost now (%.2f s, was %.2f)", run.final, orig.final)
    end
    local mine = file_ghost(scene)
    if mine and run.final >= mine.final then return nil end
    local beat = run.final < math.min(orig.final, mine and mine.final or math.huge)
    if GR.save(GR.file_path(slot, scene), run, (MN.run_time and MN.run_time()) or 0.0) then
        return beat and "the ghost now - it beat the last one" or "your best (the ghost is still faster)"
    end
    return nil
end

-- each tick: his body posed - by the run played back in the race, else by his idle
M.GHOST_FAR = 2500.0             -- (cm from the camera past which the ghost is posed only every GHOST_FAR_EVERY frames)
M.GHOST_FAR_EVERY = 3
local function ghost_pose()
    local body = GH.body
    if not (GH.actor and body) then return end
    local rp = GH.rep
    if rp and GR then
        local t = os.clock() - rp.t0
        local ok, bw, bones, done = pcall(GR.pose, rp.g, t, rp.cur)
        if not ok then
            log("race ghost: playback stopped (%s)", tostring(bw))
            GH.rep = nil
            return
        end
        -- (his run in another area of the course from him just now - M.CHAIN: not shown here, nor posed)
        local Gm = package.loaded["game"]
        local here = Gm and Gm.name
        GH.away = (GR.scene_at and here and rp.g.seams and GR.scene_at(rp.g, t, M.course_key(here)) ~= here) or nil
        if GH.away then
            if done then
                rp.done_t = rp.done_t or os.clock()
                if os.clock() - rp.done_t > 1.5 then GH.rep = nil end
            end
            return
        end
        -- (the actor where his body comes where the run had it: actor = body * his body's place in it, undone)
        local r = GH.body_rel
        local cx, cy, cz, cw = -r[4], -r[5], -r[6], r[7]
        local qx, qy, qz, qw = GR.qmul(bw[4], bw[5], bw[6], bw[7], cx, cy, cz, cw)
        local ox, oy, oz = GR.qrot(qx, qy, qz, qw, r[1], r[2], r[3])
        local ax, ay, az = bw[1] - ox, bw[2] - oy, bw[3] - oz
        if rp.from then
            if not rp.off then rp.off = { rp.from[1] - ax, rp.from[2] - ay, rp.from[3] - az } end   -- (on his first frame)
            if t < M.GHOST_EASE then
                local u = math.max(0.0, t / M.GHOST_EASE)
                local k = 1.0 - u * u * (3.0 - 2.0 * u)
                ax, ay, az = ax + rp.off[1] * k, ay + rp.off[2] * k, az + rp.off[3] * k
            end
        end
        pcall(function()
            GH.actor:K2_SetActorTransform({ Rotation = { X = qx, Y = qy, Z = qz, W = qw },
                Translation = { X = ax + OFFSET.X, Y = ay + OFFSET.Y, Z = az + OFFSET.Z }, Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } },
                false, {}, true)
        end)
        -- (his bones: one transform table filled for each, no new ones; the twist bones left - they follow the arm
        -- they lie along - and a ghost far off posed every M.GHOST_FAR_EVERY frames: "when I was racing ghost in
        -- bomb omb battlefield", stutters, 2026-11-03)
        rp.frame = (rp.frame or 0) + 1
        local far = false
        pcall(function()
            local c = lib.controller().PlayerCameraManager:GetCameraLocation()
            local dx, dy, dz = c.X - (ax + OFFSET.X), c.Y - (ay + OFFSET.Y), c.Z - (az + OFFSET.Z)
            far = dx * dx + dy * dy + dz * dz > M.GHOST_FAR * M.GHOST_FAR
        end)
        if not far or rp.frame % M.GHOST_FAR_EVERY == 0 then
            local T = rp.T
            if not T then
                T = { Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = 0.0, Y = 0.0, Z = 0.0 },
                      Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }
                rp.T = T
                rp.set = body.SetBoneTransformByName
                rp.skip = {}
                for j, n in ipairs(rp.g.names or GR.BONES) do if tostring(n):find("twist") then rp.skip[j] = true end end
            end
            local R, P = T.Rotation, T.Translation
            for j, fn in ipairs(rp.g.fnames) do
                if not rp.skip[j] then
                    local b = bones[j]
                    R.X, R.Y, R.Z, R.W = b[4], b[5], b[6], b[7]
                    P.X, P.Y, P.Z = b[1], b[2], b[3]
                    pcall(rp.set, body, fn, T, 1)
                end
            end
        end
        -- (his run over: a moment held, then his idle where he ended - set down on the floor under it, upright: a run
        -- ended in the air - over the line in a jump - left him standing on nothing, "finished racer is floating in air",
        -- 2026-11-08)
        if done then
            rp.done_t = rp.done_t or os.clock()
            if os.clock() - rp.done_t > 1.5 then
                GH.rep = nil
                pcall(function()
                    local Gm = package.loaded["game"]
                    local l = GH.actor:K2_GetActorLocation()
                    local half = (Gm and Gm.half) or 90.0
                    local fz = Gm and Gm.floor_z and Gm.floor_z(l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z)
                    if fz and l.Z - OFFSET.Z - half - fz < 2000.0 then
                        local yaw = GH.actor:K2_GetActorRotation().Yaw
                        GH.actor:K2_SetActorLocationAndRotation({ X = l.X, Y = l.Y, Z = fz + half + OFFSET.Z },
                            { Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false, {}, true)
                    end
                end)
            end
        end
        return
    end
    if GH.idle_src then pcall(function() body:CopyPoseFromSkeletalComponent(GH.idle_src) end) end
end

-- where the racer stands: where he was put (`racer`), or beside the start, `ghost_side` to its right; and his way
-- (both a little behind the line, not on it: "doesnt start behind the line", 2026-10-27)
-- (cm back from the line's middle, against the way run - the strip 90 deep: 70 left him 25 cm off its back edge,
-- standing on it as the camera saw it - "player still doesnt start behind the line", 2026-10-27)
M.LINE_BEHIND = 150.0
local function behind(st, side)
    local yaw = math.rad(st[4] or 0.0)
    local r = yaw + math.pi / 2.0
    return st[1] + math.cos(r) * side - math.cos(yaw) * M.LINE_BEHIND,
           st[2] + math.sin(r) * side - math.sin(yaw) * M.LINE_BEHIND
end
local function line_spot(st)
    local x, y = behind(st, M.RACE_TALK.ghost_side)
    return x, y, st[3], st[4] or 0.0
end
local function ghost_spot(list)
    local rc = list.racer
    if rc then return rc[1], rc[2], rc[3], rc[4] or 0.0 end
    return line_spot(list.start)
end
local IDENT = { Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = 0.0, Y = 0.0, Z = 0.0 }, Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }

-- The racer's backpack: a rounded pack - a superellipsoid, `a` deep, `b` wide, `c` tall (half each, cm), its edges
-- rounded by `e` (1 an egg, toward 0 a box) - behind his back; its back a pane of glass (the faces turned back), the
-- silver inside of it there to be seen through it, a Power Star turning in it; round straps over his shoulders and down
-- his front. Its own space: x on the way he faces, its pivot at his chest. ("make the back of the bag seethrough and
-- inside it a star", "also the bag is super blocky smooth it out", 2026-10-27)
M.PACK = { cx = -16.0, cz = -4.0, a = 9.5, b = 17.0, c = 23.0, e = 0.45, nu = 28, nv = 16, star = 0.3 }
-- (a Bowser course's big brother carries his key in it instead, rainbow, stood on end - "for the ghost runner in this
-- level put a rainbow key in his bag", 2026-11-06: Bowser's key at `key` of its size, lowered `key_dz` cm to its middle)
M.PACK.key, M.PACK.key_dz = 0.07, 8.0
local function spow(x, e) return (x < 0.0 and -1.0 or 1.0) * math.abs(x) ^ e end
-- Drawstrings: two cords from the top of the pack's back, hanging free - Unreal's own rope, CableComponent, so they swing
-- with his run, his flips and his stops ("can you add physix draw strings to the backpack?", 2026-10-30). Pack space,
-- cm: from under its bottom (at -27), either side of the middle ("they should be at the bottom of the bag", "also
-- further apart slightly", then "a molicule up and a little tiny bit further from eachother": 22 cm apart).
M.PACK_CORDS = { len = 26.0, segs = 10, width = 0.9, at = { { -18.0, 11.0, -25.5 }, { -18.0, -11.0, -25.5 } } }
local function pack_cords(pk, mat)
    local cls = StaticFindObject("/Script/CableComponent.CableComponent")
    if not (cls and cls:IsValid()) then return 0 end
    local C, n = M.PACK_CORDS, 0
    for _, a in ipairs(C.at) do
        pcall(function()
            local t = { Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = a[1], Y = a[2], Z = a[3] },
                        Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }
            local c = pk:AddComponentByClass(cls, false, t, true)
            if not (c and c:IsValid()) then return end
            c.CableLength, c.NumSegments, c.CableWidth, c.NumSides = C.len, C.segs, C.width, 6
            c.bAttachStart, c.bAttachEnd = true, false
            c.SolverIterations, c.bEnableStiffness, c.CableGravityScale = 4, true, 1.0
            pk:FinishAddComponent(c, false, t)
            if mat then pcall(function() c:SetMaterial(0, mat) end) end
            pcall(function() c:SetCastShadow(false) end)
            n = n + 1
        end)
    end
    return n
end

-- (`into`: where its pieces are kept - the racer's GH, or the GHOST RUNNER skin's own: M.pack_on)
local function make_pack(world, gx, gy, gz, gyaw, silver, into)
    into = into or GH
    local P = M.PACK
    local shell, glass = new_sec(0, "opaque", "race_white"), new_sec(1, "translucent", "race_glass")
    -- (a point of the pack and the way it faces, `k` times its size, `inward` turned in)
    local function at(u, v, k)
        local cu, su, cv, sv = math.cos(u), math.sin(u), math.cos(v), math.sin(v)
        local x = P.cx + k * P.a * spow(cv, P.e) * spow(cu, P.e)
        local y = k * P.b * spow(cv, P.e) * spow(su, P.e)
        local z = P.cz + k * P.c * spow(sv, P.e)
        local nx = spow(cv, 2.0 - P.e) * spow(cu, 2.0 - P.e) / P.a
        local ny = spow(cv, 2.0 - P.e) * spow(su, 2.0 - P.e) / P.b
        local nz = spow(sv, 2.0 - P.e) / P.c
        local l = math.sqrt(nx * nx + ny * ny + nz * nz)
        if l < 1e-6 then nx, ny, nz, l = 0.0, 0.0, (sv >= 0.0) and 1.0 or -1.0, 1.0 end
        return x, y, z, nx / l, ny / l, nz / l
    end
    local nu, nv = P.nu, P.nv
    local function grid(sec, k, inward, keep)
        local ids = {}
        for j = 0, nv do
            local v = -math.pi / 2.0 + j / nv * math.pi
            for i = 0, nu do
                local u = -math.pi + i / nu * 2.0 * math.pi
                local x, y, z, nx, ny, nz = at(u, v, k)
                if inward then nx, ny, nz = -nx, -ny, -nz end
                ids[j * (nu + 1) + i] = vert(sec, x, y, z, nx, ny, nz, i / nu, j / nv, inward and 0.7 or lit(nx, ny, nz))
            end
        end
        for j = 0, nv - 1 do
            for i = 0, nu - 1 do
                -- (its back - the faces turned back, away from him - glass; the rest its shell)
                local um, vm = -math.pi + (i + 0.5) / nu * 2.0 * math.pi, -math.pi / 2.0 + (j + 0.5) / nv * math.pi
                local _, _, _, mx, my, mz = at(um, vm, 1.0)
                local back = mx < -0.55
                if keep(back) then
                    local a0, b0 = ids[j * (nu + 1) + i], ids[(j + 1) * (nu + 1) + i]
                    tri(sec, a0, b0, b0 + 1)
                    tri(sec, a0, b0 + 1, a0 + 1)
                end
            end
        end
    end
    grid(shell, 1.0, false, function(back) return not back end)        -- (its outside)
    grid(shell, 0.9, true, function(back) return not back end)          -- (its inside, seen through the glass)
    grid(glass, 1.0, false, function(back) return back end)             -- (the glass)
    -- the straps: round tubes along a path, over his shoulders from the pack's top and down his front
    local function strap(path, r)
        local sides = 8
        local rings = {}
        for q, pnt in ipairs(path) do
            local nxt, prv = path[math.min(#path, q + 1)], path[math.max(1, q - 1)]
            local tx, ty, tz = nxt[1] - prv[1], nxt[2] - prv[2], nxt[3] - prv[3]
            local tl = math.sqrt(tx * tx + ty * ty + tz * tz)
            tx, ty, tz = tx / tl, ty / tl, tz / tl
            -- (two ways across it: its side, y, and the one square to both)
            local sx, sy, sz = 0.0, 1.0, 0.0
            local ux, uy, uz = ty * sz - tz * sy, tz * sx - tx * sz, tx * sy - ty * sx
            local ul = math.sqrt(ux * ux + uy * uy + uz * uz)
            ux, uy, uz = ux / ul, uy / ul, uz / ul
            sx, sy, sz = uy * tz - uz * ty, uz * tx - ux * tz, ux * ty - uy * tx
            local ring = {}
            for k = 0, sides do
                local t = k / sides * 2.0 * math.pi
                local nx = math.cos(t) * ux + math.sin(t) * sx * 0.45
                local ny = math.cos(t) * uy + math.sin(t) * sy * 0.45
                local nz = math.cos(t) * uz + math.sin(t) * sz * 0.45
                local px = pnt[1] + (math.cos(t) * ux + math.sin(t) * sx * 2.2) * r
                local py = pnt[2] + (math.cos(t) * uy + math.sin(t) * sy * 2.2) * r
                local pz = pnt[3] + (math.cos(t) * uz + math.sin(t) * sz * 2.2) * r
                local nl = math.sqrt(nx * nx + ny * ny + nz * nz)
                ring[k] = vert(shell, px, py, pz, nx / nl, ny / nl, nz / nl, k / sides, q / #path, lit(nx / nl, ny / nl, nz / nl))
            end
            rings[q] = ring
        end
        for q = 1, #path - 1 do
            for k = 0, sides - 1 do
                tri(shell, rings[q][k], rings[q + 1][k], rings[q + 1][k + 1])
                tri(shell, rings[q][k], rings[q + 1][k + 1], rings[q][k + 1])
            end
        end
    end
    for _, sy in ipairs({ -1.0, 1.0 }) do
        local y = sy * 9.5
        strap({ { -9.0, y, 16.0 }, { -4.0, y, 23.5 }, { 3.0, y, 26.0 }, { 9.5, y, 23.0 }, { 12.5, y, 14.0 }, { 13.0, y, 0.0 },
                { 12.0, y, -16.0 } }, 1.2)
    end
    local yaw = gyaw
    local pk = lib.spawn_actor(world, { X = gx + OFFSET.X, Y = gy + OFFSET.Y, Z = gz + OFFSET.Z + 122.0 }, yaw)
    if not pk then return nil end
    pcall(function() pk:SetActorEnableCollision(false) end)
    local pmc = lib.add_pmc(pk)
    if pmc then
        pcall(function() pmc:SetCollisionEnabled(0) end)
        for i = 1, #shell.col do shell.col[i] = 1.0 end          -- (white under the chrome, as the cap's pieces are)
        lib.add_sections(world, pmc, { shell, glass })
        if silver then pcall(function() pmc:SetMaterial(0, silver) end) end
        into.pack_pmc, into.pack_sec = pmc, shell
    end
    -- (the Power Star inside it, small, turning - or a Bowser course's big brother's key, M.PACK.key)
    pcall(function()
        local G = package.loaded["game"]
        local lv = G and G.name
        pcall(function() lv = G.level_of(G.name) end)
        local keyed = into == GH and M.STAGE and M.STAGE[lv or ""] ~= nil
        local data = lib.load_data(keyed and "data.actor_geo_bowser_key_geo" or "data.actor_star")
        if not data then return end
        local f = math.rad(yaw)
        local wx = gx + OFFSET.X + math.cos(f) * P.cx
        local wy = gy + OFFSET.Y + math.sin(f) * P.cx
        local wz = gz + OFFSET.Z + 122.0 + P.cz - 6.0 + (keyed and (P.key_dz or 0.0) or 0.0)
        local inst = lib.make_instance(world, data, { X = wx, Y = wy, Z = wz }, yaw, keyed and (P.key or 0.12) or P.star)
        if inst then
            inst.actor:K2_AttachToActor(pk, FName("None"), 1, 1, 1, false)
            -- (nothing in it solid: on the GHOST RUNNER skin's back the star stood in the camera's way - its guard met it
            -- behind his back and drew the camera in to him, "camera keeps getting zoomed in randomly", 2026-11-08)
            pcall(function() inst.actor:SetActorEnableCollision(false) end)
            into.star, into.star_yaw = inst, 0.0
            into.star_roll = keyed and 90.0 or nil         -- (the key stood on end: race_tick turns it so)
            -- (the racer's star rainbow, as the GHOST RUNNER skin's and Bowser's mega star: textures/rainbow_star.png on
            -- its faces, its eyes as they are, the colours running over it - race_tick. "make the star in his bag
            -- rainbow", 2026-11-05. The skin's own bag is made so by caps.lua.)
            if into == GH then
                local mid = lib.get_mid(world, "opaque", "rainbow_star", 0.93)
                if mid then
                    for i, part in ipairs((inst.data or data).parts or {}) do
                        local comp = inst.comps and inst.comps[i]
                        for _, sec in ipairs(part.sections or {}) do
                            if comp and not (sec.texture or ""):find("eye") then pcall(function() comp:SetMaterial(sec.id, mid) end) end
                        end
                    end
                    into.star_mid, into.star_rb = mid, 0.0
                end
            end
        end
    end)
    return pk
end

-- His star won from him already in this file: the player back to better his time (no backpack, the star it held his;
-- only the question when talked to - "now when the player comes back and retrys the level, remove the backpack from
-- the ghost and just have it ask a simple "improve your time?"", 2026-10-27)
-- ------------------------------------------------------------ the eighteen ghosts
-- One ghost a main course, and one in each Bowser course: a floor's big brother, with a key to one of the three locks
-- on the chained door at the top of the endless stairs (game.lua G.EXTRA_HALLS castle2's gate). Each has his own words,
-- and what he says hangs on the brothers beaten before him; the last of a floor's ghosts beaten tells where its big
-- brother waits, and beating him gives his key ("every ghost runners dialog should be different and dependant on
-- ghosts you beat before", "the player completes all main courses on that floor ... The last race the player runs on
-- the floor and finishes the ghost reveals the whereabouts of the key ... in bowser 1 where you have to race another
-- ghost. after beating him you gain the key", 2026-11-05). Their words: tools/race_dialogs.py, 9100 on.
M.GHOSTS = { "bob", "wf", "jrb", "ccm", "bbh", "hmc", "lll", "ssl", "ddd", "sl", "wdw", "ttm", "thi", "ttc", "rr",
             "bitdw", "bitfs", "bits" }
local GIDX = {}
for i, c in ipairs(M.GHOSTS) do GIDX[c] = i end
-- (the castle's floors as its paintings hang: the first floor's five - Big Boo's Haunt by its courtyard - the
-- basement's four, the upper floors' six. The key: "key:race<n>" in the file, as Bowser's are "key:<n>")
M.FLOORS = {
    { courses = { "bob", "wf", "jrb", "ccm", "bbh" }, stage = "bitdw", key = 1 },
    { courses = { "lll", "ssl", "hmc", "ddd" }, stage = "bitfs", key = 2 },
    { courses = { "sl", "wdw", "ttm", "thi", "ttc", "rr" }, stage = "bits", key = 3 },
}
local FLOOR_OF, STAGE = {}, {}
for _, f in ipairs(M.FLOORS) do
    for _, c in ipairs(f.courses) do FLOOR_OF[c] = f end
    STAGE[f.stage] = f
end
M.STAGE = STAGE

-- (the course the race is in - its first area's name, whichever of its areas the flags are in: "ddd" for "ddd_2". Its
-- star is kept by that, as the star select and the pause screen look for it - "next add a 7th star to every main
-- course", 2026-11-05)
local function course_name(G)
    local ok, c = pcall(function() return G.level_of(G.name) end)
    if ok and c then return c end
    return (tostring(G.name):gsub("_%d+$", ""))
end
M.course_name = course_name

local function star_given(G)
    local sf = STAGE[course_name(G)]
    if sf then
        local mn = _G.MENU
        return (mn and mn.has_key and mn.has_key("race" .. sf.key)) == true
    end
    local x = G.extra_act or (G.EXTRA_STARS and G.EXTRA_STARS[course_name(G)])
    local key = course_name(G) .. ":" .. tostring(x and x.star or 7)
    local ok, won = pcall(function() return G.star_won and G.star_won(key) end)
    return ok and won == true
end

-- (beaten: a course's ghost by its star, in any of the course's areas; a big brother by his key)
local function ghost_beaten(c)
    local mn = _G.MENU
    if not (mn and mn.has_star) then return false end
    local f = STAGE[c]
    if f then return (mn.has_key and mn.has_key("race" .. f.key)) == true end
    local G = package.loaded["game"]
    if G and G.star_won then
        local ok, won = pcall(G.star_won, c .. ":7")
        return ok and won == true
    end
    return mn.has_star(c .. ":7")
end
M.ghost_beaten = ghost_beaten
-- the beaten in the order they were beaten: "flag:ghostseq_<n>_<course>" in the file (note_beaten); one beaten before
-- the order was kept, first
local function beaten_order()
    local mn = _G.MENU
    local got = (mn and mn.stars_got and mn.stars_got()) or {}
    local at = {}
    for k in pairs(got) do
        local n, c = tostring(k):match("^flag:ghostseq_(%d+)_(.+)$")
        n = tonumber(n)
        if n and GIDX[c] and n > (at[c] or 0) then at[c] = n end
    end
    local list = {}
    for _, c in ipairs(M.GHOSTS) do
        if ghost_beaten(c) then list[#list + 1] = { at[c] or 0, c } end
    end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    return list
end
M.beaten_order = beaten_order
local function note_beaten(c)
    local mn = _G.MENU
    if not (mn and mn.add_flag and mn.stars_got and GIDX[c]) then return end
    local top = 0
    for k in pairs(mn.stars_got()) do
        local n, o = tostring(k):match("^flag:ghostseq_(%d+)_(.+)$")
        if o == c then return end
        if n then top = math.max(top, tonumber(n)) end
    end
    mn.add_flag("ghostseq_" .. (top + 1) .. "_" .. c)
end
local function ghost_base(c) local i = GIDX[c]; return i and (9100 + (i - 1) * 10) or nil end
-- what he says as he is talked to, his star not yet won: met before, his "back again" and his dare; else his
-- greeting, then - none of them beaten yet - the ghost stars' tale (once; after it, that none has been beaten), or word
-- of the brother beaten last and how many are, then his dare. The flags noted: met, and the tale told.
local function intro_ids(G)
    local c = course_name(G)
    local b = ghost_base(c)
    local mn = _G.MENU
    if not (b and mn and mn.has_flag) then return 9001 end
    if mn.has_flag("ghostmet_" .. c) then return { b + 1, b + 2 } end
    local ids = { b }
    local list = beaten_order()
    local n = #list
    if n == 0 then
        ids[#ids + 1] = mn.has_flag("ghostlore") and 9301 or 9300
    else
        ids[#ids + 1] = 9310 + GIDX[list[n][2]]
        local tier = (n >= 15 and 9305) or (n >= 10 and 9304) or (n >= 5 and 9303) or (n >= 2 and 9302) or nil
        if tier then ids[#ids + 1] = tier end
    end
    ids[#ids + 1] = b + 2
    return ids
end
local function intro_said(G, ids)
    local mn = _G.MENU
    if not (mn and mn.add_flag and type(ids) == "table") then return end
    pcall(mn.add_flag, "ghostmet_" .. course_name(G))
    for _, id in ipairs(ids) do if id == 9300 then pcall(mn.add_flag, "ghostlore") end end
end
-- beaten (his star or key not yet won): his say; the last of his floor's ghosts, where its big brother waits; that the
-- race is there to run again; then the star pulling him back in as he hands it over - a big brother's key, and how many
-- of the three that makes
local function thank_ids(G)
    local c = course_name(G)
    local b = ghost_base(c)
    if not b then return 9003 end
    local ids = { b + 4 }
    local f = FLOOR_OF[c]
    if f then
        local all = true
        for _, o in ipairs(f.courses) do if o ~= c and not ghost_beaten(o) then all = false end end
        if all then ids[#ids + 1] = 9330 + f.key end
    end
    ids[#ids + 1] = 9350
    ids[#ids + 1] = b + 5
    local sf = STAGE[c]
    if sf then
        local mn = _G.MENU
        local k = 1
        for _, f2 in ipairs(M.FLOORS) do
            if f2 ~= sf and mn and mn.has_key and mn.has_key("race" .. f2.key) then k = k + 1 end
        end
        ids[#ids + 1] = 9340 + k
    end
    return ids
end
local function gloat_ids(G)
    local b = ghost_base(course_name(G))
    return b and { b + 3 } or 9002
end
-- A Bowser course's race: there once every ghost of its floor is beaten (and after, to better the time), never in the
-- Bowser run from the hall's painting (G.gauntlet)
local function stage_on(G)
    local sf = STAGE[G.name or ""]
    if not sf or G.gauntlet then return false end
    if ghost_beaten(sf.stage) then return true end
    for _, c in ipairs(sf.courses) do if not ghost_beaten(c) then return false end end
    return true
end
M.stage_on = stage_on

-- Where each of the athlete's meshes sits on him as he stands - by its name, his own space, at his own size - kept
-- every 2 s while it is so (no shrink, upright), wherever he is: the racer made from it when his own are not as they
-- stand. On his way into a level they are shrunk, turned over and sunk in his capsule a moment, and the racer copied
-- then came out a tenth of his size, or upside down in the floor ("he's upside down in the floor and still missing",
-- 2026-11-06); waited for, he came 3 s late.
M.REL_GOOD = M.REL_GOOD or {}
function M.rel_of(KML2, src, pawn_t)
    local r = KML2:MakeRelativeTransform(src:K2_GetComponentToWorld(), pawn_t)
    local t = { Rotation = { X = r.Rotation.X, Y = r.Rotation.Y, Z = r.Rotation.Z, W = r.Rotation.W },
                Translation = { X = r.Translation.X, Y = r.Translation.Y, Z = r.Translation.Z },
                Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }
    local good = math.abs(r.Scale3D.X - 1.0) < 0.15 and math.abs(t.Rotation.X) < 0.05 and math.abs(t.Rotation.Y) < 0.05
    return t, good
end
function M.remember_rel(pawn)
    local now = os.clock()
    if now < (M.rel_at or 0.0) then return end
    M.rel_at = now + 2.0
    local KML2 = StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    local pt = pawn:GetTransform()
    for _, path in ipairs({ "/Script/Engine.SkeletalMeshComponent", "/Script/ChaosClothAssetEngine.ChaosClothComponent" }) do
        local cls = StaticFindObject(path)
        if cls and cls:IsValid() then
            for _, w in ipairs(pawn:K2_GetComponentsByClass(cls)) do
                pcall(function()
                    local src = w:get()
                    local t, good = M.rel_of(KML2, src, pt)
                    if good then M.REL_GOOD[src:GetFName():ToString()] = t end
                end)
            end
        end
    end
end

local function ghost_make(G, pawn)
    local list = load_placed()[M.here()]
    local st = list and list.start
    -- (in an area of the course on from its start, the race carried there: made at the start's place, posed by his run
    -- at once - M.CHAIN)
    if not st and RACE.state == "run" and GH.rep_carry then
        list = load_placed()[M.course_key(G.name)]
        st = list and list.start
    end
    local world = lib.world()
    if not (st and world) then return false end
    local KML2 = StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    local gx, gy, gz, gyaw = ghost_spot(list)
    gz = (G.floor_z and G.floor_z(gx, gy, gz + 150.0)) or gz
    local a = lib.spawn_actor(world, { X = gx + OFFSET.X, Y = gy + OFFSET.Y, Z = gz + OFFSET.Z + (G.half or 90.0) }, gyaw)
    GH.home = { X = gx + OFFSET.X, Y = gy + OFFSET.Y, Z = gz + OFFSET.Z + (G.half or 90.0), yaw = gyaw }
    if not a then return false end
    pcall(function() a:SetActorEnableCollision(false) end)
    local pawn_t = pawn:GetTransform()
    local function comps(cls)
        local out = {}
        pcall(function()
            for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject(cls))) do out[#out + 1] = c:get() end
        end)
        return out
    end
    -- (metal, as the metal cap makes him - caps.lua: a copy of each of his materials with Mario 64's metal picture for
    -- its colour, silver, metal and shine; the cloth and the shoes the jeans' cotton with the picture, which takes it)
    local CAPS = package.loaded["caps"]
    local metal_tex = nil
    pcall(function()
        metal_tex = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary"):ImportFileAsTexture2D(world,
            lib.MOD_DIR .. ((CAPS and CAPS.METAL_TEX) or "textures/metal_body_sm64.png"))
    end)
    local UVA = (CAPS and CAPS.METAL_UV) or 2.0
    local SILVER = { R = 0.62, G = 0.64, B = 0.70, A = 1.0 }
    local function paint(c, src)
        for i = 0, c:GetNumMaterials() - 1 do
            local ok = pcall(function()
                local base = src:GetMaterial(i)
                local guard = 0
                while base and base:IsValid() and base:GetClass():GetFName():ToString() == "MaterialInstanceDynamic" and guard < 8 do
                    base = base.Parent; guard = guard + 1
                end
                if not (base and base:IsValid() and metal_tex) then error("none") end
                local m = c:CreateDynamicMaterialInstance(i, base, FName("None"))
                for _, n in ipairs({ "Color_MAIN", "PrintColor", "BaseColor", "BaseColorTexture", "Diffuse", "diffuse",
                                     "Albedo", "BaseColorMap", "Color", "diffuse_texture", "Diffuse_Texture" }) do
                    m:SetTextureParameterValue(FName(n), metal_tex)
                end
                for _, n in ipairs({ "Tint", "diffuse_color_1", "diffuse_color_2", "B_diffuse_color_1", "C_color", "ColorFabric" }) do
                    m:SetVectorParameterValue(FName(n), SILVER)
                end
                m:SetScalarParameterValue(FName("Metallic"), 1.0)
                m:SetScalarParameterValue(FName("Roughness"), 0.25)
                m:SetScalarParameterValue(FName("UV Amount"), UVA)
            end)
            if not ok then pcall(function() c:SetMaterial(i, src:GetMaterial(i)) end) end
        end
    end
    local function cotton(c)
        local cot = StaticFindObject("/SPP/MetaHumanAdHoc/Clothing/Torso/HoodieV1/Cotton_Natural_Rough_MAT.Cotton_Natural_Rough_MAT")
        if not (cot and cot:IsValid() and metal_tex) then return end
        for i = 0, c:GetNumMaterials() - 1 do
            pcall(function()
                local m = c:CreateDynamicMaterialInstance(i, cot, FName("None"))
                m:SetTextureParameterValue(FName("BaseColor"), metal_tex)
                m:SetVectorParameterValue(FName("Tint"), { R = 1.0, G = 1.02, B = 1.08, A = 1.0 })
                m:SetScalarParameterValue(FName("UV Amount"), UVA)
                m:SetScalarParameterValue(FName("NormalStrength"), 0.15)
            end)
        end
    end
    -- (a copy put where its own is on him, metal)
    -- (at his own size, whatever the athlete's is as he is copied: shrunk a moment on his way into a level, the racer
    -- came out a tenth of his - "ghost runner is invisable agaiin", 2026-11-06 - and waited for, he came 3 s late, "ghost
    -- runner was completely gone then reappeared 3 seconds after entering level")
    local function rel(src)
        local t, good = M.rel_of(KML2, src, pawn_t)
        local nm = src:GetFName():ToString()
        if good then M.REL_GOOD[nm] = t; return t end
        -- (not as he stands: as he stood, kept - M.remember_rel; none kept, not made yet - again 2 s on)
        local kept = M.REL_GOOD[nm]
        if kept then return kept end
        error("his body is not as he stands")
    end
    local function place(c, src)
        c:K2_AttachToComponent(a.RootComponent, FName("None"), 2, 2, 2, false)
        c:K2_SetRelativeTransform(rel(src), false, {}, true)
        paint(c, src)
        pcall(function() c:SetCastShadow(true) end)
    end
    -- his body, posed as it stands now and kept so
    local body_src = nil
    for _, o in ipairs(comps("/Script/Engine.SkeletalMeshComponent")) do
        if o:GetFName():ToString() == "CharacterMesh0" then body_src = o end
    end
    -- (a try that fails takes its actor away with it: tried again 2 s on, race_tick)
    if not body_src then pcall(lib.destroy, a, false); return false end
    -- his body: one that can be posed - each tick by his idle, played on a hidden copy of it and copied over, or by a
    -- recorded run in the race (raceghost.lua: ghost_pose)
    local body, idle_src = nil, nil
    pcall(function()
        body = a:AddComponentByClass(StaticFindObject("/Script/Engine.PoseableMeshComponent"), true, IDENT, false)
        body:SetSkinnedAssetAndUpdate(body_src:GetSkinnedAsset(), true)
        place(body, body_src)
        body:CopyPoseFromSkeletalComponent(body_src)
    end)
    if not (body and body:IsValid()) then pcall(lib.destroy, a, false); return false end
    local rel_t = rel(body_src)
    local idle = StaticFindObject(M.RACER_IDLE)
    if not (idle and idle:IsValid()) then idle = lib.try_load(M.RACER_IDLE) end
    if idle and idle:IsValid() then
        -- (his idle, looping, on a copy not drawn - its bones kept going all the same)
        pcall(function()
            idle_src = a:AddComponentByClass(StaticFindObject("/Script/Engine.SkeletalMeshComponent"), true, IDENT, false)
            idle_src:SetSkinnedAssetAndUpdate(body_src:GetSkinnedAsset(), true)
            idle_src:K2_AttachToComponent(a.RootComponent, FName("None"), 2, 2, 2, false)
            idle_src:K2_SetRelativeTransform(rel_t, false, {}, true)
            pcall(function() idle_src.VisibilityBasedAnimTickOption = 0 end)
            idle_src:SetVisibility(false, false)
            idle_src:PlayAnimation(idle, true)
        end)
        if not (idle_src and idle_src:IsValid()) then idle_src = nil end
    end
    -- (where his body sits in his actor: a recorded body's place in the world puts the actor where it must be)
    GH.body, GH.idle_src = body, idle_src
    GH.body_rel = { rel_t.Translation.X, rel_t.Translation.Y, rel_t.Translation.Z,
                    rel_t.Rotation.X, rel_t.Rotation.Y, rel_t.Rotation.Z, rel_t.Rotation.W }
    local n, names = 1, { "body" }
    -- his head and shoes, led by it
    for _, src in ipairs(comps("/Script/Engine.SkeletalMeshComponent")) do
        local nm = src:GetFName():ToString()
        if nm ~= "CharacterMesh0" then
            pcall(function()
                local c = a:AddComponentByClass(StaticFindObject("/Script/Engine.SkeletalMeshComponent"), true, IDENT, false)
                c:SetSkinnedAssetAndUpdate(src:GetSkinnedAsset(), true)
                place(c, src)
                c:SetLeaderPoseComponent(body, true, false)
                pcall(function() c.VisibilityBasedAnimTickOption = 0 end)
                if nm == "Feet" then cotton(c) end
                n, names[#names + 1] = n + 1, nm
                if nm == "Head" then GH.head = c end
            end)
        end
    end
    -- his T-shirt and trousers (Chaos cloth), led by it, not blown about
    local ccls = StaticFindObject("/Script/ChaosClothAssetEngine.ChaosClothComponent")
    if ccls then
        for _, src in ipairs(comps("/Script/ChaosClothAssetEngine.ChaosClothComponent")) do
            pcall(function()
                local asset = src:GetAsset()
                if not (asset and asset:IsValid()) then return end
                local c = a:AddComponentByClass(ccls, true, IDENT, false)
                c:SetAsset(asset)
                place(c, src)
                c:SetLeaderPoseComponent(body, true, false)
                pcall(function() c:SetEnableSimulation(false) end)
                cotton(c)
                n, names[#names + 1] = n + 1, src:GetFName():ToString()
            end)
        end
    end
    -- his hair, brows and beard on the head, if they take
    local gcls = M.RACER_HAIR and StaticFindObject("/Script/HairStrandsCore.GroomComponent")
    if gcls and GH.head then
        for _, src in ipairs(comps("/Script/HairStrandsCore.GroomComponent")) do
            pcall(function()
                local ga = src.GroomAsset
                if not (ga and ga:IsValid()) then return end
                local c = a:AddComponentByClass(gcls, true, IDENT, false)
                pcall(function() c:SetBindingAsset(src.BindingAsset) end)
                c:SetGroomAsset(ga)
                c:K2_AttachToComponent(GH.head, FName("None"), 2, 2, 2, false)
                n, names[#names + 1] = n + 1, src:GetFName():ToString()
            end)
        end
    end
    GH.actor, GH.addr = a, a:GetAddress()
    local silver = nil
    pcall(function() silver = lib.get_mid(world, "opaque", "metal_silver") end)
    -- (Mario's cap, nose and mustache on his head, as the menu's figure is dressed; metal, as the metal cap makes Mario's)
    local ML = package.loaded["mariolook"]
    local chrome = nil
    pcall(function() chrome = lib.get_mid(world, "opaque", M.CHROME_TEX) end)
    GH.chrome = chrome
    if M.RACER_CAP and ML and ML.dress then
        local okd = pcall(ML.dress, a, body, "race")
        if okd and ML.paint_dressed then pcall(ML.paint_dressed, GH.addr, chrome or silver) end
        if okd and ML.dressed_pieces then
            for _, pc in ipairs(ML.dressed_pieces(GH.addr)) do
                for id in pairs(M.RACER_HIDE) do pcall(function() pc.pmc:SetMeshSectionVisible(id, false) end) end
            end
        end
        names[#names + 1] = "Mario's cap"
    end
    -- (a backpack, put where his back is as he stands now and held to his spine, so it goes with his idle)
    if M.RACER_PACK and not star_given(G) then
        local okp, errp = pcall(function()
            local pk = make_pack(world, gx, gy, gz, gyaw, chrome or silver)
            if not pk then return end
            pcall(function() pk:K2_AttachToComponent(body, FName("spine_04"), 1, 1, 1, false) end)
            GH.pack = pk
            local nc = pack_cords(pk, chrome or silver)
            names[#names + 1] = (nc > 0) and string.format("backpack (%d drawstrings)", nc) or "backpack"
        end)
        if not okp then log("race: the backpack: %s", tostring(errp)) end
    end
    log("race: the racer at (%.0f, %.0f, %.0f): %s", gx, gy, gz, table.concat(names, ", "))
    return true
end

-- The racer's backpack - its star and drawstrings, in chrome - on the athlete himself: the GHOST RUNNER skin's (caps.lua
-- M.skin), put where his back is as he stands now and held to his spine. The pack and its star, or nil.
-- (in the middle of his back: measured on him standing, his idle's sway had it 2.6 cm to his left - "the backpack is a
-- little to the left on the charater fix that", 2026-11-04)
M.PACK_REL = { loc = { X = 8.05, Y = -5.93, Z = 0.0 }, rot = { Pitch = 0.0, Yaw = 90.0, Roll = -90.0 } }
function M.pack_on(world, pawn)
    local body = pawn.Mesh
    local l, yaw, half = pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation().Yaw, 90.0
    pcall(function() half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight() end)
    local mat = nil
    pcall(function() mat = lib.get_mid(world, "opaque", M.CHROME_TEX) end)
    if not mat then pcall(function() mat = lib.get_mid(world, "opaque", "metal_silver") end) end
    local into = {}
    local pk = make_pack(world, l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - half, yaw, mat, into)
    if not pk then return nil end
    -- (on his spine where it sits as he stands - M.PACK_REL, measured so - whatever his pose as it goes on: held where
    -- it was when it went on, picked in the CHARACTER tab's pose it hung off behind his shoulders - "ghost mario bag
    -- not positioned correctly", 2026-11-04)
    local R = M.PACK_REL
    pcall(function()
        pk:K2_AttachToComponent(body, FName("spine_04"), 2, 2, 2, false)
        pk.RootComponent:K2_SetRelativeLocationAndRotation(R.loc, R.rot, false, {}, true)
    end)
    pcall(pack_cords, pk, mat)
    return pk, into.star
end

-- the athlete held (dialog.lua's way: his walking, his parkour moves and the engine's move input)
local LOCK = "SM64Race"
-- (once each way: the engine counts SetIgnoreMoveInput, and held twice - at the answer, and again lined up behind the
-- black - one let-go at GO left his move input off: "player stopping in place when sprinting?", 2026-10-27)
local function race_lock(on)
    if (on and RACE.locked) or (not on and not RACE.locked) then return end
    local pc, pawn = lib.controller(), lib.pawn()
    if not (pc and pawn) then return end
    pcall(function() pc:SetIgnoreMoveInput(on) end)
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
    -- (and his animations' own motion back as it was - hold_on_spot took it off)
    if not on and RACE.rmm ~= nil then
        pcall(function() pawn.Mesh:GetAnimInstance().RootMotionMode = RACE.rmm end)
        RACE.rmm = nil
    end
    RACE.locked = on or nil
end

-- the countdown's words in the HUD's own letters, big in the middle of the screen
local CD = nil
local function count_hide()
    if CD then pcall(function() CD:RemoveFromParent() end) end
    CD = nil
end
local function count_show(text)
    count_hide()
    local world, pc = lib.world(), lib.controller()
    if not (world and pc) then return end
    pcall(function()
        local function cls(p) return StaticFindObject(p) end
        _G.SM64_RACE_CD = (_G.SM64_RACE_CD or 0) + 1
        local n = tostring(_G.SM64_RACE_CD)
        local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("SM64RaceCount" .. n))
        local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("SM64RaceCountTree" .. n))
        w.WidgetTree = tree
        local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SM64RaceCountCanvas" .. n))
        tree.RootWidget = canvas
        local size = { X = 1920.0, Y = 1080.0 }
        pcall(function()
            local WLL = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
            local vs, sc = WLL:GetViewportSize(world), WLL:GetViewportScale(world)
            if vs and sc and sc > 0 then size = { X = vs.X / sc, Y = vs.Y / sc } end
        end)
        local px = size.Y / 240.0
        local glyph, adv = 48.0, 38.0                       -- (Mario 64's pixels: the HUD's 16, three times over)
        local total = (#text - 1) * adv + glyph
        local x0, y0 = (size.X - total * px) / 2.0, (size.Y - glyph * px) / 2.0 - 30.0 * px
        for k = 1, #text do
            local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("SM64RaceCountImg" .. n .. "_" .. k))
            local tex = lib.texture(world, "hud_" .. text:sub(k, k))
            if tex then img:SetBrushFromTexture(tex, false) end
            local slot = canvas:AddChildToCanvas(img)
            slot:SetAnchors({ Minimum = { X = 0.0, Y = 0.0 }, Maximum = { X = 0.0, Y = 0.0 } })
            slot:SetPosition({ X = x0 + (k - 1) * adv * px, Y = y0 })
            slot:SetSize({ X = glyph * px, Y = glyph * px })
        end
        w:AddToViewport(70)
        CD = w
    end)
end

local function race_sound(name, v)
    local SFX = package.loaded["sfx"]
    if SFX and SFX.play then pcall(SFX.play, name, v or 1.0, true) end      -- (kept to its end: sfx.lua)
end

-- Home: the athlete on the start line, or over it since the last tick - within its width (and its flags), near its
-- height. `ln`: list.line - its middle, the way run, its width. (x, y his middle across, z his feet, scene cm)
local function over_line(ln, x, y, z)
    local cx, cy, cz, yaw, w = ln[1], ln[2], ln[3], ln[4] or 0.0, ln[5] or 700.0
    local fx, fy = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))         -- (the way run)
    local ax, ay = -fy, fx                                                  -- (along the line)
    local dx, dy = x - cx, y - cy
    local along, off = dx * ax + dy * ay, dx * fx + dy * fy
    local prev = RACE.line_off
    RACE.line_off = off
    if math.abs(along) > w / 2.0 + 60.0 or math.abs(z - cz) > 300.0 then return false end
    if math.abs(off) <= M.LINE_DEPTH / 2.0 + 20.0 then return true end
    return prev ~= nil and (prev > 0.0) ~= (off > 0.0)
end

-- the checkpoint count under the meter (health.lua): the flags taken, of all of them
local function hud_flags()
    local HP = _G.HEALTH
    if not HP then return end
    local got, of = math.max(0, math.min(#B, (M.next or 1) - 1)), #B
    -- (a course through more than one area: the flags of those before this one taken, and all of them - M.CHAIN)
    local Gm = package.loaded["game"]
    local nm = Gm and Gm.name and M.here()
    local ch = nm and M.chain_of(nm)
    if ch then
        local lastl = load_placed()[ch[#ch]]
        local fin = (lastl and lastl.finish) and 1 or 0
        got, of = M.flag_base(nm) + got, M.flags_total(nm) + fin
        if fin == 1 and RACE.final and (RACE.state == "done" or RACE.state == "won") then got = of end
        HP.race_flags, HP.race_of = got, of
        return
    end
    -- (a finish line of its own counted as one more, crossed once the race is done - Bowser 1's, no flags: 0/1, then 1/1:
    -- "make the race counter say 0/1", 2026-11-06)
    if M.LIST_FINISH and M.LIST_FINISH() then
        of = of + 1
        if RACE.final and (RACE.state == "done" or RACE.state == "won") then got = of end
    end
    HP.race_flags, HP.race_of = got, of
end

-- The race's music: Mario 64's own for a race - Koopa the Quick's, the slide's tune - from the moment the screen goes
-- black to line them up, through the countdown and the race, till it is over ("also we have to add race music when
-- actually racing", then "do it the second the black screen comes up to transition the players in the ready
-- position", 2026-10-27); then the level's own again. A cap's tune
-- (the metal cap's, the wing and vanish caps') is let play over it, and the race's comes back after.
-- (its own remix where there is one - music_remix/level_slide@race: "Cosmic Clones | The Super Mario Galaxy REMIX as
-- race music against ghost", 2026-11-01 - else the slide tune's, music.lua file_for)
M.RACE_MUSIC = "level_slide@race"
local CAP_TUNES = { event_metal_cap = true, event_powerup = true }
-- (the states it plays through: from "Go!" till he is over the line himself, or - beaten to it by the ghost - till he
-- has gone to talk to him: "only end the music if the player has crossed the finish line or has talked to the ghost",
-- 2026-10-27)
local MUSIC_ON = { fade = true, black = true, back = true, count = true, run = true, lost = true }
-- (`finish`: over the line, or the ghost talked to - the race's fanfare first, Mario 64's for a race's end, the level's
-- tune once it has played: "also play the finish music before cutting out the music", 2026-10-27. Not on leaving the
-- level: there the place's own tune comes as it is)
M.FANFARE = "race_fanfare"
local function wav_secs(name)
    local secs = 3.0
    pcall(function()
        local f = io.open(lib.MOD_DIR .. "sfx\\" .. name .. ".wav", "rb")
        if not f then return end
        local h = f:read(44)
        local size = f:seek("end")
        f:close()
        local ch, rate = h:byte(23) + h:byte(24) * 256, string.unpack("<I4", h, 25)
        local bits = h:byte(35) + h:byte(36) * 256
        if ch > 0 and rate > 0 and bits > 0 then secs = (size - 44) / (rate * ch * bits / 8) end
    end)
    return secs
end
local function race_music(on, finish)
    local MU = package.loaded["music"]
    if not (MU and MU.play) then return end
    if on then
        local cur = MU.current
        if cur ~= M.RACE_MUSIC and not CAP_TUNES[cur or ""] then pcall(MU.play, M.RACE_MUSIC) end
        RACE.music_on = true
    elseif RACE.music_on then
        RACE.music_on = nil
        if MU.current == M.RACE_MUSIC then
            if finish then
                pcall(MU.play, nil)
                local SFX = package.loaded["sfx"]
                if SFX and SFX.play then pcall(SFX.play, M.FANFARE, 1.0, true) end
                M.music_back_at = os.clock() + wav_secs(M.FANFARE) + 0.3
            else
                local G = package.loaded["game"]
                pcall(MU.play, G and G.data and G.data.music or nil)
            end
        end
    end
end
-- (the fanfare over: the level's own tune again)
local function music_back_tick()
    local at = M.music_back_at
    if not at or os.clock() < at then return end
    M.music_back_at = nil
    local MU = package.loaded["music"]
    local G = package.loaded["game"]
    if MU and MU.play and MU.current == nil and G and G.data then pcall(MU.play, G.data.music) end
end

-- Kept on his spot from his lining up to GO: the push he talked to the racer with was still running as he was put
-- there - the frame after, STORROR gave him its lunge's speed again, 10.7 m/s, and he slid 58 cm on past the racer
-- behind the black: the ghost on its spot looked "further back" ("the ghost is further back then the player is on
-- start", 2026-10-30; the put-back at GO came too late to be seen). His controls are held meanwhile: nothing of his
-- own moves him.
local function hold_on_spot(G)
    local sp = RACE.spot
    local pawn = lib.pawn()
    if not (sp and pawn) then return end
    pcall(function()
        local cm = pawn.CharacterMovement
        local l = pawn:K2_GetActorLocation()
        local dx, dy = l.X - OFFSET.X - sp.x, l.Y - OFFSET.Y - sp.y
        local d2 = dx * dx + dy * dy
        local off = d2 > 5.0 * 5.0
        -- (and not left falling where he stands - he was, most of a second, then a landing roll, its own steps put back
        -- 5 cm up and so falling again: "player was glitching out on starting line", 2026-10-30. His height is left
        -- as it is; walking, the ground takes him.)
        local falling = cm.MovementMode == 3 and (l.Z - OFFSET.Z) - sp.z < 10.0
        -- (and kept facing the way the race is run: set only as he was put there, STORROR turned him back the way he
        -- faced before - -121 to -157 in a quarter second - "charater not facing forward on race start", 2026-11-08)
        local ry = pawn:K2_GetActorRotation().Yaw
        if math.abs(((ry - sp.yaw + 540.0) % 360.0) - 180.0) > 1.0 then
            pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = sp.yaw, Roll = 0.0 }, false)
        end
        if not (off or falling) then return end
        -- (put back no lower than his spot's own height over its ground: kept at his height where he was, on Tall, Tall
        -- Mountain's slope that was in the ground at his spot - a landing roll began, its own motion slid him off it
        -- again, and he was put back into the ground every 4th frame, shaking, held in the roll all the countdown:
        -- "player glitching out on the start line", "its like the players spawning in the floor", 2026-11-07)
        -- (moved, not teleported: a teleport is a landing to STORROR)
        if off then
            pawn:K2_SetActorLocation({ X = sp.x + OFFSET.X, Y = sp.y + OFFSET.Y, Z = math.max(l.Z, sp.z + OFFSET.Z) }, false, {}, true)
            pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = sp.yaw, Roll = 0.0 }, false)
        end
        cm:StopMovementImmediately()
        cm:SetMovementMode(1, 0)
        if d2 > 20.0 * 20.0 and G and G.reset_cloth then pcall(G.reset_cloth, pawn) end
        if off and not RACE.held_said then
            RACE.held_said = true
            log("race: kept on his spot in the countdown (%.0f cm off it)", math.sqrt(d2))
        end
    end)
end

-- The two lined up: the athlete on the line beside the racer, both facing the way it is run, held for the countdown
local function line_up(G)
    local pawn = lib.pawn()
    local list = load_placed()[M.here()]
    local st = list and list.start
    if not (pawn and st) then return end
    local yaw = st[4] or 0.0
    -- (the level's creatures and platforms put back as it first had them, chance from one seed: the same world at every
    -- start, the ghost's run in step with it - game.lua G.reset_objects. Behind the black, so none is seen go.)
    if G.reset_objects then
        local okr, errr = pcall(G.reset_objects, M.RACE_SEED)
        if not okr then log("race: the level's things not put back (%s)", tostring(errr)) end
    end
    local x, y = behind(st, M.RACE_TALK.side)
    local f = G.floor_z and G.floor_z(x, y, st[3] + 150.0) or st[3]
    RACE.spot = { x = x, y = y, z = (f or st[3]) + (G.half or 90.0) + 5.0, yaw = yaw }
    RACE.held_said = nil
    -- (moved there, not teleported: a teleport is a landing to STORROR - on Tall, Tall Mountain's slope a landing roll
    -- began on the line, and held off it the countdown kept him crouched in it, "its like the players spawning in the
    -- floor"; its animation's own motion turned off for it, he was "not connected to the ground", 2026-11-07)
    pcall(function()
        pawn:K2_SetActorLocation({ X = x + OFFSET.X, Y = y + OFFSET.Y, Z = (f or st[3]) + (G.half or 90.0) + 5.0 + OFFSET.Z }, false, {}, true)
        pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false)
        pawn.CharacterMovement.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
        pawn:GetController():SetControlRotation({ Pitch = -10.0, Yaw = yaw, Roll = 0.0 })
    end)
    -- (his clothes and hair started again from their shape where he now stands - teleported, his hair's strands flew
    -- off his head: "player still losing hair also moving around and showing bald underneith", 2026-10-27)
    if G.reset_cloth then pcall(G.reset_cloth, pawn) end
    race_lock(true)
    M.reset()
    -- (the racer onto the line beside him, facing the way)
    if GH.actor then
        local lx, ly, lz, lyaw = line_spot(st)
        lz = (G.floor_z and G.floor_z(lx, ly, lz + 150.0)) or lz
        pcall(function() GH.actor:K2_TeleportTo({ X = lx + OFFSET.X, Y = ly + OFFSET.Y, Z = lz + OFFSET.Z + (G.half or 90.0) }, { Pitch = 0.0, Yaw = lyaw, Roll = 0.0 }) end)
    end
    -- (the race's own timer and checkpoint count under the power meter - health.lua - not the speedrun timer)
    if _G.HEALTH then _G.HEALTH.race_clock = 0.0 end
    hud_flags()
    pcall(function()
        local l = pawn:K2_GetActorLocation()
        local fy = math.rad(st[4] or 0.0)
        log("race: lined up %.0f cm behind the line's middle", -((l.X - OFFSET.X - st[1]) * math.cos(fy) + (l.Y - OFFSET.Y - st[2]) * math.sin(fy)))
    end)
    log("race: lined up on the line")
end

-- "Go!": the screen fades to black, the two are lined up behind it, and it comes back for the countdown - they were put
-- there in plain sight before ("make the screen fade to black then come back when the players are line up at the
-- start", 2026-10-27). In 30ths of a second out and back (Mario 64's black fade, as EXIT COURSE: transition.lua), and
-- seconds held black between, the camera settled behind him meanwhile.
M.FADE = { out = 16, hold = 0.4, back = 16 }
local function race_begin(G)
    local pawn = lib.pawn()
    local list = load_placed()[M.here()]
    if not (pawn and list and list.start) then return end
    race_lock(true)                     -- (held from the answer on: no running off as it goes dark)
    RACE.token = (RACE.token or 0) + 1
    local token = RACE.token
    RACE.state, RACE.t, RACE.shown, RACE.line_off = "fade", 0.0, nil, nil
    race_music(true)
    local function lined()
        if RACE.token ~= token or RACE.state ~= "fade" then return end
        line_up(G)
        RACE.state, RACE.t = "black", 0.0
    end
    local TR = package.loaded["transition"]
    RACE.dark = TR and TR.close and pcall(TR.close, "black", M.FADE.out, lined) or nil
    if not RACE.dark then lined() end
end

-- the screen given back, if the race is left while it is dark (not over a warp's own: that one is the warp's)
local function race_light()
    if not RACE.dark then return end
    RACE.dark = nil
    local G = package.loaded["game"]
    if G and (G.warping or G.pending) then return end
    local TR = package.loaded["transition"]
    if TR and TR.open then pcall(TR.open, "black", 8) end
end

local function race_stop()
    count_hide()
    race_music(false)
    race_light()
    if RACE.locked then race_lock(false) end
    RACE.state = nil
    refresh()                           -- (the home beam out)
    if GR then GR.rec_drop() end        -- (a run not finished is not kept)
    GH.rep = nil
    -- (the racer back where he stands)
    local h = GH.home
    if GH.actor and h then pcall(function() GH.actor:K2_TeleportTo({ X = h.X, Y = h.Y, Z = h.Z }, { Pitch = 0.0, Yaw = h.yaw, Roll = 0.0 }) end) end
    if _G.HEALTH then _G.HEALTH.race_clock, _G.HEALTH.race_flags, _G.HEALTH.race_of = nil, nil, nil end
end

-- a new push (his push or attack, begun since the last tick)
-- The ghost home first: the race lost there and then. The camera on him at the line as he has his say (DIALOG 9002:
-- "if the ghost finishes before the player it. should say something along the lines of "I knew I could do this job
-- unfortunate for you though next time keep up!"", 2026-10-27), and the race over once it is read. His run not kept:
-- it was not finished.
-- (he waits where he finished, under the home beam, till he is talked to: "make the player talk to him first before
-- it ends", 2026-10-27 - race_tick's "lost")
local function ghost_won(G)
    -- (home in another area of the course from him: lost there and then - no racer here to talk to)
    if GH.away then
        RACE.state, RACE.t = "done", 0.0
        if GR then GR.rec_drop() end
        refresh()
        pcall(count_show, "LOST")
        log("race: the ghost is home first, in another area - lost")
        return
    end
    RACE.state, RACE.t = "lost", 0.0
    if GR then GR.rec_drop() end
    refresh()
    local gt = GH.rep and GH.rep.g and GH.rep.g.final or 0.0
    if _G.HEALTH then _G.HEALTH.race_clock = gt end         -- (the clock stopped at his time)
    log("race: the ghost is home first, in %.2f s - lost; he waits to be talked to", gt)
end

-- The racer talked to where he stands now - near him, his feet about his, facing him, a new push: where he is (scene
-- cm, his feet), or nil
local function talked_to(G, pawn, x, y, z, push)
    if not (push and GH.actor and not GH.gone) then return nil end
    local DLG = package.loaded["dialog"]
    if DLG and DLG.active then return nil end
    local gx, gy, gz = nil, nil, nil
    pcall(function()
        local l = GH.actor:K2_GetActorLocation()
        gx, gy, gz = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - (G.half or 90.0)
    end)
    if not gx then return nil end
    local dx, dy = gx - x, gy - y
    if math.sqrt(dx * dx + dy * dy) >= M.RACE_TALK.reach or math.abs(gz - z) >= 200.0 then return nil end
    local yaw = 0.0
    pcall(function() yaw = pawn:K2_GetActorRotation().Yaw end)
    local off = (math.deg(math.atan(dy, dx)) - yaw + 540.0) % 360.0 - 180.0
    if math.abs(off) >= M.RACE_TALK.facing then return nil end
    return gx, gy, gz
end

-- He goes home, beaten: his star out of him and over to its place above the start line - as Koopa the Quick's comes
-- out at his flag - see-through if it is won already; and he goes in a puff, not seen again till the level is come
-- back to. The star: the course's extra one (game.lua G.EXTRA_STARS, "bob:7").
M.STAR_UP = 200.0           -- cm over the floor where it comes to
M.STAR_AWAY = 350.0         -- cm out from the ghost, the far side from him
local function ghost_goes_home(G, gx, gy, gz)
    local x = G.extra_act
    local key = course_name(G) .. ":" .. tostring(x and x.star or 7)
    local list = load_placed()[M.here()]
    local ln = list and list.line
    local sx, sy, sz = gx, gy, gz
    if ln then
        sx, sy = ln[1], ln[2]
        sz = (G.floor_z and G.floor_z(sx, sy, ln[3] + 150.0)) or ln[3]
    end
    -- (out a little way from him - past the ghost, the far side from him, as he faces him to talk: over the line it was
    -- in his hands at once, "spawn the star a little bit away from the player when beating the ghost", 2026-10-27. On
    -- ground about the ghost's height; that way a drop, the ways round him; none, the line)
    local px, py = nil, nil
    pcall(function()
        local l = lib.pawn():K2_GetActorLocation()
        px, py = l.X - OFFSET.X, l.Y - OFFSET.Y
    end)
    if px and G.floor_z then
        local dx, dy = gx - px, gy - py
        local d = math.sqrt(dx * dx + dy * dy)
        local base = d > 1.0 and math.atan(dy, dx) or 0.0
        for _, turn in ipairs({ 0, 40, -40, 80, -80, 120, -120, 180 }) do
            local a = base + math.rad(turn)
            local cx, cy = gx + math.cos(a) * M.STAR_AWAY, gy + math.sin(a) * M.STAR_AWAY
            local fz = G.floor_z(cx, cy, gz + 150.0)
            local far = (cx - px) ^ 2 + (cy - py) ^ 2 > (M.STAR_AWAY * 0.8) ^ 2
            if fz and math.abs(fz - gz) < 150.0 and far then sx, sy, sz = cx, cy, fz; break end
        end
    end
    -- (or where it is placed to come out - list.reward, M.set_reward: Bowser 1's key, "spawn the key here instead",
    -- 2026-11-06)
    local rw = list and list.reward
    if rw then sx, sy, sz = rw[1], rw[2], rw[3] end
    local world = lib.world()
    -- (a big brother's: his key - Bowser's own model, stood on end and turning as Bowser's do; taken, the file has
    -- "key:race<n>", and he stays in the course)
    local sf = STAGE[course_name(G)]
    if sf then key = "key:race" .. sf.key end
    local ok, s = pcall(function()
        if sf then
            -- (taken, and out of the course after its dance, as a star takes him - "after grabbing the key take the player
            -- out of the level", 2026-11-06: by the course's own way out with a star, else by its way out on leaving -
            -- Bowser 1 has only that one, to the castle)
            local st = G.add_star(world, { pos = { sx, sy, sz + M.STAR_UP }, key = key, from = { gx, gy, gz + 100.0 },
                                           model = "geo_bowser_key_geo", keyn = "race" .. sf.key })
            if st then
                st.exit_to = (G.warp and (G.warp[0xF0] or G.warp[0xF1])) or nil
                st.roll, st.spin = 90.0, 168.75
                pcall(function() st.inst.actor:SetActorScale3D({ X = 0.5, Y = 0.5, Z = 0.5 }) end)
                -- (rainbow, as the one in his bag and the course ghosts' stars - "make the key rainbow", 2026-11-06)
                local mid = lib.get_mid(world, "opaque", "rainbow_star", 0.94)
                if mid and st.inst and st.inst.data then
                    for i, part in ipairs(st.inst.data.parts or {}) do
                        local comp = st.inst.comps and st.inst.comps[i]
                        for _, sec in ipairs(part.sections or {}) do
                            if comp then pcall(function() comp:SetMaterial(sec.id, mid) end) end
                        end
                    end
                    local wa = nil
                    pcall(function() wa = world:GetAddress() end)
                    RB = { st = st, mid = mid, t = 0.0, world = wa }
                end
            end
            return st
        end
        local won = G.star_won and G.star_won(key)
        local st = G.add_star(world, { pos = { sx, sy, sz + M.STAR_UP }, key = key, from = { gx, gy, gz + 100.0 },
                                       model = won and "transparent_star" or nil })
        -- (his ghost star, rainbow as the one in his bag - textures/rainbow_star.png on its faces, its eyes as they
        -- are: "turn the star rainbow", 2026-11-05. One won before stays see-through.)
        if st and not won then
            local mid = lib.get_mid(world, "opaque", "rainbow_star", 0.94)
            if mid and st.inst and st.inst.data then
                for i, part in ipairs(st.inst.data.parts or {}) do
                    local comp = st.inst.comps and st.inst.comps[i]
                    for _, sec in ipairs(part.sections or {}) do
                        if comp and not (sec.texture or ""):find("eye") then pcall(function() comp:SetMaterial(sec.id, mid) end) end
                    end
                end
                local wa = nil
                pcall(function() wa = world:GetAddress() end)
                RB = { st = st, mid = mid, t = 0.0, world = wa }
            end
        end
        return st
    end)
    -- (the run that won it, held at the finish, kept once it is taken - M.reward_tick; none come out, kept now)
    if RACE.hold_run then
        local h = RACE.hold_run
        RACE.hold_run = nil
        if ok and s then
            local wa = nil
            pcall(function() wa = world:GetAddress() end)
            M.reward_wait = { st = s, scene = h.scene, run = h.run, world = wa }
        else
            pcall(keep_run, h.scene, h.run)
        end
    end
    if ok and s then
        local SFX = package.loaded["sfx"]
        if SFX and SFX.play then pcall(SFX.play, "star_appears", 1.0, true) end
        if G.star_cutscene then pcall(G.star_cutscene, s) end
        log("race: his %s %s is out", sf and "key" or "star", key)
    else
        log("race: his star did not come out (%s)", tostring(s))
    end
    -- (and the order he was beaten in noted: what the next ghost says)
    pcall(note_beaten, course_name(G))
    -- (the puff he goes in: spawn_mist_particles, as a beaten creature's)
    local EF = package.loaded["envfx"]
    if EF and EF.poof then pcall(EF.poof, gx, gy, gz + 60.0, 1.4) end
    ghost_drop()
    GH.gone = true
end

-- beaten, and talked to once home: his say, then the star and off home (race over once it is read)
-- a time as Mario 64 writes a race's: 1'48"31
local function race_time_text(t)
    local cs = math.floor((t or 0.0) * 100.0 + 0.5)
    return string.format("%d'%02d\"%02d", cs // 6000, (cs // 100) % 60, cs % 100)
end
local function ghost_thank(G, gx, gy, gz)
    if star_given(G) then
        -- (back again for a better time - his star won before: the time beaten, then the new one; no star again, and
        -- he stays to be raced once more - "if the player succeeds label the old then the new time", 2026-10-27)
        RACE.state, RACE.t = "thank", 0.0
        log("race: the beaten ghost talked to - the old time and the new")
        pcall(G.dialog_cut, gx, gy, gz, 80.0)
        local fill = { race_time_text(RACE.old_time), race_time_text(RACE.final) }
        local ok = pcall(G.say, 9006, function()
            race_stop()
            RACE.shut_at, RACE.wait_push = os.clock(), true
        end, { fill = fill })
        if not ok then race_stop() end
        return
    end
    RACE.state, RACE.t = "thank", 0.0
    log("race: the beaten ghost talked to - he gives up the star")
    pcall(G.dialog_cut, gx, gy, gz, 80.0)
    local ok = pcall(G.say, thank_ids(G), function()
        pcall(ghost_goes_home, G, gx, gy, gz)
        race_stop()
        RACE.shut_at, RACE.wait_push = os.clock(), true
    end)
    if not ok then pcall(ghost_goes_home, G, gx, gy, gz); race_stop() end
end

-- talked to, there: the camera on him as he has his say, and the race over once it is read
local function ghost_gloat(G, gx, gy, gz)
    RACE.state, RACE.t = "gloat", 0.0
    log("race: the ghost talked to - he has his say")
    pcall(G.dialog_cut, gx, gy, gz, 80.0)
    -- (back again for a better time - his star won before: only "Try again!", "if the player fails just say. try again",
    -- 2026-10-27)
    local ok = pcall(G.say, star_given(G) and 9005 or gloat_ids(G), function()
        race_stop()
        RACE.shut_at, RACE.wait_push = os.clock(), true     -- (the push that shut it not taken as a talk to him)
    end)
    if not ok then race_stop() end
end

local function pushed_now(pawn)
    local n = nil
    pcall(function()
        local mt = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
        if mt and mt:IsValid() then n = mt:GetFName():ToString() end
    end)
    local push = n and (n:find("Attack") or n:lower():find("push")) and n or nil
    local new = push ~= nil and RACE.last_push == nil
    RACE.last_push = push
    return new
end

-- ------------------------------------------------------------ the developer mode
-- For laying a race out and recording its ghost ("record the run up to checkpoint if I don't hit the flag dont save it if
-- I do do save it, teleport me to the last collected flag if I die", 2026-11-05): on while the mod's folder has
-- race_dev.txt (the maker's own - a release leaves it out), or M.DEV is set. In a race, at GO and at each flag taken,
-- the race is kept as it is there - its clock, its recording so far, the ghost's place in his run, where he stands. A
-- death after, and he is put back where he took the last of them, no life lost, the race taken back to that moment: the
-- stretch since and its recording dropped, the run going on from there (game.lua death_warp calls M.dev_respawn).
M.DEV = nil
function M.dev_on()
    if M.DEV ~= nil then return M.DEV end
    if M.dev_file == nil then
        local f = io.open(lib.MOD_DIR .. "race_dev.txt", "rb")
        M.dev_file = f ~= nil
        if f then f:close() end
    end
    return M.dev_file
end
M.DEVK = nil
function M.dev_keep(pawn, k)
    if not M.dev_on() then return end
    local s = { k = k, at = os.clock(), t0 = RACE.t0, g0 = RACE.g0, next = M.next, times = {},
                rec_n = GR and GR.rec_mark and GR.rec_mark() or nil }
    for i, v in pairs(M.times) do s.times[i] = v end
    pcall(function()
        local l = pawn:K2_GetActorLocation()
        s.x, s.y, s.z, s.yaw = l.X, l.Y, l.Z, pawn:K2_GetActorRotation().Yaw
    end)
    if GH.rep then s.rep_t0, s.rep_done = GH.rep.t0, GH.rep.done_t end
    M.DEVK = s
    log("race (dev): kept at %s, %.2f s in", k == 0 and "GO" or ("flag " .. k), s.at - (s.t0 or s.at))
end
function M.dev_respawn(pawn)
    local s = M.DEVK
    if not (M.dev_on() and s and pawn and RACE.state == "run" and s.x) then return false end
    local now = os.clock()
    local shift = now - s.at
    RACE.t0, RACE.g0 = s.t0 and s.t0 + shift, s.g0 and s.g0 + shift
    M.next, M.times = s.next, {}
    for i, v in pairs(s.times) do M.times[i] = v + shift end
    if GR and GR.rec_cut and s.rec_n then GR.rec_cut(s.rec_n) end
    if GH.rep and s.rep_t0 then GH.rep.t0, GH.rep.done_t = s.rep_t0 + shift, s.rep_done and s.rep_done + shift or nil end
    pcall(function()
        local cm = pawn.CharacterMovement
        cm:StopMovementImmediately()
        pawn:K2_TeleportTo({ X = s.x, Y = s.y, Z = s.z }, { Pitch = 0.0, Yaw = s.yaw or 0.0, Roll = 0.0 })
        pawn:GetController():SetControlRotation({ Pitch = -10.0, Yaw = s.yaw or 0.0, Roll = 0.0 })
    end)
    s.at, s.t0, s.g0 = now, RACE.t0, RACE.g0
    if GH.rep and s.rep_t0 then s.rep_t0, s.rep_done = GH.rep.t0, GH.rep.done_t end
    pcall(refresh)
    log("race (dev): a death - back at %s, the race taken back to %.2f s", s.k == 0 and "GO" or ("flag " .. s.k), now - (RACE.t0 or now))
    return true
end

-- each tick, in the race's act: the ghost racer made once he has stood a moment, flickering; talked to; the countdown;
-- the clock
local function race_tick(dt, G, pawn, x, y, z)
    local key = built_for
    if GH.key ~= key then
        -- (the race carried on into the course's next area - M.tick, M.CHAIN: his run kept, to go on with on him as he
        -- is made here)
        -- (carried on with no ghost to race - the course's first run - just as well: "race didnt continue into
        -- pyramid", 2026-11-07, it stopped there for want of one)
        local carried = RACE.carried and RACE.state == "run"
        local rp = carried and GH.rep or nil
        ghost_drop()                    -- (a new scene: what was hung on him there taken off with him)
        GH.key, GH.still, GH.waited, GH.retry_at = key, 0.0, 0.0, nil
        if carried then GH.rep_carry = rp else race_stop() end
        RACE.carried = nil
    end
    local list = load_placed()[M.here()]
    -- (the start where the course begins: in an area on from it, the first area's - M.CHAIN)
    local headl = load_placed()[M.course_key(G.name)]
    local st = headl and headl.start
    if not st then return end
    list = list or {}
    -- (an area on from the start with no race carried into it: no racer here)
    if not list.start and RACE.state == nil and GH.actor then ghost_drop() end
    -- (the ghost racer, made as soon as the level is up: he plays his own idle, so there is no pose of the athlete's to
    -- wait for - made once the athlete had stood still half a second, or 6 s on, he came in some 10 s after the level
    -- did: "the ghost player doesnt spawn in for 10 seconds", 2026-10-27. Not while the athlete is down: his meshes are
    -- copied where they sit on him. A failed try, again 2 s on.)
    if not GH.actor and not GH.gone and os.clock() >= (GH.retry_at or 0.0) then
        local RAG = package.loaded["ragdoll"]
        local down = G.dying or G.getup_at or (RAG and RAG.active)
        if not down and not ghost_make(G, pawn) then GH.actor, GH.retry_at = nil, os.clock() + 2.0 end
    end
    -- (made in the next area of the course, the race carried there: his run goes on, on him - no easing in, his body new)
    if GH.actor and GH.rep_carry then
        local rp = GH.rep_carry
        GH.rep_carry = nil
        rp.from, rp.off, rp.T, rp.set = nil, nil, nil, nil
        GH.rep = rp
    end
    -- (the chrome on his bag and cap laid on once, as he is made: laid again 15 times a second, as the camera went
    -- round, it cost 4 ms a frame and the game went from 77 to 51 frames a second - "game is very laggy all of a sudden",
    -- 2026-10-27)
    if GH.actor and GH.chrome and not GH.chrome_done then
        GH.chrome_done = true
        local world = lib.world()
        if GH.pack_pmc and GH.pack_sec then pcall(lib.chrome, world, GH.pack_pmc, GH.pack_sec, GH.chrome) end
        local ML = package.loaded["mariolook"]
        if ML and ML.dressed_pieces and GH.addr then
            for _, p in ipairs(ML.dressed_pieces(GH.addr)) do
                for _, sp in ipairs(p.specs) do
                    if sp.sec and not M.RACER_HIDE[sp.id] then pcall(lib.chrome, world, p.pmc, sp.sec, GH.chrome) end
                end
            end
        end
    end
    ghost_pose()
    if GH.star then
        GH.star_yaw = (GH.star_yaw + 90.0 * dt) % 360.0
        pcall(function() GH.star.actor:K2_SetActorRelativeRotation({ Pitch = 0.0, Yaw = GH.star_yaw, Roll = GH.star_roll or 0.0 }, false, {}, true) end)
        -- (its rainbow running, as caps.lua runs the skin's bag star's)
        if GH.star_mid then
            GH.star_rb = (GH.star_rb or 0.0) + dt
            local off = { R = (GH.star_rb * 0.12) % 40.0, G = (GH.star_rb * 0.05) % 40.0, B = 1.0, A = 1.0 }
            pcall(function() GH.star_mid:SetVectorParameterValue(FName("BaseColorTexture_OffsetScale"), off) end)
        end
    end
    if GH.actor then
        GH.flick = not GH.flick or not M.GHOST_FLICKER
        pcall(function() GH.actor:SetActorHiddenInGame(not (M.on and GH.flick) or GH.away == true) end)
    end
    local DLG = package.loaded["dialog"]
    -- (nothing hurts him while he is lined up and counted down, held on the line, nor in the first moment after GO - a
    -- Bob-omb by Shifting Sand Land's start came for him there: "theres a bombomb attacking the player while the race is
    -- starting", 2026-11-07)
    do
        local HPg = _G.HEALTH
        local s = RACE.state
        if HPg and (s == "fade" or s == "black" or s == "back" or s == "count" or (s == "run" and (RACE.go or 0.0) < 1.5)) then
            HPg.grace = math.max(HPg.grace or 0.0, 0.3)
        end
    end
    if RACE.state == nil then
        -- (talked to: near him, facing him, a push)
        local gx, gy, gz = ghost_spot(list.start and list or headl)
        local dx, dy = gx - x, gy - y
        local d = math.sqrt(dx * dx + dy * dy)
        local push = pushed_now(pawn)
        -- (not again straight after a message: the push that turned its last page - "Don't Go" - counted as a new one,
        -- and he asked again at once, over and over: "if you say no it puts you straight back in the dialog",
        -- 2026-10-27. As the signs: 0.8 s after it shuts, and that push over first)
        if DLG and DLG.active then RACE.shut_at, RACE.wait_push = os.clock(), true end
        if RACE.wait_push then
            if RACE.last_push == nil and os.clock() - (RACE.shut_at or 0.0) > 0.8 then RACE.wait_push = nil end
            push = false
        end
        if GH.actor and not GH.gone and push and d < M.RACE_TALK.reach and math.abs(st[3] - z) < 200.0 and not (DLG and DLG.active) then
            local yaw = 0.0
            pcall(function() yaw = pawn:K2_GetActorRotation().Yaw end)
            local off = (math.deg(math.atan(dy, dx)) - yaw + 540.0) % 360.0 - 180.0
            if math.abs(off) < M.RACE_TALK.facing then
                log("race: the ghost racer talked to")
                pcall(G.dialog_cut, gx, gy, gz, 80.0)
                local ids = star_given(G) and 9004 or intro_ids(G)
                G.ask(ids, function(answer)
                    if answer == 1 then race_begin(G) end
                end)
                intro_said(G, ids)
            end
        end
    elseif RACE.state == "fade" then
        -- (going dark: transition.lua lines them up once it is black; a fade that never gets there, 3 s on, anyway)
        RACE.t = RACE.t + dt
        if RACE.t > 3.0 then
            line_up(G)
            RACE.state, RACE.t = "black", 0.0
        end
    elseif RACE.state == "black" then
        -- (lined up, held black a moment as the camera settles behind him, then the screen back)
        hold_on_spot(G)
        RACE.t = RACE.t + dt
        if RACE.t >= M.FADE.hold then
            local TR = package.loaded["transition"]
            if RACE.dark and TR and TR.open then pcall(TR.open, "black", M.FADE.back) end
            RACE.dark = nil
            RACE.state, RACE.t = "back", 0.0
        end
    elseif RACE.state == "back" then
        -- (the countdown once the screen is all back)
        hold_on_spot(G)
        RACE.t = RACE.t + dt
        if RACE.t >= M.FADE.back / 30.0 then
            RACE.state, RACE.t, RACE.shown = "count", 0.0, nil
            log("race: on the line - the countdown")
        end
    elseif RACE.state == "count" then
        hold_on_spot(G)
        RACE.t = RACE.t + dt
        if RACE.t < 3.0 then
            local n = 3 - math.floor(RACE.t)
            if RACE.shown ~= n then
                RACE.shown = n
                count_show(tostring(n))
                race_sound("menu_change_select", 1.0)
            end
        else
            -- GO: free, the clock running, the first flag taken at the line
            count_show("GO")
            race_sound("race_gun", 1.0)
            race_lock(false)
            -- (two clocks from now: t0 the race timer's, real time, running on through a pause - the only thing that
            -- does: "the only thing that should still be going when you pause is the actual timer", 2026-10-27; g0
            -- the world's, held while paused - the ghost and the recording go by it)
            RACE.state, RACE.t0, RACE.go = "run", os.clock(), 0.0
            RACE.course, RACE.area = M.course_key(M.here()), M.here()    -- (its course, and the leg he is on: M.CHAIN)
            RACE.g0 = RACE.t0
            refresh()                   -- (the first flag's beam lit)
            -- (his run recorded from now; and the ghost off along its own, from where he stands)
            if GR then
                if GR.rec_start(pawn) then GR.rec_tick(0.0, true) end
                local g, whose = ghost_to_race(M.course_key(G.name))
                if g and GH.actor then
                    local from = nil
                    pcall(function()
                        local l = GH.actor:K2_GetActorLocation()
                        from = { l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z }
                    end)
                    GH.rep = { g = g, t0 = RACE.t0, cur = {}, from = from }
                    log("race: the ghost runs %s run, %.2f s", whose, g.final)
                else
                    log("race: no ghost to race yet - this run is recorded")
                end
            end
            local b1 = not (list and list.line) and B[1] or nil     -- (from a start line, the first flag is run to)
            if b1 then
                M.times[1] = RACE.t0
                M.next = 2
                refresh()
                b1.spin_t = 0.0
                pcall(burst, b1)
            end
            -- (moved off his spot in the countdown - STORROR's character screen, swapping his face, took him 60 cm on
            -- past the racer: "okay but why is the ghost starting further back now?", 2026-10-27 - put back on it at GO)
            pcall(function()
                local sp = RACE.spot
                if not sp then return end
                local l = pawn:K2_GetActorLocation()
                local dx, dy = l.X - OFFSET.X - sp.x, l.Y - OFFSET.Y - sp.y
                if dx * dx + dy * dy > 25.0 * 25.0 then
                    pawn:K2_TeleportTo({ X = sp.x + OFFSET.X, Y = sp.y + OFFSET.Y, Z = sp.z + OFFSET.Z }, { Pitch = 0.0, Yaw = sp.yaw, Roll = 0.0 })
                    pawn.CharacterMovement.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
                    if G.reset_cloth then pcall(G.reset_cloth, pawn) end
                    log("race: put back on his spot at GO (%.0f cm off it)", math.sqrt(dx * dx + dy * dy))
                end
            end)
            pcall(function()
                local l = pawn:K2_GetActorLocation()
                local st0 = list and list.start
                if st0 then
                    local fy = math.rad(st0[4] or 0.0)
                    log("race: GO - he is %.0f cm behind the line's middle", -((l.X - OFFSET.X - st0[1]) * math.cos(fy) + (l.Y - OFFSET.Y - st0[2]) * math.sin(fy)))
                end
            end)
            log("race: GO")
            pcall(M.dev_keep, pawn, 0)
        end
    elseif RACE.state == "run" then
        RACE.go = RACE.go + dt
        if RACE.go > 1.0 and CD then count_hide() end
        race_music(true)
        local t = os.clock() - RACE.t0
        if _G.HEALTH then _G.HEALTH.race_clock = t end
        hud_flags()
        if GR then GR.rec_tick(os.clock() - (RACE.g0 or RACE.t0)) end
        -- (every flag taken: with a start line, home to it and over it to finish; without one, the last flag is the end)
        local done_at = nil
        -- (or, with a finish line of its own and no flags, straight there from GO: "make walking through it end the race",
        -- 2026-11-06, Bowser 1's)
        local chained = M.chain_of(M.here()) ~= nil
        if M.chain_last(M.here()) and (#B >= 1 or list.finish) and M.next > #B then
            local fin = list.finish or ((not chained) and list.line) or M.home_line(M.here())
            if fin then
                if over_line(fin, x, y, z) then
                    done_at = os.clock()
                    M.times[#B + 1] = done_at
                    race_sound("oneup", 1.0)
                end
            elseif #B >= 2 or chained then
                done_at = M.times[#B] or os.clock()
            end
        end
        if done_at then
            RACE.final = done_at - RACE.t0
            -- (home before the ghost raced: won - he still has his run to finish, and is talked to once home)
            local won = GH.rep ~= nil and GH.rep.g ~= nil and not GH.rep.done_t
            RACE.old_time = GH.rep and GH.rep.g and GH.rep.g.final or nil       -- (the time he beat, for the retry's box)
            RACE.state, RACE.t = won and "won" or "done", 0.0
            if won then log("race: home before the ghost (%.2f s to his %.2f) - won", RACE.final, GH.rep.g.final) end
            refresh()
            if _G.HEALTH then _G.HEALTH.race_clock = RACE.final end
            hud_flags()
            log("race: finished in %.2f s%s", RACE.final, (list.finish and " - over the finish line")
                or (list.line and " - home over the start line") or "")
            -- (the run kept: the level's ghost if it has none, else this file's best - raced from then on if faster)
            if GR then
                local run = GR.rec_finish(done_at - (RACE.g0 or RACE.t0), RACE.final)
                -- (a win with its star or key still to come: kept only once that is taken - ghost_goes_home, M.reward_tick.
                -- Beaten and the star left lying, the run was kept all the same: "if the player runs the race and beats
                -- the ghost but doesnt take the star / key it saves the new time anyways", 2026-11-06)
                if won and run and not star_given(G) then
                    RACE.hold_run = { scene = M.course_key(G.name), run = run }
                    log("race: this run is kept once his %s is taken", STAGE[course_name(G)] and "key" or "star")
                else
                    local okk, kept = pcall(keep_run, M.course_key(G.name), run)
                    if not okk then log("race ghost: not kept (%s)", tostring(kept))
                    elseif kept then log("race: this run is %s", kept)
                    else log("race: this run is not kept - a faster one is") end
                    RACE.kept = okk and kept or nil
                end
            end
        end
        -- (the ghost home before him: lost)
        if RACE.state == "run" and GH.rep and GH.rep.g and GH.rep.done_t then ghost_won(G) end
    elseif RACE.state == "done" then
        RACE.t = RACE.t + dt
        if RACE.t > 6.0 then race_stop() end
    elseif RACE.state == "lost" then
        -- (he waits where he finished: talked to - near him, facing him, a push - he has his say)
        local gx, gy, gz = talked_to(G, pawn, x, y, z, pushed_now(pawn))
        if gx then ghost_gloat(G, gx, gy, gz) end
    elseif RACE.state == "won" then
        -- (beaten: he runs his run out home, and is talked to once there - his run over)
        local push = pushed_now(pawn)
        if not GH.rep then
            local gx, gy, gz = talked_to(G, pawn, x, y, z, push)
            if gx then ghost_thank(G, gx, gy, gz) end
        end
    elseif RACE.state == "gloat" or RACE.state == "thank" then
        -- (his say read: race_stop, from its end; one that never came up, over a moment on)
        RACE.t = RACE.t + dt
        if RACE.t > 1.0 and not (DLG and DLG.active) then race_stop() end
    end
    -- (the race over - won, lost, or done: the level's music back; on through the black, the countdown and the race)
    if not MUSIC_ON[RACE.state or ""] and RACE.music_on then race_music(false, true) end
end


local function scene_key(G)
    local ok, a = pcall(function() return G.scene_actor:GetAddress() end)
    return ok and a or nil
end

-- The map gone - back to the title, another file - and all of the race's with it, freed: forgotten, never touched (its
-- flags shown or hidden on the new map crashed the game: back to the file select in the race's act, 2026-10-27 21:28)
local function forget_map()
    B, LINE, built_for = {}, {}, nil
    M.DEVK = nil
    RB = nil                    -- (its star went with the map: its material never called on again)
    FX.pool, FX.world, CD = nil, nil, nil
    GH.actor, GH.pack, GH.addr, GH.star, GH.pack_pmc, GH.pack_sec, GH.chrome_done = nil, nil, nil, nil, nil, nil, nil
    GH.body, GH.idle_src, GH.body_rel, GH.rep, GH.gone, GH.key, GH.home = nil, nil, nil, nil, nil, nil, nil
    GH.star_mid = nil
    RACE.state, RACE.locked, RACE.dark, RACE.music_on, RACE.spot, RACE.rmm = nil, nil, nil, nil, nil, nil
    M.next, M.times = 1, {}
    if GR then pcall(GR.rec_drop) end
    local HP = _G.HEALTH
    if HP then HP.race_clock, HP.race_flags, HP.race_of = nil, nil, nil end
end

function M.tick(dt, pawn)
    if pawn then pcall(M.remember_rel, pawn) end         -- (his meshes as he stands, for the racer: M.remember_rel)
    if M.reward_wait then
        local wa = nil
        pcall(function() wa = lib.world():GetAddress() end)
        pcall(M.reward_tick, wa)                        -- (a winning run waiting on its reward: M.reward_tick)
    end
    -- (another map: what was the last one's forgotten first, before anything here can touch it)
    local here = nil
    pcall(function() here = lib.world():GetAddress() end)
    if here ~= M.world_at then
        if M.world_at ~= nil then forget_map() end
        M.world_at = here
    end
    -- (the rainbow running over the star he gave up - as caps.lua runs the bag's - while it is there to be seen)
    if RB then
        local alive = RB.world == here and pcall(function() return RB.st.inst.actor:IsValid() end) and RB.st.inst.actor:IsValid()
        if not alive then
            RB = nil
        else
            RB.t = RB.t + (dt or 0.0)
            local off = { R = (RB.t * 0.12) % 40.0, G = (RB.t * 0.05) % 40.0, B = 1.0, A = 1.0 }
            pcall(function() RB.mid:SetVectorParameterValue(FName("BaseColorTexture_OffsetScale"), off) end)
        end
    end
    local G = package.loaded["game"]
    if not (G and G.name and pawn) or G.pending or G.warping then return end
    local key = scene_key(G)
    local on = (G.extra_act ~= nil) or M.edit or stage_on(G)
    if on ~= M.on then M.on = on; refresh() end
    -- (out of the race's act: the racer and what he wears taken away. His body went with the last scene, but Mario's cap
    -- on him is kept by mariolook.lua (lib.keep) and stood at his spot in the level's other acts: "in other stars on
    -- bomb omb battlefield you can see ghosts hat", 2026-10-30)
    if not on and (GH.addr or GH.actor or GH.pack) then ghost_drop(); GH.key = nil end
    -- (out of the race's act, or into another scene: the race over there and then - its clock and count off the screen,
    -- its run not kept. They went on, on the screen, in the castle: "also I left the level and the timers still going",
    -- "and on screen", 2026-10-27)
    -- (into the next area of the race's course mid-race - M.CHAIN: carried on, not stopped. Back, or anywhere else, it
    -- stops as ever)
    -- (the leg he is on: come into another scene, the next leg there - M.leg_for)
    if not (M.LEG and M.LEG.scene == G.name) then
        local prev = M.LEG and M.LEG.key
        M.LEG = { key = M.leg_for(G.name, prev), scene = G.name }
    end
    local leg = M.here()
    local carry = false
    if RACE.state == "run" and M.on and built_for ~= nil and key ~= built_for and RACE.course and RACE.area
        and M.course_key(leg) == RACE.course then
        local _, ia = M.chain_of(RACE.area)
        local _, ib = M.chain_of(leg)
        carry = ia ~= nil and ib ~= nil and ib > ia
    end
    if RACE.state ~= nil and not carry and (not M.on or (key ~= built_for and built_for ~= nil)) then race_stop() end
    if key ~= built_for then
        -- (another scene: the last one's flags went with it, only forgotten here. The same scene made again - a flag
        -- placed or moved - has its flags taken down first, by build's clear: forgotten first, they were left standing,
        -- one more set at each placing - "next checkpoint here", 2026-10-27)
        if built_for ~= nil then B = {} end
        -- (a flag placed mid-race keeps the race where it was - all six taken were back to the first: "actually add 1
        -- more flag here", 2026-10-27; a new scene, or no race on, from the first)
        local keep = built_for == nil and RACE.state == "run"
        built_for = key
        if carry then
            -- (on into the next area: its flags from its first, the clock and the recording running on - the recording
            -- told where he went, for the ghost's sake)
            RACE.area, RACE.carried = leg, true
            M.next = 1
            if GR and GR.rec_seam then GR.rec_seam(os.clock() - (RACE.g0 or RACE.t0), G.name) end
            log("race: on into %s, %d flags behind him", leg, M.flag_base(leg))
        elseif not keep then M.next, M.times = 1, {} end
        local world = lib.world()
        if world then build(world, leg) end
        if M.next > #B + 1 then M.next = #B + 1 end
        if keep or carry then refresh() end
    end
    -- (paused - Mario 64's pause screen, or STORROR's menu: the race stands still with the rest of the game - the ghost,
    -- the recording, the flags - its world's clock moved on by the time paused, so nothing jumps on after ("when pausing
    -- make sure the game pauses everything", 2026-10-27). Its timer too, now: its start and the flags' times moved on
    -- with it ("the race timer should stop while paused", 2026-10-30 - it ran on before, at "the only thing that should
    -- still be going when you pause is the actual timer", 2026-10-27). Its update is ahead of game.lua's pause.)
    local now = os.clock()
    local last = M.clock_at or now
    M.clock_at = now
    local PA = package.loaded["pause"]
    if PA and (PA.open or (PA.menu_up and PA.menu_up())) and not (PA.online and PA.online()) then
        local d = now - last
        if d > 0.0 then
            if RACE.g0 then RACE.g0 = RACE.g0 + d end           -- (the world's clock held)
            if RACE.t0 then RACE.t0 = RACE.t0 + d end           -- (and the timer's)
            for k, v in pairs(M.times) do M.times[k] = v + d end
            local rp = GH.rep
            if rp then
                rp.t0 = rp.t0 + d
                if rp.done_t then rp.done_t = rp.done_t + d end
            end
        end
        -- (the race timer drawn, held where it stopped - the HUD's update is held with the rest)
        local HP = _G.HEALTH
        if HP then
            if RACE.state == "run" and RACE.t0 then HP.race_clock = now - RACE.t0 end
            if HP.timers_tick then pcall(HP.timers_tick) end
        end
        return
    end
    music_back_tick()
    if (#B == 0 and #LINE == 0) or not M.on then return end      -- (a start line and no flags yet: still its racer)
    -- (each turned to face the camera)
    local l = pawn:K2_GetActorLocation()
    local cx, cy = lib.camera_location(l)
    local x, y, z = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - (G.half or 90.0)
    local now = os.clock()
    for _, fb in ipairs(LINE) do
        if fb.home and fb.beam then
            -- (the home beam turned to the camera, as the flags' are)
            local hx, hy = fb.x + OFFSET.X - cx, fb.y + OFFSET.Y - cy
            pcall(function() fb.beam:K2_SetActorRotation({ Pitch = 0.0, Yaw = math.deg(math.atan(hy, hx)), Roll = 0.0 }, false) end)
        end
        if fb.pole and ((fb.x - x) ^ 2 + (fb.y - y) ^ 2 < 1500.0 * 1500.0 or fb.bent) then bend(fb, dt, x, y, z) end
        if fb.pole_pmc then
            local dx, dy = fb.x + OFFSET.X - cx, fb.y + OFFSET.Y - cy
            fb.cloth_dt = (fb.cloth_dt or 0.0) + dt
            local d2 = dx * dx + dy * dy
            if fb.cloth_dt >= ((d2 > M.CLOTH_FAR * M.CLOTH_FAR) and 2.0 * M.CLOTH_STEP or M.CLOTH_STEP) then
                if d2 < 4000.0 * 4000.0 then
                    local ok, pts = pcall(cloth_sim, fb, math.min(fb.cloth_dt, 0.1), now, 0.0)
                    if ok then pcall(lib.update_section, fb.pole_pmc, SEC_BOWSER, pts) end
                end
                fb.cloth_dt = 0.0
            end
        end
    end
    for _, fb in ipairs(B) do
        if fb.on then pcall(M.ride_tick, fb) end         -- (on the ship: where that is now)
        if fb.ring_actor then pcall(M.ring_tick, fb, dt) end
        local dx, dy = fb.x + OFFSET.X - cx, fb.y + OFFSET.Y - cy
        local yaw = math.deg(math.atan(dy, dx))
        -- (turned only once the camera has gone round it a degree; its cloth every other frame, in sight - within 40 m:
        -- each flag turned and its cloth made again every frame was 1.2 ms of every frame in the race, "just in general"
        -- laggy, 2026-10-31)
        if not fb.yaw_set or math.abs(((yaw - fb.yaw_set + 540.0) % 360.0) - 180.0) > 1.0 then
            fb.yaw_set = yaw
            local rot = { Pitch = 0.0, Yaw = yaw, Roll = 0.0 }
            each_actor(fb, function(a) pcall(function() a:K2_SetActorRotation(rot, false) end) end)
        end
        -- (the pole: pushed, bent, spun - near him, or still moving)
        if fb.pole and ((fb.x - x) ^ 2 + (fb.y - y) ^ 2 < 1500.0 * 1500.0 or fb.spin_t or fb.bent) then
            bend(fb, dt, x, y, z)
        end
        -- (its cloth, in sight: within 40 m of the camera, every other frame with both frames' time)
        fb.cloth_dt = (fb.cloth_dt or 0.0) + dt
        local d2 = dx * dx + dy * dy
        if fb.cloth_dt >= ((d2 > M.CLOTH_FAR * M.CLOTH_FAR) and 2.0 * M.CLOTH_STEP or M.CLOTH_STEP) then
            if fb.pole_pmc and d2 < 4000.0 * 4000.0 then
                local ok, pts = pcall(cloth_sim, fb, math.min(fb.cloth_dt, 0.1), now, fb.spin_w or 0.0)
                if ok then pcall(lib.update_section, fb.pole_pmc, fb.cloth_sec or SEC_BOWSER, pts) end
            end
            fb.cloth_dt = 0.0
        end
    end
    fx_tick(dt, cx, cy)
    local okr, errr = pcall(race_tick, dt, G, pawn, x, y, z)
    if not okr and M.race_err ~= tostring(errr) then M.race_err = tostring(errr); log("race: %s", M.race_err) end
    pcall(M.racer_watch, dt)            -- (the racer whole: M.racer_watch)
    -- (the next one passed: within its reach, his feet about its foot - while the race is run only: a flag the athlete
    -- walks by otherwise stays as it is)
    local b = RACE.state == "run" and B[M.next] or nil
    if b then
        -- (a ring: through it, his middle - M.ring_through)
        local reached
        if b.ring then reached = M.ring_through(b, x, y, z + (G.half or 90.0))
        else reached = (x - b.x) ^ 2 + (y - b.y) ^ 2 < M.REACH * M.REACH and z > b.z - M.BELOW and z < b.z + M.ABOVE end
        if reached then
            M.times[M.next] = os.clock()
            -- (Mario 64's 1-up as he first runs into it - "also use the 1up sound when you first run into the checkpoint",
            -- after "remove the audio when you touch the flag", 2026-10-27)
            local SFX = package.loaded["sfx"]
            if SFX and SFX.play then pcall(SFX.play, "oneup", 1.0, true) end
            if M.next == 1 then
                log("race: beacon 1 passed - the clock starts")
            else
                log("race: beacon %d passed, %.2f s in", M.next, M.times[M.next] - M.times[1])
            end
            M.next = M.next + 1
            refresh()
            b.spin_t = 0.0
            pcall(burst, b)
            pcall(M.dev_keep, pawn, M.next - 1)
        end
    end
end


-- ------------------------------------------------------------ placing them (the dev channel)
-- beacon `n` put at (x, y, z), scene cm - or where he stands, on the floor under him. An `n` there already is moved; one
-- past the end is added; further past, the next number. Saved, and the scene's made again. Returns its number.
function M.place(n, x, y, z)
    local G = package.loaded["game"]
    if not (G and G.name) then return nil end
    if not x then
        local l = lib.pawn():K2_GetActorLocation()
        x, y, z = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - (G.half or 90.0)
        local f = G.floor_z and G.floor_z(x, y, z + 50.0)
        if f and z - f < 150.0 then z = f end
    end
    local all = load_placed()
    all[M.here()] = all[M.here()] or {}
    local list = all[M.here()]
    n = n or #list + 1
    if n > #list + 1 then n = #list + 1 end
    list[n] = { x, y, z }
    save_placed()
    built_for = nil
    log("race: beacon %d at (%.0f, %.0f, %.0f) in %s", n, x, y, z, G.name)
    return n
end

-- ------------------------------------------------------------ under the water: a ring, the flag wrapped round it
-- A checkpoint placed swimming under the water is a ring to swim through, not a flag ("next we have to make underwater
-- rings for checkpoints", "add a flag wrapped around the ring", 2026-11-06): a gold hoop with the flag's cloth wrapped
-- round and round it - Bowser's till it is taken, then Mario's, as a flag's cloth - standing where his middle was,
-- square to the way he swam. Taken going through it: his middle within `hole` cm of its middle across it and `depth`
-- along it; it swells a moment as it is. Its beacon keeps `ring = { yaw, pitch }`. (Mario 64's own water ring,
-- geo_water_ring_geo, drew dark and blocky here.)
-- (one flag, wrapped round `flag` of the hoop - "no just 1 flag is good", 2026-11-06, of a hoop wrapped all round)
M.RING = { r = 210.0, core = 8.0, wrap = 15.0, segs = 64, sides = 12, flag = 0.125, flag_segs = 10, hole = 185.0,
           depth = 90.0, pulse = 0.5 }
-- a ring round the actor's own X axis (the way through it), `R` cm round, its tube `r` thick; `arc` of the way round
-- (all of it, unless given), the picture `repeats` times along it and once round the tube - each a piece of its own
-- with the whole picture (the pictures are clamped at their edges: run on past 1 across, they are see-through)
function M.torus(s, R, r, segs, sides, repeats, arc)
    repeats = repeats or 1
    arc = arc or 1.0
    local per = math.max(1, segs // repeats)
    for k = 0, repeats - 1 do
        local first = s.nverts
        for i = 0, per do
            local t = (k * per + i) / (per * repeats) * 2.0 * math.pi * arc
            local cy, cz = math.cos(t), math.sin(t)
            for j = 0, sides do
                local u = j / sides * 2.0 * math.pi
                local nx, nr = math.sin(u), math.cos(u)
                local ny, nz = cy * nr, cz * nr
                vert(s, r * nx, cy * R + r * ny, cz * R + r * nz, nx, ny, nz, i / per, 1.0 - j / sides, lit(nx, ny, nz))
            end
        end
        for i = 0, per - 1 do
            for j = 0, sides - 1 do
                local a, c = first + i * (sides + 1) + j, first + (i + 1) * (sides + 1) + j
                tri(s, a, c, c + 1)
                tri(s, a, c + 1, a + 1)
            end
        end
    end
end
-- its actor: section 0 the gold hoop, 1 Bowser's cloth round it, 2 Mario's
function M.ring_actor(world, b)
    local yaw, pitch = b.ring[1] or 0.0, b.ring[2] or 0.0
    local a = lib.spawn_actor(world, { X = b.x + OFFSET.X, Y = b.y + OFFSET.Y, Z = b.z + OFFSET.Z }, yaw)
    if not a then return nil end
    local pmc = lib.add_pmc(a)
    if not pmc then return a end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    local R = M.RING
    local gold = new_sec(0, "opaque", "race_gold")
    M.torus(gold, R.r, R.core, R.segs, 8, 1)
    local bowser, mario = new_sec(1, "alpha", "race_cloth_bowser5"), new_sec(2, "alpha", "race_cloth_mario2")
    M.torus(bowser, R.r, R.wrap, R.flag_segs, R.sides, 1, R.flag)
    M.torus(mario, R.r, R.wrap, R.flag_segs, R.sides, 1, R.flag)
    lib.add_sections(world, pmc, { gold, bowser, mario })
    pcall(function() pmc:SetMeshSectionVisible(2, false) end)
    pcall(function() a:K2_SetActorRotation({ Pitch = pitch, Yaw = yaw, Roll = 0.0 }, false) end)
    return a, pmc
end
-- (x, y, z) - his middle - through ring b now
function M.ring_through(b, x, y, z)
    local yaw, pitch = math.rad(b.ring[1] or 0.0), math.rad(b.ring[2] or 0.0)
    local nx, ny, nz = math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), math.sin(pitch)
    local dx, dy, dz = x - b.x, y - b.y, z - b.z
    local along = dx * nx + dy * ny + dz * nz
    if math.abs(along) > M.RING.depth then return false end
    local rx, ry, rz = dx - along * nx, dy - along * ny, dz - along * nz
    return rx * rx + ry * ry + rz * rz < M.RING.hole * M.RING.hole
end
-- each tick: taken, it swells a moment (b.spin_t, set as it is taken)
function M.ring_tick(b, dt)
    if not (b.ring_actor and b.spin_t) then return end
    b.spin_t = b.spin_t + (dt or 0.016)
    local f = b.spin_t / M.RING.pulse
    local k = 1.0 + 0.25 * math.sin(math.min(1.0, f) * math.pi)
    pcall(function() b.ring_actor:SetActorScale3D({ X = k, Y = k, Z = k }) end)
    if f >= 1.0 then b.spin_t = nil end
end
-- beacon `n` here: a ring swimming under the water, else a flag (M.place)
function M.place_here(n)
    local G = package.loaded["game"]
    if G and G.swim and G.swim_under then return M.place_ring(n) end
    return M.place(n)
end
function M.place_ring(n)
    local G = package.loaded["game"]
    if not (G and G.name) then return nil end
    local p = lib.pawn()
    local l = p:K2_GetActorLocation()
    local x, y, z = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z
    -- (square to the way he swims: his way through the water, or the way he faces when still)
    local yaw, pitch = p:K2_GetActorRotation().Yaw, 0.0
    pcall(function()
        local v = p:GetVelocity()
        local hs = math.sqrt(v.X * v.X + v.Y * v.Y)
        if hs > 40.0 then yaw = math.deg(math.atan(v.Y, v.X)) end
        if hs + math.abs(v.Z) > 60.0 then pitch = math.deg(math.atan(v.Z, math.max(hs, 1.0))) end
    end)
    local all = load_placed()
    all[M.here()] = all[M.here()] or {}
    local list = all[M.here()]
    n = n or #list + 1
    if n > #list + 1 then n = #list + 1 end
    list[n] = { x, y, z, ring = { yaw, pitch } }
    save_placed()
    built_for = nil
    log("race: beacon %d at (%.0f, %.0f, %.0f) in %s, a ring under the water, facing %.0f, %.0f up", n, x, y, z, G.name, yaw,
        pitch)
    return n
end

-- A flag on something that moves - Jolly Roger Bay's ship ("your gonna have to attach it to the moving boat",
-- 2026-11-06). Its beacon keeps `on`: the platform's kind and where the level has it (platforms.lua's P.list, `o.bhv`,
-- `o.pos`), and the flag's place in the platform's own space. Each tick it is put where that place is now - its foot,
-- pole and beam; taken where it is. With no such platform in the scene it stands where it was placed.
function M.ride_axes(rot)
    local P, Y, R = math.rad(rot.Pitch or 0.0), math.rad(rot.Yaw or 0.0), math.rad(rot.Roll or 0.0)
    local sp, cp, sy, cy, sr, cr = math.sin(P), math.cos(P), math.sin(Y), math.cos(Y), math.sin(R), math.cos(R)
    -- (Unreal's own: its forward, right and up)
    return cp * cy, cp * sy, sp,
           sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp,
           -(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp
end
-- (x, y, z) in scene cm, in platform p's own space as it is drawn now
function M.ride_local(p, x, y, z)
    local fx, fy, fz, rx, ry, rz, ux, uy, uz = M.ride_axes(p.rot)
    local dx, dy, dz = x - p.wx, y - p.wy, z - (p.wz or z)
    return dx * fx + dy * fy + dz * fz, dx * rx + dy * ry + dz * rz, dx * ux + dy * uy + dz * uz
end
function M.ride_tick(b)
    local on = b.on
    if not on then return end
    local r = b.ride
    local PL = package.loaded["platforms"]
    -- (the scene made again - a death, the level come back to - makes its platforms anew, in a new list: the one ridden
    -- looked for again. On the old one's record the flag stood still while the ship rocked on, and that one's actor was
    -- gone - "the checkpoint flag on the boat isnt sticking on anymore", 2026-11-06)
    if r and (not PL or r.list ~= PL.list or r.p.gone) then r, b.ride = nil, nil end
    if not r then
        -- (its platform found once the scene has it: of its kind, where the level has it)
        local now = os.clock()
        if now < (b.ride_look or 0.0) then return end
        b.ride_look = now + 1.0
        for _, q in ipairs(PL and PL.list or {}) do
            local o = q.o
            if o and o.bhv == on[1] and o.pos and math.abs(o.pos[1] - on[2]) < 1.0 and math.abs(o.pos[2] - on[3]) < 1.0
                and math.abs(o.pos[3] - on[4]) < 1.0 then
                r = { p = q, list = PL.list }
                b.ride = r
                log("race: a flag rides the %s", tostring(on[1]))
                break
            end
        end
        if not r then return end
    end
    local p = r.p
    if not (p.wx and p.rot) then return end
    local fx, fy, fz, rx, ry, rz, ux, uy, uz = M.ride_axes(p.rot)
    local lx, ly, lz = on[5], on[6], on[7]
    local x = p.wx + fx * lx + rx * ly + ux * lz
    local y = p.wy + fy * lx + ry * ly + uy * lz
    local z = (p.wz or 0.0) + fz * lx + rz * ly + uz * lz
    if r.x and math.abs(x - r.x) + math.abs(y - r.y) + math.abs(z - r.z) < 0.5 then return end
    r.x, r.y, r.z = x, y, z
    b.x, b.y, b.z = x, y, z
    local loc = { X = x + OFFSET.X, Y = y + OFFSET.Y, Z = z + OFFSET.Z }
    for _, a in ipairs({ b.base or false, b.pole or false, b.beam or false, b.ring_actor or false }) do
        if a then pcall(function() a:K2_SetActorLocation(loc, false, {}, true) end) end
    end
end
-- beacon `n` where he stands, on the platform under him (platforms.lua's P.on), riding it
function M.place_on(n)
    local G = package.loaded["game"]
    local PL = package.loaded["platforms"]
    local p = PL and PL.on
    if not (G and G.name and p and p.o and p.o.bhv and p.o.pos and p.wx and p.rot) then return nil end
    local l = lib.pawn():K2_GetActorLocation()
    local x, y, z = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - (G.half or 90.0)
    local lx, ly, lz = M.ride_local(p, x, y, z)
    local all = load_placed()
    all[M.here()] = all[M.here()] or {}
    local list = all[M.here()]
    n = n or #list + 1
    if n > #list + 1 then n = #list + 1 end
    list[n] = { x, y, z, on = { p.o.bhv, p.o.pos[1], p.o.pos[2], p.o.pos[3], lx, ly, lz } }
    save_placed()
    built_for = nil
    log("race: beacon %d at (%.0f, %.0f, %.0f) in %s, on the %s (%.0f, %.0f, %.0f in its own space)", n, x, y, z, G.name,
        p.o.bhv, lx, ly, lz)
    return n
end

-- A failsafe for the ghost racer drawn as no more than his backpack - his body, and all that his body leads, there and
-- visible and not drawn ("he's legit just a floating backpack", then "make a failsafe", 2026-11-06; made again, he was
-- whole). Checked twice a second while he waits for a race: his bag drawn and his body not, for `after` s, and he is made
-- again where he stands - `most` times a minute at most. Not while a race is under way.
M.RACER_WATCH = { every = 0.5, after = 1.5, most = 3 }
function M.racer_watch(dt)
    local W = M.RACER_WATCH
    GH.watch_t = (GH.watch_t or 0.0) + (dt or 0.016)
    if GH.watch_t < W.every then return end
    local step = GH.watch_t
    GH.watch_t = 0.0
    if not (M.on and GH.actor and GH.body and GH.pack_pmc) or RACE.state ~= nil then GH.unseen = 0.0; return end
    local okp, bag = pcall(function() return GH.pack_pmc:WasRecentlyRendered(0.3) end)
    local okb, body = pcall(function() return GH.body:WasRecentlyRendered(0.3) end)
    if not (okp and okb) then return end
    -- (or his body there and drawn at a tenth of his size - made while the athlete's was shrunk: drawn, but a speck)
    local okc, sc = pcall(function() return GH.body:K2_GetComponentScale().X end)
    local shrunk = okc and sc and (sc < 0.8 or sc > 1.25)
    -- (or tipped over - upside down in the floor, 2026-11-06: waiting, he stands upright)
    local okr, over = pcall(function() local r = GH.body:K2_GetComponentRotation(); return math.abs(r.Pitch) > 45.0 or math.abs(r.Roll) > 45.0 end)
    if okr and over then shrunk = true end
    if (bag and not body) or shrunk then GH.unseen = (GH.unseen or 0.0) + step else GH.unseen = 0.0 end
    if GH.unseen < W.after then return end
    GH.unseen = 0.0
    local now = os.clock()
    local recent = {}
    for _, t in ipairs(M.racer_fixes or {}) do if now - t < 60.0 then recent[#recent + 1] = t end end
    M.racer_fixes = recent
    if #recent >= W.most then return end
    recent[#recent + 1] = now
    log("race: the racer's body was not drawn (his bag was) - made again")
    ghost_drop()
    GH.key = nil
end

-- the ghost racer's place (and the race's start): where he stands, on the floor, facing his way - or as given
function M.set_start(x, y, z, yaw)
    local G = package.loaded["game"]
    if not (G and G.name) then return nil end
    if not x then
        local p = lib.pawn()
        local l = p:K2_GetActorLocation()
        x, y, z = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - (G.half or 90.0)
        local f = G.floor_z and G.floor_z(x, y, z + 50.0)
        if f and z - f < 150.0 then z = f end
        yaw = p:K2_GetActorRotation().Yaw
    end
    local all = load_placed()
    all[M.here()] = all[M.here()] or {}
    all[M.here()].start = { x, y, z, yaw or 0.0 }
    save_placed()
    log("race: the ghost racer's place at (%.0f, %.0f, %.0f), facing %.0f, in %s", x, y, z, yaw or 0.0, G.name)
    return true
end
function M.start_of(name)
    local G = package.loaded["game"]
    local t = load_placed()[name or M.here() or ""]
    return t and t.start
end

-- the start line: across the way he faces, `ahead` cm in front of his feet, `w` wide; the ghost racer and the countdown
-- moved onto it (its middle, its way)
function M.set_line(ahead, w)
    local G = package.loaded["game"]
    if not (G and G.name) then return nil end
    local p = lib.pawn()
    local l = p:K2_GetActorLocation()
    local yaw = p:K2_GetActorRotation().Yaw
    local x, y, z = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - (G.half or 90.0)
    x, y = x + math.cos(math.rad(yaw)) * (ahead or 60.0), y + math.sin(math.rad(yaw)) * (ahead or 60.0)
    local f = G.floor_z and G.floor_z(x, y, z + 50.0)
    if f and z - f < 150.0 then z = f end
    x, y, w = M.fit_line(x, y, z, yaw, w or 700.0)        -- (on its ground: M.fit_line)
    local all = load_placed()
    all[M.here()] = all[M.here()] or {}
    all[M.here()].line = { x, y, z, yaw, w or 700.0 }
    all[M.here()].start = { x, y, z, yaw }
    -- (and the racer at his spot by it, turned round to face back down the line - "turn ghost around everytime you
    -- place a start", 2026-11-06)
    local rx, ry, rz, ryaw = line_spot(all[M.here()].start)
    all[M.here()].racer = { rx, ry, rz, ((ryaw + 360.0) % 360.0) - 180.0 }
    save_placed()
    built_for = nil
    -- (the ghost racer made again, on the line)
    ghost_drop()
    GH.key = nil
    log("race: the start line at (%.0f, %.0f, %.0f), the way %.0f, %.0f wide, in %s", x, y, z, yaw, w or 700.0, G.name)
    return true
end

-- A line fitted to the ground it lies on: from (x, y, z) across the way run (`yaw`), out each side to where the floor
-- ends (none within 40 cm of z), the line put in the middle of that and as wide as it leaves - its end flags inside its
-- edges - at most `w`. Bowser 1's finish, 7 m wide where its top is 4.6 m, hung off one side: "the finish is offcenter
-- and hangs off edge", 2026-11-06. The middle and width it gives.
M.LINE_EDGE = 50.0      -- cm kept in from each edge (the end flags stand 35 past the line's ends)
function M.fit_line(x, y, z, yaw, w)
    local G = package.loaded["game"]
    if not (G and G.floor_z) then return x, y, w end
    local fx, fy = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
    local ax, ay = -fy, fx
    local function edge(sgn)
        for d = 10, w / 2.0 + 200.0, 10 do
            local f = G.floor_z(x + ax * d * sgn, y + ay * d * sgn, z + 60.0)
            if not f or math.abs(f - z) > 40.0 then return d - 10 end
        end
        return w / 2.0 + 200.0
    end
    local lo, hi = edge(-1), edge(1)
    local shift = (hi - lo) / 2.0
    local fit = math.max(150.0, math.min(w, lo + hi - 2.0 * M.LINE_EDGE))
    return x + ax * shift, y + ay * shift, fit
end

-- A winning run waiting on its star or key (ghost_goes_home): kept the moment it is taken; the level left with it lying
-- there, the run dropped. `here`: the world's address now.
function M.reward_tick(here)
    local rw = M.reward_wait
    if not rw then return end
    if rw.st and rw.st.taken then
        M.reward_wait = nil
        local okk, kept = pcall(keep_run, rw.scene, rw.run)
        if not okk then log("race ghost: not kept (%s)", tostring(kept))
        elseif kept then log("race: its reward taken - this run is %s", kept)
        else log("race: its reward taken - this run is not kept, a faster one is") end
    elseif here ~= rw.world then
        M.reward_wait = nil
        log("race: its reward left lying - the run that won it not kept")
    end
end

-- where the race's star or key comes out once its ghost is beaten: where he stands, on the floor (ghost_goes_home)
function M.set_reward()
    local G = package.loaded["game"]
    if not (G and G.name) then return nil end
    local l = lib.pawn():K2_GetActorLocation()
    local x, y, z = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - (G.half or 90.0)
    local f = G.floor_z and G.floor_z(x, y, z + 50.0)
    if f and z - f < 150.0 then z = f end
    local all = load_placed()
    all[M.here()] = all[M.here()] or {}
    all[M.here()].reward = { x, y, z }
    save_placed()
    log("race: its reward comes out at (%.0f, %.0f, %.0f) in %s", x, y, z, G.name)
    return true
end

-- whether the scene's race has a finish line of its own (refresh: its way home lit from GO when it has no flags)
function M.LIST_FINISH()
    local G = package.loaded["game"]
    local list = G and G.name and load_placed()[M.here()]
    return (list and list.finish) and true or false
end

-- the finish line, where the race ends instead of back over the start: across the way he faces, `ahead` cm in front of
-- his feet, `w` wide at most - fitted to its ground, M.fit_line ("race end here", 2026-11-06)
function M.set_finish(ahead, w)
    local G = package.loaded["game"]
    if not (G and G.name) then return nil end
    local p = lib.pawn()
    local l = p:K2_GetActorLocation()
    local yaw = p:K2_GetActorRotation().Yaw
    local x, y, z = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - (G.half or 90.0)
    x, y = x + math.cos(math.rad(yaw)) * (ahead or 0.0), y + math.sin(math.rad(yaw)) * (ahead or 0.0)
    local f = G.floor_z and G.floor_z(x, y, z + 50.0)
    if f and z - f < 150.0 then z = f end
    x, y, w = M.fit_line(x, y, z, yaw, w or 700.0)
    local all = load_placed()
    all[M.here()] = all[M.here()] or {}
    all[M.here()].finish = { x, y, z, yaw, w or 700.0 }
    save_placed()
    built_for = nil
    log("race: the finish line at (%.0f, %.0f, %.0f), the way %.0f, %.0f wide, in %s", x, y, z, yaw, w or 700.0, G.name)
    return true
end

-- the racer's place: where he stands, on the floor, facing his way
function M.set_racer()
    local G = package.loaded["game"]
    if not (G and G.name) then return nil end
    local p = lib.pawn()
    local l = p:K2_GetActorLocation()
    local x, y, z = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - (G.half or 90.0)
    local f = G.floor_z and G.floor_z(x, y, z + 50.0)
    if f and z - f < 150.0 then z = f end
    local all = load_placed()
    all[M.here()] = all[M.here()] or {}
    all[M.here()].racer = { x, y, z, p:K2_GetActorRotation().Yaw }
    save_placed()
    ghost_drop()
    GH.key = nil
    log("race: the racer's place at (%.0f, %.0f, %.0f) in %s", x, y, z, G.name)
    return true
end

-- beacon `n` put in before the one numbered `n` now (those after it one on)
function M.insert(n, x, y, z)
    local G = package.loaded["game"]
    local all = load_placed()
    local list = all[M.here()] or {}
    if n > #list then return M.place(n, x, y, z) end
    table.insert(list, n, { 0, 0, 0 })
    all[M.here()] = list
    return M.place(n, x, y, z)
end

function M.remove(n)
    local G = package.loaded["game"]
    local list = load_placed()[M.here()]
    if not (list and list[n]) then return false end
    table.remove(list, n)
    save_placed()
    built_for = nil
    log("race: beacon %d taken out in %s", n, G.name)
    return true
end

function M.list(name)
    local G = package.loaded["game"]
    local list = load_placed()[name or M.here() or ""] or {}
    local out = {}
    for i, b in ipairs(list) do out[#out + 1] = string.format("%d (%.0f, %.0f, %.0f)", i, b[1], b[2], b[3]) end
    return table.concat(out, "; ")
end

-- the best finish on a course's race, in seconds, or nil: the star select shows it under the 100-coin star. (Kept
-- with the file once the race is run to its end; none yet.)
-- the best time in `scene` of the save file being played (its best run kept: file_ghost), or nil
-- (`scene` the course's first area: its race may be in any of its areas - kept by that area's name)
function M.best(scene)
    local G = package.loaded["game"]
    local course = scene
    pcall(function() course = G.level_of(scene) end)
    for _, s in ipairs({ scene, course .. "_2", course .. "_3", course .. "_4" }) do
        local ok, g = pcall(file_ghost, s)
        if ok and g then return g.final end
    end
    return nil
end

-- the map went: forget what was on it
function M.forget() forget_map() end

return M
