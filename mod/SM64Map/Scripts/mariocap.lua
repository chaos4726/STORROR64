-- SM64Map: Mario's own cap, and losing it (Mario 64: MARIO_CAP_ON_HEAD and the save file's SAVE_FLAG_CAP_ON_*).
--
-- As the game has it (interaction.c mario_lose_cap_to_enemy / mario_blow_off_cap / mario_retrieve_cap, cap.inc.c
-- bhvNormalCap, klepto.inc.c, mr_blizzard.inc.c, save_file.c):
--   - Shifting Sand Land's Klepto (acts 2 to 6) dives at him and snatches it, and flies about with it; hit him and he
--     lets it fall.
--   - the Snowman's Land snowman's breath, and Tall Tall Mountain's Fwoosh, blow it off him after he has been in the
--     wind for 20 frames: it flies off and lands somewhere about.
--   - lying about, it is his again for the touching. (Mario 64's, left lying when he goes, is taken by the course's thief,
--     normal_cap_set_save_flags. Here it stays where it lies - he goes, dies, comes back, and it is there: "the hat should
--     stay where it fell off at even if the player dies and has to come back to get it", 2026-10-27. And where it comes
--     to rest out of his reach - off the level, over a pit, in lava, behind a wall from where it left him - it is put
--     back where it left him, or where he last stood on solid ground: "we need a hat failsafe".)
--   - without it his hurts are half as bad again (take_damage_from_interact_object: damage += (damage + 1) / 2).
-- Kept with the file as flags ("cap_on_klepto", "cap_on_blizzard", "cap_on_ukiki"); a cap lying about is only while he
-- is in that scene (its thief's flag is set the moment it falls, and cleared when he picks it up).
-- (The "adding upgrading and improving" session, 2026-10-18.)
local lib = require("lib")
local log = lib.log

local M = {}

local OFFSET = lib.OFFSET
local U = 0.75
local FLAGS = { klepto = "cap_on_klepto", blizzard = "cap_on_blizzard", ukiki = "cap_on_ukiki" }
local THIEF = { ssl = "klepto", ssl_2 = "klepto", ssl_3 = "klepto", sl = "blizzard", sl_2 = "blizzard",
                ttm = "ukiki", ttm_2 = "ukiki", ttm_3 = "ukiki", ttm_4 = "ukiki" }
local GRAVITY = 0.7 * U * 900.0     -- cm/s/s (bhv_normal_cap_init: 0.7 a frame)
local FRICTION = 0.89               -- of its speed kept each frame on the ground
local REACH = 95.0                  -- cm: his round and the cap's (Mario's 37 and its 80 units, for a bigger figure)
local SCALE = 1.3                   -- the cap object, sized for the athlete

local ground = nil                  -- the cap lying about: { scene, x, y, z, vx, vy, vz, yaw, inst, rest }
local stash = nil                   -- the cap lying in a scene he has left: { scene, x, y, z, yaw }
local safe = nil                    -- where he last stood on solid ground: { scene, x, y, z } (scene cm, his feet)
local safe_t = 0.0
local shown = nil                   -- the look's cap pieces as last set (true/false), nil: never set
local reassert = 0.0

local function menu() return _G.MENU end
local function sfx(name, v)
    local S = package.loaded["sfx"]
    if S and S.play then pcall(S.play, name, v or 1.0) end
end

-- who has it: nil (on his head), "ground", or a thief's name
function M.where()
    if ground or stash then return "ground" end
    local MN = menu()
    if not (MN and MN.has_flag) then return nil end
    for who, f in pairs(FLAGS) do
        if MN.has_flag(f) then return who end
    end
    return nil
end
function M.on_head() return M.where() == nil end
function M.held_by(who)
    local MN = menu()
    return MN and MN.has_flag and MN.has_flag(FLAGS[who]) or false
end

-- a special cap from a box (wing, metal, vanish) on him: only his own red cap can be taken or blown off
-- (does_mario_have_normal_cap_on_head)
local function special_on()
    local C = package.loaded["caps"]
    return C and C.on and C.on() and true or false
