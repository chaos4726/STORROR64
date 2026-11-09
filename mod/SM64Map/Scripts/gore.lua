-- HUMAN MODE's gruesome death, its gore (game.lua G.gruesome_death): "on hit I want the hands arms head legs and feet
-- to fall off, and I want blood to come from each part", 2026-11-03.
--
-- Each part that comes off is a copy of him - a PoseableMeshComponent of his body, copies of his head, shoes and clothes
-- led by it - with everything but that part shrunk to nothing into its cut (his skeleton's root scaled to a thousandth
-- and put at the joint, the part set back where it was; the part below it - the arm's hand, the leg's foot - shrunk into
-- its own cut), riding a physics box of its size, thrown off him. (Hidden bones would not do: his clothes ignore a bone
-- hidden on his body, his sleeves stayed; they follow a bone shrunk.) His own body is drawn as one more such copy, posed
-- from him every frame with the parts that came off shrunk into their stumps - his body hidden, his head, shoes and
-- clothes led by the copy, as footik.lua does it - and what hangs on his head (Mario's cap and face) goes with the head.
-- Blood: drops from every cut - his five stumps, both ends of each part - in spurts with his heartbeat, fading over some
-- seconds, landing in pools that spread under them; a wound on each cut.
-- All of it put back (M.clear) as the screen has closed on him: game.lua's death_warp.
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET
local M = {}
M.VERSION = 19                -- (which copy is loaded: a dev-channel reload checks it)

local IDENT = { Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = 0.0, Y = 0.0, Z = 0.0 }, Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }
local EPS = { X = 0.001, Y = 0.001, Z = 0.001 }
local POSEABLE = "/Script/Engine.PoseableMeshComponent"
local SKEL = "/Script/Engine.SkeletalMeshComponent"
local CLOTH = "/Script/ChaosClothAssetEngine.ChaosClothComponent"
local sqrt, sin, pi, random, min, max = math.sqrt, math.sin, math.pi, math.random, math.min, math.max

