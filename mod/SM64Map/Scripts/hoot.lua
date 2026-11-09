-- Hoot, Whomp's Fortress's owl (hoot.inc.c; Mario's side act_riding_hoot / interact_hoot): there in acts 3 to 6, asleep
-- and unseen up his tree until the athlete comes to its foot (Mario 64: climbs up to him - the athlete cannot climb the
-- trees). Then he wakes, says his piece (DIALOG_044) and flies about over his home (800 out, 150 below the tree top).
-- Jumped up to and caught in the air with the jump button held, he carries the athlete: first straight up to 6500, then
-- slowly down again, the stick turning him (gPlayer3Controller: 5 a frame per step of the stick), for as long as the
-- button stays down. Under 2700 he is tired (DIALOG_045) and two seconds later lets go. Let go of, he flies off home and
-- can be caught again a second later. All in Mario 64 units at its 30 frames a second, as camlakitu.lua.
-- The athlete hangs below him in the engine's flying mode (as swim.lua swims him), STORROR's own controls off; let
-- go, he falls, and just above the ground STORROR's record of where the fall began is cleared (as caps.lua's glides)
-- so that he lands on his feet - a long drop still costs power, as it does Mario. (Hoot was missing, 2026-10-15.)
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET
local M = {}

local U = 0.75
local LOCK = "SM64Hoot"
local HANG = 65.0               -- cm from the athlete's middle up to his hands, hanging (STORROR's bar hang): at Hoot's feet
local HANG_ANIM = "/SPP/SPPCharacter/Animation/MotionMatching/Swing/MotionMatchingSwing_171_Swings_31_08_24-001_979-5438.MotionMatchingSwing_171_Swings_31_08_24-001_979-5438"
local REACH = 300.0            -- how far over the athlete's feet his hands reach, arms up (Mario 64 units)
local DRAW = 6000.0             -- (Mario 64 shows him within 2000 of Mario only; the athlete's world is seen further)
local st = nil
local fall = nil                -- the athlete's drop after letting go: { softened }

local function sins(a) return math.sin(a * math.pi / 32768.0) end
local function coss(a) return math.cos(a * math.pi / 32768.0) end
local function s16(a) a = math.floor(a) % 65536; if a >= 32768 then a = a - 65536 end; return a end
local function atan2s(y, x) return s16(math.floor(math.atan(x, y) * 32768.0 / math.pi + 0.5)) end
local function approach_s16(cur, target, inc)
    local d = s16(target - cur)
    if d > 0 then return (d > inc) and s16(cur + inc) or target end
    return (d < -inc) and s16(cur - inc) or target
end
local function sfx(name, v) local S = package.loaded["sfx"]; if S then pcall(S.play, name, v) end end

-- ------------------------------------------------------------ the athlete held
local function components(pawn, fn)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            pcall(fn, o, o:GetClass():GetFName():ToString())
        end
    end)
end

local function hold(s, pawn, on)
    local pc = lib.controller()
    pcall(function() pc:SetIgnoreMoveInput(on) end)
    pcall(function() if on then pawn:DisableInput(pc) else pawn:EnableInput(pc) end end)
    components(pawn, function(o, cname)
        if cname == "LocomotionComponent" then
            o:EnableLocomotionInputCallback(FName(LOCK), not on)
            o:EnableAdvancedLocomotionInput(FName(LOCK), not on)
        elseif cname == "ParkourComponent" then
            o:ClearInputQueue()
            o:EnableAllParkourInputs(FName(LOCK), not on)
        end
    end)
    local cm = pawn.CharacterMovement
    if on then
        pcall(function()
            local anim = pawn.Mesh:GetAnimInstance()
            s.pa, s.root_motion = anim, anim.RootMotionMode
            anim:SetRootMotionMode(1)                   -- (his animation does not move him: Hoot does)
            -- hanging from Hoot's talons: STORROR's dead hang from a bar, held for as long as he is carried
            local seq = lib.try_load(HANG_ANIM)
            if seq then s.hang = anim:PlaySlotAnimationAsDynamicMontage(seq, FName("FullBody"), 0.15, 0.2, 1.0, 100000, -1.0, 0.0) end
        end)
        pcall(function()
            s.max_fly, s.brake = cm.MaxFlySpeed, cm.BrakingDecelerationFlying
            cm:SetMovementMode(5, 0)
            cm.MaxFlySpeed, cm.BrakingDecelerationFlying = 4000.0, 0.0
            cm:StopMovementImmediately()
        end)
    else
        pcall(function()
            if s.pa and s.pa:IsValid() then
                if s.hang and s.hang:IsValid() then s.pa:Montage_Stop(0.2, s.hang) end
                s.pa:SetRootMotionMode(s.root_motion or 2)
            end
        end)
        s.hang = nil
        pcall(function()
            if s.max_fly then cm.MaxFlySpeed = s.max_fly end
            if s.brake then cm.BrakingDecelerationFlying = s.brake end
        end)
        s.pa = nil
    end
