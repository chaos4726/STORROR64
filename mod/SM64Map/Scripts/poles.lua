-- Poles and trees to climb (Mario 64: interact_pole, act_holding_pole / act_climbing_pole / act_grab_pole_* in
-- mario_actions_automatic.c; pole.inc.c, ddd_pole.inc.c). Every pole the levels place (bhvPoleGrabbing: most are the
-- level's own drawn poles, the object only the part to hold; WF's giant pole and DDD's sliding poles with models of
-- their own, drawn here) and every tree. Jumped into, the athlete takes hold where he meets it; the stick pushed up
-- climbs (Mario: stickY / 8 a frame), pulled down slides him down it turning round it, across turns him round it,
-- and the jump button kicks him off it backwards (ACT_WALL_KICK_AIR). He holds on only up to 100 below its top, lets
-- go at its foot or on the ground. Held: the engine's flying mode, STORROR's controls off, STORROR's bar hang (as
-- hoot.lua). Their tops' hidden 1-ups (macro_hidden_1up_in_pole) are game.lua's hidden 1-ups with their two marks on
-- the pole. DDD's poles are there only once the second key is had (or the upstairs door opened), as in Mario 64.
-- (Mario 64's handstand on a pole's top is not done: the athlete has none.) Mario 64 units, 30 frames a second.
-- (No pole could be climbed, and those two kinds were not drawn, 2026-10-15.)
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET
local M = {}

local U = 0.75
local LOCK = "SM64Pole"
local HANG_ANIM = "/SPP/SPPCharacter/Animation/MotionMatching/Swing/MotionMatchingSwing_171_Swings_31_08_24-001_979-5438.MotionMatchingSwing_171_Swings_31_08_24-001_979-5438"
local OFF = 34.0                -- cm from the pole's middle to his
local REACH = 117.0             -- across, his middle to the pole's (Mario's 37 + the pole's 80)
local TREE_H = 500.0            -- (bhvTree's hitbox)
local TOP = 180.0               -- he holds on up to this far below its top (Mario: 100 - Mario is smaller: hands at the top)
local KICK_UP, KICK_ON = 1000.0, 540.0     -- cm/s off a pole (Mario 64: 62 up - 3.6 m with STORROR's gravity - and 24 on)

local st = nil                  -- { world, ctx, poles, on, ... }
local fall = nil

local function sfx(name, v) local S = package.loaded["sfx"]; if S then pcall(S.play, name, v) end end
local function sins(a) return math.sin(a * math.pi / 32768.0) end
local function coss(a) return math.cos(a * math.pi / 32768.0) end
local function s16(a) a = math.floor(a) % 65536; if a >= 32768 then a = a - 65536 end; return a end

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

-- the jump button, the stick (x right, y up: -1..1)
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
    local function key(n)
        local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(n) }) end)
        return ok and v
    end
    if key("D") or key("Right") then x = 1.0 elseif key("A") or key("Left") then x = -1.0 end
    if key("W") or key("Up") then y = 1.0 elseif key("S") or key("Down") then y = -1.0 end
    return x, y
end

-- ------------------------------------------------------------ setting up
-- Bowser in the Fire Sea's sinking cages each bring a blue pole up through their middle: bhvBitFSSinkingCagePlatform's
-- SPAWN_CHILD(MODEL_BITFS_BLUE_POLE, bhvDDDMovingPole) - 80 round, 710 high, put where its cage is every frame
-- (bhv_ddd_moving_pole_loop). Made by the cage, not in the level's own list of things, it was missing ("no pole here",
-- 2026-10-24): one for each cage of the scene (G.data, its platforms - Mario 64 units), for this file and climb.lua.
-- (made longer than Mario 64's 710 on 2026-10-25 - "make this pole longer", "a little longer" - then back to it the same
-- day: "return to original size". model_h, its own height: a pole made other than it is drawn out to it)
M.CAGE_POLE_H = 710.0
function M.cage_poles()
    local out = {}
    local G = package.loaded["game"]
    for _, o in ipairs((G and G.data and G.data.objects) or {}) do
        if o.kind == "platform" and o.bhv == "bitfs_cage" and o.pos then
            local cx, cy, cz = o.pos[1], o.pos[2], o.pos[3]
            out[#out + 1] = { kind = "pole", type = "bhvDDDMovingPole", pos = { -cz * U, cx * U, cy * U }, sm64 = { cx, cy, cz },
                              height = M.CAGE_POLE_H, model_h = 710.0, down = 0.0, model = "geo_bitfs_geo_0006A8", cage = { cx, cz } }
        end
    end
    return out
