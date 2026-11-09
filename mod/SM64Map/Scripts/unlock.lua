-- SM64Map: a door unlocked the first time it is opened (mario_actions_cutscene.c act_unlocking_star_door,
-- act_unlocking_key_door). "we need a animation for unlocking new doors as well as keydoors then the dialog should run as
-- well", 2026-10-20.
--
-- A star door (the 1, 3, 8, 30 and 50 ones): he is held facing it, arms up (STORROR's Celebrate emote stopped with
-- them raised, for Mario's MARIO_ANIM_SUMMON_STAR), and a star comes up over his head (bhvUnlockDoorStar: 160 up and 30
-- to his side, rising 3.4 a frame for 30 frames and growing from half size, turning ever faster - a short chime at each
-- turn - then 30 frames turning where it is; then the star sound, and it is gone in sparkles). Then the door is his
-- (its save flag) and DIALOG_038 says so.
-- A key door: he is held before the middle of the pair, facing it, and Bowser's key comes out and goes into the lock
-- (bowser_key_cutscene_geo, its unlock_door animation - 140 frames, the key grown in from frame 38 to 58: the insert
-- at frame 79 and the turn at 111); then the door is his and swings open.
-- All at Mario 64's 30 frames a second. game.lua's doors call M.star / M.key; M.tick every frame while M.active.
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET

local M = { active = false }

local S = 0.75
local LOCK = "SM64Unlock"
local CELEBRATE = "/SPP/SPPCharacter/Animation/Emote/Emote/MontageEmote_1122_LisaS_Locomotion_061024_RandomEmotes-001.MontageEmote_1122_LisaS_Locomotion_061024_RandomEmotes-001"
local ARMS_UP_AT = 0.45                 -- s into the emote: both arms up (shock.lua holds it there too)
local st = nil

local function sfx(name, v) local SF = package.loaded["sfx"]; if SF then pcall(SF.play, name, v) end end

-- his controls held, as dialog.lua holds them (STORROR's parkour, walking and running, and the move input)
local function lock(on)
    local pc, pawn = lib.controller(), lib.pawn()
    if not (pc and pawn) then return end
    pcall(function() pc:SetIgnoreMoveInput(on) end)
    pcall(function() if on then pawn:DisableInput(pc) else pawn:EnableInput(pc) end end)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            local cname = o:GetClass():GetFName():ToString()
            if cname == "ParkourComponent" then
                o:ClearInputQueue()
                o:EnableAllParkourInputs(FName(LOCK), not on)
            elseif cname == "LocomotionComponent" then
                o:EnableLocomotionInputCallback(FName(LOCK), not on)
                o:EnableAdvancedLocomotionInput(FName(LOCK), not on)
            end
        end
    end)
    if on then
        pcall(function() pawn.CharacterMovement:StopMovementImmediately() end)
        local G = package.loaded["game"]
        if G and G.reset_athlete then pcall(G.reset_athlete, pawn, "held to unlock a door") end
    end
end

-- him put at (x, y) - scene cm, his feet's height kept - facing yaw (degrees, STORROR's)
local function place(x, y, yaw)
    pcall(function()
        local pawn = lib.pawn()
        local l = pawn:K2_GetActorLocation()
        local nx, ny = l.X, l.Y
        if x then nx, ny = x + OFFSET.X, y + OFFSET.Y end
        pawn:K2_TeleportTo({ X = nx, Y = ny, Z = l.Z }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 })
        pawn.CharacterMovement:StopMovementImmediately()
        lib.controller():SetControlRotation({ Pitch = -10.0, Yaw = yaw, Roll = 0.0 })
    end)
end

-- the scene's own camera (Mario 64's door cutscenes: from beside him): put at `at` (scene cm) looking at `look`
local function view(s, at, look, nocut)
    pcall(function()
        local world = lib.world()
        local cam = s.cam or lib.camera(world, "unlock")
        if not cam then return end
        -- (short of any wall between it and what it looks at - `nocut`: not, a place known clear)
        local G = package.loaded["game"]
        if G and G.wall_cut and not nocut then
            local cut = G.wall_cut(look[1], look[2], look[3], at[1], at[2], at[3])
            if cut < 1.0 then
                local k = math.max(0.2, cut - 0.08)
                at = { look[1] + (at[1] - look[1]) * k, look[2] + (at[2] - look[2]) * k, look[3] + (at[3] - look[3]) * k }
            end
        end
        local dx, dy, dz = look[1] - at[1], look[2] - at[2], look[3] - at[3]
        local rot = { Pitch = math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy))), Yaw = math.deg(math.atan(dy, dx)), Roll = 0.0 }
        cam:K2_SetActorLocationAndRotation({ X = at[1] + OFFSET.X, Y = at[2] + OFFSET.Y, Z = at[3] + OFFSET.Z }, rot, false, {}, true)
        if not s.cam then
            s.cam = cam
            lib.controller():SetViewTargetWithBlend(cam, 0.6, 4, 2.0, false)
        end
    end)
