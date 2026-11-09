-- SM64Map: the ghost race's ghost - a run recorded and played back, whole body and all ("next you have to record my
-- ghost", then "yes, build the full-pose ghost recording, playback, and the faster-run takeover per save file",
-- 2026-10-27).
--
-- A run, from GO to over the finish: 20 times a second where his body is (its mesh in the world) and how 33 of its bones
-- lie in its own space - the hips, spine, neck and head, the arms (their twists too: no wrung forearms), hands, legs and
-- feet; not the fingers, 358 bones in all. Played back on the racer's body, eased between the samples each frame: his
-- flips, vaults and climbs as they were run.
--
-- Kept small, as packed numbers: a sample's time and place as floats, its turns and the bones' places as 16-bit numbers
-- (a quaternion's parts in 1/32767, a bone's place in 1/50 cm). Some 490 bytes a sample: 2.3 MB for four minutes.
--   The level's own ghost, the mod's: Scripts/data/race_ghost_<scene>.bin - the first run finished with none there.
--   A save file's best run: race_file<n>_<scene>.bin by saves.lua - raced instead when it is the faster.
local lib = require("lib")
local log = lib.log

local M = {}
M.RATE = 20.0                       -- samples a second
M.MAX_SECONDS = 15 * 60             -- (a run longer than this is not kept)
M.BONES = {
    "pelvis", "spine_01", "spine_02", "spine_03", "spine_04", "spine_05", "neck_01", "neck_02", "Head",
    "clavicle_l", "upperarm_l", "upperarm_twist_01_l", "upperarm_twist_02_l", "lowerarm_l", "lowerarm_twist_01_l",
    "lowerarm_twist_02_l", "hand_l",
    "clavicle_r", "upperarm_r", "upperarm_twist_01_r", "upperarm_twist_02_r", "lowerarm_r", "lowerarm_twist_01_r",
    "lowerarm_twist_02_r", "hand_r",
    "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r",
}   -- (parents before their children: set in this order, each is placed under its parent as it now lies)
local MAGIC = "SM64GHOST1"
-- (a run through more than one area of a course - race.lua M.CHAIN, Shifting Sand Land out into its pyramid: where it
-- went on into each, `seams` { { t, scene } }, kept after its head - "Carry into pyramid", 2026-11-07. Its samples'
-- places are each in the area it was in then.)
local MAGIC2 = "SM64GHOST2"
local POS = 50.0                    -- a bone's place: 1/50 cm a step (+-655 cm)
local Q = 32767.0

local function frame_fmt(nb) return "<ffffhhhh" .. string.rep("hhhhhhh", nb) end

local function clamp16(v) v = math.floor(v + 0.5); if v > 32767 then return 32767 elseif v < -32767 then return -32767 end return v end

-- ------------------------------------------------------------ recording
local rec = nil                     -- { parts, n, last, fmt, fnames, mesh }

function M.recording() return rec ~= nil end

