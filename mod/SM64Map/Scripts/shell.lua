-- Koopa shell surfing (koopa_shell.inc.c; interaction.c interact_koopa_shell; mario_actions_moving.c
-- act_riding_shell_ground / update_shell_speed). The shell out of LLL's ! box (acts 5 and 6) lies spinning where it
-- fell; walked into or landed on, it has the athlete up on it and away: it never stops (24 a frame at the least, up to
-- 64 with the stick pushed all the way), turns toward the stick's way (the camera's) 0x800 a frame, carries him over
-- lava and water unharmed and off ledges. Into a wall, or jumped off, the ride is over and the shell bursts (Mario 64:
-- INT_STATUS_STOP_RIDING). He rides it in the engine's flying mode a little over its top, STORROR's controls off and
-- its in-the-air crouch his stance (a pad under him for STORROR to stand on was tried: a moving base flung him off);
-- the jump button (A) jumps with it under him, as Mario 64's ACT_RIDING_SHELL_JUMP, and he lands still riding; Y gets
-- him off ("you cant jump while shell riding. Make A the jump button and Y the button to get off the shell",
-- 2026-10-17).
-- Mario 64 units at its 30 frames a second. (The box gave a coin, 2026-10-15.)
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET
local M = {}

local U = 0.75
local LOCK = "SM64Shell"
local TOP = 22.0                -- cm from the ground up to the shell's top, where he stands (lava 12 under him: no harm)
local SCALE = 1.4               -- (the shell a little bigger under the athlete than under Mario)

local st = nil                  -- { world, ctx, shells = {...}, ride }

local function sfx(name, v) local S = package.loaded["sfx"]; if S then pcall(S.play, name, v) end end
local function sins(a) return math.sin(a * math.pi / 32768.0) end
local function coss(a) return math.cos(a * math.pi / 32768.0) end
local function s16(a) a = math.floor(a) % 65536; if a >= 32768 then a = a - 65536 end; return a end

local function locomotion(pawn, on, r)
    local pc = lib.controller()
    pcall(function() pc:SetIgnoreMoveInput(not on) end)
    pcall(function() if on then pawn:EnableInput(pc) else pawn:DisableInput(pc) end end)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            local cname = o:GetClass():GetFName():ToString()
            if cname == "LocomotionComponent" then
                o:EnableLocomotionInputCallback(FName(LOCK), on)
                o:EnableAdvancedLocomotionInput(FName(LOCK), on)
            elseif cname == "ParkourComponent" then
                o:ClearInputQueue()
                o:EnableAllParkourInputs(FName(LOCK), on)
            end
        end
    end)
    local cm = pawn.CharacterMovement
    if not on then
        pcall(function()
            local anim = pawn.Mesh:GetAnimInstance()
            r.pa, r.root_motion = anim, anim.RootMotionMode
            anim:SetRootMotionMode(1)
        end)
        pcall(function()
            r.max_fly, r.brake = cm.MaxFlySpeed, cm.BrakingDecelerationFlying
            cm:SetMovementMode(5, 0)
            cm.MaxFlySpeed, cm.BrakingDecelerationFlying = 4000.0, 0.0
        end)
    elseif r then
        pcall(function() if r.pa and r.pa:IsValid() then r.pa:SetRootMotionMode(r.root_motion or 2) end end)
        pcall(function()
            if r.max_fly then cm.MaxFlySpeed = r.max_fly end
            if r.brake then cm.BrakingDecelerationFlying = r.brake end
        end)
    end
end

