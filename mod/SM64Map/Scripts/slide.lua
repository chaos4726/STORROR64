-- Sliding down Mario 64's slides (mario_actions_moving.c act_butt_slide, update_sliding, update_sliding_angle;
-- mario.c mario_floor_is_slope): in the slide courses - Princess's Secret Slide, Cool, Cool Mountain's slide, Tall,
-- Tall Mountain's slide (TERRAIN_SLIDE: every floor "very slippery") - a slope of more than 5 degrees under him and he
-- slides: 10 a frame faster down the fall line each frame (times the slope's steepness), 2% lost a frame, up to 100 a
-- frame; the stick turns the slide its way and pulling against it brakes. Off a lip he flies on and lands sliding;
-- on the flat he slows and stops, and the jump button hops him off it. STORROR's own slope slide is his stance; he is
-- moved in the engine's flying mode with STORROR's controls off (as shell.lua). Mario 64 units, 30 frames a second.
-- (On foot the slides were walks - PSS's 21 seconds and the penguin's race out of reach, 2026-10-15.)
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET
local M = {}
-- OFF since 2026-10-16 (the user: "remove it and use storrors original sliding"): the slide courses are STORROR's
-- own sliding again. Set true to bring the Mario 64 slide back.
M.enabled = false

local U = 0.75
local LOCK = "SM64Slide"
local SLOPE = 0.9961947         -- (cos 5 degrees: a steeper floor is a slope to slide down)
local ANIM = "/SPP/SPPCharacter/Animation/Falling/Slide_Slope/FallingSlide_Slope_766_slides_31_08_24-002.FallingSlide_Slope_766_slides_31_08_24-002"
local SCENES = { pss = true, ccm_2 = true, ttm_2 = true, ttm_3 = true, ttm_4 = true }

local sl = nil                  -- the slide: { x, y, z (feet, scene cm), vx, vy (Mario units a frame, scene axes), vz, ... }
local cool = 0.0
local was_a = false
local fall = nil
local A = { glide = nil, last_sp = 0.0, last_t = -1.0 }   -- (STORROR's own slide, helped along: see assist below)

local function sfx(name, v) local S = package.loaded["sfx"]; if S then pcall(S.play, name, v) end end

local function hold(s, pawn, on)
    local pc = lib.controller()
    pcall(function() pc:SetIgnoreMoveInput(on) end)
    pcall(function() if on then pawn:DisableInput(pc) else pawn:EnableInput(pc) end end)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            local cname = o:GetClass():GetFName():ToString()
            if cname == "LocomotionComponent" then
                o:EnableLocomotionInputCallback(FName(LOCK), not on)
                o:EnableAdvancedLocomotionInput(FName(LOCK), not on)
            elseif cname == "ParkourComponent" then
                o:ClearInputQueue()
                o:EnableAllParkourInputs(FName(LOCK), not on)
            end
        end
    end)
    local cm = pawn.CharacterMovement
    if on then
        pcall(function()
            local anim = pawn.Mesh:GetAnimInstance()
            s.pa, s.root_motion = anim, anim.RootMotionMode
            anim:SetRootMotionMode(1)
            local seq = lib.try_load(ANIM)
            if seq then s.clip = anim:PlaySlotAnimationAsDynamicMontage(seq, FName("FullBody"), 0.2, 0.25, 1.0, 100000, -1.0, 0.0) end
        end)
        pcall(function()
            s.max_fly, s.brake = cm.MaxFlySpeed, cm.BrakingDecelerationFlying
            cm:SetMovementMode(5, 0)
            cm.MaxFlySpeed, cm.BrakingDecelerationFlying = 4000.0, 0.0
        end)
    else
        pcall(function()
            if s.pa and s.pa:IsValid() then
                if s.clip and s.clip:IsValid() then s.pa:Montage_Stop(0.25, s.clip) end
                s.pa:SetRootMotionMode(s.root_motion or 2)
            end
        end)
        pcall(function()
            if s.max_fly then cm.MaxFlySpeed = s.max_fly end
            if s.brake then cm.BrakingDecelerationFlying = s.brake end
        end)
    end
end

-- the stick, camera-relative: the way (scene, unit) and how far (0..1), or nil
local function intended()
    local x, y = 0.0, 0.0
    if M.test then x, y = M.test.x or 0.0, M.test.y or 0.0
    else
        local pc = lib.controller()
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
    end
    local mag = math.sqrt(x * x + y * y)
    if mag < 0.2 then return nil end
    local cyaw = 0.0
    pcall(function() cyaw = lib.controller():GetControlRotation().Yaw end)
    local a = math.rad(cyaw + math.deg(math.atan(x, y)))
    return math.cos(a), math.sin(a), math.min(1.0, mag)
end

local function a_down()
    if M.test then return M.test.a and true or false end
    local P = package.loaded["pad"]
    return P and P.down and P.down("ok") or false
end

local function stop(pawn, why, hop)
    local s = sl
    sl = nil
    if not s then return end
    hold(s, pawn, false)
    pcall(function()
        local cm = pawn.CharacterMovement
        cm:SetMovementMode(3, 0)
        local k = U * 30.0
        cm.Velocity = { X = s.vx * k * (hop and 0.8 or 0.3), Y = s.vy * k * (hop and 0.8 or 0.3), Z = hop and 520.0 or 0.0 }
    end)
    local G = package.loaded["game"]
    if G then
        if G.carried == "slide" then G.carried = nil end
        if G.parkour_reset then pcall(G.parkour_reset, pawn) end
    end
    cool = hop and 0.6 or 0.3
    fall = { softened = false, t = 0.0 }
    log("slide: off (%s)", why)
end

function M.active() return sl ~= nil end
-- A flip played out before STORROR's slope slide can take it: while one of its flips plays (a montage "MontageFlip..."),
-- the slide floors' own pieces (game.lua G.add_slides, a slide course's whole floor) stop answering its "Slide" trace
-- channel, 18 - he stands on them as ever, but its slide does not begin - and answer it again the moment the flip is
-- done. A flip onto Cool, Cool Mountain's snow was cut off the moment it came down on it: "animation when flipping
-- getting canceled for some reason", then "Yes, finish flips", 2026-11-05.
M.FLIP = { pmcs = {}, off = false, at = -99.0 }
function M.set_slide_pmcs(list) M.FLIP.pmcs, M.FLIP.off = list or {}, false end
function M.add_slide_pmc(p) M.FLIP.pmcs[#M.FLIP.pmcs + 1] = p end
function M.flip_tick(pawn)
    local F = M.FLIP
    if #F.pmcs == 0 then return end
    local mt = nil
    pcall(function()
        local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
        if m and m:IsValid() then mt = m:GetFName():ToString() end
    end)
    local now = os.clock()
    if mt and mt:find("^MontageFlip") then F.at = now end
    local off = now - F.at < 0.05
    if off ~= F.off then
        F.off = off
        for _, p in ipairs(F.pmcs) do
            pcall(function() if p:IsValid() then p:SetCollisionResponseToChannel(18, off and 0 or 2) end end)
        end
        log("slide: %s", off and "a flip - the slide floors out of STORROR's slide's sight till it is done" or "the flip done - the slide floors seen again")
    end
end

function M.forget()
    M.FLIP.pmcs, M.FLIP.off = {}, false        -- (the old map's pieces: never touched again)
    if sl then local G = package.loaded["game"]; if G and G.carried == "slide" then G.carried = nil end end
    sl, fall = nil, nil
    A.glide, A.last_t, A.slid = nil, -1.0, nil
end
function M.clear()
    local pawn = lib.pawn()
    if sl and pawn then stop(pawn, "the scene goes") end
    if A.glide and pawn then
        local g = A.glide
        A.glide = nil
        hold(g, pawn, false)
        pcall(function() pawn.CharacterMovement:SetMovementMode(1, 0) end)
        local G = package.loaded["game"]
        if G and G.carried == "slide" then G.carried = nil end
    end
    A.last_t, A.slid = -1.0, nil
end

-- one Mario 64 frame of the slide (update_sliding with the very slippery floor's numbers)
local function step(s, G)
    local fz, nx, ny, nz = G.floor_normal(s.x, s.y, s.z + 60.0)
    local grounded = fz and s.z - fz < 8.0 and (s.vz or 0.0) <= 0.0
    local ix, iy, mag = intended()
    if grounded then
        local loss = 0.98
        if ix then
            local sp = math.sqrt(s.vx * s.vx + s.vy * s.vy)
            local dx, dy = sp > 0.01 and s.vx / sp or ix, sp > 0.01 and s.vy / sp or iy
            local forward = dx * ix + dy * iy
            local sideward = dx * iy - dy * ix                          -- (sin of the angle from the slide to the stick)
            if forward < 0.0 and sp >= 0.0 then forward = forward * (0.5 + 0.5 * math.min(sp, 100.0) / 100.0) end
            loss = mag * forward * 0.02 + 0.98
            -- (the slide turned toward the stick: speed kept, way changed)
            local e = mag * sideward * 0.05
            s.vx, s.vy = s.vx * math.cos(e) - s.vy * math.sin(e), s.vx * math.sin(e) + s.vy * math.cos(e)
        end
        if nz and nz < 0.9999 then
            s.vx = s.vx + 10.0 * nx
            s.vy = s.vy + 10.0 * ny
        end
        s.vx, s.vy = s.vx * loss, s.vy * loss
        s.vz = 0.0
    else
        s.vz = (s.vz or 0.0) - 4.0                                      -- (off a lip: Mario 64's 4 a frame down)
    end
    local sp = math.sqrt(s.vx * s.vx + s.vy * s.vy)
    if sp > 100.0 then s.vx, s.vy, sp = s.vx * 100.0 / sp, s.vy * 100.0 / sp, 100.0 end
    -- on the flat and slow: stopped (update_sliding's stopSpeed, act_butt_slide: 4)
    if grounded and nz and nz >= SLOPE and sp < 4.0 then return "stopped" end
    local tx, ty = s.x + s.vx * U, s.y + s.vy * U
    -- a wall in the way: pushed back off it and turned along it, the way into it lost (the slide's banked walls)
    if G.wall_near then
        for _ = 1, 2 do
            local hit, wx, wy = G.wall_near(tx, ty, s.z + 60.0, 40.0)
            if not hit then break end
            local l = math.sqrt(wx * wx + wy * wy)
            if l > 1e-6 then
                local ux, uy = wx / l, wy / l
                local vn = s.vx * ux + s.vy * uy
                if vn < 0.0 then s.vx, s.vy = (s.vx - vn * ux) * 0.97, (s.vy - vn * uy) * 0.97 end
            end
            tx, ty = tx + wx, ty + wy
        end
    end
    local gz = G.floor_normal(tx, ty, s.z + 60.0)
    if not gz then
        -- (nothing under the step: straight on along the way he is going, then held where he is)
        gz = G.floor_normal(s.x, s.y, s.z + 60.0)
        if not gz then return "edge" end
        tx, ty = s.x, s.y
        s.vx, s.vy = s.vx * 0.5, s.vy * 0.5
    end
    if gz > s.z + 50.0 then return "wall" end
    s.x, s.y = tx, ty
    local nzv = s.z + s.vz * U
    if nzv <= gz or (grounded and gz >= s.z - 40.0) then s.z, s.vz = gz, 0.0 else s.z = nzv end
    return nil
end

-- STORROR's own slide, helped along (on while M.enabled - the Mario 64 slide above - is off). On the slide courses
-- game.lua makes every slope over 5 degrees too steep to walk, so STORROR's own slope slide (its Slide_Slope falling
-- move) takes him down them. On its own it was slow (2-5 m/s) and stood him up on every flat stretch. Here, while
-- STORROR slides: a pull down the fall line (ASSIST_ACC x the slope's steepness), the stick turning the slide its
-- way, up to ASSIST_MAX. Run onto the flat faster than KEEP and he goes on sliding (held in STORROR's slide pose,
-- moved by the mod as the Mario 64 slide was), losing GLIDE_LOSS a frame (Mario 64's 2% lost too much, the user said),
-- till he is slow - then on his feet - or the floor drops away again, when STORROR's slide takes him back. A hop off a
-- bump mid-slide carries the slide's speed to where he lands.
local ASSIST_ACC = 2400.0       -- cm/s/s down a slope, times its steepness (sin of its angle)
local ASSIST_ACC_COURSE = 4800.0    -- the same on the slide courses: Mario 64's very slippery slide pulls 10 units a frame
                                -- (6750 cm/s/s) and swings him round its banked turns; at 2400 the athlete went straight
                                -- on into the wall at the CCM slide's first bend, lost his speed and stuck, 2026-10-18
local ASSIST_MAX = 1700.0       -- cm/s
local ASSIST_STEER = 3.2        -- rad/s at full stick (2.4 too slow to turn in time onto TTM's slide's wooden ramp, 2026-10-27)
-- (going up a slope with his speed, the pull back down it is this much of itself: Mario 64's slide carries him up its
-- kickers on his speed - at the whole pull he fell back down TTM's slide's 28-degree lip onto its wooden ramp, "couldnt
-- make it up the small bump", 2026-10-27)
local UPHILL_PULL, UPHILL_FAST = 0.5, 400.0
-- (and all but stopped on a slide course - wedged in a corner, on a stretch too gentle to pull him: the stick takes him
-- on, as Mario 64's Mario gets up and walks; at no speed it could not even turn him - "stopping randomly on slide")
local PUSH_ACC, PUSH_MAX = 1500.0, 500.0
local KEEP = 320.0              -- cm/s onto the flat to keep sliding
local GLIDE_STOP = 140.0        -- cm/s: slow enough to stand up
local GLIDE_LOSS = 0.998        -- of his speed kept each 30th of a second on the flat (about 6% a second lost; 0.995 lost
                                -- too much - "you loose too much speed on the flat parts of the slid", 2026-10-17)
local GLIDE_BRAKE = 0.98        -- the same on a dead flat floor (under 1 degree): Mario 64's very slippery floor, 2% lost a
                                -- frame - 0.90 stopped him dead on the flat stretches mid-slide ("secret slide needs some
                                -- work on flat surfaces the charater stops sliding", 2026-10-17); still about 3 s to a stop
                                -- at the slide's end
local DEAD_FLAT = 0.9998477     -- (cos 1 degree: Mario 64's mario_floor_is_slippery stops a slide on flatter floors)
-- (and a slide course's banked turns: a face steeper than this - 46 degrees - he does not go up, his speed up it taken
-- off. TTM's slide's outer banks are 63 degrees and 2.3 m tall with nothing over them: at full speed he rode up one and
-- off its top - "glitched through the slide", 2026-10-27. Mario 64's slide swings him round along them.)
local BANK = 0.7
-- (then 0.995: at 0.98 half his speed went each second, and every gentle stretch of Cool, Cool Mountain's way down
-- stopped him - 1650 cm/s to a stand in 4 s - "player keeps getting stopped during slide down mountain", "especially
-- on bridge part", 2026-11-05. And the floor's own slope pulls him along it, down or back - 2400 cm/s/s times its
-- steepness - up to ASSIST_MAX)
local GLIDE_OUT = 0.995         -- off a slide surface outside the slide courses (CCM's mountain): kept a frame, Mario 64's
                                -- butt slide on very slippery ground (update_sliding, 0.92-0.98 by the floor's class) - he
                                -- stood up the moment the slope ran out: "flat surface you stop sliding", 2026-10-18; 0.94
                                -- still stopped him in a second ("slide still stopping on flat section"): about 4 s now
local function storror_sliding(pawn)
    local yes = false
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        local m = ai and ai:IsValid() and ai:GetCurrentActiveMontage()
        if m and m:IsValid() then yes = m:GetFName():ToString():find("FallingSlide_Slope") ~= nil end
    end)
    return yes
end
-- the stick turns (vx, vy) toward its way, at most ASSIST_STEER x dt
local function steer(vx, vy, dt)
    local ix, iy, mag = intended()
    if not ix then return vx, vy end
    local sp = math.sqrt(vx * vx + vy * vy)
    if sp < 1.0 then return vx, vy end
    local a = math.atan(vy, vx)
    local d = math.atan(iy, ix) - a
    d = (d + math.pi) % (2.0 * math.pi) - math.pi
    local turn = math.max(-ASSIST_STEER * mag * dt, math.min(ASSIST_STEER * mag * dt, d))
    -- (pulling straight back brakes a little, as Mario 64's does)
    local back = math.abs(d) > 2.4 and (1.0 - 0.6 * mag * dt) or 1.0
    return math.cos(a + turn) * sp * back, math.sin(a + turn) * sp * back
end
local function glide_end(pawn, how)
    local g = A.glide
    A.glide = nil
    if not g then return end
    hold(g, pawn, false)
    pcall(function()
        local cm = pawn.CharacterMovement
        cm:SetMovementMode((how == "slope" or how == "hop") and 3 or 1, 0)
        local k = how == "hop" and 0.8 or 1.0
        cm.Velocity = { X = g.vx * k, Y = g.vy * k, Z = how == "hop" and 520.0 or 0.0 }
    end)
    local G = package.loaded["game"]
    if G and G.carried == "slide" then G.carried = nil end
    if how ~= "slope" and G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
    -- (off a bump or onto a slope: his speed kept, so a landing on the flat glides on again - a little drop on a flat
    -- stretch stood him up: "slide still stopping on flat section", 2026-10-18)
    if how == "slope" then
        local now = os.clock()
        A.last_sp, A.last_t, A.last_vx, A.last_vy, A.slid = math.sqrt(g.vx * g.vx + g.vy * g.vy), now, g.vx, g.vy, now
    end
end
local function assist(dt, pawn, x, y, z, scene)
    local G = package.loaded["game"]
    -- (a hitch's long frame not taken as that much pull, push and steering at once: "I lagged on the slide and it killed
    -- me", 2026-10-27)
    dt = math.min(dt, 1.0 / 20.0)
    -- (the slide courses; and the slide surfaces of every other scene - game.lua G.add_slides - pulled and steered, not
    -- carried over their flats)
    local course = SCENES[scene or ""]
    if not ((course or (G and G.slides_in == scene)) and G and G.floor_normal) or G.warping or G.pending or G.dying or G.cutscene then
        if A.glide then glide_end(pawn, "off") end
        return
    end
    local cm = pawn.CharacterMovement
    local mode = cm.MovementMode
    -- (on a slide course its steep banks are slopes to him too, not walls: G.floor_normal's `steep`)
    local fz, nx, ny, nz = G.floor_normal(x, y, z + 40.0, course)
    if A.glide then
        local g = A.glide
        -- (a jump, or the floor sloping or dropping away again: STORROR's own moves have him)
        if a_down() and not was_a then glide_end(pawn, "hop"); return end
        if not fz or z - fz > 40.0 or (nz and nz < SLOPE) then glide_end(pawn, "slope"); return end
        -- (off the slide - the dead flat floor at its bottom - he slows to a stop; the user: "once you come off the
        -- slide the charater needs to slow down and stop")
        -- (the slide's end brakes him - in PSS only past its finish, the clock stopped: its flat stretches before it
        -- glide on like the rest)
        local over = true
        if scene == "pss" then over = G.pss ~= nil and not G.pss.running end
        local k = ((not course and GLIDE_OUT) or ((nz and nz >= DEAD_FLAT and over) and GLIDE_BRAKE or GLIDE_LOSS))
        -- (on TTM's and CCM's slides, as Mario 64's update_sliding on its very slippery floor: 0.98 a frame, and up to
        -- none lost with the stick held his way - a dead flat stretch mid-slide braked him to a stop whatever he did,
        -- "some sections of the slide completely stop the player", 2026-10-27)
        if course and scene ~= "pss" then
            local ix, iy, mag = intended()
            local sp0 = math.sqrt(g.vx * g.vx + g.vy * g.vy)
            local fwd = (ix and sp0 > 1.0) and (ix * g.vx + iy * g.vy) / sp0 or 0.0
            local km = math.min(1.0, 0.98 + 0.02 * (mag or 0.0) * fwd)
            k = (nz and nz >= DEAD_FLAT) and km or math.max(km, GLIDE_LOSS)
        end
        k = k ^ (dt * 30.0)
        g.vx, g.vy = steer(g.vx * k, g.vy * k, dt)
        -- (the floor's slope: down it he gains, up it he loses - its normal's lean across is the way down it)
        if not course and nx and ny then
            g.vx, g.vy = g.vx + nx * 2400.0 * dt, g.vy + ny * 2400.0 * dt
            local s2 = math.sqrt(g.vx * g.vx + g.vy * g.vy)
            if s2 > ASSIST_MAX then g.vx, g.vy = g.vx / s2 * ASSIST_MAX, g.vy / s2 * ASSIST_MAX end
        end
        local sp = math.sqrt(g.vx * g.vx + g.vy * g.vy)
        if sp < GLIDE_STOP then glide_end(pawn, "stand"); return end
        -- (a step up on the flat - a lip between its pieces: lifted onto it from just before it, as Mario 64's ground step
        -- takes him up one; held against it he pushed on at his speed - the stick held his way lost him nothing - and
        -- stood there: "still stopped randomly in some sections", 2026-10-27. Taller than 50, or held fast all the same:
        -- off the glide, on his own feet)
        local tfz = fz
        local afz = G.floor_normal(x + g.vx / sp * 45.0, y + g.vy / sp * 45.0, z + 60.0, course)
        if afz and afz > fz and afz - fz < 50.0 then tfz = afz end
        if g.lx then
            local moved = math.sqrt((x - g.lx) ^ 2 + (y - g.ly) ^ 2)
            g.stuck = (moved < sp * dt * 0.25) and (g.stuck or 0) + 1 or 0
            if g.stuck >= 6 then
                log("slide: held fast gliding at (%.0f, %.0f, %.0f) in %s - on his feet", x, y, z, tostring(scene))
                glide_end(pawn, "stand")
                return
            end
        end
        g.lx, g.ly = x, y
        pcall(function()
            local half = G.half or 90.0
            local l = pawn:K2_GetActorLocation()
            local tz = tfz + 3.0 + half + OFFSET.Z
            if cm.MovementMode ~= 5 then cm:SetMovementMode(5, 0) end
            cm.Velocity = { X = g.vx, Y = g.vy, Z = (tz - l.Z) * 0.7 / math.max(dt, 1.0 / 120.0) }
            pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = math.deg(math.atan(g.vy, g.vx)), Roll = 0.0 }, false)
        end)
        local S = package.loaded["sfx"]
        if S and S.hold then S.hold("loop_rough_slide", math.min(0.8, 0.2 + sp / 1500.0)) end
        return
    end
    local v = pawn:GetVelocity()
    local vx, vy = v.X, v.Y
    local sp = math.sqrt(vx * vx + vy * vy)
    local now = os.clock()
    -- (on a slide course, on any slope he is not standing on, slide pose or not: knocked out of STORROR's slide pose by
    -- a wall, he lost the pull and sat wedged where two banked slopes meet - "slide still stopping", 2026-10-18)
    if mode == 3 and fz and z - fz < 40.0 and (storror_sliding(pawn) or (course and nz and nz < SLOPE)) then
        -- (into a rise - a slide course's kickers: Mario 64's slide keeps him on the floor and carries him up it on his
        -- speed. The engine, sliding him, will not lift him along a face too steep to stand on - every slope, on a slide
        -- course - and stopped him short at its foot or turned him off along it: TTM's slide's lip onto its wooden ramp,
        -- "couldnt make it up the small bump", 2026-10-27. A slope rising ahead that he could ride - not a wall, not a
        -- bank - lifts him along it at his speed; and stopped short at its foot, his speed and way are given back)
        local lift = nil
        local lost = course and A.last_t > 0.0 and now - A.last_t < 0.15 and A.last_sp > UPHILL_FAST and sp < A.last_sp * 0.9
        if course and fz and (sp > UPHILL_FAST * 0.5 or lost) then
            local dvx, dvy, dsp = vx, vy, sp
            if lost then dvx, dvy, dsp = A.last_vx, A.last_vy, A.last_sp end
            local ux, uy = dvx / dsp, dvy / dsp
            local az, anx, any, anz = G.floor_normal(x + ux * 80.0, y + uy * 80.0, z + 150.0, true)
            -- (met head-on, as a kicker is - not a banked turn's side he runs along: lifted up that, he went up and over
            -- it and off the slide, 2026-10-27)
            local ah = (anx and any) and math.sqrt(anx * anx + any * any) or 0.0
            local head_on = ah > 0.01 and -(ux * anx + uy * any) / ah > 0.8
            -- (or met slantwise, as he turns onto it, where the floor goes on past its top - a kicker's way on; a bank's top
            -- has nothing past it: TTM's slide's lip onto its wooden ramp is taken turning off the run down beside it,
            -- "player couldnt make it onto wood ramp again because of small bump", 2026-10-27)
            if not head_on and ah > 0.01 and az then
                local bx, by = x - anx / ah * 300.0, y - any / ah * 300.0
                local bz = G.floor_normal(bx, by, az + 200.0, true)
                head_on = bz ~= nil and bz > fz - 60.0
            end
            if az and anz and anz > 0.6 and anz < 0.985 and az > fz + 3.0 and head_on then
                if lost then vx, vy, sp = dvx, dvy, dsp end
                lift = sp * (az - fz) / 80.0 + 60.0
            elseif lost and sp > A.last_sp * 0.15 then
                -- (turned off along what he met - a trough's side, a wall met slantwise - his speed kept that way, as Mario
                -- 64's slide runs on along a slope it meets: TTM's slide's run beside its wooden ramp is a trough, and
                -- turning for the ramp too soon he hit its side and stopped dead, 2026-10-27. Head-on, he stops)
                vx, vy, sp = vx / sp * A.last_sp, vy / sp * A.last_sp, A.last_sp
            end
        end
        -- (STORROR sliding: the pull down the fall line - the floor's normal leans the way down - and the stick)
        local h = nx and math.sqrt(nx * nx + ny * ny) or 0.0
        local acc = course and ASSIST_ACC_COURSE or ASSIST_ACC
        if h > 0.01 then
            if (vx * nx + vy * ny) < 0.0 and sp > UPHILL_FAST then acc = acc * UPHILL_PULL end      -- (on up it, on his speed)
            vx = vx + nx / h * acc * h * dt
            vy = vy + ny / h * acc * h * dt
        end
        if course and sp < PUSH_MAX then
            local ix, iy, mag = intended()
            if ix then vx, vy = vx + ix * PUSH_ACC * mag * dt, vy + iy * PUSH_ACC * mag * dt end
        end
        vx, vy = steer(vx, vy, dt)
        -- (a steep bank of a slide course: swung round along it at his speed, never up it and over its top - BANK. Its
        -- way up only taken off, he lost his speed in every banked turn and stopped in TTM's slide's corners - "stopping
        -- randomly on slide", 2026-10-27)
        local vz = v.Z
        if course and nz and nz < BANK and h > 0.01 then
            local ux, uy = -nx / h, -ny / h
            local up = vx * ux + vy * uy
            if up > 0.0 then
                local sp0 = math.sqrt(vx * vx + vy * vy)
                local tx, ty = vx - ux * up, vy - uy * up
                local tl = math.sqrt(tx * tx + ty * ty)
                if tl > 1.0 then vx, vy = tx / tl * sp0, ty / tl * sp0 else vx, vy = tx, ty end
            end
            if vz > 0.0 then vz = 0.0 end
        end
        if lift and vz < lift then vz = lift end
        sp = math.sqrt(vx * vx + vy * vy)
        if sp > ASSIST_MAX then vx, vy, sp = vx * ASSIST_MAX / sp, vy * ASSIST_MAX / sp, ASSIST_MAX end
        pcall(function() cm.Velocity = { X = vx, Y = vy, Z = vz } end)
        A.last_sp, A.last_t, A.last_vx, A.last_vy = sp, now, vx, vy
        -- (where a slide starts, and how steep - to find a slope that should not slide: "okay sliding in random area",
        -- 2026-10-26)
        if not A.slid or now - A.slid > 1.0 then
            log("slide: sliding at (%.0f, %.0f, %.0f) in %s, the floor %.0f degrees", x, y, z, tostring(scene),
                nz and math.deg(math.acos(math.max(-1.0, math.min(1.0, nz)))) or -1)
        end
        A.slid = now
        return
    end
    -- (in the air off a bump mid-slide: the slide's speed kept for where he lands)
    if mode == 3 and A.slid and now - A.slid < 4.0 then
        A.last_sp, A.last_t, A.last_vx, A.last_vy = sp, now, vx, vy
        return
    end
    -- (onto the flat from the slide, fast: on sliding rather than up on his feet)
    if mode == 1 and A.last_t > 0.0 and now - A.last_t < 0.25 and A.last_sp > KEEP and fz and nz and nz >= SLOPE then
        local g = { vx = A.last_vx, vy = A.last_vy }
        A.glide, A.last_t, A.slid = g, -1.0, nil
        hold(g, pawn, true)
        if G then G.carried = "slide" end
        log("slide: on along the flat at %.0f cm/s", A.last_sp)
    end
    if mode == 1 then A.slid = nil end
end
function M.active() return sl ~= nil or A.glide ~= nil end

-- (x, y, z): his feet, scene cm (minus OFFSET)
-- (from one area of a slide course on into the next - TTM's slide's instant warps: his speed goes with him, as Mario 64's
-- does. The change of scene held him still 0.6 s - game.lua's G.freeze - and left him at a standstill at each area's
-- start: "stopping randomly on slide", 2026-10-27. His last speed in a course, kept apart from the slide's own state,
-- which the scene's going clears)
local V = { t = -1.0 }
local function carry_on_areas(pawn, scene)
    local G = package.loaded["game"]
    local now = os.clock()
    if scene ~= V.scene then
        -- (an instant warp's - G.last_node nil: not a warp to a node, a teleport or a respawn at the course's start)
        if SCENES[scene or ""] and SCENES[V.scene or ""] and now - V.t < 1.0 and G and G.last_node == nil then
            V.carry = { vx = V.vx, vy = V.vy }
            if G and G.thaw_at then G.thaw_at = math.min(G.thaw_at, now + 0.15) end
            log("slide: on into %s at %.0f cm/s", tostring(scene), math.sqrt(V.vx * V.vx + V.vy * V.vy))
        end
        V.scene = scene
        return
    end
    if V.carry then
        if G and G.thaw_at then return end
        local c = V.carry
        V.carry = nil
        pcall(function()
            local cm = pawn.CharacterMovement
            cm:SetMovementMode(3, 0)
            cm.Velocity = { X = c.vx, Y = c.vy, Z = 0.0 }
        end)
        A.last_sp, A.last_t, A.last_vx, A.last_vy, A.slid = math.sqrt(c.vx * c.vx + c.vy * c.vy), now, c.vx, c.vy, now
        return
    end
    if SCENES[scene or ""] and not (G and G.thaw_at) then
        local ok, v = pcall(function() return pawn:GetVelocity() end)
        if ok and v and (v.X * v.X + v.Y * v.Y) > 300.0 * 300.0 then V.vx, V.vy, V.t = v.X, v.Y, now end
        -- (a sudden slowdown on a slide course: where, to find what stops him)
        if ok and v then
            local s2 = math.sqrt(v.X * v.X + v.Y * v.Y)
            if V.ps and V.ps > 800.0 and s2 < 300.0 and now - (V.pt or 0.0) < 0.3 and now - (V.logged or 0.0) > 1.0 then
                V.logged = now
                local l = pawn:K2_GetActorLocation()
                log("slide: slowed from %.0f to %.0f cm/s at (%.0f, %.0f, %.0f) in %s, mode %s", V.ps, s2, l.X - OFFSET.X,
                    l.Y - OFFSET.Y, l.Z - OFFSET.Z, tostring(scene), tostring(pawn.CharacterMovement.MovementMode))
            end
            V.ps, V.pt = s2, now
        end
    end
end

function M.update(dt, pawn, x, y, z, scene)
    if pawn then pcall(carry_on_areas, pawn, scene) end
    if pawn and M.flip_tick then pcall(M.flip_tick, pawn) end
    if not M.enabled then
        if pawn then
            local okp, errp = pcall(assist, dt, pawn, x, y, z, scene)
            if not okp then log("slide assist: %s", tostring(errp)) end
            was_a = a_down()
        end
        return
    end
    if not pawn then return end
    local G = package.loaded["game"]
    if fall then
        fall.t = fall.t + dt
        local falling = false
        pcall(function() falling = pawn.CharacterMovement:IsFalling() end)
        if not falling and fall.t > 0.2 then fall = nil
        elseif falling and not fall.softened then
            local fz = G and G.floor_z and G.floor_z(x, y, z + 20.0)
            if fz and z - fz < 60.0 then
                fall.softened = true
                if G.parkour_reset then pcall(G.parkour_reset, pawn) end
            end
        end
        if fall and fall.t > 20.0 then fall = nil end
    end
    local a = a_down()
    local pressed = a and not was_a
    was_a = a
    cool = math.max(0.0, cool - dt)
    if not sl then
        if not SCENES[scene or ""] or cool > 0.0 or not (G and G.floor_normal) then return end
        if G.carried or G.swim or G.cutscene or G.warping or G.pending then return end
        local air = true
        pcall(function() air = pawn.CharacterMovement:IsFalling() end)
        if air then return end
        local fz, nx, ny, nz = G.floor_normal(x, y, z + 30.0)
        if not (fz and nz and nz < SLOPE and z - fz < 15.0) then return end
        -- (onto a slope: he slides, his way and speed for a start)
        local v = { X = 0.0, Y = 0.0 }
        pcall(function() v = pawn:GetVelocity() end)
        sl = { x = x, y = y, z = fz, vx = v.X / (U * 30.0), vy = v.Y / (U * 30.0), vz = 0.0, acc = 0.0, blocked = 0, relock = 0.0 }
        hold(sl, pawn, true)
        if G then G.carried = "slide" end
        fall = nil
        log("slide: down he goes")
        return
    end
    local s = sl
    if pressed then stop(pawn, "a jump", true); return end
    if G and (G.warping or G.pending or G.dying) then stop(pawn, "leaving"); return end
    local px, py = s.x, s.y
    s.acc = math.min(s.acc + dt, 0.2)
    while sl and s.acc >= 1.0 / 30.0 do
        s.acc = s.acc - 1.0 / 30.0
        local r = step(s, G)
        if r then stop(pawn, r); return end
    end
    local half = (G and G.half) or 90.0
    local tx, ty, tz = s.x + OFFSET.X, s.y + OFFSET.Y, s.z + 3.0 + half + OFFSET.Z
    local fx, fy = (s.x - px) / math.max(dt, 1e-3), (s.y - py) / math.max(dt, 1e-3)
    local sp = math.sqrt(s.vx * s.vx + s.vy * s.vy)
    pcall(function()
        local l = pawn:K2_GetActorLocation()
        local cm = pawn.CharacterMovement
        if cm.MovementMode ~= 5 then cm:SetMovementMode(5, 0) end
        local ex, ey, ez = tx - l.X, ty - l.Y, tz - l.Z
        if ex * ex + ey * ey > 150.0 * 150.0 then s.blocked = s.blocked + 1 else s.blocked = 0 end
        local k = 0.7 / math.max(dt, 1.0 / 120.0)
        cm.Velocity = { X = ex * k + fx, Y = ey * k + fy, Z = ez * k }
        if sp > 1.0 then
            pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = math.deg(math.atan(s.vy, s.vx)), Roll = 0.0 }, false)
        end
        if s.pa and s.pa:IsValid() and s.pa.RootMotionMode ~= 1 then s.pa:SetRootMotionMode(1) end
    end)
    if s.blocked > 8 then sfx("en_bonk", 1.0); stop(pawn, "a wall"); return end
    s.relock = s.relock + dt
    if s.relock > 0.5 then
        s.relock = 0.0
        local pc = lib.controller()
        pcall(function() if not pc:IsMoveInputIgnored() then pc:SetIgnoreMoveInput(true) end; pawn:DisableInput(pc) end)  -- (the lock is a count: added to only when off, or every re-lock stayed on after - "randomly stops")
    end
    local S = package.loaded["sfx"]
    if S and S.hold and sp > 2.0 then S.hold("loop_rough_slide", math.min(0.8, 0.2 + sp / 120.0)) end
end

return M
