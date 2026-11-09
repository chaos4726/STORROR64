-- SM64Map: Mario 64's fog, in the scenes that have it.
--
-- Mario 64 fogs the display lists of a few areas (G_FOG with gsDPSetFogColor and gsSPFogPosition / gsSPFogFactor in
-- levels/*/model.inc.c): Hazy Maze Cave, the pyramid, the volcano, the slide inside Tall, Tall Mountain, the Princess's
-- Secret Slide, the Cavern of the Metal Cap - all to black, the colour behind them - Tick Tock Clock to its pale cyan,
-- Bowser's fire sea arena to red, and Bob-omb Battlefield's ground to grey. N64 fog runs from fogMin to fogMax of the depth range (0..1000), which with the
-- area's near and far planes (GEO_CAMERA_FRUSTUM) is a distance where it starts and one where it is half: each scene's
-- start and density here are fitted to those (an exponential height fog that does not thin with height), and it stops
-- short of the sky cylinder (radius 4 km), which keeps its own picture. ("adding upgrading and improving", 2026-10-18.)
local lib = require("lib")
local log = lib.log

local M = { enabled = true }

local OFFSET = lib.OFFSET
local function lin(c) return (c / 255.0) ^ 2.2 end
local BLACK = { 0.0, 0.0, 0.0 }
-- start (cm), density (UE's: per 1000 cm), colour (linear)
--   (960, 1000), far 12800: from 1579 cm, half by 2712 cm
--   (980, 1000), far 12800: from 2712 cm, half by 4229 cm
--   (900, 1000), far 12800: from 701 cm, half by 1306 cm
--   (960, 1000), far 20000: from 1674 cm, half by 3012 cm
local A = { start = 1579.0, density = 0.61 }
local B = { start = 2712.0, density = 0.46 }
M.SCENES = {
    hmc = { A, BLACK }, ssl_2 = { A, BLACK }, lll_2 = { A, BLACK },
    ttm_2 = { B, BLACK }, ttm_3 = { B, BLACK }, ttm_4 = { B, BLACK }, pss = { B, BLACK }, cotmc = { B, BLACK },
    -- (Tick Tock Clock's pale cyan, thinned: Mario 64's own, from 7 m and half by 13 m, hid the clock's gears and
    -- platforms over him - "whys it so foggy in tictok clock?", "fix that", 2026-11-04. From 30 m, half by about 50 m)
    ttc = { { start = 3000.0, density = 0.35 }, { lin(200), lin(255), lin(255) } },
    bowser_2 = { { start = 1674.0, density = 0.52 }, { lin(200), lin(50), 0.0 } },
    -- (Bob-omb Battlefield's whole ground, grey, (980, 1000) with its far plane 30000: from 3224 cm, half by 5639 cm -
    -- the haze over its far side. Taken off: "yes remove the fog", 2026-10-30, with its sun shadows baked in)
    -- bob = { { start = 3224.0, density = 0.29 }, { lin(160), lin(160), lin(160) } },
}
local CUTOFF = 350000.0
-- Under the water (only while the camera is): Jolly Roger Bay fogs its underwater pieces teal. Mario 64's own (dark
-- teal 5/80/75, from 7 m, half by 13 m) came out as a near-black murk here, under underwater.lua's blue tint on top -
-- "we have to fix the fog in sunken bay", 2026-10-18: a lighter blue-green that thickens more slowly (half by about
-- 26 m), so the sunken ship can be made out from across the bay; faded in and out with the tint, not switched.
M.WATER = { jrb = { { start = 900.0, density = 0.40 }, { lin(70), lin(150), lin(150) } } }
M.WATER_FADE = 5.0                  -- of the way a second (underwater.lua's FADE)
local water = { w = 0.0, at = nil, scene = nil }

local st = nil              -- { actor, comp, world, scene }

-- God rays (RENDER 96's daytime skies, sunsky.lua M.rays): where a scene has no fog of its own, a thin one with the
-- engine's volumetric fog in it, through which the level's sun - its shadows - shows its beams: through the trees, past
-- the towers and the ledges ("also add god rays to the sun", 2026-10-31). Its plain fog is a faint haze; the volumetric
-- part is what the sun lights. Off under the water (the water fog in its place) and wherever the scene has its own.
M.RAYS = { density = 0.0012, start = 0.0, color = { 0.55, 0.68, 0.82 }, extinction = 6.0, albedo = 1.0,
           phase = 0.75, distance = 9000.0, cutoff = 2600000.0 }
-- (cutoff: past the ground far under the level - sunsky.lua's 25 km - which it hazes into the horizon; short of the dome)
M.rays_on = false
function M.rays(on) M.rays_on = on and true or false end
local function set_rays(c)
    local r = M.RAYS
    pcall(function() c:SetFogHeightFalloff(0.00001) end)
    pcall(function() c:SetFogDensity(r.density) end)
    pcall(function() c:SetStartDistance(r.start) end)
    pcall(function() c:SetFogMaxOpacity(0.6) end)
    pcall(function() c:SetFogCutoffDistance(r.cutoff or CUTOFF) end)
    pcall(function() c:SetFogInscatteringColor({ R = r.color[1], G = r.color[2], B = r.color[3], A = 1.0 }) end)
    pcall(function() c:SetDirectionalInscatteringColor({ R = 0.0, G = 0.0, B = 0.0, A = 1.0 }) end)
    pcall(function() c:SetInscatteringColorCubemap(nil) end)
    pcall(function() c.SkyAtmosphereAmbientContributionColorScale = { R = 0.0, G = 0.0, B = 0.0, A = 1.0 } end)
    pcall(function() c:SetVolumetricFog(true) end)
    pcall(function() c:SetVolumetricFogScatteringDistribution(r.phase) end)
    pcall(function() c:SetVolumetricFogExtinctionScale(r.extinction) end)
    pcall(function() c:SetVolumetricFogAlbedo({ R = 255, G = 255, B = 255, A = 255 }) end)
    pcall(function() c:SetVolumetricFogDistance(r.distance) end)
    pcall(function() c:SetVolumetricFogEmissive({ R = 0.0, G = 0.0, B = 0.0, A = 1.0 }) end)
    pcall(function() c:MarkRenderStateDirty() end)
    pcall(function() c:SetVisibility(true, false) end)
end

local function valid(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

local function make(world)
    local cls = StaticFindObject("/Script/Engine.ExponentialHeightFogComponent")
    if not (cls and cls:IsValid()) then return nil end
    local a = lib.spawn_actor(world, { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z }, 0.0)
    if not a then return nil end
    pcall(function() lib.keep[a:GetAddress()] = "fog" end)
    local c = a:AddComponentByClass(cls, false, { Translation = { X = 0, Y = 0, Z = 0 }, Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
    if not valid(c) then return nil end
    return { actor = a, comp = c, world = world:GetAddress() }
end

local function set(c, spec, col)
    local p = spec
    pcall(function() c:SetFogHeightFalloff(0.00001) end)
    pcall(function() c:SetFogDensity(p.density) end)
    pcall(function() c:SetStartDistance(p.start) end)
    pcall(function() c:SetFogMaxOpacity(1.0) end)
    pcall(function() c:SetFogCutoffDistance(CUTOFF) end)
    pcall(function() c:SetFogInscatteringColor({ R = col[1], G = col[2], B = col[3], A = 1.0 }) end)
    pcall(function() c:SetDirectionalInscatteringColor({ R = 0.0, G = 0.0, B = 0.0, A = 1.0 }) end)
    pcall(function() c:SetVolumetricFog(false) end)
    -- (nothing of a sky's light or a cubemap in it: its colour is Mario 64's alone)
    pcall(function() c:SetInscatteringColorCubemap(nil) end)
    pcall(function() c.SkyAtmosphereAmbientContributionColorScale = { R = 0.0, G = 0.0, B = 0.0, A = 1.0 } end)
    pcall(function() c:MarkRenderStateDirty() end)
    pcall(function() c:SetVisibility(true, false) end)
end

-- the camera under the water or not (game.lua, every frame, beside underwater.lua): the scene's water fog faded in or out
function M.water(scene, under)
    local spec = M.enabled and M.WATER[scene or ""] or nil
    local now = os.clock()
    local dt = water.at and math.min(0.1, now - water.at) or 0.0
    water.at = now
    if not spec then
        if water.w > 0.0 then water.w = 0.0; M.apply(scene) end
        return
    end
    local want = under and 1.0 or 0.0
    if water.w == want then return end
    if want > water.w then water.w = math.min(want, water.w + M.WATER_FADE * dt)
    else water.w = math.max(want, water.w - M.WATER_FADE * dt) end
    if water.w <= 0.0 then M.apply(scene); return end          -- (back to the scene's own, or none)
    local world = lib.world()
    if not world then return end
    if st and (st.world ~= world:GetAddress() or not valid(st.comp)) then st = nil end
    if not st then st = make(world) end
    if not st then return end
    if not st.on or st.water ~= scene then
        set(st.comp, spec[1], spec[2])
        st.on, st.water = true, scene
    end
    pcall(function() st.comp:SetFogDensity(spec[1].density * water.w) end)
end

-- the scene's fog, or none
function M.apply(scene)
    if st then st.water = nil end
    local world = lib.world()
    if not world then return end
    if st and (st.world ~= world:GetAddress() or not valid(st.comp)) then st = nil end
    local spec = M.enabled and M.SCENES[scene or ""] or nil
    if not spec and M.rays_on and scene then
        if not st then st = make(world) end
        if not st then return end
        set_rays(st.comp)
        st.on = true
        log("fog: %s - the thin fog of the sun's rays", tostring(scene))
        return
    end
    if not spec then
        if st and st.on then
            st.on = false
            pcall(function() st.comp:SetVolumetricFog(false) end)
            pcall(function() st.comp:SetVisibility(false, false) end)
            log("fog: off")
        end
        return
    end
    if not st then st = make(world) end
    if not st then log("fog: no fog component"); return end
    set(st.comp, spec[1], spec[2])
    st.on = true
    log("fog: %s (from %.0f cm, density %.2f)", tostring(scene), spec[1].start, spec[1].density)
end

function M.forget() st = nil; water.w, water.at = 0.0, nil end

return M
