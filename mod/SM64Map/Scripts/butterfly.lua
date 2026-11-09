-- SM64Map: Mario 64's butterflies (game/behaviors/butterfly.inc.c and triplet_butterfly.inc.c).
--
-- A single butterfly rests on the ground, wings slowly opening and closing. Come within reach and it takes off
-- and flutters round the athlete, bobbing; go far enough from its spot and it flies home and settles again.
-- A triplet is hidden until the athlete walks right up to it: then three butterflies scatter from the spot and
-- wander about it. One of them, picked at random, turns into a 1-up when he comes close again. Where the triplet may
-- hold bombs (Tiny-Huge Island, Tall Tall Mountain) the other two, come close to, go up in a puff and are a bomb: it
-- swells over a second, then flies at him, homing, up to 20 a frame - and blows up on him (two wedges), or after
-- 158 frames, throbbing for the last 38 (triplet_butterfly_act_activate / _explode).
--
-- The model, its two animations and the places come from the player's own copy (exporter/butterflyx.py ->
-- data/actor_butterfly.lua, data/butterflies.lua). Mario 64's numbers are per frame in its units; here they are
-- turned into centimetres (0.75 to a unit) and seconds (30 frames to one).
local lib = require("lib")
local log = lib.log
local B = {}

local OFFSET = lib.OFFSET
local sin, cos, atan, sqrt, rad, deg, pi, min, max, abs, random =
    math.sin, math.cos, math.atan, math.sqrt, math.rad, math.deg, math.pi, math.min, math.max, math.abs, math.random

