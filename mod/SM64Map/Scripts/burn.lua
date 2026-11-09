-- SM64Map: burning (2026-10-14, the user: "after getting hit a small jump then you should be forced to sprint only able
-- to steer left or right also a fire texture to be placed at the bottom of the feet so you know your getting burned").
--
-- Mario 64's ACT_BURNING_JUMP and ACT_BURNING_GROUND (mario_actions_airborne.c, mario_actions_moving.c): a hop (31.5
-- up, 8 on), then a run he cannot stop (held at 32 units a frame), turned only by the stick, until the burn timer
-- passes 160 (2 a frame running, 3 in the air: about 2.7 seconds), or water puts it out.
--
-- The athlete: STORROR's own controls are off for it (its locomotion switched off under a name of our own, as the
-- swim does). The hop is set by hand (falling, with its speed); the run is a stretch of straight sprint out of its own motion
-- capture (SKMM_DrewWalkRunSprintAccelDecel, its top-speed stretch, played a quarter faster: ~8.9 m/s), played on
-- his FullBody slot, its root motion carrying him; the stick's left and right turn him. Flames burn at his feet
-- (the flame pictures), and small ones are left behind him, rising.
local lib = require("lib")
local M = {}

local sin, cos, rad, deg, atan, sqrt, max, min, abs = math.sin, math.cos, math.rad, math.deg, math.atan, math.sqrt,
    math.max, math.min, math.abs