end

-- the jump button (A), and the stick across (-1..1): read from the controller, as swim.lua does (his own are off)
local function a_down()
    if M.test then return M.test.a and true or false end
    local P = package.loaded["pad"]
    return P and P.down and P.down("ok") or false
end

local function stick_x()
    if M.test then return M.test.x or 0.0 end
    local pc = lib.controller()
    local x = 0.0
    pcall(function() x = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftX") }) end)
    if type(x) ~= "number" or math.abs(x) < 0.15 then x = 0.0 end
    local function key(n)
        local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(n) }) end)
        return ok and v
    end
    if key("D") or key("Right") then x = 1.0 elseif key("A") or key("Left") then x = -1.0 end
    return x
end

-- ------------------------------------------------------------ setting up
function M.add(world, o, ctx)
    M.clear()
    if not (o and o.sm64 and ctx) then return end
    local data = ctx.actor_data("geo_hoot_geo")
    if not data then log("hoot: no model"); return end
    local x, y, z = o.sm64[1], o.sm64[2], o.sm64[3]
    local inst = lib.make_instance(world, data, { X = -z * U + OFFSET.X, Y = x * U + OFFSET.Y, Z = y * U + OFFSET.Z }, 0.0, 1.0)
    if not inst then return end
    inst.moves = true
    pcall(function() inst.actor:SetActorHiddenInGame(true) end)     -- (asleep up the tree: GRAPH_RENDER_INVISIBLE)
    st = { world = world:GetAddress(), ctx = ctx, inst = inst, data = data,
           x = x, y = y, z = z, tx = x, ty = y, tz = z, hx = x + 800.0, hy = y - 150.0, hz = z + 300.0,
           yaw = 0, pitch = 0, f = 0, anim = 0, avail = "asleep", riding = false, act = nil, timer = 0,
           since = 999, acc = 0.0, prev = { x, y, z }, shown = false }
    log("hoot: asleep in his tree at %.0f %.0f %.0f", x, y, z)
end

function M.clear()
    local s = st
    st = nil
    if not s then return end
    local w = lib.world()
    if s.riding then
        local pawn = lib.pawn()
        if pawn then
            hold(s, pawn, false)
            pcall(function() pawn.CharacterMovement:SetMovementMode(3, 0) end)    -- (down, as from a fall: never left flying)
            local G = package.loaded["game"]
            if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end     -- (and not a fall from up there)
        end
        local G = package.loaded["game"]
        if G then G.carried = nil end
    end
    if w and w:GetAddress() == s.world and s.inst then lib.destroy(s.inst.actor) end
end

function M.forget()
    if st and st.riding then local G = package.loaded["game"]; if G then G.carried = nil end end
    st, fall = nil, nil
end

function M.active() return st ~= nil and st.riding end

-- ------------------------------------------------------------ Hoot (hoot.inc.c)
local function floor_at(s, x, y, z)
    local f = s.ctx.floor(-z * U, x * U, y * U)
    return f and f / U or nil
end

local function find_next_floor(s, dist)
    local x, z = dist * sins(s.yaw) + s.x, dist * coss(s.yaw) + s.z
    return floor_at(s, x, 10000.0, z)
end

local function floor_bounce(s)
    local fy = find_next_floor(s, 375.0)
    if fy and fy + 75.0 > s.y then s.pitch = s16(s.pitch - 3640.8888) end
    fy = find_next_floor(s, 200.0)
    if fy and fy + 125.0 > s.y then s.pitch = s16(s.pitch - 7281.7776) end
    fy = find_next_floor(s, 0.0)
    if fy and fy + 125.0 > s.y then s.y = fy + 125.0 end
    if s.pitch < -21845 then s.pitch = -21845 end
end

