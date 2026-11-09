-- SM64Map: peer-to-peer multiplayer through Steam ("next I want to work on multiplayer, we cant connect to official
-- servers so we have to setup a peer to peer", "Steam friends", "also through the multiplayer menu in game to join
-- public lobbies", 2026-11-01).
--
-- dlls\sm64net.dll does the networking (Steam lobbies to find each other, Steam's peer-to-peer messages to play); this
-- loads it, tells it what to do, and sends it this player's state: his scene and his whole pose - where his body is
-- and how 33 of its bones lie, as the race ghost records them (raceghost.lua) - 20 times a second. Every other player
-- in the same scene is drawn as the race's racer is built: a copy of the athlete's body, head, shoes and clothes with
-- Mario's cap, posed each frame from that player's bones, eased between their samples: their runs, flips, vaults and
-- climbs as they made them. No collision, no parkour, no AI: nothing of the game's touches it.
--
-- The files between this and the DLL are in the mod's net\ folder (sm64net.cpp says what each holds).
local lib = require("lib")
local log = lib.log

local M = {}

local NET = lib.MOD_DIR .. "net\\"
-- (in bin\, not dlls\: UE4SS takes a mod with a dlls folder for a C++ mod and tried to load SM64Map as one)
local DLL = lib.MOD_DIR .. "bin\\sm64net.dll"
local OFFSET = lib.OFFSET
local IDENT = { Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = 0.0, Y = 0.0, Z = 0.0 }, Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }

M.RATE = 20.0                 -- states sent a second
M.DELAY = 0.12                -- s: the others drawn this far behind their latest, eased between their samples
M.STALE = 3.0                 -- s: a player not heard from this long isn't drawn
M.MAX_DRAWN = 24              -- the most other players drawn at once (a lobby takes 100)
M.MIRROR = false              -- (testing alone: this player's own state drawn as another, M.MIRROR_SIDE cm to his right)
M.MIRROR_SIDE = 250.0
M.status = { state = "off", members = {}, list = {}, listdone = 0 }

local started, callbacks_on = false, false
local fn_callbacks = nil

-- ------------------------------------------------------------------------------------------- the DLL

local function start()
    if started then return true end
    local f, err = package.loadlib(DLL, "sm64net_start")
    if not f then log("multiplayer: couldn't load sm64net.dll (%s)", tostring(err)); return false end
    local ok, e2 = pcall(f)
    if not ok then log("multiplayer: sm64net_start failed (%s)", tostring(e2)); return false end
    fn_callbacks = package.loadlib(DLL, "sm64net_callbacks")
    started = true
    log("multiplayer: sm64net.dll started")
    return true
end
M.start = start

local function cmd(line)
    if not start() then return end
    local f = io.open(NET .. "cmd.txt", "a")
    if f then f:write(line, "\n"); f:close() end
end

-- Locked lobbies ("I also want passworded lobbies", 2026-11-01): Steam's lobbies have no password of their own, so a
-- locked one carries a hash of its 4-digit code in its data ("lock"), and a joiner from the lobby list is let in only
-- with the code that makes the same hash. (A friend's invite, or Steam's "Join Game", needs none: the host asked them.)
local function lock_of(code)
    local h = 2166136261                                   -- FNV-1a, 32 bits, over the mod's word and the code
    for c in ("sm64mp-lock:" .. tostring(code)):gmatch(".") do h = ((h ~ c:byte()) * 16777619) & 0xffffffff end
    return string.format("%08x", h)
end
M.lock_of = lock_of

function M.host(public, code)
    cmd("lock " .. (code and lock_of(code) or "-"))
    cmd(public and "host public" or "host friends")
end
function M.list() cmd("list") end
-- (a locked lobby from the list: only with its code - false if it's wrong)
function M.join(id, code)
    if not (id and tostring(id):match("^%d+$")) then return false end
    -- (an IRONMAN game he died in: not again - M.dead_in_lobby)
    if M.dead_in_lobby and M.dead_in_lobby(id) then log("multiplayer: not joining %s - died there in IRONMAN", tostring(id)); return false end
    for _, l in ipairs(M.status.list or {}) do
        if l.id == tostring(id) and l.lock and l.lock ~= "" and lock_of(code or "") ~= l.lock then return false end
    end
    cmd("join " .. tostring(id))
    return true
end
function M.leave() cmd("leave") end
-- Steam overlay's invite window - asked from the game's thread (from the DLL's own it showed nothing: "nothing shows
-- when you press invite steam friends", 2026-11-01) - and one friend invited by Steam's own lobby invite, no overlay
local fn_invite = nil
function M.invite()
    if not start() then return end
    if fn_invite == nil then fn_invite = package.loadlib(DLL, "sm64net_invite") or false end
    if fn_invite then pcall(fn_invite) else cmd("invite") end
end
function M.invite_friend(id) if id and tostring(id):match("^%d+$") then cmd("invite " .. tostring(id)) end end
function M.in_lobby() return M.status.state == "in_lobby" end
function M.others() local n = 0; for _, m in ipairs(M.status.members) do if m.id ~= M.status.me then n = n + 1 end end; return n end

-- an event to every other player (reliable): mp_event(kind, text)
function M.send_event(kind, text, to)
    if not M.in_lobby() then return end
    local f = io.open(NET .. "out_events.txt", "a")
    if f then f:write(to and ("to=" .. to .. "|") or "", kind, "|", text or "", "\n"); f:close() end
end
M.on_event = {}               -- kind -> function(from_id, text)

local function read_status()
    local f = io.open(NET .. "status.txt", "r")
    if not f then return end
    local text = f:read("*a")
    f:close()
    if not text or text == "" then return end
    local s = { members = {}, list = {}, listdone = 0 }
    for line in text:gmatch("[^\n]+") do
        local k, v = line:match("^([%w_]+)=(.*)$")
        if k == "member" then
            local id, name = v:match("^(%d+)|(.*)$")
            if id then s.members[#s.members + 1] = { id = id, name = name } end
        elseif k == "list" then
            local id, name, n, max, rest = v:match("^(%d+)|([^|]*)|(%d+)|(%-?%d+)|(.*)$")
            local scene, lock = (rest or ""):match("^([^|]*)|(.*)$")
            if id then
                s.list[#s.list + 1] = { id = id, name = name, n = tonumber(n), max = tonumber(max), scene = scene or rest, lock = lock or "" }
            end
        elseif k == "friend" then
            local id, name, here = v:match("^(%d+)|([^|]*)|(%d)$")
            if id then s.friends = s.friends or {}; s.friends[#s.friends + 1] = { id = id, name = name, here = here == "1" } end
        elseif k == "listdone" then
            s.listdone = tonumber(v) or 0
        elseif k then
            s[k] = v
        end
    end
    local was = M.status.state
    M.status = s
    if s.state ~= was then log("multiplayer: %s%s", tostring(s.state), (s.error and s.error ~= "") and (" (" .. s.error .. ")") or "") end
end

-- ------------------------------------------------------------------------------------- base64 (no | or line breaks)

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64I = {}
for i = 1, 64 do B64I[B64:byte(i)] = i - 1 end
local function b64(s)
    local out, n = {}, #s
    for i = 1, n, 3 do
        local a, b, c = s:byte(i, i + 2)
        b, c = b or 0, c or 0
        local v = a * 65536 + b * 256 + c
        local k = #out
        out[k + 1] = B64:sub((v >> 18) + 1, (v >> 18) + 1)
        out[k + 2] = B64:sub(((v >> 12) & 63) + 1, ((v >> 12) & 63) + 1)
        out[k + 3] = (i + 1 <= n) and B64:sub(((v >> 6) & 63) + 1, ((v >> 6) & 63) + 1) or "="
        out[k + 4] = (i + 2 <= n) and B64:sub((v & 63) + 1, (v & 63) + 1) or "="
    end
    return table.concat(out)
end
local function unb64(s)
    local out = {}
    for i = 1, #s - 3, 4 do
        local a, b, c, d = s:byte(i, i + 3)
        local va, vb, vc, vd = B64I[a] or 0, B64I[b] or 0, B64I[c], B64I[d]
        local v = (va << 18) | (vb << 12) | ((vc or 0) << 6) | (vd or 0)
        out[#out + 1] = string.char((v >> 16) & 255)
        if vc then out[#out + 1] = string.char((v >> 8) & 255) end
        if vd then out[#out + 1] = string.char(v & 255) end
    end
    return table.concat(out)
end

-- ------------------------------------------------------------------------------------------- his state

local GR = nil
local function ghost() if not GR then local ok, m = pcall(require, "raceghost"); GR = ok and m or false end return GR end
local POS, Q = 50.0, 32767.0
local function clamp16(v) v = math.floor(v + 0.5); if v > 32767 then return 32767 elseif v < -32767 then return -32767 end return v end
local fnames, pose_fmt = nil, nil
local function bones()
    if not fnames then
        local g = ghost()
        if not g then return nil end
        fnames = {}
        for i, b in ipairs(g.BONES) do fnames[i] = FName(b) end
        pose_fmt = "<fffhhhh" .. string.rep("hhhhhhh", #fnames)
    end
    return fnames
end

-- his pose now, packed: where his body is (scene cm) and its turn, and each bone's place and turn in the body's space
local function my_pose(pawn)
    local fn = bones()
    if not fn then return nil end
    local mesh = pawn.Mesh
    if not (mesh and mesh:IsValid()) then return nil end
    -- (the body he is drawn as: footik.lua's copy while that is drawn - the swim's strokes are on it - as the race ghost
    -- records it, 2026-11-06)
    local F = package.loaded["footik"]
    local fs = F and F.debug and F.debug()
    if fs and fs.on and fs.pose and fs.pose:IsValid() then mesh = fs.pose end
    local w = mesh:K2_GetComponentToWorld()
    local vals = { w.Translation.X - OFFSET.X, w.Translation.Y - OFFSET.Y, w.Translation.Z - OFFSET.Z,
                   clamp16(w.Rotation.X * Q), clamp16(w.Rotation.Y * Q), clamp16(w.Rotation.Z * Q), clamp16(w.Rotation.W * Q) }
    for i = 1, #fn do
        local b = mesh:GetSocketTransform(fn[i], 2)               -- (RTS_Component)
        local p, q = b.Translation, b.Rotation
        local k = #vals
        vals[k + 1], vals[k + 2], vals[k + 3] = clamp16(p.X * POS), clamp16(p.Y * POS), clamp16(p.Z * POS)
        vals[k + 4], vals[k + 5], vals[k + 6], vals[k + 7] = clamp16(q.X * Q), clamp16(q.Y * Q), clamp16(q.Z * Q), clamp16(q.W * Q)
    end
    return string.pack(pose_fmt, table.unpack(vals))
end

local function unpack_pose(data)
    bones()
    if not pose_fmt then return nil end
    local ok, t = pcall(function() return table.pack(string.unpack(pose_fmt, data)) end)
    if not ok then return nil end
    return t
end

-- ------------------------------------------------------------------------------------------- the others

local P = {}                  -- by Steam id: { actor, addr, body, body_rel, text, name, samples, off, scene }
M.fail_t = {}

local function drop(id)
    local p = P[id]
    if not p then return end
    P[id] = nil
    local ML = package.loaded["mariolook"]
    if ML and ML.undress and p.addr then pcall(ML.undress, p.addr) end
    if p.addr then lib.keep[p.addr] = nil end
    if p.actor then pcall(lib.destroy, p.actor, false) end
end

function M.drop_all() for id in pairs(P) do drop(id) end end

-- another player's figure: the athlete's body, head, shoes and clothes copied from his own, posed by their bones; and
-- their name over it
local function make(id, name, pawn)
    local world = lib.world()
    if not world then return nil end
    local KML2 = StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    local l = pawn:K2_GetActorLocation()
    local a = lib.spawn_actor(world, { X = l.X, Y = l.Y, Z = l.Z - 5000.0 }, 0.0)   -- (out of sight till posed)
    if not a then return nil end
    pcall(function() a:SetActorEnableCollision(false) end)
    local addr = a:GetAddress()
    lib.keep[addr] = "mp player"
    local pawn_t = pawn:GetTransform()
    local function comps(cls)
        local out = {}
        pcall(function() for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject(cls))) do out[#out + 1] = c:get() end end)
        return out
    end
    local function place(c, src)
        c:K2_AttachToComponent(a.RootComponent, FName("None"), 2, 2, 2, false)
        c:K2_SetRelativeTransform(KML2:MakeRelativeTransform(src:K2_GetComponentToWorld(), pawn_t), false, {}, true)
        for i = 0, c:GetNumMaterials() - 1 do pcall(function() c:SetMaterial(i, src:GetMaterial(i)) end) end
        pcall(function() c:SetCastShadow(true) end)
        pcall(function() c:SetCollisionEnabled(0) end)
    end
    local body_src = nil
    for _, o in ipairs(comps("/Script/Engine.SkeletalMeshComponent")) do
        if o:GetFName():ToString() == "CharacterMesh0" then body_src = o end
    end
    if not body_src then pcall(lib.destroy, a, false); lib.keep[addr] = nil; return nil end
    local body = nil
    pcall(function()
        body = a:AddComponentByClass(StaticFindObject("/Script/Engine.PoseableMeshComponent"), true, IDENT, false)
        body:SetSkinnedAssetAndUpdate(body_src:GetSkinnedAsset(), true)
        place(body, body_src)
        body:CopyPoseFromSkeletalComponent(body_src)
    end)
    if not (body and body:IsValid()) then pcall(lib.destroy, a, false); lib.keep[addr] = nil; return nil end
    local rel_t = KML2:MakeRelativeTransform(body_src:K2_GetComponentToWorld(), pawn_t)
    local p = { actor = a, addr = addr, body = body, name = name, samples = {}, off = nil,
                body_rel = { rel_t.Translation.X, rel_t.Translation.Y, rel_t.Translation.Z,
                             rel_t.Rotation.X, rel_t.Rotation.Y, rel_t.Rotation.Z, rel_t.Rotation.W } }
    -- his head and shoes, led by the body
    for _, src in ipairs(comps("/Script/Engine.SkeletalMeshComponent")) do
        if src:GetFName():ToString() ~= "CharacterMesh0" then
            pcall(function()
                local c = a:AddComponentByClass(StaticFindObject("/Script/Engine.SkeletalMeshComponent"), true, IDENT, false)
                c:SetSkinnedAssetAndUpdate(src:GetSkinnedAsset(), true)
                place(c, src)
                c:SetLeaderPoseComponent(body, true, false)
                pcall(function() c.VisibilityBasedAnimTickOption = 0 end)
            end)
        end
    end
    -- his clothes (Chaos cloth), led by it, not blown about
    local ccls = StaticFindObject("/Script/ChaosClothAssetEngine.ChaosClothComponent")
    if ccls and ccls:IsValid() then
        for _, src in ipairs(comps("/Script/ChaosClothAssetEngine.ChaosClothComponent")) do
            pcall(function()
                local asset = src:GetAsset()
                if not (asset and asset:IsValid()) then return end
                local c = a:AddComponentByClass(ccls, true, IDENT, false)
                c:SetAsset(asset)
                place(c, src)
                c:SetLeaderPoseComponent(body, true, false)
                pcall(function() c:SetEnableSimulation(false) end)
            end)
        end
    end
    -- Mario's cap, nose and mustache, as the menu's figure is dressed
    local ML = package.loaded["mariolook"]
    if ML and ML.dress then pcall(ML.dress, a, body, "mp") end
    -- the name over the head
    pcall(function()
        local t = a:AddComponentByClass(StaticFindObject("/Script/Engine.TextRenderComponent"), false, IDENT, false)
        t:SetText(FText(name ~= "" and name or "Player"))
        t:SetHorizontalAlignment(1)          -- (centred)
        t:SetWorldSize(18.0)
        t:SetTextRenderColor({ R = 255, G = 255, B = 255, A = 255 })
        pcall(function() t:SetCastShadow(false) end)
        p.text = t
    end)
    log("multiplayer: %s drawn", name)
    return p
end

-- a sample: { st (their clock), d (the unpacked pose) }; the pose at their clock `t`, eased between the two either side
local function pose_at(p, t)
    local s = p.samples
    if #s == 0 then return nil end
    if t <= s[1].st then return s[1].d, s[1].d, 0.0 end
    for i = #s - 1, 1, -1 do
        if s[i].st <= t then
            local a, b = s[i], s[i + 1]
            local k = (b.st > a.st) and math.min(1.0, (t - a.st) / (b.st - a.st)) or 1.0
            return a.d, b.d, k
        end
    end
    local last = s[#s].d
    return last, last, 0.0
end

local function qlerp(a, b, o, k)
    local ax, ay, az, aw = a[o] / Q, a[o + 1] / Q, a[o + 2] / Q, a[o + 3] / Q
    local bx, by, bz, bw = b[o] / Q, b[o + 1] / Q, b[o + 2] / Q, b[o + 3] / Q
    if ax * bx + ay * by + az * bz + aw * bw < 0.0 then bx, by, bz, bw = -bx, -by, -bz, -bw end
    local x, y, z, w = ax + (bx - ax) * k, ay + (by - ay) * k, az + (bz - az) * k, aw + (bw - aw) * k
    local l = math.sqrt(x * x + y * y + z * z + w * w)
    if l < 1e-6 then return 0.0, 0.0, 0.0, 1.0 end
    return x / l, y / l, z / l, w / l
end

local ONE = { X = 1.0, Y = 1.0, Z = 1.0 }
local function draw(p, now, side)
    local g = ghost()
    if not (g and p.off) then return end
    local a, b, k = pose_at(p, now - p.off - M.DELAY)
    if not a then return end
    local bx = a[1] + (b[1] - a[1]) * k
    local by = a[2] + (b[2] - a[2]) * k
    local bz = a[3] + (b[3] - a[3]) * k
    local qx0, qy0, qz0, qw0 = qlerp(a, b, 4, k)
    -- (the actor where their body comes where it is: actor = body * the body's place in it, undone)
    local r = p.body_rel
    local qx, qy, qz, qw = g.qmul(qx0, qy0, qz0, qw0, -r[4], -r[5], -r[6], r[7])
    local ox, oy, oz = g.qrot(qx, qy, qz, qw, r[1], r[2], r[3])
    if side then ox, oy = ox - side[1], oy - side[2] end            -- (the mirror: moved to his right)
    pcall(function()
        p.actor:K2_SetActorTransform({ Rotation = { X = qx, Y = qy, Z = qz, W = qw },
            Translation = { X = bx - ox + OFFSET.X, Y = by - oy + OFFSET.Y, Z = bz - oz + OFFSET.Z }, Scale3D = ONE }, false, {}, true)
    end)
    local body = p.body
    for j, fn in ipairs(fnames) do
        local o = 8 + (j - 1) * 7
        local px = (a[o] + (b[o] - a[o]) * k) / POS
        local py = (a[o + 1] + (b[o + 1] - a[o + 1]) * k) / POS
        local pz = (a[o + 2] + (b[o + 2] - a[o + 2]) * k) / POS
        local x, y, z, w = qlerp(a, b, o + 3, k)
        pcall(function()
            body:SetBoneTransformByName(fn, { Rotation = { X = x, Y = y, Z = z, W = w }, Translation = { X = px, Y = py, Z = pz }, Scale3D = ONE }, 1)
        end)
    end
    -- the name over the head, turned to the camera
    -- (from where the figure is put, not its head bone: the bone's place lagged a frame, and the mirror's name hung
    -- over him, not it)
    if p.text then
        pcall(function()
            local hx, hy, hz = bx - ox + OFFSET.X, by - oy + OFFSET.Y, bz - oz + OFFSET.Z + 120.0
            local cx, cy = lib.camera_location()
            local yaw = cx and math.deg(math.atan(cy - hy, cx - hx)) or 0.0
            p.text:K2_SetWorldLocationAndRotation({ X = hx, Y = hy, Z = hz }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false, {}, true)
        end)
    end
end

-- ------------------------------------------------------------------------- going to a friend's level

M.peer_scene = {}             -- by Steam id: the scene each other player said last
M.peer_act = {}               -- by Steam id: the act (the star chosen) each said last, nil in a hub
function M.scene_of(id) return M.peer_scene[id] end

-- (a warp only when he can take one: in a scene, nothing on the way, no intro, ending, dialog or star select. Asked
-- from the pause menu, it is carried out as the menu shuts: game.lua's tick stands still while it is up.)
local function can_go(G)
    if not G.name or G.warping or G.pending or G.dying or G.cutscene then return false end
    local IN, EN = package.loaded["intro"], package.loaded["ending"]
    if (IN and IN.active) or (EN and EN.active) then return false end
    local D, S = package.loaded["dialog"], package.loaded["starselect"]
    if (D and D.active) or (S and S.active) then return false end
    return true
end

local follow = nil            -- { id, scene, t }: going to that player's level, then put beside them there
function M.go_to(id)
    local G = package.loaded["game"]
    local sc = M.peer_scene[id]
    if not (G and sc) then return end
    if sc == G.name then follow = { id = id, scene = sc, t = os.clock() }; return end
    if not can_go(G) then return end
    log("multiplayer: to %s, a friend's level", sc)
    follow = { id = id, scene = sc, t = os.clock() }
    G.goto_scene(sc, nil, {})
end

-- there: put beside them once their figure is drawn and he has stood a moment (the level's own start puts him first)
local function follow_tick(G, pawn, now)
    local f = follow
    if not f then return end
    if now - f.t > 30.0 then follow = nil; return end
    if G.name ~= f.scene or G.warping or G.pending then return end
    f.arrived = f.arrived or now
    if now - f.arrived < 1.0 then return end
    local p = P[f.id]
    if not (p and p.actor) then return end
    follow = nil
    pcall(function()
        local l = p.actor:K2_GetActorLocation()
        local r = p.actor:GetActorRightVector()
        pawn:K2_TeleportTo({ X = l.X + r.X * 90.0, Y = l.Y + r.Y * 90.0, Z = l.Z + 20.0 }, pawn:K2_GetActorRotation())
        log("multiplayer: beside %s", p.name or "a friend")
    end)
end

-- a state line from another player (or the mirror): S|1|<scene>|<their clock>|<pose>|<pvp 0/1>
-- (each star its own stage: two players in one level, after two different stars, don't see each other - the level is
-- not the same for both, its things and its map as the act has them: "each star has its own stage so that if 2 player
-- one goes for the first star and the second person goes for the second star they shouldnt see eachother",
-- 2026-11-03. The act rides on the state, after the PvP switch; none - a hub, or an older copy of the mod - meets all.)
local function heard(id, name, line, now, pawn, scene, act)
    local sc, st, data, pv, ac = line:match("^S|1|([^|]*)|([%d%.%-]+)|([^|]+)|?(%d?)|?(%d*)")
    if not sc then return end
    M.peer_scene[id] = sc
    M.peer_pvp[id] = pv == "1"
    ac = tonumber(ac)
    if ac == 0 then ac = nil end
    M.peer_act[id] = ac
    st = tonumber(st)
    if sc ~= scene or not st or (ac and act and ac ~= act) then
        if P[id] then drop(id) end
        return
    end
    local p = P[id]
    if not p then
        if (M.fail_t[id] or -10.0) > now - 2.0 then return end    -- (a figure that wouldn't make: again in 2 s)
        -- (up to 100 in a lobby: no more than MAX_DRAWN figures at once, for the frame rate)
        local n = 0
        for _ in pairs(P) do n = n + 1 end
        if n >= M.MAX_DRAWN then return end
        p = make(id, name, pawn)
        if not p then M.fail_t[id] = now; return end
        P[id] = p
    end
    p.scene, p.heard = sc, now
    local s = p.samples
    if #s > 0 and st <= s[#s].st then return end           -- (the same one again, or an old one)
    local d = unpack_pose(unb64(data))
    if not d then return end
    s[#s + 1] = { st = st, d = d }
    while #s > 8 do table.remove(s, 1) end
    -- (their clock against ours: the least lag seen, let out slowly so a slow spell is forgotten)
    local off = now - st
    if not p.off or off < p.off then p.off = off else p.off = p.off + (off - p.off) * 0.01 end
end

-- ------------------------------------------------------------------------------------------- PvP
-- "Can players hurt each other?" - "lets do both add an option in mario settigns", then "add the pvp switch to online
-- tab" (2026-11-01): PVP ON/OFF on the ONLINE tab's screen (mpmenu.lua), off at first. With it on for both, his punches and kicks hurt a friend in front of him - the friend's
-- game hurts its own Mario the way the game's enemies do (health.lua M.damage) and knocks him back (G.knock_down).
local PVP_FILE = lib.MOD_DIR .. "mp_settings.txt"
local pvp = nil
function M.pvp()
    if pvp == nil then
        pvp = false
        local f = io.open(PVP_FILE, "r")
        if f then pvp = (f:read("*a") or ""):find("pvp=1", 1, true) ~= nil; f:close() end
    end
    return pvp
end
function M.set_pvp(v)
    local on = (tonumber(v) or 0) >= 0.5
    if on == M.pvp() then return end
    pvp = on
    local f = io.open(PVP_FILE, "w")
    if f then f:write("pvp=", on and "1" or "0", "\n"); f:close() end
    log("multiplayer: PvP %s", on and "on" or "off")
end
M.peer_pvp = {}
M.PUNCH = { wedges = 2, kick = 3, reach = 150.0, up = 130.0, push = 450.0, lift = 260.0 }

local punch_seen, punch_due = nil, nil
local function punch_tick(G, pawn, now)
    if not M.pvp() then return end
    local at = G.punch_at
    if at and at ~= punch_seen then
        punch_seen = at
        punch_due = { t = now + 0.15, kick = G.punch_chain == 3 }     -- (as the fist or foot gets there)
    end
    local d = punch_due
    if not (d and now >= d.t) then return end
    punch_due = nil
    local l, f = pawn:K2_GetActorLocation(), pawn:GetActorForwardVector()
    for id, p in pairs(P) do
        if id ~= "mirror" and M.peer_pvp[id] then
            local ok, t = pcall(function() return p.actor:K2_GetActorLocation() end)
            if ok and t then
                local dx, dy, dz = t.X - l.X, t.Y - l.Y, t.Z - l.Z
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < M.PUNCH.reach and math.abs(dz) < M.PUNCH.up and (dist < 1.0 or (dx * f.X + dy * f.Y) / dist > 0.2) then
                    local nx, ny = dist > 1.0 and dx / dist or f.X, dist > 1.0 and dy / dist or f.Y
                    M.send_event("hit", string.format("%d|%.3f|%.3f", d.kick and M.PUNCH.kick or M.PUNCH.wedges, nx, ny), id)
                    log("multiplayer: hit %s", p.name or id)
                end
            end
        end
    end
end

-- a friend's punch or kick on him: hurt and pushed back, if PvP is on here too
M.on_event.hit = function(from, body)
    if not M.pvp() then return end
    local w, nx, ny = body:match("^(%d+)|([%d%.%-]+)|([%d%.%-]+)$")
    w, nx, ny = tonumber(w), tonumber(nx), tonumber(ny)
    if not (w and nx and ny) then return end
    local HP, G, pawn = _G.HEALTH, package.loaded["game"], lib.pawn()
    if not (HP and HP.damage and G and pawn) then return end
    local ok, hurt = pcall(HP.damage, math.max(1, math.min(4, w)), "a friend's punch")
    if ok and hurt and G.knock_down then pcall(G.knock_down, pawn, nx * M.PUNCH.push, ny * M.PUNCH.push, M.PUNCH.lift) end
end

-- ------------------------------------------------------------------------------------------- each tick

local status_t, send_t, read_t = 0.0, 0.0, 0.0
local last_scene = nil

-- ------------------------------------------------------------------------------------- the host's file, shared
-- "when joining someone tell the player how much stars and what gamemodes are in the server. The host players file
-- should be shared between other players", 2026-11-03. The host sends the file it plays (its stars, keys, cap
-- switches, coin scores, HUMAN and IRONMAN) as someone joins, as it changes and every FILE_EVERY s; in pieces, an event
-- holding no more than 1100 bytes. A player in someone else's game plays that file (menu.lua M.mp_file: his own put
-- by), and is told its stars and modes as he gets it (data/dialogs_extra.lua 9010-9013); what he gets in it goes to the
-- host (M.on_change), who sends the file on again. Out of the game, his own file again (M.mp_leave).
M.FILE_EVERY = 30.0
M.FILE_PIECE = 900
local file_seq, file_t, file_dirty, file_members = 0, -100.0, false, 0
local file_in = {}                -- (pieces come in: seq -> { n, have, parts })
local function is_host() return M.in_lobby() and M.status.owner ~= nil and M.status.owner == M.status.me end
local function file_text(f)
    local got = {}
    for k in pairs(f.got or {}) do got[#got + 1] = k end
    table.sort(got)
    local coins = {}
    for c, n in pairs(f.coins or {}) do coins[#coins + 1] = tostring(c) .. "=" .. tostring(n) end
    return table.concat({ tostring(f.stars or 0), f.human and "1" or "0", f.ironman and "1" or "0",
                          table.concat(got, ","), table.concat(coins, ",") }, ";")
end
local function file_from(text)
    local stars, h, i, got, coins = text:match("^(%d+);([01]);([01]);([^;]*);?(.*)$")
    if not stars then return nil end
    local t = { stars = tonumber(stars), human = (h == "1") or nil, ironman = (i == "1") or nil, got = {}, coins = {} }
    for k in got:gmatch("[^,]+") do t.got[k] = true end
    for c, n in coins:gmatch("(%d+)=(%d+)") do t.coins[tonumber(c)] = tonumber(n) end
    return t
end
local function send_file()
    local MN = _G.MENU
    local f = MN and MN.mp_snapshot and MN.mp_snapshot()
    file_t, file_dirty = os.clock(), false
    if not f then return end
    local text = file_text(f)
    file_seq = file_seq + 1
    local n = math.max(1, math.ceil(#text / M.FILE_PIECE))
    for i = 1, n do
        M.send_event("file", string.format("%d|%d|%d|%s", file_seq, i, n, text:sub((i - 1) * M.FILE_PIECE + 1, i * M.FILE_PIECE)))
    end
end
local pending_file = nil
local function take_file(t)
    local MN = _G.MENU
    if not (MN and MN.mp_file and MN.state == "game") then pending_file = t; return end
    pending_file = nil
    if MN.mp_file(t) then
        log("multiplayer: playing the host's file - %d stars%s%s", t.stars or 0, t.human and ", HUMAN MODE" or "",
            t.ironman and ", IRONMAN MODE" or "")
        M.join_note = { stars = t.stars or 0, id = 9010 + (t.human and 1 or 0) + (t.ironman and 2 or 0) }
    end
end
M.on_event.file = function(from, body)
    if from ~= M.status.owner or is_host() then return end
    local seq, i, n, part = body:match("^(%d+)|(%d+)|(%d+)|(.*)$")
    seq, i, n = tonumber(seq), tonumber(i), tonumber(n)
    if not (seq and i and n) then return end
    local e = file_in[seq]
    if not e then e = { n = n, have = 0, parts = {} }; file_in[seq] = e end
    if not e.parts[i] then e.parts[i] = part; e.have = e.have + 1 end
    if e.have < e.n then return end
    file_in = {}
    local t = file_from(table.concat(e.parts))
    if t then take_file(t) end
end
-- (the host: what someone else got in its file, put in it - and so sent on to all)
M.on_event.got = function(from, body)
    if not is_host() then return end
    local MN = _G.MENU
    if not MN then return end
    local kind, a, b = body:match("^(%a+)|([^|]*)|?(.*)$")
    if kind == "star" then MN.add_star(a)
    elseif kind == "flag" then MN.add_flag(a)
    elseif kind == "unflag" then MN.remove_flag(a)
    elseif kind == "key" then MN.add_key(tonumber(a) or a)
    elseif kind == "coins" and tonumber(a) and tonumber(b) then MN.note_coins(tonumber(a), tonumber(b)) end
    file_dirty = true
end
-- (menu.lua tells this of every change to the file being played)
local function on_change(kind, a, b)
    if not M.in_lobby() then return end
    if is_host() then file_dirty = true; return end
    local MN = _G.MENU
    if MN and MN.mp_shared and MN.mp_shared() then
        M.send_event("got", string.format("%s|%s|%s", kind, tostring(a), tostring(b or "")), M.status.owner)
    end
end
local function file_tick(G, now)
    local MN = _G.MENU
    if MN and MN.on_change ~= on_change then MN.on_change = on_change end
    if is_host() then
        local n = M.others()
        if n > file_members or file_dirty and now - file_t > 0.5 or (n > 0 and now - file_t > M.FILE_EVERY) then send_file() end
        file_members = n
    else
        file_members = 0
        if pending_file then take_file(pending_file) end
    end
    -- (told, once he is free to read it)
    if M.join_note and G.name and not G.warping and not G.pending and not G.dying and not G.cutscene then
        local D, S = package.loaded["dialog"], package.loaded["starselect"]
        if not ((D and D.active) or (S and S.active)) then
            local j = M.join_note
            M.join_note = nil
            if G.say then pcall(G.say, j.id, nil, { fill = { tostring(j.stars) } }) end
        end
    end
end

-- IRONMAN in a shared game ("for multiplayer with iron man, make it so if the connected players disconnect and cannot
-- reconnect after death", 2026-11-04): dead in an IRONMAN game someone else hosts (menu.lua M.ironman_wipe), the host
-- told, the game left, and that lobby kept (net\ironman_dead.txt, over restarts) - never joined again: M.join refuses
-- it, and found in it all the same (a friend's invite, Steam's Join Game) he leaves it at once, and is told (DIALOG
-- 9023). The host keeps who died in its game and turns them away as they come back (an event to them: "kicked").
M.DEAD_FILE = NET .. "ironman_dead.txt"
M.KICK_EVERY = 2.0
function M.dead_load()
    if M.dead_in then return M.dead_in end
    M.dead_in = {}
    local f = io.open(M.DEAD_FILE, "r")
    if f then
        for line in f:lines() do local id = line:match("^(%d+)") if id then M.dead_in[id] = true end end
        f:close()
    end
    return M.dead_in
end
function M.dead_in_lobby(id) return M.dead_load()[tostring(id or "")] == true end
function M.died_here()
    local lob = M.status.lobby
    if not (lob and lob ~= "" and lob ~= "0") then return end
    local t = M.dead_load()
    if not t[lob] then
        t[lob] = true
        local f = io.open(M.DEAD_FILE, "a")
        if f then f:write(lob, "\n"); f:close() end
    end
    if M.status.owner and M.status.owner ~= M.status.me then M.send_event("dead", "ironman", M.status.owner) end
    log("multiplayer: IRONMAN - dead in lobby %s: no way back into it", lob)
end
M.host_dead = {}
M.on_event.dead = function(from)
    if not (M.in_lobby() and M.status.owner == M.status.me) then return end
    M.host_dead[from] = M.status.lobby
    log("multiplayer: IRONMAN - %s died in this game: kept out", tostring(from))
end
M.on_event.kicked = function(from)
    if not (M.in_lobby() and from == M.status.owner and M.status.owner ~= M.status.me) then return end
    local lob = M.status.lobby
    if lob and lob ~= "0" then
        local t = M.dead_load()
        if not t[lob] then
            t[lob] = true
            local f = io.open(M.DEAD_FILE, "a")
            if f then f:write(lob, "\n"); f:close() end
        end
    end
    M.turned_away = true
    cmd("leave")
    log("multiplayer: IRONMAN - turned away by the host: died in its game")
end
function M.ironman_tick(G, now)
    local lob = M.in_lobby() and M.status.lobby or nil
    -- (in a game he died in: out of it at once)
    if lob and M.status.owner ~= M.status.me and M.dead_in_lobby(lob) and not M.leaving_dead then
        M.leaving_dead = true
        M.turned_away = true
        cmd("leave")
        log("multiplayer: IRONMAN - in lobby %s, where he died: left it", lob)
    end
    if not lob then M.leaving_dead = nil end
    -- (the host: those who died here, turned away while they are in it)
    if lob and M.status.owner == M.status.me and next(M.host_dead) and now - (M.kick_t or 0.0) >= M.KICK_EVERY then
        M.kick_t = now
        for _, m in ipairs(M.status.members) do
            if M.host_dead[m.id] == lob then M.send_event("kicked", "ironman", m.id) end
        end
    end
    -- (and told, once he is free to read it)
    if M.turned_away and G and G.name and not G.warping and not G.pending and not G.dying and not G.cutscene then
        local D = package.loaded["dialog"]
        if not (D and D.active) and G.say then
            M.turned_away = nil
            pcall(G.say, 9023)
        end
    end
end

function M.tick(dt, G)
    if not started then return end
    local now = os.clock()
    if M.ironman_tick then pcall(M.ironman_tick, G, now) end
    -- (the game's chat: chat.lua - Enter on the keyboard)
    do
        local CH = package.loaded["chat"]
        if CH and CH.tick then pcall(CH.tick, dt) end
    end
    if now - status_t > 0.25 then
        status_t = now
        read_status()
        if not callbacks_on and fn_callbacks and M.status.state ~= "off" then
            callbacks_on = true
            pcall(fn_callbacks)
        end
    end
    local scene = G.name
    if scene ~= last_scene then
        last_scene = scene
        M.drop_all()
        if scene and M.in_lobby() then cmd("scene " .. scene) end
    end
    -- (just in someone else's lobby: to the host's level, beside them, once it is known)
    local lobby = M.in_lobby() and M.status.lobby or nil
    if lobby ~= M.joined_lobby then
        M.joined_lobby = lobby
        M.peer_scene = {}
        M.peer_act = {}
        -- (left someone's game, or now the host of one: his own file again)
        if not lobby or M.status.owner == M.status.me then
            local MN = _G.MENU
            if MN and MN.mp_shared and MN.mp_shared() then MN.mp_leave(); log("multiplayer: his own file again") end
            pending_file, M.join_note = nil, nil
        end
        M.follow_host = lobby and M.status.owner ~= M.status.me or nil
        if scene and lobby then cmd("scene " .. scene) end
    end
    if M.follow_host and M.status.owner and M.peer_scene[M.status.owner] then
        M.follow_host = nil
        M.go_to(M.status.owner)
    end
    pcall(file_tick, G, now)
    local pawn = lib.pawn()
    if pawn and scene then follow_tick(G, pawn, now) end
    if pawn and scene then pcall(punch_tick, G, pawn, now) end
    local live = (M.in_lobby() and M.others() > 0) or M.MIRROR
    if not (pawn and scene and live) then
        if next(P) then M.drop_all() end
        return
    end
    -- his state, 20 times a second
    if now - send_t >= 1.0 / M.RATE then
        send_t = now
        local ok, data = pcall(my_pose, pawn)
        if ok and data then
            local line = string.format("S|1|%s|%.3f|%s|%s|%d", scene, now, b64(data), M.pvp() and "1" or "0", G.act or 0)
            if M.in_lobby() and M.others() > 0 then
                local f = io.open(NET .. "me.txt", "w")
                if f then f:write(line, "\n"); f:close() end
            end
            if M.MIRROR then M.mirror_line = line end
        end
    end
    -- the others' states, as the DLL has them
    if now - read_t >= 1.0 / 30.0 then
        read_t = now
        local seen = {}
        if M.in_lobby() then
            local f = io.open(NET .. "peers.txt", "r")
            local text = f and f:read("*a")
            if f then f:close() end
            for line in (text or ""):gmatch("[^\n]+") do
                local id, age, name, rest = line:match("^(%d+)|(%d+)|([^|]*)|(.*)$")
                if id and tonumber(age) < M.STALE * 1000 then
                    seen[id] = true
                    heard(id, name, rest, now, pawn, scene, G.act)
                end
            end
        end
        if M.MIRROR and M.mirror_line then
            seen.mirror = true
            heard("mirror", "Mirror", M.mirror_line, now, pawn, scene, G.act)
        end
        for id in pairs(P) do if not seen[id] then drop(id) end end
    end
    -- events
    if M.in_lobby() then
        local taken = NET .. "in_events.take"
        if os.rename(NET .. "in_events.txt", taken) then
            local f = io.open(taken, "r")
            local text = f and f:read("*a")
            if f then f:close() end
            os.remove(taken)
            for line in (text or ""):gmatch("[^\n]+") do
                local from, kind, body = line:match("^(%d+)|([^|]+)|?(.*)$")
                local h = from and M.on_event[kind]
                if h then pcall(h, from, body) end
            end
        end
    end
    for id, p in pairs(P) do
        if id == "mirror" then
            -- (the mirror: his own pose, M.MIRROR_SIDE cm to his right)
            local side = { 0.0, 0.0 }
            pcall(function()
                local r = pawn:GetActorRightVector()
                side = { r.X * M.MIRROR_SIDE, r.Y * M.MIRROR_SIDE }
            end)
            pcall(draw, p, now, side)
        else
            pcall(draw, p, now)
        end
    end
end

function M.forget()
    for id, p in pairs(P) do if p.addr then lib.keep[p.addr] = nil end end
    P = {}
    last_scene = nil
end

return M
