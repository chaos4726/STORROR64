-- Mario 64's sinking sand (mario_step.c mario_update_quicksand): SSL's quicksand, its sand pits and streams, the shallow
-- sand of THI and TTM. Stood in, his depth in it goes down - half a unit a frame standing, a quarter moving - to 10
-- (shallow), 25 (shallow and flowing), 60 (quicksand) or 100 (the deep ring of SSL's pits: Mario 64 loses him at 160 there,
-- but here only the middle of a pit is death - "if the player ends up right in the middle death", 2026-10-23); onto other
-- ground it is gone at once; in the air it stays.
-- His body is not drawn lower for it: STORROR's Physics Control simulates his pelvis, head, hands and feet, which stay up
-- however his mesh is moved in his capsule (the rest of him went down, pulled apart), and switching his body's collision
-- off to free them rebuilt them away from his pose - after a quicksand game over he floated over his feet, "he's all
-- glitched out", 2026-10-23.
-- Sucked under (ACT_QUICKSAND_DEATH: the instant kind - the edges, the moat, a pit's middle): he stops where he is, his
-- controls gone, and flails as he sinks - five of Mario's units a frame, at his height - Mario 64's "waaaooow" on the way
-- down and its sinking sound all the while, till he is under, his own height and a little; then the screen closes on him
-- as for any death (G.die). He goes down whole: his capsule touches nothing and his body passes through the ground, and
-- the whole of him is lowered, his simulated parts with it. The view stays where it was (STORROR's camera hangs off his
-- body). ("the quicksand needs to kill the player correctly getting sucked in", "its not sucking the player under the
-- surface", 2026-10-23)
local lib = require("lib")
local M = { depth = 0.0 }

local CAP = { ["10"] = 10.0, ["25"] = 25.0, ["60"] = 60.0, deep = 100.0 }

local FLAIL = "/SPP/SPPCharacter/Animation/RagdollReaction/Flail/RagdollReactionFlail_88_Drew_131024_Falling-004_1319-2578_Mirrored.RagdollReactionFlail_88_Drew_131024_Falling-004_1319-2578_Mirrored"
local SUCK_SPEED = 5.0 * 176.0 / 160.0      -- (cm a frame: Mario's 5 units at the athlete's height)
local SUCK_END = 186.0                      -- (cm: his height and 10 - under)
local YELL_AT = 0.55                        -- (of the way down: Mario 64's 100 of 180)
local CHANNELS = { 0, 1 }                   -- (ECC_WorldStatic, ECC_WorldDynamic: what his body passes through)
local death = nil   -- { pawn, addr, loc, sink, anim, rm, clip, cam, cap, resp, said, done }


local function death_undo()
    local d = death
    death = nil
    if not d then return end
    local pawn = nil
    pcall(function()
        local p = lib.pawn()
        if p and p:GetAddress() == d.addr then pawn = p end
    end)
    if pawn then
        pcall(function() pawn.CapsuleComponent:SetCollisionEnabled(d.cap or 3) end)
        pcall(function()
            for _, ch in ipairs(CHANNELS) do pawn.Mesh:SetCollisionResponseToChannel(ch, (d.resp and d.resp[ch]) or 2) end
        end)
        pcall(function() lib.controller():SetViewTargetWithBlend(pawn, 0.0, 0, 0.0, false) end)
    end
    pcall(function()
        if d.anim and d.anim:IsValid() then
            if d.clip then pcall(function() d.anim:Montage_Stop(0.1, d.clip) end) end
            if d.rm then d.anim:SetRootMotionMode(d.rm) end
        end
    end)
end

function M.sucked(pawn)
    if death or not pawn then return false end
    local G = package.loaded["game"]
    if G and G.dying then return false end
    local d = { pawn = pawn, addr = pawn:GetAddress(), said = false, sink = 0.0 }
    pcall(function() d.loc = pawn:K2_GetActorLocation() end)
    if not d.loc then return false end
    death = d
    if G and G.set_down_for_good then pcall(G.set_down_for_good, true, pawn) end
    pcall(function()
        local cm = pawn.CharacterMovement
        cm:StopMovementImmediately()
        cm:SetMovementMode(0, 0)
    end)
    -- (down through the ground, whole)
    pcall(function()
        d.cap = pawn.CapsuleComponent:GetCollisionEnabled()
        pawn.CapsuleComponent:SetCollisionEnabled(0)
    end)
    pcall(function()
        d.resp = {}
        for _, ch in ipairs(CHANNELS) do
            -- (Ignore here is footik.lua's, sunk in the sand: STORROR's own is Block)
            local r = pawn.Mesh:GetCollisionResponseToChannel(ch)
            d.resp[ch] = (r ~= 0) and r or 2
            pawn.Mesh:SetCollisionResponseToChannel(ch, 0)
        end
    end)
    -- (the struggle: STORROR's flail, its root motion off so it does not move him)
    pcall(function()
        local anim = pawn.Mesh:GetAnimInstance()
        d.anim, d.rm = anim, anim.RootMotionMode
        anim:SetRootMotionMode(1)
        local seq = lib.try_load(FLAIL)
        if seq then d.clip = anim:PlaySlotAnimationAsDynamicMontage(seq, FName("FullBody"), 0.15, 0.25, 1.0, 100000, -1.0, 0.0) end
    end)
    -- (the view held where it is)
    pcall(function()
        local pc = lib.controller()
        local pcm = pc.PlayerCameraManager
        local cam = lib.camera(lib.world(), "quicksand", pcm:GetCameraLocation(), pcm:GetCameraRotation())
        if cam then pc:SetViewTargetWithBlend(cam, 0.0, 0, 0.0, false); d.cam = cam end
    end)
    lib.log("quicksand: sucked under")
    return true
end

function M.dying() return death ~= nil end

local function death_tick(dt, pawn)
    local d = death
    if not pawn or pawn:GetAddress() ~= d.addr then death_undo(); return end
    d.sink = math.min(SUCK_END, d.sink + SUCK_SPEED * 30.0 * dt)
    -- (under the sand there is no floor under him: game.lua's keep-in-the-level put him straight back on top of it,
    -- every frame - "player still not getting sucked under the sand", 2026-10-23. Its fall checks off while he goes down.)
    local G = package.loaded["game"]
    if G then G.no_fall_until = math.max(G.no_fall_until or 0.0, os.clock() + 1.0) end
    -- (and kept so: STORROR puts its own collision back on him as he lands - a jump or a run into the sand ended with him
    -- lying on top of it, "still not getting sucked into the sand kinda just laying on top of it", 2026-10-23)
    pcall(function()
        if pawn.CapsuleComponent:GetCollisionEnabled() ~= 0 then pawn.CapsuleComponent:SetCollisionEnabled(0) end
        for _, ch in ipairs(CHANNELS) do
            if pawn.Mesh:GetCollisionResponseToChannel(ch) ~= 0 then pawn.Mesh:SetCollisionResponseToChannel(ch, 0) end
        end
    end)
    pcall(function()
        pawn:K2_SetActorLocation({ X = d.loc.X, Y = d.loc.Y, Z = d.loc.Z - d.sink }, false, {}, true)
        local cm = pawn.CharacterMovement
        if cm.MovementMode ~= 0 then cm:SetMovementMode(0, 0) end
    end)
    local S = package.loaded["sfx"]
    if S and S.hold then S.hold("loop_sink_quicksand", 1.0) end
    if not d.said and d.sink >= SUCK_END * YELL_AT then
        d.said = true
        if S and S.play then pcall(S.play, "mario_waaaooow") end         -- (as loud as MARIO FX: sfx.lua)
    end
    if not d.done and d.sink >= SUCK_END then
        d.done = true
        local G = package.loaded["game"]
        if G and G.die then pcall(G.die, "quicksand", "sucked under the quicksand") end
    end
end

-- out of the sand, or the scene going: himself again
function M.reset()
    death_undo()
    M.depth = 0.0
end

function M.forget() death_undo(); M.depth = 0.0 end

-- each tick. kind: the sinking sand under his feet ("10", "25", "60", "deep") or nil; grounded; moving. (Returns false:
-- nothing here takes him under but the instant kind, game.lua's floors - M.sucked.)
function M.update(dt, pawn, kind, grounded, moving)
    if death then death_tick(dt, pawn); return false end
    if grounded and not kind then
        M.depth = 0.0
        return false
    end
    if not grounded then return false end
    if M.depth < 1.1 then M.depth = 1.1 end
    M.depth = math.min(CAP[kind] or 60.0, M.depth + (moving and 0.25 or 0.5) * 30.0 * dt)
    if kind == "deep" then
        local S = package.loaded["sfx"]
        if S and S.hold then S.hold("loop_sink_quicksand", 0.6) end
    end
    return false
end

return M