end

-- nothing takes it from him in a cannon, a cutscene or while he is going down (no interaction reaches Mario then)
local function untouchable()
    local G = package.loaded["game"]
    local HP = _G.HEALTH
    if HP and HP.dead_t then return true end
    if G and (G.cutscene or G.dying or G.pending or G.warping) then return true end
    if G and G.intangible then
        local ok, v = pcall(G.intangible)
        if ok and v then return true end
    end
    return false
end

-- a special cap from a box is a cap on his head too
local function wearing_any()
    if M.on_head() then return true end
    local C = package.loaded["caps"]
    return C and C.on and C.on() and true or false
end

-- his hurt by `wedges`, as it counts with or without his cap
function M.damage(wedges)
    if wearing_any() or not wedges or wedges <= 0 then return wedges end
    return wedges + (wedges + 1) // 2
end

local function set_flag(who)
    local MN = menu()
    if MN and MN.add_flag and FLAGS[who] then MN.add_flag(FLAGS[who]) end
end
local function clear_flags()
    local MN = menu()
    if not (MN and MN.remove_flag) then return end
    for _, f in pairs(FLAGS) do pcall(MN.remove_flag, f) end
end

-- the look's cap pieces shown or hidden to match
local function sync_look(force)
    local L = package.loaded["mariolook"]
    if not (L and L.on and L.on() and L.show_cap) then shown = nil; return end
    local want = wearing_any()
    if force or want ~= shown then
        shown = want
        pcall(L.show_cap, want)
    end
end

-- taken by a thief (Klepto, Ukiki): false when he had none to take
function M.lose_to(who)
    if not M.on_head() or not FLAGS[who] or special_on() or untouchable() then return false end
    set_flag(who)
    log("Mario's cap taken by %s", who)
    sync_look(true)
    return true
end

local function remove_ground()
    local g = ground
    ground = nil
    if g and g.inst then
        pcall(function() lib.keep[g.inst.actor:GetAddress()] = nil end)
        pcall(lib.retire, g.inst.actor)
    end
end

local function cap_inst(x, y, z, yaw)
    local G = package.loaded["game"]
    local world = lib.world()
    local data = G and G.actor_data and G.actor_data("cap_red")
    local inst = (world and data) and lib.make_instance(world, data, { X = x + OFFSET.X, Y = y + OFFSET.Y, Z = z + OFFSET.Z }, yaw or 0.0, SCALE) or nil
    if inst then pcall(function() lib.keep[inst.actor:GetAddress()] = "mario's cap" end) end
    return inst
end

-- a cap object put down at (x, y, z) (scene cm), going `fwd` cm/s along `yaw` (degrees) and `vz` up: Klepto's let go,
-- Mr. Blizzard's dropped, or blown off his head. No thief's flag: it is the ground's, wherever he goes.
function M.drop(x, y, z, yaw, fwd, vz)
    remove_ground()
    stash = nil
    local G = package.loaded["game"]
    clear_flags()
    local inst = cap_inst(x, y, z, yaw)
    local a = math.rad(yaw or 0.0)
    ground = { scene = G and G.name, x = x, y = y, z = z, vx = math.cos(a) * (fwd or 0.0), vy = math.sin(a) * (fwd or 0.0),
               vz = vz or 0.0, yaw = yaw or 0.0, inst = inst, rest = false, t = 0.0 }
    -- (and where it left him, for the failsafe: his feet, if he stood there)
    pcall(function()
        local pawn = lib.pawn()
        local l = pawn:K2_GetActorLocation()
        local half = G and G.half or 90.0
        local fx, fy, fz = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - half
        local f = G and G.floor_z and G.floor_z(fx, fy, fz + 60.0)
        if f and fz - f < 150.0 then ground.ox, ground.oy, ground.oz = fx, fy, f end
    end)
    log("Mario's cap falls at (%.0f, %.0f, %.0f)", x, y, z)
    sync_look(true)
    return true
