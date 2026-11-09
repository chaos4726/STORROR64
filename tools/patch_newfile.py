def patch(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)


patch(r'X:/mashup-work/game_cur.lua', [
('''local MIRROR = optional("mirror")    -- (the castle's mirror room: his reflection, and Lakitu filming)
''', '''local MIRROR = optional("mirror")    -- (the castle's mirror room: his reflection, and Lakitu filming)
local CAMLAK = optional("camlakitu")  -- (a new file's first look at the castle: the Lakitu Bros.' cameraman on the bridge)
'''),
('''    if MIRROR then pcall(MIRROR.clear) end''', '''    if MIRROR then pcall(MIRROR.clear) end
    if CAMLAK then pcall(CAMLAK.clear) end'''),
('''    G.name, G.data = name, data
''', '''    G.name, G.data = name, data
    -- (a new file's first walk into the castle: Bowser's welcome, DIALOG_021, before the castle's tune - Mario 64's
    -- gNeverEnteredCastle, act_warp_door_spawn and sound_init.c)
    if name == "castle" and G.never_entered then
        G.never_entered, G.welcome_at, G.music_held = false, os.clock() + 1.0, true
    end
'''),
('''    if MUSIC then pcall(MUSIC.play, G.music_override or data.music, G.music_override ~= nil) end     -- (the ending's tunes carry on)''',
 '''    if MUSIC and G.music_held then
        G.music_held = nil
        pcall(MUSIC.play, nil)                  -- (Bowser's welcome first: the castle's tune after it)
    elseif MUSIC then pcall(MUSIC.play, G.music_override or data.music, G.music_override ~= nil) end     -- (the ending's tunes carry on)
    if CAMLAK then
        local okc, errc = pcall(CAMLAK.load, world, name, {
            actor_data = actor_data, say = function(...) return G.say(...) end,
            wanted = function() return G.never_entered end,
            music_back_in = function(secs) G.music_back_at = os.clock() + secs end })
        if not okc then log("camera Lakitu failed: %s", tostring(errc)) end
    end'''),
('''    if MIRROR then guarded("mirror", MIRROR.update, dt, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0)) end''',
 '''    if MIRROR then guarded("mirror", MIRROR.update, dt, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0)) end
    if CAMLAK then
        local yaw = 0.0
        pcall(function() yaw = pawn:K2_GetActorRotation().Yaw end)
        guarded("camlakitu", CAMLAK.update, dt, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0), yaw)
    end
    if G.welcome_at and os.clock() >= G.welcome_at and not G.pending and not G.warping
        and not (DIALOG and DIALOG.active) then
        G.welcome_at = nil
        G.say(21, function() if MUSIC and G.data then pcall(MUSIC.play, G.data.music) end end)
    end'''),
('''        for _, m in ipairs({ BUTTERFLY, MOVTEX, SCENERY, MIRROR, FPV, SWIM, PAUSE, BURN, RAG }) do if m and m.forget then pcall(m.forget) end end''',
 '''        for _, m in ipairs({ BUTTERFLY, MOVTEX, SCENERY, MIRROR, CAMLAK, FPV, SWIM, PAUSE, BURN, RAG }) do if m and m.forget then pcall(m.forget) end end'''),
])

patch(r'X:/mashup-work/menu_cur.lua', [
('''    local G = require("game")
    local ok, err = pcall(G.load_scene, "grounds")''', '''    local G = require("game")
    G.never_entered = fresh             -- (Mario 64's gNeverEnteredCastle: Lakitu on the bridge, Bowser's welcome)
    local ok, err = pcall(G.load_scene, "grounds")'''),
])
print('ok')
