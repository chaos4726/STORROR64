-- His feet on the ground they stand on (asked 2026-10-15: "his feet are completely flat instead of aligning with the
-- ground"). STORROR's animation Blueprint has foot placement (MetaAnimBP's "Foot IK + Foot Locking" layer: FootPlacement
-- and LegIK nodes, ground traces on the Visibility channel), but no node in its graph calls that layer: the nodes never
-- run (ActualAlpha 0 in play) and his feet always stand as if on flat ground, on a slope and on a stair alike.
--
-- So it is done here. A PoseableMeshComponent copy of his body (on an actor of the mod's, riding his body mesh) takes
-- his animated pose every frame (CopyPoseFromSkeletalComponent); his own body mesh is hidden, and his shoes and trousers
-- (Feet, LegsCloth) follow the copy instead of it. Each foot is then put on the floor under it: the floor height
-- from the level's own collision data (G.floor_z / floor_normal, and moving platforms) - no engine traces - is compared
-- with the floor his animation stands on (his body mesh's origin), the whole body is lowered by what the lower foot
-- needs (his mesh moved in his capsule, as quicksand.lua moves it), and each leg is bent to its foot's spot with a
-- two-bone IK (thigh and calf turned in the plane the knee already bends in), the foot turned to the slope.
-- Only on the ground and walking (movement mode 1) with no montage playing; feet his animation lifts more than ~20 cm
-- are left alone. Off (his own meshes as they were) under the metal and vanish caps (their looks hide and show his
-- meshes themselves) and in cutscenes.
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET
local M = { enabled = true }

local sqrt, abs, max, min = math.sqrt, math.abs, math.max, math.min
local IDENT = { Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = 0.0, Y = 0.0, Z = 0.0 },
                Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }
local WORLD = 0                         -- (EBoneSpaces::WorldSpace)
local LEGS = { { thigh = "thigh_l", calf = "calf_l", foot = "foot_l" }, { thigh = "thigh_r", calf = "calf_r", foot = "foot_r" } }
local MAX_DROP = 40.0                   -- cm the body may be lowered
local MAX_STEP = 45.0                   -- cm a foot may be raised or lowered
local LIFT_FULL, LIFT_NONE = 18.0, 40.0 -- a foot this high over his animation's floor is fully placed .. left alone
local ON_FLOOR = 20.0                   -- his animation's floor within this of the level's floor under him: on it
local SINK_CM = 0.75                    -- cm he is drawn down per unit of quicksand.lua's depth (Mario 64 units)

local st = nil      -- { world, pawn, actor, pose, body, follow = {comps}, on, alpha, drop, shown, base, flip, legs }

-- ------------------------------------------------------------ vectors and quaternions (UE's own conventions)
local function v(x, y, z) return { x, y, z } end
local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
local function mul(a, k) return { a[1] * k, a[2] * k, a[3] * k } end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
local function len(a) return sqrt(dot(a, a)) end
local function norm(a) local l = len(a); if l < 1e-6 then return nil end; return mul(a, 1.0 / l) end
-- (FQuat::FindBetweenNormals)
local function between(a, b)
    local w = 1.0 + dot(a, b)
    local c
    if w < 1e-6 then
        w = 0.0
        c = abs(a[1]) > abs(a[3]) and { -a[2], a[1], 0.0 } or { 0.0, -a[3], a[2] }
    else
        c = cross(a, b)
    end
    local l = sqrt(c[1] * c[1] + c[2] * c[2] + c[3] * c[3] + w * w)
    return { c[1] / l, c[2] / l, c[3] / l, w / l }
end
-- a * b: b first, then a (FQuat operator*)
local function qmul(a, b)
    return { a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2],
             a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
             a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4],
             a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3] }
end
local function qrot(q, p)
    local u = { q[1], q[2], q[3] }
    local t = mul(cross(u, p), 2.0)
    return add(add(p, mul(t, q[4])), cross(u, t))
end
local function qslerp_id(q, a)        -- the identity .. q, a of the way (nlerp: the turns here are small)
    local s = (q[4] < 0.0) and -1.0 or 1.0
    local r = { q[1] * s * a, q[2] * s * a, q[3] * s * a, 1.0 + (q[4] * s - 1.0) * a }
    local l = sqrt(r[1] * r[1] + r[2] * r[2] + r[3] * r[3] + r[4] * r[4])
    return { r[1] / l, r[2] / l, r[3] / l, r[4] / l }
