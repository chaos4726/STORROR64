p = r'X:/mashup-work/exporter/platx.py'
s = open(p, encoding='utf-8').read()


def rep(a, b):
    global s
    assert s.count(a) == 1, (s.count(a), a[:80])
    s = s.replace(a, b)


rep('''BF_COL = [''', '''# the barred doors an openable grill puts either side of itself: half its width, model, collision
# (grill_door.inc.c gOpenableGrills: OPENABLE_GRILL_BP_BOB 0, OPENABLE_GRILL_BP_HMC 1)
GRILLS = [(320, 'MODEL_BOB_BARS_GRILLS', 'bob_seg7_collision_gate'),
          (410, 'MODEL_HMC_RED_GRILLS', 'hmc_seg7_collision_0702B65C')]
BF_COL = [''')
rep('''HANDLED = {'bhvCapSwitch', ''', '''HANDLED = {'bhvCapSwitch', 'bhvOpenableGrill', 'bhvFloorSwitchGrills', ''')
rep('''    if b == 'bhvCastleFloorTrap':''', '''    if b == 'bhvOpenableGrill':
        # grill_door.inc.c: two barred doors half its width either side, the first turned round, which the purple
        # switch beside it (bhvFloorSwitchGrills) swings open, 0x100 a frame for 64 frames, opposite ways
        half, model, col = GRILLS[b2 if b2 < len(GRILLS) else 0]
        tpl = T(mgmap.get(model), col)
        if not tpl:
            return []
        ya = math.radians(o['ay'])
        out = []
        for rel, turn, sign in ((half, 180, 1), (-half, 0, -1)):
            dx, dz = rel * math.cos(ya), -rel * math.sin(ya)
            out.append(dict(base, bhv='grill_door', tpl=tpl, pos=[o['x'] + dx, o['y'], o['z'] + dz],
                            ang=[o['ax'], o['ay'] + turn, o['az']], turn=sign, jingle=(b2 == 1)))
        return out
    if b == 'bhvFloorSwitchGrills':
        # the purple switch that opens them: stays down once pressed
        return one('purple_switch', T(geo, 'purple_switch_seg8_collision_0800C7A8'), scale=[1.5, 1.5, 1.5], stays=True)
    if b == 'bhvCastleFloorTrap':''')
open(p, 'w', encoding='utf-8', newline='\n').write(s)

p = r'X:/mashup-work/platforms.lua'
s = open(p, encoding='utf-8').read()
rep('''B.hidden = {''', '''-- bhvOpenableGrill (grill_door.inc.c): Bob-omb Battlefield's bars and Hazy Maze Cave's red grills, two doors that the
-- purple switch beside them swings open for good (0x100 a frame for 64 frames, the two opposite ways), with the cage's
-- sound, and in the cave the puzzle jingle. (Mario 64 spawns them at the start: they were missing, the way open and no
-- switch, 2026-10-15.)
B.grill_door = {
    step = function(p, m)
        if p.switch == nil then
            local best, bd = false, nil
            for _, q in ipairs(P.list) do
                if q.def == B.purple_switch and q.o.stays then
                    local d = (q.x - p.x) ^ 2 + (q.y - p.y) ^ 2 + (q.z - p.z) ^ 2
                    if not bd or d < bd then best, bd = q, d end
                end
            end
            p.switch = best
        end
        if p.action == 0 then
            if p.switch and p.switch.action == 2 then
                p.action = 1
                if (p.o.turn or 1) > 0 then
                    p.shot = "cage_open"
                    if p.o.jingle then play("puzzle_jingle") end
                end
            end
        elseif p.action == 1 then
            if p.timer < 64 then p.yaw = s16(p.yaw + (p.o.turn or 1) * 0x100) else p.action = 2 end
        end
    end,
}

B.hidden = {''')
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('ok')
