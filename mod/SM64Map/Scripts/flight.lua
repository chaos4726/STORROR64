-- Wing Cap flight (mario_actions_airborne.c act_shot_from_cannon / act_triple_jump -> act_flying, update_flying /
-- _pitch / _yaw): shot from a cannon with the Wing Cap on, or off a triple jump's worth (a third jump in a row, or
-- STORROR's corkscrew, vortex or gainer flip - game.lua G.triple_at - once STORROR's move is over: his own moves are
-- never cut short), once he is on the way down he flies. The stick pitches him (pushed forward: nose
-- down) and turns him; diving gains speed and climbing loses it - made easier than Mario 64's: the nose stays where he
-- puts it and he never stalls (see step). Touching down ends it (Mario's dive slide - here a landing), and so does a
-- wall (a bonk and a knock back), the water, or the cap running out. Flown in the engine's flying mode with STORROR's
-- controls off; his body laid out along his flight (swimpose.lua) with his arms out like wings.
-- Mario 64 units at its 30 frames a second. (Wing Mario only glided, 2026-10-15.)
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET
local POSE = require("swimpose")
local M = {}

local U = 0.75
local LOCK = "SM64Fly"
-- (his arms out to his sides like wings, as Mario flies: STORROR's balancing walk, held at its arms-out moment - it was
-- the bar hang, hands together in front: "make the wing cap better", 2026-10-16)
local ARMS = "/SPP/SPPCharacter/Animation/MotionMatching/Balance/MotionMatchingBalance_15_DavidBalance-001.MotionMatchingBalance_15_DavidBalance-001"
local ARMS_AT = 0.5
-- (shot from a cannon: Mario's "airborne on his stomach", his arms out ahead of him - STORROR's bar hang, laid along
-- the shot)
local SHOT_ARMS = "/SPP/SPPCharacter/Animation/MotionMatching/Swing/MotionMatchingSwing_171_Swings_31_08_24-001_979-5438.MotionMatchingSwing_171_Swings_31_08_24-001_979-5438"
local BANK_MAX = 35.0           -- degrees he leans into a turn at most (Mario 64: roll = 20 x the turn's speed)
local CAM_FOLLOW = 6.0          -- 1/s: how fast the camera comes round behind him (Mario 64: CAMERA_MODE_BEHIND_MARIO;
                                -- at 3 it fell behind in a turn and showed him side on)
local MAXP = 0x2AAA
local MIN_FV = 28.0             -- Mario 64 units a frame: never slower in the air (no stall)
local MAX_FV = 110.0            -- (a long dive's top speed)
local LEVEL_OFF = 0x100         -- a frame: the nose brought down to level when climbing has run out of speed
local GRAB_REACH = 150.0        -- cm from a tree's trunk (its middle) within which RT or LT grabs it

local fl = nil                  -- the flight: { pitch, yaw, fv, pvel, yvel, ... }
local fall = nil
local ctx = {}

local function sins(a) return math.sin(a * math.pi / 32768.0) end
local function coss(a) return math.cos(a * math.pi / 32768.0) end
local function s16(a) a = math.floor(a) % 65536; if a >= 32768 then a = a - 65536 end; return a end
local function approach(cur, target, inc, dec)
    if cur < target then return math.min(target, cur + inc) end
    return math.max(target, cur - dec)
end
local function sfx(name, v) local S = package.loaded["sfx"]; if S then pcall(S.play, name, v) end end

function M.setup(c) ctx = c or {} end

-- (one of STORROR's clips over his whole body, held still at `at` seconds: his arms for the flight or the shot)
local function play_arms(f, path, at)
    pcall(function()
        local anim = f.pa
        if not (anim and anim:IsValid()) then return end
        if f.arms and f.arms:IsValid() then anim:Montage_Stop(0.2, f.arms) end
        f.arms, f.arms_path, f.arms_at = nil, path, at
        local seq = lib.try_load(path)
        if seq then
            f.arms = anim:PlaySlotAnimationAsDynamicMontage(seq, FName("FullBody"), 0.2, 0.2, 1.0, 100000, -1.0, at)
            if f.arms and f.arms:IsValid() then anim:Montage_SetPlayRate(f.arms, 0.0) end
        end
    end)
end

local function hold(f, pawn, on)
    local pc = lib.controller()
    pcall(function() pc:SetIgnoreMoveInput(on) end)
    pcall(function() if on then pawn:DisableInput(pc) else pawn:EnableInput(pc) end end)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            local cname = o:GetClass():GetFName():ToString()
            if cname == "LocomotionComponent" then
                o:EnableLocomotionInputCallback(FName(LOCK), not on)
                o:EnableAdvancedLocomotionInput(FName(LOCK), not on)
            elseif cname == "ParkourComponent" then
                o:ClearInputQueue()
                o:EnableAllParkourInputs(FName(LOCK), not on)
            end
        end
    end)
    local cm = pawn.CharacterMovement
    if on then
        pcall(function()
            local anim = pawn.Mesh:GetAnimInstance()
            f.pa, f.root_motion = anim, anim.RootMotionMode
            anim:SetRootMotionMode(1)
        end)
        if f.shot then play_arms(f, SHOT_ARMS, 0.0) else play_arms(f, ARMS, ARMS_AT) end
        pcall(function()
            f.max_fly, f.brake = cm.MaxFlySpeed, cm.BrakingDecelerationFlying
            cm:SetMovementMode(5, 0)
            cm.MaxFlySpeed, cm.BrakingDecelerationFlying = 6000.0, 0.0
        end)
    else
        pcall(function()
            if f.pa and f.pa:IsValid() then
                if f.arms and f.arms:IsValid() then f.pa:Montage_Stop(0.2, f.arms) end
                f.pa:SetRootMotionMode(f.root_motion or 2)
            end
        end)
        pcall(function()
            if f.max_fly then cm.MaxFlySpeed = f.max_fly end
            if f.brake then cm.BrakingDecelerationFlying = f.brake end
        end)
        POSE.reset()
    end
end

-- the stick as Mario 64's controller has it: x right, y up (pushed forward), each -64..64
local function stick()
    if M.test then return (M.test.x or 0.0) * 64.0, (M.test.y or 0.0) * 64.0 end
    local pc = lib.controller()
    local x, y = 0.0, 0.0
    pcall(function()
        x = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftX") })
        y = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftY") })
    end)
    if type(x) ~= "number" then x = 0.0 end
    if type(y) ~= "number" then y = 0.0 end
    if math.abs(x) < 0.15 then x = 0.0 end
    if math.abs(y) < 0.15 then y = 0.0 end
    local function key(n)
        local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(n) }) end)
        return ok and v
    end
    if key("D") or key("Right") then x = 1.0 elseif key("A") or key("Left") then x = -1.0 end
    if key("W") or key("Up") then y = 1.0 elseif key("S") or key("Down") then y = -1.0 end
    return x * 64.0, y * 64.0
