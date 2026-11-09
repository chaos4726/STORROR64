-- SM64Map: Mario 64's round shadows (game/shadow.c) under the athlete and the creatures.
--
-- The levels are drawn unlit, and an unlit floor takes no shadow: the athlete had none at all, and how high he was
-- over a ledge, or where a jump would come down, could not be judged ("adding upgrading and improving", 2026-10-18).
-- Mario 64 puts a soft dark circle on the floor under Mario and under most things (GEO_SHADOW in their geo layouts:
-- data/shadows.lua, taken from the decomp - its solidity and size in units). Here: a flat see-through quad with the
-- game's own shadow picture (its quarter circle mirrored round, textures/shadow_circle.png), set on the floor under
-- each one every frame, tilted with the floor, and smaller the higher he is over it - Mario 64's
-- scale_shadow_with_distance: full size on the floor, half at 600 units up and above.
local lib = require("lib")
local log = lib.log

local M = { enabled = true }

local OFFSET = lib.OFFSET
local TEX = "shadow_circle"
local U = 0.75
local PLAYER_SIZE = 120.0           -- cm across under the athlete: Mario's 100 units, for a figure a good deal bigger
local PLAYER_SOLID = 0xB4           -- Mario's solidity
local HALF_AT = 600.0 * U           -- (cm) at this height and above, half size
local FAR = 9000.0                  -- creatures further than this from the athlete: no shadow (and not looked at)
local LIFT = 2.5                    -- cm over the floor (1.5 flickered into steep slopes far off)

local SIZES = nil                   -- geo name -> { type, solidity, size }
local player = nil                  -- { actor, k }
local shadows = {}                  -- enemy entry -> { actor, k, d }
local world_addr = nil

local function valid(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

-- A creature's actor found destroyed while it is still on its list is never touched again (keyed by the wrapper Lua
-- holds, so a new actor at the same address is not mistaken for it). Asked where it was once the engine had freed it,
-- the game crashed: 2026-10-27 16:46 in Bob-omb Battlefield, K2_GetActorLocation from M.tick's `one` on the dump's
-- stack - and the same crash 2026-10-18 09:52, eight minutes after this file went in. Which list kept it, logged once.
local gone = setmetatable({}, { __mode = "k" })
local function what(key)
    if type(key) ~= "table" then return tostring(key) end
    if key.type then return tostring(key.type) end
    if key.kind then return tostring(key.kind) end
    if key.seg then return "chain chomp" end
    if key.marker ~= nil or key.won ~= nil then return "star" end
    if key.state and key.scale then return "goomba" end
    return "creature"
end
local function alive(key, actor)
    if gone[actor] then return false end
    if valid(actor) then return true end
    gone[actor] = true
    log("shadows: a %s's actor was destroyed while still on its list - left alone from now on", what(key))
    return false
end

