-- SM64Map: Mario 64's rooms (surface rooms in Big Boo's Haunt, the castle's three floors and Hazy Maze Cave).
--
-- Mario 64 gives each floor triangle there a room number, Mario's room is the floor's under him (gMarioCurrentRoom), and
-- each Boo, Mr. I and the rest takes the room of the floor under where it starts (bhv_init_room): a Boo wakes only with
-- Mario in its room (boo_should_be_active), and the others stop and go from sight while he is in another
-- (cur_obj_enable_rendering_if_mario_in_room). Without them the balcony's Big Boo, 2500 units of reach, came down through
-- the ceiling after him in the hall below ("adding upgrading and improving", 2026-10-18). Floors from data/rooms.lua
-- (tools/roomx.py), looked up through a grid of 400 cm squares.
local lib = require("lib")

local M = {}

local OFFSET = lib.OFFSET
local CELL = 400.0

local scene = nil           -- name the grid was built for
local grid = nil            -- "ix:iy" -> list of triangle starts in `tris`
local tris = nil
local data = nil

M.mario = 0                 -- his room now (0: none known, as Mario 64's)
local acc = 0.0
local last_scene = nil
local adj = {}              -- room -> { room = true }: the rooms either side of each door (gDoorAdjacentRooms)
local adj_scene = nil

local function key(ix, iy) return ix * 100000 + iy end

local function build(name)
    scene, grid, tris = name, nil, nil
    if data == nil then data = lib.load_data("data.rooms") or false end
    local t = data and data[name]
    if not t then return end
    grid, tris = {}, t
    for i = 1, #t, 10 do
        local x0 = math.min(t[i], t[i + 3], t[i + 6])
        local x1 = math.max(t[i], t[i + 3], t[i + 6])
        local y0 = math.min(t[i + 1], t[i + 4], t[i + 7])
        local y1 = math.max(t[i + 1], t[i + 4], t[i + 7])
        for ix = math.floor(x0 / CELL), math.floor(x1 / CELL) do
            for iy = math.floor(y0 / CELL), math.floor(y1 / CELL) do
                local k = key(ix, iy)
                local l = grid[k]
                if not l then l = {}; grid[k] = l end
                l[#l + 1] = i
            end
        end
    end
end

-- the room of the highest floor under (x, y) at or below z + 50 (scene cm); nil where the scene has no rooms, 0 where no
-- floor is found
function M.at(name, x, y, z)
    if name ~= scene then build(name) end
    if not grid then return nil end
    local l = grid[key(math.floor(x / CELL), math.floor(y / CELL))]
    if not l then return 0 end
    local best, bz = 0, nil
    local t = tris
    for _, i in ipairs(l) do
        local ax, ay, az = t[i], t[i + 1], t[i + 2]
        local bx, by, bz2 = t[i + 3], t[i + 4], t[i + 5]
        local cx, cy, cz = t[i + 6], t[i + 7], t[i + 8]
        -- (inside the triangle seen from above: the same side of all three edges)
        local d1 = (bx - ax) * (y - ay) - (by - ay) * (x - ax)
        local d2 = (cx - bx) * (y - by) - (cy - by) * (x - bx)
        local d3 = (ax - cx) * (y - cy) - (ay - cy) * (x - cx)
        if (d1 >= 0 and d2 >= 0 and d3 >= 0) or (d1 <= 0 and d2 <= 0 and d3 <= 0) then
            -- (its height there, from the plane through the three)
            local ux, uy, uz = bx - ax, by - ay, bz2 - az
            local vx, vy, vz = cx - ax, cy - ay, cz - az
            local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            if math.abs(nz) > 1e-6 then
                local h = az - (nx * (x - ax) + ny * (y - ay)) / nz
                if h <= z + 50.0 and (not bz or h > bz) then best, bz = t[i + 9], h end
            end
        end
    end
    return best
end

-- does this scene have rooms?
function M.has(name)
    if name ~= scene then build(name) end
    return grid ~= nil
end

-- an object of `room` in Mario's room, or through a door from it (cur_obj_enable_rendering_if_mario_in_room)? True
-- where the scene has none, or his room or its is not known
function M.with_mario(room)
    if not room or room == 0 or (M.mario or 0) == 0 then return true end
    return room == M.mario or (adj[M.mario] and adj[M.mario][room]) or false
end
-- in his very room (boo_should_be_active: no doors)
function M.same(room)
    if not room or room == 0 or (M.mario or 0) == 0 then return true end
    return room == M.mario
end

-- the rooms each side of the scene's doors, as bhv_door_init gives them (gDoorAdjacentRooms): the door's own room - the
-- floor under it, a doorway's room of its own in Hazy Maze Cave - sees the rooms 200 units in front of it and behind it,
-- and nothing more (here every door's, not only the last one a room was given). Linked every way round each door - its
-- sides as well, through the walls and down the pits into the lake - every room in Hazy Maze Cave saw Dorrie's lake, and
-- she swam in sight at the foot of the boulder room's pit: "the holes in this level are seethrough, I can see dory from
-- the boulder hole", 2026-10-25.
local function door_rooms(G)
    adj, adj_scene = {}, G.name
    local n = 0
    for _, d in ipairs(G.doors or {}) do
        local a = math.rad(d.yaw or 0.0)
        local own = M.at(G.name, d.x, d.y, d.z + 50.0)
        if own and own ~= 0 then
            for _, sgn in ipairs({ 1.0, -1.0 }) do
                local r = M.at(G.name, d.x + math.cos(a) * 150.0 * sgn, d.y + math.sin(a) * 150.0 * sgn, d.z + 50.0)
                if r and r ~= 0 and r ~= own then
                    adj[own] = adj[own] or {}
                    if not adj[own][r] then adj[own][r] = true; n = n + 1 end
                end
            end
        end
    end
    lib.log("rooms: %s, %d door links", tostring(G.name), n)
end

-- ------------------------------------------------------------ the level's model, room by room
-- (the area's GEO_SWITCH_CASE(n, geo_switch_area): Mario 64 draws only his room's model - the room's own and as much of
-- its neighbours as is seen from it. All drawn at once, the holes in Hazy Maze Cave's floors showed the rooms under them
-- where Mario 64 has black: "theres a bunch of holes through the map that show the lower part of the map instead of
-- being blackend out like the ball pit", 2026-10-19. data/room_tris_<scene>.lua - exporter/roomgeo.py - gives the rooms
-- each triangle is drawn in, by its middle; the scene's sections are split by them as it loads, and only his room's are
-- shown. A triangle not found there is always drawn.)
local split = { scene = nil, secs = nil, shown = nil, water = nil, wlist = nil }
M.split_info = split

local function piece(sec, tl, id)
    local n = sec.nverts or (#sec.pos // 3)
    local w = {}
    for k, v in pairs(sec) do w[k] = v end
    local arrays = {}
    for k, v in pairs(sec) do
        if type(v) == "table" and k ~= "idx" and n > 0 and #v % n == 0 and #v // n >= 1 and #v // n <= 4 then
            arrays[k] = #v // n
            w[k] = {}
        end
    end
    local map, nv, idx, src = {}, 0, {}, sec.idx
    for _, t in ipairs(tl) do
        for j = 0, 2 do
            local o = src[t + j]
            local v = map[o]
            if not v then
                v = nv
                map[o] = v
                nv = nv + 1
                for k, st in pairs(arrays) do
                    local from, to = sec[k], w[k]
                    for c = 1, st do to[v * st + c] = from[o * st + c] end
                end
            end
            idx[#idx + 1] = v
        end
    end
    w.idx, w.nverts, w.ntris, w.id = idx, nv, #tl, id
    return w
end

function M.split_sections(name, data)
    split.scene, split.secs, split.shown, split.water, split.wlist = nil, nil, nil, nil, nil
    if data and data.room_secs then
        split.scene, split.secs, split.water = name, data.room_secs, data.room_water
        return #data.room_secs
    end
    if not data or not data.sections or not package.searchpath("data.room_tris_" .. name, package.path) then return 0 end
    local rt = lib.load_data("data.room_tris_" .. name)
    if not (rt and rt.tris) then return 0 end
    local T, fmt = rt.tris, string.format
    local nid = 0
    for _, sec in ipairs(data.sections) do if (sec.id or 0) >= nid then nid = (sec.id or 0) + 1 end end
    local out, secs, missed, total = {}, {}, 0, 0
    for _, sec in ipairs(data.sections) do
        local P, src = sec.pos, sec.idx
        local groups, order = {}, {}
        for t = 1, #src, 3 do
            local a, b, c = src[t] * 3, src[t + 1] * 3, src[t + 2] * 3
            local cx = (P[a + 1] + P[b + 1] + P[c + 1]) / 3.0
            local cy = (P[a + 2] + P[b + 2] + P[c + 2]) / 3.0
            local cz = (P[a + 3] + P[b + 3] + P[c + 3]) / 3.0
            local key = fmt("%.1f,%.1f,%.1f", cx, cy, cz)
            local m = T[key]
            -- (a triangle game.lua moved: found where it was - G.move_pieces' data.room_alias)
            if not m and data.room_alias and data.room_alias[key] then m = T[data.room_alias[key]] end
            total = total + 1
            if not m then m = 0; missed = missed + 1 end
            local g = groups[m]
            if not g then g = {}; groups[m] = g; order[#order + 1] = m end
            g[#g + 1] = t
        end
        if #order <= 1 then
            out[#out + 1] = sec
            if order[1] and order[1] ~= 0 then secs[#secs + 1] = { id = sec.id, mask = order[1] } end
        else
            for i, m in ipairs(order) do
                local id = sec.id
                if i > 1 then id, nid = nid, nid + 1 end
                out[#out + 1] = piece(sec, groups[m], id)
                if m ~= 0 then secs[#secs + 1] = { id = id, mask = m } end
            end
        end
    end
    data.sections, data.room_secs, data.room_water = out, secs, rt.water
    split.scene, split.secs, split.water = name, secs, rt.water
    lib.log("rooms: %s's model in %d pieces by room (%d of %d triangles in none)", name, #out, missed, total)
    return #secs
end

-- (the water and mist boxes too: geo_movtex_draw_water_regions is in the branches of the rooms that show them - Hazy
-- Maze Cave's lake in 6 and the rooms over it, the toxic maze's mist in 3, 11, 13 and 14. Drawn everywhere, the lake
-- lay at the foot of the shafts in the rooms above it: "theres seethrough holes all throughout hazy maze cave",
-- 2026-10-20. Each box's own, by its place: game.lua's G.water_rot.)
local function water_list(G)
    if split.wlist or not (split.water and G.water_rot and G.data and G.data.water) then return split.wlist end
    local l = {}
    for _, w in ipairs(G.water_rot) do
        local z = w.verts and w.verts[1] and w.verts[1].Z
        for _, b in ipairs(G.data.water) do
            local m = split.water[b.id or -1]
            if m and z and math.abs((-b.z2 - b.z1) / 2.0 - w.cx) < 1.0 and math.abs((b.x1 + b.x2) / 2.0 - w.cy) < 1.0
                and math.abs(b.y - z) < 0.5 then
                l[#l + 1] = { pmc = w.pmc, mask = m }
                break
            end
        end
    end
    split.wlist = l
    return l
end

-- the pieces of the rooms in `bits` (a bit a room, 1 << (room - 1)) shown, the rest hidden - each one's switched only
-- when it changes
function M.show_mask(G, bits)
    local pmc = G.pmc
    if not (pmc and split.secs) then return end
    local addr = nil
    pcall(function() addr = pmc:GetAddress() end)
    if split.vis_for ~= addr then split.vis, split.vis_for = {}, addr end
    local vis = split.vis
    for _, s in ipairs(split.secs) do
        local on = (s.mask & bits) ~= 0
        if vis[s.id] ~= on then
            vis[s.id] = on
            pcall(function() pmc:SetMeshSectionVisible(s.id, on) end)
        end
    end
    for _, w in ipairs(water_list(G) or {}) do
        local on = (w.mask & bits) ~= 0
        pcall(function() w.pmc:SetVisibility(on, false) end)
    end
    -- (and each piece's back with it - game.lua G.add_undersides, G.under_ids: drawn always, the backs of the other rooms'
    -- walls stood about this one, "black wall here?", 2026-11-06)
    local U, ids = G.under_pmc, G.under_ids
    if U and ids then
        for _, s in ipairs(split.secs) do
            local bid = ids[s.id]
            if bid then
                local on = (s.mask & bits) ~= 0
                local k = "u" .. bid
                if vis[k] ~= on then
                    vis[k] = on
                    pcall(function() U:SetMeshSectionVisible(bid, on) end)
                end
            end
        end
    end
    split.shown = bits
end
-- his room's pieces shown, the rest hidden
local function show_room(G, room)
    M.show_mask(G, 1 << (room - 1))
end
M.show_room = show_room

-- The rooms either side of every door standing open or opening, and of the castle's star doors sliding apart: shown
-- with his own the moment it starts to open - "the second a door triggers to open, load the area behind it so the
-- player can see whats going on", 2026-11-06; the room past it stood empty through the open door till he was in it.
-- A door's rooms found once, by the floors a metre and a half either side of it (M.at), and kept on it.
local function rooms_of(G, d)
    if d.rooms == nil then
        d.rooms = false
        local a = math.rad(d.yaw or 0.0)
        local rs = {}
        for _, sgn in ipairs({ 1.0, -1.0, 0.0 }) do
            local r = M.at(G.name, d.x + math.cos(a) * 150.0 * sgn, d.y + math.sin(a) * 150.0 * sgn, d.z + 50.0)
            if r and r ~= 0 then rs[#rs + 1] = r end
        end
        if #rs > 0 then d.rooms = rs end
    end
    return d.rooms or nil
end
function M.open_door_bits(G)
    local bits = 0
    for _, d in ipairs(G.doors or {}) do
        if d.f and d.f >= 0 then
            for _, r in ipairs(rooms_of(G, d) or {}) do bits = bits | (1 << (r - 1)) end
        end
    end
    for _, s in ipairs(G.stardoors or {}) do
        if (s.open or 0.0) > 0.01 then
            for _, r in ipairs(rooms_of(G, s) or {}) do bits = bits | (1 << (r - 1)) end
        end
    end
    return bits
end

function M.tick(dt, pawn)
    local G = package.loaded["game"]
    if not (G and G.name and pawn) then return end
    if G.name ~= last_scene then last_scene, M.mario, acc = G.name, 0, 0.0 end
    if not M.has(G.name) then M.mario = 0; return end
    if adj_scene ~= G.name and G.doors and #G.doors > 0 then door_rooms(G) end
    acc = acc - dt
    if acc > 0.0 then return end
    acc = 0.1
    local l = nil
    pcall(function() l = pawn:K2_GetActorLocation() end)
    if not l then return end
    local r = M.at(G.name, l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - (G.half or 90.0))
    -- (off any floor - in the air over a gap - his room is kept, as Mario 64 keeps it till he lands somewhere)
    if r and r ~= 0 then M.mario = r end
    -- (his room, and the rooms past the doors standing open - M.open_door_bits)
    if split.secs and split.scene == G.name and M.mario > 0 then
        local okb, open = pcall(M.open_door_bits, G)
        local bits = (1 << (M.mario - 1)) | ((okb and open) or 0)
        if split.shown ~= bits then M.show_mask(G, bits) end
    end
end

function M.forget() M.mario, last_scene, adj, adj_scene, split.shown = 0, nil, {}, nil, nil end

return M
