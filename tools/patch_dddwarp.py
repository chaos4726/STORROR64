def patch(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)

patch(r'X:/mashup-work/exporter/build_all.py', [
("""    if coll:
        coll.pop('water', None)
    print('   sections'""", """    if level == 'castle_inside' and area == 3:
        # the DDD painting's floor (ddd_warp.inc.c bhv_ddd_warp_loop): an object's collision, not the level's - its
        # three painting strips just behind the painting and floor round them, and the same 2073.6 further back once
        # "Board Bowser's Sub" is won. (Never exported: the DDD painting could not be entered, 2026-10-15.)
        dw = {}
        for key, sym in (('front', 'inside_castle_seg7_collision_ddd_warp'), ('back', 'inside_castle_seg7_collision_ddd_warp_2')):
            c = X.export_collision(db, sym)
            c.pop('water', None)
            dw[key] = {'collision': c, 'floors': W.rule_floors(db, sym)}
        scene['ddd_warp'] = dw
    if coll:
        coll.pop('water', None)
    print('   sections'"""),
])

patch(r'X:/mashup-work/game_cur.lua', [
("""    G.floor = build_floor(data.collision)
    G.rule = build_floor(data.floors or {})
    G.bounds = build_floor(data.collision, nil, 0.05)       -- every floor and slope, for the level's edge""",
 """    -- the DDD painting's floor (ddd_warp.inc.c): its three painting strips just behind it and floor round them, or,
    -- once "Board Bowser's Sub" is won, the same 2073.6 further back with the painting slid back there (paintings.c
    -- move_ddd_painting: 20 a frame, once - SAVE_FLAG_DDD_MOVED_BACK - G.ddd_slide) and the way before it open.
    -- (It was never exported: the DDD painting could not be entered, 2026-10-15.)
    local coll_all, rule_all = data.collision, data.floors or {}
    G.ddd_slide = nil
    if data.ddd_warp then
        local MN = _G.MENU
        local won = MN and MN.has_star and (MN.has_star("ddd:0") or MN.has_star("ddd_2:0"))
        local which = won and data.ddd_warp.back or data.ddd_warp.front
        local da = lib.spawn_actor(world, OFFSET, 0.0)
        local dp = da and lib.add_pmc(da)
        if dp then lib.add_collision(dp, { which.collision }); G.extras[#G.extras + 1] = da end
        coll_all, rule_all = {}, {}
        for _, c in ipairs(data.collision) do coll_all[#coll_all + 1] = c end
        coll_all[#coll_all + 1] = which.collision
        for _, f in ipairs(data.floors or {}) do rule_all[#rule_all + 1] = f end
        for _, f in ipairs(which.floors or {}) do rule_all[#rule_all + 1] = f end
        if won then
            local back = MN.has_flag and MN.has_flag("ddd_moved_back")
            G.ddd_slide = { at = back and DDD_BACK or 0.0 }
        end
        log("DDD painting: %s", won and "back" or "in front")
    end
    G.floor = build_floor(coll_all)
    G.rule = build_floor(rule_all)
    G.bounds = build_floor(coll_all, nil, 0.05)             -- every floor and slope, for the level's edge"""),
("""local function add_painting(world, pt)""", """local DDD_BACK = (5529.6 - 3456.0) * 0.75        -- (cm the DDD painting goes back: paintings.c move_ddd_painting)

-- the DDD painting moved back (G.ddd_slide: cm along the scene's Y, Mario 64's X), 20 Mario units a frame till it is there
local function update_ddd_slide(dt)
    local sl = G.ddd_slide
    local p
    for _, q in ipairs(G.paintings) do if q.pt and q.pt.name == "ddd" then p = q end end
    if not p then return end
    if sl.at < DDD_BACK then
        sl.at = math.min(DDD_BACK, sl.at + 20.0 * 30.0 * 0.75 * dt)
        if sl.at >= DDD_BACK then
            local MN = _G.MENU
            if MN and MN.add_flag then pcall(MN.add_flag, "ddd_moved_back") end
            log("DDD painting: moved back")
        end
    elseif sl.placed then
        return
    end
    sl.placed = sl.at >= DDD_BACK
    pcall(function() p.actor:K2_TeleportTo({ X = OFFSET.X, Y = OFFSET.Y + sl.at, Z = OFFSET.Z }, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }) end)
end

local function add_painting(world, pt)"""),
("""    if HOOT then guarded("hoot", HOOT.update, dt, pawn, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0)) end""",
 """    if HOOT then guarded("hoot", HOOT.update, dt, pawn, px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z - (G.half or 90.0)) end
    if G.ddd_slide then guarded("ddd painting", update_ddd_slide, dt) end"""),
])
print('ok')
