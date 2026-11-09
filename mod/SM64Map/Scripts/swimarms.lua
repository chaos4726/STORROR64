-- SM64Map: the swimming body, built fresh every frame ("we might have to start from scratch with a whole new swim",
-- 2026-10-24). STORROR has no swim animation: in the water its animation is an idle that bends the chest and head
-- toward the camera, and building limbs on top of it - as the first swimarms did - fought it frame by frame and
-- contorted him. Here, once, while he treads calmly, the drawn copy's pose (footik.lua's) is captured in the body's
-- own space; from then on, every swimming frame the whole upper body, arms, legs and head are written from that
-- snapshot plus pure functions of time, heading and stroke phase. Nothing is read back mid-motion, so nothing can
-- fight, lag or contort. The mesh itself is turned and tipped by swim.lua/swimpose.lua as before, carrying this pose.
--
-- The body's space (the mesh component's): +Z up his body, +Y out of his chest, -X his right. Lying into the swim the
-- component is tipped, so in this space nothing changes: legs are always -Z, strokes always pull along +Z.
local lib = require("lib")
local M = {}

local sqrt, sin, cos, pi, max, min, abs, rad = math.sqrt, math.sin, math.cos, math.pi, math.max, math.min, math.abs, math.rad
local STROKE_TIME = 0.8             -- seconds one arm's stroke takes
local KICK_STROKE_TIME = 1.0        -- the same, the arms stroking by themselves while the button is held
local EASE_IN = 4.0                 -- how fast the swim's limbs blend in and out (share a second)
local BASE_LIFT = 25.0              -- degrees above the chest the face is baked to look at the capture (level, treading)

-- ------------------------------------------------------------ vectors and quaternions
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
    if w < 1e-6 then w = 0.0; c = abs(a[1]) > abs(a[3]) and { -a[2], a[1], 0.0 } or { 0.0, -a[3], a[2] }
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
local function qinv(q) return { -q[1], -q[2], -q[3], q[4] } end
-- from a to b the short way, by way of `via` when they are near opposite - there the short way is any way at all,
-- and between() alone snapped half a turn in a frame as an arm swept past straight
local function turn_to(a, b, via)
    if dot(a, b) > -0.4 then return between(a, b) end
    local m = norm(sub(via, mul(a, dot(via, a))))
    if not m then return between(a, b) end
    return qmul(between(m, b), between(a, m))
end
local function axis_angle(ax, a) local s = sin(a / 2.0); return { ax[1] * s, ax[2] * s, ax[3] * s, cos(a / 2.0) } end
local function nlerp(a, b, w)
    if w >= 0.999 then return b end
    if w <= 0.001 then return a end
    local sg = (a[1] * b[1] + a[2] * b[2] + a[3] * b[3] + a[4] * b[4]) < 0.0 and -1.0 or 1.0
    local q = { a[1] + (b[1] * sg - a[1]) * w, a[2] + (b[2] * sg - a[2]) * w, a[3] + (b[3] * sg - a[3]) * w, a[4] + (b[4] * sg - a[4]) * w }
    local l = sqrt(q[1] * q[1] + q[2] * q[2] + q[3] * q[3] + q[4] * q[4])
    return { q[1] / l, q[2] / l, q[3] / l, q[4] / l }
end
-- a rotator's turn, as the engine composes it (FRotator::Quaternion)
local function rot_quat(r)
    local p, y, ro = rad(r.Pitch) / 2.0, rad(r.Yaw) / 2.0, rad(r.Roll) / 2.0
    local SP, CP, SY, CY, SR, CR = sin(p), cos(p), sin(y), cos(y), sin(ro), cos(ro)
    return { CR * SP * SY - SR * CP * CY, -CR * SP * CY - SR * CP * SY,
             CR * CP * SY - SR * SP * CY, CR * CP * CY + SR * SP * SY }
end

-- ------------------------------------------------------------ the copy's bones
local BONES = { "pelvis", "spine_01", "spine_02", "spine_03", "spine_04", "spine_05",
                "clavicle_l", "clavicle_r", "neck_01", "head",
                "upperarm_r", "lowerarm_r", "hand_r", "upperarm_l", "lowerarm_l", "hand_l",
                "thigh_r", "calf_r", "foot_r", "thigh_l", "calf_l", "foot_l" }
local WORLD = 0

