-- SM64Map: Mario 64's boxes (asked 2026-10-14: "for grabbing objects and enemies such as bombombs bowser and boxes
-- use the push control"; "all the enemies ... all the audio ... make sure everything looks right").
--
--   ! box (bhvExclamationBox)   floats where the level puts it, solid to stand on. Hit from below (a jump into it) or
--                               attacked (STORROR's push or drop kick), it breaks and gives what it holds: coins, a
--                               1-up, or a star (some of a course's stars are in ! boxes). Red, green and blue boxes
--                               hold Mario's caps (caps.lua): the cap pops out, falls in front of him and is his
--                               when he touches it; the box comes back 10 s later. Its colour is Mario 64's: red
--                               wing, green metal, blue vanish, otherwise yellow.
--   cork box (bhvBreakableBox)  solid; attacked, it breaks (three or five coins if the level says so).
--   small cork box              picked up with a push, carried, thrown with another; it breaks where it lands and
--                               leaves a coin.
--   jumping box (crazy box)     a cork box that hops about, solid; taken hold of (a push at it) or stood on, it
--                               carries him off in three bounces and breaks into its five coins at the third
--                               landing (act_crazy_box_bounce); kicked, it breaks.
-- Broken boxes stay broken until the level is entered again, as in Mario 64.
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET

local M = { list = {}, kinds = { box = true } }
local S = 0.75
local STEP = 1 / 30
local H = {}
local P = nil                   -- (platforms.lua: floors that move)

local sqrt, sin, cos, atan, floor, abs, pi, max, min = math.sqrt, math.sin, math.cos, math.atan, math.floor, math.abs, math.pi, math.max, math.min

function M.setup(h, p) H = h; P = p end

local function sins(a) return sin(a * pi / 32768.0) end
local function coss(a) return cos(a * pi / 32768.0) end
local function s16(a) a = floor(a) % 65536; if a >= 32768 then a = a - 65536 end; return a end
local function to_scene(x, y, z) return -z * S, x * S, y * S end
local function floor_y(x, y, z)
    if not H.floor_z then return nil end
    local sx, sy = to_scene(x, 0, z)
    local fz = H.floor_z(sx, sy, (y + 250.0) * S)
    return fz and fz / S or nil
end
local function sound(name, v)
    local SFX = package.loaded["sfx"]
    if SFX and (v or 1.0) > 0.02 then pcall(SFX.play, name, v) end
end

-- a closed box of collision, x and z from -h to h, y from y0 to y1 (Mario 64 units, the model's own space), in the
-- shape lib.add_collision takes (the game's x, y, z as this scene's -z, x, y; 0.75 cm a unit)
local function cube(h, y0, y1)
    local pos = {}
    for _, p in ipairs({ { -h, y0, -h }, { h, y0, -h }, { h, y1, -h }, { -h, y1, -h },
                         { -h, y0, h }, { h, y0, h }, { h, y1, h }, { -h, y1, h } }) do
        pos[#pos + 1], pos[#pos + 2], pos[#pos + 3] = -p[3] * S, p[1] * S, p[2] * S
    end
    return { source = "box", pos = pos,
             idx = { 0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5,
                     2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7 } }
end
local EXBOX_CUBE = cube(25, 1, 52)          -- (the ! box's model, before its scale of 2)
local CORK_CUBE = cube(100, 0, 200)

-- what a ! box holds (sExclamationBoxContents): coins, 1-ups, stars by act
local function contents(c, bp1)
    -- (a star's index is the box's own first parameter byte or'd with the contents' - exclamation_box.inc.c; JRB's box
    -- in the ship's cove is STAR_ACT_1 contents with STAR_INDEX_ACT_5 of its own)
    bp1 = bp1 or 0
    if c == 8 then return { star = bp1 | 0 } end
    if c >= 10 and c <= 14 then return { star = bp1 | (c - 9) } end
    if c == 5 then return { coins = 3 } elseif c == 6 then return { coins = 10 } elseif c == 4 then return { coins = 1 }
    elseif c == 7 then return { oneup = "walk" } elseif c == 9 then return { oneup = "away" }   -- (bhv1upWalking, bhv1upRunningAway)
    elseif c == 8 then return { star = 0 }
    elseif c >= 10 and c <= 14 then return { star = c - 9 }
    elseif c <= 2 then return { cap = ({ [0] = "wing", [1] = "metal", [2] = "vanish" })[c] }    -- (caps.lua)
    elseif c == 3 then return { shell = true }                      -- (a Koopa shell to surf on: shell.lua)
    else return { coins = 1 } end
end

-- ! boxes set by hand where the rule above cannot see their floor, Mario 64 units: { x, z, y } - Bowser in the Fire Sea's
-- 1-up box, 803 over the platform under it (and 1295 over the level's floor under that, taken for a drop): EX_LOW over
-- the platform - "this box is too high", 2026-10-25 - then "too low", "still too low", "raise it more", "more", "more",
-- "little less": 730 over it (Mario 64's own: 803)
-- (`set`: put there even if it is higher - only ever lowered without)
-- (and Bowser in the Sky's, over the spinning platform past the ledge with the Amp round it: 383 over the platform's
-- top (-1433), which the rule cannot see - a platform, not the level's floor - EX_LOW over it: "box sits too high",
-- 2026-11-02)
M.EX_AT = { { -7400.0, 0.0, 697.0 + 730.0 }, { 4100.0, -1800.0, -1433.0 + 300.0 } }
-- Cork boxes set by hand, Mario 64 units: { x, z, y }. Wet-Dry World town's four under its metal cap box, hung in the air
-- there with a slab 356 over their tops: the box 180 over them, the athlete's head into it standing on them - "this
-- metal cap box sits too low raise it", 2026-10-28 - and raised, its top in the slab ("its in the ceiling"). So the four
-- down 100 instead - "lower the platform underneith if you need to" - and the box where Mario 64 has it: 282 over them,
-- 2.1 m clear, 54 cm under the slab.
M.BOX_AT = { { -870.0, 870.0, -400.0 }, { -670.0, 870.0, -400.0 }, { -670.0, 670.0, -400.0 }, { -870.0, 670.0, -400.0 } }
local EX_REACH, EX_LOW = 330.0, 300.0      -- Mario 64 units: a ! box higher over the floor than EX_REACH comes down to EX_LOW
                                           -- (400 / 370 before: the sunken ship's star box at 341 over its tilted floor was
                                           -- only just reached - "box is too high in sunken ship", 2026-10-18)
function M.add(world, o)
    if not o.sm64 then return end
    local x, y, z = o.sm64[1], o.sm64[2], o.sm64[3]
    local yaw = s16(-(o.yaw or 0.0) * 65536.0 / 360.0)
    local b = { o = o, type = o.type, x = x, y = y, z = z, hx = x, hy = y, hz = z, yaw = yaw, fvel = 0.0, vy = 0.0,
                action = "idle", timer = 0, ground = true }
    local actor_name, scale, col
    if o.type == "bhvExclamationBox" then
        local c = o.content or 3
        actor_name = "exbox_" .. ((c <= 2) and c or 3)
        scale, col = 2.0, EXBOX_CUBE
        b.give = contents(c, o.bp1)
        b.ex = true
        -- (out of reach where Mario 64 has Mario double-jump up to it: STORROR's jump brings the athlete's head about 390
        -- over the floor, and hitting it from below wants his head within 30 of its bottom. One more than EX_REACH over
        -- the floor - and over floor, within 700, not a drop - comes down to EX_LOW over it: "this box is too high",
        -- 2026-10-18, CCM's 1-up box at 483)
        -- (the floor under it at its middle and under its four sides, the lowest: where he stands to jump on a slope)
        local fy = floor_y(x, y - 10.0, z)
        if fy then
            for _, d in ipairs({ { 100.0, 0.0 }, { -100.0, 0.0 }, { 0.0, 100.0 }, { 0.0, -100.0 } }) do
                local f2 = floor_y(x + d[1], y - 10.0, z + d[2])
                if f2 and f2 < fy and fy - f2 < 200.0 then fy = f2 end
            end
        end
        if fy and y - fy > EX_REACH and y - fy < 700.0 then
            log("box: ! box at %.0f %.0f %.0f lowered from %.0f to %.0f over the floor", x, y, z, y - fy, EX_LOW)
            b.y, b.hy = fy + EX_LOW, fy + EX_LOW
        end
        for _, at in ipairs(M.EX_AT) do
            if math.abs(x - at[1]) < 1.0 and math.abs(z - at[2]) < 1.0 and (at.set or y > at[3]) then
                log("box: ! box at %.0f %.0f %.0f set to %.0f", x, y, z, at[3])
                b.y, b.hy = at[3], at[3]
            end
        end
        -- (a cap's box is only an outline, not solid and not to be broken, until its switch is pressed:
        -- exclamation_box.inc.c, sCapSaveFlags)
        local flag = ({ [0] = "cap_wing", [1] = "cap_metal", [2] = "cap_vanish" })[c]
        local MN = _G.MENU
        if flag and not (MN and MN.has_flag and MN.has_flag(flag)) then
            b.outline, col = true, nil
        end
    else
        if o.type ~= "bhvExclamationBox" then
            local fy = floor_y(x, y + 50.0, z)
            if fy and fy > y - 400.0 then b.y, b.hy = fy, fy end
            for _, at in ipairs(M.BOX_AT) do
                if math.abs(x - at[1]) < 1.0 and math.abs(z - at[2]) < 1.0 then
                    log("box: %s at %.0f %.0f %.0f set to %.0f", o.type, x, y, z, at[3])
                    b.y, b.hy = at[3], at[3]
                end
            end
        end
        actor_name = "cork_box"
        if o.type == "bhvBreakableBoxSmall" then
            -- (solid too, as the cork boxes - its collision scaled with it - till it is picked up: "this little box
            -- doesnt have collisions", 2026-10-17)
            scale, b.small, col = 0.4, true, CORK_CUBE
        elseif o.type == "bhvJumpingBox" then
            -- (solid, as the other cork boxes: "the crazy box needs fixed it needs collisions and needs to bounce the
            -- player 3 times", 2026-10-23; its five coins - sJumpingBoxHitbox's numLootCoins)
            scale, b.jumping, col = 0.6, true, CORK_CUBE
            b.give = { coins = 5 }
            -- (its face: the crazy box's own picture; the cork boxes' plain cork - "also this random box here?",
            -- 2026-10-28, every cork box wore the face)
            actor_name = "crazy_box"
        else
            -- (the giant ones - macro_breakable_box_giant, its 2nd byte 3 - half as big again: breakable_box_init's
            -- cur_obj_scale(1.5f). Twice as big here, WDW town's 3 m tall: "why is there a bunch of huge boxes?", 2026-10-28)
            scale, col = (o.content == 3) and 1.5 or 1.0, CORK_CUBE
            b.give = { coins = (o.content == 1) and 3 or ((o.content == 2) and 5 or 0) }
        end
        -- (and not left in a wall the level put it in: WDW's giant box stood 38 cm into the wall behind it, one face of
        -- it showing - put out of it, its own half from it)
        local G = package.loaded["game"]
        if G and G.wall_near then
            local sx2, sy2, sz2 = to_scene(b.x, b.y + 100.0 * scale, b.z)
            local okw, hit, px, py = pcall(G.wall_near, sx2, sy2, sz2, 75.0 * scale)
            if okw and hit and (px ~= 0.0 or py ~= 0.0) then
                b.x, b.z = b.x + py / S, b.z - px / S
                b.hx, b.hz = b.x, b.z
                log("box: %s put %.0f cm out of a wall", o.type, math.sqrt(px * px + py * py))
            end
        end
    end
    local data = H.actor_data and H.actor_data(actor_name)
    if not data then log("box: no model %s", actor_name); return end
    local sx, sy, sz = to_scene(b.x, b.y, b.z)
    b.inst = lib.make_instance(world, data, { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z }, -yaw * 360.0 / 65536.0, scale)
    if not b.inst then return end
    b.scale = scale
    if b.outline then pcall(lib.see_through, world, b.inst, 0.35) end
    if col then
        -- solid, to stand on and to bump into (the actor's own scale scales it too)
        pcall(function()
            local pmc = lib.add_pmc(b.inst.actor)
            if pmc then lib.add_collision(pmc, { col }); b.pmc = pmc end
        end)
    end
    b.prev = { b.x, b.y, b.z }
    M.list[#M.list + 1] = b
end

-- ------------------------------------------------------------ caps out of their boxes
-- exclamation_box.inc.c exclamation_box_spawn_contents: the cap starts at the box going 20 a frame up and 3 a frame
-- the way Mario faces. cap.inc.c: wing and vanish caps fall 1.2 a frame, the metal one 2.4 (friction 0.999), each
-- turning by its forward speed * 128 a frame; it can be picked up (interact_cap) from its 21st frame, hitbox 80 across
-- and 80 high; after 300 frames it flickers for 40 (obj_flicker_and_disappear) and is gone. On a touchdown fast enough
-- to bounce, wing and vanish caps stop dead and squash (cap_scale_vertically); the metal one bounces. The vanish cap is
-- see-through (opacity 150). object_step (obj_behaviors.c): falls at most 75 a frame, bounces off a floor hit at over
-- 17.5 with half its speed, slides down slopes, turns off walls and floors too steep to climb, turns round where there
-- is no floor; in water it rises (wing, vanish) or sinks (metal) by its buoyancy.
local CAP_PHYS = { wing = { g = 1.2, b = 0.9 }, metal = { g = 2.4, b = 1.5 }, vanish = { g = 1.2, b = 0.9 } }
local caps = {}

local function yaw_of(vx, vz) return s16(atan(vx, vz) * 32768.0 / pi) end
-- v bounced off a surface whose level normal is (nx, nz) (turn_obj_away_from_surface)
local function turn_away(vx, vz, nx, nz)
    local l = nx * nx + nz * nz
    if l < 1e-9 then return vx, vz end
    return ((nz * nz - nx * nx) * vx - 2.0 * vz * nx * nz) / l, ((nx * nx - nz * nz) * vz - 2.0 * vx * nx * nz) / l
end
-- the floor under (x, z) at or below y + 78 (find_floor), Mario units, and its normal in Mario's axes
local function cap_floor(x, y, z)
    local sx, sy = to_scene(x, 0, z)
    local zmax = (y + 78.0) * S
    local G = package.loaded["game"]
    local fz, nx, ny, nz
    if G and G.floor_normal then fz, nx, ny, nz = G.floor_normal(sx, sy, zmax) end
    if not fz and H.floor_z then
        fz = H.floor_z(sx, sy, zmax)
        nx, ny, nz = 0.0, 0.0, 1.0
    end
    local pz = P and P.floor_under and P.floor_under(sx, sy, zmax)
    if pz and (not fz or pz > fz) then fz, nx, ny, nz = pz, 0.0, 0.0, 1.0 end
    -- (and the boxes' tops, solid as they stand: Mario 64's are surface objects it lands on. WDW town's metal cap came out
    -- over four cork boxes hung in the air and, no level floor under it, hung there by the ceiling out of reach - "cap
    -- still getting stuck in the ceiling", 2026-10-28)
    local BX = package.loaded["boxes"]
    for _, b in ipairs(BX and BX.list or {}) do
        if b.inst and b.pmc and b.action == "idle" then
            local s = b.scale or 1.0
            local half, top = (b.ex and 25.0 or 100.0) * s, b.y + (b.ex and 52.0 or 200.0) * s
            if math.abs(x - b.x) <= half and math.abs(z - b.z) <= half and top <= y + 78.0 and (not fz or top * S > fz) then
                fz, nx, ny, nz = top * S, 0.0, 0.0, 1.0
            end
        end
    end
    if not fz then return nil end
    return fz / S, ny, nz, -nx          -- (the scene's y, z, -x are Mario's x, y, z)
end

local function spawn_cap(world, b, m, kind)
    local G = package.loaded["game"]
    local data = H.actor_data and H.actor_data("cap_" .. kind)
    local function wear() if G and G.give_cap then pcall(G.give_cap, kind) end end
    if not data then wear(); return end
    local yaw = m.facing or 0
    local c = { kind = kind, x = b.x, y = b.y, z = b.z, vy = 20.0, fvel = 3.0, yaw = yaw, face = yaw, timer = 0,
                g = CAP_PHYS[kind].g, buoy = CAP_PHYS[kind].b, sq = nil, pitch = 0.0, roll = 0.0 }
    local sx, sy, sz = to_scene(c.x, c.y, c.z)
    c.inst = lib.make_instance(world, data, { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z }, -yaw * 360.0 / 65536.0, 1.0)
    if not c.inst then wear(); return end
    c.inst.moves = true
    if kind == "vanish" then pcall(lib.see_through, world, c.inst, 150.0 / 255.0) end
    c.prev = { c.x, c.y, c.z }
    caps[#caps + 1] = c
    log("box: the %s cap comes out", kind)
end

local function drop_cap(c)
    c.gone = true
    if c.inst then lib.destroy(c.inst.actor); c.inst = nil end
end

-- one frame of a cap (bhv_wing_vanish_cap_loop / bhv_metal_cap_loop); m: the athlete
local function cap_step(c, m)
    c.timer = c.timer + 1
    local G = package.loaded["game"]
    local x0, y0, z0 = c.x, c.y, c.z
    local vx, vz = c.fvel * sins(c.yaw), c.fvel * coss(c.yaw)
    -- a wall where it is going: pushed out of it and turned away (obj_find_wall, radius 80, at half its height)
    if G and G.wall_near and (vx ~= 0.0 or vz ~= 0.0) then
        local sx, sy, sz = to_scene(x0 + vx, y0 + 40.0, z0 + vz)
        local hit, px, py = G.wall_near(sx, sy, sz, 80.0 * S)
        if hit and (px ~= 0.0 or py ~= 0.0) then
            local wx, wz = py / S, -px / S
            c.x, c.z = x0 + vx + wx, z0 + vz + wz
            local tx, tz = turn_away(vx, vz, wx, wz)
            c.yaw = yaw_of(tx, tz)
        end
    end
    -- (rising, no floor over it taken for one - Mario 64's 78 up let it pop up onto the top of a slab over its box and
    -- lie there, in the ceiling: "cap stuck in ceiling", WDW town's metal cap, 2026-10-28)
    local fy, fnx, fny, fnz = cap_floor(x0 + vx, (c.vy > 0.0) and (y0 - 78.0) or y0, z0 + vz)
    local free = true
    if not fy then
        c.yaw = s16(c.yaw + 0x8000)                    -- (no floor at all: turned round, as Mario 64's)
        free = false
    elseif fny < 0.5 and fy > c.y then
        local tx, tz = turn_away(vx, vz, fnx, fnz)     -- (a floor too steep, above it: a wall)
        c.yaw = yaw_of(tx, tz)
        free = false
    end
    local on_floor = false
    if free then
        local wsx, wsy = to_scene(x0 + vx, 0, z0 + vz)
        local wz = G and G.water_at and G.water_at(wsx, wsy)
        local wy = wz and wz / S
        local k = (fnx * fnx + fnz * fnz) / (fnx * fnx + fny * fny + fnz * fnz)
        if wy and wy > c.y then
            local net = (1.0 - c.buoy) * -c.g
            c.vy = max(-75.0, min(75.0, c.vy - net))
            c.y = c.y + c.vy
            if c.y < fy then c.y = fy; c.vy = (c.vy < -17.5) and -c.vy / 2.0 or 0.0 end
            if c.fvel > 12.5 and wy + 30.0 > c.y and wy - 30.0 < c.y then c.vy = -c.vy end
            if c.y >= fy and c.y < fy + 37.0 then
                on_floor = true
                vx, vz = vx + fnx * k * net * 2.0, vz + fnz * k * net * 2.0
            end
            if abs(vx) < 1e-6 then vx = 0.0 end
            if abs(vz) < 1e-6 then vz = 0.0 end
            if abs(c.vy) < 1e-6 then c.vy = 0.0 end
            if vx ~= 0.0 or vz ~= 0.0 then c.yaw = yaw_of(vx, vz) end
            c.fvel = sqrt(vx * vx + vz * vz) * 0.8
            c.vy = c.vy * 0.8
        else
            c.vy = max(-75.0, min(75.0, c.vy - c.g))
            c.y = c.y + c.vy
            -- (and not up through a ceiling: stopped with its top under it, to fall from there)
            if c.vy > 0.0 and G and G.ceil_z then
                local csx, csy, csz = to_scene(x0, y0, z0)
                local cz = G.ceil_z(csx, csy, csz + 1.0)
                if cz and c.y + 45.0 > cz / S then c.y, c.vy = max(y0, cz / S - 45.0), 0.0 end
            end
            if c.y < fy then c.y = fy; c.vy = (c.vy < -17.5) and -c.vy / 2.0 or 0.0 end
            if c.y >= fy and c.y < fy + 37.0 then
                on_floor = true
                vx, vz = vx + fnx * k * c.g * 2.0, vz + fnz * k * c.g * 2.0
                if abs(vx) < 1e-6 then vx = 0.0 end
                if abs(vz) < 1e-6 then vz = 0.0 end
                if vx ~= 0.0 or vz ~= 0.0 then c.yaw = yaw_of(vx, vz) end
                c.fvel = sqrt(vx * vx + vz * vz) * ((fny < 0.2) and 0.0 or 0.999)
            end
        end
    end
    c.x, c.z = c.x + c.fvel * sins(c.yaw), c.z + c.fvel * coss(c.yaw)
    c.face = s16(c.face + c.fvel * 128.0)
    -- lying on the floor: tilted with it (obj_orient_graph)
    c.normal = on_floor and { fnx, fny, fnz } or nil
    local grounded = fy and free and floor(c.y) == floor(fy)
    if c.kind ~= "metal" and grounded and c.vy ~= 0.0 then
        c.sq, c.vy = 0, 0.0                                 -- (a bounce: it stops dead and squashes)
    end
    if c.sq then
        c.sq = c.sq + 0x2000
        c.squash = coss(c.sq) * 0.3 + 0.7
        if c.sq >= 0x10000 then c.sq, c.squash = nil, 1.0 end
    end
    -- touched: his (interact_cap)
    if c.timer > 20 then
        local dx, dz = m.x - c.x, m.z - c.z
        -- (not without his own cap on: the power-up cap stays where it is - G.capless)
        if dx * dx + dz * dz < (80.0 + 37.0) ^ 2 and m.y - 120.0 < c.y + 80.0 and m.y + 120.0 > c.y
            and not (G and G.capless and G.capless()) then
            drop_cap(c)
            if G and G.give_cap then pcall(G.give_cap, c.kind) end
            log("box: the %s cap picked up", c.kind)
            return
        end
    end
    -- (cap_despawn: from frame 300 it flickers, and at 340 it is gone)
    if c.timer > 300 then
        if c.timer >= 340 then drop_cap(c); log("box: the %s cap went", c.kind); return end
        c.hide = (c.timer % 2) ~= 0
    end
end

local function cap_render(c, a)
    if not c.inst then return end
    local pr = c.prev
    local sx, sy, sz = to_scene(pr[1] + (c.x - pr[1]) * a, pr[2] + (c.y - pr[2]) * a, pr[3] + (c.z - pr[3]) * a)
    local yaw = -c.face * 360.0 / 65536.0
    local pitch, roll = 0.0, 0.0
    if c.normal then
        -- (Mario's normal in the scene's axes, then tipped forward and sideways by it)
        local nx, ny, nz = -c.normal[3], c.normal[1], c.normal[2]
        local ry = math.rad(yaw)
        local fwd = nx * cos(ry) + ny * sin(ry)
        local side = -nx * sin(ry) + ny * cos(ry)
        pitch, roll = -math.deg(atan(fwd, nz)), math.deg(atan(side, nz))
    end
    local actor = c.inst.actor
    pcall(function()
        c.nudge = (c.nudge == 0.02) and 0.0 or 0.02
        actor:K2_TeleportTo({ X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z + c.nudge }, { Pitch = pitch, Yaw = yaw, Roll = roll })
    end)
    local sq = c.squash or 1.0
    if sq ~= (c.shown_sq or 1.0) then
        c.shown_sq = sq
        pcall(function() actor:SetActorScale3D({ X = 1.0, Y = 1.0, Z = sq }) end)
    end
    local hide = c.hide or false
    if hide ~= (c.shown_hide or false) then
        c.shown_hide = hide
        pcall(function() actor:SetActorHiddenInGame(hide) end)
    end
    -- (the metal cap in Mario 64's chrome, laid again 15 times a second as it and the camera turn: lib.chrome)
    if c.kind == "metal" and not hide and os.clock() - (c.chrome_at or -1.0) >= 1.0 / 15.0 then
        c.chrome_at = os.clock()
        pcall(function()
            local world = lib.world()
            local mid = lib.get_mid(world, "opaque", "actors__mario_cap__mario_cap_metal.rgba16")
            for i, p in ipairs(c.inst.data.parts) do
                local comp = c.inst.comps[i]
                if comp then for _, sec in ipairs(p.sections) do pcall(lib.chrome, world, comp, sec, mid) end end
            end
        end)
    end
end

function M.clear()
    for _, b in ipairs(M.list) do if b.inst then lib.destroy(b.inst.actor) end end
    for _, c in ipairs(caps) do drop_cap(c) end
    M.list, M.held, caps = {}, nil, {}
end

function M.forget() M.list, M.held, caps = {}, nil, {} end

-- ------------------------------------------------------------ breaking
local function give(b, world, m)
    local g = b.give or {}
    local sx, sy, sz = to_scene(b.x, b.y + 60.0 * (b.scale or 1.0), b.z)
    if (g.coins or 0) > 0 and H.spawn_coin then
        for _ = 1, g.coins do pcall(H.spawn_coin, sx, sy, sz) end
    end
    local G = package.loaded["game"]
    if g.oneup and G and G.add_pickup then
        -- (exclamation_box_spawn_contents: the 1-up goes the way he faces, out in its loop - one_up_loop_in_air - then
        -- walks on or runs from him. It was left hanging where the box had been)
        local dir
        pcall(function() local a = math.rad(lib.pawn():K2_GetActorRotation().Yaw); dir = { math.cos(a), math.sin(a) } end)
        pcall(G.add_pickup, { kind = "oneup", pos = { sx, sy, sz }, pop = (g.oneup == "away") and "away" or "walk", dir = dir })
        sound("oneup_appear", 1.0)
    end
    if g.star and G and G.add_star then
        -- (bhv_spawned_star_init: out of the box and over to 250 above Mario's feet, where he stands - it was left 150 cm
        -- over the box, out of reach over the floating island's: "the star in the box on the island spawns to far up so
        -- you cant grab it", 2026-10-16)
        local tx, ty, tz = sx, sy, sz + 150.0
        if m and m.x and m.y and m.z then tx, ty, tz = to_scene(m.x, m.y - 120.0 + 250.0, m.z) end
        pcall(G.add_star, world, { kind = "star", pos = { tx, ty, tz }, id = g.star, from = { sx, sy, sz } })
        sound("star_appears", 1.0)
    end
    if g.cap then
        local ok, err = pcall(spawn_cap, world, b, m or {}, g.cap)
        if not ok then
            log("box: cap %s", tostring(err))
            if G and G.give_cap then pcall(G.give_cap, g.cap) end
        end
        b.respawn = 300             -- (exclamation_box_act_5: a cap's box is back after 300 frames)
    end
    if g.shell and G and G.give_shell then
        pcall(G.give_shell, sx, sy, sz)
        -- (and a shell's box is back after 300 frames too, as a cap's - Mario 64's is gone for good: "shell box doesnt
        -- respawn", 2026-10-19)
        b.respawn = 300
    end
end

local hits                      -- (a thrown box's targets: below)
local function smash(b, world, m, why)
    if b.action == "broken" or b.outline then return end
    b.action = "broken"
    if M.held == b then M.held = nil end
    sound("box_break", 1.0)
    -- (in a white puff: obj_explode_and_spawn_coins / spawn_mist_particles - envfx.lua)
    local EF = package.loaded["envfx"]
    if EF and EF.poof then
        local sx, sy, sz = to_scene(b.x, b.y + 50.0 * (b.scale or 1.0), b.z)
        pcall(EF.poof, sx, sy, sz, math.max(0.7, (b.scale or 1.0)))
    end
    give(b, world, m)
    if b.inst then
        lib.destroy(b.inst.actor)       -- (and its collision with it)
        b.inst = nil
    end
    log("box %s broken (%s)", b.type, why)
end

-- what a thrown box at (its middle) meets: the reach of its own half size, Mario units
local HIT_REACH = 50.0
function hits(b, world, m)
    local cx, cy, cz = b.x, b.y + 40.0 * (b.scale or 1.0) / 0.4, b.z
    local n = 0
    for _, o in ipairs(M.list) do
        if o ~= b and o.action ~= "broken" and not o.outline and o.action ~= "held" then
            local s = o.scale or 1.0
            local half, top = 100.0 * s, 200.0 * s
            if o.ex then half, top = 50.0 * s, 104.0 * s end
            local dx, dz = cx - o.x, cz - o.z
            if abs(dx) < half + HIT_REACH and abs(dz) < half + HIT_REACH and cy > o.y - HIT_REACH and cy < o.y + top + HIT_REACH then
                smash(o, world, m, "hit by a thrown box")
                n = n + 1
            end
        end
    end
    local EN = package.loaded["enemies"]
    if EN and EN.hit_at then
        local ok, k = pcall(EN.hit_at, cx, cy, cz, HIT_REACH, b.yaw, m)
        if ok and k then n = n + k end
    end
    local BO = package.loaded["bobomb"]
    if BO and BO.hit_at then
        local ok, k = pcall(BO.hit_at, cx, cy, cz, HIT_REACH)
        if ok and k then n = n + k end
    end
    local G = package.loaded["game"]
    if G and G.goomba_hit_at then
        local sx, sy, sz = to_scene(cx, cy, cz)
        local ok, k = pcall(G.goomba_hit_at, sx, sy, sz, HIT_REACH * S + 30.0)
        if ok and k then n = n + k end
    end
    return n
end

-- ------------------------------------------------------------ the athlete
local function attack_of(pawn)
    local name, addr = nil, nil
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        if not (ai and ai:IsValid()) then return end
        local mt = ai:GetCurrentActiveMontage()
        if mt and mt:IsValid() then name, addr = mt:GetFName():ToString(), mt:GetAddress() end
    end)
    if not (name and (name:find("Attack") or name:lower():find("kick") or name:lower():find("push"))) then return nil end
    local air = false
    pcall(function() air = pawn.CharacterMovement:IsFalling() end)
    return { name = name, addr = addr, air = air }
end

local acc = 0.0
local last_attack, pending = nil, nil

-- The crazy box ridden (mario_actions_airborne.c act_crazy_box_bounce): three bounces, 45, 60 and 100 a frame up -
-- as high as Mario's own under his 4 a frame fall, under STORROR's - and at least 32, 36 and 48 a frame along his
-- way; at the third landing it breaks. No fall's harm on its landings (act_crazy_box_bounce never checks one): the top
-- of his fall (game.lua G.peak) kept with him all the while.
local CRAZY = { up = { 45.0, 60.0, 100.0 }, fwd = { 32.0, 36.0, 48.0 } }
local function crazy_launch(b, pawn)
    local i = b.n
    local g = 980.0
    pcall(function() g = -pawn.CharacterMovement:GetGravityZ() end)
    if g < 100.0 then g = 980.0 end
    local h = CRAZY.up[i] * CRAZY.up[i] / 8.0 * S
    local vz = sqrt(2.0 * g * h)
    local yaw = 0.0
    pcall(function() yaw = pawn:K2_GetActorRotation().Yaw * pi / 180.0 end)
    local fx, fy = cos(yaw), sin(yaw)
    local along = 0.0
    pcall(function() local v = pawn:GetVelocity(); along = v.X * fx + v.Y * fy end)
    local fwd = max(along, CRAZY.fwd[i] * 30.0 * S)
    -- (by hand, falling and his speed set, as game.lua's lava boost: STORROR's athlete takes no LaunchCharacter on his
    -- feet - it left him where he was and the three bounces went by in half a second)
    local G = package.loaded["game"]
    if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
    pcall(function()
        local cm = pawn.CharacterMovement
        cm:SetMovementMode(3, 0)
        cm.Velocity = { X = fx * fwd, Y = fy * fwd, Z = vz }
    end)
    sound("boing2", 1.0)
    b.ride_t, b.left_ground, b.odd, b.reset_t, b.reset_low, b.fell = 0, false, 0, 0, false, false
    log("crazy box: bounce %d", i)
end
local function crazy_start(b, m)
    local pawn = lib.pawn()
    if not pawn or M.held then return end
    b.action, b.n, M.held = "ride", 1, b
    -- (in his hands: not solid, and the small box - cur_obj_set_model(MODEL_BREAKABLE_BOX_SMALL))
    if b.pmc then pcall(function() b.pmc:SetCollisionEnabled(0) end) end
    pcall(function() b.inst.actor:SetActorScale3D({ X = 0.4, Y = 0.4, Z = 0.4 }) end)
    b.scale = 0.4
    crazy_launch(b, pawn)
end
local function crazy_ride(b, m, world)
    local pawn = lib.pawn()
    b.ride_t = (b.ride_t or 0) + 1
    b.x, b.y, b.z = m.x + sins(m.facing) * 70.0, m.y - 40.0, m.z + coss(m.facing) * 70.0
    b.yaw = m.facing
    if not pawn then return end
    local mode, vz, near, low = 3, 0.0, false, false
    local G = package.loaded["game"]
    pcall(function()
        local cm = pawn.CharacterMovement
        mode, vz = cm.MovementMode, cm.Velocity.Z
        local l = pawn:K2_GetActorLocation()
        local half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
        local fz = G and G.floor_z and G.floor_z(l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z)
        near = fz ~= nil and (l.Z - OFFSET.Z - half) - fz < 120.0
        low = fz ~= nil and (l.Z - OFFSET.Z - half) - fz < 35.0
    end)
    if vz < -100.0 then b.fell = true end
    if G then pcall(function() G.peak = pawn:K2_GetActorLocation().Z end) end
    if G then G.crazy_ride = os.clock() + 0.2 end       -- (no sand under his bounces: game.lua update_floors)
    -- (on the way down, STORROR's fall forgotten now and then and once more near the ground, as climb.lua's pole kick
    -- off has it: a long drop is its fall ragdoll - "using the box makes the player ragdoll", 2026-10-23)
    if vz < 0.0 and G and G.parkour_reset then
        b.reset_t = (b.reset_t or 0) + 1
        if b.reset_t >= 6 or (near and not b.reset_low) then
            b.reset_t = 0
            if near then b.reset_low = true end
            pcall(G.parkour_reset, pawn)
        end
    end
    if mode == 3 then b.left_ground = true end
    -- (landed: on his feet - walking. STORROR taking hold of a ledge or a wall on the way is no landing: a moment of
    -- that and the ride is over there, the box broken; the bounces had gone off early in mid air)
    -- (or down on a floor he slides on - the pyramid's faces, a sand bank - or sinks in: G.floor has them all, and Mario
    -- 64 lands on any floor; "crazy box didnt triple bounce on quicksand or pyramid", 2026-10-23)
    local landed = b.left_ground and b.ride_t > 3 and (mode == 1 or (mode == 3 and b.fell and low and vz <= 10.0))
    if b.left_ground and mode ~= 1 and mode ~= 3 then b.odd = (b.odd or 0) + 1 else b.odd = 0 end
    if landed and b.n < 3 then
        b.n = b.n + 1
        crazy_launch(b, pawn)
    elseif landed or b.odd > 15 or b.ride_t > 300 then
        M.held = nil
        if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
        smash(b, world, m, landed and "the third bounce" or "the ride cut short")
    end
end

local function step(b, m, world, attack, fresh)
    if b.action == "broken" then return end
    local s = b.scale or 1.0
    if b.action == "held" then
        b.x, b.y, b.z = m.x + sins(m.facing) * 110.0, m.y + 20.0, m.z + coss(m.facing) * 110.0
        b.yaw = m.facing
        if fresh then
            b.action, b.fvel, b.vy, b.ground, b.timer = "thrown", 35.0, 25.0, false, 0
            M.held = nil
            log("box thrown")
        end
        return
    end
    if b.action == "ride" then return crazy_ride(b, m, world) end
    if b.action == "thrown" then
        b.timer = b.timer + 1
        b.x, b.z = b.x + b.fvel * sins(b.yaw), b.z + b.fvel * coss(b.yaw)
        b.vy = b.vy - 3.0
        b.y = b.y + b.vy
        -- (what it flies into: goombas, enemies, bob-ombs and other boxes - beaten, set off or broken, and it breaks with
        -- them: "when you throw it at enemies or boxes they dont break die", 2026-10-17)
        -- (looked for first: a big box's top is floor, and thrown at one it broke on that as on the ground, the big box
        -- left whole - "throwing small box at big box should break it", 2026-10-23)
        if b.timer > 1 and hits(b, world, m) > 0 then smash(b, world, m, "hit something"); return end
        -- (the ground under it, no higher than 50 over it: looked for up to 350 over it, the platform over SSL's cork boxes,
        -- 4 m up, was taken for its floor and it broke a moment out of his hands - "cant break big boxes with little box
        -- still", 2026-10-23)
        local fy = floor_y(b.x, b.y - 200.0, b.z)
        if (fy and b.y <= fy and b.timer > 2) or b.timer > 120 then smash(b, world, m, "thrown") end
        return
    end
    if b.jumping then
        -- (jumping_box_act_0: on the ground 30 to 90 frames, then a hop straight up of 15 to 20 - no way along: it
        -- hopped 6 a frame a way of its own each time and wandered off its island out over the lava, "theres a crazy
        -- box out in the middle of the lava", 2026-10-19)
        b.timer = b.timer + 1
        b.hop_wait = b.hop_wait or math.random(30, 90)
        if b.ground then
            b.hop_wait = b.hop_wait - 1
            if b.hop_wait < 0 then b.vy, b.ground, b.hop_wait = 15.0 + math.random() * 5.0, false, math.random(30, 90) end
        end
        if not b.ground then
            b.vy = b.vy - 3.0
            b.y = b.y + b.vy
            local fy = floor_y(b.x, b.y + 100.0, b.z)
            if fy and b.y <= fy then b.y, b.vy, b.ground = fy, 0.0, true end
        end
    end
    local half, top = (b.ex and 50.0 or 100.0) * s, (b.ex and 104.0 or 200.0) * s
    if b.ex then half, top = 50.0, 104.0 end
    local base = b.ex and (b.y + 2.0) or b.y
    local dx, dz = m.x - b.x, m.z - b.z
    local d2 = dx * dx + dz * dz
    -- (the crazy box stood on: off he goes)
    if b.jumping and abs(dx) < half + 20.0 and abs(dz) < half + 20.0 and m.y - 120.0 > base + top - 30.0
        and m.y - 120.0 < base + top + 40.0 and not m.rising then
        crazy_start(b, m)
        return
    end
    -- (swimming he cannot break one - Mario 64's Mario cannot punch or kick in the water, nor jump up into a box from it:
    -- "able to push ! blocks in water", 2026-10-31)
    -- (under the metal cap he walks the bottom and may: "you should not be able to push ! blocks underwater unless you
    -- have metal cap", 2026-10-31)
    local CP = package.loaded["caps"]
    local metal = CP and CP.on and CP.on("metal")
    if m.under and not metal then return end
    -- an attack within reach
    if fresh and d2 < (half + 140.0) ^ 2 and m.y > base - 160.0 and m.y < base + top + 200.0 then
        if b.jumping and not attack.air then
            crazy_start(b, m)                       -- (taken hold of: off he goes)
            return
        end
        if b.small and not attack.air then
            if not M.held then
                b.action, M.held = "held", b
                -- (not solid in his hands or in the air: it would shove him, and catch on what it hits)
                if b.pmc then pcall(function() b.pmc:SetCollisionEnabled(0) end) end
                log("box picked up")
            end
            return
        end
        smash(b, world, m, attack.air and "kicked" or "pushed")
        return
    end
    -- a ! box hit from below: his head comes up into it
    if b.ex and m.rose and d2 < (half + 30.0) ^ 2 and m.head > base - 45.0 and m.head < base + 60.0 then
        smash(b, world, m, "hit from below")
    end
end

local function render(b, a)
    if not b.inst then return end
    local pr = b.prev
    local x, y, z = pr[1] + (b.x - pr[1]) * a, pr[2] + (b.y - pr[2]) * a, pr[3] + (b.z - pr[3]) * a
    local sx, sy, sz = to_scene(x, y, z)
    lib.set_pose(b.inst, sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z, -b.yaw * 360.0 / 65536.0)
end

-- outlines whose switch has just been pressed: made again, solid (Mario 64's boxes look at the save each frame)
local function solidify(world)
    local MN = _G.MENU
    if not (MN and MN.has_flag) then return end
    for i = #M.list, 1, -1 do
        local b = M.list[i]
        if b.outline then
            local flag = ({ [0] = "cap_wing", [1] = "cap_metal", [2] = "cap_vanish" })[b.o.content or 3]
            if flag and MN.has_flag(flag) then
                table.remove(M.list, i)
                lib.destroy(b.inst and b.inst.actor)
                pcall(M.add, world, b.o)
            end
        end
    end
end

function M.update(dt, px, py, pz)
    if #M.list == 0 then return end
    local world = lib.world()
    M.flag_t = (M.flag_t or 0.0) + dt
    if M.flag_t > 0.5 then M.flag_t = 0.0; pcall(solidify, world) end
    local pawn = lib.pawn()
    local sx, sy, sz = px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z
    local m = { x = sy / S, y = sz / S, z = -sx / S }
    m.head = m.y + 120.0
    -- (under the water: swimming by either of the two marks of it, or the water's top over his chest - the game's own
    -- G.swim alone missed him under it: "you should not be able to push ! blocks underwater unless you have metal cap",
    -- 2026-10-31, said twice)
    do
        local GS = package.loaded["game"]
        local SW = package.loaded["swim"]
        m.under = (GS and GS.swim) or (SW and SW.active and SW.active()) or false
        if not m.under and GS and GS.water_at then
            local top = GS.water_at(sx, sy)
            if top and top > sz + 40.0 then m.under = true end
        end
    end
    m.facing, m.rising = 0, false
    pcall(function() m.facing = s16((180.0 - pawn:K2_GetActorRotation().Yaw) * 65536.0 / 360.0) end)    -- (he faces +X)
    pcall(function() m.rising = pawn:GetVelocity().Z > 150.0 end)
    -- (and rising a moment ago, for a ! box's hit from below: his head into its underside stops him, and that frame he is
    -- rising no more - the hit went unseen, "this box doesnt drop anything?", 2026-10-28)
    if m.rising then M.rise_at = os.clock() end
    m.rose = m.rising or (M.rise_at ~= nil and os.clock() - M.rise_at < 0.25)
    local attack = pawn and attack_of(pawn) or nil
    if attack ~= nil and attack.addr ~= last_attack then pending = attack end
    last_attack = attack and attack.addr or nil
    acc = acc + dt
    local n = 0
    local again = nil
    while acc >= STEP and n < 4 do
        acc = acc - STEP
        n = n + 1
        for i = #caps, 1, -1 do
            local c = caps[i]
            c.prev[1], c.prev[2], c.prev[3] = c.x, c.y, c.z
            local ok, err = pcall(cap_step, c, m)
            if not ok then log("box: cap %s", tostring(err)); drop_cap(c) end
            if c.gone then table.remove(caps, i) end
        end
        for _, b in ipairs(M.list) do
            if b.action == "broken" and b.respawn then
                b.respawn = b.respawn - 1
                if b.respawn <= 0 then b.respawn = nil; again = again or {}; again[#again + 1] = b end
            end
            b.prev[1], b.prev[2], b.prev[3] = b.x, b.y, b.z
            local dx, dz = m.x - b.x, m.z - b.z
            if b.action == "held" or b.action == "thrown" or dx * dx + dz * dz < 3000.0 * 3000.0 then
                local ok, err = pcall(step, b, m, world, pending or attack, pending ~= nil)
                if not ok and not b.broken_log then b.broken_log = true; log("box: %s", tostring(err)) end
            end
        end
        pending = nil
    end
    if acc > STEP then acc = 0.0 end
    -- (cap boxes back where they were)
    for _, b in ipairs(again or {}) do
        for i = #M.list, 1, -1 do if M.list[i] == b then table.remove(M.list, i) end end
        local ok, err = pcall(M.add, world, b.o)
        log("box: the %s box is back%s", b.give and b.give.cap or "?", ok and "" or (" - " .. tostring(err)))
    end
    local a = acc / STEP
    for _, c in ipairs(caps) do pcall(cap_render, c, a) end
    for _, b in ipairs(M.list) do
        if b.inst and (b.action ~= "idle" or b.jumping or not b.placed) then
            pcall(render, b, a)
            b.placed = true
        end
    end
end

-- (tests: break box i as an attack would)
function M.test_break(i)
    local b = M.list[i]
    if b then smash(b, lib.world(), { x = b.x, y = b.y, z = b.z }, "test") end
end

return M