end

-- its cage (platforms.lua's, found by its home), for where it is now - looked for in the platforms as they are each
-- time, not kept: the one kept was the cage of the scene before it was made again in place (the same home, never
-- moved again), and the poles stood still while their cages rose and sank - "pole not attached to moving platform",
-- 2026-11-07
local function cage_of(p)
    local PL = package.loaded["platforms"]
    for _, c in ipairs((PL and PL.list) or {}) do
        if c.hx == p.cage[1] and c.hz == p.cage[2] then p.plat = c; return c end
    end
    p.plat = nil
    return nil
end

function M.load(world, objects, ctx)
    M.clear()
    local poles = {}
    local all = {}
    for _, o in ipairs(objects or {}) do all[#all + 1] = o end
    for _, o in ipairs(M.cage_poles()) do all[#all + 1] = o end
    objects = all
    for _, o in ipairs(objects or {}) do
        if o.kind == "pole" and o.sm64 then
            local ok = true
            if o.type == "bhvDDDPole" then
                -- (bhv_ddd_pole_init: SAVE_FLAG_HAVE_KEY_2 | SAVE_FLAG_UNLOCKED_UPSTAIRS_DOOR)
                local MN = _G.MENU
                ok = MN and MN.has_star and (MN.has_star("key:2") or MN.has_flag and MN.has_flag("upstairs_open")) or false
                -- (and in the act that needs them, "Pole-Jumping for Red Coins" (act 3), key or no key - Bowser's sub gone
                -- then too, platforms.lua B.gone_key2: "levels missing the moving poles", "still no moving poles in this
                -- level", 2026-10-23)
                local G = package.loaded["game"]
                if G and G.act == 3 then ok = true end
            end
            if ok then
                local p = { x = o.sm64[1], y = o.sm64[2], z = o.sm64[3], h = o.height or 1000.0, down = o.down or 0.0,
                            hx = o.sm64[1], hz = o.sm64[3], yaw = s16((o.yaw or 0) * 65536.0 / 360.0), travel = o.travel,
                            off = 0.0, vel = 10.0, t = 0, tree = false, cage = o.cage,
                            -- (a still pole is climb.lua's - STORROR's way - when it is there; only DDD's moving ones
                            -- are climbed here)
                            -- (DDD's moving ones too since 2026-10-23: climb.lua's trunks ride them, M.moving -
                            -- "moving poles dont have our tree poles in them"; here they are only moved and drawn)
                            native = package.loaded["climb"] ~= nil }
                if o.model then
                    local data = ctx.actor_data(o.model)
                    p.inst = data and lib.make_instance(world, data, { X = o.pos[1] + OFFSET.X, Y = o.pos[2] + OFFSET.Y, Z = o.pos[3] + OFFSET.Z },
                                                          -(o.yaw or 0), 1.0)
                    if p.inst then p.inst.moves = p.travel ~= nil or p.cage ~= nil end
                    if p.inst and o.model_h and o.height and o.height ~= o.model_h then
                        local k = o.height / o.model_h
                        p.zs = k
                        pcall(function() p.inst.actor:SetActorScale3D({ X = 1.0, Y = 1.0, Z = k }) end)
                    end
                end
                if o.ball then
                    -- (bhv_giant_pole_loop: a yellow ball on top, hitboxHeight + 50 up)
                    local data = ctx.actor_data(o.ball)
                    local bz = o.pos[3] + (p.h + 50.0) * U
                    p.ball = data and lib.make_instance(world, data, { X = o.pos[1] + OFFSET.X, Y = o.pos[2] + OFFSET.Y, Z = bz + OFFSET.Z }, 0.0, 1.0)
                end
                poles[#poles + 1] = p
            end
        elseif o.kind == "tree" and o.pos and not package.loaded["climb"] then
            poles[#poles + 1] = { x = o.pos[2] / U, y = o.pos[3] / U, z = -o.pos[1] / U, h = TREE_H, down = 0.0, tree = true }
        end
    end
    if #poles == 0 then return end
    st = { world = world:GetAddress(), ctx = ctx, poles = poles, acc = 0.0, cool = 0.0 }
    log("poles: %d to climb", #poles)
end

-- The cages' poles where they are now, for climb.lua's trunks on them: { hx, hz (their homes, Mario 64 units), sz (the
-- pole's foot now, scene cm) }
function M.lifts()
    local out = {}
    if not st then return out end
    for _, p in ipairs(st.poles) do
        if p.cage then out[#out + 1] = { hx = p.cage[1], hz = p.cage[2], sz = p.y * U } end
    end
    return out
end

-- DDD's moving poles where they are now, for climb.lua's trunks on them: { hx, hz (their homes, Mario 64 units),
-- sx, sy (now, scene cm) }
function M.moving()
    local out = {}
    if not st then return out end
    for _, p in ipairs(st.poles) do
        if p.travel then out[#out + 1] = { hx = p.hx, hz = p.hz, sx = -p.z * U, sy = p.x * U } end
    end
    return out
end

function M.clear()
    local s = st
    st = nil
    if not s then return end
    if s.on then
        local pawn = lib.pawn()
        if pawn then
            hold(s.on, pawn, false)
            pcall(function() pawn.CharacterMovement:SetMovementMode(3, 0) end)
            local G = package.loaded["game"]
            if G then G.carried = nil; if G.parkour_reset then pcall(G.parkour_reset, pawn) end end
        end
    end
    local w = lib.world()
    if w and w:GetAddress() == s.world then
        for _, p in ipairs(s.poles) do
            if p.inst then lib.destroy(p.inst.actor) end
            if p.ball then lib.destroy(p.ball.actor) end
        end
    end
end

function M.forget()
    if st and st.on then local G = package.loaded["game"]; if G then G.carried = nil end end
    st, fall = nil, nil
end

function M.active() return st ~= nil and st.on ~= nil end

-- ------------------------------------------------------------ on a pole
local function let_go(s, pawn, why, kick)
    local h = s.on
    s.on, s.cool = nil, 0.5
    hold(h, pawn, false)
    local G = package.loaded["game"]
    pcall(function()
        local cm = pawn.CharacterMovement
        cm:SetMovementMode(3, 0)
        if kick then
            -- (ACT_WALL_KICK_AIR: turned about, up and away from it)
            local r = math.rad(h.around)
            cm.Velocity = { X = math.cos(r) * KICK_ON, Y = math.sin(r) * KICK_ON, Z = KICK_UP }
            pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = h.around, Roll = 0.0 }, false)
        else
            cm.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
        end
    end)
    if G then
        G.carried = nil
        if G.parkour_reset then pcall(G.parkour_reset, pawn) end
    end
    fall = { softened = false, t = 0.0 }
    if kick then sfx("mario_hoo") end                   -- (as loud as MARIO FX: sfx.lua)
    log("pole: off (%s)", why)
end

local function grab(s, p, pawn, mx, my, mz)
    -- (interact_pole: in the air; his height on it kept; facing it)
    local G = package.loaded["game"]
    local h = { p = p, pos = math.max(-p.down, math.min(my - p.y, p.h - TOP)), yawvel = 0, climb_t = 0.0 }
    local dx, dz = mx - p.x, mz - p.z
    -- his place round it (scene degrees, from the pole out to him) and his facing (back toward it)
    local sx, sy = -dz, dx
    h.around = math.deg(math.atan(sy, sx))
    s.on = h
    hold(h, pawn, true)
    if G then G.carried = "pole"; G.air = false end
    fall = nil
    sfx("mario_whoa")
    log("pole: hold on (%s, %.0f up of %.0f)", p.tree and "tree" or "pole", h.pos, p.h)
end

-- one Mario 64 frame on it
local function climb_step(s, pawn, x, y)
    local h = s.on
    local p = h.p
    local sy, sx = y * 64.0, x * 64.0
    local top = p.h - TOP
    if sy > 16.0 and h.pos < top - 0.4 then
        h.pos = math.min(top, h.pos + sy / 8.0)
        h.yawvel = 0
        h.climbing = true
    elseif sy < -16.0 then
        -- (sliding down it, turning round it: oMarioPoleYawVel)
        h.yawvel = math.min(0x1000, h.yawvel - sy * 2)
        h.around = h.around - h.yawvel * 360.0 / 65536.0
        h.pos = h.pos - h.yawvel / 0x100
        h.climbing = false
        h.sliding = true
    else
        h.yawvel = 0
        h.around = h.around + sx * 16.0 * 360.0 / 65536.0
        h.climbing = false
    end
    if sy >= -16.0 then h.sliding = false end
end

local function step_ddd(p)
    -- (bhv_ddd_pole_update: 10 a frame out to its full travel and back, resting 20 frames at each end)
    p.t = p.t + 1
    if p.t > 20 then
        p.off = p.off + p.vel
        if p.off <= 0.0 or p.off >= p.travel then
            p.off = math.max(0.0, math.min(p.travel, p.off))
            p.vel, p.t = -p.vel, 0
        end
    end
    p.x, p.z = p.hx + coss(p.yaw) * p.off, p.hz + sins(p.yaw) * p.off      -- (obj_set_dist_from_home: x by cos, z by sin)
end

-- (x, y, z): the athlete's feet, scene cm (minus OFFSET)
function M.update(dt, pawn, x, y, z)
    -- the drop after letting go: soft landing just above the floor
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
    local mx, my, mz = y / U, z / U, -x / U
    local sx, sy = stick()
    local a = a_down()
    local pressed = a and not s.was_a
    s.was_a = a
    s.cool = math.max(0.0, s.cool - dt)
    s.acc = math.min(s.acc + dt, 0.2)
    while s.acc >= 1.0 / 30.0 do
        s.acc = s.acc - 1.0 / 30.0
        for _, p in ipairs(s.poles) do if p.travel then step_ddd(p) end end
        if s.on then climb_step(s, pawn, sx, sy) end
    end
    local cx, cy
    for _, p in ipairs(s.poles) do
        if p.cage then
            local q = cage_of(p)
            if q then p.y = q.y end
        end
        if p.inst and (p.travel or p.cage) then lib.set_pose(p.inst, -p.z * U + OFFSET.X, p.x * U + OFFSET.Y, p.y * U + OFFSET.Z, -(p.yaw * 360.0 / 65536.0)) end
        -- (its picture drawn out to its height, looked at again now and then: set as the scene was made, it did not hold -
        -- the drawn pole stayed Mario 64's 710 and he stood in the air over it, "floating on air when climbing this
        -- pole", 2026-10-25)
        if p.zs and p.inst then
            p.zs_t = (p.zs_t or 0) - 1
            if p.zs_t <= 0 then
                p.zs_t = 30
                pcall(function()
                    if math.abs(p.inst.actor:GetActorScale3D().Z - p.zs) > 0.01 then p.inst.actor:SetActorScale3D({ X = 1.0, Y = 1.0, Z = p.zs }) end
                end)
            end
        end
        if p.ball then
            -- (the ball is a sprite turned to the camera - bhvYellowBall's BILLBOARD: its face is -x)
            if not cx then
                local c = nil
                pcall(function() c = lib.controller().PlayerCameraManager:GetCameraLocation() end)
                cx, cy = c and c.X, c and c.Y
            end
            if cx then
                local bx, by = -p.z * U + OFFSET.X, p.x * U + OFFSET.Y
                local yaw = math.deg(math.atan(cy - by, cx - bx)) + 180.0
                pcall(function() p.ball.actor:K2_SetActorRotation({ Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false) end)
            end
        end
    end
    if not s.on then
        if s.cool > 0.0 or (G and (G.carried or G.swim or G.cutscene or G.warping or G.pending)) then return end
        local air = false
        pcall(function() air = pawn.CharacterMovement:IsFalling() end)
        if not air then return end
        -- jumped into one: his middle within reach across, his body over its foot and under its top
        local mid = my + 120.0
        for _, p in ipairs(s.poles) do
            local dx, dz = mx - p.x, mz - p.z
            if not p.native and dx * dx + dz * dz < REACH * REACH and mid > p.y - p.down and my < p.y + p.h - 60.0 then
                grab(s, p, pawn, mx, my, mz)
                break
            end
        end
        return
    end
    -- held: kicked off, at its foot, on the ground
    local h = s.on
    local p = h.p
    if pressed then let_go(s, pawn, "kick", true); return end
    if G and (G.warping or G.pending or G.dying) then let_go(s, pawn, "leaving", false); return end
    if h.pos < -p.down then let_go(s, pawn, "its foot", false); return end
    local r = math.rad(h.around)
    local px, py = -p.z * U + math.cos(r) * OFF, p.x * U + math.sin(r) * OFF
    local feet = (p.y + h.pos) * U
    local fz = G and G.floor_z and G.floor_z(px, py, feet + 40.0)
    if fz and feet < fz + 2.0 and h.sliding then
        let_go(s, pawn, "the ground", false)
        return
    end
    if fz and feet < fz then feet = fz; h.pos = fz / U - p.y end
    h.face = h.around + 180.0
    pcall(function()
        -- (TeleportTo every tick: the calls that hand back a hit result have brought this game down when made so often)
        pawn:K2_TeleportTo({ X = px + OFFSET.X, Y = py + OFFSET.Y, Z = feet + (G and G.half or 90.0) + OFFSET.Z },
                           { Pitch = 0.0, Yaw = h.face, Roll = 0.0 })
        local cm = pawn.CharacterMovement
        if cm.MovementMode ~= 5 then cm:SetMovementMode(5, 0) end
        cm.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
        if h.pa and h.pa:IsValid() and h.pa.RootMotionMode ~= 1 then h.pa:SetRootMotionMode(1) end
    end)
    -- his controls kept off (a message closing gives them back)
    h.relock = (h.relock or 0.0) + dt
    if h.relock > 0.5 then
        h.relock = 0.0
        local pc = lib.controller()
        pcall(function() if not pc:IsMoveInputIgnored() then pc:SetIgnoreMoveInput(true) end; pawn:DisableInput(pc) end)  -- (the lock is a count: added to only when off, or every re-lock stayed on after - "randomly stops")
    end
    -- sounds: a pull up every half second climbing, the slide while sliding
    if h.climbing then
        h.climb_t = h.climb_t - dt
        if h.climb_t <= 0.0 then h.climb_t = 0.45; sfx(p.tree and "climb_up_tree" or "climb_up_pole", 0.8) end
    else
        h.climb_t = 0.0
    end
    if h.sliding then
        local S = package.loaded["sfx"]
        if S and S.hold then S.hold(p.tree and "loop_slide_down_tree" or "loop_slide_down_pole", 0.7) end
    end
end

return M
