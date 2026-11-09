-- SM64Map: the Mario look for the athlete (the user, 2026-10-16: "make custom charater a new face shirt pant and shoe
-- option" - from his picture: Mario's big round nose and his dark brown, scalloped mustache over the face, "his eyes
-- should be blue", "I want his hat to be a baseball cap thats red with the M on the front", "I want a baseball cap not
-- the mario hat"). On his head bone: a red baseball cap (six panels, a button, a brim, Mario 64's white M badge on its
-- front), a nose and a mustache, all made here (shaded in their colours, unlit as the rest of the mod), and his irises
-- tinted blue (the MetaHuman eye's IrisBleedTint). The head bone's axes: X up the neck, Y forward, Z to his left.
-- Sizes from the face's own bones (2026-10-16): nose tip 3.2 up 12.8 forward, upper lip 0.2 / 11.6, forehead skin
-- 11.6 / 10.7, scalp top 18.7 up, ears 7.4 out.
local lib = require("lib")
local log = lib.log

local M = {}
local look = nil

-- the cap: a baseball cap - its crown part of an egg round the head (middle X/Y, radii A up, BF forward, BB back,
-- C side; SH < 1 fills its shoulders out: "the hat's squeezed"), cut by a slope from its front edge's height (FRONT)
-- to its back edge's (BACK); the brim BRIM long, tipped down by DROOP. Fitted to his scalp (the first, sized round his
-- own hair, stood off his head: "theres gaps in the hat or air where it shold be attached to his head"); his own hair
-- hidden under it ("his hairs sticking out of it" - STORROR's brush cut has no fitting for this face: it hung in his
-- neck, and putting a hair asset back crashed the game) and Mario's dark hair at the back and sides instead
-- (sized for Max Cave's head - Mario's face is his, "make marios face max caves face": the back of his skull is
-- fuller than Sacha's, and came through the cap and the hair at the back)
M.CAP = { X = 8.0, Y = 0.6, A = 11.4, BF = 11.5, BB = 13.0, C = 9.9, SH = 0.65, FRONT = 11.6, BACK = 5.6, BRIM = 7.0,
          DROOP = 0.18 }
-- where his hair stops, round his head: (angle from the front in degrees, its lowest height); above the cap's edge
-- there is none (the forehead)
M.HAIRLINE = { { 0, 99 }, { 60, 99 }, { 65, 5.0 }, { 74, 3.8 }, { 79, 3.9 }, { 85, 6.4 }, { 103, 6.4 }, { 112, 4.4 },
               { 132, 3.0 }, { 180, 2.8 } }
-- His own hair: kept under the cap (true) - but Max's tight curls needed a cap so big "it looks like he has a big head"
-- - so hidden under it (his scalp has a short buzz of its own); FAKE_HAIR, the made one, "looks like a helmet"
M.OWN_HAIR = false
M.FAKE_HAIR = false
M.TUFTS = { N = 13, LEN = 1.1, FROM = 96 }   -- (tufts along the back edge: how many round the head, how long, from where)
-- the opening at the back over the strap (the user's picture, "add this thing thats on the back of hats"): its half
-- width round the head (radians), its height over the edge (cm); the strap across its bottom, its height and snaps
M.BACK_GAP = { W = 0.42, H = 4.2, STRAP = 1.3, SNAPS = 5 }
M.BADGE = { UP = 15.2, R = 3.3 }                               -- the white badge with the M: its height, its half size
-- the band: the bottom of the crown drawn in round his head (forward / back / side radii from the middle), blending
-- out into the crown's fuller shape over H cm above its edge (roomy over the curls, no air at its edge: "theres gaps")
-- (HB: how high it blends at the back - there the edge is low, on the short fade, and the curls start just above it:
-- a tall band there pushed them through, a loose one left the strap "floating of the head")
M.BAND = { BF = 11.7, BB = 11.9, C = 9.3, H = 5.0, HB = 3.0 }
-- his own hair kept shorter under the cap (the groom's hair length scale, which must be switched on first: "the hair
-- still pokes throught the hat")
M.HAIR_LENGTH = 0.14
M.NOSE = { X = 3.8, Y = 13.6, R = { 2.9, 2.6, 3.1 } }          -- its middle (up, forward) and its radii (up, fwd, side)
M.STACHE = { X = 1.2, OUT = 1.0, DEPTH = 3.0 }                 -- its top's height, how far out from the skin, thickness
M.IRIS = { R = 0.18, G = 0.45, B = 1.0 }
-- how far forward his skin is at each distance out to his side, round the upper lip (from the face's bones)
local FACE = { { 0.0, 12.6 }, { 1.5, 12.0 }, { 3.0, 11.0 }, { 4.5, 10.2 }, { 6.0, 9.4 }, { 7.5, 8.4 }, { 8.5, 7.6 } }

local SKIN = { 1.0, 0.70, 0.53 }
local HAIR = { 0.22, 0.10, 0.06 }
local RED = { 0.92, 0.06, 0.07 }
local WHITE = { 1.0, 1.0, 1.0 }

-- shade a colour as if lit from above, in front and a little to his left
local function shade(c, nx, ny, nz)
    local k = 0.55 + 0.45 * math.max(0.0, nx * 0.55 + ny * 0.75 + nz * 0.25)
    return c[1] * k, c[2] * k, c[3] * k
end

-- a section of triangles: positions (cm, bone space), normals, colours, indices
local function section(id)
    return { id = id, layer = "opaque", pos = {}, nrm = {}, uv = {}, col = {}, idx = {}, nverts = 0 }
end
local function vert(s, x, y, z, nx, ny, nz, c)
    local r, g, b = shade(c, nx, ny, nz)
    local n = s.nverts
    s.pos[#s.pos + 1], s.pos[#s.pos + 2], s.pos[#s.pos + 3] = x, y, z
    s.nrm[#s.nrm + 1], s.nrm[#s.nrm + 2], s.nrm[#s.nrm + 3] = nx, ny, nz
    s.uv[#s.uv + 1], s.uv[#s.uv + 2] = 0.0, 0.0
    s.col[#s.col + 1], s.col[#s.col + 2], s.col[#s.col + 3], s.col[#s.col + 4] = r, g, b, 1.0
    s.nverts = n + 1
    return n
end
local function tri(s, a, b, c) s.idx[#s.idx + 1], s.idx[#s.idx + 2], s.idx[#s.idx + 3] = a, b, c end
-- every triangle both ways round (the plain material shows one side only: the first nose came out a hollow ring)
local function both(s)
    local n = #s.idx
    for t = 0, n // 3 - 1 do tri(s, s.idx[t * 3 + 1], s.idx[t * 3 + 3], s.idx[t * 3 + 2]) end
    return s
end

-- the nose: an egg, a little wider than it is tall, over his own nose
local function nose_section()
    local s = section(0)
    local N = M.NOSE
    local RINGS, SEGS = 10, 16
    for r = 0, RINGS do
        local th = math.pi * r / RINGS
        for g = 0, SEGS do
            local ph = 2.0 * math.pi * g / SEGS
            -- unit sphere: a = up (X), b = forward (Y), c = left (Z)
            local a, b, c = math.cos(th), math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph)
            vert(s, N.X + a * N.R[1], N.Y + b * N.R[2], c * N.R[3], a, b, c, SKIN)
        end
    end
    for r = 0, RINGS - 1 do
        for g = 0, SEGS - 1 do
            local p = r * (SEGS + 1) + g
            local q = p + SEGS + 1
            tri(s, p, q, p + 1)
            tri(s, p + 1, q, q + 1)
        end
    end
    return both(s)
end

-- the mustache's outline, its right half (u: out to his side, cm; v: up from its top's height), top middle to bottom
-- middle round the outside: a curl up at each end, three scallops underneath
local OUTLINE = {
    { 0.0, 0.5 }, { 2.0, 0.7 }, { 4.0, 0.9 }, { 5.8, 1.3 }, { 7.0, 2.0 }, { 7.7, 1.8 }, { 7.9, 0.8 }, { 7.6, -0.6 },
    { 7.0, -1.7 }, { 6.2, -1.3 }, { 5.5, -2.3 }, { 4.6, -2.7 }, { 3.9, -2.0 }, { 3.2, -3.0 }, { 2.2, -3.4 },
    { 1.4, -2.6 }, { 0.7, -2.7 }, { 0.0, -2.1 },
}
-- The characters (charpick.lua M.CHAR_OF: Max is Mario, Benj Luigi, Toby Wario, Drew Waluigi - "make 3 other
-- charaters and all they're clothing", 2026-11-01): each one's cap colour and badge (make_character_textures.py), its
-- mustache's colour, shape (OUTLINE's kind: its right half) and the middle its front fans from (inside the shape), its
-- nose's colour and size. The pieces are made in the colours of M.CHAR as they go on (put_on: use_char).
local MARIO_OUTLINE = {}
for i, p in ipairs(OUTLINE) do MARIO_OUTLINE[i] = { p[1], p[2] } end
M.CHARS = {
    mario = { cap = { 0.92, 0.06, 0.07 }, badge = "actors__mario_cap__mario_cap_logo.rgba16", stache = { 0.22, 0.10, 0.06 },
              nose = { 1.0, 0.70, 0.53 }, nose_r = { 2.9, 2.6, 3.1 }, nose_y = 13.6, outline = MARIO_OUTLINE, cv = -0.8 },
    -- Luigi: green, his L; a fuller, squarer mustache with less curl
    luigi = { cap = { 0.07, 0.55, 0.12 }, badge = "luigi_cap_logo", stache = { 0.16, 0.08, 0.05 },
              nose = { 1.0, 0.70, 0.53 }, nose_r = { 2.8, 2.6, 2.9 }, nose_y = 13.6, cv = -0.9,
              outline = { { 0.0, 0.5 }, { 2.0, 0.7 }, { 4.0, 0.8 }, { 5.6, 1.0 }, { 6.6, 1.4 }, { 7.2, 1.1 }, { 7.3, 0.0 },
                          { 6.9, -1.1 }, { 6.1, -1.9 }, { 5.1, -2.2 }, { 4.1, -2.4 }, { 3.1, -2.5 }, { 2.1, -2.7 },
                          { 1.1, -2.5 }, { 0.0, -2.3 } } },
    -- Wario: yellow, his W; a big pink nose; a wide zig-zag mustache with its points up
    wario = { cap = { 0.98, 0.80, 0.04 }, badge = "wario_cap_logo", stache = { 0.14, 0.08, 0.04 },
              nose = { 1.0, 0.60, 0.60 }, nose_r = { 3.5, 3.4, 4.0 }, nose_y = 14.0, cv = -0.9,
              outline = { { 0.0, 0.6 }, { 1.5, 0.9 }, { 3.0, 1.5 }, { 4.5, 2.4 }, { 6.0, 3.5 }, { 7.3, 4.6 }, { 7.9, 4.4 },
                          { 7.7, 3.0 }, { 7.1, 1.4 }, { 6.3, 0.0 }, { 5.3, -1.2 }, { 4.3, -1.8 }, { 3.2, -1.3 },
                          { 2.1, -2.2 }, { 1.0, -2.6 }, { 0.0, -2.0 } } },
    -- Waluigi: purple, his upside-down L; a long pointed nose; a thin mustache curling up at its ends
    waluigi = { cap = { 0.36, 0.09, 0.52 }, badge = "waluigi_cap_logo", stache = { 0.10, 0.06, 0.04 },
                nose = { 1.0, 0.62, 0.58 }, nose_r = { 2.4, 4.2, 2.3 }, nose_y = 14.8, cv = -0.2,
                outline = { { 0.0, 0.4 }, { 2.0, 0.5 }, { 4.0, 0.8 }, { 5.8, 1.4 }, { 7.0, 2.3 }, { 7.8, 3.2 }, { 7.6, 2.5 },
                            { 6.5, 1.3 }, { 5.1, 0.3 }, { 3.6, -0.3 }, { 2.1, -0.5 }, { 0.9, -0.6 }, { 0.0, -0.6 } } },
}
M.CHAR = "mario"
local BADGE_TEX = M.CHARS.mario.badge
local function use_char(name)
    local c = M.CHARS[name] or M.CHARS.mario
    RED[1], RED[2], RED[3] = c.cap[1], c.cap[2], c.cap[3]
    HAIR[1], HAIR[2], HAIR[3] = c.stache[1], c.stache[2], c.stache[3]
    SKIN[1], SKIN[2], SKIN[3] = c.nose[1], c.nose[2], c.nose[3]
    M.NOSE.R = { c.nose_r[1], c.nose_r[2], c.nose_r[3] }
    M.NOSE.Y = c.nose_y
    M.STACHE.CV = c.cv
    for i = #OUTLINE, 1, -1 do OUTLINE[i] = nil end
    for i, p in ipairs(c.outline) do OUTLINE[i] = { p[1], p[2] } end
    BADGE_TEX = c.badge
end
function M.set_char(name) if M.CHARS[name] then M.CHAR = name end end

-- his skin's forwardness u out to the side (FACE, between its points)
local function face(u)
    u = math.abs(u)
    for i = 1, #FACE - 1 do
        local a, b = FACE[i], FACE[i + 1]
        if u <= b[1] or i == #FACE - 1 then return a[2] + (b[2] - a[2]) * (u - a[1]) / (b[1] - a[1]) end
    end
end
local function stache_section()
    local s = section(1)
    local S = M.STACHE
    -- the whole outline, his left (z +) then his right, round as one loop
    local loop = {}
    for i = 1, #OUTLINE do loop[#loop + 1] = { OUTLINE[i][1], OUTLINE[i][2] } end
    for i = #OUTLINE - 1, 2, -1 do loop[#loop + 1] = { -OUTLINE[i][1], OUTLINE[i][2] } end
    -- (its front just out from his skin, bending back round his face; its back DEPTH behind, inside the face)
    local function at(u, v, back)
        return S.X + v, face(u) + S.OUT - (back and S.DEPTH or 0.0), u
    end
    local function normal_front(u)
        local dz = (face(u) - face(math.abs(u) + 0.5)) / 0.5 * (u < 0 and -1 or 1)
        local l = math.sqrt(1.0 + dz * dz)
        return 0.0, 1.0 / l, dz / l
    end
    -- front: a fan from a middle point
    local cu, cv = 0.0, S.CV or -0.8
    local fx, fy, fz = at(cu, cv, false)
    local mid = vert(s, fx, fy, fz, 0.0, 1.0, 0.0, HAIR)
    local first = s.nverts
    for _, p in ipairs(loop) do
        local x, y, z = at(p[1], p[2], false)
        local nx, ny, nz = normal_front(p[1])
        vert(s, x, y, z, nx + 0.15, ny, nz, HAIR)
    end
    local n = #loop
    for i = 0, n - 1 do tri(s, mid, first + (i + 1) % n, first + i) end
    -- back: the same, further in
    local bmid = vert(s, fx, fy - S.DEPTH, fz, 0.0, -1.0, 0.0, HAIR)
    local bfirst = s.nverts
    for _, p in ipairs(loop) do
        local x, y, z = at(p[1], p[2], true)
        vert(s, x, y, z, 0.0, -1.0, 0.0, HAIR)
    end
    for i = 0, n - 1 do tri(s, bmid, bfirst + i, bfirst + (i + 1) % n) end
    -- its edge all round, between the two
    for i = 1, n do
        local p, q = loop[i], loop[i % n + 1]
        local ex, ev = q[1] - p[1], q[2] - p[2]
        local l = math.max(1e-3, math.sqrt(ex * ex + ev * ev))
        local ou, ov = ev / l, -ex / l
        local x1, y1, z1 = at(p[1], p[2], false)
        local x2, y2, z2 = at(q[1], q[2], false)
        local x3, y3, z3 = at(q[1], q[2], true)
        local x4, y4, z4 = at(p[1], p[2], true)
        local a = vert(s, x1, y1, z1, ov, 0.0, ou, HAIR)
        local b = vert(s, x2, y2, z2, ov, 0.0, ou, HAIR)
        local c = vert(s, x3, y3, z3, ov, 0.0, ou, HAIR)
        local d = vert(s, x4, y4, z4, ov, 0.0, ou, HAIR)
        tri(s, a, b, c)
        tri(s, a, c, d)
    end
    return both(s)
end

-- the cap's crown: a point of it at round-the-head angle ph (0 forward, + to his left) and height angle e, its normal
local function cap_b(ph)                -- (its forward radius at ph: BF in front, BB behind)
    local C = M.CAP
    return (C.BF + C.BB) * 0.5 + (C.BF - C.BB) * 0.5 * math.cos(ph)
end
-- (how far out from the middle at height angle e: fuller than an egg's above the middle)
local function cap_h(e)
    local c = math.max(0.0, math.cos(e))
    return (e > 0.0) and c ^ M.CAP.SH or c
end
-- (k: the radii's scale - the hair under it is a little smaller)
local rim_e
local function cap_point(ph, e, k)
    local C, B = M.CAP, M.BAND
    k = k or 1.0
    local h = cap_h(e) * k
    local x, y, z = C.X + C.A * k * math.sin(e), C.Y + cap_b(ph) * h * math.cos(ph), C.C * h * math.sin(ph)
    -- (near its edge, drawn in to the band round his head)
    local hgt = B.H + (B.HB - B.H) * (0.5 - 0.5 * math.cos(ph))
    local w = 1.0 - (x - (C.X + C.A * math.sin(rim_e(ph)))) / hgt
    if w > 0.0 then
        w = math.min(1.0, w)
        w = w * w * (3.0 - 2.0 * w)
        local bb = (B.BF + B.BB) * 0.5 + (B.BF - B.BB) * 0.5 * math.cos(ph)
        y = y + (C.Y + bb * k * math.cos(ph) - y) * w
        z = z + (B.C * k * math.sin(ph) - z) * w
    end
    return x, y, z
end
local function crown_at(ph, e, k)
    local x, y, z = cap_point(ph, e, k)
    -- (its normal from two small steps along it)
    local d = 0.01
    local x1, y1, z1 = cap_point(ph + d, e, k)
    local x2, y2, z2 = cap_point(ph, e + d, k)
    local ax, ay, az = x1 - x, y1 - y, z1 - z
    local bx, by, bz = x2 - x, y2 - y, z2 - z
    local nx, ny, nz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
    local l = math.sqrt(nx * nx + ny * ny + nz * nz)
    if l < 1e-6 then return x, y, z, 1.0, 0.0, 0.0 end
    nx, ny, nz = nx / l, ny / l, nz / l
    if nx * (x - M.CAP.X) + ny * (y - M.CAP.Y) + nz * z < 0.0 then nx, ny, nz = -nx, -ny, -nz end
    return x, y, z, nx, ny, nz
end
-- the height angle of its bottom edge at ph (on the slope from FRONT to BACK; found by going round a few times)
function rim_e(ph)
    local C = M.CAP
    local slope = (C.FRONT - C.BACK) / (C.BF + C.BB)
    local x = (C.FRONT + C.BACK) * 0.5
    for _ = 1, 6 do
        local k = math.max(-0.999, math.min(0.999, (x - C.X) / C.A))
        local y = cap_b(ph) * cap_h(math.asin(k)) * math.cos(ph)
        x = C.FRONT + slope * (y - C.BF)
    end
    return math.asin(math.max(-0.999, math.min(0.999, (x - C.X) / C.A)))
end

-- where the crown starts at ph: its edge, or higher at the back, round the opening's arch
local function gap_e(ph)
    local C, G = M.CAP, M.BACK_GAP
    local e = rim_e(ph)
    local d = math.abs(math.atan(math.sin(ph - math.pi), math.cos(ph - math.pi)))
    if d >= G.W then return e end
    local x = C.X + C.A * math.sin(e) + G.H * math.sqrt(1.0 - (d / G.W) ^ 2)
    return math.asin(math.max(-0.999, math.min(0.999, (x - C.X) / C.A)))
end

-- Mario's dark hair under the cap's edge, round the back and sides (sideburns in front of the ears, cut short over them)
local function hairline_x(ph)
    local a = math.abs(math.deg(ph))
    local H = M.HAIRLINE
    for i = 1, #H - 1 do
        local p, q = H[i], H[i + 1]
        if a <= q[1] then
            local t = (a - p[1]) / (q[1] - p[1])
            t = t * t * (3.0 - 2.0 * t)                -- (eased between the points: no corners - "kinda blocky")
            local x = p[2] + (q[2] - p[2]) * t
            -- (tufts hanging at the back: pointed scallops, as Mario's hair under his cap)
            if a > M.TUFTS.FROM and x < 50 then
                local k = math.min(1.0, (a - M.TUFTS.FROM) / 12.0)
                local b = math.cos(ph * M.TUFTS.N * 0.5)
                x = x - M.TUFTS.LEN * k * (b * b) ^ 3
            end
            return x
        end
    end
    return H[#H][2]
end
-- (a strand's shade, the same for a column of the hair: lighter and darker streaks)
local function streak(g)
    local v = math.sin(g * 12.9898) * 43758.5453
    v = v - math.floor(v)
    return 0.78 + 0.4 * v
end
local function hair_section()
    local s = section(5)
    local C = M.CAP
    -- (it hugs his head more the lower it goes - standing off it all the way down it "looks like a helmet")
    local COLS, ROWS, K, K_LOW = 240, 8, 0.985, 0.915
    local rows = {}
    for g = 0, COLS do
        local ph = -math.pi + 2.0 * math.pi * g / COLS
        local sh = streak(g % COLS)
        local hc = { HAIR[1] * sh, HAIR[2] * sh, HAIR[3] * sh }
        local e_top = gap_e(ph) + 0.08              -- (up under the cap, and filling the opening at the back)
        local rim_x = C.X + C.A * math.sin(rim_e(ph))
        local bx = math.min(hairline_x(ph), rim_x)
        local e_bot = math.asin(math.max(-0.999, math.min(0.999, (bx - C.X) / (C.A * K_LOW))))
        if e_bot > e_top then e_bot = e_top end
        local col = {}
        for r = 0, ROWS do
            local t = r / ROWS
            local e = e_top + (e_bot - e_top) * t
            local x, y, z, nx, ny, nz = crown_at(ph, e, K + (K_LOW - K) * t * t)
            local d = 1.0 - 0.25 * t           -- (a little darker toward its ends)
            col[r] = vert(s, x, y, z, nx, ny, nz, { hc[1] * d, hc[2] * d, hc[3] * d })
        end
        -- (just in under its lower edge, toward his head: no air showing under it)
        local x, y, z = crown_at(ph, e_bot, K_LOW)
        col[ROWS + 1] = vert(s, x + 0.15, C.Y + (y - C.Y) * 0.93, z * 0.93, 0, 0, 0, { hc[1] * 0.6, hc[2] * 0.6, hc[3] * 0.6 })
        rows[g] = col
    end
    for g = 0, COLS - 1 do
        for r = 0, ROWS do
            local p, q = rows[g][r], rows[g][r + 1]
            local p2, q2 = rows[g + 1][r], rows[g + 1][r + 1]
            tri(s, p, q, p2); tri(s, p2, q, q2)
        end
    end
    return both(s)
end

-- the crown in six panels (a darker stitch line between them) and the button on top
local function crown_section()
    local s = section(2)
    local RINGS = 16
    local angles, seam = {}, {}
    for p = 0, 5 do
        local b = p * math.pi / 3.0
        if p > 0 then angles[#angles + 1] = b - 0.02 end
        angles[#angles + 1] = b; seam[#angles] = true
        angles[#angles + 1] = b + 0.02
        for k = 1, 9 do angles[#angles + 1] = b + (k / 10.0) * math.pi / 3.0 end
    end
    angles[#angles + 1] = 2.0 * math.pi - 0.02
    angles[#angles + 1] = 2.0 * math.pi; seam[#angles] = true
    local cols = #angles
    local dark = { RED[1] * 0.55, RED[2] * 0.55, RED[3] * 0.55 }
    for r = 0, RINGS do
        for g = 1, cols do
            local ph = angles[g]
            local e0 = gap_e(ph)
            local e = e0 + (math.pi * 0.5 - e0) * (r / RINGS) ^ 0.9
            local x, y, z, nx, ny, nz = crown_at(ph, e)
            vert(s, x, y, z, nx, ny, nz, (seam[g] and r < RINGS) and dark or RED)
        end
    end
    for r = 0, RINGS - 1 do
        for g = 0, cols - 2 do
            local p = r * cols + g
            local q = p + cols
            tri(s, p, q, p + 1)
            tri(s, p + 1, q, q + 1)
        end
    end
    -- its band inside the bottom edge, in toward his head (wherever the head is narrower than the cap, it shows this
    -- and not the air under the cap)
    local C = M.CAP
    local band = s.nverts
    for g = 1, cols do
        local ph = angles[g]
        local x, y, z = crown_at(ph, rim_e(ph))
        vert(s, x, y, z, -1, 0, 0, dark)
        vert(s, x + 0.6, C.Y + (y - C.Y) * 0.72, z * 0.72, -1, 0, 0, dark)
    end
    for g = 0, cols - 2 do
        local a, b = band + g * 2, band + g * 2 + 2
        tri(s, a, b, a + 1); tri(s, a + 1, b, b + 1)
    end
    -- the button
    local bx = C.X + C.A - 0.1
    local base = s.nverts
    local BR, BS = 4, 10
    for r = 0, BR do
        local th = (math.pi * 0.5) * r / BR
        for g = 0, BS do
            local ph = 2.0 * math.pi * g / BS
            local a, b, c = math.cos(th), math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph)
            vert(s, bx + a * 0.6, C.Y + 0.4 + b * 0.9, c * 0.9, a, b, c, RED)
        end
    end
    for r = 0, BR - 1 do
        for g = 0, BS - 1 do
            local p = base + r * (BS + 1) + g
            local q = p + BS + 1
            tri(s, p, q, p + 1)
            tri(s, p + 1, q, q + 1)
        end
    end
    return both(s)
end

-- the brim: from the crown's front edge out forward, tipped down a little, its sides curving down
-- the strap across the bottom of the opening at the back, red, its snaps' holes in a row, white
local function strap_section()
    local s = section(6)
    local C, G = M.CAP, M.BACK_GAP
    local BLACK, SNAP = RED, WHITE           -- (red, its holes white: the user, 2026-10-16)
    local N, W = 16, G.W + 0.06
    local function at(ph, up, k)              -- (up: cm over the cap's edge at ph)
        local e = rim_e(ph)
        local x = C.X + C.A * math.sin(e) + up
        local e2 = math.asin(math.max(-0.999, math.min(0.999, (x - C.X) / C.A)))
        return crown_at(ph, e2, k)
    end
    local top, bot = {}, {}
    for i = 0, N do
        local ph = math.pi - W + 2.0 * W * i / N
        local x, y, z, nx, ny, nz = at(ph, -0.1, 1.012)
        bot[i] = vert(s, x, y, z, nx, ny, nz, BLACK)
        x, y, z, nx, ny, nz = at(ph, G.STRAP, 1.012)
        top[i] = vert(s, x, y, z, nx, ny, nz, BLACK)
    end
    for i = 0, N - 1 do
        tri(s, bot[i], top[i], bot[i + 1]); tri(s, bot[i + 1], top[i], top[i + 1])
    end
    -- (the snaps: small round holes along its middle)
    for k = 1, G.SNAPS do
        local ph = math.pi - G.W * 0.8 + 1.6 * G.W * (k - 1) / (G.SNAPS - 1)
        -- (a little disc just out from the strap's face, along its normal - drawn in round his head with the band, the
        -- holes at a bigger scale than the strap sank into it: "the white dots are missing")
        local cx, cy, cz, nx, ny, nz = at(ph, G.STRAP * 0.5, 1.012)
        cx, cy, cz = cx + nx * 0.15, cy + ny * 0.15, cz + nz * 0.15
        -- (two directions along it, up and round)
        local ux, uy, uz = at(ph, G.STRAP * 0.5 + 0.1, 1.012)
        local rx, ry, rz = at(ph + 0.01, G.STRAP * 0.5, 1.012)
        ux, uy, uz = ux + nx * 0.15, uy + ny * 0.15, uz + nz * 0.15
        rx, ry, rz = rx + nx * 0.15, ry + ny * 0.15, rz + nz * 0.15
        local ax, ay, az = ux - cx, uy - cy, uz - cz
        local bx, by, bz = rx - cx, ry - cy, rz - cz
        local la, lb = math.sqrt(ax * ax + ay * ay + az * az), math.sqrt(bx * bx + by * by + bz * bz)
        ax, ay, az, bx, by, bz = ax / la, ay / la, az / la, bx / lb, by / lb, bz / lb
        local mid = vert(s, cx, cy, cz, nx, ny, nz, SNAP)
        local ring = {}
        for g = 0, 7 do
            local a = 2.0 * math.pi * g / 8
            local r = 0.28
            ring[g] = vert(s, cx + (ax * math.cos(a) + bx * math.sin(a)) * r, cy + (ay * math.cos(a) + by * math.sin(a)) * r,
                           cz + (az * math.cos(a) + bz * math.sin(a)) * r, nx, ny, nz, SNAP)
        end
        for g = 0, 7 do tri(s, mid, ring[g], ring[(g + 1) % 8]) end
    end
    return both(s)
end

local function brim_section()
    local s = section(3)
    local C = M.CAP
    local N, SPAN, TH = 24, math.rad(72.0), 0.45
    local under = { RED[1] * 0.55, RED[2] * 0.55, RED[3] * 0.55 }
    local top, bot = {}, {}
    for i = 0, N do
        local ph = -SPAN + 2.0 * SPAN * i / N
        local x, y, z = crown_at(ph, rim_e(ph))
        local f = math.cos(ph * (math.pi * 0.5) / (SPAN * 1.04))
        local L = C.BRIM * math.max(0.0, f) ^ 0.6
        local dy, dz = math.cos(ph) + 0.9, math.sin(ph)
        local dl = math.sqrt(dy * dy + dz * dz)
        dy, dz = dy / dl, dz / dl
        local sx = math.sin(ph)
        local ox = x - L * C.DROOP - 1.6 * sx * sx * (L / C.BRIM)
        local oy, oz = y + dy * L, z + dz * L
        -- (in, out) on top; the same a little lower underneath
        top[#top + 1] = { vert(s, x + 0.05, y, z, 1, 0.1, 0, RED), vert(s, ox, oy, oz, 1, 0.1, 0, RED) }
        bot[#bot + 1] = { vert(s, x - TH, y - 0.2, z, -1, 0, 0, under), vert(s, ox - TH, oy, oz, -1, 0, 0, under) }
    end
    for i = 1, N do
        local a, b = top[i], top[i + 1]
        tri(s, a[1], a[2], b[1]); tri(s, b[1], a[2], b[2])
        a, b = bot[i], bot[i + 1]
        tri(s, a[1], b[1], a[2]); tri(s, b[1], b[2], a[2])
        -- (its front edge)
        tri(s, top[i][2], bot[i][2], top[i + 1][2]); tri(s, top[i + 1][2], bot[i][2], bot[i + 1][2])
    end
    return both(s)
end

-- the white badge with the red M on the crown's front: Mario 64's own cap emblem picture on a round patch of the
-- crown just out from it (only its round disc: the see-through material drew it black)
local function badge_section()
    local s = section(4)
    s.texture = BADGE_TEX
    local C, B = M.CAP, M.BADGE
    local e0 = math.asin((B.UP - C.X) / C.A)
    local dph = B.R / (cap_b(0.0) * math.cos(e0))
    local de = B.R / math.sqrt((C.A * math.cos(e0)) ^ 2 + (cap_b(0.0) * math.sin(e0)) ^ 2)
    local RINGS, SEGS, DISC = 5, 24, 0.46            -- (DISC: the disc's radius in the picture, 0..1 across)
    local function at(r, a)
        local u, v = r * math.cos(a), r * math.sin(a)  -- (u to the right as seen from in front, v up)
        local x, y, z, nx, ny, nz = crown_at(u * dph, e0 + v * de)
        local n = vert(s, x + nx * 0.1, y + ny * 0.1, z + nz * 0.1, nx, ny, nz, WHITE)
        s.col[n * 4 + 1], s.col[n * 4 + 2], s.col[n * 4 + 3] = 1.0, 1.0, 1.0
        s.uv[n * 2 + 1], s.uv[n * 2 + 2] = 0.5 + u * DISC, 0.5 - v * DISC
        return n
    end
    local mid = at(0.0, 0.0)
    local rows = {}
    for r = 1, RINGS do
        rows[r] = {}
        for g = 0, SEGS do rows[r][g] = at(r / RINGS, 2.0 * math.pi * g / SEGS) end
    end
    for g = 0, SEGS - 1 do tri(s, mid, rows[1][g + 1], rows[1][g]) end
    for r = 1, RINGS - 1 do
        for g = 0, SEGS - 1 do
            local p, q = rows[r][g], rows[r + 1][g]
            tri(s, p, rows[r][g + 1], q); tri(s, rows[r][g + 1], rows[r + 1][g + 1], q)
        end
    end
    return both(s)
end

-- his own hair (hidden under the cap, shown again when the look comes off) - or another of his grooms by name
local function hair_comp(pawn, name)
    local hg = nil
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/HairStrandsCore.GroomComponent"))) do
            local o = c:get()
            if o:GetFName():ToString() == (name or "HairGroom") then hg = o end
        end
    end)
    return hg
end

local function head_comp(pawn)
    local head = nil
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.SkeletalMeshComponent"))) do
            local o = c:get()
            if o:GetFName():ToString() == "Head" then head = o end
        end
    end)
    return head
end

-- (body: the figure's skeletal mesh with the "head" socket - the athlete's Mesh, STORROR's menu mannequin's Body)
local function on_head(world, body, build)
    local a = lib.spawn_actor(world, body:K2_GetComponentLocation(), 0.0)
    if not a then return nil end
    pcall(function() a:SetActorEnableCollision(false) end)
    local pmc = lib.add_pmc(a)
    local specs = {}
    if pmc then
        pcall(function() pmc:SetCollisionEnabled(0) end)
        -- (whenever the sun casts shadows - real-time shadows on, part of his own: lib.lit_on)
        pcall(function() pmc:SetCastShadow(true) end)
        local secs = build()
        lib.add_sections(world, pmc, secs)
        for _, sec in ipairs(secs) do specs[#specs + 1] = { id = sec.id, layer = sec.layer, texture = sec.texture, sec = sec } end
    end
    lib.keep[a:GetAddress()] = "mario look"
    a:K2_AttachToComponent(body, FName("head"), 0, 0, 0, false)
    pcall(function()
        a.RootComponent.RelativeLocation = { X = 0.0, Y = 0.0, Z = 0.0 }
        a.RootComponent.RelativeRotation = { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }
        a.RootComponent:SetRelativeScale3D({ X = 1.0, Y = 1.0, Z = 1.0 })
    end)
    return a, pmc, specs
end

-- the look on a figure (actor, its body): returned as a record for take_off
local function put_on(world, actor, body, leave_hair)
    use_char(M.CHAR)
    local l = { actors = {}, pmcs = {}, eyes = {}, pawn = actor:GetAddress(), world = world:GetAddress(), char = M.CHAR }
    -- his own hair hidden (never a hair asset swapped: putting his own back crashed the game, 2026-10-16)
    local hg = (not leave_hair) and (not M.OWN_HAIR) and hair_comp(actor)
    if hg then
        pcall(function() if not hg.bHiddenInGame then hg:SetHiddenInGame(true, false) end end)
        l.hair = { comp = hg, hidden = true }
    end
    -- his own beard hidden: Mario has none. Close up it is strands, so fine they all but vanished; further off STORROR
    -- draws the groom's simpler stand-in instead, a full beard - "marios beard ... when zooming the camera out it shows
    -- but when zooming in it disappears", 2026-10-29. (His brows and his own mustache stay, under Mario's.)
    local bg = hair_comp(actor, "BeardGroom")
    if bg then
        pcall(function() if not bg.bHiddenInGame then bg:SetHiddenInGame(true, false); l.beard = bg end end)
    end
    -- his own hair shorter, to stay under the cap
    if M.OWN_HAIR and not leave_hair then
        local hgt = hair_comp(actor)
        if hgt then
            pcall(function() hgt:SetHairLengthScaleEnable(true); hgt:SetHairLengthScale(M.HAIR_LENGTH) end)
            l.trim = hgt
        end
    end
    -- the cap, the nose and the mustache
    local f, pmc, specs = on_head(world, body, function()
        local list = { nose_section(), stache_section(), crown_section(), brim_section(), badge_section(), strap_section() }
        if M.FAKE_HAIR then list[#list + 1] = hair_section() end
        return list
    end)
    if f then l.actors[#l.actors + 1] = f end
    if pmc then l.pmcs[#l.pmcs + 1] = { pmc = pmc, specs = specs } end
    -- the eyes blue (not on the menu's mannequin: one change fewer on a figure STORROR hides and throws away)
    local head = (not leave_hair) and head_comp(actor)
    if head then
        for _, slot in ipairs({ 3, 4 }) do
            pcall(function()
                local mat = head:GetMaterial(slot)
                local mid = head:CreateDynamicMaterialInstance(slot, mat, FName("None"))
                if mid and mid:IsValid() then
                    mid:SetVectorParameterValue(FName("IrisBleedTint"), { R = M.IRIS.R, G = M.IRIS.G, B = M.IRIS.B, A = 1.0 })
                    l.eyes[#l.eyes + 1] = { comp = head, slot = slot, mat = mat, mid = mid:GetFName():ToString() }
                end
            end)
        end
    end
    return l
end

-- (keep_hair: the hair left hidden - a re-fit straight after; showing and hiding a hair in one frame is the
-- likeliest cause of a crash on 2026-10-16 21:54)
local function take_off(l, keep_hair)
    if not (l and lib.world() and lib.world():GetAddress() == l.world) then return end
    for _, a in ipairs(l.actors) do
        pcall(function() lib.keep[a:GetAddress()] = nil end)
        lib.destroy(a)
    end
    -- (the eye's own material put back only while ours is still on it - ours holds it as its parent. Once STORROR has
    -- changed the face, the old one may be gone: putting a gone material on crashed the game, 2026-10-16 22:25)
    for _, e in ipairs(l.eyes) do
        pcall(function()
            local cur = e.comp:GetMaterial(e.slot)
            if cur and cur:GetFName():ToString() == e.mid then e.comp:SetMaterial(e.slot, e.mat) end
        end)
    end
    if l.trim and not keep_hair then
        pcall(function() l.trim:SetHairLengthScale(1.0); l.trim:SetHairLengthScaleEnable(false) end)
    end
    local h = l.hair
    if h and h.hidden and not keep_hair and h.comp:IsValid() then
        pcall(function() h.comp:SetHiddenInGame(false, false) end)
    end
    if l.beard then pcall(function() if l.beard:IsValid() then l.beard:SetHiddenInGame(false, false) end end) end
end

function M.remove(keep_hair)
    local l = look
    look = nil
    take_off(l, keep_hair)
end

-- His hair shown again, by itself, before anything else changes (a face button going down, before STORROR swaps the
-- face: shown after a swap made while it was hidden, the game crashed - 2026-10-16 22:09, and likely 21:54)
local function face_now()
    -- (while STORROR's menu is up, the face he shows is the one charhold.lua holds, not the one its cursor rests on)
    local CH = package.loaded["charhold"]
    local hf = CH and CH.face and CH.face()
    if hf then return hf end
    local f = nil
    pcall(function() f = lib.pawn().PlayerState.PlayerModel.RepCharacterEditorData.SelectedCharacter:ToString() end)
    return f
end
function M.show_hair()
    local l = look
    if not (l and l.hair and l.hair.hidden and lib.world() and lib.world():GetAddress() == l.world) then return end
    -- (the face changed while it was hidden: never shown again on this look - shown after such a swap, the game crashed;
    -- it is hidden in the menu now outside CHARACTER, 2026-11-01)
    local f = face_now()
    if l.hair.face and f and f ~= l.hair.face then
        if not l.hair.kept then l.hair.kept = true; log("mario look: his hair kept hidden - the face changed under it") end
        return
    end
    l.hair.hidden = false
    if l.hair.comp:IsValid() then pcall(function() l.hair.comp:SetHiddenInGame(false, false) end) end
end
-- (never while his cap is off him - taken, blown off - and no power-up cap on: his hair is what is on his head then.
-- charpick.lua hid it again each frame after mariocap.lua showed it: "also marios bald lmao", 2026-10-23)
function M.hide_hair()
    local MC = package.loaded["mariocap"]
    if MC and MC.on_head and not MC.on_head() then
        local C = package.loaded["caps"]
        if not (C and C.on and C.on()) then return end
    end
    local l = look
    if not (l and l.hair and not l.hair.hidden and lib.world() and lib.world():GetAddress() == l.world) then return end
    l.hair.hidden = true
    l.hair.face = face_now()
    if l.hair.comp:IsValid() then pcall(function() l.hair.comp:SetHiddenInGame(true, false) end) end
end
function M.hair_hidden() return look and look.hair and look.hair.hidden end

-- Mario's cap taken off him (mariocap.lua): its pieces - the crown, the brim, the badge with the M and the strap,
-- sections 2, 3, 4 and 6 of the look - hidden, and his own hair shown in its place; and back
local CAP_SECTIONS = { 2, 3, 4, 6 }
M.CAP_SECTIONS = CAP_SECTIONS       -- (for the mirror's copy of the look: mirror.lua sync_cap)
function M.show_cap(on)
    local l = look
    if not (l and lib.world() and lib.world():GetAddress() == l.world) then return end
    for _, p in ipairs(l.pmcs) do
        for _, id in ipairs(CAP_SECTIONS) do pcall(function() p.pmc:SetMeshSectionVisible(id, on) end) end
    end
    if on then M.hide_hair() else M.show_hair() end
end

-- First person (STORROR's view from his eyes: it hides his own head and hair): the cap, nose and mustache hidden with
-- them, every frame it is so - they sat in the camera ("marios hat nose and stash is in the camera of first person mode",
-- 2026-10-21). Told by his head hidden and the camera at it.
function M.view_tick()
    local l = look
    if not l then return end
    local pawn = lib.pawn()
    if not (pawn and pawn:GetAddress() == l.pawn and lib.world() and lib.world():GetAddress() == l.world) then return end
    local fp = false
    -- (fp.lua's own word when it has one: by the camera's distance from his head the cap and nose flickered into view
    -- as he slid, 2026-10-22)
    local FPV = package.loaded["fp"]
    if type(FPV) == "table" and FPV.on then
        local ok, on = pcall(FPV.on)
        fp = ok and on == true
    else pcall(function()
        if not (l.head_c and l.head_c:IsValid()) then l.head_c = head_comp(pawn) end
        local head = l.head_c
        if head and head.bHiddenInGame then
            local cam = lib.controller().PlayerCameraManager:GetCameraLocation()
            local hs = pawn.Mesh:GetSocketLocation(FName("head"))
            -- (within 100 cm: sliding, fp.lua's eyes sit over the middle of him, up to 60 cm from his swinging head)
            fp = (cam.X - hs.X) ^ 2 + (cam.Y - hs.Y) ^ 2 + (cam.Z - hs.Z) ^ 2 < 100.0 * 100.0
        end
    end) end
    if fp ~= (l.fp or false) then
        l.fp = fp
        for _, a in ipairs(l.actors) do pcall(function() a:SetActorHiddenInGame(fp) end) end
        log("mario look: %s (first person %s)", fp and "hidden" or "shown", tostring(fp))
    end
end

function M.on() return look ~= nil end
-- (the character the look on him is: mario, luigi, wario, waluigi)
function M.char() return look and look.char or nil end
-- (the pawn and map it is on; and forgetting it untouched when its map has gone - nothing of a gone map is touched)
function M.pawn_addr() return look and look.pawn end
function M.world_addr() return look and look.world end
function M.forget() look = nil end

-- His cap, nose and mustache all in one material `mid` (the Metal Cap's: they stayed red, skin and brown on the metal
-- statue - "make sure all of metal caps textures are grey the hat nose and mustash is still original color",
-- 2026-10-17); nil puts their own back. Their own are the mod's shared ones, made again if gone.
function M.paint(mid)
    local l = look
    local world = lib.world()
    if not (l and world and world:GetAddress() == l.world) then return end
    for _, p in ipairs(l.pmcs or {}) do
        for _, sp in ipairs(p.specs) do
            pcall(function()
                -- (their colours are their corners' - the red cap, the nose's skin, the brown mustache - which our
                -- materials multiply in: under the metal cap the pieces are made again white, and back in their
                -- colours after - "fix his nose hat and mustash please", 2026-10-18)
                if sp.sec then
                    local sec = sp.sec
                    if mid then
                        local w = {}
                        for k, v in pairs(sec) do w[k] = v end
                        local col = {}
                        for i = 1, #(sec.col or {}) do col[i] = 1.0 end
                        w.col = col
                        lib.add_sections(world, p.pmc, { w })
                    else
                        lib.add_sections(world, p.pmc, { sec })
                    end
                end
                local m = mid
                if not m then
                    local tex = sp.texture and lib.clamp_file(sp.texture)
                    m = lib.get_mid(world, sp.layer, tex)
                end
                if m then p.pmc:SetMaterial(sp.id, m) end
            end)
        end
    end
    l.painted = mid ~= nil
    l.chrome_list = nil                -- (painted or not anew: every section redone at its next turn - chrome_tick)
end

-- Mario 64's chrome on his cap, nose and mustache under the metal cap ("make it like mario 64's chrome", 2026-10-18):
-- its metal picture laid on by where each corner faces as the camera sees it - G_TEXTURE_GEN, the view's x and y of
-- the corner's normal - and laid again 15 times a second, so it slides over them as they and the camera turn, as on
-- Metal Mario (lib.chrome). (His body's meshes are skinned on the card: no such thing can be done to them.)
local CHROME_TEX = "actors__mario__mario_metal.rgba16"
-- (2026-11-01, "next we have to do major optimization": every section redone 15 times a second was 2 ms a frame on
-- average and an 8 ms hitch every fourth frame. Now two sections a tick, in turn, and one only redone when the camera or
-- the piece has turned since it last was - standing still, nothing is.)
local CHROME_PER_TICK = 2
local CHROME_TURN = 0.0004             -- (1 - the quaternion dot: about 3 degrees)
local function turned(a, b)
    if not a then return true end
    local d = a.X * b.X + a.Y * b.Y + a.Z * b.Z + a.W * b.W
    return 1.0 - math.abs(d) > CHROME_TURN
end
function M.chrome_tick(dt)
    local l = look
    local world = lib.world()
    if not (l and l.painted and world and world:GetAddress() == l.world) then return end
    local mid = lib.get_mid(world, "opaque", CHROME_TEX)
    if not mid then return end
    if not l.chrome_list then
        l.chrome_list = {}
        for _, p in ipairs(l.pmcs or {}) do
            for _, sp in ipairs(p.specs) do
                if sp.sec then l.chrome_list[#l.chrome_list + 1] = { pmc = p.pmc, sec = sp.sec } end
            end
        end
    end
    local list = l.chrome_list
    if #list == 0 then return end
    local cam = nil
    pcall(function()
        local r = lib.controller().PlayerCameraManager:GetCameraRotation()
        cam = { P = r.Pitch, Y = r.Yaw, R = r.Roll }
    end)
    if not cam then return end
    local done, tries = 0, 0
    while done < CHROME_PER_TICK and tries < #list do
        tries = tries + 1
        l.chrome_i = (l.chrome_i or 0) % #list + 1
        local e = list[l.chrome_i]
        local q = nil
        pcall(function() local r = e.pmc:K2_GetComponentToWorld().Rotation; q = { X = r.X, Y = r.Y, Z = r.Z, W = r.W } end)
        if q then
            local cmoved = not e.cam or math.abs(e.cam.P - cam.P) + math.abs((e.cam.Y - cam.Y + 540) % 360 - 180)
                + math.abs(e.cam.R - cam.R) > 2.0
            if cmoved or turned(e.q, q) then
                pcall(lib.chrome, world, e.pmc, e.sec, mid)
                e.cam, e.q = cam, q
                done = done + 1
            end
        end
    end
end

-- His look's pieces all laid in `mid`, once - caps.lua's RAINBOW skin: its liquid on the cap, nose and mustache, which
-- have no layout of their own for a picture. Laid by where each corner is, seen along the slant (1, 1, 1): no face lies
-- along it, so none gets the picture's one spot - laid by where they faced (lib.chrome), the flat brim was one colour,
-- "the hat brim is not showing the texture correctly", 2026-11-04. `per`: cm a repeat of the picture.
M.LAY_PER = 22.0
function M.lay_all(mid, per)
    local l = look
    local world = lib.world()
    if not (l and mid and world and world:GetAddress() == l.world) then return end
    local k = 1.0 / (per or M.LAY_PER)
    for _, p in ipairs(l.pmcs or {}) do
        for _, sp in ipairs(p.specs or {}) do
            local sec = sp.sec
            if sec and sec.pos and #sec.pos > 0 then
                pcall(function()
                    local w = {}
                    for key, v in pairs(sec) do w[key] = v end
                    local uv, col, P = {}, {}, sec.pos
                    for i = 0, #P // 3 - 1 do
                        local x, y, z = P[i * 3 + 1], P[i * 3 + 2], P[i * 3 + 3]
                        uv[i * 2 + 1] = (x - y) * 0.7071 * k
                        uv[i * 2 + 2] = (x + y - 2.0 * z) * 0.4082 * k
                        col[i * 4 + 1], col[i * 4 + 2], col[i * 4 + 3], col[i * 4 + 4] = 1.0, 1.0, 1.0, 1.0
                    end
                    w.uv, w.col = uv, col
                    lib.add_sections(world, p.pmc, { w })
                    p.pmc:SetMaterial(sec.id, mid)
                end)
            end
        end
    end
end

-- (his cap's mesh, for the Vanish Cap's flicker)
function M.pmcs()
    local out, l = {}, look
    for _, p in ipairs((l and l.pmcs) or {}) do out[#out + 1] = p.pmc end
    return out
end

function M.apply()
    M.remove(true)
    local world, pawn = lib.world(), lib.pawn()
    if not (world and pawn) then return false end
    look = put_on(world, pawn, pawn.Mesh)
    log("mario look: on (%d pieces, %d eyes)", #look.actors, #look.eyes)
    return true
end

-- Other figures: STORROR's menu mannequin (PlayerMannequinBP_C, its body "Body") - the CHARACTER screen shows it,
-- not the athlete. By the figure's address; a gone map's are forgotten untouched.
local extras = {}
-- (and the menu figures' looks with his own: M.forget)
local forget_own = M.forget
function M.forget() forget_own(); extras = {} end
-- (`own`: who dressed it - the race's racer, race.lua - left off M.dressed_list, which charpick.lua goes through
-- taking the look off all but its menu's figure: the racer's cap came off as soon as it went on, 2026-10-27)
function M.dress(actor, body, own)
    local world = lib.world()
    if not (world and actor and body) then return false end
    local a = actor:GetAddress()
    if extras[a] and extras[a].world == world:GetAddress() then return true end
    extras[a] = put_on(world, actor, body, true)    -- (its hair left alone: one hair fewer shown and hidden)
    extras[a].own = own
    log("mario look: on the menu's figure (%d pieces)", #extras[a].actors)
    return true
end
-- another figure's look painted as M.paint paints his (the race's metal racer, race.lua): its pieces white under `mid`
function M.paint_dressed(addr, mid)
    local l = extras[addr]
    local world = lib.world()
    if not (l and world and world:GetAddress() == l.world and mid) then return false end
    for _, p in ipairs(l.pmcs or {}) do
        for _, sp in ipairs(p.specs) do
            pcall(function()
                if sp.sec then
                    local w = {}
                    for k, v in pairs(sp.sec) do w[k] = v end
                    local col = {}
                    for i = 1, #(sp.sec.col or {}) do col[i] = 1.0 end
                    w.col = col
                    lib.add_sections(world, p.pmc, { w })
                end
                p.pmc:SetMaterial(sp.id, mid)
            end)
        end
    end
    return true
end
function M.undress(addr)
    local l = extras[addr]
    extras[addr] = nil
    take_off(l, false)
end
function M.dressed(addr)
    local l = extras[addr]
    local w = lib.world()
    if l and not (w and w:GetAddress() == l.world) then extras[addr] = nil; return false end
    return l ~= nil
end
function M.dressed_list()
    local out = {}
    for a, l in pairs(extras) do if not l.own then out[#out + 1] = a end end
    return out
end
-- a dressed figure's pieces (their meshes and sections): { { pmc, specs }, ... }
function M.dressed_pieces(addr)
    local l = extras[addr]
    return l and l.pmcs or {}
end

return M
