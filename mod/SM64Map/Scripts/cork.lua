-- The running cork (2026-10-15: "just take the code from a cork that pushes the player forward and play it when the
-- charater runs and does the cork"). Running, STORROR picks a cork take that never takes off (2664, 5962...) and he
-- stops dead - why was never found (storror-cork notes). Its animation is kept (swapping in another one, STORROR
-- stopped it and left him flying, walking on air); its motion is the good cork's: his run kept through the wind-up,
-- at its take-off a launch of 483 up (STORROR's own Cork_127) on at his run's speed, root motion off in the air, one
-- arc to the ground. Then by how it lands:
--   the flip clearly unfinished: STORROR's ragdoll ("if the animation doesnt finish make the charater ragdoll");
--   down from high: STORROR's cat landing ("its the one where he hits the ground from a high height");
--   B with it (STORROR's roll): its landing roll instead ("if the players pressing b it should roll out instead of
--     the cat landing");
--   down from really high without B: the ragdoll ("if the landing is really high up and theres no rollout it should
--     ragdol the player").
-- Corks from standing are STORROR's own, left alone. After any cork, never left flying with nothing playing.
local lib = require("lib")
local log = lib.log
local M = {}

local cur = nil                 -- the cork under way: { name, takeoff, landing, ours, on, launched, ... }

local IDLE = 100.0              -- cm/s: slower than this at its start, a cork from standing (STORROR's, left alone)
local MIN_ON, MAX_ON = 400.0, 650.0     -- cm/s on through the air: his run's speed, kept to these
local UP = 483.0                -- cm/s up at the take-off: STORROR's own Cork_127 (gravity here is 1500: ~78 cm up)
local FAIL_EARLY = 0.15         -- s: down with more than this of the flip left (to its Landing notify): failed
local TAKEOFF = { ["2664"] = 0.333, ["3823"] = 0.300, ["4140"] = 0.267, ["5962"] = 0.533 }   -- (the takes' TakeOff notifies)
local LANDING = { ["2664"] = 1.233, ["3823"] = 1.200, ["4140"] = 1.167, ["5962"] = 1.233 }   -- (their Landing notifies: the flip done)
-- down from high - more than HIGH_DROP under the top of his flight: STORROR's own landing from high (read off his real
-- 5 m drop - its cat landing). The bare sequences here: their montages have a "Reset" warp window, which dragged him
-- off elsewhere before.
local HIGH_DROP = 250.0
local CAT = "/SPP/SPPCharacter/Animation/Landing/CatLanding/LandingCatLanding_5168_ROLLS_POP_UP.LandingCatLanding_5168_ROLLS_POP_UP"
-- B held as he lands from high, pressed just before, or early in the cat landing: STORROR's landing roll (the shortest
-- take: a quick roll out of the run)
local ROLL = "/SPP/SPPCharacter/Animation/Landing/Rolling/LandingRolling_7381_ROLLS_POP_UP.LandingRolling_7381_ROLLS_POP_UP"
local ROLL_BEFORE = 0.3         -- s: B pressed this long before the landing still counts
local ROLL_INTO = 0.35          -- s: B pressed this far into the cat landing still turns it into the roll
-- down from REALLY high without B: the ragdoll. (STORROR's cat landing came on a 5 m drop by itself; this is two storeys.)
local RAGDOLL_DROP = 700.0

local function b_down()
    local ok, d = pcall(function() return lib.controller():IsInputKeyDown({ KeyName = FName("Gamepad_FaceButton_Right") }) end)
    return ok and d
end

local function play_seq(ai, path)
    local sq = lib.try_load(path)
    if not (sq and sq:IsValid()) then return nil end
    pcall(function() ai.RootMotionMode = 2 end)
    local ok, m = pcall(function() return ai:PlaySlotAnimationAsDynamicMontage(sq, FName("FullBody"), 0.1, 0.25, 1.0, 1, -1.0, 0.0) end)
    return ok and m or nil
end

-- STORROR's ragdoll, him going on the way he was going, nothing up (the knock's shove, a third of it up, threw him a
-- metre back into the air: "make the ragdols make sense")
local function bail(v)
    v = v or { X = 0.0, Y = 0.0 }
    local R = package.loaded["ragdoll"]
    local ok = R and R.start and R.start(v.X, v.Y, math.max(250.0, math.sqrt(v.X * v.X + v.Y * v.Y)))
    pcall(function()
        local rs = R.state and R.state()
        if rs and rs.push then rs.push = { X = v.X * 0.9, Y = v.Y * 0.9, Z = 0.0 } end
    end)
    return ok
end

function M.update(dt, p)
    if not p then return end
    local ai = p.Mesh:GetAnimInstance()
    local cm = p.CharacterMovement
    local m, name, pos = nil, "", 0.0
    pcall(function() m = ai:GetCurrentActiveMontage(); if m and m:IsValid() then name = m:GetFName():ToString(); pos = ai:Montage_GetPosition(m) end end)
    local take = name:match("^MontageFlipCork_(%d+)_")
    local c = cur
    local now = os.clock()
    if take and TAKEOFF[take] and not (c and c.name == name and pos >= (c.last_pos or 0) - 0.05) then
        local v = cm.Velocity
        local v0 = math.sqrt(v.X * v.X + v.Y * v.Y)
        c = { name = name, t0 = now, takeoff = TAKEOFF[take], landing = LANDING[take], m = m,
              ours = v0 >= IDLE and cm.MovementMode == 5, on = math.max(MIN_ON, math.min(MAX_ON, v0)), launched = false }
        cur = c
        if c.ours then log("cork: running cork %s at %.0f cm/s", take, v0) end
    end
    if not c then return end
    if take then c.last_pos = pos; c.seen = now end
    if c.ours and not c.launched and take then
        local yaw = math.rad(p:K2_GetActorRotation().Yaw)
        ai.RootMotionMode = 1
        if pos >= c.takeoff then
            -- (the flip at its own speed - "no dont play it 1.35x faster make it 1 again")
            c.launched = true
            pcall(function() cm:SetMovementMode(3, 0) end)
            c.vx, c.vy = math.cos(yaw) * c.on, math.sin(yaw) * c.on
            cm.Velocity = { X = c.vx, Y = c.vy, Z = UP }
        elseif cm.MovementMode == 5 then
            cm.Velocity = { X = math.cos(yaw) * c.on, Y = math.sin(yaw) * c.on, Z = 0.0 }
        end
    end
    -- (launched: falling till he is down - STORROR put him back to flying once, and with no gravity there he rose on
    -- and on: "hes getting some extreme height")
    if c.ours and c.launched and cm.MovementMode == 5 then
        local v = cm.Velocity
        pcall(function() cm:SetMovementMode(3, 0) end)
        cm.Velocity = { X = v.X, Y = v.Y, Z = math.min(v.Z, UP) }
    end
    if c.launched and cm.MovementMode == 3 then
        c.flying = true
        -- (one arc from launch to touchdown: his way on held as launched, gravity the rest - when the cork's clip
        -- ended in the air STORROR's air control and drag bent it: "you can tell it ends because his trajectory
        -- changes slightly")
        local v = cm.Velocity
        if c.ours and c.vx then cm.Velocity = { X = c.vx, Y = c.vy, Z = math.min(v.Z, UP) }
        elseif v.Z > UP + 1.0 then cm.Velocity = { X = v.X, Y = v.Y, Z = UP } end
        c.v_air = cm.Velocity
        if b_down() then c.b_at = now end
        local z = p:K2_GetActorLocation().Z
        if not c.zmax or z > c.zmax then c.zmax = z end
    end
    -- down
    if c.flying and cm.MovementMode ~= 3 and cm.MovementMode ~= 5 then
        c.flying = false
        pcall(function() ai.RootMotionMode = 2 end)
        local short = c.landing - (c.last_pos or 0.0)
        local first = not c.touched
        c.touched = true
        if first and short > FAIL_EARLY and cm.MovementMode == 1 then
            local ok = bail(c.v_air)
            log("cork: down %.2f s before the flip was done - %s", short, ok and "ragdoll" or "(no ragdoll)")
        else
            local drop = (c.zmax or 0.0) - p:K2_GetActorLocation().Z
            if c.high then
                -- (down again straight after - off the edge he came down on: the one landing already played)
            elseif drop > HIGH_DROP and (b_down() or (c.b_at and now - c.b_at <= ROLL_BEFORE)) then
                c.high = { rolled = true }
                play_seq(ai, ROLL)
                log("cork: down from %.0f cm with B - rolled out", drop)
            elseif drop > RAGDOLL_DROP then
                c.high = { rolled = true }
                local ok = bail(c.v_air)
                log("cork: down from %.0f cm, no B - %s", drop, ok and "ragdoll" or "(no ragdoll)")
            elseif drop > HIGH_DROP then
                c.high = { t = now, m = play_seq(ai, CAT), b_was = b_down() }
                log("cork: down from %.0f cm - STORROR's cat landing", drop)
            end
        end
        c.ours = false
    end
    -- B early in the cat landing: the roll takes over
    local h = c.high
    if h and not h.rolled and h.t and now - h.t <= ROLL_INTO then
        local b = b_down()
        if b and not h.b_was then
            h.rolled = true
            pcall(function() if h.m and h.m:IsValid() then ai:Montage_Stop(0.1, h.m) end end)
            play_seq(ai, ROLL)
            log("cork: B %.2f s into the cat landing - rolled out", now - h.t)
        end
        h.b_was = b
    end
    -- (never left flying with nothing playing after a cork - he walked on air)
    if not take and cm.MovementMode == 5 and now - (c.seen or c.t0) > 0.1 then
        local C = package.loaded["climb"]
        if not (C and C.active and C.active()) then
            pcall(function() cm:SetMovementMode(3, 0) end)
            pcall(function() ai.RootMotionMode = 2 end)
            log("cork: left flying after a cork - put to falling")
        end
    end
    if now - (c.seen or c.t0) > 2.5 then
        if c.ours then pcall(function() ai.RootMotionMode = 2 end) end
        cur = nil
    end
end

-- the scene going (or him gone): nothing carried over
function M.clear()
    local c = cur
    cur = nil
    if c and c.ours then
        local p = lib.pawn()
        pcall(function() p.Mesh:GetAnimInstance().RootMotionMode = 2 end)
    end
end

function M.forget() cur = nil end

return M
