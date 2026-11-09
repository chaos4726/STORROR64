-- SM64Map: swimming as Mario 64 does it.
--
-- In the water the stick does not walk the athlete about: it points his head. Left and right turn him, forward
-- tips his head down (he dives), back tips it up (he rises). Each press of the swim button is a stroke: a push
-- of water that sends him the way his head points, faster with every stroke up to a top speed. Holding the
-- button keeps a steady kick going, slower than stroking. Let go and he slows to a stop and floats gently up.
-- At the surface he swims along it; a stroke with the stick pulled back jumps him out of the water.
--
-- His body is turned to match (swimpose.lua): stretched out along the way he is heading, rolling a little
-- with each stroke, upright and treading water when he stops at the surface.
local lib = require("lib")
local pad = require("pad")
local POSE = require("swimpose")
local okA, ARMS = pcall(require, "swimarms")       -- (his arms and legs swimming, on footik.lua's copy of him: "add our
if not okA then lib.log("swim: no arms (%s)", tostring(ARMS)); ARMS = nil end      -- stroke animation back", 2026-10-24)
-- Mario 64's swimming sounds (game/mario_actions_submerged.c), rendered from the player's ROM (sfx.lua): a stroke
-- (a stronger one when he is already going fast), the flutter kick twice a kick, breaking the surface
local okS, SFX = pcall(require, "sfx")
if not okS then SFX = nil end
local function sound(name) if SFX then pcall(SFX.play, name) end end
local KICK_SOUND = 12.0 / 30.0     -- seconds between kick sounds (frames 0 and 12 of the kick)
local log = lib.log

local S = {}

local sin, cos, rad, deg, max, min, abs, sqrt = math.sin, math.cos, math.rad, math.deg, math.max, math.min, math.abs, math.sqrt

-- (Mario 64's numbers, in its units a frame, turned into cm a second: 0.75 cm a unit, 30 frames a second)
local STROKE_SPEED = 300.0          -- added by each stroke
local TOP_SPEED = 630.0             -- the most strokes can reach (28 units a frame)
local KICK_SPEED = 270.0            -- what holding the button keeps him at (12 units a frame)
local DRAG = 420.0                  -- how fast he slows when he stops swimming (cm/s each second)
local TURN = 150.0                  -- degrees a second, stick fully over
local TILT = 90.0                   -- degrees a second his head tips up or down
local TILT_MAX = 75.0               -- as far as it goes either way
local LEVEL_OFF = 25.0              -- degrees a second his head comes back level when the stick is let go
local KICK_AFTER = 0.3              -- seconds the button is held before a stroke turns into a kick
local JUMP_UP, JUMP_FORWARD = 820.0, 260.0      -- out of the water at the surface
local STICK_DEAD = 0.2
local FLOAT_UP = 45.0               -- cm a second he drifts up when he is not swimming

local st = nil                      -- { yaw, pitch, speed, held, pc }

-- STORROR's locomotion takes the stick for walking and turning; in the water that is switched off, under a
-- name of its own, and back on when he leaves it (its own switch: EnableLocomotionInputCallback).
local function locomotion(pawn, on)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetClass():GetFName():ToString() == "LocomotionComponent" then
                o:EnableLocomotionInputCallback(FName("SM64Swim"), on)
                o:EnableAdvancedLocomotionInput(FName("SM64Swim"), on)
            end
        end
    end)
end

local function keys(names)
    local pc = lib.controller()
    if not pc then return false end
    for _, n in ipairs(names) do
        local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(n) }) end)
        if ok and v then return true end
    end
    return false
end

local SWIM_KEYS = { "Gamepad_FaceButton_Bottom", "SpaceBar" }

S.test = nil                        -- (tests: { x, y, down, tap } stands in for the stick and the button)

-- The stick, x right and y forward, -1..1: the left stick, or the movement keys.
local function stick()
    if S.test then return S.test.x or 0.0, S.test.y or 0.0 end
    local pc = lib.controller()
    local x, y = 0.0, 0.0
    pcall(function()
        x = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftX") })
        y = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftY") })
    end)
    if type(x) ~= "number" then x = 0.0 end
    if type(y) ~= "number" then y = 0.0 end
    if abs(x) < STICK_DEAD then x = 0.0 end
    if abs(y) < STICK_DEAD then y = 0.0 end
    if keys({ "D", "Right" }) then x = 1.0 elseif keys({ "A", "Left" }) then x = -1.0 end
    if keys({ "W", "Up" }) then y = 1.0 elseif keys({ "S", "Down" }) then y = -1.0 end
    return x, y
end

