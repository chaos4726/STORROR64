-- SM64Map: shocked by an Amp (Mario 64's INTERACT_SHOCK, act_shocked: "Waaaooow", the buzz, Mario held lit up). The
-- user, 2026-10-17: "when hit by an amp make the charater hit the celebrate emote and free[ze] the charater. then after
-- the shock the charater ragdolls". So: held where he is - in the air too (movement mode None) - in STORROR's own
-- Celebrate emote (its action wheel's EmoteCelebrate is MontageEmote_1122, both arms up then out wide), the pose
-- stopped at arms up; SHOCK_FOR on, the pose let go and ragdoll.lua knocks him flat away from the Amp.
-- (The emote is played straight, not through STORROR's wheel - EmoteComponent:ActionWheelSelectionCallback plays it
-- only while he stands still, and he is as often hit in the air.)
local lib = require("lib")
local log = lib.log

local M = { active = false }

local CELEBRATE = "/SPP/SPPCharacter/Animation/Emote/Emote/MontageEmote_1122_LisaS_Locomotion_061024_RandomEmotes-001.MontageEmote_1122_LisaS_Locomotion_061024_RandomEmotes-001"
local HOLD_AT = 0.45                  -- s into the emote: his arms up - held there
local SHOCK_FOR = 1.2                 -- s held, then the ragdoll
local BUZZ_EVERY = 0.4
local GRACE = 2.0                     -- s after he is up again before another shock can take him
local PUSH = 150.0                    -- cm/s the ragdoll is pushed away (400 knocked him off the platform he stood on)
-- the Amp's own sparks round him while he is held ("can you add that texture around our charater as well ... when
-- getting shocked ofc", 2026-10-17): its electricity picture on quads facing the camera, round his body, each turned
-- and flickering anew every few frames
local SPARK_TEX, SPARK_HALF = "actors__amp__amp_electricity.rgba16", 42.0
local SPARKS = { { 0, 0, 70 }, { 0, 0, 25 }, { 0, 0, -25 }, { 0, 0, -70 }, { 25, 0, 40 }, { -25, 0, 0 } }

local st = nil

local function sound(name, v)
    local S = package.loaded["sfx"]
    if S and S.play then pcall(S.play, name, v or 1.0) end
end

-- e: the Amp; m: him (Mario 64 units, as enemies.lua has them). False when he cannot be shocked now.
function M.start(e, m, pawn)
    if st or M.guard or not pawn then return false end
    local HP = _G.HEALTH
    if HP and (HP.grace > 0 or HP.dead_t) then return false end
    local G = package.loaded["game"]
    if G and (G.dying or G.cutscene) then return false end
    -- (nor while nothing can touch him - a star's dance, a message up, a cannon: game.lua's G.intangible)
    if G and G.intangible and G.intangible() then return false end
    local R, B = package.loaded["ragdoll"], package.loaded["burn"]
    if R and R.active then return false end
    -- (knocked down: not shocked while he is actually limp - G.getup_at alone stays set for seconds after he is up, and a
    -- wrong treasure chest then only took its wedge: "our shock when you get a chest wrong is missing", 2026-10-18)
    if G and G.getup_at and not (R and R.limp) then return false end
    if R and R.limp and R.limp() then return false end
    if B and B.active then pcall(B.stop, true) end
    if HP and HP.damage then HP.damage(1, e.what or "an Amp") end
    -- (one voice: his "Waaaooow" - the hurt's own cry over it sounded doubled - and the buzz held for as long as the
    -- shock is, sfx.hold: loop_amp is 8 s long, and played anew every 0.4 s it piled up and buzzed on long after,
    -- "the electricute audio sounds doubled also it lasts a long ass time", 2026-10-18)
    do local S = package.loaded["sfx"]; if S and S.stop then pcall(S.stop, "mario_attacked") end end
    sound("mario_waaaooow", 1.0)
    if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
    pcall(function()
        local cm = pawn.CharacterMovement
        cm:StopMovementImmediately()
        cm:SetMovementMode(0, 0)
    end)
    local ai, mont, rm = nil, nil, nil
    pcall(function()
        ai = pawn.Mesh:GetAnimInstance()
        mont = lib.try_load(CELEBRATE)
        if ai and mont then
            rm = ai.RootMotionMode
            ai:SetRootMotionMode(1)
            ai:Montage_Play(mont, 1.0, 0, 0.0, true)
        end
    end)
    local sparks = {}
    pcall(function()
        local world = lib.world()
        local l = pawn:K2_GetActorLocation()
        for i = 1, #SPARKS do sparks[i] = lib.quad_actor(world, l, SPARK_HALF, SPARK_TEX, "alpha") end
    end)
    st = { t = 0.0, pawn = pawn, ai = ai, mont = mont, rm = rm, from = { e.x, e.z }, me = { m.x, m.z }, held = false,
           buzz = BUZZ_EVERY, sparks = sparks, spark_t = 0.0,
           -- (a treasure chest's: a short jolt, and no ragdoll after - he is under the water, in the ship)
           len = e.short and 0.8 or SHOCK_FOR, no_ragdoll = e.short }
    M.active = true
    log("shocked by %s", tostring(e.what or "an Amp"))
    return true
end

function M.tick(dt)
    -- (after a shock: none again while he is down, nor for GRACE after he is up - "make sure the amp cant attack you
    -- multiple times before you even stand up ... or after you stand up a grace period", 2026-10-17)
    local g = M.guard
    if g and not st then
        local R = package.loaded["ragdoll"]
        local G = package.loaded["game"]
        if (R and R.active) or (G and G.getup_at) then g.up = 0.0 else g.up = g.up + dt end
        if g.up >= GRACE then M.guard = nil; M.active = false end
        return
    end
    local s = st
    if not s then return end
    s.t = s.t + dt
    local pawn = s.pawn
    -- (held: no falling, no moving - STORROR would take him back otherwise)
    pcall(function() if pawn.CharacterMovement.MovementMode ~= 0 then pawn.CharacterMovement:SetMovementMode(0, 0) end end)
    if not s.held and s.t >= HOLD_AT then
        s.held = true
        pcall(function() s.ai:Montage_Pause(s.mont) end)
    end
    -- (the sparks: placed round him, to the camera, turned and flickering)
    s.spark_t = s.spark_t - dt
    local renew = s.spark_t <= 0.0
    if renew then s.spark_t = 0.05 end
    pcall(function()
        local l = pawn:K2_GetActorLocation()
        local cx, cy, cz = lib.camera_location(l)
        for i, q in ipairs(s.sparks) do
            if q and q:IsValid() then
                local o = SPARKS[i]
                local x, y, z = l.X + o[1], l.Y + o[2], l.Z + o[3]
                local dx, dy, dz = cx - x, cy - y, cz - z
                local yaw = math.deg(math.atan(dy, dx)) + 180.0
                local pitch = -math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy)))
                if renew then
                    q:SetActorHiddenInGame(math.random() < 0.3)
                    s["roll" .. i] = math.random(0, 359)
                end
                q:K2_SetActorLocationAndRotation({ X = x, Y = y, Z = z }, { Pitch = pitch, Yaw = yaw, Roll = s["roll" .. i] or 0 }, false, {}, true)
            end
        end
    end)
    do local S = package.loaded["sfx"]; if S and S.hold then pcall(S.hold, "loop_amp", 1.0) end end
    if s.t >= (s.len or SHOCK_FOR) then
        st = nil
        M.guard = { up = 0.0 }                -- (M.active stays: the guard is ticked till it ends)
        for _, q in ipairs(s.sparks or {}) do pcall(lib.destroy, q) end
        pcall(function() s.ai:Montage_Stop(0.1, s.mont) end)
        pcall(function() if s.rm then s.ai:SetRootMotionMode(s.rm) end end)
        -- (under the water - a wrong treasure chest - no ragdoll: back to his swim, the swim's own flying movement)
        local G = package.loaded["game"]
        if G and G.swim then
            pcall(function() pawn.CharacterMovement:SetMovementMode(5, 0) end)
            log("shock over: back to swimming")
            return
        end
        if s.no_ragdoll then
            pcall(function() pawn.CharacterMovement:SetMovementMode(3, 0) end)
            log("shock over: let go")
            return
        end
        pcall(function() pawn.CharacterMovement:SetMovementMode(3, 0) end)
        -- (knocked away from the Amp: Mario 64's x, z -> the scene's -z, x)
        local dx, dz = s.me[1] - s.from[1], s.me[2] - s.from[2]
        local R = package.loaded["ragdoll"]
        if R and R.start then pcall(R.start, -dz, dx, PUSH) end
        log("shock over: knocked flat")
    end
end

-- a change of scene: let him go as he is
function M.forget()
    local s = st
    st = nil
    M.active = false
    M.guard = nil
    if s then
        for _, q in ipairs(s.sparks or {}) do pcall(lib.destroy, q) end
        pcall(function() s.pawn.CharacterMovement:SetMovementMode(3, 0) end)
    end
end

return M
