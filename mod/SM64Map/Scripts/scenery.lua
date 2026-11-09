-- SM64Map: the castle grounds' living scenery, as Mario 64 has it (levels/castle_grounds/script.c and macro.inc.c):
--
--   flags      the four flags on the castle's towers, waving (bhvCastleFlagWaving)
--   birds      three flocks, out of sight until the athlete comes near; then seven birds burst up and fly off
--              over the castle (bird.inc.c: one leads, six follow it)
--   fish       a school of twenty in the lake by the waterfall, drifting up to him and darting off when he
--              comes too close (fish.inc.c)
--   mist       nine sheets of mist lying on the water at the foot of the waterfall, never still (water_mist.inc.c)
--   1-ups      one at the top of the tall tree by the castle wall, for whoever climbs up to it; and one that
--              only appears once he has passed both of its two markers (the hidden 1-up triggers)
--   Yoshi      on the castle roof, once all 120 stars are in
--
-- Models, animations and places come from the player's own copy (exporter/groundsx.py). Mario 64's numbers are
-- per frame in its units: here centimetres (0.75 to a unit) and seconds (30 frames to one).
local lib = require("lib")
local log = lib.log
local M = {}

local OFFSET = lib.OFFSET
local sin, cos, atan, sqrt, rad, deg, pi, min, max, abs, random =
    math.sin, math.cos, math.atan, math.sqrt, math.rad, math.deg, math.pi, math.min, math.max, math.abs, math.random

local U, FPS = 0.75, 30.0
local A = 360.0 / 65536.0           -- one Mario 64 angle step, in degrees

local st = nil                      -- everything built for the scene
local env = {}                      -- the game's helpers: floor_z, water_at, add_pickup, stars

local function wrap(a) return (a + pi) % (2.0 * pi) - pi end
local function turn(from, to, step) local d = wrap(to - from); return from + max(-step, min(step, d)) end
local function wloc(x, y, z) return { X = x + OFFSET.X, Y = y + OFFSET.Y, Z = z + OFFSET.Z } end

-- Models Mario 64 draws from both sides (its cloth flags, birds' and fishes' fins): their opaque triangles get a
-- reversed copy, or seen from behind they vanish (2026-10-14: the flags were gone from behind the castle).
local TWO_SIDED = { castle_flag = true, birds = true, blue_fish = true }
local TOP_FLAG = { 3015.0, 0.0, 5706.0 }        -- the tip of the main tower's roof (scene_grounds' highest point)

