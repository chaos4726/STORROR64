-- SM64Map: out of the water by a climb, as on land ("next we gotta be able to climb out", "player gets stuck in water",
-- "when next to a edge and the player presses X it should trigger the climb", "the same thing that happens when
-- climbing a wall on land should be happening when in the water", 2026-10-24). At the surface, with an edge before him
-- within reach - a floor (the level's, or a platform's) from 10 cm to 2.3 m over the water, up to 2.5 m ahead and 40
-- degrees either side - X (the gamepad's left face button; on the keyboard E):
--   he swims in to the wall (the swim's own strokes and pose, steered at it);
--   STORROR's ledge grab: he takes hold of the edge and hangs from it - his hands brought onto it - as on land;
--   from the hang, as STORROR's own: up (or X) and he climbs up over it - STORROR's climb-up, lifted by its own
--   motion (scaled to the edge's height), drawn in over the edge - and stands on the top; down (or B) and he lets go,
--   back into the water.
-- (Made as climb.lua's tree-top grab, hang and climb-up are, which hold: an earlier climb here lifted him by its own
-- clock along the clip's measured rise - he floated up the wall standing, then popped onto the top crouched - and
-- pulled him straight up, never hanging: "still very buggy climbing", "its not using storrors moveset because its
-- automatically pulling the player up".)
local lib = require("lib")
local M = {}

local sin, cos, rad, deg, atan, min, max, sqrt, abs, exp = math.sin, math.cos, math.rad, math.deg, math.atan, math.min,
    math.max, math.sqrt, math.abs, math.exp
-- STORROR's own clips (climb.lua's)
local GRAB = "/SPP/SPPCharacter/Animation/ClimbGrab/Wall/MontageClimbGrabWall_12131_toby-routine01-003.MontageClimbGrabWall_12131_toby-routine01-003"
local GRAB_FROM = 0.15      -- s into the ledge grab: past its jump up (he is already there), hands going up
local GRAB_CATCH = 0.33     -- s: he has caught the top: held there to hang
local HANG_MIN = 0.4        -- s hanging before he climbs, even with up held
local CLIMB_UP_SEQ = "/SPP/SPPCharacter/Animation/Climb/ClimbUp/ClimbClimbUp_5750_TobyKT02.ClimbClimbUp_5750_TobyKT02"
local UP_END = 1.45         -- s: the clip's lift (about 180 cm) is done; after it, it steps back off
local UP_LIFT = 180.0       -- cm the clip's own motion lifts him by UP_END
local TOP_GAP = 87.0        -- his middle this far under the top when he hangs from it
local HANG_OUT = 30.0       -- cm out from the edge his middle starts the hang (his hands then bring him in)
local ON_TOP = 45.0         -- cm past the edge he ends
local SWIM_TO = 70.0        -- cm from the edge where the swim in ends and the grab begins
local REACH, FAN = 250.0, 40.0
local KEYS_X = { "Gamepad_FaceButton_Left", "E" }
local KEYS_UP = { "W", "Up" }
local KEYS_DOWN = { "S", "Down" }
local KEYS_LET_GO = { "Gamepad_FaceButton_Right", "Q" }

local function smooth(k) k = max(0.0, min(1.0, k)); return k * k * (3.0 - 2.0 * k) end

local st = nil              -- the climb under way: { phase = "grab" | "up", ... }
local pending = nil         -- X pressed: the edge he is swimming in to
local x_was = false

function M.active() return st ~= nil or pending ~= nil end

-- ------------------------------------------------------------ the controls
local function key_down(names)
    local pc = lib.controller()
    if not pc then return false end
    local down = false
    for _, k in ipairs(names) do
        pcall(function() if pc:IsInputKeyDown({ KeyName = FName(k) }) then down = true end end)
    end
    return down
end
M.test_press = nil          -- (tests: true stands in for one press of X)
M.test_stick = nil          -- (tests: a number stands in for the stick's up/down, -1..1)
local function x_pressed()
    if M.test_press then M.test_press = nil; return true end
    local down = key_down(KEYS_X)
    local p = down and not x_was
    x_was = down
    return p
end
local function stick_y()
    if M.test_stick then return M.test_stick end
    local y = 0.0
    pcall(function()
        local v = lib.controller():GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftY") })
        if type(v) == "number" then y = v end
    end)
    if key_down(KEYS_UP) then y = 1.0 elseif key_down(KEYS_DOWN) then y = -1.0 end
    return y
end

-- ------------------------------------------------------------ the edge
-- The nearest edge before him: its top (scene cm), how far off it starts, and the way to it; nil if none in reach.
-- (x, y): his middle, scene cm; yaw his facing (degrees); sz the water's surface
local function top_at(G, ax, ay, sz)
    local top = G.floor_z(ax, ay, sz + 260.0)
    local P = G.PLAT
    if P and P.floor_under then
        local ok, pz = pcall(P.floor_under, ax, ay, sz + 260.0)
        if ok and pz and (not top or pz > top) then top = pz end
    end
    return top
end
local function find_edge(x, y, yaw, sz)
    local G = package.loaded["game"]
    if not (G and G.floor_z) then return nil end
    local best = nil
    for _, off in ipairs({ 0, -10, 10, -20, 20, -30, 30, -40, 40 }) do
        if abs(off) <= FAN then
            local a = rad(yaw + off)
            local ux, uy = cos(a), sin(a)
            for d = 20, REACH, 10 do
                if best and d >= best.d then break end
                local top = top_at(G, x + ux * d, y + uy * d, sz)
                -- (from 20 cm: a bank lower than that he hops out onto, swimming at it - game.lua's hop out; climbed
                -- too, the two fought over him, 2026-11-06)
                if top and top > sz + 20.0 and top < sz + 230.0 then
                    best = { top = top, d = d, ux = ux, uy = uy }
                    break
                end
            end
        end
    end
    return best
end

-- ------------------------------------------------------------ STORROR's parts
local function anim(pawn)
    local ai = nil
    pcall(function() ai = pawn.Mesh:GetAnimInstance() end)
    return ai
end
local function warping(pawn, on)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetClass():GetFName():ToString() == "MotionWarpingComponent" then
                if on then
                    pcall(function() o:SetComponentTickEnabled(true) end)
                    pcall(function() o:Activate(false) end)
                    pcall(function() o:RemoveWarpTarget(FName("Reset")) end)
                else
                    pcall(function() o:RemoveWarpTarget(FName("Reset")) end)
                    pcall(function() o:Deactivate() end)
                    pcall(function() o:SetComponentTickEnabled(false) end)
                end
            end
        end
    end)
end

-- STORROR's own parkour moves are off while he swims or climbs out, and back the moment he is out: its X took the
-- water's surface for a wall to climb ("when pressing x in the water he climbs the water instead of trying to climb
-- the wall", 2026-10-24). (Under a lock of their own: nothing else's lock is touched.)
local LOCK = "SM64SwimX"
local off_on = nil              -- the pawn they are off on (its address), or nil
local first = true              -- (a fresh load: a lock left by the last one is let go, unless he swims)
local function parkour(pawn, on)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetClass():GetFName():ToString() == "ParkourComponent" then
                if not on then pcall(function() o:ClearInputQueue() end) end
                o:EnableAllParkourInputs(FName(LOCK), on)
            end
        end
    end)
end

-- ------------------------------------------------------------ the grab, the hang, the climb up
local function begin_grab(pawn, e, x, y, z)
    local G = package.loaded["game"]
    if G and G.stop_swim then G.stop_swim() end
    local O = lib.OFFSET
    local half = 88.0
    pcall(function() half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight() end)
    local yaw = deg(atan(e.uy, e.ux))
    local s = { phase = "grab", e = e, half = half, yaw = yaw, t0 = os.clock(), pawn = pawn:GetAddress(), ai = anim(pawn) }
    -- (to the hang's place: his middle TOP_GAP under the top, HANG_OUT out from the edge - his hands then put on it)
    s.from = { x + O.X, y + O.Y, z + O.Z }
    s.hang = { e.ex - e.ux * HANG_OUT + O.X, e.ey - e.uy * HANG_OUT + O.Y, e.top - TOP_GAP + O.Z }
    -- (the jump up to it as long as its height asks - 0.25 s, and 1 s more for each 4 m up or 3 m in, to 0.8 s: in
    -- 0.2 s whatever its height, a 2.3 m edge put him 1.8 m up at once - "basically teleporting to the edge",
    -- 2026-11-06 - and the grab's clip from its own jump, its catch as he gets there)
    local rise = max(0.0, s.hang[3] - s.from[3])
    local run = sqrt((s.hang[1] - s.from[1]) ^ 2 + (s.hang[2] - s.from[2]) ^ 2)
    s.lift = min(0.8, max(0.25, 0.25 + rise / 400.0, run / 300.0))
    pcall(function()
        local cm = pawn.CharacterMovement
        cm:StopMovementImmediately()
        cm:SetMovementMode(5, 0)
        pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false)
    end)
    pcall(function()
        s.rm = s.ai.RootMotionMode
        s.ai.RootMotionMode = 1                     -- (he stays where he is: the grab's own jump up is not wanted)
        local m = lib.try_load(GRAB)
        if m and m:IsValid() then
            s.ai:Montage_Play(m, GRAB_CATCH / s.lift, 0, 0.0, true)
            s.gm = m
        end
    end)
    if G then G.carried = true end
    st = s
    lib.log("waterclimb: took hold of the edge (%.0f cm over the water)", e.top - e.sz)
end

local function begin_up(pawn)
    local s = st
    pcall(function() if s.gm then s.ai:Montage_Stop(0.15, s.gm) end end)
    local m = lib.try_load(CLIMB_UP_SEQ)
    if not (m and m:IsValid()) then return false end
    warping(pawn, false)
    s.ai.RootMotionMode = 3                         -- (its own lift; the way in over the edge is the mod's)
    -- (the clip's own sequence, played as a dynamic montage: STORROR's montage of it has motion-warping windows)
    m = s.ai:PlaySlotAnimationAsDynamicMontage(m, FName("FullBody"), 0.15, 0.25, 1.0, 1, -1.0, 0.0)
    if not (m and m:IsValid()) then return false end
    local l = pawn:K2_GetActorLocation()
    local O = lib.OFFSET
    local e = s.e
    s.phase, s.um, s.t0 = "up", m, os.clock()
    s.u = { z0 = l.Z, zs = l.Z, r = 0.0, x0 = l.X, y0 = l.Y, gh = 0.0,
            tx = e.ex + e.ux * ON_TOP + O.X, ty = e.ey + e.uy * ON_TOP + O.Y,
            top = e.top + O.Z, kz = (e.top + O.Z + s.half + 1.0 - l.Z) / UP_LIFT }
    lib.log("waterclimb: climbing up")
    return true
end

local function finish(pawn, why, onto_top)
    local s = st
    st = nil
    if not s then return end
    local G = package.loaded["game"]
    if onto_top then
        -- (on the top: lifted onto it if the clip ended low)
        pcall(function()
            local l = pawn:K2_GetActorLocation()
            local z = max(l.Z, s.u.top + s.half + 1.0)
            pawn:K2_SetActorLocation({ X = s.u.tx, Y = s.u.ty, Z = z }, false, {}, true)
        end)
        pcall(function() if s.um and s.um:IsValid() then s.ai:Montage_Stop(0.25, s.um) end end)
        -- (root motion off while the clip fades out - its step back would walk him off - then STORROR's own)
        pcall(function() s.ai.RootMotionMode = 1 end)
        -- (STORROR's own is 2 - from everything - as climb.lua puts back: what was there before could be the swim's 1,
        -- and left so, STORROR's root-motion moves stood still)
        M.rm_back = { ai = s.ai, rm = 2, at = os.clock() + 0.4 }
        warping(pawn, true)
        pcall(function()
            local cm = pawn.CharacterMovement
            cm.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
            cm:SetMovementMode(1, 0)                -- (handed back standing - walking - not dropped)
        end)
    else
        -- (let go: back into the water)
        pcall(function() if s.gm then s.ai:Montage_Stop(0.2, s.gm) end end)
        pcall(function() if s.um and s.um:IsValid() then s.ai:Montage_Stop(0.2, s.um) end end)
        pcall(function() s.ai.RootMotionMode = 2 end)
        warping(pawn, true)
        pcall(function() pawn.CharacterMovement:SetMovementMode(3, 0) end)
    end
    if G then
        G.carried = nil
        G.no_fall_until = os.clock() + 0.5
        if onto_top and G.parkour_reset then pcall(G.parkour_reset, pawn) end
    end
    lib.log("waterclimb: %s", tostring(why))
end

-- ------------------------------------------------------------ each swim tick (game.lua update_swim)
-- X by an edge: he swims in to it, and takes hold of it there. True once he has (the swim is over).
function M.try(pawn, x, y, z, sz)
    if st or not pawn then return false end
    if pending then
        local e = pending
        e.t = e.t + 1.0 / 60.0
        local dx, dy = e.ex - x, e.ey - y
        local d = sqrt(dx * dx + dy * dy)
        local SW = package.loaded["swim"]
        local s = SW and SW.state and SW.state()
        if s then
            s.yaw = deg(atan(dy, dx))
            s.pitch = 0.0
            if s.speed < 280.0 then s.speed = 280.0 end
        end
        if d <= SWIM_TO or e.t > 1.6 then
            pending = nil
            if d > 1.0 then e.ux, e.uy = dx / d, dy / d end
            begin_grab(pawn, e, x, y, z)
            return true
        end
        return false
    end
    if not x_pressed() then return false end
    local yaw = 0.0
    pcall(function() yaw = pawn:K2_GetActorRotation().Yaw end)
    local b = find_edge(x, y, yaw, sz)
    if not b then
        lib.log("waterclimb: X, but no edge in reach")
        return false
    end
    pending = { top = b.top, ex = x + b.ux * b.d, ey = y + b.uy * b.d, ux = b.ux, uy = b.uy, sz = sz, t = 0.0 }
    lib.log("waterclimb: an edge %.0f cm over the water, %.0f cm ahead - swimming in", b.top - sz, b.d)
    if b.d <= SWIM_TO then return M.try(pawn, x, y, z, sz) end
    return false
end

-- ------------------------------------------------------------ every tick (game.lua G.tick)
function M.update(dt, pawn)
    if not pawn then return end
    local G = package.loaded["game"]
    -- the parkour lock
    local addr = pawn:GetAddress()
    local want_off = G ~= nil and (G.swim or st ~= nil or pending ~= nil)
    if off_on and off_on ~= addr then off_on = nil end          -- (another body: the lock went with the old one)
    if first then first = false; if not want_off then parkour(pawn, true) end end
    if want_off and not off_on then parkour(pawn, false); off_on = addr
    elseif not want_off and off_on then parkour(pawn, true); off_on = nil end
    -- (the swim ended some other way while he swam in: nothing to swim in to)
    if pending and G and not G.swim then pending = nil end
    -- STORROR's root motion back, a moment after he is up
    local rb = M.rm_back
    if rb and os.clock() >= rb.at then
        M.rm_back = nil
        pcall(function() if rb.rm then rb.ai.RootMotionMode = rb.rm end end)
    end
    local s = st
    if not s then return end
    if addr ~= s.pawn then st = nil; return end
    local cm = pawn.CharacterMovement
    pcall(function()
        if cm.MovementMode ~= 5 then cm:SetMovementMode(5, 0) end
    end)
    if G then G.no_fall_until = os.clock() + 0.5 end
    local O = lib.OFFSET
    if s.phase == "grab" then
        pcall(function() cm.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 } end)
        -- into the hang's place over the jump up (s.lift: up fast and easing into it, in over the same time), then his
        -- grip (between his middle-finger roots) drawn onto the edge just under its top - at most 3 cm a frame, as the
        -- tree's
        local age = os.clock() - s.t0
        local lift = s.lift or 0.2
        pcall(function()
            if age < lift then
                local k = age / lift
                local a, up = smooth(k), 1.0 - (1.0 - k) * (1.0 - k)
                local f, h = s.from, s.hang
                pawn:K2_SetActorLocationAndRotation({ X = f[1] + (h[1] - f[1]) * a, Y = f[2] + (h[2] - f[2]) * a, Z = f[3] + (h[3] - f[3]) * up },
                    { Pitch = 0.0, Yaw = s.yaw, Roll = 0.0 }, false, {}, true)
            else
                local gl = pawn.Mesh:GetSocketLocation(FName("middle_01_l"))
                local gr = pawn.Mesh:GetSocketLocation(FName("middle_01_r"))
                local gx, gy, gz = (gl.X + gr.X) / 2.0, (gl.Y + gr.Y) / 2.0, (gl.Z + gr.Z) / 2.0
                local tx, ty, tz = s.e.ex + O.X, s.e.ey + O.Y, s.e.top + O.Z + 1.0 - 4.0
                local l = pawn:K2_GetActorLocation()
                local k = 1.0 - exp(-12.0 * dt)
                local cx, cy, cz = (tx - gx) * k, (ty - gy) * k, (tz - gz) * k
                local cl = sqrt(cx * cx + cy * cy + cz * cz)
                if cl > 3.0 then cx, cy, cz = cx * 3.0 / cl, cy * 3.0 / cl, cz * 3.0 / cl end
                pawn:K2_SetActorLocationAndRotation({ X = l.X + cx, Y = l.Y + cy, Z = l.Z + cz },
                    { Pitch = 0.0, Yaw = s.yaw, Roll = 0.0 }, false, {}, true)
            end
        end)
        -- the catch: held there, hanging
        pcall(function()
            if not s.hung and s.gm then
                local pos = s.ai:Montage_GetPosition(s.gm)
                if pos >= GRAB_CATCH or not s.ai:Montage_IsPlaying(s.gm) then
                    s.hung = os.clock()
                    if not s.ai:Montage_IsPlaying(s.gm) then s.ai:Montage_Play(s.gm, 1.0, 0, GRAB_CATCH, true) end
                    s.ai:Montage_SetPosition(s.gm, GRAB_CATCH)
                    s.ai:Montage_SetPlayRate(s.gm, 0.0)
                    lib.log("waterclimb: hanging - up or X to climb, down or B to let go")
                end
            end
        end)
        if s.hung and os.clock() - s.hung >= HANG_MIN then
            local y = stick_y()
            local x = x_pressed()
            if y > 0.5 or x then
                if not begin_up(pawn) then finish(pawn, "the climb-up did not start", false) end
            elseif y < -0.5 or key_down(KEYS_LET_GO) then
                finish(pawn, "let go, back into the water", false)
            end
        else
            x_pressed()                             -- (the press that began it is not taken again)
        end
        return
    end
    if s.phase == "up" then
        local playing = false
        pcall(function() playing = s.ai:Montage_IsPlaying(s.um) end)
        local u = s.u
        pcall(function()
            -- (up by the clip's own lift, scaled to the edge; in over the edge by the mod as he comes over it)
            local pos = playing and s.ai:Montage_GetPosition(s.um) or 2.0
            u.pos = pos
            local g = smooth((pos - 0.6) / (UP_END - 0.6))
            local l = pawn:K2_GetActorLocation()
            u.r = u.r + (l.Z - u.zs)
            -- (measured in two climbs out, 2026-10-26 - "general glitchyness when climbing out of water": drawn in over
            -- the edge while his feet were still under its top, his capsule went into the bank's corner, the engine threw
            -- it up 20 cm in a frame, that throw was counted as the clip's lift, and he went on 15 cm over where he stands
            -- and was dropped onto it at the end. Now: never over where he stands; in over the edge only once his feet
            -- are over its top, eased in; and no more than 400 cm/s up in a frame - a lump spread over a few.)
            local z = min(u.z0 + u.r * u.kz, u.top + s.half + 1.0)
            z = min(z, u.zs + 400.0 * dt + 1.0)
            local clear = z - s.half >= u.top - 3.0
            u.gh = (u.gh or 0.0) + ((clear and g or 0.0) - (u.gh or 0.0)) * min(1.0, dt * 12.0)
            local n = { X = u.x0 + (u.tx - u.x0) * u.gh, Y = u.y0 + (u.ty - u.y0) * u.gh, Z = z }
            u.zs = n.Z
            pawn:K2_SetActorLocationAndRotation(n, { Pitch = 0.0, Yaw = s.yaw, Roll = 0.0 }, false, {}, true)
        end)
        if not playing or (u.pos or 0.0) >= UP_END or os.clock() - s.t0 > 3.0 then
            finish(pawn, "out, on top", true)
        end
    end
end

function M.forget() st = nil; off_on = nil; pending = nil; M.rm_back = nil end

return M
