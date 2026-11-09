-- Mario 64's tornado ride and twirl (tweester.inc.c; mario_actions_automatic.c act_tornado_twirling;
-- mario_actions_airborne.c act_twirling, update_lava_boost_or_twirling; mario_step.c apply_twirl_gravity). Caught by a
-- Tweester he goes round and up inside it to its top - its hitbox's height, 4000 by its height scale, 0.2 to 0.4 as it
-- pulses (`top()` from enemies.lua, M.TOP without one) - drawn in toward its middle (0.95 of the way out a frame),
-- rising 1 a frame faster up to 60. At the top he leaves it twirling, as fast across as he was running when it caught
-- him (Mario's forward speed is left alone by the ride): 20 up, then falling slowly - gravity 4 a frame times 1024 over his spin, the spin
-- easing to 0x1800 (0x2000 with jump held), the fall at most 75 times the same - and steered: forward speed up 1 a
-- frame at full stick (to 32; over that it eases off 2 a frame), turning up to 1024 a frame. That glide is how Mario
-- lands on Shifting Sand Land's pillars; the athlete was only thrown 6 m straight up and fell back where he was
-- ("make the stars accessible", 2026-10-22).
local lib = require("lib")
local M = {}

local U = 0.75                  -- scene cm a Mario 64 unit
local FPS = 30.0                -- Mario 64 frames a second
M.TOP = 4000.0 * 0.3            -- Mario 64 units over the tornado's foot where it lets him go
M.TOP_K = 1.75                  -- (and that much higher up it: "tornado not high enough", 2026-11-07)
local TAU = 2.0 * math.pi

local st = nil

function M.active() return st ~= nil end

local function game() return package.loaded["game"] end

local function finish(pawn, why)
    if not st then return end
    local s = st
    st = nil
    if s.body and M.spin_body then pcall(M.spin_body, pawn, s.body, 0.0) end      -- (his body straight again)
    pcall(function()
        local cm = pawn.CharacterMovement
        cm.GravityScale = 1.0
        if cm.MovementMode == 5 then cm:SetMovementMode(3, 0) end
    end)
    local G = game()
    if G then G.carried = nil end
    lib.log("tornado: twirl over (%s)", tostring(why))
end

function M.forget() st = nil end

-- caught: `where()` gives the tornado's foot now, scene cm; `top()` its height now, Mario 64 units
function M.catch(pawn, where, top)
    if st or not pawn then return end
    local fx, fy, fz = where()
    local l = pawn:K2_GetActorLocation()
    local O = lib.OFFSET
    local v = pawn:GetVelocity()
    st = { phase = "ride", where = where, top = top, world = lib.world():GetAddress(), t = 0.0,
           run = math.sqrt(v.X * v.X + v.Y * v.Y) / (U * FPS), run_face = math.atan(v.Y, v.X),
           h = math.max(0.0, (l.Z - O.Z - fz) / U), vy = 0.0, spin = 0.0,
           dx = l.X - O.X - fx, dy = l.Y - O.Y - fy }
    pcall(function() pawn.CharacterMovement:SetMovementMode(5, 0) end)
    st.body, st.ang = M.body_base and M.body_base(pawn), 0.0
    local G = game()
    if G then G.carried, G.air = true, false end
    lib.log("tornado: caught, up it")
end

-- the move stick, camera-relative: world direction (x, y) and how far it is pushed (0..1); and jump held
M.test_stick = nil              -- (tests: a function giving x, y, mag, held in place of the player's stick)
local function stick()
    if M.test_stick then return M.test_stick() end
    local pc = lib.controller()
    if not pc then return 0.0, 0.0, 0.0, false end
    local function key(n)
        local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(n) }) end)
        return ok and v == true
    end
    local function axis(n)
        local ok, v = pcall(function() return pc:GetInputAnalogKeyState({ KeyName = FName(n) }) end)
        if not ok or type(v) ~= "number" or math.abs(v) < 0.18 then return 0.0 end
        return v
    end
    local f = axis("Gamepad_LeftY") + (key("W") and 1.0 or 0.0) - (key("S") and 1.0 or 0.0)
    local r = axis("Gamepad_LeftX") + (key("D") and 1.0 or 0.0) - (key("A") and 1.0 or 0.0)
    local mag = math.min(1.0, math.sqrt(f * f + r * r))
    local yaw = 0.0
    pcall(function() yaw = math.rad(pc:GetControlRotation().Yaw) end)
    local wx = f * math.cos(yaw) - r * math.sin(yaw)
    local wy = f * math.sin(yaw) + r * math.cos(yaw)
    local n = math.sqrt(wx * wx + wy * wy)
    if n > 1e-6 then wx, wy = wx / n, wy / n end
    return wx, wy, mag, key("SpaceBar") or key("Gamepad_FaceButton_Bottom")
