def patch(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)


patch(r'X:/mashup-work/swim.lua', [
('''function S.active() return st ~= nil end''', '''function S.active() return st ~= nil end

-- The Koopa shell held under water (mario_actions_submerged.c act_water_shell_swimming): for 240 frames he flutter-kicks
-- at 30 a frame (675 cm/s), the button not needed, and it is gone after; out of the water it is lost. (2026-10-15)
S.shell = nil
function S.grab_shell(secs) S.shell = secs or 8.0 end'''),
('''    if not down or st.speed > KICK_SPEED then st.speed = max(0.0, st.speed - DRAG * dt) end''',
 '''    if not down or st.speed > KICK_SPEED then st.speed = max(0.0, st.speed - DRAG * dt) end
    if S.shell then
        S.shell = S.shell - dt
        if S.shell <= 0.0 then S.shell = nil
        else st.speed = min(675.0, st.speed + DRAG * dt + 1350.0 * dt) end
    end'''),
('''function S.stop(pawn)
    if not st then return end''', '''function S.stop(pawn)
    S.shell = nil
    if not st then return end'''),
])

patch(r'X:/mashup-work/game_cur.lua', [
('''            elseif o.kind == "secret_trigger" then G.add_trigger(o)''',
 '''            elseif o.kind == "secret_trigger" then G.add_trigger(o)
            elseif o.kind == "water_shell" then G.add_water_shell(world, o)'''),
('''function G.give_cap(kind) if CAPS then CAPS.give(kind) end end''',
 '''function G.give_cap(kind) if CAPS then CAPS.give(kind) end end

-- The Koopa shells lying under water in DDD and JRB (koopa_shell_underwater.inc.c): swum into, he holds it out in front
-- and swims fast for 8 s to the power-up tune (swim.lua S.grab_shell); then it is gone, as it is when he leaves the
-- water. Back with the scene. (They were missing, 2026-10-15.)
G.water_shells = {}
function G.add_water_shell(world, o)
    local data = actor_data("koopa_shell")
    if not data then return end
    local inst = lib.make_instance(world, data, wpos(o.pos), 0.0, 1.0)
    if not inst then return end
    inst.moves = true
    G.extras[#G.extras + 1] = inst.actor
    G.water_shells[#G.water_shells + 1] = { inst = inst, x = o.pos[1], y = o.pos[2], z = o.pos[3], t = 0.0 }
end

local function update_water_shells(dt, pawn, px, py, pz)
    for _, s in ipairs(G.water_shells) do
        if s.held then
            if not (SWIM and SWIM.shell) then
                s.held, s.gone = false, true
                pcall(function() s.inst.actor:SetActorHiddenInGame(true) end)
                sfx("en_shrink")
            else
                -- (out in front of him as he swims)
                local yaw = 0.0
                pcall(function() yaw = pawn:K2_GetActorRotation().Yaw end)
                local r = math.rad(yaw)
                s.t = s.t + dt
                lib.set_pose(s.inst, px + math.cos(r) * 70.0, py + math.sin(r) * 70.0, pz - 30.0, yaw + 90.0)
            end
        elseif not s.gone then
            s.t = s.t + dt
            lib.set_pose(s.inst, s.x + OFFSET.X, s.y + OFFSET.Y, s.z + OFFSET.Z + 6.0 * math.sin(s.t * 2.0), (s.t * 40.0) % 360.0)
            local dx, dy, dz = px - OFFSET.X - s.x, py - OFFSET.Y - s.y, pz - OFFSET.Z - s.z
            if G.swim and SWIM and SWIM.grab_shell and dx * dx + dy * dy + dz * dz < 130.0 * 130.0 then
                s.held = true
                SWIM.grab_shell(8.0)
                if MUSIC and MUSIC.play then pcall(MUSIC.play, "event_powerup", true) end
                G.music_back_at = os.clock() + 8.2
                sfx("star_sound")
                log("koopa shell: grabbed")
            end
        end
    end
end'''),
('''    if CAPS then guarded("caps", CAPS.update, dt, pawn) end''', '''    if CAPS then guarded("caps", CAPS.update, dt, pawn) end
    if #G.water_shells > 0 then guarded("shells", update_water_shells, dt, pawn, px, py, pz) end'''),
])
print('ok')
