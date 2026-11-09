p = r'X:/mashup-work/exporter/platx.py'
s = open(p, encoding='utf-8').read()


def rep(a, b):
    global s
    assert s.count(a) == 1, (s.count(a), a[:80])
    s = s.replace(a, b)


rep('''STAIRS = [('bits_seg7_collision_0701B0D4', 'MODEL_BITS_STAIRCASE'),
          ('bitdw_seg7_collision_0700F91C', 'MODEL_BITDW_STAIRCASE_FRAME4'),
          ('rr_seg7_collision_07029924', 'MODEL_RR_TRICKY_TRIANGLES')]''',
    '''STAIRS = [('bits_seg7_collision_0701B0D4', 'MODEL_BITS_STAIRCASE'),
          ('bitdw_seg7_collision_0700F91C', 'MODEL_BITDW_STAIRCASE_FRAME4'),
          ('rr_seg7_collision_07029924', 'MODEL_RR_TRICKY_TRIANGLES')]
# ... and as they stand before it (animated_floor_switch.inc.c D_80331A54, frame 0 of each)
STAIRS_IN = [('bits_seg7_collision_0701B734', 'MODEL_BITS_STAIRCASE_FRAME4'),
             ('bitdw_seg7_collision_0700FD9C', 'MODEL_BITDW_STAIRCASE'),
             ('rr_seg7_collision_0702A6B4', 'MODEL_RR_TRICKY_TRIANGLES_FRAME4')]''')
rep('''HANDLED = {'bhvCapSwitch', ''', '''HANDLED = {'bhvCapSwitch', 'bhvFloorSwitchAnimatesObject', ''')
rep('''    if b == 'bhvAnimatesOnFloorSwitchPress':
        col, model = STAIRS[b2 if b2 < len(STAIRS) else 0]
        return one('static', T(mgmap.get(model) or geo, col))''',
    '''    if b == 'bhvAnimatesOnFloorSwitchPress':
        # animated_floor_switch.inc.c: drawn folded away until the purple switch beside it is pressed, then out for good
        # (platforms.lua B.switch_stairs: both ends of its animation, one shown at a time)
        i = b2 if b2 < len(STAIRS) else 0
        col, model = STAIRS[i]
        col_in, model_in = STAIRS_IN[i]
        return (one('switch_stairs', T(mgmap.get(model) or geo, col), out=True) +
                one('switch_stairs', T(mgmap.get(model_in) or geo, col_in), out=False))
    if b == 'bhvFloorSwitchAnimatesObject':
        # the purple switch that brings those stairs out: once pressed it stays down (its second parameter byte 0)
        return one('purple_switch', T(geo, 'purple_switch_seg8_collision_0800C7A8'), scale=[1.5, 1.5, 1.5], stays=True)''')
open(p, 'w', encoding='utf-8', newline='\n').write(s)

p = r'X:/mashup-work/platforms.lua'
s = open(p, encoding='utf-8').read()
rep('''-- bhvFloorSwitchHiddenObjects (purple_switch.inc.c): stepped on, it squashes flat (its height 1.5 -> 0.2 over 3
-- frames) with a click, ticks for 400 frames, then waits for the athlete to step off and pops back up''',
    '''-- bhvFloorSwitchHiddenObjects (purple_switch.inc.c): stepped on, it squashes flat (its height 1.5 -> 0.2 over 3
-- frames) with a click, ticks for 400 frames, then waits for the athlete to step off and pops back up. The one that
-- brings stairs out (bhvFloorSwitchAnimatesObject, `stays`) stays down once pressed, without ticking.''')
rep('''            if p.timer == 3 then
                p.action, p.shot = 2, "purple_switch"
                local SFX = package.loaded["sfx"]
                if SFX then pcall(SFX.play, "purple_ticks", 1.0) end
            end
        elseif a == 2 then
            if p.timer > 400 then p.action = 4 end''', '''            if p.timer == 3 then
                p.action, p.shot = 2, "purple_switch"
                local SFX = package.loaded["sfx"]
                if SFX and not p.o.stays then pcall(SFX.play, "purple_ticks", 1.0) end
                local G = package.loaded["game"]
                if G and G.shake_stage then pcall(G.shake_stage, 0.2) end       -- (cur_obj_shake_screen SHAKE_POS_SMALL)
            end
        elseif a == 2 then
            if p.timer > 400 and not p.o.stays then p.action = 4 end''')
rep('''B.hidden = {''', '''-- bhvAnimatesOnFloorSwitchPress (animated_floor_switch.inc.c): the Dark World's and the Sky's staircases and Rainbow
-- Ride's tricky triangles, folded away until the nearest purple switch is pressed, then out for good (Mario 64 runs
-- them out over 9 frames, through its five models; here the two ends: `out` the one shown once pressed). They were
-- always out, and the switch was missing, 2026-10-15.
B.switch_stairs = {
    init = function(p) p.up = false end,
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
            shown(p, not p.o.out)
        end
        if not p.up and p.switch and p.switch.action == 2 then
            p.up = true
            shown(p, p.o.out and true or false)
            if p.o.out then p.shot = "platform_switch" end
        end
    end,
}

B.hidden = {''')
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('ok')