end

-- ------------------------------------------------------------ his bones on the copy
local function bone(pose, name)
    local t = pose:GetBoneTransformByName(FName(name), WORLD)
    return { p = v(t.Translation.X, t.Translation.Y, t.Translation.Z),
             q = { t.Rotation.X, t.Rotation.Y, t.Rotation.Z, t.Rotation.W },
             s = v(t.Scale3D.X, t.Scale3D.Y, t.Scale3D.Z) }
end
local function set_rot(pose, name, b, q)
    pose:SetBoneTransformByName(FName(name), {
        Rotation = { X = q[1], Y = q[2], Z = q[3], W = q[4] },
        Translation = { X = b.p[1], Y = b.p[2], Z = b.p[3] },
        Scale3D = { X = b.s[1], Y = b.s[2], Z = b.s[3] } }, WORLD)
end

-- the level's floor under (x, y) (scene cm, the world's minus OFFSET) at or below zmax, and its normal
local function ground(x, y, zmax)
    local G = package.loaded["game"]
    if not G then return nil end
    local fz, nx, ny, nz
    if G.floor_normal then fz, nx, ny, nz = G.floor_normal(x, y, zmax) end
    if not fz and G.floor_z then fz = G.floor_z(x, y, zmax); nx, ny, nz = 0.0, 0.0, 1.0 end
    local P = G.PLAT
    local pz = P and P.floor_under and P.floor_under(x, y, zmax)
    if pz and (not fz or pz > fz) then fz, nx, ny, nz = pz, 0.0, 0.0, 1.0 end
    if not fz then return nil end
    return fz, { nx, ny, nz }
end

