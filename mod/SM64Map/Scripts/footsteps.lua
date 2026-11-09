-- SM64Map: the athlete's footsteps loud enough to be heard.
--
-- STORROR plays each step itself (SoundComponent:PlayPlayerSound(5, volume) - the volume becomes its FootstepsChannel's
-- volume) and works the volume out from his speed alone: 0.04 at a full run on the mod's floors, whatever their
-- surface type. Measured at the game's own audio output (tools/peak.ps1): a run's steps peaked at 0.013 against the
-- level music's 0.03, a coin's 0.125 and a landing's 0.1 - buried under the music ("still no footstep sounds",
-- 2026-10-15). Mario 64's steps are heard over its music, so each step's volume is taken up GAIN times before STORROR
-- plays it: 0.03 - 0.06, just over the music and under the coins and landings. ("adding upgrading and improving",
-- 2026-10-18.)
local lib = require("lib")

-- (STEP_GAIN, not GAIN: the hook of the first version, still registered in a running game, reads GAIN and does nothing
-- without it)
local M = { STEP_GAIN = 3.5 }
-- STORROR's own step volume came out 0 for every step - running at 580 cm/s in first person, 2026-10-22: "footsteps be
-- cutting out sometimes". A step is never quieter than his speed's: OWN_SLOW at a walk (and turning on the spot), up to
-- OWN_FAST at a full run (RUN cm/s) - the 0.03 - 0.06 STORROR's own came to once taken up.
local OWN_SLOW, OWN_FAST, RUN = 0.03, 0.06, 600.0
function M.step_volume(v)
    local own = OWN_SLOW
    pcall(function()
        local vel = lib.pawn():GetVelocity()
        local sp = math.sqrt(vel.X * vel.X + vel.Y * vel.Y)
        own = OWN_SLOW + (OWN_FAST - OWN_SLOW) * math.max(0.0, math.min(1.0, (sp - 100.0) / (RUN - 100.0)))
    end)
    return math.min(1.0, math.max((v or 0.0) * (M.STEP_GAIN or 1.0), own))
end