local function get_bone(pose, n)
    local t = pose:GetBoneTransformByName(FName(n), WORLD)
    return { p = { t.Translation.X, t.Translation.Y, t.Translation.Z },
             q = { t.Rotation.X, t.Rotation.Y, t.Rotation.Z, t.Rotation.W },
             s = { t.Scale3D.X, t.Scale3D.Y, t.Scale3D.Z } }
end
local function set_bone(pose, n, p, q, s)
    pose:SetBoneTransformByName(FName(n), { Rotation = { X = q[1], Y = q[2], Z = q[3], W = q[4] },
        Translation = { X = p[1], Y = p[2], Z = p[3] }, Scale3D = { X = s[1], Y = s[2], Z = s[3] } }, WORLD)
end

-- the component's place in the world: component space -> world
local function comp_frame(pose)
    local l = pose:K2_GetComponentLocation()
    local r = pose:K2_GetComponentRotation()
    local sc = pose:K2_GetComponentScale()
    return { p = { l.X, l.Y, l.Z }, q = rot_quat(r), s = (sc.X + sc.Y + sc.Z) / 3.0 }
end
local function to_world(C, p, q) return add(C.p, qrot(C.q, mul(p, C.s))), qmul(C.q, q) end
local function to_comp(C, p, q) return mul(qrot(qinv(C.q), sub(p, C.p)), 1.0 / C.s), qmul(qinv(C.q), q) end

