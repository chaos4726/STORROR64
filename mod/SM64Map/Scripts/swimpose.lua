-- SM64Map: how the athlete looks in the water.
--
-- STORROR has no swimming, and its animation system does not take animations from outside, so in the water
-- the athlete would just stand there. Instead his whole body is turned (swim.lua says how far): stretched out
-- along the way he is heading, head down when he dives and up when he rises, rocking with each stroke and
-- rolling while he kicks, upright and bobbing while he treads water at the surface.
--
-- Only the body is turned (the character's mesh, about the middle of its capsule): the character itself, its
-- collision and its movement stay as they are. Each change is gentle, so STORROR's physics does not take it
-- for a fall.
local lib = require("lib")
local P = {}

local sin, cos, rad, max, min, abs = math.sin, math.cos, math.rad, math.max, math.min, math.abs

local STROKE_DIP = 12.0             -- extra lean for a moment after a stroke
local ROLL = 14.0                   -- side to side with the strokes
local ROLL_HZ = 1.4                 -- strokes a second
local BOB = 4.0                     -- cm up and down while treading water
local EASE = 4.0                    -- how quickly he turns into a new position (per second)

local st = nil                      -- { mesh, loc, quat, lean, roll, t, flip }

local function to_quat(r)
    local p, y, ro = rad(r.Pitch) / 2.0, rad(r.Yaw) / 2.0, rad(r.Roll) / 2.0
    local sp, cp, sy, cy, sr, cr = sin(p), cos(p), sin(y), cos(y), sin(ro), cos(ro)
    return { cr * sp * sy - sr * cp * cy, -cr * sp * cy - sr * cp * sy, cr * cp * sy - sr * sp * cy, cr * cp * cy + sr * sp * sy }
end

local function to_rot(q)
    local x, y, z, w = q[1], q[2], q[3], q[4]
    local s = 2.0 * (w * y - z * x)
    return { Pitch = math.deg(math.asin(max(-1.0, min(1.0, s)))),
             Yaw = math.deg(math.atan(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z))),
             Roll = math.deg(math.atan(2.0 * (w * x + y * z), 1.0 - 2.0 * (x * x + y * y))) }
end

local function qmul(a, b)
    return { a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2],
             a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
             a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4],
             a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3] }
end

local function qrot(q, v)                           -- turn vector v by quaternion q
    local qv = { v[1], v[2], v[3], 0.0 }
    local qc = { -q[1], -q[2], -q[3], q[4] }
    local r = qmul(qmul(q, qv), qc)
    return r[1], r[2], r[3]
end

-- (A body's place is only taken up by the engine when the component is moved; moving it through the usual
-- calls hands back a hit result, which, called every tick, has brought this game down. Its own properties are
-- written instead, and its scale nudged by a hair, which makes the engine take the whole transform up again.)
local function apply(mesh, loc, rot, flip)
    pcall(function()
        mesh.RelativeLocation = loc
        mesh.RelativeRotation = rot
        local k = flip and 1.0001 or 1.0
        mesh:SetRelativeScale3D({ X = k, Y = k, Z = k })
    end)
end

local function begin(pawn)
    local mesh = pawn.Mesh
    if not (mesh and mesh:IsValid()) then return nil end
    local l, r = mesh.RelativeLocation, mesh.RelativeRotation
    return { mesh = mesh, pawn = pawn:GetAddress(), loc = { l.X, l.Y, l.Z }, rot = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll },
             quat = to_quat({ Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll }), lean = 0.0, roll = 0.0, t = 0.0, dip = 0.0, flip = false }
end

-- Every tick in the water. `lean`: how far forward his body should be (degrees: 0 upright, 90 stretched out,
-- more with his head down); `speed`: how fast he is going (cm/s); `stroke`: a stroke was just made;
-- `kicking`: the swim button is being held for a steady kick; `twist`: degrees his body is turned about the upright in
-- his capsule, after the rest (swim.lua: STORROR's turn of him taken back off).
function P.set(pawn, dt, lean, speed, stroke, kicking, twist)
    if not pawn then return end
    local addr = nil
    pcall(function() addr = pawn:GetAddress() end)
    if not st or st.pawn ~= addr or not pcall(function() return st.mesh:IsValid() end) then
        st = nil
        local ok, s = pcall(begin, pawn)
        if not (ok and s) then return end
        st = s
    end
    st.t = st.t + dt
    if stroke then st.dip = 1.0 end
    st.dip = max(0.0, st.dip - dt * 2.0)
    local want = lean + STROKE_DIP * st.dip
    st.lean = st.lean + (want - st.lean) * min(1.0, dt * EASE)
    -- a stroke rocks him once; a kick keeps him rolling gently from side to side
    local moving = min(1.0, speed / 300.0)
    local roll_want = 0.0
    if kicking then roll_want = ROLL * sin(st.t * ROLL_HZ * 2.0 * math.pi) end
    roll_want = roll_want + ROLL * 0.6 * st.dip * sin(st.dip * math.pi * 2.0)
    st.roll = st.roll + (roll_want - st.roll) * min(1.0, dt * 8.0)
    local bob = BOB * (1.0 - moving) * sin(st.t * 2.2)

    -- forward over about the athlete's right-hand axis, then roll about the way he faces
    local a = -rad(st.lean)
    local qt = { 0.0, sin(a / 2.0), 0.0, cos(a / 2.0) }
    local r = rad(st.roll)
    local qr = { sin(r / 2.0), 0.0, 0.0, cos(r / 2.0) }
    local tw = rad(twist or 0.0)
    local q = qmul({ 0.0, 0.0, sin(tw / 2.0), cos(tw / 2.0) }, qmul(qr, qt))
    local rot = to_rot(qmul(q, st.quat))
    -- (his place turned as the engine turns him: to_rot hands the engine a pitch and roll of the other sign than q's, so
    -- the body leaned one way and its place swung the other, and it slid off the capsule - 70 cm ahead treading, more
    -- stretched out: "body is getting away from the actual hitbox of the player", 2026-10-26. Turned by what the engine
    -- shows, his middle stays on the capsule's; how he leans is as it was.)
    local seen = qmul(to_quat(rot), { -st.quat[1], -st.quat[2], -st.quat[3], st.quat[4] })
    local x, y, z = qrot(seen, st.loc)
    st.flip = not st.flip
    apply(st.mesh, { X = x, Y = y, Z = z + bob }, rot, st.flip)
end

-- Out of the water: the body as it was.
function P.reset()
    if st then
        apply(st.mesh, { X = st.loc[1], Y = st.loc[2], Z = st.loc[3] }, st.rot, false)
    end
    st = nil
end

-- The map went: forget the body without touching it.
function P.forget() st = nil end

function P.state() return st end       -- (tests)

return P