end

-- the cap at rest out of his reach, or why not: over a pit (death or updraft floor, nothing under it), in lava, or with
-- a wall between it and where it left him
local function out_of_reach(G, g)
    if G.over_pit then
        local ok, v = pcall(G.over_pit, g.x, g.y, g.z + 20.0)
        if ok and v then return "over a pit" end
    end
    if G.lava_z then
        local ok, lz = pcall(G.lava_z, g.x, g.y, g.z + 20.0)
        if ok and lz and lz >= g.z - 10.0 then return "in lava" end
    end
    if G.wall_cut and g.ox then
        local ok, cut = pcall(G.wall_cut, g.ox, g.oy, g.oz + 60.0, g.x, g.y, g.z + 60.0)
        if ok and cut and cut < 1.0 then return "behind a wall" end
    end
    return nil
end

-- the failsafe: put down where it left him, if he stood on something then (or where he last stood on solid ground in
-- this scene). Where he last stood came first: that was where he stood now, so it went straight back on his head
-- unseen - and the Ukiki there snatched it a second later, a cap he never knew he had: "monkeys still able to grab
-- hat even though the player has no hat to grab", 2026-10-27
local function to_safety(g, why)
    local x, y, z = nil, nil, nil
    if g.ox then x, y, z = g.ox, g.oy, g.oz
    elseif safe and safe.scene == g.scene then x, y, z = safe.x, safe.y, safe.z end
    if not x then return false end
    g.x, g.y, g.z, g.vx, g.vy, g.vz, g.rest = x, y, z + 5.0, 0.0, 0.0, 0.0, true
    g.t = 0.0                        -- (put down anew: lying there a moment before it is his, as when it first fell)
    g.ox = nil                       -- (where he stood is in reach: not tried again)
    if g.inst then lib.set_pose(g.inst, g.x + OFFSET.X, g.y + OFFSET.Y, g.z + OFFSET.Z, g.yaw) end
    log("Mario's cap %s: put back where it left him, (%.0f, %.0f, %.0f)", why, x, y, z)
    return true
end

-- blown off his head by the wind (mario_blow_off_cap: 180 up on him, 50 a frame on, a little to his left)
function M.blow_off(pawn, away_yaw)
    if not M.on_head() or not pawn or special_on() or untouchable() then return false end
    local l = pawn:K2_GetActorLocation()
    local G = package.loaded["game"]
    local top = l.Z - OFFSET.Z + (G and G.half or 90.0)
    M.drop(l.X - OFFSET.X, l.Y - OFFSET.Y, top, (away_yaw or 0.0) + 5.6, 50.0 * U * 30.0 * 0.6, 300.0)
    -- (and not his again for a while: Mario 64's Mario is blown back off his feet, act_getting_blown, and interact_cap
    -- refuses it until he is up - here he is only pushed, and caught it in the air as it went: 1.5 s, not 0.66)
    if ground then ground.t = -0.9 end
    sfx("mario_whoa", 0.8)
    log("Mario's cap blown off")
    return true
end

-- his again
function M.retrieve()
    remove_ground()
    stash = nil
    clear_flags()
    sfx("star_sound", 0.9)
    sfx("mario_here_we_go", 1.0)
    log("Mario's cap back on")
    sync_look(true)
end

-- a scene change: a cap left lying stays where it lies - put back there when he is in that scene again
function M.left_scene()
    if ground then
        stash = { scene = ground.scene, x = ground.x, y = ground.y, z = ground.z, yaw = ground.yaw }
        log("Mario's cap left lying in %s at (%.0f, %.0f, %.0f): there when he comes back", tostring(ground.scene),
            ground.x, ground.y, ground.z)
        remove_ground()
    end
end

