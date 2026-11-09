-- Hanging from the mesh ceilings Mario can hang from (SURFACE_HANGABLE: BoB, the castle grounds, HMC, SSL, THI, TTM,
-- WMOTR, BitFS. mario_step.c AIR_STEP_GRABBED_CEILING; act_start_hanging / act_hanging / act_hang_moving): his head
-- meeting one on the way up, the jump button held, he takes hold of it and hangs from it; the stick moves him along
-- under it (update_hang_moving: up to 4 a frame, toward the stick's way - the camera's), the button let go drops him,
-- and so does reaching its edge (HANG_LEFT_CEIL). Hung in the engine's flying mode with STORROR's controls off and
-- STORROR's bar hang, as hoot.lua and poles.lua hang him. Mario 64 units at its 30 frames a second.
-- (Those ceilings were plain ceilings, 2026-10-15.)
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET
local M = {}

local U = 0.75
local LOCK = "SM64Hang"
local HANG_ANIM = "/SPP/SPPCharacter/Animation/MotionMatching/Swing/MotionMatchingSwing_171_Swings_31_08_24-001_979-5438.MotionMatchingSwing_171_Swings_31_08_24-001_979-5438"
local HANDS = 185.0             -- cm from his feet up to his hands, hanging (his middle 90, the bar hang's hands 95 over it)
local REACH = 40.0              -- cm his hands may be short of the ceiling as he jumps into it
local SPEED = 4.0               -- Mario units a frame along it

local st = nil                  -- { ctx, world, on, cool, was_a }
local fall = nil

local function sfx(name, v) local S = package.loaded["sfx"]; if S then pcall(S.play, name, v) end end

local function components(pawn, fn)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            pcall(fn, o, o:GetClass():GetFName():ToString())
        end
    end)
end

local function hold(h, pawn, on)
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
            h.pa, h.root_motion = anim, anim.RootMotionMode
            anim:SetRootMotionMode(1)
            local seq = lib.try_load(HANG_ANIM)
            if seq then h.hang = anim:PlaySlotAnimationAsDynamicMontage(seq, FName("FullBody"), 0.15, 0.2, 1.0, 100000, -1.0, 0.0) end
        end)
        pcall(function() cm:SetMovementMode(5, 0); cm:StopMovementImmediately() end)
    else
        pcall(function()
            if h.pa and h.pa:IsValid() then
                if h.hang and h.hang:IsValid() then h.pa:Montage_Stop(0.2, h.hang) end
                h.pa:SetRootMotionMode(h.root_motion or 2)
            end
        end)
        h.pa, h.hang = nil, nil
    end
end

local function a_down()
    if M.test then return M.test.a and true or false end
    local P = package.loaded["pad"]
    return P and P.down and P.down("ok") or false
end
local function stick()
    if M.test then return M.test.x or 0.0, M.test.y or 0.0 end
    local pc = lib.controller()
    local x, y = 0.0, 0.0
    pcall(function()
        x = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftX") })
        y = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftY") })
    end)
    if type(x) ~= "number" then x = 0.0 end
    if type(y) ~= "number" then y = 0.0 end
    if math.abs(x) < 0.2 then x = 0.0 end
    if math.abs(y) < 0.2 then y = 0.0 end
    local function key(n)
        local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(n) }) end)
        return ok and v
    end
    if key("D") or key("Right") then x = 1.0 elseif key("A") or key("Left") then x = -1.0 end
    if key("W") or key("Up") then y = 1.0 elseif key("S") or key("Down") then y = -1.0 end
    return x, y
end

-- ctx.ceiling(x, y, zmin): the hangable ceiling's height (scene cm) over (x, y) at or above zmin, or nil
function M.load(world, ctx)
    M.clear()
    if not (ctx and ctx.ceiling) then return end
    st = { ctx = ctx, world = world:GetAddress(), cool = 0.0 }
end

local function let_go(s, pawn, why)
    local h = s.on
    s.on, s.cool = nil, 0.4
    hold(h, pawn, false)
    pcall(function() pawn.CharacterMovement:SetMovementMode(3, 0); pawn.CharacterMovement.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 } end)
    local G = package.loaded["game"]
    if G then
        G.carried = nil
        if G.parkour_reset then pcall(G.parkour_reset, pawn) end
    end
    fall = { softened = false, t = 0.0 }
    log("hang: let go (%s)", why)
end

