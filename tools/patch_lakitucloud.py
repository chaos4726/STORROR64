def patch(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert s.count(a) == 1, (p, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='\n').write(s)


patch(r'X:/mashup-work/enemies.lua', [
('''function M.clear()
    for _, e in ipairs(M.list) do
        if e.inst then lib.destroy(e.inst.actor) end''', '''function M.clear()
    for _, e in ipairs(M.list) do
        if e.inst then lib.destroy(e.inst.actor) end
        for _, p in ipairs(e.cloud or {}) do lib.destroy(p.actor) end'''),
('''local function render(e, a)
    local pr = e.prev''', '''-- A Lakitu's cloud (cloud.inc.c, CLOUD_BP_LAKITU_CLOUD at twice size): five mist puffs, two thirds of the cloud's size,
-- 25 out round him at his heading plus a fifth of a turn each, 11, 8, 12, 8, 9 up, all bobbing along (1, 1, 1) once
-- in 32 frames; billboards. Gone when he is. (He flew bare, 2026-10-15.)
local PUFF_UP = { 11, 8, 12, 8, 9 }
local function render_cloud(e, a, cx, cy, cz)
    if e.cloud == nil then
        e.cloud = {}
        local mist = H.actor_data and H.actor_data("mist")
        if not mist then return end
        local world = lib.world()
        local sx, sy, sz = to_scene(e.x, e.y, e.z)
        for i = 1, 5 do
            local p = lib.make_instance(world, mist, { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z }, 0.0, 4.0 / 3.0)
            if p then p.moves = true; e.cloud[#e.cloud + 1] = p end
        end
    end
    local pr = e.prev
    local x, y, z = pr[1] + (e.x - pr[1]) * a, pr[2] + (e.y - pr[2]) * a, pr[3] + (e.z - pr[3]) * a
    local s = 4.0 / 3.0
    e.puff_t = (e.puff_t or 0) + 1
    for i, p in ipairs(e.cloud) do
        local k = i - 1
        local ang = e.yaw + 0x10000 // 5 * k
        local off = 2.0 * coss(0x800 * e.puff_t + 0x4000 * k) * s
        local sx, sy, sz = to_scene(x + 25.0 * s * sins(ang) + off, y + off + s * PUFF_UP[i], z + 25.0 * s * coss(ang) + off)
        sx, sy, sz = sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z
        local dx, dy, dz = cx - sx, cy - sy, cz - sz
        pcall(function()
            p.actor:K2_TeleportTo({ X = sx, Y = sy, Z = sz },
                { Pitch = -math.deg(atan(dz, sqrt(dx * dx + dy * dy))), Yaw = math.deg(atan(dy, dx)) + 180.0, Roll = 0.0 })
        end)
    end
end

local function cloud_gone(e)
    if e.cloud and not e.cloud_hidden then
        e.cloud_hidden = true
        for _, p in ipairs(e.cloud) do pcall(function() p.actor:SetActorHiddenInGame(true) end) end
    end
end

local function render(e, a)
    local pr = e.prev'''),
('''            elseif d2 < 9000.0 * 9000.0 then
                pcall(render, e, a)
            end''', '''            elseif d2 < 9000.0 * 9000.0 then
                pcall(render, e, a)
                if e.t.k == "lakitu" then
                    if e.action == "dying" then cloud_gone(e) else pcall(render_cloud, e, a, cx, cy, cz) end
                end
            end'''),
('''    for _, c in ipairs(M.cages) do
        local sx2, sy2, sz2 = to_scene(c.x, c.y, c.z)''', '''    for _, e in ipairs(M.list) do
        if e.cloud and (e.action == "gone" or e.broken) then cloud_gone(e) end
    end
    for _, c in ipairs(M.cages) do
        local sx2, sy2, sz2 = to_scene(c.x, c.y, c.z)'''),
])
print('ok')