local U = 0.75                      -- centimetres to a Mario 64 unit
local FPS = 30.0
local FLY, REST = 1, 2              -- the animations: the quick flap, and the slow one at rest
local NEAR = 1000 * U               -- a resting butterfly takes off when the athlete comes this close
local LEASH = 1200 * U              -- and goes home when he is this far from its spot
local SEEN = 3000 * U               -- it is only drawn this close to him
local STEP = 7 * U * FPS            -- how fast it flies (cm a second)
local TRIPLET_NEAR = 200 * U        -- a triplet comes out, and its 1-up butterfly turns, this close to him
-- (no bombs: a triplet's other two butterflies stay butterflies, its 1-up as it was - "remove them for all stars
-- completely", Tiny-Huge Island, 2026-11-07)
B.BOMBS = false

local list = {}                     -- every butterfly of the scene
local triplets = {}                 -- triplet spots that have not come out yet
local data = nil
local floor_z = nil                 -- (game.lua's lookup of the level's floor: x, y, zmax -> z)
local add_pickup = nil
local actor_data = nil              -- (game.lua's model loader: the bomb is the bowling ball's, a bob-omb billboard)
local BOMB_SCALE = 0.5

local function wrap(a) return (a + pi) % (2.0 * pi) - pi end
local function turn(from, to, step) local d = wrap(to - from); return from + max(-step, min(step, d)) end
local function approach(from, to, step) if from < to then return min(to, from + step) end return max(to, from - step) end

local function make(world, x, y, z, anim)
    local inst = lib.make_instance(world, data, { X = x + OFFSET.X, Y = y + OFFSET.Y, Z = z + OFFSET.Z }, 0.0, 1.0)
    if not inst then return nil end
    local b = { inst = inst, x = x, y = y, z = z, hx = x, hy = y, hz = z, heading = random() * 2.0 * pi, pitch = 0.0,
                anim = anim, f = random() * 7.0, phase = random() * 100.0, shown = true, t = 0.0 }
    list[#list + 1] = b
    return b
end

-- Build the scene's butterflies. `places` is data/butterflies.lua's entry for the scene (or nil).
function B.load(world, places, opts)
    B.clear()
    if not places then return 0 end
    data = data or lib.load_data("data.actor_butterfly")
    if not data then log("butterflies: no model"); return 0 end
    floor_z, add_pickup, actor_data = opts.floor_z, opts.add_pickup, opts.actor_data
    for _, p in ipairs(places.single or {}) do
        local x, y, z = p[1], p[2], p[3]
        local fz = floor_z and floor_z(x, y, z + 100.0)
        if fz then z = fz end                                   -- (DROP_TO_FLOOR)
        local b = make(world, x, y, z, REST)
        if b then b.kind, b.state = "single", "rest" end
    end
    for _, t in ipairs(places.triplet or {}) do
        triplets[#triplets + 1] = { x = t.pos[1], y = t.pos[2], z = t.pos[3], bombs = t.bombs, world = world }
    end
    log("butterflies: %d, and %d triplets waiting", #list, #triplets)
    return #list
end

function B.clear()
    for _, b in ipairs(list) do lib.destroy(b.inst and b.inst.actor) end
    list, triplets = {}, {}
end

local function show(b, on)
    if b.shown ~= on then
        b.shown = on
        pcall(function() b.inst.actor:SetActorHiddenInGame(not on) end)
    end
end

-- the three butterflies of a triplet, out of their spot
local function come_out(t)
    local pick = random(0, 2)
    for i = 0, 2 do
        local b = make(t.world, t.x, t.y, t.z, FLY)
        if b then
            b.kind, b.state = "triplet", "wander"
            b.base = rad(i * 120.0)
            b.heading = b.base + random() * rad(120.0)
            b.speed = (15.0 + random() * 15.0) * U * FPS
            b.oneup = (i == pick)
            b.bomb = B.BOMBS and (not b.oneup) and t.bombs and true or nil
        end
    end
end

-- A bomb butterfly once it is a bomb: swelling to its size over 30 frames, then after him - its speed up to 20 a frame,
-- turning 800 a frame toward his middle - for 158 frames, throbbing from 120; touching him (its 100 round) it blows up
-- on him: two wedges. True when it has gone off.
local function bomb_explode(b, hit)
    local BO = package.loaded["bobomb"]
    local w = lib.world()
    if BO and BO.explode_at and w then pcall(BO.explode_at, w, b.y / U, b.z / U, -b.x / U) end
    local SX = package.loaded["sfx"]
    if SX and SX.play then pcall(SX.play, "explosion", 1.0) end
    local HP = _G.HEALTH
    if hit and HP and HP.damage then pcall(HP.damage, 2, "a butterfly bomb") end
    log("butterfly bomb: %s", hit and "blew up on him" or "went off")
end
local function bomb_step(b, dt, k, px, py, pz)
    b.frames = b.frames + k
    if b.state == "growing" then
        b.scale = math.min(BOMB_SCALE, b.scale + BOMB_SCALE / 30.0 * k)
        if b.scale >= BOMB_SCALE then b.state, b.frames = "bomb", 0.0 end
        return false
    end
    -- (his middle: 90 over his feet)
    local tx, ty, tz = px, py, pz + 90.0
    local dx, dy, dz = tx - b.x, ty - b.y, tz - b.z
    local h = sqrt(dx * dx + dy * dy)
    if sqrt(h * h + dz * dz) < 100.0 * U + 40.0 then bomb_explode(b, true); return true end
    if b.frames >= 158.0 then bomb_explode(b, false); return true end
    b.speed = approach(b.speed, 20.0 * U * FPS, 1.0 * U * FPS * k)
    local step = rad(800 / 65536.0 * 360.0) * k
    b.heading = turn(b.heading, atan(dy, dx), step)
    b.pitch = turn(b.pitch, atan(dz, h), step)
    local s = b.speed * dt
    b.x, b.y = b.x + cos(b.heading) * cos(b.pitch) * s, b.y + sin(b.heading) * cos(b.pitch) * s
    b.z = b.z + sin(b.pitch) * s
    local fz = floor_z and floor_z(b.x, b.y, b.z + 50.0)
    if fz and b.z < fz + 40.0 then b.z = fz + 40.0 end
    if b.frames > 120.0 then
        -- (it throbs: quickly up, slowly down)
        b.phase2 = (b.phase2 or 0.0)
        local inc = 0.04 * cos(b.phase2 * pi / 32768.0) * k
        if inc > 0.0 then inc = inc * 4.5; b.phase2 = b.phase2 + 10000 * k else b.phase2 = b.phase2 + 4000 * k end
        b.scale = math.max(0.1, b.scale + inc)
    end
    return false
end

-- Every tick. (px, py, pz): the athlete's feet, scene space; pyaw his facing (degrees).
function B.update(dt, px, py, pz, pyaw)
    if #list == 0 and #triplets == 0 then return end
    local k = dt * FPS                                          -- Mario 64 frames this tick
    for i = #triplets, 1, -1 do
        local t = triplets[i]
        local dx, dy, dz = px - t.x, py - t.y, pz - t.z
        if dx * dx + dy * dy + dz * dz < TRIPLET_NEAR * TRIPLET_NEAR then
            table.remove(triplets, i)
            come_out(t)
        end
    end
    for i = #list, 1, -1 do
        local b = list[i]
        b.t = b.t + dt
        local dx, dy, dz = px - b.x, py - b.y, pz - b.z
        local d2 = dx * dx + dy * dy + dz * dz
        local moving = true
        if b.state == "rest" then
            moving = false
            if d2 < NEAR * NEAR then
                b.state, b.anim = "follow", FLY
                b.heading = rad(pyaw or 0.0)
            end
        elseif b.state == "follow" then
            -- toward him, a little off to one side and above, by how far its bob has got
            local off = 5.0 * b.phase / 4.0 * U
            local tx, ty = px - off, py + off                    -- (Mario 64's +x/+z, in this scene's axes)
            local tz = pz + (5.0 * b.phase + 256.0) / 4.0 * U
            b.heading = turn(b.heading, atan(ty - b.y, tx - b.x), rad(0x300 / 65536.0 * 360.0) * k)
            local h = sqrt((tx - b.x) ^ 2 + (ty - b.y) ^ 2)
            b.pitch = turn(b.pitch, atan(tz - b.z, h), rad(0x500 / 65536.0 * 360.0) * k)
            local hx, hy, hz = px - b.hx, py - b.hy, pz - b.hz
            if hx * hx + hy * hy + hz * hz > LEASH * LEASH then b.state = "home" end
        elseif b.state == "home" then
            local hx, hy, hz = b.hx - b.x, b.hy - b.y, b.hz - b.z
            b.heading = turn(b.heading, atan(hy, hx), rad(0x800 / 65536.0 * 360.0) * k)
            b.pitch = turn(b.pitch, atan(hz, sqrt(hx * hx + hy * hy)), rad(0x50 / 65536.0 * 360.0) * k)
            if hx * hx + hy * hy + hz * hz < (12 * U) ^ 2 then
                b.state, b.anim = "rest", REST
                b.x, b.y, b.z, b.pitch = b.hx, b.hy, b.hz, 0.0
                moving = false
            end
        elseif b.state == "wander" then
            b.speed = approach(b.speed, 8.0 * U * FPS, 0.5 * U * FPS * k)
            local target
            if b.t < 60.0 / FPS then target = atan(b.hy - b.y, b.hx - b.x) else target = b.base end
            if floor_z then
                local fz = floor_z(b.x, b.y, b.z + 100.0)
                if fz and b.hz < fz then b.hz = fz end
            end
            local want = (b.z < b.hz + (50.0 + random() * 50.0) * U) and rad(45.0) or rad(-45.0)
            b.pitch = turn(b.pitch, want, rad(400 / 65536.0 * 360.0) * k)
            b.heading = turn(b.heading, target, rad((400 + random() * 800) / 65536.0 * 360.0) * k)
            if (b.oneup or b.bomb) and b.t > 110.0 / FPS and d2 < TRIPLET_NEAR * TRIPLET_NEAR then
                b.state, b.turned = "turning", b.t
            end
        elseif b.state == "turning" then
            moving = false
            if b.t - b.turned > 20.0 / FPS and b.bomb then
                -- a puff, and in its place a bomb, growing
                local EF = package.loaded["envfx"]
                if EF and EF.poof then pcall(EF.poof, b.x, b.y, b.z - 40.0 * U, 0.6) end
                lib.destroy(b.inst.actor)
                local bd = actor_data and actor_data("geo_bowling_ball_geo")
                local inst = bd and lib.make_instance(b.inst.world or lib.world(), bd,
                    { X = b.x + OFFSET.X, Y = b.y + OFFSET.Y, Z = b.z + OFFSET.Z }, 0.0, 0.01)
                if inst then
                    inst.moves = true
                    b.inst, b.state, b.scale, b.frames, b.speed, b.ball = inst, "growing", 0.0, 0.0, 0.0, true
                else
                    table.remove(list, i)
                    b = nil
                end
            elseif b.t - b.turned > 20.0 / FPS then
                -- it turns into a 1-up where it was
                if add_pickup then pcall(add_pickup, { kind = "oneup", pos = { b.x, b.y, b.z } }) end
                lib.destroy(b.inst.actor)
                table.remove(list, i)
                b = nil
            end
        elseif b.state == "growing" or b.state == "bomb" then
            moving = false
            local gone = bomb_step(b, dt, k, px, py, pz)
            if gone then
                lib.destroy(b.inst.actor)
                table.remove(list, i)
                b = nil
            end
        end
        if b and b.ball then
            -- (the bomb: drawn at its size, turned to the camera)
            pcall(function()
                local s = math.max(0.01, b.scale)
                b.inst.actor:K2_SetActorLocation({ X = b.x + OFFSET.X, Y = b.y + OFFSET.Y, Z = b.z + OFFSET.Z }, false, {}, true)
                b.inst.actor:SetActorScale3D({ X = s, Y = s, Z = s })
            end)
            pcall(lib.face_camera, b.inst, b.x + OFFSET.X, b.y + OFFSET.Y)
        elseif b then
            if moving then
                if b.kind == "triplet" then
                    local s = b.speed * dt
                    b.x, b.y = b.x + cos(b.heading) * cos(b.pitch) * s, b.y + sin(b.heading) * cos(b.pitch) * s
                    b.z = b.z + sin(b.pitch) * s
                else
                    local s = STEP * dt
                    b.x, b.y = b.x + cos(b.heading) * s, b.y + sin(b.heading) * s
                    b.z = b.z + sin(b.pitch) * s
                    if b.state == "follow" then b.z = b.z - cos(b.phase * 0.01 * 2.0 * pi) * 5.0 * U * k end
                end
                local fz = floor_z and floor_z(b.x, b.y, b.z + 50.0)
                if fz and b.z < fz + 2.0 * U then b.z = fz + 2.0 * U end
                b.phase = b.phase + k
                if b.phase >= 101.0 then b.phase = b.phase - 101.0 end
            end
            local near = d2 < SEEN * SEEN
            show(b, near)
            if near then
                if moving or not b.placed then
                    b.placed = true
                    lib.set_pose(b.inst, b.x + OFFSET.X, b.y + OFFSET.Y, b.z + 5.0 * U + OFFSET.Z, deg(b.heading) + 180.0)
                end
                local anim = data.anims[b.anim]
                b.f = b.f + k
                if anim then lib.pose(b.inst, anim, b.f) end
            end
        end
    end
end

-- The map went: forget the butterflies without touching them (they went with it).
function B.forget() list, triplets = {}, {} end

function B.count() return #list, #triplets end     -- (tests)
function B.list() return list end

return B
