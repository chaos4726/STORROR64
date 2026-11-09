def patch(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)


patch(r'X:/mashup-work/exporter/platx.py', [
("""HANDLED = {'bhvCapSwitch', """, """HANDLED = {'bhvCapSwitch', 'bhvJRBSlidingBox', """),
("""    if b == 'bhvInSunkenShip3':""", """    if b == 'bhvJRBSlidingBox':
        # the box on the risen ship's deck, sliding up and down it as the ship rocks (jrb_ship.inc.c)
        return one('slide_box', T(geo, bhv_collision.get(b)))
    if b == 'bhvInSunkenShip3':"""),
])

patch(r'X:/mashup-work/platforms.lua', [
("""-- RR's flying ship's wings (cruiser.inc.c): flapping, and the boat's creak every 64 frames""",
 """-- JRB's sliding box (jrb_ship.inc.c bhv_jrb_sliding_box_loop): on the risen ship's deck, carried round by its rocking
-- and sliding along it at 20 * sin of a phase that turns 0x100 a frame - in step with the rock, so always downhill,
-- some 800 each way - and it hurts what it runs into (sSkullSlidingBoxHitbox: 130 round, 100 high, one wedge). (It
-- stood still on the deck, 2026-10-15.)
B.slide_box = {
    step = function(p, m)
        if p.ship == nil then
            local best, bd = false, nil
            for _, q in ipairs(P.list) do
                if q.def == B.ship_rock and q.tpl.collision then
                    local d = (q.x - p.hx) ^ 2 + (q.z - p.hz) ^ 2
                    if not bd or d < bd then best, bd = q, d end
                end
            end
            p.ship = best
            if best then p.rx, p.ry, p.rz, p.ph = p.hx - best.x, p.hy - best.y, p.hz - best.z, 0 end
        end
        local s = p.ship
        if not s then return end
        local a = s.pitch or 0
        local sa, ca = sins(a), coss(a)
        p.x = s.x + p.rx
        p.y = s.y + ca * p.ry - sa * p.rz
        p.z = s.z + sa * p.ry + ca * p.rz
        p.pitch = a
        p.rz = p.rz + sins(p.ph) * 20.0
        p.ph = (p.ph + 0x100) % 0x10000
        local dx, dz = m.x - p.x, m.z - p.z
        if dx * dx + dz * dz < 170.0 * 170.0 and m.y > p.y - 60.0 and m.y < p.y + 100.0 then
            local HP = _G.HEALTH
            if HP and HP.grace <= 0 and not HP.dead_t then HP.damage(1, "the sliding box") end
        end
    end,
}

-- RR's flying ship's wings (cruiser.inc.c): flapping, and the boat's creak every 64 frames"""),
])
print('ok')