end

local function stop(pawn, why, kv)
    local f = fl
    fl = nil
    M.paused = nil
    if not f then return end
    hold(f, pawn, false)
    pcall(function()
        local cm = pawn.CharacterMovement
        cm:SetMovementMode(3, 0)
        local k = (kv or 0.0) * U * 30.0
        cm.Velocity = { X = -coss(f.yaw) * k, Y = sins(f.yaw) * k, Z = 0.0 }
    end)
    local G = package.loaded["game"]
    if G then
        if G.carried == "fly" then G.carried = nil end
        if G.parkour_reset then pcall(G.parkour_reset, pawn) end
        if f.shot and G.PLAT then G.PLAT.cannon_flight = nil end      -- (out of act_shot_from_cannon: no flight later)
    end
    fall = { softened = false, t = 0.0 }
    log("%s: over (%s)", f.shot and "cannon shot" or "flight", why)
end

function M.active() return fl ~= nil end
function M.pause(on) M.paused = on or nil end
-- (out of the flight, falling as from its end, landing softened: a star taken in the air - ACT_FALL_AFTER_STAR_GRAB)
function M.land(pawn, why)
    if fl then stop(pawn or lib.pawn(), why or "ended") end
end

-- Knocked flat mid-flight (game.lua G.knock_down, just before its ragdoll): out of the flight first, as Mario 64's
-- ends in a knockback - it went on steering the ragdoll ("the wing cap is very buggy": a water bomb, 2026-10-16)
function M.knocked(pawn)
    if not fl then return end
    stop(pawn or lib.pawn(), "knocked flat")
    fall = nil                  -- (the ragdoll falls as it will: no landing to soften)
