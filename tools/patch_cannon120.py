def patch(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)

patch(r'X:/mashup-work/exporter/platx.py', [
("""HANDLED = {'bhvCapSwitch',""", """HANDLED = {'bhvHiddenAt120Stars', 'bhvCannon', 'bhvCapSwitch',"""),
("""                   'bhvCannonClosed', 'bhvMontyMoleHole',""", """                   'bhvCannonClosed', 'bhvCannon', 'bhvMontyMoleHole',"""),
("""    if b == 'bhvCannonClosed':
        # the lid over a cannon's hole: a Bob-omb Buddy opens it (platforms.lua B.cannon)
        return one('cannon', T(geo, bhv_collision.get(b)))""",
 """    if b == 'bhvCannonClosed':
        # the lid over a cannon's hole: a Bob-omb Buddy opens it (platforms.lua B.cannon)
        return one('cannon', T(geo, bhv_collision.get(b)))
    if b == 'bhvCannon':
        # a cannon with no lid (macro_cannon_open: the castle grounds' one, by the moat): open from the start - the lid
        # model only stands in for it and is never shown (B.cannon, o.open). Under the grill until 120 stars.
        return one('cannon', T(mgmap.get('MODEL_DL_CANNON_LID') or dl_model(level, 'MODEL_DL_CANNON_LID'),
                               bhv_collision.get('bhvCannonClosed')), open=True)
    if b == 'bhvHiddenAt120Stars':
        # castle_cannon_grate.inc.c: the grill over the castle grounds' cannon, gone once the file has 120 stars
        # (B.hidden_120). It was baked into the grounds for good.
        return one('hidden_120', T(geo, bhv_collision.get(b)))"""),
])

patch(r'X:/mashup-work/platforms.lua', [
("""B.cannon = {
    init = function(p) P.want_kick = true; p.open = false end,""",
 """B.cannon = {
    init = function(p)
        P.want_kick = true
        p.open = p.o.open and true or false
        if p.open then shown(p, false) end           -- (macro_cannon_open: no lid - its stand-in never shown)
    end,"""),
("""-- the level's cannons open (a Bob-omb Buddy's doing); false if there were none shut""",
 """-- castle_cannon_grate.inc.c: the grill over the castle grounds' cannon, gone once the file has 120 stars
B.hidden_120 = {
    init = function(p)
        local MN = _G.MENU
        local n = (MN and MN.star_count and MN.star_count()) or 0
        if n >= 120 then shown(p, false); log("the cannon grill is gone (120 stars)") end
    end,
}

-- the level's cannons open (a Bob-omb Buddy's doing); false if there were none shut"""),
])
print('ok')
