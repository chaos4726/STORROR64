-- SM64Map moving platforms: Mario 64's seesaws, sliding and circling platforms, ferris wheels, lifts on
-- tracks and elevators, moving the way the game moves them.
--
-- Each platform is an actor of its own carrying the model and its collision, so the player can stand on
-- it and is carried along by the game's own "standing on something that moves" handling. The behaviours
-- below are Mario 64's (src/game/behaviors/*.inc.c), kept in its own terms: positions in Mario 64 units,
-- angles in its 16-bit units, one step per Mario 64 frame (30 a second). What is drawn is blended between
-- the last two steps, so the motion stays smooth at any frame rate.
local lib = require("lib")
pcall(require, "squish")       -- (squished under a Thwomp, the Mario 64 way)
local function squish() return package.loaded["squish"] end
local log = lib.log
local OFFSET = lib.OFFSET

local P = { list = {}, on = nil }
P.TOX_HOLE = 150.0           -- (the tox box's hole: 154 either side of its middle)
local S = 0.75                  -- cm per Mario 64 unit
local STEP = 1 / 30
local H = {}                    -- build_floor / floor_hit, handed over by game.lua

local sqrt, sin, cos, atan, asin, floor, abs, pi, deg = math.sqrt, math.sin, math.cos, math.atan, math.asin, math.floor, math.abs, math.pi, math.deg

function P.setup(h) H = h end

-- ------------------------------------------------------------ Mario 64's arithmetic
local function sins(a) return sin(a * pi / 32768.0) end
local function coss(a) return cos(a * pi / 32768.0) end
local function atan2s(y, x) return atan(x, y) * 32768.0 / pi end        -- its argument order: (z, x) gives a yaw
local function trunc(v) if v >= 0 then return floor(v) end return -floor(-v) end
local function s16(a) a = floor(a) % 65536; if a >= 32768 then a = a - 65536 end; return a end
local function clampf(v, lo, hi)
    if v < lo then return lo, true elseif v > hi then return hi, true end
    return v, false
end

local function approach(v, target, step)
    if v < target then v = v + step; if v > target then v = target end
    elseif v > target then v = v - step; if v < target then v = target end end
    return v
end

local function approach_signed(v, target, inc)
    v = v + inc
    if inc >= 0 then if v > target then v = target end
    elseif v < target then v = target end
    return v
end

local function approach_angle(cur, target, inc)
    local d = s16(target - cur)
    if d >= 0 then
        if d > inc then return cur + inc end
    elseif d < -inc then
        return cur - inc
    end
    return cur + d
end

local function oscillate_toward(value, vel, target, close, accel, slowdown)
    local start = value
    value = value + trunc(vel)
    if value == target or ((value - target) * (start - target) < 0 and vel > -close and vel < close) then
        return target, 0.0
    end
    if value >= target then accel = -accel end
    if vel * accel < 0.0 then accel = accel * slowdown end
    return value, vel + accel
end

-- ------------------------------------------------------------ from Mario 64 space to the scene
-- The model's forward, right and up axes in scene space for Mario 64 object angles (pitch, yaw, roll),
-- as mtxf_rotate_zxy_and_translate builds them. Scene space is X = -z, Y = x, Z = y, and a model's
-- mesh was exported the same way, so its forward is the model's -Z, its right the model's X, its up Y.
local function axes(pitch, yaw, roll)
    local sx, cx = sins(pitch), coss(pitch)
    local sy, cy = sins(yaw), coss(yaw)
    local sz, cz = sins(roll), coss(roll)
    local exx, exy, exz = cy * cz + sx * sy * sz, cx * sz, -sy * cz + sx * cy * sz
    local eyx, eyy, eyz = -cy * sz + sx * sy * cz, cx * cz, sy * sz + sx * cy * cz
    local ezx, ezy, ezz = cx * sy, -sx, cx * cy
    return ezz, -ezx, -ezy, -exz, exx, exy, -eyz, eyx, eyy
end

local function rotator(fx, fy, fz, rx, ry, rz, ux, uy, uz)
    if fz > 0.99999 or fz < -0.99999 then
        -- pointing straight up or down: yaw and roll turn about the same line, so all of it goes to yaw
        return { Pitch = (fz > 0) and 90.0 or -90.0, Yaw = deg(atan(-rx, ry)), Roll = 0.0 }
    end
    return { Pitch = deg(asin(fz)), Yaw = deg(atan(fy, fx)), Roll = deg(atan(-rz, uz)) }
end

-- ------------------------------------------------------------ making one
local function prepare(tpl)
    if tpl.ready then return end
    tpl.ready = true
    local c = tpl.collision
    tpl.floor = (c and H.build_floor) and H.build_floor({ c }) or false
    local r2 = 0.0
    if c then
        local pos = c.pos
        for i = 1, #pos, 3 do
            local d = pos[i] * pos[i] + pos[i + 1] * pos[i + 1] + pos[i + 2] * pos[i + 2]
            if d > r2 then r2 = d end
        end
    end
    tpl.radius = sqrt(r2)
end

-- A platform of template `key` at Mario 64 position (x, y, z), angles in degrees, scale in Mario 64 axes.
local function make(world, templates, key, x, y, z, ang, scale)
    local tpl = templates and key and templates[key]
    if not tpl then return nil end
    prepare(tpl)
    scale = scale or { 1.0, 1.0, 1.0 }
    local us = { scale[3], scale[1], scale[2] }                 -- along the mesh's own X, Y, Z
    local actor, mesh = nil, nil
    if not P.dry then                                           -- (P.dry: behaviours only, nothing built; for tests)
        actor = lib.spawn_actor(world, { X = -z * S + OFFSET.X, Y = x * S + OFFSET.Y, Z = y * S + OFFSET.Z }, 0.0)
        if not actor then return nil end
        local pmc = lib.add_pmc(actor)
        if not pmc then lib.destroy(actor); return nil end
        lib.add_sections(world, pmc, tpl.sections or {})
        if tpl.collision then
            -- (the sides under the edges he swings from: solid still, but out of STORROR's sight, in a piece of its own
            -- on the same actor - so it moves, hides and goes with it. ledges.lua. WF's islands keep their ring)
            local coll, hidden = { tpl.collision }, nil
            -- (and none on Rainbow Ride's carpets: STORROR's ledge grab takes nothing that moves - their poles instead,
            -- carpet_bar)
            if not tostring(key):find("wf_seg7_collision_rotating_platform", 1, true) and not tostring(key):find("rr_geo_000848", 1, true) then
                pcall(function()
                    if tpl.swing == nil then
                        local main, h = require("ledges").split({ tpl.collision })
                        tpl.swing = { main, h }
                    end
                    if tpl.swing[2] then coll, hidden = tpl.swing[1], tpl.swing[2] end
                end)
            end
            lib.add_collision(pmc, coll)
            if hidden then
                local hp = lib.add_pmc(actor)
                if hp then lib.add_collision(hp, { hidden }); require("ledges").hide(hp) end
            end
        end
        mesh = pmc
        if us[1] ~= 1.0 or us[2] ~= 1.0 or us[3] ~= 1.0 then
            pcall(function() actor:SetActorScale3D({ X = us[1], Y = us[2], Z = us[3] }) end)
        end
    end
    ang = ang or { 0, 0, 0 }
    local u = 65536.0 / 360.0
    local p = {
        actor = actor, pmc = mesh, tpl = tpl, uscale = us,
        x = x, y = y, z = z, hx = x, hy = y, hz = z,
        pitch = floor(ang[1] * u + 0.5), yaw = floor(ang[2] * u + 0.5), roll = floor(ang[3] * u + 0.5),
        mpitch = 0, timer = 0, action = 0, bp = 0, b1 = 0, b2 = 0, w = 0,
    }
    p.myaw = p.yaw
    local reach = tpl.radius * math.max(us[1], us[2], us[3]) + 200.0
    p.reach2 = reach * reach
    return p
end

local function snapshot(p)
    p.px, p.py, p.pz, p.ppitch, p.pyaw, p.proll = p.x, p.y, p.z, p.pitch, p.yaw, p.roll
end

local function enlist(p)
    snapshot(p)
    P.list[#P.list + 1] = p
end

-- ------------------------------------------------------------ the behaviours
-- Besides `step`, a behaviour may have `hum` (the sound Mario 64 keeps it making, every frame, while it does
-- what it does: a held, looping sound; it may also give a reach of its own, in Mario 64 units) and `changed`
-- (called when its action changes, to set `p.shot`, a sound played once). Sounds are louder the nearer the
-- player, and silent beyond SOUND_REACH.
local B = {}

-- a piece of the level that the game treats as an object but that never moves here
B.static = {}

-- Something heavy coming down on the athlete: three wedges of power, and he is thrown out from under it - or, `flat`
-- (a Thwomp, a Grindel), squished under it. `r` is how far from its middle it covers (Mario 64 units); once per fall.
-- (put out from under it: just past its edge, r from its middle the way he is from it, and away along the floor -
-- STORROR's own moves cleared and his speed set, as a launch alone was undone by its root motion and he stayed under
-- it, and ended up inside it: "getting smashed by thwomp needs fixed im currently inside him", 2026-10-17)
local function out_from_under(p, m, r, speed)
    local pawn = lib.pawn()
    if not pawn then return end
    local dx, dz = m.x - p.x, m.z - p.z
    local d = sqrt(dx * dx + dz * dz)
    if d < 1.0 then dx, dz, d = sins(p.yaw), coss(p.yaw), 1.0 end
    local ux, uz = dx / d, dz / d
    local nx, nz = p.x + ux * (r + 10.0), p.z + uz * (r + 10.0)
    local G = package.loaded["game"]
    pcall(function()
        local l = pawn:K2_GetActorLocation()
        pawn:K2_SetActorLocation({ X = -nz * S + OFFSET.X, Y = nx * S + OFFSET.Y, Z = l.Z }, false, {}, true)
    end)
    if G and G.reset_cloth then pcall(G.reset_cloth, pawn) end
    if speed then
        if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
        pcall(function()
            local cm = pawn.CharacterMovement
            cm:SetMovementMode(3, 0)
            cm.Velocity = { X = -uz * speed, Y = ux * speed, Z = 250.0 }
        end)
    end
end

local function crush(p, m, r, what, flat)
    local dx, dz = m.x - p.x, m.z - p.z
    if not p.crushed and dx * dx + dz * dz < r * r and m.y < p.y and m.y > p.y - 220.0 and m.y > p.hy - 60.0 then
        p.crushed = true
        -- (pressed flat under it, held, and up again as it lifts: squish.lua; "well your supposed to get squished under
        -- him", 2026-10-17)
        local SQ = flat and squish()
        if SQ and SQ.start(lib.pawn(), {
                bottom = function() return (p.wz or p.y * S) + OFFSET.Z end,
                floor = (p.hy - 1.0) * S + OFFSET.Z, grounded = m.ground, what = what }) then
            return
        end
        -- (when he cannot be squished - flying, carried, knocked flat - three wedges and out from under it)
        local HP = _G.HEALTH
        if HP and HP.grace <= 0 and not HP.dead_t then HP.damage(3, what) end
        out_from_under(p, m, r + 37.0, 600.0)
    end
end

-- Squeezed into the ceiling: what he stands on going up - a Thwomp or Grindel rising, a hopping Grindel, the pyramid's
-- rolling Spindel bobbing up (179 cm under the ceiling there, and he is 176) - with the level's ceiling over him closer
-- than his own height: pressed flat between them as it goes on up, carried with it, and himself again once there is
-- room (mario.c: a moving floor or ceiling and too little room between them, INPUT_SQUISHED - Mario's 150 units, here
-- the athlete's height; "add squish animation to when you get squeezed into the ceiling by thwomp and rolling enemie",
-- 2026-10-22). squish.lua follows the platform with him. (x, y, z): his feet, scene cm.
local SQUEEZE_ROOM = 172.0
local HALF_ROOM = 88.0

-- The Spindel's size, Mario 64 units: half its square side (it rolls on that) and half its length (across the corridor)
local function spindel_size(p)
    if p.sq_half then return p.sq_half, p.long_half end
    local sq, long = 189.0, 307.0
    pcall(function()
        local c, a, b = p.tpl.collision.pos, 0.0, 0.0
        for i = 1, #c, 3 do a = math.max(a, abs(c[i]), abs(c[i + 2])); b = math.max(b, abs(c[i + 1])) end
        if a > 0.0 and b > 0.0 then sq, long = a * p.uscale[1] / S, b * p.uscale[1] / S end
    end)
    p.sq_half, p.long_half = sq, long
    return sq, long
end

-- Where he goes down off a Spindel he was squeezed on: on the corridor floor behind it (the way it is rolling from),
-- clear of its corners as it turns, where he was across the corridor. Scene cm with the offset: x, y, his feet.
local function spindel_behind(p, y)
    local sq = spindel_size(p)
    local d = (p.f8 == 0) and 1.0 or -1.0                       -- (the way it rolls, or rolls next after its rest)
    local bz = p.z - d * (sq * 1.42 + 75.0)
    local sx = -bz * S
    local f = H.floor_z and H.floor_z(sx, y, p.hy * S)
    if not f or f < (p.hy - sq) * S - 60.0 then return nil end  -- (no floor there: he stays on it)
    return sx + OFFSET.X, y + OFFSET.Y, f + OFFSET.Z
end

local function squeeze(m, x, y, z)
    local p = m.plat
    if not (p and p.wz and p.py and H.ceil_z) or p.gone then return end
    if p.y <= p.py + 0.01 then return end                       -- (not going up)
    local SQ = squish()
    if not SQ or SQ.active() then return end
    local c = H.ceil_z(x, y, z + 1.0)
    if not c or c - z >= SQUEEZE_ROOM then return end
    -- (a ceiling closer than half his height is not over his head - he could not be standing under it - but something at
    -- his feet seen from below: a sinking platform in the Fire Sea's lava found one 2 cm over his feet as he landed on
    -- it off the lava, flattened him under nothing, and held him so till the 10 s were up - "player got stuck in
    -- flattened state?", 2026-10-24. A real one comes down on him from his own height.)
    if c - z < HALF_ROOM then return end
    local pawn = lib.pawn()
    if not pawn then return end
    local wx0, wy0, wz0 = p.wx, p.wy, p.wz
    local what = (p.o and p.o.bhv) or "a platform"
    -- (the Spindel rolls on under the corridor's ceiling: never room on it, so he is put down off it once flat)
    local out = (p.def == B.spindel) and function() return spindel_behind(p, y) end or nil
    -- (the ceiling over where it has carried him now, not where it caught him: Rainbow Ride's carpet took him on past
    -- the low plank by the start, the plank's height was kept, and he stayed flat for the full 10 s and was let go off
    -- the carpet into the sky - "just got crushed", 2026-11-02)
    local function ceil_now()
        local sx, sy = (p.wx or wx0) - wx0, (p.wy or wy0) - wy0
        local cc = H.ceil_z(x + sx, y + sy, z + ((p.wz or wz0) - wz0) + 1.0)
        return (cc or 1.0e9) + OFFSET.Z
    end
    if SQ.start(pawn, { bottom = ceil_now,
                        floor_fn = function() return z + ((p.wz or wz0) - wz0) + OFFSET.Z end,
                        shift_fn = function() return (p.wx or wx0) - wx0, (p.wy or wy0) - wy0 end,
                        out = out, grounded = true, what = what }) then
        log("%s squeezed him into the ceiling (%.0f cm of room)", what, c - z)
    end
end

-- (never left inside one: down, slamming or rising, his feet under its top and inside its round - he walked under it
-- while it was down, or it came down where the crush missed him - he is put out at its edge)
-- (Only truly inside it: his middle 15 cm and more inside its square sides, and his feet well down in it - 150 cm and
-- more under its top. A circle round it, and feet anywhere under its top, also took him hanging on its edge or climbing
-- up onto it, and kept shoving him off: "getting stuck on the edge of the thwomp", 2026-10-17.)
local function box_half(p)
    if p.half_w then return p.half_w end
    local h = 150.0
    pcall(function()
        local c, mx = p.tpl.collision.pos, 0.0
        for i = 1, #c, 3 do mx = math.max(mx, abs(c[i]), abs(c[i + 1])) end
        if mx > 0.0 then h = mx * p.uscale[1] / S end
    end)
    p.half_w = h
    return h
end

-- Rolled onto: a Tox Box coming down over him where he stands - its underside within 150 units of his floor
-- (tox_box.inc.c: it is a moving ceiling over him, INPUT_SQUISHED) - presses him flat; up again once it has rolled on
-- off him ("add squish animation to when you get squeezed ... by ... rolling enemie", 2026-10-22). Its size is its
-- own collision's, half 256 units.
local function roll_crush(p, m, what)
    local SQ = squish()
    if not SQ then return end
    if p.crushed then
        if not SQ.active() then p.crushed = false end
        return
    end
    if SQ.active() or not m.ground then return end
    local half = box_half(p)
    local dx, dz = m.x - p.x, m.z - p.z
    if abs(dx) > half + 10.0 or abs(dz) > half + 10.0 then return end      -- (not under it)
    -- (its hole: a pocket 308 across and 409 deep in one face of it - ssl_seg7_collision_tox_box, its -y face - and that
    -- face coming down, its middle is safe: he is in the hole as it lands round him. "you get crushed by moving cubes even
    -- if you stand in the middle where the hole is", 2026-10-23. The face's way down: -cos pitch * cos roll, Mario 64's
    -- turning of it, roll then pitch then yaw.)
    -- (where it will lie and which way up when this roll is done - it comes down on him mid-roll, tipped over and
    -- still short of his square: measured from there it took him for off its hole, "still crushing player")
    if p.def == B.tox_box then
        local pitch, roll, lx, lz = P.tox_landing(p)
        -- (rolling off him - it lands a square on - it lifts away from him and crushes nothing: it did, the moment it
        -- left him safe in its hole, twice - "still crushing player", 2026-10-23)
        if abs(m.x - lx) > half or abs(m.z - lz) > half then return end
        if abs(m.x - lx) < P.TOX_HOLE and abs(m.z - lz) < P.TOX_HOLE and coss(pitch) * coss(roll) > 0.85 then return end
    end
    local under = p.y - half                                                -- (its underside: its middle less half)
    if under - m.y > 150.0 or under < m.y - 60.0 then return end  -- (still over his head, or he is up on it)
    local pawn = lib.pawn()
    if not pawn then return end
    local hx, hz = m.x, m.z
    p.crushed = true
    SQ.start(pawn, {
        bottom = function()
            -- (rolled on off him: nothing over him)
            if abs(hx - p.x) > half or abs(hz - p.z) > half then return 1.0e6 end
            return (p.wz or p.y * S) - half * S + OFFSET.Z
        end,
        floor = m.y * S + OFFSET.Z, grounded = true, what = what })
end

-- (beside it as it comes down - his middle out of its crush, his body under its edge: its collision closing on his
-- shoulder, the engine put him out downward, through the floor - "next to the thwomp ... when it came down it pushed me
-- through the map", 2026-10-17. Just before it reaches him he is put clear of its side, once a fall.)
local function edge_clear(p, m)
    if p.edged or p.crushed then return end
    if not (m.y < p.y and m.y > p.y - 300.0 and m.y > p.hy - 60.0) then return end
    local half = box_half(p)
    local dx, dz = m.x - p.x, m.z - p.z
    local lx = dx * coss(p.yaw) - dz * sins(p.yaw)
    local lz = dx * sins(p.yaw) + dz * coss(p.yaw)
    local big = math.max(abs(lx), abs(lz))
    if big >= half + 45.0 then return end                                   -- (clear of it)
    if dx * dx + dz * dz < (p.reach_r or 150.0) ^ 2 then return end         -- (under it: the crush)
    p.edged = true
    local d = sqrt(dx * dx + dz * dz)
    local k = (d > 1.0) and big / d or 1.0
    out_from_under(p, m, (half + 55.0) / math.max(k, 0.5) - 10.0, nil)
    log("thwomp: the athlete at its edge as it came down - put clear of it")
end

local function not_inside(p, m, r)
    local G = package.loaded["game"]
    if G and (G.dying or (G.intangible and G.intangible())) then return end
    local SQ = squish()
    if SQ and SQ.active() then return end                       -- (squished under it: held there till it lifts)
    local top = p.y + (p.top_h or 200.0)
    if m.y < p.y - 40.0 or m.y > top - 200.0 then return end     -- (under it in the air, or up on it or climbing on)
    local half = box_half(p)
    local dx, dz = m.x - p.x, m.z - p.z
    local lx = dx * coss(p.yaw) - dz * sins(p.yaw)
    local lz = dx * sins(p.yaw) + dz * coss(p.yaw)
    local inner = half - 20.0
    if abs(lx) >= inner or abs(lz) >= inner then return end
    -- out the way he is from its middle, past its side
    local d = sqrt(dx * dx + dz * dz)
    local k = (d > 1.0) and math.max(abs(lx), abs(lz)) / d or 1.0
    out_from_under(p, m, half / math.max(k, 0.5) + 30.0, nil)
end

-- (the camera passes through it: STORROR's camera boom probes on the Camera channel and pulled in close whenever one
-- came between it and him, or sat on him - "it starts zooming in when it collides with the thwomp", 2026-10-17)
local function camera_through(p)
    if p.pmc then pcall(function() p.pmc:SetCollisionResponseToChannel(4, 0) end) end
end

-- Riding a Thwomp down. Mario 64 moves Mario with the platform under him (apply_platform_displacement). Standing on
-- it, the engine carries him (it is his floor); only if it drops out from under him - he is falling, over its top - he
-- falls with it, a little faster, so he lands back on it, never pushed up and never put to falling by this (forcing
-- the fall every frame flipped STORROR between falling and landing each frame, and a push up toward its top threw him
-- off it: "getting thrown off randomly", 2026-10-17). The ride is no fall: no fall damage, and at the slam, falling,
-- STORROR forgets the drop. Called every frame, after it is drawn.
function P.thwomp_ride(p, dt)
    if not p.rider then return end
    local pawn = lib.pawn()
    if not pawn then p.rider = nil; return end
    local G = package.loaded["game"]
    pcall(function()
        local cm = pawn.CharacterMovement
        local l = pawn:K2_GetActorLocation()
        local v = cm.Velocity
        local top = (p.wz or p.y * S) + (p.top_h or 200.0) * S + OFFSET.Z
        local feet = l.Z - ((G and G.half) or 88.0)
        local wx, wy = (p.wx or -p.z * S) + OFFSET.X, (p.wy or p.x * S) + OFFSET.Y
        local r = (p.reach_r or 150.0) * S + 30.0
        local off = (l.X - wx) ^ 2 + (l.Y - wy) ^ 2 > r * r or feet > top + 120.0 or feet < top - 60.0
        local vz = p.ride_top and (top - p.ride_top) / math.max(dt, 0.005) or 0.0
        p.ride_top = top
        if G then G.peak = l.Z end                          -- (the ride is no fall)
        local falling = cm.MovementMode == 3
        if p.ride_end or off then
            lib.log("thwomp: ride down over (%s)", off and "off it" or "the slam")
            p.rider, p.ride_end, p.ride_top, p.ride_cloth = nil, nil, nil, nil
            if not off and falling and G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
            -- (his shirt back in its shape after the stop)
            if not off and G and G.reset_cloth then pcall(G.reset_cloth, pawn) end
            return
        end
        -- (his shirt and trousers carried down with him, not swung: 3 m in half a second and a dead stop threw them up
        -- round his chest - "shirt thing again", 2026-10-17)
        if not p.ride_cloth then p.ride_cloth = (G and G.cloth_comps) and G.cloth_comps(pawn) or {} end
        for _, c in ipairs(p.ride_cloth) do pcall(function() c:ForceNextUpdateTeleport() end) end
        if falling and vz < 0.0 and v.Z > vz - 60.0 then
            cm.Velocity = { X = v.X, Y = v.Y, Z = math.max(-3000.0, vz - 60.0) }
        end
    end)
end

local function ride_thwomps(dt)
    for _, p in ipairs(P.list) do
        if p.rider and p.def == B.thwomp then P.thwomp_ride(p, dt) end
    end
end

-- where the level's own floor is under (x, z), at or below height y (Mario 64 units), or nil
local function ground_under(x, y, z)
    if not H.floor_z then return nil end
    local fz = H.floor_z(-z * S, x * S, y * S)
    return fz and fz / S
end

-- bhvThwomp, bhvThwomp2, bhvGrindel: rises, waits at the top, drops, slams down with a thud, waits, and again
-- (thwomp.inc.c; asked 2026-10-14 overnight, "all the enemies"). Caught underneath as it comes down, the athlete
-- is squished (squish.lua): flat under it, three wedges of power, and up again once it lifts.
B.thwomp = {
    init = function(p)
        local fy = ground_under(p.x, p.y + 300.0, p.z)
        if fy then p.y = fy + 1.0; p.hy = p.y end
        p.vy, p.wait = 0.0, 0
        p.action = 4                            -- (it starts down, at rest)
        camera_through(p)
        p.reach_r = (p.o.grindel and 210.0 or 150.0) * p.uscale[2]
        -- (its height, from its own collision: cm up its mesh's Z, scaled)
        p.top_h = 200.0
        pcall(function()
            local c, mx = p.tpl.collision, 0.0
            for i = 3, #c.pos, 3 do if c.pos[i] > mx then mx = c.pos[i] end end
            if mx > 0.0 then p.top_h = mx * p.uscale[3] / S end
        end)
    end,
    step = function(p, m)
        local a = p.action
        if a == 0 then                          -- raise
            if p.timer > p.b2 + 40 then p.action = 1; p.y = p.y + 5.0 else p.y = p.y + 10.0 end
            p.crushed, p.edged = false, nil
        elseif a == 1 then                      -- at the top a while
            if p.timer == 0 then p.wait = math.random(10, 39) end
            if p.timer > p.wait then
                p.action = 2
                if m.plat == p then
                    p.rider, p.ride_top = true, nil
                    lib.log("thwomp: riding it down")
                end
            end
        elseif a == 2 then                      -- drop
            p.vy = p.vy - 4.0
            p.y = p.y + p.vy
            edge_clear(p, m)
            crush(p, m, p.reach_r, p.o.grindel and "a grindel" or "a thwomp", true)
            if p.y < p.hy then p.y, p.vy, p.action = p.hy, 0.0, 3 end
        elseif a == 3 then                      -- the slam
            if p.timer == 0 then
                p.shot = "en_thwomp"
                if p.rider then p.ride_end = true end
            end
            if p.timer >= 10 then p.action = 4 end
        else                                    -- at the bottom a while
            if p.timer == 0 then p.wait = math.random(20, 29) end
            if p.timer > p.wait then p.action = 0 end
        end
        if p.action ~= 2 then not_inside(p, m, p.reach_r) end
    end,
}

-- bhvHorizontalGrindel (horizontal_grindel.inc.c): hops along, 11 units a frame, with a thud each landing; once it
-- has gone 300 from home it waits, turns right round and hops back the other way. Drawn turned a quarter.
B.hgrindel = {
    init = function(p)
        local fy = ground_under(p.x, p.y + 300.0, p.z)
        if fy then p.y = fy; p.hy = fy end
        p.target, p.vy, p.fwd, p.grav = p.yaw, 0.0, 0.0, -4.0
        camera_through(p)
        p.ground, p.landed, p.dist = true, true, 0.0
        p.yaw = p.myaw + 0x4000
    end,
    step = function(p, m)
        if p.ground then
            if not p.landed then
                p.shot = "en_thwomp"
                p.landed = true
                p.dist = sqrt((p.x - p.hx) ^ 2 + (p.z - p.hz) ^ 2)
                p.fwd = 0.0
                p.timer = 0
            end
            local turn = s16(p.target - p.myaw)
            if abs(turn) <= 0x400 then
                p.myaw = p.target
                if p.timer > 60 then
                    if p.dist > 300.0 then
                        p.target = p.target + 0x8000
                        p.dist = 0.0
                    else
                        p.shot = "king_jump"
                        p.fwd, p.vy, p.grav, p.ground = 11.0, 70.0, -4.0, false
                        p.crushed = false
                    end
                end
            else
                p.myaw = p.myaw + (turn > 0 and 0x400 or -0x400)
                p.timer = 0
            end
        else
            p.landed = false
            if p.vy < 0.0 then p.grav = -16.0 end
        end
        p.yaw = p.myaw + 0x4000
        -- (cur_obj_move_standard, without the walls)
        if not p.ground then
            p.vy = p.vy + p.grav
            p.y = p.y + p.vy
            p.x = p.x + p.fwd * sins(p.myaw)
            p.z = p.z + p.fwd * coss(p.myaw)
            if p.vy < 0.0 then crush(p, m, 200.0 * p.uscale[2], "a grindel", true) end
            local fy = ground_under(p.x, p.y + 100.0, p.z)
            if fy and p.y <= fy then p.y, p.vy, p.ground = fy, 0.0, true end
            if not fy and p.y < p.hy - 2000.0 then          -- (off everything: home again)
                p.x, p.y, p.z, p.vy, p.ground = p.hx, p.hy, p.hz, 0.0, true
            end
        end
    end,
}

-- Rolled over by it: on the corridor floor in its way as it comes on, it presses him flat under it (Mario 64: its
-- faces close on him as a moving ceiling, INPUT_SQUISHED) and he is himself again once it has rolled on off him. It
-- squeezed him only when he stood on it before, and rolling into him it shoved him about inside it: "he doesnt crush
-- you correctly", 2026-10-23. Its underside over him: down as its middle comes over him, up again as it goes on.
local function spin_crush(p, m)
    local SQ = squish()
    if not SQ then return end
    if p.crushed then
        if not SQ.active() then p.crushed = false end
        return
    end
    if SQ.active() or not m.ground or p.f4 == -1 then return end      -- (resting, it rolls onto nothing)
    local sq, long = spindel_size(p)
    local dx, dz = m.x - p.x, m.z - p.z
    if abs(dx) > long + 10.0 or abs(dz) > sq + 40.0 then return end   -- (not under it, or not yet touching him)
    local d = (p.f8 == 0) and 1.0 or -1.0
    if dz * d < -40.0 then return end                                 -- (behind it: it rolls away from him)
    local base = p.hy - sq                                            -- (the floor it rolls on)
    if m.y > base + 60.0 or m.y < base - 100.0 then return end        -- (up on it, or somewhere under it)
    local pawn = lib.pawn()
    if not pawn then return end
    local hz, fy = m.z, m.y
    p.crushed = true
    if SQ.start(pawn, {
            bottom = function()
                local over = abs(hz - p.z) - (sq - 40.0)
                if over < 0.0 then over = 0.0 end
                return (fy + over * 2.0) * S + OFFSET.Z
            end,
            floor = fy * S + OFFSET.Z, grounded = true, what = "spindel" }) then
        log("spindel: rolled over him (%.0f off its middle)", dz)
    end
end

local function spindel_roll(p)
    if p.f4 == -1 then
        if p.timer == 32 then p.f4, p.timer = 0, 0 else return end
    end
    do
        local n = abs(10 - p.f4) - 6
        if n < 0 then n = 0 end
        if p.timer == n + 8 then
            p.timer = 0
            p.f4 = p.f4 + 1
            if p.f4 == 20 then p.f8, p.f4 = 1 - p.f8, -1 end
        end
        if n == 4 or n == 3 then n = 4 elseif n == 2 or n == 1 then n = 2 elseif n == 0 then n = 1 end
        if p.timer < n * 8 then
            local vz, av = 20 // n, 1024 // n
            if p.f8 ~= 0 then vz, av = -vz, -av end
            p.z = p.z + vz
            p.pitch = p.pitch + av
            if abs(p.pitch & 0x1FFF) < 800 then p.shot = "spindel_roll" end
            p.y = p.hy + abs(sins(p.pitch * 4) * 23.0)
        end
    end
end

-- bhvSpindel (spindel.inc.c): the pyramid's rolling spiked log. It rolls a step along, faster in the middle of
-- its run, twenty steps, rests a second, and rolls back.
B.spindel = {
    init = function(p) p.f4, p.f8 = 0, 0 end,
    step = function(p, m)
        spindel_roll(p)
        if m then spin_crush(p, m) end
    end,
}

-- Posts knocked out, not driven in ("earlier I said I want to drop kick them to make them go in but. lets make them
-- come out instead make the log lean to the direction it was kicked in", 2026-10-16). A drop kick into one leans it
-- away from him; the third knocks it out: it goes over, faster and faster, and lies flat that way with a thump. Going
-- over it is lifted out of its hole by its own thickness, so it comes to lie on the ground, not in it. (Mario 64 drives
-- them in with a ground pound, 65 a pound.)
local POST_LEANS = { 0x0E00, 0x1E00 }  -- (about 20 and 42 degrees after the first and second kick)
-- Its foot, never seen in Mario 64 (it stands in the ground): knocked out it was open, "the bottom of the post has no
-- texture". A cap there - its top's ringed end, turned to face down at the foot of its side.
local function post_cap(p)
    local tpl = p.tpl
    if tpl.post_cap == nil then
        tpl.post_cap = false
        local top, side = nil, nil
        for _, sec in ipairs(tpl.sections or {}) do
            local zmin, zmax = math.huge, -math.huge
            for i = 3, #sec.pos, 3 do zmin, zmax = math.min(zmin, sec.pos[i]), math.max(zmax, sec.pos[i]) end
            if zmax - zmin < 1.0 then top = sec else side = side or { zmin = zmin } end
            if side and zmin < side.zmin then side.zmin = zmin end
        end
        if top and side then
            local cap = {}
            for k, v in pairs(top) do cap[k] = v end
            local maxid = 0
            for _, sec in ipairs(tpl.sections) do maxid = math.max(maxid, sec.id or 0) end
            cap.id = maxid + 1
            cap.pos, cap.idx, cap.nrm = {}, {}, {}
            for i = 1, #top.pos, 3 do
                cap.pos[i], cap.pos[i + 1], cap.pos[i + 2] = top.pos[i], top.pos[i + 1], side.zmin
                cap.nrm[i], cap.nrm[i + 1], cap.nrm[i + 2] = 0.0, 0.0, -1.0
            end
            for i = 1, #top.idx, 3 do cap.idx[i], cap.idx[i + 1], cap.idx[i + 2] = top.idx[i], top.idx[i + 2], top.idx[i + 1] end
            tpl.post_cap = cap
        end
    end
    if tpl.post_cap and p.pmc and not p.capped then
        p.capped = true
        local w = lib.world()
        if w then pcall(lib.add_sections, w, p.pmc, { tpl.post_cap }) end
    end
end

local function post_init(p)
    p.kicks, p.lean, p.lv = 0, 0, 0
    post_cap(p)
    local top, rad = 0.0, 0.0
    local c = p.tpl.collision
    if c and c.pos then
        for i = 1, #c.pos, 3 do
            top = math.max(top, c.pos[i + 2])
            rad = math.max(rad, sqrt(c.pos[i] * c.pos[i] + c.pos[i + 1] * c.pos[i + 1]))
        end
    end
    p.top = top / S * p.uscale[3]
    p.rad = (rad > 0.0) and rad / S * p.uscale[1] or 30.0
end
-- kicked from (kx, kz): leaned away from there (false once it is out)
local function post_kicked(p, kx, kz)
    if p.kicks >= 3 then return false end
    p.kicks = p.kicks + 1
    local dx, dz = p.x - kx, p.z - kz
    if dx * dx + dz * dz < 1.0 then dx, dz = 0.0, 1.0 end
    p.yaw = s16(atan(dx, dz) * 32768.0 / pi)            -- (the way it leans: a positive pitch tips its top that way)
    p.shot = "post_pound"
    -- (the third: it jumps up out of its hole as it goes over, flies on the way it was kicked, and lies down clear of
    -- the hole, sliding a little - it went over round its foot and looked still lodged in the hole)
    -- (its lean to keep from then on: flat - the second kick's lean, left as the one to keep, stood it back up to 42 degrees
    -- once it had landed and stopped sliding, floating: "still doing it")
    if p.kicks >= 3 then p.falling, p.lv, p.vy, p.hv, p.ly, p.lean_to = true, 0x180, 22.0, 9.0, 0.0, 0x4000
    else p.lean_to = POST_LEANS[p.kicks] end
    return true
end
-- Kicked? Any attack of his (drop kick, kick, punch), once each, at any time while it plays: him within its round and
-- a leg of it (about 2.2 m from its middle), level with it. ("the log still doesnt dislodge": kicks counted only in the
-- first 0.6 s of an attack begun in the air, from 1.9 m - none reached it; the chomp's post wanted 1.65 m.) A kick that
-- comes close and does not count is logged, with why.
local function post_kick_check(p, m)
    if not (P.attack_at and P.attack_at ~= p.kick_seen) then return end
    if not P.attacking and os.clock() - P.attack_at > 0.3 then return end
    -- (a drop kick only - Mario 64's ground pound: an attack begun in the air, or that took him into it. A push on the
    -- ground counted too: "you dont have to drop kick it out, you can just push it", 2026-10-17)
    if not (P.attack_air or (P.kick_at and P.kick_at >= P.attack_at)) then
        if p.push_note ~= P.attack_at then
            local dx, dz = m.x - p.x, m.z - p.z
            if dx * dx + dz * dz < (p.rad + 300.0) ^ 2 then log("a push on a post: not counted (drop kick it)") end
            p.push_note = P.attack_at
        end
        return
    end
    local dx, dz = m.x - p.x, m.z - p.z
    local d = sqrt(dx * dx + dz * dz)
    local reach = p.rad + 200.0
    local level = m.y < p.y + p.top + 80.0 and m.y + 200.0 > p.y
    if d < reach and level then
        p.kick_seen = P.attack_at
        if post_kicked(p, m.x, m.z) then log("a post kicked (%d), %.0f from it", p.kicks, d) end
    elseif d < reach + 500.0 and p.miss_seen ~= P.attack_at then
        p.miss_seen = P.attack_at
        log("a kick by a post did not count: %.0f from it (reach %.0f), feet %.0f over its foot (top %.0f)", d, reach, m.y - p.y, p.top)
    end
end

local function post_step(p)
    if p.falling or (p.hv or 0.0) > 0.0 then
        if p.falling then
            p.lv = p.lv + 0x50
            p.lean = math.min(0x4000, p.lean + p.lv)
        end
        p.vy = p.vy - 3.5
        p.ly = p.ly + p.vy
        if p.ly <= 0.0 then
            p.ly, p.vy = 0.0, 0.0
            if p.falling and p.lean >= 0x4000 then p.falling, p.out, p.shot = nil, true, "board_thump" end
        end
        if p.hv > 0.0 then
            p.x, p.z = p.x + p.hv * sins(p.yaw), p.z + p.hv * coss(p.yaw)
            p.hv = math.max(0.0, p.hv - (p.falling and 0.2 or 1.0))     -- (slowing in the air, sliding to a stop down)
            p.gy = ground_under(p.x, p.hy + 200.0, p.z) or p.gy
        end
    elseif p.lean_to and p.lean ~= p.lean_to then
        p.lean = approach(p.lean, p.lean_to, 0x280)
    end
    p.pitch = p.lean
    -- (still lodged, leaning, its foot stays in the ground; lifted by its thickness only once knocked out and going
    -- over, so it lies on the ground - lifted while leaning it floated: "this is the post after the third kick")
    local lift = (p.falling or p.out or (p.hv or 0.0) > 0.0) and p.rad * sins(p.lean) or 0.0
    p.y = (p.gy or p.hy) + lift + (p.ly or 0.0)
end

-- bhvWoodenPost on its own: drop-kicked, it leans and goes over (above); untouched, round it three times within 200
-- frames, close, and it throws out five coins (once)
B.wpost = {
    init = function(p)
        P.want_kick = true
        p.total, p.prev = 0, nil
        post_init(p)
    end,
    step = function(p, m)
        post_kick_check(p, m)
        post_step(p)
        if p.kicks == 0 and (p.bp & 0xFF00) == 0 and not p.paid then
            local dx, dz = m.x - p.x, m.z - p.z
            local ang = s16(atan(dx, dz) * 32768.0 / pi)
            if dx * dx + dz * dz > 400.0 * 400.0 then
                p.timer, p.total = 0, 0
            elseif p.prev then
                p.total = p.total + s16(ang - p.prev)
                if abs(p.total) > 0x30000 and p.timer < 200 then
                    p.paid = true
                    local G = package.loaded["game"]
                    if G and G.spawn_coin then
                        for _ = 1, 5 do pcall(G.spawn_coin, -p.z * S, p.x * S, (p.y + 150.0) * S) end
                    end
                end
            end
            p.prev = ang
        end
    end,
}

-- bhvFloorSwitchHiddenObjects (purple_switch.inc.c): stepped on, it squashes flat (its height 1.5 -> 0.2 over 3
-- frames) with a click, ticks for 400 frames, then waits for the athlete to step off and pops back up. The one that
-- brings stairs out (bhvFloorSwitchAnimatesObject, `stays`) is down while he stands on it and pops up as he steps off;
-- its stairs keep their own time (B.switch_stairs).
local function switch_height(p, h)
    p.uscale[3] = h
    if p.actor then pcall(function() p.actor:SetActorScale3D({ X = p.uscale[1], Y = p.uscale[2], Z = h }) end) end
end
-- (on it: stood on it, or his feet over its top - at full height he can perch on it without the game counting him as
-- standing, and Rainbow Ride's never pressed, 2026-10-15)
local function on_switch(p, m)
    if m.plat == p then return true end
    local dx, dz = m.x - p.x, m.z - p.z
    local r = 70.0 * (p.uscale and p.uscale[1] or 1.0)
    return dx * dx + dz * dz < r * r and m.y > p.y + 5.0 and m.y < p.y + 80.0
end
-- (under the water - swimming, or the water's top over his chest - only the metal cap presses one: HMC's at the bottom of
-- Dorrie's lake is the metal cap's - "and guess WHAT im still able to hit the ! switch underwater", 2026-10-31)
local function under_water_unmetal(m)
    local CP = package.loaded["caps"]
    if CP and CP.on and CP.on("metal") then return false end
    local G = package.loaded["game"]
    if G and G.swim then return true end
    if G and G.water_at then
        local top = G.water_at(-m.z * S, m.x * S)
        if top and top > m.y * S + 120.0 then return true end
    end
    return false
end
P.under_water_unmetal = under_water_unmetal
B.purple_switch = {
    step = function(p, m)
        local a = p.action
        if a == 0 then
            if on_switch(p, m) and not under_water_unmetal(m) then p.action = 1 end
        elseif a == 1 then
            switch_height(p, 1.5 + (0.2 - 1.5) * math.min(1.0, (p.timer + 1) / 3.0))
            if p.timer == 3 then
                p.action, p.shot = 2, "purple_switch"
                local SFX = package.loaded["sfx"]
                if SFX and not p.o.stays then pcall(SFX.play, "purple_ticks", 1.0) end
                local G = package.loaded["game"]
                if G and G.shake_stage then pcall(G.shake_stage, 0.2) end       -- (cur_obj_shake_screen SHAKE_POS_SMALL)
            end
        elseif a == 2 then
            if p.o.stays then
                if not on_switch(p, m) then p.action = 3 end
            elseif p.timer > 400 then p.action = 4 end
        elseif a == 4 then
            if not on_switch(p, m) then p.action = 3 end
        else
            switch_height(p, 0.2 + (1.5 - 0.2) * math.min(1.0, (p.timer + 1) / 3.0))
            if p.timer == 3 then p.action = 0 end
        end
    end,
}

-- bhvCapSwitch (capswitch.inc.c): the switch at the end of each cap's secret course. Stood on, it is pressed for
-- good: flattened from half height to a tenth over frames 2 to 4 with its sound and a shake, then its message
-- (DIALOG_010/011/012), and the file keeps it (menu.lua flag cap_wing/metal/vanish), which makes that colour's !
-- boxes solid everywhere (boxes.lua). Already pressed in this file: it stands flat. (It was baked into its level,
-- 2026-10-15.)
local CAP_FLAG = { [0] = "cap_wing", [1] = "cap_metal", [2] = "cap_vanish" }
B.cap_switch = {
    init = function(p)
        local MN = _G.MENU
        local flag = CAP_FLAG[p.o.colour or 0]
        if flag and MN and MN.has_flag and MN.has_flag(flag) then
            p.action = 3
            switch_height(p, 0.1)
        end
    end,
    step = function(p, m)
        if p.action == 0 then
            if m.plat == p then
                p.action, p.timer = 1, 0
                local MN = _G.MENU
                local flag = CAP_FLAG[p.o.colour or 0]
                if flag and MN and MN.add_flag then pcall(MN.add_flag, flag) end
                local SFX = package.loaded["sfx"]
                if SFX then pcall(SFX.play, "cap_switch", 1.0) end
            end
        elseif p.action == 1 then
            if p.timer >= 2 and p.timer <= 4 then switch_height(p, 0.5 + (0.1 - 0.5) * (p.timer - 1) / 3.0) end
            if p.timer == 4 then
                local G = package.loaded["game"]
                if G and G.shake_stage then pcall(G.shake_stage, 0.3) end
            end
            if p.timer >= 8 then
                p.action = 3
                local G = package.loaded["game"]
                if G and G.say then pcall(G.say, 10 + (p.o.colour or 0)) end
            end
        end
    end,
}

-- bhvHiddenObject (switch_hidden_objects.inc.c): a cork box (or WDW's platform) that is there only while the
-- nearest purple switch ticks: 360 frames, 20 more blinking. A box broken (push or drop kick) stays gone until the
-- switch is up again.
local function shown(p, on)
    p.gone = not on
    if not p.actor then return end
    pcall(function() p.actor:SetActorHiddenInGame(not on) end)
    pcall(function() p.actor:SetActorEnableCollision(on) end)
end
-- bhvAnimatesOnFloorSwitchPress (animated_floor_switch.inc.c): the Dark World's and the Sky's staircases and Rainbow
-- Ride's tricky triangles, folded away until the nearest purple switch is pressed (Mario 64 runs them out over 9
-- frames, through its five models; here the two ends: `out` the one shown once pressed). They were always out, and the
-- switch was missing, 2026-10-15. Out for a time, ticking: 250 frames in the Dark World, 200 in the others, counted
-- from his stepping off the switch, then folded away again ("this ! switch has no timer", 2026-10-18; they had stayed
-- out for good). Pressed again while out, the time starts over.
-- A platform's slopes made a slide of their own: out of its collision into a piece on the same actor that is
-- unwalkable to the engine and blocks STORROR's slide channel (18), as G.add_slides makes the scenes' slides; P.slide_under
-- tells G.slide_walk he is over one, for STORROR's walkable angle of the slides.
local function slide_split(p)
    local c = p.tpl.collision
    if not (c and p.actor) then return end
    local flat = { source = c.source, pos = c.pos, idx = {} }
    local steep = { source = "slide", pos = c.pos, idx = {} }
    local P_, ix = c.pos, c.idx
    for t = 0, #ix // 3 - 1 do
        local a, b, d = ix[t * 3 + 1], ix[t * 3 + 2], ix[t * 3 + 3]
        local ux, uy, uz = P_[b * 3 + 1] - P_[a * 3 + 1], P_[b * 3 + 2] - P_[a * 3 + 2], P_[b * 3 + 3] - P_[a * 3 + 3]
        local vx, vy, vz = P_[d * 3 + 1] - P_[a * 3 + 1], P_[d * 3 + 2] - P_[a * 3 + 2], P_[d * 3 + 3] - P_[a * 3 + 3]
        local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        local k = abs(nz) / math.max(1e-9, sqrt(nx * nx + ny * ny + nz * nz))
        local into = (k > 0.45 and k < 0.985) and steep or flat
        into.idx[#into.idx + 1], into.idx[#into.idx + 2], into.idx[#into.idx + 3] = a, b, d
    end
    if #steep.idx == 0 then return end
    steep.ntris = #steep.idx // 3
    if #flat.idx > 0 then lib.add_collision(p.pmc, { flat }) else pcall(function() p.pmc:ClearMeshSection(1000) end) end
    local sp = lib.add_pmc(p.actor)
    if not sp then return end
    lib.add_collision(sp, { steep })
    pcall(function() sp:SetWalkableSlopeOverride({ WalkableSlopeBehavior = 3, WalkableSlopeAngle = 0.0 }) end)
    pcall(function() sp:SetCollisionResponseToChannel(18, 2) end)
    p.slide_pmc = sp
    p.slide_F = H.build_floor and H.build_floor({ steep }) or nil
end
function P.slide_under(x, y, feet)
    -- (the Fire Sea's arena, tipped, with him on it: his own walkable angle down too, so STORROR's slide takes him -
    -- its surface's override alone left him standing: "not sliding", 2026-10-25)
    -- (over it, not only stood on it: STORROR's slope slide is its falling mode, and counted only while he stood, the
    -- slide stopped as it began, his walkable angle back up each other frame - he hung in its pose unmoving)
    local ar = P.bowser_arena
    if ar and ar.slide_on and (P.on == ar or P.over(x, y, feet) == ar) then return true end
    for _, p in ipairs(P.list) do
        local F = not p.gone and p.slide_F
        if F then
            local a = p.ax or { axes(p.pitch, p.yaw, p.roll) }
            local wx, wy, wz = p.wx or (-p.z * S), p.wy or (p.x * S), p.wz or (p.y * S)
            local dx, dy, dz = x - wx, y - wy, feet + 60.0 - wz
            if dx * dx + dy * dy < (p.reach2 or 0.0) then
                local us = p.uscale
                local lx = (dx * a[1] + dy * a[2] + dz * a[3]) / us[1]
                local ly = (dx * a[4] + dy * a[5] + dz * a[6]) / us[2]
                local lz = (dx * a[7] + dy * a[8] + dz * a[9]) / us[3]
                local fz = H.floor_hit(F, lx, ly, lz)
                if fz and wz + lx * us[1] * a[3] + ly * us[2] * a[6] + fz * us[3] * a[9] > feet - 80.0 then return true end
            end
        end
    end
    return false
end

B.switch_stairs = {
    init = function(p) p.up = false end,
    -- (the ticking, heard all over: slow, a tick-tock each half second, and fast, each quarter, for the last 50 frames -
    -- by the time left, so as long as they stay out: one 8.5 s recording, made for the Dark World's 250 frames, ran out
    -- before Rainbow Ride's longer ones - "you have to match the audio to how long it lasts", 2026-11-02)
    hum = function(p)
        if p.up then return ((p.left or 0) <= 50) and "switch_ticks_fast" or "switch_ticks_slow", 1.0e6 end
    end,
    step = function(p, m)
        -- (folded, the stairs are a slope that Mario 64 makes very slippery - collapsing_stairs_5's top is
        -- SURFACE_VERY_SLIPPERY: he slides down it as on the scenes' own slides - "this doesnt make the player slide",
        -- 2026-10-18. Its slope only: the flat floor at its foot, under the switch, stays a floor - the whole of it
        -- made slippery left him stuck at the bottom.)
        if not p.o.out and not p.slid and p.pmc then
            p.slid = true
            local ok, err = pcall(slide_split, p)
            if not ok then log("switch stairs: slide %s", tostring(err)) end
        end
        if p.switch == nil then
            local best, bd = false, nil
            for _, q in ipairs(P.list) do
                if q.def == B.purple_switch and q.o.stays then
                    local d = (q.x - p.x) ^ 2 + (q.y - p.y) ^ 2 + (q.z - p.z) ^ 2
                    if not bd or d < bd then best, bd = q, d end
                end
            end
            p.switch = best
            shown(p, not p.o.out)
        end
        local sw = p.switch
        if sw and sw.action == 2 then
            if not p.up then
                p.up = true
                shown(p, p.o.out and true or false)
                if p.o.out then p.shot = "platform_switch" end
            end
            -- (how long they stay out once he is off the switch, frames: Rainbow Ride's tricky triangles 10 s longer
            -- than Mario 64's 6.7 - "this ! switch needs to last way longer", "actually like 10 seconds longer", 2026-11-02)
            local G = package.loaded["game"]
            local nm = G and G.name
            -- (Bowser in the Sky's 4 s longer: "switch doesnt last long enough add 4 seconds", 2026-11-02)
            p.left = (nm == "bitdw") and 250 or (nm == "rr") and 500 or (nm == "bits") and 320 or 200
        end
        if p.up then
            p.left = (p.left or 0) - 1
            if p.left <= 0 then
                p.up = false
                shown(p, not p.o.out)
            end
        end
    end,
}

-- bhvOpenableGrill (grill_door.inc.c): Bob-omb Battlefield's bars and Hazy Maze Cave's red grills, two doors that the
-- purple switch beside them swings open for good (0x100 a frame for 64 frames, the two opposite ways), with the cage's
-- sound, and in the cave the puzzle jingle. (Mario 64 spawns them at the start: they were missing, the way open and no
-- switch, 2026-10-15.)
B.grill_door = {
    step = function(p, m)
        if p.switch == nil then
            local best, bd = false, nil
            for _, q in ipairs(P.list) do
                if q.def == B.purple_switch and q.o.stays then
                    local d = (q.x - p.x) ^ 2 + (q.y - p.y) ^ 2 + (q.z - p.z) ^ 2
                    if not bd or d < bd then best, bd = q, d end
                end
            end
            p.switch = best
        end
        if p.action == 0 then
            if p.switch and p.switch.action == 2 then
                p.action = 1
                if (p.o.turn or 1) > 0 then
                    p.shot = "cage_open"
                    local SFX = package.loaded["sfx"]
                    if p.o.jingle and SFX then pcall(SFX.play, "puzzle_jingle", 1.0) end
                end
            end
        elseif p.action == 1 then
            if p.timer < 64 then p.yaw = s16(p.yaw + (p.o.turn or 1) * 0x100) else p.action = 2 end
        end
    end,
}

B.hidden = {
    init = function(p) P.want_kick = true; p.state, p.t = 0, 0; shown(p, false) end,
    step = function(p, m)
        if p.switch == nil then
            local best, bd = false, nil
            for _, q in ipairs(P.list) do
                if q.def == B.purple_switch then
                    local d = (q.x - p.x) ^ 2 + (q.y - p.y) ^ 2 + (q.z - p.z) ^ 2
                    if not bd or d < bd then best, bd = q, d end
                end
            end
            p.switch = best
        end
        local sw = p.switch
        -- (Mario 64's timing: out the frame the switch ticks, 360 frames, then blinking - hidden every other frame -
        -- till 403, cur_obj_wait_then_blink(360, 20): after the switch's 400 are up. Gone at 380 while it still ticked,
        -- the boxes came straight back for a second round: "blocks are still visable after purple ! timer ends",
        -- 2026-10-17. And once gone, not again for the same press.)
        if p.state == 0 then
            if sw and sw.action ~= 2 then p.spent = nil end
            if sw and sw.action == 2 and not p.spent then p.state, p.t = 1, 0; shown(p, true) end
        elseif p.state == 1 then
            p.t = p.t + 1
            if p.t >= 360 then
                local blink = p.t - 360
                if blink % 2 ~= 0 and blink // 2 > 20 then
                    p.state, p.spent = 0, true
                    shown(p, false)
                elseif p.actor then
                    pcall(function() p.actor:SetActorHiddenInGame(blink % 2 ~= 0) end)
                end
            end
            if p.o.box and P.attack_at and P.attack_at ~= p.hit_seen and os.clock() - P.attack_at < 0.4 then
                p.hit_seen = P.attack_at
                local dx, dy, dz = m.x - p.x, m.y - p.y, m.z - p.z
                if dx * dx + dz * dz < 220.0 * 220.0 and dy > -150.0 and dy < 400.0 then
                    p.state, p.shot = 2, "box_break"
                    shown(p, false)
                end
            end
        elseif sw and sw.action == 0 then
            p.state = 0
        end
    end,
}

-- bhvPushableMetalBox (metal_box.inc.c): Mario leans on it and it slides 4 a frame, square to the way he faces, while
-- there is floor 150 ahead. Here STORROR's push shoves it: 18 frames at 8 (144 units), the same squaring and floor
-- check, with its scrape.
B.metal_box = {
    init = function(p) P.want_kick = true; p.slide = 0 end,
    step = function(p, m)
        if P.attack_at and P.attack_at ~= p.push_seen and not P.attack_air and os.clock() - P.attack_at < 0.4 then
            p.push_seen = P.attack_at
            local dx, dz = p.x - m.x, p.z - m.z
            if dx * dx + dz * dz < 300.0 * 300.0 and abs(m.y - p.y) < 250.0 then
                local fyaw = nil
                pcall(function() fyaw = lib.pawn():K2_GetActorRotation().Yaw end)
                if fyaw then
                    local my = s16(floor((180.0 - fyaw) * 65536.0 / 360.0))      -- (the athlete faces +X: Mario 64's yaw is 180 - his)
                    local to_box = s16(floor(atan(dx, dz) * 32768.0 / pi))
                    if abs(s16(to_box - my)) < 0x3000 then
                        p.myaw = s16((my + 0x2000) & 0xC000)
                        p.slide, p.shot = 18, "metal_box_push"
                        p.stop_said = nil
                        log("metal box at %.0f %.0f pushed (its scrape)", -p.z * S, p.x * S)
                    end
                end
            end
        end
        if p.slide > 0 then
            p.slide = p.slide - 1
            local fx, fz = sins(p.myaw), coss(p.myaw)
            local fy = ground_under(p.x + fx * 158.0, p.y + 50.0, p.z + fz * 158.0)
            local walled = fy and abs(fy - p.y) < 40.0 and B.metal_box.walled(p, fx, fz)
            if fy and abs(fy - p.y) < 40.0 and not walled then
                p.x, p.z = p.x + fx * 8.0, p.z + fz * 8.0
            else
                p.slide = 0
                if not p.stop_said then
                    p.stop_said = true
                    log("metal box stops: %s", walled and "a wall" or "no level floor ahead")
                end
            end
        end
    end,
}
-- (a wall where it is going: stopped against it. Its floor check alone let it on into walls the floor runs on under -
-- WDW's by the far corner went 2 m into one: "cant push boxes into wall", 2026-10-28. Lines out from inside it, its
-- middle and either side, low and high, to 8 past its face: anything solid but him and itself.)
function B.metal_box.walled(p, fx, fz)
    local pawn, world = lib.pawn(), lib.world()
    B.metal_box.ksl = B.metal_box.ksl or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local K = B.metal_box.ksl
    if not (K and world) then return false end
    local ignore = { pawn, p.actor }
    local none = { R = 0, G = 0, B = 0, A = 0 }
    local sx, sz = fz, -fx                              -- (across its way)
    for _, side in ipairs({ -110.0, 0.0, 110.0 }) do
        for _, up in ipairs({ 30.0, 200.0 }) do
            local ax, ay, az = p.x + sx * side, p.y + up, p.z + sz * side
            local bx, bz = ax + fx * 170.0, az + fz * 170.0
            local hit = false
            pcall(function()
                local out = {}
                hit = K:LineTraceSingle(world, { X = -az * S + OFFSET.X, Y = ax * S + OFFSET.Y, Z = ay * S + OFFSET.Z },
                    { X = -bz * S + OFFSET.X, Y = bx * S + OFFSET.Y, Z = ay * S + OFFSET.Z }, 0, true, ignore, 0, out, true,
                    none, none, 0.0)
            end)
            if hit then return true end
        end
    end
    return false
end

-- ------------------------------------------------------------ more platforms
local function approach_inc(goal, src, inc)
    if src <= goal then
        if goal - src < inc then return goal end
        return src + inc
    end
    if goal - src > -inc then return goal end
    return src - inc
end

-- the water's surface over (x, z), Mario 64 units, or nil
local function water_level(x, z)
    local G = package.loaded["game"]
    local w = G and G.water_at and G.water_at(-z * S, x * S)
    return w and w / S
end

-- bhvLLLTiltingInvertedPyramid, bhvBitFSTiltingInvertedPyramid (tilting_inverted_pyramid.inc.c): its top leans toward
-- where the athlete stands on it (its up turns toward him, at 0.01 a frame), and back level when he is off
B.tilt_pyramid = {
    init = function(p) p.nx, p.ny, p.nz, p.yaw = 0.0, 1.0, 0.0, 0 end,      -- (Mario 64 draws it unturned)
    step = function(p, m)
        local dx, dy, dz = 0.0, 1.0, 0.0
        if m.plat == p then
            dx, dy, dz = m.x - p.x, 500.0, m.z - p.z
            local d = sqrt(dx * dx + dy * dy + dz * dz)
            dx, dy, dz = dx / d, dy / d, dz / d
        end
        p.nx, p.ny, p.nz = approach_inc(dx, p.nx, 0.01), approach_inc(dy, p.ny, 0.01), approach_inc(dz, p.nz, 0.01)
        local l = sqrt(p.nx * p.nx + p.ny * p.ny + p.nz * p.nz)
        local nx, ny, nz = p.nx / l, p.ny / l, p.nz / l
        -- (the turn that takes its up to the normal: roll about z, then pitch about x)
        p.roll = s16(floor(asin(math.max(-1.0, math.min(1.0, -nx))) * 32768.0 / pi))
        p.pitch = s16(floor(atan(nz, ny) * 32768.0 / pi))
    end,
}

-- bhvLLLSinkingRectangularPlatform (lll_sinking_rectangle.inc.c): turned ones bob up and down; the others rock
B.lll_rect = {
    init = function(p) p.osc = 0 end,
    step = function(p)
        if p.yaw ~= 0 then
            if p.action == 0 then p.action = 1
            else p.y = p.y - sins(p.osc) * 0.4; p.osc = p.osc + 0x100 end
        else
            p.pitch = s16(trunc(sins(p.osc) * 0x200))
            p.osc = p.osc + 0x100
        end
    end,
}
-- bhvLLLSinkingSquarePlatforms: bob up and down
B.lll_square = {
    init = function(p) p.osc, p.y = 0, p.y + 5.0; p.hy = p.y end,
    step = function(p)
        if p.action == 0 then p.action = 1
        else p.y = p.y - sins(p.osc) * 0.5; p.osc = p.osc + 0x100 end
    end,
}
-- bhvLLLSinkingRockBlock (lll_sinking_rock_block.inc.c): sinks 110 under the athlete, rises again when he is off
B.sink_block = {
    init = function(p) p.y = p.y - 50.0; p.hy, p.st = p.y, 0 end,
    step = function(p, m)
        if m.plat == p then
            if p.st < 0x4000 then p.st = p.st + 124 else p.st = 0x4000 end
        elseif p.st > 0 then p.st = p.st - 124 else p.st = 0 end
        p.y = p.hy + sins(p.st) * -110.0
    end,
}
-- bhvBitFSSinkingPlatforms, bhvBitFSSinkingCagePlatform (falling_rising_platform.inc.c): bob up and down
-- (how far the Fire Sea's sink, Mario 64 units: 0.58 a frame took them 47 down, their tops 6 cm over the lava at the
-- bottom - "raising and lowering platform goes too far down", 2026-11-07; then 20 at most, and "now its too high".
-- Now from `SINK_TOP` down to SINK_TOP + SINK_DEPTH under its home - tops 33 cm over the lava to 15 - worked out from
-- where it is in its swing, so it never creeps)
P.SINK_TOP, P.SINK_DEPTH = 12.0, 24.0
B.bitfs_sink = {
    init = function(p) p.osc = 0 end,
    step = function(p)
        p.y = p.hy - (P.SINK_TOP or 0.0) - (P.SINK_DEPTH or 47.3) * (1.0 - coss(p.osc)) * 0.5
        p.osc = p.osc + 0x100
    end,
}
B.bitfs_cage = {
    init = function(p)
        p.osc = 0
        if p.b2 ~= 0 then p.y = p.y - 300.0 end
    end,
    step = function(p)
        if p.b2 ~= 0 then p.y = p.y + sins(p.osc) * 7.0 else p.y = p.y - sins(p.osc) * 3.0 end
        p.osc = p.osc + 0x100
    end,
}
-- bhvSquishablePlatform: grows and shrinks in height
B.squish = {
    init = function(p) p.osc = 0 end,
    step = function(p)
        local h = (sins(p.osc) + 1.0) * 0.3 + 0.4
        p.osc = p.osc + 0x80
        p.uscale[3] = h
        if p.actor then pcall(function() p.actor:SetActorScale3D({ X = p.uscale[1], Y = p.uscale[2], Z = h }) end) end
    end,
}
-- bhvWDWSquareFloatingPlatform, bhvWDWRectangularFloatingPlatform (floating_platform.inc.c): float 64 above the water
-- (or sit 64 above the floor when the water is low), bob, and dip and tilt under the athlete
B.float_plat = {
    init = function(p) p.f8, p.vy, p.k, p.yaw0 = 0.0, 0.0, 0, p.yaw end,
    step = function(p, m)
        local wl = water_level(p.x, p.z)
        local fl = ground_under(p.x, p.y, p.z)
        local home, afloat
        if wl and (not fl or wl > fl + 64.0) then home, afloat = wl + 64.0, true
        else home = (fl or p.y - 64.0) + 64.0 end
        if afloat then
            local dx, dz = m.x - p.x, m.z - p.z
            local sp6 = s16(trunc(dx * coss(-p.yaw0) + dz * sins(-p.yaw0)))
            local sp4 = s16(trunc(dz * coss(-p.yaw0) - dx * sins(-p.yaw0)))
            if m.plat == p then
                p.pitch, p.roll = s16(sp4 * 2), s16(-sp6 * 2)
                p.vy = math.max(0.0, p.vy - 1.0)
                p.f8 = math.min(90.0, p.f8 + p.vy)
            else
                p.pitch, p.roll = trunc(p.pitch / 2), trunc(p.roll / 2)
                p.f8 = math.max(0.0, p.f8 - 5.0)
                p.vy = 10.0
            end
            p.y = home - 64.0 - p.f8 + sins(p.k * 0x800) * 10.0
            p.k = (p.k + 1) % 32
        else
            p.y = home
        end
    end,
}
-- bhvArrowLift (arrow_lift.inc.c): stood on (after a second at rest) it slides 384 the way its arrow points, waits
-- two seconds and slides back
B.arrow_lift = {
    init = function(p) p.disp, p.fyaw = 0.0, p.yaw end,
    step = function(p, m)
        local a = p.action
        if a == 0 then
            if p.timer > 60 and m.plat == p then p.action = 1 end
        elseif a == 1 then
            p.disp = p.disp + 12.0
            if p.disp > 384.0 then
                p.disp, p.action = 384.0, 2
            else
                local my = p.fyaw - 0x4000
                p.x, p.z = p.x + 12.0 * sins(my), p.z + 12.0 * coss(my)
            end
        elseif p.timer > 60 then
            p.disp = p.disp - 12.0
            if p.disp < 0.0 then
                p.disp, p.action = 0.0, 0
            else
                local my = p.fyaw + 0x4000
                p.x, p.z = p.x + 12.0 * sins(my), p.z + 12.0 * coss(my)
            end
        end
    end,
}
-- bhvWFSlidingPlatform (sliding_platform.inc.c): slides 510 out of the wall, waits, slides back in
B.wf_slide = {
    init = function(p)
        p.myaw = p.yaw
        p.yaw = s16(p.yaw - 0x4000)
        p.x = p.x + 2.0
        p.hx = p.x
        p.vel = ({ 10.0, 15.0, 20.0 })[p.b2] or 10.0
        p.fv = 0.0
        p.timer = math.random(0, 99)
        p.out_yaw, p.hz = p.myaw, p.z
    end,
    step = function(p, m)
        local a = p.action
        if a == 0 then
            if p.timer > 100 then p.action, p.fv = 1, p.vel end
        elseif a == 1 then
            if p.timer >= 500.0 / p.vel then p.fv, p.x = 0.0, p.hx + 510.0 end
            if p.timer == 60 then p.action, p.fv, p.myaw = 2, p.vel, s16(p.myaw - 0x8000) end
        else
            if p.timer >= 500.0 / p.vel then p.fv, p.x = 0.0, p.hx end
            if p.timer == 90 then p.action, p.fv, p.myaw = 1, p.vel, s16(p.myaw - 0x8000) end
        end
        p.x, p.z = p.x + p.fv * sins(p.myaw), p.z + p.fv * coss(p.myaw)
    end,
}
-- A Bomp's shove (Mario 64: its wall moves into Mario and his wall collision puts him out of it, off the ledge - here the
-- engine slid it through him: "add collisions to the wall things", 2026-10-17): him inside its box, his capsule round,
-- he is put out of its front - the way it pokes out - wherever he is in it.
local BOMP_R = 36.0                     -- (his capsule, cm)
local BOMP_BUMP, BOMP_UP = 700.0, 340.0    -- (cm/s a thumping Bomp throws him at: away from it, and up - 1100/450 "flings the player too much", 480/260 "too weak now")
local function bomp_box(tpl)
    if tpl.bomp_box then return tpl.bomp_box end
    local c = tpl.collision
    local mn, mx = { 1e9, 1e9, 1e9 }, { -1e9, -1e9, -1e9 }
    for i = 1, #c.pos, 3 do
        for k = 0, 2 do
            local v = c.pos[i + k]
            if v < mn[k + 1] then mn[k + 1] = v end
            if v > mx[k + 1] then mx[k + 1] = v end
        end
    end
    tpl.bomp_box = { mn = mn, mx = mx }
    return tpl.bomp_box
end
local function bomp_push(p)
    if not (p.tpl and p.tpl.collision) then return end
    if p.out_yaw == nil then p.out_yaw = (p.action == 3) and s16(p.myaw + 0x8000) or p.myaw end
    if p.cloth_at and os.clock() > p.cloth_at then
        p.cloth_at = nil
        local G0 = package.loaded["game"]
        if G0 and G0.reset_cloth then pcall(G0.reset_cloth) end
    end
    if p.fv <= 0.0 then p.bumped = nil end
    -- (only while it thumps out: standing still or going back in, its own collision is enough - pushed then, he was
    -- shoved off it while climbing it: "its very glitchy climbing them", 2026-10-17)
    if not (p.fv > 0.0 and p.myaw == p.out_yaw) then return end
    local pawn = lib.pawn()
    if not pawn then return end
    local G = package.loaded["game"]
    if G and (G.dying or (G.intangible and G.intangible())) then return end
    local box = bomp_box(p.tpl)
    local a = { axes(p.pitch, p.yaw, p.roll) }
    local wx, wy, wz = -p.z * S, p.x * S, p.y * S
    local l = nil
    pcall(function() l = pawn:K2_GetActorLocation() end)
    if not l then return end
    local half = (G and G.half) or 90.0
    local px, py, pz = l.X - OFFSET.X - wx, l.Y - OFFSET.Y - wy, l.Z - OFFSET.Z - wz
    local lx = px * a[1] + py * a[2] + pz * a[3]
    local ly = px * a[4] + py * a[5] + pz * a[6]
    local lz = pz                                           -- (its height: upright)
    local mn, mx = box.mn, box.mx
    if lz - half > mx[3] - 40.0 or lz + half < mn[3] then return end      -- (on top of it, or up over its top: left be)
    -- the way out: its outward travel, in its own axes; its front face along it, and how far in front of it he is
    local dx, dy = -coss(p.out_yaw), sins(p.out_yaw)        -- (Mario 64 x, z -> the scene's y, -x)
    local ox, oy = dx * a[1] + dy * a[2], dx * a[4] + dy * a[5]
    local along, across, amin, amax, cmin, cmax
    if abs(oy) >= abs(ox) then
        along, across, amin, amax, cmin, cmax = ly * ((oy > 0) and 1 or -1), lx, mn[2], mx[2], mn[1], mx[1]
        if oy < 0 then amin, amax = -mx[2], -mn[2] end
    else
        along, across, amin, amax, cmin, cmax = lx * ((ox > 0) and 1 or -1), ly, mn[1], mx[1], mn[2], mx[2]
        if ox < 0 then amin, amax = -mx[1], -mn[1] end
    end
    if across < cmin - BOMP_R or across > cmax + BOMP_R then return end
    -- (in front of its face and touching it - the engine's own collision may have put him just out of it already - or
    -- inside it: put just out, and bumped once a thump)
    if along < amin or along > amax + BOMP_R + 25.0 then return end
    local move = amax + BOMP_R - along
    if move > 0.0 then
        pcall(function()
            pawn:K2_SetActorLocation({ X = l.X + dx * move, Y = l.Y + dy * move, Z = l.Z }, false, {}, true)
        end)
        -- (his shirt not dragged after him: "its doing the shirt thing again", 2026-10-17)
        if G and G.reset_cloth then pcall(G.reset_cloth, pawn) end
    end
    -- (a bump: thrown off it, away and a little up, with a bonk - "make them bump the player", 2026-10-17)
    if p.bumped ~= p.action then
        p.bumped = p.action
        -- (STORROR's own moves cleared, falling, his speed set: a launch alone was undone by its root motion - "its still
        -- not bumping the player", 2026-10-17 - as the shell's hop off does it)
        if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
        pcall(function()
            local cm = pawn.CharacterMovement
            cm:SetMovementMode(3, 0)
            cm.Velocity = { X = dx * BOMP_BUMP, Y = dy * BOMP_BUMP, Z = BOMP_UP }
        end)
        p.cloth_at = os.clock() + 0.25          -- (and his clothes set right again once he is on his way)
        local SFX = package.loaded["sfx"]
        if SFX then pcall(SFX.play, "en_bonk", 1.0) end
        log("a Bomp bumped him")
    end
end

-- A Bomp's way back in (bhvSmallBomp / bhvLargeBomp - the faces in WF's wall): him on it as it went - hanging from its
-- edge, climbing up onto it, stood on it - was taken into the wall with it, STORROR's climb holding him to its ledge past
-- the wall's own collision: "got trapped in the wall while climbing wall movers", "the rocks with faces that push out of
-- the wall", 2026-11-04. Behind its face where it stands all the way in (p.hx), beside it or over it, he is put out in
-- front of that; and let go of it if he was climbing or hanging, falling - as Mario 64's wall pushes Mario off it.
-- (`m`: him, Mario 64's units. Only while `p.going_in`; not on WF's sliding bricks, where it shoved him walking by)
local WALL_R = 40.0                     -- (his capsule, cm, and a little)
local function wall_keep(p, m)
    if not (p.tpl and p.tpl.collision and m and p.hx) then return end
    -- (only as it goes back in, and only him climbing or hanging on it - STORROR's flying and its own modes - or stood
    -- on it: walking by a sliding brick he was put out 49 cm and knocked down, "getting ragdolled and teleported
    -- randomly", 2026-11-04)
    if not p.going_in then return end
    local pawn0 = lib.pawn()
    local mode0 = nil
    pcall(function() mode0 = pawn0.CharacterMovement.MovementMode end)
    if mode0 ~= 5 and mode0 ~= 6 and P.on ~= p then return end
    local G = package.loaded["game"]
    if G and (G.dying or (G.intangible and G.intangible())) then return end
    local dxm, dzm = m.x - p.x, m.z - p.z
    if dxm * dxm + dzm * dzm > 1400.0 * 1400.0 or abs(m.y - p.y) > 1000.0 then return end
    local oyaw = p.out_yaw
    if not oyaw then return end
    p.hz = p.hz or p.z
    local box = bomp_box(p.tpl)
    local a = { axes(p.pitch, p.yaw, p.roll) }
    local wx, wy, wz = -p.z * S, p.x * S, p.y * S
    local px, py, pz = -m.z * S - wx, m.x * S - wy, m.y * S - wz
    local lx = px * a[1] + py * a[2] + pz * a[3]
    local ly = px * a[4] + py * a[5] + pz * a[6]
    local lz = pz
    local half = (G and G.half) or 90.0
    local mn, mx = box.mn, box.mx
    if lz + half < mn[3] - 20.0 or lz - half > mx[3] + 2.0 * half then return end
    local dx, dy = -coss(oyaw), sins(oyaw)                  -- (its way out, in the scene)
    local ox, oy = dx * a[1] + dy * a[2], dx * a[4] + dy * a[5]
    local along, across, amax, cmin, cmax
    if abs(oy) >= abs(ox) then
        along, across, amax, cmin, cmax = ly * ((oy > 0) and 1 or -1), lx, mx[2], mn[1], mx[1]
        if oy < 0 then amax = -mn[2] end
    else
        along, across, amax, cmin, cmax = lx * ((ox > 0) and 1 or -1), ly, mx[1], mn[2], mx[2]
        if ox < 0 then amax = -mn[1] end
    end
    if across < cmin - WALL_R - 30.0 or across > cmax + WALL_R + 30.0 then return end
    -- (the wall's face, in its axes now: its front less how far out it is)
    local out = ((p.x - p.hx) * sins(oyaw) + (p.z - p.hz) * coss(oyaw)) * S
    local face = amax - out
    if along >= face - 2.0 or along < face - 400.0 then return end
    local pawn = lib.pawn()
    if not pawn then return end
    local move = face + WALL_R + 5.0 - along
    if move > 150.0 then return end                         -- (that far in: not off this one)
    pcall(function()
        local l = pawn:K2_GetActorLocation()
        pawn:K2_SetActorLocation({ X = l.X + dx * move, Y = l.Y + dy * move, Z = l.Z }, false, {}, true)
    end)
    if p.walled ~= p.action then
        p.walled = p.action
        local mode = nil
        pcall(function() mode = pawn.CharacterMovement.MovementMode end)
        -- (climbing or hanging - STORROR's flying and its own: let go, falling, a little off the wall)
        if mode == 5 or mode == 6 then
            if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
            pcall(function()
                local cm = pawn.CharacterMovement
                cm:SetMovementMode(3, 0)
                cm.Velocity = { X = dx * 150.0, Y = dy * 150.0, Z = 0.0 }
            end)
        end
        if G and G.reset_cloth then pcall(G.reset_cloth, pawn) end
        log("sliding wall: the athlete put out of the wall (%.0f cm, mode %s)", move, tostring(mode))
    end
end

-- bhvSmallBomp, bhvLargeBomp (bomp.inc.c): WF's pushers, poking out of the wall and thumping out to 3830
B.bomp = {
    init = function(p)
        p.hz = p.z
        if p.o.big then p.myaw = s16(p.yaw + 0x4000) else p.myaw, p.yaw = p.yaw, s16(p.yaw - 0x4000) end
        p.out_yaw = p.myaw                       -- (the way it pokes out)
        p.ext, p.fv = p.o.big and 10.0 or 40.0, 0.0
        p.timer = math.random(0, 99)
    end,
    step = function(p, m)
        local a = p.action
        if a == 0 then
            if p.timer > 100 then p.action, p.fv = 1, 30.0 end
        elseif a == 1 then
            if p.x > 3450.0 then p.x, p.fv = 3450.0, 0.0 end
            if p.timer == 15 then p.action, p.fv, p.shot = 2, p.ext, "bomp" end
        elseif a == 2 then
            if p.x > 3830.0 then p.x, p.fv = 3830.0, 0.0 end
            if p.timer == 60 then p.action, p.fv, p.shot, p.myaw = 3, 10.0, "bomp", s16(p.myaw - 0x8000) end
        else
            if p.x < 3330.0 then p.x, p.fv = 3330.0, 0.0 end
            if p.timer == 90 then p.action, p.fv, p.myaw = 1, 25.0, s16(p.myaw - 0x8000) end
        end
        p.x, p.z = p.x + p.fv * sins(p.myaw), p.z + p.fv * coss(p.myaw)
        bomp_push(p)
        p.hx, p.going_in = 3330.0, (p.action == 3 and p.fv > 0.0)
        wall_keep(p, m)
    end,
}
-- bhvSwingPlatform (swing_platform.inc.c): RR's swings, to and fro
B.swing = {
    init = function(p) p.ang, p.spd = 0x2000, 0.0 end,
    step = function(p)
        if p.roll < 0 then p.spd = p.spd + 4.0 else p.spd = p.spd - 4.0 end
        p.ang = p.ang + p.spd
        p.roll = s16(trunc(p.ang))
    end,
}
-- bhvSSLMovingPyramidWall (pyramid_wall.inc.c): up and down 512, a third of the way apart from each other
B.pyramid_wall = {
    init = function(p)
        if p.b2 == 1 then p.y = p.y - 256.0; p.timer = 50
        elseif p.b2 == 2 then p.y = p.y - 512.0; p.action = 1 end
    end,
    step = function(p)
        if p.action == 0 then
            p.vy = -5.12
            if p.timer == 100 then p.action = 1 end
        else
            p.vy = 5.12
            if p.timer == 100 then p.action = 0 end
        end
        p.y = p.y + p.vy
    end,
}

-- bhvLLLRotatingHexagonalPlatform: turns steadily
B.spin_hex = { step = function(p) p.yaw = s16(p.yaw + 0x100) end }

-- bhvLLLRotatingHexagonalRing (lll_hexagonal_ring.inc.c): turns; stood on, it slows to a stop for a while, then
-- turns again
B.hex_ring = {
    init = function(p) p.av = 0x100 end,
    step = function(p, m)
        local a = p.action
        if a == 0 then
            if m.plat == p then p.action = 1 end
            p.av = 0x100
        elseif a == 1 then
            p.av = 256.0 - sins(p.timer * 128) * 256.0
            if p.timer > 128 then p.action = 2 end
        elseif a == 2 then
            if m.plat ~= p or p.timer > 128 then p.action = 3 end
            p.av = 0
        else
            p.av = sins(p.timer * 128) * 256.0
            if p.timer > 128 then p.action = 0 end
        end
        p.yaw = s16(trunc(p.yaw - p.av))
    end,
}

-- bhvLLLRollingLog, bhvTTMRollingLog (rolling_log.inc.c): rolls the way the athlete walks on it, within its circle;
-- off it, it rolls back home and stops
B.roll_log = {
    init = function(p)
        if p.o.ttm then p.cx, p.cz, p.r2, p.myaw = 3970.0, 3654.0, 271037.0, 8810
        else p.cx, p.cz, p.r2, p.myaw = 5120.0, 6016.0, 1048576.0, 0x3FFF end
        p.av, p.pitch = 0, 0
    end,
    step = function(p, m)
        if m.plat == p then
            local d = (m.z - p.z) * coss(-p.myaw) - (m.x - p.x) * sins(-p.myaw)
            p.av = (d > 0) and p.av + 0x10 or p.av - 0x10
            p.av = math.max(-0x200, math.min(0x200, p.av))
        elseif (p.x - p.hx) ^ 2 + (p.y - p.hy) ^ 2 + (p.z - p.hz) ^ 2 < 100.0 * 100.0 then
            if p.av ~= 0 then
                p.av = (p.av > 0) and p.av - 0x10 or p.av + 0x10
                if p.av < 0x10 and p.av > -0x10 then p.av = 0 end
            end
        elseif p.av ~= 0x100 then
            p.av = (p.av > 0x100) and p.av - 0x10 or p.av + 0x10
            if p.av < 0x110 and p.av > 0xF0 then p.av = 0x100 end
        end
        local fv = p.av / 0x40
        local px, pz = p.x, p.z
        p.x, p.z = p.x + fv * sins(p.myaw), p.z + fv * coss(p.myaw)
        if p.r2 < (p.x - p.cx) ^ 2 + (p.z - p.cz) ^ 2 then p.x, p.z = px, pz end
        p.pitch = s16(p.pitch + p.av)
        if abs(p.pitch & 0x1FFF) < 528 and p.av ~= 0 then p.shot = "log_roll" end
    end,
}

-- bhvLLLVolcanoFallingTrap (rolling_log.inc.c): the wall in the volcano that falls flat as the athlete comes near,
-- lies a while and stands up again
B.volcano_trap = {
    init = function(p) p.av, p.acc, p.pitch = 0.0, 0.0, 0 end,
    step = function(p, m)
        local a = p.action
        if a == 0 then
            if (m.x - p.x) ^ 2 + (m.y - p.y) ^ 2 + (m.z - p.z) ^ 2 < 1000.0 * 1000.0 then p.action, p.shot = 1, "quiet_pound" end
        elseif a == 1 then
            p.acc = p.acc + 4.0
            p.av = p.av + p.acc
            p.pitch = s16(trunc(p.pitch - p.av))
            if p.pitch < -0x4000 or p.av > 0x4000 then
                p.pitch, p.av, p.acc, p.action, p.shot = -0x4000, 0.0, 0.0, 2, "big_pound"
                crush(p, m, 600.0, "a falling wall")
            end
        elseif a == 2 then
            if p.timer < 8 then p.y = p.hy + sins(p.timer * 0x1000) * 10.0 end
            if p.timer == 50 then p.action = 3 end
        else
            p.pitch = math.min(0, p.pitch + 0x90)
            if p.timer == 200 then p.action = 0 end
        end
    end,
}

-- bhvMerryGoRound (bbh_merry_go_round.inc.c): turns steadily
B.merry = {
    step = function(p, m)
        p.yaw = s16(p.yaw + 0x80)
        -- its tune: alone while he rides it, soft over the level's around it (bbh_merry_go_round.inc.c)
        local dx, dz = m.x - p.x, m.z - p.z
        local d2 = dx * dx + dz * dz
        local MUSIC = package.loaded["music"]
        if MUSIC and MUSIC.want_secondary and abs(m.y - p.y) < 700.0 then
            if m.plat == p then MUSIC.want_secondary("event_merry_go_round", 1.0, 0.0)
            elseif d2 < 1600.0 * 1600.0 then MUSIC.want_secondary("event_merry_go_round", 0.35, 0.4) end
        end
    end,
    hum = function(p) return "loop_merry_creak", 1800.0 end,
}

-- bhvPyramidElevator (pyramid_elevator.inc.c): stood on, it dips and goes down to 128 at 10 a frame
B.pyr_elev = {
    step = function(p, m)
        local a = p.action
        if a == 0 then
            if m.plat == p then p.action = 1 end
        elseif a == 1 then
            p.y = p.hy - sins(p.timer * 0x1000) * 10.0
            if p.timer == 8 then p.action = 2 end
        elseif a == 2 then
            p.y = p.y - 10.0
            if p.y < 128.0 then p.y, p.action = 128.0, 3 end
        else
            p.y = (p.timer >= 8) and 128.0 or (sins(p.timer * 0x1000) * 10.0 + 128.0)
        end
    end,
    hum = function(p) if p.action == 2 then return "loop_elevator1", 3000.0 end end,
}

-- bhvWDWExpressElevator (express_elevator.inc.c): stood on, it drops 132 frames at 20, waits, and climbs home at 10
-- (its wait at the foot `wait` frames, not Mario's 110: off it, round through the cage's hole and up onto it again
-- took the athlete longer - "platform starts going up to soon to get on", 2026-10-28)
B.express = {
    wait = 300,
    step = function(p, m)
        local a = p.action
        if a == 0 then
            if m.plat == p then p.action = 1 end
        elseif a == 1 then
            p.y = p.y - 20.0
            if p.timer > 132 then p.action = 2 end
        elseif a == 2 then
            if p.timer > B.express.wait then p.action = 3 end
        elseif a == 3 then
            p.y = p.y + 10.0
            if p.y >= p.hy then p.y, p.action = p.hy, 4 end
        elseif m.plat ~= p then
            p.action = 0
        end
    end,
    hum = function(p) if p.action == 1 or p.action == 3 then return "loop_elevator4", 3000.0 end end,
}

-- bhvBBHTiltingTrapPlatform (bbh_tilting_trap.inc.c): tips the way the athlete stands off its middle, then rights
B.tilt_trap = {
    step = function(p, m)
        local av = 0
        local on = m.plat == p
        if on then p.action = 1 else p.action = 0 end
        if on then
            local dx, dz = m.x - p.x, m.z - p.z
            local d = sqrt(dx * dx + (m.y - p.y) ^ 2 + dz * dz)
            local ang = atan(dx, dz) * 32768.0 / pi
            av = trunc(d * coss(ang))
            p.pitch = s16(p.pitch + av)                 -- (the game adds it twice a frame while he is on it)
        elseif abs(p.pitch) < 3000 or p.timer > 15 then
            if p.pitch > 0 then
                if p.pitch < 200 then p.pitch = 0 else av = -200 end
            else
                if p.pitch > -200 then p.pitch = 0 else av = 200 end
            end
        end
        p.pitch = s16(p.pitch + av)
    end,
}

-- bhvLLLMovingOctagonalMeshPlatform (lll_octagonal_rotating_mesh.inc.c): stood on it sinks 80 and runs its path
local MESH_PATHS = {
    [0] = { 2, 30, 0x4000, 0, 1, 220, 900, 30, 1, 30, 0, -30, 2, 30, -0x4000, 0, 1, 220, 900, 30, 1, 30, 0, -30, 3, 0 },
    [1] = { 4, 0, 0, 0, 1, 475, 900, 30, 1, 30, 0, -30, 2, 30, 0x8000, 0, 1, 475, 900, 30, 1, 30, 0, -30, 3, 0 },
}
B.oct_mesh = {
    init = function(p)
        p.y = p.y - 50.0; p.hy = p.y
        p.at, p.fv, p.myaw, p.st, p.sink, p.osc, p.bob = 1, 0.0, 0, 0, 0.0, 0, 0.0
        p.path = MESH_PATHS[p.b2] or MESH_PATHS[0]
    end,
    step = function(p, m)
        local t, i = p.path, p.at
        local c = t[i]
        if c == 4 then
            p.myaw, p.fv = t[i + 2], t[i + 3] / 100.0
            if m.plat == p then p.at, p.timer = i + 4, 0 end
        elseif c == 2 then
            p.myaw, p.fv = t[i + 2], t[i + 3] / 100.0
            if p.timer > t[i + 1] then p.at, p.timer = i + 4, 0 end
        elseif c == 1 then
            local goal, inc = t[i + 2] / 100.0, t[i + 3] / 100.0
            p.fv = p.fv + inc
            if (inc >= 0 and p.fv > goal) or (inc < 0 and p.fv < goal) then p.fv = goal end
            if p.timer > t[i + 1] then p.at, p.timer = i + 4, 0 end
        elseif c == 3 then
            p.fv, p.at = 0.0, 1
        end
        p.x, p.z = p.x + p.fv * sins(p.myaw), p.z + p.fv * coss(p.myaw)
        if m.plat == p then
            if p.st < 0x4000 then p.st = p.st + 0x400 else p.st = 0x4000 end
        elseif p.st > 0 then p.st = p.st - 0x400 else p.st = 0 end
        p.sink = sins(p.st) * -80.0
        if p.st == 0 or p.st == 0x4000 then
            p.osc = p.osc + 0x800
            p.bob = p.bob - sins(p.osc) * 2.0
        end
        p.y = p.bob + p.hy + p.sink
    end,
}

-- bhvRRRotatingBridgePlatform: RR's turning bridge, 0x80 a frame - and a flamethrower on it (bhv_flamethrower_loop,
-- its blue flames out along the way it faces: enemies.lua's flamethrower, carried round with it)
B.rr_bridge = {
    init = function(p, world)
        local EN = package.loaded["enemies"]
        if EN and EN.attach_thrower then
            local ok, e = pcall(EN.attach_thrower, world, p.x, p.y, p.z, p.yaw, p.b2)
            if ok then p.thrower = e end
        end
    end,
    step = function(p)
        p.yaw = s16(p.yaw - 0x80)
        local e = p.thrower
        if e then e.x, e.y, e.z, e.yaw = p.x, p.y, p.z, p.yaw end
    end,
}

-- bhvLLLRotatingBlockWithFireBars (lll_rotating_hex_flame.inc.c): with the athlete near (3000) the block turns, and
-- two bars of four flames (three for the small block) turn with it, 200 to 650 out from its middle. They burn.
B.fire_bars = {
    init = function(p) p.flames = {} end,
    step = function(p, m)
        local a = p.action
        if a == 0 then
            if (m.x - p.x) ^ 2 + (m.y - p.y) ^ 2 + (m.z - p.z) ^ 2 < 3000.0 * 3000.0 then p.action = 1 end
        elseif a == 1 then
            p.yaw, p.action = 0, 2
        elseif a == 2 then
            p.yaw = s16(p.yaw - 0x100)
            if (m.x - p.x) ^ 2 + (m.y - p.y) ^ 2 + (m.z - p.z) ^ 2 > 3200.0 * 3200.0 then p.action = 0 end
        end
        p.burning = (p.action == 2)
        if p.burning then
            local n = (p.b2 == 0) and 4 or 3
            for bar = 0, 1 do
                for i = 0, n - 1 do
                    local r = (200.0 + 150.0 * i) * ((bar == 0) and 1.0 or -1.0)
                    local fx, fz = p.x + r * sins(p.yaw), p.z + r * coss(p.yaw)
                    -- (bhvLLLRotatingHexFlame: INTERACT_FLAME, 50 round and 100 high from 50 to 150 over the block's foot -
                    -- with his 37 across and 160 up; it reached him 110 out and up to 300 over it, "the fire spinner still
                    -- reaches the player", 2026-10-19 - and sets him alight, as the torches do)
                    local dx, dz = m.x - fx, m.z - fz
                    if dx * dx + dz * dz < 87.0 * 87.0 and m.y > p.y - 110.0 and m.y < p.y + 150.0 then
                        local E = package.loaded["enemies"]
                        if E and E.set_alight then
                            pcall(E.set_alight, { x = fx, z = fz, type = "fire bar" }, m, lib.pawn(), "a fire bar", fx, fz)
                        else
                            local HP = _G.HEALTH
                            if HP and HP.grace <= 0 and not HP.dead_t then HP.damage((HP.DAMAGE and HP.DAMAGE.fire) or 1, "a fire bar") end
                        end
                    end
                end
            end
        end
    end,
}

-- drawing the fire bars' flames: pictures facing the camera
local function draw_fire_bars(p, a)
    local n = (p.b2 == 0) and 4 or 3
    if not p.quads then
        if not p.burning or P.dry then return end
        p.quads = {}
        local world = lib.world()
        for k = 1, 2 * n do
            -- (Mario 64's own flame pictures, as Bowser's and the flamethrowers': the painted ones were not its own,
            -- "some fires dont have the right textures", 2026-10-19)
            local q = lib.quad_actor(world, { X = p.wx + OFFSET.X, Y = p.wy + OFFSET.Y, Z = p.wz + OFFSET.Z }, 25.0 * 6.0 * S,
                                     "flame_sm64_red_" .. ((k - 1) % 8), "translucent")
            -- (RENDER 96: the fire in the round - burn.lua fire3d_on)
            do local BU = package.loaded["burn"]; if BU and BU.fire3d_on and q then pcall(BU.fire3d_on, world, q, 25.0 * 6.0 * S, false, nil) end end
            p.quads[k] = q or false
        end
    end
    local pawn = lib.pawn()
    local cx, cy, cz = 0.0, 0.0, 0.0
    pcall(function() local l = pawn:K2_GetActorLocation(); cx, cy, cz = lib.camera_location(l) end)
    local yaw = p.pyaw + s16(p.yaw - p.pyaw) * a
    local k = 0
    for bar = 0, 1 do
        for i = 0, n - 1 do
            k = k + 1
            local q = p.quads[k]
            if q then
                local r = (200.0 + 150.0 * i) * ((bar == 0) and 1.0 or -1.0)
                local fx, fz = p.x + r * sins(yaw), p.z + r * coss(yaw)
                local sx, sy, sz = -fz * S + OFFSET.X, fx * S + OFFSET.Y, (p.y + 100.0) * S + OFFSET.Z
                local dx, dy, dz = cx - sx, cy - sy, cz - sz
                pcall(function()
                    q:SetActorHiddenInGame(not p.burning)
                    q:K2_TeleportTo({ X = sx, Y = sy, Z = sz }, { Pitch = -deg(atan(dz, sqrt(dx * dx + dy * dy))), Yaw = deg(atan(dy, dx)) + 180.0, Roll = 0.0 })
                end)
            end
        end
    end
end
P.draw_fire_bars = draw_fire_bars

-- a tumbling bridge's plank (tumbling_bridge.inc.c): stood on, it shakes 5 frames, then tips and tumbles down
-- (300 below its floor it is gone); once the athlete is 1200 from it, it is back in its place
B.tumble_plank = {
    init = function(p) p.avp, p.avr, p.vy = 0, 0, 0.0 end,
    step = function(p, m)
        local a = p.action
        if a == 0 then
            if m.plat == p then p.action, p.rdir = 1, (math.random() < 0.5) and -0x80 or 0x80 end
        elseif a == 1 then
            p.fl = ground_under(p.x, p.y - 10.0, p.z) or (p.hy - 1700.0)
            -- (Mario 64's 5 frames; LLL's bridge waits a second: STORROR climbs its 150-high steps where Mario hops them, and
            -- the planks fell from under him mid-climb - "the platforms are buggy", 2026-10-19)
            if p.timer > (p.o.delay or 5) then p.action, p.shot = 2, "platform" end
        elseif a == 2 then
            if p.avp < 0x400 then p.avp = p.avp + 0x80 end
            if p.avr > -0x400 and p.avr < 0x400 then p.avr = p.avr + p.rdir end
            p.pitch, p.roll = s16(p.pitch + p.avp), s16(p.roll + p.avr)
            p.vy = p.vy - 3.0
            p.y = p.y + p.vy
            if p.y < p.fl - 300.0 then
                p.action, p.gone = 3, true
                if p.actor then pcall(function() p.actor:SetActorHiddenInGame(true) end) end
            end
        elseif not p.o.noreset and (m.x - p.hx) ^ 2 + (m.z - p.hz) ^ 2 > 1200.0 * 1200.0 then
            -- (LLL's, put up by the Big Bully's fall, does not come back: tumbling_bridge_act_2)
            p.x, p.y, p.z, p.pitch, p.roll, p.vy, p.avp, p.avr = p.hx, p.hy, p.hz, 0, 0, 0.0, 0, 0
            p.action, p.gone = 0, false
            if p.actor then pcall(function() p.actor:SetActorHiddenInGame(false) end) end
            p.jump = true
        end
    end,
}

-- the castle's trapdoor (castle_floor_trap.inc.c): both panels share one state (by `o.group`); stood on, they swing
-- open (the roll speeds from 0x400 down by 0x100 a frame to -0x4000) with a clank; 1000 away, they shut again.
-- Open, they are nothing to stand on or hold: the floor falls out from under him, as under Mario (they carried him
-- down with them and STORROR took hold of them: "make the trapdoors fall out from under the player instead of
-- grabbing the player", 2026-10-17); solid again once shut.
local traps = {}
B.floor_trap = {
    solid = function(g, on)
        for _, q in ipairs(g.panels) do
            q.gone = not on
            if q.actor then pcall(function() q.actor:SetActorEnableCollision(on) end) end
        end
    end,
    init = function(p)
        local g = traps[p.o.group]
        if not g then g = { action = 0, roll = 0, av = 0, t = 0, on = false, panels = {} }; traps[p.o.group] = g end
        g.panels[#g.panels + 1] = p
        p.trap = g
    end,
    step = function(p, m)
        local g = p.trap
        if m.plat == p then g.on = true end
        if p ~= g.panels[1] then p.roll = s16(g.roll); return end        -- (the first panel moves the pair)
        g.t = g.t + 1
        if g.action == 0 then
            g.av = 0x400
            if g.on then g.action, g.t, p.shot = 1, 0, "castle_trap"; B.floor_trap.solid(g, false) end
        elseif g.action == 1 then
            g.av = g.av - 0x100
            g.roll = g.roll + g.av
            if g.roll < -0x4000 then g.roll, g.action = -0x4000, 2 end
        elseif g.action == 2 then
            if not g.held and (m.x - p.x) ^ 2 + (m.y - p.y) ^ 2 + (m.z - p.z) ^ 2 > 1000.0 * 1000.0 then g.action = 3 end
        else
            g.roll = g.roll + 0x400
            if g.roll > 0 then g.roll, g.action = 0, 0; B.floor_trap.solid(g, true) end
        end
        g.on = false
        p.roll = s16(g.roll)
    end,
}

-- An arrival up out of the trap door's pit (game.lua G.arrive: the death that sends him back from the Dark World) finds
-- it open, and held open till he is back on the floor, when it shuts ("make him come out of the hole with the trap
-- doors open then when back on surface close the trap doors", 2026-10-15). Scene x, y and reach; returns how many
-- panels and the height of their hinges (the hallway's floor).
function P.open_traps(sx, sy, r)
    local n, top = 0, nil
    for _, p in ipairs(P.list) do
        local g = p.trap
        if g then
            local dx, dy = -p.z * S - sx, p.x * S - sy
            if dx * dx + dy * dy < r * r then
                g.action, g.roll, g.av, g.held = 2, -0x4000, 0, true
                p.roll, p.proll, p.drawn = -0x4000, -0x4000, nil      -- (open at once, not swung there)
                n, top = n + 1, p.y * S
            end
        end
    end
    return n, top
end
function P.shut_traps()
    for _, p in ipairs(P.list) do
        local g = p.trap
        if g and g.held then
            g.held = nil
            if g.action == 2 then g.action = 3 end
        end
    end
end

-- bhvBooStaircase (boo.inc.c bhv_boo_staircase): Big Boo's Haunt, act 1 - once the Ghost Hunt's Big Boo is beaten
-- (enemies.lua), the hall's three steps come up from 620 under where they stand, 8 a frame and humming, to their heights
-- (b2 1: 0, 0: -206, 2: -413), jiggle (jiggle_bbh_stair: -8 8 -4 4), and the top one plays the puzzle jingle. (In acts 2
-- to 6 they are there from the start: bhvHiddenStaircaseStep, plain static platforms.)
B.boo_stairs = {
    init = function(p)
        p.target = ({ [0] = -206.0, [1] = 0.0, [2] = -413.0 })[p.b2] or 0.0
        p.y = p.y - 620.0
        p.action = 1
    end,
    hum = function(p) return (p.action == 1) and "loop_elevator2" or nil, 2500.0 end,
    step = function(p)
        if p.action == 1 then
            p.y = p.y + 8.0
            if p.y > p.target then p.y, p.action = p.target, 2 end
        elseif p.action == 2 then
            if p.timer == 0 then p.shot = "lift_stop" end
            local j = ({ -8.0, 8.0, -4.0, 4.0 })[p.timer + 1]
            if j then p.y = p.y + j else p.action = 3 end
        elseif p.action == 3 then
            if p.timer == 0 and p.b2 == 1 then p.shot = "puzzle_jingle" end
            p.action = 4
        end
    end,
}

-- the castle clock's hands: turning (minute -0x180, hour -0x20 a frame), till he goes into the clock. Where they point is
-- kept across levels (P.clock_rolls, by turn rate), so they come back where they were and turn on from there, not from
-- 12 ("everytime I leave the level the minute and hour hand are on 12", 2026-10-30); Mario 64 builds them new at 12.
P.clock_rolls = P.clock_rolls or {}
B.spin_roll = {
    init = function(p)
        local r = P.clock_rolls[p.o.av or 0]
        if r then p.roll = r end
    end,
    step = function(p)
        if not p.stilled then p.roll = s16(p.roll + (p.o.av or 0)) end
        P.clock_rolls[p.o.av or 0] = p.roll
    end,
}

-- Tick Tock Clock's speed (gTTCSpeedSetting: 0 slow, 1 fast, 2 random, 3 stopped), from where the castle clock's minute
-- hand points as he jumps into the clock (clock_arm.inc.c: within 15 degrees of 12 stopped, the right half - round 3 -
-- slow, round 6 random, the left half - round 9 - fast); kept till he goes in again. The hands stop there. The hand goes
-- round once in 5.7 s, so the stopped window is half a second. Returns the speed; P.ttc_hand is where the hand was, in
-- minutes past the hour as drawn (for the log: "entering the level during specific times" - 2026-10-29)
P.ttc_speed = P.ttc_speed or 0
function P.ttc_clock()
    for _, p in ipairs(P.list) do
        if p.def == B.spin_roll then
            if (p.o.av or 0) == -0x180 then
                local r = p.roll % 0x10000
                P.ttc_hand = ((0x10000 - r) % 0x10000) * 60.0 / 0x10000
                if r < 0xAAA then P.ttc_speed = 3 elseif r < 0x6AA4 then P.ttc_speed = 1
                elseif r < 0x954C then P.ttc_speed = 2 elseif r < 0xF546 then P.ttc_speed = 0 else P.ttc_speed = 3 end
            end
            p.stilled = true
        end
    end
    if P.ttc_hand then log("castle clock: the minute hand at %.1f minutes past (12 = stopped)", P.ttc_hand) end
    return P.ttc_speed
end

-- the castle clock's pendulum: swings, a tock as it turns back at each end
B.deco_pendulum = {
    init = function(p) p.av = 0x100 end,
    step = function(p)
        if p.roll > 0 then p.av = p.av - 0x08 else p.av = p.av + 0x08 end
        p.roll = s16(p.roll + p.av)
        if p.av == 0x10 or p.av == -0x10 then p.shot = "big_clock" end
    end,
}

-- WF's tower ring (tower_platform.inc.c): sliders go in and out along their spoke, 3 a frame, 126 frames each way
B.tower_slide = {
    init = function(p) p.myaw, p.fv = p.yaw, 0.0 end,
    step = function(p)
        local span = 380 // 3
        if p.action == 0 then
            if p.timer > span then p.action = 1 end
            p.fv = -3.0
        else
            if p.timer > span then p.action = 0 end
            p.fv = 3.0
        end
        p.x, p.z = p.x + p.fv * sins(p.myaw), p.z + p.fv * coss(p.myaw)
    end,
}
-- ... and the lift at the top: stood on, it rises 700 (140 frames), waits 2 seconds, comes down
B.tower_elev = {
    step = function(p, m)
        local a = p.action
        if a == 0 then
            if m.plat == p then p.action = 1 end
        elseif a == 1 then
            if p.timer > 140 then p.action = 2 else p.y = p.y + 5.0 end
        elseif a == 2 then
            if p.timer > 60 then p.action = 3 end
        else
            if p.timer > 140 then p.action = 0 else p.y = p.y - 5.0 end
        end
    end,
    hum = function(p) if p.action == 1 or p.action == 3 then return "loop_elevator1", 2500.0 end end,
}

-- RR's donut blocks (donut_platform.inc.c): stood on, it shakes; after 15 frames it drops (gaining 0.1 a frame) and
-- bursts with a coin where it lands; it is back once the athlete is 1000 away
B.donut = {
    init = function(p) p.vy, p.t = 0.0, 0 end,
    step = function(p, m)
        local d2 = (m.x - p.hx) ^ 2 + (m.y - p.hy) ^ 2 + (m.z - p.hz) ^ 2
        if p.action == 0 then
            if m.plat == p then
                p.t = p.t + 1
                p.y = p.hy + ((p.t % 2 == 0) and 4.0 or -4.0)
                if p.t > 15 then p.action, p.vy = 1, 0.0 end
            else
                p.y, p.t = p.hy, 0
            end
        elseif p.action == 1 then
            p.vy = math.max(p.vy - 0.1, -75.0)
            p.y = p.y + p.vy
            local fy = ground_under(p.x, p.y + 50.0, p.z)
            if (fy and p.y <= fy) or p.y < p.hy - 3000.0 or d2 > 2500.0 * 2500.0 then
                p.action, p.gone = 2, true
                if p.actor then pcall(function() p.actor:SetActorHiddenInGame(true); p.actor:SetActorEnableCollision(false) end) end
                if fy and p.y <= fy then
                    p.shot = "donut_burst"
                    local G = package.loaded["game"]
                    if G and G.spawn_coin then pcall(G.spawn_coin, -p.z * S, p.x * S, (p.y + 60.0) * S) end
                end
            end
        elseif d2 > 1000.0 * 1000.0 then
            p.x, p.y, p.z, p.vy, p.t, p.action, p.gone = p.hx, p.hy, p.hz, 0.0, 0, 0, false
            if p.actor then pcall(function() p.actor:SetActorHiddenInGame(false); p.actor:SetActorEnableCollision(true) end) end
            p.jump = true
        end
    end,
}

-- the treasure chests (treasure_chest.inc.c): a group's state is shared (by `o.group`)
local chest_groups = {}

-- BBH's haunted books (flying_bookend_switch.inc.c bhv_haunted_bookshelf_manager_loop, bhv_book_switch_loop): the
-- manager's state is shared by the shelf and its three books. f4: books hit in order so far (-1: a wrong one);
-- f8: the books are to pop out.
local books = nil
local function book_state()
    if not books then books = { f4 = 0, f8 = 0, act = 1, t = 0, dx = 0.0 } end
    return books
end
local function play(name)
    local SFX = package.loaded["sfx"]
    if SFX then pcall(SFX.play, name, 1.0) end
end

-- bhvControllablePlatform (controllable_platform.inc.c): HMC's metal platform with an arrow on each side. Stood on, an
-- arrow sinks in and the platform sets off that way at 10 a frame; three feelers 300 ahead find the walls - the
-- middle one, or a side one pushed back along the way it goes, and it has hit one: it shakes a second and comes back
-- the other way (a side feeler pushed sideways only nudges it along). Left - the athlete 400 away - it flickers out
-- after five seconds and is back at home. (It was baked into the level, never moving, 2026-10-15.)
local CTRL_DIR = { [1] = { 0, 1 }, [2] = { 0, -1 }, [3] = { 1, 0 }, [4] = { -1, 0 } }      -- (x, z) per arrow
local CTRL_BACK = { [1] = 2, [2] = 1, [3] = 4, [4] = 3 }
-- a feeler at (x, z) at the platform's height: hit, and its push in Mario 64 units (x, z)
local function ctrl_feel(p, x, z)
    if not H.wall_near then return false, 0.0, 0.0 end
    local hit, sx, sy = H.wall_near(-z * S, x * S, p.y * S, 50.0 * S)
    return hit, (sy or 0.0) / S, -(sx or 0.0) / S
end
B.ctrl_platform = {
    init = function(p) p.d, p.f8, p.base, p.away, p.t5, p.t6, p.idle = 0, 0, p.y, false, 0, 0, 0 end,
    hum = function(p) if p.d >= 1 and p.d <= 4 then return "loop_elevator2", 2500.0 end end,
    step = function(p, m)
        local d = p.d
        if d == 0 then
            p.idle = p.idle + 1
            if p.away and p.idle > 30 then p.d, p.t6 = 6, 0 end
        elseif d >= 1 and d <= 4 then
            local v = CTRL_DIR[d]
            local ax, az = p.x + v[1] * 300.0, p.z + v[2] * 300.0
            local sx, sz = v[2] * 250.0, v[1] * 250.0
            local hm = ctrl_feel(p, ax, az)
            local ha, ax1, az1 = ctrl_feel(p, ax + sx, az + sz)
            local hb, ax2, az2 = ctrl_feel(p, ax - sx, az - sz)
            local function along(px, pz) return abs(v[1] ~= 0 and px or pz) >= 1.0 end
            if hm or (ha and hb) or (ha and along(ax1, az1)) or (hb and along(ax2, az2)) then
                -- (controllable_platform_hit_wall)
                p.f8, p.d, p.t5 = CTRL_BACK[d], 5, 0
                play("quiet_pound1")
            else
                if ha then p.x, p.z = p.x + ax1, p.z + az1 end
                if hb then p.x, p.z = p.x + ax2, p.z + az2 end
                p.x, p.z = p.x + v[1] * 10.0, p.z + v[2] * 10.0
            end
            local dx, dy, dz = m.x - p.x, m.y - p.y, m.z - p.z
            if dx * dx + dy * dy + dz * dz > 400.0 * 400.0 then p.d, p.away, p.t6 = 6, true, 0 end
        elseif d == 5 then
            -- (controllable_platform_shake_on_wall_hit)
            p.t5 = p.t5 + 1
            local t = p.t5
            if p.f8 == 1 or p.f8 == 2 then p.pitch = s16(sins(t * 0x1000) * 1820.4) else p.roll = s16(sins(t * 0x1000) * 1820.4) end
            p.y = p.base + sins(t * 0x2000) * 20.0
            if t >= 32 then p.d, p.pitch, p.roll, p.y = p.f8, 0, 0, p.base end
        elseif d == 6 then
            -- (obj_flicker_and_disappear(o, 150): five seconds, then a flicker, then back at home)
            p.t6 = p.t6 + 1
            if p.t6 > 150 and p.t6 < 190 then
                shown(p, p.t6 % 2 == 0)
            elseif p.t6 >= 190 then
                p.x, p.y, p.z, p.d, p.away, p.idle = p.hx, p.hy, p.hz, 0, false, 0
                shown(p, true)
                p.jump = true
                log("HMC's arrow platform is back at home")
            end
        end
        -- (controllable_platform_tilt_from_mario: stood on again before it goes, it stays)
        if p.d == 6 and m.plat and (m.plat == p or m.plat.main == p) then
            p.d, p.t6, p.idle = 0, 0, 0
            shown(p, true)
        end
    end,
}
B.ctrl_arrow = {
    step = function(p, m)
        local c = p.main
        if not c then
            for _, q in ipairs(P.list) do if q.def == B.ctrl_platform then c = q end end
            if not c then return end
            p.main, p.rel, p.state, p.t = c, 51.0, 0, 0
        end
        p.t = p.t + 1
        local dir = p.o.dir
        if p.state == 0 then
            -- (bhv_controllable_platform_sub_loop: up, and after a second ready to be stood on)
            -- (stood on: Mario 64 asks which surface is under him; here the slab, listed first, would answer for
            -- its arrows, so: his feet on the arrow's plate)
            local dx, dz = m.x - p.x, m.z - p.z
            local on = m.plat == p or (m.ground and dx * dx + dz * dz < 80.0 * 80.0 and abs(m.y - p.y) < 40.0)
            if p.t >= 30 and on and c.d ~= 6 then
                c.d, c.idle = dir, 0
                p.state, p.t = 1, 0
                play("platform_switch")
            end
        elseif p.state == 1 then
            p.rel = p.rel - 4.0
            if p.rel < 41.0 then p.rel, p.state, p.t = 41.0, 2, 0 end
        elseif p.state == 2 and c.d ~= dir then
            p.rel = p.rel + 4.0
            if p.rel > 51.0 then p.rel, p.state, p.t = 51.0, 0, 0 end
        end
        local off = p.o.off
        p.x, p.y, p.z = c.x + off[1], c.y + p.rel - 51.0 + off[2], c.z + off[3]
        if abs(p.x - (p.px or p.x)) > 200.0 or abs(p.z - (p.pz or p.z)) > 200.0 then p.jump = true end   -- (back home)
        if (p.gone or false) ~= (c.gone or false) then shown(p, not c.gone) end
    end,
}

-- (Reaches are Mario 64's hitboxes widened by the athlete's girth: he is much wider than Mario's 37, and solid things
-- hold him further off.)
-- An attack of the athlete's (a push, or a kick in the air) just now, at something within reach `r` across and from
-- `lo` to `hi` above its foot (Mario 64 units): Mario 64's check_mario_attacking, each attack counted once per thing
local function attacked_here(p, m, r, lo, hi)
    if not (P.attack_at and P.attack_at ~= p.hit_seen and os.clock() - P.attack_at < 0.4) then return nil end
    local dx, dz = m.x - p.x, m.z - p.z
    if dx * dx + dz * dz > r * r or m.y < p.y + lo or m.y > p.y + hi then return nil end
    p.hit_seen = P.attack_at
    return P.attack_air and 2 or 1
end

-- bhvTowerDoor (tower_door.inc.c): the door in Whomp's Fortress's tower; a punch or a kick breaks it (its 100-wide box
-- against Mario's). (Baked into the level, it stood for good, 2026-10-15.)
B.tower_door = {
    init = function(p) P.want_kick = true end,
    step = function(p, m)
        if not p.gone and attacked_here(p, m, 200.0, -160.0, 100.0) then
            play("wall_explosion")
            shown(p, false)
            log("WF's tower door broken")
        end
    end,
}

-- bhvKickableBoard (kickable_board.inc.c): Whomp's Fortress's plank standing on end. Hit, it rocks back and forth,
-- less and less; jump-kicked while it rocks from more than 160 up its side, it falls flat - a bridge - with a thump and
-- a shake. (Baked into the level, standing for good, 2026-10-15.)
B.kick_board = {
    init = function(p) P.want_kick = true; p.f8, p.f4, p.pv, p.rock_t = 0, 0, 0, 0 end,
    step = function(p, m)
        local a = p.action
        if a == 0 then
            p.pitch = 0
            if attacked_here(p, m, 190.0, -160.0, 1200.0) then p.f8, p.f4, p.rock_t, p.action = 1600, 0, 0, 1 end
        elseif a == 1 then
            p.rock_t = p.rock_t + 1
            p.pitch = s16(-sins(p.f4) * p.f8)
            -- (rocking, any push or kick at it knocks it over - Mario 64 wants a kick from up high, 160 over its foot, which
            -- the athlete could not give it: "cant push it over", 2026-10-17)
            local hit = p.rock_t > 15 and attacked_here(p, m, 190.0, -160.0, 1200.0)
            if hit then
                p.action, p.pv = 2, 0
                play("button_press2")
                -- (its shadow - a see-through decal in its model, on the ground under it standing - would tip up with it
                -- and stand at the bridge's end: Mario 64 changes to the felled board's model; "theres a wierd shadow at
                -- the bottom of the plank", 2026-10-17)
                for _, sec in ipairs(p.tpl and p.tpl.sections or {}) do
                    if sec.layer == "translucent_decal" and p.pmc then pcall(function() p.pmc:SetMeshSectionVisible(sec.id, false) end) end
                end
                return
            end
            if p.rock_t ~= 0 then
                p.f8 = p.f8 - 8
                if p.f8 < 0 then p.action, p.pitch = 0, 0; return end
            end
            if (p.f4 & 0x7FFF) == 0 then play("button_press2") end
            p.f4 = (p.f4 + 0x400) & 0xFFFF
        elseif a == 2 then
            p.pv = p.pv - 0x80
            p.pitch = p.pitch + p.pv
            if p.pitch < -0x4000 then
                p.pitch, p.pv, p.action = -0x4000, 0, 3
                play("board_thump")
                local G = package.loaded["game"]
                if G and G.shake_stage then pcall(G.shake_stage, 0.3) end
                log("WF's plank has fallen into a bridge")
            end
        end
    end,
}

-- bhvWFBreakableWallRight/Left (breakable_wall.inc.c): Whomp's Fortress's two walls by the tower. Shot from the cannon
-- into one (its 300 by 400 cylinder against Mario's), it blows apart - the right one with the puzzle jingle - and hurts
-- him a wedge, as Mario 64's does. (They were baked into the level, solid for good, 2026-10-15: "Blast Away the Wall"
-- could not be won.)
B.wf_wall = {
    step = function(p, m)
        if p.gone or not P.cannon_flight then return end
        local dx, dz = m.x - p.x, m.z - p.z
        if dx * dx + dz * dz < 337.0 * 337.0 and m.y > p.y - 160.0 and m.y < p.y + 400.0 then
            if p.o.right then play("puzzle_jingle") end
            play("wall_explosion")
            shown(p, false)
            local HP = _G.HEALTH
            if HP and HP.damage and (HP.grace or 0) <= 0 then pcall(HP.damage, 1, "a breakable wall") end
            local G = package.loaded["game"]
            if G and G.shake_stage then pcall(G.shake_stage, 0.3) end
            log("WF's %s breakable wall blown apart", p.o.right and "right" or "left")
        end
    end,
}

-- bhvWaterLevelPillar (water_pillar.inc.c): the two pillars in the castle basement's lake. A drop kick on top (Mario
-- 64's ground pound) drives one 80 down; both down, the puzzle jingle, the file keeps it (menu.lua flag "moat_drained":
-- SAVE_FLAG_MOAT_DRAINED) and the lake drains away below them, its first and third water boxes down to -2450 at 5 a
-- frame, with the rush of it. Drained already: they stand low, the lake low. Outside, the moat is drained with it
-- (game.lua, as the grounds load) and its grill gone (B.moat_grills): the way into Vanish Cap Under the Moat.
-- (Both were baked into their levels, the moat never to drain, 2026-10-15.)
local DRAIN_BOXES, DRAIN_TO = { 1, 3 }, -2450.0
local function moat_drained()
    local MN = _G.MENU
    return MN and MN.has_flag and MN.has_flag("moat_drained")
end
local function drain_boxes(y)
    local G = package.loaded["game"]
    if not (G and G.set_water_box) then return end
    for _, i in ipairs(DRAIN_BOXES) do pcall(G.set_water_box, i, y * S) end
end
B.water_pillar = {
    init = function(p)
        P.want_kick = true
        local top = 0.0
        local c = p.tpl.collision
        if c and c.pos then for i = 3, #c.pos, 3 do top = math.max(top, c.pos[i]) end end
        p.top = top / S * p.uscale[3]
        if moat_drained() then p.action, p.y = 9, p.hy - 80.0 end
    end,
    hum = function(p) if P.drain and P.drain.by == p and P.drain.t < 300 then return "loop_water_drain", 6000.0 end end,
    step = function(p, m)
        if p.action == 9 then
            -- (water_level_pillar_drained)
            if not p.set then p.set = true; drain_boxes(DRAIN_TO) end
            return
        end
        if p.action == 0 then
            local dx, dz = m.x - p.x, m.z - p.z
            local over = dx * dx + dz * dz < 160.0 * 160.0 and m.y > p.y + p.top - 80.0
            if (m.plat == p or over) and m.kick and P.kick_at ~= p.kick_seen then
                p.kick_seen = P.kick_at
                p.action = 1
                log("a basement pillar pounded down")
            elseif m.plat == p and m.land and P.land_at ~= p.land_seen then
                p.land_seen = P.land_at
                p.action = 1
                log("a basement pillar jumped down")
            end
            if p.action == 1 then
                local EF = package.loaded["envfx"]
                if EF and EF.poof then pcall(EF.poof, -p.z * S, p.x * S, (p.y + p.top) * S) end      -- (spawn_mist_particles)
                play("big_pound")
            end
        elseif p.action == 1 then
            if p.timer < 4 then p.y = p.y - 20.0 else p.action = 2 end
        elseif p.action == 2 then
            local other = nil
            for _, q in ipairs(P.list) do if q.def == B.water_pillar and q ~= p then other = q end end
            if other and other.action >= 2 and other.action ~= 9 and not P.drain then
                P.drain = { by = p, t = 0, y = -1228.0 }
                local MN = _G.MENU
                if MN and MN.add_flag then pcall(MN.add_flag, "moat_drained") end
                play("puzzle_jingle")
                log("both basement pillars down: the moat drains")
            end
            if P.drain then p.action = 3 end
        elseif p.action == 3 and P.drain and P.drain.by == p then
            local d = P.drain
            d.t = d.t + 1
            if d.t < 300 then
                d.y = approach(d.y, DRAIN_TO, 5.0)
                drain_boxes(d.y)
            end
        end
    end,
}
B.moat_grills = {
    init = function(p) if moat_drained() then shown(p, false) end end,
}

-- bhvPyramidTop (pyramid_top.inc.c): Shifting Sand Land's pyramid's top piece, the lid on the way down to Eyerok.
-- Each of the four stone pillars about the pyramid counts once he has stood on top of it (bhvPyramidPillarTouchDetector,
-- at Mario 64's own four spots: its 50-unit box against Mario's); all four, and the puzzle jingle - the top rises a
-- little, shakes, spins faster and faster and climbs, and after five seconds blows apart, the way in open. Each visit
-- anew, as in Mario 64. (It was baked into the level, the way to Eyerok's star shut for good, 2026-10-15.)
local PYRAMID_PILLARS = { { 1789, 1024, 764 }, { 1789, 896, -2579 }, { -5883, 1024, -2579 }, { -5883, 1024, 764 } }
B.pyramid_top = {
    init = function(p) p.touched, p.count, p.avel, p.vy = {}, 0, 0, 0.0 end,
    step = function(p, m)
        if p.action == 0 then
            for i, q in ipairs(PYRAMID_PILLARS) do
                local dx, dz = m.x - q[1], m.z - q[3]
                if not p.touched[i] and dx * dx + dz * dz < 130.0 * 130.0 and m.y > q[2] - 160.0 and m.y < q[2] + 60.0 then
                    p.touched[i], p.count = true, p.count + 1
                    log("the pyramid: pillar %d stood on (%d of 4)", i, p.count)
                end
            end
            if p.count >= 4 then
                p.action = 1
                play("puzzle_jingle")
                play("pyramid_spin")
            end
        elseif p.action == 1 then
            -- (bhv_pyramid_top_spinning)
            local t = p.timer
            p.x = p.hx + sins(t * 0x4000) * 40.0
            if t < 60 then
                p.y = p.hy + abs(sins(t * 0x2000) * 10.0)
            else
                p.avel = p.avel + 0x100
                if p.avel > 0x1800 then p.avel, p.vy = 0x1800, 5.0 end
                p.yaw = s16(p.yaw + p.avel)
                p.y = p.y + p.vy
            end
            if t >= 150 then p.action = 2 end
        elseif p.action == 2 and p.timer == 0 then
            -- (bhv_pyramid_top_explode: gone, in a burst of dust)
            play("pyramid_explode")
            shown(p, false)
            local G = package.loaded["game"]
            if G and G.shake_stage then pcall(G.shake_stage, 0.5) end
            log("the pyramid's top has blown apart: the way to Eyerok is open")
        end
    end,
}

B.bookshelf = {
    init = function(p) book_state().shelf = p end,
    step = function(p)
        if p.action == 1 then
            p.x = p.x + 5.0
            if p.timer > 101 then
                p.action, p.gone = 2, true
                if p.actor then
                    pcall(function() p.actor:SetActorHiddenInGame(true) end)
                    pcall(function() p.actor:SetActorEnableCollision(false) end)
                end
                log("the bookshelf has gone back")
            end
        end
    end,
    hum = function(p) if p.action == 1 then return "loop_elevator4", 3000.0 end end,
}
-- BitFS's tilting arena (bowser_act_tilt_lava_platform): { which way, speed, until frame }
local TILT_DATA = { { 1, 10, 40 }, { 0, 0, 74 }, { -1, -10, 114 }, { 1, -20, 134 }, { -1, 20, 154 }, { 1, 40, 164 },
                    { -1, -40, 174 }, { 1, -80, 179 }, { -1, 80, 184 }, { 1, 160, 186 }, { -1, -160, 186 } }
B.bowser_tilt = {
    init = function(p) P.bowser_arena = p end,
    step = function(p)
        -- (tipped, he slides on it, as on the sub: STORROR's own slope slide past 15 degrees and its "Slide" channel, 18,
        -- blocked - Mario 64 tips it to about 43; the athlete stands to 60 and had stood firm through it: "when the stage
        -- tilts the player needs to slide", 2026-10-25. Only while it is tipped: made a slide for good, level as it is when
        -- he arrives, STORROR slid him off it into the lava the moment he landed - "died the second i spawned in bowser
        -- fight".)
        local tipped = p.tt ~= nil and (abs(p.pitch) + abs(p.roll)) > 0x700
        if tipped ~= (p.slide_on or false) then
            p.slide_on = tipped
            pcall(function()
                if tipped then
                    p.pmc:SetWalkableSlopeOverride({ WalkableSlopeBehavior = 2, WalkableSlopeAngle = 15.0 })
                    p.pmc:SetCollisionResponseToChannel(18, 2)
                else
                    p.pmc:SetWalkableSlopeOverride({ WalkableSlopeBehavior = 0, WalkableSlopeAngle = 0.0 })
                    p.pmc:SetCollisionResponseToChannel(18, 0)
                end
            end)
        end
        if not p.tt then return end
        p.tt = p.tt + 1
        local sp
        for i, d in ipairs(TILT_DATA) do
            if p.tt < d[3] then
                if d[1] > 0 then sp = (d[3] - p.tt - 1) * d[2] else sp = (p.tt - TILT_DATA[i - 1][3]) * d[2] end
                break
            end
        end
        if not sp then
            p.tt, p.pitch, p.roll = nil, 0, 0
            return
        end
        p.pitch = s16(p.pitch + trunc(coss(p.tang) * sp))
        p.roll = s16(p.roll - trunc(sins(p.tang) * sp))
    end,
    hum = function(p) if p.tt then return "loop_big_platform", 8000.0 end end,
}
-- Bowser has landed at (x, z) (Mario 64 units): the arena rocks away from him
function P.tilt_arena(x, z)
    local p = P.bowser_arena
    if not p or p.tt then return end
    p.tt, p.tang = -1, s16(atan(p.x - x, p.z - z) * 32768.0 / pi + 0x8000)
end

-- The final fight's floors (game.lua G.pancakes): the Sky's arena three times over, b1 its number from the top. The
-- second rocks as the Fire Sea's does ("second stage he is able to tilt the stage as before on bowser in the fire sea",
-- 2026-11-03). Below the one he fights on, not solid (P.pancake_solid) - bowser_fight.lua makes the next one solid as
-- the one above it breaks.
P.pancakes = nil
B.pancake = {
    init = function(p)
        p.floor = p.b1
        P.pancakes = P.pancakes or {}
        P.pancakes[p.floor] = p
        if p.floor == 2 then P.bowser_arena = p end
        -- (the floor over it casts no shadow on it: the sun is overhead, and the floors are the arena's size)
        pcall(function() p.pmc:SetCastShadow(false) end)
        if p.floor > 1 then P.pancake_solid(p, false) end
    end,
    step = function(p, m)
        if p.floor == 2 and not p.gone then B.bowser_tilt.step(p, m) end
    end,
    hum = function(p) if p.floor == 2 and not p.gone then return B.bowser_tilt.hum(p) end end,
}
function P.pancake_solid(p, on)
    p.unsolid = not on
    if p.actor then pcall(function() p.actor:SetActorEnableCollision(on) end) end
end

-- THI's island tops (thi_top.inc.c)
B.thi_top = {
    init = function(p) P.want_kick = true; p.st = 0 end,
    step = function(p, m)
        local G = package.loaded["game"]
        if not G then return end
        local function gone()
            if p.gone then return end
            p.gone = true
            if p.actor then
                pcall(function() p.actor:SetActorHiddenInGame(true) end)
                pcall(function() p.actor:SetActorEnableCollision(false) end)
            end
        end
        if G.thi_drained then gone(); return end
        if not p.o.tiny then return end
        if p.st == 0 then
            local dx, dy, dz = m.x - p.x, m.y - p.y, m.z - p.z
            -- (or walked onto: on his feet over it, within 200 of its middle and 150 of its height - "make it so when you
            -- walk over it it opens", 2026-10-29; Mario 64's wants a ground pound, the athlete's drop kick did it here)
            local over = m.ground and dx * dx + dz * dz < 200.0 * 200.0 and math.abs(dy) < 150.0
            if over or (m.kick and dx * dx + dy * dy + dz * dz < 500.0 * 500.0) then
                p.st, p.t = 1, 0
                gone()
                p.shot = "cap_switch"
                log("the tiny island's top is broken")
            end
        elseif p.st == 1 then
            p.t = p.t + 1
            local SFX = package.loaded["sfx"]
            if SFX and SFX.hold then SFX.hold("loop_water_drain", 0.8) end
            if G.water_box_level then
                local z = G.water_box_level(3)
                if z then G.set_water_box(3, z - 0.75) end
            end
            if p.t >= 50 then
                p.st, G.thi_drained = 2, true
                if G.set_water_box then G.set_water_box(3, 700.0 * S) end
                local SFXp = package.loaded["sfx"]
                if SFXp then pcall(SFXp.play, "puzzle_jingle", 1.0) end
            end
        end
    end,
}

-- The ragdoll test area's movers (data/test_area.lua, tools/test_area.py: "make a test area, some stairs to fall down a
-- plink machine, and some moving parts to knock the player around", 2026-10-29). Each knocks him down (game.lua
-- G.knock_down with a push, which ragdoll.lua throws his body with), once in TEST_COOL seconds, not while he is down.
local TEST_COOL = 2.0
local function test_knock(p, dx, dz, speed, up, why)
    local G = package.loaded["game"]
    local RG = package.loaded["ragdoll"]
    if not (G and G.knock_down) then return false end
    if os.clock() < (p.cool or 0.0) then return false end
    if G.dying or (G.intangible and G.intangible()) or (RG and RG.limp and RG.limp()) then return false end
    local pawn = lib.pawn()
    if not pawn then return false end
    local d = math.sqrt(dx * dx + dz * dz)
    if d < 1e-6 then dx, dz, d = 0.0, 1.0, 1.0 end
    p.cool = os.clock() + TEST_COOL
    -- (Mario 64 x, z -> the scene's y, -x)
    G.knock_down(pawn, -dz / d * speed, dx / d * speed, up)
    log("test area: %s knocked him down", why)
    return true
end

-- a trip plate: stood on, it knocks him down the way it points (o.dir: Mario 64 x and z)
B.test_trip = {
    step = function(p, m)
        if not m.ground then return end
        local o = p.o
        if math.abs(m.x - p.x) > (o.hx or 60.0) or math.abs(m.z - p.z) > (o.hz or 250.0) or math.abs(m.y - p.y) > 80.0 then return end
        test_knock(p, o.dir[1], o.dir[2], o.speed or 650.0, o.up or 320.0, "a trip plate")
    end,
}

-- a bar spinning round its post, `half` long each way, `rate` a frame: met, it knocks him the way it is going there
B.test_bar = {
    init = function(p) p.yaw = 0 end,
    step = function(p, m)
        local o = p.o
        p.yaw = s16(p.yaw + (o.rate or 0x140))
        local half = o.half or 350.0
        local dx, dz = m.x - p.x, m.z - p.z
        local s, c = sins(p.yaw), coss(p.yaw)
        local along, out = dx * s + dz * c, dx * c - dz * s
        if math.abs(along) > half + 40.0 or math.abs(out) > 85.0 then return end
        if m.y > p.y + 90.0 or m.y + 170.0 < p.y - 40.0 then return end
        local sign = (along < 0.0) and -1.0 or 1.0
        test_knock(p, c * sign, -s * sign, 850.0, 350.0, "the spinning bar")
    end,
}

-- a ram sliding to and fro along x, `span` each way (round in 180 frames): met, it knocks him the way it is going
B.test_ram = {
    init = function(p) p.hx, p.t, p.vx = p.x, 0, 0.0 end,
    step = function(p, m)
        local o = p.o
        p.t = p.t + 1
        local nx = p.hx + (o.span or 400.0) * sins(p.t * 364)
        p.vx, p.x = nx - p.x, nx
        if math.abs(m.x - p.x) > (o.hx or 150.0) + 45.0 or math.abs(m.z - p.z) > (o.hz or 130.0) + 45.0 then return end
        if m.y > p.y + (o.h or 200.0) or m.y + 170.0 < p.y then return end
        if math.abs(p.vx) < 2.0 then return end
        test_knock(p, (p.vx > 0.0) and 1.0 or -1.0, 0.0, 800.0, 350.0, "the ram")
    end,
}

-- TTM's monkey cage (ukiki_cage.inc.c): waits; the Ukiki spins it; it falls, breaks, and leaves its star
B.ukiki_cage = {
    init = function(p) P.ukiki_cage, p.st, p.vy = p, "wait", 0.0 end,
    step = function(p)
        if p.st == "spin" then
            p.yaw = s16(p.yaw + 0x800)
        elseif p.st == "fall" then
            p.vy = math.max(-75.0, p.vy - 4.0)
            p.y = p.y + p.vy
            local fy = ground_under(p.x, p.y - p.vy + 50.0, p.z)
            if fy and p.y <= fy then
                p.y, p.st, p.gone = fy, "hide", true
                if p.actor then
                    pcall(function() p.actor:SetActorHiddenInGame(true) end)
                    pcall(function() p.actor:SetActorEnableCollision(false) end)
                end
                local G = package.loaded["game"]
                if G and G.add_star then
                    pcall(G.add_star, lib.world(), { kind = "star", pos = { -1300.0 * S, 2500.0 * S, -1200.0 * S }, id = p.o.star_id or 1 })
                end
                local SFX = package.loaded["sfx"]
                if SFX then pcall(SFX.play, "star_appears", 1.0) end
                p.shot = "big_pound"
                log("the monkey cage has broken")
            end
        end
    end,
}

-- HMC's Dorrie (dorrie.inc.c bhv_dorrie_update): round the lake 1650 to 2300 from home (that shifted by her neck's
-- reach); ridden, the way he faces at 10, dipping under him. A drop kick on her back near her neck's foot (Mario 64's
-- ground pound, under 320 ahead of her middle) lowers her head - her collision swapped for the lowered one - and out on
-- her head (over 780 ahead, settled under him) she lifts him on it to the ledges, along her neck's arc
-- (dorrie_raise_head); left alone 5 s, she raises it again. Drawn animated - swimming, head down and up - over her
-- template's collision. ("next dori needs fixed", 2026-10-19: she was a still model that only swam.)
local DORRIE_LOW = "none|dorrie_seg6_collision_0600FBB8"
local function dorrie_low_tpl(templates)
    local t = templates and templates[DORRIE_LOW]
    if t then return t end
    local G = package.loaded["game"]
    local x = G and G.extra_statics
    if x == nil then x = lib.load_data("data.extra_statics") end
    return x and x.hmc and x.hmc.templates and x.hmc.templates[DORRIE_LOW] or nil
end
local function dorrie_build(p, templates)
    p.tpl_hi = p.tpl_hi or p.tpl
    local lo = dorrie_low_tpl(templates)
    if lo then prepare(lo); p.tpl_lo = lo end
    if P.dry or not p.actor then return end
    p.cols_hi = {}
    pcall(function()
        local cls = StaticFindObject("/Script/ProceduralMeshComponent.ProceduralMeshComponent")
        for _, c in ipairs(p.actor:K2_GetComponentsByClass(cls)) do p.cols_hi[#p.cols_hi + 1] = c:get() end
    end)
    if lo and lo.collision then
        local pmc = lib.add_pmc(p.actor)
        if pmc then
            lib.add_collision(pmc, { lo.collision })
            pcall(function() pmc:SetCollisionEnabled(0) end)
            p.col_lo = pmc
        end
    end
end
local function dorrie_cols(p, low)
    if (p.low or false) == low or (low and not p.col_lo) then return end
    p.low = low
    for _, c in ipairs(p.cols_hi or {}) do pcall(function() c:SetCollisionEnabled(low and 0 or 3) end) end
    if p.col_lo then pcall(function() p.col_lo:SetCollisionEnabled(low and 3 or 0) end) end
    p.tpl = low and p.tpl_lo or p.tpl_hi
end
-- him held on her head as she lifts it (Mario 64 has him in a dialog the while): input off, out of STORROR's moves, flying
local function dorrie_hold(p, on)
    local pawn, pc = lib.pawn(), lib.controller()
    if not (pawn and pc) then return end
    if on then
        local G = package.loaded["game"]
        if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
        pcall(function() if not pc:IsMoveInputIgnored() then pc:SetIgnoreMoveInput(true); p.ign = true end end)
        pcall(function() local cm = pawn.CharacterMovement; cm:SetMovementMode(5, 0); cm:StopMovementImmediately() end)
    else
        pcall(function() if p.ign then pc:SetIgnoreMoveInput(false) end end)
        p.ign = nil
        -- (on her raised head: down onto its top, the floor of her raised collision under him)
        pcall(function()
            local l = pawn:K2_GetActorLocation()
            local half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
            local a, us, F = p.ax, p.uscale, p.tpl_hi and p.tpl_hi.floor
            if a and F and p.wx then
                local dx, dy, dz = l.X - OFFSET.X - p.wx, l.Y - OFFSET.Y - p.wy, l.Z - half - OFFSET.Z - p.wz
                local lx = (dx * a[1] + dy * a[2] + dz * a[3]) / us[1]
                local ly = (dx * a[4] + dy * a[5] + dz * a[6]) / us[2]
                local lz = (dx * a[7] + dy * a[8] + dz * a[9]) / us[3]
                local fz = H.floor_hit(F, lx, ly, lz + 150.0 / us[3])
                if fz then pawn:K2_TeleportTo({ X = l.X, Y = l.Y, Z = l.Z + (fz - lz) * us[3] + 2.0 }, pawn:K2_GetActorRotation()) end
            end
        end)
        pcall(function() pawn.CharacterMovement:SetMovementMode(3, 0) end)
    end
end
-- dorrie_raise_head: him carried along the arc her head makes, 440 out from her neck's foot
local function dorrie_raise_head(p)
    local a0 = p.neck
    p.neck = s16(p.neck - trunc(abs(370.0 * sins(p.raise))))
    local xz = 440.0 * (coss(p.neck) - coss(a0))
    local dy = 440.0 * (sins(p.neck) - sins(a0))
    local mx, my, mz = xz * sins(p.yaw), -dy, xz * coss(p.yaw)
    pcall(function()
        local pawn = lib.pawn()
        local l = pawn:K2_GetActorLocation()
        pawn:K2_TeleportTo({ X = l.X - mz * S, Y = l.Y + mx * S, Z = l.Z + my * S }, pawn:K2_GetActorRotation())
        pawn.CharacterMovement.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
    end)
end
local function dorrie_begin_raise(p, lifting)
    p.action, p.lifting, p.raise = 2, lifting, 0
    if lifting then dorrie_hold(p, true) else dorrie_cols(p, false) end
end
B.dorrie = {
    init = function(p, world, templates)
        p.fv, p.yv, p.off, p.vy = 0.0, 0, 0.0, 0.0
        p.x = p.x + 2000.0                              -- (ADD_FLOAT(oPosX, 2000), after SET_HOME)
        p.neck, p.af, p.anim = -0x26F4, 0.0, 2
        P.want_kick = true                              -- (m.kick: his drop kick, her ground pound)
        dorrie_build(p, templates)
    end,
    step = function(p, m)
        local function a2s(y, x) return s16(atan(x, y) * 32768.0 / pi) end
        -- (moved by her speed, then kept in her bounds)
        p.x, p.z = p.x + p.fv * sins(p.yaw), p.z + p.fv * coss(p.yaw)
        local to_home = a2s(p.hz - p.z, p.hx - p.x)
        local hx, hz = p.x - p.hx, p.z - p.hz
        local dist = sqrt(hx * hx + hz * hz)
        local shift = 440.0 * coss(p.neck) * coss(s16(p.yaw - to_home))
        local lo, hi = 1650.0 + shift, 2300.0 + shift
        if dist > 1.0 and (dist < lo or dist > hi) then
            local k = math.max(lo, math.min(hi, dist)) / dist
            p.x, p.z, dist = p.hx + hx * k, p.hz + hz * k, dist * k
        end
        local on = m.plat == p
        local fwd = (m.x - p.x) * sins(p.yaw) + (m.z - p.z) * coss(p.yaw)
        local pounded = on and m.kick
        -- dipping under him
        local maxo = 0.0
        if on then
            maxo = -17.0
            if p.off >= 0.0 then p.vy = pounded and -15.0 or -6.0 end
        end
        p.off = p.off + p.vy
        p.vy = approach(p.vy, 3.0, 1.0)
        if p.vy > 0.0 and p.off > maxo then p.off = maxo end
        p.y = p.hy + p.off
        if p.action == 0 then
            -- dorrie_act_move
            p.neck = -0x26F4
            if p.anim ~= 2 then p.anim, p.af = 2, 0.0 end
            p.af = p.af + 1.0
            if fwd < 320.0 and pounded and p.col_lo then
                p.action, p.fv, p.yv = 1, 0.0, 0
                p.anim, p.af = 3, 0.0
                dorrie_cols(p, true)
                log("Dorrie: her head down")
            else
                local ty, ts
                if on then
                    -- (ridden: the way he faces; he faces his actor's +X)
                    local face = p.yaw
                    pcall(function() face = s16((180.0 - lib.pawn():K2_GetActorRotation().Yaw) * 65536.0 / 360.0) end)
                    ty, ts = face, 10.0
                else
                    local circ = s16(0x4000 - a2s(2000.0, dist - 2000.0))
                    if s16(p.yaw - to_home) < 0 then circ = -circ end
                    ty, ts = s16(to_home + circ), 5.0
                end
                p.fv = approach(p.fv, ts, 0.5)
                local want = trunc(s16(ty - p.yaw) / 50)
                if p.yv < want then p.yv = math.min(want, p.yv + 5) else p.yv = math.max(want, p.yv - 5) end
                p.yaw = s16(p.yaw + p.yv)
            end
        elseif p.action == 1 then
            -- dorrie_act_lower_head: down to frame 35 of it and held there
            if p.af >= 35.0 then
                p.af = 35.0
                if on then
                    if abs(p.off + 17.0) < 0.01 and fwd > 780.0 then
                        dorrie_begin_raise(p, true)
                        log("Dorrie: lifting him")
                    elseif fwd > 320.0 then
                        p.timer = 0
                    end
                elseif p.timer > 150 then
                    dorrie_begin_raise(p, false)
                end
            else
                p.af = p.af + 1.0
                p.neck = s16(p.neck + 0x115)
            end
        else
            -- dorrie_act_raise_head
            p.af = p.af + 1.0
            if p.lifting then
                if p.af < 74.0 then
                    p.raise = p.raise + 0x1CC
                    dorrie_raise_head(p)
                end
                if p.af >= 73.0 then
                    p.lifting = false
                    dorrie_cols(p, false)
                    dorrie_hold(p, false)
                end
            end
            if p.af >= 79.0 then
                p.action, p.anim, p.af = 0, 2, 0.0
                dorrie_cols(p, false)
            end
        end
    end,
    -- her animated model (actor_geo_dorrie_geo: 2 swimming, 3 her head down and up), her template's own hidden
    draw = function(p, x, y, z, yaw)
        if p.vis == nil then
            p.vis = false
            local data = not P.dry and lib.load_data("data.actor_geo_dorrie_geo")
            if data then
                local inst = lib.make_instance(lib.world(), data, { X = -z * S + OFFSET.X, Y = x * S + OFFSET.Y, Z = y * S + OFFSET.Z }, 0.0, 1.0)
                if inst then
                    inst.moves = true
                    p.vis = inst
                    p.quads = p.quads or {}
                    p.quads[#p.quads + 1] = inst.actor
                    pcall(function()
                        for _, sec in ipairs((p.tpl_hi or p.tpl).sections or {}) do p.pmc:SetMeshSectionVisible(sec.id, false) end
                    end)
                end
            end
        end
        local v = p.vis
        if not v then return end
        lib.set_pose(v, -z * S + OFFSET.X, x * S + OFFSET.Y, y * S + OFFSET.Z, -yaw * 360.0 / 65536.0)
        local anim = v.data.anims and v.data.anims[p.anim or 2]
        if anim then lib.pose(v, anim, p.af or 0.0) end
    end,
}

-- DDD's whirlpool's swirl (bhv_whirlpool_loop): spinning, with the rush of the water
B.whirlpool = {
    step = function(p) p.yaw = s16(p.yaw + 8000) end,
    hum = function(p) return "loop_env_water", 3000.0 end,
}

-- SSL's tox boxes (tox_box.inc.c): 1 land, 2 rest, 4 forward (+z), 5 back, 6 right (-x), 7 left (+x), by table
local TOX_TABLES = {
    [0] = { 4, 1, 4, 1, 6, 1, 6, 1, 5, 1, 5, 1, 6, 1, 6, 1, 5, 1, 2, 4, 1, 4, 1, 4, 1, 2, 5, 1, 5, 1, 7, 1, 7, 1, 4, 1, 4, 1,
            7, 1, 7, 1, 5, 1, 5, 1, 5, 1, 2, 4, 1 },
    [1] = { 4, 1, 4, 1, 7, 1, 7, 1, 7, 1, 2, 6, 1, 6, 1, 6, 1, 5, 1, 5, 1, 6, 1, 5, 1, 5, 1, 2, 4, 1, 4, 1, 7, 1 },
    [2] = { 4, 1, 4, 1, 4, 1, 4, 1, 4, 1, 2, 5, 1, 5, 1, 5, 1, 5, 1, 5, 1, 7, 1, 2, 6, 1, 6, 1, 5, 1, 2, 4, 1, 7, 1 },
}
local TOX_ROLL = { [4] = { 0.0, 64.0, 0x800, 0 }, [5] = { 0.0, -64.0, -0x800, 0 }, [6] = { -64.0, 0.0, 0, 0x800 },
                   [7] = { 64.0, 0.0, 0, -0x800 } }
-- (its pitch and roll once the roll under way is done: tox_box_move's turning, the frames left of its 8)
function P.tox_landing(p)
    local pitch, roll, x, z = p.pitch or 0, p.roll or 0, p.x, p.z
    local r = TOX_ROLL[p.action]
    if not r then return pitch, roll, x, z end
    for _ = (p.timer or 0) + 1, 7 do
        pitch = s16(pitch + r[3])
        roll = s16(roll + ((pitch < 0) and -r[4] or r[4]))
        x, z = x + r[1], z + r[2]
    end
    return pitch, roll, x, z
end
B.tox_box = {
    init = function(p)
        p.hy = p.y + 256.0                      -- (ADD_FLOAT(oPosY, 256), then SET_HOME)
        p.y = p.hy
        p.tbl = TOX_TABLES[p.b2] or TOX_TABLES[0]
        p.ti, p.action = 1, p.tbl[1]
    end,
    step = function(p, m)
        local function next_action()
            p.ti = p.ti + 1
            if not p.tbl[p.ti] then p.ti = 1 end
            p.action = p.tbl[p.ti]
        end
        local r = TOX_ROLL[p.action]
        if r then
            p.y = 99.41124 * sins(floor((p.timer + 1) / 8 * 0x8000)) + p.hy + 3.0
            p.x, p.z = p.x + r[1], p.z + r[2]
            p.pitch = s16(p.pitch + r[3])
            local dr = (p.pitch < 0) and -r[4] or r[4]
            p.roll = s16(p.roll + dr)
            if p.timer == 7 then next_action(); p.shot = "tox_box" end
        elseif p.action == 1 then
            p.y = p.hy + 3.0
            if p.timer == 20 then next_action() end
        elseif p.timer == 20 then
            next_action()
        end
        if m then roll_crush(p, m, "a tox box") end
    end,
}

-- LLL's drawbridge halves (bhv_lll_drawbridge_loop): up to 45 degrees and down, resting between
B.drawbridge = {
    step = function(p)
        p.clock = (p.clock or 0) + 1                -- (Mario 64's global timer: both halves keep step)
        if p.action == 0 then p.roll = p.roll + 0x100 else p.roll = p.roll - 0x100 end
        if p.roll < -0x1FFD then
            p.roll = -0x2001
            if p.timer > 50 and p.clock % 8 == 0 then p.action, p.shot = 0, "boat_tilt1" end
        end
        if p.roll >= 0 then
            p.roll = 0
            if p.timer > 50 and p.clock % 8 == 0 then p.action, p.shot = 1, "boat_tilt2" end
        end
    end,
}
-- LLL's floating wooden planks (bhv_lll_wood_piece_loop)
B.wood_piece = {
    init = function(p) p.t = p.o.phase or 0 end,
    step = function(p)
        p.y = p.y + sins(p.t) * 3.0
        p.t = p.t + 0x400
    end,
}

-- LLL's Bowser puzzle (bowser_puzzle_piece.inc.c): each piece runs its list of moves, a move every 24 frames
local puzzle = nil
local PUZZLE_MOVE = { [3] = { -120.0, 0.0 }, [4] = { 120.0, 0.0 }, [5] = { 0.0, -120.0 }, [6] = { 0.0, 120.0 } }
-- (each piece 491 across, Mario 64's, laid 480 apart: the neighbours' edges overlapped and flickered through each other
-- - "the pieces are inside eachother slightly", 2026-10-19 - so each is drawn and stood on exactly 480 across, edge to
-- edge: at 0.975 a gap showed between them, "make the pieces bigger again and make sure they dont overlap")
local PUZZLE_FIT = 480.0 / 491.0
B.puzzle_piece = {
    noride = true,                  -- (render: he is not carried as it slides)
    init = function(p)
        p.i, p.ox, p.oy, p.oz = 0, 0.0, 0.0, 0.0
        puzzle = puzzle or { flags = 0, paid = false }
        local us = p.uscale or { 1.0, 1.0, 1.0 }
        pcall(function() p.actor:SetActorScale3D({ X = us[1] * PUZZLE_FIT, Y = us[2] * PUZZLE_FIT, Z = us[3] }) end)
    end,
    step = function(p, m)
        local g = puzzle
        if m.plat == p then g.flags = g.flags | 1 end
        -- the next move, when the last is done (bhv_lll_bowser_puzzle_piece_update)
        if not p.busy then
            local list = p.o.moves
            p.i = p.i % #list + 1
            p.action, p.timer, p.busy = list[p.i], 0, true
            if p.i == #list then g.flags = g.flags | 2 end
        end
        local mv = PUZZLE_MOVE[p.action]
        if mv then
            if p.timer < 20 then
                p.oy = (p.timer % 2 == 1) and 0.0 or -6.0          -- (it shakes first)
            else
                if p.timer == 20 then p.shot = "puzzle_piece" end
                if p.timer < 24 then
                    p.ox, p.oz = p.ox + mv[1], p.oz + mv[2]
                else
                    p.busy = false
                end
            end
        elseif p.timer >= 24 then
            p.busy = false
        end
        p.x, p.y, p.z = p.hx + p.ox, p.hy + p.oy, p.hz + p.oz
        -- stood on, and a round done, him near: five coins (once)
        if g.flags == 3 and not g.paid then
            local h = p.o.home
            local dx, dy, dz = m.x - h[1], m.y - h[2], m.z - h[3]
            if dx * dx + dy * dy + dz * dz < 1000.0 * 1000.0 then
                g.paid, g.flags = true, 0
                local G = package.loaded["game"]
                if G and G.spawn_coin then
                    for _ = 1, 5 do pcall(G.spawn_coin, -h[3] * S, h[1] * S, (h[2] + 100.0) * S) end
                end
                log("the Bowser puzzle's five coins")
            end
        end
    end,
}

-- BBH's coffins (coffin.inc.c): the odd ones stand up as he walks by - bhv_coffin_spawner_loop gives each its order's
-- i & 1, and COFFIN_BP_STATIC is 0. (The even ones stood up, and the two red coins lay under coffins that never did: "the
-- two red coins in this room we're in coffins that didnt stand up", 2026-10-22.)
B.coffin = {
    init = function(p) p.still, p.pv = (p.o.order % 2 == 0), 0.0 end,
    step = function(p, m)
        if p.still then return end
        local SQ = squish()
        if p.squishing and not (SQ and SQ.active()) then p.squishing = nil end
        if p.action == 0 then
            if p.pitch ~= 0 then
                -- lying back down
                p.pv = approach(p.pv, -2000.0, 200.0)
                p.pitch = approach(p.pitch, 0, -p.pv)
                if p.pitch == 0 then p.shot = "coffin_thud" end
                p.timer = 0
                -- (coming down on him where it lies - its length runs from 150 before its hinge to 450 behind, 140 to
                -- either side - he is pressed flat under it as a Thwomp presses him: squish.lua, "add our squish
                -- animation the coffins", 2026-10-22. Its underside over him: his way along it from the hinge, by
                -- the sine of how far up it still is.)
                if SQ and not SQ.active() and not p.squishing then
                    local yc, ys = coss(p.yaw), sins(p.yaw)
                    local dx, dz = m.x - p.x, m.z - p.z
                    local fwd, side = dx * yc + dz * ys, dz * yc - dx * ys
                    if abs(fwd) < 140.0 and side < 150.0 and side > -450.0 and m.y - p.y < 200.0 then
                        local along = math.max(0.0, -side)
                        local function under() return (p.y + along * sins(p.pitch)) * S end
                        if under() < p.y * S + 196.0 and SQ.start(lib.pawn(), {
                                bottom = function() return under() + OFFSET.Z end,
                                floor = p.y * S + OFFSET.Z, grounded = m.ground, what = "a coffin" }) then
                            p.squishing = true
                        end
                    end
                end
            else
                local yc, ys = coss(p.yaw), sins(p.yaw)
                local dx, dz = m.x - p.x, m.z - p.z
                local fwd, side = dx * yc + dz * ys, dz * yc - dx * ys
                -- (with him squished under it, it stands up again: coffin_act_idle's ACT_SQUISHED)
                if p.timer > 60 and (dx * dx + dz * dz > 100.0 * 100.0 or p.squishing) and m.y - p.y < 200.0 and abs(fwd) < 140.0
                   and side < 150.0 and side > -450.0 then
                    p.freeing = p.squishing
                    p.shot = "coffin_up"
                    p.action = 1
                end
                p.pv = 0.0
            end
        else
            if p.pitch ~= 0x4000 then
                p.pv = approach(p.pv, 1000.0, 200.0)
                p.pitch = approach(p.pitch, 0x4000, p.pv)
            else
                -- (up off him, it stays up till he is out from under it - 40 past where it lies - or 10 s: it lay down
                -- again before he could get out and pressed him flat once more - "the coffin stands and shuts too fast
                -- before the player can get out from under it", 2026-10-22)
                local under_it = false
                if p.freeing then
                    local yc, ys = coss(p.yaw), sins(p.yaw)
                    local dx, dz = m.x - p.x, m.z - p.z
                    local fwd, side = dx * yc + dz * ys, dz * yc - dx * ys
                    under_it = abs(fwd) < 180.0 and side < 190.0 and side > -490.0 and m.y - p.y < 200.0
                end
                if p.timer > 60 and (not under_it or p.timer > 300) then
                    p.action, p.roll, p.freeing = 0, 0, nil
                elseif p.timer > 30 then
                    -- (it shakes and rattles while it stands)
                    if p.timer % 4 == 0 then p.shot = "coffin_thud" end
                    p.roll = 400 * (p.timer % 2) - 200
                end
                p.pv = 0.0
            end
        end
    end,
}
B.book_mgr = {
    init = function(p) book_state().mgr = p; P.want_kick = true end,
    step = function(p, m)
        local g = book_state()
        g.t = g.t + 1
        local dx, dz = m.x - p.x, m.z - p.z
        local d = sqrt(dx * dx + (m.y - p.y) ^ 2 + dz * dz)
        local facing = abs(s16(atan(dx, dz) * 32768.0 / pi - p.yaw)) < 0x3000
        if g.act == 1 then
            if g.f8 == 0 then
                if d < 500.0 and facing then g.f8 = 1 end
            elseif g.t > 60 then
                g.act, g.f8, g.t = 2, 0, 0
            end
        elseif g.act == 2 then
            if d > 1500.0 and g.f4 < 3 then
                -- (he has left the library: the books go back in, as from the start)
                g.act, g.f4, g.f8, g.t = 1, 0, 0, 0
            elseif g.f4 < 0 then
                if g.t > 30 then g.f4, g.f8 = 0, 0 elseif g.t > 10 then g.f8 = 1 end
            elseif g.f4 >= 3 then
                if g.t == 30 then play("puzzle_jingle") end
                if g.t > 100 and g.shelf then
                    g.shelf.action, g.shelf.timer = 1, 0
                    g.act, g.t = 3, 0
                    log("haunted books: all three, the shelf goes back")
                end
            else
                g.t = 0
            end
        elseif g.act == 3 then
            g.dx = 5.0
            if g.t > 101 then g.act, g.dx = 4, 0.0 end
        end
    end,
}
B.book_switch = {
    init = function(p) book_state(); P.want_kick = true; p.out, p.hz0 = 0.0, p.z end,
    step = function(p, m)
        local g = book_state()
        if p.gone then return end
        if g.act == 4 then
            p.gone = true
            if p.actor then pcall(function() p.actor:SetActorHiddenInGame(true) end) end
            return
        end
        if g.f8 ~= 0 or p.action == 1 then
            if p.action ~= 1 and p.out == 0.0 then p.shot = "en_default_death" end
            p.action = 1
            p.out = approach(p.out, 50.0, 20.0)
            if p.out == 50.0 then
                -- hit while it sticks out (a punch or kick in Mario 64: STORROR's push, close to it)
                -- (the books are close together: only the nearest one to him takes the blow)
                local dx, dz = m.x - p.x, m.z - p.z
                local d2 = dx * dx + dz * dz
                local nearest = true
                for _, q in ipairs(P.list) do
                    if q ~= p and q.def == B.book_switch and not q.gone and (m.x - q.x) ^ 2 + (m.z - q.z) ^ 2 < d2 then nearest = false end
                end
                local close = nearest and d2 < 170.0 * 170.0 and m.y > p.y - 320.0 and m.y < p.y + 60.0
                -- (one blow, one book: the next nearest is not hit as the first goes in)
                if g.f4 >= 0 and p.timer > 60 and close and P.attack_at and P.attack_at ~= g.hit_seen
                   and os.clock() - P.attack_at < 0.4 then
                    g.hit_seen = P.attack_at
                    p.action = 2
                    log("haunted book %d hit", p.o.order)
                end
            else
                p.timer = 0
            end
        else
            p.out = approach(p.out, 0.0, 20.0)
            if p.out == 0.0 and p.action ~= 0 then
                if g.f4 == p.o.order then
                    play("right_answer")
                    g.f4 = g.f4 + 1
                    log("haunted book %d: right (%d)", p.o.order, g.f4)
                else
                    play("menu_buzz")
                    log("haunted book %d: wrong (wanted %d)", p.o.order, g.f4)
                    -- a bookend flies at him (from the room's side, at the shelf's height)
                    local E = package.loaded["enemies"]
                    if E and E.spawn_bookend then
                        local side = math.random(0, 1)
                        pcall(E.spawn_bookend, lib.world(), 0x1FC * side - 0x8CA, 890.0, math.min(0.0, m.z), 0x8000 * side + 0x4000)
                    end
                    g.f4 = -1
                end
                p.action = 0
            end
        end
        p.x = p.x + g.dx
        p.z = p.hz0 - p.out
    end,
}
local function chest_group(p)
    local g = chest_groups[p.o.group]
    if not g then g = { next = 1, fail = false, solved = false, t = 0 }; chest_groups[p.o.group] = g end
    return g
end
B.chest = {
    init = function(p) p.g = chest_group(p); p.open = false end,
    step = function(p, m)
        local g = p.g
        local dx, dz = m.x - p.x, m.z - p.z
        local near = dx * dx + dz * dz < 200.0 * 200.0 and abs(m.y - p.y) < 250.0
        if p.action == 0 then
            if near and not g.fail and not p.open then
                if g.next == p.o.order then
                    g.next, p.open, p.action = g.next + 1, true, 1
                    p.shot = "right_answer"
                    -- (its number in orange, 40 under it: spawn_orange_number)
                    local EF = package.loaded["envfx"]
                    if EF and EF.number then pcall(EF.number, p.o.order, -p.z * S, p.x * S, (p.y - 40.0) * S) end
                else
                    g.next, g.fail, p.action = 1, true, 2
                    p.shot = "menu_buzz"
                    -- (the wrong one: electrocuted - the Amp's shock, shock.lua: held lit up, the sparks, "Waaaooow",
                    -- a wedge - "add our electrocute to the chests if you get the pattern wrong", 2026-10-18; Mario 64's
                    -- wrong chest shocks Mario and shuts them all)
                    local HP = _G.HEALTH
                    -- (loaded here if no Amp has loaded it yet - enemies.lua does on an Amp's touch: Jolly Roger Bay has
                    -- none, and after a restart a wrong chest only took its wedge, "chest shock not working", 2026-10-18)
                    local okS, SH = pcall(require, "shock")
                    if not okS then SH = nil end
                    local shocked = SH and SH.start and SH.start({ x = p.x, y = p.y, z = p.z, what = "a treasure chest's shock", short = true }, m, lib.pawn())
                    if not shocked and HP and HP.grace <= 0 and not HP.dead_t then
                        HP.damage(1, "a treasure chest's shock")
                        local d = math.max(1.0, sqrt(dx * dx + dz * dz))
                        pcall(lib.bounce, lib.pawn(), -dz / d * 600.0, dx / d * 600.0, 400.0)
                    end
                end
            end
        elseif p.action == 1 then
            if g.fail then p.open, p.action = false, 0 end
        elseif not near and dx * dx + dz * dz > 500.0 * 500.0 then
            g.fail, p.action = false, 0
        end
        -- the last chest open: a jingle, and a second later the star
        if p.o.order == 4 and g.next == 5 and not g.solved then
            g.t = g.t + 1
            if g.t == 1 then local SFX = package.loaded["sfx"]; if SFX then pcall(SFX.play, "puzzle_jingle", 1.0) end end
            if g.t == 60 then
                g.solved = true
                local st = p.o.star
                local G = package.loaded["game"]
                if st and G and G.add_star then
                    pcall(G.add_star, lib.world(), { kind = "star", pos = { -st[3] * S, st[1] * S, st[2] * S }, id = p.o.star_id })
                    local SFX = package.loaded["sfx"]
                    if SFX then pcall(SFX.play, "star_appears", 1.0) end
                end
                log("treasure chests: all four open")
            end
        end
        if p.o.order == 4 and g.next == 5 and not g.drained and tostring(p.o.group):find("^bhvTreasureChestsShip") then
            P.ship_drain(g)
        end
    end,
}
-- The sunken ship's four open: Mario 64 drains the ship (bhv_treasure_chest_ship_loop: from the jingle on, the water
-- 5 a frame lower till it is at -335, SOUND_ENV_WATER_DRAIN heard and the camera shaking with it - "after doing the
-- chest puzzle in the sunken ship the water needs to lower", 2026-10-18). The ship's one water box, its surface with it.
P.SHIP_DRAIN_TO, P.SHIP_DRAIN_RATE = -335.0, 15.0        -- (Mario 64 units, and a frame: 3 times Mario 64's 5 - "make
                                                          -- the water drain 3 times faster", 2026-10-18)
function P.ship_drain(g)
    local G = package.loaded["game"]
    local z = G and G.water_box_level and G.water_box_level(1)
    if not z then g.drained = true; return end
    if not g.drain_t then log("treasure chests: the ship drains") end
    g.drain_t = (g.drain_t or 0) + 1
    z = math.max(P.SHIP_DRAIN_TO * S, z - P.SHIP_DRAIN_RATE * S)
    G.set_water_box(1, z)
    P.drain_until = os.clock() + 0.15            -- (its sound held every frame: P.update)
    if g.drain_t % 8 == 1 and G.shake_camera then pcall(G.shake_camera, 0.35) end
    if z <= P.SHIP_DRAIN_TO * S then g.drained = true; log("treasure chests: the ship drained") end
end
B.chest_lid = {
    init = function(p) p.g = chest_group(p) end,
    step = function(p)
        local chest
        for _, q in ipairs(P.list) do if q.def == B.chest and q.o.group == p.o.group and q.o.order == p.o.order then chest = q end end
        if chest and chest.open then
            if p.pitch > -0x4000 then
                if p.pitch == 0 then p.shot = p.o.bubble and "clam_shell" or "open_chest" end
                p.pitch = math.max(-0x4000, p.pitch - 0x200)
            end
        elseif p.pitch < 0 then
            p.pitch = math.min(0, p.pitch + 0x800)
        end
    end,
}

-- a cannon (cannon_lid / cannon.inc.c): shut until a Bob-omb Buddy opens it; then drop in, aim with the camera, push
local function grilled()
    for _, q in ipairs(P.list) do if q.def == B.hidden_120 and not q.gone then return true end end
    return false
end

-- The cannon itself (cannon.inc.c bhvCannon and its barrel; 2026-10-16 "add the cannon too"): once its lid is open it
-- waits 340 under the lid's place, out of sight down the hole. In: it rises 5 a frame for 68 frames, shaking, with
-- its sound; swings its barrel round and back (act 6) and nods it (act 5), each with its sound; then its barrel
-- follows his aim, and he is fired out of its mouth. Then it is back down the hole. (Mario 64 does not draw it
-- further than 500 from Mario; here it is always there - down the hole it is out of sight anyway.)
local CANNON_DOWN = 340.0
local cannon_models = nil
local function cannon_draw(p)
    local c = p.can
    local h = p.home
    local x, y, z = h[1] + c.dx, c.y, h[3] + c.dz
    local loc = { X = -z * S + OFFSET.X, Y = x * S + OFFSET.Y, Z = y * S + OFFSET.Z }
    -- (c.yaw: the way it faces, an engine yaw - 180 - Mario 64's. The base's model has its front along -X, as every
    -- exported model does; the barrel tips toward +X. Both turned by the model's rest yaw, the barrel had nodded and
    -- swung about the way behind it, then snapped to the camera's: "make cannons open the correct way", 2026-10-16)
    pcall(function() c.base.actor:K2_TeleportTo(loc, { Pitch = 0.0, Yaw = c.yaw + 180.0, Roll = 0.0 }) end)
    -- (the barrel stands up in its model: tipped forward by `tilt` degrees from upright, toward its yaw)
    pcall(function() c.barrel.actor:K2_TeleportTo(loc, { Pitch = -c.tilt, Yaw = c.yaw, Roll = 0.0 }) end)
end
local function cannon_make(p)
    if p.can or P.dry or not p.home then return end
    if not cannon_models then
        cannon_models = { base = lib.load_data("data.actor_cannon_base"), barrel = lib.load_data("data.actor_cannon_barrel") }
    end
    if not (cannon_models.base and cannon_models.barrel) then return end
    local w = lib.world()
    if not w then return end
    local h = p.home
    local rest = -((((p.o.bp or 0) >> 16) & 0xFF) << 8) * 360.0 / 65536.0       -- (its yaw: bparam2 << 8)
    local loc = { X = -h[3] * S + OFFSET.X, Y = h[1] * S + OFFSET.Y, Z = (h[2] - CANNON_DOWN) * S + OFFSET.Z }
    local base = lib.make_instance(w, cannon_models.base, loc, rest, 1.0)
    local barrel = lib.make_instance(w, cannon_models.barrel, loc, rest, 1.0)
    if not (base and barrel) then return end
    p.can = { base = base, barrel = barrel, rest = rest, face = rest + 180.0, yaw = rest + 180.0, tilt = 0.0, y = h[2] - CANNON_DOWN, dx = 0.0, dz = 0.0,
              act = 0, t = 0, f4 = 0 }
    cannon_draw(p)
end
local function cannon_home(c, p)
    c.act, c.t, c.f4 = 0, 0, 0
    c.y, c.dx, c.dz, c.yaw, c.tilt = p.home[2] - CANNON_DOWN, 0.0, 0.0, c.face, 0.0
end
local function jig(t, k) return ((math.floor(t / 2) % 2) - 0.5) * k end
-- one frame of the cannon (30 a second); `aim` = { yaw, pitch } in degrees while he is in it
local function cannon_step(p, aim)
    local c = p.can
    if not c then return end
    local SFX = package.loaded["sfx"]
    if c.act == 4 then                          -- (up out of the hole, shaking)
        c.y = c.y + 5.0
        c.dx, c.dz = c.dx + jig(c.t, 2.0), c.dz + jig(c.t, 2.0)
        if c.t > 67 then
            c.dx, c.dz = c.dx + jig(c.t, 4.0), c.dz + jig(c.t, 4.0)
            c.act, c.t = 6, -1
        end
    elseif c.act == 6 then                      -- (its barrel swung round and back)
        if c.t == 0 and SFX then pcall(SFX.play, "cannon_swing", 1.0) end
        if c.t < 4 then
            c.dx, c.dz = c.dx + jig(c.t, 4.0), c.dz + jig(c.t, 4.0)
        elseif c.t >= 6 and c.t < 22 then
            c.yaw = c.face - math.sin(c.f4 * 2.0 * math.pi / 65536.0) * 90.0
            c.f4 = c.f4 + 0x400
        elseif c.t >= 26 then
            c.f4, c.act, c.t = 0, 5, -1
        end
    elseif c.act == 5 then                      -- (and nodded)
        if c.t == 0 and SFX then pcall(SFX.play, "cannon_nod", 1.0) end
        if c.t >= 4 and c.t < 20 then
            c.f4 = c.f4 + 0x400
            c.tilt = math.sin(c.f4 * 2.0 * math.pi / 65536.0) * 45.0
        elseif c.t >= 25 then
            c.act, c.t = 1, -1
            -- (act_in_cannon: his aim starts where the cannon has come to point - its facing, nodded 45 up)
            p.aim_pitch = 90.0 - c.tilt
            pcall(function()
                local pc = lib.controller()
                local r = pc:GetControlRotation()
                pc:SetControlRotation({ Pitch = r.Pitch, Yaw = c.yaw, Roll = 0.0 })
            end)
        end
    elseif c.act == 1 and aim then              -- (his aim: the barrel where he will go)
        c.yaw, c.tilt = aim[1], 90.0 - aim[2]
    end
    c.t = c.t + 1
    cannon_draw(p)
end
-- his aim in the cannon: where the camera looks, a little higher (the camera looks down on him)
-- In a cannon, the view from behind and above it, along his aim, turned as he aims (camera.c's cannon camera looks
-- out of the barrel; his own camera sat inside it, the barrel's inside all he saw, 2026-10-16). Given back as he
-- is shot.
local BARREL_BACK, BARREL_UP = 560.0, 300.0     -- cm behind the hole and above it
-- Once it is up and aiming, Mario 64's own view from inside it ("wheres the cannon aimer just like in mario 64",
-- 2026-10-16): camera.c mode_cannon_camera puts the camera in the barrel looking exactly the way it aims (here at
-- its mouth, nothing of it in the way); screen_transition.c render_cannon_circle_base blacks out all but a round
-- window (its circle texture: 20 texels in a 51-texel-high screen, a radius of 0.392 of the screen's height, soft at
-- the edge); ingame_menu.c render_hud_cannon_reticle draws the sight - four triangles (0,0 8,8 0,16) in grey 50 at
-- 180/255, pointing in from 12 to 20 of its 240 lines off the middle. Mario 64's 45-degree view (73 across, wide).
local SCOPE_FOV = 73.0
local scope, scope_serial = nil, 0
local function scope_ok()
    if not scope then return false end
    local ok, valid = pcall(function() return scope.world == lib.world():GetAddress() and scope.widget:IsValid() end)
    return ok and valid
end
local function scope_build(world)
    local pc = lib.controller()
    if not (world and pc) then return nil end
    local function cls(path) return StaticFindObject(path) end
    scope_serial = scope_serial + 1
    local n = scope_serial
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("SM64CannonScope" .. n))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("SM64CannonScopeTree" .. n))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SM64CannonScopeCanvas" .. n))
    tree.RootWidget = canvas
    local H = 1080.0
    pcall(function()
        local WLL = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        local vs, sc = WLL:GetViewportSize(world), WLL:GetViewportScale(world)
        if vs and sc and sc > 0 then H = vs.Y / sc end
    end)
    local px = H / 240.0
    local count = 0
    local function image(file, x, y, iw, ih, angle)
        count = count + 1
        local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("SM64CannonScopeImg" .. n .. "_" .. count))
        local tex = lib.texture(world, file)
        if tex then img:SetBrushFromTexture(tex, false) end
        local slot = canvas:AddChildToCanvas(img)
        slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
        slot:SetAlignment({ X = 0.5, Y = 0.5 })
        slot:SetSize({ X = iw, Y = ih })
        slot:SetPosition({ X = x, Y = y })
        if angle then img:SetRenderTransformAngle(angle) end
    end
    -- (the window: its circle an eighth of the picture across; the picture wider than any screen)
    local side = 8.0 * 0.392 * H
    image("cannon_scope", 0.0, 0.0, side, side)
    -- (the sight: each triangle 8 by 16 of its pixels, centred 16 off the middle; screen y runs down here)
    image("cannon_reticle", -16.0 * px, 0.0, 8.0 * px, 16.0 * px, 0.0)
    image("cannon_reticle", 16.0 * px, 0.0, 8.0 * px, 16.0 * px, 180.0)
    image("cannon_reticle", 0.0, 16.0 * px, 8.0 * px, 16.0 * px, -90.0)
    image("cannon_reticle", 0.0, -16.0 * px, 8.0 * px, 16.0 * px, 90.0)
    w:AddToViewport(40)                         -- (under the HUD, as Mario 64 draws its counters over it)
    return { widget = w, world = world:GetAddress(), shown = true }
end
local function scope_show(on)
    if on and not scope_ok() then
        scope = nil
        local ok, s = pcall(scope_build, lib.world())
        if ok and s then scope = s else log("cannon scope: %s", tostring(s)) end
        return
    end
    if scope_ok() and scope.shown ~= on then
        scope.shown = on
        pcall(function() scope.widget:SetVisibility(on and 3 or 1) end)
    end
end
local function barrel_view(p, aim, hx, hy, hz)
    local pc, world = lib.controller(), lib.world()
    if not (pc and world) then return end
    local inside = not p.can or p.can.act == 1
    local yaw = math.rad(aim[1])
    local loc, rot
    if inside then
        -- (at the barrel's mouth, 200 cm along the aim from where it turns, looking along it)
        local cp = math.cos(math.rad(aim[2]))
        loc = { X = hx + OFFSET.X + math.cos(yaw) * cp * 200.0, Y = hy + OFFSET.Y + math.sin(yaw) * cp * 200.0,
                Z = hz + OFFSET.Z + math.sin(math.rad(aim[2])) * 200.0 }
        rot = { Pitch = aim[2], Yaw = aim[1], Roll = 0.0 }
    else
        -- (while it rises: behind it and above, raised a little as the barrel is - the cannon kept in sight)
        loc = { X = hx + OFFSET.X - math.cos(yaw) * BARREL_BACK, Y = hy + OFFSET.Y - math.sin(yaw) * BARREL_BACK,
                Z = hz + OFFSET.Z + BARREL_UP }
        rot = { Pitch = (aim[2] - 10.0) * 0.4 - 12.0, Yaw = aim[1], Roll = 0.0 }
    end
    local b = P.barrel_cam
    if not b then
        local cam = lib.camera(world, "cannon_barrel", loc, rot)
        if not cam then return end
        b = { cam = cam, pc = pc, world = world:GetAddress() }
        P.barrel_cam = b
        pcall(function() cam.CameraComponent:SetFieldOfView(90.0) end)
        pcall(function() pc:SetViewTargetWithBlend(cam, 0.5, 4, 2.0, false) end)
    else
        pcall(function() b.cam:K2_TeleportTo(loc, rot) end)
    end
    if inside ~= b.inside then
        b.inside = inside
        pcall(function() b.cam.CameraComponent:SetFieldOfView(inside and SCOPE_FOV or 90.0) end)
        scope_show(inside)
    end
end
local function barrel_view_end(blend)
    local b = P.barrel_cam
    P.barrel_cam = nil
    scope_show(false)
    if not b then return end
    local w = lib.world()
    if not (w and w:GetAddress() == b.world) then return end
    pcall(function() local pawn = lib.pawn(); if pawn then b.pc:SetViewTargetWithBlend(pawn, blend or 0.0, 4, 2.0, false) end end)
end

-- His aim in the cannon: its yaw the camera's, its pitch kept here (act_in_cannon: 0 to 80 degrees; 10 at least
-- here, the barrel clear of the hole). It was the camera's pitch too, but STORROR, holding him "falling" all the time
-- he sits in the barrel, eases the camera down to -20 every frame, and every shot went off at the lowest
-- (2026-10-16). Up aims up: the mouse, either stick, W or the up arrow; the left stick across, A and D, or the
-- arrows also turn it (Mario 64: 10 a frame of the stick's 64, 105 degrees a second flat out).
local AIM_MOUSE = 2.5           -- degrees for each unit the mouse travels
local AIM_RATE = 105.0          -- degrees a second, a stick flat out
local FIRE_KEYS = { "Gamepad_FaceButton_Bottom", "Gamepad_FaceButton_Right", "Gamepad_FaceButton_Left",
                    "Gamepad_RightTrigger", "LeftMouseButton", "SpaceBar" }
local function aim_input(dt)
    local p = P.in_cannon
    local pc = p and lib.controller()
    if not pc then return end
    local function axis(n)
        local ok, v = pcall(function() return pc:GetInputAnalogKeyState({ KeyName = FName(n) }) end)
        return (ok and type(v) == "number") and v or 0.0
    end
    local function key(n)
        local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(n) }) end)
        return ok and v
    end
    local function dead(v) return math.abs(v) < 0.15 and 0.0 or v end
    local my, ry, lx, ly = axis("MouseY"), dead(axis("Gamepad_RightY")), dead(axis("Gamepad_LeftX")), dead(axis("Gamepad_LeftY"))
    if key("W") or key("Up") then ly = 1.0 elseif key("S") or key("Down") then ly = -1.0 end
    if key("D") or key("Right") then lx = 1.0 elseif key("A") or key("Left") then lx = -1.0 end
    local up = math.max(-1.0, math.min(1.0, ry + ly))
    p.aim_pitch = math.max(10.0, math.min(80.0, (p.aim_pitch or 30.0) + my * AIM_MOUSE + up * AIM_RATE * dt))
    if lx ~= 0.0 then
        pcall(function()
            local r = pc:GetControlRotation()
            pc:SetControlRotation({ Pitch = r.Pitch, Yaw = r.Yaw + lx * AIM_RATE * dt, Roll = 0.0 })
        end)
    end
    -- Fire: a button pressed afresh once it is up (act_in_cannon: A). It went only by STORROR's own attack, which it
    -- stops doing after a while of "falling" in the barrel ("cannons arnt working", 2026-10-16: 90 s in, nothing).
    local down = false
    for _, k in ipairs(FIRE_KEYS) do if key(k) then down = true; break end end
    local ready = not p.can or p.can.act == 1
    if down and not p.fire_held and ready then P.attack_at = os.clock() end
    p.fire_held = down
end
local function cannon_aim(p)
    local r = nil
    pcall(function() r = lib.controller():GetControlRotation() end)
    return { r and r.Yaw or 0.0, (p and p.aim_pitch) or 30.0 }
end

-- BoB's act-1 cannon (water_bomb_cannon.inc.c; "still no lid on the cannon", 2026-10-16 - in act 1 the start's cannon
-- hole has no lid: this stands in it). Its parameter is 1, so it never fires; it shows within 2000 of him (hidden past
-- 2500), its barrel tipped 0x1C00 toward where it faces, and he is kept off a cylinder 220 round it, 300 up and down.
local WBC_TILT = 0x1C00 * 360.0 / 65536.0
-- The mountain's water bomb cannon (macro_water_bomb_cannon_2, its second parameter 0: water_bomb_cannon_act_1 and
-- bhv_bubble_cannon_barrel_loop; "what is this supposed to be?", 2026-10-16 - the white stone square it stands on was
-- all there was of it): its barrel turns to an aim - pitch 0x80 a frame, yaw 0x100 - and 60 frames after it is there
-- fires a water bomb out along it at 100 a frame (SOUND_OBJ_CANNON4, a shake, the barrel kicking back); 70 still, then
-- a new aim: 0x1000 + 0x400 x (0..3) tipped from upright, its yaw -0x2000 + 0x1000 x (0..4) about its own (the
-- first, Mario 64's leftover, yaw 0).
local function wbc_turn(cur, target, step)
    local d = s16(target - cur)
    if d > step then return s16(cur + step) elseif d < -step then return s16(cur - step) end
    return target
end
local function wbc_draw(p)
    local w = p.wbc
    local tilt = w.pitch * 360.0 / 65536.0
    local face = 180.0 - w.yaw * 360.0 / 65536.0
    local back = -w.recoil * S                      -- (kicked back along its axis)
    local ar, at = math.rad(face), math.rad(tilt)
    local loc = { X = -p.z * S + OFFSET.X + math.cos(ar) * math.sin(at) * back, Y = p.x * S + OFFSET.Y + math.sin(ar) * math.sin(at) * back,
                  Z = p.y * S + OFFSET.Z + math.cos(at) * back }
    pcall(function() p.barrel.actor:K2_TeleportTo(loc, { Pitch = -tilt, Yaw = face, Roll = 0.0 }) end)
end
local function wbc_fire_step(p, m)
    local w = p.wbc
    if not w then
        w = { rest = s16(((p.o.ang and p.o.ang[2]) or 0.0) * 65536.0 / 360.0), pitch = 0x1C00, tpitch = 0x1C00, yaw = 0, tyaw = 0,
              cool = 0, wait = 0, recoil = 0.0 }
        w.yaw = w.rest
        p.wbc = w
    end
    if w.cool > 0 then
        w.cool = w.cool - 1
    else
        w.pitch = wbc_turn(w.pitch, w.tpitch, 0x80)
        w.yaw = wbc_turn(w.yaw, w.tyaw, 0x100)
        if w.yaw == w.tyaw then
            if w.wait > 0 then
                w.wait = w.wait - 1
            else
                -- (fired along the barrel - its axis tipped `pitch` from upright - from 150 out along it)
                local E = package.loaded["enemies"]
                local elev = 0x4000 - w.pitch
                local cx, cz = sins(w.yaw) * coss(elev), coss(w.yaw) * coss(elev)
                if E and E.launch_wbomb then
                    pcall(E.launch_wbomb, lib.world(), p.x + cx * 150.0, p.y + 60.0 + sins(elev) * 150.0, p.z + cz * 150.0,
                          w.yaw, 100.0 * coss(elev), 100.0 * sins(elev))
                end
                local dx, dz = m.x - p.x, m.z - p.z
                local d = sqrt(dx * dx + dz * dz)
                local SFX = package.loaded["sfx"]
                if SFX and d < 4000.0 then pcall(SFX.play, "cannon_fire", math.max(0.2, 1.0 - d / 4000.0)) end
                local G = package.loaded["game"]
                if G and G.shake_stage and d < 1500.0 then pcall(G.shake_stage, 0.2) end
                w.recoil = 50.0
                w.cool = 70
                w.tpitch = 0x1000 + 0x400 * math.random(0, 3)
                w.tyaw = s16(-0x2000 + w.rest + 0x1000 * math.random(0, 4))
                w.wait = 60
            end
        end
    end
    w.recoil = math.max(0.0, w.recoil - 4.0)
    wbc_draw(p)
end
B.wbomb_cannon = {
    init = function(p)
        local data = not P.dry and lib.load_data("data.actor_cannon_barrel")
        local w = lib.world()
        if data and w then
            local face = 180.0 - ((p.o.ang and p.o.ang[2]) or 0.0)       -- (where it faces, as an engine yaw)
            local loc = { X = -p.z * S + OFFSET.X, Y = p.x * S + OFFSET.Y, Z = p.y * S + OFFSET.Z }
            p.barrel = lib.make_instance(w, data, loc, face, 1.0)
            if p.barrel then
                pcall(function() p.barrel.actor:K2_TeleportTo(loc, { Pitch = -WBC_TILT, Yaw = face, Roll = 0.0 }) end)
            end
        end
        p.vis = true
    end,
    step = function(p, m)
        local dx, dz = m.x - p.x, m.z - p.z
        local d = sqrt(dx * dx + dz * dz)
        local vis = p.vis
        if d < 2000.0 then vis = true elseif d > 2500.0 then vis = false end
        if vis ~= p.vis then
            p.vis = vis
            shown(p, vis)
            if p.barrel then pcall(function() p.barrel.actor:SetActorHiddenInGame(not vis) end) end
        end
        if vis and p.barrel and (((p.bp or 0) >> 16) & 0xFF) == 0 then wbc_fire_step(p, m) end
        -- (cur_obj_push_mario_away_from_cylinder: off it, out to its edge)
        if d < 220.0 and abs(m.y - p.y) < 300.0 then
            local pawn = lib.pawn()
            if pawn then
                local ux, uz = (d > 1.0) and dx / d or 1.0, (d > 1.0) and dz / d or 0.0
                local out = (220.0 - d) * S
                pcall(function()
                    local l = pawn:K2_GetActorLocation()
                    pawn:K2_SetActorLocation({ X = l.X - uz * out, Y = l.Y + ux * out, Z = l.Z }, false, {}, true)
                end)
            end
        end
    end,
}

local CANNON_DEPTH = 400.0         -- (Mario units his feet must be under a cannon's rim to be taken in: 3 m of its 3.8 - "make it go even further down")
local CANNON_WET_DEPTH = 130.0     -- (the same, swimming in a hole with water in it)
B.cannon = {
    init = function(p)
        P.want_kick = true
        p.home = { p.x, p.y, p.z }                   -- (the hole: the lid slides off it)
        p.open = p.o.open and true or false
        if p.open then shown(p, false); cannon_make(p) end     -- (macro_cannon_open: no lid - its stand-in never shown)
    end,
    step = function(p, m)
        -- (opening - cannon_door.inc.c: still for 60 frames while the camera comes to it, then down 0.5 a frame for 30
        -- with the cannon's sound, then aside along x 4 a frame for 50, then gone and the cannon open)
        local o = p.opening
        if o then
            o.t = o.t + 1
            if o.t == 61 then
                local SFX = package.loaded["sfx"]
                if SFX then pcall(SFX.play, "cannon_up", 1.0) end
            end
            if o.t > 60 and o.t <= 90 then p.y = p.y - 0.5
            elseif o.t > 90 and o.t <= 140 then p.x = p.x + 4.0 end
            if o.t >= 140 then
                p.opening, p.open, p.gone = nil, true, true
                if p.actor then
                    pcall(function() p.actor:SetActorHiddenInGame(true) end)
                    pcall(function() p.actor:SetActorEnableCollision(false) end)
                end
                log("cannon lid open")
            end
            return
        end
        if not p.open then return end
        if not p.can then cannon_make(p) end
        if p.o.open and grilled() then return end      -- (the castle grounds' one: under its grill till 120 stars)
        local pawn = lib.pawn()
        local h = p.home
        local hx, hy, hz = -h[3] * S, h[1] * S, h[2] * S        -- (the hole, scene cm)
        if P.in_cannon == p then
            -- (no swimming out of it: the swim held off while he sits in it)
            do local G = package.loaded["game"]; if G then G.swim_cool = math.max(G.swim_cool or 0.0, 0.5) end end
            -- (taken from it some other way than a shot - a warp within the scene: no longer in it. Left held, the next
            -- press of the button shot him out of this cannon from wherever he was, 2026-10-18)
            local l = nil
            pcall(function() l = pawn:K2_GetActorLocation() end)
            if not l or (l.X - OFFSET.X - hx) ^ 2 + (l.Y - OFFSET.Y - hy) ^ 2 > 300.0 * 300.0 then
                P.in_cannon = nil
                barrel_view_end(0.0)
                if p.can then cannon_home(p.can, p); cannon_draw(p) end
                log("out of the cannon without a shot")
                return
            end
            local aim = cannon_aim(p)
            cannon_step(p, aim)
            barrel_view(p, aim, hx, hy, hz)
            local ready = not p.can or p.can.act == 1
            if ready and P.attack_at and P.attack_at ~= p.fire_seen and os.clock() - P.attack_at < 0.4 then
                p.fire_seen = P.attack_at
                local pitch, yaw = aim[2], aim[1]
                local v = 100.0 * 30.0 * S                  -- (Mario 64: 100 a frame)
                local cp = cos(math.rad(pitch))
                local d = { cos(math.rad(yaw)) * cp, sin(math.rad(yaw)) * cp, sin(math.rad(pitch)) }
                -- (out of its mouth, his feet there: the barrel stands 177 cm up from where it turns, at the hole's rim
                -- once risen. His middle put there, his feet were down in the hole and he flew into its side)
                local G = package.loaded["game"]
                barrel_view_end(0.3)
                local mouth = p.can and 200.0 or 0.0
                local up = p.can and ((G and G.half) or 90.0) or 200.0
                -- (STORROR thought him falling all the time he sat in the barrel: its record of that cleared)
                if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
                pcall(function()
                    pawn:K2_TeleportTo({ X = hx + d[1] * mouth + OFFSET.X, Y = hy + d[2] * mouth + OFFSET.Y,
                                         Z = hz + d[3] * mouth + OFFSET.Z + up }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 })
                end)
                if G then G.air = false end
                P.in_cannon, p.cool = nil, 90
                P.cannon_flight = os.clock()        -- (ACT_SHOT_FROM_CANNON, until he is down again: P.update)
                -- (flown by flight.lua as Mario 64 has a shot, the level's edge a wall to it as to Mario - it once
                -- had G.no_fall_until set for 8 s here, which also switched the edge off: "make sure you cant cannon
                -- out of the world", 2026-10-16; without flight.lua, thrown, and that still needs it)
                local FL = package.loaded["flight"]
                if not (FL and FL.shoot and FL.shoot(pawn, pitch, yaw)) then
                    if G then G.no_fall_until = os.clock() + 8.0 end
                    pcall(function() pawn.CharacterMovement:SetMovementMode(3, 0) end)
                    pcall(lib.bounce, pawn, d[1] * v, d[2] * v, d[3] * v)
                end
                p.shot = "cannon"
                P.shot_from_cannon = true           -- (gMarioShotFromCannon: Koopa the Quick calls it cheating)
                -- (the cannon gone from sight as he is shot, back down its hole: opened_cannon_act_1 .. 0)
                if p.can then cannon_home(p.can, p); cannon_draw(p) end
                log("cannon fired: pitch %.0f yaw %.0f", pitch, yaw)
            end
            return
        end
        if p.cool and p.cool > 0 then p.cool = p.cool - 1; return end
        local dx, dz = m.x - h[1], m.z - h[3]
        -- (down in it: his feet a metre and more under its rim, inside the hole - Mario 64's cannon takes Mario as he
        -- falls in. Taken with his feet still level with the rim, crossing its edge was enough: "make sure you actually
        -- go down into cannons before it grabs to shoot you", 2026-10-17. BoB's holes are 3.8 m deep.)
        -- (a hole with water in it - Jolly Roger Bay's: swimming, he floats 2.3 m under its rim and could never get 3 m
        -- down; Mario 64 takes Mario into a cannon whatever he is doing, swimming too: "cannons having trouble grabbing
        -- player in water", 2026-10-18 - swimming, a metre under the rim will do, and his swim is ended first)
        local GW = package.loaded["game"]
        local wet = GW ~= nil and GW.swim
        local depth = wet and CANNON_WET_DEPTH or CANNON_DEPTH
        if dx * dx + dz * dz < 120.0 * 120.0 and m.y < h[2] - depth and m.y > h[2] - 600.0 then
            -- in: held in the barrel (the character stops moving until he fires), the cannon rising round him
            if wet and GW.stop_swim then pcall(GW.stop_swim); GW.swim_cool = 0.5 end
            P.in_cannon = p
            pcall(function()
                pawn:K2_TeleportTo({ X = hx + OFFSET.X, Y = hy + OFFSET.Y, Z = hz + OFFSET.Z - 40.0 }, pawn:K2_GetActorRotation())
                pawn.CharacterMovement:SetMovementMode(0, 0)
            end)
            p.shot = "cannon_in"                    -- (SOUND_OBJ_CANNON1: its rise)
            p.aim_pitch = 30.0
            p.fire_held = true                      -- (the button that took him in let go first)
            if p.can then p.can.act, p.can.t = 4, 0 end
            log("into a cannon")
        end
    end,
}

-- ddd_sub.inc.c: Bowser's sub and the door by it, gone once the file has the second key (SAVE_FLAG_HAVE_KEY_2)
B.gone_key2 = {
    init = function(p)
        local MN = _G.MENU
        if MN and MN.has_star and MN.has_star("key:2") then shown(p, false); log("Bowser's sub has gone (second key)"); return end
        -- (gone too in "Pole-Jumping for Red Coins" (act 3): its moving poles are where it lies - poles.lua)
        local G = package.loaded["game"]
        if G and G.name == "ddd_2" and G.act == 3 then shown(p, false); log("Bowser's sub has gone (act 3: the poles)"); return end
        -- (its slopes slide him off into the water, as Mario 64's do - mario_floor_is_slippery; only the level's own
        -- slopes had been made slides: "ship not making player slide in dire dire docks", 2026-10-23. The sub's hull is
        -- SURFACE_VERY_SLIPPERY, 276 of its 304 faces, sliding from 10 degrees; only its flat deck is ordinary floor
        -- (ddd/submarine/collision.inc.c) - at 38, the default kind's, he still stood on it: "the sub doesnt make the
        -- player slide". The door, the default kind. STORROR's own slope slide, as on the level's slides: too steep to
        -- stand on there, and its "Slide" trace channel, 18, blocked.)
        local steepest = tostring(p.o and p.o.tpl):find("submarine") and 10.0 or 38.0
        pcall(function() p.pmc:SetWalkableSlopeOverride({ WalkableSlopeBehavior = 2, WalkableSlopeAngle = steepest }) end)
        pcall(function() p.pmc:SetCollisionResponseToChannel(18, 2) end)
    end,
}

-- castle_cannon_grate.inc.c: the grill over the castle grounds' cannon, gone once the file has 120 stars
B.hidden_120 = {
    init = function(p)
        local MN = _G.MENU
        local n = (MN and MN.star_count and MN.star_count()) or 0
        if n >= 120 then shown(p, false); log("the cannon grill is gone (120 stars)") end
    end,
}

-- The camera on a cannon's lid as it opens (camera.c cutscene_prepare_cannon, 2026-10-16 "next add the cannon
-- doors"): it flies to the lid, 300 units off it and 45 degrees above, coming in from where the camera was, turns a
-- quarter of a right angle round it (0x400, 17 a frame) and stays the 140 frames the lid takes; then it flies back.
-- He stands still meanwhile, as Mario does.
local CUT_AT = 140 / 30         -- s on the lid
local CUT_FLY = 1.0             -- s flying there and back
local function cut_place(c)
    local turn = math.min(1.0, c.t * 30.0 / 60.0) * math.rad(22.5)
    local yaw = c.yaw0 + turn
    local d = 300.0 * S
    local h = d * math.cos(math.rad(45.0))
    local pos = { c.lid[1] + math.cos(yaw) * h, c.lid[2] + math.sin(yaw) * h, c.lid[3] + d * math.sin(math.rad(45.0)) }
    local dx, dy, dz = c.lid[1] - pos[1], c.lid[2] - pos[2], c.lid[3] - pos[3]
    local rot = { Pitch = math.deg(math.atan(dz, sqrt(dx * dx + dy * dy))), Yaw = math.deg(math.atan(dy, dx)), Roll = 0.0 }
    pcall(function() c.cam:K2_TeleportTo({ X = pos[1], Y = pos[2], Z = pos[3] }, rot) end)
end
local function cut_end(c, here)
    P.cut = nil
    if not here then return end                 -- (another map: nothing of the old one touched)
    pcall(function()
        if c.locked and c.pc:IsMoveInputIgnored() then c.pc:SetIgnoreMoveInput(false) end
        local pawn = lib.pawn()
        if pawn then pawn:EnableInput(c.pc) end
    end)
end
local function cut_start(p)
    local pc, world, pawn = lib.controller(), lib.world(), lib.pawn()
    if not (pc and world and pawn and p.wx) then return end
    local cl = pc.PlayerCameraManager:GetCameraLocation()
    local lid = { p.wx + OFFSET.X, p.wy + OFFSET.Y, p.wz + OFFSET.Z }
    local cam = lib.camera(world, "cannon", cl, pc.PlayerCameraManager:GetCameraRotation())
    if not cam then return end
    local c = { cam = cam, lid = lid, yaw0 = math.atan(cl.Y - lid[2], cl.X - lid[1]), t = 0.0, pc = pc,
                world = world:GetAddress(), prev = pc:GetViewTarget() }
    -- (begun from the Bob-omb Buddy's talk, the view was its dialog camera's: back to him after, not to that)
    pcall(function()
        local G = package.loaded["game"]
        local dc = G and G.dialog_cam and G.dialog_cam.cam
        if dc and c.prev and c.prev:GetAddress() == dc:GetAddress() then c.prev = pawn end
    end)
    P.cut = c
    cut_place(c)
    pcall(function() pc:SetViewTargetWithBlend(cam, CUT_FLY, 4, 2.0, false) end)
    pcall(function()
        if not pc:IsMoveInputIgnored() then pc:SetIgnoreMoveInput(true); c.locked = true end
        pawn:DisableInput(pc)
        pawn.CharacterMovement:StopMovementImmediately()
    end)
end
local function cut_tick(dt)
    local c = P.cut
    if not c then return end
    local w = lib.world()
    if not (w and w:GetAddress() == c.world) then cut_end(c, false); return end
    c.t = c.t + dt
    cut_place(c)
    if c.t >= CUT_AT and not c.back then
        c.back = true
        local to = nil
        pcall(function() if c.prev and c.prev:IsValid() then to = c.prev end end)
        to = to or lib.pawn()
        if to then pcall(function() c.pc:SetViewTargetWithBlend(to, CUT_FLY, 4, 2.0, false) end) end
    end
    if c.t >= CUT_AT + CUT_FLY then cut_end(c, true) end
end
-- whether the cannon's camera has the view (first person leaves it be)
function P.camera_busy() return P.cut ~= nil or P.barrel_cam ~= nil end

-- the level's cannons open (a Bob-omb Buddy's doing); false if there were none shut. Quiet (a scene load, the flag
-- already set): open at once. Otherwise the lid's opening, with the camera on it.
function P.open_cannons(quiet)
    local any, first = false, nil
    for _, p in ipairs(P.list) do
        if p.def == B.cannon and not p.open and not p.opening then
            any = true
            if quiet then
                p.open, p.gone = true, true
                if p.actor then
                    pcall(function() p.actor:SetActorHiddenInGame(true) end)
                    pcall(function() p.actor:SetActorEnableCollision(false) end)
                end
            else
                p.opening = { t = 0 }
                first = first or p
            end
        end
    end
    if first and not P.cut then pcall(cut_start, first) end
    return any
end

-- the final arena's outer pieces (bowser_falling_platform.inc.c): once Bowser is down to his last hit, they fall
-- one after another (20 frames apart, by their number): a lurch up for 22 frames with a crack, then down
B.bowser_plat = {
    step = function(p)
        if p.action == 0 then
            local G = package.loaded["game"]
            local bw = G and G.bowser
            if bw and bw.health and bw.health <= 1 then
                p.wait = (p.wait or 0) + 1
                if p.wait > 20 * (p.b2 - 1) then p.action = 1 end
            end
        elseif p.action == 1 then
            if p.timer == 0 or p.timer == 22 then p.shot = "bowser_plat" end
            if p.timer < 22 then p.vy = 8.0 else p.vy = (p.vy or 0.0) - 4.0 end
            p.y = p.y + p.vy
            if p.timer > 300 then
                p.action, p.gone = 2, true
                if p.actor then pcall(function() p.actor:SetActorHiddenInGame(true); p.actor:SetActorEnableCollision(false) end) end
            end
        end
    end,
}
-- (and one Bowser big-jumps off falls at once - falling_bowser_plat_act_check: his platform, his big jump: "he didnt jump
-- after he got damaged which usually makes the stage start to fall apart", 2026-11-02. bowser_fight.lua finds the piece
-- under him and breaks it.) The outer piece still in place under (x, y) - scene cm - no higher than zmax: it, its height.
function P.bowser_piece_under(x, y, zmax)
    local best, bz = nil, nil
    for _, p in ipairs(P.list) do
        local F = p.def == B.bowser_plat and not p.gone and (p.action or 0) == 0 and p.tpl and p.tpl.floor
        if F then
            local a = p.ax or { axes(p.pitch, p.yaw, p.roll) }
            local wx, wy, wz = p.wx or (-p.z * S), p.wy or (p.x * S), p.wz or (p.y * S)
            local dx, dy, dz = x - wx, y - wy, zmax - wz
            if dx * dx + dy * dy < (p.reach2 or 0.0) then
                local us = p.uscale
                local lx = (dx * a[1] + dy * a[2] + dz * a[3]) / us[1]
                local ly = (dx * a[4] + dy * a[5] + dz * a[6]) / us[2]
                local lz = (dx * a[7] + dy * a[8] + dz * a[9]) / us[3]
                local fz = H.floor_hit(F, lx, ly, lz)
                if fz then
                    local z = wz + lx * us[1] * a[3] + ly * us[2] * a[6] + fz * us[3] * a[9]
                    if z <= zmax + 1.0 and (not bz or z > bz) then best, bz = p, z end
                end
            end
        end
    end
    return best, bz
end
function P.break_bowser_piece(p)
    if p and p.def == B.bowser_plat and not p.gone and (p.action or 0) == 0 then p.action, p.timer = 1, 0; return true end
    return false
end

-- JRB's risen ship, rocking (bhv_ship_part_3_loop)
B.ship_rock = {
    init = function(p) p.t = 0 end,
    step = function(p, m)
        p.t = p.t + 0x100
        p.pitch = s16(trunc(sins(p.t) * 0x400))
        -- (the creak once for the whole ship: from its deck)
        if p.tpl.collision and m.y > 1000.0 and p.t % 0x4000 == 0 then p.shot = "boat_rock" end
    end,
}

-- JRB's sliding box (jrb_ship.inc.c bhv_jrb_sliding_box_loop): on the risen ship's deck, carried round by its rocking
-- and sliding along it at 20 * sin of a phase that turns 0x100 a frame - in step with the rock, so always downhill,
-- some 800 each way - and it hurts what it runs into (sSkullSlidingBoxHitbox: 130 round, 100 high, one wedge). (It
-- stood still on the deck, 2026-10-15.)
B.slide_box = {
    -- (SOUND_AIR_ROUGH_SLIDE while it slides fast and he is up on the ship)
    hum = function(p, m) if m.y > 1000.0 and p.v and abs(p.v) > 3.0 then return "loop_rough_slide" end end,
    step = function(p, m)
        if p.ship == nil then
            local best, bd = false, nil
            for _, q in ipairs(P.list) do
                if q.def == B.ship_rock and q.tpl.collision then
                    local d = (q.x - p.hx) ^ 2 + (q.z - p.hz) ^ 2
                    if not bd or d < bd then best, bd = q, d end
                end
            end
            p.ship = best
            if best then p.rx, p.ry, p.rz, p.ph = p.hx - best.x, p.hy - best.y, p.hz - best.z, 0 end
        end
        local s = p.ship
        if not s then return end
        local a = s.pitch or 0
        local sa, ca = sins(a), coss(a)
        p.x = s.x + p.rx
        p.y = s.y + ca * p.ry - sa * p.rz
        p.z = s.z + sa * p.ry + ca * p.rz
        p.pitch = a
        p.v = sins(p.ph) * 20.0
        p.rz = p.rz + p.v
        p.ph = (p.ph + 0x100) % 0x10000
        local dx, dz = m.x - p.x, m.z - p.z
        if dx * dx + dz * dz < 170.0 * 170.0 and m.y > p.y - 60.0 and m.y < p.y + 100.0 then
            local HP = _G.HEALTH
            if HP and HP.grace <= 0 and not HP.dead_t then
                HP.damage(1, "the sliding box")
                P.box_knock(p, dx, dz)
            end
        end
    end,
}
-- (run into by it: knocked flat, shoved out from it and on the way it slides - "make the moving box on the ship ragdoll
-- the player also add collisions", 2026-10-18: moved where it is each frame, it went through him, as a thing moved
-- never pushes his capsule; its collision only stopped him walking into it)
P.BOX_SHOVE, P.BOX_UP = 400.0, 300.0     -- (was 700, 400: "why is everything in the game doing so much knockback?", 2026-10-31)
--                     -- (cm/s out from it, and up)
function P.box_knock(p, dx, dz)
    local G = package.loaded["game"]
    local pawn = lib.pawn()
    if not (G and G.knock_down and pawn) then return end
    local d = math.max(1.0, sqrt(dx * dx + dz * dz))
    local slide = (p.v or 0.0) * 30.0 * S                  -- (its slide, along Mario 64's z: cm/s)
    local ax, az = dx / d * P.BOX_SHOVE, dz / d * P.BOX_SHOVE + slide
    pcall(G.knock_down, pawn, -az, ax, P.BOX_UP, true)
    log("the sliding box: knocked flat")
end

-- Snowman's Land's sliding snow mounds (snow_mound.inc.c): while he is within 6000 of the spawner and not 1000 above
-- it, one sets off at frames 64, 128, 192, 224 and 256 of each 256: 40 a frame along -x for 118 frames (rideable),
-- then down into the water (5 along, 10 down a frame) for 50 more, and gone. A pool of five, shown and hidden in
-- turn (actors made and destroyed by the dozen crashed the game, see the crash notes). (They were missing,
-- 2026-10-15.)
local MOUND_AT = { [64] = true, [128] = true, [192] = true, [224] = true, [256] = true }
-- A mound that reaches him from its front while it slides pushes him along before it, in STORROR's slope slide pose:
-- "make the mound push me along in front of it while I slide", 2026-10-26. (Left to the engine it shoved him a while
-- on its plain collision, or with its slide slopes slid him up and over it in a moment.) He is held PUSH_GAP before
-- its front side's foot - it slides along -y, Mario 64's -x; its sides 76.5 cm out from its ridge, which runs along x
-- for 192 either way - so it never touches him, till he steps out to the side, jumps, outruns it or it sinks. Its
-- draw, every frame: (x, y, z) its place this frame, Mario 64 units.
P.PUSH_GAP = 40.0
local SLIDE_POSE = "/SPP/SPPCharacter/Animation/Falling/Slide_Slope/FallingSlide_Slope_766_slides_31_08_24-002.FallingSlide_Slope_766_slides_31_08_24-002"
function P.push_end(pawn)
    local pu = P.pushed
    P.pushed = nil
    if pu and pu.clip and pawn then pcall(function() pawn.Mesh:GetAnimInstance():Montage_Stop(0.2, pu.clip) end) end
    log("snow mound: let go of him")
end
-- ...and limp (his ragdoll: movement mode 0), his body is pushed: its bodies given the mound's speed along its way,
-- each frame his pelvis is just before its front side - the engine's own push of a body by a moved collider is none:
-- "ragdoll doesnt get pushed by ice", 2026-10-26. (A velocity change, as the lava's throw of his body: G.lava_touch.)
P.MOUND_SPEED = 40.0 * S * 30.0                     -- (cm/s: 40 Mario 64 units a frame)
function P.mound_push_limp(p, pawn, wx, wy, wz)
    if p.gone or p.action ~= 0 then return end
    pcall(function()
        local mesh = pawn.Mesh
        local pl = mesh:GetSocketLocation(FName("pelvis"))
        local px, py, pz = pl.X - OFFSET.X, pl.Y - OFFSET.Y, pl.Z - OFFSET.Z
        local dx, dy = px - wx, py - wy
        if math.abs(dx) > 230.0 or dy < -(76.5 + 60.0) or dy > -10.0 or pz < wz - 40.0 or pz > wz + 150.0 then return end
        local v = mesh:GetPhysicsLinearVelocity(FName("pelvis"))
        local want = -P.MOUND_SPEED
        if v.Y > want then mesh:AddImpulseToAllBodiesBelow({ X = 0.0, Y = want - v.Y, Z = 0.0 }, FName("pelvis"), true, true) end
    end)
end
function P.mound_push(p, x, y, z)
    local pu = P.pushed
    if pu and pu.p ~= p and os.clock() - pu.t < 0.5 then return end        -- (another has him)
    local pawn = lib.pawn()
    if not pawn then return end
    local G = package.loaded["game"]
    local cm = pawn.CharacterMovement
    local l = pawn:K2_GetActorLocation()
    local half = (G and G.half) or 90.0
    local px, py, feet = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - half
    local wx, wy, wz = -z * S, x * S, y * S
    local dx, dy = px - wx, py - wy
    local front = -(76.5 + P.PUSH_GAP)
    local mode = cm.MovementMode
    if mode == 0 then
        if pu and pu.p == p then P.push_end(pawn) end
        return P.mound_push_limp(p, pawn, wx, wy, wz)
    end
    local footed = mode == 1 or (mode == 3 and cm.Velocity.Z < 50.0)          -- (not leaping up off it)
    local held = not p.gone and p.action == 0 and footed and math.abs(dx) < 215.0 and dy > front - 10.0 and dy < -10.0
        and feet > wz - 40.0 and feet < wz + 60.0
    if not held then
        if pu and (pu.p == p or os.clock() - pu.t >= 0.5) then P.push_end(pawn) end
        return
    end
    if not pu or pu.p ~= p then
        pu = { p = p }
        P.pushed = pu
        pcall(function()
            local seq = lib.try_load(SLIDE_POSE)
            if seq then pu.clip = pawn.Mesh:GetAnimInstance():PlaySlotAnimationAsDynamicMontage(seq, FName("FullBody"), 0.15, 0.25, 1.0, 100000, -1.0, 0.0) end
        end)
        log("snow mound: pushing him")
    end
    pu.t = os.clock()
    if dy > front then
        pcall(function() pawn:K2_SetActorLocation({ X = l.X, Y = wy + front + OFFSET.Y, Z = l.Z }, false, {}, true) end)
    end
end
B.snow_mound = {
    draw = function(p, x, y, z) P.mound_push(p, x, y, z) end,
    -- (SOUND_ENV_SINK_QUICKSAND as it slides)
    hum = function(p) if not p.gone and p.action == 0 then return "loop_sink_quicksand" end end,
    spawn = function(world, templates, o)
        local ctl = { mounds = {}, t = 0, x = o.pos[1], y = o.pos[2], z = o.pos[3] }
        for i = 1, 5 do
            local p = make(world, templates, o.tpl, o.pos[1], o.pos[2], o.pos[3], o.ang, o.scale)
            if p then
                p.o, p.def, p.bp, p.ctl, p.slot = o, B.snow_mound, 0, ctl, i
                shown(p, false)
                enlist(p)
                ctl.mounds[#ctl.mounds + 1] = p
            end
        end
    end,
    step = function(p, m)
        -- (its two 45-degree sides a slide, its ends walls - jumped onto, he slides down it: slide_split, once - "slide
        -- down its slopes", 2026-10-26. Its push: P.mound_push.)
        if not p.slid and p.pmc then
            p.slid = true
            local ok, err = pcall(slide_split, p)
            if not ok then log("snow mound: slide %s", tostring(err)) end
        end
        local c = p.ctl
        if p == c.mounds[1] then
            c.t = c.t + 1
            local dx, dy, dz = m.x - c.x, m.y - c.y, m.z - c.z
            if dx * dx + dy * dy + dz * dz < 6000.0 * 6000.0 and m.y < c.y + 1000.0 and MOUND_AT[c.t] then
                for _, q in ipairs(c.mounds) do
                    if q.gone then
                        q.x, q.y, q.z, q.action, q.timer, q.jump = q.hx, q.hy, q.hz, 0, 0, true
                        shown(q, true)
                        break
                    end
                end
            end
            if c.t >= 256 then c.t = 0 end
        end
        if p.gone then return end
        if p.action == 0 then
            p.x = p.x - 40.0
            if p.timer > 117 then p.action = 1 end
        else
            p.x, p.y, p.z = p.x - 5.0, p.y - 10.0, p.hz - 2.0
            if p.timer > 50 then shown(p, false) end
        end
    end,
}

-- Snowman's Land's big penguin (sl_walking_penguin.inc.c), on the ice bridge: forwards by a set of steps - walk 2 s,
-- stop 1 s, hurry 1 s, stop, back up 1 s, stop - until x < 300, a half turn (0x400 a frame for 32 frames), back at
-- a steady 12 until x > 1700, a half turn, and again. Six times a penguin's size, solid (he can be stood on), and
-- he shields whoever walks behind him from the snowman's breath (enemies.lua step_wind). (He stood still as a
-- statue, 2026-10-15.)
local PENGUIN_STEPS = { { 60, 1, 6.0, 1.0 }, { 30, 4, 0.0, 1.0 }, { 30, 1, 12.0, 2.0 }, { 30, 4, 0.0, 1.0 },
                        { 30, 1, -6.0, 1.0 }, { 30, 4, 0.0, 1.0 } }        -- (frames, animation 1 walk 4 idle, speed, rate)
B.walk_penguin = {
    init = function(p) p.cur, p.ct, p.af, p.anim, p.quads = 1, 0, 0.0, 1, {} end,
    step = function(p)
        local v, anim, rate = 0.0, 1, 1.0
        if p.action == 0 then
            if p.timer == 0 then p.cur, p.ct = 1, 0 end
            if p.ct < PENGUIN_STEPS[p.cur][1] then p.ct = p.ct + 1
            else p.ct, p.cur = 0, p.cur % #PENGUIN_STEPS + 1 end
            local s = PENGUIN_STEPS[p.cur]
            if p.x < 300.0 then p.action = 1
            else v, anim, rate = s[3], s[2], s[4] end
        elseif p.action == 1 or p.action == 3 then
            p.yaw = s16(p.yaw + 0x400)
            if p.timer == 31 then p.action = (p.action + 1) % 4 end
        else
            v, rate = 12.0, 2.0
            if p.x > 1700.0 then p.action = 3 end
        end
        p.x, p.z = p.x + sins(p.yaw) * v, p.z + coss(p.yaw) * v
        local fy = ground_under(p.x, p.y + 100.0, p.z)
        if fy and abs(fy - p.y) < 200.0 then p.y = fy end
        if anim ~= p.anim then p.anim, p.af = anim, 0.0 end
        local f0 = p.af
        p.af = p.af + rate
        -- (his footsteps: frames 1 and 11 of the walk, play_penguin_walking_sound(PENGUIN_WALK_BIG))
        if anim == 1 then
            for f = floor(f0) + 1, floor(p.af) do
                if f % 20 == 1 or f % 20 == 11 then p.shot = "big_penguin_walk" end
            end
        end
    end,
    draw = function(p, x, y, z, yaw)
        if p.vis == nil then
            p.vis = false
            local data = not P.dry and lib.load_data("data.actor_geo_penguin_geo")
            if data then
                local inst = lib.make_instance(lib.world(), data, { X = -z * S + OFFSET.X, Y = x * S + OFFSET.Y, Z = y * S + OFFSET.Z }, 0.0, 6.0)
                if inst then
                    inst.moves = true
                    p.vis = inst
                    p.quads[#p.quads + 1] = inst.actor         -- (taken away with the platform)
                end
            end
        end
        local v = p.vis
        if not v then return end
        lib.set_pose(v, -z * S + OFFSET.X, x * S + OFFSET.Y, y * S + OFFSET.Z, -yaw * 360.0 / 65536.0)
        local anim = v.data.anims and v.data.anims[p.anim or 1]
        if anim then lib.pose(v, anim, p.af or 0.0) end
    end,
}

-- RR's flying ship's wings (cruiser.inc.c): flapping, and the boat's creak every 64 frames
B.rr_wing = {
    init = function(p) p.y0, p.p0, p.t = p.yaw, p.pitch, 0 end,
    step = function(p)
        p.t = p.t + 1
        local sgn = (p.b2 == 0) and 1.0 or -1.0
        p.yaw = s16(trunc(p.y0 + sgn * sins(p.t * 0x400) * 8192.0))
        p.pitch = s16(trunc(p.p0 + coss(p.t * 0x400) * 2048.0))
        if p.t == 64 then p.t, p.shot = 0, "boat_rock" end
    end,
    -- (half as loud, and heard 22 m round, not 37: six wings creak at once - one creak now, sounds() - and it rang out
    -- over the whole carpet ride: "boat is really loud", 2026-11-02)
    shot_gain = 0.5,
    shot_reach = 3000.0,
}

-- bhvBlueCoinSwitch (blue_coin.inc.c): standing on it sinks it with a click (Mario 64 wants a ground pound; here a step
-- onto it does - "make it so if you walk on it it activates", 2026-10-17); it goes, the level's hidden blue coins come
-- out and it ticks while they last
B.blue_switch = {
    init = function(p) P.want_kick = true end,
    step = function(p, m)
        if p.action == 0 then
            if m.plat == p then p.action, p.vy, p.shot = 1, -20.0, "switch_press" end
        elseif p.action == 1 then
            if p.timer > 5 then
                p.action = 2
                p.gone = true
                if p.actor then
                    pcall(function() p.actor:SetActorHiddenInGame(true) end)
                    pcall(function() p.actor:SetActorEnableCollision(false) end)
                end
                local G = package.loaded["game"]
                if G and G.reveal_blue then pcall(G.reveal_blue) end        -- (it ticks while they last: G.blue_tick_check)
            else
                p.y = p.y + p.vy
            end
        end
    end,
}

-- ------------------------------------------------------------ Tick Tock Clock (ttc_*.inc.c), at the speed P.ttc_speed
-- (Mario 64's random_sign, random_mod_offset, random_linear_offset, and the clock's speed: 0 slow, 1 fast, 2 random, 3
-- stopped - each table below is in that order)
local TTC = {}
function TTC.sp()
    -- (a star played at a speed of its own - Tick Tock Clock's ghost race at the clock's own, whatever the minute hand
    -- said: game.lua G.EXTRA_STARS `ttc_speed`)
    local G = package.loaded["game"]
    local x = G and G.extra_act
    if x and x.ttc_speed ~= nil then return x.ttc_speed end
    return P.ttc_speed or 0
end
function TTC.sign() return (math.random(0, 1) == 0) and 1 or -1 end
function TTC.mod(base, step, m) return base + step * (math.random(0, 0xFFFF) % m) end
function TTC.lin(base, range) return base + floor(range * math.random()) end
function TTC.r16() return math.random(0, 0xFFFF) end
-- approach_f32_ptr: (new value, whether it got there)
function TTC.approach(cur, target, inc)
    if cur < target then cur = math.min(cur + inc, target) elseif cur > target then cur = math.max(cur - inc, target) end
    return cur, cur == target
end
-- the treadmills' one shared speed (their surfaces are one: sMasterTreadmill drives it at random)
TTC.tread = { speed = 50.0, target = 0.0, switch_at = 0, timer = 0 }
local function approach_s16(cur, target, inc)
    local d = s16(target - cur)
    if d >= 0 then
        if d > inc then return s16(cur + inc) end
    elseif d < -inc then
        return s16(cur - inc)
    end
    return s16(target)
end

-- (never left inside a moving box - Tick Tock Clock's rotating cube turning a side over onto him, its push blocks shooting
-- out into him: "stuck inside cube", 2026-10-29. Measured in the box's own frame from its actor's transform as drawn -
-- its turn mid-roll, its scale - against its collision's extents: his middle inside it by more than 10 cm, he is put out
-- through its nearest face, onto its top if that is nearest. Once a check every frame, a word in the log once in 3 s)
local KMathL = nil
-- (its collision's true extents, low and high on each axis: taken as the furthest each way from its middle, a bar
-- sticking out of its wall from its foot - Tick Tock Clock's, -8 to 338 long - got a box 338 the other way too, out in
-- front of the wall where no bar is, and he was put out of it there: "somethings blocking the player from walking
-- infront of the wall bumper", 2026-10-30)
local function box_bounds(p)
    if p.box_mn then return p.box_mn, p.box_mx end
    local mn, mx = { -100.0, -100.0, -100.0 }, { 100.0, 100.0, 100.0 }
    pcall(function()
        local c = p.tpl.collision.pos
        local lo, hi = { 1e9, 1e9, 1e9 }, { -1e9, -1e9, -1e9 }
        for i = 1, #c, 3 do
            for k = 0, 2 do
                local v = c[i + k]
                if v < lo[k + 1] then lo[k + 1] = v end
                if v > hi[k + 1] then hi[k + 1] = v end
            end
        end
        if hi[1] > lo[1] then mn, mx = lo, hi end
    end)
    p.box_mn, p.box_mx = mn, mx
    return mn, mx
end
local function keep_out_box(p)
    if not p.actor then return end
    local G = package.loaded["game"]
    if G and (G.dying or G.warping or (G.intangible and G.intangible())) then return end
    local pawn = lib.pawn()
    if not pawn then return end
    KMathL = KMathL or StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    pcall(function()
        local T = p.actor:GetTransform()
        local loc = pawn:K2_GetActorLocation()
        local mn, mx = box_bounds(p)
        local lp = KMathL:InverseTransformLocation(T, loc)
        local l = { lp.X, lp.Y, lp.Z }
        local inside = true
        for k = 1, 3 do if l[k] < mn[k] + 10.0 or l[k] > mx[k] - 10.0 then inside = false end end
        if not inside then return end
        -- (out through the nearest face: the axis he is furthest along from its middle, for its size)
        local c, e = {}, {}
        for k = 1, 3 do c[k], e[k] = (mn[k] + mx[k]) / 2.0, (mx[k] - mn[k]) / 2.0 end
        local best, bk = -1.0, 1
        for k = 1, 3 do local f = abs(l[k] - c[k]) / math.max(1.0, e[k]); if f > best then best, bk = f, k end end
        local sgn = (l[bk] >= c[bk]) and 1.0 or -1.0
        local out = { l[1], l[2], l[3] }
        out[bk] = c[bk] + sgn * (e[bk] + 45.0)
        local w = KMathL:TransformLocation(T, { X = out[1], Y = out[2], Z = out[3] })
        local dz = w.Z - loc.Z
        local up = dz > 0.0 and dz > 0.7 * math.sqrt((w.X - loc.X) ^ 2 + (w.Y - loc.Y) ^ 2 + dz * dz)
        if up then w = { X = w.X, Y = w.Y, Z = w.Z + 60.0 } end                -- (onto its top: his capsule's height)
        pawn:K2_SetActorLocation({ X = w.X, Y = w.Y, Z = w.Z }, false, {}, true)
        if os.clock() - (p.out_said or -9.0) > 3.0 then
            p.out_said = os.clock()
            log("%s: the athlete inside it - put out%s", tostring(p.o and p.o.bhv), up and " onto its top" or " at its side")
        end
    end)
end

-- bhvTTCRotatingSolid: a cube (4 sides) or prism (3) that dips, bleeps and turns a side over, every 4 seconds. It
-- turns at a quarter of Mario 64's 1200 a frame ("slow spinning cubes and triangles by 50%", then "slower", 2026-10-30),
-- and at half that on the fast setting, where its short wait has it turning nearly all the time ("make the blocks spin
-- slower in fast time", 2026-10-30).
B.ttc_solid = {
    turn = 300,
    turn_fast = 150,
    init = function(p)
        p.sides = (p.b2 == 0) and 4 or 3
        p.delay, p.vy, p.turns, p.beep = ({ 120, 40, 0, 0 })[TTC.sp() + 1], -5.0, 1, 0
        p.roll = s16(p.roll)
    end,
    step = function(p)
        if TTC.sp() ~= 3 and p.timer > p.delay then
            if p.beep ~= 0 then
                p.beep = p.beep - 1
                if p.beep == 0 then p.shot = "rotating_block_alert" end
            elseif p.vy > 0.0 and p.y >= p.hy then
                local target = s16(floor(p.turns / p.sides * 0x10000))
                local start = p.roll
                p.roll = approach_s16(p.roll, target, (TTC.sp() == 1) and B.ttc_solid.turn_fast or B.ttc_solid.turn)
                if p.roll ~= start then p.turning = (p.turning or 0) + 1 end
                if p.roll == start then
                    p.shot = "rotating_block_click"
                    p.turns = (p.turns + 1) % p.sides
                    -- (on Mario 64's timetable still: the frames its slower turn took past Mario 64's own are taken off
                    -- the wait for the next - counted from the end of each turn, the slow turns put every later one
                    -- further behind: "cubes dont spin during correct time", "cubes timings are still off", 2026-10-30)
                    -- (not on the random setting: each wait there is drawn anew, there's no timetable to keep, and taking
                    -- the slow turn off waits of 5 or 25 frames left none - turns back to back: "cubes trigger back to
                    -- back to back with no time inbetween", 2026-10-30. Nor on fast: its 40-frame wait went the same way,
                    -- turning without a stop - "cubes in fast clock still moving too fast", 2026-10-30.)
                    local own = math.ceil((0x10000 / p.sides) / 1200)
                    p.timer = (TTC.sp() == 2 or TTC.sp() == 1) and 0 or math.max(0, (p.turning or own) - own)
                    p.turning = 0
                    if TTC.sp() == 2 then p.delay = TTC.mod(5, 20, 7) end
                end
            else
                p.vy = p.vy + 0.5
                p.y = p.y + p.vy
                if p.y >= p.hy then p.y, p.beep = p.hy, 6 end
            end
        else
            p.vy = -5.0
        end
        keep_out_box(p)
    end,
}

-- bhvTTCPendulum: swings to and fro (accelerating toward the middle all the way), a swish each swing
-- A pendulum swung into him puts him out of its weight, as the cubes and bars do (keep_out_box) - he had nothing to put him
-- out of it, and was left inside it: "got stuck in pendulum", 2026-10-30. Its box is its weight's alone - the vertices
-- wider than its rod (a 30 cm rod above a weight 100 by 217): its whole height would have made the space round the rod
-- solid too.
local function pendulum_box(p)
    if p.box_mn then return end
    pcall(function()
        local c = p.tpl.collision.pos
        local lo, hi = { 1e9, 1e9, 1e9 }, { -1e9, -1e9, -1e9 }
        for i = 1, #c, 3 do
            if math.max(abs(c[i]), abs(c[i + 1])) > 20.0 then
                for k = 0, 2 do
                    local v = c[i + k]
                    if v < lo[k + 1] then lo[k + 1] = v end
                    if v > hi[k + 1] then hi[k + 1] = v end
                end
            end
        end
        if hi[1] > lo[1] then p.box_mn, p.box_mx = lo, hi end
    end)
end

B.ttc_pendulum = {
    init = function(p)
        -- (hung 70 higher - 52 cm, the athlete's height over Mario's: at the ends of its swing its weight goes 179 over
        -- the floor, clear of Mario's 160 and into the athlete's chest, and it shoved him off the clock's floor where
        -- Mario walks under it - stood on the gears by the start, he went into the pit, 2026-10-29)
        p.y = p.y + 70.0
        p.hy = (p.hy or p.y - 70.0) + 70.0
        p.acc, p.ang, p.dir, p.vel, p.delay, p.beep = ({ 13.0, 22.0, 13.0, 0.0 })[TTC.sp() + 1], 6500.0, 1.0, 0.0, 0, 0
        if TTC.sp() == 3 then p.ang = 6371.5557 end
    end,
    step = function(p)
        pendulum_box(p)
        if TTC.sp() == 3 then p.roll = s16(floor(p.ang)); keep_out_box(p); return end
        if p.beep ~= 0 then
            p.beep = p.beep - 1
            if p.beep == 0 then p.shot = "pendulum_swing" end
        end
        if p.delay ~= 0 then
            p.delay = p.delay - 1
        else
            if p.ang * p.dir > 0.0 then p.dir = -p.dir end
            p.vel = p.vel + p.acc * p.dir
            if p.vel == 0.0 then
                if TTC.sp() == 2 then
                    -- (a new swing strength, and now and then a pause)
                    p.acc = (TTC.r16() % 3 ~= 0) and 13.0 or 42.0
                    if TTC.r16() % 2 == 0 then p.delay = TTC.lin(5, 30) end
                end
                p.beep = p.delay + 15
            end
            p.ang = p.ang + p.vel
        end
        p.roll = s16(floor(p.ang))
        keep_out_box(p)
    end,
}

-- bhvTTCTreadmill: stands still; what stands on it is carried along (4.2 units a frame, its yaw's way: see P.update)
B.ttc_treadmill = {
    init = function(p)
        TTC.tread.master = nil
        TTC.tread.speed = ({ 50.0, 100.0, 0.0, 0.0 })[TTC.sp() + 1]
        p.convey = 0.084 * TTC.tread.speed
        local MT = package.loaded["movtex"]
        if MT and MT.set_speed then pcall(MT.set_speed, "MOVTEX_TREADMILL", TTC.tread.speed / 50.0) end
    end,
    hum = function(p) return (TTC.tread.speed ~= 0.0) and "loop_elevator2" or nil, 2500.0 end,
    step = function(p)
        local t = TTC.tread
        if t.master == nil or t.master == p then
            t.master = p
            if TTC.sp() == 2 then
                -- (still 5 frames, then toward the speed picked, till it is time to stop and pick again: 50 either way)
                t.timer = t.timer + 1
                if t.timer > t.switch_at then
                    local v, got = TTC.approach(t.speed, 0.0, 10.0)
                    t.speed = v
                    if got then t.switch_at, t.target, t.timer = TTC.mod(10, 20, 7), TTC.sign() * 50.0, 0 end
                elseif t.timer > 5 then
                    t.speed = TTC.approach(t.speed, t.target, 10.0)
                end
                local MT = package.loaded["movtex"]
                if MT and MT.set_speed then pcall(MT.set_speed, "MOVTEX_TREADMILL", t.speed / 50.0) end
            end
        end
        p.convey = 0.084 * t.speed
        -- (its belt, put on it once the scene's moving textures are read: movtex.lua M.attach - the big treadmill's or the
        -- small one's, by its model; "conveyer belt missing in tiktok clock", 2026-10-29)
        if p.belt == nil and p.actor then
            local MT = package.loaded["movtex"]
            if MT and MT.attach and MT.templates and next(MT.templates) then
                local id = (p.o and p.o.tpl and p.o.tpl:find("0002A8", 1, true)) and "MOVTEX_TREADMILL_SMALL" or "MOVTEX_TREADMILL_BIG"
                local okb, made = pcall(MT.attach, lib.world(), id, p.actor)
                p.belt = (okb and made) and true or false
                if not p.belt then log("ttc treadmill: no belt (%s)", tostring(made)) end
            end
        end
    end,
}

-- The bar shooting out of the wall into him bumps him off it, as the Bomps do (bomp_push): put just out in front of it,
-- thrown away and a little up, with a bonk - once a shot, while it shoots out ("next the beams that come out of the wall
-- should bump the player", 2026-10-30: it only put him out of itself, keep_out_box). It goes out along its own facing.
local function ttc_bar_bump(p)
    if p.cloth_at and os.clock() > p.cloth_at then
        p.cloth_at = nil
        local G0 = package.loaded["game"]
        if G0 and G0.reset_cloth then pcall(G0.reset_cloth) end
    end
    if p.action ~= 2 then p.bumped = nil; return end
    if p.bumped or p.spd <= 0.0 then return end
    if not (p.tpl and p.tpl.collision) then return end
    local pawn = lib.pawn()
    if not pawn then return end
    local G = package.loaded["game"]
    if G and (G.dying or (G.intangible and G.intangible())) then return end
    local box = bomp_box(p.tpl)
    local a = { axes(p.pitch, p.yaw, p.roll) }
    local wx, wy, wz = -p.z * S, p.x * S, p.y * S
    local l = nil
    pcall(function() l = pawn:K2_GetActorLocation() end)
    if not l then return end
    local half = (G and G.half) or 90.0
    local px, py, pz = l.X - OFFSET.X - wx, l.Y - OFFSET.Y - wy, l.Z - OFFSET.Z - wz
    local lx = px * a[1] + py * a[2] + pz * a[3]
    local ly = px * a[4] + py * a[5] + pz * a[6]
    local lz = pz
    local mn, mx = box.mn, box.mx
    if lz - half > mx[3] - 40.0 or lz + half < mn[3] then return end      -- (on top of it, or up over its top: left be)
    local dx, dy = -coss(p.yaw), sins(p.yaw)                -- (its way out: Mario 64 x, z -> the scene's y, -x)
    local ox, oy = dx * a[1] + dy * a[2], dx * a[4] + dy * a[5]
    local along, across, amin, amax, cmin, cmax
    if abs(oy) >= abs(ox) then
        along, across, amin, amax, cmin, cmax = ly * ((oy > 0) and 1 or -1), lx, mn[2], mx[2], mn[1], mx[1]
        if oy < 0 then amin, amax = -mx[2], -mn[2] end
    else
        along, across, amin, amax, cmin, cmax = lx * ((ox > 0) and 1 or -1), ly, mn[1], mx[1], mn[2], mx[2]
        if ox < 0 then amin, amax = -mx[1], -mn[1] end
    end
    if across < cmin - BOMP_R or across > cmax + BOMP_R then return end
    -- (only from in front of its tip: beside it - along its length - he was taken out to the tip, up to 3 m, and thrown
    -- off from there: "got sucked into the bump from the wall bumper", 2026-10-30. 30 cm covers a frame of its shooting
    -- out, 22 at most; a bar sliding by beside him is the box's side to keep_out_box, as in Mario 64)
    if along < amax - 30.0 or along > amax + BOMP_R + 25.0 then return end
    local move = amax + BOMP_R - along
    if move > 0.0 then
        pcall(function()
            pawn:K2_SetActorLocation({ X = l.X + dx * move, Y = l.Y + dy * move, Z = l.Z }, false, {}, true)
        end)
        if G and G.reset_cloth then pcall(G.reset_cloth, pawn) end
    end
    p.bumped = true
    if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
    pcall(function()
        local cm = pawn.CharacterMovement
        cm:SetMovementMode(3, 0)
        cm.Velocity = { X = dx * BOMP_BUMP, Y = dy * BOMP_BUMP, Z = BOMP_UP }
    end)
    p.cloth_at = os.clock() + 0.25
    local SFX = package.loaded["sfx"]
    if SFX then pcall(SFX.play, "en_bonk", 1.0) end
    log("a clock bar bumped him (%.0f cm in front of its tip, %.0f beside it, moved %.0f)", along - amax,
        math.max(cmin - across, across - cmax, 0.0), math.max(move, 0.0))
end

-- bhvTTCMovingBar: a push block; it draws back, shoots out 250 with a spring, holds, slides back in, waits
B.ttc_bar = {
    init = function(p)
        p.delay, p.stopped = ({ 55, 30, 55, 0 })[TTC.sp() + 1], 10 * p.b2
        p.myaw = s16(0x4000 - p.yaw)
        p.off, p.spd = 0.0, 0.0
        if p.delay == 0 then p.off = 250.0 end              -- (stopped: stuck out)
    end,
    step = function(p)
        local start = p.off
        p.off = p.off + p.spd
        local a = p.action
        if a == 0 then
            if p.delay ~= 0 and p.timer > p.delay then
                if p.stopped ~= 0 then
                    p.stopped = p.stopped - 1
                else
                    if TTC.sp() == 2 then
                        p.delay = ({ 1, 12, 55, 100 })[(TTC.r16() & 3) + 1]
                        if TTC.r16() % 2 == 0 then p.stopped = TTC.lin(20, 100) end      -- (a pause once drawn back)
                    end
                    p.action, p.spd = 1, -8.0
                end
            end
        elseif a == 1 then
            p.spd = p.spd + 0.73
            if p.spd > 0.0 then
                if p.stopped ~= 0 then p.stopped, p.spd = p.stopped - 1, 0.0 else p.action, p.spd = 2, 29.0 end
            end
        elseif a == 2 then
            if (p.off == 250.0 or (250.0 - p.off) * (250.0 - start) < 0.0) and p.spd > -8.0 and p.spd < 8.0 then
                p.action, p.spd = 3, 0.0
            else
                local acc = (p.off < 250.0) and 6.4 or -6.4
                if p.spd * acc < 0.0 then acc = acc * 2.35 end
                p.spd = p.spd + acc
                -- (random: past its rest point, one time in four it stops dead - a feint)
                if TTC.sp() == 2 and p.off * start < 0.0 and TTC.r16() % 4 == 0 then p.off, p.spd, p.action = 0.0, 0.0, 0 end
            end
        else
            if p.timer > 30 then
                p.spd = -5.0
                if p.off < 0.0 then p.off, p.spd, p.action = 0.0, 0.0, 0 end
            end
        end
        p.x = p.hx + p.off * coss(p.myaw)
        p.z = p.hz + p.off * sins(p.myaw)
        keep_out_box(p)
        ttc_bar_bump(p)
    end,
}

-- bhvTTCCog: hexagons and triangles turning steadily
B.ttc_cog = {
    init = function(p) p.dir, p.cspd, p.ctarget = ((p.b2 & 1) == 0) and 1 or -1, 0.0, 0.0 end,
    step = function(p)
        local sp = TTC.sp()
        if sp == 0 or sp == 1 then
            p.cspd = ({ 200.0, 400.0 })[sp + 1]
        elseif sp == 2 then
            local v, got = TTC.approach(p.cspd, p.ctarget, 50.0)
            p.cspd = v
            if got then p.ctarget = 200.0 * (TTC.r16() % 7) * TTC.sign() end
        end
        p.yaw = s16(p.yaw + floor(p.cspd * p.dir))
    end,
}

-- bhvTTCSpinner: the flipping bars, turning over and over
-- bhvTTCSpinner: the flat bars that spin end over end (the red coins' ones at the bottom), at half Mario 64's 200 / 600
-- a frame ("make the red coin platforms spin 50% slower", 2026-10-30)
B.ttc_spinner = {
    init = function(p) p.sdir, p.cdt = 0, 0 end,
    step = function(p)
        local av = ({ 100, 300, 100, 0 })[TTC.sp() + 1]
        if TTC.sp() == 2 then
            -- (a new way round now and then, still for 5 frames first)
            if p.timer > p.cdt then
                p.sdir, p.cdt, p.timer = TTC.sign(), TTC.mod(30, 30, 4), 0
            elseif p.timer > 5 then
                av = av * p.sdir
            else
                av = 0
            end
        end
        p.pitch = s16(p.pitch + av)
    end,
}

-- bhvTTC2DRotator: the clock's hands tick round 6 degrees at a time; the gears 18
B.ttc_rotator = {
    init = function(p)
        p.wait = ((p.b2 == 0) and { 40, 10, 10, 0 } or { 20, 5, 5, 0 })[TTC.sp() + 1]
        p.speed = (p.b2 == 0) and -0x444 or -0xCCC
        p.inc, p.rdt = p.speed, 0
        p.target, p.yaw = 0, s16(p.yaw)
    end,
    step = function(p)
        if p.rdt ~= 0 then p.rdt = p.rdt - 1 end
        if p.wait == 0 then return end                  -- (stopped)
        p.yaw = approach_s16(p.yaw, p.target, 0xC8)
        if p.yaw == s16(p.target) and p.timer > p.wait then
            p.target = s16(p.target + p.inc)
            p.timer = 0
            if TTC.sp() == 2 then
                -- (now and then the other way round for a while)
                if p.rdt == 0 then
                    if TTC.r16() & 3 ~= 0 then p.inc, p.rdt = p.speed, TTC.mod(90, 60, 4)
                    else p.inc, p.rdt = -p.speed, TTC.mod(30, 30, 3) end
                end
                p.wait = TTC.mod(10, 20, 3)
            end
        end
    end,
}

-- A pit block coming down on him squishes him, as a Thwomp does: squish.lua presses him flat under it, holds him while
-- it sits on him and lets him up once it lifts. It came down through him and left him standing inside it ("got stuck
-- in block instead of being squished by it", 2026-10-30). Him under its square - his middle, as Mario 64 looks for a
-- ceiling at Mario's own point, and 25 cm round it for his capsule's edge - with its underside between his feet and
-- over his head. (Not put out of its side when inside it: its side is a drop - it threw him off, 2026-10-30.)
local function pit_crush(p, m)
    local SQ = squish()
    if not SQ or SQ.active() or not p.actor then return end
    local pawn = lib.pawn()
    if not pawn then return end
    KMathL = KMathL or StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    local mn, mx = box_bounds(p)
    local over = nil
    pcall(function()
        local l = KMathL:InverseTransformLocation(p.actor:GetTransform(), pawn:K2_GetActorLocation())
        if l.X < mn[1] - 25.0 or l.X > mx[1] + 25.0 or l.Y < mn[2] - 25.0 or l.Y > mx[2] + 25.0 then return end
        local G = package.loaded["game"]
        local o = mn[3] - (l.Z - ((G and G.half) or 90.0))
        if o > -20.0 and o < 196.0 then over = o end
    end)
    if not over then return end
    if SQ.start(pawn, { bottom = function() return p.y * S + OFFSET.Z + mn[3] end,
                        floor = p.hy * S + OFFSET.Z + mn[3], grounded = m and m.ground, what = "a pit block" }) then
        log("a pit block came down on him (its underside %.0f cm over his feet)", over)
    end
end

-- bhvTTCPitBlock: rises 330 and sinks again, waiting at each end
B.ttc_pit = {
    init = function(p)
        p.peak, p.vy, p.dir, p.wait = p.y + 330.0, 0.0, 0, 0
        if TTC.sp() == 3 then p.y = p.peak end           -- (stopped: up)
    end,
    step = function(p, m)
        local down = p.timer > p.wait and p.vy < 0.0
        if p.timer > p.wait then
            p.y = p.y + p.vy
            local hit = false
            if p.y <= p.hy then p.y, hit = p.hy, true elseif p.y >= p.peak then p.y, hit = p.peak, true end
            if hit then
                p.dir = 1 - p.dir
                local pr = ({ { { 11, 20 }, { -9, 30 } }, { { 18, 15 }, { -11, 15 } }, { { 11, 20 }, { -9, -1 } },
                              { { 0, 0 }, { 0, 0 } } })[TTC.sp() + 1][p.dir + 1]
                p.vy, p.wait = pr[1], pr[2]
                if p.wait < 0 then p.wait = TTC.mod(10, 20, 6) end
                p.timer = 0
            end
        end
        if down then pit_crush(p, m) end
    end,
}

-- bhvTTCElevator: up and down between its place and 100 x its parameter higher (500 without one)
-- (Frozen, Mario 64 leaves it at the bottom, and Mario gets up past it with wall kicks the athlete has not: "no way up
-- here in forzen clock setting", 2026-10-30. Frozen, it carries him up while he stands on it - at the slow setting's
-- speed - and goes back down once he is off it.)
B.ttc_elevator = {
    init = function(p) p.peak, p.dir, p.mt = p.y + ((p.w ~= 0) and 100.0 * p.w or 500.0), 1, 0 end,
    step = function(p, m)
        local vy = ({ 6.0, 10.0, 6.0, 0.0 })[TTC.sp() + 1] * p.dir
        if TTC.sp() == 3 then
            vy = (m and m.plat == p) and 6.0 or -6.0
            if (vy > 0.0 and p.y >= p.peak) or (vy < 0.0 and p.y <= p.hy) then vy = 0.0 end
            p.moving = vy ~= 0.0
        elseif TTC.sp() == 2 then
            -- (now and then still for 5 frames, then off either way)
            if p.timer > p.mt then
                p.dir, p.mt, p.timer = TTC.sign(), TTC.mod(30, 30, 6), 0
            elseif p.timer < 5 then
                vy = 0.0
            end
        end
        p.y = p.y + vy
        if p.y <= p.hy then p.y, p.dir = p.hy, -p.dir elseif p.y >= p.peak then p.y, p.dir = p.peak, -p.dir end
    end,
    hum = function(p) return (TTC.sp() ~= 3 or p.moving) and "loop_elevator1" or nil, 1500.0 end,
}

-- bhvWoodenPost: the chain chomp's post (chomp.lua makes it). Each drop kick (`p.kick`, where he kicked from, set by
-- chomp.lua) leans it as the free posts (B.wpost); the third knocks it out, and the chomp is let go (`p.released`).
B.post = {
    init = function(p) P.want_kick = true; post_init(p) end,
    step = function(p, m)
        post_kick_check(p, m)
        post_step(p)
        if p.kicks >= 3 and not p.released then p.released = true end
    end,
}

-- bhvSquarishPathMoving: round a square, one side at a time
B.squarish = {
    step = function(p)
        if p.action == 0 then
            p.action = (p.b2 & 3) + 1
        else
            p.myaw = (p.action - 1) * 0x4000
            if p.timer > 60 then p.action = p.action % 4 + 1 end
        end
        p.x = p.x + 10.0 * sins(p.myaw)
        p.z = p.z + 10.0 * coss(p.myaw)
    end,
}

-- bhvSeesawPlatform: tips toward whichever end is stood on, swings back level when left alone; it creaks while
-- it swings
B.seesaw = {
    init = function(p) p.pvel = 0.0 end,
    hum = function(p) return abs(p.pvel) > 10.0 and "loop_seesaw" or nil end,
    step = function(p, m)
        p.pitch = p.pitch + trunc(p.pvel)
        if m.plat == p then
            local dx, dy, dz = m.x - p.x, m.y - p.y, m.z - p.z
            local rot = sqrt(dx * dx + dy * dy + dz * dz) * coss(atan2s(dz, dx) - p.myaw)
            if p.pvel * rot < 0 then rot = rot * 0.04 else rot = rot * 0.02 end
            p.pvel = clampf(p.pvel + rot, -50.0, 50.0)
        else
            p.pitch, p.pvel = oscillate_toward(p.pitch, p.pvel, 0, 6.0, 3.0, 3.0)
        end
        -- Mario slides off at 38 degrees (a plain floor's slope limit, normal 0.788); the athlete does not, so the tilt stops
        -- there - still a floor to him (STORROR walks up to 60). Stopped at 67.5 under him he stood on a wall, carried
        -- with it, and could not move: "players stuck", 2026-10-25. Past it (as it was), eased back.
        local cap = 0x1B00
        if p.pitch > cap then p.pitch, p.pvel = math.max(cap, p.pitch - 0x100), 0.0
        elseif p.pitch < -cap then p.pitch, p.pvel = math.min(-cap, p.pitch + 0x100), 0.0 end
    end,
}

-- bhvSlidingPlatform2: back and forth along its facing (or up and down), pausing at each end
B.slide2 = {
    init = function(p)
        local idx = (p.w & 0x0380) >> 7
        p.len = 50.0 * (p.w & 0x3F)
        p.dist, p.dir = 0.0, 0.0
        if idx < 5 or idx > 6 then
            p.vel = 15.0
            if (p.w & 0x40) ~= 0 then p.myaw = p.myaw + 0x8000 end
        else
            p.vel = 10.0
            p.dir = ((p.w & 0x40) ~= 0) and -1.0 or 1.0
        end
    end,
    step = function(p)
        if p.timer > 10 then
            local hit
            p.dist, hit = clampf(p.dist + p.vel, -p.len, 0.0)
            if hit then
                p.vel = -p.vel
                p.timer = 0
            end
        end
        if p.dir ~= 0.0 then
            p.y = p.hy + p.dist * p.dir
        else
            p.x = p.hx + p.dist * coss(p.myaw)
            p.z = p.hz + p.dist * sins(p.myaw)
        end
    end,
}

-- WF's spinning islands: an unseen bar all round their top edge, 6 cm out, for STORROR's own grab and swing - his
-- hands on the island's edge, carried round as it turns ("now replace the 3 islands with our new and improved
-- island", 2026-10-17). STORROR's ledge grab takes nothing that moves, but it swings on any bar thinner than its
-- SwingingBarWidth (30 cm). Its own actor, fixed to the island's.
local RING_OUT, RING_R, RING_DOWN, RING_SIDES = 6.0, 4.0, 5.0, 10
local function ring_bar(p, world)
    local c = p.tpl and p.tpl.collision and p.tpl.collision.pos
    if not (c and p.actor) then return end
    -- (the top's outline, in the island's frame)
    local zmax = -1e9
    for i = 3, #c, 3 do if c[i] > zmax then zmax = c[i] end end
    local pts, sx, sy = {}, 0.0, 0.0
    for i = 1, #c, 3 do
        if c[i + 2] > zmax - 1.0 then
            local dup = false
            for _, q in ipairs(pts) do if abs(q[1] - c[i]) < 1.0 and abs(q[2] - c[i + 1]) < 1.0 then dup = true end end
            if not dup then pts[#pts + 1] = { c[i], c[i + 1] }; sx, sy = sx + c[i], sy + c[i + 1] end
        end
    end
    local n = #pts
    if n < 3 then return end
    local cx, cy = sx / n, sy / n
    table.sort(pts, function(a, b) return atan(a[2] - cy, a[1] - cx) < atan(b[2] - cy, b[1] - cx) end)
    -- (each corner pushed out RING_OUT from both its edges)
    local function out_normal(u, v)
        local ex, ey = v[1] - u[1], v[2] - u[2]
        local l = sqrt(ex * ex + ey * ey)
        local nx, ny = ey / l, -ex / l
        if nx * (u[1] - cx) + ny * (u[2] - cy) < 0 then nx, ny = -nx, -ny end
        return nx, ny
    end
    local ring = {}
    for i = 1, n do
        local a, b, d = pts[(i - 2) % n + 1], pts[i], pts[i % n + 1]
        local n1x, n1y = out_normal(a, b)
        local n2x, n2y = out_normal(b, d)
        local bx, by = n1x + n2x, n1y + n2y
        local bl = sqrt(bx * bx + by * by)
        bx, by = bx / bl, by / bl
        local k = RING_OUT / (bx * n1x + by * n1y)
        ring[i] = { b[1] + bx * k, b[2] + by * k }
    end
    local actor = lib.spawn_actor(world, p.actor:K2_GetActorLocation(), 0.0)
    local pmc = actor and lib.add_pmc(actor)
    if not pmc then if actor then lib.destroy(actor) end; return end
    local z, coll = zmax - RING_DOWN, {}
    for i = 1, n do
        local a, b = ring[i], ring[i % n + 1]
        local ex, ey = b[1] - a[1], b[2] - a[2]
        local len = sqrt(ex * ex + ey * ey)
        local px, py = -ey / len, ex / len
        local pos, idx = {}, {}
        for j = 0, RING_SIDES - 1 do
            local an = j * 2 * pi / RING_SIDES
            for _, e in ipairs({ a, b }) do
                pos[#pos + 1] = e[1] + px * RING_R * cos(an); pos[#pos + 1] = e[2] + py * RING_R * cos(an)
                pos[#pos + 1] = z + RING_R * sin(an)
            end
        end
        for j = 0, RING_SIDES - 1 do
            local a0, a1 = j * 2, ((j + 1) % RING_SIDES) * 2
            for _, t in ipairs({ { a0, a1, a0 + 1 }, { a1, a1 + 1, a0 + 1 }, { a0, a0 + 1, a1 }, { a1, a0 + 1, a1 + 1 } }) do
                idx[#idx + 1] = t[1]; idx[#idx + 1] = t[2]; idx[#idx + 1] = t[3]
            end
        end
        coll[#coll + 1] = { source = "island ring " .. i, pos = pos, idx = idx }
    end
    lib.add_collision(pmc, coll)
    -- (his body parts - physics-simulated, object channel 17 - pass through, as with the tree trunks)
    pcall(function() pmc:SetCollisionResponseToChannel(17, 0) end)
    pcall(function() actor:K2_AttachToActor(p.actor, FName("None"), 2, 2, 2, false) end)
    p.ring = actor
    local rmax = 0.0
    for _, q in ipairs(ring) do rmax = math.max(rmax, sqrt(q[1] * q[1] + q[2] * q[2])) end
    p.ring_r, p.ring_z = rmax, zmax
end

-- Standing on an island's ring (STORROR stands on bars too) he turns with the island, as on its top: the engine
-- carries him round on it, but nothing turned him ("no when standing on the bar", 2026-10-17)
local function on_ring(grounded)
    if not grounded then return nil end
    local pawn = lib.pawn()
    if not pawn then return nil end
    local l = pawn:K2_GetActorLocation()
    local half = 88.0
    pcall(function() half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight() end)
    for _, p in ipairs(P.list) do
        if p.ring and p.ring_r and p.actor then
            local c = p.actor:K2_GetActorLocation()
            local d = sqrt((l.X - c.X) ^ 2 + (l.Y - c.Y) ^ 2)
            local top = c.Z + p.ring_z - RING_DOWN + RING_R
            if d > p.ring_r * 0.95 - 40.0 and d < p.ring_r + 40.0 and abs(l.Z - half - top) < 30.0 then return p end
        end
    end
    return nil
end

-- bhvOctagonalPlatformRotating, bhvRotatingPlatform: turning at a steady rate
B.spin = {
    init = function(p, world)
        p.avel = p.o.avel or 0
        if world and tostring(p.o.tpl or ""):find("wf_seg7_collision_rotating_platform", 1, true) then
            local ok, err = pcall(ring_bar, p, world)
            if not ok then log("island ring: %s", tostring(err)) end
        end
    end,
    step = function(p) p.yaw = p.yaw + p.avel end,
}

-- bhvWFRotatingWoodenPlatform: waits two seconds, turns half way round (humming), waits again
B.wf_wood = {
    hum = function(p) return p.action == 1 and "loop_elevator2" or nil end,
    step = function(p)
        local avel = 0
        if p.action == 0 then
            if p.timer > 60 then p.action = 1 end
        else
            avel = 0x100
            if p.timer > 126 then p.action = 0 end
        end
        p.yaw = p.yaw + avel
    end,
}

-- bhvFerrisWheelAxle and its four platforms, which stay level as the wheel carries them round
B.ferris_seat = {
    step = function(p)
        local q = p.parent
        local a = q.roll + p.i * 0x4000
        local off = 400.0 * coss(a)
        p.x = q.x + off * sins(q.myaw) + 300.0 * coss(q.myaw)
        p.y = q.y + 400.0 * sins(a)
        p.z = q.z + off * coss(q.myaw) + 300.0 * sins(q.myaw)
    end,
}
B.ferris = {
    init = function(p, world, templates)
        p.myaw = p.myaw + 0x4000
        p.seats = {}
        for i = 0, 3 do
            local c = make(world, templates, p.o.tpl2, p.x, p.y, p.z, p.o.ang)
            if c then
                c.def, c.parent, c.i = B.ferris_seat, p, i
                B.ferris_seat.step(c)
                p.seats[#p.seats + 1] = c
            end
        end
    end,
    after = function(p) for _, c in ipairs(p.seats) do enlist(c) end end,      -- seats step after their wheel
    step = function(p) p.roll = p.roll + 400 end,
}

-- Rainbow Ride's magic carpets (rr_geo_000848): Mario 64 makes the carpet's cloth as it draws it (geo_misc.c
-- geo_exec_flying_carpet_create) - 21 points in 7 rows of 3 (flying_carpet_static_vertex_data: x, z, and the picture's
-- place), a ripple 20 high running down it, the quarter carpet picture mirrored over it, both sides drawn - so nothing
-- of it was exported: only its floor, unseen ("no magic carpet", 2026-10-30). Made here as Mario 64 makes it, its ripple
-- stepped 0x400 a frame (geo_exec_flying_carpet_timer_update).
local CARPET = {
    -306, 205, 0, 0,     -306, 0, 992, 0,     -306, -204, 0, 0,
    -204, 205, 0, 308,   -204, 0, 992, 308,   -204, -204, 0, 308,
    -102, 205, 0, 650,   -102, 0, 992, 650,   -102, -204, 0, 650,
    0, 205, 0, 992,      0, 0, 992, 992,      0, -204, 0, 992,
    102, 205, 0, 650,    102, 0, 992, 650,    102, -204, 0, 650,
    205, 205, 0, 308,    205, 0, 992, 308,    205, -204, 0, 308,
    307, 205, 0, 0,      307, 0, 990, 0,      307, -204, 0, 0,
}
local CARPET_TEX = "levels__rr__quarter_flying_carpet.rgba16"
local function carpet_points(t)
    local verts = {}
    for n = 0, 20 do
        local row, col = n // 3, n % 3
        local x, z = CARPET[n * 4 + 1], CARPET[n * 4 + 2]
        local y = math.floor(sins(t + (row << 12) + (col << 14)) * 20.0 + 0.5)
        verts[n + 1] = { X = -z * S, Y = x * S, Z = y * S }
    end
    return verts
end
local function carpet_make(p, world)
    local top, bot, uvs, cols, nu, nd = {}, {}, {}, {}, {}, {}
    for r = 0, 5 do
        for c = 0, 1 do
            local a = r * 3 + c                 -- (dl_flying_carpet_model_half: a, a+1, a+3 and a+3, a+1, a+4)
            for _, i in ipairs({ a, a + 1, a + 3, a + 3, a + 1, a + 4 }) do top[#top + 1] = i end
            for _, i in ipairs({ a, a + 3, a + 1, a + 3, a + 4, a + 1 }) do bot[#bot + 1] = i end
        end
    end
    for n = 0, 20 do
        uvs[n + 1] = { X = CARPET[n * 4 + 3] / 1024.0, Y = CARPET[n * 4 + 4] / 1024.0 }
        cols[n + 1] = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
        nu[n + 1], nd[n + 1] = { X = 0.0, Y = 0.0, Z = 1.0 }, { X = 0.0, Y = 0.0, Z = -1.0 }
    end
    local v = carpet_points(0)
    lib.create_section(p.pmc, 0, v, top, nu, uvs, cols, false)
    lib.create_section(p.pmc, 1, v, bot, nd, uvs, cols, false)
    local mid = lib.get_mid(world, "opaque", CARPET_TEX)
    if mid then pcall(function() p.pmc:SetMaterial(0, mid); p.pmc:SetMaterial(1, mid) end) end
    p.carpet = { uvs = uvs, cols = cols, t = -1 }
end
-- The carpet's poles ("also add poles along the edge of the carpet", 2026-10-31): a bar all round its edge, as WF's
-- islands have (ring_bar) - STORROR's ledge grab takes nothing that moves, so the carpet's edges were never held; it
-- swings on any bar thinner than 30 cm, carried with it. Unseen, as the islands' ("pole should be invisable",
-- 2026-10-31 - it was drawn in the carpet's gold at first); its own actor, fixed to the carpet's (gone with it: p.ring).
local CBAR_OUT, CBAR_R, CBAR_DOWN, CBAR_SIDES = 6.0, 4.0, 5.0, 10
local function carpet_bar(p, world)
    local c = p.tpl and p.tpl.collision and p.tpl.collision.pos
    if not (c and p.actor and world) then return end
    local x0, x1, y0, y1, zt = 1e9, -1e9, 1e9, -1e9, -1e9
    for i = 1, #c, 3 do
        x0, x1 = math.min(x0, c[i]), math.max(x1, c[i])
        y0, y1 = math.min(y0, c[i + 1]), math.max(y1, c[i + 1])
        zt = math.max(zt, c[i + 2])
    end
    x0, x1, y0, y1 = x0 - CBAR_OUT, x1 + CBAR_OUT, y0 - CBAR_OUT, y1 + CBAR_OUT
    local z = zt - CBAR_DOWN
    local corners = { { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 } }
    local actor = lib.spawn_actor(world, p.actor:K2_GetActorLocation(), 0.0)
    local pmc = actor and lib.add_pmc(actor)
    if not pmc then if actor then lib.destroy(actor) end; return end
    local coll = {}
    for i = 1, 4 do
        local a, b = corners[i], corners[i % 4 + 1]
        local ex, ey = b[1] - a[1], b[2] - a[2]
        local len = sqrt(ex * ex + ey * ey)
        local ux, uy = ex / len, ey / len
        local A, Bq = { a[1] - ux * CBAR_R, a[2] - uy * CBAR_R }, { b[1] + ux * CBAR_R, b[2] + uy * CBAR_R }   -- (closed at the corners)
        local px, py = -uy, ux
        local pos, idx = {}, {}
        for j = 0, CBAR_SIDES - 1 do
            local an = j * 2 * pi / CBAR_SIDES
            local ox, oy, oz = px * cos(an), py * cos(an), sin(an)
            for _, e in ipairs({ A, Bq }) do
                pos[#pos + 1], pos[#pos + 2], pos[#pos + 3] = e[1] + ox * CBAR_R, e[2] + oy * CBAR_R, z + oz * CBAR_R
            end
        end
        for j = 0, CBAR_SIDES - 1 do
            local a0, a1 = j * 2, ((j + 1) % CBAR_SIDES) * 2
            for _, t in ipairs({ { a0, a1, a0 + 1 }, { a1, a1 + 1, a0 + 1 }, { a0, a0 + 1, a1 }, { a1, a0 + 1, a1 + 1 } }) do
                idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = t[1], t[2], t[3]
            end
        end
        coll[#coll + 1] = { source = "carpet pole " .. i, pos = pos, idx = idx }
    end
    lib.add_collision(pmc, coll)
    pcall(function() pmc:SetCollisionResponseToChannel(17, 0) end)       -- (his loose body parts pass, as the trunks)
    pcall(function() actor:K2_AttachToActor(p.actor, FName("None"), 2, 2, 2, false) end)
    p.ring = actor
end
-- Him with the carpet, not stood on it - hanging from its poles, swinging round them, stood on them, a jump up off it,
-- down on it in a fall: whether that is near enough to be riding it, and (x, y, z) his feet in its own frame. Only stood
-- on it counted: hanging from its edge it took him for gone, blinked and went back to its start from under him -
-- "carpet disappeared even though I was on it", 2026-10-31.
local function carpet_near(p, m)
    local a = p.ax
    if not (a and p.wx and m) then return false end
    local dx, dy, dz = -m.z * S - p.wx, m.x * S - p.wy, m.y * S - p.wz
    local lx = dx * a[1] + dy * a[2] + dz * a[3]
    local ly = dx * a[4] + dy * a[5] + dz * a[6]
    local lz = dx * a[7] + dy * a[8] + dz * a[9]
    local mn, mx = box_bounds(p)
    return lx > mn[1] - 200.0 and lx < mx[1] + 200.0 and ly > mn[2] - 200.0 and ly < mx[2] + 200.0
        and lz > mn[3] - 300.0 and lz < mx[3] + 300.0, lx, ly, lz
end
local function carpet_ripple(p)
    local t = (math.floor(os.clock() * 30.0) * 0x400) % 0x10000
    if t == p.carpet.t then return end
    p.carpet.t = t
    local v = carpet_points(t)
    pcall(lib.update_section, p.pmc, 0, v, p.carpet.cols, p.carpet.uvs)
    pcall(lib.update_section, p.pmc, 1, v, p.carpet.cols, p.carpet.uvs)
end

-- bhvPlatformOnTrack: waits for a rider, then follows its line of waypoints
local function track_advance(p)
    local wps, first = p.path, p.prev_i
    local ni, pi = first, first
    p.prev_flags = 0
    local amount = p.fvel
    local x, y, z = p.x, p.y, p.z
    local dx, dy, dz, d = 0.0, 0.0, 0.0, 0.0
    repeat
        pi = ni
        ni = ni + 1
        if wps[ni][1] == -1 then
            p.prev_flags = -1
            if p.ret then ni = 1 else return end
        end
        dx, dy, dz = wps[ni][2] - x, wps[ni][3] - y, wps[ni][4] - z
        d = sqrt(dx * dx + dy * dy + dz * dz)
        amount = amount - d
        x, y, z = x + dx, y + dy, z + dz
    until amount <= 0.0
    if d > 1e-6 then
        local k = amount / d
        x, y, z = x + dx * k, y + dy * k, z + dz * k
    end
    if pi ~= first then
        if p.prev_flags == 0 then p.prev_flags = wps[first][1] end
        p.prev_i = pi
    end
    p.vx, p.vy, p.vz = x - p.x, y - p.y, z - p.z
    p.x, p.y, p.z = x, y, z
    p.tpitch = atan2s(sqrt(p.vx * p.vx + p.vz * p.vz), -p.vy)
    p.tyaw = atan2s(p.vz, p.vx)
end

B.track = {
    -- (the ski lift hums while it goes, Hazy Maze Cave's lift, path 4, as the lifts do; the others go quietly)
    hum = function(p)
        if p.action ~= 2 then return nil end
        if p.ski then return "loop_elevator3" end
        if (p.w & 0xF) == 4 then return "loop_elevator1" end
        return nil
    end,
    init = function(p, world)
        p.path = p.o.path
        p.ski = (p.o.ptype == 1)
        p.ret = (p.w & 0x0100) ~= 0             -- at the end of the line, go back to the start
        p.stay = (p.w & 0x0200) ~= 0            -- do not go back to the start when left alone
        p.no_yaw = (p.w & 0x0400) ~= 0
        p.turn_roll = (p.w & 0x0800) ~= 0
        p.yaw0 = p.yaw
        p.rollvel, p.fvel, p.vx, p.vy, p.vz = 0.0, 0.0, 0.0, 0.0, 0.0
        p.prev_i, p.prev_flags = 1, 0
        local s = p.path[1]
        p.x, p.y, p.z = s[2], s[3], s[4]
        p.action = 1
        if p.pmc and tostring(p.o.tpl):find("rr_geo_000848", 1, true) then pcall(carpet_make, p, world) end
        if p.carpet then
            local okb, errb = pcall(carpet_bar, p, world)
            if not okb then log("carpet poles: %s", tostring(errb)) end
        end
    end,
    changed = function(p, was)
        if not p.carpet then return end
        local what = ({ [0] = "back to its start", [2] = "off along its line", [4] = "at the end of its line, falling" })[p.action]
        if what then log("carpet %d: %s", p.o.bp or 0, what) end
    end,
    step = function(p, m)
        if p.carpet then carpet_ripple(p) end
        local on = (m.plat == p)
        -- (held on to, a carpet - see carpet_near - is not left alone; it still sets off only for him stood on it)
        local held, hx, hy, hz = on, nil, nil, nil
        if not on and p.carpet then held, hx, hy, hz = carpet_near(p, m) end
        local act = p.action
        if act == 0 then
            p.prev_i, p.prev_flags = 1, 0
            local s = p.path[1]
            p.x, p.y, p.z = s[2], s[3], s[4]
            p.hx, p.hy, p.hz = p.x, p.y, p.z
            p.yaw = p.yaw0
            p.fvel, p.vx, p.vy, p.vz = 0.0, 0.0, 0.0, 0.0
            if not p.ski then p.roll = 0 end
            p.jump = true                       -- a jump back to the start is not to be blended
            p.action = 1
        elseif act == 1 then
            if on then
                if p.timer > 20 then p.action = 2 end
            else
                p.timer = 0
            end
        elseif act == 2 then
            if p.prev_flags == -1 and not p.ret then
                p.action = 4
            else
                if p.prev_flags ~= 0 and p.ski then
                    if p.prev_flags == -1 or p.prev_flags == 3 then
                        p.shot = "ski_lift_stop"
                        p.fvel = 0.0
                        p.action = (p.prev_flags == -1) and 0 or 3
                    end
                elseif p.ski then
                    p.fvel = approach(p.fvel, 10.0, 0.1)
                else
                    p.fvel = 10.0
                end
                track_advance(p)
                if p.tyaw then
                    p.mpitch, p.myaw = p.tpitch, p.tyaw
                    if not p.no_yaw then
                        local target = p.myaw + 0x4000
                        local speed = clampf(abs(s16(target - p.yaw)) / 20, 100, 500)
                        p.yaw = approach_angle(p.yaw, target, speed)
                    end
                    if p.turn_roll then
                        local speed = clampf(abs(s16(p.mpitch - p.roll)) / 20, 100, 500)
                        p.roll = approach_angle(p.roll, p.mpitch, speed)
                    end
                end
            end
            if held then p.timer = 0 elseif not p.stay and p.timer > 230 then p.action = 0 end
        elseif act == 3 then
            if p.timer > 20 then p.action = 2 end
        elseif act == 4 then
            p.x, p.z = p.x + p.vx, p.z + p.vz
            p.vy = p.vy - 1.0
            p.y = p.y + p.vy
            if held then p.timer = 0 elseif p.timer > 230 then p.action = 0 end
        end
        -- (left alone on its way, it blinks its last 80 frames before it goes back to its start - every other frame unseen,
        -- cur_obj_wait_then_blink(150, 40): "carpet should blink before it disappears", 2026-10-30)
        local blink = (p.action == 2 or p.action == 4) and not held and not p.stay and p.timer >= 150
        if blink and p.timer == 150 and p.carpet then
            log("carpet %d: left alone 5 s, blinking (his feet %s from it; on %s)", p.o.bp or 0,
                hx and string.format("%.0f %.0f %.0f", hx, hy, hz) or "far", m.plat and tostring(m.plat.o.bhv) or (m.ground and "the ground" or "nothing"))
        end
        local hide = blink and ((p.timer - 150) % 2 == 1)
        if hide ~= (p.blink_hidden or false) then
            p.blink_hidden = hide
            pcall(function() p.actor:SetActorHiddenInGame(hide) end)
            if p.ring then pcall(function() p.ring:SetActorHiddenInGame(hide) end) end
        end
        if p.ski then
            p.roll = p.roll + trunc(p.rollvel)
            local target = 0
            if on then
                local dx, dy, dz = m.x - p.x, m.y - p.y, m.z - p.z
                target = trunc(p.fvel * sins(p.myaw) * -50.0)
                    + trunc(sqrt(dx * dx + dy * dy + dz * dz) * sins(atan2s(dz, dx) - p.yaw) * -4.0)
            end
            p.roll, p.rollvel = oscillate_toward(p.roll, p.rollvel, target, 5.0, 6.0, 1.5)
            p.rollvel = clampf(p.rollvel, -100.0, 100.0)
        end
    end,
}

-- bhvCheckerboardElevatorGroup: two platforms that rise and sink in turn and swing over to change sides
local CHECKER = { [0] = { 145, { 0.7, 1.5, 0.7 }, 7.0 }, [1] = { 235, { 1.2, 2.0, 1.2 }, 11.6 } }
B.checker_sub = {
    hum = function(p) return "loop_elevator4", 1000.0 end,      -- (always, within 1000 units, as Mario 64's)
    step = function(p)
        local act, flag = p.action, 0
        if act == 0 then
            p.action = (p.b2 == 0) and 1 or 3
        elseif act == 1 or act == 3 then
            p.mpitch, p.avelp, p.fvel = 0, 0, 0.0
            p.vy = (act == 1) and 10.0 or -10.0
            if p.timer > p.wait then p.action = act + 1 end
        else
            local nxt = (act == 2) and 3 or 1
            p.vy = 0.0
            p.avelp = (act == 2) and 512 or -512
            if p.timer + 1 == 0x8000 // 512 then p.action = nxt end
            flag = nxt
        end
        p.mpitch = p.mpitch + abs(p.avelp)
        p.pitch = p.pitch + abs(p.avelp)
        p.yaw = p.myaw
        if p.mpitch ~= 0 then
            local sgn = (p.avelp >= 0) and 1.0 or -1.0
            p.fvel = sgn * sins(p.mpitch) * p.arc
            p.vy = sgn * coss(p.mpitch) * p.arc
        end
        if flag == 1 then
            p.avelp = 0
            p.pitch = p.pitch & ~0x7FFF
        end
        p.x = p.x + p.fvel * sins(p.myaw)
        p.y = p.y + p.vy
        p.z = p.z + p.fvel * coss(p.myaw)
    end,
}
B.checker = {
    -- the object in the level is only the pair's centre: it makes the two platforms and is gone
    spawn = function(world, templates, o)
        local bp = o.bp or 0
        local b1, b2 = (bp >> 24) & 0xFF, (bp >> 16) & 0xFF
        if b2 == 0 then b2 = 65 end
        local D = CHECKER[b1] or CHECKER[0]
        local yaw = (o.ang and o.ang[2] or 0) * 65536.0 / 360.0
        for i = 0, 1 do
            local rz = (i == 0) and -D[1] or D[1]
            local c = make(world, templates, o.tpl, o.pos[1] + rz * sins(yaw), o.pos[2] + i * b2 * 10, o.pos[3] + rz * coss(yaw), o.ang, D[2])
            if c then
                c.def, c.b2, c.arc, c.wait = B.checker_sub, i, D[3], b2
                c.avelp, c.fvel, c.vy = 0, 0.0, 0.0
                enlist(c)
            end
        end
    end,
}

-- bhv_elevator_loop: the lifts that go when stood on (Hazy Maze Cave, Rainbow Ride, Big Boo's Haunt): a thud as
-- one sets off under the player, a hum while it goes, a clang as it arrives
B.elevator = {
    hum = function(p) return (p.action == 1 or p.action == 2) and "loop_elevator1" or nil end,
    changed = function(p, was, m)
        if (p.action == 1 or p.action == 2) and m.plat == p then p.shot = "lift_start"
        elseif p.action == 3 or p.action == 4 then p.shot = "lift_stop" end
    end,
    init = function(p)
        local o = p.o
        -- (BBH's mesh elevator: its behavior sets its own oBhvParams2ndByte to 4 - sElevatorHeights' -2360, down to the
        -- merry-go-round's basement; the exporter read its 0 (-51) and it only rose 154 over its pit, so he fell down the
        -- shaft, 2026-10-22)
        if o.tpl and o.tpl:find("mesh_elevator", 1, true) then o.low = -2360 end
        if (o.fixed or 0) == 0 then
            p.lo, p.hi = o.low or 0, p.hy
            p.kind = o.rr and 1 or 0
        else
            p.lo, p.hi = o.low or 0, o.high or 0
            p.kind = 2
        end
        p.mid = (p.lo + p.hi) / 2
        p.vy = 0.0
    end,
    step = function(p, m)
        local on, act = (m.plat == p), p.action
        if act == 0 then
            p.vy = 0.0
            if p.kind == 2 then
                if on then p.action = (p.y > p.mid) and 2 or 1 end
            elseif m.y > p.mid or p.kind == 1 then
                p.y = p.hi
                if on then p.action = 2 end
            else
                p.y = p.lo
                if on then p.action = 1 end
            end
        elseif act == 1 then
            p.vy = approach_signed(p.vy, 10.0, 2.0)
            p.y = p.y + p.vy
            if p.y > p.hi then
                p.y = p.hi
                if p.kind ~= 0 then p.action = 3
                elseif m.y < p.mid then p.action = 2
                else p.action = 3 end
            end
        elseif act == 2 then
            p.vy = approach_signed(p.vy, -10.0, -2.0)
            p.y = p.y + p.vy
            if p.y < p.lo then
                p.y = p.lo
                if p.kind == 1 then p.action = 4
                elseif p.kind == 2 then p.action = 3
                elseif m.y > p.mid then p.action = 1
                else p.action = 3 end
            end
        else
            p.vy = 0.0
            if m.ground and not on then p.action = (act == 3) and 0 or 1 end
        end
    end,
}

-- bhvActivatedBackAndForthPlatform: sets off when stood on, runs to the end of its line and back
B.bf = {
    init = function(p)
        local t = p.o.ptype or 0
        p.flip = (t == 0) and 0x8000 or 0
        p.max = 50.0 * (p.w & 0x7F)
        if t == 2 then p.max = p.max - 12.0 end
        p.vertical = (p.w & 0x80) ~= 0
        p.vel, p.off, p.count, p.vy = 0.0, 0.0, 0, 0.0
    end,
    step = function(p, m)
        p.vy = (m.plat == p) and -6.0 or 6.0
        if p.vel ~= 0.0 then
            if p.count ~= 0 then
                p.count = p.count - 1
            else
                local hit
                p.off, hit = clampf(p.off + p.vel, 0.0, p.max)
                if not hit and p.vel > 0.0 then
                    local dx, dy, dz = m.x - p.x, m.y - p.y, m.z - p.z
                    hit = dx * dx + dy * dy + dz * dz > 3000.0 * 3000.0
                end
                if hit then
                    p.count = 20
                    if p.vy < 0.0 or p.vel > 0.0 then p.vel = -p.vel else p.vel = 0.0 end
                    p.yaw = p.yaw + p.flip
                end
            end
        else
            if p.vy < 0.0 then p.vel = 10.0 end
            p.count = 20
        end
        if p.vertical then
            p.y = p.hy + p.off
        else
            p.y = clampf(p.y + p.vy, p.hy - 20.0, p.hy)
            p.x = p.hx - p.off * coss(p.myaw)
            p.z = p.hz - p.off * sins(p.myaw)
        end
    end,
}

P.behaviours = B

-- ------------------------------------------------------------ the scene's platforms
function P.add(world, o, templates)
    local def = B[o.bhv]
    if not def then return end
    if def.spawn then
        def.spawn(world, templates, o)
        return
    end
    local p = make(world, templates, o.tpl, o.pos[1], o.pos[2], o.pos[3], o.ang, o.scale)
    if not p then return end
    p.o, p.def, p.bp = o, def, o.bp or 0
    p.b1, p.b2, p.w = (p.bp >> 24) & 0xFF, (p.bp >> 16) & 0xFF, (p.bp >> 16) & 0xFFFF
    if def.init then def.init(p, world, templates) end
    -- (in a course turned and joined on to another - game.lua G.join_scenes - its way of moving turned to match)
    if o.move_turn then p.myaw = s16(p.myaw + floor(o.move_turn * 65536.0 / 360.0 + 0.5)) end
    enlist(p)
    if def.after then def.after(p) end
    return p
end

-- One platform taken away for good (the chain chomp's gate, smashed).
function P.remove(p)
    for i = #P.list, 1, -1 do
        if P.list[i] == p then table.remove(P.list, i) end
    end
    if P.on == p then P.on = nil end
    if p.ring then lib.destroy(p.ring); p.ring = nil end
    if p.actor then lib.destroy(p.actor) end
    p.actor = nil
end

local function sfx() return package.loaded["sfx"] end

function P.clear()
    if P.cut then
        local c = P.cut
        local w = lib.world()
        cut_end(c, w and w:GetAddress() == c.world)
        pcall(function() local pawn = lib.pawn(); if pawn then c.pc:SetViewTargetWithBlend(pawn, 0.0, 0, 0.0, false) end end)
    end
    barrel_view_end(0.0)
    do local SQ = squish(); if SQ then pcall(SQ.stop) end end
    P.want_kick, P.kick_at, P.attack_at, P.attacking, P.in_cannon = nil, nil, nil, nil, nil
    for k in pairs(traps) do traps[k] = nil end
    for k in pairs(chest_groups) do chest_groups[k] = nil end
    books, puzzle, P.ukiki_cage, P.bowser_arena, P.drain, P.cannon_flight, P.pancakes = nil, nil, nil, nil, nil, nil, nil
    local SFX = sfx()
    if SFX and SFX.quiet_held then pcall(SFX.quiet_held) end
    -- (and the purple switch's ticking - one long sound, played once as it is pressed, its 14 s heard on in the castle
    -- after a death or a star: "the ! switch audio transfers over to the castle if the player dies or collects a star",
    -- 2026-10-28)
    if SFX and SFX.stop then pcall(SFX.stop, "purple_ticks") end
    for _, p in ipairs(P.list) do
        if p.ring then lib.destroy(p.ring) end
        lib.destroy(p.actor)
        for _, q in ipairs(p.quads or {}) do if q then lib.destroy(q) end end
        if p.can then lib.destroy(p.can.base.actor); lib.destroy(p.can.barrel.actor) end
        if p.barrel then lib.destroy(p.barrel.actor) end
    end
    P.list, P.on = {}, nil
end

-- the map was swapped out underneath: the actors are already gone
function P.forget()
    do local SQ = squish(); if SQ then pcall(SQ.stop) end end
    P.list, P.on, P.in_cannon, P.cut, P.barrel_cam = {}, nil, nil, nil, nil
    scope_show(false)                           -- (only if it belongs to this map: scope_ok)
    for k in pairs(traps) do traps[k] = nil end
    for k in pairs(chest_groups) do chest_groups[k] = nil end
    books, puzzle, P.ukiki_cage, P.bowser_arena, P.drain, P.cannon_flight, P.pancakes = nil, nil, nil, nil, nil, nil, nil
end

-- Is (x, y, z) (scene cm) inside one of the platforms' collision - its box in its own frame, grown by r? (Bullet
-- Bill's walls: WF's tower and the blocks round it are platforms, not the level's walls, and it flew through them -
-- "still goin through walls", 2026-10-17)
local function coll_box(p)
    if p.cbox ~= nil then return p.cbox end
    local c = p.tpl and p.tpl.collision
    if not (c and c.pos and #c.pos >= 3) then p.cbox = false; return false end
    local mn, mx = { 1e9, 1e9, 1e9 }, { -1e9, -1e9, -1e9 }
    for i = 1, #c.pos, 3 do
        for k = 1, 3 do
            local v = c.pos[i + k - 1]
            if v < mn[k] then mn[k] = v end
            if v > mx[k] then mx[k] = v end
        end
    end
    p.cbox = { mn, mx }
    return p.cbox
end

function P.solid_at(x, y, z, r)
    r = r or 0.0
    for _, p in ipairs(P.list) do
        local a = p.ax
        if a and p.wx and not p.gone and p.actor then
            local dx, dy, dz = x - p.wx, y - p.wy, z - p.wz
            if dx * dx + dy * dy + dz * dz <= (p.reach2 or 0) + r * r * 4.0 then
                local box = coll_box(p)
                if box then
                    local us = p.uscale
                    local lx = (dx * a[1] + dy * a[2] + dz * a[3]) / us[1]
                    local ly = (dx * a[4] + dy * a[5] + dz * a[6]) / us[2]
                    local lz = (dx * a[7] + dy * a[8] + dz * a[9]) / us[3]
                    local mn, mx = box[1], box[2]
                    if lx > mn[1] - r / us[1] and lx < mx[1] + r / us[1] and ly > mn[2] - r / us[2] and ly < mx[2] + r / us[2]
                       and lz > mn[3] - r / us[3] and lz < mx[3] + r / us[3] then
                        return true, p
                    end
                end
            end
        end
    end
    return false
end

-- (x, y, z) inside a platform's box grown by r across and by vr below (its own axes; scene cm) - not over its top,
-- where one stands on it: a creature walking or skating into its side kept off it (enemies.lua's Skeeters: "skeeters
-- still going through platforms", 2026-10-28). Returns true, the way out across (scene x and y, a unit vector: its
-- nearest side's), the platform.
function P.solid_near(x, y, z, r, vr)
    local reach = math.max(r, vr)
    for _, p in ipairs(P.list) do
        local a = p.ax
        if a and p.wx and not p.gone and p.actor then
            local dx, dy, dz = x - p.wx, y - p.wy, z - p.wz
            if dx * dx + dy * dy + dz * dz <= (p.reach2 or 0) + reach * reach * 4.0 then
                local box = coll_box(p)
                if box then
                    local us = p.uscale
                    local lx = (dx * a[1] + dy * a[2] + dz * a[3]) / us[1]
                    local ly = (dx * a[4] + dy * a[5] + dz * a[6]) / us[2]
                    local lz = (dx * a[7] + dy * a[8] + dz * a[9]) / us[3]
                    local mn, mx = box[1], box[2]
                    local gx, gy, gz = r / us[1], r / us[2], vr / us[3]
                    if lx > mn[1] - gx and lx < mx[1] + gx and ly > mn[2] - gy and ly < mx[2] + gy
                       and lz > mn[3] - gz and lz < mx[3] then
                        local o1, o2 = (lx - mn[1] + gx) * us[1], (mx[1] + gx - lx) * us[1]
                        local o3, o4 = (ly - mn[2] + gy) * us[2], (mx[2] + gy - ly) * us[2]
                        local least = math.min(o1, o2, o3, o4)
                        local ux, uy
                        if least == o1 then ux, uy = -a[1], -a[2]
                        elseif least == o2 then ux, uy = a[1], a[2]
                        elseif least == o3 then ux, uy = -a[4], -a[5]
                        else ux, uy = a[4], a[5] end
                        local l = math.sqrt(ux * ux + uy * uy)
                        if l > 1e-3 then ux, uy = ux / l, uy / l end
                        return true, ux, uy, p
                    end
                end
            end
        end
    end
    return false
end

-- Is the point (scene space, at the player's feet) on this platform's floor?
-- The highest platform floor under (x, y) at or below zmax (scene cm), for putting him down on arrival.
function P.floor_under(x, y, zmax)
    local best = nil
    for _, p in ipairs(P.list) do
        local F = not p.gone and not p.unsolid and p.tpl and p.tpl.floor
        if F then
            local a = p.ax or { axes(p.pitch, p.yaw, p.roll) }
            local wx, wy, wz = p.wx or (-p.z * S), p.wy or (p.x * S), p.wz or (p.y * S)
            local dx, dy, dz = x - wx, y - wy, zmax - wz
            if dx * dx + dy * dy < (p.reach2 or 0.0) then
                local us = p.uscale
                local lx = (dx * a[1] + dy * a[2] + dz * a[3]) / us[1]
                local ly = (dx * a[4] + dy * a[5] + dz * a[6]) / us[2]
                local lz = (dx * a[7] + dy * a[8] + dz * a[9]) / us[3]
                local fz = H.floor_hit(F, lx, ly, lz)
                if fz then
                    local z = wz + lx * us[1] * a[3] + ly * us[2] * a[6] + fz * us[3] * a[9]
                    if z <= zmax + 1.0 and (not best or z > best) then best = z end
                end
            end
        end
    end
    return best
end

local function standing_on(p, x, y, z)
    if p.gone or p.unsolid then return false end        -- (hidden, not solid)
    local F = p.tpl.floor
    local a = p.ax
    if not (F and a) then return false end
    local dx, dy, dz = x - p.wx, y - p.wy, z - p.wz
    if dx * dx + dy * dy + dz * dz > p.reach2 then return false end
    local us = p.uscale
    local lx = (dx * a[1] + dy * a[2] + dz * a[3]) / us[1]
    local ly = (dx * a[4] + dy * a[5] + dz * a[6]) / us[2]
    local lz = (dx * a[7] + dy * a[8] + dz * a[9]) / us[3]
    local fz = H.floor_hit(F, lx, ly, lz + 45.0 / us[3])
    if fz == nil then return false end
    local gap = abs(lz - fz) * us[3]
    return gap < 45.0, gap
end

-- A platform under him - on it, or in the air over it, not more than 30 cm down into it: the lava (or a death plane)
-- under a platform does not reach through it (game.lua update_floors; "sometimes when landing on the lava platforms the
-- lava hits you through it", 2026-10-19). (x, y, z): his feet, scene cm.
-- The top of the highest platform under (x, y) - scene cm - no higher than z + 45 there: its height, or nil. (Coins come
-- down on them: game.lua update_pickup - they fell into a metal box, through its top, "coins fall into moving box
-- also", 2026-10-28.)
function P.top_under(x, y, z)
    local best = nil
    for _, p in ipairs(P.list) do
        if not p.gone and p.tpl and p.tpl.floor and p.ax and p.wx then
            local F, a, us = p.tpl.floor, p.ax, p.uscale
            local dx, dy, dz = x - p.wx, y - p.wy, z - p.wz
            if dx * dx + dy * dy <= p.reach2 then
                local lx = (dx * a[1] + dy * a[2] + dz * a[3]) / us[1]
                local ly = (dx * a[4] + dy * a[5] + dz * a[6]) / us[2]
                local lz = (dx * a[7] + dy * a[8] + dz * a[9]) / us[3]
                local fz = H.floor_hit(F, lx, ly, lz + 45.0 / us[3])
                if fz then
                    local wz = p.wz + lx * us[1] * a[3] + ly * us[2] * a[6] + fz * us[3] * a[9]
                    if not best or wz > best then best = wz end
                end
            end
        end
    end
    return best
end

function P.over(x, y, z)
    for _, p in ipairs(P.list) do
        if not p.gone and p.tpl and p.tpl.floor and p.ax and p.wx then
            local F, a, us = p.tpl.floor, p.ax, p.uscale
            local dx, dy, dz = x - p.wx, y - p.wy, z - p.wz
            if dx * dx + dy * dy + dz * dz <= p.reach2 then
                local lx = (dx * a[1] + dy * a[2] + dz * a[3]) / us[1]
                local ly = (dx * a[4] + dy * a[5] + dz * a[6]) / us[2]
                local lz = (dx * a[7] + dy * a[8] + dz * a[9]) / us[3]
                local fz = H.floor_hit(F, lx, ly, lz + 45.0 / us[3])
                if fz and (lz - fz) * us[3] > -30.0 then return p end
            end
        end
    end
    return nil
end

local function step(p, m)
    snapshot(p)
    local fn = p.def.step
    if not fn then return end
    local a0 = p.action
    fn(p, m)
    p.timer = p.timer + 1
    if p.action ~= a0 then
        p.timer = 0
        if p.def.changed then p.def.changed(p, a0, m) end
    end
    if p.jump then p.jump = nil; snapshot(p) end
end

local function render(p, a)
    local x, y, z = p.px + (p.x - p.px) * a, p.py + (p.y - p.py) * a, p.pz + (p.z - p.pz) * a
    local pitch = p.ppitch + s16(p.pitch - p.ppitch) * a
    local yaw = p.pyaw + s16(p.yaw - p.pyaw) * a
    local roll = p.proll + s16(p.roll - p.proll) * a
    if p.def.draw then pcall(p.def.draw, p, x, y, z, yaw) end      -- (a model of its own drawn with it, animated)
    local d = p.drawn
    if d and abs(d[1] - x) < 0.01 and abs(d[2] - y) < 0.01 and abs(d[3] - z) < 0.01
        and abs(d[4] - pitch) < 0.5 and abs(d[5] - yaw) < 0.5 and abs(d[6] - roll) < 0.5 then
        return
    end
    p.drawn = { x, y, z, pitch, yaw, roll }
    local fx, fy, fz, rx, ry, rz, ux, uy, uz = axes(pitch, yaw, roll)
    p.ax = { fx, fy, fz, rx, ry, rz, ux, uy, uz }
    local ox, oy = p.wx, p.wy
    p.wx, p.wy, p.wz = -z * S, x * S, y * S
    local rot = rotator(fx, fy, fz, rx, ry, rz, ux, uy, uz)
    p.rot = rot
    if not p.actor then return end
    pcall(function()
        p.actor:K2_TeleportTo({ X = p.wx + OFFSET.X, Y = p.wy + OFFSET.Y, Z = p.wz + OFFSET.Z }, rot)
    end)
    -- (one that does not take him along: the engine carries the character with the floor it stands on, the next frame;
    -- put where he already is the same frame - a teleport - it forgets where that floor was, and he stays put as it
    -- slides from under him. LLL's puzzle pieces: "make sure it doesnt bring the player with it when the pieces move",
    -- 2026-10-19 - measured: he stayed to the centimetre while his piece slid 1.8 m. Moved back by its travel instead,
    -- he was pushed the other way.)
    if p.def.noride and P.on == p and ox and (abs(p.wx - ox) > 0.05 or abs(p.wy - oy) > 0.05) then
        pcall(function()
            local pawn = lib.pawn()
            pawn:K2_TeleportTo(pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation())
        end)
    end
end

local acc = 0.0

-- how loud a platform's sound is where the player is (0..1): Mario 64's falls away with distance
local SOUND_REACH = 5000.0          -- Mario 64 units
local function loudness(p, m, reach)
    local dx, dy, dz = p.x - m.x, p.y - m.y, p.z - m.z
    local k = 1.0 - sqrt(dx * dx + dy * dy + dz * dz) / (reach or SOUND_REACH)
    if k <= 0.0 then return 0.0 end
    return k ^ 1.5
end

local function sounds(list, m, dt)
    local SFX = sfx()
    if not (SFX and SFX.hold) then return end
    -- (where the scene has rooms - the castle's floors, Big Boo's Haunt, Hazy Maze Cave - heard only with him in its room
    -- or one through a door from it (rooms.lua; its room the floor's under where it starts, as bhv_init_room gives it),
    -- as Mario 64's room objects go still away from him. Its reach alone carried the castle clock's pendulum, on the
    -- third floor, 37 m round and through the floor to the second: "can hear the clock from downstairs", 2026-10-27.
    -- What is heard all over - the switch's ticking - still is.)
    local R, G = package.loaded["rooms"], package.loaded["game"]
    local roomed = R and G and G.name and R.has(G.name)
    local shots = nil
    for _, p in ipairs(list) do
        local here = true
        if roomed then
            if p.room == nil then
                local ok, r = pcall(R.at, G.name, -p.z * S, p.x * S, p.y * S + 10.0)
                p.room = (ok and r) or 0
            end
            here = R.with_mario(p.room)
        end
        local hum = p.def.hum
        if hum then
            local ok, name, reach = pcall(hum, p, m)
            if ok and name and (here or (reach or 0) >= 1.0e5) then SFX.hold(name, loudness(p, m, reach)) end
        end
        if p.shot then
            -- (`shot_gain`, `shot_reach`: a behaviour's own loudness for them)
            local v = loudness(p, m, p.def.shot_reach) * (p.def.shot_gain or 1.0)
            if v > 0.02 and here then
                -- (the same sound from several at the same moment played once, as loud as the nearest: RR's ship's six
                -- wings creaked as one, six times over)
                shots = shots or {}
                if (shots[p.shot] or 0.0) < v then shots[p.shot] = v end
            end
            p.shot = nil
        end
    end
    for name, v in pairs(shots or {}) do pcall(SFX.play, name, v) end
    pcall(SFX.update_held, dt)
end

-- STORROR's attack going on now (push, kick ...), and whether he is in the air (a drop kick)
local function air_attack()
    local pawn = lib.pawn()
    if not pawn then return false, false end
    local name = nil
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        if not (ai and ai:IsValid()) then return end
        local mt = ai:GetCurrentActiveMontage()
        if mt and mt:IsValid() then name = mt:GetFName():ToString() end
    end)
    if not (name and (name:find("Attack") or name:lower():find("kick") or name:lower():find("push"))) then return false, false end
    local air = false
    pcall(function() air = pawn.CharacterMovement:IsFalling() end)
    return air, true
end

-- Standing still on one that turns, he turns with it (Mario 64's apply_platform_displacement turns his facing by its
-- yaw speed: "make sure the charater spins with the platform correctly when on top", 2026-10-17). The engine's base
-- following carries him round, but STORROR swings his facing straight back to one it keeps (it takes a new one only in
-- a fall), so his body is turned instead: the mesh's own yaw, by what the platform has turned since he stood still.
-- Moving or off it, that eases back to nothing - STORROR faces him where he runs.
local rider = { p = nil, yaw = nil, off = 0.0, set = 0.0, base = nil }
local function turn_rider(p, dt)
    local pawn = lib.pawn()
    if not pawn then return end
    if not rider.base then
        pcall(function() local r = pawn.Mesh.RelativeRotation; rider.base = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } end)
        if not rider.base then return end
    end
    local sp = 0.0
    pcall(function() local v = pawn:GetVelocity(); sp = sqrt(v.X * v.X + v.Y * v.Y) end)
    local yaw = nil
    if p and p.actor then pcall(function() yaw = p.actor:K2_GetActorRotation().Yaw end) end
    if yaw and rider.p == p and rider.yaw and sp < 40.0 then
        local d = (yaw - rider.yaw + 540.0) % 360.0 - 180.0
        if abs(d) < 45.0 then rider.off = rider.off + d end
    elseif rider.off ~= 0.0 then
        rider.off = rider.off * math.exp(-8.0 * math.min(dt, 0.1))
        if abs(rider.off) < 0.2 then rider.off = 0.0 end
    end
    rider.off = (rider.off + 540.0) % 360.0 - 180.0
    rider.p, rider.yaw = p, yaw
    if rider.off ~= rider.set then
        rider.set = rider.off
        local b = rider.base
        pcall(function() pawn.Mesh:K2_SetRelativeRotation({ Pitch = b.Pitch, Yaw = b.Yaw + rider.off, Roll = b.Roll }, false, {}, true) end)
    end
end

-- Every tick: (x, y, z) is the player's feet in scene space, `grounded` whether he is standing.
-- Mario 64's rooms (rooms.lua): these take the room of the floor under where they start (bhv_init_room) and are drawn
-- only with him in it or in one through a door from it (cur_obj_enable_rendering_if_mario_in_room) - Dorrie, Hazy Maze
-- Cave's lifts, the platforms on tracks. Drawn always, Dorrie swam in sight at the foot of the boulder room's pit: "the
-- holes in this level are seethrough, I can see dory from the boulder hole", 2026-10-25. Only what this hid is shown
-- again (Dorrie's template stays hidden under her animated model).
P.ROOMED = { dorrie = true, track = true, elevator = "hmc" }
function P.room_sight(list)
    local R, G = package.loaded["rooms"], package.loaded["game"]
    if not (R and G and G.name and R.has(G.name)) then return end
    for _, p in ipairs(list) do
        local how = p.o and P.ROOMED[p.o.bhv]
        if how == true or how == G.name then
            if p.room == nil then
                local ok, r = pcall(R.at, G.name, -p.z * S, p.x * S, p.y * S + 10.0)
                p.room = (ok and r) or 0
            end
            local away = not R.with_mario(p.room)
            if away ~= (p.room_hid ~= nil) then
                if away then
                    p.room_hid = {}
                    for _, a in ipairs({ p.actor or false, p.vis and p.vis.actor or false }) do
                        if a and a:IsValid() and not a.bHidden then
                            a:SetActorHiddenInGame(true)
                            p.room_hid[#p.room_hid + 1] = a
                        end
                    end
                else
                    for _, a in ipairs(p.room_hid) do pcall(function() if a:IsValid() then a:SetActorHiddenInGame(false) end end) end
                    p.room_hid = nil
                end
            end
        end
    end
end

-- The Fire Sea's arena while it rocks: never through him. Sliding down it he is in STORROR's falling mode, not carried
-- with it, and as it swung back level its rising side came up through him - he dropped out under it into the lava:
-- "also fell through the stage", 2026-10-25. Its top over his feet (by no more than 1.5 m): he is put back on it, his
-- fall into it stopped. (x, y, feet: scene cm.)
function P.arena_keep(x, y, feet)
    local ar = P.bowser_arena
    if not (ar and ar.tt and not ar.gone) then return end
    local top = P.floor_under(x, y, feet + 150.0)
    if not top or top <= feet + 1.0 then return end
    local pawn = lib.pawn()
    if not pawn then return end
    -- (not while he lies limp: his capsule goes after his body then, and lifted it only fought it)
    local limp = false
    pcall(function() limp = pawn.CharacterMovement.MovementMode == 0 end)
    if limp then return end
    pcall(function()
        local l = pawn:K2_GetActorLocation()
        pawn:K2_SetActorLocation({ X = l.X, Y = l.Y, Z = l.Z + (top - feet) + 2.0 }, false, {}, true)
        local cm = pawn.CharacterMovement
        local v = cm.Velocity
        if v.Z < 0.0 then cm.Velocity = { X = v.X, Y = v.Y, Z = 0.0 } end
    end)
end

-- Down the Fire Sea's tipped arena he gathers speed: its slope's pull, ARENA_PUSH cm/s/s times sin*cos of it, up to
-- ARENA_MAX cm/s across it. STORROR's falling mode only kept the speed he had - 474 cm/s held for 3 s at 43 degrees:
-- "make the charater slide more", 2026-10-26. At 800 he went 110 to 735 cm/s in 2 s at 43 degrees (some 350 cm/s/s):
-- "make him slide even more", doubled. Past ARENA_BRAKE at its steepest (800): the stick straight back slows him there,
-- no longer stops him. Downhill from the arena's top 40 cm either side of him.
P.ARENA_PUSH, P.ARENA_MAX = 1600.0, 2000.0
function P.arena_push(x, y, feet, dt, cm)
    local d, zmax = 40.0, feet + 150.0
    local e, w = P.floor_under(x + d, y, zmax), P.floor_under(x - d, y, zmax)
    local n, s_ = P.floor_under(x, y + d, zmax), P.floor_under(x, y - d, zmax)
    if not (e and w and n and s_) then return end
    local gx, gy = (e - w) / (2.0 * d), (n - s_) / (2.0 * d)
    local t2 = gx * gx + gy * gy
    local t = sqrt(t2)
    if t < 0.001 then return end
    local acc = P.ARENA_PUSH * t / (1.0 + t2)
    local v = cm.Velocity
    local was = sqrt(v.X * v.X + v.Y * v.Y)
    local vx, vy = v.X - gx / t * acc * dt, v.Y - gy / t * acc * dt
    local sp = sqrt(vx * vx + vy * vy)
    if sp > P.ARENA_MAX and sp > was then
        local k = math.max(P.ARENA_MAX, was) / sp
        vx, vy = vx * k, vy * k
    end
    cm.Velocity = { X = vx, Y = vy, Z = v.Z }
end

-- Sliding down the Fire Sea's tipped arena, the stick against the slide brakes it - up to ARENA_BRAKE cm/s/s at full
-- stick straight back, never past a stop - and across it turns it a little (ARENA_STEER rad/s): "make it possible to
-- slow yourself by pulling in opposite direction", 2026-10-25. The stick as the camera sees it, as burn.lua's.
P.ARENA_BRAKE, P.ARENA_STEER = 500.0, 1.2     -- ("too much backup" at 1500: STORROR's own air control pulls back too)
function P.arena_brake(x, y, feet, dt)
    local ar = P.bowser_arena
    if not (ar and ar.slide_on and not ar.gone and P.over(x, y, feet) == ar) then return end
    local pawn, pc = lib.pawn(), lib.controller()
    if not (pawn and pc) then return end
    local cm = pawn.CharacterMovement
    if cm.MovementMode ~= 3 then return end
    pcall(P.arena_push, x, y, feet, dt, cm)
    local sx, sy = 0.0, 0.0
    pcall(function()
        sx = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftX") })
        sy = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftY") })
    end)
    if type(sx) ~= "number" then sx = 0.0 end
    if type(sy) ~= "number" then sy = 0.0 end
    local function key(n)
        local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(n) }) end)
        return ok and v
    end
    if key("D") or key("Right") then sx = 1.0 elseif key("A") or key("Left") then sx = -1.0 end
    if key("W") or key("Up") then sy = 1.0 elseif key("S") or key("Down") then sy = -1.0 end
    local mag = math.min(1.0, sqrt(sx * sx + sy * sy))
    if mag < 0.2 then return end
    local cam = 0.0
    pcall(function() cam = pc.PlayerCameraManager:GetCameraRotation().Yaw end)
    local want = math.rad(cam) + atan(sx, sy)
    local v = cm.Velocity
    local sp = sqrt(v.X * v.X + v.Y * v.Y)
    if sp < 1.0 then return end
    local a = atan(v.Y, v.X)
    local d = (want - a + pi) % (2.0 * pi) - pi
    -- (against it: slowed; across it: turned)
    local back = -math.cos(d)
    if back > 0.0 then sp = math.max(0.0, sp - P.ARENA_BRAKE * back * mag * dt) end
    local turn = math.max(-P.ARENA_STEER * dt, math.min(P.ARENA_STEER * dt, math.sin(d) * P.ARENA_STEER * mag * dt))
    a = a + turn
    pcall(function() cm.Velocity = { X = math.cos(a) * sp, Y = math.sin(a) * sp, Z = v.Z } end)
end

-- (20 m, not 60: in Whomp's Fortress 26 of its 39 were 20 to 60 m off, the moving ones put in place every frame - and
-- every 3rd frame is still Mario 64's own 30 a second - "when I entered the level it was 120 fps now its 80", 2026-11-05)
P.LOD_FAR, P.LOD_EVERY = 2000.0, 3
P.LOD_FARTHER, P.LOD_EVERY_FAR = 15000.0, 8
function P.update(dt, x, y, z, grounded)
    if P.cut then pcall(cut_tick, dt) end
    local list = P.list
    if #list == 0 then
        P.on = nil
        pcall(turn_rider, nil, dt)
        local SFX = sfx()
        if SFX and SFX.update_held then pcall(SFX.update_held, dt) end      -- (anything still humming fades)
        local SQ = squish()
        if SQ and SQ.active() then pcall(SQ.tick, dt) end
        return
    end
    local m = { x = y / S, y = z / S, z = -x / S, ground = grounded, plat = nil }
    if P.in_cannon then aim_input(dt) end          -- (every frame: the mouse's travel is a frame's)
    -- (landed; flown, the engine has him not falling - flight.lua ends the shot itself)
    local FL = package.loaded["flight"]
    if P.cannon_flight and grounded and os.clock() - P.cannon_flight > 0.5 and not (FL and FL.active and FL.active()) then
        P.cannon_flight = nil
    end
    if P.want_kick then
        local air, any = air_attack()
        if air then P.kick_at = os.clock() end
        if any and not P.attacking then P.attack_at, P.attack_air = os.clock(), air end
        P.attacking = any
        m.kick = P.kick_at ~= nil and os.clock() - P.kick_at < 1.0          -- (it lands just after)
    end
    -- (a landing from a jump - down at least 30 cm from the top of it - kept a moment, as the kick is: the frame he
    -- lands may run no platform step. The basement pillars go down to it: "make the water pillers drop by jumping on
    -- them", 2026-10-19)
    if grounded then
        if P.was_air and (P.air_top or z) - z > 30.0 then P.land_at = os.clock() end
        P.was_air, P.air_top = false, nil
    else
        P.was_air, P.air_top = true, math.max(P.air_top or z, z)
    end
    m.land = P.land_at ~= nil and os.clock() - P.land_at < 0.4
    if grounded then
        -- (the one whose top is nearest his feet: the Dark World's purple switch stands on its folded stairs, and the
        -- first one found was the stairs, so the switch was never pressed, 2026-10-15)
        local bg = nil
        for _, p in ipairs(list) do
            local on, gap = standing_on(p, x, y, z)
            if on and (not bg or gap < bg) then m.plat, bg = p, gap end
        end
    end
    if P.rider then m.plat = P.rider end                -- (tests: say who is being stood on)
    P.on = m.plat
    local tm = m.plat
    if tm and tm.convey and not P.dry then
        -- (Mario 64 moves him by its speed every frame: 30 frames a second)
        local k = tm.convey * 30.0 * dt * S
        local dx, dy = -coss(tm.yaw) * k, sins(tm.yaw) * k
        pcall(function()
            local pawn = lib.pawn()
            local l, r = pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation()
            pawn:K2_TeleportTo({ X = l.X + dx, Y = l.Y + dy, Z = l.Z }, r)
        end)
    end
    if P.drain_until and os.clock() < P.drain_until then
        local SFX = package.loaded["sfx"]
        if SFX and SFX.hold then pcall(SFX.hold, "loop_water_drain", 1.0) end
    end
    acc = acc + dt
    local n = 0
    while acc >= STEP and n < 4 do
        acc = acc - STEP
        n = n + 1
        for _, p in ipairs(list) do
            local ok, e = pcall(step, p, m)
            if not ok and not p.broken then
                p.broken = true
                p.def = B.static
                log("platform %s stopped: %s", tostring(p.o and p.o.bhv), tostring(e))
            end
        end
    end
    if acc > STEP then acc = 0.0 end
    pcall(P.room_sight, list)
    pcall(P.arena_keep, x, y, z)
    pcall(P.arena_brake, x, y, z, math.min(dt or 0.016, 0.1))
    local a = acc / STEP
    -- (far ones - over P.LOD_FAR cm from him, not the one he is on - drawn every P.LOD_EVERY frames, each on its own
    -- frame of them: their steps go on as ever, only where they are drawn waits. Of the Bowser run's 76, 59 were over 60
    -- m off and every moving one was put in place every frame - "optimize the game", 2026-11-03)
    -- (and up or down from him too, the run's level being a tower; over P.LOD_FARTHER, every P.LOD_EVERY_FAR - "I want a
    -- significant boost in fps", 2026-11-03)
    P.lod_frame = (P.lod_frame or 0) + 1
    local lf2, le = (P.LOD_FAR or 6000.0) ^ 2, P.LOD_EVERY or 3
    local lff2, lef = (P.LOD_FARTHER or 15000.0) ^ 2, P.LOD_EVERY_FAR or 8
    for i, p in ipairs(list) do
        local d2 = 0.0
        if P.on ~= p and p.wx ~= nil then d2 = (p.wx - x) ^ 2 + (p.wy - y) ^ 2 + ((p.wz or z) - z) ^ 2 end
        local every = (d2 > lff2) and lef or ((d2 > lf2) and le or 1)
        if every == 1 or (P.lod_frame + i) % every == 0 then
            render(p, a)
            if p.def == B.fire_bars then pcall(draw_fire_bars, p, a) end
        end
    end
    pcall(ride_thwomps, dt)
    local turn_on = tm
    if not turn_on then
        local okr, rp = pcall(on_ring, grounded)
        if okr then turn_on = rp end
    end
    pcall(turn_rider, turn_on, dt)
    if grounded then pcall(squeeze, m, x, y, z) end
    local SQ = squish()                 -- (after the drawing: what is on top of him is where it is drawn)
    if SQ and SQ.active() then pcall(SQ.tick, dt) end
    sounds(list, m, dt)
end

return P