end

local function ride(dt, pawn, f)
    local fx, fy, fz = st.where()
    st.vy = math.min(60.0, st.vy + f)
    st.h = st.h + st.vy * f
    st.spin = math.min(0x1000, st.spin + 0x100 * f)
    -- (and his body spun round by it, as Mario's is - act_tornado_twirling: "make the player spin when sucked into a
    -- tornado", 2026-11-07)
    st.ang = (st.ang or 0.0) + st.spin / 65536.0 * TAU * f
    if st.body and M.spin_body then pcall(M.spin_body, pawn, st.body, st.ang) end
    local k = 0.95 ^ f
    local a = st.spin / 65536.0 * TAU * f
    local dx, dy = st.dx * k, st.dy * k
    st.dx, st.dy = dx * math.cos(a) - dy * math.sin(a), dx * math.sin(a) + dy * math.cos(a)
    local O = lib.OFFSET
    local tx, ty, tz = fx + st.dx + O.X, fy + st.dy + O.Y, fz + st.h * U + O.Z
    -- (put there each tick, swept so walls and ceilings stop him: the flying movement's speed alone left him where he
    -- stood)
    pcall(function()
        local cm = pawn.CharacterMovement
        if cm.MovementMode ~= 5 then cm:SetMovementMode(5, 0) end
        cm.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
        pawn:K2_SetActorLocation({ X = tx, Y = ty, Z = tz }, true, {}, true)
    end)
    if st.h >= (st.top and st.top() or M.TOP) * (M.TOP_K or 1.0) then
        -- out of the top, twirling: 20 up, his spin at its fastest (0x3000 by the ride's end)
        st.phase, st.vz, st.spin, st.fwd, st.soft = "twirl", 20.0, 0x3000, math.min(48.0, st.run), false
        st.face = st.run_face
        if st.fwd < 4.0 then
            st.fwd = 0.0
            pcall(function() st.face = math.rad(lib.controller():GetControlRotation().Yaw) end)
        end
        pcall(function()
            local cm = pawn.CharacterMovement
            cm:SetMovementMode(3, 0)
            cm.GravityScale = 0.0
        end)
        local G = game()
        if G then
            G.carried = nil
            if G.parkour_reset then pcall(G.parkour_reset, pawn) end
        end
        lib.log("tornado: out of the top, twirling")
    end
end

local function twirl(dt, pawn, f)
    local mode = 3
    pcall(function() mode = pawn.CharacterMovement.MovementMode end)
    if st.t > 0.3 and mode ~= 3 then finish(pawn, "down"); return end
    local wx, wy, mag, held = stick()
    local want = held and 0x2000 or 0x1800
    if st.spin > want then st.spin = math.max(want, st.spin - 0x200 * f) else st.spin = math.min(want, st.spin + 0x200 * f) end
    -- (his body spinning on as he twirls down - act_twirling's twirlYaw)
    st.ang = (st.ang or 0.0) + st.spin / 65536.0 * TAU * f
    if st.body and M.spin_body then pcall(M.spin_body, pawn, st.body, st.ang) end
    local heavy = math.min(1.0, 1024.0 / st.spin)
    st.vz = math.max(-75.0 * heavy, st.vz - 4.0 * heavy * f)
    if mag > 0.0 then
        local d = math.atan(wy, wx) - st.face
        d = (d + math.pi) % TAU - math.pi
        st.fwd = st.fwd + math.cos(d) * mag * f
        st.face = st.face + math.sin(d) * mag * (1024.0 / 65536.0 * TAU) * f
        if st.fwd < 0.0 then st.fwd, st.face = -st.fwd, st.face + math.pi end
    end
    if st.fwd > 32.0 then st.fwd = math.max(32.0, st.fwd - 2.0 * f) end
    local v = st.fwd * U * FPS
    pcall(function()
        local cm = pawn.CharacterMovement
        cm.GravityScale = 0.0
        cm.Velocity = { X = math.cos(st.face) * v, Y = math.sin(st.face) * v, Z = st.vz * U * FPS }
    end)
    local G = game()
    if G then
        G.no_fall_until, G.air = os.clock() + 0.5, false        -- (a twirl's landing does not hurt: ACT_TWIRL_LAND)
        -- (STORROR's record of where his fall began goes again just above the ground, so it lands him lightly)
        if not st.soft and G.parkour_reset then
            local l = pawn:K2_GetActorLocation()
            local O = lib.OFFSET
            local fz = G.floor_z and G.floor_z(l.X - O.X, l.Y - O.Y, l.Z - O.Z)
            if fz and l.Z - O.Z - (G.half or 90.0) - fz < 60.0 then
                st.soft = true
                pcall(G.parkour_reset, pawn)
            end
        end
    end
end

-- ------------------------------------------------------------ into the Boo's cage
-- Mario 64's way into Big Boo's Haunt (mario_actions_cutscene.c act_bbh_enter_jump, act_bbh_enter_spin): touched from
-- the ground the cage makes him jump, 60 up and toward it at a twentieth of the way a frame; then he somersaults (one
-- every 10 frames, SOUND_ACTION_SPIN each) up to 512 over the floor, drawn in toward the cage's middle at 10 a frame.
-- Falling, he finishes his somersault and dives in head first (SOUND_ACTION_SHRINK_INTO_BBH), shrinking 0.06 a frame
-- to a tenth; where he lands the screen goes white (WARP_OP_SPIN_SHRINK, 30 frames) and he is in. The athlete was put
-- in BBH the moment he touched it ("when entering the level the charater doesnt get sucked in", 2026-10-22). His body
-- is turned and shrunk in his capsule, which is carried there as on the tornado; it is put back once he is in.
M.SPIN_TOP = 512.0              -- Mario 64 units over the floor the somersaults take him to
local cage = nil

function M.in_cage() return cage ~= nil end

local function sound(name, v)
    local S = package.loaded["sfx"]
    if S then pcall(S.play, name, v) end
end

local function qmul(ax, ay, az, aw, bx, by, bz, bw)
    return aw * bx + ax * bw + ay * bz - az * by,
           aw * by - ax * bz + ay * bw + az * bx,
           aw * bz + ax * by - ay * bx + az * bw,
           aw * bw - ax * bx - ay * by - az * bz
end

-- where his body sits in his capsule (read from the engine: its own place, turned to his front, its size)
local function body_base(pawn)
    local ok, b = pcall(function()
        local al, ar = pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation()
        local mesh = pawn.Mesh
        local ml, mr, ms = mesh:K2_GetComponentLocation(), mesh:K2_GetComponentRotation(), mesh:K2_GetComponentScale()
        local y = math.rad(ar.Yaw)
        local dx, dy = ml.X - al.X, ml.Y - al.Y
        return { x = dx * math.cos(y) + dy * math.sin(y), y = -dx * math.sin(y) + dy * math.cos(y), z = ml.Z - al.Z,
                 yaw = math.rad(mr.Yaw - ar.Yaw), s = ms.X, half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight() }
    end)
    -- (not as it should stand - mid-fall, say: the athlete's own, as measured 2026-10-22)
    if not ok or math.abs(b.x) > 3.0 or math.abs(b.y) > 3.0 or math.abs(b.z + 88.1) > 6.0 or math.abs(b.s - 1.0) > 0.05 then
        b = { x = 0.0, y = 0.0, z = -88.1, yaw = math.rad(-90.0), s = 1.0, half = 86.0 }
    end
    return b
end

-- his body turned head over heels by `flip` (radians, his head toward his front) about his middle, and shrunk to `k`
-- toward the bottom of his capsule (where Mario 64's model has its feet)
local function pose_body(pawn, b, flip, k)
    local c, sn = math.cos(flip), math.sin(flip)
    local lx, lz = b.x * c + b.z * sn, -b.x * sn + b.z * c
    local qx, qy, qz, qw = qmul(0.0, math.sin(flip * 0.5), 0.0, math.cos(flip * 0.5),
                                0.0, 0.0, math.sin(b.yaw * 0.5), math.cos(b.yaw * 0.5))
    pcall(function()
        pawn.Mesh:K2_SetRelativeTransform({
            Rotation = { X = qx, Y = qy, Z = qz, W = qw },
            Translation = { X = k * lx, Y = k * b.y, Z = -b.half * (1.0 - k) + k * lz },
            Scale3D = { X = b.s * k, Y = b.s * k, Z = b.s * k },
        }, false, {}, true)
    end)
end

-- his body turned `ang` (radians) round its upright in his capsule, the rest as it sat - the tornado's spin (0: as it was)
M.body_base = body_base
function M.spin_body(pawn, b, ang)
    local yaw = b.yaw + ang
    local c, sn = math.cos(ang), math.sin(ang)
    pawn.Mesh:K2_SetRelativeTransform({
        Rotation = { X = 0.0, Y = 0.0, Z = math.sin(yaw * 0.5), W = math.cos(yaw * 0.5) },
        Translation = { X = b.x * c - b.y * sn, Y = b.x * sn + b.y * c, Z = b.z },
        Scale3D = { X = b.s, Y = b.s, Z = b.s },
    }, false, {}, true)
end

-- Bounced off something into a twirl - Mario 64's INT_SUBTYPE_TWIRL_BOUNCE, Spindrift's (bounce_off_object 80 up, then
-- ACT_TWIRLING), and the Fly Guy's here too: "make the player spin if they jump on the flower enemy and shyguy, make it
-- controlable to like the wind on ttm", 2026-11-07. `up` Mario 64 units a frame up (80), then twirling down as he does
-- out of a tornado's top: spinning, falling slowly, steered by the stick - forward speed and turn (twirl).
function M.bounce_twirl(pawn, up)
    if st or not pawn then return false end
    local v = pawn:GetVelocity()
    local face = math.atan(v.Y, v.X)
    local run = math.sqrt(v.X * v.X + v.Y * v.Y) / (U * FPS)
    if run < 4.0 then
        run = 0.0
        pcall(function() face = math.rad(pawn:K2_GetActorRotation().Yaw) end)
    end
    st = { phase = "twirl", world = lib.world():GetAddress(), t = 0.0, vz = up or 80.0, spin = 0.0,
           fwd = math.min(32.0, run), face = face, soft = false, body = M.body_base and M.body_base(pawn), ang = 0.0 }
    local G = game()
    if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
    pcall(function()
        local cm = pawn.CharacterMovement
        cm:SetMovementMode(3, 0)
        cm.GravityScale = 0.0
        cm.Velocity = { X = math.cos(face) * st.fwd * U * FPS, Y = math.sin(face) * st.fwd * U * FPS, Z = st.vz * U * FPS }
    end)
    local S = package.loaded["sfx"]
    if S then pcall(S.play, "bounce_off", 1.0) end
    lib.log("twirl: bounced off into a twirl")
    return true
end

local function cage_finish(pawn, why)
    local c = cage
    cage = nil
    if not c then return end
    if pawn then pose_body(pawn, c.body, 0.0, 1.0) end
    local G = game()
    if G then G.carried = nil end
    lib.log("cage: %s", tostring(why))
end

-- touched: the cage's foot (scene cm, without the offset) and `done()`, the way in, called where he lands
function M.into_cage(pawn, cx, cy, cz, done)
    if cage or not pawn then return false end
    if st then finish(pawn, "into a cage") end
    local G = game()
    local l = pawn:K2_GetActorLocation()
    local O = lib.OFFSET
    local mode = 1
    pcall(function() mode = pawn.CharacterMovement.MovementMode end)
    local b = body_base(pawn)
    cage = { phase = (mode == 3) and "spin0" or "jump", cx = cx, cy = cy, floor = cz, done = done, body = b,
             x = l.X - O.X, y = l.Y - O.Y, h = math.max(0.0, (l.Z - O.Z - b.half - cz) / U), vy = 0.0, fwd = 0.0,
             flip = 0.0, timer = 100.0, k = 1.0, t = 0.0, scene = G and G.name, pawn = pawn:GetAddress() }
    pcall(function() pawn.CharacterMovement:SetMovementMode(5, 0) end)
    if G then G.carried, G.air = true, false end
    lib.log("cage: in he goes (%s)", cage.phase)
    return true
end

local function cage_step(dt, pawn, f)
    local c = cage
    local G = game()
    if c.phase == "in" then
        -- (landed: the screen whitens and he is taken in; back as he was once he is there)
        if (G and G.name ~= c.scene) or c.t - c.t_in > 6.0 then cage_finish(pawn, "in") end
        return
    end
    local dx, dy = c.cx - c.x, c.cy - c.y
    local dcm = math.sqrt(dx * dx + dy * dy)
    local dist = dcm / U
    if c.phase == "jump" and not c.vy0 then
        c.vy0, c.vy, c.fwd = true, 60.0, dist / 20.0
        sound(({ "mario_yah", "mario_wah", "mario_hoo" })[math.random(1, 3)])   -- (as loud as MARIO FX: sfx.lua)
    elseif c.phase == "spin0" then
        local room = M.SPIN_TOP - c.h
        c.vy = room > 0.0 and (math.sqrt(4.0 * room + 1.0) - 1.0) or 2.0
        c.phase = "spin"
        sound("bbh_spin")
    end
    if c.phase ~= "jump" then
        c.fwd = dist > 20.0 and 10.0 or dist / 2.0
        if c.fwd < 0.5 then c.fwd = 0.0 end
    end
    -- the step: toward the cage (never past its middle), up or down, then gravity (perform_air_step, apply_gravity)
    if dcm > 1e-3 then
        local step = math.min(c.fwd * f, dist) * U
        c.x, c.y = c.x + dx / dcm * step, c.y + dy / dcm * step
    end
    c.h = c.h + c.vy * f
    c.vy = math.max(-75.0, c.vy - 4.0 * f)
    if c.phase == "jump" and c.vy <= 0.0 then c.phase = "spin0" end
    if c.phase == "spin" or c.phase == "spin_end" then
        local before = c.flip
        c.flip = c.flip + TAU / 10.0 * f
        if c.phase == "spin" and math.floor(c.flip / TAU) > math.floor(before / TAU) then sound("bbh_spin") end
        if c.phase == "spin" and c.vy <= 0.0 then c.phase, c.flip_end = "spin_end", (math.floor(c.flip / TAU) + 1) * TAU end
        if c.phase == "spin_end" and c.flip >= c.flip_end then
            c.flip, c.phase = c.flip_end, "dive"
            sound("bbh_shrink")
        end
    elseif c.phase == "dive" then
        -- (head first along his fall, turning into it no faster than a somersault)
        c.flip = math.min(c.flip_end + math.atan(c.fwd, c.vy), c.flip + TAU / 10.0 * f)
    end
    if c.phase == "spin_end" or c.phase == "dive" then
        if c.timer >= 11.0 then c.timer = math.max(10.0, c.timer - 6.0 * f) end
        c.k = c.timer / 100.0
    end
    local landed = c.phase ~= "jump" and c.phase ~= "spin0" and c.h <= 0.0 and c.vy < 0.0
    if landed then c.h = 0.0 end
    local O = lib.OFFSET
    pcall(function()
        local cm = pawn.CharacterMovement
        if cm.MovementMode ~= 5 then cm:SetMovementMode(5, 0) end
        cm.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
        pawn:K2_SetActorLocation({ X = c.x + O.X, Y = c.y + O.Y, Z = c.floor + c.h * U + c.body.half + O.Z }, true, {}, true)
        if dcm > 5.0 then pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = math.deg(math.atan(dy, dx)), Roll = 0.0 }, false) end
        -- (where the sweep left him: a wall stops him there)
        local l = pawn:K2_GetActorLocation()
        c.x, c.y = l.X - O.X, l.Y - O.Y
    end)
    if c.phase ~= "jump" then pose_body(pawn, c.body, c.flip, c.k) end
    if G then G.no_fall_until = os.clock() + 1.0 end
    if landed or c.t > 8.0 then
        c.phase, c.t_in = "in", c.t
        pcall(function() pawn.CharacterMovement:StopMovementImmediately() end)
        lib.log("cage: landed, taken in")
        if c.done then
            local ok, err = pcall(c.done)
            if not ok then lib.log("cage: the way in failed: %s", tostring(err)) end
        end
    end
end

function M.update(dt, pawn)
    if cage and pawn then
        if pawn:GetAddress() ~= cage.pawn then cage = nil
        else
            cage.t = cage.t + dt
            local ok, err = pcall(cage_step, dt, pawn, math.min(dt, 0.1) * FPS)
            if not ok then lib.log("cage: %s", tostring(err)); cage_finish(pawn, "error") end
        end
    end
    if not st or not pawn then return end
    local w = lib.world()
    if not w or w:GetAddress() ~= st.world then st = nil; return end       -- (the scene went)
    st.t = st.t + dt
    if st.t > 40.0 then finish(pawn, "too long"); return end
    local f = math.min(dt, 0.1) * FPS
    local ok, err = pcall(st.phase == "ride" and ride or twirl, dt, pawn, f)
    if not ok then lib.log("tornado: %s", tostring(err)); finish(pawn, "error") end
end

return M
