p = r'X:/mashup-work/game_cur.lua'
s = open(p, encoding='utf-8').read()


def rep(a, b):
    global s
    assert s.count(a) == 1, (s.count(a), a[:80])
    s = s.replace(a, b)


NEW = r'''-- Warp pipes made deep too ("you need the pipe to go deeper as well", 2026-10-15): the pipe's bottom is cut out (in the
-- picture and the collision, and whatever else lies in its column, trimmed to a square under its walls), its eight
-- inner faces carried on `depth` down with the pipe's own texture at its own scale, lit as each face is at the pipe's
-- foot and darkening to black (`fade`: depth under the foot -> light), with solid walls and a floor at the bottom; its
-- warp waits `trigger` under the foot. Out of it (G.arrive, a death beside it) he starts deep in it.
local DEEP_PIPES = {
    bitdw = { depth = 1500.0, trigger = 450.0, inner = 76.5, hole = 78.0,
              fade = { { 0.0, 1.0 }, { 100.0, 0.6 }, { 300.0, 0.25 }, { 700.0, 0.06 }, { 1200.0, 0.0 } } },
}

-- the parts of a convex polygon on one side of x (axis 1) or y (axis 2) = value; each vertex a list {x, y, z, ...}
-- whose further numbers are carried along by interpolation
local function clip_half(poly, axis, value, keep_less)
    local out = {}
    local n = #poly
    for i = 1, n do
        local a, b = poly[i], poly[i % n + 1]
        local ina, inb
        if keep_less then ina, inb = a[axis] <= value, b[axis] <= value
        else ina, inb = a[axis] >= value, b[axis] >= value end
        if ina then out[#out + 1] = a end
        if ina ~= inb then
            local t = (value - a[axis]) / (b[axis] - a[axis])
            local v = {}
            for k = 1, #a do v[k] = a[k] + (b[k] - a[k]) * t end
            out[#out + 1] = v
        end
    end
    return out
end
-- the parts of a triangle outside the square [x0, x1] x [y0, y1], as convex polygons
local function outside_square(tri, x0, x1, y0, y1)
    local pieces = {}
    local function add(poly) if #poly >= 3 then pieces[#pieces + 1] = poly end end
    add(clip_half(tri, 1, x0, true))
    add(clip_half(tri, 1, x1, false))
    local mid = clip_half(clip_half(tri, 1, x0, false), 1, x1, true)
    if #mid >= 3 then
        add(clip_half(mid, 2, y0, true))
        add(clip_half(mid, 2, y1, false))
    end
    return pieces
end

-- every triangle of a mesh with its corners between z `lo` and `hi` cut away inside the square (a section carries its
-- uv, colour and normal along)
local function carve(m, x0, x1, y0, y1, lo, hi, visual)
    local p, idx = m.pos, m.idx
    if not (p and idx) then return 0 end
    local function vert(i)
        local v = { p[i * 3 + 1], p[i * 3 + 2], p[i * 3 + 3] }
        if visual then
            v[4], v[5] = m.uv[i * 2 + 1], m.uv[i * 2 + 2]
            for k = 1, 4 do v[5 + k] = m.col[i * 4 + k] end
            for k = 1, 3 do v[9 + k] = m.nrm[i * 3 + k] end
        end
        return v
    end
    local function push(v)
        p[#p + 1], p[#p + 2], p[#p + 3] = v[1], v[2], v[3]
        if visual then
            m.uv[#m.uv + 1], m.uv[#m.uv + 2] = v[4], v[5]
            for k = 1, 4 do m.col[#m.col + 1] = v[5 + k] end
            for k = 1, 3 do m.nrm[#m.nrm + 1] = v[9 + k] end
        end
        return #p // 3 - 1
    end
    local keep, cut = {}, 0
    for t = 1, #idx - 2, 3 do
        local a, b, c = idx[t], idx[t + 1], idx[t + 2]
        local A, B, C = vert(a), vert(b), vert(c)
        local zlo, zhi = math.min(A[3], B[3], C[3]), math.max(A[3], B[3], C[3])
        local bx0, bx1 = math.min(A[1], B[1], C[1]), math.max(A[1], B[1], C[1])
        local by0, by1 = math.min(A[2], B[2], C[2]), math.max(A[2], B[2], C[2])
        if zlo < lo or zhi > hi or bx1 <= x0 or bx0 >= x1 or by1 <= y0 or by0 >= y1 then
            keep[#keep + 1], keep[#keep + 2], keep[#keep + 3] = a, b, c
        else
            cut = cut + 1
            for _, poly in ipairs(outside_square({ A, B, C }, x0, x1, y0, y1)) do
                local first = push(poly[1])
                local prev = push(poly[2])
                for k = 3, #poly do
                    local cur = push(poly[k])
                    keep[#keep + 1], keep[#keep + 2], keep[#keep + 3] = first, prev, cur
                    prev = cur
                end
            end
        end
    end
    m.idx, m.ntris = keep, #keep // 3
    if visual then m.nverts = #p // 3 end
    return cut
end

local function deepen_pipes(name, data)
    local h = DEEP_PIPES[name]
    if not h then return end
    for _, o in ipairs(data.objects or {}) do
        if o.kind == "pipe" and o.pos then
            local px, py, foot = o.pos[1], o.pos[2], o.pos[3]
            local bottom = foot - h.depth
            -- (its inner faces as they are at its foot: their texture, and each corner's light, by angle)
            local tex, light = nil, {}
            for _, m in ipairs(data.sections or {}) do
                local p = m.pos or {}
                for i = 1, #p - 2, 3 do
                    local dx, dy = p[i] - px, p[i + 1] - py
                    local r = math.sqrt(dx * dx + dy * dy)
                    if m.texture and m.col and r > h.inner - 3.0 and r < h.inner + 3.0 and math.abs(p[i + 2] - foot) < 1.0 then
                        tex = tex or m.texture
                        local k = math.floor((math.deg(math.atan(dy, dx)) % 360.0) / 45.0 + 0.5) % 8
                        light[k] = light[k] or m.col[(i - 1) // 3 * 4 + 1]
                    end
                end
            end
            local x0, x1, y0, y1 = px - h.hole, px + h.hole, py - h.hole, py + h.hole
            local cut = 0
            for _, m in ipairs(data.sections or {}) do
                if m.uv and m.col and m.nrm then cut = cut + carve(m, x0, x1, y0, y1, bottom - 1.0, foot + 10.0, true) end
            end
            for _, m in ipairs(data.collision or {}) do cut = cut + carve(m, x0, x1, y0, y1, bottom - 1.0, foot + 10.0, false) end
            -- the shaft: eight faces from the foot down, lit as at the foot and darkening; a black floor
            local pos, uv, col, nrm, idx = {}, {}, {}, {}, {}
            local cpos, cidx = {}, {}
            local V = 0.982 / 153.75                   -- (the pipe's inner wall: its texture once over its height)
            local function fade(dep)
                local f = h.fade
                if dep <= f[1][1] then return f[1][2] end
                for i = 2, #f do
                    if dep <= f[i][1] then
                        local a, b = f[i - 1], f[i]
                        return a[2] + (b[2] - a[2]) * (dep - a[1]) / (b[1] - a[1])
                    end
                end
                return f[#f][2]
            end
            local zs = { foot }
            for _, f in ipairs(h.fade) do if f[1] > 0.0 and foot - f[1] > bottom + 1.0 then zs[#zs + 1] = foot - f[1] end end
            zs[#zs + 1] = bottom
            local function vtx(x, y, z, u, v, c, nx, ny, nz)
                pos[#pos + 1], pos[#pos + 2], pos[#pos + 3] = x, y, z
                uv[#uv + 1], uv[#uv + 2] = u, v
                col[#col + 1], col[#col + 2], col[#col + 3], col[#col + 4] = c, c, c, 1.0
                nrm[#nrm + 1], nrm[#nrm + 2], nrm[#nrm + 3] = nx, ny, nz
                return #pos // 3 - 1
            end
            local function cvtx(x, y, z)
                cpos[#cpos + 1], cpos[#cpos + 2], cpos[#cpos + 3] = x, y, z
                return #cpos // 3 - 1
            end
            -- (facing in: the cross product of its edges against its inward normal, < 0, as the castle's pit walls)
            local function face(list, P, a, b, c, nx, ny, nz)
                local ax, ay, az = P[a * 3 + 1], P[a * 3 + 2], P[a * 3 + 3]
                local ux, uy, uz = P[b * 3 + 1] - ax, P[b * 3 + 2] - ay, P[b * 3 + 3] - az
                local wx, wy, wz = P[c * 3 + 1] - ax, P[c * 3 + 2] - ay, P[c * 3 + 3] - az
                local d = (uy * wz - uz * wy) * nx + (uz * wx - ux * wz) * ny + (ux * wy - uy * wx) * nz
                if d > 0 then b, c = c, b end
                list[#list + 1], list[#list + 2], list[#list + 3] = a, b, c
            end
            for k = 0, 7 do
                local a0, a1 = math.rad(k * 45.0), math.rad((k + 1) * 45.0)
                local ax, ay = px + math.cos(a0) * h.inner, py + math.sin(a0) * h.inner
                local bx, by = px + math.cos(a1) * h.inner, py + math.sin(a1) * h.inner
                local am = math.rad(k * 45.0 + 22.5)
                local nx, ny = -math.cos(am), -math.sin(am)
                local la, lb = light[k] or 0.5, light[(k + 1) % 8] or 0.5
                local prev = nil
                for _, z in ipairs(zs) do
                    local v, f = 0.982 + (foot - z) * V, fade(foot - z)
                    local pa = vtx(ax, ay, z, 0.0, v, la * f, nx, ny, 0.0)
                    local pb = vtx(bx, by, z, 0.967, v, lb * f, nx, ny, 0.0)
                    if prev then
                        face(idx, pos, prev[1], prev[2], pb, nx, ny, 0.0)
                        face(idx, pos, prev[1], pb, pa, nx, ny, 0.0)
                    end
                    prev = { pa, pb }
                end
                -- (its collision: one face, the whole way down)
                local c1, c2 = cvtx(ax, ay, foot + 5.0), cvtx(bx, by, foot + 5.0)
                local c3, c4 = cvtx(bx, by, bottom), cvtx(ax, ay, bottom)
                face(cidx, cpos, c1, c2, c3, nx, ny, 0.0)
                face(cidx, cpos, c1, c3, c4, nx, ny, 0.0)
            end
            -- the floor at the bottom, black, facing up (picture and collision)
            local f, cf = {}, {}
            for k = 0, 7 do
                local a = math.rad(k * 45.0)
                local x, y = px + math.cos(a) * h.inner, py + math.sin(a) * h.inner
                f[k] = vtx(x, y, bottom, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0)
                cf[k] = cvtx(x, y, bottom)
            end
            for k = 1, 6 do
                face(idx, pos, f[0], f[k], f[k + 1], 0.0, 0.0, 1.0)
                face(cidx, cpos, cf[0], cf[k], cf[k + 1], 0.0, 0.0, 1.0)
            end
            if tex then
                local top = -1
                for _, m in ipairs(data.sections) do top = math.max(top, m.id or 0) end
                data.sections[#data.sections + 1] = { id = top + 1, layer = "opaque", texture = tex, nverts = #pos // 3,
                    ntris = #idx // 3, pos = pos, uv = uv, col = col, nrm = nrm, idx = idx }
            end
            data.collision[#data.collision + 1] = { source = "deep pipe", ntris = #cidx // 3, pos = cpos, idx = cidx }
            o.trigger = foot - h.trigger
            log("scene %s: the pipe at (%.0f, %.0f) made deep, to %.0f (%d triangles cut, texture %s)", name, px, py,
                bottom, cut, tostring(tex))
        end
    end
end

function G.load_scene(name, keep_player)'''

rep('''function G.load_scene(name, keep_player)''', NEW)
rep('''    pcall(deepen, name, data)''', '''    pcall(deepen, name, data)
    do
        local okp, errp = pcall(deepen_pipes, name, data)
        if not okp then log("deep pipe failed: %s", tostring(errp)) end
    end''')
rep('''        r = o.radius or ((o.kind == "pipe") and 60.0 or 70.0), t = 0.0 }''',
    '''        r = o.radius or ((o.kind == "pipe") and 60.0 or 70.0), t = 0.0, tz = o.trigger }''')
rep('''        elseif w.kind == "pipe" then inside = d < w.r and z > w.z - 40.0 and z < w.z + 110.0''',
    '''        elseif w.kind == "pipe" then inside = d < w.r and z > (w.tz or w.z) - 40.0 and z < (w.tz or w.z) + 110.0''')
rep('''        x, y, z = pipe.x, pipe.y, pipe.z
        fz = pipe.z + 10.0''', '''        x, y, z = pipe.x, pipe.y, pipe.z
        fz = pipe.tz and (pipe.z - PIT_START) or (pipe.z + 10.0)''')
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('ok')
