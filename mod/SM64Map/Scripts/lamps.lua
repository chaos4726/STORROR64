-- SM64Map: lamps indoors.
--
-- "live shadows are messed up in the castle", "just in general the lighting is terrible im guessing because its an
-- inclosed space and you only have 1 light source", 2026-10-31. With real-time shadows on (game.lua G.LIT_LEVELS) the
-- castle's floors were lit by the sun outside alone - their shade the castle's own roof and walls, sunlight leaking in
-- through every seam - and by the soft lights all round (menu.lua M.AMBIENT_ROTS), which pass through walls alike: flat,
-- with bright patches where no light could be. Indoors now the sun is put out and the rooms get lamps of their own.
--
-- Where: Mario 64's own rooms (data/rooms.lua - each floor triangle's room). Each room in squares of CELL; over each
-- square with floor enough (MIN_AREA), above the floor triangle nearest its middle, a lamp LAMP_DOWN under the ceiling
-- (MAX_UP over the floor at most); two of a room closer than MERGE made one. Which: every lamp of his room (rooms.lua
-- M.mario) and of the rooms of the NEAR lamps nearest him - the doorway he stands in, the room through it - at most LIT,
-- the nearest; the MAX nearest of them casting shadows (the walls stop those, so none shines into the next room), the
-- rest light without. Only the nearest few were lit at first: the far end of his own room went dark and its lamps came on
-- and went off as he walked - "lights get dim when far from them?", 2026-10-31. Faded in and out (FADE a second); the
-- rest are out. Point lights, warm, soft-edged (SOURCE_R).
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET

local M = {}
M.SCENES = { castle = true, castle2 = true, castle3 = true }
-- (and every enclosed level: the caves, the pyramid, the clock, the slides, the ship, the igloo, the haunted house -
-- "all enclosed levels need lamps and correct lighting", 2026-10-31. Their floors: data/rooms.lua where Mario 64 has
-- rooms, else data/lamp_floors.lua - tools/lampfloors.py, each area one room)
for _, n in ipairs({ "bbh", "hmc", "cotmc", "vcutm", "pss", "sa", "ttc", "ssl_2", "ssl_3", "lll_2", "ccm_2", "sl_2",
                     "ttm_2", "ttm_3", "ttm_4", "thi_3", "jrb_2", "ddd_2", "wdw_2" }) do M.SCENES[n] = true end
