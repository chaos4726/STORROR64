-- SM64Map: bob-ombs, the pink bob-omb buddies and King Bob-omb (asked 2026-10-14: "also bombombs", "aswell as king
-- bombomb"; grabbing with STORROR's push: "for grabbing objects and enemies such as bombombs bowser and boxes use the
-- push control").
--
-- Mario 64's behaviours (src/game/behaviors/bobomb.inc.c, king_bobomb.inc.c), kept in its own terms as
-- platforms.lua and chomp.lua are: Mario 64 units, its 16-bit angles, one step per Mario 64 frame (30 a second),
-- drawn blended between steps.
--
-- A bob-omb patrols near where it stands; when it faces the player it lights its fuse and chases him, and five
-- seconds later it explodes (two wedges of power to anyone close). Pushing one (STORROR's push, on the ground)
-- picks it up and carries it, its fuse burning; pushing again throws it, and it explodes where it lands. A drop
-- kick (the push in the air) sends it flying, the same. Landing on one sets it off. Each leaves a coin the first
-- time, and comes back once the player has gone 3000 units away.
--
-- King Bob-omb waits on his summit until the player comes near, then the boss music starts and he stomps after
-- him. Touching him from the front, he grabs the athlete and throws him; pushed from behind, he is thrown instead
-- and lands hurt. Thrown off his summit he leaps back up. Three throws and he is beaten, and his star appears.
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET

local M = { list = {}, kinds = { bobomb = true, bobomb_buddy = true, king_bobomb = true } }
local S = 0.75
local STEP = 1 / 30
local H = {}

local sqrt, sin, cos, atan, floor, abs, pi, max, min = math.sqrt, math.sin, math.cos, math.atan, math.floor, math.abs, math.pi, math.max, math.min

function M.setup(h) H = h end

-- ------------------------------------------------------------ Mario 64's arithmetic
local function sins(a) return sin(a * pi / 32768.0) end
local function coss(a) return cos(a * pi / 32768.0) end
local function atan2s(y, x) return atan(x, y) * 32768.0 / pi end
local function s16(a) a = floor(a) % 65536; if a >= 32768 then a = a - 65536 end; return a end
local function turn_toward(cur, target, inc)
    local d = s16(target - cur)
    if d > inc then return s16(cur + inc), false end
    if d < -inc then return s16(cur - inc), false end
    return s16(target), true
end

local function to_scene(x, y, z) return -z * S, x * S, y * S end
-- (his words with Mario 64's CUTSCENE_DIALOG: game.lua G.dialog_cut - his hitbox 100 high, his scale 2)
local function king_talk_cut(b, G)
    if not (G and G.dialog_cut) then return end
    local x, y, z = to_scene(b.x, b.y, b.z)
    pcall(G.dialog_cut, x, y, z, 200.0 * S, 220.0)
end
local function floor_y(x, y, z)
    if not H.floor_z then return nil end
    local sx, sy = to_scene(x, 0, z)
    local fz = H.floor_z(sx, sy, (y + 250.0) * S)
    -- (and the moving platforms' tops - Bowser in the Sky's spinning ones, any: thrown onto one, it fell through to the
    -- level's floor under it - "threw a bombomb on a spinning platform and he went through it", 2026-11-02. Only one no
    -- more than 60 over it: a platform passing over its head is no floor)
    local PL = package.loaded["platforms"]
    if PL and PL.floor_under then
        local ok, pz = pcall(PL.floor_under, sx, sy, (y + 60.0) * S)
        if ok and pz and (not fz or pz > fz) then fz = pz end
    end
    return fz and fz / S or nil
end

local function sfx() return package.loaded["sfx"] end
local function sound(name, v)
    local SFX = sfx()
    if SFX and (v or 1.0) > 0.02 then pcall(SFX.play, name, v) end
end
local function loudness(o, m, reach)
    local dx, dy, dz = o.x - m.x, o.y - m.y, o.z - m.z
    local k = 1.0 - sqrt(dx * dx + dy * dy + dz * dz) / (reach or 5000.0)
    if k <= 0.0 then return 0.0 end
    return k ^ 1.5
end

-- ------------------------------------------------------------ the athlete
-- STORROR's push and drop kick are its attack montages (MontageAttack...): on the ground a push, in the air a kick
local function attack_of(pawn)
    local name, addr = nil, nil
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        if not (ai and ai:IsValid()) then return end
        local mt = ai:GetCurrentActiveMontage()
        if mt and mt:IsValid() then name, addr = mt:GetFName():ToString(), mt:GetAddress() end
    end)
    if not (name and (name:find("Attack") or name:lower():find("kick") or name:lower():find("push"))) then return nil end
    local air = false
    pcall(function() air = pawn.CharacterMovement:IsFalling() end)
    return { name = name, addr = addr, air = air }
end

-- ------------------------------------------------------------ explosions
local EXPLOSION_FRAMES = 7
local function explosion(world, x, y, z)
    local e = { x = x, y = y + 100.0, z = z, t = 0, quads = {} }
    local sx, sy, sz = to_scene(e.x, e.y, e.z)
    for i = 0, EXPLOSION_FRAMES - 1 do
        local q = lib.quad_actor(world, { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z }, 160.0,
            "actors__explosion__explosion_" .. i .. ".rgba16", "translucent")
        if q then pcall(function() q:SetActorHiddenInGame(i ~= 0) end) end
        e.quads[i] = q
    end
    M.booms[#M.booms + 1] = e
    return e
end
M.booms = {}

local function update_booms(cx, cy)
    for i = #M.booms, 1, -1 do
        local e = M.booms[i]
        e.t = e.t + 1
        local frame = floor(e.t / 2)
        local sx, sy = to_scene(e.x, e.y, e.z)
        local yaw = math.deg(atan(cy - (sy + OFFSET.Y), cx - (sx + OFFSET.X)))
        for j = 0, EXPLOSION_FRAMES - 1 do
            local q = e.quads[j]
            if q then
                pcall(function()
                    q:SetActorHiddenInGame(j ~= frame)
                    if j == frame then q:K2_SetActorRotation({ Pitch = 0.0, Yaw = yaw + 180.0, Roll = 0.0 }, false) end
                end)
            end
        end
        if frame >= EXPLOSION_FRAMES then
            for j = 0, EXPLOSION_FRAMES - 1 do if e.quads[j] then lib.destroy(e.quads[j]) end end
            table.remove(M.booms, i)
        end
    end
end

-- the blast: two wedges to the athlete if he is within it, thrown away from it
local BLAST = 260.0
local CHAIN = 300.0         -- (a bob-omb this close to an explosion goes off too: collide, below)
-- (halved: since ragdoll.lua gives his body the push in full it threw him across the level - "bomb omb chainchomp and
-- big balls do significantly more knockback then usual", 2026-10-30; it was 1800, 1400)
local BLAST_OUT, BLAST_UP = 550.0, 450.0     -- (was 900, 700: "why is everything in the game doing so much knockback?", 2026-10-31)
--       -- cm/s he is thrown at, away from it and up
-- Enemies and goombas within `reach` of (x, y, z), Mario units, beaten - as a thrown box beats them (enemies.lua
-- M.hit_at, game.lua G.goomba_hit_at). How many. A thrown bob-omb goes off on the first it meets (Mario 64's
-- INT_STATUS_TOUCHED_BOB_OMB) and its blast takes out every one in it: "bomombs dont kill other enemies when thrown at
-- them", 2026-10-23 - its blast reached only him and a Pokey.
local function hit_enemies(x, y, z, reach, yaw, m)
    local n = 0
    local EN = package.loaded["enemies"]
    if EN and EN.hit_at then
        local ok, k = pcall(EN.hit_at, x, y, z, reach, yaw, m)
        if ok and k then n = n + k end
    end
    local G = package.loaded["game"]
    if G and G.goomba_hit_at then
        local sx, sy, sz = to_scene(x, y, z)
        local ok, k = pcall(G.goomba_hit_at, sx, sy, sz, reach * 0.75 + 30.0)
        if ok and k then n = n + k end
    end
    return n
end
local function blast(o, m, pawn)
    hit_enemies(o.x, o.y + 60.0, o.z, BLAST, o.yaw, m)
    -- (the chain chomp, if it is close: up into the air)
    local CH = package.loaded["chomp"]
    if CH and CH.blast_at then pcall(CH.blast_at, o.x, o.y + 60.0, o.z) end
    -- (and a Pokey in it, blown apart: enemies.lua M.blast_at)
    local EN = package.loaded["enemies"]
    if EN and EN.blast_at then pcall(EN.blast_at, o.x, o.y + 60.0, o.z, BLAST) end
    local dx, dy, dz = m.x - o.x, m.y - (o.y + 60.0), m.z - o.z
    if dx * dx + dy * dy + dz * dz > BLAST * BLAST then return end
    local HP = _G.HEALTH
    if HP and (HP.grace > 0 or HP.dead_t) then return end
    -- (no harm from a blast under the vanish cap: Mario 64's take_damage_and_knock_back - "when invis capped enemies should not be able to ragdol the player", 2026-10-26)
    do local C = package.loaded["caps"]; if C and C.on and C.on("vanish") then return end end
    if HP then HP.damage(HP.DAMAGE and HP.DAMAGE.bobomb or 2, "a bob-omb") end
    local d = sqrt(dx * dx + dz * dz)
    if d < 1.0 then dx, dz, d = 1.0, 0.0, 1.0 end
    -- (thrown hard, all of him at once: "if you get expoded by them make it launch the charater harder" - it was 900
    -- out and 700 up on his hips alone)
    if H.knock_down then pcall(H.knock_down, pawn, -dz / d * BLAST_OUT, dx / d * BLAST_OUT, BLAST_UP, true) end
end

-- ------------------------------------------------------------ adding them
local function instance(world, name, x, y, z, yaw, scale)
    local data = H.actor_data and H.actor_data(name)
    if not data then return nil end
    local sx, sy, sz = to_scene(x, y, z)
    return lib.make_instance(world, data, { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z }, -yaw * 360.0 / 65536.0, scale or 1.0)
end

function M.add(world, o)
    if not o.sm64 then return end
    local x, y, z = o.sm64[1], o.sm64[2], o.sm64[3]
    local fy = floor_y(x, y, z)
    if fy then y = fy end
    local yaw = s16(-(o.yaw or 0.0) * 65536.0 / 360.0)
    local kind = o.kind
    local name = (kind == "bobomb") and "bobomb" or ((kind == "bobomb_buddy") and "bobomb_buddy" or "king_bobomb")
    local inst = instance(world, name, x, y, z, yaw)
    if not inst then log("%s: no model", kind); return end
    local b = { kind = kind, o = o, inst = inst, x = x, y = y, z = z, hx = x, hy = y, hz = z, yaw = yaw,
                fvel = 0.0, vy = 0.0, timer = 0, f = math.random(0, 20), action = "patrol", ground = true,
                stationary = o.stationary, fuse = false, fuse_t = 0, coin_given = false, health = 3, sub = 0 }
    if kind == "king_bobomb" then b.action, b.star = "wait", o.star or 0 end
    if kind == "bobomb_buddy" then b.action = "idle" end
    b.prev = { x, y, z }
    M.list[#M.list + 1] = b
end

function M.clear()
    if M.release_held then pcall(M.release_held) end         -- (held by the King as the scene goes: let go)
    for _, b in ipairs(M.list) do if b.inst then lib.destroy(b.inst.actor) end end
    for _, e in ipairs(M.booms) do for j = 0, EXPLOSION_FRAMES - 1 do if e.quads[j] then lib.destroy(e.quads[j]) end end end
    if M.boss_music then M.end_boss_music() end
    M.list, M.booms, M.held = {}, {}, nil
end

function M.forget()
    local G = package.loaded["game"]
    if G and G.carried == "king" then G.carried = nil end
    M.list, M.booms, M.held, M.boss_music = {}, {}, nil, nil
end

-- ------------------------------------------------------------ moving
-- along its move yaw, falling, landing on the floor (object_step); returns true if it landed this step. A walker
-- (`careful`) stops at a ledge instead of walking off it, as Mario 64's do (cur_obj_move_standard's edge check).
local BODY = 50.0           -- (its body, Mario units: for walls, other bob-ombs and him)
local function move(b, gravity, terminal, careful)
    b.edge = false
    local nx, nz = b.x + b.fvel * sins(b.yaw), b.z + b.fvel * coss(b.yaw)
    -- (the level's walls - fences too - stop it, out of them; a walker turns away: "give them collision as well")
    b.walled = false
    if H.wall_near and b.fvel ~= 0.0 then
        local sx, sy, sz = to_scene(nx, b.y, nz)
        local hit, px, py = H.wall_near(sx, sy, sz + 30.0, BODY * S)
        if hit then nx, nz, b.walled = nx + py / S, nz - px / S, true end
    end
    if careful and b.ground and b.fvel ~= 0.0 then
        local ahead = floor_y(nx + 60.0 * sins(b.yaw), b.y, nz + 60.0 * coss(b.yaw))
        if not ahead or ahead < b.y - 100.0 then
            nx, nz = b.x, b.z
            b.edge = true
        end
    end
    b.vy = b.vy - gravity
    if b.vy < -(terminal or 75.0) then b.vy = -(terminal or 75.0) end
    local ny = b.y + b.vy
    local fy = floor_y(nx, max(ny, b.y), nz)
    local fy0 = fy
    if fy and fy > b.y + 120.0 and b.ground then
        -- a wall or a step too high: it stays, and a walker turns away
        nx, nz, fy = b.x, b.z, floor_y(b.x, max(ny, b.y), b.z)
        b.blocked = true
    else
        b.blocked = false
    end
    b.x, b.z = nx, nz
    local landed = false
    if fy and ny <= fy then
        ny = fy
        if not b.ground then landed = true end
        b.vy = 0.0
        b.ground = true
    else
        b.ground = false
    end
    b.y = ny
    b.edge = b.edge or (fy0 == nil)
    return landed
end

-- ------------------------------------------------------------ bob-ombs
local function bobomb_respawn(b)
    b.x, b.y, b.z = b.hx, b.hy, b.hz
    b.action, b.fuse, b.fuse_t, b.timer, b.fvel, b.vy = "patrol", false, 0, 0, 0.0, 0.0
    pcall(function() b.inst.actor:SetActorHiddenInGame(false) end)
    pcall(function() b.inst.actor:SetActorScale3D({ X = 1.0, Y = 1.0, Z = 1.0 }) end)
end

local function bobomb_explode_now(b, m, pawn)
    b.action, b.timer = "explode", 0
    if M.held == b then M.held = nil end
end

local function step_bobomb(b, m, pawn, world)
    b.timer = b.timer + 1
    local act = b.action
    if act == "gone" then
        local dx, dz = m.x - b.hx, m.z - b.hz
        if dx * dx + dz * dz > 3000.0 * 3000.0 then bobomb_respawn(b) end
        return
    end
    if act == "patrol" then
        if not b.stationary then
            b.fvel = 5.0
            local hx, hz = b.hx - b.x, b.hz - b.z
            if hx * hx + hz * hz > 400.0 * 400.0 or b.blocked or b.edge or b.walled then
                b.yaw = turn_toward(b.yaw, atan2s(hz, hx), 0x400)
            elseif b.timer % 90 == 0 then
                b.want = s16(b.yaw + math.random(-0x3000, 0x3000))
            end
            if b.want then b.yaw = turn_toward(b.yaw, b.want, 0x200) end
            if b.edge then b.want = s16(b.yaw + 0x8000) end
            -- it sees the player: lights its fuse and gives chase - on its own level only (Mario 64's 400 units from its
            -- home counts the height too): seen from a ledge far over him, it lit and ran off after him - "bombombs
            -- trigger when your way underneith them", 2026-10-25
            if abs(s16(m.angle - b.yaw)) < 0x2000 and m.dist < 2000.0 and abs(m.feet - b.y) < 400.0 then
                b.fuse, b.action, b.timer = true, "chase", 0
            end
        else
            b.fvel = 0.0
        end
        move(b, 2.5, 75.0, true)
        b.f = b.f + 1.0
    elseif act == "chase" then
        b.fvel = 20.0
        b.yaw = turn_toward(b.yaw, m.angle, 0x800)
        move(b, 2.5, 75.0, true)
        b.f = b.f + 1.0
        local fi = floor(b.f) % 25
        if fi == 5 or fi == 16 then sound("bobomb_walk", loudness(b, m, 3000.0)) end
    elseif act == "launched" then
        if move(b, 2.5) or (b.ground and b.timer > 2) or (b.timer > 1 and hit_enemies(b.x, b.y + 50.0, b.z, 40.0, b.yaw, m) > 0) then
            bobomb_explode_now(b, m, pawn)
        end
    elseif act == "held" then
        -- in the athlete's hands: in front of him, at his chest
        local fx, fz = sins(m.facing), coss(m.facing)
        b.x, b.y, b.z = m.x + fx * 110.0, m.y + 40.0, m.z + fz * 110.0
        b.yaw, b.ground = m.facing, false
    elseif act == "explode" then
        local k = 1.0 + b.timer / 5.0
        pcall(function() b.inst.actor:SetActorScale3D({ X = k, Y = k, Z = k }) end)
        if b.timer >= 5 then
            sound("explosion", loudness(b, m, 8000.0))
            explosion(world, b.x, b.y, b.z)
            blast(b, m, pawn)
            -- (and any bob-omb in its blast goes off too, a moment later: one sets off the next)
            for _, o in ipairs(M.list) do
                if o ~= b and o.kind == "bobomb" and o.action ~= "explode" and o.action ~= "gone" then
                    local dx, dy, dz = o.x - b.x, o.y - b.y, o.z - b.z
                    if dx * dx + dy * dy + dz * dz < CHAIN * CHAIN then
                        if M.held == o then M.held = nil end
                        o.action, o.timer = "explode", 0
                    end
                end
            end
            -- (its coin: again after it comes back only if he did not pick it up - game.lua drop_loot)
            local G = package.loaded["game"]
            if G and G.drop_loot then
                local sx, sy, sz = to_scene(b.x, b.y, b.z)
                pcall(G.drop_loot, b, 1, sx, sy, sz + 40.0)
            elseif not b.coin_given and H.spawn_coin then
                b.coin_given = true
                local sx, sy, sz = to_scene(b.x, b.y, b.z)
                pcall(H.spawn_coin, sx, sy, sz + 40.0)
            end
            b.action, b.fuse = "gone", false
            pcall(function() b.inst.actor:SetActorHiddenInGame(true) end)
        end
    end
    if b.fuse and b.action ~= "explode" and b.action ~= "gone" then
        b.fuse_t = b.fuse_t + 1
        if b.fuse_t > 150 then bobomb_explode_now(b, m, pawn) end
    end
end

-- the athlete and a bob-omb: grabbed by a push, kicked away by a drop kick, set off by a landing on top
local function touch_bobomb(b, m, pawn, attack, new_attack)
    do local G = package.loaded["game"]; if G and G.cutscene then return end end   -- (the ending: creatures take no notice of him)
    if b.action == "gone" or b.action == "explode" or b.action == "launched" then return end
    if b.action == "held" then
        if new_attack then
            -- thrown, the way he faces
            b.action, b.timer = "launched", 0
            b.yaw, b.fvel, b.vy, b.fuse = m.facing, 25.0 * 1.6, 20.0 * 1.5, true
            b.ground = false
            M.held = nil
            log("bob-omb thrown")
        end
        return
    end
    local dx, dy, dz = m.x - b.x, m.y - (b.y + 80.0), m.z - b.z
    local d2 = dx * dx + dz * dz
    if new_attack and d2 < 220.0 * 220.0 and abs(dy) < 250.0 then
        if attack.air then
            b.action, b.timer = "launched", 0
            b.yaw, b.fvel, b.vy, b.fuse = m.facing, 40.0, 30.0, true
            b.ground = false
            log("bob-omb kicked")
        elseif not M.held then
            b.action, b.fuse, b.timer = "held", true, 0
            M.held = b
            log("bob-omb picked up")
        end
        return
    end
    -- landed on from above
    if m.falling and d2 < 120.0 * 120.0 and m.feet > b.y + 60.0 and m.feet < b.y + 200.0 then
        bobomb_explode_now(b, m, pawn)
    end
end

-- Solid (2026-10-16, "give them collision as well", as the goombas): two walking bob-ombs closer than their two bodies
-- are put apart, half each, not into a wall; and one he is inside, on the ground, pushes him out to its edge (slid by
-- the engine along what he meets) - or, knocked flat, his body's parts it walks into are pushed from its middle.
local BODY_PUSH = 2500.0    -- cm/s each second at its middle, on his body
-- Bob-ombs that collide explode (the user, 2026-10-17: "next when bombombs collide make them explode"): two touching,
-- one of them lit - chasing him, carried, or thrown - both go off (two still on patrol, fuses unlit, only bump apart,
-- or the level's bob-ombs would blow each other up on their own); and an explosion sets off any bob-omb within CHAIN.
local function lit(b)
    return b.kind == "bobomb" and b.action ~= "explode" and b.action ~= "gone"
        and (b.fuse or b.action == "launched" or b.action == "held")
end
local function live(b) return b.kind == "bobomb" and b.action ~= "explode" and b.action ~= "gone" end
local function collide()
    local list = M.list
    for i = 1, #list do
        local a = list[i]
        if live(a) then
            for j = i + 1, #list do
                local b = list[j]
                if live(b) and (lit(a) or lit(b)) then
                    local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
                    -- (a thrown one reaches a little further: it is moving fast)
                    local r = 2.0 * BODY + ((a.action == "launched" or b.action == "launched") and 40.0 or 0.0)
                    if dx * dx + dz * dz < r * r and abs(dy) < 120.0 then
                        for _, o in ipairs({ a, b }) do
                            if M.held == o then M.held = nil end
                            o.action, o.timer = "explode", 0
                        end
                        log("bob-ombs collided - both explode")
                    end
                end
            end
        end
    end
end
local function walking(b) return b.kind == "bobomb" and (b.action == "patrol" or b.action == "chase") end
local function apart()
    local list = M.list
    for i = 1, #list do
        local a = list[i]
        if walking(a) then
            for j = i + 1, #list do
                local b = list[j]
                if walking(b) and abs(a.y - b.y) < 150.0 then
                    local dx, dz = b.x - a.x, b.z - a.z
                    local d = sqrt(dx * dx + dz * dz)
                    if d < 2.0 * BODY then
                        if d < 1.0 then dx, dz, d = sins(a.yaw), coss(a.yaw), 1.0 end
                        local half = (2.0 * BODY - d) / 2.0
                        local ux, uz = dx / d, dz / d
                        for _, q in ipairs({ { a, -half }, { b, half } }) do
                            local o, k = q[1], q[2]
                            local nx, nz = o.x + ux * k, o.z + uz * k
                            local sx, sy, sz = to_scene(nx, o.y, nz)
                            if not (H.wall_near and H.wall_near(sx, sy, sz + 30.0, BODY * S)) then o.x, o.z = nx, nz end
                        end
                    end
                end
            end
        end
    end
end
local function push_him(b, m, pawn)
    if not walking(b) then return end
    local G = package.loaded["game"]
    if G and (G.dying or G.cutscene or (G.intangible and G.intangible())) then return end
    local R = package.loaded["ragdoll"]
    local sx, sy, sz = to_scene(b.x, b.y, b.z)
    if R and R.active then
        pcall(function()
            local mesh = pawn.Mesh
            local pl = mesh:GetSocketLocation(FName("pelvis"))
            local reach = BODY * S + 60.0
            local hx, hy = pl.X - OFFSET.X - sx, pl.Y - OFFSET.Y - sy
            if hx * hx + hy * hy < (reach + 80.0) ^ 2 and abs(pl.Z - OFFSET.Z - sz) < 150.0 then
                mesh:AddRadialImpulse({ X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + 40.0 + OFFSET.Z }, reach, BODY_PUSH * STEP, 1, true)
            end
        end)
        return
    end
    if not (G and G.grounded) then return end
    local dx, dz = m.x - b.x, m.z - b.z
    local d = sqrt(dx * dx + dz * dz)
    local r = BODY + 37.0
    if d >= r or m.feet > b.y + 113.0 or m.feet + 240.0 < b.y then return end
    if d < 1.0 then dx, dz, d = sins(b.yaw), coss(b.yaw), 1.0 end
    local out = (r - d + 1.0) * S
    local ux, uz = dx / d, dz / d
    pcall(function()
        local l = pawn:K2_GetActorLocation()
        pawn:K2_SetActorLocation({ X = l.X - uz * out, Y = l.Y + ux * out, Z = l.Z }, true, {}, false)
    end)
end

-- ------------------------------------------------------------ the buddies
local function step_buddy(b, m, pawn, world, attack, fresh)
    b.f = b.f + 1.0
    if m.dist < 700.0 then b.yaw = turn_toward(b.yaw, m.angle, 0x140) end
    -- a buddy that opens cannons: pushed (Mario talks to him), the level's cannons open
    if b.o.opens and fresh and attack and not attack.air and m.dist < 300.0 then
        local PL = package.loaded["platforms"]
        if PL and PL.open_cannons and PL.open_cannons() then log("a Bob-omb Buddy opened the cannons") end
    end
end

-- ------------------------------------------------------------ King Bob-omb
-- (his animations: 0 grab, 1 holding, 2 hit, 4 stomp, 5 idle, 7 landing, 8 jump, 9 throw, 10 getting up, 11 walk)
-- ------------------------------------------------------------ held by King Bob-omb
-- (king_bobomb_act_3 with Mario's act_grabbed - "next lets add king bombombs pickup spin and throw of the player",
-- 2026-10-16; the athlete was only ever knocked flat at the throw): picked up and held at the King's hands, his controls
-- off and nothing hurting him, in STORROR's dead hang as Hoot carries him; carried along, turned with the King, and
-- thrown - or dropped, if he wriggles free.
local HELD_LOCK = "SM64King"
local HELD_ANIM = "/SPP/SPPCharacter/Animation/MotionMatching/Swing/MotionMatchingSwing_171_Swings_31_08_24-001_979-5438.MotionMatchingSwing_171_Swings_31_08_24-001_979-5438"
local KING_HANDS = { 34, 44 }           -- (his two hands: parts p33 and p43, the ends of his arms - p9 and p20 are his feet)
-- (held in the King's hands, his chest between them: the hands' height and reach before the King, as posed, with
-- nothing to the side - over them, 1 m up and 0.9 m out, he floated far off them, and swung on with his hang: "the
-- grab and spin is very glitchy. you not actually staying in his hands and floating way outside", 2026-10-16. Out in
-- front of the King, he is swung right round in the spin.)
local HOLD_UP, HOLD_OUT = 141.0, 124.0  -- cm: the hands over the King's feet and before him as he carries him (no hands)
local HOLD_IN = 75.0                    -- cm: never nearer the King's middle than this (in him)
local HOLD_GRIP = 15.0                  -- cm: the athlete's middle under the hands
local HOLD_LIFT = 10                    -- steps: from where he stood into the hands
-- (flown there, as Hoot carries him: STORROR's body is simulated, and set there each frame - teleported - it trailed
-- half a metre and more behind him in the spin, and further moved there without the teleport; flown, it keeps up.
-- Teleported only when he is held up on something, more than this far off)
local HOLD_SNAP = 150.0
local hold_dt = 1.0 / 60.0
-- (thrown: common_anchor_mario_behavior's 50 a frame on and 50 up - in Mario 64's gravity, 4 a frame, a throw some 9 m
-- out and 2.3 m up; given in this world's gravity for the same arc)
local THROW_OUT, THROW_UP = 700.0, 680.0
-- (the King lifted by the athlete: up over his raised hands in 12 frames, held 10, thrown; his feet this far over the
-- athlete's and ahead of him, Mario units)
local LIFT_STEPS, LIFT_HOLD = 12, 10
local LIFT_UP, LIFT_AHEAD = 250.0, 40.0
local function held_lock(h, pawn, on)
    local pc = lib.controller()
    pcall(function() pc:SetIgnoreMoveInput(on) end)
    pcall(function() if on then pawn:DisableInput(pc) else pawn:EnableInput(pc) end end)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            local cname = o:GetClass():GetFName():ToString()
            if cname == "LocomotionComponent" then
                o:EnableLocomotionInputCallback(FName(HELD_LOCK), not on)
                o:EnableAdvancedLocomotionInput(FName(HELD_LOCK), not on)
            elseif cname == "ParkourComponent" then
                o:ClearInputQueue()
                o:EnableAllParkourInputs(FName(HELD_LOCK), not on)
            end
        end
    end)
    local cm = pawn.CharacterMovement
    if on then
        pcall(function()
            local anim = pawn.Mesh:GetAnimInstance()
            h.pa, h.rm = anim, anim.RootMotionMode
            anim:SetRootMotionMode(1)
            local seq = lib.try_load(HELD_ANIM)
            if seq then h.hang = anim:PlaySlotAnimationAsDynamicMontage(seq, FName("FullBody"), 0.15, 0.2, 1.0, 100000, -1.0, 0.0) end
            if h.hang and h.hang:IsValid() then anim:Montage_SetPlayRate(h.hang, 0.0) end     -- (held still: no swing)
        end)
        pcall(function() cm:SetMovementMode(5, 0); cm:StopMovementImmediately() end)
        -- (flown into the hands by velocity: STORROR flies no faster than 600 cm/s, and the King's spin wants more - he fell
        -- up to a metre behind the hands and snapped back, 2026-10-16 "king bombombs grab is still buggy")
        pcall(function()
            h.max_fly, h.brake_fly = cm.MaxFlySpeed, cm.BrakingDecelerationFlying
            cm.MaxFlySpeed, cm.BrakingDecelerationFlying = 20000.0, 0.0
        end)
    else
        pcall(function()
            if h.pa and h.pa:IsValid() then
                if h.hang and h.hang:IsValid() then h.pa:Montage_Stop(0.2, h.hang) end
                h.pa:SetRootMotionMode(h.rm or 2)
            end
        end)
        pcall(function() cm:SetMovementMode(3, 0) end)
        pcall(function()
            if h.max_fly then cm.MaxFlySpeed = h.max_fly end
            if h.brake_fly then cm.BrakingDecelerationFlying = h.brake_fly end
        end)
    end
end
local function king_hold(b, pawn)
    if b.held or not pawn then return end
    b.held = { esc = 0, flick = false }
    pcall(function() local l = pawn:K2_GetActorLocation(); b.held.from = { l.X, l.Y, l.Z } end)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetClass():GetFName():ToString() == "HumanPhysicsComponent" then b.held.hp = o end
        end
    end)
    held_lock(b.held, pawn, true)
    local G = package.loaded["game"]
    if G then G.carried = "king" end
    if b.kind == "king_bobomb" then log("King Bob-omb picked the athlete up") end
end
-- how: "throw" (thrown the way he faces, all of him), "drop" (let go: 10 a frame on and up), or nil (just let go)
local function king_release(b, pawn, how)
    local h = b.held
    if not h then return end
    b.held = nil
    local G = package.loaded["game"]
    if G and G.carried == "king" then G.carried = nil end
    if not pawn then return end
    held_lock(h, pawn, false)
    local fx, fz = sins(b.yaw), coss(b.yaw)
    if how == "throw" then
        if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
        local tout, tup = b.throw_out or THROW_OUT, b.throw_up or THROW_UP
        if H.knock_down then pcall(H.knock_down, pawn, -fz * tout, fx * tout, tup, true) end
        if b.kind == "king_bobomb" then log("King Bob-omb threw the athlete") end
    elseif how == "drop" then
        pcall(function() pawn:LaunchCharacter({ X = -fz * 225.0, Y = fx * 225.0, Z = 225.0 }, true, true) end)
        if b.kind == "king_bobomb" then log("the athlete wriggled free of King Bob-omb") end
    end
end
function M.release_held()
    for _, b in ipairs(M.list) do
        if b.held then king_release(b, lib.pawn(), nil) end
        if b.lift_h then
            local pawn = lib.pawn()
            if pawn then held_lock(b.lift_h, pawn, false) end
            b.lift_h = nil
        end
    end
end
-- (player_performed_grab_escape_action: a push of the stick out from the middle, or A)
local function wriggled(h)
    local P = package.loaded["pad"]
    if not P then return false end
    local x, y = 0.0, 0.0
    pcall(function() x, y = P.sticks() end)
    if P.down("up") or P.down("down") or P.down("left") or P.down("right") then x = 1.0 end
    local mag = math.sqrt(x * x + y * y)
    local hit = false
    if mag < 0.47 then h.flick = false end
    if not h.flick and mag > 0.62 then h.flick, hit = true, true end
    if P.pressed("ok") then hit = true end
    return hit
end
-- (each frame, after his pose: the athlete in the King's hands, turned as he is - Mario 64's act_grabbed faces Mario
-- the King's way - and lifted into them from where he stood; (sx, sy, sz): the King's feet, scene cm, and yaw his
-- facing, as drawn; a: how far on to the next step)
local function place_held(b, pawn, sx, sy, sz, yaw, a)
    local h = b.held
    if not (h and pawn) then return end
    local face = 180.0 - yaw * 360.0 / 65536.0
    local fa = math.rad(face)
    local cx, cy = math.cos(fa), math.sin(fa)
    local fx, fy, fz = sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z
    local out, side, up = b.hold_out or HOLD_OUT, 0.0, b.hold_up or HOLD_UP
    local comps = b.inst.comps or {}
    local n, hx, hy, hz = 0, 0.0, 0.0, 0.0
    for _, i in ipairs(b.hands or KING_HANDS) do
        local c = comps[i]
        if c then
            local ok, l = pcall(function() return c:K2_GetComponentLocation() end)
            if ok and l then n, hx, hy, hz = n + 1, hx + l.X, hy + l.Y, hz + l.Z end
        end
    end
    if n > 0 then
        hx, hy, hz = hx / n - fx, hy / n - fy, hz / n - fz
        out, side, up = hx * cx + hy * cy, -hx * cy + hy * cx, hz
    end
    out = math.max(out, HOLD_IN)
    local tx, ty, tz = fx + cx * out - cy * side, fy + cy * out + cx * side, fz + up - HOLD_GRIP
    if b.sub == 0 and h.from then
        local k = math.max(0.0, math.min(1.0, ((b.hold_t or b.timer) - 1 + a) / HOLD_LIFT))
        k = k * k * (3.0 - 2.0 * k)
        tx, ty, tz = h.from[1] + (tx - h.from[1]) * k, h.from[2] + (ty - h.from[2]) * k, h.from[3] + (tz - h.from[3]) * k
    end
    h.at = { tx - OFFSET.X, ty - OFFSET.Y, tz - OFFSET.Z, out, side, up }
    pcall(function()
        local cm = pawn.CharacterMovement
        local l = pawn:K2_GetActorLocation()
        local ex, ey, ez = tx - l.X, ty - l.Y, tz - l.Z
        local pv = h.prev_t
        if not pv or ex * ex + ey * ey + ez * ez > HOLD_SNAP * HOLD_SNAP then
            pawn:K2_SetActorLocation({ X = tx, Y = ty, Z = tz }, false, {}, true)
            cm.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
        else
            -- (to his place, and on as it goes: scene cm a second)
            local kk = 1.0 / hold_dt
            if cm.MovementMode ~= 5 then cm:SetMovementMode(5, 0) end
            cm.Velocity = { X = ex * kk * 0.7 + (tx - pv[1]) * kk, Y = ey * kk * 0.7 + (ty - pv[2]) * kk,
                            Z = ez * kk * 0.7 + (tz - pv[3]) * kk }
        end
        pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = face, Roll = 0.0 }, true)
    end)
    h.prev_t = { tx, ty, tz }
    -- (the hanging pose kept: turned in the King's hands, STORROR set off its turn-on-the-spot montage over it - his legs
    -- stepping in mid-air - and once that ended no montage was left)
    if h.pa and h.pa:IsValid() then
        pcall(function()
            local cur = h.pa:GetCurrentActiveMontage()
            local mine = h.hang and h.hang:IsValid()
            if cur and cur:IsValid() and not (mine and cur:GetAddress() == h.hang:GetAddress()) then h.pa:Montage_Stop(0.0, cur) end
            if not (mine and h.pa:Montage_IsPlaying(h.hang)) then
                local seq = lib.try_load(HELD_ANIM)
                if seq then h.hang = h.pa:PlaySlotAnimationAsDynamicMontage(seq, FName("FullBody"), 0.1, 0.2, 1.0, 100000, -1.0, 0.0) end
                if h.hang and h.hang:IsValid() then h.pa:Montage_SetPlayRate(h.hang, 0.0) end
            end
        end)
    end
    -- (and his simulated body put back on his pose: in the spin it swung out and trailed behind him)
    if h.hp and h.hp:IsValid() then pcall(function() h.hp:ResetBodyModifiersInSetToCachedBoneTransforms(FName("All"), 1) end) end
end

local function king_anim(b, i, from)
    if b.anim ~= i then b.anim, b.f = i, from or 0 end
end

-- The same hold for others that grab him (Chuckya, enemies.lua): grab(b, pawn), release(b, pawn, "throw"|"drop"|nil),
-- place(b, pawn, sx, sy, sz, yaw, a) every frame (b.hands, b.hold_out, b.hold_up, b.throw_out, b.throw_up its own), the
-- escape pushes (wriggled(b.held)), and the frame time the flying uses (set_dt)
M.hold = { grab = function(b, pawn) return king_hold(b, pawn) end, release = function(b, pawn, how) return king_release(b, pawn, how) end,
           place = function(...) return place_held(...) end, wriggled = function(h) return wriggled(h) end,
           set_dt = function(dt) hold_dt = math.max(dt, 1.0 / 240.0) end }

function M.start_boss_music()
    local MUSIC = package.loaded["music"]
    if MUSIC and MUSIC.play and not M.boss_music then pcall(MUSIC.play, "event_boss"); M.boss_music = true end
end
function M.end_boss_music()
    local MUSIC = package.loaded["music"]
    if MUSIC and MUSIC.play and M.boss_music then
        pcall(MUSIC.play, (_G.SM64 and _G.SM64.data and _G.SM64.data.music) or nil)
    end
    M.boss_music = nil
end

local function king_frames(b)
    local data = b.inst.data
    local a = data.anims and data.anims[(b.anim or 5) + 1]
    return a and a.frames or 30
end

-- (quicker than Mario 64's in his fight - his walk, his lift and his throw half as fast again, his chase three times
-- Mario 64's 3 a frame and his turn three times its 0x100: the athlete runs rings round Mario's King - "also he seems
-- slow ?", 2026-10-16)
local KING_PACE = 1.5
-- (frame n of his animation passed this step - a quicker pace steps over some frames)
local function passed(b, n, frames)
    local a, c = b.pf % frames, b.f % frames
    if c >= a then return a < n and c >= n end
    return a < n or c >= n
end
-- Holding the King over his head (Mario 64's ACT_HOLD_HEAVY_IDLE / ACT_HOLD_HEAVY_WALKING): once he is up, STORROR's
-- own walking is given back - its parkour moves kept off (no vaults, jumps or attacks with him overhead) - and he goes
-- where the athlete goes; standing still, the athlete's arms are up under him (the frozen hold pose), walking, STORROR's
-- own walk. A new press of B, X, Y, A, a trigger, the mouse's left button, F or the space bar throws (ACT_HEAVY_THROW). True on the
-- throw. (h: the athlete's lock while he lifts, b.lift_h. "you cant move while picking him up", 2026-10-16.)
-- (Y and A too, and the space bar: "tie it to Y and A as well please", 2026-10-16)
local THROW_KEYS = { "Gamepad_FaceButton_Right", "Gamepad_FaceButton_Left", "Gamepad_FaceButton_Top", "Gamepad_FaceButton_Bottom",
                     "Gamepad_RightTrigger", "Gamepad_LeftTrigger", "LeftMouseButton", "F", "SpaceBar" }
local function carry_on(h, pawn)
    h.carry = true
    local pc = lib.controller()
    pcall(function() pc:SetIgnoreMoveInput(false) end)
    pcall(function() pawn:EnableInput(pc) end)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetClass():GetFName():ToString() == "LocomotionComponent" then
                o:EnableLocomotionInputCallback(FName(HELD_LOCK), true)
                o:EnableAdvancedLocomotionInput(FName(HELD_LOCK), true)
            end
        end
    end)
    local cm = pawn.CharacterMovement
    pcall(function()
        if h.pa and h.pa:IsValid() then h.pa:SetRootMotionMode(h.rm or 2) end     -- (STORROR walks by root motion)
        if h.max_fly then cm.MaxFlySpeed = h.max_fly end
        if h.brake_fly then cm.BrakingDecelerationFlying = h.brake_fly end
        cm:SetMovementMode(3, 0)                                                     -- (down onto his feet)
    end)
end
local function lift_controls(h, pawn)
    local pc = lib.controller()
    if not pc then return false end
    if not h.carry then carry_on(h, pawn) end
    local down = false
    for _, k in ipairs(THROW_KEYS) do
        local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(k) }) end)
        if ok and v == true then down = true end
    end
    -- (a press begun while he holds him: not the one that picked him up)
    local throw = down and h.armed
    if not down then h.armed = true end
    -- (arms up under him while he stands; his own walk while he walks)
    if h.pa and h.pa:IsValid() then
        pcall(function()
            local v = pawn:GetVelocity()
            local still = v.X * v.X + v.Y * v.Y < 40.0 * 40.0
            local mine = h.hang and h.hang:IsValid() and h.pa:Montage_IsPlaying(h.hang)
            if still and not mine then
                local cur = h.pa:GetCurrentActiveMontage()
                if cur and cur:IsValid() then h.pa:Montage_Stop(0.1, cur) end
                local seq = lib.try_load(HELD_ANIM)
                if seq then h.hang = h.pa:PlaySlotAnimationAsDynamicMontage(seq, FName("FullBody"), 0.15, 0.15, 1.0, 100000, -1.0, 0.0) end
                if h.hang and h.hang:IsValid() then h.pa:Montage_SetPlayRate(h.hang, 0.0) end
            elseif not still and mine then
                h.pa:Montage_Stop(0.15, h.hang)
            end
        end)
    end
    return throw
end
-- (and the athlete lifting something else heavy as he lifts the King - enemies.lua's Chuckya: his lock on or off, and
-- each frame his walk with it overhead, true on the throw)
M.hold.lock = function(h, pawn, on) return held_lock(h, pawn, on) end
M.hold.carry = function(h, pawn) return lift_controls(h, pawn) end

local function step_king(b, m, pawn, world)
    b.timer = b.timer + 1
    b.pf = b.f
    -- (his chase's walk at the pace of its speed, 7.5 to Mario 64's 3 on a stride for 3 x 1.5: a little under the rest)
    b.f = b.f + ((b.action == "grab") and KING_PACE or (b.action == "fight") and 1.25 or 1.0)
    local frames = king_frames(b)
    local at_end = b.f >= frames - 1
    local act = b.action
    if act == "wait" then
        king_anim(b, 5)
        b.fvel, b.vy = 0.0, 0.0
        b.x, b.y, b.z, b.ground = b.hx, b.hy, b.hz, true         -- (waiting, he is at home: cur_obj_set_pos_to_home)
        -- (not in a cutscene: in the credits' shot of the mountain the athlete walked up to him, the fight began
        -- and its music cut the credits' tune, 2026-10-14)
        local G = package.loaded["game"]
        -- (cur_obj_can_mario_activate_textbox_2(500, 100): within 500 across, his feet from 160 under the King to 100
        -- over, on the ground and free to talk - not hanging off the summit's edge beside him, as he could: "make sure
        -- the player is on stage before starting the dialog with king bombomb", 2026-10-16)
        local lat = sqrt((m.x - b.x) ^ 2 + (m.z - b.z) ^ 2)
        local ready = m.walking and not (G and (G.carried or G.cutscene or G.swim))
        if lat < 500.0 and m.feet > b.y - 160.0 and m.feet < b.y + 100.0 and ready and b.timer > 15 then
            -- (king_bobomb_act_0: his challenge first, DIALOG_017, the level's tune turned down under it; the boss
            -- tune once it is read)
            b.action = "talk"
            local MUSIC = package.loaded["music"]
            if MUSIC and MUSIC.dip then pcall(MUSIC.dip, 120.0, 0.4) end
            log("King Bob-omb: his challenge")
            local function go()
                if MUSIC and MUSIC.dip then pcall(MUSIC.dip, 0.0) end
                b.action, b.timer, b.sub = "fight", 0, 0
                M.start_boss_music()
                sound("king_voice", 1.0)
                log("King Bob-omb: the fight begins")
            end
            king_talk_cut(b, G)
            if G and G.say then G.say(17, go) else go() end
        end
    elseif act == "talk" or act == "words" then
        king_anim(b, act == "talk" and 5 or 2)
        b.fvel, b.vy = 0.0, 0.0
        -- (DIALOG_FLAG_TURN_TO_MARIO: round to face him for his challenge, 0x800 a frame)
        if act == "talk" then b.yaw = turn_toward(b.yaw, m.angle, 0x800) end
    elseif act == "fight" then
        if b.sub == 0 then
            king_anim(b, 4)
            if passed(b, 15, frames) then sound("king_step", loudness(b, m)) end
            b.fvel = 0.0
            if at_end then b.sub = 1 end
        else
            king_anim(b, 11)
            if passed(b, 1, frames) or passed(b, 15, frames) then sound("king_step", loudness(b, m)) end
            if (b.wait or 0) > 0 then
                b.fvel, b.wait = 0.0, b.wait - 1
            else
                b.fvel = 7.5                -- (2.5 x Mario 64's 3 - 9 was a tad quick: "also his walking speead")
                b.yaw = turn_toward(b.yaw, m.angle, 0x240)       -- (a tad slower than 0x300: "slow his turn speed down by a tad")
            end
        end
        if b.y - b.hy < -100.0 and b.ground then b.action, b.timer, b.sub = "return", 0, 0 end
        if b.y - m.y > 1200.0 then
            b.action = "wait"
            M.end_boss_music()
        end
    elseif act == "grab" then
        -- he has the athlete (king_bobomb_act_3): picks him up over his head, carries him on a little and turns
        -- round to face one way (yaw 0, 0x400 a frame, after 20 frames), and throws him; wriggled free (more than 10
        -- pushes of the stick or A), he drops him
        if b.sub == 0 then
            b.fvel = 0.0
            king_anim(b, 0)
            if b.timer == 1 then sound("king_grab", 1.0); king_hold(b, pawn); b.spin_left = nil end
            if at_end then b.sub, b.timer, b.carry = 1, 0, 0; king_anim(b, 1, 0) end
        elseif b.sub == 1 then
            king_anim(b, 1)
            if b.held and wriggled(b.held) then b.held.esc = b.held.esc + 1 end
            if b.held and b.held.esc > 10 then
                king_release(b, pawn, "drop")
                b.action, b.timer, b.sub, b.wait = "fight", 0, 1, 35
            else
                b.fvel = 3.0
                b.carry = (b.carry or 0) + 1
                if b.carry > 8 then
                    -- (a spin with him held out: right round and on to the way he throws - Mario 64 only turns
                    -- him to face it, often hardly at all: "he doesnt spin you though?", 2026-10-16. Once round at
                    -- 0x800 a frame: twice at 0xC00 swung his body out of the King's hands - "glitchy", the same day)
                    b.fvel = 0.0
                    if not b.spin_left then b.spin_left = 0x10000 + ((0 - b.yaw) % 0x10000) end
                    local step = math.min(0x800, b.spin_left)
                    b.yaw, b.spin_left = s16(b.yaw + step), b.spin_left - step
                    if b.spin_left <= 0 then
                        b.spin_left = nil
                        b.sub, b.timer = 2, 0
                        king_anim(b, 9, 22)
                    end
                end
            end
        else
            b.fvel = 0.0
            king_anim(b, 9)
            if b.pf < 31 and b.f >= 31 and b.held then
                sound("king_throw", 1.0)
                king_release(b, pawn, "throw")
            end
            if at_end then
                if b.held then king_release(b, pawn, "drop") end
                b.action, b.timer, b.sub, b.wait = "fight", 0, 1, 35
            end
        end
    elseif act == "lifted" then
        -- (Mario 64: grabbed from behind, the King is picked up over Mario's head and thrown - ACT_PICKING_UP,
        -- ACT_HOLD_HEAVY_IDLE, ACT_HEAVY_THROW. The athlete hoists him up - arms raised, held as the King holds him - for
        -- a moment and throws him the way he faces. Before, a push from behind just sent him flying.)
        king_anim(b, 6)
        b.fvel, b.vy, b.ground = 0.0, 0.0, false
        local k = math.min(1.0, b.timer / LIFT_STEPS)
        k = k * k * (3.0 - 2.0 * k)
        local fx, fz = sins(m.facing), coss(m.facing)
        local tx, ty, tz = m.x + fx * LIFT_AHEAD, m.feet + LIFT_UP, m.z + fz * LIFT_AHEAD
        local f = b.lift_from or { b.x, b.y, b.z }
        b.x, b.y, b.z = f[1] + (tx - f[1]) * k, f[2] + (ty - f[2]) * k, f[3] + (tz - f[3]) * k
        b.yaw = turn_toward(b.yaw, m.facing, 0x1000)
        -- (held over his head till he throws him, as Mario holds him till B: it threw him by itself 0.7 s on - "when the
        -- player picks him up it automatically throws him", 2026-10-16)
        local throw = not pawn
        if pawn and b.timer >= LIFT_STEPS then throw = lift_controls(b.lift_h or {}, pawn) end
        if throw then
            if b.lift_h and pawn then held_lock(b.lift_h, pawn, false) end
            b.lift_h, b.lift_from = nil, nil
            b.action, b.timer = "thrown", 0
            b.yaw, b.fvel, b.vy, b.ground = m.facing, 20.0, 50.0, false
            sound("king_throw", 1.0)
            log("King Bob-omb thrown (%d left)", b.health - 1)
        end
        return
    elseif act == "thrown" then
        king_anim(b, 2)
        if b.ground and b.timer > 2 then
            b.fvel, b.vy = 0.0, 0.0
            if b.y - b.hy > -100.0 then
                b.health = b.health - 1
                sound("king_voice", 1.0)
                if b.health > 0 then
                    b.action, b.timer, b.sub, b.hits = "hurt", 0, 0, 0
                    sound("king_hurt", 1.0)
                else
                    b.action, b.timer = "beaten", 0
                end
            else
                b.action, b.timer, b.sub = "return", 0, 0
            end
        end
    elseif act == "hurt" then
        b.fvel = 0.0
        if b.sub == 0 then
            king_anim(b, 2)
            if at_end then b.hits = (b.hits or 0) + 1; b.f = 0 end
            if (b.hits or 0) > 3 then b.sub = 1; king_anim(b, 10) end
        elseif b.sub == 1 then
            king_anim(b, 10)
            if at_end then b.sub = 2 end
        else
            king_anim(b, 11)
            local yaw, there = turn_toward(b.yaw, m.angle, 0x800)
            b.yaw = yaw
            if there then b.action, b.timer, b.sub = "fight", 0, 1 end
        end
    elseif act == "return" then
        -- back up onto his summit in one leap
        if b.sub == 0 then
            king_anim(b, 8)
            sound("king_jump", loudness(b, m))
            local dx, dz = b.hx - b.x, b.hz - b.z
            local dy = b.hy - b.y
            local vy = max(100.0, sqrt(8.0 * (dy + 150.0)))           -- (high enough to clear his summit)
            local t = (vy + sqrt(max(0.0, vy * vy - 8.0 * dy))) / 4.0
            b.yaw = s16(atan2s(dz, dx))
            b.fvel, b.vy, b.ground, b.sub = sqrt(dx * dx + dz * dz) / max(t, 1.0), vy, false, 1
        elseif b.sub == 1 then
            if b.vy < 0.0 and b.y <= b.hy + 5.0 and b.ground then
                b.fvel, b.vy, b.sub = 0.0, 0.0, 2
                king_anim(b, 7)
                sound("king_voice", 1.0)
            end
        elseif b.sub == 2 then
            king_anim(b, 7)
            if at_end then b.sub = 3 end
        elseif b.sub == 3 then
            -- (king_bobomb_act_5: back on top he waits for him - "You're not supposed to throw me out of the ring!",
            -- DIALOG_128 - or, the athlete gone far below, goes back to waiting)
            king_anim(b, 5)
            local G = package.loaded["game"]
            if b.y - m.y > 1200.0 then
                b.action = "wait"
                M.end_boss_music()
            -- (as his challenge's: cur_obj_can_mario_activate_textbox_2(500, 100), by his feet - by his middle it reached
            -- the spiral path 3.1 m under the summit and started from there, 2026-10-29)
            elseif sqrt((m.x - b.x) ^ 2 + (m.z - b.z) ^ 2) < 500.0 and m.feet > b.y - 160.0 and m.feet < b.y + 100.0
                and m.walking and not (G and (G.carried or G.cutscene or G.swim)) then
                b.sub = 4
                local function go() b.action, b.timer, b.sub = "fight", 0, 1; M.start_boss_music() end
                if G and G.say then G.say(128, go) else go() end
            end
        else
            king_anim(b, 5)
        end
    elseif act == "beaten" then
        king_anim(b, 2)
        b.fvel = 0.0
        if b.timer == 45 then
            -- (king_bobomb_act_7: his last words, DIALOG_116; then he blows up and his star comes out of him, over to
            -- the summit, where Mario 64 sends it)
            b.action = "words"
            local G = package.loaded["game"]
            local function blow()
                sound("king_death", 1.0)
                explosion(world, b.x, b.y + 100.0, b.z)
                pcall(function() b.inst.actor:SetActorHiddenInGame(true) end)
                if G and G.add_star then
                    local sx, sy, sz = to_scene(2000.0, 4500.0 + 200.0, -4500.0)
                    local fx, fy, fz = to_scene(b.x, b.y + 200.0, b.z)
                    local ok, star = pcall(G.add_star, world, { kind = "star", pos = { sx, sy, sz }, id = b.star or 0, from = { fx, fy, fz } })
                    -- (cur_obj_spawn_star_at_y_offset: its CUTSCENE_STAR_SPAWN, the camera on it to the summit)
                    if ok and star and G.star_cutscene then pcall(G.star_cutscene, star) end
                end
                if G and G.shake_stage then pcall(G.shake_stage, 0.3) end     -- (cur_obj_shake_screen)
                b.action = "gone"
                M.end_boss_music()
                log("King Bob-omb beaten")
            end
            king_talk_cut(b, G)
            if G and G.say then G.say(116, blow) else blow() end
        end
    elseif act == "gone" then
        return
    end
    -- falling and landing (he has Mario 64's -4 a frame)
    move(b, 4.0, 200.0, act == "fight" or act == "hurt" or act == "grab")
end

-- The King is solid (push_mario_out_of_object for INTERACT_GRABBABLE): the athlete pushed out of his body - 165 between
-- their middles, his drawn body's width with the athlete's; he walked through him before ("also he needs collisions",
-- 2026-10-16). Not while either holds the other, nor once he is thrown or gone.
local KING_SOLID = 165.0
local function king_solid(b, m, pawn)
    local a = b.action
    if b.held or b.lift_h or a == "lifted" or a == "thrown" or a == "gone" or a == "beaten" or a == "grab" then return end
    local G = package.loaded["game"]
    if G and (G.dying or G.cutscene or G.carried or (G.intangible and G.intangible())) then return end
    local R = package.loaded["ragdoll"]
    if R and R.active then return end
    local dx, dz = m.x - b.x, m.z - b.z
    local d = sqrt(dx * dx + dz * dz)
    if d >= KING_SOLID or m.feet > b.y + 330.0 or m.feet + 240.0 < b.y then return end
    if d < 1.0 then dx, dz, d = sins(b.yaw), coss(b.yaw), 1.0 end
    local out = (KING_SOLID - d + 1.0) * S
    local ux, uz = dx / d, dz / d
    pcall(function()
        local l = pawn:K2_GetActorLocation()
        pawn:K2_SetActorLocation({ X = l.X - uz * out, Y = l.Y + ux * out, Z = l.Z }, true, {}, false)
    end)
end

local function touch_king(b, m, pawn, attack, new_attack)
    do local G = package.loaded["game"]; if G and G.cutscene then return end end   -- (the ending: creatures take no notice of him)
    if b.action ~= "fight" or b.sub == 0 then return end
    local dx, dz = m.x - b.x, m.z - b.z
    local d2 = dx * dx + dz * dz
    local R = 330.0
    if d2 > R * R or abs(m.y - (b.y + 200.0)) > 350.0 then return end
    local behind = abs(s16(m.angle - b.yaw)) > 0x5000
    if new_attack and not attack.air and behind then
        -- pushed from behind: lifted over the athlete's head, then thrown the way he faces
        b.action, b.timer = "lifted", 0
        b.lift_from = { b.x, b.y, b.z }
        b.lift_h = {}
        held_lock(b.lift_h, pawn, true)
        sound("king_grab", 1.0)
        log("King Bob-omb lifted (%d left)", b.health - 1)
        return
    end
    -- (only from in front of him: interact_grabbable's object_facing_mario, within 0x2AAA - 60 degrees - of the way he
    -- faces; he caught him from the side too: "make sure he can only grab you if you infront of him", 2026-10-16)
    local in_front = abs(s16(m.angle - b.yaw)) < 0x2AAA
    if in_front and (b.grab_cool or 0) <= 0 then
        local HP = _G.HEALTH
        if HP and HP.dead_t then return end
        local G = package.loaded["game"]
        if G and G.getup_at then return end         -- (not while the athlete is still down from the last throw)
        b.action, b.timer, b.sub, b.grab_cool = "grab", 0, 0, 150
        log("King Bob-omb grabbed the athlete")
    end
end

-- ------------------------------------------------------------ every tick
local acc = 0.0
local last_attack = nil
local pending = nil                 -- an attack begun and not yet seen by a step

local function render(b, a, cx, cy)
    local pr = b.prev
    local x, y, z = pr[1] + (b.x - pr[1]) * a, pr[2] + (b.y - pr[2]) * a, pr[3] + (b.z - pr[3]) * a
    local sx, sy, sz = to_scene(x, y, z)
    local yaw = b.yaw
    -- (the King's turn drawn smoothly between his 30 steps a second: spinning the athlete at 0x800 a step, drawn in steps,
    -- his hands - and the athlete flown to them - jumped 20 cm at each one: "its very jittery after he picks the player
    -- up", 2026-10-16. Tried once before and worse, when STORROR's 600 cm/s flying limit still held the athlete back.)
    if b.kind == "king_bobomb" and b.prev_yaw then yaw = b.prev_yaw + s16(b.yaw - b.prev_yaw) * a end
    local yawd = -yaw * 360.0 / 65536.0
    local data = b.inst.data
    local anim_i = (b.kind == "king_bobomb") and ((b.anim or 5) + 1) or ((b.action == "held") and 2 or 1)
    local anim = data.anims and (data.anims[anim_i] or data.anims[1])
    -- (far off, its walk posed every other frame, past 40 m every third, past 80 m every sixth: a pose was 0.08 ms, 19 a frame in BoB the
    -- most of the mod's time; the King, held or holding, and the near ones every frame)
    local every = 1
    if b.kind ~= "king_bobomb" and cx then
        local dx, dy = sx + OFFSET.X - cx, sy + OFFSET.Y - cy
        local d2 = dx * dx + dy * dy
        every = (d2 > 8000.0 * 8000.0) and 6 or ((d2 > 4000.0 * 4000.0) and 3 or ((d2 > 2500.0 * 2500.0) and 2 or 1))
    end
    b.pose_n = ((b.pose_n or 0) + 1) % 60
    -- (and moved then too, far off: every one moved every frame was still 0.7 ms in BoB - "just in general" laggy,
    -- 2026-10-31; near ones, the King and one held every frame as before)
    if every == 1 or b.pose_n % every == 0 then
        lib.set_pose(b.inst, sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z, yawd)
        if anim then pcall(lib.pose, b.inst, anim, b.f) end
        pcall(lib.face_camera, b.inst, sx + OFFSET.X, sy + OFFSET.Y)
    end
    if b.held then place_held(b, lib.pawn(), sx, sy, sz, yaw, a) end
end

-- Time stopped by a message (no steps): only their camera-facing parts turned to the camera - the dialog's camera came
-- round and a Bob-omb Buddy's body showed edge-on, a thin pink disc, 2026-10-16
function M.reface()
    for _, b in ipairs(M.list) do
        if b.inst and b.action ~= "gone" then
            local sx, sy = to_scene(b.x, b.y, b.z)
            pcall(lib.face_camera, b.inst, sx + OFFSET.X, sy + OFFSET.Y)
            -- (face_camera only writes the parts' rotation; the actor's move applies it - and in a message nothing
            -- moves, so the turn never showed: King Bob-omb squashed edge-on in his talk, 2026-10-16. Nudged in place.)
            pcall(function()
                local l = b.inst.actor:K2_GetActorLocation()
                lib.set_pose(b.inst, l.X, l.Y, l.Z - (b.inst.nudge or 0.0), b.inst.yaw or 0.0)
            end)
        end
    end
end

function M.update(dt, px, py, pz)
    if #M.list == 0 and #M.booms == 0 then return end
    local world = lib.world()
    local pawn = lib.pawn()
    local sx, sy, sz = px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z
    local m = { x = sy / S, y = sz / S, z = -sx / S }
    m.feet = m.y - 120.0
    m.facing = 0
    pcall(function() m.facing = s16((180.0 - pawn:K2_GetActorRotation().Yaw) * 65536.0 / 360.0) end)    -- (he faces +X)
    m.falling = false
    pcall(function() m.falling = pawn.CharacterMovement:IsFalling() and pawn:GetVelocity().Z < -50.0 end)
    m.walking = false               -- (on his feet: the engine's walking mode - not hanging, climbing or in the air)
    pcall(function() m.walking = pawn.CharacterMovement.MovementMode == 1 end)
    local attack = pawn and attack_of(pawn) or nil
    if attack ~= nil and attack.addr ~= last_attack then pending = attack end
    last_attack = attack and attack.addr or nil
    acc = acc + dt
    hold_dt = math.max(dt, 1.0 / 240.0)
    local n = 0
    while acc >= STEP and n < 4 do
        acc = acc - STEP
        n = n + 1
        for _, b in ipairs(M.list) do
            b.prev[1], b.prev[2], b.prev[3] = b.x, b.y, b.z
            b.prev_yaw = b.yaw
            local dx, dy, dz = m.x - b.x, m.y - b.y, m.z - b.z
            m.dist = sqrt(dx * dx + dy * dy + dz * dz)
            m.angle = s16(atan2s(dz, dx))
            if b.grab_cool and b.grab_cool > 0 then b.grab_cool = b.grab_cool - 1 end
            if m.dist < 5000.0 or b.action == "held" or b.action == "launched" or b.action == "explode" or b.action == "gone" then
                local fn = (b.kind == "bobomb") and step_bobomb or ((b.kind == "king_bobomb") and step_king or step_buddy)
                local ok, e = pcall(fn, b, m, pawn, world, pending or attack, pending ~= nil)
                if not ok and not b.broken then b.broken = true; log("%s: %s", b.kind, tostring(e)) end
                if pawn and b.kind == "bobomb" then pcall(touch_bobomb, b, m, pawn, pending or attack, pending ~= nil) end
                if pawn and b.kind == "bobomb" then pcall(push_him, b, m, pawn) end
                if pawn and b.kind == "king_bobomb" then pcall(touch_king, b, m, pawn, pending or attack, pending ~= nil) end
                if pawn and b.kind == "king_bobomb" then pcall(king_solid, b, m, pawn) end
            end
        end
        pending = nil                      -- (a push counts once)
        pcall(collide)
        pcall(apart)
    end
    if acc > STEP then acc = 0.0 end
    local cx, cy = lib.camera_location({ X = px, Y = py, Z = pz })
    local a = acc / STEP
    local SFX = sfx()
    -- (far ones drawn less often - every 3rd frame past 19 m, every 8th past 60 m, up or down too - as the creatures are:
    -- "I want a significant boost in fps", 2026-11-03)
    M.lod_frame = (M.lod_frame or 0) + 1
    for i, b in ipairs(M.list) do
        if b.action ~= "gone" and not b.broken then
            local dx, dz = m.x - b.x, m.z - b.z
            local h2 = dx * dx + dz * dz
            local dy = m.y - b.y
            local d3 = h2 + dy * dy
            local every = 1
            if b.action ~= "held" and b.action ~= "launched" and b.kind ~= "king_bobomb" then
                every = (d3 > 8000.0 * 8000.0) and 4 or ((d3 > 2500.0 * 2500.0) and 3 or 1)
            end
            -- (drawn from far off too: King Bob-omb is seen on his summit from across the field)
            if (h2 < 12000.0 * 12000.0 or b.kind == "king_bobomb" or b.action == "held") and (every == 1 or (M.lod_frame + i) % every == 0) then
                pcall(render, b, a, cx, cy)
            end
            if b.fuse and SFX and SFX.hold then SFX.hold("loop_fuse", loudness(b, m, 3000.0)) end
        end
    end
    update_booms(cx, cy)
end

-- An explosion at a spot (Mario 64 units), for others to use: Bowser's bombs (game.lua).
function M.explode_at(world, x, y, z) return explosion(world, x, y, z) end

-- Hit by something thrown (boxes.lua's small box): bob-ombs within `reach` of (x, y, z), Mario units, go off. How many.
function M.hit_at(x, y, z, reach)
    local n = 0
    for _, b in ipairs(M.list) do
        if b.kind == "bobomb" and b.action ~= "explode" and b.action ~= "gone" then
            local dx, dy, dz = x - b.x, y - (b.y + 50.0), z - b.z
            local r = BODY + reach
            if dx * dx + dz * dz < r * r and abs(dy) < 60.0 + reach then
                if M.held == b then M.held = nil end
                b.action, b.timer = "explode", 0
                n = n + 1
                log("bob-omb hit by a thrown box")
            end
        end
    end
    return n
end

return M