end

-- (a new map: nothing of the old one touched)
function M.forget()
    if fl then local G = package.loaded["game"]; if G and G.carried == "fly" then G.carried = nil end end
    fl, fall, M.paused = nil, nil, nil
end

function M.clear()
    local pawn = lib.pawn()
    if fl and pawn then stop(pawn, "the scene goes") end
end

-- one Mario 64 frame of flight (update_flying)
local function step(f)
    f.ppitch, f.pyaw, f.pfv = f.pitch, f.yaw, f.fv
    local sx, sy = stick()
    -- pitch: pushed forward, nose down
    local tp = -(sy * (f.fv / 5.0))
    if tp > 0 then
        if f.pvel < 0 then f.pvel = math.min(f.pvel + 0x40, 0x20) else f.pvel = approach(f.pvel, tp, 0x20, 0x40) end
    elseif tp < 0 then
        if f.pvel > 0 then f.pvel = math.max(f.pvel - 0x40, -0x20) else f.pvel = approach(f.pvel, tp, 0x40, 0x20) end
    else
        f.pvel = approach(f.pvel, 0, 0x40, 0x40)
    end
    -- yaw: the stick across
    local ty = -(sx * (f.fv / 4.0))
    if ty > 0 then
        if f.yvel < 0 then f.yvel = math.min(f.yvel + 0x40, 0x10) else f.yvel = approach(f.yvel, ty, 0x10, 0x20) end
    elseif ty < 0 then
        if f.yvel > 0 then f.yvel = math.max(f.yvel - 0x40, -0x10) else f.yvel = approach(f.yvel, ty, 0x20, 0x10) end
    else
        f.yvel = approach(f.yvel, 0, 0x40, 0x40)
    end
    f.yaw = s16(f.yaw + f.yvel)
    f.fv = f.fv - (2.0 * (f.pitch / 0x4000) + 0.1)
    f.fv = f.fv - 0.5 * (1.0 - coss(f.yvel))
    -- (made easier: "we need to add a new flying mechanic its not working out" - he chose Mario 64's, made easier, no
    -- climbing by itself at speed and no stall, 2026-10-16. Mario 64 also turns the nose by (fv - 32) x 6 or 10 a frame
    -- - up when fast, down when slow - and drops it 0x400 a frame under 4: it climbed him into a stall over and over.
    -- Now the nose stays where he puts it, the speed never falls under MIN_FV, and out of speed in a climb he levels
    -- off instead of stalling. Diving still builds speed and climbing still costs it.)
    local p = f.pitch + f.pvel
    if f.fv <= MIN_FV then
        f.fv = MIN_FV
        if f.pvel > 0 then p = f.pitch end                          -- (no climbing on no speed)
        if p > 0 then p = math.max(0, p - LEVEL_OFF) end
    end
    f.fv = math.min(f.fv, MAX_FV)
    f.pitch = math.max(-MAXP, math.min(MAXP, p))
end

-- one Mario 64 frame of a cannon shot (act_shot_from_cannon; apply_gravity: only 1 a frame for it, 75 at most down;
-- 0.05 a frame of speed lost, 10 at least); his body along the way he is going
local function shot_step(f)
    f.ppitch, f.pyaw, f.pfv, f.pvy = f.pitch, f.yaw, f.fv, f.vy
    f.vy = math.max(-75.0, f.vy - 1.0)
    f.fv = math.max(10.0, f.fv - 0.05)
    f.pitch = s16(math.atan(f.vy, f.fv) * 32768.0 / math.pi)
