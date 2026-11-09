-- SM64Map: Mario 64's moving textures that are meshes of their own (game/moving_texture.c gMovtexNonColored):
-- the castle grounds' waterfall, Tall Tall Mountain's waterfalls, the lava of Lethal Lava Land and Bowser in the
-- Fire Sea, Shifting Sand Land's sand and quicksand, the Cavern of the Metal Cap's stream and Tick Tock Clock's
-- treadmills. Each is built once with the scene and its texture slides along it every tick, as the game's does:
-- `speed` tiles a frame along u, wrapping round. (exporter/movtexx.py -> data/movtex.lua)
local lib = require("lib")
local log = lib.log
local M = {}

local FPS = 30.0
local list = {}

-- See-through surfaces (the waterfalls, most of the lava) get the glTF blend material, its colour factor's alpha
-- for how see-through: the engine's translucent widget material the rest of the mod uses drew the waterfall
-- solid black (2026-10-14).
local BLEND = "/InterchangeAssets/gltf/MaterialInstances/MI_Unlit_Blend.MI_Unlit_Blend"
local serial = 0
local function see_through(world, texture, alpha)
    local parent = lib.try_load(BLEND)
    -- (the classic look's smooth tiled copy, drawn at 1/N: Mario 64's own picture showed a line at every repeat)
    local tex, n = nil, 1
    if lib.tiled_texture then tex, n = lib.tiled_texture(world, texture) else tex = lib.texture(world, texture) end
    if not (parent and tex) then return nil end
    serial = serial + 1
    local KML = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    local mid = KML:CreateDynamicMaterialInstance(world, parent, FName(string.format("SM64Movtex_%d_%d", math.floor(os.clock() * 1000), serial)), 0)
    if not (mid and mid:IsValid()) then return nil end
    mid:SetTextureParameterValue(FName("BaseColorTexture"), tex)
    mid:SetVectorParameterValue(FName("BaseColorFactor"), { R = 1.0, G = 1.0, B = 1.0, A = alpha })
    if n and n > 1 then
        pcall(function() mid:SetVectorParameterValue(FName("BaseColorTexture_OffsetScale"), { R = 0.0, G = 0.0, B = 1.0 / n, A = 1.0 / n }) end)
    end
    return mid
end

local function vec(flat, i) return { X = flat[i * 3 + 1], Y = flat[i * 3 + 2], Z = flat[i * 3 + 3] } end

-- (the treadmills' belts belong to each treadmill - Mario 64 draws them as part of the treadmill object, in its own
-- frame - and were built once at the level's origin, so no treadmill had one: "conveyer belt missing in tiktok clock",
-- 2026-10-29. Kept as templates here; each treadmill puts one on itself, M.attach)
local OBJECT_LOCAL = { MOVTEX_TREADMILL_BIG = true, MOVTEX_TREADMILL_SMALL = true }
M.templates = {}