-- Into the water: he keeps the way he was facing, and the stick is the swim's, not the walk's.
function S.start(pawn)
    local pc = lib.controller()
    local yaw = 0.0
    pcall(function() yaw = pawn:K2_GetActorRotation().Yaw end)
    local v = pawn:GetVelocity()
    st = { yaw = yaw, pitch = 0.0, speed = min(TOP_SPEED, sqrt(v.X * v.X + v.Y * v.Y)), held = 0.0,
           was = keys(SWIM_KEYS), pawn = pawn }
    pcall(function() pc:SetIgnoreMoveInput(true) end)
    -- STORROR's own controls are off while he swims: its jump is on the swim button, and would fling him out
    -- of the water. (The camera is the controller's, and still turns; the swim reads the buttons itself.)
    pcall(function() pawn:DisableInput(pc) end)
    locomotion(pawn, false)
    -- STORROR moves its athlete by his animation ("root motion"), which leaves nothing to a speed set from
    -- here. In the water that is switched off, and the engine's own flying movement carries him: it slides
    -- him along the bottom and along walls instead of stopping him dead against them.
    pcall(function()
        local anim = pawn.Mesh:GetAnimInstance()
        st.anim, st.root_motion = anim, anim.RootMotionMode
        anim:SetRootMotionMode(1)                       -- ignore root motion
    end)
    pcall(function()
        local cm = pawn.CharacterMovement
        st.max_fly, st.brake = cm.MaxFlySpeed, cm.BrakingDecelerationFlying
        cm.MaxFlySpeed = TOP_SPEED + 80.0
        cm.BrakingDecelerationFlying = 0.0              -- (the swim does its own slowing down)
    end)
end

function S.stop(pawn)
    S.shell = nil
    if not st then return end
    local s0 = st
    st = nil
    pcall(function() lib.controller():SetIgnoreMoveInput(false) end)
    pcall(function() (pawn or s0.pawn):EnableInput(lib.controller()) end)
    locomotion(pawn or s0.pawn, true)
    pcall(function() if s0.anim:IsValid() then s0.anim:SetRootMotionMode(s0.root_motion or 3) end end)
    pcall(function()
        local cm = s0.pawn.CharacterMovement
        if s0.max_fly then cm.MaxFlySpeed = s0.max_fly end
        if s0.brake then cm.BrakingDecelerationFlying = s0.brake end
    end)
    POSE.reset()
    if ARMS then ARMS.reset() end
end

function S.active() return st ~= nil end

-- The Koopa shell held under water (mario_actions_submerged.c act_water_shell_swimming): for 240 frames he flutter-kicks
-- at 30 a frame (675 cm/s), the button not needed, and it is gone after; out of the water it is lost. (2026-10-15)
S.shell = nil
function S.grab_shell(secs) S.shell = secs or 8.0 end

-- Every tick in the water. z is his middle (scene space), top where his middle floats at the surface, fz the
-- floor under him (or nil). Returns the height he should be at now, and "jump" when he leaves the water.
function S.tick(pawn, dt, z, top, fz)
    if not st then S.start(pawn) end
    -- (STORROR turns its animation-driven movement back on by itself; it is turned off again every tick, or
    -- his walking animation walks him along the bottom)
    pcall(function()
        local a = st.anim
        if a and a.RootMotionMode ~= 1 then a:SetRootMotionMode(1) end
    end)
    local x, y = stick()
    -- (a star taken: held still and upright while the star dance plays - game.lua's, STORROR's corkscrew - as Mario
    -- 64's ACT_WATER_STAR_DANCE holds him; "next play our star animation when picking up a star underwater", 2026-10-18)
    local G = package.loaded["game"]
    local dancing = G ~= nil and G.star_dance_st ~= nil
    if dancing then x, y = 0.0, 0.0 end
    -- the head: turning, and tipping up and down (pulling back tips it up, as on Mario 64's stick)
    st.yaw = st.yaw + x * TURN * dt
    if y ~= 0.0 then
        st.pitch = max(-TILT_MAX, min(TILT_MAX, st.pitch - y * TILT * dt))
    elseif abs(st.pitch) > 0.5 then
        local back = min(abs(st.pitch), LEVEL_OFF * dt)
        st.pitch = st.pitch - back * (st.pitch > 0 and 1.0 or -1.0)
    end
    local at_surface = z >= top - 12.0
    if at_surface and st.below then sound("water_surface") end         -- (coming up to the surface)
    st.below = not at_surface
    if at_surface and st.pitch > 0.0 then st.pitch = st.pitch * (1.0 - min(1.0, dt * 6.0)) end

    -- strokes and kicks
    local down = keys(SWIM_KEYS)
    if S.test then
        down = (S.test.down or S.test.tap) and true or false
        S.test.tap = nil                -- (a tap is the button down for one tick)
    end
    if dancing or st.kb then down = false end         -- (knocked back: no strokes till it is over, S.knock)
    local stroke = down and not st.was
    st.was = down
    if stroke then
        if at_surface and y < -0.5 then
            -- out of the water
            local r = rad(st.yaw)
            sound("swim_stroke")
            S.stop(pawn)
            lib.bounce(pawn, cos(r) * JUMP_FORWARD, sin(r) * JUMP_FORWARD, JUMP_UP)
            return z, "jump"
        end
        sound(st.speed > KICK_SPEED and "swim_stroke_fast" or "swim_stroke")
        st.speed = min(TOP_SPEED, st.speed + STROKE_SPEED)
        st.kick_t = 0.0
        st.held = 0.0
    elseif down then
        st.held = st.held + dt
        if st.held > KICK_AFTER and st.speed < KICK_SPEED then st.speed = min(KICK_SPEED, st.speed + KICK_SPEED * dt * 3.0) end
        if st.held > KICK_AFTER then
            st.kick_t = (st.kick_t or 0.0) - dt
            if st.kick_t <= 0.0 then st.kick_t = KICK_SOUND; sound("swim_kick") end
        end
    end
    if not down or st.speed > KICK_SPEED then st.speed = max(0.0, st.speed - DRAG * dt) end
    if S.shell then
        S.shell = S.shell - dt
        if S.shell <= 0.0 then S.shell = nil
        else st.speed = min(675.0, st.speed + DRAG * dt + 1350.0 * dt) end
    end

    -- where that takes him: a speed for the engine's flying movement, which keeps him out of the bottom and
    -- the walls by itself. He drifts up when he is not swimming, and never comes up through the surface.
    if dancing then st.speed = 0.0 end
    local r, p = rad(st.yaw), rad(st.pitch)
    local hs, vz = st.speed * cos(p), st.speed * sin(p)
    if not down and st.speed < 60.0 and z < top then vz = vz + FLOAT_UP end
    if z >= top - 2.0 and vz > 0.0 then vz = 0.0 end
    if z > top + 2.0 then vz = min(vz, (top - z) * 5.0) end
    if at_surface and vz <= 0.0 and not down and st.speed < 40.0 and z < top then vz = (top - z) * 4.0 end
    if dancing then vz = 0.0 end
    -- (knocked back: its push on top, slowing to nothing - S.knock)
    local kbx, kby = 0.0, 0.0
    if st.kb then
        st.kb.t = st.kb.t - dt
        if st.kb.t <= 0.0 then st.kb = nil
        else
            local f = st.kb.t / st.kb.t0
            kbx, kby = st.kb.vx * f, st.kb.vy * f
        end
    end
    st.vx, st.vy = cos(r) * hs + kbx, sin(r) * hs + kby
    -- (STORROR turns him between ticks, back toward a facing of its own - the one he had when he last jumped or fell -
    -- a tenth of the way a frame, up to 12 degrees; that is how he is seen, not as he is set here. So his body was seen
    -- turned off the way he swam, and flicked from one side to the other as he swam past the far side of that facing:
    -- "I dont know why direction of swim unsyncs with the head all the time", 2026-10-24. How far it turned him since
    -- the last tick is how far it will turn him again before he is seen: his body is turned that far the other way in
    -- his capsule, swimpose.lua, and is seen facing the way he swims.)
    local pull = 0.0
    pcall(function()
        if st.set_yaw then pull = (pawn:K2_GetActorRotation().Yaw - st.set_yaw + 180.0) % 360.0 - 180.0 end
    end)
    if abs(pull) > 90.0 then pull = 0.0 end         -- (turned by something else: not that)
    pcall(function()
        pawn.CharacterMovement.Velocity = { X = st.vx, Y = st.vy, Z = vz }
        -- (every tick: STORROR turns him its own way otherwise)
        pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = st.yaw, Roll = 0.0 }, false)
    end)
    st.set_yaw = st.yaw

    -- the body: along the way he heads, upright when he treads water at the surface
    local resting = at_surface and st.speed < 60.0
    -- (swimming, 62 degrees forward - 20 more upright than the 82 that had him nearly flat: "make him tilt up a little
    -- more", "lets try 15 degrees upright", "try 20", 2026-10-18)
    POSE.set(pawn, dt, dancing and 0.0 or (resting and 25.0 or (62.0 - st.pitch)), st.speed, stroke, down and st.held > KICK_AFTER, -pull)
    if ARMS and not dancing then pcall(ARMS.update, dt, st.speed, stroke, down and st.held > KICK_AFTER, resting, st.yaw, st.pitch) end
    return z, nil                       -- (the movement is the engine's: the caller has nothing more to do)
end

-- How fast he is going across the water (cm/s, x and y), for climbing out onto a bank.
-- Knocked back through the water (a hit while he swims - game.lua G.knock_down): pushed along (vx, vy), cm a second,
-- slowing to nothing over `secs`, his strokes not taken till then, and swimming on after. Mario 64's
-- ACT_BACKWARD_WATER_KB / ACT_FORWARD_WATER_KB.
function S.knock(vx, vy, secs)
    if not st then return false end
    secs = secs or 0.7
    st.kb = { vx = vx or 0.0, vy = vy or 0.0, t = secs, t0 = secs }
    st.speed = 0.0
    return true
end

function S.velocity()
    if not st then return 0.0, 0.0 end
    return st.vx or 0.0, st.vy or 0.0
end

-- The map went (and the athlete with it): forget the swim without touching him.
function S.forget()
    st = nil
    if ARMS then ARMS.reset() end
    if POSE.forget then POSE.forget() end
end

function S.state() return st end       -- (tests)

return S
