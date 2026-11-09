-- SM64Map: Bob-omb Battlefield's chain chomp, on its chain at its wooden post (asked 2026-10-14: "next lets add
-- chain chomp").
--
-- Mario 64's behaviour (src/game/behaviors/chain_chomp.inc.c), kept in its own terms as platforms.lua is:
-- positions in Mario 64 units, angles in its 16-bit units, one step per Mario 64 frame (30 a second), drawn blended
-- between the last two steps. It turns to face the player with little hops, then lunges out to the end of its
-- chain, which rattles as it is pulled up short. Touching it costs three wedges of power and knocks the athlete
-- down; touching it in the middle of an attack makes it rear up instead, as hitting it does in Mario 64.
--
-- Its post sinks a little each time it is pounded; Mario ground-pounds it, the athlete drop-kicks it (his attack:
-- STORROR's MontageAttack animations, "as for the ground pound I thought we could use drop kick", 2026-10-14).
-- Three and the chomp is free: Mario 64's puzzle jingle, it bounds about, smashes the gate in front of the star
-- behind it, then bounds away over the field and is gone. (Mario 64 shows that from a camera of its own; here the
-- player keeps his.)
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET

local C = { list = {}, kinds = { chain_chomp = true } }
local S = 0.75                      -- cm per Mario 64 unit
local STEP = 1 / 30
local H = {}                        -- floor_z, actor_data, knock_down: handed over by game.lua
local PLAT = nil                    -- platforms.lua (the post is one of its platforms, and so is the gate)

local sqrt, sin, cos, atan, floor, abs, pi = math.sqrt, math.sin, math.cos, math.atan, math.floor, math.abs, math.pi

function C.setup(h, plat) H, PLAT = h, plat end

-- ------------------------------------------------------------ Mario 64's arithmetic
local function sins(a) return sin(a * pi / 32768.0) end
local function coss(a) return cos(a * pi / 32768.0) end
local function atan2s(y, x) return atan(x, y) * 32768.0 / pi end        -- (z, x) gives a yaw
local function s16(a) a = floor(a) % 65536; if a >= 32768 then a = a - 65536 end; return a end
local function approach(v, target, step)
    if v < target then v = v + step; if v > target then v = target end
    elseif v > target then v = v - step; if v < target then v = target end end
    return v
end
-- an angle toward another by at most `inc`; true once there (approach_s16_symmetric)
local function turn_toward(cur, target, inc)
    local d = s16(target - cur)
    if d > inc then return s16(cur + inc), false end
    if d < -inc then return s16(cur - inc), false end
    return s16(target), true
end

-- Mario 64 units <-> this scene's space (the level's world, less lib.OFFSET)
local function to_scene(x, y, z) return -z * S, x * S, y * S end
local function floor_y(x, y, z)
    if not H.floor_z then return nil end
    local sx, sy = to_scene(x, 0, z)
    local fz = H.floor_z(sx, sy, (y + 300.0) * S)
    return fz and fz / S or nil
end

local function sound(name, v)
    local SFX = package.loaded["sfx"]
    if SFX and (v or 1.0) > 0.02 then pcall(SFX.play, name, v) end
end
local function loudness(c, m)
    local dx, dy, dz = c.x - m.x, c.y - m.y, c.z - m.z
    local k = 1.0 - sqrt(dx * dx + dy * dy + dz * dz) / 5000.0
    if k <= 0.0 then return 0.0 end
    return k ^ 1.5
end

-- ------------------------------------------------------------ its numbers
local GRAPH_Y = 240.0               -- the model is drawn this far above where the chomp is (oGraphYOffset)
local CHAIN_GRAPH_Y = 40.0
local BODY_R = 290.0                -- its ball, at scale 2
local REACH = 60.0                  -- the athlete's half-width
local NORMAL_LEN, LUNGE_LEN = 750.0 / 5, 900.0 / 5     -- chain length per link: resting, lunging
local GATE = { 1456.0, 768.0, 446.0 }                   -- Bob-omb Battlefield's gate (levels/bob/script.c)
local GATE_AIM = { 1450.0, 562.0 }                      -- where the freed chomp leaps to hit it
local AWAY = { 3288.0, -1770.0 }                        -- and where it leaps to after

