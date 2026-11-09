-- SM64Map game logic: scenes, goombas, doors, paintings, Bowser.
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET
local PLAT = require("platforms")
-- parts the game can run without: a failure in one of them is logged and that part is left out
local function optional(name)
    local ok, m = pcall(require, name)
    if ok then return m end
    log("%s did not load: %s", name, tostring(m))
    return nil
end
local STOR, SKY, MUSIC, PAUSE = optional("storror"), optional("sky"), optional("music"), optional("pause")
local SWIM = optional("swim")
local BUTTERFLY = optional("butterfly")
local MOVTEX = optional("movtex")
local ENVFX = optional("envfx")        -- (Mario 64's falling snow: envfx.lua)
local SCENERY = optional("scenery")
local MIRROR = optional("mirror")    -- (the castle's mirror room: his reflection, and Lakitu filming)
local CAPS = optional("caps")         -- (Mario 64's wing, metal and vanish caps, out of their ! boxes)
local HOOT = optional("hoot")         -- (Whomp's Fortress's owl, who carries him about)
local POLES = optional("poles")       -- (poles: drawn, DDD's moving ones climbed Mario 64's way)
local CLIMB = optional("climb")       -- (trees and still poles climbed STORROR's way)
local CORK = optional("cork")         -- (the running cork: launched, landed, rolled out or bailed)
local PAINT = optional("painting")    -- (the paintings' ripples, the camera and him going in)
local QSAND = optional("quicksand")   -- (sand he sinks in)
local HANG = optional("hang")         -- (ceilings to hang from)
local SHELL = optional("shell")       -- (Koopa shells to surf on)
local FLIGHT = optional("flight")     -- (Wing Cap flight, out of a cannon)
local SLIDE = optional("slide")       -- (sliding down the slide courses)
local FOOTIK = optional("footik")     -- (his feet on sloped ground: STORROR's own foot IK never runs)
-- (roundoff.lua - STORROR cutting its roundoff short, undone. Off on 2026-10-17 - "the roundoffs should be completely
-- stock" - and on again 2026-10-22: the cut came back with the foot IK not under way, STORROR's own and mostly with the
-- flip button held - "roundoff is still bugged how did we fix it before?". false, not nil, if it will not load: the forget
-- list below is walked with ipairs, which stops at a nil)
local ROUNDOFF = optional("roundoff") or false
local CAMLAK = optional("camlakitu")  -- (a new file's first look at the castle: the Lakitu Bros.' cameraman on the bridge)
local FPV = optional("fp")
local BURN = optional("burn")      -- (set alight by Bowser's flames: a hop, then a run he cannot stop)
local RAG = optional("ragdoll")    -- (knocked flat when Bowser comes down on him; up when the player asks)
local UNDERWATER = optional("underwater")
local TRANS = optional("transition")
optional("shadows")                      -- (Mario 64's round shadows under him and the creatures: package.loaded)
optional("mariocap")                     -- (Mario's own cap, and losing it: package.loaded)
optional("dust")                         -- (Mario 64's dust at his feet: package.loaded)
optional("race")                         -- (the ghost race's checkpoint beacons: package.loaded)
optional("secrets")                      -- (Final Bowser's secret unlocks, for every file: package.loaded)
optional("chat")                         -- (a multiplayer game's chat, Enter: package.loaded - mp.lua ticks it)
optional("footsteps")                    -- (his footsteps loud enough to hear: package.loaded)
optional("rooms")                        -- (Mario 64's rooms: which one he is in - package.loaded)
optional("fog")                          -- (Mario 64's fog in the scenes that have it - package.loaded)
optional("lamps")                        -- (lamps in the castle's rooms with real-time shadows - package.loaded)
local STARSEL = optional("starselect")  -- (Mario 64's star select, between a painting and its course)
local DIALOG = optional("dialog")       -- (Mario 64's dialog box: signs, Toads, switches)   -- (Mario 64's screen transitions: Bowser's head for a death, the circle, the star)
-- Creatures in modules of their own: each has `kinds` (the scene object kinds it takes), setup(helpers, platforms),
-- add(world, object, templates), clear(), forget() and update(dt, x, y, z) (the athlete's middle, in the world).
local CREATURES = {}
for _, name in ipairs({ "chomp", "bobomb", "enemies", "boxes", "loops" }) do
    local m = optional(name)
    if m then CREATURES[#CREATURES + 1] = m end
end
-- each scene's ambience under its music (music.lua M.ambience; <mod>/ambience/<name>.m4a, rendered from the ROM)
local AMBIENCE = { grounds = "castle_grounds" }
-- (outside places with an ambience only with REMIX MUSIC on - the courtyard: music.lua AMB_REMIX_DIR, 2026-11-01. Kept
-- in AMBIENCE, not locals of their own: this file is at Lua's 200)
AMBIENCE._remix = { courtyard = "castle_grounds" }
function AMBIENCE._for(name)
    if AMBIENCE[name] then return AMBIENCE[name] end
    if MUSIC and MUSIC.remix and AMBIENCE._remix[name] then return AMBIENCE._remix[name] end
    return nil
end
-- (REMIX MUSIC turned: the ambience as it now is for the scene he is in - music.lua M.set_remix)
if MUSIC then
    MUSIC.amb_again = function()
        local GG = package.loaded["game"]
        if GG and GG.name then pcall(MUSIC.ambience, AMBIENCE._for(GG.name)) end
    end
end

local G = {
    name = nil, data = nil, scene_actor = nil, pmc = nil,
    goombas = {}, doors = {}, paintings = {}, bowser = nil, fireballs = {}, extras = {}, trees = {},
    floor = nil, pending = nil, actors = {}, last_t = os.clock(), warp_cool = 0.0,
}

-- (Mario 64's course-complete screen, back in the castle after a star: on G, the main chunk is at its 200 locals)
G.CM = optional("complete")

local SCENES = { "grounds", "castle", "bob", "bowser" }
G.SCENES = SCENES

-- Where every door, painting, pipe and exit leads comes from Mario 64's own level scripts, written into
-- each scene by the exporter: `warps` (warp node -> scene and the node to arrive at there), `pwarps`
-- (the same for the paintings), `nodes` (the places a player can arrive at) and `instant` (areas that
-- carry straight on from one another). They are indexed here when a scene loads.
G.warp, G.pwarp, G.node, G.instant = {}, {}, {}, {}

-- ------------------------------------------------------------ math helpers
local sqrt, cos, sin, atan, rad, deg, floor, abs = math.sqrt, math.cos, math.sin, math.atan, math.rad, math.deg, math.floor, math.abs
G.GOOMBA_SIZE = 1.4      -- goombas are built this much bigger than Mario 64's
G.GOOMBA_DROP = 37.5     -- cm: the most a goomba steps down (Mario 64's careful walkers: 50 units)
G.GOOMBA_REACH, G.GOOMBA_REACH_UP = 40.0, 80.0     -- cm its stomp box reaches past its body at most (G.goomba_contact)

-- ------------------------------------------------------------ floor lookup (own collision data)
local CELL = 400.0
local function cell_key(i, j) return i * 65536 + j end

local function build_floor(collision, off, steep)
    local grid, tris = {}, {}
    local minz = math.huge
    for _, c in ipairs(collision) do
        -- (a piece solid only, `no_floor` - the castle's stair ramps, G.stair_ramps - is no floor read here: his feet
        -- and the fall heights go by the steps under it)
        local p, ix = c.pos, c.idx
        for t = 0, (c.no_floor and 0 or c.ntris) - 1 do
            local a, b, d = ix[t * 3 + 1] * 3, ix[t * 3 + 2] * 3, ix[t * 3 + 3] * 3
            local ax, ay, az = p[a + 1], p[a + 2], p[a + 3]
            local bx, by, bz = p[b + 1], p[b + 2], p[b + 3]
            local cx, cy, cz = p[d + 1], p[d + 2], p[d + 3]
            local ux, uy, uz = bx - ax, by - ay, bz - az
            local vx, vy, vz = cx - ax, cy - ay, cz - az
            local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            local len = sqrt(nx * nx + ny * ny + nz * nz)
            if len > 1e-6 and abs(nz) / len > (steep or 0.45) then
                local T = { ax, ay, az, bx, by, bz, cx, cy, cz, nz, c.tag }
                tris[#tris + 1] = T
                local lo = math.min(az, bz, cz)
                if lo < minz then minz = lo end
                local minx, maxx = math.min(ax, bx, cx), math.max(ax, bx, cx)
                local miny, maxy = math.min(ay, by, cy), math.max(ay, by, cy)
                for i = floor(minx / CELL), floor(maxx / CELL) do
                    for j = floor(miny / CELL), floor(maxy / CELL) do
                        local k = cell_key(i, j)
                        local g = grid[k]
                        if not g then g = {}; grid[k] = g end
                        g[#g + 1] = T
                    end
                end
            end
        end
    end
    return { grid = grid, n = #tris, min_z = (minz < math.huge) and minz or nil }
end

-- The level's walls (its collision's steep triangles), each taken as standing upright: its line across the ground
-- between its two farthest corners, from its lowest point to its highest. Built when first asked for - again for each
-- scene loaded, the same one again too (by its data: its pieces moved since, SL's igloo's ice wall lowered). And its
-- vanish-cap walls with them: Mario 64's stop every object but a Boo (find_wall_collisions, surface_collision.c -
-- ACTIVE_FLAG_MOVE_THROUGH_GRATE, boo.inc.c's alone) - its enemies walked through SL's igloo's ice walls, "enemies
-- going through ice walls", 2026-10-26.
local function build_walls(collision)
    local grid = {}
    local list = {}
    for _, c in ipairs(collision or {}) do list[#list + 1] = c end
    if G.data and G.data.vanish_walls and G.data.vanish_walls.ntris then list[#list + 1] = G.data.vanish_walls end
    for _, c in ipairs(list) do
        local p, ix = c.pos, c.idx
        for t = 0, c.ntris - 1 do
            local a, b, d = ix[t * 3 + 1] * 3, ix[t * 3 + 2] * 3, ix[t * 3 + 3] * 3
            local v = { { p[a + 1], p[a + 2], p[a + 3] }, { p[b + 1], p[b + 2], p[b + 3] }, { p[d + 1], p[d + 2], p[d + 3] } }
            local ux, uy, uz = v[2][1] - v[1][1], v[2][2] - v[1][2], v[2][3] - v[1][3]
            local wx, wy, wz = v[3][1] - v[1][1], v[3][2] - v[1][2], v[3][3] - v[1][3]
            local nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
            local len = sqrt(nx * nx + ny * ny + nz * nz)
            if len > 1e-6 and abs(nz) / len < 0.45 then
                local best, e1, e2 = -1, 1, 2
                for _, pr in ipairs({ { 1, 2 }, { 2, 3 }, { 1, 3 } }) do
                    local q1, q2 = v[pr[1]], v[pr[2]]
                    local dd = (q1[1] - q2[1]) ^ 2 + (q1[2] - q2[2]) ^ 2
                    if dd > best then best, e1, e2 = dd, pr[1], pr[2] end
                end
                local W = { v[e1][1], v[e1][2], v[e2][1], v[e2][2],
                            math.min(v[1][3], v[2][3], v[3][3]), math.max(v[1][3], v[2][3], v[3][3]), v = v }
                for i = floor(math.min(W[1], W[3]) / CELL), floor(math.max(W[1], W[3]) / CELL) do
                    for j = floor(math.min(W[2], W[4]) / CELL), floor(math.max(W[2], W[4]) / CELL) do
                        local k = cell_key(i, j)
                        local g = grid[k]
                        if not g then g = {}; grid[k] = g end
                        g[#g + 1] = W
                    end
                end
            end
        end
    end
    return grid
end

-- Where a wall triangle is at height z: the line it cuts across that height (x1, y1, x2, y2), and how far z is over
-- or under it. A sloping one leans - standing it upright on its widest line put WF's slanted cliffs out in the open
-- air, and a cannon shot bonked off nothing ("I keep hitting this wall when launching from the cannon even though its
-- not close", 2026-10-17).
-- (a G field: the chunk's locals are full)
function G.wall_at(W, z)
    local v = W.v
    if not v then return W[1], W[2], W[3], W[4], 0.0 end
    local zc = math.max(W[5], math.min(W[6], z))
    local px, py, n = {}, {}, 0
    for _, e in ipairs({ { 1, 2 }, { 2, 3 }, { 3, 1 } }) do
        local a, b = v[e[1]], v[e[2]]
        if a[3] == zc and b[3] == zc then return a[1], a[2], b[1], b[2], z - zc end
        if a[3] ~= b[3] and (a[3] - zc) * (b[3] - zc) <= 0 then
            local t = (zc - a[3]) / (b[3] - a[3])
            n = n + 1
            px[n], py[n] = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
        end
    end
    if n < 2 then return W[1], W[2], W[3], W[4], z - zc end
    return px[1], py[1], px[2], py[2], z - zc
end

-- Is there a wall within `r` of the point (scene cm)? If so, also how far it pushes the point out (x, y): Mario
-- 64's obj_find_wall_displacement, near enough. `vr`, when given: Mario 64's own test - only a wall that spans the
-- point's height, within vr, counts, and only how far off it is across the ground (find_wall_collisions; the racing
-- penguin, his wall round him 300 wide, stood stuck behind the 58-unit step at the top of his slide, 2026-10-18).
local function wall_near(x, y, z, r, vr)
    if G.walls_for ~= G.data then
        G.walls_for, G.walls = G.data, build_walls(G.data and G.data.collision)
    end
    local grid = G.walls
    if not grid then return false end
    local hit, px, py = false, 0.0, 0.0
    for i = floor((x - r) / CELL), floor((x + r) / CELL) do
        for j = floor((y - r) / CELL), floor((y + r) / CELL) do
            for _, W in ipairs(grid[cell_key(i, j)] or {}) do
                if z >= W[5] - (vr or r) and z <= W[6] + (vr or r) then
                    local x1, y1, x2, y2, dz = G.wall_at(W, z)
                    local dx, dy = x2 - x1, y2 - y1
                    local L = dx * dx + dy * dy
                    local t = L > 0 and math.max(0.0, math.min(1.0, ((x - x1) * dx + (y - y1) * dy) / L)) or 0.0
                    local ox, oy = x - (x1 + dx * t), y - (y1 + dy * t)
                    local dist = sqrt(ox * ox + oy * oy)
                    if (vr and abs(dz) <= vr and dist < r) or (not vr and sqrt(dist * dist + dz * dz) < r) then
                        hit = true
                        if dist > 1e-3 then px, py = px + ox / dist * (r - dist), py + oy / dist * (r - dist) end
                    end
                end
            end
        end
    end
    return hit, px, py
end
G.wall_near = wall_near

-- The walls under water push him off them, as a jet stream does ("everywall underwater needs a vortex to push the player
-- away from the wall", 2026-10-24): how hard, 0..1 for each wall within `r` of the point (scene cm) that spans its height
-- within `vr` - 1 against it, nothing at `r` - and which way, straight out from it, all of them added (x, y); nil if none.
-- A flat wall counts once: only the triangle the point stands square in front of (the same foot met again - a wall of
-- stacked triangles, a doubled one - counts once). Off a corner, in front of none, its nearest point. A wall whose top
-- is between `lo` and `hi` (when given) is left out.
function G.wall_push(x, y, z, r, vr, lo, hi)
    if G.walls_for ~= G.data then
        G.walls_for, G.walls = G.data, build_walls(G.data and G.data.collision)
    end
    local grid = G.walls
    if not grid then return nil end
    -- (none off the scene's pillars solid as drawn, G.SOLID_AS_DRAWN's `nopush`)
    local NP = G.SOLID_AS_DRAWN and G.SOLID_AS_DRAWN[G.name or ""]
    if NP and not NP.nopush then NP = nil end
    local feet, nd, nx, ny = {}, r, nil, nil
    for i = floor((x - r) / CELL), floor((x + r) / CELL) do
        for j = floor((y - r) / CELL), floor((y + r) / CELL) do
            for _, W in ipairs(grid[cell_key(i, j)] or {}) do
                if z >= W[5] - vr and z <= W[6] + vr and not (lo and W[6] >= lo and W[6] <= hi) then
                    local x1, y1, x2, y2, dz = G.wall_at(W, z)
                    local dx, dy = x2 - x1, y2 - y1
                    local L = dx * dx + dy * dy
                    if abs(dz) <= vr and L > 1.0 then
                        local t = ((x - x1) * dx + (y - y1) * dy) / L
                        local tc = math.max(0.0, math.min(1.0, t))
                        local fx, fy = x1 + dx * tc, y1 + dy * tc
                        local d = sqrt((x - fx) ^ 2 + (y - fy) ^ 2)
                        local pillar = false
                        if NP then
                            for _, c in ipairs(NP) do
                                if (fx - c[1]) ^ 2 + (fy - c[2]) ^ 2 < c[3] * c[3] then pillar = true; break end
                            end
                        end
                        if d < r and d > 1e-3 and not pillar then
                            if t > 0.0 and t < 1.0 then
                                local seen = false
                                for _, f in ipairs(feet) do
                                    if abs(f[1] - fx) < 3.0 and abs(f[2] - fy) < 3.0 then seen = true; break end
                                end
                                if not seen then feet[#feet + 1] = { fx, fy, d } end
                            elseif d < nd then
                                nd, nx, ny = d, fx, fy
                            end
                        end
                    end
                end
            end
        end
    end
    if #feet == 0 and nx then feet[1] = { nx, ny, nd } end
    if #feet == 0 then return nil end
    local px, py = 0.0, 0.0
    for _, f in ipairs(feet) do
        local k = (1.0 - f[3] / r) / f[3]
        px, py = px + (x - f[1]) * k, py + (y - f[2]) * k
    end
    return px, py
end
G.WALL_PUSH = 2700.0            -- cm/s, against the wall: four times his fastest stroke, 630 ("make the push way stonger" than 900, 2026-10-24)
G.WALL_PUSH_R = 200.0           -- cm out from it, where it is gone

-- How far along the line from (ax, ay, az) to (bx, by, bz) - scene cm - the first wall stands across it, 0..1 (1: none).
local function wall_cut(ax, ay, az, bx, by, bz)
    if G.walls_for ~= G.data then
        G.walls_for, G.walls = G.data, build_walls(G.data and G.data.collision)
    end
    local grid = G.walls
    if not grid then return 1.0 end
    local best = 1.0
    local dx, dy = bx - ax, by - ay
    local seen = {}
    for i = floor(math.min(ax, bx) / CELL), floor(math.max(ax, bx) / CELL) do
        for j = floor(math.min(ay, by) / CELL), floor(math.max(ay, by) / CELL) do
            for _, W in ipairs(grid[cell_key(i, j)] or {}) do
                if not seen[W] then
                    seen[W] = true
                    local ex, ey = W[3] - W[1], W[4] - W[2]
                    local den = dx * ey - dy * ex
                    if abs(den) > 1e-6 then
                        local t = ((W[1] - ax) * ey - (W[2] - ay) * ex) / den
                        local u = ((W[1] - ax) * dy - (W[2] - ay) * dx) / den
                        if t >= 0.0 and t < best and u >= 0.0 and u <= 1.0 then
                            local z = az + (bz - az) * t
                            if z >= W[5] and z <= W[6] then best = t end
                        end
                    end
                end
            end
        end
    end
    return best
end
G.wall_cut = wall_cut

-- highest floor of `F` at (x,y) that is <= zmax, and the triangle it belongs to; coordinates in scene space
local function floor_hit(F, x, y, zmax)
    if not F then return nil end
    local g = F.grid[cell_key(floor(x / CELL), floor(y / CELL))]
    if not g then return nil end
    local best, hit = nil, nil
    for _, T in ipairs(g) do
        local ax, ay, az, bx, by, bz, cx, cy, cz, nz = T[1], T[2], T[3], T[4], T[5], T[6], T[7], T[8], T[9], T[10]
        local d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(d) > 1e-9 then
            local l1 = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / d
            local l2 = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / d
            local l3 = 1 - l1 - l2
            if l1 >= -0.001 and l2 >= -0.001 and l3 >= -0.001 then
                local z = l1 * az + l2 * bz + l3 * cz
                if z <= zmax and (not best or z > best) then best, hit = z, T end
            end
        end
    end
    return best, hit
end
local function floor_z(x, y, zmax) return (floor_hit(G.floor, x, y, zmax)) end

-- the floor under (x, y) at or below zmax with its normal, facing up (scene axes): z, nx, ny, nz - or nil. `steep`: and
-- the slopes too steep to stand on (G.bounds: every face but the upright walls) - the slides' banked turns
function G.floor_normal(x, y, zmax, steep)
    local z, T = floor_hit((steep and G.bounds) or G.floor, x, y, zmax)
    if not T then return nil end
    local ux, uy, uz = T[4] - T[1], T[5] - T[2], T[6] - T[3]
    local vx, vy, vz = T[7] - T[1], T[8] - T[2], T[9] - T[3]
    local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    local l = sqrt(nx * nx + ny * ny + nz * nz)
    if l < 1e-9 then return z, 0.0, 0.0, 1.0 end
    if nz < 0.0 then nx, ny, nz = -nx, -ny, -nz end
    return z, nx / l, ny / l, nz / l
end

-- the same for a ceiling: the lowest of F's triangles over (x, y) at or above zmin (the ceilings he can hang from)
local function ceil_hit(F, x, y, zmin)
    if not F then return nil end
    local g = F.grid[cell_key(floor(x / CELL), floor(y / CELL))]
    if not g then return nil end
    local best = nil
    for _, T in ipairs(g) do
        local ax, ay, az, bx, by, bz, cx, cy, cz = T[1], T[2], T[3], T[4], T[5], T[6], T[7], T[8], T[9]
        local d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(d) > 1e-9 then
            local l1 = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / d
            local l2 = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / d
            local l3 = 1 - l1 - l2
            if l1 >= -0.001 and l2 >= -0.001 and l3 >= -0.001 then
                local z = l1 * az + l2 * bz + l3 * cz
                if z >= zmin and (not best or z < best) then best = z end
            end
        end
    end
    return best
end
G.hang = nil
function G.hang_ceiling(x, y, zmin) return ceil_hit(G.hang, x, y, zmin) end
G.floor_z = floor_z
-- (the level's lowest ceiling over (x, y) at or above zmin, scene cm: G.floor holds every flat-ish triangle, facing up
-- or down - a Thwomp rising under a ceiling squeezes him into it, platforms.lua)
function G.ceil_z(x, y, zmin) return ceil_hit(G.floor, x, y, zmin) end
PLAT.setup({ build_floor = build_floor, floor_hit = floor_hit, floor_z = floor_z, ceil_z = G.ceil_z, wall_near = wall_near })
G.PLAT = PLAT

-- ------------------------------------------------------------ actor data cache
-- (models Mario 64 turns to the camera in their objects' behaviour scripts - BILLBOARD() - rather than in the model
-- itself: the exporter leaves them flat, so they are marked here. The rolling iron balls showed edge-on, as thin
-- dark discs - "next we gotta fix the rolling boulders", 2026-10-16 - and Mr. I's body the same.)
local BEHAVIOUR_BILLBOARDS = { geo_bowling_ball_geo = true, geo_mr_i_geo = true,
                                geo_pokey_head_geo = true, geo_pokey_body_part_geo = true,      -- (bhvPokeyBodyPart: BILLBOARD)
                                geo_fwoosh_geo = true }                                         -- (bhvCloud: BILLBOARD)
-- The Boo's model, for both ways it is drawn (enemies.lua M.boo_look): solid as exported, and see-through while it
-- fades - every section twice, a solid one and a see-through one, each keeping its material for good; the look is
-- changed by showing one set and hiding the other. (Materials swapped in and out were held by nothing in the engine
-- while not in use: its garbage collection freed them and the next swap brought the game down - "crash", twice,
-- 2026-10-22.) Its body is an open shell facing forward, which Mario 64 draws from both sides: the solid material does
-- that, the see-through one draws one side only, so the see-through body has a copy wound the other way round too (one
-- side alone, a fading Boo was hollow from behind, "the opposite side of the ghosts face is invisable"). Its mouth and
-- eyes are a part of their own (a second component, on the body), drawn after the body when see-through (in the one
-- component the engine drew the sections in any order and the body hid the face, "they're missing they're face").
function G.boo_body_first(data)
    local p = data.parts and data.parts[1]
    if not p or data.boo_split then return end
    local body, face = nil, {}
    for _, sec in ipairs(p.sections or {}) do
        if sec.texture then face[#face + 1] = sec else body = body or sec end
    end
    if not body or #face == 0 then return end
    local function copy(sec, role, flip)
        local c = {}
        for k, v in pairs(sec) do c[k] = v end
        if flip then
            local idx = {}
            for t = 0, #sec.idx // 3 - 1 do
                idx[t * 3 + 1], idx[t * 3 + 2], idx[t * 3 + 3] = sec.idx[t * 3 + 1], sec.idx[t * 3 + 3], sec.idx[t * 3 + 2]
            end
            c.idx = idx
        end
        c.boo_role = role
        return c
    end
    local bodies = { copy(body, "solid"), copy(body, "see_through"), copy(body, "see_through", true) }
    local faces = {}
    for _, sec in ipairs(face) do faces[#faces + 1] = copy(sec, "solid") end
    -- (see-through, the face is first its white: Mario 64 draws the eyes and mouth over the body's white (G_CC_DECALFADE),
    -- where the pictures' own clear parts cut holes in it - its middle was a hollow showing the inside of its back,
    -- "you didnt fix the face still????", 2026-10-22. These come first, so the eyes and mouth are drawn over them.)
    for _, flip in ipairs({ false, true }) do
        for _, sec in ipairs(face) do
            faces[#faces + 1] = copy(sec, "see_through", flip)
            faces[#faces].boo_base = true
        end
    end
    for _, sec in ipairs(face) do faces[#faces + 1] = copy(sec, "see_through") end
    -- (and its face the other way round too, seen from behind through its open back as Mario 64 draws it: "when looking
    -- at the lobby ghost from behind his face is invisible", 2026-10-22)
    for _, sec in ipairs(face) do faces[#faces + 1] = copy(sec, "see_through", true) end
    for k, sec in ipairs(bodies) do sec.id = k - 1 end
    for k, sec in ipairs(faces) do sec.id = k - 1 end
    p.sections = bodies
    data.parts[#data.parts + 1] = { name = "face", parent = 0, off = { 0, 0, 0 }, billboard = p.billboard, sections = faces }
    data.boo_split = true
end
local function actor_data(name)
    if G.actors[name] == nil then
        G.actors[name] = lib.load_data("data.actor_" .. name) or false
        -- (the castle's Boo too: its own model, the same three sections - its face was still missing, "it was in the
        -- hall", 2026-10-22)
        if G.actors[name] and (name == "geo_boo_geo" or name == "geo_boo_castle_geo") then G.boo_body_first(G.actors[name]) end
        if G.actors[name] and BEHAVIOUR_BILLBOARDS[name] then
            for _, p in ipairs(G.actors[name].parts or {}) do p.billboard = true end
        end
        -- (a Koopa's neck yellow: Mario 64 lights the top of his shell's rim, round his neck, white - only a small
        -- patch in front is yellow - and from behind it read as a white neck: "his neck is still white", 2026-10-16)
        if G.actors[name] and name == "geo_koopa_with_shell_geo" then
            local p = (G.actors[name].parts or {})[2]
            for _, sec in ipairs(p and p.sections or {}) do
                if not sec.texture then
                    for i = 0, #sec.pos // 3 - 1 do
                        local r, b = sec.col[i * 4 + 1], sec.col[i * 4 + 3]
                        if sec.pos[i * 3 + 2] >= 15.0 and b > 0.3 then
                            local k = math.max(0.6, r)
                            sec.col[i * 4 + 1], sec.col[i * 4 + 2], sec.col[i * 4 + 3] = 0.88 * k, 0.68 * k, 0.0
                        end
                    end
                end
            end
        end
        -- (the Skeeter's round body and nose: Mario 64's one white-ball picture times their vertex colour - teal, orange
        -- (G_CC_MODULATERGBA); the materials take no vertex colour, and they were plain white: "skeeters missing texture",
        -- 2026-10-28. Each its tinted picture, made once beside it - tint_skeeter.py. The eyes are the picture alone.)
        if G.actors[name] and name == "geo_skeeter_geo" then
            for _, p in ipairs(G.actors[name].parts or {}) do
                for _, sec in ipairs(p.sections or {}) do
                    if sec.texture == "actors__skeeter__skeeter_eye.rgba16" and sec.col and sec.col[1] then
                        local r, g = sec.col[1], sec.col[2]
                        if r < 0.1 and g > 0.9 then sec.texture = "actors__skeeter__skeeter_eye_body.rgba16"
                        elseif r > 0.9 and g < 0.5 then sec.texture = "actors__skeeter__skeeter_eye_nose.rgba16" end
                    end
                end
            end
        end
        -- (the Wing Cap's feathered wings: the masked material drew them black; the blend one shows them white)
        if G.actors[name] and name == "cap_wing" then
            for _, p in ipairs(G.actors[name].parts or {}) do
                for _, sec in ipairs(p.sections or {}) do
                    if sec.texture and sec.texture:find("wing") and not sec.both then
                        sec.layer = "translucent"
                        -- (and seen from both sides, as Mario 64 draws them - G_CULL_BACK cleared for the wings: from
                        -- behind they were not there, "the back of the wing caps wings are invisable", 2026-10-17). Each
                        -- triangle a reversed twin a hair behind it, facing the other way.
                        sec.both = true
                        local n = sec.nverts
                        local pos, nrm, uv, col, idx = sec.pos, sec.nrm, sec.uv, sec.col, sec.idx
                        for i = 0, n - 1 do
                            local nx, ny, nz = nrm[i * 3 + 1] or 0.0, nrm[i * 3 + 2] or 0.0, nrm[i * 3 + 3] or 1.0
                            pos[#pos + 1] = pos[i * 3 + 1] - nx * 0.4
                            pos[#pos + 1] = pos[i * 3 + 2] - ny * 0.4
                            pos[#pos + 1] = pos[i * 3 + 3] - nz * 0.4
                            nrm[#nrm + 1], nrm[#nrm + 2], nrm[#nrm + 3] = -nx, -ny, -nz
                            uv[#uv + 1], uv[#uv + 2] = uv[i * 2 + 1], uv[i * 2 + 2]
                            for c = 1, 4 do col[#col + 1] = col[i * 4 + c] end
                        end
                        local m = #idx
                        for t = 0, m // 3 - 1 do
                            idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = idx[t * 3 + 1] + n, idx[t * 3 + 3] + n, idx[t * 3 + 2] + n
                        end
                        sec.nverts = n * 2
                        if sec.ntris then sec.ntris = sec.ntris * 2 end
                    end
                end
            end
        end
    end
    return G.actors[name]
end
G.actor_data = actor_data
for _, m in ipairs(CREATURES) do
    if m.setup then
        pcall(m.setup, { floor_z = floor_z, actor_data = actor_data, wall_near = wall_near, floor_normal = G.floor_normal,
                         knock_down = function(...) return G.knock_down(...) end,
                         spawn_coin = function(...) return G.spawn_coin(...) end }, PLAT)
    end
end

-- ------------------------------------------------------------ scene lifecycle
local teardown

-- (while a scene is torn down everything it destroys is only retired: hidden and untouchable until he stands on the
-- next one, see lib.retire)
function G.destroy_scene()
    local destroy = lib.destroy
    lib.destroy = lib.retire
    local ok, err = pcall(teardown)
    lib.destroy = destroy
    if not ok then error(err) end
end

teardown = function()
    G.stage_shake = nil
    if BURN then pcall(BURN.stop, true) end
    if RAG and RAG.active then
        pcall(RAG.stop, true)
        G.reset_athlete(nil, "the scene went while he was down")
    elseif RAG then
        pcall(RAG.stop, true)
    end
    for _, g in ipairs(G.goombas) do lib.destroy(g.inst and g.inst.actor) end
    for _, d in ipairs(G.doors) do lib.destroy(d.inst and d.inst.actor) end
    for _, p in ipairs(G.paintings) do lib.destroy(p.actor) end
    for _, f in ipairs(G.fireballs) do lib.destroy(f.actor) end
    if package.loaded["bowser_fight"] then pcall(package.loaded["bowser_fight"].clear) end
    if G.bowser then lib.destroy(G.bowser.inst and G.bowser.inst.actor) end
    for _, bm in ipairs(G.bombs or {}) do lib.destroy(bm.inst and bm.inst.actor) end
    G.bombs = {}
    for _, a in ipairs(G.extras) do lib.destroy(a) end
    for _, t in ipairs(G.trees) do lib.destroy(t.actor) end
    G.extras, G.trees, G.sprites = {}, {}, {}
    if G.swim and G.stop_swim then G.stop_swim() end
    G.water_rects = {}
    lib.destroy(G.scene_actor)
    G.goombas, G.doors, G.paintings, G.fireballs, G.bowser = {}, {}, {}, {}, nil
    G.coins, G.getup_at, G.doors_paired = {}, nil, nil
    G.water_shells, G.jingles = {}, {}
    for _, st in ipairs(G.stars or {}) do lib.destroy(st.inst and st.inst.actor) end
    G.stars, G.red_star, G.star_exit_at, G.music_back_at = {}, nil, nil, nil
    G.secret_star, G.triggers, G.secrets = nil, {}, 0
    for _, sd in ipairs(G.stardoors or {}) do lib.destroy(sd.inst and sd.inst.actor) end
    G.stardoors, G.warps, G.rule = {}, {}, nil
    G.bounds, G.inside = nil, nil
    for _, m in ipairs(CREATURES) do if m.clear then pcall(m.clear) end end
    PLAT.clear()
    G.scene_actor, G.pmc, G.floor, G.data, G.name = nil, nil, nil, nil, nil
    if package.loaded["fog"] then pcall(package.loaded["fog"].apply, nil) end     -- (none over a menu after it)
    lib.sweep_stale()
    if G.restore_walkable then G.restore_walkable() end
    if MUSIC and MUSIC.ambience then pcall(MUSIC.ambience, nil) end
    if BUTTERFLY then pcall(BUTTERFLY.clear) end
    if MOVTEX then pcall(MOVTEX.clear) end
    if ENVFX then pcall(ENVFX.clear) end
    if SCENERY then pcall(SCENERY.clear) end
    if MIRROR then pcall(MIRROR.clear) end
    if CAMLAK then pcall(CAMLAK.clear) end
    if HOOT then pcall(HOOT.clear) end
    if POLES then pcall(POLES.clear) end
    if CLIMB then pcall(CLIMB.clear) end
    if CORK then pcall(CORK.clear) end
    if PAINT then pcall(PAINT.clear) end
    if QSAND then pcall(QSAND.reset) end
    if HANG then pcall(HANG.clear) end
    if SHELL then pcall(SHELL.clear) end
    if FLIGHT then pcall(FLIGHT.clear) end
    if SLIDE then pcall(SLIDE.clear) end
    if FOOTIK then pcall(FOOTIK.clear) end
    if ROUNDOFF then pcall(ROUNDOFF.clear) end
    if UNDERWATER then pcall(UNDERWATER.clear) end
    if MUSIC and MUSIC.waterfall then pcall(MUSIC.waterfall, nil) end
end

local function wpos(p) return { X = p[1] + OFFSET.X, Y = p[2] + OFFSET.Y, Z = p[3] + OFFSET.Z } end

-- Hazy Maze Cave: the drop off the end of the boulders' slope, where its rocks roll off into the big cavern - looking
-- down it, the cavern's walls far below showed: "the hole the boulders go down in hazy maze is seethrough can see walls
-- down in the hole ... just fix the boulder hole by putting a black panel at the bottom so you cant see through it",
-- 2026-11-02. A black floor across it 1.5 m under the slope's lowest point (z -995), from under the slope's end (x 3100)
-- out over the drop to the cavern's walls; drawn both sides, never touched. Scene cm.
G.HMC_HOLE = { x0 = 1500.0, x1 = 3200.0, y0 = -4800.0, y1 = -2400.0, z = -1150.0 }
function G.hmc_hole_cover(world)
    local h = G.HMC_HOLE
    local cx, cy = (h.x0 + h.x1) / 2.0, (h.y0 + h.y1) / 2.0
    local hx, hy = (h.x1 - h.x0) / 2.0, (h.y1 - h.y0) / 2.0
    local actor = lib.spawn_actor(world, wpos({ cx, cy, h.z }), 0.0)
    if not actor then return end
    local pmc = lib.add_pmc(actor)
    if not pmc then return end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    local sec = {
        id = 0, layer = "opaque", texture = "black", nverts = 4, ntris = 4,
        pos = { -hx, -hy, 0.0, hx, -hy, 0.0, hx, hy, 0.0, -hx, hy, 0.0 },
        uv = { 0, 0, 1, 0, 1, 1, 0, 1 },
        col = { 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
        nrm = { 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1 },
        idx = { 0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2 },
    }
    lib.add_sections(world, pmc, { sec })
    pcall(function() pmc:SetCastShadow(false) end)
    log("hmc: the boulders' drop covered in black (%.0f x %.0f cm at z %.0f)", hx * 2.0, hy * 2.0, h.z)
end

-- His animation runs every frame, seen or not. STORROR's athlete only animates while he is on the screen
-- (VisibilityBasedAnimTickOption 4); when his animation ran again after a scene had been torn down out of his sight,
-- it read freed memory and crashed the game: three times in the ending (the ending sets this for itself), and after
-- a game over, parked at the file select while Bowser's arena went (2026-10-14). Set at every scene load.
local function always_animate(pawn)
    if not pawn then return end
    local cls = StaticFindObject("/Script/Engine.SkeletalMeshComponent")
    for _, c in ipairs(pawn:K2_GetComponentsByClass(cls)) do
        local o = c:get()
        pcall(function()
            if o.VisibilityBasedAnimTickOption ~= 0 then o.VisibilityBasedAnimTickOption = 0 end
            if o.bEnableUpdateRateOptimizations then o.bEnableUpdateRateOptimizations = false end
        end)
    end
end

-- a Mario 64 sound (<mod>/sfx/<name>.wav, sfx.lua), at loudness v (0..1)
local function sfx(name, v)
    local S = package.loaded["sfx"]
    if S then pcall(S.play, name, v) end
end

-- Mario's voice on a jump (as loud as the player's MARIO FX setting, as all his voice is: sfx.lua M.mario_fx)
local function jump_voice(name)
    sfx(name)
end

local function add_goomba(world, o)
    local data = actor_data("goomba")
    if not data then return end
    local scale = ((o.size == "huge") and 3.5 or ((o.size == "tiny") and 0.5 or 1.0)) * G.GOOMBA_SIZE
    local x, y, z = o.pos[1], o.pos[2], o.pos[3]
    local fz = floor_z(x, y, z + 300)
    if fz then z = fz end
    local inst = lib.make_instance(world, data, wpos({ x, y, z }), o.yaw, scale)
    if not inst then return end
    local g = {
        inst = inst, x = x, y = y, z = z, hx = x, hy = y, scale = scale,
        heading = rad(math.random(0, 359)), turn_t = 1 + math.random() * 2, state = "wander",
        f = math.random(0, 29), cool = 0.0, t = 0.0, resp = 0.0,
    }
    G.goombas[#G.goombas + 1] = g
    -- (in its walk's pose from the start: one far from him is not moved, and stood as it is made, unposed - on its side,
    -- its feet out: THI's in the ending's credits, "tiny huge goombas laying on they're side like a t pose", 2026-11-02)
    local anim = data.anims and data.anims[1]
    if anim then pcall(lib.pose, inst, anim, g.f) end
end

-- Mario 64's door collision (actors/warp_collision: door_seg3_collision_0301CE78), made a closed slab: 160 units
-- wide, 240 tall, 60 thick, about the doorway, in the door's own space (the game's x, y, z as -z, x, y; 0.75 cm a unit)
local DOOR_COLLISION = (function()
    local pos = {}
    for _, p in ipairs({ { -80, 0, -30 }, { 80, 0, -30 }, { 80, 240, -30 }, { -80, 240, -30 },
                         { -80, 0, 30 }, { 80, 0, 30 }, { 80, 240, 30 }, { -80, 240, 30 } }) do
        pos[#pos + 1], pos[#pos + 2], pos[#pos + 3] = -p[3] * 0.75, p[1] * 0.75, p[2] * 0.75
    end
    return { source = "door", pos = pos,
             idx = { 0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6, 0, 4, 5, 0, 5, 1, 1, 5, 6, 1, 6, 2,
                     2, 6, 7, 2, 7, 3, 3, 7, 4, 3, 4, 0 } }
end)()

-- a shut door is solid; while it swings it is not
local function door_solid(dr, on)
    if dr.col and dr.solid ~= on then
        dr.solid = on
        pcall(function() dr.col:SetCollisionEnabled(on and 3 or 0) end)
    end
end

-- The door models carry Mario 64's lighting baked into their colours as the exporter found it, in the model's own
-- frame: ambient 0.25 and the light from (-1, 1, 1) (the model's axes) - the front lit, the back in shadow. Mario 64
-- lights a door alike from either side, so each face gets the light of whichever is brighter, itself or the same face
-- on the door turned round (normal (-x, -y, z)): the right door of a pair is the left one turned round, and showed
-- its dark back - "the right door seems to be darker for all doors", then "the door knobs on the doors are still
-- dark", 2026-10-15. Once per model.
local DOOR_LIGHT = { -1.0 / sqrt(3.0), 1.0 / sqrt(3.0), 1.0 / sqrt(3.0) }
local function door_lit(nx, ny, nz)
    return 0.247 + math.max(0.0, nx * DOOR_LIGHT[1] + ny * DOOR_LIGHT[2] + nz * DOOR_LIGHT[3])
end
local function light_door_faces(data)
    if data.faces_lit then return end
    data.faces_lit = true
    for _, part in ipairs(data.parts or {}) do
        for _, sec in ipairs(part.sections or {}) do
            local nrm, col = sec.nrm, sec.col
            if nrm and col then
                for i = 0, (sec.nverts or 0) - 1 do
                    local nx, ny, nz = nrm[i * 3 + 1], nrm[i * 3 + 2], nrm[i * 3 + 3]
                    local own = door_lit(nx, ny, nz)
                    local k = math.max(own, door_lit(-nx, -ny, nz)) / own
                    for c = 1, 3 do col[i * 4 + c] = math.min(1.0, col[i * 4 + c] * k) end
                end
            end
        end
    end
end

-- A door's leaf as a solid box: the part of the model with the most to it, the box round its own vertices (thickened
-- to 30 cm at least, so that the athlete cannot slip through an edge), on that part, so that it swings with the leaf.
-- (2026-10-15: "also add collisions to the doors" - "Both": shut and solid until he walks into it, and solid as it
-- swings.) The collision, or nil.
local function leaf_collision(inst)
    local data = inst.data
    local leaf, best = nil, 0
    for pi, part in ipairs(data.parts or {}) do
        local n = 0
        for _, sec in ipairs(part.sections or {}) do n = n + (sec.nverts or 0) end
        if n > best and inst.comps[pi] then leaf, best = pi, n end
    end
    if not leaf then return nil end
    local lo, hi = { 1e9, 1e9, 1e9 }, { -1e9, -1e9, -1e9 }
    for _, sec in ipairs(data.parts[leaf].sections) do
        local p = sec.pos
        for v = 0, (sec.nverts or 0) - 1 do
            for k = 1, 3 do
                lo[k] = math.min(lo[k], p[v * 3 + k]); hi[k] = math.max(hi[k], p[v * 3 + k])
            end
        end
    end
    local mid = (lo[1] + hi[1]) / 2
    lo[1], hi[1] = math.min(lo[1], mid - 15.0), math.max(hi[1], mid + 15.0)
    local pos = {}
    for _, c in ipairs({ { 1, 1, 1 }, { 2, 1, 1 }, { 2, 2, 1 }, { 1, 2, 1 }, { 1, 1, 2 }, { 2, 1, 2 }, { 2, 2, 2 }, { 1, 2, 2 } }) do
        pos[#pos + 1] = (c[1] == 1) and lo[1] or hi[1]
        pos[#pos + 1] = (c[2] == 1) and lo[2] or hi[2]
        pos[#pos + 1] = (c[3] == 1) and lo[3] or hi[3]
    end
    local col = lib.add_pmc(inst.actor)
    if not col then return nil end
    lib.add_collision(col, { { source = "door leaf", pos = pos, idx = DOOR_COLLISION.idx } })
    pcall(function() col:K2_AttachToComponent(inst.comps[leaf], FName("None"), 2, 2, 2, false) end)
    return col
end

-- Doors come out of only, by scene and the warp node each names: never opened from outside, he only arrives through
-- them. Cool, Cool Mountain's at the foot of the mountain, the slide's way out ("in cool cool mountain the door at the
-- bottom of the map can only be exited from. But opens anyways", 2026-11-06).
G.EXIT_ONLY_DOORS = { ccm = { [20] = true } }
local function add_door(world, o)
    local data = actor_data("door_" .. tostring(o.style or "wooden")) or actor_data("door_wooden")
    if not data then return end
    light_door_faces(data)
    local inst = lib.make_instance(world, data, wpos(o.pos), o.yaw, 1.0)
    if not inst then return end
    -- a door to somewhere else names a warp node; the scene says where that node leads
    local w = o.node and G.warp[o.node] or nil
    lib.pose(inst, data.anims[1], 0)
    local col = nil
    pcall(function() col = leaf_collision(inst) end)
    if not col then
        pcall(function()
            col = lib.add_pmc(inst.actor)
            if col then lib.add_collision(col, { DOOR_COLLISION }) end
        end)
    end
    G.doors[#G.doors + 1] = {
        inst = inst, x = o.pos[1], y = o.pos[2], z = o.pos[3], yaw = o.yaw, data = data,
        target = w and w.scene or nil, dest = w and w.node or nil, need = o.need, key = o.key,
        f = -1, anim = 2, armed = true, col = col, solid = true, style = o.style,
        exit_only = (o.node and G.EXIT_ONLY_DOORS and G.EXIT_ONLY_DOORS[G.name or ""] and G.EXIT_ONLY_DOORS[G.name or ""][o.node]) or nil,
    }
end

local function add_bowser(world, o)
    local data = actor_data("bowser")
    if not data then return end
    local inst = lib.make_instance(world, data, wpos(o.pos), o.yaw, 1.0)
    if not inst then return end
    G.bowser = {
        inst = inst, x = o.pos[1], y = o.pos[2], z = o.pos[3], yaw = o.yaw,
        state = "idle", f = 0.0, anim = 1, atk = 4.0, breath_t = 0.0, shots = 0,
        hx = o.pos[1], hy = o.pos[2], hz = o.pos[3], health = (G.name == "bowser_3") and 3 or 1,
    }
end

-- Mario 64's camera-facing level pieces that the export baked in flat: left out of the scene's mesh and put up as
-- pictures that face the camera. The Dark World arena's sixteen yellow spheres round its rim (special_level_geo_03 =
-- bowser_1_yellow_sphere_geo: a billboarded 153-unit square picture, at 384 up), at the game's own places (x, z);
-- baked, their triangles came out scrambled into a few lopsided yellow eggs on one side - "its just a yellow ball
-- thing thats supposed to be inbetween each of the corners of the map", 2026-10-14
local BILLBOARD_PROPS = {
    bowser = { texture = "actors__yellow_sphere__yellow_sphere.rgba16", half = 76.5, y = 384.0, at = {
        { 0, 3072 }, { -2171, -2171 }, { 0, -3071 }, { -3071, 0 }, { -2171, 2172 }, { -2621, 1086 }, { 2172, 2172 },
        { 3072, 0 }, { 2172, -2171 }, { -1085, 2622 }, { 2622, 1086 }, { -2621, -1085 }, { -1085, -2621 },
        { 1086, -2621 }, { 2622, -1085 }, { 1086, 2622 } } },
}
G.sprites = {}

-- the bombs round Bowser's arena
G.bombs = {}
local function add_bowser_bomb(world, o)
    local data = actor_data("bowser_bomb")
    if not data then return end
    local inst = lib.make_instance(world, data, wpos(o.pos), 0.0, 1.0)
    -- (`floor`: which of the final fight's three floors it lies on - G.pancakes)
    if inst then G.bombs[#G.bombs + 1] = { inst = inst, x = o.pos[1], y = o.pos[2], z = o.pos[3], floor = o.floor } end
end

-- STORROR's push (an attack montage while not falling): a new one since the last look, for grabbing his tail
local last_push = nil
local function pushed(pawn)
    local name, addr = nil, nil
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        if not (ai and ai:IsValid()) then return end
        local mt = ai:GetCurrentActiveMontage()
        if mt and mt:IsValid() then name, addr = mt:GetFName():ToString(), mt:GetAddress() end
    end)
    local is = name and (name:find("Attack") or name:lower():find("push")) and true or false
    local fresh = is and addr ~= last_push
    last_push = is and addr or nil
    return fresh
end

local DDD_BACK = (5529.6 - 3456.0) * 0.75        -- (cm the DDD painting goes back: paintings.c move_ddd_painting)

-- the DDD painting moved back (G.ddd_slide: cm along the scene's Y, Mario 64's X), 20 Mario units a frame till it is there
local function update_ddd_slide(dt)
    local sl = G.ddd_slide
    local p
    for _, q in ipairs(G.paintings) do if q.pt and q.pt.name == "ddd" then p = q end end
    if not p then return end
    if sl.at < DDD_BACK then
        sl.at = math.min(DDD_BACK, sl.at + 20.0 * 30.0 * 0.75 * dt)
        if sl.at >= DDD_BACK then
            local MN = _G.MENU
            if MN and MN.add_flag then pcall(MN.add_flag, "ddd_moved_back") end
            log("DDD painting: moved back")
        end
    elseif sl.placed then
        return
    end
    sl.placed = sl.at >= DDD_BACK
    pcall(function() p.actor:K2_TeleportTo({ X = OFFSET.X, Y = OFFSET.Y + sl.at, Z = OFFSET.Z }, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }) end)
end

local function add_painting(world, pt)
    local c = pt.corners
    local nx, ny, nz = pt.normal[1], pt.normal[2], pt.normal[3]
    -- (its picture stays on the wall's face; behind it, its hollow - G.recess_paintings - `recess` deep)
    local f0 = { c[1], c[2], c[3] }
    local back = pt.recess or 0.0
    local ox, oy, oz = nx * 2, ny * 2, nz * 2
    local verts = {}
    for i = 0, 3 do verts[i + 1] = { X = c[i * 3 + 1] + ox, Y = c[i * 3 + 2] + oy, Z = c[i * 3 + 3] + oz } end
    local actor = lib.spawn_actor(world, wpos({ 0, 0, 0 }), 0.0)
    if not actor then return end
    local pmc = lib.add_pmc(actor)
    if not pmc then return end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    -- edge vectors for the trigger test
    local e1 = { c[4] - c[1], c[5] - c[2], c[6] - c[3] }
    local e2 = { c[10] - c[1], c[11] - c[2], c[12] - c[3] }
    local q = {
        actor = actor, pt = pt, c0 = { c[1], c[2], c[3] }, e1 = e1, e2 = e2,
        l1 = sqrt(e1[1] ^ 2 + e1[2] ^ 2 + e1[3] ^ 2), l2 = sqrt(e2[1] ^ 2 + e2[2] ^ 2 + e2[3] ^ 2),
        f0 = f0, recess = (back > 0.0) and back or nil,
    }
    G.paintings[#G.paintings + 1] = q
    if PAINT then
        local okp, errp = pcall(PAINT.add, world, q, pmc)
        if okp then return end
        log("painting %s: no ripple (%s)", pt.name, tostring(errp))
    end
    local ok, err = pcall(function()
        local n = { X = nx, Y = ny, Z = nz }
        lib.create_section(pmc, 0, verts, { 0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2 }, { n, n, n, n },
            { { X = 0, Y = 1 }, { X = 1, Y = 1 }, { X = 1, Y = 0 }, { X = 0, Y = 0 } },
            { { R = 1, G = 1, B = 1, A = 1 }, { R = 1, G = 1, B = 1, A = 1 }, { R = 1, G = 1, B = 1, A = 1 }, { R = 1, G = 1, B = 1, A = 1 } }, false)
        local mid = lib.get_mid(world, "opaque", pt.texture)
        if mid then pmc:SetMaterial(0, mid) end
    end)
    if not ok then log("painting %s failed: %s", pt.name, tostring(err)) end
end

-- translucent water surfaces from the level's water boxes (scene-space UE units, see exporter)
-- One water box's level (scene cm), its surface moved with it: the i-th box of the scene that is water to swim in.
function G.water_box_level(i)
    local r = G.water_rects and G.water_rects[i]
    return r and r.z
end
function G.set_water_box(i, z)
    local r = G.water_rects and G.water_rects[i]
    if r then r.z = z end
    local w = G.water_actors and G.water_actors[i]
    if w then
        pcall(function() w.actor:K2_TeleportTo({ X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z + (z - w.base) }, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }) end)
    end
end

-- a scene's water level, when it can change (WDW): Mario 64 units; the surfaces, the water boxes and what floats move
G.water_actors = {}
function G.water_level() return G.wlevel end
function G.set_water_level(y)
    G.wlevel = y
    if G.name == "wdw" or G.name == "wdw_2" then G.wdw_level = y end
end
local function apply_water_level(dt)
    if not G.wlevel then return end
    G.wbob = (G.wbob or 0) + dt * 30.0 * 0x200
    local y = G.wlevel + sin(G.wbob * math.pi / 32768.0) * 20.0          -- (bhv_init_changing_water_level_loop)
    local z = y * 0.75
    for _, r in ipairs(G.water_rects or {}) do r.z = z end
    for _, w in ipairs(G.water_actors) do
        pcall(function() w.actor:K2_TeleportTo({ X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z + (z - w.base) }, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }) end)
    end
end
G.apply_water_level = apply_water_level

-- (each box's look, as Mario 64 draws it: exporter/waterx.py)
local WATER_TEX = { water = "water_surface2", jrb = "movtex_texture_waterbox_jrb_water", mist = "movtex_texture_waterbox_mist",
                    lava = "movtex_texture_waterbox_lava", unk = "movtex_texture_waterbox_unknown_water" }
-- HMC's poison gas (mario.c: below the gas's top less 100 he is in it; 4 of 2176 health a frame): a wedge every 64
-- frames, with a cough now and then. Not under the metal cap (MARIO_METAL_CAP). (The maze's floor is only 2 cm under
-- that line, and his capsule rests a little over the floor: he was never in it - "make the smoke in hazy maze do
-- damage", 2026-10-20. GAS_SLACK cm of give; the raised parts, 5 cm higher than that, stay clear as in Mario 64.)
G.GAS_SLACK = 12.0
function G.poison_gas(dt, x, y, feet)
    local inside = false
    for _, r in ipairs(G.gas_rects or {}) do
        if x > r.x0 and x < r.x1 and y > r.y0 and y < r.y1 and feet < r.z - 100.0 * 0.75 + G.GAS_SLACK then inside = true; break end
    end
    if inside and CAPS and CAPS.on and CAPS.on("metal") then inside = false end
    if not inside then G.gas_t = nil; return end
    G.gas_t = (G.gas_t or 0.0) + dt
    if G.gas_t >= 64.0 / 30.0 then
        G.gas_t = G.gas_t - 64.0 / 30.0
        local HP = _G.HEALTH
        if HP and HP.damage and not HP.dead_t then HP.damage(1, "poison gas") end
        sfx("mario_cough")
    end
end

-- Mario 64's own texture scale for a scene's boxes (MOV_TEX_ROT_SCALE in levels/*/movtext.inc.c, by box id): the
-- texture repeats about scale x 1.41 times along each side of the box, whatever its size (movtex_make_quad_vertex).
-- Elsewhere a repeat every 320 cm, as before. ("zoom the texture also offset it", Jolly Roger Bay, 2026-10-18: its
-- bay's water repeated three or four times too often, a grid of small squares.)
G.WATER_SCALE = { jrb = { [0] = 6, [1] = 2, [51] = 3 } }    -- (the mist's 10 made 3: "make the fog squares bigger")
G.MIST_UNDER = 0.45                 -- (the mist's underside: its opacity)

local function add_water(world, boxes)
    for i, b in ipairs(boxes or {}) do
        local MN = _G.MENU
        local gone = b.mist_until and MN and MN.has_star and (MN.has_star(b.mist_until) or MN.has_star(b.mist_until:gsub(":", "_2:")))
        if gone then goto next_box end
        local x0, x1 = -b.z2, -b.z1      -- UE X from SM64 -z
        local y0, y1 = b.x1, b.x2        -- UE Y from SM64 x
        local z = b.y
        local T = 320.0
        local sc = G.WATER_SCALE[G.name or ""] and G.WATER_SCALE[G.name or ""][b.id or -1]
        local Tu, Tv = T, T                  -- (cm a repeat along Y and along X)
        if sc then Tu, Tv = (y1 - y0) / (sc * 1.4142), (x1 - x0) / (sc * 1.4142) end
        local off = (b.tex == "mist") and 0.5 or 0.0       -- (the mist's pattern half a repeat off the water's under it)
        local verts = {
            { X = x0, Y = y0, Z = z }, { X = x0, Y = y1, Z = z },
            { X = x1, Y = y1, Z = z }, { X = x1, Y = y0, Z = z },
        }
        local up = { X = 0, Y = 0, Z = 1 }
        local tint = b.tint or { 1.0, 1.0, 1.0 }
        local col = { R = tint[1], G = tint[2], B = tint[3], A = b.alpha or 0.59 }
        local actor = lib.spawn_actor(world, wpos({ 0, 0, 0 }), 0.0)
        local pmc = actor and lib.add_pmc(actor)
        if pmc then
            pcall(function() pmc:SetCollisionEnabled(0) end)
            local ok, err = pcall(function()
                -- (both faces: seen from under the water, or the mist from under it, it was not there at all -
                -- "underneith the texture doesnt show". The mist's underside a section of its own: below.)
                local mist = b.tex == "mist"
                local uvs = { { X = y0 / Tu + off, Y = x0 / Tv + off }, { X = y1 / Tu + off, Y = x0 / Tv + off },
                              { X = y1 / Tu + off, Y = x1 / Tv + off }, { X = y0 / Tu + off, Y = x1 / Tv + off } }
                lib.create_section(pmc, 0, verts, mist and { 0, 1, 2, 0, 2, 3 } or { 0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2 },
                    { up, up, up, up }, uvs, { col, col, col, col }, false)
                -- (a mist box as faint as Mario 64 draws it, MOV_TEX_ALPHA 0x32: the material takes no notice of the
                -- vertices' alpha, so its own - drawn at the picture's own, Jolly Roger Bay's first-visit mist lay over
                -- the bay and its beach like a thick white fog: "we have to fix the fog in sunken bay", 2026-10-18)
                -- (the green room's and Jolly Roger Bay's water picture is solid - Mario 64 draws it at the box's alpha,
                -- 0x96: drawn solid, Mips ran under it out of sight, "I cant see him in the water", 2026-10-19)
                local own = mist and (b.alpha or 0.196) or (b.tex == "jrb" and b.alpha) or nil
                local mid = lib.get_mid(world, "translucent", WATER_TEX[b.tex or "water"] or "water_surface2", own)
                if mid then pmc:SetMaterial(0, mid) end
                if mist then
                    -- (from under it, the mist as faint as from above was white on the bright sky and not there at
                    -- all - "the fog texture is invisable from underneith", 2026-10-18: its underside G.MIST_UNDER thick)
                    local dn = { X = 0, Y = 0, Z = -1 }
                    lib.create_section(pmc, 1, verts, { 0, 2, 1, 0, 3, 2 }, { dn, dn, dn, dn }, uvs, { col, col, col, col }, false)
                    local mid2 = lib.get_mid(world, "translucent", WATER_TEX.mist or "water_surface2", G.MIST_UNDER)
                    if mid2 then pmc:SetMaterial(1, mid2) end
                    G.mist_pmcs[#G.mist_pmcs + 1] = pmc
                end
            end)
            if not ok then log("water %d failed: %s", i, tostring(err)) end
            if ok then
                G.water_rot = G.water_rot or {}
                G.water_rot[#G.water_rot + 1] = { pmc = pmc, verts = verts, cx = (x0 + x1) / 2.0, cy = (y0 + y1) / 2.0, T = T,
                                                  Tu = Tu, Tv = Tv, off = off, dir = (i % 2 == 0) and -1.0 or 1.0, col = col,
                                                  under = b.tex == "mist",
                                                  -- (RENDER 96's real water takes it over: water96.lua - only water
                                                  -- he can swim in: Shifting Sand Land's quicksand pools are boxes of
                                                  -- the water picture tinted sand, and came out blue and clear - "shifting
                                                  -- sand lands quick sand is showing as water", 2026-11-02)
                                                  actor = actor, x0 = x0, x1 = x1, y0 = y0, y1 = y1, base = z,
                                                  tex = b.tex or "water", w96 = (b.swim ~= false or b.tex == "lava") }
            end
            G.extras[#G.extras + 1] = actor
            if b.swim ~= false then G.water_actors[#G.water_actors + 1] = { actor = actor, base = z } end
        end
        ::next_box::
    end
end

-- (their texture turns slowly about the box's middle, as Mario 64's water boxes do: MOV_TEX_ROT_SPEED 10 to 20 a frame
-- of 0x10000, one way or the other - the castle's moat and lake, the courses' water. It stood still.)
local WATER_ROT_SPEED = 15.0 * 30.0 / 65536.0 * 2.0 * math.pi        -- radians a second
local function turn_water(dt)
    local list = G.water_rot
    if not list or #list == 0 then return end
    G.water_rot_t = (G.water_rot_t or 0.0) + dt
    G.water_rot_n = ((G.water_rot_n or 0) + 1) % 2
    if G.water_rot_n ~= 0 then return end                           -- (every other frame)
    for _, w in ipairs(list) do
        if w.still then goto still end          -- (RENDER 96's real water: its pictures drift instead - water96.lua)
        local a = G.water_rot_t * WATER_ROT_SPEED * w.dir
        local ca, sa = cos(a), sin(a)
        local uvs = {}
        local Tu, Tv, off = w.Tu or w.T, w.Tv or w.T, w.off or 0.0
        for k, v in ipairs(w.verts) do
            local u, vv = (v.Y - w.cy) / Tu, (v.X - w.cx) / Tv
            uvs[k] = { X = w.cy / Tu + u * ca - vv * sa + off, Y = w.cx / Tv + u * sa + vv * ca + off }
        end
        local ok = pcall(lib.update_section, w.pmc, 0, w.verts, { w.col, w.col, w.col, w.col }, uvs)
        if ok and w.under then pcall(lib.update_section, w.pmc, 1, w.verts, { w.col, w.col, w.col, w.col }, uvs) end
        if not ok then w.dir = 0.0 end
        ::still::
    end
end
G.turn_water = turn_water

local function add_tree(world, o)
    -- (RENDER 96: Render96's tree, a model all round - not turned to the camera, casting its own shadow: lib.r96_trees)
    local r96 = lib.r96_trees and lib.r96_trees()
    local t3 = r96 and r96[o.geo]
    if t3 then
        local loc = wpos(o.pos)
        local actor = lib.spawn_actor(world, loc, 0.0)
        local pmc = actor and lib.add_pmc(actor)
        if not pmc then return end
        pcall(function() pmc:SetCollisionEnabled(0) end)
        lib.add_sections(world, pmc, t3)
        G.trees[#G.trees + 1] = { actor = actor, x = loc.X, y = loc.Y, z = loc.Z, yaw = 0.0, fixed = true }
        return
    end
    local tpl = G.data.tree_templates and G.data.tree_templates[o.geo]
    if not tpl then return end
    local loc = wpos(o.pos)
    local actor = lib.spawn_actor(world, loc, 0.0)
    local pmc = actor and lib.add_pmc(actor)
    if not pmc then return end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    lib.add_sections(world, pmc, tpl)
    -- (it turns to the camera, and so would its shadow: none from it - a copy of it turned to the sun, hidden, casts the
    -- tree's own - the engine's "cast hidden shadow". Made whatever the setting: with real-time shadows off the sun casts
    -- none - G.set_realtime_shadows)
    local caster = nil
    pcall(function() pmc:SetCastShadow(false) end)
    pcall(function()
        local sun = (_G.MENU and _G.MENU.SUN) or { 65.0, 35.0 }
        caster = lib.spawn_actor(world, loc, sun[2])
        local cp = caster and lib.add_pmc(caster)
        if not cp then return end
        cp:SetCollisionEnabled(0)
        lib.add_sections(world, cp, tpl)
        cp:SetCastHiddenShadow(true)
        caster:SetActorHiddenInGame(true)
        G.extras[#G.extras + 1] = caster
    end)
    G.trees[#G.trees + 1] = { actor = actor, x = loc.X, y = loc.Y, z = loc.Z, yaw = 0.0, caster = caster }
end

-- the game's character only treats slopes up to 20 degrees as walkable; SM64 floors go up to ~60
G.WALK_ANGLE = 60.0
G.STEP_HEIGHT = 50.0        -- cm the athlete can walk up without jumping (STORROR's own is 10, too little for Mario's stairs)
-- The slide courses (Mario 64's TERRAIN_SLIDE: every slope over 5 degrees slides): there any slope over 5 degrees is too
-- steep to walk, so STORROR's own slope slide takes him down it (its Slide_Slope falling move; the floors also block its
-- "Slide" channel, load_scene) - the user, 2026-10-16: "use storrors original sliding"
G.SLIDE_COURSES = { pss = true, ccm_2 = true, ttm_2 = true, ttm_3 = true, ttm_4 = true }
-- (BoB: the tree by the cannon rock moved to the rock's foot, to climb and jump across onto it - "can you move this tree
-- closer to the cannon on the rock so you can get up there?", 2026-10-16)
G.TREE_MOVES = { bob = { { -2829.0, 3156.0, -3079.0, 3504.0, 753.0 } } }     -- (then "a little further away")
-- Scenes whose slide floors all slide him only on his way down, as the gentle ones below: Mario 64 starts a slide only
-- standing, facing downhill or backing (should_begin_sliding) - he walks up the slippery slopes. BBH's roof (35-65
-- degrees) is the way from the balcony to the act 5 star, and the athlete slid off it every time (2026-10-22).
G.WALKUP_SLIDES = {}
-- Scenes with no slide floors at all: Mario 64's slippery floors there are plain floor. A number is the steepest slope
-- stood on there (else the athlete's own limit, 60 degrees): BBH's roof (35-65 degrees, its way from the balcony to the
-- act 5 star), walked up and down without a slide ("next make sure the entire roof is slide free", 2026-10-22).
-- Shifting Sand Land's dunes (10-50 degrees, slippery and very slippery sand) slid him where nothing looked like a
-- slide, on along the flat after ("randomly sliding", 2026-10-22): its sand and the pyramid's are plain floor.
-- Snowman's Land's snow and ice banks round the frozen pond (21, 29, and a 29 m sliver of 46 degrees along its edge)
-- slid him off the moment he set foot on them - "random spots around map making player slide", 2026-10-26 - and as
-- walk-up slides (G.WALKUP_SLIDES) still at every step down or across them at his walking pace ("still sliding randomly"):
-- plain floor. (Its ice keeps its little grip: G.ice_walk.)
G.NO_SLIDES = { bbh = 70.0, ssl = true, ssl_2 = true, sl = true }
-- ...but there, the slide floors with their middle in one of these boxes (x0, y0, x1, y1, z0, z1: scene cm) slide still:
-- Snowman's Land's 45-55 degree bank by where the snow mounds start - "also the slope im standing on should slide the
-- player", 2026-10-26.
G.SLIDE_KEEP = { sl = { { -2926.0, 581.0, -1047.0, 1540.0, 738.0, 1146.0 } } }
-- ...and there, every slide floor at least this steep (degrees) slides still: Mario 64's default floors from 38 degrees
-- are too steep to stand, and Snowman's Land's border walls (41-72) and steep banks, up to its 60-degree limit, were
-- walked up - "very steep surfaces and border walls dont make player slide", 2026-10-26. (Its frozen pond's banks stay
-- plain floor: G.NO_SLIDE_AT. The steep faces of the igloo's drawn dome slide too: G.move_pieces' solid_drawn.)
G.SLIDE_MIN = { sl = 45.0 }
-- (45, not 40: the snow-mound bank's 41-42 degree top lip slid him walking along it - "sliding", 2026-10-26)
-- ...but not those reaching down into its water (a corner inside a water box, under its top or 40 over it): Snowman's
-- Land's lake banks - he jumped out of the water onto them and slid straight back in, "swimming is messed up now",
-- 2026-10-26. (The snow-mound bank, G.SLIDE_KEEP, slides still.)
G.SLIDE_DRY = { sl = true }
-- ...but there, the slopes into the deadly quicksand slide still: Mario 64's very slippery band round the course's edge,
-- the banks of the pyramid's moat and of the pits slide him in, as they do Mario - slide-free, he stood at the edge of
-- the quicksand ("its not sucking the player under the surface also im standing on it somehow", 2026-10-23). Those
-- are the slide floors with an edge on the deadly quicksand, and the ones joined to them by an edge (G.quicksand_banks).
G.SLIDE_BANKS = { ssl = true }
-- Slide floors that are plain floor here: those with their middle in a box { x1, y1, x2, y2, z1, z2 } (scene cm). Bowser
-- in the Fire Sea's ridged ramp by the start, its top lined with coins (39 and 45 degrees: walked up and down) - "turn off
-- sliding on this ramp", 2026-10-24. A 7th number is the steepest slope stood on there (degrees), for floors steeper than
-- the athlete's own 60: they are a piece of their own that he can stand on that steep (G.add_slides).
G.NO_SLIDE_AT = { bitfs = { { -500.0, -900.0, 0.0, 0.0, 150.0, 700.0 } },
                  -- (Tall Tall Mountain's slope over the start pond, 52 and 61 degrees, 2.6 m up to the ledge above:
                  -- "sliding on this slope fix", 2026-10-27. Its 59-degree drop below, to the pond, slides still)
                  ttm = { { -3080.0, 850.0, -1910.0, 1545.0, -1425.0, -1150.0, 65.0 },
                  -- (and the 46-degree slope up onto the ledge by the mountain path, 3 m across and 1.5 m up: "sliding
                  -- on this platform to my left", 2026-10-27)
                          { 2150.0, -1030.0, 2260.0, -940.0, -260.0, -150.0 } },
                  -- (and Snowman's Land's frozen pond, its banks round it: 21, 29 and 46-52 degrees, "random spots around
                  -- map making player slide", 2026-10-26 - kept so with the steep ones back, G.SLIDE_MIN)
                  sl = { { 350.0, -1250.0, 2250.0, 800.0, 600.0, 1100.0 },
                  -- (and the big snowman: its body's and head's 42-77 degree sides, the way up wound round them - "it was
                  -- on the path climbing up to the snowman", 2026-10-26)
                         { -900.0, -900.0, 900.0, 900.0, 2000.0, 3700.0 },
                  -- (and the snow-mound bank's 54-degree top, above where it slides: walked along, it slid him every
                  -- time - "still sliding in the same area", 2026-10-26)
                         { -1700.0, 850.0, -1150.0, 1100.0, 1146.0, 1350.0 } },
                  -- (the castle grounds' moat bank by the castle's west wall, down from the path to the water: two
                  -- 41-degree slippery floors, 16 m long - "also fix this sliding slope right in front of me", 2026-11-01)
                  grounds = { { -1300.0, 900.0, -800.0, 1300.0, 150.0, 450.0 },
                              { -2700.0, 900.0, -2150.0, 1350.0, 0.0, 300.0 } } }
-- Shifting Sand Land's sand pits (the special objects special_level_geo_03/04 - their quicksand funnels, movtex.lua):
-- under their sand a conveyor carries him to the middle, and the middle is death - sucked under (the instant quicksand
-- there). Nothing in them slides: "instead of sliding into it make a conveyer under the sand that pulls the player
-- torwards the center if the player ends up right in the middle death", 2026-10-23. { x, y } scene cm; 768 round.
G.PITS = { ssl = { { -4313.0, 4320.0 }, { -2201.0, -2687.0 }, { -2201.0, -383.0 }, { -2866.0, 768.0 }, { -281.0, 2304.0 } },
           -- (the pyramid's, at its foot: their floor's height too - `PIT_DZ` over or under it, not in it. Its sand river
           -- 11 m over the one at (-1382, -1305) was taken for it, and drew him to its middle - not carried along:
           -- "the path makes the player float and doesnt go the correct direction", 2026-11-07)
           ssl_2 = { { -1382.0, 1306.0, -230.0 }, { -396.0, 0.0, -230.0 }, { -1382.0, -1305.0, -230.0 } } }
G.PIT_R, G.PIT_PULL, G.PIT_DZ = 768.0, 300.0, 400.0     -- (cm round; cm a second toward the middle; cm up or down)
function G.pit_at(x, y, z)
    for _, c in ipairs(G.PITS[G.name or ""] or {}) do
        local dx, dy = c[1] - x, c[2] - y
        if dx * dx + dy * dy < G.PIT_R * G.PIT_R and not (c[3] and z and math.abs(z - c[3]) > G.PIT_DZ) then return c end
    end
end
-- Things added to a scene that Mario 64 does not have, so the athlete can get where Mario gets with his own moves:
-- { scene = { objects as data/scene_*.lua has them } }. (BBH had three of the hall's staircase steps up to the third
-- floor's door, for the wall kick Mario makes there - taken out at the user's word: "can you remove the stairs to get
-- up top", 2026-10-22. G.BBH_STEP is their model.)
G.BBH_STEP = "geo_bbh_0005B0|bbh_seg7_collision_staircase_step"
G.EXTRA_OBJECTS = {}
-- Tick Tock Clock's floor at the bottom, by the start: a ring of 8 coins - Mario 64's horizontal ring, 300 units round
-- its middle - where the athlete stood ("not enough coins in level add a coin ring where im standing", 2026-10-30).
-- Scene cm, on the floor.
G.EXTRA_OBJECTS.ttc = {
    { kind = "coin", value = 1, ground = true, pos = { 45.5, 1046.5, -3616.5 } },
    { kind = "coin", value = 1, ground = true, pos = { -20.4, 1205.6, -3616.5 } },
    { kind = "coin", value = 1, ground = true, pos = { -179.5, 1271.5, -3616.5 } },
    { kind = "coin", value = 1, ground = true, pos = { -338.6, 1205.6, -3616.5 } },
    { kind = "coin", value = 1, ground = true, pos = { -404.5, 1046.5, -3616.5 } },
    { kind = "coin", value = 1, ground = true, pos = { -338.6, 887.4, -3616.5 } },
    { kind = "coin", value = 1, ground = true, pos = { -179.5, 821.5, -3616.5 } },
    { kind = "coin", value = 1, ground = true, pos = { -20.4, 887.4, -3616.5 } },
}

-- Bars to hang from and jump between - STORROR's own bar hang and its jumps from bar to bar (it swings on anything
-- thinner than its SwingingBarWidth, 30 cm, as on WF's island rings) - where Mario 64's way up is a move the athlete
-- does not have. (BBH had iron bars up the east wall of the second floor's far right room - but on a bar STORROR only
-- swings: its dynos are climbing moves, from a ledge it hangs on with its feet on the wall - "no dino option for some
-- reason?", 2026-10-22. Ledges there now, G.EXTRA_HOLDS.) Each { x0, y0, x1, y1, z }: scene cm.
G.EXTRA_BARS = {}
G.BAR_R, G.BAR_SIDES = 4.0, 10
function G.add_bars(world, name)
    G.bar_actors = {}
    local list = G.EXTRA_BARS[name]
    if not list then return 0 end
    for _, b in ipairs(list) do
        local x0, y0, x1, y1, z = b[1], b[2], b[3], b[4], b[5]
        local ex, ey = x1 - x0, y1 - y0
        local len = sqrt(ex * ex + ey * ey)
        local px, py = -ey / len, ex / len
        local pos, idx, nrm, uv, col = {}, {}, {}, {}, {}
        local R, N = G.BAR_R, G.BAR_SIDES
        for j = 0, N - 1 do
            local an = j * 2 * math.pi / N
            for _, e in ipairs({ { x0, y0 }, { x1, y1 } }) do
                pos[#pos + 1] = e[1] + px * R * cos(an); pos[#pos + 1] = e[2] + py * R * cos(an); pos[#pos + 1] = z + R * sin(an)
                nrm[#nrm + 1] = px * cos(an); nrm[#nrm + 1] = py * cos(an); nrm[#nrm + 1] = sin(an)
                uv[#uv + 1] = 0.0; uv[#uv + 1] = 0.0
                local k = 0.22 + 0.14 * (sin(an) + 1.0) * 0.5            -- (dark iron, lighter along its top)
                col[#col + 1] = k; col[#col + 1] = k; col[#col + 1] = k * 1.1; col[#col + 1] = 1.0
            end
        end
        for j = 0, N - 1 do
            local a0, a1 = j * 2, ((j + 1) % N) * 2
            for _, t in ipairs({ { a0, a1, a0 + 1 }, { a1, a1 + 1, a0 + 1 }, { a0, a0 + 1, a1 }, { a1, a0 + 1, a1 + 1 } }) do
                idx[#idx + 1] = t[1]; idx[#idx + 1] = t[2]; idx[#idx + 1] = t[3]
            end
        end
        local actor = lib.spawn_actor(world, OFFSET, 0.0)
        local pmc = actor and lib.add_pmc(actor)
        if pmc then
            lib.add_collision(pmc, { { source = "bar", pos = pos, idx = idx } })
            -- (his body parts - physics-simulated, object channel 17 - pass through, as with the island rings)
            pcall(function() pmc:SetCollisionResponseToChannel(17, 0) end)
            local vis = lib.add_pmc(actor)
            if vis then
                pcall(function() vis:SetCollisionEnabled(0) end)
                lib.add_sections(world, vis, { { id = 0, layer = "opaque", nverts = #pos // 3, ntris = #idx // 3, pos = pos,
                                                 nrm = nrm, uv = uv, col = col, idx = idx } })
            end
            G.extras[#G.extras + 1] = actor
            G.bar_actors[#G.bar_actors + 1] = actor
        elseif actor then
            lib.destroy(actor)
        end
    end
    log("bars: %d to hang from in %s", #list, name)
    return #list
end

-- Ledges to climb and dyno between: blocks on a wall, their sides taller than STORROR's SwingingBarWidth (30 cm) so it
-- hangs on them as on any ledge, feet on the wall, and dynos from one to the next (its ClimbDyno). BBH: four up the east
-- wall of the second floor's far right room, from over its platform (7.68 m) toward the third floor's landing (13.05
-- m) - each 1 m over the last and 60 cm nearer the landing - then a shelf along the wall level with the landing, its
-- corner, to climb onto and walk off: Mario's wall kick there ("add pole hangs to dino onto to get up there", "on the
-- wall im looking at", "no put them on the wall not the air", "move them closer to eachother", "no dino option for some
-- reason?", "move them further apart", 2026-10-22). Each { x (the wall), out (-1/+1: which way off it), y0, y1, top,
-- depth, height }: scene cm.
-- A pillar's rings of ledges: blocks round all four of its sides (as BBH's, 20 cm out and 40 cm high), a ring every metre
-- from 1 m under its top down to 1.5 m over the ground by it, each on its sides where they are at that height (they
-- lean in, `hb` half its width at its foot `zb`, `ht` at its top `zt`). Scene cm.
function G.pillar_rings(cx, cy, zb, zt, hb, ht, ground, oz)
    local boxes = {}
    local top = zt - 100.0
    while top - 40.0 >= zb and top >= ground + 150.0 do
        local z0 = top - 40.0
        local h = hb + (ht - hb) * (z0 - zb) / (zt - zb) - 1.0             -- (its side at the block's foot, a cm in)
        local o = h + 21.0
        boxes[#boxes + 1] = { cx + h, cx + o, cy - o, cy + o, z0, top }      -- (+x side, round both corners)
        boxes[#boxes + 1] = { cx - o, cx - h, cy - o, cy + o, z0, top }      -- (-x side)
        boxes[#boxes + 1] = { cx - h, cx + h, cy + h, cy + o, z0, top }      -- (+y side, between them)
        boxes[#boxes + 1] = { cx - h, cx + h, cy - o, cy - h, z0, top }      -- (-y side)
        top = top - 100.0
    end
    return { boxes = boxes, oz = oz }
end
G.EXTRA_HOLDS = {
    -- (Shifting Sand Land's four pillars round the pyramid - the "stand tall on the four pillars" star: rings of ledges
    -- all the way round each, to dyno up to its top - "the 4 pillars around the ssl need to be dinoable just like in boos
    -- world to get uptop, make it go all the way around", 2026-10-23)
    ssl = { G.pillar_rings(-576.0, 1344.0, 116.0, 768.0, 144.0, 108.0, 0.0),
            G.pillar_rings(1919.0, 1344.0, 20.0, 672.0, 144.0, 108.0, -74.0, 672.0),
            G.pillar_rings(1919.0, -4415.0, 116.0, 768.0, 144.0, 108.0, 0.0),
            G.pillar_rings(-576.0, -4415.0, 116.0, 768.0, 144.0, 108.0, 0.0) },
    -- (Big Boo's Haunt's lowest at chest height, its top 1.9 m up: at 2.32 m he walked in under it to the wall and
    -- STORROR's climb did nothing there, 2026-10-29)
    -- (Rainbow Ride's wall over the lower ledge by the tiled floor, scene x -202, from its foot (-1336) to the platform
    -- on top (-837), 5 m: three up it a metre apart, the lowest 2 m up, the last a metre under its edge - "make a
    -- ladder right in front of me", then "I shouldnt have said ladder ... like in boo world to get to the roof", 2026-11-02)
    rr = { { -202.0, -1, -2562.0, -2362.0, -1137.0, 20.0, 40.0 }, { -202.0, -1, -2562.0, -2362.0, -1037.0, 20.0, 40.0 },
           { -202.0, -1, -2562.0, -2362.0, -937.0, 20.0, 40.0 },
           -- (the L of wall hanging 5 m over the tiled ledge by the blue coin switch - scene x -202..334 along y -5546..-5392,
           -- and x 257..334 back to y -5008, its foot at -837: brought all the way down to the floor (-1336), blocks of
           -- its own wood under it - "bring this wall all the way down", "the wall thats hanging needs to be lowered",
           -- 2026-11-02. Its top meets the roof, so it is not moved: filled in under it)
           { oz = -837.0, boxes = { { -202.0, 334.0, -5546.0, -5392.0, -1336.0, -837.0 },
                                    { 257.0, 334.0, -5392.0, -5008.0, -1336.0, -837.0 } } } },
    -- (Bowser in the Sky's steep face over the ramp from the start's way (scene x -315..298): 76 degrees, from the
    -- ramp's top (-2918, y 1844) 12.3 m to the slope over it (-1690, y 2150) - ledges up it to dyno and shimmy, each in
    -- the face at its own height: "this wall needs a ladder, or a dino to get up top", then "make it fun to climb slight
    -- difficulty, also color them correctly", 2026-11-02. A zigzag: each over part of the last, so he shimmies along
    -- one to dyno to the next, 0.9 to 1.2 m apart, two wide ones to rest on, the last a metre under the edge. In the
    -- wall's yellow, the plain part of its arrow tile)
    bits = { { oz = -1689.0, look = { texture = "levels__bits__2.rgba16", flat_uv = { 0.22, 0.88 }, tint = { 0.51, 0.51, 0.0 },
                                      u_cm = 536.0, v_cm = 537.0, oy = 0.0, oz = -1689.0 },
               boxes = {
                                       { -175.0, 25.0, 1861.5, 1896.5, -2768.0, -2728.0 }, { -75.0, 125.0, 1888.9, 1923.9, -2658.0, -2618.0 }, { 25.0, 225.0, 1916.4, 1951.4, -2548.0, -2508.0 },
                                       { 25.0, 285.0, 1943.9, 1978.9, -2438.0, -2398.0 }, { -105.0, 55.0, 1973.9, 2008.9, -2318.0, -2278.0 }, { -255.0, -75.0, 2001.3, 2036.3, -2208.0, -2168.0 },
                                       { -295.0, -35.0, 2028.8, 2063.8, -2098.0, -2058.0 }, { -95.0, 65.0, 2056.3, 2091.3, -1988.0, -1948.0 }, { 45.0, 225.0, 2078.8, 2113.8, -1898.0, -1858.0 },
                                       { -35.0, 165.0, 2095.8, 2130.8, -1830.0, -1790.0 } } },
             -- (and the two steep faces further up the same way, x 367..981, each over a ramp: 1130 to 1976 at y 3862..4093,
             -- then 2205 to 2929 at y 4630..4899 - a zigzag up each the same: "on this new wall in front of me", "theres
             -- another one not too far as well", 2026-11-02. In their green-tinted bolted panel's plain corner)
             { oz = 1976.0, look = { texture = "textures__sky__rr_textures.07800.rgba16", flat_uv = { 0.1, 0.9 }, tint = { 0.59, 0.8, 0.59 },
                                      u_cm = 460.0, v_cm = 460.0, oy = 0.0, oz = 0.0 },
               boxes = {
                                       { 574.0, 774.0, 3883.9, 3918.9, 1280.0, 1320.0 }, { 674.0, 874.0, 3913.9, 3948.9, 1390.0, 1430.0 }, { 774.0, 934.0, 3944.0, 3979.0, 1500.0, 1540.0 },
                                       { 534.0, 814.0, 3974.0, 4009.0, 1610.0, 1650.0 }, { 434.0, 614.0, 4004.0, 4039.0, 1720.0, 1760.0 }, { 554.0, 754.0, 4035.7, 4070.7, 1836.0, 1876.0 } } },
             { oz = 2929.0, look = { texture = "textures__sky__rr_textures.07800.rgba16", flat_uv = { 0.1, 0.9 }, tint = { 0.59, 0.8, 0.59 },
                                      u_cm = 460.0, v_cm = 460.0, oy = 0.0, oz = 0.0 },
               boxes = {
                                       { 574.0, 774.0, 4670.6, 4705.6, 2355.0, 2395.0 }, { 454.0, 654.0, 4711.5, 4746.5, 2465.0, 2505.0 }, { 404.0, 564.0, 4752.3, 4787.3, 2575.0, 2615.0 },
                                       { 474.0, 754.0, 4793.2, 4828.2, 2685.0, 2725.0 }, { 674.0, 874.0, 4831.8, 4866.8, 2789.0, 2829.0 } } } },
    bbh = { { 0.0, -1, 2200.0, 2400.0, 958.0, 20.0, 40.0 }, { 0.0, -1, 2140.0, 2340.0, 1100.0, 20.0, 40.0 },
            { 0.0, -1, 2080.0, 2280.0, 1200.0, 20.0, 40.0 }, { 0.0, -1, 1990.0, 2150.0, 1305.0, 60.0, 40.0 } },
    -- (Snowman's Land's big ice block, at half again its size (G.MOVE_PIECES): its maze's way to the top, the shaft
    -- (x -3770..-3540, y 3052..3283) open from the maze's floor (999) to the hole in its roof (1689) - Mario's wall kicks
    -- - a column of ledges up its -x wall, a metre apart, the last a metre under the roof's edge, to dyno up and climb
    -- out onto the roof: "make this dynoable to get to the top", then "you put the dino in the wrong spot inside the ice
    -- puzzle is a way to the top of the blox thats where it needs to be placed", 2026-10-26)
    sl = { { oz = 1689.38, boxes = { { -3771.25, -3750.25, 3062.0, 3273.0, 1149.38, 1189.38 },
                                     { -3771.25, -3750.25, 3062.0, 3273.0, 1249.38, 1289.38 },
                                     { -3771.25, -3750.25, 3062.0, 3273.0, 1349.38, 1389.38 },
                                     { -3771.25, -3750.25, 3062.0, 3273.0, 1449.38, 1489.38 },
                                     { -3771.25, -3750.25, 3062.0, 3273.0, 1549.38, 1589.38 } } } },
    -- (Tiny-Huge Island's red coin cave: two of its red coins are where Mario 64 gets by moves the athlete has not -
    -- the tall pillar in the corner over the low floor (6.1 m, its top 998), wall kicked up, and the high ledge with the
    -- blue coin switch (1075), 3.1 m over the walkway and 3.5 m off it, a triple jump. A column of ledges a metre apart
    -- up the pillar's face toward the low floor, the last a metre under its top; and two rows along the ledge's face
    -- toward the walkway (each one long ledge along the slanting face), 1 and 2 m under its top, to jump across to, catch
    -- and climb, 2026-10-29. The pillar's lowest at chest height, 1.5 m up, as Snowman's Land's: at 1.74 m he walked
    -- in under it and STORROR's climb did nothing there, or threw him through the floor)
    thi_3 = { { oz = 998.0, boxes = {
                  { 1285.0, 1310.0, -1530.0, -1310.0, 534.0, 574.0 }, { 1285.0, 1310.0, -1530.0, -1310.0, 615.0, 655.0 },
                  { 1285.0, 1310.0, -1530.0, -1310.0, 696.0, 736.0 }, { 1285.0, 1310.0, -1530.0, -1310.0, 777.0, 817.0 },
                  { 1285.0, 1310.0, -1530.0, -1310.0, 858.0, 898.0 } } },
              { oz = 1075.5, boxes = {
                  { line = { -768.0, 0.0, -460.5, -153.0 }, n = { 0.4455, 0.8953 }, out = 20.0, back = 5.0, z0 = 835.0, z1 = 875.0 },
                  { line = { -768.0, 0.0, -460.5, -153.0 }, n = { 0.4455, 0.8953 }, out = 20.0, back = 5.0, z0 = 935.0, z1 = 975.0 } } } },
}
-- their look: the wall's own texture, laid as the wall has it (cm a repeat across and down, where a repeat begins) -
-- "also make the texture the same as the wall", 2026-10-22
-- Shifting Sand Land's pyramid climbed by its own spiral path: its ledges wind round it - the foot's on the west (1.92
-- m), the north (3.84), the east (5.76), the south (7.68), the west again (8.27), then the top (9.6) - with a steep
-- corner between each, a face it slides him off now (Mario 64's, G.SLIDE_AREAS). A flight of steps up each corner
-- ("you cant climb the pyramid because you slide we need a custom path to the top", then "they should follow the spiral
-- path to the top", 2026-10-23), in its own sand brick. Each flight { along "x"/"y", which way (+1/-1), where the face
-- starts up, its height there, steps, rise, run, across from, across to, how deep a block (nil: down to the ledge) };
-- each block's back in the face where the face reaches its top (scene cm, from the level's collision).
G.PYRAMID_FLIGHTS = {
    { "x", 1, -385.0, 192.0, 6, 32.0, 32.0, -560.0, -370.0 },          -- (north-west: the foot to the north ledge)
    { "y", -1, -575.0, 384.0, 6, 32.0, 32.0, 1545.0, 1710.0 },         -- (north-east: to the east ledge)
    { "x", -1, 1535.0, 576.0, 6, 32.0, 33.3, -2290.0, -2120.0, 160.0 }, -- (south-east: to the narrow south ledge)
    { "y", 1, -2112.0, 768.0, 2, 29.5, 30.0, 180.0, 300.0, 60.0 },     -- (south-west: up to the west ledge)
    { "x", 1, 355.0, 827.0, 4, 33.25, 33.0, -1600.0, -1480.0, 0.0 },   -- (the last: up the wall onto the top)
}
function G.pyramid_stairs()
    local boxes = {}
    for _, f in ipairs(G.PYRAMID_FLIGHTS) do
        local axis, dir, a0, z0, n, rise, run, c0, c1, depth = f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8], f[9], f[10]
        for i = 1, n do
            local zt = z0 + rise * i
            local back = a0 + dir * run * i
            local lo, hi = math.min(back - dir * run, back + dir * 2.0), math.max(back - dir * run, back + dir * 2.0)
            local zb = (depth == 0.0) and (z0 - 1.0) or (zt - (depth or 40.0))
            if axis == "x" then boxes[#boxes + 1] = { lo, hi, c0, c1, zb, zt }
            else boxes[#boxes + 1] = { c0, c1, lo, hi, zb, zt } end
        end
    end
    return { boxes = boxes, oz = 960.0, stairs = true,
             look = { texture = "textures__generic__bob_textures.00800.rgba16", u_cm = 193.0, v_cm = 193.0, oy = 0.0, oz = 960.0 } }
end
table.insert(G.EXTRA_HOLDS.ssl, G.pyramid_stairs())
G.HOLD_LOOK = {
    -- (the pillars' own sand brick: a repeat each 96.5 cm across and down, from their tops)
    ssl = { texture = "textures__generic__bob_textures.01000.rgba16", u_cm = 96.5, v_cm = 96.5, oy = 0.0, oz = 768.0 },
    -- (RR's wood, as that wall has it - laid slanting there; a repeat each 4.6 m)
    rr = { texture = "textures__sky__rr_textures.07000.rgba16", u_cm = 460.0, v_cm = 460.0, oy = -2320.0, oz = -837.0 },
    bbh = { texture = "textures__spooky__bbh_textures.03800.rgba16", u_cm = 312.2, v_cm = 626.5, oy = 1766.0, oz = 1228.0 },
    -- (the ice block's: its own ice, drawn solid)
    sl = { texture = "textures__snow__ccm_textures.00800.rgba16", u_cm = 230.0, v_cm = 230.0, oy = 0.0, oz = 1689.38 },
    -- (the cave's own rock, as its pillars have it: stretched, a repeat each 11 m across and 16 m down)
    thi_3 = { texture = "textures__grass__wf_textures.01800.rgba16", u_cm = 1120.0, v_cm = 1600.0, oy = 0.0, oz = 998.0 },
}
-- Signs of the mod's own: a signpost where it stands, read as the level's are (its words a message of the mod's,
-- data/dialogs_extra.lua - tools/race_dialogs.py). By scene: { pos = { x, y, z } scene cm (dropped onto the ground under
-- it), yaw (its face looks along -X turned by it, as the level's signs), dialog }.
G.EXTRA_SIGNS = {
    -- (RR, on the tiled ledge, right before the wall brought down - its arm at x 257 - facing out from it: "in front of
    -- the player place a sign and make it say Tic Tac Needed", then "put the sign in front of me", 2026-11-02)
    rr = { { pos = { 222.0, -5140.0, -1336.0 }, yaw = -3.0, dialog = 9007 } },
}
function G.add_signs(world, name)
    for _, s in ipairs(G.EXTRA_SIGNS[name] or {}) do
        G.add_prop(world, { kind = "prop", actor = "signpost", pos = { s.pos[1], s.pos[2], s.pos[3] }, yaw = s.yaw })
    end
end

function G.add_holds(world, name)
    G.hold_actors = {}
    local list = G.EXTRA_HOLDS[name]
    -- (and the courses joined on in the Bowser run, moved with them: G.join_scenes)
    if G.data and G.data.joined_holds and #G.data.joined_holds > 0 then
        local all = {}
        for _, h in ipairs(list or {}) do all[#all + 1] = h end
        for _, h in ipairs(G.data.joined_holds) do all[#all + 1] = h end
        list = all
    end
    if not list then return 0 end
    local n = 0
    for _, h in ipairs(list) do
        local look = h.look or G.HOLD_LOOK[name]       -- (an entry's own look: the pyramid's stair)
        -- (a wall's ledge { x, out, y0, y1, top, depth, height }, or a set of boxes { boxes = { {x0, x1, y0, y1, z0, z1},
        -- ... }, oz = where its texture starts down }: all of one entry are one actor)
        local boxes = h.boxes
        if not boxes then
            local wx, out, y0, y1, top, dep, ht = h[1], h[2], h[3], h[4], h[5], h[6], h[7]
            boxes = { { wx, wx + out * dep, y0, y1, top - ht, top } }
        end
        local oz = h.oz or (look and look.oz) or 0.0
        local cpos, cidx = {}, {}
        local pos, idx, nrm, uv, col = {}, {}, {}, {}, {}
        for _, bx in ipairs(boxes) do
            n = n + 1
            -- (a box: its corners, and each face both ways round)
            local P
            if bx.line then
                -- (or a ledge along a slanting face: its back `back` in from the line a-b, its front `out` out the way n -
                -- one long ledge where a row of boxes stepping along it gave STORROR only short ones it would not take)
                local L, nx, ny, z0, z1 = bx.line, bx.n[1], bx.n[2], bx.z0, bx.z1
                local ib, ob = -(bx.back or 5.0), bx.out or 20.0
                P = { { L[1] + nx * ib, L[2] + ny * ib, z0 }, { L[3] + nx * ib, L[4] + ny * ib, z0 },
                      { L[3] + nx * ob, L[4] + ny * ob, z0 }, { L[1] + nx * ob, L[2] + ny * ob, z0 },
                      { L[1] + nx * ib, L[2] + ny * ib, z1 }, { L[3] + nx * ib, L[4] + ny * ib, z1 },
                      { L[3] + nx * ob, L[4] + ny * ob, z1 }, { L[1] + nx * ob, L[2] + ny * ob, z1 } }
            else
                local x0, x1, y0, y1, z0, z1 = bx[1], bx[2], bx[3], bx[4], bx[5], bx[6]
                P = { { x0, y0, z0 }, { x1, y0, z0 }, { x1, y1, z0 }, { x0, y1, z0 },
                      { x0, y0, z1 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z1 } }
            end
            -- (each face: its corners, its shade, how its texture lies - "h" across x and y, "xz" or "yz" up the wall's way)
            local faces = { { 1, 2, 3, 4, 0.70, "h" }, { 5, 6, 7, 8, 0.98, "h" }, { 1, 2, 6, 5, 0.85, "xz" },
                            { 4, 3, 7, 8, 0.85, "xz" }, { 2, 3, 7, 6, 0.98, "yz" }, { 1, 4, 8, 5, 0.98, "yz" } }
            local cbase = #cpos // 3
            for _, q in ipairs(P) do cpos[#cpos + 1] = q[1]; cpos[#cpos + 1] = q[2]; cpos[#cpos + 1] = q[3] end
            for _, f in ipairs(faces) do
                local v0 = #pos // 3
                for k = 1, 4 do
                    local q = P[f[k]]
                    pos[#pos + 1] = q[1]; pos[#pos + 1] = q[2]; pos[#pos + 1] = q[3]
                    nrm[#nrm + 1] = 0.0; nrm[#nrm + 1] = 0.0; nrm[#nrm + 1] = 1.0
                    local u, v = 0.0, 0.0
                    if look and look.flat_uv then
                        -- (one patch of the picture all over: a plain part of a wall's - Bowser in the Sky's arrow tile)
                        u, v = look.flat_uv[1], look.flat_uv[2]
                    elseif look then
                        if f[6] == "h" then u, v = (q[2] - look.oy) / look.u_cm, q[1] / look.u_cm
                        elseif f[6] == "xz" then u, v = q[1] / look.u_cm, (oz - q[3]) / look.v_cm
                        else u, v = (q[2] - look.oy) / look.u_cm, (oz - q[3]) / look.v_cm end
                    end
                    uv[#uv + 1] = u; uv[#uv + 1] = v
                    local k2 = f[5]
                    if look then
                        -- (in the wall's own tint, as its vertex colours have it: Bowser in the Sky's yellow - "also color
                        -- them correctly", 2026-11-02)
                        local tn = look.tint or { 1.0, 1.0, 1.0 }
                        col[#col + 1] = k2 * tn[1]; col[#col + 1] = k2 * tn[2]; col[#col + 1] = k2 * tn[3]; col[#col + 1] = 1.0
                    else                                                    -- (no texture: dark wood, its top lightest)
                        col[#col + 1] = k2 * 0.6; col[#col + 1] = k2 * 0.41; col[#col + 1] = k2 * 0.25; col[#col + 1] = 1.0
                    end
                end
                for _, t in ipairs({ { 0, 1, 2 }, { 0, 2, 3 }, { 0, 2, 1 }, { 0, 3, 2 } }) do
                    idx[#idx + 1] = v0 + t[1]; idx[#idx + 1] = v0 + t[2]; idx[#idx + 1] = v0 + t[3]
                end
                local a, b2, c, d = cbase + f[1] - 1, cbase + f[2] - 1, cbase + f[3] - 1, cbase + f[4] - 1
                for _, t in ipairs({ { a, b2, c }, { a, c, d }, { a, c, b2 }, { a, d, c } }) do
                    cidx[#cidx + 1] = t[1]; cidx[#cidx + 1] = t[2]; cidx[#cidx + 1] = t[3]
                end
            end
        end
        local actor = lib.spawn_actor(world, OFFSET, 0.0)
        local pmc = actor and lib.add_pmc(actor)
        if pmc then
            lib.add_collision(pmc, { { source = "hold", pos = cpos, idx = cidx } })
            local vis = lib.add_pmc(actor)
            if vis then
                pcall(function() vis:SetCollisionEnabled(0) end)
                lib.add_sections(world, vis, { { id = 0, layer = "opaque", texture = look and look.texture, nverts = #pos // 3,
                                                 ntris = #idx // 3, pos = pos, nrm = nrm, uv = uv, col = col, idx = idx } })
            end
            G.extras[#G.extras + 1] = actor
            G.hold_actors[#G.hold_actors + 1] = actor
        elseif actor then
            lib.destroy(actor)
        end
    end
    log("holds: %d ledges to climb in %s", n, name)
    return n
end

-- Mario 64's slide surfaces everywhere else (data/slides.lua, exporter/slidex.py; the user, 2026-10-16: "add all the
-- slide surfaces"): the floors that slide Mario (mario_floor_is_slippery) - ice and the very slippery over 10 degrees,
-- the slippery over 20, any other over 38 - taken out of the scene's own collision and given a piece of their own
-- that STORROR cannot stand on (WalkableSlope_Unwalkable), so its own slope slide takes him down them as Mario 64's
-- takes Mario. Returns the scene's collision without them. (G.floor keeps them all: the mod's own floor queries.)
-- (and the big dune by the start, 13-61 degrees up to 9.6 m: "hill next to spawn of ssl not slipper", 2026-10-23)
G.SLIDE_AREAS = { ssl = { { -800.0, -3100.0, 2350.0, 30.0 }, { -4650.0, -2700.0, -2850.0, 3500.0 } } }
function G.quicksand_banks(sd, data, pits)
    local function key(x, y, z) return string.format("%.1f,%.1f,%.1f", x, y, z) end
    local qv = {}
    for _, f in ipairs((data and data.floors) or {}) do
        local tag = tostring(f.tag)
        if tag:find("^quicksand") or tag:find("^sink:deep") then
            local P = f.pos
            for i = 1, #P, 3 do qv[key(P[i], P[i + 1], P[i + 2])] = true end
        end
    end
    local P, I = sd.pos, sd.idx
    local n = #I // 3
    local tv, edges, keep, front = {}, {}, {}, {}
    for t = 0, n - 1 do
        local v = {}
        for k = 1, 3 do local a = I[t * 3 + k] * 3; v[k] = key(P[a + 1], P[a + 2], P[a + 3]) end
        tv[t] = v
        for _, e in ipairs({ { 1, 2 }, { 2, 3 }, { 1, 3 } }) do
            local a, b = v[e[1]], v[e[2]]
            local ek = (a < b) and (a .. "|" .. b) or (b .. "|" .. a)
            edges[ek] = edges[ek] or {}
            table.insert(edges[ek], t)
        end
        local on = (qv[v[1]] and 1 or 0) + (qv[v[2]] and 1 or 0) + (qv[v[3]] and 1 or 0)
        if on >= 2 then keep[t] = true; front[#front + 1] = t end
    end
    while #front > 0 do
        local t = table.remove(front)
        local v = tv[t]
        for _, e in ipairs({ { 1, 2 }, { 2, 3 }, { 1, 3 } }) do
            local a, b = v[e[1]], v[e[2]]
            for _, u in ipairs(edges[(a < b) and (a .. "|" .. b) or (b .. "|" .. a)]) do
                if not keep[u] then keep[u] = true; front[#front + 1] = u end
            end
        end
    end
    -- (and every one in a scene's own slide areas - scene x0, y0, x1, y1: Shifting Sand Land's pyramid, its 45 degree
    -- faces, which Mario slides off - "the pyramid doesnt make the player slide off", 2026-10-23)
    local areas = G.SLIDE_AREAS[G.name or ""]
    for t = 0, n - 1 do
        if areas and not keep[t] then
            local cx, cy = 0.0, 0.0
            for k = 1, 3 do local a = I[t * 3 + k] * 3; cx, cy = cx + P[a + 1] / 3.0, cy + P[a + 2] / 3.0 end
            for _, b in ipairs(areas) do
                if cx > b[1] and cx < b[3] and cy > b[2] and cy < b[4] then keep[t] = "area"; break end
            end
        end
    end
    -- (none in the sand pits: their conveyor takes him in)
    for t = 0, n - 1 do
        if keep[t] and keep[t] ~= "area" and pits then
            local cx, cy = 0.0, 0.0
            for k = 1, 3 do local a = I[t * 3 + k] * 3; cx, cy = cx + P[a + 1] / 3.0, cy + P[a + 2] / 3.0 end
            for _, c in ipairs(pits) do
                if (c[1] - cx) ^ 2 + (c[2] - cy) ^ 2 < 900.0 * 900.0 then keep[t] = nil; break end
            end
        end
    end
    local idx, m = {}, 0
    for t = 0, n - 1 do
        if keep[t] then
            idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = I[t * 3 + 1], I[t * 3 + 2], I[t * 3 + 3]
            m = m + 1
        end
    end
    if m == 0 then return nil end
    return { pos = P, idx = idx, ntris = m }
end
-- the slide floors `sd` less those with their middle in any of `boxes` (G.NO_SLIDE_AT); nil if none are left
function G.slides_outside(sd, boxes)
    if not boxes then return sd end
    local P, I, idx = sd.pos, sd.idx, {}
    for t = 0, #I // 3 - 1 do
        local cx, cy, cz = 0.0, 0.0, 0.0
        for k = 1, 3 do local a = I[t * 3 + k] * 3; cx, cy, cz = cx + P[a + 1] / 3.0, cy + P[a + 2] / 3.0, cz + P[a + 3] / 3.0 end
        local out = false
        for _, b in ipairs(boxes) do
            if cx > b[1] and cx < b[3] and cy > b[2] and cy < b[4] and cz > (b[5] or -1e9) and cz < (b[6] or 1e9) then out = true; break end
        end
        if not out then idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = I[t * 3 + 1], I[t * 3 + 2], I[t * 3 + 3] end
    end
    if #idx == 0 then return nil end
    return { pos = P, idx = idx, ntris = #idx // 3 }
end

-- the slide floors `sd` with their middle in one of `boxes` (G.SLIDE_KEEP, or none) or at least `deg` steep
-- (G.SLIDE_MIN); nil if none
function G.slides_kept(sd, boxes, deg, wet)
    -- (in the water: a corner over one of `wet` - { x0, x1, y0, y1, z } - and under its top, or 40 over it)
    local function in_water(x, y, z)
        for _, r in ipairs(wet or {}) do
            if x >= r.x0 and x <= r.x1 and y >= r.y0 and y <= r.y1 and z < r.z + 40.0 then return true end
        end
        return false
    end
    local P, I, idx = sd.pos, sd.idx, {}
    local lim = math.cos(math.rad(deg))
    for t = 0, #I // 3 - 1 do
        local a, b, c = I[t * 3 + 1] * 3, I[t * 3 + 2] * 3, I[t * 3 + 3] * 3
        local ux, uy, uz = P[b + 1] - P[a + 1], P[b + 2] - P[a + 2], P[b + 3] - P[a + 3]
        local wx, wy, wz = P[c + 1] - P[a + 1], P[c + 2] - P[a + 2], P[c + 3] - P[a + 3]
        local nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
        local l = sqrt(nx * nx + ny * ny + nz * nz)
        local keep = l > 1e-6 and abs(nz) / l <= lim and not (wet and (in_water(P[a + 1], P[a + 2], P[a + 3])
            or in_water(P[b + 1], P[b + 2], P[b + 3]) or in_water(P[c + 1], P[c + 2], P[c + 3])))
        if not keep then
            local cx, cy, cz = (P[a + 1] + P[b + 1] + P[c + 1]) / 3.0, (P[a + 2] + P[b + 2] + P[c + 2]) / 3.0, (P[a + 3] + P[b + 3] + P[c + 3]) / 3.0
            for _, bx in ipairs(boxes or {}) do
                if cx > bx[1] and cx < bx[3] and cy > bx[2] and cy < bx[4] and cz > (bx[5] or -1e9) and cz < (bx[6] or 1e9) then keep = true; break end
            end
        end
        if keep then idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = I[t * 3 + 1], I[t * 3 + 2], I[t * 3 + 3] end
    end
    if #idx == 0 then return nil end
    return { pos = P, idx = idx, ntris = #idx // 3 }
end

-- the slide floors `sd` with their middle in one of `boxes` (G.SLIDE_KEEP); nil if none
function G.slides_within(sd, boxes)
    local P, I, idx = sd.pos, sd.idx, {}
    for t = 0, #I // 3 - 1 do
        local cx, cy, cz = 0.0, 0.0, 0.0
        for k = 1, 3 do local a = I[t * 3 + k] * 3; cx, cy, cz = cx + P[a + 1] / 3.0, cy + P[a + 2] / 3.0, cz + P[a + 3] / 3.0 end
        for _, b in ipairs(boxes) do
            if cx > b[1] and cx < b[3] and cy > b[2] and cy < b[4] and cz > (b[5] or -1e9) and cz < (b[6] or 1e9) then
                idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = I[t * 3 + 1], I[t * 3 + 2], I[t * 3 + 3]
                break
            end
        end
    end
    if #idx == 0 then return nil end
    return { pos = P, idx = idx, ntris = #idx // 3 }
end

-- Pieces of a slide course that are plain floor, not slide: by the collision they came from, the steepest slope stood on
-- there. TTM's slide's exit podium (its warp on top): its sides are 14-degree ramps, and on the slide course's 5-degree
-- footing he slid back off them every time he walked up to its warp - "im sliding right here which needs fixed",
-- 2026-10-27.
G.COURSE_FLOORS = { ["ttm_seg7_collision_podium_warp"] = 45.0 }
function G.course_floors(actor, coll)
    local out, n = {}, 0
    for _, m in ipairs(coll) do
        local deg = m.source and G.COURSE_FLOORS[m.source]
        local fp = deg and lib.add_pmc(actor)
        if fp then
            lib.add_collision(fp, { m })
            pcall(function() fp:SetWalkableSlopeOverride({ WalkableSlopeBehavior = 1, WalkableSlopeAngle = deg }) end)
            n = n + 1
        else
            out[#out + 1] = m
        end
    end
    if n > 0 then log("slide course: %d pieces of plain floor", n) end
    return out
end

function G.add_slides(actor, name, coll)
    G.slides_in = nil
    -- (the slide floors' pieces handed to slide.lua, for a flip to play out on them: M.flip_tick)
    local SL = package.loaded["slide"]
    if SL and SL.set_slide_pmcs then pcall(SL.set_slide_pmcs, {}) end
    if G.SLIDE_COURSES[name] then return G.course_floors(actor, coll) end
    if G.SLIDE_COURSES[name] or (G.NO_SLIDES[name] and not G.SLIDE_BANKS[name] and not G.SLIDE_KEEP[name] and not G.SLIDE_MIN[name]) then return coll end
    if G.slide_data == nil then G.slide_data = lib.load_data("data.slides") or false end
    local sd = G.slide_data and G.slide_data[name]
    if not sd then return coll end
    -- (the slide floors made plain floor by a box with a steepest slope of its own, G.NO_SLIDE_AT's 7th number: taken out
    -- of the scene's collision too, and put back as a piece he can stand on that steep)
    local stand, stand_keys = {}, {}
    for _, b in ipairs(G.NO_SLIDE_AT[name] or {}) do
        if b[7] then
            local w = G.slides_within(sd, { b })
            if w then stand[#stand + 1] = { sd = w, angle = b[7] } end
        end
    end
    if G.NO_SLIDES[name] then
        if G.SLIDE_MIN[name] then
            local wet = nil
            if G.SLIDE_DRY[name] then
                -- (its water boxes, as load_scene makes G.water_rects of them - later than this)
                wet = {}
                for _, b in ipairs((G.data and G.data.water) or {}) do
                    if not b.gas and b.swim ~= false and (b.id or 0) < 50 then
                        wet[#wet + 1] = { x0 = -b.z2, x1 = -b.z1, y0 = b.x1, y1 = b.x2, z = b.y }
                    end
                end
            end
            sd = G.slides_kept(sd, G.SLIDE_KEEP[name], G.SLIDE_MIN[name], wet)
        elseif G.SLIDE_KEEP[name] then sd = G.slides_within(sd, G.SLIDE_KEEP[name])
        else sd = G.quicksand_banks(sd, G.data, G.PITS[name]) end
        if not sd then return coll end
    end
    sd = G.slides_outside(sd, G.NO_SLIDE_AT[name])
    if not sd then
        if #stand == 0 then return coll end
        sd = { pos = {}, idx = {}, ntris = 0 }
    end
    local function key(p, i)
        return string.format("%.2f,%.2f,%.2f", p[i * 3 + 1] + 0.0, p[i * 3 + 2] + 0.0, p[i * 3 + 3] + 0.0)
    end
    local function tri(p, a, b, c)
        local k = { key(p, a), key(p, b), key(p, c) }
        table.sort(k)
        return k[1] .. "|" .. k[2] .. "|" .. k[3]
    end
    local slide = {}
    for t = 0, #sd.idx // 3 - 1 do slide[tri(sd.pos, sd.idx[t * 3 + 1], sd.idx[t * 3 + 2], sd.idx[t * 3 + 3])] = true end
    for _, st in ipairs(stand) do
        local w = st.sd
        for t = 0, #w.idx // 3 - 1 do stand_keys[tri(w.pos, w.idx[t * 3 + 1], w.idx[t * 3 + 2], w.idx[t * 3 + 3])] = true end
    end
    local out, cut = {}, 0
    for _, m in ipairs(coll) do
        local idx = {}
        for t = 0, #m.idx // 3 - 1 do
            local a, b, c = m.idx[t * 3 + 1], m.idx[t * 3 + 2], m.idx[t * 3 + 3]
            local k = tri(m.pos, a, b, c)
            if slide[k] or stand_keys[k] then
                cut = cut + 1
            else
                idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = a, b, c
            end
        end
        if #idx > 0 then out[#out + 1] = { source = m.source, pos = m.pos, idx = idx } end
    end
    -- (the gentle ones - under 10 degrees, CCM's snow from 5: slidex.py VERY_LIM - apart, in a piece he can stand on:
    -- G.slide_walk lets them slide him only on his way down them, so he can still walk up them - "cant reach red coin
    -- here because of slide", 2026-10-18)
    local steep_idx, gentle_idx, gentle = {}, {}, {}
    local P = sd.pos
    for t = 0, #sd.idx // 3 - 1 do
        local a, b, c = sd.idx[t * 3 + 1], sd.idx[t * 3 + 2], sd.idx[t * 3 + 3]
        local ux, uy, uz = P[b * 3 + 1] - P[a * 3 + 1], P[b * 3 + 2] - P[a * 3 + 2], P[b * 3 + 3] - P[a * 3 + 3]
        local wx, wy, wz = P[c * 3 + 1] - P[a * 3 + 1], P[c * 3 + 2] - P[a * 3 + 2], P[c * 3 + 3] - P[a * 3 + 3]
        local nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
        local l = sqrt(nx * nx + ny * ny + nz * nz)
        local into = (l > 1e-6 and (abs(nz) / l > 0.98481 or G.WALKUP_SLIDES[name])) and gentle_idx or steep_idx
        into[#into + 1], into[#into + 2], into[#into + 3] = a, b, c
        if into == gentle_idx then gentle[tri(P, a, b, c)] = true end
    end
    local sp = lib.add_pmc(actor)
    if not sp then return coll end
    if #steep_idx > 0 then lib.add_collision(sp, { { source = "slides", pos = sd.pos, idx = steep_idx } }) end
    pcall(function() sp:SetWalkableSlopeOverride({ WalkableSlopeBehavior = 3, WalkableSlopeAngle = 0.0 }) end)
    -- (and STORROR's own slide surfaces block its "Slide" trace channel, 18: without it its slide never began on them -
    -- he hung in his falling pose and crept down; the user: "the sliding is bugged")
    pcall(function() sp:SetCollisionResponseToChannel(18, 2) end)
    if SL and SL.add_slide_pmc then pcall(SL.add_slide_pmc, sp) end
    if #gentle_idx > 0 then
        local gp = lib.add_pmc(actor)
        if gp then
            lib.add_collision(gp, { { source = "gentle slides", pos = sd.pos, idx = gentle_idx } })
            pcall(function() gp:SetCollisionResponseToChannel(18, 2) end)
            if SL and SL.add_slide_pmc then pcall(SL.add_slide_pmc, gp) end
        end
    end
    for _, st in ipairs(stand) do
        local fp = lib.add_pmc(actor)
        if fp then
            lib.add_collision(fp, { { source = "steep floor", pos = st.sd.pos, idx = st.sd.idx } })
            pcall(function() fp:SetWalkableSlopeOverride({ WalkableSlopeBehavior = 1, WalkableSlopeAngle = st.angle }) end)
            log("slides: %d steep floors to stand on, to %.0f degrees", st.sd.ntris, st.angle)
        end
    end
    G.slides_in, G.slide_keys, G.slide_T, G.slide_on, G.slide_gentle = name, slide, nil, false, gentle
    log("slides: %d slide floors (%d cut from the scene's collision)", sd.ntris, cut)
    return out
end
G.SLIDE_WALK_ANGLE = 5.0
-- Falling and not moving - set down inside a floor, where the engine keeps him falling at full speed with the floor
-- holding him (out of BoB's painting he was left 33 cm into the platform before it: "Im stuck in place?", 2026-10-16;
-- the stuck check above looks at his speed, and his speed was 40 m/s): after 0.8 s, onto the floor over his feet, his
-- fall forgotten (no damage, no ragdoll).
function G.unstick(pawn, dt)
    local mode, l = 1, nil
    pcall(function() mode = pawn.CharacterMovement.MovementMode; l = pawn:K2_GetActorLocation() end)
    local s = G.unstick_st
    if mode ~= 3 or not l or G.warping or G.pending or G.dying or G.carried then G.unstick_st = nil; return end
    -- (6 cm of give: held in a floor he can jitter 2 cm a tick, which kept this from ever coming - RR's maze, 2026-10-29)
    if not s or math.abs(l.X - s.x) > 6.0 or math.abs(l.Y - s.y) > 6.0 or math.abs(l.Z - s.z) > 6.0 then
        G.unstick_st = { x = l.X, y = l.Y, z = l.Z, t = 0.0 }
        return
    end
    s.t = s.t + dt
    if s.t < 0.8 then return end
    G.unstick_st = nil
    local half = G.half or 90.0
    local x, y, feet = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - half
    local fz = floor_z(x, y, feet + 300.0)
    if not fz or feet > fz + 5.0 then return end
    pcall(function()
        local cm = pawn.CharacterMovement
        cm.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
        pcall(function() cm:StopMovementImmediately() end)     -- (its fall speed went with him otherwise: through the floor)
        pawn:K2_TeleportTo({ X = l.X, Y = l.Y, Z = fz + OFFSET.Z + half + 5.0 }, pawn:K2_GetActorRotation())
        pcall(function() cm:StopMovementImmediately() end)
        cm:SetMovementMode(1, 0)
    end)
    G.air, G.peak = false, fz + OFFSET.Z + half
    log("unstuck: %.0f cm into the floor - set on it", fz - feet)
end

-- And never down through a floor of the level (2026-11-02, "just fell through the stage": Bowser in the Sky's red-coin
-- star taken on the walkway past the top, one of STORROR's flips after the dance left him in its flying mode inside the
-- walkway's floor, and put to falling he went out through it, 35 m down and out of the level). Each frame he falls,
-- where his feet were and are: a floor of the level where he is (G.floor - the level's solid faces, not its special
-- floors) that they were on or in, no more than GUARD.inside under its top, and now are further under, come down to by
-- falling - no more than GUARD.across over and GUARD.down down in the frame: not moved there - and he is put back on
-- it, still going across, no longer down. Not swimming, carried, on the way out of a warp or a death, in a cutscene,
-- nor while the fall checks are off (G.no_fall_until: a warp's arrival, a pipe out, the quicksand pulling him under).
G.FLOOR_GUARD = { inside = 60.0, across = 150.0, down = 600.0 }
function G.floor_guard(pawn, dt)
    local l, mode, half = nil, 1, G.half or 90.0
    pcall(function()
        l = pawn:K2_GetActorLocation()
        mode = pawn.CharacterMovement.MovementMode
        half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
    end)
    if not l then return end
    local x, y, feet = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - half
    local last = G.guard_last
    G.guard_last = { x = x, y = y, feet = feet, name = G.name }
    if not last or last.name ~= G.name or mode ~= 3 then return end
    if G.swim or G.carried or G.warping or G.pending or G.dying or G.cutscene or os.clock() < (G.no_fall_until or 0.0) then return end
    if QSAND and QSAND.dying and QSAND.dying() then return end
    local g = G.FLOOR_GUARD
    local dx, dy, dz = x - last.x, y - last.y, feet - last.feet
    if dz >= 0.0 or -dz > g.down or dx * dx + dy * dy > g.across * g.across then return end
    local fz = floor_z(x, y, last.feet + g.inside)
    if not fz or last.feet < fz - g.inside or feet >= fz - g.inside then return end
    pcall(function()
        local cm = pawn.CharacterMovement
        local v = cm.Velocity
        pawn:K2_TeleportTo({ X = l.X, Y = l.Y, Z = fz + OFFSET.Z + half + 2.0 }, pawn:K2_GetActorRotation())
        cm.Velocity = { X = v.X, Y = v.Y, Z = 0.0 }
    end)
    G.guard_last.feet = fz + 2.0
    log("floor guard: down through the floor at (%.0f, %.0f, %.0f) - put back on it", x, y, fz)
end

-- Over a slide floor (G.add_slides) STORROR's walkable angle is the slide courses' 5 degrees: its own slope slide
-- begins only on a floor steeper than that angle (its pieces' Unwalkable alone left him hanging in his falling pose on
-- them - the user: "the sliding is bugged"); off it, back to G.WALK_ANGLE. (x, y, feet: scene cm.) Every tick.
function G.slide_walk(pawn, x, y, feet)
    pcall(G.ice_walk, pawn, x, y, feet)
    -- (and the slopes of the things placed in it - the Dark World's folded stairs: platforms.lua slide_split)
    local plat = PLAT and PLAT.slide_under and PLAT.slide_under(x, y, feet) or false
    local scene = G.slides_in == G.name and G.slide_keys
    if not scene and not plat and not G.slide_plat then G.slide_want = false; return end
    G.slide_plat = plat
    local on, gentle, T = false, false, nil
    if scene then
        local _fz; _fz, T = floor_hit(G.floor, x, y, feet + 60.0)
        if T then
            if T == G.slide_T then
                on, gentle = G.slide_on, G.slide_gent
            else
                local function k(i) return string.format("%.2f,%.2f,%.2f", T[i] + 0.0, T[i + 1] + 0.0, T[i + 2] + 0.0) end
                local a = { k(1), k(4), k(7) }
                table.sort(a)
                local kk = a[1] .. "|" .. a[2] .. "|" .. a[3]
                on = G.slide_keys[kk] == true
                gentle = on and G.slide_gentle ~= nil and G.slide_gentle[kk] == true
            end
        end
        G.slide_T, G.slide_on, G.slide_gent = T, on, gentle
    end
    -- (a gentle one slides him only on his way down it - moving down its fall line, or already in STORROR's slide)
    local slide = on
    if on and gentle then
        slide = false
        pcall(function()
            local ux, uy, uz = T[4] - T[1], T[5] - T[2], T[6] - T[3]
            local wx, wy, wz = T[7] - T[1], T[8] - T[2], T[9] - T[3]
            local nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
            if nz < 0.0 then nx, ny = -nx, -ny end           -- (the normal up: its level part points down the slope)
            local l = sqrt(nx * nx + ny * ny)
            local v = pawn:GetVelocity()
            slide = l > 1e-6 and (v.X * nx + v.Y * ny) / l > 150.0
            if not slide then
                local mt = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
                slide = mt ~= nil and mt:IsValid() and mt:GetFName():ToString():find("FallingSlide") ~= nil
            end
        end)
    end
    G.slide_want = slide or plat
    local want = (slide or plat) and G.SLIDE_WALK_ANGLE or G.WALK_ANGLE
    pcall(function()
        local cm = pawn.CharacterMovement
        if math.abs(cm.WalkableFloorAngle - want) > 0.5 then cm:SetWalkableFloorAngle(want) end
    end)
end

-- On Mario 64's ice (data/ice.lua, exporter/icex.py: its flat SURFACE_ICE floors - Snowman's Land's frozen pond and the
-- ice bully's floe, the ice block's floors, Cool, Cool Mountain's few) he keeps little grip: STORROR's ground friction and
-- braking G.ICE_GRIP of their own, so he skids on when he stops and drifts as he turns, as Mario 64's Mario does
-- (apply_slope_decel: 0.2 of the braking on the very slippery). Off it, his own again. "next player sliding on ice",
-- 2026-10-26. (x, y, feet: scene cm.) Every tick, from G.slide_walk.
G.ICE_GRIP = 0.15
function G.ice_walk(pawn, x, y, feet)
    if G.ice_for ~= G.data then                     -- (each load: its moved pieces' ice moved by then)
        G.ice_for, G.ice_keys = G.data, nil
        if G.ice_data == nil then G.ice_data = lib.load_data("data.ice") or false end
        local ic = G.ice_data and G.ice_data[G.name or ""]
        if ic then
            local P = ic.pos
            local function k(i) return string.format("%.2f,%.2f,%.2f", P[i * 3 + 1] + 0.0, P[i * 3 + 2] + 0.0, P[i * 3 + 3] + 0.0) end
            G.ice_keys = {}
            for t = 0, #ic.idx // 3 - 1 do
                local a = { k(ic.idx[t * 3 + 1]), k(ic.idx[t * 3 + 2]), k(ic.idx[t * 3 + 3]) }
                table.sort(a)
                G.ice_keys[a[1] .. "|" .. a[2] .. "|" .. a[3]] = true
            end
        end
    end
    local on = false
    if G.ice_keys and G.floor then
        local _fz, T = floor_hit(G.floor, x, y, feet + 60.0)
        if T and _fz and feet - _fz < 30.0 then
            local function k(i) return string.format("%.2f,%.2f,%.2f", T[i] + 0.0, T[i + 1] + 0.0, T[i + 2] + 0.0) end
            local a = { k(1), k(4), k(7) }
            table.sort(a)
            on = G.ice_keys[a[1] .. "|" .. a[2] .. "|" .. a[3]] == true
        end
    end
    if on == (G.on_ice or false) then return end
    local cm = pawn.CharacterMovement
    if on then
        G.ice_grip0 = G.ice_grip0 or { cm.GroundFriction, cm.BrakingDecelerationWalking }
        cm.GroundFriction = G.ice_grip0[1] * G.ICE_GRIP
        cm.BrakingDecelerationWalking = G.ice_grip0[2] * G.ICE_GRIP
    elseif G.ice_grip0 then
        cm.GroundFriction, cm.BrakingDecelerationWalking = G.ice_grip0[1], G.ice_grip0[2]
    end
    G.on_ice = on
    log("ice: %s", on and "on it - little grip" or "off it")
end

-- His clothes' cloth (STORROR's Chaos cloth, TorsoCloth and LegsCloth): told of a jump in place, it starts again from
-- its rest shape instead of being dragged after him. STORROR has it notice only a 10 m jump in a frame, and every
-- shorter one the mod makes - a warp's arrival, the shell putting him back on it - dragged the shirt up round his chest
-- ("next we got to fix the shirt it does this sometimes", 2026-10-17): 1.5 m, more than he ever goes in a frame.
G.CLOTH_JUMP = 150.0
function G.cloth_comps(pawn)
    local out = {}
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/ChaosClothAssetEngine.ChaosClothComponent"))) do
            out[#out + 1] = c:get()
        end
    end)
    return out
end
function G.reset_cloth(pawn)
    pawn = pawn or lib.pawn()
    if not pawn then return end
    for _, o in ipairs(G.cloth_comps(pawn)) do pcall(function() o:ForceNextUpdateTeleportAndReset() end) end
    G.reset_hair(pawn)
end
-- The shirt never left ridden up (2026-11-02, "shirt keeps getting inverted we need a failsafe to make sure the shirt
-- never gets like this": STORROR's simulated T-shirt flung up round his chest and caught there, his middle bare - after
-- a ragdoll, a swing of Bowser, a fall). His clothes started again from their shape (G.reset_cloth):
--   seen ridden up: on his feet, the shirt's box (its bounds follow the cloth) its foot SHIRT_GUARD.up over his hips for
--     SHIRT_GUARD.hold s;
--   back on his feet: out of the ragdoll or a hold - mode none to walking (not STORROR's flying: every vault and
--     climb is that, and the shirt would jump at each) - a moment after;
--   standing still: once each time he stops, SHIRT_GUARD.idle s on, where nothing shows the reset.
-- No more than once in SHIRT_GUARD.gap s; each logged.
G.SHIRT_GUARD = { up = 10.0, hold = 0.3, idle = 0.8, settle = 0.25, gap = 1.0 }
-- Sunk into the floor after a way in: a death's arrival brought STORROR's ragdoll with it, still falling (13 m/s), its
-- body through the floor, and he got up where its hips were - 56 cm into the Bowser hallway's floor, stuck: "im glitched
-- in the floor?", 2026-11-03. For SUNK_HOLD s after any arrival (G.arrive), his feet more than 20 cm under the floor at
-- his middle (and not as much as 1.5 m: no floor over his head) - on his feet or falling, not in a ragdoll - put back on it.
G.SUNK_HOLD = 3.0
function G.sunk_guard(pawn, dt)
    if not (G.sunk_until and os.clock() < G.sunk_until and pawn) then return end
    local RG = package.loaded["ragdoll"]
    if RG and RG.active then return end
    local mode = pawn.CharacterMovement.MovementMode
    if mode ~= 1 and mode ~= 3 then return end
    local l = pawn:K2_GetActorLocation()
    local half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
    local z = l.Z - OFFSET.Z
    local feet = z - half
    local f = G.floor_z(l.X - OFFSET.X, l.Y - OFFSET.Y, z + half)
    if f and feet < f - 20.0 and f - feet < 150.0 then
        pawn:K2_SetActorLocation({ X = l.X, Y = l.Y, Z = f + half + 5.0 + OFFSET.Z }, false, {}, true)
        pcall(function() pawn.CharacterMovement:StopMovementImmediately(); pawn.CharacterMovement:SetMovementMode(1, 0) end)
        log("sunk %.0f cm into the floor after arriving: put back on it", f - feet)
    end
end
function G.shirt_guard(pawn, dt)
    local g, st = G.SHIRT_GUARD, G.shirt_st
    if not st or st.addr ~= pawn:GetAddress() then st = { addr = pawn:GetAddress(), mode = 1, high = 0.0, still = 0.0, last = -99.0 }; G.shirt_st = st end
    local now = os.clock()
    local mode, sp = 1, 0.0
    pcall(function()
        mode = pawn.CharacterMovement.MovementMode
        local v = pawn:GetVelocity()
        sp = math.sqrt(v.X * v.X + v.Y * v.Y)
    end)
    local why = nil
    -- (back on his feet)
    if mode == 1 and (st.mode == 0 or st.mode == 6) then st.back = now end
    st.mode = mode
    if st.back and now - st.back >= g.settle then st.back = nil; why = "back on his feet" end
    if mode == 1 then
        -- (standing still)
        if sp < 20.0 then
            st.still = st.still + dt
            if st.still >= g.idle and not st.idle_done then st.idle_done = true; why = why or "standing still" end
        else
            st.still, st.idle_done = 0.0, false
        end
        -- (ridden up: the shirt's foot over his hips)
        st.check = (st.check or 0.0) + dt
        if st.check >= 0.1 then
            local dt2 = st.check
            st.check = 0.0
            local up = nil
            pcall(function()
                local tc = nil
                for _, o in ipairs(G.cloth_comps(pawn)) do if o:GetFName():ToString() == "TorsoCloth" then tc = o end end
                if not tc then return end
                G.KSL = G.KSL or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
                local org, ext, rad = {}, {}, {}
                G.KSL:GetComponentBounds(tc, org, ext, rad)
                local oz, ez = org.Z, ext.Z
                if type(org.get) == "function" then oz = org:get().Z end
                if type(ext.get) == "function" then ez = ext:get().Z end
                local pel = pawn.Mesh:GetSocketLocation(FName("pelvis"))
                -- (a box round the whole of him - the ragdoll's, the cloth asleep - is not the shirt's)
                if ez < 70.0 then up = (oz - ez) - pel.Z end
            end)
            if up and up > g.up then st.high = st.high + dt2 else st.high = 0.0 end
            if st.high >= g.hold then why = string.format("ridden up, its foot %.0f cm over his hips", up or 0.0); st.high = 0.0 end
        end
    else
        st.still, st.idle_done, st.high = 0.0, false, 0.0
    end
    if why and now - st.last >= g.gap then
        st.last = now
        G.reset_cloth(pawn)
        log("shirt guard: %s - his clothes put right", why)
    end
end

-- His body never left turned on his capsule (2026-11-02, "something very wrong with movement after coming out of
-- cutscene. players moving slightly left during jumps": after the ending his mesh stood 13 degrees round from its
-- -90 on the capsule - a turn of STORROR's cut short as the ending moved him, it seems - and STORROR's jumps, moved by
-- their animations in the mesh's own frame, went off 13 degrees to the side). On his feet and nothing of ours turning
-- him on purpose - the ending, a twirl or a cage, a climb, a platform he rides (its turning), the water, a carry - and
-- turned more than MESH_GUARD.tol from -90 (or tipped) for MESH_GUARD.hold s: put straight, and logged.
G.MESH_GUARD = { yaw = -90.0, tol = 2.0, hold = 1.0 }
function G.mesh_guard(pawn, dt)
    local g = G.MESH_GUARD
    local st = G.mesh_st
    if not st or st.addr ~= pawn:GetAddress() then st = { addr = pawn:GetAddress(), off = 0.0 }; G.mesh_st = st end
    local mode, r = 1, nil
    pcall(function() mode = pawn.CharacterMovement.MovementMode; r = pawn.Mesh.RelativeRotation end)
    local TW, CL = package.loaded["twirl"], package.loaded["climb"]
    local busy = mode ~= 1 or not r or G.cutscene or G.carried or G.swim or G.dying or G.pending or G.warping
        or (G.ending_on and G.ending_on()) or (PLAT and PLAT.on)
        or (TW and ((TW.active and TW.active()) or (TW.in_cage and TW.in_cage())))
        or (CL and CL.active and CL.active())
    if busy then st.off = 0.0; return end
    local dy = ((r.Yaw - g.yaw) + 540.0) % 360.0 - 180.0
    if math.abs(dy) <= g.tol and math.abs(r.Pitch) <= g.tol and math.abs(r.Roll) <= g.tol then st.off = 0.0; return end
    st.off = st.off + dt
    if st.off < g.hold then return end
    st.off = 0.0
    pcall(function() pawn.Mesh:K2_SetRelativeRotation({ Pitch = 0.0, Yaw = g.yaw, Roll = 0.0 }, false, {}, true) end)
    log("mesh guard: his body turned %.1f on his capsule (tipped %.1f, %.1f) - put straight", dy, r.Pitch, r.Roll)
end

-- His hair, brows, mustache and beard (STORROR's grooms, their strands simulated as the cloth is) started again from
-- their shape where he is, with his clothes: left as they were, a teleport flung the strands off his head - the hair
-- "moving around and showing bald underneith", 2026-10-27
function G.reset_hair(pawn)
    pawn = pawn or lib.pawn()
    if not pawn then return end
    G.GROOM_CLASS = G.GROOM_CLASS or StaticFindObject("/Script/HairStrandsCore.GroomComponent")    -- (no file local: the file is at Lua's 200)
    if not G.GROOM_CLASS then return end
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(G.GROOM_CLASS)) do
            local o = c:get()
            if o and o:IsValid() then pcall(function() o:ResetSimulation() end) end
        end
    end)
end

local function apply_walkable(pawn)
    for _, o in ipairs(G.cloth_comps(pawn)) do
        pcall(function() if o:GetTeleportDistanceThreshold() > G.CLOTH_JUMP then o:SetTeleportDistanceThreshold(G.CLOTH_JUMP) end end)
    end
    pcall(function()
        local cm = pawn.CharacterMovement
        if G.orig_walk == nil then G.orig_walk = cm.WalkableFloorAngle end
        local want = (G.SLIDE_COURSES[G.name or ""] or G.slide_want) and G.SLIDE_WALK_ANGLE or G.WALK_ANGLE
        if math.abs(cm.WalkableFloorAngle - want) > 0.5 then cm:SetWalkableFloorAngle(want) end
        if G.orig_step == nil then G.orig_step = cm.MaxStepHeight end
        if math.abs(cm.MaxStepHeight - G.STEP_HEIGHT) > 0.5 then cm.MaxStepHeight = G.STEP_HEIGHT end
    end)
end
local function restore_walkable()
    local pawn = lib.pawn()
    if pawn and G.orig_walk ~= nil then
        pcall(function() pawn.CharacterMovement:SetWalkableFloorAngle(G.orig_walk) end)
        if G.orig_step ~= nil then pcall(function() pawn.CharacterMovement.MaxStepHeight = G.orig_step end) end
    end
end
G.restore_walkable = restore_walkable

-- Falls while ragdolled ("the player should take fall damage if they fall a far distance and are ragdolled", 2026-11-01):
-- STORROR's ragdoll - its own bail, a knock-down, ragdoll.lua's - puts his movement at None, so the fall the power meter
-- counts (IsFalling, the tick's HEALTH part) ended the moment he went limp and the rest of the drop was never counted.
-- While limp his hips are followed instead: the highest they were (from the top of the fall he was already in, if he went
-- limp in the air) and how fast they come down. When they stop coming down fast - a landing - the drop since that highest
-- point is Mario 64's check_fall_damage's: past HP.FALL 2 wedges, past HP.FALL_FAR 4, only landing faster than 55 units a
-- frame. Not into water, not on the slide courses, not metal under water, not on the way out of a warp or a death.
-- Returns true while he is limp (the tick's own fall count stands aside).
G.RAGFALL = { land_v = 300.0, fast_v = 55.0 * 0.75 * 30.0 }    -- (cm/s down: a landing under land_v, after over fast_v)
function G.ragdoll_fall(pawn, dt, HP)
    local limp = false
    if RAG and RAG.limp then pcall(function() limp = RAG.limp() and true or false end) end
    if not limp then
        G.ragfall = nil
        return false
    end
    local p = nil
    pcall(function() p = pawn.Mesh:GetSocketLocation(FName("pelvis")) end)
    if not p then return true end
    local r = G.ragfall
    if not r then
        -- (gone limp mid-fall: its top carried over, and the tick's own count of it dropped - one fall, counted once)
        local top = p.Z
        if G.air and G.peak and G.peak > top then top = G.peak end
        -- (and how fast he was coming down then: STORROR's bail at the very landing - limp the frame he hit the ground -
        -- left his hips no fall to be seen, and a jump off RR's top roof onto the course below hurt nothing - "make sure
        -- the player recieves damage when falling from extreme height also that you can take damage in ragdol mode",
        -- 2026-11-02. Coming down fast as he went limp, the next frames' stop is that landing)
        local fast = G.air and (G.fall_vz or 0.0) < -G.RAGFALL.fast_v or false
        G.air = false
        r = { top = top, z = p.Z, fast = fast }
        G.ragfall = r
        return true
    end
    local vz = (dt and dt > 0.0001) and (p.Z - r.z) / dt or 0.0
    r.z = p.Z
    if p.Z > r.top then r.top = p.Z end
    if vz < -G.RAGFALL.fast_v then r.fast = true end
    if r.fast and vz > -G.RAGFALL.land_v then
        local drop = r.top - p.Z
        r.top, r.fast = p.Z, false
        local x, y, z = p.X - OFFSET.X, p.Y - OFFSET.Y, p.Z - OFFSET.Z
        local wtop = G.water_at and G.water_at(x, y)
        local wet = wtop ~= nil and z < wtop + 60.0
        local skip = G.swim or wet or G.SLIDE_COURSES[G.name or ""] or G.dying or G.pending
                     or os.clock() < (G.no_fall_until or 0) or not HP or HP.dead_t
        if drop > HP.FALL and not skip then
            if drop > HP.FALL_FAR then HP.damage(HP.DAMAGE.fall_far, "a very long drop (ragdolled)", true)
            else HP.damage(HP.DAMAGE.fall, "a long drop (ragdolled)", true) end
        elseif drop > HP.FALL then
            log("a long drop (%.0f cm) ragdolled, into water or out of harm's way: no harm", drop)
        end
    end
    return true
end

-- The levels' undersides ("there is no underside to any of the maps please fix that", 2026-11-01): Mario 64 draws each
-- face from one side, and from under a floating island, a ledge or a bridge you saw through it. Each solid face gets its
-- back - the same face turned over, its normal down - on a mesh of its own on the scene's actor: casting no shadow (the
-- floors would shade themselves), not solid, its pictures and lighting the level's own (lib.add_sections). Not where the
-- level already has that face's back (thin walls modelled both ways: the two would fight), nor for decals (they lie on
-- floors), cut-outs or see-through faces (theirs are drawn as they are). Returns how many.
G.UNDERSIDES = true
-- (each back made from a piece of the level kept by that piece's id, G.under_ids[piece id] = the back's section: in the
-- levels drawn room by room - rooms.lua - the backs of a room's walls go with them. Drawn always, they stood about the
-- other rooms: a black wall by Big Boo's Haunt's balcony, its front hidden there, "black wall here?", 2026-11-06.
-- `dry`: that list alone, nothing made)
function G.add_undersides(world, actor, sections, dry)
    if not (G.UNDERSIDES and sections and (dry or (world and actor))) then return dry and {} or 0 end
    local function key(P, a, b, c)
        -- (the face's corners in turn, from the least: the same face whichever corner it starts at, facing its way)
        local k = { string.format("%.1f,%.1f,%.1f", P[a * 3 + 1], P[a * 3 + 2], P[a * 3 + 3]),
                    string.format("%.1f,%.1f,%.1f", P[b * 3 + 1], P[b * 3 + 2], P[b * 3 + 3]),
                    string.format("%.1f,%.1f,%.1f", P[c * 3 + 1], P[c * 3 + 2], P[c * 3 + 3]) }
        local f = 1
        if k[2] < k[f] then f = 2 end
        if k[3] < k[f] then f = 3 end
        return k[f] .. "|" .. k[f % 3 + 1] .. "|" .. k[(f + 1) % 3 + 1]
    end
    -- (every face the level has, whatever its kind, the way it faces)
    local have = {}
    for _, sec in ipairs(sections) do
        local P, I = sec.pos, sec.idx
        if P and I then
            for t = 1, #I - 2, 3 do have[key(P, I[t], I[t + 1], I[t + 2])] = true end
        end
    end
    local backs, n = {}, 0
    for _, sec in ipairs(sections) do
        local P, I, NR, UV, C = sec.pos, sec.idx, sec.nrm, sec.uv, sec.col
        if sec.layer == "opaque" and P and I and UV then
            local pos, nrm, uv, col, idx = {}, {}, {}, {}, {}
            local nv = 0
            for t = 1, #I - 2, 3 do
                local a, b, c = I[t], I[t + 1], I[t + 2]
                local rk = key(P, a, c, b)
                if not have[rk] and not (sec.no_back and sec.no_back[t]) then
                    have[rk] = true
                    for _, v in ipairs({ a, c, b }) do
                        pos[#pos + 1] = P[v * 3 + 1]; pos[#pos + 1] = P[v * 3 + 2]; pos[#pos + 1] = P[v * 3 + 3]
                        if NR then
                            nrm[#nrm + 1] = -NR[v * 3 + 1]; nrm[#nrm + 1] = -NR[v * 3 + 2]; nrm[#nrm + 1] = -NR[v * 3 + 3]
                        else
                            nrm[#nrm + 1] = 0.0; nrm[#nrm + 1] = 0.0; nrm[#nrm + 1] = -1.0
                        end
                        uv[#uv + 1] = UV[v * 2 + 1]; uv[#uv + 1] = UV[v * 2 + 2]
                        if C then
                            col[#col + 1] = C[v * 4 + 1] or 1.0; col[#col + 1] = C[v * 4 + 2] or 1.0
                            col[#col + 1] = C[v * 4 + 3] or 1.0; col[#col + 1] = C[v * 4 + 4] or 1.0
                        else
                            col[#col + 1] = 1.0; col[#col + 1] = 1.0; col[#col + 1] = 1.0; col[#col + 1] = 1.0
                        end
                        idx[#idx + 1] = nv
                        nv = nv + 1
                    end
                    n = n + 1
                end
            end
            if nv > 0 then
                backs[#backs + 1] = { id = #backs, layer = "opaque", texture = sec.texture, unlit = sec.unlit,
                                      nverts = nv, ntris = nv // 3, pos = pos, nrm = nrm, uv = uv, col = col, idx = idx,
                                      src = sec.id }
            end
        end
    end
    local ids = {}
    for _, bk in ipairs(backs) do if bk.src then ids[bk.src] = bk.id end end
    if dry then return ids end
    G.under_ids = ids
    if #backs == 0 then return 0 end
    local pmc = lib.add_pmc(actor)
    if not pmc then return 0 end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    lib.add_sections(world, pmc, backs)
    G.under_pmc = pmc
    return n
end

-- ------------------------------------------------------------ swimming
-- The game has no swimming, so we drive the character ourselves: Flying movement mode while inside an SM64 water
-- box, steering up/down with the camera pitch, floating to the surface when idle, hopping out at banks.
local water_at
function G.water_at(x, y) return water_at(x, y) end

-- Wading: in water too shallow to swim, his feet in it, Mario 64's shallow water - rings round his legs
-- (PARTICLE_SHALLOW_WATER_WAVE: envfx water_waves, a wake as he moves), a little splash and the water's own step sound
-- at each step (PARTICLE_SHALLOW_WATER_SPLASH, SOUND_ACTION_TERRAIN_STEP + SOUND_TERRAIN_WATER), and its jump and
-- landing sounds ("when moving around in water theres no splashes or ripples" "or audio", 2026-10-17). Returns the
-- water's top while he wades, for the rings.
G.wade = { dist = 0.0, ground = false, was = false }
function G.wade_tick(pawn, dt, px, py, pz)
    local w = G.wade
    local x, y = px - OFFSET.X, py - OFFSET.Y
    local feet = pz - OFFSET.Z - (G.half or 90.0)
    local top = (not G.swim) and water_at(x, y) or nil
    if top and not (feet < top - 5.0 and feet > top - 140.0) then top = nil end
    local ground, vz, sp = true, 0.0, 0.0
    pcall(function()
        ground = not pawn.CharacterMovement:IsFalling()
        local v = pawn:GetVelocity()
        vz, sp = v.Z, math.sqrt(v.X * v.X + v.Y * v.Y)
    end)
    -- (in the water at his feet, in the air over it: the jump from it, the landing in it)
    local near = (not G.swim) and water_at(x, y) or nil
    if near and feet < near + 40.0 then
        if w.ground and not ground and vz > 150.0 and w.was then sfx("jump_water") end
        if ground and not w.ground and top then
            sfx("land_water")
            if ENVFX and ENVFX.wade_splash then pcall(ENVFX.wade_splash, x, y, top) end
        end
    end
    w.ground = ground
    w.was = top ~= nil
    if not top then w.dist = 0.0; return nil end
    -- a step each time one of his feet comes down - its lowest point, near the floor - with its splash where that foot
    -- is ("the splash dont follow the footsteps", 2026-10-17: they came every 75 cm, at his middle)
    if ground and sp > 40.0 then
        local floor = feet
        for _, b in ipairs({ "foot_l", "foot_r" }) do
            local f = w[b] or {}
            w[b] = f
            local okf, p = pcall(function() return pawn.Mesh:GetSocketLocation(FName(b)) end)
            if okf and p then
                local h = p.Z - OFFSET.Z - floor
                local dh = f.h and (h - f.h) or 0.0
                -- (as it touches down - its ankle under 6 cm, planted at 3-4 - or, on uneven ground, at its lowest under
                -- 14; measured 2026-10-17: it comes down over half a second, so 12 cm was a sixth of a second early)
                local touch = (f.h and f.h >= 6.0 and h < 6.0) or (f.dh and f.dh < -0.3 and dh >= 0.0 and h < 14.0 and h >= 6.0)
                if touch and os.clock() - (f.at or 0.0) > 0.25 then
                    f.at = os.clock()
                    sfx("step_water", math.min(1.0, 0.45 + sp / 600.0))
                    if ENVFX and ENVFX.wade_splash then pcall(ENVFX.wade_splash, p.X - OFFSET.X, p.Y - OFFSET.Y, top) end
                end
                f.h, f.dh = h, dh
            end
        end
    else
        w.foot_l, w.foot_r = nil, nil
    end
    return top
end
function water_at(x, y)
    for _, b in ipairs(G.water_rects or {}) do
        if x >= b.x0 and x <= b.x1 and y >= b.y0 and y <= b.y1 then return b.z end
    end
    return nil
end

local function stop_swim(pawn, cool)
    if SWIM then pcall(SWIM.stop, pawn) end
    if G.swim and pawn then
        pcall(function() pawn.CharacterMovement:SetMovementMode(3, 0) end)
    end
    G.swim = false
    G.swim_hover = false
    G.swim_cool = cool or 0.5
end
G.stop_swim = function() stop_swim(lib.pawn(), 0) end

-- the vanish-cap walls (data.vanish_walls, apart from the level's collision): solid but while he wears the cap
G.vanish_actor = nil
function G.vanish_walls(on)
    local a = G.vanish_actor
    -- (back solid with him inside one - the cap run out mid-wall - and he was shut in it: first out by the nearer side,
    -- "player gets stuck inside ice wall when cap runs out", 2026-10-26)
    if on and a then pcall(G.vanish_out, lib.pawn()) end
    if a then pcall(function() a:SetActorEnableCollision(on) end) end
end
-- Is he inside a vanish-cap wall? A line straight out from him, at his middle and at his knees, crosses its faces an odd
-- number of times both ways along some line (a slab, a block) - one face alone (a partition, met once one way) does not
-- count. If so, he is put out the nearer way, clear of it by his round and more. True if moved.
function G.vanish_out(pawn)
    local V = G.data and G.data.vanish_walls
    if not (V and V.idx and pawn) then return false end
    local l = pawn:K2_GetActorLocation()
    local x, y, zm = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z
    local half = G.half or 86.0
    local P = V.pos
    -- (the distances along (dx, dy) at height z where its faces are met, each place once - a face drawn both ways, or
    -- two meeting at an edge, met once)
    local function crossings(z, dx, dy)
        local ds = {}
        for t = 0, #V.idx // 3 - 1 do
            local a, b, c = V.idx[t * 3 + 1] * 3, V.idx[t * 3 + 2] * 3, V.idx[t * 3 + 3] * 3
            local e1x, e1y, e1z = P[b + 1] - P[a + 1], P[b + 2] - P[a + 2], P[b + 3] - P[a + 3]
            local e2x, e2y, e2z = P[c + 1] - P[a + 1], P[c + 2] - P[a + 2], P[c + 3] - P[a + 3]
            local px, py, pz = dy * e2z, -dx * e2z, dx * e2y - dy * e2x                  -- (d x e2, d level)
            local det = e1x * px + e1y * py + e1z * pz
            if abs(det) > 1e-9 then
                local tx, ty, tz = x - P[a + 1], y - P[a + 2], z - P[a + 3]
                local u = (tx * px + ty * py + tz * pz) / det
                if u >= 0.0 and u <= 1.0 then
                    local qx, qy, qz = ty * e1z - tz * e1y, tz * e1x - tx * e1z, tx * e1y - ty * e1x
                    local v = (dx * qx + dy * qy) / det
                    if v >= 0.0 and u + v <= 1.0 then
                        local d = (e2x * qx + e2y * qy + e2z * qz) / det
                        if d > 0.0 then
                            local seen = false
                            for _, o in ipairs(ds) do if abs(o - d) < 1.0 then seen = true; break end end
                            if not seen then ds[#ds + 1] = d end
                        end
                    end
                end
            end
        end
        return ds
    end
    for _, z in ipairs({ zm, zm - half + 25.0 }) do
        for k = 0, 3 do
            local ang = k * math.pi / 4.0
            local dx, dy = math.cos(ang), math.sin(ang)
            local fw, bw = crossings(z, dx, dy), crossings(z, -dx, -dy)
            if #fw % 2 == 1 and #bw % 2 == 1 then
                local nf, nb = math.min(table.unpack(fw)), math.min(table.unpack(bw))
                local d, sx, sy = nf, dx, dy
                if nb < nf then d, sx, sy = nb, -dx, -dy end
                local step = d + 45.0
                pawn:K2_SetActorLocation({ X = l.X + sx * step, Y = l.Y + sy * step, Z = l.Z + 5.0 }, false, {}, true)
                log("vanish cap off inside its wall: out %.0f cm", step)
                return true
            end
        end
    end
    return false
end
-- (no power-up cap without his own: Mario's cap taken - Klepto, Ukiki, Mr. Blizzard - or blown off and lying about,
-- the wing, metal and vanish caps are not his to wear: "you shouldnt be able to pickup powerups without the hat",
-- 2026-10-23. False when refused.)
function G.capless()
    local MC = package.loaded["mariocap"]
    return MC ~= nil and MC.on_head ~= nil and not MC.on_head()
end
function G.give_cap(kind)
    if G.capless() then log("cap: no %s cap without his own", tostring(kind)); return false end
    if CAPS then CAPS.give(kind) end
    return true
end
if FLIGHT then FLIGHT.setup({ water = function(x, y) return water_at(x, y) end }) end
-- a Koopa shell out of a box (exclamation_box.inc.c contents 3: LLL's), down on the floor under (x, y, z) - shell.lua
function G.give_shell(x, y, z)
    if not SHELL then return end
    local fz = floor_z(x, y, z) or z
    SHELL.add(x, y, fz)
end

-- Falling by a wall, a ledge in reach: STORROR's own fall forgotten every G.LEDGE_FALL.step cm of it, started again
-- from where he is (a reset, then its StartFallingCallback - the pole jump's way, climb.lua). Its ledge grab counts as a
-- landing from where its fall began - 0.33 s into the grab, its "Landing" - and a catch partway down a long drop was a
-- bail: "when I tried to grab onto a ledge the player ragdolled instead of grabbing the edge", 2026-11-05. Not in the
-- middle of one of its moves (a flip, a dive, the grab itself); Mario 64's fall damage is the mod's own (G.peak).
-- (any fall, not only by a wall: the ledges he catches - Cool, Cool Mountain's by its race's fourth flag - are often
-- no wall of the level's within reach, and none was found all the way down, "still getting ragdolled", 2026-11-05.
-- `walls`: true to ask for a wall within `r` again)
-- (and only past `first` cm down from the top of the fall, his speed kept through it: each hop off a bump on Cool, Cool
-- Mountain's slide was a fall too, reset every 2 m, and the reset stopped him dead - "player keeps getting stopped
-- during slide down mountain", "especially on bridge part", 2026-11-05)
-- (and not within `ground` cm over the floor under him: begun again near the ground, STORROR's landing counted only the
-- last 2 m or so of any drop, and its own stumble, roll or splat off a high one was gone - "player not stumbling after a
-- high fall anymore?", 2026-11-05. Within 9 m - above Mario 64's 8.6 m that knocks him flat anyway (HP.FALL) - the whole
-- drop is STORROR's again; a ledge caught over that high is still no bail.)
-- (and not more often than `every` s, nor with no floor under him at all - off the level, nothing to catch or land on:
-- falling fast it was begun again every 50 ms, each time cutting STORROR's flail of his arms short - "players arms dont
-- flail when dropping from high places", "im not landing just jumping off the map and the flailing is still missing",
-- 2026-11-06)
-- (back to every 2 m and down to 3 m over the floor: once every 0.75 s - 15 m, falling fast - and none in the last 9 m
-- left most catches counting a long drop again, a bail: "I remember you talking about resetting the players falling
-- every 3 meters or something along those lines thats when it works", 2026-11-07. The flail kept going through each by
-- putting it back where it had got to - below)
G.LEDGE_FALL = { step = 200.0, first = 500.0, r = 200.0, up = 150.0, walls = false, after = 0.8, ground = 300.0, every = 0.08 }
-- (one of its moves - a flip, a dive - seen in the fall, G.fall_moves each frame of it: none till that has been gone
-- G.LEDGE_FALL.after s - its fall's own clip showed as the one playing while a flip still played, and the reset cut the
-- flip short: "animation when flipping getting canceled for some reason", 2026-11-05)
-- (and, while G.storror_fall_again is restarting his fall, his arms' flail kept going: STORROR begins its fall's clip
-- from the start again a frame after each restart, and restarted every 0.08 s his pose froze at its first frame -
-- "nope charater just freezes", 2026-11-07. Its clip put back each frame to how long the flail has gone, G.flail_keep)
function G.fall_moves(pawn)
    local mt = nil
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        local m = ai:GetCurrentActiveMontage()
        if m and m:IsValid() then
            mt = m:GetFName():ToString()
            -- (only just after a restart, and only when the clip went back: its own loop - STORROR's in-air clips are
            -- 0.6 s swings of his arms, played round and round - is left alone)
            local k = G.flail_keep
            local now = os.clock()
            if k and now - k.last < 0.6 and mt:find("FallingInAir") then
                k.seen = k.seen or {}
                local pos = ai:Montage_GetPosition(m)
                local s = k.seen[mt]
                if s and now - s.t < 0.3 and now - k.last < 0.2 then
                    local len = 0.0
                    pcall(function() len = m:GetPlayLength() end)
                    local want = s.pos + (now - s.t)
                    if pos < want - 0.1 and want < len - 0.05 then
                        ai:Montage_SetPosition(m, want)
                        if G.FLAIL_KEEP_LOG then lib.log("flail keep: %s %.2f -> %.2f (len %.2f)", mt:sub(1, 40), pos, want, len) end
                        pos = want
                    end
                end
                k.seen[mt] = { pos = pos, t = now }
            end
        end
    end)
    if mt and not (mt:find("Falling") and not mt:find("Slide") and not mt:find("Ragdoll")) then G.fall_move_at = os.clock() end
    return mt
end
function G.storror_fall_again(pawn)
    local L = G.LEDGE_FALL
    if L.every and os.clock() - (G.fall_again_at or -99.0) < L.every then return false end
    local gnd = L.ground
    if gnd then
        local O = package.loaded["lib"].OFFSET
        local l = pawn:K2_GetActorLocation()
        local feet = l.Z - O.Z - (G.half or 90.0)
        local fz = G.floor_z(l.X - O.X, l.Y - O.Y, feet + 40.0)
        -- (with no floor under him at all, begun again all the same: past a ledge over a drop - Cool, Cool Mountain's,
        -- by its race - he was never, and the catch was a bail, "got ragdolled off still", 2026-11-07. The flail is
        -- kept through it now, below)
        if fz and feet - fz < gnd then return false end
    end
    G.fall_again_at = os.clock()
    local mt = G.fall_moves(pawn)
    if mt and not (mt:find("Falling") and not mt:find("Slide") and not mt:find("Ragdoll")) then return false end
    if os.clock() - (G.fall_move_at or -99.0) < (G.LEDGE_FALL.after or 0.8) then return false end
    local cm, v = pawn.CharacterMovement, nil
    pcall(function() local w = cm.Velocity; v = { X = w.X, Y = w.Y, Z = w.Z } end)
    -- (his arms' flail on a long drop - STORROR's MontageFallingInAir - kept going through it: the reset stopped it, and
    -- begun again every 2 m it never came back - "players arms dont flail when dropping from high places", 2026-11-06.
    -- Not flailing yet, this far down: STORROR's own begun, G.FALL_FLAIL)
    local ai, flail, at = nil, nil, 0.0
    pcall(function()
        ai = pawn.Mesh:GetAnimInstance()
        local m = ai:GetCurrentActiveMontage()
        if m and m:IsValid() and m:GetFName():ToString():find("FallingInAir") then flail, at = m, ai:Montage_GetPosition(m) end
    end)
    G.parkour_reset(pawn)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetClass():GetFName():ToString() == "ParkourComponent" then o:StartFallingCallback() end
        end
    end)
    if v then pcall(function() cm.Velocity = v end) end
    -- (how long his arms have flailed, for G.fall_moves to keep STORROR's fall clip there through each restart: from
    -- where its clip had got to at the first restart of this fall)
    local now = os.clock()
    local k = G.flail_keep
    if not k or now - k.last > 0.6 then
        k = { t0 = now - ((flail and at) or 0.0), last = now, seen = {} }
        G.flail_keep = k
    end
    k.last = now
    return true
end
-- (STORROR's arms' flail on a long drop, begun by G.storror_fall_again when none is going)
G.FALL_FLAIL = "/SPP/SPPCharacter/Animation/Falling/InAir/MontageFallingInAir_40_Drew_131024_Falling-003_frames_829-1555.MontageFallingInAir_40_Drew_131024_Falling-003_frames_829-1555"

-- STORROR's parkour state reset (ParkourComponent SimpleReset): forgets where his fall began - a slowed fall's landing
-- (the caps) is then a short one instead of the big drop that knocks him flat. He is not moved.
function G.parkour_reset(pawn)
    pawn = pawn or lib.pawn()
    if not pawn then return end
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetClass():GetFName():ToString() == "ParkourComponent" then o:SimpleReset(pawn) end
        end
    end)
end

-- The Koopa shells lying under water in DDD and JRB (koopa_shell_underwater.inc.c): swum into, he holds it out in front
-- and swims fast for 8 s to the power-up tune (swim.lua S.grab_shell); then it is gone, as it is when he leaves the
-- water. Back with the scene. (They were missing, 2026-10-15.)
-- (music_touch.inc.c: a spot that plays the puzzle jingle the first time he comes within 200 of it - CCM's hidden one.
-- It was missing, 2026-10-15)
G.jingles = {}
local function update_jingles(px, py, pz)
    for i = #G.jingles, 1, -1 do
        local j = G.jingles[i]
        local dx, dy, dz = px - OFFSET.X - j.x, py - OFFSET.Y - j.y, pz - OFFSET.Z - j.z
        if dx * dx + dy * dy + dz * dz < (200.0 * 0.75 + 60.0) ^ 2 then
            table.remove(G.jingles, i)
            sfx("puzzle_jingle")
            log("a hidden spot: the puzzle jingle")
        end
    end
end

G.water_shells = {}
function G.add_water_shell(world, o)
    local data = actor_data("koopa_shell")
    if not data then return end
    local inst = lib.make_instance(world, data, wpos(o.pos), 0.0, 1.0)
    if not inst then return end
    inst.moves = true
    G.extras[#G.extras + 1] = inst.actor
    G.water_shells[#G.water_shells + 1] = { inst = inst, x = o.pos[1], y = o.pos[2], z = o.pos[3], t = 0.0 }
end

local function update_water_shells(dt, pawn, px, py, pz)
    for _, s in ipairs(G.water_shells) do
        if s.held then
            if not (SWIM and SWIM.shell) then
                s.held, s.gone = false, true
                pcall(function() s.inst.actor:SetActorHiddenInGame(true) end)
                sfx("en_shrink")
            else
                -- (out in front of him as he swims)
                local yaw = 0.0
                pcall(function() yaw = pawn:K2_GetActorRotation().Yaw end)
                local r = math.rad(yaw)
                s.t = s.t + dt
                lib.set_pose(s.inst, px + math.cos(r) * 70.0, py + math.sin(r) * 70.0, pz - 30.0, yaw + 90.0)
            end
        elseif not s.gone then
            s.t = s.t + dt
            lib.set_pose(s.inst, s.x + OFFSET.X, s.y + OFFSET.Y, s.z + OFFSET.Z + 6.0 * math.sin(s.t * 2.0), (s.t * 40.0) % 360.0)
            local dx, dy, dz = px - OFFSET.X - s.x, py - OFFSET.Y - s.y, pz - OFFSET.Z - s.z
            if G.swim and SWIM and SWIM.grab_shell and dx * dx + dy * dy + dz * dz < 130.0 * 130.0 then
                s.held = true
                SWIM.grab_shell(8.0)
                if MUSIC and MUSIC.play then pcall(MUSIC.play, "event_powerup", true) end
                G.music_back_at = os.clock() + 8.2
                sfx("star_sound")
                log("koopa shell: grabbed")
            end
        end
    end
end
if CAPS then
    CAPS.setup({
        music_back = function() if MUSIC and G.data then pcall(MUSIC.play, G.data.music) end end,
        vanish_walls = function(on) G.vanish_walls(on) end,
        busy = function() return G.thaw_at ~= nil or G.entry ~= nil or G.cutscene end,
        level = function() return G.name and G.level_of(G.name) end,
        swimming = function() return G.swim end,
        stop_swim = function() stop_swim(lib.pawn(), 0.5) end,
        under_water = function()
            local l = lib.pawn():K2_GetActorLocation()
            local sz = water_at(l.X - OFFSET.X, l.Y - OFFSET.Y)
            return sz ~= nil and l.Z - OFFSET.Z - (G.half or 90.0) < sz
        end,
        above_floor = function()
            local l = lib.pawn():K2_GetActorLocation()
            local x, y, z = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - (G.half or 90.0)
            local fz = floor_z(x, y, z + 20.0)
            return fz and (z - fz) or 1e9
        end,
        parkour_reset = function() G.parkour_reset() end,
        actor_data = actor_data,
    })
end

-- The level's whirlpools and jet streams (apply_water_current): (x, y, z) where he swims, scene cm; the move they
-- give him this tick, scene cm, or nil.
-- (a jet stream's push - a negative strength - twice Mario 64's: at Mario's own top speed the athlete swam into Jolly
-- Roger Bay's against it, to the star it guards - "the vortex that pushes players away from the star isnt strong
-- enough", 2026-10-18; the metal cap still walks him in, the currents never move him under it)
G.JET_STREAM_K = 2.0
function G.water_current(x, y, z, dt)
    local wl = G.data and G.data.whirlpools
    if not (wl and #wl > 0) then return nil end
    local mx, my, mz = y / 0.75, z / 0.75, -x / 0.75
    local sx, sy, sz = 0.0, 0.0, 0.0
    for _, w in ipairs(wl) do
        -- (1: before Bowser 2 is beaten; 2: after: the keys are not kept yet, so never; 3: from act 2)
        local on = w.cond == 0 or w.cond == 1 or (w.cond == 3 and (G.act or 1) >= 2)
        if on then
            local dx, dy, dz = w.pos[1] - mx, w.pos[2] - my, w.pos[3] - mz
            local lat = sqrt(dx * dx + dz * dz)
            local dist = sqrt(lat * lat + dy * dy)
            local pitch = math.atan(dy, lat)
            local yaw = math.atan(dx, dz) - (0x2000 * 1000.0 / (dist + 1000.0)) * math.pi / 32768.0
            local radius = (G.data.level == "ddd" and G.data.area == 2) and 4000.0 or 2000.0
            local st = 0.0
            if w.strength >= 0 then
                if dist >= 26.0 and dist < radius then st = w.strength * (1.0 - dist / radius) end
            elseif dist < 2000.0 then
                st = w.strength * (1.0 - dist / 2000.0) * G.JET_STREAM_K
            end
            sx = sx + st * math.cos(pitch) * math.sin(yaw)
            sy = sy + st * math.sin(pitch)
            sz = sz + st * math.cos(pitch) * math.cos(yaw)
        end
    end
    if sx == 0.0 and sy == 0.0 and sz == 0.0 then return nil end
    local k = 30.0 * dt * 0.75                  -- (Mario 64 units a frame, to cm this tick)
    return -sz * k, sx * k, sy * k
end

-- the rush of the water near a whirlpool or jet stream (SOUND_ENV_WATER)
function G.water_rush(x, y, z)
    local wl = G.data and G.data.whirlpools
    if not wl then return end
    local SFXm = package.loaded["sfx"]
    if not (SFXm and SFXm.hold) then return end
    local mx, my, mz = y / 0.75, z / 0.75, -x / 0.75
    for _, w in ipairs(wl) do
        local dx, dy, dz = w.pos[1] - mx, w.pos[2] - my, w.pos[3] - mz
        local d = sqrt(dx * dx + dy * dy + dz * dz)
        if d < 3000.0 then SFXm.hold("loop_env_water", 1.0 - d / 3000.0) end
    end
end

-- A bank he hops out onto (update_swim): its top at most this far under the water's surface, or up to 20 cm over it.
-- It was 140 - and Snowman's Land's lake, 1.3 m deep, had its own floor taken for a bank: every stroke threw him out of
-- the water, "when pressing a to go forward the player jumps out of the water instead of swimming", 2026-10-26.
G.HOP_BANK_UNDER = 40.0
-- Over a pit: the ground under (x, y) the pit's floor - its death or updraft plane - with nothing of the level's over it.
function G.over_pit(x, y, z)
    if not G.rule then return false end
    local rz, T = floor_hit(G.rule, x, y, z + 60.0)
    if not T or (T[11] ~= "death" and T[11] ~= "vwind") then return false end
    local fz = floor_z(x, y, z + 60.0)
    return not (fz and fz > rz + 5.0)
end
-- (him limp: STORROR's flail, or the mod's own ragdoll with his hips under his capsule - ragdoll.lua M.limp)
function G.swim_limp_check()
    local RG = package.loaded["ragdoll"]
    if RG and RG.limp then return RG.limp() and true or false end
    return false
end
local function update_swim(pawn, dt, loc, vel)
    if G.swim_cool and G.swim_cool > 0 then G.swim_cool = G.swim_cool - dt end
    -- (limp - ragdolled: no swimming, the ragdoll floats him on the top (ragdoll.lua afloat), his capsule after his hips.
    -- Swimming took his capsule as it went under, set it flying and moved it, every frame, against the float - "when
    -- ragdolled in water it glitches tf out instead of showing the player ragdolled on waters surface and floating",
    -- 2026-10-28. Swimming already, it ends, his movement left as STORROR's ragdoll has it, none.)
    if G.swim_limp_check then
        local okl, limp = pcall(G.swim_limp_check)
        if okl and limp then
            if G.swim then
                if SWIM then pcall(SWIM.stop, pawn) end
                pcall(function() pawn.CharacterMovement:SetMovementMode(0, 0) end)
                G.swim, G.swim_hover, G.swim_settle = false, false, nil
                log("swim: ended - he is ragdolled")
            end
            G.swim_cool = math.max(G.swim_cool or 0.0, 0.3)
            return
        end
    end
    local x, y, z = loc.X - OFFSET.X, loc.Y - OFFSET.Y, loc.Z - OFFSET.Z
    local sz = water_at(x, y)
    -- (RENDER 96's waves: he floats on them - water96.lua)
    if sz and package.loaded["water96"] then
        local okh, h = pcall(package.loaded["water96"].height, x, y)
        if okh and h then sz = sz + h end
    end
    -- (no water over a pit: a water box's square runs on out over the drop beside its pool - Tall, Tall Mountain's pond
    -- by the cliff - and there he swam in the air over the abyss and fell out of the level: "just fell through the world
    -- for some reason", 2026-10-26)
    if sz and G.over_pit(x, y, z) then sz = nil end
    local cm = pawn.CharacterMovement
    if not G.swim then
        if not sz or (G.swim_cool or 0) > 0 then return end
        if G.carried then return end                           -- (Hoot has him)
        if CAPS and CAPS.on("metal") then return end          -- (metal: he sinks and walks the bottom, caps.lua)
        local fz = floor_z(x, y, z)
        local depth = fz and (sz - fz) or 1e9
        -- nothing touches the fall until the water is reached. A fast fall makes the character ragdoll (bail) if it
        -- "lands" in the water, so on contact go straight to fly mode (no landing), settle to the surface, then sync.
        local fast_fall = vel and vel.Z < -300
        if depth >= 120 and vel and vel.Z < -600 and z < sz + 60 then
            G.swim = true
            G.swim_hover = true
            pcall(function()
                cm:StopMovementImmediately()
                cm:SetMovementMode(5, 0)
                cm.MaxFlySpeed = 520.0
                cm.BrakingDecelerationFlying = 1500.0
            end)
            log("swim: water contact at speed %.0f", vel.Z)
            local S = package.loaded["sfx"]
            if S then pcall(S.play, "water_plunge") end         -- (Mario 64's plunge into the water)
            if ENVFX and ENVFX.splash then pcall(ENVFX.splash, x, y, sz) end        -- (and its splash)
            -- (and the bubbles of the plunge: act_water_plunge, PARTICLE_PLUNGE_BUBBLE)
            if ENVFX and ENVFX.breath then for _ = 1, 6 do pcall(ENVFX.breath, x, y, sz - 60.0 - math.random() * 80.0, sz) end end
            G.swim_since = os.clock()
            return
        end
        if depth >= 120 and (z < sz - 10 or (fast_fall and z < sz + 60)) then
            G.swim = true
            pcall(function()
                -- kill the fall speed FIRST so the walk switch below doesn't register as a hard landing (fall damage)
                cm:StopMovementImmediately()
                cm:SetMovementMode(1, 0)  -- walk first so the character BP leaves its airborne state, then fly
                cm:SetMovementMode(5, 0)
                cm.MaxFlySpeed = 520.0
                cm.BrakingDecelerationFlying = 1500.0
                cm:StopMovementImmediately()
                -- a fast fall keeps carrying the character down for a moment even with zero velocity, so
                -- catch it at the surface and keep killing its momentum for a short settle period
                local topz = sz - 25 + OFFSET.Z
                if loc.Z > topz then
                    pawn:K2_SetActorLocation({ X = loc.X, Y = loc.Y, Z = topz }, false, {}, true)
                end
            end)
            G.swim_settle = 0.5
            G.swim_since = os.clock()
            log("swim: enter (surface %.0f)", sz)
            local S = package.loaded["sfx"]
            if S and fast_fall then pcall(S.play, "water_plunge") end
            if fast_fall and ENVFX and ENVFX.splash then pcall(ENVFX.splash, x, y, sz) end
            if fast_fall and ENVFX and ENVFX.breath then for _ = 1, 6 do pcall(ENVFX.breath, x, y, sz - 60.0 - math.random() * 80.0, sz) end end
        end
        return
    end
    -- swimming
    local fz = sz and floor_z(x, y, z) or nil
    if not sz or (fz and sz - fz < 85) then
        stop_swim(pawn, 0.5)
        return
    end
    if G.swim_hover then
        pcall(function() cm:StopMovementImmediately() end)
        local topz = sz - 25
        local nz = z - 700.0 * dt
        if nz <= topz then
            G.swim_hover = false
            pcall(function()
                pawn:K2_SetActorLocation({ X = loc.X, Y = loc.Y, Z = topz + OFFSET.Z }, false, {}, true)
                cm:SetMovementMode(3, 0)  -- now, at zero speed, run a fresh fall->land so the character BP leaves its airborne state
                cm:SetMovementMode(1, 0)
                cm:SetMovementMode(5, 0)
                cm:StopMovementImmediately()
            end)
            G.swim_settle = 0.3
            log("swim: hover done")
        else
            pcall(function() pawn:K2_SetActorLocation({ X = loc.X, Y = loc.Y, Z = nz + OFFSET.Z }, false, {}, true) end)
        end
        return
    end
    local mode = cm.MovementMode
    if mode ~= 5 then pcall(function() cm:SetMovementMode(1, 0); cm:SetMovementMode(5, 0) end) end
    if (G.swim_settle or 0) > 0 then
        G.swim_settle = G.swim_settle - dt
        pcall(function() cm:StopMovementImmediately() end)
    end
    local vx, vy = vel.X, vel.Y
    local hs = sqrt(vx * vx + vy * vy)
    -- X at the surface by an edge: climbed out of the water (waterclimb.lua - "next we gotta be able to climb out",
    -- 2026-10-24)
    if z > sz - 60.0 then
        local okw, WC = pcall(require, "waterclimb")
        if okw and WC and WC.try then
            local okc, went = pcall(WC.try, pawn, x, y, z, sz)
            if okc and went then return end
        end
    end
    -- Mario 64's swimming (swim.lua): the stick points his head, the swim button strokes him along
    local top = sz - 25
    -- under, for the power meter: more than a metre below where he floats (Mario 64: 140 units under the
    -- surface); there it runs down and he can drown
    G.swim_under = z < top - 100.0
    local nz, what = z, nil
    if SWIM then
        local ok, r1, r2 = pcall(SWIM.tick, pawn, dt, z, top, fz)
        if ok then nz, what = r1, r2 else log("swim: %s", tostring(r1)) end
    end
    if what == "jump" then
        stop_swim(pawn, 1.0)
        log("swim: jump out")
        return
    end
    if SWIM and SWIM.velocity then          -- (he moves by the swim, not by his own speed)
        vx, vy = SWIM.velocity()
        hs = sqrt(vx * vx + vy * vy)
    end
    -- Flying mode ignores vertical velocity for this character, so move the actor directly
    if math.abs(nz - z) > 0.01 then
        pcall(function() pawn:K2_SetActorLocation({ X = loc.X, Y = loc.Y, Z = nz + OFFSET.Z }, false, {}, false) end)
    end
    -- the water's currents: whirlpools drag him, jet streams push him off (moved, not blocked by walls)
    local cx2, cy2, cz2 = G.water_current(x, y, nz, dt)
    if cx2 and not (CAPS and CAPS.on("metal")) then           -- (metal Mario is not carried off)
        pcall(function()
            local l = pawn:K2_GetActorLocation()
            pawn:K2_SetActorLocation({ X = l.X + cx2, Y = l.Y + cy2, Z = l.Z + cz2 }, true, {}, false)
        end)
    end
    -- and the walls push him off them (G.wall_push) - not while he swims in to an edge to climb out (waterclimb.lua),
    -- nor, at the surface, a bank low enough to hop out onto (below): held 1.5 m off it, he never got near enough to
    local WCm = package.loaded["waterclimb"]
    if (G.WALL_PUSH or 0) > 0 and not (WCm and WCm.active and WCm.active()) then
        local up = nz > sz - 55
        local wx, wy = G.wall_push(x, y, nz, G.WALL_PUSH_R, 80.0, up and sz - 140 or nil, up and sz + 20 or nil)
        if wx then
            local k = G.WALL_PUSH * dt
            pcall(function()
                local l = pawn:K2_GetActorLocation()
                pawn:K2_SetActorLocation({ X = l.X + wx * k, Y = l.Y + wy * k, Z = l.Z }, true, {}, false)
            end)
        end
    end
    -- hop out onto a bank (not straight after landing in the water: the speed he fell in with is not a swim)
    -- (and not while he swims in to an edge to climb it, waterclimb.lua: both at once, the climb steered him in while the
    -- hop threw him onto the bank, and STORROR threw him down - "when climbing out of water its super glitchy",
    -- 2026-11-06)
    if z > sz - 55 and hs > 150 and (G.swim_cool or 0) <= 0 and os.clock() - (G.swim_since or 0) > 0.8
        and not (WCm and WCm.active and WCm.active()) then
        local ax, ay = x + vx / hs * 120, y + vy / hs * 120
        local fa = floor_z(ax, ay, sz + 230)
        -- (only onto banks its 640 up clears - about 20 cm over the water; a taller one it fell short of and dunked him
        -- back, again and again - "player gets stuck in water", 2026-10-24. Those are climbed with X: waterclimb.lua)
        if fa and fa > sz - G.HOP_BANK_UNDER and fa < sz + 20 then
            stop_swim(pawn, 1.2)
            pcall(function() pawn:LaunchCharacter({ X = vx / hs * 280, Y = vy / hs * 280, Z = 640.0 }, false, true) end)
            log("swim: hop out")
        end
    end
end

-- Mario 64's acts: a course is entered for one of its stars, and some of what the level holds is there only for some
-- of them (King Bob-omb waits on his summit only for the first, Whomp's Fortress's tower stands only once the Whomp
-- King is beaten). Mario 64's star select starts on the first star not yet collected; so does this, there being no
-- star select: the act is that star's. Objects carry `acts` (exporter: a bit mask of acts 1-6). The castle and its
-- grounds have no acts.
local ACT_HUBS = { grounds = true, castle = true, castle2 = true, castle3 = true, courtyard = true }
-- Stars past Mario 64's seven, on a course's star select after its six acts: `act` the number it is picked as, `as` the
-- act whose course it is played in, `star` its flag in the save (menu.lua "bob:7"), `name` as the star select shows it
-- (tools/extra_star_names.py draws it). Bob-omb Battlefield's eighth: the race against the user's ghost over the
-- beacons (race.lua) - "an experimental star, a 8th star that has the player racing against my ghost", then "you
-- didn't add a new star, also we have to name these stars", 2026-10-27. Played in act 3's course: no King Bob-omb on
-- the summit, where the race ends, and no Koopa the Quick. G.extra_act: the one being played, else nil.
-- Then the same race on every main course, its 7th star on the star select ("next add a 7th star to every main
-- course", "we are adding ghost racer to all of them", "same way we did before", 2026-11-05): each played in the act
-- with the least in the way - no boss, no other racer (Koopa the Quick, the racing penguin), the level as whole as it
-- gets (Whomp's tower up, Jolly Roger's ship afloat, Bowser's sub gone). The flags, the racer and the line placed as
-- Bob-omb Battlefield's were (race.lua M.place, M.set_line, M.set_racer); its ghost the first run finished there.
G.EXTRA_STARS = {
    bob = { act = 7, as = 3, star = 7, name = "OUTRUN THE GHOST TO THE SUMMIT" },
    wf  = { act = 7, as = 6, star = 7, name = "OUTRUN THE GHOST ROUND THE FORT" },
    jrb = { act = 7, as = 4, star = 7, name = "OUTRUN THE GHOST ROUND THE BAY" },
    ccm = { act = 7, as = 6, star = 7, name = "OUTRUN THE GHOST IN THE SNOW" },
    bbh = { act = 7, as = 4, star = 7, name = "OUTRUN THE GHOST IN THE MANSION" },
    hmc = { act = 7, as = 2, star = 7, name = "OUTRUN THE GHOST IN THE CAVERNS" },
    lll = { act = 7, as = 3, star = 7, name = "OUTRUN THE GHOST OVER THE LAVA" },
    ssl = { act = 7, as = 5, star = 7, name = "OUTRUN THE GHOST IN THE SANDS" },
    ddd = { act = 7, as = 3, star = 7, name = "OUTRUN THE GHOST BY THE DOCKS" },
    sl  = { act = 7, as = 3, star = 7, name = "OUTRUN THE GHOST ON THE ICE" },
    wdw = { act = 7, as = 3, star = 7, name = "OUTRUN THE GHOST AT HIGH TIDE" },
    ttm = { act = 7, as = 3, star = 7, name = "OUTRUN THE GHOST UP THE PEAK" },
    thi = { act = 7, as = 4, star = 7, name = "OUTRUN THE GHOST ON THE ISLAND" },
    -- (played at the clock's own speed, 0, whatever the minute hand said as he jumped in - platforms.lua TTC.sp: "star 7
    -- should only be available in normal clock speed for tiktok clock", then, hidden at the other speeds, "keep it in
    -- there regardless of where the time is", 2026-11-08)
    ttc = { act = 7, as = 1, star = 7, name = "OUTRUN THE GHOST UP THE CLOCK", ttc_speed = 0 },
    rr  = { act = 7, as = 1, star = 7, name = "OUTRUN THE GHOST IN THE CLOUDS" },
}
function G.act_for(name, level)
    G.extra_act = nil
    if G.act_override then return G.act_override end       -- (the ending's credits: each shot's own act)
    if ACT_HUBS[name] then G.course_act = nil; return nil end
    -- (chosen at the star select: kept through all of the course's areas, until he is back in the castle)
    if G.course_act and G.course_act.course == (level or name) then
        local x = G.EXTRA_STARS[G.course_act.course]
        if x and G.course_act.act == x.act then G.extra_act = x; return x.as end
        return G.course_act.act
    end
    local MN = _G.MENU
    if not (MN and MN.has_star) then return 1 end
    local course = level or name
    for i = 0, 5 do
        local got = false
        for _, p in ipairs({ course, course .. "_2", course .. "_3", course .. "_4", name }) do
            if MN.has_star(p .. ":" .. i) then got = true end
        end
        if not got then return i + 1 end
    end
    return 6
end

-- Holes deeper than Mario 64 has them, so that he is seen to fall in ("can you make the entrance hole to bowser level
-- deeper so you actually fall in it?", 2026-10-15): under the castle's trap door to the Dark World was a dark box 1.5 m
-- deep with the warp at its floor, and the screen closed as soon as he dropped through. Its floor goes down to `to`
-- (its dark walls stretched with it, in the picture and the collision), and its warp waits at `warp`, some 6.5 m under
-- the hallway: he falls into the dark, and is still falling when the screen has closed. (Scene units; the data file is
-- read afresh at each load, so this is done to each new copy.)
-- Its walls were untextured (drawn flat grey, whatever their dark vertex colours said: "you have to fix the textures in
-- the hole", 2026-10-15), so the deep shaft is drawn afresh: the castle's stone brick (`tex`) down each wall at the
-- scale of the hallway's own walls, darkening to black a few metres down (`fade`: depth under the hallway -> light),
-- over a black floor; the untextured pit is taken out. (Not the carpet that folds over two of its edges: carried down,
-- the shaft was all red carpet.) The two walls the trap door's panels hang down on are set back `recess` behind the
-- floor's edge: a panel swings down with its thickness behind its hinge, and hung in the wall's own plane, it and the
-- brick fought over the same pixels - brick showed through it ("the trap door isnt going to the edge fully on both
-- sides", 2026-10-15). Corners A B C D in turn (the carpet folds over AB and CD; the panels hang on BC and DA), the light
-- at the top of each wall, the carpet fold's foot.
local PIT_V = 7.9824 / 614.25                     -- (the hallway walls' scale: v per cm down, u per cm along)
local PIT_U = PIT_V
local DEEPEN = {
    castle = { x = 3243.0, y = -4134.75, r = 450.0, bottom = 384.0, to = -2000.0, warp = -100.0, hall = 537.75,
               tex = "textures__inside__inside_castle_textures.03000.rgba16",
               fade = { { 0.0, 1.0 }, { 150.0, 0.5 }, { 400.0, 0.18 }, { 900.0, 0.04 }, { 1600.0, 0.0 } },
               corners = { { 2889.75, -4161.0 }, { 3269.25, -3781.5 }, { 3595.5, -4107.0 }, { 3215.25, -4487.25 } },
               light = { ab = 0.45, bc = 0.65, cd = 0.9, da = 0.65 }, fold = 499.5, recess = 80.0 },
    -- (Rainbow Ride's hole, in the raised step of the castle's top room: 154 cm deep, he landed in it standing, his head
    -- out, and the screen closed as he touched its floor - "make the rainbow ride hole deeper", 2026-10-31. Down to just
    -- over the drawn ceiling of the room under it (1728), 5.2 m under the step's top; its warp floor (data.floors,
    -- `tag`) 3.6 m under it, so he is still falling as the screen closes. Its own brick walls (`cut_tex`, inside its
    -- square of `half`) out, the brick shaft in, lit as they were: the two facing the light bright, the others dim.)
    castle2 = { x = -4414.875, y = -2557.875, r = 115.0, bottom = 2112.0, to = 1745.0, warp = 1905.0, hall = 2265.75,
                tex = "textures__inside__inside_castle_textures.03000.rgba16",
                cut_tex = "textures__inside__inside_castle_textures.03000.rgba16", half = 77.0, tag = "paint:42",
                fade = { { 0.0, 1.0 }, { 120.0, 0.55 }, { 260.0, 0.2 }, { 400.0, 0.05 }, { 500.0, 0.0 } },
                corners = { { -4491.75, -2634.75 }, { -4338.0, -2634.75 }, { -4338.0, -2481.0 }, { -4491.75, -2481.0 } },
                light = { ab = 0.95, bc = 0.95, cd = 0.372, da = 0.372 } },
}

-- the pit's shaft and floor as one section of the hallway's brick (see DEEPEN)
local function pit_shaft(h)
    local pos, uv, col, nrm, idx = {}, {}, {}, {}, {}
    local function light(z)
        local dep, f = h.hall - z, h.fade
        if dep <= f[1][1] then return f[1][2] end
        for i = 2, #f do
            if dep <= f[i][1] then
                local a, b = f[i - 1], f[i]
                return a[2] + (b[2] - a[2]) * (dep - a[1]) / (b[1] - a[1])
            end
        end
        return f[#f][2]
    end
    local function vert(x, y, z, u, v, c, nx, ny, nz)
        pos[#pos + 1], pos[#pos + 2], pos[#pos + 3] = x, y, z
        uv[#uv + 1], uv[#uv + 2] = u, v
        col[#col + 1], col[#col + 2], col[#col + 3], col[#col + 4] = c, c, c, 1.0
        nrm[#nrm + 1], nrm[#nrm + 2], nrm[#nrm + 3] = nx, ny, nz
        return #pos // 3 - 1
    end
    -- (a triangle faces the way the castle's own pit walls did: its edges' cross product against its normal, < 0)
    local function tri(a, b, c, nx, ny, nz)
        local function P(i) return pos[i * 3 + 1], pos[i * 3 + 2], pos[i * 3 + 3] end
        local ax, ay, az = P(a); local bx, by, bz = P(b); local cx, cy, cz = P(c)
        local ux, uy, uz, wx, wy, wz = bx - ax, by - ay, bz - az, cx - ax, cy - ay, cz - az
        local d = (uy * wz - uz * wy) * nx + (uz * wx - ux * wz) * ny + (ux * wy - uy * wx) * nz
        if d > 0 then b, c = c, b end
        idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = a, b, c
    end
    -- (the corners set back along AB, the panels' walls with them)
    local A, B, C, D = h.corners[1], h.corners[2], h.corners[3], h.corners[4]
    local ab = math.sqrt((B[1] - A[1]) ^ 2 + (B[2] - A[2]) ^ 2)
    local ux, uy, r = (B[1] - A[1]) / ab, (B[2] - A[2]) / ab, h.recess or 0.0
    local function back(P, s) return { P[1] + ux * r * s, P[2] + uy * r * s } end
    local A2, B2, C2, D2 = back(A, -1), back(B, 1), back(C, 1), back(D, -1)
    local L = h.light
    -- (each wall: from, to, its top, its light, its brick's u at `from`)
    local walls = {
        { A2, A, h.hall, L.ab, 0.0 }, { A, B, h.fold, L.ab, r * PIT_U }, { B, B2, h.hall, L.ab, (r + ab) * PIT_U },
        { D2, D, h.hall, L.cd, 0.0 }, { D, C, h.fold, L.cd, r * PIT_U }, { C, C2, h.hall, L.cd, (r + ab) * PIT_U },
        { D2, A2, h.hall, L.da, 0.0 }, { B2, C2, h.hall, L.bc, 0.0 },
    }
    -- (a plain square hole - no carpet folded over its edges, no panels hung in it: its four walls from the top)
    if not h.fold then
        walls = { { A, B, h.hall, L.ab, 0.0 }, { B, C, h.hall, L.bc, 0.0 }, { C, D, h.hall, L.cd, 0.0 }, { D, A, h.hall, L.da, 0.0 } }
    end
    for _, w in ipairs(walls) do
        local p, q, top, c0, u0, ud = w[1], w[2], w[3], w[4], w[5], 1.0
        local len = math.sqrt((q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2)
        -- (its normal: level, toward the pit's middle)
        local mx, my = (p[1] + q[1]) / 2, (p[2] + q[2]) / 2
        local nx, ny = -(q[2] - p[2]) / len, (q[1] - p[1]) / len
        if nx * (h.x - mx) + ny * (h.y - my) < 0 then nx, ny = -nx, -ny end
        -- (rows: its top, then where the light steps down, then the floor)
        local zs = { top }
        for _, f in ipairs(h.fade) do
            local z = h.hall - f[1]
            if z < top - 1.0 and z > h.to + 1.0 then zs[#zs + 1] = z end
        end
        zs[#zs + 1] = h.to
        local prev = nil
        for _, z in ipairs(zs) do
            local v, c = (h.hall - z) * PIT_V, c0 * light(z)
            local a = vert(p[1], p[2], z, u0, v, c, nx, ny, 0.0)
            local b = vert(q[1], q[2], z, u0 + ud * len * PIT_U, v, c, nx, ny, 0.0)
            if prev then
                tri(prev[1], prev[2], b, nx, ny, 0.0)
                tri(prev[1], b, a, nx, ny, 0.0)
            end
            prev = { a, b }
        end
    end
    -- the floor, black, facing up
    local f = {}
    for i, w in ipairs({ A2, B2, C2, D2 }) do
        f[i] = vert(w[1], w[2], h.to, w[1] * PIT_U, w[2] * PIT_U, 0.0, 0.0, 0.0, 1.0)
    end
    tri(f[1], f[2], f[3], 0.0, 0.0, 1.0)
    tri(f[1], f[3], f[4], 0.0, 0.0, 1.0)
    return { id = 0, layer = "opaque", texture = h.tex, nverts = #pos // 3, ntris = #idx // 3,
             pos = pos, uv = uv, col = col, nrm = nrm, idx = idx }
end
-- Faces Mario 64 kept out of sight with its rooms - only the room Mario is in drawn - that show here, where the room
-- through a doorway is drawn too, and where every face has a back (G.add_undersides). By scene: faces of a texture in a
-- wall's plane (y, between x and z): `drop` not drawn at all (their solid is the collision's, untouched), `no_back`
-- drawn without a back. The castle: the main staircase's green side walls over the stairway down to the basement - their
-- backs, and a wall inside the staircase that faces the stairway, came through its brick ceiling as triangles: "these
-- triangles on the path downstairs", "its the railing on the stairs uptop pokeing through", 2026-11-01.
-- `cut` = { x0, z0, x1, z1 }: what lies under that line (in x, z) cut off them - the staircase's sides' foot, where it
-- reached down past the brick ceiling of the stairway under it and showed there in its two top corners: "triangles
-- still on the path downstairs", "its just the corner from the stairs sticking through the wall can you just cut it",
-- 2026-11-06. The line is that ceiling's (537, 230) to (-268, -345).
G.STAIR_CEIL = { 537.0, 230.0, -268.0, -345.0 }
G.FACE_FIX = {
    castle = {
        -- (the staircase's sloped side, x -116..345 rising 38..384: drawn again, its front only, as Mario 64 has it -
        -- left out, it took the railing with it: "the railing was missing completely", 2026-11-01)
        { tex = "textures__inside__inside_castle_textures.00000.rgba16", y = -883.0, x = { -120.0, 350.0 }, z = { -1.0, 386.0 }, no_back = true, cut = G.STAIR_CEIL },
        { tex = "textures__inside__inside_castle_textures.00000.rgba16", y = -614.0, x = { -120.0, 350.0 }, z = { -1.0, 386.0 }, no_back = true, cut = G.STAIR_CEIL },
        { tex = "textures__inside__inside_castle_textures.00000.rgba16", y = -921.0, x = { -120.0, 350.0 }, z = { -1.0, 386.0 }, no_back = true, cut = G.STAIR_CEIL },
        { tex = "textures__inside__inside_castle_textures.00000.rgba16", y = -652.0, x = { -120.0, 350.0 }, z = { -1.0, 386.0 }, no_back = true, cut = G.STAIR_CEIL },
    },
}
-- a face of `m` (corners a, b, c) cut along the line `L` (G.FACE_FIX's `cut`): the corners of what lies over it, in turn
-- (new corners on its edges added to the piece, their picture, colour and normal between their ends'); none if all under
function G.cut_face(m, a, b, c, L)
    local P = m.pos
    local function side(v)
        local x, z = P[v * 3 + 1], P[v * 3 + 3]
        return z - (L[2] + (x - L[1]) * (L[4] - L[2]) / (L[3] - L[1]))
    end
    local function between(v, w, k)
        local nv = #P // 3
        for j = 1, 3 do P[#P + 1] = P[v * 3 + j] + (P[w * 3 + j] - P[v * 3 + j]) * k end
        if m.uv then for j = 1, 2 do m.uv[#m.uv + 1] = m.uv[v * 2 + j] + (m.uv[w * 2 + j] - m.uv[v * 2 + j]) * k end end
        if m.col then for j = 1, 4 do m.col[#m.col + 1] = (m.col[v * 4 + j] or 1.0) + ((m.col[w * 4 + j] or 1.0) - (m.col[v * 4 + j] or 1.0)) * k end end
        if m.nrm then for j = 1, 3 do m.nrm[#m.nrm + 1] = m.nrm[v * 3 + j] + (m.nrm[w * 3 + j] - m.nrm[v * 3 + j]) * k end end
        return nv
    end
    local vs = { a, b, c }
    local out = {}
    for i = 1, 3 do
        local v, w = vs[i], vs[i % 3 + 1]
        local sv, sw = side(v), side(w)
        if sv >= 0.0 then out[#out + 1] = v end
        if (sv >= 0.0) ~= (sw >= 0.0) then out[#out + 1] = between(v, w, sv / (sv - sw)) end
    end
    return out, side(a) >= 0.0 and side(b) >= 0.0 and side(c) >= 0.0
end
function G.face_fixes(name, data)
    local list = G.FACE_FIX[name]
    if not (list and data and data.sections) then return end
    local dropped, unbacked, trimmed = 0, 0, 0
    for _, m in ipairs(data.sections) do
        local P, I = m.pos, m.idx
        if P and I then
            local keep, changed = {}, false
            for t = 1, #I - 2, 3 do
                local hit = nil
                for _, f in ipairs(list) do
                    if m.texture == f.tex then
                        local all = true
                        for k = 0, 2 do
                            local v = I[t + k]
                            local x, y, z = P[v * 3 + 1], P[v * 3 + 2], P[v * 3 + 3]
                            if math.abs(y - f.y) > 1.0 or x < f.x[1] or x > f.x[2] or z < f.z[1] or z > f.z[2] then all = false; break end
                        end
                        if all then hit = f; break end
                    end
                end
                local poly, whole = nil, true
                if hit and hit.cut and not hit.drop then poly, whole = G.cut_face(m, I[t], I[t + 1], I[t + 2], hit.cut) end
                if hit and hit.drop then
                    changed, dropped = true, dropped + 1
                elseif not whole then
                    -- (cut: what is left over the line, in triangles round its first corner)
                    changed, trimmed = true, trimmed + 1
                    for k = 2, #poly - 1 do
                        local n = #keep
                        keep[n + 1], keep[n + 2], keep[n + 3] = poly[1], poly[k], poly[k + 1]
                        if hit.no_back then
                            m.no_back = m.no_back or {}
                            m.no_back[n + 1] = true
                        end
                    end
                else
                    local n = #keep
                    keep[n + 1], keep[n + 2], keep[n + 3] = I[t], I[t + 1], I[t + 2]
                    if hit and hit.no_back then
                        m.no_back = m.no_back or {}
                        m.no_back[n + 1] = true                     -- (by its place in the kept list: add_undersides)
                        unbacked = unbacked + 1
                    end
                end
            end
            if changed then m.idx, m.ntris, m.nverts = keep, #keep // 3, #m.pos // 3 end
        end
    end
    log("scene %s: %d faces left undrawn, %d without a back, %d cut (G.FACE_FIX)", name, dropped, unbacked, trimmed)
end

local function deepen(name, data)
    local h = DEEPEN[name]
    if not h then return end
    local n = 0
    local function sink(list)
        for _, m in ipairs(list or {}) do
            local p = m.pos or {}
            for i = 1, #p - 2, 3 do
                local dx, dy = p[i] - h.x, p[i + 1] - h.y
                if dx * dx + dy * dy < h.r * h.r and math.abs(p[i + 2] - h.bottom) < 0.5 then p[i + 2] = h.to; n = n + 1 end
            end
        end
    end
    sink(data.sections)
    sink(data.collision)
    if h.corners then
        -- (the untextured pit out of the picture: every triangle of an untextured section with all three corners in it)
        local cut = 0
        for _, m in ipairs(data.sections or {}) do
            local lined = h.cut_tex ~= nil and m.texture == h.cut_tex
            if (lined or not m.texture) and m.idx then
                local p, keep = m.pos, {}
                local function inside(i)
                    if lined then
                        -- (its own old walls only: inside its square, from its floor - sunk already - to its top)
                        local z = p[i * 3 + 3]
                        return math.abs(p[i * 3 + 1] - h.x) <= h.half + 1.0 and math.abs(p[i * 3 + 2] - h.y) <= h.half + 1.0
                            and z >= h.to - 1.0 and z <= h.hall + 1.0
                    end
                    local dx, dy = p[i * 3 + 1] - h.x, p[i * 3 + 2] - h.y
                    return dx * dx + dy * dy < h.r * h.r
                end
                for t = 1, #m.idx - 2, 3 do
                    local a, b, c = m.idx[t], m.idx[t + 1], m.idx[t + 2]
                    if inside(a) and inside(b) and inside(c) then cut = cut + 1
                    else keep[#keep + 1], keep[#keep + 2], keep[#keep + 3] = a, b, c end
                end
                m.idx, m.ntris = keep, #keep // 3
            end
        end
        local ok, sec = pcall(pit_shaft, h)
        if ok then
            -- (the next section number: the mesh keeps a slot for every number up to the highest)
            local top = -1
            for _, m in ipairs(data.sections) do top = math.max(top, m.id or 0) end
            sec.id = top + 1
            data.sections[#data.sections + 1] = sec
        else log("the pit's shaft failed: %s", tostring(sec)) end
        log("scene %s: the pit's untextured walls out (%d triangles), its brick shaft in (%d)", name, cut,
            ok and sec.ntris or 0)
    end
    for _, o in ipairs(data.objects or {}) do
        if o.kind == "warp" and o.pos then
            local dx, dy = o.pos[1] - h.x, o.pos[2] - h.y
            if dx * dx + dy * dy < h.r * h.r then o.pos[3] = h.warp end
        end
    end
    -- (a warp that is a floor of its own - a painting strip's: down to `warp` too)
    if h.tag then
        for _, f in ipairs(data.floors or {}) do
            if f.tag == h.tag and f.pos then for i = 3, #f.pos, 3 do f.pos[i] = h.warp end end
        end
    end
    log("scene %s: the hole at (%.0f, %.0f) made deeper, %d corners down to %.0f", name, h.x, h.y, n, h.to)
end

-- Warp pipes made deep too ("you need the pipe to go deeper as well", 2026-10-15): the pipe's bottom is cut out (in the
-- picture and the collision, and whatever else lies in its column, trimmed to a square under its walls), its eight
-- inner faces carried on `depth` down with the pipe's own texture at its own scale, lit as each face is at the pipe's
-- foot and darkening to black (`fade`: depth under the foot -> light), with solid walls and a floor at the bottom; its
-- warp waits `trigger` under the foot. Out of it (G.arrive, a death beside it) he starts deep in it.
local DEEP_PIPES = {
    bitdw = { depth = 1500.0, trigger = 450.0, inner = 76.5, hole = 78.0,
              fade = { { 0.0, 1.0 }, { 100.0, 0.6 }, { 300.0, 0.25 }, { 700.0, 0.06 }, { 1200.0, 0.0 } } },
    -- (the Sky's pipe stands on its last stair: the shaft stays inside the stair blocks, above the floor at 4298)
    bits = { depth = 650.0, trigger = 450.0, inner = 76.5, hole = 78.0,
             fade = { { 0.0, 1.0 }, { 100.0, 0.6 }, { 300.0, 0.25 }, { 500.0, 0.06 }, { 640.0, 0.0 } } },
    -- (Tiny-Huge Island's pipes between its islands - "make the pipes in tiny huge deeper", 2026-11-08: down `depth`, or
    -- to 50 cm over the first ground under it (the tiny island's south pipe has the sea bed 3.5 m down), its warp `trigger`
    -- down, or 60 cm over its floor. `drawn`: only a pipe drawn there - its peaks' pipe objects have none)
    thi = { depth = 450.0, trigger = 300.0, inner = 76.5, hole = 78.0, drawn = true,
            fade = { { 0.0, 1.0 }, { 100.0, 0.6 }, { 250.0, 0.3 }, { 400.0, 0.08 }, { 450.0, 0.0 } } },
    thi_2 = { depth = 450.0, trigger = 300.0, inner = 76.5, hole = 78.0, drawn = true,
              fade = { { 0.0, 1.0 }, { 100.0, 0.6 }, { 250.0, 0.3 }, { 400.0, 0.08 }, { 450.0, 0.0 } } },
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
-- (a painting's face kept clear: Mario 64's collision has two SURFACE_DEFAULT triangles over the Lethal Lava Land
-- painting's face, facing both ways, that its walls - pushing out by their own side - let him through; STORROR's solid
-- ones shut him out of the course: "make all the downstairs levels accessable", 2026-10-19. Any triangle lying in an
-- upright painting's face, within it, is taken out of the scene's collision.)
-- (Mario 64's camera-only walls - SURFACE_CAMERA_BOUNDARY: the camera keeps off them, Mario goes through them - were
-- exported solid: over Hazy Maze Cave's pool they made a lid he stood on, and Lethal Lava Land's painting a wall -
-- "make all the downstairs levels accessable", 2026-10-19. Taken out as the scene is read, before anything else
-- touches its collision: data/camera_bounds.lua says which triangles, by source, when its count still matches.)
function G.drop_camera_walls(data)
    if not data or data.cam_dropped then return 0 end
    data.cam_dropped = true
    if G.camera_bounds == nil then G.camera_bounds = lib.load_data("data.camera_bounds") or false end
    local CB = G.camera_bounds
    if not CB then return 0 end
    local n = 0
    for _, c in ipairs(data.collision or {}) do
        local e = c.source and CB[c.source]
        if e and c.idx and #c.idx // 3 == e.total then
            local drop = {}
            for _, r in ipairs(e) do for t = r[1], r[1] + r[2] - 1 do drop[t] = true end end
            local keep = {}
            for t = 0, #c.idx // 3 - 1 do
                if drop[t] then n = n + 1
                else keep[#keep + 1], keep[#keep + 2], keep[#keep + 3] = c.idx[t * 3 + 1], c.idx[t * 3 + 2], c.idx[t * 3 + 3] end
            end
            c.idx, c.ntris = keep, #keep // 3
        end
    end
    if n > 0 then log("camera-only walls: %d triangles left out", n) end
    return n
end

-- (level pieces Mario 64 places as objects that the scene export left undrawn - LLL's two step-and-ramp blocks, whose
-- floors were there with nothing to see: "is there supposed to be a ramp or something here?", 2026-10-19. Drawn as
-- static platforms from data/extra_statics.lua.)
function G.add_extra_statics(name, data)
    -- (and the level's model split room by room, only his room's to be drawn: rooms.lua)
    do local RM = package.loaded["rooms"]; if RM and RM.split_sections then pcall(RM.split_sections, name, data) end end
    if not data or data.extra_added then return 0 end
    data.extra_added = true
    if G.extra_statics == nil then G.extra_statics = lib.load_data("data.extra_statics") or false end
    local x = G.extra_statics and G.extra_statics[name]
    if not x then return 0 end
    data.templates = data.templates or {}
    for k, t in pairs(x.templates or {}) do if not data.templates[k] then data.templates[k] = t end end
    data.objects = data.objects or {}
    for _, o in ipairs(x.objects or {}) do data.objects[#data.objects + 1] = o end
    -- (and paintings the export left out - it takes them from the castle alone: Tall Tall Mountain's slide painting,
    -- its way in, "missing texture actually", 2026-10-27)
    data.paintings = data.paintings or {}
    for _, pt in ipairs(x.paintings or {}) do data.paintings[#data.paintings + 1] = pt end
    log("scene %s: %d level pieces added", name, #(x.objects or {}))
    return #(x.objects or {})
end

-- The ragdoll test area (data/test_area.lua, made by tools/test_area.py: "make a test area, some stairs to fall down a
-- plink machine, and some moving parts to knock the player around", 2026-10-29): its pieces, movers, pipes and warps
-- put into the scene they belong to (the castle grounds) as it is read - templates, objects, warps and nodes alike.
function G.add_test_area(name, data)
    if not data or data.test_added then return 0 end
    data.test_added = true
    if G.test_area == nil then G.test_area = lib.load_data("data.test_area") or false end
    local x = G.test_area and G.test_area[name]
    if not x then return 0 end
    data.templates = data.templates or {}
    for k, t in pairs(x.templates or {}) do data.templates[k] = t end
    data.objects = data.objects or {}
    for _, o in ipairs(x.objects or {}) do data.objects[#data.objects + 1] = o end
    data.warps = data.warps or {}
    for _, w in ipairs(x.warps or {}) do data.warps[#data.warps + 1] = w end
    data.nodes = data.nodes or {}
    for _, n in ipairs(x.nodes or {}) do data.nodes[#data.nodes + 1] = n end
    log("scene %s: the test area added (%d pieces)", name, #(x.objects or {}))
    return #(x.objects or {})
end

-- A hallway of the mod's own, through a wall, a painting at its far end: on the castle's top floor the east wall that
-- Bowser's face hangs on opened where the face was, a long hall run on from the doorway, and the face hung at its end
-- as a painting into Bowser in the Dark World - "right in front of me make a long hallway", "save the painting as
-- well", "in this painting put bowser 1 stage", 2026-11-03. The painting is as every wall painting is: its hollow, its
-- sill at its foot and its warp strip behind it (G.recess_paintings, update_floors), its ripple and the camera going in
-- (painting.lua). Its picture is the face's four tiles made one (textures/painting_bowser_face.png, and Render 96's).
-- The wall's brick round the doorway is kept as it was drawn - its picture, light and turn carried over from the wall's
-- corners - and the hall is in the room's own carpet and brick, lit as the room's wall is, a little darker halfway.
-- (Scene cm. Each stretch of it a piece of its own, its picture repeating no more than the tiled copies hold: M.tiles.)
G.EXTRA_HALLS = {
    castle2 = {
        wall = { x = 2858.25, y0 = -517.5, y1 = 211.5, z0 = 3763.5, z1 = 4377.75 },     -- (the wall opened: one quad)
        face = { x = 2850.75, y0 = -383.25, y1 = 76.5, z0 = 3840.0, z1 = 4300.5 },     -- (Bowser's face on it: taken down)
        door = { y0 = -383.25, y1 = 76.5, z1 = 4300.5 },                               -- (the doorway, up from the floor)
        length = 3000.0,
        step = 500.0,                                                                   -- (cm a stretch)
        floor_tex = "textures__inside__inside_castle_textures.04000.rgba16",
        floor_uv = { u = 11.98, x = 2666.25, v = -2.402, y = -517.5, k = 0.0065 },     -- (the room's carpet, carried on)
        wall_tex = "textures__inside__inside_castle_textures.03000.rgba16",
        wall_k = 0.013,                                                                 -- (the brick's repeats a cm)
        ceil_uv = { u = 7.738, x = 2090.25, v = -1.404, y = -517.5, k = 0.0065 },
        dim = 0.25,                                                                     -- (its light halfway along: this much less)
        tint = { 1.0, 0.86, 0.95 },                                                     -- (the room's pink light on what is lit)
        -- (fire torches on both its walls down to the painting: "put fire torches on the wall down to the painting",
        -- 2026-11-03. Each an iron sconce on the wall, Mario 64's own flame over its cup (enemies.lua bhvFlame: it burns
        -- him, as the basement's do - smaller, `scale`), the basement torches' glow on the wall behind it, and a warm
        -- lamp of its own (lamps.lua). In pairs, `every` cm apart from `first` in; the flame `up` over the floor and
        -- `out` from the wall, as the basement's are.)
        torches = { first = 375.0, every = 750.0, up = 270.0, out = 46.0, scale = 2.0,
                    -- (the basement's glow, its own copy: that one is drawn at a fifth of its alpha, lib.ALPHA_SCALE - on
                    -- the hall's brick it did not show)
                    glow_tex = "torch_glow", glow = { 150.0, 230.0 }, glow_col = { 1.0, 0.62, 0.3, 0.55 },
                    light = { R = 1.0, G = 0.62, B = 0.3, A = 1.0 }, lux = 24.0, reach = 800.0 },
        painting = { name = "bowser_hall", target = "bitdw", id = 60, node = 10, texture = "painting_bowser_face", gauntlet = true,
                     exit_node = 160, exit_bhv = "bhvPaintingDeathWarp" },
        -- (the doorway bolted shut: a riveted iron door in it, two iron bars bolted across it, and three brass padlocks
        -- hanging on steel chains - "put a bolted up entrance, with 3 locks hanging on chains", 2026-11-03. Not there
        -- once the file has `open_flag`.)
        gate = {
            open_flag = "bowser_hall_open",
            -- (its locks' keys: "key:race<n>", the key a floor's big brother gives (race.lua M.FLOORS) - "heres how the
            -- locked bowser doors gonna work with the 3 chains", 2026-11-05. A lock comes off - its chain and padlock -
            -- only when he brings a key to the gate and turns it in it (G.gate_tick: the outermost lock still on, each
            -- key one lock), the file then has `lock_flag`<i>; all three off, the door and bars with them (`open_flag`).
            -- Not as the key is won: "I noticed a lock went missing from the final bowser door before I even removed
            -- it", 2026-11-06)
            keys = "race", lock_flag = "bowser_gate_lock",
            reach = 170.0,                                  -- (cm out from the chains he is near enough to unlock one)
            wall_gap = 10.0,                                -- (cm the unseen wall stands out from the outermost chain on)
            key_scale = 0.5,                                -- (Bowser's key, turned in a padlock: of its door size)
            door_tex = "actors__door__metal_door.rgba16", iron_tex = "actors__door__metal_door_overlay.rgba16",
            steel_tex = "actors__chain_ball__chain_ball.rgba16",
            lock_tex = "actors__treasure_chest__treasure_chest_lock.rgba16",
            lock_side = "actors__treasure_chest__treasure_chest_lock_top.rgba16",
            door_in = 6.0,                                  -- (cm into the doorway)
            -- (the whole of it - door, bars, chains and locks, the unseen wall before them - this far back into the
            -- doorway from the room's wall: "push the whole door back a bit", 2026-11-06. The bars' and chains' ends,
            -- past the doorway's sides, go into the hall's walls)
            back = 120.0,                                   -- ("further", 2026-11-06: 60 first)
            bars = { { 3890.0, 3950.0 }, { 4140.0, 4200.0 } }, bar_over = 45.0, bar_depth = 14.0,
            -- (the chains: each across the doorway from the wall left of it to the wall right of it, its ends at heights
            -- of their own, its padlock somewhere along it pulling it down into a V, turned a little; each a layer further
            -- out than the last, so they cross and lie over one another and over each other's locks - "make the chains
            -- and locks overlap randomly", 2026-11-03. Drawn from `seed`, so the same each time. In front of the
            -- outermost, a wall not drawn: he is kept off them, not walked through them.)
            seed = 29, count = 3,
            chain_out = 26.0,                               -- (cm in front of the wall: the nearest chain)
            layer = 15.0,                                   -- (cm further out each chain)
            ends_z = { 3880.0, 4270.0 },                    -- (its ends' heights, between these)
            lock_u = { 0.3, 0.7 },                          -- (where along it its lock hangs)
            sag = { 50.0, 150.0 },                          -- (cm its lock pulls it down)
            arm_sag = 0.05,                                 -- (each arm's own sag, of its length)
            yaw = 10.0,                                     -- (degrees a lock is turned, either way)
            lowest = 85.0,                                  -- (cm over the floor its lock's link hangs at least)
            link = { 20.0, 10.0, 3.2 },                     -- (a link: outer length, outer width, its wire)
            lock = { 30.0, 26.0, 10.0 },                    -- (a padlock's body: width, height, depth)
            shackle = { 8.0, 10.0, 1.7 },                   -- (its shackle: half its width, its legs, its wire's radius)
            tint = { 1.0, 0.86, 0.95 }, brass = { 1.0, 0.78, 0.36 }, steel = { 0.85, 0.82, 0.88 },
        },
        -- (the wall's corners as the export has them, should they not be found)
        corners = { lb = { uv = { 0.0, 0.967 }, col = { 1.0, 0.728, 0.925 } }, rb = { uv = { 9.451, 0.967 }, col = { 0.838, 0.541, 0.687 } },
                    lt = { uv = { 0.0, -7.018 }, col = { 0.479, 0.309, 0.392 } }, rt = { uv = { 9.451, -7.018 }, col = { 0.318, 0.204, 0.259 } } },
    },
}
function G.add_halls(name, data)
    local h = G.EXTRA_HALLS[name]
    if not (h and data and data.sections) or data.halls_added then return 0 end
    data.halls_added = true
    local W, F, D = h.wall, h.face, h.door
    local X0, X1, ZF = W.x, W.x + h.length, W.z0
    local function on(px, py, pz, x, b)
        return math.abs(px - x) < 1.0 and py > b.y0 - 1.0 and py < b.y1 + 1.0 and pz > b.z0 - 1.0 and pz < b.z1 + 1.0
    end
    -- the wall and the face on it out of the picture - the wall's corners noted first
    local corner, cut = {}, 0
    for _, sec in ipairs(data.sections) do
        local P, idx = sec.pos, sec.idx
        if P and idx then
            local keep = {}
            for t = 1, #idx - 2, 3 do
                local wall, face = true, true
                for k = 0, 2 do
                    local i = idx[t + k] * 3
                    if not on(P[i + 1], P[i + 2], P[i + 3], W.x, W) then wall = false end
                    if not on(P[i + 1], P[i + 2], P[i + 3], F.x, F) then face = false end
                end
                if wall and sec.texture == h.wall_tex and sec.uv and sec.col then
                    for k = 0, 2 do
                        local v = idx[t + k]
                        local key = (math.abs(P[v * 3 + 2] - W.y0) < 1.0 and "l" or "r") .. (math.abs(P[v * 3 + 3] - W.z0) < 1.0 and "b" or "t")
                        if not corner[key] then
                            corner[key] = { uv = { sec.uv[v * 2 + 1], sec.uv[v * 2 + 2] },
                                            col = { sec.col[v * 4 + 1], sec.col[v * 4 + 2], sec.col[v * 4 + 3] },
                                            nrm = sec.nrm and { sec.nrm[v * 3 + 1], sec.nrm[v * 3 + 2], sec.nrm[v * 3 + 3] } or nil }
                        end
                    end
                end
                if wall or face then cut = cut + 1
                else keep[#keep + 1], keep[#keep + 2], keep[#keep + 3] = idx[t], idx[t + 1], idx[t + 2] end
            end
            if #keep < #idx then
                sec.idx, sec.ntris = keep, #keep // 3
                if #keep == 0 then sec.dropped = true end
            end
        end
    end
    local kept = {}
    for _, sec in ipairs(data.sections) do if not sec.dropped then kept[#kept + 1] = sec end end
    data.sections = kept
    for _, k in ipairs({ "lb", "rb", "lt", "rt" }) do
        if not corner[k] then corner[k] = h.corners[k]; log("hall %s: the wall's corner %s not found - the export's taken", name, k) end
    end
    -- and out of the collision
    local ccut = 0
    for _, m in ipairs(data.collision or {}) do
        local P, idx = m.pos, m.idx
        if P and idx then
            local keep = {}
            for t = 1, #idx - 2, 3 do
                local wall = true
                for k = 0, 2 do
                    local i = idx[t + k] * 3
                    if not on(P[i + 1], P[i + 2], P[i + 3], W.x, W) then wall = false; break end
                end
                if wall then ccut = ccut + 1 else keep[#keep + 1], keep[#keep + 2], keep[#keep + 3] = idx[t], idx[t + 1], idx[t + 2] end
            end
            if #keep < #idx then m.idx, m.ntris = keep, #keep // 3 end
        end
    end
    -- the wall at (y, z): its picture, light and turn, between its corners
    local function lerp(a, b, k) return a + (b - a) * k end
    local function wall_at(y, z)
        local s, t = (y - W.y0) / (W.y1 - W.y0), (z - W.z0) / (W.z1 - W.z0)
        local lb, rb, lt, rt = corner.lb, corner.rb, corner.lt, corner.rt
        local function bl(a, b, c, d) return lerp(lerp(a, b, s), lerp(c, d, s), t) end
        local r = { uv = { bl(lb.uv[1], rb.uv[1], lt.uv[1], rt.uv[1]), bl(lb.uv[2], rb.uv[2], lt.uv[2], rt.uv[2]) },
                    col = { bl(lb.col[1], rb.col[1], lt.col[1], rt.col[1]), bl(lb.col[2], rb.col[2], lt.col[2], rt.col[2]),
                            bl(lb.col[3], rb.col[3], lt.col[3], rt.col[3]) } }
        if lb.nrm and rb.nrm and lt.nrm and rt.nrm then
            local n = { bl(lb.nrm[1], rb.nrm[1], lt.nrm[1], rt.nrm[1]), bl(lb.nrm[2], rb.nrm[2], lt.nrm[2], rt.nrm[2]),
                        bl(lb.nrm[3], rb.nrm[3], lt.nrm[3], rt.nrm[3]) }
            local l = math.sqrt(n[1] * n[1] + n[2] * n[2] + n[3] * n[3])
            if l > 1e-6 then r.nrm = { n[1] / l, n[2] / l, n[3] / l } end
        end
        return r
    end
    -- the hall's light along it: as the room's wall, darker halfway
    local function lit(c, x)
        local f = 1.0 - h.dim * math.sin(math.pi * math.max(0.0, math.min(1.0, (x - X0) / h.length)))
        return { c[1] * f, c[2] * f, c[3] * f }
    end
    -- one face: corners A B C D in turn round it ({ p, uv, col, nrm }), seen from N, in the piece `key`
    local drawn, order, cpos, cidx = {}, {}, {}, {}
    local gate_xf = nil                 -- (a chain unlocked: drawn where it fell, through this - the gate's chains below)
    -- (`gate_solid`: the gate's own solid kept apart, gpos/gidx - an actor of its own, G.gate_solid_make, its collision
    -- turned off the moment it opens. In the castle's, built again to open it, the old castle's stayed a few seconds
    -- after: he walked into it as the doors swung, and put back where he stood was pushed out of it through the
    -- doorway - "running into a wall", "still teleporting to the other side of the door", 2026-11-07)
    local gate_solid, gpos, gidx = false, {}, {}
    local function quad(tex, key, vs, N, solid, layer)
        if gate_xf then
            local t = {}
            for k, v in ipairs(vs) do t[k] = { p = gate_xf(v.p), uv = v.uv, col = v.col, nrm = v.nrm and gate_xf(v.nrm, true) } end
            vs, N = t, gate_xf(N, true)
        end
        local A, B, C = vs[1].p, vs[2].p, vs[3].p
        local ux, uy, uz = B[1] - A[1], B[2] - A[2], B[3] - A[3]
        local wx, wy, wz = C[1] - A[1], C[2] - A[2], C[3] - A[3]
        local cx, cy, cz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
        -- (wound as the level's own: (B - A) x (C - A) against N)
        if cx * N[1] + cy * N[2] + cz * N[3] > 0 then vs = { vs[1], vs[4], vs[3], vs[2] } end
        local s = drawn[key]
        if not s then
            s = { layer = layer or "opaque", texture = tex, pos = {}, uv = {}, col = {}, nrm = {}, idx = {} }
            drawn[key] = s
            order[#order + 1] = key
        end
        local sb = #s.pos // 3
        for _, v in ipairs(vs) do
            local n = v.nrm or N
            s.pos[#s.pos + 1], s.pos[#s.pos + 2], s.pos[#s.pos + 3] = v.p[1], v.p[2], v.p[3]
            s.uv[#s.uv + 1], s.uv[#s.uv + 2] = v.uv[1], v.uv[2]
            s.col[#s.col + 1], s.col[#s.col + 2], s.col[#s.col + 3], s.col[#s.col + 4] = v.col[1], v.col[2], v.col[3], v.col[4] or 1.0
            s.nrm[#s.nrm + 1], s.nrm[#s.nrm + 2], s.nrm[#s.nrm + 3] = n[1], n[2], n[3]
        end
        for _, k in ipairs({ 0, 1, 2, 0, 2, 3 }) do s.idx[#s.idx + 1] = sb + k end
        if solid ~= false then
            local P, I = cpos, cidx
            if gate_solid then P, I = gpos, gidx end
            local cb = #P // 3
            for _, v in ipairs(vs) do P[#P + 1], P[#P + 2], P[#P + 3] = v.p[1], v.p[2], v.p[3] end
            for _, k in ipairs({ 0, 1, 2, 0, 2, 3 }) do I[#I + 1] = cb + k end
        end
    end
    local WT, FT = h.wall_tex, h.floor_tex
    -- the wall round the doorway, as it was: left of it, right of it, over it
    local function wall_piece(key, ya, yb, za, zb)
        local vs = {}
        for _, c in ipairs({ { ya, za }, { yb, za }, { yb, zb }, { ya, zb } }) do
            local w = wall_at(c[1], c[2])
            vs[#vs + 1] = { p = { X0, c[1], c[2] }, uv = w.uv, col = w.col, nrm = w.nrm }
        end
        quad(WT, key, vs, { -1.0, 0.0, 0.0 })
    end
    wall_piece("door_l", W.y0, D.y0, W.z0, W.z1)
    wall_piece("door_r", D.y1, W.y1, W.z0, W.z1)
    wall_piece("door_top", D.y0, D.y1, D.z1, W.z1)
    -- the hall, a stretch at a time
    local k, fu, cu = h.wall_k, h.floor_uv, h.ceil_uv
    local ul, ur = wall_at(D.y0, ZF).uv[1], wall_at(D.y1, ZF).uv[1]
    local n = math.max(1, math.ceil(h.length / h.step))
    for i = 1, n do
        local xa, xb = X0 + (i - 1) * h.length / n, X0 + i * h.length / n
        local key = "s" .. i
        -- (its floor and ceiling)
        local f, c = {}, {}
        for _, q in ipairs({ { xa, D.y0 }, { xb, D.y0 }, { xb, D.y1 }, { xa, D.y1 } }) do
            local x, y = q[1], q[2]
            f[#f + 1] = { p = { x, y, ZF }, uv = { fu.u + (x - fu.x) * fu.k, fu.v + (y - fu.y) * fu.k }, col = lit(wall_at(y, ZF).col, x) }
            c[#c + 1] = { p = { x, y, D.z1 }, uv = { cu.u + (x - cu.x) * cu.k, cu.v + (y - cu.y) * cu.k }, col = lit(wall_at(y, D.z1).col, x) }
        end
        quad(FT, "floor_" .. key, f, { 0.0, 0.0, 1.0 })
        quad(WT, "ceil_" .. key, c, { 0.0, 0.0, -1.0 })
        -- (its walls: the brick on round the doorway's sides, its rows as the wall's)
        for _, sd in ipairs({ { "l", D.y0 }, { "r", D.y1 } }) do
            local side, y = sd[1], sd[2]
            local u0 = side == "l" and ul or ur
            local vs = {}
            for _, q in ipairs({ { xa, ZF }, { xb, ZF }, { xb, D.z1 }, { xa, D.z1 } }) do
                local x, z = q[1], q[2]
                local w = wall_at(y, z)
                vs[#vs + 1] = { p = { x, y, z }, uv = { u0 + (x - X0) * k * (side == "l" and -1.0 or 1.0), w.uv[2] }, col = lit(w.col, x) }
            end
            quad(WT, "wall_" .. side .. key, vs, { 0.0, side == "l" and 1.0 or -1.0, 0.0 })
        end
    end
    -- its end: the brick under the painting, up to its foot (the painting's sill, as the castle's own are)
    do
        local vs = {}
        for _, q in ipairs({ { D.y0, ZF }, { D.y1, ZF }, { D.y1, F.z0 }, { D.y0, F.z0 } }) do
            local w = wall_at(q[1], q[2])
            vs[#vs + 1] = { p = { X1, q[1], q[2] }, uv = w.uv, col = w.col }
        end
        quad(WT, "end", vs, { -1.0, 0.0, 0.0 })
    end
    -- (the iron pieces' helpers: their light, a box, a wire swept along a path - none made while `gate_skip`: a lock
    -- whose key is won)
    local gate_skip = false
        local L = { -0.55, -0.35, 0.76 }
        local ll = math.sqrt(L[1] * L[1] + L[2] * L[2] + L[3] * L[3])
        L = { L[1] / ll, L[2] / ll, L[3] / ll }
        -- (lit from in front, above and left, in the room's light)
        local function shade(n, tint)
            local d = math.max(0.0, n[1] * L[1] + n[2] * L[2] + n[3] * L[3])
            local k = 0.42 + 0.68 * d
            local t = h.tint or { 1.0, 1.0, 1.0 }
            return { math.min(1.0, tint[1] * t[1] * k), math.min(1.0, tint[2] * t[2] * k), math.min(1.0, tint[3] * t[3] * k) }
        end
        local function norm(v)
            local l = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
            if l < 1e-9 then return { 0.0, 0.0, 1.0 } end
            return { v[1] / l, v[2] / l, v[3] / l }
        end
        local function crs(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
        -- a box: its middle, half sizes, the picture on its front (-X) face and on the rest, how many cm a repeat (nil:
        -- the picture once on each face)
        local function box(key, c, hx, hy, hz, front_tex, side_tex, tint, solid, per, side_key, yaw)
            if gate_skip then return end
            local cy, sy = math.cos(yaw or 0.0), math.sin(yaw or 0.0)
            local function turn(q) return { q[1] * cy - q[2] * sy, q[1] * sy + q[2] * cy, q[3] } end
            local faces = {
                { { -1, 0, 0 }, { { -hx, -hy, -hz }, { -hx, hy, -hz }, { -hx, hy, hz }, { -hx, -hy, hz } }, true },
                { { 1, 0, 0 }, { { hx, hy, -hz }, { hx, -hy, -hz }, { hx, -hy, hz }, { hx, hy, hz } } },
                { { 0, 0, 1 }, { { -hx, -hy, hz }, { -hx, hy, hz }, { hx, hy, hz }, { hx, -hy, hz } } },
                { { 0, 0, -1 }, { { hx, -hy, -hz }, { hx, hy, -hz }, { -hx, hy, -hz }, { -hx, -hy, -hz } } },
                { { 0, -1, 0 }, { { hx, -hy, -hz }, { -hx, -hy, -hz }, { -hx, -hy, hz }, { hx, -hy, hz } } },
                { { 0, 1, 0 }, { { -hx, hy, -hz }, { hx, hy, -hz }, { hx, hy, hz }, { -hx, hy, hz } } },
            }
            for _, f in ipairs(faces) do
                local N, cs = turn(f[1]), f[2]
                local w = math.sqrt((cs[2][1] - cs[1][1]) ^ 2 + (cs[2][2] - cs[1][2]) ^ 2 + (cs[2][3] - cs[1][3]) ^ 2)
                local hgt = math.sqrt((cs[4][1] - cs[1][1]) ^ 2 + (cs[4][2] - cs[1][2]) ^ 2 + (cs[4][3] - cs[1][3]) ^ 2)
                local su, sv = per and w / per or 1.0, per and hgt / per or 1.0
                local uvs = { { 0.0, sv }, { su, sv }, { su, 0.0 }, { 0.0, 0.0 } }
                local col = shade(N, tint)
                local vs = {}
                for i, q in ipairs(cs) do
                    q = turn(q)
                    vs[i] = { p = { c[1] + q[1], c[2] + q[2], c[3] + q[3] }, uv = uvs[i], col = col, nrm = N }
                end
                if f[3] then quad(front_tex, key, vs, N, solid)
                else quad(side_tex, side_key or key, vs, N, solid) end
            end
        end
        -- a wire swept along a path (a closed ring, or open): round `ax`, the way across the path's plane
        local function sweep(key, tex, path, closed, ax, r, tint)
            if gate_skip then return end
            local M, n = 4, #path
            local rings = {}
            for i = 1, n do
                local a = path[closed and ((i - 2) % n + 1) or math.max(1, i - 1)]
                local b = path[closed and (i % n + 1) or math.min(n, i + 1)]
                local T = norm({ b[1] - a[1], b[2] - a[2], b[3] - a[3] })
                local A = norm(crs(T, ax))
                local ring = {}
                for j = 0, M - 1 do
                    local f = math.pi / 4 + j * math.pi / 2
                    local d = { A[1] * math.cos(f) + ax[1] * math.sin(f), A[2] * math.cos(f) + ax[2] * math.sin(f),
                                A[3] * math.cos(f) + ax[3] * math.sin(f) }
                    ring[j + 1] = { p = { path[i][1] + d[1] * r, path[i][2] + d[2] * r, path[i][3] + d[3] * r }, n = d }
                end
                rings[i] = ring
            end
            for i = 1, closed and n or n - 1 do
                local r1, r2 = rings[i], rings[i % n + 1]
                for j = 1, M do
                    local j2 = j % M + 1
                    local q = { r1[j], r2[j], r2[j2], r1[j2] }
                    local N = norm({ q[1].n[1] + q[2].n[1] + q[3].n[1] + q[4].n[1], q[1].n[2] + q[2].n[2] + q[3].n[2] + q[4].n[2],
                                     q[1].n[3] + q[2].n[3] + q[3].n[3] + q[4].n[3] })
                    local u1, u2 = (j - 1) / M, j / M
                    local uvs = { { u1, 0.45 }, { u1, 0.55 }, { u2, 0.55 }, { u2, 0.45 } }
                    local vs = {}
                    for k = 1, 4 do vs[k] = { p = q[k].p, uv = uvs[k], col = shade(q[k].n, tint), nrm = q[k].n } end
                    quad(tex, key, vs, N, false)
                end
            end
        end
    -- the torches down the hall (h.torches)
    local tc = h.torches
    if tc then
        local okt, errt = pcall(function()

            local n = 0
            local iron = { 0.9, 0.9, 0.9 }
            local IT = (h.gate and h.gate.iron_tex) or "actors__door__metal_door_overlay.rgba16"
            local ST = (h.gate and h.gate.steel_tex) or "actors__chain_ball__chain_ball.rgba16"
            local x = X0 + tc.first
            local zf = ZF + tc.up                       -- (the flame's middle)
            local room_at = { X0 - 300.0, (D.y0 + D.y1) / 2.0, ZF + 50.0 }
            data.objects = data.objects or {}
            data.extra_lamps = data.extra_lamps or {}
            while x < X1 - 100.0 do
                for _, side in ipairs({ { D.y0, 1.0 }, { D.y1, -1.0 } }) do
                    local wy, out = side[1], side[2]           -- (the wall, and the way out of it into the hall)
                    local fy = wy + out * tc.out
                    -- its sconce: a plate on the wall, an arm out, a cup under the flame
                    box("torch_iron", { x, wy + out * 2.0, zf - 50.0 }, 9.0, 2.0, 20.0, IT, IT, iron, false, 30.0)
                    box("torch_iron", { x, (wy + fy) / 2.0, zf - 36.0 }, 3.0, math.abs(fy - wy) / 2.0, 3.0, IT, IT, iron, false, 30.0)
                    box("torch_steel", { x, fy, zf - 29.0 }, 12.0, 12.0, 7.0, ST, ST, { 0.75, 0.7, 0.72 }, false)
                    -- the basement's glow on the wall behind it
                    do
                        local gw, gh = tc.glow[1] / 2.0, tc.glow[2] / 2.0
                        local gy = wy + out * 1.5
                        local c = { tc.glow_col[1], tc.glow_col[2], tc.glow_col[3], tc.glow_col[4] or 1.0 }
                        local N = { 0.0, out, 0.0 }
                        quad(tc.glow_tex, "torch_glow", {
                            { p = { x - gw, gy, zf - gh + 20.0 }, uv = { 0.0, 1.0 }, col = c },
                            { p = { x + gw, gy, zf - gh + 20.0 }, uv = { 1.0, 1.0 }, col = c },
                            { p = { x + gw, gy, zf + gh + 20.0 }, uv = { 1.0, 0.0 }, col = c },
                            { p = { x - gw, gy, zf + gh + 20.0 }, uv = { 0.0, 0.0 }, col = c } }, N, false, "translucent")
                    end
                    -- the flame (Mario 64 units: x = scene y, y = scene z, z = -scene x)
                    data.objects[#data.objects + 1] = { kind = "enemy", type = "bhvFlame", geo = "red_flame_geo", bp = 0, yaw = 0,
                        scale = tc.scale, pos = { x, fy, zf }, sm64 = { fy / 0.75, zf / 0.75, -x / 0.75 }, hall_torch = true }
                    -- and its lamp, a little out from the flame
                    data.extra_lamps[#data.extra_lamps + 1] = { x = x, y = wy + out * (tc.out + 40.0), z = zf + 10.0, I = tc.lux,
                        r = tc.reach, col = tc.light, room_at = room_at }
                    n = n + 1
                end
                x = x + tc.every
            end
            log("hall %s: %d torches down its walls", name, n)
        end)
        if not okt then log("hall %s: the torches failed: %s", name, tostring(errt)) end
    end
    -- the doorway bolted shut (h.gate), unless the file has had it opened
    local gt = h.gate
    local opened = false
    -- (lock i off: unlocked at the gate with a key - G.gate_tick)
    local function key_won(i)
        local MN = _G.MENU
        local ok, won = pcall(function() return gt.lock_flag and MN and MN.has_flag and MN.has_flag(gt.lock_flag .. i) end)
        return ok and won == true
    end
    local unlocked = 0
    if gt then
        local MN = _G.MENU
        pcall(function() opened = MN and MN.has_flag and MN.has_flag(gt.open_flag) or false end)
        for i = 1, gt.count do if key_won(i) then unlocked = unlocked + 1 end end
        if gt.lock_flag and unlocked >= gt.count then opened = true end
    end
    -- (the gate as built, for G.gate_tick: each chain's pieces - a piece each, to be taken out when it is unlocked - and
    -- its padlock's keyhole)
    local gate_live = nil
    if gt and (not opened or (gt.lock_flag and unlocked >= gt.count)) then
        gate_solid = true
        local ok, err = pcall(function()
            -- a chain link: its middle, its long way, its across way
            local Lk = gt.link
            local steel_key = "gate_steel"                  -- (the piece the links go in: each chain its own)
            local chains = {}
            local la, lb, lw = (Lk[1] - Lk[3]) / 2.0, (Lk[2] - Lk[3]) / 2.0, Lk[3] / 2.0
            local pitch = Lk[1] - 2.0 * Lk[3]
            local function link(c, U, V)
                local path = {}
                for i = 0, 9 do
                    local t = i / 10 * 2.0 * math.pi
                    path[#path + 1] = { c[1] + U[1] * la * math.cos(t) + V[1] * lb * math.sin(t),
                                        c[2] + U[2] * la * math.cos(t) + V[2] * lb * math.sin(t),
                                        c[3] + U[3] * la * math.cos(t) + V[3] * lb * math.sin(t) }
                end
                sweep(steel_key, gt.steel_tex, path, true, norm(crs(U, V)), lw, gt.steel)
            end
            local XG = X0 + (gt.back or 0.0)                -- (the gate's own wall: gt.back)
            local XD = XG + gt.door_in
            -- the door: two riveted iron leaves filling the doorway, the right one the left's mirror; their backs too. Each
            -- a piece of its own; open, swung in on its hinge `GATE_OPEN` degrees and left so - not gone: "when the keys
            -- are all used make the metal door slowly open and stay not just disappear", 2026-11-07 (G.gate_open_tick
            -- swings them)
            local ym = (D.y0 + D.y1) / 2.0
            local swing = math.rad(G.GATE_OPEN or 90.0)
            for _, leaf in ipairs({ { D.y0, ym, 0.0, 1.0, D.y0, -1.0, "gate_door_l" }, { ym, D.y1, 1.0, 0.0, D.y1, 1.0, "gate_door_r" } }) do
                local ya, yb, ua, ub, yh, sg, lkey = leaf[1], leaf[2], leaf[3], leaf[4], leaf[5], leaf[6], leaf[7]
                if opened then
                    local ca, sa = math.cos(sg * swing), math.sin(sg * swing)
                    gate_xf = function(p, dir)
                        if dir then return { p[1] * ca - p[2] * sa, p[1] * sa + p[2] * ca, p[3] } end
                        local rx, ry = p[1] - XD, p[2] - yh
                        return { XD + rx * ca - ry * sa, yh + rx * sa + ry * ca, p[3] }
                    end
                end
                local N = { -1.0, 0.0, 0.0 }
                local col = shade(N, { 1.0, 1.0, 1.0 })
                quad(gt.door_tex, lkey, { { p = { XD, ya, ZF }, uv = { ua, 1.0 }, col = col }, { p = { XD, yb, ZF }, uv = { ub, 1.0 }, col = col },
                    { p = { XD, yb, D.z1 }, uv = { ub, 0.0 }, col = col }, { p = { XD, ya, D.z1 }, uv = { ua, 0.0 }, col = col } }, N)
                -- (10 cm of iron: its back, and its edges round it - its sides and top - a thin slice of the picture
                -- along each: two faces half a centimetre apart, "doors are also thin as paper", 2026-11-07)
                local TH = gt.door_thick or 10.0
                local B = { 1.0, 0.0, 0.0 }
                local cb = shade({ -1.0, 0.0, 0.0 }, { 0.6, 0.6, 0.6 })
                quad(gt.door_tex, lkey, { { p = { XD + TH, ya, ZF }, uv = { ua, 1.0 }, col = cb }, { p = { XD + TH, yb, ZF }, uv = { ub, 1.0 }, col = cb },
                    { p = { XD + TH, yb, D.z1 }, uv = { ub, 0.0 }, col = cb }, { p = { XD + TH, ya, D.z1 }, uv = { ua, 0.0 }, col = cb } }, B, false)
                local eu = 0.04
                local ce = shade({ 0.0, 1.0, 0.0 }, { 0.75, 0.75, 0.75 })
                for _, ed in ipairs({ { ya, { 0.0, -1.0, 0.0 } }, { yb, { 0.0, 1.0, 0.0 } } }) do
                    local y = ed[1]
                    quad(gt.door_tex, lkey, { { p = { XD, y, ZF }, uv = { 0.0, 1.0 }, col = ce }, { p = { XD + TH, y, ZF }, uv = { eu, 1.0 }, col = ce },
                        { p = { XD + TH, y, D.z1 }, uv = { eu, 0.0 }, col = ce }, { p = { XD, y, D.z1 }, uv = { 0.0, 0.0 }, col = ce } }, ed[2], false)
                end
                local ct = shade({ 0.0, 0.0, 1.0 }, { 0.75, 0.75, 0.75 })
                quad(gt.door_tex, lkey, { { p = { XD, ya, D.z1 }, uv = { ua, 0.0 }, col = ct }, { p = { XD, yb, D.z1 }, uv = { ub, 0.0 }, col = ct },
                    { p = { XD + TH, yb, D.z1 }, uv = { ub, eu }, col = ct }, { p = { XD + TH, ya, D.z1 }, uv = { ua, eu }, col = ct } }, { 0.0, 0.0, 1.0 }, false)
                gate_xf = nil
            end
            -- the bars across it, bolted into the wall either side and at the middle
            local hx = gt.bar_depth / 2.0
            local bx = XG - 2.0 - hx
            local iron = { 0.9, 0.9, 0.9 }
            for _, band in ipairs(opened and {} or gt.bars) do
                local zc, hz = (band[1] + band[2]) / 2.0, (band[2] - band[1]) / 2.0
                local y0, y1 = D.y0 - gt.bar_over, D.y1 + gt.bar_over
                box("gate_bar", { bx, (y0 + y1) / 2.0, zc }, hx, (y1 - y0) / 2.0, hz, gt.iron_tex, gt.iron_tex, iron, true, 80.0)
                for _, y in ipairs({ y0 + gt.bar_over * 0.5, ym, y1 - gt.bar_over * 0.5 }) do
                    for _, dz in ipairs({ -hz * 0.5, hz * 0.5 }) do
                        box("gate_bar_bolt", { bx - hx - 2.5, y, zc + dz }, 2.5, 4.5, 4.5, gt.steel_tex, gt.steel_tex, gt.steel, false)
                    end
                end
            end
            -- the chains (see gate.seed): each from the wall left of the doorway to the wall right of it, a layer further
            -- out than the last
            local seed = gt.seed
            local function rnd(lo, hi)
                seed = (seed * 1103515245 + 12345) % 2147483648
                return lo + (hi - lo) * seed / 2147483648
            end
            local XAX, ZAX = { 1.0, 0.0, 0.0 }, { 0.0, 0.0, 1.0 }
            local yl, yr = D.y0 - 22.0, D.y1 + 22.0
            local sh, lk = gt.shackle, gt.lock
            local XC = XG - gt.chain_out
            for i = 1, gt.count do
                XC = XG - gt.chain_out - (i - 1) * gt.layer
                local za, zb = rnd(gt.ends_z[1], gt.ends_z[2]), rnd(gt.ends_z[1], gt.ends_z[2])
                local u, sag = rnd(gt.lock_u[1], gt.lock_u[2]), rnd(gt.sag[1], gt.sag[2])
                local yaw = math.rad(rnd(-gt.yaw, gt.yaw))
                local yp = yl + (yr - yl) * u
                local zp = math.max(ZF + gt.lowest, za + (zb - za) * u - sag)
                -- (its eye bolts, out from the wall to it)
                for _, e in ipairs({ { yl, za }, { yr, zb } }) do
                    box("gate_bolt", { (XG + XC) / 2.0, e[1], e[2] }, (XG - XC) / 2.0, 2.5, 2.5, gt.steel_tex, gt.steel_tex, gt.steel, false)
                    box("gate_bolt", { XG - 3.0, e[1], e[2] }, 3.0, 6.0, 6.0, gt.steel_tex, gt.steel_tex, gt.steel, false)
                end
                -- (its chain and padlock off once its key is won - the bolts it hung from left in the wall; the draws
                -- above made all the same, so the other chains lie as ever)
                -- (unlocked: drawn where it fell - dropped till its padlock's foot met the floor, then tipped over
                -- toward him round it, flat: "the chain should drop", 2026-11-06. G.gate_drop_tick drops it so.)
                local off = key_won(i)
                gate_skip = false
                steel_key = "gate_steel#" .. i
                local zfoot = (zp - la + 2.0) - la + lw + sh[3] - sh[1] - sh[2] + 2.0 - lk[2]
                local lie_z = ZF + 8.0 + (gt.count - i) * 2.0
                local XCi = XC
                gate_xf = off and function(p, dir)
                    if dir then return { -p[3], p[2], p[1] } end
                    return { XCi - (p[3] - zfoot), p[2], lie_z + (p[1] - XCi) }
                end or nil
                -- (its curve: two arms down to where its lock pulls it, each sagging a little)
                local pts, acc = {}, { 0.0 }
                local function arm(y1, z1, y2, z2, first)
                    local len = math.sqrt((y2 - y1) ^ 2 + (z2 - z1) ^ 2)
                    for j = first and 0 or 1, 150 do
                        local t = j / 150.0
                        pts[#pts + 1] = { XC, y1 + (y2 - y1) * t, z1 + (z2 - z1) * t - gt.arm_sag * len * 4.0 * t * (1.0 - t) }
                        if #pts > 1 then
                            local a, b = pts[#pts - 1], pts[#pts]
                            acc[#acc + 1] = acc[#acc] + math.sqrt((b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
                        end
                    end
                end
                arm(yl, za, yp, zp, true)
                local sP = acc[#acc]
                arm(yp, zp, yr, zb, false)
                local S = acc[#acc]
                local function at(sv)
                    local lo, hi = 1, #acc
                    while hi - lo > 1 do local m = (lo + hi) // 2; if acc[m] <= sv then lo = m else hi = m end end
                    local k = (sv - acc[lo]) / math.max(1e-6, acc[hi] - acc[lo])
                    local a, b = pts[lo], pts[hi]
                    return { a[1], a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }, norm({ 0.0, b[2] - a[2], b[3] - a[3] })
                end
                -- (the lock turned: F its way out of the keyhole's back, R across it)
                local F, R = { math.cos(yaw), math.sin(yaw), 0.0 }, { -math.sin(yaw), math.cos(yaw), 0.0 }
                -- (the links each side hooked through the next, the first pair both on the one it hangs from, side by
                -- side; that one hangs straight down, the lock's shackle through it)
                local K1 = math.floor((sP - la) / pitch + 0.5)
                local K2 = math.floor((S - sP - la) / pitch + 0.5)
                for k = -K1, K2 do
                    if k == 0 then
                        link({ XC, yp, zp - la + 2.0 }, ZAX, F)
                    else
                        local sg = k > 0 and 1.0 or -1.0
                        local c, T = at(sP + sg * (math.abs(k) - 0.5) * pitch)
                        local Nin = { 0.0, -T[3], T[2] }
                        if math.abs(k) == 1 then c = { c[1] - sg * 1.7 * F[1], c[2] - sg * 1.7 * F[2], c[3] } end
                        if math.abs(k) % 2 == 1 then link(c, T, Nin) else link(c, T, XAX) end
                    end
                end
                -- the padlock: its shackle through that link, its brass body under it, the keyhole to the front
                local zl = zp - la + 2.0
                local zap = zl - la + lw + sh[3]
                local zc = zap - sh[1]
                local path = {}
                local function sp(across, z) return { XC + R[1] * across, yp + R[2] * across, z } end
                path[#path + 1] = sp(-sh[1], zc - sh[2])
                for j = 0, 8 do
                    local a = math.pi - j / 8 * math.pi
                    path[#path + 1] = sp(sh[1] * math.cos(a), zc + sh[1] * math.sin(a))
                end
                path[#path + 1] = sp(sh[1], zc - sh[2])
                sweep(steel_key, gt.steel_tex, path, false, F, sh[3], gt.steel)
                local ztop = zc - sh[2] + 2.0
                box("gate_lock#" .. i, { XC, yp, ztop - lk[2] / 2.0 }, lk[3] / 2.0, lk[1] / 2.0, lk[2] / 2.0, gt.lock_tex, gt.lock_side, gt.brass,
                    false, nil, "gate_lock_side#" .. i, yaw)
                -- (its keyhole: the middle of the padlock's front)
                chains[i] = { on = not off, keys = { steel_key, "gate_lock#" .. i, "gate_lock_side#" .. i },
                              hole = { XC - F[1] * lk[3] / 2.0, yp - F[2] * lk[3] / 2.0, ztop - lk[2] / 2.0 },
                              pivot = { XC, 0.0, zfoot }, lie_z = lie_z }
                gate_xf = nil
            end
            gate_skip = false
            gate_xf = nil
            steel_key = "gate_steel"
            -- (and the wall not drawn, in front of the outermost still on: he stands off the chains. Just clear of its
            -- padlock, turned, and back as they come off - "it would be nice if you pushed the wall back a bit",
            -- 2026-11-06: it was 20 cm out from the outermost whatever was left)
            if not opened then
                local xo = XC
                for k = gt.count, 1, -1 do
                    if not key_won(k) then xo = XG - gt.chain_out - (k - 1) * gt.layer; break end
                end
                local xg = xo - (gt.wall_gap or 10.0)
                local y0, y1 = D.y0 - gt.bar_over, D.y1 + gt.bar_over
                local A, B, C, Dg = { xg, y0, ZF }, { xg, y1, ZF }, { xg, y1, D.z1 }, { xg, y0, D.z1 }
                -- (wound as the level's own, facing him: -X - the gate's own solid)
                local cb = #gpos // 3
                for _, v in ipairs({ A, Dg, C, B }) do gpos[#gpos + 1], gpos[#gpos + 2], gpos[#gpos + 3] = v[1], v[2], v[3] end
                local e1 = { Dg[1] - A[1], Dg[2] - A[2], Dg[3] - A[3] }
                local e2 = { C[1] - A[1], C[2] - A[2], C[3] - A[3] }
                local cr = crs(e1, e2)
                local order = cr[1] * -1.0 > 0 and { 0, 2, 1, 0, 3, 2 } or { 0, 1, 2, 0, 2, 3 }
                for _, k in ipairs(order) do gidx[#gidx + 1] = cb + k end
                gate_live = { scene = name, count = gt.count, keys = gt.keys, flag = gt.lock_flag, open_flag = gt.open_flag,
                              wall_x = xg, y0 = D.y0, y1 = D.y1, zf = ZF, reach = gt.reach or 170.0,
                              key_scale = gt.key_scale or 0.5, chains = chains,
                              hinges = { { XD, D.y0, ZF, -1.0 }, { XD, D.y1, ZF, 1.0 } }, ceil = W.z1, bar_low = gt.bars[1][1] }
            end
        end)
        gate_solid = false
        if not ok then log("hall %s: the gate failed: %s", name, tostring(err))
        elseif opened then log("hall %s: its gate unlocked and open, its %d chains on the floor before it", name, unlocked)
        else log("hall %s: its doorway bolted shut, %d locks on chains (%d unlocked)", name, gt.count - unlocked, unlocked) end
    elseif gt then
        log("hall %s: its gate opened on this file", name)
    end
    -- behind the painting, shut in: the castle's own paintings have the castle round the hollow behind their pictures, this
    -- one had the open sky past the hall's end - gone through it with no warp, he fell out of the world, the camera left
    -- looking at the hall from outside, and the game came down: "im currently looking outside the map", "crash",
    -- 2026-11-03. A dark brick room 3.3 m deep behind its face, its floor just under the warp's strip, as tall and wide as
    -- the hall.
    do
        local back, fz = X1 + 330.0, F.z0 - 82.0
        local dark = { 0.08, 0.06, 0.07 }
        local function v(x, y, z) return { p = { x, y, z }, uv = { (y - D.y0) * h.wall_k + (x - X1) * h.wall_k, (D.z1 - z) * h.wall_k }, col = dark } end
        quad(WT, "behind", { v(X1, D.y0, fz), v(back, D.y0, fz), v(back, D.y1, fz), v(X1, D.y1, fz) }, { 0.0, 0.0, 1.0 })
        quad(WT, "behind", { v(X1, D.y0, D.z1), v(back, D.y0, D.z1), v(back, D.y1, D.z1), v(X1, D.y1, D.z1) }, { 0.0, 0.0, -1.0 })
        quad(WT, "behind", { v(back, D.y0, fz), v(back, D.y1, fz), v(back, D.y1, D.z1), v(back, D.y0, D.z1) }, { -1.0, 0.0, 0.0 })
        quad(WT, "behind", { v(X1, D.y0, fz), v(back, D.y0, fz), v(back, D.y0, D.z1), v(X1, D.y0, D.z1) }, { 0.0, 1.0, 0.0 })
        quad(WT, "behind", { v(X1, D.y1, fz), v(back, D.y1, fz), v(back, D.y1, D.z1), v(X1, D.y1, D.z1) }, { 0.0, -1.0, 0.0 })
    end
    -- the pieces into the scene
    local nid = 0
    for _, sec in ipairs(data.sections) do if (sec.id or 0) >= nid then nid = (sec.id or 0) + 1 end end
    for _, key in ipairs(order) do
        local sec = drawn[key]
        sec.id, nid = nid, nid + 1
        sec.nverts, sec.ntris = #sec.pos // 3, #sec.idx // 3
        data.sections[#data.sections + 1] = sec
    end
    if gate_live then
        for _, ch in pairs(gate_live.chains) do
            ch.ids = {}
            for _, k in ipairs(ch.keys) do if drawn[k] then ch.ids[#ch.ids + 1] = drawn[k].id end end
        end
        gate_live.leaf_ids = { drawn.gate_door_l and drawn.gate_door_l.id, drawn.gate_door_r and drawn.gate_door_r.id }
        gate_live.bar_ids = {}
        for _, k in ipairs({ "gate_bar", "gate_bar_bolt" }) do if drawn[k] then gate_live.bar_ids[#gate_live.bar_ids + 1] = drawn[k].id end end
        gate_live.solid = { source = "the Bowser gate", pos = gpos, idx = gidx, ntris = #gidx // 3 }
        data.gate_live = gate_live
    elseif gt and opened and drawn.gate_door_l then
        -- (open: its open leaves, and their solid)
        data.gate_live = { scene = name, opened = true, open_ids = { drawn.gate_door_l.id, drawn.gate_door_r and drawn.gate_door_r.id },
                           solid = { source = "the Bowser gate", pos = gpos, idx = gidx, ntris = #gidx // 3 } }
    end
    data.collision = data.collision or {}
    data.collision[#data.collision + 1] = { source = "the hallway to the Bowser painting", pos = cpos, idx = cidx, ntris = #cidx // 3 }
    -- the face, hung at its end: a painting into the level, its warp, and its strip behind it - 22 to 306 cm back and 77
    -- under its foot, as the castle's own
    local pp = h.painting
    data.paintings = data.paintings or {}
    data.paintings[#data.paintings + 1] = { name = pp.name, target = pp.target, id = pp.id, node = pp.node, texture = pp.texture,
        size = D.y1 - D.y0, normal = { -1.0, 0.0, 0.0 },
        corners = { X1, D.y0, F.z0, X1, D.y1, F.z0, X1, D.y1, F.z1, X1, D.y0, F.z1 } }
    data.pwarps = data.pwarps or {}
    data.pwarps[#data.pwarps + 1] = { id = pp.id, node = pp.node, scene = pp.target, gauntlet = pp.gauntlet }
    -- (and where he comes out of it again - the run over, by a death or a fall or the way out: on the floor 2.5 m in
    -- front of it, turned away from it, as Mario 64 puts him out in front of a course's painting - G.GAUNTLET)
    if pp.exit_node then
        data.nodes = data.nodes or {}
        -- (and out of it as out of the castle's own paintings, `exit_bhv`: he jumps out of it down the hall toward the
        -- camera, which looks back at the painting - "when exited the level to the painting the camera keeps pointing the
        -- wrong way", "At the painting", 2026-11-03. Its yaw the way he comes out, as a painting's node's is)
        data.nodes[#data.nodes + 1] = { id = pp.exit_node, kind = "ground", pos = { X1 - 250.0, (D.y0 + D.y1) / 2.0, ZF },
                                        yaw = pp.exit_bhv and 180.0 or 0.0, bhv = pp.exit_bhv }
    end
    data.floors = data.floors or {}
    local sz = F.z0 - 77.0
    data.floors[#data.floors + 1] = { tag = "paint:" .. pp.id, ntris = 2, idx = { 0, 1, 2, 0, 2, 3 },
        pos = { X1 + 22.0, D.y0, sz, X1 + 306.0, D.y0, sz, X1 + 306.0, D.y1, sz, X1 + 22.0, D.y1, sz } }
    G.PAINT_RECESS.tex[pp.name] = WT
    log("scene %s: the wall opened (%d triangles, %d solid), a hall %.0f m long, %s's painting at its end -> %s",
        name, cut, ccut, h.length / 100.0, pp.name, pp.target)
    return 1
end

-- The Bowser gate's locks unlocked (G.EXTRA_HALLS castle2's gate): he walks up to its chains with a Bowser key he has
-- not used yet and it goes into the outermost padlock still on, as Mario 64's key doors (unlock.lua M.key, the key at
-- `key_scale`); turned, that chain and its padlock are gone (their pieces hidden now, not drawn from then on) and the
-- file has the lock's flag. The last of them off, the gate is open (`open_flag`) and the castle's floor built again in
-- place, the door and bars and the unseen wall in front of them gone. Every frame from G.tick, a look every 0.1 s.
function G.gate_tick(pawn, dt)
    local gl = G.data and G.data.gate_live
    if not (gl and gl.scene == G.name and pawn) then return end
    if gl.solid and not gl.solid_made then gl.solid_made = true; pcall(G.gate_solid_make, gl) end
    -- (the opening playing out - G.gate_open_start - and nothing else meanwhile)
    if G.gate_anim then G.gate_anim_tick(gl, dt); return end
    if gl.opened then return end
    if gl.drops then G.gate_drop_tick(gl, dt) end
    -- (the last lock off and its chain down: the castle built open, the bars up and the doors swung open in it -
    -- G.gate_open_start, G.gate_anim_tick)
    -- (not while the keys' own scene still plays: built again in the middle of it, its camera and its hold on him went
    -- with the old castle - "player was on other side of door before it opened?", 2026-11-07)
    if gl.open_at then
        if os.clock() >= gl.open_at and not G.unlocking and not G.dying then gl.open_at = nil; G.gate_open_start(gl) end
        return
    end
    if gl.rebuild_at then
        if os.clock() >= gl.rebuild_at and not G.unlocking and not G.dying then
            gl.rebuild_at = nil
            G.gate_rebuild(gl)
        end
        return
    end
    gl.acc = (gl.acc or 0.0) + (dt or 0.016)
    if gl.acc < 0.1 then return end
    gl.acc = 0.0
    if G.unlocking or G.dying or (DIALOG and DIALOG.active) then return end
    local l = pawn:K2_GetActorLocation()
    local x, y, z = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z
    local near = not (x > gl.wall_x + 10.0 or x < gl.wall_x - gl.reach or y < gl.y0 or y > gl.y1)
    -- (only once he has been away from them: the castle built again with him at the chains - a lock put back on - it
    -- waits for him to walk up to them)
    if not gl.armed then
        if not near then gl.armed = true end
        return
    end
    if not near then return end
    if z - (G.half or 90.0) > gl.zf + 60.0 then return end
    local falling = false
    pcall(function() falling = pawn.CharacterMovement:IsFalling() end)
    if falling then return end
    local MN = _G.MENU
    if not (MN and MN.has_key and MN.has_flag and MN.add_flag) then return end
    -- (a key for it: more keys won than locks off)
    local keys, off = 0, 0
    for k = 1, gl.count do
        if MN.has_key(gl.keys .. k) then keys = keys + 1 end
        if MN.has_flag(gl.flag .. k) then off = off + 1 end
    end
    if keys <= off then return end
    -- (every key not used yet at once, each into a lock, from the outermost still on: "if the player has a 3 keys at
    -- the same time and havent opened a single lock make all 3 open at the same time, same if you only have 2", "so it
    -- should be 3 keys going into all the locks", 2026-11-06)
    local pick = {}
    for i = gl.count, 1, -1 do
        local c = gl.chains[i]
        if #pick < keys - off and c and c.on and not MN.has_flag(gl.flag .. i) then pick[#pick + 1] = i end
    end
    if #pick == 0 then return end
    local okU, U = pcall(require, "unlock")
    if not (okU and U and U.key) then return end
    -- (each key's tip `GATE_KEY_IN` cm into its keyhole, its model put under it: unlock.lua measures the tip 145 up and
    -- 15 in, at its full size. He stands before their middle. 3 cm in, its tip only touched the padlock's face: "the
    -- keys not going in the lock", 2026-11-07 - now as far in as a door's key goes, for its size)
    local s = gl.key_scale
    local spots, mx, my, mz = {}, 0.0, 0.0, 0.0
    for _, i in ipairs(pick) do
        local h = gl.chains[i].hole
        local sp = { x = h[1] - 15.0 * s + (G.GATE_KEY_IN or 7.5), y = h[2], z = h[3] - 145.0 * s }
        spots[#spots + 1] = sp
        mx, my, mz = mx + sp.x, my + sp.y, mz + sp.z
    end
    local door = { x = mx / #spots, y = my / #spots, z = mz / #spots, face = 0.0, scale = s }
    if #spots > 1 then
        door.holes, door.view = spots, 1.5
        -- (and a camera that has all their padlocks in sight: out in the room before the hall, to his right, over them -
        -- over his head - looking at their middle, not drawn in by the unseen wall before the chains: "the camera angle
        -- was terrible make sure you can see all 3 keypads", 2026-11-07)
        local lz = door.z + 145.0 * s
        door.cam = { from = { door.x - 230.0, door.y + 90.0, lz + 60.0 }, look = { door.x, door.y, lz }, nocut = true }
    end
    -- (the unlock's own camera, to the side: a camera of its own back in the hall, tried 2026-11-07, was not wanted -
    -- "return the old camera angle")
    -- (turned, the keys gone and the locks off - their chains dropping - the camera kept on them a second longer)
    door.turned_at, door.key_goes, door.hold = 116, true, 30
    door.rainbow = true             -- (the race's key, rainbow as it was won: "the key wasnt rainbow", 2026-11-06)
    door.turned = function() for _, i in ipairs(pick) do G.gate_unlocked(gl, i) end end
    if U.key(door, function() end) then
        log("bowser gate: %d key(s) into lock(s) %s (%d keys, %d locks off)", #pick, table.concat(pick, ", "), keys, off)
    end
end

-- lock i off (G.gate_tick, once its key has turned): the file told, and its chain and padlock dropped - a copy of their
-- pieces, their own actor, falls (G.gate_drop_tick) while the level's are hidden; the last, the gate open once it lies
G.GATE_DROP = { g = 1500.0, tip = 0.45 }        -- (cm/s/s it falls; s it takes to tip over flat once its lock is down)
function G.gate_unlocked(gl, i)
    local MN = _G.MENU
    local ch = gl.chains[i]
    if not (MN and ch) then return end
    pcall(MN.add_flag, gl.flag .. i)
    ch.on = false
    do local LG = package.loaded["ledges"]; if LG and LG.cache then LG.cache[gl.scene] = nil end end
    -- (its copy, round the padlock's foot)
    local okd, errd = pcall(function()
        local world = lib.world()
        local pv = ch.pivot
        local secs = {}
        for _, id in ipairs(ch.ids or {}) do
            for _, sec in ipairs(G.data.sections) do
                if sec.id == id and sec.pos then
                    local pos = {}
                    for k = 1, #sec.pos, 3 do
                        pos[k], pos[k + 1], pos[k + 2] = sec.pos[k] - pv[1], sec.pos[k + 1] - pv[2], sec.pos[k + 2] - pv[3]
                    end
                    secs[#secs + 1] = { id = #secs, layer = sec.layer, texture = sec.texture, unlit = sec.unlit, pos = pos,
                                        uv = sec.uv, col = sec.col, nrm = sec.nrm, idx = sec.idx, nverts = sec.nverts, ntris = sec.ntris }
                    break
                end
            end
        end
        if #secs == 0 or not world then return end
        local actor = lib.spawn_actor(world, { X = pv[1] + OFFSET.X, Y = pv[2] + OFFSET.Y, Z = pv[3] + OFFSET.Z }, 0.0)
        if not actor then return end
        G.extras[#G.extras + 1] = actor
        local pmc = lib.add_pmc(actor)
        if not pmc then return end
        pcall(function() pmc:SetCollisionEnabled(0) end)
        lib.add_sections(world, pmc, secs)
        gl.drops = gl.drops or {}
        gl.drops[#gl.drops + 1] = { actor = actor, ch = ch, t = 0.0, z = pv[3], vz = 0.0 }
    end)
    if not okd then log("bowser gate: its chain's drop failed: %s", tostring(errd)) end
    for _, id in ipairs(ch.ids or {}) do
        pcall(function() G.pmc:SetMeshSectionVisible(id, false) end)
        local bid = G.under_ids and G.under_ids[id]
        if bid and G.under_pmc then pcall(function() G.under_pmc:SetMeshSectionVisible(bid, false) end) end
    end
    local left = 0
    for k = 1, gl.count do if not MN.has_flag(gl.flag .. k) then left = left + 1 end end
    log("bowser gate: lock %d off, its chain dropping, %d left on", i, left)
    if left == 0 then
        pcall(MN.add_flag, gl.open_flag)
        gl.open_when_down = true
        log("bowser gate: all its locks off - open once it lies")
    end
end

-- the dropped chains falling (G.gate_unlocked): straight down till the padlock's foot is on the floor, then tipped over
-- toward him round it till flat (pitched 90: up goes to -X), a clank each time - lying as G.add_halls draws it from then on
function G.gate_drop_tick(gl, dt)
    local GD = G.GATE_DROP
    local SF = package.loaded["sfx"]
    local all_down = true
    for _, d in ipairs(gl.drops) do
        if not d.down then
            all_down = false
            dt = math.min(dt or 0.016, 0.05)
            local ch, pv = d.ch, d.ch.pivot
            local pitch = 0.0
            if not d.tip then
                d.vz = d.vz + GD.g * dt
                d.z = d.z - d.vz * dt
                if d.z <= gl.zf then
                    d.z, d.tip = gl.zf, 0.0
                    if SF then pcall(SF.play, "door_iron_close", 0.6) end
                end
            else
                d.tip = d.tip + dt
                local k = math.min(1.0, d.tip / GD.tip)
                pitch = 90.0 * k * k
                d.z = gl.zf + (ch.lie_z - gl.zf) * k
                if k >= 1.0 then
                    d.down = true
                    if SF then pcall(SF.play, "door_iron_close", 1.0) end
                end
            end
            pcall(function()
                if d.actor:IsValid() then
                    d.actor:K2_SetActorLocationAndRotation({ X = pv[1] + OFFSET.X, Y = pv[2] + OFFSET.Y, Z = d.z + OFFSET.Z },
                        { Pitch = pitch, Yaw = 0.0, Roll = 0.0 }, false, {}, true)
                end
            end)
        end
    end
    if all_down and gl.open_when_down then
        gl.open_when_down = nil
        gl.open_at = os.clock() + 0.5
    end
end

-- The gate's own solid (G.add_halls keeps it apart): an actor of its own, solid only, unseen - its collision turned off
-- the moment the gate opens, nothing built again.
function G.gate_solid_make(gl)
    local world = lib.world()
    if not (world and gl.solid and #gl.solid.idx > 0) then return end
    local actor = lib.spawn_actor(world, { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z }, 0.0)
    if not actor then return end
    G.extras[#G.extras + 1] = actor
    local pmc = lib.add_pmc(actor)
    if not pmc then return end
    lib.add_collision(pmc, { gl.solid })
    gl.solid_actor = actor
end

-- The gate opening (G.gate_tick, the last chain down): its solid off at once - he can walk in as it opens - and copies
-- of its bars and of its two leaves, their own actors, the level's hidden: the bars rise up into the ceiling, then the
-- leaves swing in on their hinges, slowly, GATE_OPEN degrees, and are left so (built again some other time, the castle
-- draws them open). Not the castle built again: its old solid stayed a few seconds after, a wall as they swung, and he
-- was pushed through the doorway out of it - "still teleporting to the other side of the door", 2026-11-07.
G.GATE_OPEN = 75.0          -- (at 90 each leaf lay flat on the hall's wall, there and not seen)
G.GATE_OPEN_T = { bars = 1.2, wait = 0.4, doors = 3.5 }
function G.gate_open_start(gl)
    if gl.solid_actor then pcall(function() gl.solid_actor:SetActorEnableCollision(false) end) end
    local world = lib.world()
    local function copy(ids, pv)
        local secs = {}
        for _, id in ipairs(ids or {}) do
            for _, sec in ipairs(G.data.sections) do
                if sec.id == id and sec.pos then
                    local pos = {}
                    for k = 1, #sec.pos, 3 do
                        pos[k], pos[k + 1], pos[k + 2] = sec.pos[k] - pv[1], sec.pos[k + 1] - pv[2], sec.pos[k + 2] - pv[3]
                    end
                    secs[#secs + 1] = { id = #secs, layer = sec.layer, texture = sec.texture, unlit = sec.unlit, pos = pos,
                                        uv = sec.uv, col = sec.col, nrm = sec.nrm, idx = sec.idx, nverts = sec.nverts, ntris = sec.ntris }
                    break
                end
            end
        end
        if #secs == 0 or not world then return nil end
        local actor = lib.spawn_actor(world, { X = pv[1] + OFFSET.X, Y = pv[2] + OFFSET.Y, Z = pv[3] + OFFSET.Z }, 0.0)
        if not actor then return nil end
        G.extras[#G.extras + 1] = actor
        local pmc = lib.add_pmc(actor)
        if not pmc then return nil end
        pcall(function() pmc:SetCollisionEnabled(0) end)
        lib.add_sections(world, pmc, secs)
        return actor
    end
    local a = { scene = gl.scene, t = 0.0, leaves = {}, rise = (gl.ceil or 4400.0) - (gl.bar_low or 3890.0) + 40.0 }
    local ok, err = pcall(function()
        a.bar_actor = copy(gl.bar_ids, { 0.0, 0.0, 0.0 })
        for i, h in ipairs(gl.hinges or {}) do a.leaves[#a.leaves + 1] = { actor = copy({ gl.leaf_ids and gl.leaf_ids[i] }, h), h = h } end
    end)
    if not ok then log("bowser gate: its opening failed: %s", tostring(err)) end
    local hide = {}
    for _, id in ipairs(gl.bar_ids or {}) do hide[#hide + 1] = id end
    for _, id in ipairs(gl.leaf_ids or {}) do hide[#hide + 1] = id end
    for _, id in ipairs(hide) do
        pcall(function() G.pmc:SetMeshSectionVisible(id, false) end)
        local bid = G.under_ids and G.under_ids[id]
        if bid and G.under_pmc then pcall(function() G.under_pmc:SetMeshSectionVisible(bid, false) end) end
    end
    G.gate_anim = a
    local SF = package.loaded["sfx"]
    if SF then pcall(SF.play, "door_iron_close", 0.5) end
    log("bowser gate: opening - its solid off, its bars up, then its doors")
end
function G.gate_anim_tick(gl, dt)
    local a = G.gate_anim
    if a.scene ~= G.name then G.gate_anim = nil; return end
    local T = G.GATE_OPEN_T
    a.t = a.t + math.min(dt or 0.016, 0.05)
    local function ease(k) k = math.max(0.0, math.min(1.0, k)); return k * k * (3.0 - 2.0 * k) end
    local kb = ease(a.t / T.bars)
    if a.bar_actor then pcall(function() a.bar_actor:K2_SetActorLocation({ X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z + a.rise * kb }, false, {}, true) end) end
    local t2 = a.t - T.bars - T.wait
    -- (the doors as they swing: the rolling log's rumble, again each GATE_ROLL_EVERY s - "make the doors opening sound
    -- like the rolling logs", 2026-11-07)
    if t2 > 0.0 and t2 < T.doors and a.t >= (a.next_roll or 0.0) then
        a.next_roll = a.t + (G.GATE_ROLL_EVERY or 0.95)
        local SF = package.loaded["sfx"]
        if SF then pcall(SF.play, "log_roll", 1.0) end
    end
    local kd = ease(t2 / T.doors)
    for _, lf in ipairs(a.leaves) do
        if lf.actor then
            local h = lf.h
            pcall(function()
                lf.actor:K2_SetActorLocationAndRotation({ X = h[1] + OFFSET.X, Y = h[2] + OFFSET.Y, Z = h[3] + OFFSET.Z },
                    { Pitch = 0.0, Yaw = h[4] * (G.GATE_OPEN or 75.0) * kd, Roll = 0.0 }, false, {}, true)
            end)
        end
    end
    if t2 >= T.doors then
        if a.bar_actor then pcall(function() lib.destroy(a.bar_actor) end) end
        G.gate_anim = nil
        log("bowser gate: open")
    end
end

-- the gate open (G.gate_unlocked): the castle built again where he stands, without it - its old solid forgotten first
-- (ledges.lua keeps each scene's split for the session)
function G.gate_rebuild(gl)
    if G.name ~= gl.scene then return end
    local LG = package.loaded["ledges"]
    if LG and LG.cache then LG.cache[gl.scene] = nil end
    log("bowser gate: the castle built again without it")
    pcall(G.goto_scene, gl.scene, nil, { move = { 0.0, 0.0, 0.0 } })
end

-- The Bowser run: the hallway's painting (G.EXTRA_HALLS) into the three Bowser courses one after another - "in this new
-- level we're gonna combine all the bowser courses into one so once the player gets to the top of bowser 1 then its 2
-- and so on", "remove the red coins", "add double the enemies", 2026-11-03. No Bowser on the way: each course's top
-- (its pipe or warp into Bowser's arena) goes on to the next course's start - "no bowser Fight until you reach the very
-- top its also going to be a custom bowser fight" (the Sky's top still into Mario 64's last fight till that is made).
-- Out of it any other way - a death, a fall out of the level ("if the player falls out of the level make it spawn the
-- player outside the correct painting"), the way out - he is put out in front of the painting it began at, the run over
-- ("Whole run restarts" on a death): jumped into again, it starts again from the Dark World. G.gauntlet is set while it
-- goes. In its courses no red coins nor their star, and every enemy but the fixed flamethrowers twice over: each twin on
-- the same floor near it (not across a gap), a circling Amp's half a turn round its circle from it.
G.GAUNTLET = {
    courses = { bitdw = true, bitfs = true, bits = true },
    -- (the scenes the run is: the Fire Sea and the Sky are in the Dark World's now - G.RUN_JOIN - so not on their own)
    scenes = { bitdw = true, bowser_3 = true },
    next = { bowser = { "bitfs", 10 }, bowser_2 = { "bits", 10 } },
    final = "bowser_3",
    exit = { "castle2", 160 },
    -- (not the Amps: "also remove the double shocker enemies"; nor the Bullies, as many as Mario 64 has: "return the
    -- bullies to they're regular amount", 2026-11-03)
    double = { bhvChuckya = true,
               bhvFireSpitter = true, bhvFirePiranhaPlant = true, bhvGoomba = true, bhvBobomb = true, bhvSwoop = true,
               bhvSnufit = true, bhvMrBlizzard = true, bhvSpindrift = true, bhvBulletBill = true },
    spread = { 160.0, 120.0, 220.0, 90.0 },        -- (cm from it a twin is looked for a floor at)
    -- (every other yellow coin out: "and half the coins in this level", 2026-11-03)
    half_coins = true,
    -- (one tune all the way up, the final Bowser remix, not each course its own: "music keeps switching I only want final
    -- bowser to play", 2026-11-03 - G.join_scenes)
    music = "level_koopa_road@run_sky",
}
-- The courses one level: on from the Dark World's top, where its pipe stood, the Fire Sea itself - "remove the pipe and
-- continue the level with bowser 2 course", 2026-11-03. In the run, the scene built is the first course with the next
-- put on after it, moved `move` (scene cm) - its first platform straight on from the Dark World's top platform's tip, at
-- its height - all of it: its picture, its floors and walls, its lava and its other floors of note, its things (its
-- platforms and their tracks in Mario 64's units), its lava's moving surfaces (movtex.lua), its ways out (renumbered
-- `ids` on, so they do not meet the first course's). The first course's pipe out is gone. What has the scene's name -
-- its sky, its music - stays the first course's.
-- (`no_lava`: none of its lava - its moving surfaces, its burning floors, the sea bed under them - and a fall between its
-- platforms a fall out of the level, as in the Dark World: a death plane `death` (its own cm) under it all - "remove the
-- lava on bowser 2 course", 2026-11-03)
G.RUN_JOIN = {
    -- (its start - where Mario comes down into it, on its first platform's floor - put `to`, where he stood on the Dark
    -- World's top platform, 1 cm over its floor, and the course turned `yaw` degrees about it: "bring the start of bowser
    -- 2 course right where im standing", "also turn the course 90degrees to the right", 2026-11-03)
    -- (its square first platform out, `drop` - every triangle wholly in that box, its own cm - and its middle on the
    -- middle of the Dark World's octagonal top, where the pipe stood: the octagon its start, its bridge on from its edge -
    -- "the start point is off center can you also round off the square so it fits the scene better?", 2026-11-03. Its
    -- bridge's near end - where the square was - put at the octagon's outer edge, level with the foot of its rim, on its
    -- middle: wider than that side of the octagon by a hair, laid over the rim its corners showed over the rim's slanting
    -- sides - "the edges stick out just a hair", "still sticking out a bit")
    bitdw = { { scene = "bitfs", from = { 0.0, -5299.0, -2073.0 }, to = { -532.5, 5111.6, 2073.75 }, yaw = 90.0, ids = 100,
                drop = { { -386.0, 386.0, -5991.0, -5290.0, -2310.0, -2070.0 },
                         -- (and what held its two raised lava pools, the lava gone: each one's floor, walls and rim, and the
                         -- floor left where the lava's surface was - not to be seen, but stood on: "on bowser 2 course
                         -- remove the lava holder", 2026-11-03)
                         { -880.0, 910.0, -5670.0, 3720.0, -2.0, 200.0 },
                         -- (the upper one's to its rim's top, the ring round it: "remove the outer ring")
                         { -880.0, 910.0, -3470.0, 4320.0, 2400.0, 2655.0 },
                         -- (the four brick pillars that held the two pools up, holding nothing now: "also remove these
                         -- poles", 2026-11-03)
                         -- (the poles from their very foot: from 22 m down their last 2 m were left, stubs out of the lava
                         -- race's lava - "also these poles are still here", 2026-11-03)
                         { -515.0, -345.0, -4235.0, -4055.0, -2310.0, 10.0 }, { 345.0, 515.0, -4235.0, -4055.0, -2310.0, 10.0 },
                         { -515.0, -345.0, 3135.0, 3315.0, 150.0, 2465.0 }, { 345.0, 515.0, 3135.0, 3315.0, 150.0, 2465.0 },
                         -- (and its way into Bowser's arena - the spring and its dish round the warp - the last course on
                         -- from there instead: "replace bowser 2 entrance with final bowser course")
                         { -310.0, 185.0, 4795.0, 5310.0, 2380.0, 3200.0 },
                         -- (and the green funnel the spring stood in: "you didnt remove the green funnel")
                         { -660.0, 515.0, 4465.0, 5640.0, 2985.0, 3385.0 },
                         -- (and the floor under the spring, at the foot of its pit: not drawn, but stood on)
                         { -260.0, 110.0, 4870.0, 5230.0, 2165.0, 2185.0 } },
                drop_kinds = { warp = true }, music = "level_koopa_road@bitfs",
                -- (and things of its own left out, by type and where Mario 64 has them (its units, within 60): the small
                -- Bully on the stone platform with the Goombas, at its edge where he comes up off the ramp - "remove the
                -- bully gaurding the edge", "nope def still there" with its picture, 2026-11-03)
                drop_objects = { { "bhvSmallBully", 2340.0, -2764.0, 580.0 } },
                -- (and pieces of things cut away, by behaviour and Mario 64 place as above: the triangles of its picture
                -- and its solid whose middles lie in `box` - its own frame - left out of a copy of its template for it
                -- alone. The middle of the three ramps of the sinking metal platform in front of that Bully's - "also
                -- remove the blue triangle in the middle of that picture", "it was only supposed to be the middle one",
                -- 2026-11-03)
                cut_objects = { { "bitfs_sink", 1126.0, -3065.0, 307.0, tag = "nomid",
                                  box = { -1000.0, 1000.0, -230.0, 230.0, -100.0, 200.0 } } },
                no_lava = { bed = -2303.25, death = -4000.0, margin = 600.0 } },
              -- (the Sky on where the Fire Sea's way into Bowser's arena was, `at` in the Fire Sea's own cm - on the
              -- middle of its first platform, its near edge on the end of the Fire Sea's walk there (the funnel the
              -- spring stood in gone), 32 cm over it - and turned `turn` degrees more: "replace
              -- bowser 2 entrance with final bowser course", "turn the course 90 degrees right again as well",
              -- 2026-11-03. Its top's pipe into the last fight kept.)
              { scene = "bits", after = 1, at = { -74.25, 4771.25, 3335.25 }, turn = 90.0, from = { 0.0, -5428.0, -3609.0 }, ids = 200,
                -- (its tune the unused one, "Ultimate Final Bowser (Orchestral Metal Hybrid Halloween Remix)": "also use the
                -- unused bowser final song", 2026-11-03 - music_remix/level_koopa_road@run_sky.mp3; Mario 64's own Koopa's
                -- Road with the remixes off)
                music = "level_koopa_road@run_sky" } },
}
-- The lava race: a sea of lava under the whole run level - one flat sheet of the Fire Sea's lava (its moving texture),
-- `margin` out past the level's every side - that rises and falls as he goes ("attach lava 20cm below the player make it
-- span the entire map", "lava not following the player also make it 200cm", "my idea with this is I can record my
-- player and the lava will raise lower as I traverse through the level", 2026-11-03). A START line `start` across the
-- Dark World's first platform, in front of where he stood, and a FINISH line `finish` at the very top, where the Sky's
-- last stairs meet its pipe's platform ("put a race start in front of me when the player goes past it the lava starts
-- to record", "also put one all the way at the top for a race end"): { x, y, floor z, the way across it (degrees) },
-- `*_w` half its width. Past START with no pace kept, the lava follows him `below` cm under the ground he is on - his
-- feet on the ground; in the air the ground he left, or lower as he drops under it - and that height is kept every
-- `rec_dt` s; at FINISH it is saved (G.lava_race_save, lava_race.lua in the mod's folder). Past START once one is kept,
-- the lava plays it back: as high, at each moment, as his ground was then, `below` under it - he has to keep ahead of
-- his own pace ("Record, then chase"); it reaching his feet costs a life, and the run starts again ("Lose a life,
-- restart"). It glides to its height (`glide` a second); before START it lies at `z`, `below` under the start. Never
-- solid nor burning by itself: the burn threw him off it again and again, limp - "also its glitching".
-- (START bigger - `start_w` half its width, `start_h` its height, its posts `start_down` down into the lava - and passed
-- anywhere within `start_reach` cm either side of it, from behind it; till then the lava lies 12 m under the start, `z`,
-- so as START is passed it is seen to rise: "make that one bigger and the second someone triggers it the lava starts
-- rising", 2026-11-03)
-- (its picture the metal cap's, Mario 64's metal - `texture`, a repeat every `tile` cm: "I want to use the same texture
-- as metal cap"; and a swell of its own, up and down - `bob` cm over `bob_period` s, and a smaller quicker one, `bob2`
-- over `bob2_period`, only seen: what catches him is its height without it - "I also want the lava to kinda move up and
-- down on its own", 2026-11-03)
-- (before START it lies 200 cm under the start, as under him after: "when the level starts why is the lava so far
-- down?", "it should be 200?", 2026-11-03 - it was 12 m down, to be seen rising)
-- (its picture 4 times bigger: "also increase the size of the metal cap texture", 2026-11-03)
G.RUN_LAVA = { bitdw = { z = -2565.0, below = 200.0, margin = 40000.0, tile = 2400.0, speed = -0.002, glide = 2.5,
                         texture = "run_chrome_ball",
                         -- (liquid chrome: "its showing as a metal circle which is wrong", "Liquid chrome", 2026-11-03 -
                         -- Mario 64's metal picture is a chrome ball laid on by where a surface faces as the camera sees it
                         -- (G_TEXTURE_GEN), so a flat sheet is one colour of it: round him a patch `size` cm across, `n`
                         -- squares a side, rippling - its waves, `amp` cm, fading to flat at its edge - the picture laid on
                         -- by each corner's facing, as on Metal Mario; the sheet beyond it the flat colour, so they meet
                         -- unseen. Redone every `every` frames.)
                         -- (`tilt`: how much more each ripple turns the picture than its slope would - its waves are
                         -- gentle, and laid on as they are the chrome showed one flat grey; `reach`: how far out of the
                         -- ball's middle a facing lays it - a floor seen from the side is the ball's dark rim at 1)
                         -- (`sky`: the background in the same chrome - a sphere of its own just inside the sky's, its
                         -- picture the chrome ball laid round it, straight up its middle and the horizon its outer ring:
                         -- "also going to have to make this custom the backround needs that same chrome", 2026-11-03)
                         -- (a world of its own in chrome, made for it - "the backround is really bad", "you have to make
                         -- it custom", 2026-11-03: X:/mashup-work/tools/chrome_env.py, a chrome studio under an indigo sky, ribbons of
                         -- light, a pink glow at a crisp white horizon - painted as a panorama for the sky, `sky.tex`, and
                         -- as a chrome ball, `texture`, which the lava is a mirror of: each corner shows what the camera
                         -- would see in it, its ripples bending that. Round him a patch `size` cm across, `n` squares a
                         -- side, its ripples `amp` cm fading to flat at its edge, their slope `tilt` times over in the
                         -- mirror; beyond it, a coarse grid `far` squares a side over the whole sheet, flat. Redone every
                         -- `every` frames.)
                         -- (the mirror one round mesh centred on him - `in_rings` rings `in_step` cm apart, then `out_rings`
                         -- growing out to `r_out` at the sky, `around` corners round each - its ripples full to `wave_full`
                         -- cm out and gone by `wave_end`: a square patch on a coarser grid showed where it ended, "also I can
                         -- see where the waves end", 2026-11-03. The outer rings' reflections redone half as often.)
                         -- (its ripples lower, `amp` 14 not 28, and their highest crest kept under the gap too: "waves
                         -- coming up a little too high", 2026-11-03)
                         chrome = { in_rings = 10, in_step = 600.0, out_rings = 9, r_out = 390000.0, around = 26,
                                    wave_full = 3500.0, wave_end = 6000.0, snap = 500.0, amp = 14.0, every = 4, tilt = 8.0,
                                    sky = { r = 395000.0, around = 64, rings = 32, up = 900.0, tex = "run_chrome_sky" },
                                    waves = { { 0.00085, 0.00031, 1.6, 0.6 }, { -0.00042, 0.00093, 1.1, 0.4 },
                                              { 0.0016, -0.0012, 2.3, 0.18 } } },
                         bob = 45.0, bob_period = 5.0, bob2 = 15.0, bob2_period = 1.7, bob_gap = 180.0,
                         -- (the deep pipe at the top kept clear of it - a dark lid across its shaft just over the liquid:
                         -- `r` its shaft's octagon (DEEP_PIPES inner 76.5) a little over, `depth` the shaft's - "no you
                         -- just lowered the liquid, I just dont want it in the pipe", 2026-11-04)
                         pipe_lid = { r = 79.0, depth = 1500.0, texture = "pipe_dark" },
                         rec_dt = 0.1, max_speed = 350.0, chase_delay = 2.0,
                         start = { -2915.0, -5005.0, -2365.0, 90.0 }, start_w = 420.0, start_h = 560.0, start_down = 1300.0,
                         -- (unseen, and passed anywhere 12 m either side of it: "make the start even bigger also make
                         -- it invisable", 2026-11-03)
                         -- (and then the whole world: past its line anywhere, at any height, once he has been behind it -
                         -- "make the start even bigger I dont want any players to get around it somehow", 2026-11-03)
                         start_reach = 1.0e7, start_below = 1.0e7, start_above = 1.0e7, start_hidden = true,
                         finish = { -14560.0, -660.0, 15926.0, 180.0 }, finish_w = 230.0, finish_zone = 900.0,
                         -- (no arch at the top: the race still ends there, unseen - "theres still a finish checkpoint",
                         -- 2026-11-03)
                         finish_hidden = true } }

-- A copy of template `key` (in `templates`) with every triangle of its pictures and its solid whose middle lies in
-- `box` = { x0, x1, y0, y1, z0, z1 } (its own frame) left out, put in under `key .. "#" .. tag`; that key returned
-- (G.RUN_JOIN `cut_objects`)
function G.cut_template(templates, key, box, tag)
    local nk = key .. "#" .. tostring(tag)
    if templates[nk] then return nk end
    local t = templates[key]
    local function inside(P, a, b, c)
        local x = (P[a + 1] + P[b + 1] + P[c + 1]) / 3.0
        local y = (P[a + 2] + P[b + 2] + P[c + 2]) / 3.0
        local z = (P[a + 3] + P[b + 3] + P[c + 3]) / 3.0
        return x >= box[1] and x <= box[2] and y >= box[3] and y <= box[4] and z >= box[5] and z <= box[6]
    end
    local function cut(m)
        if not (m and m.pos and m.idx) then return m end
        local c = {}
        for k, v in pairs(m) do c[k] = v end
        local keep = {}
        for i = 1, #m.idx - 2, 3 do
            local a, b, d = m.idx[i] * 3, m.idx[i + 1] * 3, m.idx[i + 2] * 3
            if not inside(m.pos, a, b, d) then keep[#keep + 1], keep[#keep + 2], keep[#keep + 3] = m.idx[i], m.idx[i + 1], m.idx[i + 2] end
        end
        c.idx, c.ntris = keep, #keep // 3
        return c
    end
    local nt = {}
    -- (what platforms.lua works out from it once - its floor, its reach, its edges - worked out again for the copy)
    for k, v in pairs(t) do if k ~= "swing" and k ~= "ready" and k ~= "floor" and k ~= "radius" then nt[k] = v end end
    nt.sections = {}
    for i, sec in ipairs(t.sections or {}) do nt.sections[i] = cut(sec) end
    nt.collision = cut(t.collision)
    templates[nk] = nt
    return nk
end

function G.join_scenes(name, data)
    local list = G.gauntlet and G.RUN_JOIN[name]
    if not (list and data and data.sections) or data.joined then return 0 end
    data.joined = true
    local kept, pipes = {}, {}
    for _, o in ipairs(data.objects or {}) do
        if o.kind == "pipe" then pipes[#pipes + 1] = o.pos else kept[#kept + 1] = o end
    end
    data.objects = kept
    -- (and the pipe itself, the level's own model of it - its side, top and dark inside - and its solid round: every
    -- piece lying wholly within 2 m of where it stood, from its foot to 3 m up)
    local function at_pipe(P)
        for _, pp in ipairs(pipes) do
            if pp and P and #P >= 3 then
                local all = true
                for i = 1, #P - 2, 3 do
                    if (P[i] - pp[1]) ^ 2 + (P[i + 1] - pp[2]) ^ 2 > 200.0 * 200.0 or P[i + 2] < pp[3] - 10.0 or P[i + 2] > pp[3] + 300.0 then
                        all = false
                        break
                    end
                end
                if all then return true end
            end
        end
        return false
    end
    do
        local secs, cols = {}, {}
        for _, sec in ipairs(data.sections) do if not at_pipe(sec.pos) then secs[#secs + 1] = sec end end
        for _, m in ipairs(data.collision or {}) do if not at_pipe(m.pos) then cols[#cols + 1] = m end end
        if #secs < #data.sections or #cols < #(data.collision or {}) then
            log("bowser run: %s's pipe out (%d pieces, %d solid)", name, #data.sections - #secs, #(data.collision or {}) - #cols)
        end
        data.sections, data.collision = secs, cols
    end
    data.collision, data.floors, data.warps, data.nodes = data.collision or {}, data.floors or {}, data.warps or {}, data.nodes or {}
    data.movtex_extra = data.movtex_extra or {}
    local function copy(t) local c = {}; for k, v in pairs(t) do c[k] = v end; return c end
    -- (the lowest floor among all put in so far over a rectangle: a death plane is kept far enough under it - 16 m: he
    -- falls out of the level within 15.4 m over one - or it took him off another course's floors over it)
    local function lowest_under(x0, x1, y0, y1)
        local low = nil
        for _, m in ipairs(data.collision) do
            local P, I = m.pos, m.idx
            if P and I then
                for t = 1, #I - 2, 3 do
                    local a, b, c = I[t] * 3, I[t + 1] * 3, I[t + 2] * 3
                    local inside = false
                    for _, i in ipairs({ a, b, c }) do
                        if P[i + 1] >= x0 and P[i + 1] <= x1 and P[i + 2] >= y0 and P[i + 2] <= y1 then inside = true; break end
                    end
                    if inside then
                        local ux, uy, uz = P[b + 1] - P[a + 1], P[b + 2] - P[a + 2], P[b + 3] - P[a + 3]
                        local vx, vy, vz = P[c + 1] - P[a + 1], P[c + 2] - P[a + 2], P[c + 3] - P[a + 3]
                        local nz = ux * vy - uy * vx
                        local l = math.sqrt((uy * vz - uz * vy) ^ 2 + (uz * vx - ux * vz) ^ 2 + nz * nz)
                        if l > 0.0 and math.abs(nz / l) > 0.7 then
                            local z = math.min(P[a + 3], P[b + 3], P[c + 3])
                            if not low or z < low then low = z end
                        end
                    end
                end
            end
        end
        return low
    end
    local function death_rect(x0, x1, y0, y1, z)
        local low = lowest_under(x0, x1, y0, y1)
        if low and z > low - 1600.0 then z = low - 1600.0 end
        return { tag = "death", ntris = 2, idx = { 0, 1, 2, 0, 2, 3 }, pos = { x0, y0, z, x1, y0, z, x1, y1, z, x0, y1, z } }
    end
    local n = 0
    -- (the 4 m squares each course's floors lie over, for its tune - G.run_section_tick: the first course to claim a square
    -- keeps it, the scene's own first, so at a join each course keeps its own edge)
    data.join_cells = data.join_cells or {}
    local function mark_floors(m, ri)
        local P, I = m.pos, m.idx
        if not (P and I) then return end
        local cells = data.join_cells
        for t = 1, #I - 2, 3 do
            local a, b, d = I[t] * 3, I[t + 1] * 3, I[t + 2] * 3
            local ax, ay, bx, by, cx, cy = P[a + 1], P[a + 2], P[b + 1], P[b + 2], P[d + 1], P[d + 2]
            local ux, uy, uz = bx - ax, by - ay, P[b + 3] - P[a + 3]
            local vx, vy, vz = cx - ax, cy - ay, P[d + 3] - P[a + 3]
            local nz = ux * vy - uy * vx
            local l = math.sqrt((uy * vz - uz * vy) ^ 2 + (uz * vx - ux * vz) ^ 2 + nz * nz)
            if l > 0.0 and math.abs(nz / l) > 0.7 then
                local function claim(ix, iy)
                    local k = ix .. ":" .. iy
                    if cells[k] == nil then cells[k] = ri end
                end
                claim(math.floor(ax / 400.0), math.floor(ay / 400.0))
                claim(math.floor(bx / 400.0), math.floor(by / 400.0))
                claim(math.floor(cx / 400.0), math.floor(cy / 400.0))
                local dd = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
                if math.abs(dd) > 1e-9 then
                    for ix = math.floor(math.min(ax, bx, cx) / 400.0), math.floor(math.max(ax, bx, cx) / 400.0) do
                        for iy = math.floor(math.min(ay, by, cy) / 400.0), math.floor(math.max(ay, by, cy) / 400.0) do
                            local px, py = (ix + 0.5) * 400.0, (iy + 0.5) * 400.0
                            local l1 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / dd
                            local l2 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / dd
                            if l1 >= 0.0 and l2 >= 0.0 and 1.0 - l1 - l2 >= 0.0 then claim(ix, iy) end
                        end
                    end
                end
            end
        end
    end
    for _, m in ipairs(data.collision or {}) do mark_floors(m, 0) end
    local frames = {}
    for ji, j in ipairs(list) do
        local src = lib.load_data("data.scene_" .. j.scene)
        if src then
            -- (its platforms' and trees' models, kept by name: its moving platforms were not built without them - "you
            -- also have to add all the moving platforms", 2026-11-03. In their own frame, so not moved.)
            data.templates = data.templates or {}
            for k, t in pairs(src.templates or {}) do if data.templates[k] == nil then data.templates[k] = t end end
            data.tree_templates = data.tree_templates or {}
            for k, t in pairs(src.tree_templates or {}) do if data.tree_templates[k] == nil then data.tree_templates[k] = t end end
            -- (its own fixes, made to it as its own scene has them, before it is moved: they go by its name and its own
            -- cm - G.MOVE_PIECES and the rest. The Sky's - its flamethrower and block taken out, its beam laid flat, its
            -- pipe made deep - were missing: "bowser 3 is missing its additions", 2026-11-03)
            pcall(G.drop_camera_walls, src)
            for _, fx in ipairs({ G.fix_sections, deepen, G.face_fixes, G.raise_parts, G.move_pieces, G.deepen_pipes or function() end }) do
                local okf, errf = pcall(fx, j.scene, src)
                if not okf then log("bowser run: a fix of %s failed: %s", j.scene, tostring(errf)) end
            end
            -- (where a point of it goes: about its `from`, turned `yaw`, put at `to` - scene cm; and in Mario 64's units)
            local F, T, yawj = j.from, j.to, j.yaw or 0.0
            if j.after and frames[j.after] then
                local fr = frames[j.after]
                T = { fr.tp(j.at[1], j.at[2], j.at[3]) }
                yawj = fr.yaw + (j.turn or 0.0)
            end
            local cy, sy = math.cos(math.rad(yawj)), math.sin(math.rad(yawj))
            local function tp(x, y, z)
                local rx, ry = x - F[1], y - F[2]
                return T[1] + rx * cy - ry * sy, T[2] + rx * sy + ry * cy, z - F[3] + T[3]
            end
            local function mv(P)
                local out = {}
                for i = 1, #P - 2, 3 do out[i], out[i + 1], out[i + 2] = tp(P[i], P[i + 1], P[i + 2]) end
                return out
            end
            local function tsm(X, Y, Z)
                local x, y, z = tp(-Z * 0.75, X * 0.75, Y * 0.75)
                return y / 0.75, z / 0.75, -x / 0.75
            end
            frames[ji] = { tp = tp, yaw = yawj }
            local bx0, bx1, by0, by1 = math.huge, -math.huge, math.huge, -math.huge
            -- (the triangles of `drop`'s boxes out of an index list over P - its own cm)
            local function undropped(P, idx)
                if not (j.drop and idx) then return idx end
                local keep = {}
                for t = 1, #idx - 2, 3 do
                    local gone = false
                    for _, b in ipairs(j.drop) do
                        local all = true
                        for k = 0, 2 do
                            local i = idx[t + k] * 3
                            local x, y, z = P[i + 1], P[i + 2], P[i + 3]
                            if x < b[1] or x > b[2] or y < b[3] or y > b[4] or z < b[5] or z > b[6] then all = false; break end
                        end
                        if all then gone = true; break end
                    end
                    if not gone then keep[#keep + 1], keep[#keep + 2], keep[#keep + 3] = idx[t], idx[t + 1], idx[t + 2] end
                end
                return keep
            end
            local nid = 0
            for _, sec in ipairs(data.sections) do if (sec.id or 0) >= nid then nid = (sec.id or 0) + 1 end end
            for _, sec in ipairs(src.sections or {}) do
                local c = copy(sec)
                c.pos, c.id, nid = mv(sec.pos), nid, nid + 1
                c.idx = undropped(sec.pos, sec.idx)
                c.ntris = #c.idx // 3
                if sec.nrm and yawj ~= 0.0 then
                    local N = {}
                    for i = 1, #sec.nrm - 2, 3 do
                        local nx, ny = sec.nrm[i], sec.nrm[i + 1]
                        N[i], N[i + 1], N[i + 2] = nx * cy - ny * sy, nx * sy + ny * cy, sec.nrm[i + 2]
                    end
                    c.nrm = N
                end
                for i = 1, #c.pos - 2, 3 do
                    bx0, bx1 = math.min(bx0, c.pos[i]), math.max(bx1, c.pos[i])
                    by0, by1 = math.min(by0, c.pos[i + 1]), math.max(by1, c.pos[i + 1])
                end
                data.sections[#data.sections + 1] = c
            end
            local nl = j.no_lava
            -- (where it lies, for its tune: G.run_section_tick)
            data.join_regions = data.join_regions or {}
            data.join_regions[#data.join_regions + 1] = { scene = j.scene, music = j.music, x0 = bx0, x1 = bx1, y0 = by0, y1 = by1 }
            -- (its climbing holds - G.EXTRA_HOLDS - and its plain ledges - ledges.lua M.PLAIN - moved with it: boxes, so a
            -- quarter turn keeps them boxes)
            local dzz = T[3] - F[3]
            local function tbox(b)
                local ax, ay = tp(b[1], b[3], 0.0)
                local cx, cy2 = tp(b[2], b[4], 0.0)
                return { math.min(ax, cx), math.max(ax, cx), math.min(ay, cy2), math.max(ay, cy2), b[5] + dzz, b[6] + dzz }
            end
            data.joined_holds = data.joined_holds or {}
            for _, h in ipairs(G.EXTRA_HOLDS[j.scene] or {}) do
                local c = copy(h)
                local boxes = h.boxes
                if not boxes then
                    local wx, out, y0, y1, top, dep, ht = h[1], h[2], h[3], h[4], h[5], h[6], h[7]
                    boxes = { { wx, wx + out * dep, y0, y1, top - ht, top } }
                end
                local nb = {}
                for _, b in ipairs(boxes) do
                    if b.line then
                        local L = b.line
                        local ax, ay = tp(L[1], L[2], 0.0)
                        local cx, cy2 = tp(L[3], L[4], 0.0)
                        local q = copy(b)
                        q.line = { ax, ay, cx, cy2 }
                        q.n = { b.n[1] * cy - b.n[2] * sy, b.n[1] * sy + b.n[2] * cy }
                        q.z0, q.z1 = b.z0 + dzz, b.z1 + dzz
                        nb[#nb + 1] = q
                    else
                        nb[#nb + 1] = tbox(b)
                    end
                end
                c.boxes = nb
                for k = 1, 7 do c[k] = nil end
                if h.oz then c.oz = h.oz + dzz end
                local lk = h.look or G.HOLD_LOOK[j.scene]
                if lk then
                    c.look = copy(lk)
                    if lk.oz then c.look.oz = lk.oz + dzz end
                    if not h.oz and lk.oz then c.oz = lk.oz + dzz end
                end
                data.joined_holds[#data.joined_holds + 1] = c
            end
            data.joined_plain = data.joined_plain or {}
            do
                local LG = package.loaded["ledges"]
                for _, b in ipairs((LG and LG.PLAIN and LG.PLAIN[j.scene]) or {}) do data.joined_plain[#data.joined_plain + 1] = tbox(b) end
            end
            local ri = #data.join_regions
            for _, m in ipairs(src.collision or {}) do
                local c = copy(m)
                c.pos = mv(m.pos)
                c.idx = undropped(m.pos, m.idx)
                c.ntris = #c.idx // 3
                -- (no lava: its sea bed out - the triangles lying flat at its height)
                if nl and c.idx then
                    local keep, P, I = {}, m.pos, c.idx
                    for t = 1, #I - 2, 3 do
                        local bed = true
                        for k = 0, 2 do
                            if math.abs(P[I[t + k] * 3 + 3] - nl.bed) > 2.0 then bed = false; break end
                        end
                        if not bed then keep[#keep + 1], keep[#keep + 2], keep[#keep + 3] = I[t], I[t + 1], I[t + 2] end
                    end
                    c.idx, c.ntris = keep, #keep // 3
                end
                mark_floors(c, ri)
                data.collision[#data.collision + 1] = c
            end
            for _, f in ipairs(src.floors or {}) do
                if not (nl and f.tag == "lava") then
                    local c = copy(f)
                    c.pos = mv(f.pos)
                    -- (its winds turned with it - their way a Mario 64 angle)
                    local wa = tonumber(tostring(f.tag or ""):match("^wind:(%d+)$"))
                    if wa then c.tag = "wind:" .. math.floor((wa - yawj * 65536.0 / 360.0) % 65536.0 + 0.5) % 65536 end
                    -- (its death plane under it as it now lies and no further: under another course it would take him
                    -- off its floors)
                    if f.tag == "death" and bx0 < bx1 then
                        local m = 600.0
                        c = death_rect(bx0 - m, bx1 + m, by0 - m, by1 + m, c.pos[3])
                    end
                    data.floors[#data.floors + 1] = c
                end
            end
            if nl then
                -- (under all of it as it now lies, and no further: under the Dark World it would take him off its floors)
                local m = nl.margin or 600.0
                local _, _, z = tp(F[1], F[2], nl.death)
                data.floors[#data.floors + 1] = death_rect(bx0 - m, bx1 + m, by0 - m, by1 + m, z)
            end
            -- (its ways: into its own places and out into Bowser's arena; not its death exits - the first course's hold)
            for _, w in ipairs(src.warps or {}) do
                if w.id < 0xF0 then
                    local c = copy(w)
                    c.id = w.id + j.ids
                    if w.scene == j.scene then c.scene, c.node = name, w.node + j.ids end
                    data.warps[#data.warps + 1] = c
                end
            end
            for _, nd in ipairs(src.nodes or {}) do
                local c = copy(nd)
                c.id = nd.id + j.ids
                c.src_scene, c.src_id = j.scene, nd.id          -- (its own course's node: G.arrive)
                if nd.pos then c.pos = { tp(nd.pos[1], nd.pos[2], nd.pos[3]) } end
                c.yaw = (nd.yaw or 0.0) + yawj
                data.nodes[#data.nodes + 1] = c
            end
            for _, o in ipairs(src.objects or {}) do
              local gone = false
              for _, q in ipairs(j.drop_objects or {}) do
                  -- (a creature by its type and Mario 64 place; a platform by its behaviour and its place, Mario 64's units)
                  local at = o.sm64 or (o.kind == "platform" and o.pos)
                  if (o.type == q[1] or o.bhv == q[1]) and at and math.abs(at[1] - q[2]) < 60.0 and math.abs(at[2] - q[3]) < 60.0
                     and math.abs(at[3] - q[4]) < 60.0 then gone = true end
              end
              local cut = nil
              for _, q in ipairs(j.cut_objects or {}) do
                  local at = o.sm64 or (o.kind == "platform" and o.pos)
                  if (o.type == q[1] or o.bhv == q[1]) and at and math.abs(at[1] - q[2]) < 60.0 and math.abs(at[2] - q[3]) < 60.0
                     and math.abs(at[3] - q[4]) < 60.0 then cut = q end
              end
              if not gone and not (j.drop_kinds and j.drop_kinds[o.kind]) then
                local c = copy(o)
                if cut and o.tpl and data.templates and data.templates[o.tpl] then
                    c.tpl = G.cut_template(data.templates, o.tpl, cut.box, cut.tag)
                end
                if o.kind == "platform" then
                    -- (a platform's place, track and turn in Mario 64's terms: its yaw against the scene's)
                    if o.pos then c.pos = { tsm(o.pos[1], o.pos[2], o.pos[3]) } end
                    if o.path then
                        local path = {}
                        for i, pt in ipairs(o.path) do
                            local q = copy(pt)
                            q[2], q[3], q[4] = tsm(pt[2], pt[3], pt[4])
                            path[i] = q
                        end
                        c.path = path
                    end
                    local a = o.ang or { 0, 0, 0 }
                    c.ang = { a[1], a[2] - yawj, a[3] }
                    -- (the ones that move along x = cos, z = sin of their angle - Mario 64's obj_set_dist_from_home and its
                    -- like: the sliding blocks, the back-and-forth platforms - turn the other way for the same angle: their
                    -- way turned again, twice the course's turn, platforms.lua P.add. The Fire Sea's sliding block went
                    -- back through its elevator - "a block just came through elevator?", 2026-11-03)
                    if o.bhv == "slide2" or o.bhv == "bf" then c.move_turn = 2.0 * yawj end
                else
                    if o.pos then c.pos = { tp(o.pos[1], o.pos[2], o.pos[3]) } end
                    if o.sm64 then c.sm64 = { tsm(o.sm64[1], o.sm64[2], o.sm64[3]) } end
                    c.yaw = (o.yaw or 0.0) + yawj
                    if (o.kind == "warp" or o.kind == "pipe" or o.kind == "fading_warp") and o.node then c.node = o.node + j.ids end
                end
                c.joined_from = j.scene
                data.objects[#data.objects + 1] = c
              end
            end
            for _, e in ipairs((lib.load_data("data.movtex") or {})[j.scene] or {}) do
                local lava = tostring(e.texture or ""):find("lava") or tostring(e.id or ""):find("LAVA")
                if not (nl and lava) then
                    local c = copy(e)
                    if e.verts then c.verts = mv(e.verts) end
                    data.movtex_extra[#data.movtex_extra + 1] = c
                end
            end
            n = n + 1
            log("bowser run: %s joined on after %s (%d pieces, %d things)", j.scene, name, #(src.sections or {}), #(src.objects or {}))
        end
    end
    -- (the run's one tune - G.GAUNTLET.music - for the level and every course joined on: G.run_section_tick has nothing
    -- to change)
    local tune = G.GAUNTLET and G.GAUNTLET.music
    if tune then
        data.music = tune
        for _, r in ipairs(data.join_regions or {}) do r.music = tune end
    end
    -- (the lava race's sea under it all - G.RUN_LAVA - out past every side of the level as it now lies: only seen, moved
    -- each frame by G.lava_race_tick; and its START and FINISH lines)
    local lv = G.RUN_LAVA and G.RUN_LAVA[name]
    if lv then
        local x0, x1, y0, y1 = 1e9, -1e9, 1e9, -1e9
        for _, m in ipairs(data.collision) do
            local P = m.pos or {}
            for i = 1, #P - 2, 3 do
                if P[i] < x0 then x0 = P[i] end
                if P[i] > x1 then x1 = P[i] end
                if P[i + 1] < y0 then y0 = P[i + 1] end
                if P[i + 1] > y1 then y1 = P[i + 1] end
            end
        end
        if x0 < x1 and y0 < y1 then
            local mg, z, tile = lv.margin or 40000.0, lv.z, lv.tile or 3072.0
            x0, x1, y0, y1 = x0 - mg, x1 + mg, y0 - mg, y1 + mg
            local tu, tv = (x1 - x0) / tile, (y1 - y0) / tile
            data.movtex_extra[#data.movtex_extra + 1] = { id = "MOVTEX_RUN_LAVA_SEA",
                texture = lv.texture or "movtex_texture_waterbox_lava",
                verts = { x0, y0, z, x1, y0, z, x1, y1, z, x0, y1, z }, tris = { 0, 1, 2, 0, 2, 3 },
                uv = { 0.0, 0.0, tu, 0.0, tu, tv, 0.0, tv }, color = { 1.0, 1.0, 1.0, 1.0 }, translucent = false,
                -- (its corners' UVs never moved: it slides by its material - G.lava_race_tick)
                speed = 0.0 }
            log("bowser run: the lava race's sea under %s (%.0f x %.0f m)", name, (x1 - x0) / 100.0, (y1 - y0) / 100.0)
        end
        -- (each line an arch over the way: a post each side, a banner across their tops - its name on both faces - and a
        -- checker strip on the floor; only seen, nothing to hold or stand on)
        local ok, err = pcall(function()
            local secs = {}
            local LX, LY, LZ = -0.4, -0.3, 0.866
            local function face(tex, P, UV, N)
                local s = secs[tex]
                if not s then
                    s = { layer = "opaque", texture = tex, pos = {}, uv = {}, col = {}, nrm = {}, idx = {} }
                    secs[tex] = s
                    secs[#secs + 1] = s
                end
                local A, B, C = P[1], P[2], P[3]
                local ux, uy, uz = B[1] - A[1], B[2] - A[2], B[3] - A[3]
                local wx, wy, wz = C[1] - A[1], C[2] - A[2], C[3] - A[3]
                local cx, cy, cz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
                -- (wound as the level's own: (B - A) x (C - A) against N)
                local order = { 1, 2, 3, 4 }
                if cx * N[1] + cy * N[2] + cz * N[3] > 0 then order = { 1, 4, 3, 2 } end
                local k = 0.62 + 0.38 * math.max(0.0, N[1] * LX + N[2] * LY + N[3] * LZ)
                local sb = #s.pos // 3
                for _, i in ipairs(order) do
                    local p, uv = P[i], UV[i]
                    s.pos[#s.pos + 1], s.pos[#s.pos + 2], s.pos[#s.pos + 3] = p[1], p[2], p[3]
                    s.uv[#s.uv + 1], s.uv[#s.uv + 2] = uv[1], uv[2]
                    s.col[#s.col + 1], s.col[#s.col + 2], s.col[#s.col + 3], s.col[#s.col + 4] = k, k, k, 1.0
                    s.nrm[#s.nrm + 1], s.nrm[#s.nrm + 2], s.nrm[#s.nrm + 3] = N[1], N[2], N[3]
                end
                for _, q in ipairs({ 0, 1, 2, 0, 2, 3 }) do s.idx[#s.idx + 1] = sb + q end
            end
            -- a box on the floor: its foot's middle (cx, cy), the way f and across r (unit), half sizes along them, z0..z1;
            -- `front`/`back` the picture on its faces across the way (seen the right way round from each side), `rest`
            -- on the others (a repeat each `per` cm)
            local function box(cx, cy, f, r, hf, hr, z0, z1, front, back, rest, per)
                local function at(a, b, z) return { cx + f[1] * a + r[1] * b, cy + f[2] * a + r[2] * b, z } end
                local function rep(len) return len / per end
                face(front, { at(-hf, -hr, z1), at(-hf, hr, z1), at(-hf, hr, z0), at(-hf, -hr, z0) },
                     { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } }, { -f[1], -f[2], 0.0 })
                face(back, { at(hf, hr, z1), at(hf, -hr, z1), at(hf, -hr, z0), at(hf, hr, z0) },
                     { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } }, { f[1], f[2], 0.0 })
                local hz = rep(z1 - z0)
                face(rest, { at(-hf, hr, z1), at(hf, hr, z1), at(hf, hr, z0), at(-hf, hr, z0) },
                     { { 0, 0 }, { rep(2 * hf), 0 }, { rep(2 * hf), hz }, { 0, hz } }, { r[1], r[2], 0.0 })
                face(rest, { at(hf, -hr, z1), at(-hf, -hr, z1), at(-hf, -hr, z0), at(hf, -hr, z0) },
                     { { 0, 0 }, { rep(2 * hf), 0 }, { rep(2 * hf), hz }, { 0, hz } }, { -r[1], -r[2], 0.0 })
                face(rest, { at(-hf, -hr, z1), at(hf, -hr, z1), at(hf, hr, z1), at(-hf, hr, z1) },
                     { { 0, 0 }, { rep(2 * hf), 0 }, { rep(2 * hf), rep(2 * hr) }, { 0, rep(2 * hr) } }, { 0.0, 0.0, 1.0 })
                face(rest, { at(-hf, hr, z0), at(hf, hr, z0), at(hf, -hr, z0), at(-hf, -hr, z0) },
                     { { 0, 0 }, { rep(2 * hf), 0 }, { rep(2 * hf), rep(2 * hr) }, { 0, rep(2 * hr) } }, { 0.0, 0.0, -1.0 })
            end
            local CK = "race_checker"
            for _, ln in ipairs({ { (not lv.start_hidden) and lv.start or false, lv.start_w, "race_start", lv.start_h,
                                    lv.start_down },
                                  { (not lv.finish_hidden) and lv.finish or false, lv.finish_w, "race_finish", lv.finish_h,
                                    lv.finish_down } }) do
                local L, hw, tex = ln[1], ln[2], ln[3]
                local H, down = ln[4] or 330.0, ln[5] or 0.0
                local k = H / 330.0
                if L then
                    local a = math.rad(L[4])
                    local f = { math.cos(a), math.sin(a) }
                    local r = { -f[2], f[1] }                   -- (the runner's right, going the way across it)
                    local fz = L[3]
                    for _, sd in ipairs({ -1.0, 1.0 }) do
                        local px, py = L[1] + r[1] * sd * (hw - 10.0), L[2] + r[2] * sd * (hw - 10.0)
                        box(px, py, f, r, 10.0 * k, 10.0 * k, fz - down, fz + H, CK, CK, CK, 40.0 * k)
                    end
                    box(L[1], L[2], f, r, 5.0 * k, hw, fz + H - 68.0 * k, fz + H, tex, tex, CK, 34.0 * k)
                    -- (the strip on the floor: 50 cm along the way, the width of the arch)
                    local function at(a, b) return { L[1] + f[1] * a + r[1] * b, L[2] + f[2] * a + r[2] * b, fz + 1.5 } end
                    face(CK, { at(-25.0, -hw), at(-25.0, hw), at(25.0, hw), at(25.0, -hw) },
                         { { 0, 0 }, { 2 * hw / 100.0, 0 }, { 2 * hw / 100.0, 0.5 }, { 0, 0.5 } }, { 0.0, 0.0, 1.0 })
                end
            end
            local nid = 0
            for _, sec in ipairs(data.sections) do if (sec.id or 0) >= nid then nid = (sec.id or 0) + 1 end end
            for _, s in ipairs(secs) do
                s.id, nid = nid, nid + 1
                s.nverts, s.ntris = #s.pos // 3, #s.idx // 3
                data.sections[#data.sections + 1] = s
            end
        end)
        if not ok then log("lava race: its lines not made: %s", tostring(err)) end
    end
    return n
end

-- The lava race's kept paces, by scene: { dt = s between them, h = { the ground's height each dt from START } }, in
-- lava_race.lua in the mod's folder (G.RUN_LAVA)
function G.lava_race_kept()
    if G.lava_paces then return G.lava_paces end
    G.lava_paces = {}
    local f = io.open(lib.MOD_DIR .. "lava_race.lua", "rb")
    if f then
        local src = f:read("a")
        f:close()
        local fn = load(src, "lava_race", "t", {})
        local ok, t = pcall(fn or function() return nil end)
        if ok and type(t) == "table" then G.lava_paces = t end
    end
    return G.lava_paces
end
-- one kept (nil: that scene's thrown away - a new pace recorded on the next run)
function G.lava_race_save(scene, rec)
    local all = G.lava_race_kept()
    all[scene] = rec
    local parts = { "-- the lava race's kept paces (written by the mod: game.lua G.RUN_LAVA)\nreturn {\n" }
    for sc, r in pairs(all) do
        local hs = {}
        for i, h in ipairs(r.h or {}) do hs[i] = string.format("%.1f", h) end
        parts[#parts + 1] = string.format("  [%q] = { dt = %.3f, h = { %s } },\n", sc, r.dt or 0.1, table.concat(hs, ", "))
    end
    parts[#parts + 1] = "}\n"
    local f = io.open(lib.MOD_DIR .. "lava_race.lua", "wb")
    if not f then log("lava race: could not write its paces"); return false end
    f:write(table.concat(parts))
    f:close()
    return true
end

-- Each frame in the run: the lava race (G.RUN_LAVA) - START and FINISH passed, the pace recorded or played back, the
-- lava's sheet moved to its height, and caught by it.
function G.lava_race_tick(pawn, dt)
    local d = G.data
    local cfg = G.RUN_LAVA and G.RUN_LAVA[G.name or ""]
    if not (d and cfg and G.gauntlet and d.joined and pawn) then return end
    -- (the way back from the last fight, out of the pipe: STORROR's own ragdoll - its flail, his fall off Bowser's stage
    -- carried over - stopped the moment it begins, so that he comes up out of the pipe on his feet; limp, he dropped down
    -- the deep pipe - G.arrive)
    if G.entry and G.entry.pipe and G.entry.death then
        local RG = package.loaded["ragdoll"]
        local okl, limp = pcall(function() return RG and RG.limp and RG.limp() end)
        if okl and limp and RG.up_now then
            pcall(RG.up_now, true)
            log("pipe exit: STORROR's ragdoll stopped")
        end
    end
    local S = d.lava_race
    if not S then
        S = { phase = "wait", z = cfg.z, want = cfg.z }
        -- (back from the last fight by a death there: the race as it was when he went into its pipe - G.goto_scene keeps it;
        -- the level comes back new, and the lava was down at its start: "2 the lava should be there", 2026-11-03)
        local K = G.lava_resume
        G.lava_resume = nil
        if K and os.clock() - (K.at or 0.0) < 60.0 and K.z then
            S.phase, S.z, S.want, S.rec, S.t, S.ground = K.phase or "done", K.z, K.want or K.z, K.rec, K.t or 0.0, K.ground
            -- (the race over, or never run - put at the top some other way: the lava up at the top, as close under the
            -- FINISH as the race brings it, where he comes out of the pipe - not left down where it was outrun)
            if (S.phase == "wait" or S.phase == "done") and cfg.finish then
                S.phase, S.z = "done", math.max(S.z, cfg.finish[3] - (cfg.below or 200.0))
                S.want = S.z
            end
            -- (and not touching him for 4 s while he comes back)
            S.grace_until = os.clock() + 4.0
            log("lava race: back from the last fight - the lava where it was (%s, %.0f)", tostring(S.phase), S.z)
        end
        d.lava_race = S
    end
    -- (the sheet: movtex's surface, its actor where it was made)
    if not S.s then
        local MT = package.loaded["movtex"]
        local s = MT and MT.surface and MT.surface("MOVTEX_RUN_LAVA_SEA")
        if s and s.actor and pcall(function() return s.actor:IsValid() end) and s.actor:IsValid() then
            -- (where the scene put it - its origin, movtex.lua's load - not where it is now: a race taken up again at a
            -- checkpoint found it raised by the last one, and put it that much higher again, over him - "lava is above
            -- player now??", 2026-11-03)
            S.s, S.base = s, { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z }
        end
    end
    -- (its picture slid by its material's offset, a float in the shader - not by its corners' UVs, which the engine keeps
    -- as half floats: on a sheet 300 tiles across they moved a quarter tile at a time, and the picture skipped sideways as
    -- it slid - "the texture keeps jumping", "Pattern skips sideways", 2026-11-03. Wrapped at 40: whole pictures whether
    -- the offset is taken before the scale or after it, at RENDER 96's 2.2 and a tiled copy's 1/2, 1/4, 1/8 alike)
    if S.s and S.s.pmc and cfg.speed and cfg.speed ~= 0.0 then
        if S.mid == nil then
            S.mid = false
            pcall(function()
                -- (a material of its own, not the one every surface with its picture shares: the metal cap's picture is
                -- Metal Mario's chrome too, mariolook.lua, and the slide and the size went onto his cap - lib.get_mid's
                -- key takes the "alpha" even for an opaque one, so 0.99 is a copy of its own)
                local mt = nil
                if cfg.texture then
                    mt = lib.get_mid(lib.world(), "opaque", cfg.texture, 0.99)
                    if mt and mt:IsValid() then S.s.pmc:SetMaterial(0, mt) else mt = nil end
                end
                mt = mt or S.s.pmc:GetMaterial(0)
                if mt and mt:IsValid() then
                    local su, sv = 1.0, 1.0
                    pcall(function()
                        local v = mt:K2_GetVectorParameterValue(FName("BaseColorTexture_OffsetScale"))
                        if v and v.B and v.B > 0.0 then su, sv = v.B, (v.A and v.A > 0.0) and v.A or v.B end
                    end)
                    S.mid, S.msu, S.msv, S.moff = mt, su, sv, 0.0
                end
            end)
        end
        if S.mid and cfg.chrome then
            -- (laid on by facing, not slid: the picture whole, once - G.lava_chrome)
            if not S.mset then
                S.mset = true
                pcall(function()
                    local v = { R = 0.0, G = 0.0, B = 1.0, A = 1.0 }
                    S.mid:SetVectorParameterValue(FName("BaseColorTexture_OffsetScale"), v)
                    S.mid:SetVectorParameterValue(FName("EmissiveTexture_OffsetScale"), v)
                end)
            end
        elseif S.mid then
            S.moff = (S.moff + cfg.speed * dt * 30.0 * S.msu) % 40.0
            local v = { R = S.moff, G = 0.0, B = S.msu, A = S.msv }
            pcall(function()
                S.mid:SetVectorParameterValue(FName("BaseColorTexture_OffsetScale"), v)
                S.mid:SetVectorParameterValue(FName("EmissiveTexture_OffsetScale"), v)
            end)
        end
    end
    local l = pawn:K2_GetActorLocation()
    local x, y = l.X - OFFSET.X, l.Y - OFFSET.Y
    local feet = l.Z - OFFSET.Z - (G.half or 90.0)
    -- (on the ground: walking on it, STORROR's mode 1 - not its climbs, vaults and wall moves, which are not falling
    -- either: the lava went up with every one and back down after - "fix the lava stuttering", 2026-11-03)
    local grounded = false
    pcall(function() grounded = pawn.CharacterMovement.MovementMode == 1 end)
    -- (and on a pole or a tree, up or down it, and over its top: climb.lua - his feet are his ground there; "while I was
    -- climbing a pole the lava didnt follow", 2026-11-03)
    if not grounded then
        local CL = package.loaded["climb"]
        local okc, on = pcall(function() return CL and CL.active and CL.active() end)
        if (okc and on) or G.carried == "pole" then grounded = true end
    end
    local below = cfg.below or 200.0
    local function across(L)
        local a = math.rad(L[4])
        local fx, fy = math.cos(a), math.sin(a)
        local rx, ry = x - L[1], y - L[2]
        return rx * fx + ry * fy, -rx * fy + ry * fx
    end
    local function sound(n) local SX = package.loaded["sfx"]; if SX then pcall(SX.play, n, 1.0) end end
    -- (the ground he is on: his feet on the ground; in the air the ground he left, or lower as he drops under it)
    if grounded or S.ground == nil then S.ground = feet elseif feet < S.ground then S.ground = feet end
    if S.phase == "wait" then
        local sf, sl = across(cfg.start)
        local wide = (cfg.start_w or 225.0) + (cfg.start_reach or 60.0)
        -- (behind it once - anywhere along it - then past it: however fast, from a run, a jump or a dive over it)
        if sf < 0.0 and math.abs(sl) <= wide then S.behind = true end
        if S.behind and sf >= 0.0 and math.abs(sl) <= wide
            and feet > cfg.start[3] - (cfg.start_below or 400.0) and feet < cfg.start[3] + (cfg.start_above or 900.0) then
            local kept = G.lava_race_kept()[G.name]
            S.t = 0.0
            if kept and kept.h and #kept.h > 1 then
                S.phase, S.rec = "chase", kept
                log("lava race: START - the lava follows your kept pace (%.1f s to the top)", #kept.h * (kept.dt or 0.1))
            else
                S.phase, S.rec = "record", { dt = cfg.rec_dt or 0.1, h = {} }
                log("lava race: START - your pace recorded")
            end
            -- (silent: "also remove the sound of going past the start", 2026-11-03)
        end
        S.sf = sf
    end
    if S.phase == "record" or S.phase == "chase" then
        S.t = S.t + dt
        local R = S.rec
        if S.phase == "record" then
            local need = math.floor(S.t / R.dt) + 1
            while #R.h < need do R.h[#R.h + 1] = S.ground end
            S.want = S.ground - below
        else
            -- (`chase_delay` s behind the kept pace: the dip after START, left in 3 s on the kept run, caught him 3.8 s in -
            -- "Yes, 2 s delay", 2026-11-03)
            -- (the lowest the kept pace is at over its next `chase_low` s, not where it is: it went up after his every
            -- ledge, pole and jump - the kept run's - and came up over him on the floor under them: "liquid comes up too
            -- high sometimes", 2026-11-04. Worked out once a race, on the race's own table, not the kept one)
            if not S.low then
                local h, n = R.h, #R.h
                local w = math.max(1, math.floor((cfg.chase_low or 8.0) / R.dt + 0.5))
                local low = {}
                for i = 1, n do
                    local m = h[i]
                    for j = i + 1, math.min(n, i + w) do if h[j] < m then m = h[j] end end
                    low[i] = m
                end
                S.low = low
            end
            local L = S.low
            local k = math.max(0.0, S.t - (cfg.chase_delay or 0.0)) / R.dt
            local i = math.floor(k)
            local a, b = L[math.min(#L, i + 1)], L[math.min(#L, i + 2)]
            S.want = a + (b - a) * (k - i) - below
        end
        -- FINISH: past its line, or anywhere on the top beyond it
        local F = cfg.finish
        local ff, fl = across(F)
        if ff >= 0.0 and math.abs(fl) <= (cfg.finish_zone or 900.0) and feet > F[3] - 100.0 then
            if S.phase == "record" then
                local saved = G.lava_race_save(G.name, R)
                log("lava race: FINISH - your pace kept (%.1f s, %s): from now on the lava follows it", S.t, tostring(saved))
            else
                log("lava race: FINISH - you beat the lava (%.1f s; its pace %.1f s)", S.t, #R.h * R.dt)
            end
            S.phase = "done"
            -- (silent: "also turn off the race finish audio at the top", 2026-11-03)
        end
    end
    -- the sheet glides to its height (recording: never up to him)
    -- (and no faster than `max_speed` cm/s, so a jump in the height it wants is a steady rise)
    do
        local step = (S.want - S.z) * math.min(1.0, dt * (cfg.glide or 2.5))
        local cap = (cfg.max_speed or 350.0) * dt
        if step > cap then step = cap elseif step < -cap then step = -cap end
        S.z = S.z + step
    end
    if S.phase == "record" and S.z > feet - below then S.z = feet - below end
    -- (the deep pipe at the top, found once - cfg.pipe_lid: the lid over the liquid down it, below, and the liquid drawn
    -- far under while the camera is down it, following him in: under the lid it showed again, "I can still see it in the
    -- pipe", 2026-11-04. Down a pipe nothing outside it is seen, so the move is never seen)
    local PLID = cfg.pipe_lid
    if PLID and cfg.finish and S.lid_pipe == nil then
        S.lid_pipe = false
        local F = cfg.finish
        for _, w in ipairs(G.warps or {}) do
            if w.kind == "pipe" and (w.x - F[1]) ^ 2 + (w.y - F[2]) ^ 2 < 2000.0 * 2000.0 then S.lid_pipe = w end
        end
    end
    local cam_in_pipe = false
    if PLID and S.lid_pipe then
        local wp = S.lid_pipe
        local okc, cl = pcall(function() return lib.controller().PlayerCameraManager:GetCameraLocation() end)
        if okc and cl then
            local cx, cy, cz = cl.X - OFFSET.X, cl.Y - OFFSET.Y, cl.Z - OFFSET.Z
            cam_in_pipe = (cx - wp.x) ^ 2 + (cy - wp.y) ^ 2 < 110.0 * 110.0 and cz < wp.z + 160.0
                and cz > wp.z - PLID.depth - 300.0
        end
    end
    if S.s and S.base then
        local zz = S.base.Z + (S.z - cfg.z)
        -- (its swell, seen only - and never up within `bob_gap` cm of his feet: "but always below 180cm", 2026-11-03)
        if cfg.bob then
            local tt = os.clock()
            local b = cfg.bob * math.sin(tt * 2.0 * math.pi / (cfg.bob_period or 5.0))
                + (cfg.bob2 or 0.0) * math.sin(tt * 2.0 * math.pi / (cfg.bob2_period or 1.7) + 1.1)
            -- (and with the ripples' highest crest on top of it)
            local crest = 0.0
            if cfg.chrome then for _, w in ipairs(cfg.chrome.waves or {}) do crest = crest + (cfg.chrome.amp or 0.0) * w[4] end end
            if b > 0.0 then b = math.min(b, math.max(0.0, (feet - (cfg.bob_gap or 180.0) - crest) - S.z)) end
            zz = zz + b
            S.vis = S.z + b
        else
            S.vis = S.z
        end
        if cam_in_pipe then zz = zz - 3000.0 end
        if not S.last_zz or math.abs(zz - S.last_zz) > 0.05 then
            local okv = pcall(function() return S.s.actor:IsValid() end) and S.s.actor:IsValid()
            if okv then
                pcall(function() S.s.actor:K2_SetActorLocation({ X = S.base.X, Y = S.base.Y, Z = zz }, false, {}, true) end)
                S.last_zz = zz
            else
                S.s, S.base = nil, nil
            end
        end
        if cfg.chrome and S.s and S.mid then
            local okc, ec = pcall(G.lava_chrome, S, cfg, zz, l)
            if not okc and not G.chrome_err then G.chrome_err = true; log("lava chrome: %s", tostring(ec)) end
        end
    end
    -- (the deep pipe at the top: no liquid seen down it - the lava stands 350 cm down its shaft once the race is done, and
    -- a dark lid lies across the shaft just over its highest ripple, following it, the shaft dark from there on down as it
    -- is under the lid's height anyway; drawn only - he falls through it, and the liquid under it ignores him in the pipe,
    -- below. "no you just lowered the liquid, I just dont want it in the pipe", 2026-11-04)
    if PLID and cfg.finish and S.vis then
        local w = S.lid_pipe
        if w then
            local crest = 0.0
            if cfg.chrome then for _, wv in ipairs(cfg.chrome.waves or {}) do crest = crest + (cfg.chrome.amp or 0.0) * wv[4] end end
            local lz = S.vis + crest + 6.0
            local show = lz > w.z - PLID.depth and lz < w.z - 20.0
            local L = S.lid
            if L and not (pcall(function() return L.actor:IsValid() end) and L.actor:IsValid()) then L, S.lid = nil, nil end
            if show and not L then
                local world = lib.world()
                local actor = world and lib.spawn_actor(world, { X = OFFSET.X + w.x, Y = OFFSET.Y + w.y, Z = OFFSET.Z + lz }, 0.0)
                local pmc = actor and lib.add_pmc(actor)
                if pmc then
                    pcall(function() pmc:SetCollisionEnabled(0) end)
                    pcall(function() pmc:SetCastShadow(false) end)
                    if G.extras then G.extras[#G.extras + 1] = actor end            -- (gone with the scene)
                    local verts, uvs = { { X = 0.0, Y = 0.0, Z = 0.0 } }, { { X = 0.5, Y = 0.5 } }
                    local nrm, cols, idx = { { X = 0.0, Y = 0.0, Z = 1.0 } }, { { R = 0.0, G = 0.0, B = 0.0, A = 1.0 } }, {}
                    for k = 0, 7 do
                        local a = math.rad(k * 45.0)
                        verts[#verts + 1] = { X = math.cos(a) * PLID.r, Y = math.sin(a) * PLID.r, Z = 0.0 }
                        uvs[#uvs + 1] = { X = 0.5 + 0.5 * math.cos(a), Y = 0.5 + 0.5 * math.sin(a) }
                        nrm[#nrm + 1] = { X = 0.0, Y = 0.0, Z = 1.0 }
                        cols[#cols + 1] = { R = 0.0, G = 0.0, B = 0.0, A = 1.0 }
                    end
                    for k = 1, 8 do
                        local b = k % 8 + 1
                        for _, t in ipairs({ 0, k, b, 0, b, k }) do idx[#idx + 1] = t end    -- (both faces)
                    end
                    lib.create_section(pmc, 0, verts, idx, nrm, uvs, cols, false)
                    local mt = lib.get_mid(world, "opaque", PLID.texture)
                    if mt then pcall(function() pmc:SetMaterial(0, mt) end) end
                    L = { actor = actor, z = lz, shown = true }
                    S.lid = L
                    log("lava race: the pipe at the top lidded over the liquid (%.0f)", lz)
                end
            end
            if L then
                if show ~= L.shown then
                    L.shown = show
                    pcall(function() L.actor:SetActorHiddenInGame(not show) end)
                end
                if show and math.abs(lz - L.z) > 0.5 then
                    L.z = lz
                    pcall(function() L.actor:K2_SetActorLocation({ X = OFFSET.X + w.x, Y = OFFSET.Y + w.y, Z = OFFSET.Z + lz }, false, {}, true) end)
                end
            end
        end
    end
    -- touched: his feet in the liquid as it is seen, whatever the race is doing - a life, and the run again ("also if the
    -- liquid touches you once its death", 2026-11-03)
    -- (not in a pipe, or over one: the Sky's at the top is deep, down past the lava's height as the race ends, and the
    -- way down it to Bowser was death - "there is liquid in the pipe that just killed me", 2026-11-04)
    local in_pipe = false
    for _, w in ipairs(G.warps or {}) do
        if w.kind == "pipe" and (x - w.x) ^ 2 + (y - w.y) ^ 2 < 130.0 * 130.0 and feet > w.z - 3000.0
            and feet < w.z + 600.0 then in_pipe = true end
    end
    if S.vis and feet <= S.vis + 5.0 and not S.touched and not G.dying and not G.pending and not G.warping
        and os.clock() >= (S.grace_until or 0.0) and not in_pipe then
        S.touched = true
        log("lava race: he touched the liquid")
        -- (a splash where he went in: Mario 64's plunge - its column - and a ring of drops round it, and its sound - "make a
        -- splash effect when the player falls in", 2026-11-03)
        local EF = package.loaded["envfx"]
        if EF then
            if EF.splash then pcall(EF.splash, x, y, S.vis) end
            if EF.wade_splash then
                for k = 0, 3 do
                    local a = k * math.pi / 2.0 + 0.4
                    pcall(EF.wade_splash, x + math.cos(a) * 45.0, y + math.sin(a) * 45.0, S.vis)
                end
            end
        end
        sound("water_plunge")
        local HP = _G.HEALTH
        if HP and HP.kill then HP.kill("touched the liquid") end
    end
    -- caught: the lava at his feet - a life, and the run again
    if S.phase == "chase" and S.z >= feet - 5.0 and not G.dying and not G.pending and not in_pipe then
        S.phase = "caught"
        log("lava race: caught by the lava (%.1f s in)", S.t)
        local HP = _G.HEALTH
        if HP and HP.kill then HP.kill("caught by the lava") end
    end
end
-- The lava race's liquid chrome (G.RUN_LAVA `chrome`): the run's chrome sky, and the lava a mirror of it - a rippling
-- patch round him and a flat coarse grid over the rest of the sheet, in the sheet's own material (S.mid, the chrome
-- ball), each corner's picture what the camera sees reflected there: the view's reflection off its facing, read off the
-- ball (a sphere map, straight up its middle). The sheet itself, a single square, hidden. `zz`: where the sheet's actor
-- stands now (world Z); `l`: his place.
-- The run's chrome sky (G.RUN_LAVA's `chrome.sky`, K): a sphere of its own just inside the scene's sky, K.r round and
-- K.up over the scene's middle, the panorama K.tex round it - the run's level's (G.lava_chrome), and the last fight's
-- too, the run's own ("wheres the new texture for the backround that we made?", 2026-11-03: the last fight had the Sky's
-- own clouds). Gone with the scene (G.extras). Its actor, or nil.
function G.chrome_sky_up(K)
    local world = lib.world()
    if not (world and K) then return nil end
    local actor = lib.spawn_actor(world, { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z + (K.up or 900.0) }, 0.0)
    local pmc = actor and lib.add_pmc(actor)
    local mid = lib.get_mid(world, "opaque", K.tex, 0.99)
    if not (pmc and mid) then return nil end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    if G.extras then G.extras[#G.extras + 1] = actor end
    local verts, uvs, nrm, cols, idx = {}, {}, {}, {}, {}
    local na, nr = K.around, K.rings
    for k = 0, nr do
        local e = -math.pi / 2.0 + math.pi * k / nr
        for i = 0, na do
            local a = 2.0 * math.pi * i / na
            local dx, dy, dz = math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)
            verts[#verts + 1] = { X = K.r * dx, Y = K.r * dy, Z = K.r * dz }
            uvs[#uvs + 1] = { X = i / na, Y = 0.5 - e / math.pi }
            nrm[#nrm + 1] = { X = -dx, Y = -dy, Z = -dz }
            cols[#cols + 1] = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
        end
    end
    for k = 0, nr - 1 do
        for i = 0, na - 1 do
            local a = k * (na + 1) + i
            local b, c, d = a + 1, a + na + 2, a + na + 1
            for _, t in ipairs({ a, b, c, a, c, d, a, c, b, a, d, c }) do idx[#idx + 1] = t end
        end
    end
    lib.create_section(pmc, 0, verts, idx, nrm, uvs, cols, false)
    pmc:SetMaterial(0, mid)
    return actor
end

function G.lava_chrome(S, cfg, zz, l)
    local C = cfg.chrome
    local world = lib.world()
    if not world then return end
    S.cf = (S.cf or 0) + 1
    local function alive(a) return a and pcall(function() return a:IsValid() end) and a:IsValid() end
    local function grid(n)
        local actor = lib.spawn_actor(world, { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z }, 0.0)
        local pmc = actor and lib.add_pmc(actor)
        if not pmc then return nil end
        pcall(function() pmc:SetCollisionEnabled(0) end)
        pcall(function() pmc:SetCastShadow(false) end)
        if G.extras then G.extras[#G.extras + 1] = actor end            -- (gone with the scene)
        local verts, uvs, nrm, cols, idx = {}, {}, {}, {}, {}
        for _ = 0, n do
            for _ = 0, n do
                verts[#verts + 1] = { X = 0.0, Y = 0.0, Z = 0.0 }
                uvs[#uvs + 1] = { X = 0.5, Y = 0.5 }
                nrm[#nrm + 1] = { X = 0.0, Y = 0.0, Z = 1.0 }
                cols[#cols + 1] = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
            end
        end
        for j = 0, n - 1 do
            for i = 0, n - 1 do
                local a = j * (n + 1) + i
                local b, c, d = a + 1, a + n + 2, a + n + 1
                for _, t in ipairs({ a, b, c, a, c, d, a, c, b, a, d, c }) do idx[#idx + 1] = t end    -- (both faces)
            end
        end
        lib.create_section(pmc, 0, verts, idx, nrm, uvs, cols, false)
        pmc:SetMaterial(0, S.mid)
        return { actor = actor, pmc = pmc, verts = verts, uvs = uvs, n = n }
    end
    -- the sky, once a scene: a sphere of its own just inside the sky's, the panorama round it (G.chrome_sky_up)
    if C.sky and not alive(S.csky) then
        S.csky = G.chrome_sky_up(C.sky)
        if S.csky then log("lava race: the chrome sky up") end
    end
    -- the mirror, once a scene: rings round its middle, `around` corners each; the sheet's own square hidden under it
    local M = S.mirror
    if not (M and alive(M.actor)) then
        local actor = lib.spawn_actor(world, { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z }, 0.0)
        local pmc = actor and lib.add_pmc(actor)
        if not pmc then return end
        pcall(function() pmc:SetCollisionEnabled(0) end)
        pcall(function() pmc:SetCastShadow(false) end)
        if G.extras then G.extras[#G.extras + 1] = actor end            -- (gone with the scene)
        local A, KI, KO = C.around, C.in_rings, C.out_rings
        local R = { [0] = 0.0 }
        for k = 1, KI do R[k] = C.in_step * k end
        local r0 = R[KI]
        for k = 1, KO do R[KI + k] = r0 * (C.r_out / r0) ^ (k / KO) end
        local K = KI + KO
        local ca, sa = {}, {}
        for i = 0, A - 1 do ca[i], sa[i] = math.cos(2 * math.pi * i / A), math.sin(2 * math.pi * i / A) end
        local verts, uvs, nrm, cols, idx = {}, {}, {}, {}, {}
        for _ = 0, K do
            for _ = 0, A - 1 do
                verts[#verts + 1] = { X = 0.0, Y = 0.0, Z = 0.0 }
                uvs[#uvs + 1] = { X = 0.5, Y = 0.5 }
                nrm[#nrm + 1] = { X = 0.0, Y = 0.0, Z = 1.0 }
                cols[#cols + 1] = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
            end
        end
        for k = 0, K - 1 do
            for i = 0, A - 1 do
                local a, b = k * A + i, k * A + (i + 1) % A
                local c, d = (k + 1) * A + (i + 1) % A, (k + 1) * A + i
                for _, t in ipairs({ a, b, c, a, c, d, a, c, b, a, d, c }) do idx[#idx + 1] = t end    -- (both faces)
            end
        end
        lib.create_section(pmc, 0, verts, idx, nrm, uvs, cols, false)
        pmc:SetMaterial(0, S.mid)
        M = { actor = actor, pmc = pmc, verts = verts, uvs = uvs, R = R, K = K, KI = KI, A = A, ca = ca, sa = sa }
        S.mirror = M
        if S.s and alive(S.s.actor) then pcall(function() S.s.actor:SetActorHiddenInGame(true) end) end
    end
    pcall(function() M.actor:K2_SetActorLocation({ X = OFFSET.X, Y = OFFSET.Y, Z = zz }, false, {}, true) end)
    if S.cf % (C.every or 2) ~= 0 then return end
    local outer = S.cf % (2 * (C.every or 2)) == 0
    -- the camera, scene cm; the actor's rise (a corner's height in the scene is lift + its own)
    local cl = lib.controller().PlayerCameraManager:GetCameraLocation()
    local ex, ey, ez = cl.X - OFFSET.X, cl.Y - OFFSET.Y, cl.Z - OFFSET.Z
    local lift = zz - OFFSET.Z
    -- its middle under him, on a grid of `snap` (so its corners do not slide over the waves as he moves)
    local sn = C.snap or 300.0
    local mx = math.floor((l.X - OFFSET.X) / sn + 0.5) * sn
    local my = math.floor((l.Y - OFFSET.Y) / sn + 0.5) * sn
    local t = os.clock()
    local W, tl, A = C.waves, C.tilt or 1.0, M.A
    local wf, we = C.wave_full, C.wave_end
    local base = cfg.z + 2.0
    for k = 0, M.K do
        local r = M.R[k]
        local inner = k <= M.KI
        local a = 0.0
        if r < we then a = 1.0 - math.max(0.0, math.min(1.0, (r - wf) / (we - wf))); a = a * a * (3.0 - 2.0 * a) end
        for i = 0, A - 1 do
            local x, y = mx + r * M.ca[i], my + r * M.sa[i]
            local n = k * A + i + 1
            local h, hx, hy = 0.0, 0.0, 0.0
            if a > 0.0 then
                for _, w in ipairs(W) do
                    local ph = w[1] * x + w[2] * y + w[3] * t
                    local amp = C.amp * w[4] * a
                    h = h + amp * math.sin(ph)
                    local c = amp * math.cos(ph)
                    hx, hy = hx + c * w[1], hy + c * w[2]
                end
            end
            local vt = M.verts[n]
            vt.X, vt.Y, vt.Z = x, y, base + h
            if inner or outer then
                -- the view reflected off its facing, read off the ball (a sphere map, straight up its middle)
                local gx, gy = hx * tl, hy * tl
                local nl = math.sqrt(gx * gx + gy * gy + 1.0)
                local nx, ny, nz = -gx / nl, -gy / nl, 1.0 / nl
                local vx, vy, vz = x - ex, y - ey, lift + base + h - ez
                local vl = math.sqrt(vx * vx + vy * vy + vz * vz)
                local q = M.uvs[n]
                if vl > 1e-3 then
                    vx, vy, vz = vx / vl, vy / vl, vz / vl
                    local d = 2.0 * (vx * nx + vy * ny + vz * nz)
                    local rx, ry, rz = vx - d * nx, vy - d * ny, vz - d * nz
                    local m = 2.0 * math.sqrt(rx * rx + ry * ry + (rz + 1.0) ^ 2)
                    if m > 1e-4 then q.X, q.Y = 0.5 + rx / m, 0.5 - ry / m end
                end
            end
        end
    end
    pcall(lib.update_section, M.pmc, 0, M.verts, nil, M.uvs)
end

function G.gauntlet_objects(name, data)
    local R = G.GAUNTLET
    if not (G.gauntlet and R.courses[name] and data and data.objects) or data.gauntlet_in then return 0 end
    data.gauntlet_in = true
    local kept, red, add, coins, cut = {}, 0, {}, 0, 0
    for _, o in ipairs(data.objects) do
        if o.kind == "coin" and o.red then red = red + 1
        elseif o.kind == "red_coin_star" then
            -- (out)
        elseif o.kind == "coin" and R.half_coins and (o.value or 1) == 1 then
            coins = coins + 1
            if coins % 2 == 0 then cut = cut + 1 else kept[#kept + 1] = o end
        else
            kept[#kept + 1] = o
        end
    end
    local function fl(x, y, z) return G.floor_z(x, y, z + 100.0) end
    for _, o in ipairs(kept) do
        local doubled = o.kind == "goomba" or o.kind == "bobomb" or (o.kind == "enemy" and R.double[o.type or ""])
        if doubled and o.pos then
            local c = {}
            for k, v in pairs(o) do c[k] = v end
            local p = o.pos
            local placed = false
            if o.type == "bhvCirclingAmp" then
                o.start_ang = math.random(0, 65535)
                c.start_ang = (o.start_ang + 0x8000) % 65536
                placed = true
            else
                local f0 = fl(p[1], p[2], p[3])
                for _, r in ipairs(R.spread) do
                    for i = 0, 7 do
                        local a = (i + 0.5 * (#add % 2)) * math.pi / 4.0
                        local x, y = p[1] + math.cos(a) * r, p[2] + math.sin(a) * r
                        local f = fl(x, y, p[3])
                        local fm = fl((p[1] + x) / 2.0, (p[2] + y) / 2.0, p[3])
                        if f0 and f and fm and math.abs(f - f0) < 25.0 and math.abs(fm - f0) < 25.0 then
                            c.pos = { x, y, p[3] + (f - f0) }
                            placed = true
                            break
                        end
                    end
                    if placed then break end
                end
            end
            if placed then
                if c.sm64 then c.sm64 = { c.pos[2] / 0.75, c.pos[3] / 0.75, -c.pos[1] / 0.75 } end
                c.gauntlet_twin = true
                add[#add + 1] = c
            end
        end
    end
    for _, c in ipairs(add) do kept[#kept + 1] = c end
    data.objects = kept
    log("bowser run: %s - %d red coins and their star out, %d of its %d coins out, %d enemies doubled", name, red, cut, coins, #add)
    return #add
end

-- The Bowser run's tune, the course he is in: each joined course its own (G.RUN_JOIN `music`), the first its scene's -
-- only while a course's tune plays (not a cap's, a pause's, a fight's)
function G.run_section_tick(pawn, dt)
    local d = G.data
    if not (G.gauntlet and d and d.join_regions and pawn and MUSIC and MUSIC.play) then return end
    G.rs_t = (G.rs_t or 0.0) - (dt or 0.016)
    if G.rs_t > 0.0 then return end
    G.rs_t = 0.5
    local l = pawn:K2_GetActorLocation()
    local x, y = l.X - OFFSET.X, l.Y - OFFSET.Y
    -- (the course whose floor is under him, by its 4 m squares - not the box round each course: the Fire Sea's reached
    -- over the Dark World's top, and the tune went back and forth there - "why does the music keep changing?",
    -- 2026-11-03; and only once he has been in it 1.5 s, so a join's edge does not flick it)
    local want = d.music
    local ri = d.join_cells and d.join_cells[math.floor(x / 400.0) .. ":" .. math.floor(y / 400.0)]
    if ri and ri > 0 and d.join_regions[ri] and d.join_regions[ri].music then want = d.join_regions[ri].music end
    if want ~= G.rs_want then G.rs_want, G.rs_since = want, os.clock() end
    if os.clock() - (G.rs_since or 0.0) < 1.5 then return end
    if not want or MUSIC.current == want then return end
    local cur = MUSIC.current
    local course = cur == d.music
    for _, r in ipairs(d.join_regions) do if cur == r.music then course = true end end
    if course then pcall(MUSIC.play, want) end
end

-- Every painting on a wall made deeper: behind its picture (which stays on the wall's face) a hollow its own size,
-- `depth` deep - a sill at its foot, its sides and top lined with the wall round it - "make every painting in the game
-- deeper and vaultable at the base", then "I only wanted it deeper so the player wouldnt stick out after going through
-- the painting", 2026-10-29 (the picture set back 1.2 m first: "pushed really far back"). The sill is a ledge the
-- height of the painting's foot (77 cm in the castle's first rooms, 1.15-1.5 m upstairs) for STORROR to vault or climb
-- onto, through the picture; and he goes in only once all of him is through: its warp strips (behind the wall, 22-306
-- cm, under the sill) take him `through` behind its face (G.recess_at, update_floors). Room behind every painting is
-- Mario 64's own: the hollow its strips lie in, nothing in it for 1.4 m. Not DDD's, which slides back of its own, nor
-- HMC's on the floor.
G.PAINT_RECESS = {
    depth = 120.0,              -- cm behind the wall's face
    through = 60.0,             -- cm behind it his middle is before it takes him (his capsule 35 round: all of him)
    tile = 120.0,               -- cm a lining texture's repeat
    shade = 0.72,               -- (the lining's light: a little darker in than the wall outside)
    skip = { ddd = true },
    tex = { bob = "textures__inside__inside_castle_textures.0A000.rgba16", ccm = "textures__inside__inside_castle_textures.0A000.rgba16",
            wf = "textures__inside__inside_castle_textures.0A000.rgba16", jrb = "textures__inside__inside_castle_textures.01000.rgba16",
            wdw = "textures__inside__inside_castle_textures.0B800.rgba16", thi_tiny = "textures__inside__inside_castle_textures.04800.rgba16",
            ttm = "textures__inside__inside_castle_textures.0B800.rgba16", ttc = "textures__inside__inside_castle_textures.07000.rgba16",
            sl = "textures__inside__inside_castle_textures.07000.rgba16", thi_huge = "textures__inside__inside_castle_textures.04800.rgba16",
            lll = "textures__inside__inside_castle_textures.07000.rgba16", ssl = "textures__inside__inside_castle_textures.07000.rgba16",
            ttm_slide = "textures__mountain__ttm_textures.04000.rgba16" },
    tex_default = "textures__inside__inside_castle_textures.07000.rgba16",
}
-- Pieces of a scene drawn otherwise than the export left them - by their picture (false: none), their layer, and a box
-- they lie wholly in (scene cm: x0 x1 y0 y1 z0 z1): `both` drawn from both sides, `alpha` their vertex alpha times this.
G.SECTION_FIX = {
    -- (Hazy Maze Cave's shafts of light down into the lake: drawn as pale boxes, their tops solid squares - "sun shafts
    -- where dori is is bugged", 2026-10-31. Their flat tops and bottoms gone, their sides faint)
    hmc = {
        -- (0.4 still stood as pale boards by the ceiling - "also the sun shafts, where dori is"; with RENDER 96 their
        -- picture is a soft beam fading at its sides, textures_r96, and 0.45 of their alpha)
        { texture = "textures__cave__hmc_textures.0B800.ia16", upright = true, beam = true, alpha = 0.45, what = "the shafts of light" },
    },
    -- (the basement's light in the doorway at the foot of the stairs down - scene x -884..-806, y -422..-76: a beam drawn
    -- as a box, one-sided, so two pale slabs; in the athlete's way at head height - "raise this glass", 2026-10-25 - and
    -- raised, two pale triangles hanging in the doorway: "2 things sticking out on the path to the basement", "fix the
    -- stairwell triangles", 2026-10-31. Not drawn.)
    -- (drawn again, where Mario 64 has it - "glass is missing here", 2026-11-08: its solid pane stood unseen across the
    -- opening over the white wall, scene x -884, 1.6 to 4.6 m up. The export lays its six faces four times over, each
    -- half see-through, and they drew as near-white slabs: each face once (`once`), seen from both sides, a little
    -- fainter - glass)
    castle3 = {
        { texture = "levels__castle_inside__castle_light.ia16", once = true, both = true, alpha = 0.7,
          box = { -900.0, -790.0, -440.0, -60.0, -700.0, -150.0 }, what = "the glass in the doorway by the basement stairs" },
    },
    castle2 = {
        -- (the beams of light out of the top room's two high openings, to Rainbow Ride and Wing Mario Over the Rainbow:
        -- Mario 64 draws them from both sides; one-sided here, only the two faces turned toward him showed, two hard
        -- white slabs at each opening's edge - "the light coming out of the holes of rainbow ride and red hat level is
        -- bugged", 2026-10-31. Both sides, at a little over half their alpha: the faces now lie two deep)
        { texture = "levels__castle_inside__castle_light.ia16", both = true, alpha = 0.55, what = "the light beams out of the high openings" },
        -- (the pane over the castle clock's pendulum: no picture, its alpha 1 - "the under part of ticktok clock that is
        -- yellow needs 50% opacity", 2026-10-31)
        { texture = false, layer = "translucent", box = { -5360.0, -5260.0, -320.0, 10.0, 1680.0, 1970.0 }, alpha = 0.5,
          what = "the yellow pane over the clock's pendulum" },
    },
    -- (the Dark World's six quartz crystals - Mario 64's special_level_geo_0E, placed by its collision's special objects:
    -- the export drew only the first two, three times over each, and the other four stood solid and unseen - "theres
    -- invisable crystals on bowser 1 course", "crystals still missing", 2026-11-03. One crystal, laid at all six.)
    bitdw = {
        { texture = "levels__bitdw__3.rgba16", layer = "translucent", what = "the six quartz crystals",
          copies = { { -7108, 209, 356 }, { -7103, 844, -2088 }, { -6466, 9, 986 }, { -4013, -670, 990 }, { -5251, -276, 967 },
                     { -7665, 502, -251 } } },
    },
}

-- A model Mario 64 places at several spots, exported at too few (G.SECTION_FIX's `copies`: its spots in Mario 64's x, y,
-- z): its faces round the first spot, each once, laid down again at every spot - the piece's own faces replaced. Once.
function G.lay_copies(sec, f)
    if sec.copied or not (sec.pos and sec.idx and sec.uv and sec.col) then return false end
    local function at(p) return -p[3] * 0.75, p[1] * 0.75, p[2] * 0.75 end
    local ox, oy, oz = at(f.copies[1])
    local P, UV, C, N, idx = sec.pos, sec.uv, sec.col, sec.nrm, sec.idx
    -- (the model's corners round the first spot, each once: by place, picture and colour)
    local vmap, vkeys, verts, tris, seen = {}, {}, {}, {}, {}
    local function vert(v)
        if vmap[v] then return vmap[v] end
        local key = string.format("%.1f,%.1f,%.1f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f", P[v * 3 + 1], P[v * 3 + 2], P[v * 3 + 3],
            UV[v * 2 + 1] or 0, UV[v * 2 + 2] or 0, C[v * 4 + 1] or 1, C[v * 4 + 2] or 1, C[v * 4 + 3] or 1, C[v * 4 + 4] or 1)
        local i = vkeys[key]
        if not i then
            verts[#verts + 1] = v
            i = #verts - 1
            vkeys[key] = i
        end
        vmap[v] = i
        return i
    end
    for t = 1, #idx - 2, 3 do
        local near = true
        for k = 0, 2 do
            local v = idx[t + k]
            local dx, dy, dz = P[v * 3 + 1] - ox, P[v * 3 + 2] - oy, P[v * 3 + 3] - oz
            if math.abs(dx) > 150.0 or math.abs(dy) > 150.0 or dz < -100.0 or dz > 350.0 then near = false; break end
        end
        if near then
            local a, b, c = vert(idx[t]), vert(idx[t + 1]), vert(idx[t + 2])
            -- (its corners in their own turn, from the least: the same face whichever corner it starts at)
            local k1, k2, k3 = a, b, c
            if b < k1 and b < c then k1, k2, k3 = b, c, a elseif c < k1 and c < b then k1, k2, k3 = c, a, b end
            local key = k1 .. "," .. k2 .. "," .. k3
            if not seen[key] then seen[key] = true; tris[#tris + 1], tris[#tris + 2], tris[#tris + 3] = a, b, c end
        end
    end
    if #tris == 0 then return false end
    local pos, uv, col, nrm, out = {}, {}, {}, {}, {}
    for _, s in ipairs(f.copies) do
        local sx, sy, sz = at(s)
        local base = #pos // 3
        for _, v in ipairs(verts) do
            pos[#pos + 1], pos[#pos + 2], pos[#pos + 3] = P[v * 3 + 1] - ox + sx, P[v * 3 + 2] - oy + sy, P[v * 3 + 3] - oz + sz
            uv[#uv + 1], uv[#uv + 2] = UV[v * 2 + 1] or 0, UV[v * 2 + 2] or 0
            for k = 1, 4 do col[#col + 1] = C[v * 4 + k] or 1.0 end
            if N then for k = 1, 3 do nrm[#nrm + 1] = N[v * 3 + k] or 0.0 end end
        end
        for _, i in ipairs(tris) do out[#out + 1] = base + i end
    end
    sec.pos, sec.uv, sec.col, sec.idx = pos, uv, col, out
    if N then sec.nrm = nrm end
    sec.nverts, sec.ntris = #pos // 3, #out // 3
    sec.idx_once, sec.copied = nil, true
    log("%s: %d faces at %d spots", tostring(f.what), #tris // 3, #f.copies)
    return true
end

-- The final fight's three floors (asked 2026-11-03: "theres gonna be 3 platforms hovering over eachother like pancake.
-- starting at the top ... hit him 3 times the stage will shatter and bowser and mario fall to the next", "should be 9
-- hits in total to kill him"). The Sky's arena - its star and its ten outer pieces - made one platform of its own
-- (platforms.lua B.pancake), laid three times, `gap` cm apart, the first where the arena is; each with Mario 64's five
-- bombs on its points (`floor` on each). Only the floor he fights on is solid: off it he falls past the others to the
-- death floor, put that much further down. bowser_fight.lua breaks them.
-- (50 m apart: "make the fall after breaking the stage way higher", 2026-11-03 - it was 26)
-- (200 m apart: 80, not 50 - "make the fall longer", then "make the fall way way way longer", 2026-11-04. Kept with the
-- scene as it is laid - data.pancake_gap - for bowser_fight's floor heights, so a change here waits for its next load)
G.PANCAKE = { gap = 20000.0,
    -- (the floors in the run's chrome sky's colours - the arena's own Render 96 pictures recoloured, tools/
    -- final_stage_tex.py: "also you have to do something about the stage texture make it match our backround", 2026-11-04)
    -- (then the liquid chrome itself, all of it, drifting - bowser_fight.lua's liquid_tick; tools/final_liquid_tex.py:
    -- "can you make the stage look like the liquid?", 2026-11-04)
    -- (then without colour, for its rainbow - tools/final_liquid_rb_tex.py: "also make it change colors like a rainbow")
    retex = { ["levels__bowser_3__0.rgba16"] = "final_liquid_rb", ["levels__bowser_3__1.rgba16"] = "final_liquid_rb",
              ["levels__bowser_3__2.rgba16"] = "final_liquid_rb" } }
function G.pancakes(name, data)
    if name ~= "bowser_3" or not data or data.pancaked then return 0 end
    data.pancaked = true
    local RT = G.PANCAKE.retex or {}
    local function recolour(list) for _, s in ipairs(list or {}) do s.texture = RT[s.texture or ""] or s.texture end end
    recolour(data.sections)
    for _, o in ipairs(data.objects or {}) do
        if o.kind == "platform" and o.bhv == "bowser_plat" and data.templates and data.templates[o.tpl] then
            recolour(data.templates[o.tpl].sections)
        end
    end
    local secs, cpos, cidx = {}, {}, {}
    local function add_sec(s)
        local c = {}
        for k, v in pairs(s) do c[k] = v end
        c.id, c.idx_once = #secs, nil
        -- (drawn unlit, as the chrome sky is: lit by the sun, the floors' dark colours went grey - "the floor is still
        -- really greyed out", 2026-11-04)
        c.unlit = true
        secs[#secs + 1] = c
    end
    local function add_col(c)
        if not (c and c.pos and c.idx) then return end
        local base = #cpos // 3
        for i = 1, #c.pos do cpos[#cpos + 1] = c.pos[i] end
        for i = 1, #c.idx do cidx[#cidx + 1] = c.idx[i] + base end
    end
    local star = {}
    for _, s in ipairs(data.sections or {}) do add_sec(s); star[#star + 1] = s end
    for _, c in ipairs(data.collision or {}) do add_col(c) end
    local keep, bombs, pieces = {}, {}, {}
    for _, o in ipairs(data.objects or {}) do
        if o.kind == "platform" and o.bhv == "bowser_plat" then
            local t = data.templates and data.templates[o.tpl]
            if t then
                for _, s in ipairs(t.sections or {}) do add_sec(s) end
                add_col(t.collision)
                pieces[#pieces + 1] = o.tpl
            end
        else
            if o.kind == "bowser_bomb" then o.floor = 1; bombs[#bombs + 1] = o end
            keep[#keep + 1] = o
        end
    end
    if #secs == 0 or #cidx == 0 then return 0 end
    data.templates = data.templates or {}
    data.templates.pancake = { sections = secs, collision = { source = "pancake", ntris = #cidx // 3, pos = cpos, idx = cidx } }
    data.sections, data.collision = {}, {}
    local gap = G.PANCAKE.gap
    data.pancake_gap = gap
    for k = 1, 3 do
        keep[#keep + 1] = { kind = "platform", bhv = "pancake", tpl = "pancake", pos = { 0.0, -(k - 1) * gap / 0.75, 0.0 },
                            ang = { 0, 0, 0 }, bp = k << 24 }
        if k > 1 then
            for _, bm in ipairs(bombs) do
                keep[#keep + 1] = { kind = "bowser_bomb", pos = { bm.pos[1], bm.pos[2], bm.pos[3] - (k - 1) * gap }, floor = k }
            end
        end
    end
    data.objects = keep
    for _, f in ipairs(data.floors or {}) do
        if f.tag == "death" and f.pos then for i = 3, #f.pos, 3 do f.pos[i] = f.pos[i] - 2.0 * gap end end
    end
    -- (what its breaking throws down: the ten pieces and the star, bowser_fight.lua's debris)
    data.pancake_pieces, data.pancake_star = pieces, star
    log("final fight: three floors of %d pieces, %d m apart, %d bombs each", #secs, math.floor(gap / 100.0), #bombs)
    return 3
end
function G.fix_sections(name, data)
    local list = G.SECTION_FIX[name]
    if not (list and data and data.sections) then return 0 end
    local n = 0
    for _, f in ipairs(list) do
        for _, sec in ipairs(data.sections) do
            local pic = (f.texture == false and sec.texture == nil) or (f.texture and sec.texture == f.texture)
            if pic and (not f.layer or sec.layer == f.layer) and sec.pos and sec.idx then
                local inside = true
                local b = f.box
                if b then
                    for i = 1, #sec.pos - 2, 3 do
                        local x, y, z = sec.pos[i], sec.pos[i + 1], sec.pos[i + 2]
                        if x < b[1] or x > b[2] or y < b[3] or y > b[4] or z < b[5] or z > b[6] then inside = false; break end
                    end
                end
                if inside and f.drop then
                    sec.dropped = true
                    n = n + 1
                    log("scene %s: %s, not drawn", name, tostring(f.what))
                elseif inside then
                    if f.alpha and sec.col then for i = 4, #sec.col, 4 do sec.col[i] = sec.col[i] * f.alpha end end
                    if f.upright then
                        -- (only its upright faces kept: a light shaft's top and bottom drawn as solid squares)
                        local P, keep = sec.pos, {}
                        local idx = sec.idx
                        for t = 1, #idx - 2, 3 do
                            local a, b, c = idx[t] * 3, idx[t + 1] * 3, idx[t + 2] * 3
                            local ux, uy, uz = P[b + 1] - P[a + 1], P[b + 2] - P[a + 2], P[b + 3] - P[a + 3]
                            local wx, wy, wz = P[c + 1] - P[a + 1], P[c + 2] - P[a + 2], P[c + 3] - P[a + 3]
                            local nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
                            local l = math.sqrt(nx * nx + ny * ny + nz * nz)
                            if l > 1e-9 and math.abs(nz) / l < 0.5 then
                                keep[#keep + 1], keep[#keep + 2], keep[#keep + 3] = idx[t], idx[t + 1], idx[t + 2]
                            end
                        end
                        sec.idx, sec.ntris = keep, #keep // 3
                    end
                    if f.beam then
                        -- (each face's picture laid on it straight - across its width 0 to 1, up it 0 to 1: Mario 64's
                        -- ran at a slant across the faces, and the soft-edged beam's edges fell across them)
                        local P, UV, idx = sec.pos, sec.uv, sec.idx
                        local groups = {}
                        for t = 1, #idx - 2, 3 do
                            local a, b, c = idx[t], idx[t + 1], idx[t + 2]
                            local ux, uy, uz = P[b * 3 + 1] - P[a * 3 + 1], P[b * 3 + 2] - P[a * 3 + 2], P[b * 3 + 3] - P[a * 3 + 3]
                            local wx, wy, wz = P[c * 3 + 1] - P[a * 3 + 1], P[c * 3 + 2] - P[a * 3 + 2], P[c * 3 + 3] - P[a * 3 + 3]
                            local nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
                            local l = math.sqrt(nx * nx + ny * ny + nz * nz)
                            if l > 1e-9 then
                                nx, ny, nz = nx / l, ny / l, nz / l
                                local dd = nx * P[a * 3 + 1] + ny * P[a * 3 + 2] + nz * P[a * 3 + 3]
                                local key = string.format("%d,%d,%d,%d", math.floor(nx * 50 + 0.5), math.floor(ny * 50 + 0.5),
                                    math.floor(nz * 50 + 0.5), math.floor(dd / 5 + 0.5))
                                local g = groups[key]
                                if not g then g = { nx = nx, ny = ny, v = {} }; groups[key] = g end
                                g.v[a], g.v[b], g.v[c] = true, true, true
                            end
                        end
                        for _, g in pairs(groups) do
                            local vs = {}
                            for i in pairs(g.v) do vs[#vs + 1] = i end
                            if #vs >= 4 then
                                table.sort(vs, function(i, j) return P[i * 3 + 3] > P[j * 3 + 3] end)
                                local hx, hy = -g.ny, g.nx
                                local function along(i) return P[i * 3 + 1] * hx + P[i * 3 + 2] * hy end
                                local tl, tr, bl = vs[1], vs[2], vs[#vs - 1]
                                if along(tl) > along(tr) then tl, tr = tr, tl end
                                local b2 = vs[#vs]
                                if along(bl) > along(b2) then bl = b2 end
                                -- (p = TL + a (TR - TL) + b (BL - TL), solved in the face's plane)
                                local ex, ey, ez = P[tr * 3 + 1] - P[tl * 3 + 1], P[tr * 3 + 2] - P[tl * 3 + 2], P[tr * 3 + 3] - P[tl * 3 + 3]
                                local sx, sy, sz = P[bl * 3 + 1] - P[tl * 3 + 1], P[bl * 3 + 2] - P[tl * 3 + 2], P[bl * 3 + 3] - P[tl * 3 + 3]
                                local ee, es, ss = ex * ex + ey * ey + ez * ez, ex * sx + ey * sy + ez * sz, sx * sx + sy * sy + sz * sz
                                local det = ee * ss - es * es
                                if math.abs(det) > 1e-6 then
                                    for _, i in ipairs(vs) do
                                        local px, py, pz = P[i * 3 + 1] - P[tl * 3 + 1], P[i * 3 + 2] - P[tl * 3 + 2], P[i * 3 + 3] - P[tl * 3 + 3]
                                        local pe, ps = px * ex + py * ey + pz * ez, px * sx + py * sy + pz * sz
                                        local a = (pe * ss - ps * es) / det
                                        local b = (ps * ee - pe * es) / det
                                        UV[i * 2 + 1], UV[i * 2 + 2] = math.max(0.0, math.min(1.0, a)), math.max(0.0, math.min(1.0, 1.0 - b))
                                    end
                                end
                            end
                        end
                    end
                    if f.once then
                        -- (a face the export laid down more than once, by its corners' places: kept once)
                        local P, idx, keep, seen = sec.pos, sec.idx, {}, {}
                        for t = 1, #idx - 2, 3 do
                            local ks = {}
                            for j = 0, 2 do
                                local i = idx[t + j] * 3
                                ks[j + 1] = string.format("%.0f,%.0f,%.0f", P[i + 1], P[i + 2], P[i + 3])
                            end
                            table.sort(ks)
                            local key = table.concat(ks, "|")
                            if not seen[key] then
                                seen[key] = true
                                keep[#keep + 1], keep[#keep + 2], keep[#keep + 3] = idx[t], idx[t + 1], idx[t + 2]
                            end
                        end
                        sec.idx, sec.ntris = keep, #keep // 3
                    end
                    if f.both then
                        local idx = sec.idx
                        local m = #idx
                        for t = 1, m - 2, 3 do idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = idx[t], idx[t + 2], idx[t + 1] end
                        sec.ntris = #idx // 3
                    end
                    if f.copies then G.lay_copies(sec, f) end
                    n = n + 1
                    log("scene %s: %s%s%s%s", name, f.what, f.both and ", drawn from both sides" or "", f.upright and ", upright faces only" or "",
                        f.alpha and string.format(", its alpha x%.2f", f.alpha) or "")
                end
            end
        end
    end
    -- (the pieces not drawn: out of the list)
    local kept = {}
    for _, sec in ipairs(data.sections) do if not sec.dropped then kept[#kept + 1] = sec end end
    if #kept ~= #data.sections then data.sections = kept end
    return n
end

function G.recess_paintings(name, data)
    if not data or data.recessed then return 0 end
    data.recessed = true
    local R = G.PAINT_RECESS
    local D = R.depth
    local cpos, cidx = {}, {}
    local drawn = {}                -- texture -> section being built
    local function vsub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
    local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
    -- one face A B C D, seen from N (the way out of it), its texture's repeats along A->B and A->D
    local function face(A, B, C, Dp, N, tex)
        -- (wound as the level's own: (B - A) x (C - A) against N)
        local cr = cross(vsub(B, A), vsub(C, A))
        if cr[1] * N[1] + cr[2] * N[2] + cr[3] * N[3] > 0 then A, B, C, Dp = A, Dp, C, B end
        local base = #cpos // 3
        for _, p in ipairs({ A, B, C, Dp }) do cpos[#cpos + 1], cpos[#cpos + 2], cpos[#cpos + 3] = p[1], p[2], p[3] end
        for _, k in ipairs({ 0, 1, 2, 0, 2, 3 }) do cidx[#cidx + 1] = base + k end
        local s = drawn[tex]
        if not s then s = { layer = "opaque", texture = tex, pos = {}, uv = {}, col = {}, nrm = {}, idx = {} }; drawn[tex] = s end
        local sb = #s.pos // 3
        local lab = math.sqrt((B[1] - A[1]) ^ 2 + (B[2] - A[2]) ^ 2 + (B[3] - A[3]) ^ 2) / R.tile
        local lad = math.sqrt((Dp[1] - A[1]) ^ 2 + (Dp[2] - A[2]) ^ 2 + (Dp[3] - A[3]) ^ 2) / R.tile
        for i, p in ipairs({ A, B, C, Dp }) do
            s.pos[#s.pos + 1], s.pos[#s.pos + 2], s.pos[#s.pos + 3] = p[1], p[2], p[3]
            local uv = ({ { 0, 0 }, { lab, 0 }, { lab, lad }, { 0, lad } })[i]
            s.uv[#s.uv + 1], s.uv[#s.uv + 2] = uv[1], uv[2]
            for _ = 1, 3 do s.col[#s.col + 1] = R.shade end
            s.col[#s.col + 1] = 1.0
            s.nrm[#s.nrm + 1], s.nrm[#s.nrm + 2], s.nrm[#s.nrm + 3] = N[1], N[2], N[3]
        end
        for _, k in ipairs({ 0, 1, 2, 0, 2, 3 }) do s.idx[#s.idx + 1] = sb + k end
    end
    local n = 0
    for _, pt in ipairs(data.paintings or {}) do
        local nr, c = pt.normal, pt.corners
        if nr and c and #c >= 12 and math.abs(nr[3]) < 0.5 and not R.skip[pt.name or ""] then
            local P0 = { c[1], c[2], c[3] }
            local e1 = { c[4] - c[1], c[5] - c[2], c[6] - c[3] }
            local e2 = { c[10] - c[1], c[11] - c[2], c[12] - c[3] }
            local P1 = { P0[1] + e1[1], P0[2] + e1[2], P0[3] + e1[3] }
            local P3 = { P0[1] + e2[1], P0[2] + e2[2], P0[3] + e2[3] }
            local P2 = { P1[1] + e2[1], P1[2] + e2[2], P1[3] + e2[3] }
            local function back(p) return { p[1] - nr[1] * D, p[2] - nr[2] * D, p[3] - nr[3] * D } end
            local l1 = math.sqrt(e1[1] ^ 2 + e1[2] ^ 2 + e1[3] ^ 2)
            local u = { e1[1] / l1, e1[2] / l1, e1[3] / l1 }
            local tex = R.tex[pt.name or ""] or R.tex_default
            face(P0, P1, back(P1), back(P0), { 0, 0, 1 }, tex)                  -- the sill
            face(P3, P2, back(P2), back(P3), { 0, 0, -1 }, tex)                 -- its top
            face(P0, P3, back(P3), back(P0), u, tex)                            -- its sides
            face(P1, P2, back(P2), back(P1), { -u[1], -u[2], -u[3] }, tex)
            pt.recess = D
            n = n + 1
        end
    end
    if n == 0 then return 0 end
    data.collision = data.collision or {}
    data.collision[#data.collision + 1] = { source = "painting recesses", pos = cpos, idx = cidx, ntris = #cidx // 3 }
    local nid = 0
    for _, sec in ipairs(data.sections or {}) do if (sec.id or 0) >= nid then nid = (sec.id or 0) + 1 end end
    for _, s in pairs(drawn) do
        s.id, nid = nid, nid + 1
        s.nverts, s.ntris = #s.pos // 3, #s.idx // 3
        data.sections[#data.sections + 1] = s
    end
    log("scene %s: %d paintings %.0f cm deep behind their pictures, sills at their feet", name, n, D)
    return n
end
-- (him in a painting's recess - x, y, z his feet, scene cm - or behind it over its strips: that painting's, and whether
-- he has come to its picture; nil anywhere else)
function G.recess_at(x, y, z)
    for _, q in ipairs(G.paintings or {}) do
        local f0 = q.f0
        if q.recess and f0 then
            local nr = q.pt.normal
            local d = { x - f0[1], y - f0[2], z - f0[3] }
            local a = (d[1] * q.e1[1] + d[2] * q.e1[2] + d[3] * q.e1[3]) / (q.l1 * q.l1)
            local b = (d[1] * q.e2[1] + d[2] * q.e2[2] + d[3] * q.e2[3]) / (q.l2 * q.l2)
            local behind = -(d[1] * nr[1] + d[2] * nr[2] + d[3] * nr[3])
            -- (his feet from 2 m under its foot - the hollow's floor and its strips, under a high sill - to its top)
            if a > -0.02 and a < 1.02 and b > -200.0 / q.l2 and b < 1.0 and behind > -5.0 and behind < 330.0 then
                return { q = q, at_picture = behind >= G.PAINT_RECESS.through }
            end
        end
    end
    return nil
end

function G.open_paintings(data)
    if not data or data.paint_open then return 0 end
    data.paint_open = true
    local n = 0
    for _, pt in ipairs(data.paintings or {}) do
        local nr, c = pt.normal, pt.corners
        if nr and c and #c >= 12 and math.abs(nr[3]) < 0.5 then
            local x0, x1, y0, y1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
            for i = 1, #c, 3 do
                x0, x1 = math.min(x0, c[i]), math.max(x1, c[i])
                y0, y1 = math.min(y0, c[i + 1]), math.max(y1, c[i + 1])
                z0, z1 = math.min(z0, c[i + 2]), math.max(z1, c[i + 2])
            end
            local d = nr[1] * c[1] + nr[2] * c[2] + nr[3] * c[3]
            for _, m in ipairs(data.collision or {}) do
                local p, idx = m.pos, m.idx
                if p and idx then
                    local keep = {}
                    for t = 1, #idx - 2, 3 do
                        local inside = true
                        for k = 0, 2 do
                            local i = idx[t + k] * 3
                            local x, y, z = p[i + 1], p[i + 2], p[i + 3]
                            if abs(nr[1] * x + nr[2] * y + nr[3] * z - d) > 3.0 or x < x0 - 3.0 or x > x1 + 3.0
                                or y < y0 - 3.0 or y > y1 + 3.0 or z < z0 - 3.0 or z > z1 + 3.0 then inside = false; break end
                        end
                        if inside then n = n + 1 else keep[#keep + 1], keep[#keep + 2], keep[#keep + 3] = idx[t], idx[t + 1], idx[t + 2] end
                    end
                    if #keep < #idx then m.idx, m.ntris = keep, #keep // 3 end
                end
            end
        end
    end
    if n > 0 then log("paintings: %d triangles over their faces taken out", n) end
    return n
end
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
            -- (the pipe's own solid, a model of its own there - warp_pipe platforms from data/extra_statics.lua, whose
            -- collision has a floor across its foot: taken out of it - "something blocking the way down the pipe", the
            -- shaft dug and that floor still under him, 2026-11-08. A drawn one - the islands' peaks', `warp_pipe_geo` -
            -- its dark floor taken out too, its side's picture for the shaft: "pipes still not deep", those were the
            -- ones he went down. A platform's place: Mario 64's, x = -z, y = x)
            for _, o2 in ipairs(data.objects or {}) do
                if o2.kind == "platform" and o2.tpl and tostring(o2.tpl):find("warp_pipe", 1, true) and o2.pos then
                    local ox, oy = -o2.pos[3] * 0.75, o2.pos[1] * 0.75
                    if math.abs(ox - px) < 10.0 and math.abs(oy - py) < 10.0 then
                        local tp = data.templates and data.templates[o2.tpl]
                        if tp and tp.collision and tp.collision.idx and not tp.floor_cut then
                            tp.floor_cut = true
                            local c = tp.collision
                            local P, X, keep = c.pos, c.idx, {}
                            for q = 0, #X // 3 - 1 do
                                local i1, i2, i3 = X[q * 3 + 1], X[q * 3 + 2], X[q * 3 + 3]
                                local z1, z2, z3 = P[i1 * 3 + 3], P[i2 * 3 + 3], P[i3 * 3 + 3]
                                local hi = math.max(z1, z2, z3)
                                if not (hi < 20.0 and hi - math.min(z1, z2, z3) < 1.0) then
                                    keep[#keep + 1], keep[#keep + 2], keep[#keep + 3] = i1, i2, i3
                                end
                            end
                            c.idx, c.ntris = keep, #keep // 3
                        end
                        if not tex and tostring(o2.tpl):find("warp_pipe_geo", 1, true) then
                            tex = "actors__warp_pipe__warp_pipe_side.rgba16"
                            if tp and tp.sections then
                                local keep = {}
                                for _, s in ipairs(tp.sections) do if s.texture then keep[#keep + 1] = s end end
                                tp.sections = keep
                            end
                        end
                    end
                end
            end
            if h.drawn and not tex then goto next_pipe end
            -- (no deeper than 50 cm over the first ground under its foot, its warp at least 60 cm over its floor)
            local depth, trig = h.depth, h.trigger
            do
                local under = nil
                for _, m in ipairs(data.collision or {}) do
                    local P, X = m.pos, m.idx
                    for q = 0, #X // 3 - 1 do
                        local a3, b3, c3 = X[q * 3 + 1] * 3, X[q * 3 + 2] * 3, X[q * 3 + 3] * 3
                        local ax, ay, az = P[a3 + 1], P[a3 + 2], P[a3 + 3]
                        local bx, by, bz = P[b3 + 1], P[b3 + 2], P[b3 + 3]
                        local cx, cy, cz = P[c3 + 1], P[c3 + 2], P[c3 + 3]
                        local d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
                        if math.abs(d) > 1e-9 then
                            local l1 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / d
                            local l2 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / d
                            local l3 = 1.0 - l1 - l2
                            if l1 >= -0.001 and l2 >= -0.001 and l3 >= -0.001 then
                                local z = l1 * az + l2 * bz + l3 * cz
                                if z < foot - 20.0 and (not under or z > under) then under = z end
                            end
                        end
                    end
                end
                if under then depth = math.min(depth, foot - under - 50.0) end
                trig = math.min(trig, depth - 60.0)
            end
            local bottom = foot - depth
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
            o.trigger = foot - trig
            log("scene %s: the pipe at (%.0f, %.0f) made deep, to %.0f (%d triangles cut, texture %s)", name, px, py,
                bottom, cut, tostring(tex))
        end
        ::next_pipe::
    end
end
G.deepen_pipes = deepen_pipes        -- (for G.join_scenes, which comes before it)

-- Parts of a level raised for the athlete, taller than Mario: everything of the scene's picture and collision inside a
-- box (scene cm) carried up `by`. PSS's third arch over the slide: its crossbeam 178 cm over the slide, Mario clear
-- under it and the athlete's head into it ("mario hits his head off the 3rd pole coming down the slide please raise it",
-- 2026-10-17) - up 75 cm, its legs drawn out with it. (A G field: the chunk's locals are full.)
G.RAISE = {
    pss = { { x0 = 1245, x1 = 1295, y0 = 1050, y1 = 1750, z0 = -1084, z1 = -1020, by = 75.0, what = "the third arch's crossbeam" } },
    -- (the hole in the pyramid corridor's wall to hide from the Spindel in: 77 cm deep past its end, but its ceiling 154
    -- cm up - Mario stands in it, the athlete (176) did not fit: "the hole in the wall by rolling thwomp is not big
    -- enough to hide in", 2026-10-23. Its ceiling up 60 cm, the corridor wall's edge over it with it.)
    -- ("its not deep enough": its back wall out 70 cm too, 147 cm deep - `dy` carries corners along y)
    ssl_2 = { { x0 = -240, x1 = -75, y0 = -2160, y1 = -2065, z0 = 1590, z1 = 1598, by = 60.0, what = "the hiding hole by the Spindel's run (its ceiling)" },
              { x0 = -240, x1 = -75, y0 = -2160, y1 = -2140, z0 = 1430, z1 = 1665, dy = -70.0, what = "the hiding hole's back wall" } },
    -- (Tall Tall Mountain's slide: the wooden ramp's top edge, 1.5 m over the run down beside it - its lip a kicker the
    -- slide took him up only straight on, turning off the run he met it slantwise and was turned away: "player couldnt
    -- make it onto wood ramp again because of small bump", then "if you can just flatten the bump in that section",
    -- 2026-10-27. Down 1.6 m, level with the run: the ramp starts from it, 11 degrees on down instead of 22)
    ttm_3 = { { x0 = 4880, x1 = 4990, y0 = -1150, y1 = -820, z0 = -500, z1 = -440, by = -160.0, what = "the wooden ramp's lip on the slide" } },
}
-- The pyramid's railings (ssl_2): under each drawn grate its collision is a parapet 31 cm thick, its top sloping 45
-- degrees from 85 cm at the front down to 54 at the back - STORROR could not climb up onto it ("fences in the pyramid
-- are bugged", "cant climb them correctly", 2026-10-23). The top made flat: each sloped strip's low corners up to its
-- high ones, and its back wall's top with them - collision only, the grate drawn as it was.
G.FLATTEN = { ssl_2 = { { lo = 54.0, hi = 85.0, what = "the walkway railings' sloping tops" } } }
function G.flatten_tops(name, data)
    local list = G.FLATTEN[name]
    if not list or data.flattened then return end
    data.flattened = true
    local function key(x, y) return string.format("%.1f,%.1f", x, y) end
    for _, f in ipairs(list) do
        local low, strips = {}, 0
        for _, m in ipairs(data.collision or {}) do
            local p, idx = m.pos or {}, m.idx or {}
            for t = 1, #idx - 2, 3 do
                local a, b, c = idx[t] * 3, idx[t + 1] * 3, idx[t + 2] * 3
                local za, zb, zc = p[a + 3], p[b + 3], p[c + 3]
                local zmin, zmax = math.min(za, zb, zc), math.max(za, zb, zc)
                if math.abs(zmin - f.lo) < 1.0 and math.abs(zmax - f.hi) < 1.0 then
                    local ux, uy, uz = p[b + 1] - p[a + 1], p[b + 2] - p[a + 2], zb - za
                    local wx, wy, wz = p[c + 1] - p[a + 1], p[c + 2] - p[a + 2], zc - za
                    local nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
                    local l = math.sqrt(nx * nx + ny * ny + nz * nz)
                    local k = (l > 1e-6) and math.abs(nz) / l or 0.0
                    if k > 0.5 and k < 0.9 then                     -- (sloped: not a wall, not already flat)
                        strips = strips + 1
                        for _, i in ipairs({ a, b, c }) do
                            if math.abs(p[i + 3] - f.lo) < 1.0 then low[key(p[i + 1], p[i + 2])] = true end
                        end
                    end
                end
            end
        end
        local n = 0
        for _, m in ipairs(data.collision or {}) do
            local p = m.pos or {}
            for i = 1, #p, 3 do
                if math.abs(p[i + 2] - f.lo) < 1.0 and low[key(p[i], p[i + 1])] then p[i + 2] = f.hi; n = n + 1 end
            end
        end
        log("scene %s: %s made flat (%d sloped triangles, %d corners up %.0f cm)", name, f.what, strips, n, f.hi - f.lo)
    end
end

-- Pillars solid as they are drawn: Jolly Roger Bay's four stone pillars. Mario 64's collision for each is a plain taper
-- from its foot on the seabed to a point some 3 m under its drawn top, fatter than the drawn stone - 30 cm a side at the
-- water - and he stuck in the gaps between them: "getting stuck between rock pilons", "its the hitbox on the pillars",
-- 2026-11-06. In each circle ({ x, y, r }, scene cm) the collision's triangles all inside it that rise over `above` are
-- taken out and the drawn ones of the pillars' own pictures (`textures`) put in their place: their feet are the same
-- corners, the seabed between them left as it is.
G.SOLID_AS_DRAWN = {
    -- (`nopush`: and the swim's push off walls (G.wall_push) not off them - 2 m out and four times his stroke, it held
    -- him in the middle of them, "getting stuck between rock pilons", 2026-11-06; a pillar has nowhere to wedge him)
    jrb = { above = 0.0, nopush = true, textures = { "jrb_textures.01800", "jrb_textures.02800" },
            { -2484.0, 494.0, 330.0 }, { -2848.0, 816.0, 330.0 }, { -2043.0, 40.0, 330.0 }, { -4586.0, -1900.0, 330.0 } },
}
function G.solid_as_drawn(name, data)
    local S = G.SOLID_AS_DRAWN[name]
    if not S or data.solid_drawn then return end
    data.solid_drawn = true
    local function inside(x, y)
        for i, c in ipairs(S) do
            if (x - c[1]) ^ 2 + (y - c[2]) ^ 2 < c[3] * c[3] then return i end
        end
    end
    local function within(P, a, b, c)
        local ca = inside(P[a + 1], P[a + 2])
        return ca and ca == inside(P[b + 1], P[b + 2]) and ca == inside(P[c + 1], P[c + 2])
            and math.max(P[a + 3], P[b + 3], P[c + 3]) > (S.above or 0.0)
    end
    local cut, add = 0, 0
    for _, m in ipairs(data.collision or {}) do
        local P, I = m.pos, m.idx
        if P and I then
            local keep = {}
            for t = 1, #I, 3 do
                if within(P, I[t] * 3, I[t + 1] * 3, I[t + 2] * 3) then cut = cut + 1
                else keep[#keep + 1], keep[#keep + 2], keep[#keep + 3] = I[t], I[t + 1], I[t + 2] end
            end
            if #keep < #I then m.idx, m.ntris = keep, #keep // 3 end
        end
    end
    local pos, idx = {}, {}
    for _, s in ipairs(data.sections or {}) do
        local P, I, tex = s.pos, s.idx, tostring(s.texture)
        local mine = false
        for _, w in ipairs(S.textures or {}) do if tex:find(w, 1, true) then mine = true end end
        if mine and P and I then
            for t = 1, #I, 3 do
                local a, b, c = I[t] * 3, I[t + 1] * 3, I[t + 2] * 3
                if within(P, a, b, c) then
                    for _, v in ipairs({ a, b, c }) do
                        pos[#pos + 1], pos[#pos + 2], pos[#pos + 3] = P[v + 1], P[v + 2], P[v + 3]
                        idx[#idx + 1] = #pos // 3 - 1
                    end
                    add = add + 1
                end
            end
        end
    end
    if add > 0 then
        data.collision = data.collision or {}
        data.collision[#data.collision + 1] = { source = "the pillars as drawn", pos = pos, idx = idx, ntris = #idx // 3 }
    end
    log("scene %s: %d pillars solid as drawn (%d of their solid triangles out, %d drawn ones in)", name, #S, cut, add)
end

function G.raise_parts(name, data)
    pcall(G.flatten_tops, name, data)
    local list = G.RAISE[name]
    if not list or data.raised then return end
    data.raised = true
    for _, b in ipairs(list) do
        local n = 0
        for _, group in ipairs({ data.sections or {}, data.collision or {} }) do
            for _, m in ipairs(group) do
                local p = m.pos or {}
                for i = 1, #p, 3 do
                    local x, y, z = p[i], p[i + 1], p[i + 2]
                    if x > b.x0 and x < b.x1 and y > b.y0 and y < b.y1 and z > b.z0 and z < b.z1 then
                        if b.by then p[i + 2] = z + b.by end
                        if b.dy then p[i + 1] = y + b.dy end
                        n = n + 1
                    end
                end
            end
        end
        log("scene %s: %s moved %.0f cm (%d corners)", name, b.what, b.by or b.dy or 0.0, n)
    end
end

-- Pieces of a level moved where he asked: the triangles of the scene's picture and its collision whose three corners
-- are all among a piece's corners (Mario 64 units) - new corners for them, so nothing else that shares a corner is pulled
-- along - carried `dz` (Mario 64 units). CCM's wedge of a ledge by the fenced path at the mountain's foot, 4.9 m over
-- the path and out of the athlete's reach: "actually just bring the platform down", 2026-10-18 - down 3.3 m, its top
-- 1.7 m over the path.
-- (or `box` - x0, x1, y0, y1, z0, z1, Mario 64 units - with `textures`: the drawn triangles of those pictures all inside
-- it, `solid` the collision too, `stars` the stars of those ids)
-- (then "raise it more also bring the ice with it" / "a smidge higher also your not moving the ice or star with it":
-- its top 3.3 m over the path, and the ice bridge it holds up - the clear ice, its icicles, its solid, and the star
-- over its end block (act 6's) - with it)
G.MOVE_PIECES = {
    ccm = { { dz = -230.0, what = "the wedge ledge over the fenced path",
              corners = { { -355, -2531, -2547 }, { 121, -2573, -2661 }, { 34, -2543, -3499 }, { -695, -2531, -3289 },
                          { -692, -2764, -3291 }, { -355, -2764, -2548 } } },
            { dz = -230.0, what = "the ice bridge off it, its icicles and the star", solid = true, stars = { 5 },
              textures = { "textures__snow__ccm_textures.07000.rgba16", "textures__snow__ccm_textures.00800.rgba16" },
              box = { -2333, -507, -2787, -2507, -3307, -2573 } } },
    -- (`stretch`: the corners themselves moved, with every triangle that has them - nothing comes apart.) The Secret
    -- Aquarium's window: its recess 1.5 m tall, the athlete only hung from its sill - "can you actually add the ability
    -- to climb into the hole", 2026-10-18: its top 0.7 m higher, 2.3 m clear, room to climb in and stand
    castle = { { dz = 96.0, stretch = true, what = "the Secret Aquarium window's top",
                 corners = { { 2036, 1024, 1352 }, { 1891, 1024, 1208 }, { 2180, 1024, 1208 }, { 2036, 1024, 1063 } } } },
    -- Wet-Dry World's cage round the Express Elevator star (scene x 959..1631, y 480..884): its way in, the hole low
    -- through its wall on the far side from the start (x 959..1109), 149 cm tall, and inside, over the elevator up
    -- top, 146 cm to its solid ceiling - Mario's size, the athlete 172 - "cage hole is too small to get in", 2026-10-28.
    -- The hole's top up 1 m (its solid along the wall's whole foot with it, so nothing comes apart: 2.5 m clear), and
    -- the solid ceiling up to the cage's drawn roof (2688: 1.9 m over the elevator).
    wdw = { { dz = 133.33, stretch = true, what = "the cage's way in",
              corners = { { 1178, 404, -1279 }, { 1280, 404, -1279 }, { 1178, 404, -1479 }, { 1280, 404, -1479 },
                          { 1178, 404, -2175 }, { 1280, 404, -2175 }, { 1228.6, 404, -1279 }, { 1228.6, 404, -1479 } } },
            { dz = 61.0, stretch = true, what = "the cage's ceiling",
              corners = { { 640, 3523, -1279 }, { 1178, 3523, -1279 }, { 640, 3523, -2175 }, { 1178, 3523, -2175 } } },
            -- (the orange block the Bob-omb Buddy stands on - scene x -2880..-2496, y -191..192 - its top 4.6 m over the
            -- wooden plank floating by it at the level's start water, its underside 3.7 m: out of the athlete's reach -
            -- "lower this platform above me", 2026-10-28. Down 2.4 m: its top 2.2 m over the plank, 1.4 m clear of the
            -- water under it. Its 12 drawn and 12 solid triangles, nothing else in the box; the Buddy, put on the floor
            -- under his feet + 250, comes down onto its top - he stood in it, on its underside, before.)
            { dz = -320.0, what = "the Bob-omb Buddy's orange block", box = { -300, 300, 3000, 3260, 3280, 3900 } } },
    -- (`squash`, scene cm: its corners pressed up between `from` and `top` into `to` and `top` - its top kept where it
    -- meets what is over it.) Hazy Maze Cave's red grate over the green slope (scene x -1920..-1844, y 4184..4683): its
    -- solid 138 cm over the slope, the athlete crouched under it - "increase the height of this grate", 2026-10-25. Its
    -- foot up 150 cm ("needs raised higher"), its top at 692 as it was: 2.5 m clear under it.
    hmc = { { squash = { from = 116.0, to = 266.0, top = 692.0 }, solid = true, what = "the red grate over the green slope",
              textures = { "textures__cave__hmc_textures.01000.rgba16" }, box = { 5573, 6253, 147, 933, 2453, 2567 } } },
    -- The basement's glass in the doorway at the foot of the stairs down (scene x -884..-806, y -422..-76): a box drawn
    -- and solid from 1.62 m over the floor (-644) up to the lintel (-322), the doorway open under it - Mario's height and
    -- some, the athlete's head into it: "raise the glass", 2026-11-08 (and 2026-10-25). Its foot up 1.33 m, its top kept
    -- at the lintel - raised whole, it stood out over the lintel into the stairwell, two pale triangles: "2 things
    -- sticking out on the path to the basement", 2026-10-31. Drawn as glass by G.SECTION_FIX castle3. (Its box in Mario
    -- 64 units: x = scene y, y = scene z, z = -scene x.)
    castle3 = { { squash = { from = -644.0, to = -511.0, top = -322.0 }, solid = true, what = "the glass in the doorway by the basement stairs",
                  textures = { "levels__castle_inside__castle_light.ia16" }, box = { -566, -98, -862, -426, 1070, 1185 } } },
    -- Wet-Dry World's town, the tunnel down to it from the fenced hole in the main room's corner (scene y -2850..-2140):
    -- its two eight-sided holes, 7.1 m across and 7.1 m high, each with a solid chain-link gate in it that leaves only a
    -- lens of a gap - over the first (scene x 1190, its top at -565 under the hole's -412), under the second (x 2054,
    -- its foot at -970 over the floor's -1122) - 1.5 m at most, Mario's way through; the athlete's too small for it:
    -- "gates in the tunnel holes are too small", 2026-10-28. Each gate pressed toward its solid end (its fence and its
    -- solid: 74 drawn and 14 solid triangles each, nothing else in the box), its free edge 2.35 m further off: a gap of
    -- 3.9 m in the middle, 2.1 m at the hole's sides.
    -- Tick Tock Clock's push blocks' ledge along the back wall, under the grate cage (x -617..611, z 1672..2081): its
    -- frame's underside 205 units over the ledge - 1.54 m, Mario's way under it, too low for the athlete's 1.72
    -- (2026-10-29: then only its solid raised to its grate; its drawn frame, solid to him too, still caught him at the
    -- cage's ends - "getting stuck on cage overhang", 2026-10-30). The whole cage pressed up from its underside at 3277
    -- to 3380, under its top at 3943: 2.3 m clear.
    ttc = { { lift = { -645, 645, 1665, 2090, 3277, 3380, 3943 }, square = true, what = "the push blocks' cage over the ledge" },
            -- (the cage round act 5's star, its way in off the top push block of the three: under a beam of its grate
            -- 205 units over the ledge into it - 1.54 m, Mario's way in, the athlete's 1.72 too much: "this hole is too
            -- small", 2026-10-30. The beam lies at 45 degrees (x + z -2941..-2217, x - z 13..433) - up 100 from its
            -- underside at 2319: 2.3 m clear - and the grate over it, to the cage's top at 2585, pressed up with it.
            -- Its 9 solid corners alone left the grate's own drawn bars - solid to him too - where they were: "opening
            -- still too small".)
            { lift = { -2947, -2211, -5, 440, 2319, 2419, 2585 }, what = "the star cage's way in, over the top push block" },
            -- (the ghost race's star, 7: the two Bob-ombs on the bottom floor by its start left out - "for this star only
            -- remove the 2 bomb ombs", 2026-11-08)
            { star = 7, what = "the two Bob-ombs by the race's start", remove = { { "bobomb", -142.0, 1262.0 }, { "bobomb", -478.0, 808.0 } } } },
    -- Tiny-Huge Island's way into the cave (the huge island's, by the Koopa's beach): a tunnel 205 units square and
    -- 410 long into the cliff, its warp 230 cm in - 1.54 m tall, Mario's height and a bit, the athlete's 1.72 too much:
    -- he could not get in to the red coins (2026-10-29). Its roof's six corners up 100 (75 cm): 2.29 m. Rock above it.
    thi = { { dz = 100.0, stretch = true, what = "the cave tunnel's roof",
              corners = { { 512, -306, 1024 }, { 307, -306, 1024 }, { 512, -306, 819 }, { 307, -306, 819 },
                          { 307, -306, 614 }, { 512, -306, 614 } } } },
    -- ...and its other end, in the cave (where he comes in, and the way back out): as low, its roof up the same.
    thi_3 = { { dz = 100.0, stretch = true, what = "the tunnel's roof",
                corners = { { 410, 1229, 2253 }, { 614, 1229, 2253 }, { 614, 1229, 2048 }, { 614, 1229, 2458 },
                            { 410, 1229, 2458 }, { 410, 1229, 2048 } } } },
    -- The tiny island's beach corner (scene x -1844..-1382, y -1843..-1151): its little fence round the level's edge is
    -- drawn 23 cm tall, and its walls stood 1.54 m - Mario 64's own, to keep him in. The athlete climbed them and stood
    -- in the air over the fence: "mini fence hitbox is huge", 2026-10-29. Its four triangles brought down to the fence's
    -- top, their foot kept; the edge of the level (keep_in_level - no ground past it) still holds him in.
    thi_2 = { { squash = { from = -513.75, to = -644.0, top = -667.5 }, solid = true, what = "the beach fence's walls",
                textures = { "(none drawn)" }, box = { -2467, -1527, -900, -673, 1833, 2467 } } },
    wdw_2 = { { squash = { from = -565.0, to = -800.0, top = -1122.0 }, solid = true, what = "the first gate in the town's tunnel",
                textures = { "textures__grass__wf_textures.00000.rgba16" }, box = { -3814, -2839, -1508, -746, -1654, -1519 } },
              { squash = { from = -970.0, to = -735.0, top = -412.0 }, solid = true, what = "the second gate in the town's tunnel",
                textures = { "textures__grass__wf_textures.00000.rgba16" }, box = { -3814, -2839, -1307, -540, -2808, -2673 } },
              -- (the tower against the wall with the pole on top - scene x -2880..-2400, y -863..-287: its roof round the
              -- arch on three sides, 56 degrees, its eaves at -1007 up to the ledge round the tower at -863, and the
              -- tower's pyramid roof, 63, from -671 up to its little flat top under the pole at -499 - too steep for him:
              -- "this roof is too steep to climb", "also the top part of it", 2026-10-28. Each brought to 35 degrees,
              -- its foot kept: the eaves raised first put them out of reach, "roof is too high to reach now". So the
              -- pyramid's top down 112 cm, and then all of it over the roof - the ledge, the tower and its pyramid - down
              -- 77 cm: the eaves as they were, the pyramid's edge 1.9 m over the ledge as before. The pole and the
              -- ledge's coin with them. Only the tower's own triangles have these corners.)
              -- (and the pyramid's 24 cm overhang closed - "close the overhang on the upper bit", 2026-10-28: the tower's
              -- walls, at its top and at the top of the slope at its foot, out to the pyramid's edge, the tower one box)
              { what = "the tower's walls out to its roof's edge",
                moves = { { { -671, -1100, 3488 }, { -639, -1100, 3456 } }, { { -863, -1100, 3488 }, { -895, -1100, 3456 } },
                          { { -671, -1100, 3680 }, { -639, -1100, 3712 } }, { { -863, -1100, 3680 }, { -895, -1100, 3712 } },
                          { { -671, -895, 3488 }, { -639, -895, 3456 } }, { { -863, -895, 3488 }, { -895, -895, 3456 } },
                          { { -671, -895, 3680 }, { -639, -895, 3712 } }, { { -863, -895, 3680 }, { -895, -895, 3712 } } } },
              { dz = -149.0, stretch = true, what = "the tower's pyramid top", objects = { { "pole", -2688, -576 } },
                corners = { { -755, -665, 3571 }, { -779, -665, 3571 }, { -755, -665, 3597 }, { -779, -665, 3597 } } },
              { dz = -102.4, stretch = true, what = "the tower over its roof", objects = { { "pole", -2688, -576 }, { "coin", -2550, -585 } },
                box = { -1034, -499, -1161, -532, 3319, 3854 } } },
    -- (`scale`: x, y, z, k - its corners k times as far from that point, Mario 64 units; `slides`, the slide floors
    -- among them (data.slides) with them.) Snowman's Land's big ice block, the maze in it to act 3's star ("In the Deep
    -- Freeze"): Mario's size, the athlete half again his - "increase the size of the ice puzzle", 2026-10-26. Half again
    -- as big about the middle of its foot: 11.5 by 9.2 m and 6.9 m tall, its base and the base's snow, its star, and its
    -- roof's sloped edges (slide floors) with it. (`outer_last`: its see-through faces drawn in G.outer_last's order -
    -- "the seethrough is a mess", 2026-10-26.)
    sl = { { scale = { 4377, 1024, 4565, 1.5 }, solid = true, slides = true, stars = { 2 }, outer_last = true,
             what = "the big ice block and its maze",
             textures = { "textures__snow__ccm_textures.00800.rgba16", "textures__snow__ccm_textures.05000.rgba16",
                          "textures__snow__ccm_textures.08800.rgba16" },
             box = { 3940, 4810, 1000, 1870, 4030, 5100 },
             -- (and its brick base on under the back quarter of the ice it left overhanging, either side of the hole up
             -- into the maze, which is kept: "extend the wood under the overhang but keep the entrance hole open",
             -- 2026-10-26. Its pictures laid on as the base's own.)
             add = { side = "textures__snow__ccm_textures.05000.rgba16", top = "textures__snow__ccm_textures.08800.rgba16", solid = true,
                     side_uv = { x0 = -3040.5, y0 = 2975.25, z0 = 921.75, v0 = 0.9668, ux = 0.006457, uy = 0.0065548, vz = 0.0064787 },
                     top_uv = { x0 = -3808.5, y0 = 3436.5, v0 = -1.0293, uy = 0.0025279, vx = 0.0025991 },
                     prisms = { { z0 = 768.0, z1 = 921.75, sides = { false, true, true, true },
                                  corners = { { -3808.5, 3436.5 }, { -3654.75, 3436.5 }, { -3654.75, 3589.5 }, { -3808.5, 3589.5 } } },
                                { z0 = 768.0, z1 = 921.75, sides = { false, true, true, true },
                                  corners = { { -3499.5, 3436.5 }, { -3040.5, 3436.5 }, { -3040.5, 3589.5 }, { -3501.0, 3589.5 } } } } } },
           -- (`warps`: the warp triggers in its box with it, their reach too; `node_at`: arrival spots set where given, scene
           -- x and y, the rest in its box moved with it.) Snowman's Land's igloo, 2.2 m across and its way in 1 m high:
           -- "the igloo needs to be 2.5x as big", then "tuck it in the wall a bit", 2026-10-26 - its ledge, 4 m across with a
           -- 6.5 m drop to the west, holds no 5.6 m dome: grown from a point that keeps its west side on the ledge, its east
           -- side 1.3 m into the rock that rises there and its back 0.5 m into the wall behind. Its way in 2.4 m high; the
           -- spot he comes out at in front of it, not past the ledge's edge where the dome's growth would have put it.
           -- (`turn` { x, y, degrees }: then turned about that point, scene cm - more than 0 clockwise from above, the
           -- engine's yaw; `shift` { x, y }: then slid that far, scene cm; `solid_drawn`: its drawn triangles made solid
           -- too.) "tilt the igloo 20 degrees to the right" - "counter clockwise", from above - then "10 more degrees to
           -- the right also push it in the hill a bit more": 80 cm straight back from its doorway, into the rock behind
           -- it - and "add collisions to the igloo", 2026-10-26: Mario 64's igloo is solid
           -- only as a ring of walls and a rim, its top open in the middle - at 2.5 times, a hole to walk and fall through,
           -- and its way in had no roof: its drawn dome and tunnel solid as they are seen.
           { scale = { 480.0, 2149.3, 1395.6, 2.5 }, solid = true, warps = true, node_at = { [11] = { -1052.0, 75.0 } },
             turn = { -960.0, 427.0, -30.0 }, shift = { 56.0, 57.0 }, solid_drawn = true,
             what = "the igloo",
             textures = { "textures__snow__ccm_textures.08800.rgba16", "textures__snow__ccm_textures.01000.rgba16" },
             box = { 320, 747, 2133, 2400, 1133, 1600 } },
           -- (`underside`: the flat drawn faces in the box given a back - a copy facing the other way.) The ice bridge
           -- to the big snowman: one see-through face, drawn from above only (Mario 64 culls its back) - nothing under
           -- it: "underneath ice bridge has no texture", 2026-10-26.
           { underside = true, what = "the ice bridge", textures = { "textures__snow__ccm_textures.00800.rgba16" },
             box = { 0, 2100, 3300, 3350, 200, 2100 } } },
    -- Inside the igloo: the see-through ice wall before the vanish cap's box, 3.08 m - out of the athlete's reach: "lower
    -- this ice wall", 2026-10-26. Its top corners brought down to 2 m, its solid and its ice with it.
    sl_2 = { { dz = -143.3, stretch = true, solid = true, slides = true, what = "the ice wall before the vanish cap's box",
               box = { 1210, 2060, 395, 425, -1445, -1215 } },
             -- (`remove`: objects left out - { kind, x, y } in scene cm, the nearest within 30.) "remove the goomba by the
             -- star in the ice", 2026-10-26: the one beside the star in its ice block.
             { remove = { { "goomba", -720.0, -15.0 } }, what = "the goomba by the star in the ice" } },
    -- Tall Tall Mountain's ledge by the sign and the fading warp, low on its east face: under the rock overhang above
    -- it but for a sliver 1 m wide, and off the overhang's edge he came down on the 60-degree face beyond it and slid
    -- to the foot - "can you expand the floor here", "the underside next to the sign I mean", "so the players able to
    -- reach", 2026-10-27. A shelf of its sand flush with it, out 5 m past the overhang's edge (x 3800 there), on a rock column down
    -- into the face (its pictures laid on as the ledge's own: the sand from its top, the rock from its walls).
    ttm = { { what = "the shelf by the sign under the overhang",
              add = { side = "textures__mountain__ttm_textures.04000.rgba16", top = "textures__mountain__ttm_textures.03800.rgba16",
                      solid = true,
                      side_uv = { x0 = 4598.2, y0 = -342.8, z0 = -4607.2, v0 = 0.9668, ux = 0.0025787, uy = 0.002545, vz = 0.0025994 },
                      top_uv = { x0 = 3062.2, y0 = -1522.5, v0 = -18.7734, uy = -0.0026010, vx = -0.0025992 },
                      prisms = { { z0 = -4450.0, z1 = -2586.0, sides = { true, true, true, false },
                                   corners = { { 3447.4, -897.0 }, { 4300.0, -897.0 }, { 4300.0, -343.0 }, { 3599.2, -343.0 } } } } } } },
    -- Bob-omb Battlefield's fence by the pit of iron balls: two runs of it 2.9 m apart (scene x 3618..3875), and its stone
    -- rail drawn on across the gap between them - no bars under it, nothing solid: a fence with a piece missing, walked
    -- through - "fell through a gap in the fence", then "no collision", "just remove the section in the fence",
    -- 2026-10-27. That rail taken out (`cut`), the two rails' ends left open by it closed with a face of their stone each,
    -- as the base's end is (0.0096 of its picture a cm). Drawn only: the gap stays open.
    bob = { { what = "the rail across the gap in the fence by the pit",
              cut = { "textures__generic__bob_textures.02000.rgba16" }, cut_strip = { 3617.6, -1696.9, 3874.85, -1826.65, 22.0, 1260.0, 1310.0 },
              add = { side = "textures__generic__bob_textures.02000.rgba16",
                      side_uv = { x0 = 0.0, y0 = -1680.0, z0 = 1305.75, v0 = 0.0, ux = 0.0108, uy = 0.0108, vz = 0.0096 },
                      prisms = { { z0 = 1267.5, z1 = 1305.75, top = false, sides = { true, false, false, false },
                                   corners = { { 3609.0, -1713.8 }, { 3626.2, -1680.0 }, { 3625.75, -1679.77 }, { 3608.55, -1713.57 } } },
                                 { z0 = 1267.5, z1 = 1305.75, top = false, sides = { true, false, false, false },
                                   corners = { { 3883.5, -1809.8 }, { 3866.2, -1844.0 }, { 3866.65, -1844.23 }, { 3883.95, -1810.03 } } } } } } },
    -- Rainbow Ride's carpet that sets off along x 120 (its start scene x 138, y 485): its two sets of donut platforms
    -- over its line taken out - three at 922 (y 179, 26, -127), the carpet climbing to 161 cm under the last, Mario's
    -- room, not the athlete's 176; three at 1996 (y -567, -721, -874) - and its whole line 50 cm higher: "just remove
    -- the 2 sets of donuts on the carpet ride track and make the carpet go a little higher", 2026-11-02.
    -- (Bowser in the Sky's red coin over the gap by the metal box, scene (0, -2220): 3.5 m over the box's top (-2845) -
    -- down 1.7 m, 1.8 m over it, a jump off the box: "red coin is too High", 2026-11-02)
    bits = { { what = "the red coin over the metal box", relocate = { { "coin", 0.0, -2220.0, 0.0, -2220.0, -2690.0 } } },
             -- (and the flamethrower in the stone block under the bolted green platform, scene (1436, 4849, 2798): "remove
             -- this flamer thrower", 2026-11-02 - its block, the level's, stays)
             { what = "the flamethrower under the green platform", remove = { { "enemy", 1436.0, 4849.0 } } },
             -- (and its block, the nozzle's, scene x 1301..1570, y 4733..4964, z 2607..2876: "its still there" - 24 drawn
             -- triangles and 18 solid, nothing else in the box)
             { delete = true, what = "the flamethrower's block", box = { 6300, 6630, 3460, 3845, -2105, -1725 } },
             -- (and the beam between the two wooden pillars by the purple switch, scene x 447..908, turned 45 degrees on its
             -- length - an edge up: laid flat, its corners turned back about its middle (y -93, z 2205), its top at 2259,
             -- the red coin 1 m over it - "make this block lay flat instead of angled", 2026-11-02)
             { what = "the turned beam between the pillars, laid flat", moves = {
                         { { -227.00, 2940.00, -597.00 }, { -196.98, 3012.48, -597.00} }, { {-125.00, 2839.00, -597.00 }, { -196.27, 2868.94, -597.00} },
                         { {-125.00, 3043.00, -597.00 }, { -52.02, 3013.19, -597.00} }, { {-124.00, 2837.00, -597.00 }, { -196.98, 2866.81, -597.00} },
                         { {-124.00, 3042.00, -597.00 }, { -52.02, 3011.77, -597.00} }, { {-22.00, 2940.00, -597.00 }, { -52.02, 2867.52, -597.00} },
                         { {-227.00, 2940.00, -1210.00 }, { -196.98, 3012.48, -1210.00} }, { {-125.00, 2839.00, -1210.00 }, { -196.27, 2868.94, -1210.00} },
                         { {-125.00, 3043.00, -1210.00 }, { -52.02, 3013.19, -1210.00} }, { {-22.00, 2940.00, -1210.00 }, { -52.02, 2867.52, -1210.00} },
                         { {-227.00, 2940.00, -1211.00 }, { -196.98, 3012.48, -1211.00} }, { {-124.00, 2837.00, -1211.00 }, { -196.98, 2866.81, -1211.00} },
                         { {-124.00, 3042.00, -1211.00 }, { -52.02, 3011.77, -1211.00} }, { {-22.00, 2940.00, -1211.00 }, { -52.02, 2867.52, -1211.00 } } } },
             -- (and its twin 12 m on, scene x 447..908, y -1399..-1245, z 2205..2359, as turned: laid flat the same way about
             -- its middle (y -1322, z 2282), its top at 2336 - "also do the same thing to the other one", 2026-11-02. Both
             -- tops' edges ledges, not bars: ledges.lua M.PLAIN)
             { what = "the other turned beam, laid flat", moves = {
                         { { -1865.00, 3042.00, -597.00 }, { -1835.33, 3114.62, -597.00 } }, { { -1865.00, 3043.00, -597.00 }, { -1834.62, 3115.33, -597.00 } },
                         { { -1763.00, 2940.00, -597.00 }, { -1835.33, 2970.38, -597.00 } }, { { -1763.00, 3145.00, -597.00 }, { -1690.38, 3115.33, -597.00 } },
                         { { -1762.00, 2940.00, -597.00 }, { -1834.62, 2969.67, -597.00 } }, { { -1762.00, 3145.00, -597.00 }, { -1689.67, 3114.62, -597.00 } },
                         { { -1660.00, 3042.00, -597.00 }, { -1690.38, 2969.67, -597.00 } }, { { -1660.00, 3043.00, -597.00 }, { -1689.67, 2970.38, -597.00 } },
                         { { -1865.00, 3043.00, -1210.00 }, { -1834.62, 3115.33, -1210.00 } }, { { -1762.00, 2940.00, -1210.00 }, { -1834.62, 2969.67, -1210.00 } },
                         { { -1762.00, 3145.00, -1210.00 }, { -1689.67, 3114.62, -1210.00 } }, { { -1660.00, 3043.00, -1210.00 }, { -1689.67, 2970.38, -1210.00 } },
                         { { -1865.00, 3042.00, -1211.00 }, { -1835.33, 3114.62, -1211.00 } }, { { -1763.00, 2940.00, -1211.00 }, { -1835.33, 2970.38, -1211.00 } },
                         { { -1763.00, 3145.00, -1211.00 }, { -1690.38, 3115.33, -1211.00 } }, { { -1660.00, 3042.00, -1211.00 }, { -1690.38, 2969.67, -1211.00 } } } },
             -- (the stone shelf under the stairs down from the far platform, scene x 3367..3598, y -428..953, its top 4413:
             -- the stairs' underside over it 4528..4605, 140 cm clear where the red coin is (x 3439, y 261) - Mario's room, not
             -- the athlete's 176. Down 90 cm, all of it - top 4323, the wall over its back stretched down with it: 2.3 m
             -- clear at the coin, 2 m at the back - "cant get under the bridge to get this coin", "lower the floor",
             -- 2026-11-02. 8 solid corners and 14 drawn, nothing else in the box)
             { dz = -120.0, stretch = true, what = "the shelf under the stairs", box = { -587, 1287, 5820, 5894, -4814, -4473 } },
             -- (and its red coin down with it, 28 cm over its top again)
             { what = "the red coin under the stairs", relocate = { { "coin", 3439.0, 261.0, 3439.0, 261.0, 4351.0 } } } },
    rr = { -- (the ghost race's star, 7: a ledge 3 m on off the corner of the stone floor by the steps, scene (-3464, -902),
           -- the way to the next floor 14 m on (61 degrees), 2.4 m wide, rounded at its end and where it leaves the corner -
           -- "make a platform extention here only for this star", "Short ledge (~3 m)", "its at a corner so round it off a bit
           -- too", 2026-11-08. As thick as the floor, its top 2 cm under it (no flicker where they overlap); RR's stone laid
           -- at the floor's own slant, `affine`; shaded as the floor's top is, 0.78 - "make it a shade darker too")
           { star = 7, what = "the ledge off the stone floor's corner",
             add = { side = "textures__sky__rr_textures.07000.rgba16", top = "textures__sky__rr_textures.07000.rgba16", solid = true,
                     tint = 0.78,
                     side_uv = { affine = { -0.003245, 0.003245, 0.003045, -5.2994, 0.003174, 0.003174, 0.00322, 18.0125 } },
                     top_uv = { affine = { 0.003245, 0.003217, 18.7234, 0.003249, -0.003249, 7.6727 } },
                     prisms = {
                                { z0 = -991.0, z1 = -839.0, sides = { false, true, false, true }, corners = { { -3555.6, -1057.0 }, { -3546.9, -1061.9 }, { -3509.7, -1073.3 }, { -3585.1, -1031.5 } } },
                                { z0 = -991.0, z1 = -839.0, sides = { false, true, false, true }, corners = { { -3585.1, -1031.5 }, { -3509.7, -1073.3 }, { -3483.6, -1074.1 }, { -3599.6, -1009.8 } } },
                                { z0 = -991.0, z1 = -839.0, sides = { false, true, false, true }, corners = { { -3599.6, -1009.8 }, { -3483.6, -1074.1 }, { -3458.9, -1069.5 }, { -3608.8, -986.4 } } },
                                { z0 = -991.0, z1 = -839.0, sides = { false, true, false, true }, corners = { { -3608.8, -986.4 }, { -3458.9, -1069.5 }, { -3431.3, -1057.3 }, { -3613.1, -956.6 } } },
                                { z0 = -991.0, z1 = -839.0, sides = { false, true, false, true }, corners = { { -3613.1, -956.6 }, { -3431.3, -1057.3 }, { -3406.0, -1037.0 }, { -3609.3, -924.4 } } },
                                { z0 = -991.0, z1 = -839.0, sides = { false, true, false, true }, corners = { { -3609.3, -924.4 }, { -3406.0, -1037.0 }, { -3388.1, -1012.7 }, { -3598.0, -896.3 } } },
                                { z0 = -991.0, z1 = -839.0, sides = { false, true, false, true }, corners = { { -3598.0, -896.3 }, { -3388.1, -1012.7 }, { -3349.3, -942.7 }, { -3559.3, -826.3 } } },
                                { z0 = -991.0, z1 = -839.0, sides = { false, true, false, true }, corners = { { -3559.3, -826.3 }, { -3349.3, -942.7 }, { -3310.6, -872.7 }, { -3520.5, -756.4 } } },
                                { z0 = -991.0, z1 = -839.0, sides = { false, true, false, true }, corners = { { -3520.5, -756.4 }, { -3310.6, -872.7 }, { -3271.8, -802.7 }, { -3481.7, -686.4 } } },
                                { z0 = -991.0, z1 = -839.0, sides = { false, true, false, true }, corners = { { -3481.7, -686.4 }, { -3271.8, -802.7 }, { -3260.6, -774.7 }, { -3463.8, -662.0 } } },
                                { z0 = -991.0, z1 = -839.0, sides = { false, true, false, true }, corners = { { -3463.8, -662.0 }, { -3260.6, -774.7 }, { -3256.8, -742.5 }, { -3438.5, -641.7 } } },
                                { z0 = -991.0, z1 = -839.0, sides = { false, true, false, true }, corners = { { -3438.5, -641.7 }, { -3256.8, -742.5 }, { -3261.1, -712.6 }, { -3411.0, -629.6 } } },
                                { z0 = -991.0, z1 = -839.0, sides = { false, true, false, true }, corners = { { -3411.0, -629.6 }, { -3261.1, -712.6 }, { -3270.2, -689.3 }, { -3386.3, -624.9 } } },
                                { z0 = -991.0, z1 = -839.0, sides = { false, true, false, true }, corners = { { -3386.3, -624.9 }, { -3270.2, -689.3 }, { -3284.8, -667.5 }, { -3360.1, -625.7 } } },
                                { z0 = -991.0, z1 = -839.0, sides = { false, true, false, true }, corners = { { -3360.1, -625.7 }, { -3284.8, -667.5 }, { -3314.2, -642.0 }, { -3322.9, -637.2 } } },
                     } } },
           { what = "the donut platforms over the carpet's line",
             remove = { { "platform", 130.0, 179.0 }, { "platform", 130.0, 26.0 }, { "platform", 130.0, -127.0 },
                        { "platform", 140.0, -567.0 }, { "platform", 140.0, -721.0 }, { "platform", 140.0, -874.0 } } },
           { dz = 66.67, what = "the carpet along x 120, its line", objects = { { "platform", 138.0, 485.0 } } },
           -- (the block over the next carpet's line by the tiled floor, scene x -209..98, y 1441..1556, its top 1882..2036:
           -- "remove this block", 2026-11-02. 16 drawn triangles, 16 solid, 4 of them slide floors - nothing else in the box)
           { delete = true, what = "the block over the carpet's line by the tiled floor", box = { 1907, 2093, 2493, 2727, -147, 293 } },
           -- (the wooden wedge up from the plank by the goomba, scene x -5153..-4693, y 249..556, 45 degrees, its face a
           -- slide floor: walked up and down now - "make this wood triangle walkable", "im still sliding on it",
           -- 2026-11-02. Its two slide floors, nothing else in the box)
           { unslide = true, what = "the wooden wedge up from the plank", box = { 307, 767, -1947, -1507, 6233, 6893 } },
           -- (and its far side, 45 degrees down from its top, y 633..940: he slid down it off the top)
           { unslide = true, what = "the wooden wedge's far side", box = { 820, 1260, -1960, -1500, 6233, 6893 } },
           -- (its six hidden blue coins - one in the slot by the switch, five 26 m over the tower - in a line along the
           -- switch's ledge instead, 4 m apart from 1.5 m off where he stood (x -465, y -4921), still out only once the
           -- switch is pressed)
           { what = "the blue coins, in a line along the switch's ledge", relocate = {
                 { "coin", 0.0, -5062.0, -465.0, -4771.0, -1306.0 }, { "coin", 0.0, -4875.0, -465.0, -4371.0, -1306.0 },
                 { "coin", 0.0, -4650.0, -465.0, -3971.0, -1306.0 }, { "coin", 0.0, -4425.0, -465.0, -3571.0, -1306.0 },
                 { "coin", 0.0, -4200.0, -465.0, -3171.0, -1306.0 }, { "coin", 0.0, -3975.0, -465.0, -2771.0, -1306.0 } } } },
}
-- Drawn triangles taken out of `data`'s sections in the pictures `mv.cut`: those with all three corners in
-- `mv.cut_strip` { ax, ay, bx, by, half, z0, z1 } (scene cm) - within `half` of the line a-b, between its ends (2 cm
-- either way) and between heights z0 and z1. Drawn only: what is solid is left. The number taken out.
function G.cut_drawn(data, mv)
    local cs = mv.cut_strip
    local ax, ay, bx, by, half, z0, z1 = cs[1], cs[2], cs[3], cs[4], cs[5], cs[6], cs[7]
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    local ux, uy = dx / len, dy / len
    local want = {}
    for _, t in ipairs(mv.cut) do want[t] = true end
    local n = 0
    for _, s in ipairs(data.sections or {}) do
        if want[s.texture] then
            local P, I, keep = s.pos, s.idx, {}
            for t = 1, #I, 3 do
                local inside = true
                for k = 0, 2 do
                    local v = I[t + k]
                    local x, y, z = P[v * 3 + 1], P[v * 3 + 2], P[v * 3 + 3]
                    local rx, ry = x - ax, y - ay
                    local al, off = rx * ux + ry * uy, -rx * uy + ry * ux
                    if al < -2.0 or al > len + 2.0 or math.abs(off) > half or z < z0 or z > z1 then inside = false; break end
                end
                if inside then
                    n = n + 1
                else
                    keep[#keep + 1], keep[#keep + 2], keep[#keep + 3] = I[t], I[t + 1], I[t + 2]
                end
            end
            s.idx, s.ntris = keep, #keep // 3
        end
    end
    return n
end

-- An object's place, scene cm, x and y: a platform's is Mario 64's (x, height, z, in its units), the others' scene cm
function G.obj_xy(o)
    if o.kind == "platform" then return -o.pos[3] * 0.75, o.pos[1] * 0.75 end
    return o.pos[1], o.pos[2]
end

-- Lethal Lava Land: a stone plank out over the lava from the walkway's end facing the volcano (its edge scene x -2498,
-- y 14), 5.5 m on and 1.5 m wide at the walkway's height, solid, in the walkway's own stone laid on as it is, on a
-- stone beam up out of the lava near its end - "also put a small bridge down infront of me", "Short plank, ~4 m", then
-- "give it a support beam make it a bit longer and only show that platform for star 7", 2026-11-07. Only in its 7th
-- star, the ghost race (`star`: G.move_pieces).
G.MOVE_PIECES.lll = { { what = "the plank off the walkway toward the volcano", star = 7,
    add = { side = "levels__lll__9.rgba16", top = "levels__lll__9.rgba16", solid = true,
            side_uv = { x0 = -2592.8, y0 = 378.5, z0 = 230.0, v0 = 0.0, ux = 0.0052, uy = 0.0052, vz = 0.0052 },
            top_uv = { x0 = -2592.8, y0 = 378.5, v0 = 0.4668, uy = 0.0051995, vx = 0.005209 },
            prisms = { { z0 = 200.0, z1 = 230.0, sides = { true, true, true, false },
                         corners = { { -2508.0, -61.0 }, { -1948.0, -61.0 }, { -1948.0, 89.0 }, { -2508.0, 89.0 } } },
                       { z0 = -60.0, z1 = 200.0, top = false, sides = { true, true, true, true },
                         corners = { { -2033.0, -11.0 }, { -1983.0, -11.0 }, { -1983.0, 39.0 }, { -2033.0, 39.0 } } } } } } }
-- Dire, Dire Docks' 7th star, the ghost race: a raft at the start, out on the water by the way in (its middle scene x
-- 1273, y -2399; the water's top at 0): 4.7 m on the way the race runs (+x) and 5.2 m across, its deck 25 cm over the
-- water and 35 under it, solid, in Jolly Roger Bay's ship's wood - the start line on it 1.2 m from its front, room
-- behind for him and the racer lined up - "start here", "we need a custom start a raft of some sort", 2026-11-07. Off
-- the spot he drops in at (x 0) - "platform not in right area" - and put just in front of him where he swam, 9 m on
-- ("put it in front of me").
G.MOVE_PIECES.ddd = G.MOVE_PIECES.ddd or {}
G.MOVE_PIECES.ddd[#G.MOVE_PIECES.ddd + 1] = { what = "the race's raft", star = 7,
    add = { side = "textures__water__jrb_textures.0A000.rgba16", top = "textures__water__jrb_textures.0A000.rgba16",
            solid = true, new_section = true,
            side_uv = { x0 = 1038.0, y0 = -2139.0, z0 = 25.0, v0 = 0.0, ux = 0.01, uy = 0.01, vz = 0.01 },
            top_uv = { x0 = 1038.0, y0 = -2139.0, v0 = 0.0, uy = 0.01, vx = 0.01 },
            prisms = { { z0 = -35.0, z1 = 25.0, sides = { true, true, true, true },
                         corners = { { 1038.0, -2659.0 }, { 1508.0, -2659.0 }, { 1508.0, -2139.0 }, { 1038.0, -2139.0 } } } } } }
-- Bowser in the Fire Sea: the black square Mario 64 draws across the elevator's shaft (scene x -385..-77, y 1996..2304,
-- 1.84 m up - untextured, black) taken out, and its upper lava cut round the shaft (movtex.lua M.HOLES): he rode up
-- through both - "lava inside elevator also black plate?", "Remove both from shaft", 2026-11-07. (`box`: Mario 64 units)
G.MOVE_PIECES.bitfs = G.MOVE_PIECES.bitfs or {}
G.MOVE_PIECES.bitfs[#G.MOVE_PIECES.bitfs + 1] = { what = "the black square across the elevator's shaft", delete = true,
    box = { 2650.0, 3085.0, 240.0, 251.0, 95.0, 520.0 } }
-- Shifting Sand Land's 7th star, the ghost race: the Bob-omb 4 m from its start line (scene -4838, 1312) left out - it
-- came for him as he was lined up: "on this specifc star remove the bombomb closest to the race start", 2026-11-07
G.MOVE_PIECES.ssl = { { what = "the Bob-omb by the race's start", star = 7, remove = { { "bobomb", -4838.0, 1312.0 } } } }
-- Hazy Maze Cave's 7th star, the ghost race: the Scuttlebug 8 m from its start line (scene -5055, -4740) left out - "for
-- this star only remove the spider creature closest to the race start", 2026-11-07 (the cave's own pieces kept)
G.MOVE_PIECES.hmc[#G.MOVE_PIECES.hmc + 1] = { what = "the Scuttlebug by the race's start", star = 7,
    remove = { { "enemy", -5055.0, -4740.0 } } }
-- (and the pink grate cage by the breakable block (scene x -3302..-2918, y 1536..2074): its peaked roof, 8.44 to 9.98 m,
-- made flat at its eaves, 8.44 m, solid across - "make the top of this cage flat for this star only", 2026-11-07)
G.MOVE_PIECES.hmc[#G.MOVE_PIECES.hmc + 1] = { what = "the grate cage's top made flat", star = 7,
    cap = { -3305.0, -2915.0, 1533.0, 2077.0, 844.0, 1000.0 }, cap_tex = "textures__cave__hmc_textures.01000.rgba16" }
-- Tall, Tall Mountain's 7th star, the ghost race: the three Goombas 4 to 7 m from its start line (scene -3990, 1470;
-- -4133, 1222; -3847, 1222) left out - "also for this star only remove the 3 goombas closest to the start", 2026-11-07
-- (the mountain's own pieces kept)
G.MOVE_PIECES.ttm[#G.MOVE_PIECES.ttm + 1] = { what = "the three Goombas by the race's start", star = 7,
    remove = { { "goomba", -3990.0, 1470.0 }, { "goomba", -4133.0, 1222.0 }, { "goomba", -3847.0, 1222.0 } } }
-- Tiny-Huge Island's 7th star, the ghost race, begun on the tiny island (G.STAR_START): the tiny Goomba 1.4 m from its
-- start line (scene -1290, -1515) left out - "race start also remove the goomba that spawns here for this star only",
-- 2026-11-07 (the island's own pieces kept) - and the one on the grass ledge 1.5 m over its way on (-788, -775): "also
-- remove this goomba here for star 7 only" - and the one on the peak by its pipe (112, -412): "remove the tiny goomba
-- infront of me for this star only", 2026-11-08
G.MOVE_PIECES.thi_2[#G.MOVE_PIECES.thi_2 + 1] = { what = "the Goombas by the race's start", star = 7,
    remove = { { "goomba", -1290.0, -1515.0 }, { "goomba", -788.0, -775.0 }, { "goomba", 112.0, -412.0 } } }
-- Tiny-Huge Island's tiny island: its two goombas by the north pipe (688, 1611; 1133, 1366) left out in every star -
-- "the two goombas here need removed from the game completely", 2026-11-08
G.MOVE_PIECES.thi_2[#G.MOVE_PIECES.thi_2 + 1] = { what = "the two goombas by the north pipe",
    remove = { { "goomba", 688.0, 1611.0 }, { "goomba", 1133.0, 1366.0 } } }
function G.move_pieces(name, data)
    local list = G.MOVE_PIECES[name]
    if not list or data.pieces_moved then return end
    data.pieces_moved = true
    -- (slide floors a `cap` took out for one star put back first: G.slide_data is kept from scene to scene)
    do
        local sd = G.slide_data and G.slide_data[name]
        if sd and sd.cap_out then
            for _, v in ipairs(sd.cap_out) do sd.idx[#sd.idx + 1] = v end
            sd.ntris, sd.cap_out = #sd.idx // 3, nil
        end
    end
    -- (`star`: that piece only in that star of the course, as chosen at the star select - LLL's plank, its ghost race's)
    do
        local ca = G.course_act
        local act = ca and ca.course == (data.level or name) and ca.act or nil
        local only = {}
        for _, mv in ipairs(list) do if not mv.star or mv.star == act then only[#only + 1] = mv end end
        list = only
    end
    for _, mv in ipairs(list) do
        if mv.cut then
            local okc, nc = pcall(G.cut_drawn, data, mv)
            log("scene %s: %s", name, okc and string.format("%d triangles taken out for %s", nc, mv.what) or ("nothing cut: " .. tostring(nc)))
        end
        -- (`delete` with `box` - Mario 64 units, as below: the drawn triangles and the solid all inside it taken out of the
        -- level, and its slide floors with them - a block in RR over a carpet's line, "remove this block", 2026-11-02.
        -- `unslide`: only its slide floors taken out - plain floor, walked on - RR's wooden ramp, "make this wood
        -- triangle walkable", 2026-11-02)
        if (mv.delete or mv.unslide) and mv.box then
            local db = mv.box
            local function inb(P, i)
                local x, y, z = P[i * 3 + 2] / 0.75, P[i * 3 + 3] / 0.75, -P[i * 3 + 1] / 0.75
                return x > db[1] and x < db[2] and y > db[3] and y < db[4] and z > db[5] and z < db[6]
            end
            local function cut(m)
                local P, I = m.pos, m.idx
                if not (P and I) then return 0 end
                local keep, n = {}, 0
                for t = 1, #I - 2, 3 do
                    local a, b, c = I[t], I[t + 1], I[t + 2]
                    if inb(P, a) and inb(P, b) and inb(P, c) then n = n + 1
                    else keep[#keep + 1], keep[#keep + 2], keep[#keep + 3] = a, b, c end
                end
                if n > 0 then m.idx, m.ntris = keep, #keep // 3 end
                return n
            end
            local nd, nc, nsl = 0, 0, 0
            if mv.delete then
                for _, sec in ipairs(data.sections or {}) do nd = nd + cut(sec) end
                for _, c in ipairs(data.collision or {}) do nc = nc + cut(c) end
                if data.vanish_walls then nc = nc + cut(data.vanish_walls) end
            end
            -- (the slide floors: G.slide_data is kept from scene to scene, so taken out of it once)
            if G.slide_data == nil then G.slide_data = lib.load_data("data.slides") or false end
            local sd = G.slide_data and G.slide_data[name]
            if sd and not (sd.deleted and sd.deleted[mv.what]) then
                sd.deleted = sd.deleted or {}
                sd.deleted[mv.what] = true
                nsl = cut(sd)
            end
            if mv.delete then
                log("scene %s: %s taken out (%d drawn triangles, %d solid, %d slide floors)", name, mv.what, nd, nc, nsl)
            else
                log("scene %s: %s plain floor (%d slide floors no more)", name, mv.what, nsl)
            end
            goto next_piece
        end
        -- (`relocate`: { kind, x, y, nx, ny, nz } a piece - the level's object of that kind at x, y (scene cm, within 30)
        -- put at nx, ny, nz instead: RR's six blue coins, in a line along the switch's ledge - "put them in a line infront
        -- of me", "spread them further apart", "make sure they're tied to the blue coin switch", 2026-11-02)
        if mv.relocate then
            local n = 0
            for _, r in ipairs(mv.relocate) do
                for _, o in ipairs(data.objects or {}) do
                    if o.kind == r[1] and o.pos and not o.relocated then
                        local ox, oy = G.obj_xy(o)
                        if abs(ox - r[2]) < 30.0 and abs(oy - r[3]) < 30.0 then
                            o.pos = { r[4], r[5], r[6] }
                            if o.sm64 then o.sm64 = { r[5] / 0.75, r[6] / 0.75, -r[4] / 0.75 } end
                            o.relocated = true
                            n = n + 1
                            break
                        end
                    end
                end
            end
            log("scene %s: %s put elsewhere (%d)", name, mv.what, n)
            goto next_piece
        end
        -- (`cap`: { x0, x1, y0, y1, z, zmax } scene cm - in that column every corner over z and up to zmax, drawn (of
        -- `cap_tex` when given) and solid, brought down to z, and a solid top laid flat across it at z: a roof made flat.
        -- Its slide floors with a corner up there taken out too - they are solid of their own, the old slope still there
        -- over the flat top: "you have to make the hitbox flat too", 2026-11-07 - and kept to be put back above)
        if mv.cap then
            local c = mv.cap
            local nd, nc = 0, 0
            local function cap_list(list, tex, count)
                for _, m in ipairs(list or {}) do
                    local P = m.pos
                    if P and (not tex or m.texture == tex) then
                        for i = 1, #P, 3 do
                            local z = P[i + 2]
                            if z > c[5] and z <= c[6] and P[i] >= c[1] and P[i] <= c[2] and P[i + 1] >= c[3] and P[i + 1] <= c[4] then
                                P[i + 2] = c[5]
                                count = count + 1
                            end
                        end
                    end
                end
                return count
            end
            nd = cap_list(data.sections, mv.cap_tex, 0)
            nc = cap_list(data.collision, nil, 0)
            if G.slide_data == nil then G.slide_data = lib.load_data("data.slides") or false end
            local sd = G.slide_data and G.slide_data[name]
            local nsl = 0
            if sd and sd.pos and sd.idx then
                local P, I = sd.pos, sd.idx
                local function up(i)
                    local z = P[i * 3 + 3]
                    return z > c[5] and z <= c[6] and P[i * 3 + 1] >= c[1] and P[i * 3 + 1] <= c[2] and P[i * 3 + 2] >= c[3] and P[i * 3 + 2] <= c[4]
                end
                local keep, out = {}, sd.cap_out or {}
                for t = 1, #I - 2, 3 do
                    local a, b, d = I[t], I[t + 1], I[t + 2]
                    if up(a) or up(b) or up(d) then
                        out[#out + 1], out[#out + 2], out[#out + 3] = a, b, d
                        nsl = nsl + 1
                    else
                        keep[#keep + 1], keep[#keep + 2], keep[#keep + 3] = a, b, d
                    end
                end
                if nsl > 0 then sd.idx, sd.ntris, sd.cap_out = keep, #keep // 3, out end
            end
            local ok = pcall(G.add_prisms, data, { side = mv.cap_tex, top = "(none)", solid = true,
                prisms = { { z0 = c[5] - 1.0, z1 = c[5], sides = { false, false, false, false },
                             corners = { { c[1], c[3] }, { c[2], c[3] }, { c[2], c[4] }, { c[1], c[4] } } } } })
            log("scene %s: %s - %d drawn corners and %d solid brought down to %.0f, %d slide floors out, its top solid (%s)", name, mv.what, nd, nc, c[5], nsl, tostring(ok))
            goto next_piece
        end
        if mv.remove then
            local n = 0
            for _, r in ipairs(mv.remove) do
                for i = #(data.objects or {}), 1, -1 do
                    local o = data.objects[i]
                    local ox, oy = 0.0, 0.0
                    if o.pos then ox, oy = G.obj_xy(o) end
                    if o.kind == r[1] and o.pos and abs(ox - r[2]) < 30.0 and abs(oy - r[3]) < 30.0 then
                        table.remove(data.objects, i)
                        n = n + 1
                    end
                end
            end
            log("scene %s: %s left out (%d)", name, mv.what, n)
            goto next_piece
        end
        if mv.underside then
            local ok, n = pcall(G.add_underside, data, mv)
            log("scene %s: %s", name, ok and string.format("%d faces under %s", n, mv.what) or ("no underside: " .. tostring(n)))
            goto next_piece
        end
        if mv.lift then
            -- (`lift`: { u0, u1, w0, w1, from, to, top } - Mario 64 units: every corner, drawn and solid, inside the strip
            -- u0 <= x + z <= u1, w0 <= x - z <= w1 (a piece lying at 45 degrees) and from - 5 <= y < top, put up so that
            -- `from` goes to `to` and `top` stays: what is between pressed up with it, nothing torn. With `square`, the
            -- first four are x0, x1, z0, z1: a piece square to the axes.)
            local L, nm = mv.lift, 0
            local function lift_all(m)
                local P = m.pos
                if not P then return end
                m.n0 = m.n0 or #P // 3
                for i = 0, m.n0 - 1 do
                    local x, y, z = P[i * 3 + 2] / 0.75, P[i * 3 + 3] / 0.75, -P[i * 3 + 1] / 0.75
                    local u, w = x + z, x - z
                    if mv.square then u, w = x, z end
                    if u >= L[1] and u <= L[2] and w >= L[3] and w <= L[4] and y >= L[5] - 5.0 and y < L[7] then
                        local ny = L[6] + (math.max(y, L[5]) - L[5]) * (L[7] - L[6]) / (L[7] - L[5])
                        P[i * 3 + 3] = ny * 0.75
                        nm = nm + 1
                    end
                end
            end
            for _, sec in ipairs(data.sections or {}) do lift_all(sec) end
            for _, c in ipairs(data.collision or {}) do lift_all(c) end
            log("scene %s: %s - %d corners moved", name, mv.what, nm)
            goto next_piece
        end
        if mv.moves then
            -- (`moves`: { { from, to }, ... } - Mario 64 units: every corner at `from` - drawn and solid, the level's own
            -- ones - put at `to`, every triangle that has it with it: WDW town's tower walls out to its roof's edge)
            local nm = 0
            local function shift_all(m)
                local P = m.pos
                if not P then return end
                m.n0 = m.n0 or #P // 3
                for i = 0, m.n0 - 1 do
                    for _, ft in ipairs(mv.moves) do
                        local f, t = ft[1], ft[2]
                        if abs(P[i * 3 + 1] + f[3] * 0.75) < 1.5 and abs(P[i * 3 + 2] - f[1] * 0.75) < 1.5 and abs(P[i * 3 + 3] - f[2] * 0.75) < 1.5 then
                            P[i * 3 + 1], P[i * 3 + 2], P[i * 3 + 3] = -t[3] * 0.75, t[1] * 0.75, t[2] * 0.75
                            nm = nm + 1
                            break
                        end
                    end
                end
            end
            for _, sec in ipairs(data.sections or {}) do shift_all(sec) end
            for _, c in ipairs(data.collision or {}) do shift_all(c) end
            log("scene %s: %s - %d corners moved", name, mv.what, nm)
            goto next_piece
        end
        if mv.add then
            local oka, na = pcall(G.add_prisms, data, mv.add)
            log("scene %s: %s", name, oka and string.format("%d faces added for %s", na, mv.what) or ("pieces not added: " .. tostring(na)))
        end
        local keys = {}
        for _, c in ipairs(mv.corners or {}) do keys[#keys + 1] = { -c[3] * 0.75, c[1] * 0.75, c[2] * 0.75 } end
        local bx = mv.box
        local function corner(P, i, n0)
            if i >= n0 then return false end      -- (a corner an earlier piece already moved)
            if bx then
                -- (scene cm back to Mario 64 units: x = y, y = z, z = -x)
                local x, y, z = P[i * 3 + 2] / 0.75, P[i * 3 + 3] / 0.75, -P[i * 3 + 1] / 0.75
                return x > bx[1] and x < bx[2] and y > bx[3] and y < bx[4] and z > bx[5] and z < bx[6]
            end
            for _, k in ipairs(keys) do
                if abs(P[i * 3 + 1] - k[1]) < 1.5 and abs(P[i * 3 + 2] - k[2]) < 1.5 and abs(P[i * 3 + 3] - k[3]) < 1.5 then return true end
            end
            return false
        end
        local dz = (mv.dz or 0.0) * 0.75
        local sc = mv.scale and { -mv.scale[3] * 0.75, mv.scale[1] * 0.75, mv.scale[2] * 0.75, mv.scale[4] }
        local tn = mv.turn and { mv.turn[1], mv.turn[2], math.cos(math.rad(mv.turn[3])), math.sin(math.rad(mv.turn[3])) }
        local sh = mv.shift
        local function turned(x, y)
            if tn then
                local dx, dy = x - tn[1], y - tn[2]
                x, y = tn[1] + dx * tn[3] - dy * tn[4], tn[2] + dx * tn[4] + dy * tn[3]
            end
            if sh then x, y = x + sh[1], y + sh[2] end
            return x, y
        end
        local extra = mv.solid_drawn and {} or nil        -- (its drawn triangles' corners, three a triangle, for its solid)
        local function stretch(m)
            local P = m.pos
            if not P then return 0 end
            local n = #P // 3
            m.n0 = m.n0 or n
            local c = 0
            for i = 0, n - 1 do
                if corner(P, i, m.n0) then P[i * 3 + 3] = P[i * 3 + 3] + dz; c = c + 1 end
            end
            return c
        end
        local function move(m, per)
            if mv.stretch then return stretch(m) end
            local P, keep, moved, remap = m.pos, {}, {}, {}
            if not (P and m.idx) then return 0 end
            local n = #P // 3
            m.n0 = m.n0 or n
            local n0 = m.n0
            for t = 0, #m.idx // 3 - 1 do
                local a, b, c = m.idx[t * 3 + 1], m.idx[t * 3 + 2], m.idx[t * 3 + 3]
                if corner(P, a, n0) and corner(P, b, n0) and corner(P, c, n0) then
                    local m0 = #moved
                    for _, i in ipairs({ a, b, c }) do
                        if not remap[i] then
                            remap[i] = n
                            n = n + 1
                            local x, y, z = P[i * 3 + 1], P[i * 3 + 2], P[i * 3 + 3]
                            local sq = mv.squash
                            if sc then
                                x, y, z = sc[1] + (x - sc[1]) * sc[4], sc[2] + (y - sc[2]) * sc[4], sc[3] + (z - sc[3]) * sc[4]
                            elseif sq then z = sq.top - (sq.top - z) * (sq.top - sq.to) / (sq.top - sq.from) else z = z + dz end
                            x, y = turned(x, y)
                            P[#P + 1], P[#P + 2], P[#P + 3] = x, y, z
                            for f, w in pairs(per) do
                                local arr = m[f]
                                if arr then for q = 1, w do arr[#arr + 1] = arr[i * w + q] end end
                            end
                            if tn and per.nrm and m.nrm then
                                local N = m.nrm
                                local k = #N - 3
                                local nx, ny = N[k + 1], N[k + 2]
                                N[k + 1], N[k + 2] = nx * tn[3] - ny * tn[4], nx * tn[4] + ny * tn[3]
                            end
                        end
                        moved[#moved + 1] = remap[i]
                    end
                    -- (a drawn triangle moved keeps its room: rooms.lua finds it by its middle where it was)
                    if per.uv then
                        local function mid(x, y, z) return string.format("%.1f,%.1f,%.1f", x, y, z) end
                        local o1, o2, o3 = a * 3, b * 3, c * 3
                        local n1, n2, n3 = moved[m0 + 1] * 3, moved[m0 + 2] * 3, moved[m0 + 3] * 3
                        data.room_alias = data.room_alias or {}
                        data.room_alias[mid((P[n1 + 1] + P[n2 + 1] + P[n3 + 1]) / 3.0, (P[n1 + 2] + P[n2 + 2] + P[n3 + 2]) / 3.0,
                            (P[n1 + 3] + P[n2 + 3] + P[n3 + 3]) / 3.0)] =
                            mid((P[o1 + 1] + P[o2 + 1] + P[o3 + 1]) / 3.0, (P[o1 + 2] + P[o2 + 2] + P[o3 + 2]) / 3.0,
                                (P[o1 + 3] + P[o2 + 3] + P[o3 + 3]) / 3.0)
                    end
                else
                    keep[#keep + 1], keep[#keep + 2], keep[#keep + 3] = a, b, c
                end
            end
            if #moved == 0 then return 0 end
            if mv.outer_last and per.uv and m.layer == "translucent" then G.outer_last(P, moved) end
            if extra and per.uv then
                -- (but not its doorway: the dark hole drawn on its dome, black at every corner)
                local C = m.col
                local function dark(v) return C and C[v * 4 + 1] + C[v * 4 + 2] + C[v * 4 + 3] < 0.15 end
                for q = 1, #moved - 2, 3 do
                    local a, b, c = moved[q], moved[q + 1], moved[q + 2]
                    if not (dark(a) and dark(b) and dark(c)) then
                        for _, v in ipairs({ a, b, c }) do extra[#extra + 1] = { P[v * 3 + 1], P[v * 3 + 2], P[v * 3 + 3] } end
                    end
                end
            end
            for _, v in ipairs(moved) do keep[#keep + 1] = v end
            m.idx = keep
            if m.nverts then m.nverts = n end
            m.ntris = #keep // 3
            return #moved // 3
        end
        local nd, nc = 0, 0
        local tex = nil
        for _, t in ipairs(mv.textures or {}) do tex = tex or {}; tex[t] = true end
        for _, sec in ipairs(data.sections or {}) do
            if not tex or tex[sec.texture] then nd = nd + move(sec, { uv = 2, col = 4, nrm = 3 }) end
        end
        if not tex or mv.solid then for _, c in ipairs(data.collision or {}) do nc = nc + move(c, {}) end end
        -- (and the vanish-cap walls, apart from it: SL's igloo's ice walls are - lowered, they stood as high as ever:
        -- "you made it shorter but didnt fix collisions", 2026-10-26)
        if (not tex or mv.solid) and data.vanish_walls then nc = nc + move(data.vanish_walls, {}) end
        if extra and #extra > 0 and data.collision and data.collision[1] then
            local c1 = data.collision[1]
            local base = #c1.pos // 3
            for k, q in ipairs(extra) do
                c1.pos[#c1.pos + 1], c1.pos[#c1.pos + 2], c1.pos[#c1.pos + 3] = q[1], q[2], q[3]
                c1.idx[#c1.idx + 1] = base + k - 1
            end
            c1.ntris = #c1.idx // 3
            nc = nc + #extra // 3
            -- (its steep faces slide, where the scene's steep floors do - G.SLIDE_MIN: put with the slide floors, once)
            local lim = G.SLIDE_MIN and G.SLIDE_MIN[name]
            if lim then
                if G.slide_data == nil then G.slide_data = lib.load_data("data.slides") or false end
                local sd = G.slide_data and G.slide_data[name]
                if sd and not (sd.drawn_in and sd.drawn_in[mv.what]) then
                    sd.drawn_in = sd.drawn_in or {}
                    sd.drawn_in[mv.what] = true
                    local cl = math.cos(math.rad(lim))
                    local ns = 0
                    for q = 1, #extra - 2, 3 do
                        local A, B, C = extra[q], extra[q + 1], extra[q + 2]
                        local ux, uy, uz = B[1] - A[1], B[2] - A[2], B[3] - A[3]
                        local wx, wy, wz = C[1] - A[1], C[2] - A[2], C[3] - A[3]
                        -- (wound as the export winds them: (b - a) x (c - a) points in, so up is minus it)
                        local nx, ny, nz = -(uy * wz - uz * wy), -(uz * wx - ux * wz), -(ux * wy - uy * wx)
                        local l = math.sqrt(nx * nx + ny * ny + nz * nz)
                        if l > 1e-6 and nz / l > 0.05 and nz / l <= cl then
                            local base = #sd.pos // 3
                            for _, Q in ipairs({ A, B, C }) do sd.pos[#sd.pos + 1], sd.pos[#sd.pos + 2], sd.pos[#sd.pos + 3] = Q[1], Q[2], Q[3] end
                            sd.idx[#sd.idx + 1], sd.idx[#sd.idx + 2], sd.idx[#sd.idx + 3] = base, base + 1, base + 2
                            ns = ns + 1
                        end
                    end
                    sd.ntris = #sd.idx // 3
                    log("scene %s: %s - %d steep faces slide", name, mv.what, ns)
                end
            end
        end
        -- (the slide floors are cut out of the collision by their corners: moved alike, they still match. G.slide_data
        -- is kept from scene to scene, so moved only once)
        local nsl = 0
        if mv.slides then
            if G.slide_data == nil then G.slide_data = lib.load_data("data.slides") or false end
            local sd = G.slide_data and G.slide_data[name]
            if sd and not (sd.moved and sd.moved[mv.what]) then
                sd.moved = sd.moved or {}
                sd.moved[mv.what] = true
                nsl = move(sd, {})
            end
            -- (and its ice: G.ice_walk finds it by its corners too)
            if G.ice_data == nil then G.ice_data = lib.load_data("data.ice") or false end
            local ic = G.ice_data and G.ice_data[name]
            if ic and not (ic.moved and ic.moved[mv.what]) then
                ic.moved = ic.moved or {}
                ic.moved[mv.what] = true
                move(ic, {})
            end
        end
        -- (its warp triggers and arrival spots: scaled with it if in its box; `node_at` puts some where given)
        local nw = 0
        if sc and (mv.warps or mv.node_at) then
            local function inbox(q)
                local x, y, z = q[2] / 0.75, q[3] / 0.75, -q[1] / 0.75
                return bx and x > bx[1] and x < bx[2] and y > bx[3] - 50 and y < bx[4] and z > bx[5] and z < bx[6]
            end
            local function grow(q)
                q[1], q[2], q[3] = sc[1] + (q[1] - sc[1]) * sc[4], sc[2] + (q[2] - sc[2]) * sc[4], sc[3] + (q[3] - sc[3]) * sc[4]
                q[1], q[2] = turned(q[1], q[2])
            end
            for _, o in ipairs(mv.warps and data.objects or {}) do
                if o.kind == "warp" and o.pos and inbox(o.pos) then
                    grow(o.pos)
                    if o.radius then o.radius = o.radius * sc[4] end
                    nw = nw + 1
                end
            end
            for _, n in ipairs(data.nodes or {}) do
                if n.pos then
                    local at = mv.node_at and mv.node_at[n.id]
                    if at then n.pos[1], n.pos[2] = turned(at[1], at[2]); nw = nw + 1
                    elseif mv.warps and inbox(n.pos) then grow(n.pos); nw = nw + 1 end
                end
            end
        end
        local ns = 0
        for _, id in ipairs(mv.stars or {}) do
            for _, o in ipairs(data.objects or {}) do
                if o.kind == "star" and o.id == id and o.pos then
                    if sc then
                        local q = o.pos
                        q[1], q[2], q[3] = sc[1] + (q[1] - sc[1]) * sc[4], sc[2] + (q[2] - sc[2]) * sc[4], sc[3] + (q[3] - sc[3]) * sc[4]
                    else o.pos[3] = o.pos[3] + dz end
                    ns = ns + 1
                end
            end
        end
        -- (`objects`: { kind, x, y } - scene cm, within 30 - the level's objects there carried dz with it: the pole on
        -- WDW town's tower top and the coin on its ledge, 2026-10-28)
        for _, r in ipairs(mv.objects or {}) do
            for _, o in ipairs(data.objects or {}) do
                -- (a platform's place is Mario 64's - x, height, z, in its units - the others' scene cm: RR's donut
                -- platforms, 2026-11-02)
                local m64 = (o.kind == "platform")
                local sx, sy = 0.0, 0.0
                if o.pos then sx, sy = G.obj_xy(o) end
                if o.kind == r[1] and o.pos and abs(sx - r[2]) < 30.0 and abs(sy - r[3]) < 30.0 then
                    if m64 then o.pos[2] = o.pos[2] + dz / 0.75 else o.pos[3] = o.pos[3] + dz end
                    -- (one on a track - RR's carpets - its whole line with it: { flag, x, height, z } a point)
                    for _, w in ipairs(o.path or {}) do if w[1] ~= -1 then w[3] = w[3] + dz / 0.75 end end
                    if o.sm64 then o.sm64[2] = o.sm64[2] + dz / 0.75 end
                    ns = ns + 1
                end
            end
        end
        if sc then
            log("scene %s: %s %.2f times as big (%d drawn triangles, %d solid, %d slide floors, %d stars, %d warps and spots)", name, mv.what, sc[4], nd, nc, nsl, ns, nw)
        else
            log("scene %s: %s moved %.0f cm (%d drawn %s, %d solid, %d stars and objects)", name, mv.what, mv.squash and (mv.squash.to - mv.squash.from) or dz, nd,
                mv.stretch and "corners" or "triangles", nc, ns)
        end
        ::next_piece::
    end
end

-- A back for flat drawn faces seen from above only: each triangle of the sections drawn in `textures` whose corners are
-- all inside `box` (Mario 64 units, as G.MOVE_PIECES's) and level, copied facing down - the same corners, picture and
-- shade, turned the other way round. The number of faces made.
function G.add_underside(data, mv)
    local tex = {}
    for _, t in ipairs(mv.textures or {}) do tex[t] = true end
    local bx = mv.box
    local function inside(P, i)
        local x, y, z = P[i * 3 + 2] / 0.75, P[i * 3 + 3] / 0.75, -P[i * 3 + 1] / 0.75
        return x > bx[1] and x < bx[2] and y > bx[3] and y < bx[4] and z > bx[5] and z < bx[6]
    end
    local made = 0
    for _, m in ipairs(data.sections or {}) do
        local P = m.pos
        if tex[m.texture] and P and m.idx then
            local n = #P // 3
            local add = {}
            for t = 0, #m.idx // 3 - 1 do
                local a, b, c = m.idx[t * 3 + 1], m.idx[t * 3 + 2], m.idx[t * 3 + 3]
                if inside(P, a) and inside(P, b) and inside(P, c)
                    and abs(P[a * 3 + 3] - P[b * 3 + 3]) < 1.0 and abs(P[a * 3 + 3] - P[c * 3 + 3]) < 1.0 then
                    add[#add + 1] = { a, c, b }
                end
            end
            for _, tri in ipairs(add) do
                for _, i in ipairs(tri) do
                    P[#P + 1], P[#P + 2], P[#P + 3] = P[i * 3 + 1], P[i * 3 + 2], P[i * 3 + 3]
                    for f, w in pairs({ uv = 2, col = 4, nrm = 3 }) do
                        local arr = m[f]
                        if arr then for q = 1, w do arr[#arr + 1] = arr[i * w + q] end end
                    end
                    if m.nrm then local N = m.nrm; N[#N - 2], N[#N - 1], N[#N] = -N[#N - 2], -N[#N - 1], -N[#N] end
                    m.idx[#m.idx + 1] = n
                    n = n + 1
                end
                made = made + 1
            end
            if #add > 0 then
                if m.nverts then m.nverts = n end
                m.ntris = #m.idx // 3
            end
        end
    end
    return made
end

-- New pieces for a level, made before G.move_pieces moves its piece, so they move with it: upright prisms over a
-- footprint (scene cm, its corners anticlockwise seen from above), a side on each edge asked for (`sides`), and a top -
-- drawn in the `side` and `top` pictures, laid on as `side_uv` and `top_uv` say (matched to what they continue), and
-- solid (`solid`: in the scene's first collision mesh). Shaded as Mario 64 lit the faces beside them: facing -x or +y
-- full, +x or -y half. Wound as the export winds its faces: (b - a) x (c - a) pointing in. The number of faces made.
function G.add_prisms(data, add)
    local function section(tex)
        for _, s in ipairs(data.sections or {}) do if s.texture == tex then return s end end
        -- (`new_section`: a picture the level has nothing in - a section of its own made for it, drawn as the rest:
        -- DDD's raft in JRB's ship wood)
        if add.new_section and tex and data.sections then
            local s = { id = 900 + #data.sections, layer = "opaque", texture = tex, nverts = 0, ntris = 0,
                        pos = {}, uv = {}, col = {}, nrm = {}, idx = {} }
            data.sections[#data.sections + 1] = s
            return s
        end
    end
    local side_sec, top_sec = section(add.side), add.top and section(add.top)
    local coll = add.solid and data.collision and data.collision[1]
    if not side_sec then return 0 end
    local nf = 0
    local function face(sec, quad, nx, ny, nz, shade, uvf)
        for _, tr in ipairs({ { 1, 2, 3 }, { 1, 3, 4 } }) do
            local a, b, c = quad[tr[1]], quad[tr[2]], quad[tr[3]]
            local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
            local wx, wy, wz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
            if (uy * wz - uz * wy) * nx + (uz * wx - ux * wz) * ny + (ux * wy - uy * wx) * nz > 0.0 then b, c = c, b end
            if sec then
                local base = #sec.pos // 3
                for _, v in ipairs({ a, b, c }) do
                    local P, U, C, N = sec.pos, sec.uv, sec.col, sec.nrm
                    P[#P + 1], P[#P + 2], P[#P + 3] = v[1], v[2], v[3]
                    local u, w = uvf(v)
                    U[#U + 1], U[#U + 2] = u, w
                    local sh = shade * (add.tint or 1.0)        -- (`tint`: all of it darker, to match what it joins)
                    C[#C + 1], C[#C + 2], C[#C + 3], C[#C + 4] = sh, sh, sh, 1.0
                    N[#N + 1], N[#N + 2], N[#N + 3] = nx, ny, nz
                end
                local X = sec.idx
                X[#X + 1], X[#X + 2], X[#X + 3] = base, base + 1, base + 2
                sec.nverts, sec.ntris = #sec.pos // 3, #sec.idx // 3
            end
            if coll then
                local base = #coll.pos // 3
                for _, v in ipairs({ a, b, c }) do
                    local P = coll.pos
                    P[#P + 1], P[#P + 2], P[#P + 3] = v[1], v[2], v[3]
                end
                local X = coll.idx
                X[#X + 1], X[#X + 2], X[#X + 3] = base, base + 1, base + 2
                coll.ntris = #coll.idx // 3
            end
        end
        nf = nf + 1
    end
    local su, tu = add.side_uv, add.top_uv
    for _, pr in ipairs(add.prisms or {}) do
        local cs, z0, z1 = pr.corners, pr.z0, pr.z1
        for i = 1, #cs do
            if pr.sides[i] then
                local p, q = cs[i], cs[i % #cs + 1]
                local dx, dy = q[1] - p[1], q[2] - p[2]
                local l = math.sqrt(dx * dx + dy * dy)
                local nx, ny = dy / l, -dx / l
                local along_y = math.abs(nx) >= math.abs(ny)
                local shade = (along_y and nx < 0.0 or (not along_y and ny > 0.0)) and 1.0 or 0.5
                face(side_sec, { { p[1], p[2], z0 }, { q[1], q[2], z0 }, { q[1], q[2], z1 }, { p[1], p[2], z1 } }, nx, ny, 0.0, shade,
                    function(v)
                        -- (`affine`: u and v straight from x, y, z - a picture laid at a slant, as RR's stone is)
                        local K = su.affine
                        if K then return K[1] * v[1] + K[2] * v[2] + K[3] * v[3] + K[4], K[5] * v[1] + K[6] * v[2] + K[7] * v[3] + K[8] end
                        local u = along_y and (su.y0 - v[2]) * su.uy or (su.x0 - v[1]) * su.ux
                        return u, su.v0 + (su.z0 - v[3]) * su.vz
                    end)
            end
        end
        if pr.top ~= false then
            local quad = {}
            for i = 1, #cs do quad[i] = { cs[i][1], cs[i][2], z1 } end
            face(top_sec, quad, 0.0, 0.0, 1.0, 1.0,
                function(v)
                    local K = tu.affine
                    if K then return K[1] * v[1] + K[2] * v[2] + K[3], K[4] * v[1] + K[5] * v[2] + K[6] end
                    return (tu.y0 - v[2]) * tu.uy, tu.v0 + (v[1] - tu.x0) * tu.vx
                end)
        end
    end
    return nf
end

-- A see-through piece's triangles in the order they are drawn: the engine blends a mesh's see-through faces as listed,
-- a nearer one over a farther only if listed after it. Its inside first, the deepest first, and its outer faces last, so
-- seen from outside its outer faces lie over what is in it - SL's ice block: its maze's ceilings stood as dark slabs over
-- its front face, "the seethrough is a mess", 2026-10-26. Outer: on a side or the top of the piece's bounds, facing out
-- of it. (The export winds its faces inward - its x = -z - so a face's normal is (c - a) x (b - a). No bottom: Mario 64
-- draws none under the ice.) `list`: corner indices into P, three a triangle, put in that order in place.
function G.outer_last(P, list)
    local x0, x1, y0, y1, z1 = math.huge, -math.huge, math.huge, -math.huge, -math.huge
    for _, i in ipairs(list) do
        local x, y, z = P[i * 3 + 1], P[i * 3 + 2], P[i * 3 + 3]
        x0, x1, y0, y1, z1 = math.min(x0, x), math.max(x1, x), math.min(y0, y), math.max(y1, y), math.max(z1, z)
    end
    local tris = {}
    for t = 0, #list // 3 - 1 do
        local a, b, c = list[t * 3 + 1], list[t * 3 + 2], list[t * 3 + 3]
        local ax, ay, az = P[a * 3 + 1], P[a * 3 + 2], P[a * 3 + 3]
        local ux, uy, uz = P[c * 3 + 1] - ax, P[c * 3 + 2] - ay, P[c * 3 + 3] - az
        local wx, wy, wz = P[b * 3 + 1] - ax, P[b * 3 + 2] - ay, P[b * 3 + 3] - az
        local nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
        local l = math.sqrt(nx * nx + ny * ny + nz * nz)
        if l > 1e-9 then nx, ny, nz = nx / l, ny / l, nz / l end
        local cx = (ax + P[b * 3 + 1] + P[c * 3 + 1]) / 3.0
        local cy = (ay + P[b * 3 + 2] + P[c * 3 + 2]) / 3.0
        local cz = (az + P[b * 3 + 3] + P[c * 3 + 3]) / 3.0
        local dx0, dx1, dy0, dy1, dz1 = cx - x0, x1 - cx, cy - y0, y1 - cy, z1 - cz
        local outer = (dx0 < 2.0 and nx < -0.7) or (dx1 < 2.0 and nx > 0.7) or (dy0 < 2.0 and ny < -0.7)
            or (dy1 < 2.0 and ny > 0.7) or (dz1 < 2.0 and nz > 0.7)
        tris[#tris + 1] = { a, b, c, outer and -1.0 or math.min(dx0, dx1, dy0, dy1, dz1), t }
    end
    table.sort(tris, function(p, q) if p[4] ~= q[4] then return p[4] > q[4] end return p[5] < q[5] end)
    for t, e in ipairs(tris) do list[t * 3 - 2], list[t * 3 - 1], list[t * 3] = e[1], e[2], e[3] end
end

-- What his footsteps sound of in each scene: Mario 64's terrain of the area (TERRAIN_TYPE in levels/*/script.c) as
-- STORROR's surface types (its footsteps' MetaSound by the floor's SurfaceType; told apart by recording them,
-- 2026-10-18: 1 short and sharp - concrete, 2 a soft crunch - dirt, 3 a thump and a rustle - grass, 4 a high crunch -
-- gravel, 5 and 6 ringing - metal and wood; 7 and 8 make no sound at all). Grass for the grass courses, stone and the
-- slides concrete, snow the crunch, sand dirt, Big Boo's Haunt wood; anything else concrete.
G.SURFACE_OF = { bob = 3, thi = 3, thi_2 = 3, thi_3 = 3, grounds = 3,
                 ccm = 4, sl = 4, sl_2 = 4, ssl = 2, bbh = 6 }      -- (Wing Mario's snow is nearly all hard: concrete)

-- The scene's creatures and platforms put back as the scene first had them - each one gone and made again from the
-- scene's own list, where it was and as it was (the cannons open again if the file has them so) - and chance started
-- again from one seed: the race's world the same at every start, with the ghost's run in step with it ("can you sync
-- the movement of all platforms to the start of the race?", "as well as the enemies?", 2026-10-27; race.lua calls it
-- behind its black). The level itself, its coins and its stars are left as they are. How many were made again.
function G.reset_objects(seed)
    local world, data, name = lib.world(), G.data, G.name
    if not (world and data and name) then return nil end
    for _, m in ipairs(CREATURES) do if m.clear then pcall(m.clear) end end
    PLAT.clear()
    for _, g in ipairs(G.goombas or {}) do pcall(lib.destroy, g.inst and g.inst.actor) end
    G.goombas = {}
    if seed then math.randomseed(seed) end
    local n = 0
    for _, o in ipairs(data.objects or {}) do
        local ok, err = pcall(function()
            if o.acts and G.act and ((o.acts >> (G.act - 1)) & 1) == 0 then return end      -- (not in this act)
            if o.kind == "goomba" then add_goomba(world, o); n = n + 1
            elseif o.kind == "platform" then PLAT.add(world, o, data.templates); n = n + 1
            else
                for _, m in ipairs(CREATURES) do
                    if m.kinds and m.kinds[o.kind] then m.add(world, o, data.templates); n = n + 1 end
                end
            end
        end)
        if not ok then log("reset: object %s failed: %s", tostring(o.kind), tostring(err)) end
    end
    local MN = _G.MENU
    if MN and MN.has_flag and MN.has_flag("cannon_" .. G.level_of(name)) and PLAT.open_cannons then
        pcall(PLAT.open_cannons, true)
    end
    log("scene %s: its creatures and platforms put back as it first had them (%d)%s", name, n,
        seed and (", chance from " .. tostring(seed)) or "")
    return n
end

-- Baked sun shadows (tools/shadowbake.py - "next I want to work on shadows, I want them baked into the game", 2026-10-30:
-- the level and what never moves baked, moving things in real time): a scene's sections with the sun's shadows in their
-- colours, split finer where a shadow's edge crosses them, in data/shadow_<scene>.lua - swapped in for its own as it
-- loads, before anything else changes them. A scene with none is as it was.
-- (off since the levels are lit and the engine casts every shadow on them itself - G.LIT_LEVELS: baked in as well, the
-- shade fell twice. tools/shadowbake.py and data/shadow_*.lua kept.)
G.SHADOWS_BAKED = false

-- Lit levels: the level's own solid pictures drawn with the glTF lit material (M_Default) in place of the unlit one, so
-- the engine's shadows fall on them - his real shadow, the creatures', the platforms', the level's own, all cast by the
-- sun (menu.lua M.SUN) in real time: "it should show a real shadow of the player not circles", 2026-10-30. Before, an
-- unlit level took no shadow at all, and his was faked from soft shapes. Cut-out and see-through pieces stay unlit.
G.LIT_LEVELS = true
G.LIT_PARENT = "/InterchangeAssets/gltf/M_Default.M_Default"
G.lit_mids = {}
function G.light_level(world, sections, pmc)
    -- (the level's solid pictures are drawn lit by lib.add_sections itself - lib.lit_on - and swapped when the setting is
    -- turned, lib.relight: here only counted, for the log)
    if not (G.LIT_LEVELS and sections) then return 0 end
    local n = 0
    for _, sec in ipairs(sections) do if sec.layer == "opaque" and sec.texture then n = n + 1 end end
    return n
end

-- Far things updated less often (goombas, a level's coins; enemies.lua M.LOD_* for the creatures): beyond this (cm) from
-- him, every this many frames
G.LOD_NEAR, G.LOD_EVERY = 2000.0, 3
-- (a coin's picture put in place again only once it has turned this many degrees to the camera, or moved: each one in
-- sight was put in place every frame, two pictures each, still or not - 0.44 ms of every frame in Whomp's Fortress's 73,
-- "when I entered the level it was 120 fps now its 80", 2026-11-05)
G.COIN_TURN = 1.5
-- (and RENDER 96's coins, spinning - turned every frame, so put in place every frame, each in sight: further than `near`
-- cm from him, their spin put at most `near_hz` times a second; further than `far`, `far_hz`. The near ones every frame.)
G.COIN3D_STEPS = { near = 900.0, near_hz = 30.0, far = 2000.0, far_hz = 15.0 }

-- RENDER 96 turned (lib.set_r96): the creatures, stars and trees Render96 has models of are other models now - those loaded
-- forgotten (G.actors), and the scene built again round him where he stands (an instant warp's way: opt.move)
lib.on_r96 = function(on)
    G.actors = {}
    -- (and the HUD's pictures - its numbers, letters, power meter, icons - made again from the switch as it now stands)
    local HL = package.loaded["health"]
    if HL and HL.refresh_hud then pcall(HL.refresh_hud) end
    if G.name and not (G.dying or G.warping or G.pending) then G.goto_scene(G.name, nil, { move = { 0.0, 0.0, 0.0 } }) end
end

-- Settings > Graphics, REAL TIME SHADOWS (msettings.lua; kept with the save files, menu.lua): on, the levels and everything
-- in them drawn lit and the sun casting every shadow; off, Mario 64's own look - unlit, its round shadows under him and
-- the creatures (shadows.lua) and the shadows painted on its levels. Turned live, while a level is up ("it should be
-- mario shadows off. it should be real time shadows on", 2026-10-30).
function G.set_realtime_shadows(on)
    on = on and true or false
    local was = G.LIT_LEVELS
    G.LIT_LEVELS = on
    local MN = _G.MENU
    local env = MN and MN.env
    local here = nil
    pcall(function() here = lib.world():GetAddress() end)
    if env and env.world == here then
        local sun = env.lights and env.lights[1]
        if sun and sun:IsValid() then pcall(function() sun.LightComponent:SetCastShadows(on) end) end
    end
    local SKY = package.loaded["sky"]
    if SKY and SKY.relight then pcall(SKY.relight) end
    if was ~= on then
        local n = 0
        local world = lib.world()
        if world then
            local okr, r = pcall(lib.relight, world, on)
            if okr then n = r else log("shadows: relight: %s", tostring(r)) end
        end
        pcall(G.painted_shadows)
        log("shadows: %s (%d pictures swapped)", on and "real time" or "Mario 64's", n)
    end
end

-- The shadows Mario 64 paints on its levels, under their trees (a soft dark circle or star, see-through, on the ground):
-- hidden with real-time shadows, which cast the trees' own - both, the tree had two ("also double shadows", 2026-10-30)
G.PAINTED_SHADOWS = {
    ["textures__outside__castle_grounds_textures.0BC00.ia16"] = true,   -- the castle grounds and courtyard
    ["textures__generic__bob_textures.0B000.ia16"] = true,              -- Bob-omb Battlefield
    ["textures__grass__wf_textures.0B000.ia16"] = true,                 -- Whomp's Fortress, Tiny-Huge Island
    ["textures__snow__ccm_textures.09800.ia16"] = true,                 -- Cool, Cool Mountain, the slide
    ["levels__ssl__1.ia16"] = true,                                     -- Shifting Sand Land's palms
}
function G.painted_shadows(pmc, sections)
    pmc = pmc or G.pmc
    sections = sections or (G.data and G.data.sections)
    if not (pmc and sections and pmc:IsValid()) then return 0 end
    local n = 0
    for _, sec in ipairs(sections) do
        if sec.id and sec.texture and G.PAINTED_SHADOWS[sec.texture] then
            pcall(function() pmc:SetMeshSectionVisible(sec.id, not G.LIT_LEVELS) end)
            n = n + 1
        end
    end
    return n
end

-- Lit, the levels showed each of Mario 64's tiles as a square of its own: its corners are its own, not shared with the
-- tiles beside it, each turned its own way to the sun - a slope of snow a chequerboard of light and less light ("you can
-- see squares in the floor and wall", "for every level", 2026-10-30). Where tiles meet, each corner is turned the way
-- of them all together - the tiles there turned within G.SMOOTH_ANGLE of it: a slope's or a curve's - so the light runs
-- smooth across them; a floor's edge against a wall stays sharp. Once a level's data is loaded (kept: once only).
G.SMOOTH_ANGLE = 35.0
function G.smooth_normals(data)
    if not data or data.normals_smoothed then return 0 end
    data.normals_smoothed = true
    local cosmax = math.cos(math.rad(G.SMOOTH_ANGLE))
    local fl = math.floor
    local buckets = {}
    for _, sec in ipairs(data.sections or {}) do
        if sec.layer == "opaque" and sec.nrm and sec.pos and sec.nverts then
            local pos, nrm = sec.pos, sec.nrm
            for i = 0, sec.nverts - 1 do
                local b = i * 3
                local key = fl(pos[b + 1] * 2 + 0.5) .. "," .. fl(pos[b + 2] * 2 + 0.5) .. "," .. fl(pos[b + 3] * 2 + 0.5)
                local list = buckets[key]
                if not list then list = {}; buckets[key] = list end
                list[#list + 1] = { nrm, b, nrm[b + 1] or 0.0, nrm[b + 2] or 0.0, nrm[b + 3] or 1.0 }
            end
        end
    end
    local n = 0
    for _, list in pairs(buckets) do
        if #list > 1 then
            for _, v in ipairs(list) do
                local sx, sy, sz = 0.0, 0.0, 0.0
                for _, w in ipairs(list) do
                    if v[3] * w[3] + v[4] * w[4] + v[5] * w[5] >= cosmax then sx, sy, sz = sx + w[3], sy + w[4], sz + w[5] end
                end
                local l = math.sqrt(sx * sx + sy * sy + sz * sz)
                if l > 1e-6 then
                    local t, b = v[1], v[2]
                    t[b + 1], t[b + 2], t[b + 3] = sx / l, sy / l, sz / l
                    n = n + 1
                end
            end
        end
    end
    return n
end

-- Where the sun is, level by level (menu.lua M.SUN: degrees up, and round from the scene's +X toward +Y): most under the
-- one sun; the castle grounds' in front of the castle, behind him as he comes up to it - from behind, its whole front
-- was in shade ("whole front part of the castle is black", 2026-10-30).
G.SUN_AT = { grounds = { 60.0, 200.0 } }
function G.aim_sun(name)
    local MN = _G.MENU
    if not (MN and MN.aim_sun) then return end
    MN.aim_sun(G.SUN_AT[name] or MN.SUN_DEFAULT)
end
function G.bake_shadows(name, data)
    if not G.SHADOWS_BAKED or not data or not data.sections then return 0 end
    -- (its compiled form, quick: lib.load_chunk)
    local f = lib.load_chunk("data.shadow_" .. name)
    if not f then return 0 end
    local sh = f()
    if not (sh and sh.sections) then return 0 end
    local n = 0
    for _, sec in ipairs(data.sections) do
        local b = sec.id and sh.sections[sec.id]
        if b then
            sec.pos, sec.nrm, sec.uv, sec.col, sec.idx = b.pos, b.nrm, b.uv, b.col, b.idx
            sec.nverts, sec.ntris = b.nverts, b.ntris
            n = n + 1
        end
    end
    log("scene %s: sun shadows baked in (%d sections)", name, n)
    return n
end

-- The caves and other places shut in under rock or roof: the one sun shone in through the rock, low, his shadow thrown
-- far across the lake - "shadows completely cooked in hazy maze cave", 2026-10-31. Real-time shadows off in them
-- (Mario 64's own look) read as the setting turning itself off - "for some reason shadows is turning off on its own?".
-- So they stay on: in a cave the light comes straight down (G.SUN_AT) and the rock itself casts none (its PMC's shadow
-- off, G.load_scene) - everything in it lit from above, his and the creatures' shadows right under them, as Mario 64's
-- round ones fall.
G.CAVES = { hmc = true, cotmc = true, vcutm = true, pss = true, sa = true, ttc = true, ssl_2 = true, ssl_3 = true,
            lll_2 = true, ccm_2 = true, sl_2 = true, ttm_2 = true, ttm_3 = true, ttm_4 = true, thi_3 = true, jrb_2 = true,
            ddd_2 = true }
for cave in pairs(G.CAVES) do G.SUN_AT[cave] = G.SUN_AT[cave] or { 89.0, 0.0 } end
function G.cave_light(name)
    -- (from the first way of it: shadows turned off for a cave, put back as the setting has them)
    if G.cave_unlit then
        G.cave_unlit = nil
        local MN = _G.MENU
        local want = not (MN and MN.realtime_shadows and MN.realtime_shadows() < 0.5)
        if want and not G.LIT_LEVELS then G.set_realtime_shadows(true) end
    end
    if G.CAVES[name] then log("scene %s: a cave - the light straight down, the rock casting no shadow", name) end
end

-- Stairs made smooth: in the castle (G.SMOOTH_STAIRS) each flight of steps found in the level's collision - risers 12 to
-- 40 cm tall, each the next one's foot, 12 to 90 cm on up the way it faces, straight or turning - gets a ramp over it,
-- solid only: from one step's depth out in front of its first riser, on the floor, up through the nose of every step to
-- the top one's, flush with the floor up there. He walks up and down it as up a slope, not bumped step by step: "can
-- you make all the stairs in the castle smooth", 2026-11-07. The steps stay as drawn, and are what his feet stand on -
-- the ramps are a collision of their own (`no_floor`), left out of the floors the mod reads (G.floor: footik.lua's feet,
-- the fall heights).
G.SMOOTH_STAIRS = { castle = true, castle2 = true, castle3 = true }
G.STAIR_RAMP = { rise_min = 12.0, rise_max = 40.0, run_min = 12.0, run_max = 90.0, lift = 2.0, turn = 0.8, strip = 60.0 }
function G.stair_ramps(name, data)
    if not (G.SMOOTH_STAIRS and G.SMOOTH_STAIRS[name]) then return 0 end
    local coll = data.collision and data.collision[1]
    if not coll or data.stair_ramps_made then return 0 end
    data.stair_ramps_made = true
    local S = G.STAIR_RAMP
    local P, X = coll.pos, coll.idx
    local sqrt, abs, min, max, floor = math.sqrt, math.abs, math.min, math.max, math.floor
    -- (the risers: upright faces that tall, by their plane and heights, each a stretch along it)
    local groups, order = {}, {}
    for t = 0, coll.ntris - 1 do
        local i1, i2, i3 = X[t * 3 + 1] * 3, X[t * 3 + 2] * 3, X[t * 3 + 3] * 3
        local ax, ay, az = P[i1 + 1], P[i1 + 2], P[i1 + 3]
        local bx, by, bz = P[i2 + 1], P[i2 + 2], P[i2 + 3]
        local cx, cy, cz = P[i3 + 1], P[i3 + 2], P[i3 + 3]
        local ux, uy, uz = bx - ax, by - ay, bz - az
        local vx, vy, vz = cx - ax, cy - ay, cz - az
        local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        local l = sqrt(nx * nx + ny * ny + nz * nz)
        if l > 1e-6 and abs(nz) / l < 0.05 then
            local zb, zt = min(az, bz, cz), max(az, bz, cz)
            if zt - zb >= S.rise_min and zt - zb <= S.rise_max then
                local hl = sqrt(nx * nx + ny * ny)
                nx, ny = nx / hl, ny / hl
                local d = nx * ax + ny * ay
                local key = floor(nx * 100.0 + 0.5) .. "|" .. floor(ny * 100.0 + 0.5) .. "|" .. floor(zb + 0.5) .. "|" ..
                            floor(zt + 0.5) .. "|" .. floor(d + 0.5)
                local g = groups[key]
                if not g then g = { nx = nx, ny = ny, zb = zb, zt = zt, d = d, iv = {} }; groups[key] = g; order[#order + 1] = g end
                local tx, ty = -ny, nx
                local t1, t2, t3 = tx * ax + ty * ay, tx * bx + ty * by, tx * cx + ty * cy
                g.iv[#g.iv + 1] = { min(t1, t2, t3), max(t1, t2, t3) }
            end
        end
    end
    -- (each plane's stretches joined where they touch: a gap between two is two risers)
    local R = {}
    for _, g in ipairs(order) do
        table.sort(g.iv, function(p, q) return p[1] < q[1] end)
        local runs = {}
        for _, iv in ipairs(g.iv) do
            local last = runs[#runs]
            if last and iv[1] <= last[2] + 1.0 then last[2] = max(last[2], iv[2]) else runs[#runs + 1] = { iv[1], iv[2] } end
        end
        local tx, ty = -g.ny, g.nx
        for _, rn in ipairs(runs) do
            local p0x, p0y = g.nx * g.d + tx * rn[1], g.ny * g.d + ty * rn[1]
            local p1x, p1y = g.nx * g.d + tx * rn[2], g.ny * g.d + ty * rn[2]
            R[#R + 1] = { nx = g.nx, ny = g.ny, zb = g.zb, zt = g.zt, p0 = { p0x, p0y }, p1 = { p1x, p1y },
                          mx = (p0x + p1x) / 2.0, my = (p0y + p1y) / 2.0, w = rn[2] - rn[1] }
        end
    end
    -- (the riser above each: its foot at this one's top, on up the way this one faces - the level's collision has them
    -- facing up the stairs - near, turned little, as wide)
    local function cost(a, b)
        if abs(b.zb - a.zt) > 1.5 then return nil end
        if a.nx * b.nx + a.ny * b.ny < S.turn then return nil end
        if min(a.w, b.w) < 0.7 * max(a.w, b.w) then return nil end
        local dx, dy = b.mx - a.mx, b.my - a.my
        local run = dx * a.nx + dy * a.ny
        local side = abs(-dx * a.ny + dy * a.nx)
        if run < S.run_min or run > S.run_max or side > 0.5 * max(a.w, b.w) then return nil end
        return run + side
    end
    local up, upc = {}, {}
    for i, a in ipairs(R) do
        for j, b in ipairs(R) do
            if i ~= j then
                local c = cost(a, b)
                if c and (not upc[i] or c < upc[i]) then up[i], upc[i] = j, c end
            end
        end
    end
    -- (one below each at most: the nearest)
    local down = {}
    for i, j in pairs(up) do
        if not down[j] or upc[i] < upc[down[j]] then down[j] = i end
    end
    for i, j in pairs(up) do if down[j] ~= i then up[i] = nil end end
    local ramps = { source = "stair ramps", pos = {}, idx = {}, ntris = 0, no_floor = true }
    local RP, RI = ramps.pos, ramps.idx
    local function tri(a, b, c)
        -- (facing up, as the level's floors are wound: the cross of its edges pointing down. None upright - nothing
        -- under it to stand on: a spiral's steps all meet at its column)
        local ux, uy = b[1] - a[1], b[2] - a[2]
        local vx, vy = c[1] - a[1], c[2] - a[2]
        local cr = ux * vy - uy * vx
        if abs(cr) < 2.0 then return end
        if cr > 0.0 then b, c = c, b end
        local base = #RP // 3
        for _, v in ipairs({ a, b, c }) do RP[#RP + 1], RP[#RP + 2], RP[#RP + 3] = v[1], v[2], v[3] end
        RI[#RI + 1], RI[#RI + 2], RI[#RI + 3] = base, base + 1, base + 2
    end
    local function quad(a, b, c, d) tri(a, b, c); tri(a, c, d) end
    -- (from one riser's top to the next one's, in strips across them `strip` cm wide - a spiral's wedge of a step is
    -- laid by many, as a screw's thread, where one quad across it dipped under the next step)
    local function band(p, pz, q, qz)
        local n = math.max(1, math.ceil(math.max(p.w, q.w) / S.strip))
        for k = 0, n - 1 do
            local u0, u1 = k / n, (k + 1) / n
            local function at(s, u, z) return { s.p0[1] + (s.p1[1] - s.p0[1]) * u, s.p0[2] + (s.p1[2] - s.p0[2]) * u, z } end
            quad(at(p, u0, pz), at(p, u1, pz), at(q, u1, qz), at(q, u0, qz))
        end
    end
    local flights, steps = 0, 0
    for i = 1, #R do
        if up[i] and not down[i] then
            local ch = { R[i] }
            local k = i
            while up[k] and #ch < 200 do k = up[k]; ch[#ch + 1] = R[k] end
            if #ch >= 3 then
                flights, steps = flights + 1, steps + #ch
                local lift = S.lift
                local a, b = ch[1], ch[2]
                local run = (b.mx - a.mx) * a.nx + (b.my - a.my) * a.ny
                local foot = { p0 = { a.p0[1] - a.nx * run, a.p0[2] - a.ny * run }, p1 = { a.p1[1] - a.nx * run, a.p1[2] - a.ny * run }, w = a.w }
                band(foot, a.zb + lift, a, a.zt + lift)
                for s = 1, #ch - 1 do band(ch[s], ch[s].zt + lift, ch[s + 1], ch[s + 1].zt + lift) end
            end
        end
    end
    ramps.ntris = #RI // 3
    if ramps.ntris > 0 then data.collision[#data.collision + 1] = ramps end
    return flights, steps, ramps.ntris
end

function G.load_scene(name, keep_player)
    local world = lib.world()
    if not world then log("no world yet"); return false end
    local t0 = os.clock()
    local data = lib.load_data("data.scene_" .. name)
    if not data then return false end           -- nothing is torn down for a scene that cannot be built
    -- (the Bowser run over whatever way he left it - a game over goes to the title and on to the grounds without a
    -- warp: left set, it sent the next castle door out in front of the run's painting)
    if G.gauntlet and G.GAUNTLET and not G.GAUNTLET.scenes[name] then
        G.gauntlet, G.run_lava_kept, G.lava_resume = nil, nil, nil
        log("bowser run: over (%s)", name)
    end
    -- (the final fight's three floors - G.pancakes)
    do
        local okp, errp = pcall(G.pancakes, name, data)
        if not okp then log("final fight floors: %s", tostring(errp)) end
    end
    -- (the Bowser run: the next course put on after this one - G.join_scenes)
    do
        local okj, errj = pcall(G.join_scenes, name, data)
        if not okj then log("bowser run join: %s", tostring(errj)) end
    end
    pcall(G.bake_shadows, name, data)
    pcall(G.aim_sun, name)
    do
        local okc, errc = pcall(G.cave_light, name)
        if not okc then log("cave light: %s", tostring(errc)) end
    end
    do
        local oks, ns = pcall(G.smooth_normals, data)
        if oks and ns > 0 then log("scene %s: %d tile corners shaded smooth", name, ns) elseif not oks then log("smooth normals: %s", tostring(ns)) end
    end
    pcall(G.drop_camera_walls, data)
    pcall(G.add_extra_statics, name, data)
    -- (the mod's own hallways: G.EXTRA_HALLS - before the paintings' hollows, which take its painting too)
    do
        local okh, errh = pcall(G.add_halls, name, data)
        if not okh then log("halls failed: %s", tostring(errh)) end
    end
    -- (the castle's stairs made smooth: a ramp over each flight, solid only - G.stair_ramps)
    do
        local oks, nf, ns = pcall(G.stair_ramps, name, data)
        if not oks then log("stair ramps: %s", tostring(nf))
        elseif nf and nf > 0 then log("scene %s: %d flights of stairs made smooth (%d steps)", name, nf, ns or 0) end
    end
    -- (the ragdoll test area no longer added: "get rid of the test", 2026-10-29 - G.add_test_area and tools/test_area.py
    -- kept, unused)
    do
        local okr, errr = pcall(G.recess_paintings, name, data)
        if not okr then log("painting recesses failed: %s", tostring(errr)) end
        local okf, errf = pcall(G.fix_sections, name, data)
        if not okf then log("section fixes failed: %s", tostring(errf)) end
    end
    lib.SURFACE = G.SURFACE_OF[name] or 1       -- (the floors made from here on: lib.add_collision)
    -- (no arrival of the last scene carried into this one: a death's landing left pending took a life on the next
    -- scene's ground, 2026-10-18)
    G.entry = nil
    pcall(deepen, name, data)
    do
        local okf, errf = pcall(G.face_fixes, name, data)
        if not okf then log("face fixes: %s", tostring(errf)) end
    end
    do
        local oks, errs = pcall(G.solid_as_drawn, name, data)
        if not oks then log("pillars as drawn failed: %s", tostring(errs)) end
        local okr, errr = pcall(G.raise_parts, name, data)
        if not okr then log("raised parts failed: %s", tostring(errr)) end
        local okm, errm = pcall(G.move_pieces, name, data)
        if not okm then log("moved pieces failed: %s", tostring(errm)) end
    end
    do
        local okp, errp = pcall(deepen_pipes, name, data)
        if not okp then log("deep pipe failed: %s", tostring(errp)) end
    end
    G.destroy_scene()
    if G.set_down_for_good then pcall(G.set_down_for_good, false) end
    -- (object_list_processor.c: a course's second area entered sets gCCMEnteredSlide; a new course clears it)
    do
        local lvl = G.level_of(name)
        if G.slid and G.slid ~= lvl then G.slid = nil end
        if name == lvl .. "_2" then G.slid = lvl end
    end
    if CAPS and CAPS.on() and CAPS.level ~= G.level_of(name) then pcall(CAPS.stop, true) end    -- (out of its course: gone)
    G.pss = nil                                     -- (the slide's clock: a fresh one each visit)
    if _G.HEALTH then _G.HEALTH.clock = nil end
    G.name, G.data = name, data
    -- (a new file's first walk into the castle: Bowser's welcome, DIALOG_021, before the castle's tune - Mario 64's
    -- gNeverEnteredCastle, act_warp_door_spawn and sound_init.c)
    if name == "castle" and G.never_entered then
        G.never_entered, G.welcome_at, G.music_held = false, os.clock() + 1.0, true
    end
    -- (the coins are the course's, not the area's: from one of its areas to another - Cool, Cool Mountain to its slide
    -- and back - the count goes on, as Mario 64's numCoins does; a new course, or the castle, starts it again. "when
    -- going to the slide it resets the coin counter in the level is that how its supposed to be?", 2026-10-18)
    local course = G.level_of(name)
    if G.coin_course ~= course then G.coin_count, G.coin_course = 0, course end
    G.red_count = 0
    G.warp, G.pwarp, G.node, G.instant = {}, {}, {}, {}
    for _, w in ipairs(data.warps or {}) do G.warp[w.id] = w end
    for _, w in ipairs(data.pwarps or {}) do G.pwarp[w.id] = w end
    for _, n in ipairs(data.nodes or {}) do if not G.node[n.id] then G.node[n.id] = n end end
    for _, w in ipairs(data.instant or {}) do G.instant[w.index] = w end

    local actor = lib.spawn_actor(world, OFFSET, 0.0)
    if not actor then log("scene actor spawn failed"); return false end
    G.scene_actor = actor
    local pmc = lib.add_pmc(actor)
    if not pmc then log("scene PMC failed"); return false end
    G.pmc = pmc
    -- (a cave's rock casts no shadow: the light from above would leave it all in the dark - G.cave_light)
    if G.CAVES[name] then pcall(function() pmc:SetCastShadow(false) end) end
    local sections, bb = data.sections, BILLBOARD_PROPS[name]
    if bb then
        sections = {}
        for _, sec in ipairs(data.sections) do if sec.texture ~= bb.texture then sections[#sections + 1] = sec end end
    end
    local made = lib.add_sections(world, pmc, sections)
    -- (and their undersides - G.add_undersides)
    do
        local oku, nu = pcall(G.add_undersides, world, actor, sections)
        if oku and nu and nu > 0 then log("scene %s: %d undersides", name, nu) elseif not oku then log("undersides: %s", tostring(nu)) end
    end
    do
        local okl, nl = pcall(G.light_level, world, sections, pmc)
        if okl and nl > 0 then log("scene %s: lit (%d sections take shadows)", name, nl) elseif not okl then log("lit levels: %s", tostring(nl)) end
        pcall(G.painted_shadows, pmc, sections)
    end
    G.sprites = {}
    if bb then
        for _, p in ipairs(bb.at) do
            -- (Mario 64's x, z -> the scene's: x = -z, y = x, in centimetres)
            local x, y, z = -p[2] * 0.75, p[1] * 0.75, bb.y * 0.75
            local a = lib.quad_actor(world, wpos({ x, y, z }), bb.half * 0.75, bb.texture, "alpha")
            if a then
                G.extras[#G.extras + 1] = a
                G.sprites[#G.sprites + 1] = { actor = a, x = x, y = y, z = z }
            end
        end
    end
    pcall(G.open_paintings, data)
    -- (the sides under the edges he swings from: solid still, but out of STORROR's sight - ledges.lua)
    local own_coll = data.collision
    pcall(function()
        local LG = require("ledges")
        -- (the Bowser run's level its own: its solid ground split and kept apart from the plain Dark World's, which has
        -- its name - one taken for the other, the Fire Sea and the Sky had none, or the Dark World the run's)
        local key = name
        if data.joined then
            key = name .. "#run"
            local pl = {}
            for _, b in ipairs(LG.PLAIN[name] or {}) do pl[#pl + 1] = b end
            for _, b in ipairs(data.joined_plain or {}) do pl[#pl + 1] = b end
            LG.PLAIN[key] = pl
        end
        local main, hidden, n = LG.split(data.collision, key, data.vanish_walls and { data.vanish_walls } or nil)
        if hidden then
            local ha = LG.hidden_actor(world, hidden, OFFSET)
            if ha then own_coll = main; G.extras[#G.extras + 1] = ha end
            log("swing edges: %d (%d triangles out of STORROR's sight)", n, #hidden.idx // 3)
        end
    end)
    lib.add_collision(pmc, G.add_slides(actor, name, own_coll))
    if type(G.NO_SLIDES[name]) == "number" then
        pcall(function() pmc:SetWalkableSlopeOverride({ WalkableSlopeBehavior = 1, WalkableSlopeAngle = G.NO_SLIDES[name] }) end)
    end
    -- (the slide courses' floors are STORROR slide surfaces: they block its "Slide" trace channel, ECC_GameTraceChannel5
    -- = 18, as its own slides do - the user, 2026-10-16: "use storrors original sliding")
    if G.SLIDE_COURSES[name] then
        pcall(function() pmc:SetCollisionResponseToChannel(18, 2) end)
        local SL = package.loaded["slide"]
        if SL and SL.add_slide_pmc then pcall(SL.add_slide_pmc, pmc) end
    end
    G.vanish_actor = nil
    if data.vanish_walls then
        local va = lib.spawn_actor(world, OFFSET, 0.0)
        local vp = va and lib.add_pmc(va)
        if vp then
            lib.add_collision(vp, { data.vanish_walls })
            G.extras[#G.extras + 1] = va
            G.vanish_actor = va
            if CAPS and CAPS.on("vanish") then G.vanish_walls(false) end
        end
    end
    -- the DDD painting's floor (ddd_warp.inc.c): its three painting strips just behind it and floor round them, or,
    -- once "Board Bowser's Sub" is won, the same 2073.6 further back with the painting slid back there (paintings.c
    -- move_ddd_painting: 20 a frame, once - SAVE_FLAG_DDD_MOVED_BACK - G.ddd_slide) and the way before it open.
    -- (It was never exported: the DDD painting could not be entered, 2026-10-15.)
    -- (its vertical wind moved, where it is: G.VWIND_MOVE)
    local vmove = G.VWIND_MOVE and G.VWIND_MOVE[name]
    if vmove and not data.vwind_moved then
        data.vwind_moved = true
        local n = 0
        for _, f in ipairs(data.floors or {}) do
            if f.tag == "vwind" and f.pos then
                for i = 1, #f.pos, 3 do f.pos[i], f.pos[i + 1] = f.pos[i] + vmove[1], f.pos[i + 1] + vmove[2] end
                n = n + 1
            end
        end
        log("scene %s: its vertical wind moved %.0f, %.0f cm (%d floor%s)", name, vmove[1], vmove[2], n, n == 1 and "" or "s")
    end
    local coll_all, rule_all = data.collision, data.floors or {}
    G.ddd_slide = nil
    if data.ddd_warp then
        local MN = _G.MENU
        local won = MN and MN.has_star and (MN.has_star("ddd:0") or MN.has_star("ddd_2:0"))
        local which = won and data.ddd_warp.back or data.ddd_warp.front
        local da = lib.spawn_actor(world, OFFSET, 0.0)
        local dp = da and lib.add_pmc(da)
        if dp then lib.add_collision(dp, { which.collision }); G.extras[#G.extras + 1] = da end
        coll_all, rule_all = {}, {}
        for _, c in ipairs(data.collision) do coll_all[#coll_all + 1] = c end
        coll_all[#coll_all + 1] = which.collision
        for _, f in ipairs(data.floors or {}) do rule_all[#rule_all + 1] = f end
        for _, f in ipairs(which.floors or {}) do rule_all[#rule_all + 1] = f end
        if won then
            local back = MN.has_flag and MN.has_flag("ddd_moved_back")
            G.ddd_slide = { at = back and DDD_BACK or 0.0 }
        end
        log("DDD painting: %s", won and "back" or "in front")
    end
    G.floor = build_floor(coll_all)
    -- (the ceilings he can hang from apart: they are not floors to stand on, and would hide what lies under them)
    local rules, hangs = {}, {}
    for _, f in ipairs(rule_all) do if f.tag == "hang" then hangs[#hangs + 1] = f else rules[#rules + 1] = f end end
    G.rule = build_floor(rules)
    -- (and its vertical winds apart: under the tiny island's pit its wind's floor and the death plane over all the level
    -- lie at one height, and the death plane was the one found - the wind was never felt there, he fell on through:
    -- "the wind in THI doesnt lift the player", 2026-10-29. G.vwind_under, update_floors)
    do
        local vw = {}
        for _, f in ipairs(rules) do if f.tag == "vwind" then vw[#vw + 1] = f end end
        G.vwind_rule = (#vw > 0) and build_floor(vw) or nil
    end
    G.hang = (#hangs > 0) and build_floor(hangs, nil, 0.3) or nil
    G.bounds = build_floor(coll_all, nil, 0.05)             -- every floor and slope, for the level's edge
    G.inside = nil
    log("scene %s: %d/%d sections, %d floor tris (%.1fs)", name, made, #data.sections, G.floor.n, os.clock() - t0)

    G.water_actors, G.wlevel, G.water_changing, G.water_rot = {}, nil, false, {}
    G.mist_pmcs, G.mist_under = {}, nil
    add_water(world, data.water)
    -- (RENDER 96: the water made real - its look, waves round him, ripples - water96.lua)
    do
        local okw, W96 = pcall(require, "water96")
        if okw and W96 then
            local oks, errs = pcall(W96.setup, world, G)
            if not oks then log("water96: %s", tostring(errs)) end
        end
    end
    if MOVTEX then          -- the waterfalls, lava and sand Mario 64 draws apart from the level (movtex.lua)
        local mt = (lib.load_data("data.movtex") or {})[name]
        -- (and a course joined on's, moved with it: G.join_scenes)
        if data.movtex_extra and #data.movtex_extra > 0 then
            local all = {}
            for _, e in ipairs(mt or {}) do all[#all + 1] = e end
            for _, e in ipairs(data.movtex_extra) do all[#all + 1] = e end
            mt = all
        end
        local okm, errm = pcall(MOVTEX.load, world, mt, wpos({ 0, 0, 0 }))
        if not okm then log("moving textures failed: %s", tostring(errm)) end
    end
    if ENVFX then pcall(ENVFX.load, world, name) end
    G.portrait = nil
    if name == "castle" then pcall(G.lobby_light, world); pcall(G.bowser_portrait, world) end
    G.water_rects, G.gas_rects = {}, {}
    for _, b in ipairs(data.water or {}) do
        -- (only boxes under 50 are water, and not lava; 50, 60, ... are poison gas)
        local r = { x0 = -b.z2, x1 = -b.z1, y0 = b.x1, y1 = b.x2, z = b.y }
        if b.gas then G.gas_rects[#G.gas_rects + 1] = r
        elseif b.swim ~= false and (b.id or 0) < 50 then G.water_rects[#G.water_rects + 1] = r end
    end
    -- the castle grounds' moat, drained from the basement (moat_drainer.inc.c bhv_invisible_objects_under_bridge_init:
    -- both its water boxes at -800)
    if name == "grounds" and _G.MENU and _G.MENU.has_flag and _G.MENU.has_flag("moat_drained") then
        G.set_water_box(1, -800.0 * 0.75)
        G.set_water_box(2, -800.0 * 0.75)
        log("the moat is drained")
    end
    if name == "hmc" then pcall(G.hmc_hole_cover, world) end
    -- THI's summit pool, drained in this visit (thi_top.inc.c): 3000 in the huge island, 700 in the tiny
    if data.level ~= "thi" then
        G.thi_drained = nil
    elseif G.thi_drained then
        G.set_water_box(3, ((name == "thi") and 3000.0 or 700.0) * 0.75)
    end
    if name == "wdw" or name == "wdw_2" then
        -- (geo_wdw_set_initial_water_level: by how high he jumped into the painting; kept between the two areas)
        local start = G.wdw_level
        if not start then
            local py = G.painting_y
            start = (py and py <= 1382.4) and 31 or ((py and py >= 1600.0) and 2816 or 1024)
        end
        G.set_water_level(start)
        apply_water_level(0.0)
        log("WDW water at %d", start)
    end
    G.act = G.act_for(name, data.level)
    if G.act then log("scene %s: act %d", name, G.act) end
    -- (a Bob-omb Buddy in every act Mario 64 has one where it stands: the exporter kept one of the two at each spot -
    -- act 1's - so from act 2 the one who opens the cannons was never there: "wheres the pink bombombs that you talk to
    -- to open the cannons?", 2026-10-16. Its acts widened by those of the talk spots at the same place.)
    do
        local talk = (lib.load_data("data.talk") or {})[name] or {}
        for _, o in ipairs(data.objects) do
            if o.kind == "bobomb_buddy" and o.pos and o.acts then
                for _, t in ipairs(talk) do
                    if (t.kind == "buddy" or t.kind == "cannon_buddy") and t.pos and t.acts
                       and math.abs(t.pos[1] - o.pos[1]) < 5.0 and math.abs(t.pos[2] - o.pos[2]) < 5.0 then
                        o.acts = o.acts | t.acts
                    end
                end
            end
        end
    end
    -- (trees moved from where Mario 64 has them, the user's asking: scene cm, from -> to)
    for _, mv in ipairs(G.TREE_MOVES[name] or {}) do
        for _, o in ipairs(data.objects) do
            if o.kind == "tree" and o.pos and math.abs(o.pos[1] - mv[1]) < 5.0 and math.abs(o.pos[2] - mv[2]) < 5.0 then
                -- (its trunk's solid with it: the export puts each tree's trunk into the level's own collision, "trunks",
                -- and it stood on where the tree had been, unseen - "invisable tree infront of me", 2026-10-30)
                local dx, dy, dz = mv[3] - o.pos[1], mv[4] - o.pos[2], mv[5] - o.pos[3]
                for _, c in ipairs(data.collision or {}) do
                    if c.source == "trunks" and c.pos then
                        local P = c.pos
                        for i = 0, #P // 3 - 1 do
                            local x, y, z = P[i * 3 + 1], P[i * 3 + 2], P[i * 3 + 3]
                            if (x - o.pos[1]) ^ 2 + (y - o.pos[2]) ^ 2 < 40.0 * 40.0 and z > o.pos[3] - 50.0 and z < o.pos[3] + 600.0 then
                                P[i * 3 + 1], P[i * 3 + 2], P[i * 3 + 3] = x + dx, y + dy, z + dz
                            end
                        end
                    end
                end
                o.pos = { mv[3], mv[4], mv[5] }
            end
        end
    end
    pcall(G.add_bars, world, name)
    pcall(G.add_holds, world, name)
    pcall(G.add_signs, world, name)
    do
        local okg, errg = pcall(G.gauntlet_objects, name, data)
        if not okg then log("bowser run objects: %s", tostring(errg)) end
    end
    if G.EXTRA_OBJECTS[name] and not data.extras_in then
        data.extras_in = true
        for _, o in ipairs(G.EXTRA_OBJECTS[name]) do data.objects[#data.objects + 1] = o end
    end
    for _, o in ipairs(data.objects) do
        local ok, err = pcall(function()
            if o.acts and G.act and ((o.acts >> (G.act - 1)) & 1) == 0 then return end      -- (not in this act)
            if G.extra_act and o.kind == "star" and o.acts then return end      -- (an extra star's: not the act's own)
            if o.kind == "goomba" then add_goomba(world, o)
            elseif o.kind == "door" then add_door(world, o)
            elseif o.kind == "tree" then add_tree(world, o)
            elseif o.kind == "bowser" then add_bowser(world, o)
            elseif o.kind == "bowser_bomb" then add_bowser_bomb(world, o)
            elseif o.kind == "coin" or o.kind == "oneup" or o.kind == "heart" then G.add_pickup(o)
            elseif o.kind == "prop" then G.add_prop(world, o)
            elseif o.kind == "warp" or o.kind == "pipe" or o.kind == "fading_warp" then G.add_warp(o)
            elseif o.kind == "stardoor" then G.add_stardoor(world, o)
            elseif o.kind == "platform" then PLAT.add(world, o, data.templates)
            elseif o.kind == "star" then G.add_star(world, o)
            elseif o.kind == "red_coin_star" then
                G.red_star = G.add_star(world, o, true)
                local okm, errm = pcall(G.add_red_marker, world, o)
                if not okm then log("red coin marker failed: %s", tostring(errm)) end
            elseif o.kind == "slide_star" then
                -- (gCCMEnteredSlide: set by going down the slide, cleared when the course is entered afresh)
                if G.slid == G.level_of(name) then
                    G.add_star(world, { pos = o.to, id = o.id, from = o.pos })
                    log("back from the slide: its star has come out")
                end
            elseif o.kind == "secret_star" then G.secret_star = G.add_star(world, o, true)
            elseif o.kind == "secret_trigger" then G.add_trigger(o)
            elseif o.kind == "water_shell" then G.add_water_shell(world, o)
            elseif o.kind == "jingle" then G.jingles[#G.jingles + 1] = { x = o.pos[1], y = o.pos[2], z = o.pos[3] }
            elseif o.kind == "hoot" and HOOT then
                HOOT.add(world, o, { actor_data = actor_data, say = function(...) return G.say(...) end,
                                     floor = function(x, y, z) return floor_z(x, y, z) end })
            else
                for _, m in ipairs(CREATURES) do
                    if m.kinds and m.kinds[o.kind] then m.add(world, o, data.templates) end
                end
            end
        end)
        if not ok then log("object %s failed: %s", tostring(o.kind), tostring(err)) end
    end
    for _, pt in ipairs(data.paintings or {}) do pcall(add_painting, world, pt) end
    local schools, tanks = {}, {}
    for _, o in ipairs(data.objects or {}) do
        if o.kind == "fish_school" and (not o.acts or not G.act or ((o.acts >> (G.act - 1)) & 1) == 1) then
            schools[#schools + 1] = { pos = o.pos, count = o.count }
        elseif o.kind == "tank_fish" then
            tanks[#tanks + 1] = { pos = o.pos, count = o.count }
        end
    end
    if SCENERY and name ~= "grounds" and #schools + #tanks > 0 then     -- (fish.inc.c's schools: the lake fish's code)
        local oks, errs = pcall(SCENERY.load, world, { fish_schools = schools, tanks = tanks }, { floor_z = floor_z, water_at = water_at })
        if not oks then log("fish failed: %s", tostring(errs)) end
    end
    if MIRROR then
        local okm, errm = pcall(MIRROR.load, world, name, actor_data)
        if not okm then log("mirror failed: %s", tostring(errm)) end
    end
    if SCENERY and name == "grounds" then        -- the castle grounds' flags, birds, fish, mist and hidden 1-ups
        local oks, errs = pcall(SCENERY.load, world, lib.load_data("data.grounds_life"), {
            floor_z = floor_z, water_at = water_at, add_pickup = G.add_pickup,
            stars = function() return (_G.MENU and _G.MENU.star_count and _G.MENU.star_count()) or 0 end,
            sound = function(n) local S = package.loaded["sfx"]; if S then pcall(S.play, n) end end,
            waterfall = function(v) if MUSIC and MUSIC.waterfall then MUSIC.waterfall(v) end end })
        if not oks then log("scenery failed: %s", tostring(errs)) end
    end
    if BUTTERFLY then
        local places = (lib.load_data("data.butterflies") or {})[name]
        local okb, errb = pcall(BUTTERFLY.load, world, places, { floor_z = floor_z, add_pickup = G.add_pickup, actor_data = actor_data })
        if not okb then log("butterflies failed: %s", tostring(errb)) end
    end
    do
        local MN = _G.MENU
        local course = G.level_of(name)
        if MN and MN.has_flag and MN.has_flag("cannon_" .. course) and PLAT.open_cannons then
            pcall(PLAT.open_cannons, true)          -- (opened by a Bob-omb Buddy on an earlier visit: the file keeps it)
        end
    end
    -- (Lua's whole-heap collection now, while the screen is still closed on the scene's making - not in play: main.lua)
    pcall(collectgarbage, "collect")
    log("scene %s ready: %d goombas, %d doors, %d paintings, bowser=%s (%.1fs total)", name, #G.goombas, #G.doors,
        #G.paintings, tostring(G.bowser ~= nil), os.clock() - t0)
    pcall(function() G.world_addr = lib.world():GetAddress() end)    -- to notice if the game swaps the map out from under us
    -- (the engine's own kill height and world box off: a pawn past either is hidden, cut loose from its controller and
    -- destroyed (APawn::OutsideWorldBounds / FellOutOfWorld), and there is no getting him back - once, dying in Shifting
    -- Sand Land's quicksand under random input, he was gone 0.4 s after landing in the castle and every teleport after
    -- was refused, 2026-10-18. The mod has its own falls out of the level: G.fall_out, the edge, the respawn.)
    pcall(function()
        local ws = lib.world():K2_GetWorldSettings()
        if ws and ws.bEnableWorldBoundsChecks then ws.bEnableWorldBoundsChecks = false; log("world bounds checks off") end
    end)
    if SKY then pcall(SKY.apply, data.sky) end
    -- (RENDER 96: Unreal's sky, real clouds and the sun's rays under a daytime sky - sunsky.lua)
    do
        local okr, SS = pcall(require, "sunsky")
        if okr and SS then
            local oks, errs = pcall(SS.apply, data.sky, name)
            if not oks then log("sunsky: %s", tostring(errs)) end
        end
    end
    if package.loaded["fog"] then pcall(package.loaded["fog"].apply, name) end
    if MUSIC and G.music_held then
        G.music_held = nil
        pcall(MUSIC.play, nil)                  -- (Bowser's welcome first: the castle's tune after it)
    elseif MUSIC then pcall(MUSIC.play, G.music_override or data.music, G.music_override ~= nil) end     -- (the ending's tunes carry on)
    if SHELL then
        pcall(SHELL.load, world, { actor_data = actor_data, floor = function(x, y, z) return floor_z(x, y, z) end,
                                   water = function(x, y) return water_at(x, y) end })
    end
    if HANG and G.hang then
        local okh, errh = pcall(HANG.load, world, { ceiling = G.hang_ceiling })
        if not okh then log("hang failed: %s", tostring(errh)) end
    end
    if POLES then
        local climb = {}
        for _, o in ipairs(data.objects or {}) do
            if (o.kind == "pole" or o.kind == "tree") and not (o.acts and G.act and ((o.acts >> (G.act - 1)) & 1) == 0) then
                climb[#climb + 1] = o
            end
        end
        -- (Koopa the Quick's finish flag: a pole - bhvKoopaFlag is INTERACT_POLE, 700 high - solid and climbable as the
        -- trees are: "add collisions to the flag and also our tree pole so we can climb it", 2026-10-16)
        for _, o in ipairs(data.objects or {}) do
            local f = o.race and o.type ~= "bhvRacingPenguin" and o.race.flag
            if f and not (o.acts and G.act and ((o.acts >> (G.act - 1)) & 1) == 0) then
                local fx, fy = -f[3] * 0.75, f[1] * 0.75
                local fz = floor_z(fx, fy, f[2] * 0.75 + 100.0) or f[2] * 0.75
                climb[#climb + 1] = { kind = "pole", type = "bhvKoopaFlag", pos = { fx, fy, fz }, sm64 = { f[1], fz / 0.75, f[3] },
                                      height = 700.0, down = 0.0 }
            end
        end
        local okp, errp = pcall(POLES.load, world, climb, { actor_data = actor_data })
        if not okp then log("poles failed: %s", tostring(errp)) end
        if CLIMB then
            -- (RENDER 96: its trees' own heights - Render96's palm is 1.5 m taller than Mario 64's)
            local tt = data.tree_templates or (G.data and G.data.tree_templates)
            local r96 = lib.r96_trees and lib.r96_trees()
            if r96 and tt then
                local m = {}
                for k, v in pairs(tt) do m[k] = r96[k] or v end
                tt = m
            end
            local okc, errc = pcall(CLIMB.load, world, climb, { tree_templates = tt })
            if not okc then log("climb failed: %s", tostring(errc)) end
        end
    end
    if CAMLAK then
        local okc, errc = pcall(CAMLAK.load, world, name, {
            actor_data = actor_data, say = function(...) return G.say(...) end,
            wanted = function() return G.never_entered end,
            music_back_in = function(secs) G.music_back_at = os.clock() + secs end })
        if not okc then log("camera Lakitu failed: %s", tostring(errc)) end
    end
    if MUSIC and MUSIC.ambience then pcall(MUSIC.ambience, AMBIENCE._for(name)) end

    pcall(always_animate, lib.pawn())
    if not keep_player then G.teleport_spawn() end
    G.warp_cool = 2.0
    return true
end

-- hold the player in place (no gravity, no velocity) while freshly built collision comes online
function G.freeze(sec)
    local pawn = lib.pawn()
    if not pawn then return end
    pcall(function()
        local cm = pawn.CharacterMovement
        cm.GravityScale = 0.0
        cm:StopMovementImmediately()
    end)
    G.thaw_at = os.clock() + (sec or 1.5)
end

-- after a warp the player stands still and on his feet, whatever he was doing when it took him
local function settle(pawn)
    if G.set_down_for_good then G.set_down_for_good(false, pawn) end
    pcall(function() pawn.CharacterMovement.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 } end)
    if G.get_up then G.get_up(pawn, true) end
    G.getup_at = nil
    -- (out of the engine's flying or swimming movement before he is moved: those take the distance he went in a frame
    -- as his speed (PhysFlying: Velocity = moved / time), and a teleport out of the water - the swim flies him - became
    -- 7 km/s: flung 70 m and more off the level, out of Hazy Maze Cave, 2026-10-18. The same, very likely, lost him out of
    -- the world after Shifting Sand Land's quicksand.)
    pcall(function()
        local cm = pawn.CharacterMovement
        local mode = cm.MovementMode
        if mode == 4 or mode == 5 then cm:SetMovementMode(3, 0) end
        cm:StopMovementImmediately()
    end)
    -- (a fall begun in the scene he is leaving is not one he lands from here: STORROR's record of where it began goes,
    -- or a star taken high in the air - off Hoot, out of a cannon - knocked him flat on arriving, 2026-10-15)
    pcall(function() if pawn.CharacterMovement.MovementMode ~= 0 then G.parkour_reset(pawn) end end)
end

G.settle = settle

-- A speed no move of his comes near (a cannon's shot is 2250 cm/s, a long fall's under 5000): stopped, and the frame's
-- move it made taken back (a teleport the engine took for a move flings him once, then this), before it carries him out
-- of the world (G.tick, every frame)
function G.unfling(pawn, dt)
    local v = nil
    pcall(function() v = pawn:GetVelocity() end)
    if not v then return end
    local sp2 = v.X * v.X + v.Y * v.Y + v.Z * v.Z
    if sp2 < 15000.0 * 15000.0 then return end
    local l = nil
    pcall(function() l = pawn:K2_GetActorLocation() end)
    pcall(function()
        local cm = pawn.CharacterMovement
        if cm.MovementMode == 4 or cm.MovementMode == 5 then cm:SetMovementMode(3, 0) end
        cm:StopMovementImmediately()
        cm.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
    end)
    log("flung at %.0f cm/s: stopped", math.sqrt(sp2))
    if not l then return end
    local bx, by, bz = l.X - v.X * (dt or 0.0), l.Y - v.Y * (dt or 0.0), l.Z - v.Z * (dt or 0.0)
    if math.abs(bx - OFFSET.X) > 40000.0 or math.abs(by - OFFSET.Y) > 40000.0 or math.abs(bz - OFFSET.Z) > 40000.0 then
        pcall(G.respawn)
    else
        pcall(function() pawn:K2_TeleportTo({ X = bx, Y = by, Z = bz }, pawn:K2_GetActorRotation()) end)
    end
end

-- Never left in flying mode by nothing (G.tick, every frame): STORROR plays some moves in it (a roundoff) and the mod's
-- swim, climbs, carries and flights use it, but in it with no move playing and none of those, he stood running on the
-- spot - no gravity, no friction - "charater is stuck running forward", 2026-10-18, after STORROR's CHARACTER screen;
-- and taking a star under the metal cap. Half a second of that and he is put to falling, with what was going on logged.
function G.flying_guard(pawn, dt)
    local cm = pawn.CharacterMovement
    if cm.MovementMode ~= 5 then G.fly_stray = 0.0; return end
    local name = ""
    pcall(function() local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage(); if m and m:IsValid() then name = m:GetFName():ToString() end end)
    local PZ, CL, FL, HO = package.loaded["pause"], package.loaded["climb"], package.loaded["flight"], package.loaded["hoot"]
    local busy = name ~= "" or G.swim or G.carried or G.cutscene or G.pending or G.warping or G.dying or G.star_dance_st
        or G.entry or (CL and CL.active and CL.active()) or (FL and FL.active and FL.active()) or (HO and HO.active and HO.active())
        or (PZ and (PZ.open or (PZ.menu_up and PZ.menu_up()))) or (PLAT and PLAT.in_cannon)
    if busy then G.fly_stray = 0.0; return end
    G.fly_stray = (G.fly_stray or 0.0) + dt
    if G.fly_stray < 0.5 then return end
    G.fly_stray = 0.0
    pcall(function() cm:SetMovementMode(3, 0) end)
    pcall(G.parkour_reset, pawn)
    local v = cm.Velocity
    log("flying mode with nothing holding him: put to falling (speed %.0f)", math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z))
end

-- A painting's way out is inside the painting, on its own trigger floor: Mario 64 has him jump out of it forward.
-- Here a point on such a floor (a warp node, or a scene's start point: the castle basement's is on LLL's) is moved
-- past it the way he faces (or the other way, if that is the wall). (2026-10-14: coming out of WDW he stood on
-- WDW's trigger and went straight back in; the basement's start went into LLL.)
local function off_painting(x, y, z, yaw)
    local function on_painting(px, py)
        -- (in a painting's hollow, on its sill - G.recess_paintings - is in it still: put down there, 49 cm behind its
        -- picture, a step took him straight back in, 2026-10-29)
        if G.recess_at and G.recess_at(px, py, z) then return true end
        if not G.rule then return false end
        local rz, T = floor_hit(G.rule, px, py, z + 60.0)
        if not (T and type(T[11]) == "string" and T[11]:match("^paint:")) then return false end
        local oz = floor_z(px, py, z + 60.0)
        return not (oz and oz > rz + 5.0)
    end
    if not on_painting(x, y) then return x, y, yaw end
    local fx, fy = cos(rad(yaw)), sin(rad(yaw))
    for _, sgn in ipairs({ 1.0, -1.0 }) do
        for k = 1, 20 do
            local tx, ty = x + fx * sgn * 40.0 * k, y + fy * sgn * 40.0 * k
            if floor_z(tx, ty, z + 150.0) and not on_painting(tx, ty) then
                log("painting exit: put down past its trigger")
                return tx + fx * sgn * 60.0, ty + fy * sgn * 60.0, (sgn < 0) and (yaw + 180.0) or yaw
            end
        end
    end
    log("painting exit: could not get past its trigger")
    return x, y, yaw
end

-- Where to put him down at (x, y), from z (scene cm): the highest of the level's floor (within `reach` below), a
-- platform's floor, and deep water's surface (he falls into it, as Mario does).
local function put_down(x, y, z, reach)
    local fz = floor_z(x, y, z + 150) or floor_z(x, y, z + reach)
    local pz = PLAT.floor_under and PLAT.floor_under(x, y, z + 150)
    if pz and (not fz or pz > fz) then fz = pz end
    local wz = water_at(x, y)
    if wz and fz and wz > fz + 100.0 and wz < z + 150 then fz = wz end
    return fz
end

-- A flying warp's arrival (TotWC): Mario flies in (and up, onto the tower); he is put down on the first floor
-- ahead (the way `yaw` faces, within 4500) that is not more than 4500 below nor 600 above (TotWC: Mario glides
-- down 3600 onto the tower; the plane far under it is a warp).
local function fly_down(x, y, z, yaw)
    local fx, fy = cos(rad(yaw)), sin(rad(yaw))
    for d = 0.0, 4500.0, 75.0 do
        local px, py = x + fx * d, y + fy * d
        local fz = floor_z(px, py, z + 600)
        local pz = PLAT.floor_under and PLAT.floor_under(px, py, z + 600)
        if pz and (not fz or pz > fz) then fz = pz end
        if fz and fz > z - 4500.0 then return px + fx * 120.0, py + fy * 120.0, fz end
    end
    return nil
end

local function fly_node_at(x, y)
    for _, n in pairs(G.node or {}) do
        if n.kind == "fly" and abs(n.pos[1] - x) < 1.0 and abs(n.pos[2] - y) < 1.0 then return n end
    end
end

function G.teleport_spawn()
    local pawn = lib.pawn()
    if not (pawn and G.data) then log("teleport: no pawn/scene"); return end
    local s = G.data.spawn
    local sx, sy, syaw = off_painting(s.pos[1], s.pos[2], s.pos[3], s.yaw + 180.0)
    local sz = s.pos[3]
    if fly_node_at(s.pos[1], s.pos[2]) then
        local fx2, fy2, fz2 = fly_down(sx, sy, sz, syaw)
        if fx2 then sx, sy, sz = fx2, fy2, fz2 end
    elseif s.snap then
        sz = put_down(sx, sy, sz, 3000) or sz
    end
    local dest = { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z + 150.0 }
    G.last_node, G.last_opt = nil, nil
    G.entry = nil
    settle(pawn)
    -- (refused when the capsule would overlap something there: higher up, and at last forced - but first lower, his
    -- middle 90 over the floor: under the SL igloo's low way in, 150 up put his head in its roof and the next tries
    -- went out over it, inside its shell, as G.arrive's did - "spawned inside a wall in the igloo", 2026-10-26)
    local rot = { Pitch = 0.0, Yaw = syaw, Roll = 0.0 }
    local placed = false
    for _, up in ipairs({ 0.0, -60.0, 100.0, 250.0, 500.0 }) do
        local ok, r = pcall(function() return pawn:K2_TeleportTo({ X = dest.X, Y = dest.Y, Z = dest.Z + up }, rot) end)
        if ok and r then placed = true; dest.Z = dest.Z + up; break end
    end
    if not placed then
        pcall(function() pawn:K2_SetActorLocationAndRotation(dest, rot, false, {}, true) end)
        log("spawn: teleport refused, placed anyway")
    end
    pcall(function() lib.controller():SetControlRotation({ Pitch = 0.0, Yaw = syaw, Roll = 0.0 }) end)
    G.freeze(1.5)
    G.air = false               -- a warp is not a fall,
    G.no_fall_until = os.clock() + 3.0      -- and for a moment after one the player's position is not to be trusted
    log("player -> %s spawn (%.0f, %.0f, %.0f)", G.name, dest.X, dest.Y, dest.Z)
end

-- Ask for another scene. `node` is the warp node to arrive at there (none = its start point). `opt.flip`
-- says which side of a door to come out on; `opt.move` keeps his place, moved by that much, instead.
function G.goto_scene(name, node, opt)
    -- (not while a death's screen is closing in: its own way out follows. One asked for then fought it for the screen,
    -- and the screen stayed black for good, 2026-10-18)
    if G.dying then log("warp to %s held off: a death is under way", tostring(name)); return end
    -- (the Bowser run - G.GAUNTLET: a course's top on to the next course's start; out of it any way but the last fight
    -- won, out in front of its painting, the run over)
    -- (the last fight is the run's only, however he came to it: a death there goes back to the run's level by its pipe,
    -- not to the Sky on its own - "after dieing to bowser it put me in bowser in the sky? Our Level should be called Final
    -- Bowser", 2026-11-03)
    if not G.gauntlet and G.GAUNTLET and G.name == G.GAUNTLET.final and opt and opt.death then
        G.gauntlet = { t = os.clock() }
        log("bowser run: a death in the last fight, come to it outside the run - back to the run's level")
    end
    local R = G.gauntlet and G.GAUNTLET
    if R then
        local nx = R.next[name]
        if nx and R.scenes[G.name or ""] then
            log("bowser run: the top of %s - on to %s", tostring(G.name), nx[1])
            name, node, opt = nx[1], nx[2], {}
        end
        -- (a death in the last fight: back out by its pipe at the top of the joined level, the run going on, as Mario 64
        -- sends him back to the course from Bowser's arena - its way there, a course of G.RUN_JOIN's, is that course's
        -- node in the level it is part of: "Back at the pipe", 2026-11-03)
        -- (into the last fight from the run's level: its lava race as it is, for a death there to find again -
        -- G.lava_race_tick; "when player gets killed by bowser ... 2 the lava should be there", 2026-11-03)
        if name == R.final and G.name ~= R.final and R.scenes[G.name or ""] then
            local S = G.data and G.data.lava_race
            G.run_lava_kept = S and { phase = S.phase, z = S.z, want = S.want, rec = S.rec, t = S.t, ground = S.ground } or nil
        end
        local back = false
        if G.name == R.final and opt and opt.death and node then
            for main, joins in pairs(G.RUN_JOIN or {}) do
                for _, j in ipairs(joins) do
                    if not back and j.scene == name and R.scenes[main] then
                        log("bowser run: a death in the last fight - back by its pipe (%s node %d in %s)", name, node, main)
                        name, node, back = main, node + j.ids, true
                    end
                end
            end
        end
        -- (come to the fight some other way, none kept: the lava up at the top all the same - G.lava_race_tick)
        if back then
            G.lava_resume = G.run_lava_kept or { phase = "wait", z = -1.0e9, want = -1.0e9 }
            G.lava_resume.at = os.clock()
        end
        -- (a death anywhere else in it, wherever Mario 64 sends him, out too: off the last fight's stage it sent him back
        -- to the Sky on its own, the joined level gone - "the entire level has disappeared?", 2026-11-03)
        -- (EXIT TO CASTLE, though, to the castle itself as anywhere else - not in front of the painting: "cant exit to
        -- castle from final bowser just puts me outside", 2026-11-07)
        if not back and (not R.scenes[name] or (opt and opt.death)) then
            if (G.name ~= R.final or (opt and opt.death)) and not (opt and opt.to_castle) then
                log("bowser run: over - out in front of its painting")
                name, node, opt = R.exit[1], R.exit[2], opt
            end
            G.gauntlet, G.run_lava_kept, G.lava_resume = nil, nil, nil
        end
    end
    G.pending = { name = name, node = node, opt = opt or {} }
end

-- The controller left without the athlete (seen once, 2026-10-18: after two deaths on top of each other the player had
-- no pawn, every tick stopped short and the screen stayed black): his body taken back and put at the scene's start.
function G.repossess()
    local pc = lib.controller()
    if not pc then return end
    local ch = nil
    for _, c in ipairs(FindAllOf("SPPPlayerCharacterBP3_C") or {}) do
        -- (never one that is being destroyed: taken back, every teleport after was refused and he stood at the world's
        -- middle, 2026-10-18)
        local ok, alive = pcall(function() return c:IsValid() and not c.bActorIsBeingDestroyed and c.CharacterMovement:IsValid() end)
        if ok and alive then ch = c; break end
    end
    if not ch then
        if not G.no_athlete_said then G.no_athlete_said = true; log("no pawn, and no athlete to take back") end
        return
    end
    G.no_athlete_said = nil
    local ok, err = pcall(function() pc:Possess(ch) end)
    log("the controller had lost the athlete: taken back (%s %s)", tostring(ok), tostring(err))
    pcall(function() ch:SetActorHiddenInGame(false) end)
    pcall(function() ch.CharacterMovement:SetMovementMode(1, 0) end)
    G.dying, G.pending, G.entry = nil, nil, nil
    if TRANS then pcall(TRANS.forget); pcall(TRANS.open, "star", 16) end
    local HP = _G.HEALTH
    if HP then HP.dead_t = nil end
    pcall(G.set_down_for_good, false, ch)
    pcall(G.respawn)
end

-- Out by a warp, as Mario 64 shuts the screen for it (level_update.c level_trigger_warp): a door between areas a circle,
-- a pipe or a hole a star, a teleport a white fade, a painting a white fade (initiate_painting_warp), a star's exit
-- Mario's head; the pause menu's EXIT COURSE a black fade. `pin`: held still meanwhile (in a pipe, in a painting).
-- They all cut straight across before (2026-10-15).
-- a scene's level (its course): "thi_2" is Tiny-Huge Island's (data/scenes.lua)
local LEVEL_OF = nil
function G.level_of(scene)
    if LEVEL_OF == nil then
        LEVEL_OF = {}
        for _, e in ipairs(lib.load_data("data.scenes") or {}) do LEVEL_OF[e.name] = e.level end
    end
    return LEVEL_OF[scene] or scene
end

local WARP_OUT = { door = { "circle", 20 }, pipe = { "star", 20 }, warp = { "star", 20 }, fade = { "white", 20 },
                   painting = { "white", 30 }, star = { "mario", 32 }, exit = { "black", 16 },
                   lookup = { "white", 48 },       -- (WARP_OP_UNKNOWN_01: the Tower of the Wing Cap, into white)
                   shrink = { "white", 30 } }      -- (WARP_OP_SPIN_SHRINK: into the Boo's cage, twirl.lua M.into_cage)

-- (the music fades out as the screen closes, as Mario 64's fadeout_music does at a warp; back at its own loudness
-- for the next place's tune)
local function music_fade(frames)
    if not (MUSIC and MUSIC.set_volume) then return end
    if not G.mfade then G.mfade = { v0 = MUSIC.volume or 1.0 } end
    G.mfade.t, G.mfade.dur = 0.0, math.max(0.1, (frames or 20) / 30.0)
end
local function music_back()
    local f = G.mfade
    G.mfade = nil
    if f and MUSIC and MUSIC.set_volume then pcall(MUSIC.set_volume, f.v0) end
end
G.music_back = music_back
G.warping = false
-- (a star of a course begun in one place whichever way in he took: { [course] = { [act] = { scene, node } } }, the act
-- chosen at the star select. Tiny-Huge Island's 7th star, the ghost race: on the tiny island, its own painting's way in,
-- by the huge island's painting too - "for tiny huge 7th star race make the player start on the small map first even if
-- they go through the large painting", 2026-11-07)
G.STAR_START = { thi = { [7] = { scene = "thi_2", node = 10 } } }
function G.warp_out(kind, name, node, opt, pin)
    if G.warping or G.pending or G.dying then return end
    -- (no fall counted on the way out: a pipe's hold stops him - mode none, not falling - and that was taken for his
    -- landing, his jump into the pipe a long drop; knocked flat by it, he came into Bowser's arena limp and fell off it:
    -- "taking damage when entering level", "also fell through map again", 2026-10-25)
    G.no_fall_until = math.max(G.no_fall_until or 0.0, os.clock() + 5.0)
    if kind ~= "star" then G.complete = nil end         -- (the course-complete screen: only after a star)
    local t = WARP_OUT[kind]
    if not (TRANS and t) then G.goto_scene(name, node, opt); return end
    G.warping = true
    local token = {}
    G.warp_token = token
    G.warp_cool = math.max(G.warp_cool, 3.0)
    music_fade(t[2])
    if pin then
        local pawn = lib.pawn()
        if pawn then
            G.pinned = true
            pcall(function() pawn.CharacterMovement:StopMovementImmediately() end)
            pcall(function() pawn.CharacterMovement:SetMovementMode(0, 0) end)
        end
    end
    TRANS.close(t[1], t[2], function()
        if G.warp_token ~= token then return end        -- (another scene change came first: G.arrive)
        -- (a painting into one of the fifteen courses: Mario 64's star select first, out of the white and back
        -- into it, then the course at the act chosen - levels/menu level_main_menu_entry_2)
        local course = G.level_of(name)
        if (kind == "painting" or kind == "warp" or kind == "pipe" or kind == "shrink") and ACT_HUBS[G.name or ""] and STARSEL
            and STARSEL.open(course, function(act)
                music_fade(16)
                TRANS.close("white", 16, function()
                    STARSEL.close()
                    G.course_act = { course = course, act = act }
                    G.warping = false
                    local ss = G.STAR_START and G.STAR_START[course] and G.STAR_START[course][act]
                    if ss and ss.scene ~= name then
                        log("star %d of %s: begun in %s, not %s", act, course, ss.scene, tostring(name))
                        name, node = ss.scene, ss.node
                    end
                    G.goto_scene(name, node, opt)
                end)
            end) then
            music_back()                -- (the star select's own tune, at full loudness)
            STARSEL.play_music()
            TRANS.open("white", 16)
            return
        end
        G.warping = false
        G.goto_scene(name, node, opt)
    end)
end

-- ------------------------------------------------------------ per-frame logic
local function dist2(ax, ay, bx, by) local dx, dy = ax - bx, ay - by; return sqrt(dx * dx + dy * dy), dx, dy end

-- ------------------------------------------------------------ being knocked down
-- The athlete's own ragdoll: STORROR's ParkourComponent starts it, a shove on the hips sends him the
-- way the hit was going, and a little later he is told to get up (it only works once he has come to rest,
-- so it is asked a few times).
local function parkour(pawn)
    local addr = nil
    pcall(function() addr = pawn:GetAddress() end)
    if G.pk and G.pk_pawn == addr then
        local ok, valid = pcall(function() return G.pk:IsValid() end)
        if ok and valid then return G.pk end
    end
    G.pk, G.pk_pawn = nil, addr
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetClass():GetFName():ToString() == "ParkourComponent" then G.pk = o end
        end
    end)
    return G.pk
end

-- Untouchable: in a cannon (ACT_IN_CANNON is ACT_FLAG_INTANGIBLE - nothing hurts, throws or shoves him there;
-- "bombombs can kill me in the cannon", 2026-10-16)
G.REBUILD_SAFE = 3.0       -- (seconds he cannot be touched after the scene is built again round him)
function G.intangible(fall)
    -- (and held up by King Bob-omb: ACT_GRABBED is invulnerable)
    -- (and up on a Koopa shell: all he meets is beaten by it - shell.lua - Mario 64's shell ride takes no harm from them)
    -- (and once a death has begun - sucked under the quicksand, the screen closing: a Pokey's hit as the screen closed on
    -- a quicksand death knocked him limp, he arrived limp, and the life was never taken - "after dying to it and
    -- respawning, the charater didnt lose a life and has 1 hp left", 2026-10-23)
    -- (and for a moment after the scene is built again round him - G.safe_until - but for a fall: `fall`, health.lua's)
    -- (and while a message is up - a sign, a Toad, a ghost racer, any of Mario 64's dialogs - and from a star taken to
    -- the course's end: the wait before a star with no dance takes him out (G.star_exit_at) and the screen closing after
    -- the dance (G.warping, any warp's fade) - a Spindrift's touch as the dance ended and the screen closed hurt him and
    -- knocked him flat: "make sure the player cant be damaged during picking up stars, also during reading signs",
    -- 2026-11-08)
    return (PLAT ~= nil and PLAT.in_cannon ~= nil) or G.star_cut ~= nil or G.carried == "king" or G.star_dance_st ~= nil
        or G.carried == "shell" or G.dying ~= nil or (QSAND ~= nil and QSAND.dying ~= nil and QSAND.dying())
        or G.star_exit_at ~= nil or G.warping == true or (DIALOG ~= nil and DIALOG.active == true)
        or (not fall and os.clock() < (G.safe_until or 0.0))
end

-- (No ledge shield: the creatures went blind to him on a ledge and for 1.5 s after - "enemies edge gaurding",
-- 2026-11-03 - taken out again: "also the edge gaurding enemies shit is still on please remove that", 2026-11-05)

-- (`whole`: every part of him given that speed - thrown as one, as a blast does - not only his hips)
-- Out of sight (swallowed by Bubba: Mario 64's act_eaten_by_bubba takes Mario out of the picture till its death warp -
-- "after the fish eats the player make the player disappear", 2026-10-29): his own actor and every actor on him that
-- shows (the Mario look's pieces, the cap, the feet's copy - each its own actor), his shadow with them (shadows.lua goes
-- by his actor). Kept so each tick (G.hidden_tick) - the feet's copy comes and goes - and shown again, only what was
-- hidden here, once the scene changes (the death warp), or 15 s on whatever happens.
-- (His actor hidden alone did not do: STORROR shows its athlete again every frame - he stayed in sight, "player not
-- disappearing when eaten by bubba", 2026-10-29. So his body and every part under it - his clothes, his hair, the feet's
-- copy, the Mario look's pieces - each hidden in itself, which STORROR leaves be; and his shadow off by shadows.lua's
-- own switch, G.cutscene_noshadow, as it goes by his actor.)
function G.hide_athlete(on, why)
    local pawn = lib.pawn()
    if on then
        local h = G.athlete_hidden
        if not h then
            h = { scene = G.name, t = os.clock(), actors = {}, comps = {}, noshadow_was = G.cutscene_noshadow }
            G.athlete_hidden = h
            log("athlete out of sight (%s)", tostring(why))
        end
        G.cutscene_noshadow = true
        if not pawn then return end
        pcall(function() if not pawn.bHidden then pawn:SetActorHiddenInGame(true) end end)
        local out = {}
        pcall(function() pawn:GetAttachedActors(out, true, true) end)
        for i = 1, #out do
            pcall(function()
                local a = out[i]
                a = a.get and a:get() or a
                if not a.bHidden then a:SetActorHiddenInGame(true); h.actors[#h.actors + 1] = a end
            end)
        end
        local comps = {}
        pcall(function() pawn.Mesh:GetChildrenComponents(true, comps) end)
        table.insert(comps, 1, pawn.Mesh)
        -- (and every part of his own wherever it hangs: knocked flat first - Bubba's bump out of the water, then the
        -- swallow - STORROR's ragdoll has his clothes off his body's tree, and his shirt, arms and middle, stayed in
        -- sight: "dude the arms and stomach show after he eats the player", 2026-10-29)
        pcall(function()
            for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.PrimitiveComponent"))) do
                comps[#comps + 1] = c
            end
        end)
        for i = 1, #comps do
            pcall(function()
                local c = comps[i]
                c = c.get and c:get() or c
                if c:IsValid() and not c.bHiddenInGame then c:SetHiddenInGame(true, false); h.comps[#h.comps + 1] = c end
            end)
        end
    else
        local h = G.athlete_hidden
        G.athlete_hidden = nil
        if not h then return end
        if pawn then pcall(function() pawn:SetActorHiddenInGame(false) end) end
        for _, a in ipairs(h.actors) do pcall(function() if a:IsValid() then a:SetActorHiddenInGame(false) end end) end
        for _, c in ipairs(h.comps) do pcall(function() if c:IsValid() then c:SetHiddenInGame(false, false) end end) end
        -- (his hair, brows and beard and his clothes started again from their shape where he is: they were out of sight
        -- through a warp, and the strands came back flung)
        if pawn and G.reset_cloth then pcall(G.reset_cloth, pawn) end
        G.cutscene_noshadow = h.noshadow_was
        log("athlete in sight again")
    end
end
function G.hidden_tick()
    local h = G.athlete_hidden
    if not h then return end
    if G.name ~= h.scene or os.clock() - h.t > 15.0 then G.hide_athlete(false) else G.hide_athlete(true) end
end

G.WATER_KB = 16.0 * 0.75 * 30.0          -- cm/s: knocked back while swimming, Mario 64's 16 a frame
function G.knock_down(pawn, vx, vy, vz, whole)
    if not pawn or G.intangible() then return end
    -- (swimming: knocked back through the water, not down - Mario 64's water knockback: pushed off, slowing to a stop,
    -- and swimming again (swim.lua S.knock). A ragdoll there ended his swim and left him floating, helpless: Bubba bumped
    -- him and swallowed him as he lay - "bubba's attack is messed up", 2026-10-29. A death in the water ends the swim
    -- before it comes here.)
    local HPk = _G.HEALTH
    if SWIM and SWIM.active and SWIM.active() and SWIM.knock and not (HPk and HPk.dead_t) then
        local n = sqrt((vx or 0.0) ^ 2 + (vy or 0.0) ^ 2)
        local k = n > 1.0 and G.WATER_KB / n or 0.0
        pcall(SWIM.knock, (vx or 0.0) * k, (vy or 0.0) * k, 0.7)
        return
    end
    if FLIGHT and FLIGHT.knocked then pcall(FLIGHT.knocked, pawn) end
    -- (the push kept for ragdoll.lua to give his whole body a moment on: given here, as STORROR's ragdoll begins, it is
    -- lost - he went down on the spot, never thrown - "our euphoria kinda sucks right now", 2026-10-29)
    G.knock_push = { X = vx or 0.0, Y = vy or 0.0, Z = vz or 0.0, t = os.clock() }
    local pk = parkour(pawn)
    local ok = pk and pcall(function()
        pk:StartRagdoll(1.0, false)
        if whole then
            pawn.Mesh:AddImpulseToAllBodiesBelow({ X = vx, Y = vy, Z = vz }, FName("pelvis"), true, true)
        else
            pawn.Mesh:AddImpulse({ X = vx, Y = vy, Z = vz }, FName("pelvis"), true)
        end
    end)
    if not ok then lib.bounce(pawn, vx, vy, vz) return end      -- no ragdoll to be had: at least throw him
    if G.down_for_good then return end
    G.getup_at, G.getup_tries = os.clock() + 2.2, 0
end

-- (`force`: up now wherever he is - after a warp, revived. Otherwise not while he is still in the air or tumbling:
-- ragdoll.lua's M.settled - "when the player gets ragdolled, the players able to stand up instantly even in the air",
-- 2026-10-28; the timed get-up after a knock-down tries again later)
function G.get_up(pawn, force)
    if G.down_for_good then return end
    -- (the knock-down's timed get-up back: "never on his own" went with the Euphoria mod - "idk i give up lets get rid of
    -- the euphoria and load back up the sm64", 2026-10-29)
    local RG = package.loaded["ragdoll"]
    if not force then
        if RG and RG.settled and not RG.settled() then return end
        -- (up already - got up on his A: no more tries of the timed get-up, each of which reset his moves, a twitch every
        -- 0.8 s: "the player twitches when pressing a", 2026-10-28)
        if RG and RG.limp and not RG.limp() then G.getup_tries = 99; return end
    elseif RG and RG.forget_knock then
        RG.forget_knock()
    end
    local pk = pawn and parkour(pawn)
    if pk then pcall(function() pk:TryGetupFromRagdoll() end) end
end

-- Out of power he stays down till the screen has closed on him ("when you loose all your health you cant stand back
-- up", 2026-10-15): no get-up of the mod's (its timer, ragdoll.lua's A), and STORROR's own inputs off. Ended by the
-- death's warp, any arrival, any new scene.
local DOWN_SOURCE = "sm64_out_of_power"
function G.set_down_for_good(on, pawn)
    on = on and true or nil
    if (G.down_for_good or nil) == on then return end
    G.down_for_good = on
    if on then G.getup_at = nil end
    pawn = pawn or lib.pawn()
    local pk = pawn and parkour(pawn)
    if pk then pcall(function() pk:EnableAllParkourInputs(FName(DOWN_SOURCE), not on) end) end
    -- (all his controls off till he is back: a burn going out as he lay dying gave them back, and he stood up - "just
    -- lock the player in ragdoll until the reset just turn off the players controls", 2026-10-19; G.keep_down keeps
    -- them off)
    local pc = lib.controller()
    if pawn and pc then pcall(function() if on then pawn:DisableInput(pc) else pawn:EnableInput(pc) end end) end
    if pc then pcall(function() if on then pc:SetIgnoreMoveInput(true) else pc:ResetIgnoreMoveInput() end end) end
    log("out of power: %s", on and "down for good" or "free to get up again")
end

-- (and down he stays: STORROR stood him up of its own accord before the screen had closed - "make sure when the player
-- dies they cant stand up until they respawn", 2026-10-19 - so while he is out of power, found off his ragdoll he is
-- put back in it)
-- Limp on the lava - STORROR's own ragdoll as well as the mod's: his body, not his capsule, is where he is; at the lava
-- under his hips it is thrown up off it (check_lava_boost), hurt when he can be ("ragdolling on lava still isnt
-- fixed", 2026-10-19). Every frame (G.tick).
-- Mario 64's leap off the lava (ACT_LAVA_BOOST: straight up, his speed across gone but a little): STORROR's own moves
-- cleared, falling, his speed set by hand - a launch alone did nothing to the athlete (burn.lua's hop has it so too), and
-- he stood in the lava taking a hit a second: "mario gets stuck in the fire", 2026-10-19
function G.lava_boost(pawn)
    if not pawn then return end
    if G.parkour_reset then pcall(G.parkour_reset, pawn) end
    pcall(function()
        local cm = pawn.CharacterMovement
        cm:SetMovementMode(3, 0)
        local v = cm.Velocity
        cm.Velocity = { X = v.X * 0.3, Y = v.Y * 0.3, Z = 1500.0 }
    end)
end

function G.lava_limp(pawn)
    if not pawn then return end
    local HP = _G.HEALTH
    if not HP or HP.dead_t or os.clock() - (G.lava_at or 0.0) < 0.25 then return end
    local RG = package.loaded["ragdoll"]
    local limp = (RG and RG.active) or G.getup_at
    if not limp then
        pcall(function()
            if pawn.CharacterMovement.MovementMode == 0 then limp = true; return end
            local mt = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
            if mt and mt:IsValid() and mt:GetFName():ToString():find("Ragdoll", 1, true) then limp = true end
        end)
    end
    if not limp then return end
    local hp = nil
    pcall(function() hp = pawn.Mesh:GetSocketLocation(FName("pelvis")) end)
    if not hp then return end
    local x, y, z = hp.X - OFFSET.X, hp.Y - OFFSET.Y, hp.Z - OFFSET.Z
    if PLAT.over and PLAT.over(x, y, z - 20.0) then return end
    local lz = G.lava_z and G.lava_z(x, y, z + 60.0)
    if not (lz and z - lz < 30.0) then return end
    G.lava_at = os.clock()
    if not (CAPS and CAPS.on("metal")) and HP.grace <= 0 then
        HP.damage(HP.DAMAGE.fire, "lava")
        local BU = package.loaded["burn"]
        if BU and BU.lava then pcall(BU.lava) end
    end
    sfx("en_flame_blown")
    -- (on his feet at once, and off the lava as when he lands on it standing - "it should make the player stand back
    -- up instantly")
    if RG and RG.up_now then pcall(RG.up_now) end
    G.getup_at = nil
    G.lava_boost(pawn)
    log("lava: up off it at once")
end

function G.keep_down(pawn)
    if not (G.down_for_good and pawn) then return end
    G.keep_down_n = (G.keep_down_n or 0) + 1
    if G.keep_down_n % 10 == 0 then
        local pc = lib.controller()
        if pc then pcall(function() pawn:DisableInput(pc) end) end
    end
    -- (STORROR's own get-up - it starts by itself once he lies still - cut off as it begins: back into his ragdoll)
    local getup = false
    pcall(function()
        local mt = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
        getup = mt and mt:IsValid() and mt:GetFName():ToString():find("Getup", 1, true) ~= nil
    end)
    if getup then
        local pk = parkour(pawn)
        pcall(function() local ai = pawn.Mesh:GetAnimInstance(); ai:Montage_Stop(0.0, ai:GetCurrentActiveMontage()) end)
        if pk then pcall(function() pk:StartRagdoll(1.0, false) end) end
        if os.clock() - (G.keep_down_said or 0.0) > 1.0 then G.keep_down_said = os.clock(); log("out of power: his get-up stopped") end
        return
    end
    local HP = _G.HEALTH
    if not (HP and HP.dead_t and HP.dead_t > 1.0) then G.stood_since = nil; return end     -- (his fall first)
    -- (up: his hips back at standing height, as ragdoll.lua tells it - a moment of it)
    local standing = false
    pcall(function() standing = pawn.Mesh:GetSocketLocation(FName("pelvis")).Z > pawn:K2_GetActorLocation().Z - 35.0 end)
    if not standing then G.stood_since = nil; return end
    G.stood_since = G.stood_since or os.clock()
    if os.clock() - G.stood_since < 0.15 then return end
    G.stood_since = nil
    local pk = parkour(pawn)
    if pk then pcall(function() pk:StartRagdoll(1.0, false) end) end
    if os.clock() - (G.keep_down_said or 0.0) > 1.0 then G.keep_down_said = os.clock(); log("out of power: kept down") end
end

-- ------------------------------------------------------------ coins and other pick-ups
-- Mario 64's coins, 1-up mushrooms and recovery hearts are flat pictures that face the camera. A coin
-- spins by showing four pictures in turn (each for two Mario 64 frames). Coins placed in the level wait
-- to be collected; a coin knocked out of an enemy pops up, bounces to rest and blinks away after a while.
-- Yellow coins are worth 1 and give back one wedge of power, red 2, blue 5.
G.coins = {}
G.coin_count, G.red_count = 0, 0
local PICKUP_RANGE = 3600.0         -- pick-ups further than this from the player are not drawn or turned
local COIN_LIFE = 13.0
local PICKUPS = {
    coin = { frames = { "coin_front", "coin_tilt_right", "coin_side", "coin_tilt_left" }, half = 24.0 },
    red = { frames = { "coin_red_front", "coin_red_tilt_right", "coin_red_side", "coin_red_tilt_left" }, half = 24.0 },
    blue = { frames = { "coin_blue_front", "coin_blue_tilt_right", "coin_blue_side", "coin_blue_tilt_left" }, half = 30.0 },
    oneup = { frames = { "actors__mushroom_1up__1-up_mushroom.rgba16" }, half = 24.0 },
    heart = { frames = { "actors__heart__spinning_heart.rgba16" }, half = 30.0, turns = true },
}

-- RENDER 96: Render96's coins, models all round (data_r96/actor_coin3d_*, tools/r96_models.py), spun as Mario 64 spins
-- them (geo_rotate_coin), in place of the four pictures in turn - each its own shadow: "also wheres the coin 3d models?",
-- 2026-10-31. Their foot is their origin: COIN3D_MID under the coin's middle.
G.COIN3D = { coin = "coin3d_yellow", red = "coin3d_red", blue = "coin3d_blue" }     -- (on G: the main chunk is at its 200 locals)
G.COIN3D_MID, G.COIN3D_SPIN = 21.0, 337.5              -- (cm; degrees a second)
local function pickup_quads(c)
    local world = lib.world()
    if not world then return end
    c.quads, c.hidden, c.qlx = {}, {}, nil        -- (c.qlx: where each was last put - update_pickup)
    local m3 = lib.R96 and G.COIN3D[c.kind] and actor_data(G.COIN3D[c.kind])
    if m3 then
        local inst = lib.make_instance(world, m3, { X = c.x + OFFSET.X, Y = c.y + OFFSET.Y, Z = c.z + OFFSET.Z - G.COIN3D_MID }, 0.0, 1.0)
        if inst then
            pcall(lib.pose, inst, nil, 0)
            c.quads[1], c.hidden[1], c.model3d = inst.actor, false, true
            return
        end
    end
    for i, tex in ipairs(c.K.frames) do
        local q = lib.quad_actor(world, { X = c.x + OFFSET.X, Y = c.y + OFFSET.Y, Z = c.z + OFFSET.Z }, c.K.half, tex, "alpha")
        if q then pcall(function() q:SetActorHiddenInGame(i ~= 1) end) end
        c.quads[i], c.hidden[i] = q or false, (i ~= 1)
    end
    -- (one shadow for its pictures in turn: lib.twin_group)
    pcall(lib.twin_group, c.quads)
end

-- a coin thrown out of something (a squashed goomba)
function G.spawn_coin(x, y, z, blue)
    local a, s = math.random() * 2 * math.pi, math.random() * 240.0
    -- (`blue`: a blue coin, five - what a Mr. I or a Pokey's head leaves, bhvMrIBlueCoin)
    local c = { kind = blue and "blue" or "coin", K = blue and PICKUPS.blue or PICKUPS.coin, value = blue and 5 or 1,
        x = x, y = y, z = z, t = 0.0, life = COIN_LIFE,
        vx = cos(a) * s, vy = sin(a) * s, vz = 520.0 + math.random() * 420.0,
        -- (kept under what is over where they come out: a ! box's under WDW's yellow overhang threw them up through its
        -- underside, and they lay inside the block, out of sight - "this box doesnt drop anything?", "still nothing in
        -- it", 2026-10-28)
        roof = G.ceil_z and G.ceil_z(x, y, z) or nil }
    G.coins[#G.coins + 1] = c
    return c
end

-- Coins an enemy leaves when beaten, counted on it (`owner`): beaten again once it has come back, it leaves only those
-- he did not pick up - the ones that blinked away - and none while its last ones still lie about ("make sure enemies
-- dont double drop coins. if the player picked up the monsters coin dont respawn it", "if the player didnt make sure
-- it spawns another coin", 2026-10-17). (A coin gone before its time was up was picked up.)
function G.drop_loot(owner, n, x, y, z, blue)
    local key = blue and "loot_blue" or "loot"
    local L = owner[key]
    if not L then L = { out = {}, taken = 0 }; owner[key] = L end
    local lying = 0
    for i = #L.out, 1, -1 do
        local c = L.out[i]
        if c.gone then
            if c.t < (c.life or 13.0) then L.taken = L.taken + 1 end
            table.remove(L.out, i)
        else
            lying = lying + 1
        end
    end
    local owe = math.max(0, n - L.taken - lying)
    for _ = 1, owe do
        local c = G.spawn_coin(x, y, z, blue)
        if c then L.out[#L.out + 1] = c end
    end
    if owe < n then log("%s: %d of its %d coins (%d picked up before, %d still out)", tostring(owner.type or owner.kind or "enemy"), owe, n, L.taken, lying) end
    return owe
end

-- something the level itself has lying about (from the scene's object list)
-- (the coins over Shifting Sand Land's four pillars, 208 over their tops - 336 over the second's - out of reach from
-- them: set down on the tops, "lower the coins on top of each of the towers", 2026-10-23. The pillars' middles, Mario's
-- units, as the pyramid's touch spots: platforms.lua PYRAMID_PILLARS.)
G.COIN_ON_TOP = { ssl = { { 1789, 764 }, { 1789, -2579 }, { -5883, -2579 }, { -5883, 764 } } }
function G.add_pickup(o)
    local kind = o.kind
    if kind == "coin" then kind = o.red and "red" or (o.blue and "blue" or "coin") end
    local K = PICKUPS[kind]
    if not K then return end
    local x, y, z = o.pos[1], o.pos[2], o.pos[3]
    if o.ground then z = floor_z(x, y, z + 150) or z end
    local tops = G.COIN_ON_TOP[G.name or ""]
    if tops and not o.pop then
        for _, q in ipairs(tops) do
            if math.abs(y / 0.75 - q[1]) < 250.0 and math.abs(-x / 0.75 - q[2]) < 250.0 then
                local fz = floor_z(x, y, z)
                if fz and z - fz > 20.0 then z = fz + 8.0 end
            end
        end
    end
    G.coins[#G.coins + 1] = { kind = kind, K = K, value = o.value or 1, x = x, y = y, z = z + K.half, t = math.random() * 4.0,
        rest = true, fixed = true, lurk = o.lurk, need = o.need, touched = 0,
        -- (a moving blue coin stays where it is - "blue coins need to stay in place", 2026-10-27; Mario 64's slid off down
        -- the slide ahead of him. The sliding 1-up still comes after him)
        act = (o.slide and not o.blue) and "slide_wait" or (o.pop and "pop" or nil), at = 0, syaw = o.yaw,
        -- (a ! box's 1-up: out in the loop, not to be taken for 37 frames, then walking or running off - boxes.lua)
        pop_then = o.pop, dir = o.pop and o.dir or nil, pitch = o.pop and -0x4000 or nil,
        cool = o.pop and 37.0 / 30.0 or nil, acc = o.pop and 0.0 or nil,
        -- (and kept under what is over the box: its loop up took it through the slab over SSL's pyramid box, and it
        -- walked off on top of it, out of sight - "one up in this box didnt appear", 2026-10-23)
        roof = o.pop and G.ceil_z and G.ceil_z(x, y, z) or nil,
        -- (a moving blue coin: off within 1500, up to 75 a frame, gone 600 frames on - bhv_moving_blue_coin_loop)
        snear = (o.slide and o.blue) and 1500.0 or 1000.0, smax = (o.slide and o.blue) and 75.0 or 40.0,
        slife = (o.slide and o.blue) and 600 or nil }
end

-- the hidden blue coins, shown by a blue coin switch: 10 seconds in all, the last 40 frames blinking (Mario 64: 200 and 40
-- of blinking, cur_obj_wait_then_blink 200, 20 - "blue coin box timer fades too quickly", then "do 10", 2026-10-17)
function G.reveal_blue()
    local n = 0
    for _, c in ipairs(G.coins) do
        if c.lurk == "blue" then
            c.lurk, c.fixed, c.t, c.life, c.blink = nil, false, 0.36, 10.0, 40.0 / 30.0
            c.switched = true
            n = n + 1
        end
    end
    G.blue_ticking = n > 0
    log("blue coin switch: %d blue coins out", n)
end

-- The switch ticks while any of its coins is left, and stops once they are all taken or gone (bhv_blue_coin_switch_loop:
-- deleted once no bhvHiddenBlueCoin is near; "once you collect all the coins make the countdown stop", 2026-10-17).
-- A held sound, asked for every frame: played once, the coins' own sounds on the three players cut it short.
function G.blue_tick_check()
    if not G.blue_ticking then return end
    local S = package.loaded["sfx"]
    for _, c in ipairs(G.coins) do
        if c.switched and not c.gone then
            -- (its own ticking, as long as the coins are out - 10 s, its last tick just before they go: switch_ticks'
            -- 8.5 s ran out with them out another second - "blue coin timer not making coins dissappear when audio
            -- ends", 2026-10-28; tools/blue_ticks.py)
            if S and S.hold then pcall(S.hold, "switch_ticks_blue", 1.0) end
            return
        end
    end
    G.blue_ticking = false
    log("blue coin switch: all its coins gone - the ticking stops")
end

-- Invisible triggers: secrets for a level's hidden star (five) and the ones that call out a hidden 1-up
G.triggers, G.secrets = {}, 0
function G.add_trigger(o)
    G.triggers[#G.triggers + 1] = { x = o.pos[1], y = o.pos[2], z = o.pos[3], what = o.what }
end

-- (a secret still in its box - a ! box or cork box not yet broken, its foot within 80 cm over it - or under a metal box
-- not yet pushed off it, is not there to touch: WDW's five are in three ! boxes and under two metal boxes, and were
-- taken by standing by them - "The 5 boxes around the map trigger by just being by them instead of having to break
-- them", 2026-10-28)
function G.trigger_covered(t)
    local BX = package.loaded["boxes"]
    for _, b in ipairs(BX and BX.list or {}) do
        if b.action ~= "broken" and not b.outline and b.action ~= "held" then
            local s = b.scale or 1.0
            local half, y0, y1 = 100.0 * s, 0.0, 200.0 * s
            if b.ex then half, y0, y1 = 25.0 * s, 1.0 * s, 52.0 * s end
            local bx, by, bz = -b.z * 0.75, b.x * 0.75, b.y * 0.75
            local hc = half * 0.75 + 30.0
            if abs(t.x - bx) < hc and abs(t.y - by) < hc and t.z > bz + y0 * 0.75 - 80.0 and t.z < bz + y1 * 0.75 + 30.0 then return true end
        end
    end
    for _, p in ipairs(PLAT and PLAT.list or {}) do
        if p.slide ~= nil then
            -- (Mario 64 units, about its middle, turned to its own square: 153 out each way, 307 up)
            local dx, dz, dy = t.y / 0.75 - p.x, -t.x / 0.75 - p.z, t.z / 0.75 - p.y
            local c, sn = math.cos((p.yaw or 0) * math.pi / 32768.0), math.sin((p.yaw or 0) * math.pi / 32768.0)
            local lx, lz = dx * c - dz * sn, dx * sn + dz * c
            if abs(lx) < 140.0 and abs(lz) < 140.0 and dy > -60.0 and dy < 320.0 then return true end
        end
    end
    return false
end

local function update_triggers(px, py, pz)
    local x, y, z = px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z
    for i = #G.triggers, 1, -1 do
        local t = G.triggers[i]
        -- (Mario 64: a cylinder 100 units round and high; the athlete is a bigger target than Mario)
        if dist2(x, y, t.x, t.y) < 110.0 and z > t.z - 160.0 and z < t.z + 200.0 and not G.trigger_covered(t) then
            table.remove(G.triggers, i)
            if t.what == "star" then
                G.secrets = G.secrets + 1
                sfx("secret_" .. math.min(G.secrets, 5))
                if ENVFX and ENVFX.number then pcall(ENVFX.number, G.secrets, t.x, t.y, t.z) end     -- (its count, in orange)
                log("secret %d of 5", G.secrets)
                if G.secrets == 5 and G.secret_star and G.secret_star.hidden then
                    -- (hidden_star.inc.c: spawn_red_coin_cutscene_star, as the red coins' - it came out unseen, far
                    -- off: "the 5 coins star in the coin rings", 2026-10-16)
                    G.reveal_star(G.secret_star)
                    log("five secrets: the star has appeared")
                end
            else
                -- the nearest hidden 1-up counts it
                local best, bd = nil, nil
                for _, c in ipairs(G.coins) do
                    if c.lurk == "oneup" then
                        local d = dist2(t.x, t.y, c.x, c.y) + abs(t.z - c.z)
                        if not bd or d < bd then best, bd = c, d end
                    end
                end
                if best then
                    best.touched = best.touched + 1
                    -- (its marks right under it: the top of a pole - 37.5 and 187.5 cm under it there. Not one whose
                    -- mark is level with it, 15 cm under or above it: the castle's, Dire, Dire Docks' and the Secret
                    -- Aquarium's plain hidden 1-ups, which run off as a 1-up does - they flew at him, 2026-10-18)
                    if dist2(t.x, t.y, best.x, best.y) < 30.0 and best.z - ((best.K and best.K.half) or 0.0) - t.z > 25.0 then best.pole = true end
                    if best.touched >= (best.need or 0) then
                        best.lurk = nil
                        best.act, best.at, best.acc, best.cool = "pop", 0, 0.0, 37.0 / 30.0
                        sfx("oneup_appear")
                        log("hidden 1-up out%s", best.pole and " (the pole's)" or "")
                    end
                end
            end
        end
    end
end

-- Mario 64's sounds (rendered from the player's ROM by sm64audio into <mod>/sfx): its coin counter dings once for
-- each coin it counts up (a blue coin five times; the underwater ding while swimming), a red coin plays its
-- jingle a step higher for each of the eight, and a stomped goomba is the bounce, its squish and, as it goes,
-- its puff (the low one for a huge goomba).
local function sound(name)
    local S = package.loaded["sfx"]
    if S then pcall(S.play, name) end
end

local function collect(c)
    local HP = _G.HEALTH
    if c.kind == "oneup" then
        if HP then HP.lives = HP.lives + 1 end
        sfx("oneup")
        log("1-up")
    else
        if ENVFX and ENVFX.sparkle then pcall(ENVFX.sparkle, c.x, c.y, c.z) end     -- (bhvGoldenCoinSparkles)
        local before = G.coin_count
        G.coin_count = G.coin_count + c.value
        if before < 100 and G.coin_count >= 100 then pcall(G.hundred_coin_star) end
        if HP then HP.heal(c.value) end
        if c.kind == "red" then
            sound("coin_red_" .. math.max(1, math.min(8, G.red_count + 1)))
        elseif c.kind == "blue" then
            sound(G.swim and "coin_blue_water" or "coin_blue")
        else
            sound(G.swim and "coin_water" or "coin")
        end
        if c.kind == "red" then
            G.red_count = G.red_count + 1
            log("red coin %d of 8", G.red_count)
            if ENVFX and ENVFX.number then pcall(ENVFX.number, G.red_count, c.x, c.y, c.z) end     -- (its count, in orange)
            if G.on_red_coin then G.on_red_coin(G.red_count) end
        end
    end
    return true
end

-- The spinning heart (recovery_heart.inc.c bhv_recovery_heart_loop; "next add the spinning heart that gives health",
-- 2026-10-16 - it was a pick-up that gave 8 wedges at a touch): it turns slowly by itself (400 a frame); run through it
-- (its 50-unit cylinder and his) and it spins with his speed - 200 x his speed + 1000 a frame - and every whole turn
-- mends a wedge (healCounter += 4), on and on as it slows after him by 50 a frame back to 400 (where its count of
-- turns starts again). SOUND_GENERAL_HEART_SPIN as he goes in.
local HEART_REACH = 85.0            -- cm round it that reach him (the athlete is wider than Mario)
local function heart_step(c, dt, d2, pz, sp)
    c.vel, c.ang, c.spin = c.vel or 400, c.ang or 0, c.spin or 0
    local inside = d2 < HEART_REACH * HEART_REACH and abs((pz - OFFSET.Z) - c.z) < 150.0
    if inside and not c.inside then sfx("heart") end
    c.inside = inside
    c.hacc = math.min((c.hacc or 0.0) + dt * 30.0, 6.0)
    while c.hacc >= 1.0 do
        c.hacc = c.hacc - 1.0
        if inside then
            c.vel = floor(200.0 * (sp / (0.75 * 30.0)) + 1000.0)
        else
            c.vel = c.vel - 50
            if c.vel < 400 then c.vel, c.spin = 400, 0 end
        end
        c.spin = c.spin + c.vel
        if c.spin >= 0x10000 then
            c.spin = c.spin - 0x10000
            local HP = _G.HEALTH
            if HP then HP.heal(1) end
        end
        c.ang = (c.ang + c.vel) % 0x10000
    end
end

-- A hidden 1-up out (mushroom_1up.inc.c bhv_1up_hidden_loop / bhv_1up_hidden_in_pole_loop): it jumps up and loops
-- the loop in the air (one_up_loop_in_air: 40 up for 5 frames, then round at 30 a frame, 0x1000 of turn a frame) and
-- can be taken after 37 frames; then the one called out by the marks on the ground runs off, away from him at 8 a
-- frame (one_up_move_away_from_mario) - into a wall, or 3000 off, and it flickers out (obj_flicker_and_disappear, 30
-- frames) - and the one at the top of a pole flies at him, 30 a frame (pole_1up_move_towards_mario). Before, both just
-- appeared where they were and waited.
local ONEUP_CM = 0.75                       -- (Mario units -> scene cm)
local function oneup_step(c, dt, px, py, pz)
    -- (a moving 1-up leaves sparkles behind it: bhvSparkleSpawn - not a moving blue coin)
    if c.kind == "oneup" and c.act ~= "slide_wait" and c.act ~= "vanish" and ENVFX and ENVFX.sparkle then
        c.spark_t = (c.spark_t or 0.0) + dt
        if c.spark_t >= 0.1 then c.spark_t = 0.0; pcall(ENVFX.sparkle, c.x, c.y, c.z - 25.0, 1) end
    end
    c.acc = math.min((c.acc or 0.0) + dt * 30.0, 6.0)
    -- (its floors and its height under the ceiling it came out under, c.roof)
    local roof = c.roof
    local function floor_z(x, y, zmax)
        if roof and zmax > roof - 1.0 then zmax = roof - 1.0 end
        return G.floor_z(x, y, zmax)
    end
    local function under_roof()
        if roof and c.z > roof - c.K.half - 4.0 then c.z = roof - c.K.half - 4.0; if (c.vy or 0.0) > 0.0 then c.vy = 0.0 end end
    end
    local ax, ay = px - OFFSET.X, py - OFFSET.Y
    local afeet = pz - OFFSET.Z - (G.half or 90.0)
    while c.acc >= 1.0 do
        c.acc = c.acc - 1.0
        c.at = c.at + 1
        if c.act == "pop" then
            if not c.dir then
                local dx, dy = c.x - ax, c.y - ay
                local d = sqrt(dx * dx + dy * dy)
                if d < 1.0 then dx, dy, d = 1.0, 0.0, 1.0 end
                c.dir, c.pitch = { dx / d, dy / d }, -0x4000
            end
            local vy, fv = 40.0, 0.0
            if c.at > 5 then
                c.pitch = c.pitch - 0x1000
                local p = c.pitch * math.pi / 32768.0
                vy, fv = cos(p) * 30.0 + 2.0, -sin(p) * 30.0
            end
            local nx, ny = c.x + c.dir[1] * fv * ONEUP_CM, c.y + c.dir[2] * fv * ONEUP_CM
            if floor_z(nx, ny, c.z + 200.0) then c.x, c.y = nx, ny end
            c.z = c.z + vy * ONEUP_CM
            under_roof()
            local fz = floor_z(c.x, c.y, c.z + 80.0)
            if fz and c.z < fz + c.K.half then c.z = fz + c.K.half end
            if c.at >= 37 then c.act, c.at, c.vy = (c.pole and "home" or (c.pop_then or "away")), 0, 0.0 end
        elseif c.act == "away" then
            local dx, dy = c.x - ax, c.y - ay
            local d = sqrt(dx * dx + dy * dy)
            if d > 3000.0 * ONEUP_CM then c.act, c.at = "vanish", 0
            else
                if d < 1.0 then dx, dy, d = 1.0, 0.0, 1.0 end
                local nx, ny = c.x + dx / d * 8.0 * ONEUP_CM, c.y + dy / d * 8.0 * ONEUP_CM
                local fz = floor_z(nx, ny, c.z + 80.0)
                local wall = G.wall_near and G.wall_near(nx, ny, c.z, 20.0)
                if wall then c.act, c.at = "vanish", 0
                elseif fz then c.x, c.y = nx, ny end
                -- (its own weight: 3 a frame, down to its floor)
                c.vy = math.max(-75.0, (c.vy or 0.0) - 3.0)
                c.z = c.z + c.vy * ONEUP_CM
                under_roof()
                local gz = floor_z(c.x, c.y, c.z + 80.0)
                if gz and c.z <= gz + c.K.half then c.z, c.vy = gz + c.K.half, 0.0 end
            end
        elseif c.act == "walk" then
            -- (bhv_1up_walking_loop, the ! box's: on at 2 a frame the way it came out, its own weight 3 a frame, down to
            -- its floor; 300 frames on it flickers out. Before, it hung in the air where the box was: "floating one up
            -- after breaking a box", 2026-10-17)
            if c.at > 300 then c.act, c.at = "vanish", 0
            else
                local nx, ny = c.x + c.dir[1] * 2.0 * ONEUP_CM, c.y + c.dir[2] * 2.0 * ONEUP_CM
                local wall = G.wall_near and G.wall_near(nx, ny, c.z, 20.0)
                if not wall and floor_z(nx, ny, c.z + 80.0) then c.x, c.y = nx, ny end
                c.vy = math.max(-75.0, (c.vy or 0.0) - 3.0)
                c.z = c.z + c.vy * ONEUP_CM
                under_roof()
                local gz = floor_z(c.x, c.y, c.z + 80.0)
                if gz and c.z <= gz + c.K.half then c.z, c.vy = gz + c.K.half, 0.0 end
            end
        elseif c.act == "home" then
            local tx, ty, tz = ax - c.x, ay - c.y, afeet + 120.0 * ONEUP_CM - c.z
            local d = sqrt(tx * tx + ty * ty + tz * tz)
            local step = 30.0 * ONEUP_CM
            if d <= step then c.x, c.y, c.z = ax, ay, afeet + 120.0 * ONEUP_CM
            else c.x, c.y, c.z = c.x + tx / d * step, c.y + ty / d * step, c.z + tz / d * step end
        elseif c.act == "slide_wait" then
            -- (bhv_1up_sliding_loop: the sliding 1-up waits till he is within 1000)
            if sqrt((c.x - ax) ^ 2 + (c.y - ay) ^ 2 + (c.z - afeet) ^ 2) < (c.snear or 1000.0) * ONEUP_CM then
                local a = rad(c.syaw or 0.0)
                c.act, c.at, c.fv, c.vy, c.dir = "slide", 0, 0.0, 0.0, { -cos(a), sin(a) }
            end
        elseif c.act == "slide" then
            -- (sliding_1up_move: on the ground 25 a frame faster, 40 at most, the floor's tilt turning it down the slide;
            -- 2% lost a frame in the air; 5000 off him, it flickers out)
            local fz, nx, ny, nz = G.floor_normal(c.x, c.y, c.z + 60.0)
            local grounded = fz and (c.z - c.K.half) - fz < 12.0
            if grounded then
                c.fv = math.min(c.smax or 40.0, c.fv + 25.0)
                if nz and nz < 0.999 then
                    local vx, vy = c.dir[1] * c.fv + nx * 20.0, c.dir[2] * c.fv + ny * 20.0
                    local l = sqrt(vx * vx + vy * vy)
                    if l > 0.01 then c.dir = { vx / l, vy / l } end
                end
            else
                c.fv = c.fv * 0.98
            end
            local tx, ty = c.x + c.dir[1] * c.fv * ONEUP_CM, c.y + c.dir[2] * c.fv * ONEUP_CM
            local hit, wx, wy = false, 0.0, 0.0
            if G.wall_near then hit, wx, wy = G.wall_near(tx, ty, c.z, 25.0) end
            if hit then
                -- (along the wall, the way into it lost)
                local l = sqrt(wx * wx + wy * wy)
                if l > 1e-6 then
                    local ux, uy = wx / l, wy / l
                    local vn = c.dir[1] * ux + c.dir[2] * uy
                    if vn < 0.0 then
                        local dx, dy = c.dir[1] - vn * ux, c.dir[2] - vn * uy
                        local dl = sqrt(dx * dx + dy * dy)
                        if dl > 1e-3 then c.dir = { dx / dl, dy / dl } end
                    end
                end
                tx, ty = tx + wx, ty + wy
            end
            if floor_z(tx, ty, c.z + 200.0) then c.x, c.y = tx, ty end
            c.vy = math.max(-75.0, (c.vy or 0.0) - 4.0)
            c.z = c.z + c.vy * ONEUP_CM
            local gz = floor_z(c.x, c.y, c.z + 80.0)
            if gz and c.z <= gz + c.K.half then c.z, c.vy = gz + c.K.half, 0.0 end
            if sqrt((c.x - ax) ^ 2 + (c.y - ay) ^ 2) > 5000.0 * ONEUP_CM then c.act, c.at = "vanish", 0 end
            if c.slife and c.at > c.slife - 30 then c.act, c.at = "vanish", 0 end
        elseif c.act == "vanish" then
            if c.at > 30 then c.gone = true; return end
        end
    end
end

local function update_pickup(c, dt, px, py, pz, cx, cy, sp)
    if c.lurk then return end
    c.t = c.t + dt
    if c.cool then c.cool = c.cool - dt; if c.cool <= 0 then c.cool = nil end end
    if c.act then oneup_step(c, dt, px, py, pz); if c.gone then return end end
    if not c.rest then
        c.vz = c.vz - 2700.0 * dt
        local nx, ny, nz = c.x + c.vx * dt, c.y + c.vy * dt, c.z + c.vz * dt
        -- (no higher than the roof over where it came out; its floor looked for from under that roof)
        local probe = c.z + 80
        if c.roof then
            if nz > c.roof - c.K.half then
                nz = c.roof - c.K.half
                if c.vz > 0.0 then c.vz = 0.0 end
            end
            probe = math.min(probe, c.roof - 1.0)
        end
        -- (and off walls, back the way they came at half the speed: kept under the overhang, two of the three flew out
        -- through the wall beside the box and fell out of the level)
        if (nx ~= c.x or ny ~= c.y) and G.wall_near and G.wall_near(nx, ny, nz, 20.0) then
            nx, ny = c.x, c.y
            c.vx, c.vy = -c.vx * 0.5, -c.vy * 0.5
        end
        local fz = floor_z(nx, ny, probe)
        -- (and a platform's top under it - a metal box's: they fell in through its top, "coins fall into moving box
        -- also", 2026-10-28)
        if PLAT and PLAT.top_under then
            local okt, tz = pcall(PLAT.top_under, nx, ny, probe - 45.0)
            if okt and tz and (not fz or tz > fz) then fz = tz end
        end
        if fz and nz <= fz + c.K.half then
            nz = fz + c.K.half
            if c.vz < -240.0 then
                c.vz, c.vx, c.vy = -c.vz * 0.5, c.vx * 0.6, c.vy * 0.6
            else
                c.vz, c.vx, c.vy, c.rest = 0.0, 0.0, 0.0, true
            end
        elseif not fz then
            nx, ny = c.x, c.y                   -- nothing under it that way: stay over the ground
            c.vx, c.vy = 0.0, 0.0
        end
        c.x, c.y, c.z = nx, ny, nz
    end

    local rx, ry = (px - OFFSET.X) - c.x, (py - OFFSET.Y) - c.y
    local d2 = rx * rx + ry * ry
    if c.kind == "heart" then heart_step(c, dt, d2, pz, sp or 0.0) end
    if d2 > PICKUP_RANGE * PICKUP_RANGE then
        if c.quads and not c.far then
            c.far = true
            for i, q in ipairs(c.quads) do
                if q and not c.hidden[i] then c.hidden[i] = true; pcall(function() q:SetActorHiddenInGame(true) end) end
            end
        end
    else
        if not c.quads then pickup_quads(c) end
        c.far = false
        local n = #c.K.frames
        -- coins that belong to the level all turn together, as they do in Mario 64
        local frame = (n > 1 and not c.model3d) and (floor((c.fixed and os.clock() or c.t) * 15.0) % n + 1) or 1
        local blink = (not c.fixed) and c.t > (c.life or COIN_LIFE) - (c.blink or 2.5) and floor(c.t * 12.0) % 2 == 0
        if c.act == "vanish" then blink = c.at % 2 == 0 end
        local wx, wy, wz = c.x + OFFSET.X, c.y + OFFSET.Y, c.z + OFFSET.Z
        local yaw
        if c.model3d then
            yaw = ((c.fixed and os.clock() or c.t) * G.COIN3D_SPIN) % 360.0
            wz = wz - G.COIN3D_MID
        elseif c.K.turns then
            yaw = (((c.ang or 0) + (c.vel or 400) * (c.hacc or 0.0)) * 360.0 / 65536.0) % 360.0   -- (heart_step)
            -- (its back draws black: turned half round whenever that would face the camera - the heart is the same both
            -- ways round, so the spin looks no different)
            local fr = rad(yaw)
            if -cos(fr) * (cx - wx) - sin(fr) * (cy - wy) < 0.0 then yaw = yaw + 180.0 end
        else
            yaw = deg(atan(cy - wy, cx - wx)) + 180.0
        end
        -- (each picture's last place and turn kept: put there again only when it has moved, or turned G.COIN_TURN)
        local lx, ly, lz, lyaw = c.qlx, c.qly, c.qlz, c.qlyaw
        if not lx then
            lx, ly, lz, lyaw = {}, {}, {}, {}
            c.qlx, c.qly, c.qlz, c.qlyaw = lx, ly, lz, lyaw
        end
        local turn = G.COIN_TURN or 0.0
        -- (a 3D coin's spin, off from him: G.COIN3D_STEPS)
        local due = true
        local S = G.COIN3D_STEPS
        if c.model3d and S and lyaw[1] ~= nil and lx[1] == wx and ly[1] == wy and lz[1] == wz and d2 > S.near * S.near then
            local hz = (d2 > S.far * S.far) and S.far_hz or S.near_hz
            due = os.clock() - (c.spun_at or 0.0) >= 1.0 / hz
        end
        for i, q in ipairs(c.quads or {}) do
            if q then
                -- (and the first picture always: its twin casts the coin's shadow - lib.twin_group - and left where it was
                -- last shown, a coin knocked out of something left its shadow behind: "also coin shadows need fixed",
                -- 2026-10-31)
                local put = due and (i == frame or i == 1) and (lyaw[i] == nil or lx[i] ~= wx or ly[i] ~= wy or lz[i] ~= wz
                    or abs(((yaw - lyaw[i] + 540.0) % 360.0) - 180.0) > turn)
                local hide = (i ~= frame) or blink
                if put or c.hidden[i] ~= hide then
                    pcall(function()
                        if put then
                            -- (where it was: only turned)
                            if lx[i] == wx and ly[i] == wy and lz[i] == wz then
                                q:K2_SetActorRotation({ Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false)
                            else
                                q:K2_TeleportTo({ X = wx, Y = wy, Z = wz }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 })
                            end
                            lx[i], ly[i], lz[i], lyaw[i] = wx, wy, wz, yaw
                            c.spun_at = os.clock()
                        end
                        if c.hidden[i] ~= hide then
                            c.hidden[i] = hide
                            q:SetActorHiddenInGame(hide)
                        end
                    end)
                end
            end
        end
    end

    if c.kind ~= "heart" and (c.fixed or c.t > 0.35) and not c.cool and d2 < 85.0 * 85.0 and abs((pz - OFFSET.Z) - c.z) < 150.0 then
        if collect(c) then c.gone = true end
    end
    if not c.fixed and c.t > (c.life or COIN_LIFE) then c.gone = true end
end

local function update_coins(dt, px, py, pz, cx, cy)
    local sp = 0.0                  -- (his speed along the ground, cm/s: the hearts spin with it)
    pcall(function() local v = lib.pawn():GetVelocity(); sp = sqrt(v.X * v.X + v.Y * v.Y) end)
    for i = #G.coins, 1, -1 do
        local c = G.coins[i]
        -- (a level's own coin far off - over G.LOD_NEAR - every G.LOD_EVERY frames: it only turns there; moving ones and
        -- near ones every frame - G.lod_frame, the goombas')
        local ok, e = true, nil
        c.lod_dt = (c.lod_dt or 0.0) + dt
        local cdx, cdy = (px - OFFSET.X) - c.x, (py - OFFSET.Y) - c.y
        if not c.fixed or not c.quads or cdx * cdx + cdy * cdy < G.LOD_NEAR * G.LOD_NEAR or ((G.lod_frame or 0) + i) % G.LOD_EVERY == 0 then
            ok, e = pcall(update_pickup, c, math.min(c.lod_dt, 0.1), px, py, pz, cx, cy, sp)
            c.lod_dt = 0.0
        end
        if not ok then log("pick-up: %s", tostring(e)); c.gone = true end
        if c.gone then
            for _, q in ipairs(c.quads or {}) do if q then lib.destroy(q) end end
            table.remove(G.coins, i)
        end
    end
    if _G.HEALTH then _G.HEALTH.coins = G.coin_count end
    if G.blue_ticking then pcall(G.blue_tick_check) end
    if #G.triggers > 0 then pcall(update_triggers, px, py, pz) end
end

-- ------------------------------------------------------------ props
-- Things that only stand there (signposts): a model from the exporter, put where the level has it.
-- Mario 64's signpost collision (a box round the post and board, 89 x 135 x 32 units), in the sign's own space:
-- the game's x, y, z as this scene's -z, x, y, at 0.75 cm a unit
local SIGN_COLLISION = (function()
    local v = { { -44, -9, -12 }, { -44, 126, 20 }, { -44, 126, -12 }, { 45, 126, 20 },
                { 45, 126, -12 }, { 45, -9, -12 }, { -44, -9, 20 }, { 45, -9, 20 } }
    local pos = {}
    for _, p in ipairs(v) do
        pos[#pos + 1], pos[#pos + 2], pos[#pos + 3] = -p[3] * 0.75, p[1] * 0.75, p[2] * 0.75
    end
    return { source = "signpost", pos = pos,
             idx = { 0, 1, 2, 2, 1, 3, 2, 3, 4, 5, 0, 2, 5, 2, 4, 6, 3, 1, 0, 6, 1, 7, 4, 3, 6, 7, 3, 7, 5, 4, 5, 7, 6, 5, 6, 0 } }
end)()

function G.add_prop(world, o)
    local data = actor_data(o.actor)
    if not data then return end
    local pos = o.pos
    if o.actor == "signpost" then
        -- Mario 64 drops a sign onto the ground below where the level puts it (DROP_TO_FLOOR, from 200 units
        -- up): one on the castle grounds would float otherwise, and one stood sunk into a slope
        local fz = floor_hit(G.bounds, pos[1], pos[2], pos[3] + 150.0) or floor_z(pos[1], pos[2], pos[3] + 150.0)
        if fz then pos = { pos[1], pos[2], fz } end
    end
    local inst = lib.make_instance(world, data, wpos(pos), o.yaw or 0.0, 1.0)
    if inst then G.extras[#G.extras + 1] = inst.actor end
    if inst and o.actor == "signpost" then
        -- a sign is solid, as Mario 64's is: its collision box (actors/wooden_signpost/collision.inc.c), on the
        -- sign itself so that it turns with it
        local okc, errc = pcall(function()
            local pmc = lib.add_pmc(inst.actor)
            if pmc then lib.add_collision(pmc, { SIGN_COLLISION }) end
        end)
        if not okc then log("sign collision: %s", tostring(errc)) end
    end
end

-- ------------------------------------------------------------ power stars
-- A star turns on the spot where the level has it. Touching it adds it to the save file (each star
-- counts once), refills the power meter and, a moment later, puts the player back in the castle in
-- front of the painting, as getting a star does in Mario 64. The red-coin star stays hidden until all
-- eight red coins of the level have been collected.
G.stars = {}

-- A star already won shows see-through (spawn_star.inc.c bhv_collect_star_init: MODEL_TRANSPARENT_STAR), wherever it
-- is put: the course's stars, the bosses', the red coins' and the secrets'. (They all showed solid, 2026-10-15.)
-- Its key may be any of the course's areas: a star is the course's whichever area it was won in.
function G.star_won(key)
    local MN = _G.MENU
    if not (MN and MN.has_star and key) then return false end
    if MN.has_star(key) then return true end
    local scene, id = tostring(key):match("^(.-):(%d+)$")
    if not scene or scene == "castle" or scene == "key" then return false end
    local course = G.level_of(scene)
    for _, p in ipairs({ course, course .. "_2", course .. "_3", course .. "_4" }) do
        if MN.has_star(p .. ":" .. id) then return true end
    end
    return false
end

-- The red-coin star's place (reds_star_marker.inc.c, spawned by bhv_hidden_red_coin_star_init in every course but
-- Jolly Roger Bay): a see-through star lying flat on the floor, 60 up, half again as big and turning 0x100 a frame,
-- left there when the star itself comes out. (There was none, 2026-10-15.)
function G.add_red_marker(world, o)
    if G.level_of(G.name) == "jrb" then return end
    local data = actor_data("transparent_star")
    if not data then return end
    local x, y = o.pos[1], o.pos[2]
    local fz = floor_z(x, y, o.pos[3] + 100.0)
    if not fz then return end
    local inst = lib.make_instance(world, data, wpos({ x, y, fz + 60.0 * 0.75 }), 0.0, 1.0)
    if not inst then return end
    inst.moves = true
    pcall(function() inst.actor:SetActorScale3D({ X = 0.75, Y = 1.5, Z = 1.5 }) end)
    G.stars[#G.stars + 1] = { inst = inst, x = x, y = y, z = fz + 60.0 * 0.75, marker = true, t = 0.0 }
end

-- Stars out of the athlete's reach where Mario 64 reaches them with a jump higher than his: { scene = { [star index] =
-- cm over the floor under it } - put that high, a jump up to it as the 100-coin star's 260. He takes one within 236 cm
-- over his feet standing, some 295 jumping (update_stars). Rainbow Ride's "Swingin' in the Breeze" star 312 over its
-- ledge, its red coin star 287 (2026-10-29).
G.STAR_DROP = { rr = { [2] = 260.0, [3] = 260.0 } }
function G.add_star(world, o, hidden)
    local key = o.key or (tostring(G.name) .. ":" .. tostring(o.id or 0))
    local model = o.model or (G.star_won(key) and "transparent_star" or nil)
    local data = actor_data(model or "star")
    if not data then return nil end
    local x, y, z = o.pos[1], o.pos[2], o.pos[3]
    local drop = G.STAR_DROP[G.name or ""] and o.id and G.STAR_DROP[G.name][o.id]
    if drop and not o.from then
        local fz = G.floor_z(x, y, z)
        if fz and z - fz > drop and z - fz < 450.0 then z = fz + drop end
    end
    local inst = lib.make_instance(world, data, wpos({ x, y, z }), 0.0, 1.0)
    if not inst then return nil end
    inst.moves = true
    local s = { inst = inst, x = x, y = y, z = z, key = key, hidden = hidden and true or false, t = 0.0,
                noexit = o.noexit, keyn = o.keyn }
    if hidden then pcall(function() inst.actor:SetActorHiddenInGame(true) end) end
    if o.from then
        -- (spawn_default_star: out of the boss, or whatever gives it, and over to its place: fly_star)
        local f = o.from
        s.fly = { style = "coords", phase = 0, x0 = f[1], y0 = f[2], z0 = f[3], x1 = x, y1 = y, z1 = z }
        s.x, s.y, s.z = f[1], f[2], f[3]
    end
    G.stars[#G.stars + 1] = s
    return s
end

-- The 100-coin star (interaction.c interact_coin -> bhv_spawn_star_no_level_exit(STAR_INDEX_100_COINS)): in one of
-- the fifteen courses, the coin that makes 100 brings the course's seventh star out over him (250 up from Mario,
-- spawn_star.inc.c set_home_to_mario), see-through if it is won already; taking it leaves him in the course.
-- There was none (2026-10-15).
function G.hundred_coin_star()
    local data = lib.load_data("data.starselect")
    local level = G.level_of(G.name)
    if not (data and data.courses and data.courses[level]) then return end
    local world, pawn = lib.world(), lib.pawn()
    if not (world and pawn) then return end
    local l = pawn:K2_GetActorLocation()
    local key = tostring(G.name) .. ":6"
    local MN = _G.MENU
    local won = MN and MN.has_star and MN.has_star(key)
    -- (a jump up to it, as Mario has to: put in his reach it was taken the moment it came, 2026-10-15)
    local s = G.add_star(world, { pos = { l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - 90.0 + 260.0 }, id = 6,
                                  noexit = true, model = won and "transparent_star" or nil })
    if s then
        s.fly = { phase = 1, x0 = s.x, y0 = s.y, x1 = s.x, y1 = s.y, z1 = s.z }
        sfx("star_appears")
        G.star_cutscene(s)                  -- (CUTSCENE_STAR_SPAWN)
        log("100 coins: the star has appeared%s", won and " (won already)" or "")
    end
end

-- A star given in the castle (bhv_spawn_star_no_level_exit, from a Toad with TOAD_STAR_n or from Mips): out of its
-- giver and over to 250 above Mario (set_home_to_mario), taken without leaving. The castle's own five stars (Mario
-- 64's COURSE_NONE: the Toads' 0-2, Mips' 3-4) are kept as "castle:<n>"; the pause screen counts them with the
-- secret stars. (There were none, 2026-10-15.)
-- Mario 64's horizontal wind (mario_step.c mario_update_windy_ground, mario_actions_airborne.c's windy floors): over
-- a floor of it - BitS's windy stretch, RR's, SL's and THI's - he is pushed its way (each triangle's force << 8):
-- on it 3.2 to 6.2 a frame standing (4.7 here), off it in the air ever faster, 1.2 a frame more each frame up to 32.
-- Moved as the conveyors move him (platforms.lua): a small step each tick. (Those floors were holes, 2026-10-15.)
-- (none at all in these scenes)
G.NO_FLOOR_WIND = {}
-- In these, a wind floor throws him limp and carries his body off its way, as a gust would - { speed, up: cm/s, again: s
-- on his feet before it can again }. Snowman's Land's windy channel only shoved him along it, nothing to be seen there,
-- and looked like sliding: "random sliding here", "well if theres wind here we have to fix it", "is there a way to
-- ragdoll the charater sending him flying in the direction the wind blows", 2026-10-26. The wind heard while he is on it.
G.WIND_RAGDOLL = { sl = { speed = 900.0, up = 450.0, again = 1.0 } }
-- (elsewhere, on his feet: this share of Mario 64's push, and only while he moves faster than `min` cm/s; in the air,
-- Mario 64's own)
G.WIND_GROUND = { k = 0.5, min = 60.0 }
G.wind_v = nil
function G.apply_wind(dt, pawn, grounded)
    local d = G.wind_dir
    if not d or G.carried or G.swim or G.NO_FLOOR_WIND[G.name or ""] then G.wind_v = nil; return end
    local a = (d * 256) * math.pi / 32768.0
    local sx, sz = math.sin(a), math.cos(a)                 -- (Mario 64's x and z)
    local wr = G.WIND_RAGDOLL[G.name or ""]
    if wr then
        local wx, wy = -sz, sx                              -- (its way in the scene: Mario 64's x, z are its y, -x)
        local SFXm = package.loaded["sfx"]
        if SFXm and SFXm.hold then pcall(SFXm.hold, "loop_wind", 0.7) end
        local limp = false
        pcall(function() limp = pawn.CharacterMovement.MovementMode == 0 end)
        if limp then
            -- (carried off: his body kept at the wind's speed its way, gaining up to three times that a second)
            pcall(function()
                local v = pawn.Mesh:GetPhysicsLinearVelocity(FName("pelvis"))
                local along = v.X * wx + v.Y * wy
                if along < wr.speed then
                    local dv = math.min(wr.speed - along, wr.speed * 3.0 * dt)
                    pawn.Mesh:AddImpulseToAllBodiesBelow({ X = wx * dv, Y = wy * dv, Z = 0.0 }, FName("pelvis"), true, true)
                end
            end)
            G.wind_hit = os.clock()
        elseif os.clock() - (G.wind_hit or 0.0) > wr.again then
            G.wind_hit = os.clock()
            G.knock_down(pawn, wx * wr.speed, wy * wr.speed, wr.up, true)
            sfx("mario_waaaooow")
            log("blown off his feet by the wind")
        end
        return
    end
    local vx, vz
    if grounded then
        G.wind_v = nil
        -- (on his feet: a little drift its way while he walks, none standing still - shoved along at Mario 64's 4.7 a
        -- frame he was seen to slide on the spot: "player sliding in wind?", then "should be able to walk in it but it
        -- pushing the player to the right a bit", 2026-10-29)
        local sp = 0.0
        pcall(function() local v = pawn:GetVelocity(); sp = math.sqrt(v.X * v.X + v.Y * v.Y) end)
        if sp < G.WIND_GROUND.min then return end
        vx, vz = G.WIND_GROUND.k * 4.7 * sx, G.WIND_GROUND.k * 4.7 * sz
    else
        local v = G.wind_v or { 0.0, 0.0 }
        v[1], v[2] = v[1] + 1.2 * sx * 30.0 * dt, v[2] + 1.2 * sz * 30.0 * dt
        local sp = math.sqrt(v[1] * v[1] + v[2] * v[2])
        if sp > 32.0 then v[1], v[2] = v[1] * 32.0 / sp, v[2] * 32.0 / sp end
        G.wind_v = v
        vx, vz = v[1], v[2]
    end
    local k = 30.0 * dt * 0.75                              -- (Mario units a frame -> scene cm this tick)
    -- (moved, not teleported: a teleport each tick started STORROR's locomotion afresh each time, and walking in the wind
    -- he was seen gliding in his standing pose, "players sliding not walking", 2026-10-29. Not swept either: along the
    -- huge island's windy slope the sweep met the ground and he was not moved at all, "player nmot being pushed" - kept
    -- off the walls here instead: no step that would put him within his capsule's reach of one.)
    pcall(function()
        local l = pawn:K2_GetActorLocation()
        local nx, ny = l.X - vz * k, l.Y + vx * k
        if G.wall_near and G.wall_near(nx - OFFSET.X, ny - OFFSET.Y, l.Z - OFFSET.Z, 40.0, 60.0) then return end
        pawn:K2_SetActorLocation({ X = nx, Y = ny, Z = l.Z }, false, {}, false)
    end)
end

-- vertical wind (mario_step.c apply_vertical_wind): over the wind floor at the bottom of a chasm - Tall, Tall
-- Mountain's sides, Tiny-Huge Island's pits, Cool, Cool Mountain's - and in the air between 3000 under Mario 64's -1500
-- and 2000 over it, he is blown up: to 50 a frame low down, 10000 / (height + 200) higher, gaining an eighth of that a
-- frame - near the bottom it carries him up, higher it only slows his fall. (It was taken for the death plane alone.)
local VWIND_SOUND_GAP = 1.0
-- (steered in it: STORROR's athlete has no say in the air at all - its AirControl is 0 - and the updraft holds him up for
-- seconds, carried off the mountain whatever he did: "need to be able to control player in wind", Tall, Tall Mountain,
-- 2026-10-26. The stick, or the movement keys, moves him the way the camera looks, as Mario 64's freefall steers him:
-- gaining this a second (cm/s/s), up to this fast (cm/s) - no faster than he came in; let go, he keeps his way.)
G.VWIND_STEER = { acc = 1400.0, max = 450.0 }
-- (a vertical wind's floor under (x, y) from z, nothing of the level's between: its height, or nil - ragdoll.lua's
-- updraft, which blows his limp body up out of it)
function G.vwind_under(x, y, z)
    if not (G.vwind_rule or G.rule) then return nil end
    local rz, T = floor_hit(G.vwind_rule or G.rule, x, y, z)
    if not (T and T[11] == "vwind") then return nil end
    local fz = floor_z(x, y, z)
    if fz and fz > rz + 5.0 then return nil end
    return rz
end
-- (in a vertical wind's column or by it - up to 3 m off its floor's edge, nothing under him: the shaft over the tiny
-- island's pit is wider than its wind's floor, and down its side he went on through, 2026-10-29 - the wind's floor's
-- height, or nil)
function G.vwind_near(x, y, z)
    local wz = G.vwind_under(x, y, z)
    if wz then return wz end
    local fz = floor_z(x, y, z)
    for _, r in ipairs({ 150.0, 300.0 }) do
        for k = 0, 7 do
            local a = k * math.pi / 4.0
            local w = G.vwind_under(x + math.cos(a) * r, y + math.sin(a) * r, z)
            if w and not (fz and fz > w + 5.0) then return w end
        end
    end
    return nil
end
-- (the nearest ground round a vertical wind's column from (x, y, z) - its floor at wz: { x, y, z } or nil. Ground: a
-- floor of the level's over the wind's floor, no column of it there)
-- (`up`: ground no more than that over z - 25 m when not given)
function G.vwind_goal(x, y, z, wz, up)
    local best, first = nil, nil
    for r = 150.0, 1800.0, 75.0 do
        if first and r > first + 300.0 then break end
        for k = 0, 23 do
            local a = k * math.pi / 12.0
            local gx, gy = x + math.cos(a) * r, y + math.sin(a) * r
            local gz = floor_z(gx, gy, z + (up or 2500.0))
            if gz and gz > wz + 300.0 and not G.vwind_under(gx, gy, gz + 50.0) then
                -- (and well onto it, 1.5 m on the same way, about as high: set down at the column's very edge - the tiny
                -- island's pit's north lip - he hung over the wind and bobbed there, 2026-10-29)
                local hx, hy = x + math.cos(a) * (r + 150.0), y + math.sin(a) * (r + 150.0)
                local hz = floor_z(hx, hy, gz + 100.0)
                -- (and flat there: set down on the pit's 27-degree side, he slid back across it and off the island,
                -- 2026-10-29 - within 12 cm half a metre round, about 13 degrees)
                local flat = hz ~= nil
                if flat then
                    for q = 0, 3 do
                        local b = q * math.pi / 2.0
                        local fz2 = floor_z(hx + math.cos(b) * 50.0, hy + math.sin(b) * 50.0, hz + 60.0)
                        if not (fz2 and math.abs(fz2 - hz) < 12.0) then flat = false; break end
                    end
                end
                if flat and math.abs(hz - gz) < 60.0 and not G.vwind_under(hx, hy, hz + 50.0) then
                    first = first or r
                    -- (the highest within 3 m of the nearest: out over the top, not onto a step down inside it - the
                    -- tiny island's pit has one 4.4 m under its rim, and he slid back in from it)
                    if not best or hz > best[3] + 30.0 then best = { hx, hy, hz } end
                end
            end
        end
    end
    return best
end
-- Down in the column - under the ground round it - he is lifted back up to hover a little over that ground, and steers
-- himself out as he likes: Mario 64's wind, weak at the mouth of the tiny island's pit and strong only far down, let him
-- fall on through it and out of the level ("Yes, fix it", 2026-10-29). (Set down out of it for him at first - "the player
-- should be able to control themselves in the updraft why is it auto placing the player?", 2026-10-29: only lifted now.)
-- Over that height, Mario 64's wind as before; his steering always. (Limp, ragdoll.lua lifts his body and stands him up.)
G.VWIND_LIFT = { over = 180.0, rise = 900.0, acc = 3000.0, drag = 250.0 }
-- (one star's wind reaching less high - in that course and star only (G.vwind_star), the rest as above and below: over
-- `top` (scene cm, his feet) neither Mario 64's push nor the lift down its column takes him. Optional too: `k` of Mario
-- 64's push and its top speed, `grav` cm/s/s less push; down its column, lifted to ground no more than `up` cm over him
-- as he comes over it and no higher than `from_peak` cm under the top of the jump or drop that brought him there.
-- Tall, Tall Mountain's 7th star, the ghost race: lifted to 1.8 m over the ledge by its column, -350, it reaches -1300
-- now (-700, then "lower" three times), its push as it was - "make this wind not push you as high", "these changes are for this star only", "just make
-- the wind not reach as high", 2026-11-07)
-- (an entry with no `star`: every star of that scene - Tiny-Huge Island's huge island, its updraft eased to -1350, the
-- height its column's lift holds him at (180 over the ground round it, -1535): Mario 64's carried him to -650 or so, 9 m
-- over that ground - "the updraft im currently on needs lowered for all stars", 2026-11-07)
G.VWIND_STAR = { ttm = { star = 7, top = -1300.0 }, thi = { top = -1350.0 } }
function G.vwind_star()
    local s = G.VWIND_STAR and G.VWIND_STAR[G.name]
    if not s then return nil end
    if not s.star then return s end
    local ca = G.course_act
    if ca and ca.course == G.name and ca.act == s.star then return s end
    return nil
end
-- (a level's vertical wind moved, its floor - its column, its lift and its puffs with it - { dx, dy } scene cm: Cool,
-- Cool Mountain's out into the open drop, off the little ledge by its column that its race's fourth flag stands on - by
-- it on the way down, the wind had him: "I think its the wind doing that shit move the wind further out", 2026-11-05)
G.VWIND_MOVE = {}                -- (ccm = { -900.0, 0.0 } for a while: put back where Mario 64 has it - "put the wind back", 2026-11-05)
function G.vwind_lift(dt, pawn, feet)
    local l = pawn:K2_GetActorLocation()
    local x, y = l.X - OFFSET.X, l.Y - OFFSET.Y
    -- (the ground's height chosen once for the whole of a fall, till he is down on something - G.vgoal's time is his
    -- last frame in the air)
    local vg = G.vgoal
    if vg and os.clock() - vg.t > 0.5 then vg = nil; G.vgoal = nil end
    if not vg then
        local wz = G.vwind_near(x, y, feet + 60.0)
        if not wz then return false end
        -- (in one star's - G.VWIND_STAR - ground no more than `up` over him as he comes over the column, and no higher
        -- than `from_peak` under the top of the jump or drop that brought him there)
        local S = G.vwind_star and G.vwind_star()
        local goal = G.vwind_goal(x, y, feet, wz, S and S.up)
        if not goal then return false end
        local pk = S and S.from_peak and G.air and G.peak
        if pk then
            local cap = pk - OFFSET.Z - (G.half or 90.0) - S.from_peak
            if cap < goal[3] and cap > wz + 300.0 then goal = { goal[1], goal[2], cap } end
        end
        vg = { goal = goal, t = os.clock() }
        G.vgoal = vg
    end
    vg.t = os.clock()
    local g, O = vg.goal, G.VWIND_LIFT
    -- (only once he has fallen in, under that ground: a jump over the column, or from ledge to ledge over Tall, Tall
    -- Mountain's, has Mario 64's wind alone)
    if feet < g[3] - 50.0 and not vg.down then
        vg.down = true
        log("vertical wind: down its column - lifted to %.0f cm over the ground round it (%.0f)", O.over, g[3])
    end
    if not vg.down then return false end
    local cm = pawn.CharacterMovement
    local v = cm.Velocity
    local function approach(a, b, s) if a < b then return math.min(b, a + s) end return math.max(b, a - s) end
    local aim = g[3] + O.over
    local S = G.vwind_star and G.vwind_star()
    if S and S.top and aim > S.top then aim = S.top end      -- (one star's reaching less high: G.VWIND_STAR)
    local want = math.max(-200.0, math.min(O.rise, (aim - feet) * 2.0))
    -- (and a light drag across, as Mario 64's in the air: what he came in with dies away, his steering is his own)
    cm.Velocity = { X = approach(v.X, 0.0, O.drag * dt), Y = approach(v.Y, 0.0, O.drag * dt), Z = approach(v.Z, want, (O.acc + 980.0) * dt) }
    return true
end
-- (`near`: by its column, not over its own floor - the tiny island's shaft is wider than its wind's floor, G.vwind_near)
function G.apply_vwind(dt, pawn, feet, near)
    if G.carried or G.swim or G.star_cut or G.cutscene or (FLIGHT and FLIGHT.active and FLIGHT.active()) then return end
    if PLAT and PLAT.in_cannon ~= nil then return end
    if near then
        local l = pawn:K2_GetActorLocation()
        if not G.vwind_near(l.X - OFFSET.X, l.Y - OFFSET.Y, feet + 60.0) then return end
    end
    -- (one star's reaching less high - G.VWIND_STAR: over its `top` no push, only his own steering)
    local S = G.vwind_star and G.vwind_star()
    local over_top = S and S.top and feet > S.top
    local okl, lifted = false, false
    if not over_top then okl, lifted = pcall(G.vwind_lift, dt, pawn, feet) end
    lifted = okl and lifted
    local off = feet / 0.75 + 1500.0
    if not lifted and not over_top and S and S.top then
        -- (one star's reaching less high: under its `top` eased up to it and held there, as the lift down a column holds
        -- him - Mario 64's push, cut off at it, threw him far over it and he dropped back fast: "players being lifted very
        -- high then low very fast", 2026-11-07)
        pcall(function()
            local cm = pawn.CharacterMovement
            local v = cm.Velocity
            local want = math.max(-200.0, math.min(G.VWIND_LIFT.rise, (S.top - feet) * 2.0))
            local step = (G.VWIND_LIFT.acc + 1500.0) * dt
            local z = v.Z
            if z < want then z = math.min(want, z + step) else z = math.max(want, z - step) end
            cm.Velocity = { X = v.X, Y = v.Y, Z = z }
        end)
    elseif not lifted and not over_top then
        if off <= -3000.0 or off >= 2000.0 then return end
        local maxv = (off >= 0.0) and (10000.0 / (off + 200.0)) or 50.0
        local P = G.vwind_star and G.vwind_star()          -- (one star's gentler: G.VWIND_STAR)
        local k, less = (P and P.k) or 1.0, (P and P.grav) or 0.0
        local top = maxv * 0.75 * 30.0 * k                  -- (Mario units a frame -> scene cm a second)
        pcall(function()
            local cm = pawn.CharacterMovement
            local v = cm.Velocity
            if v.Z < top then
                -- (an eighth of it a frame, 30 frames a second, in scene cm)
                local push = math.max(0.0, maxv / 8.0 * 30.0 * 0.75 * 30.0 * k - less)
                cm.Velocity = { X = v.X, Y = v.Y, Z = math.min(top, v.Z + push * dt) }
            end
        end)
    end
    pcall(function()
        local pc = lib.controller()
        local sx = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftX") }) or 0.0
        local sy = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftY") }) or 0.0
        if abs(sx) < 0.2 then sx = 0.0 end
        if abs(sy) < 0.2 then sy = 0.0 end
        if pc:IsInputKeyDown({ KeyName = FName("D") }) then sx = 1.0 elseif pc:IsInputKeyDown({ KeyName = FName("A") }) then sx = -1.0 end
        if pc:IsInputKeyDown({ KeyName = FName("W") }) then sy = 1.0 elseif pc:IsInputKeyDown({ KeyName = FName("S") }) then sy = -1.0 end
        if sx == 0.0 and sy == 0.0 then return end
        local yaw = math.rad(pc:GetControlRotation().Yaw)
        local dx = math.cos(yaw) * sy - math.sin(yaw) * sx                   -- (forward (cos, sin), right (-sin, cos))
        local dy = math.sin(yaw) * sy + math.cos(yaw) * sx
        local cm = pawn.CharacterMovement
        local v = cm.Velocity
        local was = sqrt(v.X * v.X + v.Y * v.Y)
        local vx, vy = v.X + dx * G.VWIND_STEER.acc * dt, v.Y + dy * G.VWIND_STEER.acc * dt
        local hs = sqrt(vx * vx + vy * vy)
        local cap = math.max(G.VWIND_STEER.max, was)
        if hs > cap then vx, vy = vx * cap / hs, vy * cap / hs end
        cm.Velocity = { X = vx, Y = vy, Z = v.Z }
    end)
    local now = os.clock()
    if now - (G.vwind_snd or 0.0) > VWIND_SOUND_GAP then G.vwind_snd = now; sfx("wind_up", 0.6) end
end

-- moving quicksand (mario_step.c mario_update_moving_sand): standing in it he is carried its way - force's low byte
-- the direction >> 8, its high byte which of 12, 8, 4 or 0 a frame (sMovingSandSpeeds) - SSL's sand streams, toward
-- their pits. Moved as the wind moves him.
local SAND_SPEED = { [0] = 12.0, 8.0, 4.0, 0.0 }
function G.apply_sand(dt, pawn)
    if G.dying or (QSAND and QSAND.dying and QSAND.dying()) then return end      -- (going under: held where he went in)
    local pc = G.pit_pull
    if pc and not G.carried and not G.swim then
        -- (set down on the sand where it carries him, not lifted over it: lifted, he was falling all the while, in
        -- STORROR's falling pose, and skated down into the pit - "still sliding on vortex sand pits", 2026-10-23)
        pcall(function()
            local l = pawn:K2_GetActorLocation()
            local dx, dy = pc[1] + OFFSET.X - l.X, pc[2] + OFFSET.Y - l.Y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < 1.0 then return end
            local k = math.min(d, G.PIT_PULL * dt)
            local nx, ny = l.X + dx / d * k, l.Y + dy / d * k
            local half = (G.half or 86.0)
            local fz = G.floor_z(nx - OFFSET.X, ny - OFFSET.Y, l.Z - OFFSET.Z - half + 50.0)
            local nz = fz and (fz + half + 2.0 + OFFSET.Z) or l.Z
            pawn:K2_SetActorLocation({ X = nx, Y = ny, Z = nz }, false, {}, true)
        end)
        return
    end
    local f = G.sand_push
    if not f or G.carried or G.swim then return end
    local speed = SAND_SPEED[(f >> 8) & 3] or 0.0
    if speed <= 0.0 then return end
    local a = ((f & 0xFF) * 256) * math.pi / 32768.0
    local k = speed * 30.0 * dt * 0.75
    pcall(function()
        -- (slid along at his own height, swept - a wall stops it - his own walking keeping him on the sand: not
        -- teleported 2 cm up each frame (STORROR had him falling every frame, and walking on it stuttered and slid -
        -- "also very buggy to walk on"), nor set down where the floor was looked up (where the look missed the sand it
        -- stopped, and unswept it held him: "stops moving the player in random areas also player gets stuck trying to
        -- move in it", 2026-11-07))
        local l = pawn:K2_GetActorLocation()
        pawn:K2_SetActorLocation({ X = l.X - math.cos(a) * k, Y = l.Y + math.sin(a) * k, Z = l.Z }, true, {}, false)
    end)
end

-- Princess's Secret Slide's clock (interaction.c pss_begin_slide / pss_end_slide): onto the slide's first floor it
-- starts and shows on the HUD (once a visit: it stays shown after); onto its last floor it stops, and under 21 seconds
-- (630 frames) act 2's star comes out of him and flies down to (-6358, -4300, 4700) (spawn_default_star). Paused
-- time does not count (G.pss.t is the tick's own time). (Not built: that star could not be had, 2026-10-15.)
G.pss = nil
function G.pss_floor(tag)
    local HP = _G.HEALTH
    if tag == "timer_start" then
        if not G.pss then G.pss = { t = 0.0, running = true }; log("PSS: the clock starts") end
        return
    end
    local c = G.pss
    if not (c and c.running) then return end
    c.running = false
    if HP then HP.clock = c.t end
    log("PSS: the clock stops at %.2f s", c.t)
    -- (Mario 64's 21 seconds - 630 frames - made 27 for the athlete: "next make the secret star spawn un 27 seconds",
    -- 2026-10-17)
    if c.t >= 27.0 then return end
    local world, pawn = lib.world(), lib.pawn()
    if not (world and pawn) then return end
    local l = pawn:K2_GetActorLocation()
    local key = "pss:1"
    local MN = _G.MENU
    local won = MN and MN.has_star and MN.has_star(key)
    local ax, ay, az = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z
    local s = G.add_star(world, { pos = { ax, ay, az }, key = key, model = won and "transparent_star" or nil })
    if not s then return end
    s.fly = { style = "coords", phase = 1, n = 0, x0 = ax, y0 = ay, z0 = az,
              x1 = -4700.0 * 0.75, y1 = -6358.0 * 0.75, z1 = -4300.0 * 0.75 }
    log("PSS: under 27 seconds - its star")
end

function G.gift_star(n, from)
    local world, pawn = lib.world(), lib.pawn()
    if not (world and pawn) then return nil end
    local l = pawn:K2_GetActorLocation()
    local hx, hy, hz = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - 90.0 + 260.0
    local key = "castle:" .. tostring(n)
    local MN = _G.MENU
    local won = MN and MN.has_star and MN.has_star(key)
    local s = G.add_star(world, { pos = { from[1], from[2], hz }, key = key, noexit = true,
                                  model = won and "transparent_star" or nil })
    if not s then return nil end
    s.fly = { phase = 1, x0 = from[1], y0 = from[2], x1 = hx, y1 = hy, z1 = hz }
    sfx("star_appears")
    log("star %s given", key)
    return s
end

function G.on_red_coin(n)
    if n >= 8 and G.red_star and G.red_star.hidden then
        G.reveal_star(G.red_star)
        log("all eight red coins: the star has appeared")
    end
end

-- A star coming out (sparkle_spawn_star.inc.c bhv_spawned_star_loop), at Mario 64's 30 frames a second: up at 50 and
-- 4 a frame slower, over to its place in some 25 frames; then its jingle, up again at 20 slowing 1 a frame, down no
-- faster than 4 until it is back at its place, where it can be taken.
-- A boss's star, a red-coin star (spawn_star.inc.c bhv_star_spawn_loop): turning where it came out for 20 frames, over
-- to its place in 30 on an arc 400 high, then its jingle, up a little and down onto its place.
local function fly_star(s, dt)
    local f = s.fly
    -- (sparkles behind it as it flies: bhv_spawned_star's bhvSparkleSpawn)
    if ENVFX and ENVFX.sparkle then
        f.spark = (f.spark or 0.0) + dt
        if f.spark >= 0.06 then f.spark = 0.0; pcall(ENVFX.sparkle, s.x, s.y, s.z, 1) end
    end
    f.acc = (f.acc or 0.0) + dt * 30.0
    while s.fly and f.acc >= 1.0 do
        f.acc = f.acc - 1.0
        f.n = (f.n or 0) + 1
        if f.style == "coords" then
            if f.phase == 0 then
                if f.n >= 20 then f.phase, f.n = 1, 0 end
            elseif f.phase == 1 then
                local k = math.min(1.0, f.n / 30.0)
                s.x, s.y = f.x0 + (f.x1 - f.x0) * k, f.y0 + (f.y1 - f.y0) * k
                s.z = f.z0 + (f.z1 - f.z0) * k + math.sin(k * math.pi) * 400.0 * 0.75
                if f.n >= 30 then
                    f.phase, f.n = 2, 0
                    sfx("star_spawn_jingle")
                    if MUSIC and MUSIC.dip then pcall(MUSIC.dip, 4.2) end
                end
            else
                s.z = s.z + ((f.n < 20) and (20 - f.n) or -10.0) * 0.75
                if f.n >= 20 and s.z <= f.z1 then
                    s.z, s.fly = f.z1, nil
                    sfx("star_appears")
                end
            end
        elseif f.phase == 1 then
            f.vz = (f.vz or 50.0) - 4.0
            local k = math.min(1.0, f.n / 23.0)
            s.x, s.y = f.x0 + (f.x1 - f.x0) * k, f.y0 + (f.y1 - f.y0) * k
            s.z = s.z + f.vz * 0.75
            if f.vz < 0.0 and s.z < f.z1 then
                f.phase, f.vz = 2, 20.0
                sfx("star_spawn_jingle")                    -- (play_power_star_jingle: the tune turned down under it)
                if MUSIC and MUSIC.dip then pcall(MUSIC.dip, 4.2) end
            end
        else
            f.vz = math.max(f.vz, -4.0) - 1.0
            s.z = s.z + f.vz * 0.75
            if f.vz < 0.0 and s.z < f.z1 then s.z = f.z1; s.fly = nil end
        end
    end
end

-- A star coming out, seen as Mario 64 shows it (camera.c CUTSCENE_RED_COIN_STAR_SPAWN for the red coins' and the
-- secrets' stars, CUTSCENE_STAR_SPAWN for the 100-coin star; "you have to add the cutscenes in for red coin 100 coin
-- and the 5 coins in the sky", 2026-10-16 - they came out unseen, often far off): time stops for him, the camera goes
-- to the star and watches it come out and settle, a moment more, then back to him. He is held where he is (flying:
-- the flight paused) and nothing touches him meanwhile (G.intangible).
local STAR_CUT_BACK, STAR_CUT_UP = 800.0, 300.0     -- cm from the star toward him, and above it
local STAR_CUT_MAX = 7.0                            -- s at most
local function star_cut_place(c)
    local st = c.star
    local dx, dy, dz = st.x - c.cx, st.y - c.cy, st.z - c.cz
    local rot = { Pitch = deg(atan(dz, sqrt(dx * dx + dy * dy))), Yaw = deg(atan(dy, dx)), Roll = 0.0 }
    pcall(function() c.cam:K2_TeleportTo({ X = c.cx + OFFSET.X, Y = c.cy + OFFSET.Y, Z = c.cz + OFFSET.Z }, rot) end)
end
function G.star_cutscene(st)
    if G.star_cut or not st or G.dying or G.warping or G.pending then return end
    local world, pc, pawn = lib.world(), lib.controller(), lib.pawn()
    if not (world and pc and pawn) then return end
    local l = pawn:K2_GetActorLocation()
    local dx, dy = l.X - OFFSET.X - st.x, l.Y - OFFSET.Y - st.y
    local d = sqrt(dx * dx + dy * dy)
    if d < 1.0 then dx, dy, d = 1.0, 0.0, 1.0 end
    local cam = lib.camera(world, "star_cut")
    if not cam then return end
    local c = { star = st, t = 0.0, pc = pc, world = world:GetAddress(), cam = cam,
                cx = st.x + dx / d * STAR_CUT_BACK, cy = st.y + dy / d * STAR_CUT_BACK, cz = st.z + STAR_CUT_UP }
    star_cut_place(c)
    -- (time stops for him: held where he is)
    if FLIGHT and FLIGHT.active and FLIGHT.active() and FLIGHT.pause then
        c.flying = true
        pcall(FLIGHT.pause, true)
    else
        pcall(function()
            local cm = pawn.CharacterMovement
            c.mode = cm.MovementMode
            cm:StopMovementImmediately()
            cm:SetMovementMode(0, 0)
        end)
    end
    pcall(function()
        if not pc:IsMoveInputIgnored() then pc:SetIgnoreMoveInput(true); c.locked = true end
        pawn:DisableInput(pc)
    end)
    G.star_cut = c
    pcall(function() pc:SetViewTargetWithBlend(cam, 0.6, 4, 2.0, false) end)
    log("star cutscene")
end
local function star_cut_end(c, here)
    G.star_cut = nil
    if not here then return end
    local pawn = lib.pawn()
    if c.flying then
        if FLIGHT and FLIGHT.pause then pcall(FLIGHT.pause, false) end
    elseif pawn then
        -- (flying mode put back only to what still holds him so - the swim, a pole, Hoot: otherwise falling. Let go of a
        -- pole in it, he was left floating in the air, 2026-10-23)
        local mode = c.mode or 3
        if mode == 5 and not (G.swim or G.carried) then mode = 3 end
        if mode == 0 then mode = 3 end
        pcall(function() pawn.CharacterMovement:SetMovementMode(mode, 0) end)
    end
    pcall(function()
        if c.locked and c.pc:IsMoveInputIgnored() then c.pc:SetIgnoreMoveInput(false) end
        if pawn then
            pawn:EnableInput(c.pc)
            c.pc:SetViewTargetWithBlend(pawn, 0.6, 4, 2.0, false)
        end
    end)
end
local function star_cut_tick(dt)
    local c = G.star_cut
    if not c then return end
    local w = lib.world()
    local here = w and w:GetAddress() == c.world
    if not here or G.dying or G.warping then star_cut_end(c, here); return end
    c.t = c.t + dt
    star_cut_place(c)
    if not c.flying then
        pcall(function() local cm = lib.pawn().CharacterMovement; if cm.MovementMode ~= 0 then cm:SetMovementMode(0, 0) end end)
    end
    if not c.star.fly then c.done = (c.done or 0.0) + dt end
    if (c.done or 0.0) > 1.0 or c.t > STAR_CUT_MAX then star_cut_end(c, true) end
end
-- (a hidden star shown: up out of its own place and back down onto it - spawn_red_coin_cutscene_star - and watched)
function G.reveal_star(st)
    st.hidden = false
    pcall(function() st.inst.actor:SetActorHiddenInGame(false) end)
    st.fly = { style = "coords", phase = 0, x0 = st.x, y0 = st.y, z0 = st.z, x1 = st.x, y1 = st.y, z1 = st.z }
    G.star_cutscene(st)
end

-- Talked to by someone with a cutscene of it (camera.c CUTSCENE_DIALOG, cutscene_dialog_start /
-- _move_mario_shoulder; King Bob-omb's challenge and last words - "next the king bombomb cutscene", 2026-10-16): the
-- camera comes round over his shoulder - behind him, turned 0x6000 (135 degrees) from the way to the speaker on the side
-- it was already, 180 units off his head (125 over his feet), up or down by the difference in their heights - and
-- looks mostly at him, a little toward the speaker (whose head is its top + 200). Time is stopped by the message itself
-- (dialog.lua); back to him when it shuts, unless a star's cutscene has taken over. (x, y, z): the speaker's feet,
-- scene cm (no OFFSET); h: its hitbox height, cm.
local DLG_SCALE = 1.5                           -- the athlete against Mario's size
-- (the ending's scenes - Peach's, the credits: he walks about in them, but nothing there speaks to him or takes the
-- camera - the racing penguin's question came up over the credits and stopped them: "the player is interacting with
-- shit in the outra such as the penguin which breaks the ending credits", 2026-11-02. G.say, G.ask, G.dialog_cut)
function G.ending_on()
    local EN = package.loaded["ending"]
    return EN ~= nil and EN.active == true
end
function G.dialog_cut(x, y, z, h, r)
    if G.dialog_cam or G.star_cut or G.dying or G.warping or G.ending_on() then return end
    local world, pc, pawn = lib.world(), lib.controller(), lib.pawn()
    if not (world and pc and pawn) then return end
    local l = pawn:K2_GetActorLocation()
    local feet = l.Z - OFFSET.Z - (G.half or 90.0)
    local ax, ay, az = l.X - OFFSET.X, l.Y - OFFSET.Y, feet + 125.0 * 0.75 * DLG_SCALE
    -- (its head: no more than 3 m up - the Whomp King, 6.5 m tall, had the camera looking steeply up from his knees)
    local bx, by, bz = x, y, z + math.min(h or 75.0, 300.0) + 200.0 * 0.75
    local to_b = atan(by - ay, bx - ax)
    local cl = pc.PlayerCameraManager:GetCameraLocation()
    local to_cam = atan(cl.Y - OFFSET.Y - ay, cl.X - OFFSET.X - ax)
    local side = (((to_cam - to_b + 3.0 * math.pi) % (2.0 * math.pi)) - math.pi) < 0.0 and -1.0 or 1.0
    local db = sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    -- (a big speaker - King Bob-omb, 3 m to the athlete's 1.8 - "the king bomb omb dialog camera is cooked", 2026-10-16:
    -- Mario 64's 180 units at his shoulder put the camera at the athlete's chest, his back filling the picture and the
    -- King behind it, over the summit's edge: further off by the speaker's size, above his head, looking between them,
    -- and turned to whichever of a few angles has the ground under it)
    local big = r and r > 120.0
    local dist = big and math.max(180.0 * 0.75 * DLG_SCALE, r * 1.6, (h or 0.0) * 0.8) or 180.0 * 0.75 * DLG_SCALE
    -- (a small one - a Bob-omb Buddy, a Toad - hid behind the athlete's body at his shoulder: higher, looking down)
    local small = not big and (h or 75.0) < 100.0
    local lift = big and 110.0 or 0.0
    if small then bz = z + (h or 75.0) * 0.7 end        -- (its middle, not 2 m over it)
    local cx, cy, yaw
    -- (and with no wall between him and it: in the castle's rooms a Toad's camera stood inside the wall)
    local tries = big and { 135.0, 115.0, 155.0, 100.0 } or { 135.0, 115.0, 155.0, 100.0, 70.0 }
    local sides = { side, -side }
    for _, sd in ipairs(sides) do
        for _, ang in ipairs(tries) do
            local yw = to_b + sd * math.rad(ang)
            local tx, ty = ax + cos(yw) * dist, ay + sin(yw) * dist
            local fz = floor_z(tx, ty, feet + 300.0)
            if (not big or (fz and fz > feet - 250.0)) and wall_cut(ax, ay, az, tx, ty, az + 30.0) >= 1.0 then
                cx, cy, yaw = tx, ty, yw
                break
            end
        end
        if cx then break end
    end
    if not cx then
        yaw = to_b + side * math.rad(135.0)
        cx, cy = ax + cos(yaw) * dist, ay + sin(yaw) * dist
    end
    -- (never inside the speaker - its round `r` cm and a little more: further back along the same line until clear)
    for _ = 1, 8 do
        if not r or (cx - bx) ^ 2 + (cy - by) ^ 2 >= (r + 60.0) ^ 2 then break end
        dist = dist + 60.0
        cx, cy = ax + cos(yaw) * dist, ay + sin(yaw) * dist
    end
    local cz = az + lift + sin(atan(az - bz, math.max(db, 1.0))) * 100.0 * 0.75 * DLG_SCALE
    if small then cz = az + 15.0 end                    -- (at his shoulder: from above, its turned-to-face body looked thin)
    -- (nowhere clear: in front of the first wall that way)
    local cut = wall_cut(ax, ay, az, cx, cy, cz)
    if cut < 1.0 then
        local k = math.max(0.2, cut - 40.0 / math.max(dist, 1.0))
        cx, cy, cz = ax + (cx - ax) * k, ay + (cy - ay) * k, az + (cz - az) * k
    end
    local k = big and 0.5 or (small and 0.45 or 0.7)    -- (how far toward him it looks, from the speaker)
    local fx, fy, fz = bx + (ax - bx) * k, by + (ay - by) * k, bz + (az - bz) * k
    fz = fz + (bz - fz) * 0.1
    local dx, dy, dz = fx - cx, fy - cy, fz - cz
    local rot = { Pitch = deg(atan(dz, sqrt(dx * dx + dy * dy))), Yaw = deg(atan(dy, dx)), Roll = 0.0 }
    local cam = lib.camera(world, "dialog_cut", { X = cx + OFFSET.X, Y = cy + OFFSET.Y, Z = cz + OFFSET.Z }, rot)
    if not cam then return end
    G.dialog_cam = { cam = cam, pc = pc, world = world:GetAddress(), t = 0.0 }
    pcall(function() pc:SetViewTargetWithBlend(cam, 0.6, 4, 2.0, false) end)
    log("dialog cutscene")
end
local function dialog_cut_tick(dt)
    local c = G.dialog_cam
    if not c then return end
    c.t = c.t + dt
    local w = lib.world()
    local here = w and w:GetAddress() == c.world
    -- (shut: the message gone - a moment after it opened, so its own first frames count)
    if here and c.t < 0.5 then return end
    if here and DIALOG and DIALOG.active and not G.dying then return end
    G.dialog_cam = nil
    if not here or G.star_cut then return end
    -- (only while the view is still its own: a Bob-omb Buddy's words end with the cannon's camera, which it cut short)
    pcall(function()
        local pawn, vt = lib.pawn(), c.pc:GetViewTarget()
        if pawn and vt and vt:GetAddress() == c.cam:GetAddress() then c.pc:SetViewTargetWithBlend(pawn, 0.6, 4, 2.0, false) end
    end)
end

-- ------------------------------------------------------------ the star dance
-- (act_star_dance / general_star_dance_handler, CUTSCENE_DANCE_DEFAULT: the star taken, Mario lands if he is in the
-- air, dances and holds the star up over him while the camera comes round to his front; "Here we go!" at frame 42; out
-- of the course at frame 80, or - a star that lets him stay - back to him. The athlete throws his arms up - STORROR's
-- emote - and his controls are held meanwhile; nothing hurts him. Before, the star just went and he was sent out three
-- seconds on.)
-- (STORROR's corkscrew, as he does it taking Bowser's key - bowser_fight.lua's - in slow motion and on the spot; it was
-- an arms-up emote: "star pickups ... the cork that you do when picking up bowsers key? can you change it to that?",
-- 2026-10-16. The dance ends as he lands from it, 1.35 s into the take, not at Mario 64's 80 frames.)
local DANCE_EMOTE = "/SPP/SPPCharacter/Animation/Flip/Cork/MontageFlipCork_3823_SPPFlipsKelan_frames_0-68026.MontageFlipCork_3823_SPPFlipsKelan_frames_0-68026"
G.DANCE_RATE, G.DANCE_LAND = 0.75, 1.35
G.DANCE_FLIP_DOWN = 1.0         -- s into the take: stopped after this, the flip is done (its Landing notify is at 1.2)
local DANCE_LOCK = "SM64StarDance"
local DANCE_VOICE, DANCE_OUT = 42.0 / 30.0, 80.0 / 30.0     -- s from the dance's start
local DANCE_WAIT = 4.0                                      -- s: in the air, till he lands (ACT_FALL_AFTER_STAR_GRAB)
local DANCE_CAM_BACK, DANCE_CAM_UP = 330.0, 35.0            -- cm: the camera before him, over his middle
local DANCE_STAR_UP = 150.0                                 -- cm: the star over his middle (over his raised hands)

-- The dance played as STORROR's own emote (ParkourComponent.PlayEmoteMontage), then slowed and moved on to `from` s.
-- Played with Montage_Play, STORROR stopped it before the next frame, every time and any montage - nothing in the
-- mod did, and no script call: "no star animation", 2026-10-23. Its emote STORROR keeps. Montage_Play if that fails.
-- The take's length, s, or 0 if it does not play.
function G.play_emote(pawn, ai, m, rate, from)
    local ok = false
    local pk = parkour(pawn)
    if pk then pcall(function() pk:PlayEmoteMontage(m); ok = ai:Montage_IsPlaying(m) end) end
    if ok then
        pcall(function() ai:Montage_SetPlayRate(m, rate) end)
        if from and from > 0.0 then pcall(function() ai:Montage_SetPosition(m, from) end) end
    else
        pcall(function() ai:Montage_Play(m, rate, 0, from or 0.0, true) end)
    end
    local len = 0.0
    pcall(function() if ai:Montage_IsPlaying(m) then len = m:GetPlayLength() end end)
    return len
end

local function dance_lock(d, pawn, on)
    local pc = d.pc
    pcall(function()
        if on then
            if not pc:IsMoveInputIgnored() then pc:SetIgnoreMoveInput(true); d.ign = true end
        elseif d.ign then
            pc:SetIgnoreMoveInput(false); d.ign = nil
        end
    end)
    pcall(function() if on then pawn:DisableInput(pc) else pawn:EnableInput(pc) end end)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            local cname = o:GetClass():GetFName():ToString()
            if cname == "ParkourComponent" then
                o:ClearInputQueue()
                o:EnableAllParkourInputs(FName(DANCE_LOCK), not on)
            elseif cname == "LocomotionComponent" then
                o:EnableLocomotionInputCallback(FName(DANCE_LOCK), not on)
                o:EnableAdvancedLocomotionInput(FName(DANCE_LOCK), not on)
            end
        end
    end)
end

-- s: the star (or key) just taken - its model is the one held up
function G.star_dance(s)
    local pawn, world, pc = lib.pawn(), lib.world(), lib.controller()
    if not (pawn and world and pc) or G.star_dance_st then return false end
    local d = { star = s, t = 0.0, pc = pc, world = world:GetAddress(), exit = not s.noexit }
    -- (taken flying or sliding: out of it first, down to the ground - ACT_FALL_AFTER_STAR_GRAB - then the dance)
    if FLIGHT and FLIGHT.active and FLIGHT.active() and FLIGHT.land then pcall(FLIGHT.land, pawn, "a star taken") end
    local SL = package.loaded["slide"]
    if SL and SL.active and SL.active() and SL.clear then pcall(SL.clear) end
    dance_lock(d, pawn, true)
    pcall(function() s.inst.actor:SetActorHiddenInGame(false) end)
    G.star_dance_st = d
    log("star dance")
    return true
end

local function dance_end(d, view_back)
    G.star_dance_st = nil
    local pawn = lib.pawn()
    if pawn then
        dance_lock(d, pawn, false)
        -- (never left hovering in flying mode after it - no gravity there - unless something has him in it)
        pcall(function()
            local cm = pawn.CharacterMovement
            if cm.MovementMode == 5 and not G.swim and not G.carried then cm:SetMovementMode(3, 0) end
        end)
        pcall(function()
            if d.ai and d.ai:IsValid() then
                if d.mont and d.mont:IsValid() then d.ai:Montage_Stop(0.25, d.mont) end
                d.ai:SetRootMotionMode(d.rm or 2)
            end
        end)
        if view_back then pcall(function() d.pc:SetViewTargetWithBlend(pawn, 0.6, 4, 2.0, false) end) end
    end
    pcall(function() d.star.inst.actor:SetActorHiddenInGame(true) end)
end

local function dance_cam_place(d, el, l)
    local a = d.yaw0 + math.rad(math.min(el, DANCE_OUT) * 9.0)          -- (round him, slowly)
    local back = DANCE_CAM_BACK - math.min(el, DANCE_OUT) * 18.0
    local mx, my, mz = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z
    local cx, cy, cz = mx + cos(a) * back, my + sin(a) * back, mz + DANCE_CAM_UP
    local cut = wall_cut(mx, my, mz + 40.0, cx, cy, cz)
    if cut < 1.0 then
        local k = math.max(0.3, cut - 40.0 / back)
        cx, cy, cz = mx + (cx - mx) * k, my + (cy - my) * k, mz + (cz - mz) * k
    end
    local tz = mz + 55.0
    local hd = math.max(1.0, sqrt((mx - cx) ^ 2 + (my - cy) ^ 2))
    local rot = { Pitch = deg(atan(tz - cz, hd)), Yaw = deg(atan(my - cy, mx - cx)), Roll = 0.0 }
    pcall(function() d.cam:K2_SetActorLocationAndRotation({ X = cx + OFFSET.X, Y = cy + OFFSET.Y, Z = cz + OFFSET.Z }, rot, false, {}, true) end)
end

local function star_dance_tick(dt)
    if G.oneup_chimes and G.oneup_chimes > 0 then
        G.oneup_chime_t = (G.oneup_chime_t or 0.0) - dt
        if G.oneup_chime_t <= 0.0 then
            G.oneup_chime_t, G.oneup_chimes = 0.45, G.oneup_chimes - 1
            sfx("oneup")
        end
    end
    -- (out of the course after it: the view back on him once the next scene is up - it stayed on the dance's camera,
    -- left behind in the course, and the castle was black)
    local hold = G.dance_view
    if hold and (G.name ~= hold.name or not (G.warping or G.pending)) then
        G.dance_view = nil
        pcall(function()
            local pawn = lib.pawn()
            local vt = hold.pc:GetViewTarget()
            if pawn and (not vt or vt:GetAddress() == hold.addr) then hold.pc:SetViewTargetWithBlend(pawn, 0.0, 0, 0.0, false) end
        end)
    end
    local d = G.star_dance_st
    if not d then return end
    local w = lib.world()
    local pawn = lib.pawn()
    if not (w and pawn) or w:GetAddress() ~= d.world or G.dying then dance_end(d, pawn ~= nil); return end
    d.t = d.t + dt
    local l = pawn:K2_GetActorLocation()
    if not d.started then
        local falling = false
        pcall(function() falling = pawn.CharacterMovement:IsFalling() end)
        -- (taken in the air in one of STORROR's flips: its flying mode is not falling, and the dance began up there - set
        -- on his feet in the air, he fell at once, and STORROR stopped the dance every frame of it: "still no star
        -- animation", 2026-10-22. As Mario 64's ACT_FALL_AFTER_STAR_GRAB: the flip ended, he falls, and dances once down.)
        if not falling and not G.swim and not G.carried and d.t < DANCE_WAIT then
            local mode = -1
            pcall(function() mode = pawn.CharacterMovement.MovementMode end)
            if mode == 5 then
                local fz = G.floor_z and G.floor_z(l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z)
                local half = G.half or 86.0
                pcall(function() half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight() end)
                if fz and l.Z - OFFSET.Z - half - fz > 15.0 then
                    pcall(G.parkour_reset, pawn)
                    pcall(function() pawn.CharacterMovement:SetMovementMode(3, 0) end)
                    falling = true
                    if not d.dropped then d.dropped = true; log("star dance: taken in the air mid-move - down first") end
                end
            end
        end
        if falling and not G.swim and not G.carried and d.t < DANCE_WAIT then
            -- (still in the air: the star keeps over him till he lands)
            pcall(function() d.star.inst.actor:K2_TeleportTo({ X = l.X, Y = l.Y, Z = l.Z + DANCE_STAR_UP }, { Pitch = 0.0, Yaw = (d.t * 337.5) % 360.0, Roll = d.star.roll or 0.0 }) end)
            return
        end
        d.started = d.t
        pcall(function() pawn.CharacterMovement:StopMovementImmediately() end)
        local yaw = 0.0
        pcall(function() yaw = pawn:K2_GetActorRotation().Yaw end)
        d.yaw0 = math.rad(yaw)
        -- (the dance: on his feet - taken out of a climb up or off a ledge, STORROR still had him in its climbing mode and
        -- no dance came: "didnt get a star grab animation for the star in the tower", 2026-10-17. Its move ended, he is
        -- put on his feet first.)
        local mode = -1
        pcall(function() mode = pawn.CharacterMovement.MovementMode end)
        log("star dance: movement mode %d", mode)
        if mode ~= 1 and not G.swim and not G.carried then
            pcall(G.parkour_reset, pawn)
            pcall(function() pawn.CharacterMovement:SetMovementMode(1, 0) end)
            pcall(function() mode = pawn.CharacterMovement.MovementMode end)
        end
        local walking = mode == 1
        -- (in the water too - Mario 64's ACT_WATER_STAR_DANCE; swim.lua holds him still and upright meanwhile: "next
        -- play our star animation when picking up a star underwater", 2026-10-18 - and in whatever mode he is in, not
        -- carried: under the metal cap at the bottom of the water he was in flying mode, and no dance came, "no star
        -- animation collect when using metal cap")
        if walking or G.swim or not G.carried then
            pcall(function()
                local ai = pawn.Mesh:GetAnimInstance()
                local m = lib.try_load(DANCE_EMOTE)
                if ai and m then
                    d.ai, d.rm, d.mont = ai, ai.RootMotionMode, m
                    local len = G.play_emote(pawn, ai, m, G.DANCE_RATE, 0.0)
                    ai:SetRootMotionMode(1)
                    d.out = G.DANCE_LAND / G.DANCE_RATE         -- (played again below if it did not take)
                    log("star dance: emote %s", tostring(len))
                end
            end)
        end
        d.cam = lib.camera(w, "star_dance")
        if d.cam then
            dance_cam_place(d, 0.0, l)
            pcall(function() d.pc:SetViewTargetWithBlend(d.cam, 0.8, 4, 2.0, false) end)
        end
    end
    local el = d.t - d.started
    if d.cam then dance_cam_place(d, el, l) end
    -- (the dance kept on: a move of STORROR's own under way as he took the star - a landing - played over it, or it
    -- did not take, and no dance was seen: "the star animation didnt play", 2026-10-18. Played again where it would be.)
    -- (and on his anim instance as it is now: played on the one he had when it began, gone under him, nothing was seen
    -- for the whole dance - "animation didnt play when collecting a star", 2026-10-19)
    if d.mont and el < d.out - 0.15 then
        pcall(function()
            local ai = pawn.Mesh:GetAnimInstance()
            if ai and ai:IsValid() and ai:GetAddress() ~= d.ai:GetAddress() then
                d.ai, d.rm = ai, ai.RootMotionMode
                ai:SetRootMotionMode(1)
                log("star dance: his anim instance changed at %.2f s", el)
            end
            if not d.ai:Montage_IsPlaying(d.mont) and el * G.DANCE_RATE >= G.DANCE_FLIP_DOWN then
                -- (STORROR ends its flip itself as he comes down from it - played as its emote, its take-off has him
                -- in its flying mode, and at the landing it stops the take: the flip is done. Not played again - in
                -- that mode it would not take, and it flickered - he is on his feet and the dance closes.)
                if not d.flip_down then
                    d.flip_down = true
                    d.mont = nil
                    d.out = math.min(d.out or DANCE_OUT, el + 0.2)
                    pcall(function()
                        local cm = pawn.CharacterMovement
                        if cm.MovementMode == 5 and not G.swim and not G.carried then cm:SetMovementMode(1, 0) end
                    end)
                    log("star dance: the flip done at %.2f s (STORROR ended it)", el)
                end
            elseif not d.ai:Montage_IsPlaying(d.mont) then
                local cur = d.ai:GetCurrentActiveMontage()
                -- (stopped again and again with nothing over it - taken in the middle of one of STORROR's own moves, its
                -- end still stopping whatever plays: "star animation didnt play", 2026-10-22. After a few, the move is
                -- cleared once more - its state, his walking, its queued inputs - before the next try.)
                d.replays = (d.replays or 0) + 1
                if d.replays == 3 and not d.recleared then
                    d.recleared = true
                    if not G.swim and not G.carried then
                        pcall(G.parkour_reset, pawn)
                        pcall(function() pawn.CharacterMovement:SetMovementMode(1, 0) end)
                    end
                    pcall(dance_lock, d, pawn, true)
                end
                local len = G.play_emote(pawn, d.ai, d.mont, G.DANCE_RATE, el * G.DANCE_RATE)
                pcall(function() d.ai:SetRootMotionMode(1) end)
                if d.replays <= 6 then
                    local mode = -1
                    pcall(function() mode = pawn.CharacterMovement.MovementMode end)
                    log("star dance: emote played again at %.2f s (%s over it, %s, mode %d)", el,
                        (cur and cur:IsValid()) and cur:GetFName():ToString() or "nothing", tostring(len), mode)
                end
            end
        end)
    end
    -- (bhvCelebrationStar: round his head as it rises, then over him, turning)
    local spin = (d.t * 337.5) % 360.0
    local sx, sy, sz = l.X, l.Y, l.Z + DANCE_STAR_UP
    if el < 1.33 then
        local k = el / 1.33
        local a = el * 2.0 * math.pi * 1.2
        local r = 70.0 * (1.0 - k)
        sx, sy, sz = l.X + cos(a) * r, l.Y + sin(a) * r, l.Z + 40.0 + (DANCE_STAR_UP - 40.0) * k
    end
    pcall(function() d.star.inst.actor:K2_TeleportTo({ X = sx, Y = sy, Z = sz }, { Pitch = 0.0, Yaw = spin, Roll = d.star.roll or 0.0 }) end)
    if not d.said and el >= math.min(DANCE_VOICE, (d.out or DANCE_OUT) - 0.4) then
        d.said = true
        sfx("mario_here_we_go")
    end
    if el >= (d.out or DANCE_OUT) then
        -- the course's own "got a star" way out - or the star's own, `exit_to` (a ghost race's key: race.lua)
        local wo = d.exit and (d.star.exit_to or G.warp[0xF0])
        if wo then
            -- (without the course-complete screen, its lives at 50, 100 and 150 coins given here)
            if not G.CM then
                local n = math.min(3, math.floor((G.coin_count or 0) / 50))
                local HP = _G.HEALTH
                if n > 0 and HP then
                    HP.lives = HP.lives + n
                    G.oneup_chimes = n
                    log("course complete: %d coins, %d more %s", G.coin_count, n, n == 1 and "life" or "lives")
                end
            end
            -- (out, the camera kept on him through the fade; the next scene puts the view back)
            dance_end(d, false)
            G.warp_out("star", wo.scene, wo.node, nil, true)
            if not G.warping then pcall(function() d.pc:SetViewTargetWithBlend(pawn, 0.0, 0, 0.0, false) end)
            elseif d.cam then
                local addr = nil
                pcall(function() addr = d.cam:GetAddress() end)
                G.dance_view = { pc = d.pc, addr = addr, name = G.name }
            end
        else
            dance_end(d, true)
            G.complete = nil                            -- (he stays: no screen)
            -- (general_star_dance_handler, a star that does not end the course, frame 80: "Do you want to Save?" -
            -- DIALOG_013 after the 100-coin star, 014 after another. The file was saved as the star was taken, so
            -- either answer goes on; then the star-count message, as after the course-complete screen.)
            local s = d.star
            if s and not s.keyn and not s.grand and s.count_after then
                local after = s.count_after
                local before = after - (s.new_star and 1 or 0)
                -- (Mario 64's "Do you want to Save?" here - DIALOG_013/014 - left out: "honestly dont add a save
                -- screen", 2026-10-16; the file is saved as the star is taken)
                G.star_count_message(before, after)
            end
        end
    end
end

-- (nothing solid between him and a star in reach: WDW's Express Elevator star, in its closed cage, was taken from on
-- top of the cage's roof, 188 cm over it - "able to grab star through cage needs fixed", 2026-10-28. Lines from his
-- middle and from his head to 40 cm short of the star's middle (a star set into a wall is not hidden by it), he and
-- the star left out; either one clear will do. No trace to be had: taken as before.)
function G.star_in_view(s, px, py, pz)
    G.KSL_CLASS = G.KSL_CLASS or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    G.NO_COLOR = G.NO_COLOR or { R = 0, G = 0, B = 0, A = 0 }
    local KSL, pawn, world = G.KSL_CLASS, lib.pawn(), lib.world()
    if not (KSL and pawn and world) then return true end
    local ignore = { pawn }
    pcall(function() if s.inst.actor:IsValid() then ignore[2] = s.inst.actor end end)
    local tx, ty, tz = s.x + OFFSET.X, s.y + OFFSET.Y, s.z + 40.0 + OFFSET.Z
    for _, up in ipairs({ 0.0, 60.0 }) do
        local fz = pz + up
        local dx, dy, dz = tx - px, ty - py, tz - fz
        local len = math.sqrt(dx * dx + dy * dy + dz * dz)
        if len <= 40.0 then return true end
        local k = (len - 40.0) / len
        local ok, blocked = pcall(function()
            local out = {}
            return KSL:LineTraceSingle(world, { X = px, Y = py, Z = fz }, { X = px + dx * k, Y = py + dy * k, Z = fz + dz * k },
                0, true, ignore, 0, out, true, G.NO_COLOR, G.NO_COLOR, 0.0)
        end)
        if not ok or not blocked then return true end
    end
    return false
end

local function update_stars(dt, px, py, pz)
    for _, s in ipairs(G.stars) do
        local taking = not G.cutscene           -- (the ending: he can walk about, but takes nothing)
        if s.marker then
            s.t = s.t + dt
            local yaw = (s.t * 42.1875) % 360.0
            pcall(function() s.inst.actor:K2_TeleportTo({ X = s.x + OFFSET.X, Y = s.y + OFFSET.Y, Z = s.z + OFFSET.Z },
                { Pitch = 90.0, Yaw = yaw, Roll = 0.0 }) end)
        elseif not s.hidden and not s.taken then
            s.t = s.t + dt
            if s.fly then fly_star(s, dt) end
            local yaw = (s.t * (s.spin or 337.5)) % 360.0
            if s.roll then
                -- (stood at a roll: Bowser's key, upright)
                pcall(function() s.inst.actor:K2_TeleportTo({ X = s.x + OFFSET.X, Y = s.y + OFFSET.Y, Z = s.z + OFFSET.Z },
                    { Pitch = 0.0, Yaw = yaw, Roll = s.roll }) end)
            else
                lib.set_pose(s.inst, s.x + OFFSET.X, s.y + OFFSET.Y, s.z + OFFSET.Z, yaw)
            end
            local d = dist2(px - OFFSET.X, py - OFFSET.Y, s.x, s.y)
            -- (`reach`, `reach_h`: a bigger star's - Bowser's mega star, bowser_fight M.mega_star)
            if taking and d < (s.reach or 130.0) and abs((pz - OFFSET.Z) - (s.z + 40.0)) < (s.reach_h or 190.0) and not G.star_exit_at
                and not G.star_dance_st and os.clock() >= (s.ready_at or 0.0) and not s.fly
                and G.star_in_view(s, px, py, pz) then
                s.taken = true
                pcall(function() s.inst.actor:SetActorHiddenInGame(true) end)
                -- (its fanfare: the level's music stops for it. The Grand Star's is only the star's ding,
                -- SOUND_MENU_STAR_SOUND - the ending's victory tune follows at once: "also played a regular star pickup
                -- jingle", 2026-11-02)
                sfx(s.keyn and "key_get" or (s.grand and "star_sound") or "star_get")
                if MUSIC and MUSIC.play then pcall(MUSIC.play, nil) end
                local new
                if s.keyn then
                    new = _G.MENU and _G.MENU.add_key and _G.MENU.add_key(s.keyn)
                    s.key = "key:" .. s.keyn
                elseif s.grand then
                    -- (the Grand Star is not one of the 120: the file only notes that the game was finished)
                    new = _G.MENU and _G.MENU.add_key and _G.MENU.add_key("grand")
                    s.key = "key:grand"
                else
                    new = _G.MENU and _G.MENU.add_star and _G.MENU.add_star(s.key)
                end
                local best = false
                if _G.MENU and _G.MENU.note_coins and PAUSE and PAUSE.course_of then
                    local okN, r = pcall(_G.MENU.note_coins, PAUSE.course_of(G.name), G.coin_count)
                    best = okN and r == true
                end
                -- (and, for a star he stays after, the save question and the star-count message: star_dance_tick)
                s.new_star = new and true or false
                s.count_after = (_G.MENU and _G.MENU.star_count) and _G.MENU.star_count() or 0
                -- (what the course-complete screen shows once he is back in the castle: gLastCompletedCourseNum,
                -- gLastCompletedStarNum, the coins, gGotFileCoinHiScore, and whether the star is new - the fanfare)
                G.complete = nil
                if not s.noexit and not s.grand and PAUSE and PAUSE.course_of then
                    local cn = PAUSE.course_of(G.name)
                    local id = tonumber(tostring(s.key or ""):match(":(%d+)$") or "")
                    if cn then
                        local after = (_G.MENU and _G.MENU.star_count) and _G.MENU.star_count() or 0
                        G.complete = { course = cn, star = id and (id + 1) or nil, coins = G.coin_count or 0,
                                       hiscore = best and (G.coin_count or 0) > 0, new = new and true or false, from = G.name,
                                       after = after, before = after - ((new and not s.keyn) and 1 or 0) }
                    end
                end
                log("star %s%s", s.key, new and "" or " (already had it)")
                if _G.HEALTH then _G.HEALTH.reset() end
                local EN = s.grand and package.loaded["ending"]
                local okE, on = false, false
                if EN and EN.start then okE, on = pcall(EN.start) end
                if not okE and on then log("the ending did not start: %s", tostring(on)) end
                if okE and on then
                    -- (the Grand Star: Mario 64's ending, not the way out of the course)
                else
                    if s.noexit then
                        -- (he stays: the course's music again after the fanfare - after the remixed one, which is longer:
                        -- sfx_remix/star_get.wav, "Super Mario 64 - Course Clear (MIDI Remix)", 5.6 s, 2026-11-01)
                        local back = 3.5
                        pcall(function()
                            local MU = package.loaded["music"]
                            if MU and MU.remix then
                                local f = io.open(lib.MOD_DIR .. "sfx_remix/star_get.wav", "rb")
                                if f then f:close(); back = 5.8 end
                            end
                        end)
                        G.music_back_at = os.clock() + back
                    end
                    -- (the star dance, and out of the course after it; without it, out three seconds on. A Bowser key:
                    -- his fight's own key dance takes it from here, the corkscrew and the way out - bowser_fight.lua
                    -- M.key_dance. The star dance as well sent him out twice, and the first way out, cut short, left
                    -- G.warping set: no talking, no doors after - "cant talk to the toad", 2026-10-18)
                    local BF = s.keyn and package.loaded["bowser_fight"]
                    G.star_exit_to = (not s.noexit) and s.exit_to or nil     -- (its own way out: star_exit_at below)
                    if not (BF and BF.key_star) then
                        local okD, danced = pcall(G.star_dance, s)
                        if not (okD and danced) and not s.noexit then G.star_exit_at = os.clock() + 3.0 end
                    end
                end
            end
        end
    end
    if G.music_back_at and os.clock() >= G.music_back_at then
        G.music_back_at = nil
        if MUSIC and MUSIC.play and G.data then pcall(MUSIC.play, G.data.music) end
    end
    if G.star_exit_at and os.clock() >= G.star_exit_at then
        G.star_exit_at = nil
        local w = G.star_exit_to or G.warp[0xF0]    -- the course's own "got a star" way out, or the star's own
        G.star_exit_to = nil
        if w then G.warp_out("star", w.scene, w.node) else G.complete = nil end
    end
    if _G.HEALTH and _G.MENU and _G.MENU.star_count then _G.HEALTH.stars = _G.MENU.star_count() end
end

-- ------------------------------------------------------------ arriving
-- Coming into a scene puts the player at the warp node he was sent to, the way Mario 64 does: through a
-- door he comes out 300 Mario units beyond it, on the far side from the one he went in by; anywhere
-- else he is put on the floor at the node, facing the way it faces. `G.last_node` remembers it, for
-- being put back there.
-- How he comes out at a warp node, by its object (area.c sWarpBhvSpawnTable -> level_update.c set_mario_initial_action;
-- data/spawns.lua from exporter/spawnx.py): out of a painting (held a moment, then out and down), launched up out of
-- the floor (the trap door after Bowser: "when I left bowsers stage with the key I should have come back out the trap
-- door", 2026-10-15), dropped in from where the node is, or hopping out of a pipe. A death's own kinds end with him
-- knocked flat where he lands, "Mamma mia", and the life taken; only when he got there by dying.
local ENTRY = {
    bhvPaintingStarCollectWarp = { style = "painting" }, bhvPaintingDeathWarp = { style = "painting", death = true },
    bhvLaunchStarCollectWarp = { style = "launch", yahoo = true }, bhvLaunchDeathWarp = { style = "launch", death = true },
    bhvAirborneStarCollectWarp = { style = "drop" }, bhvAirborneDeathWarp = { style = "drop", death = true },
    bhvDeathWarp = { style = "drop", death = true }, bhvAirborneWarp = { style = "drop" },
    bhvSpinAirborneWarp = { style = "drop" }, bhvSpinAirborneCircleWarp = { style = "drop" },
    bhvHardAirKnockBackWarp = { style = "drop" }, bhvWarpPipe = { style = "pipe" },
}
local OPEN_WITH = {
    bhvDoorWarp = { "circle", 16 }, bhvSpinAirborneCircleWarp = { "circle", 16 },
    bhvFadingWarp = { "white", 20 }, bhvSpinAirborneWarp = { "white", 26 },
}
local SPAWNS = nil
function G.spawn_bhv(scene, node)
    -- (a node of the mod's own with its arrival's kind on it: the Bowser hallway's painting, G.EXTRA_HALLS)
    local own = scene == G.name and G.node and node and G.node[node]
    if own and own.bhv then return own.bhv end
    if SPAWNS == nil then SPAWNS = lib.load_data("data.spawns") or false end
    return SPAWNS and SPAWNS[scene] and SPAWNS[scene][node] or nil
end
G.entry = nil
-- (Mario 64's arcs, for the athlete's own gravity: a launch up 64 a frame rises 512 Mario units, 384 cm; a painting
-- sends him out at 32 a frame, the floor's trap door 24 a frame, here a little slower as he falls more slowly)
-- (out of a warp pipe forward too, as Mario 64's launch_mario_until_land does at 8 a frame, a little more for his size:
-- Tiny-Huge Island's pipes, solid at last, had him straight up and back down into the pipe he came out of, and it
-- took him straight back to the other island, over and over - 2026-10-29)
local ENTRY_UP, ENTRY_OUT = { launch = 1070.0, pipe = 870.0 }, { painting = 450.0, launch = 360.0, pipe = 240.0 }
local ENTRY_WAIT = { painting = 16 / 30, launch = 11 / 30 }
local PIT_START, PIT_RISE = 300.0, 250.0     -- (out of a trap door's pit: from this far down in it, to this far over the floor)
local PIPE_RIM = 153.75                       -- (a warp pipe's rim over its foot: warp_pipe collision, 205 Mario units)

-- (a node over a ceiling - the first face under it facing down - is one Mario drops through: Mario 64's ceilings stop him
-- only from below. STORROR's collision is solid both ways, and he came down on the top of Hazy Maze Cave's first room
-- instead of into it - "the spawn in hazy maze is incorrect", 2026-10-19. The height just under it, scene cm, or nil.)
function G.under_ceiling(x, y, z)
    local cz, T = floor_hit(G.floor, x, y, z + 60.0)
    if not T then return nil end
    local ux, uy = T[4] - T[1], T[5] - T[2]
    local vx, vy = T[7] - T[1], T[8] - T[2]
    if ux * vy - uy * vx <= 0.0 then return nil end          -- (a floor: in the scene's axes a floor's turn is the other way)
    if not floor_z(x, y, cz - 5.0) then return nil end
    log("arrival: under the ceiling at %.0f, not on it", cz / 0.75)
    return math.min(z, cz - 250.0)              -- (his capsule, 180 tall, clear under it: nearer, the arrival lifted him back over it)
end

function G.arrive(node, opt)
    -- (here, so no way out is under way any more: one overtaken by another scene change - the Bowser key's two exits -
    -- never cleared it, and G.warping held off talking, doors and paintings, 2026-10-18)
    G.warping, G.warp_token = false, nil
    local pawn = lib.pawn()
    local n = node and G.node[node]
    if not (pawn and n and G.data) then return false end
    opt = opt or {}
    G.sunk_until = os.clock() + G.SUNK_HOLD           -- (G.sunk_guard: not left in the floor he arrives on)
    local how = (not opt.respawn) and ENTRY[G.spawn_bhv(G.name, node) or ""] or nil
    if how and how.death and not opt.death then how = { style = how.style } end
    -- (the Bowser run's level: a death in its last fight sends him to the node of the course that led there - that
    -- course's own 0x0C, its way back by the pipe (G.join_scenes: `src_id`), which has no arrival of its own in the joined
    -- level, and he was set down beside the pipe: "when player gets killed by bowser, he should 1 be thrown out of the
    -- pipe", 2026-11-03)
    local back_pipe = opt.death and n.src_id == 0x0C and not opt.respawn
    if back_pipe and not how then how = { style = "drop", death = true } end
    local x, y, z = n.pos[1], n.pos[2], n.pos[3]
    if n.kind ~= "door" then z = G.under_ceiling(x, y, z) or z end
    local yaw = (n.yaw or 0.0) + 180.0
    if n.kind == "door" then
        local fx, fy = -cos(rad(n.yaw or 0.0)), -sin(rad(n.yaw or 0.0))      -- the way the door faces
        local s = opt.flip and -1.0 or 1.0
        for _, d in ipairs(G.doors) do
            if dist2(d.x, d.y, x, y) < 320.0 and abs(d.z - z) < 200.0 then d.armed = false end   -- not to swing open at him
        end
        x, y = x + fx * s * 225.0, y + fy * s * 225.0
        yaw = deg(atan(fy * s, fx * s))
    end
    x, y, yaw = off_painting(x, y, z, yaw)
    local fz = put_down(x, y, z, 1500) or z
    -- (a drop's node under a roof - TTM's slide's way out, in a hollow of its little cave's roof: put_down took the roof
    -- over the node, 1.5 m up, for his floor, and set him on top of it, out on the mountain over the cave - "after the
    -- slide I spawned in the wrong location", 2026-10-27. The floor under the node instead)
    if how and how.style == "drop" and fz > z then fz = floor_z(x, y, z) or fz end
    -- (a swimming warp - the Secret Aquarium's way in: Mario 64 starts him swimming where it is, mid-water,
    -- MARIO_SPAWN_SWIMMING. Put down on the floor under it he began on the tank's bottom, 27 m down, 2026-10-18)
    if G.spawn_bhv(G.name, node) == "bhvSwimmingWarp" then fz = z - 30.0 end
    -- (the Tower of the Wing Cap's flying warp: he arrives where it is, up in the sky, the Wing Cap on and flying -
    -- level_update.c MARIO_SPAWN_FLYING and set_mario_initial_cap_powerup, "you should start in the sky with the wing cap
    -- equipped already flying", 2026-10-17. Without flight.lua, put down on the tower as before)
    local flying_in = n.kind == "fly" and FLIGHT ~= nil and FLIGHT.fly_in ~= nil and CAPS ~= nil
    if n.kind == "fly" then
        if flying_in then
            fz = z - 120.0
        else
            local fx2, fy2, fz2 = fly_down(x, y, z, yaw)
            if fx2 then x, y, fz = fx2, fy2, fz2 end
        end
    end
    -- (out of a painting or up through the floor Mario moves backward from the way the node faces - his speed out is
    -- negative - turned round to face where he goes: the node's own yaw here, whatever off_painting made of it; the
    -- trap door sent him the other way, into the wall, 2026-10-15)
    -- Out of the pipe instead of out of the air, when a death sends him back beside one (falling off Bowser's arena puts
    -- him back on his course by the pipe that took him there: bitdw, bitfs and bits node 0x0C): he is shot up out of it,
    -- straight up till he is over its rim, then out onto the floor beside it, toward where Mario 64 drops him ("do the
    -- same thing we just did with the trap door but with the pipe", 2026-10-15)
    -- (the course's own return point, 0x0C: 6.8 m from the Dark World's pipe, 16 m from the Sky's)
    local pipe = nil
    if how and how.death and how.style == "drop" and (node == 0x0C or back_pipe) then
        for _, w in ipairs(G.warps or {}) do
            if w.kind == "pipe" and dist2(w.x, w.y, x, y) < 1800.0 then pipe = w end
        end
    end
    if pipe then
        how = { style = "launch", death = true }
        local d, dx, dy = dist2(x, y, pipe.x, pipe.y)
        yaw = (d > 1.0) and deg(atan(dy, dx)) or (n.yaw or yaw)
        x, y, z = pipe.x, pipe.y, pipe.z
        fz = pipe.tz and (pipe.z - PIT_START) or (pipe.z + 10.0)
        -- (the Bowser run's way back from its last fight: out over the pipe's rim, not from down in it - the Sky's pipe at
        -- its top is made deep, and started in it he caught on it and stayed there: "player died and got traped in pipe
        -- didnt exit correctly", 2026-11-04)
        -- (from just inside its top, half a metre under the rim, up and out: started beside it he never came out of it -
        -- "didnt actually come out of the pipe", 2026-11-04. STORROR's own ragdoll, his fall off Bowser's stage carried
        -- over, which dropped him down the deep pipe under the lava's height, is stopped as it begins - G.lava_race_tick)
        if back_pipe then fz = pipe.z + PIPE_RIM - 50.0 end
    elseif how and (how.style == "painting" or how.style == "launch") then yaw = n.yaw or yaw end
    -- (a launch starts under the floor - the castle's trap door - and Mario goes up through it, as Mario 64's floors
    -- let him from below; ours do not, and a teleport into it was refused: he starts on top, with what is left of the
    -- rise, 512 Mario units above the node)
    local up_left, pit = nil, nil
    -- Out of the trap door's own pit, when the node is over one (the death that sends him back from the Dark World):
    -- the trap door stands open as the screen opens, he is shot up out of the hole from `PIT_START` down in it to
    -- `PIT_RISE` over the hallway and out onto it, and the trap door shuts once he has landed (platforms.lua
    -- P.open_traps / P.shut_traps; "make him come out of the hole with the trap doors open then when back on surface
    -- close the trap doors", 2026-10-15)
    if how and how.style == "launch" and PLAT and PLAT.open_traps then
        local ok, n, top = pcall(PLAT.open_traps, x, y, 450.0)
        if ok and n and n > 0 and top then pit = top end
    end
    if pit then
        fz = pit - PIT_START
    elseif pipe then
        -- (in the pipe, on its floor; how high he goes is reckoned once he is there)
    elseif how and how.style == "launch" then
        -- (the floor round the trap door: under the node itself there is only the pit, open or not - starting in it, he
        -- came back down into it and fell through to the Dark World again)
        local top = nil
        for _, d in ipairs({ 0.0, 120.0, 220.0, 320.0 }) do
            for k = 0, 7 do
                local a = rad(k * 45.0)
                local f2 = floor_z(x + cos(a) * d, y + sin(a) * d, z + 400.0)
                if f2 and f2 > fz + 30.0 and (not top or f2 > top) then top = f2 end
            end
            if top then break end
        end
        if top then fz = top end
        up_left = math.max(60.0, z + 384.0 - fz)
    end
    local dest = { X = x + OFFSET.X, Y = y + OFFSET.Y, Z = fz + OFFSET.Z + 120.0 }
    -- (a painting's and a drop's node is up in the air where Mario appears; a launch and a pipe start at the floor)
    if how and (how.style == "painting" or how.style == "drop") and z > fz + 30.0 then dest.Z = z + OFFSET.Z + 90.0 end
    -- (and under whatever is over him there: TTM's slide's way out drops him into its little cave at its foot, its roof
    -- over the node a head over Mario's - the athlete's head in it, he was pushed up out through it onto the mountainside:
    -- "after the slide I spawned in the wrong location", 2026-10-27. Not lower than standing on its floor)
    do
        -- (over all of him, not his middle alone)
        local cz = nil
        for k = -1, 7 do
            local px, py = x, y
            if k >= 0 then px, py = x + cos(rad(k * 45.0)) * 45.0, y + sin(rad(k * 45.0)) * 45.0 end
            local c = G.ceil_z(px, py, fz + 20.0)
            if c and (not cz or c < cz) then cz = c end
        end
        if cz and how and how.style == "drop" and cz - fz < 600.0 then
            dest.Z = fz + 90.0 + OFFSET.Z                   -- (indoors, a roof low over him: on its floor, no drop)
        else
            local top = cz and (cz - (G.half or 86.0) - 8.0)
            if top and dest.Z - OFFSET.Z > top then dest.Z = math.max(fz + 90.0, top) + OFFSET.Z end
        end
    end
    for _, w in ipairs(G.warps or {}) do
        if dist2(w.x, w.y, x, y) < (w.r or 60.0) + 120.0 then w.used = true end      -- he is standing in it: not straight back
    end
    G.settle(pawn)
    -- (refused when the capsule would overlap something there: a little higher, as the start point does - but first a
    -- little lower, his middle 90 over the floor, 4 under his feet: under a low roof, 120 up put his head in it and
    -- every lift after went higher, out over the SL igloo's way in, inside its shell - "spawned inside a wall in the
    -- igloo", 2026-10-26; his capsule is 172 tall, the way in 192)
    for _, lift in ipairs({ 0.0, -30.0, 40.0, 100.0, 160.0, 220.0, 300.0, 450.0 }) do
        local ok, r = pcall(function() return pawn:K2_TeleportTo({ X = dest.X, Y = dest.Y, Z = dest.Z + lift }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 }) end)
        if ok and r then dest.Z = dest.Z + lift; break end
        if lift == 450.0 then log("arrive: teleport refused at node 0x%02X", node) end
    end
    -- (the rise left, from where he was put: the trap door's own floor is not among ours, and he went up 8 m into the
    -- hallway's ceiling and was knocked flat)
    if up_left then up_left = math.max(60.0, z + 384.0 - (dest.Z - OFFSET.Z - 90.0)) end
    if pit then up_left = pit + PIT_RISE - (dest.Z - OFFSET.Z - 90.0) end
    if pipe then up_left = pipe.z + PIPE_RIM + PIT_RISE - (dest.Z - OFFSET.Z - 90.0) end
    pcall(function() lib.controller():SetControlRotation({ Pitch = 0.0, Yaw = yaw, Roll = 0.0 }) end)
    G.entry = nil
    if flying_in then
        -- (the cap for 1200 frames, as Mario 64 gives it here - not the 1800 of a cap from a box - and off he flies)
        G.give_cap("wing")
        CAPS.left = 40.0
        local okf = pcall(FLIGHT.fly_in, pawn, yaw, 32.0)
        if not okf then log("arrive: flying in failed") end
    elseif how then
        local f = rad(yaw)
        local out, up = ENTRY_OUT[how.style] or 0.0, ENTRY_UP[how.style] or 0.0
        if up_left then up = math.sqrt(2.0 * 1450.0 * up_left) end      -- (his gravity: about 1450 cm/s/s)
        -- (a death's launch out of a pool - the basement's way into Hazy Maze Cave - out past its edge: up and out far
        -- enough to land on the floor beyond it, looked for along the way he goes. Shot out at the trap door's rise left
        -- he went up under a metre and back into the pool, and into the course again: "after death player didnt launch
        -- far enough out of oil pit and fell back in", 2026-11-04)
        if how.style == "launch" and how.death and not pit and not pipe then
            local rim = fz
            local need = nil
            for d = 50.0, 1500.0, 50.0 do
                local f2 = floor_z(x + cos(f) * d, y + sin(f) * d, rim + 600.0)
                if f2 and f2 >= rim - 30.0 and f2 <= rim + 250.0 then
                    -- (ground there and a little on: not a lip)
                    local f3 = floor_z(x + cos(f) * (d + 60.0), y + sin(f) * (d + 60.0), rim + 600.0)
                    if f3 and f3 >= rim - 30.0 then need = d + 110.0; break end
                end
            end
            if need and need > 120.0 then
                up = math.max(up, 950.0)
                local T = 2.0 * up / 1450.0
                out = math.max(out, math.min(1100.0, need / T))
                log("arrive: launched out past the pool's edge, %.0f cm on (%.0f out, %.0f up)", need, out, up)
            end
        end
        -- (out of a painting or up through the floor he comes toward the camera, which looks back at where he came
        -- from, as Mario 64's does; behind him it went into the painting's wall once he lay down)
        if how.style == "painting" or how.style == "launch" then
            pcall(function() lib.controller():SetControlRotation({ Pitch = -10.0, Yaw = yaw + 180.0, Roll = 0.0 }) end)
        end
        G.entry = { style = how.style, death = how.death, yahoo = how.yahoo, t = 0.0, fx = cos(f), fy = sin(f), yaw = yaw,
                    vx = cos(f) * out, vy = sin(f) * out, vz = up, wait = ENTRY_WAIT[how.style] or 0.0, phase = "wait",
                    pipe = pipe and true or nil,
                    -- (out of a warp pipe: straight up till over its rim - from its foot - then out)
                    out_above = (pipe and (pipe.z + PIPE_RIM + 20.0)) or (how.style == "pipe" and (fz + PIPE_RIM + 20.0)) or nil }
        -- (and that way held while he comes out: entry_tick)
        if how.style == "painting" or how.style == "launch" then G.entry.cam = { pitch = -10.0, yaw = yaw + 180.0 } end
        if G.entry.wait > 0.0 then
            -- (held where he appears: no movement at all - gravity off alone did not hold him, and STORROR shows
            -- him again if hidden; the screen's opening covers most of it, as in Mario 64)
            G.entry.pin = dest
            pcall(function() pawn.CharacterMovement:SetMovementMode(0, 0) end)
        end
    else
        G.freeze(1.0)
    end
    -- (held still in a pipe or a painting on the way here: moving again, unless the arrival holds him itself)
    if G.pinned then
        G.pinned = false
        if not (G.entry and G.entry.pin) then pcall(function() pawn.CharacterMovement:SetMovementMode(3, 0) end) end
    end
    -- (and the screen opens as Mario 64 opens it for this kind of arrival: init_mario_after_warp)
    G.reset_cloth(pawn)              -- (his clothes start again from their shape where he is)
    G.open_with = OPEN_WITH[G.spawn_bhv(G.name, node) or ""] or { "star", 16 }
    G.air = false
    G.no_fall_until = os.clock() + 3.0
    G.warp_cool = 1.5
    G.last_node, G.last_opt = node, opt
    log("player -> %s node 0x%02X (%s%s) at (%.0f, %.0f, %.0f)", G.name, node, tostring(n.kind),
        how and (", " .. how.style .. (how.death and " death" or "")) or "", dest.X, dest.Y, dest.Z)
    -- (the camera out of any wall behind him: G.camera_clear - not out of a painting or up through the floor)
    if not (how and (how.style == "painting" or how.style == "launch")) then pcall(G.camera_clear, pawn) end
    if n.kind == "pipe" then sfx("pipe_exit") elseif n.kind == "fading" then sfx("teleport") end
    return true
end

-- The camera's way as he arrives, out of the rock: anywhere but out of a painting or up through the floor (which turn it
-- themselves) he keeps the way the camera looked, and next to a wall it could be in it - Bob-omb Battlefield's teleport
-- up the mountain, "when coming out of teleport on bomb omb battlefield the camera is inside the mountain", 2026-11-05.
-- Kept if `need` cm along its arm from his head is clear (the Camera channel, as STORROR's arm sweeps), else turned to
-- the nearest way that is, `step` degrees at a time either side. `dry`: only say which.
G.CAM_CLEAR = { need = 260.0, up = 60.0, step = 20.0 }
function G.camera_clear(pawn, dry)
    G.KSL_CLASS = G.KSL_CLASS or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    G.NO_COLOR = G.NO_COLOR or { R = 0, G = 0, B = 0, A = 0 }
    local KSL, world, pc = G.KSL_CLASS, lib.world(), lib.controller()
    if not (KSL and world and pc and pawn) then return nil end
    local C = G.CAM_CLEAR
    local l = pawn:K2_GetActorLocation()
    local r = pc:GetControlRotation()
    local sx, sy, sz = l.X, l.Y, l.Z + C.up
    local p = math.rad(r.Pitch)
    local function clear(yaw)
        local f = math.rad(yaw)
        local ex = sx - cos(f) * cos(p) * C.need
        local ey = sy - sin(f) * cos(p) * C.need
        local ez = sz - sin(p) * C.need
        local ok, blocked = pcall(function()
            local out = {}
            return KSL:LineTraceSingle(world, { X = sx, Y = sy, Z = sz }, { X = ex, Y = ey, Z = ez }, 1, true, { pawn }, 0,
                out, true, G.NO_COLOR, G.NO_COLOR, 0.0)
        end)
        return ok and not blocked
    end
    if clear(r.Yaw) then return r.Yaw, false end
    for k = 1, 9 do
        for _, s in ipairs({ 1, -1 }) do
            local y = r.Yaw + s * k * C.step
            if clear(y) then
                if not dry then
                    pcall(function() pc:SetControlRotation({ Pitch = r.Pitch, Yaw = y, Roll = 0.0 }) end)
                    log("camera: turned %+.0f degrees as he arrives, out of the wall behind him", s * k * C.step)
                end
                return y, true
            end
        end
    end
    return nil
end

-- Mario 64's EXIT COURSE (the pause screen's): out of any course. Not offered in the castle itself. Out in front of the
-- course's own way in - its painting, or wherever its star sends him (its 0xF0 node) - not Mario 64's castle node 0x1F
-- in the entrance hall: "exiting course should put you outside of paintings", 2026-10-18.
local HUBS = { grounds = true, castle = true, castle2 = true, castle3 = true, courtyard = true }
function G.can_exit() return G.name ~= nil and not HUBS[G.name] and not G.pending end
-- (a course with no star's way out - the Bowser courses: out where a death there puts him, its 0xF1 node, in front of
-- its own door - Bowser in the Fire Sea's in the basement, not the entrance hall: "exiting course in bowser in the fire
-- sea brings player all the way to floor one", 2026-11-07)
function G.exit_course()
    if not G.can_exit() then return end
    local w = G.warp and (G.warp[0xF0] or G.warp[0xF1])
    if w then G.warp_out("exit", w.scene, w.node) else G.warp_out("exit", "castle", 0x1F) end
end
-- (the pause screen's EXIT TO CASTLE, the mod's own: Mario 64's EXIT COURSE destination, the entrance hall)
function G.exit_to_castle()
    if G.can_exit() then G.warp_out("exit", "castle", 0x1F, { to_castle = true }) end
end

-- what the pause screen needs to know (it does not open on the way to another scene, while a star is being
-- collected, while he is out of power, or during a new file's opening)
-- No pause from the moment his power runs out (or any death begins) till he is out of the course and standing there:
-- the death's warp done, the scene up, his landing played out, the screen open again - "when the players energy runs
-- out they cant press pause, give them the ability back once the player arrives outside the painting or level",
-- 2026-10-31. (Mario 64's screen was already not offered while he was dead; STORROR's menu still came up on Start.)
-- The death's warp is told by G.dying having been set and gone again (G.die's, then death_warp's).
-- Start only once he has landed: on his feet on the ground (walking), or swimming, or on a pole - anything else
-- (falling, STORROR's flying jumps and flips, its other moves, and his ragdoll, flying or lying) holds it off till he is
-- on his feet: "just disable the pause button until the player lands", 2026-11-02; "players able to pause during
-- ragdoll", 2026-11-03
function G.in_air_for_pause()
    -- (limp, never - whatever his capsule's mode says while his body lies: "players able to pause during ragdoll",
    -- 2026-11-03; it was let be, the body held still under it - nor while he gets up from it)
    local RG = package.loaded["ragdoll"]
    if RG and RG.limp then local ok, l = pcall(RG.limp); if ok and l then return true end end
    if G.getup_at then return true end
    local mode = -1
    pcall(function() mode = lib.pawn().CharacterMovement.MovementMode end)
    if mode == 1 or G.swim then return false end
    local CL = package.loaded["climb"]
    if CL and CL.active then local ok, a = pcall(CL.active); if ok and a then return false end end
    return true
end
function G.pause_blocked()
    -- (and through the ending: Start held there skips it - ending.lua - and opened STORROR's menu too)
    if G.ending_on and G.ending_on() then return true end
    -- (nor through Bowser's entrance - his shot and his words, bowser_fight.lua's cutscene: "can pause during bowser
    -- cutscene", 2026-11-04)
    local BF = package.loaded["bowser_fight"]
    if BF and BF.cutscene then return true end
    -- (and a moment after it: Start pressed at the cake to go on, or held to skip, also opened STORROR's menu as the
    -- ending let go - "when pressing pause to skip the storror charater pops up", 2026-11-02)
    local EN = package.loaded["ending"]
    if EN and EN.ended_at and os.clock() - EN.ended_at < 1.5 then return true end
    -- (none till he has landed: G.in_air_for_pause - "just disable the pause button until the player lands", 2026-11-02)
    if G.in_air_for_pause() then return true end
    -- (nor in the air: falling - off a ledge, a jump on its way down or up - Start does nothing till he is down: "if the
    -- player is falling they cant pause", 2026-11-02. Nor in his ragdoll: G.in_air_for_pause.)
    local HP = _G.HEALTH
    local now = os.clock()
    if (HP and HP.dead_t) or G.dying then
        if not G.pause_block then G.pause_block = { t = now }; log("pause: off (a death)") end
        if G.dying then G.pause_block.died = true end
    end
    local b = G.pause_block
    if not b then return false end
    local busy = G.dying or G.pending or G.warping or G.entry or (HP and HP.dead_t) or (TRANS and TRANS.busy and TRANS.busy())
    if b.died and not busy then
        b.clear_t = b.clear_t or now
        -- (a moment's settling: between the warp's steps the flags can all be down for a frame)
        if now - b.clear_t >= 0.3 then
            G.pause_block = nil
            log("pause: back (out of the course)")
            return false
        end
    else
        b.clear_t = nil
    end
    -- (never for good: a death that went some other way)
    if now - b.t > 45.0 then G.pause_block = nil; log("pause: back (45 s)"); return false end
    return true
end

function G.pause_info()
    local HP = _G.HEALTH
    local IN, EN = package.loaded["intro"], package.loaded["ending"]
    local can = G.name ~= nil and not G.pending and not G.star_exit_at and not G.star_dance_st and not (HP and HP.dead_t)
        and not (G.CM and G.CM.active) and not G.complete
        and not (IN and IN.active) and not (EN and EN.active)
    -- (nor on the star select - Mario 64 offers no pause there; STORROR's menu came up over it: "able to pause in star
    -- select screen which needs fixed", 2026-11-01)
    -- (and through the opening intro and the ending, as Mario 64: paused in the intro, the game stood still while the
    -- scene went on - he never came out of the pipe, the pipe never went down, the camera stayed on it - "pausing
    -- during intro fuckes up the sequence", 2026-11-01. Blocked, Start shuts STORROR's menu at once: pause.lua block)
    local blocked = G.pause_blocked() or (STARSEL and STARSEL.active and true or false)
        or (IN and IN.active and true or false) or (EN and EN.active and true or false)
    return { scene = G.name, can_pause = can and not blocked, blocked = blocked, can_exit = G.can_exit(), exit = G.exit_course,
             castle = G.exit_to_castle }
end

-- back to where he last came into this scene (or its start point)
-- STORROR's own "reset finished" on its locomotion and physics parts: what took him out of the stuck state (running or
-- walking on in a straight line, deaf to the stick) after a get-up was cut short, 2026-10-14
function G.reset_athlete(pawn, why)
    pawn = pawn or lib.pawn()
    if not pawn then return end
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            local cn = o:GetClass():GetFName():ToString()
            if cn == "LocomotionComponent" or cn == "HumanPhysicsComponent" then pcall(function() o:OnCharacterResetFinished() end) end
        end
    end)
    log("athlete reset: %s", tostring(why))
end

function G.respawn()
    -- (moved while knocked flat - his body fell off the arena with him down - the ragdoll is ended first and STORROR
    -- told: moved inside it, the body came along, the ragdoll took that for standing up, and STORROR was left half in
    -- its ragdoll, running him in a straight line: "charater got stuck running in a straight line again", 2026-10-14)
    if RAG and RAG.active then
        pcall(RAG.stop, true)
        G.reset_athlete(nil, "moved back while down")
    end
    local o = { respawn = true }
    for k, v in pairs(G.last_opt or {}) do if k ~= "death" then o[k] = v end end
    if G.last_node and G.arrive(G.last_node, o) then return end
    local c = G.came_in
    local pawn = lib.pawn()
    if c and c.scene == G.name and pawn then
        settle(pawn)
        pcall(function() pawn.CharacterMovement:StopMovementImmediately() end)
        pcall(function() pawn:K2_TeleportTo({ X = c.X, Y = c.Y, Z = c.Z }, { Pitch = 0.0, Yaw = c.yaw or 0.0, Roll = 0.0 }) end)
        G.freeze(0.6)
        G.air, G.no_fall_until, G.warp_cool = false, os.clock() + 3.0, 1.5
        log("respawn: where he came into %s", tostring(G.name))
        return
    end
    G.teleport_spawn()
end

-- Where a goomba and he meet (2026-10-16 "we gotta work on goomba hitboxes": they reached him from 1.3 m and could be
-- squashed from 3.4 m above). Mario 64's own boxes (goomba.inc.c sGoombaHitbox, scaled by its size as obj_set_hitbox
-- does, Mario 37 round): its hitbox 72 round, 50 high, to be landed on; its hurtbox 42 round, 40 high, to hurt him.
-- Squashed (interaction.c determine_interaction, INT_HIT_FROM_ABOVE): he is in the air, coming down, his feet above
-- its own, and touching its hitbox - or his feet went past its top since the last frame (a fast fall). Any other
-- touch of its hurtbox hurts him, in the air too (from the side, or jumping up into it), as in Mario 64.
-- (A table function, so it can be tuned in a running game.)
local PLAYER_R = 37.0 * 0.75
-- (its box to land on reaches STOMP_UP times Mario 64's height: 50 high was too little to land on it from STORROR's
-- jumps - "extend the goomba hitbox up more so you can actually hit him")
local STOMP_UP = 2.5
function G.goomba_contact(g, d, pzs, vz)
    if G.intangible() then return false, false end
    local half = G.half or 90.0
    local feet, head = pzs - half, pzs + half
    local gz = g.z + (g.hop or 0.0)
    local k = g.scale * 0.75
    -- (what its box to land on reaches past its body - Mario 64's 30 round past its 42, and STOMP_UP's height over its
    -- 50 - at most `GOOMBA_REACH` cm out and `GOOMBA_REACH_UP` up: grown with a huge one's size, Tiny-Huge Island's big
    -- ones were squashed from 2.9 m off and 4.6 m over them - from inside a pipe beside one: "big goombas hitboxes are
    -- huge", "im going down the pipe and killing the big goomba somehow", 2026-11-08. A goomba's own and a tiny one's as
    -- they were)
    local hit_r = 42.0 * k + math.min(30.0 * k, G.GOOMBA_REACH or 40.0) + PLAYER_R
    local hit_h = 50.0 * k + math.min(50.0 * k * (STOMP_UP - 1.0), G.GOOMBA_REACH_UP or 80.0)
    local hurt_r, hurt_h = 42.0 * k + PLAYER_R, 40.0 * k
    local pf = g.pf
    g.pf = feet
    local falling = not G.grounded and vz < 0.0
    local stomp = falling and d < hit_r and head > gz
        and ((feet > gz and feet < gz + hit_h) or (pf and pf >= gz + hit_h and feet < gz + hit_h))
    local hurt = not stomp and d < hurt_r and feet < gz + hurt_h and head > gz
    -- (no harm under the vanish cap - Mario 64's take_damage_and_knock_back: "when invis capped enemies should not be able to ragdol the player", 2026-10-26; stomped as ever)
    if hurt and CAPS and CAPS.on("vanish") then hurt = false end
    return stomp, hurt
end

-- Its body solid to him on the ground: inside its round (its hurtbox and his), he is pushed out to its edge, the way it
-- is going, slid by the engine along what he meets ("add collisions to them so they ... push you on the ground").
-- Knocked flat, his body is shoved instead: the parts of him it walks into pushed out from its middle, a little
-- more each frame (a steady push, like walking into him) - "they cant push the body around when your down".
local BODY_PUSH = 2500.0        -- cm/s each second, at its middle (falling off to nothing at its edge)
function G.goomba_push(g, d, dx, dy, pzs, dt)
    if G.dying or G.intangible() then return end
    local gz = g.z + (g.hop or 0.0)
    local k = g.scale * 0.75
    local R = package.loaded["ragdoll"]
    if R and R.active then
        pcall(function()
            local mesh = lib.pawn().Mesh
            local pl = mesh:GetSocketLocation(FName("pelvis"))
            local reach = 42.0 * k + 60.0           -- (its body, and his: a limb reaches out from his hips)
            local hx, hy = pl.X - OFFSET.X - g.x, pl.Y - OFFSET.Y - g.y
            if hx * hx + hy * hy < (reach + 80.0) ^ 2 and abs(pl.Z - OFFSET.Z - gz) < 150.0 * g.scale then
                mesh:AddRadialImpulse({ X = g.x + OFFSET.X, Y = g.y + OFFSET.Y, Z = gz + 20.0 * k + OFFSET.Z }, reach,
                    BODY_PUSH * (dt or 0.016), 1, true)
            end
        end)
        return
    end
    if not G.grounded then return end
    local half = G.half or 90.0
    local r = 42.0 * k + PLAYER_R
    if d >= r or pzs - half > gz + 40.0 * k or pzs + half < gz then return end
    local ux, uy = dx / math.max(d, 1.0), dy / math.max(d, 1.0)
    if d < 1.0 then ux, uy = cos(g.heading), sin(g.heading) end
    local out = r - d + 1.0
    pcall(function()
        local pawn = lib.pawn()
        local l = pawn:K2_GetActorLocation()
        pawn:K2_SetActorLocation({ X = l.X + ux * out, Y = l.Y + uy * out, Z = l.Z }, true, {}, false)
    end)
end

-- Goombas solid to each other ("they're walking through eachother"): two walking ones closer than their two bodies
-- (hurtboxes, 42 round each) are put apart, half each - not into a wall.
function G.goombas_apart()
    -- (every other frame: each time sets them wholly apart, so a frame between is nothing to see; 34 in the Bowser run
    -- made it 0.1 ms of every frame - "optimize the game", 2026-11-03)
    G.ga_frame = (G.ga_frame or 0) + 1
    if G.ga_frame % 2 == 1 then return end
    local list = G.goombas
    local function walking(g) return g.state == "wander" or g.state == "chase" end
    for i = 1, #list do
        local a = list[i]
        if walking(a) then
            for j = i + 1, #list do
                local b = list[j]
                if walking(b) and abs(a.z - b.z) < 60.0 * math.max(a.scale, b.scale) then
                    local ra, rb = 42.0 * 0.75 * a.scale, 42.0 * 0.75 * b.scale
                    local dx, dy = b.x - a.x, b.y - a.y
                    local d = sqrt(dx * dx + dy * dy)
                    if d < ra + rb then
                        if d < 1.0 then dx, dy, d = cos(a.heading or 0.0), sin(a.heading or 0.0), 1.0 end
                        local half = (ra + rb - d) / 2.0
                        local ux, uy = dx / d, dy / d
                        local ax, ay, bx, by = a.x - ux * half, a.y - uy * half, b.x + ux * half, b.y + uy * half
                        if not wall_near(ax, ay, a.z + 30.0, ra) then a.x, a.y = ax, ay end
                        if not wall_near(bx, by, b.z + 30.0, rb) then b.x, b.y = bx, by end
                    end
                end
            end
        end
    end
end

local function update_goomba(g, dt, px, py, pz, vz, cx, cy)
    local inst = g.inst
    if g.cool > 0 then g.cool = g.cool - dt end
    if g.state == "dead" then
        g.t = g.t - dt
        local k = math.max(0.05, g.t / 0.6)
        pcall(function() inst.actor:SetActorScale3D({ X = g.scale, Y = g.scale, Z = g.scale * k }) end)
        if g.t <= 0 then
            g.state, g.resp = "gone", math.huge     -- squashed is squashed: it is back when the level is entered again
            pcall(function() inst.actor:SetActorHiddenInGame(true) end)
            -- (gone in a white puff: spawn_mist_particles_with_sound)
            if ENVFX and ENVFX.poof then pcall(ENVFX.poof, g.x, g.y, g.z + 30.0 * g.scale / G.GOOMBA_SIZE, math.max(0.6, g.scale / G.GOOMBA_SIZE)) end
        end
        return
    elseif g.state == "gone" then
        g.resp = g.resp - dt
        if g.resp <= 0 then
            g.x, g.y = g.hx, g.hy
            g.state = "wander"
            pcall(function() inst.actor:SetActorHiddenInGame(false) end)
            pcall(function() inst.actor:SetActorScale3D({ X = g.scale, Y = g.scale, Z = g.scale }) end)
        end
        return
    end

    local d, dx, dy = dist2(px - OFFSET.X, py - OFFSET.Y, g.x, g.y)
    -- (or near the ending's camera: its credits look at goombas far from him - enemies.lua near_view)
    if d > 6000 and not (G.ending_on() and dist2(cx - OFFSET.X, cy - OFFSET.Y, g.x, g.y) < 11000) then return end
    local pzs = pz - OFFSET.Z

    -- Mario 64's goomba: ambles about and hops now and then; when Mario comes close it starts with a
    -- little jump, then charges. It turns and picks up speed gradually rather than snapping.
    if g.state == "wander" and d < 750 and abs(pzs - g.z) < 400 then
        g.state = "chase"
        if (g.hop or 0) <= 0 then g.vz = 420.0 end              -- the jump of alarm
        sfx("en_goomba_alert", math.max(0.0, 1.0 - d / 3000.0))   -- (goomba.inc.c goomba_begin_jump: SOUND_OBJ_GOOMBA_ALERT)
    elseif g.state == "chase" and (d > 1500 or abs(pzs - g.z) > 600) then
        g.state = "wander"
        g.want = g.heading
    end

    local target, speed
    if g.state == "chase" then
        target = atan(dy, dx)
        speed = 190.0
    else
        g.turn_t = g.turn_t - dt
        if g.turn_t <= 0 then
            g.turn_t = 2.0 + math.random() * 3
            g.want = g.heading + rad(math.random(-100, 100))
            if math.random(1, 4) == 1 and (g.hop or 0) <= 0 then g.vz = 300.0 end   -- a hop for no reason, as they do
            local hd = dist2(g.x, g.y, g.hx, g.hy)
            if hd > 1200 then g.want = atan(g.hy - g.y, g.hx - g.x) end
        end
        target = g.want or g.heading
        speed = 36.0
    end
    local pi = math.pi
    local diff = (target - g.heading + pi) % (2 * pi) - pi
    local turn = ((g.state == "chase") and 5.5 or 2.2) * dt
    g.heading = g.heading + math.max(-turn, math.min(turn, diff))
    g.spd = g.spd or 0.0
    g.spd = g.spd + math.max(-500.0 * dt, math.min(500.0 * dt, speed - g.spd))

    g.hop, g.vz = g.hop or 0.0, g.vz or 0.0
    if g.hop > 0 or g.vz > 0 then
        g.hop = g.hop + g.vz * dt
        g.vz = g.vz - 1900.0 * dt
        if g.hop <= 0 then g.hop, g.vz = 0.0, 0.0 end
    end

    local nx, ny = g.x + cos(g.heading) * g.spd * dt, g.y + sin(g.heading) * g.spd * dt
    -- (the level's walls - fences too - stop it: out of them, turned away; Mario 64's goombas resolve wall
    -- collisions and turn about. Its body: its hurtbox, 42 round.)
    local wall, wx, wy = wall_near(nx, ny, g.z + 30.0, 42.0 * 0.75 * g.scale)
    if wall then
        nx, ny = nx + wx, ny + wy
        if g.state ~= "chase" and (wx ~= 0.0 or wy ~= 0.0) then
            g.heading = atan(wy, wx) + rad(math.random(-45, 45))
            g.want, g.turn_t = g.heading, 1.0
        end
    end
    local fz = floor_z(nx, ny, g.z + 70)
    -- (not in under a floor low over it: the pyramid's raised floor, 96 cm over its walkway and open at its sides - one
    -- went in under it, out of sight, and met him through it: "invisable goomba up here", 2026-10-23. From under one
    -- already, it may walk on out.)
    if fz then
        local over = floor_z(nx, ny, fz + 150.0)
        if over and over > fz + 20.0 then
            local here = floor_z(g.x, g.y, g.z + 150.0)
            if not (here and here > g.z + 20.0) then fz = nil end
        end
    end
    -- (and the water kept out of, as enemies.lua's walkers keep out of it: its edge is an edge, as a drop is. Tall, Tall
    -- Mountain's goombas walked the pond's bed under the water: "goombas straight up walkin underwater", 2026-10-26; one
    -- in it walked its top, and walked off ledges into the sea and on over it: "goombas walk over ledges and walk on
    -- water", 2026-11-08. One in it now only steps out onto dry ground)
    if fz then
        local wt = water_at(nx, ny)
        if wt and wt > fz + 5.0 then fz = nil end
    end
    -- (no step down more than `GOOMBA_DROP` cm: Mario 64's goombas move carefully, cur_obj_move_standard(-78) - a floor
    -- more than 50 units under them is an edge, OBJ_MOVE_HIT_EDGE. 1.6 m took them over the islands' ledges)
    if fz and fz > g.z - (G.GOOMBA_DROP or 37.5) then
        g.x, g.y, g.z = nx, ny, fz
    else
        -- an edge or a wall: turn away from it
        g.heading = g.heading + rad(150 + math.random(0, 60))
        g.want = g.heading
        g.turn_t = 1.0
    end
    -- (its floor the lava: gone at once in a puff, with the death sound, its coin left - Mario 64's goombas die the
    -- moment there is lava under them, obj_die_if_above_lava_and_health_non_positive: "goombas walkin on lava",
    -- 2026-10-24)
    if G.lava_z then
        local lz = G.lava_z(g.x, g.y, g.z + 70.0)
        if lz and abs(lz - g.z) < 10.0 then
            g.state, g.resp = "gone", math.huge
            pcall(function() inst.actor:SetActorHiddenInGame(true) end)
            if ENVFX and ENVFX.poof then pcall(ENVFX.poof, g.x, g.y, g.z + 30.0 * g.scale / G.GOOMBA_SIZE, math.max(0.6, g.scale / G.GOOMBA_SIZE)) end
            sfx("en_default_death", math.max(0.0, 1.0 - d / 3000.0))
            G.spawn_coin(g.x, g.y, g.z + 40.0)
            log("goomba: into the lava")
            return
        end
    end
    local yawd = deg(g.heading) + 180.0
    lib.set_pose(inst, g.x + OFFSET.X, g.y + OFFSET.Y, g.z + g.hop + OFFSET.Z, yawd)

    -- the walk plays as fast as the feet are moving, every tick, blended between frames
    local anim = inst.data.anims[1]
    local f0 = g.f
    g.f = g.f + dt * 30.0 * math.min(2.4, 0.5 + g.spd / 80.0)
    if anim then lib.pose(inst, anim, g.f) end
    -- its feet heard (goomba.inc.c goomba_act_walk: SOUND_OBJ_GOOMBA_WALK at frames 2 and 17 of its walk, while it goes
    -- fast - after him), fainter the further it is ("do the goombas not have a walking audio?")
    if anim and g.state == "chase" and g.spd > 100.0 and floor(g.f) ~= floor(f0) then
        local k = floor(g.f) % (anim.frames or 20)
        if k == 2 or k == 17 then sfx("goomba_walk", math.max(0.0, 1.0 - d / 2500.0) * math.min(1.0, g.scale / G.GOOMBA_SIZE)) end
    end
    lib.face_camera(inst, g.x + OFFSET.X, g.y + OFFSET.Y, cx, cy)

    -- meeting the player: landed on from above it is squashed for good and leaves a coin; touched any other way, it
    -- knocks him down (his own ragdoll) and costs power. While he is down or still flashing it cannot hit again.
    -- (a floor between them - he up on a floor over it, it under that floor - and nothing meets: no stomp, no hurt, no
    -- push through it)
    local between = floor_z(g.x, g.y, pzs - 80.0)
    if between and between > g.z + 20.0 then return end
    local stomp, hurt = G.goomba_contact(g, d, pzs, vz)
    if not stomp then G.goomba_push(g, d, dx, dy, pzs, dt) end
    if stomp or hurt then
        if stomp then
            g.state, g.t = "dead", 0.6
            sound(g.scale > 3.0 and "goomba_stomp_huge" or "goomba_stomp")
            -- a hop off its head, not a launch - and his way on kept ("make sure the player keeps his kinetic energy")
            pcall(function() lib.pawn():LaunchCharacter({ X = 0.0, Y = 0.0, Z = 560.0 }, false, true) end)
            -- (a huge one squashed by Mario 64's ground pound leaves a blue coin - ATTACK_HANDLER_SQUISHED_WITH_BLUE_COIN; here
            -- the air kick stands for it, as platforms.lua counts it)
            local blue = false
            if g.scale > 3.0 then
                pcall(function()
                    local ai = lib.pawn().Mesh:GetAnimInstance()
                    local mt = ai and ai:IsValid() and ai:GetCurrentActiveMontage()
                    if mt and mt:IsValid() then
                        local mn = mt:GetFName():ToString()
                        blue = mn:find("Attack") ~= nil or mn:lower():find("kick") ~= nil
                    end
                end)
            end
            G.spawn_coin(g.x, g.y, g.z + 40.0, blue)
            log("goomba stomped%s", blue and " with a kick: a blue coin" or "")
        elseif g.cool <= 0 then
            local HP = _G.HEALTH
            if not (HP and (HP.grace > 0 or HP.dead_t)) then
                g.cool = 4.5
                local ux, uy = dx / math.max(d, 1), dy / math.max(d, 1)
                local kind = (g.scale > 3.0) and "goomba_huge" or ((g.scale < 1.0) and "goomba_tiny" or "goomba")
                if HP then
                    HP.damage(HP.DAMAGE[kind], "a goomba")
                    HP.grace = math.max(HP.grace, 4.5)    -- time to get back up and away
                end
                G.knock_down(lib.pawn(), ux * 650, uy * 650, 420)
            end
        end
    end
end

-- Hit by something thrown (boxes.lua's small box, 2026-10-17: "when you throw it at enemies or boxes they dont break
-- die"): goombas within `reach` cm of (x, y, z) - scene space - are beaten as by a stomp, and leave their coin. How many.
function G.goomba_hit_at(x, y, z, reach)
    local n = 0
    for _, g in ipairs(G.goombas) do
        if g.state ~= "dead" and g.state ~= "gone" then
            local r = reach + 40.0 * g.scale
            local h = 110.0 * g.scale
            if dist2(g.x, g.y, x, y) < r and z > g.z - reach and z < g.z + h + reach then
                g.state, g.t = "dead", 0.6
                sound(g.scale > 3.0 and "goomba_stomp_huge" or "goomba_stomp")
                G.spawn_coin(g.x, g.y, g.z + 40.0, false)
                n = n + 1
                log("goomba hit by a thrown box")
            end
        end
    end
    return n
end

local DOOR_OPEN_FRAME = 30.0     -- by this frame of the door's animation it stands wide open
-- Doors open as he comes near ("I also want to fix all the doors in the castle and levels can they just open when the
-- player comes near them", 2026-11-06): a door he may go through - no lock, its unlocking done - swings open once he is
-- within DOOR_NEAR cm in front of it or behind it and DOOR_NEAR_ACROSS of its middle along it, whichever way he faces or
-- goes; a star door slides open from STARDOOR_NEAR and shuts past STARDOOR_SHUT. A locked one's message, and the first
-- unlocking, still wait for him to come right up to it.
-- (then from further off - "just make the doors open from a little further away", 2026-11-06 - and let close only
-- once he is DOOR_SHUT cm off)
-- (and further off again, and quicker - "make doors open faster and from further", 2026-11-06: a door swings open
-- DOOR_OPEN_SPEED times its animation's pace, shutting at its own; a star door slides open in STARDOOR_TIME s)
G.DOOR_NEAR, G.DOOR_NEAR_ACROSS, G.DOOR_SHUT = 500.0, 220.0, 700.0
G.STARDOOR_NEAR, G.STARDOOR_SHUT = 550.0, 700.0
G.DOOR_OPEN_SPEED, G.STARDOOR_TIME = 2.5, 0.3
-- whether he may go through door d now: no lock on it, and its unlocking (G.door_unlock_due) done
function G.door_free(d)
    if G.door_lock(d.need, d.key) then return false end
    local MN = _G.MENU
    local flag = G.door_flag(d.need, d.key, d.x, d.y, d.z)
    if flag and MN and MN.has_flag and not MN.has_flag(flag) then return false end
    return true
end

-- Two leaves of a double door are the same door turned to face each other, so left alone one swings in
-- and the other out. The second of each such pair plays its swing mirrored, and the pair then opens as one.
local function pair_doors()
    for i = 1, #G.doors do
        for j = i + 1, #G.doors do
            local a, b = G.doors[i], G.doors[j]
            local turned = abs(((a.yaw - b.yaw) % 360.0) - 180.0) < 10.0
            if turned and dist2(a.x, a.y, b.x, b.y) < 260.0 and abs(a.z - b.z) < 60.0 and not a.mirror then
                b.mirror = true
                b.inst.mirror = true
            end
        end
    end
end

-- A door opens as the player comes up to it and waits open while he is near. Walking through the
-- doorway (his side of the door changing, within its width) is what takes him to the next place:
-- standing in front of an open door does nothing.
local function update_door(dr, dt, px, py, pz)
    local x, y, z = px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z
    local d, dx, dy = dist2(x, y, dr.x, dr.y)
    local anims = dr.data.anims
    local fx, fy = -cos(rad(dr.yaw)), -sin(rad(dr.yaw))       -- the way the door faces
    local side = dx * fx + dy * fy                            -- in front of the door (+) or behind it (-)
    -- (his feet at its threshold - a metre under it for stairs up to it, 1.5 m over for a jump: his middle within
    -- 3.5 m of it either way had the upstairs key door telling him it was locked from the passage under its landing,
    -- "the upstairs key door is triggering undernieth the floor", 2026-10-22)
    local feet = z - (G.half or 90.0)
    local level = feet > dr.z - 100.0 and feet < dr.z + 150.0
    local across = abs(-dx * fy + dy * fx)                     -- how far along the door from its middle
    if dr.f < 0 then
        -- (solid again once he is clear of it: never shut on him where he stands in the doorway)
        if abs(side) > 60 or across > 75 then door_solid(dr, true) end
        if abs(side) > 150 or across > 150 then dr.armed, dr.told = true, nil end
        if dr.exit_only then return end         -- (one he only comes out of: shut to him - G.EXIT_ONLY_DOORS)
        -- Mario 64 opens a door as Mario walks into it (interact_door): shut and solid until the athlete is up against
        -- this leaf - within 130 cm of it, the leaf being 60 cm thick with its knobs - and moving into it or facing it;
        -- the leaf of a double door he is at, not the other. (It opened as he came within 3 m, and went soft as it
        -- swung, 2026-10-15. Read only at the door he is at: reading the keys and the stick for every door every
        -- frame brought the game down, and a reach of 85 cm left him shut outside, "im trapped inside the doors".)
        local into = false
        local close = dr.armed and abs(side) < 130 and across < 75 and level
        -- (near enough, and free to go through: opened as if he walked into it - G.DOOR_NEAR)
        if not close and dr.armed and level and abs(side) < (G.DOOR_NEAR or 0.0) and across < (G.DOOR_NEAR_ACROSS or 0.0)
            and G.warp_cool <= 0 and not G.swim and not dr.pass and G.door_free and G.door_free(dr) then
            close = true
        end
        if close then
            pcall(function()
                local pawn = lib.pawn()
                local v = pawn:GetVelocity()
                local along = v.X * fx + v.Y * fy
                if side > 0 then along = -along end
                local yaw = rad(pawn:K2_GetActorRotation().Yaw)
                local tl = sqrt(dx * dx + dy * dy)
                local facing = tl > 1.0 and (cos(yaw) * -dx + sin(yaw) * -dy) / tl > 0.6
                into = along > 40.0 or facing
                -- (a door free to go through needs neither)
                if not into and G.door_free and G.door_free(dr) then into = true end
            end)
        end
        if close and into and G.warp_cool <= 0 and not G.swim and not dr.pass then
            local msg, var, pass = G.door_lock(dr.need, dr.key)
            if msg then
                -- (locked: shut and solid, its message once till he has stepped away; the 70 one opens after it)
                if not dr.told and not (DIALOG and DIALOG.active) then
                    dr.told = true
                    -- (and the other leaf of a double door told with it: shut, he was still against the pair and the
                    -- other leaf said it again - "locked doors dialog trigger twice", 2026-11-01)
                    for _, o in ipairs(G.doors or {}) do
                        if o ~= dr and o.need == dr.need and o.key == dr.key and dist2(o.x, o.y, dr.x, dr.y) < 250.0 then
                            o.told = true
                        end
                    end
                    G.say(msg, pass and function() dr.pass = true end or nil, var)
                end
                return
            end
            if G.door_unlock_due(dr, G.doors, fx, fy) then return end
        end
        if dr.pass and close then dr.pass, into = nil, true end
        -- (and shut while a message is up: the star door's DIALOG_038 was still being read as it swung open - "also
        -- the doors open before dialog ends", 2026-10-20)
        if (DIALOG and DIALOG.active) or G.unlocking then into = false end
        if close and into and G.warp_cool <= 0 and not G.swim then
            -- (it swings away from him, the way he is going: both of the model's swings turn the leaf toward its back,
            -- played mirrored toward its front - each leaf by his side of it, so the two of a double door go the same
            -- way. Before, a pair always swung one way, toward him from the other side - "you have to make doors open
            -- in the direction you walking through them", 2026-10-15)
            dr.anim = 2
            dr.inst.mirror = side < 0
            dr.f, dr.armed, dr.from, dr.through = 0.0, false, (side > 0) and 1 or -1, false
            local iron = dr.style == "metal" or dr.style == "hmc"
            sfx(iron and "door_iron_open" or "door_wood_open")
        end
        return
    end

    local a = anims[dr.anim]
    if not dr.through then
        local lateral = abs(-dx * fy + dy * fx)
        -- a door to another place has a wall behind it, so "through" there is reaching the open doorway itself
        local reached = dr.target and (dr.f >= 18 and side * dr.from < 40) or (side * dr.from < -25)
        if level and lateral < 130 and reached then
            dr.through = true
            -- Mario 64's rule: in by the back of a door, out by the front of the one it leads to (and the other way round)
            -- (level_update.c init_door_warp: out along the door he arrives at, turned round when he pushed this one
            -- open from its front - interaction.c should_push_or_pull_door. Each leaf by its own facing, the turned
            -- leaf of a double door too: taken by its partner's facing, the castle's right front door put him out in
            -- the black behind the doors, 2026-10-15 "fix the spawn location for the front door of the castle".)
            local flip = dr.from > 0
            if dr.target and not G.pending and not G.cutscene then G.warp_out("door", dr.target, dr.dest, { flip = flip }) end
        elseif d > (G.DOOR_SHUT or 420.0) or not level then
            dr.through = true                                 -- he walked away: let it close
        end
    end
    -- (the leaf stays solid as it swings away from him; swinging back shut it would close on him in the doorway: there,
    -- not solid until he is clear)
    if dr.through and abs(side) < 60 and across < 75 then door_solid(dr, false) end
    if dr.f < DOOR_OPEN_FRAME or dr.through then
        local pace = (not dr.through and dr.f < DOOR_OPEN_FRAME) and (G.DOOR_OPEN_SPEED or 1.0) or 1.0
        dr.f = dr.f + dt * 30.0 * pace
        if not dr.through and dr.f > DOOR_OPEN_FRAME then dr.f = DOOR_OPEN_FRAME end
    end
    if a then lib.pose(dr.inst, a, math.min(dr.f, a.frames - 1)) end
    if not a or dr.f >= a.frames - 1 then
        if dr.f >= 0 and not dr.target then
            local iron = dr.style == "metal" or dr.style == "hmc"
            sfx(iron and "door_iron_close" or "door_wood_close", 0.8)
        end
        dr.f = -1
        if anims[1] then lib.pose(dr.inst, anims[1], 0) end
    end
end

-- ------------------------------------------------------------ floors that mean something
-- Mario 64 gives some floor triangles a meaning of their own, and whatever floor is under Mario decides
-- what happens to him: the strip behind a painting takes him into it, lava burns, the plane under a
-- level is the end of a fall, and some floors hand over to the next area. `G.rule` holds those
-- triangles; this looks up the one under the player's feet (x, y, z in scene space, z at his feet).
local function game_over()
    local HP = _G.HEALTH
    HP.reset()                      -- (his death over: it started a second close behind the GAME OVER screen)
    HP.lives = HP.START_LIVES
    log("game over")
    HP.hud_hide()
    G.dying, G.entry, G.mama_at, G.warping, G.pinned = nil, nil, nil, false, false
    if TRANS then TRANS.clear() end
    music_back()
    local MN = _G.MENU
    if MN then
        if MN.game_over then MN.game_over() else MN.back_to_menu() end
    end
end

-- ------------------------------------------------------------ death (level_update.c)
-- Out of power: his cry and his fall, then the screen closes in on him in the shape of Bowser's head over 48 frames
-- with Bowser's laugh (WARP_OP_DEATH). Off the bottom of a course: a circle over 20 frames (WARP_OP_WARP_FLOOR).
-- Behind the black: a "warp floor" exit (0xF3) just puts him outside; else, with no lives left, the game is over;
-- else out of the course to its death node (0xF1), where the life is taken as he lands there (act_death_exit and its
-- kin), with one wedge of power that then fills back up. Before (2026-10-15: "next I want to work on death") he lay
-- 2.5 s and it cut straight to the castle, and a fall cut at once.
G.dying = nil           -- { kind = "power"/"fall", why, black }
-- (courses whose bottom is a death here, though Mario 64's warp floor only puts him outside: Vanish Cap Under the Moat -
-- "falling in that world doesnt count as a death", 2026-10-19. Out to its death node, the life taken on landing.)
G.FALL_COSTS_LIFE = { vcutm = true }
local function death_warp(d)
    -- (HUMAN MODE's gore put back - his body his own again - while the screen is closed: gore.lua)
    do local GO = package.loaded["gore"]; if GO and GO.clear then pcall(GO.clear) end end
    if CAPS and CAPS.on() then pcall(CAPS.stop, true) end
    -- (a burn still going took the one wedge he comes back with as he arrived, and he died twice for one death -
    -- out of Bowser's fight, 2026-10-18: two lives gone, and no way out of the pipe)
    local BU = package.loaded["burn"]
    if BU and BU.active then pcall(BU.stop, true) end
    local HP = _G.HEALTH
    G.air, G.warp_cool = false, 2.0
    local pawn = lib.pawn()
    -- (the race's developer mode: a death in a race goes back to its last flag taken, the race and its recording taken
    -- back there, no life lost - race.lua M.dev_respawn)
    do
        local RCd = package.loaded["race"]
        if RCd and RCd.dev_respawn and pawn and RCd.dev_on and RCd.dev_on() then
            if HP then HP.reset() end
            G.breath_hold, G.revived_at = os.clock() + 2.5, os.clock()
            pcall(G.set_down_for_good, false, pawn)
            pcall(G.get_up, pawn, true)
            local okr, did = pcall(RCd.dev_respawn, pawn)
            if okr and did then
                G.air, G.no_fall_until = false, os.clock() + 1.0
                if TRANS then TRANS.open("star", 16) end
                return
            end
            if not okr then log("race (dev): the respawn failed: %s", tostring(did)) end
        end
    end
    if d.kind == "fall" and G.warp[0xF3] and not G.FALL_COSTS_LIFE[G.name or ""] then
        local w = G.warp[0xF3]
        log("%s: out by the warp floor", tostring(d.why))
        G.goto_scene(w.scene, w.node, { landed = true })
        return
    end
    -- (IRONMAN MODE: no life to lose - the file wiped and back to the file select: menu.lua M.ironman_wipe)
    local MNi = _G.MENU
    if MNi and MNi.ironman_on and MNi.ironman_on() then
        if HP then HP.reset() end
        log("%s: IRONMAN - the run is over", tostring(d.why))
        if HP and HP.hud_hide then HP.hud_hide() end
        G.dying, G.entry, G.mama_at, G.warping, G.pinned = nil, nil, nil, false, false
        if TRANS then TRANS.clear() end
        music_back()
        pcall(function() require("game").destroy_scene() end)
        if MNi.ironman_wipe then MNi.ironman_wipe() else MNi.back_to_menu() end
        return
    end
    if HP and HP.lives <= 0 then
        if TRANS then TRANS.clear() end
        game_over()
        return
    end
    if HP then HP.health, HP.hurt, HP.mend, HP.grace, HP.dead_t = 0x100, 0, 0, 2.0, nil end
    -- (just revived: not out of power again for a moment, whatever drains it - one death cost two lives on landing in
    -- the castle from Tiny-Huge Island, 2026-10-18, with nothing in the log to say what took the last wedge)
    G.breath_hold = os.clock() + 2.5
    G.revived_at = os.clock()
    G.set_down_for_good(false, pawn)
    if pawn then G.get_up(pawn, true) end
    local w = G.warp[0xF1]
    if w then
        -- (the life taken here, with the warp: taken when he landed on the far side, it was never taken if he did not
        -- land as a death exit does - knocked limp as the screen closed, 2026-10-23)
        if HP then HP.lives = HP.lives - 1; HP.mend = 31; log("%s: lost a life, %d left", tostring(d.why), HP.lives) end
        G.goto_scene(w.scene, w.node, { death = true })
    else
        -- (nowhere to be thrown out to: the life is taken here, and he starts again where he came in)
        if HP then HP.lives = HP.lives - 1; HP.mend = 31; log("%s: lost a life, %d left", tostring(d.why), HP.lives) end
        G.respawn()
        if TRANS then TRANS.open("star", 16) end
    end
end

-- HUMAN MODE's death (health.lua M.human_death): his whole body thrown back and up off his feet by STORROR's ragdoll, a
-- crack of bone and his cry, a thud as he comes down, the screen red a moment; the screen closes on him later than on a
-- plain death, `wait` s after - "you die gruesomely", 2026-11-02.
-- (`throw`: his body thrown `back` and `up` by it - off: the hit's own knock-back only, as in a plain game - "return it to
-- normal", 2026-11-03, of the throw that sent him flying)
-- (`gore`: his hands, arms, head, legs and feet come off, bleeding - gore.lua: "on hit I want the hands arms head legs and
-- feet to fall off, and I want blood to come from each part", 2026-11-03; `wait` a second longer for it)
G.HUMAN_DEATH = { throw = false, gore = true, back = 1500.0, up = 1100.0, wait = 4.0, red = 0.45, red_t = 0.9 }
G.gore = nil                -- { t, thud, veil, img }
function G.gruesome_death(pawn)
    local H = G.HUMAN_DEATH
    local fx, fy = 1.0, 0.0
    pcall(function() local f = pawn:GetActorForwardVector(); fx, fy = f.X, f.Y end)
    sfx("hit_crack")
    sfx("mario_dying")
    sfx("mario_attacked")
    if G.shake_camera then pcall(G.shake_camera, 2.6) end
    if H.throw then G.knock_down(pawn, -fx * H.back, -fy * H.back, H.up, true)
    else G.knock_down(pawn, 0, 0, 300) end          -- (a plain death's: down where he stands)
    if H.gore then
        local okg, GO = pcall(require, "gore")
        if okg and GO then
            local oks, errs = pcall(GO.start, pawn, { death = true })
            if not oks then log("gore: %s", tostring(errs)) end
        end
    end
    G.gore = { t = 0.0, thud = false }
    -- (the screen red a moment)
    pcall(function()
        local pc = lib.controller()
        local function cls(p) return StaticFindObject(p) end
        _G.SM64_GORE_N = (_G.SM64_GORE_N or 0) + 1
        local n = "SM64Gore" .. _G.SM64_GORE_N
        local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName(n))
        local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName(n .. "Tree"))
        w.WidgetTree = tree
        local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName(n .. "Canvas"))
        tree.RootWidget = canvas
        local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName(n .. "Img"))
        img:SetColorAndOpacity({ R = 0.6, G = 0.0, B = 0.0, A = 1.0 })
        local slot = canvas:AddChildToCanvas(img)
        slot:SetAnchors({ Minimum = { X = 0.0, Y = 0.0 }, Maximum = { X = 1.0, Y = 1.0 } })
        slot:SetOffsets({ Left = 0.0, Top = 0.0, Right = 0.0, Bottom = 0.0 })
        img:SetRenderOpacity(H.red)
        w:AddToViewport(95)
        G.gore.veil, G.gore.img = w, img
    end)
    log("HUMAN MODE: a gruesome death")
end
function G.gruesome_tick(dt)
    local g = G.gore
    if not g then return end
    g.t = g.t + math.min(dt, 0.1)
    local H = G.HUMAN_DEATH
    if not g.thud and g.t > 0.75 then g.thud = true; sfx("body_hit_ground") end
    if g.img then
        local a = math.max(0.0, H.red * (1.0 - g.t / H.red_t))
        pcall(function() g.img:SetRenderOpacity(a) end)
        if a <= 0.0 then pcall(function() g.veil:RemoveFromParent() end); g.img, g.veil = nil, nil end
    end
    if g.t > H.wait + 1.0 then G.gore = nil end
end

function G.die(kind, why)
    if G.dying then return end
    local d = { kind = kind, why = why }
    G.dying = d
    -- (whatever the death - out of power, a fall, a crushing - his controls off till he is back: G.set_down_for_good;
    -- "its not a bug speciefic to lava", 2026-10-19)
    pcall(G.set_down_for_good, true)
    log("%s: the screen closes (%s)", tostring(why), kind)
    if kind ~= "fall" then sfx("menu_bowser_laugh") end
    music_fade(kind == "fall" and 20 or 48)
    if TRANS then
        TRANS.close(kind == "fall" and "circle" or "bowser", kind == "fall" and 20 or 48, function() d.black = true end)
    else
        d.black = true
    end
end

-- Fallen out of the level.
function G.fall_out(why)
    if G.dying then return end
    -- (not in the ending: it plays on where the Grand Star was taken - over the void, for Bowser's mega star)
    local EN = package.loaded["ending"]
    if EN and EN.active then return end
    G.die("fall", why)
end

-- The edge of the level. Mario 64 never lets Mario step where there is no ground under him at all: past the
-- last floor of a level is as good as a wall, and he stops there. The athlete gets the same invisible wall,
-- which also keeps him from climbing or jumping out over a level's outer walls. The planes under a course
-- (falling onto one costs a life) and the other special floors count as ground, as they do in the game.
-- x, y, z: his middle, world space. Returns true when he was put back.
local function keep_in_level(pawn, x, y, z)
    if not G.bounds or G.pending or G.warp_cool > 0 or G.thaw_at or os.clock() < (G.no_fall_until or 0) then
        G.inside = nil
        return false
    end
    local HP = _G.HEALTH
    if HP and HP.dead_t then return false end
    if PLAT.on then G.inside = { x, y }; return false end      -- a platform is ground wherever it goes
    -- (and one just under his feet, though the check of who stands on what missed him this frame: a carpet climbing its
    -- line is a step ahead of that check, and at the level's edge he was held back as it went on without him, and fell
    -- - Rainbow Ride's first carpet, 2026-10-31)
    if PLAT.top_under then
        local fz = z - OFFSET.Z - (G.half or 90.0)
        local okt, top = pcall(PLAT.top_under, x - OFFSET.X, y - OFFSET.Y, fz)
        if okt and top and fz - top < 300.0 then G.inside = { x, y }; return false end
    end
    -- (on a tree or pole to climb, or round it - climb.lua: Jolly Roger Bay's climbable spikes stand on no floor at all,
    -- their foot over the sea bed, and holding one, or stepping off its top, put him back where he last had ground under
    -- him, every frame - "getting stuck on them", "still stuck on top of spike", 2026-10-18)
    if G.carried == "pole" then G.inside = { x, y }; return false end
    local CLM = package.loaded["climb"]
    if CLM and CLM.near_trunk and CLM.near_trunk(x, y, z) then G.inside = { x, y }; return false end
    local sx, sy, sz = x - OFFSET.X, y - OFFSET.Y, z - OFFSET.Z + 20.0
    if floor_hit(G.bounds, sx, sy, sz) or floor_hit(G.rule, sx, sy, sz) then
        G.inside = { x, y }
        return false
    end
    -- (a small hole in the floors - a spike's foot stands on none, poled or not - is not the edge of the level: with
    -- ground 1.8 m out on six sides of eight he goes on over it; "hit an invisable wall when jumping off the spike",
    -- 2026-10-18)
    local around = 0
    for k = 0, 7 do
        local ax, ay = sx + cos(k * math.pi / 4.0) * 180.0, sy + sin(k * math.pi / 4.0) * 180.0
        if floor_hit(G.bounds, ax, ay, sz) or floor_hit(G.rule, ax, ay, sz) then around = around + 1 end
    end
    if around >= 6 then return false end
    -- (nor the hole in the bed a whirlpool or jet stream comes out of: Dire, Dire Docks' jet stream rises from one 4.5 m
    -- across, the star beside it, and it held him back like a wall - "invisable wall next to water vortex star",
    -- 2026-10-23)
    for _, w in ipairs((G.data and G.data.whirlpools) or {}) do
        local wx, wy = -w.pos[3] * 0.75, w.pos[1] * 0.75
        if (sx - wx) ^ 2 + (sy - wy) ^ 2 < 800.0 * 800.0 then G.inside = { x, y }; return false end
    end
    local back = G.inside
    if not back then return false end
    -- back to the last place with ground under it, at the height he is at now, and no further that way
    local rot = { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }
    pcall(function() rot = pawn:K2_GetActorRotation() end)
    local moved = false
    pcall(function() moved = pawn:K2_TeleportTo({ X = back[1], Y = back[2], Z = z }, rot) end)
    pcall(function()
        local v = pawn.CharacterMovement.Velocity
        pawn.CharacterMovement.Velocity = { X = 0.0, Y = 0.0, Z = v.Z }
    end)
    if not G.edge_said then G.edge_said = true; log("edge of the level: held back (%s)", tostring(moved)) end
    G.edge_at = os.clock()          -- (flight.lua: flown into it, a wall)
    return true
end
G.keep_in_level = keep_in_level

-- Touching the lava: `above`, his feet over its surface (cm, under 12). (update_floors: the level's lava under him, or a
-- platform he stands on sunk into it.)
function G.lava_touch(pawn, above)
    local HP = _G.HEALTH
    -- (check_lava_boost: every touch of the lava throws him off it - hurt only when he can be; the leap was held
    -- back with the hurt, and he lay in it. Limp, his body itself is thrown: a launch moves only the capsule -
    -- "when ragdolling on lava it doesnt make the player bounce on the lava like normal", 2026-10-19)
    -- (but not hanging from a ledge or climbing up it - Mario 64 looks for lava only in his steps on the ground and
    -- in the air, never in ACT_LEDGE_GRAB: hung from a low ledge over the lava his feet were in it, the leap could
    -- not pull him off STORROR's hold, and he was hurt again and again there - "when getting burned by lava and
    -- trying to grab ledge player gets stuck in lava", 2026-10-24)
    local ledge, mt = false, "-"
    if above < 12.0 then
        pcall(function() ledge = pawn.CharacterMovement:IsClimbing() and true or false end)
        pcall(function()
            local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
            if m and m:IsValid() then mt = m:GetFName():ToString() end
        end)
        if mt:find("Climb", 1, true) then ledge = true end
    end
    if above < 12.0 and os.clock() - (G.lava_said or 0.0) > 0.5 then
        G.lava_said = os.clock()
        local mode = "?"
        pcall(function() mode = tostring(pawn.CharacterMovement.MovementMode) end)
        log("lava: touched (%.0f cm, mode %s, montage %s%s)", above, mode, mt:sub(1, 40), ledge and ", on a ledge: let be" or "")
    end
    if ledge then
        -- (nothing)
    elseif above < 12.0 and HP and not HP.dead_t and os.clock() - (G.lava_at or 0.0) > 0.25 then
        G.lava_at = os.clock()
        -- (metal: the leap off it, and no harm - check_lava_boost)
        if not (CAPS and CAPS.on("metal")) and HP.grace <= 0 then
            HP.damage(HP.DAMAGE.fire, "lava")
            local BU = package.loaded["burn"]
            if BU and BU.lava then pcall(BU.lava) end      -- (the flames under him on the way up: burn.lua)
        end
        sfx("en_flame_blown")
        local RG = package.loaded["ragdoll"]
        if (RG and RG.active) or G.getup_at then
            pcall(function() pawn.Mesh:AddImpulseToAllBodiesBelow({ X = 0.0, Y = 0.0, Z = 1500.0 }, FName("pelvis"), true, true) end)
        end
        G.lava_boost(pawn)                      -- Mario 64's leap off the lava
    end
end

G.STAIRS_TUNE, G.STAIRS_HOLD = "event_endless_stairs", 8.0
function G.stairs_tune()
    if not G.stairs_t or os.clock() - G.stairs_t < G.STAIRS_HOLD then return end
    G.stairs_t = nil
    if MUSIC and MUSIC.current == G.STAIRS_TUNE and G.data then pcall(MUSIC.play, G.music_override or G.data.music) end
end
-- The endless stairs (level_update.c check_instant_warp): in the castle, while the file has fewer than 70 stars, the
-- floor near the top of the stairs puts him back down them by its displacement, he and his view moved alike; with 70,
-- nothing. They led straight up before. `w`: the scene's instant warp (data.instant) whose floor he is on.
function G.stairs_loop(pawn, w)
    local MN = _G.MENU
    local stars = (MN and MN.star_count and MN.star_count()) or 0
    if not (G.level_of(G.name) == G.level_of("castle") and stars < 70 and os.clock() >= (G.instant_cool or 0.0)) then return end
    G.instant_cool = os.clock() + 0.3
    local m = w.move
    -- (moved by exactly the displacement, as Mario 64 moves him, so the stairs round him are the same as before and
    -- nothing is seen to change: set where he is, not teleported - a teleport looks for room round him and can put him
    -- off by the steps' edges - and the view told it is a cut, so its blur and smoothing do not smear 3.4 m of jump
    -- across the picture; his hair carried with him, not flung off his head (his clothes' cloth sees the jump itself,
    -- apply_walkable); and the drop down the stairs no fall: "the infinite stairs is very glitchy", 2026-11-03)
    local moved = pcall(function()
        local l = pawn:K2_GetActorLocation()
        pawn:K2_SetActorLocation({ X = l.X + m[1], Y = l.Y + m[2], Z = l.Z + m[3] }, false, {}, true)
    end)
    if not moved then
        pcall(function()
            local l, r = pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation()
            pawn:K2_TeleportTo({ X = l.X + m[1], Y = l.Y + m[2], Z = l.Z + m[3] }, r)
        end)
    end
    pcall(function() lib.controller().PlayerCameraManager:SetGameCameraCutThisFrame() end)
    pcall(G.reset_hair, pawn)
    G.no_fall_until = math.max(G.no_fall_until or 0.0, os.clock() + 0.5)
    if not G.stairs_said then G.stairs_said = true; log("the endless stairs: back down them (%d stars)", stars) end
    -- (and their own tune while he climbs them - Mario 64's SEQ_EVENT_ENDLESS_STAIRS - where there is a file for it;
    -- back to the castle's once he has not been sent down them for a while: G.stairs_tune)
    G.stairs_t = os.clock()
    if MUSIC and MUSIC.has and MUSIC.has(G.STAIRS_TUNE) and MUSIC.current ~= G.STAIRS_TUNE then pcall(MUSIC.play, G.STAIRS_TUNE) end
end
-- (the stairs' loop is held off by nothing that holds the warps off: the scene built again round him - RENDER 96
-- switched - holds them off 1.5 s (warp_cool), and he ran past its strip in that time and on up the stairs: "also able
-- to get past the infinite stairs by switching to render 96", 2026-11-03)
function G.stairs_held(pawn, x, y, z)
    local rz, T = floor_hit(G.rule, x, y, z + 60.0)
    if not T then return end
    local n = tonumber(T[11]:match("^instant:(%d+)"))
    local w = n and G.instant[n]
    if not (w and w.same and w.move) then return end
    local fz = floor_z(x, y, z + 60.0)
    if fz and fz > rz + 5.0 then return end         -- (ordinary floor between him and it)
    G.stairs_loop(pawn, w)
end
local function update_floors(pawn, x, y, z, grounded)
    if G.stairs_t then pcall(G.stairs_tune) end
    G.sink_kind, G.wind_dir, G.sand_push, G.vwind, G.pit_pull = nil, nil, nil, nil, nil
    if G.warp_cool > 0 and not G.pending and G.rule then pcall(G.stairs_held, pawn, x, y, z) end
    if G.warp_cool > 0 or G.pending or not G.rule then return end
    -- (dancing with a star: no floor of the level's takes him - no stream carries him, no pit pulls, no quicksand
    -- swallows: Mario 64's star dance does no ground steps. A star taken on the pyramid's sand streams, he was carried
    -- into its pit while he danced, his controls held, and lost a life: "died after collecting star", 2026-10-23)
    if G.star_dance_st then return end
    -- (hanging on a ledge, or in one of STORROR's moves - flying or its own mode: no sand takes him, carries him or pulls
    -- him, as Mario 64's only do in his ground steps - hung by an edge over the pyramid's quicksand, his feet in reach of
    -- it, he was sucked under: "got sucked into quicksand while grabing a edge", 2026-11-07)
    local hung = false
    pcall(function() local mm = pawn.CharacterMovement.MovementMode; hung = mm == 5 or mm == 6 end)
    -- his floor is a platform: whatever lies far below does not count (or one is under him, in the air over it:
    -- platforms.lua) - but the lava does once the platform has sunk into it, its top at or under the lava's surface:
    -- then he stands on the lava, as Mario 64's lava is a floor of its own over the sunk platform's. A platform under
    -- him anywhere had let him stand on the lava unhurt ("when platforms sink underwater and lava is replaced by it you
    -- dont take damage from the lava", "lit standing on lava", 2026-10-24)
    if PLAT.on or (PLAT.over and PLAT.over(x, y, z)) then
        local lz = G.lava_z and G.lava_z(x, y, z + 200.0)
        if not lz then return end
        local top = PLAT.floor_under and PLAT.floor_under(x, y, z + 45.0)
        if top and top > lz + 2.0 then return end                -- (its top over the lava: on it, he is safe)
        if z - lz < 12.0 then G.lava_touch(pawn, z - lz) end
        return
    end
    local rz, T = floor_hit(G.rule, x, y, z + 60.0)
    if not T then return end
    -- (a vertical wind's floor as high as the death plane found there: the wind's - G.vwind_rule)
    if T[11] == "death" and G.vwind_rule then
        local vz, VT = floor_hit(G.vwind_rule, x, y, z + 60.0)
        if VT and vz >= rz - 5.0 then rz, T = vz, VT end
    end
    -- (riding the crazy box - boxes.lua, G.crazy_ride till when: its bounces never stand on the sand. Mario 64's
    -- act_crazy_box_bounce goes from each landing straight into the next bounce, and quicksand takes him only on his feet
    -- (mario_update_quicksand, in the ground steps): no pit's pull, no sinking and no quicksand till the third landing -
    -- the pit held him down under his bounce, "box glitches out when landing on sand vortex", 2026-10-23)
    if G.crazy_ride and os.clock() < G.crazy_ride then
        local t0 = T[11]:match("^(.-)@%d+$") or T[11]
        if t0 == "quicksand" or t0:sub(1, 5) == "sink:" then return end
    end
    -- (moving quicksand: its way and speed after the @ - read before the test below, which the stream's own slopes
    -- and banks often fail)
    local base, force = T[11]:match("^(.-)@(%d+)$")
    if base and z - rz < 30.0 and not hung then G.sand_push = tonumber(force) end
    local fz = floor_z(x, y, z + 60.0)
    -- (a painting's strip under its hollow - G.recess_paintings: it takes him once he is all the way through the
    -- picture and not before, whatever the sill over it - the sill is floor between him and it, as high as its foot)
    local rec = nil
    if (base or T[11]):sub(1, 6) == "paint:" and G.recess_at then
        rec = G.recess_at(x, y, z)
        if rec then
            if not rec.at_picture then return end
            fz = nil
        end
    end
    if fz and fz > rz + 5.0 then return end         -- there is ordinary floor between him and it
    local tag, above = T[11], z - rz
    if rec then above = 0.0 end
    if base then tag = base end
    -- (in a sand pit, on its sand: carried to its middle, whichever way its sand runs)
    if (tag:sub(1, 5) == "sink:" or tag == "quicksand") and above < 30.0 and not hung then
        local pc = G.pit_at(x, y, z)
        if pc then G.pit_pull, G.sand_push = pc, nil end
    end
    local HP = _G.HEALTH
    if tag == "death" or tag == "vwind" then
        if above < 1536.0 then G.fall_out("fell out of the level") end       -- 2048 Mario units above the plane
        if tag == "vwind" and not grounded then G.vwind = z end              -- (G.apply_vwind: his feet, scene cm)
    elseif tag == "warp" then
        G.fall_out("fell out of the level")
    elseif tag == "lava" then
        if above < 12.0 then G.lava_touch(pawn, above) end
    elseif tag == "quicksand" then
        -- (sucked under it, as Mario is: quicksand.lua; the life goes once he is under)
        if above < 12.0 and not hung and HP and not HP.dead_t and not G.dying then
            if not (QSAND and QSAND.sucked and QSAND.sucked(pawn)) and not (QSAND and QSAND.dying and QSAND.dying()) then
                HP.kill("quicksand")
            end
        end
    elseif tag:sub(1, 5) == "wind:" then
        G.wind_dir = tonumber(tag:sub(6))               -- (his floor blows: G.apply_wind, on it or over it)
    elseif tag:sub(1, 5) == "sink:" then
        if above < 12.0 then G.sink_kind = tag:sub(6) end
    elseif tag == "timer_start" or tag == "timer_end" then
        if above < 60.0 then G.pss_floor(tag) end
    elseif tag then
        local n = tonumber(tag:match("^paint:(%d+)"))
        if n then
            local w = G.pwarp[n]
            if w and (n < 39 or above < 60.0) and not (G.warping or G.pending) then     -- (once: held there till it goes)
                log("into painting strip %d -> %s", n, w.scene)
                -- (the Bowser hallway's painting: the run begins - G.GAUNTLET)
                if w.gauntlet then G.gauntlet = { t = os.clock() }; log("bowser run: begun") end
                G.painting_y = z / 0.75
                if w.scene == "wdw" then G.wdw_level = nil end          -- (a fresh visit: the jump decides)
                -- (into the clock: where its minute hand points sets Tick Tock Clock's speed)
                if w.scene == "ttc" and PLAT and PLAT.ttc_clock then
                    local okT, sp = pcall(PLAT.ttc_clock)
                    if okT then log("Tick Tock Clock speed: %s", ({ [0] = "slow", "fast", "random", "stopped" })[sp] or tostring(sp)) end
                end
                sfx("painting_enter")
                G.warp_out("painting", w.scene, w.node, nil, true)
                if PAINT and G.warping then pcall(PAINT.enter, pawn, w.scene) end
            end
            return
        end
        n = tonumber(tag:match("^instant:(%d+)"))
        local w = n and G.instant[n]
        if w and w.same and w.move then
            G.stairs_loop(pawn, w)
        elseif w and not w.same then
            log("instant warp %d -> %s", n, w.scene)
            G.goto_scene(w.scene, nil, { move = w.move })
        end
    end
end

-- (envfx.lua's lava bubbles: the lava's height at (x, y) - scene cm - at or under zmax, nil where there is none or
-- ordinary floor lies over it)
function G.lava_z(x, y, zmax)
    if not G.rule then return nil end
    local rz, T = floor_hit(G.rule, x, y, zmax)
    if not (T and T[11] == "lava") then return nil end
    local fz = floor_z(x, y, zmax)
    if fz and fz > rz + 5.0 then return nil end
    return rz
end

-- ------------------------------------------------------------ warp objects
-- Invisible spots that send the player on when he is in them (the hole behind a star door, the way into
-- a secret course), warp pipes (drop into the top), and the pairs of "fading" warps inside a level,
-- which take whoever stands still on one to the other.
G.warps = {}
function G.add_warp(o)
    -- (a teleport spot reaches him as Mario 64's does: bhv_fading_warp_loop's 85 round it and Mario's 37, 122 units -
    -- 92 cm - and a little more: 100. At 70 and then 80 the one in BoB's hole in the hill was out of reach - its point
    -- is behind the hole's back wall, 91 cm off where he can stand: "the teleport still isnt working the one in the hole
    -- in the hill", 2026-10-16)
    local r = (o.kind == "pipe") and 60.0 or (o.kind == "fading_warp") and 100.0 or 70.0
    r = o.radius or r
    -- (the castle's two windows - the Princess's Secret Slide and the Secret Aquarium: their warp is 1.6 m back in a
    -- recess Mario jumps into and the athlete is too tall for - STORROR leaves him hanging on the step before it. It
    -- reaches him on that step: "I cant climb into princess secret slide", 2026-10-17)
    -- (and hanging from the aquarium window's sill - 3.8 m over the floor, its recess 1.5 m tall: his feet 1.8 m under
    -- the warp, 2 m off it - "I cant enter the secret water level", 2026-10-18: reached from 2.6 m under, 2.3 m off)
    -- (then the aquarium's recess made tall enough to climb into - MOVE_PIECES - and its warp back to the recess
    -- itself: it takes him once he is in, not while he hangs from the sill)
    local low = nil
    if G.name == "castle" and o.kind == "warp" and o.node == 10 then r, low = 200.0, 260.0 end
    if G.name == "castle" and o.kind == "warp" and o.node == 12 then r = 70.0 end
    G.warps[#G.warps + 1] = { kind = o.kind, x = o.pos[1], y = o.pos[2], z = o.pos[3], node = o.node, low = low,
        r = r, t = 0.0, tz = o.trigger, deep = (G.name == "castle" and o.kind == "warp" and o.node == 0x0B) or nil }
end

local WING_JUMP = 1300.0       -- cm/s up given to the Wing Cap's third jump (some 8.5 m)
local TELEPORT_WAIT = 2.0     -- s standing still on a teleport spot before it takes him
local function update_warps(dt, x, y, z, speed, grounded)
    for _, w in ipairs(G.warps) do
        local d = dist2(x, y, w.x, w.y)
        local inside
        if w.kind == "warp" then
            inside = d < w.r + 28.0 and z > w.z - (w.low or 150.0) and z < w.z + 80.0
            -- (the castle trapdoor's pit, made deep under it: fallen in below its trigger it takes him all the same, even
            -- "used" - a death's way back starts him standing in it, and a launch out that fell short left him at the
            -- pit's bottom for good: "the players spawning inside the trapdoor", 2026-10-17)
            if w.deep and d < w.r + 28.0 and z <= w.z - 150.0 then inside, w.used = true, false end
        elseif w.kind == "pipe" then
            inside = d < w.r and z > (w.tz or w.z) - 40.0 and z < (w.tz or w.z) + 110.0
            -- (a deep pipe: anywhere down its shaft under its warp, to its walls - fallen past the warp's band, he stood at
            -- the bottom of Tiny-Huge Island's 4.5 m shaft 58 cm off its middle and never went, 2026-11-08)
            if w.tz and not inside then inside = d < 85.0 and z < w.tz + 110.0 and z > w.tz - 1500.0 end
        else inside = d < w.r and abs(z - w.z) < 90.0 end
        if not inside then
            w.t, w.used, w.said, w.px, w.py = 0.0, false, nil, nil, nil
        elseif not w.used and G.warp_cool <= 0 and not G.pending then
            local go = true
            if w.kind == "fading_warp" then
                -- (stood still on it - Mario 64 takes him when he stands idle there, or against a wall - for
                -- TELEPORT_WAIT first: "make the play wait 3 seconds before the teleport", then "shorten teleport time to
                -- 2 seconds", 2026-10-16; it was 0.8 s. Still by where he is, not his speed: STORROR's walk into the
                -- hillside reads as moving while it holds him in place)
                if not w.said then w.said = true; log("on the teleport spot 0x%02X: still for %.0f s and it takes him", w.node, TELEPORT_WAIT) end
                local moved = 0.0
                if w.px and dt > 0.0 then moved = sqrt((x - w.px) ^ 2 + (y - w.py) ^ 2) / dt end
                w.px, w.py = x, y
                w.t = (grounded and moved < 40.0) and (w.t + dt) or 0.0
                go = w.t > TELEPORT_WAIT
            end
            local dest = go and G.warp[w.node]
            if dest then
                w.used = true
                log("%s 0x%02X -> %s 0x%02X", w.kind, w.node, dest.scene, dest.node)
                if w.kind == "pipe" then sfx("pipe_enter") elseif w.kind == "fading_warp" then sfx("teleport") end
                if w.kind == "pipe" then G.warp_out("pipe", dest.scene, dest.node, nil, true)
                elseif w.kind == "fading_warp" then G.warp_out("fade", dest.scene, dest.node)
                else G.warp_out("warp", dest.scene, dest.node) end
            end
        end
    end
end

-- ------------------------------------------------------------ locked doors
-- Mario 64's locks (interaction.c interact_door, interact_warp_door): a door marked with stars opens with that many in
-- the file - else DIALOG_024 (1), 025 (3), 026 (8), 027 (30), 028 (50) with the stars still wanting in it, or 029 at the
-- 70 one, which lets him through after it (to the endless stairs); a key door opens with its key - the upstairs one
-- (its door id 1) Bowser's second, the basement's (2) his first - else DIALOG_022, or 023 holding the other key. (They
-- all opened for anyone: "next doors and locations should be locked until you have the required stars/keys",
-- 2026-10-20.) Nil when it opens; else the message, its number, and whether he goes through after it.
G.DOOR_STAR_MSG = { [1] = 24, [3] = 25, [8] = 26, [30] = 27, [50] = 28, [70] = 29 }
function G.door_lock(need, key)
    local MN = _G.MENU
    if key == 1 or key == 2 then
        local mine = (key == 1) and 2 or 1
        local has = MN and MN.has_key
        if has and has(mine) then return nil end
        local other = has and has((mine == 1) and 2 or 1)
        return other and 23 or 22, nil, false
    end
    if need and need > 0 then
        local stars = (MN and MN.star_count and MN.star_count()) or 0
        if stars >= need then return nil end
        local id = G.DOOR_STAR_MSG[need] or 22
        return id, (id >= 25 and id <= 28) and (need - stars) or nil, need == 70
    end
    return nil
end

-- The door's own mark in the file once it has been unlocked (Mario 64's get_door_save_file_flag: the 1 star doors told
-- apart by height - Peach's Slide's is upstairs - the 3 star ones by side; and the key doors' SAVE_FLAG_UNLOCKED_*). Nil
-- for a door that needs none.
function G.door_flag(need, key, x, y, z)
    if key == 1 then return "unlocked_upstairs" elseif key == 2 then return "unlocked_basement" end
    if need == 1 then return ((z or 0.0) > 500.0 * 0.75) and "unlocked_pss" or "unlocked_wf" end
    if need == 3 then return ((y or 0.0) < 0.0) and "unlocked_ccm" or "unlocked_jrb" end
    if need == 8 then return "unlocked_bitdw" end
    if need == 30 then return "unlocked_bitfs" end
    if need == 50 then return "unlocked_50" end
    return nil
end

-- The first time a door he may now open is opened, it is unlocked first, as Mario 64 does it (unlock.lua: the star
-- summoned and DIALOG_038, or Bowser's key turned in the lock). d: the door (a leaf of G.doors, or a half of a star
-- door), list: its kind's doors (its partner found among them, for the middle of the pair), (nx, ny): the way it faces.
-- True while it is not to open yet.
function G.door_unlock_due(d, list, nx, ny)
    local MN = _G.MENU
    local flag = G.door_flag(d.need, d.key, d.x, d.y, d.z)
    if not (flag and MN and MN.has_flag and MN.add_flag) or MN.has_flag(flag) then return false end
    if G.unlocking or (DIALOG and DIALOG.active) then return true end
    if d.told then return true end
    local okU, U = pcall(require, "unlock")
    if not okU or not U then return false end
    local mx, my = d.x, d.y
    for _, o in ipairs(list or {}) do
        if o ~= d and o.need == d.need and o.key == d.key and dist2(o.x, o.y, d.x, d.y) < 250.0 then
            mx, my = (d.x + o.x) / 2.0, (d.y + o.y) / 2.0
            break
        end
    end
    local px, py = 0.0, 0.0
    pcall(function() local l = lib.pawn():K2_GetActorLocation(); px, py = l.X - OFFSET.X, l.Y - OFFSET.Y end)
    local sgn = (((px - mx) * nx + (py - my) * ny) > 0) and -1.0 or 1.0           -- (he looks at it from his side)
    local door = { x = mx, y = my, z = d.z, face = deg(atan(ny * sgn, nx * sgn)) }
    d.told = true
    local function marked() MN.add_flag(flag); log("door unlocked: %s", flag) end
    if d.key then
        U.key(door, function() marked(); d.pass = true end)
    else
        U.star(door, marked)
    end
    return true
end

-- ------------------------------------------------------------ star doors
-- The castle's big star doors do not swing: the two halves slide apart as the player comes up to them
-- and close again behind him.
G.stardoors = {}
function G.add_stardoor(world, o)
    local data = actor_data(o.actor)
    if not data then return end
    light_door_faces(data)          -- (its two halves are one model, the second turned round: lit alike, as the doors)
    local inst = lib.make_instance(world, data, wpos(o.pos), o.yaw, 1.0)
    if not inst then return end
    inst.moves = true
    pcall(leaf_collision, inst)     -- (each half solid, sliding aside with it)
    G.stardoors[#G.stardoors + 1] = { inst = inst, x = o.pos[1], y = o.pos[2], z = o.pos[3], yaw = o.yaw or 0.0,
        need = o.need, open = 0.0, shown = -1.0 }
end

local function update_stardoors(dt, x, y, z)
    for _, s in ipairs(G.stardoors) do
        -- (its other half: the two slide together)
        if s.partner == nil then
            s.partner = false
            for _, o in ipairs(G.stardoors) do if o ~= s and dist2(o.x, o.y, s.x, s.y) < 250.0 then s.partner = o end end
        end
        -- shut and solid until he comes right up to it (as the doors: "Both", 2026-10-15; it slid open from 3.8 m);
        -- then both halves slide aside, and stay open till he is 3.8 m away
        local d = dist2(x, y, s.x, s.y)
        if s.partner then d = math.min(d, (dist2(x, y, s.partner.x, s.partner.y))) end
        local opened = s.open > 0.01 or (s.partner and s.partner.open > 0.01)
        -- (open from G.STARDOOR_NEAR - it waited till he was 1.1 m off - and shut past G.STARDOOR_SHUT)
        local near = d < (opened and (G.STARDOOR_SHUT or 380.0) or (G.STARDOOR_NEAR or 110.0)) and abs(z - s.z) < 300.0
        local close = d < 110.0 and abs(z - s.z) < 300.0
        -- (locked till the file has its stars - G.door_lock - its message once each time he comes up to it; the 70
        -- one opens after its message)
        if near and not opened and not s.pass and not (s.partner and s.partner.pass) then
            local msg, var, pass = G.door_lock(s.need, nil)
            if msg then
                near = false
                if close and not s.told and not (s.partner and s.partner.told) and not (DIALOG and DIALOG.active) then
                    s.told = true
                    G.say(msg, pass and function() s.pass = true end or nil, var)
                end
            elseif not close and not G.door_free(s) then
                near = false            -- (its unlocking still to come: it waits for him at the door)
            elseif not (s.partner and s.partner.told) and G.door_unlock_due(s, G.stardoors, cos(rad(s.yaw)), sin(rad(s.yaw))) then
                near = false
            end
        end
        if d > (G.STARDOOR_SHUT or 380.0) then s.told, s.pass = nil, nil end
        -- (shut while a message is up, and through a door's unlocking: the other half of the 30 star door, its partner
        -- unlocking, slid open under the star - "door still opens before dialog ends", 2026-10-20)
        if not opened and ((DIALOG and DIALOG.active) or G.unlocking) then near = false end
        if near ~= (s.was_near or false) then
            s.was_near = near
            sfx(near and "stardoor_open" or "stardoor_close")
        end
        local step = dt / (G.STARDOOR_TIME or 0.55)
        s.open = s.open + math.max(-step, math.min(step, (near and 1.0 or 0.0) - s.open))
        if abs(s.open - s.shown) > 0.004 then
            s.shown = s.open
            local slide = s.open * 100.0
            lib.set_pose(s.inst, s.x + sin(rad(s.yaw)) * slide + OFFSET.X, s.y - cos(rad(s.yaw)) * slide + OFFSET.Y,
                s.z + OFFSET.Z, s.yaw)
        end
    end
end

local function spawn_fireball(world, x, y, z, heading)
    local actor = lib.quad_actor(world, { X = x + OFFSET.X, Y = y + OFFSET.Y, Z = z + OFFSET.Z }, 70.0, "actors__yellow_sphere__yellow_sphere.rgba16", "alpha")
    if not actor then return end
    G.fireballs[#G.fireballs + 1] = {
        actor = actor, x = x, y = y, z = z, vx = cos(heading) * 650, vy = sin(heading) * 650, t = 4.0,
    }
end

-- Bowser's landings shake the stage (the scene's own actor and the bombs, a few cm, dying away) and the camera
-- (STORROR's own landing shake). 2026-10-14: "when bowser lands from jump the level shakes", "no make the stage
-- shake", "the camera shake would be cool too add that as well".
local SHAKE_CLASS = "/SPP/SPPCharacter/Components/Locomotion/LocomotionScreenShake.LocomotionScreenShake_C"
-- The camera alone shaken (set_camera_shake_from_hit): health.lua on a hurt, by how bad it was. STORROR's own shake
-- (above) is a 1 cm, half-degree noise that did not move the view at all; this moves his camera itself - its place on
-- the end of its arm - in a quick wobble that dies away, k x 6 cm, then puts it back.
function G.shake_camera(k)
    local pawn = lib.pawn()
    if not pawn then return end
    local cam = nil
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.CameraComponent"))) do cam = c:get() end
    end)
    if not cam then return end
    local old = G.cam_shake
    local home = old and old.home or nil
    if not home then pcall(function() local r = cam.RelativeLocation; home = { r.X, r.Y, r.Z } end) end
    if not home then return end
    G.cam_shake = { cam = cam, home = home, t = 0.0, len = 0.25 + 0.12 * (k or 1.0), amp = 6.0 * (k or 1.0) }
end
function G.cam_shake_tick(dt)
    local s = G.cam_shake
    if not s then return end
    s.t = s.t + dt
    local done = s.t >= s.len
    local a = done and 0.0 or s.amp * (1.0 - s.t / s.len) ^ 1.5
    pcall(function()
        s.cam.RelativeLocation = { X = s.home[1], Y = s.home[2] + a * 0.6 * sin(s.t * 71.0), Z = s.home[3] + a * sin(s.t * 89.0 + 1.3) }
    end)
    if done then G.cam_shake = nil end
end
function G.shake_stage(k)
    k = k or 1.0
    G.stage_shake = { t = 0.0, len = 0.8, amp = 16.0 * k }       -- (cm; at 8 it was hardly to be seen)
    pcall(function()
        local cls = StaticFindObject(SHAKE_CLASS)
        if cls and cls:IsValid() then
            lib.controller().PlayerCameraManager:StartCameraShake(cls, 3.0 * k, 0, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
        end
    end)
end
local function update_stage_shake(dt)
    local s = G.stage_shake
    if not s then return end
    s.t = s.t + dt
    local done = s.t >= s.len
    local k = done and 0.0 or (1.0 - s.t / s.len) ^ 1.5 * s.amp
    local ox, oy, oz = k * 0.5 * sin(s.t * 61.0), k * 0.5 * cos(s.t * 53.0), k * sin(s.t * 79.0)
    local zero = { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }
    if G.scene_actor then
        pcall(function() G.scene_actor:K2_TeleportTo({ X = OFFSET.X + ox, Y = OFFSET.Y + oy, Z = OFFSET.Z + oz }, zero) end)
    end
    G.shake_off = done and nil or { ox, oy, oz }        -- (the bombs shake with it: update_bombs)
    if done then G.stage_shake = nil end
end

-- The bombs round Bowser's arena: their ball is a picture that faces the camera, up and down as well as around, as
-- Mario 64's billboard does; turned every frame (it was left as placed, a flat disc: from the side a thin sliver, from
-- behind black - "the bombs need to be fixed", 2026-10-14). The spikes round it stay as they are. The stage's shake
-- moves them too.
local function update_bombs()
    local off = G.shake_off or { 0.0, 0.0, 0.0 }
    if #G.sprites > 0 then
        local cx, cy, cz = lib.camera_location({ X = 0.0, Y = 0.0, Z = 0.0 })
        for _, sp in ipairs(G.sprites) do
            local p = wpos({ sp.x + off[1], sp.y + off[2], sp.z + off[3] })
            local dx, dy, dz = cx - p.X, cy - p.Y, cz - p.Z
            -- (its picture faces its -X: that side to the camera, up and down as well as around)
            local rot = { Pitch = -deg(atan(dz, sqrt(dx * dx + dy * dy))), Yaw = deg(atan(dy, dx)) + 180.0, Roll = 0.0 }
            pcall(function() sp.actor:K2_TeleportTo(p, rot) end)
        end
    end
    -- (the final fight's bombs on the floors below his: still, drawn now and then - G.pancakes)
    G.bomb_frame = (G.bomb_frame or 0) + 1
    for i, bm in ipairs(G.bombs or {}) do
        local here = not bm.floor or not G.pancake_floor or bm.floor == G.pancake_floor or (G.bomb_frame + i) % 8 == 0
        if not bm.gone and bm.inst and here then
            local p = wpos({ bm.x + off[1], bm.y + off[2], bm.z + off[3] })
            lib.face_camera(bm.inst, p.X, p.Y)
            lib.set_pose(bm.inst, p.X, p.Y, p.Z, 0.0)
        end
    end
end

G.BOWSER_TURN = 105.0         -- degrees a second he turns toward the athlete as he walks: "just enough to reach behind
                              -- him" (2026-10-14: 60 was too slow, 150 "turns too quick", 85 then "just a tad faster",
                              -- 100 then "by a legit hair");
                              -- Mario 64's Dark World Bowser's own 0x200 a frame (84), and up to 169 for the Sky's
-- The fight itself is Scripts/bowser_fight.lua (Mario 64's Bowser, rebuilt 2026-10-14: "the entire boss fight needs
-- worked on"); it can be reloaded while the game runs.
local BOWSER_HURT = { body = 2, fire = 2, shock = 1, land = 1, stomp = 2, ram = 2, jumpin = 2 }
local bowser_hurt_t = 0.0
local function bowser_ctx()
    return {
        lib = lib, OFFSET = OFFSET, MUSIC = MUSIC, PLAT = PLAT, pushed = pushed, log = log,
        sfx = function(name, v) sfx(name, v) end,
        hold_sfx = function(name, v) local SFXm = package.loaded["sfx"]; if SFXm and SFXm.hold then SFXm.hold(name, v) end end,
        floor_at = function(x, y, zmax)
            local fz = floor_z(x, y, zmax)
            local pz = PLAT.floor_under and PLAT.floor_under(x, y, zmax)
            if pz and (not fz or pz > fz) then fz = pz end
            return fz
        end,
        bombs = function() return G.bombs end,
        explode = function(world, bm)
            local BB = package.loaded["bobomb"]
            if BB and BB.explode_at then pcall(BB.explode_at, world, bm.y / 0.75, bm.z / 0.75, -bm.x / 0.75) end
        end,
        actor_data = function(n) return actor_data(n) end,
        add_star = function(world, o) return G.add_star(world, o) end,
        scene_name = function() return G.name end,
        turn_speed = G.BOWSER_TURN,
        wedges = function() return _G.HEALTH and _G.HEALTH.wedges and _G.HEALTH.wedges() or 8 end,
        -- (hurt and knocked back from (dx, dy), the way away from what hit him)
        hurt = function(kind, why, dx, dy)
            local HP = _G.HEALTH
            -- (no fire under the metal or the vanish cap: interact_flame)
            if kind == "fire" and CAPS and (CAPS.on("metal") or CAPS.on("vanish")) then return end
            -- (burning already, a flame only starts the burn over, as Mario 64's does; it costs nothing more)
            if kind == "fire" and BURN and BURN.active then pcall(BURN.start, dx, dy); return end
            if kind == "fire" and RAG and RAG.active then return end         -- (lying flat: no burn on top)
            if not HP or os.clock() < bowser_hurt_t then return end
            if (kind == "stomp" or kind == "ram" or kind == "jumpin") and RAG then
                -- (he came down on him: knocked flat; he ran into him in a charge: sent flying. STORROR's ragdoll, up
                -- again when the player presses A; 2026-10-14)
                bowser_hurt_t = os.clock() + 1.0
                HP.damage(BOWSER_HURT[kind], why)
                if not RAG.active then pcall(RAG.start, dx, dy, (kind == "ram") and 1400.0 or ((kind == "jumpin") and 700.0 or 600.0)) end
                return
            end
            if kind == "fire" and BURN then
                -- (Mario 64: a flame costs nothing at the touch; he burns, and the burn drains the power, about three
                -- wedges in all: burn.lua. Not while he is still unhurtable from a hit.)
                if (HP.grace or 0) > 0 or HP.dead_t then return end
                bowser_hurt_t = os.clock() + 1.0
                lib.log("set alight by %s", tostring(why))
                sfx("mario_burn")
                pcall(BURN.start, dx, dy)
                return
            end
            if HP.damage(BOWSER_HURT[kind] or 1, why) then
                bowser_hurt_t = os.clock() + 1.0
                if BURN and BURN.active then pcall(BURN.stop, true) end
                local d = math.max(1.0, sqrt(dx * dx + dy * dy))
                local k = (kind == "body" or kind == "land") and 650.0 or 450.0
                -- (knocked back off him: into the air by hand, as STORROR's athlete takes no LaunchCharacter standing;
                -- "if you get hit by bowser when walking close to him get bumped of", then "make the bump not luanch
                -- you as far", 2026-10-14; "still bumps you pretty far": a short low skip now, so that he comes down
                -- too gently for STORROR's running landing roll, which carried him on several metres)
                pcall(function()
                    local cm = lib.pawn().CharacterMovement
                    cm:SetMovementMode(3, 0)
                    cm.Velocity = { X = dx / d * k, Y = dy / d * k, Z = 200.0 }       -- ("a little harder")
                end)
                if kind == "fire" then sfx("mario_burn") end
            end
        end,
        stun = function() if G.freeze then G.freeze(0.5) end end,
        spawn_coin = function(x, y, z) G.spawn_coin(x, y, z) end,
        shake = function(k) G.shake_stage(k) end,
        -- (his landing knocks him flat if he is on his feet, unhurt; in the air he jumped it)
        knockdown = function(dx, dy)
            local pawn = lib.pawn()
            if not (pawn and RAG) or RAG.active then return end
            local mode = 1
            pcall(function() mode = pawn.CharacterMovement.MovementMode end)
            if mode ~= 1 then return end
            lib.log("knocked flat by Bowser's landing")
            pcall(RAG.start, dx, dy, 250.0)
        end,
    }
end
local BF = optional("bowser_fight")
if BF then BF.setup(bowser_ctx()) end
G.bowser_fight = BF

local function update_bowser(b, dt, px, py, pz, cx, cy)
    local F = package.loaded["bowser_fight"]
    if not F then return end
    F.update(b, dt, lib.world(), lib.pawn(), px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z, G.grounded)
end
-- (to reload the fight while the game runs: G.reload_bowser_fight())
function G.reload_bowser_fight()
    if package.loaded["bowser_fight"] then pcall(package.loaded["bowser_fight"].clear) end
    package.loaded["bowser_fight"] = nil
    -- (read afresh: UE4SS's own module searcher keeps the first copy it loaded, so require would bring that back)
    local ok, F = pcall(function()
        local path = package.searchpath("bowser_fight", package.path)
        local m = assert(loadfile(path))()
        package.loaded["bowser_fight"] = m
        return m
    end)
    if ok and F then F.setup(bowser_ctx()); G.bowser_fight = F; if G.bowser then G.bowser.stage = nil end end
    return ok
end

local function update_fireballs(dt, px, py, pz, cx, cy)
    local x, y, z = px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z
    local keep = {}
    for _, f in ipairs(G.fireballs) do
        f.t = f.t - dt
        f.x, f.y = f.x + f.vx * dt, f.y + f.vy * dt
        local hit = false
        local d = sqrt((x - f.x) ^ 2 + (y - f.y) ^ 2)
        if d < 100 and abs(z - f.z) < 200 then
            hit = true
            lib.bounce(lib.pawn(), f.vx * 0.9, f.vy * 0.9, 400)
            if _G.HEALTH then _G.HEALTH.damage(_G.HEALTH.DAMAGE.fire, "Bowser's fire") end
        end
        if f.t <= 0 or hit then
            lib.destroy(f.actor)
        else
            local ay = deg(atan(cy - (f.y + OFFSET.Y), cx - (f.x + OFFSET.X))) + 180.0
            pcall(function()
                f.actor:K2_SetActorLocationAndRotation({ X = f.x + OFFSET.X, Y = f.y + OFFSET.Y, Z = f.z + OFFSET.Z },
                    { Pitch = 0.0, Yaw = ay, Roll = 0.0 }, false, {}, true)
            end)
            keep[#keep + 1] = f
        end
    end
    G.fireballs = keep
end

local errlog = {}
local function guarded(tag, fn, ...)
    -- (a crash hunt: each part named in the log as it starts, while _G.SM64_TRACE_UNTIL is ahead - set from a dev command)
    if _G.SM64_TRACE_UNTIL and os.clock() < _G.SM64_TRACE_UNTIL then log("trace %s", tag) end
    local ok, err = pcall(fn, ...)
    if not ok then
        local now = os.clock()
        if not errlog[tag] or now - errlog[tag] > 5 then
            errlog[tag] = now
            log("%s error: %s", tag, tostring(err))
        end
    end
end

-- Mario 64's messages: G.say(n, done) shows DIALOG_n (dialog.lua), done() once it is read
function G.say(id, done, var)
    if G.ending_on() then return false end
    if DIALOG and DIALOG.open(id, done, nil, var) then return true end
    if done then pcall(done) end
    return false
end

-- A question (dialog.lua M.ask: Mario 64's create_dialog_box_with_response): done(1) for its first answer, done(2) for
-- its second. Without the box, the first.
function G.ask(id, done)
    if G.ending_on() then return false end
    if DIALOG and DIALOG.ask and DIALOG.ask(id, done) then return true end
    if done then pcall(done, 1) end
    return false
end

-- Signs and the castle's Toads (data/talk.lua from exporter/talkx.py): read with STORROR's push - Mario 64's B -
-- standing close and facing them (2026-10-15: the signs stood silent)
local TALK, TALK_FOR = nil, nil
-- the Toads with a star to give (mario_misc.c bhv_toad_message_init): there from 12, 25 and 35 stars; once it is
-- given, their thanks
local SIGN_REACH = 140.0                     -- cm from a sign's middle
local SIGN_CONE = math.cos(math.rad(40.0))   -- out of its face
local SIGN_FACING = 60.0                     -- degrees he may look away from it
local TOAD_GIFT = { [82] = { star = 0, need = 12, after = 154 }, [76] = { star = 1, need = 25, after = 155 },
                    [83] = { star = 2, need = 35, after = 156 } }
local talk_shut_at = 0.0
local function update_talk(pawn, px, py, pz)
    if DIALOG and DIALOG.active then talk_shut_at = os.clock(); G.talk_wait_push = true end
    if not DIALOG or DIALOG.active or G.cutscene or G.warping or G.dying or G.pending then return end
    -- (a message shut while his push is still playing must not open again at once: a new push is wanted)
    if os.clock() - talk_shut_at < 0.8 then return end
    -- (and the push that shut it - Y both turns the pages and pushes - over before another counts: the sign opened again
    -- at once, over and over - "stuck in sign", 2026-10-16)
    if G.talk_wait_push then
        local busy = false
        pcall(function()
            local mt = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
            if mt and mt:IsValid() then
                local n = mt:GetFName():ToString()
                busy = (n:find("Attack") or n:lower():find("push")) and true or false
            end
        end)
        if busy then return end
        G.talk_wait_push, last_push = nil, nil
    end
    if TALK_FOR ~= G.name then
        TALK_FOR = G.name
        local all = lib.load_data("data.talk") or {}
        TALK = all[G.name or ""]
        -- (and the mod's own signs: G.EXTRA_SIGNS)
        for _, s in ipairs(G.EXTRA_SIGNS[G.name or ""] or {}) do
            TALK = TALK or {}
            TALK[#TALK + 1] = { kind = "sign", pos = { s.pos[1], s.pos[2], s.pos[3] }, yaw = s.yaw, dialog = s.dialog }
        end
        -- (a sign read where it is drawn: dropped onto the ground below its place, as G.add_prop puts it - one on the
        -- grounds hung 2.5 m over its post and could not be read: "this sign in front of me has no dialog as well",
        -- 2026-10-20)
        for _, t in ipairs(TALK or {}) do
            if t.kind == "sign" then
                local p = t.pos
                local fz = floor_hit(G.bounds, p[1], p[2], p[3] + 150.0) or floor_z(p[1], p[2], p[3] + 150.0)
                if fz then t.pos = { p[1], p[2], fz } end
            end
        end
    end
    local near, ndx, ndy = nil, 0.0, 0.0
    -- (Yoshi on the roof, at 120 stars: yoshi.inc.c, DIALOG_161 - then 100 lives, and he jumps off and is gone)
    local yo = SCENERY and SCENERY.yoshi and SCENERY.yoshi()
    if yo then
        local dx, dy = yo.x + OFFSET.X - px, yo.y + OFFSET.Y - py
        if dx * dx + dy * dy < 250.0 * 250.0 and abs(yo.z + OFFSET.Z - (pz - 90.0)) < 250.0 then
            near, ndx, ndy = { kind = "yoshi", dialog = 161, pos = { yo.x, yo.y, yo.z } }, dx, dy
        end
    end
    if not (TALK or near) then return end
    local stars = (_G.MENU and _G.MENU.star_count and _G.MENU.star_count()) or 0
    for _, t in ipairs(near and {} or TALK) do
        local dx, dy = t.pos[1] + OFFSET.X - px, t.pos[2] + OFFSET.Y - py
        local in_act = not (t.acts and G.act) or ((t.acts >> (G.act - 1)) & 1) == 1
        local gift = t.kind == "toad" and TOAD_GIFT[t.dialog]
        if gift and stars < gift.need then in_act = false end
        local close = dx * dx + dy * dy < 180.0 * 180.0
        if t.kind == "sign" then
            -- a sign is read only from right in front of it (asked 2026-10-15: "you should be standing right in front
            -- of it otherwise it shouldnt work"). Mario 64's check_read_sign takes its whole front half within its
            -- 150-unit hitbox (+ Mario's 37: 140 cm); here a 40 degree cone out of its face. (Its face looks along
            -- -X turned by its yaw: the model's +z, Mario 64's sins/coss(oMoveAngleYaw).)
            local a = math.rad(t.yaw or 0.0)
            local fx, fy = -math.cos(a), -math.sin(a)
            local d = math.sqrt(dx * dx + dy * dy)
            close = d < SIGN_REACH and d > 1.0 and (-dx * fx - dy * fy) / d > SIGN_CONE
        end
        if in_act and close and abs(t.pos[3] + OFFSET.Z - (pz - 90.0)) < 220.0 then
            near, ndx, ndy = t, dx, dy
            break
        end
    end
    if not near then return end
    local yaw = 0.0
    pcall(function() yaw = pawn:K2_GetActorRotation().Yaw end)
    local d = (deg(atan(ndy, ndx)) - yaw + 540.0) % 360.0 - 180.0
    if abs(d) > ((near.kind == "sign") and SIGN_FACING or 75.0) then return end
    if not pushed(pawn) then return end
    -- (Toads, Bob-omb Buddies and Yoshi talk with Mario 64's CUTSCENE_DIALOG camera, as the King does; a sign is read
    -- without it)
    if near.kind ~= "sign" and near.pos then
        pcall(G.dialog_cut, near.pos[1], near.pos[2], near.pos[3], (near.kind == "yoshi") and 150.0 or 80.0)
    end
    if near.kind == "cannon_buddy" then
        -- (bobomb_buddy_cannon_dialog: the first time, his offer and the course's cannons open for good; then his
        -- reminder)
        local course = G.level_of(G.name)
        local MN = _G.MENU
        local opened = MN and MN.has_flag and MN.has_flag("cannon_" .. course)
        local bob = course == "bob"
        local d = opened and (bob and 105 or 106) or (bob and 4 or 47)
        log("talking: cannon buddy, dialog %d", d)
        G.say(d, function()
            if opened then return end
            if MN and MN.add_flag then pcall(MN.add_flag, "cannon_" .. course) end
            if PLAT.open_cannons and PLAT.open_cannons() then log("a Bob-omb Buddy opened the cannons") end
        end)
        return
    end
    if near.kind == "yoshi" then
        log("talking: Yoshi")
        G.say(161, function()
            if _G.HEALTH then _G.HEALTH.lives = 100 end
            sfx("oneup")
            if SCENERY and SCENERY.yoshi_leave then SCENERY.yoshi_leave() end
            log("Yoshi: 100 lives")
        end)
        return
    end
    if near.kind == "toad" then
        sfx("toad_jingle")                      -- (play_toads_jingle: his little tune, the castle's turned down under it)
        if MUSIC and MUSIC.dip then pcall(MUSIC.dip, 2.6) end
        local g = TOAD_GIFT[near.dialog]
        if g then
            -- (toad_message_talking: his star comes out after his message; then, for the rest of the visit and once
            -- it is won, his thanks)
            local key = "castle:" .. g.star
            local MN = _G.MENU
            local given = MN and MN.has_star and MN.has_star(key)
            for _, s in ipairs(G.stars) do if s.key == key then given = true end end
            if given then
                log("talking: Toad, dialog %d", g.after)
                G.say(g.after)
            else
                log("talking: Toad, dialog %d and his star", near.dialog)
                G.say(near.dialog, function() G.gift_star(g.star, near.pos) end)
            end
            return
        end
    end
    -- (the castle grounds' first sign - Mario 64's DIALOG_167, by the start - shows the music credits: credits.lua,
    -- "on the first sign in the game I want you to add all the music here in one window", 2026-11-01)
    if near.kind == "sign" and near.dialog == 167 and G.name == "grounds" then
        local okc, CR = pcall(require, "credits")
        if okc and CR and CR.open then
            if CR.active then return end
            -- (its own message first, then the credits: "I also still want my original dialog on the sign")
            log("reading: the first sign - its message, then the music credits")
            G.say(near.dialog, function() pcall(CR.open) end)
            return
        end
    end
    log("reading: %s, dialog %d", near.kind, near.dialog)
    G.say(near.dialog)
end

-- Mario 64's course-complete screen (act_exit_land_save_dialog -> MENU_MODE_RENDER_COURSE_COMPLETE_SCREEN): once he
-- is back in the castle after a star and has landed out of the painting (or come up through the trap door), a
-- moment on. (Any other way out of the course forgets it: G.warp_out.)
function G.complete_due(pawn, dt)
    local c = G.complete
    if G.name == c.from or G.warping or G.pending then return end           -- (still in the course, or on the way)
    if not ACT_HUBS[G.name or ""] then G.complete = nil; return end
    local falling = false
    pcall(function() falling = pawn.CharacterMovement:IsFalling() end)
    if G.entry or G.dying or falling or (DIALOG and DIALOG.active) or (STARSEL and STARSEL.active) then c.wait = 0.0; return end
    c.wait = (c.wait or 0.0) + dt
    if c.wait < 0.3 then return end
    G.complete = nil
    -- (no screen - "honestly dont add a save screen", 2026-10-16: he took it for Mario 64's save menu; the file is saved
    -- as each star is taken anyway. Its lives at 50, 100 and 150 coins given here, with their chimes; then the
    -- star-count message. G.CM.open(c, ...) brings the screen back.)
    local n = math.min(3, math.floor((c.coins or 0) / 50))
    local HP = _G.HEALTH
    if n > 0 and HP then
        HP.lives = HP.lives + n
        G.oneup_chimes = n
        log("course complete: %d coins, %d more %s", c.coins or 0, n, n == 1 and "life" or "lives")
    end
    G.star_count_message(c.before or 0, c.after or 0)
end

-- After it (handle_save_menu): if the stars he has now have passed 1, 3, 8, 30, 50 or 70, Peach's jingle and her
-- message about the doors they open (get_star_collection_dialog: DIALOG_141 to 146, ACT_READING_AUTOMATIC_DIALOG)
function G.star_count_message(before, after)
    for i, n in ipairs({ 1, 3, 8, 30, 50, 70 }) do
        if before < n and after >= n then
            sfx("message_jingle")                       -- (play_peachs_jingle: the music silent under it)
            if MUSIC and MUSIC.dip then pcall(MUSIC.dip, 5.8, 0.0) end
            log("stars: %d -> %d, Peach's message %d", before, after, 140 + i)
            G.say(140 + i)
            return true
        end
    end
    return false
end

-- The lobby's sunbeam (geo_exec_inside_castle_light, dl_castle_lobby_wing_cap_light): with ten stars and the Wing Cap
-- switch not yet pressed, a shaft of light from the high window down onto the octagon in the floor - where looking up
-- takes him to the Tower of the Wing Cap (G.look_up_tick). Mario 64's own sixteen points and 32 x 32 light picture
-- (textures/castle_light.png), at half strength (its vertex alpha 0x80).
function G.lobby_light(world)
    local MN = _G.MENU
    local stars = (MN and MN.star_count and MN.star_count()) or 0
    if stars < 10 or (MN and MN.has_flag and MN.has_flag("cap_wing")) then return end
    local V = { { -1075, 1741, -380, -360, -62 }, { -1125, -50, 461, 478, 990 }, { -1279, -50, 594, 612, 990 },
                { -1075, 1741, -130, -110, -62 }, { -921, -50, 973, 990, 990 }, { -968, 1741, -130, -110, -62 },
                { -767, -50, 819, 836, 990 }, { -896, 1741, -201, -180, -62 }, { -1125, -50, 973, 990, 990 },
                { -767, -50, 614, 632, 990 }, { -896, 1741, -309, -288, -62 }, { -921, -50, 461, 478, 990 },
                { -968, 1741, -380, -360, -62 }, { -1147, 1741, -201, -180, -62 }, { -1147, 1741, -309, -288, -62 },
                { -1279, -50, 819, 836, 990 } }
    local T = { 0, 1, 2, 3, 4, 5, 5, 4, 6, 5, 6, 7, 3, 8, 4, 7, 6, 9, 7, 9, 10, 10, 9, 11, 10, 11, 12, 12, 11, 1,
                12, 1, 0, 13, 8, 3, 0, 2, 14, 14, 2, 15, 14, 15, 13, 13, 15, 8 }
    local verts, nrms, uvs, cols, idx = {}, {}, {}, {}, {}
    for i, v in ipairs(V) do
        verts[i] = { X = -v[3] * 0.75, Y = v[1] * 0.75, Z = v[2] * 0.75 }
        nrms[i] = { X = 0.0, Y = 0.0, Z = 1.0 }
        uvs[i] = { X = v[4] / 1024.0, Y = v[5] / 1024.0 }
        cols[i] = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
    end
    -- (drawn from both sides: G_CULL_BACK is cleared for it)
    for t = 1, #T, 3 do
        idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = T[t], T[t + 1], T[t + 2]
        idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = T[t], T[t + 2], T[t + 1]
    end
    local actor = lib.spawn_actor(world, wpos({ 0, 0, 0 }), 0.0)
    -- (gone with the scene: left behind, one more each visit hung in the air of the next scene at the lobby's place -
    -- "random light source in bowser 1?", 2026-11-05)
    if actor and G.extras then G.extras[#G.extras + 1] = actor end
    local pmc = actor and lib.add_pmc(actor)
    if not pmc then return end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    lib.create_section(pmc, 0, verts, idx, nrms, uvs, cols, false)
    local mid = lib.get_mid(world, "translucent", "castle_light", 0.35)     -- (both faces drawn: lighter than its 0x80)
    if mid then pmc:SetMaterial(0, mid) end
    log("castle: the lobby's sunbeam (%d stars, no Wing Cap yet)", stars)
end

-- Mario 64's look-up warp (act_first_person, SURFACE_LOOK_UP_WARP): with ten stars, standing on the lobby's sunlit
-- octagon - (-1023, -50, 717), 256 round - and looking up at the window, he is taken to the Tower of the Wing Cap
-- (warp node 0xF2: a white fade, the star sound). Mario 64 wants its C-up view tilted right up; here the camera
-- tilted up 35 degrees or more and turned toward the window, held a moment.
G.LOOKUP_AT = { -717.0 * 0.75, -1023.0 * 0.75, -50.0 * 0.75 }      -- (on G: the main chunk is at its 200 locals)
function G.look_up_tick(pawn, dt)
    if G.name ~= "castle" or G.warping or G.pending or G.dying or G.cutscene or (DIALOG and DIALOG.active) then G.lookup_t = 0.0; return end
    local l = pawn:K2_GetActorLocation()
    local x, y, z = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z - (G.half or 90.0)
    local dx, dy = x - G.LOOKUP_AT[1], y - G.LOOKUP_AT[2]
    if dx * dx + dy * dy > 190.0 * 190.0 or abs(z - G.LOOKUP_AT[3]) > 60.0 then G.lookup_t = 0.0; return end
    local MN = _G.MENU
    if ((MN and MN.star_count and MN.star_count()) or 0) < 10 then return end
    local rot = lib.controller():GetControlRotation()
    local pitch = rot.Pitch
    if pitch > 180.0 then pitch = pitch - 360.0 end
    -- (toward the window: Mario 64's -z, this scene's +X)
    local yaw = ((rot.Yaw + 180.0) % 360.0) - 180.0
    local v = pawn:GetVelocity()
    if pitch >= 35.0 and math.abs(yaw) < 60.0 and v.X * v.X + v.Y * v.Y < 2500.0 then
        G.lookup_t = (G.lookup_t or 0.0) + dt
        if G.lookup_t > 0.4 then
            local w = G.warp and G.warp[0xF2]
            if w then
                G.lookup_t = 0.0
                log("looking up from the lobby's sunbeam: to %s", tostring(w.scene))
                sfx("star_sound")
                G.warp_out("lookup", w.scene, w.node)
            end
        end
    else
        G.lookup_t = 0.0
    end
end

-- Peach's portrait at the end of the hall to the Dark World's trap door (inside_castle_seg7_dl_07023DB0): drawn with two
-- pictures in the RDP's level-of-detail blend (G_CC_TRILERP, G_TL_LOD) - Bowser's the near one, Peach's the far - so
-- that from down the hall it is Peach, and walking up to it, it turns into Bowser. Here Bowser's four tiles (textures
-- 12-15) over hers, a hair in front, seen through by the blend's fraction: at Mario 64's own 240 lines and 45 degrees
-- one of its texels (307 / 32) is one pixel 2781 away; Bowser whole nearer than that, Peach whole at twice it (more
-- seen from the side).
function G.bowser_portrait(world)
    local V = { { -7395, 1126, -5772, 0, 992 }, { -7178, 1126, -5989, 992, 992 }, { -7178, 1434, -5989, 992, 0 }, { -7395, 1434, -5772, 0, 0 },
                { -7178, 1126, -5989, 0, 992 }, { -6961, 1126, -6206, 992, 992 }, { -6961, 1434, -6206, 992, 0 }, { -7178, 1434, -5989, 0, 0 },
                { -7395, 819, -5772, 0, 992 }, { -7178, 819, -5989, 992, 992 }, { -7178, 1126, -5989, 992, 0 }, { -7395, 1126, -5772, 0, 0 },
                { -7178, 819, -5989, 0, 992 }, { -6961, 819, -6206, 992, 992 }, { -6961, 1126, -6206, 992, 0 }, { -7178, 1126, -5989, 0, 0 } }
    -- (its face toward the hall: Mario 64's +x +z, this scene's -X +Y)
    local nx, ny = -0.7071, 0.7071
    local actor = lib.spawn_actor(world, wpos({ 0, 0, 0 }), 0.0)
    if actor and G.extras then G.extras[#G.extras + 1] = actor end      -- (gone with the scene, as the sunbeam)
    local pmc = actor and lib.add_pmc(actor)
    if not pmc then return end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    local mids = {}
    for q = 0, 3 do
        local verts, nrms, uvs, cols = {}, {}, {}, {}
        for i = 1, 4 do
            local v = V[q * 4 + i]
            verts[i] = { X = -v[3] * 0.75 + nx * 0.6, Y = v[1] * 0.75 + ny * 0.6, Z = v[2] * 0.75 }
            nrms[i] = { X = nx, Y = ny, Z = 0.0 }
            uvs[i] = { X = v[4] / 1024.0, Y = v[5] / 1024.0 }
            cols[i] = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
        end
        lib.create_section(pmc, q, verts, { 0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2 }, nrms, uvs, cols, false)
        local mid = lib.get_mid(world, "translucent", string.format("levels__castle_inside__%d.rgba16", 12 + q), 1.0)
        if mid then pmc:SetMaterial(q, mid); mids[#mids + 1] = mid end
    end
    G.portrait = { actor = actor, mids = mids, x = 4491.75, y = -5383.5, z = 844.9, nx = nx, ny = ny }
    G.portrait_tick()
end

function G.portrait_tick()
    local P = G.portrait
    local cx, cy, cz = lib.camera_location({ X = P.x + OFFSET.X, Y = P.y + OFFSET.Y, Z = P.z + OFFSET.Z })
    local dx, dy, dz = cx - OFFSET.X - P.x, cy - OFFSET.Y - P.y, cz - OFFSET.Z - P.z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz) + 0.001
    local cos = (dx * P.nx + dy * P.ny) / d
    local lod = (d / 0.75) / (2781.0 * math.max(cos, 0.25))
    local a = 1.0 - math.max(0.0, math.min(1.0, lod - 1.0))
    if cos <= 0.0 then a = 0.0 end
    a = math.floor(a * 50.0 + 0.5) / 50.0
    if a == P.alpha then return end
    P.alpha = a
    if not P.actor:IsValid() then G.portrait = nil; return end
    P.actor:SetActorHiddenInGame(a <= 0.0)
    -- (the material takes its opacity as a colour, sRGB: put back to straight)
    local f = a > 0.0 and (1.055 * a ^ (1.0 / 2.4) - 0.055) or 0.0
    for _, mid in ipairs(P.mids) do
        pcall(function() mid:SetVectorParameterValue(FName("BaseColorFactor"), { R = 1.0, G = 1.0, B = 1.0, A = f }) end)
    end
end

-- an arrival under way (G.entry, from G.arrive): held, then out; on landing, a death's end
local function entry_tick(pawn, dt)
    local e = G.entry
    if not e then return end
    e.t = e.t + dt
    -- (he keeps facing out: STORROR turned him aside while he was held)
    if e.yaw then pcall(function() pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = e.yaw, Roll = 0.0 }, false) end) end
    -- (the camera's way out of a painting or up through the floor held as G.arrive set it, while he is held and the
    -- first moments he is out: STORROR's menu, shut as he left the course by EXIT COURSE, put back its own look from
    -- before - 58 degrees down, its arm out through the room's ceiling: "camera keeps going outside map when exiting
    -- cool cool mountain", "its putting the camera in the ceiling", 2026-11-05)
    if e.cam and (e.phase == "wait" or e.t < 0.6) then
        pcall(function()
            local pc = lib.controller()
            local r = pc:GetControlRotation()
            local pt = r.Pitch > 180.0 and r.Pitch - 360.0 or r.Pitch
            if math.abs(pt - e.cam.pitch) > 1.0 or math.abs(((r.Yaw - e.cam.yaw + 540.0) % 360.0) - 180.0) > 1.0 then
                pc:SetControlRotation({ Pitch = e.cam.pitch, Yaw = e.cam.yaw, Roll = 0.0 })
            end
        end)
    end
    if e.phase == "wait" then
        if e.t < e.wait then
            if e.pin then pcall(function() if pawn.CharacterMovement.MovementMode ~= 0 then pawn.CharacterMovement:SetMovementMode(0, 0) end end) end
            return
        end
        e.phase, e.t = "air", 0.0
        G.thaw_at = nil
        pcall(function()
            local cm = pawn.CharacterMovement
            cm.GravityScale = 1.0
            if e.vx ~= 0.0 or e.vy ~= 0.0 or e.vz ~= 0.0 or e.pin then
                cm:SetMovementMode(3, 0)
                -- (out of a pipe: straight up till he is over its rim)
                if e.out_above then cm.Velocity = { X = 0.0, Y = 0.0, Z = e.vz }
                else cm.Velocity = { X = e.vx, Y = e.vy, Z = e.vz } end
            end
        end)
        if e.yahoo then jump_voice("mario_yahoo") end
        if e.style == "pipe" or e.pipe then sfx("pipe_exit") end
        return
    end
    local falling = false
    pcall(function() falling = pawn.CharacterMovement:IsFalling() end)
    if falling then
        e.flew = true
        -- (launch_mario_until_land keeps his speed out every frame)
        if e.out_above then
            pcall(function()
                if pawn:K2_GetActorLocation().Z - OFFSET.Z - 90.0 > e.out_above then e.out_above = nil end
            end)
        end
        if (e.vx ~= 0.0 or e.vy ~= 0.0) and not e.out_above then
            pcall(function()
                local v = pawn.CharacterMovement.Velocity
                pawn.CharacterMovement.Velocity = { X = e.vx, Y = e.vy, Z = v.Z }
            end)
        end
        if e.t > 6.0 then G.entry = nil end
        return
    end
    if not e.flew and e.t < 0.3 then return end         -- (not off the ground yet)
    G.entry = nil
    if PLAT and PLAT.shut_traps then pcall(PLAT.shut_traps) end      -- (a trap door he came up through: back on the floor)
    if e.death then
        -- (act_death_exit and kin: "Oof" as he lands; act_death_exit_land: over on his back, "Mamma mia" at frame 54)
        local HP = _G.HEALTH
        sfx("mario_ooof2")
        G.knock_down(pawn, -e.fx * 250.0, -e.fy * 250.0, 150.0)
        G.mama_at = os.clock() + 1.6
        -- (the life itself went with the warp: G.die's warp)
    end
end

function G.tick()
    local now = os.clock()
    local dt = math.min(now - G.last_t, 0.1)
    G.last_t = now
    -- (peer-to-peer multiplayer through Steam, before anything here can return: mp.lua)
    if G.mpb == nil then local okb, mb = pcall(require, "mp"); G.mpb = okb and mb or false end
    if G.mpb then guarded("multiplayer", G.mpb.tick, dt, G) end
    if not G.name then return end
    -- The game reloaded its map (a restart, a session change): everything this mod built went with the
    -- old one. Forget it without touching it; the boot flow brings the file select back.
    local w0 = lib.world()
    local waddr = nil
    if w0 then pcall(function() waddr = w0:GetAddress() end) end
    if G.world_addr and waddr ~= G.world_addr then
        log("the map was reloaded under scene %s: dropping it", tostring(G.name))
        G.goombas, G.doors, G.paintings, G.fireballs, G.bowser = {}, {}, {}, {}, nil
        G.bombs = {}
        G.coins, G.getup_at, G.pk, G.doors_paired = {}, nil, nil, nil
        G.stars, G.red_star, G.star_exit_at, G.music_back_at = {}, nil, nil, nil
        G.secret_star, G.triggers, G.secrets = nil, {}, 0
        G.stardoors, G.warps, G.rule = {}, {}, nil
        G.water_shells, G.jingles = {}, {}
        G.bounds, G.inside = nil, nil
        PLAT.forget()
        for _, m in ipairs({ BUTTERFLY, MOVTEX, ENVFX, SCENERY, MIRROR, CAMLAK, CAPS, HOOT, POLES, CLIMB, CORK, PAINT, QSAND, HANG, SHELL, FLIGHT, SLIDE, FOOTIK, ROUNDOFF, FPV, SWIM, PAUSE, BURN, RAG }) do if m and m.forget then pcall(m.forget) end end
        for _, m in ipairs(CREATURES) do if m.forget then pcall(m.forget) end end
        G.swim, G.swim_hover = false, false
        G.dying, G.entry, G.mama_at, G.warping, G.pinned = nil, nil, nil, false, false
        if TRANS then TRANS.forget() end
        if STARSEL then STARSEL.forget() end
        if DIALOG then DIALOG.forget() end
        if G.CM then G.CM.forget() end
        G.complete = nil
        G.extras, G.trees, G.water_rects, G.sprites = {}, {}, {}, {}
        G.scene_actor, G.pmc, G.floor, G.data, G.name = nil, nil, nil, nil, nil
        G.world_addr = nil
        return
    end
    if G.warp_cool > 0 then G.warp_cool = G.warp_cool - dt end
    if G.thaw_at and now >= G.thaw_at then
        G.thaw_at = nil
        local p0 = lib.pawn()
        if p0 then pcall(function() p0.CharacterMovement.GravityScale = 1.0 end) end
    end

    local pawn = lib.pawn()
    if not pawn then
        G.no_pawn_t = (G.no_pawn_t or 0.0) + dt
        local MN = _G.MENU
        if G.no_pawn_t > 2.0 and MN and MN.state == "game" then G.no_pawn_t = 0.0; pcall(G.repossess) end
        return
    end
    G.no_pawn_t = 0.0
    -- (first: the copy of his body that is drawn takes his pose every frame, whatever the rest of the tick does)
    if FOOTIK then guarded("feet", FOOTIK.update, dt, pawn) end
    -- (HUMAN MODE's gore, while it lasts: gore.lua)
    do local GO = package.loaded["gore"]; if GO then guarded("gore", GO.tick, dt) end end
    if ROUNDOFF then guarded("roundoff", ROUNDOFF.update, dt, pawn) end
    local SHADOWS = package.loaded["shadows"]       -- (not a file-level local: the file is at Lua's 200)
    if SHADOWS then guarded("shadows", SHADOWS.tick, dt, pawn) end
    local MCAP = package.loaded["mariocap"]
    if MCAP then guarded("mario's cap", MCAP.tick, dt, pawn) end
    if package.loaded["dust"] then guarded("dust", package.loaded["dust"].tick, dt, pawn) end
    if package.loaded["race"] then guarded("race", package.loaded["race"].tick, dt, pawn) end
    if package.loaded["footsteps"] then guarded("footsteps", package.loaded["footsteps"].tick, dt, pawn) end
    if package.loaded["rooms"] then guarded("rooms", package.loaded["rooms"].tick, dt, pawn) end
    guarded("unfling", G.unfling, pawn, dt)
    guarded("flying guard", G.flying_guard, pawn, dt)
    if G.cam_shake then guarded("camera shake", G.cam_shake_tick, dt) end
    -- Mario 64's pause screen, or STORROR's menu that Start opens first: while either is up the game stands still and
    -- only the menus run
    if PAUSE and (PAUSE.open or (PAUSE.menu_up and PAUSE.menu_up())) then
        -- (in multiplayer the game goes on under the menus: the rest of this tick too - pause.lua M.online)
        local online = PAUSE.online and PAUSE.online()
        -- (the platforms stand still while paused, and stop humming, as Mario 64's do)
        local SX = package.loaded["sfx"]
        if SX and SX.quiet_held and not online then pcall(SX.quiet_held) end
        guarded("pause", PAUSE.tick, dt, G.pause_info())
        -- (once a frame: online the tick goes on past here, and ran the menus a second time below - "pretty bad lag when
        -- pausing in multiplayer", 2026-11-04: 3.7 ms each, twice a frame)
        G.pause_ticked = true
        -- (the pause tune: music.lua's tick, which starts it, is below this return)
        if not online then
            if MUSIC and MUSIC.pause_watch then guarded("pause tune", MUSIC.pause_watch) end
            return
        end
    end
    update_stage_shake(dt)
    if TRANS then guarded("transition", TRANS.tick, dt) end
    if G.mfade and G.mfade.dur and MUSIC and MUSIC.set_volume then
        local f = G.mfade
        f.t = f.t + dt
        pcall(MUSIC.set_volume, f.v0 * math.max(0.0, 1.0 - f.t / f.dur))
    end
    if STARSEL and STARSEL.active then guarded("star select", STARSEL.tick, dt) end
    if DIALOG and DIALOG.active then guarded("dialog", DIALOG.tick, dt) end
    do local CR = package.loaded["credits"]; if CR and CR.active then guarded("credits", CR.tick, dt) end end
    do local U = package.loaded["unlock"]; if U and U.active then guarded("unlock", U.tick, dt) end end
    if G.dying and G.dying.black then
        local d = G.dying
        G.dying = nil
        guarded("death warp", death_warp, d)
    end
    if G.entry then guarded("arrival", entry_tick, pawn, dt) end
    if G.name == "castle" then guarded("look up", G.look_up_tick, pawn, dt) end
    if G.data and G.data.gate_live then guarded("bowser gate", G.gate_tick, pawn, dt) end
    if G.portrait then guarded("portrait", G.portrait_tick) end
    if G.CM and G.CM.active then guarded("course complete", G.CM.tick, dt) end
    if G.complete and G.CM then guarded("course complete", G.complete_due, pawn, dt) end
    if G.mama_at and now >= G.mama_at then G.mama_at = nil; sfx("mario_mama_mia") end
    if (G.bombs and #G.bombs > 0) or #G.sprites > 0 then guarded("bombs", update_bombs) end
    -- stuck running: moving fast on his own, the stick and keys let go, for over a second, nothing of ours or STORROR's
    -- (a move, a montage) driving him -> STORROR's reset (2026-10-14: "charater got stuck running in a straight line
    -- again"). What it saw goes to the log.
    do
        local fast, why = false, nil
        pcall(function()
            local B, R = package.loaded["burn"], package.loaded["ragdoll"]
            local BF = package.loaded["bowser_fight"]
            if (B and B.active) or (R and R.active) or (BF and BF.cutscene) or G.cutscene or G.swim or G.thaw_at or G.carried then return end
            local mode = pawn.CharacterMovement.MovementMode
            if mode ~= 1 and mode ~= 5 then return end
            local v = pawn:GetVelocity()
            local speed = sqrt(v.X * v.X + v.Y * v.Y)
            if speed < 250.0 then return end
            local pc = lib.controller()
            local sx = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftX") })
            local sy = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftY") })
            if abs(sx or 0) > 0.15 or abs(sy or 0) > 0.15 then return end
            for _, k in ipairs({ "W", "A", "S", "D", "Up", "Down", "Left", "Right" }) do
                if pc:IsInputKeyDown({ KeyName = FName(k) }) then return end
            end
            local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
            if m and m:IsValid() then return end
            fast, why = true, string.format("mode %d, %.0f cm/s, no stick", mode, speed)
        end)
        if fast then
            G.runaway_t = (G.runaway_t or 0.0) + dt
            if G.runaway_t > 1.2 then
                G.runaway_t = -2.0              -- (not again at once: give the reset a moment)
                G.reset_athlete(pawn, "ran on by himself (" .. tostring(why) .. ")")
            end
        elseif (G.runaway_t or 0.0) > 0.0 then
            G.runaway_t = 0.0
        elseif G.runaway_t then
            G.runaway_t = math.min(0.0, G.runaway_t + dt)
        end
    end
    -- the last scene's actors go once he is on his feet: walking, not knocked down, not in STORROR's get-up
    if lib.retired_count() > 0 then
        local settled = false
        pcall(function()
            local R = package.loaded["ragdoll"]
            if pawn.CharacterMovement.MovementMode ~= 1 or (R and R.active) then return end
            local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
            if m and m:IsValid() then
                local n = m:GetFName():ToString()
                if n:find("Getup") or n:find("Ragdoll") then return end
            end
            settled = true
        end)
        lib.tick_retired(dt, settled)
    end
    -- stuck: falling, yet not moving at all for 2 s - wedged in something (2026-10-14, after a warp the athlete fell
    -- through the start of the Dark World course and stuck 19 m below it): put back where he last came in
    do
        local mode, v, l = 1, nil, nil
        pcall(function() mode = pawn.CharacterMovement.MovementMode; v = pawn:GetVelocity(); l = pawn:K2_GetActorLocation() end)
        local B, R = package.loaded["burn"], package.loaded["ragdoll"]
        local held = (B and B.active) or (R and R.active) or G.cutscene or G.thaw_at
        pcall(function() if pawn.CustomTimeDilation <= 0.0 then held = true end end)
        if mode == 3 and v and l and not held and (v.X * v.X + v.Y * v.Y + v.Z * v.Z) < 25.0 then
            local a = G.stuck_at
            if a and math.abs(l.X - a.X) < 2.0 and math.abs(l.Y - a.Y) < 2.0 and math.abs(l.Z - a.Z) < 2.0 then
                G.stuck_t = (G.stuck_t or 0.0) + dt
                if G.stuck_t > 2.0 then
                    G.stuck_at, G.stuck_t = nil, 0.0
                    log("stuck falling in place: put back")
                    G.respawn()
                end
            else
                G.stuck_at, G.stuck_t = { X = l.X, Y = l.Y, Z = l.Z }, 0.0
            end
        else
            G.stuck_at, G.stuck_t = nil, 0.0
        end
    end
    G.unstick(pawn, dt)
    do local okg, eg = pcall(G.floor_guard, pawn, dt); if not okg then log("floor guard error: %s", tostring(eg)) end end
    do local oks, es = pcall(G.shirt_guard, pawn, dt); if not oks and not G.shirt_err then G.shirt_err = true; log("shirt guard error: %s", tostring(es)) end end
    do local oku, eu = pcall(G.sunk_guard, pawn, dt); if not oku and not G.sunk_err then G.sunk_err = true; log("sunk guard error: %s", tostring(eu)) end end
    do local okr, er = pcall(G.run_section_tick, pawn, dt); if not okr and not G.rs_err then G.rs_err = true; log("run section tick error: %s", tostring(er)) end end
    do local okl, el = pcall(G.lava_race_tick, pawn, dt); if not okl and not G.lr_err then G.lr_err = true; log("lava race tick error: %s", tostring(el)) end end
    do local okm, em = pcall(G.mesh_guard, pawn, dt); if not okm and not G.mesh_err then G.mesh_err = true; log("mesh guard error: %s", tostring(em)) end end
    G.walk_t = (G.walk_t or 0) - dt
    if G.walk_t <= 0 then G.walk_t = 1.0; apply_walkable(pawn) end
    local loc = pawn:K2_GetActorLocation()
    local vel = pawn:GetVelocity()
    local px, py, pz = loc.X, loc.Y, loc.Z
    G.slide_walk(pawn, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0))
    local cx, cy = lib.camera_location(loc)
    local on_ground = false
    pcall(function() on_ground = not pawn.CharacterMovement:IsFalling() end)
    G.grounded = on_ground

    -- off Bowser's stage: a death, back to the course by its pipe (WARP_NODE_DEATH 0xF1 -> its 0x0C), a life gone, as in
    -- Mario 64 - "when jumping off of bowsers stage it should kill and respawn the player back at the pipe", 2026-10-18;
    -- he was put back on the stage. 12 m under its lowest floor: the Dark World's death floor is 36 m down.
    -- (once: not again while the way out is under way - a second death came as the first sent him off, and took him on
    -- out of the course to the castle: "falling off the arena teleported me all the way out of the level", 2026-10-18)
    if (G.name or ""):match("^bowser") and G.warp[0xF1] and not G.dying and not G.pending and not G.warping
        and G.warp_cool <= 0 and pz < OFFSET.Z + ((G.floor and G.floor.min_z) or -6000.0) - 1200.0 then
        G.fall_out("fell off Bowser's stage")
        return
    end
    -- fell out of the level -> back to spawn (not while a way out is under way: it put him back on Bowser's stage as his
    -- death sent him off it, 2026-10-18)
    if pz < OFFSET.Z + ((G.floor and G.floor.min_z) or -6000.0) - 2500.0 and not G.dying and not G.pending and G.warp_cool <= 0 then
        if os.clock() > (G.respawned_at or 0.0) + 1.0 then
            G.respawned_at = os.clock()
            log("fell out of the world, respawning")
            G.respawn()
        end
        return
    end
    local ok_edge, held = pcall(keep_in_level, pawn, px, py, pz)
    if not ok_edge then log("edge error: %s", tostring(held))
    elseif held then
        loc = pawn:K2_GetActorLocation()
        px, py, pz = loc.X, loc.Y, loc.Z
    end

    -- Mario's voice on a jump (play_mario_jump_sound): a first jump "Yah!", "Wah!" or "Hoo!", one straight after it
    -- "Hoo-hoo!" (the double jump), a third "Yahoo!" (the triple); STORROR's corkscrew, vortex and gainer flips "Yahoo!"
    -- too, its other flips as a jump. Heard from STORROR's own jump and flip moves (their montages), never ours.
    -- (The athlete jumped in silence, 2026-10-15.)
    pcall(function()
        local name = nil
        local ai = pawn.Mesh:GetAnimInstance()
        if ai and ai:IsValid() then
            local mt = ai:GetCurrentActiveMontage()
            if mt and mt:IsValid() then name = mt:GetFName():ToString() end
        end
        if name == G.last_montage then return end
        G.last_montage = name
        -- (his punches and kicks: Mario 64's "Yah!", "Wah!" and "Hoo!" of the punch, punch, kick (act_punching,
        -- act_move_punching - SOUND_MARIO_PUNCH_YAH/WAH/HOO); a haul up onto a ledge or a wall's top "Uh!"
        -- (act_ledge_climb_fast: SOUND_MARIO_UH2). Rendered from the ROM, 2026-10-18.)
        if name and not G.swim and not G.cutscene then
            local low = name:lower()
            if name:find("^MontageAttack") or low:find("kick") then
                local now = os.clock()
                G.punch_chain = (now - (G.punch_at or 0.0) < 0.9) and ((G.punch_chain or 0) % 3 + 1) or 1
                G.punch_at = now
                if low:find("kick") then G.punch_chain = 3 end
                jump_voice(({ "mario_punch_yah", "mario_punch_wah", "mario_punch_hoo" })[G.punch_chain])
                return
            elseif name:find("^MontageClimbClimbUp") or name:find("^MontageClimbWallPop") then
                if os.clock() - (G.uh_at or 0.0) > 1.2 then G.uh_at = os.clock(); jump_voice("mario_uh2") end
                return
            elseif name:find("^MontageClimbGrabLedge") or name:find("^MontageDescentClimbDown") then
                -- (catching a ledge from a fall, or lowering himself off one: "Whoa!" - act_ledge_grab,
                -- act_ledge_climb_down)
                if os.clock() - (G.whoa_at or 0.0) > 1.5 then G.whoa_at = os.clock(); jump_voice("mario_whoa") end
                return
            elseif name:find("^MontageBailBumpIntoWall") then
                -- (run into a wall and knocked back: "Doh!" - play_knockback_sound)
                jump_voice("mario_doh")
                return
            elseif name:find("^MontageSplat") then
                jump_voice("mario_ooof")            -- (a hard landing: act_hard_*_ground_kb's SOUND_MARIO_OOOF)
                return
            elseif name:find("^MontageDiveRollDiveRoll") then
                jump_voice("mario_hoohoo")          -- (Mario 64's dive: act_dive, SOUND_MARIO_HOOHOO)
                return
            elseif name:find("^MontageSwingLacheEject") then
                -- (let go of a bar and flung on: as off a pole, a jump's voice - act_top_of_pole_jump)
                jump_voice(({ "mario_yah", "mario_wah", "mario_hoo" })[math.random(1, 3)])
                return
            elseif name:find("^MontageDyno") then
                -- (STORROR's dynos - off a wall backwards (WallDyno180, its wall jump), off a ledge or a pole backwards,
                -- up from ledge to ledge: Mario 64's wall kick's voice, a jump's "Yah!", "Wah!" or "Hoo!" (act_wall_kick_air
                -- calls play_mario_jump_sound) - "no mario wall jump noise?", 2026-11-02)
                jump_voice(({ "mario_yah", "mario_wah", "mario_hoo" })[math.random(1, 3)])
                return
            end
        end
        if not name or not (name:find("^MontageJump") or name:find("^MontageFlip")) then return end
        local B, R, BF = package.loaded["burn"], package.loaded["ragdoll"], package.loaded["bowser_fight"]
        if (B and B.active) or (R and R.active) or (BF and BF.cutscene) or G.cutscene or G.swim then return end
        local now = os.clock()
        if name:find("^MontageFlip") and (name:find("Cork") or name:find("Vortex") or name:find("Gainer")) then
            jump_voice("mario_yahoo")
            G.jump_chain = 0
            G.triple_at = now           -- (a triple jump's worth: with the Wing Cap he flies from it - flight.lua)
        else
            G.jump_chain = (now - (G.jump_at or 0.0) < 1.6) and ((G.jump_chain or 0) % 3 + 1) or 1
            if G.jump_chain == 1 then
                jump_voice(({ "mario_yah", "mario_wah", "mario_hoo" })[math.random(1, 3)])
            elseif G.jump_chain == 2 then
                jump_voice("mario_hoohoo")
            else
                jump_voice("mario_yahoo")
                G.triple_at = now
                if CAPS and CAPS.on and CAPS.on("wing") then G.wing_boost = now end
            end
        end
        G.jump_at = now
    end)
    -- (the Wing Cap's third jump: up high, to get off the ground - "next on the third jump with wing cap make him jump
    -- up high for extra height to get off the ground", 2026-10-16. Given once he has left the ground on it, on top of
    -- STORROR's own jump; flight.lua takes him from its top)
    if G.wing_boost then
        if os.clock() - G.wing_boost > 0.8 then
            G.wing_boost = nil
        else
            local up = false
            pcall(function() up = pawn.CharacterMovement:IsFalling() and pawn:GetVelocity().Z > 50.0 end)
            if up then
                G.wing_boost = nil
                pcall(function() pawn:LaunchCharacter({ X = 0.0, Y = 0.0, Z = WING_JUMP }, false, true) end)
                log("wing cap: the third jump goes up high")
            end
        end
    end

    -- (act_panting: low on power - under 0x500, four wedges or fewer - and standing still, Mario pants: a breath each time
    -- round its animation, one of three; as loud as his jump voice)
    do
        local HP0 = _G.HEALTH
        local still = false
        pcall(function()
            local v = pawn:GetVelocity()
            still = not pawn.CharacterMovement:IsFalling() and v.X * v.X + v.Y * v.Y < 400.0
        end)
        if HP0 and HP0.health and HP0.health < 0x500 and not HP0.dead_t and still and not G.swim and not G.dying
           and not (DIALOG and DIALOG.active) and not G.star_dance_st and not (G.CM and G.CM.active) then
            G.pant_t = (G.pant_t or 0.0) + dt
            if G.pant_t > 0.6 then
                G.pant_t = G.pant_t - 1.1
                jump_voice("mario_panting_" .. math.random(1, 3))
            end
        else
            G.pant_t = 0.0
        end
    end

    -- Mario 64's power meter: damage counted out, long drops, and what happens when it runs out
    local HP = _G.HEALTH
    if HP then
        local falling = false
        pcall(function() falling = pawn.CharacterMovement:IsFalling() end)
        -- (limp - ragdolled: the drop counted from his hips - G.ragdoll_fall)
        local limp = false
        do local okl, l = pcall(G.ragdoll_fall, pawn, dt, HP); limp = okl and l end
        -- (and none while he flies - the wing cap's flight, a cannon shot: its touchdown is no drop)
        if os.clock() < (G.no_fall_until or 0) or G.carried == "fly" then
            G.air = false
        elseif limp then
            G.air = false
        elseif falling then
            if not G.air then G.air, G.peak, G.screamed, G.fall_vz, G.fall_mark = true, pz, false, 0.0, pz end
            if pz > G.peak then G.peak = pz end
            pcall(function() G.fall_vz = pawn:GetVelocity().Z end)     -- (how fast he comes down: the landing's, below)
            -- (by a wall on the way down: STORROR's fall begun again every few metres - a ledge caught is no bail,
            -- G.storror_fall_again)
            if not G.fall_mark or pz > G.fall_mark then G.fall_mark = pz end
            pcall(G.fall_moves, pawn)
            if G.fall_mark - pz > G.LEDGE_FALL.step and G.peak - pz > G.LEDGE_FALL.first and (G.fall_vz or 0.0) < 0.0 then
                local near = not G.LEDGE_FALL.walls
                if not near then
                    pcall(function()
                        near = G.wall_near(px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z, G.LEDGE_FALL.r, G.LEDGE_FALL.up) and true or false
                    end)
                end
                if near and G.storror_fall_again(pawn) then G.fall_mark = pz end
            end
            -- (sliding down a slope - STORROR's slide is a fall - the drop counts from where he leaves it. Only while its
            -- slide plays: near the floor alone was every fall's last moment too, and no drop hurt any more - "the player
            -- isnt taking damage from high falls anymore", 2026-10-16)
            local fz = floor_z(px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0) + 40.0)
            if fz and pz - OFFSET.Z - (G.half or 90.0) - fz < 40.0 then
                pcall(function()
                    local mo = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
                    if mo and mo:IsValid() and mo:GetFName():ToString():find("FallingSlide") then G.peak = pz end
                end)
            end
            -- (play_far_fall_sound: "Waaaooow" once he is 1150 Mario units below the top of his fall)
            if not G.screamed and G.peak - pz > 1150.0 * 0.75 and not G.swim then
                G.screamed = true
                sfx("mario_waaaooow")
            end
        elseif G.air then
            G.air = false
            local drop = G.peak - pz
            -- (caught on the way down - a ledge, a wall, the air grab: STORROR's catch ends its fall as a landing does,
            -- and the drop hurt him in mid-air and knocked him flat off what he held, down out of the level - "taking
            -- damage in air for some reason?", 2026-11-05, Cool, Cool Mountain. A landing is his feet on the ground:
            -- walking, or the floor within 60 cm under them. Caught, the fall is over unharmed, as Mario 64's ledge
            -- grab ends one; a fall from there counts from there.)
            local mode = 1
            pcall(function() mode = pawn.CharacterMovement.MovementMode end)
            local feet = pz - OFFSET.Z - (G.half or 90.0)
            local fz0 = floor_z(px - OFFSET.X, py - OFFSET.Y, feet + 40.0)
            if not (mode == 1 or mode == 2 or (fz0 ~= nil and feet - fz0 < 60.0)) then
                if drop > HP.FALL then log("a long drop (%.0f cm) caught in the air (movement mode %d): no harm", drop, mode) end
                drop = 0.0
            end
            -- (no fall damage on the slide courses: STORROR's slope slide is a fall all the way down; nor with the metal cap
            -- under the water - he sinks to the bottom and walks it, and Mario 64's metal Mario never takes a fall's harm
            -- there (act_metal_water_*): "make sure the player doesn't receive fall damage when using metal cap
            -- underwater", 2026-10-18)
            local metal_wet = false
            if CAPS and CAPS.on("metal") then
                local top = G.water_at(px - OFFSET.X, py - OFFSET.Y)
                metal_wet = top ~= nil and pz - OFFSET.Z - (G.half or 90.0) < top
            end
            -- (and only landing fast: check_fall_damage hurts only coming down faster than 55 a frame - 12.4 m/s here,
            -- about what an 8 m drop comes to. A slow way down from high up - the wing cap's glide, a flight's touchdown
            -- - hurt and knocked him flat, and the ragdoll went on with his speed: "just got launched randomly",
            -- 2026-10-29 - Wing Mario Over the Rainbow, out of a flight onto the rainbow and over its edge)
            local fast = (G.fall_vz or -99999.0) < -55.0 * 0.75 * 30.0
            if not fast and drop > HP.FALL then log("a long drop (%.0f cm) landed slowly (%.0f cm/s): no harm", drop, G.fall_vz or 0) end
            if fast and not G.swim and not G.SLIDE_COURSES[G.name or ""] and not metal_wet then
                local hard = drop > HP.FALL
                if drop > HP.FALL_FAR then HP.damage(HP.DAMAGE.fall_far, "a very long drop", true)
                elseif drop > HP.FALL then HP.damage(HP.DAMAGE.fall, "a long drop", true) end
                -- (a fall that hurts lands him flat - check_fall_damage -> ACT_HARD_BACKWARD_GROUND_KB - and up again
                -- after: no rolling out of it, "when taking damage from a high fall you can roll out of it", 2026-10-16)
                if hard then G.knock_down(pawn, 0.0, 0.0, 0.0) end
            end
        end
        local water = G.swim and (G.swim_under and "under" or "surface") or nil
        if water and CAPS and CAPS.on("metal") then water = nil end     -- (metal: no breath to lose)
        -- (none lost on the way out after a death: the screen black, he is given his one wedge back while still under
        -- the water, and its first frame there drowned him again - two lives for one, and out of the castle to the
        -- grounds, 2026-10-18)
        if water and (G.pending or G.dying or os.clock() < (G.breath_hold or 0.0)) then water = nil end
        if not HP.dead_t and os.clock() - (G.revived_at or -99.0) < 2.5 and HP.health < 0x100 then HP.health = 0x100 end
        if HP.tick(dt, water) then
            log("out of power%s", water == "under" and " (drowned)" or "")
            -- (GORE, the HUMAN secret's setting - secrets.lua M.gore_any: gruesome in any mode, as the power runs out -
            -- not drowned - with no one-hit death: "allows the player to be gored in any mode just without the one tap",
            -- 2026-11-04)
            if not HP.gruesome and water ~= "under" then
                local SE = package.loaded["secrets"]
                if SE and SE.gore_any and SE.gore_any() then HP.gruesome = { why = "GORE", t = os.clock() } end
            end
            if HP.gruesome then
                -- HUMAN MODE: thrown back and up off his feet, all of him, a crack of bone, his cry, the screen gone red a
                -- moment - and longer on him before the screen closes (G.HUMAN_DEATH)
                if G.swim then stop_swim(pawn, 3.0) end
                pcall(G.gruesome_death, pawn)
            else
                if G.swim then
                    -- drowned: Mario 64's cry, and out of the swim so that he goes limp
                    local S = package.loaded["sfx"]
                    if S then pcall(S.play, "mario_drowning") end
                    stop_swim(pawn, 3.0)
                else
                    sfx("mario_dying")          -- (common_death_handler: SOUND_MARIO_DYING as he goes down)
                end
                G.knock_down(pawn, 0, 0, 300)
            end
            G.set_down_for_good(true, pawn)     -- he stays down until the screen has closed on him
        end
        if HP.dead_t then
            HP.dead_t = HP.dead_t + dt
            pcall(G.keep_down, pawn)
            -- (his fall takes 54 frames, then the screen closes on him: act_death_on_back and the rest - HUMAN MODE's a while
            -- longer, to see him come down)
            if G.gruesome_tick then pcall(G.gruesome_tick, dt) end
            local wait = HP.gruesome and G.HUMAN_DEATH.wait or 1.8
            if HP.dead_t > wait and not G.dying then G.die("power", HP.gruesome and "human mode" or "out of power") end
        end
    end

    guarded("swim", update_swim, pawn, dt, loc, vel)
    -- leaves shaken out of the tree he climbs (PARTICLE_LEAF: each frame he goes up or down a tree, more than 100 over
    -- its foot, a 30% chance of a leaf - snow in CCM and SL; envfx.lua M.leaf). Climbing is climb.lua's (STORROR's way).
    if ENVFX and ENVFX.leaf and CLIMB and CLIMB.active and CLIMB.active() then
        local moved = math.abs(pz - (G.leaf_z or pz))
        G.leaf_z = pz
        G.leaf_acc = (G.leaf_acc or 0.0) + dt
        if G.leaf_acc >= 1.0 / 30.0 then
            G.leaf_acc = 0.0
            if moved > 0.5 then
                for _, t in ipairs(G.trees) do
                    local dx, dy = px - t.x, py - t.y
                    if dx * dx + dy * dy < 120.0 * 120.0 and t.z and pz - 90.0 - t.z > 75.0 then
                        if math.random() < 0.3 then
                            local lv = G.level_of and G.level_of(G.name) or G.name
                            pcall(ENVFX.leaf, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z + 40.0, lv == "ccm" or lv == "sl")
                        end
                        break
                    end
                end
            end
        end
    else
        G.leaf_z = nil
    end
    -- rings on the water round him at its surface (PARTICLE_IDLE_WATER_WAVE floating still, PARTICLE_WAVE_TRAIL swimming
    -- along: envfx.lua M.water_waves)
    if ENVFX and ENVFX.water_waves then
        local mode, top = nil, nil
        local wade_top = nil
        if not (HP and HP.dead_t) then
            local okw, wt = pcall(G.wade_tick, pawn, dt, px, py, pz)
            if okw then wade_top = wt end
        end
        if (G.swim and not G.swim_under and not (HP and HP.dead_t)) or wade_top then
            top = wade_top or water_at(px - OFFSET.X, py - OFFSET.Y)
            local sp = 0.0
            pcall(function() local v = pawn:GetVelocity(); sp = math.sqrt(v.X * v.X + v.Y * v.Y) end)
            if top then mode = (sp > 60.0) and "trail" or "idle" end
        end
        pcall(ENVFX.water_waves, px - OFFSET.X, py - OFFSET.Y, top, mode)
    end
    -- his breath under the water (mario.c: PARTICLE_BUBBLE while he swims deep - a bubble every 2-10 frames from about
    -- his head, rising to the surface: envfx.lua M.breath)
    if ENVFX and ENVFX.breath and G.swim and G.swim_under and not (HP and HP.dead_t) then
        G.breath_t = (G.breath_t or 0.0) - dt
        if G.breath_t <= 0.0 then
            G.breath_t = math.random(2, 10) / 30.0
            local top = water_at(px - OFFSET.X, py - OFFSET.Y)
            if top then pcall(ENVFX.breath, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z + 60.0, top) end
        end
    end
    guarded("talk", update_talk, pawn, px, py, pz)
    if UNDERWATER then          -- the picture turns blue while the camera is under the water
        local under = false
        pcall(function()
            local c = lib.controller().PlayerCameraManager:GetCameraLocation()
            local sz = water_at(c.X - OFFSET.X, c.Y - OFFSET.Y)
            under = sz ~= nil and c.Z - OFFSET.Z < sz
        end)
        guarded("underwater", UNDERWATER.update, dt, under)
        -- (the mist over the water stays in sight with the camera under it - "the fog texture is invisable from
        -- underneith", 2026-10-18 - where Mario 64's movtex_gen_list leaves it out)
        if package.loaded["fog"] and package.loaded["fog"].water then guarded("water fog", package.loaded["fog"].water, G.name, under) end
    end
    -- (RENDER 96's sky: its clouds' material kept up with Ultra Dynamic Sky's - sunsky.lua M.tick)
    if package.loaded["sunsky"] and package.loaded["sunsky"].tick then guarded("sunsky", package.loaded["sunsky"].tick, dt) end
    -- (RENDER 96's water: its pictures drift, the waves round him move - water96.lua M.tick)
    if package.loaded["water96"] and package.loaded["water96"].tick then guarded("water96", package.loaded["water96"].tick, dt) end
    for _, t in ipairs(G.trees) do
        local ddx, ddy = cx - t.x, cy - t.y
        if not t.fixed and ddx * ddx + ddy * ddy < 1.0e8 then
            local yaw = math.deg(math.atan(ddy, ddx)) + 180.0
            local d = math.abs(((yaw - t.yaw + 540.0) % 360.0) - 180.0)
            if d > 1.5 then
                t.yaw = yaw
                pcall(function() t.actor:K2_SetActorRotation({ Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false) end)
            end
        end
    end
    if not (DIALOG and DIALOG.active) then
        -- (far ones - over G.LOD_NEAR from him, not after him, not being squashed - every G.LOD_EVERY frames, their time
        -- saved up for them: eleven took 1.4 ms of every frame, the most of anything of the mod's - "some lag coming
        -- through now", "just in general", 2026-10-31. Each its own frame of the three, so they do not all go at once.)
        -- (and further off - up or down too, the run's level a tower - less often again: of the Bowser run's 34, 28 were
        -- over 50 m off, 18 over 100 m - "I want a significant boost in fps", 2026-11-03)
        G.lod_frame = (G.lod_frame or 0) + 1
        local ending = G.ending_on()
        for i, g in ipairs(G.goombas) do
            g.lod_dt = (g.lod_dt or 0.0) + dt
            local every = 1
            if g.state ~= "chase" and g.state ~= "dead" and not ending then
                local gdx, gdy, gdz = px - OFFSET.X - g.x, py - OFFSET.Y - g.y, pz - OFFSET.Z - (g.z or (pz - OFFSET.Z))
                local d = math.sqrt(gdx * gdx + gdy * gdy + gdz * gdz)
                -- (every 6th and 4th at most: at every 12th they stood still and jumped - "enemies freezing randomly",
                -- 2026-11-04 - and the time they missed theirs, up to a fifth of a second, not a tenth: slowed, too)
                if d > G.LOD_NEAR then every = (d > 10000.0) and 6 or ((d > 5000.0) and 4 or G.LOD_EVERY) end
            end
            if every == 1 or (G.lod_frame + i) % every == 0 then
                guarded("goomba", update_goomba, g, math.min(g.lod_dt, (every > 1) and 0.2 or 0.1), px, py, pz, vel.Z, cx, cy)
                g.lod_dt = 0.0
            end
        end
        guarded("goombas apart", G.goombas_apart)
    else
        -- (time stopped: their faces still turned to the camera - the dialog's comes round)
        for _, g in ipairs(G.goombas) do
            if g.inst then pcall(lib.face_camera, g.inst, g.x + OFFSET.X, g.y + OFFSET.Y) end
        end
    end
    update_coins(dt, px, py, pz, cx, cy)
    if G.wlevel then pcall(apply_water_level, dt) end
    guarded("water texture", turn_water, dt)
    if G.gas_rects and #G.gas_rects > 0 then guarded("gas", G.poison_gas, dt, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0)) end
    if MUSIC and MUSIC.tick then guarded("music", MUSIC.tick, dt) end
    if G.data and G.data.whirlpools and #G.data.whirlpools > 0 then
        guarded("rush", G.water_rush, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z)
    end
    if MOVTEX then guarded("movtex", MOVTEX.update, dt) end
    if ENVFX then guarded("snow", ENVFX.update, dt) end
    if SCENERY then guarded("scenery", SCENERY.update, dt, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0)) end
    if MIRROR then guarded("mirror", MIRROR.update, dt, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0)) end
    if CAPS then guarded("caps", CAPS.update, dt, pawn) end
    if package.loaded["twirl"] then guarded("twirl", package.loaded["twirl"].update, dt, pawn) end     -- (a tornado's ride)
    if package.loaded["waterclimb"] then guarded("waterclimb", package.loaded["waterclimb"].update, dt, pawn) end -- (out of the water)
    if HOOT then guarded("hoot", HOOT.update, dt, pawn, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0)) end
    if G.ddd_slide then guarded("ddd painting", update_ddd_slide, dt) end
    if G.pss and G.pss.running then
        G.pss.t = G.pss.t + dt
        if _G.HEALTH then _G.HEALTH.clock = G.pss.t end
    end
    if POLES then guarded("poles", POLES.update, dt, pawn, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0)) end
    if CLIMB then guarded("climb", CLIMB.update, dt, pawn) end
    if package.loaded["lamps"] then guarded("lamps", package.loaded["lamps"].update, dt, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z) end
    if HANG then guarded("hang", HANG.update, dt, pawn, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0)) end
    if SHELL then guarded("shell", SHELL.update, dt, pawn, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0)) end
    if FLIGHT then guarded("flight", FLIGHT.update, dt, pawn, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0)) end
    if SLIDE then guarded("slide", SLIDE.update, dt, pawn, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0), G.name) end
    if #G.water_shells > 0 then guarded("shells", update_water_shells, dt, pawn, px, py, pz) end
    if #G.jingles > 0 then guarded("jingles", update_jingles, px, py, pz) end
    if CAMLAK then
        local yaw = 0.0
        pcall(function() yaw = pawn:K2_GetActorRotation().Yaw end)
        guarded("camlakitu", CAMLAK.update, dt, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0), yaw)
    end
    if G.welcome_at and os.clock() >= G.welcome_at and not G.pending and not G.warping
        and not (DIALOG and DIALOG.active) then
        G.welcome_at = nil
        G.say(21, function() if MUSIC and G.data then pcall(MUSIC.play, G.data.music) end end)
    end
    if BURN then guarded("burn", BURN.tick, dt) end
    if G.athlete_hidden then guarded("out of sight", G.hidden_tick) end
    if RAG then guarded("ragdoll", RAG.tick, dt) end
    if CORK then guarded("cork", CORK.update, dt, pawn) end
    if PAINT then guarded("painting", PAINT.update, dt, pawn) end
    if FPV then         -- first person, when the file select's switch is on and nothing else has the camera
        local MN, IN = _G.MENU, package.loaded["intro"]
        local on = MN and MN.first_person and MN.first_person() and MN.state == "game" and not (IN and IN.active)
            and not (STARSEL and STARSEL.active) and not (PAINT and PAINT.holding())
            and not (PLAT.camera_busy and PLAT.camera_busy()) and not G.star_cut and not G.dialog_cam
            and not (G.star_dance_st and G.star_dance_st.cam)
        guarded("first person", FPV.update, dt, pawn, on)
    end
    if BUTTERFLY then
        local pyaw = 0.0
        pcall(function() pyaw = pawn:K2_GetActorRotation().Yaw end)
        guarded("butterfly", BUTTERFLY.update, dt, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0), pyaw)
    end
    update_stars(dt, px, py, pz)
    guarded("star cutscene", star_cut_tick, dt)
    guarded("star dance", star_dance_tick, dt)
    guarded("dialog cutscene", dialog_cut_tick, dt)
    if G.getup_at and os.clock() >= G.getup_at then
        G.getup_tries = G.getup_tries + 1
        G.get_up(pawn)
        G.getup_at = (G.getup_tries < 6) and (os.clock() + 0.8) or nil
    end
    if not G.doors_paired then G.doors_paired = true; pair_doors() end
    for _, dr in ipairs(G.doors) do guarded("door", update_door, dr, dt, px, py, pz) end
    do
        local half = G.half
        if not half then
            half = 90.0
            pcall(function() half = pawn.CapsuleComponent.CapsuleHalfHeight end)
            if type(half) ~= "number" or half < 20.0 then half = 90.0 end
            G.half = half
        end
        local sx, sy, sz = px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - half      -- scene space, at his feet
        local grounded = false
        pcall(function() grounded = not pawn.CharacterMovement:IsFalling() end)
        guarded("platform", PLAT.update, dt, sx, sy, sz, grounded)
        -- (a message on the screen stops them, as Mario 64 stops time for one: TIME_STOP_DIALOG)
        local still = (DIALOG and DIALOG.active) or (G.CM and G.CM.active)
        for _, m in ipairs(CREATURES) do
            if m.update and not still then guarded("creature", m.update, dt, px, py, pz)
            elseif still and m.reface then guarded("creature", m.reface) end
        end
        guarded("floors", update_floors, pawn, sx, sy, sz, grounded)
        pcall(G.lava_limp, pawn)
        local speed = sqrt(vel.X * vel.X + vel.Y * vel.Y)
        if G.wind_dir or G.wind_v then guarded("wind", G.apply_wind, dt, pawn, grounded) end
        if G.vwind and not grounded then guarded("vwind", G.apply_vwind, dt, pawn, sz)
        elseif not grounded and G.vwind_rule then guarded("vwind", G.apply_vwind, dt, pawn, sz, true) end
        if G.sand_push or G.pit_pull then guarded("sand", G.apply_sand, dt, pawn) end      -- (on it: within 12 of it - its own steps make him "fall" a moment)
        if QSAND and not G.swim and not G.carried and not G.star_dance_st then
            local ok, under = pcall(QSAND.update, dt, pawn, G.sink_kind, grounded, speed > 60.0)
            if ok and under and _G.HEALTH and not _G.HEALTH.dead_t and not G.dying then
                log("under the quicksand")
                if not (QSAND.sucked and QSAND.sucked(pawn)) then _G.HEALTH.kill("quicksand") end
            end
        end
        guarded("warps", update_warps, dt, sx, sy, sz, speed, grounded)
        if STOR then guarded("storror", STOR.tick, pawn) end
        if PAUSE and not G.pause_ticked then guarded("pause", PAUSE.tick, dt, G.pause_info()) end
        G.pause_ticked = nil
        guarded("stardoor", update_stardoors, dt, sx, sy, sz)
    end
    if G.bowser then guarded("bowser", update_bowser, G.bowser, dt, px, py, pz, cx, cy) end
    if #G.fireballs > 0 then guarded("fireball", update_fireballs, dt, px, py, pz, cx, cy) end

    if G.pending then
        local p = G.pending
        G.pending = nil
        local opt = p.opt or {}
        log("warp -> %s%s", tostring(p.name), p.node and string.format(" node 0x%02X", p.node) or "")
        if p.name == G.name and p.node then
            G.arrive(p.node, opt)                   -- somewhere else in the same scene: nothing to rebuild
        else
            local keep = nil
            if opt.move then
                local l = pawn:K2_GetActorLocation()
                keep = { X = l.X + opt.move[1], Y = l.Y + opt.move[2], Z = l.Z + opt.move[3] + 5.0 }
            end
            if G.load_scene(p.name, true) ~= false then
                if keep then
                    -- the next area carries straight on from this one: same place, moved by what the level says
                    pcall(function() pawn:K2_TeleportTo(keep, pawn:K2_GetActorRotation()) end)
                    G.freeze(0.6)
                    -- (and nothing put back round him touches him for a moment: every creature starts again where the
                    -- level puts it, and one there - a Piranha Plant by Whomp's Fortress's edge - bit him at once, its
                    -- knock-down threw him off the level: "sometimes get launched when changing graphics to render 96",
                    -- 2026-11-01)
                    G.safe_until = os.clock() + G.REBUILD_SAFE
                    if _G.HEALTH then _G.HEALTH.grace = math.max(_G.HEALTH.grace or 0.0, G.REBUILD_SAFE) end
                    -- (no fall counted while he is held there, only: 3 s of none, and a jump off the level straight
                    -- after came to nothing - "just fell from a high height took no damage", 2026-11-02)
                    G.air, G.no_fall_until, G.warp_cool = false, os.clock() + 0.8, 1.5
                    G.last_node, G.last_opt = nil, nil
                    -- (where he came in, for a respawn: these areas - the Tall Mountain's slide past its first part,
                    -- the pyramid's top - have no start point of their own, and one sent him to (0, 0, 0) in the void,
                    -- over and over)
                    local r0 = { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }
                    pcall(function() r0 = pawn:K2_GetActorRotation() end)
                    G.came_in = { scene = p.name, X = keep.X, Y = keep.Y, Z = keep.Z, yaw = r0.Yaw }
                elseif not G.arrive(p.node, opt) then
                    G.teleport_spawn()
                end
            end
        end
        music_back()
        if TRANS and TRANS.is_black() then
            local o = (not G.data or not G.name) and { "star", 16 } or (G.open_with or { "star", 16 })
            G.open_with = nil
            TRANS.open(o[1], o[2])
        end
    end
end

return G
