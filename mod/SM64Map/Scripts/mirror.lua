-- The castle's mirror room (Mario 64's castle_inside area 2): the room is built twice, the second half the first
-- turned round across the mirror (Mario 64 x 4331.53), and Mario 64 draws Mario a second time there
-- (geo_render_mirror_mario) and Lakitu where the camera's reflection is (camera_lakitu.inc.c,
-- CAMERA_LAKITU_BP_FOLLOW_CAMERA: shown while the camera is between x 1700 and the mirror, on his cloud).
-- Here the athlete's reflection is a copy of his meshes - body, face, shoes, his shirt and joggers (Chaos cloth) and
-- hair (grooms) - each posed by his own (leader pose), under a root turned inside out across the mirror's plane.
-- Built the first time he walks into the room, shown while he is in it. (There was no one in the mirror, 2026-10-15.)
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET
local M = {}

local U = 0.75          -- (scene cm to a Mario 64 unit)
-- scene name -> the mirror's plane (scene y), the room in front of it (scene cm), where Lakitu shows from
local MIRRORS = {
    castle2 = { ym = 4331.53 * U, x0 = -2945.0, x1 = 510.0, y0 = 1252.0, z0 = 950.0, z1 = 1800.0, cam_y0 = 1700.0 * U },
}

local IDENT = { Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = 0.0, Y = 0.0, Z = 0.0 },
                Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }
local st = nil

local function comps_of(pawn, path)
    local out = {}
    local cls = StaticFindObject(path)
    if not (cls and cls:IsValid()) then return out end
    for _, c in ipairs(pawn:K2_GetComponentsByClass(cls)) do
        local o = c:get()
        if o and o:IsValid() then out[o:GetFName():ToString()] = o end
    end
    return out
end

local function copy_materials(src, c)
    for i = 0, src:GetNumMaterials() - 1 do
        local m = src:GetMaterial(i)
        if m and m:IsValid() then c:SetMaterial(i, m) end
    end
end

-- the reflection: his meshes, copied, under a root at the mirror scaled -1 across it
local function build_reflection(world, pawn, def)
    local skel = comps_of(pawn, "/Script/Engine.SkeletalMeshComponent")
    local prim = comps_of(pawn, "/Script/Engine.PrimitiveComponent")
    local body = skel["CharacterMesh0"]
    if not body then return nil end
    local a = lib.spawn_actor(world, { X = OFFSET.X, Y = def.ym + OFFSET.Y, Z = OFFSET.Z }, 0.0)
    if not a then return nil end
    a:SetActorScale3D({ X = 1.0, Y = -1.0, Z = 1.0 })
    pcall(function() a:SetActorEnableCollision(false) end)
    local scls = StaticFindObject("/Script/Engine.SkeletalMeshComponent")
    local function skin(src, parent, socket)
        local c = a:AddComponentByClass(scls, true, IDENT, false)
        if not (c and c:IsValid()) then return nil end
        local asset = src:GetSkinnedAsset()
        if asset and asset:IsValid() then c:SetSkinnedAssetAndUpdate(asset, true) end
        c:K2_AttachToComponent(parent or a.RootComponent, FName(socket or "None"), 2, 2, 2, false)
        copy_materials(src, c)
        c:SetLeaderPoseComponent(src, true, false)
        pcall(function() c:SetCastShadow(false) end)
        pcall(function() c:SetCollisionEnabled(0) end)
        pcall(function() c.VisibilityBasedAnimTickOption = 0 end)
        return c
    end
    local cb = skin(body, nil)
    if not cb then lib.destroy(a); return nil end
    local head = skel["Head"] and skin(skel["Head"], cb)
    if skel["Feet"] then skin(skel["Feet"], cb) end
    -- his clothes: Chaos cloth posed by his body
    local ccls = StaticFindObject("/Script/ChaosClothAssetEngine.ChaosClothComponent")
    for _, n in ipairs({ "TorsoCloth", "LegsCloth" }) do
        local src = prim[n]
        if src and ccls and ccls:IsValid() then
            pcall(function()
                local c = a:AddComponentByClass(ccls, true, IDENT, false)
                if not (c and c:IsValid()) then return end
                c:K2_AttachToComponent(cb, FName("None"), 2, 2, 2, false)
                local asset = src:GetAsset()
                if asset and asset:IsValid() then c:SetAsset(asset) end
                copy_materials(src, c)
                c:SetLeaderPoseComponent(body, true, false)
                pcall(function() c:SetCastShadow(false) end)
            end)
        end
    end
    -- his hair, brows and stubble: grooms bound to his face
    local gcls = StaticFindObject("/Script/HairStrandsCore.GroomComponent")
    for _, n in ipairs({ "HairGroom", "BrowsGroom", "MustacheGroom", "BeardGroom" }) do
        local src = prim[n]
        -- (none hidden on him - his beard, and his hair under Mario's cap: in the mirror as on him, 2026-10-29; the hair
        -- came through the reflection's cap, 2026-10-31)
        if src and src.bHiddenInGame then src = nil end
        if src and head and gcls and gcls:IsValid() then
            pcall(function()
                local ga, gb = src.GroomAsset, src.BindingAsset
                if not (ga and ga:IsValid()) then return end
                local c = a:AddComponentByClass(gcls, true, IDENT, false)
                if not (c and c:IsValid()) then return end
                c:K2_AttachToComponent(head, src.AttachSocketName, 2, 2, 2, false)
                if gb and gb:IsValid() then c:SetBindingAsset(gb) end
                c:SetGroomAsset(ga)
                pcall(function() c:SetCastShadow(false) end)
            end)
        end
    end
    -- Mario's cap, nose and mustache (mariolook.lua's pieces on his head bone, not his own meshes): on the
    -- reflection's head as on his - "in the mirror marios missing his hat nose and stash", 2026-10-31
    local dressed = nil
    local ML = package.loaded["mariolook"]
    if ML and ML.on and ML.on() and ML.dress then
        local okd, r = pcall(ML.dress, a, cb, "mirror")
        if okd and r then dressed = a:GetAddress() end
    end
    return { actor = a, body = cb, src = body, dressed = dressed }
