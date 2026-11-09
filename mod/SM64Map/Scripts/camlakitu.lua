-- The Lakitu Bros.' cameraman on the castle bridge, the first time a new file comes to the castle (camera_lakitu.inc.c,
-- CAMERA_LAKITU_BP_INTRO, there while gNeverEnteredCastle): once the athlete is on the bridge he is held looking up,
-- Lakitu on his cloud comes down out of the sky (from 1800, 2400, -2400) circling in on him, his tune starts within
-- 1000, he stops in front of him, says his piece (DIALOG_034) and flies off up and away, gone 6000 out. All in Mario 64
-- units at its 30 frames a second. (He never came, 2026-10-15.)
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET
local M = {}

local U = 0.75
local LOCK = "SM64Lakitu"
local st = nil

local function sins(a) return math.sin(a * math.pi / 32768.0) end
local function coss(a) return math.cos(a * math.pi / 32768.0) end
local function s16(a) a = math.floor(a) % 65536; if a >= 32768 then a = a - 65536 end; return a end
local function atan2s(y, x) return s16(math.floor(math.atan(x, y) * 32768.0 / math.pi + 0.5)) end
local function approach_s16(cur, target, inc)
    local d = s16(target - cur)
    if d > 0 then return (d > inc) and s16(cur + inc) or target end
    return (d < -inc) and s16(cur - inc) or target
end
local function approach_f(cur, target, d)
    if cur < target then return math.min(target, cur + d) end
    return math.max(target, cur - d)
end
local function sfx(name) local S = package.loaded["sfx"]; if S then pcall(S.play, name) end end

-- the athlete held looking up (as dialog.lua holds him for a message)
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
                -- (its walking and running too, as dialog.lua holds them: left on, the stick held as Lakitu came was
                -- kept, and run on through his words)
                o:EnableLocomotionInputCallback(FName(LOCK), not on)
                o:EnableAdvancedLocomotionInput(FName(LOCK), not on)
            end
        end
    end)
    if on then pcall(function() pawn.CharacterMovement:StopMovementImmediately() end) end
end

local PUFF_UP = { 11, 8, 12, 8, 9 }

function M.load(world, name, ctx)
    M.clear()
    if name ~= "grounds" or not (ctx and ctx.wanted and ctx.wanted()) then return end
    local data = ctx.actor_data("lakitu")
    if not data then return end
    st = { world = world:GetAddress(), ctx = ctx, act = 0, data = data, t = 0.0, acc = 0.0 }
    log("camera Lakitu: waiting on the bridge")
end

local function build(s)
    local world = lib.world()
    local inst = lib.make_instance(world, s.data, { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z }, 0.0, 1.0)
    if not inst then return false end
    inst.moves = true
    s.inst, s.puffs = inst, {}
    local mist = s.ctx.actor_data("mist")
    if mist then
        for i = 1, 5 do
            local p = lib.make_instance(world, mist, { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z }, 0.0, 4.0 / 3.0)
            if p then p.moves = true; s.puffs[i] = p end
        end
    end
    return true
end

function M.clear()
    if not st then return end
    if st.locked then lock(false) end
    local w = lib.world()
    if w and w:GetAddress() == st.world then
        if st.inst then lib.destroy(st.inst.actor) end
        for _, p in ipairs(st.puffs or {}) do lib.destroy(p.actor) end
    end
    st = nil
end

function M.forget() st = nil end