-- A hole in a flat four-cornered surface, { x0, x1, y0, y1 } scene cm: Bowser in the Fire Sea's upper lava crosses the
-- elevator's shaft, and he rode up through it - "lava inside elevator also black plate?", then "Remove both from
-- shaft", 2026-11-07. The surface made again as the strips round the hole, its picture laid on as before.
M.HOLES = { MOVTEX_BITFS_LAVA_FIRST = { -395.0, -67.0, 1986.0, 2314.0 } }
function M.holed(e, h)
    if #e.verts ~= 12 then return nil end
    local V, U = e.verts, e.uv
    local X0, X1, Y0, Y1 = math.huge, -math.huge, math.huge, -math.huge
    for i = 1, 12, 3 do X0, X1, Y0, Y1 = math.min(X0, V[i]), math.max(X1, V[i]), math.min(Y0, V[i + 1]), math.max(Y1, V[i + 1]) end
    local z = V[3]
    -- (its picture's place as a plane over x, y: from corners 0, 1 and 3)
    local ax, ay, bx, by = V[4] - V[1], V[5] - V[2], V[10] - V[1], V[11] - V[2]
    local det = ax * by - ay * bx
    if math.abs(det) < 1e-6 then return nil end
    local function grad(k)
        local d1, d3 = U[2 + k] - U[k], U[6 + k] - U[k]
        return (d1 * by - d3 * ay) / det, (ax * d3 - bx * d1) / det
    end
    local gux, guy = grad(1)
    local gvx, gvy = grad(2)
    local function uv(x, y) return U[1] + (x - V[1]) * gux + (y - V[2]) * guy, U[2] + (x - V[1]) * gvx + (y - V[2]) * gvy end
    local hx0, hx1 = math.max(X0, h[1]), math.min(X1, h[2])
    local hy0, hy1 = math.max(Y0, h[3]), math.min(Y1, h[4])
    if hx0 >= hx1 or hy0 >= hy1 then return nil end
    local rects = { { X0, hx0, Y0, Y1 }, { hx1, X1, Y0, Y1 }, { hx0, hx1, Y0, hy0 }, { hx0, hx1, hy1, Y1 } }
    local verts, uvs, tris = {}, {}, {}
    for _, r in ipairs(rects) do
        if r[2] - r[1] > 0.5 and r[4] - r[3] > 0.5 then
            local k = #verts // 3
            for _, c in ipairs({ { r[1], r[3] }, { r[1], r[4] }, { r[2], r[4] }, { r[2], r[3] } }) do
                verts[#verts + 1], verts[#verts + 2], verts[#verts + 3] = c[1], c[2], z
                local u, v = uv(c[1], c[2])
                uvs[#uvs + 1], uvs[#uvs + 2] = u, v
            end
            for _, i in ipairs({ 0, 1, 2, 0, 2, 3 }) do tris[#tris + 1] = k + i end
        end
    end
    local out = {}
    for key, val in pairs(e) do out[key] = val end
    out.verts, out.uv, out.tris = verts, uvs, tris
    return out
end

-- one surface: on `host` (an actor it is part of, in that actor's own frame) or on an actor of its own at `origin`
local function build(world, e, host, origin)
    if M.HOLES and M.HOLES[e.id] and M.holed then e = M.holed(e, M.HOLES[e.id]) or e end
    local n = #e.verts // 3
    if n < 3 or not e.texture then return nil end
    local made = nil
    local ok, err = pcall(function()
        local actor = host or lib.spawn_actor(world, origin, 0.0)
        local pmc = actor and lib.add_pmc(actor)
        if not pmc then return end
        pcall(function() pmc:SetCollisionEnabled(0) end)
        pcall(function() pmc:SetCastShadow(false) end)
        local verts, nrms, cols = {}, {}, {}
        local col = { R = e.color[1], G = e.color[2], B = e.color[3], A = e.color[4] }
        for i = 0, n - 1 do
            verts[i + 1] = vec(e.verts, i)
            nrms[i + 1] = { X = 0.0, Y = 0.0, Z = 1.0 }
            cols[i + 1] = col
        end
        -- (both faces: the game draws these without culling, and seen from behind they must not vanish)
        local idx = {}
        for t = 0, #e.tris // 3 - 1 do
            local a, b, c = e.tris[t * 3 + 1], e.tris[t * 3 + 2], e.tris[t * 3 + 3]
            idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = a, b, c
            idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = a, c, b
        end
        -- (its picture's place on it kept near 0, a whole number of repeats taken off: the mesh keeps where the picture
        -- lies in half precision, and the further from 0 the coarser - at 32 to 64 repeats a step of a 32nd, and Bowser
        -- in the Fire Sea's lava, slow, went on by jumps about once a second: "the lava is not 60fps", "its moving at
        -- 1fps", 2026-11-07)
        local su, sv = 0.0, 0.0
        for i = 1, #e.uv, 2 do su, sv = su + e.uv[i], sv + e.uv[i + 1] end
        su, sv = math.floor(su / n + 0.5), math.floor(sv / n + 0.5)
        local uv = {}
        for i = 1, #e.uv, 2 do uv[i], uv[i + 1] = e.uv[i] - su, e.uv[i + 1] - sv end
        local s = { pmc = pmc, actor = (not host) and actor or nil, attached = host ~= nil, verts = verts, cols = cols, uv = uv,
                    n = n, speed = e.speed or 0.0, base = e.speed or 0.0, off = 0.0, id = e.id, wrap = 40.0 }
        lib.create_section(pmc, 0, verts, idx, nrms, M.uvs(s), cols, false)
        -- (RENDER 96: the lava solid, glowing, lit - water96.lua M.lava_material)
        local mid = nil
        if lib.R96 and e.texture == "movtex_texture_waterbox_lava" then
            local okw, W96 = pcall(require, "water96")
            if okw and W96 and W96.lava_material then
                local okm, m = pcall(W96.lava_material, world)
                if okm then mid = m end
            end
            -- (its picture 2.2 times a repeat: 5 repeats are 11 whole pictures, so it wraps there, the numbers small)
            if mid then s.wrap = 5.0 end
        end
        mid = mid or (e.translucent and see_through(world, e.texture, e.color[4]) or lib.get_mid(world, "opaque", e.texture))
        if mid then pmc:SetMaterial(0, mid) end
        list[#list + 1] = s
        made = s
    end)
    if not ok then log("moving texture %s: %s", tostring(e.id), tostring(err)) end
    return made
end

-- Build the scene's surfaces. `entries`: data/movtex.lua's list for the scene (or nil); `origin`: the scene's
-- origin in the world.
function M.load(world, entries, origin)
    M.clear()
    M.templates = {}
    for _, e in ipairs(entries or {}) do
        if OBJECT_LOCAL[e.id] then M.templates[e.id] = e
        else build(world, e, nil, origin) end
    end
    if #list > 0 then log("moving textures: %d", #list) end
    return #list
end

-- One of the templates put on `actor` (a treadmill), in its frame; sliding with the rest, at the speed set for it
function M.attach(world, id, actor)
    local e = M.templates[id]
    if not (e and actor) then return nil end
    local s = build(world, e, actor, nil)
    if s and M.speed_k and M.speed_k[id:sub(1, 16)] then s.speed = s.base * M.speed_k[id:sub(1, 16)] end
    return s
end

function M.uvs(s)
    local out = {}
    for i = 0, s.n - 1 do out[i + 1] = { X = s.uv[i * 2 + 1] + s.off, Y = s.uv[i * 2 + 2] } end
    return out
end

-- Every tick: each texture slides on by its speed (Mario 64 moves it once a frame, and wraps it at one tile).
function M.update(dt)
    for _, s in ipairs(list) do
        if s.speed ~= 0.0 then
            -- (wrapped at 40 tiles, not 1: a material that draws the picture more or less than once a tile - RENDER 96's
            -- lava, 2.2 times, water96.lua LAVA_SCALE - jumped by part of a picture at every wrap, "the texture keeps
            -- jumping", 2026-11-03; 40 of them are whole pictures for it, and for a tiled copy of 2, 4 or 8)
            s.off = (s.off + s.speed * dt * FPS) % (s.wrap or 40.0)
            pcall(lib.update_section, s.pmc, 0, s.verts, s.cols, M.uvs(s))
        end
    end
end

-- The textures whose id starts with `prefix` at `k` times their own speed (TTC's treadmills, as the clock's speed
-- sets them: platforms.lua)
function M.set_speed(prefix, k)
    M.speed_k = M.speed_k or {}
    M.speed_k[prefix:sub(1, 16)] = k
    for _, s in ipairs(list) do
        if s.id and s.id:sub(1, #prefix) == prefix then s.speed = (s.base or 0.0) * k end
    end
end

function M.clear()
    -- (one on a treadmill went with it, the scene's platforms torn down: forgotten, not touched)
    for _, s in ipairs(list) do if s.actor then lib.destroy(s.actor) end end
    list = {}
end

-- The map went: forget the surfaces without touching them.
function M.forget() list = {} end

function M.count() return #list end

-- The surface made from the entry `id` (its { pmc, actor, ... }), or nil: the lava race's sheet, moved by game.lua
-- G.lava_race_tick
function M.surface(id)
    for _, s in ipairs(list) do if s.id == id then return s end end
    return nil
end

return M