-- ------------------------------------------------------------ where the hands go (component space, cm from the
-- shoulder: +Z toward his head, `out` to that arm's side, +Y out of his chest)
local GLIDE = { 50.0, 8.0, 8.0 }
local STROKE_KEYS = {           -- a front-crawl pull: ahead, down under the chest, back to the hip, round low and out
    { 0.00, 50.0, 8.0, 8.0 }, { 0.25, 25.0, 10.0, 32.0 }, { 0.45, -15.0, 8.0, 24.0 },
    { 0.60, -40.0, 14.0, 2.0 }, { 0.80, 8.0, 26.0, -8.0 }, { 1.00, 50.0, 8.0, 8.0 },
}
local function stroke_at(ph)
    for i = 1, #STROKE_KEYS - 1 do
        local a, b = STROKE_KEYS[i], STROKE_KEYS[i + 1]
        if ph <= b[1] then
            local k = (ph - a[1]) / (b[1] - a[1])
            k = k * k * (3.0 - 2.0 * k)
            return { a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k, a[4] + (b[4] - a[4]) * k }
        end
    end
    return GLIDE
end
local OTHER = { l = "r", r = "l" }

local base = nil        -- the captured pose: name -> { p, q, s } in component space; arm/leg lengths
local st = nil          -- per-swim: stroke phases, blend weights

-- (the capture kept on disk once made, and read back at start: it waited for a calm moment treading water in each
-- session, and a swim begun at once - hopping in and swimming off - had no swimming body at all, STORROR's plain water
-- idle instead: "sometimes when hopping in water animation doesnt trigger", 2026-10-29. Same skeleton every session)
local BASE_FILE = (lib.MOD_DIR or "") .. "swim_base.lua"
do
    local f = loadfile(BASE_FILE)
    if f then
        local ok, t = pcall(f)
        if ok and type(t) == "table" and t.pelvis and t.arm and t.leg then base = t; lib.log("swim body: pose read back") end
    end
end
local function ser(v)
    local ty = type(v)
    if ty == "number" then return string.format("%.9g", v) end
    if ty == "string" then return string.format("%q", v) end
    if ty == "boolean" then return tostring(v) end
    if ty ~= "table" then return "nil" end
    local parts = {}
    for k, x in pairs(v) do
        local key = (type(k) == "number") and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
        parts[#parts + 1] = key .. "=" .. ser(x)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function save_base(b)
    local f = io.open(BASE_FILE, "w")
    if not f then return false end
    f:write("-- the swimming body's pose, captured once (swimarms.lua)\nreturn " .. ser(b) .. "\n")
    f:close()
    return true
end
function M.has_base() return base ~= nil end
function M.save_base() return base ~= nil and save_base(base) end

-- the capture: only with the chest square and the body calm, so the look-at's bend is not frozen in
local function try_capture(pose)
    local C = comp_frame(pose)
    local ur, ul = get_bone(pose, "upperarm_r"), get_bone(pose, "upperarm_l")
    local urc = to_comp(C, ur.p, ur.q)
    local ulc = to_comp(C, ul.p, ul.q)
    local sh = sub(urc, ulc)
    if abs(sh[2]) > 0.18 * max(1.0, abs(sh[1])) then return false end     -- (chest turned aside: not square enough)
    local b = {}
    for _, n in ipairs(BONES) do
        local w = get_bone(pose, n)
        local p, q = to_comp(C, w.p, w.q)
        b[n] = { p = p, q = q, s = w.s }
    end
    -- (and only upright: his legs hanging under his hips, his head over his pelvis. Caught as he fell into the water or
    -- landed in it, a bent pose was frozen in, and every swim after drew him contorted - "the bodys all fucking
    -- contorted", 2026-10-26)
    local function hangs(t, f)
        local d = sub(b[f].p, b[t].p)
        local l = len(d)
        return l > 1e-3 and -d[3] > 0.8 * l
    end
    if not (hangs("thigh_r", "foot_r") and hangs("thigh_l", "foot_l")) then return false end
    local up = sub(b.head.p, b.pelvis.p)
    if up[3] < 0.8 * len(up) then return false end
    -- the face baked level (treading, the body is upright but for its small lean): toward +Y, tipped BASE_LIFT up
    local want = { 0.0, cos(rad(BASE_LIFT)), sin(rad(BASE_LIFT)) }
    for _, part in ipairs({ { "neck_01", 0.5 }, { "head", 1.0 } }) do
        local e = b[part[1]]
        local face = qrot(e.q, { 0.0, 1.0, 0.0 })
        local fix = between(norm(face) or want, want)
        e.q = qmul(nlerp({ 0.0, 0.0, 0.0, 1.0 }, fix, part[2]), e.q)
    end
    b.arm = { l1 = len(sub(b.lowerarm_r.p, b.upperarm_r.p)), l2 = len(sub(b.hand_r.p, b.lowerarm_r.p)) }
    b.leg = { l1 = len(sub(b.calf_r.p, b.thigh_r.p)), l2 = len(sub(b.foot_r.p, b.calf_r.p)) }
    base = b
    lib.log("swim body: pose captured%s", (pcall(save_base, b)) and " and kept" or "")
    return true
end

-- one arm in component space: shoulder at the base spot, the hand to `target`, elbow toward `pole`. The elbow's way
-- keeps memory (`pb`): passing full stretch its side turns ambiguous, and without the memory it flipped 138 degrees
-- in a frame as a stroke handed off to the glide (caught by the harness).
local function arm_cs(out, side, target, pole, pb)
    local U, L, H = "upperarm_" .. side, "lowerarm_" .. side, "hand_" .. side
    local S = base[U].p
    local l1, l2 = base.arm.l1, base.arm.l2
    local st_ = sub(target, S)
    local d = max(abs(l1 - l2) + 0.5, min(l1 + l2 - 0.3, len(st_)))
    local u = norm(st_); if not u then return end
    local b = norm(sub(pole, mul(u, dot(pole, u)))) or { 0.0, -1.0, 0.0 }
    if pb and pb[side] then
        local m = add(mul(pb[side], 0.65), mul(b, 0.35))
        b = norm(sub(m, mul(u, dot(m, u)))) or b          -- (kept square to the arm's line, or it shortened)
    end
    if pb then pb[side] = b end
    local ca = max(-1.0, min(1.0, (l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d)))
    local sa = sqrt(1.0 - ca * ca)
    local E = add(S, add(mul(u, l1 * ca), mul(b, l1 * sa)))
    local A = add(S, mul(u, d))
    local d0 = norm(sub(base[L].p, base[U].p)) or { 0.0, 0.0, -1.0 }
    local d0f = norm(sub(base[H].p, base[L].p)) or d0
    local dU = norm(sub(E, S)) or d0
    local dF = norm(sub(A, E)) or dU
    -- turned on from last frame's directions, never from scratch: consecutive frames are never opposite, so the
    -- turn is continuous by construction (from the base it snapped half a turn as the arm swept past straight);
    -- a gentle pull toward the from-base turn keeps the slow drift of stacked small turns bounded
    local a = pb[side .. "_acc"]
    if not a then a = { du = d0, qu = { 0.0, 0.0, 0.0, 1.0 }, df = d0f, qf = { 0.0, 0.0, 0.0, 1.0 } }; pb[side .. "_acc"] = a end
    a.qu = qmul(between(a.du, dU), a.qu); a.du = dU
    a.qf = qmul(between(a.df, dF), a.qf); a.df = dF
    if dot(d0, dU) > 0.2 then a.qu = nlerp(a.qu, between(d0, dU), 0.06) end
    if dot(d0f, dF) > 0.2 then a.qf = nlerp(a.qf, between(d0f, dF), 0.06) end
    -- (the pull only to turns that still land on the right direction: nlerp of two turns to the same spot stays there)
    out[U] = { p = S, q = qmul(a.qu, base[U].q) }
    out[L] = { p = E, q = qmul(a.qf, base[L].q) }
    out[H] = { p = A, q = qmul(a.qf, base[H].q) }
end

-- one leg in component space: straight down the body (-Z), swung `a` toward his front, the knee bent `k` back
local function leg_cs(out, side, a, k)
    local T, Ca, F = "thigh_" .. side, "calf_" .. side, "foot_" .. side
    local D = { 0.0, sin(a), -cos(a) }
    local bk = a - k
    local Dc = { 0.0, sin(bk), -cos(bk) }
    local Tp = base[T].p
    local Cp = add(Tp, mul(D, base.leg.l1))
    local Fp = add(Cp, mul(Dc, base.leg.l2))
    local d0 = norm(sub(base[Ca].p, base[T].p)) or { 0.0, 0.0, -1.0 }
    local q1 = turn_to(d0, D, { 0.0, 1.0, 0.0 })
    local d1 = norm(sub(base[F].p, base[Ca].p)) or d0
    local q2 = turn_to(d1, Dc, { 0.0, 1.0, 0.0 })
    out[T] = { p = Tp, q = qmul(q1, base[T].q) }
    out[Ca] = { p = Cp, q = qmul(q2, base[Ca].q) }
    out[F] = { p = Fp, q = qmul(q2, base[F].q) }
end

-- Every swim tick, after swim.lua has turned and tipped the mesh: speed (cm/s), stroke (just pressed), kicking (the
-- button held), resting (treading at the surface), yaw and pitch (degrees, the way he swims).
function M.update(dt, speed, stroke, kicking, resting, yaw, pitch)
    local F = package.loaded["footik"]
    local fs = F and F.debug and F.debug()
    if not (fs and fs.on and fs.pose) then return end
    local pose = fs.pose
    if not base then
        -- (once he has trodden water calmly most of a second: STORROR's fall and landing poses gone from the copy)
        M.calm = (resting and speed < 60.0) and (M.calm or 0.0) + dt or 0.0
        if M.calm > 0.8 then pcall(try_capture, pose) end
        if not base then return end
    end
    if not st then st = { t = 0.0, next = "l", strokes = {}, aw = 0.0, pb = {}, lp = 0.0 } end
    st.t = st.t + dt
    -- strokes: a press starts the next arm's, left then right; held, they take turns by themselves
    if stroke then
        st.strokes[st.next] = { ph = 0.0, len = STROKE_TIME }
        st.next = OTHER[st.next]
    end
    if kicking then
        local o = st.strokes[OTHER[st.next]]
        if not st.strokes[st.next] and (not o or o.ph >= 0.5) then
            st.strokes[st.next] = { ph = 0.0, len = KICK_STROKE_TIME }
            st.next = OTHER[st.next]
        end
    end
    local any = false
    for _, side in ipairs({ "r", "l" }) do
        local sk = st.strokes[side]
        if sk then
            sk.ph = sk.ph + dt / sk.len
            if sk.ph >= 1.0 then st.strokes[side] = nil else any = true end
        end
    end
    -- how much the arms swim rather than hang: strokes, the held kick, or good way on
    local busy = any or kicking or speed > 120.0
    st.aw = max(0.0, min(1.0, st.aw + (busy and dt * EASE_IN or -dt * EASE_IN)))

    local ok, err = pcall(function()
        local C = comp_frame(pose)
        local out = {}
        -- the trunk: as captured - still, square to the way he swims (the mesh carries the turn and the lean)
        for _, n in ipairs({ "pelvis", "spine_01", "spine_02", "spine_03", "spine_04", "spine_05",
                             "clavicle_l", "clavicle_r" }) do
            out[n] = { p = base[n].p, q = base[n].q }
        end
        -- the face along the way he swims: lifted from the chest by his heading against his body's lean
        local P = package.loaded["swimpose"]
        local ps = P and P.state and P.state()
        local lean = (ps and ps.lean) or 25.0
        local lift = max(-20.0, min(75.0, (pitch or 0.0) + lean))
        -- (treading water, he looks slowly about him: "also no idle animation", 2026-10-24)
        local look = 10.0 * sin(2.0 * pi * 0.15 * st.t) * (1.0 - st.aw)
        local turn = qmul(axis_angle({ 0.0, 0.0, 1.0 }, rad(look)), axis_angle({ 1.0, 0.0, 0.0 }, rad(lift - BASE_LIFT)))
        for _, part in ipairs({ { "neck_01", 0.5 }, { "head", 1.0 } }) do
            local e = base[part[1]]
            out[part[1]] = { p = e.p, q = qmul(nlerp({ 0.0, 0.0, 0.0, 1.0 }, turn, part[2]), e.q) }
        end
        -- the arms: the hand's spot eased between its natural hang and the glide or stroke, and the arm always
        -- solved whole to that spot - blending the solved bones instead shortened the forearm (the harness caught
        -- the arm at 6 cm of its 28)
        for _, side in ipairs({ "r", "l" }) do
            local sgn = side == "r" and -1.0 or 1.0          -- (his right is the body's -X)
            local sk = st.strokes[side]
            local want = sk and stroke_at(sk.ph) or GLIDE
            local S = base["upperarm_" .. side].p
            local target = add(S, { want[2] * sgn, want[3], want[1] })
            -- (not swimming, he treads water: both hands scull in front of his chest, out and in, a little forward
            -- and back - "also no idle animation", 2026-10-24; they hung still at his sides)
            local w = 2.0 * pi * 0.8 * st.t
            local scull = add(S, { (32.0 + 12.0 * sin(w)) * sgn, 22.0 + 6.0 * cos(w), -30.0 + 3.0 * sin(2.0 * w) })
            target = add(mul(scull, 1.0 - st.aw), mul(target, st.aw))
            -- (and never moved faster than a hand swims: the fade from a stroke to the hang swept it half the body
            -- in a blink)
            local tg = st.pb[side .. "_tg"]
            if tg then
                local d = sub(target, tg)
                local l = len(d)
                local most = 320.0 * dt
                if l > most then target = add(tg, mul(d, most / l)) end
            end
            st.pb[side .. "_tg"] = target
            -- the elbow: a continuous function of where the hand is - the lower the hand hangs, the further out from
            -- his side the elbow points; back toward his spine through the pull, up over his back as the hand comes
            -- round. (Any fixed direction flipped the elbow side to side as the hand swept past it: the harness's
            -- worst single-frame turn fell from 134 to under 20 degrees with this.)
            local rec = sk and max(0.0, min(1.0, (sk.ph - 0.55) / 0.3)) or 0.0
            if sk and sk.ph > 0.92 then rec = (1.0 - sk.ph) / 0.08 * rec end
            local down = max(0.0, min(1.0, (S[3] - target[3]) / 60.0))
            local pole = { (0.25 + 0.6 * down) * sgn, -0.6 + 0.4 * rec, -0.5 + 1.1 * rec }
            arm_cs(out, side, target, pole, st.pb)
        end
        -- the legs: swimming, a flutter from the hips, hard while the button is held; treading water, slow kicks
        -- in turn with his knees bent and thighs a little forward, eased between the two with the arms
        local amp, hz, knee = 14.0, 1.6, 16.0
        if kicking then amp, hz, knee = 22.0, 2.6, 26.0 end
        local idle = 1.0 - st.aw
        amp = amp + (12.0 - amp) * idle
        hz = hz + (0.8 - hz) * idle
        knee = knee + (24.0 - knee) * idle
        local fwd, bent = 12.0 * idle, 30.0 * idle
        st.lp = st.lp + 2.0 * pi * hz * dt           -- (the kick's phase carried on, so a change of pace never jumps)
        for _, L in ipairs({ { "l", 0.0 }, { "r", pi } }) do
            local phph = st.lp + L[2]
            leg_cs(out, L[1], rad(fwd + amp * sin(phph)), rad(bent + knee * (0.5 + 0.5 * sin(phph + pi / 2.0))))
        end
        -- written parent first, all from the one captured pose: nothing left for the animation to bend
        for _, n in ipairs(BONES) do
            local e = out[n]
            if e then
                local wp, wq = to_world(C, e.p, e.q)
                set_bone(pose, n, wp, wq, base[n].s)
            end
        end
    end)
    if not ok and not st.err then st.err = true; lib.log("swim body: %s", tostring(err)) end
    -- (his head's copy put on the neck as posed here: footik.lua M.swim_head)
    local Fh = package.loaded["footik"]
    if Fh and Fh.swim_head_sync then pcall(Fh.swim_head_sync) end
end

function M.reset() st = nil end
function M.rebase() base, st = nil, nil end       -- (tests: capture the pose afresh)

return M
