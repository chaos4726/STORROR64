p = r'X:\mashup-work\enemies.lua'
s = open(p, encoding='utf-8').read()


def rep(a, b):
    global s
    assert s.count(a) == 1, (a[:80], s.count(a))
    s = s.replace(a, b, 1)


# --- init: the cap Klepto and the cap Mr. Blizzard
rep('''    if o.type == "bhvKlepto" and ((o.bp or 0) >> 16) & 0xFF ~= 0 then e.star_held = true end''',
'''    if o.type == "bhvKlepto" and ((o.bp or 0) >> 16) & 0xFF ~= 0 then e.star_held = true end
    -- (the other Klepto, acts 2 to 6: after Mario's cap - mariocap.lua)
    if o.type == "bhvKlepto" and ((o.bp or 0) >> 16) & 0xFF == 0 then e.cap_klepto = true end''')
rep('''        if not jumping then e.bz_hidden = true; pcall(function() inst.actor:SetActorHiddenInGame(true) end) end
    end''', '''        if not jumping then e.bz_hidden = true; pcall(function() inst.actor:SetActorHiddenInGame(true) end) end
        -- (MR_BLIZZARD_STYPE_CAP: the one who wears Mario's cap when the file says he has it - mariocap.lua)
        e.cap_bz = (((o.bp or 0) >> 16) & 0xFF) == 2
    end''')