-- one Mario 64 frame; (mx, my, mz) the athlete's feet and myaw his facing, Mario 64 units
local function step(s, mx, my, mz, myaw)
    if s.act == 0 then
        -- (camera_lakitu_intro_act_trigger_cutscene: on the bridge - its bounds a little short of the bridge's own)
        if mx > -544.0 and mx < 545.0 and my > 800.0 and mz > -2000.0 and mz < -177.0 then
            if not build(s) then st = nil; return end
            lock(true)
            s.locked, s.act = true, 1
            s.x, s.y, s.z = 1800.0, 2400.0, -2400.0
            s.mpitch, s.myaw, s.fpitch, s.fyaw = 0x4000, 0, 0, 0
            s.speed, s.radius, s.pvel, s.yvel = 60.0, 1000.0, 0, 0
            s.frames = 0
            log("camera Lakitu: coming")
        end
        return
    end
    s.frames = s.frames + 1
    local dx, dy, dz = mx - s.x, my - s.y, mz - s.z
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    local to = atan2s(dz, dx)
    -- (facing him: obj_turn_pitch_toward_mario(120, 0), and his angle)
    s.fpitch = atan2s(math.sqrt(dx * dx + dz * dz), -(my - (s.y - 120.0)))
    s.fyaw = to
    local tpitch, tyaw = s.mpitch, to
    if s.act == 3 then
        -- (finished: off up and away)
        s.speed = approach_f(s.speed, 60.0, 3.0)
        tpitch, tyaw = -0x3000, -0x6000
        if dist > 6000.0 then M.clear(); log("camera Lakitu: gone"); return end
    elseif s.speed ~= 0.0 then
        if dist > 5000.0 then
            tpitch, tyaw = s.mpitch, to
        else
            local turn = 0x4000 - atan2s(s.radius, dist - s.radius)
            if s16(s.myaw - to) < 0 then turn = -turn end
            tyaw, tpitch = s16(to + turn), s.fpitch
            s.radius = approach_f(s.radius, 200.0, 50.0)
            if dist < 1000.0 then
                if not s.tune then
                    s.tune = true
                    local MU = package.loaded["music"]
                    if MU and MU.play then pcall(MU.play, "event_cutscene_lakitu", true) end
                    s.ctx.music_back_in(6.0)
                end
                s.speed = approach_f(s.speed, 20.0, 1.0)
                -- (within 500 and facing him: to a stop; he waits no more than 25 s for that)
                local facing = math.abs(s16(myaw - s.fyaw)) > 0x7000
                if dist < 500.0 and (facing or s.frames > 750) then s.speed = approach_f(s.speed, 0.0, 5.0) end
            end
        end
    elseif s.act == 1 then
        s.act = 2
        if s.locked then lock(false); s.locked = false end
        s.ctx.say(34, function() s.act = 3 end)
    end
    s.pvel = approach_s16(s.pvel, 2000, 400)
    s.mpitch = approach_s16(s.mpitch, tpitch, s.pvel)
    s.yvel = approach_s16(s.yvel, 2000, 100)
    s.myaw = approach_s16(s.myaw, tyaw, s.yvel)
    local fv = s.speed * coss(s.mpitch)
    s.x, s.z = s.x + fv * sins(s.myaw), s.z + fv * coss(s.myaw)
    s.y = s.y - s.speed * sins(s.mpitch)
end

local function draw(s, dt)
    local inst = s.inst
    if not inst then return end
    local wx, wy, wz = -s.z * U + OFFSET.X, s.x * U + OFFSET.Y, s.y * U + OFFSET.Z
    s.t = s.t + dt
    local anim = inst.data.anims and inst.data.anims[1]
    if anim then lib.pose(inst, anim, s.t * 30.0) end
    pcall(function()
        inst.actor:K2_TeleportTo({ X = wx, Y = wy, Z = wz },
            { Pitch = s.fpitch * 360.0 / 65536.0, Yaw = -s.fyaw * 360.0 / 65536.0, Roll = 0.0 })
    end)
    -- his cloud (cloud.inc.c bhv_cloud_part_update), puffs turned to the camera (their face is -x)
    local cam
    pcall(function() cam = lib.controller().PlayerCameraManager:GetCameraLocation() end)
    if not cam then return end
    local sc, frame = 4.0 / 3.0, s.t * 30.0
    for i, p in ipairs(s.puffs) do
        local k = i - 1
        local ang = s.fyaw + 0x10000 // 5 * k
        local off = 2.0 * coss(frame * 0x800 + 0x4000 * k) * sc
        local px = s.x + 25.0 * sc * sins(ang) + off
        local py = s.y + off + sc * PUFF_UP[i]
        local pz = s.z + 25.0 * sc * coss(ang) + off
        local qx, qy, qz = -pz * U + OFFSET.X, px * U + OFFSET.Y, py * U + OFFSET.Z
        local ddx, ddy, ddz = cam.X - qx, cam.Y - qy, cam.Z - qz
        pcall(function()
            p.actor:K2_TeleportTo({ X = qx, Y = qy, Z = qz },
                { Pitch = -math.deg(math.atan(ddz, math.sqrt(ddx * ddx + ddy * ddy))), Yaw = math.deg(math.atan(ddy, ddx)) + 180.0, Roll = 0.0 })
        end)
    end
end

-- (x, y, z): his feet, scene cm; yaw: his facing, degrees
function M.update(dt, x, y, z, yaw)
    local s = st
    if not s then return end
    local w = lib.world()
    if not (w and w:GetAddress() == s.world) then st = nil; return end
    local mx, my, mz = y / U, z / U, -x / U
    local myaw = s16(math.floor(((180.0 - (yaw or 0.0)) % 360.0) * 65536.0 / 360.0))     -- (Mario 64's yaw: 0 along +z)
    s.acc = math.min(s.acc + dt, 0.2)
    while st and s.acc >= 1.0 / 30.0 do
        s.acc = s.acc - 1.0 / 30.0
        step(s, mx, my, mz, myaw)
    end
    if st and s.inst then draw(s, dt) end
    -- (his cloud's wind while he is up - camera_lakitu.inc.c, cur_obj_play_sound_1(SOUND_AIR_LAKITU_FLY) every frame
    -- he flies: sfx/loop_lakitu.wav, held each tick, louder the nearer he is - "no wind sound on lakito", 2026-11-01)
    -- (only while he flies - coming down (act 1) and away (act 3), not while he hovers saying his piece (act 2):
    -- "wind noises when talking to lakito on the bridge?", 2026-11-01)
    if st and s.inst and (s.act == 1 or s.act == 3) then
        local S = package.loaded["sfx"]
        if S and S.hold then
            local d = math.sqrt(((s.x or 0) - mx) ^ 2 + ((s.y or 0) - my) ^ 2 + ((s.z or 0) - mz) ^ 2)
            -- (loop_wind: loop_lakitu.wav is all but silent, its loudest -29 dB)
            pcall(S.hold, "loop_wind", math.max(0.2, math.min(0.7, 0.7 - d / 7000.0)))
        end
    end
end

return M