-- (a lamp's colour where the warm indoor one is wrong: the volcano's glow, under the sea, the ice)
M.SCENE_COLOR = {
    lll_2 = { R = 1.0, G = 0.58, B = 0.32, A = 1.0 },
    sa = { R = 0.62, G = 0.85, B = 1.0, A = 1.0 }, jrb_2 = { R = 0.66, G = 0.86, B = 1.0, A = 1.0 },
    ddd_2 = { R = 0.62, G = 0.85, B = 1.0, A = 1.0 },
    ccm_2 = { R = 0.86, G = 0.93, B = 1.0, A = 1.0 }, sl_2 = { R = 0.86, G = 0.93, B = 1.0, A = 1.0 },
    vcutm = { R = 0.8, G = 0.9, B = 1.0, A = 1.0 },
}
M.CELL = 900.0
M.MIN_AREA = 12.0e4          -- (cm^2: 12 m^2 of floor in a square)
M.MERGE = 450.0
M.LAMP_DOWN = 60.0
M.MAX_UP = 520.0
M.MIN_UP = 180.0
M.MAX = 3                    -- (casting shadows: 5 were heavy on the GPU - "some lag coming through now", 2026-10-31)
M.NEAR = 4                   -- (the rooms of this many nearest lamps lit whole, with his own)
M.LIT = 16
-- (fewer in the basement: its 41 lamps in small rooms close together lit 16 at once, 3 with shadows - a point light's
-- shadow draws the scene six times over - and it ran at 81 a second, 111 with them all out: "80 fps in basement",
-- "still terrible fps in basement", 2026-11-05)
-- (16 again with the one shadow: 8 left the rooms he walked away from going dark - "areas going dark when moving from
-- them", 2026-11-06 - and 16 cost 0.26 ms a frame there, 11.48 to 11.74)
M.SCENE_LIT = { castle3 = 16 }
-- (none with shadows there: the one cost 2.2 ms a frame, 12.3 to 10.0 - "its 80 fps should be 120", 2026-11-06)
M.SCENE_MAX = { castle3 = 0 }
M.REACH = 6000.0             -- (no lamp further off than this lit)
M.SAME_ROOM = 900.0          -- (cm taken off a lamp's distance in his own room, choosing)
M.LUX = 6.0                  -- (about this on the floor under a lamp; 4 with the fill at 0.55 was flat, 2026-10-31)
M.SOURCE_R = 25.0
M.FADE = 2.5
M.COLOR = { R = 1.0, G = 0.88, B = 0.72, A = 1.0 }
M.AMB_IN = 0.4               -- (each soft light all round, indoors, with the lamps: low enough for their pools to show)
M.CHOOSE_EVERY = 0.25

local st = nil               -- { world, name, lamps = { { x, y, z, room, I, r, a, lc, w, want } }, t, sun_t }

local function valid(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

-- the lamps of scene `name`, worked out from its rooms (scene centimetres)
local function plan(name)
    local data = lib.load_data("data.rooms")
    local t = data and data[name]
    if not t then
        local lf = lib.load_data("data.lamp_floors")
        t = lf and lf[name]
    end
    if not t then return {} end
    local col = M.SCENE_COLOR[name] or M.COLOR
    local G = package.loaded["game"]
    local cells = {}
    for i = 1, #t, 10 do
        local ax, ay, az, bx, by, bz, cx, cy, cz, room = t[i], t[i + 1], t[i + 2], t[i + 3], t[i + 4], t[i + 5], t[i + 6], t[i + 7], t[i + 8], t[i + 9]
        local a = math.abs((bx - ax) * (cy - ay) - (cx - ax) * (by - ay)) * 0.5
        if a > 1.0 then
            local mx, my, mz = (ax + bx + cx) / 3.0, (ay + by + cy) / 3.0, (az + bz + cz) / 3.0
            local k = room .. ":" .. math.floor(mx / M.CELL) .. ":" .. math.floor(my / M.CELL)
            local c = cells[k]
            if not c then c = { room = room, a = 0.0, sx = 0.0, sy = 0.0, tris = {} }; cells[k] = c end
            c.a, c.sx, c.sy = c.a + a, c.sx + mx * a, c.sy + my * a
            c.tris[#c.tris + 1] = { mx, my, mz }
        end
    end
    local lamps = {}
    for _, c in pairs(cells) do
        if c.a >= M.MIN_AREA then
            local gx, gy = c.sx / c.a, c.sy / c.a
            local best, bd = nil, nil
            for _, p in ipairs(c.tris) do
                local d = (p[1] - gx) ^ 2 + (p[2] - gy) ^ 2
                if not bd or d < bd then best, bd = p, d end
            end
            local x, y, f = best[1], best[2], best[3]
            local ceil = G and G.ceil_z and G.ceil_z(x, y, f + 30.0) or nil
            local z = ceil and (ceil - M.LAMP_DOWN) or (f + 400.0)
            z = math.max(f + M.MIN_UP, math.min(z, f + M.MAX_UP))
            local near = false
            for _, l in ipairs(lamps) do
                if l.room == c.room and (l.x - x) ^ 2 + (l.y - y) ^ 2 < M.MERGE * M.MERGE and math.abs(l.z - z) < 200.0 then near = true; break end
            end
            if not near then
                local up = (z - f) / 100.0
                lamps[#lamps + 1] = { x = x, y = y, z = z, room = c.room, I = M.LUX * up * up, r = M.CELL * 1.4 + (z - f), w = 0.0, want = false,
                                    shade = false, shading = false, col = col }
            end
        end
    end
    -- (and the scene's own besides its rooms', game.lua puts in data.extra_lamps - the Bowser hallway's torches: each
    -- of the room at its `room_at`, so lit with it, its own strength, reach and colour)
    local R = package.loaded["rooms"]
    for _, e in ipairs((G and G.data and G.name == name and G.data.extra_lamps) or {}) do
        local room = 0
        if R and R.at and e.room_at then pcall(function() room = R.at(name, e.room_at[1], e.room_at[2], e.room_at[3]) or 0 end) end
        lamps[#lamps + 1] = { x = e.x, y = e.y, z = e.z, room = room, I = e.I or M.LUX * 4.0, r = e.r or 800.0, w = 0.0,
                              want = false, shade = false, shading = false, col = e.col or col }
    end
    return lamps
end

local function spawn_lamp(world, l)
    local cls = StaticFindObject("/Script/Engine.PointLight")
    if not (cls and cls:IsValid()) then return end
    local a = world:SpawnActor(cls, { X = l.x + OFFSET.X, Y = l.y + OFFSET.Y, Z = l.z + OFFSET.Z }, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
    if not (a and a:IsValid()) then return end
    l.a = a
    pcall(function() lib.keep[a:GetAddress()] = true end)       -- (the scene sweep leaves them: M.clear takes them)
    pcall(function()
        local lc = a.LightComponent
        l.lc = lc
        lc:SetMobility(2)
        pcall(function() lc:SetIntensityUnits(1) end)            -- (candelas)
        lc:SetIntensity(0.0)
        lc:SetLightColor(l.col or M.COLOR, true)
        lc:SetAttenuationRadius(l.r)
        pcall(function() lc:SetSourceRadius(M.SOURCE_R) end)
        lc:SetCastShadows(false)
        lc:SetVisibility(false, false)
    end)
end

local function sun_in(on_lamps)
    local env = _G.MENU and _G.MENU.env
    if not env then return end
    local here = nil
    pcall(function() here = lib.world():GetAddress() end)
    if env.world ~= here then return end
    if on_lamps then
        for i, l in ipairs(env.lights or {}) do
            pcall(function()
                local lc = l.LightComponent
                if i == 1 then lc:SetIntensity(0.0); lc:SetCastShadows(false)
                elseif i == 2 then lc:SetIntensity(0.0)
                else lc:SetIntensity(M.AMB_IN) end
            end)
        end
    else
        local G = package.loaded["game"]
        local sun = env.lights and env.lights[1]
        if sun then pcall(function() sun.LightComponent:SetCastShadows(not (G and G.LIT_LEVELS == false)) end) end
        local SKY = package.loaded["sky"]
        if SKY and SKY.relight then pcall(SKY.relight) end
    end
end

function M.clear()
    local s = st
    st = nil
    if not s then return end
    local here = nil
    pcall(function() here = lib.world():GetAddress() end)
    if s.world == here then
        for _, l in ipairs(s.lamps) do
            if valid(l.a) then pcall(function() lib.keep[l.a:GetAddress()] = nil; l.a:K2_DestroyActor() end) end
        end
        sun_in(false)
    end
end
function M.forget() st = nil end

function M.active() return st ~= nil end
function M.lamps() return st and st.lamps or {} end

-- every frame: (x, y, z) his middle, scene centimetres
function M.update(dt, x, y, z)
    local G = package.loaded["game"]
    local world = lib.world()
    if not (G and world) then return end
    local addr = world:GetAddress()
    if st and st.world ~= addr then st = nil end                  -- (the map went, and the lamps with it)
    local want = G.LIT_LEVELS ~= false and M.SCENES[G.name or ""] and not G.warping
    if st and (st.name ~= G.name or not want) then M.clear() end
    if not want then return end
    if not st then
        local lamps = plan(G.name)
        if #lamps == 0 then return end
        st = { world = addr, name = G.name, lamps = lamps, t = 0.0, sun_t = 0.0 }
        for _, l in ipairs(lamps) do spawn_lamp(world, l) end
        log("lamps: %s, %d lamps in its rooms", G.name, #lamps)
    end
    dt = math.min(dt or 0.016, 0.1)
    -- (the sun kept out: the sky's mood puts it back at each change of sky)
    st.sun_t = st.sun_t - dt
    if st.sun_t <= 0.0 then st.sun_t = 0.5; sun_in(true) end
    st.t = st.t - dt
    if st.t <= 0.0 then
        st.t = M.CHOOSE_EVERY
        local R = package.loaded["rooms"]
        local his = R and R.mario or 0
        local order = {}
        for _, l in ipairs(st.lamps) do
            local d = math.sqrt((l.x - x) ^ 2 + (l.y - y) ^ 2 + (l.z - z) ^ 2)
            if d < M.REACH then
                if his ~= 0 and l.room == his then d = d - M.SAME_ROOM end
                order[#order + 1] = { l = l, d = d }
            end
            l.want, l.shade = false, false
        end
        table.sort(order, function(a, b) return a.d < b.d end)
        -- (his room and the nearest lamps' rooms, whole; the nearest of all of them casting shadows)
        local rooms = {}
        if his ~= 0 then rooms[his] = true end
        for i = 1, math.min(M.NEAR, #order) do rooms[order[i].l.room] = true end
        -- (and every room drawn now - his and those through open doors, rooms.lua's mask: walked out of, a room still in
        -- sight went dark - "areas going dark when moving from them", 2026-11-06)
        local si = R and R.split_info
        if si and si.shown and si.scene == st.name then
            for r = 1, 32 do if (si.shown >> (r - 1)) & 1 == 1 then rooms[r] = true end end
        end
        local n = 0
        for _, o in ipairs(order) do
            if rooms[o.l.room] and n < (M.SCENE_LIT[st.name] or M.LIT) then
                n = n + 1
                o.l.want = true
                o.l.shade = n <= (M.SCENE_MAX[st.name] or M.MAX)
            end
        end
    end
    for _, l in ipairs(st.lamps) do
        local target = l.want and 1.0 or 0.0
        if l.lc and (l.w ~= target or l.shade ~= l.shading) then
            local was = l.w
            if l.w < target then l.w = math.min(target, l.w + M.FADE * dt) elseif l.w > target then l.w = math.max(target, l.w - M.FADE * dt) end
            pcall(function()
                local lc = l.lc
                if was == 0.0 and l.w > 0.0 then lc:SetVisibility(true, false) end
                local sh = l.shade and l.w > 0.0
                if sh ~= (l.shading or false) then lc:SetCastShadows(sh); l.shading = sh end
                lc:SetIntensity(l.I * l.w)
                if l.w == 0.0 then lc:SetVisibility(false, false) end
            end)
        end
    end
end

return M
