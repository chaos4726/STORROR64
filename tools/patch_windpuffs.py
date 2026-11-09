def patch(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)


patch(r'X:/mashup-work/enemies.lua', [
('''        for _, p in ipairs(e.cloud or {}) do lib.destroy(p.actor) end''',
 '''        for _, p in ipairs(e.cloud or {}) do lib.destroy(p.actor) end
        for _, w in ipairs(e.wpool or {}) do lib.destroy(w.inst.actor) end'''),
('''-- (strong_wind_particle.inc.c: the breath's puffs die within 300 of the big penguin's middle''',
 '''-- The wind seen (strong_wind_particle.inc.c, spawned by cur_obj_spawn_strong_wind_particles): every other frame a
-- mist puff three times its size out of the blower (within 50 of it), at 100 a frame along its aim, spread up to
-- 6000 either way, for 15 frames, 100/255 opaque. A pool of eight per blower, shown and hidden in turn. (The
-- snowman's breath and Fwoosh's blew unseen, 2026-10-15.)
local function wind_puffs(e, yaw, ox, oy, oz)
    if e.wpool == nil then
        e.wpool = {}
        local mist = H.actor_data and H.actor_data("mist")
        local world = lib.world()
        if mist and world then
            for i = 1, 8 do
                local p = lib.make_instance(world, mist, { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z }, 0.0, 3.0)
                if p then
                    p.moves = true
                    pcall(lib.see_through, world, p, 100.0 / 255.0)
                    pcall(function() p.actor:SetActorHiddenInGame(true) end)
                    e.wpool[#e.wpool + 1] = { inst = p, life = 0 }
                end
            end
        end
    end
    e.wind_t = (e.wind_t or 0) + 1
    if e.wind_t % 2 ~= 0 then return end
    for _, w in ipairs(e.wpool) do
        if w.life <= 0 then
            local a = yaw + (math.random() * 2.0 - 1.0) * 6000.0
            w.life = 15
            w.x = (ox or e.x) + (math.random() - 0.5) * 100.0
            w.y = (oy or e.y) + (math.random() - 0.5) * 100.0
            w.z = (oz or e.z) + (math.random() - 0.5) * 100.0
            w.vx, w.vz = sins(a) * 100.0, coss(a) * 100.0
            w.shown = false
            break
        end
    end
end

local function move_wind_puffs(e)
    for _, w in ipairs(e.wpool or {}) do
        if w.life > 0 then
            w.life = w.life - 1
            w.x, w.z = w.x + w.vx, w.z + w.vz
        end
    end
end

-- (billboards: each puff's face, its -x side, turned to the camera)
local function render_wind_puffs(e, cx, cy, cz)
    for _, w in ipairs(e.wpool) do
        if w.life > 0 then
            local sx, sy, sz = to_scene(w.x, w.y, w.z)
            sx, sy, sz = sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z
            local dx, dy, dz = cx - sx, cy - sy, cz - sz
            pcall(function()
                w.inst.actor:K2_TeleportTo({ X = sx, Y = sy, Z = sz },
                    { Pitch = -math.deg(atan(dz, sqrt(dx * dx + dy * dy))), Yaw = math.deg(atan(dy, dx)) + 180.0, Roll = 0.0 })
                if not w.shown then w.shown = true; w.inst.actor:SetActorHiddenInGame(false) end
            end)
        elseif w.shown then
            w.shown = false
            pcall(function() w.inst.actor:SetActorHiddenInGame(true) end)
        end
    end
end

-- (strong_wind_particle.inc.c: the breath's puffs die within 300 of the big penguin's middle'''),
# the snowman's breath
('''local function step_wind(e, m)
    if not e.spoke then''', '''local function step_wind(e, m)
    move_wind_puffs(e)
    if not e.spoke then'''),
('''    local away = s16(m.angle)
    local off = s16(away - e.yaw)
    if m.dist < 1500.0 and abs(m.y - e.y) < 500.0 and abs(off) < 0x1500 and not penguin_shields(e, m) then''',
 '''    local away = s16(m.angle)
    local off = s16(away - e.yaw)
    if m.dist < 1500.0 and abs(m.y - e.y) < 500.0 then
        -- (bhv_sl_snowman_wind_loop: aimed at him, but no more than 0x1500 off its own way)
        wind_puffs(e, e.yaw + math.max(-0x1500, math.min(0x1500, off)))
    end
    if m.dist < 1500.0 and abs(m.y - e.y) < 500.0 and abs(off) < 0x1500 and not penguin_shields(e, m) then'''),
# Fwoosh
('''local function step_fwoosh(e, m)
    e.at = (e.at or 0) + 1''', '''local function step_fwoosh(e, m)
    move_wind_puffs(e)
    e.at = (e.at or 0) + 1'''),
('''        elseif e.grow < -0.1 then
            -- the puff: blown back, hard
            if m.dist < 1500.0 then push_athlete(m.angle, 30.0) end''',
 '''        elseif e.grow < -0.1 then
            -- the puff: blown back, hard (and seen: out of his mouth, 120 in front of him and 50 down, as he is scaled)
            if m.dist < 1500.0 then push_athlete(m.angle, 30.0) end
            local k = e.sk or 3.0
            wind_puffs(e, e.yaw, e.x + sins(e.yaw) * 120.0 * k, e.y - 50.0 * k, e.z + coss(e.yaw) * 120.0 * k)'''),
# drawing
('''    for _, e in ipairs(M.list) do
        if e.cloud and (e.action == "gone" or e.broken) then cloud_gone(e) end
    end''', '''    for _, e in ipairs(M.list) do
        if e.cloud and (e.action == "gone" or e.broken) then cloud_gone(e) end
        if e.wpool then pcall(render_wind_puffs, e, cx, cy, cz) end
    end'''),
])
print('ok')
