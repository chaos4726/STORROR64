p = r'X:\mashup-work\enemies.lua'
s = open(p, encoding='utf-8').read()
def rep(a, b):
    global s
    assert s.count(a) == 1, (a[:80], s.count(a))
    s = s.replace(a, b, 1)
rep('''    if o.type == "bhvKlepto" and ((o.bp or 0) >> 16) & 0xFF == 0 then e.cap_klepto = true end''',
'''    if o.type == "bhvKlepto" and ((o.bp or 0) >> 16) & 0xFF == 0 then e.cap_klepto = true end
    -- (Tall Tall Mountain's other Ukiki, UKIKI_BP_CAP: grabbed, he takes Mario's cap - mariocap.lua)
    if o.type == "bhvUkiki" and ((o.bp or 0) >> 16) & 0xFF == 1 then e.cap_ukiki = true end''')
rep('''    if e.type == "bhvKlepto" and e.cap_klepto then
        if e.kc and e.kc.act == "hold" then''', '''    -- The cap Ukiki (ukiki.inc.c cap_ukiki_held_loop): grabbed - a punch at him, as the athlete takes hold of things - he
    -- snatches Mario's cap (DIALOG_100) and runs from him with it on his head; grabbed again, he gives it back
    -- (DIALOG_101, mario_retrieve_cap).
    if e.cap_ukiki then
        local MC = package.loaded["mariocap"]
        local has = MC and MC.held_by and MC.held_by("ukiki")
        if has and not e.t.flee then e.t = setmetatable({ flee = true }, { __index = T.bhvUkiki })
        elseif not has and e.t.flee then e.t, e.fleeing = T.bhvUkiki, nil end
        cap_shown_on(e, world, has, e.x, e.y + 95.0, e.z, -(e.yaw or 0) * 360.0 / 65536.0)
        e.cap_cool = math.max(0, (e.cap_cool or 0) - 1)
        local dx, dz = m.x - e.x, m.z - e.z
        if MC and e.cap_cool == 0 and new_attack and attack and not attack.air and dx * dx + dz * dz < 240.0 * 240.0
            and abs(m.y - e.y) < 250.0 then
            e.cap_cool = 60
            if has then
                say(101, nil, e)
                MC.retrieve()
                log("Ukiki gave Mario's cap back")
            elseif MC.lose_to and MC.lose_to("ukiki") then
                sound("en_ukiki", 1.0)
                say(100, nil, e)
                log("Ukiki took Mario's cap")
            end
        end
        return
    end
    if e.type == "bhvKlepto" and e.cap_klepto then
        if e.kc and e.kc.act == "hold" then''')
open(p, 'w', encoding='utf-8').write(s)
print('ok')