end

-- the reflection's cap shown as his is (off his head when he has lost it: mariocap.lua, mariolook.show_cap)
local function sync_cap(r)
    local ML = package.loaded["mariolook"]
    if not (r.dressed and ML and ML.pmcs and ML.dressed_pieces) then return end
    local ids = ML.CAP_SECTIONS or { 2, 3, 4, 6 }
    local src = ML.pmcs()[1]
    if not src then return end
    local okv, on = pcall(function() return src:IsMeshSectionVisible(ids[1]) end)
    if not okv or on == r.cap_on then return end
    r.cap_on = on
    for _, p in ipairs(ML.dressed_pieces(r.dressed)) do
        for _, id in ipairs(ids) do pcall(function() p.pmc:SetMeshSectionVisible(id, on) end) end
    end
end

-- the reflection's look taken off with it (its pieces are actors of their own, on its head)
local function undress(r)
    local ML = package.loaded["mariolook"]
    if r and r.dressed and ML and ML.undress then pcall(ML.undress, r.dressed) end
end

-- Lakitu and his cloud (cloud.inc.c: five mist puffs, two thirds of the cloud's size, 25 out round him at his
-- heading plus a fifth of a turn each, 11, 8, 12, 8, 9 up, all bobbing along (1, 1, 1) once in 32 frames)
local PUFF_UP = { 11, 8, 12, 8, 9 }
local function build_lakitu(world, actor_data)
    local data = actor_data("lakitu")
    if not data then return nil end
    local inst = lib.make_instance(world, data, { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z }, 0.0, 1.0)
    if not inst then return nil end
    inst.moves = true
    local L = { inst = inst, puffs = {}, f = 0.0 }
    local mist = actor_data("mist")
    if mist then
        for i = 1, 5 do
            local p = lib.make_instance(world, mist, { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z }, 0.0, 4.0 / 3.0)
            if p then p.moves = true; L.puffs[i] = p end
        end
    end
    return L
end

local function hide(o, h)
    if o and o.shown ~= not h then
        o.shown = not h
        pcall(function() o.actor:SetActorHiddenInGame(h) end)
    end
end

-- the reflection hidden or shown, and the look's pieces on its head with it (actors of their own: hiding the
-- reflection's actor leaves them up)
local function ref_hide(r, h)
    if not r then return end
    hide(r, h)
    local ML = package.loaded["mariolook"]
    if r.dressed and ML and ML.dressed_pieces and r.dressed_shown ~= not h then
        r.dressed_shown = not h
        for _, p in ipairs(ML.dressed_pieces(r.dressed)) do
            pcall(function() p.pmc:GetOwner():SetActorHiddenInGame(h) end)
        end
    end
end

local function lakitu_hide(L, h)
    if not L then return end
    hide(L.inst, h)
    for _, p in ipairs(L.puffs) do hide(p, h) end
end

function M.load(world, name, actor_data)
    M.clear()
    local def = MIRRORS[name]
    if not (def and world) then return end
    st = { world = world:GetAddress(), def = def, actor_data = actor_data, t = 0.0 }
end

function M.clear()
    if not st then return end
    local w = lib.world()
    if w and w:GetAddress() == st.world then
        if st.ref then undress(st.ref); lib.destroy(st.ref.actor) end
        if st.lakitu then
            lib.destroy(st.lakitu.inst.actor)
            for _, p in ipairs(st.lakitu.puffs) do lib.destroy(p.actor) end
        end
    end
    st = nil
end

-- (dev: the state, to look at)
function M.debug() return st end

