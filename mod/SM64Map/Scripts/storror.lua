-- SM64Map: the parts of the host game that have no place in Mario 64, kept out of the way.
--
-- STORROR counts the force of every knock taken while ragdolled and turns it into sprains and fractures,
-- shown on a red counter beside the athlete. The injuries stay exactly as the game has them; only the
-- counter is hidden, so that Mario's power meter is the one thing on screen that keeps score.
--
-- Also off the screen while a level is played: the "PREPARING SHADERS" line, the compass, the list of
-- d-pad options at the bottom left, and the session marker's own prompt. And the session marker itself
-- does nothing: a marker to jump back to at any moment would undo every level. The game's code for it
-- cannot be stopped from running, so what it does is undone: its marker is not shown, and a jump to it
-- is put back the moment it happens.
local lib = require("lib")
local M = {}

local comp, comp_pawn = nil, nil

local function component(pawn, name)
    local found = nil
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetClass():GetFName():ToString() == name then found = o end
        end
    end)
    return found
end

local function bail_component(pawn)
    local addr = nil
    pcall(function() addr = pawn:GetAddress() end)
    if comp and comp_pawn == addr then
        local ok, valid = pcall(function() return comp:IsValid() end)
        if ok and valid then return comp end
    end
    comp, comp_pawn = nil, addr
    comp = component(pawn, "BailComponent")
    return comp
end

-- ------------------------------------------------------------ the host game's HUD
-- (the stamina meter was hidden for a while, at the user's ask on 2026-10-14 as it sat on Mario 64's life counter;
-- later the same day "bring back the stamina bar")
local HIDE = { "PrepShadersBP_C", "CompassBarWidgetBP_C", "ActionHintsWidgetBP_C", "SessionMarkerWidgetBP_C",
               "XPNotificationWidgetBP_C" }
-- (STORROR makes its XP notification, a yellow bar and "+6" that sat in the life counter, afresh as XP comes in:
-- it is looked for again every second, not only after the level starts)
local AGAIN = { "XPNotificationWidgetBP_C" }
local again_t = 0.0
local LOOKS = { 1.0, 3.0, 6.0, 12.0, 25.0, 50.0 }       -- seconds after a level starts at which they are looked for
local widgets, looked, since_t, looked_pawn = {}, 0, 0.0, nil

