-- SM64Map: first person (the file select's FIRST PERSON switch).
--
-- STORROR has no first-person view of its athlete, so it is made here: a camera of the mod's own sits at his eyes
-- (just in front of his head bone) and looks where the player looks, the controller's view, so the right stick
-- still turns it and moving is still along the way he looks. His head, a mesh part of its own, is hidden so that
-- it does not fill the view; the rest of him stays, for looking down at. Off during the new-file opening, which
-- has its cameras, and outside a game. When it goes off, the view goes back to STORROR's own camera behind him.
--
-- The view turns with his body (asked 2026-10-14: "the head or camera isnt attached to the body example being when
-- doing a flip the camera stays horizontal"): his upper chest's turn away from how it sits while he stands is put
-- on top of where the player looks, so a flip goes head over heels, a roll rolls, a vault tips the view. Only
-- big turns count in full: the sway of walking, running and standing (under 20 degrees) is left out, and between
-- 20 and 45 degrees it comes in gradually. How the chest sits while he stands is measured whenever he stands
-- still, so it follows STORROR's own idle.
local lib = require("lib")
local log = lib.log
local M = {}

local EYES_FORWARD, EYES_UP = 14.0, 6.0     -- cm from the head bone to the eyes (9 at first; the user: "eye 14 cm")
-- How his face sits relative to his head bone, measured while he stands (a quaternion): in a flip the eyes are put in
-- front of the face the head bone shows, so that they never lag behind into his clothes.
local head_to_face = nil
local FOV = 105.0
-- How far down the player can look (degrees below level): not far enough to see his body, whose skin pieces have
-- gaps with the shirt hidden ("lock the camera from going to low so you cant see the holes in charater",
-- 2026-10-14). The camera manager's own limit (ViewPitchMin), put back when first person goes off.
local PITCH_MIN = -60.0                     -- (35 at first; "try 30"; "needs to go lower": 40; "also try 50"; "try 60 so I can see the feet")
local pitch_was = nil                           -- (90 at first; "increase the fov", 2026-10-14)
-- How fast the eyes follow the head, relative to him (per second): slowly on the ground, which takes most of the
-- bob of each step out ("lower the head bobbing", 2026-10-14), quickly in the air and in flips, so that the eyes
-- stay in his head as he turns over.
local FOLLOW_GROUND, FOLLOW_GROUND_UP, FOLLOW_MOVES = 4.0, 1.5, 25.0   -- (sideways, up and down, in moves)
local TURN_LOCKED = 60.0                    -- while a flip or roll is under way: locked on to the body
local TURN_FOLLOW = 30.0                    -- how fast the view takes up the body's turn (per second): no jitter
-- The view stays in front of him (asked 2026-10-14: "limit the view to the front of the body only so when finishing
-- a flip your not looking behind yourself"): at most LIMIT degrees either side of the way he faces. When his body
-- turns away (a flip, a turn, anything in the air) the view is brought round with it; when he stands and the player
-- turns the view past his shoulder, he turns with it. Not while he runs on the ground: STORROR turns a runner
-- towards where he is steered, relative to the view, so holding the view would send both spinning round.
local LIMIT = 90.0
-- (brought round to straight ahead of him, not to the edge, which left the view on his shoulder after a flip:
-- "it needs to be aimed in front of the body", 2026-10-14; eased in, so it does not jump)
local RECENTER = 12.0                       -- per second
local recentering = false
-- The view comes back round to the front of his body by itself ("make it so the head auto recenters to the front
-- of the body", 2026-10-14): once the right stick (or the mouse) has been left alone for AUTO_DELAY seconds, eased
-- at AUTO_RATE per second, never faster than AUTO_MAX degrees a second. Not while the stick is pulled back: STORROR
-- has no walking backwards, it turns him round to run towards the view, and bringing the view round after him
-- would only turn him round again, endlessly; once back is let go the view comes round to his front. Steered to
-- the side, he runs an arc, the view following him round. (A hard lock at 90 degrees was tried and taken out the
-- same day: pulling back then looked like walking forward.)
local AUTO_DELAY, AUTO_RATE, AUTO_MAX = 0.6, 2.0, 120.0
local BODY_TURN = 14.0                      -- how fast his body takes up the view's turn, standing (per second)
local STAND_EXACT, STAND_EASE = 20.0, 12.0  -- standing: within 20 degrees of the view exactly its way, further eased (per second)
local stand_yaw, stand_t = nil, -1.0        -- the way the standing turn last put him, and when
local CLIMB_FOLLOW, CLIMB_FOLLOW_UP = 2.0, 1.5   -- how fast the eyes follow his head while he climbs (per second)
-- (and the camera's own place eased too while he climbs, and for CLIMB_LINGER after: "it needs to be way smoother")
local CLIMB_WORLD, CLIMB_LINGER = 9.0, 0.35
-- (on a leash: never more than CLIMB_LEASH behind where the eyes would be - eased further, the camera fell back into his
-- neck and his body showed: "body is showing up during climbing now", 2026-10-22)
local CLIMB_LEASH = 6.0
local function leash(a, b, most)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if d <= most then return a end
    local k = most / d
    return { X = b.X + dx * k, Y = b.Y + dy * k, Z = b.Z + dz * k }
end
local climb_cam, climb_t = nil, -1.0
local CLIMB_AFTER, climb_last, CLIMB_SOFT = 0.8, -1.0, 6.0
-- Rolls (a landing's, a dive's, a front roll): the view eases after his body's turn instead of locking on to it, and the
-- eyes after his head, on CLIMB_LEASH - "rolls are still very ridgid", 2026-10-22
local ROLL_FOLLOW, ROLL_EYES = 10.0, 8.0
local SWING_FOLLOW, SWING_LEAVE = 14.0, 6.0  -- how fast the view takes up his swing on a bar, and lets it go after (per second)
local swing_ref, swung = nil, nil           -- how he hung as the swing began; the swing as the view has it
local FLY_AHEAD = 18.0                      -- cm in front of his head along his body while he flies (see flying)
-- In the water ("swimming in first person is really bad right now", 2026-10-14): swimpose.lua lays his body out
-- along the way he swims and rocks it with every stroke, which the view took for a flip, tipping over with him and
-- shaking at each stroke. While he swims the view looks the way he swims instead (swim.lua's heading: its turns
-- and its dives are carried into the view), the right stick still looks round, and once it is left alone for
-- AUTO_DELAY the view comes back to the heading at SWIM_FOLLOW per second. He dives as steeply as SWIM_PITCH_MIN.
local SWIM_FOLLOW = 3.0
local SWIM_PITCH_MIN = -80.0
local swim_last = nil                       -- the heading last tick, { yaw, pitch }
-- Sliding (STORROR's slope slide, and slide.lua carrying him on along a flat): "sliding in first person is very hard
-- because the camera keeps moving around" (2026-10-21), then "the camera just goes everywhere because sometimes the
-- charater spins around while sliding" (2026-10-22). His slide pose leans and sways him (taken for a flip: the view
-- tipped and rolled with him), STORROR spins him round on the slope, his head swings up to 60 cm about him, STORROR
-- tips the view down as he goes, and the view was kept to the way his body faced. While he slides the view is the
-- player's and level: no body turn, not kept to his facing; the pitch held unless the right stick moves it; left alone
-- for SLIDE_DELAY, it comes round to the way he is going (SLIDE_FOLLOW a second, at most SLIDE_MAX degrees a second);
-- the eyes steady over the middle of him, SLIDE_ABOVE over his head's height, risen to quickly and let down slowly.
-- (Tried 2026-10-21 for every move, it tipped flips - his stance was measured in the slide pose; now only while he
-- slides, and his stance is not measured then.)
local SLIDE_DELAY, SLIDE_FOLLOW, SLIDE_MAX = 0.3, 3.0, 150.0
local SLIDE_ABOVE, SLIDE_RISE, SLIDE_SINK = 12.0, 10.0, 2.5
local SLIDE_LINGER = 0.6                    -- seconds still taken as sliding after it (a bump's hop mid-slide)
local slide_t, slide_pitch = nil, nil       -- when last seen sliding; the pitch held
local quiet = 0.0                           -- seconds since the view was last turned by the player
local move_facing = nil                     -- the way he faced last tick (a move turning him turns the view too)
local LAND_HOLD, land_hold = 0.35, 0.0      -- seconds after landing out of a move still taken as in the air
local BODY_BONE = "spine_05"                -- the upper chest: turns with the body, not with the head's own looks
-- body turns below FROM are left out, in full from FULL: in the air (flips) from 20 to 45 degrees; on the ground
-- only the biggest (rolls), from 70 to 110, as running sways and leans the chest well past 20 and that tipped the
-- view at every stride ("the head bobbing is still really bad", 2026-10-14). The one eases into the other.
-- (in the air, the 20 left out is made up gradually, by 100 - from 20 to 45 it was all made up at once, and as a
-- move began the view turned up to three times as fast as his body: "now the start of the roundoff as well",
-- 2026-10-22. See air_part.)
local AIR_FROM, AIR_FULL = 20.0, 100.0
local GROUND_FROM, GROUND_FULL = 70.0, 110.0
-- The walls and floors the view stays off (cm): the eyes are put back along the way from the middle of him when a
-- wall stands across it, and up off the floor under them ("head clips through walls and floors", 2026-10-22)
local WALL_GAP, FLOOR_GAP = 8.0, 10.0
local WALL_ROOM = 8.0                       -- cm kept from every wall around the eyes
-- ...and never put back more than BACK_MOST from where the eyes would be: 20 cm off the walls put them back into his
-- neck and shirt ("now the camera gets stuck in the body when too close to a wall", 2026-10-22). Instead the picture
-- starts NEAR_CLIP from the eyes while first person is on (the engine's own 10 elsewhere: r.SetNearClipPlane), so
-- the eyes can come that much nearer a wall without seeing through it.
local BACK_MOST, NEAR_CLIP, NEAR_CLIP_WAS = 12.0, 3.0, 10.0
local near_t = nil                          -- when the near clip was last set (nil: not ours)
local cam, head, was_on = nil, nil, false
-- What else is hidden in first person: his shirt (a cloth of its own, TorsoCloth, which the camera saw through from
-- inside) and his hair, brows, beard and moustache (grooms on the head, still drawn with the head hidden). His arms
-- and stomach stay (the user, 2026-10-14: "well no you got rid of the arms and stomach", then, when the shirt came
-- back with them, "why'd the shirt come back"; hiding bones also pulled the head bone, and the view, to his waist).
-- (the shirt is shown again: "add the shirt back", 2026-10-14, after a while hidden)
local HIDE_PARTS = { HairGroom = true, BrowsGroom = true, MustacheGroom = true, BeardGroom = true }
-- (His shirt was swapped for a double-sided stand-in for a while, 2026-10-14, to "hide the holes": wrongly, as
-- STORROR's clothing materials are double-sided already. The holes are real gaps: under his clothes STORROR's body
-- is only a stomach and forearms, m_med_nrw_stomach_forearms_only.)
local hidden = nil                          -- { parts = {...}, mesh = body mesh } while hidden
local hide_t = 0.0
local rest = nil                            -- the chest's rotation, relative to him, while he stands (a quaternion)
local REMEASURE = 1.5                       -- seconds standing still, chest steady: rest measured again (see body_turn)
local rest_last, still_t = nil, 0.0
-- The body's turn is followed only while it is turning fast (a flip, a roll under way): once it settles, even bent
-- over as he comes out of a flip, the view eases back to straight ahead (the bend that stays at the end of a flip
-- left the view on his shoulders: "it needs to be aimed in front of the body", 2026-10-14).
local FAST = 90.0                           -- degrees a second: turning faster than this is a move under way
local ACT_IN, ACT_OUT = 20.0, 3.0           -- how fast following starts, and fades once he settles (per second)
local active, last_d = 0.0, nil
local eyes = nil                            -- where the eyes are kept, relative to him (smoothed)
local last_cam = nil
local air = 0.0                             -- 0 on the ground, 1 in the air, eased between
local turned = nil                          -- the body's turn as the view has it (smoothed)

local function valid(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

-- ------------------------------------------------------------------ rotations (quaternions as {x, y, z, w})
-- (Unreal's own conversions, FRotator::Quaternion and FQuat::Rotator; a * b is b first, then a)
local D2R, R2D = math.pi / 180.0, 180.0 / math.pi

local function quat(p, y, r)
    local sp, cp = math.sin(p * D2R / 2), math.cos(p * D2R / 2)
    local sy, cy = math.sin(y * D2R / 2), math.cos(y * D2R / 2)
    local sr, cr = math.sin(r * D2R / 2), math.cos(r * D2R / 2)
    return { x = cr * sp * sy - sr * cp * cy, y = -cr * sp * cy - sr * cp * sy,
             z = cr * cp * sy - sr * sp * cy, w = cr * cp * cy + sr * sp * sy }
end

local function rotator(q)
    local test = q.z * q.x - q.w * q.y
    local yaw = math.atan(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z)) * R2D
    local pitch, roll
    if test < -0.4999995 then
        pitch = -90.0
        roll = -yaw - 2 * math.atan(q.x, q.w) * R2D
    elseif test > 0.4999995 then
        pitch = 90.0
        roll = yaw - 2 * math.atan(q.x, q.w) * R2D
    else
        pitch = math.asin(2 * test) * R2D
        roll = math.atan(-2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y)) * R2D
    end
    roll = (roll + 180.0) % 360.0 - 180.0
    return { Pitch = pitch, Yaw = yaw, Roll = roll }
end

local function mul(a, b)
    return { w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
             x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
             y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
             z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w }
end

local function inv(q) return { x = -q.x, y = -q.y, z = -q.z, w = q.w } end

local function rotate(q, v)                 -- q applied to the vector v
    local r = mul(mul(q, { x = v.X, y = v.Y, z = v.Z, w = 0.0 }), inv(q))
    return { X = r.x, Y = r.y, Z = r.z }
end

local function normalize(q)
    local n = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    if n < 1e-9 then return { x = 0, y = 0, z = 0, w = 1 } end
    return { x = q.x / n, y = q.y / n, z = q.z / n, w = q.w / n }
end

-- part of a rotation: the same axis, `k` of the angle
local function part(q, k)
    if q.w < 0 then q = { x = -q.x, y = -q.y, z = -q.z, w = -q.w } end
    local half = math.acos(math.max(-1.0, math.min(1.0, q.w)))
    local s = math.sin(half)
    if s < 1e-6 then return { x = 0, y = 0, z = 0, w = 1 } end
    local h = half * k
    local f = math.sin(h) / s
    return { x = q.x * f, y = q.y * f, z = q.z * f, w = math.cos(h) }
end

local function angle_of(q)                  -- degrees
    return 2 * math.acos(math.min(1.0, math.abs(q.w))) * R2D
end

-- the way from a to b, a step `k` of it
local function toward(a, b, k)
    if a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w < 0 then b = { x = -b.x, y = -b.y, z = -b.z, w = -b.w } end
    return normalize({ x = a.x + (b.x - a.x) * k, y = a.y + (b.y - a.y) * k, z = a.z + (b.z - a.z) * k, w = a.w + (b.w - a.w) * k })
end

-- ------------------------------------------------------------------
-- walking on the ground (CharacterMovement's mode Walking or NavWalking): STORROR's own moves, its flips among
-- them, may use other modes without ever "falling"
local function on_ground(pawn)
    local ok, mode = pcall(function() return pawn.CharacterMovement.MovementMode end)
    return ok and (mode == 1 or mode == 2)
end

-- the last few seconds of the camera, to read back after a move that did not look right
local trace, trace_n = {}, 0
local function note(fmt, ...)
    trace_n = trace_n % 400 + 1
    trace[trace_n] = string.format("%.2f ", os.clock()) .. string.format(fmt, ...)
end

-- Which way he faces. STORROR turns the whole of him over in a flip (the actor itself pitches round, seen
-- 2026-10-14), and past straight up the actor's yaw reads half a turn off; so the way he faces is taken only while
-- he is upright, and kept from then while he is upside down or on his side.
local facing = nil
local function facing_of(pawn)
    local ar = pawn:K2_GetActorRotation()
    local upright = math.abs(ar.Pitch) < 60.0 and math.abs(ar.Roll) < 60.0
    if upright or not facing then facing = ar.Yaw end
    return facing, upright, ar
end

local function analog(pc, key)
    local v = 0.0
    pcall(function() v = pc:GetInputAnalogKeyState({ KeyName = FName(key) }) end)
    return type(v) == "number" and v or 0.0
end

local function key_down(pc, key)
    local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(key) }) end)
    return ok and v == true
end

-- the view's way, kept in front of him (returns the control rotation to use)
local function wrap(a) return (a + 540.0) % 360.0 - 180.0 end

-- swim.lua's state while he swims ({ yaw, pitch, ... }), else nil
local function swimming()
    local S = package.loaded["swim"]
    if not (type(S) == "table" and S.state) then return nil end
    local ok, sw = pcall(S.state)
    if ok and type(sw) == "table" and type(sw.yaw) == "number" and type(sw.pitch) == "number" then return sw end
    return nil
end

-- the view in the water (returns the control rotation to use): see SWIM_FOLLOW
local function swim_view(pc, sw, dt)
    local step = math.max(dt or 0.016, 0.001)
    local rot = pc:GetControlRotation()
    local yaw, pitch = rot.Yaw, wrap(rot.Pitch)
    if swim_last then
        yaw = yaw + wrap(sw.yaw - swim_last.yaw)
        pitch = pitch + (sw.pitch - swim_last.pitch)
    end
    swim_last = { yaw = sw.yaw, pitch = sw.pitch }
    local looking = math.abs(analog(pc, "Gamepad_RightX")) > 0.15 or math.abs(analog(pc, "Gamepad_RightY")) > 0.15
        or math.abs(analog(pc, "MouseX")) > 0.0 or math.abs(analog(pc, "MouseY")) > 0.0
    if looking then quiet = 0.0 else quiet = quiet + step end
    if quiet >= AUTO_DELAY then
        local k = 1.0 - math.exp(-SWIM_FOLLOW * step)
        yaw = yaw - wrap(yaw - sw.yaw) * k
        pitch = pitch - (pitch - sw.pitch) * k
    end
    pitch = math.max(SWIM_PITCH_MIN, math.min(80.0, pitch))
    local kept = { Pitch = pitch, Yaw = yaw, Roll = 0.0 }
    pcall(function() pc:SetControlRotation(kept) end)
    return kept
end

-- sliding: STORROR's slope slide, or slide.lua carrying him
local function sliding_now(pawn)
    local yes = false
    pcall(function()
        local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
        local n = (m and m:IsValid()) and m:GetFName():ToString():lower() or ""
        yes = n:find("fallingslide_slope") ~= nil
    end)
    if not yes then
        local S = package.loaded["slide"]
        if type(S) == "table" and S.active then
            local ok, a = pcall(S.active)
            yes = ok and a == true
        end
    end
    return yes
end

-- the view while he slides (returns the control rotation to use): see SLIDE_DELAY
local function slide_view(pc, pawn, dt)
    local step = math.max(dt or 0.016, 0.001)
    local rot = pc:GetControlRotation()
    local yaw, pitch = rot.Yaw, wrap(rot.Pitch)
    if math.abs(analog(pc, "Gamepad_RightY")) > 0.15 or math.abs(analog(pc, "MouseY")) > 0.0 or not slide_pitch then
        slide_pitch = pitch
    end
    pitch = slide_pitch
    local looking = math.abs(analog(pc, "Gamepad_RightX")) > 0.15 or math.abs(analog(pc, "MouseX")) > 0.0
    if looking then quiet = 0.0 else quiet = quiet + step end
    if quiet >= SLIDE_DELAY then
        local v = pawn:GetVelocity()
        if v.X * v.X + v.Y * v.Y > 150.0 * 150.0 then
            local d = wrap(math.atan(v.Y, v.X) * R2D - yaw)
            local turn = d * (1.0 - math.exp(-SLIDE_FOLLOW * step))
            local most = SLIDE_MAX * step
            if turn > most then turn = most elseif turn < -most then turn = -most end
            yaw = yaw + turn
        end
    end
    local kept = { Pitch = pitch, Yaw = yaw, Roll = 0.0 }
    pcall(function() pc:SetControlRotation(kept) end)
    return kept
end

local function keep_in_front(pc, pawn, rot, grounded, dt)
    local body, upright = nil, false
    pcall(function() body, upright = facing_of(pawn) end)
    if not body or not upright then return rot end         -- (not in the middle of a flip)
    local d = (rot.Yaw - body + 540.0) % 360.0 - 180.0
    local looking = math.abs(analog(pc, "Gamepad_RightX")) > 0.15 or math.abs(analog(pc, "MouseX")) > 0.0
    local steering = math.abs(analog(pc, "Gamepad_LeftX")) > 0.2 or math.abs(analog(pc, "Gamepad_LeftY")) > 0.2
        or key_down(pc, "W") or key_down(pc, "A") or key_down(pc, "S") or key_down(pc, "D")
    local back = analog(pc, "Gamepad_LeftY") < -0.3 or key_down(pc, "S")
    if looking or back then quiet = 0.0 else quiet = quiet + (dt or 0.016) end
    -- (on the ground, standing, with no move of STORROR's playing, he faces where the view looks - turned with it as
    -- the stick turns it, and kept so: "is it possible to make the player turn when moving the right stick ... in first
    -- person", then "its turning him but its also ripping him back", 2026-10-22 - STORROR turns a standing athlete back
    -- to the way he last moved, about 200 degrees a second, so his facing is set again every tick while he stands. Quick
    -- but eased: BODY_TURN a second. Once he moves, or a move plays, STORROR has him again.)
    if grounded and not steering then
        local playing, still = false, false
        pcall(function()
            local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
            playing = m ~= nil and m:IsValid()
            local v = pawn:GetVelocity()
            still = (v.X * v.X + v.Y * v.Y) < 60.0 * 60.0
            -- (never in the air - "make sure in the air you cant turn your body like that", 2026-10-22: a jump's first
            -- frames still count as walking, but he is already going up)
            if math.abs(v.Z) > 50.0 then playing = true end
        end)
        if not playing and (still or looking) then
            recentering = false
            -- (exactly the view's way, every tick: eased, STORROR's pull back held him some 14 degrees short of it - "he's
            -- not facing fully forward when looking around"; the stick turns the view smoothly, so he turns smoothly)
            local yaw = rot.Yaw
            -- (a big way round - out of STORROR's turn on the spot, or out of a run sideways, his body up to 90 degrees
            -- from the view - eased, STAND_EASE a second, from where we last put him: turned at once, his head, off the
            -- middle of him, took the camera 10 cm sideways in a frame - "still a slight snap", 2026-10-22. Within
            -- STAND_EXACT of the view, as the stick turns it, exactly the view's way.)
            -- (from where this last put him, a moment ago - not where STORROR has pulled him back to since: from there,
            -- his pull won and he stayed 60 to 90 degrees behind a turning view, "the right joystick isnt moving the body
            -- anymore", 2026-10-22)
            local cur = nil
            pcall(function() cur = facing_of(pawn) end)
            local now = os.clock()
            local mine = stand_yaw and now - stand_t < 0.25 and cur and math.abs(wrap(stand_yaw - cur)) < 45.0
            local from = mine and stand_yaw or cur or yaw
            local gap = wrap(yaw - from)
            if math.abs(gap) > STAND_EXACT then
                yaw = from + gap * (1.0 - math.exp(-STAND_EASE * math.max(dt or 0.016, 0.001)))
            end
            pcall(function() pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false) end)
            facing, stand_yaw, stand_t = yaw, yaw, now
            return rot
        end
    end
    if recentering and (looking or (grounded and steering) or math.abs(d) < 2.0) then recentering = false end
    if not recentering then
        if math.abs(d) <= LIMIT or (grounded and steering) then
            -- (left alone: round to his front, see AUTO_DELAY; running past the edge too, see LIMIT)
            if quiet < AUTO_DELAY or math.abs(d) < 0.5 then return rot end
            local step = math.max(dt or 0.016, 0.001)
            local turn = d * (1.0 - math.exp(-AUTO_RATE * step))
            local most = AUTO_MAX * step
            if turn > most then turn = most elseif turn < -most then turn = -most end
            local kept = { Pitch = rot.Pitch, Yaw = rot.Yaw - turn, Roll = rot.Roll }
            pcall(function() pc:SetControlRotation(kept) end)
            return kept
        end
        if grounded and looking then
            -- standing, the view turned past his shoulder: he turns with it
            local side = d > 0 and LIMIT or -LIMIT
            pcall(function() pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = rot.Yaw - side, Roll = 0.0 }, false) end)
            return rot
        end
        -- (on the ground, stopping out of a run with his body turned away from the view - run sideways, STORROR faces him
        -- the way he runs - the view is left where it is: swung round to him, it snapped 90 to 110 degrees in a quarter of
        -- a second as the stick was let go, "camera snaping", 2026-10-22. Once he stands he is turned to the view.)
        if grounded then return rot end
        recentering = true                  -- his body turned away from the view: round to in front of him
    end
    local kept = { Pitch = rot.Pitch, Yaw = rot.Yaw - d * (1.0 - math.exp(-RECENTER * (dt or 0.016))), Roll = rot.Roll }
    pcall(function() pc:SetControlRotation(kept) end)
    return kept
end

local function head_part(pawn)
    for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.SkeletalMeshComponent"))) do
        local o = c:get()
        if o:GetFName():ToString() == "Head" then return o end
    end
    return nil
end

local function hide_body(pawn, on)
    if on then
        if hidden then
            -- (put back again now and then: STORROR shows its parts again after some of its own moves)
            for _, c in ipairs(hidden.parts) do pcall(function() if c:IsVisible() then c:SetHiddenInGame(true, false) end end) end
            return
        end
        hidden = { parts = {}, mesh = pawn.Mesh }
        pcall(function()
            for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.PrimitiveComponent"))) do
                local o = c:get()
                -- (only those showing: put back on the way out of first person, a part hidden before - Mario's look
                -- hides his beard - came back with them, 2026-10-29)
                if HIDE_PARTS[o:GetFName():ToString()] and not o.bHiddenInGame then
                    pcall(function() o:SetCastHiddenShadow(true) end)
                    o:SetHiddenInGame(true, false)
                    hidden.parts[#hidden.parts + 1] = o
                end
            end
        end)
        log("first person: %d parts of him hidden (hair)", #hidden.parts)
    elseif hidden then
        for _, c in ipairs(hidden.parts) do pcall(function() if c:IsValid() then c:SetHiddenInGame(false, false) end end) end
        hidden = nil
    end
end

local function near_clip(cm)
    pcall(function()
        local KSL = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        KSL:ExecuteConsoleCommand(lib.world(), string.format("r.SetNearClipPlane %g", cm), lib.controller())
    end)
end

local function off(pawn)
    if near_t then near_t = nil; near_clip(NEAR_CLIP_WAS) end
    -- (this camera still the view, off: back to him, the game's own camera behind him - every frame, not only as it
    -- goes off: turned off with a menu up, the menu gave the view back to this camera as it shut, and it stood still
    -- there, "the cameras stuck in 3rd person mode", 2026-10-22. Him, not the STORROR camera it may have taken the view
    -- from: those are its missions' cameras, placed about the city - "the camera is out of bounds in 3rd person")
    pcall(function()
        local pc = lib.controller()
        if pc and pawn and valid(cam) and pc:GetViewTarget():GetAddress() == cam:GetAddress() then
            pc:SetViewTargetWithBlend(pawn, 0.0, 0, 0.0, false)
        end
    end)
    if not was_on then return end
    was_on = false
    move_facing = nil
    local pc = lib.controller()
    if pitch_was then
        pcall(function() pc.PlayerCameraManager.ViewPitchMin = pitch_was end)
        pitch_was = nil
    end
    if valid(head) then pcall(function() head:SetHiddenInGame(false, false) end) end
    head = nil
    hide_body(pawn, false)
end

-- the body's turn away from standing, in the world, as much of it as counts (a quaternion)
local function body_turn(pawn, from_deg, full_deg, dt)
    local a, b, tilt = nil, nil, "?"
    pcall(function()
        local yaw, _, ar = facing_of(pawn)
        local br = pawn.Mesh:GetSocketRotation(FName(BODY_BONE))
        -- (his facing only: STORROR tips the whole of him over in a flip, and that is part of the turn too)
        a, b = quat(0.0, yaw, 0.0), quat(br.Pitch, br.Yaw, br.Roll)
        tilt = string.format("%.0f/%.0f", ar.Pitch, ar.Roll)
    end)
    if not (a and b) then return nil end
    local here = mul(inv(a), b)             -- the chest, relative to him
    -- standing still on the ground: that is how the chest sits (followed gently, as STORROR's idle moves)
    local still = false
    pcall(function()
        local v = pawn:GetVelocity()
        still = on_ground(pawn) and (v.X * v.X + v.Y * v.Y + v.Z * v.Z) < 40.0 * 40.0
    end)
    -- (and the chest near how it sat: a flip done on the spot, Y on the pad, is slow and may not count as falling,
    -- and was taken for standing, so the measure followed the flip round and the view never turned, 2026-10-14
    -- "the camera isnt locking in when doing flips with Y on controller")
    -- (but standing quite still, his chest steady, for REMEASURE seconds: measured again however far off it was - a
    -- pose held still once dragged it away from his idle, past 25 degrees, and stuck there, every flip then tipped
    -- to one side: "kinda tilting his head to the left or right a bit", 2026-10-21)
    local spin = rest_last and angle_of(mul(here, inv(rest_last))) / math.max(dt or 0.016, 0.001) or 0.0
    rest_last = here
    if still and spin < 30.0 then still_t = still_t + (dt or 0.016) else still_t = 0.0 end
    -- (the first measure too only once he has stood still a moment: at a fresh start the first still tick could be
    -- a landing or getting-up pose, and every flip was tipped until it was measured again)
    if still and ((not rest and still_t > 0.5) or (rest and angle_of(mul(here, inv(rest))) < 25.0) or still_t > REMEASURE) then
        rest = rest and toward(rest, here, 0.2) or here
    end
    if not rest then return nil end
    local d = mul(here, inv(rest))          -- the turn, relative to him
    local deg = angle_of(d)
    local step = math.max(dt or 0.016, 0.001)
    local speed = last_d and angle_of(mul(d, inv(last_d))) / step or 0.0
    last_d = d
    if speed > FAST then
        active = active + (1.0 - active) * (1.0 - math.exp(-ACT_IN * step))
    else
        active = active * math.exp(-ACT_OUT * step)
    end
    note("mode %s actor %s body %.0f speed %.0f active %.2f", tostring(pawn.CharacterMovement.MovementMode), tilt, deg, speed, active)
    -- how much of the turn the view takes (degrees): on the ground none below GROUND_FROM, in full from GROUND_FULL,
    -- eased; in the air a smooth curve from none at AIR_FROM to the whole of it at AIR_FULL, never turning more than
    -- 1.6 times as fast as he does; the one eased into the other as he leaves the ground or lands
    local function ground_part(x)
        if x <= GROUND_FROM then return 0.0 end
        local u = math.min(1.0, (x - GROUND_FROM) / (GROUND_FULL - GROUND_FROM))
        return x * u * u * (3 - 2 * u)
    end
    local function air_part(x)
        if x <= AIR_FROM then return 0.0 end
        if x >= AIR_FULL then return x end
        local L = AIR_FULL - AIR_FROM
        local u = (x - AIR_FROM) / L
        return AIR_FULL * (3 * u * u - 2 * u * u * u) + L * (u * u * u - u * u)
    end
    local shown = ground_part(deg) + (air_part(deg) - ground_part(deg)) * air
    if shown <= 0.0 then return nil end
    local k = shown / deg * active          -- (only while the move is under way)
    if k < 0.002 then return nil end
    return mul(mul(a, part(d, k)), inv(a))  -- in the world
end

-- The eyes at `p` (world cm), kept off the level's walls and floors (see WALL_GAP): back along the way from the middle
-- of him (his capsule, never inside a wall) to before the first wall across it, and up off the floor under them.
local function clear_of_level(pawn, p)
    local G = package.loaded["game"]
    if not (type(G) == "table" and G.wall_cut and G.floor_z) then return p end
    local out = p
    pcall(function()
        local O = lib.OFFSET
        local c = pawn:K2_GetActorLocation()
        local ax, ay, az = c.X - O.X, c.Y - O.Y, c.Z - O.Z
        local bx, by, bz = p.X - O.X, p.Y - O.Y, p.Z - O.Z
        local dx, dy, dz = bx - ax, by - ay, bz - az
        local len = math.sqrt(dx * dx + dy * dy + dz * dz)
        if len > 1.0 then
            -- (to WALL_GAP past the eyes, so a wall just beyond them counts too)
            local reach = (len + WALL_GAP) / len
            local t = G.wall_cut(ax, ay, az, ax + dx * reach, ay + dy * reach, az + dz * reach)
            if t < 1.0 then
                local k = math.max(0.0, math.min(1.0, (t * reach * len - WALL_GAP) / len))
                bx, by, bz = ax + dx * k, ay + dy * k, az + dz * k
            end
        end
        -- (and pushed off any wall nearer than WALL_ROOM all round: side on to a wall, or leaning into it on a wall
        -- run or a ledge, the way from him did not cross it, yet the picture's near edge, 13 cm out at the sides,
        -- went through it - "camera still going through walls", 2026-10-22)
        if G.wall_near then
            for _ = 1, 2 do
                local hit, px, py = G.wall_near(bx, by, bz, WALL_ROOM)
                if not hit then break end
                bx, by = bx + px, by + py
            end
        end
        -- (the floor under the eyes no higher than the middle of him: a floor above is not his)
        local fz = G.floor_z(bx, by, math.min(bz + 50.0, az))
        if fz and bz < fz + FLOOR_GAP then bz = fz + FLOOR_GAP end
        -- (at most BACK_MOST from the eyes, so never into him)
        local ex, ey, ez = p.X - O.X, p.Y - O.Y, p.Z - O.Z
        local mx, my, mz = bx - ex, by - ey, bz - ez
        local moved = math.sqrt(mx * mx + my * my + mz * mz)
        if moved > BACK_MOST then
            local k = BACK_MOST / moved
            bx, by, bz = ex + mx * k, ey + my * k, ez + mz * k
        end
        out = { X = bx + O.X, Y = by + O.Y, Z = bz + O.Z }
    end)
    return out
end

-- ...and then off everything solid the game has, not only the level's own walls - doors, platforms, props ("can see
-- through walls in first person", 2026-10-22): a ball of EYE_BALL swept from his head bone (inside his unseen head)
-- out to the eyes on the game's camera channel, the eyes put where it stops. So the eyes are never further back than
-- his head, never in his body, never in anything.
local EYE_BALL = 6.0
local function swept(pawn, p)
    local out = p
    pcall(function()
        local h = pawn.Mesh:GetSocketLocation(FName("Head"))
        local KSL = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        local hit = {}
        local none = { R = 0, G = 0, B = 0, A = 0 }
        local blocked = KSL:SphereTraceSingle(lib.world(), h, p, EYE_BALL, 1, false, { pawn }, 0, hit, true, none, none, 0.0)
        if blocked then
            local l = hit.Location
            out = { X = l.X, Y = l.Y, Z = l.Z }
        end
    end)
    return out
end

-- Every tick of the game. `on`: the switch, and nothing else holding the camera.
function M.update(dt, pawn, on)
    if not (on and pawn) then off(pawn); return end
    local pc, world = lib.controller(), lib.world()
    if not (pc and world) then return end
    if not valid(cam) then
        cam = world:SpawnActor(StaticFindObject("/Script/Engine.CameraActor"), pawn:K2_GetActorLocation(), { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
        if not valid(cam) then cam = nil; return end
        pcall(function() lib.keep[cam:GetAddress()] = true end)       -- (it outlives a change of scene)
        pcall(function() cam.CameraComponent:SetFieldOfView(FOV) end)
        -- (no motion blur: STORROR's, made for a camera behind him, smeared the whole picture at every turn)
        pcall(function()
            local cc = cam.CameraComponent
            cc.PostProcessBlendWeight = 1.0
            local pp = cc.PostProcessSettings
            pp.bOverride_MotionBlurAmount = true
            pp.MotionBlurAmount = 0.0
            pp.bOverride_MotionBlurMax = true
            pp.MotionBlurMax = 0.0
        end)
        eyes = nil
        log("first person: on")
    end
    if not valid(head) then
        local ok, h = pcall(head_part, pawn)
        head = ok and h or nil
        -- (hidden, his head still casts its shadow: gone, his shadow on the ground had no head - "also no head shadow on
        -- the ground", 2026-10-22)
        if head then pcall(function() head:SetCastHiddenShadow(true); head:SetHiddenInGame(true, false) end) end
    end
    was_on = true
    -- (set again every few seconds: a change of map or STORROR's settings may put the engine's back)
    if not near_t or os.clock() - near_t > 3.0 then near_t = os.clock(); near_clip(NEAR_CLIP) end
    local sw = swimming()
    pcall(function()
        local pcm = pc.PlayerCameraManager
        local want = sw and SWIM_PITCH_MIN or PITCH_MIN
        if pcm.ViewPitchMin ~= want then
            pitch_was = pitch_was or pcm.ViewPitchMin
            pcm.ViewPitchMin = want
        end
    end)
    hide_t = (hide_t or 0) - (dt or 0.016)
    if hide_t <= 0 or not hidden then hide_t = 1.0; hide_body(pawn, true) end
    local grounded = on_ground(pawn)
    -- (climbing - pulling up over a ledge, a wall pop, a run up, hanging - his chest bends 80 degrees and back in a third
    -- of a second, and the view went with it: "when climbing his neck snaps down really fast then back up", 2026-10-22.
    -- The view stays where it is aimed while he climbs, as while he swims.)
    local climbing = false
    pcall(function()
        local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
        local n = (m and m:IsValid()) and m:GetFName():ToString():lower() or ""
        climbing = n:find("climb") ~= nil or n:find("ledge") ~= nil or n:find("hang") ~= nil or n:find("wallpop") ~= nil
            or n:find("runup") ~= nil or n:find("pullup") ~= nil or n:find("mantle") ~= nil or n:find("shimmy") ~= nil
    end)
    -- (on a tree or a pole - climb.lua's: held on the trunk, hanging from its top, going over it - the same: the view
    -- was turned with him as he went round the trunk, and his climb-up onto the top is a montage of no name -
    -- "climbing trees ... forces the camera to the right direction make it free", "when climbing to the top the camera
    -- freaks out", 2026-10-22. Its Pole 180 jump off turns the view with him, as STORROR's own moves do.)
    local tree = nil
    pcall(function() local C = package.loaded["climb"]; if C and C.phase then tree = C.phase() end end)
    if tree and tree ~= "jump" then climbing = true end
    -- (swinging on a bar or a pole - STORROR's own movement mode for it, custom (6), no move playing: it turns the whole
    -- of him round the bar. His chest's turn taken into the view whipped it round and back up to 115 degrees, "when pole
    -- swinging the camera shakes hard and you can see the body"; then held level, the eyes sat in his chest at the top of
    -- each swing, "the eyes dont follow the head on the pole", 2026-10-22. So: the view the player's, swung with him by
    -- the swing itself - his whole body's turn about the bar, a smooth pendulum - and the eyes in front of his swung face.
    -- See SWING_FOLLOW.)
    local swinging = false
    pcall(function()
        if pawn.CharacterMovement.MovementMode == 6 then
            local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
            swinging = not (m and m:IsValid())
        end
    end)
    -- (flying - a cannon shot or the Wing Cap, flight.lua: his body laid out along the flight, arms ahead, as swimpose.lua
    -- lays him out in the water. Taken for a flip, the view and the eyes were tipped with his chest down into him: "when
    -- shot out of cannon the camera ends up inside the body", 2026-10-22. The view is flight.lua's - it keeps it the way
    -- he flies - and his body's turn is left out, as in the water.)
    local flying = false
    pcall(function() local F = package.loaded["flight"]; flying = F ~= nil and F.active ~= nil and F.active() == true end)
    -- (and for CLIMB_AFTER after: standing up from a climb his chest is still bent, and the view dips with it 10 to 20
    -- degrees and back - kept, but eased, CLIMB_SOFT a second: "small quick bounce while climb", then "i'd actually keep
    -- it but it needs smoothed out its too rigid", 2026-10-22)
    local after_climb, rolling = false, false
    pcall(function()
        local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
        local n = (m and m:IsValid()) and m:GetFName():ToString():lower() or ""
        rolling = n:find("roll") ~= nil
    end)
    if climbing then climb_last = os.clock() elseif os.clock() - climb_last < CLIMB_AFTER then after_climb = true end
    -- sliding (see SLIDE_DELAY)
    local now_s = os.clock()
    if not sw and not climbing and not flying and sliding_now(pawn) then slide_t = now_s end
    local sliding = slide_t ~= nil and now_s - slide_t < SLIDE_LINGER
    if slide_t and not sliding then
        -- (off the slide: he faces the way the view looks, so it is not swung round to where he faced before)
        slide_t, slide_pitch, recentering, quiet = nil, nil, false, 0.0
        pcall(function()
            local y = pc:GetControlRotation().Yaw
            if math.abs(wrap(y - facing_of(pawn))) > 45.0 then
                pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = y, Roll = 0.0 }, false)
                facing = y
            end
        end)
    end
    local rot
    if sw then
        move_facing = nil
        rot = swim_view(pc, sw, dt)
    elseif sliding then
        swim_last, move_facing, recentering = nil, nil, false
        rot = slide_view(pc, pawn, dt)
    elseif climbing or flying or swinging then
        -- (the view is the player's alone while he climbs: kept in front of him, a look past his shoulder was pulled
        -- back round at 1100 degrees a second - "theres still some moments where the head is ripped around during a
        -- climb ... when turning the camera", 2026-10-22; nor is it turned with him as he turns on the wall)
        move_facing, recentering, quiet = nil, false, 0.0
        rot = pc:GetControlRotation()
    else
        swim_last = nil
        -- (a move under way off the ground: as STORROR turns him, the view turns with him. In the round-off it turns
        -- him half round while his chest twists; the view stayed put until he was 90 degrees away, then was swung
        -- round after him at 700 a second, and the twist it had taken from his chest sprang back as he landed -
        -- "roundoff camera still snapping", 2026-10-22. Not on the ground, where STORROR turns him towards the
        -- view and the view following him would turn them both round and round.)
        local f_now = nil
        pcall(function() f_now = facing_of(pawn) end)
        -- (falling or STORROR's own flying moves only, and a turn, not a jump: in a bail his ragdoll's facing jumps
        -- half round from one tick to the next, and the view went with it)
        local mv = 0
        pcall(function() mv = pawn.CharacterMovement.MovementMode end)
        if f_now and move_facing and (active > 0.5 or tree == "jump") and not grounded and (mv == 3 or mv == 5) then
            local dy = wrap(f_now - move_facing)
            if math.abs(dy) > 0.01 and math.abs(dy) < 30.0 then
                pcall(function()
                    local cr = pc:GetControlRotation()
                    pc:SetControlRotation({ Pitch = cr.Pitch, Yaw = cr.Yaw + dy, Roll = cr.Roll })
                end)
            end
        end
        move_facing = f_now
        rot = keep_in_front(pc, pawn, pc:GetControlRotation(), grounded, dt)
    end
    local view = quat(rot.Pitch, rot.Yaw, 0.0)
    local step = dt or 0.016
    -- (landing out of a move, still in the air's way for LAND_HOLD: on the ground's at once, his chest still bent
    -- from the landing was dropped from the view in a twentieth of a second - the snap at the end of a round-off)
    if not grounded then land_hold = (active > 0.5) and LAND_HOLD or 0.0
    else land_hold = math.max(0.0, land_hold - step) end
    air = air + ((((not grounded) or land_hold > 0.0) and 1.0 or 0.0) - air) * (1.0 - math.exp(-8.0 * step))
    local from_deg = GROUND_FROM + (AIR_FROM - GROUND_FROM) * air
    local full_deg = GROUND_FULL + (AIR_FULL - GROUND_FULL) * air
    local ok, turn = true, nil
    if sw or climbing or sliding or flying or swinging then
        last_d, active = nil, 0.0          -- (his laid-out, rocking swimming body is not a flip; nor a climb's bend, nor his slide pose)
    else
        ok, turn = pcall(body_turn, pawn, from_deg, full_deg, step)
    end
    local target = (ok and turn) or { x = 0, y = 0, z = 0, w = 1 }
    local follow = (active > 0.5) and TURN_LOCKED or TURN_FOLLOW
    if after_climb then follow = CLIMB_SOFT end
    if rolling then follow = ROLL_FOLLOW end
    turned = turned and toward(turned, target, 1.0 - math.exp(-follow * step)) or target
    if angle_of(turned) > 0.05 then view = normalize(mul(turned, view)) end
    -- the swing: his turn about the bar from how he hung at its start, eased (SWING_FOLLOW), back to none once off it
    do
        local target = { x = 0, y = 0, z = 0, w = 1 }
        if swinging then
            -- (from how he hung as the swing began, all of it: measured from his facing alone, a swing begun with him
            -- over the top of the bar turned the view upside down)
            pcall(function()
                local ar = pawn:K2_GetActorRotation()
                local aq = quat(ar.Pitch, ar.Yaw, ar.Roll)
                if not swing_ref then swing_ref = aq end
                target = normalize(mul(aq, inv(swing_ref)))
            end)
        else
            swing_ref = nil
        end
        local rate = swinging and SWING_FOLLOW or SWING_LEAVE
        swung = swung and toward(swung, target, 1.0 - math.exp(-rate * step)) or target
        if angle_of(swung) > 0.05 then view = normalize(mul(swung, view)) end
    end
    note("  view turned %.0f (target %.0f) ground %s", angle_of(turned), angle_of(target), tostring(grounded))
    local eye = pawn.Mesh:GetSocketLocation(FName("Head"))
    local loc = pawn:K2_GetActorLocation()
    local rel = { X = eye.X - loc.X, Y = eye.Y - loc.Y, Z = eye.Z - loc.Z }
    if sliding then rel = { X = 0.0, Y = 0.0, Z = rel.Z + SLIDE_ABOVE } end
    if not eyes or math.abs(rel.X - eyes.X) + math.abs(rel.Y - eyes.Y) + math.abs(rel.Z - eyes.Z) > 150.0 then
        eyes = rel                          -- (a fresh start, or he was moved: no gliding there)
    else
        local calm = (grounded or sw ~= nil) and not (ok and turn)
        local k = 1.0 - math.exp(-(calm and FOLLOW_GROUND or FOLLOW_MOVES) * step)
        local kz = 1.0 - math.exp(-(calm and FOLLOW_GROUND_UP or FOLLOW_MOVES) * step)
        -- (with a flip under way, on his head itself: trailing it up to 15 cm, the eyes came back to his neck in a
        -- front flip and his body showed through the view - "during frontflip the body sticks through cam a bit",
        -- 2026-10-22)
        k, kz = math.max(k, active), math.max(kz, active)
        -- (climbing, his head bobs and dips against him all the way up: the eyes ease after it - they go with him, not
        -- with each bob - "its still pretty shakey", 2026-10-22)
        if climbing then
            k = 1.0 - math.exp(-CLIMB_FOLLOW * step)
            kz = 1.0 - math.exp(-CLIMB_FOLLOW_UP * step)
        elseif sliding then
            -- (over the middle of him, steady: up at once, so never inside him as he sits up, down slowly)
            k = 1.0 - math.exp(-FOLLOW_GROUND * step)
            kz = 1.0 - math.exp(-((rel.Z > eyes.Z) and SLIDE_RISE or SLIDE_SINK) * step)
        elseif rolling then
            k = 1.0 - math.exp(-ROLL_EYES * step)
            kz = k
        end
        eyes = { X = eyes.X + (rel.X - eyes.X) * k, Y = eyes.Y + (rel.Y - eyes.Y) * k, Z = eyes.Z + (rel.Z - eyes.Z) * kz }
        if climbing or rolling then eyes = leash(eyes, rel, CLIMB_LEASH) end
    end
    eye = { X = loc.X + eyes.X, Y = loc.Y + eyes.Y, Z = loc.Z + eyes.Z }
    -- (the eyes sit in front of his face the way he faces, and turn over with him in a flip; they used to follow
    -- the way the player looks, which put the camera down into his collar when looking down, and the shirt was seen
    -- from inside: "seeing through charater model", 2026-10-14)
    -- (level, the way the player looks: walking backwards STORROR turns him round to face the camera, and eyes in
    -- front of his face were then behind him, looking down the back of his shirt: "if I just walk backwards I can
    -- see the body", 2026-10-14. The way he looks, level, never puts the camera into his collar either.)
    local face = quat(0.0, rot.Yaw, 0.0)
    if angle_of(turned) > 0.05 then face = normalize(mul(turned, face)) end
    if swung and angle_of(swung) > 0.05 then face = normalize(mul(swung, face)) end
    local mode = 1
    pcall(function() mode = pawn.CharacterMovement.MovementMode end)
    -- the face by his head bone: measured against the way he faces while he stands upright and still, used in
    -- proportion to how far over he is turned (fully from 30 degrees)
    pcall(function()
        local hr = pawn.Mesh:GetSocketRotation(FName("Head"))
        local hq = quat(hr.Pitch, hr.Yaw, hr.Roll)
        local _, upright = facing_of(pawn)
        local still = false
        local v = pawn:GetVelocity()
        still = on_ground(pawn) and upright and (v.X * v.X + v.Y * v.Y) < 40.0 * 40.0 and angle_of(turned) < 2.0
        local flat = quat(0.0, facing or rot.Yaw, 0.0)
        if still then
            local now_off = mul(inv(hq), flat)
            head_to_face = head_to_face and toward(head_to_face, now_off, 0.2) or now_off
        end
        if head_to_face then
            local k = math.min(1.0, angle_of(turned) / 30.0)
            if k > 0.0 then face = toward(face, normalize(mul(hq, head_to_face)), k) end
        end
    end)
    local off_eye = rotate(face, { X = EYES_FORWARD, Y = 0.0, Z = EYES_UP })
    if flying then
        -- (laid out along the flight: in front of his head along his body - chest to head - however steep the flight; put
        -- level in front of it, in a dive the eyes sat 8 cm back over his neck, his shoulders round the view)
        pcall(function()
            local h = pawn.Mesh:GetSocketLocation(FName("Head"))
            local c = pawn.Mesh:GetSocketLocation(FName(BODY_BONE))
            local ax, ay, az = h.X - c.X, h.Y - c.Y, h.Z - c.Z
            local n = math.sqrt(ax * ax + ay * ay + az * az)
            if n > 1.0 then off_eye = { X = ax / n * FLY_AHEAD, Y = ay / n * FLY_AHEAD, Z = az / n * FLY_AHEAD } end
        end)
    end
    local r = rotator(view)
    do
        local p = { X = eye.X + off_eye.X, Y = eye.Y + off_eye.Y, Z = eye.Z + off_eye.Z }
        if last_cam then
            local moved = math.sqrt((p.X - last_cam.X) ^ 2 + (p.Y - last_cam.Y) ^ 2 + (p.Z - last_cam.Z) ^ 2)
            local fall = 0.0
            pcall(function() local v = pawn:GetVelocity(); fall = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) * step end)
            note("  cam moved %.1f (his own move %.1f) mode %s", moved, fall, tostring(mode))
        end
        last_cam = p
    end
    -- (the field of view, every tick: something of STORROR's keeps pulling the view camera's own down to about 72)
    pcall(function()
        local cc = cam.CameraComponent
        if math.abs(cc.FieldOfView - FOV) > 0.01 then cc.FieldOfView = FOV end
    end)
    pcall(function()
        local want = clear_of_level(pawn, { X = eye.X + off_eye.X, Y = eye.Y + off_eye.Y, Z = eye.Z + off_eye.Z })
        local now = os.clock()
        if climbing then climb_t = now end
        if now - climb_t < CLIMB_LINGER and climb_cam then
            -- (easing back to following outright as the linger runs out)
            local rate = CLIMB_WORLD * (climbing and 1.0 or (1.0 + 6.0 * (now - climb_t) / CLIMB_LINGER))
            local k = 1.0 - math.exp(-rate * step)
            want = leash({ X = climb_cam.X + (want.X - climb_cam.X) * k, Y = climb_cam.Y + (want.Y - climb_cam.Y) * k,
                     Z = climb_cam.Z + (want.Z - climb_cam.Z) * k }, want, CLIMB_LEASH)
        end
        climb_cam = (now - climb_t < CLIMB_LINGER) and want or nil
        if climbing and not climb_cam then climb_cam = want end
        cam:K2_TeleportTo(swept(pawn, want), r)
    end)
    local same = false
    pcall(function() same = pc:GetViewTarget():GetAddress() == cam:GetAddress() end)
    if not same then pcall(function() pc:SetViewTargetWithBlend(cam, 0.0, 0, 0.0, false) end) end
end

-- First person showing: its camera is the view (mariolook.lua hides his cap, nose and moustache by it - told by the
-- camera's distance from his head it flickered into view as he slid, the camera over the middle of him and a frame behind)
function M.on()
    if not (was_on and valid(cam)) then return false end
    local same = false
    pcall(function() same = lib.controller():GetViewTarget():GetAddress() == cam:GetAddress() end)
    return same
end

-- `a` (an actor) is this camera
function M.is_ours(a)
    local same = false
    pcall(function() same = a ~= nil and valid(cam) and a:GetAddress() == cam:GetAddress() end)
    return same
end

-- The world went (the game reloaded its map): forget the camera without touching it.
function M.forget()
    cam, head, was_on, eyes, turned, air, active, last_d, facing, hidden, swim_last = nil, nil, false, nil, nil, 0.0, 0.0, nil, nil, nil, nil
    move_facing = nil
    slide_t, slide_pitch = nil, nil
end

-- (for checking the conversions over the dev channel)
M.debug = { quat = quat, rotator = rotator, mul = mul, inv = inv, body_turn = body_turn, rest = function() return rest end,
            trace = function(n)
                local out = {}
                for i = n - 1, 0, -1 do
                    local e = trace[((trace_n - 1 - i) % 400) + 1]
                    if e then out[#out + 1] = e end
                end
                return table.concat(out, " | ")
            end }

return M
