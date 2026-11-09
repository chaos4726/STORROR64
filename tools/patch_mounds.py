def patch(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)


patch(r'X:/mashup-work/exporter/platx.py', [
("""HANDLED = {'bhvCapSwitch', """, """HANDLED = {'bhvCapSwitch', 'bhvSnowMoundSpawn', """),
("""    if b == 'bhvSLWalkingPenguin':""", """    if b == 'bhvSnowMoundSpawn':
        # Snowman's Land's sliding snow mounds (snow_mound.inc.c): a spawner that sends them over the icy water
        return one('snow_mound', T(mgmap.get('MODEL_SL_SNOW_TRIANGLE'), 'sl_seg7_collision_sliding_snow_mound'))
    if b == 'bhvSLWalkingPenguin':"""),
])

patch(r'X:/mashup-work/platforms.lua', [
("""-- Snowman's Land's big penguin (sl_walking_penguin.inc.c), on the ice bridge""",
 """-- Snowman's Land's sliding snow mounds (snow_mound.inc.c): while he is within 6000 of the spawner and not 1000 above
-- it, one sets off at frames 64, 128, 192, 224 and 256 of each 256: 40 a frame along -x for 118 frames (rideable),
-- then down into the water (5 along, 10 down a frame) for 50 more, and gone. A pool of five, shown and hidden in
-- turn (actors made and destroyed by the dozen crashed the game, see the crash notes). (They were missing,
-- 2026-10-15.)
local MOUND_AT = { [64] = true, [128] = true, [192] = true, [224] = true, [256] = true }
B.snow_mound = {
    spawn = function(world, templates, o)
        local ctl = { mounds = {}, t = 0, x = o.pos[1], y = o.pos[2], z = o.pos[3] }
        for i = 1, 5 do
            local p = make(world, templates, o.tpl, o.pos[1], o.pos[2], o.pos[3], o.ang, o.scale)
            if p then
                p.o, p.def, p.bp, p.ctl, p.slot = o, B.snow_mound, 0, ctl, i
                shown(p, false)
                enlist(p)
                ctl.mounds[#ctl.mounds + 1] = p
            end
        end
    end,
    step = function(p, m)
        local c = p.ctl
        if p == c.mounds[1] then
            c.t = c.t + 1
            local dx, dy, dz = m.x - c.x, m.y - c.y, m.z - c.z
            if dx * dx + dy * dy + dz * dz < 6000.0 * 6000.0 and m.y < c.y + 1000.0 and MOUND_AT[c.t] then
                for _, q in ipairs(c.mounds) do
                    if q.gone then
                        q.x, q.y, q.z, q.action, q.timer, q.jump = q.hx, q.hy, q.hz, 0, 0, true
                        shown(q, true)
                        break
                    end
                end
            end
            if c.t >= 256 then c.t = 0 end
        end
        if p.gone then return end
        if p.action == 0 then
            p.x = p.x - 40.0
            if p.timer > 117 then p.action = 1 end
        else
            p.x, p.y, p.z = p.x - 5.0, p.y - 10.0, p.hz - 2.0
            if p.timer > 50 then shown(p, false) end
        end
    end,
}

-- Snowman's Land's big penguin (sl_walking_penguin.inc.c), on the ice bridge"""),
])
print('ok')