local function make(world, solid)
    local actor = lib.spawn_actor(world, { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z - 20000.0 }, 0.0)
    if not actor then return nil end
    -- (kept from the scene's sweep of stale actors: these are let go here, by hand)
    pcall(function() lib.keep[actor:GetAddress()] = "shadow" end)
    local pmc = lib.add_pmc(actor)
    if not pmc then return nil end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    local a = (solid or 0xB4) / 255.0
    lib.add_sections(world, pmc, { {
        id = 0, layer = "translucent", texture = TEX, nverts = 4, ntris = 2,
        pos = { -50, -50, 0, 50, -50, 0, 50, 50, 0, -50, 50, 0 },
        uv = { 0, 0, 1, 0, 1, 1, 0, 1 },
        col = { 0, 0, 0, a, 0, 0, 0, a, 0, 0, 0, a, 0, 0, 0, a },
        nrm = { 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1 },
        idx = { 0, 2, 1, 0, 3, 2 },
    } })
    return { actor = actor, k = -1.0, shown = true }
end

local function let_go(s)
    if not s then return end
    pcall(function() lib.keep[s.actor:GetAddress()] = nil end)
    pcall(lib.retire, s.actor)
end

local function hide(s)
    if s.shown then
        s.shown = false
        pcall(function() s.actor:SetActorHiddenInGame(true) end)
    end
end

-- the floor under (x, y) at or below z (scene cm), with its normal: the level's and the moving platforms'
local function floor_under(G, x, y, z)
    local fz, nx, ny, nz = nil, 0.0, 0.0, 1.0
    if G.floor_normal then fz, nx, ny, nz = G.floor_normal(x, y, z) end
    local P = G.PLAT
    local pz = P and P.floor_under and P.floor_under(x, y, z)
    if pz and (not fz or pz > fz) then fz, nx, ny, nz = pz, 0.0, 0.0, 1.0 end
    -- (over water, on its surface, as Mario 64 draws it - not on the bed far below)
    for _, r in ipairs(G.water_rects or {}) do
        if x > r.x0 and x < r.x1 and y > r.y0 and y < r.y1 and r.z <= z and (not fz or r.z > fz) then
            fz, nx, ny, nz = r.z, 0.0, 0.0, 1.0
        end
    end
    return fz, nx or 0.0, ny or 0.0, nz or 1.0
end

-- put shadow `s` (size `d` cm across) under the point (x, y, z), scene cm
local function place(G, s, x, y, z, d)
    local fz, nx, ny, nz = floor_under(G, x, y, z + 40.0)
    if not fz or z - fz > 8000.0 then hide(s); return end
    local h = math.max(0.0, z - fz)
    local k = (d / 100.0) * ((h >= HALF_AT) and 0.5 or (1.0 - 0.5 * h / HALF_AT))
    -- (tilted to lie on the floor: its up turned to the floor's normal)
    local pitch = -math.deg(math.atan(nx, nz))
    local roll = math.deg(math.atan(ny, math.sqrt(nx * nx + nz * nz)))
    pcall(function()
        s.actor:K2_TeleportTo({ X = x + OFFSET.X, Y = y + OFFSET.Y, Z = fz + LIFT + OFFSET.Z }, { Pitch = pitch, Yaw = 0.0, Roll = roll })
    end)
    if math.abs(k - s.k) > 0.01 then
        s.k = k
        pcall(function() s.actor:SetActorScale3D({ X = k, Y = k, Z = 1.0 }) end)
    end
    if not s.shown then
        s.shown = true
        pcall(function() s.actor:SetActorHiddenInGame(false) end)
    end
end

-- The athlete's own shadow, in real time: his body cast by the sun the levels' shadows are baked with (menu.lua M.SUN)
-- onto the floor - each part of him (hips and chest, shoulders, neck and head, upper and lower arms and hands, thighs,
-- shins, feet and toes) a soft dark shape from bone to bone, laid along the sun's rays where they meet the floor, every
-- frame: it runs, flips and climbs with him ("build the shadows", 2026-10-30, for "the actual player has no shadow other
-- than a circle"). The levels are drawn unlit, so the engine's own shadows cannot fall on them; his round one goes.
M.BODY = false                      -- (off: the levels are lit and the engine casts his real shadow - game.lua G.LIT_LEVELS)
local BODY_SOLID = 0.6
local BODY_TEX = "shadow_body"     -- (solid to three quarters out, soft over the last: Mario 64's circle, all soft, made a
                                    -- thin arm or leg a faint smudge - "no shadow", 2026-10-30)
local BODY_MAX_UP = 4000.0          -- (cm) higher than this over the floor, none
-- { from bone, to bone (or nil: on from `from` the way its parent points, `len` cm), width cm, len, parent }
local BODY_PARTS = {
    { "pelvis", "spine_03", 38.0 }, { "spine_03", "neck_01", 42.0 }, { "upperarm_l", "upperarm_r", 16.0 },
    { "neck_01", "Head", 16.0 }, { "Head", nil, 28.0, 18.0, "neck_01" },
    { "upperarm_l", "lowerarm_l", 15.0 }, { "lowerarm_l", "hand_l", 13.0 }, { "hand_l", nil, 12.0, 10.0, "lowerarm_l" },
    { "upperarm_r", "lowerarm_r", 15.0 }, { "lowerarm_r", "hand_r", 13.0 }, { "hand_r", nil, 12.0, 10.0, "lowerarm_r" },
    { "thigh_l", "calf_l", 21.0 }, { "calf_l", "foot_l", 16.0 }, { "foot_l", "ball_l", 13.0 }, { "ball_l", nil, 12.0, 9.0, "foot_l" },
    { "thigh_r", "calf_r", 21.0 }, { "calf_r", "foot_r", 16.0 }, { "foot_r", "ball_r", 13.0 }, { "ball_r", nil, 12.0, 9.0, "foot_r" },
}
local CORNERS = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } }
local body = nil                    -- { actor, pmc, uvs, cols, shown }
local fnames = {}
local function fname(n) local f = fnames[n]; if not f then f = FName(n); fnames[n] = f end; return f end

local function sun_dir()
    local MN = _G.MENU
    local sun = (MN and MN.SUN) or { 65.0, 35.0 }
    local el, az = math.rad(sun[1]), math.rad(sun[2])
    return math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)
