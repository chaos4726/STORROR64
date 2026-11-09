-- Squished under a Thwomp (or a Grindel), the Mario 64 way (act_squished in mario_actions_cutscene.c, squish_mario_model
-- in mario.c): as it comes down on him he is pressed flat, a pancake on the floor under it - 1.8 times as wide, a
-- twentieth as high - and three wedges of power go; he is held there while it sits on him; once it has lifted off him
-- (30 units), half a second later he pops back up - small a moment, then a rubbery wobble back to his own size (Mario 64
-- squats him 1.4 wide and 0.4 high and wobbles that; the athlete's shirt and trousers can only be scaled evenly) - and is
-- let go once it is clear over his head (his capsule is out of it).
-- ("well your supposed to get squished under him", 2026-10-17; before this he was thrown out from under it.)
-- Out of power under it, he stays flat until the screen closes on him (Mario 64: he is gone, squashed).
local lib = require("lib")

local M = {}

local LOCK = "SM64Squish"
local HEIGHT = 176.0            -- his capsule's height, cm (his body mesh sits at its foot, 88 under its middle)
local HALF = 88.0
local FLAT_XY, FLAT_Z = 1.8, 0.05
local FLAT_AT = 10.1 * 0.75     -- (the room under it, cm, at which he is flat and hurt)
local LIFTED = 30.0 * 0.75      -- (it is off him: 30 units over his floor)
local WAIT = 15 / 30            -- (then this long, still flat)
local SQUAT = 14 / 30           -- (squishTimer 30 down to 17: 1.4 wide, 0.4 high)
local POP = { 0x46, 0x32, 0x32, 0x3C, 0x46, 0x50, 0x50, 0x3C, 0x28, 0x14, 0x14, 0x1E, 0x32, 0x3C, 0x3C, 0x28 }   -- sSquishScaleOverTime
local CLEAR = HEIGHT + 10.0     -- (let go once it is this far over his feet)
local ROOM = HEIGHT - 2.0       -- (squeezed from below: room enough to be himself again - Mario 64's 160 units, his height)
local LONGEST = 10.0            -- (Mario 64 kills him after 300 frames under it; here he is let go)
local OUT_AFTER = 0.4           -- (flat this long on something carrying him on, before he is put down off it: o.out)

local st = nil   -- { pawn, addr, body, x, y, zc (his middle, held), feet, bottom (fn), what, phase, t, age, cloth, ... }

local function game() return package.loaded["game"] end
local function sfx(name, v) local S = package.loaded["sfx"]; if S then pcall(S.play, name, v) end end

function M.active() return st ~= nil end
function M.debug() return st end

-- his controls off (on): the stick, STORROR's own locomotion and every parkour move (jumps too) - shell.lua's way
local function controls(s, on)
    local pawn, pc = s.pawn, lib.controller()
    if not on then
        -- (the move-input lock is a count: added to only when it is off, and taken back only if it was ours)
        pcall(function() if not pc:IsMoveInputIgnored() then pc:SetIgnoreMoveInput(true); s.ign = true end end)
        pcall(function() pawn:DisableInput(pc) end)
    else
        pcall(function() if s.ign then pc:SetIgnoreMoveInput(false); s.ign = nil end end)
        pcall(function() pawn:EnableInput(pc) end)
    end
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
    s.locked = not on
end

-- What of him is drawn, to be flattened piece by piece: his head, shirt, trousers and shoes, and the actors of ours on
-- him - footik's copy of his body (drawn in place of his own) at his feet, scaled with the rest; Mario's cap and the
-- caps at his head bone, moved down and shrunk with his flattened head. NOT his body mesh: STORROR's Physics Control
-- simulates it - scaled, its bodies blew apart ("the charater model completely disintagrates") - and the camera boom
-- hangs off its pelvis ("the camear laucnes lightyears into the sky"), 2026-10-17.
-- His shirt and trousers (Chaos cloth) only take an even scale: squashed one way they splay out in spikes, at a twentieth
-- high into a band across the level (seen 2026-10-17, even with their simulation off) - so they shrink evenly to his
-- flattened height, and a flat pancake of overalls and shirt lies under him in their place (`pancake`).
local PARTS = { Head = true, Feet = true }
local CLOTH = { TorsoCloth = true, LegsCloth = true }

local function find_parts(s)
    local parts, sock, cloth, ours = {}, {}, {}, {}
    local ok, err = pcall(function()
        s.body.AttachChildren:ForEach(function(_, e)
            local c = e:get()
            if not (c and c:IsValid()) then return end
            local o = c:GetOwner()
            if not (o and o:IsValid()) then return end
            if o:GetAddress() == s.addr then
                local n = c:GetFName():ToString()
                if PARTS[n] then parts[#parts + 1] = c elseif CLOTH[n] then cloth[#cloth + 1] = c end
                return
            end
            if not lib.keep[o:GetAddress()] then return end           -- (only ours: not STORROR's flashlight)
            local name = c:GetAttachSocketName()
            if name:ToString() == "None" then
                parts[#parts + 1] = c
                ours[#ours + 1] = o
            else
                local rl, rs = c.RelativeLocation, c.RelativeScale3D
                sock[#sock + 1] = { c = c, name = name, rl = { rl.X, rl.Y, rl.Z }, rs = { rs.X, rs.Y, rs.Z } }
            end
        end)
    end)
    s.parts, s.sock, s.cloth_parts = parts, sock, cloth
    -- (the cloth of ours on him - the Metal Cap's metal copies of his shirt and trousers, in its actor at his feet -
    -- hidden and still with his own: scaled with that actor they stretched the same way, "thwomp is still stretching
    -- cloths when squashed while having metal cap", 2026-10-17)
    s.cloth_extra = {}
    pcall(function()
        local ccls = StaticFindObject("/Script/ChaosClothAssetEngine.ChaosClothComponent")
        for _, o in ipairs(ours) do
            for _, e in ipairs(o:K2_GetComponentsByClass(ccls)) do
                local c = e:get()
                if c and c:IsValid() then s.cloth_extra[#s.cloth_extra + 1] = c; s.cloth[#s.cloth + 1] = c end
            end
        end
    end)
    -- (footik's copy leads his shoes, trousers and shirt; a squashed leader smears its followers across the level - a
    -- band through him, 20 times as wide at a twentieth high - so they follow his own unsquashed body meanwhile, as his
    -- head always does, and footik's leg bending stops at once: it works in the world, through the copy's squash)
    local F = package.loaded["footik"]
    local fs = F and F.debug and F.debug()
    if fs and fs.on and fs.follow then
        s.fs = fs
        fs.alpha = 0.0
        for _, c in ipairs(fs.follow) do
            pcall(function() if c:IsValid() then c:SetLeaderPoseComponent(s.body, true, false) end end)
        end
    end
    local names = {}
    for _, c in ipairs(parts) do pcall(function() names[#names + 1] = c:GetFName():ToString() end) end
    for _, c in ipairs(cloth) do pcall(function() names[#names + 1] = c:GetFName():ToString() .. " (evenly)" end) end
    for _, k in ipairs(sock) do pcall(function() names[#names + 1] = k.c:GetFName():ToString() .. "@" .. k.name:ToString() end) end
    lib.log("squish: flattening %s%s", table.concat(names, ", "), ok and "" or (" (" .. tostring(err) .. ")"))
    -- (his shirt and trousers drawn as skinned, not simulated, while he is out of shape: they would fly about as he is
    -- pressed and popped)
    s.sim = {}
    for _, c in ipairs(s.cloth) do
        pcall(function()
            if c:IsSimulationEnabled() then c:SetEnableSimulation(false); s.sim[#s.sim + 1] = c end
        end)
    end
    -- (footik off - a cap's look, or footik switched off - his own body is what is drawn: hidden while he is out of shape)
    pcall(function() if s.body:IsVisible() then s.body:SetVisibility(false, false); s.body_hidden = true end end)
end

-- (a rotator's axes, Unreal's way)
local function axes(r)
    local p, y, l = math.rad(r.Pitch), math.rad(r.Yaw), math.rad(r.Roll)
    local sp, cp, sy, cy, sr, cr = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(l), math.cos(l)
    return { cp * cy, cp * sy, sp },
           { sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp },
           { -(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp }
end

-- (an actor of ours at a bone: where it would be, pulled to the flattened body round his feet, and shrunk by as much;
-- written as properties and taken up by the scale call - no function with a hit result, every frame)
local function place_sock(s, k, o, xy, z)
    local c = k.c
    if not c:IsValid() then return end
    local sl = s.body:GetSocketLocation(k.name)
    local X, Y, Z = axes(s.body:GetSocketRotation(k.name))
    local rl = k.rl
    local wx = sl.X + X[1] * rl[1] + Y[1] * rl[2] + Z[1] * rl[3]
    local wy = sl.Y + X[2] * rl[1] + Y[2] * rl[2] + Z[2] * rl[3]
    local wz = sl.Z + X[3] * rl[1] + Y[3] * rl[2] + Z[3] * rl[3]
    local tx, ty, tz = o.X + (wx - o.X) * xy - sl.X, o.Y + (wy - o.Y) * xy - sl.Y, o.Z + (wz - o.Z) * z - sl.Z
    c.RelativeLocation = { X = X[1] * tx + X[2] * ty + X[3] * tz, Y = Y[1] * tx + Y[2] * ty + Y[3] * tz,
                           Z = Z[1] * tx + Z[2] * ty + Z[3] * tz }
    local u = (xy * xy * z) ^ (1.0 / 3.0)
    c:SetRelativeScale3D({ X = k.rs[1] * u, Y = k.rs[2] * u, Z = k.rs[3] * u })
end

-- His shirt and trousers while he is pressed and flat: hidden - the pancake is drawn in their place. Led from his body
-- and shrunk they still stretched out across the floor under the Thwomp ("when getting crushed by thwomp the cloths
-- stretch out really far", 2026-10-17). For the pop they are back, led by footik's copy again, scaled evenly with him.
local function cloth_hidden(s, hide)
    if s.cloth_hid == hide then return end
    s.cloth_hid = hide
    for _, c in ipairs(s.cloth_parts or {}) do pcall(function() if c:IsValid() then c:SetHiddenInGame(hide, false) end end) end
    for _, c in ipairs(s.cloth_extra or {}) do pcall(function() if c:IsValid() then c:SetHiddenInGame(hide, false) end end) end
end

local function cloth_follow_copy(s)
    local fs = s.fs
    if not (fs and fs.on and fs.pose and fs.pose:IsValid()) then return end
    for _, c in ipairs(s.cloth_parts or {}) do
        pcall(function() if c:IsValid() then c:SetLeaderPoseComponent(fs.pose, true, false) end end)
    end
end

-- his shape, set every frame: `xy` wide and `z` high (his shirt and trousers hidden while he is out of an even shape)
local function shape(s, xy, z)
    s.xy, s.z = xy, z
    if not s.parts then find_parts(s) end
    for _, c in ipairs(s.parts) do
        pcall(function() if c:IsValid() then c:SetRelativeScale3D({ X = xy, Y = xy, Z = z }) end end)
    end
    local even = math.abs(xy - z) < 0.001
    cloth_hidden(s, not even)
    for _, c in ipairs(s.cloth_parts) do
        pcall(function() if c:IsValid() then c:SetRelativeScale3D({ X = z, Y = z, Z = z }) end end)
    end
    if #s.sock > 0 then
        local o = nil
        pcall(function() o = s.body:K2_GetComponentLocation() end)
        if o then for _, k in ipairs(s.sock) do pcall(place_sock, s, k, o, xy, z) end end
    end
end

-- his own shape again
local function unshape(s)
    cloth_hidden(s, false)
    for _, c in ipairs(s.cloth_parts or {}) do
        pcall(function() if c:IsValid() then c:SetRelativeScale3D({ X = 1.0, Y = 1.0, Z = 1.0 }) end end)
    end
    for _, c in ipairs(s.parts or {}) do
        pcall(function() if c:IsValid() then c:SetRelativeScale3D({ X = 1.0, Y = 1.0, Z = 1.0 }) end end)
    end
    for _, k in ipairs(s.sock or {}) do
        pcall(function()
            if not k.c:IsValid() then return end
            k.c.RelativeLocation = { X = k.rl[1], Y = k.rl[2], Z = k.rl[3] }
            k.c:SetRelativeScale3D({ X = k.rs[1], Y = k.rs[2], Z = k.rs[3] })
        end)
    end
    local fs = s.fs
    s.fs = nil
    if fs and fs.on and fs.follow and fs.pose and fs.pose:IsValid() then
        for _, c in ipairs(fs.follow) do
            pcall(function() if c:IsValid() then c:SetLeaderPoseComponent(fs.pose, true, false) end end)
        end
    end
    if s.body_hidden then
        s.body_hidden = nil
        local F = package.loaded["footik"]
        local fs = F and F.debug and F.debug()
        if not (fs and fs.on) then pcall(function() s.body:SetVisibility(true, false) end) end
    end
    for _, c in ipairs(s.sim or {}) do pcall(function() if c:IsValid() then c:SetEnableSimulation(true) end end) end
    s.sim = nil
    for _, c in ipairs(s.cloth) do pcall(function() c:ForceNextUpdateTeleportAndReset() end) end
end

-- The pancake: Mario 64's flattened Mario seen from above, lying on the floor under his own flattened head, hands and
-- shoes - blue overalls spread round him, red shoulders and arms out to the sides with white gloves, the straps and
-- their gold buttons. A mesh of ours in his facing, at his feet, for as long as he is flat.
local BLUE, RED, WHITE, GOLD = { 0.10, 0.22, 0.70 }, { 0.80, 0.08, 0.08 }, { 0.95, 0.95, 0.95 }, { 1.0, 0.78, 0.15 }

local function pancake_section()
    local sec = { id = 0, layer = "opaque", pos = {}, nrm = {}, uv = {}, col = {}, idx = {}, nverts = 0 }
    local function v(x, y, z, c)
        local n = #sec.pos
        sec.pos[n + 1], sec.pos[n + 2], sec.pos[n + 3] = x, y, z
        sec.nrm[n + 1], sec.nrm[n + 2], sec.nrm[n + 3] = 0.0, 0.0, 1.0
        sec.uv[#sec.uv + 1], sec.uv[#sec.uv + 2] = 0.0, 0.0
        local k = #sec.col
        sec.col[k + 1], sec.col[k + 2], sec.col[k + 3], sec.col[k + 4] = c[1], c[2], c[3], 1.0
        sec.nverts = sec.nverts + 1
        return sec.nverts - 1
    end
    local function tri(a, b, c)            -- (both ways round: seen from above whichever way the engine faces it)
        local i = #sec.idx
        sec.idx[i + 1], sec.idx[i + 2], sec.idx[i + 3] = a, b, c
        sec.idx[i + 4], sec.idx[i + 5], sec.idx[i + 6] = a, c, b
    end
    local function ellipse(cx, cy, rx, ry, z, c)
        local mid, ring = v(cx, cy, z, c), {}
        for i = 0, 24 do
            local a = 2.0 * math.pi * i / 24
            ring[i] = v(cx + rx * math.cos(a), cy + ry * math.sin(a), z, c)
        end
        for i = 0, 23 do tri(mid, ring[i], ring[i + 1]) end
    end
    local function rect(x0, y0, x1, y1, z, c)
        local a, b, cc, d = v(x0, y0, z, c), v(x1, y0, z, c), v(x1, y1, z, c), v(x0, y1, z, c)
        tri(a, b, cc); tri(a, cc, d)
    end
    -- (cm, x forward and y to his right; each layer a little over the one under it)
    ellipse(0.0, 0.0, 38.0, 46.0, 0.6, BLUE)                -- overalls, legs spread round
    ellipse(-3.0, 0.0, 17.0, 40.0, 0.9, RED)                -- shoulders
    for _, side in ipairs({ -1.0, 1.0 }) do
        ellipse(-2.0, side * 56.0, 9.0, 20.0, 0.8, RED)     -- an arm
        ellipse(-2.0, side * 76.0, 8.0, 8.0, 1.0, WHITE)    -- its glove
        rect(-20.0, side * 9.0, 16.0, side * 16.0, 1.2, BLUE)   -- a strap
        ellipse(14.0, side * 12.5, 3.2, 3.2, 1.4, GOLD)     -- its button
    end
    return sec
end

local function pancake_on(s)
    if s.pancake then return end
    pcall(function()
        local world = lib.world()
        local yaw = s.pawn:K2_GetActorRotation().Yaw
        local a = lib.spawn_actor(world, { X = s.x, Y = s.y, Z = s.feet + 0.5 }, yaw)
        if not a then return end
        pcall(function() a:SetActorEnableCollision(false) end)
        local pmc = lib.add_pmc(a)
        if pmc then
            pcall(function() pmc:SetCollisionEnabled(0) end)
            pcall(function() pmc:SetCastShadow(false) end)
            lib.add_sections(world, pmc, { pancake_section() })
            -- (metal, as he is, under the Metal Cap: its own material, caps.lua's)
            local C = package.loaded["caps"]
            if C and C.on and C.on("metal") then
                local mid = lib.try_load("/Engine/EngineMaterials/WorldGridMaterial.WorldGridMaterial")
                if mid then pcall(function() pmc:SetMaterial(0, mid) end) end
            end
        end
        s.pancake = a
    end)
end

local function pancake_off(s)
    local a = s.pancake
    s.pancake = nil
    if a then pcall(lib.destroy, a) end
end

-- kept where he was pressed down: no movement at all (mode None, set after any move - a move sets him falling)
local function hold(s)
    pcall(function()
        local pawn = s.pawn
        local l = pawn:K2_GetActorLocation()
        local dx, dy, dz = l.X - s.x, l.Y - s.y, l.Z - s.zc
        if dx * dx + dy * dy + dz * dz > 4.0 then
            pawn:K2_SetActorLocation({ X = s.x, Y = s.y, Z = s.zc }, false, {}, true)
        end
        local cm = pawn.CharacterMovement
        if cm.MovementMode ~= 0 then cm:SetMovementMode(0, 0) end
    end)
end

-- (every frame of a squish written down, and put in the log when it ends: what moved him, what STORROR played, where
-- the camera was - "the squish is very very very very buggy", 2026-10-17)
local function note(s, pawn, gap)
    if not s.trace or #s.trace >= 400 then return end
    local r = { string.format("%.2f", s.age), s.phase, string.format("g%.0f", gap > 1.0e8 and -1 or gap) }
    pcall(function()
        r[#r + 1] = string.format("sc%.2f/%.2f", s.xy or 1.0, s.z or 1.0)
        local cm = pawn.CharacterMovement
        r[#r + 1] = "m" .. tostring(cm.MovementMode)
        local l = pawn:K2_GetActorLocation()
        r[#r + 1] = string.format("d%.0f,%.0f,%.0f", l.X - s.x, l.Y - s.y, l.Z - s.zc)
        local v = cm.Velocity
        r[#r + 1] = string.format("v%.0f", math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z))
        local mt = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
        if mt and mt:IsValid() then r[#r + 1] = mt:GetFName():ToString() end
        local c = lib.controller().PlayerCameraManager:GetCameraLocation()
        r[#r + 1] = string.format("cam%.0f/%.0f", math.sqrt((c.X - l.X) ^ 2 + (c.Y - l.Y) ^ 2), c.Z - s.feet)
    end)
    s.trace[#s.trace + 1] = table.concat(r, " ")
end

local function dump(s)
    local t = s.trace
    if not t or #t == 0 then return end
    s.trace = nil
    lib.log("squish trace (%d frames; age phase gap sc mode drift speed montage cam):", #t)
    for i = 1, #t, 8 do lib.log("  %s", table.concat(t, " | ", i, math.min(#t, i + 7))) end
end

local function unfreeze(s)
    if s.rate == nil then return end
    local r = s.rate
    s.rate = nil
    pcall(function() s.body.GlobalAnimRateScale = (r > 0.0) and r or 1.0 end)
end

local function release(s)
    if s.free then return end
    s.free = true
    unfreeze(s)
    controls(s, true)
    local G = game()
    if G and G.parkour_reset then pcall(G.parkour_reset, s.pawn) end
    -- (out of None the way an arrival is: falling, still - he is on his floor, so he lands at once)
    pcall(function()
        local cm = s.pawn.CharacterMovement
        cm:SetMovementMode(3, 0)
        cm.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
    end)
end

-- (STORROR's knock-down would ragdoll a pancake: out of power under it he stays flat, as Mario does)
local function guard_game()
    local G = game()
    if not G or G.squish_guarded then return end
    G.squish_guarded = true
    local kd, sd = G.knock_down, G.set_down_for_good
    local function on() local SQ = package.loaded["squish"]; return SQ and SQ.active and SQ.active() end
    if kd then G.knock_down = function(...) if on() then return end; return kd(...) end end
    if sd then G.set_down_for_good = function(v, ...) if v and on() then return end; return sd(v, ...) end end
end

-- Pressed down on by something: `o.bottom()` its underside (scene Z), `o.floor` its floor (scene Z, where he goes if he
-- is in the air), `o.grounded`, `o.what` (for the log). False when he cannot be squished now.
function M.start(pawn, o)
    if st or not pawn then return false end
    local G = game()
    if G and (G.dying or (G.intangible and G.intangible())) then return false end
    local R = package.loaded["ragdoll"]
    if R and R.active then return false end
    local body = nil
    pcall(function() body = pawn.Mesh end)
    if not (body and body:IsValid()) then return false end
    local l = nil
    pcall(function() l = pawn:K2_GetActorLocation() end)
    if not l then return false end
    local zc = l.Z
    if o.floor and not o.grounded then zc = o.floor + HALF end
    if o.floor_fn then
        local f = nil
        pcall(function() f = o.floor_fn() end)
        if f then zc = f + HALF end
    end
    guard_game()
    local s = { pawn = pawn, addr = pawn:GetAddress(), body = body, x = l.X, y = l.Y, zc = zc, feet = zc - HALF,
                bottom = o.bottom, floor_fn = o.floor_fn, shift_fn = o.shift_fn, out = o.out, x0 = l.X, y0 = l.Y,
                what = o.what or "something heavy", phase = "down", t = 0.0,
                age = 0.0, frame = 0, cloth = (G and G.cloth_comps) and G.cloth_comps(pawn) or {}, trace = {} }
    st = s
    if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
    -- (his pose stops where it is while he is held - Mario 64 holds one pose - or STORROR runs, jumps or flails on in
    -- the pancake)
    pcall(function() s.rate = body.GlobalAnimRateScale; body.GlobalAnimRateScale = 0.0 end)
    pcall(function() pawn.CharacterMovement:StopMovementImmediately() end)
    hold(s)
    controls(s, false)
    lib.log("squished by %s", s.what)
    return true
end

-- back to his own shape and his controls, now (a scene going, a new athlete)
function M.stop()
    local s = st
    if not s then return end
    st = nil
    dump(s)
    pancake_off(s)
    pcall(function() if s.pawn:IsValid() and s.pawn:GetAddress() == s.addr then
        unshape(s)
        unfreeze(s)
        if s.locked then controls(s, true) end
        if not s.free then
            pcall(function() if s.pawn.CharacterMovement.MovementMode == 0 then s.pawn.CharacterMovement:SetMovementMode(3, 0) end end)
        end
    end end)
end

local function hurt(s)
    local HP = _G.HEALTH
    local C = package.loaded["caps"]
    if C and C.on and C.on("metal") then return end
    if HP and HP.grace <= 0 and not HP.dead_t and HP.damage(3, s.what) then
        sfx("mario_attacked")                           -- (as loud as MARIO FX: sfx.lua)
    end
end

local function to_pop(s)
    s.phase, s.t = "pop", 0.0
    unfreeze(s)
    pancake_off(s)
    cloth_follow_copy(s)
end

-- each frame, after the platforms are drawn
function M.tick(dt)
    local s = st
    if not s then return end
    local pawn = lib.pawn()
    if not pawn or pawn:GetAddress() ~= s.addr then st = nil; dump(s); return end
    s.t, s.age, s.frame = s.t + dt, s.age + dt, s.frame + 1
    local HP, G = _G.HEALTH, game()
    local dead = (HP and HP.dead_t) or (G and G.dying)
    -- (died flat under it, and the death warp has been: himself again wherever he starts)
    if dead then s.died = true elseif s.died then M.stop(); return end
    local bz = nil
    pcall(function() bz = s.bottom() end)
    -- (squeezed up into a ceiling by what he stands on: his feet go with it - never past the ceiling - and the pancake)
    if s.floor_fn and not s.free then
        local f = nil
        pcall(function() f = s.floor_fn() end)
        -- (and along with it, if it goes sideways: the Spindel rolling on, a hopping Grindel)
        local dx, dy = nil, nil
        if s.shift_fn then pcall(function() dx, dy = s.shift_fn() end) end
        if f then
            if bz and f > bz - 0.5 then f = bz - 0.5 end
            local nx, ny = dx and s.x0 + dx or s.x, dy and s.y0 + dy or s.y
            if math.abs(f - s.feet) > 0.01 or math.abs(nx - s.x) > 0.01 or math.abs(ny - s.y) > 0.01 then
                s.feet, s.zc, s.x, s.y = f, f + HALF, nx, ny
                if s.pancake then
                    pcall(function() s.pancake:K2_SetActorLocation({ X = s.x, Y = s.y, Z = f + 0.5 }, false, {}, true) end)
                end
            end
        end
    end
    local gap = bz and (bz - s.feet) or 1.0e9
    note(s, pawn, gap)
    if s.phase == "down" and s.floor_fn and gap > ROOM and s.t > 0.2 then
        -- (room again before he was flat - it stopped short of the ceiling and went down: act_squished's state 0, with
        -- room for him he is himself again, unhurt)
        to_pop(s)
    elseif s.phase == "down" then
        -- (pressed from below he stays as squeezed as the room leaves him, as Mario 64's does; pressed from above he is
        -- flat within a second)
        if gap <= FLAT_AT or (s.t > 1.0 and not s.floor_fn) then
            s.phase, s.t = "flat", 0.0
            shape(s, FLAT_XY, FLAT_Z)
            pancake_on(s)
            hurt(s)
        else
            local z = math.max(FLAT_Z, math.min(1.0, gap / HEIGHT))
            shape(s, math.min(FLAT_XY, 2.0 - z), z)
        end
        hold(s)
    elseif s.phase == "flat" then
        -- (squeezed on something that carries him on under a ceiling that never leaves him room - the Spindel rolling
        -- on under the pyramid corridor's ceiling: flat a moment, then put down off it, still flat, and up again there.
        -- He rode it flat for ten seconds: "got stuck in rolling thwomp", 2026-10-23)
        if s.out and s.t >= OUT_AFTER and not dead then
            local x, y, f = nil, nil, nil
            pcall(function() x, y, f = s.out() end)
            s.out = nil
            if x and y and f then
                s.x, s.y, s.feet, s.zc = x, y, f, f + HALF
                s.floor_fn, s.shift_fn = nil, nil
                s.bottom = function() return 1.0e9 end
                gap = 1.0e9
                if s.pancake then
                    pcall(function() s.pancake:K2_SetActorLocation({ X = x, Y = y, Z = f + 0.5 }, false, {}, true) end)
                end
                lib.log("squish: put down off %s", s.what)
            end
        end
        shape(s, FLAT_XY, FLAT_Z)
        hold(s)
        if gap >= LIFTED then s.phase, s.t = "wait", 0.0 end
    elseif s.phase == "wait" then
        shape(s, FLAT_XY, FLAT_Z)
        hold(s)
        if s.t >= WAIT and not dead then to_pop(s) end
    else
        -- pop: squat a moment, then the wobble (Mario 64's table, 30 a second, blended between its steps). His shirt and
        -- trousers only take an even scale, so the whole of him goes evenly: Mario 64's height, softened (its root)
        local xy, z
        if s.t < SQUAT then
            xy, z = 1.0, 0.4
        else
            local k = (s.t - SQUAT) * 30.0
            if k >= #POP then
                if s.free then
                    unshape(s)
                    st = nil
                    dump(s)
                    return
                end
                xy, z = 1.0, 1.0
            else
                local i = math.floor(k)
                local a, b = POP[i + 1], POP[i + 2] or 0
                local v = a + (b - a) * (k - i)
                xy, z = 1.0, 1.0 - v * 0.006
            end
        end
        local u = math.sqrt(z)
        shape(s, u, u)
        if not s.free then
            if gap >= (s.floor_fn and ROOM or CLEAR) or s.age > LONGEST then release(s) else hold(s) end
        end
    end
    -- (too long under it: let go, and the Thwomp's own check puts him out from under it)
    if s.age > LONGEST and not s.free and not dead and s.phase ~= "pop" then to_pop(s) end
    -- (pause.lua's unfreeze gives the controls back)
    if s.locked and s.frame % 10 == 0 then pcall(function() s.pawn:DisableInput(lib.controller()) end) end
end

return M
