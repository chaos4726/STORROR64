-- Edges he hangs from as from a bar: every edge with less than 130 cm of side under it ("block 5 is the only acceptable
-- hang block every one before it should trigger a hang with the bar instead", then "meassure box 5s verticle width. if
-- the width of the area is smaller on any platform the player should swing", 2026-10-17 - box 5 was 130 cm thick).
-- STORROR picks for itself: it swings from an edge whose side under the hands is about 30 cm or less and wall-climbs
-- the rest, measured by its own traces (its SwingingBarWidth setting changes nothing). Tried on a test rig over BitDW:
-- a 100 cm block whose side below a 25 cm lip blocks only him (Pawn), the camera and loose body parts, every other
-- channel let through, is swung from every time; the same block whole is wall-climbed. So here the faces under each
-- such edge, below a 25 cm lip, go into a piece of collision of their own made that way: solid as ever to him, out of
-- STORROR's sight. (Unseen bars along the edges, tried first, lost to its wall grab every time.)
-- An edge: a floor's edge, looked at every 10 cm, where
--   no floor goes on past it (15 out, 25 up or down),
--   no wall rises at it (30 up, 5 in to 15 out),
--   no ground is close under it (40 out, 5 to 170 down: he would stand there, and STORROR's own ways are left) - unless
--     its face leans in (none within 15 in, 30 down),
--   and its side ends within 130 down (no face within 45 in from the edge's line, at some depth to 130).
local lib = require("lib")
local M = {}

local FLOORMIN, STEP, CELL, MINLEN = 0.7, 10.0, 200.0, 30.0
local SIDE_MAX, WALL_IN = 130.0, 45.0                   -- (a side as tall as box 5 is a wall; its face within 45 in)
M.LIP, M.HIDE_IN, M.HIDE_OUT, M.HIDE_DOWN, M.CAP_IN = 25.0, 160.0, 10.0, 170.0, 150.0
M.cache = {}
M.HUBS = { castle = true, castle2 = true, castle3 = true, courtyard = true, grounds = true }
-- Pieces whose edges stay STORROR's own ledges, never bars, by scene: boxes { x0, x1, y0, y1, z0, z1 } (scene cm), an
-- edge whose middle is in one left out. (Bowser in the Sky's two beams between the wooden pillars, laid flat, 110 cm
-- thick - bars, and he got stuck climbing onto one: "was getting stuck on something from climbing that block",
-- 2026-11-02. Their tops' edges, hung from and climbed up now as any ledge)
M.PLAIN = {
    bits = { { 430.0, 925.0, -165.0, -20.0, 2240.0, 2280.0 }, { 430.0, 925.0, -1395.0, -1250.0, 2316.0, 2356.0 } },
}

local sqrt, floor, abs, min, max = math.sqrt, math.floor, math.abs, math.min, math.max

local function cell_key(i, j) return i * 65536 + j end

-- every triangle of `meshes` (each { pos, idx }: scene centimetres, 0-based corners) with its upward normal z.
-- (The scene is Mario 64 mirrored, so the corners wind the other way: the normal is minus the cross product.)
local function each_tri(meshes, fn)
    for mi, m in ipairs(meshes) do
        local pos, idx = m.pos, m.idx
        if pos and idx then
            for t = 1, #idx - 2, 3 do
                local i1, i2, i3 = idx[t] * 3, idx[t + 1] * 3, idx[t + 2] * 3
                local ax, ay, az = pos[i1 + 1], pos[i1 + 2], pos[i1 + 3]
                local bx, by, bz = pos[i2 + 1], pos[i2 + 2], pos[i2 + 3]
                local cx, cy, cz = pos[i3 + 1], pos[i3 + 2], pos[i3 + 3]
                if ax and bx and cx then
                    local ux, uy, uz = bx - ax, by - ay, bz - az
                    local wx, wy, wz = cx - ax, cy - ay, cz - az
                    local nx, ny, nz = -(uy * wz - uz * wy), -(uz * wx - ux * wz), -(ux * wy - uy * wx)
                    local l = sqrt(nx * nx + ny * ny + nz * nz)
                    if l > 1e-6 then fn(ax, ay, az, bx, by, bz, cx, cy, cz, nz / l, mi, t) end
                end
            end
        end
    end
end

local function add_cells(grid, x0, y0, x1, y1, item)
    for i = floor(min(x0, x1) / CELL), floor(max(x0, x1) / CELL) do
        for j = floor(min(y0, y1) / CELL), floor(max(y0, y1) / CELL) do
            local k = cell_key(i, j)
            local l = grid[k]
            if not l then l = {}; grid[k] = l end
            l[#l + 1] = item
        end
    end
end

-- The swing edges of `meshes`, and the grids of their triangles: { { ax, ay, az, bx, by, bz, ox, oy }, ... }
local function swing_edges(meshes)
    local fgrid, wgrid, floors, fedge, walls = {}, {}, {}, {}, {}
    local function rk(x) return floor(x * 10.0 + 0.5) end
    local function vkey(x, y, z) return rk(x) .. "," .. rk(y) .. "," .. rk(z) end
    local function ekey(k1, k2) return (k1 < k2) and (k1 .. "|" .. k2) or (k2 .. "|" .. k1) end
    each_tri(meshes, function(ax, ay, az, bx, by, bz, cx, cy, cz, nz, mi, t)
        local v = { ax, ay, az, bx, by, bz, cx, cy, cz, mi = mi, t = t, nz = nz }
        local x0, y0, x1, y1 = min(ax, bx, cx), min(ay, by, cy), max(ax, bx, cx), max(ay, by, cy)
        if nz >= 0.3 then
            add_cells(fgrid, x0, y0, x1, y1, v)
            local ka, kb, kc = vkey(ax, ay, az), vkey(bx, by, bz), vkey(cx, cy, cz)
            for _, e in ipairs({ ekey(ka, kb), ekey(kb, kc), ekey(kc, ka) }) do fedge[e] = (fedge[e] or 0) + 1 end
            if nz >= FLOORMIN then v.keys = { ka, kb, kc }; floors[#floors + 1] = v end
        else
            add_cells(wgrid, x0, y0, x1, y1, v)
            walls[#walls + 1] = v
        end
    end)
    local function floor_in(x, y, z0, z1)
        local l = fgrid[cell_key(floor(x / CELL), floor(y / CELL))]
        if not l then return false end
        for _, v in ipairs(l) do
            local ax, ay, az, bx, by, bz, cx, cy, cz = v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9]
            local d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(d) > 1e-9 then
                local l1 = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / d
                local l2 = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / d
                local l3 = 1.0 - l1 - l2
                if l1 >= -1e-4 and l2 >= -1e-4 and l3 >= -1e-4 then
                    local z = l1 * az + l2 * bz + l3 * cz
                    if z >= z0 and z <= z1 then return true end
                end
            end
        end
        return false
    end
    -- (a level ray, x y z along dx dy, against everything but floors: is anything within maxd)
    local function wall_hit(x, y, z, dx, dy, maxd)
        local x1, y1 = x + dx * maxd, y + dy * maxd
        local done = {}
        for i = floor(min(x, x1) / CELL), floor(max(x, x1) / CELL) do
            for j = floor(min(y, y1) / CELL), floor(max(y, y1) / CELL) do
                local l = wgrid[cell_key(i, j)]
                if l then
                    for _, v in ipairs(l) do
                        if not done[v] then
                            done[v] = true
                            local ax, ay, az = v[1], v[2], v[3]
                            local e1x, e1y, e1z = v[4] - ax, v[5] - ay, v[6] - az
                            local e2x, e2y, e2z = v[7] - ax, v[8] - ay, v[9] - az
                            local px, py, pz = dy * e2z, -dx * e2z, dx * e2y - dy * e2x
                            local det = e1x * px + e1y * py + e1z * pz
                            if abs(det) > 1e-9 then
                                local inv = 1.0 / det
                                local tx, ty, tz = x - ax, y - ay, z - az
                                local u = (tx * px + ty * py + tz * pz) * inv
                                if u >= 0.0 and u <= 1.0 then
                                    local qx, qy, qz = ty * e1z - tz * e1y, tz * e1x - tx * e1z, tx * e1y - ty * e1x
                                    local w = (dx * qx + dy * qy) * inv
                                    if w >= 0.0 and u + w <= 1.0 then
                                        local t = (e2x * qx + e2y * qy + e2z * qz) * inv
                                        if t >= 0.0 and t <= maxd then return true end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return false
    end
    local function swing_at(x, y, z, ox, oy)
        if floor_in(x + ox * 15.0, y + oy * 15.0, z - 25.0, z + 25.0) then return false end
        if wall_hit(x - ox * 5.0, y - oy * 5.0, z + 30.0, ox, oy, 20.0) then return false end
        -- (ground close under it: a low wall, STORROR's own to climb or vault - unless the face under the edge leans in,
        -- with nothing there for STORROR at all: BitDW's yellow platform over its walkway, "no the yellow platform with
        -- the underhang", 2026-10-17)
        if floor_in(x + ox * 40.0, y + oy * 40.0, z - 170.0, z - 5.0)
            and wall_hit(x + ox * 30.0, y + oy * 30.0, z - 30.0, -ox, -oy, 30.0 + 15.0) then return false end
        for d = 10.0, SIDE_MAX, 10.0 do
            if not wall_hit(x + ox * 30.0, y + oy * 30.0, z - d, -ox, -oy, 30.0 + WALL_IN) then return true end
        end
        return false
    end
    -- Railings: a standing wall's top edge with nothing on it or over it, the wall as thin as paper, at most 170 over a
    -- floor on one side and over a drop on the other, 150 long at least - BitDW's bridge railings, a single face 70 cm
    -- high. STORROR took hold of a top as thin as paper and it went wrong ("grabbing fencing here is buggy",
    -- 2026-10-17). Each gets a beam along its top, 8 wide and 25 deep: a top to hold, as a wall's (tried on a copy of
    -- the bridge: a pole hang there swung him into the floor 70 under the railing; the wall hang "ehh good enough").
    local cgrid, wedge = {}, {}
    for _, v in ipairs(walls) do
        if v.nz < -0.3 then add_cells(cgrid, min(v[1], v[4], v[7]), min(v[2], v[5], v[8]), max(v[1], v[4], v[7]), max(v[2], v[5], v[8]), v) end
        if abs(v.nz) < 0.15 then
            local ka, kb, kc = vkey(v[1], v[2], v[3]), vkey(v[4], v[5], v[6]), vkey(v[7], v[8], v[9])
            v.wkeys = { ka, kb, kc }
            for _, e in ipairs({ ekey(ka, kb), ekey(kb, kc), ekey(kc, ka) }) do wedge[e] = (wedge[e] or 0) + 1 end
        end
    end
    local function ceil_in(x, y, z0, z1)
        local l = cgrid[cell_key(floor(x / CELL), floor(y / CELL))]
        if not l then return false end
        for _, v in ipairs(l) do
            local ax, ay, az, bx, by, bz, cx, cy, cz = v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9]
            local d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(d) > 1e-9 then
                local l1 = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / d
                local l2 = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / d
                local l3 = 1.0 - l1 - l2
                if l1 >= -1e-4 and l2 >= -1e-4 and l3 >= -1e-4 then
                    local z = l1 * az + l2 * bz + l3 * cz
                    if z >= z0 and z <= z1 then return true end
                end
            end
        end
        return false
    end
    local fences = {}
    for _, v in ipairs(walls) do
        if v.wkeys then
            for k = 0, 2 do
                local k2, k3 = (k + 1) % 3, (k + 2) % 3
                local p = { v[k * 3 + 1], v[k * 3 + 2], v[k * 3 + 3] }
                local q = { v[k2 * 3 + 1], v[k2 * 3 + 2], v[k2 * 3 + 3] }
                local rx, ry, rz = v[k3 * 3 + 1], v[k3 * 3 + 2], v[k3 * 3 + 3]
                local L = sqrt((q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2)
                -- (its third corner under the edge's line there: a top edge, if nothing else shares it - the line, as the
                -- bridge's railing climbs with the bridge)
                local below = false
                if L >= 150.0 then
                    local t = ((rx - p[1]) * (q[1] - p[1]) + (ry - p[2]) * (q[2] - p[2])) / (L * L)
                    below = rz < p[3] + (q[3] - p[3]) * t - 20.0
                end
                if wedge[ekey(v.wkeys[k + 1], v.wkeys[k2 + 1])] == 1 and below then
                    local ex, ey = (q[1] - p[1]) / L, (q[2] - p[2]) / L
                    local nx, ny = ey, -ex
                    local mx, my, mz = (p[1] + q[1]) * 0.5, (p[2] + q[2]) * 0.5, (p[3] + q[3]) * 0.5
                    local ok = true
                    for _, sg in ipairs({ 1.0, -1.0 }) do
                        for _, dd in ipairs({ 5.0, 20.0, 40.0 }) do
                            if ok and floor_in(mx + nx * dd * sg, my + ny * dd * sg, mz - 10.0, mz + 40.0) then ok = false end
                        end
                        if ok and (ceil_in(mx + nx * 3.0 * sg, my + ny * 3.0 * sg, mz + 2.0, mz + 60.0)
                            or floor_in(mx + nx * 3.0 * sg, my + ny * 3.0 * sg, mz + 2.0, mz + 60.0)) then ok = false end
                    end
                    if ok and (wall_hit(mx + nx, my + ny, mz - 30.0, nx, ny, 15.0) or wall_hit(mx - nx, my - ny, mz - 30.0, -nx, -ny, 15.0)) then ok = false end
                    if ok then
                        local low, drop = false, false
                        for _, sg in ipairs({ 1.0, -1.0 }) do
                            if floor_in(mx + nx * 40.0 * sg, my + ny * 40.0 * sg, mz - 170.0, mz - 40.0) then low = true end
                            if not floor_in(mx + nx * 40.0 * sg, my + ny * 40.0 * sg, mz - 400.0, mz + 5.0) then drop = true end
                        end
                        if low and drop then fences[#fences + 1] = { p = p, q = q, nx = nx, ny = ny, ex = ex, ey = ey, L = L, mi = v.mi } end
                    end
                end
            end
        end
    end
    local seen, edges = {}, {}
    for _, v in ipairs(floors) do
        for k = 0, 2 do
            local k2, k3 = (k + 1) % 3, (k + 2) % 3
            local key = ekey(v.keys[k + 1], v.keys[k2 + 1])
            if not seen[key] and fedge[key] == 1 then
                seen[key] = true
                local p = { v[k * 3 + 1], v[k * 3 + 2], v[k * 3 + 3] }
                local q = { v[k2 * 3 + 1], v[k2 * 3 + 2], v[k2 * 3 + 3] }
                local rx, ry = v[k3 * 3 + 1], v[k3 * 3 + 2]
                local ex, ey = q[1] - p[1], q[2] - p[2]
                local L = sqrt(ex * ex + ey * ey)
                if L >= MINLEN then
                    local ox, oy = ey / L, -ex / L              -- (outward: away from the floor's third corner)
                    if ox * (rx - p[1]) + oy * (ry - p[2]) > 0.0 then ox, oy = -ox, -oy end
                    local m = max(2, floor(L / STEP) + 1)
                    local run
                    for i = 0, m do
                        local t = i / m
                        local ok = swing_at(p[1] + ex * t, p[2] + ey * t, p[3] + (q[3] - p[3]) * t, ox, oy)
                        if ok and not run then run = t end
                        if run and (not ok or i == m) then
                            local t1 = ok and t or (i - 1) / m
                            if (t1 - run) * L >= MINLEN then
                                edges[#edges + 1] = {
                                    p[1] + ex * run, p[2] + ey * run, p[3] + (q[3] - p[3]) * run,
                                    p[1] + ex * t1, p[2] + ey * t1, p[3] + (q[3] - p[3]) * t1,
                                    ox, oy }
                            end
                            run = nil
                        end
                    end
                end
            end
        end
    end
    return edges, wgrid, floor_in, fences
end

-- a convex polygon (list of {x, y, z}) cut by the plane n . p = d: the part with n . p <= d, and the rest. (Corners on
-- the plane go to both parts: kept to one side only, a piece whose edge lay on it - the lip's sides, cut once already
-- at its line - was lost whole at the next cut, and the lips' sides were missing on the rig: "cant grab either of them")
local EPS = 0.01
local function area2(poly)
    local ax, ay, az = 0.0, 0.0, 0.0
    local p0 = poly[1]
    for i = 2, #poly - 1 do
        local a, b = poly[i], poly[i + 1]
        local ux, uy, uz = a[1] - p0[1], a[2] - p0[2], a[3] - p0[3]
        local vx, vy, vz = b[1] - p0[1], b[2] - p0[2], b[3] - p0[3]
        ax, ay, az = ax + uy * vz - uz * vy, ay + uz * vx - ux * vz, az + ux * vy - uy * vx
    end
    return ax * ax + ay * ay + az * az
end
local function cut(poly, nx, ny, nz, d)
    local inside, outside = {}, {}
    local n = #poly
    for i = 1, n do
        local a, b = poly[i], poly[i % n + 1]
        local da = nx * a[1] + ny * a[2] + nz * a[3] - d
        local db = nx * b[1] + ny * b[2] + nz * b[3] - d
        if da <= EPS then inside[#inside + 1] = a end
        if da >= -EPS then outside[#outside + 1] = a end
        if (da < -EPS and db > EPS) or (da > EPS and db < -EPS) then
            local t = da / (da - db)
            local c = { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
            inside[#inside + 1] = c
            outside[#outside + 1] = c
        end
    end
    if #inside < 3 or area2(inside) < 1e-4 then inside = nil end
    if #outside < 3 or area2(outside) < 1e-4 then outside = nil end
    return inside, outside
end

-- The faces under each swing edge, below its lip, taken out: returns the collision without them (a list like
-- `meshes`) and them as one piece ({ source, pos, idx }), or nil when there are none; and the number of edges.
-- `seen`: more solid pieces, looked at but never cut or returned - the level's vanish-cap walls, a collision of their
-- own: SL's igloo's ice wall's sides are, and without them its top was an edge with nothing under it, a bar - "why is
-- the ice wall acting as a swinging pole?", 2026-10-26.
function M.split(meshes, name, seen)
    if name and M.cache[name] then local c = M.cache[name]; return c[1], c[2], c[3] end
    local all = meshes
    if seen and #seen > 0 then
        all = {}
        for _, m in ipairs(meshes) do all[#all + 1] = m end
        for _, m in ipairs(seen) do all[#all + 1] = m end
    end
    local edges, wgrid, floor_in, fences = swing_edges(all)
    if name and M.HUBS[name] then fences = {} end          -- (the castle's: its trapdoor pit's rim and stray walls)
    local plain = name and M.PLAIN[name]
    if plain then
        local keep = {}
        for _, e in ipairs(edges) do
            local mx, my, mz = (e[1] + e[4]) * 0.5, (e[2] + e[5]) * 0.5, (e[3] + e[6]) * 0.5
            local inside = false
            for _, b in ipairs(plain) do
                if mx > b[1] and mx < b[2] and my > b[3] and my < b[4] and mz > b[5] and mz < b[6] then inside = true; break end
            end
            if not inside then keep[#keep + 1] = e end
        end
        edges = keep
    end
    if all ~= meshes then                                   -- (no railing of a piece only looked at)
        local keep = {}
        for _, f in ipairs(fences) do if f.mi <= #meshes then keep[#keep + 1] = f end end
        fences = keep
    end
    if #edges == 0 and #fences == 0 then
        if name then M.cache[name] = { meshes, nil, 0 } end
        return meshes, nil, 0
    end
    -- each edge's box (in its own frame: along, out, up), and the triangles near it
    local pieces = {}                                       -- [triangle] = list of polygons still left of it
    local hid = {}                                          -- polygons taken out
    for _, e in ipairs(edges) do
        local ax, ay, az, bx, by, bz, ox, oy = e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8]
        local ex, ey = bx - ax, by - ay
        local L = sqrt(ex * ex + ey * ey)
        ex, ey = ex / L, ey / L
        local top = min(az, bz) - M.LIP
        local planes = {
            { ox, oy, 0.0, ox * ax + oy * ay + M.HIDE_OUT },              -- no further out than HIDE_OUT
            { -ox, -oy, 0.0, -(ox * ax + oy * ay) + M.HIDE_IN },          -- no further in than HIDE_IN
            { -ex, -ey, 0.0, -(ex * ax + ey * ay) + 5.0 },                -- from its start
            { ex, ey, 0.0, ex * bx + ey * by + 5.0 },                     -- to its end
            { 0.0, 0.0, 1.0, top },                                       -- under the lip
            { 0.0, 0.0, -1.0, -(top - M.HIDE_DOWN) },
        }
        local x0 = min(ax, bx) - M.HIDE_IN - 10.0
        local x1 = max(ax, bx) + M.HIDE_IN + 10.0
        local y0 = min(ay, by) - M.HIDE_IN - 10.0
        local y1 = max(ay, by) + M.HIDE_IN + 10.0
        local done = {}
        for i = floor(x0 / CELL), floor(x1 / CELL) do
            for j = floor(y0 / CELL), floor(y1 / CELL) do
                for _, v in ipairs(wgrid[cell_key(i, j)] or {}) do
                    -- (Mario 64's walls and ceilings only: a steep floor may be a slide floor, which add_slides takes out by itself)
                    if not done[v] and v.mi <= #meshes and v.nz <= 0.01 and min(v[3], v[6], v[9]) < top and max(v[3], v[6], v[9]) > top - M.HIDE_DOWN then
                        done[v] = true
                        local left = pieces[v] or { { { v[1], v[2], v[3] }, { v[4], v[5], v[6] }, { v[7], v[8], v[9] } } }
                        local still = {}
                        for _, poly in ipairs(left) do
                            local inner = poly
                            for _, pl in ipairs(planes) do
                                local inn, out = cut(inner, pl[1], pl[2], pl[3], pl[4])
                                if out then still[#still + 1] = out end
                                inner = inn
                                if not inner then break end
                            end
                            if inner then hid[#hid + 1] = inner end
                        end
                        pieces[v] = still
                    end
                end
            end
        end
    end
    -- the collision again: each mesh without the triangles that were cut, and what is left of those as a mesh more
    local cutset = {}
    for v in pairs(pieces) do cutset[v.mi .. ":" .. v.t] = true end
    local main, rest = {}, { source = "swing edges (rest)", pos = {}, idx = {} }
    for mi, m in ipairs(meshes) do
        local idx = {}
        for t = 1, #m.idx - 2, 3 do
            if not cutset[mi .. ":" .. t] then idx[#idx + 1] = m.idx[t]; idx[#idx + 1] = m.idx[t + 1]; idx[#idx + 1] = m.idx[t + 2] end
        end
        if #idx > 0 then main[#main + 1] = { source = m.source, pos = m.pos, idx = idx } end
    end
    local function add(mesh, poly)
        local base = #mesh.pos // 3
        for _, p in ipairs(poly) do mesh.pos[#mesh.pos + 1] = p[1]; mesh.pos[#mesh.pos + 1] = p[2]; mesh.pos[#mesh.pos + 1] = p[3] end
        for k = 2, #poly - 1 do mesh.idx[#mesh.idx + 1] = base; mesh.idx[#mesh.idx + 1] = base + k - 1; mesh.idx[#mesh.idx + 1] = base + k end
    end
    for _, polys in pairs(pieces) do for _, poly in ipairs(polys) do add(rest, poly) end end
    -- the lip's underside, under each edge: a strip CAP_IN in from its line, LIP down, faced both ways. STORROR takes
    -- an edge for a bar only when it finds the underside close under the hands: on the rig a lip open underneath was
    -- not taken at all, and the game's cut sides alone left the Ferris wheel's blocks wall-climbed ("it doesnt seem like
    -- the poles are on moving platforms", 2026-10-17)
    -- (in as far as the top goes, CAP_IN at most - on the rig a 40 cm strip under a 100 cm block was not enough, STORROR
    -- found the block's own bottom further in - and no further: not out past the far side of a narrow piece)
    for _, e in ipairs(edges) do
        local ax, ay, az, bx, by, bz, ox, oy = e[1], e[2], e[3] - M.LIP, e[4], e[5], e[6] - M.LIP, e[7], e[8]
        local mx, my, mz = (e[1] + e[4]) * 0.5, (e[2] + e[5]) * 0.5, (e[3] + e[6]) * 0.5
        local cap = 0.0
        while cap + 10.0 <= M.CAP_IN and floor_in(mx - ox * (cap + 10.0), my - oy * (cap + 10.0), mz - 40.0, mz + 40.0) do cap = cap + 10.0 end
        cap = math.max(10.0, cap)
        local q = { { ax, ay, az }, { bx, by, bz }, { bx - ox * cap, by - oy * cap, bz }, { ax - ox * cap, ay - oy * cap, az } }
        add(rest, q)
        add(rest, { q[4], q[3], q[2], q[1] })
        -- and the lip itself straight down LIP along the edge's line, both ways: under a leaning face (BitDW's octagons)
        -- the edge was not taken at all - the rig's lips that swung were all straight
        local w = { { e[1], e[2], e[3] }, { e[4], e[5], e[6] }, { bx, by, bz }, { ax, ay, az } }
        add(rest, w)
        add(rest, { w[4], w[3], w[2], w[1] })
    end
    -- each railing's beam: 4 to each side of its face, from its top 25 down, closed, faced both ways
    for _, f in ipairs(fences) do
        local px, py = f.nx * 4.0, f.ny * 4.0
        local P = {}
        for _, c in ipairs({ f.p, f.q }) do
            for _, sg in ipairs({ 1.0, -1.0 }) do
                P[#P + 1] = { c[1] + px * sg, c[2] + py * sg, c[3] }
                P[#P + 1] = { c[1] + px * sg, c[2] + py * sg, c[3] - M.LIP }
            end
        end
        for _, q in ipairs({ { 1, 5, 7, 3 }, { 2, 4, 8, 6 }, { 1, 2, 6, 5 }, { 3, 7, 8, 4 }, { 1, 3, 4, 2 }, { 5, 6, 8, 7 } }) do
            local quad = { P[q[1]], P[q[2]], P[q[3]], P[q[4]] }
            add(rest, quad)
            add(rest, { quad[4], quad[3], quad[2], quad[1] })
        end
    end
    if #rest.idx > 0 then main[#main + 1] = rest end
    local hidden = { source = "swing edges (out of STORROR's sight)", pos = {}, idx = {} }
    for _, poly in ipairs(hid) do add(hidden, poly) end
    if #hidden.idx == 0 then hidden = nil end
    if name then M.cache[name] = { main, hidden, #edges } end
    return main, hidden, #edges
end

-- A piece made solid to him (Pawn, 2), the camera (4) and loose body parts (PhysicsBody 5, PhysicsMesh 17) only
function M.hide(pmc)
    pcall(function()
        pmc:SetCollisionResponseToAllChannels(0)
        for _, ch in ipairs({ 2, 4, 5, 17 }) do pmc:SetCollisionResponseToChannel(ch, 2) end
    end)
end

-- The scene's piece: its own actor at the scene's place
function M.hidden_actor(world, hidden, loc)
    local actor = lib.spawn_actor(world, loc, 0.0)
    local pmc = actor and lib.add_pmc(actor)
    if not pmc then if actor then lib.destroy(actor) end; return nil end
    lib.add_collision(pmc, { hidden })
    M.hide(pmc)
    return actor
end

return M
