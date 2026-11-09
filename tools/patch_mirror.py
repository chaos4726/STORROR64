def patch(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)


patch(r'X:/mashup-work/game_cur.lua', [
('''local SCENERY = optional("scenery")
''', '''local SCENERY = optional("scenery")
local MIRROR = optional("mirror")    -- (the castle's mirror room: his reflection, and Lakitu filming)
'''),
('''    if SCENERY then pcall(SCENERY.clear) end
    if UNDERWATER then pcall(UNDERWATER.clear) end''', '''    if SCENERY then pcall(SCENERY.clear) end
    if MIRROR then pcall(MIRROR.clear) end
    if UNDERWATER then pcall(UNDERWATER.clear) end'''),
('''    if SCENERY and name == "grounds" then        -- the castle grounds' flags, birds, fish, mist and hidden 1-ups''',
 '''    if MIRROR then
        local okm, errm = pcall(MIRROR.load, world, name, actor_data)
        if not okm then log("mirror failed: %s", tostring(errm)) end
    end
    if SCENERY and name == "grounds" then        -- the castle grounds' flags, birds, fish, mist and hidden 1-ups'''),
('''    if SCENERY then guarded("scenery", SCENERY.update, dt, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0)) end''',
 '''    if SCENERY then guarded("scenery", SCENERY.update, dt, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0)) end
    if MIRROR then guarded("mirror", MIRROR.update, dt, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0)) end'''),
('''        for _, m in ipairs({ BUTTERFLY, MOVTEX, SCENERY, FPV, SWIM, PAUSE, BURN, RAG }) do if m and m.forget then pcall(m.forget) end end''',
 '''        for _, m in ipairs({ BUTTERFLY, MOVTEX, SCENERY, MIRROR, FPV, SWIM, PAUSE, BURN, RAG }) do if m and m.forget then pcall(m.forget) end end'''),
])
print('ok')
