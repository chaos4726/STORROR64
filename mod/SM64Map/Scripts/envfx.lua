-- SM64Map: Mario 64's environment effects (game/envfx_snow.c, envfx_bubbles.c), by scene:
--   snow (ENVFX_SNOW_NORMAL: Cool, Cool Mountain and Snowman's Land) - Mario 64 keeps up to 140 little flakes round a
--     point before the camera, each falling 2 units a frame with a jitter. Here a field of flakes - a tile of 40
--     repeated 4 x 4 across and 3 up - stands round the camera, laid on the tiles' grid so that each flake keeps its
--     place in the world as he goes, and slides down 2 units a frame (45 cm a second), swaying a little. Each flake is
--     three small crossed squares of Mario 64's snowflake picture, so that it shows from any side. One mesh, built once
--     a scene; moved once a frame.
--   water specks (ENVFX_SNOW_WATER: the Secret Aquarium and the sunken ship) - the same field, sparser, its flakes the
--     blue-edged ones, hanging in the water with a slow drift.
--   lava bubbles (ENVFX_LAVA_BUBBLES: Lethal Lava Land, Bowser in the Fire Sea, his arena there) - fifteen bubbles on
--     the lava within 3000 of the camera's focus, each popping through its eight pictures (two frames apiece) and then
--     somewhere else; a spot with no lava under it shows none (Mario 64 puts those far under the course).
--   bubbles of the water's currents (ENVFX_JETSTREAM_BUBBLES / ENVFX_WHIRLPOOL_BUBBLES: Jolly Roger Bay, Dire, Dire
--     Docks): from each jet stream that is running, bubbles rise and spread; round each whirlpool they swirl in and
--     down into it. Only near him (4000).
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET
local M = {}

local MODES = { ccm = "snow", sl = "snow", sa = "water", jrb_2 = "water", lll = "lava", bitfs = "lava", bowser_2 = "lava",
                jrb = "streams", ddd = "streams", ddd_2 = "streams" }
local STREAM_N, BUBBLE_HALF = 16, 9.0
local FIELDS = {
    snow = { W = 400.0, H = 400.0, NX = 4, NZ = 3, PER = 40, HALF = 4.5, FALL = 2.0 * 0.75 * 30.0, SWAY = 12.0,
             texture = "envfx_snowflake" },
    water = { W = 400.0, H = 400.0, NX = 4, NZ = 3, PER = 10, HALF = 3.0, FALL = -6.0, SWAY = 20.0,
              texture = "envfx_waterflake" },
}
local LAVA_N, LAVA_HALF, LAVA_REACH = 15, 37.5, 3000.0 * 0.75       -- bubbles, half a bubble's square (cm), reach (cm)

local st = nil

-- (its own little random numbers: the same field every time, and the game's own sequence untouched)
local seed = 12345
local function rnd()
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed / 2147483648
end

local WHITE = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
local function quad(mesh, cx, cy, cz, half, ax, ay, az, bx, by, bz, nx, ny, nz)
    local verts, idx = mesh.verts, mesh.idx
    local n = #verts
    local corners = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }
    local tc = { { 0, 1 }, { 1, 1 }, { 1, 0 }, { 0, 0 } }
    for k = 1, 4 do
        local s, t = corners[k][1] * half, corners[k][2] * half
        verts[n + k] = { X = cx + ax * s + bx * t, Y = cy + ay * s + by * t, Z = cz + az * s + bz * t }
        mesh.nrms[n + k] = { X = nx, Y = ny, Z = nz }
        mesh.uvs[n + k] = { X = tc[k][1], Y = tc[k][2] }
        mesh.cols[n + k] = WHITE
    end
    local m = #idx
    idx[m + 1], idx[m + 2], idx[m + 3], idx[m + 4], idx[m + 5], idx[m + 6] = n, n + 1, n + 2, n, n + 2, n + 3
end
local function mesh_actor(world, mesh, texture, loc)
    local actor = lib.spawn_actor(world, loc or OFFSET, 0.0)
    local pmc = actor and lib.add_pmc(actor)
    if not pmc then return nil end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    lib.create_section(pmc, 0, mesh.verts, mesh.idx, mesh.nrms, mesh.uvs, mesh.cols, false)
    local mid = lib.get_mid(world, "translucent", texture)
    if mid then pmc:SetMaterial(0, mid) end
    return actor, pmc
end

-- Materials only Lua holds are freed by the engine's next garbage collection, and a SetMaterial with one then crashes
-- the game (the orange numbers, 2026-10-16 10:07, the first collection ~68 s after start). The effects that switch
-- pictures keep theirs on a hidden holder: one tiny section per material.
local function hold_mids(world, mids)
    local actor = lib.spawn_actor(world, OFFSET, 0.0)
    local pmc = actor and lib.add_pmc(actor)
    if not pmc then return actor end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    local n = 0
    for _, mid in pairs(mids) do
        if mid then
            local v = { { X = 0.0, Y = 0.0, Z = 0.0 }, { X = 0.01, Y = 0.0, Z = 0.0 }, { X = 0.0, Y = 0.01, Z = 0.0 } }
            local nr = { { X = 0.0, Y = 0.0, Z = 1.0 }, { X = 0.0, Y = 0.0, Z = 1.0 }, { X = 0.0, Y = 0.0, Z = 1.0 } }
            local uv = { { X = 0.0, Y = 0.0 }, { X = 1.0, Y = 0.0 }, { X = 0.0, Y = 1.0 } }
            local c = { WHITE, WHITE, WHITE }
            pcall(function()
                lib.create_section(pmc, n, v, { 0, 1, 2 }, nr, uv, c, false)
                pmc:SetMaterial(n, mid)
            end)
            n = n + 1
        end
    end
    pcall(function() actor:SetActorHiddenInGame(true) end)
    return actor
end

local function build_field(world, F)
    local mesh = { verts = {}, idx = {}, nrms = {}, uvs = {}, cols = {} }
    seed = 12345
    local flakes = {}
    for i = 1, F.PER do flakes[i] = { rnd() * F.W, rnd() * F.W, rnd() * F.H } end
    for tx = 0, F.NX - 1 do
        for ty = 0, F.NX - 1 do
            for tz = 0, F.NZ - 1 do
                for _, f in ipairs(flakes) do
                    local cx, cy, cz = tx * F.W + f[1], ty * F.W + f[2], tz * F.H + f[3]
                    quad(mesh, cx, cy, cz, F.HALF, 1, 0, 0, 0, 0, 1, 0, 1, 0)     -- (upright, facing along Y)
                    quad(mesh, cx, cy, cz, F.HALF, 0, 1, 0, 0, 0, 1, 1, 0, 0)     -- (upright, facing along X)
                    quad(mesh, cx, cy, cz, F.HALF, 1, 0, 0, 0, 1, 0, 0, 0, 1)     -- (flat)
                end
            end
        end
    end
    local actor = mesh_actor(world, mesh, F.texture)
    return actor, #mesh.verts
end