-- (a new map: everything of the old one is gone, untouched)
function M.forget() st = nil end

-- (x, y, z): his feet, scene cm
function M.update(dt, x, y, z)
    if not st then return end
    local world = lib.world()
    if not (world and world:GetAddress() == st.world) then st = nil; return end
    local d = st.def
    local inside = x > d.x0 and x < d.x1 and y > d.y0 and y < d.ym and z > d.z0 and z < d.z1
    if not inside then
        ref_hide(st.ref, true)
        lakitu_hide(st.lakitu, true)
        return
    end
    local pawn = lib.pawn()
    if not pawn then return end
    local pa = pawn:GetAddress()
    if st.ref and st.ref.pawn ~= pa then undress(st.ref); lib.destroy(st.ref.actor); st.ref = nil end      -- (another athlete)
    if not st.ref and not st.failed then
        local ok, r = pcall(build_reflection, world, pawn, d)
        if ok and r then
            st.ref, r.pawn, r.shown = r, pa, true
            log("mirror: his reflection is up")
        else
            st.failed = true
            log("mirror: no reflection (%s)", tostring(r))
        end
        if not st.lakitu then
            local okl, L = pcall(build_lakitu, world, st.actor_data)
            if okl then st.lakitu = L end
        end
    end
    st.t = st.t + dt
    local r = st.ref
    if r then
        ref_hide(r, false)
        sync_cap(r)
        -- his body's place and turn, measured from the mirror: the root's -1 across it does the rest
        local L = r.src:K2_GetComponentLocation()
        local R = r.src:K2_GetComponentRotation()
        r.body.RelativeLocation = { X = L.X - OFFSET.X, Y = L.Y - (d.ym + OFFSET.Y), Z = L.Z - OFFSET.Z }
        r.body.RelativeRotation = { Pitch = R.Pitch, Yaw = R.Yaw, Roll = R.Roll }
        r.nudge = (r.nudge == 0.02) and 0.0 or 0.02
        r.actor:K2_TeleportTo({ X = OFFSET.X, Y = d.ym + OFFSET.Y, Z = OFFSET.Z + r.nudge }, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
    end
    -- Lakitu: where the camera's reflection is, facing the way it looks (at the mirror, so out at the player)
    local Lk = st.lakitu
    if Lk then
        local pc = lib.controller()
        local cam, rot
        pcall(function()
            local pcm = pc.PlayerCameraManager
            cam, rot = pcm:GetCameraLocation(), pcm:GetCameraRotation()
        end)
        local cx, cy, cz = cam and cam.X - OFFSET.X, cam and cam.Y - OFFSET.Y, cam and cam.Z - OFFSET.Z
        local hl = pawn:K2_GetActorLocation()
        -- (not from his own eyes: in first person there is no camera to see)
        local near = cam and ((cam.X - hl.X) ^ 2 + (cam.Y - hl.Y) ^ 2 + (cam.Z - hl.Z - 70.0) ^ 2 < 90.0 ^ 2)
        if not cam or near or cy < d.cam_y0 or cy > d.ym then
            lakitu_hide(Lk, true)
            return
        end
        lakitu_hide(Lk, false)
        local lx, ly, lz = cx, 2.0 * d.ym - cy, cz
        local yaw = -rot.Yaw
        local data = Lk.inst.data
        Lk.f = Lk.f + dt * 30.0
        if data.anims and data.anims[1] then lib.pose(Lk.inst, data.anims[1], Lk.f) end
        pcall(function()
            Lk.inst.actor:K2_TeleportTo({ X = lx + OFFSET.X, Y = ly + OFFSET.Y, Z = lz + OFFSET.Z },
                { Pitch = -rot.Pitch, Yaw = yaw + 180.0, Roll = 0.0 })
        end)
        local s = 4.0 / 3.0
        local frame = st.t * 30.0
        for i, p in ipairs(Lk.puffs) do
            local k = i - 1
            local ang = math.rad(yaw + 180.0 + k * 72.0)
            local bob = 2.0 * math.cos(math.rad((frame * 0x800 + 0x4000 * k) * 360.0 / 65536.0)) * s * U
            local px = lx + math.cos(ang) * 25.0 * s * U + bob
            local py = ly + math.sin(ang) * 25.0 * s * U + bob
            local pz = lz + PUFF_UP[i] * s * U + bob
            -- (billboards: each turned to face the camera - the puff's face is its -x side)
            local fy = math.deg(math.atan(cy - py, cx - px))
            local fp = math.deg(math.atan(cz - pz, math.sqrt((cx - px) ^ 2 + (cy - py) ^ 2)))
            pcall(function()
                p.actor:K2_TeleportTo({ X = px + OFFSET.X, Y = py + OFFSET.Y, Z = pz + OFFSET.Z },
                    { Pitch = -fp, Yaw = fy + 180.0, Roll = 0.0 })
            end)
        end
    end
end

return M