function M.clear()
    local s = st
    st = nil
    if s and s.on then
        local pawn = lib.pawn()
        if pawn then
            hold(s.on, pawn, false)
            pcall(function() pawn.CharacterMovement:SetMovementMode(3, 0) end)
            local G = package.loaded["game"]
            if G then G.carried = nil; if G.parkour_reset then pcall(G.parkour_reset, pawn) end end
        end
    end
end

function M.forget()
    if st and st.on then local G = package.loaded["game"]; if G then G.carried = nil end end
    st, fall = nil, nil
end

-- (x, y, z): his feet, scene cm (minus OFFSET)
function M.update(dt, pawn, x, y, z)
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
        if fall and fall.t > 20.0 then fall = nil end
    end
    local s = st
    if not s or not pawn then return end
    local w = lib.world()
    if not (w and w:GetAddress() == s.world) then st = nil; return end
    local G = package.loaded["game"]
    local a = a_down()
    s.cool = math.max(0.0, s.cool - dt)
    if not s.on then
        if not a or s.cool > 0.0 or (G and (G.carried or G.swim or G.cutscene or G.warping or G.pending)) then return end
        local up, air = false, false
        pcall(function()
            local cm = pawn.CharacterMovement
            air = cm:IsFalling()
            up = cm.Velocity.Z > -50.0
        end)
        if not (air and up) then return end
        local hands = z + HANDS
        local cz = s.ctx.ceiling(x, y, z + 100.0)
        if cz and hands >= cz - REACH and hands <= cz + 60.0 then
            local h = { cz = cz, yaw = 0.0, v = 0.0, relock = 0.0 }
            pcall(function() h.yaw = pawn:K2_GetActorRotation().Yaw end)
            s.on = h
            hold(h, pawn, true)
            if G then G.carried = "hang"; G.air = false end
            fall = nil
            sfx("mario_whoa", 0.8)
            log("hang: took hold of the ceiling at %.0f", cz / U)
        end
        return
    end
    local h = s.on
    if not a then let_go(s, pawn, "button"); return end
    if G and (G.warping or G.pending or G.dying) then let_go(s, pawn, "leaving"); return end
    -- along under it, toward the stick's way (the camera's)
    local sx, sy = stick()
    local nx, ny = x, y
    if sx ~= 0.0 or sy ~= 0.0 then
        local cyaw = 0.0
        pcall(function() cyaw = lib.controller():GetControlRotation().Yaw end)
        local want = cyaw + math.deg(math.atan(sx, sy))
        local d = ((want - h.yaw + 540.0) % 360.0) - 180.0
        local turn = 11.25 * 30.0 * dt                  -- (0x800 a frame)
        h.yaw = h.yaw + math.max(-turn, math.min(turn, d))
        h.v = math.min(SPEED, h.v + 1.0 * 30.0 * dt)
        local step = h.v * 30.0 * dt * U * math.min(1.0, math.sqrt(sx * sx + sy * sy))
        nx, ny = x + math.cos(math.rad(h.yaw)) * step, y + math.sin(math.rad(h.yaw)) * step
    else
        h.v = 0.0
    end
    local cz = s.ctx.ceiling(nx, ny, z + 100.0)
    if not cz then
        if nx ~= x or ny ~= y then
            -- (HANG_LEFT_CEIL: off its edge - he drops)
            let_go(s, pawn, "its edge")
            return
        end
        cz = h.cz
    end
    h.cz = cz
    local feet = cz - HANDS
    pcall(function()
        -- (TeleportTo every tick: the calls that hand back a hit result have brought this game down when made so often)
        pawn:K2_TeleportTo({ X = nx + OFFSET.X, Y = ny + OFFSET.Y, Z = feet + (G and G.half or 90.0) + OFFSET.Z },
                           { Pitch = 0.0, Yaw = h.yaw, Roll = 0.0 })
        local cm = pawn.CharacterMovement
        if cm.MovementMode ~= 5 then cm:SetMovementMode(5, 0) end
        cm.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
        if h.pa and h.pa:IsValid() and h.pa.RootMotionMode ~= 1 then h.pa:SetRootMotionMode(1) end
    end)
    h.relock = h.relock + dt
    if h.relock > 0.5 then
        h.relock = 0.0
        local pc = lib.controller()
        pcall(function() if not pc:IsMoveInputIgnored() then pc:SetIgnoreMoveInput(true) end; pawn:DisableInput(pc) end)  -- (the lock is a count: added to only when off, or every re-lock stayed on after - "randomly stops")
    end
end

return M
