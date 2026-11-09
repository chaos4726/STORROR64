-- SM64Map: RENDER 96's sky. Under a level's daytime sky (Mario 64's picture of the sky, its clouds painted in), with
-- RENDER 96 on: Unreal's own sky of the air (SkyAtmosphere) with the sun's disc in it, real clouds (VolumetricCloud,
-- the engine's m_SimpleVolumetricCloud) and the sun's rays (light-shaft bloom and occlusion) - "next I want sunrays on
-- every map with a sun, and real clouds instead of the 2d ones", 2026-10-31. The picture of the sky is hidden while it
-- is up; the enclosed levels, and the night and Bowser skies, keep theirs.
--
-- The sky is lit by a sun of its own: the level's sun (menu.lua's, 6 lux, as the levels' lighting is made for) made a
-- sky as dark as dusk and the clouds grey. The sky's sun lights nothing else (lighting channel 2, which nothing is in),
-- SKY_SUN times as strong, turned as the level's is; the rays are its. Under the horizon Unreal's ground showed black
-- past the levels' edges: a dome of colour there instead (unlit, the horizon's haze down to the sky's own colour - the
-- sea under Bob-omb Battlefield's sky, the sand under Shifting Sand Land's, a sea of cloud under Whomp's Fortress's).
-- Called by game.lua's load_scene after sky.lua (the sky's name, the scene's name); RENDER 96 turned reloads the level.
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET

local M = {}

-- The BACKGROUND switch (MARIO SETTINGS - "add a backround switch for real mario 64 backrounds instead of our clouds",
-- 2026-11-01): MARIO 64, the level's own picture of the sky (sky.lua) even with RENDER 96 on; CLOUDS, this sky. Kept
-- beside the save files (background.lua); turned live - the sky put up again where he stands (M.set_picture_sky).
local BG_FILE = lib.MOD_DIR .. "background.lua"
M.PICTURE = nil
function M.picture_sky()
    if M.PICTURE == nil then
        M.PICTURE = false
        local f = io.open(BG_FILE, "r")
        if f then
            local t = f:read("a"); f:close()
            if t and t:match("picture%s*=%s*true") then M.PICTURE = true end
        end
    end
    return M.PICTURE
end
-- the skies with a sun: how much of them the clouds cover (Ultra Dynamic Sky's 0-10), the sky's ground (cm under the
-- scene's origin - its clouds are 0.6 to 1.3 km over it; the cloud sea's levels up over them), and the dome's colour
-- under the horizon (sRGB): deep, and at the horizon
M.HAZE = { 0.86, 0.9, 0.95 }
M.SKIES = {
    water = { coverage = 3.8, ground = 0.0, deep = { 0.12, 0.34, 0.6 }, haze = { 0.62, 0.76, 0.9 } },
    ssl = { coverage = 2.0, ground = 0.0, deep = { 0.78, 0.66, 0.48 }, haze = { 0.92, 0.88, 0.82 } },
    wdw = { coverage = 3.5, ground = 0.0, deep = { 0.36, 0.48, 0.58 } },
    ccm = { coverage = 4.5, ground = 0.0, deep = { 0.8, 0.86, 0.92 } },
    clouds = { coverage = 6.0, ground = 0.0, deep = { 0.3, 0.45, 0.6 } },
    -- (over the sea of cloud: fuller cover, and the sea far under it - between the clouds, as from a height; white under
    -- them it read as grey patches on snow, 2026-10-31)
    cloud_floor = { coverage = 6.5, ground = 250000.0, under = true, deep = { 0.1, 0.27, 0.45 }, haze = { 0.62, 0.74, 0.86 } },
}
-- The clouds: the engine's stock cloud material made a thin fog of a cloud ("clouds are more like fog I want Cumulus
-- clouds", 2026-10-31). STORROR has Ultra Dynamic Sky in it, whose clouds are cumulus - but made whole it lights the
-- level with a sun and a sky light of its own. So it is made for a moment at each daytime level (deferred, in one call:
-- never drawn), its cloud material's settings copied onto one of ours, its layer read, and it is taken away; the
-- parameter collections it filled (UDS_VolumetricClouds_MPC, the weather's) keep their values.
M.UDS = "/Game/UltraDynamicSky/Blueprints/Ultra_Dynamic_Sky.Ultra_Dynamic_Sky_C"
-- the god rays (fog.lua M.rays): the level's sun lit into the thin volumetric fog, its shadows the beams; the soft
-- lights all round and the sky's sun none (they would light it evenly - a glow, no beams)
M.RAYS_SUN = 3.0
-- (the light all round under the open sky: menu.lua's soft lights - made for the picture sky - this much stronger and a
-- little blue, as a clear sky lights what the sun does not reach. Their sides in shade stood near black under it -
-- Rainbow Ride's floating blocks and its ship, 2026-10-31)
M.SKY_AMB = 1.8
M.SKY_AMB_TINT = { R = 0.84, G = 0.91, B = 1.0, A = 1.0 }
M.SKY_SUN = 4.0              -- (the sky's sun, times the level's)
-- (the sky's own light, caught from the sky as it is drawn: what glossy things - RENDER 96's water, water96.lua - shine
-- with; without it the water reflected nothing and was dark)
M.SKY_LIGHT = 1.0
M.SKY_LOW = { R = 0.2, G = 0.28, B = 0.32, A = 1.0 }
M.SHAFT_BLOOM = 0.25         -- (the rays: the light-shaft bloom's strength, and from how bright a pixel)
M.SHAFT_THRESHOLD = 0.6
M.SHAFT_DARK = 0.35          -- (the shade the occlusion lays where the sky toward the sun is blocked)
M.DOME_R = 3000000.0         -- (cm: 30 km round the scene's origin, past the ground under the level)
M.DOME_TOP = 0.0             -- (degrees over the horizon its top edge: the ground under the level meets the sky there)
M.DOME_FADE = 18.0           -- (degrees under the horizon to its deep colour)
-- (the dome's top edge met the sky in a hard line - "fade the horizon", 2026-11-01: over it a band of the dome's own
-- haze, see-through and fading out over FADE_UP degrees of the sky - sky_fade, a picture solid at its foot, clear at its top)
M.FADE_UP = 5.0
M.FADE_TEX = "sky_fade"
M.BLEND = "/InterchangeAssets/gltf/MaterialInstances/MI_Unlit_Blend.MI_Unlit_Blend"
-- (the sea of cloud under the levels up over it, its top this far (cm) under the level's lowest floor: 1.2 km down it was
-- far below, small - "bring them up higher", 2026-11-01. The clouds' layer is Ultra Dynamic Sky's - CLOUD_TOP its top
-- over its ground when it cannot be read)
M.CLOUD_UNDER = 15000.0
M.CLOUD_TOP = 130000.0
M.CLOUD_MAT = "/Engine/EngineSky/VolumetricClouds/m_SimpleVolumetricCloud_Inst.m_SimpleVolumetricCloud_Inst"

-- The ground far under the level, out to the horizon: past the levels' edges there was only the dome's flat colour -
-- "the border right now it just shows a blank greyness going on infinitely", 2026-10-31. A sea under the sea skies,
-- sand under Shifting Sand Land's, snow under the snow levels' (tools/ground_tex.py's pictures, tiling), lit as the level
-- is; Unreal's sky hazes it into the horizon as it goes. GROUND_DOWN under the level's lowest floor, GROUND_R out. The
-- levels up over the sea of cloud have the clouds under them instead.
M.GROUND_TEX = { water = "ground_sea", clouds = "ground_sea", wdw = "ground_sea", ssl = "ground_sand", ccm = "ground_snow",
                 cloud_floor = "ground_sea" }
M.GROUND_ROUGH = { ground_sea = 0.22, ground_sand = 0.9, ground_snow = 0.55 }
M.GROUND_DOWN = 2000.0
M.GROUND_R = 2500000.0
M.GROUND_TILE = 6000.0       -- (cm of ground a picture: wide, so it does not show its repeat)
M.GROUND_NEAR = 20000.0      -- (its picture out to this from the level's middle; plain past it - 400 m showed the picture's
                             -- repeats shimmering far off: "also smooth the distance", 2026-11-01)
-- (the levels in the sea - their own sea a water box: the far sea at its height, a hole where the box is, so it goes on
-- from the level's water to the horizon; under it, 20 m down, it stood as a step down past the box's edge)
M.SEA_LEVEL = { thi = true, thi_2 = true, ddd = true, jrb = true }
-- (the far ground goes into the horizon's haze: the sea ran deep blue to the horizon and met the sky's pale haze in a
-- hard line - "fix this as well make it blend together better", 2026-11-01. A ring of the dome's haze colour lies just
-- over it, clear HAZE_RINGS[1] from the level's middle and thicker outward to solid at its edge - sky_fade's alpha,
-- by the ring's v - so the sea and the sky's foot are one colour where they meet.)
-- (seen from 30-40 m over the sea, all past 2 km lies in the last few pixels under the horizon: the haze's rise is
-- within the first few km - clear at 300 m, about half at 1.2 km, all but solid by 5 km)
M.HAZE_RINGS = { { 30000.0, 0.0 }, { 60000.0, 0.32 }, { 120000.0, 0.47 }, { 250000.0, 0.63 }, { 500000.0, 0.78 },
                 { 1000000.0, 0.95 } }
M.HAZE_LIFT = 150.0

local st = nil               -- { world, atmo, cloud, sun, dome, ground, on, sky, coverage }
-- (dev: Ultra Dynamic Sky handed over from a module reloaded live - one made after another was taken away gave no clouds)
local kept_uds = nil
function M.keep_uds(a) kept_uds = a end

local function valid(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

local function env_here()
    local env = _G.MENU and _G.MENU.env
    local here = nil
    pcall(function() here = lib.world():GetAddress() end)
    if env and env.world == here then return env end
    return nil
end

local function spawn(world, cls, z)
    local c = StaticFindObject(cls)
    if not (c and c:IsValid()) then return nil end
    local a = world:SpawnActor(c, { X = OFFSET.X, Y = OFFSET.Y, Z = z }, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
    if not (a and a:IsValid()) then return nil end
    pcall(function() lib.keep[a:GetAddress()] = "sunsky" end)
    return a
end

-- the dome under the horizon: rings from DOME_TOP over it down to straight under, haze to `deep`
local function dome_section(def)
    local N, R = 48, M.DOME_R
    local pos, nrm, uv, col, idx = {}, {}, {}, {}, {}
    local haze, deep = def.haze or M.HAZE, def.deep
    local rings = { M.DOME_TOP, 0.0, -2.0, -5.0, -9.0, -14.0, -M.DOME_FADE, -30.0, -50.0, -70.0, -89.0 }
    for ri, e in ipairs(rings) do
        local k = math.max(0.0, math.min(1.0, -e / M.DOME_FADE))
        k = k * k * (3.0 - 2.0 * k)
        local c = { haze[1] + (deep[1] - haze[1]) * k, haze[2] + (deep[2] - haze[2]) * k, haze[3] + (deep[3] - haze[3]) * k }
        local er = math.rad(e)
        for i = 0, N do
            local a = 2.0 * math.pi * i / N
            pos[#pos + 1] = R * math.cos(er) * math.cos(a); pos[#pos + 1] = R * math.cos(er) * math.sin(a); pos[#pos + 1] = R * math.sin(er)
            nrm[#nrm + 1] = 0; nrm[#nrm + 1] = 0; nrm[#nrm + 1] = 1
            uv[#uv + 1] = i / N; uv[#uv + 1] = ri / #rings
            col[#col + 1] = c[1]; col[#col + 1] = c[2]; col[#col + 1] = c[3]; col[#col + 1] = 1.0
        end
    end
    local W = N + 1
    for r = 0, #rings - 2 do
        for i = 0, N - 1 do
            local a, b, c, d = r * W + i, r * W + i + 1, (r + 1) * W + i, (r + 1) * W + i + 1
            -- (both windings: seen from inside, whichever way the engine draws)
            idx[#idx + 1] = a; idx[#idx + 1] = b; idx[#idx + 1] = c
            idx[#idx + 1] = b; idx[#idx + 1] = d; idx[#idx + 1] = c
            idx[#idx + 1] = a; idx[#idx + 1] = c; idx[#idx + 1] = b
            idx[#idx + 1] = b; idx[#idx + 1] = c; idx[#idx + 1] = d
        end
    end
    return { id = 0, layer = "opaque", unlit = true, texture = nil, nverts = #pos // 3, ntris = #idx // 3,
             pos = pos, nrm = nrm, uv = uv, col = col, idx = idx }
end

-- the ground: out to GROUND_R, its picture laid on by place (GROUND_TILE a picture) - out to GROUND_NEAR from the level's
-- middle its picture, past that its plain far copy (the picture's own average: the mod's pictures have no smaller copies
-- for the distance, and the far ground's repeats drew stripes running to the horizon - Cool, Cool Mountain's snow
-- plain, 2026-10-31; tools/ground_tex.py makes both). Two sections: 0 near, 1 far.
local function ground_section(tex, hole)
    local R, RN = M.GROUND_R, M.GROUND_NEAR
    local function new(id, t) return { id = id, layer = "lit", texture = t, pos = {}, nrm = {}, uv = {}, col = {}, idx = {} } end
    local near, far = new(0, tex), new(1, tex .. "_far")
    local function finish(sec) sec.nverts = #sec.pos // 3; sec.ntris = #sec.idx // 3; return sec end
    local function point(sec, x, y, k)
        local pos, nrm, uv, col = sec.pos, sec.nrm, sec.uv, sec.col
        pos[#pos + 1] = x; pos[#pos + 1] = y; pos[#pos + 1] = 0.0
        nrm[#nrm + 1] = 0; nrm[#nrm + 1] = 0; nrm[#nrm + 1] = 1
        uv[#uv + 1] = x / M.GROUND_TILE; uv[#uv + 1] = y / M.GROUND_TILE
        col[#col + 1] = k; col[#col + 1] = k; col[#col + 1] = k; col[#col + 1] = 1
    end
    local function both(sec, a, b, c)
        local idx = sec.idx
        idx[#idx + 1] = a; idx[#idx + 1] = b; idx[#idx + 1] = c
        idx[#idx + 1] = a; idx[#idx + 1] = c; idx[#idx + 1] = b
    end
    if hole then
        -- (a square with the box's rectangle cut out: four strips round it - near, then the far frame round that)
        local function quad(sec, x0, y0, x1, y1)
            if x1 <= x0 or y1 <= y0 then return end
            local b = #sec.pos // 3
            for _, c in ipairs({ { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 } }) do point(sec, c[1], c[2], 1.0) end
            both(sec, b, b + 1, b + 2)
            both(sec, b, b + 2, b + 3)
        end
        local h = hole
        local n0, n1 = math.min(-RN, h.x0 - 1000.0, h.y0 - 1000.0), math.max(RN, h.x1 + 1000.0, h.y1 + 1000.0)
        -- (the hole just the boxes themselves, not the rectangle round them all: between Tiny-Huge Island's bay and its
        -- cliff, outside any box, the sea stood open down to the dark deep - "black water", 2026-10-31. A grid on every
        -- box's edges; each of its cells sea unless inside a box)
        local boxes = h.boxes or { { x0 = h.x0, x1 = h.x1, y0 = h.y0, y1 = h.y1 } }
        local xs, ys = { n0, n1 }, { n0, n1 }
        for _, b in ipairs(boxes) do
            xs[#xs + 1] = b.x0; xs[#xs + 1] = b.x1
            ys[#ys + 1] = b.y0; ys[#ys + 1] = b.y1
        end
        local function uniq(t)
            table.sort(t)
            local o = {}
            for _, v in ipairs(t) do if v >= n0 and v <= n1 and (#o == 0 or v - o[#o] > 0.5) then o[#o + 1] = v end end
            return o
        end
        xs, ys = uniq(xs), uniq(ys)
        for i = 1, #xs - 1 do
            for j = 1, #ys - 1 do
                local cx, cy = (xs[i] + xs[i + 1]) * 0.5, (ys[j] + ys[j + 1]) * 0.5
                local water = false
                for _, b in ipairs(boxes) do
                    if cx > b.x0 and cx < b.x1 and cy > b.y0 and cy < b.y1 then water = true; break end
                end
                if not water then quad(near, xs[i], ys[j], xs[i + 1], ys[j + 1]) end
            end
        end
        quad(far, -R, -R, n0, R)
        quad(far, n1, -R, R, R)
        quad(far, n0, -R, n1, n0)
        quad(far, n0, n1, n1, R)
        return { finish(near), finish(far) }
    end
    local N = 64
    -- (rings: those out to GROUND_NEAR the near section's, the rest the far one's, the ring between in both)
    local radii = { 0.0, 2000.0, 6000.0, 15000.0, RN, 100000.0, 250000.0, 600000.0, 1200000.0, R }
    local function rings(sec, list, plain)
        local first = 0
        for ri, r in ipairs(list) do
            local n = (r == 0.0) and 1 or N
            for i = 0, n - 1 do
                local a = 2.0 * math.pi * i / N
                -- (a slow wander of light and dark across it, ring by ring - near only, and slight: far off, each of the
                -- 64 wedges round was its own shade, bands standing up to the horizon - "smooth the distance")
                local k = plain and 1.0 or (0.95 + 0.05 * math.sin(a * 3.0 + ri * 1.7) * math.cos(a * 5.0 - ri * 0.9))
                if r >= RN then k = 1.0 end
                point(sec, r * math.cos(a), r * math.sin(a), k)
            end
        end
        local starts, at = {}, 0
        for ri, r in ipairs(list) do starts[ri] = at; at = at + ((r == 0.0) and 1 or N) end
        for ri = 1, #list - 1 do
            local a0, b0 = starts[ri], starts[ri + 1]
            for i = 0, N - 1 do
                local j = (i + 1) % N
                if list[ri] == 0.0 then
                    both(sec, a0, b0 + i, b0 + j)
                else
                    both(sec, a0 + i, b0 + i, b0 + j)
                    both(sec, a0 + i, b0 + j, a0 + j)
                end
            end
        end
    end
    local nl, fl = {}, {}
    for _, r in ipairs(radii) do
        if r <= RN then nl[#nl + 1] = r end
        if r >= RN then fl[#fl + 1] = r end
    end
    rings(near, nl, false)
    rings(far, fl, true)
    return { finish(near), finish(far) }
end

-- the haze over the far ground: rings out to GROUND_R, lifted HAZE_LIFT, its alpha by HAZE_RINGS (solid at the edge)
local function haze_section()
    local N, R = 64, M.GROUND_R
    local pos, nrm, uv, col, idx = {}, {}, {}, {}, {}
    local rings = {}
    for _, h in ipairs(M.HAZE_RINGS) do rings[#rings + 1] = h end
    rings[#rings + 1] = { R, 1.0 }
    for _, rv in ipairs(rings) do
        local r, v = rv[1], rv[2]
        for i = 0, N do
            local a = 2.0 * math.pi * i / N
            pos[#pos + 1] = r * math.cos(a); pos[#pos + 1] = r * math.sin(a); pos[#pos + 1] = M.HAZE_LIFT
            nrm[#nrm + 1] = 0; nrm[#nrm + 1] = 0; nrm[#nrm + 1] = 1
            uv[#uv + 1] = i / N; uv[#uv + 1] = math.max(0.005, math.min(0.995, v))
            col[#col + 1] = 1.0; col[#col + 1] = 1.0; col[#col + 1] = 1.0; col[#col + 1] = 1.0
        end
    end
    local W = N + 1
    for r = 0, #rings - 2 do
        for i = 0, N - 1 do
            local a, b, c, d = r * W + i, r * W + i + 1, (r + 1) * W + i, (r + 1) * W + i + 1
            idx[#idx + 1] = a; idx[#idx + 1] = b; idx[#idx + 1] = c
            idx[#idx + 1] = b; idx[#idx + 1] = d; idx[#idx + 1] = c
            idx[#idx + 1] = a; idx[#idx + 1] = c; idx[#idx + 1] = b
            idx[#idx + 1] = b; idx[#idx + 1] = c; idx[#idx + 1] = d
        end
    end
    return { id = 2, layer = "translucent", texture = M.FADE_TEX, nverts = #pos // 3, ntris = #idx // 3,
             pos = pos, nrm = nrm, uv = uv, col = col, idx = idx }
end

local function build_ground(world, tex, hole, haze)
    local a = lib.spawn_actor(world, { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z }, 0.0)
    if not a then return nil end
    pcall(function() lib.keep[a:GetAddress()] = "sunsky" end)
    pcall(function() a:SetActorEnableCollision(false) end)
    local pmc = lib.add_pmc(a)
    if not pmc then return a end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    local secs = ground_section(tex, hole)
    if haze then secs[#secs + 1] = haze_section() end
    lib.add_sections(world, pmc, secs)
    -- (the haze ring in the horizon's colour, as the dome's band: its own material, the picture's alpha for how much)
    if haze then
        pcall(function()
            local KML = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
            local parent = LoadAsset(M.BLEND)
            local ftex = lib.texture(world, M.FADE_TEX)
            if KML and parent and ftex then
                local mid = KML:CreateDynamicMaterialInstance(world, parent, FName("sunsky_ground_haze"), 0)
                mid:SetTextureParameterValue(FName("BaseColorTexture"), ftex)
                mid:SetVectorParameterValue(FName("BaseColorFactor"), { R = haze[1] ^ 2.2, G = haze[2] ^ 2.2, B = haze[3] ^ 2.2, A = 1.0 })
                pmc:SetMaterial(2, mid)
            end
        end)
    end
    -- (the sea shines where the sun catches it; the sand and the snow hardly)
    for k = 0, 1 do
        pcall(function()
            local m = pmc:GetMaterial(k)
            if m and m:IsValid() then m:SetScalarParameterValue(FName("RoughnessFactor"), M.GROUND_ROUGH[tex] or 0.8) end
        end)
    end
    return a
end

-- the band over the dome's top: a ring from its edge FADE_UP degrees up the sky, the fade picture laid up it (its foot
-- at the dome, clear at its top)
local function fade_section()
    local N, R = 48, M.DOME_R * 0.995
    local pos, nrm, uv, col, idx = {}, {}, {}, {}, {}
    local rings = { M.DOME_TOP, M.DOME_TOP + M.FADE_UP * 0.5, M.DOME_TOP + M.FADE_UP }
    for ri, e in ipairs(rings) do
        local er = math.rad(e)
        for i = 0, N do
            local a = 2.0 * math.pi * i / N
            pos[#pos + 1] = R * math.cos(er) * math.cos(a); pos[#pos + 1] = R * math.cos(er) * math.sin(a); pos[#pos + 1] = R * math.sin(er)
            nrm[#nrm + 1] = 0; nrm[#nrm + 1] = 0; nrm[#nrm + 1] = 1
            uv[#uv + 1] = i / N; uv[#uv + 1] = 0.995 - 0.99 * (ri - 1) / (#rings - 1)
            col[#col + 1] = 1.0; col[#col + 1] = 1.0; col[#col + 1] = 1.0; col[#col + 1] = 1.0
        end
    end
    local W = N + 1
    for r = 0, #rings - 2 do
        for i = 0, N - 1 do
            local a, b, c, d = r * W + i, r * W + i + 1, (r + 1) * W + i, (r + 1) * W + i + 1
            idx[#idx + 1] = a; idx[#idx + 1] = b; idx[#idx + 1] = c
            idx[#idx + 1] = b; idx[#idx + 1] = d; idx[#idx + 1] = c
            idx[#idx + 1] = a; idx[#idx + 1] = c; idx[#idx + 1] = b
            idx[#idx + 1] = b; idx[#idx + 1] = c; idx[#idx + 1] = d
        end
    end
    return { id = 1, layer = "translucent", texture = M.FADE_TEX, nverts = #pos // 3, ntris = #idx // 3,
             pos = pos, nrm = nrm, uv = uv, col = col, idx = idx }
end

local function build_dome(world, def)
    local a = lib.spawn_actor(world, { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z }, 0.0)
    if not a then return nil end
    pcall(function() lib.keep[a:GetAddress()] = "sunsky" end)
    pcall(function() a:SetActorEnableCollision(false) end)
    local pmc = lib.add_pmc(a)
    if not pmc then return a end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    lib.add_sections(world, pmc, { dome_section(def), fade_section() })
    -- (the band in the dome's haze colour: its own material, the picture's alpha for how much)
    pcall(function()
        local KML = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
        local parent = LoadAsset(M.BLEND)
        local tex = lib.texture(world, M.FADE_TEX)
        if KML and parent and tex then
            local mid = KML:CreateDynamicMaterialInstance(world, parent, FName("sunsky_fade"), 0)
            mid:SetTextureParameterValue(FName("BaseColorTexture"), tex)
            local h = def.haze or M.HAZE
            mid:SetVectorParameterValue(FName("BaseColorFactor"), { R = h[1] ^ 2.2, G = h[2] ^ 2.2, B = h[3] ^ 2.2, A = 1.0 })
            pmc:SetMaterial(1, mid)
        end
    end)
    return a
end

-- Ultra Dynamic Sky kept for the clouds: made once in a map (deferred, its settings in before it is built), every part
-- of it that draws or lights hidden at once and again at each level - its sun, moon, sky light, sky, fog, its own cloud
-- layer - its cloud material (which it goes on driving: the parameter collections, the clouds' drift) put on ours.
-- Made for a moment only and taken away, it left the collections short of what it sets as it runs: no clouds.
local function hide_uds(a)
    local cls = StaticFindObject("/Script/Engine.SceneComponent")
    local list = {}
    pcall(function() list = a:K2_GetComponentsByClass(cls) end)
    for _, c in ipairs(list) do
        local o = nil
        pcall(function() o = c:get() end)
        if o and valid(o) then
            pcall(function() o:SetVisibility(false, false) end)
            pcall(function() o:SetHiddenInGame(true, false) end)
        end
    end
    pcall(function() a:SetActorHiddenInGame(true) end)
end

local function ensure_uds(world, cov)
    if not (st and valid(st.cloud)) then return false end
    if not valid(st.uds) then
        local cls = nil
        pcall(function() cls = LoadAsset(M.UDS) end)
        if not (cls and valid(cls)) then return false end
        local GS = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        local xf = { Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z },
                     Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }
        local a = nil
        pcall(function() a = GS:BeginDeferredActorSpawnFromClass(world, cls, xf, 1, nil, 0) end)
        if not (a and valid(a)) then return false end
        for k, v in pairs({ ["Animate Time of Day"] = false, ["Time of Day"] = 1200.0, ["Cloud Coverage"] = cov, ["Fog"] = 0.0,
                            ["Use Volumetric Fog"] = false, ["Enable Volumetric Cloud Light Rays"] = false,
                            ["Render Sky Light"] = false, ["Sun Casts Shadows"] = false }) do
            pcall(function() a[k] = v end)
        end
        pcall(function() GS:FinishSpawningActor(a, xf, 0) end)
        pcall(function() lib.keep[a:GetAddress()] = "sunsky uds" end)
        hide_uds(a)
        st.uds = a
        log("sunsky: Ultra Dynamic Sky up, hidden, for its clouds")
    else
        pcall(function() st.uds["Cloud Coverage"] = cov end)
        hide_uds(st.uds)
    end
    pcall(function() st.uds:SetActorTickEnabled(true) end)
    local mat = nil
    pcall(function() local m = st.uds["Vol Clouds MID Complex"]; if m and valid(m) then mat = m end end)
    if not mat then return false end
    local c = st.cloud.VolumetricCloudComponent
    pcall(function() c:SetMaterial(mat) end)
    pcall(function()
        local vc = st.uds.VolumetricCloud
        if vc and valid(vc) then
            c:SetLayerBottomAltitude(vc.LayerBottomAltitude)
            c:SetLayerHeight(vc.LayerHeight)
        end
    end)
    return true
end

-- the soft lights all round (menu.lua's 3rd to 6th) under the open sky: SKY_AMB times what sky.lua gave them
local function sky_amb(on)
    local env = env_here()
    if not (env and env.lights and st) then return end
    if not on then
        if st.amb then
            st.amb = nil
            local SKY = package.loaded["sky"]
            if SKY and SKY.relight then pcall(SKY.relight) end
        end
        return
    end
    local l3 = env.lights[3]
    if not valid(l3) then return end
    local cur = 0.0
    pcall(function() cur = l3.LightComponent.Intensity end)
    -- (sky.lua's own strength: what it is now, unless that is ours from before - the same sky leaves them as they were)
    local base = cur
    if st.amb and math.abs(cur - st.amb.val) < 0.001 then base = st.amb.base end
    local val = base * M.SKY_AMB
    for i = 3, #env.lights do
        local l = env.lights[i]
        if valid(l) then
            pcall(function()
                l.LightComponent:SetIntensity(val)
                l.LightComponent:SetLightColor(M.SKY_AMB_TINT, true)
            end)
        end
    end
    st.amb = { base = base, val = val }
end

-- the lights' part in the god-ray fog
local function rays_light(on)
    local env = env_here()
    for i, l in ipairs((env and env.lights) or {}) do
        pcall(function() l.LightComponent:SetVolumetricScatteringIntensity(on and ((i == 1) and M.RAYS_SUN or 0.0) or 1.0) end)
    end
    if st and valid(st.sun) then pcall(function() st.sun.LightComponent:SetVolumetricScatteringIntensity(0.0) end) end
end

-- the level's sun and the sky's: the sky's turned as the level's, SKY_SUN times as strong, the rays its
local function suns(on)
    local env = env_here()
    local sun = env and env.lights and env.lights[1]
    if valid(sun) then
        pcall(function()
            local lc = sun.LightComponent
            lc:SetAtmosphereSunLight(false)
            lc:SetEnableLightShaftBloom(false)
            lc:SetEnableLightShaftOcclusion(false)
        end)
    end
    if not (st and valid(st.sun)) then return end
    if not on then pcall(function() st.sun:SetActorHiddenInGame(true); st.sun.LightComponent:SetVisibility(false, false) end); return end
    pcall(function()
        local lc = st.sun.LightComponent
        local lux = 24.0
        -- (movable first: turned before, it did not hold - menu.lua's sun the same)
        lc:SetMobility(2)
        if valid(sun) then
            local r = sun:K2_GetActorRotation()
            st.sun:K2_SetActorRotation({ Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll }, false)
            lux = math.max(sun.LightComponent.Intensity, 1.0) * M.SKY_SUN
        end
        lc:SetLightingChannels(false, false, true)
        lc:SetCastShadows(false)
        lc:SetSpecularScale(0.0)
        lc:SetIntensity(lux)
        lc:SetAtmosphereSunLight(true)
        lc:SetEnableLightShaftBloom(true)
        lc:SetBloomScale(M.SHAFT_BLOOM)
        lc:SetBloomThreshold(M.SHAFT_THRESHOLD)
        lc:SetEnableLightShaftOcclusion(true)
        lc:SetOcclusionMaskDarkness(M.SHAFT_DARK)
        st.sun:SetActorHiddenInGame(false)
        lc:SetVisibility(true, false)
    end)
end

local function picture_sky(show)
    local env = env_here()
    if env and valid(env.sky) then pcall(function() env.sky:SetActorHiddenInGame(not show) end) end
end

local function hide_all()
    if not st then return end
    st.on = false
    for _, k in ipairs({ "atmo", "cloud", "dome", "ground", "deep" }) do
        if valid(st[k]) then pcall(function() st[k]:SetActorHiddenInGame(true) end) end
    end
    if valid(st.skyl) then pcall(function() st.skyl.LightComponent:SetVisibility(false, false) end) end
end

function M.apply(sky, scene)
    local world = lib.world()
    if not world then return end
    local addr = world:GetAddress()
    if st and st.world ~= addr then st = nil end              -- (a gone map's are gone with it, untouched)
    local G = package.loaded["game"]
    local def = M.SKIES[sky or ""]
    local want = lib.R96 and not M.picture_sky() and def ~= nil and not (G and G.CAVES and G.CAVES[scene or ""])
    local FOG = package.loaded["fog"]
    if FOG and FOG.rays then FOG.rays(want) end
    if not want then
        hide_all()
        suns(false)
        rays_light(false)
        sky_amb(false)
        picture_sky(true)
        -- (its clouds' driver resting, still hidden)
        if st and valid(st.uds) then
            hide_uds(st.uds)
            pcall(function() st.uds:SetActorTickEnabled(false) end)
        end
        return
    end
    if not st then
        st = { world = addr, uds = kept_uds }
        kept_uds = nil
        st.atmo = spawn(world, "/Script/Engine.SkyAtmosphere", OFFSET.Z)
        st.cloud = spawn(world, "/Script/Engine.VolumetricCloud", OFFSET.Z)
        st.sun = spawn(world, "/Script/Engine.DirectionalLight", OFFSET.Z + 5000.0)
        st.skyl = spawn(world, "/Script/Engine.SkyLight", OFFSET.Z + 2000.0)
        if valid(st.skyl) then
            pcall(function()
                local c = st.skyl.LightComponent
                c:SetMobility(2)                    -- (movable first: a static one takes nothing after)
                c.bRealTimeCapture = true
                c.SourceType = 0                    -- (the scene as drawn: the sky, its clouds)
                c:SetIntensity(M.SKY_LIGHT)
                -- (under the horizon a dim sea-blue, not black: the water's ripples mirror a little of it)
                c.bLowerHemisphereIsBlack = false
                c.LowerHemisphereColor = M.SKY_LOW
            end)
        end
        log("sunsky: sky of the air %s, clouds %s, sky's sun %s", tostring(valid(st.atmo)), tostring(valid(st.cloud)),
            tostring(valid(st.sun)))
    end
    -- (the dome made again for each sky: its colours are the sky's)
    if st.sky ~= sky or not valid(st.dome) then
        if valid(st.dome) then pcall(function() lib.keep[st.dome:GetAddress()] = nil; st.dome:K2_DestroyActor() end) end
        st.dome = build_dome(world, def)
    end
    -- (the sky's ground under the level - its planet's top at the actor - and the clouds over it)
    -- (the sea of cloud just under the level: its ground put so that the clouds' top is CLOUD_UNDER under the lowest floor)
    local dground = def.ground
    if def.under and G and G.floor and G.floor.min_z then
        local top = M.CLOUD_TOP
        pcall(function()
            local vc = st and st.uds and st.uds.VolumetricCloud
            if vc and valid(vc) then top = (vc.LayerBottomAltitude + vc.LayerHeight) * 100000.0 end
        end)
        dground = math.max(0.0, top + M.CLOUD_UNDER - G.floor.min_z)
    end
    local gz = OFFSET.Z - dground
    if valid(st.atmo) then
        pcall(function()
            st.atmo:K2_SetActorLocation({ X = OFFSET.X, Y = OFFSET.Y, Z = gz }, false, {}, true)
            local c = st.atmo.SkyAtmosphereComponent
            c.TransformMode = 1                                   -- (PlanetTopAtComponentTransform)
            c:MarkRenderStateDirty()
        end)
    end
    if valid(st.cloud) then
        pcall(function() st.cloud:K2_SetActorLocation({ X = OFFSET.X, Y = OFFSET.Y, Z = gz }, false, {}, true) end)
        if ensure_uds(world, def.coverage) then
            if st.coverage ~= def.coverage then log("sunsky: Ultra Dynamic Sky's clouds, coverage %.1f", def.coverage) end
            st.coverage = def.coverage
        else
            if not st.stock then
                st.stock = true
                local mat = nil
                pcall(function() mat = LoadAsset(M.CLOUD_MAT) end)
                if mat then pcall(function() st.cloud.VolumetricCloudComponent:SetMaterial(mat) end) end
                log("sunsky: Ultra Dynamic Sky's clouds not had - the engine's own")
            end
        end
    end
    for _, k in ipairs({ "atmo", "cloud", "dome" }) do
        if valid(st[k]) then pcall(function() st[k]:SetActorHiddenInGame(false) end) end
    end
    -- (the ground: made again when its picture changes, put under this level's lowest floor)
    local gtex = M.GROUND_TEX[sky or ""]
    -- (a level in the sea: its biggest water box, the sea's hole and height)
    local hole = nil
    if M.SEA_LEVEL[scene or ""] and G then
        -- (the boxes at one height together - Tiny-Huge Island's sea is two strips, an L round the island; a pond up the
        -- hill another - the height with the most water the sea, the hole round all of its boxes)
        local groups = {}
        for _, b in ipairs(G.water_rects or {}) do
            if b.x0 and b.z then
                local g = nil
                for _, h in ipairs(groups) do if math.abs(h.z - b.z) < 5.0 then g = h end end
                if not g then g = { z = b.z, area = 0.0, x0 = b.x0, x1 = b.x1, y0 = b.y0, y1 = b.y1, boxes = {} }; groups[#groups + 1] = g end
                g.area = g.area + (b.x1 - b.x0) * (b.y1 - b.y0)
                g.boxes[#g.boxes + 1] = { x0 = b.x0, x1 = b.x1, y0 = b.y0, y1 = b.y1 }
                g.x0, g.x1 = math.min(g.x0, b.x0), math.max(g.x1, b.x1)
                g.y0, g.y1 = math.min(g.y0, b.y0), math.max(g.y1, b.y1)
            end
        end
        for _, g in ipairs(groups) do if not hole or g.area > hole.area then hole = g end end
    end
    local gkey = tostring(gtex) .. (hole and string.format(":%.0f:%.0f:%.0f:%.0f:%d", hole.x0, hole.x1, hole.y0, hole.y1, #(hole.boxes or {})) or "")
    if gkey ~= st.gkey or not valid(st.ground) then
        if valid(st.ground) then pcall(function() lib.keep[st.ground:GetAddress()] = nil; st.ground:K2_DestroyActor() end) end
        st.ground, st.gtex, st.gkey = gtex and build_ground(world, gtex, hole, def.haze or M.HAZE) or nil, gtex, gkey
    end
    if valid(st.ground) then
        local low = (G and G.floor and G.floor.min_z) or -6000.0
        -- (under the level - or, over the sea of cloud, at the sky's ground under the clouds)
        local gzz = math.min(low - M.GROUND_DOWN, -dground)
        if hole then gzz = hole.z - 10.0 end
        pcall(function()
            st.ground:K2_SetActorLocation({ X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z + gzz }, false, {}, true)
            st.ground:SetActorHiddenInGame(false)
        end)
        -- (and, under a sea level's own water where it has no bed - seen through it, the sky's dome below - the deep sea:
        -- the whole disc 20 m under its lowest floor)
        if hole then
            if not valid(st.deep) then st.deep = build_ground(world, gtex, nil) end
            if valid(st.deep) then
                pcall(function()
                    st.deep:K2_SetActorLocation({ X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z + low - M.GROUND_DOWN }, false, {}, true)
                    st.deep:SetActorHiddenInGame(false)
                end)
            end
        elseif valid(st.deep) then
            pcall(function() st.deep:SetActorHiddenInGame(true) end)
        end
    end
    -- (the clouds take the planet from the sky of the air when they are made: made before its ground was put under the
    -- level - or moved after - they lay 3 km down, under the sea, and the sky was empty till the level was left and come
    -- back to. Both hidden a moment and shown again, a little after: made anew on the right planet - M.tick)
    if st.gz ~= gz or not st.kicked then st.gz, st.kick, st.kick_at, st.kicked = gz, 2, os.clock() + 0.5, true end
    st.on, st.sky = true, sky
    if valid(st.skyl) then
        pcall(function()
            local c = st.skyl.LightComponent
            c:SetIntensity(M.SKY_LIGHT)
            c:SetVisibility(true, false)
            c:RecaptureSky()
        end)
    end
    suns(true)
    rays_light(true)
    sky_amb(true)
    picture_sky(false)
    log("sunsky: %s (%s) - Unreal's sky, clouds and the sun's rays", tostring(scene), tostring(sky))
end

-- Every frame (game.lua): Ultra Dynamic Sky makes its cloud material anew in its first moments (its start-up), so the one
-- put on our clouds as it was made went stale - no clouds till the level was left and come back to. Its current one
-- looked at once a second and put on when it changes.
function M.tick(dt)
    if not (st and st.on) then return end
    if st.kick and os.clock() >= st.kick_at then
        local hide = st.kick == 2
        for _, k in ipairs({ "atmo", "cloud" }) do
            if valid(st[k]) then pcall(function() st[k]:SetActorHiddenInGame(hide) end) end
        end
        if hide then st.kick, st.kick_at = 1, os.clock() + 0.2 else st.kick = nil; log("sunsky: sky and clouds made anew on their ground") end
    end
    if not st.uds then return end
    st.look_t = (st.look_t or 0.0) - (dt or 0.016)
    if st.look_t > 0.0 then return end
    st.look_t = 1.0
    if not (valid(st.uds) and valid(st.cloud)) then return end
    local m = nil
    pcall(function() local x = st.uds["Vol Clouds MID Complex"]; if x and valid(x) then m = x end end)
    if not m then return end
    local addr = nil
    pcall(function() addr = m:GetAddress() end)
    if addr and addr ~= st.mid_addr then
        st.mid_addr = addr
        pcall(function() st.cloud.VolumetricCloudComponent:SetMaterial(m) end)
        log("sunsky: Ultra Dynamic Sky's cloud material put on (again)")
    end
end

function M.forget() st = nil end

-- the switch turned: kept, and the sky put up again for the level he is in
function M.set_picture_sky(on)
    on = on and true or false
    if M.picture_sky() == on then return end
    M.PICTURE = on
    local f = io.open(BG_FILE, "w")
    if f then
        f:write("-- SM64Map: MARIO SETTINGS' BACKGROUND (written by the mod)\nreturn { picture = ", tostring(on), " }\n")
        f:close()
    end
    local SKY, G = package.loaded["sky"], package.loaded["game"]
    if SKY and G and G.name then
        local ok, err = pcall(M.apply, SKY.current, G.name)
        if not ok then log("background: %s", tostring(err)) end
    end
    log("background: %s", on and "Mario 64's" or "clouds")
end
function M.debug() return st end

return M