function M.tick(dt, pawn)
    local G = package.loaded["game"]
    if not (G and pawn) then return end
    -- (paused - Mario 64's pause screen or STORROR's menu: a cap lying or falling stands still with the rest - its update
    -- is ahead of game.lua's pause: "when pausing make sure the game pauses everything", 2026-10-27)
    local PA = package.loaded["pause"]
    if PA and (PA.open or (PA.menu_up and PA.menu_up())) and not (PA.online and PA.online()) then return end
    reassert = reassert - dt
    if reassert <= 0.0 then
        reassert = 0.5
        -- (the look is built again now and then - a face change, the metal cap's paint: its pieces put right)
        sync_look(not wearing_any())
    else
        sync_look(false)
    end
    -- (where he stands on solid ground, now and then: the failsafe's place)
    safe_t = safe_t - dt
    if safe_t <= 0.0 and G.name and not (G.pending or G.warping or G.dying or G.swim) then
        safe_t = 0.25
        pcall(function()
            if pawn.CharacterMovement.MovementMode ~= 1 then return end
            local l = pawn:K2_GetActorLocation()
            local half = G.half or 90.0
            local x, y, z = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - half
            local f = G.floor_z and G.floor_z(x, y, z + 40.0)
            if not f or z - f > 30.0 then return end
            if G.over_pit and G.over_pit(x, y, z + 20.0) then return end
            safe = { scene = G.name, x = x, y = y, z = f }
        end)
    end
    -- (back in the scene where it was left lying: there it is)
    if not ground and stash and stash.scene == G.name and not (G.pending or G.warping) then
        local s0 = stash
        stash = nil
        ground = { scene = s0.scene, x = s0.x, y = s0.y, z = s0.z, vx = 0.0, vy = 0.0, vz = 0.0, yaw = s0.yaw or 0.0,
                   inst = cap_inst(s0.x, s0.y, s0.z, s0.yaw), rest = true, t = 1.0 }
        log("Mario's cap where he left it in %s, (%.0f, %.0f, %.0f)", tostring(s0.scene), s0.x, s0.y, s0.z)
    end
    local g = ground
    if not g then return end
    if g.scene ~= G.name then M.left_scene(); return end
    g.t = g.t + dt
    -- (bhv_normal_cap_loop: falling and sliding to rest, spinning while it moves)
    if not g.rest then
        g.vz = g.vz - GRAVITY * dt
        local nx, ny, nz = g.x + g.vx * dt, g.y + g.vy * dt, g.z + g.vz * dt
        -- (walls: where it would go there is no floor at all - out through the level's side - or the floor is well
        -- above it - a wall or a step: it goes no further that way and drops where it is, as object_step's walls stop
        -- it. Blown off in the castle it went through the wall and out of the level, 2026-10-18)
        -- (a wall is one of the level's own walls across its way, G.wall_cut: a floor high over it is no wall. Looked for
        -- from 300 up, the mountain over TTM's path above Fwoosh stopped it dead every time - blown off, it fell at his
        -- feet in the wind, where the cliff hid it from the camera and he walked over it unseen and had it blown straight
        -- back off, 2026-10-27. A floor ahead well above it stops it only where the walls are not known. And at a wall it
        -- goes on along it with what of its way the wall leaves it, as object_step slides it: stopped dead at the rock
        -- where the path turns, 2 m on, it lay where the gust had pushed him and he stood on it again)
        local function way_ok(bx, by)
            local ahead = G.floor_z and G.floor_z(bx, by, g.z + 300.0)
            if not ahead then return false end
            if G.wall_cut then return G.wall_cut(g.x, g.y, g.z + 15.0, bx, by, g.z + 15.0) >= 1.0 end
            return ahead <= g.z + 40.0
        end
        if not way_ok(nx, ny) then
            -- (along the wall, at whatever slant: its way turned the least that clears it, its speed what is left
            -- along that way - TTM's cliff by Fwoosh is slantwise to both axes)
            local sp = math.sqrt(g.vx * g.vx + g.vy * g.vy)
            local a0 = math.atan(g.vy, g.vx)
            local slid = false
            if sp > 1.0 then
                for _, d in ipairs({ 20, -20, 40, -40, 60, -60, 80, -80 }) do
                    local a, s = a0 + math.rad(d), sp * math.cos(math.rad(d))
                    local tx, ty = g.x + math.cos(a) * s * dt, g.y + math.sin(a) * s * dt
                    if way_ok(tx, ty) then
                        nx, ny, g.vx, g.vy, slid = tx, ty, math.cos(a) * s, math.sin(a) * s, true
                        break
                    end
                end
            end
            if not slid then nx, ny, g.vx, g.vy = g.x, g.y, 0.0, 0.0 end
        end
        local fz = G.floor_z and G.floor_z(nx, ny, g.z + 60.0)
        if fz and nz <= fz then
            nz, g.vz = fz, 0.0
            local k = FRICTION ^ (dt * 30.0)
            g.vx, g.vy = g.vx * k, g.vy * k
            if g.vx * g.vx + g.vy * g.vy < 25.0 then g.rest = true end
        end
        -- (in water it floats up to the top and drifts to a stop there: bhv_normal_cap_init's buoyancy)
        for _, r in ipairs(G.water_rects or {}) do
            if nx > r.x0 and nx < r.x1 and ny > r.y0 and ny < r.y1 and nz < r.z and (not fz or r.z > fz) then
                nz, g.vz = r.z, 0.0
                local k = FRICTION ^ (dt * 30.0)
                g.vx, g.vy = g.vx * k, g.vy * k
                if g.vx * g.vx + g.vy * g.vy < 25.0 then g.rest = true end
                fz = r.z
            end
        end
        if not fz and nz < ((G.floor and G.floor.min_z) or -6000.0) - 2000.0 then
            -- (gone off the level: the failsafe; with nowhere known to put it, back on his head)
            if not to_safety(g, "fell out of the level") then
                log("Mario's cap fell out of the level: back on his head")
                M.retrieve()
            end
            return
        end
        g.x, g.y, g.z = nx, ny, nz
        if M.trace then        -- (dev: its way, logged from here on the game thread)
            g.tr = (g.tr or 0.0) + dt
            if g.tr >= 0.2 then
                g.tr = 0.0
                log("cap trace: (%.0f, %.0f, %.0f) going (%.0f, %.0f, %.0f)", g.x, g.y, g.z, g.vx, g.vy, g.vz)
            end
        end
        g.yaw = g.yaw + math.sqrt(g.vx * g.vx + g.vy * g.vy) * dt * 2.0
        if g.inst then lib.set_pose(g.inst, g.x + OFFSET.X, g.y + OFFSET.Y, g.z + OFFSET.Z, g.yaw) end
        -- (come to rest: within his reach, or the failsafe)
        if g.rest then
            local why = out_of_reach(G, g)
            if why then to_safety(g, why)
            else log("Mario's cap comes to rest at (%.0f, %.0f, %.0f)", g.x, g.y, g.z) end
        end
    end
    -- his for the touching (not while it is still on its way out: cap_set_hitbox after 20 frames; and not while the
    -- wind blows him, as interact_cap refuses it in act_getting_blown. Blown along after it, he caught it in the air a
    -- second after every gust took it, and the next gust took it again - by Fwoosh he never saw it lying, 2026-10-27)
    local blown = M.blown_at and os.clock() - M.blown_at < 0.5
    if g.t > 0.66 and not blown then
        local l = pawn:K2_GetActorLocation()
        -- (his body, top to toe, against the cap's height: swimming up to it his feet hang far below)
        local px, py, mid = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z
        local half = G.half or 90.0
        if (px - g.x) ^ 2 + (py - g.y) ^ 2 < REACH * REACH and mid - half < g.z + 60.0 and mid + half > g.z - 30.0 then
            M.retrieve()
        end
    end
end

-- the map went: forget what was on it untouched
function M.forget()
    ground, shown = nil, nil
end

return M
