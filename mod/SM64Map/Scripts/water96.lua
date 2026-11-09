-- water96.lua: RENDER 96's water made to look and move like real water ("no you gotta make it behave like real water
-- is what im saying", 2026-10-31).
-- Unreal's own water (the Water plugin: lakes, oceans, a water zone, Gerstner waves) is in the game, but it can't be made
-- while the game runs: its water-info material is not shipped, and a lake made then never joins a zone (tried in Jolly
-- Roger Bay: nothing drawn). So it is done here, on the mod's own water boxes:
--  * the look: the glTF transmission material - Unreal's thin-translucent shading, lit per pixel with screen-space
--    reflections: the cliffs, posts and sky mirrored in it, the sun glinting, what is under it seen through, tinted.
--    (The glTF blend material, tried first, is lit the cheap way - no reflections at all: drawn black and solid it
--    showed nothing of the sky.) Its colour water96_tint and ripple normal map water96_normal (tools/r96_water.py;
--    water96_normal_s the same stored for the colour import - tools/normal_srgb.py), the two drifting different ways
--    (the material's own texture offsets - free); the sky's light from sunsky.lua's sky light, under a daytime sky
--  * waves: round Mario a grid of points, finer near him, moved every other frame by a few Gerstner waves (rounded
--    troughs, sharper crests, each length at its own speed as on deep water), fading out to the flat water at the
--    grid's edge; the flat water has a hole where the grid is
--  * ripples: rings that run out from where he goes in, swims and wades
--  * he bobs with the waves (game.lua update_swim: M.height)
-- Only the water boxes Mario 64 draws as water (game.lua add_water: G.water_rot entries with `w96`), not its mist or
-- lava. Classic look (RENDER 96 off): untouched.
local M = {}
local sin, cos, sqrt, exp, floor, abs = math.sin, math.cos, math.sqrt, math.exp, math.floor, math.abs

M.PARENT = "/InterchangeAssets/gltf/MaterialInstances/MI_Transmission.MI_Transmission"
M.KINDS = { water = true, jrb = true, unk = true }          -- (Mario 64's water box pictures made real water)
M.TEX, M.NORMAL = "water96_tint", "water96_normal_s"
-- (by the box's picture: `tint` what the light through it is coloured, `through` how much of it gets through - Jolly
-- Roger Bay's sea deeper than a moat)
M.LOOK = {
    water = { tint = { 0.6, 0.85, 0.85 }, through = 0.85 },
    jrb = { tint = { 0.55, 0.8, 0.82 }, through = 0.85 },
    unk = { tint = { 0.6, 0.85, 0.85 }, through = 0.85 },
}
M.ROUGH = 0.03
M.IOR = 1.33
-- (drawn before every other see-through thing: the water shows what is behind it from a picture of the scene taken
-- before any of them are drawn, so drawn after one in front of it - Snowman's Land's ice over its pool - it painted over
-- it and the ice vanished: "ice disappears when theres water behind it", 2026-10-31. The caustics under it first of all)
M.SORT, M.CAUSTIC_SORT = -2, -3
M.REPEAT = 900.0                -- (cm of water a repeat of the colour picture)
-- (the ripple picture carries the water's chop everywhere: 12 m a repeat, its waves 0.5 to 6 m long, sliding at a wave's
-- speed, ~1.2 m/s, and swaying - the grid round him can only draw short waves where its points are close, within ~4 m
-- of him: "the waves stop showing about 12 feet out. so far out I can see the water is stagnant", 2026-11-01. 6.4 m a
-- repeat and 0.4 m/s at first: tiny ripples, crawling - still, from afar)
M.NRM_SCALE = 0.75              -- (the ripple picture this many times as often as the colour one)
M.DRIFT_TEX = { 0.010, 0.004 }  -- (repeats a second each way)
M.DRIFT_NRM = { -0.06, 0.08 }
M.NRM_SWAY = { 0.03, 0.9, 0.025, 0.6 }  -- (and swaying back and forth a little: repeats and radians a second, each way)
M.NRM_STRENGTH = 0.8            -- (not 0: the material's sums break - the whole screen went white)
M.EVERY = 3                     -- (the grid round him moved every this many frames: ~2 ms a time for its 841 points)
-- (then by the clock, not the frame: M.STEP s apart - every 3 frames was 37 times a second at 110 fps, 0.85 ms of
-- every frame, "when I entered the level it was 120 fps now its 80", 2026-11-05)
M.STEP = 1.0 / 24.0
M.MID_STEP = 1.0 / 30.0         -- (its pictures' drift set this often, not every frame: steps of a 400th of a repeat)

-- the waves: { direction (degrees), length (cm), height (cm), sharpness 0..1 }; their speed is deep water's
M.WAVES = {
    { 37.0, 900.0, 9.0, 0.55 },
    { 115.0, 520.0, 5.0, 0.5 },
    { -14.0, 310.0, 2.6, 0.45 },
    { 228.0, 175.0, 1.3, 0.35 },
}
M.GRAVITY = 981.0
-- (how big a scene's waves are: the seas full, ponds and moats less; and never more than its box's size allows)
M.SCALE = { jrb = 1.0, ddd = 1.0, thi = 1.0, thi_2 = 0.7, thi_3 = 0.5, grounds = 0.5, wdw = 0.6, wdw_2 = 0.45,
            bob = 0.45, ccm = 0.35, ccm_2 = 0.35, sl = 0.35, sl_2 = 0.35, hmc = 0.45, ttm = 0.35, castle = 0.25,
            courtyard = 0.25, wf = 0.4 }
M.SCALE_DEFAULT = 0.45
M.BOX_FULL = 3000.0             -- (a box this wide or more gets the full waves; a smaller one less, down to a quarter)

-- the grid round Mario: rings out to RINGS each way, the n-th at STEP1*n + STEP2*n^2 cm (finer near him)
-- (13 m out at first - 10 rings of 30n + 10n^2: "your water wave system is distance based", 2026-11-01 - its edge was
-- seen. Now 27 m, its points further apart further out, and the waves fading over its outer 60%: the long swell
-- carried furthest, the short ones only where the points are close enough to draw them - LOD)
M.RINGS, M.STEP1, M.STEP2 = 14, 35.0, 11.5
M.FADE_FROM = 0.4               -- (the waves full inside this share of the grid, fading to none at its edge)
M.SNAP = 80.0                   -- (the grid moved with him in steps of this)
M.NEAR_Z = 1500.0               -- (only while he is within this of the water's height)

-- the ripples: { length (cm), speed (cm/s), fade a second, life (s) }
M.RIP_LEN, M.RIP_SPEED, M.RIP_DECAY, M.RIP_LIFE, M.RIP_MAX = 150.0, 160.0, 1.1, 3.0, 8
M.RIP_ENTER, M.RIP_SWIM, M.RIP_IDLE, M.RIP_WADE = 14.0, 5.0, 2.2, 3.0

-- RENDER 96's lava ("also the lava", 2026-10-31): solid, lit, glowing - dark crust plates with molten cracks between
-- (tools/r96_water.py lava96_base / lava96_glow), its glow breathing slowly; it still slides as Mario 64's does (the
-- moving textures' own scroll, movtex.lua; a lava box's turn, game.lua). On Mario 64's lava pictures: the moving lava
-- of Lethal Lava Land and Bowser in the Fire Sea (movtex.lua asks M.lava_material) and the volcano's lava box.
M.LAVA_PARENT = "/InterchangeAssets/gltf/M_Default.M_Default"
M.LAVA_TEX, M.LAVA_GLOW = "lava96_base", "lava96_glow"
M.LAVA_PICTURE = "movtex_texture_waterbox_lava"
M.LAVA_HEAT = { 1.0, 0.62, 0.32 }       -- (the glow's colour)
M.LAVA_STRENGTH = 7.0                   -- (how bright: over 1 it blooms)
M.LAVA_PULSE = { 0.14, 0.7, 0.07, 2.1 }  -- (two slow swells in the glow: share, radians a second, share, radians a second)
M.LAVA_SCALE = 2.2                      -- (its picture this many times as often as Mario 64's: at 0.5 one plate was
                                        -- metres across, the cracks thin lines on brown)
M.LAVA_CRUST = { 0.24, 0.19, 0.18 }     -- (the crust darkened: lit by the orange sky it read brown, not cooled rock)
M.LAVA_ROUGH = 0.75
M.LAVA_BOX_TILE = 3.0                   -- (a lava box's picture repeats every 3.2 m: this many times larger - in the
                                        -- volcano its cracks were a dense net)
local lava = { mid = nil, world = nil }

-- Caustics: the net of light the ripples throw on the seabed in sunshine (tools/caustics.py caustic96), on the level's
-- own floors under each water box, two layers drifting different ways so the net shifts and breaks as real caustics do.
-- Under a daytime sky only (sunsky.lua's sky up: no sun in a cave), and not where the water rises and falls (WDW).
M.CAUSTIC_TEX = "caustic96"
M.CAUSTIC_MIN_UP = 0.6          -- (how much a face must look up to take the caustics: floors and slopes to ~53 degrees)
M.CAUSTIC_PARENT = "/InterchangeAssets/gltf/MaterialInstances/MI_Unlit_Blend.MI_Unlit_Blend"
M.CAUSTIC_TILE = 420.0                  -- (cm a repeat)
M.CAUSTIC_DEPTH = 1600.0                -- (floors at most this far under the water)
M.CAUSTIC_TINT = { 2.0, 2.3, 2.4 }     -- (brighter than white - the material is unlit, so it glows: in white the net was
M.CAUSTIC_ALPHA = 0.75                  -- lost on the bright sand under the water)
M.CAUSTIC_LAYERS = { { drift = { 0.035, 0.018 }, scale = 1.0 }, { drift = { -0.022, 0.03 }, scale = 0.79 } }
M.CAUSTIC_LIFT = 2.5                    -- (cm off the floor)

local st = nil          -- this scene's: { world, list, mids, t, active, ... }

local function lib() return package.loaded["lib"] end
local function valid(a) return a ~= nil and pcall(function() return a:IsValid() end) and a:IsValid() end
local function log(fmt, ...)
    local L = lib()
    if L and L.log then pcall(L.log, "water96: " .. fmt, ...) else print(string.format("[water96] " .. fmt, ...)) end
end

-- the waves' numbers, worked out once: direction, wavenumber, angular speed, height, sideways reach
local WV = {}
local function prepare_waves()
    WV = {}
    for _, w in ipairs(M.WAVES) do
        local a = math.rad(w[1])
        local k = 2.0 * math.pi / w[2]
        local A = w[3]
        local H = w[4] / (k * #M.WAVES)            -- (sharpness 1: crests just short of folding over)
        WV[#WV + 1] = { dx = cos(a), dy = sin(a), k = k, om = sqrt(M.GRAVITY * k), A = A, H = H, kA = k * A, kH = k * H }
    end
end
prepare_waves()

-- the grid's ring offsets (cm from its middle), each point's fade, and how much of each wave it carries: a wave shorter
-- than four of the grid's steps there fades out, gone at two (the short ones, drawn by the far, wide-spaced points,
-- creased the water into straight lines)
local OFFS, NP, R = {}, 0, 0.0
local FADE, LOD = {}, {}
local function prepare_grid()
    OFFS = {}
    for n = -M.RINGS, M.RINGS do
        local a = abs(n)
        local f = M.STEP1 * a + M.STEP2 * a * a
        OFFS[#OFFS + 1] = (n < 0) and -f or f
    end
    NP = #OFFS
    R = OFFS[NP]
    FADE = {}
    for j = 1, NP do
        for i = 1, NP do
            local m = math.max(abs(OFFS[i]), abs(OFFS[j])) / R
            local t = (m - M.FADE_FROM) / (1.0 - M.FADE_FROM)
            t = math.max(0.0, math.min(1.0, t))
            FADE[(j - 1) * NP + i] = 1.0 - t * t * (3.0 - 2.0 * t)
        end
    end
    local step = {}
    for i = 1, NP do
        local a = (i > 1) and abs(OFFS[i] - OFFS[i - 1]) or 0.0
        local b = (i < NP) and abs(OFFS[i + 1] - OFFS[i]) or 0.0
        step[i] = math.max(a, b)
    end
    LOD = {}
    for j = 1, NP do
        for i = 1, NP do
            local sp = math.max(step[i], step[j], 1.0)
            local l = {}
            for w = 1, #M.WAVES do
                local q = (M.WAVES[w][2] / sp - 2.0) / 2.0
                l[w] = math.max(0.0, math.min(1.0, q))
            end
            LOD[(j - 1) * NP + i] = l
        end
    end
end
prepare_grid()

-- the flat water round the grid: a frame of quads from the wave grid's edge out to the box's - a strip on each side cut
-- at every one of the wave grid's lines, and the four corners - so where the two meet they share every point. (Four plain
-- strips met the wave grid's points with one long edge each: hairline cracks along it, a square round him seen through
-- Snowman's Land's ice - "the seams are still there", 2026-10-31. A full grid of its own did the same at four times the
-- points.) With no wave grid every cut sits at the box's near edge: the far corner's quad is then the whole box.
local function cuts(lo, hi, c)
    local t = {}
    for i = 1, NP do t[i] = c and math.max(lo, math.min(hi, c + OFFS[i])) or lo end
    return t
end
local FLAT_QUADS = 4 * (NP - 1) + 4
local FLAT_N = FLAT_QUADS * 4
local function flat_points(s, cx, cy)
    local xs, ys = cuts(s.x0, s.x1, cx), cuts(s.y0, s.y1, cx and cy)
    local v, uv = {}, {}
    local function quad(ax, bx, ay, by)
        for _, c in ipairs({ { ax, ay }, { bx, ay }, { bx, by }, { ax, by } }) do
            v[#v + 1] = { X = c[1], Y = c[2], Z = s.base }
            uv[#uv + 1] = { X = c[2] / M.REPEAT, Y = c[1] / M.REPEAT }
        end
    end
    for i = 1, NP - 1 do
        quad(xs[i], xs[i + 1], s.y0, ys[1])         -- (the strip along its near y side)
        quad(xs[i], xs[i + 1], ys[NP], s.y1)        -- (its far y side)
        quad(s.x0, xs[1], ys[i], ys[i + 1])         -- (its near x side)
        quad(xs[NP], s.x1, ys[i], ys[i + 1])        -- (its far x side)
    end
    quad(s.x0, xs[1], s.y0, ys[1])
    quad(xs[NP], s.x1, s.y0, ys[1])
    quad(s.x0, xs[1], ys[NP], s.y1)
    quad(xs[NP], s.x1, ys[NP], s.y1)
    return v, uv
end
local FLAT_IDX = {}
for q = 0, FLAT_QUADS - 1 do
    local b = q * 4
    for _, t in ipairs({ { 0, 1, 2 }, { 0, 2, 3 }, { 0, 2, 1 }, { 0, 3, 2 } }) do
        FLAT_IDX[#FLAT_IDX + 1] = b + t[1]; FLAT_IDX[#FLAT_IDX + 1] = b + t[2]; FLAT_IDX[#FLAT_IDX + 1] = b + t[3]
    end
end

local function white(n)
    local c = {}
    for i = 1, n do c[i] = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 } end
    return c
end
local function ups(n)
    local c = {}
    for i = 1, n do c[i] = { X = 0.0, Y = 0.0, Z = 1.0 } end
    return c
end

-- the material for one kind of water (one a scene: their pictures drift together)
local function material(world, kind)
    if st.mids[kind] then return st.mids[kind] end
    local L = lib()
    local KML = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    local parent = LoadAsset(M.PARENT)
    if not (KML and valid(parent)) then return nil end
    local mid = KML:CreateDynamicMaterialInstance(world, parent, FName("water96_" .. kind), 0)
    if not valid(mid) then return nil end
    local look = M.LOOK[kind] or M.LOOK.water
    local base = L.texture(world, M.TEX)
    local nrm = L.texture(world, M.NORMAL)
    pcall(function()
        if base then mid:SetTextureParameterValue(FName("BaseColorTexture"), base) end
        if nrm then mid:SetTextureParameterValue(FName("NormalTexture"), nrm) end
        local t = look.tint
        mid:SetVectorParameterValue(FName("BaseColorFactor"), { R = t[1], G = t[2], B = t[3], A = 1.0 })
        mid:SetScalarParameterValue(FName("TransmissionFactor"), look.through)
        mid:SetScalarParameterValue(FName("RoughnessFactor"), M.ROUGH)
        mid:SetScalarParameterValue(FName("MetallicFactor"), 0.0)
        mid:SetScalarParameterValue(FName("IOR"), M.IOR)
        mid:SetScalarParameterValue(FName("NormalScale"), M.NRM_STRENGTH)
    end)
    st.mids[kind] = mid
    return mid
end

-- The lava's material (one a map; nil with RENDER 96 off - Mario 64's own then)
function M.lava_material(world)
    local L = lib()
    if not (L and L.R96 and world) then return nil end
    local addr = nil
    pcall(function() addr = world:GetAddress() end)
    if lava.mid and valid(lava.mid) and lava.world == addr then return lava.mid end
    local KML = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    local parent = LoadAsset(M.LAVA_PARENT)
    if not (KML and valid(parent)) then return nil end
    local mid = KML:CreateDynamicMaterialInstance(world, parent, FName("water96_lava"), 0)
    if not valid(mid) then return nil end
    local base, glow = L.texture(world, M.LAVA_TEX), L.texture(world, M.LAVA_GLOW)
    if not (base and glow) then return nil end
    pcall(function()
        mid:SetTextureParameterValue(FName("BaseColorTexture"), base)
        mid:SetTextureParameterValue(FName("EmissiveTexture"), glow)
        local h = M.LAVA_HEAT
        mid:SetVectorParameterValue(FName("EmissiveFactor"), { R = h[1], G = h[2], B = h[3], A = 1.0 })
        mid:SetScalarParameterValue(FName("EmissiveStrength"), M.LAVA_STRENGTH)
        mid:SetScalarParameterValue(FName("RoughnessFactor"), M.LAVA_ROUGH)
        mid:SetScalarParameterValue(FName("MetallicFactor"), 0.0)
        local c = M.LAVA_CRUST
        mid:SetVectorParameterValue(FName("BaseColorFactor"), { R = c[1], G = c[2], B = c[3], A = 1.0 })
        local k = M.LAVA_SCALE
        mid:SetVectorParameterValue(FName("BaseColorTexture_OffsetScale"), { R = 0.0, G = 0.0, B = k, A = k })
        mid:SetVectorParameterValue(FName("EmissiveTexture_OffsetScale"), { R = 0.0, G = 0.0, B = k, A = k })
    end)
    lava.mid, lava.world, lava.t = mid, addr, 0.0
    log("lava material made")
    return mid
end

-- Made for a scene, after its water (game.lua load_scene): its water boxes' surfaces given the real water - the flat
-- water a section of its own (2) on the box's mesh, its own surface (0) hidden; the grid (3) made when first needed.
function M.setup(world, G)
    st = nil
    local L = lib()
    if not (L and L.R96 and G and G.water_rot) then return 0 end
    st = { world = world, list = {}, mids = {}, t = 0.0, frame = 0, ripples = {}, scene = G.name }
    local sc = M.SCALE[G.name or ""] or M.SCALE_DEFAULT
    for _, w in ipairs(G.water_rot) do
        if w.w96 and w.tex == "lava" and valid(w.pmc) then
            local lm = M.lava_material(world)
            if lm then
                pcall(function() w.pmc:SetMaterial(0, lm) end)
                w.Tu, w.Tv = (w.Tu or w.T) * M.LAVA_BOX_TILE, (w.Tv or w.T) * M.LAVA_BOX_TILE   -- (game.lua turn_water)
            end
        end
        if w.w96 and not w.under and M.KINDS[w.tex or "water"] and valid(w.pmc) then
            local mid = material(world, w.tex or "water")
            if mid then
                local s = { pmc = w.pmc, actor = w.actor, x0 = w.x0, x1 = w.x1, y0 = w.y0, y1 = w.y1, base = w.base,
                            kind = w.tex or "water", mid = mid }
                local side = math.min(s.x1 - s.x0, s.y1 - s.y0)
                s.amp = sc * math.max(0.25, math.min(1.0, side / M.BOX_FULL))
                local ok, err = pcall(function()
                    local v, uv = flat_points(s, nil, nil)
                    L.create_section(s.pmc, 2, v, FLAT_IDX, ups(FLAT_N), uv, white(FLAT_N), false)
                    s.pmc:SetMaterial(2, mid)
                    s.pmc:SetMeshSectionVisible(0, false)
                    s.pmc:SetTranslucentSortPriority(M.SORT)
                end)
                if ok then
                    w.still = true                  -- (game.lua turn_water: its picture no longer turned)
                    st.list[#st.list + 1] = s
                else
                    log("box failed: %s", tostring(err))
                end
            end
        end
    end
    log("%s: %d water surfaces made real (waves x%.2f)", tostring(G.name), #st.list, sc)
    if #st.list == 0 then st = nil end
    return st and #st.list or 0
end

-- a box's water height now (its mesh is moved with the level: WDW's water, the drained moat)
local function level_of(s)
    local z = s.base
    pcall(function() z = s.base + (s.actor:K2_GetActorLocation().Z - lib().OFFSET.Z) end)
    return z
end

-- the waves' height at a point, as the grid draws it (the waves alone: no ripples, no sideways shift)
local function wave_h(s, x, y)
    local dz = 0.0
    local t = st.t
    for i = 1, #WV do
        local W = WV[i]
        dz = dz + W.A * sin(W.k * (W.dx * x + W.dy * y) - W.om * t)
    end
    local m = math.max(abs(x - st.cx), abs(y - st.cy)) / R
    local f = (m - M.FADE_FROM) / (1.0 - M.FADE_FROM)
    f = math.max(0.0, math.min(1.0, f))
    return dz * s.amp * (1.0 - f * f * (3.0 - 2.0 * f))
end

-- How far the water's top is moved by the waves at (x, y) (scene cm): game.lua update_swim floats him on it
function M.height(x, y)
    if not (st and st.active and st.cx) then return 0.0 end
    local s = st.active
    if x < s.x0 or x > s.x1 or y < s.y0 or y > s.y1 then return 0.0 end
    return wave_h(s, x, y)
end

-- a ring run out from (x, y)
function M.ripple(x, y, amp)
    if not st then return end
    local r = st.ripples
    if #r >= M.RIP_MAX then table.remove(r, 1) end
    r[#r + 1] = { x = x, y = y, t0 = st.t, amp = amp or M.RIP_SWIM }
end

-- the grid made for a box (once): rest points, and its mesh section
local function make_grid(s)
    local L = lib()
    local n = NP * NP
    s.rx, s.ry = {}, {}
    s.pv, s.pn, s.puv = {}, ups(n), {}
    for k = 1, n do
        s.pv[k] = { X = 0.0, Y = 0.0, Z = s.base }
        s.puv[k] = { X = 0.0, Y = 0.0 }
        s.rx[k], s.ry[k] = 0.0, 0.0
    end
    local idx = {}
    for j = 0, NP - 2 do
        for i = 0, NP - 2 do
            local a = j * NP + i
            local b, c, d = a + 1, a + NP, a + NP + 1
            idx[#idx + 1] = a; idx[#idx + 1] = c; idx[#idx + 1] = b
            idx[#idx + 1] = b; idx[#idx + 1] = c; idx[#idx + 1] = d
            idx[#idx + 1] = a; idx[#idx + 1] = b; idx[#idx + 1] = c
            idx[#idx + 1] = b; idx[#idx + 1] = d; idx[#idx + 1] = c
        end
    end
    L.create_section(s.pmc, 3, s.pv, idx, s.pn, s.puv, white(n), false)
    s.pmc:SetMaterial(3, s.mid)
    s.grid = true
end

-- the grid put round (cx, cy), and the flat water's hole round it
local function place(s, cx, cy)
    local L = lib()
    st.cx, st.cy = cx, cy
    for j = 1, NP do
        local y = math.max(s.y0, math.min(s.y1, cy + OFFS[j]))
        for i = 1, NP do
            local x = math.max(s.x0, math.min(s.x1, cx + OFFS[i]))
            local k = (j - 1) * NP + i
            s.rx[k], s.ry[k] = x, y
            local uv = s.puv[k]
            uv.X, uv.Y = y / M.REPEAT, x / M.REPEAT
        end
    end
    local v, uv = flat_points(s, cx, cy)
    pcall(L.update_section, s.pmc, 2, v, nil, uv)
end

local function deactivate(s)
    if not s then return end
    local L = lib()
    pcall(function()
        local v, uv = flat_points(s, nil, nil)
        L.update_section(s.pmc, 2, v, nil, uv)
        if s.grid then s.pmc:SetMeshSectionVisible(3, false) end
    end)
end

-- the grid's points moved: waves, then ripples
local function move_grid(s, with_uv)
    local t = st.t
    local base = s.base
    local amp = s.amp
    local rx, ry, pv, pn = s.rx, s.ry, s.pv, s.pn
    local rips = st.ripples
    local nr = #rips
    local RK = 2.0 * math.pi / M.RIP_LEN
    local nw = #WV
    for k = 1, NP * NP do
        local x, y = rx[k], ry[k]
        local f = FADE[k] * amp
        local dz, hx, hy, nx, ny, ns = 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
        if f > 0.0 then
            local lw = LOD[k]
            for i = 1, nw do
                local W = WV[i]
                local ph = W.k * (W.dx * x + W.dy * y) - W.om * t
                local q = lw[i]
                local sp, cp = sin(ph) * q, cos(ph) * q
                dz = dz + W.A * sp
                hx = hx + W.H * W.dx * cp
                hy = hy + W.H * W.dy * cp
                nx = nx + W.dx * W.kA * cp
                ny = ny + W.dy * W.kA * cp
                ns = ns + W.kH * sp
            end
            dz, hx, hy, nx, ny, ns = dz * f, hx * f, hy * f, nx * f, ny * f, ns * f
        end
        for r = 1, nr do
            local rp = rips[r]
            local age = t - rp.t0
            local front = M.RIP_SPEED * age
            local ddx, ddy = x - rp.x, y - rp.y
            local d = sqrt(ddx * ddx + ddy * ddy)
            if d < front and d < 900.0 then
                local edge = math.min(1.0, (front - d) / 80.0)
                local env = rp.amp * exp(-age * M.RIP_DECAY) / (1.0 + d / 120.0) * edge * FADE[k]
                local ph = RK * (d - front)
                dz = dz + env * sin(ph)
                if d > 1.0 then
                    local g = env * RK * cos(ph) / d
                    nx = nx + g * ddx
                    ny = ny + g * ddy
                end
            end
        end
        local V = pv[k]
        V.X, V.Y, V.Z = x + hx, y + hy, base + dz
        local nz = 1.0 - ns
        local l = 1.0 / sqrt(nx * nx + ny * ny + nz * nz)
        local N = pn[k]
        N.X, N.Y, N.Z = -nx * l, -ny * l, nz * l
    end
    local L = lib()
    -- (SectionIndex, Vertices, Normals, UV0, UV1, UV2, UV3, VertexColors, Tangents, bSRGBConversion)
    s.pmc:UpdateMeshSection_LinearColor(3, pv, pn, with_uv and s.puv or {}, {}, {}, {}, {}, {}, false)
end

-- the caustics' mesh: the level's solid floors under the scene's water boxes, lifted a little off them
local function build_caustics(G)
    local L = lib()
    local data = G and G.data
    if not (data and data.sections) or G.wlevel then return nil end
    -- (each box at its water's height now, not as the level was made: the castle grounds' moat drained from the
    -- basement lies 600 under its banks, and its dry floor had the net of light on it - "outside theres a water texture
    -- with no water?", 2026-11-01)
    local boxes = {}
    for _, s in ipairs(st.list) do
        boxes[#boxes + 1] = { x0 = s.x0, x1 = s.x1, y0 = s.y0, y1 = s.y1, base = level_of(s) }
    end
    if #boxes == 0 then return nil end
    local tex = L.texture(st.world, M.CAUSTIC_TEX)
    local parent = LoadAsset(M.CAUSTIC_PARENT)
    local KML = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    if not (tex and valid(parent) and KML) then return nil end
    local verts, nrms, uvs, cols, idx = {}, {}, {}, {}, {}
    local T, lift = M.CAUSTIC_TILE, M.CAUSTIC_LIFT
    for _, sec in ipairs(data.sections) do
        local layer = sec.layer
        if (layer == "opaque" or layer == "lit") and sec.pos and sec.idx then
            local P, I, NR = sec.pos, sec.idx, sec.nrm
            for t = 1, #I - 2, 3 do
                local a, b, c = I[t], I[t + 1], I[t + 2]
                local ax, ay, az = P[a * 3 + 1], P[a * 3 + 2], P[a * 3 + 3]
                local bx, by, bz = P[b * 3 + 1], P[b * 3 + 2], P[b * 3 + 3]
                local cx, cy, cz = P[c * 3 + 1], P[c * 3 + 2], P[c * 3 + 3]
                local mx, my, mz = (ax + bx + cx) / 3.0, (ay + by + cy) / 3.0, (az + bz + cz) / 3.0
                -- (all of the face under the water, not just its middle: a bank's faces stood up out of it with the net
                -- of light on them - "water texxture is still over reaching", 2026-11-01)
                local top = math.max(az, bz, cz)
                local under = false
                for _, w in ipairs(boxes) do
                    if mx > w.x0 and mx < w.x1 and my > w.y0 and my < w.y1 and top < w.base - 2.0 and mz > w.base - M.CAUSTIC_DEPTH then
                        under = true
                        break
                    end
                end
                if under then
                    -- (its face's way out: the stored normals, else the side the engine draws it from)
                    local nx, ny, nz
                    if NR then
                        nx = NR[a * 3 + 1] + NR[b * 3 + 1] + NR[c * 3 + 1]
                        ny = NR[a * 3 + 2] + NR[b * 3 + 2] + NR[c * 3 + 2]
                        nz = NR[a * 3 + 3] + NR[b * 3 + 3] + NR[c * 3 + 3]
                    else
                        local ux, uy, uz = bx - ax, by - ay, bz - az
                        local vx, vy, vz = cx - ax, cy - ay, cz - az
                        nx, ny, nz = -(uy * vz - uz * vy), -(uz * vx - ux * vz), -(ux * vy - uy * vx)
                    end
                    local l = sqrt(nx * nx + ny * ny + nz * nz)
                    -- (floors and gentle slopes only: the net is laid on from above, and on a wall it ran into long
                    -- streaks; no ceilings either - no sun reaches up there)
                    if l > 1e-6 and nz / l > M.CAUSTIC_MIN_UP then
                        nx, ny, nz = nx / l, ny / l, nz / l
                        local base = #verts
                        for _, q in ipairs({ { ax, ay, az }, { bx, by, bz }, { cx, cy, cz } }) do
                            verts[#verts + 1] = { X = q[1] + nx * lift, Y = q[2] + ny * lift, Z = q[3] + nz * lift }
                            nrms[#nrms + 1] = { X = nx, Y = ny, Z = nz }
                            uvs[#uvs + 1] = { X = q[2] / T, Y = q[1] / T }
                            cols[#cols + 1] = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
                        end
                        idx[#idx + 1] = base; idx[#idx + 1] = base + 1; idx[#idx + 1] = base + 2
                        idx[#idx + 1] = base; idx[#idx + 1] = base + 2; idx[#idx + 1] = base + 1
                    end
                end
            end
        end
    end
    if #verts == 0 then return nil end
    local actor = L.spawn_actor(st.world, { X = L.OFFSET.X, Y = L.OFFSET.Y, Z = L.OFFSET.Z }, 0.0)
    local pmc = actor and L.add_pmc(actor)
    if not pmc then return nil end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    pcall(function() pmc:SetTranslucentSortPriority(M.CAUSTIC_SORT) end)
    local mids = {}
    for i, ly in ipairs(M.CAUSTIC_LAYERS) do
        L.create_section(pmc, i - 1, verts, idx, nrms, uvs, cols, false)
        local mid = KML:CreateDynamicMaterialInstance(st.world, parent, FName("water96_caustic_" .. i), 0)
        if valid(mid) then
            pcall(function()
                mid:SetTextureParameterValue(FName("BaseColorTexture"), tex)
                local t = M.CAUSTIC_TINT
                mid:SetVectorParameterValue(FName("BaseColorFactor"), { R = t[1], G = t[2], B = t[3], A = M.CAUSTIC_ALPHA })
            end)
            pmc:SetMaterial(i - 1, mid)
            mids[#mids + 1] = { mid = mid, layer = ly }
        end
    end
    if G.extras then G.extras[#G.extras + 1] = actor end      -- (gone with the scene)
    log("caustics: %d floor triangles under the water", #verts // 3)
    return { actor = actor, pmc = pmc, mids = mids }
end

-- Every frame (game.lua tick): the pictures drift; every other frame the grid round him moves
function M.tick(dt)
    if lava.mid then
        if valid(lava.mid) then
            lava.t = (lava.t or 0.0) + (dt or 0.016)
            local P = M.LAVA_PULSE
            local k = 1.0 + P[1] * sin(lava.t * P[2]) + P[3] * sin(lava.t * P[4] + 1.3)
            pcall(function() lava.mid:SetScalarParameterValue(FName("EmissiveStrength"), M.LAVA_STRENGTH * k) end)
        else
            lava.mid = nil
        end
    end
    if not st then return end
    local L = lib()
    if not L then return end
    -- (the scene gone under it: its meshes with it - nothing of theirs touched again)
    local s1 = st.list[1]
    if not (s1 and valid(s1.pmc) and valid(s1.actor)) then st = nil; return end
    st.t = st.t + (dt or 0.016)
    local t = st.t
    st.mid_t = (st.mid_t or 0.0) + (dt or 0.016)
    local drift = st.mid_t >= M.MID_STEP
    if drift then st.mid_t = 0.0 end
    local FN = M.FN
    if not FN then
        FN = { base = FName("BaseColorTexture_OffsetScale"), nrm = FName("NormalTexture_OffsetScale") }
        M.FN = FN
    end
    if drift then for _, mid in pairs(st.mids) do
        if valid(mid) then pcall(function()
            mid:SetVectorParameterValue(FN.base,
                { R = (M.DRIFT_TEX[1] * t) % 1.0, G = (M.DRIFT_TEX[2] * t) % 1.0, B = 1.0, A = 1.0 })
            mid:SetVectorParameterValue(FN.nrm,
                { R = (M.DRIFT_NRM[1] * t + M.NRM_SWAY[1] * sin(M.NRM_SWAY[2] * t)) % 1.0,
                  G = (M.DRIFT_NRM[2] * t + M.NRM_SWAY[3] * cos(M.NRM_SWAY[4] * t)) % 1.0, B = M.NRM_SCALE, A = M.NRM_SCALE })
        end) end
    end end
    -- (the caustics: made once the sky is known - sunsky.lua is put up after the water - and drifting)
    if not st.caustic_tried then
        local SS = package.loaded["sunsky"]
        local sky = SS and SS.debug and SS.debug()
        if sky ~= nil or (st.t > 2.0) then
            st.caustic_tried = true
            if sky and sky.on then
                local okc, c = pcall(build_caustics, package.loaded["game"])
                if okc then st.caustic = c else log("caustics: %s", tostring(c)) end
            end
        end
    end
    if st.caustic and drift then
        for _, m in ipairs(st.caustic.mids) do
            if valid(m.mid) then pcall(function()
                local d, k = m.layer.drift, m.layer.scale
                m.mid:SetVectorParameterValue(FN.base,
                    { R = (d[1] * t) % 1.0, G = (d[2] * t) % 1.0, B = k, A = k })
            end) end
        end
    end
    -- (old ripples gone)
    local rips = st.ripples
    while #rips > 0 and t - rips[1].t0 > M.RIP_LIFE do table.remove(rips, 1) end
    st.step_t = (st.step_t or 0.0) + (dt or 0.016)
    if st.step_t < M.STEP then return end
    local since = st.step_t
    st.step_t = 0.0
    local pawn = L.pawn()
    if not valid(pawn) then return end
    local loc = pawn:K2_GetActorLocation()
    local px, py, pz = loc.X - L.OFFSET.X, loc.Y - L.OFFSET.Y, loc.Z - L.OFFSET.Z
    -- (the box under him, its water nearest his height)
    local best, bd, blev = nil, M.NEAR_Z, nil
    for _, s in ipairs(st.list) do
        if px > s.x0 - 300.0 and px < s.x1 + 300.0 and py > s.y0 - 300.0 and py < s.y1 + 300.0 and valid(s.actor) and valid(s.pmc) then
            local lev = level_of(s)
            local d = abs(pz - lev)
            if d < bd then best, bd, blev = s, d, lev end
        end
    end
    if best ~= st.active then
        deactivate(st.active)
        st.active, st.cx, st.cy = best, nil, nil
        st.ripples = {}
        rips = st.ripples
        if best then
            if not best.grid then
                local ok, err = pcall(make_grid, best)
                if not ok then log("grid: %s", tostring(err)); st.active = nil; return end
            end
            pcall(function() best.pmc:SetMeshSectionVisible(3, true) end)
        end
    end
    local s = st.active
    if not s then return end
    -- (ripples where he goes in, swims and wades)
    local G = package.loaded["game"]
    local v = pawn:GetVelocity()
    local hs = sqrt(v.X * v.X + v.Y * v.Y)
    local swim = G and G.swim
    local inside = px >= s.x0 and px <= s.x1 and py >= s.y0 and py <= s.y1
    if swim and not st.was_swim and inside then M.ripple(px, py, M.RIP_ENTER) end
    st.was_swim = swim
    st.rip_t = (st.rip_t or 0.0) - since
    if inside and st.rip_t <= 0.0 then
        if swim and abs(pz - blev) < 130.0 then
            if hs > 80.0 then M.ripple(px, py, M.RIP_SWIM); st.rip_t = 0.35
            else M.ripple(px, py, M.RIP_IDLE); st.rip_t = 1.4 end
        elseif not swim and pz > blev - 100.0 and pz < blev + 110.0 and hs > 100.0 then
            M.ripple(px, py, M.RIP_WADE); st.rip_t = 0.45
        end
    end
    -- (the grid round him, moved in steps)
    local cx, cy = floor(px / M.SNAP + 0.5) * M.SNAP, floor(py / M.SNAP + 0.5) * M.SNAP
    local moved = cx ~= st.cx or cy ~= st.cy
    if moved then place(s, cx, cy) end
    local ok, err = pcall(move_grid, s, moved)
    if not ok then
        log("waves: %s", tostring(err))
        deactivate(s)
        st.list = {}
        st.active = nil
    end
end

-- the scene left / RENDER 96 turned off: nothing to keep (the meshes go with the scene)
function M.forget() st = nil end
function M.debug() return st end

return M