-- (Looking through everything the game has is not something to do every tick: it is done a few times
-- after the athlete appears, and what was found is then watched.)
local function look_for_widgets()
    local found = {}
    for _, cname in ipairs(HIDE) do
        local ok, ws = pcall(function() return FindAllOf(cname) end)
        if ok and ws then
            for i = 1, #ws do
                local w = ws[i]
                pcall(function()
                    if w:IsValid() then
                        found[#found + 1] = w
                        -- (and see-through and shrunk to nothing: some, the stamina meter among them, are shown
                        -- again by the game every frame while they are in use, later in the frame than this runs)
                        w:SetRenderOpacity(0.0)
                        w:SetRenderScale({ X = 0.0, Y = 0.0 })
                    end
                end)
            end
        end
    end
    widgets = found
end

local function hide_widgets(pawn)
    local addr = nil
    pcall(function() addr = pawn:GetAddress() end)
    if addr ~= looked_pawn then looked_pawn, looked, since_t, widgets = addr, 0, os.clock(), {} end
    if LOOKS[looked + 1] and os.clock() - since_t >= LOOKS[looked + 1] then
        looked = looked + 1
        look_for_widgets()
    end
    if os.clock() - again_t > 1.0 then
        again_t = os.clock()
        for _, cname in ipairs(AGAIN) do
            local ok, ws = pcall(function() return FindAllOf(cname) end)
            if ok and ws then
                for i = 1, #ws do
                    pcall(function()
                        local w = ws[i]
                        if w:IsValid() and w.RenderTransform.Scale.X ~= 0.0 then
                            w:SetRenderOpacity(0.0)
                            w:SetRenderScale({ X = 0.0, Y = 0.0 })
                            widgets[#widgets + 1] = w
                        end
                    end)
                end
            end
        end
    end
    for _, w in ipairs(widgets) do
        -- the game brings some of them back by itself; each is put away again before it is drawn
        pcall(function() if w:IsValid() and w:GetVisibility() ~= 1 then w:SetVisibility(1) end end)
    end
end

-- ------------------------------------------------------------ the session marker
local hooked, hook_tries = false, 0
local before = nil              -- where the athlete was when the game began a jump to the marker
local guard_until = 0.0         -- for a few seconds after, any sudden jump is put back too
local last = nil                -- where the athlete was a tick ago
local marker_comp, marker_pawn, decal_addr = nil, nil, nil

local function in_level() return _G.MENU ~= nil and _G.MENU.state == "game" end

local function hook()
    hook_tries = hook_tries + 1
    local ok, err = pcall(function()
        RegisterHook("/Script/SPP.SessionMarkerComponent:TravelToLocation", function(ctx)
            before = nil
            if not in_level() then return end
            pcall(function()
                local pawn = ctx:get():GetOwner()
                local l, r = pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation()
                before = { pawn = pawn, loc = { X = l.X, Y = l.Y, Z = l.Z }, rot = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } }
            end)
        end, function()
            if not before then return end
            guard_until = os.clock() + 3.0
            pcall(function() before.pawn:K2_TeleportTo(before.loc, before.rot) end)
            lib.log("a jump to the session marker was undone")
        end)
    end)
    if ok then hooked = true; lib.log("the session marker is switched off")
    elseif hook_tries == 1 then lib.log("the session marker could not be reached yet: %s", tostring(err)) end
end

local function quiet_marker(pawn)
    if not hooked and hook_tries < 5 then hook() end
    local addr = nil
    pcall(function() addr = pawn:GetAddress() end)
    if addr ~= marker_pawn then
        marker_pawn, marker_comp, decal_addr, last = addr, component(pawn, "SessionMarkerComponent"), nil, nil
        -- the jump back to the marker is switched off at its source, with the marker's own switch for its
        -- input (the hook on TravelToLocation below never saw a jump: the game does not go through it)
        if marker_comp then
            local ok = pcall(function() marker_comp:EnableResetPlayerInput(FName("SM64Map"), false) end)
            lib.log("the session marker's jump is %s", ok and "switched off" or "still on (the switch failed)")
            -- and placing one makes no sound (the game skips a sound that is not there)
            for _, n in ipairs({ "PlaceMarkerSound", "TravelToMarkerSound", "RevertTravelSound" }) do
                pcall(function() marker_comp[n] = nil end)
            end
        end
    end
    -- its marker on the ground is not shown: the game shows it again at every placing, so it is looked at
    -- every tick (a property read) and hidden again whenever it is showing
    if marker_comp then
        pcall(function()
            local d = marker_comp.SpawnDecalActor
            if d and d:IsValid() and not d.bHidden then
                decal_addr = d:GetAddress()
                d:SetActorHiddenInGame(true)
            end
        end)
    end
    -- a jump that comes a moment after the game was asked for one (it may not make it at once) is put back
    local now = os.clock()
    pcall(function()
        local l = pawn:K2_GetActorLocation()
        if last and now < guard_until then
            local dx, dy, dz = l.X - last.X, l.Y - last.Y, l.Z - last.Z
            if dx * dx + dy * dy + dz * dz > 800.0 * 800.0 then
                pawn:K2_TeleportTo(last, pawn:K2_GetActorRotation())
                lib.log("a late jump to the session marker was undone")
                return
            end
        end
        last = { X = l.X, Y = l.Y, Z = l.Z }
    end)
end

-- No motion blur anywhere ("no motion blur please", 2026-10-14): the renderer's own switch, looked at every few
-- seconds as STORROR's graphics settings can set it again.
local blur_t = 0.0
local function no_motion_blur()
    if os.clock() - blur_t < 3.0 then return end
    blur_t = os.clock()
    pcall(function()
        local KSL = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        if KSL:GetConsoleVariableIntValue("r.MotionBlurQuality") ~= 0 then
            KSL:ExecuteConsoleCommand(lib.world(), "r.MotionBlurQuality 0", lib.controller())
            lib.log("motion blur off")
        end
    end)
end

-- ------------------------------------------------------------ a vault's speed kept at its hand-back
-- STORROR hands him back out of a vault with speed to go on with: in a fresh session 65% of the vault's own or more
-- (3 to 5 m/s out of every vault recorded, 2026-10-22). Late in a session - after some hours, a good many falls and
-- ragdolls - it handed him back with 4 to 12% of it, and every slow vault and kong over the lobby fence died on it and
-- dropped him back on his side ("the fence bug", "kong flips not working tho"; a restart put it right, as it had the
-- first time). What builds up is STORROR's own and not yet known (its injuries, kept by the session marker the mod keeps
-- off, are the likeliest). So: handed back from a vault with under KEEP of its speed, he keeps the vault's speed for
-- CARRY seconds and goes on as the clip shows him. In a fresh session this never happens; nothing moves him.
-- (CARRY at most - it ends as he lands: 0.3 s ran out mid-flip in a kong front or a kong gainer, and he dropped on the
-- fence all the same - "kong gainers not working on fences", "same as kong front", 2026-11-02)
local KEEP, CARRY = 0.4, 1.5
local VK = { v5 = nil, carry = nil, done_t = -1.0 }
local function vault_carry(pawn)
    local cm = pawn.CharacterMovement
    local name = ""
    pcall(function()
        local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
        if m and m:IsValid() then name = m:GetFName():ToString() end
    end)
    local vault = name:find("Vault") ~= nil
    local mode = cm.MovementMode
    local v = cm.Velocity
    local sp = math.sqrt(v.X * v.X + v.Y * v.Y)
    local now = os.clock()
    -- (carrying on: the vault's speed kept while he falls on)
    local c = VK.carry
    if c then
        if mode ~= 3 or now > c.till then VK.carry = nil
        elseif sp < 0.8 * c.sp then cm.Velocity = { X = c.vx, Y = c.vy, Z = v.Z } end
        return
    end
    if vault and mode == 5 then
        -- (its fastest and highest kept too, not only its last: a kong gainer slows and sinks in its own clip before the
        -- hand-back - 558 down to 189 cm/s, its rise 533 down to 214 - and at its last it looked handed back whole; no
        -- bump, "no bump on kong gainer, kong front however is working", 2026-11-02)
        if sp > 150.0 then
            local q = VK.v5
            if not q or now - q.t > 0.3 then q = { max_sp = 0.0, max_vz = 0.0 }; VK.v5 = q end
            q.vx, q.vy, q.vz, q.sp, q.t = v.X, v.Y, v.Z, sp, now
            if sp > q.max_sp then q.max_sp = sp end
            if v.Z > q.max_vz then q.max_vz = v.Z end
        end
        return
    end
    local p = VK.v5
    if not (vault and mode == 3 and p and now - p.t < 0.2 and now - VK.done_t > 1.0) then return end
    if sp >= KEEP * (p.max_sp or p.sp) then
        if now - p.t > 0.05 then VK.v5 = nil end       -- (kept by STORROR: nothing to do)
        return
    end
    VK.done_t, VK.v5 = now, nil
    -- (on the way it last went, at what a fresh session hands back - 65% of its fastest - or its last, if that is more)
    local go = math.max(p.sp, 0.65 * (p.max_sp or p.sp))
    local vx, vy = p.vx / p.sp * go, p.vy / p.sp * go
    VK.carry = { vx = vx, vy = vy, sp = go, till = now + CARRY }
    -- (and its rise: the hand-back took that too - a kong front's or a kong gainer's flip went up 40 cm, not over, and
    -- off the balcony's railing he fell flat on the floor below: "still not working", 2026-11-02 - its highest, the bump
    -- a fresh session gives it: "usually it bumps the player upwards a bit so it can get it off")
    cm.Velocity = { X = vx, Y = vy, Z = math.max(v.Z, p.max_vz or p.vz or v.Z) }
    lib.log("vault: handed back with %.0f of its %.0f cm/s (%s) - its speed kept", sp, p.sp, name:sub(1, 44))
end

-- every tick, with the player's character
-- STORROR's camera arm (HitsSpringArmComponent) let shorter, as near as M.CAM_MIN cm: it stops at walls, but never came
-- in closer than its own MinSpringArmDistance, a metre - with a wall nearer than that behind him the camera sat in it
-- ("when coming out of teleport on bomb omb battlefield the camera is inside the mountain", "camera also goes through
-- walls", 2026-11-05). Looked to twice a second: put back if anything sets it again; the arm found again for a new body.
M.CAM_MIN = 30.0
local cam = { arm = nil, pawn = nil, next = 0.0 }
local function camera_arm(pawn)
    local now = os.clock()
    if now < cam.next then return end
    cam.next = now + 0.5
    local pa = nil
    pcall(function() pa = pawn:GetAddress() end)
    local ok = cam.arm ~= nil and cam.pawn == pa and pcall(function() return cam.arm:IsValid() end) and cam.arm:IsValid()
    if not ok then
        cam.arm, cam.pawn = nil, pa
        pcall(function()
            for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
                local o = c:get()
                if o:GetClass():GetFName():ToString() == "HitsSpringArmComponent" then cam.arm = o end
            end
        end)
        if not cam.arm then return end
    end
    pcall(function()
        local v = cam.arm.MinSpringArmDistance
        if type(v) == "number" and math.abs(v - M.CAM_MIN) > 0.5 then
            cam.arm.MinSpringArmDistance = M.CAM_MIN
            lib.log("camera: its arm may come in to %.0f cm at walls (was %.0f)", M.CAM_MIN, v)
        end
    end)
end
function M.forget_camera() cam.arm, cam.pawn, cam.next, cam.camc, cam.pulled = nil, nil, 0.0, nil, nil end

-- The camera kept this side of walls: STORROR's arm left it on a wall's very face, the view clipping into it, and its lag
-- swung it metres out behind walls as it turned ("camera goes through walls", "Everywhere", 2026-11-07: seen 9.8 m out
-- with a wall at 4). Each frame a ball `CAM_BALL` cm round is swept from the arm's start to its end - the end as STORROR's
-- arm has it, its own socket (SpringEndpoint), never worked out from the camera: a first try did that, each pull fed the
-- next, and the camera went 1e125 cm out of the map. Meeting anything, the camera is put on that line `CAM_PAD` short of
-- where the ball stopped (never nearer him than CAM_MIN); the way clear, it is given back to STORROR as it was. An arm
-- longer than `CAM_SANE` cm, or any error, and the guard turns itself off. The ball begun inside something - the floor
-- he crouches on, a piece he wears - a plain line is tested instead, and anything within `CAM_NEAR` cm of the arm's
-- start let be (his own, STORROR's arm sees to walls that near): the ball's start inside took the camera in to 30 cm,
-- 14 times in 2 minutes ("camera zooms in real close randomly?", 2026-11-07).
M.CAM_BALL, M.CAM_PAD, M.CAM_SANE, M.CAM_NEAR = 20.0, 10.0, 3000.0, 25.0
M.CAM_GUARD = true
local CAM_C0 = { R = 0.0, G = 0.0, B = 0.0, A = 0.0 }
local CAM_END = nil
function M.camera_guard(pawn)
    local arm = cam.arm
    if not (M.CAM_GUARD and arm) then return end
    if not cam.camc or cam.camc_pawn ~= cam.pawn then
        cam.camc, cam.pulled = nil, nil
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetFName():ToString() == "ThirdPersonCamera" then cam.camc = o end
        end
        cam.camc_pawn, cam.ignore = cam.pawn, { pawn }
        if not cam.camc then return end
    end
    M.KSL = M.KSL or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    CAM_END = CAM_END or FName("SpringEndpoint")
    local camc = cam.camc
    local ok, err = pcall(function()
        local al, en = arm:K2_GetComponentLocation(), arm:GetSocketLocation(CAM_END)
        local dx, dy, dz = en.X - al.X, en.Y - al.Y, en.Z - al.Z
        local full = math.sqrt(dx * dx + dy * dy + dz * dz)
        -- (an arm that long: left to STORROR this frame, the guard kept on - just after a warp its lag has the camera
        -- still back where he was, 60 m off, and taken for an error that turned the guard off for good, the camera then
        -- through the walls: "cameras outside of map when returning from thi", 2026-11-08)
        if full > M.CAM_SANE then
            if cam.pulled then camc:K2_SetRelativeLocation({ X = 0.0, Y = 0.0, Z = 0.0 }, false, {}, true); cam.pulled = false end
            return
        end
        local want = full
        if full > 1.0 then
            local hit = cam.hit or {}
            cam.hit = hit
            local blocked = M.KSL:SphereTraceSingle(lib.world(), al, en, M.CAM_BALL, 1, false, cam.ignore, 0, hit, true, CAM_C0, CAM_C0, 0)
            if blocked and hit.bStartPenetrating then
                -- (begun inside something - the athlete is thin, and against a wall, on a ledge or climbing his middle is
                -- within the ball of it: 39% of frames in Tick Tock Clock. The plain line tried then met that same
                -- ground or ledge a hand's width off and took the camera in to 20 cm - "camera keeps zooming in really
                -- close for no fuckin reason", "camera keeps zooming in", 2026-11-08. So: the ball's start pushed out
                -- of it, its own way out (the hit's Normal and PenetrationDepth), and swept again; still inside, this
                -- frame is left to STORROR's arm, which stops at walls itself)
                local nr, dp = hit.Normal, hit.PenetrationDepth or 0.0
                local s2 = cam.s2 or {}
                cam.s2 = s2
                s2.X, s2.Y, s2.Z = al.X + nr.X * (dp + 2.0), al.Y + nr.Y * (dp + 2.0), al.Z + nr.Z * (dp + 2.0)
                blocked = M.KSL:SphereTraceSingle(lib.world(), s2, en, M.CAM_BALL, 1, false, cam.ignore, 0, hit, true, CAM_C0, CAM_C0, 0)
                if blocked and hit.bStartPenetrating then blocked = false end
            end
            if blocked then
                local L = hit.Location
                local hd = math.sqrt((L.X - al.X) ^ 2 + (L.Y - al.Y) ^ 2 + (L.Z - al.Z) ^ 2)
                if hd > (M.CAM_NEAR or 25.0) then want = math.max(M.CAM_MIN or 30.0, hd - M.CAM_PAD) end
            end
        end
        if want < full - 1.0 then
            local k = want / full
            local p = cam.p or {}
            cam.p = p
            p.X, p.Y, p.Z = al.X + dx * k, al.Y + dy * k, al.Z + dz * k
            camc:K2_SetWorldLocation(p, false, {}, true)
            cam.pulled = true
        elseif cam.pulled then
            camc:K2_SetRelativeLocation({ X = 0.0, Y = 0.0, Z = 0.0 }, false, {}, true)
            cam.pulled = false
        end
    end)
    if not ok then
        M.CAM_GUARD = false
        pcall(function() camc:K2_SetRelativeLocation({ X = 0.0, Y = 0.0, Z = 0.0 }, false, {}, true) end)
        lib.log("camera guard: off (%s)", tostring(err))
    end
end

function M.tick(pawn)
    pcall(vault_carry, pawn)
    pcall(camera_arm, pawn)
    pcall(M.camera_guard, pawn)
    no_motion_blur()
    local bc = bail_component(pawn)
    if bc then
        pcall(function()
            local w = bc.BailModeWidget
            if w and w:IsValid() then
                -- the game brings its counter back at every bail; it is put away again before it is drawn
                if M.widget ~= w:GetAddress() then
                    M.widget = w:GetAddress()
                    w:SetRenderScale({ X = 0.0, Y = 0.0 })
                    lib.log("STORROR's injury counter is hidden")
                end
                if w:GetVisibility() ~= 1 then w:SetVisibility(1) end
            end
        end)
    end
    hide_widgets(pawn)
    quiet_marker(pawn)
end

return M
