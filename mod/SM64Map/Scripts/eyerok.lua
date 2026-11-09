-- SM64Map: Eyerok, Shifting Sand Land's boss (behaviors/eyerok.inc.c), ported as Mario 64 has him: a boss object with
-- no body of its own and two great stone hands. Asleep, the hands lie flat and crossed in the floor of his room, made
-- to look like it (eyerok_hand_act_sleep: 724 past their places, their rise played backwards); within 500 of him he
-- wakes - the hands come up out of the floor and over to their places, the right one arcing over the left - says his
-- piece (DIALOG_117) and the fight begins to the boss tune. The hands take turns: the one whose turn it is either rises
-- over the athlete and smashes down on him (target, smash) - turning, if he stands at its side, into a sweep across
-- the floor (fist sweep) - or pushes along the floor at him as a fist, then sweeps sideways (fist push, fist sweep); the
-- other opens to show its eye (open, show eye) till the first is home. Every sixth turn both rise over him and pound
-- the floor turn about, hopping across the room (double pound) - as they do, in place, whenever he is right by Eyerok.
-- The eye hit from in front of it (a punch or a kick, or landed on) - three times a hand - and the hand is knocked back;
-- the third and it dies; both, and Eyerok's star. The hands are solid - to stand on, to be pushed by - and a pound on
-- him hurts ("we need to fix the eye rock boss fight", "the eyerok has no collisions when you first come into the
-- level they're not hiding. they're not using the push move", "seemingly no audio from the eyerocks", 2026-10-23).
-- Driven from enemies.lua: step_boss / step_hand each frame (30 a second), touch for the athlete's attacks; X its
-- helpers (sound, floor_y, hurt, say, talk_cam, boss_music, to_scene, log).
local lib = require("lib")
local M = {}
M.PUSH_SPEED, M.SWEEP_MAX, M.SHOVE_MAX = 30.0, 40.0, 600.0   -- (Mario units a frame; the shove in cm a second)
local floor, abs, sqrt, min, max, pi = math.floor, math.abs, math.sqrt, math.min, math.max, math.pi
local S = 0.75

local function s16(a) a = floor(a) % 65536; if a >= 32768 then a = a - 65536 end; return a end
local function sins(a) return math.sin(a * pi / 32768.0) end
local function coss(a) return math.cos(a * pi / 32768.0) end
local function atan2s(y, x) return math.atan(x, y) * 32768.0 / pi end
local function turn_toward(cur, target, inc)
    local d = s16(target - cur)
    if d > inc then return s16(cur + inc), false end
    if d < -inc then return s16(cur - inc), false end
    return s16(target), true
end
local function approach(v, target, step)
    if v < target then v = min(target, v + step) else v = max(target, v - step) end
    return v, v == target
end

-- the hands' solid shape: a block on their underside, a little smaller than the fist (Mario 64 units, before its 1.5)
local HAND_BOX = { half = 100.0, top = 110.0 }
local function box_collision()
    local h, y0, y1 = HAND_BOX.half, 0.0, HAND_BOX.top
    local pos = {}
    for _, p in ipairs({ { -h, y0, -h }, { h, y0, -h }, { h, y1, -h }, { -h, y1, -h },
                         { -h, y0, h }, { h, y0, h }, { h, y1, h }, { -h, y1, h } }) do
        pos[#pos + 1], pos[#pos + 2], pos[#pos + 3] = -p[3] * S, p[1] * S, p[2] * S
    end
    return { source = "eyerok", pos = pos,
             idx = { 0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5,
                     2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7 } }
end
local function solid(h, on)
    local k = h.ey
    if on and not k.pmc and h.inst and h.inst.actor then
        pcall(function()
            local pmc = lib.add_pmc(h.inst.actor)
            if pmc then
                lib.add_collision(pmc, { box_collision() }); k.pmc = pmc
                -- (the left hand's mirror undone for its solid box: inside out, it would not hold him up)
                pcall(function() pmc:SetRelativeScale3D({ X = 1.0, Y = k.side, Z = 1.0 }) end)
            end
        end)
    end
    if k.pmc and k.solid ~= on then
        k.solid = on
        pcall(function() k.pmc:SetCollisionEnabled(on and 3 or 0) end)
    end
end

-- ------------------------------------------------------------ animation (each hand's own: id, frame)
local function alen(h, n)
    local an = h.inst and h.inst.data and h.inst.data.anims and h.inst.data.anims[n + 1]
    return (an and an.frames) or 30
end
local function anim(h, n) local k = h.ey; if k.anim ~= n then k.anim, k.af = n, 0 end end
local function at_end(h) return h.ey.af >= alen(h, h.ey.anim) - 1 end
local function near_end(h) return h.ey.af >= alen(h, h.ey.anim) - 2 end
local function anim_end(h, n) anim(h, n); return at_end(h) end          -- (cur_obj_init_anim_and_check_if_end)

-- ------------------------------------------------------------ the boss
local function boss_state(e)
    if e.ey then return e.ey end
    e.ey = { act = "sleep", timer = 0, hands = 0, fc = 0, u104 = 0, u108 = 0.0, u10C = 0.0, u110 = 0.0, active = 0,
             u1AC = 0 }
    return e.ey
end
-- (eyerok_check_mario_relative_z: the athlete less than `d` out in front of Eyerok - by him, among his hands)
local function close_in(e, m, d) return m.z - e.hz < d end

function M.step_boss(e, m, pawn, world, X)
    local B = boss_state(e)
    B.timer = B.timer + 1
    if B.act == "sleep" then
        if B.timer > 15 and m.dist < 500.0 then
            B.act, B.timer = "wake", 0
            X.sound("eyerok_wake", 1.0)
            X.log("Eyerok wakes (%.0f away)", m.dist)
        end
    elseif B.act == "wake" then
        -- (eyerok_boss_act_wake_up: both hands up, then his piece - DIALOG_117 - and the fight to the boss tune)
        if B.hands < 2 then B.timer = 0
        elseif B.timer > 5 then
            B.act = "intro"
            pcall(X.talk_cam, e)
            X.say(117, function() B.act, B.timer = "fight", 0; X.boss_music(true) end, e)
        end
    elseif B.act == "fight" then
        if B.hands == 0 then
            B.act, B.timer = "die", 0
        elseif B.u1AC == 0 and B.active == 0 then
            -- (eyerok_boss_act_fight: whose turn, and every sixth a double pound - or, him right by Eyerok, a
            -- pounding in place till he moves off)
            if B.u104 ~= 0 then
                local reached
                B.u110, reached = approach(B.u110, 1.0, 0.02)
                if reached then
                    if B.u104 < 0 then
                        if not close_in(e, m, 400.0) then
                            B.u104 = B.u104 + 1
                            if B.u104 == 0 then B.u104 = 1 end
                        end
                    else
                        B.u104 = B.u104 - 1
                    end
                    if B.u104 ~= 0 and B.u104 ~= 1 then
                        B.fc = B.fc + 1
                        B.active = (B.fc % 2 == 0) and -1 or 1
                    end
                end
            else
                B.fc = B.fc + 1
                if close_in(e, m, 400.0) then
                    B.u104, B.u110, B.u108 = -8, 1.0, 0.0
                elseif B.hands == 2 and B.fc % 6 == 0 then
                    B.u104, B.u110 = 8, 0.0
                    B.fc = math.random(0, 1)
                    B.u108 = (B.fc ~= 0) and -1.0 or 1.0
                    B.u10C = max(e.hz + 400.0, min(e.hz + 1600.0, m.z))
                else
                    B.active = (B.fc % 2 == 0) and -1 or 1
                end
            end
        end
    elseif B.act == "die" then
        -- (eyerok_boss_act_die: his DIALOG_118, then his star out of him to its place)
        if B.timer == 60 then
            B.act = "dead"
            X.log("Eyerok beaten")
            pcall(X.talk_cam, e)
            X.say(118, function()
                X.boss_music(false)
                local G = package.loaded["game"]
                if G and G.add_star then
                    local sx, sy, sz = X.to_scene(0.0, -900.0, -3700.0)
                    local fx, fy, fz = X.to_scene(e.x, e.y + 300.0, e.z)
                    pcall(G.add_star, world, { kind = "star", pos = { sx, sy, sz }, id = ((e.o.bp or 0) >> 24) & 0xFF,
                                               from = { fx, fy, fz } })
                end
            end, e)
        end
    end
end

-- ------------------------------------------------------------ the hands
local function hand_state(h)
    if h.ey then return h.ey end
    local B = h.boss
    local side = (h.hx > B.x) and -1 or 1           -- (the left hand, its second parameter -1, 500 to Eyerok's left)
    h.ey = { act = "sleep", timer = 0, side = side, hp = 4, anim = 6, af = 0, fyaw = s16(-0x4000 * side), myaw = 0,
             fvel = 0.0, vy = 0.0, grav = -4.0, ground = true, wake_t = 0, fc2 = 0, u100 = 0, received = false,
             push_cool = 0 }
    -- (one hand drawn twice: Mario 64 mirrors it for the left - its x scale 1.5 times its side - and the left hand was
    -- a second right one, the wrong way round: "the right hand is facing the wrong way", 2026-10-23. Mario's x is the
    -- scene's y.)
    pcall(function() h.inst.actor:SetActorScale3D({ X = 1.5, Y = 1.5 * side, Z = 1.5 }) end)
    return h.ey
end
local function go(h, act) h.ey.act, h.ey.timer = act, 0 end

-- (eyerok_hand_pound_ground: the loud pound, the stage and the camera shaken, dust; a pound on him hurts - he was under
-- it - and anywhere in the room it throws him off his feet unless he is in the air: "when the hand slams make the stage
-- shake add the camera shake and make the playeer fall if he didnt jump", 2026-10-23. Not off the hand he stands on.)
-- (its throw off his feet only close by: dodged clear of it, he keeps them - "make sure the player doesnt fall down if
-- they dodge the first slam", 2026-10-23; the whole room at first)
M.QUAKE = { shake = 1.5, reach = 450.0, up = 200.0, hurt_knock = 0.4, every = 3.0 }
local function pound(h, m, pawn, X, no_throw)
    X.sound("big_pound", 1.0)
    local G = package.loaded["game"]
    if G and G.shake_stage then pcall(G.shake_stage, M.QUAKE.shake) end
    local EF = package.loaded["envfx"]
    if EF and EF.poof then
        local sx, sy, sz = X.to_scene(h.x, h.y, h.z)
        pcall(EF.poof, sx, sy, sz, 1.5)
    end
    if not pawn then return end
    local dx, dz = m.x - h.x, m.z - h.z
    local reach = HAND_BOX.half * 1.5 + 50.0
    local top = h.y + HAND_BOX.top * 1.5
    local SQ = package.loaded["squish"]
    local squished = SQ and SQ.active and SQ.active()
    if squished then return end
    if abs(dx) < reach and abs(dz) < reach and m.feet < top + 40.0 and m.feet > h.y - 100.0 and m.feet < top - 30.0 then
        -- (a short knock back: at 1.3 it threw him over the room's edge, a life gone - 2026-10-23)
        X.hurt(h, m, pawn, 3, "Eyerok", M.QUAKE.hurt_knock)
        return
    end
    local on_hand = abs(dx) < reach and abs(dz) < reach and m.feet >= top - 30.0
    -- (once in a while only, and not while he is down or getting up, and dropped where he stands: the double pound's
    -- pounds, one each 0.4 s, threw him down again and again as he got up, each time a little further out, and over
    -- the edge - "seems glitchy", a life gone, 2026-10-23)
    local now = os.clock()
    local down = G and (G.getup_at ~= nil or G.down_for_good)
    local RG = package.loaded["ragdoll"]
    if RG and RG.active then down = true end
    -- (not the double pound's: one each 0.4 s, the first threw him down for the next to land on - "player still falls
    -- over after dodging multi slam attacks first slam", 2026-10-23)
    if not no_throw and not m.air and not on_hand and not down and now >= (M.quake_next or 0.0)
       and dx * dx + dz * dz < M.QUAKE.reach * M.QUAKE.reach and G and G.knock_down then
        M.quake_next = now + M.QUAKE.every
        pcall(G.knock_down, pawn, 0.0, 0.0, M.QUAKE.up)
        X.log("Eyerok's pound knocks him off his feet")
    end
end

-- (crushed under it as it comes down on him - squish.lua, as under a Thwomp: pressed flat under its underside, three
-- wedges, held while it sits on him, up again once it lifts: "hand doesnt crush player if it lands on him", 2026-10-23.
-- Its own solid block shoved him out from under it before; it is not solid while it falls.)
M.CRUSH = { reach = 170.0, head = 235.0 }
M.INSIDE_R = 215.0              -- (its block's corner, 150 * 1.41, and his half width)
local function crush(h, m, pawn, X)
    local k = h.ey
    if not pawn or k.vy >= 0.0 or k.ground then return end
    local dx, dz = m.x - h.x, m.z - h.z
    if abs(dx) > M.CRUSH.reach or abs(dz) > M.CRUSH.reach then return end
    if h.y < m.feet + 20.0 or h.y > m.feet + M.CRUSH.head + 60.0 then return end
    local SQ = package.loaded["squish"]
    if not (SQ and SQ.start) or (SQ.active and SQ.active()) then return end
    local O = lib.OFFSET
    local fy = X.floor_y(h.x, h.y + 200.0, h.z) or h.hy
    -- (its underside over where he lies; off him - lifted, or slid away home along the floor, or gone - it is clear of
    -- him: slid off him, it kept him flat for good, "body stuck crushed", 2026-10-23)
    local px, pz = m.x, m.z
    local function bottom()
        if h.action == "gone" or abs(h.x - px) > M.CRUSH.reach or abs(h.z - pz) > M.CRUSH.reach then
            return fy * S + O.Z + 100000.0
        end
        return h.y * S + O.Z
    end
    local ok = SQ.start(pawn, { bottom = bottom, floor = fy * S + O.Z, grounded = not m.air, what = "Eyerok" })
    if ok then X.log("crushed under Eyerok's hand") end
end

-- (cur_obj_move_standard(-78): along its way - never off an edge: OBJ_MOVE_HIT_EDGE - and stopped by a rise in the
-- floor, OBJ_MOVE_HIT_WALL; then its fall, onto the floor)
local function move(h, X, fall)
    local k = h.ey
    k.hit_edge, k.hit_wall = false, false
    if k.fvel ~= 0.0 then
        local nx, nz = h.x + k.fvel * sins(k.myaw), h.z + k.fvel * coss(k.myaw)
        local here = X.floor_y(h.x, h.y + 200.0, h.z) or h.y
        local there = X.floor_y(nx, h.y + 200.0, nz)
        if not there or there < here - 100.0 then k.hit_edge = true
        elseif there > h.y + 60.0 then k.hit_wall = true
        else h.x, h.z = nx, nz end
    end
    if fall then
        k.vy = max(-75.0, k.vy + k.grav)
        h.y = h.y + k.vy
        local fy = X.floor_y(h.x, h.y + 200.0, h.z)
        if fy and h.y <= fy then
            h.y = fy
            if k.vy < 0.0 then k.vy = 0.0 end
            k.ground = true
        else
            k.ground = false
        end
    else
        -- (moved by hand - risen, carried over him: on the ground only where it stands on it. A stale "on the ground"
        -- from before sent a double pound's hand hopping up and away for good)
        local fy = X.floor_y(h.x, h.y + 200.0, h.z)
        k.ground = fy ~= nil and h.y <= fy + 1.0
    end
end

-- (eyerok_hand_check_attacked: its eye hit from in front of it - the second hit leaves it two, the third kills it)
local function check_attacked(h, m, X)
    local k = h.ey
    -- (from any side: Mario 64 takes it only within 0x3000 of the hand's front, and its eye did not always look that way
    -- here - "cant hit eyerok sometimes when should be able to", 2026-10-23)
    if not k.received then return false end
    k.received = false
    X.sound("eyerok_hurt", 1.0)
    local B = h.boss.ey
    k.hp = k.hp - 1
    if k.hp >= 2 then
        go(h, "attacked")
        k.vy = 30.0
        X.log("Eyerok's hand hit (%d to go)", k.hp - 1)
    else
        B.hands = B.hands - 1
        go(h, "die")
        k.vy = 50.0
        X.log("Eyerok's hand beaten")
    end
    k.fvel = k.fvel * 0.2
    k.myaw = s16(k.fyaw + 0x8000)
    k.grav = -4.0
    return true
end

function M.step_hand(h, m, pawn, X)
    local k = hand_state(h)
    local B = boss_state(h.boss)
    local side = k.side
    k.timer = k.timer + 1
    local a = k.act
    local fall = true
    if a == "sleep" then
        -- (eyerok_hand_act_sleep: flat in the floor, crossed, 724 past its place, till Eyerok wakes; then up out of it
        -- and over - an arc, the right hand's higher - turning to face the room, its rise played to its end)
        fall = false
        solid(h, false)
        if B.act ~= "sleep" then
            k.wake_t = k.wake_t + 1
            if k.wake_t > -3 * side then
                if near_end(h) then
                    B.hands = B.hands + 1
                    go(h, "idle")
                    h.x, h.y = h.hx, h.hy
                else
                    h.x = approach(h.x, h.hx, 15.0)
                    h.y = h.hy + (200.0 * side + 400.0) * sins(s16(abs(h.x - h.hx) / 724.0 * 0x8000))
                    k.fyaw = turn_toward(k.fyaw, k.myaw, 400)
                    k.af = k.af + 1
                end
            end
        else
            h.x, h.y, h.z = h.hx + 724.0 * side, h.hy, h.hz
            k.anim, k.af = 6, 0
        end
    else
        -- (solid at rest and rising - to stand on - but not falling, nor moving across: a solid block moving fast
        -- threw him out of its way and over the room's edge, a life gone, 2026-10-23; it shoves him gently instead)
        -- (and never made solid round him: stopped or landed where he stood, its block shut him in - "player gets stuck in
        -- the hands", 2026-10-23; it waits till he is out of it)
        local dxh, dzh = m.x - h.x, m.z - h.z
        local inside = dxh * dxh + dzh * dzh < M.INSIDE_R * M.INSIDE_R and m.feet < h.y + HAND_BOX.top * 1.5 - 15.0
                       and m.feet + 235.0 > h.y
        solid(h, a ~= "die" and a ~= "dead" and not (h.ey.vy < -5.0 and not h.ey.ground) and h.ey.fvel <= 5.0
                 and not (inside and not (h.ey.solid)))
        if a == "idle" then
            anim(h, 2)
            fall = false
            if B.act == "fight" then
                if B.u104 ~= 0 then
                    if B.u104 ~= 1 then go(h, "begin_double"); k.grav = 0.0 end
                elseif B.u1AC == 0 and B.active ~= 0 then
                    if B.active == side then
                        if close_in(h.boss, m, 400.0) or math.random(0, 1) ~= 0 then
                            go(h, "target"); k.myaw = m.angle; k.grav = 0.0
                        else
                            -- (the fist push: along the floor at him, a little to his side of Eyerok)
                            go(h, "fist_push")
                            k.myaw = s16(m.angle + ((h.boss.x - m.x < 0.0) and -0x800 or 0x800))
                            k.grav = -4.0
                        end
                    else
                        go(h, "open")
                    end
                end
            else
                h.y = h.hy + B.u110
            end
        elseif a == "open" then
            B.u1AC = side
            if check_attacked(h, m, X) then
                -- (hit as its eye opened)
            elseif anim_end(h, 4) then
                go(h, "show_eye")
                k.fc2, k.u100 = 2, 60
                if B.hands ~= 2 then
                    k.myaw = max(-0x3000, min(0x3000, m.angle))
                    k.fvel = M.PUSH_SPEED                -- (the last hand's eye coming at him: Mario 64's 50, as the push)
                else
                    k.myaw = 0
                end
            end
        elseif a == "show_eye" then
            anim(h, 5)
            if k.timer == 1 then X.sound("eyerok_eye", 1.0) end
            if not check_attacked(h, m, X) then
                if B.active == 0 then
                    if near_end(h) or k.timer > 40 then go(h, "close") end
                elseif B.hands ~= 2 then
                    k.fyaw = turn_toward(k.fyaw, k.myaw, 0x800)
                    if k.timer > 10 and (h.z - m.z > 0.0 or k.hit_edge) then
                        B.active, k.fvel = 0, 0.0
                    end
                end
            end
        elseif a == "close" then
            anim(h, 7)
            if check_attacked(h, m, X) then
                -- (hit as its eye shut)
            elseif k.af >= 1 then
                if B.hands ~= 2 then
                    go(h, "retreat")
                    B.active = side
                elseif B.active == 0 then
                    go(h, "idle")
                    B.u1AC = 0
                end
            end
        elseif a == "attacked" then
            if anim_end(h, 3) then go(h, "recover") end
            if k.ground then k.fvel = 0.0 end
        elseif a == "recover" then
            if anim_end(h, 0) then go(h, "become_active") end
        elseif a == "become_active" then
            if B.active == 0 or B.hands ~= 2 then
                go(h, "retreat")
                B.active = side
            end
        elseif a == "die" then
            if anim_end(h, 1) then
                B.u1AC = 0
                -- (eyerok_hand_act_die_event: it bursts, gone)
                X.sound("eyerok_die", 1.0)
                local EF = package.loaded["envfx"]
                if EF and EF.poof then
                    local sx, sy, sz = X.to_scene(h.x, h.y + 100.0, h.z)
                    pcall(EF.poof, sx, sy, sz, 3.0)
                end
                solid(h, false)
                go(h, "dead")
                h.action = "gone"
                pcall(function() h.inst.actor:SetActorHiddenInGame(true) end)
            end
            if k.ground and k.timer > 2 then
                if k.fvel ~= 0.0 then X.sound("big_pound", 0.8) end
                k.fvel = 0.0
            end
        elseif a == "retreat" then
            -- (eyerok_hand_act_retreat: home, 40 a frame, facing the room again)
            fall = false
            k.vy, k.fvel = 0.0, 0.0
            local dx, dz = h.x - h.hx, h.z - h.hz
            local d = sqrt(dx * dx + dz * dz)
            local nd = max(0.0, d - 40.0)
            if d > 0.0 then h.x, h.z = h.hx + dx / d * nd, h.hz + dz / d * nd end
            k.fyaw = turn_toward(k.fyaw, 0, 400)
            local reached
            h.y, reached = approach(h.y, h.hy, 20.0)
            if reached and nd == 0.0 and k.fyaw == 0 then
                go(h, "idle")
                B.active = B.active - side
                if B.u1AC == side then B.u1AC = 0 end
            end
        elseif a == "target" then
            -- (eyerok_hand_act_target_mario: up 300 and over him - not past him, nor too far from Eyerok - then the smash)
            fall = false
            k.vy = 0.0
            if close_in(h.boss, m, 400.0) or h.z - m.z > 0.0 or h.z - h.boss.z > 1700.0 or abs(h.x - h.boss.x) > 900.0
               or k.hit_wall then
                k.fvel = 0.0
                local reached
                h.y, reached = approach(h.y, h.hy + 300.0, 20.0)
                if reached then go(h, "smash") end
            else
                k.fvel = approach(k.fvel, 50.0, 5.0)
                h.y = approach(h.y, h.hy + 300.0, 20.0)
                k.myaw = turn_toward(k.myaw, m.angle, 4000)
            end
        elseif a == "smash" then
            -- (eyerok_hand_act_smash: a moment over him, then down hard - the pound; and if he stands at its side, a
            -- sweep his way, else home)
            if k.timer > 20 then
                if k.ground then
                    if k.grav < -4.0 then
                        pound(h, m, pawn, X)
                        k.grav = -4.0
                    else
                        local d = abs(s16(k.fyaw - m.angle))
                        if m.dist < 300.0 and d > 0x2000 and d < 0x6000 then
                            go(h, "fist_sweep")
                            k.myaw = (s16(k.fyaw - m.angle) < 0) and 0x4000 or -0x4000
                        else
                            go(h, "retreat")
                        end
                    end
                else
                    k.grav = -20.0
                end
            else
                k.grav, k.vy = 0.0, 0.0
            end
        elseif a == "fist_push" then
            -- (eyerok_hand_act_fist_push: along the floor at him, 50 a frame; past him or at an edge, a sweep sideways)
            if k.timer > 5 and (h.z - m.z > 0.0 or k.hit_edge) then
                go(h, "fist_sweep")
                k.fvel = 0.0
                k.myaw = (h.x - m.x < 0.0) and 0x4000 or -0x4000
            else
                k.fvel = M.PUSH_SPEED                    -- (Mario 64's 50 a frame "way to fast" here: 30)
            end
        elseif a == "fist_sweep" then
            -- (eyerok_hand_act_fist_sweep: faster and faster across, till near Eyerok or at an edge)
            if h.z - h.boss.z < 1000.0 or k.hit_edge then
                go(h, "retreat")
                k.fvel = 0.0
            else
                k.fvel = min(M.SWEEP_MAX, approach(k.fvel, 5.0, 0.02) * 1.08)   -- (its 8% a frame, now with a top)
                k.timer = 0
            end
        elseif a == "begin_double" then
            -- (eyerok_hand_act_begin_double_pound: both hands up over him together)
            fall = false
            if B.u104 < 0 or B.active == side then
                go(h, "double")
                k.myaw = s16(k.fyaw - 0x4000 * B.u108)
            else
                local tx = h.boss.x + 400.0 * B.u108 - 180.0 * side
                h.x = h.hx + (tx - h.hx) * B.u110
                h.y = h.hy + 300.0 * B.u110
                h.z = h.hz + (B.u10C - h.hz) * B.u110
                k.vy = 0.0
            end
        elseif a == "double" then
            -- (eyerok_hand_act_double_pound: turn about, a pound and a hop across)
            if B.hands ~= 2 then B.active = side end
            if B.u104 == 1 then
                go(h, "retreat")
                B.u1AC = side
            elseif B.active == side then
                if k.ground then
                    if k.grav < -15.0 then
                        B.active = 0
                        pound(h, m, pawn, X, true)
                        k.fvel, k.grav = 0.0, -15.0
                    else
                        k.fvel = 30.0 * abs(B.u108)
                        k.vy = 100.0
                        k.ground = false
                        -- (and a fall to come down by: its first hop from the floor - him by Eyerok, the pound in place
                        -- straight from its rest - had none, and it rose for good)
                        if k.grav > -15.0 then k.grav = -15.0 end
                    end
                elseif k.vy <= 0.0 then
                    k.grav = -20.0
                end
            end
        end
        if k.act ~= "dead" then move(h, X, fall) end
        if k.act == "smash" or k.act == "double" then crush(h, m, pawn, X) end
        -- (a moving fist shoves him: Mario 64's push - its solid side against him; never a hurt of its own)
        if pawn and k.fvel > 5.0 and k.act ~= "die" and k.act ~= "dead" then
            if k.push_cool > 0 then k.push_cool = k.push_cool - 1 end
            local dx, dz = m.x - h.x, m.z - h.z
            local reach = HAND_BOX.half * 1.5 + 60.0
            if k.push_cool == 0 and abs(dx) < reach and abs(dz) < reach and m.feet < h.y + HAND_BOX.top * 1.5 then
                k.push_cool = 15
                -- (shoved along at its own speed, a little up - not thrown: "they're push is way to strong", 2026-10-23,
                -- once he was flung out of the room)
                local v = min(M.SHOVE_MAX, k.fvel * 30.0 * S)
                local sx, sy = -coss(k.myaw), sins(k.myaw)           -- (its way, in the scene: Mario's z is -x there)
                pcall(function()
                    local cm = pawn.CharacterMovement
                    cm:SetMovementMode(3, 0)
                    cm.Velocity = { X = sx * v, Y = sy * v, Z = 150.0 }
                end)
            end
        end
    end
    h.yaw = k.fyaw
    h.anim_i = k.anim
    h.f = k.af
    if a ~= "sleep" then
        local len = alen(h, k.anim)
        if k.anim == 2 or k.anim == 5 then k.af = (k.af + 1) % len else k.af = min(k.af + 1, len - 1) end
    end
end

-- the athlete's attacks on a hand: kept for its show_eye to look at (obj_check_attacks)
function M.touch(h, m, pawn, attack, new_attack)
    local k = h.ey
    if not k or (k.act ~= "show_eye" and k.act ~= "open" and k.act ~= "close") then return end
    local dx, dz = m.x - h.x, m.z - h.z
    local d2 = dx * dx + dz * dz
    local struck = new_attack and attack and d2 < 380.0 * 380.0 and abs(m.y - h.y) < 400.0
    local stomped = m.falling and d2 < 260.0 * 260.0 and m.feet > h.y + 60.0 and m.feet < h.y + HAND_BOX.top * 1.5 + 80.0
    if struck or stomped then k.received = true end
    if stomped and pawn then pcall(lib.bounce, pawn, 0, 0, 900) end
end

return M