local function build_lava(world)
    local mids = {}
    for i = 1, 8 do mids[i] = lib.get_mid(world, "translucent", "envfx_lava_" .. i) end
    local bubbles = {}
    for i = 1, LAVA_N do
        local mesh = { verts = {}, idx = {}, nrms = {}, uvs = {}, cols = {} }
        -- (a square facing -X, turned to the camera each frame; its picture's bubble sits in its lower half)
        quad(mesh, 0.0, 0.0, LAVA_HALF, LAVA_HALF, 0, 1, 0, 0, 0, 1, -1, 0, 0)
        local actor, pmc = mesh_actor(world, mesh, "envfx_lava_1")
        if actor then
            pcall(function() actor:SetActorHiddenInGame(true) end)
            bubbles[#bubbles + 1] = { actor = actor, pmc = pmc, frame = 9, acc = math.random() * 0.6, shown = false }
        end
    end
    return bubbles, mids, hold_mids(world, mids)
end

local function build_streams(world)
    local G = package.loaded["game"]
    local wl = G and G.data and G.data.whirlpools
    local streams = {}
    for _, w in ipairs(wl or {}) do
        local s = { w = w, bubbles = {} }
        for i = 1, STREAM_N do
            local mesh = { verts = {}, idx = {}, nrms = {}, uvs = {}, cols = {} }
            quad(mesh, 0.0, 0.0, 0.0, BUBBLE_HALF, 0, 1, 0, 0, 0, 1, -1, 0, 0)
            local actor = mesh_actor(world, mesh, "envfx_bubble")
            if actor then
                pcall(function() actor:SetActorHiddenInGame(true) end)
                s.bubbles[#s.bubbles + 1] = { actor = actor, age = -math.random(0, 60), life = 0, shown = false }   -- (staggered)
            end
        end
        streams[#streams + 1] = s
    end
    return streams
end

-- A splash where he plunges into the water (bhvWaterSplash): Mario 64's eight pictures, two frames apiece, turned to the
-- camera, 128 x 256 units with its foot on the water - half as big again for the athlete. Two at most at once.
local SPLASH_W, SPLASH_H = 64.0 * 0.75 * 1.5, 256.0 * 0.75 * 1.5
local splash = nil
local function splash_pool(world)
    local mids = {}
    for i = 1, 8 do mids[i] = lib.get_mid(world, "translucent", "envfx_splash_" .. i) end
    local pool = {}
    for i = 1, 2 do
        local mesh = { verts = {}, idx = {}, nrms = {}, uvs = {}, cols = {} }
        quad(mesh, 0.0, 0.0, SPLASH_H / 2.0, 1.0, 0, SPLASH_W, 0, 0, 0, SPLASH_H / 2.0, -1, 0, 0)
        local actor, pmc = mesh_actor(world, mesh, "envfx_splash_1")
        if actor then
            pcall(function() actor:SetActorHiddenInGame(true) end)
            pool[#pool + 1] = { actor = actor, pmc = pmc, t = nil }
        end
    end
    return { pool = pool, mids = mids, world = world:GetAddress(), holder = hold_mids(world, mids) }
end
-- (x, y): where, z: the water's top - scene cm
function M.splash(x, y, z)
    local world = lib.world()
    if not world then return end
    if splash and splash.world ~= world:GetAddress() then splash = nil end
    if not splash then
        local ok, sp = pcall(splash_pool, world)
        if not (ok and sp) then return end
        splash = sp
    end
    local pick = nil
    for _, p in ipairs(splash.pool) do if not p.t then pick = p; break end end
    pick = pick or splash.pool[1]
    if not pick then return end
    pick.t, pick.frame, pick.x, pick.y, pick.z = 0.0, 0, x, y, z
    pcall(function() pick.actor:SetActorHiddenInGame(false) end)
end
-- A step in shallow water (bhvShallowWaterSplash -> bhvWaterDroplet): a few small white drops flicked up and out from
-- the foot, falling back into the water - Mario 64's white particle picture. Twenty at most, moved without a hit result
-- (teleported) every frame. ("splashes are still incorrect", 2026-10-17: the plunge's column shrunk stood up behind him.)
local DROP_HALF, DROP_G = 3.0, 900.0
local wade = nil
local function wade_pool(world)
    local pool = {}
    for i = 1, 20 do
        local mesh = { verts = {}, idx = {}, nrms = {}, uvs = {}, cols = {} }
        quad(mesh, 0.0, 0.0, 0.0, 1.0, 0, DROP_HALF, 0, 0, 0, DROP_HALF, -1, 0, 0)
        local actor = mesh_actor(world, mesh, "actors__white_particle__snow_particle.rgba16")
        if actor then
            pcall(function() actor:SetActorHiddenInGame(true) end)
            pool[#pool + 1] = { actor = actor, t = nil }
        end
    end
    return { pool = pool, world = world:GetAddress(), next = 1 }
end
-- (x, y): the foot, z: the water's top - scene cm
function M.wade_splash(x, y, z)
    local world = lib.world()
    if not world then return end
    if wade and wade.world ~= world:GetAddress() then wade = nil end
    if not wade then
        local ok, w = pcall(wade_pool, world)
        if not (ok and w) then return end
        wade = w
    end
    for _ = 1, 5 do
        local p = wade.pool[wade.next]
        wade.next = wade.next % #wade.pool + 1
        if p then
            local a = math.random() * 2.0 * math.pi
            local out = 40.0 + math.random() * 60.0
            p.t, p.x, p.y, p.z, p.top = 0.0, x + math.cos(a) * 6.0, y + math.sin(a) * 6.0, z + 1.0, z
            p.vx, p.vy, p.vz = math.cos(a) * out, math.sin(a) * out, 140.0 + math.random() * 120.0
            pcall(function() p.actor:SetActorHiddenInGame(false) end)
        end
    end
end
local function update_wade(dt, cx, cy)
    if not wade then return end
    for _, p in ipairs(wade.pool) do
        if p.t then
            p.t = p.t + dt
            p.vz = p.vz - DROP_G * dt
            p.x, p.y, p.z = p.x + p.vx * dt, p.y + p.vy * dt, p.z + p.vz * dt
            if p.t > 0.8 or (p.vz < 0.0 and p.z < p.top) then
                p.t = nil
                pcall(function() p.actor:SetActorHiddenInGame(true) end)
            else
                local wx, wy = p.x + OFFSET.X, p.y + OFFSET.Y
                local yaw = math.deg(math.atan(cy - wy, cx - wx)) + 180.0
                pcall(function() p.actor:K2_TeleportTo({ X = wx, Y = wy, Z = p.z + OFFSET.Z }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 }) end)
            end
        end
    end
end

local function update_splash(dt, cx, cy)
    pcall(update_wade, dt, cx, cy)
    if not splash then return end
    for _, p in ipairs(splash.pool) do
        if p.t then
            p.t = p.t + dt
            local f = math.floor(p.t * 15.0) + 1
            if f > 8 then
                p.t = nil
                pcall(function() p.actor:SetActorHiddenInGame(true) end)
            else
                if f ~= p.frame and splash.mids[f] then p.frame = f; pcall(function() p.pmc:SetMaterial(0, splash.mids[f]) end) end
                local wx, wy = p.x + OFFSET.X, p.y + OFFSET.Y
                local yaw = math.deg(math.atan(cy - wy, cx - wx)) + 180.0
                pcall(function() p.actor:K2_SetActorLocationAndRotation({ X = wx, Y = wy, Z = p.z + OFFSET.Z }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false, {}, true) end)
            end
        end
    end
end

-- His breath under the water (mario.c: PARTICLE_BUBBLE while he swims deep -> bhvBubbleParticleSpawner ->
-- bhvSmallWaterWave): a bubble about his head every 2-10 frames, each rising 7 a frame with a little drift, wobbling
-- in its two sizes, for two seconds or till it reaches the surface. Mario 64's bubble is 32 across. Twelve at most.
local BREATH_HALF = 16.0 * 0.75
local breath = nil
local function breath_pool(world)
    local pool = {}
    for i = 1, 12 do
        local mesh = { verts = {}, idx = {}, nrms = {}, uvs = {}, cols = {} }
        quad(mesh, 0.0, 0.0, 0.0, 1.0, 0, 1, 0, 0, 0, 1, -1, 0, 0)
        local actor = mesh_actor(world, mesh, "envfx_breath")         -- (Mario 64's MODEL_BUBBLE picture: a clear ring)
        if actor then
            pcall(function() actor:SetActorHiddenInGame(true) end)
            pool[#pool + 1] = { actor = actor }
        end
    end
    return { pool = pool, world = world:GetAddress(), next = 1, acc = 0.0 }
end
-- (x, y, z): about his head, top: the water's surface there - scene cm
function M.breath(x, y, z, top)
    local world = lib.world()
    if not world then return end
    if breath and breath.world ~= world:GetAddress() then breath = nil end
    if not breath then
        local ok, bp = pcall(breath_pool, world)
        if not (ok and bp and #bp.pool > 0) then return end
        breath = bp
    end
    local p = breath.pool[breath.next]
    breath.next = breath.next % #breath.pool + 1
    p.x, p.y = x + (math.random() - 0.5) * 100.0 * 0.75, y + (math.random() - 0.5) * 100.0 * 0.75
    p.z, p.top, p.age = z + math.random() * 50.0 * 0.75, top, 0
    p.wa, p.wb = 0x800 + math.random() * 2048.0, 0x800 + math.random() * 2048.0
    p.sa, p.sb = 0.0, 0.0
    pcall(function() p.actor:SetActorHiddenInGame(false) end)
end
local function update_breath(dt, cx, cy)
    if not breath then return end
    breath.acc = math.min(breath.acc + dt, 0.2)
    while breath.acc >= 1.0 / 30.0 do
        breath.acc = breath.acc - 1.0 / 30.0
        for _, p in ipairs(breath.pool) do
            if p.age then
                p.age = p.age + 1
                p.z = p.z + 7.0 * 0.75
                p.x, p.y = p.x + (math.random() * 5.0 - 2.0) * 0.75, p.y + (math.random() * 5.0 - 2.0) * 0.75
                p.sa, p.sb = p.sa + p.wa, p.sb + p.wb
                if p.age > 60 or p.z > p.top then
                    p.age = nil
                    pcall(function() p.actor:SetActorHiddenInGame(true) end)
                end
            end
        end
    end
    for _, p in ipairs(breath.pool) do
        if p.age then
            local wx, wy = p.x + OFFSET.X, p.y + OFFSET.Y
            local yaw = math.deg(math.atan(cy - wy, cx - wx)) + 180.0
            local a = BREATH_HALF * (1.0 + 0.2 * math.sin(p.sa * math.pi / 32768.0))
            local b = BREATH_HALF * (1.0 + 0.2 * math.sin(p.sb * math.pi / 32768.0))
            pcall(function()
                p.actor:K2_SetActorLocationAndRotation({ X = wx, Y = wy, Z = p.z + OFFSET.Z }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false, {}, true)
                p.actor:SetActorScale3D({ X = 1.0, Y = a, Z = b })
            end)
        end
    end
end

-- A punch or kick that lands (interaction.c bounce_back_from_attack: PARTICLE_TRIANGLE -> collide_particles.inc.c
-- bhv_punch_tiny_triangle_init): six tiny yellow triangles (dirt_animation_geo's case 5, 20 across) burst back from
-- where it struck - 100 before him, 60 up - at 25, turned to the camera, shrinking from 1.28 by 0.2 a frame.
local TRI = { 0xD000, 0, 0x3000, 0, 0xDE67, 0x2199, 0x2199, 0x2199, 0xDE67, 0xDE67, 0x2199, 0xDE67 }
local TRI_K = 10.0 * 0.75 * 1.25
local hit = nil
local function hit_pool(world)
    local pool = {}
    for i = 1, 12 do
        local mesh = { verts = { { X = 0.0, Y = -1.0, Z = 1.0 }, { X = 0.0, Y = 1.0, Z = 1.0 }, { X = 0.0, Y = 0.0, Z = -1.0 } },
                       idx = { 0, 2, 1 },     -- (wound as quad()'s, toward -X)
                       nrms = { { X = -1.0, Y = 0.0, Z = 0.0 }, { X = -1.0, Y = 0.0, Z = 0.0 }, { X = -1.0, Y = 0.0, Z = 0.0 } },
                       uvs = { { X = 0.0, Y = 0.0 }, { X = 1.0, Y = 0.0 }, { X = 0.5, Y = 1.0 } },
                       cols = { { R = 1.0, G = 1.0, B = 0.0, A = 1.0 }, { R = 1.0, G = 1.0, B = 0.0, A = 1.0 }, { R = 1.0, G = 1.0, B = 0.0, A = 1.0 } } }
        local actor = mesh_actor(world, mesh, "envfx_white")
        if actor then
            pcall(function() actor:SetActorHiddenInGame(true) end)
            pool[#pool + 1] = { actor = actor }
        end
    end
    return { pool = pool, world = world:GetAddress(), next = 1, acc = 0.0 }
end
-- (x, y, z): where it struck, scene cm; yaw: the way he faces, Mario 64's angle
function M.hit(x, y, z, yaw)
    local world = lib.world()
    if not world then return end
    if hit and hit.world ~= world:GetAddress() then hit = nil end
    if not hit then
        local ok, H = pcall(hit_pool, world)
        if not (ok and H and #H.pool > 0) then return end
        hit = H
    end
    for i = 0, 5 do
        local p = hit.pool[hit.next]
        hit.next = hit.next % #hit.pool + 1
        local a = (yaw + TRI[2 * i + 1] + 0x8000) * math.pi / 32768.0
        local up = TRI[2 * i + 2] * math.pi / 32768.0
        p.x, p.y, p.z, p.k, p.age = x, y, z, 1.28, 0
        -- (Mario 64 units a frame along its heading - x = sin, z = cos - into the scene's axes)
        local fv = math.cos(up) * 25.0
        p.vx, p.vy, p.vz = -math.cos(a) * fv * 0.75, math.sin(a) * fv * 0.75, math.sin(up) * 25.0 * 0.75
        pcall(function() p.actor:SetActorHiddenInGame(false) end)
    end
end
local function update_hit(dt, cx, cy)
    if not hit then return end
    hit.acc = math.min(hit.acc + dt, 0.2)
    while hit.acc >= 1.0 / 30.0 do
        hit.acc = hit.acc - 1.0 / 30.0
        for _, p in ipairs(hit.pool) do
            if p.age then
                p.age = p.age + 1
                p.x, p.y, p.z = p.x + p.vx, p.y + p.vy, p.z + p.vz
                p.k = p.k - 0.2
                if p.age > 6 or p.k <= 0.0 then
                    p.age = nil
                    pcall(function() p.actor:SetActorHiddenInGame(true) end)
                end
            end
        end
    end
    for _, p in ipairs(hit.pool) do
        if p.age then
            local wx, wy = p.x + OFFSET.X, p.y + OFFSET.Y
            local yw = math.deg(math.atan(cy - wy, cx - wx)) + 180.0
            local k = TRI_K * math.max(0.01, p.k)
            pcall(function()
                p.actor:K2_SetActorLocationAndRotation({ X = wx, Y = wy, Z = p.z + OFFSET.Z }, { Pitch = 0.0, Yaw = yw, Roll = 0.0 }, false, {}, true)
                p.actor:SetActorScale3D({ X = 1.0, Y = k, Z = k })
            end)
        end
    end
end

-- Rings on the water round him at its surface (water_splashes_and_waves.inc.c): floating still, one ring round him
-- (bhvIdleWaterWave: idle_water_wave_geo's pictures 0 1 2 3 2 1, eight frames each); swimming along, a wake of them
-- (bhvWaveTrail: one every other frame where he is, through pictures 0-3 two frames each, then shrinking away).
-- Mario 64's water_wave pictures (textures/envfx_wave_0..3), 128 across - a quarter bigger for the athlete.
local WAVE_HALF = 64.0 * 0.75 * 1.25
local WAVE_IDLE = { 0, 1, 2, 3, 2, 1 }
local wave = nil
local function wave_pool(world)
    local mids = {}
    -- (its vertices' alpha 0xC8: about three quarters through - the material's opacity is a colour, sRGB)
    for i = 0, 3 do mids[i + 1] = lib.get_mid(world, "translucent", "envfx_wave_" .. i, 0.86) end
    local function make()
        local mesh = { verts = {}, idx = {}, nrms = {}, uvs = {}, cols = {} }
        quad(mesh, 0.0, 0.0, 0.0, 1.0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
        local ix = mesh.idx
        ix[7], ix[8], ix[9], ix[10], ix[11], ix[12] = 0, 2, 1, 0, 3, 2         -- (from below too: MI_Unlit_Blend is one-sided)
        local actor, pmc = mesh_actor(world, mesh, "envfx_wave_0")
        if actor then pcall(function() actor:SetActorHiddenInGame(true) end) end
        return { actor = actor, pmc = pmc }
    end
    local W = { ring = make(), trail = {}, mids = mids, world = world:GetAddress(), holder = hold_mids(world, mids),
                next = 1, acc = 0.0, t = 0, mode = nil }
    for i = 1, 8 do W.trail[i] = make() end
    return W
end
local function wave_frame(p, f)
    if p.frame ~= f and wave.mids[f + 1] then
        p.frame = f
        pcall(function() p.pmc:SetMaterial(0, wave.mids[f + 1]) end)
    end
end
local function wave_show(p, on)
    if p.shown == on then return end
    p.shown = on
    pcall(function() p.actor:SetActorHiddenInGame(not on) end)
end
-- Each frame from game.lua: (x, y) where he is, top the water's surface there (scene cm); mode "idle", "trail" or nil
function M.water_waves(x, y, top, mode)
    if not mode and not wave then return end
    local world = lib.world()
    if not world then return end
    if wave and wave.world ~= world:GetAddress() then wave = nil end
    if not wave then
        if not mode then return end
        local ok, W = pcall(wave_pool, world)
        if not (ok and W) then return end
        wave = W
    end
    wave.x, wave.y, wave.top, wave.mode = x, y, top, mode
end
local function update_waves(dt)
    if not wave then return end
    wave.acc = math.min(wave.acc + dt, 0.2)
    while wave.acc >= 1.0 / 30.0 do
        wave.acc = wave.acc - 1.0 / 30.0
        wave.t = wave.t + 1
        -- (the wake: a new ring every other frame while he swims along)
        if wave.mode == "trail" and wave.top and wave.t % 2 == 0 then
            local p = wave.trail[wave.next]
            wave.next = wave.next % #wave.trail + 1
            p.age, p.size, p.x, p.y, p.z = 0, 1.0, wave.x, wave.y, wave.top
        end
        for _, p in ipairs(wave.trail) do
            if p.age then
                p.age = p.age + 1
                local state = math.floor(p.age / 2)
                if state > 3 then p.size = p.size - 0.1 end
                if p.size <= 0.0 or state > 7 then p.age = nil end
            end
        end
    end
    -- the ring round him, floating still
    local r = wave.ring
    if wave.mode == "idle" and wave.top and r.actor then
        wave_show(r, true)
        wave_frame(r, WAVE_IDLE[math.floor(wave.t / 8) % 6 + 1])
        pcall(function()
            r.actor:K2_SetActorLocation({ X = wave.x + OFFSET.X, Y = wave.y + OFFSET.Y, Z = wave.top + 4.0 + OFFSET.Z }, false, {}, true)
            r.actor:SetActorScale3D({ X = WAVE_HALF, Y = WAVE_HALF, Z = 1.0 })
        end)
    elseif r.actor then
        wave_show(r, false)
    end
    for _, p in ipairs(wave.trail) do
        if p.actor then
            if p.age then
                wave_show(p, true)
                wave_frame(p, math.min(3, math.floor(p.age / 2)))
                local k = WAVE_HALF * math.max(0.01, p.size)
                pcall(function()
                    p.actor:K2_SetActorLocation({ X = p.x + OFFSET.X, Y = p.y + OFFSET.Y, Z = p.z + 3.0 + OFFSET.Z }, false, {}, true)
                    p.actor:SetActorScale3D({ X = k, Y = k, Z = 1.0 })
                end)
            else
                wave_show(p, false)
            end
        end
    end
end

-- Leaves shaken out of a tree as he climbs it (mario_actions_automatic.c PARTICLE_LEAF -> bhv_snow_leaf_particle_spawn_init,
-- tree_particles.inc.c): a leaf of 0-3 times its size flies off at 5-10 (slowing 0.3 a frame), up at 0-15 and falling
-- (3 a frame, at most 8), fluttering from side to side and tumbling, till it reaches the ground or 100 frames pass;
-- in CCM and SL a speck of snow instead (Mario 64's white particle). Sixteen at most.
local leaf = nil
local function leaf_pool(world)
    local L = { pool = {}, world = world:GetAddress(), next = 1, acc = 0.0 }
    for _, kind in ipairs({ "leaves", "white_particle" }) do
        local data = lib.load_data("data.actor_geo_" .. kind .. "_geo")
        if data then
            -- (seen from both sides as it tumbles: MI_Unlit_Blend draws one side only)
            for _, part in ipairs(data.parts or {}) do
                for _, sec in ipairs(part.sections or {}) do
                    if not sec.both then
                        local idx, n = sec.idx, #sec.idx
                        for i = 1, n, 3 do idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = idx[i], idx[i + 2], idx[i + 1] end
                        sec.both, sec.ntris = true, (sec.ntris or 0) * 2
                    end
                end
            end
            L[kind] = data
        end
    end
    return L
end
-- (x, y, z): where he is on the trunk - scene cm; snow: specks of snow rather than leaves
function M.leaf(x, y, z, snow)
    local world = lib.world()
    if not world then return end
    if leaf and leaf.world ~= world:GetAddress() then leaf = nil end
    if not leaf then
        local ok, L = pcall(leaf_pool, world)
        if not (ok and L) then return end
        leaf = L
    end
    local data = snow and leaf.white_particle or leaf.leaves
    if not data then return end
    local p = leaf.pool[leaf.next]
    if not p or p.snow ~= snow then
        if p and p.inst then pcall(lib.destroy, p.inst.actor) end
        local inst = lib.make_instance(world, data, { X = x + OFFSET.X, Y = y + OFFSET.Y, Z = z + OFFSET.Z }, 0.0, 1.0)
        if not inst then return end
        p = { inst = inst, snow = snow }
        leaf.pool[leaf.next] = p
    end
    leaf.next = leaf.next % 16 + 1
    local k = snow and math.random() or math.random() * 3.0
    p.x, p.y, p.z, p.k = x, y, z, math.max(0.05, k)
    p.yaw = math.random() * 65536.0
    p.fvel = snow and math.random() * 5.0 or (math.random() * 5.0 + 5.0)
    p.vy = math.random() * 15.0
    p.pitch, p.roll = math.random() * 65536.0, math.random() * 65536.0
    p.pv, p.rv = (math.random() - 0.5) * 0x1000, (math.random() - 0.5) * 0x1000
    p.fl, p.flv = 0.0, math.random() * 0x400 + 0x600
    p.age = 0
    pcall(function()
        p.inst.actor:SetActorScale3D({ X = p.k, Y = p.k, Z = p.k })
        p.inst.actor:SetActorHiddenInGame(false)
    end)
end
local function update_leaf(dt)
    if not leaf then return end
    leaf.acc = math.min(leaf.acc + dt, 0.2)
    local U = 0.75
    while leaf.acc >= 1.0 / 30.0 do
        leaf.acc = leaf.acc - 1.0 / 30.0
        for _, p in pairs(leaf.pool) do
            if p.age then
                p.age = p.age + 1
                p.pitch, p.roll = p.pitch + p.pv, p.roll + p.rv
                p.vy = math.max(-8.0, p.vy - 3.0)
                p.fvel = math.max(0.0, p.fvel - 0.3)
                -- (Mario 64 units: its heading in the scene's x/y, the flutter across it)
                local a = p.yaw * math.pi / 32768.0
                local fl = math.sin(p.fl * math.pi / 32768.0) * 4.0
                local mx, mz = (p.fvel + fl) * math.sin(a), (p.fvel + fl) * math.cos(a)
                p.fl = p.fl + p.flv
                p.x, p.y, p.z = p.x - mz * U, p.y + mx * U, p.z + p.vy * U
                local G = package.loaded["game"]
                local fz = G and G.floor_z and G.floor_z(p.x, p.y, p.z + 50.0)
                if p.age > 100 or (fz and p.z < fz) then
                    p.age = nil
                    pcall(function() p.inst.actor:SetActorHiddenInGame(true) end)
                end
            end
        end
    end
    for _, p in pairs(leaf.pool) do
        if p.age then
            pcall(function()
                p.inst.actor:K2_SetActorLocationAndRotation({ X = p.x + OFFSET.X, Y = p.y + OFFSET.Y, Z = p.z + OFFSET.Z },
                    { Pitch = p.pitch * 360.0 / 65536.0, Yaw = p.yaw * 360.0 / 65536.0, Roll = p.roll * 360.0 / 65536.0 }, false, {}, true)
            end)
        end
    end
end

-- A coin's sparkles as it is taken (bhvGoldenCoinSparkles / bhvCoinSparkles): three, a little apart, each turned to the
-- camera and running through Mario 64's six sparkle pictures (the geo's twelve states, last first) over ten frames.
local SPARK_HALF = 32.0 * 0.6 * 0.75 * 0.75
local spark = nil
local function spark_pool(world)
    local mids = {}
    for i = 1, 6 do mids[i] = lib.get_mid(world, "translucent", "envfx_sparkle_" .. i) end
    local pool = {}
    for i = 1, 9 do
        local mesh = { verts = {}, idx = {}, nrms = {}, uvs = {}, cols = {} }
        quad(mesh, 0.0, 0.0, 0.0, SPARK_HALF, 0, 1, 0, 0, 0, 1, -1, 0, 0)
        local actor, pmc = mesh_actor(world, mesh, "envfx_sparkle_6")
        if actor then
            pcall(function() actor:SetActorHiddenInGame(true) end)
            pool[#pool + 1] = { actor = actor, pmc = pmc, t = nil }
        end
    end
    return { pool = pool, mids = mids, world = world:GetAddress(), next = 1, holder = hold_mids(world, mids) }
end
-- (x, y, z): the coin, scene cm; n: how many (three for a coin, one a time for a moving 1-up's trail)
function M.sparkle(x, y, z, n)
    local world = lib.world()
    if not world then return end
    if spark and spark.world ~= world:GetAddress() then spark = nil end
    if not spark then
        local ok, sp = pcall(spark_pool, world)
        if not (ok and sp) then return end
        spark = sp
    end
    for k = 0, (n or 3) - 1 do
        local p = spark.pool[spark.next]
        spark.next = spark.next % #spark.pool + 1
        if p then
            p.t, p.delay, p.frame = 0.0, k / 30.0, 0
            p.x, p.y, p.z = x + (math.random() - 0.5) * 30.0 * 0.75, y + (math.random() - 0.5) * 30.0 * 0.75, z + 25.0 * 0.75
        end
    end
end
local function update_spark(dt, cx, cy)
    if not spark then return end
    for _, p in ipairs(spark.pool) do
        if p.t then
            p.t = p.t + dt
            local tt = p.t - p.delay
            if tt >= 0.0 then
                local f = math.floor(tt * 30.0)                     -- (its frame, 0..9)
                if f > 9 then
                    p.t = nil
                    pcall(function() p.actor:SetActorHiddenInGame(true) end)
                else
                    local pic = 6 - math.min(5, math.floor(f / 2))  -- (the sixth picture first)
                    if pic ~= p.frame and spark.mids[pic] then
                        p.frame = pic
                        pcall(function() p.pmc:SetMaterial(0, spark.mids[pic]); p.actor:SetActorHiddenInGame(false) end)
                    end
                    local wx, wy = p.x + OFFSET.X, p.y + OFFSET.Y
                    local yaw = math.deg(math.atan(cy - wy, cx - wx)) + 180.0
                    pcall(function() p.actor:K2_SetActorLocationAndRotation({ X = wx, Y = wy, Z = p.z + OFFSET.Z }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false, {}, true) end)
                end
            end
        end
    end
end

-- The orange numbers (spawn_orange_number, bhvOrangeNumber): a red coin's count, a secret's, a treasure chest's, a water
-- ring's - the HUD's digit on a billboard 64 Mario units across, 25 over where it was spawned, thrown up at 26 a frame
-- and falling 2 a frame (back up at 14 when it is past 21 down), gone in sparkles on its 35th frame.
local NUM_HALF = 32.0 * 0.75
local num = nil
local function num_pool(world)
    local mids = {}
    for d = 0, 9 do mids[d] = lib.get_mid(world, "translucent", "envfx_num_" .. d) end
    local pool = {}
    for i = 1, 4 do
        local mesh = { verts = {}, idx = {}, nrms = {}, uvs = {}, cols = {} }
        quad(mesh, 0.0, 0.0, 0.0, NUM_HALF, 0, 1, 0, 0, 0, 1, -1, 0, 0)
        -- (the picture mirrored: as the sparkle's square is turned to the camera its u runs to the viewer's left)
        for _, uv in ipairs(mesh.uvs) do uv.X = 1.0 - uv.X end
        local actor, pmc = mesh_actor(world, mesh, "envfx_num_0")
        if actor then
            pcall(function() actor:SetActorHiddenInGame(true) end)
            pool[#pool + 1] = { actor = actor, pmc = pmc, t = nil }
        end
    end
    return { pool = pool, mids = mids, world = world:GetAddress(), next = 1, holder = hold_mids(world, mids) }
end
-- n: the digit (0-9; Mario 64 shows none from 10 up); (x, y, z): what it is for, scene cm
function M.number(n, x, y, z)
    n = math.floor(n or 0)
    if n < 0 or n >= 10 then return end
    local world = lib.world()
    if not world then return end
    if num and num.world ~= world:GetAddress() then num = nil end
    if not num then
        local ok, np = pcall(num_pool, world)
        if not (ok and np) then return end
        num = np
    end
    local p = num.pool[num.next]
    num.next = num.next % #num.pool + 1
    if not p then return end
    p.t, p.frame, p.x, p.y, p.z, p.vy = 0.0, 0, x, y, z + 25.0 * 0.75, 26.0
    if num.mids[n] then pcall(function() p.pmc:SetMaterial(0, num.mids[n]) end) end
    pcall(function() p.actor:SetActorHiddenInGame(false) end)
end
local function update_num(dt, cx, cy)
    if not num then return end
    for _, p in ipairs(num.pool) do
        if p.t then
            p.t = p.t + dt
            local f = math.floor(p.t * 30.0)
            while p.frame < f do                    -- (its motion, a Mario 64 frame at a time)
                p.frame = p.frame + 1
                p.z = p.z + p.vy * 0.75
                p.vy = p.vy - 2.0
                if p.vy < -21.0 then p.vy = 14.0 end
            end
            if f >= 35 then
                p.t = nil
                pcall(function() p.actor:SetActorHiddenInGame(true) end)
                M.sparkle(p.x, p.y, p.z - 30.0 * 0.75 - 25.0 * 0.75, 3)       -- (bhvGoldenCoinSparkles, 30 under it)
            else
                local wx, wy = p.x + OFFSET.X, p.y + OFFSET.Y
                local yaw = math.deg(math.atan(cy - wy, cx - wx)) + 180.0
                pcall(function() p.actor:K2_SetActorLocationAndRotation({ X = wx, Y = wy, Z = p.z + OFFSET.Z }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false, {}, true) end)
            end
        end
    end
end

-- A defeated creature's puff (spawn_mist_particles: bhvWhitePuffExplosion with sMistParticles): white mist puffs thrown
-- out every way at 40-45 a frame and up at 30-50, falling 4 a frame, dragged, fading 21 of 254 a frame and shrinking
-- with it - twelve frames. Mario 64 throws twenty; eight here, from a pool of sixteen of the mod's mist model.
local POOF_N, POOF_SCALE = 8, 2.6
local poof = nil
local function poof_pool(world)
    local data = lib.load_data("data.actor_mist")
    if not data then return nil end
    local pool = {}
    for i = 1, 16 do
        local inst = lib.make_instance(world, data, OFFSET, 0.0, POOF_SCALE)
        if inst then
            inst.moves = true
            local ok, mids = pcall(lib.see_through, world, inst, 1.0)
            pcall(function() inst.actor:SetActorHiddenInGame(true) end)
            pool[#pool + 1] = { inst = inst, mids = ok and mids or {}, life = 0 }
        end
    end
    return { pool = pool, world = world:GetAddress(), next = 1 }
end
-- (x, y, z): its middle, scene cm; k: its size against Mario 64's (1)
function M.poof(x, y, z, k)
    local world = lib.world()
    if not world then return end
    if poof and poof.world ~= world:GetAddress() then poof = nil end
    if not poof then
        local ok, pp = pcall(poof_pool, world)
        if not (ok and pp) then return end
        poof = pp
    end
    k = k or 1.0
    for _ = 1, POOF_N do
        local p = poof.pool[poof.next]
        poof.next = poof.next % #poof.pool + 1
        if p then
            local a = math.random() * 2.0 * math.pi
            p.x, p.y, p.z = x, y, z
            p.fv, p.vz, p.dir = (40.0 + math.random() * 5.0) * 0.75 * k, (30.0 + math.random() * 20.0) * 0.75 * k, a
            p.op, p.size, p.life, p.acc = 254.0, POOF_SCALE * k * (1.0 + math.random() * 0.03), 12, 0.0
            p.shown = false
        end
    end
end
local function update_poof(dt, cx, cy)
    if not poof then return end
    for _, p in ipairs(poof.pool) do
        if p.life > 0 then
            p.acc = p.acc + dt
            while p.acc >= 1.0 / 30.0 and p.life > 0 do
                p.acc = p.acc - 1.0 / 30.0
                p.x, p.y = p.x + math.cos(p.dir) * p.fv, p.y + math.sin(p.dir) * p.fv
                p.z = p.z + p.vz
                p.vz = p.vz - 4.0 * 0.75
                p.fv = p.fv * 0.85
                p.op = p.op - 21.0
                p.life = p.life - 1
            end
            if p.life <= 0 or p.op < 2.0 then
                p.life = 0
                pcall(function() p.inst.actor:SetActorHiddenInGame(true) end)
            else
                local sc = p.size * p.op / 254.0
                local wx, wy = p.x + OFFSET.X, p.y + OFFSET.Y
                local yaw = math.deg(math.atan(cy - wy, cx - wx)) + 180.0
                pcall(function()
                    p.inst.actor:K2_SetActorLocationAndRotation({ X = wx, Y = wy, Z = p.z + OFFSET.Z }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false, {}, true)
                    p.inst.actor:SetActorScale3D({ X = sc, Y = sc, Z = sc })
                    if not p.shown then p.shown = true; p.inst.actor:SetActorHiddenInGame(false) end
                end)
                for _, m in ipairs(p.mids or {}) do
                    pcall(function() m:SetVectorParameterValue(FName("BaseColorFactor"), { R = 1.0, G = 1.0, B = 1.0, A = p.op / 254.0 }) end)
                end
            end
        end
    end
end

-- Dust at his feet (PARTICLE_DUST: bhvMistParticleSpawner's bhvWhitePuff2, the walk smoke): a square of Mario 64's
-- 64 units standing on the ground where he is, a little off to a side (obj_translate_xz_random 40), turned to the
-- camera, running through the seven smoke pictures one a frame and gone (smoke_geo; its vertices' alpha 0x64, a little
-- more here on the bigger figure). dust.lua says when. ("adding upgrading and improving", 2026-10-18.)
local DUST_HALF = 32.0 * 0.75 * 1.4
local DUST_ALPHA = 0.5
local dust = nil
local function dust_pool(world)
    local mids = {}
    for i = 1, 7 do mids[i] = lib.get_mid(world, "translucent", "walk_smoke_" .. (i - 1), DUST_ALPHA) end
    local pool = {}
    for _ = 1, 16 do
        local mesh = { verts = {}, idx = {}, nrms = {}, uvs = {}, cols = {} }
        quad(mesh, 0.0, 0.0, DUST_HALF, DUST_HALF, 0, 1, 0, 0, 0, 1, -1, 0, 0)
        local actor, pmc = mesh_actor(world, mesh, nil)
        if actor then
            if mids[1] then pcall(function() pmc:SetMaterial(0, mids[1]) end) end
            pcall(function() actor:SetActorHiddenInGame(true) end)
            pool[#pool + 1] = { actor = actor, pmc = pmc, t = nil, frame = 1, k = 1.0 }
        end
    end
    return { pool = pool, mids = mids, world = world:GetAddress(), next = 1, holder = hold_mids(world, mids) }
end
-- (x, y, z): under his feet, scene cm; k: its size against Mario 64's (1)
function M.dust(x, y, z, k)
    local world = lib.world()
    if not world then return end
    if dust and dust.world ~= world:GetAddress() then dust = nil end
    if not dust then
        local ok, dp = pcall(dust_pool, world)
        if not (ok and dp) then return end
        dust = dp
    end
    local p = dust.pool[dust.next]
    dust.next = dust.next % #dust.pool + 1
    if not p then return end
    local r = 20.0 * 0.75 * 1.4
    p.t, p.frame = 0.0, 0
    p.x, p.y, p.z = x + (math.random() * 2.0 - 1.0) * r, y + (math.random() * 2.0 - 1.0) * r, z
    k = k or 1.0
    if math.abs(k - p.k) > 0.01 then
        p.k = k
        pcall(function() p.actor:SetActorScale3D({ X = k, Y = k, Z = k }) end)
    end
end
local function update_dust(dt, cx, cy)
    if not dust then return end
    for _, p in ipairs(dust.pool) do
        if p.t then
            p.t = p.t + dt
            local f = math.floor(p.t * 30.0) + 1            -- (its picture, 1..7)
            if f > 7 then
                p.t = nil
                pcall(function() p.actor:SetActorHiddenInGame(true) end)
            else
                if f ~= p.frame and dust.mids[f] then
                    local first = p.frame == 0
                    p.frame = f
                    pcall(function()
                        p.pmc:SetMaterial(0, dust.mids[f])
                        if first then p.actor:SetActorHiddenInGame(false) end
                    end)
                end
                local wx, wy = p.x + OFFSET.X, p.y + OFFSET.Y
                local yaw = math.deg(math.atan(cy - wy, cx - wx)) + 180.0
                pcall(function() p.actor:K2_SetActorLocationAndRotation({ X = wx, Y = wy, Z = p.z + OFFSET.Z }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false, {}, true) end)
            end
        end
    end
end

-- ------------------------------------------------------------ the wind seen
-- The level's wind floors shown as Mario 64 shows its wind (strong_wind_particle.inc.c: mist puffs, as the snowman's
-- breath and Fwoosh blow - enemies.lua): over a horizontal wind floor (game.lua G.apply_wind: BitS's, RR's, SL's and
-- THI's) puffs fly its way a little over it; up a vertical wind's column (G.apply_vwind: TTM's, THI's and CCM's chasms)
-- they rise, where nothing stands between them and its floor and no higher than its wind reaches (Mario 64's 2000 over
-- -1500: 375 cm). Near him only. "make sure all wind blowing types in game have a visual queue", 2026-10-29: the floors'
-- winds blew unseen - the snowman's breath, Fwoosh and the tornado had theirs.
M.WIND = { reach = 2500.0, n = 32, h_rate = 18.0, v_rate = 12.0, h_speed = 750.0, v_speed = 600.0, h_life = 1.3,
           v_life = 1.6, h_half = 75.0, v_half = 80.0, alpha = 0.55, top = 375.0, bottom = -3375.0,
           texture = "actors__mist__mist.ia16" }
local wind = nil
local function wind_floors()
    local G = package.loaded["game"]
    local data = G and G.data
    local h, v = {}, {}
    for _, fl in ipairs((data and data.floors) or {}) do
        local tag = tostring(fl.tag or "")
        local d = tonumber(tag:match("^wind:(%-?%d+)$"))
        local isv = tag == "vwind"
        local P, I = fl.pos, fl.idx
        if (d or isv) and P and I then
            for t = 1, #I - 2, 3 do
                local a, b, c = I[t] * 3, I[t + 1] * 3, I[t + 2] * 3
                local A, B, C = { P[a + 1], P[a + 2], P[a + 3] }, { P[b + 1], P[b + 2], P[b + 3] }, { P[c + 1], P[c + 2], P[c + 3] }
                local area = math.abs((B[1] - A[1]) * (C[2] - A[2]) - (C[1] - A[1]) * (B[2] - A[2])) / 2.0
                if area > 100.0 then
                    local cx, cy, cz = (A[1] + B[1] + C[1]) / 3.0, (A[2] + B[2] + C[2]) / 3.0, (A[3] + B[3] + C[3]) / 3.0
                    local r = 0.0
                    for _, q in ipairs({ A, B, C }) do r = math.max(r, math.sqrt((q[1] - cx) ^ 2 + (q[2] - cy) ^ 2)) end
                    local tri = { A, B, C, area = area, cx = cx, cy = cy, cz = cz, r = r }
                    if isv then
                        v[#v + 1] = tri
                    else
                        local ang = (d * 256) * math.pi / 32768.0          -- (its way: Mario 64's x, z are the scene's y, -x)
                        tri.dx, tri.dy = -math.cos(ang), math.sin(ang)
                        h[#h + 1] = tri
                    end
                end
            end
        end
    end
    return h, v
end
local function wind_pool(world)
    local pool = {}
    local mid = lib.get_mid(world, "translucent", M.WIND.texture, M.WIND.alpha)
    for i = 1, M.WIND.n do
        local mesh = { verts = {}, idx = {}, nrms = {}, uvs = {}, cols = {} }
        quad(mesh, 0.0, 0.0, 0.0, 1.0, 0, 1, 0, 0, 0, 1, -1, 0, 0)
        local actor, pmc = mesh_actor(world, mesh, M.WIND.texture)
        if actor then
            if mid and pmc then pcall(function() pmc:SetMaterial(0, mid) end) end
            pcall(function() actor:SetActorHiddenInGame(true) end)
            pool[#pool + 1] = { actor = actor }
        end
    end
    return pool
end
-- one of `list` near him (its share by its area), or nil
local function wind_pick(list, px, py, pz, zr)
    local c, tot = {}, 0.0
    for _, t in ipairs(list) do
        if math.sqrt((t.cx - px) ^ 2 + (t.cy - py) ^ 2) - t.r < M.WIND.reach and (not zr or math.abs(t.cz - pz) < zr) then
            c[#c + 1] = t
            tot = tot + t.area
        end
    end
    if #c == 0 then return nil end
    local r = math.random() * tot
    for _, t in ipairs(c) do r = r - t.area; if r <= 0.0 then return t end end
    return c[#c]
end
local function wind_point(t)
    local r1, r2 = math.random(), math.random()
    if r1 + r2 > 1.0 then r1, r2 = 1.0 - r1, 1.0 - r2 end
    local A, B, C = t[1], t[2], t[3]
    return A[1] + r1 * (B[1] - A[1]) + r2 * (C[1] - A[1]), A[2] + r1 * (B[2] - A[2]) + r2 * (C[2] - A[2]),
           A[3] + r1 * (B[3] - A[3]) + r2 * (C[3] - A[3])
end
local function wind_free()
    for _, p in ipairs(wind.pool) do if not p.t then return p end end
    return nil
end
local function wind_spawn(kind, px, py, pz)
    local W = M.WIND
    local p = wind_free()
    if not p then return end
    if kind == "h" then
        for _ = 1, 4 do
            local t = wind_pick(wind.h, px, py, pz, 1000.0)
            if not t then return end
            local x, y, z = wind_point(t)
            if math.sqrt((x - px) ^ 2 + (y - py) ^ 2) < W.reach then
                p.x, p.y, p.z = x, y, z + 20.0 + math.random() * 200.0
                local s = W.h_speed * (0.8 + math.random() * 0.4)
                p.vx, p.vy, p.vz = t.dx * s, t.dy * s, (math.random() - 0.5) * 60.0
                p.t, p.life, p.half = 0.0, W.h_life * (0.8 + math.random() * 0.4), W.h_half * (0.8 + math.random() * 0.5)
                return
            end
        end
    else
        local G = package.loaded["game"]
        for _ = 1, 4 do
            local t = wind_pick(wind.v, px, py, nil, nil)
            if not t then return end
            local x, y = wind_point(t)
            local lo = math.max(t.cz + 30.0, pz - 900.0, W.bottom)
            local hi = math.min(W.top, pz + 200.0)
            if hi > lo and math.sqrt((x - px) ^ 2 + (y - py) ^ 2) < W.reach then
                local z = lo + math.random() * (hi - lo)
                -- (only where its column is open: no floor of the level's between the puff and the wind's floor)
                local fz = G and G.floor_z and G.floor_z(x, y, z)
                if not (fz and fz > t.cz + 5.0) then
                    p.x, p.y, p.z = x, y, z
                    p.vx, p.vy, p.vz = (math.random() - 0.5) * 60.0, (math.random() - 0.5) * 60.0, W.v_speed * (0.8 + math.random() * 0.4)
                    p.t, p.life, p.half = 0.0, W.v_life * (0.8 + math.random() * 0.4), W.v_half * (0.8 + math.random() * 0.5)
                    return
                end
            end
        end
    end
end
local function update_wind(dt, cx, cy, cz)
    if not wind then return end
    local W = M.WIND
    local px, py, pz
    pcall(function()
        local l = lib.pawn():K2_GetActorLocation()
        px, py, pz = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z
    end)
    if px then
        dt = math.min(dt, 0.1)
        if #wind.h > 0 then
            wind.hacc = wind.hacc + dt * W.h_rate
            while wind.hacc >= 1.0 do wind.hacc = wind.hacc - 1.0; wind_spawn("h", px, py, pz) end
        end
        if #wind.v > 0 then
            wind.vacc = wind.vacc + dt * W.v_rate
            while wind.vacc >= 1.0 do wind.vacc = wind.vacc - 1.0; wind_spawn("v", px, py, pz) end
        end
    end
    -- (each puff drawn every other frame, every third once it is 15 m off - a move and a size, an engine call apiece, for
    -- 20-odd puffs were 1.1 ms of every frame: "I want a significant boost in fps", 2026-11-03 - half of them one frame,
    -- the other half the next; and its size set only once it has changed by a few percent)
    wind.frame = (wind.frame or 0) + 1
    for i, p in ipairs(wind.pool) do
        if p.t then
            p.t = p.t + dt
            if p.t >= p.life then
                p.t = nil
                pcall(function() p.actor:SetActorHiddenInGame(true) end)
                p.shown, p.ls = false, nil
            else
                p.x, p.y, p.z = p.x + p.vx * dt, p.y + p.vy * dt, p.z + p.vz * dt
                local wx, wy, wz = p.x + OFFSET.X, p.y + OFFSET.Y, p.z + OFFSET.Z
                local dx, dy, dz = cx - wx, cy - wy, cz - wz
                local d2 = dx * dx + dy * dy
                local every = (d2 + dz * dz > 1500.0 * 1500.0) and 3 or 2
                if not p.shown or (i + wind.frame) % every == 0 then
                    local k = p.t / p.life
                    local s = p.half * math.min(1.0, k * 4.0, (1.0 - k) * 3.0)      -- (swells in, fades out)
                    pcall(function()
                        p.actor:K2_SetActorLocationAndRotation({ X = wx, Y = wy, Z = wz },
                            { Pitch = -math.deg(math.atan(dz, math.sqrt(d2))), Yaw = math.deg(math.atan(dy, dx)) + 180.0, Roll = 0.0 },
                            false, {}, true)
                        if not p.ls or math.abs(s - p.ls) > 0.04 * p.half then
                            p.ls = s
                            p.actor:SetActorScale3D({ X = 1.0, Y = math.max(0.01, s), Z = math.max(0.01, s) })
                        end
                        if not p.shown then p.shown = true; p.actor:SetActorHiddenInGame(false) end
                    end)
                end
            end
        end
    end
end
local function load_wind(world)
    local okf, h, v = pcall(wind_floors)
    if not okf or (#h == 0 and #v == 0) then return end
    local okp, pool = pcall(wind_pool, world)
    if not (okp and pool and #pool > 0) then return end
    wind = { pool = pool, h = h, v = v, hacc = 0.0, vacc = 0.0 }
    log("wind seen: %d horizontal and %d vertical wind floor triangles", #h, #v)
end

function M.clear()
    if wind then
        for _, p in ipairs(wind.pool) do pcall(lib.destroy, p.actor) end
        wind = nil
    end
    if dust then
        for _, p in ipairs(dust.pool) do pcall(lib.destroy, p.actor) end
        if dust.holder then pcall(lib.destroy, dust.holder) end
        dust = nil
    end
    -- (the wading drops too: kept over a change of scene - the map the same - their actors went with the old scene's,
    -- and the next splash touched them once the engine had freed them: the three crashes of 2026-10-17, 05:18 05:26
    -- 05:45, each in UE4SS with land_water and SetActorHiddenInGame on its stack)
    if wade then
        for _, p in ipairs(wade.pool) do pcall(lib.destroy, p.actor) end
        wade = nil
    end
    if hit then
        for _, p in ipairs(hit.pool) do pcall(lib.destroy, p.actor) end
        hit = nil
    end
    if wave then
        if wave.ring.actor then pcall(lib.destroy, wave.ring.actor) end
        for _, p in ipairs(wave.trail) do if p.actor then pcall(lib.destroy, p.actor) end end
        if wave.holder then pcall(lib.destroy, wave.holder) end
        wave = nil
    end
    if leaf then
        for _, p in pairs(leaf.pool) do if p.inst then pcall(lib.destroy, p.inst.actor) end end
        leaf = nil
    end
    if breath then
        for _, p in ipairs(breath.pool) do pcall(lib.destroy, p.actor) end
        breath = nil
    end
    if num then
        for _, p in ipairs(num.pool) do pcall(lib.destroy, p.actor) end
        if num.holder then pcall(lib.destroy, num.holder) end
        num = nil
    end
    if poof then
        for _, p in ipairs(poof.pool) do pcall(lib.destroy, p.inst.actor) end
        poof = nil
    end
    if spark then
        for _, p in ipairs(spark.pool) do pcall(lib.destroy, p.actor) end
        if spark.holder then pcall(lib.destroy, spark.holder) end
        spark = nil
    end
    if splash then
        for _, p in ipairs(splash.pool) do pcall(lib.destroy, p.actor) end
        if splash.holder then pcall(lib.destroy, splash.holder) end
        splash = nil
    end
    if st then
        if st.actor then pcall(lib.destroy, st.actor) end
        if st.holder then pcall(lib.destroy, st.holder) end
        for _, b in ipairs(st.bubbles or {}) do pcall(lib.destroy, b.actor) end
        for _, s in ipairs(st.streams or {}) do
            for _, b in ipairs(s.bubbles) do pcall(lib.destroy, b.actor) end
        end
    end
    st = nil
end
function M.forget() st, splash, spark, poof, num, breath, leaf, wave, hit, wade, dust, wind = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil end

-- the scene's effect, if it has one (`name`: the scene)
function M.load(world, name)
    M.clear()
    load_wind(world)
    local mode = MODES[name or ""]
    if not mode then return end
    if mode == "streams" then
        local ok, streams = pcall(build_streams, world)
        if ok and streams and #streams > 0 then
            st = { mode = mode, streams = streams, t = 0.0 }
            log("current bubbles: %d streams", #streams)
        end
        return
    end
    if mode == "lava" then
        local ok, bubbles, mids, holder = pcall(build_lava, world)
        if ok and bubbles then
            st = { mode = mode, bubbles = bubbles, mids = mids, t = 0.0, holder = holder }
            log("lava bubbles: %d", #bubbles)
        else
            log("lava bubbles: not built (%s)", tostring(bubbles))
        end
        return
    end
    local F = FIELDS[mode]
    local ok, actor, n = pcall(build_field, world, F)
    if ok and actor then
        st = { mode = mode, F = F, actor = actor, t = 0.0 }
        log("%s: %d flakes round the camera (%d points)", mode, F.PER * F.NX * F.NX * F.NZ, n or 0)
    else
        log("%s: not built (%s)", mode, tostring(actor))
    end
end

-- one bubble somewhere new on the lava near (fx, fy) - scene cm - or nowhere
local function place_bubble(b, fx, fy, fz)
    local G = package.loaded["game"]
    b.frame, b.acc = 0, 0.0
    local x, y = fx + (math.random() * 2.0 - 1.0) * LAVA_REACH, fy + (math.random() * 2.0 - 1.0) * LAVA_REACH
    local z = G and G.lava_z and G.lava_z(x, y, fz + 500.0 * 0.75)
    if z then
        b.x, b.y, b.z = x, y, z
        if not b.shown then b.shown = true; pcall(function() b.actor:SetActorHiddenInGame(false) end) end
    else
        b.x = nil
        if b.shown then b.shown = false; pcall(function() b.actor:SetActorHiddenInGame(true) end) end
    end
end

-- (one bubble of a current, Mario 64 units: a jet stream's rising and spreading, a whirlpool's swirling in and down)
local function stream_bubble(b, w, jet)
    b.age = 0
    local a = math.random() * 2.0 * math.pi
    if jet then
        local r = math.random() * 150.0
        b.x, b.y, b.z = w.pos[1] + r * math.cos(a), w.pos[2], w.pos[3] + r * math.sin(a)
        b.vx, b.vy, b.vz = math.cos(a) * 3.0, 14.0 + math.random() * 8.0, math.sin(a) * 3.0
        b.life = 35 + math.random(0, 20)
    else
        b.ang, b.rad, b.y = a, 500.0 + math.random() * 500.0, w.pos[2] + math.random() * 500.0
        b.life = 120
    end
end
local function update_streams(dt, cx, cy, cz)
    local G = package.loaded["game"]
    local pawn = lib.pawn()
    local mx, my, mz = 0.0, 0.0, 0.0
    pcall(function() local l = pawn:K2_GetActorLocation(); mx, my, mz = (l.Y - OFFSET.Y) / 0.75, (l.Z - OFFSET.Z) / 0.75, -(l.X - OFFSET.X) / 0.75 end)
    st.acc = (st.acc or 0.0) + dt
    local steps = 0
    while st.acc >= 1.0 / 30.0 and steps < 4 do st.acc = st.acc - 1.0 / 30.0; steps = steps + 1 end
    for _, s in ipairs(st.streams) do
        local w = s.w
        local on = w.cond == 0 or w.cond == 1 or (w.cond == 3 and ((G and G.act) or 1) >= 2)
        local near = (w.pos[1] - mx) ^ 2 + (w.pos[2] - my) ^ 2 + (w.pos[3] - mz) ^ 2 < 4000.0 * 4000.0
        local jet = w.strength < 0
        for _, b in ipairs(s.bubbles) do
            if not (on and near) then
                if b.shown then b.shown = false; pcall(function() b.actor:SetActorHiddenInGame(true) end) end
            else
                for _ = 1, steps do
                    b.age = b.age + 1
                    if b.age > b.life then stream_bubble(b, w, jet) end
                    if b.age < 0 or not (jet and b.vx or b.ang) then
                        -- (not out yet: the bubbles start staggered, and one not yet blown has no way to go)
                    elseif jet then
                        b.x, b.y, b.z = b.x + b.vx, b.y + b.vy, b.z + b.vz
                    else
                        b.ang = b.ang + 0.08 + 40.0 / math.max(b.rad, 60.0)
                        b.rad = math.max(20.0, b.rad - 8.0)
                        b.y = b.y - 5.0
                        b.x, b.z = w.pos[1] + b.rad * math.cos(b.ang), w.pos[3] + b.rad * math.sin(b.ang)
                        if b.rad <= 20.0 then b.age = b.life + 1 end
                    end
                end
                if b.x then
                    if not b.shown then b.shown = true; pcall(function() b.actor:SetActorHiddenInGame(false) end) end
                    local wx, wy, wz = -b.z * 0.75 + OFFSET.X, b.x * 0.75 + OFFSET.Y, b.y * 0.75 + OFFSET.Z
                    local yaw = math.deg(math.atan(cy - wy, cx - wx)) + 180.0
                    pcall(function() b.actor:K2_SetActorLocationAndRotation({ X = wx, Y = wy, Z = wz }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false, {}, true) end)
                end
            end
        end
    end
end

M.WIND_SNOW = 900.0
function M.update(dt)
    if not (st or splash or spark or poof or num or breath or leaf or wave or hit or dust or wind) then return end
    local cx, cy, cz = lib.camera_location(OFFSET)
    update_wind(dt, cx, cy, cz)
    update_dust(dt, cx, cy)
    update_breath(dt, cx, cy)
    update_leaf(dt)
    update_waves(dt)
    update_hit(dt, cx, cy)
    update_num(dt, cx, cy)
    update_splash(dt, cx, cy)
    update_spark(dt, cx, cy)
    update_poof(dt, cx, cy)
    if not st then return end
    st.t = st.t + dt
    if st.mode == "streams" then update_streams(dt, cx, cy, cz); return end
    if st.mode == "lava" then
        -- (its focus: the athlete, as the camera's)
        local pawn = lib.pawn()
        local fx, fy, fz = cx - OFFSET.X, cy - OFFSET.Y, cz - OFFSET.Z
        pcall(function() local l = pawn:K2_GetActorLocation(); fx, fy, fz = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z end)
        for _, b in ipairs(st.bubbles) do
            b.acc = b.acc + dt
            if b.acc >= 2.0 / 30.0 then
                b.acc = b.acc - 2.0 / 30.0
                b.frame = b.frame + 1
                if b.frame > 8 then
                    place_bubble(b, fx, fy, fz)
                elseif b.x and b.frame >= 1 and st.mids[b.frame] then
                    pcall(function() b.pmc:SetMaterial(0, st.mids[b.frame]) end)
                end
            end
            if b.x and b.shown then
                local wx, wy = b.x + OFFSET.X, b.y + OFFSET.Y
                local yaw = math.deg(math.atan(cy - wy, cx - wx)) + 180.0
                pcall(function() b.actor:K2_SetActorLocationAndRotation({ X = wx, Y = wy, Z = b.z + OFFSET.Z }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false, {}, true) end)
            end
        end
        return
    end
    local F = st.F
    local fall = (st.t * F.FALL) % F.H
    -- (blown along a wind floor's way while he is on one - game.lua's G.wind_dir: the snow flies past him at WIND_SNOW
    -- cm/s, the wind seen - "theres no visual", 2026-10-26. Wrapped at a tile: the field repeats.)
    local G = package.loaded["game"]
    local wd = G and G.wind_dir
    if wd then
        local a = (wd * 256) * math.pi / 32768.0
        st.wx = ((st.wx or 0.0) - math.cos(a) * M.WIND_SNOW * dt) % F.W
        st.wy = ((st.wy or 0.0) + math.sin(a) * M.WIND_SNOW * dt) % F.W
    end
    local x0 = math.floor(cx / F.W) * F.W - (F.NX / 2) * F.W + math.sin(st.t * 0.6) * F.SWAY + (st.wx or 0.0)
    local y0 = math.floor(cy / F.W) * F.W - (F.NX / 2) * F.W + math.cos(st.t * 0.45) * F.SWAY * 0.7 + (st.wy or 0.0)
    local z0 = math.floor(cz / F.H) * F.H - F.H - fall
    pcall(function() st.actor:K2_SetActorLocation({ X = x0, Y = y0, Z = z0 }, false, {}, true) end)
end

return M
