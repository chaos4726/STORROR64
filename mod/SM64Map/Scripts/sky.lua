-- SM64Map skies: every level under the sky Mario 64 gives it.
--
-- A scene names its sky ("water", "bbh", "bitfs", ...; or "color_XXXX" for the flat background colour of
-- indoor levels). The pictures are textures/sky_<name>.png, put back together from the player's own ROM
-- by the exporter. The sky itself is the one big cylinder the menu builds; only its picture changes, and
-- with it how bright and what colour the two lights on the athlete are, so that he does not stand in
-- noon sunshine inside a haunted house.
local lib = require("lib")
local log = lib.log
local M = { current = nil, actor = nil }

-- sun strength, fill strength, tint of both
local MOOD = {
    water = { 6.0, 2.5, { 1.0, 1.0, 1.0 } },
    ssl = { 6.5, 2.5, { 1.0, 0.97, 0.9 } },
    cloud_floor = { 6.0, 2.8, { 1.0, 1.0, 1.0 } },
    clouds = { 5.5, 2.8, { 1.0, 1.0, 1.0 } },
    wdw = { 5.0, 2.5, { 0.95, 0.98, 1.0 } },
    ccm = { 4.2, 3.0, { 0.86, 0.93, 1.0 } },
    bbh = { 1.1, 1.5, { 0.6, 0.7, 1.0 } },
    bidw = { 1.5, 1.7, { 0.7, 1.0, 0.82 } },
    -- (Bowser in the Sky and the last fight: brighter - its arena, dark stone with green veins, all but black under
    -- 1.7 with real-time shadows: "especially so for the final bowser", 2026-10-31)
    bits = { 3.4, 2.8, { 0.96, 0.84, 1.0 } },
    bitfs = { 2.4, 1.6, { 1.0, 0.72, 0.5 } },
}
local INDOORS = { 2.4, 2.2, { 1.0, 0.96, 0.9 } }
M.FILL_LIT = 1.25           -- the fill with real-time shadows, of its mood's strength
M.AMB_LIT = 0.36            -- each soft light all round with real-time shadows, of the fill's mood strength

local function valid(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

-- Put up sky `name` (nil = the ocean sky the menu starts with).
function M.apply(name)
    name = name or "water"
    local env = _G.MENU and _G.MENU.env
    -- (only a sky of this map: one of a map that has gone is not to be touched)
    local here = nil
    pcall(function() here = lib.world():GetAddress() end)
    if not (env and env.world == here) then return false end
    local sky = env.sky
    if not valid(sky) then return false end
    local addr = sky:GetAddress()
    if M.current == name and M.actor == addr then return true end
    local world = lib.world()
    local ok, err = pcall(function()
        local pmc = nil
        for _, c in ipairs(sky:K2_GetComponentsByClass(StaticFindObject("/Script/ProceduralMeshComponent.ProceduralMeshComponent"))) do
            pmc = c:get()
        end
        -- (the sphere's band, then its top and bottom domes: menu.lua build_sky; the domes' pictures from
        -- exporter/skycapx.py, or the band's own for a sky without them)
        local mid = pmc and lib.get_mid(world, "opaque", "sky_" .. name)
        if mid then pmc:SetMaterial(0, mid) end
        for sec, part in ipairs({ "_top", "_bottom" }) do
            local has = lib.texture(world, "sky_" .. name .. part)
            local m2 = pmc and ((has and lib.get_mid(world, "opaque", "sky_" .. name .. part)) or mid)
            if m2 then pmc:SetMaterial(sec, m2) end
        end
    end)
    if not ok then log("sky %s: %s", name, tostring(err)) end
    local mood = MOOD[name] or (name:find("^color_") and INDOORS) or MOOD.water
    for i, l in ipairs(env.lights or {}) do
        pcall(function()
            local lc = l.LightComponent
            -- (with the levels lit - game.lua G.LIT_LEVELS - the fill, low over the ground - menu.lua M.FILL_PITCH -
            -- lights the walls in shade, and the soft lights all round - menu.lua M.AMBIENT_ROTS - lift every shade, on
            -- the ground, the walls and the ceilings alike: too strong, his real shadow showed only faintly; too weak,
            -- "the shadows are quite dark", 2026-10-30 - M.FILL_LIT, M.AMB_LIT. Unlit levels: the fill as it always
            -- was, none all round.)
            local G = package.loaded["game"]
            local lit = G and G.LIT_LEVELS
            local v
            if i == 1 then v = mood[1]
            elseif i == 2 then v = mood[2] * (lit and M.FILL_LIT or 1.0)
            else v = lit and mood[2] * M.AMB_LIT or 0.0 end
            lc:SetIntensity(v)
            lc:SetLightColor({ R = mood[3][1], G = mood[3][2], B = mood[3][3], A = 1.0 }, true)
        end)
    end
    M.current, M.actor = name, addr
    log("sky: %s", name)
    return true
end

-- the lights put again as the sky has them (real-time shadows turned: the fill's strength goes with them)
function M.relight()
    local name = M.current
    M.current = nil
    return M.apply(name)
end

return M