-- The parts. root: its top bone (where it was cut off him); tip: the bone its length runs to (stretch: the length past
-- it, a hand's fingers, a foot's toes); cut: the part below it, shrunk into its lower end; sphere / w: its box's
-- radius or half-width (cm); kg; wear: his meshes it takes copies of (by name: Head the face, TorsoCloth the shirt,
-- LegsCloth the joggers, Feet the shoes - each part only what is on it: every part with copies of all of them, his face
-- nine times, held the game up half a second as he died, "game lags when the player dies", 2026-11-03); ends: its cuts - the bone at each and the way blood leaves it, from -> to, taken on
-- him as it came off.
M.PARTS = {
    -- (a copy of his face mesh, not his body's: `face`)
    -- (its ball as big as his head and set in its middle: at 11 cm, 9 up from the head bone, the head lay sunk in the floor
    -- and went out of sight under it - "the head still goes invisable", "I think the problem may be that the head is to
    -- close to the ground", 2026-11-03)
    { id = "head", root = "neck_01", tip = "head", sphere = 15.0, up = 11.0, kg = 5.0, wear = {}, face = true,
      ends = { { at = "neck_01", from = "head", to = "neck_01", w = 5.0 } } },
}
for _, s in ipairs({ "l", "r" }) do
    local function b(n) return n .. "_" .. s end
    M.PARTS[#M.PARTS + 1] = { id = b("arm"), root = b("upperarm"), tip = b("hand"), cut = b("hand"), w = 5.5, kg = 3.5,
        wear = { "TorsoCloth" },
        ends = { { at = b("upperarm"), from = b("lowerarm"), to = b("upperarm"), w = 5.0 },
                 { at = b("hand"), from = b("lowerarm"), to = b("hand"), w = 3.5 } } }
    M.PARTS[#M.PARTS + 1] = { id = b("hand"), root = b("hand"), tip = b("middle_01"), stretch = 1.8, w = 4.0, kg = 0.6,
        wear = {},
        ends = { { at = b("hand"), from = b("middle_01"), to = b("hand"), w = 3.5 } } }
    M.PARTS[#M.PARTS + 1] = { id = b("leg"), root = b("thigh"), tip = b("foot"), cut = b("foot"), w = 7.5, kg = 9.0,
        wear = { "LegsCloth" },
        ends = { { at = b("thigh"), from = b("calf"), to = b("thigh"), w = 7.0 },
                 { at = b("foot"), from = b("calf"), to = b("foot"), w = 4.0 } } }
    M.PARTS[#M.PARTS + 1] = { id = b("foot"), root = b("foot"), tip = b("ball"), stretch = 1.6, w = 5.0, kg = 1.2,
        wear = { "Feet" },
        ends = { { at = b("foot"), from = b("foot"), to = b("calf"), w = 4.0 } } }
end
-- his stumps: the bone shrunk on his copy, and the way blood leaves it (from its parent)
M.STUMPS = {
    { at = "neck_01", from = "spine_05", w = 6.0 },
    { at = "upperarm_l", from = "clavicle_l", w = 5.5 }, { at = "upperarm_r", from = "clavicle_r", w = 5.5 },
    { at = "thigh_l", from = "pelvis", w = 7.5 }, { at = "thigh_r", from = "pelvis", w = 7.5 },
}
-- how the parts leave him: out from his chest, up, turning (cm/s, degrees/s) - on top of how he was moving
M.FLING = { out = 230.0, up = 170.0, spin = 420.0 }
-- the blood. rate: drops a second at a stump / at a part's cut, at the height of a beat; beat: beats a second; life: s
-- it lasts, fading; burst: drops at once as it comes off; speed: cm/s out of the cut (stump, part); spread: cm/s every
-- way; size: a drop's half-size, cm; pool: the most a pool under a stump / a part spreads (cm); max: drops at once
-- (`max` drops and `pools` made ahead, `prewarm` a frame, while HUMAN MODE is on: made as he died, they held the game up)
-- (more of it, rushing out and painting the ground: "I want more blood as well, I want blood to rush out the limbs and
-- paint the ground", 2026-11-03 - a stronger jet that lasts longer, a low beat that never stops it, pools grown wide)
M.BLOOD = { rate = 42.0, end_rate = 16.0, beat = 1.4, low = 0.45, life = 6.5, burst = 22, speed = { 300.0, 190.0 },
            spread = 60.0, size = { 2.6, 5.2 }, gravity = 980.0, max = 170, pools = 0, prewarm = 3,
            -- (each drop leaves a splat where it lands, on the ground there - not a pool that fills: "can you make the
            -- blood drops land correctly? more like painting the ground not just 1 pool that fills", 2026-11-03. A
            -- splat: `splat` times the drop's size, drawn out the way it was going by `stretch` per cm/s of it, at most
            -- `long`; laid on in batches every `every` s, `secs` batches at most)
            splat = { 2.2, 3.6 }, stretch = 1.0 / 260.0, long = 2.6, every = 0.1, secs = 120, batch = 28 }

local st = nil              -- { world, pawn, body, torso, pieces, emitters, t, foot_was }
local drops = nil           -- { world, list = { { actor, on, ... } }, next }
local pools = nil           -- { world, list = { { actor, on, x, y, z, r, max } } }

local function here() local w = lib.world(); return w and w:GetAddress() end
local function comps(actor, path)
    local out = {}
    pcall(function()
        local cls = StaticFindObject(path)
        if not (cls and cls:IsValid()) then return end
        for _, c in ipairs(actor:K2_GetComponentsByClass(cls)) do out[#out + 1] = c:get() end
    end)
    return out
end
local function at(c, bone) local p = c:GetSocketLocation(FName(bone)); return { p.X, p.Y, p.Z } end
local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
local function mul(a, k) return { a[1] * k, a[2] * k, a[3] * k } end
local function len(a) return sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3]) end
local function unit(a) local l = len(a); if l < 1e-6 then return { 0.0, 0.0, 1.0 } end; return mul(a, 1.0 / l) end
local function V(a) return { X = a[1], Y = a[2], Z = a[3] } end
local function rnd(a, b) return a + (b - a) * random() end
local function KML() return StaticFindObject("/Script/Engine.Default__KismetMathLibrary") end

-- ------------------------------------------------------------ the meshes of the blood
local WHITE = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
-- (h: half-size; three squares across each other - a blob from any side - or one flat on the floor; both their faces)
local function mesh(h, flat)
    local verts, idx, nrms, uvs, cols = {}, {}, {}, {}, {}
    local corners = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }
    local tc = { { 0, 1 }, { 1, 1 }, { 1, 0 }, { 0, 0 } }
    local function quad(ax, ay, az, bx, by, bz, nx, ny, nz)
        local n = #verts
        for k = 1, 4 do
            local s, t = corners[k][1] * h, corners[k][2] * h
            verts[n + k] = { X = ax * s + bx * t, Y = ay * s + by * t, Z = az * s + bz * t }
            nrms[n + k] = { X = nx, Y = ny, Z = nz }
            uvs[n + k] = { X = tc[k][1], Y = tc[k][2] }
            cols[n + k] = WHITE
        end
        local m = #idx
        idx[m + 1], idx[m + 2], idx[m + 3], idx[m + 4], idx[m + 5], idx[m + 6] = n, n + 1, n + 2, n, n + 2, n + 3
        idx[m + 7], idx[m + 8], idx[m + 9], idx[m + 10], idx[m + 11], idx[m + 12] = n, n + 2, n + 1, n, n + 3, n + 2
    end
    quad(1, 0, 0, 0, 1, 0, 0, 0, 1)
    if not flat then
        quad(1, 0, 0, 0, 0, 1, 0, 1, 0)
        quad(0, 1, 0, 0, 0, 1, 1, 0, 0)
    end
    return verts, idx, nrms, uvs, cols
end
local function section(world, pmc, h, flat, tex)
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    local v, i, n, u, c = mesh(h, flat)
    lib.create_section(pmc, 0, v, i, n, u, c, false)
    -- (cut out, not see-through: through the see-through material the red came out brown, 2026-11-03)
    local mid = lib.get_mid(world, "alpha", tex)
    if mid then pcall(function() pmc:SetMaterial(0, mid) end) end
end
-- an actor of the blood's (a drop, a pool): kept, hidden, between deaths - a scene's sweep leaves it
local function sprite(world, flat, tex)
    local a = lib.spawn_actor(world, OFFSET, 0.0)
    if not a then return nil end
    pcall(function() a:SetActorEnableCollision(false) end)
    local pmc = lib.add_pmc(a)
    if not pmc then pcall(lib.destroy, a); return nil end
    section(world, pmc, 1.0, flat, tex)
    pcall(function() a:SetActorHiddenInGame(true) end)
    lib.keep[a:GetAddress()] = "gore"
    return a
end
-- a wound on a cut: on `pose`'s bone, part of the actor `a`
local function wound(world, a, pose, bone, h)
    local pmc = lib.add_pmc(a)
    if not pmc then return end
    section(world, pmc, h, false, "gore_blood_cut")
    pcall(function() pmc:K2_AttachToComponent(pose, FName(bone), 2, 2, 2, false) end)
end

-- ------------------------------------------------------------ his own copy, the parts gone from it
local function copy_mats(dst, src)
    pcall(function()
        for i = 0, src:GetNumMaterials() - 1 do
            local m = src:GetMaterial(i)
            if m and m:IsValid() then dst:SetMaterial(i, m) end
        end
    end)
end
-- his meshes named in `wear` (his face, shoes, clothes), copied onto `a`, led by `pose` (a part's copy):
-- { { c, name } } - placed and dressed as his own at the death (dress_followers)
local function make_followers(a, pawn, pose, wear)
    local out = {}
    local want = {}
    for _, n in ipairs(wear or {}) do want[n] = true end
    if not next(want) then return out end
    for _, src in ipairs(comps(pawn, SKEL)) do
        local n = src:GetFName():ToString()
        if want[n] then pcall(function()
            local c = a:AddComponentByClass(StaticFindObject(SKEL), true, IDENT, false)
            c:SetSkinnedAssetAndUpdate(src:GetSkinnedAsset(), true)
            c:K2_AttachToComponent(pose, FName("None"), 0, 0, 0, false)
            pcall(function() c:SetCollisionEnabled(0) end)
            c:SetLeaderPoseComponent(pose, true, false)
            pcall(function() c.VisibilityBasedAnimTickOption = 0 end)
            pcall(function() c:SetForcedLOD(1) end)
            pcall(function() c.bComponentUseFixedSkelBounds = true end)
            pcall(function() c:SetBoundsScale(1.5) end)
            out[#out + 1] = { c = c, name = n }
        end) end
    end
    local ccls = StaticFindObject(CLOTH)
    if not (ccls and ccls:IsValid()) then return out end
    for _, src in ipairs(comps(pawn, CLOTH)) do
        local n = src:GetFName():ToString()
        if want[n] then pcall(function()
            local asset = src:GetAsset()
            if not (asset and asset:IsValid()) then return end
            local c = a:AddComponentByClass(ccls, true, IDENT, false)
            c:SetAsset(asset)
            c:K2_AttachToComponent(pose, FName("None"), 0, 0, 0, false)
            c:SetLeaderPoseComponent(pose, true, false)
            pcall(function() c:SetEnableSimulation(false) end)
            pcall(function() c:SetBoundsScale(1.5) end)
            out[#out + 1] = { c = c, name = n }
        end) end
    end
    return out
end
local function dress_followers(pawn, list)
    if #list == 0 then return end
    local by = {}
    for _, src in ipairs(comps(pawn, SKEL)) do by[src:GetFName():ToString()] = src end
    for _, src in ipairs(comps(pawn, CLOTH)) do by[src:GetFName():ToString()] = src end
    for _, f in ipairs(list) do
        local src = by[f.name]
        if src then pcall(function()
            f.c:K2_SetWorldTransform(src:K2_GetComponentToWorld(), false, {}, true)
            copy_mats(f.c, src)
        end) end
    end
end

-- what hangs on his head (Mario's cap and face, a flashlight): onto `to`'s head, or back onto his body
local function carry(s, to)
    if to then
        s.carried = {}
        local kids = {}
        pcall(function() s.body:GetChildrenComponents(false, kids) end)
        for _, c in ipairs(kids) do
            pcall(function()
                local o = c.get and c:get() or c
                if not (o and o:IsValid()) then return end
                local sock = o:GetAttachSocketName():ToString()
                if sock:lower() == "head" then
                    o:K2_AttachToComponent(to, FName(sock), 0, 0, 0, false)
                    s.carried[#s.carried + 1] = { o = o, sock = sock }
                end
            end)
        end
    else
        for _, e in ipairs(s.carried or {}) do
            pcall(function() if e.o:IsValid() then e.o:K2_AttachToComponent(s.body, FName(e.sock), 0, 0, 0, false) end end)
        end
        s.carried = nil
    end
end

-- The copies are made ahead, hidden, a few frames apart while HUMAN MODE is on (M.tick: prep_step) - made as he died,
-- all of them in that one frame, they held the game up: "still a pretty big lag spike optimize it", 2026-11-03 (115 ms
-- after the copies of his face and clothes were cut to what each part shows). At the death each is only put where he
-- is, dressed as he is, posed, shown and thrown (fire_*), and after it put away again, hidden, for the next (reset_*).
-- His clothes changed since (the outfits' names: sig_of), they are made again.

-- his face mesh ("Head"), or his body if he has none
local function face_of(pawn)
    for _, c in ipairs(comps(pawn, SKEL)) do if c:GetFName():ToString() == "Head" then return c end end
    return pawn.Mesh
end

-- one part, ready: its box (no collision, no physics yet), the copy on it, his clothes on that, a wound on each cut
local function prep_part(world, pawn, body, P)
    local a = lib.spawn_actor(world, body:K2_GetComponentLocation(), 0.0)
    if not a then return nil end
    -- (left by a scene's sweep: only this script takes it away - swept with the level he died in, then touched, it
    -- crashed the game, 2026-11-03 00:58)
    lib.keep[a:GetAddress()] = "gore"
    pcall(function() a:SetActorHiddenInGame(true) end)
    local part = { actor = a, P = P }
    local ok, err = pcall(function()
        local box = a:AddComponentByClass(StaticFindObject(P.sphere and "/Script/Engine.SphereComponent"
            or "/Script/Engine.BoxComponent"), true, IDENT, false)
        box:K2_AttachToComponent(a.RootComponent, FName("None"), 2, 2, 2, false)
        box:SetCollisionProfileName(FName("PhysicsActor"), true)
        for _, ch in ipairs({ 2, 4, 5 }) do pcall(function() box:SetCollisionResponseToChannel(ch, 0) end) end   -- (him, the camera, each other)
        pcall(function() box:SetUseCCD(true, FName("None")) end)
        pcall(function() box:SetLinearDamping(0.1) end)
        pcall(function() box:SetAngularDamping(1.2) end)
        box:SetCollisionEnabled(0)
        part.box = box
        local pose = a:AddComponentByClass(StaticFindObject(POSEABLE), true, IDENT, false)
        -- (the head: a copy of his face mesh - its own bones, his face's - not of his body led onto it: led, a face's
        -- own bones stand where they rest, and its skin and hair came away, 2026-11-03)
        local src = P.face and face_of(pawn) or body
        pose:SetSkinnedAssetAndUpdate(src:GetSkinnedAsset(), true)
        pose:K2_AttachToComponent(box, FName("None"), 0, 0, 0, false)
        pcall(function() pose:SetCastShadow(true) end)
        -- (drawn in full: all but the part shrunk to nothing, the copy looks tiny to the engine, which drew it - and his
        -- face led by it - at its plainest, his face without its skin: "the head keeps losing its skin", 2026-11-03)
        pcall(function() pose:SetForcedLOD(1) end)
        -- (seen by the mesh's own bounds, not ones worked out from its bones: all but the part shrunk to a point at its
        -- cut, those were tiny and off where the part is, and as the camera turned the engine stopped drawing it - the
        -- flying head's skin gone, its hair still there: "heads skin still flickers", 2026-11-03)
        pcall(function() pose.bComponentUseFixedSkelBounds = true end)
        pcall(function() pose:SetBoundsScale(1.5) end)
        part.pose = pose
        part.follow = make_followers(a, pawn, pose, P.wear)
        for _, E in ipairs(P.ends) do wound(world, a, pose, E.at, E.w) end
    end)
    if not ok then
        log("gore: the %s's copy could not be made: %s", P.id, tostring(err))
        pcall(function() lib.keep[a:GetAddress()] = nil end)
        pcall(lib.destroy, a)
        return nil
    end
    part.ready = true
    return part
end

-- one part off him: put where it is on him, dressed and posed as he is, all of him but it shrunk into its cut, thrown
local function fire_part(world, pawn, body, part, base_v, chest)
    local P = part.P
    local p0 = at(body, P.root)
    local p1 = at(body, P.tip)
    local center, xdir, half
    if P.sphere then
        center = add(p1, mul(unit(sub(p1, p0)), P.up))
    else
        local d = sub(p1, p0)
        half = len(d) * (P.stretch or 1.0) / 2.0
        xdir = unit(d)
        center = add(p0, mul(xdir, half))
    end
    local box, pose = part.box, part.pose
    if P.sphere then
        box:SetSphereRadius(P.sphere, false)
        box:K2_SetWorldLocationAndRotation(V(center), { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }, false, {}, true)
    else
        box:SetBoxExtent({ X = half, Y = P.w, Z = P.w }, false)
        box:K2_SetWorldLocationAndRotation(V(center), KML():MakeRotFromX(V(xdir)), false, {}, true)
    end
    local src = P.face and face_of(pawn) or body
    pose:K2_SetWorldTransform(src:K2_GetComponentToWorld(), false, {}, true)
    copy_mats(pose, src)
    dress_followers(pawn, part.follow)
    -- (posed from his body, always: STORROR animates his body and his face mesh only follows it as it is drawn - its own
    -- pose is where it rests, and the head copied from it flew a body's length off its ball: "its like its attached to a
    -- ball but also from 10ft away", 2026-11-03. Copied by the bones' names onto the face's copy, his face's own bones
    -- keep where they sit on his head.)
    pose:CopyPoseFromSkeletalComponent(body)
    local tp = pose:GetBoneTransformByName(FName(P.root), 0)
    local root = pose:GetBoneName(0)
    pose:SetBoneScaleByName(root, EPS, 1)
    pose:SetBoneLocationByName(root, tp.Translation, 0)
    pose:SetBoneTransformByName(FName(P.root), tp, 0)
    if P.cut then pose:SetBoneScaleByName(FName(P.cut), EPS, 1) end
    -- its cuts: the way its blood leaves each, kept in the box's own frame
    part.ends = {}
    local bt = box:K2_GetComponentToWorld()
    for _, E in ipairs(P.ends) do
        local d = unit(sub(at(body, E.to), at(body, E.from)))
        local dl = KML():InverseTransformDirection(bt, V(d))
        part.ends[#part.ends + 1] = { bone = E.at, dl = { dl.X, dl.Y, dl.Z }, w = E.w }
    end
    pcall(function() part.actor:SetActorHiddenInGame(false) end)
    -- thrown off him
    box:SetCollisionEnabled(3)
    box:SetSimulatePhysics(true)
    pcall(function() box:SetMassOverrideInKg(FName("None"), P.kg, true) end)
    local out = unit(sub(center, chest))
    local F = M.FLING
    local v = add(base_v, add(mul(out, F.out * rnd(0.7, 1.2)), { rnd(-40, 40), rnd(-40, 40), F.up * rnd(0.6, 1.2) }))
    box:SetPhysicsLinearVelocity(V(v), false, FName("None"))
    box:SetPhysicsAngularVelocityInDegrees({ X = rnd(-F.spin, F.spin), Y = rnd(-F.spin, F.spin), Z = rnd(-F.spin, F.spin) }, false, FName("None"))
    part.ready = false
end

-- put away again, hidden, its box back on its actor, for the next death
local function reset_part(part)
    pcall(function() part.box:SetSimulatePhysics(false) end)
    pcall(function() part.box:SetCollisionEnabled(0) end)
    pcall(function() part.box:K2_AttachToComponent(part.actor.RootComponent, FName("None"), 1, 1, 1, false) end)
    pcall(function() part.actor:SetActorHiddenInGame(true) end)
    part.ready = true
end

-- his own body drawn as a copy, posed from him every frame, the parts gone shrunk into their stumps: ready, hidden,
-- riding his body
local function prep_torso(world, pawn, body)
    local a = lib.spawn_actor(world, body:K2_GetComponentLocation(), 0.0)
    if not a then return nil end
    lib.keep[a:GetAddress()] = "gore"
    pcall(function() a:SetActorHiddenInGame(true) end)
    pcall(function() a:SetActorEnableCollision(false) end)
    local t = { actor = a, cuts = {}, ready = true }
    local ok, err = pcall(function()
        a:K2_AttachToComponent(body, FName("None"), 2, 2, 2, false)
        local pose = a:AddComponentByClass(StaticFindObject(POSEABLE), true, IDENT, false)
        pose:SetSkinnedAssetAndUpdate(body:GetSkinnedAsset(), true)
        pose:K2_AttachToComponent(a.RootComponent, FName("None"), 2, 2, 2, false)
        pcall(function() pose:SetCastShadow(true) end)
        pcall(function() pose:SetForcedLOD(1) end)
        t.pose = pose
        for _, S in ipairs(M.STUMPS) do t.cuts[#t.cuts + 1] = FName(S.at) end
        t.posed = function()
            pose:CopyPoseFromSkeletalComponent(body)
            for _, f in ipairs(t.cuts) do pose:SetBoneScaleByName(f, EPS, 1) end
        end
        for _, S in ipairs(M.STUMPS) do wound(world, a, pose, S.at, S.w) end
    end)
    if not ok then
        log("gore: his body's copy could not be made: %s", tostring(err))
        pcall(function() lib.keep[a:GetAddress()] = nil end)
        pcall(lib.destroy, a)
        return nil
    end
    return t
end
-- His face mesh (the "Head" component, its own skeleton with his face's bones) hidden while its copy flies, and the
-- hair hung on it - hair, brows, beard, mustache (grooms on its FACIAL_C_FacialRoot) - moved onto the copy; all put back
-- after. (His own head led by the part's copy - of his body, which has none of a face's bones - drew its skin and hair
-- where they rest, not on it: "head still disappearing or the skin is", "hair comes off the head", 2026-11-03.)
local GROOM = "/Script/HairStrandsCore.GroomComponent"
local function own_head_off(s, pawn, body, part)
    local head = face_of(pawn)
    if head == body then return end
    s.head = { c = head, hair = {} }
    pcall(function() head:SetVisibility(false, false) end)
    for _, g in ipairs(comps(pawn, GROOM)) do
        pcall(function()
            local sock = g:GetAttachSocketName()
            g:K2_AttachToComponent(part.pose, sock, 0, 0, 0, false)
            s.head.hair[#s.head.hair + 1] = { g = g, sock = sock }
        end)
    end
end
local function own_head_back(s)
    local h = s.head
    s.head = nil
    if not h then return end
    for _, e in ipairs(h.hair) do
        pcall(function() if e.g:IsValid() then e.g:K2_AttachToComponent(h.c, e.sock, 0, 0, 0, false) end end)
    end
    pcall(function() if h.c:IsValid() then h.c:SetVisibility(true, false) end end)
end

local function fire_torso(pawn, body, t, skip)
    copy_mats(t.pose, body)
    pcall(t.posed)
    -- (his hidden body still posed every frame, for the copy)
    pcall(function() t.tick_was = body.VisibilityBasedAnimTickOption; body.VisibilityBasedAnimTickOption = 0 end)
    pcall(function() body:SetVisibility(false, false) end)
    t.follow = {}
    for _, c in ipairs(comps(pawn, SKEL)) do
        local n = c:GetFName():ToString()
        if n ~= "CharacterMesh0" and not (skip and skip[n]) then t.follow[#t.follow + 1] = c end
    end
    for _, c in ipairs(comps(pawn, CLOTH)) do t.follow[#t.follow + 1] = c end
    for _, c in ipairs(t.follow) do pcall(function() c:SetLeaderPoseComponent(t.pose, true, false) end) end
    pcall(function() t.actor:SetActorHiddenInGame(false) end)
    t.ready = false
end
local function reset_torso(t, body)
    for _, c in ipairs(t.follow or {}) do pcall(function() if c:IsValid() then c:SetLeaderPoseComponent(body, true, false) end end) end
    t.follow = nil
    pcall(function()
        if body:IsValid() then
            body:SetVisibility(true, false)
            if t.tick_was ~= nil then body.VisibilityBasedAnimTickOption = t.tick_was end
        end
    end)
    pcall(function() t.actor:SetActorHiddenInGame(true) end)
    t.ready = true
end

-- the copies ready for him: { world, pawn, sig, torso, parts = { [i] = part or false } }
local prep = nil
-- (what he wears, by name: his outfit changed, the copies are made again)
local function sig_of(pawn)
    local t = {}
    pcall(function() t[#t + 1] = pawn.Mesh:GetSkinnedAsset():GetFName():ToString() end)
    for _, c in ipairs(comps(pawn, SKEL)) do pcall(function() t[#t + 1] = c:GetSkinnedAsset():GetFName():ToString() end) end
    for _, c in ipairs(comps(pawn, CLOTH)) do pcall(function() t[#t + 1] = c:GetAsset():GetFName():ToString() end) end
    return table.concat(t, "|")
end
local function prep_drop()
    local p = prep
    prep = nil
    if not (p and p.world == here()) then return end
    local function gone(a)
        if not a then return end
        pcall(function() lib.keep[a:GetAddress()] = nil end)
        pcall(lib.destroy, a)
    end
    if p.torso then
        if not p.torso.ready and p.body then reset_torso(p.torso, p.body) end
        gone(p.torso.actor)
    end
    for _, part in pairs(p.parts) do if part then gone(part.actor) end end
end
-- one copy more made ready (true), or all are (false)
local function prep_step(world, pawn)
    local wa, pa = world:GetAddress(), pawn:GetAddress()
    if not (prep and prep.world == wa and prep.pawn == pa) then
        prep_drop()
        prep = { world = wa, pawn = pa, body = pawn.Mesh, sig = sig_of(pawn), parts = {} }
    end
    if prep.torso == nil then prep.torso = prep_torso(world, pawn, pawn.Mesh) or false; return true end
    for i, P in ipairs(M.PARTS) do
        if prep.parts[i] == nil then prep.parts[i] = prep_part(world, pawn, pawn.Mesh, P) or false; return true end
    end
    return false
end

-- ------------------------------------------------------------ the blood
local function drop_list(world)
    local w = world:GetAddress()
    if not (drops and drops.world == w) then drops = { world = w, list = {}, next = 1 } end
    return drops
end
local function pool_list(world)
    local w = world:GetAddress()
    if not (pools and pools.world == w) then pools = { world = w, list = {} } end
    return pools
end
local function floor_under(x, y, z)
    local G = package.loaded["game"]
    if not (G and G.floor_normal) then return nil end
    local ok, fz = pcall(G.floor_normal, x - OFFSET.X, y - OFFSET.Y, z - OFFSET.Z + 5.0)
    if ok and fz then return fz + OFFSET.Z end
    return nil
end
local function emit(world, e, pos, dir, speed)
    local D = drop_list(world)
    local B = M.BLOOD
    local d = nil
    for i = 1, #D.list do if not D.list[i].on then d = D.list[i]; break end end
    if not d then
        if #D.list < B.max then
            local a = sprite(world, false, "gore_blood_drop")
            if not a then return end
            d = { actor = a }
            D.list[#D.list + 1] = d
        else
            D.next = D.next % #D.list + 1
            d = D.list[D.next]
        end
    end
    local sp = speed * rnd(0.6, 1.15)
    local s = B.spread
    d.on, d.t, d.e = true, 0.0, e
    d.p = { pos[1], pos[2], pos[3] }
    d.v = { dir[1] * sp + rnd(-s, s), dir[2] * sp + rnd(-s, s), dir[3] * sp + rnd(-s, s) }
    d.floor = floor_under(pos[1], pos[2], pos[3])
    local k = rnd(B.size[1], B.size[2])
    d.size, d.ft = k, 0.05
    pcall(function()
        d.actor:SetActorScale3D({ X = k, Y = k, Z = k })
        d.actor:K2_SetActorLocation(V(d.p), false, {}, true)
        d.actor:SetActorHiddenInGame(false)
    end)
end
-- The ground painted: every drop leaves a splat where it lands, flat on the ground there (its slope), drawn out the way
-- it was going - all of them on one mesh of the mod's, a section of splats added every `every` s (hundreds of splats as
-- actors of their own would cost more than the blood). Wiped as the death is over.
local paint = nil               -- { world, actor, pmc, sec, pending, t, n }
-- Four kinds of splat, on one picture two by two (gore_blood_splats.png: make_gore_assets.py splat_atlas) - "can you
-- make 4 different types of blood spatter?", "like streak, and pool and super tiny", 2026-11-03. Each: its size against
-- the drop's (r), how far it is drawn out by the drop's speed along the ground (stretch per cm/s, at most long), and
-- where the drop came down along it (at: its share of the half-length behind the middle).
-- (four across, eight down: `dir` - laid the way the drop was going; then 16 more streaks, each its own: "make like 10 to
-- 20 new ones", "like the streak", 2026-11-03)
M.SPLAT_GRID = { 4, 8 }
M.SPLATS = {
    { name = "impact", r = { 2.2, 3.6 }, stretch = 1.0 / 260.0, long = 2.6, at = 0.18, dir = true },   -- (a blob, its spatter ahead)
    { name = "pool", r = { 3.6, 6.2 }, stretch = 0.0, long = 1.0, at = 0.0 },                           -- (blood run together)
    { name = "streak", r = { 1.6, 2.6 }, stretch = 1.0 / 170.0, long = 4.6, at = 0.5, dir = true },     -- (fast and low)
    { name = "tiny", r = { 0.35, 0.8 }, stretch = 0.0, long = 1.0, at = 0.0 },                          -- (a super tiny drop)
}
for _, n in ipairs({ "long thin", "short fat", "curved", "wavy", "twin", "fan", "forked", "beaded", "splashed head",
                     "into dots", "spiked", "hairline", "brush smear", "s-curve", "three short", "tadpole" }) do
    M.SPLATS[#M.SPLATS + 1] = { name = n, r = { 1.6, 2.8 }, stretch = 1.0 / 190.0, long = 4.2, at = 0.55, dir = true,
                                streak = true }
end
local STREAKS = { 3 }
for i, K in ipairs(M.SPLATS) do if K.streak then STREAKS[#STREAKS + 1] = i end end
-- A pool forming round his body: under his chest, from `r0` to `r1` cm across its half over `grow` s once `start` s in
-- (slowing as it goes), following him while he settles (`follow` s) - "also make a pool form around the body",
-- 2026-11-03. One flat picture of the mod's, made ahead with the drops.
M.BODY_POOL = { start = 0.3, grow = 7.0, r0 = 12.0, r1 = 130.0, follow = 2.0, bone = "spine_03" }
local body_pool = nil           -- { world, actor }
local function body_pool_actor(world)
    local w = world:GetAddress()
    if body_pool and body_pool.world == w then return body_pool.actor end
    local a = sprite(world, true, "gore_blood_pool")
    if not a then return nil end
    body_pool = { world = w, actor = a }
    return a
end
local function body_pool_tick(world, s)
    local BP = M.BODY_POOL
    if not s.torso or s.t < BP.start then return end
    local a = body_pool_actor(world)
    if not a then return end
    local bp = s.bpool
    if not bp then bp = { yaw = rnd(0, 360) }; s.bpool = bp end
    if not bp.z or s.t < BP.follow then
        local okp, p = pcall(function() return s.torso.pose:GetSocketLocation(FName(BP.bone)) end)
        if okp and p then
            local fz = floor_under(p.X, p.Y, p.Z + 20.0)
            if fz then bp.x, bp.y, bp.z = p.X, p.Y, fz + 0.25 end
        end
    end
    if not bp.z then return end
    local k = min(1.0, (s.t - BP.start) / BP.grow)
    k = 1.0 - (1.0 - k) * (1.0 - k)           -- (fast at first, slowing)
    local r = BP.r0 + (BP.r1 - BP.r0) * k
    pcall(function()
        a:K2_SetActorLocationAndRotation({ X = bp.x, Y = bp.y, Z = bp.z }, { Pitch = 0.0, Yaw = bp.yaw, Roll = 0.0 }, false, {}, true)
        a:SetActorScale3D({ X = r, Y = r, Z = 1.0 })
        if not bp.shown then bp.shown = true; a:SetActorHiddenInGame(false) end
    end)
end

-- (how often each: `tiny` of all drops a super tiny one; of the rest, `glob` a big glob - the impact's blob or a pool -
-- whatever its speed, then the fast ones streaks and the slow ones mostly globs: "make it more probable to land on big
-- globs", 2026-11-03 - it was a quarter tiny and the fast all streaks)
M.ODDS = { tiny = 0.15, glob = 0.45, slow_glob = 0.75 }
local GLOBS = { 1, 2 }
local function splat_kind(d, hs)
    local O = M.ODDS
    if random() < O.tiny then return 4 end
    if random() < O.glob then return GLOBS[math.random(#GLOBS)] end
    if hs > 120.0 then return STREAKS[math.random(#STREAKS)] end
    if random() < O.slow_glob then return GLOBS[math.random(#GLOBS)] end
    return STREAKS[math.random(#STREAKS)]
end
local function paint_of(world)
    local w = world:GetAddress()
    if paint and paint.world == w then return paint end
    local a = lib.spawn_actor(world, OFFSET, 0.0)
    if not a then return nil end
    lib.keep[a:GetAddress()] = "gore"
    pcall(function() a:SetActorEnableCollision(false) end)
    local pmc = lib.add_pmc(a)
    if not pmc then pcall(lib.destroy, a); return nil end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    paint = { world = w, actor = a, pmc = pmc, sec = 0, pending = {}, t = 0.0, n = 0 }
    return paint
end
local function landed(world, d)
    local Pt = paint_of(world)
    if not Pt then return end
    local B = M.BLOOD
    -- the ground right there: its height and slope (scene axes)
    local G = package.loaded["game"]
    local z, nx, ny, nz = d.floor, 0.0, 0.0, 1.0
    pcall(function()
        local fz, ax, ay, az = G.floor_normal(d.p[1] - OFFSET.X, d.p[2] - OFFSET.Y, d.p[3] - OFFSET.Z + 20.0)
        if fz then z, nx, ny, nz = fz + OFFSET.Z, ax or 0.0, ay or 0.0, az or 1.0 end
    end)
    if not z then return end
    local hs = sqrt(d.v[1] * d.v[1] + d.v[2] * d.v[2])
    local kind = splat_kind(d, hs)
    local K = M.SPLATS[kind]
    local r = d.size * rnd(K.r[1], K.r[2])
    Pt.n = Pt.n + 1
    Pt.pending[#Pt.pending + 1] = { x = d.p[1], y = d.p[2], z = z + 0.4 + (Pt.n % 50) * 0.02, nx = nx, ny = ny, nz = nz,
        vx = d.v[1], vy = d.v[2], hs = hs, r = r, long = min(K.long, 1.0 + hs * K.stretch), kind = kind, at = K.at }
end
-- the splats waiting laid on as one more section
local function paint_flush(world, force)
    local Pt = paint
    if not (Pt and Pt.world == world:GetAddress()) or #Pt.pending == 0 then return end
    if not force and os.clock() - Pt.t < M.BLOOD.every then return end
    if Pt.sec >= M.BLOOD.secs then Pt.pending = {}; return end
    Pt.t = os.clock()
    local verts, idx, nrms, uvs, cols = {}, {}, {}, {}, {}
    local C = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
    -- (`batch` at a time: the first gush laid on at once held a frame up 22 ms)
    local take, rest = {}, {}
    for i, q in ipairs(Pt.pending) do if i <= M.BLOOD.batch then take[#take + 1] = q else rest[#rest + 1] = q end end
    for _, q in ipairs(take) do
        -- (its way along the ground: the way it was going, laid on the slope - or any way, straight down)
        local ux, uy, uz
        if q.hs > 20.0 and M.SPLATS[q.kind].dir then ux, uy, uz = q.vx / q.hs, q.vy / q.hs, 0.0
        else local a = rnd(0, 2 * pi); ux, uy, uz = math.cos(a), math.sin(a), 0.0 end
        local dt = ux * q.nx + uy * q.ny + uz * q.nz
        ux, uy, uz = ux - q.nx * dt, uy - q.ny * dt, uz - q.nz * dt
        local ul = sqrt(ux * ux + uy * uy + uz * uz)
        if ul < 1e-4 then ux, uy, uz, ul = 1.0, 0.0, 0.0, 1.0 end
        ux, uy, uz = ux / ul, uy / ul, uz / ul
        local vx, vy, vz = q.ny * uz - q.nz * uy, q.nz * ux - q.nx * uz, q.nx * uy - q.ny * ux
        local a, b = q.r * q.long, q.r
        -- (the picture's blob sits left of its middle, its spatter to the right: the quad set on so the blob is where
        -- the drop came down)
        local ox, oy, oz = q.x + ux * a * q.at, q.y + uy * a * q.at, q.z + uz * a * q.at
        -- (its cell of the picture)
        local gx, gy = M.SPLAT_GRID[1], M.SPLAT_GRID[2]
        local cu, cv = ((q.kind - 1) % gx) / gx, math.floor((q.kind - 1) / gx) / gy
        local n = #verts
        local corners = { { -1, -1, 0, 1 }, { 1, -1, 1, 1 }, { 1, 1, 1, 0 }, { -1, 1, 0, 0 } }
        for k = 1, 4 do
            local cs, ct = corners[k][1], corners[k][2]
            verts[n + k] = { X = ox + ux * a * cs + vx * b * ct, Y = oy + uy * a * cs + vy * b * ct, Z = oz + uz * a * cs + vz * b * ct }
            nrms[n + k] = { X = q.nx, Y = q.ny, Z = q.nz }
            uvs[n + k] = { X = cu + corners[k][3] / gx, Y = cv + corners[k][4] / gy }
            cols[n + k] = C
        end
        local m = #idx
        idx[m + 1], idx[m + 2], idx[m + 3], idx[m + 4], idx[m + 5], idx[m + 6] = n, n + 1, n + 2, n, n + 2, n + 3
        idx[m + 7], idx[m + 8], idx[m + 9], idx[m + 10], idx[m + 11], idx[m + 12] = n, n + 2, n + 1, n, n + 3, n + 2
    end
    Pt.pending = rest
    -- (the mesh at the scene's origin: the corners are where they are in the world, less it)
    for _, v in ipairs(verts) do v.X, v.Y, v.Z = v.X - OFFSET.X, v.Y - OFFSET.Y, v.Z - OFFSET.Z end
    local sec = Pt.sec
    Pt.sec = sec + 1
    pcall(function()
        lib.create_section(Pt.pmc, sec, verts, idx, nrms, uvs, cols, false)
        local mid = lib.get_mid(world, "alpha", "gore_blood_splats")
        if mid then Pt.pmc:SetMaterial(sec, mid) end
    end)
end
local function paint_wipe()
    local Pt = paint
    if not (Pt and Pt.world == here()) then return end
    pcall(function() Pt.pmc:ClearAllMeshSections() end)
    Pt.sec, Pt.pending, Pt.n = 0, {}, 0
end
local function drops_tick(world, dt)
    local D = drops
    if not (D and D.world == world:GetAddress()) then return end
    local g = M.BLOOD.gravity
    for _, d in ipairs(D.list) do
        if d.on then
            d.t = d.t + dt
            d.v[3] = d.v[3] - g * dt
            d.p[1], d.p[2], d.p[3] = d.p[1] + d.v[1] * dt, d.p[2] + d.v[2] * dt, d.p[3] + d.v[3] * dt
            -- (the ground under it where it is now, a few times a second - not where it left the cut: it came down
            -- short of slopes and through steps)
            d.ft = (d.ft or 0.0) - dt
            if d.ft <= 0.0 then d.ft = 0.05; d.floor = floor_under(d.p[1], d.p[2], d.p[3] + 15.0) end
            if d.floor and d.p[3] <= d.floor + 0.5 then
                d.on = false
                pcall(function() d.actor:SetActorHiddenInGame(true) end)
                pcall(landed, world, d)
            elseif d.t > 2.5 then
                d.on = false
                pcall(function() d.actor:SetActorHiddenInGame(true) end)
            else
                pcall(function() d.actor:K2_SetActorLocation(V(d.p), false, {}, true) end)
            end
        end
    end
end

-- ------------------------------------------------------------ the death
function M.active() return st ~= nil end

-- `opts.death`: from his death (game.lua) - put back by itself once the death is over, whatever way he comes back
function M.start(pawn, opts)
    if st then return false end
    local world = lib.world()
    pawn = pawn or lib.pawn()
    if not (world and pawn) then return false end
    local body = pawn.Mesh
    if not (body and body:IsValid()) then return false end
    -- (the feet's own copy of him let go first, and kept off: it hands his clothes back to his body as it goes)
    local FT = package.loaded["footik"]
    local foot_was = nil
    if FT then pcall(FT.clear); foot_was = FT.enabled; FT.enabled = false end
    local s = { world = world:GetAddress(), pawn = pawn:GetAddress(), body = body, pieces = {}, emitters = {}, t = 0.0,
                foot_was = foot_was, death = opts and opts.death or false, t0 = os.clock() }
    -- the copies ready - made now what is not (his clothes changed since, or no time to before)
    if prep and prep.world == s.world and prep.pawn == s.pawn and prep.sig ~= sig_of(pawn) then prep_drop() end
    local made = 0
    while prep_step(world, pawn) do made = made + 1 end
    s.made = made
    -- how he was moving, and his chest: what the parts are thrown out from
    local base_v = { 0.0, 0.0, 0.0 }
    pcall(function() local v = pawn:GetVelocity(); base_v = { v.X * 0.6, v.Y * 0.6, v.Z * 0.6 } end)
    local chest = at(body, "spine_03")
    for i in ipairs(M.PARTS) do
        local part = prep.parts[i]
        if part and part.ready then
            local ok, err = pcall(fire_part, world, pawn, body, part, base_v, chest)
            if ok then
                s.pieces[#s.pieces + 1] = part
                if part.P.face then pcall(own_head_off, s, pawn, body, part) end
            else log("gore: the %s did not come off: %s", part.P.id, tostring(err)); reset_part(part) end
        end
    end
    -- his own body without them, Mario's cap and face onto the head that came off
    if prep.torso and prep.torso.ready then
        local okt, errt = pcall(fire_torso, pawn, body, prep.torso, { Head = true })
        if okt then s.torso = prep.torso else log("gore: his body copy failed: %s", tostring(errt)); reset_torso(prep.torso, body) end
    end
    for _, part in ipairs(s.pieces) do
        if part.P.id == "head" and part.pose then pcall(carry, s, part.pose) end
    end
    -- the blood: his stumps, and each part's cuts
    if s.torso then
        for _, S in ipairs(M.STUMPS) do
            s.emitters[#s.emitters + 1] = { stump = true, pose = s.torso.pose, at = FName(S.at), from = FName(S.from),
                                            acc = 0.0, burst = M.BLOOD.burst }
        end
    end
    for _, part in ipairs(s.pieces) do
        for _, E in ipairs(part.ends) do
            s.emitters[#s.emitters + 1] = { part = part, at = FName(E.bone), dl = E.dl, acc = 0.0,
                                            burst = math.floor(M.BLOOD.burst / 2) }
        end
    end
    st = s
    s.cost = { n = 0, sum = 0.0, top = 0.0 }
    log("gore: %d parts off him, %d cuts bleeding (%.0f ms, %d copies made then)", #s.pieces, #s.emitters,
        (os.clock() - s.t0) * 1000.0, made)
    return true
end

-- drops and pools made ahead, `n` a frame, while HUMAN MODE is on and nothing bleeds
local function prewarm(world, n)
    local B = M.BLOOD
    local D, Pl = drop_list(world), pool_list(world)
    if not (body_pool and body_pool.world == world:GetAddress()) then pcall(body_pool_actor, world); return end
    for _ = 1, n do
        if #D.list < B.max then
            local a = sprite(world, false, "gore_blood_drop")
            if not a then return end
            D.list[#D.list + 1] = { actor = a }
        elseif #Pl.list < B.pools then
            local a = sprite(world, true, "gore_blood_pool")
            if not a then return end
            Pl.list[#Pl.list + 1] = { actor = a }
        else
            return
        end
    end
end

M.PREP_EVERY = 0.1             -- (s between the copies made ahead)
local prep_t, sig_t = 0.0, 0.0
local tick_inner
function M.tick(dt)
    local c0 = os.clock()
    tick_inner(dt)
    local s = st
    if s and s.cost then
        local ms = (os.clock() - c0) * 1000.0
        s.cost.n, s.cost.sum, s.cost.top = s.cost.n + 1, s.cost.sum + ms, math.max(s.cost.top, ms)
    end
end
tick_inner = function(dt)
    local s = st
    local world = lib.world()
    if not world then return end
    if not s then
        -- (ahead of a death: only in HUMAN MODE, only in a level - a copy every PREP_EVERY s, then the blood)
        local MN, G = _G.MENU, package.loaded["game"]
        local pawn = lib.pawn()
        local SE = package.loaded["secrets"]
        local gory = (MN and MN.human_on and MN.human_on()) or (SE and SE.gore_any and SE.gore_any())
        if gory and G and G.name and not G.warping and not G.pending and not G.dying
            and pawn then
            prep_t = prep_t + (dt or 0.016)
            sig_t = sig_t + (dt or 0.016)
            if sig_t > 2.0 then
                sig_t = 0.0
                if prep and prep.world == world:GetAddress() and prep.sig ~= sig_of(pawn) then
                    log("gore: his clothes changed - the copies made again")
                    prep_drop()
                end
            end
            if prep_t >= M.PREP_EVERY then
                prep_t = 0.0
                local ok, more = pcall(prep_step, world, pawn)
                if not (ok and more) then pcall(prewarm, world, M.BLOOD.prewarm) end
            end
        end
        if not drops then return end
    end
    dt = min(dt or 0.016, 0.1)
    if s and s.world == world:GetAddress() then
        s.t = s.t + dt
        -- (the death over - he is back, the screen opening on him, or out to the file select: put back. game.lua's
        -- death_warp puts it back first; this is for any other way back - "when the player respawns have the parts come
        -- back", 2026-11-03)
        local HP = _G.HEALTH
        if s.death and s.t > 1.0 and HP and not HP.dead_t then
            M.clear()
            return
        end
        if s.torso then
            pcall(s.torso.posed)
            -- (held: anything that handed his clothes back to his body as it began - footik.lua going off - undone,
            -- once; every half second it was a cost of its own)
            if not s.refollowed and s.t > 0.4 then
                s.refollowed = true
                for _, c in ipairs(s.torso.follow) do pcall(function() c:SetLeaderPoseComponent(s.torso.pose, true, false) end) end
                pcall(function() s.body:SetVisibility(false, false) end)
            end
        end
        -- blood from every cut: spurts with his heartbeat, fading
        local B = M.BLOOD
        local fade = max(0.0, 1.0 - s.t / B.life)
        local beat = sin(s.t * B.beat * 2.0 * pi)
        local pulse = B.low + (1.0 - B.low) * (beat > 0.0 and beat * beat or 0.0)
        for _, e in ipairs(s.emitters) do
            local ok, pos, dir = pcall(function()
                if e.stump then
                    local p = e.pose:GetSocketLocation(e.at)
                    local q = e.pose:GetSocketLocation(e.from)
                    return { p.X, p.Y, p.Z }, unit({ p.X - q.X, p.Y - q.Y, p.Z - q.Z })
                end
                local p = e.part.pose:GetSocketLocation(e.at)
                local d = KML():TransformDirection(e.part.box:K2_GetComponentToWorld(), V(e.dl))
                return { p.X, p.Y, p.Z }, unit({ d.X, d.Y, d.Z })
            end)
            if ok and pos then
                local speed = e.stump and B.speed[1] or B.speed[2]
                if e.burst > 0 then
                    for _ = 1, e.burst do emit(world, e, pos, dir, speed * 1.3) end
                    e.burst = 0
                end
                e.acc = e.acc + (e.stump and B.rate or B.end_rate) * fade * pulse * dt
                while e.acc >= 1.0 do
                    e.acc = e.acc - 1.0
                    emit(world, e, pos, dir, speed * (0.5 + 0.5 * pulse))
                end
            end
        end
    end
    drops_tick(world, dt)
    paint_flush(world, false)
    if s and s.world == world:GetAddress() then pcall(body_pool_tick, world, s) end
    -- (a test from the dev channel: the game's own pictures at its seconds, and all put back at clear_at, then `after`)
    local T = M.test
    if T and s then
        T.done = T.done or {}
        for i, at_t in ipairs(T.shots or {}) do
            if not T.done[i] and s.t >= at_t then
                T.done[i] = true
                pcall(function()
                    StaticFindObject("/Script/Engine.Default__KismetSystemLibrary"):ExecuteConsoleCommand(world,
                        "HighResShot 1092x615", lib.controller())
                end)
            end
        end
        if T.clear_at and s.t >= T.clear_at then
            M.test = nil
            M.clear()
            if T.after then pcall(T.after) end
        end
    end
end

-- put back as the screen has closed on him (game.lua death_warp): his body and clothes his own again, the parts gone,
-- the blood taken up
function M.clear()
    local s = st
    st = nil
    local w = here()
    if s and s.world == w then
        pcall(own_head_back, s)
        if s.torso then reset_torso(s.torso, s.body) end
        pcall(carry, s, nil)
        for _, part in ipairs(s.pieces) do reset_part(part) end
    end
    if s then
        local FT = package.loaded["footik"]
        if FT and s.foot_was ~= nil then FT.enabled = s.foot_was end
        local c = s.cost or { n = 0, sum = 0.0, top = 0.0 }
        log("gore: cleared (its frames: %.1f ms on average, %.1f at most, over %d)", c.n > 0 and c.sum / c.n or 0.0, c.top, c.n)
    end
    if drops and drops.world == w then
        for _, d in ipairs(drops.list) do if d.on then d.on = false; pcall(function() d.actor:SetActorHiddenInGame(true) end) end end
    end
    if pools and pools.world == w then
        for _, p in ipairs(pools.list) do if p.on then p.on = false; pcall(function() p.actor:SetActorHiddenInGame(true) end) end end
    end
    paint_wipe()
    if body_pool and body_pool.world == w then pcall(function() body_pool.actor:SetActorHiddenInGame(true) end) end
end

-- (the map gone: what was kept of it dropped untouched - main.lua's watch on the map)
function M.forget()
    if st then
        local FT = package.loaded["footik"]
        if FT and st.foot_was ~= nil then FT.enabled = st.foot_was end
    end
    st, drops, pools, prep, paint, body_pool = nil, nil, nil, nil, nil, nil
end

function M.debug() return st, drops, pools, prep, paint end

return M