-- release status, as Mario 64's
local NOT_RELEASED, TRIGGER, LUNGE_AROUND, BREAK_GATE, JUMP_AWAY, GONE = 0, 1, 2, 3, 4, 5

-- ------------------------------------------------------------ the scene's chomp
local LOWER_SHELL = 0.96
function C.add(world, o, templates)
    local data, ball = H.actor_data and H.actor_data("chain_chomp"), H.actor_data and H.actor_data("chain_ball")
    if not (data and ball and o.sm64) then log("chain chomp: no model"); return end
    local x, y, z = o.sm64[1], o.sm64[2], o.sm64[3]
    local fy = floor_y(x, y, z)
    if fy then y = fy end                               -- (DROP_TO_FLOOR)
    local c = {
        o = o, hx = x, hy = y, hz = z, x = x, y = y, z = z, vy = 0.0, fvel = 0.0, gravity = -4.0,
        yaw = s16(-(o.yaw or 0.0) * 65536.0 / 360.0), pitch = 0, target_pitch = 0,
        sub = "turn", timer = 0, release = NOT_RELEASED, ground = true,
        per = 0.0, between = 0.0, unk104 = 0.0, lunges = 0, hit_gate = false, restricted = false, dist_pivot = 0.0,
        pvx = x, pvy = y, pvz = z,                      -- the pivot: the link at the post
        seg = {}, f = 0.0, hit_cool = 0, gate_t = 0,
    }
    for i = 0, 4 do c.seg[i] = { x = 0.0, y = 0.0, z = 0.0 } end
    local sx, sy, sz = to_scene(x, y, z)
    c.inst = lib.make_instance(world, data, { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z + GRAPH_Y * S }, 0.0, 2.0)
    -- (its two shells are the same size and hinge on the same middle: behind the hinge they swing through each other
    -- as it bites - "his two halves are still intersecting". The lower one a little smaller, nested inside the upper:
    -- what overlaps is hidden, the outside one round ball.)
    if c.inst and c.inst.comps[2] then
        pcall(function() c.inst.comps[2]:SetRelativeScale3D({ X = LOWER_SHELL, Y = LOWER_SHELL, Z = LOWER_SHELL }) end)
    end
    if c.inst then c.inst.moves = true end      -- (placed by render with its own turn: lib.pose leaves it be)
    c.balls = {}
    for i = 0, 4 do
        c.balls[i] = lib.make_instance(world, ball, { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z + CHAIN_GRAPH_Y * S }, 0.0, 2.0)
    end
    -- its wooden post: a platform (it can be stood on, and sinks when pounded), half the model's size
    if PLAT and PLAT.add and o.post_tpl then
        local ok, p = pcall(PLAT.add, world, { kind = "platform", bhv = "post", tpl = o.post_tpl, pos = { x, y, z },
                                                ang = { 0, 0, 0 }, scale = { 0.5, 0.5, 0.5 }, bp = 0 }, templates)
        if ok then c.post = p else log("chain chomp: no post (%s)", tostring(p)) end
    end
    c.prev = { c.x, c.y, c.z, c.pvx, c.pvy, c.pvz }
    for i = 1, 4 do c.prev[#c.prev + 1] = 0.0; c.prev[#c.prev + 1] = 0.0; c.prev[#c.prev + 1] = 0.0 end
    C.list[#C.list + 1] = c
    log("chain chomp at %.0f %.0f %.0f%s", x, y, z, c.post and ", on its post" or ", no post")
end

function C.clear()
    for _, c in ipairs(C.list) do
        if c.inst then lib.destroy(c.inst.actor) end
        for i = 0, 4 do if c.balls[i] then lib.destroy(c.balls[i].actor) end end
    end
    C.list = {}
end

-- the map went: forget it without touching anything
function C.forget() C.list = {} end

-- ------------------------------------------------------------ Mario 64's behaviour
local function restore_lengths(c)
    c.per = approach(c.per, NORMAL_LEN, 4.0)
    c.between = c.per
end

local function sub_turn(c, m)
    c.gravity = -4.0
    restore_lengths(c)
    c.pitch = turn_toward(c.pitch, 0, 0x100)
    if c.ground then
        c.yaw = turn_toward(c.yaw, m.angle, 0x400)
        if abs(s16(m.angle - c.yaw)) < 0x800 then
            if c.timer > 30 then
                if c.frame0 then
                    c.reverse = true
                    if c.timer > 40 then
                        sound("chomp_lunge", loudness(c, m))
                        c.sub = "lunge"
                        c.per = LUNGE_LEN
                        c.fvel, c.vy, c.gravity = 140.0, 20.0, 0.0
                        c.target_pitch = s16(-atan2s(c.fvel, c.vy))
                    end
                else
                    c.timer = c.timer - 1
                end
            else
                c.fvel = 0.0
            end
        else
            sound("chomp_hop", loudness(c, m))
            c.fvel, c.vy = 10.0, 20.0
        end
    else
        c.yaw = turn_toward(c.yaw, m.angle, 400)
        c.timer = 0
    end
end

local function sub_lunge(c, m)
    c.pitch = turn_toward(c.pitch, c.target_pitch, 0x400)
    if c.fvel ~= 0.0 then
        if c.restricted then
            c.fvel, c.vy = 0.0, 0.0
            c.unk104 = 30.0
        end
        local v = 900.0 - c.dist_pivot
        if v > 220.0 then v = 220.0 end
        c.between = v / 220.0 * c.per
        c.timer = 0
    else
        c.yaw = turn_toward(c.yaw, atan2s(c.seg[0].z, c.seg[0].x), 0x1000)
        if c.unk104 ~= 0.0 then
            c.unk104 = approach(c.unk104, 0.0, 0.8)
        else
            c.sub = "turn"
        end
        -- (the chain rattles as it is pulled up short: its links jump back and forth every other frame)
        c.between = c.unk104
        if c.frames % 2 ~= 0 then c.between = -c.unk104 end
    end
    if c.timer < 30 then c.reverse = true end
end

local function on_released(c, m)
    if c.release == TRIGGER then
        c.fvel, c.gravity = 0.0, -4.0
        if c.ground then c.release, c.timer = LUNGE_AROUND, 0 end
    elseif c.release == LUNGE_AROUND then
        restore_lengths(c)
        if c.ground then
            if c.lunges == 0 then
                local yaw, there = turn_toward(c.yaw, m.angle, 800)
                c.yaw = yaw
                if there then
                    if c.timer > 60 then c.lunges = c.lunges + 1 end
                else
                    c.timer = 0
                end
            else
                c.lunges = c.lunges + 1
                if c.lunges <= 5 then
                    sound("chomp_hop", loudness(c, m))
                    c.yaw = s16(m.angle + ((math.random(0, 1) == 0) and -0x2000 or 0x2000))
                    c.fvel, c.vy = 30.0, 50.0
                else
                    c.release, c.gate_t = BREAK_GATE, 0
                    local dx, dz = GATE_AIM[1] - c.x, GATE_AIM[2] - c.z
                    c.yaw = s16(atan2s(dz, dx))
                    c.fvel, c.vy = sqrt(dx * dx + dz * dz) / 8.0, 50.0
                end
            end
        end
    elseif c.release == BREAK_GATE then
        c.gate_t = c.gate_t + 1
        if not c.hit_gate then
            -- (Mario 64 takes any wall it runs into for the gate; here it is the gate itself, and after five
            -- seconds without reaching it the gate goes anyway, so that the star can never be shut in for good)
            local dx, dz = c.x - GATE[1], c.z - GATE[3]
            if dx * dx + dz * dz < 330.0 * 330.0 or c.gate_t > 150 then
                c.hit_gate = true
                c.yaw = s16(c.yaw + 0x8000)
                c.fvel = c.fvel * 0.4
                C.break_gate(m)
            end
        elseif c.ground then
            c.release = JUMP_AWAY
            local dx, dz = AWAY[1] - c.x, AWAY[2] - c.z
            c.yaw = s16(atan2s(dz, dx))
            c.fvel, c.vy = sqrt(dx * dx + dz * dz) / 50.0, 120.0
        end
    elseif c.release == JUMP_AWAY then
        if c.ground and c.vy <= 0.0 then
            c.release = GONE
            if c.inst then pcall(function() c.inst.actor:SetActorHiddenInGame(true) end) end
            for i = 0, 4 do if c.balls[i] then pcall(function() c.balls[i].actor:SetActorHiddenInGame(true) end) end end
            log("chain chomp: gone")
        end
    end
end

-- forward along its yaw, gravity, and the floor under it (cur_obj_move_standard)
local function move(c)
    local nx, nz = c.x + c.fvel * sins(c.yaw), c.z + c.fvel * coss(c.yaw)
    c.vy = c.vy + c.gravity
    if c.vy < -78.0 then c.vy = -78.0 end
    local ny = c.y + c.vy
    local fy = floor_y(nx, math.max(ny, c.y), nz)
    if fy and fy > c.y + 150.0 then
        -- a wall or a step too high: it stays where it is
        nx, nz, fy = c.x, c.z, floor_y(c.x, math.max(ny, c.y), c.z)
    end
    c.x, c.z = nx, nz
    if fy and ny <= fy then
        ny = fy
        if c.vy < 0.0 then c.vy = 0.0 end
        c.ground = true
    else
        c.ground = false
    end
    c.y = ny
end

local function update_chain(c)
    local vy = (c.vy < 0.0) and c.vy or -20.0
    for i = 1, 4 do
        local p, s = c.seg[i - 1], c.seg[i]
        s.y = s.y + vy
        if s.y < 0.0 then s.y = 0.0 end
        local ox, oy, oz = s.x - p.x, s.y - p.y, s.z - p.z
        local d = sqrt(ox * ox + oy * oy + oz * oz)
        if d > c.between and d > 1e-6 then
            local k = c.between / d
            ox, oy, oz = ox * k, oy * k, oz * k
        end
        ox, oy, oz = ox + p.x, oy + p.y, oz + p.z
        d = sqrt(ox * ox + oy * oy + oz * oz)
        local most = c.per * (5 - i)
        if d > most and d > 1e-6 then
            local k = most / d
            ox, oy, oz = ox * k, oy * k, oz * k
        end
        s.x, s.y, s.z = ox, oy, oz
    end
end

local function step(c, m)
    c.frames = (c.frames or 0) + 1
    c.reverse = false
    if c.release == NOT_RELEASED then
        if c.sub == "turn" then sub_turn(c, m) else sub_lunge(c, m) end
    else
        on_released(c, m)
    end
    if c.release == GONE then return end
    move(c)
    local s0 = c.seg[0]
    s0.x, s0.y, s0.z = c.x - c.pvx, c.y - c.pvy, c.z - c.pvz
    c.dist_pivot = sqrt(s0.x * s0.x + s0.y * s0.y + s0.z * s0.z)
    local most = c.per * 5
    if c.dist_pivot > most then
        local k = most / c.dist_pivot
        c.dist_pivot = most
        s0.x, s0.y, s0.z = s0.x * k, s0.y * k, s0.z * k
        if c.release == NOT_RELEASED then
            c.x, c.y, c.z = c.pvx + s0.x, c.pvy + s0.y, c.pvz + s0.z
            c.restricted = true
        else
            -- free: it drags the chain's end along after it, over the ground
            c.pvx, c.pvz = c.x - s0.x, c.z - s0.z
            c.pvy = floor_y(c.pvx, c.pvy + 200.0, c.pvz) or (c.y - s0.y)
        end
    else
        c.restricted = false
    end
    update_chain(c)
    -- its biting, 20 frames, played backwards at times (cur_obj_reverse_animation)
    local frames = c.anim_frames or 20
    c.f = c.f + (c.reverse and -1.0 or 1.0)
    if c.f < 0 then c.f = c.f + frames elseif c.f >= frames then c.f = c.f - frames end
    c.frame0 = floor(c.f + 0.5) % frames == 0
    c.timer = c.timer + 1
end

-- ------------------------------------------------------------ the athlete
-- the montage STORROR is playing on him, if it is one of his attacks (the drop kick among them)
local seen_montage = nil
local function attack_montage(pawn)
    local name, addr = nil, nil
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        if not (ai and ai:IsValid()) then return end
        local mt = ai:GetCurrentActiveMontage()
        if mt and mt:IsValid() then
            name, addr = mt:GetFName():ToString(), mt:GetAddress()
        end
    end)
    if name and name ~= seen_montage then
        seen_montage = name
        -- (every move he made in Bob-omb Battlefield went into the log - 60 lines in half a minute: only when asked)
        if C.trace then log("chain chomp: the athlete plays %s", name) end
    elseif not name then
        seen_montage = nil
    end
    if name and (name:find("Attack") or name:lower():find("kick")) then return name, addr end
    return nil
end

-- (halved: since ragdoll.lua gives his body the push in full it threw him across the level - "bomb omb chainchomp and
-- big balls do significantly more knockback then usual", 2026-10-30; it was 2200, 1300)
local BITE_OUT, BITE_UP = 600.0, 400.0       -- (was 1100, 650: "why is everything in the game doing so much knockback?", 2026-10-31)
--       -- cm/s a bite throws him at, away from it and up
local function touch(c, m, pawn, attacking)
    do local G = package.loaded["game"]; if G and G.cutscene then return end end   -- (the ending: creatures take no notice of him)
    if c.release ~= NOT_RELEASED or c.hit_cool > 0 then return end
    local dx, dy, dz = m.x - c.x, m.y - (c.y + GRAPH_Y), m.z - c.z
    local r = BODY_R + REACH
    if dx * dx + dy * dy + dz * dz > r * r then return end
    c.hit_cool = 30
    -- (kicked or not, he comes off worse: hurt and thrown - "make sure when drop kicking chain chomp you get damaged
    -- and tossed by him instead of him getting damaged and tossed in the air". Only a bob-omb sends it up: C.blast_at)
    if attacking then log("chain chomp: kicked - it bites back") end
    local HP = _G.HEALTH
    if HP and (HP.grace > 0 or HP.dead_t) then return end
    -- (no harm from its bite under the vanish cap: Mario 64's take_damage_and_knock_back - "when invis capped enemies should not be able to ragdol the player", 2026-10-26)
    do local C = package.loaded["caps"]; if C and C.on and C.on("vanish") then return end end
    if HP then HP.damage(3, "the chain chomp") end
    if H.knock_down then
        -- thrown away from it, the way it faces as much as away from its middle
        local d = sqrt(dx * dx + dz * dz)
        if d < 1.0 then dx, dz, d = sins(c.yaw), coss(c.yaw), 1.0 end
        local sx, sy = -dz / d, dx / d                 -- (Mario 64 x, z -> this scene's x, y)
        -- (hard, all of him at once - "add nockback to chainchomps attacks": it was 900 out, 500 up, on his hips alone)
        pcall(H.knock_down, pawn, sx * BITE_OUT, sy * BITE_OUT, BITE_UP, true)
    end
end

-- A bob-omb going off by it (Mario 64: an explosion is an attack on it, obj_check_attacks): it rears up, high into the
-- air - "when you throw a bob omb at chainchomp he goes in the air. like the real game". (x, y, z): the blast, Mario 64
-- units.
function C.blast_at(x, y, z)
    for _, c in ipairs(C.list) do
        if c.release == NOT_RELEASED and not c.broken then
            local dx, dy, dz = c.x - x, c.y + GRAPH_Y - y, c.z - z
            if dx * dx + dy * dy + dz * dz < (BODY_R + 350.0) ^ 2 then
                c.sub = "lunge"
                c.per = LUNGE_LEN
                c.fvel, c.vy, c.gravity = 0.0, 300.0, -4.0
                c.target_pitch = -0x3000
                c.hit_cool = 30
                log("chain chomp: blown up into the air by a bob-omb")
            end
        end
    end
end

-- the post: drop-kicked, once per kick - it leans away from him, and the third kick knocks it out (platforms.lua B.post)
local function pound_post(c, m, attack, addr)
    do return end           -- (platforms.lua's B.post sees its kicks itself now, by the same rule as the other posts)
    local p = c.post
    if not (p and attack) or c.release ~= NOT_RELEASED then return end
    if addr == c.last_attack then return end
    local dx, dz = m.x - p.x, m.z - p.z
    if dx * dx + dz * dz > 220.0 * 220.0 then return end
    if m.y < p.y - 100.0 or m.y > p.y + 500.0 then return end
    c.last_attack = addr
    p.kick = { x = m.x, z = m.z }
    c.pounds = (c.pounds or 0) + 1
    log("chain chomp: post kicked (%d), %s", c.pounds, attack)
end

function C.break_gate(m)
    local P = PLAT
    if not (P and P.list) then return end
    for _, p in ipairs(P.list) do
        if p.o and p.o.gate == "chomp" then
            local dx, dz = p.x - m.x, p.z - m.z
            local k = 1.0 - sqrt(dx * dx + dz * dz) / 6000.0
            sound("gate_break", k > 0.3 and k or 0.3)
            if P.remove then P.remove(p) end
            log("chain chomp: the gate is broken")
            return
        end
    end
end

-- ------------------------------------------------------------ every tick
local acc = 0.0

-- The shine on its body (Mario 64 G_TEXTURE_GEN: its "dull" and "bright shine" textures are mapped by where each
-- point faces as the camera sees it - right and up of the view - not painted on). Exported with the model's own fixed
-- coordinates, each facet showed a random patch of shine: "chainchomp kinda looks chopped". Every frame, near him.
local function shine(c, cam)
    local inst = c.inst
    if not c.shine then
        c.shine = {}
        for i, part in ipairs(inst.data.parts or {}) do
            for _, sec in ipairs(part.sections or {}) do
                if sec.texture and sec.texture:find("shine") and sec.nrm and inst.comps[i] then
                    c.shine[#c.shine + 1] = { comp = inst.comps[i], id = sec.id, nrm = sec.nrm, n = sec.nverts }
                end
            end
        end
    end
    local r, u = cam.r, cam.u
    for _, s in ipairs(c.shine) do
        local ok, F, R, U = pcall(function() return s.comp:GetForwardVector(), s.comp:GetRightVector(), s.comp:GetUpVector() end)
        if ok and F then
            local uvs, nr = {}, s.nrm
            for i = 0, s.n - 1 do
                local a, b, d = nr[i * 3 + 1], nr[i * 3 + 2], nr[i * 3 + 3]
                local wx, wy, wz = a * F.X + b * R.X + d * U.X, a * F.Y + b * R.Y + d * U.Y, a * F.Z + b * R.Z + d * U.Z
                uvs[i + 1] = { X = 0.5 + 0.5 * (wx * r[1] + wy * r[2] + wz * r[3]), Y = 0.5 - 0.5 * (wx * u[1] + wy * u[2] + wz * u[3]) }
            end
            pcall(lib.update_section, s.comp, s.id, {}, nil, uvs)
        end
    end
end

local function render(c, a, cx, cy, cz)
    local pr = c.prev
    local function lerp(i, v) return pr[i] + (v - pr[i]) * a end
    local x, y, z = lerp(1, c.x), lerp(2, c.y), lerp(3, c.z)
    local sx, sy, sz = to_scene(x, y + GRAPH_Y, z)
    -- (its parts posed first, then it is placed - turned to him, tipped as it lunges - which carries them along; a
    -- hair up and down every other frame so a still chomp's parts still take their new pose. lib.pose used to place
    -- it again itself, facing one fixed way: "currently he only looks in one direction")
    local anim = c.inst.data.anims and c.inst.data.anims[1]
    if anim then
        c.anim_frames = anim.frames or 20
        pcall(lib.pose, c.inst, anim, c.f)
    end
    c.nudge = (c.nudge == 0.02) and 0.0 or 0.02
    local yaw = -c.yaw * 360.0 / 65536.0
    c.inst.yaw = yaw
    pcall(function()
        c.inst.actor:K2_TeleportTo({ X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z + c.nudge },
            { Pitch = c.pitch * 360.0 / 65536.0, Yaw = yaw, Roll = 0.0 })
    end)
    -- the links: the pivot at the post, the others out along the chain, each turned to the camera
    local pvx, pvy, pvz = lerp(4, c.pvx), lerp(5, c.pvy), lerp(6, c.pvz)
    for i = 0, 4 do
        local b = c.balls[i]
        if b then
            local lx, ly, lz = pvx, pvy, pvz
            if i > 0 then
                local j = 7 + (i - 1) * 3
                lx, ly, lz = pvx + lerp(j, c.seg[i].x), pvy + lerp(j + 1, c.seg[i].y), pvz + lerp(j + 2, c.seg[i].z)
            end
            local bx, by, bz = to_scene(lx, ly + CHAIN_GRAPH_Y, lz)
            bx, by, bz = bx + OFFSET.X, by + OFFSET.Y, bz + OFFSET.Z
            local dx, dy, dz = cx - bx, cy - by, cz - bz
            local yaw = math.deg(atan(dy, dx)) + 180.0
            local pitch = -math.deg(atan(dz, sqrt(dx * dx + dy * dy)))
            pcall(function() b.actor:K2_TeleportTo({ X = bx, Y = by, Z = bz }, { Pitch = pitch, Yaw = yaw, Roll = 0.0 }) end)
        end
    end
end

local function snapshot(c)
    local pr = c.prev
    pr[1], pr[2], pr[3], pr[4], pr[5], pr[6] = c.x, c.y, c.z, c.pvx, c.pvy, c.pvz
    for i = 1, 4 do
        local j = 7 + (i - 1) * 3
        pr[j], pr[j + 1], pr[j + 2] = c.seg[i].x, c.seg[i].y, c.seg[i].z
    end
end

-- (px, py, pz): the athlete's middle, in the world
function C.update(dt, px, py, pz)
    if #C.list == 0 then return end
    local pawn = lib.pawn()
    local sx, sy, sz = px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z
    local m = { x = sy / S, y = sz / S, z = -sx / S }
    local attack, addr = nil, nil
    local cam = nil
    acc = acc + dt
    local n = 0
    while acc >= STEP and n < 4 do
        acc = acc - STEP
        n = n + 1
        for _, c in ipairs(C.list) do
            if c.release ~= GONE then
                snapshot(c)
                m.angle = s16(atan2s(m.z - c.z, m.x - c.x))
                if c.hit_cool > 0 then c.hit_cool = c.hit_cool - 1 end
                local ok, e = pcall(step, c, m)
                if not ok and not c.broken then c.broken = true; log("chain chomp: %s", tostring(e)) end
            end
        end
    end
    if acc > STEP then acc = 0.0 end
    for _, c in ipairs(C.list) do
        if c.release ~= GONE and not c.broken then
            -- the post: freed once it has sunk all the way (platforms.lua's post)
            if c.post and c.post.released and c.release == NOT_RELEASED then
                c.release, c.timer, c.sub = TRIGGER, 0, "turn"
                sound("puzzle_jingle", 1.0)
                log("chain chomp: free!")
            end
            local near = (m.x - c.x) ^ 2 + (m.z - c.z) ^ 2 < 2500.0 * 2500.0
            if near and pawn then
                if not attack then attack, addr = attack_montage(pawn) end
                pound_post(c, m, attack, addr)
                touch(c, m, pawn, attack ~= nil)
            end
            local cx, cy, cz = lib.camera_location({ X = px, Y = py, Z = pz + 500.0 })
            render(c, acc / STEP, cx, cy, cz)
            if near then
                if not cam then
                    cam = false
                    pcall(function()
                        local cr = lib.controller().PlayerCameraManager:GetCameraRotation()
                        local yw, pt = math.rad(cr.Yaw), math.rad(cr.Pitch)
                        cam = { r = { -math.sin(yw), math.cos(yw), 0.0 },
                                u = { -math.sin(pt) * math.cos(yw), -math.sin(pt) * math.sin(yw), math.cos(pt) } }
                    end)
                end
                if cam then pcall(shine, c, cam) end
            end
        end
    end
end

return C
