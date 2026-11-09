-- SM64Map: knocked flat (2026-10-14, the user: "if bowser jumps on you it should ragdol the player"; "you dont have to
-- have him automatically stand up").
--
-- STORROR's own ragdoll and get-up: its parkour component's StartRagdoll (its fall state, its flail; the athlete
-- stays down) and TryGetupFromRagdoll (its own get-up animations, face up or down as he lies). The mod knocks him
-- flat with the first, shoves him away from what hit him, and on A (pressed afresh, MIN_DOWN after he went down)
-- calls the second, as STORROR's own button does. ("he should pick himself off the ground like normal after a
-- ragdoll", 2026-10-14: the physics component's EnableRagdollPhysics, used before, left STORROR not knowing he was
-- down, and he could not get up.) Thrown off the stage, he is let fall on (the capsule put level with his body,
-- moved without a physics teleport: a K2_TeleportTo drags the ragdoll along with it).
local lib = require("lib")
local M = {}

local MIN_DOWN = 1.0                -- seconds down before he can get up (and count as up again)
M.SELF_UP_MIN = 0.25                -- (a ragdoll this long or longer is never ended by itself: M.tick)
-- (the active ragdoll - muscle, poses, injuries and their figure, the limbs kept apart, never up on his own - is its own
-- mod now, STORROR Euphoria, in its own folder: "this should be a seperate mod", 2026-10-29. Here it stays off; this
-- module keeps the mashup's own: the knock-down's throw, the holds, the water and the rest. The code below stays for
-- now, switched off.)
M.EUPHORIA = false
-- (the separate mod puts him back down if he gets up without the player's button; a get-up of ours on purpose - a
-- warp, the lava's leap, a revive: forget_knock - is written into its folder for it to see)
local EUPH_ALLOW = lib.MOD_DIR .. "../STORROREuphoria/allow_up.txt"
-- (any of these down while he lies there counts as the player getting him up: Space and A alone missed the get-ups of
-- the player's own, and he was put back down on each, 2026-10-29)
local INTENT_KEYS = {}
for _, k in ipairs({ "SpaceBar", "Gamepad_FaceButton_Bottom", "Gamepad_FaceButton_Right", "Gamepad_FaceButton_Left",
                     "Gamepad_FaceButton_Top", "W", "A", "S", "D", "E", "F", "Q", "R", "C", "LeftShift", "LeftControl",
                     "LeftMouseButton", "RightMouseButton", "Enter", "Gamepad_LeftStick_Up", "Gamepad_LeftStick_Down",
                     "Gamepad_LeftStick_Left", "Gamepad_LeftStick_Right", "Gamepad_RightTrigger", "Gamepad_LeftTrigger",
                     "Gamepad_RightShoulder", "Gamepad_LeftShoulder" }) do
    INTENT_KEYS[#INTENT_KEYS + 1] = { name = k, key = { KeyName = FName(k) } }
end
local UP_KEYS = { "Gamepad_FaceButton_Bottom", "SpaceBar" }     -- A, or Space
M.active = false
local st = nil

local function log(fmt, ...) lib.log(fmt, ...) end

local function comp(pawn, name)
    local found = nil
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetFName():ToString() == name then found = o; break end
        end
    end)
    return found
end

-- Knocked flat: (dx, dy) the way from what hit him to him; push, cm/s off the ground that way (a third of it up).
-- (his shirt and trousers back in their shape on him: flung about with the lying body, and the capsule put back under
-- it, they stayed bunched up after he got up - "the cloths thing again", 2026-10-17)
local function cloth_back(pawn)
    local G = package.loaded["game"]
    if G and G.reset_cloth then pcall(G.reset_cloth, pawn) end
end

-- No getting up in the air ("when the player gets ragdolled, the players able to stand up instantly even in the air",
-- 2026-10-28): while he is down - this module's ragdoll, a knock-down's (game.lua G.knock_down), STORROR's own - his
-- parkour and locomotion inputs are off (STORROR's own get-up on A is one of them) till his body has come to rest:
-- his hips slower than SETTLE_V for SETTLE_T together - on the ground, on a platform, afloat; never at the top of a
-- throw, where gravity takes that much off in the time. This module's A and game.lua's timed get-up wait for it too
-- (M.settled).
-- (still as STORROR has it before its A gets him up - "usually it waits for the player to completely stop moving in
-- ragdol mode then allowing the player to press a which triggers the getup animation", 2026-10-28: on land under 80 for
-- 0.35 s; afloat, where the water rocks him, under SETTLE_V_WATER)
M.SETTLE_V, M.SETTLE_T, M.SETTLE_V_WATER = 80.0, 0.35, 150.0
local AIR_LOCK = "SM64RagdollAir"
local air = { on = false, rest = 0.0 }
-- (an input handler of the mod's on top of all the others, blocking what is under it - STORROR's own A included, which
-- none of its own switches stopped: pressed while he was flying or not yet still, its get-up began and was undone, a
-- twitch - "also still twitches when pressing a", 2026-10-28. Its own hidden actor, made when first wanted.)
local function blocker(on)
    local pc = lib.controller()
    if not pc then return end
    local a = air.blocker
    if on then
        if not (a and a:IsValid()) then
            local w = lib.world()
            if not w then return end
            a = lib.spawn_actor(w, { X = 0.0, Y = 0.0, Z = -100000.0 }, 0.0)
            if not a then return end
            pcall(function() a.bBlockInput = true; a.InputPriority = 1000 end)
            pcall(function() a:SetActorHiddenInGame(true) end)
            -- (kept from lib's sweeps; forgotten untouched when the map goes - M.tick)
            pcall(function() air.blocker_addr = a:GetAddress(); lib.keep[air.blocker_addr] = "blocker" end)
            air.blocker = a
        end
        pcall(function() a:EnableInput(pc) end)
    elseif a and a:IsValid() then
        pcall(function() a:DisableInput(pc) end)
    end
end
local function inputs(pawn, on)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            local cname = o:GetClass():GetFName():ToString()
            if cname == "ParkourComponent" then
                o:EnableAllParkourInputs(FName(AIR_LOCK), on)
                -- (and the component's own input as a whole - HITSActorComponentWithInput: STORROR's get-up out of its
                -- ragdoll on A is the parkour component's own, and came through the rest off - "how is the player
                -- standing up anyways the only way you should be able to stand up after being ragdolled is through a
                -- picking yourself up animation", 2026-10-28)
                pcall(function() o:EnableComponentInput(FName(AIR_LOCK), on) end)
            elseif cname == "LocomotionComponent" then
                o:EnableLocomotionInputCallback(FName(AIR_LOCK), on)
                o:EnableAdvancedLocomotionInput(FName(AIR_LOCK), on)
                pcall(function() o:EnableComponentInput(FName(AIR_LOCK), on) end)
            end
        end
    end)
    -- (and his own input: STORROR's get-up comes through it too - thrown high by a Heave-Ho, he was got up out of the
    -- ragdoll in the air with the others off, and flew on up 40 m: "still able to stand in mid air", 2026-10-28. Given
    -- back only where nothing else has it off: out of power, a star's or a talk's cutscene keep it so themselves.)
    blocker(not on)
    local pc = lib.controller()
    if not pc then return end
    if on then
        local G = package.loaded["game"]
        if G and (G.down_for_good or G.star_cut or G.cutscene or G.dialog_cam) then return end
        -- (nor while the race holds him on its line, "Go!" to GO: race.lua's race_lock gives it back itself)
        local RC = package.loaded["race"]
        if RC and RC.race and RC.race.locked then return end
        pcall(function() pawn:EnableInput(pc) end)
    else
        pcall(function() pawn:DisableInput(pc) end)
    end
end
local function hold_air(pawn, on, why)
    local addr = nil
    if pawn then pcall(function() addr = pawn:GetAddress() end) end
    if on == air.on and (not on or air.addr == addr) then return end
    local was = air.on
    if air.on and air.pawn and air.pawn:IsValid() then inputs(air.pawn, true) end
    air.on, air.pawn, air.addr = false, nil, nil
    if on and pawn then
        inputs(pawn, false)
        air.on, air.pawn, air.addr = true, pawn, addr
        if not was then
            -- (and what put him down: its montage, and whether it was the mod's knock-down)
            local mt = "-"
            pcall(function()
                local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
                if m and m:IsValid() then mt = m:GetFName():ToString() end
            end)
            local G = package.loaded["game"]
            log("ragdoll: down - no getting up till he comes to rest (%s, %s)", G and G.getup_at and "knocked down" or "his own", mt)
            -- (his body's gravity on: STORROR's pole turns it off and a bail off the pole kept it so - he went limp
            -- over Bowser in the Fire Sea's lava and hung there, "stuck in air?", 2026-11-07)
            pcall(function()
                if not pawn.Mesh:IsGravityEnabled() then
                    pawn.Mesh:SetEnableGravity(true)
                    log("ragdoll: his body's gravity was off (STORROR's pole) - on again")
                end
            end)
        end
    elseif was then
        log("ragdoll: hold off - %s", why or "free to get up")
    end
end
-- (at rest, or not down at all: a get-up asked for while he is not found limp goes ahead as before)
-- (and lying on something: ground within GROUND_REACH under his hips, or afloat - or two seconds quite still, wherever
-- he lies; not free at the slow top of a throw - "still able to stand up while rag dolled in air", 2026-10-28)
M.GROUND_REACH = 70.0
function M.settled()
    if not air.down then return true end
    -- (not while he struggles on the ground - his hips may be still, the rest of him is not: M.STRUGGLE)
    if M.struggling and M.struggling() then return false end
    if M.knocked_out and M.knocked_out() then return false end      -- (knocked out: M.INJURY.ko)
    if air.rest < M.SETTLE_T then return false end
    return air.ground_ok or air.rest >= 2.0
end
local KSL = nil
local NO_COLOR = { R = 0, G = 0, B = 0, A = 0 }
local function ground_under(pawn)
    KSL = KSL or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local ok, b = pcall(function()
        local p = pawn.Mesh:GetSocketLocation(FName("pelvis"))
        local hit = {}
        return KSL:LineTraceSingle(lib.world(), { X = p.X, Y = p.Y, Z = p.Z + 5.0 }, { X = p.X, Y = p.Y, Z = p.Z - M.GROUND_REACH },
            0, true, { pawn }, 0, hit, true, NO_COLOR, NO_COLOR, 0.0)
    end)
    return ok and b and true or false
end
-- (anything solid on the line from a to b, him left out)
local function ray(pawn, a, b)
    KSL = KSL or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local ok, r = pcall(function()
        local hit = {}
        return KSL:LineTraceSingle(lib.world(), a, b, 0, true, { pawn }, 0, hit, true, NO_COLOR, NO_COLOR, 0.0)
    end)
    return ok and r and true or false
end
-- The speed to put back into a fresh ragdoll: his flight's, unless it would drive him into something - STORROR ends its
-- ragdoll as he lands or hits a wall, and the speed from before the hit, given back to every part of him, pushed him
-- into it and the physics threw him out: "just got launched up into a wall", 2026-10-28. Ground under his hips, or
-- anything in the way he was going within the next 0.06 s and 20 cm: none. At most CARRY_MAX.
M.CARRY_MAX = 2500.0
local function safe_carry(pawn, lv)
    if not lv then return nil end
    local sp = math.sqrt(lv.X * lv.X + lv.Y * lv.Y + lv.Z * lv.Z)
    if sp < 1.0 or sp ~= sp then return nil end
    if ground_under(pawn) then return nil end
    local p = nil
    pcall(function() p = pawn.Mesh:GetSocketLocation(FName("pelvis")) end)
    if not p then return nil end
    local reach = sp * 0.06 + 20.0
    if ray(pawn, { X = p.X, Y = p.Y, Z = p.Z }, { X = p.X + lv.X / sp * reach, Y = p.Y + lv.Y / sp * reach, Z = p.Z + lv.Z / sp * reach }) then
        return nil
    end
    local k = math.min(1.0, M.CARRY_MAX / sp)
    return { X = lv.X * k, Y = lv.Y * k, Z = lv.Z * k }
end

-- (STORROR's get-up out of its ragdoll while he is still flying from a knock-down - on its A, or of its own accord, which
-- no switching off of his input stopped: straight back into the ragdoll in the same frame, flying on as he was, so he is
-- never seen standing - he was, a moment, and twitched: "can still stand in air also the player twitches when pressing
-- a", 2026-10-28. Hooked once; only as STORROR's own functions are called through the engine - a call it makes inside
-- its own code goes by unseen, and M.tick's check after it still catches that.)
function M.on_getup(pk)
    if not air.knock_t or M.settled() then return end
    local lv = air.last_v
    if not lv or math.sqrt(lv.X * lv.X + lv.Y * lv.Y + lv.Z * lv.Z) < 300.0 then return end
    if (air.re_n or 0) >= 12 then return end
    if pcall(function() pk:StartRagdoll(1.0, false) end) then
        air.re_n = (air.re_n or 0) + 1
        local lw = air.last_w
        local pawn = lib.pawn()
        local cv = pawn and safe_carry(pawn, lv)
        air.carry = cv and { v = cv, w = lw and { X = lw.X, Y = lw.Y, Z = lw.Z }, n = 3 } or nil
        log("ragdoll: STORROR's get-up in the air undone at once (%d)", air.re_n)
    end
end
if not _G.SM64_GETUP_HOOK then
    -- (after it has run: a hook's one callback runs before the function, its second after)
    local okh, pre, post = pcall(RegisterHook, "/Script/HumanEmotion.ParkourComponent:TryGetupFromRagdoll", function() end, function(ctx)
        local R = package.loaded["ragdoll"]
        if R and R.on_getup then pcall(function() R.on_getup(ctx:get()) end) end
    end)
    if okh then _G.SM64_GETUP_HOOK = { pre, post } end
end
function M.air_held() return air.on, air.rest end          -- (tests)

function M.start(dx, dy, push)
    if st then return true end
    local world, pc, pawn = lib.world(), lib.controller(), lib.pawn()
    if not (world and pc and pawn) then return false end
    local phys = comp(pawn, "Physics Control")
    local pk = comp(pawn, "Parkour!")
    if not (phys and pk) then return false end
    local BURN = package.loaded["burn"]
    if BURN and BURN.active then pcall(BURN.stop, true) end
    local ok, e = pcall(function() pk:StartRagdoll(1.0, false) end)
    if not ok then log("ragdoll: not on (%s)", tostring(e)); return false end
    -- (his controls stay STORROR's: getting up is STORROR's own, on A, as after any fall of its own; the mod's get-up
    -- was taken out, "whatever script is in there that makes the charater stand up like that needs removed",
    -- 2026-10-14)
    local d = math.sqrt((dx or 0) ^ 2 + (dy or 0) ^ 2)
    push = push or 500.0
    local v = { X = 0.0, Y = 0.0, Z = push * 0.35 }
    if d > 1.0 then v.X, v.Y = dx / d * push, dy / d * push end
    st = { world = world:GetAddress(), pawn = pawn, phys = phys, pk = pk, t = 0.0, push = v, pushed = false, frame = 0,
           up_for = 0.0, held = true }
    M.active = true
    log("ragdoll: knocked flat")
    return true
end

-- Up again: the capsule under his body, then STORROR's blend back to standing. `quiet`: a change of scene.
function M.stop(quiet)
    local s = st
    st = nil
    M.active = false
    if not s then return end
    local same = false
    pcall(function() same = lib.world():GetAddress() == s.world end)
    if not same then return end
    local pc, pawn = lib.controller(), lib.pawn()
    if not pawn then return end
    if not quiet then
        pcall(function()
            local p = pawn.Mesh:GetSocketLocation(FName("pelvis"))
            local a = pawn:K2_GetActorLocation()
            -- (the capsule to his body: level with it if the body went down off an edge, so he falls on from there)
            local z = (p.Z < a.Z - 150.0) and (p.Z + 95.0) or a.Z
            if (p.X - a.X) ^ 2 + (p.Y - a.Y) ^ 2 > 30.0 * 30.0 or z ~= a.Z then
                -- (no physics teleport: that would carry the lying body along with the capsule)
                pawn:K2_SetActorLocation({ X = p.X, Y = p.Y, Z = z }, false, {}, false)
            end
        end)
    end
    pcall(function() s.phys:DisableRagdollPhysics(pawn) end)
    pcall(function() pawn.CharacterMovement:SetMovementMode(3, 0) end)        -- (STORROR's ragdoll had him at None)
    M.forget_knock()
    hold_air(pawn, false)
    cloth_back(pawn)
    log("ragdoll: let go")
end

-- Up at once, whoever's ragdoll he lies in - this module's, a knock-down's, STORROR's own: the capsule to his body, the
-- ragdoll's physics off, STORROR's flail or get-up stopped, falling. (The lava throws him off it on his feet: "it should
-- make the player stand back up instantly" - falling on lava while ragdolled, 2026-10-19.)
-- `stay`: his capsule left where it is - just set off (a bail swimming into a wall: his hips were in the wall, and
-- the capsule put there was thrown out of the level - "just randomly launched out of the map", 2026-10-23)
function M.up_now(stay)
    local pawn = lib.pawn()
    if not pawn then return false end
    local phys = (st and st.phys) or comp(pawn, "Physics Control")
    if not stay then
        pcall(function()
            local p = pawn.Mesh:GetSocketLocation(FName("pelvis"))
            pawn:K2_SetActorLocation({ X = p.X, Y = p.Y, Z = p.Z + 95.0 }, false, {}, false)
        end)
    end
    if phys then pcall(function() phys:DisableRagdollPhysics(pawn) end) end
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        local mt = ai:GetCurrentActiveMontage()
        if mt and mt:IsValid() then ai:Montage_Stop(0.0, mt) end
    end)
    pcall(function() pawn.CharacterMovement:SetMovementMode(3, 0) end)
    st, M.active = nil, false
    M.forget_knock()                -- (up on purpose - off the lava: not put back down as he flies off it)
    hold_air(pawn, false)
    air.rest = 0.0
    cloth_back(pawn)
    log("ragdoll: up at once")
    return true
end

-- Afloat ("if you ragdoll in water you drop to the bottom make it instead raise you to the top", 2026-10-18): lying
-- limp in the water - any of his ragdolls: this module's, a knock-down's, STORROR's own (STORROR plays its flail
-- montage, "...Ragdoll...", while he is limp, then "...Getup..."; its physics component's type stays as it was, and
-- the movement mode is the swim's again every frame - "charater still doesnt float in water when ragdolled"; this
-- module's own down a while after the flail, his hips still under his capsule) - his body rises: every part of it
-- held up against the world's gravity and pushed up the more
-- the deeper his hips are under where he floats (FLOAT_DEPTH under the top), slowed as it goes, and kept there. His
-- capsule (the camera's, the power meter's, where he gets up) goes after his hips, FLOAT_FOLLOW cm a frame at most,
-- never teleported (that would drag the body along); no getting up on the way.
M.FLOAT_DEPTH, M.FLOAT_K, M.FLOAT_DRAG, M.FLOAT_MAX, M.FLOAT_FOLLOW = 30.0, 6.0, 2.5, 1500.0, 8.0
M.FLOAT_CAP = 4000.0                -- (cm/s/s at most, each way)
M.FLOAT_MIN = 2.5                   -- (s afloat before the timed get-up)
local fl = { on = false }
-- limp: STORROR's flail montage on, or this module's down with his hips under his capsule; never in its get-up
local function limp(pawn, margin)
    local name = ""
    pcall(function()
        local mt = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
        if mt and mt:IsValid() then name = mt:GetFName():ToString() end
    end)
    if name:find("Getup") then return false end
    if name:find("Ragdoll") then return true end
    if not st then return false end
    local below = false
    pcall(function() below = pawn.Mesh:GetSocketLocation(FName("pelvis")).Z < pawn:K2_GetActorLocation().Z - (margin or 10.0) end)
    return below
end
local function afloat(pawn)
    local G = package.loaded["game"]
    if not (G and G.water_at and pawn) then return false end
    local world = lib.world()
    if not world then return false end
    local wa, pa = world:GetAddress(), pawn:GetAddress()
    if fl.world ~= wa or fl.pawn ~= pa then
        fl.world, fl.pawn, fl.g = wa, pa, nil
        pcall(function() fl.g = -world:K2_GetWorldSettings().WorldGravityZ end)
        if type(fl.g) ~= "number" or fl.g <= 0 then fl.g = 980.0 end
    end
    if not limp(pawn) then fl.since, fl.wet = nil, nil; return false end
    -- (not in the first quarter second: the body still flying from what threw it - a 20 m/s bail into the water was
    -- followed by a GPU crash, 2026-10-18 21:05, as the push began)
    fl.since = fl.since or os.clock()
    if os.clock() - fl.since < 0.25 then return false end
    local mesh = pawn.Mesh
    local O = lib.OFFSET
    local p = mesh:GetSocketLocation(FName("pelvis"))
    local top = G.water_at(p.X - O.X, p.Y - O.Y)
    if not top then return false end
    local depth = top - M.FLOAT_DEPTH - (p.Z - O.Z)
    -- (out of the water: his hips not under its top. Held up from a metre over it - gravity all but taken off him, and
    -- slowed - he fell slowly and stopped turning in the air by Wet-Dry World's water: "body not falling realistically
    -- kinda floaty", "body will be mid rotation and slowly come to a stop", 2026-10-28)
    if depth < -15.0 then return false end
    local v = mesh:GetPhysicsLinearVelocity(FName("pelvis"))
    if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z or p.Z ~= p.Z then return false end          -- (never a NaN pushed on)
    local up = math.max(-300.0, math.min(M.FLOAT_MAX, depth * M.FLOAT_K))
    local d = M.FLOAT_DRAG
    local function cap(a) return math.max(-M.FLOAT_CAP, math.min(M.FLOAT_CAP, a)) end
    mesh:AddForceToAllBodiesBelow({ X = cap(-v.X * d), Y = cap(-v.Y * d), Z = cap(fl.g + up - v.Z * d) }, FName("pelvis"), true, true)
    local a = pawn:K2_GetActorLocation()
    local dx, dy, dz = p.X - a.X, p.Y - a.Y, p.Z + 20.0 - a.Z
    local l = math.sqrt(dx * dx + dy * dy + dz * dz)
    if l > 1.0 then
        local k = math.min(1.0, M.FLOAT_FOLLOW / l)
        pawn:K2_SetActorLocation({ X = a.X + dx * k, Y = a.Y + dy * k, Z = a.Z + dz * k }, false, {}, false)
    end
    if depth > 60.0 and G.getup_at then G.getup_at, G.getup_tries = math.max(G.getup_at, os.clock() + 0.5), 0 end
    -- (and seen floating a while, FLOAT_MIN from his first moment in the water, before the timed get-up: at rest on the
    -- top in half a second, he was up again before he was seen to float - his own A gets him up sooner)
    fl.wet = fl.wet or os.clock()
    if G.getup_at then G.getup_at = math.max(G.getup_at, fl.wet + M.FLOAT_MIN) end
    if not fl.on then log("ragdoll: afloat, %.0f cm under where he floats", depth) end
    fl.depth = depth
    return true
end
function M.afloat() return fl.on, fl.depth end     -- (tests)

-- In an updraft (game.lua's vertical wind): limp over its open column - STORROR's flail as he fell into it - he took none
-- of the wind his capsule was given, and went on down through it and out of the level: falling into the tiny island's
-- pit killed him, "Yes, fix it", 2026-10-29. His body is blown up its column as the afloat one is held - every part of
-- it - to a little over the height of the ground round it (found once), his capsule after his hips (the death plane under
-- the wind is judged by it); there he is stood up in the air (M.up_now), and game.lua's wind holds him and he steers
-- himself out, as Mario 64 is steered in its wind (act_vertical_wind). (Set down out of it for him at first: "the
-- player should be able to control themselves in the updraft why is it auto placing the player?", 2026-10-29.)
M.UPDRAFT = { over = 180.0, rise = 900.0, k = 3.0, cap = 4500.0, follow = 30.0, stand = 60.0 }
local up = { on = false }
local function updraft(pawn)
    local G = package.loaded["game"]
    if not (G and G.vwind_under and G.floor_z and pawn) then return false end
    if not limp(pawn) then up.since, up.goal = nil, nil; return false end
    up.since = up.since or os.clock()
    if os.clock() - up.since < 0.15 then return false end
    local U = M.UPDRAFT
    local mesh = pawn.Mesh
    local O = lib.OFFSET
    local p = mesh:GetSocketLocation(FName("pelvis"))
    local x, y, z = p.X - O.X, p.Y - O.Y, p.Z - O.Z
    local wz = (G.vwind_near or G.vwind_under)(x, y, z)
    if not wz then return false end
    -- (the ground's height once while he lies limp)
    if not up.goal then
        local best = G.vwind_goal and G.vwind_goal(x, y, z, wz)
        if not best then return false end
        up.goal = best
        log("ragdoll: in an updraft - his body blown up to %.0f cm over the ground round it (%.0f)", U.over, best[3])
    end
    local goal = up.goal
    -- (up there: on his feet in the air, the wind his capsule's again, and the stick his)
    if z > goal[3] + U.over - U.stand then
        log("ragdoll: up its column - stood up in the air to steer")
        up.since, up.goal = nil, nil
        G.vgoal = { goal = goal, t = os.clock(), down = true }         -- (game.lua's lift holds him there from here)
        pcall(M.up_now)
        return false
    end
    local g = fl.g or 980.0
    local v = mesh:GetPhysicsLinearVelocity(FName("pelvis"))
    if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z or p.Z ~= p.Z then return false end          -- (never a NaN pushed on)
    local function cap(a) return math.max(-U.cap, math.min(U.cap, a)) end
    local vz = math.max(-200.0, math.min(U.rise, (goal[3] + U.over - z) * 2.0))
    -- (straight up its column, nothing across)
    mesh:AddForceToAllBodiesBelow({ X = cap(-v.X * 1.5), Y = cap(-v.Y * 1.5), Z = g + cap((vz - v.Z) * U.k) }, FName("pelvis"), true, true)
    local a = pawn:K2_GetActorLocation()
    local dx, dy, dz = p.X - a.X, p.Y - a.Y, p.Z + 20.0 - a.Z
    local l = math.sqrt(dx * dx + dy * dy + dz * dz)
    if l > 1.0 then
        local k = math.min(1.0, U.follow / l)
        pawn:K2_SetActorLocation({ X = a.X + dx * k, Y = a.Y + dy * k, Z = a.Z + dz * k }, false, {}, false)
    end
    if G.getup_at then G.getup_at = math.max(G.getup_at, os.clock() + 0.5) end      -- (no getting up on the way)
    return true
end
function M.updraft() return up.on, up.goal end     -- (tests)
function M.limp() local p = lib.pawn(); return p ~= nil and limp(p) end     -- (shock.lua: not shocked while limp)

-- (a get-up of the game's own, wherever he is - after a warp, revived: no knock-down of his going on any more, so no
-- putting him back down after it - he was, arriving after a death, 2026-10-28)
function M.forget_knock()
    air.knock_t, air.re_n, air.carry, air.up_at, air.allowed = nil, 0, nil, nil, os.clock()
    pcall(function() local f = io.open(EUPH_ALLOW, "w"); if f then f:write(tostring(os.clock())); f:close() end end)
end

-- The world went: forget it all without touching any of it (but his inputs, if still there).
function M.forget()
    st = nil; M.active = false
    if air.on and air.pawn and air.pawn:IsValid() then inputs(air.pawn, true) end
    air.on, air.pawn, air.addr, air.rest, air.down, air.knock_t, air.re_n = false, nil, nil, 0.0, false, nil, 0
    air.last_v, air.last_w, air.carry = nil, nil, nil
    if air.blocker and air.blocker:IsValid() then pcall(function() air.blocker:DisableInput(lib.controller()) end) end
    air.blocker = nil
end

function M.state() return st end            -- (tests)

-- Muscle in the ragdoll (a powered ragdoll, as Euphoria's: "how hard would it be to add euphoria ragdolling", then
-- "Yes, build it", 2026-10-29): Unreal's PhysicalAnimationComponent on the athlete, each joint held to the animation's
-- angle from its parent (local: nothing pinned in the world - gravity and the hit still take him down) - STORROR plays
-- its flail while he is down, so he goes down folding and flailing, not as a sack. Full strength as he goes down, held
-- HOLD seconds, then faded to nothing over FADE: with it on he never came to rest, and the rest check and STORROR's own
-- ragdoll set each other off again and again. Once a ragdoll: not again till he has been up. (Tried by hand first: head
-- 27-38 cm over the hips down on his knees, against 57 under them flat, limp.)
-- (k 1200: at 2000 he held STORROR's flail as a stiff pose as he went down, "a karate kick pose", 2026-10-29)
M.MUSCLE = { k = 900.0, hold = 0.4, fade = 1.0, every = 0.05 }    -- (900: at 1200 limbs were still driven through each other, 2026-10-29)
local mus = { on = false, ready = true, t = 0.0, k = 0.0, sent = -1.0, last = -1.0 }
local INJ = { pushed = {} }    -- (his injuries, section by section: filled below, ahead of muscle_tick - M.INJURY;
                               -- pushed: the bodies the limb separation moved, and when - not blows)
local function muscle_data(k)
    return { bIsLocalSimulation = true, OrientationStrength = k, AngularVelocityStrength = k * 0.1, PositionStrength = 0.0,
             VelocityStrength = 0.0, MaxLinearForce = 0.0, MaxAngularForce = 0.0 }
end
-- The muscle (Unreal's physical animation, each joint held toward STORROR's flail): a low tone over all of him, the
-- head and neck held harder (M.TONE.head) so his head is carried, not flopping; never the pelvis itself: with no parent
-- body of its own it is driven to the animation's pose in the world - upright, facing where he stood, turning with the
-- flail - and that torque righted him and spun him round ("why does he spin when ragdolling like cinderella",
-- 2026-10-29). What his limbs do comes from the poses below.
local function muscle_set(k, head)
    local c = mus.comp
    if not (c and c:IsValid()) then return end
    c:ApplyPhysicalAnimationSettingsBelow(FName("pelvis"), muscle_data(k), false)
    if head and head ~= k then c:ApplyPhysicalAnimationSettingsBelow(FName("neck_01"), muscle_data(head), true) end
    if not mus.pelvis_zeroed then
        mus.pelvis_zeroed = true
        pcall(function() c:ApplyPhysicalAnimationSettings(FName("pelvis"), muscle_data(0.0)) end)
    end
    mus.k = k
end
local function muscle_comp(pawn)
    local addr = pawn:GetAddress()
    if mus.comp and mus.comp:IsValid() and mus.addr == addr then return mus.comp end
    mus.comp, mus.pelvis_zeroed = nil, false
    -- (one made by this module before a reload: used again, not a second one)
    local g = _G.SM64_MUSCLE
    if g and g.addr == addr then
        local okv, valid = pcall(function() return g.comp:IsValid() end)
        if okv and valid then mus.comp, mus.addr = g.comp, addr; return g.comp end
        _G.SM64_MUSCLE = nil
    end
    local cls = StaticFindObject("/Script/Engine.PhysicalAnimationComponent")
    if not (cls and cls:IsValid()) then return nil end
    local c = pawn:AddComponentByClass(cls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 },
        Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
    if not (c and c:IsValid()) then return nil end
    c:SetSkeletalMeshComponent(pawn.Mesh)
    mus.comp, mus.addr = c, addr
    _G.SM64_MUSCLE = { comp = c, addr = addr }
    return c
end

-- What he does with himself, GTA IV's way ("can you use gta 4's euphoria? ... but not actually from the game", "Yes,
-- add them", then "the euphoria needs alot and I mean alot of work", 2026-10-29), made here from Unreal's Physics Control:
-- one control at each shoulder, elbow, hip and knee (on STORROR's ragdoll body, m_med_nrw_ragdoll_stable), aimed every
-- frame as the moment asks, their strength eased from one moment's to the next (POSE.ramp) so nothing snaps:
--   falling (nothing under his hips, a third of a second in): arms out to the sides and a little up, half bent, legs
--     down and a little apart - a body in the air, not a sack and not a windmill;
--   the ground or a wall coming within BEHAVE.brace_t along the way he flies, fast: arms thrown out at it, bent down,
--     the two apart (brace), knees drawn up to meet it;
--   down on the ground: a struggle - hands to his head for a moment after an enemy's hit (STRUGGLE.cover), otherwise
--     his arms go down to the ground as if to push up, his legs pulled in and working gently against each other
--     (STRUGGLE.pedal) - STRUGGLE.knocked seconds after a hit, by how fast he came down after a fall of his own;
--   then rest: held as he lies, softly, till he gets up - no going limp.
-- The targets: each limb's direction wanted, in his own body's frame (up his spine, across his collarbones, out of his
-- chest) or the world's; the turn from where the bone points now to that, put on the bone and made relative to its
-- parent, is the control's target.
M.BEHAVE = { air_after = 0.33, brace_t = 0.5, brace_v = 450.0, brace_down = 0.6, brace_spread = 0.45, max_air = 6.0,
             flail = "RagdollReactionFlail", flail_from = 0.05 }
-- (the tone toward STORROR's flail lowered in the air and on the ground, the poses stronger: the limbs barely moved -
-- "theres no love or attention like no falling flailing or fear in movements or pain", 2026-10-29)
M.TONE = { fall = 90.0, brace = 250.0, roll = 300.0, struggle = 260.0, rest = 200.0, head = 1500.0 }
M.POSE = { ramp = 0.3, ramp_brace = 0.06, ramp_struggle = 0.4, damp = 0.5,
           hz = { fall = 5.0, fall_legs = 4.0, brace = 12.0, struggle = 3.5, rest = 1.6, flinch = 9.0, spasm = 7.0 } }
M.STRUGGLE = { knocked = 2.5, max = 3.0, from_v = 350.0, per_v = 500.0, least = 1.2, pedal_hz = 0.9, pedal = 0.45, cover = 0.4 }
-- (life: the flinch at a hard stop, the scream of a long fall, and on the ground the rocking, the spasms, the groans, the
-- shifts of a body lying there - each with its own spacing, in seconds)
M.LIFE = { flinch_from = 750.0, flinch_t = 0.28, scream_air = 0.7, scream_vz = -700.0, rock_deg = 70.0, rock_every = { 0.9, 1.6 },
           spasm_every = { 0.7, 1.6 }, spasm_t = 0.22, groan_every = { 1.4, 2.6 }, rest_shift = { 2.5, 5.0 }, rest_groan = { 3.5, 6.5 } }
-- (landing with speed across the ground: tucked - arms in over the chest, knees up - and let roll on with it, the torso's
-- spin damper eased off, till he is nearly stopped (end_v) or ROLL.max is up; then the struggle. He stopped dead where he
-- landed before; GTA IV's bodies roll on, 2026-10-29)
M.ROLL = { min_v = 450.0, end_v = 150.0, max = 1.2, hz = 2.5, spin_damp = 0.3, spin = 0.2, spin_max = 150.0 }
local function qmul(a, b)
    return { x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y, y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
             z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w, w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z }
end
local function vnorm(v)
    local n = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if n < 1e-6 then return { x = 0.0, y = 0.0, z = 0.0 } end
    return { x = v.x / n, y = v.y / n, z = v.z / n }
end
local function vcross(a, b) return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x } end
-- (the turn taking direction u onto v the short way, as a quaternion)
local function qarc(u, v)
    local d = u.x * v.x + u.y * v.y + u.z * v.z
    if d < -0.9999 then
        local ax = vnorm({ x = 0.0, y = -u.z, z = u.y })
        if ax.x == 0.0 and ax.y == 0.0 and ax.z == 0.0 then ax = { x = 0.0, y = 0.0, z = 1.0 } end
        return { x = ax.x, y = ax.y, z = ax.z, w = 0.0 }
    end
    local c = vcross(u, v)
    local q = { x = c.x, y = c.y, z = c.z, w = 1.0 + d }
    local n = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    return { x = q.x / n, y = q.y / n, z = q.z / n, w = q.w / n }
end
-- (Unreal's FQuat::Rotator)
local function q2rot(q)
    local R2D = 180.0 / math.pi
    local sing = q.z * q.x - q.w * q.y
    local yy, yx = 2.0 * (q.w * q.z + q.x * q.y), 1.0 - 2.0 * (q.y * q.y + q.z * q.z)
    if sing < -0.4999995 then
        local yaw = math.atan(yy, yx) * R2D
        return { Pitch = -90.0, Yaw = yaw, Roll = -yaw - 2.0 * math.atan(q.x, q.w) * R2D }
    elseif sing > 0.4999995 then
        local yaw = math.atan(yy, yx) * R2D
        return { Pitch = 90.0, Yaw = yaw, Roll = yaw - 2.0 * math.atan(q.x, q.w) * R2D }
    end
    return { Pitch = math.asin(2.0 * sing) * R2D, Yaw = math.atan(yy, yx) * R2D,
             Roll = math.atan(-2.0 * (q.w * q.x + q.y * q.z), 1.0 - 2.0 * (q.x * q.x + q.y * q.y)) * R2D }
end
local function mix(...)
    local a = { ... }
    local v = { x = 0.0, y = 0.0, z = 0.0 }
    for i = 1, #a, 2 do v.x, v.y, v.z = v.x + a[i].x * a[i + 1], v.y + a[i].y * a[i + 1], v.z + a[i].z * a[i + 1] end
    return vnorm(v)
end
local DOWN = { x = 0.0, y = 0.0, z = -1.0 }

local function pose_end()
    local ps = mus.pose
    mus.pose = nil
    if ps and ps.pc and ps.pc:IsValid() then pcall(function() ps.pc:K2_DestroyComponent(ps.pc) end) end
end
-- the controls, made once a ragdoll (their strength starts at nothing: eased up by pose_tick)
local function pose_start(pawn)
    pose_end()
    local mesh = pawn.Mesh
    local have = {}
    pcall(function()
        local pa = nil
        pcall(function() pa = mesh.PhysicsAssetOverride end)
        if not (pa and pa:IsValid()) then pa = mesh.SkeletalMesh.PhysicsAsset end
        pa.SkeletalBodySetups:ForEach(function(i, e) have[e:get().BoneName:ToString()] = true end)
    end)
    local cls = StaticFindObject("/Script/PhysicsControl.PhysicsControlComponent")
    if not (cls and cls:IsValid()) then return false end
    local pc = pawn:AddComponentByClass(cls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 },
        Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
    if not (pc and pc:IsValid()) then return false end
    local data = { bEnabled = true, LinearStrength = 0.0, LinearDampingRatio = 1.0, LinearExtraDamping = 0.0, MaxForce = 0.0,
        AngularStrength = 0.0, AngularDampingRatio = 1.0, AngularExtraDamping = M.POSE.damp, MaxTorque = 0.0,
        LinearTargetVelocityMultiplier = 0.0, AngularTargetVelocityMultiplier = 0.0, CustomControlPoint = { X = 0, Y = 0, Z = 0 },
        bUseCustomControlPoint = false, bUseSkeletalAnimation = false, bDisableCollision = false, bOnlyControlChildObject = true }
    local target = { TargetPosition = { X = 0, Y = 0, Z = 0 }, TargetVelocity = { X = 0, Y = 0, Z = 0 },
        TargetOrientation = { Pitch = 0, Yaw = 0, Roll = 0 }, TargetAngularVelocity = { X = 0, Y = 0, Z = 0 }, bApplyControlPointToTarget = false }
    local ctl = {}
    for _, side in ipairs({ "l", "r" }) do
        for _, j in ipairs({ { "clavicle_", "upperarm_", "lowerarm_", "shoulder" }, { "upperarm_", "lowerarm_", "hand_", "elbow" },
                              { "pelvis", "thigh_", "calf_", "hip" }, { "thigh_", "calf_", "foot_", "knee" } }) do
            local parent = (j[1] == "pelvis") and "pelvis" or (j[1] .. side)
            local child, tip = j[2] .. side, j[3] .. side
            if have[parent] and have[child] then
                ctl[#ctl + 1] = { name = pc:CreateControl(mesh, FName(parent), mesh, FName(child), data, target, FName("Pose"),
                                  "pose_" .. j[4] .. "_" .. side), parent = parent, child = child, tip = tip, side = side, joint = j[4], hz = 0.0 }
            end
        end
    end
    if #ctl == 0 then pcall(function() pc:K2_DestroyComponent(pc) end); return false end
    mus.pose = { pc = pc, ctl = ctl }
    return true
end
-- each control's strength eased toward what its phase wants (arms and legs may differ)
local function pose_strength(dt, arms_hz, legs_hz, ramp)
    local ps = mus.pose
    if not (ps and ps.pc and ps.pc:IsValid()) then return end
    for _, c in ipairs(ps.ctl) do
        local want = (c.joint == "shoulder" or c.joint == "elbow") and arms_hz or legs_hz
        -- (as its section is: slow and heavy sprained, nothing broken or knocked out, held harder where it holds - INJ.ctl)
        local damp, r = M.POSE.damp, ramp or M.POSE.ramp
        if INJ.ctl then want, damp, r = INJ.ctl(c, want, damp, r) end
        if c.jerk and want > 0.0 then want, r = math.max(want, M.POSE.hz.spasm), 0.03 end     -- (a spasm: snapped)
        local k = math.min(1.0, dt / r)
        local hz = c.hz + (want - c.hz) * k
        if math.abs(hz - c.hz) > 0.01 or (want == 0.0 and c.hz > 0.0) or damp ~= c.dmp then
            c.hz, c.dmp = hz, damp
            pcall(function() ps.pc:SetControlAngularData(c.name, hz, 1.0, damp, 0.0, true, true, false) end)
        end
    end
end
-- the limbs aimed: `want(c, frame)` gives each control its direction (nil: left as it is)
local function pose_aim(pawn, want)
    local ps = mus.pose
    if not (ps and ps.pc and ps.pc:IsValid()) then return end
    local mesh = pawn.Mesh
    -- (each bone read once a frame: the reaches ask for the same ones again - 0.74 ms a frame down, 2026-10-29)
    local pc_, rc_ = {}, {}
    local function pos(n)
        local v = pc_[n]
        if v then return { x = v.x, y = v.y, z = v.z } end
        local p = mesh:GetSocketLocation(FName(n))
        v = { x = p.X, y = p.Y, z = p.Z }
        pc_[n] = v
        return { x = v.x, y = v.y, z = v.z }
    end
    local function rot(n)
        local q = rc_[n]
        if not q then local r = mesh:GetSocketQuaternion(FName(n)); q = { x = r.X, y = r.Y, z = r.Z, w = r.W }; rc_[n] = q end
        return q
    end
    local pel, chest = pos("pelvis"), pos("spine_05")
    local cl, cr = pos("clavicle_l"), pos("clavicle_r")
    local frame = { up = vnorm({ x = chest.x - pel.x, y = chest.y - pel.y, z = chest.z - pel.z }),
                    right = vnorm({ x = cr.x - cl.x, y = cr.y - cl.y, z = cr.z - cl.z }), head = pos("head"), pos = pos }
    frame.fwd = vcross(frame.right, frame.up)
    local worst = 0.0
    for _, c in ipairs(ps.ctl) do
        local d = want(c, frame)
        if d then
            local a0, a1 = pos(c.child), pos(c.tip)
            local cur = vnorm({ x = a1.x - a0.x, y = a1.y - a0.y, z = a1.z - a0.z })
            if cur.x ~= 0.0 or cur.y ~= 0.0 or cur.z ~= 0.0 then
                if c.joint == "shoulder" then
                    worst = math.max(worst, math.deg(math.acos(math.max(-1.0, math.min(1.0, cur.x * d.x + cur.y * d.y + cur.z * d.z)))))
                end
                local rp = rot(c.parent)
                local rel = qmul({ x = -rp.x, y = -rp.y, z = -rp.z, w = rp.w }, qmul(qarc(cur, d), rot(c.child)))
                ps.pc:SetControlTargetOrientation(c.name, q2rot(rel), 0.0, true, false, true, false)
            end
        end
    end
    return worst
end
-- the poses
-- (in the air: arms forward and up, elbows bent, hips flexed, knees bent, the limbs slowly waving out of step with each
-- other - arms straight out to the sides and legs straight read as a dropped mannequin, 2026-10-29)
-- Each fall its own (the user: "the movements should be randomized a bit so no fall is like another", 2026-10-29): drawn
-- when the ragdoll begins (fall_character), and read by every pose - the limbs' waving pace and size, one side a little
-- more than the other, arms higher or lower and wider or narrower in the air, legs apart or together, knees bent more or
-- less, how far apart and how far down the arms brace, the struggle's pace and size and length, how hard a hit turns him
-- and how much more it takes his upper body than his legs, the muscle's tone, the curl's depth, which hand gets to a hurt
-- place first and how much later the other, and whether a curl on his back rolls him onto a side, and which.
local NO_RND = { wave_hz = 1.0, wave = 1.0, side_l = 1.0, side_r = 1.0, arms_out = 0.0, arms_up = 0.0, legs_out = 0.0,
                 knees = 0.0, brace_spread = 0.45, brace_down = 0.6, pedal_hz = 1.0, pedal = 1.0, writhe = 1.0, spin = 1.0,
                 split = 1.0, tone = 1.0, curl = 0.0, hand_delay = 0.0, late = "l", side_roll = 0, style = "windmill",
                 mill_hz = 1.3, mill_lag = 3.14, flail_hz = 1.6, air_pedal_hz = 1.2, arm_mode = "head", rock = 1.0, spasm = 1.0 }
local function rr(a, b) return a + (b - a) * math.random() end
local function fall_character()
    local modes = { "head", "chest", "push" }
    return { wave_hz = rr(0.75, 1.3), wave = rr(0.75, 1.3), side_l = rr(0.8, 1.2), side_r = rr(0.8, 1.2),
             arms_out = rr(-0.15, 0.25), arms_up = rr(-0.25, 0.25), legs_out = rr(-0.12, 0.15), knees = rr(-0.2, 0.25),
             brace_spread = rr(0.3, 0.6), brace_down = rr(0.45, 0.8), pedal_hz = rr(0.75, 1.4), pedal = rr(0.7, 1.4),
             writhe = rr(0.8, 1.35), spin = rr(0.75, 1.3), split = rr(0.8, 1.3), tone = rr(0.85, 1.2), curl = rr(-0.15, 0.15),
             hand_delay = rr(0.0, 0.6), late = (math.random() < 0.5) and "l" or "r",
             side_roll = (math.random() < 0.65) and ((math.random() < 0.5) and -1 or 1) or 0,
             -- (in the air: arms turning in circles, or thrown about)
             style = (math.random() < 0.5) and "windmill" or "flail", mill_hz = rr(1.0, 1.7),
             mill_lag = (math.random() < 0.7) and rr(2.6, 3.7) or rr(-0.4, 0.4), flail_hz = rr(1.2, 2.1), air_pedal_hz = rr(0.9, 1.6),
             -- (on the ground: where the hands go when nothing in particular hurts; how much he rocks and twitches)
             arm_mode = modes[math.random(1, 3)], rock = rr(0.6, 1.3), spasm = rr(0.6, 1.4) }
end
-- In the air, GTA IV's way: the arms windmilling - big circles out at his sides, one half a turn behind the other (or
-- together) - or flailing, each thrown about on its own, three waves at once; the legs running in the air, half a stride
-- apart. All of it quicker and bigger the longer the fall (panic: from 0.6 s in, twice by 1.4 s). (Before: a slow wave of a
-- third of a turn a second, a fifth as strong - "no falling flailing or fear", 2026-10-29)
local function want_fall(t, air_t)
    local panic = 1.0 + math.min(1.0, math.max(0.0, ((air_t or 0.0) - 0.6) / 0.8))
    local R = mus.rnd or NO_RND
    local pace = 0.8 + 0.4 * panic
    return function(c, f)
        local s = (c.side == "l") and -1.0 or 1.0
        local amp = (c.side == "l") and R.side_l or R.side_r
        if c.joint == "shoulder" or c.joint == "elbow" then
            if R.style == "windmill" then
                local th = t * 2.0 * math.pi * R.mill_hz * pace + ((c.side == "l") and 0.0 or R.mill_lag)
                if c.joint == "elbow" then th = th + 0.6 end         -- (the forearm leading the circle)
                return mix(f.up, math.cos(th) * amp, f.fwd, math.sin(th) * amp, f.right, s * (((c.joint == "shoulder") and 0.55 or 0.45) + R.arms_out))
            end
            local a = t * 2.0 * math.pi * R.flail_hz * pace
            local ph = (c.side == "l") and 0.0 or 2.3
            local u = (math.sin(a + ph) + 0.5 * math.sin(a * 1.7 + ph * 2.0)) * amp
            local v = (math.sin(a * 1.3 + ph + 1.1) + 0.4 * math.sin(a * 2.3 + ph)) * amp
            if c.joint == "shoulder" then return mix(f.right, s * (0.6 + R.arms_out), f.up, 0.3 + R.arms_up + 0.55 * u, f.fwd, 0.35 + 0.55 * v) end
            return mix(f.up, 0.5 + 0.5 * v, f.fwd, 0.4 + 0.4 * u, f.right, s * 0.5)
        end
        local lw = t * 2.0 * math.pi * R.air_pedal_hz * pace + ((c.side == "l") and 0.0 or math.pi)
        if c.joint == "hip" then return mix(f.up, -0.8, f.fwd, 0.15 + 0.55 * math.sin(lw) * R.wave, f.right, s * (0.2 + R.legs_out)) end
        return mix(f.up, -0.75, f.fwd, -0.55 - R.knees + 0.45 * math.cos(lw) * R.wave)
    end
end
local function want_roll(c, f)
    local s = (c.side == "l") and -1.0 or 1.0
    if c.joint == "shoulder" then return mix(f.fwd, 0.8, f.up, 0.3, f.right, -s * 0.2)
    elseif c.joint == "elbow" then return mix(f.up, 0.8, f.fwd, 0.2, f.right, -s * 0.4)
    elseif c.joint == "hip" then return mix(f.fwd, 0.9, f.up, 0.3, f.right, s * 0.2)
    else return mix(f.up, -0.8, f.fwd, -0.5) end
end
local function want_brace(aim, right)
    return function(c, f)
        local s = (c.side == "l") and -1.0 or 1.0
        if c.joint == "shoulder" or c.joint == "elbow" then
            local sp = (mus.rnd or NO_RND).brace_spread
            return vnorm({ x = aim.x + right.x * s * sp, y = aim.y + right.y * s * sp, z = aim.z + right.z * s * sp })
        elseif c.joint == "hip" then return mix(f.up, -0.6, f.fwd, 0.7, f.right, s * 0.3)
        else return mix(f.up, -0.9, f.fwd, -0.2) end
    end
end
-- On the ground, in pain (the struggle): by how he lies - on his back, face down, on his side - and by each fall's arm_mode
-- when nothing in particular hurts: hands to his head, forearms over his chest, or arms down pushing at the ground (face
-- down, always that). The legs squirm, drawn up and let down out of step, uneven, bigger the more it hurts (mus.pain). Now
-- and then a spasm: one limb jerked for a moment - an arm flung out, a knee snatched up (mus.spasm, set in INJ.life). What
-- hurts in particular is held over all of this (INJ.want).
local function want_struggle(t, cover)
    local R = mus.rnd or NO_RND
    local sg = M.STRUGGLE
    local pain = mus.pain or 0.5
    local sp = mus.spasm
    return function(c, f)
        local s = (c.side == "l") and -1.0 or 1.0
        local arm = (c.joint == "shoulder" or c.joint == "elbow")
        c.jerk = false
        if sp and sp.side == c.side and sp.arm == arm and os.clock() < sp.until_t then
            c.jerk = true
            return sp.dir(c, f, s)
        end
        local a = t * sg.pedal_hz * R.pedal_hz * 2.0 * math.pi
        local ph = (c.side == "l") and 0.0 or math.pi
        local w = (math.sin(a + ph) + 0.35 * math.sin(a * 2.3 + ph * 1.7)) * sg.pedal * R.pedal * (0.7 + 0.6 * pain)
        local on_back, face_down = f.fwd.z > 0.4, f.fwd.z < -0.4
        if arm then
            local mode = cover and "head" or R.arm_mode
            if face_down and not cover then mode = "push" end
            if mode == "head" then
                if c.joint == "shoulder" then return mix(f.fwd, 0.75, f.up, 0.45 + w * 0.25, f.right, s * 0.35) end
                local e, h = f.pos(c.child), f.head
                return vnorm({ x = h.x - e.x, y = h.y - e.y, z = h.z - e.z })
            elseif mode == "chest" then
                if c.joint == "shoulder" then return mix(f.fwd, 0.7, f.up, -0.2 + w * 0.3, f.right, s * 0.3) end
                return mix(f.right, -s * 0.8, f.up, 0.35, f.fwd, 0.3)
            end
            local push = 0.5 + 0.5 * math.sin(a * 0.7 + ph * 0.3)
            if c.joint == "shoulder" then return mix(DOWN, 0.7, f.fwd, 0.5 * push, f.right, s * 0.5) end
            return mix(DOWN, 0.85, f.fwd, 0.35, f.right, s * 0.3)
        elseif c.joint == "hip" then
            if on_back then return mix(f.fwd, 0.8, f.up, 0.35 + w, f.right, s * 0.18) end
            return mix(f.fwd, 0.9, f.up, 0.2 + w, f.right, s * 0.25)
        end
        return mix(f.up, -0.9, f.fwd, (on_back and -0.6 or -0.35) - w * 0.8)
    end
end
-- The flinch: a hard stop and for a moment everything comes in - forearms up over his face, knees up (M.LIFE.flinch_t)
local function want_flinch(c, f)
    local s = (c.side == "l") and -1.0 or 1.0
    if c.joint == "shoulder" then return mix(f.fwd, 0.8, f.up, 0.2, f.right, s * 0.25)
    elseif c.joint == "elbow" then return mix(f.up, 0.9, f.right, -s * 0.5, f.fwd, 0.2)
    elseif c.joint == "hip" then return mix(f.fwd, 0.8, f.up, 0.2, f.right, s * 0.1) end
    return mix(f.up, -0.6, f.fwd, -0.8)
end
-- Lying there (rest): each limb as it last was, and every few seconds one of them moved somewhere else, slowly - along
-- his side, out on the ground, a hand to his belly or his brow; a leg straight, a knee up, a leg out (mus.rest_t, set in
-- INJ.life): a body lying still is not a statue.
local REST_ARM = {
    function(c, f, s) if c.joint == "shoulder" then return mix(f.up, -0.9, f.right, s * 0.35) end return mix(f.up, -0.9, f.right, s * 0.2, f.fwd, 0.1) end,
    function(c, f, s) if c.joint == "shoulder" then return mix(f.right, s * 0.9, f.up, 0.25) end return mix(f.right, s * 0.8, f.up, 0.4) end,
    function(c, f, s) if c.joint == "shoulder" then return mix(f.up, -0.5, f.fwd, 0.55, f.right, s * 0.25) end return mix(f.right, -s * 0.8, f.up, 0.35, f.fwd, 0.2) end,
    function(c, f, s)
        if c.joint == "shoulder" then return mix(f.up, 0.55, f.right, s * 0.6, f.fwd, 0.35) end
        local e, h = f.pos(c.child), f.head
        return vnorm({ x = h.x - e.x, y = h.y - e.y, z = h.z - e.z })
    end,
}
local REST_LEG = {
    function(c, f, s) if c.joint == "hip" then return mix(f.up, -1.0, f.right, s * 0.15) end return mix(f.up, -1.0, f.fwd, -0.05) end,
    function(c, f, s) if c.joint == "hip" then return mix(f.up, -0.5, f.fwd, 0.8, f.right, s * 0.1) end return mix(f.up, -0.9, f.fwd, -0.4) end,
    function(c, f, s) if c.joint == "hip" then return mix(f.up, -0.9, f.right, s * 0.35) end return mix(f.up, -0.9, f.fwd, -0.25) end,
}
local function want_rest(c, f)
    local arm = (c.joint == "shoulder" or c.joint == "elbow")
    local fn = mus.rest_t and mus.rest_t[c.side .. (arm and "arm" or "leg")]
    if fn then return fn(c, f, (c.side == "l") and -1.0 or 1.0) end
    return nil
end

-- The push and the speed he goes down with, given a moment on (Unreal's whole-body velocity change - given as STORROR's
-- ragdoll begins, they were lost and he dropped on the spot): an enemy's knock-down's push (game.lua G.knock_down keeps
-- it, G.knock_push) - his upper body a little more of it than his legs, so the hit turns him, his head leading the way it
-- sends him (HIT.upper, HIT.lower) - or, going down at a run, his own speed, and that way a forward tumble, his body set
-- turning about the line across his way; not into a wall ahead.
-- (and turned by it: his head sent the way of the push, HIT.spin degrees a second for each cm/s of it, HIT.spin_max at most -
-- with the push alone he flew bolt upright and sat down where he landed, 2026-10-29)
M.HIT = { upper = 1.3, lower = 0.75, spin = 0.35, spin_max = 240.0, twist = 160.0 }
M.TUMBLE = { at = 0.04, min_v = 350.0, spin = 0.25, spin_max = 200.0, wall = 90.0 }
local function throw_now(pawn)
    local mesh = pawn.Mesh
    local push = mus.push
    if push then
        local R = mus.rnd or NO_RND
        local lo = M.HIT.lower
        local hi = lo + (M.HIT.upper - lo) * R.split
        mesh:AddImpulseToAllBodiesBelow({ X = push.X * lo, Y = push.Y * lo, Z = push.Z * lo }, FName("pelvis"), true, true)
        mesh:AddImpulseToAllBodiesBelow({ X = push.X * (hi - lo), Y = push.Y * (hi - lo), Z = push.Z * (hi - lo) }, FName("spine_03"), true, true)
        local hsp = math.sqrt(push.X * push.X + push.Y * push.Y)
        local deg = 0.0
        if hsp > 1.0 then
            local dir = { x = push.X / hsp, y = push.Y / hsp, z = 0.0 }
            local axis = vcross({ x = 0.0, y = 0.0, z = 1.0 }, dir)
            deg = math.min(M.HIT.spin_max, hsp * M.HIT.spin) * R.spin
            pcall(function() mesh:AddAngularImpulseInDegrees({ X = axis.x * deg, Y = axis.y * deg, Z = axis.z * deg }, FName("pelvis"), true) end)
            pcall(function() mesh:AddAngularImpulseInDegrees({ X = axis.x * deg * 0.5, Y = axis.y * deg * 0.5, Z = axis.z * deg * 0.5 }, FName("spine_03"), true) end)
        end
        -- (and a little twist about the vertical, either way, so no two hits flip him in quite the same plane)
        local twist = (math.random() - 0.5) * M.HIT.twist
        pcall(function() mesh:AddAngularImpulseInDegrees({ X = 0.0, Y = 0.0, Z = twist }, FName("spine_03"), true) end)
        log("ragdoll: thrown by the hit (%.0f %.0f %.0f, turned %.0f deg/s, twist %.0f)", push.X, push.Y, push.Z, deg, twist)
        return
    end
    local cv = mus.carry
    if not cv then return end
    local sp = math.sqrt(cv.X * cv.X + cv.Y * cv.Y)
    local body = mesh:GetPhysicsLinearVelocity(FName("pelvis"))
    local bsp = math.sqrt(body.X * body.X + body.Y * body.Y)
    if bsp >= sp * 0.6 then return end                  -- (STORROR kept his speed itself: nothing to add)
    local p = mesh:GetSocketLocation(FName("pelvis"))
    local dir = { x = cv.X / sp, y = cv.Y / sp, z = 0.0 }
    local reach = M.TUMBLE.wall
    if ray(pawn, { X = p.X, Y = p.Y, Z = p.Z }, { X = p.X + dir.x * reach, Y = p.Y + dir.y * reach, Z = p.Z }) then
        log("ragdoll: (a wall ahead: no tumble)")
        return
    end
    mesh:AddImpulseToAllBodiesBelow({ X = cv.X - body.X, Y = cv.Y - body.Y, Z = 0.0 }, FName("pelvis"), true, true)
    local axis = vcross({ x = 0.0, y = 0.0, z = 1.0 }, dir)
    local deg = math.min(M.TUMBLE.spin_max, sp * M.TUMBLE.spin)
    pcall(function() mesh:AddAngularImpulseInDegrees({ X = axis.x * deg, Y = axis.y * deg, Z = axis.z * deg }, FName("pelvis"), true) end)
    log("ragdoll: tumbling with his speed (%.0f cm/s, %.0f deg/s)", sp, deg)
end

-- The torso's spin damped (Physics Control, a control on his hips and chest against the world with no strength, only
-- extra angular damping): with STORROR's dampers off and the pelvis free, his limbs' swinging spun the torso the other
-- way, as a skater's arms do, up to 540 degrees a second: "why does he spin when ragdolling like cinderella",
-- 2026-10-29. The limbs keep their freedom.
M.SPIN_DAMP = { damping = 1.5, bones = { "pelvis", "spine_03" } }     -- (1.5: at 8 he fell bolt upright, never tipping over, 2026-10-29)
local function spin_damp_end()
    local sd = mus.sd
    mus.sd = nil
    if sd and sd.pc and sd.pc:IsValid() then pcall(function() sd.pc:K2_DestroyComponent(sd.pc) end) end
end
local function spin_damp_start(pawn)
    spin_damp_end()
    local cls = StaticFindObject("/Script/PhysicsControl.PhysicsControlComponent")
    if not (cls and cls:IsValid()) then return false end
    local mesh = pawn.Mesh
    local pc = pawn:AddComponentByClass(cls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 },
        Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
    if not (pc and pc:IsValid()) then return false end
    local data = { bEnabled = true, LinearStrength = 0.0, LinearDampingRatio = 1.0, LinearExtraDamping = 0.0, MaxForce = 0.0,
        AngularStrength = 0.0, AngularDampingRatio = 1.0, AngularExtraDamping = M.SPIN_DAMP.damping, MaxTorque = 0.0,
        LinearTargetVelocityMultiplier = 0.0, AngularTargetVelocityMultiplier = 0.0, CustomControlPoint = { X = 0, Y = 0, Z = 0 },
        bUseCustomControlPoint = false, bUseSkeletalAnimation = false, bDisableCollision = false, bOnlyControlChildObject = true }
    local target = { TargetPosition = { X = 0, Y = 0, Z = 0 }, TargetVelocity = { X = 0, Y = 0, Z = 0 },
        TargetOrientation = { Pitch = 0, Yaw = 0, Roll = 0 }, TargetAngularVelocity = { X = 0, Y = 0, Z = 0 }, bApplyControlPointToTarget = false }
    local n, names = 0, {}
    for _, b in ipairs(M.SPIN_DAMP.bones) do
        local ok, nm = pcall(function() return pc:CreateControl(mesh, FName("None"), mesh, FName(b), data, target, FName("SpinDamp"), "spin_" .. b) end)
        if ok then n = n + 1; names[#names + 1] = nm end
    end
    if n == 0 then pcall(function() pc:K2_DestroyComponent(pc) end); return false end
    mus.sd = { pc = pc, names = names }
    return true
end
local function spin_damp_set(damping)
    local sd = mus.sd
    if not (sd and sd.pc and sd.pc:IsValid()) then return end
    for _, nm in ipairs(sd.names or {}) do pcall(function() sd.pc:SetControlAngularData(nm, 0.0, 1.0, damping, 0.0, true, true, false) end) end
end

-- STORROR's own dampers: its ragdoll body (m_med_nrw_ragdoll_stable) has a velocity drive on all 20 joints, strength 50 to
-- 300 - no pose held, every joint braked - and they braked the muscle and the poses: "I think storrors original ragdol
-- is messing with this ragdol" / "I do believe its interfering with the euphoria", 2026-10-29. Off while he falls and
-- struggles, back on as he rests (still in that ragdoll body: he settles as STORROR's does). Never touched when he is
-- up - his everyday physics, the hands', has its own.
local function dampers(pawn, on)
    local ok = pcall(function() pawn.Mesh:SetAllMotorsAngularVelocityDrive(on, on, false) end)
    if ok then mus.damp_off = not on end
end

-- (what is coming: anything solid along his hips' way for the next `t` seconds, and 40 cm more)
local function impact_within(pawn, v, t)
    local sp = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
    if sp < 1.0 then return false end
    local p = nil
    pcall(function() p = pawn.Mesh:GetSocketLocation(FName("pelvis")) end)
    if not p then return false end
    local reach = sp * t + 40.0
    return ray(pawn, { X = p.X, Y = p.Y, Z = p.Z }, { X = p.X + v.X / sp * reach, Y = p.Y + v.Y / sp * reach, Z = p.Z + v.Z / sp * reach })
end

-- Injuries, by section of him ("damage in section having certain parts of the body react to how damaged they are ...
-- the hand, the forearm, upper arm, the head, the chest, the thigh, the leg, the foot", 2026-10-29). Each section takes
-- damage from what it hits - its own body's sudden stop against something solid, INJURY.dv_from cm/s and more (the stop
-- beyond that over per_dv, in points; a joint's yank, with nothing solid there, is not a blow) - and from an enemy's
-- blow (the section on the side it came from, and the chest a little). Three tiers by points:
--   healthy;
--   sprained (INJURY.sprain): still moving, but slow, weak and heavy (its muscle at slow_tone, its pose control at slow
--     strength, slow_damp times as damped, slow_ramp times as slow to change), and held by the rest of him in pain on the
--     ground - a free hand reaches for it, a hurt arm is held in to the chest, a hurt leg drawn up; the chest's pain curls
--     both legs up to it ("chest pains would have the legs curl up to the chest");
--   broken (INJURY.broken): limp - no muscle, no pose - and not held: he cannot feel it.
-- The head: hurt, the whole of him goes limp ("head damage would make the whole body go limp") - for INJURY.stun
-- seconds at a sprain; at a break, knocked out: limp the whole time down, and INJURY.ko seconds more at rest before he
-- can get up. All well again as soon as he is up ("the health should refresh after every fall"), and when he dies.
-- A little figure on the screen shows each section: white, orange, black ("add a little charater hud white for tier 1
-- orange for tier 2 and black for tier 3 show the segments as well").
M.INJURY = { sprain = 35.0, broken = 70.0, max = 100.0, heal = 0.2, heal_broken = 0.08,
             dv_from = 550.0, per_dv = 12.0, quiet = 0.15, contact = 30.0, hit = 30.0, hit_chest = 10.0,
             slow = 0.3, slow_tone = 0.35, slow_damp = 3.0, slow_ramp = 3.0, hold_hz = 5.0, hold_tone = 0.15, hold_turn = 150.0, writhe = 3.0,
             stun = 1.5, ko = 3.0, thud_from = 600.0, shake_from = 900.0, side_roll = 200.0 }
do
    local I = M.INJURY
    local SEGS, BYID, BODIES = {}, {}, {}
    local function seg(id, label, bones, t)
        t = t or {}
        t.id, t.label, t.bones = id, label, bones
        SEGS[#SEGS + 1] = t
        BYID[id] = t
        for _, b in ipairs(bones) do BODIES[#BODIES + 1] = { bone = b, fname = FName(b), seg = t, w = (t.w and t.w[b]) or 1.0 } end
    end
    seg("head", "head", { "Head", "neck_01" })
    seg("chest", "chest", { "spine_05", "spine_04", "spine_03", "spine_02", "pelvis" }, { w = { pelvis = 0.6, spine_02 = 0.8 } })
    for _, sd in ipairs({ { "l", "left" }, { "r", "right" } }) do
        local s, word = sd[1], sd[2]
        seg("upperarm_" .. s, word .. " upper arm", { "upperarm_" .. s, "clavicle_" .. s }, { side = s, limb = "arm", a = "upperarm_" .. s, b = "lowerarm_" .. s })
        seg("forearm_" .. s, word .. " forearm", { "lowerarm_" .. s }, { side = s, limb = "arm", a = "lowerarm_" .. s, b = "hand_" .. s })
        seg("hand_" .. s, word .. " hand", { "hand_" .. s }, { side = s, limb = "arm", a = "hand_" .. s })
        seg("thigh_" .. s, word .. " thigh", { "thigh_" .. s }, { side = s, limb = "leg", a = "thigh_" .. s, b = "calf_" .. s })
        seg("leg_" .. s, word .. " leg", { "calf_" .. s }, { side = s, limb = "leg", a = "calf_" .. s, b = "foot_" .. s })
        seg("foot_" .. s, word .. " foot", { "foot_" .. s }, { side = s, limb = "leg", a = "foot_" .. s })
    end
    INJ.SEGS, INJ.BYID = SEGS, BYID
    local BONESEG = {}
    for _, b in ipairs(BODIES) do BONESEG[b.bone] = b.seg.id end
    -- (kept through a reload of this file: the damage is his, not the module's)
    local inj = _G.SM64_INJURY
    if not (inj and inj.seg) then inj = { seg = {}, ver = 0 }; _G.SM64_INJURY = inj end
    for _, s in ipairs(SEGS) do inj.seg[s.id] = inj.seg[s.id] or { dmg = 0.0, tier = 1 } end
    inj.pv = {}
    INJ.state = inj
    local function tier_of(d) return (d >= I.broken and 3) or (d >= I.sprain and 2) or 1 end
    function INJ.tier(id) local st = inj.seg[id]; return st and st.tier or 1 end
    local WORD = { "healthy", "sprained", "broken" }
    local function sound(name, v)
        local S = package.loaded["sfx"]
        if S then pcall(S.play, name, v or 1.0) end
    end
    local voice_t = -99.0
    local function voice(name, v)
        if os.clock() - voice_t < 0.45 then return end
        voice_t = os.clock()
        sound(name, v or 1.0)
    end
    INJ.sound, INJ.voice = sound, voice
    -- damage to a section: its tier anew, and what that brings
    function INJ.add(id, pts, why)
        local st = inj.seg[id]
        if not st or not pts or pts <= 0.0 then return end
        local was = st.tier
        st.dmg = math.min(I.max, st.dmg + pts)
        st.tier = tier_of(st.dmg)
        if id == "head" and mus.on and st.tier >= 2 then
            if st.tier >= 3 then
                if not mus.ko then mus.ko = true; log("ragdoll: knocked out - his head (%.0f)", st.dmg) end
            else
                mus.stun_until = os.clock() + I.stun
            end
        end
        -- (sprained while he writhes - tumbling on down the stairs: he writhes on, holding it)
        if st.tier == 2 and was < 2 and mus.on and mus.phase == "struggle" then
            mus.struggle_for = math.max(mus.struggle_for or 0.0, (mus.t or 0.0) + I.writhe * 0.7)
        end
        if st.tier ~= was then
            inj.ver = inj.ver + 1
            inj.flash = inj.flash or {}
            inj.flash[id] = os.clock()
            if mus.on then mus.pain = math.min(1.5, (mus.pain or 0.5) + ((st.tier >= 3) and 0.2 or 0.3)) end
            log("ragdoll: his %s %s (%.0f points, %s)", BYID[id].label, WORD[st.tier], st.dmg, why or "?")
            if st.tier >= 3 then
                sound("hit_crack", 0.9)
                voice(id == "head" and "mario_ooof" or "mario_attacked")
            else
                voice((math.random() < 0.5) and "mario_uh2" or "mario_ooof2")
            end
        end
    end
    function INJ.reset(why)
        for _, s in ipairs(SEGS) do local st = inj.seg[s.id]; st.dmg, st.tier = 0.0, 1 end
        inj.ver = inj.ver + 1
        if why then log("ragdoll: all his injuries gone (%s)", why) end
    end
    -- healing, while he is up
    function INJ.heal(dt)
        for _, s in ipairs(SEGS) do
            local st = inj.seg[s.id]
            if st.dmg > 0.0 then
                st.dmg = math.max(0.0, st.dmg - dt * ((st.tier >= 3) and I.heal_broken or I.heal))
                local t = tier_of(st.dmg)
                if t ~= st.tier then
                    st.tier = t
                    inj.ver = inj.ver + 1
                    log("ragdoll: his %s healed to %s", s.label, WORD[t])
                end
            end
        end
    end
    function INJ.any(tier)
        for _, s in ipairs(SEGS) do if inj.seg[s.id].tier == tier then return true end end
        return false
    end
    function INJ.stunned() return mus.on and ((mus.ko and true) or ((mus.stun_until or -1.0) > os.clock())) or false end
    function INJ.key() return string.format("%d%s%s%s", inj.ver, mus.ko and "K" or "", INJ.stunned() and "S" or "", inj.hold_sig or "") end
    -- the muscle's tone, section by section: weak where sprained, none where broken; none at all knocked out or stunned
    function INJ.apply(k, head)
        if INJ.stunned() then muscle_set(0.0, 0.0); return end
        muscle_set(k, head)
        local c = mus.comp
        if not (c and c:IsValid()) then return end
        for _, s in ipairs(SEGS) do
            local t = inj.seg[s.id].tier
            if t >= 2 then
                local f = (t >= 3) and 0.0 or I.slow_tone
                local base = (s.id == "head") and (head or k) or k
                for _, b in ipairs(s.bones) do
                    if b ~= "pelvis" then pcall(function() c:ApplyPhysicalAnimationSettings(FName(b), muscle_data(base * f)) end) end
                end
            end
        end
        -- (a limb that holds or is held in: most of its tone off - the tone pulls toward STORROR's flail, and beat the
        -- reach by 50 to 60 degrees, the hands never getting there, 2026-10-29)
        local plan = inj.hold_plan
        if plan then
            for _, side in ipairs({ "l", "r" }) do
                local limbs = {}
                if plan.arm[side] or plan.guard[side] then limbs[#limbs + 1] = { "upperarm_", "lowerarm_", "hand_" } end
                if plan.leg[side] then limbs[#limbs + 1] = { "thigh_", "calf_", "foot_" } end
                for _, l in ipairs(limbs) do
                    for _, pre in ipairs(l) do
                        local b = pre .. side
                        local t = BONESEG[b] and inj.seg[BONESEG[b]].tier or 1
                        local f = (t >= 3) and 0.0 or (I.hold_tone * ((t == 2) and I.slow_tone or 1.0))
                        pcall(function() c:ApplyPhysicalAnimationSettings(FName(b), muscle_data(k * f)) end)
                    end
                end
            end
        end
    end
    -- a pose control's strength, damping and ease, as its section is: (hz, extra damping, ramp)
    local CTL_SEG = { shoulder = "upperarm_", elbow = "forearm_", hip = "thigh_", knee = "leg_" }
    function INJ.ctl(c, hz, damp, ramp)
        if INJ.stunned() then return 0.0, 0.0, 0.05 end
        local t = INJ.tier(CTL_SEG[c.joint] .. c.side)
        if t >= 3 then return 0.0, 0.0, 0.05 end
        if c.hold then hz = math.max(hz, I.hold_hz) end
        if t == 2 then return hz * I.slow, damp * I.slow_damp, ramp * I.slow_ramp end
        return hz, damp, ramp
    end
    -- what the pain asks of the limbs on the ground: which section each free hand holds, which arm is held in, which
    -- leg drawn up or curled to the chest (nil: nothing hurts). Broken sections are not felt: never held.
    function INJ.plan()
        local list = {}
        for _, s in ipairs(SEGS) do if inj.seg[s.id].tier == 2 then list[#list + 1] = s end end
        if #list == 0 then inj.plan_t = nil; return nil end
        inj.plan_t = inj.plan_t or os.clock()
        table.sort(list, function(a, b) return inj.seg[a.id].dmg > inj.seg[b.id].dmg end)
        local p = { arm = {}, guard = {}, leg = {} }
        for _, side in ipairs({ "l", "r" }) do
            for _, s in ipairs(list) do if s.limb == "arm" and s.side == side then p.guard[side] = true end end
            if not p.guard[side] and INJ.tier("upperarm_" .. side) < 3 and INJ.tier("forearm_" .. side) < 3 then
                for _, s in ipairs(list) do
                    if not (s.limb == "arm" and s.side == side) then p.arm[side] = s; break end
                end
            end
        end
        local R = mus.rnd or NO_RND
        if p.arm[R.late] and os.clock() - inj.plan_t < R.hand_delay then p.arm[R.late] = nil end
        if inj.seg.chest.tier == 2 then p.leg.l, p.leg.r = "curl", "curl" end
        for _, s in ipairs(list) do if s.limb == "leg" and not p.leg[s.side] then p.leg[s.side] = "draw" end end
        return p
    end
    function INJ.mark(plan)
        local sig = ""
        if plan then
            for _, side in ipairs({ "l", "r" }) do
                sig = sig .. ((plan.arm[side] and ("A" .. plan.arm[side].id)) or (plan.guard[side] and "G") or "-") .. (plan.leg[side] or "-")
            end
        end
        inj.hold_sig, inj.hold_plan = sig, plan
        local ps = mus.pose
        if not ps then return end
        for _, c in ipairs(ps.ctl) do
            local arm = (c.joint == "shoulder" or c.joint == "elbow")
            c.hold = plan and ((arm and (plan.arm[c.side] or plan.guard[c.side])) or ((not arm) and plan.leg[c.side])) and true or false
            if not c.hold then c.iw = nil end
            c.jerk = false              -- (a spasm's, set again each frame by want_struggle while it lasts)
        end
    end
    local function add3(a, b, k) return { x = a.x + b.x * k, y = a.y + b.y * k, z = a.z + b.z * k } end
    local function sub3(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end
    local function len3(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
    local function seg_point(f, s)
        if s.id == "chest" then return add3(f.pos("spine_04"), f.fwd, 12.0) end
        if s.id == "head" then return add3(f.pos("head"), f.fwd, 10.0) end
        local a = f.pos(s.a)
        -- (a leg held near the knee - the thigh's lower part, the shin's upper - where the hands can get to)
        local at = (s.id:find("^thigh") and 0.65) or (s.id:find("^leg") and 0.3) or 0.5
        if s.b then local b = f.pos(s.b); return { x = a.x + (b.x - a.x) * at, y = a.y + (b.y - a.y) * at, z = a.z + (b.z - a.z) * at } end
        return a
    end
    -- an arm aimed to put its hand on a point: the forearm from the elbow to it; the upper arm by the triangle of the
    -- two bones and the reach, the elbow out to his side
    local function reach_dir(c, f, s, sgn)
        local t = add3(add3(seg_point(f, s), f.right, sgn * 5.0), f.fwd, 4.0)
        if c.joint == "elbow" then return vnorm(sub3(t, f.pos(c.child))) end
        local sh, el, hd = f.pos(c.child), f.pos(c.tip), f.pos("hand_" .. c.side)
        local L1, L2 = len3(sub3(el, sh)), len3(sub3(hd, el)) + 7.0
        local to = sub3(t, sh)
        local D = len3(to)
        if D < 1.0 or L1 < 1.0 then return nil end
        local u = { x = to.x / D, y = to.y / D, z = to.z / D }
        if D >= (L1 + L2) * 0.98 then return u end
        local ca = math.max(-1.0, math.min(1.0, (L1 * L1 + D * D - L2 * L2) / (2.0 * L1 * D)))
        local sa = math.sqrt(1.0 - ca * ca)
        local pole = mix(f.right, sgn * 0.8, f.up, -0.4, f.fwd, -0.2)
        local pd = pole.x * u.x + pole.y * u.y + pole.z * u.z
        pole = vnorm({ x = pole.x - u.x * pd, y = pole.y - u.y * pd, z = pole.z - u.z * pd })
        return vnorm({ x = u.x * ca + pole.x * sa, y = u.y * ca + pole.y * sa, z = u.z * ca + pole.z * sa })
    end
    -- (a holding limb's aim turned toward its goal at INJ.hold_turn degrees a second at most, from where the bone points:
    -- set at once, the strong hold whipped the arm round at 8 m/s and it sprained itself on the floor, 2026-10-29)
    local function ease(c, f, d)
        local prev = c.iw
        if not prev then local a0, a1 = f.pos(c.child), f.pos(c.tip); prev = vnorm(sub3(a1, a0)) end
        local dt = mus.dt or 0.016
        local cs = math.max(-1.0, math.min(1.0, prev.x * d.x + prev.y * d.y + prev.z * d.z))
        local ang = math.acos(cs)
        local step = math.rad(I.hold_turn) * dt
        local out = d
        if ang > step and ang > 1e-3 then
            local k = step / ang
            local sn = math.sin(ang)
            if sn > 1e-3 then
                local wa, wb = math.sin((1.0 - k) * ang) / sn, math.sin(k * ang) / sn
                out = vnorm({ x = prev.x * wa + d.x * wb, y = prev.y * wa + d.y * wb, z = prev.z * wa + d.z * wb })
            else
                out = vnorm(add3(prev, f.up, 0.1))
            end
        end
        c.iw = out
        return out
    end
    function INJ.want(base, plan)
        local inner = INJ.want_raw(base, plan)
        return function(c, f)
            local d = inner(c, f)
            if d and c.hold then return ease(c, f, d) end
            return d
        end
    end
    function INJ.want_raw(base, plan)
        return function(c, f)
            if plan then
                local sgn = (c.side == "l") and -1.0 or 1.0
                if c.joint == "shoulder" or c.joint == "elbow" then
                    local s = plan.arm[c.side]
                    if s then
                        local d = reach_dir(c, f, s, sgn)
                        if d then
                            if _G.INJ_DBG then local cur = f.pos(c.tip); local a0 = f.pos(c.child); _G.INJ_DBG[c.joint .. c.side] = { want = d, cur = vnorm({ x = cur.x - a0.x, y = cur.y - a0.y, z = cur.z - a0.z }) } end
                            return d
                        end
                    end
                    if plan.guard[c.side] then
                        if c.joint == "shoulder" then return mix(f.up, -0.7, f.fwd, 0.6, f.right, sgn * 0.1) end
                        return mix(f.right, -sgn * 0.85, f.fwd, 0.4, f.up, 0.2)
                    end
                else
                    local how = plan.leg[c.side]
                    local cu = (mus.rnd or NO_RND).curl
                    -- (knees and feet in toward the middle: aimed out, they splayed wide - "the legs come up to the chest
                    -- like he's giving birth, should be a little more centered", 2026-10-29)
                    if how == "curl" then
                        if c.joint == "hip" then return mix(f.fwd, 0.8, f.up, 0.6 + cu, f.right, -sgn * 0.03) end
                        return mix(f.up, -0.9, f.fwd, -0.25 - cu * 0.5, f.right, -sgn * 0.02)
                    elseif how == "draw" then
                        -- (the knee up to the chest, the shin out in front: within his hands' reach - drawn up only
                        -- level with his hips, the knee was 45 cm past them, 2026-10-29)
                        if c.joint == "hip" then return mix(f.fwd, 0.7, f.up, 0.7 + cu, f.right, 0.0) end
                        return mix(f.fwd, 0.5, f.up, -0.85)
                    end
                end
            end
            if base then return base(c, f) end
            return nil
        end
    end
    -- an enemy's blow: on the section nearest the side it came from (a little chance in it), and the chest a little
    function INJ.hit(pawn, push)
        local hsp = math.sqrt(push.X * push.X + push.Y * push.Y)
        if hsp < 100.0 then return end
        local from = { x = -push.X / hsp, y = -push.Y / hsp }
        local mesh = pawn.Mesh
        local pel = mesh:GetSocketLocation(FName("pelvis"))
        local best, bs = nil, -1e9
        for _, s in ipairs(SEGS) do
            local p = mesh:GetSocketLocation(FName(s.a or ((s.id == "head") and "head" or "spine_04")))
            local sc = (p.X - pel.X) * from.x + (p.Y - pel.Y) * from.y + (p.Z - pel.Z) * 0.3 + math.random() * 15.0
            if sc > bs then best, bs = s, sc end
        end
        local k = hsp / 600.0
        if best then
            INJ.add(best.id, math.max(10.0, math.min(60.0, I.hit * k)), "a blow")
            if best.id ~= "chest" then INJ.add("chest", I.hit_chest * k, "a blow") end
        end
    end
    -- each of his bodies' speed, frame to frame: a sudden stop against something solid is an impact, on that section
    function INJ.quiet(t) inj.quiet_until = os.clock() + (t or I.quiet) end
    function INJ.scan_reset() inj.pv, inj.peak, inj.peak_seg, inj.quiet_until, inj.hold_sig, inj.hold_plan, inj.plan_t = {}, 0.0, nil, 0.0, nil, nil, nil end
    -- (curled up on his back: rolled onto a side, as each fall has it - a body hugging its chest does not lie flat)
    function INJ.roll_side(pawn, dir)
        local mesh = pawn.Mesh
        local pel, ch = mesh:GetSocketLocation(FName("pelvis")), mesh:GetSocketLocation(FName("spine_05"))
        local cl, cr = mesh:GetSocketLocation(FName("clavicle_l")), mesh:GetSocketLocation(FName("clavicle_r"))
        local up = vnorm({ x = ch.X - pel.X, y = ch.Y - pel.Y, z = ch.Z - pel.Z })
        local right = vnorm({ x = cr.X - cl.X, y = cr.Y - cl.Y, z = cr.Z - cl.Z })
        local fwd = vcross(right, up)
        if fwd.z < 0.4 then return false end             -- (only from his back)
        local deg = I.side_roll * dir
        mesh:AddAngularImpulseInDegrees({ X = up.x * deg, Y = up.y * deg, Z = up.z * deg }, FName("pelvis"), true)
        mesh:AddAngularImpulseInDegrees({ X = up.x * deg, Y = up.y * deg, Z = up.z * deg }, FName("spine_03"), true)
        INJ.quiet(0.1)
        return true
    end
    -- (16 of his 21 bodies - not the neck, the collarbones or every link of the spine - and none while he lies still on
    -- the ground: 1.5 ms a frame down, all 21 read every frame, 2026-10-29)
    local SKIP = { neck_01 = true, clavicle_l = true, clavicle_r = true, spine_05 = true, spine_03 = true }
    function INJ.scan(pawn, sp)
        if sp and sp < 150.0 and (mus.phase == "struggle" or mus.phase == "rest") then
            if next(inj.pv) then inj.pv = {} end
            return
        end
        local mesh = pawn.Mesh
        local quiet = os.clock() < (inj.quiet_until or 0.0)
        local worst, wseg = 0.0, nil
        local hits = nil
        pcall(function()
            for _, b in ipairs(BODIES) do
                if not SKIP[b.bone] and os.clock() - (INJ.pushed[b.bone] or -9.0) > 0.12 then
                    local v = mesh:GetPhysicsLinearVelocity(b.fname)
                    local vx, vy, vz = v.X, v.Y, v.Z
                    if vx == vx then
                        local pv = inj.pv[b.bone]
                        if pv and not quiet then
                            local ps = math.sqrt(pv[1] * pv[1] + pv[2] * pv[2] + pv[3] * pv[3])
                            if ps > I.dv_from * 0.8 then
                                local ux, uy, uz = pv[1] / ps, pv[2] / ps, pv[3] / ps
                                local stop = -((vx - pv[1]) * ux + (vy - pv[2]) * uy + (vz - pv[3]) * uz)
                                if stop > I.dv_from * 0.8 then
                                    hits = hits or {}
                                    hits[#hits + 1] = { b = b, stop = stop, ux = ux, uy = uy, uz = uz }
                                end
                            end
                        end
                        if pv then pv[1], pv[2], pv[3] = vx, vy, vz else inj.pv[b.bone] = { vx, vy, vz } end
                    end
                end
            end
        end)
        -- (against something solid: a joint's yank is not a blow)
        for _, h in ipairs(hits or {}) do
            local b = h.b
            local p = mesh:GetSocketLocation(b.fname)
            local r = I.contact
            if ray(pawn, { X = p.X - h.ux * 5.0, Y = p.Y - h.uy * 5.0, Z = p.Z - h.uz * 5.0 }, { X = p.X + h.ux * r, Y = p.Y + h.uy * r, Z = p.Z + h.uz * r }) then
                if h.stop > worst then worst, wseg = h.stop, b.seg end
                if h.stop > I.dv_from then INJ.add(b.seg.id, (h.stop - I.dv_from) / I.per_dv * b.w, string.format("hit at %.0f cm/s", h.stop)) end
            end
        end
        -- heard and felt: the thud of him landing; the camera shaken by the hard ones
        if worst > I.thud_from and os.clock() - (inj.thud_t or -9.0) > 0.18 then
            inj.thud_t = os.clock()
            sound((worst > 1100.0) and "heavy_landing" or "body_hit_ground", math.max(0.35, math.min(1.0, (worst - I.thud_from) / 700.0 + 0.35)))
            if worst > I.shake_from then
                local G = package.loaded["game"]
                if G and G.shake_camera then pcall(G.shake_camera, math.max(0.4, math.min(1.6, (worst - I.shake_from) / 500.0 + 0.4))) end
            end
        end
        if worst > (inj.peak or 0.0) then inj.peak, inj.peak_seg = worst, wseg and wseg.id end
        -- (a hard stop: he flinches, and the big ones knock the wind out of him)
        if worst > M.LIFE.flinch_from and mus.phase ~= "brace" and not INJ.stunned() then
            mus.flinch_until = os.clock() + M.LIFE.flinch_t
            if worst > 950.0 then voice((math.random() < 0.5) and "mario_ooof" or "mario_ooof2", 0.9) end
        end
    end
    function INJ.peak() return inj.peak or 0.0, inj.peak_seg end
    -- (rocked about his spine, either way)
    function INJ.rock(pawn, deg)
        local mesh = pawn.Mesh
        local pel, ch = mesh:GetSocketLocation(FName("pelvis")), mesh:GetSocketLocation(FName("spine_05"))
        local up = vnorm({ x = ch.X - pel.X, y = ch.Y - pel.Y, z = ch.Z - pel.Z })
        mesh:AddAngularImpulseInDegrees({ X = up.x * deg, Y = up.y * deg, Z = up.z * deg }, FName("pelvis"), true)
        mesh:AddAngularImpulseInDegrees({ X = up.x * deg * 0.7, Y = up.y * deg * 0.7, Z = up.z * deg * 0.7 }, FName("spine_03"), true)
        INJ.quiet(0.08)
    end
    -- Life on the ground: writhing - rocked side to side, a spasm now and then, groans - and lying there - a limb moved now
    -- and then, and a groan if it still hurts. Not stunned or knocked out.
    local GROANS = { "mario_uh", "mario_uh2", "mario_ooof2" }
    local function spasm()
        local arm = math.random() < 0.55
        local side = (math.random() < 0.5) and "l" or "r"
        local k1, k2, k3 = rr(-0.3, 0.6), rr(0.0, 0.6), rr(0.2, 0.7)
        local dir
        if arm then
            dir = function(c, f, sg)
                if c.joint == "shoulder" then return mix(f.right, sg * 0.9, f.up, k1, f.fwd, k2) end
                return mix(f.right, sg * 0.7, f.fwd, 0.3, f.up, k3)
            end
        else
            dir = function(c, f, sg)
                if c.joint == "hip" then return mix(f.fwd, 0.9, f.up, 0.3 + k2, f.right, sg * 0.1) end
                return mix(f.up, -0.7, f.fwd, -0.7)
            end
        end
        return { arm = arm, side = side, dir = dir, until_t = os.clock() + M.LIFE.spasm_t }
    end
    function INJ.life(pawn, phase)
        if INJ.stunned() then return end
        local L, R = M.LIFE, mus.rnd or NO_RND
        local now = os.clock()
        local pain = mus.pain or 0.5
        if phase == "struggle" then
            if now >= (mus.rock_at or 0.0) then
                if mus.rock_at then
                    mus.rock_dir = -(mus.rock_dir or 1)
                    pcall(INJ.rock, pawn, mus.rock_dir * L.rock_deg * R.rock * (0.6 + 0.6 * pain))
                else
                    mus.rock_dir = (math.random() < 0.5) and 1 or -1
                end
                mus.rock_at = now + rr(L.rock_every[1], L.rock_every[2])
            end
            if now >= (mus.spasm_at or 0.0) then
                if mus.spasm_at then mus.spasm = spasm() end
                mus.spasm_at = now + rr(L.spasm_every[1], L.spasm_every[2]) / (R.spasm * (0.7 + 0.5 * pain))
            end
            if now >= (mus.groan_at or 0.0) then
                if mus.groan_at and pain >= 0.45 then voice(GROANS[math.random(1, #GROANS)], math.min(0.9, 0.5 + 0.25 * pain)) end
                mus.groan_at = now + rr(L.groan_every[1], L.groan_every[2])
            end
        elseif phase == "rest" then
            mus.rest_t = mus.rest_t or {}
            if now >= (mus.shift_at or 0.0) then
                if mus.shift_at then
                    local arm = math.random() < 0.5
                    local side = (math.random() < 0.5) and "l" or "r"
                    local set = arm and REST_ARM or REST_LEG
                    mus.rest_t[side .. (arm and "arm" or "leg")] = set[math.random(1, #set)]
                end
                mus.shift_at = now + rr(L.rest_shift[1], L.rest_shift[2])
            end
            if now >= (mus.rgroan_at or 0.0) then
                if mus.rgroan_at and (INJ.any(2) or INJ.any(3)) then voice(GROANS[math.random(1, #GROANS)], 0.45) end
                mus.rgroan_at = now + rr(L.rest_groan[1], L.rest_groan[2])
            end
        end
    end

    -- The figure on the screen: a rectangle for each section, outlined, at the bottom left; seen from behind, as he is
    -- seen, his left on the left. (figure units, y down: id, centre x, centre y, width, height, turned degrees)
    local FIG = {
        { "head", 0.0, 6.0, 11.0, 12.0, 0.0 }, { "chest", 0.0, 23.0, 15.0, 20.0, 0.0 },
        { "upperarm_l", -11.0, 20.0, 4.5, 12.0, 12.0 }, { "forearm_l", -13.5, 32.0, 4.0, 11.0, 6.0 }, { "hand_l", -14.6, 40.5, 5.0, 5.0, 0.0 },
        { "upperarm_r", 11.0, 20.0, 4.5, 12.0, -12.0 }, { "forearm_r", 13.5, 32.0, 4.0, 11.0, -6.0 }, { "hand_r", 14.6, 40.5, 5.0, 5.0, 0.0 },
        { "thigh_l", -4.0, 40.0, 6.0, 14.0, 0.0 }, { "leg_l", -4.5, 54.0, 5.0, 13.0, 0.0 }, { "foot_l", -5.5, 62.5, 7.0, 4.0, 0.0 },
        { "thigh_r", 4.0, 40.0, 6.0, 14.0, 0.0 }, { "leg_r", 4.5, 54.0, 5.0, 13.0, 0.0 }, { "foot_r", 5.5, 62.5, 7.0, 4.0, 0.0 },
    }
    M.INJURY_HUD = { unit = 1.9, x = 30.0, y = -92.0 }
    local COLORS = { { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }, { R = 1.0, G = 0.22, B = 0.0, A = 1.0 }, { R = 0.0, G = 0.0, B = 0.0, A = 1.0 } }
    local OUTLINE, BLINK = { R = 0.06, G = 0.06, B = 0.06, A = 0.9 }, { R = 1.0, G = 0.0, B = 0.0, A = 1.0 }
    -- (the figure kept through a reload of this file, not a second one put up over it)
    local hud, hud_serial, hud_wait = _G.SM64_INJURY_HUD, _G.SM64_INJURY_SERIAL or 0, 0.0
    local function hud_ok()
        if not hud then return false end
        local ok, valid = pcall(function() return hud.world == lib.world():GetAddress() and hud.widget:IsValid() end)
        return ok and valid
    end
    local function hud_build()
        local world, pc = lib.world(), lib.controller()
        if not (world and pc) then return end
        local function cls(p) return StaticFindObject(p) end
        local HU = M.INJURY_HUD
        local U = HU.unit
        hud_serial = hud_serial + 1
        _G.SM64_INJURY_SERIAL = hud_serial
        local tag = "SM64Injury" .. hud_serial
        local widget = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName(tag))
        local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), widget, FName(tag .. "Tree"))
        widget.WidgetTree = tree
        local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName(tag .. "Canvas"))
        tree.RootWidget = canvas
        local tex = lib.texture(world, "hud_white")
        local n = 0
        local function rect(cx, cy, w, h, ang, color)
            n = n + 1
            local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName(tag .. "_" .. n))
            if tex then img:SetBrushFromTexture(tex, false) end
            img:SetColorAndOpacity(color)
            local slot = canvas:AddChildToCanvas(img)
            slot:SetAnchors({ Minimum = { X = 0.0, Y = 1.0 }, Maximum = { X = 0.0, Y = 1.0 } })
            slot:SetAlignment({ X = 0.5, Y = 0.5 })
            slot:SetSize({ X = w * U, Y = h * U })
            slot:SetPosition({ X = (HU.x + cx) * U, Y = (HU.y + cy) * U })
            if ang ~= 0.0 then img:SetRenderTransformAngle(ang) end
            return img
        end
        local h = { widget = widget, world = world:GetAddress(), fill = {}, shown = {} }
        for _, f in ipairs(FIG) do rect(f[2], f[3], f[4] + 2.0, f[5] + 2.0, f[6], OUTLINE) end
        for _, f in ipairs(FIG) do h.fill[f[1]] = rect(f[2], f[3], f[4], f[5], f[6], COLORS[1]); h.shown[f[1]] = 2 end
        widget:AddToViewport(49)
        hud = h
        _G.SM64_INJURY_HUD = h
        log("ragdoll: the injury figure is up (%d sections)", #FIG)
    end
    function INJ.hud_update(dt)
        if not hud_ok() then
            hud = nil
            hud_wait = hud_wait + (dt or 0.016)
            if hud_wait < 1.2 then return end
            hud_wait = 0.0
            local okb, errb = pcall(hud_build)
            if not okb and not inj.hud_err then inj.hud_err = true; log("ragdoll: the injury figure failed (%s)", tostring(errb)) end
            if not hud then return end
        end
        local HP = _G.HEALTH
        local hide = ((HP and HP.hud_off) or M.INJURY_HUD.off) and true or false
        if hide ~= (hud.hidden or false) then
            hud.hidden = hide
            pcall(function() hud.widget:SetVisibility(hide and 1 or 4) end)
        end
        if hide then return end
        local now = os.clock()
        for id, img in pairs(hud.fill) do
            local t = inj.seg[id].tier
            local fl = inj.flash and inj.flash[id]
            local blink = fl and (now - fl < 1.0) and (math.floor((now - fl) / 0.12) % 2 == 1) or false
            local key = t * 2 + (blink and 1 or 0)
            if key ~= hud.shown[id] then
                hud.shown[id] = key
                pcall(function() img:SetColorAndOpacity(blink and BLINK or COLORS[t]) end)
            end
        end
    end
end
-- (tests and the dev channel)
function M.injuries()
    local out = {}
    for _, s in ipairs(INJ.SEGS) do local st = INJ.state.seg[s.id]; out[s.id] = { dmg = st.dmg, tier = st.tier } end
    return out
end
function M.injure(id, pts, why) INJ.add(id, pts, why or "dev") end
function M.heal_injuries() INJ.reset("dev") end
function M.pose_dbg()
    local ps = mus.pose
    if not ps then return "no poses" end
    local t = {}
    for _, c in ipairs(ps.ctl) do t[#t + 1] = string.format("%s_%s %.1fhz d%.1f%s", c.joint, c.side, c.hz, c.dmp or -1, c.hold and " HOLD" or "") end
    return table.concat(t, ", ") .. " | tone " .. tostring(mus.k) .. " stunned " .. tostring(INJ.stunned())
end
function M.knocked_out() return mus.on and mus.ko and air.rest < M.SETTLE_T + M.INJURY.ko or false end

-- His limbs kept out of each other. STORROR's ragdoll has no collision between its own bodies and none can be switched on
-- from here (the physics asset's table is not reachable), and with the stronger poses arms and legs passed through each
-- other and through him - "arms and legs still going through eachother", 2026-10-29. So: each limb a capsule along its
-- bones (the hand to the middle of its fingers, the foot to the ball of it), and every frame, any two that should never
-- meet and overlap are pushed apart along the line between their nearest points - the way they were coming together
-- taken out, and SELF.k cm/s more for each cm of overlap (SELF.max_dv at most); the trunk moved a quarter as much as a
-- limb. Not the upper arms or thighs against the trunk: they meet it at the shoulder and the hip.
-- (pushed apart only up to a separating speed of SELF.k cm/s per cm of overlap, and each body SELF.max_dv a frame at most
-- all told: added afresh each frame and pair by pair, a hand among four limbs was flung at 11 m/s and sprained itself
-- lying still, 2026-10-29)
-- (15 and 1.5 m/s let a forearm sink 10 cm into a thigh - through it: firmer, the pile-up still gone, 2026-10-29)
M.SELF = { k = 35.0, max_dv = 300.0 }
local SELFCOL = {}
do
    local CAPS = {
        torso = { "pelvis", "spine_05", 11.0, "spine_03", 0.25 },
        thigh_l = { "thigh_l", "calf_l", 6.5, "thigh_l", 1.0 }, thigh_r = { "thigh_r", "calf_r", 6.5, "thigh_r", 1.0 },
        calf_l = { "calf_l", "foot_l", 5.5, "calf_l", 1.0 }, calf_r = { "calf_r", "foot_r", 5.5, "calf_r", 1.0 },
        foot_l = { "foot_l", "ball_l", 4.5, "foot_l", 1.0 }, foot_r = { "foot_r", "ball_r", 4.5, "foot_r", 1.0 },
        upperarm_l = { "upperarm_l", "lowerarm_l", 5.0, "upperarm_l", 1.0 }, upperarm_r = { "upperarm_r", "lowerarm_r", 5.0, "upperarm_r", 1.0 },
        lowerarm_l = { "lowerarm_l", "hand_l", 4.0, "lowerarm_l", 1.0 }, lowerarm_r = { "lowerarm_r", "hand_r", 4.0, "lowerarm_r", 1.0 },
        hand_l = { "hand_l", "middle_01_l", 4.0, "hand_l", 1.0 }, hand_r = { "hand_r", "middle_01_r", 4.0, "hand_r", 1.0 },
    }
    local PAIRS = {
        { "thigh_l", "thigh_r" }, { "thigh_l", "calf_r" }, { "calf_l", "thigh_r" }, { "calf_l", "calf_r" },
        { "foot_l", "foot_r" }, { "foot_l", "calf_r" }, { "calf_l", "foot_r" },
        { "lowerarm_l", "torso" }, { "hand_l", "torso" }, { "lowerarm_r", "torso" }, { "hand_r", "torso" },
        { "lowerarm_l", "lowerarm_r" }, { "hand_l", "hand_r" }, { "lowerarm_l", "hand_r" }, { "hand_l", "lowerarm_r" },
        { "upperarm_l", "lowerarm_r" }, { "lowerarm_l", "upperarm_r" }, { "upperarm_l", "hand_r" }, { "hand_l", "upperarm_r" },
    }
    for _, a in ipairs({ "lowerarm_l", "lowerarm_r", "hand_l", "hand_r" }) do
        for _, b in ipairs({ "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r" }) do PAIRS[#PAIRS + 1] = { a, b } end
    end
    local BONES = {}
    do
        local seen = {}
        for _, c in pairs(CAPS) do for i = 1, 2 do if not seen[c[i]] then seen[c[i]] = true; BONES[#BONES + 1] = { c[i], FName(c[i]) } end end end
    end
    for _, c in pairs(CAPS) do c.fbody = FName(c[4]) end
    local function closest(p1, q1, p2, q2)
        local d1x, d1y, d1z = q1.x - p1.x, q1.y - p1.y, q1.z - p1.z
        local d2x, d2y, d2z = q2.x - p2.x, q2.y - p2.y, q2.z - p2.z
        local rx, ry, rz = p1.x - p2.x, p1.y - p2.y, p1.z - p2.z
        local a = d1x * d1x + d1y * d1y + d1z * d1z
        local e = d2x * d2x + d2y * d2y + d2z * d2z
        local f = d2x * rx + d2y * ry + d2z * rz
        local sv, tv = 0.0, 0.0
        if a > 1e-6 or e > 1e-6 then
            if a <= 1e-6 then
                tv = math.max(0.0, math.min(1.0, f / e))
            else
                local c = d1x * rx + d1y * ry + d1z * rz
                if e <= 1e-6 then
                    sv = math.max(0.0, math.min(1.0, -c / a))
                else
                    local b = d1x * d2x + d1y * d2y + d1z * d2z
                    local den = a * e - b * b
                    sv = (den > 1e-6) and math.max(0.0, math.min(1.0, (b * f - c * e) / den)) or 0.0
                    tv = (b * sv + f) / e
                    if tv < 0.0 then tv = 0.0; sv = math.max(0.0, math.min(1.0, -c / a))
                    elseif tv > 1.0 then tv = 1.0; sv = math.max(0.0, math.min(1.0, (b - c) / a)) end
                end
            end
        end
        return { x = p1.x + d1x * sv, y = p1.y + d1y * sv, z = p1.z + d1z * sv }, { x = p2.x + d2x * tv, y = p2.y + d2y * tv, z = p2.z + d2z * tv }
    end
    function SELFCOL.tick(pawn)
        local mesh = pawn.Mesh
        local P = {}
        for _, b in ipairs(BONES) do local v = mesh:GetSocketLocation(b[2]); P[b[1]] = { x = v.X, y = v.Y, z = v.Z } end
        local n_hit = 0
        local acc = {}
        local function push(cap, x, y, z)
            local e = acc[cap[4]]
            if not e then e = { f = cap.fbody, bone = cap[4], x = 0.0, y = 0.0, z = 0.0 }; acc[cap[4]] = e end
            e.x, e.y, e.z = e.x + x, e.y + y, e.z + z
        end
        for _, pr in ipairs(PAIRS) do
            local A, B = CAPS[pr[1]], CAPS[pr[2]]
            local ca, cb = closest(P[A[1]], P[A[2]], P[B[1]], P[B[2]])
            local dx, dy, dz = cb.x - ca.x, cb.y - ca.y, cb.z - ca.z
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            local pen = A[3] + B[3] - dist
            if pen > 0.0 then
                local nx, ny, nz
                if dist > 0.5 then
                    nx, ny, nz = dx / dist, dy / dist, dz / dist
                else
                    local ma, mb = P[A[1]], P[B[1]]
                    local ex, ey, ez = mb.x - ma.x, mb.y - ma.y, mb.z - ma.z
                    local el = math.sqrt(ex * ex + ey * ey + ez * ez)
                    if el < 0.5 then nx, ny, nz = 1.0, 0.0, 0.0 else nx, ny, nz = ex / el, ey / el, ez / el end
                end
                local va = mesh:GetPhysicsLinearVelocity(A.fbody)
                local vb = mesh:GetPhysicsLinearVelocity(B.fbody)
                local apart = (vb.X - va.X) * nx + (vb.Y - va.Y) * ny + (vb.Z - va.Z) * nz      -- (> 0: separating)
                local want = math.max(0.0, M.SELF.k * pen - apart)
                if want > 0.0 then
                    local wa, wb = A[5], B[5]
                    local ka, kb = want * wa / (wa + wb), want * wb / (wa + wb)
                    push(A, -nx * ka, -ny * ka, -nz * ka)
                    push(B, nx * kb, ny * kb, nz * kb)
                end
                n_hit = n_hit + 1
                if _G.SELF_DBG then _G.SELF_DBG[pr[1] .. "-" .. pr[2]] = math.max(_G.SELF_DBG[pr[1] .. "-" .. pr[2]] or 0.0, pen) end
            end
        end
        for _, e in pairs(acc) do
            local m = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z)
            if m > 0.01 then
                local k = math.min(1.0, M.SELF.max_dv / m)
                mesh:AddImpulse({ X = e.x * k, Y = e.y * k, Z = e.z * k }, e.f, true)
                if m > 50.0 then INJ.pushed[e.bone] = os.clock() end
            end
        end
        return n_hit
    end
end

-- (the switch off: the mashup's own part alone - a knock-down's push given to his body a moment in, or his own speed
-- into a tumble going down at a run: Unreal's whole-body velocity change, lost when given as the ragdoll begins)
local function throw_only(pawn, down, dt)
    if not down then
        mus.on = false
        pcall(function() local v = pawn:GetVelocity(); mus.cap_v = { X = v.X, Y = v.Y, Z = v.Z } end)
        return
    end
    local G = package.loaded["game"]
    if not mus.on then
        mus.on, mus.t, mus.thrown, mus.rnd = true, 0.0, false, nil
        local kp = G and G.knock_push
        mus.push, mus.carry, mus.knocked = nil, nil, false
        if kp and os.clock() - (kp.t or 0) < 0.4 then
            mus.knocked = true
            if kp.X * kp.X + kp.Y * kp.Y + kp.Z * kp.Z > 1.0 then mus.push = kp end
            G.knock_push = nil
        end
        local cv = mus.cap_v
        if not mus.push and cv and cv.X * cv.X + cv.Y * cv.Y > M.TUMBLE.min_v * M.TUMBLE.min_v then mus.carry = cv end
        pcall(function() pawn.Mesh:SetUseCCD(true, FName("None")) end)
        return
    end
    mus.t = mus.t + math.min(dt or 0.016, 0.1)
    local kp = G and G.knock_push
    if kp and kp ~= mus.push_seen and os.clock() - (kp.t or 0) < 0.3 and mus.thrown then
        mus.push_seen, G.knock_push = kp, nil
        if kp.X * kp.X + kp.Y * kp.Y + kp.Z * kp.Z > 1.0 then mus.push, mus.carry, mus.thrown, mus.t = kp, nil, false, 0.0 end
    end
    if not mus.thrown and mus.t >= M.TUMBLE.at then
        mus.thrown = true
        local okt, errt = pcall(throw_now, pawn)
        if not okt then log("ragdoll: throw failed (%s)", tostring(errt)) end
    end
end

local function muscle_tick(pawn, down, dt)
    if not pawn then return end
    if not M.EUPHORIA then return throw_only(pawn, down, dt) end
    local G = package.loaded["game"]
    if not down then
        -- (up again: all his sections well again - each fall starts fresh, "the health should refresh after every
        -- fall", 2026-10-29)
        if mus.on then
            local pk, pseg = INJ.peak()
            log("ragdoll: up - the hardest stop %.0f cm/s (%s)", pk, tostring(pseg))
            if INJ.any(2) or INJ.any(3) then INJ.reset("he got up") end
        end
        mus.ko, mus.stun_until = nil, nil
        mus.damp_off = false        -- (up: his everyday physics back, its own settings with it - not touched)
        if mus.pose then pose_end() end
        if mus.sd then spin_damp_end() end
        if mus.on or mus.k > 0.0 then muscle_set(0.0, 0.0) end
        mus.on, mus.ready = false, true
        -- (his speed on his feet, for a tumble if he goes down at a run)
        pcall(function() local v = pawn:GetVelocity(); mus.cap_v = { X = v.X, Y = v.Y, Z = v.Z } end)
        return
    end
    local d = math.min(dt or 0.016, 0.1)
    mus.dt = d
    local b, sg, T, P = M.BEHAVE, M.STRUGGLE, M.TONE, M.POSE
    if not mus.on then
        if not mus.ready then return end
        if not muscle_comp(pawn) then mus.ready = false; return end
        mus.on, mus.ready, mus.t, mus.sent, mus.phase, mus.air_t = true, false, 0.0, -1.0, "fall", 0.0
        mus.vmax, mus.thrown, mus.windmilled = 0.0, false, false
        mus.seed = math.random() * 6.2832          -- (each fall a little different: where the limbs' waving starts)
        mus.rnd, mus.side_rolled = fall_character(), false   -- (and its own character: fall_character)
        mus.pain, mus.spasm, mus.flinch_until, mus.screamed = 0.5, nil, nil, false
        mus.rock_at, mus.spasm_at, mus.groan_at, mus.shift_at, mus.rgroan_at, mus.rest_t = nil, nil, nil, nil, nil, nil
        -- (what threw him: an enemy's knock-down just now, or his own run)
        local kp = G and G.knock_push
        mus.push, mus.carry, mus.knocked = nil, nil, false
        if kp and os.clock() - (kp.t or 0) < 0.4 then
            mus.knocked = true
            if kp.X * kp.X + kp.Y * kp.Y + kp.Z * kp.Z > 1.0 then mus.push = kp end
            G.knock_push = nil
        end
        local cv = mus.cap_v
        if not mus.push and cv and cv.X * cv.X + cv.Y * cv.Y > M.TUMBLE.min_v * M.TUMBLE.min_v then mus.carry = cv end
        -- (the injuries: impacts read from now on, the first moments left out; a blow's put on its section; a broken
        -- head knocks him out again)
        INJ.scan_reset()
        INJ.quiet()
        mus.ko, mus.stun_until = (INJ.tier("head") >= 3) or nil, nil
        if mus.ko then log("ragdoll: knocked out - his head is broken") end
        if mus.push then pcall(INJ.hit, pawn, mus.push) end
        INJ.apply(T.fall * mus.rnd.tone, T.head)
        mus.tone_key = INJ.key()
        dampers(pawn, false)
        -- (his bodies' collision made continuous: at 9 m/s they went through a 30 cm slab and on into the floor under it,
        -- the test area's chute, 2026-10-29)
        pcall(function() pawn.Mesh:SetUseCCD(true, FName("None")) end)
        local oks, made = pcall(spin_damp_start, pawn)
        local okp, posed = pcall(pose_start, pawn)
        log("ragdoll: muscle on (%.0f%s%s%s)", T.fall, mus.knocked and ", knocked down" or "", (oks and made) and "" or ", no spin damper",
            (okp and posed) and "" or ", no poses")
        return
    end
    mus.t = mus.t + d
    -- (hit again while down - an enemy's next blow, the ram coming back: thrown again, the fall begun afresh; the first
    -- blow alone counted before, and the rest just shoved his capsule, 2026-10-29)
    do
        local kp = G and G.knock_push
        if kp and kp ~= mus.push_seen and os.clock() - (kp.t or 0) < 0.3 and mus.thrown then
            mus.push_seen, G.knock_push = kp, nil
            if kp.X * kp.X + kp.Y * kp.Y + kp.Z * kp.Z > 1.0 then
                mus.push, mus.carry, mus.knocked, mus.thrown = kp, nil, true, false
                mus.phase, mus.t, mus.air_t, mus.sent = "fall", 0.0, 0.0, -1.0
                dampers(pawn, false)
                log("ragdoll: hit again while down")
                pcall(INJ.hit, pawn, kp)
                INJ.quiet()
            end
        end
    end
    local v = air.last_v or { X = 0.0, Y = 0.0, Z = 0.0 }
    local sp = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
    if sp > (mus.vmax or 0.0) then mus.vmax = sp end
    local PF = _G.RG_PROF          -- (dev: where the time goes, when asked for)
    local pf0 = PF and os.clock()
    do
        local oks, errs = pcall(INJ.scan, pawn, sp)
        if not oks and not mus.scan_err then mus.scan_err = true; log("ragdoll: injury scan failed (%s)", tostring(errs)) end
    end
    if PF then PF.scan = (PF.scan or 0.0) + os.clock() - pf0; PF.n = (PF.n or 0) + 1 end
    if not mus.thrown and mus.t >= M.TUMBLE.at then
        mus.thrown = true
        local okt, errt = pcall(throw_now, pawn)
        if not okt then log("ragdoll: throw failed (%s)", tostring(errt)) end
        INJ.quiet()
    end
    local was = mus.phase
    -- (down on the ground: the struggle - a hit's, or by how fast he came down; none afloat)
    local function settle_down()
        local dur = 0.0
        if not fl.on then
            if mus.knocked then dur = sg.knocked
            else dur = math.min(sg.max, math.max(sg.least, ((mus.vmax or 0.0) - sg.from_v) / sg.per_v)) end
        end
        -- (hurting, he writhes longer, holding it; knocked out, not at all)
        if not fl.on and INJ.any(2) then dur = math.max(dur, M.INJURY.writhe) end
        -- (how much it hurts: how hard he came down, a hit, what is sprained and broken - the writhing's size and length)
        local nspr, nbrk = 0, 0
        for _, sgm in ipairs(INJ.SEGS) do local tt = INJ.tier(sgm.id); if tt == 2 then nspr = nspr + 1 elseif tt == 3 then nbrk = nbrk + 1 end end
        mus.pain = math.max(0.2, math.min(1.5, 0.25 + ((mus.vmax or 0.0) - 400.0) / 1500.0 + 0.3 * nspr + 0.2 * nbrk + (mus.knocked and 0.3 or 0.0)))
        dur = dur * (mus.rnd or NO_RND).writhe * (0.8 + 0.5 * mus.pain)
        if mus.ko then dur = 0.0 end
        if dur > 0.0 and mus.pose then
            mus.phase, mus.t, mus.struggle_for = "struggle", 0.0, dur
            log("ragdoll: struggling on the ground (%.1f s)", dur)
        else
            mus.phase, mus.t = "rest", 0.0
            if mus.damp_off then dampers(pawn, true) end
        end
    end
    local function landed()
        local R = M.ROLL
        local hsp = math.sqrt(v.X * v.X + v.Y * v.Y)
        if not fl.on and mus.pose and hsp > R.min_v then
            mus.phase, mus.t = "roll", 0.0
            spin_damp_set(R.spin_damp)
            -- (set rolling the way he goes, if he is not turning much already)
            pcall(function()
                local w = pawn.Mesh:GetPhysicsAngularVelocityInDegrees(FName("pelvis"))
                if math.sqrt(w.X * w.X + w.Y * w.Y) < 90.0 then
                    local dir = { x = v.X / hsp, y = v.Y / hsp, z = 0.0 }
                    local axis = vcross({ x = 0.0, y = 0.0, z = 1.0 }, dir)
                    local deg = math.min(R.spin_max, hsp * R.spin)
                    pawn.Mesh:AddAngularImpulseInDegrees({ X = axis.x * deg, Y = axis.y * deg, Z = axis.z * deg }, FName("pelvis"), true)
                end
            end)
            INJ.quiet(0.08)
            log("ragdoll: rolling on (%.0f cm/s)", hsp)
        else
            settle_down()
        end
    end
    if mus.phase == "fall" then
        local grounded = fl.on or ground_under(pawn)
        if grounded or (sp < 150.0 and mus.air_t <= b.air_after) then
            if grounded or mus.t > 0.2 then landed() end
        else
            mus.air_t = mus.air_t + d
            -- (STORROR's flail kept going - its ragdoll is the flail's: replaced, it ended the ragdoll in the air, the
            -- mod put him back down, round and round. Set back before it runs out; at this tone it barely shows)
            if mus.air_t > b.air_after then
                pcall(function()
                    local ai = pawn.Mesh:GetAnimInstance()
                    local cur = ai:GetCurrentActiveMontage()
                    if cur and cur:IsValid() and cur:GetFName():ToString():find(b.flail, 1, true) then
                        if ai:Montage_GetPosition(cur) > cur:GetPlayLength() - 0.08 then ai:Montage_SetPosition(cur, b.flail_from) end
                    end
                end)
                if not mus.windmilled then mus.windmilled = true; log("ragdoll: falling (%.1f s, %s)", mus.air_t, (mus.rnd or NO_RND).style) end
                -- (a long way down, fast: Mario's scream)
                if not mus.screamed and mus.air_t > M.LIFE.scream_air and v.Z < M.LIFE.scream_vz then
                    mus.screamed = true
                    if INJ.voice then INJ.voice("mario_waaaooow", 1.0) end
                end
            end
            if mus.air_t > b.air_after and sp > b.brace_v and impact_within(pawn, v, b.brace_t) then
                mus.phase, mus.brace_at, mus.brace_v0 = "brace", mus.t, sp
                log("ragdoll: bracing (%.0f cm/s, %.1f s falling)", sp, mus.air_t)
            end
            if mus.air_t > b.max_air then landed() end
        end
    elseif mus.phase == "brace" then
        if fl.on or ground_under(pawn) or sp < (mus.brace_v0 or sp) * 0.55 or mus.t - (mus.brace_at or mus.t) > 0.7 then
            if mus.brace_first then
                log("ragdoll: the reach - upper arms %.0f degrees off their aim at the start, %.0f at the end", mus.brace_first, mus.brace_last or mus.brace_first)
            end
            mus.brace_first, mus.brace_last = nil, nil
            landed()
        end
    elseif mus.phase == "roll" then
        local hsp = math.sqrt(v.X * v.X + v.Y * v.Y)
        if fl.on or hsp < M.ROLL.end_v or mus.t > M.ROLL.max then
            spin_damp_set(M.SPIN_DAMP.damping)
            settle_down()
        end
    elseif mus.phase == "struggle" then
        pcall(INJ.life, pawn, "struggle")
        if fl.on or mus.t >= (mus.struggle_for or 0.0) then
            mus.phase, mus.t = "rest", 0.0
            if mus.damp_off then dampers(pawn, true) end
            log("ragdoll: done struggling - lying as he is")
        end
    end
    -- the poses: aimed, and their strength eased toward the phase's
    local pf1 = PF and os.clock()
    if mus.pose then
        local okp, errp = pcall(function()
            -- (on the ground, what hurts is held: INJ.plan; in the air and the roll, nothing)
            local plan = (mus.phase == "struggle" or mus.phase == "rest") and INJ.plan() or nil
            INJ.mark(plan)
            if plan and plan.leg.l == "curl" and not mus.side_rolled and mus.rnd and mus.rnd.side_roll ~= 0 then
                mus.side_rolled = true
                local okr, rolled = pcall(INJ.roll_side, pawn, mus.rnd.side_roll)
                if okr and rolled then log("ragdoll: curled up - rolled onto his %s side", (mus.rnd.side_roll > 0) and "one" or "other") end
            end
            if mus.phase == "rest" then pcall(INJ.life, pawn, "rest") end
            if mus.flinch_until and os.clock() < mus.flinch_until and not INJ.stunned() then
                pose_aim(pawn, INJ.want(want_flinch, plan))
                pose_strength(d, P.hz.flinch, P.hz.flinch, 0.03)
            elseif mus.phase == "fall" then
                pose_aim(pawn, want_fall(mus.air_t + (mus.seed or 0.0), mus.air_t))
                pose_strength(d, P.hz.fall, P.hz.fall_legs)
            elseif mus.phase == "brace" then
                local dir = vnorm({ x = v.X, y = v.Y, z = v.Z })
                local aim = vnorm({ x = dir.x, y = dir.y, z = dir.z - (mus.rnd or NO_RND).brace_down })
                local mesh = pawn.Mesh
                local cl, cr = mesh:GetSocketLocation(FName("clavicle_l")), mesh:GetSocketLocation(FName("clavicle_r"))
                local right = vnorm({ x = cr.X - cl.X, y = cr.Y - cl.Y, z = cr.Z - cl.Z })
                local off = pose_aim(pawn, want_brace(aim, right))
                mus.brace_first = mus.brace_first or off
                mus.brace_last = off
                pose_strength(d, P.hz.brace, P.hz.fall, P.ramp_brace)
            elseif mus.phase == "roll" then
                pose_aim(pawn, want_roll)
                pose_strength(d, M.ROLL.hz, M.ROLL.hz)
            elseif mus.phase == "struggle" then
                pose_aim(pawn, INJ.want(want_struggle(mus.t + (mus.seed or 0.0), mus.knocked and mus.t < sg.cover), plan))
                pose_strength(d, P.hz.struggle, P.hz.struggle, P.ramp_struggle)
            else
                pose_aim(pawn, INJ.want(want_rest, plan))      -- (at rest: still holding what hurts; shifting now and then)
                pose_strength(d, P.hz.rest, P.hz.rest)
            end
        end)
        if not okp and not mus.pose_err then mus.pose_err = true; log("ragdoll: poses failed (%s)", tostring(errp)) end
    end
    -- the muscle's tone by phase (again a moment in, STORROR's ragdoll perhaps having made its bodies anew; then as it
    -- changes), STORROR's dampers kept off while he falls and struggles
    local k = (mus.phase == "fall" and T.fall) or (mus.phase == "brace" and T.brace) or (mus.phase == "roll" and T.roll) or (mus.phase == "struggle" and T.struggle) or T.rest
    if PF then PF.pose = (PF.pose or 0.0) + os.clock() - pf1 end
    do
        local okc, errc = pcall(SELFCOL.tick, pawn)
        if not okc and not mus.self_err then mus.self_err = true; log("ragdoll: limb separation failed (%s)", tostring(errc)) end
    end
    local key = INJ.key()       -- (and again when an injury changes, or he is stunned or comes to)
    if was ~= mus.phase or (mus.sent < 0.1 and mus.t >= 0.1) or mus.t < mus.sent or key ~= mus.tone_key then
        if mus.sent < 0.1 and mus.t >= 0.1 and mus.phase ~= "rest" then dampers(pawn, false); pcall(function() pawn.Mesh:SetUseCCD(true, FName("None")) end) end
        INJ.apply(k * (mus.rnd or NO_RND).tone, T.head)
        mus.sent, mus.tone_key = mus.t, key
    end
end
function M.muscle_state() return mus.on, mus.k, mus.t end      -- (tests)
function M.muscle_phase() return mus.on and mus.phase or nil, mus.air_t, mus.t end      -- (tests)
function M.struggling() return mus.on and mus.phase == "struggle" end
function M.set_cap_v(v) mus.cap_v = v end      -- (tests: his speed on his feet, for a tumble)

-- A watchdog for a state that should not exist: his capsule climbing while the movement component has him in free
-- fall at terminal speed (velocity down, height up, second after second). Seen three times on 2026-10-29, each after a
-- test tool of mine got him up with the capsule left behind his lying body: STORROR still held him for ragdolled (its
-- physics type 2, not its everyday 10) and carried the capsule after the mesh each frame, a few metres a second
-- upward, for good. Its own get-up (TryGetupFromRagdoll) ends that state - it stopped the climb at once; a change of
-- scene does too. So: a second of it and STORROR's get-up is asked for; two more and he is respawned (game.lua
-- G.respawn, the scene again where he came in).
local climb = { z = nil, t = 0.0, bad = 0.0, tried = 0.0 }
local function climb_watch(pawn, dt)
    if not pawn then climb.z = nil; return end
    local z, vz, mode = nil, 0.0, 0
    pcall(function()
        z = pawn:K2_GetActorLocation().Z
        vz = pawn:GetVelocity().Z
        mode = pawn.CharacterMovement.MovementMode
    end)
    if not z then return end
    -- (not through a cutscene: the ending moves him itself, and over the Final Bowser's broken floor it was taken for
    -- the climb and he was respawned in the middle of it - "player getting stuck during outro", 2026-11-04)
    do
        local Gc = package.loaded["game"]
        if Gc and Gc.cutscene then climb.z, climb.t, climb.bad = z, 0.0, 0.0; return end
    end
    local d = math.min(dt or 0.016, 0.1)
    climb.t = climb.t + d
    if climb.t < 0.5 then return end
    local rose = climb.z and (z - climb.z) or 0.0
    -- (half a second falling faster than 15 m/s and yet 100 cm higher than before: impossible. Or STORROR's physics type
    -- reading 2 - its ragdoll's - while he is not down and "falling": seen only in the climbs, and sooner)
    local ptype = nil
    pcall(function()
        local hp = climb.hp
        if not (hp and hp:IsValid()) or climb.hp_for ~= pawn:GetAddress() then
            hp = comp(pawn, "Physics Control")
            climb.hp, climb.hp_for = hp, pawn:GetAddress()
        end
        if hp then ptype = hp.CharacterPhysicsType end
    end)
    local odd = ptype == 2 and mode == 3 and not limp(pawn)
    if (mode == 3 and vz < -1500.0 and rose > 100.0) or (odd and rose > 30.0) then climb.bad = climb.bad + climb.t else climb.bad = 0.0 end
    climb.z, climb.t = z, 0.0
    if climb.bad >= 1.0 and os.clock() - climb.tried > 2.5 then
        climb.tried = os.clock()
        local G = package.loaded["game"]
        local pk = comp(pawn, "Parkour!")
        if pk and os.clock() - (climb.respawned or -99.0) > 10.0 and not climb.getup_done then
            climb.getup_done = true
            log("ragdoll watchdog: climbing %.0f cm while in free fall at %.0f cm/s - STORROR's get-up asked for", rose, vz)
            pcall(function() pk:TryGetupFromRagdoll() end)
        elseif G and G.respawn and not G.pending and not G.dying then
            climb.getup_done, climb.respawned = nil, os.clock()
            log("ragdoll watchdog: still climbing (%.0f cm) - respawning him", rose)
            pcall(G.respawn)
        end
    elseif climb.bad == 0.0 then
        climb.getup_done = nil
    end
end

function M.tick(dt)
    do local okw, errw = pcall(climb_watch, lib.pawn(), dt); if not okw and not climb.said then climb.said = true; log("ragdoll watchdog failed: %s", tostring(errw)) end end
    -- (his injuries: all mended when he dies; the figure on the screen kept up to date)
    if not M.EUPHORIA and _G.SM64_INJURY_HUD and not mus.hud_gone then
        mus.hud_gone = true
        pcall(function()
            local h = _G.SM64_INJURY_HUD
            if h.world == lib.world():GetAddress() and h.widget:IsValid() then h.widget:RemoveFromParent() end
        end)
        _G.SM64_INJURY_HUD = nil
    end
    if M.EUPHORIA then
        local okh, errh = pcall(function()
            local G = package.loaded["game"]
            local dying = G and G.dying
            if dying and not INJ.state.dead then INJ.state.dead = true; INJ.reset("he died")
            elseif not dying then INJ.state.dead = nil end
            INJ.hud_update(dt)
        end)
        if not okh and not mus.hud_err then mus.hud_err = true; log("ragdoll: the injuries' tick failed (%s)", tostring(errh)) end
    end
    do
        local okf, onf = pcall(afloat, lib.pawn())
        fl.on = (okf and onf) and true or false
        local oku, onu = false, false
        if not fl.on then oku, onu = pcall(updraft, lib.pawn()) end
        up.on = (oku and onu) and true or false
    end
    do
        local w = lib.world()
        local wa = w and w:GetAddress()
        if wa ~= air.world then
            air.world = wa
            M.forget_knock()
            -- (the map went, and its actors with it: the blocker and the athlete held forgotten, untouched - a method
            -- called on one freed crashes the game)
            if air.blocker_addr then lib.keep[air.blocker_addr] = nil end
            air.blocker, air.blocker_addr = nil, nil
            air.pawn, air.addr, air.on, air.pk, air.pk_for = nil, nil, false, nil, nil
            -- (and the muscle's and the brace's parts, gone with it: forgotten, not touched)
            mus.comp, mus.addr, mus.bc, mus.ours, mus.on, mus.ready, mus.k = nil, nil, nil, nil, false, true, 0.0
            mus.pose, mus.push, mus.carry, mus.sd = nil, nil, nil, nil
        end
    end
    -- (down: still, a while - or no getting up yet)
    do
        local pawn = lib.pawn()
        local down = false
        if pawn then
            -- (his hips well under his capsule, as tick's `standing` has it: just up off STORROR's get-up, his hips a
            -- little low still, the hold came back on for a moment)
            local okl, l = pcall(limp, pawn, 35.0)
            down = (okl and l) and true or false
        end
        air.down = down
        if down then
            local v = nil
            pcall(function()
                local u = pawn.Mesh:GetPhysicsLinearVelocity(FName("pelvis"))
                v = math.sqrt(u.X * u.X + u.Y * u.Y + u.Z * u.Z)
                if v == v then air.last_v = { X = u.X, Y = u.Y, Z = u.Z } end      -- (his flight, kept for M.tick's re-ragdoll)
                local wv = pawn.Mesh:GetPhysicsAngularVelocityInDegrees(FName("pelvis"))
                if wv.X == wv.X then air.last_w = { X = wv.X, Y = wv.Y, Z = wv.Z } end   -- (and his spin)
            end)
            local lim = fl.on and M.SETTLE_V_WATER or M.SETTLE_V
            if v and v == v and v < lim then air.rest = air.rest + math.min(dt or 0.016, 0.1) else air.rest = 0.0 end
        else
            air.rest = 0.0
        end
        do
            local okm, errm = pcall(muscle_tick, pawn, down, dt)
            if not okm and not mus.err then mus.err = true; log("ragdoll: muscle failed (%s)", tostring(errm)) end
        end
        air.ground_ok = down and air.rest >= M.SETTLE_T and (fl.on or ground_under(pawn)) or false
        hold_air(pawn, down and not M.settled(), down and "at rest, free to get up" or "out of the ragdoll")
        -- (out of it while still flying - STORROR's own get-up in the air, on its own or on a button the holds did not
        -- reach; a Heave-Ho's throw then carried him on up 40 m stood up: "still able to stand in mid air", 2026-10-28):
        -- back into STORROR's ragdoll at once, flying on. Only after a knock-down not yet at rest, three times at most,
        -- for six seconds at most.)
        if down then
            air.up_at = nil
            if M.settled() then air.knock_t, air.re_n = nil, 0
            -- (a knock-down of the mod's only - an enemy's hit or throw, G.knock_down's timed get-up: STORROR's own
            -- stumble, off a wall or an overhang in mid-air, is over in a third of a second and was forced down again,
            -- twice, his body still moving - "somethings wrong with this wall in front of me like the collisions are
            -- off", 2026-10-28)
            elseif not air.knock_t then
                local G = package.loaded["game"]
                if G and G.getup_at then air.knock_t, air.re_n = os.clock(), 0 end
            end
        elseif air.knock_t and pawn then
            -- (only the moment he comes out of it: a quarter second on he is up, the knock-down over - a jump of his after
            -- getting up was taken for a get-up in the air, and he was put down: "player randomly falling over when
            -- jumping", 2026-10-28)
            air.up_at = air.up_at or os.clock()
            if os.clock() - air.up_at > 0.25 then air.knock_t, air.re_n, air.up_at = nil, 0, nil end
        end
        -- (never up on his own: "the player should never stand on his own", 2026-10-29. Out of a ragdoll with no press of his
        -- get-up (UP_KEYS) and no get-up of the game's (a warp, a revive, the lava's leap: forget_knock) - STORROR ending its
        -- ragdoll by itself as he rolls, or after a stumble - back down at once, flying on as he was. Not afloat, in an
        -- updraft, carried, dying or out of power; six times in ten seconds at most)
        local redone = false
        if not M.EUPHORIA then
            air.down_for = 0.0
        elseif down then
            if (air.down_for or 0.0) == 0.0 then air.down_start = os.clock() end
            air.down_for = (air.down_for or 0.0) + math.min(dt or 0.016, 0.1)
            local pc = lib.controller()
            if pc then
                for _, k in ipairs(INTENT_KEYS) do
                    local okk, kv = pcall(function() return pc:IsInputKeyDown(k.key) end)
                    if okk and kv then air.asked, air.asked_key = os.clock(), k.name; break end
                end
            end
        elseif (air.down_for or 0.0) > 0.0 then
            local was = air.down_for
            air.down_for = 0.0
            local G = package.loaded["game"]
            -- (a press any time in this spell down, the last 8 s: STORROR's get-up from lying flat takes longer than the
            -- 2 s first allowed, and the player's press was taken for none - "it takes 2 a presses to get up now", 2026-10-29)
            local pressed = (air.asked or -99.0) >= (air.down_start or 0.0) and os.clock() - air.asked < 8.0
            local asked = pressed or os.clock() - (air.allowed or -99.0) < 1.0
            if was >= M.SELF_UP_MIN and pressed then log("ragdoll: up on the player's %s", tostring(air.asked_key)) end
            if os.clock() - (air.self_t0 or -99.0) > 10.0 then air.self_n, air.self_t0 = 0, os.clock() end
            if pawn and not asked and was >= M.SELF_UP_MIN and not fl.on and not up.on and (air.self_n or 0) < 6
               and not (G and (G.down_for_good or G.dying or G.pending or G.carried)) then
                -- (STORROR really out of its ragdoll - its physics type no longer 2 - not a flicker of his hips' height)
                local ptype = nil
                pcall(function() local hp = comp(pawn, "Physics Control"); ptype = hp and hp.CharacterPhysicsType end)
                if ptype ~= 2 then
                    local pk = comp(pawn, "Parkour!")
                    if pk and pcall(function() pk:StartRagdoll(1.0, false) end) then
                        redone = true
                        air.self_n = (air.self_n or 0) + 1
                        local lv, lw = air.last_v, air.last_w
                        local cv = safe_carry(pawn, lv)
                        air.carry = cv and { v = cv, w = lw and { X = lw.X, Y = lw.Y, Z = lw.Z }, n = 3 } or nil
                        log("ragdoll: stood up on his own after %.1f s down - back down (%d)", was, air.self_n)
                    end
                end
            end
        end
        if not down and air.knock_t and pawn and not redone then
            -- (STORROR can end its ragdoll again and again in one flight - three times in a second and a half, a Heave-Ho's
            -- throw, and on the third he was left standing in the air: twelve, within eight seconds)
            if os.clock() - air.knock_t > 8.0 or (air.re_n or 0) >= 12 then
                air.knock_t, air.re_n = nil, 0
            else
                -- (out of it the first frame, while his body was still flying - its speed the frame before: waiting for
                -- STORROR's falling state left him seen standing a few frames, "still able to stand up mid air", 2026-10-28)
                local flying = false
                local lv = air.last_v
                if lv and math.sqrt(lv.X * lv.X + lv.Y * lv.Y + lv.Z * lv.Z) > 300.0 then flying = true end
                if not flying then
                    pcall(function()
                        local v = pawn:GetVelocity()
                        flying = pawn.CharacterMovement.MovementMode == 3 and math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) > 300.0
                    end)
                end
                if flying then
                    local pk = comp(pawn, "Parkour!")
                    if pk and pcall(function() pk:StartRagdoll(1.0, false) end) then
                        air.re_n = (air.re_n or 0) + 1
                        -- (and on as he was flying: a fresh ragdoll starts still, and he dropped straight down - "after being
                        -- ragdolled in the air and pressing a to stand up it stops all momentum", 2026-10-28. His body's
                        -- speed from just before, given to all of it over the next frames, gravity taken off as it goes)
                        local lv, lw = air.last_v, air.last_w
                        local cv = safe_carry(pawn, lv)
                        air.carry = cv and { v = cv, w = lw and { X = lw.X, Y = lw.Y, Z = lw.Z }, n = 3 } or nil
                        if not cv then log("ragdoll: (landed or by a wall: not flung on)") end
                        log("ragdoll: got up in the air - back down (%d)", air.re_n)
                    end
                end
            end
        end
        -- (the flight carried into a fresh ragdoll: its bodies set going as he was, three frames running)
        local c = air.carry
        if c and pawn then
            local d = math.min(dt or 0.016, 0.1)
            c.v.Z = c.v.Z - (fl.g or 1500.0) * d
            local okc = pcall(function() pawn.Mesh:SetAllPhysicsLinearVelocity(c.v, false) end)
            if not okc then pcall(function() pawn.Mesh:AddImpulseToAllBodiesBelow(c.v, FName("pelvis"), true, true) end) end
            -- (his spin as well: "also doesnt keep rotational momentum", 2026-10-28)
            if c.w then pcall(function() pawn.Mesh:SetAllPhysicsAngularVelocityInDegrees(c.w, false) end) end
            c.n = c.n - 1
            if c.n <= 0 then air.carry = nil end
        end
        -- (and every press STORROR has queued up meanwhile thrown away, each frame: it reads its A for itself, past every
        -- switch and the blocker - pressed while he flew, its get-up began, and was undone, a twitch; "very slight
        -- twitching with a presses", 2026-10-28)
        if air.on and pawn then
            if not (air.pk and air.pk_for == air.addr and air.pk:IsValid()) then
                air.pk, air.pk_for = comp(pawn, "Parkour!"), air.addr
            end
            if air.pk then pcall(function() air.pk:ClearInputQueue() end) end
        end
        -- (kept off while held: anything giving his input back meanwhile - a cutscene's end - is undone)
        if air.on and pawn then
            air.re = (air.re or 0.0) + (dt or 0.016)
            if air.re > 0.25 then
                air.re = 0.0
                local pc = lib.controller()
                if pc then pcall(function() pawn:DisableInput(pc) end) end
            end
        end
    end
    local s = st
    if not s then return end
    local world = lib.world()
    if not world or world:GetAddress() ~= s.world then st, M.active = nil, false; return end
    local pc, pawn = lib.controller(), lib.pawn()
    if not (pc and pawn) then M.stop(true); return end
    s.t = s.t + math.min(dt or 0.016, 0.1)
    s.frame = s.frame + 1
    -- (the shove: the frame after the ragdoll comes on, once its bodies are moving)
    if not s.pushed and s.frame >= 2 then
        s.pushed = true
        pcall(function() pawn.Mesh:AddImpulseToAllBodiesBelow(s.push, FName("pelvis"), true, true) end)
    end
    -- (thrown off the stage: once his body is well below where he stood, it is over; the capsule goes down to it, and
    -- the game's own falling and lava take it from there)
    local fell, standing = false, false
    pcall(function()
        local pz, az = pawn.Mesh:GetSocketLocation(FName("pelvis")).Z, pawn:K2_GetActorLocation().Z
        fell = pz < az - 700.0
        standing = pz > az - 35.0 and not fl.on and not up.on    -- (afloat or in an updraft, his capsule is up with his hips)
    end)
    if fell then log("ragdoll: off the edge"); M.stop(); return end
    -- A: STORROR's own get-up (a press since he went down, not a button still held from before)
    local now = false
    for _, k in ipairs(UP_KEYS) do
        local okk, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(k) }) end)
        if okk and v then now = true end
    end
    -- (not out of power: then he stays down till the screen closes, game.lua G.set_down_for_good)
    local G = package.loaded["game"]
    if now and not s.held and s.t > MIN_DOWN and M.settled() and not (G and G.down_for_good) and not (fl.on and (fl.depth or 0) > 60.0) then
        pcall(function() s.pk:TryGetupFromRagdoll() end)
        log("ragdoll: getting up (STORROR's)")
    end
    s.held = now
    -- (STORROR got him up: his pelvis back up at standing height a while)
    if s.t > MIN_DOWN and standing then s.up_for = s.up_for + math.min(dt or 0.016, 0.1) else s.up_for = 0.0 end
    if s.up_for > 0.4 then
        st, M.active = nil, false
        cloth_back(pawn)
        log("ragdoll: up (STORROR's own)")
    end
end

return M
