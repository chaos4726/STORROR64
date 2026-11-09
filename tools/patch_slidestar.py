def patch(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)


patch(r'X:/mashup-work/exporter/build_all.py', [
('''            elif b == 'bhvHiddenRedCoinStar':
                objects.append({'kind': 'red_coin_star', 'pos': ue(*pos), 'id': star_id(o.get('bparam', '0'))})''',
 '''            elif b == 'bhvHiddenRedCoinStar':
                objects.append({'kind': 'red_coin_star', 'pos': ue(*pos), 'id': star_id(o.get('bparam', '0'))})
            elif b == 'bhvCCMTouchedStarSpawn':
                # Cool, Cool Mountain's slide star (spawn_star_exit.inc.c): once he has been down the slide (area 2),
                # coming back out by the cabin brings it out of (2780, y+100, 4666) over to (2500, -4350, 5750)
                objects.append({'kind': 'slide_star', 'pos': ue(2780, o['y'] + 100, 4666), 'to': ue(2500, -4350, 5750),
                                'id': star_id(o.get('bparam', '0'))})'''),
])

patch(r'X:/mashup-work/game_cur.lua', [
# --- won stars see-through, everywhere a star is put
('''function G.add_star(world, o, hidden)
    local data = actor_data(o.model or "star")''',
 '''-- A star already won shows see-through (spawn_star.inc.c bhv_collect_star_init: MODEL_TRANSPARENT_STAR), wherever it
-- is put: the course's stars, the bosses', the red coins' and the secrets'. (They all showed solid, 2026-10-15.)
-- Its key may be any of the course's areas: a star is the course's whichever area it was won in.
function G.star_won(key)
    local MN = _G.MENU
    if not (MN and MN.has_star and key) then return false end
    if MN.has_star(key) then return true end
    local scene, id = tostring(key):match("^(.-):(%d+)$")
    if not scene or scene == "castle" or scene == "key" then return false end
    local course = G.level_of(scene)
    for _, p in ipairs({ course, course .. "_2", course .. "_3", course .. "_4" }) do
        if MN.has_star(p .. ":" .. id) then return true end
    end
    return false
end

-- The red-coin star's place (reds_star_marker.inc.c, spawned by bhv_hidden_red_coin_star_init in every course but
-- Jolly Roger Bay): a see-through star lying flat on the floor, 60 up, half again as big and turning 0x100 a frame,
-- left there when the star itself comes out. (There was none, 2026-10-15.)
local function add_red_marker(world, o)
    if G.level_of(G.name) == "jrb" then return end
    local data = actor_data("transparent_star")
    if not data then return end
    local x, y = o.pos[1], o.pos[2]
    local fz = floor_z(x, y, o.pos[3] + 100.0)
    if not fz then return end
    local inst = lib.make_instance(world, data, wpos({ x, y, fz + 60.0 * 0.75 }), 0.0, 1.0)
    if not inst then return end
    inst.moves = true
    pcall(function() inst.actor:SetActorScale3D({ X = 0.75, Y = 1.5, Z = 1.5 }) end)
    G.stars[#G.stars + 1] = { inst = inst, x = x, y = y, z = fz + 60.0 * 0.75, marker = true, t = 0.0 }
end

function G.add_star(world, o, hidden)
    local key = o.key or (tostring(G.name) .. ":" .. tostring(o.id or 0))
    local model = o.model or (G.star_won(key) and "transparent_star" or nil)
    local data = actor_data(model or "star")'''),
('''    local s = { inst = inst, x = x, y = y, z = z, key = o.key or (tostring(G.name) .. ":" .. tostring(o.id or 0)), hidden = hidden and true or false, t = 0.0,''',
 '''    local s = { inst = inst, x = x, y = y, z = z, key = key, hidden = hidden and true or false, t = 0.0,'''),
# --- markers turn in place, untaken
('''    for _, s in ipairs(G.stars) do
        local taking = not G.cutscene           -- (the ending: he can walk about, but takes nothing)
        if not s.hidden and not s.taken then''',
 '''    for _, s in ipairs(G.stars) do
        local taking = not G.cutscene           -- (the ending: he can walk about, but takes nothing)
        if s.marker then
            s.t = s.t + dt
            local yaw = (s.t * 42.1875) % 360.0
            pcall(function() s.inst.actor:K2_TeleportTo({ X = s.x + OFFSET.X, Y = s.y + OFFSET.Y, Z = s.z + OFFSET.Z },
                { Pitch = 90.0, Yaw = yaw, Roll = 0.0 }) end)
        elseif not s.hidden and not s.taken then'''),
# --- the objects
('''            elseif o.kind == "red_coin_star" then G.red_star = G.add_star(world, o, true)''',
 '''            elseif o.kind == "red_coin_star" then
                G.red_star = G.add_star(world, o, true)
                pcall(add_red_marker, world, o)
            elseif o.kind == "slide_star" then
                -- (gCCMEnteredSlide: set by going down the slide, cleared when the course is entered afresh)
                if G.slid == G.level_of(name) then
                    G.add_star(world, { pos = o.to, id = o.id, from = o.pos })
                    log("back from the slide: its star has come out")
                end'''),
# --- the flag
('''    G.destroy_scene()
    if G.set_down_for_good then pcall(G.set_down_for_good, false) end''',
 '''    G.destroy_scene()
    if G.set_down_for_good then pcall(G.set_down_for_good, false) end
    -- (object_list_processor.c: a course's second area entered sets gCCMEnteredSlide; a new course clears it)
    do
        local lvl = G.level_of(name)
        if G.slid and G.slid ~= lvl then G.slid = nil end
        if name == lvl .. "_2" then G.slid = lvl end
    end'''),
])
print('ok')
