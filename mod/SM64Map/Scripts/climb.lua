-- Climbing trees and poles, STORROR's way (2026-10-15: "lets start tree climbing from scratch", "no dont use mario 64
-- mechanics", then step by step on a white test pole). Each tree and each still pole of the level gets an invisible
-- trunk 8 cm across (STORROR takes anything upright up to 40 cm across as a pole: its own pole slide grabs it) and a
-- top: a disc 70 cm round on a tree, a square 24 cm across on a pole. Once STORROR's pole slide has him, the mod holds
-- him on it (flying mode, root motion off, his stick locked, his trick buttons live), in STORROR's pole-slide pose:
--   stick up climbs (the slide played backwards), across goes round, down slides (the mod's own slide - STORROR's ran
--   him to the foot whatever the stick did; down counts only after the stick has rested in the middle, or letting go
--   of up read as down), let go holds; at the top STORROR's ledge grab (its wall grab, held at its catch), his hands
--   put on a pole's square edge by arm IK on footik's drawn copy of him; up again: STORROR's climb-up (its bare
--   sequence - its montage's warp windows dragged him to other trees - with its own lift, scaled to the top), handed
--   back standing in its middle; down from the hang syncs him back onto the pole.
--   Jump: STORROR's Pole 180 - the push and the half turn and the launch the mod's (its own turn was fought by
--   STORROR's stored facing), STORROR's fall started at take-off so it keeps his new facing.
-- Things learnt the hard way (and kept): his body parts are physics-simulated on channel 17 - the trunks ignore it
-- (his hands struck the pole at the kick off: ragdoll); never leave a "Reset" warp target behind; never leave him in
-- flying mode after (no gravity, no friction: "mach 10"); STORROR's pole slide has root motion ignored (mode 1) -
-- set it back yourself. DDD's moving poles stay poles.lua's.
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET
local M = { enabled = true }

local U = 0.75
local st = nil                  -- this scene's: { world, trunks = { { x, y, z, h, actor, square, stand, tree } } }
local TC = {}                   -- the climb under way and what follows it
local CLIMB = 140.0         -- cm/s at full stick
local SLIDE = 350.0         -- cm/s down the pole at full stick
local ROUND = 120.0         -- deg/s round the trunk at full stick
local TOP_GAP = 87.0        -- his middle this far under the tree's top when he hangs from it: feet 173 under it, what the
                            -- climb-up lifts (hands at the top of the leaves)
local CLIMB_UP_SEQ = "/SPP/SPPCharacter/Animation/Climb/ClimbUp/ClimbClimbUp_5750_TobyKT02.ClimbClimbUp_5750_TobyKT02"
local UP_END = 1.45         -- s: the clip's lift (173 cm) is done; after it, it steps back off
                            -- (ClimbingHeightFromLedge 176; its climb-up lifts him 2.6 m from there)
local UP_KXY = 0.23         -- the climb-up's forward motion (~1.5 m) cut to the 0.34 m to the top's middle
local LOCK = "SM64Tree"
local CLIMB_UP = "/SPP/SPPCharacter/Animation/Climb/ClimbUp/MontageClimbClimbUp_5750_TobyKT02.MontageClimbClimbUp_5750_TobyKT02"
local GRAB = "/SPP/SPPCharacter/Animation/ClimbGrab/Wall/MontageClimbGrabWall_12131_toby-routine01-003.MontageClimbGrabWall_12131_toby-routine01-003"
local GRAB_FROM = 0.15      -- s into STORROR's ledge grab: past its jump up (he is already there), hands going up
local GRAB_CATCH = 0.33     -- s: its Landing - he has caught the top (it blends out from here): held there to hang
local HANG_MIN = 0.4        -- s hanging before he pulls himself up, even with the stick held up
local DYNO = "/SPP/SPPCharacter/Animation/Dyno/PoleDyno180/MontageDynoPoleDyno180_383_TobyClimbing_030325_ArmJump-001.MontageDynoPoleDyno180_383_TobyClimbing_030325_ArmJump-001"
local DYNO_SEQ = "/SPP/SPPCharacter/Animation/Dyno/PoleDyno180/DynoPoleDyno180_383_TobyClimbing_030325_ArmJump-001.DynoPoleDyno180_383_TobyClimbing_030325_ArmJump-001"
local TAKEOFF = 0.29        -- s into STORROR's Pole 180: where its own falls into flight
local OUT_V, UP_V = 520.0, 450.0    -- cm/s at take-off: straight away from the pole, and up
local PUSH_UP = 45.0        -- cm up the pole in the push before take-off (the clip's own push)
-- the climb-up's rise through the clip (measured: its own root motion, by montage position), as a share of the whole;
-- he is moved along it by the mod, root motion off - anything the clip's motion could be warped to is out of it
-- (cm up by montage position: MontageClimbClimbUp_5750's own root motion, measured in game 2026-10-15 20:33)
local UP_RISE = { { 0.0, 0.0 }, { 0.02, 3 }, { 0.07, 11 }, { 0.12, 19 }, { 0.16, 25 }, { 0.22, 45 }, { 0.26, 66 }, { 0.31, 86 },
    { 0.36, 103 }, { 0.41, 119 }, { 0.46, 133 }, { 0.51, 144 }, { 0.56, 152 }, { 0.61, 159 }, { 0.66, 166 }, { 0.72, 174 },
    { 0.77, 180 }, { 0.82, 187 }, { 0.86, 194 }, { 0.92, 203 }, { 0.97, 210 }, { 1.02, 218 }, { 1.06, 224 }, { 1.11, 230 },
    { 1.16, 234 }, { 1.21, 238 }, { 1.26, 242 }, { 1.31, 245 }, { 1.36, 249 }, { 1.41, 252 }, { 1.46, 254 } }
local UP_IN_FROM, UP_IN_TO = 0.3, 1.3       -- s of the clip over which he goes in, over the edge to the top's middle
local function curve(t, pts)
    if t <= pts[1][1] then return pts[1][2] end
    for i = 2, #pts do
        if t <= pts[i][1] then
            local a, b = pts[i - 1], pts[i]
            return a[2] + (b[2] - a[2]) * (t - a[1]) / (b[1] - a[1])
        end
    end
    return pts[#pts][2]
end
M.HIP_AT = 22.0            -- cm from a moving pole's middle to his hips while he holds it (below)
local NEAR = 34.0           -- cm from the trunk's middle to his: where STORROR's own slide keeps him
M.CATCH = 90.0              -- cm: another trunk this near his middle in a jump off one is grabbed (climb's jump_tick)
M.REACH = 150.0             -- cm: STORROR's pole slide on something this near a trunk's middle is on that trunk
local PULL = 8.0            -- 1/s: how fast he is drawn in to it
local function axis(name)
    local pc = lib.controller()
    local v = 0.0
    pcall(function() v = pc:GetInputAnalogKeyState({ KeyName = FName(name) }) end)
    return v
end
local function key(name)
    local d = false
    pcall(function() d = lib.controller():IsInputKeyDown({ KeyName = FName(name) }) end)
    return d
end
local function stick()
    local x, y = axis("Gamepad_LeftX"), axis("Gamepad_LeftY")
    if key("W") then y = 1.0 elseif key("S") then y = -1.0 end
    if key("D") then x = 1.0 elseif key("A") then x = -1.0 end
    return x, y
end
-- (on a trunk while someone speaks - Hoot, woken at the top of his tree - nothing he presses moves him or lets him go:
-- the A that turns the pages jumped him off, "make sure you cant leave the tree until the dialog ends", 2026-10-17;
-- and after it, till A and the stick are let go - the press that shut it)
local hush = false
local function jump_raw() return key("Gamepad_FaceButton_Bottom") or key("SpaceBar") end
local function jump_down() return (not hush) and jump_raw() end
local function nearest_trunk(l)
    if not st then return nil end
    local best, bd = nil, 1e9
    for _, t in ipairs(st.trunks) do
        local d = math.sqrt((t.x - l.X) ^ 2 + (t.y - l.Y) ^ 2)
        if d < bd and l.Z > t.z - 100.0 and l.Z < t.z + t.h + 150.0 then best, bd = t, d end
    end
    return best, bd
end
local function lock(pawn, on)
    local pc = lib.controller()
    pcall(function()
        if on then if not TC.locked then pc:SetIgnoreMoveInput(true) end
        elseif TC.locked then pc:SetIgnoreMoveInput(false) end
    end)
    TC.locked = on
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetClass():GetFName():ToString() == "LocomotionComponent" then
                o:EnableLocomotionInputCallback(FName(LOCK), not on)
                o:EnableAdvancedLocomotionInput(FName(LOCK), not on)
            end
        end
    end)
end
-- ------------------------------------------------------------ his hands on the top's edge (arm IK on footik's copy)
local WORLD = 0
local sqrt = math.sqrt
local function v3(x, y, z) return { x, y, z } end
local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
local function mul(a, k) return { a[1] * k, a[2] * k, a[3] * k } end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
local function len(a) return sqrt(dot(a, a)) end
local function norm(a) local l = len(a); if l < 1e-6 then return nil end; return mul(a, 1.0 / l) end
local function between(a, b)
    local w = 1.0 + dot(a, b)
    local c
    if w < 1e-6 then w = 0.0; c = math.abs(a[1]) > math.abs(a[3]) and { -a[2], a[1], 0.0 } or { 0.0, -a[3], a[2] }
    else c = cross(a, b) end
    local l = sqrt(c[1] * c[1] + c[2] * c[2] + c[3] * c[3] + w * w)
    return { c[1] / l, c[2] / l, c[3] / l, w / l }
end
local function qmul(a, b)
    return { a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2],
             a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
             a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4],
             a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3] }
end
local function qrot(q, p)
    local u = { q[1], q[2], q[3] }
    local t = mul(cross(u, p), 2.0)
    return add(add(p, mul(t, q[4])), cross(u, t))
end
local function bone(pose, name)
    local t = pose:GetBoneTransformByName(FName(name), WORLD)
    return { p = v3(t.Translation.X, t.Translation.Y, t.Translation.Z), q = { t.Rotation.X, t.Rotation.Y, t.Rotation.Z, t.Rotation.W },
             s = v3(t.Scale3D.X, t.Scale3D.Y, t.Scale3D.Z) }