# --- the cap Klepto's flight, and Mario's cap shown on whoever has it
rep('''local function step_flyer(e, m, pawn, world)
    if e.type == "bhvKlepto" and e.star_held ~= nil then return step_klepto(e, m, pawn, world) end''',
'''-- Mario's cap held by someone (Klepto in his talons, Mr. Blizzard on his head): drawn there, or put away
local function cap_shown_on(e, world, on, x, y, z, yaw)
    if not on then
        if e.cap_inst then lib.destroy(e.cap_inst.actor); e.cap_inst = nil end
        return
    end
    if not e.cap_inst then
        local data = H.actor_data and H.actor_data("cap_red")
        if data then e.cap_inst = instance(world, data, x, y, z, 0, 1.3) end
    end
    if e.cap_inst then
        local sx, sy, sz = to_scene(x, y, z)
        lib.set_pose(e.cap_inst, sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z, yaw or 0.0)
    end
end

-- The other Klepto (klepto.inc.c, Shifting Sand Land acts 2 to 6): he circles his place; with Mario within 1000 he
-- turns to him, then dives at him at 60; on him (within 200, up his body) and Mario wearing his cap, he takes it
-- (mario_lose_cap_to_enemy) and flies about the desert's pillars with it, as the star Klepto does. Hit, he lets it
-- fall (spawn_object bhvNormalCap) and is knocked away, back at his place later.
local function klepto_cap_drop(e, m, world)
    local kc = e.kc
    kc.act, kc.t = "struck", 0
    e.away = s16(m.angle + 0x8000)
    sound("en_klepto", 1.0)
    cap_shown_on(e, world, false)
    local MC = package.loaded["mariocap"]
    if MC and MC.drop then
        local sx, sy, sz = to_scene(e.x, e.y - 60.0, e.z)
        pcall(MC.drop, sx, sy, sz, math.random(0, 359), 150.0, 0.0)
    end
    log("Klepto: hit, he lets Mario's cap go")
end
local function step_klepto_cap(e, m, pawn, world)
    local MC = package.loaded["mariocap"]
    e.kc = e.kc or { act = (MC and MC.held_by and MC.held_by("klepto")) and "hold" or "wait", t = 0 }
    local kc = e.kc
    kc.t = kc.t + 1
    e.f = e.f + 1.0
    e.at = (e.at or 0) + 1
    local function go(act) kc.act, kc.t = act, 0 end
    local lat = math.sqrt((m.x - e.x) ^ 2 + (m.z - e.z) ^ 2)
    if kc.act == "struck" then
        local up = (kc.t < 20) and -10.0 or 25.0
        fly_to(e, e.x + 400.0 * sins(e.away), e.y + up * 16.0, e.z + 400.0 * coss(e.away), (kc.t < 20) and 25.0 or 30.0)
        if kc.t > 150 then
            -- (klepto_act_reset_position: back at his place)
            e.x, e.y, e.z = e.hx, e.hy, e.hz
            go("wait")
        end
        return
    end
    if kc.act == "hold" then
        -- (klepto_act_circle_target_holding: round one of the three pillars at 40, now and then over to another at 50)
        if not (MC and MC.held_by and MC.held_by("klepto")) then go("wait"); cap_shown_on(e, world, false); return end
        e.tgt = e.tgt or 1
        e.change = e.change or (300 + math.random(0, 300))
        e.since = (e.since or 0) + 1
        if e.since >= e.change or (e.since > 60 and m.dist > 2000.0 and e.near_pick ~= e.tgt) then
            local best, bd = e.tgt, nil
            if m.dist > 2000.0 then
                for i, T in ipairs(KLEPTO_TARGETS) do
                    local d = (m.x - T[1]) ^ 2 + (m.z - T[3]) ^ 2
                    if not bd or d < bd then best, bd = i, d end
                end
                e.near_pick = best
            else
                best = math.random(1, 3)
            end
            e.tgt, e.since, e.change = best, 0, 300 + math.random(0, 300)
        end
        local T = KLEPTO_TARGETS[e.tgt]
        local far = (e.x - T[1]) ^ 2 + (e.z - T[3]) ^ 2 > 1800.0 * 1800.0
        e.ang = (e.ang or 0) + 0x180
        fly_to(e, T[1] + 300.0 * sins(e.ang), T[2] + 40.0 * sins(e.at * 500), T[3] + 300.0 * coss(e.ang), far and 50.0 or 40.0)
        cap_shown_on(e, world, true, e.x, e.y - 90.0, e.z, (e.at * 6.0) % 360.0)
        return
    end
    cap_shown_on(e, world, false)
    if kc.act == "wait" then
        e.ang = (e.ang or 0) + 0x140
        fly_to(e, e.hx + 300.0 * sins(e.ang), e.hy + 40.0 * sins(e.at * 500), e.hz + 300.0 * coss(e.ang), 30.0)
        if lat < 1000.0 and abs(m.y - e.y) < 1500.0 then go("turn"); sound("en_klepto", loudness(e, m)) end
    elseif kc.act == "turn" then
        -- (klepto_act_turn_toward_mario: round him at 1000, then the dive once he is lined up and 800 off)
        local a = s16(atan2s(e.z - m.z, e.x - m.x) + 0x200)
        fly_to(e, m.x + 1000.0 * sins(a), m.y + 600.0, m.z + 1000.0 * coss(a), 35.0)
        if lat > 1500.0 then go("wait")
        elseif kc.t > 45 and lat > 800.0 then go("dive"); sound("en_klepto", loudness(e, m)) end
    elseif kc.act == "dive" then
        -- (klepto_act_dive_at_mario: at 60, at his middle)
        fly_to(e, m.x, m.y + 40.0, m.z, 60.0)
        local dy = e.y - m.feet
        if lat < 200.0 and dy > 40.0 and dy < 260.0 and MC and MC.lose_to and MC.lose_to("klepto") then
            sound("en_klepto", 1.0)
            log("Klepto took Mario's cap")
            go("hold")
        elseif kc.t > 75 then
            go("wait")
        end
    end
end

local function step_flyer(e, m, pawn, world)
    if e.type == "bhvKlepto" and e.star_held ~= nil then return step_klepto(e, m, pawn, world) end
    if e.type == "bhvKlepto" and e.cap_klepto then return step_klepto_cap(e, m, pawn, world) end''')

