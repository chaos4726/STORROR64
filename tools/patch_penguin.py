def patch(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)


patch(r'X:/mashup-work/exporter/platx.py', [
("""HANDLED = {'bhvCapSwitch', """, """HANDLED = {'bhvCapSwitch', 'bhvSLWalkingPenguin', """),
("""    if b == 'bhvJRBSlidingBox':""", """    if b == 'bhvSLWalkingPenguin':
        # Snowman's Land's big penguin (sl_walking_penguin.inc.c), six times a penguin's size, walking the ice
        # bridge: his collision here (to stand on), his animated model drawn by the platform (B.walk_penguin)
        return one('walk_penguin', T('none', bhv_collision.get(b)), scale=[6.0, 6.0, 6.0])
    if b == 'bhvJRBSlidingBox':"""),
])

patch(r'X:/mashup-work/platforms.lua', [
# --- the draw hook
("""local function render(p, a)
    local x, y, z = p.px + (p.x - p.px) * a, p.py + (p.y - p.py) * a, p.pz + (p.z - p.pz) * a
    local pitch = p.ppitch + s16(p.pitch - p.ppitch) * a
    local yaw = p.pyaw + s16(p.yaw - p.pyaw) * a
    local roll = p.proll + s16(p.roll - p.proll) * a""",
 """local function render(p, a)
    local x, y, z = p.px + (p.x - p.px) * a, p.py + (p.y - p.py) * a, p.pz + (p.z - p.pz) * a
    local pitch = p.ppitch + s16(p.pitch - p.ppitch) * a
    local yaw = p.pyaw + s16(p.yaw - p.pyaw) * a
    local roll = p.proll + s16(p.roll - p.proll) * a
    if p.def.draw then pcall(p.def.draw, p, x, y, z, yaw) end      -- (a model of its own drawn with it, animated)"""),
# --- the penguin
("""-- RR's flying ship's wings (cruiser.inc.c): flapping, and the boat's creak every 64 frames""",
 """-- Snowman's Land's big penguin (sl_walking_penguin.inc.c), on the ice bridge: forwards by a set of steps - walk 2 s,
-- stop 1 s, hurry 1 s, stop, back up 1 s, stop - until x < 300, a half turn (0x400 a frame for 32 frames), back at
-- a steady 12 until x > 1700, a half turn, and again. Six times a penguin's size, solid (he can be stood on), and
-- he shields whoever walks behind him from the snowman's breath (enemies.lua step_wind). (He stood still as a
-- statue, 2026-10-15.)
local PENGUIN_STEPS = { { 60, 1, 6.0, 1.0 }, { 30, 4, 0.0, 1.0 }, { 30, 1, 12.0, 2.0 }, { 30, 4, 0.0, 1.0 },
                        { 30, 1, -6.0, 1.0 }, { 30, 4, 0.0, 1.0 } }        -- (frames, animation 1 walk 4 idle, speed, rate)
B.walk_penguin = {
    init = function(p) p.cur, p.ct, p.af, p.anim, p.quads = 1, 0, 0.0, 1, {} end,
    step = function(p)
        local v, anim, rate = 0.0, 1, 1.0
        if p.action == 0 then
            if p.timer == 0 then p.cur, p.ct = 1, 0 end
            if p.ct < PENGUIN_STEPS[p.cur][1] then p.ct = p.ct + 1
            else p.ct, p.cur = 0, p.cur % #PENGUIN_STEPS + 1 end
            local s = PENGUIN_STEPS[p.cur]
            if p.x < 300.0 then p.action = 1
            else v, anim, rate = s[3], s[2], s[4] end
        elseif p.action == 1 or p.action == 3 then
            p.yaw = s16(p.yaw + 0x400)
            if p.timer == 31 then p.action = (p.action + 1) % 4 end
        else
            v, rate = 12.0, 2.0
            if p.x > 1700.0 then p.action = 3 end
        end
        p.x, p.z = p.x + sins(p.yaw) * v, p.z + coss(p.yaw) * v
        local fy = ground_under(p.x, p.y + 100.0, p.z)
        if fy and abs(fy - p.y) < 200.0 then p.y = fy end
        if anim ~= p.anim then p.anim, p.af = anim, 0.0 end
        p.af = p.af + rate
    end,
    draw = function(p, x, y, z, yaw)
        if p.vis == nil then
            p.vis = false
            local data = not P.dry and lib.load_data("data.actor_geo_penguin_geo")
            if data then
                local inst = lib.make_instance(lib.world(), data, { X = -z * S + OFFSET.X, Y = x * S + OFFSET.Y, Z = y * S + OFFSET.Z }, 0.0, 6.0)
                if inst then
                    inst.moves = true
                    p.vis = inst
                    p.quads[#p.quads + 1] = inst.actor         -- (taken away with the platform)
                end
            end
        end
        local v = p.vis
        if not v then return end
        lib.set_pose(v, -z * S + OFFSET.X, x * S + OFFSET.Y, y * S + OFFSET.Z, -yaw * 360.0 / 65536.0)
        local anim = v.data.anims and v.data.anims[p.anim or 1]
        if anim then lib.pose(v, anim, p.af or 0.0) end
    end,
}

-- RR's flying ship's wings (cruiser.inc.c): flapping, and the boat's creak every 64 frames"""),
])

patch(r'X:/mashup-work/enemies.lua', [
("""-- SL's snowman's breath across the ice bridge
local function step_wind(e, m)""",
 """-- (strong_wind_particle.inc.c: the breath's puffs die within 300 of the big penguin's middle - a point 60 behind
-- and 100 aside of him - so whoever has him between themselves and the snowman is not blown)
local function penguin_shields(e, m)
    local PL = package.loaded["platforms"]
    if not (PL and PL.list) then return false end
    for _, p in ipairs(PL.list) do
        if p.o and p.o.bhv == "walk_penguin" then
            local wx = p.x + sins(0xDBB0) * 60.0 + 100.0 * sins(0x1BB0)
            local wz = p.z + coss(0xDBB0) * 60.0 + 100.0 * coss(0x1BB0)
            local ax, az = m.x - e.x, m.z - e.z
            local len = sqrt(ax * ax + az * az)
            if len > 1.0 then
                local ux, uz = ax / len, az / len
                local qx, qz = wx - e.x, wz - e.z
                local along = qx * ux + qz * uz
                if along > 0.0 and along < len and abs(qx * uz - qz * ux) < 300.0 then return true end
            end
        end
    end
    return false
end

-- SL's snowman's breath across the ice bridge
local function step_wind(e, m)"""),
("""    if m.dist < 1500.0 and abs(m.y - e.y) < 500.0 and abs(off) < 0x1500 then
        push_athlete(away, 9.0)""",
 """    if m.dist < 1500.0 and abs(m.y - e.y) < 500.0 and abs(off) < 0x1500 and not penguin_shields(e, m) then
        push_athlete(away, 9.0)"""),
])
print('ok')