local function anim_frame(s) return math.floor(s.f) % ((s.anim == 1) and 10 or 20) end

local function free_step(s, speed)
    local fr = anim_frame(s)
    local px, pz = s.x, s.z
    local vy = sins(s.pitch) * speed
    local hs = coss(s.pitch) * speed
    s.x = s.x + sins(s.yaw) * hs
    s.y = s.y - (vy + coss(math.floor(fr * 3276.8)) * 50.0 / 4.0)
    s.z = s.z + coss(s.yaw) * hs
    if not floor_at(s, s.x, s.y, s.z) then s.x, s.z = px, pz end
end

local function carry_step(s, speed)
    local fr = anim_frame(s)
    local vy = sins(s.pitch) * speed
    local hs = coss(s.pitch) * speed
    s.vx, s.vz = sins(s.yaw) * hs, coss(s.yaw) * hs
    s.x = s.x + s.vx
    s.y = s.y - (vy + coss(math.floor(fr * 6553.6)) * 50.0 / 4.0)
    s.z = s.z + s.vz
end

local function surface_collision(s, px, pz)
    local fy = floor_at(s, s.x, s.y, s.z)
    -- (out over the void past the fortress's edge he flies on: Mario 64's level has floor under all of it, this map's
    -- floors only the fortress, and he stopped dead at their edge, hanging there - "for whatever reason he gets stuck in
    -- the air", 2026-10-17. Only the 8000 bounds hold him, and at them he turns back in)
    local out = false
    if math.abs(s.x) > 8000.0 then s.x, out = px, true end
    if math.abs(s.z) > 8000.0 then s.z, out = pz, true end
    if out then s.yaw = approach_s16(s.yaw, atan2s(-s.z, -s.x), 0x400) end
    if fy and fy + 125.0 > s.y then s.y = fy + 125.0 end
end

local function turn_to_home(s)
    local dx, dy, dz = s.hx - s.x, s.hy - s.y, s.hz - s.z
    s.yaw = approach_s16(s.yaw, atan2s(dz, dx), 0x140)
    s.pitch = approach_s16(s.pitch, atan2s(math.sqrt(dx * dx + dz * dz), -dy), 0x140)
end

local release

local function action_loop(s, m)
    local px, pz = s.x, s.z
    s.timer = s.timer + 1
    if s.act == "ascent" then
        -- (hoot_act_ascent: turning toward the middle of the level, straight up at 60 till 6500)
        s.yaw = approach_s16(s.yaw, atan2s(-s.z, -s.x), 0x500)
        s.pitch = s16(0xCE38)
        if s.timer >= 29 then
            local SX = package.loaded["sfx"]
            if SX and SX.hold then SX.hold("loop_wind", 0.6) end
        end
        if s.y > 6500.0 then s.act, s.timer = "carry", 0 end
        carry_step(s, 60)
    elseif s.act == "carry" then
        s.yaw = s16(s.yaw - 5 * math.floor(m.stick * 64.0))
        s.pitch = 0x71C
        if s.y < 2700.0 and not s.asked then
            -- (tired: time stands still while he says so)
            s.asked, s.waiting = true, true
            log("hoot: tired (DIALOG_045)")
            s.ctx.say(45, function() s.waiting, s.act, s.timer = false, "tired", 0 end)
            return
        end
        carry_step(s, 20)
    elseif s.act == "tired" then
        s.yaw = s16(s.yaw - 5 * math.floor(m.stick * 64.0))
        s.pitch = 0
        carry_step(s, 20)
        if s.timer > 60 then s.drop = "tired" end
    end
    surface_collision(s, px, pz)
end

local function grab(s, pawn)
    s.riding, s.act, s.timer, s.asked, s.drop, s.blocked = true, "ascent", 0, false, nil, 0
    hold(s, pawn, true)
    local G = package.loaded["game"]
    if G then G.carried = true; G.air = false end
    fall = nil
    log("hoot: caught - up we go")
end

release = function(s, pawn, why)
    s.riding, s.act, s.since, s.waiting = false, nil, 0, false
    if pawn then
        hold(s, pawn, false)
        pcall(function()
            local cm = pawn.CharacterMovement
            cm:SetMovementMode(3, 0)
            local k = 30.0 * U * 0.5                    -- (going his way a little as he lets go)
            cm.Velocity = { X = -(s.vz or 0.0) * k, Y = (s.vx or 0.0) * k, Z = 0.0 }
        end)
        -- (STORROR's record of where his fall began goes; and again just above the ground: M.update)
        local G = package.loaded["game"]
        if G then
            G.carried = nil
            if G.parkour_reset then pcall(G.parkour_reset, pawn) end
        end
        fall = { softened = false, t = 0.0 }
    end
    sfx("mario_uh")
    log("hoot: let go (%s) at %.0f", tostring(why), s.y)
end

local function awake_idle(s)
    turn_to_home(s)
    floor_bounce(s)
    free_step(s, 10)
end

-- one Mario 64 frame; m: the athlete { x, y (feet), z, air, a, stick }
local function step(s, m, pawn)
    s.prev[1], s.prev[2], s.prev[3] = s.x, s.y, s.z
    s.since = s.since + 1
    local dx, dz = m.x - s.x, m.z - s.z
    if s.avail == "asleep" then
        -- (Mario 64: within 50 of him - he sits at the top of his tree, so for Mario climbed up to him. Here the same:
        -- the athlete climbing his tree and at the top of it, or up on top of it - not at its foot: "make sure the owl
        -- doesn't trigger until your climbing the tree also when your at the top of the tree", 2026-10-17)
        local wake = false
        local CL = package.loaded["climb"]
        if CL and CL.on_trunk then
            local t, below = CL.on_trunk()
            if t then
                local ex, ey = t.x - (-s.z * U + OFFSET.X), t.y - (s.x * U + OFFSET.Y)
                wake = ex * ex + ey * ey < 150.0 * 150.0 and below < 40.0
            end
        end
        if not wake and not m.air and dx * dx + dz * dz < 150.0 * 150.0 and m.y >= s.y then wake = true end
        if wake then
            s.avail, s.shown = "talk", true
            pcall(function() s.inst.actor:SetActorHiddenInGame(false) end)
            log("hoot: awake (DIALOG_044)")
            -- (with Mario 64's CUTSCENE_DIALOG camera on him, as the others who speak: game.lua G.dialog_cut)
            local G = package.loaded["game"]
            if G and G.dialog_cut then pcall(G.dialog_cut, -s.z * U, s.x * U, s.y * U - 40.0, 80.0) end
            s.ctx.say(44, function() s.avail = "ready"; log("hoot: ready to fly") end)
        end
        return
    end
    if s.waiting then return end                        -- (his words being read: everything waits)
    local G = package.loaded["game"]
    if s.riding and G and (G.star_exit_at or G.pending or G.dying) then
        -- (a star caught on the way: ACT_FALL_AFTER_STAR_GRAB - he lets go, and the drop does not hurt)
        G.no_fall_until = os.clock() + 8.0
        release(s, pawn, G.star_exit_at and "star" or "leaving")
        return
    end
    if s.riding then
        if s.drop then release(s, pawn, s.drop); s.drop = nil
        elseif not m.a then release(s, pawn, "button")
        else
            action_loop(s, m)
            s.anim = 1
        end
    else
        s.anim, s.act, s.timer = 0, nil, 0
        awake_idle(s)
        -- caught (interact_hoot): in the air, a second after last letting go, his body within reach of the
        -- athlete's hands (Mario's hurtbox is 37 wide and 160 tall; the athlete's reach, arms up, ~300 up)
        if s.avail == "ready" and s.since > 30 and m.air and m.a then
            local h = dx * dx + dz * dz
            if h < 125.0 * 125.0 and m.y <= s.y + 75.0 and m.y + REACH >= s.y then grab(s, pawn) end
        end
    end
    s.f = s.f + 1.0
    if anim_frame(s) == 0 and s.shown then
        local d = math.sqrt(dx * dx + (m.y - s.y) ^ 2 + dz * dz)
        if d < 2500.0 then sfx("hoot_flap", math.max(0.15, 1.0 - d / 2500.0)) end
    end
end

-- ------------------------------------------------------------ each tick
-- (x, y, z): the athlete's feet, scene cm (minus OFFSET)
function M.update(dt, pawn, x, y, z)
    -- his drop after letting go: soft landing just above the floor (G.parkour_reset)
    if fall and pawn then
        fall.t = fall.t + dt
        local falling = false
        pcall(function() falling = pawn.CharacterMovement:IsFalling() end)
        if not falling and fall.t > 0.2 then fall = nil
        elseif falling and not fall.softened then
            local G = package.loaded["game"]
            local fz = G and G.floor_z and G.floor_z(x, y, z + 20.0)
            if fz and z - fz < 60.0 then
                fall.softened = true
                if G.parkour_reset then pcall(G.parkour_reset, pawn) end
            end
        end
        if fall and fall.t > 30.0 then fall = nil end
    end
    local s = st
    if not s then return end
    local w = lib.world()
    if not (w and w:GetAddress() == s.world) then st = nil; return end
    local m = { x = y / U, y = z / U, z = -x / U, air = false, a = a_down(), stick = stick_x() }
    pcall(function() m.air = pawn.CharacterMovement:IsFalling() end)
    s.acc = math.min(s.acc + dt, 0.2)
    while st and s.acc >= 1.0 / 30.0 do
        s.acc = s.acc - 1.0 / 30.0
        step(s, m, pawn)
    end
    if not st then return end
    -- drawn between his last two frames
    local a = s.acc * 30.0
    local hx = s.prev[1] + (s.x - s.prev[1]) * a
    local hy = s.prev[2] + (s.y - s.prev[2]) * a
    local hz = s.prev[3] + (s.z - s.prev[3]) * a
    local wx, wy, wz = -hz * U + OFFSET.X, hx * U + OFFSET.Y, hy * U + OFFSET.Z
    if s.shown then
        local dx, dz = m.x - hx, m.z - hz
        local near = dx * dx + dz * dz < DRAW * DRAW
        if near ~= s.drawn then
            s.drawn = near
            pcall(function() s.inst.actor:SetActorHiddenInGame(not near) end)
        end
        if near then
            lib.set_pose(s.inst, wx, wy, wz, -s.yaw * 360.0 / 65536.0)
            local anim = s.data.anims and s.data.anims[s.anim + 1]
            if anim then pcall(lib.pose, s.inst, anim, s.f + a) end
        end
    end
    -- the athlete hanging from him: carried to where he hangs (the engine's flying movement, which stops him at
    -- walls - Hoot lets go then, as he does when he flies into one)
    if s.riding and pawn then
        local tx, ty, tz = wx, wy, wz - HANG
        pcall(function()
            local l = pawn:K2_GetActorLocation()
            local cm = pawn.CharacterMovement
            if cm.MovementMode ~= 5 then cm:SetMovementMode(5, 0) end
            local ex, ey, ez = tx - l.X, ty - l.Y, tz - l.Z
            local d = math.sqrt(ex * ex + ey * ey + ez * ez)
            if d > 150.0 then s.blocked = s.blocked + 1 else s.blocked = 0 end
            s.miss = { l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z, d }
            -- (to where he hangs, and on with Hoot: his own speed, scene cm a second)
            local fx, fy, fz = -(s.z - s.prev[3]) * U * 30.0, (s.x - s.prev[1]) * U * 30.0, (s.y - s.prev[2]) * U * 30.0
            if s.waiting then fx, fy, fz = 0.0, 0.0, 0.0 end
            local k = 1.0 / math.max(dt, 1.0 / 120.0)
            cm.Velocity = { X = ex * k * 0.7 + fx, Y = ey * k * 0.7 + fy, Z = ez * k * 0.7 + fz }
            pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = 180.0 - s.yaw * 360.0 / 65536.0, Roll = 0.0 }, false)
            if s.pa and s.pa:IsValid() and s.pa.RootMotionMode ~= 1 then s.pa:SetRootMotionMode(1) end
        end)
        s.relock = (s.relock or 0.0) + dt
        if s.relock > 0.5 and not s.waiting then
            s.relock = 0.0
            local pc = lib.controller()
            -- (the lock is a count: added to only when off, or every re-lock stayed on after - "randomly stops")
            pcall(function() if not pc:IsMoveInputIgnored() then pc:SetIgnoreMoveInput(true) end end)
            pcall(function() pawn:DisableInput(pc) end)
        end
        if s.blocked > 6 and not s.waiting then
            local q = s.miss or {}
            log("hoot: he is held back %.0f cm from Hoot's feet (at %.0f %.0f %.0f; Hoot %.0f %.0f %.0f)", q[4] or -1,
                (q[2] or 0) / U, (q[3] or 0) / U, -(q[1] or 0) / U, s.x, s.y, s.z)
            release(s, pawn, "wall")
        end
    end
end

return M