-- the stick, camera-relative: its way (Mario 64 yaw) and how far (0..1), or nil
local function intended()
    if M.test then
        if not M.test.x and not M.test.y then return nil end
        local x, y = M.test.x or 0.0, M.test.y or 0.0
        local cyaw = 0.0
        pcall(function() cyaw = lib.controller():GetControlRotation().Yaw end)
        return s16((180.0 - (cyaw + math.deg(math.atan(x, y)))) * 65536.0 / 360.0), math.min(1.0, math.sqrt(x * x + y * y))
    end
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
    local mag = math.sqrt(x * x + y * y)
    if mag < 0.2 then return nil end
    local cyaw = 0.0
    pcall(function() cyaw = pc:GetControlRotation().Yaw end)
    local ue = cyaw + math.deg(math.atan(x, y))                     -- (the way in the scene, degrees)
    return s16((180.0 - ue) * 65536.0 / 360.0), math.min(1.0, mag)  -- (Mario 64's yaw: 0 along +z)
end

-- ------------------------------------------------------------ the scene's shells
function M.load(world, ctx)
    M.clear()
    st = { world = world:GetAddress(), ctx = ctx, shells = {} }
end

-- a shell lying at (x, y, z): scene cm, its floor
function M.add(x, y, z)
    local s = st
    if not s then return end
    local w = lib.world()
    local data = s.ctx.actor_data("koopa_shell")
    if not (w and data) then return end
    local inst = lib.make_instance(w, data, { X = x + OFFSET.X, Y = y + OFFSET.Y, Z = z + OFFSET.Z }, 0.0, SCALE)
    if not inst then return end
    inst.moves = true
    local sh = { x = x, y = y, z = z, inst = inst, t = 0.0, cool = 0.6 }
    s.shells[#s.shells + 1] = sh
    log("shell: one lies at %.0f %.0f %.0f", x, y, z)
    return sh
end

-- the shells lying free - not gone, not under him: for a Koopa knocked out of his to run back to (enemies.lua
-- M.koopa_bare_step, as koopa_unshelled_act_run finds the nearest bhvKoopaShell)
function M.free()
    local out = {}
    if not st then return out end
    for _, sh in ipairs(st.shells) do
        if not sh.gone and not (st.ride and st.ride.shell == sh) then out[#out + 1] = sh end
    end
    return out
end

-- a shell taken back by a Koopa diving into it: gone, without its burst (koopa_unshelled_act_dive)
function M.take(sh)
    if not st or not sh or sh.gone or (st.ride and st.ride.shell == sh) then return false end
    sh.gone = true
    pcall(function() sh.inst.actor:SetActorHiddenInGame(true) end)
    lib.destroy(sh.inst.actor)
    return true
end

local function burst(sh)
    pcall(function() sh.inst.actor:SetActorHiddenInGame(true) end)
    sh.gone = true
    sfx("en_shrink", 1.0)
    local G = package.loaded["game"]
    if G and G.puff then pcall(G.puff, sh.x, sh.y, sh.z + 30.0) end
end

local function stop_ride(s, pawn, why, hop)
    local r = s.ride
    s.ride = nil
    if not r then return end
    local G = package.loaded["game"]
    if pawn then
        locomotion(pawn, true, r)
        pcall(function()
            local cm = pawn.CharacterMovement
            cm:SetMovementMode(3, 0)
            local on = hop and r.v * U * 30.0 * 0.6 or 0.0
            local a = r.yaw
            cm.Velocity = { X = -coss(a) * on, Y = sins(a) * on, Z = hop and 520.0 or 0.0 }
        end)
        if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
    end
    if G and G.carried == "shell" then G.carried = nil end
    burst(r.shell)
    -- (stop_shell_music: the course's own tune again)
    local MU = package.loaded["music"]
    if MU and MU.play and G and G.data and not (G.warping or G.pending) then pcall(MU.play, G.data.music) end
    log("shell: off (%s)", why)
end

function M.clear()
    local s = st
    if not s then return end
    local w = lib.world()
    local here = w and w:GetAddress() == s.world
    if s.ride then
        local G = package.loaded["game"]
        if G and G.carried == "shell" then G.carried = nil end
        local pawn = lib.pawn()
        if pawn then
            locomotion(pawn, true, s.ride)
            pcall(function() pawn.CharacterMovement:SetMovementMode(3, 0) end)
        end
        s.ride = nil
    end
    if here then for _, sh in ipairs(s.shells) do lib.destroy(sh.inst.actor) end end
    st = nil
end

function M.forget()
    if st and st.ride then local G = package.loaded["game"]; if G and G.carried == "shell" then G.carried = nil end end
    st = nil
end

function M.riding() return st ~= nil and st.ride ~= nil end

-- the ground under (x, y) at or below zmax - the level's, or a platform's (the seesaw and the other moving ones,
-- platforms.lua) - or the water's surface over it (scene cm), or nil
local function ground(s, x, y, zmax)
    local fz = s.ctx.floor(x, y, zmax)
    local PL = package.loaded["platforms"]
    if PL and PL.floor_under then
        local ok, pz = pcall(PL.floor_under, x, y, zmax)
        if ok and pz and (not fz or pz > fz) then fz = pz end
    end
    local wz = s.ctx.water and s.ctx.water(x, y)
    if wz and (not fz or wz > fz) and wz <= zmax + 100.0 then return wz end
    return fz
end

-- Only a wall bursts it ("the shell keeps breaking make sure it only breaks if you hit a wall. no slide areas or moving
-- platforms like the seesaw", 2026-10-17): a wall of the level across its way at its own height (game.lua's walls);
-- the ground ahead rising is climbed - up to CLIMB a step, more at speed (slopes and slides) - and a step up higher
-- than that, with no wall there, only stops it. No ground at all ahead: off it goes into the air, and falls.
local CLIMB = 45.0
-- A wall across its way from (x0, y0) to (x1, y1) at height z (scene cm): how far along (0..1), and the wall's line
-- there (x1, y1, x2, y2) - or nil. Each wall where it is at that height, leaning as it does (G.wall_at's way): game.lua's
-- wall_cut stands each one upright on its widest line, from its lowest point to its highest - a leaning one's out over
-- open ground there. (game.lua's wall grid: 400 cm cells, a cell's key i * 65536 + j; a cell more all round, for a
-- leaning one's line out past its widest one's cells.)
local function wall_ahead(s, x0, y0, x1, y1, z)
    local G = package.loaded["game"]
    if not (G and G.wall_cut) then return nil end
    if G.walls_for ~= G.data then pcall(G.wall_cut, x0, y0, z, x0, y0, z) end        -- (builds the scene's walls)
    local grid = G.walls
    if type(grid) ~= "table" then return nil end
    local dx, dy = x1 - x0, y1 - y0
    local best, bx1, by1, bx2, by2
    local seen = {}
    local fl = math.floor
    for i = fl(math.min(x0, x1) / 400.0) - 1, fl(math.max(x0, x1) / 400.0) + 1 do
        for j = fl(math.min(y0, y1) / 400.0) - 1, fl(math.max(y0, y1) / 400.0) + 1 do
            local g = grid[i * 65536 + j]
            if g then
                for _, W in ipairs(g) do
                    if not seen[W] and z >= W[5] and z <= W[6] then
                        seen[W] = true
                        local qx, qy, rx, ry
                        local v = W.v
                        if v then
                            for e = 1, 3 do
                                local a, c = v[e], v[e % 3 + 1]
                                if a[3] == z and c[3] == z then qx, qy, rx, ry = a[1], a[2], c[1], c[2]; break end
                                if a[3] ~= c[3] and (a[3] - z) * (c[3] - z) <= 0.0 then
                                    local k = (z - a[3]) / (c[3] - a[3])
                                    local px, py = a[1] + (c[1] - a[1]) * k, a[2] + (c[2] - a[2]) * k
                                    if not qx then qx, qy = px, py
                                    elseif not rx and math.abs(px - qx) + math.abs(py - qy) > 0.01 then rx, ry = px, py end
                                end
                            end
                        else
                            qx, qy, rx, ry = W[1], W[2], W[3], W[4]
                        end
                        if rx then
                            local ex, ey = rx - qx, ry - qy
                            local den = dx * ey - dy * ex
                            if math.abs(den) > 1e-6 then
                                local t = ((qx - x0) * ey - (qy - y0) * ex) / den
                                local u = ((qx - x0) * dy - (qy - y0) * dx) / den
                                if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0 and (not best or t < best) then
                                    best, bx1, by1, bx2, by2 = t, qx, qy, rx, ry
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best, bx1, by1, bx2, by2
end

-- one Mario 64 frame of the ride
local function ride_step(s, pawn)
    local r = s.ride
    local want, mag = intended()
    local target = math.max(24.0, math.min(64.0, (mag or 0.0) * 32.0 * 2.0))
    if r.v <= 0.0 then r.v = r.v + 1.1
    elseif r.v <= target then r.v = r.v + 1.1 - r.v / 58.0
    else r.v = r.v - 1.0 end
    r.v = math.min(64.0, r.v)
    if want then
        local d = s16(want - r.yaw)
        r.yaw = s16(r.yaw + math.max(-0x800, math.min(0x800, d)))
    end
    local step = r.v * U
    local nx, ny = r.x - coss(r.yaw) * step, r.y + sins(r.yaw) * step     -- (Mario 64's z is the scene's -x)
    local base = r.top - TOP
    -- (a wall both at its foot and up at his middle, as Mario 64 tests his walls at 30 and 60: one only low down - a lip,
    -- a kerb, the slanted foot of a slope - burst it under him out on the lava: "the shell breaks randomly", 2026-10-19)
    -- Mario 64's ride bursts it only on a wall it meets head on (act_riding_shell_ground, perform_ground_quarter_step): one
    -- it glances - its way within 30 degrees of the wall's, wallDYaw 60..120 - it goes on along; and in the air
    -- (act_riding_shell_air) a wall only stops it ("shell just got destroyed randomly?", 2026-11-08)
    local hit = wall_ahead(s, r.x, r.y, nx, ny, base + 25.0)
    local _, wx1, wy1, wx2, wy2
    if hit then _, wx1, wy1, wx2, wy2 = wall_ahead(s, r.x, r.y, nx, ny, base + 80.0) end
    if wx1 then
        local ex, ey = wx2 - wx1, wy2 - wy1
        local el = math.sqrt(ex * ex + ey * ey)
        local mx, my = nx - r.x, ny - r.y
        local ml = math.sqrt(mx * mx + my * my)
        local along = (el > 1e-3 and ml > 1e-3) and (ex * mx + ey * my) / (el * ml) or 0.0
        if not r.air and math.abs(along) < 0.866 then
            r.wall = { wx1, wy1, wx2, wy2, along }
            return "wall"
        end
        -- (its step put along the wall's line, if that is clear - else, and in the air, it stays where it is)
        local k = (ex * mx + ey * my) / (el * el)
        local sx, sy = r.x + ex * k, r.y + ey * k
        if r.air or wall_ahead(s, r.x, r.y, sx, sy, base + 25.0) or wall_ahead(s, r.x, r.y, sx, sy, base + 80.0) then
            sx, sy = r.x, r.y
        end
        if r.air then r.v = 0.0 end
        nx, ny = sx, sy
    end
    local climb = math.max(CLIMB, step * 1.7)             -- (up to ~60 degrees at speed)
    local g = ground(s, nx, ny, base + climb)
    if g == nil then
        -- (nothing under it at all within reach: it is in the air over a drop - unless there is ground higher up there,
        -- a step too high: then it stops)
        local hi = ground(s, nx, ny, base + 600.0)
        if hi and hi > base + climb then r.v = 0.0; return nil end
        r.x, r.y = nx, ny
        r.vz = (r.vz or 0.0) - 4.0 * U
        r.top = r.top + r.vz
        r.air = true
        r.fell = (r.fell or 0.0) + math.max(0.0, -r.vz)
        if r.fell > 3000.0 then return "fell" end
        return nil
    end
    r.fell = 0.0
    r.x, r.y = nx, ny
    local gtop = g + TOP
    if not r.air and gtop > r.top then r.top = gtop end      -- (up a slope or onto a step it can climb)
    if r.air or gtop < r.top - 2.0 then
        -- (jumping, or off a ledge: down it comes, Mario 64's 4 a frame more each frame, till it is on the ground again)
        r.vz = (r.vz or 0.0) - 4.0 * U
        r.top = r.top + r.vz
        if r.top <= gtop then
            if r.air then sfx("box_land", 0.6) end
            r.top, r.vz, r.air = gtop, 0.0, false
        end
    else
        r.top, r.vz = gtop, 0.0
    end
    return nil
end

-- the jump button's press (A: once a press), and the get-off button's (Y)
local function jump_pressed(s)
    local down = false
    if M.test then down = M.test.a and true or false
    else
        local P = package.loaded["pad"]
        down = P and P.down and P.down("ok") or false
    end
    local p = down and not s.was_a
    s.was_a = down
    return p
end
local function off_pressed(s)
    local down = false
    if M.test then down = M.test.y and true or false
    else
        local P = package.loaded["pad"]
        down = P and P.down and P.down("skip") or false
    end
    local p = down and not s.was_y
    s.was_y = down
    return p
end

-- (x, y, z): his feet, scene cm (minus OFFSET)
function M.update(dt, pawn, x, y, z)
    local s = st
    if not s or not pawn then return end
    local w = lib.world()
    if not (w and w:GetAddress() == s.world) then st = nil; return end
    local G = package.loaded["game"]
    local jumped = jump_pressed(s)
    local off = off_pressed(s)
    -- (time stopped while a star comes out - G.star_cut, Mario 64's time stop for its cutscene: the ride held where it is,
    -- him on it, and the shells lying about with it, till the camera is back on him. Presses meanwhile are let go by.
    -- "when riding a shell it keeps moving during star spawning", 2026-10-28)
    if G and G.star_cut and not (G.warping or G.pending or G.dying) then
        if s.ride then pcall(function() pawn.CharacterMovement.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 } end) end
        return
    end
    if s.ride then
        local r = s.ride
        if off then stop_ride(s, pawn, "got off", true); return end
        -- (A: up it goes with him on it - set_mario_y_vel_based_on_fspeed(m, 42, 0.25) - from the ground only)
        if jumped and not r.air then
            r.air, r.vz = true, (42.0 + 0.25 * r.v) * U
            sfx(({ "mario_yah", "mario_wah", "mario_hoo" })[math.random(1, 3)])     -- (as loud as MARIO FX: sfx.lua)
        end
        if G and (G.warping or G.pending or G.dying) then stop_ride(s, pawn, "leaving"); return end
        r.acc = math.min(r.acc + dt, 0.2)
        while s.ride and r.acc >= 1.0 / 30.0 do
            r.acc = r.acc - 1.0 / 30.0
            -- (where it was before this step: drawn blended between the two - Mario 64's 30 steps a second shown at
            -- the screen's own rate; drawn at each step it jerked forward every third frame, "lots of stuttering")
            r.ox, r.oy, r.otop, r.oyaw = r.x, r.y, r.top, r.yaw
            local why = ride_step(s, pawn)
            if why == "wall" then
                sfx("en_bonk", 1.0)
                -- (where, and which way: "shell just got destroyed randomly?", 2026-11-08 - nothing in the log said where)
                local w = r.wall or {}
                lib.log("shell: a wall in its way at %.0f %.0f, its foot %.0f, going %.0f - the wall %.0f %.0f to %.0f %.0f, %.0f degrees off it",
                    r.x, r.y, r.top - TOP, r.yaw * 360.0 / 65536.0, w[1] or 0, w[2] or 0, w[3] or 0, w[4] or 0,
                    math.deg(math.acos(math.min(1.0, math.abs(w[5] or 0.0)))))
                stop_ride(s, pawn, "a wall")
                return
            elseif why == "fell" then
                stop_ride(s, pawn, "fell off the world")
                return
            end
        end
        local a = math.max(0.0, math.min(1.0, r.acc * 30.0))
        local ox, oy, otop, oyaw = r.ox or r.x, r.oy or r.y, r.otop or r.top, r.oyaw or r.yaw
        local dxs, dys, dtop = ox + (r.x - ox) * a, oy + (r.y - oy) * a, otop + (r.top - otop) * a
        local dyaw = s16(oyaw + s16(r.yaw - oyaw) * a)
        local yaw = 180.0 - dyaw * 360.0 / 65536.0
        local half = (G and G.half) or 90.0
        local tx, ty, tz = dxs + OFFSET.X, dys + OFFSET.Y, dtop + 4.0 + half + OFFSET.Z
        local lx, ly = r.dx or dxs, r.dy or dys
        local fx, fy = (dxs - lx) / math.max(dt, 1e-3), (dys - ly) / math.max(dt, 1e-3)
        r.dx, r.dy = dxs, dys
        pcall(function()
            local l = pawn:K2_GetActorLocation()
            local cm = pawn.CharacterMovement
            if cm.MovementMode ~= 5 then cm:SetMovementMode(5, 0) end
            local ex, ey, ez = tx - l.X, ty - l.Y, tz - l.Z
            -- (kept on it: more than half a metre from where he stands on it - his body caught on a slope it climbs, an
            -- edge it rides past - he is put back on it at once; it was the shell put back to him: "the players no
            -- longer connected to the shell", 2026-10-17)
            if ex * ex + ey * ey + ez * ez > 50.0 * 50.0 then
                pawn:K2_TeleportTo({ X = tx, Y = ty, Z = tz }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 })
                if cm.MovementMode ~= 5 then cm:SetMovementMode(5, 0) end      -- (a teleport can set him falling)
                if G and G.reset_cloth then G.reset_cloth(pawn) end               -- (his shirt not dragged after him)
                ex, ey, ez = 0.0, 0.0, 0.0
            end
            r.blocked = 0
            local k = 0.7 / math.max(dt, 1.0 / 120.0)
            cm.Velocity = { X = ex * k + fx, Y = ey * k + fy, Z = ez * k }
            pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false)
            if r.pa and r.pa:IsValid() and r.pa.RootMotionMode ~= 1 then r.pa:SetRootMotionMode(1) end
        end)

        lib.set_pose(r.shell.inst, dxs + OFFSET.X, dys + OFFSET.Y, dtop - TOP + OFFSET.Z, yaw)
        r.shell.x, r.shell.y, r.shell.z = r.x, r.y, r.top - TOP
        -- what he rides into is beaten (Mario 64: riding a shell is an attack on all he meets - goombas squashed,
        -- enemies beaten, bob-ombs set off - "you cant kill goombas while on it"); he is not hurt meanwhile
        -- (G.intangible counts G.carried == "shell")
        pcall(function()
            local GM = package.loaded["game"]
            local feet = dtop - TOP
            if GM and GM.goomba_hit_at then GM.goomba_hit_at(dxs, dys, feet + 10.0, 45.0) end
            local mx, my, mz = dys / U, (feet + 40.0) / U, -dxs / U      -- (Mario 64 units)
            local EN = package.loaded["enemies"]
            if EN and EN.hit_at then EN.hit_at(mx, my, mz, 60.0, r.yaw, { x = mx, y = my, z = mz, facing = r.yaw }) end
            local BO = package.loaded["bobomb"]
            if BO and BO.hit_at then BO.hit_at(mx, my, mz, 60.0) end
        end)
        r.relock = (r.relock or 0.0) + dt
        if r.relock > 0.5 then
            r.relock = 0.0
            local pc = lib.controller()
            pcall(function() if not pc:IsMoveInputIgnored() then pc:SetIgnoreMoveInput(true) end; pawn:DisableInput(pc) end)  -- (the lock is a count: added to only when off, or every re-lock stayed on after - "randomly stops")
        end
        -- its sound: the shell's roll, louder the faster
        local S = package.loaded["sfx"]
        if S and S.hold then S.hold("loop_rough_slide", 0.3 + 0.5 * r.v / 64.0) end
        return
    end
    for _, sh in ipairs(s.shells) do
        if not sh.gone then
            sh.t = sh.t + dt
            sh.cool = math.max(0.0, sh.cool - dt)
            lib.set_pose(sh.inst, sh.x + OFFSET.X, sh.y + OFFSET.Y, sh.z + OFFSET.Z, (sh.t * 360.0) % 360.0)
            -- (walked into or landed on: his feet by its top)
            local dx, dy = x - sh.x, y - sh.y
            if sh.cool <= 0.0 and dx * dx + dy * dy < 70.0 * 70.0 and z > sh.z - 20.0 and z < sh.z + TOP + 70.0
               and not (G and (G.carried or G.swim or G.cutscene)) then
                local yaw = 0.0
                pcall(function() yaw = pawn:K2_GetActorRotation().Yaw end)
                local r = { shell = sh, x = sh.x, y = sh.y, top = sh.z + TOP, v = 0.0, acc = 0.0,
                            yaw = s16((180.0 - yaw) * 65536.0 / 360.0) }
                s.ride = r
                locomotion(pawn, false, r)
                if G then G.carried = "shell"; G.air = false end
                sfx("star_sound", 0.6)
                -- (play_shell_music: the power-up tune while he rides it)
                local MU = package.loaded["music"]
                if MU and MU.play then pcall(MU.play, "event_powerup") end
                log("shell: up on it")
                break
            end
        end
    end
end

return M