end

local function body_make(world)
    local actor = lib.spawn_actor(world, { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z }, 0.0)
    if not actor then return nil end
    pcall(function() lib.keep[actor:GetAddress()] = "shadow" end)
    local pmc = lib.add_pmc(actor)
    if not pmc then return nil end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    local n = #BODY_PARTS
    local pos, uv, col, nrm, idx = {}, {}, {}, {}, {}
    -- (made with its first two corners at one far corner of the level and its other two at the opposite one: two
    -- triangles of no size, nothing drawn, but its bounds the whole level - the engine sizes a mesh by the corners it is
    -- made with, and one made down out of sight was never drawn where its corners went: "no shadow?", 2026-10-30)
    local FAR_C = { { -100000.0, -100000.0, -20000.0 }, { -100000.0, -100000.0, -20000.0 },
                    { 100000.0, 100000.0, 20000.0 }, { 100000.0, 100000.0, 20000.0 } }
    for i = 0, n - 1 do
        for k, c in ipairs(CORNERS) do
            local f = (i == 0) and FAR_C[k] or { 0.0, 0.0, -20000.0 }
            pos[#pos + 1], pos[#pos + 2], pos[#pos + 3] = f[1], f[2], f[3]
            uv[#uv + 1], uv[#uv + 2] = c[1], c[2]
            col[#col + 1], col[#col + 2], col[#col + 3], col[#col + 4] = 0.0, 0.0, 0.0, BODY_SOLID
            nrm[#nrm + 1], nrm[#nrm + 2], nrm[#nrm + 3] = 0.0, 0.0, 1.0
        end
        local b = i * 4
        for _, k in ipairs({ 0, 2, 1, 0, 3, 2 }) do idx[#idx + 1] = b + k end
    end
    lib.add_sections(world, pmc, { { id = 0, layer = "translucent", texture = BODY_TEX, nverts = n * 4, ntris = n * 2,
                                      pos = pos, uv = uv, col = col, nrm = nrm, idx = idx } })
    local uvs, cols = {}, {}
    for i = 1, n * 4 do
        local c = CORNERS[((i - 1) % 4) + 1]
        uvs[i] = { X = c[1], Y = c[2] }
        cols[i] = { R = 0.0, G = 0.0, B = 0.0, A = BODY_SOLID }
    end
    return { actor = actor, pmc = pmc, uvs = uvs, cols = cols, shown = true }
end

local function body_hide()
    if body and body.shown then
        body.shown = false
        pcall(function() body.actor:SetActorHiddenInGame(true) end)
    end
end

-- each frame: his bones, laid on the floor along the sun
local function body_tick(G, pawn, world, px, py, pz)
    if body and not valid(body.actor) then body = nil end
    if not body then body = body_make(world) end
    if not body then return end
    local mesh = nil
    pcall(function() mesh = pawn.Mesh end)
    if not valid(mesh) then body_hide(); return end
    local base = floor_under(G, px, py, pz + 40.0)
    if not base or pz - base > BODY_MAX_UP then body_hide(); return end
    local dx, dy, dz = sun_dir()
    -- (each bone's point where the ray to the sun through it meets the floor - the floor there, a step up or down)
    local at = {}
    local function ground(name)
        local g = at[name]
        if g ~= nil then return g end
        local w = nil
        pcall(function() w = mesh:GetSocketLocation(fname(name)) end)
        if not w then at[name] = false; return false end
        local x, y, z = w.X - OFFSET.X, w.Y - OFFSET.Y, w.Z - OFFSET.Z
        local t = (z - base) / dz
        local gx, gy = x - dx * t, y - dy * t
        local fz = floor_under(G, gx, gy, base + 120.0) or base
        if fz > z then fz = base end
        t = (z - fz) / dz
        g = { x - dx * t, y - dy * t, fz, x, y, z }
        at[name] = g
        return g
    end
    local verts = {}
    for i, part in ipairs(BODY_PARTS) do
        local a = ground(part[1])
        local b = part[2] and ground(part[2]) or nil
        if a and not part[2] and part[5] then
            -- (on from the bone the way its parent points: the head past the neck, the hand past the wrist)
            local pa = ground(part[5])
            if pa then
                local ux, uy, uz = a[4] - pa[4], a[5] - pa[5], a[6] - pa[6]
                local l = math.sqrt(ux * ux + uy * uy + uz * uz)
                if l > 0.001 then
                    local k = part[4] / l
                    local x, y, z = a[4] + ux * k, a[5] + uy * k, a[6] + uz * k
                    local t = (z - a[3]) / dz
                    b = { x - dx * t, y - dy * t, a[3] }
                end
            end
        end
        local v0 = (i - 1) * 4
        if a and b then
            local ux, uy = b[1] - a[1], b[2] - a[2]
            local l = math.sqrt(ux * ux + uy * uy)
            if l < 0.01 then ux, uy, l = 1.0, 0.0, 1.0 end
            ux, uy = ux / l, uy / l
            local r = part[3] * 0.5
            local nx, ny = -uy * r, ux * r
            local ex, ey = ux * r, uy * r
            local za, zb = a[3] + LIFT, b[3] + LIFT
            verts[v0 + 1] = { X = a[1] - ex - nx, Y = a[2] - ey - ny, Z = za }
            verts[v0 + 2] = { X = b[1] + ex - nx, Y = b[2] + ey - ny, Z = zb }
            verts[v0 + 3] = { X = b[1] + ex + nx, Y = b[2] + ey + ny, Z = zb }
            verts[v0 + 4] = { X = a[1] - ex + nx, Y = a[2] - ey + ny, Z = za }
        else
            for k = 1, 4 do verts[v0 + k] = { X = 0.0, Y = 0.0, Z = -20000.0 } end
        end
    end
    pcall(lib.update_section, body.pmc, 0, verts, body.cols, body.uvs)
    if not body.shown then
        body.shown = true
        pcall(function() body.actor:SetActorHiddenInGame(false) end)
    end
end

function M.forget()
    let_go(player)
    player = nil
    let_go(body)
    body = nil
    for _, s in pairs(shadows) do let_go(s) end
    shadows = {}
end

function M.tick(dt, pawn)
    if not M.enabled then return end
    -- (the pictures' shadow twins: each casting only while its picture is shown - lib.sync_twins)
    pcall(lib.sync_twins, dt)
    local G = package.loaded["game"]
    if not (G and G.name and pawn) then return end
    local world = lib.world()
    if not world then return end
    local here = nil
    pcall(function() here = world:GetAddress() end)
    if here ~= world_addr then
        -- (a new map: the old actors went with it - only forgotten)
        world_addr, player, shadows, body = here, nil, {}, nil
    end
    if SIZES == nil then SIZES = lib.load_data("data.shadows") or false end

    -- the athlete's
    if player and not valid(player.actor) then player = nil end
    if not player then player = make(world, PLAYER_SOLID) end
    local l = pawn:K2_GetActorLocation()
    local px, py, pz = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - (G.half or 90.0)
    if player then
        local hidden = false
        pcall(function() hidden = pawn.bHidden end)
        -- (a lit level takes his real shadow from the engine: no round one - "it should show a real shadow of the player
        -- not circles", 2026-10-30)
        if G.LIT_LEVELS then
            hide(player)
            body_hide()
        elseif G.swim or hidden or G.cutscene_noshadow then
            hide(player)
            body_hide()
        elseif M.BODY then
            hide(player)
            local okb, errb = pcall(body_tick, G, pawn, world, px, py, pz)
            if not okb then
                if not M.body_err then M.body_err = true; log("shadows: his body's shadow failed (%s) - his round one back", tostring(errb)) end
                body_hide()
                place(G, player, px, py, pz, PLAYER_SIZE)
            end
        else
            body_hide()
            place(G, player, px, py, pz, PLAYER_SIZE)
        end
    end

    -- the creatures': every list of them, each with its model's shadow (its geo layout's), sized by its own scale as
    -- Mario 64's are (the object's scale times the layout's)
    local seen = {}
    -- (x, y, z: its foot, scene cm; still there since the last frame, its shadow is left where it is)
    local function at(key, x, y, z, hid, geo, sc)
        local spec = geo and SIZES[geo]
        if not spec then return end
        seen[key] = true
        local s = shadows[key]
        if hid or (x - px) ^ 2 + (y - py) ^ 2 > FAR * FAR then
            if s then hide(s) end
            return
        end
        if not s or not valid(s.actor) then
            s = make(world, spec[2])
            shadows[key] = s
            if not s then return end
        end
        if s.shown and s.lx and math.abs(s.lx - x) < 0.5 and math.abs(s.ly - y) < 0.5 and math.abs(s.lz - z) < 0.5 then return end
        s.lx, s.ly, s.lz = x, y, z
        place(G, s, x, y, z, spec[3] * U * (sc or 1.0))
    end
    local function one(key, actor, geo)
        if not (actor and geo and SIZES[geo]) then return end
        if not alive(key, actor) then return end
        local el, hid, sc = nil, true, 1.0
        pcall(function() el = actor:K2_GetActorLocation(); hid = actor.bHidden; sc = actor:GetActorScale3D().X end)
        if not el then return end
        at(key, el.X - OFFSET.X, el.Y - OFFSET.Y, el.Z - OFFSET.Z, hid, geo, sc)
    end
    if SIZES and not G.LIT_LEVELS then
        local EN = package.loaded["enemies"]
        for _, e in ipairs((EN and EN.list) or {}) do
            if not e.dead and not (e.alpha and e.alpha < 0.5) then one(e, e.inst and e.inst.actor, e.o and e.o.geo) end
        end
        for _, g in ipairs(G.goombas or {}) do one(g, g.inst and g.inst.actor, "goomba_geo") end
        local BO = package.loaded["bobomb"]
        local BOMB_GEO = { bobomb = "black_bobomb_geo", bobomb_buddy = "bobomb_buddy_geo", king_bobomb = "king_bobomb_geo" }
        for _, b in ipairs((BO and BO.list) or {}) do
            if not b.dead and not b.gone then one(b, b.inst and b.inst.actor, BOMB_GEO[b.kind]) end
        end
        local CH = package.loaded["chomp"]
        for _, c in ipairs((CH and CH.list) or {}) do one(c, c.inst and c.inst.actor, "chain_chomp_geo") end
        if G.bowser then one(G.bowser, G.bowser.inst and G.bowser.inst.actor, "bowser_shadow_geo") end
    end
    if SIZES and not G.LIT_LEVELS then
        -- the coins, 1-ups and stars (yellow_coin_geo and the rest: Mario 64 gives them theirs too. With real-time
        -- shadows they cast their own, the coins through twins turned to the sun - lib.shade_twin)
        local COIN_GEO = { coin = "yellow_coin_geo", red = "red_coin_geo", blue = "blue_coin_geo", oneup = "mushroom_1up_geo" }
        for _, c in ipairs(G.coins or {}) do
            local geo = COIN_GEO[c.kind]
            if geo then
                local shown = false
                if not c.gone and c.quads then for i = 1, #c.quads do if c.hidden and c.hidden[i] == false then shown = true; break end end end
                at(c, c.x, c.y, c.z - ((c.K and c.K.half) or 24.0), not shown, geo, 1.0)
            end
        end
        for _, st in ipairs(G.stars or {}) do
            if not st.marker then one(st, st.inst and st.inst.actor, st.won and "transparent_star_geo" or "star_geo") end
        end
    end
    for e, s in pairs(shadows) do
        if not seen[e] then let_go(s); shadows[e] = nil end
    end
end

return M
