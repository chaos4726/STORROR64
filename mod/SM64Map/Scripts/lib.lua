-- SM64Map shared helpers: logging, asset loading, materials, procedural-mesh building, actor instances.
local UEHelpers = require("UEHelpers")

local M = {}

local function log(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    print("[SM64Map] " .. (ok and msg or tostring(fmt)) .. "\n")
end
M.log = log

local SCRIPT_DIR = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "")
M.MOD_DIR = (SCRIPT_DIR:gsub("Scripts[/\\]$", ""))

-- every scene is built at this world offset (cm), far above the real map
M.debug = false
M.OFFSET = { X = 0.0, Y = 0.0, Z = 300000.0 }
M.ONE = { X = 1.0, Y = 1.0, Z = 1.0 }
M.ZERO_ROT = { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }
local IDENT = {
    Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 },
    Translation = { X = 0.0, Y = 0.0, Z = 0.0 },
    Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 },
}

-- ------------------------------------------------------------ engine access
-- (UE4SS's GetPlayerController searches every object in the engine - FindAllOf - at each call, ~0.2 ms, and the mod
-- asked ~50 times a frame: 11 ms of a 25 ms frame in BoB - "it feels laggy", 2026-10-16. Inside one of the mod's
-- frames - main.lua's loop, frame_begin .. frame_end - the controller, its world and the camera's place are looked up
-- once. Never kept past the frame: a map change frees the old controller, and touching it then crashes the game.)
local fc = nil
function M.frame_begin() fc = {} end
function M.frame_end() fc = nil end

function M.controller()
    if fc and fc.pc ~= nil then return fc.pc or nil end
    local pc = UEHelpers.GetPlayerController()
    if not (pc and pc:IsValid()) then pc = nil end
    if fc then fc.pc = pc or false end
    return pc
end

function M.world()
    if fc and fc.world ~= nil then return fc.world or nil end
    local w = nil
    local pc = M.controller()
    if pc then pcall(function() w = pc:GetWorld() end) end
    if not (w and w:IsValid()) then w = UEHelpers.GetWorld() end
    if not (w and w:IsValid()) then w = nil end
    if fc then fc.world = w or false end
    return w
end

function M.pawn()
    local pc = M.controller()
    if not pc then return nil end
    local p = pc.Pawn
    if p and p:IsValid() then return p end
    return nil
end

function M.camera_location(fallback)
    if fc and fc.cam then return fc.cam[1], fc.cam[2], fc.cam[3] end
    local pc = M.controller()
    if pc then
        local ok, loc = pcall(function() return pc.PlayerCameraManager:GetCameraLocation() end)
        if ok and loc then
            if fc then fc.cam = { loc.X, loc.Y, loc.Z } end
            return loc.X, loc.Y, loc.Z
        end
    end
    return fallback.X, fallback.Y, fallback.Z
end

-- RENDER 96 (M.R96): the Render96 model pack's models (github.com/Render96/ModelPack, the Render96 team's - made by
-- tools/r96_overlay.py and tools/r96_models.py with the mod's own exporter, on Mario 64's skeletons and animations) in
-- place of Mario 64's: Scripts/data_r96/actor_<name>.lua wherever there is one ("okay next lets do the enemies 3d models",
-- "also the star model", "also trees", 2026-10-31). Turned while a level is up: M.set_r96, then the game's M.on_r96.
local r96_data = {}
local function r96_data_file(rest)
    local h = r96_data[rest]
    if h == nil then
        local f = io.open(M.MOD_DIR .. "Scripts\\data_r96\\" .. rest .. ".lua", "rb")
        h = f ~= nil
        if f then f:close() end
        r96_data[rest] = h
    end
    return h
end
-- Render96's trees, as models ({ [geo] = sections }), with RENDER 96 on - or nil
local r96_trees = nil
function M.r96_trees()
    if not M.R96 then return nil end
    if r96_trees == nil then
        r96_trees = false
        if r96_data_file("trees") then
            local ok, t = pcall(require, "data_r96.trees")
            if ok and type(t) == "table" then r96_trees = t end
        end
    end
    return r96_trees or nil
