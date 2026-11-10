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
-- The FIRST PERSON tab's settings (fpconfig.lua; read every frame, so a slider moved shows at once): "start adding all
-- of our new settings", 2026-11-09 - promised in Discord 2026-10-22 as FOV, angle of view, widen the POV,
-- rubberbanding, motion, and locking the head upwards.
local function setting(k, d) local C = _G.FP_CFG; if C then return C.num(k) end; return d end
-- FIELD OF VIEW: degrees across (FOV till set), up to 179 - a flat picture cannot show 180 ("make field of view go up
-- to 200", 2026-11-09; ANGLE OF VIEW, a lens's focal length on top of it for a while, taken out: "angle of view and
-- field of view are the same thing")
-- SPEED FOV: the view wider the faster he runs - up to SPEED_FOV_MAX degrees at its 100%, from nothing at SPEED_FROM cm a
-- second to all of it at SPEED_FULL (a sprint, a wall run: MaxWallRunningSpeed 700), eased (SPEED_EASE a second); his
-- whole speed, falling too ("Speed FOV", then "it should work with falling as well", 2026-11-09 - asked from a list: the
-- view widening with speed, as in Mirror's Edge)
local SPEED_FROM, SPEED_FULL, SPEED_FOV_MAX, SPEED_EASE = 250.0, 750.0, 30.0, 3.0
-- The feel of moving ("add all of it", 2026-11-09 - from a list: a landing's impact, leaning into turns, looking down in
-- the air, the hands in view at a sprint). Each its slider, 0 to 100%, 0 off:
--   LANDING IMPACT: landing out of a fall the camera dips (up to IMPACT_DIP cm) and shakes (up to IMPACT_SHAKE degrees),
--     the harder the faster he fell (from IMPACT_FROM to IMPACT_FULL cm a second down), and settles
--   LEAN: the view rolls into a turn (up to LEAN_MAX degrees), by how fast the way he runs turns (LEAN_FULL degrees a
--     second for all of it)
--   LOOK DOWN IN AIR: off the ground the view tips down (up to AIR_LOOK_MAX degrees), so he sees where he lands
--   SPRINT HANDS: at a sprint (from SPRINT_FROM to SPRINT_FULL cm a second) the camera goes forward and down and tips
--     down a little (up to SPRINT_FWD, SPRINT_DOWN cm and SPRINT_TILT degrees), so his hands are in view
local IMPACT_DIP, IMPACT_SHAKE, IMPACT_FROM, IMPACT_FULL = 14.0, 4.0, 350.0, 1500.0
local LEAN_MAX, LEAN_FULL = 8.0, 150.0
local AIR_LOOK_MAX = 25.0
-- (SPRINT_FROM/FULL 450/700 at first: his runs go about 460 to 590, so it hardly came in - "sprint hands doesnt work
-- sometimes", 2026-11-10)
-- (SPRINT_DOWN/TILT 8 cm / 6 degrees at first: "sprint hands doesnt bring the camera down enough", 2026-11-10)
local SPRINT_FROM, SPRINT_FULL, SPRINT_FWD, SPRINT_DOWN, SPRINT_TILT = 300.0, 520.0, 10.0, 20.0, 16.0
local feel = { was_ground = true, vz = 0.0, impact = 0.0, impact_t = 10.0, lean = 0.0, heading = nil, air = 0.0, sprint = 0.0,
               -- ("all of it", 2026-11-09, from a list:) WALL RUN TILT: the view leans away from a wall he runs along, up
               -- to WALL_MAX degrees; BREATHING: a slow sway standing still (degrees, cm), times MOTION; JUMP FOV KICK: the
               -- field of view out by up to KICK_MAX degrees as he jumps, and back
               wall = 0.0, WALL_MAX = 12.0, breath_w = 0.0, breath_t = 0.0, kick = 0.0, kick_t = 10.0, kick_amt = 0.0,
               was_ground_k = true, KICK_MAX = 12.0,
               -- SPRINT SHAKE: a small steady shake at a sprint (degrees, cm), "sprint shake", 2026-11-09
               shake_w = 0.0, shake_t = 0.0,
               AIR_FALL_FULL = 900.0 }   -- (LOOK DOWN IN AIR: all of it falling this fast, cm a second)
-- (a percent slider's share, up to 3: LOOK DOWN IN AIR and SPRINT HANDS go to 300% - 200% first, then "make look down in
-- air go to 300% also sprint hands", 2026-11-10; the rest stop at 100)
local function amount(k) return math.max(0.0, math.min(3.0, setting(k, 0) / 100.0)) end
local speed_add = 0.0
local function fov() return math.max(20.0, math.min(179.0, setting("fov", FOV) + speed_add + feel.kick)) end
-- RUBBERBANDING: every rate the eyes and the view follow him at, times this - 3 at 0 (tight), 1 at 50 (as it was), a
-- third at 100 (loose)
local function rubber() return 3.0 ^ ((50.0 - setting("rubber", 50)) / 50.0) end
-- MOTION: how much of his head's bob as he moves the camera takes, 0 to 1 (see bob below) - not his flips, which are
-- FOLLOW FLIPS' ("For motion that only meant for head bobbing and camera movement, not the camera moving with flips
-- that should be its own switch", 2026-11-09)
local function motion() return math.max(0.0, math.min(1.0, setting("motion", 100) / 100.0)) end
-- FOLLOW FLIPS: the view turns with his body in flips, rolls, vaults and swings (as it did); off, it takes none of it
local function follow_flips() return setting("follow_flips", 1) >= 0.5 end
-- (LOCK HEAD UP - of his body's turn only its yaw taken, the view kept upright - taken out: "remove lock head up",
-- 2026-11-09)
-- DRONE FISHEYE: the first-person view as the drone sees - the drone camera's angle (BP_DronePawn's Camera, 100) and its
-- fisheye (SPPCameraComponent's FishEyePostProcessMaterial, PP_FishEye_Inst at Intensity 0.5: WIDEN POV's 50), and its
-- vignette ("also add an option for the drone fisheye", "thats not the drone fisheye", 2026-11-09). Turned on, it puts
-- FIELD OF VIEW and WIDEN POV at the drone's (fpsettings.lua), and they are the player's to change from there ("should
-- still be able to mess with drone fisheyes fov and other settings"); here, only its vignette: VignetteIntensity 1, the
-- engine's own 0.4 when off.
local DRONE_VIGNETTE, VIGNETTE_WAS = 1.0, 0.4
local vig_set = nil                         -- the vignette last set on the camera (nil: not yet)
local function drone_look() return setting("drone_fish", 0) >= 0.5 end
local function fisheye_pct() return setting("widen", 0) end
-- CAMERA X, Y, Z: cm the camera is moved from his eyes (up to 100 each way) - forward, right and up, the way his face looks ("add an x y and
-- z axis that the player can move the camera/head around with", 2026-11-09)
local function cam_offset() return { X = setting("cam_x", 0), Y = setting("cam_y", 0), Z = setting("cam_z", 0) } end
-- HEAD LOCK: how far the player can look down and up, as a share taken off the full range (LOOK_DOWN to LOOK_UP): 0 the
-- whole of it, 1 none - the view kept level ("a head lock switch for where you cant look too far down or up", then "make
-- the head lock a slider, where 100% would make the camera stay perfectly horizontal and 0 would be full range", and "with
-- head lock at 0% you dont get full range", 2026-11-09 - it was PITCH_MIN down, the game's own 75 up)
local LOOK_DOWN, LOOK_UP = -89.0, 89.0
local function head_lock() return math.max(0.0, math.min(1.0, setting("head_lock", 0) / 100.0)) end
local pitch_max_was = nil                   -- the camera manager's own ViewPitchMax, put back when ours goes
-- MOTION's fixed place: his eyes as they sit while he stands still, relative to him and his facing; the camera is put
-- MOTION's share of the way from it to his head's own place (see MOTION in M.update). (A slow-following steady point
-- before, 2026-11-09: "barely move", "no head bobbing at all", then "at 0% the head should move none ... at 100% it
-- should follow the head exactly".)
local stand_eye = nil
local motion_m = 1.0                        -- MOTION as used now: eased to 1 in moves (see MOTION in M.update)
-- WIDEN POV: the picture widened at its edges as a fisheye does - STORROR's own fisheye, its drone camera's
-- (PP_FishEye_Inst, Intensity 0.5 there), on this camera alone: 0 to 100 percent is its Intensity 0 to FISH_MAX, so 50
-- is the drone's. (The engine's Panini projection, tried first, is not in this build: its settings read back 0.)
local FISHEYE = "/HITS_Shared/PostEffects/PP_FishEye_Inst.PP_FishEye_Inst"
local FISH_MAX = 1.0
-- (Eased off at wide fields of view for a while, 2026-11-09, against its blur - taken out: "dont limit the fisheye thats
-- not what I asked for, I wanted you to fix the blurryness". Full strength is full strength.)
local fish, fish_cam, fish_set = nil, nil, nil   -- our copy of it, the camera it is on (address), the share last set
-- How far down the player can look (degrees below level): not far enough to see his body, whose skin pieces have
-- gaps with the shirt hidden ("lock the camera from going to low so you cant see the holes in charater",
-- 2026-10-14). The camera manager's own limit (ViewPitchMin), put back when first person goes off.
local PITCH_MIN = -60.0                     -- (35 at first; "try 30"; "needs to go lower": 40; "also try 50"; "try 60 so I can see the feet")
-- (no longer the limit, 2026-11-09: HEAD LOCK's full range, LOOK_DOWN, is - "with head lock at 0% you dont get full range")
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
-- RUBBERBAND X, Y and STRENGTH (the FIRST PERSON tab): the head pulled back to where his body faces - X left and right,
-- Y up and down (to level). Each 0 to 100%: at 0 free; above it stretchy - the whole range can still be reached, but a
-- turn away from his body's way is slowed the further it is from it (by its share, all of it at the far end), and
-- left alone for AUTO_DELAY it is pulled back at STRENGTH's rate (up to PULL_MAX a second; 25% is AUTO_RATE's 2); at
-- 100% the head cannot leave his body's way at all. (A hard limit at first - X 65% let it turn only 35% of the way:
-- "I dont have full range of motion while looking even though head lock is 0%", "camera still locked as well".) ("next
-- rubberbanding on the x and y axis also add a slider for rubberbanding strength, at 0 there should be no rubber banding
-- to the middle at 100% the head is no longer able to move from where the bodys looking at. strength should imply how
-- fast its pulled to the center", 2026-11-09 - RUBBERBANDING was at first how loosely the camera trailed him.)
local PULL_MAX = 8.0
local function rb_x() return math.max(0.0, math.min(1.0, setting("rb_x", 50) / 100.0)) end
local function rb_y() return math.max(0.0, math.min(1.0, setting("rb_y", 0) / 100.0)) end
-- STRENGTH: how hard the stretch resists (times the axis's own share); CENTER SPEED: how fast it comes back to the
-- middle once the right stick is let go - none at 0, at once at 100 ("add a rubberband center speed slider. at 0 it never
-- centers at 100% it instantly centers the camera the second you let go of the right stick", 2026-11-09)
-- CENTER DELAY: on, the centering waits AUTO_DELAY after the right stick is let go; off, it starts at once ("add another
-- thing to rubberband a toggle of a centering delay", 2026-11-09)
local function center_delay() return (setting("rb_delay", 0) >= 0.5) and AUTO_DELAY or 0.0 end
local function rb_strength() return math.max(0.0, math.min(1.0, setting("rb_strength", 25) / 100.0)) end
local function center_k(step)                   -- the share of the way back to the middle this frame
    local cs = math.max(0.0, math.min(1.0, setting("rb_center", 25) / 100.0))
    if cs <= 0.0 then return 0.0 end
    if cs >= 0.999 then return 1.0 end
    return 1.0 - math.exp(-30.0 * cs * cs * step)
end
local pitch_quiet = 0.0                     -- seconds since the look was last turned up or down
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
local SWIM_PITCH_MIN = -80.0                  -- (no longer the limit in the water either: LOOK_DOWN, 2026-11-09)
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

-- a body turn as the view takes it: none with FOLLOW FLIPS off
local function as_shown(q)
    if not q then return nil end
    if not follow_flips() then return { x = 0, y = 0, z = 0, w = 1 } end
    return q
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

-- Read once a frame ("we need to optimize", 2026-11-09: the same things were asked of the game several times a frame -
-- his facing 5 times, the move playing up to 7, his speed up to 8, the same keys twice - and key names and bone names
-- made again at every ask): `once.frame` counts M.update's frames, and each of these keeps its answer for the frame it
-- was asked in. (All in one table: this file is at Lua's 200 locals.)
--   once.trace: the camera's last few seconds kept (note), read back after a move that did not look right - only while
--     set (M.debug.set_trace): written every frame it cost frame time for nothing
--   once.cam_on: the him, by address, whose capsule the camera rides
local once = { frame = 0, trace = false, cam_on = nil,
               BODY_BACK = 0.15, body_gone = false, gone_t = nil,   -- (HIDE BODY IN FLIPS / ROLLS: back this long after)
               FLIP_DEG = 110.0, turn_deg = 0.0,                    -- (a flip: turned over past this, body_turn's measure)
               -- (TURN CONE: the stick this far off ahead turns him round - 60 at first, then only right back: "shrink the
               -- cone of when you push back on the stick so running will only triggle if its perfectly facing backwards",
               -- 2026-11-10; held on 10 degrees looser once turning)
               TURN_CONE = 160.0, TURN_HOLD = 10.0, turning = false,
               RUN_FROM = 300.0,                                    -- (HIDE BODY WHEN RUNNING: cm a second, past a walk)
               STAND_UNDER = 60.0,                                  -- (HIDE BODY WHEN STANDING: cm a second, near still)
               facing_at = -1, facing_up = false, facing_ar = nil, vel_at = -1, vel = nil,
               mont_at = -1, mont_on = false, mont_name = "", keys_at = -1, keys = {}, analog = {}, down = {},
               head = FName("Head"), none = FName("None"), body = FName(BODY_BONE) }
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
    if once.facing_at ~= once.frame or not once.facing_ar then
        local ar = pawn:K2_GetActorRotation()
        once.facing_ar = { Pitch = ar.Pitch, Yaw = ar.Yaw, Roll = ar.Roll }
        once.facing_up = math.abs(ar.Pitch) < 60.0 and math.abs(ar.Roll) < 60.0
        once.facing_at = once.frame
        if once.facing_up or not facing then facing = ar.Yaw end
    end
    return facing, once.facing_up, once.facing_ar
end

-- his speed (a copy: { X, Y, Z } cm a second)
function once.velocity(pawn)
    if once.vel_at ~= once.frame or not once.vel then
        local v = pawn:GetVelocity()
        once.vel = { X = v.X, Y = v.Y, Z = v.Z }
        once.vel_at = once.frame
    end
    return once.vel
end

-- the move of STORROR's playing on him: playing at all, and its name in lower case ("" for none)
function once.montage(pawn)
    if once.mont_at ~= once.frame then
        once.mont_at, once.mont_on, once.mont_name = once.frame, false, ""
        pcall(function()
            local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
            if m and m:IsValid() then once.mont_on = true; once.mont_name = m:GetFName():ToString():lower() end
        end)
    end
    return once.mont_on, once.mont_name
end

-- his head bone's place (a copy)
function once.head_at(pawn)
    if once.head_t ~= once.frame or not once.head_loc then
        local h = pawn.Mesh:GetSocketLocation(once.head)
        once.head_loc = { X = h.X, Y = h.Y, Z = h.Z }
        once.head_t = once.frame
    end
    return once.head_loc
end

-- the keys (made once a name) and what they read this frame
function once.key(name)
    local k = once.keys[name]
    if not k then k = { KeyName = FName(name) }; once.keys[name] = k end
    if once.keys_at ~= once.frame then once.keys_at, once.analog, once.down = once.frame, {}, {} end
    return k
end

local function analog(pc, key)
    local k = once.key(key)
    local v = once.analog[key]
    if v ~= nil then return v end
    v = 0.0
    pcall(function() v = pc:GetInputAnalogKeyState(k) end)
    if type(v) ~= "number" then v = 0.0 end
    once.analog[key] = v
    return v
end

local function key_down(pc, key)
    local k = once.key(key)
    local v = once.down[key]
    if v ~= nil then return v end
    local ok, d = pcall(function() return pc:IsInputKeyDown(k) end)
    v = ok and d == true
    once.down[key] = v
    return v
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
    local keep = 1.0 - head_lock()
    pitch = math.max(LOOK_DOWN * keep, math.min(LOOK_UP * keep, pitch))
    local kept = { Pitch = pitch, Yaw = yaw, Roll = 0.0 }
    pcall(function() pc:SetControlRotation(kept) end)
    return kept
end

-- sliding: STORROR's slope slide, or slide.lua carrying him
local function sliding_now(pawn)
    local yes = false
    pcall(function()
        local _, n = once.montage(pawn)
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
        local v = once.velocity(pawn)
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
    if looking or back or once.turning then quiet = 0.0 else quiet = quiet + (dt or 0.016) end
    -- (on the ground, standing, with no move of STORROR's playing, he faces where the view looks - turned with it as
    -- the stick turns it, and kept so: "is it possible to make the player turn when moving the right stick ... in first
    -- person", then "its turning him but its also ripping him back", 2026-10-22 - STORROR turns a standing athlete back
    -- to the way he last moved, about 200 degrees a second, so his facing is set again every tick while he stands. Quick
    -- but eased: BODY_TURN a second. Once he moves, or a move plays, STORROR has him again.)
    -- LEFT STICK STEERS off: moving on the ground, no move of STORROR's playing, he faces where the view looks, not the way
    -- he is steered - the stick moves him sideways and back without turning him ("add an option for left joystick steers
    -- body", then "what it does now" for on, 2026-11-09)
    -- (and pulled back, whatever LEFT STICK STEERS says: he backs up facing the view, the camera on him - STORROR would
    -- turn him round to run back, and the view turned round after him had him run forward on screen while the stick was
    -- held back: "pushing the stick backwards makes the player run forward?", 2026-11-09)
    -- (with LEFT STICK STEERS on, pulled back no longer backs him up: he turns round, the view with him - TURN CONE,
    -- back_view)
    if grounded and steering and setting("left_steers", 1) < 0.5 then
        local playing = false
        pcall(function()
            playing = once.montage(pawn)
            if math.abs(once.velocity(pawn).Z) > 50.0 then playing = true end
        end)
        if not playing then
            recentering = false
            pcall(function() pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = rot.Yaw, Roll = 0.0 }, false) end)
            facing, stand_yaw, stand_t = rot.Yaw, rot.Yaw, os.clock()
            return rot
        end
    end
    -- (RIGHT STICK TURNS BODY off: the right stick turns his head alone - his body left as it stands - "also add a right
    -- stick x axis turns body toggle", 2026-11-09)
    local turns_body = setting("rstick_body", 1) >= 0.5
    if grounded and not steering and turns_body then
        local playing, still = false, false
        pcall(function()
            playing = once.montage(pawn)
            local v = once.velocity(pawn)
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
    -- (off the ground no rubberband at all - no centring, no pulling round - till he lands: "if rubberbanding and look
    -- down in air are on at the same time, rubberbanding should turn off until player hits the ground", 2026-11-10)
    if once.air_on and not grounded then recentering = false; return rot end
    if recentering and (looking or (grounded and steering) or math.abs(d) < 2.0) then recentering = false end
    -- (how far the head may turn from him: RUBBERBAND X's share of 180 - LIMIT's 90 at its 50)
    local lim = (rb_x() >= 0.999) and 0.0 or 180.0

    if not recentering then
        if math.abs(d) <= lim or (grounded and steering) then
            -- (left alone: round to his front at RUBBERBAND STRENGTH's rate, see AUTO_DELAY - none at RUBBERBAND X 0;
            -- running past the edge too)
            local step = math.max(dt or 0.016, 0.001)
            local kc = center_k(step)
            if quiet <= center_delay() or math.abs(d) < 0.5 or rb_x() <= 0.0 or kc <= 0.0 then return rot end
            local turn = d * kc
            local most = (kc >= 1.0) and 360.0 or (AUTO_MAX * 8.0 * step)
            if turn > most then turn = most elseif turn < -most then turn = -most end
            local kept = { Pitch = rot.Pitch, Yaw = rot.Yaw - turn, Roll = rot.Roll }
            pcall(function() pc:SetControlRotation(kept) end)
            return kept
        end
        if grounded and looking and turns_body then
            -- standing, the view turned past his shoulder: he turns with it
            local side = d > 0 and lim or -lim
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

-- The body-part switches on the FIRST PERSON tab: each hides one of his parts from the player's own view ("a toggle for
-- each body part to make it invisable in the players eyes", 2026-11-09) - hidden in this game only (in multiplayer the
-- others still see him whole), still casting its shadow. His head and hair (HIDE_PARTS) go with HIDE HEAD (on unless set
-- off). (His stomach cannot be hidden apart from his arms: the skin is one mesh of one material - HIDE ARMS & STOMACH.)
local PART_SWITCHES = {
    { key = "hide_arms", part = "CharacterMesh0", says = "arms" },     -- (his skin; with HIDE STOMACH off, its copy's stomach shown)
    { key = "hide_shirt", part = "TorsoCloth", says = "shirt" },
    { key = "hide_pants", part = "LegsCloth", says = "pants" },
    { key = "hide_shoes", part = "Feet", says = "shoes" },
}
-- (his skin, CharacterMesh0, is the mesh that moves all of him and carries the head bone the camera sits at, and STORROR
-- has it keep its pose only while it is drawn (VisibilityBasedAnimTickOption 4): hidden as it was, his pose - and the
-- view - would stand still. Hidden, it is told to keep its pose always (0), STORROR's own given back when it is shown.)
local ALWAYS_TICK = 0

-- what is to be hidden now (by part name), and a word for it to tell when it changes
local function hide_wanted()
    local want, sig = {}, ""
    -- (his hair, brows and beard with his head: HIDE HEAD)
    if setting("hide_head", 1) >= 0.5 then
        for name in pairs(HIDE_PARTS) do want[name] = true end
        sig = "head "
    end
    for _, s in ipairs(PART_SWITCHES) do
        if setting(s.key, 0) >= 0.5 then want[s.part] = true; sig = sig .. s.says .. " " end
    end
    -- (HIDE STOMACH: the skin itself hidden too - its arms, if they are to be seen, are the copy's: SKIN COPY)
    if setting("hide_stomach", 0) >= 0.5 then want["CharacterMesh0"] = true; sig = sig .. "stomach " end
    -- (HIDE BODY IN FLIPS / IN ROLLS, while one is under way - once.body_gone, M.update's: all of him)
    if once.body_gone then
        for _, s in ipairs(PART_SWITCHES) do want[s.part] = true end
        for name in pairs(HIDE_PARTS) do want[name] = true end
        sig = sig .. "gone "
    end
    return want, sig
end

-- SKIN COPY: his skin is one piece - forearms, hands and the band of stomach above his pants, one mesh of one material
-- and one section, its arm bones under its spine's - so neither can be hidden from it alone. With one of HIDE ARMS and
-- HIDE STOMACH on, the skin is hidden and a copy of it shown (a PoseableMeshComponent on him, on his skin, its pose
-- copied from his skin every frame), the other part taken out of the copy: for the stomach, everything shrunk away at
-- the root and his two arm chains put back from the clavicles, just where his are; for the arms, the clavicles shrunk
-- away. ("why is stomach on the same tab as arms? make it seperate", "arms and stomach still on the same switch",
-- 2026-11-09.) The copy casts no shadow (the hidden skin's still does), is never destroyed - hidden when not wanted -
-- and is made again for a new him.
local skin_copy, skin_copy_of = nil, nil
local SMALL = { X = 0.001, Y = 0.001, Z = 0.001 }
local ARM_ROOTS = { "clavicle_l", "clavicle_r" }
local function skin_copy_update(pawn, on)
    local arms, stomach = setting("hide_arms", 0) >= 0.5, setting("hide_stomach", 0) >= 0.5
    local want = on and (arms ~= stomach)
    local mesh = pawn and pawn.Mesh
    local have = skin_copy ~= nil and valid(skin_copy) and mesh ~= nil and skin_copy_of == mesh:GetAddress()
    if not want then
        if skin_copy and valid(skin_copy) then pcall(function() if skin_copy:IsVisible() then skin_copy:SetHiddenInGame(true, false) end end) end
        return
    end
    if not have then
        skin_copy = nil
        local ok, err = pcall(function()
            local c = pawn:AddComponentByClass(StaticFindObject("/Script/Engine.PoseableMeshComponent"), true,
                { Translation = { X = 0, Y = 0, Z = 0 }, Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
            if not valid(c) then return end
            c:K2_AttachToComponent(mesh, once.none, 2, 2, 2, true)
            c:SetSkinnedAssetAndUpdate(mesh:GetSkinnedAsset(), true)
            c:SetMaterial(0, mesh:GetMaterial(0))
            pcall(function() c:SetCastShadow(false) end)
            skin_copy, skin_copy_of = c, mesh:GetAddress()
        end)
        if not skin_copy then log("first person: no skin copy (%s)", tostring(err)); return end
        log("first person: skin copy made (arms and stomach apart)")
    end
    pcall(function()
        local c = skin_copy
        if not c:IsVisible() then c:SetHiddenInGame(false, false) end
        c:CopyPoseFromSkeletalComponent(mesh)
        if stomach then
            c:SetBoneScaleByName(FName("Root"), SMALL, 1)
            for _, b in ipairs(ARM_ROOTS) do c:SetBoneTransformByName(FName(b), mesh:GetSocketTransform(FName(b), 2), 1) end
        else
            for _, b in ipairs(ARM_ROOTS) do c:SetBoneScaleByName(FName(b), SMALL, 1) end
        end
    end)
end

local function show_parts(h)
    for _, c in ipairs(h.parts) do pcall(function() if c:IsValid() then c:SetHiddenInGame(false, false) end end) end
    if h.tick_was ~= nil then pcall(function() if h.mesh:IsValid() then h.mesh.VisibilityBasedAnimTickOption = h.tick_was end end) end
    if h.uro_was ~= nil then pcall(function() if h.mesh:IsValid() then h.mesh.bEnableUpdateRateOptimizations = h.uro_was end end) end
end

local function hide_body(pawn, on)
    if on then
        local want, sig = hide_wanted()
        local same_mesh = false
        pcall(function() same_mesh = hidden ~= nil and hidden.mesh:GetAddress() == pawn.Mesh:GetAddress() end)
        if hidden and hidden.sig == sig and same_mesh then
            -- (put back again now and then: STORROR shows its parts again after some of its own moves)
            for _, c in ipairs(hidden.parts) do pcall(function() if c:IsVisible() then c:SetHiddenInGame(true, false) end end) end
            return
        end
        -- (nothing hidden yet, or the switches changed, or he is a new him: what was hidden shown, and hidden afresh)
        local prev_sig = hidden and hidden.sig
        if hidden then show_parts(hidden) end
        hidden = { parts = {}, mesh = pawn.Mesh, sig = sig }
        pcall(function()
            local mesh_addr = pawn.Mesh:GetAddress()
            for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.PrimitiveComponent"))) do
                local o = c:get()
                -- (in the Super Mario 64 mashup only those showing: put back on the way out of first person, a part
                -- hidden before - Mario's look hides his beard - came back with them, 2026-10-29)
                if want[o:GetFName():ToString()] and not (_G.FP_MASHUP and o.bHiddenInGame) then
                    if o:GetAddress() == mesh_addr then
                        pcall(function()
                            hidden.tick_was = o.VisibilityBasedAnimTickOption
                            o.VisibilityBasedAnimTickOption = ALWAYS_TICK
                        end)
                        -- (and posed every frame: with every part of him hidden - HIDE BODY IN FLIPS - the engine, seeing
                        -- none of him drawn, would pose him only every few frames, and the view, at his head, stutter)
                        pcall(function()
                            hidden.uro_was = o.bEnableUpdateRateOptimizations
                            o.bEnableUpdateRateOptimizations = false
                        end)
                    end
                    pcall(function() o:SetCastHiddenShadow(true) end)
                    o:SetHiddenInGame(true, false)
                    hidden.parts[#hidden.parts + 1] = o
                end
            end
        end)
        -- (not told for each flip or roll)
        if not sig:find("gone") and not (prev_sig or ""):find("gone") then
            log("first person: %d parts of him hidden (%s)", #hidden.parts, sig)
        end
    elseif hidden then
        show_parts(hidden)
        hidden = nil
    end
end

local function console(cmd)
    pcall(function()
        local KSL = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        KSL:ExecuteConsoleCommand(lib.world(), cmd, lib.controller())
    end)
end

local function near_clip(cm) console(string.format("r.SetNearClipPlane %g", cm)) end

-- WIDEN POV set on this camera as the setting reads (0 to 100 percent). Our copy of the fisheye is made the first time
-- it is wanted, and put among the camera's post-process materials at once - kept by the camera from then on (a material
-- kept by Lua alone is collected under it); made again for a new camera.
local function widen(pct)
    if not valid(cam) then return end
    -- (-100 to 100 percent: below 0 the fisheye the other way round, its Intensity below 0 - "widen pov should also be able
    -- to go negative", 2026-11-09)
    local k = math.max(-1.0, math.min(1.0, (pct or 0) / 100.0))
    local here = cam:GetAddress()
    local have = fish ~= nil and fish_cam == here
    if have and fish_set and math.abs(fish_set - k) < 0.001 then return end
    if not have and k == 0.0 then return end              -- (not made till wanted)
    pcall(function()
        local cc = cam.CameraComponent
        if not have then
            local base = StaticFindObject(FISHEYE)
            if not valid(base) then pcall(function() base = LoadAsset(FISHEYE) end) end
            if not valid(base) then fish_set = k; fish_cam = here; fish = nil; return end
            local KML = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
            local m = KML:CreateDynamicMaterialInstance(lib.world(), base, once.none, 0)
            if not valid(m) then return end
            cc:AddOrUpdateBlendable(m, 0.0)
            fish, fish_cam = m, here
            log("first person: fisheye made for WIDEN POV")
        end
        if not fish then return end
        fish:SetScalarParameterValue(FName("Intensity"), k * FISH_MAX)
        cc:AddOrUpdateBlendable(fish, k ~= 0.0 and 1.0 or 0.0)
        fish_set = k
    end)
end

-- THE LOOK, kept by the mod in first person. STORROR keeps the player's look itself: up, its own input stops it at 45
-- degrees, and with nothing pressed it eases the look back towards about -16 ("head still cant look all the way up",
-- "still cant look up", 2026-11-09 - measured: the look stopped at 45.0 however far it was pushed; set to 70 with nothing
-- pressed, it sank back about 1% a frame). So here the look's pitch is our own (look_v): moved as STORROR moves it while
-- the player turns it, left alone while nothing is pressed, and past STORROR's 45 taken on from the input itself at the
-- rate STORROR was seen to turn it (learned, per mouse and per stick); HEAD LOCK's range holds it. STORROR is given back
-- the same pitch each frame (no more than its 45), so that its own look stays with ours.
-- STICK TURN RATE: the stick's turning (left/right and up/down) times this ("next add sensitity slider for joystick turn
-- rate", 2026-11-09); the mouse as it was.
local LOOK_CAP = 44.9
local look_v, look_c, look_y = nil, nil, nil  -- our look's pitch; the pitch STORROR was given; its yaw as we left it
local rate_mouse, rate_stick = nil, nil       -- STORROR's turning: degrees per unit of mouse, per unit of stick a second
local function stick_rate() return math.max(0.1, math.min(3.0, setting("stick_rate", 100) / 100.0)) end
local function look_take(pc, dt)
    local step = math.max(dt or 0.016, 0.001)
    local r = pc:GetControlRotation()
    local c = wrap(r.Pitch)
    local my, mx = analog(pc, "MouseY"), analog(pc, "MouseX")
    local sy, sx = analog(pc, "Gamepad_RightY"), analog(pc, "Gamepad_RightX")
    local mouse = math.abs(my) + math.abs(mx) > 0.0
    local stick_y, stick_x = math.abs(sy) > 0.15, math.abs(sx) > 0.15
    local rate = stick_rate()
    local yaw = r.Yaw
    -- (left and right: the stick's turn since we left it, times STICK TURN RATE)
    if look_y and stick_x and not mouse and math.abs(rate - 1.0) > 0.001 then
        local d = wrap(yaw - look_y)
        if math.abs(d) < 45.0 then yaw = look_y + d * rate end
    end
    -- (off the ground - once.air_on, the feel's last frame: no rubberband, X or Y, till he lands - see below)
    local air_free = once.air_on == true
    -- (RUBBERBAND X, stretchy: a turn away from his body's way slowed by its share, the more the further it is from it)
    do
        local ax = rb_x()
        if not air_free and look_y and facing and ax > 0.0 and ax < 0.999 then
            local d = wrap(yaw - look_y)
            local dev = wrap(look_y - facing)
            if math.abs(d) > 1e-4 and math.abs(d) < 45.0 and (dev == 0.0 or (d > 0.0) == (dev > 0.0)) then
                yaw = look_y + d * (1.0 - ax * rb_strength() * math.min(1.0, math.abs(dev) / 180.0))
            end
        end
    end
    -- (RUBBERBAND Y, stretchy: a turn up or down away from level slowed the same way)
    local ay = rb_y()
    -- (off the ground - once.air_on, the feel's last frame: RUBBERBAND Y neither pulls the head back to level nor holds
    -- a look down back - the two fought, "rubberbanding and look down in air conflict
    -- with eachother", 2026-11-10; it comes back on landing)
    local function resist(v, delta)
        if air_free or ay <= 0.0 or delta == 0.0 or (v ~= 0.0 and (delta > 0.0) ~= (v > 0.0)) then return delta end
        return delta * (1.0 - math.min(1.0, ay) * rb_strength() * math.min(1.0, math.abs(v) / 89.0))
    end
    if not look_v then look_v = c end
    -- (LOOK UP/DOWN SPEED: the up and down turn times its share; INVERT LOOK UP/DOWN: turned the other way, in first person
    -- only - "all of it", 2026-11-09, from a list)
    local pmul = math.max(0.1, setting("pitch_rate", 100) / 100.0)
    local inv = setting("invert_y", 0) >= 0.5
    if look_c then
        local d = c - look_c                      -- (STORROR's change since: the player's turning, or its easing back)
        local pinned = look_c >= LOOK_CAP - 0.05
        if not (mouse or stick_y) then
            -- (nothing pressed: its easing back, left out)
        elseif inv and ((mouse and my ~= 0.0 and rate_mouse) or (stick_y and not mouse and rate_stick)) then
            -- (inverted, once the input's rate is known: its own push, the other way - so it turns at the top and the
            -- bottom of the range too, where STORROR's own turn stops)
            local dv = 0.0
            if mouse and rate_mouse then dv = my * rate_mouse else dv = sy * step * rate_stick * rate end
            look_v = look_v + resist(look_v, -dv * pmul)
        elseif pinned and d > -0.01 and not inv then
            -- (at STORROR's top: the push from the input itself, at the rate it was seen to turn)
            local dv = 0.0
            if mouse and my ~= 0.0 and rate_mouse then dv = my * rate_mouse
            elseif stick_y and rate_stick then dv = sy * step * rate_stick * rate end
            if dv > 0.0 then look_v = look_v + resist(look_v, dv * pmul) end
        else
            -- (learned while it turns freely: degrees per unit of input)
            if not pinned and math.abs(d) > 0.01 then
                if mouse and math.abs(my) > 0.001 and not stick_y then
                    local q = d / my
                    if math.abs(q) > 1e-4 and math.abs(q) < 100.0 then rate_mouse = rate_mouse and (rate_mouse + (q - rate_mouse) * 0.2) or q end
                elseif stick_y and not mouse then
                    local q = d / (sy * step)
                    if math.abs(q) > 1e-3 and math.abs(q) < 2000.0 then rate_stick = rate_stick and (rate_stick + (q - rate_stick) * 0.2) or q end
                end
            end
            look_v = look_v + resist(look_v, d * ((stick_y and not mouse) and rate or 1.0) * pmul * (inv and -1.0 or 1.0))
        end
    end
    local keep = 1.0 - head_lock()
    -- (RUBBERBAND Y: only its share of the range, and pulled back to level at STRENGTH's rate once left alone)
    keep = keep * ((ay >= 0.999) and 0.0 or 1.0)                -- (at 100% not at all)
    if mouse and my ~= 0.0 or stick_y then pitch_quiet = 0.0 else pitch_quiet = pitch_quiet + step end
    if ay > 0.0 and pitch_quiet > center_delay() and not air_free then look_v = look_v * (1.0 - center_k(step)) end
    look_v = math.max(LOOK_DOWN * keep, math.min(LOOK_UP * keep, look_v))
    local give = math.max(-89.0, math.min(LOOK_CAP, look_v))
    pc:SetControlRotation({ Pitch = give, Yaw = yaw, Roll = 0.0 })
    look_c = give
end

-- PULLED BACK: STORROR has no running backwards - the left stick pulled back turns him round to run towards the camera
-- (STORROR's look, the control rotation, which the stick steers by). The view now turns round after him (back_off: the
-- view's yaw ahead of the control's, eased to where his body faces, BACK_TURN a second), while the control is left as
-- it was, so that the stick held back goes on taking him the same way - turned with him, the control sent him round
-- again, endlessly (why the view was left behind before). Let go of back, or pushed forward, the control is put where
-- the view looks and the stick goes on from there. ("if the player pulls back on the stick, the body goes backwards and
-- the camera doesnt follow", 2026-11-09.) Not with LEFT STICK STEERS off: there he backs up facing the view.
local BACK_TURN = 10.0
local back_off = 0.0
-- TURN CONE (2026-11-10, "make the turning cone way bigger so you can turn around by pointing the stick back left
-- joystick steering camera"; then narrowed to right back only): the left stick pointed once.TURN_CONE degrees or more
-- off straight ahead - back - turns him that way, STORROR's steering, and the view swings round after him (as PULLED BACK above), so pointed
-- back he turns round and runs on the new way; brought back towards ahead or let go, the stick steers on from where the
-- view now looks. (Backing up facing ahead - pulled back, before - stays with LEFT STICK STEERS off.)
local function back_view(pc, pawn, rot, dt)
    local step = math.max(dt or 0.016, 0.001)
    local lx, ly = analog(pc, "Gamepad_LeftX"), analog(pc, "Gamepad_LeftY")
    if key_down(pc, "W") then ly = ly + 1.0 end
    if key_down(pc, "S") then ly = ly - 1.0 end
    if key_down(pc, "D") then lx = lx + 1.0 end
    if key_down(pc, "A") then lx = lx - 1.0 end
    local m = math.sqrt(lx * lx + ly * ly)
    local ang = (m > 0.01) and math.abs(math.deg(math.atan(lx, ly))) or 0.0      -- (0 ahead, 180 back)
    local back
    if once.turning then back = m > 0.25 and ang >= once.TURN_CONE - once.TURN_HOLD  -- (held a little looser once turning)
    else back = m > 0.35 and ang >= once.TURN_CONE end
    if setting("left_steers", 1) < 0.5 then back = false end
    once.turning = back
    if back then
        local body, upright = nil, false
        pcall(function() body, upright = facing_of(pawn) end)
        if body and upright then
            local want = wrap(body - rot.Yaw)
            back_off = back_off + wrap(want - back_off) * (1.0 - math.exp(-BACK_TURN * step))
        end
    elseif back_off ~= 0.0 then
        local yaw = rot.Yaw + back_off
        pcall(function()
            local cr = pc:GetControlRotation()
            pc:SetControlRotation({ Pitch = cr.Pitch, Yaw = yaw, Roll = 0.0 })
        end)
        back_off = 0.0
        return yaw
    end
    return rot.Yaw + back_off
end

local function off(pawn)
    if near_t then near_t = nil; near_clip(NEAR_CLIP_WAS) end
    look_v, look_c, look_y = nil, nil, nil
    back_off = 0.0
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
    -- (the FLASHLIGHT out with first person)
    if once.light_i and once.light_i > 0.0 and valid(once.light) then
        pcall(function() once.light:SetVisibility(false, false) end)
        once.light_i = nil
    end
    if not was_on then return end
    was_on = false
    move_facing = nil
    local pc = lib.controller()
    if pitch_was then
        pcall(function() pc.PlayerCameraManager.ViewPitchMin = pitch_was end)
        pitch_was = nil
    end
    if pitch_max_was then
        pcall(function() pc.PlayerCameraManager.ViewPitchMax = pitch_max_was end)
        pitch_max_was = nil
    end
    if valid(head) then pcall(function() head:SetHiddenInGame(false, false) end) end
    head = nil
    hide_body(pawn, false)
    pcall(skin_copy_update, pawn, false)
end

-- the body's turn away from standing, in the world, as much of it as counts (a quaternion)
local function body_turn(pawn, from_deg, full_deg, dt)
    once.turn_deg = 0.0
    local a, b, tilt = nil, nil, "?"
    pcall(function()
        local yaw, _, ar = facing_of(pawn)
        local br = pawn.Mesh:GetSocketRotation(once.body)
        -- (his facing only: STORROR tips the whole of him over in a flip, and that is part of the turn too)
        a, b = quat(0.0, yaw, 0.0), quat(br.Pitch, br.Yaw, br.Roll)
        tilt = string.format("%.0f/%.0f", ar.Pitch, ar.Roll)
    end)
    if not (a and b) then return nil end
    local here = mul(inv(a), b)             -- the chest, relative to him
    -- standing still on the ground: that is how the chest sits (followed gently, as STORROR's idle moves)
    local still = false
    pcall(function()
        local v = once.velocity(pawn)
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
    once.turn_deg = deg                     -- (how far over he is: HIDE BODY IN FLIPS)
    local step = math.max(dt or 0.016, 0.001)
    local speed = last_d and angle_of(mul(d, inv(last_d))) / step or 0.0
    last_d = d
    if speed > FAST then
        active = active + (1.0 - active) * (1.0 - math.exp(-ACT_IN * step))
    else
        active = active * math.exp(-ACT_OUT * step)
    end
    if once.trace then note("mode %s actor %s body %.0f speed %.0f active %.2f", tostring(pawn.CharacterMovement.MovementMode), tilt, deg, speed, active) end
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
        local h = once.head_at(pawn)
        -- (the library and the colours made once, not every frame; him, left out, never kept past the frame)
        if not valid(once.ksl) then once.ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
        once.clear = once.clear or { R = 0, G = 0, B = 0, A = 0 }
        local hit = {}
        local blocked = once.ksl:SphereTraceSingle(lib.world(), h, p, EYE_BALL, 1, false, { pawn }, 0, hit, true, once.clear, once.clear, 0.0)
        if blocked then
            local l = hit.Location
            out = { X = l.X, Y = l.Y, Z = l.Z }
        end
    end)
    return out
end

-- Every tick of the game. `on`: the switch, and nothing else holding the camera.
function M.update(dt, pawn, on)
    once.frame = once.frame + 1             -- (a new frame: what was read once a frame is read again)
    if not (on and pawn) then off(pawn); return end
    -- THIRD PERSON IN BAILS: while his body is a ragdoll, and while he gets up, STORROR's own camera behind him ("all of
    -- it", 2026-11-09, from a list: the ragdoll throws his head about)
    if setting("bail_third", 0) >= 0.5 then
        local bail = false
        pcall(function() bail = pawn.Mesh:IsSimulatingPhysics(once.none) == true end)
        if not bail then
            local _, n = once.montage(pawn)
            bail = n:find("ragdoll") ~= nil or n:find("getup") ~= nil
        end
        if bail then off(pawn); return end
    end
    local pc, world = lib.controller(), lib.world()
    if not (pc and world) then return end
    if not valid(cam) then
        cam = world:SpawnActor(StaticFindObject("/Script/Engine.CameraActor"), pawn:K2_GetActorLocation(), { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
        if not valid(cam) then cam = nil; return end
        once.cam_on = nil                                                   -- (attached to him below)
        fish, fish_cam, fish_set = nil, nil, nil                       -- (WIDEN POV's fisheye: made again for this one)
        vig_set = nil
        once.pp_key = nil
        pcall(function() lib.keep[cam:GetAddress()] = true end)       -- (it outlives a change of scene)
        pcall(function() cam.CameraComponent:SetFieldOfView(fov()) end)
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
        if head then pcall(function() head:SetCastHiddenShadow(true) end) end
    end
    -- HIDE HEAD: his head hidden, as it always was, or shown ("also add a hide stomach and head control", 2026-11-09);
    -- kept so every frame, as STORROR shows it again after some of its own moves
    if head then
        local hide = setting("hide_head", 1) >= 0.5
        pcall(function()
            if hide and head:IsVisible() then head:SetHiddenInGame(true, false)
            elseif not hide and not head:IsVisible() then head:SetHiddenInGame(false, false) end
        end)
    end
    was_on = true
    -- (set again every few seconds: a change of map or STORROR's settings may put the engine's back)
    -- (NEAR CLIP: the player's, 1 to 20 cm - "all of it", 2026-11-09 - put at once when moved)
    do
        local nc = math.max(1.0, math.min(20.0, setting("near_clip", NEAR_CLIP)))
        if not near_t or os.clock() - near_t > 3.0 or nc ~= once.clip_set then
            near_t = os.clock(); once.clip_set = nc; near_clip(nc)
        end
    end
    widen(fisheye_pct())
    do
        local amt = math.max(0.0, math.min(1.0, setting("speed_fov", 0) / 100.0))
        local target = 0.0
        if amt > 0.0 then
            pcall(function()
                local v = once.velocity(pawn)
                local t = math.max(0.0, math.min(1.0, (math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) - SPEED_FROM) / (SPEED_FULL - SPEED_FROM)))
                target = amt * SPEED_FOV_MAX * t * t * (3.0 - 2.0 * t)
            end)
        end
        speed_add = speed_add + (target - speed_add) * (1.0 - math.exp(-SPEED_EASE * math.max(dt or 0.016, 0.001)))
    end
    -- (the camera's post-process: DRONE FISHEYE's vignette; SPEED EFFECTS - the vignette darker and the colours split at
    -- the edges the faster he goes, as SPEED FOV widens; MOTION BLUR - none at 0, as it was, the engine's own amount at
    -- 50%. Put only when something changed.)
    do
        local st = math.max(dt or 0.016, 0.001)
        local fx = amount("speed_fx")
        local t = 0.0
        if fx > 0.0 then
            pcall(function()
                local v = once.velocity(pawn)
                t = math.max(0.0, math.min(1.0, (math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) - SPEED_FROM) / (SPEED_FULL - SPEED_FROM)))
                t = t * t * (3.0 - 2.0 * t)
            end)
        end
        once.fx = (once.fx or 0.0) + (fx * t - (once.fx or 0.0)) * (1.0 - math.exp(-4.0 * st))
        local drone = drone_look()
        local vig = nil
        if drone or once.fx > 0.005 then vig = (drone and DRONE_VIGNETTE or VIGNETTE_WAS) + once.fx * 1.2 end
        local blur = amount("motion_blur")
        local fringe = once.fx * 4.0
        local key = string.format("%.2f|%.2f|%.2f", vig or -1.0, blur, fringe)
        if key ~= once.pp_key then
            once.pp_key = key
            pcall(function()
                local pp = cam.CameraComponent.PostProcessSettings
                pp.bOverride_VignetteIntensity = vig ~= nil
                pp.VignetteIntensity = vig or VIGNETTE_WAS
                pp.bOverride_MotionBlurAmount = true
                pp.MotionBlurAmount = blur
                pp.bOverride_MotionBlurMax = true
                pp.MotionBlurMax = blur * 10.0
                pp.bOverride_SceneFringeIntensity = fringe > 0.001
                pp.SceneFringeIntensity = fringe
            end)
        end
        vig_set = drone
    end
    -- FLASHLIGHT: a spot light on the camera, lit while it is on - FLASHLIGHT BRIGHTNESS its share of BRIGHT_MOST, by the
    -- light's own units ("flashlight", 2026-11-09). Made for this camera when first wanted, then kept; no shadows (from
    -- the eyes they fall behind what they light, never seen).
    do
        local want = setting("flashlight", 0) >= 0.5
        local here = cam:GetAddress()
        if want and not (valid(once.light) and once.light_cam == here) then
            pcall(function()
                local l = cam:AddComponentByClass(StaticFindObject("/Script/Engine.SpotLightComponent"), false,
                    { Translation = { X = 0, Y = 0, Z = 0 }, Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
                if not valid(l) then return end
                pcall(function() l:SetCastShadows(false) end)
                pcall(function() l:SetInnerConeAngle(16.0) end)
                pcall(function() l:SetOuterConeAngle(32.0) end)
                pcall(function() l:SetAttenuationRadius(4000.0) end)
                pcall(function() l:SetLightColor({ R = 1.0, G = 0.95, B = 0.85, A = 1.0 }, true) end)
                local units = 0
                pcall(function() units = l.IntensityUnits end)
                -- (unitless, candelas, lumens)
                once.light_most = (units == 1) and 2000.0 or ((units == 2) and 20000.0 or 50000.0)
                once.light, once.light_cam, once.light_i = l, here, nil
                log("first person: flashlight made (units %s)", tostring(units))
            end)
        end
        if valid(once.light) and once.light_cam == here then
            local i = want and math.max(0.0, math.min(1.0, setting("flash_bright", 50) / 100.0)) * (once.light_most or 50000.0) or 0.0
            if once.light_i ~= i then
                pcall(function() once.light:SetIntensity(i) end)
                pcall(function() once.light:SetVisibility(want, false) end)
                once.light_i = i
            end
        end
    end
    local rb = rubber()
    local sw = swimming()
    -- (how far he can look down and up: HEAD LOCK's share of the full range, the camera manager's own put back as first
    -- person goes - off)
    pcall(function()
        local pcm = pc.PlayerCameraManager
        local keep = 1.0 - head_lock()                -- (the share of the range left)
        local want = LOOK_DOWN * keep
        if math.abs(pcm.ViewPitchMin - want) > 0.01 then
            pitch_was = pitch_was or pcm.ViewPitchMin
            pcm.ViewPitchMin = want
        end
        local want_up = LOOK_UP * keep
        if math.abs(pcm.ViewPitchMax - want_up) > 0.01 then
            pitch_max_was = pitch_max_was or pcm.ViewPitchMax
            pcm.ViewPitchMax = want_up
        end
    end)
    -- HIDE BODY IN FLIPS / HIDE BODY IN ROLLS: all of him gone from view while he flips in the air (his chest turning
    -- over off the ground - `active`, as last measured - as when the view turns over with him) or rolls (a move of
    -- STORROR's whose name has "roll" in it), and back a moment (once.BODY_BACK) after ("body parts to dissappear when
    -- flipping", "for front roll to just turn off the body completely", 2026-11-09)
    do
        local now = os.clock()
        -- (a flip: off the ground, turned over past FLIP_DEG from how he stands - not how fast he turns, which a plain
        -- jump and a vault reach too: "bodys getting hidden when just normally jumping", "and vaulting", 2026-11-09 - and
        -- never in a vault, whose lean can go far over)
        local _, mn = once.montage(pawn)
        local flip = setting("flip_hide", 0) >= 0.5 and not on_ground(pawn) and (once.turn_deg or 0.0) > once.FLIP_DEG
            and mn:find("vault") == nil
        -- (a roll: "...LandingRolling..." - not "roll" alone, which his plain running landing, "...LandingRunning..._ROLLS_
        -- POP_UP", has too, and he was hidden at every landing: seen 2026-11-09 by recording his moves)
        local roll = setting("roll_hide", 0) >= 0.5 and (mn:find("rolling") ~= nil or mn:find("^montageroll") ~= nil)
        -- (HIDE BODY IN VAULTS: a move of STORROR's whose name has "vault" in it - "also add a toggle for invis when
        -- vaulting", 2026-11-09)
        local vault = setting("vault_hide", 0) >= 0.5 and mn:find("vault") ~= nil
        -- (HIDE BODY WHEN RUNNING: on the ground going faster than a walk, once.RUN_FROM - "add a go invisable when running
        -- toggle", 2026-11-09)
        -- (HIDE BODY WHEN STANDING: on the ground, near still - under once.STAND_UNDER - "and standing", 2026-11-09)
        local run, stand = false, false
        local want_run, want_stand = setting("run_hide", 0) >= 0.5, setting("stand_hide", 0) >= 0.5
        if (want_run or want_stand) and on_ground(pawn) then
            local v = once.velocity(pawn)
            local flat2 = v.X * v.X + v.Y * v.Y
            run = want_run and flat2 > once.RUN_FROM * once.RUN_FROM
            stand = want_stand and flat2 < once.STAND_UNDER * once.STAND_UNDER
        end
        if flip or roll or vault or run or stand then once.gone_t = now end
        once.body_gone = once.gone_t ~= nil and now - once.gone_t < once.BODY_BACK
    end
    hide_t = (hide_t or 0) - (dt or 0.016)
    do
        -- (at once when a body-part switch is flipped; else once a second)
        local _, sig = hide_wanted()
        if hide_t <= 0 or not hidden or hidden.sig ~= sig then hide_t = 1.0; hide_body(pawn, true) end
    end
    pcall(skin_copy_update, pawn, not once.body_gone)
    local grounded = on_ground(pawn)
    -- (PULL BACK TO STAND STILL - the left stick all the way back stopping him - was here; STORROR moves him its own way
    -- every frame and nothing held: the move input ignored, the acceleration or the walk speed put to 0. Taken out for
    -- TURN CONE - see back_view: "instead of stopping the player by pulling back on the stick just make the turning cone
    -- way bigger", 2026-11-10)
    -- (climbing - pulling up over a ledge, a wall pop, a run up, hanging - his chest bends 80 degrees and back in a third
    -- of a second, and the view went with it: "when climbing his neck snaps down really fast then back up", 2026-10-22.
    -- The view stays where it is aimed while he climbs, as while he swims.)
    local climbing = false
    pcall(function()
        local _, n = once.montage(pawn)
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
            swinging = not once.montage(pawn)
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
        local _, n = once.montage(pawn)
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
    -- (the look kept by us - see THE LOOK - but in the water and on a slide, whose views keep the look their own way)
    if sw or sliding then look_v, look_c = nil, nil
    else pcall(look_take, pc, dt) end
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
    -- (the look's pitch ours where we keep it: STORROR's stops at 45)
    -- (MOTION's share now: 1 in STORROR's own moves - a move of its playing (flips, vaults, rolls, landings), climbs,
    -- swings, flight, a flip in the air - where his head's going is his body's and a camera held back came off him
    -- ("flipping camera gets detached from body"); MOTION's own anywhere else, running and walking among it. Taken up at
    -- once as a move starts, let go slowly after. Not by how fast his chest turns, as at first: running sways it past
    -- that, and the head's bob came back at every stride - "the motion slider at 0% still shakes and moves it should be
    -- completely still", 2026-11-09.)
    do
        local montage = false
        montage = once.montage(pawn)
        local in_move = montage or climbing or rolling or swinging or flying or (not grounded and active > 0.5)
        local m_want = in_move and 1.0 or motion()
        local st = math.max(dt or 0.016, 0.001)
        motion_m = motion_m + (m_want - motion_m) * (1.0 - math.exp(-((m_want > motion_m) and 25.0 or 4.0) * st))
    end
    -- (pulled back: the view turned round after him - see PULLED BACK)
    local view_yaw = rot.Yaw
    if sw or sliding or climbing or flying or swinging then back_off = 0.0
    else
        local ok, y = pcall(back_view, pc, pawn, rot, dt)
        if ok and y then view_yaw = y end
    end
    local view_pitch = (look_v and not (sw or sliding)) and look_v or rot.Pitch
    -- LOOK SMOOTHING: the player's look eased - raw at 0, slow and cinematic at 100 - the turns of his body on top of it
    -- as they were ("all of it", 2026-11-09, from a list)
    do
        local sm = amount("look_smooth")
        if sm > 0.0 and not (sw or sliding or climbing or flying or swinging) then
            local k = 1.0 - math.exp(-(4.0 + 46.0 * (1.0 - sm) ^ 2) * math.max(dt or 0.016, 0.001))
            if not once.sm_yaw then once.sm_yaw, once.sm_pitch = view_yaw, view_pitch end
            once.sm_yaw = once.sm_yaw + wrap(view_yaw - once.sm_yaw) * k
            once.sm_pitch = once.sm_pitch + (view_pitch - once.sm_pitch) * k
            view_yaw, view_pitch = once.sm_yaw, once.sm_pitch
        else
            once.sm_yaw, once.sm_pitch = nil, nil
        end
    end
    local view = quat(view_pitch, view_yaw, 0.0)
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
    turned = turned and toward(turned, target, 1.0 - math.exp(-follow * rb * step)) or target
    -- (as the view takes it: MOTION's share, upright with LOCK HEAD UP)
    local turned_v = as_shown(turned)
    -- (outside STORROR's moves - a jump's or a landing's bend - only MOTION's share of it: still at 0)
    if motion_m < 0.999 then turned_v = part(turned_v, motion_m) end
    if angle_of(turned_v) > 0.05 then view = normalize(mul(turned_v, view)) end
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
        swung = swung and toward(swung, target, 1.0 - math.exp(-rate * rb * step)) or target
        local swung_v = as_shown(swung)
        if angle_of(swung_v) > 0.05 then view = normalize(mul(swung_v, view)) end
    end
    if once.trace then note("  view turned %.0f (target %.0f) ground %s", angle_of(turned), angle_of(target), tostring(grounded)) end
    local eye = once.head_at(pawn)
    local loc = pawn:K2_GetActorLocation()
    local rel = { X = eye.X - loc.X, Y = eye.Y - loc.Y, Z = eye.Z - loc.Z }
    if sliding then rel = { X = 0.0, Y = 0.0, Z = rel.Z + SLIDE_ABOVE } end
    if not eyes or math.abs(rel.X - eyes.X) + math.abs(rel.Y - eyes.Y) + math.abs(rel.Z - eyes.Z) > 150.0 then
        eyes = rel                          -- (a fresh start, or he was moved: no gliding there)
    else
        local calm = (grounded or sw ~= nil) and not (ok and turn)
        local k = 1.0 - math.exp(-(calm and FOLLOW_GROUND or FOLLOW_MOVES) * rb * step)
        local kz = 1.0 - math.exp(-(calm and FOLLOW_GROUND_UP or FOLLOW_MOVES) * rb * step)
        -- (with a flip under way, on his head itself: trailing it up to 15 cm, the eyes came back to his neck in a
        -- front flip and his body showed through the view - "during frontflip the body sticks through cam a bit",
        -- 2026-10-22)
        k, kz = math.max(k, active), math.max(kz, active)
        -- (climbing, his head bobs and dips against him all the way up: the eyes ease after it - they go with him, not
        -- with each bob - "its still pretty shakey", 2026-10-22)
        if climbing then
            k = 1.0 - math.exp(-CLIMB_FOLLOW * rb * step)
            kz = 1.0 - math.exp(-CLIMB_FOLLOW_UP * rb * step)
        elseif sliding then
            -- (over the middle of him, steady: up at once, so never inside him as he sits up, down slowly)
            k = 1.0 - math.exp(-FOLLOW_GROUND * rb * step)
            kz = 1.0 - math.exp(-((rel.Z > eyes.Z) and SLIDE_RISE or SLIDE_SINK) * rb * step)
        elseif rolling then
            k = 1.0 - math.exp(-ROLL_EYES * rb * step)
            kz = k
        end
        eyes = { X = eyes.X + (rel.X - eyes.X) * k, Y = eyes.Y + (rel.Y - eyes.Y) * k, Z = eyes.Z + (rel.Z - eyes.Z) * kz }
        if climbing or rolling then eyes = leash(eyes, rel, CLIMB_LEASH) end
    end
    -- MOTION: the camera from a fixed place on him to his head's own place, exactly - 0 none of his head's movement (no
    -- bob, no sway, no dip: only his body's own going), 1 his head itself, every bob of it ("at 0% the head should move
    -- none, no bobbing or nothing but at 100% it should follow the head exactly bobbing with the body", 2026-11-09). The
    -- fixed place: his eyes as they sit while he stands still (measured then, relative to him and the way he faces).
    local m = motion_m
    local fy = (facing or rot.Yaw)
    local yq = quat(0.0, fy, 0.0)
    if not stand_eye then stand_eye = rotate(inv(yq), rel) end
    pcall(function()
        local v = once.velocity(pawn)
        if grounded and active < 0.05 and not (climbing or rolling or sliding or sw) and (v.X * v.X + v.Y * v.Y) < 40.0 * 40.0 then
            local here = rotate(inv(yq), rel)
            local k = 1.0 - math.exp(-2.0 * step)
            stand_eye = { X = stand_eye.X + (here.X - stand_eye.X) * k, Y = stand_eye.Y + (here.Y - stand_eye.Y) * k,
                          Z = stand_eye.Z + (here.Z - stand_eye.Z) * k }
        end
    end)
    -- (turned with the view, as a head on its neck - not with his body, whose every small turn swung it sideways)
    local fixed = rotate(quat(0.0, view_yaw, 0.0), stand_eye)
    local shown = { X = fixed.X + (rel.X - fixed.X) * m, Y = fixed.Y + (rel.Y - fixed.Y) * m, Z = fixed.Z + (rel.Z - fixed.Z) * m }
    eye = { X = loc.X + shown.X, Y = loc.Y + shown.Y, Z = loc.Z + shown.Z }
    -- (the eyes sit in front of his face the way he faces, and turn over with him in a flip; they used to follow
    -- the way the player looks, which put the camera down into his collar when looking down, and the shirt was seen
    -- from inside: "seeing through charater model", 2026-10-14)
    -- (level, the way the player looks: walking backwards STORROR turns him round to face the camera, and eyes in
    -- front of his face were then behind him, looking down the back of his shirt: "if I just walk backwards I can
    -- see the body", 2026-10-14. The way he looks, level, never puts the camera into his collar either.)
    local face = quat(0.0, view_yaw, 0.0)
    if angle_of(turned_v) > 0.05 then face = normalize(mul(turned_v, face)) end
    local swung_f = as_shown(swung)
    if swung_f and angle_of(swung_f) > 0.05 then face = normalize(mul(swung_f, face)) end
    local mode = 1
    pcall(function() mode = pawn.CharacterMovement.MovementMode end)
    -- the face by his head bone: measured against the way he faces while he stands upright and still, used in
    -- proportion to how far over he is turned (fully from 30 degrees)
    pcall(function()
        local hr = pawn.Mesh:GetSocketRotation(once.head)
        local hq = quat(hr.Pitch, hr.Yaw, hr.Roll)
        local _, upright = facing_of(pawn)
        local still = false
        local v = once.velocity(pawn)
        still = on_ground(pawn) and upright and (v.X * v.X + v.Y * v.Y) < 40.0 * 40.0 and angle_of(turned) < 2.0
        local flat = quat(0.0, facing or rot.Yaw, 0.0)
        if still then
            local now_off = mul(inv(hq), flat)
            head_to_face = head_to_face and toward(head_to_face, now_off, 0.2) or now_off
        end
        if head_to_face then
            local k = math.min(1.0, angle_of(turned_v) / 30.0)
            if k > 0.0 then face = toward(face, normalize(mul(hq, head_to_face)), k) end
        end
    end)
    local off_eye = rotate(face, { X = EYES_FORWARD, Y = 0.0, Z = EYES_UP })
    if flying then
        -- (laid out along the flight: in front of his head along his body - chest to head - however steep the flight; put
        -- level in front of it, in a dive the eyes sat 8 cm back over his neck, his shoulders round the view)
        pcall(function()
            local h = once.head_at(pawn)
            local c = pawn.Mesh:GetSocketLocation(once.body)
            local ax, ay, az = h.X - c.X, h.Y - c.Y, h.Z - c.Z
            local n = math.sqrt(ax * ax + ay * ay + az * az)
            if n > 1.0 then off_eye = { X = ax / n * FLY_AHEAD, Y = ay / n * FLY_AHEAD, Z = az / n * FLY_AHEAD } end
        end)
    end
    -- (CAMERA X, Y, Z: the camera moved from his eyes - forward, right, up - as his face looks)
    do
        local o = cam_offset()
        if o.X ~= 0 or o.Y ~= 0 or o.Z ~= 0 then
            local d = rotate(face, o)
            off_eye = { X = off_eye.X + d.X, Y = off_eye.Y + d.Y, Z = off_eye.Z + d.Z }
        end
    end
    -- (THE FEEL OF MOVING: landing impact, lean, looking down in the air, sprint hands - see LANDING IMPACT)
    local feel_down, feel_fwd = 0.0, 0.0
    pcall(function()
        local st = math.max(dt or 0.016, 0.001)
        local v = once.velocity(pawn)
        local flat = math.sqrt(v.X * v.X + v.Y * v.Y)
        -- landing: out of the air onto the ground, as hard as he was falling just before
        if grounded and not feel.was_ground and feel.vz < -IMPACT_FROM then
            feel.impact = amount("impact") * math.min(1.0, (-feel.vz - IMPACT_FROM) / (IMPACT_FULL - IMPACT_FROM))
            feel.impact_t = 0.0
        end
        feel.was_ground, feel.vz = grounded, v.Z
        feel.impact_t = feel.impact_t + st
        local t = feel.impact_t
        local env = (t < 0.06) and (t / 0.06) or math.exp(-(t - 0.06) * 6.0)
        local dip = feel.impact * IMPACT_DIP * env
        local shake = feel.impact * IMPACT_SHAKE * math.sin(t * 45.0) * math.exp(-t * 9.0)
        -- lean: how fast the way he runs turns
        local target_lean = 0.0
        if flat > 200.0 then
            local h = math.deg(math.atan(v.Y, v.X))
            if feel.heading then
                local rate = wrap(h - feel.heading) / st
                target_lean = amount("lean") * LEAN_MAX * math.max(-1.0, math.min(1.0, rate / LEAN_FULL))
            end
            feel.heading = h
        else
            feel.heading = nil
        end
        feel.lean = feel.lean + (target_lean - feel.lean) * (1.0 - math.exp(-6.0 * st))
        -- sprint hands
        local sp = grounded and math.max(0.0, math.min(1.0, (flat - SPRINT_FROM) / (SPRINT_FULL - SPRINT_FROM))) or 0.0
        local want_sprint = amount("sprint_hands") * sp
        feel.sprint = feel.sprint + (want_sprint - feel.sprint) * (1.0 - math.exp(-4.0 * st))
        -- WALL RUN TILT: off the ground, quick along, not falling fast, a wall within reach to one side: the view leans
        -- away from it
        local want_wall = 0.0
        local wt = amount("wall_tilt")
        local side = 0                                       -- (a wall he runs along: 1 to his right, -1 to his left)
        if (wt > 0.0 or amount("air_look") > 0.0) and not grounded and flat > 300.0 and math.abs(v.Z) < 500.0
            and not (climbing or swinging or flying or sw or sliding) then
            pcall(function()
                local c = pawn:K2_GetActorLocation()
                local rx, ry = -v.Y / flat, v.X / flat          -- (to his right as he goes)
                if not valid(once.ksl) then once.ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end
                once.clear = once.clear or { R = 0, G = 0, B = 0, A = 0 }
                local function wall(sx)
                    local hit = {}
                    return once.ksl:LineTraceSingle(lib.world(), c, { X = c.X + rx * 90.0 * sx, Y = c.Y + ry * 90.0 * sx, Z = c.Z },
                        0, false, { pawn }, 0, hit, true, once.clear, once.clear, 0.0) == true
                end
                if wall(1) then side = 1 elseif wall(-1) then side = -1 end
            end)
            want_wall = side * wt * feel.WALL_MAX
        end
        -- LOOK DOWN IN AIR: off the ground (see below) - and not in a flip (the view
        -- turning over with him), a vault or a wall run ("look down in air not working properly", 2026-11-09: it tipped the
        -- view down the moment he left the ground, going up too, along walls and through flips)
        local _, mname = once.montage(pawn)
        -- (a flip: turned over past FLIP_DEG - not `active`, how fast his chest turns, which a plain jump reaches too and
        -- the tip never came: "its still not working", 2026-11-10)
        local airborne = not grounded and not (climbing or swinging or flying or sw or sliding) and side == 0
            and (once.turn_deg or 0.0) <= once.FLIP_DEG and mname:find("vault") == nil
        -- (from leaving the ground - not only falling fast, as for a while: STORROR's jumps go up for most of their time,
        -- in its flying mode, and the view hardly tipped - "rubberbanding still takes over before the camera can pan to
        -- legs", 2026-11-10)
        local want_air = airborne and amount("air_look") or 0.0
        feel.air = feel.air + (want_air - feel.air) * (1.0 - math.exp(-((want_air > feel.air) and 3.0 or 6.0) * st))
        -- (RUBBERBAND Y let go meanwhile - look_take: any time off the ground, not only falling with the view tipped -
        -- "looking down in air is still overridden by rubberbanding", 2026-11-10)
        once.air_on = not grounded or feel.air > 0.02
        feel.wall = feel.wall + (want_wall - feel.wall) * (1.0 - math.exp(-6.0 * st))
        -- BREATHING: standing still, nothing of STORROR's playing - a slow rise and fall, a little sway
        local br = amount("breathing") * motion()
        local still = grounded and flat < 30.0 and not once.montage(pawn)
        feel.breath_w = feel.breath_w + ((still and br or 0.0) - feel.breath_w) * (1.0 - math.exp(-1.5 * st))
        feel.breath_t = feel.breath_t + st
        local bt = feel.breath_t
        local b_pitch = feel.breath_w * 0.8 * math.sin(bt * 1.7)
        local b_roll = feel.breath_w * 0.4 * math.sin(bt * 0.9 + 1.0)
        local b_down = feel.breath_w * 0.6 * math.sin(bt * 1.7 + 0.5)
        -- JUMP FOV KICK: leaving the ground going up
        if feel.was_ground_k and not grounded and v.Z > 200.0 then feel.kick_t, feel.kick_amt = 0.0, amount("jump_kick") end
        feel.was_ground_k = grounded
        feel.kick_t = feel.kick_t + st
        local kt = feel.kick_t
        feel.kick = feel.kick_amt * feel.KICK_MAX * ((kt < 0.08) and (kt / 0.08) or math.exp(-(kt - 0.08) * 3.5))
        if feel.kick < 0.01 then feel.kick = 0.0 end
        -- SPRINT SHAKE: on the ground from a run to a full sprint (SPRINT_FROM to SPRINT_FULL), a quick small shake
        local sp_t = grounded and math.max(0.0, math.min(1.0, (flat - SPRINT_FROM) / (SPRINT_FULL - SPRINT_FROM))) or 0.0
        feel.shake_w = feel.shake_w + (amount("sprint_shake") * sp_t - feel.shake_w) * (1.0 - math.exp(-5.0 * st))
        feel.shake_t = feel.shake_t + st
        local sw_, ST = feel.shake_w, feel.shake_t
        local s_pitch = sw_ * (0.6 * math.sin(ST * 21.0) + 0.35 * math.sin(ST * 33.0 + 1.3))
        local s_roll = sw_ * 0.5 * math.sin(ST * 17.0 + 0.7)
        local s_down = sw_ * 0.4 * math.sin(ST * 27.0)
        -- on the view: tipped down (air, sprint, the shakes, breathing), rolled (lean, the wall, breathing, the shake); on
        -- the camera's place: the dip, the sprint, breathing, the shake
        -- (the air's tip never past looking straight down)
        local air_tip = math.min(feel.air * AIR_LOOK_MAX, math.max(0.0, (view_pitch or 0.0) + 85.0))
        local pitch_down = air_tip + feel.sprint * SPRINT_TILT + shake - b_pitch + s_pitch
        local roll = -feel.lean + feel.wall + b_roll + s_roll
        if math.abs(pitch_down) > 0.01 or math.abs(roll) > 0.01 then
            view = normalize(mul(view, quat(-pitch_down, 0.0, roll)))
        end
        feel_down = dip + feel.sprint * SPRINT_DOWN + b_down + s_down
        feel_fwd = feel.sprint * SPRINT_FWD
    end)
    if feel_down ~= 0.0 or feel_fwd ~= 0.0 then
        local d = rotate(face, { X = feel_fwd, Y = 0.0, Z = 0.0 })
        off_eye = { X = off_eye.X + d.X, Y = off_eye.Y + d.Y, Z = off_eye.Z + d.Z - feel_down }
    end
    local r = rotator(view)
    do
        local p = { X = eye.X + off_eye.X, Y = eye.Y + off_eye.Y, Z = eye.Z + off_eye.Z }
        if once.trace and last_cam then
            local moved = math.sqrt((p.X - last_cam.X) ^ 2 + (p.Y - last_cam.Y) ^ 2 + (p.Z - last_cam.Z) ^ 2)
            local fall = 0.0
            pcall(function() local v = once.velocity(pawn); fall = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) * step end)
            note("  cam moved %.1f (his own move %.1f) mode %s", moved, fall, tostring(mode))
        end
        last_cam = p
    end
    -- (the field of view, every tick: something of STORROR's keeps pulling the view camera's own down to about 72)
    pcall(function()
        local cc = cam.CameraComponent
        local want = fov()
        if math.abs(cc.FieldOfView - want) > 0.01 then cc.FieldOfView = want end
    end)
    pcall(function()
        local want = clear_of_level(pawn, { X = eye.X + off_eye.X, Y = eye.Y + off_eye.Y, Z = eye.Z + off_eye.Z })
        local now = os.clock()
        if climbing then climb_t = now end
        if now - climb_t < CLIMB_LINGER and climb_cam then
            -- (easing back to following outright as the linger runs out)
            local rate = CLIMB_WORLD * rb * (climbing and 1.0 or (1.0 + 6.0 * (now - climb_t) / CLIMB_LINGER))
            local k = 1.0 - math.exp(-rate * step)
            want = leash({ X = climb_cam.X + (want.X - climb_cam.X) * k, Y = climb_cam.Y + (want.Y - climb_cam.Y) * k,
                     Z = climb_cam.Z + (want.Z - climb_cam.Z) * k }, want, CLIMB_LEASH)
        end
        climb_cam = (now - climb_t < CLIMB_LINGER) and want or nil
        if climbing and not climb_cam then climb_cam = want end
        -- (riding his capsule: placed here, before the game moves him this frame, the camera was drawn a whole frame of
        -- his move behind him - 7 cm a frame at a run, more at a sprint, changing frame to frame - so his shirt and arms
        -- jumped about in view: "shirts lagging like crazy", 2026-11-09, measured 6.7 cm. Attached, the game takes it
        -- along as it moves him (0.1 cm); its turn stays ours alone - rotation absolute.)
        local paddr = pawn:GetAddress()
        if once.cam_on ~= paddr then
            once.cam_on = paddr
            local oka, ea = pcall(function()
                local root = cam.RootComponent
                root:K2_AttachToComponent(pawn.RootComponent, once.none, 1, 1, 1, false)
                root:SetAbsolute(false, true, true)
            end)
            log("first person: camera %s", oka and "riding his capsule" or ("not attached (" .. tostring(ea) .. ")"))
        end
        cam:K2_TeleportTo(swept(pawn, want), r)
    end)
    local same = false
    pcall(function() same = pc:GetViewTarget():GetAddress() == cam:GetAddress() end)
    if not same then pcall(function() pc:SetViewTargetWithBlend(cam, 0.0, 0, 0.0, false) end) end
    -- (the look's yaw as we leave it, for STICK TURN RATE's next measure of the stick's turn)
    pcall(function() look_y = pc:GetControlRotation().Yaw end)
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
    once.body_gone, once.gone_t = false, nil
    once.pp_key, once.sm_yaw, once.sm_pitch, once.clip_set = nil, nil, nil, nil
    once.light, once.light_cam, once.light_i = nil, nil, nil
    cam, head, was_on, eyes, turned, air, active, last_d, facing, hidden, swim_last = nil, nil, false, nil, nil, 0.0, 0.0, nil, nil, nil, nil
    move_facing = nil
    slide_t, slide_pitch = nil, nil
    fish, fish_cam, fish_set = nil, nil, nil
    stand_eye = nil
    motion_m = 1.0
    skin_copy, skin_copy_of = nil, nil
    vig_set = nil
    once.cam_on = nil
end

-- (the look as we keep it, for checking over the dev channel: our pitch, STORROR's, the rates learned)
function M.look() return look_v, look_c, rate_mouse, rate_stick end

-- (for checking the conversions over the dev channel)
M.debug = { quat = quat, rotator = rotator, mul = mul, inv = inv, body_turn = body_turn, rest = function() return rest end,
            set_trace = function(on) once.trace = on and true or false end,
            turn = function() return once.turn_deg, active, once.body_gone end,
            air = function() return once.air_on, feel.air end,
            feel = function() return feel end,
            trace = function(n)
                local out = {}
                for i = n - 1, 0, -1 do
                    local e = trace[((trace_n - 1 - i) % 400) + 1]
                    if e then out[#out + 1] = e end
                end
                return table.concat(out, " | ")
            end }

return M
