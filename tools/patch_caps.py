def patch(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)


patch(r'X:/mashup-work/game_cur.lua', [
('''local CAMLAK = optional("camlakitu")''', '''local CAPS = optional("caps")         -- (Mario 64's wing, metal and vanish caps, out of their ! boxes)
local CAMLAK = optional("camlakitu")'''),
# setup after stop_swim exists
('''G.stop_swim = function() stop_swim(lib.pawn(), 0) end
''', '''G.stop_swim = function() stop_swim(lib.pawn(), 0) end

-- the vanish-cap walls (data.vanish_walls, apart from the level's collision): solid but while he wears the cap
G.vanish_actor = nil
function G.vanish_walls(on)
    local a = G.vanish_actor
    if a then pcall(function() a:SetActorEnableCollision(on) end) end
end
function G.give_cap(kind) if CAPS then CAPS.give(kind) end end
if CAPS then
    CAPS.setup({
        music_back = function() if MUSIC and G.data then pcall(MUSIC.play, G.data.music) end end,
        vanish_walls = function(on) G.vanish_walls(on) end,
        stop_swim = function() stop_swim(lib.pawn(), 0.5) end,
        swimming = function() return G.swim end,
        busy = function() return G.thaw_at ~= nil or G.entry ~= nil or G.cutscene end,
        level = function() return G.name and G.level_of(G.name) end,
    })
end
'''),
# metal: no swimming
('''    if not G.swim then
        if not sz or (G.swim_cool or 0) > 0 then return end''', '''    if not G.swim then
        if not sz or (G.swim_cool or 0) > 0 then return end
        if CAPS and CAPS.on("metal") then return end          -- (metal: he sinks and walks the bottom)'''),
# the walls built with the scene
('''    lib.add_collision(pmc, data.collision)
    G.floor = build_floor(data.collision)''', '''    lib.add_collision(pmc, data.collision)
    G.vanish_actor = nil
    if data.vanish_walls then
        local va = lib.spawn_actor(world, OFFSET, 0.0)
        local vp = va and lib.add_pmc(va)
        if vp then
            lib.add_collision(vp, { data.vanish_walls })
            G.extras[#G.extras + 1] = va
            G.vanish_actor = va
            if CAPS and CAPS.on("vanish") then G.vanish_walls(false) end
        end
    end
    G.floor = build_floor(data.collision)'''),
# a cap ends with the course
('''    G.name, G.data = name, data
''', '''    if CAPS and CAPS.on() and CAPS.level ~= G.level_of(name) then pcall(CAPS.stop, true) end    -- (out of its course: gone)
    G.name, G.data = name, data
'''),
# and with a death
('''local function death_warp(d)
    local HP = _G.HEALTH''', '''local function death_warp(d)
    if CAPS and CAPS.on() then pcall(CAPS.stop, true) end
    local HP = _G.HEALTH'''),
# ticked
('''    if MIRROR then guarded("mirror", MIRROR.update, dt, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0)) end''',
 '''    if MIRROR then guarded("mirror", MIRROR.update, dt, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0)) end
    if CAPS then guarded("caps", CAPS.update, dt, pawn) end'''),
('''        for _, m in ipairs({ BUTTERFLY, MOVTEX, SCENERY, MIRROR, CAMLAK, FPV, SWIM, PAUSE, BURN, RAG }) do if m and m.forget then pcall(m.forget) end end''',
 '''        for _, m in ipairs({ BUTTERFLY, MOVTEX, SCENERY, MIRROR, CAMLAK, CAPS, FPV, SWIM, PAUSE, BURN, RAG }) do if m and m.forget then pcall(m.forget) end end'''),
])

patch(r'X:/mashup-work/health_cur.lua', [
('''function M.damage(wedges, why)
    if wedges <= 0 or M.grace > 0 or M.dead_t then return false end''', '''function M.damage(wedges, why)
    if wedges <= 0 or M.grace > 0 or M.dead_t then return false end
    local C = package.loaded["caps"]
    if C and C.shield and C.shield(why) then return false end         -- (the metal or vanish cap: not hurt but by falls)'''),
])

patch(r'X:/mashup-work/boxes_cur.lua', [
('''    elseif c <= 2 then return { coins = 3, cap = true }               -- (a cap the athlete cannot wear)''',
 '''    elseif c <= 2 then return { cap = ({ [0] = "wing", [1] = "metal", [2] = "vanish" })[c] }    -- (caps.lua)'''),
('''    if g.cap then sound("right_answer", 1.0) end''', '''    if g.cap and G and G.give_cap then pcall(G.give_cap, g.cap) end'''),
])
print('ok')