function M.rec_start(pawn)
    local mesh = nil
    pcall(function() mesh = pawn.Mesh end)
    if not (mesh and mesh:IsValid()) then rec = nil; return false end
    local fnames = {}
    for i, b in ipairs(M.BONES) do fnames[i] = FName(b) end
    rec = { parts = {}, n = 0, last = -1.0, fmt = frame_fmt(#M.BONES), fnames = fnames, mesh = mesh, seams = {} }
    return true
end

-- the run gone on into the area `scene` at `t` s since GO (race.lua, as it carries the race on)
function M.rec_seam(t, scene)
    if rec then rec.seams[#rec.seams + 1] = { t, scene } end
end

function M.rec_drop() rec = nil end

-- one sample at `t` s since GO, if a 20th of a second has gone since the last (or `force`)
function M.rec_tick(t, force)
    local r = rec
    if not r then return end
    if not force and t - r.last < 1.0 / M.RATE - 0.002 then return end
    if t > M.MAX_SECONDS then rec = nil; log("race ghost: the run went past %d minutes - not kept", M.MAX_SECONDS // 60); return end
    local ok, err = pcall(function()
        local mesh = r.mesh
        if not mesh:IsValid() then error("his body is gone") end
        -- (the body he is drawn as: footik.lua's copy of it while that is drawn - the swim's strokes are on it, and his
        -- feet set on the ground; his own, hidden then, stood in STORROR's idle in the water - "also ghost doesnt have
        -- swimming animation in water", 2026-11-06)
        local F = package.loaded["footik"]
        local fs = F and F.debug and F.debug()
        if fs and fs.on and fs.pose and fs.pose:IsValid() then mesh = fs.pose end
        local w = mesh:K2_GetComponentToWorld()
        local O = lib.OFFSET
        local vals = { t, w.Translation.X - O.X, w.Translation.Y - O.Y, w.Translation.Z - O.Z,
                       clamp16(w.Rotation.X * Q), clamp16(w.Rotation.Y * Q), clamp16(w.Rotation.Z * Q), clamp16(w.Rotation.W * Q) }
        for i = 1, #r.fnames do
            local b = mesh:GetSocketTransform(r.fnames[i], 2)        -- (RTS_Component: in the mesh's own space)
            local p, q = b.Translation, b.Rotation
            vals[#vals + 1] = clamp16(p.X * POS); vals[#vals + 1] = clamp16(p.Y * POS); vals[#vals + 1] = clamp16(p.Z * POS)
            vals[#vals + 1] = clamp16(q.X * Q); vals[#vals + 1] = clamp16(q.Y * Q); vals[#vals + 1] = clamp16(q.Z * Q)
            vals[#vals + 1] = clamp16(q.W * Q)
        end
        r.n = r.n + 1
        r.parts[r.n] = string.pack(r.fmt, table.unpack(vals))
        r.last = t
    end)
    if not ok then rec = nil; log("race ghost: recording stopped (%s)", tostring(err)) end
end

-- the run finished: its last sample taken at `t_last` (the world's clock, held while paused - the samples' own), and it
-- handed back to be kept with its time `final` (the race timer's, which runs on through a pause) - { n, final, data } -
-- or nil
-- (the race's developer mode, race.lua M.dev_keep / M.dev_respawn: how far the recording has got, and back to there -
-- a stretch not finished, its samples dropped, the run recorded on from where it was then)
function M.rec_mark() return rec and rec.n or nil end
function M.rec_cut(n)
    local r = rec
    if not (r and n) then return false end
    for i = r.n, n + 1, -1 do r.parts[i] = nil end
    if n < r.n then r.n = n end
    r.last = -1.0
    return true
end

function M.rec_finish(t_last, final)
    if not rec then return nil end
    final = final or t_last
    M.rec_tick(t_last, true)
    local r = rec
    rec = nil
    if not r or r.n < 2 then return nil end
    return { n = r.n, final = final, data = table.concat(r.parts), seams = (#(r.seams or {}) > 0) and r.seams or nil }
end

-- ------------------------------------------------------------ the files
local cache = {}                    -- path -> ghost (or false: none there)
local function data_dir() return lib.MOD_DIR .. "Scripts\\data\\" end
function M.original_path(scene) return data_dir() .. "race_ghost_" .. scene .. ".bin" end
function M.file_path(slot, scene) return lib.MOD_DIR .. "race_file" .. tostring(slot) .. "_" .. scene .. ".bin" end

-- write run `run` ({ n, final, data }) to `path`, with the save file's play time `played` (seconds; 0 for the level's
-- own): to a .tmp first, then over the old one
function M.save(path, run, played)
    local seams = run.seams
    local head = { (seams and #seams > 0) and MAGIC2 or MAGIC }
    head[#head + 1] = string.pack("<IHff", run.n, #M.BONES, run.final, played or 0.0)
    if seams and #seams > 0 then
        head[#head + 1] = string.pack("<H", #seams)
        for _, s in ipairs(seams) do head[#head + 1] = string.pack("<f", s[1]) .. string.pack("s1", s[2]) end
    end
    for _, b in ipairs(M.BONES) do head[#head + 1] = string.pack("s1", b) end
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "wb")
    if not f then log("race ghost: could not write %s", tmp); return false end
    f:write(table.concat(head), run.data)
    f:close()
    local moved = pcall(function()
        os.remove(path)
        assert(os.rename(tmp, path))
    end)
    if not moved then
        -- (no renaming to be had: written over it straight)
        local g = io.open(path, "wb")
        if not g then log("race ghost: could not write %s", path); return false end
        g:write(table.concat(head), run.data)
        g:close()
        pcall(os.remove, tmp)
    end
    cache[path] = nil
    log("race ghost: kept %d samples, %.2f s, in %s (%.1f MB)", run.n, run.final, path:match("[^\\/]+$"), (#run.data) / 1048576.0)
    return true
end

-- a ghost from `path`: { n, final, played, fmt, size, start, data, names } - or nil
function M.load(path)
    local c = cache[path]
    if c ~= nil then return c or nil end
    local f = io.open(path, "rb")
    if not f then cache[path] = false; return nil end
    local s = f:read("a")
    f:close()
    local v2 = s:sub(1, #MAGIC2) == MAGIC2
    if not v2 and s:sub(1, #MAGIC) ~= MAGIC then cache[path] = false; log("race ghost: %s is not a ghost", path); return nil end
    local pos = #MAGIC + 1
    local n, nb, final, played
    n, nb, final, played, pos = string.unpack("<IHff", s, pos)
    local seams = nil
    if v2 then
        local ns
        ns, pos = string.unpack("<H", s, pos)
        seams = {}
        for i = 1, ns do
            local st, sc
            st, pos = string.unpack("<f", s, pos)
            sc, pos = string.unpack("s1", s, pos)
            seams[i] = { st, sc }
        end
    end
    local names = {}
    for i = 1, nb do names[i], pos = string.unpack("s1", s, pos) end
    local fmt = frame_fmt(nb)
    local size = string.packsize(fmt)
    if #s < pos - 1 + n * size then cache[path] = false; log("race ghost: %s is cut short", path); return nil end
    local fnames = {}
    for i, b in ipairs(names) do fnames[i] = FName(b) end
    local g = { n = n, final = final, played = played, fmt = fmt, size = size, start = pos, data = s, names = names,
                fnames = fnames, path = path, seams = seams }
    cache[path] = g
    return g
end

function M.forget(path) if path then cache[path] = nil else cache = {} end end

-- the area the run was in at `t` s: the last it went on into by then, else `head` (where it began)
function M.scene_at(g, t, head)
    local sc = head
    for _, s in ipairs(g.seams or {}) do if s[1] <= t then sc = s[2] else break end end
    return sc
end

-- ------------------------------------------------------------ playing one back
local function frame(g, i)
    return table.pack(string.unpack(g.fmt, g.data, g.start + (i - 1) * g.size))
end
local function time_of(g, i) return (string.unpack("<f", g.data, g.start + (i - 1) * g.size)) end

-- the pose at `t` s: where his body is (scene cm) and its turn, and each bone's place and turn in its own space -
-- eased between the samples either side. `cur`: a cursor kept by the one playing it (the samples are gone through in
-- order). Returns body = { x, y, z, qx, qy, qz, qw }, bones = { { x, y, z, qx, qy, qz, qw }, ... }, done - the same
-- tables each time, kept in `cur`, and each sample read where it lies, not unpacked whole: two whole samples and 34
-- tables made every frame kept Lua's collector busy as the ghost ran - "when I was racing ghost in bomb omb
-- battlefield", stutters, 2026-11-03.
local HEAD_FMT, BONE_FMT = "<ffffhhhh", "<hhhhhhh"
local HEAD_SIZE, BONE_SIZE = 24, 14
local sunpack, sqrt = string.unpack, math.sqrt
local function nquat(ax, ay, az, aw, bx, by, bz, bw, k)
    ax, ay, az, aw, bx, by, bz, bw = ax / Q, ay / Q, az / Q, aw / Q, bx / Q, by / Q, bz / Q, bw / Q
    if ax * bx + ay * by + az * bz + aw * bw < 0.0 then bx, by, bz, bw = -bx, -by, -bz, -bw end
    local x, y, z, w = ax + (bx - ax) * k, ay + (by - ay) * k, az + (bz - az) * k, aw + (bw - aw) * k
    local l = sqrt(x * x + y * y + z * z + w * w)
    if l < 1e-6 then return 0.0, 0.0, 0.0, 1.0 end
    return x / l, y / l, z / l, w / l
end
function M.pose(g, t, cur)
    local i = math.max(1, math.min(g.n - 1, cur.i or 1))
    if time_of(g, i) > t then i = 1 end
    while i < g.n - 1 and time_of(g, i + 1) <= t do i = i + 1 end
    cur.i = i
    local pa = g.start + (i - 1) * g.size
    local pb = pa + g.size
    local ta, ax, ay, az, aqx, aqy, aqz, aqw = sunpack(HEAD_FMT, g.data, pa)
    local tb, bx, by, bz, bqx, bqy, bqz, bqw = sunpack(HEAD_FMT, g.data, pb)
    local k = (tb > ta) and math.max(0.0, math.min(1.0, (t - ta) / (tb - ta))) or 1.0
    local body = cur.body
    if not body then body = {}; cur.body = body end
    body[1], body[2], body[3] = ax + (bx - ax) * k, ay + (by - ay) * k, az + (bz - az) * k
    body[4], body[5], body[6], body[7] = nquat(aqx, aqy, aqz, aqw, bqx, bqy, bqz, bqw, k)
    local bones = cur.bones
    if not bones then bones = {}; cur.bones = bones end
    local nb = #g.fnames
    for j = 1, nb do
        local off = HEAD_SIZE + (j - 1) * BONE_SIZE
        local a1, a2, a3, a4, a5, a6, a7 = sunpack(BONE_FMT, g.data, pa + off)
        local b1, b2, b3, b4, b5, b6, b7 = sunpack(BONE_FMT, g.data, pb + off)
        local e = bones[j]
        if not e then e = {}; bones[j] = e end
        e[1], e[2], e[3] = (a1 + (b1 - a1) * k) / POS, (a2 + (b2 - a2) * k) / POS, (a3 + (b3 - a3) * k) / POS
        e[4], e[5], e[6], e[7] = nquat(a4, a5, a6, a7, b4, b5, b6, b7, k)
    end
    return body, bones, t >= tb and i + 1 >= g.n
end

-- ------------------------------------------------------------ quaternions (x, y, z, w), as Unreal's FQuat
function M.qmul(ax, ay, az, aw, bx, by, bz, bw)
    return aw * bx + ax * bw + ay * bz - az * by,
           aw * by - ax * bz + ay * bw + az * bx,
           aw * bz + ax * by - ay * bx + az * bw,
           aw * bw - ax * bx - ay * by - az * bz
end
function M.qrot(qx, qy, qz, qw, vx, vy, vz)
    local tx, ty, tz = 2.0 * (qy * vz - qz * vy), 2.0 * (qz * vx - qx * vz), 2.0 * (qx * vy - qy * vx)
    return vx + qw * tx + (qy * tz - qz * ty), vy + qw * ty + (qz * tx - qx * tz), vz + qw * tz + (qx * ty - qy * tx)
end

return M