end

local function finish(s, ok)
    if st ~= s then return end
    st, M.active = nil, false
    if s.mont and s.ai then pcall(function() s.ai:Montage_Stop(0.3, s.mont) end) end
    if s.star then pcall(function() lib.destroy(s.star.actor) end) end
    for _, k in ipairs(s.keys or { s.key }) do pcall(function() lib.destroy(k.actor) end) end
    if s.cam then pcall(function() lib.controller():SetViewTargetWithBlend(lib.pawn(), 0.6, 4, 2.0, false) end) end
    lock(false)
    local G = package.loaded["game"]
    if G then G.unlocking = nil end
    if ok and s.done then pcall(s.done) end
end

-- door: { x, y, z = the middle of its doorway (scene cm), face = the yaw (degrees) he looks at it with }. done(): once
-- it is unlocked (after DIALOG_038).
function M.star(door, done)
    if st then return false end
    local world, pawn = lib.world(), lib.pawn()
    if not (world and pawn) then return false end
    st = { kind = "star", t = 0.0, f = 0, door = door, done = done, world = world:GetAddress() }
    M.active = true
    local G = package.loaded["game"]
    if G then G.unlocking = true end
    lock(true)
    place(nil, nil, door.face)
    -- (arms up: the Celebrate emote, held raised)
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        local m = lib.try_load(CELEBRATE)
        if ai and m then
            st.ai, st.mont = ai, m
            ai:Montage_Play(m, 1.0, 0, 0.0, true)
        end
    end)
    pcall(function()
        local l = pawn:K2_GetActorLocation()
        local a = math.rad(door.face)
        local px, py, pz = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z
        local fx, fy, rx, ry = math.cos(a), math.sin(a), -math.sin(a), math.cos(a)
        -- (on his side of the door, behind him and to one side, looking up past him at the star and the door: in
        -- front of him it was through the door - "when unlocking the 3 star door the camera ends up on the wrong side
        -- of the door", 2026-10-20)
        view(st, { px - fx * 230.0 + rx * 170.0, py - fy * 230.0 + ry * 170.0, pz + 70.0 }, { px + fx * 50.0, py + fy * 50.0, pz + 120.0 })
    end)
    log("unlock: a star door, with a star")
    return true
end

function M.key(door, done)
    if st then return false end
    local world, pawn = lib.world(), lib.pawn()
    if not (world and pawn) then return false end
    st = { kind = "key", t = 0.0, f = 0, door = door, done = done, world = world:GetAddress() }
    M.active = true
    local G = package.loaded["game"]
    if G then G.unlocking = true end
    lock(true)
    -- (he stands before the middle of the pair, 85 cm out, facing it: the key's bow just before him. `door.scale`: the
    -- key smaller, its measures with it - the Bowser gate's padlocks, game.lua G.gate_tick)
    local a = math.rad(door.face)
    local ks = door.scale or 1.0
    place(door.x - math.cos(a) * 85.0, door.y - math.sin(a) * 85.0, door.face)
    local data = lib.load_data("data.actor_geo_bowser_key_cutscene_geo")
    if data then
        -- (placed by where its animation leaves it, measured: at its end the key's tip is 22 cm back and 13 to the side
        -- of the model's place, 145 up, and the key runs out from it 26 degrees round from the model's back. So it is
        -- turned that much less, to stand straight out of the door, and put with its tip 15 cm into the lock at the
        -- middle of the pair. Put by the animation's own start it ended 60 cm inside the door and askew: "the unlocking a
        -- locked door with a key animation is wrong", 2026-10-20)
        local KEY_TIP_X, KEY_TIP_Y, KEY_TURN = -22.1 * ks, -12.8 * ks, 26.3
        local yk = door.face + 180.0 - KEY_TURN
        local r = math.rad(yk)
        -- (`door.holes`: a key into each of these at once, { x, y, z } as the door's own - the Bowser gate's padlocks,
        -- every key not used yet turned together: "if the player has a 3 keys at the same time and havent opened a
        -- single lock make all 3 open at the same time", "so it should be 3 keys going into all the locks",
        -- 2026-11-06. The door's x, y, z then their middle, where he stands before and the camera looks.)
        -- (`door.rainbow`: the keys rainbow - textures/rainbow_star.png, its colours running over them in M.tick - as
        -- the race's key: the Bowser gate's, game.lua G.gate_tick)
        local mid = door.rainbow and lib.get_mid(world, "opaque", "rainbow_star", 0.94) or nil
        st.keys = {}
        for _, sp in ipairs(door.holes or { door }) do
            local tx, ty = sp.x + math.cos(a) * 15.0 * ks, sp.y + math.sin(a) * 15.0 * ks
            local ox = tx - (math.cos(r) * KEY_TIP_X - math.sin(r) * KEY_TIP_Y)
            local oy = ty - (math.sin(r) * KEY_TIP_X + math.cos(r) * KEY_TIP_Y)
            local inst = lib.make_instance(world, data, { X = ox + OFFSET.X, Y = oy + OFFSET.Y, Z = sp.z + OFFSET.Z }, yk, ks)
            if inst then
                st.keys[#st.keys + 1] = inst
                if mid then
                    for i, part in ipairs((inst.data or data).parts or {}) do
                        local comp = inst.comps and inst.comps[i]
                        for _, sec in ipairs(part.sections or {}) do
                            if comp then pcall(function() comp:SetMaterial(sec.id, mid) end) end
                        end
                    end
                    st.key_mid, st.key_rb = mid, 0.0
                end
            end
        end
        st.key = st.keys[1]
        -- (left where it is: its animation moves it - lib.pose puts its parts each time)
    end
    -- (`door.cam`: { from, look } its own camera - the Bowser gate's, back in the hall: the usual one, to the side, was
    -- drawn in to 40 cm from the padlock by the recess it stands in, the keys coming in from behind it - "the keys not
    -- going in the lock", 2026-11-07)
    if door.cam then
        view(st, door.cam.from, door.cam.look, door.cam.nocut)
    else
        local fx, fy, rx, ry = math.cos(a), math.sin(a), -math.sin(a), math.cos(a)
        local lx, ly, lz = door.x - fx * 35.0 * ks, door.y - fy * 35.0 * ks, door.z + 120.0 * ks
        local cs = math.max(ks, 0.7) * (door.view or 1.0)        -- (`door.view`: further back, for several keys)
        view(st, { lx - fx * 150.0 * cs + rx * 230.0 * cs, ly - fy * 150.0 * cs + ry * 230.0 * cs, lz + 30.0 * cs }, { lx, ly, lz })
    end
    sfx("bowser_key")
    log("unlock: a key door, with Bowser's key")
    return true
end

-- one Mario 64 frame of the star (bhv_unlock_door_star_loop)
local function star_frame(s)
    local u = s.star_u
    if not u then return end
    local prev = u.yaw
    u.prev_ang = u.ang
    if u.vel < 0x2400 then u.vel = u.vel + 0x60 end
    if u.state < 2 then u.ang = u.ang + u.vel end
    if u.state == 0 then
        u.z = u.z + 3.4 * S
        u.yaw = (u.yaw + u.vel) % 65536
        u.scale = u.t / 50.0 + 0.5
        u.t = u.t + 1
        if u.t == 30 then u.t, u.state = 0, 1 end
    elseif u.state == 1 then
        u.yaw = (u.yaw + u.vel) % 65536
        u.t = u.t + 1
        if u.t == 30 then
            sfx("star_sound")
            pcall(function() s.star.actor:SetActorHiddenInGame(true) end)
            local EF = package.loaded["envfx"]
            if EF and EF.poof then pcall(EF.poof, u.x, u.y, u.z, 0.6) end
            u.t, u.state = 0, 2
        end
    elseif u.state == 2 then
        u.t = u.t + 1
        if u.t == 20 then u.state = 3 end
    end
    if u.state < 2 and u.yaw < prev then sfx("star_short", 0.8) end          -- (round once more)
end

function M.tick(dt)
    local s = st
    if not s then M.active = false; return end
    local w = lib.world()
    if not (w and w:GetAddress() == s.world) then st, M.active = nil, false; return end
    local HP = _G.HEALTH
    if HP then HP.grace = math.max(HP.grace or 0.0, 0.3) end              -- (nothing hurts him meanwhile)
    s.t = s.t + math.min(dt, 0.1)
    local frames = math.floor(s.t * 30.0)
    local pawn = lib.pawn()
    if s.kind == "star" then
        -- (arms held up once they are)
        if s.mont and not s.held and s.t >= ARMS_UP_AT then
            s.held = true
            pcall(function() s.ai:Montage_SetPlayRate(s.mont, 0.0) end)
        elseif s.mont and s.held then
            -- (STORROR lets the pose go of itself: put back, held)
            pcall(function()
                if not s.ai:Montage_IsPlaying(s.mont) then
                    s.ai:Montage_Play(s.mont, 1.0, 0, ARMS_UP_AT, true)
                    s.ai:Montage_SetPlayRate(s.mont, 0.0)
                end
            end)
        end
        while s.f < frames do
            s.f = s.f + 1
            if s.f == 15 and not s.star_u then
                -- the star, over his head and to his side
                local G = package.loaded["game"]
                local data = lib.load_data("data.actor_star")
                local l = pawn and pawn:K2_GetActorLocation()
                if data and l then
                    local feet = l.Z - OFFSET.Z - ((G and G.half) or 90.0)
                    local a = math.rad(s.door.face + 90.0)
                    local u = { state = 0, t = 0, vel = 0x1000, yaw = 0x7800, ang = 0x7800, prev_ang = 0x7800, scale = 0.5,
                                x = l.X - OFFSET.X + math.cos(a) * 30.0 * S, y = l.Y - OFFSET.Y + math.sin(a) * 30.0 * S,
                                z = feet + 160.0 * S }
                    s.star_u = u
                    s.star = lib.make_instance(lib.world(), data, { X = u.x + OFFSET.X, Y = u.y + OFFSET.Y, Z = u.z + OFFSET.Z }, 0.0, 0.5)
                    if s.star then s.star.moves = true end
                    sfx("star_appears")
                end
            end
            star_frame(s)
            -- (Mario 64: 70 frames after the star came, he turns back to the door; then the door is his)
            if s.f == 15 + 72 and s.mont and s.ai then pcall(function() s.ai:Montage_Stop(0.35, s.mont) end); s.mont = nil end
            if s.f >= 15 + 90 then
                local done = s.done
                s.done = nil
                finish(s, false)
                local G = package.loaded["game"]
                if done then pcall(done) end
                if G and G.say then pcall(G.say, 38) end
                log("unlock: the star door opened to him (DIALOG_038)")
                return
            end
        end
        local u = s.star_u
        if u and s.star and u.state < 2 then
            -- (turned smoothly between Mario 64's frames: jumped round 50 degrees at a time, the game's motion blur
            -- smeared it into a white blur)
            local frac = math.max(0.0, math.min(1.0, s.t * 30.0 - s.f))      -- (a frame behind: from the last turn to this)
            local ang = u.prev_ang + (u.ang - u.prev_ang) * frac
            pcall(function()
                s.star.actor:K2_TeleportTo({ X = u.x + OFFSET.X, Y = u.y + OFFSET.Y, Z = u.z + OFFSET.Z },
                    { Pitch = 0.0, Yaw = -ang * 360.0 / 65536.0, Roll = 0.0 })
                local k = u.scale
                s.star.actor:SetActorScale3D({ X = k, Y = k, Z = k })
            end)
        end
    else
        -- the key (bhv_bowser_key_unlock_door_loop): its animation, grown in, the two sounds
        local key = s.key
        if key then
            local f = math.min(frames, 139)
            local anim = key.data.anims and key.data.anims[1]
            for _, kk in ipairs(s.keys or { key }) do
                if anim then pcall(lib.pose, kk, anim, s.t * 30.0 < 139 and s.t * 30.0 or 139) end
            end
            if s.key_mid then
                s.key_rb = s.key_rb + math.min(dt, 0.1)
                local off = { R = (s.key_rb * 0.12) % 40.0, G = (s.key_rb * 0.05) % 40.0, B = 1.0, A = 1.0 }
                pcall(function() s.key_mid:SetVectorParameterValue(FName("BaseColorTexture_OffsetScale"), off) end)
            end
            local k
            if f < 38 then k = 0.0 elseif f < 49 then k = 0.2 elseif f < 58 then k = (f - 53) * 0.11875 + 0.2
            elseif f < 59 then k = 1.1 elseif f < 60 then k = 1.05 else k = 1.0 end
            k = math.max(k, 0.001)
            if k ~= s.ks then
                s.ks = k
                for _, kk in ipairs(s.keys or { key }) do
                    local c = kk.comps[#kk.comps]
                    if c then pcall(function() c:SetRelativeScale3D({ X = k, Y = k, Z = k }) end) end
                end
            end
        end
        while s.f < frames do
            s.f = s.f + 1
            if s.f == 79 then sfx("door_insert_key") end
            if s.f == 111 then sfx("door_turn_key") end
            -- (`door.turned`: called this frame once the key has turned - the Bowser gate's padlock off, its chain
            -- dropping; `key_goes`, the key gone with it; `hold`, frames more before he is let go)
            if s.door.turned and s.f >= (s.door.turned_at or 116) then
                local fn = s.door.turned
                s.door.turned = nil
                if s.door.key_goes and s.key then
                    for _, kk in ipairs(s.keys or { s.key }) do pcall(function() lib.destroy(kk.actor) end) end
                    s.key, s.keys, s.key_mid = nil, nil, nil
                end
                pcall(fn)
            end
            if s.f >= 150 + (s.door.hold or 0) then
                finish(s, true)
                log("unlock: the key door is open")
                return
            end
        end
    end
end

function M.forget() if st then finish(st, false) end end

return M