-- ------------------------------------------------------------ the copy, on and off
local function comps_of(pawn, path)
    local out = {}
    pcall(function()
        local cls = StaticFindObject(path)
        if not (cls and cls:IsValid()) then return end
        for _, w in ipairs(pawn:K2_GetComponentsByClass(cls)) do out[#out + 1] = w:get() end
    end)
    return out
end

local function here(s)
    local w = lib.world()
    return w and s and w:GetAddress() == s.world
end

local function copy_materials(s)
    pcall(function()
        for i = 0, s.body:GetNumMaterials() - 1 do
            local m = s.body:GetMaterial(i)
            if m and m:IsValid() then s.pose:SetMaterial(i, m) end
        end
    end)
end

-- (his body mesh moved down by dz in his capsule: its property written, its scale nudged so the engine takes it up)
local function place_body(s, dz)
    s.flip = not s.flip
    local k = s.flip and 1.0001 or 1.0
    pcall(function()
        s.body.RelativeLocation = { X = s.base[1], Y = s.base[2], Z = s.base[3] - dz }
        s.body:SetRelativeScale3D({ X = k, Y = k, Z = k })
    end)
    s.shown = dz
end

local function build(world, pawn)
    local body = pawn.Mesh
    if not (body and body:IsValid()) then return nil end
    local asset = body:GetSkinnedAsset()
    if not (asset and asset:IsValid()) then return nil end
    local a = lib.spawn_actor(world, body:K2_GetComponentLocation(), 0.0)
    if not a then return nil end
    pcall(function() a:SetActorEnableCollision(false) end)
    lib.keep[a:GetAddress()] = "footik"            -- (a scene load's sweep leaves it)
    a:K2_AttachToComponent(body, FName("None"), 2, 2, 2, false)
    local pose = a:AddComponentByClass(StaticFindObject("/Script/Engine.PoseableMeshComponent"), true, IDENT, false)
    if not (pose and pose:IsValid()) then return nil end
    pose:SetSkinnedAssetAndUpdate(asset, true)
    pose:K2_AttachToComponent(a.RootComponent, FName("None"), 2, 2, 2, false)
    pcall(function() pose:SetCastShadow(true) end)
    local s = { world = world:GetAddress(), pawn = pawn:GetAddress(), actor = a, pose = pose, body = body,
                on = false, alpha = 0.0, drop = 0.0, shown = 0.0, flip = false, legs = { 0.0, 0.0 }, mat_t = 0.0 }
    copy_materials(s)
    pcall(function() pose:SetVisibility(false, false) end)
    -- (his face mesh drawn in full, always: led by his body, which this hides and shows, it went down to a plainer
    -- face for moments - its skin flickering: "nah the heads skin still flickers", 2026-11-03)
    for _, c in ipairs(comps_of(pawn, "/Script/Engine.SkinnedMeshComponent")) do
        if c:GetFName():ToString() == "Head" then pcall(function() c:SetForcedLOD(1) end) end
    end
    log("feet: copy of his body made")
    return s
end

local function followers(s, pawn)
    local out = {}
    for _, c in ipairs(comps_of(pawn, "/Script/Engine.SkinnedMeshComponent")) do
        local n = c:GetFName():ToString()
        -- (not his head: led by this copy - or by his body, once handed back - its face's own bones, which no body has,
        -- stood where they rest whatever his head did, and his face's skin and the hair on it (Sacha's) came away from
        -- his head as he stood: "while charaters idle hair comes off the head", "the head keeps losing its skin",
        -- 2026-11-03. Left to STORROR's own animation of it, which follows his body. It was led here for the swim -
        -- "head disconnected from the body", 2026-10-24 - and this copy is no longer held through a swim.)
        if n == "Feet" then out[#out + 1] = c end
    end
    -- (his T-shirt too: it covers his upper arms, and the climb's arms are bent on this copy - left on his own body,
    -- its sleeves kept STORROR's pose while his forearms and hands went where the climb put them: "the arms
    -- disconnect", 2026-10-16)
    for _, c in ipairs(comps_of(pawn, "/Script/ChaosClothAssetEngine.ChaosClothComponent")) do
        local n = c:GetFName():ToString()
        if n == "LegsCloth" or n == "TorsoCloth" then out[#out + 1] = c end
    end
    return out
end

-- What hangs on his head - Mario's cap and face (mariolook.lua), a flashlight - is hung on the copy's head while the
-- copy is drawn, and back on his own after: on his hidden body it kept STORROR's pose of him ("head disconnected from the
-- body", 2026-10-24). `on`: also each half second while it is drawn, for anything hung on him since.
local function carry(s, on)
    -- (no longer: his head is left on his own body - followers - and what hangs on it stays with it there, his face and
    -- Mario's cap moving as one. Hung on this copy's head, the cap came away from his face as this copy came and went:
    -- "also hat is detached from player", 2026-11-03. Anything still hung here is put back.)
    if on then return end
    if on then
        s.carried = s.carried or {}
        local kids = {}
        pcall(function() s.body:GetChildrenComponents(false, kids) end)
        for _, c in ipairs(kids) do
            pcall(function()
                local o = c.get and c:get() or c
                if not (o and o:IsValid()) then return end
                local sock = o:GetAttachSocketName():ToString()
                if sock:lower() == "head" then
                    o:K2_AttachToComponent(s.pose, FName(sock), 0, 0, 0, false)
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

local function engage(s, pawn)
    if s.on then return end
    local l = s.body.RelativeLocation
    s.base, s.shown, s.drop = { l.X, l.Y, l.Z }, 0.0, 0.0
    s.legs = { 0.0, 0.0 }
    pcall(function() s.pose:CopyPoseFromSkeletalComponent(s.body) end)
    copy_materials(s)
    pcall(function() s.pose:SetVisibility(true, false) end)
    pcall(function() s.body:SetVisibility(false, false) end)
    s.follow = followers(s, pawn)
    for _, c in ipairs(s.follow) do pcall(function() c:SetLeaderPoseComponent(s.pose, true, false) end) end
    carry(s, true)
    s.carry_t = 0.0
    s.on = true
    log("feet: on (%d parts follow the copy)", #s.follow)
end

-- Sunk in sand, his body passes through the ground (WorldStatic, WorldDynamic): STORROR's Physics Control simulates
-- his feet, which stood on the sand while the rest of him went down, his knees folded under him - "legs not actually
-- sinking", 2026-10-23. Kept every frame (STORROR puts its own back after some moves), and back to Block (STORROR's)
-- once he is out. Only the body's responses: his capsule still walks on the sand.
local SINK_CHANNELS = { 0, 1 }
local function sink_through(s, on)
    if on then
        s.through = true
        for _, ch in ipairs(SINK_CHANNELS) do
            pcall(function() if s.body:GetCollisionResponseToChannel(ch) ~= 0 then s.body:SetCollisionResponseToChannel(ch, 0) end end)
        end
    elseif s.through then
        s.through = nil
        for _, ch in ipairs(SINK_CHANNELS) do pcall(function() s.body:SetCollisionResponseToChannel(ch, 2) end) end
    end
end

-- back to his own meshes; `show` false leaves his body's visibility to whoever hides it now (the caps)
local function disengage(s, show)
    sink_through(s, false)
    if not s.on then return end
    s.on = false
    if s.shown ~= 0.0 then place_body(s, 0.0) end
    carry(s, false)
    for _, c in ipairs(s.follow or {}) do pcall(function() if c:IsValid() then c:SetLeaderPoseComponent(s.body, true, false) end end) end
    s.follow = nil
    pcall(function() s.pose:SetVisibility(false, false) end)
    if show then pcall(function() s.body:SetVisibility(true, false) end) end
    s.alpha, s.drop, s.legs = 0.0, 0.0, { 0.0, 0.0 }
    log("feet: off")
end

-- ------------------------------------------------------------ the legs
local function leg_ik(pose, L, target_dz, normal, weight, fwd)
    local th, ca, ft = bone(pose, L.thigh), bone(pose, L.calf), bone(pose, L.foot)
    local H, K, A = th.p, ca.p, ft.p
    local T = { A[1], A[2], A[3] + target_dz }
    local l1, l2 = len(sub(K, H)), len(sub(A, K))
    local ht = sub(T, H)
    local d = len(ht)
    local u = norm(ht)
    if not u or l1 < 1.0 or l2 < 1.0 then return end
    d = max(abs(l1 - l2) + 0.5, min(l1 + l2 - 0.3, d))
    -- (the knee stays on the side it bends to now; a straight leg bends forward)
    local kh = sub(K, H)
    local b = sub(kh, mul(u, dot(kh, u)))
    b = norm(b)
    if not b or len(sub(kh, mul(u, dot(kh, u)))) < 0.5 then b = norm(sub(fwd, mul(u, dot(fwd, u)))) or { 1.0, 0.0, 0.0 } end
    local ca_ = (l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d)
    ca_ = max(-1.0, min(1.0, ca_))
    local sa = sqrt(1.0 - ca_ * ca_)
    local K2 = add(H, add(mul(u, l1 * ca_), mul(b, l1 * sa)))
    local A2 = add(H, mul(u, d))
    local q1 = between(norm(kh), norm(sub(K2, H)))
    set_rot(pose, L.thigh, th, qmul(q1, th.q))
    local ka = qrot(q1, sub(A, K))
    local q2 = between(norm(ka), norm(sub(A2, K2)) or norm(ka))
    local ca2 = bone(pose, L.calf)
    set_rot(pose, L.calf, ca2, qmul(q2, qmul(q1, ca.q)))
    -- the foot keeps its animated turn in the world, tipped to the floor's slope
    local qa = { 0.0, 0.0, 0.0, 1.0 }
    if normal then qa = qslerp_id(between({ 0.0, 0.0, 1.0 }, normal), weight) end
    local ft2 = bone(pose, L.foot)
    set_rot(pose, L.foot, ft2, qmul(qa, ft.q))
end

local function wanted(pawn)
    local G = package.loaded["game"]
    if not M.enabled or not G then return false end
    if G.cutscene or G.warping or G.dying or G.swim or G.carried then return false end
    -- (sinking sand: held, and drawn down in it below - only going under is left to quicksand.lua)
    local Q = package.loaded["quicksand"]
    if Q and Q.dying and Q.dying() then return false end
    local R = package.loaded["ragdoll"]
    if R and R.active then return false end
    local ok, good = pcall(function()
        if pawn.CharacterMovement.MovementMode ~= 1 then return false end
        local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
        return not (m and m:IsValid())
    end)
    return ok and good
end

-- Held only while it is needed - walking (its feet on the ground), a tree climb (climb.lua's limbs are bent on the copy),
-- the squish (squish.lua scales the copy). Through any other move of STORROR's his own body is drawn and leads his
-- shoes and clothes again, as STORROR made him: held through them, it cut his roundoffs short on flat floors - STORROR
-- dropped him into a fall at 1.27 s, some 7 in 10 of them; footik off, 8 of 8 whole ("could it have something to do with
-- foot alignment?", 2026-10-17).
local function needed(pawn)
    if wanted(pawn) then return true end
    local CL = package.loaded["climb"]
    if CL and CL.active and CL.active() then return true end
    local SQ = package.loaded["squish"]
    if SQ and SQ.active and SQ.active() then return true end
    -- (swimming: his arms and legs swim on the copy - swimarms.lua, "add our stroke animation back", 2026-10-24)
    local SW = package.loaded["swim"]
    if SW and SW.active and SW.active() then return true end
    return false
end

-- ------------------------------------------------------------ his head through a swim
-- Swimming, the stroke is posed on this copy (swimarms.lua), and his own head - left on his hidden body since it may
-- not follow this copy (followers) - kept STORROR's pose of him: hung off the front of his neck, jerking about as
-- STORROR turned it to the camera ("head is detached from body while swimming also twitching like crazy",
-- 2026-11-06). So through a swim a copy of his head is drawn in its place: his head's own mesh, posed from his body
-- (its face's own bones as they lie on its head - led by this copy instead, they stood where they rest and its skin came
-- away, 2026-11-03), then its neck and head put where the swim has this copy's (M.swim_head_sync, after swimarms each
-- frame). What hangs on his head - Mario's cap and face - is hung on it till the swim is over.
M.HEAD_BONES = { "pelvis", "spine_01", "spine_02", "spine_03", "spine_04", "spine_05", "clavicle_l", "clavicle_r",
    "neck_01", "neck_02", "head" }      -- (parents first; those his head's mesh has)
function M.swim_carry(s, on)
    if on then
        s.hcarried = s.hcarried or {}
        -- (what hangs on his body's head socket, and anything on his head's own mesh)
        for _, parent in ipairs({ s.body, s.rhead }) do
            local kids = {}
            pcall(function() parent:GetChildrenComponents(false, kids) end)
            for _, c in ipairs(kids) do
                pcall(function()
                    local o = c.get and c:get() or c
                    if not (o and o:IsValid()) then return end
                    local sock = o:GetAttachSocketName():ToString()
                    if parent == s.rhead or sock:lower() == "head" then
                        o:K2_AttachToComponent(s.hc, FName(sock), 0, 0, 0, false)
                        s.hcarried[#s.hcarried + 1] = { o = o, sock = sock, parent = parent }
                    end
                end)
            end
        end
    else
        for _, e in ipairs(s.hcarried or {}) do
            pcall(function()
                if e.o:IsValid() and e.parent:IsValid() then e.o:K2_AttachToComponent(e.parent, FName(e.sock), 0, 0, 0, false) end
            end)
        end
        s.hcarried = nil
    end
end
function M.swim_head_sync()
    local s = st
    if not (s and s.swim_head_on and s.hc and s.pose) then return end
    pcall(function() s.hc:CopyPoseFromSkeletalComponent(s.body) end)
    for _, n in ipairs(s.hc_bones or {}) do
        local fn = FName(n)
        local t = s.pose:GetBoneTransformByName(fn, WORLD)
        s.hc:SetBoneTransformByName(fn, {
            Rotation = { X = t.Rotation.X, Y = t.Rotation.Y, Z = t.Rotation.Z, W = t.Rotation.W },
            Translation = { X = t.Translation.X, Y = t.Translation.Y, Z = t.Translation.Z },
            Scale3D = { X = t.Scale3D.X, Y = t.Scale3D.Y, Z = t.Scale3D.Z } }, WORLD)
    end
end
-- (a skin on him through a swim - caps.lua's pieces, each a copy of a part of his: led by this copy, his head's by the
-- swim's copy of his head (the same mesh); this copy and that head hidden where the skin covers them, his sleeves and
-- gloves on this copy would show through it. Back to his own body after)
function M.skin_follow(s, on)
    local lib = require("lib")
    local C = package.loaded["caps"]
    local parts = C and C.skin_parts and C.skin_parts()
    local body_cov, head_cov = false, false
    for _, e in ipairs(parts or {}) do
        pcall(function()
            if not e.c:IsValid() then return end
            local lead = s.body
            if on then lead = (e.nm == "Head" and s.hc and s.hc:IsValid()) and s.hc or s.pose end
            e.c:SetLeaderPoseComponent(lead, true, false)
        end)
        if e.nm == "CharacterMesh0" then body_cov = true end
        if e.nm == "Head" then head_cov = true end
    end
    if on then
        if body_cov then pcall(function() s.pose:SetVisibility(false, false) end) end
        if head_cov and s.hc then pcall(function() s.hc:SetVisibility(false, false) end) end
    elseif s.on then
        pcall(function() s.pose:SetVisibility(true, false) end)
    end
    -- (and its backpack held to the same spine bone of whichever body leads, where race.lua M.pack_on puts it on his:
    -- "bag not attached", 2026-11-07 - left on his own body, STORROR's standing pose, as he swam off)
    local pk = C and C.skin_pack and C.skin_pack()
    local R = package.loaded["race"]
    if pk and R and R.PACK_REL then
        pcall(function()
            if not pk:IsValid() then return end
            pk:K2_AttachToComponent(on and s.pose or s.body, FName("spine_04"), 2, 2, 2, false)
            pk.RootComponent:K2_SetRelativeLocationAndRotation(R.PACK_REL.loc, R.PACK_REL.rot, false, {}, true)
        end)
    end
    s.skin_led, s.skin_ref, s.pack_ref = on or nil, on and parts or nil, on and pk or nil
    lib.log("feet: the skin's %d pieces led by %s", #(parts or {}), on and "the swim's body" or "his own")
end
function M.swim_head(s, pawn, on)
    if on then
        pawn = pawn or lib.pawn()
        local head = nil
        for _, c in ipairs(comps_of(pawn, "/Script/Engine.SkinnedMeshComponent")) do
            if c:GetFName():ToString() == "Head" then head = c end
        end
        if not (head and head:IsValid()) then return end
        local asset = head:GetSkinnedAsset()
        if not (asset and asset:IsValid()) then return end
        if not (s.hc and s.hc:IsValid()) or s.hc_asset ~= asset:GetAddress() then
            local hc = s.actor:AddComponentByClass(StaticFindObject("/Script/Engine.PoseableMeshComponent"), true, IDENT, false)
            if not (hc and hc:IsValid()) then return end
            hc:SetSkinnedAssetAndUpdate(asset, true)
            hc:K2_AttachToComponent(s.actor.RootComponent, FName("None"), 2, 2, 2, false)
            pcall(function() hc:SetCastShadow(true) end)
            pcall(function() hc:SetForcedLOD(1) end)
            s.hc, s.hc_asset = hc, asset:GetAddress()
        end
        pcall(function()
            for i = 0, head:GetNumMaterials() - 1 do
                local m = head:GetMaterial(i)
                if m and m:IsValid() then s.hc:SetMaterial(i, m) end
            end
        end)
        s.hc_bones = {}
        for _, n in ipairs(M.HEAD_BONES) do
            local okb, bi = pcall(function() return s.hc:GetBoneIndex(FName(n)) end)
            if okb and bi and bi >= 0 then s.hc_bones[#s.hc_bones + 1] = n end
        end
        s.rhead, s.swim_head_on, s.hcarry_t = head, true, 0.0
        M.swim_head_sync()
        pcall(function() s.hc:SetVisibility(true, false) end)
        pcall(function() head:SetVisibility(false, false) end)
        M.swim_carry(s, true)
        log("feet: his head drawn on the swim's body (%d of its bones led, %d things carried)", #s.hc_bones, #(s.hcarried or {}))
    else
        s.swim_head_on = false
        M.swim_carry(s, false)
        pcall(function() if s.hc and s.hc:IsValid() then s.hc:SetVisibility(false, false) end end)
        pcall(function() if s.rhead and s.rhead:IsValid() then s.rhead:SetVisibility(true, false) end end)
        log("feet: his own head back")
    end
end

-- ------------------------------------------------------------ each frame
M.R3_OFF = 0.6               -- (s: his own body shown after R3, see M.update)
-- (scenes it is off in - none: tried off in the basement for its frame rate, the copy 2 ms a frame there, and wanted
-- back - "I still want the foot-FK", 2026-11-06)
M.OFF_SCENES = {}
function M.update(dt, pawn)
    if not pawn then return end
    local world = lib.world()
    if not world then return end
    local s = st
    if s and (s.world ~= world:GetAddress() or s.pawn ~= pawn:GetAddress()) then st, s = nil, nil end
    -- (the caps' looks hide and show his meshes themselves)
    local C = package.loaded["caps"]
    local capped = C and C.on and (C.on("metal") or C.on("vanish"))
    -- (and a skin on any part of him - caps.lua M.parts: its copies follow his own body, and this copy's painted
    -- sleeves and gloves showed through them. His own given back: the skin hides what it covers)
    local skinned = C and C.parts_on and C.parts_on()
    local Gm = package.loaded["game"]
    local off_here = Gm and Gm.name and M.OFF_SCENES[Gm.name]
    -- (a skin on him and swimming: on all the same, the skin's pieces led by the swim's body - M.skin_follow. Off, a skin
    -- had no swimming body at all, STORROR's water idle: "swimming animation doesnt take hold sometimes", 2026-11-07)
    local SWs = package.loaded["swim"]
    local swim_now = (SWs and SWs.active and SWs.active()) and true or false
    if capped or (skinned and not swim_now) or off_here or not M.enabled then
        if s and s.skin_led then pcall(M.skin_follow, s, false) end
        if s and s.swim_head_on then pcall(M.swim_head, s, pawn, false) end
        if s and s.on then
            disengage(s, not capped)
            -- (his body and head shown again by it: hidden again where the skin covers them)
            if skinned and C and C.skin_rehide then pcall(C.skin_rehide) end
        end
        return
    end
    -- (R3 pressed - STORROR's ragdoll, which it starts some 0.27 s later - his own body is shown again at once, while he
    -- is still on his feet: handed back as the ragdoll began, the copy rode up a metre with the capsule STORROR lifts
    -- over his hips on that frame, and his body after it - "when pressing r3 to ragdoll ... jumps up 3ft for 2
    -- frames", 2026-10-26; with this off, nothing jumped. Kept off till R3_OFF after the press.)
    local r3 = false
    pcall(function() r3 = lib.controller():IsInputKeyDown({ KeyName = FName("Gamepad_RightThumbstick") }) end)
    if r3 then M.r3_t = os.clock() end
    local r3_off = M.r3_t ~= nil and os.clock() - M.r3_t < M.R3_OFF
    if r3_off or not needed(pawn) then
        if s and s.swim_head_on then pcall(M.swim_head, s, pawn, false) end
        if s and s.on then disengage(s, true) end
        return
    end
    if not s then
        local ok, r = pcall(build, world, pawn)
        if not ok then log("feet: %s", tostring(r)); M.enabled = false; return end
        st, s = r, r
        if not s then M.enabled = false; return end
    end
    if not s.on then engage(s, pawn) end
    -- (a swim: a copy of his head drawn on this copy's neck - M.swim_head)
    do
        local SWm = package.loaded["swim"]
        local swimming = (SWm and SWm.active and SWm.active()) and true or false
        if swimming ~= (s.swim_head_on or false) then pcall(M.swim_head, s, pawn, swimming) end
        local lead = (swimming and skinned) and true or false
        if lead ~= (s.skin_led or false) then pcall(M.skin_follow, s, lead)
        elseif lead and C and ((C.skin_parts and C.skin_parts() ~= s.skin_ref) or (C.skin_pack and C.skin_pack() ~= s.pack_ref)) then
            pcall(M.skin_follow, s, true)       -- (made again)
        end
        if s.swim_head_on then
            pcall(function() if s.rhead:IsVisible() then s.rhead:SetVisibility(false, false) end end)
            s.hcarry_t = (s.hcarry_t or 0.0) + dt
            if s.hcarry_t > 0.5 then s.hcarry_t = 0.0; pcall(M.swim_carry, s, true) end
        end
    end
    -- (STORROR shows its meshes again after some of its own moves)
    pcall(function() if s.body:IsVisible() then s.body:SetVisibility(false, false) end end)
    s.mat_t = s.mat_t + dt
    if s.mat_t > 1.0 then s.mat_t = 0.0; copy_materials(s) end
    s.carry_t = (s.carry_t or 0.0) + dt
    if s.carry_t > 0.5 then s.carry_t = 0.0; carry(s, true) end
    local pose = s.pose
    pcall(function() pose:CopyPoseFromSkeletalComponent(s.body) end)
    if s.swim_head_on then pcall(M.swim_head_sync) end
    -- how much of it, eased in and out
    local want = wanted(pawn) and 1.0 or 0.0
    s.alpha = s.alpha + (want - s.alpha) * min(1.0, dt * 8.0)
    if s.alpha < 0.01 and abs(s.shown) < 0.05 then s.alpha = 0.0; sink_through(s, false); return end
    local ok, err = pcall(function()
        -- his animation's floor: his body mesh's origin, less what this has lowered it by
        local o = s.body:K2_GetComponentLocation()
        local floor0 = o.Z - OFFSET.Z + s.shown
        local ox, oy = o.X - OFFSET.X, o.Y - OFFSET.Y
        local gc = ground(ox, oy, floor0 + 30.0)
        local on = gc and abs(gc - floor0) < ON_FLOOR
        local need, normals, weights = {}, {}, {}
        local lowest = 0.0
        for i, L in ipairs(LEGS) do
            local ft = bone(pose, L.foot)
            local fx, fy = ft.p[1] - OFFSET.X, ft.p[2] - OFFSET.Y
            local h = ft.p[3] - OFFSET.Z + s.shown - floor0          -- (the foot over his animation's floor)
            local w = 1.0
            if h > LIFT_FULL then w = max(0.0, 1.0 - (h - LIFT_FULL) / (LIFT_NONE - LIFT_FULL)) end
            local g, n = nil, nil
            if on then g, n = ground(fx, fy, floor0 + MAX_STEP) end
            local dz = 0.0
            if g and g > floor0 - MAX_STEP then
                -- (a foot tipped to a slope keeps its height over the ground square to the slope: its ankle goes up by
                -- h (1/cos - 1), or the toes of a foot pointing downhill are in the ground)
                local lift = (n and n[3] and n[3] > 0.5) and max(0.0, h) * (1.0 / n[3] - 1.0) or 0.0
                dz = (g - floor0 + lift) * w
            else
                w = 0.0
            end
            need[i], normals[i], weights[i] = dz, n, w
            lowest = min(lowest, dz)
        end
        local a = s.alpha
        local target_drop = on and max(-MAX_DROP, lowest) * a or 0.0
        -- (in sinking sand the whole of him is drawn down in it, as deep as quicksand.lua has him - Mario 64 draws
        -- Mario lower by his quicksandDepth - and his feet are left in it, no IK: "the sand doesnt slowly suck you in",
        -- 2026-10-23. Lowered here, on this copy of him, not his own body: STORROR's physics held his own up.)
        local Q = package.loaded["quicksand"]
        local sink = (Q and Q.depth or 0.0) * SINK_CM
        if sink > 0.5 then target_drop = -sink * a end
        sink_through(s, sink > 0.5 or s.drop < -MAX_DROP)
        s.drop = s.drop + (target_drop - s.drop) * min(1.0, dt * 10.0)
        if abs(-s.drop - s.shown) > 0.1 then place_body(s, -s.drop) end
        if sink > 0.5 then return end
        if not on and a <= 0.0 then return end
        local yaw = math.rad(pawn:K2_GetActorRotation().Yaw)
        local fwd = { math.cos(yaw), math.sin(yaw), 0.0 }
        for i, L in ipairs(LEGS) do
            local t = (need[i] - s.drop) * a
            s.legs[i] = s.legs[i] + (t - s.legs[i]) * min(1.0, dt * 15.0)
            -- (a foot on flat ground with nothing to bend is as his animation has it already: left be - its bones read
            -- and set for nothing took a third of a millisecond of every frame, "I want a significant boost in fps",
            -- 2026-11-03)
            local n = normals[i]
            local tilted = n and n[3] and n[3] < 0.999
            if abs(s.legs[i]) > 0.2 or (tilted and weights[i] * a > 0.02) then
                leg_ik(pose, L, s.legs[i], normals[i], weights[i] * a, fwd)
            end
        end
    end)
    if not ok and not s.err then s.err = true; log("feet: %s", tostring(err)) end
end

-- the scene going: his own meshes back (the copy kept, hidden, for the next)
function M.clear()
    local s = st
    if s and s.swim_head_on and here(s) then pcall(M.swim_head, s, nil, false) end
    if s and s.on and here(s) then disengage(s, true) end
end

function M.forget() st = nil end

function M.debug() return st end

return M