local FOOTSTEP = 5                      -- (PlayPlayerSound's sound kind for a step; landings are 7)
local tried = 0.0

-- What the floor under him sounds of, Mario 64's way: the scene's own (game.lua G.SURFACE_OF, every floor made with
-- it) unless the floor triangle under his feet is one of data/surfaces.lua's (tools/surfx.py: its surface type and
-- the area's terrain, mario_get_terrain_sound_addend) - Bob-omb Battlefield's stone paths among its grass, Big Boo's
-- Haunt's stone among its boards, the sea beds' sand. That floor's piece of the level is given that surface type, so
-- STORROR's next step there sounds of it.
local OFFSET = lib.OFFSET
local CELL = 400.0
local sdata = nil
local scene, grid, tris = nil, nil, nil
local acc = 0.0
local last_pmc, last_kind = nil, nil

local function build(name)
    scene, grid, tris = name, nil, nil
    if sdata == nil then sdata = lib.load_data("data.surfaces") or false end
    local t = sdata and sdata[name]
    if not t then return end
    grid, tris = {}, t
    for i = 1, #t, 10 do
        local x0, x1 = math.min(t[i], t[i + 3], t[i + 6]), math.max(t[i], t[i + 3], t[i + 6])
        local y0, y1 = math.min(t[i + 1], t[i + 4], t[i + 7]), math.max(t[i + 1], t[i + 4], t[i + 7])
        for ix = math.floor(x0 / CELL), math.floor(x1 / CELL) do
            for iy = math.floor(y0 / CELL), math.floor(y1 / CELL) do
                local k = ix * 100000 + iy
                local l = grid[k]
                if not l then l = {}; grid[k] = l end
                l[#l + 1] = i
            end
        end
    end
end

-- the listed floor right under (x, y) at height fz (within 25 cm of it), or nil
local function kind_at(x, y, fz)
    local l = grid and grid[math.floor(x / CELL) * 100000 + math.floor(y / CELL)]
    if not l then return nil end
    local t = tris
    for _, i in ipairs(l) do
        local ax, ay, az, bx, by, bz, cx, cy, cz = t[i], t[i + 1], t[i + 2], t[i + 3], t[i + 4], t[i + 5], t[i + 6], t[i + 7], t[i + 8]
        local d1 = (bx - ax) * (y - ay) - (by - ay) * (x - ax)
        local d2 = (cx - bx) * (y - by) - (cy - by) * (x - bx)
        local d3 = (ax - cx) * (y - cy) - (ay - cy) * (x - cx)
        if (d1 >= 0 and d2 >= 0 and d3 >= 0) or (d1 <= 0 and d2 <= 0 and d3 <= 0) then
            local ux, uy, uz = bx - ax, by - ay, bz - az
            local vx, vy, vz = cx - ax, cy - ay, cz - az
            local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            if math.abs(nz) > 1e-6 then
                local h = az - (nx * (x - ax) + ny * (y - ay)) / nz
                if math.abs(h - fz) < 25.0 then return t[i + 9] end
            end
        end
    end
    return nil
end

local function floor_sound(dt, pawn)
    local G = package.loaded["game"]
    if not (G and G.name and pawn) then return end
    acc = acc - dt
    if acc > 0.0 then return end
    acc = 0.1
    if G.name ~= scene then build(G.name); last_pmc, last_kind = nil, nil end
    local base = nil
    pcall(function() base = pawn.BasedMovement.MovementBase end)
    if not (base and base:IsValid()) then return end
    -- (only the level's own floor - its scene actor's: a moving platform keeps the scene's sound, not that of the
    -- floor far under it)
    local own = false
    pcall(function() own = G.scene_actor ~= nil and base:GetOwner():GetAddress() == G.scene_actor:GetAddress() end)
    if not own then return end
    local pm = nil
    pcall(function() pm = base.BodyInstance.PhysMaterialOverride end)
    if not (pm and pm:IsValid() and pm:GetFName():ToString():find("SM64Surface")) then return end
    local l = pawn:K2_GetActorLocation()
    local x, y, feet = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - (G.half or 90.0)
    local fz = G.floor_z and G.floor_z(x, y, feet + 40.0)
    local kind = (fz and kind_at(x, y, fz)) or ((G.SURFACE_OF and G.SURFACE_OF[G.name]) or 1)
    local addr = base:GetAddress()
    if addr == last_pmc and kind == last_kind then return end
    last_pmc, last_kind = addr, kind
    pcall(function() if pm.SurfaceType ~= kind then pm.SurfaceType = kind end end)
end

local function hook()
    if _G.SM64_STEP_HOOK2 then return true end
    local ok, err = pcall(RegisterHook, "/Script/SPP.SoundComponent:PlayPlayerSound", function(self, kind, vol)
        local K = package.loaded["footsteps"]
        if not (K and K.step_volume) then return end
        local k = nil
        pcall(function() k = kind:get() end)
        if k ~= FOOTSTEP then return end
        pcall(function() vol:set(K.step_volume(vol:get())) end)
    end)
    _G.SM64_STEP_HOOK2 = ok or nil
    lib.log("footsteps: %s", ok and ("taken up x" .. tostring(M.STEP_GAIN) .. ", never under his speed's") or ("no hook (" .. tostring(err) .. ")"))
    return ok
end

-- (tried again now and then until it takes: STORROR's class may not be there yet when the mod starts)
function M.tick(dt, pawn)
    if pawn then pcall(floor_sound, dt or 0.0, pawn) end
    if _G.SM64_STEP_HOOK2 then return end
    tried = tried - (dt or 0.0)
    if tried > 0.0 then return end
    tried = 5.0
    hook()
end

hook()

return M