end
-- A data file's chunk, quick: its compiled form (Lua bytecode, string.dump) kept in SM64Map/data_bc - named by the source
-- file's size, so an edited file is compiled anew - and the last few kept in memory. Parsing the source anew each visit
-- (a scene's file is up to 10 MB) was most of a level's load: "lag when enter levels", "next we have to do major
-- optimization", 2026-11-01. A fresh table each call (the chunk is run again): the build changes what it is given.
local chunk_mem, chunk_order = {}, {}
local CHUNK_KEEP = 6
function M.load_chunk(modname)
    local path = package.searchpath(modname, package.path)
    if not path then return nil end
    local size = nil
    pcall(function()
        local f = io.open(path, "rb")
        if f then size = f:seek("end"); f:close() end
    end)
    local key = modname .. "#" .. tostring(size)
    local fn = chunk_mem[key]
    if not fn then
        local bc = M.MOD_DIR .. "data_bc\\" .. modname:gsub("[^%w_]", "_") .. "_" .. tostring(size) .. ".luac"
        fn = loadfile(bc, "b")
        if not fn then
            fn = loadfile(path)
            if not fn then return nil end
            pcall(function()
                local out = io.open(bc, "wb")
                if out then out:write(string.dump(fn, true)); out:close() end
            end)
        end
        chunk_mem[key] = fn
        chunk_order[#chunk_order + 1] = key
        while #chunk_order > CHUNK_KEEP do chunk_mem[table.remove(chunk_order, 1)] = nil end
    end
    return fn
end
local function require_quick(modname)
    local fn = M.load_chunk(modname)
    if not fn then return require(modname) end
    local data = fn(modname)
    package.loaded[modname] = data
    return data
end

function M.load_data(name)
    if M.R96 and type(name) == "string" then
        local rest = name:match("^data%.(actor_[%w_]+)$")
        if rest and r96_data_file(rest) then
            local alt = "data_r96." .. rest
            package.loaded[alt] = nil
            local ok, data = pcall(require_quick, alt)
            package.loaded[alt] = nil
            if ok and data then return data end
            log("failed to load %s: %s", alt, tostring(data))
        end
    end
    package.loaded[name] = nil
    local ok, data = pcall(require_quick, name)
    -- (not kept in package.loaded: it is made again from its file every time anyway, and kept there every level visited
    -- stayed in memory all session - 154 MB of Lua live by the basement, its whole-heap passes half a second - "why is
    -- it so incredibly laggy?", 2026-11-06. Whoever uses it holds its own.)
    package.loaded[name] = nil
    if not ok then
        log("failed to load %s: %s", name, tostring(data))
        return nil
    end
    -- (a scene's fences solid with RENDER 96 on: M.r96_fences)
    local scene = M.R96 and type(name) == "string" and name:match("^data%.scene_([%w_]+)$")
    if scene and type(data) == "table" then
        local okf, errf = pcall(M.r96_fences, data, scene)
        if not okf then log("fences %s: %s", scene, tostring(errf)) end
    end
    return data
end

-- RENDER 96's solid fences (tools/r96_fences.py, data_r96/fences_<scene>.lua - Render96 has no fence models: "including
-- 3d fences add all the 3d models", 2026-10-31): a scene's fence sections, while it is on, put back as their faces a
-- thickness apart, front and back each one-sided, with walls round the picture's solid part between them - lit by the
-- way they face, in the picture's edge colour. A fence picture's sections are left as they are when the scene's are not
-- as the file has them (texture and triangle count). Called by M.load_data on a scene's data.
local function fence_shade(ox, oy, oz)
    local s = 0.8 + 0.2 * math.max(0.0, oz) - 0.15 * math.max(0.0, -oz) + 0.07 * (0.6 * ox + 0.8 * oy)
    return math.max(0.5, math.min(1.0, s))
end
-- Turned posts and round rails of RENDER 96's fences (tools/r96_fences.py TURN - the castle's balustrades and the grounds'
-- log fence: "fences look extremely wierd wrong", 2026-10-31, their balusters pushed out flat stood as angled slabs from the
-- side). A post: rings down it, each as wide as the picture's post at that row and as deep, about its middle; a rail: a
-- round bar along the panel between its rows. The picture laid on from the front (read a little in from the edge, where
-- it is solid), lit by the way each part faces. One section, solid and unlit, as the walls.
local TURN_SEG = 12
local function fence_turned(e, G, GS)
    local W, H = e.W, e.H
    local P, U, C, N, I = {}, {}, {}, {}, {}
    local nv, ni = 0, 0
    local lx, ly, lz = 0.35, 0.45, 0.82
    local ll = math.sqrt(lx * lx + ly * ly + lz * lz); lx, ly, lz = lx / ll, ly / ll, lz / ll
    local cs, sn = {}, {}
    for k = 0, TURN_SEG - 1 do cs[k] = math.cos(2.0 * math.pi * k / TURN_SEG); sn[k] = math.sin(2.0 * math.pi * k / TURN_SEG) end
    local function vert(x, y, z, u, v, nx, ny, nz, r, g, b)
        local s = 0.78 + 0.22 * (nx * lx + ny * ly + nz * lz)
        if s < 0.55 then s = 0.55 elseif s > 1.0 then s = 1.0 end
        P[nv * 3 + 1], P[nv * 3 + 2], P[nv * 3 + 3] = x, y, z
        U[nv * 2 + 1], U[nv * 2 + 2] = u, v
        C[nv * 4 + 1], C[nv * 4 + 2], C[nv * 4 + 3], C[nv * 4 + 4] = r * s, g * s, b * s, 1.0
        N[nv * 3 + 1], N[nv * 3 + 2], N[nv * 3 + 3] = nx, ny, nz
        nv = nv + 1
        return nv - 1
    end
    -- (a triangle turned to face (fx, fy, fz))
    local function tri(a, b, c, fx, fy, fz)
        local ax, ay, az = P[a * 3 + 1], P[a * 3 + 2], P[a * 3 + 3]
        local ux, uy, uz = P[b * 3 + 1] - ax, P[b * 3 + 2] - ay, P[b * 3 + 3] - az
        local wx, wy, wz = P[c * 3 + 1] - ax, P[c * 3 + 2] - ay, P[c * 3 + 3] - az
        local d = (uy * wz - uz * wy) * fx + (uz * wx - ux * wz) * fy + (ux * wy - uy * wx) * fz
        if d >= 0 then I[ni + 1], I[ni + 2], I[ni + 3] = a, b, c else I[ni + 1], I[ni + 2], I[ni + 3] = a, c, b end
        ni = ni + 3
    end
    -- a tube: rings { cx, cy, cz, u, v, radius } along it; across (ax..) and deep (dx..) per pixel of radius, the
    -- picture's step across per pixel (au, av), each ring's radius in pixels; closed at both ends, the ends' middles read
    -- (eu, ev) further in
    local function tube(rings, ax, ay, az, dx, dy, dz, au, av, r, g, b, eu, ev)
        local al = math.sqrt(ax * ax + ay * ay + az * az)
        local dl = math.sqrt(dx * dx + dy * dy + dz * dz)
        local first = nv
        for j = 1, #rings do
            local q = rings[j]
            for k = 0, TURN_SEG - 1 do
                local c, s = cs[k], sn[k]
                local nx, ny, nz = c * ax / al + s * dx / dl, c * ay / al + s * dy / dl, c * az / al + s * dz / dl
                vert(q[1] + q[6] * (c * ax + s * dx), q[2] + q[6] * (c * ay + s * dy), q[3] + q[6] * (c * az + s * dz),
                     q[4] + 0.85 * q[6] * c * au, q[5] + 0.85 * q[6] * c * av, nx, ny, nz, r, g, b)
            end
        end
        for j = 0, #rings - 2 do
            for k = 0, TURN_SEG - 1 do
                local k1 = (k + 1) % TURN_SEG
                local a0, a1 = first + j * TURN_SEG + k, first + j * TURN_SEG + k1
                local b0, b1 = a0 + TURN_SEG, a1 + TURN_SEG
                local c, s = cs[k] + cs[k1], sn[k] + sn[k1]
                local fx, fy, fz = c * ax / al + s * dx / dl, c * ay / al + s * dy / dl, c * az / al + s * dz / dl
                tri(a0, a1, b1, fx, fy, fz)
                tri(a0, b1, b0, fx, fy, fz)
            end
        end
        -- (its ends: a fan from the middle, facing out along it)
        local q1, q2 = rings[1], rings[#rings]
        local ex, ey, ez = q2[1] - q1[1], q2[2] - q1[2], q2[3] - q1[3]
        for side = 1, 2 do
            local q = side == 1 and q1 or q2
            local sg = side == 1 and -1 or 1
            local base = first + (side == 1 and 0 or (#rings - 1) * TURN_SEG)
            local m = vert(q[1], q[2], q[3], q[4] - sg * (eu or 0.0), q[5] - sg * (ev or 0.0), ex * sg, ey * sg, ez * sg, r, g, b)
            for k = 0, TURN_SEG - 1 do tri(m, base + k, base + (k + 1) % TURN_SEG, ex * sg, ey * sg, ez * sg) end
        end
    end
    local place, rails = e.place or {}, e.rails or {}
    for k = 1, #place, 4 do
        local gb, post, ku, kv = place[k] * GS, e.posts[place[k + 1] + 1], place[k + 2], place[k + 3]
        local nx, ny, nz = G[gb + 1], G[gb + 2], G[gb + 3]
        local r, g, b = G[gb + 5], G[gb + 6], G[gb + 7]
        local Ox, Oy, Oz = G[gb + 9], G[gb + 10], G[gb + 11]
        local dux, duy, duz = G[gb + 12], G[gb + 13], G[gb + 14]
        local dvx, dvy, dvz = G[gb + 15], G[gb + 16], G[gb + 17]
        local su = math.sqrt(dux * dux + duy * duy + duz * duz) / W
        local uc = (post[1] + ku * W) / W
        local rings = {}
        for j = 2, #post - 1, 2 do
            local v = (post[j] + kv * H) / H
            rings[#rings + 1] = { Ox + uc * dux + v * dvx, Oy + uc * duy + v * dvy, Oz + uc * duz + v * dvz, uc, v, post[j + 1] }
        end
        if #rings >= 2 then
            tube(rings, dux / W, duy / W, duz / W, nx * su, ny * su, nz * su, 1.0 / W, 0.0, r, g, b, 0.0, 2.5 / H)
        end
    end
    for k = 1, #rails, 6 do
        local gb = rails[k] * GS
        local y0, y1, u0, u1 = rails[k + 1], rails[k + 2], rails[k + 3], rails[k + 4]
        local nx, ny, nz = G[gb + 1], G[gb + 2], G[gb + 3]
        local r, g, b = G[gb + 5], G[gb + 6], G[gb + 7]
        local Ox, Oy, Oz = G[gb + 9], G[gb + 10], G[gb + 11]
        local dux, duy, duz = G[gb + 12], G[gb + 13], G[gb + 14]
        local dvx, dvy, dvz = G[gb + 15], G[gb + 16], G[gb + 17]
        local sv = math.sqrt(dvx * dvx + dvy * dvy + dvz * dvz) / H
        local v = (y0 + y1) / 2.0 / H
        local rad = (y1 - y0) / 2.0
        local deep = (rails[k + 5] or rad) / rad          -- (a handrail deeper than it is tall)
        local rings = {}
        for _, uu in ipairs({ u0 / W, u1 / W }) do
            rings[#rings + 1] = { Ox + uu * dux + v * dvx, Oy + uu * duy + v * dvy, Oz + uu * duz + v * dvz, uu, v, rad }
        end
        tube(rings, dvx / H, dvy / H, dvz / H, nx * sv * deep, ny * sv * deep, nz * sv * deep, 0.0, 1.0 / H, r, g, b, 0.75 / W, 0.0)
    end
    if nv == 0 then return nil end
    return { layer = "opaque", unlit = true, texture = e.texture, nverts = nv, ntris = ni // 3, pos = P, uv = U, col = C, nrm = N, idx = I }
end
function M.r96_fences(data, scene)
    if not (M.R96 and data and data.sections and r96_data_file("fences_" .. scene)) then return 0 end
    local mod = "data_r96.fences_" .. scene
    package.loaded[mod] = nil
    local ok, F = pcall(require, mod)
    package.loaded[mod] = nil
    if not ok or type(F) ~= "table" then log("fences %s: %s", scene, tostring(F)); return 0 end
    local byid, top = {}, 0
    for _, sec in ipairs(data.sections) do
        if sec.id then byid[sec.id] = sec; if sec.id > top then top = sec.id end end
    end
    local gone, add, nwall = {}, {}, 0
    for _, e in ipairs(F) do
        local fine = true
        for k = 1, #e.drop, 2 do
            local sec = byid[e.drop[k]]
            if not (sec and sec.texture == e.texture and sec.idx and #sec.idx // 3 == e.drop[k + 1]) then fine = false end
        end
        if not fine then
            log("fences %s: %s - its sections are not as the file has them, left flat", scene, e.texture)
        else
            local G = e.groups
            local GS = e.W and 17 or 8          -- (each group's numbers: 17 with the panel's picture mapping)
            -- the faces, front and back
            local cp, cu, cc, cn, ci, nv = {}, {}, {}, {}, {}, 0
            local caps = e.caps
            for k = 1, #caps, 3 do
                local sec, t, gb = byid[caps[k]], caps[k + 1], caps[k + 2] * GS
                local nx, ny, nz, h = G[gb + 1], G[gb + 2], G[gb + 3], G[gb + 4]
                local P, UV, C, I = sec.pos, sec.uv, sec.col, sec.idx
                local ia, ib, ic = I[t * 3 + 1], I[t * 3 + 2], I[t * 3 + 3]
                local ax, ay, az = P[ia * 3 + 1], P[ia * 3 + 2], P[ia * 3 + 3]
                local ux, uy, uz = P[ib * 3 + 1] - ax, P[ib * 3 + 2] - ay, P[ib * 3 + 3] - az
                local wx, wy, wz = P[ic * 3 + 1] - ax, P[ic * 3 + 2] - ay, P[ic * 3 + 3] - az
                local along = (uy * wz - uz * wy) * nx + (uz * wx - ux * wz) * ny + (ux * wy - uy * wx) * nz
                for side = 1, -1, -2 do
                    local ox, oy, oz = nx * h * side, ny * h * side, nz * h * side
                    local b, c = ib, ic
                    if (along > 0) ~= (side > 0) then b, c = ic, ib end
                    for _, v in ipairs({ ia, b, c }) do
                        cp[nv * 3 + 1], cp[nv * 3 + 2], cp[nv * 3 + 3] = P[v * 3 + 1] + ox, P[v * 3 + 2] + oy, P[v * 3 + 3] + oz
                        cu[nv * 2 + 1], cu[nv * 2 + 2] = UV[v * 2 + 1], UV[v * 2 + 2]
                        cc[nv * 4 + 1], cc[nv * 4 + 2], cc[nv * 4 + 3], cc[nv * 4 + 4] = C[v * 4 + 1], C[v * 4 + 2], C[v * 4 + 3], C[v * 4 + 4]
                        cn[nv * 3 + 1], cn[nv * 3 + 2], cn[nv * 3 + 3] = nx * side, ny * side, nz * side
                        ci[nv + 1] = nv
                        nv = nv + 1
                    end
                end
            end
            if nv > 0 then
                local ct = (e.caps_tex and e.caps_tex ~= "") and e.caps_tex or e.texture
                add[#add + 1] = { layer = "alpha1", texture = ct, nverts = nv, ntris = nv // 3, pos = cp, uv = cu, col = cc, nrm = cn, idx = ci }
            end
            -- turned posts and round rails (tools/r96_fences.py TURN)
            if e.posts and ((e.place and #e.place > 0) or (e.rails and #e.rails > 0)) then
                local sec = fence_turned(e, G, GS)
                if sec then add[#add + 1] = sec; nwall = nwall + sec.ntris // 2 end
            end
            -- the walls round each outline: each corner twice, the thickness apart
            local wp, wu, wc, wn, wi, wv, wt = {}, {}, {}, {}, {}, 0, 0
            local L, k = e.loops, 1
            while k <= #L do
                local gb, n = L[k] * GS, L[k + 1]
                local nx, ny, nz, h = G[gb + 1], G[gb + 2], G[gb + 3], G[gb + 4]
                local r, g, b, sign = G[gb + 5], G[gb + 6], G[gb + 7], G[gb + 8]
                local base = k + 2
                -- (each wall's outside, and its light)
                local ox, oy, oz, sh = {}, {}, {}, {}
                for q = 0, n - 1 do
                    local i0, i1 = base + q * 5, base + ((q + 1) % n) * 5
                    local dx, dy, dz = L[i1] - L[i0], L[i1 + 1] - L[i0 + 1], L[i1 + 2] - L[i0 + 2]
                    local cx, cy, cz = (dy * nz - dz * ny) * sign, (dz * nx - dx * nz) * sign, (dx * ny - dy * nx) * sign
                    local len = math.sqrt(cx * cx + cy * cy + cz * cz)
                    if len < 1e-9 then len = 1.0 end
                    ox[q], oy[q], oz[q] = cx / len, cy / len, cz / len
                    sh[q] = fence_shade(ox[q], oy[q], oz[q])
                end
                for q = 0, n - 1 do
                    local i = base + q * 5
                    local pq = (q - 1) % n
                    local mx, my, mz = ox[q] + ox[pq], oy[q] + oy[pq], oz[q] + oz[pq]
                    local ml = math.sqrt(mx * mx + my * my + mz * mz)
                    if ml < 1e-9 then mx, my, mz, ml = ox[q], oy[q], oz[q], 1.0 end
                    local s = 0.5 * (sh[q] + sh[pq])
                    for side = 1, -1, -2 do
                        wp[wv * 3 + 1], wp[wv * 3 + 2], wp[wv * 3 + 3] = L[i] + nx * h * side, L[i + 1] + ny * h * side, L[i + 2] + nz * h * side
                        wu[wv * 2 + 1], wu[wv * 2 + 2] = L[i + 3], L[i + 4]
                        wc[wv * 4 + 1], wc[wv * 4 + 2], wc[wv * 4 + 3], wc[wv * 4 + 4] = r * s, g * s, b * s, 1.0
                        wn[wv * 3 + 1], wn[wv * 3 + 2], wn[wv * 3 + 3] = mx / ml, my / ml, mz / ml
                        wv = wv + 1
                    end
                end
                -- (corner q's two: first + 2q its front, first + 2q + 1 its back; a wall from each to the next, its
                -- triangles turned to its outside - sign: which way the outline goes round)
                local first = wv - 2 * n
                for q = 0, n - 1 do
                    local t0, b0 = first + 2 * q, first + 2 * q + 1
                    local q1 = (q + 1) % n
                    local t1, b1 = first + 2 * q1, first + 2 * q1 + 1
                    if sign > 0 then
                        wi[wt + 1], wi[wt + 2], wi[wt + 3], wi[wt + 4], wi[wt + 5], wi[wt + 6] = t0, b1, t1, t0, b0, b1
                    else
                        wi[wt + 1], wi[wt + 2], wi[wt + 3], wi[wt + 4], wi[wt + 5], wi[wt + 6] = t0, t1, b1, t0, b1, b0
                    end
                    wt = wt + 6
                end
                nwall = nwall + n
                k = base + n * 5
            end
            if wv > 0 then
                add[#add + 1] = { layer = "opaque", unlit = true, texture = e.texture, nverts = wv, ntris = wt // 3, pos = wp, uv = wu, col = wc, nrm = wn, idx = wi }
            end
            -- the faces that are not upright, as they were
            local rest = {}
            for q = 1, #e.rest, 2 do
                local sid, t = e.rest[q], e.rest[q + 1]
                local sec = byid[sid]
                local o = rest[sid]
                if not o then
                    o = { layer = sec.layer, texture = sec.texture, nverts = 0, ntris = 0, pos = {}, uv = {}, col = {}, nrm = {}, idx = {} }
                    rest[sid] = o
                    add[#add + 1] = o
                end
                for j = 1, 3 do
                    local v = sec.idx[t * 3 + j]
                    local m = o.nverts
                    o.pos[m * 3 + 1], o.pos[m * 3 + 2], o.pos[m * 3 + 3] = sec.pos[v * 3 + 1], sec.pos[v * 3 + 2], sec.pos[v * 3 + 3]
                    o.uv[m * 2 + 1], o.uv[m * 2 + 2] = sec.uv[v * 2 + 1], sec.uv[v * 2 + 2]
                    o.col[m * 4 + 1], o.col[m * 4 + 2], o.col[m * 4 + 3], o.col[m * 4 + 4] = sec.col[v * 4 + 1], sec.col[v * 4 + 2], sec.col[v * 4 + 3], sec.col[v * 4 + 4]
                    o.nrm[m * 3 + 1], o.nrm[m * 3 + 2], o.nrm[m * 3 + 3] = sec.nrm[v * 3 + 1], sec.nrm[v * 3 + 2], sec.nrm[v * 3 + 3]
                    o.idx[m + 1] = m
                    o.nverts = m + 1
                end
                o.ntris = o.nverts // 3
            end
            for q = 1, #e.drop, 2 do gone[e.drop[q]] = true end
        end
    end
    if next(gone) == nil then return 0 end
    local kept = {}
    for _, sec in ipairs(data.sections) do if not gone[sec.id] then kept[#kept + 1] = sec end end
    for _, sec in ipairs(add) do
        top = top + 1
        sec.id = top
        kept[#kept + 1] = sec
    end
    data.sections = kept
    log("fences %s: made solid - %d sections in place of their flat ones, %d walls", scene, #add, nwall)
    return #add
end

local function try_load(path)
    local obj = StaticFindObject(path)
    if obj and obj:IsValid() then return obj end
    local ok, loaded = pcall(LoadAsset, path)
    if ok and loaded and loaded:IsValid() then return loaded end
    return nil
end
M.try_load = try_load

-- ------------------------------------------------------------ textures
local tex_cache = {}
-- (The caches below hold the engine's objects only from Lua. Once a scene is torn down nothing holds its
-- textures and materials, the engine frees them, and a new object can be made at the same address: a stale
-- entry then still looks valid but is something else (2026-10-14: a sign showed the waterfall's water). Each
-- entry keeps the object's name, and is only used while the object at that address still has it.)
local function same(entry)
    return entry ~= nil and entry ~= false and entry.obj:IsValid() and entry.obj:GetFName():ToString() == entry.name
end
-- Settings > Graphics, RENDER 96 (msettings.lua; kept with the save files, menu.lua): the Render 96 HD texture pack's
-- pictures (github.com/pokeheadroom/RENDER96-HD-TEXTURE-PACK, the Render96 team's - made into textures_r96/ by
-- tools/r96_build.py: the same names, the levels' tiled and clamped copies, the skies) in place of Mario 64's, wherever
-- there is one by that name; the rest as they are. "next I want another graphics option called render 96, it should
-- replace all the textures", 2026-10-31. Turned while a level is up: M.set_r96.
M.R96 = true
-- (on from the start when the save files have it - or have none yet: a new player's is on, "before even launching into the game these options should be ticked or on", 2026-11-01 - set before the
-- first scene is built - read by the settings (msettings.lua) some seconds in, the first scene was built with Mario
-- 64's and built again then)
pcall(function()
    local f = io.open(M.MOD_DIR .. "saves.lua", "r")
    if f then
        local t = f:read("a")
        f:close()
        if t and t:match("render96%s*=%s*0") then M.R96 = false end
    end
end)
local r96_has = {}
local function r96_file(file)
    local h = r96_has[file]
    if h == nil then
        local f = io.open(M.MOD_DIR .. "textures_r96\\" .. file .. ".png", "rb")
        h = f ~= nil
        if f then f:close() end
        r96_has[file] = h
    end
    return h
end
-- A picture from a file of the mod's - textures\<file> - made once and kept for as long as the map lasts. Each made one
-- is held by a hidden mesh of the mod's (a material of its own with the picture on it): otherwise the engine frees it
-- once nothing shows it, and it was made again - 30 to 50 ms each, the CHARACTER tab's four photos, the pickers' -
-- every time a menu came back: "lag when going from menu to menu", 2026-11-05. `path`: from the mod's folder.
local kept = { world = nil, actor = nil, pmc = nil, n = 0, by = {} }
function M.file_texture(world, path)
    if not world then return nil end
    local wa = nil
    pcall(function() wa = world:GetAddress() end)
    local okv = kept.pmc ~= nil and pcall(function() return kept.pmc:IsValid() end) and kept.pmc:IsValid()
    if kept.world ~= wa or not okv then
        kept.world, kept.actor, kept.pmc, kept.n, kept.by = wa, nil, nil, 0, {}
        local a = M.spawn_actor(world, M.OFFSET, 0.0)
        if a then
            pcall(function() a:SetActorHiddenInGame(true) end)
            pcall(function() a:SetActorEnableCollision(false) end)
            pcall(function() M.keep[a:GetAddress()] = "textures" end)
            kept.actor, kept.pmc = a, M.add_pmc(a)
        end
    end
    local e = kept.by[path]
    if e then
        local ok, same = pcall(function() return e.obj:IsValid() and e.obj:GetFName():ToString() == e.name end)
        if ok and same then return e.obj end
    end
    local t = nil
    pcall(function()
        t = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary"):ImportFileAsTexture2D(world, M.MOD_DIR .. path)
    end)
    if not (t and pcall(function() return t:IsValid() end) and t:IsValid()) then return nil end
    local e2 = { obj = t, name = t:GetFName():ToString() }
    if kept.pmc then
        pcall(function()
            local parent = try_load(M.init_materials(world).opaque.path)
            local KML = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
            local mid = KML:CreateDynamicMaterialInstance(world, parent, FName("SM64Kept_" .. kept.n), 0)
            mid:SetTextureParameterValue(FName("BaseColorTexture"), t)
            kept.pmc:SetMaterial(kept.n, mid)
            kept.n = kept.n + 1
            e2.mid = mid
        end)
    end
    kept.by[path] = e2
    return t
end

function M.texture(world, file)
    local hd = M.R96 and file ~= nil and r96_file(file)
    local ck = hd and ("r96|" .. file) or file
    local c = tex_cache[ck]
    if c == false and not hd and M.R96 and file ~= nil and r96_has[file] == false then
        -- (one taken for missing before its Render 96 picture came: looked for again, below)
        r96_has[file] = nil
        if r96_file(file) then return M.texture(world, file) end
    end
    if c == false then
        if hd then return M.texture_plain(world, file) end
        return false
    end
    local ok_same, is_same = pcall(same, c)
    if ok_same and is_same then return c.obj end
    local KRL = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
    local path = M.MOD_DIR .. (hd and "textures_r96\\" or "textures\\") .. file .. ".png"
    local ok, tex = pcall(function() return KRL:ImportFileAsTexture2D(world, path) end)
    if ok and tex and tex:IsValid() then
        tex_cache[ck] = { obj = tex, name = tex:GetFName():ToString() }
        return tex
    end
    -- (a Render 96 picture added since it was last looked for: looked for again - the Render96 models' pictures put in
    -- while the game ran were taken for missing, and the doors, signs, coins and Boos drawn without them, red: "a bunch
    -- of missing textures just showing up as red", 2026-10-31)
    if not hd and M.R96 and file ~= nil and r96_has[file] == false then
        r96_has[file] = nil
        if r96_file(file) then return M.texture(world, file) end
    end
    -- (one only Render 96 has, asked for with it off - its models' materials given again as RENDER 96 is turned off:
    -- the Render 96 one, not none - Dorrie was left with no picture at all, "dori is missing textures", 2026-10-31)
    if not hd and not M.R96 and file ~= nil and r96_file(file) then
        local p96 = M.MOD_DIR .. "textures_r96\\" .. file .. ".png"
        local ok2, tex2 = pcall(function() return KRL:ImportFileAsTexture2D(world, p96) end)
        if ok2 and tex2 and tex2:IsValid() then
            tex_cache[ck] = { obj = tex2, name = tex2:GetFName():ToString() }
            return tex2
        end
    end
    log("texture import failed: %s", path)
    tex_cache[ck] = false
    if hd then return M.texture_plain(world, file) end
    return false
end
-- (Mario 64's own picture, whatever the setting)
function M.texture_plain(world, file)
    local was = M.R96
    M.R96 = false
    local t = M.texture(world, file)
    M.R96 = was
    return t
end

-- ------------------------------------------------------------ materials
-- Masked material for alpha-tested textures.  Widget3DPassThrough_Masked is an engine material (blend = Masked)
-- whose texture parameter is called "SlateUI".  Set USE_MASKED to false to fall back to opaque for everything.
M.USE_MASKED = true
M.ALPHA_BOTH = true
-- Pictures drawn in another's place, made once beside them in textures/: Mario 64's G_CC_BLENDRGBA - the picture over
-- the shade by its own alpha - drawn opaque here, so its see-through part came out as the black under it. The Snufits'
-- eyes (snufit_seg6_dl_06009498): the eye over white, the shade (their vertex colour, the lit mask) multiplied in after,
-- as Mario 64 shows it - "snuffets eyes textures are messed up", 2026-10-25.
M.TEX_SWAP = {
    ["actors__snufit__snufit_eye.rgba16"] = "actors__snufit__snufit_eye_blend.rgba16",
    -- (Render96's signpost's face is a white board of blurred writing, opaque here: Mario 64's face in Render 96's HD -
    -- wood, a plaque pinned on - "signs got messed up somehow", 2026-10-31)
    ["actors__wooden_signpost__exclamationpoint.rgba32"] = "actors__wooden_signpost__wooden_signpost_front.rgba16",
}         -- (cut-out faces drawn front and back in the one-sided masked material: add_sections)
-- Pictures drawn as cut-outs though the export took their faces for solid: the Big Chill Bully's eyes (chilly_chief's
-- eye section came out opaque, the bully's own alpha) - their see-through part drawn as the dark stored under it, a black
-- box round them: "ice bullys eyes", 2026-10-26. (add_sections)
M.LAYER_SWAP = { ["actors__chillychief__chill_bully_eye.rgba16"] = "alpha" }
-- Cut-out pictures that repeat across their faces, drawn in the glTF cut-out material (cfg.alphaw), whose picture
-- repeats: the engine's masked one holds its picture at its edge past one repeat, and the Boo's cage - its bars 20 times
-- round - stood as a solid purple drum, its bars on one face: "also fix boo cage", 2026-11-06.
M.ALPHA_WRAP = { ["actors__haunted_cage__bbh_cage_bars.rgba16"] = true }
local cfg = nil
local mid_serial = 0
local mats_by_key = {}

function M.init_materials(world)
    if cfg then return cfg end
    cfg = { opaque = { path = "/InterchangeAssets/gltf/M_Unlit.M_Unlit", param = "BaseColorTexture" } }
    cfg.alpha, cfg.trans = cfg.opaque, cfg.opaque
    if M.USE_MASKED then
        cfg.alpha = { path = "/Engine/EngineMaterials/Widget3DPassThrough_Masked.Widget3DPassThrough_Masked", param = "SlateUI" }
        -- (its one-sided twin, for cut-out faces drawn twice - front and back - by add_sections: M.ALPHA_BOTH)
        cfg.alpha1 = { path = "/Engine/EngineMaterials/Widget3DPassThrough_Masked_OneSided.Widget3DPassThrough_Masked_OneSided", param = "SlateUI" }
        -- (and the glTF one, for the cut-outs that repeat: M.ALPHA_WRAP)
        cfg.alphaw = { path = "/InterchangeAssets/gltf/MaterialInstances/MI_Unlit_Mask.MI_Unlit_Mask", param = "BaseColorTexture" }
        -- (2026-10-14: the engine's translucent widget material drew soft-edged textures (HMC's lamp glows, BBH's
        -- windows) as solid white discs; the glTF blend material, which the mist and moving water use, blends them)
        cfg.trans = { path = "/InterchangeAssets/gltf/MaterialInstances/MI_Unlit_Blend.MI_Unlit_Blend", param = "BaseColorTexture" }
    end
    -- (the lit one: the glTF material that takes the sun's light and shadows - M.lit_on)
    cfg.lit = { path = "/InterchangeAssets/gltf/M_Default.M_Default", param = "BaseColorTexture" }
    log("materials: opaque=%s alpha=%s trans=%s", cfg.opaque.path, cfg.alpha.path, cfg.trans.path)
    return cfg
end

local function tier(layer)
    if layer == "lit" then return "lit" end
    if layer == "alpha" then return "alpha" end
    if layer == "alpha1" then return "alpha1" end
    if layer == "translucent" or layer == "translucent_decal" then return "trans" end
    return "opaque"
end

-- see-through textures drawn fainter than Mario 64's own alpha: the basement torches' wall glow, "decrease the
-- backdrop opacity of the flame by 50%", then "do 25% opacity then its still very bright", then "do 10%", then "5%", 2026-10-19
-- BBH's light shafts from its windows (0.35 alpha) stood as solid glowing yellow ramps on the floors: 0.01, 2026-10-22
-- (Both were tuned while every see-through triangle was drawn several times over - 4 and 6 times - each copy adding
-- its own alpha (M.once_tris); drawn once now, raised by as many times so they look as they were.)
-- BBH's door glows, drawn once at their own 0.6: "halve the opacity of those lights", then "halve it again", 2026-10-22
-- Wing Mario Over the Rainbow's two clouds (its see-through section of levels/wmotr/2), drawn whole at Mario 64's
-- alpha of 1 they hid the red coin inside one: "the opacity of the cloud should be half", 2026-10-29
M.ALPHA_SCALE = { ["levels__castle_inside__2.ia16"] = 0.2, ["textures__spooky__bbh_textures.0B000.ia16"] = 0.18,
                  ["textures__spooky__bbh_textures.0B800.ia16"] = 0.25, ["levels__wmotr__2.rgba16"] = 0.5 }

-- Solid pictures repeated across a level: the glTF materials wrap a picture in the shader, without the blur carrying over
-- its edge - every repeat a square of its own ("squares in the floor and wall", "for every level", 2026-10-30). Each is
-- drawn from a copy of it repeated N x N (textures/<name>.x<N>.png, tools/tile_textures.py) at 1/N: a piece of level whose
-- picture repeats no more than N times across it - its UVs moved by whole repeats to start at 0, add_sections - shows no
-- edge at all. N by picture: data/texture_tiles.lua.
M.TILES = nil
function M.tiles(texture)
    if M.TILES == nil then M.TILES = M.load_data("data.texture_tiles") or false end
    return texture and M.TILES and M.TILES[texture] or nil
end

-- a material's picture: a solid one repeated across a level its copy N x N, at 1/N (M.tiles); the Render 96 one where
-- the setting has it (M.texture)
local function put_texture(world, mid, t, spec, texture)
    -- (see-through faces too, since the classic look's copies are smooth: Snowman's Land's pool ice showed a line at every
    -- repeat - "render 96 is off right now and the seems are showing", 2026-10-31; tools/smooth_classic.py)
    local n = (t == "opaque" or t == "lit" or t == "trans") and M.tiles(texture) or nil
    -- (Render 96's own picture, where there is one, drawn as it is, not from a tiled copy: at its size the seam those
    -- copies hide is a hair. Kept to the tiled copies, a level's biggest surfaces - 16 and 32 repeats, no room left in
    -- 1024 for anything finer than Mario 64's - stayed as they were: "its very obvouse to me that some of the textures
    -- didnt change at all", 2026-10-31; Bob-omb Battlefield was 80% Mario 64's)
    if n and M.R96 and r96_file(texture) then n = nil end
    local tex = n and M.texture(world, texture .. ".x" .. n) or nil
    if tex then
        mid:SetTextureParameterValue(FName(spec.param), tex)
        pcall(function() mid:SetVectorParameterValue(FName("BaseColorTexture_OffsetScale"), { R = 0.0, G = 0.0, B = 1.0 / n, A = 1.0 / n }) end)
    else
        tex = M.texture(world, texture)
        if tex then mid:SetTextureParameterValue(FName(spec.param), tex) end
        if t == "opaque" or t == "lit" or t == "trans" then
            pcall(function() mid:SetVectorParameterValue(FName("BaseColorTexture_OffsetScale"), { R = 0.0, G = 0.0, B = 1.0, A = 1.0 }) end)
        end
    end
end

-- A picture for a surface the mod draws itself (movtex.lua's see-through moving textures): its smooth tiled copy where
-- the classic look has one (M.tiles), and the N to draw it at 1/N of; else the picture itself, 1 - as put_texture does
function M.tiled_texture(world, texture)
    local n = M.tiles(texture)
    if n and M.R96 and r96_file(texture) then n = nil end
    local tex = n and M.texture(world, texture .. ".x" .. n) or nil
    if tex then return tex, n end
    return M.texture(world, texture), 1
end

-- one shared dynamic material instance per (tier, texture[, alpha])
function M.get_mid(world, layer, texture, alpha)
    -- (every cut-out face is drawn twice, front and back, by add_sections (M.ALPHA_BOTH): a cut-out material asked for
    -- anywhere is the one-sided twin, or the two faces fight to black - the key dance's sparkles, their pictures swapped
    -- frame by frame: "when picking up the key in bowser in the fire sea and the animation play some textures are black",
    -- 2026-10-25. And a picture drawn in another's place (M.TEX_SWAP) is that one wherever it is asked for.)
    if M.ALPHA_BOTH and layer == "alpha" then layer = "alpha1" end
    if texture and M.TEX_SWAP then
        local base, clampy = texture:match("^(.-)(%.clamp)$")
        local sw = M.TEX_SWAP[base or texture]
        if sw then texture = sw .. (clampy or "") end
    end
    local t = tier(layer)
    if (t == "alpha" or t == "alpha1") and texture and M.ALPHA_WRAP and M.ALPHA_WRAP[texture] and M.init_materials(world).alphaw then
        t = "alphaw"
    end
    local key = t .. "|" .. tostring(texture) .. (alpha and string.format("|%.2f", alpha) or "")
    local c = mats_by_key[key]
    local ok_same, is_same = pcall(same, c)
    if ok_same and is_same then return c.obj end
    local spec = M.init_materials(world)[t]
    local parent = try_load(spec.path)
    if not parent then return nil end
    local KML = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    mid_serial = mid_serial + 1
    local mid = KML:CreateDynamicMaterialInstance(world, parent, FName(string.format("SM64Mat_%d_%d_%d", os.time(), math.floor(os.clock() * 1000), mid_serial)), 0)
    if not (mid and mid:IsValid()) then return nil end
    if texture then put_texture(world, mid, t, spec, texture) end
    if alpha and t == "trans" then
        pcall(function() mid:SetVectorParameterValue(FName("BaseColorFactor"), { R = 1.0, G = 1.0, B = 1.0, A = alpha }) end)
    end
    if t == "lit" then
        -- (a glTF material is metal unless told otherwise: matte, as Mario 64's are)
        pcall(function() mid:SetScalarParameterValue(FName("MetallicFactor"), 0.0) end)
        pcall(function() mid:SetScalarParameterValue(FName("RoughnessFactor"), 1.0) end)
    end
    mats_by_key[key] = { obj = mid, name = mid:GetFName():ToString(), t = t, texture = texture }
    return mid
end

-- RENDER 96 turned while a level is up: every material made so far given its picture again from the set now chosen
function M.set_r96(on)
    on = on and true or false
    if M.R96 == on then return 0 end
    M.R96 = on
    -- (its files looked for afresh: some may have come since)
    r96_has, r96_data = {}, {}
    local world = M.world()
    local n = 0
    if world then
        for _, c in pairs(mats_by_key) do
            local ok, is = pcall(same, c)
            if ok and is and c.texture then
                local spec = M.init_materials(world)[c.t]
                if spec and pcall(put_texture, world, c.obj, c.t, spec, c.texture) then n = n + 1 end
            end
        end
    end
    log("render 96: %s (%d pictures given again)", on and "on" or "off", n)
    if M.on_r96 then
        local ok, err = pcall(M.on_r96, on)
        if not ok then log("render 96: %s", tostring(err)) end
    end
    return n
end

-- Real-time shadows everywhere (game.lua G.LIT_LEVELS - "lets just go full real time shadows", 2026-10-30): every solid
-- thing of a level drawn lit - the creatures, the platforms, the pieces that move - so that shadows fall on them as on the
-- level, his own on the platform he stands on. The menu's own pictures and the skies stay unlit.
M.UNLIT_PREFIX = { "menu_", "sky_", "title_" }
function M.lit_on()
    local G = package.loaded["game"]
    return (G and G.LIT_LEVELS) and true or false
end
local function unlit_tex(tex)
    if not tex then return false end
    for _, pre in ipairs(M.UNLIT_PREFIX) do if tex:sub(1, #pre) == pre then return true end end
    return false
end

-- A picture turned to the camera (Mario 64's billboards: the bob-ombs, the chain chomp, the iron balls, the coins)
-- would cast a shadow that turns with the camera, thin from one side and whole from another. Its shadow comes from a
-- twin instead: the same picture on it, turned to the sun, never seen - hidden, casting its shadow all the same (the
-- engine's "cast hidden shadow", as the trees' copies: drawn only into the shadows - "render in main pass" off - it cast
-- none at all, "some things still not getting shadows", 2026-10-30). It goes where the picture goes; its shadow only
-- while the picture is shown (M.sync_twins - hidden, it would cast on). Flames and sparkles cast none.
M.SHADE_SKIP = { "sparkle", "flame", "iris", "explosion", "smoke" }
M.twins = 0
M.twin_list, M.twin_world = {}, nil          -- { twin, owners (actors), addrs, comp, on }
local function sun_facing()
    local MN = _G.MENU
    local sun = (MN and MN.SUN) or { 65.0, 35.0 }
    -- (its face, the -x side, to the sun: as face_camera turns it to the camera)
    return { Pitch = -sun[1], Yaw = sun[2] + 180.0, Roll = 0.0 }
end
function M.shade_twin(world, actor, comp, sections)
    -- (made whatever the setting: with real-time shadows off the sun casts none, and it casts nothing)
    if not (actor and comp and sections and #sections > 0) then return nil end
    local casts = false
    for _, sec in ipairs(sections) do
        local t = tier(sec.layer)
        local tex = sec.texture or ""
        local skip = false
        for _, w in ipairs(M.SHADE_SKIP) do if tex:find(w, 1, true) then skip = true end end
        if (t == "alpha" or t == "opaque" or t == "alpha1") and not skip then casts = true end
    end
    if not casts then return nil end
    local twin = M.add_pmc(actor)
    if not twin then return nil end
    pcall(function() twin:SetCollisionEnabled(0) end)
    pcall(function() twin:K2_AttachToComponent(comp, FName("None"), 2, 2, 2, false) end)
    M.add_sections(world, twin, sections)
    pcall(function() twin:SetCastShadow(true) end)
    pcall(function() twin:SetHiddenInGame(true, false) end)
    pcall(function() twin:SetCastHiddenShadow(true) end)
    pcall(function()
        twin.RelativeRotation = sun_facing()
        twin:SetAbsolute(false, true, false)
    end)
    pcall(function() comp:SetCastShadow(false) end)
    M.twins = M.twins + 1
    local here, addr = nil, nil
    pcall(function() here = world:GetAddress() end)
    pcall(function() addr = actor:GetAddress() end)
    if M.twin_world ~= here then M.twin_list, M.twin_world = {}, here end
    M.twin_list[#M.twin_list + 1] = { twin = twin, owners = { actor }, addrs = { [addr or 0] = true }, comp = comp, on = true }
    return twin
end

-- Pictures shown in turn (a coin's four, game.lua's pick-ups): one shadow for them all - the first's twin, cast while any
-- of them is shown; the others' twins cast none (each its own, the shadow would blink as they turned)
function M.twin_group(actors)
    local set, first, list = {}, nil, {}
    for _, a in ipairs(actors or {}) do
        if a then
            local addr = nil
            pcall(function() addr = a:GetAddress() end)
            if addr then
                set[addr] = true
                first = first or addr
                list[#list + 1] = a
            end
        end
    end
    if not first then return end
    local keep, lead = {}, nil
    for _, e in ipairs(M.twin_list) do
        local mine = false
        for addr in pairs(e.addrs) do if set[addr] then mine = true end end
        if not mine then
            keep[#keep + 1] = e
        elseif e.addrs[first] and not lead then
            lead = e
            e.owners, e.addrs = list, set
            keep[#keep + 1] = e
        else
            pcall(function() e.twin:SetCastShadow(false) end)
        end
    end
    M.twin_list = keep
end

-- A few times a second: each twin's shadow on while what it is of is shown, off while it is hidden (a coin taken, a
-- creature gone, a picture of a pool put away). A twin whose actor is gone is let go untouched; a new map, all of them.
local twin_t = 0.0
function M.sync_twins(dt)
    twin_t = twin_t - (dt or 0.0)
    if twin_t > 0.0 then return end
    twin_t = 0.1
    local here = nil
    pcall(function() here = M.world():GetAddress() end)
    if here ~= M.twin_world then M.twin_list, M.twin_world = {}, here; return end
    local keep = {}
    for _, e in ipairs(M.twin_list) do
        local alive, shown = false, false
        pcall(function()
            if not e.twin:IsValid() then return end
            alive = true
            for _, o in ipairs(e.owners) do
                if o:IsValid() and not o.bHidden then shown = true; break end
            end
            if shown and e.comp:IsValid() and not e.comp.bVisible then shown = false end
        end)
        if alive then
            keep[#keep + 1] = e
            if shown ~= e.on then
                e.on = shown
                pcall(function() e.twin:SetCastShadow(shown) end)
            end
        end
    end
    M.twin_list = keep
end

-- The solid pictures that are lit with real-time shadows and unlit without, by their material's name: what each is a
-- picture of, and whether it is the lit one. Settings > Graphics, REAL TIME SHADOWS, turned while a level is up:
-- every one of them in the world swapped for its other (M.relight).
M.litable = {}
function M.relight(world, on)
    local n = 0
    for _, c in ipairs(FindAllOf("ProceduralMeshComponent") or {}) do
        if c and c:IsValid() then
            local cnt = 0
            pcall(function() cnt = c:GetNumMaterials() end)
            for i = 0, cnt - 1 do
                local m = nil
                pcall(function() m = c:GetMaterial(i) end)
                if m and m:IsValid() then
                    local e = M.litable[m:GetFName():ToString()]
                    if e and e.lit ~= on then
                        local mid = M.get_mid(world, on and "lit" or "opaque", e.tex)
                        if mid and mid:IsValid() then
                            M.litable[mid:GetFName():ToString()] = { tex = e.tex, lit = on }
                            pcall(function() c:SetMaterial(i, mid) end)
                            n = n + 1
                        end
                    end
                end
            end
        end
    end
    return n
end

-- ------------------------------------------------------------ procedural meshes
local sig_cache = nil
local function get_sig()
    if sig_cache ~= nil then return sig_cache end
    sig_cache = false
    local fn = StaticFindObject("/Script/ProceduralMeshComponent.ProceduralMeshComponent:CreateMeshSection_LinearColor")
    if fn and fn:IsValid() then
        local names = {}
        local ok = pcall(function()
            fn:ForEachProperty(function(prop) names[#names + 1] = prop:GetFName():ToString() end)
        end)
        if ok and #names > 0 then sig_cache = names end
    end
    return sig_cache
end

local function create_section(pmc, id, verts, idx, nrms, uvs, cols, collide)
    local sig = get_sig()
    local args
    if sig then
        args = {}
        for i, name in ipairs(sig) do
            local n = name:lower()
            if n == "sectionindex" then args[i] = id
            elseif n == "vertices" then args[i] = verts
            elseif n == "triangles" then args[i] = idx
            elseif n == "normals" then args[i] = nrms
            elseif n == "uv0" then args[i] = uvs
            elseif n == "vertexcolors" then args[i] = cols
            elseif n == "bcreatecollision" then args[i] = collide
            elseif n:sub(1, 1) == "b" then args[i] = false
            else args[i] = {} end
        end
    else
        args = { id, verts, idx, nrms, uvs, {}, {}, {}, cols, {}, collide, false }
    end
    pmc:CreateMeshSection_LinearColor(table.unpack(args, 1, #args))
end
M.create_section = create_section

local function vec_array(flat, n)
    local out = {}
    for i = 0, n - 1 do
        out[i + 1] = { X = flat[i * 3 + 1], Y = flat[i * 3 + 2], Z = flat[i * 3 + 3] }
    end
    return out
end
M.vec_array = vec_array

local function two_sided(idx)
    local out = {}
    local n = #idx
    for i = 1, n do out[i] = idx[i] end
    for t = 0, n // 3 - 1 do
        out[n + t * 3 + 1] = idx[t * 3 + 1]
        out[n + t * 3 + 2] = idx[t * 3 + 3]
        out[n + t * 3 + 3] = idx[t * 3 + 2]
    end
    return out
end

-- add visual sections (no collision) to a PMC and give each a material
-- Textures Mario 64 draws clamped: past their edge the last row of pixels carries on, where a wrapped
-- texture would start over. Each has a "<name>.clamp.png" beside it: the texture in the middle third of a
-- picture three times the size, its edges drawn out to fill the rest. Sections using one read that instead.
M.CLAMP = {
    ["actors__goomba__goomba_face.rgba16"] = true,
    -- (Snowman's Land's big snowman's mouth: its ring on snow, laid on past its edges - wrapped, the head showed bits
    -- of several rings: "face of the big snowman is messed up", 2026-10-26)
    ["levels__sl__3.rgba16"] = true,
    -- (the penguins' eyes, penguin_seg5_dl_05006380: G_TX_CLAMP, and G_CC_BLENDRGBA - the picture over his blue by its
    -- own alpha, not tinted by it: the "_blend" picture is that, made once - "penguinz eye texture is off", 2026-10-18)
    ["actors__penguin__penguin_eye_open_blend.rgba16"] = true,
    -- (PSS's railings: its gold bands clamped top to bottom, G_TX_CLAMP mask 6 - their tops read just over the top edge,
    -- and wrapped that was the black of the bottom rows: "the railings tops are still black", 2026-10-17)
    ["textures__mountain__ttm_textures.01800.rgba16"] = true,
    ["actors__toad__toad_face.rgba16"] = true,         -- (Toad's face and spots: toad_seg6_dl_06007710, G_TX_CLAMP)
    -- (the Ukiki's face, ukiki_seg5_dl_0500B278: G_TX_CLAMP both ways - its edge's brown fur carries on over the rest of
    -- his head. Wrapped, the face was repeated all round it, pale patches and eyes all over: "the monkey, his textures
    -- are all messed up", 2026-10-27)
    ["actors__ukiki__ukiki_face.rgba16"] = true,
    ["actors__toad__toad_head.rgba16"] = true,
    -- (the Koopas' faces: koopa_seg6_dl_06007A60 / 06007AA0, G_TX_CLAMP - wrapped, the eye outline's yellow arches ran
    -- down the back of Koopa the Quick's head: "koopa textures are messed up", 2026-10-16)
    ["actors__koopa__koopa_eyes_open.rgba16"] = true,
    ["actors__koopa__koopa_eye_border.rgba16"] = true,
    ["actors__koopa__koopa_nostrils.rgba16"] = true,
    ["actors__koopa_flag__koopa_flag_banner.rgba16"] = true,  -- (the finish flag's banner: G_TX_CLAMP; repeated, "the flag texture is messed up")
    -- (the purple "!" floor switch, purple_switch_seg8_dl_0800C668: its "!" in the middle of the button, purple past it,
    -- and its base's gold fading once to bright - repeated, scraps of "!" and gold stripes: "next power switch texture")
    ["actors__purple_switch__purple_switch_exclamation_point.rgba16"] = true,
    ["actors__purple_switch__purple_switch_base.rgba16"] = true,
    -- (the Boos' eyes and mouth, boo_seg5_dl_0500C1B0 / boo_castle's: G_TX_CLAMP - wrapped, bits of eye and mouth were
    -- repeated over its face: "they're textures are messed up", 2026-10-17)
    ["actors__boo__boo_eyes.rgba16"] = true,
    ["actors__boo__boo_mouth.rgba16"] = true,
    ["actors__boo_castle__bbh_boo_eyes.rgba16"] = true,
    ["actors__boo_castle__bbh_boo_mouth.rgba16"] = true,
    -- (Bullet Bill's eye and mouth, bullet_bill_seg5_dl_0500E730's: G_TX_CLAMP - "they're textures are off", 2026-10-17)
    ["actors__bullet_bill__bullet_bill_eye.rgba16"] = true,
    ["actors__bullet_bill__bullet_bill_mouth.rgba16"] = true,
    -- (the Snufits' eyes, snufit_seg6_dl_06009498: G_TX_CLAMP - their corners read well past the picture, and wrapped
    -- the eyes came round again in pieces: "fix the shyguys they are contorted", 2026-10-20)
    ["actors__snufit__snufit_eye.rgba16"] = true,
    ["actors__snufit__snufit_eye_blend.rgba16"] = true,
    -- (Klepto, klepto_seg5_dl_05003BD0 and on: every picture of his G_TX_CLAMP - wrapped, his eye came round again over
    -- his head, "he also has multiple eyes", 2026-10-23)
    ["actors__klepto__klepto_eye.rgba16"] = true,
    ["actors__klepto__klepto_beak.rgba16"] = true,
    ["actors__klepto__klepto_chest_tuft.rgba16"] = true,
    ["actors__klepto__klepto_wing.rgba16"] = true,
    ["actors__klepto__klepto_wing_flap.rgba16"] = true,
    -- (the Heave-Ho, heave_ho_seg5_dl_05011EC0 and the rest: every picture of it G_TX_CLAMP - its "KOOPA" logo and
    -- ornaments laid on well past their edges, wrapped, came out in pieces over its body: "chukyas textures are messed
    -- up" - the Heave-Hos, 2026-10-28)
    ["actors__heave_ho__heave-ho_arm_ornament.rgba16"] = true,
    ["actors__heave_ho__heave-ho_face.rgba16"] = true,
    ["actors__heave_ho__heave-ho_logo.rgba16"] = true,
    ["actors__heave_ho__heave-ho_platform.rgba16"] = true,
    ["actors__heave_ho__heave-ho_roller.rgba16"] = true,
    ["actors__heave_ho__heave-ho_turnkey.rgba16"] = true,
    -- (Peach's dress, peach_seg5_dl_05006A18 and the rest: G_TX_CLAMP top to bottom only, wrapped round her - its
    -- darker pink waves along its foot carried on down the skirt to the hem. Wrapped both ways the skirt under the waves
    -- started the picture's pale top again: "peaches dress is messed up", 2026-11-02. "v": clamped top to bottom only)
    ["actors__peach__peach_dress.rgba16"] = "v",
    -- (Yoshi's eyes and nostrils, yoshi_seg5_dl_0501D8F8: G_TX_CLAMP both ways - laid on well past their edges, wrapped,
    -- his eyes and nostrils came round again over his head: "yoshi's messed up", 2026-11-02)
    ["actors__yoshi__yoshi_eye.rgba16"] = true,
    ["actors__yoshi__yoshi_nostril.rgba16"] = true,
}
-- The picture a clamped texture is drawn from: "<name>.clamp" (three times the size, its edges drawn out), or for one
-- clamped top to bottom only ("v") "<name>.clampv" (as wide, three times as tall, its top and bottom rows drawn out)
function M.clamp_file(name)
    local c = name and M.CLAMP[name]
    if not c then return name end
    return name .. ((c == "v") and ".clampv" or ".clamp")
end

-- A see-through section's triangles, each once. Levels drawn room by room (BBH, the castle's inside: Mario 64 draws
-- only the room Mario is in) come out of the exporter with every room's copy of a shared light at once - BBH's door
-- glows nine times on the same spot, at 0.6 alpha each, stood as solid yellow over its doors ("where are the doors?",
-- 2026-10-22). Opaque ones are left be: a copy there changes nothing. A copy turned round is not one: the see-through
-- material draws a face's front only, and that is its back (SL's ice bridge from under it, G.add_underside: "still no
-- texture under ice bridge", 2026-10-26).
function M.once_tris(sec)
    if sec.idx_once then return sec.idx_once end
    local P, UV, idx = sec.pos, sec.uv, sec.idx
    local seen, out = {}, {}
    for t = 0, #idx // 3 - 1 do
        local ks = {}
        for k = 1, 3 do
            local v = idx[t * 3 + k]
            ks[k] = string.format("%.1f,%.1f,%.1f,%.3f,%.3f", P[v * 3 + 1], P[v * 3 + 2], P[v * 3 + 3],
                                  UV[v * 2 + 1] or 0, UV[v * 2 + 2] or 0)
        end
        -- (its corners in their own turn, from the least: the same face whichever corner it starts at, facing the same way)
        local f = 1
        if ks[2] < ks[f] then f = 2 end
        if ks[3] < ks[f] then f = 3 end
        local key = ks[f] .. "|" .. ks[f % 3 + 1] .. "|" .. ks[(f + 1) % 3 + 1]
        if not seen[key] then
            seen[key] = true
            out[#out + 1], out[#out + 2], out[#out + 3] = idx[t * 3 + 1], idx[t * 3 + 2], idx[t * 3 + 3]
        end
    end
    sec.idx_once = out
    return out
end

-- See-through sheets drawn from both sides: Mario 64 draws them one-sided, and from under them they were not there -
-- Snowman's Land's ice over its freezing pool, swum under: "no underside to the ice", 2026-10-31. Each face's back added
-- (unless the level has it already).
M.TRANS_BOTH = { ["textures__snow__ccm_textures.00800.rgba16"] = true }
function M.with_backs(sec, idx)
    local P = sec.pos
    local function vkey(v) return string.format("%.1f,%.1f,%.1f", P[v * 3 + 1], P[v * 3 + 2], P[v * 3 + 3]) end
    local function fkey(a, b, c)
        local k = { vkey(a), vkey(b), vkey(c) }
        local f = 1
        if k[2] < k[f] then f = 2 end
        if k[3] < k[f] then f = 3 end
        return k[f] .. "|" .. k[f % 3 + 1] .. "|" .. k[(f + 1) % 3 + 1]
    end
    local seen, out = {}, {}
    for t = 0, #idx // 3 - 1 do
        local a, b, c = idx[t * 3 + 1], idx[t * 3 + 2], idx[t * 3 + 3]
        seen[fkey(a, b, c)] = true
        out[#out + 1], out[#out + 2], out[#out + 3] = a, b, c
    end
    for t = 0, #idx // 3 - 1 do
        local a, b, c = idx[t * 3 + 1], idx[t * 3 + 2], idx[t * 3 + 3]
        local k = fkey(a, c, b)
        if not seen[k] then seen[k] = true; out[#out + 1], out[#out + 2], out[#out + 3] = a, c, b end
    end
    return out
end

function M.add_sections(world, pmc, sections, tint_scale)
    local made = 0
    for _, sec in ipairs(sections) do
        local swap = sec.texture and M.LAYER_SWAP[sec.texture]
        if swap then sec.layer = swap end
        if M.debug then log("  section %s layer=%s tex=%s verts=%d", tostring(sec.id), tostring(sec.layer), tostring(sec.texture), sec.nverts) end
        local ok, err = pcall(function()
            local texname = sec.texture and (M.TEX_SWAP[sec.texture] or sec.texture)
            local clamp = texname and M.CLAMP[texname]
            local verts = vec_array(sec.pos, sec.nverts)
            local nrms = vec_array(sec.nrm, sec.nverts)
            local uvs, cols = {}, {}
            -- (a solid picture drawn from its copy N x N - M.tiles: the piece's UVs moved by whole repeats, which shows
            -- the same, to start at 0, so that up to N repeats across it fall inside the one copy)
            local su, sv = 0.0, 0.0
            if not clamp and (tier(sec.layer) == "opaque" or tier(sec.layer) == "trans") and M.tiles(texname) and sec.nverts > 0 then
                local mu, mv = math.huge, math.huge
                for i = 0, sec.nverts - 1 do
                    local u, v = sec.uv[i * 2 + 1], sec.uv[i * 2 + 2]
                    if u < mu then mu = u end
                    if v < mv then mv = v end
                end
                su, sv = math.floor(mu), math.floor(mv)
            end
            for i = 0, sec.nverts - 1 do
                local u, v = sec.uv[i * 2 + 1] - su, sec.uv[i * 2 + 2] - sv
                -- (kept just inside the picture: on its very edge the engine's wrap blended in the opposite edge - the
                -- Koopa's yellow neck came out white, 2026-10-16)
                if clamp == "v" then v = (math.max(-0.98, math.min(1.98, v)) + 1.0) / 3.0
                elseif clamp then u, v = (math.max(-0.98, math.min(1.98, u)) + 1.0) / 3.0, (math.max(-0.98, math.min(1.98, v)) + 1.0) / 3.0 end
                uvs[i + 1] = { X = u, Y = v }
                local r, g, b, a = sec.col[i * 4 + 1], sec.col[i * 4 + 2], sec.col[i * 4 + 3], sec.col[i * 4 + 4]
                cols[i + 1] = { R = r ^ 2.2, G = g ^ 2.2, B = b ^ 2.2, A = a }
            end
            local idx = (tier(sec.layer) == "trans") and M.once_tris(sec) or sec.idx
            if tier(sec.layer) == "trans" and M.TRANS_BOTH[sec.texture or ""] then idx = M.with_backs(sec, idx) end
            -- (the engine masked material is two-sided; duplicating triangles made them z-fight to black. The see-through
            -- one - the glTF blend - is one-sided: a face's back is a triangle of its own, M.once_tris keeps it)
            -- (but the two-sided masked one draws a face's back black: the Swoops' wings from above or behind, "top side
            -- of bat wings are black", 2026-10-25. A cut-out face is drawn twice instead, front and back, each in the
            -- one-sided twin, so each side shows its picture and neither fights the other.)
            local layer = sec.layer
            if M.ALPHA_BOTH and tier(layer) == "alpha" and M.init_materials(world).alpha1 then idx, layer = two_sided(idx), "alpha1" end
            -- (solid, in a level, with real-time shadows: lit, so shadows fall on it - M.lit_on)
            -- (but not the walls of RENDER 96's solid fences - sec.unlit: drawn as their faces are, unlit, M.r96_fences)
            if tier(layer) == "opaque" and M.lit_on() and not unlit_tex(texname) and not sec.unlit then layer = "lit" end
            create_section(pmc, sec.id, verts, idx, nrms, uvs, cols, false)
            -- (a see-through section's own alpha, in its vertices, as Mario 64 blends it: the blend material reads only
            -- the texture's, and the castle's light shafts at half alpha stood as white sheets, hiding the aquarium,
            -- 2026-10-15)
            local alpha = nil
            if tier(sec.layer) == "trans" and sec.nverts > 0 then
                local sum = 0.0
                for i = 0, sec.nverts - 1 do sum = sum + (sec.col[i * 4 + 4] or 1.0) end
                local a = sum / sec.nverts
                if a < 0.98 then alpha = math.floor(a * 20.0 + 0.5) / 20.0 end
                local sc = M.ALPHA_SCALE[sec.texture]
                if sc then alpha = math.floor((alpha or 1.0) * sc * 100.0 + 0.5) / 100.0 end
            end
            local mid = M.get_mid(world, layer, clamp and M.clamp_file(texname) or texname, alpha)
            if mid then pmc:SetMaterial(sec.id, mid) end
            -- (one that is lit with real-time shadows and unlit without: noted, to be swapped when the setting is - M.relight)
            if mid and (layer == "lit" or (tier(layer) == "opaque" and not unlit_tex(texname) and not sec.unlit)) then
                pcall(function() M.litable[mid:GetFName():ToString()] = { tex = clamp and M.clamp_file(texname) or texname, lit = (layer == "lit") } end)
            end
        end)
        if ok then made = made + 1 else log("section %s failed: %s", tostring(sec.id), tostring(err)) end
    end
    return made
end

-- Mario 64's chrome (G_TEXTURE_GEN): a section's metal picture laid by where each corner faces as the camera sees it -
-- the view's x and y of its normal - made again whenever called, so it slides over the thing as it and the camera turn
-- (his cap, nose and mustache under the metal cap, mariolook.lua; the metal cap out of its box, boxes.lua). The
-- section's own UVs are left alone: Mario 64 never read them under its texture gen, and they put the metal cap on the
-- picture's black half ("the hat alone is completely black when it drops out of the box", 2026-10-18).
function M.chrome(world, pmc, sec, mid)
    if not (sec.nrm and #sec.nrm > 0) then return end
    local cr = M.controller().PlayerCameraManager:GetCameraRotation()
    local rp, ry, rr = math.rad(cr.Pitch), math.rad(cr.Yaw), math.rad(cr.Roll)
    local cp, sp, cy, sy, cro, sro = math.cos(rp), math.sin(rp), math.cos(ry), math.sin(ry), math.cos(rr), math.sin(rr)
    local Rx, Ry, Rz = sro * sp * cy - cro * sy, sro * sp * sy + cro * cy, -sro * cp
    local Ux, Uy, Uz = -(cro * sp * cy + sro * sy), cy * sro - cro * sp * sy, cro * cp
    local q = pmc:K2_GetComponentToWorld().Rotation
    local qx, qy, qz, qw = q.X, q.Y, q.Z, q.W
    local w = {}
    for k, v in pairs(sec) do w[k] = v end
    local uv, col, nrm = {}, {}, sec.nrm
    for i = 0, #nrm // 3 - 1 do
        local x, y, z = nrm[i * 3 + 1], nrm[i * 3 + 2], nrm[i * 3 + 3]
        local tx, ty, tz = 2.0 * (qy * z - qz * y), 2.0 * (qz * x - qx * z), 2.0 * (qx * y - qy * x)
        local nx, ny, nz = x + qw * tx + (qy * tz - qz * ty), y + qw * ty + (qz * tx - qx * tz), z + qw * tz + (qx * ty - qy * tx)
        uv[i * 2 + 1] = 0.5 + 0.5 * (nx * Rx + ny * Ry + nz * Rz)
        uv[i * 2 + 2] = 0.5 - 0.5 * (nx * Ux + ny * Uy + nz * Uz)
        col[i * 4 + 1], col[i * 4 + 2], col[i * 4 + 3], col[i * 4 + 4] = 1.0, 1.0, 1.0, 1.0
    end
    w.uv, w.col = uv, col
    M.add_sections(world, pmc, { w })
    pmc:SetMaterial(sec.id, mid)
end

-- hidden, collision-only sections for a scene PMC
function M.add_collision(pmc, collision, cid0)
    local cid = cid0 or 1000                -- (a second lot on the same component starts further on: ledges.lua's bars)
    for _, m in ipairs(collision) do
        local n = #m.pos // 3
        local ok, err = pcall(function()
            create_section(pmc, cid, vec_array(m.pos, n), m.idx, {}, {}, {}, true)
            pmc:SetMeshSectionVisible(cid, false)
        end)
        if not ok then log("collision %s failed: %s", tostring(m.source), tostring(err)) end
        cid = cid + 1
    end
    pcall(function() pmc:SetCollisionProfileName(FName("BlockAll"), true) end)
    pcall(function() M.touchable(pmc:GetOwner()) end)          -- (never to be freed: see M.destroy)
    pcall(M.surface, pmc, M.SURFACE)
end

-- STORROR's footsteps come from the physical material under his feet (its SurfaceType); a floor with none is walked
-- in silence ("the feet on ground. or walking audio is gone", 2026-10-15: every floor of the mod's was). Each floor
-- gets a physical material of its own with the surface type asked for (STORROR's own: 1 concrete, 2 dirt, 3 grass,
-- 4 gravel, 5 metal, 6 wood, 7 glass, 8 water - DefaultEngine.ini PhysicalSurfaces), made here and kept by the
-- component's own property (so the collector leaves it).
M.SURFACE = 1
function M.surface(pmc, kind)
    local cls = StaticFindObject("/Script/PhysicsCore.PhysicalMaterial")
    if not (cls and cls:IsValid() and pmc and pmc:IsValid()) then return nil end
    local pm = StaticConstructObject(cls, pmc:GetOwner(), FName("SM64Surface_" .. tostring(pmc:GetAddress())))
    if not (pm and pm:IsValid()) then return nil end
    pm.SurfaceType = kind or M.SURFACE
    pmc:SetPhysMaterialOverride(pm)
    return pm
end

-- ------------------------------------------------------------ actors
local function actor_class() return StaticFindObject("/Script/Engine.StaticMeshActor") end

function M.spawn_actor(world, loc, yaw)
    local a = world:SpawnActor(actor_class(), loc, { Pitch = 0.0, Yaw = yaw or 0.0, Roll = 0.0 })
    if not (a and a:IsValid()) then return nil end
    pcall(function() a.RootComponent:SetMobility(2) end)
    return a
end

function M.add_pmc(actor)
    local cls = StaticFindObject("/Script/ProceduralMeshComponent.ProceduralMeshComponent")
    local c = actor:AddComponentByClass(cls, false, IDENT, false)
    if c and c:IsValid() then
        pcall(function() c:SetMobility(2) end)
        return c
    end
    return nil
end

function M.add_scene(actor)
    local cls = StaticFindObject("/Script/Engine.SceneComponent")
    local c = actor:AddComponentByClass(cls, false, IDENT, false)
    if c and c:IsValid() then
        pcall(function() c:SetMobility(2) end)
        return c
    end
    return nil
end

M.keep = {}     -- actors (by address) that sweep_stale must leave alone (sky, menu)

-- Never freed: anything the athlete could have touched. STORROR's parkour component keeps bare pointers to the
-- components its traces hit - the floor at +0x188, another at +0xaf8, a move's hit at +0x1398, maybe more - which the
-- garbage collector does not see, and its moves warp against them long after: +0xaf8 still held a Dark World floor
-- through a whole visit to the castle and on, and two moves crashed on freed ones (2026-10-15 05:40 after a death in
-- the Dark World, 05:48 two seconds into it again; the 2026-10-14 get-up crashes were the same). Waiting for him to
-- stand elsewhere (M.retire) does not cover it. So an actor with anything that collides is not destroyed but left as
-- a husk: hidden, no collision, its meshes and materials let go, kept for as long as the map lasts (a few KB each).
-- (what collides is what was given collision here, M.add_collision, the mod's only way to it: those actors are noted)
local PMC_CLASS = nil
M.husks = { world = nil, n = 0, touchable = {} }
local function husk_world()
    local here = nil
    pcall(function() here = M.world():GetAddress() end)
    local H = M.husks
    if H.world ~= here then
        -- (a new map: the old one's husks went with it, and their addresses may come round again)
        for k, v in pairs(M.keep) do if v == "husk" then M.keep[k] = nil end end
        H.world, H.n, H.touchable = here, 0, {}
    end
end
function M.touchable(actor)
    husk_world()
    pcall(function() M.husks.touchable[actor:GetAddress()] = true end)
end
function M.collides(actor)
    husk_world()
    local ok, addr = pcall(function() return actor:GetAddress() end)
    return ok and M.husks.touchable[addr] == true
end
function M.husk(actor)
    husk_world()
    pcall(function()
        if not actor:IsValid() then return end
        local addr = actor:GetAddress()
        if M.keep[addr] == "husk" then return end
        actor:SetActorHiddenInGame(true)
        actor:SetActorEnableCollision(false)
        PMC_CLASS = PMC_CLASS or StaticFindObject("/Script/ProceduralMeshComponent.ProceduralMeshComponent")
        for _, c in ipairs(actor:K2_GetComponentsByClass(PMC_CLASS)) do
            local o = c:get()
            pcall(function() o:ClearAllMeshSections() end)
            pcall(function() for i = 0, o:GetNumMaterials() - 1 do o:SetMaterial(i, nil) end end)
        end
        M.keep[addr] = "husk"
        M.husks.n = M.husks.n + 1
    end)
end

-- `hit`: whether it collided, when that was found before its collision was turned off (M.retire)
function M.destroy(actor, hit)
    if not actor then return end
    local ok, valid = pcall(function() return actor:IsValid() end)
    if not (ok and valid) then return end
    if hit == nil then hit = M.collides(actor) end
    if hit then M.husk(actor) return end
    pcall(function() actor:K2_DestroyActor() end)
end

-- A model of make_instance's drawn see-through, `alpha` 0..1: each part's sections given Mario 64's blend material with
-- their own texture (as intro.lua fades Peach). Returns the materials, to change their alpha later.
-- (`two_sided`: the blend material drawing both sides of each face - the plain one draws only the side the mirrored
-- models turn inward, and a Boo showed its inside)
local BLEND = "/InterchangeAssets/gltf/MaterialInstances/MI_Unlit_Blend.MI_Unlit_Blend"
local BLEND_DS = "/InterchangeAssets/gltf/MaterialInstances/MI_Unlit_Blend_DS.MI_Unlit_Blend_DS"
local see_serial = 0
function M.see_through(world, inst, alpha, two_sided)
    local mids = {}
    local parent = M.try_load(two_sided and BLEND_DS or BLEND) or M.try_load(BLEND)
    if not (parent and inst and inst.data) then return mids end
    local KML = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    local by_tex = {}
    for i, part in ipairs(inst.data.parts) do
        local comp = inst.comps[i]
        for _, sec in ipairs(part.sections or {}) do
            local key = tostring(sec.texture)
            local mid = by_tex[key]
            if not mid then
                see_serial = see_serial + 1
                pcall(function()
                    mid = KML:CreateDynamicMaterialInstance(world, parent, FName("SM64SeeThrough" .. see_serial), 0)
                    if sec.texture then
                        local tex = M.texture(world, M.clamp_file(sec.texture))
                        if tex then mid:SetTextureParameterValue(FName("BaseColorTexture"), tex) end
                    end
                    mid:SetVectorParameterValue(FName("BaseColorFactor"), { R = 1.0, G = 1.0, B = 1.0, A = alpha })
                end)
                by_tex[key] = mid
                if mid then mids[#mids + 1] = mid end
            end
            if comp and mid then pcall(function() comp:SetMaterial(sec.id, mid) end) end
        end
    end
    return mids
end

-- Cameras of our own (cutscenes, the menus, the star select): one for each use, made once for a map and never
-- destroyed. STORROR may keep a bare pointer to what the view last looked through: two crashes on a freed component
-- (2026-10-14 22:42 and 2026-10-15 01:09) both came just after the Bowser entrance's camera was destroyed and the
-- athlete was knocked flat. A camera that stays cannot be left behind freed. `key` names the use.
local cams = { world = nil, list = {} }
function M.camera(world, key, loc, rot)
    local here = nil
    pcall(function() here = world:GetAddress() end)
    if cams.world ~= here then cams.world, cams.list = here, {} end
    local c = cams.list[key]
    local ok = c ~= nil and pcall(function() return c:IsValid() end) and c:IsValid()
    loc, rot = loc or M.OFFSET, rot or { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }
    if not ok then
        c = world:SpawnActor(StaticFindObject("/Script/Engine.CameraActor"), loc, rot)
        if not c then return nil end
        pcall(function() M.keep[c:GetAddress()] = "camera" end)
        cams.list[key] = c
    else
        -- (set, not teleported: a teleport into a wall is refused, and the camera stayed where it last was - a Toad's
        -- talk in the castle was seen from the Whomp King's summit, 2026-10-16)
        pcall(function() c:K2_SetActorLocationAndRotation(loc, rot, false, {}, true) end)
    end
    return c
end

-- ------------------------------------------------------------ a scene's actors go only once he stands elsewhere
-- STORROR keeps the floor under the athlete as a bare pointer in its parkour component (offset 0x188, not seen by the
-- garbage collector) and warps his get-up against it. It takes up a new floor only once he is on his feet. A scene
-- torn down while he was down or getting up (dying while knocked flat, the ending's cuts) had its floor freed by the
-- next garbage collection, and STORROR read the freed memory: the crashes in its motion warping, 2026-10-14.
-- So when a scene goes its actors are hidden and made untouchable, and destroyed once he has stood on the new one -
-- those that collide only emptied, never freed (M.destroy: STORROR holds other such pointers for far longer).
M.retired = { world = nil, list = {}, t = 0.0, steady = 0.0 }

function M.retire(actor)
    if not actor then return end
    -- (the last scene's batch still going: finished first, before this scene's actors join the list and the next
    -- scene's are spawned)
    if M.retired.dying then M.finish_dying() end
    local addr, hit = nil, nil
    pcall(function()
        if not actor:IsValid() then return end
        addr = actor:GetAddress()
        if not M.keep[addr] then hit = M.collides(actor) end
        actor:SetActorHiddenInGame(true)
        actor:SetActorEnableCollision(false)
    end)
    if not addr or M.keep[addr] then return end
    local R = M.retired
    local here = nil
    pcall(function() here = M.world():GetAddress() end)
    if R.world ~= here then M.drop_retired() end
    R.world = here
    M.keep[addr] = "retired"
    R.list[#R.list + 1] = { actor = actor, addr = addr, hit = hit }
    R.t, R.steady = 0.0, 0.0
end

-- the map went: its actors went with it, forget them untouched
function M.drop_retired()
    local R = M.retired
    for _, e in ipairs(R.dying or {}) do if M.keep[e.addr] == "dying" then M.keep[e.addr] = nil end end
    R.dying = nil                      -- (gone with their map: never touched again)
    for _, e in ipairs(R.list) do if M.keep[e.addr] == "retired" then M.keep[e.addr] = nil end end
    R.list, R.world = {}, nil
end

function M.retired_count() return #M.retired.list + (M.retired.dying and #M.retired.dying or 0) end

-- One retired actor destroyed (M.destroy), if it is still the one retired: still noted as dying, hidden, no collision.
-- (Only so: the list holds bare objects, and one freed by anything else can come back as a new scene's actor at the
-- same address - the old scene's batch, left waiting into the next scene, took that scene's floors and railings:
-- "fell through map multiple times", "the railing was missing completely", 2026-11-01.)
local function destroy_dying(e)
    if M.keep[e.addr] ~= "dying" then return end
    M.keep[e.addr] = nil
    local still = true
    pcall(function()
        if not e.actor:IsValid() or e.actor:GetAddress() ~= e.addr then still = false; return end
        if e.actor:GetActorEnableCollision() then still = false; return end
        if e.actor.bHidden == false then still = false end
    end)
    if still then M.destroy(e.actor, e.hit or false) end
end

-- the batch now, all of it (a scene going while the last one's batch was still being destroyed)
function M.finish_dying()
    local R = M.retired
    local list = R.dying
    if not list then return end
    R.dying = nil
    for i = #list, 1, -1 do destroy_dying(list[i]) end
    log("destroyed %d actors of the last scene at once (%d kept as husks, %d in all)", R.dying_n or 0, R.dying_h or 0, M.husks.n)
end

-- settled: he is on his feet, not knocked down or getting up. The retired actors go after 2 s of that, 5 s at least
-- after the last one was retired (STORROR took up the new floor within 0.01 s of his landing in a test).
function M.tick_retired(dt, settled)
    local R = M.retired
    if #R.list == 0 and not R.dying then return end
    local here = nil
    pcall(function() here = M.world():GetAddress() end)
    if here ~= R.world then M.drop_retired(); return end
    -- (a few a tick, not all at once: 171 of them in one tick, 5 s into a level, was a hitch - "lag when enter
    -- levels", 2026-11-01. Ticked till the batch is empty: the list being empty stopped it half way, and the rest
    -- waited into the next scene)
    if R.dying then
        for _ = 1, 12 do
            local e = table.remove(R.dying)
            if not e then break end
            destroy_dying(e)
        end
        if #R.dying == 0 then
            log("destroyed %d actors of the last scene (%d kept as husks, %d in all)", R.dying_n, R.dying_h, M.husks.n)
            R.dying = nil
        end
        return
    end
    R.t = R.t + dt
    R.steady = settled and (R.steady + dt) or 0.0
    if R.t < 5.0 or R.steady < 2.0 then return end
    local list = R.list
    R.list = {}
    local husked = 0
    for _, e in ipairs(list) do
        -- (still kept from the sweep at a scene load while they wait: only destroy_dying frees them)
        if M.keep[e.addr] == "retired" then M.keep[e.addr] = "dying" end
        if e.hit then husked = husked + 1 end
    end
    if #list == 0 then return end
    R.dying, R.dying_n, R.dying_h = list, #list - husked, husked
end

-- remove every actor this mod ever spawned (they all live high above the world)
function M.sweep_stale()
    local n = 0
    for _, cname in ipairs({ "StaticMeshActor" }) do
        local ok, list = pcall(FindAllOf, cname)
        if ok and list then
            for _, a in ipairs(list) do
                pcall(function()
                    if a:IsValid() and not M.keep[a:GetAddress()] and a:K2_GetActorLocation().Z > 250000 then
                        M.destroy(a)            -- (M.retire while a scene is torn down)
                        n = n + 1
                    end
                end)
            end
        end
    end
    if n > 0 then log("swept %d stale actors", n) end
end

-- Build a posable multi-part actor ("instance") from exported actor data.
function M.make_instance(world, data, loc, yaw, scale)
    local actor = M.spawn_actor(world, loc, yaw)
    if not actor then return nil end
    local comps = {}
    for i, p in ipairs(data.parts) do
        local comp
        if #p.sections > 0 then
            comp = M.add_pmc(actor)
            if comp then
                pcall(function() comp:SetCollisionEnabled(0) end)
                -- (a model casts its real shadow - when the sun casts any: game.lua G.set_realtime_shadows - but not a
                -- picture turned to the camera, whose shadow would turn with it: "still multiple objects missing
                -- shadows", 2026-10-30)
                local cast = not p.billboard
                pcall(function() comp:SetCastShadow(cast) end)
                M.add_sections(world, comp, p.sections)
                -- (a picture turned to the camera: its shadow from a twin turned to the sun - M.shade_twin)
                if p.billboard then pcall(M.shade_twin, world, actor, comp, p.sections) end
            end
        else
            comp = M.add_scene(actor)
        end
        if comp and p.parent >= 0 and comps[p.parent + 1] then
            pcall(function() comp:K2_AttachToComponent(comps[p.parent + 1], FName("None"), 2, 2, 2, false) end)
        end
        comps[i] = comp or false
    end
    if scale and scale ~= 1.0 then
        pcall(function() actor:SetActorScale3D({ X = scale, Y = scale, Z = scale }) end)
    end
    local inst = { actor = actor, comps = comps, data = data, last_fi = -1, yaw = yaw or 0.0 }
    M.pose(inst, nil, 0)
    return inst
end

local function yaw_quat(deg)
    local h = math.rad(deg) * 0.5
    return 0.0, 0.0, math.sin(h), math.cos(h)
end

-- Pose every part from animation `anim` at (float) frame `f`.  Pass anim=nil for the bind pose.
function M.pose(inst, anim, f)
    local data = inst.data
    local fi = math.floor(f or 0)
    if anim then fi = fi % anim.frames end
    inst.last_fi = fi
    for i, p in ipairs(data.parts) do
        local comp = inst.comps[i]
        if comp and not p.billboard then
            local tx, ty, tz = p.off[1], p.off[2], p.off[3]
            local qx, qy, qz, qw = 0.0, 0.0, 0.0, 1.0
            if p.rot then qx, qy, qz, qw = p.rot[1], p.rot[2], p.rot[3], p.rot[4] end
            if anim and p.bone ~= nil then
                local r = anim.rot[p.bone + 1]
                if r then
                    local b = fi * 4
                    qx, qy, qz, qw = r[b + 1], r[b + 2], r[b + 3], r[b + 4]
                end
                if p.bone == 0 then
                    tx = tx + anim.trans[fi * 3 + 1]
                    ty = ty + anim.trans[fi * 3 + 2]
                    tz = tz + anim.trans[fi * 3 + 3]
                end
            end
            pcall(function()
                comp:K2_SetRelativeTransform({
                    Rotation = { X = qx, Y = qy, Z = qz, W = qw },
                    Translation = { X = tx, Y = ty, Z = tz },
                    Scale3D = M.ONE,
                }, false, {}, true)
            end)
        end
    end
end

-- billboard parts: turn their local -X axis toward the camera (yaw only)
function M.face_camera(inst, ax, ay, cx, cy)
    local yaw = math.deg(math.atan(cy - ay, cx - ax)) + 180.0 - inst.yaw
    local qx, qy, qz, qw = yaw_quat(yaw)
    for i, p in ipairs(inst.data.parts) do
        local comp = inst.comps[i]
        if comp and p.billboard then
            pcall(function()
                comp:K2_SetRelativeTransform({
                    Rotation = { X = qx, Y = qy, Z = qz, W = qw },
                    Translation = { X = p.off[1], Y = p.off[2], Z = p.off[3] },
                    Scale3D = M.ONE,
                }, false, {}, true)
            end)
        end
    end
end

function M.set_pose(inst, x, y, z, yaw)
    inst.yaw = yaw
    pcall(function()
        inst.actor:K2_SetActorLocationAndRotation({ X = x, Y = y, Z = z }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false, {}, true)
    end)
end

-- flat textured quad facing -X (billboard-ready) or arbitrary corners
function M.quad_actor(world, loc, size, texture, layer)
    local actor = M.spawn_actor(world, loc, 0.0)
    if not actor then return nil end
    local pmc = M.add_pmc(actor)
    if not pmc then return nil end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    local s = size
    local sec = {
        id = 0, layer = layer or "alpha", texture = texture, nverts = 4, ntris = 2,
        pos = { 0, -s, -s, 0, s, -s, 0, s, s, 0, -s, s },
        uv = { 0, 1, 1, 1, 1, 0, 0, 0 },
        col = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
        nrm = { -1, 0, 0, -1, 0, 0, -1, 0, 0, -1, 0, 0 },
        idx = { 0, 1, 2, 0, 2, 3 },
    }
    M.add_sections(world, pmc, { sec })
    -- (it is turned to the camera: no shadow of its own, a twin turned to the sun casts it - M.shade_twin)
    pcall(function() pmc:SetCastShadow(false) end)
    pcall(M.shade_twin, world, actor, pmc, { sec })
    return actor
end

function M.bounce(pawn, vx, vy, vz)
    -- (a bounce straight up - a stomp - keeps his way on across: replacing it stopped him dead on every enemy he
    -- landed on, "koopa stops you momentum when killing him", 2026-10-17; the goombas' own already kept it)
    local keep = (vx or 0.0) == 0.0 and (vy or 0.0) == 0.0
    local ok = pcall(function() pawn:LaunchCharacter({ X = vx, Y = vy, Z = vz }, not keep, true) end)
    return ok
end


-- ------------------------------------------------------------ posing (replaces M.pose, M.face_camera, M.set_pose above)
-- The originals posed every part through K2_SetRelativeTransform / K2_SetActorLocationAndRotation, which hand
-- back an FHitResult. Called a thousand times a second for the goombas, that out-parameter crashed the game.
-- These never call a function with an out-parameter: parts get their RelativeLocation / RelativeRotation
-- properties written directly, and K2_TeleportTo on the actor's root makes every attached part pick them up.

local deg, rad, atan, asin, sqrt, floor = math.deg, math.rad, math.atan, math.asin, math.sqrt, math.floor

local function quat_rot(x, y, z, w)
    local s = z * x - w * y
    local yaw = deg(atan(2 * (w * z + x * y), 1 - 2 * (y * y + z * z)))
    local pitch, roll
    if s < -0.4999995 then
        pitch = -90.0
        roll = -yaw - deg(2 * atan(x, w))
    elseif s > 0.4999995 then
        pitch = 90.0
        roll = yaw - deg(2 * atan(x, w))
    else
        pitch = deg(asin(2 * s))
        roll = deg(atan(-2 * (w * x + y * z), 1 - 2 * (x * x + y * y)))
    end
    roll = (roll + 180.0) % 360.0 - 180.0
    return { Pitch = pitch, Yaw = yaw, Roll = roll }
end

-- shortest-path blend of two unit quaternions (normalised lerp: plenty between neighbouring frames)
local function blend(ax, ay, az, aw, bx, by, bz, bw, t)
    if ax * bx + ay * by + az * bz + aw * bw < 0 then bx, by, bz, bw = -bx, -by, -bz, -bw end
    local x, y, z, w = ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t, aw + (bw - aw) * t
    local n = sqrt(x * x + y * y + z * z + w * w)
    if n < 1e-9 then return ax, ay, az, aw end
    return x / n, y / n, z / n, w / n
end

local function refresh(inst)
    pcall(function()
        local a = inst.actor
        local l = a:K2_GetActorLocation()
        local prev = inst.nudge or 0.0
        inst.nudge = (prev == 0.02) and 0.0 or 0.02
        a:K2_TeleportTo({ X = l.X, Y = l.Y, Z = l.Z - prev + inst.nudge }, { Pitch = 0.0, Yaw = inst.yaw or 0.0, Roll = 0.0 })
    end)
end

-- Pose every part from `anim` at frame `f`. A fractional frame blends the two frames around it, so a
-- 30-frames-a-second Mario 64 animation still moves smoothly at whatever rate the game is drawing.
function M.pose(inst, anim, f)
    local data = inst.data
    f = f or 0
    local fi = floor(f)
    local t = f - fi
    local fj = fi + 1
    if anim then
        fi = fi % anim.frames
        fj = fj % anim.frames
        if anim.hold and fj < fi then fj = fi end      -- one-shot clips stop on their last frame
    end
    inst.last_fi = fi
    for i, p in ipairs(data.parts) do
        local comp = inst.comps[i]
        if comp and not p.billboard then
            local tx, ty, tz = p.off[1], p.off[2], p.off[3]
            local qx, qy, qz, qw = 0.0, 0.0, 0.0, 1.0
            if p.rot then qx, qy, qz, qw = p.rot[1], p.rot[2], p.rot[3], p.rot[4] end
            if anim and p.bone ~= nil then
                local r = anim.rot[p.bone + 1]
                if r then
                    local a, b = fi * 4, fj * 4
                    qx, qy, qz, qw = r[a + 1], r[a + 2], r[a + 3], r[a + 4]
                    if t > 0.001 then qx, qy, qz, qw = blend(qx, qy, qz, qw, r[b + 1], r[b + 2], r[b + 3], r[b + 4], t) end
                    if inst.mirror then qx, qy, qz = -qx, -qy, -qz end      -- the other leaf of a double door swings the other way round
                end
                if p.bone == 0 then
                    local a, b = fi * 3, fj * 3
                    local tr = anim.trans
                    tx = tx + tr[a + 1] + (tr[b + 1] - tr[a + 1]) * t
                    ty = ty + tr[a + 2] + (tr[b + 2] - tr[a + 2]) * t
                    tz = tz + tr[a + 3] + (tr[b + 3] - tr[a + 3]) * t
                end
            end
            pcall(function()
                comp.RelativeLocation = { X = tx, Y = ty, Z = tz }
                comp.RelativeRotation = quat_rot(qx, qy, qz, qw)
            end)
        end
    end
    if not inst.moves then refresh(inst) end
end

-- Billboards the way Mario 64 does them: the part ignores whatever its parents are doing and turns
-- to face the camera, up and down as well as around. (ax, ay) is the actor; the camera is read here.
function M.face_camera(inst, ax, ay)
    -- (a model with no such part: nothing to turn - its place and the camera's were read for each one every frame, for
    -- nothing, 2026-11-05)
    local hb = inst.has_bb
    if hb == nil then
        hb = false
        for _, p in ipairs(inst.data and inst.data.parts or {}) do
            if p.billboard then hb = true; break end
        end
        inst.has_bb = hb
    end
    if not hb then return end
    local az = inst.z or 0.0
    pcall(function() az = inst.actor:K2_GetActorLocation().Z end)
    local cx, cy, cz = M.camera_location({ X = ax, Y = ay + 500.0, Z = az })
    local dx, dy, dz = cx - ax, cy - ay, cz - az
    local yaw = deg(atan(dy, dx)) + 180.0
    local pitch = -deg(atan(dz, sqrt(dx * dx + dy * dy)))
    for i, p in ipairs(inst.data.parts) do
        local comp = inst.comps[i]
        if comp and p.billboard then
            pcall(function()
                if not inst.bb_abs then comp:SetAbsolute(false, true, false) end
                comp.RelativeLocation = { X = p.off[1], Y = p.off[2], Z = p.off[3] }
                comp.RelativeRotation = { Pitch = pitch, Yaw = yaw, Roll = 0.0 }
            end)
        end
    end
    inst.bb_abs = true
end

function M.set_pose(inst, x, y, z, yaw)
    inst.yaw = yaw
    inst.moves = true
    pcall(function()
        local prev = inst.nudge or 0.0
        inst.nudge = (prev == 0.02) and 0.0 or 0.02
        inst.actor:K2_TeleportTo({ X = x, Y = y, Z = z + inst.nudge }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 })
    end)
end

-- Move the points of a mesh section that is already made and, given `cols` or `uvs`, recolour it or slide its
-- texture. The engine's
-- function takes every part of a section at once; an empty list leaves that part as it is.
local update_sig = nil
function M.update_section(pmc, id, verts, cols, uvs)
    if update_sig == nil then
        update_sig = false
        local fn = StaticFindObject("/Script/ProceduralMeshComponent.ProceduralMeshComponent:UpdateMeshSection_LinearColor")
        if fn and fn:IsValid() then
            local names = {}
            local ok = pcall(function() fn:ForEachProperty(function(p) names[#names + 1] = p:GetFName():ToString() end) end)
            if ok and #names > 0 then update_sig = names end
        end
    end
    local args
    if update_sig then
        args = {}
        for i, name in ipairs(update_sig) do
            local n = name:lower()
            if n == "sectionindex" then args[i] = id
            elseif n == "vertices" then args[i] = verts
            elseif n:find("color", 1, true) then args[i] = cols or {}
            elseif n == "uv0" then args[i] = uvs or {}
            elseif n:sub(1, 1) == "b" then args[i] = false
            else args[i] = {} end
        end
    else
        args = { id, verts, {}, uvs or {}, {}, {}, {}, cols or {}, {}, false }
    end
    pmc:UpdateMeshSection_LinearColor(table.unpack(args, 1, #args))
end

return M