end
local function set_rot(pose, name, b, q)
    pose:SetBoneTransformByName(FName(name), { Rotation = { X = q[1], Y = q[2], Z = q[3], W = q[4] },
        Translation = { X = b.p[1], Y = b.p[2], Z = b.p[3] }, Scale3D = { X = b.s[1], Y = b.s[2], Z = b.s[3] } }, WORLD)
end
-- one arm: its finger root (middle_01) brought to `target`, `w` of the way; the elbow bends the way it does now, the
-- hand keeps its turn in the world
local function arm_ik(pose, side, target, w)
    local U, L, Hn, F = "upperarm_" .. side, "lowerarm_" .. side, "hand_" .. side, "middle_01_" .. side
    local up, lo, ha, fi = bone(pose, U), bone(pose, L), bone(pose, Hn), bone(pose, F)
    local T = sub(target, sub(fi.p, ha.p))
    T = add(ha.p, mul(sub(T, ha.p), w))
    local S, E, A = up.p, lo.p, ha.p
    local l1, l2 = len(sub(E, S)), len(sub(A, E))
    local st_ = sub(T, S)
    local d, u = len(st_), norm(st_)
    if not u or l1 < 1.0 or l2 < 1.0 then return end
    d = math.max(math.abs(l1 - l2) + 0.5, math.min(l1 + l2 - 0.3, d))
    local es = sub(E, S)
    local b = norm(sub(es, mul(u, dot(es, u)))) or { 0.0, 0.0, -1.0 }
    local ca = (l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d)
    ca = math.max(-1.0, math.min(1.0, ca))
    local sa = sqrt(1.0 - ca * ca)
    local E2 = add(S, add(mul(u, l1 * ca), mul(b, l1 * sa)))
    local A2 = add(S, mul(u, d))
    local q1 = between(norm(es), norm(sub(E2, S)))
    set_rot(pose, U, up, qmul(q1, up.q))
    local ea = qrot(q1, sub(A, E))
    local q2 = between(norm(ea), norm(sub(A2, E2)) or norm(ea))
    set_rot(pose, L, bone(pose, L), qmul(q2, qmul(q1, lo.q)))
    set_rot(pose, Hn, bone(pose, Hn), ha.q)
end
-- one leg: its foot brought to `target`, `w` of the way; the knee bends the way it does now (a straight leg forward)
local function leg_ik(pose, side, target, w, fwd)
    local Tn, Cn, Fn = "thigh_" .. side, "calf_" .. side, "foot_" .. side
    local th, ca, ft = bone(pose, Tn), bone(pose, Cn), bone(pose, Fn)
    local H, K, A = th.p, ca.p, ft.p
    local T = add(A, mul(sub(target, A), w))
    local l1, l2 = len(sub(K, H)), len(sub(A, K))
    local ht = sub(T, H)
    local d, u = len(ht), norm(ht)
    if not u or l1 < 1.0 or l2 < 1.0 then return end
    d = math.max(math.abs(l1 - l2) + 0.5, math.min(l1 + l2 - 0.3, d))
    local kh = sub(K, H)
    local b = sub(kh, mul(u, dot(kh, u)))
    if len(b) < 0.5 then b = sub(fwd, mul(u, dot(fwd, u))) end
    b = norm(b) or { 1.0, 0.0, 0.0 }
    local ca_ = (l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d)
    ca_ = math.max(-1.0, math.min(1.0, ca_))
    local sa = sqrt(1.0 - ca_ * ca_)
    local K2 = add(H, add(mul(u, l1 * ca_), mul(b, l1 * sa)))
    local A2 = add(H, mul(u, d))
    local q1 = between(norm(kh), norm(sub(K2, H)))
    set_rot(pose, Tn, th, qmul(q1, th.q))
    local ka = qrot(q1, sub(A, K))
    local q2 = between(norm(ka), norm(sub(A2, K2)) or norm(ka))
    set_rot(pose, Cn, bone(pose, Cn), qmul(q2, qmul(q1, ca.q)))
    set_rot(pose, Fn, bone(pose, Fn), ft.q)
end
-- Climbing up a trunk, hand over hand ("next add a climbing animation", 2026-10-16 - STORROR has no pole climb; it
-- was its pole slide played backwards). On STORROR's slide pose, held still: each stroke one hand lets go, reaches up
-- past the other and takes hold again, with the opposite foot stepping up the trunk, while the other hand and foot
-- hold where they are on it; his body goes up in a pull, quickest mid-stroke, still as hands change. Strokes take
-- turns: right hand + left foot, then left hand + right foot. The stick sets how fast the strokes go.
local STROKE = 40.0         -- cm up the trunk a stroke
local REACH_OUT = 7.0       -- cm a moving hand or foot comes off the trunk on its way up
local IK_IN = 0.15          -- s to blend the climb's limbs in or out
local function stroke_pos(phi)        -- (how far up his body is, in strokes: still at each change of hands)
    local k = math.floor(phi)
    local f = phi - k
    return k + f - math.sin(2.0 * math.pi * f) / (2.0 * math.pi)
end
-- each limb's way up and out from where STORROR's slide pose has it, at climb phase `phi`
local function limb_moves(phi)
    local k = math.floor(phi)
    local f = phi - k
    local e = f - math.sin(2.0 * math.pi * f) / (2.0 * math.pi)
    local hold = STROKE / 2.0 - STROKE * e                  -- (still on the trunk while his body goes up past it)
    local m = math.max(0.0, math.min(1.0, (f - 0.1) / 0.8))
    m = m * m * (3.0 - 2.0 * m)
    local move = -STROKE / 2.0 + STROKE * m                 -- (off, up past, and on again)
    local out = REACH_OUT * math.sin(math.pi * m)
    if k % 2 == 0 then
        return { hand_r = { move, out }, hand_l = { hold, 0.0 }, foot_l = { move, out }, foot_r = { hold, 0.0 } }
    end
    return { hand_r = { hold, 0.0 }, hand_l = { move, out }, foot_l = { hold, 0.0 }, foot_r = { move, out } }
end
local function climb_limbs(h, w)
    if w <= 0.001 then return end
    local F = package.loaded["footik"]
    local fs = F and F.debug and F.debug()
    if not (fs and fs.on and fs.pose) then return end
    local a = math.rad(h.ang)
    local n = { math.cos(a), math.sin(a), 0.0 }             -- (from the trunk out to him)
    local fwd = { -n[1], -n[2], 0.0 }                       -- (he faces the trunk)
    local mv = limb_moves(h.phi or 0.0)
    pcall(function()
        for _, side in ipairs({ "r", "l" }) do
            local o = mv["hand_" .. side]
            local fi = bone(fs.pose, "middle_01_" .. side)
            arm_ik(fs.pose, side, add(fi.p, { n[1] * o[2], n[2] * o[2], o[1] }), w)
        end
        for _, side in ipairs({ "l", "r" }) do
            local o = mv["foot_" .. side]
            local ft = bone(fs.pose, "foot_" .. side)
            leg_ik(fs.pose, side, add(ft.p, { n[1] * o[2], n[2] * o[2], o[1] }), w, fwd)
        end
    end)
end
local DOWN_T = 0.35         -- s from hanging off the top back onto the pole
local DOWN_DZ = 30.0        -- cm down the pole meanwhile
local HAND_GAP = 7.0        -- cm each side of the edge's middle
local HAND_IN = 3.0         -- cm in from the edge, onto the top: fingers over it
local function hands_on_edge(h, w)
    if w <= 0.001 then return end
    local F = package.loaded["footik"]
    local fs = F and F.debug and F.debug()
    if not (fs and fs.on and fs.pose) then return end
    local sq = h.t.square
    if not sq then return end
    local a = math.rad(h.ang)
    local n = { math.cos(a), math.sin(a) }                  -- (from the pole out to him)
    local r = { n[2], -n[1] }                               -- (his right: he faces -n)
    local e = { h.t.x + n[1] * (sq - HAND_IN), h.t.y + n[2] * (sq - HAND_IN), h.t.z + h.t.h + 2.0 }
    pcall(function()
        arm_ik(fs.pose, "r", { e[1] + r[1] * HAND_GAP, e[2] + r[2] * HAND_GAP, e[3] }, w)
        arm_ik(fs.pose, "l", { e[1] - r[1] * HAND_GAP, e[2] - r[2] * HAND_GAP, e[3] }, w)
    end)