local actors = {}
local function actor(name)
    if actors[name] == nil then
        local data = lib.load_data("data.actor_" .. name) or false
        if data and TWO_SIDED[name] then
            for _, p in ipairs(data.parts or {}) do
                for _, sec in ipairs(p.sections or {}) do
                    if sec.layer == "opaque" and not sec.two_sided then
                        local idx, n = sec.idx, #sec.idx
                        for t = 0, n // 3 - 1 do
                            idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = idx[t * 3 + 1], idx[t * 3 + 3], idx[t * 3 + 2]
                        end
                        sec.ntris = (sec.ntris or n // 3) * 2
                        sec.two_sided = true
                    end
                end
            end
        end
        actors[name] = data
    end
    return actors[name] or nil
end

local function make(world, name, x, y, z, yaw)
    local data = actor(name)
    if not data then return nil end
    local inst = lib.make_instance(world, data, wloc(x, y, z), yaw or 0.0, 1.0)
    if inst then st.all[#st.all + 1] = inst.actor end
    return inst
end

local function hide(inst, on) pcall(function() inst.actor:SetActorHiddenInGame(on) end) end

-- (the mist is see-through with the glTF blend material: the translucent widget material drew the waterfall,
-- which shares its look, solid black)
local BLEND = "/InterchangeAssets/gltf/MaterialInstances/MI_Unlit_Blend.MI_Unlit_Blend"
local function see_through(world, actor, texture, alpha)
    pcall(function()
        local parent, tex = lib.try_load(BLEND), lib.texture(world, texture)
        if not (parent and tex) then return end
        local KML = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
        local mid = KML:CreateDynamicMaterialInstance(world, parent, FName(string.format("SM64Mist_%d_%d", math.floor(os.clock() * 1000), random(1, 1000000))), 0)
        mid:SetTextureParameterValue(FName("BaseColorTexture"), tex)
        mid:SetVectorParameterValue(FName("BaseColorFactor"), { R = 1.0, G = 1.0, B = 1.0, A = alpha })
        local pmc = actor:GetComponentByClass(StaticFindObject("/Script/ProceduralMeshComponent.ProceduralMeshComponent"))
        pmc:SetMaterial(0, mid)
    end)
end

-- ------------------------------------------------------------ building
function M.load(world, life, helpers)
    M.clear()
    if not life then return false end
    env = helpers or {}
    st = { world = world, all = {}, flags = {}, flocks = {}, birds = {}, schools = {}, fish = {}, mist = {}, t = 0.0,
           tanks = {}, tank_fish = {} }
    local flags = {}
    for _, f in ipairs(life.flags or {}) do flags[#flags + 1] = f end
    -- (one more on the main tower, where Mario 64 has none: asked 2026-10-14, "add the flag to the top of the
    -- castle". It stands on the tip of the tower's roof, as the four corner flags stand on the tips of theirs.)
    if #flags > 0 then flags[#flags + 1] = { pos = TOP_FLAG, yaw = 0.0 } end
    for _, f in ipairs(flags) do
        local inst = make(world, "castle_flag", f.pos[1], f.pos[2], f.pos[3], f.yaw or 0.0)
        if inst then st.flags[#st.flags + 1] = { inst = inst, f = random() * 29.0 } end       -- (bhv_castle_flag_init)
    end
    for _, b in ipairs(life.bird_flocks or {}) do st.flocks[#st.flocks + 1] = { x = b.pos[1], y = b.pos[2], z = b.pos[3] } end
    for _, s in ipairs(life.fish_schools or {}) do
        st.schools[#st.schools + 1] = { x = s.pos[1], y = s.pos[2], z = s.pos[3], count = s.count or 20 }
    end
    for _, t in ipairs(life.tanks or {}) do
        st.tanks[#st.tanks + 1] = { x = t.pos[1], y = t.pos[2], z = t.pos[3], count = t.count or 15 }
    end
    for _, m in ipairs(life.mist or {}) do
        local a = lib.quad_actor(world, wloc(m.pos[1], m.pos[2], m.pos[3]), 50.0 * 21.0 * U / 2.0, "mist_sprite", "translucent")
        if a then
            see_through(world, a, "mist_sprite", 0.9)       -- (Mario 64: opacity 200-250 of 255)
            st.all[#st.all + 1] = a
            st.mist[#st.mist + 1] = { actor = a, x = m.pos[1], y = m.pos[2], z = m.pos[3] }
        end
    end
    if life.yoshi and life.yoshi[1] and env.stars and env.stars() >= 120 then
        local p = life.yoshi[1].pos
        local z = (env.floor_z and env.floor_z(p[1], p[2], p[3] + 200.0)) or p[3]
        local yaw = random() * 360.0
        st.yoshi = { inst = make(world, "yoshi", p[1], p[2], z, yaw), f = 0.0, x = p[1], y = p[2], z = z, yaw = yaw }
    end
    st.pole = life.hidden_1up_pole and life.hidden_1up_pole[1] and { x = life.hidden_1up_pole[1].pos[1], y = life.hidden_1up_pole[1].pos[2],
                                                                    z = life.hidden_1up_pole[1].pos[3] } or nil
    st.triggers = {}
    for _, t in ipairs(life.hidden_1up_triggers or {}) do st.triggers[#st.triggers + 1] = { x = t.pos[1], y = t.pos[2], z = t.pos[3] } end
    st.hidden = life.hidden_1up and life.hidden_1up[1] and life.hidden_1up[1].pos or nil
    st.waterfall = life.waterfall_sound and life.waterfall_sound[1] and life.waterfall_sound[1].pos or nil
    log("castle grounds scenery: %d flags, %d flocks, %d fish schools, %d mist, yoshi=%s", #st.flags, #st.flocks,
        #st.schools, #st.mist, tostring(st.yoshi ~= nil))
    return true
end

function M.clear()
    if st then for _, a in ipairs(st.all) do lib.destroy(a) end end
    st = nil
end

-- ------------------------------------------------------------ the birds
local function flock_up(fl)
    local parent = nil
    for i = 0, 6 do
        local inst = make(st.world, "birds", fl.x, fl.y, fl.z, 0.0)
        if inst then
            local b = { inst = inst, x = fl.x, y = fl.y, z = fl.z, heading = random() * 2.0 * pi,
                        pitch = rad((5000 - 4000 * random()) * A) * -1.0,         -- (Mario 64: nose a little down)
                        speed = 40.0 * U * FPS, f = random() * 7.0, roll = 0.0 }
            if i == 0 then b.lead, parent = true, b else b.parent = parent end
            st.birds[#st.birds + 1] = b
        end
    end
    if env.sound then env.sound("birds_fly_away") end
end

local function update_birds(dt, k)
    for i = #st.birds, 1, -1 do
        local b = st.birds[i]
        local tyaw, tpitch
        if b.lead then
            -- the leader makes for a point high over the castle (Mario 64: (-20, -3990) at 10000 units up)
            local hx, hy = -(-3990) * U, -20 * U
            local dist = sqrt((hx - b.x) ^ 2 + (hy - b.y) ^ 2)
            tpitch = atan(10000.0 * U - b.z, dist)
            tyaw = atan(hy - b.y, hx - b.x)
        else
            local p = b.parent
            local dist = sqrt((p.x - b.x) ^ 2 + (p.y - b.y) ^ 2)
            tpitch = atan(p.z - b.z, dist)
            tyaw = atan(p.y - b.y, p.x - b.x)
            b.speed = (0.04 * sqrt(dist * dist + (p.z - b.z) ^ 2) / U + 20.0) * U * FPS
        end
        b.pitch = turn(b.pitch, tpitch, rad(140 * A) * k)
        local before = b.heading
        b.heading = turn(b.heading, tyaw, rad(800 * A) * k)
        local s = b.speed * dt
        b.x, b.y = b.x + cos(b.heading) * cos(b.pitch) * s, b.y + sin(b.heading) * cos(b.pitch) * s
        b.z = b.z + sin(b.pitch) * s
        local lead = b.lead and b or b.parent
        if lead.z > 8000.0 * U then
            lib.destroy(b.inst.actor)
            table.remove(st.birds, i)
        else
            lib.set_pose(b.inst, b.x + OFFSET.X, b.y + OFFSET.Y, b.z + OFFSET.Z, deg(b.heading) + 180.0)
            b.f = b.f + k
            local data = actor("birds")
            if data and data.anims[1] then lib.pose(b.inst, data.anims[1], b.f) end
        end
    end
end

-- ------------------------------------------------------------ the fish
-- (water a fish can be in: inside one of the level's water boxes, and the ground there under its surface - Mario 64's
-- box for the grounds runs on under all of it at the lake's height, and the school followed him out of the lake to
-- swim under the grass: "fish on land", 2026-10-22. Ground up to 3 m over the water counts, a bridge higher up not.)
local function water_here(x, y)
    local wl = env.water_at and env.water_at(x, y)
    if not wl then return nil end
    local fz = env.floor_z and env.floor_z(x, y, wl + 300.0)
    if not fz or fz > wl - 60.0 * U then return nil end
    return wl, fz
end
-- a place in the water round a school's middle
local function spot(sc)
    local x, y, wl, fz
    for _ = 1, 40 do
        x = sc.x + (random() * 2.0 - 1.0) * 700.0 * U
        y = sc.y + (random() * 2.0 - 1.0) * 700.0 * U
        wl, fz = water_here(x, y)
        if wl then break end
    end
    if not wl then x, y = sc.x, sc.y; wl = env.water_at and env.water_at(x, y) end
    local z = sc.z + (random() * 2.0 - 1.0) * 700.0 * U
    if wl then z = min(z, wl - 50.0 * U) end
    if fz then z = max(z, fz + 30.0) end
    return x, y, z
end
local function school_out(sc)
    for i = 1, sc.count do
        local x, y, z = spot(sc)
        local inst = make(st.world, "blue_fish", x, y, z, 0.0)
        if inst then
            st.fish[#st.fish + 1] = { inst = inst, x = x, y = y, z = z, home = sc, heading = random() * 2.0 * pi,
                                      state = "roam", t = 0.0, f = random() * 30.0, speed = (random() * 2.0 + 3.0) * U * FPS,
                                      lift = random() * 100.0 * U, reach = (random() * 500.0 + 200.0) * U }
        end
    end
end

local function update_fish(dt, k, px, py, pz)
    local data = actor("blue_fish")
    for _, f in ipairs(st.fish) do
        f.t = f.t + dt
        local dx, dy = px - f.x, py - f.y
        local d = sqrt(dx * dx + dy * dy + (pz - f.z) ^ 2)
        local to_him = atan(dy, dx)
        if f.state == "roam" then
            f.heading = turn(f.heading, to_him, rad(0x400 * A) * k)
            f.speed = (f.speed0 or f.speed)
            if d < f.reach + 150.0 * U then
                f.state, f.t = "flee", 0.0
                f.speed0 = f.speed0 or f.speed
                f.speed = (random() * 4.0 + 13.0) * U * FPS
                f.spin = rad((random() * 1024.0 + 1024.0) * A) * (random() < 0.5 and -1.0 or 1.0)
            end
        else
            -- away from him, fast, for a moment
            f.heading = turn(f.heading, to_him + pi, abs(f.spin) * k)
            if f.t > 2.0 and d > f.reach + 150.0 * U then f.state, f.speed = "roam", f.speed0 end
        end
        -- (one out of the water - left there before it knew the lake's shore - is put back in its school)
        if not water_here(f.x, f.y) then
            f.x, f.y, f.z = spot(f.home)
            f.state, f.speed = "roam", f.speed0 or f.speed
        end
        local s = f.speed * dt
        local nx, ny = f.x + cos(f.heading) * s, f.y + sin(f.heading) * s
        local wl = water_here(nx, ny)
        if wl then                                   -- (a fish never leaves the water)
            f.x, f.y = nx, ny
            local goal = min(pz + f.lift, wl - 50.0 * U)
            local fz = env.floor_z and env.floor_z(f.x, f.y, f.z + 50.0)
            if fz then goal = max(goal, fz + 30.0) end
            local step = 2.0 * U * FPS * dt
            if goal > f.z then f.z = min(goal, f.z + step) else f.z = max(goal, f.z - step) end
        else
            f.heading = f.heading + pi * 0.5
        end
        lib.set_pose(f.inst, f.x + OFFSET.X, f.y + OFFSET.Y, f.z + OFFSET.Z, deg(f.heading) + 180.0)
        f.f = f.f + k * ((f.state == "flee") and 2.0 or 1.0)
        if data and data.anims[1] then lib.pose(f.inst, data.anims[1], f.f) end
    end
end

-- ------------------------------------------------------------ the castle aquarium's fish
-- (blue_fish.inc.c bhv_blue_fish_movement_loop: forward 3-5 a frame, diving or climbing a little for 60-90 frames,
-- then turning 0x800 a frame for 15 frames - nearly about - and the other way up again: back and forth in the tank.
-- They swim in the castle's aquarium, which has no water box: no water is asked of them.)
local function tank_out(t)
    for i = 1, t.count do
        local inst = make(st.world, "blue_fish", t.x, t.y, t.z, 0.0)
        if inst then
            st.tank_fish[#st.tank_fish + 1] = { inst = inst, home = t,
                x = t.x + (random() * 2.0 - 1.0) * 200.0 * U, y = t.y + (random() * 2.0 - 1.0) * 200.0 * U,
                z = t.z + (random() * 2.0 - 1.0) * 200.0 * U, heading = random() * 2.0 * pi, pitch = 0.0,
                phase = 0, t = 0, f = random() * 30.0 }
        end
    end
end

local function update_tank_fish(dt, k)
    local data = actor("blue_fish")
    for _, f in ipairs(st.tank_fish) do
        f.t = f.t + k
        if f.phase == 0 or f.phase == 2 then
            if f.t < k + 0.01 and f.phase == 0 then
                f.turn = (random() < 0.5 and -1.0 or 1.0) * 0x800
                f.vel = random() * 2.0 + 3.0
                f.len = math.floor(random() * 30.0 / 2.0) * 2.0 + 60.0
                f.pv = (random() * 5.0 < 2.0) and ((random() * 2.0 - 1.0) * 128.0) or 0.0
            end
            local dir = (f.phase == 0) and 1.0 or -1.0
            f.pitch = f.pitch + dir * ((f.t < f.len / 2.0) and f.pv or -f.pv) * k
            if f.t >= f.len then f.phase, f.t = f.phase + 1, 0 end
        else
            f.heading = f.heading + rad((f.turn or 0x800) * A) * k
            if f.t >= 15 then f.phase, f.t = (f.phase + 1) % 4, 0 end
        end
        local v = (f.vel or 3.0) * U * FPS * dt
        local p = rad(f.pitch * A)
        -- (kept within 220 of where the group spawned them - the tanks are not much bigger, and Mario 64's own fish
        -- pass through nothing: one drifting further is turned for home and held at the edge)
        local h = f.home
        local nx, ny = f.x + cos(f.heading) * cos(p) * v, f.y + sin(f.heading) * cos(p) * v
        local dx, dy = nx - h.x, ny - h.y
        local lim = 220.0 * U
        if dx * dx + dy * dy > lim * lim then
            f.heading = atan(h.y - f.y, h.x - f.x)
            local d = sqrt(dx * dx + dy * dy)
            nx, ny = h.x + dx / d * lim, h.y + dy / d * lim
        end
        f.x, f.y = nx, ny
        f.z = max(h.z - 200.0 * U, min(h.z + 200.0 * U, f.z - sin(p) * v))
        lib.set_pose(f.inst, f.x + OFFSET.X, f.y + OFFSET.Y, f.z + OFFSET.Z, deg(f.heading) + 180.0)
        f.f = f.f + k * ((f.phase % 2 == 1) and 2.0 or 1.0)
        if data and data.anims[1] then lib.pose(f.inst, data.anims[1], f.f) end
    end
end

-- ------------------------------------------------------------ every tick
-- (px, py, pz): the athlete's feet, scene space
function M.update(dt, px, py, pz)
    if not st then return end
    local k = dt * FPS
    st.t = st.t + dt
    local data = actor("castle_flag")
    for _, fl in ipairs(st.flags) do
        fl.f = fl.f + k
        if data and data.anims[1] then lib.pose(fl.inst, data.anims[1], fl.f) end
    end
    for i = #st.flocks, 1, -1 do
        local fl = st.flocks[i]
        if (px - fl.x) ^ 2 + (py - fl.y) ^ 2 + (pz - fl.z) ^ 2 < (2000.0 * U) ^ 2 then
            table.remove(st.flocks, i)
            flock_up(fl)
        end
    end
    if #st.birds > 0 then update_birds(dt, k) end
    for _, sc in ipairs(st.schools) do
        if not sc.out and (px - sc.x) ^ 2 + (py - sc.y) ^ 2 + (pz - sc.z) ^ 2 < (1500.0 * U) ^ 2 then
            sc.out = true
            school_out(sc)
        end
    end
    if #st.fish > 0 then update_fish(dt, k, px, py, pz) end
    for _, t in ipairs(st.tanks) do
        if not t.out and (px - t.x) ^ 2 + (py - t.y) ^ 2 + (pz - t.z) ^ 2 < (2500.0 * U) ^ 2 then
            t.out = true
            tank_out(t)
        end
    end
    if #st.tank_fish > 0 then update_tank_fish(dt, k) end
    for _, m in ipairs(st.mist) do
        local wl = (env.water_at and env.water_at(m.x, m.y)) or m.z
        pcall(function()
            m.actor:K2_TeleportTo(wloc(m.x + (random() * 2.0 - 1.0) * 150.0 * U, m.y + (random() * 2.0 - 1.0) * 150.0 * U, wl + 20.0 * U),
                { Pitch = 90.0, Yaw = 0.0, Roll = 0.0 })
        end)
    end
    if st.yoshi and st.yoshi.inst then
        local y = st.yoshi
        local yd = actor("yoshi")
        y.f = y.f + k
        if y.leaving then
            -- (yoshi_walk_jump_off_roof_loop, _finish_jumping_and_despawn: up and off the roof's edge, and gone)
            y.lt = y.lt + k
            local a = math.rad(y.yaw)
            local s = math.min(y.lt, 60.0)
            local wx, wy = y.x + math.cos(a) * 12.0 * s, y.y + math.sin(a) * 12.0 * s
            local wz = y.z + (40.0 * s - 1.5 * s * s) * U
            pcall(lib.set_pose, y.inst, wloc(wx, wy, wz).X, wloc(wx, wy, wz).Y, wloc(wx, wy, wz).Z, y.yaw)
            if y.lt > 60.0 then hide(y.inst, true); st.yoshi = nil end
        end
        if st.yoshi and yd and yd.anims[1] then lib.pose(y.inst, yd.anims[1], y.f) end
    end
    -- the 1-up at the top of the tree: there for whoever gets up to it
    if st.pole and (px - st.pole.x) ^ 2 + (py - st.pole.y) ^ 2 < (150.0) ^ 2 and pz > st.pole.z - 120.0 then
        if env.add_pickup then pcall(env.add_pickup, { kind = "oneup", pos = { st.pole.x, st.pole.y, st.pole.z + 60.0 } }) end
        log("the hidden 1-up at the top of the tree")
        st.pole = nil
    end
    -- the 1-up that comes out once both its markers have been passed
    if st.hidden and #st.triggers > 0 then
        for i = #st.triggers, 1, -1 do
            local t = st.triggers[i]
            if (px - t.x) ^ 2 + (py - t.y) ^ 2 + (pz - t.z) ^ 2 < (100.0 * U + 60.0) ^ 2 then table.remove(st.triggers, i) end
        end
        if #st.triggers == 0 then
            if env.add_pickup then pcall(env.add_pickup, { kind = "oneup", pos = st.hidden }) end
            log("the hidden 1-up came out")
            st.hidden = nil
        end
    end
    -- the waterfall: louder the nearer he is
    if st.waterfall and env.waterfall then
        local w = st.waterfall
        local d = sqrt((px - w[1]) ^ 2 + (py - w[2]) ^ 2 + (pz - w[3]) ^ 2)
        env.waterfall(max(0.0, min(1.0, 1.0 - (d - 600.0) / 3400.0)))
    end
end

-- The map went: forget everything without touching it.
function M.forget() st = nil end

-- Yoshi, if he is on the roof (at 120 stars): his place, for talking to him; M.yoshi_leave() sends him off it
function M.yoshi()
    local y = st and st.yoshi
    if y and not y.leaving then return y end
    return nil
end
function M.yoshi_leave()
    local y = st and st.yoshi
    if y then y.leaving, y.lt = true, 0.0 end
end

function M.state() return st end        -- (tests)

return M
