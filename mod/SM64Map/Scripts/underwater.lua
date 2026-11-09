-- SM64Map: under the water the picture turns blue.
--
-- Whenever the camera itself is below the surface of a level's water (not just the athlete), a post-process
-- volume covering the whole world tints the picture blue and darkens its edges a little; it fades in and out
-- over a fraction of a second as the camera dips under or comes up.
local lib = require("lib")
local log = lib.log
local M = {}

local TINT = { R = 0.42, G = 0.72, B = 1.30, A = 1.0 }   -- colour the scene is multiplied by
local VIGNETTE = 0.75
local FADE = 5.0                                           -- of the way in or out, a second

local vol, vol_world, weight = nil, nil, 0.0

local function valid(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

local function ensure()
    local world = lib.world()
    if not world then return nil end
    local addr = world:GetAddress()
    if vol and vol_world == addr and valid(vol) then return vol end
    vol, weight = nil, 0.0
    local v = world:SpawnActor(StaticFindObject("/Script/Engine.PostProcessVolume"), { X = 0.0, Y = 0.0, Z = 0.0 },
        { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
    if not valid(v) then return nil end
    pcall(function() lib.keep[v:GetAddress()] = true end)
    local ok, err = pcall(function()
        v.bUnbound = true
        v.Priority = 1000.0
        v.BlendWeight = 0.0
        local s = v.Settings
        s.bOverride_SceneColorTint = true
        s.SceneColorTint = TINT
        s.bOverride_VignetteIntensity = true
        s.VignetteIntensity = VIGNETTE
    end)
    if not ok then log("underwater: %s", tostring(err)) end
    vol, vol_world = v, addr
    return vol
end

-- Every tick of a level: `under` is whether the camera is below the water.
function M.update(dt, under)
    local want = under and 1.0 or 0.0
    if weight == want and not under then return end         -- (nothing made until it is first needed)
    local v = ensure()
    if not v then return end
    local step = FADE * (dt or 0.0)
    if weight < want then weight = math.min(want, weight + step) else weight = math.max(want, weight - step) end
    pcall(function() v.BlendWeight = weight end)
end

-- Out of the level: the picture clear at once.
function M.clear()
    weight = 0.0
    -- (a volume of a map that has gone is only forgotten: touching it can bring the game down)
    local here = nil
    pcall(function() here = lib.world():GetAddress() end)
    if vol and vol_world ~= here then vol, vol_world = nil, nil; return end
    if valid(vol) then pcall(function() vol.BlendWeight = 0.0 end) end
end

return M