local SPRINT = "SKMM_DrewWalkRunSprintAccelDecel"
-- (the top-speed stretch of that take, 7.1 m/s, straight: its fastest; STORROR has no faster run. Played a quarter
-- faster, his legs go as a flat-out sprint does, about 8.9 m/s; 13.3 s on, used at first, still had the end of the
-- speeding up in it and read as a jog: "its not the sprinting state its jogging", 2026-10-14)
local SPRINT_FROM, SPRINT_TO = 14.3, 15.8
local RUN_RATE = 1.25
local TURN = 220.0                  -- degrees a second, stick fully over (Mario 64: 0x600 a frame, ~250)
local HOP_UP, HOP_ON = 520.0, 180.0 -- cm/s (Mario 64's 31.5 up against its gravity of 4: a hop of about 90 cm)
local BURN_END = 160.0              -- Mario 64's burn timer: 2 a frame running, 3 in the air
local HOLD_MAX = 4.0                -- seconds a burn's timer may wait out STORROR's own moves (his jumps) in all
local STICK_DEAD = 0.2
local FOOT_SIZE = 32.0              -- half the height of the flame picture at each foot (cm)
local TRAIL_EVERY = 0.07            -- seconds between the small flames left behind
local TRAIL_MAX = 12
local DRAIN = 10.0                  -- power lost a frame while he burns (Mario 64's)
local BURN_COST = 3 * 256           -- and a burn costs three wedges, no more, no less: relit by more flames while burning,
                                    -- Mario 64's runs on and costs more ("it should be 3 Its doing 4", 2026-10-14)

M.active = false
M.test = nil                        -- (tests: { x = -1..1 } stands in for the stick)
local st = nil
local lv = nil                      -- the lava's flames under him (M.lava): { world, t, feet, trail, trail_t, frame }
local after, storror_move, unstick_if_flying          -- (below)

local function log(fmt, ...) lib.log(fmt, ...) end
local function sfx(name, v) local S = package.loaded["sfx"]; if S and S.play then pcall(S.play, name, v or 1.0) end end
local function hold_sfx(name, v) local S = package.loaded["sfx"]; if S and S.hold then pcall(S.hold, name, v or 1.0) end end
local function wrap(a) return (a + 540.0) % 360.0 - 180.0 end

-- In water enough to put a fire out: swimming, or his feet in water more than 50 units (37.5 cm) deep where he is.
-- Mario 64's act_burning_ground goes out where m->waterLevel - m->floorHeight > 50, and a burning jump or fall into
-- the water plunges him in. Only swimming put it out here, and swimming starts 1.2 m deep: running or hopping into the
-- shallows he burnt on - "cant hop in water when on fire to stop burning", 2026-10-29.
local WATER_DEEP = 50.0 * 0.75
function M.in_water(pawn, loc)
    local G = package.loaded["game"]
    local SW = package.loaded["swim"]
    if (G and G.swim) or (SW and SW.active and SW.active()) then return true end
    if not (G and G.water_at) then return false end
    if not loc then pcall(function() loc = (pawn or lib.pawn()):K2_GetActorLocation() end) end
    if not loc then return false end
    local O = lib.OFFSET
    local x, y, z = loc.X - O.X, loc.Y - O.Y, loc.Z - O.Z
    local top = G.water_at(x, y)
    if not top then return false end
    if G.over_pit and G.over_pit(x, y, z) then return false end      -- (a water box's square out over a drop)
    local feet = z - (G.half or 90.0)
    -- (his feet in it at all: a puddle puts it out too - Mario 64's 50 deep left him burning in the shallows, "when on
    -- fire and jumping into small puddle the fire seems to stay", 2026-10-31)
    return feet <= top - 2.0
end

local function keys(pc, names)
    for _, n in ipairs(names) do
        local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(n) }) end)
        if ok and v then return true end
    end
    return false
end

-- the stick's left and right (or the keys): all he has
local function steer(pc)
    if M.test then return M.test.x or 0.0 end
    local x = 0.0
    pcall(function() x = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftX") }) end)
    if type(x) ~= "number" or abs(x) < STICK_DEAD then x = 0.0 end
    if keys(pc, { "D", "Right" }) then x = 1.0 elseif keys(pc, { "A", "Left" }) then x = -1.0 end
    return x
end

-- STORROR's locomotion takes the stick for walking and turning: off while he burns (as the swim does it)
local function locomotion(pawn, on)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetClass():GetFName():ToString() == "LocomotionComponent" then
                o:EnableLocomotionInputCallback(FName("SM64Burn"), on)
                o:EnableAdvancedLocomotionInput(FName("SM64Burn"), on)
            end
        end
    end)
end

local sprint_seq = nil
local function sprint_anim()
    if sprint_seq then
        local ok, good = pcall(function() return sprint_seq:IsValid() end)
        if ok and good then return sprint_seq end
        sprint_seq = nil
    end
    for _, o in ipairs(FindAllOf("AnimSequence") or {}) do
        local ok, n = pcall(function() return o:GetFName():ToString() end)
        if ok and n == SPRINT then sprint_seq = o; return o end
    end
    return nil
end

local function run_from_start(s, pawn, blend)
    local seq = sprint_anim()
    if not seq then return end
    pcall(function()
        local m = pawn.Mesh:GetAnimInstance():PlaySlotAnimationAsDynamicMontage(seq, FName("FullBody"), blend, 0.3, RUN_RATE, 1,
            -1.0, SPRINT_FROM)
        if m and m:IsValid() then
            s.montages = s.montages or {}
            s.montages[#s.montages + 1] = m
        end
    end)
    s.run_t = 0.0
end

-- ------------------------------------------------------------ the flames on him
local PMC = nil
-- (the small flames left behind are kept and used again, not made and thrown away fourteen a second: actors made and
-- destroyed in numbers came before a crash on a background thread, 2026-10-14; the pool belongs to its world)
local pool = { world = nil, free = {} }
-- (the flames' pictures: Mario 64's red, or its blue - Bowser's blue fire's - for a burn by ice, Snowman's Land's
-- freezing water (Mario 64's lava there): "when burnt by ice the fire should be blue", 2026-10-26)
M.ICE_SCENES = { sl = true }
local function flame_tex(blue, n) return (blue and "flame_sm64_blue_" or "flame_sm64_red_") .. n end
-- RENDER 96's fire (Render96 has no model of it - "need to also make a new fire 3d model, that ties to mario getting burned
-- or running", 2026-10-31): the flames at his feet and the small ones left behind him, while RENDER 96 is on, as fire in
-- the round - tongues of it, round at the foot and pointed at the tip, a tall one in the middle and six round it leaning
-- out, in a picture going white-yellow at the foot through orange and red to clear at the tips (fire3d, fire3d_blue in
-- textures_r96: tools/r96_fire.py) - turning and flickering as it burns. Mario 64's flat flame pictures with it off.
local FIRE3D = nil
local function fire3d_data()
    if FIRE3D then return FIRE3D end
    local pos, uv, col, nrm, idx = {}, {}, {}, {}, {}
    local nv, ni = 0, 0
    local SEG = 8
    local PROF = { { 0.0, 0.4 }, { 0.08, 0.85 }, { 0.22, 1.0 }, { 0.4, 0.86 }, { 0.58, 0.6 }, { 0.76, 0.32 }, { 0.9, 0.12 }, { 1.0, 0.0 } }
    local function tri(a, b, c, fx, fy, fz)
        local ax, ay, az = pos[a * 3 + 1], pos[a * 3 + 2], pos[a * 3 + 3]
        local ux, uy, uz = pos[b * 3 + 1] - ax, pos[b * 3 + 2] - ay, pos[b * 3 + 3] - az
        local wx, wy, wz = pos[c * 3 + 1] - ax, pos[c * 3 + 2] - ay, pos[c * 3 + 3] - az
        local d = (uy * wz - uz * wy) * fx + (uz * wx - ux * wz) * fy + (ux * wy - uy * wx) * fz
        -- (the engine draws a face from the side its (b - a) x (c - a) points away from - a test of both, 2026-10-31:
        -- built the other way the tongues showed their insides)
        if d >= 0 then idx[ni + 1], idx[ni + 2], idx[ni + 3] = a, c, b else idx[ni + 1], idx[ni + 2], idx[ni + 3] = a, b, c end
        ni = ni + 3
    end
    local function vert(x, y, z, u, v, nx, ny, nz)
        pos[nv * 3 + 1], pos[nv * 3 + 2], pos[nv * 3 + 3] = x, y, z
        uv[nv * 2 + 1], uv[nv * 2 + 2] = u, v
        col[nv * 4 + 1], col[nv * 4 + 2], col[nv * 4 + 3], col[nv * 4 + 4] = 1.0, 1.0, 1.0, 1.0
        local l = sqrt(nx * nx + ny * ny + nz * nz)
        nrm[nv * 3 + 1], nrm[nv * 3 + 2], nrm[nv * 3 + 3] = nx / l, ny / l, nz / l
        nv = nv + 1
        return nv - 1
    end
    -- (a tongue: at (cx, cy), h tall, r round, its tip leaning (lx, ly), twisting as it rises)
    local function tongue(cx, cy, h, r, lx, ly, twist, u0)
        local first = nv
        for _, pr in ipairs(PROF) do
            local t, f = pr[1], pr[2]
            local ox, oy = cx + lx * t * t, cy + ly * t * t
            for k = 0, SEG - 1 do
                local a = 2.0 * math.pi * k / SEG + twist * t
                vert(ox + cos(a) * r * f, oy + sin(a) * r * f, t * h, u0 + k / SEG, 1.0 - 0.98 * t, cos(a), sin(a), 0.35)
            end
        end
        for j = 0, #PROF - 2 do
            for k = 0, SEG - 1 do
                local k1 = (k + 1) % SEG
                local a0, a1 = first + j * SEG + k, first + j * SEG + k1
                local b0, b1 = a0 + SEG, a1 + SEG
                local ang = 2.0 * math.pi * (k + 0.5) / SEG + twist * PROF[j + 1][1]
                tri(a0, a1, b1, cos(ang), sin(ang), 0.2)
                tri(a0, b1, b0, cos(ang), sin(ang), 0.2)
            end
        end
        local m = vert(cx, cy, 0.0, u0 + 0.5, 1.0, 0.0, 0.0, -1.0)
        for k = 0, SEG - 1 do tri(m, first + k, first + (k + 1) % SEG, 0.0, 0.0, -1.0) end
    end
    tongue(0.0, 0.0, 1.0, 0.24, 0.0, 0.0, 1.4, 0.0)
    for i = 0, 5 do
        local a = i * math.pi / 3.0 + 0.4
        tongue(cos(a) * 0.19, sin(a) * 0.19, 0.5 + 0.08 * ((i * 3) % 4), 0.16, cos(a) * 0.14, sin(a) * 0.14, -1.0, i * 0.17)
    end
    FIRE3D = { parts = { { name = "p0", parent = -1, off = { 0.0, 0.0, 0.0 }, billboard = false, sections = {
        { id = 0, layer = "translucent", texture = "fire3d", nverts = nv, ntris = ni // 3, pos = pos, uv = uv, col = col, nrm = nrm, idx = idx } } } },
        anims = {}, nbones = 0, cum = 1 }
    return FIRE3D
end
local function fire3d_tex(blue) return blue and "fire3d_blue" or "fire3d" end

-- RENDER 96's fire on everything that shoots it ("make sure everything that shoots fire has the new fire render 96
-- texture", 2026-11-01): the flamethrowers, fire spitters, bouncing fireballs, the Piranha Plants' and Fly Guys' shots,
-- LLL's fire bars, the torches and Bowser's fire. Each draws Mario 64's flat flame picture turned to the camera - on
-- such a flame (`actor`, its picture the first mesh on it, `size` its half-height in cm at scale 1) the fire in the
-- round goes instead: the picture hidden, the fire on the flame's foot, kept upright whichever way the picture is
-- turned, turning and flickering (worn_tick) and growing and shrinking with it. Pictures kept in sets, one shown at a time
-- (a torch's eight), share a `seed`: the fire on each the same, so the swap does not show. Nothing with RENDER 96 off.
local worn = {}
local PMCC = nil
-- (`k`: the fire that much of its usual size - a torch's, enemies.lua add_flame)
function M.fire3d_on(world, actor, size, blue, seed, k)
    if not (lib.R96 and world and actor and size) then return nil end
    PMCC = PMCC or StaticFindObject("/Script/ProceduralMeshComponent.ProceduralMeshComponent")
    local flat = nil
    pcall(function() flat = actor:GetComponentByClass(PMCC) end)
    local pmc = lib.add_pmc(actor)
    if not pmc then return nil end
    local sec = fire3d_data().parts[1].sections[1]
    lib.add_sections(world, pmc, { sec })
    if blue then
        local mid = lib.get_mid(world, "translucent", fire3d_tex(true))
        if mid then pcall(function() pmc:SetMaterial(0, mid) end) end
    end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    -- (its own way up: the picture is turned to the camera, the fire stays standing)
    pcall(function() pmc:SetAbsolute(false, true, false) end)
    pcall(function() pmc:K2_SetRelativeLocation({ X = 0.0, Y = 0.0, Z = -0.75 * size }, false, {}, false) end)
    if flat then pcall(function() flat:SetVisibility(false, false) end) end
    local w = { actor = actor, pmc = pmc, s3 = size * 2.3 * (k or 1.0), seed = seed or math.random() * 6.28, blue = blue and true or false }
    worn[#worn + 1] = w
    return pmc
end
-- (a pooled flame used again in the other colour)
function M.fire3d_color(world, actor, blue)
    blue = blue and true or false
    for _, w in ipairs(worn) do
        if w.actor == actor and w.blue ~= blue then
            w.blue = blue
            local mid = lib.get_mid(world, "translucent", fire3d_tex(blue))
            if mid then pcall(function() w.pmc:SetMaterial(0, mid) end) end
        end
    end
end
-- (one further than this from the camera turned and flickered every third frame, not every one: the basement's
-- thirteen torches made 52 KB of the engine's objects a frame, the collector's passes through them hitches - "why is it
-- so incredibly laggy?", 2026-11-06. Where each is looked up every 30th frame.)
M.FIRE_NEAR = 2500.0
local function worn_tick()
    local t = os.clock()
    -- (one parked in a pool - M.fire3d_park - looked at only every 30th frame, to see it is still there: a fight's pools
    -- came to a hundred flames and more, each looked at three times a frame - "lots of lag during fight", 2026-11-04)
    worn.k = (worn.k or 0) + 1
    local k = worn.k
    local cam = nil
    if k % 30 == 0 then pcall(function() cam = lib.controller().PlayerCameraManager:GetCameraLocation() end) end
    for i = #worn, 1, -1 do
        local w = worn[i]
        if (w.parked and (k + i) % 30 ~= 0) or (w.far and not w.parked and (k + i) % 3 ~= 0) then
            -- (parked, or far)
        else
        local alive, hidden = false, true
        pcall(function()
            alive = w.actor:IsValid() and w.pmc:IsValid()
            if alive then hidden = w.actor.bHidden end
        end)
        if not alive then
            table.remove(worn, i)
        elseif not w.parked and not hidden then
            if cam then
                pcall(function()
                    local p = w.actor:K2_GetActorLocation()
                    w.far = (p.X - cam.X) ^ 2 + (p.Y - cam.Y) ^ 2 + (p.Z - cam.Z) ^ 2 > M.FIRE_NEAR * M.FIRE_NEAR
                end)
            end
            local sd = w.seed
            local fl = 1.0 + 0.14 * sin(t * 19.0 + sd) + 0.07 * sin(t * 31.0 + sd * 2.0)
            local s3 = w.s3
            pcall(function()
                w.pmc:K2_SetWorldRotation({ Pitch = 5.0 * sin(t * 7.0 + sd), Yaw = (t * 150.0 + sd * 57.3) % 360.0,
                                            Roll = 5.0 * cos(t * 9.0 + sd) }, false, {}, false)
                w.pmc:SetRelativeScale3D({ X = s3 * (1.0 + 0.06 * sin(t * 23.0 + sd)), Y = s3 * (1.0 + 0.06 * cos(t * 21.0 + sd)), Z = s3 * fl })
            end)
        end
        end
    end
end
function M.fire3d_count() return #worn end
-- The fire on a flame kept hidden in a pool (bowser_fight's, this file's own): `parked` true as it goes in, false as it
-- comes out - not looked at each frame the while (worn_tick)
function M.fire3d_park(actor, parked)
    for _, w in ipairs(worn) do
        if w.actor == actor then w.parked = parked and true or nil end
    end
end
local function flame(world, x, y, z, size, blue)
    blue = blue and true or false
    local r96 = lib.R96 and true or false
    local here = world:GetAddress()
    if pool.world ~= here then pool.world, pool.free = here, {} end
    for i = #pool.free, 1, -1 do
        local e = pool.free[i]
        if e.size == size and (e.r96 or false) == r96 then
            table.remove(pool.free, i)
            local ok = pcall(function()
                e.actor:K2_TeleportTo({ X = x, Y = y, Z = z }, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
                e.actor:SetActorHiddenInGame(false)
            end)
            pcall(M.fire3d_park, e.actor, false)
            if ok then
                -- (one kept from a burn of the other colour: its picture changed now, not at its next step)
                if (e.blue or false) ~= blue then
                    e.blue = blue
                    pcall(function()
                        local mid = lib.get_mid(world, "translucent", e.r96 and fire3d_tex(blue) or flame_tex(blue, e.anim))
                        if mid and e.pmc then e.pmc:SetMaterial(0, mid) end
                    end)
                end
                return e
            end
        end
    end
    local anim = math.random(0, 7)
    if r96 then
        -- (RENDER 96: the fire in the round, fire3d_data)
        local inst = lib.make_instance(world, fire3d_data(), { X = x, Y = y, Z = z }, 0.0, size * 2.3)
        if not inst then return nil end
        local pmc = inst.comps[1] or nil
        if blue and pmc then
            pcall(function()
                local mid = lib.get_mid(world, "translucent", fire3d_tex(true))
                if mid then pmc:SetMaterial(0, mid) end
            end)
        end
        pcall(function() pmc:SetCastShadow(false) end)
        return { actor = inst.actor, pmc = pmc, anim = anim, size = size, blue = blue, r96 = true, seed = math.random() * 6.28 }
    end
    local a = lib.quad_actor(world, { X = x, Y = y, Z = z }, size, flame_tex(blue, anim), "translucent")
    if not a then return nil end
    PMC = PMC or StaticFindObject("/Script/ProceduralMeshComponent.ProceduralMeshComponent")
    local pmc = nil
    pcall(function() pmc = a:GetComponentByClass(PMC) end)
    return { actor = a, pmc = pmc, anim = anim, size = size, blue = blue }
end

-- its face to the camera, its foot at (x, y, z), its picture moved on every other frame
local function place(world, f, x, y, z, cam, scale, step)
    if f.r96 then
        -- (the fire in the round: standing on its foot, turning, and flickering taller and shorter)
        local t = os.clock()
        local sd = f.seed or 0.0
        local fl = 1.0 + 0.14 * sin(t * 19.0 + sd) + 0.07 * sin(t * 31.0 + sd * 2.0)
        local s3 = f.size * 2.3 * scale
        pcall(function()
            f.actor:K2_TeleportTo({ X = x, Y = y, Z = z - f.size * 0.15 * scale },
                { Pitch = 5.0 * sin(t * 7.0 + sd), Yaw = (t * 150.0 + sd * 57.3) % 360.0, Roll = 5.0 * cos(t * 9.0 + sd) })
            f.actor:SetActorScale3D({ X = s3 * (1.0 + 0.06 * sin(t * 23.0 + sd)), Y = s3 * (1.0 + 0.06 * cos(t * 21.0 + sd)), Z = s3 * fl })
        end)
        return
    end
    if step then
        f.anim = (f.anim + 1) % 8
        pcall(function()
            local mid = lib.get_mid(world, "translucent", flame_tex(f.blue, f.anim))
            if mid and f.pmc then f.pmc:SetMaterial(0, mid) end
        end)
    end
    -- (the flame stands on its foot. Mario 64's own flame pictures, as on Bowser's fire - "the player on fire textures are
    -- wrong", 2026-10-18; the painted fire's foot sat at its bottom edge, at 0.7)
    local cz = z + f.size * scale * 0.6
    local yaw, pitch = 0.0, 0.0
    if cam then
        local dx, dy, dz = cam.X - x, cam.Y - y, cam.Z - cz
        yaw, pitch = deg(atan(dy, dx)) + 180.0, -deg(atan(dz, sqrt(dx * dx + dy * dy)))
    end
    pcall(function()
        f.actor:K2_TeleportTo({ X = x, Y = y, Z = cz }, { Pitch = pitch, Yaw = yaw, Roll = 0.0 })
        f.actor:SetActorScale3D({ X = scale, Y = scale, Z = scale })
    end)
end

-- (the pool emptied, its actors destroyed, when the scene goes: the scene's load sweeps the mod's leftover actors
-- away, and a flame kept in the pool through that was a destroyed actor when the next burn used it - the game crashed
-- twice that way, 2026-10-14)
local function drop_pool()
    local here = nil
    pcall(function() here = lib.world():GetAddress() end)
    if pool.world == here then for _, e in ipairs(pool.free) do lib.destroy(e.actor) end end
    pool.world, pool.free = nil, {}
end

local function give_back(f)
    local here = nil
    pcall(function() here = lib.world():GetAddress() end)
    if pool.world ~= here then return end
    pcall(function() f.actor:SetActorHiddenInGame(true) end)
    pool.free[#pool.free + 1] = f
    pcall(M.fire3d_park, f.actor, true)
end

local function clear_flames(s)
    for _, f in ipairs(s.feet or {}) do give_back(f) end
    for _, f in ipairs(s.trail or {}) do give_back(f) end
    s.feet, s.trail = {}, {}
end

-- ------------------------------------------------------------ on and off
-- Set alight (Bowser's flames); (dx, dy): the way from the flame to him, which he leaps and runs (he would
-- otherwise run on the way he faced, often straight into Bowser). Burnt again while burning: the timer starts over.
function M.start(dx, dy)
    local world, pc, pawn = lib.world(), lib.controller(), lib.pawn()
    if not (world and pc and pawn) then return false end
    if st then
        st.timer = 0.0
        return true
    end
    -- (not set alight while nothing can touch him - a star's dance, a message up, a cannon: game.lua's G.intangible)
    do local G = package.loaded["game"]; if G and G.intangible and G.intangible() then return false end end
    -- (in the water a flame goes out on him: Mario 64's interact_flame, swimming or deep in it)
    if M.in_water(pawn) then sfx("en_flame_blown", 0.8); log("burn: a flame went out on him in the water"); return false end
    local s = { world = world:GetAddress(), pawn = pawn, t = 0.0, timer = 0.0, phase = "hop", trail = {}, feet = {},
                trail_t = 0.0, frame = 0, cost = 0 }
    pcall(function() s.yaw = pawn:K2_GetActorRotation().Yaw end)
    s.yaw = s.yaw or 0.0
    if dx and dy and (dx * dx + dy * dy) > 1.0 then s.yaw = deg(atan(dy, dx)) end
    pcall(function() pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = s.yaw, Roll = 0.0 }, false) end)
    pcall(function() pc:SetIgnoreMoveInput(true) end)
    pcall(function() pawn:DisableInput(pc) end)
    locomotion(pawn, false)
    -- (on the ground, or still going up: the hop; falling already: he falls burning, Mario 64's ACT_BURNING_FALL)
    local mode, vz = 1, 0.0
    pcall(function() mode = pawn.CharacterMovement.MovementMode; vz = pawn:GetVelocity().Z end)
    if mode == 1 or vz > 0.0 then
        -- (STORROR's athlete takes no LaunchCharacter: into the air by hand, falling, with the hop's speed)
        local a = rad(s.yaw)
        pcall(function()
            local cm = pawn.CharacterMovement
            cm:SetMovementMode(3, 0)
            cm.Velocity = { X = cos(a) * HOP_ON, Y = sin(a) * HOP_ON, Z = HOP_UP }
        end)
    else
        s.phase = "fall"
    end
    pcall(function() s.at = pawn:K2_GetActorLocation() end)
    for i = 1, 2 do
        local f = flame(world, 0.0, 0.0, -100000.0, FOOT_SIZE)
        if f then s.feet[#s.feet + 1] = f end
    end
    st = s
    M.active = true
    log("burn: alight (%s)", s.phase)
    return true
end

-- Out: his controls back. `quiet`: a change of scene (or the menus): no sound, and the pool goes too.
local stop_burn
function M.stop(quiet)
    local s = st
    st = nil
    M.active = false
    if s then stop_burn(s) end
    if quiet then drop_pool() end
end
stop_burn = function(s)
    local same = false
    pcall(function() same = lib.world():GetAddress() == s.world end)
    if not same then return end
    local pc, pawn = lib.controller(), lib.pawn()
    clear_flames(s)
    if pawn then
        pcall(function() pawn.Mesh:GetAnimInstance():StopSlotAnimation(0.3, FName("FullBody")) end)
        -- (and each of our sprints by name: StopSlotAnimation passes over one the engine no longer counts as playing,
        -- and a STORROR jump in the middle of the burn can leave ours so - it then ran on to the end of its take,
        -- seconds of running straight: "the bug where you get stuck running forward ... repeatable by catching on
        -- fire then jumping", 2026-10-14)
        pcall(function()
            local ai = pawn.Mesh:GetAnimInstance()
            for _, m in ipairs(s.montages or {}) do
                pcall(function() if m:IsValid() then ai:Montage_Stop(0.3, m) end end)
            end
        end)
        -- (out in the water and swimming: the swim has him in its flying mode, his controls off. Taken for the stuck
        -- flying state, STORROR's reset was called on him and his controls given back, both against the swim. The
        -- move-input switch is a count, so the burn's own is still handed back.)
        -- (Just in, before the swim has taken his controls - or still settling from a plunge - they are his, as on any
        -- way into the water: the swim takes them when it starts.)
        local G, SW = package.loaded["game"], package.loaded["swim"]
        local stroking = (SW and SW.active and SW.active()) and true or false
        if not (stroking or (G and G.swim)) then
            after = { until_t = os.clock() + 3.0, world = s.world, t = 0.0, last = -1.0, stuck = 0.0 }
            unstick_if_flying(pawn, "a burn ended")
        end
        locomotion(pawn, true)
        if pc then
            pcall(function() pc:SetIgnoreMoveInput(false) end)
            if not stroking then pcall(function() pawn:EnableInput(pc) end) end
        end
    end
    log("burn: out")
end

-- The world went: forget it all without touching any of it.
function M.forget() st = nil; M.active = false; pool.world, pool.free = nil, {} end

function M.state() return st end            -- (tests)

-- ------------------------------------------------------------ every frame
after = nil

-- STORROR's own move playing (a jump, a landing, a vault): a montage of its own, not one of ours (AnimMontage_<n>).
-- (Not its fall's, on the ground: caught hanging on a wall and flipped up onto it, he landed with STORROR's fall still
-- playing, the burn waited on it for good and never ran - he stood there on fire, his controls the burn's: "after
-- climbing something on fire the player stops sprinting", 2026-10-29. stale_fall stops it.)
local FALL_MONTAGE = "^MontageFallingInAir"
storror_move = function(pawn)
    local busy = false
    pcall(function()
        local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
        if m and m:IsValid() then
            local n = m:GetFName():ToString()
            if not n:find("^AnimMontage_") and not (n:find(FALL_MONTAGE) and pawn.CharacterMovement.MovementMode == 1) then busy = true end
        end
    end)
    return busy
end

M.RUN_PUSH = 650.0                  -- cm/s: his run on fire when the take will not play (Mario 64's 32 a frame: 720)
-- a function of STORROR's locomotion on him, one taking nothing (ClearClimbAnchor, OnStickCallback): true when called
function M.loco_call(pawn, fname)
    local done = false
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetClass():GetFName():ToString() == "LocomotionComponent" then o[fname](o); done = true end
        end
    end)
    return done
end
-- any take playing or going out on him (STORROR's or ours)
function M.any_montage(pawn)
    local on = false
    pcall(function() on = pawn.Mesh:GetAnimInstance():IsAnyMontagePlaying() and true or false end)
    return on
end
-- his walking speed and root motion as they were before the push changed them (M.walk_back), given back when the push
-- stops - his speed unless something set it since
function M.walk_restore()
    local w = M.walk_back
    M.walk_back = nil
    local pawn = lib.pawn()
    if not (w and pawn) then return end
    local cm = pawn.CharacterMovement
    if math.abs(cm.MaxWalkSpeed - w.set) < 1.0 then cm.MaxWalkSpeed = w.v end
    if w.rm ~= nil then pawn.Mesh:GetAnimInstance().RootMotionMode = w.rm end
    log("burn: his walking speed and root motion given back (%.0f, %s)", w.v, tostring(w.rm))
end
-- the burn's own take playing (a montage made to play it: AnimMontage_...)
function M.sprint_on(pawn)
    local on = false
    pcall(function()
        local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
        on = m ~= nil and m:IsValid() and m:GetFName():ToString():find("^AnimMontage_") ~= nil
    end)
    return on
end

-- STORROR's fall still playing with him on his feet a while (ground_t: seconds on the ground): stopped
local function stale_fall(pawn, ground_t)
    if ground_t < 0.25 then return end
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        local m = ai:GetCurrentActiveMontage()
        if m and m:IsValid() and m:GetFName():ToString():find(FALL_MONTAGE) then
            ai:Montage_Stop(0.2, m)
            log("burn: STORROR's fall was still playing on the ground - stopped")
        end
    end)
end

-- left in STORROR's flying mode (5) with none of its moves playing - the stuck-running state - STORROR's reset
unstick_if_flying = function(pawn, why)
    local stuck = false
    pcall(function() stuck = pawn.CharacterMovement.MovementMode == 5 and not storror_move(pawn) end)
    if not stuck then return end
    local G = package.loaded["game"]
    if G and G.reset_athlete then G.reset_athlete(pawn, why) end
end

-- (a burn's trace in the log, every quarter second while it lasts and 3 s after: what to look at if he is ever
-- stuck running after one again)
local function trace(tag, pawn, pc)
    pcall(function()
        local v = pawn:GetVelocity()
        local m = "-"
        local mm = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
        if mm and mm:IsValid() then m = mm:GetFName():ToString():sub(1, 44) end
        local x = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftX") })
        local y = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftY") })
        log("burn trace %s: mode %s, %.0f cm/s, stick %.1f %.1f, montage %s", tag,
            tostring(pawn.CharacterMovement.MovementMode), sqrt(v.X * v.X + v.Y * v.Y), x or 0, y or 0, m)
    end)
end

-- after a burn: one of our own montages (made on the fly, named AnimMontage_<n>) still playing is stopped, and left in
-- STORROR's flying mode with no move of its own playing he is reset
local function after_burn(dt)
    local a = after
    if not a then return end
    if os.clock() > a.until_t then after = nil; return end
    local world, pc, pawn = lib.world(), lib.controller(), lib.pawn()
    if not (world and pc and pawn) or world:GetAddress() ~= a.world then after = nil; return end
    -- (swimming - put out falling into deep water, the swim starting after: its flying mode and its climb out are the
    -- swim's, not the stuck state, and are left to it)
    local G, SW, WC = package.loaded["game"], package.loaded["swim"], package.loaded["waterclimb"]
    if (G and G.swim) or (SW and SW.active and SW.active()) or (WC and WC.active and WC.active()) then after = nil; return end
    a.t = a.t + (dt or 0.016)
    if a.t - a.last >= 0.25 then a.last = a.t; trace(string.format("after %.2f", a.t), pawn, pc) end
    local walking = false
    pcall(function() walking = pawn.CharacterMovement.MovementMode == 1 end)
    a.ground_t = walking and ((a.ground_t or 0.0) + (dt or 0.016)) or 0.0
    stale_fall(pawn, a.ground_t)
    local flying = false
    pcall(function() flying = pawn.CharacterMovement.MovementMode == 5 and not storror_move(pawn) end)
    a.stuck = flying and (a.stuck + (dt or 0.016)) or 0.0
    if a.stuck > 0.4 then a.stuck = -5.0; unstick_if_flying(pawn, "still in STORROR's flying mode after a burn") end
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        local m = ai:GetCurrentActiveMontage()
        if m and m:IsValid() and m:GetFName():ToString():find("^AnimMontage_") then
            ai:Montage_Stop(0.25, m)
            log("burn: our sprint was still playing after the burn - stopped")
        end
    end)
end

-- Off the lava (Mario 64's ACT_LAVA_BOOST: PARTICLE_FIRE - his flame, at twice its size, under him - all the while he
-- goes up; not in the metal cap): flames under his feet, and small ones left behind, rising, as when he burns - "add the
-- flame texture underneith the players feet if he falls in lava", 2026-10-19. Each leap off it starts them over.
local LAVA_SIZE = FOOT_SIZE * 1.2
local function lava_flames(world)
    lv.feet, lv.flames_done = {}, false
    for i = 1, 2 do
        local f = flame(world, 0.0, 0.0, -100000.0, LAVA_SIZE, lv.blue)
        if f then lv.feet[i] = f end
    end
end
function M.lava()
    local world, pawn = lib.world(), lib.pawn()
    if not (world and pawn) then return end
    local G = package.loaded["game"]
    local blue = (G and M.ICE_SCENES[G.name or ""]) and true or false
    if lv and lv.world == world:GetAddress() then
        lv.t, lv.air_t, lv.blue = 0.0, 0.0, blue
        if lv.flames_done then lava_flames(world) end
        return
    end
    lv = { world = world:GetAddress(), t = 0.0, air_t = 0.0, feet = {}, trail = {}, trail_t = 0.0, frame = 0, blue = blue }
    lava_flames(world)
end
local function lava_flames_out()
    for _, f in pairs(lv.feet) do give_back(f) end
    for _, f in ipairs(lv.trail) do give_back(f) end
    lv.feet, lv.trail, lv.flames_done = {}, {}, true
end
local function lava_end()
    if not lv.flames_done then lava_flames_out() end
    lv = nil
end

-- (and in the air off the lava he is steered: Mario 64's update_lava_boost_or_twirling - the stick, as the camera
-- sees it, speeds him up along it (1 a frame at most) and turns him toward it (1024 a frame at most), no faster than
-- 32 - "when getting burned by lava allow the player to control the direction of travel in the air", 2026-10-19;
-- STORROR's own control in the air hardly moved him. Till he is down again.)
local LAVA_ACCEL, LAVA_TURN, LAVA_TOP = 1.0 * 0.75 * 900.0, 1024.0 / 65536.0 * 360.0 * 30.0, 32.0 * 0.75 * 30.0
local function stick2(pc)
    local x, y = 0.0, 0.0
    pcall(function()
        x = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftX") })
        y = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftY") })
    end)
    if type(x) ~= "number" then x = 0.0 end
    if type(y) ~= "number" then y = 0.0 end
    if keys(pc, { "D", "Right" }) then x = 1.0 elseif keys(pc, { "A", "Left" }) then x = -1.0 end
    if keys(pc, { "W", "Up" }) then y = 1.0 elseif keys(pc, { "S", "Down" }) then y = -1.0 end
    local mag = sqrt(x * x + y * y)
    if mag < STICK_DEAD then return nil end
    return x / mag, y / mag, min(mag, 1.0)
end
local function lava_steer(pawn, pc, dt)
    local HP = _G.HEALTH
    if HP and HP.dead_t then return end
    local sx, sy, mag = stick2(pc)
    if not sx then return end
    local cam = 0.0
    pcall(function() cam = pc.PlayerCameraManager:GetCameraRotation().Yaw end)
    local want = cam + deg(atan(sx, sy))
    pcall(function()
        local cm = pawn.CharacterMovement
        local v = cm.Velocity
        local speed = sqrt(v.X * v.X + v.Y * v.Y)
        local face = (speed > 5.0) and deg(atan(v.Y, v.X)) or pawn:K2_GetActorRotation().Yaw
        local d = rad(wrap(want - face))
        speed = speed + cos(d) * mag * LAVA_ACCEL * dt
        face = face + sin(d) * mag * LAVA_TURN * dt
        if speed < 0.0 then face, speed = face + 180.0, -speed end
        if speed > LAVA_TOP then speed = max(LAVA_TOP, speed - 2.0 * 0.75 * 900.0 * dt) end
        cm.Velocity = { X = cos(rad(face)) * speed, Y = sin(rad(face)) * speed, Z = v.Z }
        pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = face, Roll = 0.0 }, false)
    end)
end

local function lava_tick(dt)
    local world, pawn, pc = lib.world(), lib.pawn(), lib.controller()
    if not (world and pawn) or world:GetAddress() ~= lv.world then lv = nil; return end
    dt = min(dt or 0.016, 0.1)
    lv.t, lv.frame = lv.t + dt, lv.frame + 1
    local vz, mode = 0.0, 1
    pcall(function() vz = pawn:GetVelocity().Z; mode = pawn.CharacterMovement.MovementMode end)
    -- (steered till he is down: off the ground a while first, then on it again)
    if mode == 1 and lv.t > 0.3 then lava_end(); return end
    if lv.t > 4.0 then lava_end(); return end
    -- (a wall met on the way up off the lava: Mario 64 bounces off it - act_lava_boost's mario_bonk_reflection - where
    -- STORROR took it into its wall slide and slid him down it back into the lava, again and again: "still getting stuck
    -- in lava", 2026-10-25. Its wall move stopped, he goes on falling, mirrored off the wall at its speed or more.)
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        local mt = ai:GetCurrentActiveMontage()
        if not (mt and mt:IsValid() and mt:GetFName():ToString():find("Wall", 1, true)) then return end
        ai:Montage_Stop(0.1, mt)
        local G = package.loaded["game"]
        if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
        local cm = pawn.CharacterMovement
        cm:SetMovementMode(3, 0)
        local v = cm.Velocity
        local l = pawn:K2_GetActorLocation()
        local ux, uy = 0.0, 0.0
        if G and G.wall_near then
            local hit, wx, wy = G.wall_near(l.X - lib.OFFSET.X, l.Y - lib.OFFSET.Y, l.Z - lib.OFFSET.Z, 60.0)
            local n = hit and sqrt(wx * wx + wy * wy) or 0.0
            if n > 1e-3 then ux, uy = wx / n, wy / n end
        end
        if ux == 0.0 and uy == 0.0 then
            -- (a wall the scene's data does not have - a platform's: back the way he came)
            local n = sqrt(v.X * v.X + v.Y * v.Y)
            if n > 1.0 then ux, uy = -v.X / n, -v.Y / n else
                local yaw = rad(pawn:K2_GetActorRotation().Yaw)
                ux, uy = -cos(yaw), -sin(yaw)
            end
        end
        local into = v.X * ux + v.Y * uy
        local rx, ry = v.X, v.Y
        if into < 0.0 then rx, ry = v.X - 2.0 * into * ux, v.Y - 2.0 * into * uy end
        local away = rx * ux + ry * uy
        if away < 300.0 then rx, ry = rx + (300.0 - away) * ux, ry + (300.0 - away) * uy end
        cm.Velocity = { X = rx, Y = ry, Z = v.Z }
        pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = deg(atan(ry, rx)), Roll = 0.0 }, false)
        lib.log("lava: off the wall it met on the way up (%s)", mt:GetFName():ToString():sub(1, 30))
    end)
    if pc then lava_steer(pawn, pc, dt) end
    if lv.flames_done then return end
    if (lv.t > 0.3 and vz <= 0.0) or lv.t > 3.0 then lava_flames_out(); return end
    local cam = nil
    pcall(function() cam = pc.PlayerCameraManager:GetCameraLocation() end)
    local step = (lv.frame % 2 == 0)
    local feet = {}
    for i, bone in ipairs({ "foot_l", "foot_r" }) do
        local p = nil
        pcall(function()
            local a = pawn.Mesh:GetSocketLocation(FName(bone))
            local b = pawn.Mesh:GetSocketLocation(FName(i == 1 and "ball_l" or "ball_r"))
            p = { X = (a.X + b.X) * 0.5, Y = (a.Y + b.Y) * 0.5, Z = min(a.Z, b.Z) - 8.0 }
        end)
        feet[i] = p
        local f = lv.feet[i]
        if f and p then place(world, f, p.X, p.Y, p.Z, cam, 1.0 + 0.12 * sin(lv.t * 23.0 + i * 2.0), step) end
    end
    lv.trail_t = lv.trail_t + dt
    if lv.trail_t >= TRAIL_EVERY and #lv.trail < TRAIL_MAX then
        lv.trail_t = 0.0
        local p = feet[math.random(1, 2)]
        if p then
            local f = flame(world, p.X, p.Y, p.Z, FOOT_SIZE * 0.8, lv.blue)
            if f then
                f.x, f.y, f.z, f.age = p.X + (math.random() - 0.5) * 16.0, p.Y + (math.random() - 0.5) * 16.0, p.Z, 0.0
                lv.trail[#lv.trail + 1] = f
            end
        end
    end
    local keep = {}
    for _, f in ipairs(lv.trail) do
        f.age = f.age + dt
        if f.age > 0.45 then
            give_back(f)
        else
            f.z = f.z + 90.0 * dt
            place(world, f, f.x, f.y, f.z, cam, max(0.05, 1.0 - f.age / 0.45), step)
            keep[#keep + 1] = f
        end
    end
    lv.trail = keep
end

function M.tick(dt)
    if #worn > 0 then pcall(worn_tick) end
    if lv then pcall(lava_tick, dt) end
    if not st and after then after_burn(dt) end
    if not st and M.walk_back then pcall(M.walk_restore) end
    local s = st
    if not s then return end
    local world = lib.world()
    if not world or world:GetAddress() ~= s.world then st, M.active = nil, false; return end
    local pc, pawn = lib.controller(), lib.pawn()
    if not (pc and pawn) then M.stop(true); return end
    local G = package.loaded["game"]
    local MN = _G.MENU
    if (G and G.cutscene) or (MN and MN.state ~= "game") then M.stop(true); return end
    dt = min(dt or 0.016, 0.1)
    s.t = s.t + dt
    s.frame = s.frame + 1
    s.trace_t = (s.trace_t or 0.0) + dt
    if s.trace_t >= 0.25 then s.trace_t = 0.0; trace(string.format("%s %.2f", s.phase, s.t), pawn, pc) end
    local loc = nil
    pcall(function() loc = pawn:K2_GetActorLocation() end)
    if not loc then M.stop(true); return end
    -- (moved far at a stroke: a respawn or a door; the burn is over)
    if s.at and ((loc.X - s.at.X) ^ 2 + (loc.Y - s.at.Y) ^ 2 + (loc.Z - s.at.Z) ^ 2) > 600.0 * 600.0 then M.stop(true); return end
    s.at = loc
    -- water puts it out (M.in_water: swimming, or his feet in any water - a puddle too)
    if M.in_water(pawn, loc) then
        sfx("en_flame_blown", 0.8)
        log("burn: put out by the water")
        M.stop()
        return
    end

    local mode = 1
    pcall(function() mode = pawn.CharacterMovement.MovementMode end)
    local grounded = (mode == 1)
    s.ground_t = grounded and ((s.ground_t or 0.0) + dt) or 0.0
    -- (a climb of STORROR's under way - a wall grabbed, climbed up: it ends only through STORROR's locomotion, which the
    -- burn turns off; left off, he stood held still after it, the burn's take stopped each time it began - "player
    -- stands completely still after climbing up something while on fire", 2026-11-07. Its locomotion on again as he
    -- comes off the climb freed him at once)
    if not grounded and not s.climbed then
        pcall(function()
            local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
            if m and m:IsValid() and m:GetFName():ToString():find("Climb") then s.climbed = true end
        end)
    end
    stale_fall(pawn, s.ground_t)
    -- the stick turns him, and that is all (his own controls back - s.free - his way as he goes)
    if s.free then
        pcall(function() s.yaw = pawn:K2_GetActorRotation().Yaw end)
    else
        s.yaw = s.yaw + steer(pc) * TURN * dt
        pcall(function() pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = s.yaw, Roll = 0.0 }, false) end)
    end
    -- (a move of STORROR's own under way - he jumped, falls, lands - the burn's clock waits, up to HOLD_MAX in a burn:
    -- the fire goes on after the jump. Mario 64's clock runs faster in the air, and a jump used up most of the burn:
    -- "the fire has to continue after jumping", 2026-10-14. Its three wedges stay three.)
    local own = storror_move(pawn) or mode == 5 or (s.storror and not grounded)
    local hold = own and (s.held or 0.0) < HOLD_MAX
    if hold then s.held = (s.held or 0.0) + dt end
    if s.phase ~= "run" then
        if not hold then s.timer = s.timer + 3.0 * dt * 30.0 end
        -- (and none of STORROR's takes still going out - a climb up's, as it blends away: cut short by ours, it left him
        -- held still for the rest of the burn - at most 0.6 s on his feet waited for)
        if grounded and s.t > 0.15 and not storror_move(pawn) and (s.ground_t > 0.6 or not M.any_montage(pawn)) then
            s.phase = "run"
            if s.climbed then
                s.climbed = false
                pcall(locomotion, pawn, true)
                log("burn: off a climb - STORROR's locomotion on and its climb anchor let go (%s) for the run",
                    tostring(M.loco_call(pawn, "ClearClimbAnchor")))
            end
            run_from_start(s, pawn, 0.15)
            log("burn: running (%.2f s after it caught)", s.t)
        end
    else
        if not hold then s.timer = s.timer + (grounded and 2.0 or 3.0) * dt * 30.0 end
        s.run_t = (s.run_t or 0.0) + dt
        if storror_move(pawn) or mode == 5 then
            -- (a move of STORROR's own - he jumped: it is let finish. Our sprint started over it cut STORROR's jump
            -- short, which left him in its flying mode, running on after the burn: "the glitch is still happening",
            -- 2026-10-14. Back on the ground, the sprint again.)
            s.storror = true
        -- (his own controls back - below: nothing of ours plays, he runs as STORROR runs him)
        elseif s.free then s.storror = false
        elseif s.storror then
            if grounded then
                s.storror = false
                if s.climbed then
                    s.climbed = false
                    pcall(locomotion, pawn, true)
                    log("burn: off a climb - STORROR's locomotion on and its climb anchor let go (%s) for the run",
                        tostring(M.loco_call(pawn, "ClearClimbAnchor")))
                end
                run_from_start(s, pawn, 0.2)
            end
        -- (the straight stretch of the take, again from its start when it runs out)
        elseif s.run_t > (SPRINT_TO - SPRINT_FROM) / RUN_RATE - 0.2 then run_from_start(s, pawn, 0.2)
        -- (the take stopped under him - STORROR's climb up, ending just after the run began, stops what plays - and
        -- he stood still till the burn was out: "player stands completely still after climbing up something while on
        -- fire", 2026-11-07. On his feet with nothing of ours playing, the take again - a third of a second apart.
        -- Stopped twice, it will not play at all: after a climb up STORROR stops each the moment it starts and holds
        -- him still - neither his speed set nor its root motion off moved him ("still gets stuck") - till he has his
        -- controls again, as at the burn's end. So what the burn took from him is given back a step at a time till
        -- the take plays; at the last he has his controls for the rest of the burn: still alight, flames, the power it
        -- costs and its clock as ever, but run and steered by him.)
        elseif grounded and s.run_t > 0.15 and os.clock() > (s.retry_at or 0.0) and not M.sprint_on(pawn) then
            s.retry_at = os.clock() + 0.3
            run_from_start(s, pawn, 0.1)
            s.no_take = (s.no_take or 0) + 1
            if s.no_take >= 1 and not s.rehop then
                -- (off a climb it will not play - STORROR holds him till the stick moves, and neither its locomotion on,
                -- its climb anchor let go nor its stick callback freed him: "kinda worked I had to push the stick
                -- forward", 2026-11-07 - so the burn's hop again, as when it caught: on landing STORROR is through
                -- with the climb and the take plays, as after any hop)
                s.rehop = true
                local face = rad(s.yaw)
                pcall(function()
                    local cm = pawn.CharacterMovement
                    cm:SetMovementMode(3, 0)
                    cm.Velocity = { X = cos(face) * HOP_ON, Y = sin(face) * HOP_ON, Z = HOP_UP }
                end)
                s.phase, s.ground_t, s.no_take = "hop", 0.0, 0
                log("burn: the run's take will not play off a climb - the hop again, to run on landing")
            elseif s.no_take >= 1 then
                -- (and after that hop still not: his own controls for the rest of the burn)
                s.free = true
                pcall(locomotion, pawn, true)
                pcall(function() pc:SetIgnoreMoveInput(false) end)
                pcall(function() pawn:EnableInput(pc) end)
                log("burn: still no take after the hop - his own controls for the rest of the burn")
            else
                log("burn: the run's take stopped under him - again")
            end
        end
    end
    -- the camera comes round behind him as he turns (his own, with his controls back)
    if not s.free then pcall(function()
        local r = pc:GetControlRotation()
        local k = min(1.0, 5.0 * dt)
        pc:SetControlRotation({ Pitch = r.Pitch, Yaw = r.Yaw + wrap(s.yaw - r.Yaw) * k, Roll = 0.0 })
    end) end
    hold_sfx("loop_fire", 0.9)
    -- the burn drains his power as Mario 64's does: nothing at the touch, 10 a frame while it lasts (health.lua's
    -- own tick sees him out of power: "usually you loose 3 hp from fire right?", 2026-10-14)
    local HP = _G.HEALTH
    if HP and not HP.dead_t and HP.health then
        s.drain = (s.drain or 0.0) + DRAIN * dt * 30.0
        local n = math.min(math.floor(s.drain), BURN_COST - s.cost)
        s.drain = s.drain - math.floor(s.drain)
        if n > 0 then HP.health = HP.health - n; s.cost = s.cost + n end
    end
    -- (the pause gives him his controls back when it shuts: off again)
    if s.frame % 10 == 0 and not s.free then pcall(function() pawn:DisableInput(pc) end) end

    -- the flames: at his feet, and small ones left behind, rising
    local cam = nil
    pcall(function() cam = pc.PlayerCameraManager:GetCameraLocation() end)
    local step = (s.frame % 2 == 0)
    local feet = {}
    for i, bone in ipairs({ "foot_l", "foot_r" }) do
        local p = nil
        pcall(function()
            local a = pawn.Mesh:GetSocketLocation(FName(bone))
            local b = pawn.Mesh:GetSocketLocation(FName(i == 1 and "ball_l" or "ball_r"))
            p = { X = (a.X + b.X) * 0.5, Y = (a.Y + b.Y) * 0.5, Z = min(a.Z, b.Z) - 8.0 }
        end)
        feet[i] = p
        local f = s.feet[i]
        if f and p then place(world, f, p.X, p.Y, p.Z, cam, 1.0 + 0.12 * sin(s.t * 23.0 + i * 2.0), step) end
    end
    s.trail_t = s.trail_t + dt
    if s.trail_t >= TRAIL_EVERY and #s.trail < TRAIL_MAX then
        s.trail_t = 0.0
        local p = feet[math.random(1, 2)]
        if p then
            local f = flame(world, p.X, p.Y, p.Z, FOOT_SIZE * 0.8)
            if f then
                f.x, f.y, f.z, f.age = p.X + (math.random() - 0.5) * 16.0, p.Y + (math.random() - 0.5) * 16.0, p.Z, 0.0
                s.trail[#s.trail + 1] = f
            end
        end
    end
    local keep = {}
    for _, f in ipairs(s.trail) do
        f.age = f.age + dt
        if f.age > 0.45 then
            give_back(f)
        else
            f.z = f.z + 90.0 * dt
            place(world, f, f.x, f.y, f.z, cam, max(0.05, 1.0 - f.age / 0.45), step)
            keep[#keep + 1] = f
        end
    end
    s.trail = keep

    if s.timer > BURN_END then
        -- (burnt out: what is left of its three wedges, all at once)
        local HP = _G.HEALTH
        if HP and not HP.dead_t and HP.health and s.cost < BURN_COST then HP.health = HP.health - (BURN_COST - s.cost) end
        s.cost = BURN_COST
        M.stop()
    end
end

return M