end

-- Shot out of a cannon (platforms.lua, at its mouth; pitch and yaw in degrees, yaw an engine yaw): 100 a frame along
-- the barrel, flown here as the Wing Cap flight is - in the engine's flying mode with STORROR's controls off. (Let go
-- to STORROR's own falling, he was thrown into its flail and held in the air there - all the time he sat in the
-- barrel it thought him falling - and its moves took his speed; nor does it have Mario's light fall for a shot.)
-- A wall knocks him back (the bonk), the ground ends it, and with the Wing Cap on, once on the way down, he flies.
function M.shoot(pawn, pitch, yaw)
    if not pawn or fl then return false end
    local a = pitch * 65536.0 / 360.0
    fl = { shot = true, fv = 100.0 * coss(a), vy = 100.0 * sins(a), pitch = s16(a), yaw = s16((180.0 - yaw) * 65536.0 / 360.0),
           pvel = 0, yvel = 0, acc = 0.0, blocked = 0, relock = 0.0, snap = true, t0 = os.clock() }
    hold(fl, pawn, true)
    local G = package.loaded["game"]
    if G then G.carried = "fly"; G.air = false end
    fall = nil
    sfx("mario_yahoo")                                  -- (as loud as MARIO FX: sfx.lua)
    log("cannon shot: pitch %.0f, yaw %.0f", pitch, yaw)
    return true
end

-- Flying from the start (the Tower of the Wing Cap's arrival, level_update.c MARIO_SPAWN_FLYING: set_mario_action
-- ACT_FLYING - "you should start in the sky with the wing cap equipped already flying", 2026-10-17): level, the way
-- `yaw` faces (an engine yaw), at `fv` a frame (Mario's flying speed, 32 by default). The Wing Cap must be on.
function M.fly_in(pawn, yaw, fv)
    if not pawn or fl then return false end
    fl = { fv = fv or 32.0, pitch = 0, yaw = s16((180.0 - yaw) * 65536.0 / 360.0), pvel = 0, yvel = 0, acc = 0.0,
           blocked = 0, relock = 0.0, snap = true }
    fl.ppitch, fl.pyaw, fl.pfv = fl.pitch, fl.yaw, fl.fv
    hold(fl, pawn, true)
    local G = package.loaded["game"]
    if G then G.carried = "fly"; G.air = false end
    fall = nil
    log("flight: flying in (%.0f a frame)", fl.fv)
    return true
end

-- (the shot, on the way down with the Wing Cap on: act_flying, at the shot's speed and pitch)
local function to_flight(f)
    f.shot, f.vy, f.pvy = nil, nil, nil
    f.pvel, f.yvel = 0, 0
    play_arms(f, ARMS, ARMS_AT)
    local G = package.loaded["game"]
    if G and G.PLAT then G.PLAT.cannon_flight = nil end
    log("flight: off he flies (%.0f a frame)", f.fv)
end

-- RT or LT (STORROR's grab buttons)
local function trigger_down()
    if M.test and M.test.grab ~= nil then return M.test.grab end
    local pc = lib.controller()
    local function key(n)
        local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(n) }) end)
        return ok and v
    end
    return key("Gamepad_RightTrigger") or key("Gamepad_LeftTrigger")
end

-- (x, y, z): his feet, scene cm (minus OFFSET)
function M.update(dt, pawn, x, y, z)
    if not pawn then return end
    local G = package.loaded["game"]
    -- the drop after a flight: STORROR's fall record cleared just above the ground (his landing a short one)
    if fall then
        fall.t = fall.t + dt
        local falling = false
        pcall(function() falling = pawn.CharacterMovement:IsFalling() end)
        if not falling and fall.t > 0.2 then fall = nil
        elseif falling and not fall.softened then
            local fz = G and G.floor_z and G.floor_z(x, y, z + 20.0)
            if fz and z - fz < 60.0 then
                fall.softened = true
                if G.parkour_reset then pcall(G.parkour_reset, pawn) end
            end
        end
        if fall and fall.t > 20.0 then fall = nil end
    end
    local CAPS = package.loaded["caps"]
    local wing = CAPS and CAPS.on and CAPS.on("wing")
    if not fl then
        -- (act_shot_from_cannon: the Wing Cap on and on the way down - he flies)
        local P = G and G.PLAT
        local triple = G and G.triple_at and os.clock() - G.triple_at < 2.5
        if not (wing and P and (P.cannon_flight or triple)) or (G.carried or G.swim) then return end
        local v, air, busy = nil, false, false
        pcall(function() v = pawn:GetVelocity(); air = pawn.CharacterMovement:IsFalling() end)
        if triple and not P.cannon_flight then
            pcall(function()
                -- (his jump or flip still under way; his falling loop is not a move of his)
                local mt = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
                local name = mt and mt:IsValid() and mt:GetFName():ToString() or ""
                busy = name:find("^MontageJump") ~= nil or name:find("^MontageFlip") ~= nil
            end)
        end
        if busy or not (v and air and v.Z < 90.0) then return end
        G.triple_at = nil
        local hs = math.sqrt(v.X * v.X + v.Y * v.Y)
        local yaw = 0.0
        pcall(function() yaw = pawn:K2_GetActorRotation().Yaw end)
        if hs > 50.0 then yaw = math.deg(math.atan(v.Y, v.X)) end
        fl = { fv = math.min(100.0, math.sqrt(hs * hs + v.Z * v.Z) / (U * 30.0)),
               pitch = math.max(-MAXP, math.min(MAXP, math.atan(v.Z, math.max(hs, 1.0)) * 32768.0 / math.pi)),
               yaw = s16((180.0 - yaw) * 65536.0 / 360.0), pvel = 0, yvel = 0, acc = 0.0, blocked = 0, relock = 0.0 }
        P.cannon_flight = nil
        hold(fl, pawn, true)
        if G then G.carried = "fly"; G.air = false end
        fall = nil
        sfx("mario_yahoo")                              -- (as loud as MARIO FX: sfx.lua)
        log("flight: off he flies (%.0f a frame)", fl.fv)
        return
    end
    local f = fl
    if G and (G.warping or G.pending or G.dying) then stop(pawn, "leaving"); return end
    -- (time stopped - a star's cutscene, game.lua G.star_cutscene: held where he is, his flight's clock still)
    if M.paused then
        pcall(function() pawn.CharacterMovement.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 } end)
        f.acc = 0.0
        return
    end
    if not wing and not f.shot then stop(pawn, "the cap is off"); return end
    -- (a tree grabbed on the way: RT or LT held with one in reach - climb.lua takes him; "make it so I can grab the tree
    -- when blasting out of the cannon by pressing rt lt", 2026-10-16. The trigger let go first since the shot or the
    -- flight began: RT also fires the cannon)
    if not trigger_down() then f.grab_armed = true
    elseif f.grab_armed then
        local CL = package.loaded["climb"]
        local t = CL and CL.trunk_in_reach and CL.trunk_in_reach(pawn, GRAB_REACH)
        if t then
            stop(pawn, "grabbed a tree", 0.0)
            fall = nil
            CL.grab_from_air(pawn, t)
            return
        end
    end
    -- the water: in he goes (swim.lua takes him)
    local wz = ctx.water and ctx.water(x, y)
    if wz and z < wz then stop(pawn, "the water"); return end
    f.acc = math.min(f.acc + dt, 0.2)
    while f.acc >= 1.0 / 30.0 do
        f.acc = f.acc - 1.0 / 30.0
        if f.shot then
            shot_step(f)
            if wing and f.vy < 0.0 then to_flight(f) end
        else
            step(f)
        end
    end
    -- (blended between Mario 64's 30-a-second steps: his way and speed changed in steps, a judder at the game's rate)
    local a = math.min(1.0, f.acc * 30.0)
    local pitch = (f.ppitch or f.pitch) + (f.pitch - (f.ppitch or f.pitch)) * a
    local yaw = (f.pyaw or f.yaw) + s16(f.yaw - (f.pyaw or f.yaw)) * a
    local fv = (f.pfv or f.fv) + (f.fv - (f.pfv or f.fv)) * a
    local k, vx, vy, vz
    if f.shot then
        -- (a shot: its speed along the ground and up or down kept apart, as Mario 64 has them)
        local h = fv * U * 30.0
        vz = ((f.pvy or f.vy) + (f.vy - (f.pvy or f.vy)) * a) * U * 30.0
        vx, vy = -coss(yaw) * h, sins(yaw) * h
        k = math.sqrt(h * h + vz * vz)
    else
        k = fv * U * 30.0
        vx = -coss(pitch) * coss(yaw) * k
        vy = coss(pitch) * sins(yaw) * k
        vz = sins(pitch) * k
    end
    -- touching down: the ground just under him on the way down
    local fz = G and G.floor_z and G.floor_z(x, y, z + 30.0)
    if fz and vz <= 0.0 and z - fz < 25.0 then stop(pawn, "touched down", f.fv * 0.5); return end
    -- (a wall flown into - Mario 64's act_flying, AIR_STEP_HIT_WALL: a bonk, knocked back 16, and down he drops. STORROR's
    -- own movement slid him along it instead: "add wall collisions while flying so if you hit a wall you drop", 2026-10-16)
    -- (a shot's first 0.4 s free of both wall tests: leaving the cannon he passes its hole's rim and its own body, and
    -- every shot ended 0.2 s out against "a wall" with none near - "I keep hitting this wall when launching from the
    -- cannon even though its not close", 2026-10-17)
    local grace = f.shot and f.t0 and os.clock() - f.t0 < 0.4
    if G and G.wall_near and not grace then
        local hit, px, py = G.wall_near(x, y, z + 90.0, 50.0)
        local pl = math.sqrt(px * px + py * py)
        local sp = math.sqrt(vx * vx + vy * vy)
        if hit and pl > 0.001 and sp > 100.0 and (vx * px + vy * py) / (pl * sp) < -0.25 then
            sfx("en_bonk", 1.0)
            log("flight: a level wall within 50 cm ahead, %.2f s in", os.clock() - (f.t0 or os.clock()))
            stop(pawn, "a wall", -16.0)
            return
        end
    end
    local moved = true
    pcall(function()
        local cm = pawn.CharacterMovement
        if cm.MovementMode ~= 5 then cm:SetMovementMode(5, 0) end
        -- (held back hard: a wall)
        local real = pawn:GetVelocity()
        if f.last_k and f.last_k > 300.0 then
            local got = math.sqrt(real.X * real.X + real.Y * real.Y + real.Z * real.Z)
            moved = got > f.last_k * 0.35
        end
        cm.Velocity = { X = vx, Y = vy, Z = vz }
        -- (leaning into his turns: update_flying_yaw's roll, 20 x the turn's speed, eased)
        local bank = math.max(-BANK_MAX, math.min(BANK_MAX, -f.yvel * 20.0 * 360.0 / 65536.0))
        f.bank = (f.bank or 0.0) + (bank - (f.bank or 0.0)) * math.min(1.0, dt * 6.0)
        -- (his physics turned with him: nearly every bone of STORROR's athlete is simulated, pulled to the animation by
        -- springs; turned without them his limbs lagged and flailed in a turn - "when trying to move left the charater
        -- spazzes out turning into a ball", 2026-10-16)
        pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = 180.0 - yaw * 360.0 / 65536.0, Roll = f.bank }, true)
        if f.pa and f.pa:IsValid() and f.pa.RootMotionMode ~= 1 then f.pa:SetRootMotionMode(1) end
    end)
    -- (his flying pose kept: turned hard, STORROR set off its own turn-on-the-spot montage over it - he balled up and
    -- the turn stuck: "when turning too hard with wing cap the charater start balling up and then you cant turn",
    -- 2026-10-16 - any other montage stopped, and the pose put back)
    if f.pa and f.pa:IsValid() and f.arms_path then
        pcall(function()
            local cur = f.pa:GetCurrentActiveMontage()
            local mine = f.arms and f.arms:IsValid()
            if cur and cur:IsValid() and not (mine and cur:GetAddress() == f.arms:GetAddress()) then f.pa:Montage_Stop(0.0, cur) end
            if not (mine and f.pa:Montage_IsPlaying(f.arms)) then
                local seq = lib.try_load(f.arms_path)
                if seq then f.arms = f.pa:PlaySlotAnimationAsDynamicMontage(seq, FName("FullBody"), 0.1, 0.2, 1.0, 100000, -1.0, f.arms_at or 0.0) end
                if f.arms and f.arms:IsValid() then f.pa:Montage_SetPlayRate(f.arms, 0.0) end
            end
        end)
    end
    -- (and his simulated body snapped onto that pose each frame, as the King's hold does: nearly every bone of STORROR's
    -- athlete is physics pulled to the animation by springs, and in a fast turn they lagged and folded - he balled up
    -- "for seemingly no reason", 2026-10-16)
    if not f.hp_looked then
        f.hp_looked = true
        pcall(function()
            for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
                local o = c:get()
                if o:GetClass():GetFName():ToString() == "HumanPhysicsComponent" then f.hp = o end
            end
        end)
    end
    if f.hp and f.hp:IsValid() then pcall(function() f.hp:ResetBodyModifiersInSetToCachedBoneTransforms(FName("All"), 1) end) end
    f.last_k = k
    -- the camera round behind him, looking the way he flies, a little down on him
    pcall(function()
        local pc = lib.controller()
        local cr = pc:GetControlRotation()
        local want_yaw = 180.0 - yaw * 360.0 / 65536.0
        local want_pitch = -12.0 + (pitch * 360.0 / 65536.0) * 0.5
        local kk = 1.0 - math.exp(-CAM_FOLLOW * dt)
        local cy = cr.Yaw + ((((want_yaw - cr.Yaw) + 540.0) % 360.0) - 180.0) * kk
        local cpitch = (cr.Pitch > 180.0) and (cr.Pitch - 360.0) or cr.Pitch
        cpitch = cpitch + (want_pitch - cpitch) * kk
        pc:SetControlRotation({ Pitch = cpitch, Yaw = cy, Roll = 0.0 })
    end)
    -- (held back at the level's edge: a wall - at once for a shot, as Mario 64's air step makes no floor beyond)
    if G and G.edge_at and os.clock() - G.edge_at < 0.1 then
        moved = false
        if f.shot then f.blocked = math.max(f.blocked, 4) end
    end
    f.blocked = (moved or grace) and 0 or f.blocked + 1
    if f.blocked > 4 then
        sfx("en_bonk", 1.0)
        log("flight: held back 5 frames (the level's edge %s), %.2f s in", tostring(G and G.edge_at and os.clock() - G.edge_at < 0.1),
            os.clock() - (f.t0 or os.clock()))
        stop(pawn, "a wall", -16.0)
        return
    end
    -- his body along his flight: level is 90 degrees over, nose down more
    -- (out of a cannon he is laid along the shot at once, not eased over as he is into a flight)
    pcall(POSE.set, pawn, f.snap and 1.0 or dt, 90.0 - pitch * 360.0 / 65536.0, k, false, false)
    f.snap = nil
    f.relock = f.relock + dt
    if f.relock > 0.5 then
        f.relock = 0.0
        local pc = lib.controller()
        pcall(function() if not pc:IsMoveInputIgnored() then pc:SetIgnoreMoveInput(true) end; pawn:DisableInput(pc) end)  -- (the lock is a count: added to only when off, or every re-lock stayed on after - "randomly stops")
    end
    local S = package.loaded["sfx"]
    if S and S.hold then S.hold("loop_flying", math.min(1.0, 0.35 + fv / 90.0)) end
end

return M