# --- hitting the cap Klepto while he holds it
rep('''        if near and (new_attack or (m.air and not m.falling and m.y < e.y)) then klepto_drop(e, m, world) end
        return
    end''', '''        if near and (new_attack or (m.air and not m.falling and m.y < e.y)) then klepto_drop(e, m, world) end
        return
    end
    if e.type == "bhvKlepto" and e.cap_klepto then
        if e.kc and e.kc.act == "hold" then
            local dx, dz = m.x - e.x, m.z - e.z
            local near = dx * dx + dz * dz < 280.0 * 280.0 and m.y > e.y - 330.0 and m.y < e.y + 250.0
            if near and (new_attack or (m.air and not m.falling and m.y < e.y)) then klepto_cap_drop(e, m, world) end
        end
        return
    end''')

# --- Mr. Blizzard: the cap on his head, and let fall when he topples
rep('''local function bz_topple(e, m)
    local B = e.bz''', '''local function bz_topple(e, m)
    local B = e.bz
    -- (mr_blizzard_act_death: wearing Mario's cap, he lets it fall - 105 up on him, 10 a frame off to a side)
    if e.cap_bz and e.cap_inst then
        local MC = package.loaded["mariocap"]
        cap_shown_on(e, lib.world(), false)
        if MC and MC.drop then
            local sx, sy, sz = to_scene(e.x, e.y + (B.gy or 0.0) + 105.0, e.z)
            pcall(MC.drop, sx, sy, sz, math.random(0, 359), 225.0, 200.0)
        end
        log("Mr. Blizzard: toppled, he lets Mario's cap fall")
    end''')
rep('''local function step_blizzard(e, m, pawn, world)
    local B = e.bz
    B.t = B.t + 1''', '''local function step_blizzard(e, m, pawn, world)
    local B = e.bz
    B.t = B.t + 1
    -- (Mario's cap on his head while the file says he has it, and he is up out of the snow)
    if e.cap_bz then
        local MC = package.loaded["mariocap"]
        local has = MC and MC.held_by and MC.held_by("blizzard")
        local up = has and not e.bz_hidden and B.act ~= "death"
        cap_shown_on(e, world, up, e.x, e.y + (B.gy or 0.0) + 105.0 * (B.scale or 1.0), e.z, -(e.yaw or 0) * 360.0 / 65536.0)
    end''')

# --- the wind: blown for 20 frames, the cap goes (act_getting_blown, mario_blow_off_cap)
rep('''    if m.dist < 1500.0 and abs(m.y - e.y) < 500.0 and abs(off) < 0x1500 and not penguin_shields(e, m) then
        push_athlete(away, 9.0)''', '''    if m.dist < 1500.0 and abs(m.y - e.y) < 500.0 and abs(off) < 0x1500 and not penguin_shields(e, m) then
        push_athlete(away, 9.0)
        blown_cap(away)''')
rep('''            if m.dist < 1500.0 then push_athlete(m.angle, 30.0) end''',
    '''            if m.dist < 1500.0 then push_athlete(m.angle, 30.0); blown_cap(m.angle) end''')
rep('''local function push_athlete(dir, k)''', '''-- 20 frames blown, and the wind takes Mario's cap off him (act_getting_blown's actionTimer, mario_blow_off_cap): the
-- frames counted while it keeps blowing on him, started again once it has stopped for half a second
local blown = { n = 0, at = 0.0 }
local function blown_cap(dir)
    local now = os.clock()
    if now - blown.at > 0.5 then blown.n = 0 end
    blown.at, blown.n = now, blown.n + 1
    if blown.n == 20 then
        local MC = package.loaded["mariocap"]
        if MC and MC.blow_off then
            -- (the way he is blown, in the scene's own turning: Mario 64's x, z are the scene's y, -x)
            pcall(MC.blow_off, lib.pawn(), math.deg(math.atan(sins(dir), -coss(dir))))
        end
    end
end

local function push_athlete(dir, k)''')
open(p, 'w', encoding='utf-8').write(s)
print('ok')
