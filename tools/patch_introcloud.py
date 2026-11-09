def patch(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)


patch(r'X:/mashup-work/intro_cur.lua', [
('''    s.lakitu = actor("lakitu", wpos(data.cam, 1))
''', '''    s.lakitu = actor("lakitu", wpos(data.cam, 1))
    -- (his cloud, intro_lakitu.inc.c -> bhvCloud: five mist puffs; he flew bare, 2026-10-15)
    s.lakitu_cloud = {}
    for i = 1, 5 do
        local p = actor("mist", wpos(data.cam, 1))
        if p then
            pcall(function() p.actor:SetActorScale3D({ X = 4.0 / 3.0, Y = 4.0 / 3.0, Z = 4.0 / 3.0 }) end)
            s.lakitu_cloud[#s.lakitu_cloud + 1] = p
        end
    end
'''),
('''        lib.destroy(s.lakitu and s.lakitu.actor)
''', '''        lib.destroy(s.lakitu and s.lakitu.actor)
        for _, p in ipairs(s.lakitu_cloud or {}) do lib.destroy(p.actor) end
'''),
('''    s.cam_pitch = pitch
''', '''    s.cam_pitch = pitch
    s.cam_at = { px, py, pz }
'''),
('''            pcall(function() s.lakitu.actor:SetActorHiddenInGame(not on) end)
''', '''            pcall(function() s.lakitu.actor:SetActorHiddenInGame(not on) end)
            for _, p in ipairs(s.lakitu_cloud or {}) do pcall(function() p.actor:SetActorHiddenInGame(not on) end) end
'''),
('''                    { Pitch = turn(Lk[a6 + 4], Lk[b6 + 4], lt), Yaw = turn(Lk[a6 + 5], Lk[b6 + 5], lt), Roll = turn(Lk[a6 + 6], Lk[b6 + 6], lt) })
            end)
''', '''                    { Pitch = turn(Lk[a6 + 4], Lk[b6 + 4], lt), Yaw = turn(Lk[a6 + 5], Lk[b6 + 5], lt), Roll = turn(Lk[a6 + 6], Lk[b6 + 6], lt) })
            end)
            -- his cloud (cloud.inc.c bhv_cloud_part_update: two thirds of the cloud's double size, 25 out round him a
            -- fifth of a turn apart, 11, 8, 12, 8, 9 up, bobbing along (1, 1, 1) once in 32 frames), each puff a
            -- billboard: its face (-x) turned to the camera
            local cam = s.cam_at
            if cam and s.lakitu_cloud then
                local lx, ly, lz = lerp(Lk, a6, b6, lt, 1), lerp(Lk, a6, b6, lt, 2), lerp(Lk, a6, b6, lt, 3)
                local lyaw = turn(Lk[a6 + 5], Lk[b6 + 5], lt)
                local sc, U = 4.0 / 3.0, 0.75
                local UP = { 11, 8, 12, 8, 9 }
                for i, p in ipairs(s.lakitu_cloud) do
                    local k = i - 1
                    local ang = rad(lyaw + k * 72.0)
                    local bob = 2.0 * cos(rad(((f - data.lakitu_from) * 0x800 + 0x4000 * k) * 360.0 / 65536.0)) * sc * U
                    local qx = lx + cos(ang) * 25.0 * sc * U + bob
                    local qy = ly + sin(ang) * 25.0 * sc * U + bob
                    local qz = lz + UP[i] * sc * U + bob
                    local dx, dy, dz = cam[1] - qx, cam[2] - qy, cam[3] - qz
                    pcall(function()
                        p.actor:K2_TeleportTo({ X = qx + OFFSET.X, Y = qy + OFFSET.Y, Z = qz + OFFSET.Z },
                            { Pitch = -deg(atan(dz, sqrt(dx * dx + dy * dy))), Yaw = deg(atan(dy, dx)) + 180.0, Roll = 0.0 })
                    end)
                end
            end
'''),
])
print('ok')
