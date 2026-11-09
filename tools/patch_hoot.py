def patch(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)

patch(r'X:/mashup-work/game_cur.lua', [
('''local CAPS = optional("caps")         -- (Mario 64's wing, metal and vanish caps, out of their ! boxes)''',
 '''local CAPS = optional("caps")         -- (Mario 64's wing, metal and vanish caps, out of their ! boxes)
local HOOT = optional("hoot")         -- (Whomp's Fortress's owl, who carries him about)'''),
('''    if CAMLAK then pcall(CAMLAK.clear) end
    if UNDERWATER then pcall(UNDERWATER.clear) end''', '''    if CAMLAK then pcall(CAMLAK.clear) end
    if HOOT then pcall(HOOT.clear) end
    if UNDERWATER then pcall(UNDERWATER.clear) end'''),
('''            elseif o.kind == "water_shell" then G.add_water_shell(world, o)''',
 '''            elseif o.kind == "water_shell" then G.add_water_shell(world, o)
            elseif o.kind == "hoot" and HOOT then
                HOOT.add(world, o, { actor_data = actor_data, say = function(...) return G.say(...) end,
                                     floor = function(x, y, z) return floor_z(x, y, z) end })'''),
('''        for _, m in ipairs({ BUTTERFLY, MOVTEX, SCENERY, MIRROR, CAMLAK, CAPS, FPV, SWIM, PAUSE, BURN, RAG }) do if m and m.forget then pcall(m.forget) end end''',
 '''        for _, m in ipairs({ BUTTERFLY, MOVTEX, SCENERY, MIRROR, CAMLAK, CAPS, HOOT, FPV, SWIM, PAUSE, BURN, RAG }) do if m and m.forget then pcall(m.forget) end end'''),
('''    if CAPS then guarded("caps", CAPS.update, dt, pawn) end
''', '''    if CAPS then guarded("caps", CAPS.update, dt, pawn) end
    if HOOT then guarded("hoot", HOOT.update, dt, pawn, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0)) end
'''),
('''            if (B and B.active) or (R and R.active) or (BF and BF.cutscene) or G.cutscene or G.swim or G.thaw_at then return end''',
 '''            if (B and B.active) or (R and R.active) or (BF and BF.cutscene) or G.cutscene or G.swim or G.thaw_at or G.carried then return end'''),
('''    if not G.swim then
        if not sz or (G.swim_cool or 0) > 0 then return end''', '''    if not G.swim then
        if not sz or (G.swim_cool or 0) > 0 then return end
        if G.carried then return end                           -- (Hoot has him)'''),
])
print('ok')