end
local function ignore_tree(pawn, h, on)
    if not (h and h.t and h.t.actor) then return end
    if not on then
        -- (clear of the tree's top before it counts again: his head may be up in it)
        pcall(function()
            local l = pawn:K2_GetActorLocation()
            local half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
            local topz = h.t.z + h.t.h
            local dx, dy = l.X - h.t.x, l.Y - h.t.y
            local n = math.sqrt(dx * dx + dy * dy)
            local clear = (h.t.stand or 70.0) + 17.0
            if l.Z + half > topz - 2.0 and l.Z - half < topz + 2.0 and n < clear then
                if n < 0.5 then dx, dy, n = 1.0, 0.0, 1.0 end
                pawn:K2_SetActorLocation({ X = h.t.x + dx / n * clear, Y = h.t.y + dy / n * clear, Z = l.Z }, false, {}, true)
            end
        end)
    end
    pcall(function() pawn.CapsuleComponent:IgnoreActorWhenMoving(h.t.actor, on) end)
    -- (the pole as drawn: off while he is on it, back once he is clear of it - M.update)
    if h.t.drawn then
        if on then pcall(function() h.t.drawn:SetCollisionEnabled(0) end); h.t.drawn_off = true end
    end
end
-- Round a trunk (3 m and more round it, from its foot to 6 m over its top): ground, as far as game.lua's edge
-- of the level is concerned (a spike's foot stands where the level has no floor under it)
function M.near_trunk(x, y, z)
    if not st then return false end
    for _, t in ipairs(st.trunks) do
        -- (3 m round at least, up to 6 m over the top: a spike's foot is wider than its drawn top, and jumped off,
        -- he hit the edge of the level - "hit an invisable wall when jumping off the spike", 2026-10-18)
        local r = math.max(t.wide or 0.0, t.stand or 0.0, 150.0) + 150.0
        if (x - t.x) ^ 2 + (y - t.y) ^ 2 < r * r and z > t.z - 200.0 and z < t.z + t.h + 600.0 then return true end
    end
    return false
end
-- (each frame: a drawn pole left off solid again once he is clear of it, and not on it)
local function drawn_back(l)
    for _, t in ipairs(st.trunks) do
        if t.drawn_off and not (TC.on and TC.on.t == t) then
            if (l.X - t.x) ^ 2 + (l.Y - t.y) ^ 2 > (t.wide + 45.0) ^ 2 then
                t.drawn_off = nil
                pcall(function() t.drawn:SetCollisionEnabled(1) end)
            end
        end
    end
end
local function carried_off()
    local G = package.loaded["game"]
    if G and G.carried == "pole" then G.carried = nil end
end
-- On DDD's moving poles his body is drawn on the pole by moving his mesh inside his capsule (lx, ly: cm, the capsule's
-- own frame - forward, right; nil: back where it was). The capsule stays on his side of the pole: put round the far
-- side instead, so his hips came onto the pole, the camera that follows it looked through the pole - "camera and audio
-- bugging out when on pole", 2026-10-23.
local function mesh_shift(pawn, lx, ly)
    local m = pawn.Mesh
    if lx == nil then
        -- (across only: its height is STORROR's own)
        local b = TC.mbase
        if b then pcall(function() m:K2_SetRelativeLocation({ X = b.X, Y = b.Y, Z = m.RelativeLocation.Z }, false, {}, true) end) end
        TC.mbase, TC.mshift = nil, nil
        return
    end
    if not TC.mbase then
        local r = m.RelativeLocation
        TC.mbase = { X = r.X, Y = r.Y, Z = r.Z }
    end
    local b = TC.mbase
    TC.mshift = { lx, ly }
    pcall(function() m:K2_SetRelativeLocation({ X = b.X + lx, Y = b.Y + ly, Z = m.RelativeLocation.Z }, false, {}, true) end)
end
local function let_go(pawn, why)
    local h = TC.on
    TC.on = nil
    carried_off()
    pcall(mesh_shift, pawn)
    ignore_tree(pawn, h, false)
    lock(pawn, false)
    pcall(function() pawn.Mesh:GetAnimInstance().RootMotionMode = 2 end)
    pcall(function() pawn.CharacterMovement:SetMovementMode(3, 0) end)
    TC.cool = 0.25          -- (STORROR's slide takes him back first, if it will)
    TC.watch_until = os.clock() + 3.0
    log("climb: let go (%s) at %.0f cm up", why, h.z - h.t.z)
end
local function take(pawn, t, l)
    local ai = pawn.Mesh:GetAnimInstance()
    local m = ai:GetCurrentActiveMontage()
    local h = { t = t, z = l.Z, d = math.sqrt((l.X - t.x) ^ 2 + (l.Y - t.y) ^ 2),
                ang = math.deg(math.atan(l.Y - t.y, l.X - t.x)), rm = ai.RootMotionMode, jump_was = jump_down() }
    if m and m:IsValid() then h.montage = m; h.mpos = ai:Montage_GetPosition(m) end
    TC.on = h
    local G = package.loaded["game"]
    if G then G.carried = "pole" end
    ignore_tree(pawn, h, true)
    lock(pawn, true)
    ai.RootMotionMode = 1
    pawn.CharacterMovement:SetMovementMode(5, 0)
    pawn.CharacterMovement.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
    log("climb: holding on (%.0f cm from the middle, %.0f up, montage %s at %.2f)", h.d, h.z - t.z,
        h.montage and h.montage:GetFName():ToString():sub(1, 30) or "-", h.mpos or -1)
end
-- Grabbed out of the air by the mod: a cannon shot or a Wing Cap flight, RT or LT held with a trunk in reach
-- (flight.lua; "make it so I can grab the tree when blasting out of the cannon by pressing rt lt", 2026-10-16 -
-- STORROR's own pole grab is off while it flies him). Put at the trunk, facing it, in STORROR's pole slide as its own
-- grab would have him, then held as when its slide catches one.
local POLE_SLIDE = "/SPP/SPPCharacter/Animation/Falling/Slide_Pole/MontageFallingSlide_Pole_74_slides_31_08_24-004.MontageFallingSlide_Pole_74_slides_31_08_24-004"
local POLE_SLIDE_AT = 0.6       -- s into it: hands on, the grab's reach over
function M.trunk_in_reach(pawn, reach)
    if not (M.enabled and st and pawn) or TC.on then return nil end
    local w = lib.world()
    if not (w and w:GetAddress() == st.world) then return nil end
    local t, d = nearest_trunk(pawn:K2_GetActorLocation())
    if t and d <= (reach or 150.0) then return t end
    return nil
end
function M.grab_from_air(pawn, t)
    if not (t and pawn) or TC.on then return false end
    local l = pawn:K2_GetActorLocation()
    local a = math.atan(l.Y - t.y, l.X - t.x)
    local z = math.max(t.z + 100.0, math.min(t.z + t.h - TOP_GAP, l.Z))
    pcall(function()
        pawn:K2_SetActorLocation({ X = t.x + math.cos(a) * NEAR, Y = t.y + math.sin(a) * NEAR, Z = z }, false, {}, true)
        pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = math.deg(a) + 180.0, Roll = 0.0 }, true)
    end)
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        local m = lib.try_load(POLE_SLIDE)
        if m and m:IsValid() then
            ai:Montage_Play(m, 1.0, 0, POLE_SLIDE_AT, true)
            ai:Montage_SetPlayRate(m, 0.0)
        end
    end)
    local ok, err = pcall(take, pawn, t, pawn:K2_GetActorLocation())
    if not ok then log("climb: grab from the air failed (%s)", tostring(err)); return false end
    log("climb: grabbed from the air")
    return true
end
-- on top: STORROR's own ledge climb-up (its "Reset" warp aimed at the middle of the tree's top)
local function start_up(pawn, h)
    -- (the clip's own sequence, played as a dynamic montage: STORROR's montage of it has motion-warping windows, and
    -- those dragged him to another tree - 32 m in a test; the bare sequence has none and lifts him straight up)
    local m = lib.try_load(CLIMB_UP_SEQ)
    if not (m and m:IsValid()) then return false end
    local ai = pawn.Mesh:GetAnimInstance()
    if h.montage then pcall(function() ai:Montage_Stop(0.1, h.montage) end) end
    ai.RootMotionMode = 3               -- (its own lift; the way in to the top's middle is the mod's)
    local top = h.t.z + h.t.h + 1.0
    local mw = nil
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetClass():GetFName():ToString() == "MotionWarpingComponent" then mw = o end
        end
    end)
    if mw then
        pcall(function() mw:RemoveWarpTarget(FName("Reset")) end)
        pcall(function() mw:Deactivate() end)
        pcall(function() mw:SetComponentTickEnabled(false) end)
    end
    -- (the tree's top overhangs him: his body passes through the tree while he goes over it)
    pcall(function() pawn.CapsuleComponent:IgnoreActorWhenMoving(h.t.actor, true) end)
    m = ai:PlaySlotAnimationAsDynamicMontage(m, FName("FullBody"), 0.15, 0.25, 1.0, 1, -1.0, 0.0)
    if not (m and m:IsValid()) then return false end
    local l0 = pawn:K2_GetActorLocation()
    local half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
    -- (its lift - 180 cm by 1.45 s - scaled to end with his feet just on the top, wherever his hands put him)
    h.up = { m = m, t0 = os.clock(), top = top, z0 = l0.Z, trace = {}, mw = mw, x0 = l0.X, y0 = l0.Y,
             zs = l0.Z, r = 0.0, kz = (top + half + 1.0 - l0.Z) / 180.0 }
    log("climb: climbing up on top")
    return true
end
-- at the top: STORROR's ledge grab - he takes hold of the tree's top and hangs from it
local function start_grab(pawn, h)
    local m = lib.try_load(GRAB)
    if not (m and m:IsValid()) then return false end
    local ai = pawn.Mesh:GetAnimInstance()
    if h.montage then pcall(function() ai:Montage_Stop(0.1, h.montage) end) end
    ai.RootMotionMode = 1               -- (he stays where he is: the grab's own jump up is not wanted)
    ai:Montage_Play(m, 1.0, 0, GRAB_FROM, true)
    h.grab = { m = m, t0 = os.clock() }
    log("climb: took hold of the top")
    return true
end
-- the kick off: STORROR's Pole 180 as STORROR plays it - its bare sequence (its montage's warp window would drag him
-- off), its own motion (the push off and the half turn), flying mode till its take-off, then falling with a launch
-- up while the clip carries him on. STORROR's pole-slide state is cleared at take-off (it landed him as off a pole
-- slide) and again near the ground (a long drop is its fall ragdoll). "the kickoff from the pole its rather buggy"
local function start_jump(pawn, h)
    local seq = lib.try_load(DYNO_SEQ)
    if not (seq and seq:IsValid()) then return false end
    local ai = pawn.Mesh:GetAnimInstance()
    if h.montage then pcall(function() ai:Montage_Stop(0.1, h.montage) end) end
    local m = ai:PlaySlotAnimationAsDynamicMontage(seq, FName("FullBody"), 0.1, 0.25, 1.0, 1, -1.0, 0.0)
    if not (m and m:IsValid()) then return false end
    -- (its look only: root motion off. Its own turn was fought by STORROR's stored facing - sometimes the full half
    -- turn, sometimes 5 deg: "sometimes he doesnt jump off the pole in the correct direction", "sometimes its a limp
    -- kick off". The push, the half turn and the launch are the mod's, the same every time.)
    ai.RootMotionMode = 1
    local l = pawn:K2_GetActorLocation()
    h.jump = { m = m, seq = seq, t0 = os.clock(), x0 = l.X, y0 = l.Y, z0 = l.Z, yaw0 = h.ang + 180.0, trace = {} }
    -- (on DDD's moving poles: the push goes with the pole, and his capsule - held by his hips, on the pole's far side -
    -- comes round to NEAR out on the side he jumps to by take-off: launched from the far side he went into the pole
    -- and off it any way, "when jumping off a pole it doesnt go in the correct direction", 2026-10-23)
    if h.t.mover then
        local a = math.rad(h.ang)
        h.jump.mv = { rx = l.X - h.t.x, ry = l.Y - h.t.y, tx = math.cos(a) * NEAR, ty = math.sin(a) * NEAR }
    end
    log("climb: jumping off (STORROR's Pole 180)")
    return true
end
local function jump_tick(pawn, h)
    local j = h.jump
    local cm = pawn.CharacterMovement
    local ai = pawn.Mesh:GetAnimInstance()
    local el = os.clock() - j.t0
    local G = package.loaded["game"]
    if not j.off then
        -- the push: up the pole, turning round to face away from it
        if cm.MovementMode ~= 5 then pcall(function() cm:SetMovementMode(5, 0) end) end
        local k = math.min(1.0, el / TAKEOFF)
        local e = k * k * (3.0 - 2.0 * k)
        cm.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
        local px, py = j.x0, j.y0
        if TC.mshift then
            j.ms0 = j.ms0 or { TC.mshift[1], TC.mshift[2] }
            pcall(mesh_shift, pawn, j.ms0[1] * (1.0 - e), j.ms0[2] * (1.0 - e))
        end
        if j.mv then
            px = h.t.x + j.mv.rx + (j.mv.tx - j.mv.rx) * e
            py = h.t.y + j.mv.ry + (j.mv.ty - j.mv.ry) * e
        end
        pcall(function()
            pawn:K2_SetActorLocation({ X = px, Y = py, Z = j.z0 + PUSH_UP * e }, false, {}, true)
            pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = j.yaw0 + 180.0 * e, Roll = 0.0 }, false)
        end)
        if el >= TAKEOFF then
            j.off = true
            -- (a moving pole stays out of his way till the jump is over: it went on into him)
            if not j.mv then ignore_tree(pawn, h, false) end
            lock(pawn, false)
            -- take-off: facing away, STORROR's own fall started from here (so it keeps this facing - a reset first:
            -- it ignores a fall start while it thinks he is on the pole), the clip back on, the launch the mod's
            local a = math.rad(h.ang)
            pcall(function() pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = h.ang, Roll = 0.0 }, false) end)
            if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
            local pk = nil
            pcall(function()
                for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
                    local o = c:get()
                    if o:GetClass():GetFName():ToString() == "ParkourComponent" then pk = o end
                end
            end)
            local fell = pk and pcall(function() pk:StartFallingCallback() end)
            if not fell then pcall(function() cm:SetMovementMode(3, 0) end) end
            pcall(function()
                j.m = ai:PlaySlotAnimationAsDynamicMontage(j.seq, FName("FullBody"), 0.05, 0.25, 1.0, 1, -1.0, TAKEOFF)
            end)
            ai.RootMotionMode = 1
            cm.Velocity = { X = math.cos(a) * OUT_V, Y = math.sin(a) * OUT_V, Z = UP_V }
        end
        return
    end
    -- (STORROR's bail - its ragdoll, movement off - set off at the kick off: undone at once, and the jump goes on the way
    -- it was launched. Left to it he was thrown off at any angle and fell limp through the water to its bottom - "when
    -- jumping off a pole it doesnt go in the correct direction", 2026-10-23)
    if el < TAKEOFF + 1.2 and (j.unbail or 0) < 3 then
        local bail = cm.MovementMode == 0
        pcall(function()
            local mt = ai:GetCurrentActiveMontage()
            if mt ~= nil and mt:IsValid() and mt:GetFName():ToString():find("Ragdoll") then bail = true end
        end)
        if bail then
            j.unbail = (j.unbail or 0) + 1
            local RAG = package.loaded["ragdoll"]
            if RAG and RAG.up_now then pcall(RAG.up_now, true) end
            if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
            local a = math.rad(h.ang)
            pcall(function() cm:SetMovementMode(3, 0) end)
            cm.Velocity = { X = math.cos(a) * OUT_V, Y = math.sin(a) * OUT_V, Z = UP_V - 1500.0 * (el - TAKEOFF) }
            pcall(function() pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = h.ang, Roll = 0.0 }, false) end)
            log("climb: STORROR's bail in the jump undone (%.2f s after take-off)", el - TAKEOFF)
        end
    end
    -- (near the ground on the way down: STORROR's fall forgotten, no ragdoll for the drop)
    if not j.reset_low then
        pcall(function()
            local l = pawn:K2_GetActorLocation()
            local half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
            local fz = G and G.floor_z and G.floor_z(l.X - lib.OFFSET.X, l.Y - lib.OFFSET.Y, l.Z - lib.OFFSET.Z)
            if cm.Velocity.Z < 0 and fz and (l.Z - lib.OFFSET.Z - half) - fz < 120.0 then
                j.reset_low = true
                G.parkour_reset(pawn)
            end
        end)
    end
    -- (another pole or tree reached in the jump: grabbed, as Mario 64's Mario takes the next pole out of the air. Held
    -- as on the old one till the jump landed, he went by it - "cant go from one moving pole to another", 2026-10-23)
    if el > TAKEOFF + 0.1 and st then
        local t2, d2 = nil, 1.0e9
        pcall(function()
            local l = pawn:K2_GetActorLocation()
            for _, t in ipairs(st.trunks) do
                if t ~= h.t and l.Z > t.z - 50.0 and l.Z < t.z + t.h + 60.0 then
                    local d = math.sqrt((l.X - t.x) ^ 2 + (l.Y - t.y) ^ 2)
                    if d < d2 then t2, d2 = t, d end
                end
            end
            local sliding = false
            pcall(function() sliding = cm:IsPoleSliding() end)
            if not (d2 < M.CATCH or (sliding and d2 < M.REACH)) then t2 = nil end
        end)
        if t2 then
            pcall(function() if ai:Montage_IsPlaying(j.m) then ai:Montage_Stop(0.1, j.m) end end)
            ai.RootMotionMode = 2
            TC.on = nil
            carried_off()
            ignore_tree(pawn, h, false)
            log("climb: the next %s reached in the jump (%.0f cm off it) - grabbed", t2.tree and "tree" or "pole", d2)
            if not M.grab_from_air(pawn, t2) then TC.cool = 0.0 end
            return
        end
    end
    -- (down to water: the jump over there, the swim's from here - held as "carried" by the pole till it ended, he
    -- fell through all the water to its bottom, "you will fall through all the water below it", 2026-10-23)
    local wet = false
    pcall(function()
        local l = pawn:K2_GetActorLocation()
        local sz = G and G.water_at and G.water_at(l.X - lib.OFFSET.X, l.Y - lib.OFFSET.Y)
        -- (going down by where he is, not his speed: limp, his speed reads nothing)
        wet = sz ~= nil and l.Z <= (j.lastz or 1.0e12) and (l.Z - lib.OFFSET.Z) < sz + 100.0
        j.lastz = l.Z
    end)
    if wet or (cm.MovementMode == 1 and el > TAKEOFF + 0.2) or el > 3.0 then
        local ai = pawn.Mesh:GetAnimInstance()
        ai.RootMotionMode = 2           -- (STORROR's own on the ground; on the trunk its slide had it ignored)
        pcall(function() if ai:Montage_IsPlaying(j.m) then ai:Montage_Stop(0.25, j.m) end end)
        local G = package.loaded["game"]
        if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
        TC.on = nil
        carried_off()
        if j.mv then ignore_tree(pawn, h, false) end
        TC.cool = 0.3
        TC.watch_until = os.clock() + 3.0
        log("climb: jump over (%s)", wet and "into the water" or cm.MovementMode == 1 and "landed" or "took too long")
    end
end
local function finish_up(pawn, h)
    local l = pawn:K2_GetActorLocation()
    local half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
    local feet = l.Z - half
    -- (on the top: lifted onto it if the climb ended low; a little high, he drops onto it)
    do
        -- (on the top: within its disc, and not under it)
        local dx, dy = l.X - h.t.x, l.Y - h.t.y
        local n = math.sqrt(dx * dx + dy * dy)
        local z = math.max(l.Z, h.up.top + half + 1.0)
        if n > 30.0 then dx, dy = dx / n * 25.0, dy / n * 25.0 end
        if n > 30.0 or feet < h.up.top - 2.0 then
            pcall(function() pawn:K2_SetActorLocation({ X = h.t.x + dx, Y = h.t.y + dy, Z = z }, false, {}, true) end)
        end
    end
    pcall(function() pawn.CapsuleComponent:IgnoreActorWhenMoving(h.t.actor, false) end)
    -- (root motion off while the clip fades out - its step back would walk him off the top - then STORROR's own)
    pcall(function() pawn.Mesh:GetAnimInstance().RootMotionMode = 1 end)
    TC.rm_back = os.clock() + 0.4
    if h.up.mw then
        pcall(function() h.up.mw:SetComponentTickEnabled(true) end)
        pcall(function() h.up.mw:Activate(false) end)
    end
    -- (our "Reset" target gone: STORROR's other moves steer to that name too, and pulled him to the tree's top
    -- - "the charaters moving to another tree")
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetClass():GetFName():ToString() == "MotionWarpingComponent" then o:RemoveWarpTarget(FName("Reset")) end
        end
    end)
    TC.on = nil
    carried_off()
    -- (handed back standing - walking mode - not dropped: a drop made STORROR's landing step take him ~40 cm on.
    -- The stick stays locked, and he is held on the top's middle, till it is let go (at most 1.5 s): pushed up to
    -- climb, it walked him straight off the top - "he lands on top but not in the right area")
    pcall(function() pawn.CharacterMovement:SetMovementMode(1, 0) end)
    local G = package.loaded["game"]
    if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
    pcall(function() local p = pawn:K2_GetActorLocation(); TC.pin = { x = p.X, y = p.Y, till = os.clock() + 1.5, t = h.t } end)
    if not TC.pin then lock(pawn, false) end
    TC.cool = 0.5
    log("climb: on top (feet %.0f cm from it, %.0f cm from its middle)", feet - h.up.top, math.sqrt((l.X - h.t.x) ^ 2 + (l.Y - h.t.y) ^ 2))
end
-- the trunks on DDD's moving poles brought to where the poles are now (poles.lua moved them this tick, first)
local function follow_movers()
    local PO = package.loaded["poles"]
    if not (PO and PO.moving) then return end
    local now = nil
    local lifts = nil
    for _, t in ipairs(st.trunks) do
        -- (a cage's pole, up and down with its cage: the trunk with it, and him on it - every height his hold keeps)
        if t.lifter and PO.lifts then
            lifts = lifts or PO.lifts()
            for _, q in ipairs(lifts) do
                if q.hx == t.lifter.hx and q.hz == t.lifter.hz then
                    local nz = q.sz + OFFSET.Z
                    local dz = nz - t.z
                    if math.abs(dz) > 0.01 then
                        t.z = nz
                        pcall(function() t.actor:K2_SetActorLocation({ X = t.x, Y = t.y, Z = nz }, false, {}, true) end)
                        local h = TC.on
                        if h and h.t == t then
                            if h.z then h.z = h.z + dz end
                            if h.up then h.up.top = h.up.top + dz; h.up.z0 = h.up.z0 + dz end
                            if h.jump then h.jump.z0 = h.jump.z0 + dz end
                            if h.down then h.down.z0 = h.down.z0 + dz end
                        end
                    end
                    break
                end
            end
        end
        if t.mover then
            now = now or PO.moving()
            local m = t.mover.i and now[t.mover.i]
            if not (m and m.hx == t.mover.hx and m.hz == t.mover.hz) then
                m = nil
                for i, q in ipairs(now) do
                    if math.abs(q.hx - t.mover.hx) < 1.0 and math.abs(q.hz - t.mover.hz) < 1.0 then m, t.mover.i = q, i; break end
                end
            end
            if m then
                local nx, ny = m.sx + OFFSET.X, m.sy + OFFSET.Y
                if math.abs(nx - t.x) > 0.01 or math.abs(ny - t.y) > 0.01 then
                    local ox, oy = t.x, t.y
                    t.x, t.y = nx, ny
                    pcall(function() t.actor:K2_SetActorLocation({ X = nx, Y = ny, Z = t.z }, false, {}, true) end)
                    -- (just up on its top, held there a moment: the spot he is held at goes with it)
                    if TC.pin and TC.pin.t == t then TC.pin.x, TC.pin.y = TC.pin.x + (nx - ox), TC.pin.y + (ny - oy) end
                end
            end
        end
    end
end

function M.update(dt, pawn)
    if not (M.enabled and st and pawn) then return end
    local w = lib.world()
    if not (w and w:GetAddress() == st.world) then return end
    pcall(follow_movers)
    -- (a star's cutscene - time stopped for him, his movement off: game.lua G.star_cut - holds him where he is on the
    -- pole, as Mario 64's does. Taken for being knocked off, he was let go, then left flying in the air when it ended:
    -- "after collecting 8th red coin while grabbing a pole it left the player floating in the air", 2026-10-23.)
    local GM = package.loaded["game"]
    if GM and GM.star_cut and TC.on then
        TC.frozen = TC.frozen or os.clock()
        return
    end
    if TC.frozen then
        local f = os.clock() - TC.frozen
        TC.frozen = nil
        if TC.on and TC.on.jump then TC.on.jump.t0 = TC.on.jump.t0 + f end
    end
    if TC.mbase then
        local h0 = TC.on
        if not (h0 and h0.t and h0.t.mover and not h0.grab and not h0.up and not (h0.jump and h0.jump.off)) then pcall(mesh_shift, pawn) end
    end
    dt = math.min(0.1, dt or (1.0 / 60.0))
    local cm = pawn.CharacterMovement
    local l = pawn:K2_GetActorLocation()
    local now = os.clock()
    pcall(drawn_back, l)
    local G = package.loaded["game"]
    if G and (G.cutscene or G.warping or G.pending or G.dying or G.swim) then
        if TC.on and not TC.on.jump then let_go(pawn, "leaving") end
        if not TC.on then return end
    end
    local sx, sy = stick()
    if TC.on then
        local D = package.loaded["dialog"]
        local talking = D and D.active
        if talking then hush = true end
        if hush then
            if not talking and not jump_raw() and math.abs(sx) < 0.2 and math.abs(sy) < 0.2 then
                hush = false
                TC.on.jump_was = false
                log("climb: the words over - free to move on the trunk again")
            else
                sx, sy = 0.0, 0.0
            end
        end
    else
        hush = false
    end
    if TC.pin then
        -- (and at a jump: pinned with the stick still held from the climb up, a jump off went straight up and down onto
        -- the top again - "got stuck when trying to jump off pole", 2026-11-02)
        if now > TC.pin.till or (math.abs(sx) < 0.2 and math.abs(sy) < 0.2) or jump_raw() then
            TC.pin = nil
            lock(pawn, false)
        else pcall(function() pawn:K2_SetActorLocation({ X = TC.pin.x, Y = TC.pin.y, Z = l.Z }, false, {}, true) end) end
    end
    if TC.rm_back and now >= TC.rm_back then
        TC.rm_back = nil
        pcall(function() pawn.Mesh:GetAnimInstance().RootMotionMode = 2 end)
    end
    local h = TC.on
    -- (Mario 64's climbing sounds - SOUND_ACTION_CLIMB_UP_TREE / _POLE with each pull up, the slide-down loop as he comes
    -- down, by how he moves on the trunk: "next add tree climbing audio", 2026-10-16)
    -- (only on the trunk itself - Mario 64's are his pulls up it and his slide down it: hanging from its top and going
    -- over onto it, STORROR's own moves lift him, and each lift was taken for pulls up the pole - "pole climbing audio is
    -- bugged", 2026-10-24)
    if h and h.t and not h.jump and not h.grab and not h.up and not h.down then
        local S = package.loaded["sfx"]
        -- (his height on the trunk, not in the world: a Fire Sea cage's pole goes up and down with him held still on it,
        -- and that played the climbing and sliding sounds too)
        -- (his hold's own height - h.z, carried with the cage in the same frame - not his capsule's, a frame behind it:
        -- read from the capsule, the cage's every step looked like a pull up and a slide back, and with the wait between
        -- pulls set to nothing at each, the pull's sound played near every frame - "it sounds like 100 tree climbing audios
        -- stacked ontop of eachother", 2026-10-25. The wait runs down whatever he does.)
        local rel = (h.z or l.Z) - h.t.z
        local z0 = TC.snd_t_of == h.t and TC.snd_z or nil
        TC.snd_z, TC.snd_t_of = rel, h.t
        TC.snd_t = math.max(0.0, (TC.snd_t or 0.0) - dt)
        if S and z0 then
            local dz = (rel - z0) / math.max(dt, 1e-3)
            if dz > 40.0 then
                if TC.snd_t <= 0.0 then
                    TC.snd_t = 0.4
                    pcall(S.play, h.t.tree and "climb_up_tree" or "climb_up_pole", 0.8)
                end
            else
                if dz < -60.0 and S.hold then
                    pcall(S.hold, h.t.tree and "loop_slide_down_tree" or "loop_slide_down_pole", math.min(0.9, 0.3 - dz / 600.0))
                end
            end
        end
    else
        TC.snd_z = nil
    end
    -- (a pull off the pole - "floates off to the side at mach 10 ... like a magnet ... while holding onto the pole":
    -- held by the mod, never more than 1.2 m from it; in STORROR's own pole slide, which only goes down, no more than
    -- 3 m/s across. Each caught, logged with what he was doing.)
    pcall(function()
        local v = cm.Velocity
        local across = math.sqrt(v.X * v.X + v.Y * v.Y)
        if h and h.t and not h.jump then
            local dd = math.sqrt((l.X - h.t.x) ^ 2 + (l.Y - h.t.y) ^ 2)
            if dd > 120.0 then
                local phase = h.up and "climbing up" or h.grab and "hanging from the top" or h.down and "coming down" or "on the pole"
                -- (pulled off every frame - something else holding him elsewhere - he lets go rather than be fought over:
                -- stuck there for seconds, a line logged each frame, 2026-10-18)
                TC.pulls = (TC.pulls or 0) + 1
                if TC.pulls > 40 then
                    TC.pulls = 0
                    log("climb: pulled off %.0f cm every frame (%s) - let go", dd, phase)
                    let_go(pawn, "kept being pulled off")
                    return
                end
                if TC.pulls == 1 then log("climb: PULLED %.0f cm off the pole (%s, mode %d, %.0f cm/s) - put back", dd, phase, cm.MovementMode, across) end
                local a = math.rad(h.ang)
                pawn:K2_SetActorLocation({ X = h.t.x + math.cos(a) * NEAR, Y = h.t.y + math.sin(a) * NEAR, Z = l.Z }, false, {}, true)
                cm.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
                if h.up then h.up.x0, h.up.y0 = h.t.x + math.cos(a) * NEAR, h.t.y + math.sin(a) * NEAR end
            else
                TC.pulls = 0
            end
        elseif not h and across > 300.0 then
            local sliding = false
            pcall(function() sliding = cm:IsPoleSliding() end)
            if sliding then
                local name = ""
                pcall(function() local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage(); if m and m:IsValid() then name = m:GetFName():ToString():sub(1, 30) end end)
                log("climb: PULLED across at %.0f cm/s in STORROR's pole slide (%s, mode %d) - stopped", across, name, cm.MovementMode)
                cm.Velocity = { X = 0.0, Y = 0.0, Z = v.Z }
            end
        end
    end)
    if h and TC.on ~= h then return end                -- (let go just now: pulled off once too often)
    -- (after leaving a pole: never left in flying mode - no gravity, no friction there, so any speed he had kept him
    -- going: "launched off the pole at mach 10". STORROR's pole-slide landing left him so.)
    if not h and TC.watch_until and now < TC.watch_until and cm.MovementMode == 5 then
        local name = ""
        pcall(function() local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage(); if m and m:IsValid() then name = m:GetFName():ToString() end end)
        if name == "" or name:find("Slide_Pole") then
            TC.fly_t = (TC.fly_t or 0.0) + dt
            if TC.fly_t > 0.1 then
                TC.fly_t = 0.0
                local v = cm.Velocity
                pcall(function() cm:SetMovementMode(3, 0) end)
                cm.Velocity = { X = 0.0, Y = 0.0, Z = math.min(0.0, v.Z) }
                local G = package.loaded["game"]
                if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
                log("climb: left flying after the pole (%s, %.0f cm/s) - put back to falling", name ~= "" and name:sub(1, 30) or "no move", math.sqrt(v.X * v.X + v.Y * v.Y))
            end
        else TC.fly_t = 0.0 end
    end
    if not h then
        if TC.cool and TC.cool > 0 then TC.cool = TC.cool - dt; return end
        local sliding = false
        pcall(function() sliding = cm:IsPoleSliding() end)
        if sliding then
            -- (only a trunk within reach: STORROR's slide takes anything thin and upright - a spike with no pole - and
            -- he was taken to the nearest trunk 12 m off and held there, "getting stuck on them also", 2026-10-18;
            -- with none near, STORROR's own slide has him)
            local t, td = nearest_trunk(l)
            if t and td < M.REACH then take(pawn, t, l) end
        end
        return
    end
    if h.jump then jump_tick(pawn, h); return end
    -- hanging from the top (STORROR's ledge grab, held at its end)
    if h.grab and not h.up then
        local ai = pawn.Mesh:GetAnimInstance()
        cm.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
        if cm.MovementMode ~= 5 then pcall(function() cm:SetMovementMode(5, 0) end) end
        local g = h.grab
        -- (placed by his hands: their grip - between the two middle-finger roots - drawn onto the top's edge on his
        -- side, just under its top: "make him grab the square in the correct area". A top without an edge given
        -- (the trees) - his hang under its top, as before.)
        pcall(function()
            local sq = h.t.square
            local a = math.rad(h.ang)
            local cx, cy = math.cos(a), math.sin(a)
            if sq then
                -- (facing a side of the square, not a corner)
                local side = math.floor((h.ang + 45.0) / 90.0) * 90.0
                local da = ((side - h.ang + 540.0) % 360.0) - 180.0
                h.ang = h.ang + da * (1.0 - math.exp(-10.0 * dt))
                a = math.rad(h.ang)
                cx, cy = math.cos(a), math.sin(a)
                local gl = pawn.Mesh:GetSocketLocation(FName("middle_01_l"))
                local gr = pawn.Mesh:GetSocketLocation(FName("middle_01_r"))
                local gx, gy, gz = (gl.X + gr.X) / 2.0, (gl.Y + gr.Y) / 2.0, (gl.Z + gr.Z) / 2.0
                local ed = sq / math.max(math.abs(cx), math.abs(cy))
                local tx, ty, tz = h.t.x + cx * ed, h.t.y + cy * ed, h.t.z + h.t.h + 1.0 - 4.0
                local l = pawn:K2_GetActorLocation()
                local k = 1.0 - math.exp(-12.0 * dt)
                -- (at most 3 cm a frame: his hands are physics-simulated and can lag; chasing them unbounded could
                -- run away - "floates off to the side at mach 10")
                local cx_, cy_, cz_ = (tx - gx) * k, (ty - gy) * k, (tz - gz) * k
                local cl = math.sqrt(cx_ * cx_ + cy_ * cy_ + cz_ * cz_)
                if cl > 3.0 then cx_, cy_, cz_ = cx_ * 3.0 / cl, cy_ * 3.0 / cl, cz_ * 3.0 / cl end
                local n = { X = l.X + cx_, Y = l.Y + cy_, Z = l.Z + cz_ }
                pawn:K2_SetActorLocation(n, false, {}, true)
                h.z = n.Z
                h.d = math.sqrt((n.X - h.t.x) ^ 2 + (n.Y - h.t.y) ^ 2)
                g.miss = math.sqrt((tx - gx) ^ 2 + (ty - gy) ^ 2 + (tz - gz) ^ 2)
            else
                local hz = h.t.z + h.t.h - TOP_GAP
                h.z = hz + (h.z - hz) * math.exp(-10.0 * dt)
                pawn:K2_SetActorLocation({ X = h.t.x + cx * h.d, Y = h.t.y + cy * h.d, Z = h.z }, false, {}, true)
            end
            pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = h.ang + 180.0, Roll = 0.0 }, false)
        end)
        pcall(function()
            local pos = ai:Montage_GetPosition(g.m)
            if not g.hang and (pos >= GRAB_CATCH or not ai:Montage_IsPlaying(g.m)) then
                g.hang = os.clock()
                if not ai:Montage_IsPlaying(g.m) then ai:Montage_Play(g.m, 1.0, 0, GRAB_CATCH, true) end
                ai:Montage_SetPosition(g.m, GRAB_CATCH)
                ai:Montage_SetPlayRate(g.m, 0.0)
            end
        end)
        -- (his hands onto the edge, eased in once he has caught it)
        g.ik = math.min(1.0, (g.ik or 0.0) + (g.hang and dt / 0.15 or 0.0))
        hands_on_edge(h, g.ik)
        local jd = jump_down()
        if jd and not h.jump_was then
            pcall(function() ai:Montage_Stop(0.1, g.m) end)
            h.grab = nil
            if not start_jump(pawn, h) then let_go(pawn, "jump") end
            return
        end
        h.jump_was = jd
        if g.hang then
            if not g.logged and os.clock() - g.hang > 0.3 then
                g.logged = true
                log("climb: hanging - grip %.0f cm from the top's edge, his middle %.0f cm out, %.0f under the top",
                    g.miss or -1, h.d, h.t.z + h.t.h - h.z)
            end
            if sy > 0.5 and os.clock() - g.hang >= HANG_MIN then
                pcall(function() ai:Montage_Stop(0.15, g.m) end)
                if start_up(pawn, h) then return end
            elseif sy < -0.5 then
                -- (back down onto the pole: eased from the hang to his hold on it, the ledge grab fading into the
                -- pole's slide pose, his hands letting go of the edge - "it has to sync back onto the pole")
                pcall(function() ai:Montage_Stop(DOWN_T, g.m) end)
                if h.montage then pcall(function() ai:Montage_Play(h.montage, 1.0, 0, h.mpos or 0.5, true); ai:Montage_SetPlayRate(h.montage, 0.0) end) end
                h.down = { t0 = os.clock(), z0 = h.z, d0 = h.d, ik0 = g.ik or 0.0 }
                h.grab = nil
                log("climb: back down from the top onto the pole")
            end
        end
        return
    end
    -- climbing up on top
    if h.up then
        if cm.MovementMode ~= 5 then pcall(function() cm:SetMovementMode(5, 0) end) end
        hands_on_edge(h, (h.grab and h.grab.ik or 0.0) * math.max(0.0, 1.0 - (os.clock() - h.up.t0) / 0.25))
        local ai = pawn.Mesh:GetAnimInstance()
        local playing = false
        pcall(function() playing = ai:Montage_IsPlaying(h.up.m) end)
        pcall(function()
            -- (up by the clip's own lift; in to the top's middle as he comes over the edge, by the mod)
            local u = h.up
            local pos = playing and ai:Montage_GetPosition(u.m) or 2.0
            u.pos = pos
            local g = math.min(1.0, math.max(0.0, (pos - 0.6) / (UP_END - 0.6)))
            g = g * g * (3.0 - 2.0 * g)
            local l = pawn:K2_GetActorLocation()
            u.r = u.r + (l.Z - u.zs)
            l = { X = u.x0 + (h.t.x - u.x0) * g, Y = u.y0 + (h.t.y - u.y0) * g, Z = u.z0 + u.r * u.kz }
            u.zs = l.Z
            pawn:K2_SetActorLocation(l, false, {}, true)
        end)
        if not playing or (h.up.pos or 0) >= UP_END or os.clock() - h.up.t0 > 3.0 then
            pcall(function() ai:Montage_Stop(0.25, h.up.m) end)
            finish_up(pawn, h)
        end
        return
    end
    -- from the top back onto the pole
    if h.down then
        local d = h.down
        local k = math.min(1.0, (os.clock() - d.t0) / DOWN_T)
        local e = k * k * (3.0 - 2.0 * k)
        if cm.MovementMode ~= 5 then pcall(function() cm:SetMovementMode(5, 0) end) end
        cm.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
        h.d = d.d0 + (NEAR - d.d0) * e
        h.z = d.z0 - DOWN_DZ * e
        local a = math.rad(h.ang)
        pcall(function()
            pawn:K2_SetActorLocation({ X = h.t.x + math.cos(a) * h.d, Y = h.t.y + math.sin(a) * h.d, Z = h.z }, false, {}, true)
            pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = h.ang + 180.0, Roll = 0.0 }, false)
        end)
        hands_on_edge(h, d.ik0 * (1.0 - e))
        if k >= 1.0 then h.down = nil end
        h.ik = 0.0                  -- (the climb's limbs blended back in once he holds the trunk again)
        return
    end
    -- held on the trunk
    if cm.MovementMode ~= 5 then let_go(pawn, "moved off by something else"); return end
    local jd = jump_down()
    if jd and not h.jump_was then
        if not start_jump(pawn, h) then let_go(pawn, "jump") end
        return
    end
    h.jump_was = jd
    -- (down: the mod's own slide, as fast as the stick is down, held again the moment it is let go - STORROR's slide,
    -- handed to, ran him to the foot in half a second whatever the stick did: "he still slides down on his own")
    -- (down slides him only once the stick has rested in the middle 0.15 s first: let go of from up, it read fully
    -- down for up to 0.7 s and slid him - "when going up then letting go the charater starts falling on his own".
    -- Going up or hard across ends the rest; a slide, once going, lasts while down is held.)
    local now_ = os.clock()
    if math.abs(sx) < 0.15 and math.abs(sy) < 0.15 then
        h.rest = (h.rest or 0.0) + dt
        if h.rest >= 0.15 then h.armed = true end
    elseif sy > 0.3 or math.abs(sx) > 0.5 then
        h.rest, h.armed = 0.0, false
    end
    local down = sy < -0.3 and math.abs(sy) > math.abs(sx)
    if down and (h.armed or h.sliding) then
        if not h.sliding then h.slide_t = now_ end
        h.sliding = true
    else
        h.sliding = false
    end
    h.down_t = h.sliding and (now_ - (h.slide_t or now_)) + 0.1 or 0.0
    local sliding_down = h.sliding
    if sliding_down then
        local half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
        local foot = h.t.z + half + 2.0
        h.z = h.z - SLIDE * math.min(1.0, -sy) * math.min(1.0, (h.down_t - 0.1) / 0.25) * dt
        if h.z <= foot then
            h.z = foot
            local a = math.rad(h.ang)
            pcall(function() pawn:K2_SetActorLocation({ X = h.t.x + math.cos(a) * h.d, Y = h.t.y + math.sin(a) * h.d, Z = h.z }, false, {}, true) end)
            let_go(pawn, "slid to its foot")
            pcall(function() cm:SetMovementMode(1, 0) end)
            return
        end
    end
    local ai = pawn.Mesh:GetAnimInstance()
    local rate = 0.0
    if sy > 0.3 then
        local top = h.t.z + h.t.h - TOP_GAP
        local phi0 = h.phi or 0.0
        local phi1 = phi0 + CLIMB * sy * dt / STROKE
        local nz = h.z + STROKE * (stroke_pos(phi1) - stroke_pos(phi0))
        if nz > top then nz = math.max(h.z, top) else h.phi = phi1 end
        h.z = nz
        -- (at the top, still pushed up: over the top onto the tree)
        if nz >= top - 0.5 and sy > 0.5 then
            h.push = (h.push or 0.0) + dt
            if h.push > 0.15 and start_grab(pawn, h) then return end
        else h.push = 0.0 end
    else h.push = 0.0 end
    if math.abs(sx) > 0.3 then h.ang = h.ang - ROUND * sx * dt end
    h.d = NEAR + (h.d - NEAR) * math.exp(-PULL * dt)
    local a = math.rad(h.ang)
    local hx, hy = h.t.x + math.cos(a) * h.d, h.t.y + math.sin(a) * h.d
    -- (on DDD's moving poles, STORROR's held slide pose has his hips some 54 cm out behind his capsule: put by his capsule
    -- he hung in the air beside the pole - "has the player floatin next to it instead of on it", "not on the pole",
    -- 2026-10-23. There his capsule goes where his hips come M.HIP_AT from the pole's middle.)
    if h.t.mover then
        -- (Mario 64's set_pole_position: a wall within 60 units of the pole where he is on it bonks him off it, a floor
        -- come up over his feet stands him on it. Carried by the pole into a block, his legs went through it - "legs go
        -- through objects when climbing", 2026-10-23)
        local G = package.loaded["game"]
        local out = nil
        pcall(function()
            local half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
            local px, py, feet = h.t.x - OFFSET.X, h.t.y - OFFSET.Y, h.z - half - OFFSET.Z
            local fz = G.floor_z(px, py, feet + 58.0)
            if fz and fz > feet then out = { floor = fz, half = half }; return end
            local hit, wx, wy = G.wall_near(px, py, feet + 50.0 * U, 60.0 * U, 10.0)
            if not hit then hit, wx, wy = G.wall_near(px, py, feet + 24.0 * U, 30.0 * U, 10.0) end
            if hit then out = { wx = wx, wy = wy, half = half } end
        end)
        if out then
            local cx, cy = h.t.x + math.cos(a) * NEAR, h.t.y + math.sin(a) * NEAR
            if out.floor then
                let_go(pawn, "the floor came up under him")
                pcall(function()
                    pawn:K2_SetActorLocation({ X = cx, Y = cy, Z = out.floor + OFFSET.Z + out.half + 2.0 }, false, {}, true)
                    cm:SetMovementMode(1, 0)
                end)
            else
                let_go(pawn, "bonked off a wall")
                local n = math.sqrt(out.wx * out.wx + out.wy * out.wy)
                local ux, uy = math.cos(a), math.sin(a)
                if n > 1e-3 then ux, uy = out.wx / n, out.wy / n end
                pcall(function()
                    pawn:K2_SetActorLocation({ X = cx + out.wx, Y = cy + out.wy, Z = h.z }, false, {}, true)
                    cm.Velocity = { X = ux * 120.0, Y = uy * 120.0, Z = 0.0 }
                end)
            end
            TC.cool = 0.6       -- (the pole not taken again at once: it is still going that way)
            return
        end
        -- (his body on the pole: his mesh moved in his capsule so his hips come M.HIP_AT from the pole's middle - STORROR's
        -- held slide pose has them some 54 cm out behind the capsule, and he hung in the air beside the pole, "not on the
        -- pole", 2026-10-23)
        pcall(function()
            local l = pawn:K2_GetActorLocation()
            local yaw = math.rad(pawn:K2_GetActorRotation().Yaw)
            local cs, sn = math.cos(yaw), math.sin(yaw)
            local pel = pawn.Mesh:GetSocketLocation(FName("pelvis"))
            local wx, wy = pel.X - l.X, pel.Y - l.Y
            local sh = TC.mshift or { 0.0, 0.0 }
            -- (the pose's own hips in his frame, the shift taken out)
            local ox, oy = wx * cs + wy * sn - sh[1], -wx * sn + wy * cs - sh[2]
            if h.poff then ox, oy = h.poff[1] + (ox - h.poff[1]) * 0.3, h.poff[2] + (oy - h.poff[2]) * 0.3 end
            h.poff = { ox, oy }
            -- (he faces the pole: its middle is h.d ahead of his capsule, his hips wanted M.HIP_AT short of it)
            mesh_shift(pawn, (h.d - M.HIP_AT) - ox, -oy)
        end)
    end
    pcall(function()
        pawn:K2_SetActorLocation({ X = hx, Y = hy, Z = h.z }, false, {}, true)
        pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = h.ang + 180.0, Roll = 0.0 }, false)
    end)
    cm.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
    -- (STORROR's slide pose: its montage kept on, still while he holds and climbs - the climb is his limbs, below)
    if sliding_down then rate = 0.8 * math.min(1.0, -sy) end
    h.ik = math.max(0.0, math.min(1.0, (h.ik or 0.0) + (sliding_down and -dt or dt) / IK_IN))
    climb_limbs(h, h.ik)
    if h.montage then
        pcall(function()
            if not ai:Montage_IsPlaying(h.montage) then ai:Montage_Play(h.montage, 1.0, 0, h.mpos or 0.5, true) end
            local p = ai:Montage_GetPosition(h.montage)
            if rate < 0 and p < 0.25 then ai:Montage_SetPosition(h.montage, math.max(0.3, (h.mpos or 1.0))) end
            -- (sliding: its slide played on, looped back before its end)
            if rate > 0 and p > 2.4 then ai:Montage_SetPosition(h.montage, math.max(0.3, (h.mpos or 1.0))) end
            ai:Montage_SetPlayRate(h.montage, rate)
        end)
    end
end



-- ------------------------------------------------------------ the trunks
local function cylinder(r, z0, z1, sides, pos, idx)
    local b = #pos // 3
    for i = 0, sides - 1 do
        local a = i * 2 * math.pi / sides
        for _, z in ipairs({ z0, z1 }) do pos[#pos + 1] = r * math.cos(a); pos[#pos + 1] = r * math.sin(a); pos[#pos + 1] = z end
    end
    for i = 0, sides - 1 do
        local a0, a1 = b + i * 2, b + ((i + 1) % sides) * 2
        for _, t in ipairs({ { a0, a1, a0 + 1 }, { a1, a1 + 1, a0 + 1 }, { a0, a0 + 1, a1 }, { a1, a0 + 1, a1 + 1 } }) do
            idx[#idx + 1] = t[1]; idx[#idx + 1] = t[2]; idx[#idx + 1] = t[3]
        end
    end
end
local function disc(r, z, sides, pos, idx)
    local c = #pos // 3
    pos[#pos + 1] = 0.0; pos[#pos + 1] = 0.0; pos[#pos + 1] = z
    for i = 0, sides - 1 do
        local a = i * 2 * math.pi / sides
        pos[#pos + 1] = r * math.cos(a); pos[#pos + 1] = r * math.sin(a); pos[#pos + 1] = z
    end
    for i = 0, sides - 1 do
        local v0, v1 = c + 1 + i, c + 1 + (i + 1) % sides
        idx[#idx + 1] = c; idx[#idx + 1] = v0; idx[#idx + 1] = v1
        idx[#idx + 1] = c; idx[#idx + 1] = v1; idx[#idx + 1] = v0
    end
end
local function box(hx, z0, z1, pos, idx)
    local function quad(p)
        local b = #pos // 3
        for _, v in ipairs(p) do pos[#pos + 1] = v[1]; pos[#pos + 1] = v[2]; pos[#pos + 1] = v[3] end
        for _, t in ipairs({ { 0, 1, 2 }, { 0, 2, 3 }, { 0, 2, 1 }, { 0, 3, 2 } }) do
            idx[#idx + 1] = b + t[1]; idx[#idx + 1] = b + t[2]; idx[#idx + 1] = b + t[3]
        end
    end
    local h = hx
    quad({ { -h, -h, z1 }, { h, -h, z1 }, { h, h, z1 }, { -h, h, z1 } })
    quad({ { -h, -h, z0 }, { h, -h, z0 }, { h, h, z0 }, { -h, h, z0 } })
    quad({ { h, -h, z0 }, { h, h, z0 }, { h, h, z1 }, { h, -h, z1 } })
    quad({ { -h, -h, z0 }, { -h, h, z0 }, { -h, h, z1 }, { -h, -h, z1 } })
    quad({ { -h, h, z0 }, { h, h, z0 }, { h, h, z1 }, { -h, h, z1 } })
    quad({ { -h, -h, z0 }, { h, -h, z0 }, { h, -h, z1 }, { -h, -h, z1 } })
end
local TRUNK_R = 4.0             -- cm: STORROR's slide keeps his middle 20 from a pole's; his capsule is 15 round
local TREE_STAND = 70.0         -- a tree's top: a disc this round
local POLE_SQUARE = 12.0        -- a pole's top: a square this far each way from its middle (his hands take its edge)

local function make_trunk(world, x, y, z, h, tree, drawn, spike)
    local a = lib.spawn_actor(world, { X = x, Y = y, Z = z }, 0.0)
    if not a then return nil end
    local pmc = lib.add_pmc(a)
    if not pmc then lib.destroy(a); return nil end
    local pos, idx = {}, {}
    cylinder(TRUNK_R, 0.0, h, 12, pos, idx)
    if tree then disc(TREE_STAND, h + 1.0, 16, pos, idx) else box(POLE_SQUARE, h - 9.0, h + 1.0, pos, idx) end
    lib.add_collision(pmc, { { source = tree and "tree trunk" or "pole", pos = pos, idx = idx } })
    -- (the pole as drawn, a component of its own: it blocks his capsule and nothing else - STORROR's traces go through
    -- it to the trunk inside, so its pole slide still takes it - and it is off while he is on this pole: holding a
    -- spike thicker than where the mod holds him, he was pushed out of it 1.4 m every frame and put back, "please add
    -- our tree pole to the spikes", 2026-10-18)
    local dp, wide = nil, 0.0
    if drawn then
        dp = lib.add_pmc(a)
        if dp then
            lib.add_collision(dp, { drawn })
            pcall(function() dp:SetCollisionResponseToAllChannels(0) end)
            pcall(function() dp:SetCollisionResponseToChannel(2, 2) end)          -- (ECC_Pawn: blocked)
            pcall(function() dp:SetCollisionEnabled(1) end)
            for i = 1, #drawn.pos, 3 do wide = math.max(wide, math.sqrt(drawn.pos[i] ^ 2 + drawn.pos[i + 1] ^ 2)) end
        end
    end
    -- (his body parts - physics-simulated, object channel 17 - pass through: his hands striking the pole at the kick
    -- off made STORROR bail him into its ragdoll. His capsule still meets it.)
    pcall(function() pmc:SetCollisionResponseToChannel(17, 0) end)
    -- (nor the camera (ECC_Camera, 4): climbing, the pole between it and him drew STORROR's camera arm in onto the pole,
    -- the view stuck inside it - "camera gets stuck inside pole when climbing this is old", 2026-11-07. STORROR's own
    -- climbing traces are not the camera's.)
    pcall(function() pmc:SetCollisionResponseToChannel(4, 0) end)
    return { x = x, y = y, z = z, h = h, actor = a, tree = tree, spike = spike, drawn = dp, wide = wide,
             square = (not tree) and POLE_SQUARE or nil, stand = tree and TREE_STAND or POLE_SQUARE }
end

-- The pole as the level draws it, solid (in this pole's actor's own frame: (ox, oy, oz) its foot), or nil: Jolly Roger
-- Bay's climbable spikes are drawn up to the pole's top, their collision only up to its foot - Mario holds the rest -
-- and the athlete went through their upper three to seven metres ("next add collisions the the climbable spikes",
-- 2026-10-18). The level's drawn triangles that reach the pole's top, one corner at its middle, all of them within
-- 2.5 m of it; both faces. The pole's own actor: ignored with the trunk while he is on it.
M.DRAWN_NEAR, M.DRAWN_TIP, M.DRAWN_TOP = 250.0, 30.0, 30.0
local function drawn_pole(ox, oy, oz, top)
    local G = package.loaded["game"]
    local secs = G and G.data and G.data.sections
    if not secs then return nil end
    local pos, idx = {}, {}
    for _, m in ipairs(secs) do
        local P, I = m.pos, m.idx
        if P and I then
            for t = 1, #I, 3 do
                local ok, tip, zmax = true, false, -1e9
                for k = 0, 2 do
                    local v = I[t + k] * 3
                    local r = math.sqrt((P[v + 1] - ox) ^ 2 + (P[v + 2] - oy) ^ 2)
                    if r > M.DRAWN_NEAR then ok = false; break end
                    if r < M.DRAWN_TIP then tip = true end
                    zmax = math.max(zmax, P[v + 3])
                end
                if ok and tip and zmax >= top - M.DRAWN_TOP then
                    local b = #pos // 3
                    for k = 0, 2 do
                        local v = I[t + k] * 3
                        pos[#pos + 1] = P[v + 1] - ox; pos[#pos + 1] = P[v + 2] - oy; pos[#pos + 1] = P[v + 3] - oz
                    end
                    idx[#idx + 1] = b; idx[#idx + 1] = b + 1; idx[#idx + 1] = b + 2
                    idx[#idx + 1] = b; idx[#idx + 1] = b + 2; idx[#idx + 1] = b + 1
                end
            end
        end
    end
    if #idx == 0 then return nil end
    -- (a spike: its drawn top a single point - kept on the trunk as `spike`; climbed, held and stood on top of as any
    -- pole is, "just add our tree pole to them", 2026-10-18 - the trouble on them was game.lua's edge of the level)
    local zt = -1e9
    for i = 3, #pos, 3 do zt = math.max(zt, pos[i]) end
    local px, py, point = nil, nil, true
    for i = 1, #pos, 3 do
        if pos[i + 2] > zt - 5.0 then
            if not px then px, py = pos[i], pos[i + 1]
            elseif (pos[i] - px) ^ 2 + (pos[i + 1] - py) ^ 2 > 9.0 then point = false end
        end
    end
    return { source = "drawn pole", pos = pos, idx = idx }, point
end

-- the height of a tree's drawn model (cm), from its template
local function tree_height(tpl)
    local zmax = nil
    for _, sec in ipairs(tpl or {}) do
        local p = sec.pos
        if p then for i = 3, #p, 3 do if not zmax or p[i] > zmax then zmax = p[i] end end end
    end
    return zmax
end

-- objects: the level's trees and poles (game.lua's act-filtered list); ctx.tree_templates: the drawn trees
function M.load(world, objects, ctx)
    M.clear()
    local trunks = {}
    local n_drawn = 0
    -- (the poles Bowser in the Fire Sea's sinking cages bring up through their middles: poles.lua M.cage_poles, "no pole
    -- here", 2026-10-24)
    local PO = package.loaded["poles"]
    if PO and PO.cage_poles then
        local all = {}
        for _, o in ipairs(objects or {}) do all[#all + 1] = o end
        for _, o in ipairs(PO.cage_poles()) do all[#all + 1] = o end
        objects = all
    end
    for _, o in ipairs(objects or {}) do
        local ok, err = pcall(function()
            if o.kind == "tree" and o.pos then
                local h = tree_height(ctx and ctx.tree_templates and ctx.tree_templates[o.geo]) or 440.0
                trunks[#trunks + 1] = make_trunk(world, o.pos[1] + OFFSET.X, o.pos[2] + OFFSET.Y, o.pos[3] + OFFSET.Z, math.max(150.0, h - 1.0), true)
            elseif o.kind == "pole" and o.pos then
                -- (a pole: from its foot - down under where it stands - to its top, its height over where it stands)
                local down = (o.down or 0.0) * U
                local h = (o.height or 1000.0) * U + down
                local drawn, spike = drawn_pole(o.pos[1], o.pos[2], o.pos[3] - down, o.pos[3] + (o.height or 1000.0) * U)
                -- (the drawn pole made solid only for a spike - JRB's, thick and climbed: a thin pole is held as a tree is,
                -- by its trunk alone; solid round it, LLL's volcano poles "feels off from our normal trees", 2026-10-19)
                if not spike then drawn = nil end
                -- (and held as a tree is, all of it - its top a tree's too: "replace them with our tree pole", 2026-10-19)
                local t = make_trunk(world, o.pos[1] + OFFSET.X, o.pos[2] + OFFSET.Y, o.pos[3] + OFFSET.Z - down, h, not spike, drawn, spike)
                -- (DDD's moving poles: this trunk rides one - poles.lua moves and draws it, M.moving; the trunk follows
                -- each frame and him with it, held or on top: "moving poles dont have our tree poles in them",
                -- 2026-10-23)
                if t and o.type == "bhvDDDPole" and o.sm64 then t.mover = { hx = o.sm64[1], hz = o.sm64[3] } end
                -- (and the Fire Sea's cages' poles go up and down with their cages: poles.lua M.lifts)
                if t and o.cage then t.lifter = { hx = o.cage[1], hz = o.cage[2] } end
                trunks[#trunks + 1] = t
                if drawn then n_drawn = n_drawn + 1 end
            end
        end)
        if not ok then log("climb: a trunk failed: %s", tostring(err)) end
    end
    if #trunks == 0 then return end
    st = { world = world:GetAddress(), trunks = trunks }
    log("climb: %d trees and poles to climb (%d drawn poles made solid)", #trunks, n_drawn)
end

-- the scene going: him off any pole, the trunks gone
function M.clear()
    local s = st
    st = nil
    local pawn = lib.pawn()
    if TC.on and pawn then
        local h = TC.on
        TC.on = nil
        carried_off()
        pcall(function() pawn.CapsuleComponent:IgnoreActorWhenMoving(h.t.actor, false) end)
        lock(pawn, false)
        pcall(function() pawn.Mesh:GetAnimInstance().RootMotionMode = 2 end)
        pcall(function() if pawn.CharacterMovement.MovementMode == 5 then pawn.CharacterMovement:SetMovementMode(3, 0) end end)
    end
    if TC.pin and pawn then lock(pawn, false) end
    TC = {}
    local w = lib.world()
    if s and w and w:GetAddress() == s.world then
        for _, t in ipairs(s.trunks) do pcall(function() lib.destroy(t.actor) end) end
    end
end

function M.forget()
    if TC.on then carried_off() end
    if TC.mbase then pcall(mesh_shift, lib.pawn()) end
    st, TC = nil, {}
end

function M.active() return TC.on ~= nil end

-- What the climb under way is doing (fp.lua's first-person view): "hold" on the trunk, "hang" from its top, "up" going
-- over it, "jump" its Pole 180; nil off a trunk
function M.phase()
    local h = TC.on
    if not h then return nil end
    if h.jump then return "jump" end
    if h.up then return "up" end
    if h.grab then return "hang" end
    return "hold"
end

-- The trunk he is climbing, and how far under the top of his climb he is (cm: 0 at the top - hanging from it or going
-- over it); nil off a trunk. (Hoot wakes only for his tree climbed to its top: hoot.lua)
function M.on_trunk()
    local h = TC.on
    if not (h and h.t) then return nil end
    if h.grab or h.up then return h.t, 0.0 end
    return h.t, math.max(0.0, (h.t.z + h.t.h - TOP_GAP) - (h.z or -1.0e9))
end

return M
