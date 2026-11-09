import re


def patch(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)


patch(r'X:/mashup-work/exporter/build_all.py', [
('''            elif b == 'bhvFishSpawner':''', '''            elif b == 'bhvTankFishGroup':
                # the castle aquarium's fish (blue_fish.inc.c bhv_tank_fish_group_loop): fifteen spawned (0x300, 0, -200)
                # from the group in its own frame, each moved up to 200 about it
                ya = math.radians(o['ay'])
                rx, rz = 300.0, -200.0
                cx, cz = o['x'] + rx * math.cos(ya) + rz * math.sin(ya), o['z'] - rx * math.sin(ya) + rz * math.cos(ya)
                objects.append({'kind': 'tank_fish', 'pos': ue(cx, o['y'], cz), 'count': 15})
            elif b == 'bhvFishSpawner':'''),
])

patch(r'X:/mashup-work/game_cur.lua', [
('''    local schools = {}
    for _, o in ipairs(data.objects or {}) do
        if o.kind == "fish_school" and (not o.acts or not G.act or ((o.acts >> (G.act - 1)) & 1) == 1) then
            schools[#schools + 1] = { pos = o.pos, count = o.count }
        end
    end
    if SCENERY and name ~= "grounds" and #schools > 0 then     -- (fish.inc.c's schools: the lake fish's code)
        local oks, errs = pcall(SCENERY.load, world, { fish_schools = schools }, { floor_z = floor_z, water_at = water_at })''',
 '''    local schools, tanks = {}, {}
    for _, o in ipairs(data.objects or {}) do
        if o.kind == "fish_school" and (not o.acts or not G.act or ((o.acts >> (G.act - 1)) & 1) == 1) then
            schools[#schools + 1] = { pos = o.pos, count = o.count }
        elseif o.kind == "tank_fish" then
            tanks[#tanks + 1] = { pos = o.pos, count = o.count }
        end
    end
    if SCENERY and name ~= "grounds" and #schools + #tanks > 0 then     -- (fish.inc.c's schools: the lake fish's code)
        local oks, errs = pcall(SCENERY.load, world, { fish_schools = schools, tanks = tanks }, { floor_z = floor_z, water_at = water_at })'''),
])

patch(r'X:/mashup-work/scenery.lua', [
('''    st = { world = world, all = {}, flags = {}, flocks = {}, birds = {}, schools = {}, fish = {}, mist = {}, t = 0.0 }''',
 '''    st = { world = world, all = {}, flags = {}, flocks = {}, birds = {}, schools = {}, fish = {}, mist = {}, t = 0.0,
           tanks = {}, tank_fish = {} }'''),
('''    for _, m in ipairs(life.mist or {}) do''', '''    for _, t in ipairs(life.tanks or {}) do
        st.tanks[#st.tanks + 1] = { x = t.pos[1], y = t.pos[2], z = t.pos[3], count = t.count or 15 }
    end
    for _, m in ipairs(life.mist or {}) do'''),
('''-- ------------------------------------------------------------ every tick''', '''-- ------------------------------------------------------------ the castle aquarium's fish
-- (blue_fish.inc.c bhv_blue_fish_movement_loop: forward 3-5 a frame, diving or climbing a little for 60-90 frames,
-- then turning 0x800 a frame for 15 frames - nearly about - and the other way up again: back and forth in the tank.
-- They swim in the castle's aquarium, which has no water box: no water is asked of them.)
local function tank_out(t)
    for i = 1, t.count do
        local inst = make(st.world, "blue_fish", t.x, t.y, t.z, 0.0)
        if inst then
            st.tank_fish[#st.tank_fish + 1] = { inst = inst, home = t,
                x = t.x + (random() * 2.0 - 1.0) * 200.0 * U, y = t.y + (random() * 2.0 - 1.0) * 200.0 * U,
                z = t.z + (random() * 2.0 - 1.0) * 200.0 * U, heading = random() * 2.0 * pi, pitch = 0.0,
                phase = 0, t = 0, f = random() * 30.0 }
        end
    end
end

local function update_tank_fish(dt, k)
    local data = actor("blue_fish")
    for _, f in ipairs(st.tank_fish) do
        f.t = f.t + k
        if f.phase == 0 or f.phase == 2 then
            if f.t < k + 0.01 and f.phase == 0 then
                f.turn = (random() < 0.5 and -1.0 or 1.0) * 0x800
                f.vel = random() * 2.0 + 3.0
                f.len = math.floor(random() * 30.0 / 2.0) * 2.0 + 60.0
                f.pv = (random() * 5.0 < 2.0) and ((random() * 2.0 - 1.0) * 128.0) or 0.0
            end
            local dir = (f.phase == 0) and 1.0 or -1.0
            f.pitch = f.pitch + dir * ((f.t < f.len / 2.0) and f.pv or -f.pv) * k
            if f.t >= f.len then f.phase, f.t = f.phase + 1, 0 end
        else
            f.heading = f.heading + rad((f.turn or 0x800) * A) * k
            if f.t >= 15 then f.phase, f.t = (f.phase + 1) % 4, 0 end
        end
        local v = (f.vel or 3.0) * U * FPS * dt
        local p = rad(f.pitch * A)
        -- (and never further than 400 from where the group spawned them: a fish that drifts is turned back)
        local h = f.home
        if (f.x - h.x) ^ 2 + (f.y - h.y) ^ 2 > (400.0 * U) ^ 2 then f.heading = atan(h.y - f.y, h.x - f.x) end
        f.x, f.y = f.x + cos(f.heading) * cos(p) * v, f.y + sin(f.heading) * cos(p) * v
        f.z = max(h.z - 200.0 * U, min(h.z + 200.0 * U, f.z - sin(p) * v))
        lib.set_pose(f.inst, f.x + OFFSET.X, f.y + OFFSET.Y, f.z + OFFSET.Z, deg(f.heading) + 180.0)
        f.f = f.f + k * ((f.phase % 2 == 1) and 2.0 or 1.0)
        if data and data.anims[1] then lib.pose(f.inst, data.anims[1], f.f) end
    end
end

-- ------------------------------------------------------------ every tick'''),
('''    if #st.fish > 0 then update_fish(dt, k, px, py, pz) end''', '''    if #st.fish > 0 then update_fish(dt, k, px, py, pz) end
    for _, t in ipairs(st.tanks) do
        if not t.out and (px - t.x) ^ 2 + (py - t.y) ^ 2 + (pz - t.z) ^ 2 < (2500.0 * U) ^ 2 then
            t.out = true
            tank_out(t)
        end
    end
    if #st.tank_fish > 0 then update_tank_fish(dt, k) end'''),
])
print('ok')
