-- SM64Map Bowser fight: Bowser as Mario 64 has him (game/behaviors/bowser.inc.c, bowser_flame.inc.c,
-- shock_wave.inc.c), asked 2026-10-14: "the entire boss fight needs worked on. make sure to really buff it over".
--
-- One Bowser per fight scene (bowser = the Dark World, bowser_2 = the Fire Sea, bowser_3 = the Sky). He runs
-- Mario 64's actions at its 30 frames a second, in its own numbers (turned into the scene's centimetres):
--   intro       looks up and walks on, then picks a move
--   default     picks the next move by the stage's own rules (bowser_bitdw/bitfs/bits_actions), every other
--               time just walking on
--   walk        slow gait toward the athlete, turning, until he faces him
--   breath      inhales and breathes a stream of fire that lands and burns on the floor
--   spit        (Fire Sea, Sky) spits a fireball onto the floor, one to three times
--   sky         (Sky) spits flames into the sky that rain down on the arena
--   charge      runs at him, slips and skids to a stop; at the edge he teeters and turns back
--   quickjump   (Dark World) a hop at him: landing close knocks him down
--   bigjump     (Fire Sea, Sky) a great leap; the Fire Sea's arena rocks, the Sky's floor sends out a shockwave
--   teleport    (Fire Sea) fades out, glides at him, fades in
--   dance       a little dance (sometimes in the Dark World; in the Sky with one hit left)
--   held        his tail in the athlete's hands: spun by the camera or the stick, let go by a push
--   thrown      tumbling through the air; a bomb within 6 m (800 units) goes off: a hit
--   hitmine     a hit he lives through: flipped back onto the middle, gets up
--   fallen      off the arena: leaps back on
--   dead        flies back to the middle, lies down, twirls away; his key (or the Sky's star)
local M = {}

local sqrt, sin, cos, atan, floor, abs, pi = math.sqrt, math.sin, math.cos, math.atan, math.floor, math.abs, math.pi
local S = 0.75                  -- Mario 64 units to centimetres
local FRAME = 1.0 / 30.0
local U = 360.0 / 65536.0       -- a Mario 64 angle unit, in degrees

-- his animations (their Mario 64 numbers; the actor carries all 27, in order)
local A = { stand_up = 0, shaking = 2, grabbed = 3, breath = 6, jump_stop = 8, jump_start = 9, dance = 10,
            breath_up = 11, idle = 12, slow_gait = 13, look_down_stop = 14, look_up_walk = 15, flip_down = 16,
            lay_down = 17, run_start = 18, run = 19, run_stop = 20, run_slip = 21, breath_quick = 22, edge_move = 23,
            edge_stop = 24, flip = 25, stand_up_from_flip = 26 }

local ctx = nil                 -- what the game gives: lib, OFFSET, floor_at, sfx, pushed, PLAT, MUSIC, actor_data, add_star

function M.setup(c) ctx = c end

-- ------------------------------------------------------------ small helpers
local function adiff(a, b) return ((a - b + 540.0) % 360.0) - 180.0 end
local function turn(cur, target, step)
    local d = adiff(target, cur)
    if d > step then d = step elseif d < -step then d = -step end
    return cur + d
end
local function yaw_to(ax, ay, bx, by) return math.deg(atan(by - ay, bx - ax)) end
local function sfx(name, v) if ctx and ctx.sfx then ctx.sfx(name, v) end end
local function stage(b) return b.stage end           -- "bitdw" / "bitfs" / "bits"

-- the floor under (x, y) no higher than z+up (the level's, or a platform's: the Fire Sea's arena, the Sky's pieces)
local function ground(x, y, z, up)
    return ctx.floor_at(x, y, z + (up or 150.0))
end

-- ------------------------------------------------------------ his poses
local function anim_data(b, id) return b.inst.data.anims[id + 1] end
local function set_anim(b, id)
    if b.anim_id ~= id then b.anim_id, b.af = id, 0.0 end
end
-- the animation's last frame (its loopEnd), and whether it is near its end (cur_obj_check_if_near_animation_end)
local function anim_len(b) local a = anim_data(b, b.anim_id); return a and math.max(1, (a.loopEnd or 1)) or 1 end
local function near_end(b) return b.af >= anim_len(b) - 2 end
local function at_frame(b, f) return floor(b.af) == f and floor(b.af_prev or -1) ~= f end
-- the sounds his animations make, at their frames (sBowserSoundStates, by animation)
local ANIM_SFX = {
    [8] = { "bowser_walk", 0 }, [9] = { "bowser_roar", 0 }, [10] = { "bowser_roar", 0 }, [13] = { "bowser_walk", 20, 40 },
    [14] = { "bowser_walk", 20 }, [15] = { "bowser_walk", 20, 40 }, [16] = { "bowser_tail", 0 }, [17] = { "bowser_defeated", 0 },
    [18] = { "bowser_walk", 8 }, [19] = { "bowser_walk", 8, 17 }, [20] = { "bowser_walk", 8 }, [22] = { "en_flame_blown", 5 },
    [25] = { "bowser_tail", 0 }, [26] = { "bowser_roar", 0 },
}
local function advance_anim(b)
    b.af_prev = b.af
    local a = anim_data(b, b.anim_id)
    if not a then return end
    -- (each frame once: a held last frame does not sound again)
    local f = floor(b.af)
    if f ~= b.snd_f or b.anim_id ~= b.snd_a then
        b.snd_f, b.snd_a = f, b.anim_id
        local e = ANIM_SFX[b.anim_id]
        if e and not b.hidden and (f == e[2] or f == e[3]) then sfx(e[1], 1.0) end
    end
    b.af = b.af + 1.0
    if b.af >= (a.loopEnd or 1) then
        if b.hold_last then b.af = (a.loopEnd or 1) - 1
        else b.af = a.loopStart or 0 end
    end
end

M.trace = {}                    -- (his last moves, for checking the fight: "act@x,y")
local function go(b, act)
    b.act, b.sub, b.timer, b.btimer, b.hold_last = act, 0, 0, 0, false
    b.snipe_n = nil                     -- (a fire snipe's run of four, cut short by anything else)
    b.arm = nil                         -- (the meteor shower's raised arm)
    b.tilt_jump = nil                   -- (a big jump that rocks the arena - choose)
    -- (a jump off an outer piece cut short - his tail taken before he was off: forgotten, not carried into a later jump)
    b.breaking = nil
    M.trace[#M.trace + 1] = string.format("%s@%d,%d", act, floor(b.x or 0), floor(b.y or 0))
    if #M.trace > 24 then table.remove(M.trace, 1) end
end

-- his breath (dBowserFlamesOrientationValues): for each frame of the breath that throws a flame, the mouth (up, on)
-- and the flame's way (yaw, pitch), in Mario 64 units
local BREATH = {
    [46] = { 229, 139, -1, 2051 }, [48] = { 222, 147, -1, 2344 }, [50] = { 221, 149, -1, 2582 },
    [52] = { 221, 150, -1, 2806 }, [54] = { 222, 150, -1, 2948 }, [56] = { 223, 149, 1316, 2974 },
    [58] = { 226, 147, 2623, 2903 }, [60] = { 228, 144, 3328, 2789 }, [62] = { 232, 140, 3467, 2632 },
    [64] = { 236, 136, 3309, 2410 }, [66] = { 239, 132, 2934, 2147 }, [68] = { 244, 128, 2416, 1870 },
    [70] = { 248, 122, 1827, 1609 }, [72] = { 253, 117, 1238, 1401 }, [74] = { 256, 111, 713, 1289 },
    [76] = { 261, 105, 321, 1317 }, [78] = { 264, 100, 110, 1561 }, [80] = { 268, 95, 12, 2223 },
    [82] = { 272, 90, -1, 3184 }, [84] = { 274, 86, 20, 4278 },
}

-- ------------------------------------------------------------ flames (bowser_flame.inc.c, flame.inc.c)
-- Every flame is Mario 64's: its 25-unit picture at its scale, raised 14 units a scale (oGraphYOffset), turned to the
-- camera, flickering through its eight pictures every other frame. Kinds, as Mario 64 has them:
--   stream   bhvFlameMovingForwardGrowing: from his mouth, on and down, growing (3, half a scale a frame); it burns;
--            on the floor it pops up as a "pop"
--   pop      bhvFlameBowser before it lands: a hop (now and then a great one), drifting; lands as a "burn"
--   burn     bhvFlameBowser landed: 6-8 big, burning; dies down after a while
--   large    bhvFlameLargeBurningOut: falls in place, lands as a burn of 8
--   skyball  bhvBlueBowserFlame: up out of his mouth into the sky; breaks into three "float" (blue: two)
--   float    bhvFlameFloatingLanding: drifts down over the arena; lands as a "large" (blue: a ring of "bounce")
--   bounce   bhvFlameBouncing: blue, bouncing outward across the floor
--   roller   bhvSmallPiranhaFlame (scale 7): the fireball he spits onto the floor; slows, then turns after him
--   puff     bhvFlyguyFlame: what the fireball sheds, rising and shrinking
M.flames = {}
local MAX_FLAMES = 120          -- (room for the breath's 40 and the fires they leave)
local FLAME_TEX_RED, FLAME_TEX_BLUE = {}, {}
-- (Mario 64's own flame pictures, as the flamethrowers have: "change the fire texture to be the actual fire texture from
-- the game", 2026-10-18; they were make_flames.py's painted fire)
for k = 0, 7 do FLAME_TEX_RED[k], FLAME_TEX_BLUE[k] = "flame_sm64_red_" .. k, "flame_sm64_blue_" .. k end
M.arena_z = 0.0                 -- (his home floor: below it by 3 m is the lava, where flames go out)
-- (2026-10-14, the user: "the fire is huge", "too much fire", "too often". Every flame is drawn, and hits, at this
-- share of Mario 64's size; a breath throws half Mario 64's flames, the sky attack half its fireballs; and between
-- one fire attack and the next he waits FIRE_GAP seconds, give or take a fifth.)
local LOOK = 0.45
-- (the breath's plume reaches further and wider than Mario 64's: "make fire plume stream of fire reach more area",
-- then "make the plume land in a much larger area", 2026-10-14. Each of its flames flies at its own speed, between
-- PLUME_SPEED and PLUME_SPEED2 times Mario 64's, and lives PLUME_LIFE frames, so they come down near and far; its
-- sweep is PLUME_SWEEP times as wide, to about 57 degrees either side)
-- (a quarter faster, over the same ground - "make bowsers fire ball a bit faster", 2026-10-18: it was 1.2 to 2.4 for 90)
local PLUME_SPEED, PLUME_SPEED2, PLUME_LIFE, PLUME_SWEEP = 1.5, 3.0, 72, 3.0
-- (and more of it: "add more fire to fire plume as well", 2026-10-14: PLUME_PER flames on each of Mario 64's frames that
-- throw one, every other frame, each its own way a little; 40 a breath, where for a while it was 10)
local PLUME_PER, PLUME_JITTER = 2, 8.0
local LOB = 60.0                -- (degrees up he is thrown at: a lob; 40 was "higher lob needed still", 2026-10-14)
local FIRE_GAP = 6.0

-- (flames are kept, not destroyed: a dead one is hidden and handed to the next. With the breath at 40 flames the game
-- made and threw away hundreds of actors a fight, and crashed on a background thread reading freed memory,
-- 2026-10-14. The pool belongs to its world: a new world, and the old ones are forgotten untouched.)
local pool = { world = nil, free = {} }
local function release(f)
    local here = nil
    pcall(function() here = ctx.lib.world():GetAddress() end)
    if pool.world ~= here then return end
    pcall(function() f.actor:SetActorHiddenInGame(true) end)
    pool.free[#pool.free + 1] = { actor = f.actor, pmc = f.pmc }
    -- (its RENDER 96 fire not looked at while it waits - burn.lua M.fire3d_park)
    local BU = package.loaded["burn"]
    if BU and BU.fire3d_park then pcall(BU.fire3d_park, f.actor, true) end
end

-- a new flame's actor, made - flame_quad takes one from the pool first
local function flame_new(world, x, y, z, blue)
    local lib = ctx.lib
    local actor = lib.spawn_actor(world, { X = x + ctx.OFFSET.X, Y = y + ctx.OFFSET.Y, Z = z + ctx.OFFSET.Z }, 0.0)
    if not actor then return nil end
    local pmc = lib.add_pmc(actor)
    if not pmc then lib.destroy(actor); return nil end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    local h = 25.0 * S
    -- (one face, toward -X: the see-through material is two-sided already; a second face z-fought it black)
    lib.add_sections(world, pmc, { {
        id = 0, layer = "translucent", texture = (blue and FLAME_TEX_BLUE or FLAME_TEX_RED)[0], nverts = 4, ntris = 2,
        pos = { 0, -h, -h, 0, h, -h, 0, h, h, 0, -h, h },
        uv = { 0, 1, 1, 1, 1, 0, 0, 0 },
        col = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
        nrm = { -1, 0, 0, -1, 0, 0, -1, 0, 0, -1, 0, 0 },
        idx = { 0, 1, 2, 0, 2, 3 },
    } })
    -- (RENDER 96: the fire in the round - burn.lua fire3d_on)
    do local BU = package.loaded["burn"]; if BU and BU.fire3d_on and actor then pcall(BU.fire3d_on, world, actor, h, blue, nil) end end
    return actor, pmc
end

local function flame_quad(world, x, y, z, blue)
    local lib = ctx.lib
    local here = world:GetAddress()
    if pool.world ~= here then pool.world, pool.free = here, {} end
    local e = table.remove(pool.free)
    if e then
        local ok = pcall(function()
            e.actor:K2_TeleportTo({ X = x + ctx.OFFSET.X, Y = y + ctx.OFFSET.Y, Z = z + ctx.OFFSET.Z }, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
            local mid = lib.get_mid(world, "translucent", (blue and FLAME_TEX_BLUE or FLAME_TEX_RED)[0])
            if mid then e.pmc:SetMaterial(0, mid) end
            e.actor:SetActorHiddenInGame(false)
            local BU = package.loaded["burn"]
            if BU and BU.fire3d_color then BU.fire3d_color(world, e.actor, blue) end
            if BU and BU.fire3d_park then BU.fire3d_park(e.actor, false) end
        end)
        if ok then return e.actor, e.pmc end
    end
    return flame_new(world, x, y, z, blue)
end
-- Flames made ahead into the pool, FLAMES_AHEAD_PER a frame up to FLAMES_AHEAD: an attack that throws twenty takes them
-- from it, not new - the fire snipe's strip made all of its in one frame, 8 ms of it ("lots of lag during fight",
-- 2026-11-04)
M.AHEAD = { n = 64, per = 3 }           -- (FLAMES_AHEAD, FLAMES_AHEAD_PER: fields, the file's locals are full)
function M.flames_ahead(world)
    local here = world:GetAddress()
    if pool.world ~= here then pool.world, pool.free, pool.made = here, {}, 0 end
    if (pool.made or 0) >= M.AHEAD.n then return end
    local BU = package.loaded["burn"]
    for _ = 1, M.AHEAD.per do
        local actor, pmc = flame_new(world, 0.0, 0.0, -50000.0, false)
        if not actor then pool.made = M.AHEAD.n; return end
        pcall(function() actor:SetActorHiddenInGame(true) end)
        if BU and BU.fire3d_park then pcall(BU.fire3d_park, actor, true) end
        pool.free[#pool.free + 1] = { actor = actor, pmc = pmc }
        pool.made = (pool.made or 0) + 1
    end
end

-- a new flame: kind, where (scene cm, his record's frame), which way (scene degrees), its scale
local function add_flame(world, kind, x, y, z, yaw, s, blue, o)
    if #M.flames >= MAX_FLAMES then return nil end
    local actor, pmc = flame_quad(world, x, y, z, blue)
    if not actor then return nil end
    local f = { actor = actor, pmc = pmc, kind = kind, x = x, y = y, z = z, yaw = yaw or (math.random() * 360.0), s = s or 1.0,
                t = 0, blue = blue, anim = math.random(0, 7), wob = math.random(0, 63), fwd = 0.0, vz = 0.0, grav = 0.0,
                vzmin = -1e9 }
    if o then for k, v in pairs(o) do f[k] = v end end
    M.flames[#M.flames + 1] = f
    return f
end

-- (bhvFlameBowser's start: a hop of 20, or 80 one time in five; on at 10; gravity 4, falling no faster than 4)
local function pop_from(world, x, y, z)
    add_flame(world, "pop", x, y, z, nil, math.random() + 1.0, false,
        { vz = ((math.random() < 0.2) and 80.0 or 20.0) * S, fwd = 10.0 * S, grav = -4.0 * S, vzmin = -4.0 * S })
end

-- the athlete inside a flame's hitbox: radius and height (Mario 64 units, times its scale), down offset
local function in_flame(f, ax, ay, az, r, h, down)
    local rr = (r * f.s * LOOK + 37.0) * S
    local dx, dy = ax - f.x, ay - f.y
    if dx * dx + dy * dy > rr * rr then return false end
    local bot = f.z - down * f.s * LOOK * S
    return az + 90.0 > bot and az - 90.0 < bot + h * f.s * LOOK * S
end

-- Mario 64's move: on along its way, falling, landing on what is under it (false: it went into the lava)
local function flame_move(f)
    f.x = f.x + cos(math.rad(f.yaw)) * f.fwd
    f.y = f.y + sin(math.rad(f.yaw)) * f.fwd
    f.vz = math.max(f.vz + f.grav, f.vzmin)
    f.z = f.z + f.vz
    local fz = ground(f.x, f.y, f.z, 60.0)
    if fz and f.z <= fz and f.vz <= 0.0 then
        f.z = fz
        if fz < M.arena_z - 300.0 then return "lava" end
        return "landed"
    end
    if not fz and f.z < M.arena_z - 300.0 then return "lava" end         -- (off the Sky's pieces: gone)
    return nil
end

-- (bowser_flame_move: drifting to and fro along its way)
local function flame_wobble(f, gt)
    local a = (((f.wob + gt) % 64) * 1024) * U
    local d = sin(math.rad(a)) * 4.0 * S
    f.x = f.x + cos(math.rad(f.yaw)) * d
    f.y = f.y + sin(math.rad(f.yaw)) * d
end

M.gt = 0                        -- (Mario 64's global timer, for the drift)

local let_go                    -- (below, with the hold: Bowser let go of, thrown or dropped)
local spark_add, spark_step     -- (below, with the key's dance: sparkles)
local words, words_start, words_tick, words_stop    -- (below, with his entrance: his words when he is beaten)

-- (`draw`: false for all but the frame's last step - drawn once a frame, not at every one of his steps: four steps in a
-- long frame each moved, turned and sized every flame, the next frame longer still - "major major major input delay
-- during boss fight", 2026-11-04)
local function update_flames(world, ax, ay, az, grounded, draw)
    local keep = {}
    M.gt = M.gt + 1
    local cx, cy, cz = ctx.lib.camera_location({ X = ax + ctx.OFFSET.X, Y = ay + ctx.OFFSET.Y, Z = az + ctx.OFFSET.Z })
    pcall(function() local cm = ctx.lib.controller().PlayerCameraManager:GetCameraLocation(); cx, cy, cz = cm.X, cm.Y, cm.Z end)
    local hurt = nil
    local born = {}             -- (flames this frame makes: added once the list is walked)
    local function spawn(...) born[#born + 1] = { ... } end
    for _, f in ipairs(M.flames) do
        f.t = f.t + 1
        local alive = true
        local yoff = 14.0           -- (Mario 64's oGraphYOffset, for its own picture; the painted fire's foot needed 20)
        local k = f.kind
        if k == "stream" then
            -- (growing as Mario 64's does, but no bigger than 18: at 30 they filled the screen)
            f.s = math.min(f.s + 0.5, 18.0)
            if f.pitch > 0x800 then f.pitch = f.pitch - 0x200 end
            local p = math.rad(f.pitch * U)
            local v = 30.0 * S * (f.spd or PLUME_SPEED)
            f.x = f.x + cos(math.rad(f.yaw)) * cos(p) * v
            f.y = f.y + sin(math.rad(f.yaw)) * cos(p) * v
            f.z = f.z - sin(p) * v
            if in_flame(f, ax, ay, az, 10, 40, 20) then hurt = hurt or f end
            local fz = ground(f.x, f.y, f.z, 60.0)
            if f.t > PLUME_LIFE then   -- (Mario 64's: gone at a scale of 30, 54 frames out)
                alive = false
            elseif fz and f.z < fz then
                alive = false
                if fz > M.arena_z - 300.0 then spawn("pop", f.x, f.y, fz) end
            end
        elseif k == "pop" or k == "large" then
            if k == "pop" then flame_wobble(f, M.gt) end
            local m = flame_move(f)
            if m == "lava" or f.t > 400 then
                alive = false
            elseif m == "landed" then
                f.kind, f.t, f.fwd, f.vz, f.grav = "burn", 0, 0.0, 0.0, 0.0
                f.s = (k == "large") and 8.0 or (math.random() * 2.0 + 6.0)
            end
        elseif k == "burn" then
            if f.t > f.s * 10.0 + 5.0 then f.s = f.s - 0.15 end
            if f.s <= 0.0 then
                alive = false
                -- (a burnt-out flame leaves a coin now and then: "add coins that drop from fire", then "make it a 1 in
                -- 30", then "1 in 40", 2026-10-14; Mario 64's bowser_flame_despawn has 1 in 10, but the breath throws 40)
                if math.random() < 1.0 / 40.0 and ctx.spawn_coin then pcall(ctx.spawn_coin, f.x, f.y, f.z + 20.0) end
            end
            if alive and in_flame(f, ax, ay, az, 10, 40, 0) then hurt = hurt or f end
        elseif k == "skyball" then
            if f.s < 16.0 then f.s = f.s + 0.5 end
            flame_move(f)
            if in_flame(f, ax, ay, az, 10, 40, 20) then hurt = hurt or f end
            if f.t > 20 then
                alive = false
                if f.bluefloat then
                    spawn("float", f.x, f.y, f.z, 8.0, true, 1)
                    spawn("float", f.x, f.y, f.z, 8.0, true, 2)
                else
                    for i = 1, 3 do spawn("float", f.x, f.y, f.z, 5.0, false, 0, i == 1) end
                end
            end
        elseif k == "float" then
            flame_wobble(f, M.gt)
            local m = flame_move(f)
            if m == "lava" or f.t > 900 then
                alive = false
            elseif m == "landed" then
                alive = false
                if f.param == 0 then
                    spawn("large", f.x, f.y, f.z)
                else
                    spawn("bluegroup", f.x, f.y, f.z)
                end
            end
        elseif k == "bounce" then
            f.fwd = 15.0 * S
            local m = flame_move(f)
            if m == "landed" then f.vz = 30.0 * S end           -- (bounciness -1: off the floor as fast as it came)
            if in_flame(f, ax, ay, az, 10, 40, 20) then hurt = hurt or f end
            if m == "lava" or f.t > 300 then alive = false end
            -- (gone when it reaches him)
            local bb = M.bowser
            if bb and not bb.held and (f.x - bb.x) ^ 2 + (f.y - bb.y) ^ 2 < (300.0 * S) ^ 2 and f.t > 20 then alive = false end
        elseif k == "roller" then
            yoff = 21.0
            -- (slowing from 30 to 12, turning after him all the while: "a single flame that tracks mario and moves
            -- torwards him", 2026-10-14; Mario 64's only turns once it has slowed to 10)
            if f.speed > 12.0 then f.speed = math.max(12.0, f.speed - 0.6) end
            f.yaw = turn(f.yaw, yaw_to(f.x, f.y, ax, ay), ((f.speed > 12.0) and 0x100 or 0x280) * U)
            f.fwd = f.speed * cos(math.rad(0x1000 * U)) * S
            f.vz = -f.speed * sin(math.rad(0x1000 * U)) * S
            local m = flame_move(f)
            f.went = (f.went or 0.0) + f.speed
            if in_flame(f, ax, ay, az, 10, 20, 10) then hurt = hurt or f end
            if f.t >= (f.next_puff or 8) then
                f.next_puff = f.t + math.random(8, 15)
                spawn("puff", f.x, f.y, f.z + 15.0 * f.s * S, f.s)
            end
            if f.went > 2400.0 or m == "lava" then alive = false; sfx("en_flame_blown", 0.5) end
        elseif k == "puff" then
            f.vz = f.vz + 2.0 * S
            f.z = f.z + f.vz
            f.s = f.s - 0.6
            if f.s <= 0.0 then alive = false end
        elseif k == "hand" then
            -- (the meteor shower's tell: a fire in his raised hand, growing till the slam - M.arm_turn says where)
            local hb = M.bowser
            if hb and hb.act == "meteor" and (hb.sub or 0) < 1 then
                if M.hand_at then f.x, f.y, f.z = M.hand_at[1], M.hand_at[2], M.hand_at[3] - 40.0 end
                f.s = math.min(f.grow or 9.0, f.s + 0.18)
                if ctx.hold_sfx then ctx.hold_sfx("loop_bowser_fire", 0.7) end
            else
                alive = false
            end
        elseif k == "upshot" then
            -- (the meteor shower's: breathed straight up, growing to `grow`, quicker by `acc` a frame, gone high over the
            -- arena; harmless)
            local life = f.life or 60
            if f.t < life - 12 then f.s = math.min(f.grow or 10.0, f.s + 0.6) else f.s = f.s * 0.8 end
            f.vz = f.vz + (f.acc or 0.0)
            f.z = f.z + f.vz
            if f.t > life or f.s < 0.3 then alive = false end
        elseif k == "jet" then
            -- (the fire snipe's: up out of the floor to `grow` in 5 frames, held `hold`, then down - M.snipe)
            if f.t <= 5 then f.s = math.min(f.grow or 6.0, f.s + (f.grow or 6.0) / 5.0)
            elseif f.t > 5 + (f.hold or 18) then f.s = f.s - 0.35 end
            if f.s <= 0.0 then alive = false end
            if alive and in_flame(f, ax, ay, az, 10, 40, 0) then hurt = hurt or f end
        elseif k == "meteor" then
            -- (the meteor shower's: held up there `delay` frames, then down onto its mark, where it lands as a fire;
            -- it burns on the way down too)
            if (f.delay or 0) > 0 then
                f.delay = f.delay - 1
            else
                local m = flame_move(f)
                if in_flame(f, ax, ay, az, 12, 50, 25) then hurt = hurt or f end
                if m == "landed" then
                    f.kind, f.t, f.vz, f.grav, f.s = "burn", 0, 0.0, 0.0, 8.0
                    sfx("explosion", 0.45)
                    if ctx.shake then pcall(ctx.shake, 0.2) end
                    if M.hide_mark then pcall(M.hide_mark, f.mark) end
                    for _ = 1, 3 do spawn("pop", f.x, f.y, f.z) end
                elseif m == "lava" or f.t > 300 then
                    alive = false
                    if M.hide_mark then pcall(M.hide_mark, f.mark) end
                end
            end
        end
        if alive and draw == false then
            keep[#keep + 1] = f
        elseif alive then
            local s = math.max(0.05, f.s) * LOOK
            if f.t % 2 == 0 then
                f.anim = (f.anim + 1) % 8
                pcall(function()
                    local mid = ctx.lib.get_mid(world, "translucent", (f.blue and FLAME_TEX_BLUE or FLAME_TEX_RED)[f.anim])
                    if mid then f.pmc:SetMaterial(0, mid) end
                end)
            end
            local okp, errp = pcall(function()
                -- (its face to the camera)
                local px, py, pz = f.x + ctx.OFFSET.X, f.y + ctx.OFFSET.Y, f.z + ctx.OFFSET.Z + yoff * s * S
                local dx, dy, dz = cx - px, cy - py, cz - pz
                local yaw = math.deg(atan(dy, dx)) + 180.0
                local pitch = -math.deg(atan(dz, sqrt(dx * dx + dy * dy)))
                -- (close to the camera it shrinks away, so that a flame going by never fills the screen)
                local half, dist = 25.0 * s * S, sqrt(dx * dx + dy * dy + dz * dz)
                if dist < half * 3.0 then s = s * math.max(0.1, dist / (half * 3.0)) end
                f.actor:K2_TeleportTo({ X = px, Y = py, Z = pz }, { Pitch = pitch, Yaw = yaw, Roll = 0.0 })
                local sx, sz = s, s
                if k == "roller" then local r = math.random() - 0.5; sz, sx = s * (1.0 + 0.3 * r), s * (1.0 - 0.2 * r) end
                f.actor:SetActorScale3D({ X = s, Y = sx, Z = sz })
            end)
            if not okp then M.flame_err = tostring(errp) end
            keep[#keep + 1] = f
        else
            release(f)
        end
    end
    M.flames = keep
    -- the flames this frame made
    for _, n in ipairs(born) do
        local kind, x, y, z = n[1], n[2], n[3], n[4]
        if kind == "pop" then
            pop_from(world, x, y, z)
        elseif kind == "large" then
            add_flame(world, "large", x, y, z, nil, 7.0, false, { vz = 10.0 * S, grav = -4.0 * S, vzmin = -4.0 * S })
        elseif kind == "float" then
            local s, blue, param, aimed = n[5], n[6], n[7], n[8]
            local yaw, fwd = math.random() * 360.0, (param == 0) and math.random() * 70.0 or math.random() * 5.0
            local vz = math.random() * 20.0
            if aimed then
                -- (one of each three comes down on the athlete: how long it falls, as it will fall)
                local d = sqrt((ax - x) ^ 2 + (ay - y) ^ 2) / S
                local zz, v, n, feet = z / S, vz, 0, (az - 90.0) / S
                while zz > feet and n < 900 do v = math.max(v - 1.0, -8.0); zz = zz + v; n = n + 1 end
                yaw, fwd = yaw_to(x, y, ax, ay) + (math.random() - 0.5) * 16.0, math.min(70.0, d / math.max(1, n))
            end
            add_flame(world, "float", x, y, z, yaw, s, blue,
                { param = param, fwd = fwd * S, vz = vz * S, grav = -1.0 * S, vzmin = ({ [0] = -8.0, -6.0, -3.0 })[param] * S })
        elseif kind == "bluegroup" then
            -- (bhv_blue_flames_group_loop: three ways from him, eight times, smaller each time)
            M.blue_groups = M.blue_groups or {}
            M.blue_groups[#M.blue_groups + 1] = { x = x, y = y, z = z, t = 0, yaw = yaw_to(x, y, ax, ay), s = 5.0 }
        elseif kind == "puff" then
            add_flame(world, "puff", x, y, z, nil, n[5], false, {})
        end
    end
    -- the blue groups: every other frame, three bouncing flames a third of a turn apart
    if M.blue_groups then
        local kg = {}
        for _, g in ipairs(M.blue_groups) do
            if g.t % 2 == 0 then
                for i = 0, 2 do
                    add_flame(world, "bounce", g.x, g.y, g.z, g.yaw - i * 120.0, g.s, true,
                        { vz = 30.0 * S, grav = -4.0 * S, vzmin = -75.0 * S })
                end
                g.s = g.s - 0.5
            end
            g.t = g.t + 1
            if g.t < 16 then kg[#kg + 1] = g end
        end
        M.blue_groups = kg
    end
    if hurt and ctx.hurt and not words then
        -- (burnt while he swings him: Bowser is dropped - flying off as fast as he was swung, as Mario 64's
        -- interact_flame drops what Mario holds - and then he burns. Both at once left the swing holding him still
        -- while the burn ran him, until it burnt him out: "new problem if fire hits you while grabbing bowsers
        -- tale", 2026-10-14)
        local b = M.bowser
        if b and b.held then let_go(b, ctx.lib.pawn(), ax, ay, true) end
        ctx.hurt("fire", "Bowser's flame", ax - hurt.x, ay - hurt.y)
    end
end

-- ------------------------------------------------------------ the Sky's shockwave (bhvBowserShockWave)
M.waves = {}
-- (Mario 64's impact ring: a quad of 10 by 10 at scale 1, its two halves two pictures of the rings, white and see-through)
local function ring_half(id, right, lv)
    local h = 5.0 * S
    local x0, x1 = right and 0.0 or -h, right and h or 0.0
    -- (Mario 64's x is the scene's Y, its z the scene's -X: u runs along x, v along z)
    local function v(x, z) return -z, x end
    local ax_, ay_ = v(x0, -h); local bx_, by_ = v(x1, -h); local cx_, cy_ = v(x1, h); local dx_, dy_ = v(x0, h)
    -- (its rings drawn thin - textures/impact_ring_l<lv>_*.png, the game's rings' places, each band a third as thick and
    -- thinner again in the later pictures: "make them skinnier", 2026-11-02)
    return { id = id, layer = "translucent", texture = string.format("impact_ring_l%d_%s", lv or 1, right and "right" or "left"), nverts = 4, ntris = 2,
             pos = { ax_, ay_, 0, bx_, by_, 0, cx_, cy_, 0, dx_, dy_, 0 },
             uv = { 0, 0, 1, 0, 1, 1, 0, 1 },
             col = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
             nrm = { 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1 },
             idx = { 0, 2, 1, 0, 3, 2 } }
end
local function add_wave(world, x, y, z)
    -- (one actor a thickness, the first shown)
    local actors = {}
    for lv = 1, #M.WAVE_SIG do
        local actor = ctx.lib.spawn_actor(world, { X = x + ctx.OFFSET.X, Y = y + ctx.OFFSET.Y, Z = z + ctx.OFFSET.Z + 12.0 }, 0.0)
        local pmc = actor and ctx.lib.add_pmc(actor)
        if pmc then
            pcall(function() pmc:SetCollisionEnabled(0) end)
            ctx.lib.add_sections(world, pmc, { ring_half(0, false, lv), ring_half(1, true, lv) })
            pcall(function() actor:SetActorScale3D({ X = 0.01, Y = 0.01, Z = 1.0 }) end)
            if lv > 1 then pcall(function() actor:SetActorHiddenInGame(true) end) end
        end
        actors[lv] = actor or false
    end
    if not actors[1] then return end
    M.waves[#M.waves + 1] = { actors = actors, lv = 1, x = x, y = y, z = z, t = 0 }
    sfx("big_pound", 1.0)
end
local function wave_gone(w) for _, a in ipairs(w.actors) do if a then ctx.lib.destroy(a) end end end
-- (the whole wave at this share of Mario 64's - drawn and felt alike: at his 10 a frame its outer ring was past the
-- Sky arena's edge, 2539 out, in 53 frames and still hurting at 3360, rings bigger than the stage - "bowser shockwaves
-- are huge", 2026-11-02. At 0.6 the outer ring stops hurting at 2016, four fifths of the way out)
M.WAVE_SCALE = 0.6
-- (its rings in three pictures, each band WAVE_SIG of the picture's half-size, the next thinner one taking over at the
-- scales in WAVE_UP: about one width, half a metre or so, all the way out - and it goes on to WAVE_EDGE, past the outer
-- pieces' corners, before it goes, hurting across each band as it goes: Mario 64's stopped hurting at 70 frames and
-- went at 90 here, half way across the stage - "the shockwave rings dont keep going", 2026-11-02)
M.WAVE_SIG = { 0.09, 0.04, 0.018 }
M.WAVE_UP = { 450.0, 1000.0 }
M.WAVE_EDGE = 3900.0
local RING_PEAK = { 2.15, 4.4 }
local function update_waves(ax, ay, az, grounded)
    local keep = {}
    for _, w in ipairs(M.waves) do
        w.t = w.t + 1
        local sc = w.t * 10.0 * M.WAVE_SCALE  -- (its scale: the rings lie at 2.15 and 4.4 of it)
        -- (the thinner picture once it has grown: the rings about one width all the way out)
        local lv = 1
        for i, at in ipairs(M.WAVE_UP) do if sc >= at then lv = i + 1 end end
        if lv ~= w.lv and w.actors[lv] then
            local old, new = w.actors[w.lv], w.actors[lv]
            pcall(function() new:SetActorHiddenInGame(false) end)
            if old then pcall(function() old:SetActorHiddenInGame(true) end) end
            w.lv = lv
        end
        local a = w.actors[w.lv]
        if a then pcall(function() a:SetActorScale3D({ X = sc, Y = sc, Z = 1.0 }) end) end
        -- (each ring hurts across its drawn band, as long as it goes)
        local half = 1.5 * M.WAVE_SIG[w.lv] * sc + 20.0
        if grounded and abs(az - 90.0 - w.z) < 120.0 then
            local d = sqrt((ax - w.x) ^ 2 + (ay - w.y) ^ 2) / S
            for _, pk in ipairs(RING_PEAK) do
                if abs(d - pk * sc) < half then
                    if ctx.hurt then ctx.hurt("shock", "Bowser's shockwave", ax - w.x, ay - w.y) end
                    break
                end
            end
        end
        -- (gone once its inner ring is out past the arena's edge)
        if RING_PEAK[1] * sc - half > M.WAVE_EDGE or w.t > 900 then wave_gone(w) else keep[#keep + 1] = w end
    end
    M.waves = keep
end

function M.clear()
    if M.expo_set then pcall(M.expo_set, false) end
    if M.cut_stop then M.cut_stop(false) end
    if M.dance_stop then M.dance_stop(false) end
    if M.spark_clear then M.spark_clear() end
    M.key_star, M.key_danced = nil, nil
    if words_stop then words_stop(false) end
    for _, f in ipairs(M.flames) do ctx.lib.destroy(f.actor) end
    local here = nil
    pcall(function() here = ctx.lib.world():GetAddress() end)
    if pool.world == here then for _, e in ipairs(pool.free) do ctx.lib.destroy(e.actor) end end
    pool.world, pool.free = nil, {}
    for _, w in ipairs(M.waves) do wave_gone(w) end
    M.flames, M.waves, M.blue_groups, M.grand, M.key = {}, {}, nil, nil, nil
    -- (the final fight's own: its marks, its falling pieces, the wind's puffs, his shadow - only in the world they were
    -- made in; a new map took them with it)
    if M.clone and M.clone_gone then pcall(M.clone_gone) end
    if M.aura then pcall(M.aura_off) end
    -- (his clear time down with the scene - not into the ending, which shows it on)
    do
        local HP, EN = _G.HEALTH, package.loaded["ending"]
        if HP and HP.final_clear and not (EN and EN.active) then HP.final_clear, HP.grand_time = nil, nil end
    end
    if M.ghosts and M.ghosts.world == here then
        if M.ghosts.aura then pcall(ctx.lib.destroy, M.ghosts.aura.inst.actor) end
        if M.ghosts.clone then pcall(ctx.lib.destroy, M.ghosts.clone.inst.actor) end
    end
    M.ghosts = nil
    if M.glow and M.glow.world == here then pcall(ctx.lib.destroy, M.glow.actor) end
    M.glow = nil
    if M.air and M.air.world == here then for _, e in ipairs(M.air.list) do pcall(ctx.lib.destroy, e.inst.actor) end end
    M.air = nil
    local T = M.tells
    if T and T.world == here then
        if T.strip then ctx.lib.destroy(T.strip.actor) end
        for _, r in pairs(T.rings or {}) do ctx.lib.destroy(r.actor) end
    end
    local D = M.debris
    if D and D.world == here then for _, c in ipairs(D.list) do ctx.lib.destroy(c.actor) end end
    local PF = M.puffs
    if PF and PF.world == here then for _, p in ipairs(PF.list) do ctx.lib.destroy(p.actor) end end
    M.tells, M.debris, M.puffs, M.catch, M.clone, M.sky, M.liquid = nil, nil, nil, nil, nil, nil, nil
    local G = package.loaded["game"]
    if G then G.pancake_floor = nil end
end

-- ------------------------------------------------------------ the final fight's three floors (2026-11-03)
-- "theres gonna be 3 platforms hovering over eachother like pancake. starting at the top ... everytime bowser gets blown
-- up and lands back on the stage the stage will crack, hit him 3 times the stage will shatter and bowser and mario fall
-- to the next wind for a short period of time lifts the player up so the player takes no damage"; "should be 9 hits in
-- total to kill him". game.lua G.pancakes lays the floors, platforms.lua B.pancake makes them (the second rocks). Here:
-- a crack where he lands after each hit he lives through, the floor breaking at its third, the fall, the wind; each
-- floor quicker than the last (`speeds`: his frames a second, 30 times this - "the speed for bowser 2 is 1.3x and the
-- final is 1.7x", 2026-11-03; then 1.2 and 1.4 - "lets just do this instead bowser 1 is 1.0x, bowser 2 is 1.2x bowser 3
-- is 1.4x", 2026-11-04).
M.PC = { per = 3, top = 230.25, speeds = { 1.0, 1.2, 1.4 },
         -- (the camera's exposure fixed through the fight: left to itself, over the dark floors and the dark sky it
         -- brightened the whole picture to a white haze - "floor is super white/foggy", 2026-11-04)
         ev = -0.7 }
-- (the sprint's reach by floor: `overrun` frames more of running on, straight, once he would stop - past him or done -
-- and his skid `skid` times as hard; floor 2 a bit further - "on 2nd stage make bowsers sprint attack go a bit further",
-- 2026-11-04)
M.PC.reach = { [2] = { overrun = 7, skid = 0.7 } }
-- The floors' liquid (game.lua G.pancakes gives them final_liquid_rb - tools/final_liquid_rb_tex.py, the liquid's flow
-- drawn without colour): flowing as the water does, its picture slid along and swaying by its material's offset (not
-- the faces' UVs: the engine keeps those as half floats), and each wedge of the arena tinted its own colour of the
-- rainbow by its material's colour, the colours turning round it; the middle paler, every colour in turn - "can you make
-- the stage texture move like the water, also make it change colors like a rainbow", 2026-11-04. A material of its own
-- for each wedge (lib.get_mid's key takes the "alpha" even for an opaque one: each its own copy), the same flow in all,
-- so the picture runs on across their seams. `u`, `v`: pictures a second; `sway` pictures, over `sway_t` s; `scale`:
-- the picture's repeats to the faces' one; `period`: s for the colours to go once round; `sat`: the wedges' colour.
M.LIQUID = { u = 0.07, v = 0.03, sway = 0.04, sway_t = 5.0, scale = 2.0, period = 8.0, sat = 0.85, mid_sat = 0.45 }
M.liquid = nil
local LIQUID_TEX = { final_liquid = true, final_liquid_rb = true }
local function hsv(h, s, v)
    local i = math.floor(h * 6.0) % 6
    local f = h * 6.0 - math.floor(h * 6.0)
    local p, q, t = v * (1.0 - s), v * (1.0 - f * s), v * (1.0 - (1.0 - f) * s)
    if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v end
    return v, p, q
end
function M.liquid_tick(world, dt)
    local L = M.liquid
    local here = nil
    pcall(function() here = ctx.lib.world():GetAddress() end)
    if not L or L.world ~= here then
        local PL = ctx.PLAT
        if not (PL and PL.pancakes) then return end
        local floors = 0
        for k = 1, 3 do if PL.pancakes[k] and PL.pancakes[k].pmc then floors = floors + 1 end end
        if floors < 3 then return end                   -- (again next frame, till all three are up)
        -- (every material kept here is on a face, the floors' or their falling pieces': one on none the engine throws
        -- away, and the next call on it crashed the game - the plain shared one, kept for the pieces when the pieces had
        -- the old picture, 2026-11-04)
        local mats, by_key, n = {}, {}, 0
        local function wedge(cx, cy)
            if cx * cx + cy * cy < 300.0 * 300.0 then return "mid", nil end
            local a = math.deg(math.atan(cy, cx)) % 360.0
            return math.floor(a / 10.0 + 0.5), a / 360.0
        end
        local function mat_for(key, hue)
            local e = by_key[key]
            if not e then
                local mid = ctx.lib.get_mid(world, "opaque", "final_liquid_rb", 0.70 + #mats * 0.01)
                if mid then
                    e = { mid = mid, hue = hue }
                    by_key[key] = e
                    mats[#mats + 1] = e
                end
            end
            return e
        end
        for k = 1, 3 do
            local p = PL.pancakes[k]
            for _, sec in ipairs(p.tpl.sections or {}) do
                if LIQUID_TEX[sec.texture or ""] then
                    -- (its wedge: where its corners lie round the middle - a wedge's top and side share it)
                    local P = sec.pos or {}
                    local sx, sy, m = 0.0, 0.0, 0
                    for i = 1, #P - 2, 3 do sx, sy, m = sx + P[i], sy + P[i + 1], m + 1 end
                    local e = (m > 0) and mat_for(wedge(sx / m, sy / m)) or nil
                    if e then pcall(function() p.pmc:SetMaterial(sec.id, e.mid) end); n = n + 1 end
                end
            end
        end
        -- (and the broken floor's pieces as they fall, each its wedge's colour - debris_build, made before this)
        local D = M.debris
        if D and D.world == here then
            for _, c in ipairs(D.list or {}) do
                if c.pmc and c.secs then
                    local e = mat_for(wedge(c.cx, c.cy))
                    for _, sec in ipairs(c.secs) do
                        if e and LIQUID_TEX[sec.texture or ""] then pcall(function() c.pmc:SetMaterial(sec.id, e.mid) end) end
                    end
                end
            end
        end
        L = { world = here, mats = mats, t = 0.0, k = 0 }
        M.liquid = L
        ctx.log("final fight: the floors' rainbow liquid flowing (%d faces, %d colours)", n, #mats)
    end
    local C = M.LIQUID
    L.t, L.k = L.t + dt, L.k + 1
    local t = L.t
    local w = 2.0 * math.pi * t / C.sway_t
    local off = { R = (C.u * t) % 40.0 + C.sway * math.sin(w), G = (C.v * t) % 40.0 + C.sway * math.cos(w * 0.8),
                  B = C.scale, A = C.scale }
    local turn = t / C.period
    local recolour = L.k % 2 == 0
    for _, e in ipairs(L.mats) do
        pcall(function() e.mid:SetVectorParameterValue(FName("BaseColorTexture_OffsetScale"), off) end)
        if recolour then
            local h = e.hue and (e.hue - turn) % 1.0 or turn % 1.0
            local r, g, b = hsv(h, e.hue and C.sat or C.mid_sat, 1.0)
            -- (the colour as shown: the material takes it linear)
            local col = { R = r ^ 2.2, G = g ^ 2.2, B = b ^ 2.2, A = 1.0 }
            pcall(function() e.mid:SetVectorParameterValue(FName("BaseColorFactor"), col) end)
        end
    end
end

-- (the map gone - STORROR's own reload: the floors' rainbow materials dropped, not called on - main.lua FORGET_ON_MAP)
function M.forget() M.liquid, M.aura, M.glow, M.air, M.ghosts, M.mega = nil, nil, nil, nil, nil, nil end

-- his camera's exposure fixed at M.PC.ev (on) or put back as it was (off)
M.expo = nil
local function expo(on)
    pcall(function()
        local cam = ctx.lib.pawn():GetComponentByClass(StaticFindObject("/Script/Engine.CameraComponent"))
        if not cam then return end
        local pp = cam.PostProcessSettings
        if on then
            if not M.expo then
                M.expo = { world = nil, a = pp.bOverride_AutoExposureMinBrightness, b = pp.bOverride_AutoExposureMaxBrightness,
                           mn = pp.AutoExposureMinBrightness, mx = pp.AutoExposureMaxBrightness }
                pcall(function() M.expo.world = ctx.lib.world():GetAddress() end)
            end
            pp.bOverride_AutoExposureMinBrightness, pp.bOverride_AutoExposureMaxBrightness = true, true
            pp.AutoExposureMinBrightness, pp.AutoExposureMaxBrightness = M.PC.ev, M.PC.ev
        elseif M.expo then
            local e = M.expo
            M.expo = nil
            pp.bOverride_AutoExposureMinBrightness, pp.bOverride_AutoExposureMaxBrightness = e.a or false, e.b or false
            pp.AutoExposureMinBrightness, pp.AutoExposureMaxBrightness = e.mn or -10.0, e.mx or 20.0
        end
    end)
end
M.expo_set = expo
local function floor_top(k)
    local G = package.loaded["game"]
    -- (the gap the scene was laid with - game.lua G.pancakes - not the one set now, which waits for its next load)
    local gap = (G and G.data and G.data.pancake_gap) or (G and G.PANCAKE and G.PANCAKE.gap) or 2600.0
    return M.PC.top - ((k or 1) - 1) * gap
end
local function here_world()
    local a = nil
    pcall(function() a = ctx.lib.world():GetAddress() end)
    return a
end

-- the red marks on the floor that tell where an attack lands: one strip (the fire snipe), rings (the meteors). Kept for
-- the fight, hidden between uses (as the flames are: made once, never thrown away mid-fight)
M.tells = nil
local function tell_actor(world)
    local lib = ctx.lib
    local actor = lib.spawn_actor(world, { X = ctx.OFFSET.X, Y = ctx.OFFSET.Y, Z = ctx.OFFSET.Z }, 0.0)
    local pmc = actor and lib.add_pmc(actor)
    if not pmc then return nil end
    pcall(function() pmc:SetCollisionEnabled(0); pmc:SetCastShadow(false) end)
    pcall(function() actor:SetActorHiddenInGame(true) end)
    return { actor = actor, pmc = pmc }
end
local function tells(world)
    local w = here_world()
    if not M.tells or M.tells.world ~= w then M.tells = { world = w, rings = {} } end
    return M.tells
end
-- a flat strip along `pts` (scene cm, each { x, y, z } on the floor), `w` wide
local function tell_strip(world, pts, w)
    local T = tells(world)
    if #pts < 2 then return end
    T.strip = T.strip or tell_actor(world)
    local t = T.strip
    if not t then return end
    local pos, uv, col, nrm, idx = {}, {}, {}, {}, {}
    local along = 0.0
    for i, p in ipairs(pts) do
        local q = pts[math.min(#pts, i + 1)]
        local o = pts[math.max(1, i - 1)]
        local dx, dy = q[1] - o[1], q[2] - o[2]
        local l = math.max(1.0, sqrt(dx * dx + dy * dy))
        local sx, sy = -dy / l * w * 0.5, dx / l * w * 0.5
        if i > 1 then along = along + sqrt((p[1] - pts[i - 1][1]) ^ 2 + (p[2] - pts[i - 1][2]) ^ 2) end
        for side = 0, 1 do
            local k = (side == 0) and 1.0 or -1.0
            pos[#pos + 1], pos[#pos + 2], pos[#pos + 3] = p[1] + sx * k, p[2] + sy * k, p[3] + 4.0
            uv[#uv + 1], uv[#uv + 2] = along / 400.0, side
            for _ = 1, 4 do col[#col + 1] = 1.0 end
            nrm[#nrm + 1], nrm[#nrm + 2], nrm[#nrm + 3] = 0.0, 0.0, 1.0
        end
        if i > 1 then
            local a, b0, c, d = (i - 2) * 2, (i - 2) * 2 + 1, (i - 1) * 2, (i - 1) * 2 + 1
            for _, v in ipairs({ a, c, b0, b0, c, d, a, b0, c, b0, d, c }) do idx[#idx + 1] = v end
        end
    end
    ctx.lib.add_sections(world, t.pmc, { { id = 0, layer = "translucent", texture = "tell_strip", nverts = #pos // 3,
        ntris = #idx // 3, pos = pos, uv = uv, col = col, nrm = nrm, idx = idx } })
    pcall(function() t.actor:SetActorHiddenInGame(false) end)
end
local function tell_strip_hide()
    local T = M.tells
    if T and T.world == here_world() and T.strip then pcall(function() T.strip.actor:SetActorHiddenInGame(true) end) end
end
-- ring `i`: a mark `r` round at (x, y) on the floor at z
local function tell_ring(world, i, x, y, z, r)
    local T = tells(world)
    T.rings[i] = T.rings[i] or tell_actor(world)
    local t = T.rings[i]
    if not t then return end
    local zz = z + 5.0
    ctx.lib.add_sections(world, t.pmc, { { id = 0, layer = "translucent", texture = "tell_ring", nverts = 4, ntris = 4,
        pos = { x - r, y - r, zz, x + r, y - r, zz, x + r, y + r, zz, x - r, y + r, zz },
        uv = { 0, 0, 1, 0, 1, 1, 0, 1 }, col = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
        nrm = { 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1 }, idx = { 0, 2, 1, 0, 3, 2, 0, 1, 2, 0, 2, 3 } } })
    pcall(function() t.actor:SetActorHiddenInGame(false) end)
end
M.hide_mark = function(i)
    local T = M.tells
    if T and T.world == here_world() and i and T.rings[i] then pcall(function() T.rings[i].actor:SetActorHiddenInGame(true) end) end
end

-- a crack in floor `k` where he landed (scene x, y): a cut-out picture on the floor's own mesh, so it tilts with it and
-- goes with it; bigger at each hit, the third biggest of all
local function pancake_crack(b, world, big)
    local PL = ctx.PLAT
    local p = PL and PL.pancakes and PL.pancakes[b.lvl or 1]
    if not (p and p.pmc) or p.gone then return end
    p.cracks = (p.cracks or 0) + 1
    local n = math.min(3, p.cracks)
    -- (one crack a floor, growing at each hit - 16 m, 24 m, then 34 m, the arena across - out from where he came down:
    -- black splits with a glowing rim, tools/boss_cracks.py. A thin dark one of a few metres was lost on the floor's
    -- cells and veins: "the crack is still bad, its also very small", 2026-11-03)
    local h = ({ 1600.0, 2400.0, 3400.0 })[n] * 0.5
    if not p.crack_a then p.crack_a, p.crack_x, p.crack_y = math.random() * 2.0 * pi, b.x, b.y end
    local a = p.crack_a + (n - 1) * 0.6
    local ca, sa = cos(a) * h, sin(a) * h
    -- (its mesh's own frame: the scene's, the floor laid `gap` lower; where the first came, the rest grow from)
    local x, y, z = p.crack_x, p.crack_y, M.PC.top + 4.0
    local pos = {}
    for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
        pos[#pos + 1] = x + c[1] * ca - c[2] * sa
        pos[#pos + 1] = y + c[1] * sa + c[2] * ca
        pos[#pos + 1] = z
    end
    pcall(ctx.lib.add_sections, world, p.pmc, { { id = 300, layer = "translucent", texture = "fissure_" .. n,
        nverts = 4, ntris = 4, pos = pos, uv = { 0, 0, 1, 0, 1, 1, 0, 1 },
        col = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }, nrm = { 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1 },
        idx = { 0, 2, 1, 0, 3, 2, 0, 1, 2, 0, 2, 3 } } })
    sfx("hit_crack", 1.0)
    sfx("bowser_plat", 0.8)
    if big then sfx("pound_rock", 1.0) end
    if ctx.shake then ctx.shake(big and 0.9 or 0.5) end
    ctx.log("final fight: floor %d cracks (%d)", b.lvl or 1, p.cracks)
end

-- the floor's pieces as it breaks: copies of the Sky's ten outer pieces and its star (not solid), thrown out and down,
-- tumbling - made once for the fight, hidden, and used for both breaks
M.debris = nil
local function debris_build(world)
    local G = package.loaded["game"]
    local d = G and G.data
    if not (d and d.templates and d.pancake_pieces) then return end
    local O = ctx.OFFSET
    local list = {}
    local groups = {}
    for _, key in ipairs(d.pancake_pieces) do
        local t = d.templates[key]
        if t and t.sections then groups[#groups + 1] = t.sections end
    end
    if d.pancake_star and #d.pancake_star > 0 then groups[#groups + 1] = d.pancake_star end
    for _, secs in ipairs(groups) do
        local sx, sy, sz, n = 0.0, 0.0, 0.0, 0
        for _, s in ipairs(secs) do
            for i = 1, #s.pos, 3 do sx, sy, sz, n = sx + s.pos[i], sy + s.pos[i + 1], sz + s.pos[i + 2], n + 1 end
        end
        if n > 0 then
            local cx, cy, cz = sx / n, sy / n, sz / n
            local shifted = {}
            for i, s in ipairs(secs) do
                local c = {}
                for k, v in pairs(s) do c[k] = v end
                local P = {}
                for j = 1, #s.pos, 3 do P[j], P[j + 1], P[j + 2] = s.pos[j] - cx, s.pos[j + 1] - cy, s.pos[j + 2] - cz end
                c.pos, c.id, c.idx_once = P, i - 1, nil
                shifted[#shifted + 1] = c
            end
            local actor = ctx.lib.spawn_actor(world, { X = cx + O.X, Y = cy + O.Y, Z = cz + O.Z }, 0.0)
            local pmc = actor and ctx.lib.add_pmc(actor)
            if pmc then
                pcall(function() pmc:SetCollisionEnabled(0); pmc:SetCastShadow(false) end)
                ctx.lib.add_sections(world, pmc, shifted)
                pcall(function() actor:SetActorHiddenInGame(true) end)
                list[#list + 1] = { actor = actor, cx = cx, cy = cy, cz = cz, pmc = pmc, secs = shifted }
            end
        end
    end
    M.debris = { world = here_world(), list = list }
    ctx.log("final fight: %d pieces ready to fall", #list)
end
local function debris_start(k)
    local D = M.debris
    if not (D and D.world == here_world()) then return end
    local dz = floor_top(k) - floor_top(1)
    for _, c in ipairs(D.list) do
        local out = math.atan(c.cy, c.cx)
        local far = sqrt(c.cx * c.cx + c.cy * c.cy)
        local hs = (far > 300.0) and (120.0 + math.random() * 260.0) or 0.0
        c.x, c.y, c.z = c.cx, c.cy, c.cz + dz
        c.vx, c.vy, c.vz = cos(out) * hs, sin(out) * hs, 120.0 + math.random() * 380.0
        c.p, c.yw, c.r = 0.0, 0.0, 0.0
        c.sp, c.sy, c.sr = (math.random() - 0.5) * 160.0, (math.random() - 0.5) * 90.0, (math.random() - 0.5) * 160.0
        c.wait = (far > 300.0) and math.random() * 0.25 or 0.1
        pcall(function() c.actor:SetActorHiddenInGame(false) end)
    end
    D.t = 0.0
end
local function debris_tick(dt)
    local D = M.debris
    if not (D and D.t and D.world == here_world()) then return end
    D.t = D.t + dt
    local O = ctx.OFFSET
    for _, c in ipairs(D.list) do
        if c.wait > 0.0 then
            c.wait = c.wait - dt
        else
            c.vz = c.vz - 980.0 * dt
            c.x, c.y, c.z = c.x + c.vx * dt, c.y + c.vy * dt, c.z + c.vz * dt
            c.p, c.yw, c.r = c.p + c.sp * dt, c.yw + c.sy * dt, c.r + c.sr * dt
        end
        pcall(function()
            c.actor:K2_SetActorLocationAndRotation({ X = c.x + O.X, Y = c.y + O.Y, Z = c.z + O.Z },
                { Pitch = c.p, Yaw = c.yw, Roll = c.r }, false, {}, true)
        end)
    end
    if D.t > 3.5 then
        for _, c in ipairs(D.list) do pcall(function() c.actor:SetActorHiddenInGame(true) end) end
        D.t = nil
    end
end

-- the updraft he falls through, seen: mist puffs rushing up all round him (Mario 64's own mist picture) - "the wind
-- should be all around", 2026-11-03. A pool, one puff at a time from it
M.puffs = nil
local PUFF_N = 36
local function puff_one(world, x, y, z)
    local w = here_world()
    if not M.puffs or M.puffs.world ~= w then M.puffs = { world = w, list = {} } end
    local L = M.puffs.list
    local p = nil
    for _, q in ipairs(L) do if not q.t then p = q; break end end
    if not p then
        if #L >= PUFF_N then return end
        local a = ctx.lib.quad_actor(world, { X = ctx.OFFSET.X, Y = ctx.OFFSET.Y, Z = ctx.OFFSET.Z }, 90.0,
            "actors__mist__mist.ia16", "translucent")
        if not a then return end
        pcall(function() a:SetActorHiddenInGame(true) end)
        p = { actor = a }
        L[#L + 1] = p
    end
    p.x, p.y, p.z = x, y, z
    p.vz, p.t, p.life = 1300.0 + math.random() * 700.0, 0.0, 0.7 + math.random() * 0.5
    p.s0 = 0.8 + math.random() * 0.9
end
local function puffs_tick(dt)
    local P = M.puffs
    if not (P and P.world == here_world()) then return end
    local O = ctx.OFFSET
    local cx, cy = ctx.lib.camera_location({ X = O.X, Y = O.Y, Z = O.Z })
    for _, p in ipairs(P.list) do
        if p.t then
            p.t = p.t + dt
            p.z = p.z + p.vz * dt
            if p.t >= p.life then
                p.t = nil
                pcall(function() p.actor:SetActorHiddenInGame(true) end)
            else
                local k = p.t / p.life
                local s = p.s0 * (0.6 + 1.6 * k)
                local wx, wy, wz = p.x + O.X, p.y + O.Y, p.z + O.Z
                pcall(function()
                    p.actor:K2_SetActorLocationAndRotation({ X = wx, Y = wy, Z = wz },
                        { Pitch = 0.0, Yaw = math.deg(atan(cy - wy, cx - wx)) + 180.0, Roll = 0.0 }, false, {}, true)
                    p.actor:SetActorScale3D({ X = 1.0, Y = s * (1.0 - k * 0.6), Z = s * 2.2 })
                    p.actor:SetActorHiddenInGame(false)
                end)
            end
        end
    end
end

-- the floor he is on breaks: the next made solid, this one gone (its bombs too), its pieces thrown down, and on to the
-- next floor for him - and the athlete, whom the wind catches over it (catch_tick)
M.catch = nil
-- The bombs in the air on the fall (pancake_break): Bowser's own, floating down the drop, bobbing and turning - `path`
-- of them one under another below where the athlete starts down, the rest about the column - touched, one goes off: hurt,
-- and knocked aside out of the wind's hold a moment ("make the fall longer and during the fall make the player avoid
-- bombs floating in the air", 2026-11-04). Made once a fight, hidden (air_build); laid at each floor's break (air_place);
-- hidden again once he is down. `r`: how near his middle comes to one's, cm; `top`, `bottom`: the clear drop under the
-- broken floor and over the next; `spread`: the column's half-width. (The first 40 m under the floor clear, so that they
-- are seen down there as it breaks; more of them for the longer drop - "make the fall way way way longer and move the
-- bombs furth down so you can see them during stage break", 2026-11-04: they were 9 m under it)
M.AIRBOMB = { n = 20, path = 6, r = 170.0, top = 4000.0, bottom = 900.0, spread = 1700.0, bob = 40.0, scale = 1.0 }
M.air = nil
local function air_build(world)
    local data = ctx.actor_data("bowser_bomb")
    -- (more wanted than were made - this file reloaded with a bigger `n`: the ones there kept, the rest made)
    local list = (M.air and M.air.world == here_world() and M.air.list) or {}
    local O = ctx.OFFSET
    if data then
        for _ = #list + 1, M.AIRBOMB.n do
            local inst = ctx.lib.make_instance(world, data, { X = O.X, Y = O.Y, Z = O.Z - 50000.0 }, 0.0, M.AIRBOMB.scale)
            if inst then
                pcall(function() inst.actor:SetActorHiddenInGame(true) end)
                list[#list + 1] = { inst = inst, on = false }
            end
        end
    end
    M.air = { world = here_world(), list = list, short = #list < M.AIRBOMB.n }
    ctx.log("final fight: %d bombs ready for the air", #list)
end
local function air_place(b, world, k)
    local A = M.air
    if not (A and A.world == here_world()) then return end
    local hi, lo = floor_top(k) - M.AIRBOMB.top, floor_top(k + 1) + M.AIRBOMB.bottom
    if lo >= hi then return end
    local px, py = 0.0, 0.0
    pcall(function() local l = ctx.lib.pawn():K2_GetActorLocation(); px, py = l.X - ctx.OFFSET.X, l.Y - ctx.OFFSET.Y end)
    local n, placed = #A.list, {}
    local function free(x, y, z)
        for _, q in ipairs(placed) do
            if (q[1] - x) ^ 2 + (q[2] - y) ^ 2 + (q[3] - z) ^ 2 < 450.0 * 450.0 then return false end
        end
        return true
    end
    for i, e in ipairs(A.list) do
        local x, y, z
        for _ = 1, 12 do
            if i <= M.AIRBOMB.path then
                -- (one under another, below him, in the upper three quarters of the drop)
                local f = (i - 0.5) / M.AIRBOMB.path
                z = hi - (hi - lo) * 0.75 * f
                local a, r = math.random() * 2.0 * pi, math.random() * 160.0
                x, y = px + cos(a) * r, py + sin(a) * r
            else
                local a, r = math.random() * 2.0 * pi, sqrt(math.random()) * M.AIRBOMB.spread
                x, y, z = cos(a) * r, sin(a) * r, lo + math.random() * (hi - lo)
            end
            if free(x, y, z) then break end
        end
        placed[#placed + 1] = { x, y, z }
        e.x, e.y, e.z, e.ph, e.on = x, y, z, math.random() * 6.28, true
        pcall(function() e.inst.actor:SetActorHiddenInGame(false) end)
    end
    A.t = 0.0
    ctx.log("final fight: %d bombs in the air, %.0f m of drop", n, (hi - lo) / 100.0)
end
local function air_hide()
    local A = M.air
    if not (A and A.world == here_world()) then return end
    for _, e in ipairs(A.list) do
        if e.on then
            e.on = false
            pcall(function() e.inst.actor:SetActorHiddenInGame(true) end)
        end
    end
end
local function air_tick(world, dt, ax, ay, az)
    local A = M.air
    if not (A and A.world == here_world()) then return end
    if not M.catch then air_hide(); return end
    A.t = (A.t or 0.0) + dt
    A.k = (A.k or 0) + 1
    local O = ctx.OFFSET
    local mid = az + 90.0
    local rr = M.AIRBOMB.r * M.AIRBOMB.r
    for i, e in ipairs(A.list) do
        -- (the ones far over or under him drawn every 8th frame only, and never touched: "lots of lag during fight",
        -- 2026-11-04 - the fall was the fight's dearest stretch)
        local near = abs(e.z - mid) < 5000.0
        if e.on and (near or (A.k + i) % 8 == 0) then
            local z = e.z + sin(A.t * 1.3 + e.ph) * M.AIRBOMB.bob
            local wx, wy, wz = e.x + O.X, e.y + O.Y, z + O.Z
            ctx.lib.face_camera(e.inst, wx, wy)
            ctx.lib.set_pose(e.inst, wx, wy, wz, (A.t * 25.0 + e.ph * 57.0) % 360.0)
            local dx, dy, dz = ax - e.x, ay - e.y, mid - z
            if near and dx * dx + dy * dy + dz * dz < rr then
                -- (touched: off it goes)
                e.on = false
                pcall(function() e.inst.actor:SetActorHiddenInGame(true) end)
                if ctx.explode then pcall(ctx.explode, world, { x = e.x, y = e.y, z = z - 75.0 }) end
                sfx("explosion", 1.0)
                if ctx.shake then pcall(ctx.shake, 0.3) end
                if ctx.hurt then pcall(ctx.hurt, "body", "a bomb in the air", dx, dy) end
                ctx.log("final fight: he flew into a bomb in the air")
            end
        end
    end
end

local function pancake_break(b, world)
    b.break_t0 = os.clock()
    local PL = ctx.PLAT
    local PCK = PL and PL.pancakes
    if not PCK then return end
    local k = b.lvl or 1
    local cur, nxt = PCK[k], PCK[k + 1]
    if nxt and PL.pancake_solid then PL.pancake_solid(nxt, true) end
    if cur then
        if PL.pancake_solid then PL.pancake_solid(cur, false) end
        cur.gone = true
        pcall(function() cur.actor:SetActorHiddenInGame(true) end)
    end
    for _, bm in ipairs((ctx.bombs and ctx.bombs()) or {}) do
        if bm.floor == k and not bm.gone then
            bm.gone = true
            pcall(function() bm.inst.actor:SetActorHiddenInGame(true) end)
        end
    end
    local tb = os.clock()
    tell_strip_hide()
    debris_start(k)
    local td = os.clock()
    pcall(air_place, b, world, k)
    ctx.log("final fight: the break's parts - floors and bombs %.0f ms, pieces %.0f ms, air bombs %.0f ms",
        (tb - (b.break_t0 or tb)) * 1000.0, (td - tb) * 1000.0, (os.clock() - td) * 1000.0)
    sfx("pyramid_explode", 1.0)
    sfx("gate_break", 1.0)
    if ctx.shake then ctx.shake(1.0) end
    if M.clone and M.clone_gone then pcall(M.clone_gone) end
    b.lvl = math.min(3, k + 1)
    b.speed = M.PC.speeds[b.lvl] or b.speed
    M.catch = { t0 = os.clock(), top = floor_top(b.lvl) }
    local G = package.loaded["game"]
    if G then G.no_fall_until = os.clock() + 8.0 end
    ctx.log("final fight: floor %d broke - down to floor %d (x%.2f)", k, b.lvl, b.speed or 1.0)
end
-- (the fall to the next floor: a moment's free fall, then an updraft all round him - its column the floors' own width -
-- slows him to a drift down that he steers through with the stick or the movement keys, the way the camera looks, as in
-- Tall, Tall Mountain's wind (game.lua G.apply_vwind); 3.5 m over the floor a gust lifts him and he settles onto it, no
-- fall counted - "make the fall after breaking the stage way higher also the wind should be all around and you should be
-- able to control yourself in the air like in tall tall mountain", 2026-11-03. (A slow drift its last 10 m first, and
-- Bowser, down long before, set him alight in the air: he waits for him now, choose.)
M.UPDRAFT = { free = 0.8, fall = 650.0, brake = 2600.0, steer = 1500.0, max = 650.0, wall = 2100.0, push = 1400.0,
              lift_at = 350.0, lift = 320.0, puffs = 22.0, reach = 1800.0,
              -- (weaker high up, stronger near the floor - "make the wind stronger the closer you get to the ground but
              -- weaker the further up you are", 2026-11-03: falling at `fall_high` cm/s `high` cm over the floor and up,
              -- `fall_low` at `low` and under, between the two in between)
              high = 4000.0, low = 600.0, fall_high = 1700.0, fall_low = 300.0 }
-- the speed the updraft lets him (or Bowser) fall at, `h` cm over the floor; and how strong it is there, 0..1
function M.updraft_fall(h)
    local U2 = M.UPDRAFT
    local k = math.max(0.0, math.min(1.0, (h - U2.low) / (U2.high - U2.low)))
    return U2.fall_low + (U2.fall_high - U2.fall_low) * k, 1.0 - k
end
local function steer_input()
    local sx, sy, yaw = 0.0, 0.0, nil
    pcall(function()
        local pc = ctx.lib.controller()
        sx = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftX") }) or 0.0
        sy = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftY") }) or 0.0
        if abs(sx) < 0.2 then sx = 0.0 end
        if abs(sy) < 0.2 then sy = 0.0 end
        if pc:IsInputKeyDown({ KeyName = FName("D") }) then sx = 1.0 elseif pc:IsInputKeyDown({ KeyName = FName("A") }) then sx = -1.0 end
        if pc:IsInputKeyDown({ KeyName = FName("W") }) then sy = 1.0 elseif pc:IsInputKeyDown({ KeyName = FName("S") }) then sy = -1.0 end
        yaw = math.rad(pc:GetControlRotation().Yaw)
    end)
    if not yaw or (sx == 0.0 and sy == 0.0) then return 0.0, 0.0 end
    return cos(yaw) * sy - sin(yaw) * sx, sin(yaw) * sy + cos(yaw) * sx
end
local function catch_tick(pawn, world, dt)
    local c = M.catch
    if not (c and pawn) then return end
    local G = package.loaded["game"]
    if G then G.no_fall_until = math.max(G.no_fall_until or 0.0, os.clock() + 1.5) end
    local l, v = nil, nil
    pcall(function() l, v = pawn:K2_GetActorLocation(), pawn:GetVelocity() end)
    if not (l and v) then return end
    local O, U2 = ctx.OFFSET, M.UPDRAFT
    local x, y = l.X - O.X, l.Y - O.Y
    -- (his feet: his capsule's own half height under its middle - taken as 90, he was 5 cm and more over the floor
    -- standing on it, and the set-down below never came)
    if not c.half then pcall(function() c.half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight() end) end
    local feet = l.Z - O.Z - (c.half or 90.0)
    local age = os.clock() - c.t0
    local walking = false
    pcall(function() walking = pawn.CharacterMovement.MovementMode == 1 end)
    if not c.hover and ((walking and abs(feet - c.top) < 200.0 and age > 0.5) or age > 25.0) then M.catch = nil; return end
    -- (the end's hover - M.finale_step - holds him on into the ending's start too, which plays where he is: let go, he
    -- fell into the death floor as it began - "it didnt start the peach outro?", 2026-11-04; the scene's end clears it)
    local RG = package.loaded["ragdoll"]
    local limp = RG and RG.active
    if age < U2.free or (feet < c.top - 150.0 and not c.hover) then return end
    -- (the wind seen: puffs about him all the way down)
    local fall_at, strength = M.updraft_fall(feet - c.top)
    c.pacc = (c.pacc or 0.0) + dt * U2.puffs * (0.5 + strength)
    while c.pacc >= 1.0 do
        c.pacc = c.pacc - 1.0
        local a, r = math.random() * 2.0 * pi, 150.0 + math.random() * U2.reach
        puff_one(world, x + cos(a) * r, y + sin(a) * r, feet - 500.0 + math.random() * 700.0)
    end
    if not c.blown then
        c.blown = true
        sfx("blow_wind", 1.0)
    end
    if ctx.hold_sfx then ctx.hold_sfx("loop_blow_wind", 0.8) end
    if limp then return end
    -- (the gust's set-down: in the engine's flying from the gust, lifted a little, then down onto the floor and stood on
    -- it walking - no landing for STORROR to throw him into its ragdoll for: "when falling on the floor from wind the
    -- player ragdolls", 2026-11-04. Steered all the while; cut short after 4 s, back to falling)
    if c.fly then
        pcall(function()
            local cm = pawn.CharacterMovement
            local ft = os.clock() - c.fly
            local ground = ctx.floor_at(x, y, feet + 120.0)
            local vx, vy = v.X * 0.96, v.Y * 0.96
            local dx, dy = steer_input()
            if dx ~= 0.0 or dy ~= 0.0 then
                vx, vy = vx + dx * U2.steer * dt, vy + dy * U2.steer * dt
                local hs = sqrt(vx * vx + vy * vy)
                if hs > U2.max then vx, vy = vx * U2.max / hs, vy * U2.max / hs end
            end
            -- (down to a hand over the floor, then stood on it in its walking: no landing for STORROR, which counts the
            -- fall from the floor that broke, 50 m up, and threw him down in its ragdoll even after the last 25 cm of
            -- it - "player gets ragdolled when coming down from the wind part", 2026-11-04. His feet are his capsule's
            -- own now - taken as 90 cm, he hung over the floor and "doesnt land properly". Held against the floor,
            -- stopped, the same)
            local stopped = ft > 0.6 and abs(v.Z) < 15.0
            if ft < 0.35 then
                cm.Velocity = { X = vx, Y = vy, Z = 180.0 }
            elseif ground and feet - ground > 25.0 and not stopped then
                cm.Velocity = { X = vx, Y = vy, Z = -math.min(260.0, math.max(80.0, (feet - ground) * 3.0)) }
            else
                -- (STORROR's own fall begun again here - its parkour reset, its fall's start set (as climb.lua's pole
                -- jumps do) - and let go: it lands him from a hand's height, its own way. Stood on the floor in its
                -- walking instead, with no landing, he was left in a glitched state: "player in glitched state after
                -- wind and touching ground", 2026-11-04)
                c.fly = nil
                local G = package.loaded["game"]
                if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
                pcall(function()
                    for _, cc in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
                        local o = cc:get()
                        if o:GetClass():GetFName():ToString() == "ParkourComponent" then o:StartFallingCallback() end
                    end
                end)
                cm:SetMovementMode(3, 0)
                cm.Velocity = { X = vx * 0.5, Y = vy * 0.5, Z = -100.0 }
                sfx("blow_wind", 0.4)
            end
            if c.fly and (ft > 4.0 or not ground) then
                c.fly = nil
                cm:SetMovementMode(3, 0)
            end
        end)
        return
    end
    -- (STORROR counts his fall from where it began - the floor that broke, 50 m up - and at the bottom threw him down
    -- in its flail as if he had dropped it all: "ragdoll: down ... his own", 2026-11-03. Out of falling and straight back
    -- into it, a frame in the engine's flying, now and then and as the gust takes him: his fall begun again there)
    if c.refall and not c.hover then
        local keep = c.refall
        c.refall = nil
        pcall(function()
            local cm = pawn.CharacterMovement
            cm:SetMovementMode(3, 0)
            cm.Velocity = keep
        end)
        return
    end
    c.next_refall = c.next_refall or (os.clock() + 1.5)
    local function refall(vel)
        c.refall, c.next_refall = vel, os.clock() + 1.5
        pcall(function() pawn.CharacterMovement:SetMovementMode(5, 0) end)
    end
    pcall(function()
        local cm = pawn.CharacterMovement
        local vx, vy, vz = v.X, v.Y, v.Z
        local function approach(a, b, st) if a < b then return math.min(b, a + st) end return math.max(b, a - st) end
        if c.hover then
            -- (held there in the wind, gently rising and sinking - the end's: M.finale_step - in the engine's flying, as
            -- the gust's set-down is: falling, STORROR's own fall took him again once his words let his controls go, and
            -- he dropped into the death floor - "I died during the talk with bowser?", 2026-11-04)
            if feet < c.top + 600.0 then
                if cm.MovementMode ~= 5 then cm:SetMovementMode(5, 0) end
                if os.clock() >= (c.hlog or 0.0) then
                    c.hlog = os.clock() + 2.0
                    ctx.log("final fight: the wind holds him, %.0f cm off its height", feet - c.top)
                end
                local want = math.max(-260.0, math.min(260.0, (c.top - feet) * 2.0)) + 25.0 * sin(os.clock() * 1.6)
                vz = approach(vz, want, 1600.0 * dt)
            elseif vz < -fall_at then
                vz = approach(vz, -fall_at, (U2.brake * (0.4 + strength) + 980.0) * dt)
            end
        elseif not c.lifted and feet < c.top + U2.lift_at and vz < -300.0 then
            -- (the gust under him, over the floor: into flying - c.fly, above)
            c.lifted, vz = true, U2.lift
            vx, vy = vx * 0.5, vy * 0.5
            c.fly = os.clock()
            cm:SetMovementMode(5, 0)
            sfx("blow_wind", 0.8)
            for _ = 1, 8 do
                local a, r = math.random() * 2.0 * pi, 60.0 + math.random() * 220.0
                puff_one(world, x + cos(a) * r, y + sin(a) * r, c.top - 100.0)
            end
        elseif vz < -fall_at then
            vz = approach(vz, -fall_at, (U2.brake * (0.4 + strength) + 980.0) * dt)
        end
        -- (his steering)
        local dx, dy = steer_input()
        if dx ~= 0.0 or dy ~= 0.0 then
            local was = sqrt(vx * vx + vy * vy)
            vx, vy = vx + dx * U2.steer * dt, vy + dy * U2.steer * dt
            local hs = sqrt(vx * vx + vy * vy)
            local cap = math.max(U2.max, was)
            if hs > cap then vx, vy = vx * cap / hs, vy * cap / hs end
        end
        -- (the column's edge: blown back in over the floor)
        local r = sqrt(x * x + y * y)
        if r > U2.wall then
            vx, vy = vx - x / r * U2.push * dt, vy - y / r * U2.push * dt
        end
        cm.Velocity = { X = vx, Y = vy, Z = vz }
        if not c.lifted and not c.hover and os.clock() >= c.next_refall then
            refall({ X = vx, Y = vy, Z = vz })
        end
    end)
end

-- the fire snipe's line: from before his mouth, straight at where the athlete stands and 7 m on past him, as far as the
-- floor goes - a point every SNIPE_STEP cm, on the floor; and its red strip
local SNIPE_TELL, SNIPE_W, SNIPE_STEP = 27, 170.0, 190.0      -- (a jet every 1.9 m, bigger: four snipes running)
local function snipe_aim(b, world, ax, ay)
    local dir = math.rad(b.face)
    local fx, fy = cos(dir), sin(dir)
    local x0, y0 = b.x + fx * 260.0, b.y + fy * 260.0
    local d = sqrt((ax - x0) ^ 2 + (ay - y0) ^ 2)
    local len = math.max(900.0, math.min(3400.0, d + 700.0))
    local top = b.hz or b.z
    local pts = {}
    for i = 0, math.floor(len / SNIPE_STEP) do
        local x, y = x0 + fx * i * SNIPE_STEP, y0 + fy * i * SNIPE_STEP
        local z = ground(x, y, top + 150.0, 0.0)
        if not z or z < top - 400.0 then break end
        pts[#pts + 1] = { x, y, z }
    end
    b.snipe = { pts = pts, i = 0, fx = fx, fy = fy }
    tell_strip(world, pts, SNIPE_W)
end

-- the meteor shower's marks: one where he stands, two more close by, the rest about the floor; METEOR_TELL frames on
-- them before the meteors come
-- (75 frames on the marks, his arm raised over 45 and held to 80 before the slam: at half that all of it came and went
-- before it could be seen - "bowsers metoir attack still happens way too quickly", 2026-11-04)
-- (the meteors bigger - METEOR_SIZE, their marks with them - one after another in no order, METEOR_GAP frames apart, and
-- slower down: "increase the size of the meteors also have them come down at different times and more slowly",
-- 2026-11-04 - they were 9, in pairs, down in under 2 s)
local METEOR_N, METEOR_TELL, METEOR_R = 8, 75, 265.0
local METEOR_SIZE, METEOR_GAP = 14.0, 12
-- (his shadow told before it comes - the "clone" act: the frame of his snap, and of the shadow)
-- (`snap`, `tell`: the frames of his snap and of the shadow; `up`: those his arm takes up; `arm`: its raise, of the full
-- turn M.arm_turn makes. A table: the file's locals are full)
M.SNAP = { snap = 26, tell = 56, up = 16, arm = 0.7 }
-- (his blink away after a floor's fall - the "blink" act: frames gone, and how far out from the middle he comes back,
-- nearer in where the floor does not reach)
M.BLINK = { t = 10, r = { 1400.0, 1000.0, 600.0, 0.0 } }
local function meteor_marks(b, world, ax, ay)
    local top = b.hz or b.z
    local marks = {}
    local function try(x, y)
        local z = ground(x, y, top + 150.0, 0.0)
        if not z or z < top - 400.0 then return end
        for _, m in ipairs(marks) do if (m[1] - x) ^ 2 + (m[2] - y) ^ 2 < (METEOR_R * 1.7) ^ 2 then return end end
        marks[#marks + 1] = { x, y, z }
    end
    try(ax, ay)
    for _ = 1, 16 do
        if #marks >= 3 then break end
        local a, r = math.random() * 2.0 * pi, 280.0 + math.random() * 380.0
        try(ax + cos(a) * r, ay + sin(a) * r)
    end
    for _ = 1, 60 do
        if #marks >= METEOR_N then break end
        local a, r = math.random() * 2.0 * pi, math.random() * 2300.0
        try(cos(a) * r, sin(a) * r)
    end
    b.meteors = marks
    for i, m in ipairs(marks) do tell_ring(world, i, m[1], m[2], m[3], METEOR_R) end
end
local function meteor_fall(b, world)
    local list = b.meteors or {}
    local order = {}
    for i = 1, #list do order[i] = i end
    for i = #order, 2, -1 do local j = math.random(1, i); order[i], order[j] = order[j], order[i] end
    for k, i in ipairs(order) do
        local m = list[i]
        add_flame(world, "meteor", m[1], m[2], m[3] + 2200.0, nil, METEOR_SIZE, false,
            { vz = -8.0 * S, grav = -1.0 * S, vzmin = -28.0 * S, mark = i, delay = (k - 1) * METEOR_GAP + math.random(0, 5) })
    end
    sfx("bowser_roar", 0.8)
end

-- ------------------------------------------------------------ Bowser
function M.new(b, name)
    b.stage = (name == "bowser_2") and "bitfs" or ((name == "bowser_3") and "bits" or "bitdw")
    -- (the Fire Sea's two hits, where Mario 64's takes one: "in bowser 2, I want bowser to have 2 hp", 2026-10-25)
    b.health = (b.stage == "bits") and 3 or ((b.stage == "bitfs") and 2 or 1)
    b.face = b.yaw - 180.0              -- (the model faces its -X: he faces b.yaw - 180)
    b.fvel, b.vz, b.acc = 0.0, 0.0, 0.0
    b.reacting = false
    b.hidden = false
    b.cam_act = "idle"                  -- (oBowserCamAct: "idle", "walk" when the entrance shot sends him, "end" to fight)
    b.cut_tried = nil                   -- (new to the arena - also after a reload of this file - so his entrance plays)
    -- (the final fight on its three floors - game.lua G.pancakes: nine hits, three a floor, the first floor first)
    local PL = ctx.PLAT
    if b.stage == "bits" and PL and PL.pancakes and PL.pancakes[1] then
        b.pancake, b.lvl, b.health, b.speed, b.chain = true, 1, 3 * M.PC.per, M.PC.speeds[1], nil
    end
    go(b, "wait")
    set_anim(b, A.idle)
end

-- the athlete in relation to him: distance (Mario 64 units), angle to him, whether he faces him
local function sense(b, ax, ay, az)
    b.dist = sqrt((ax - b.x) ^ 2 + (ay - b.y) ^ 2 + (az - 90.0 - b.z) ^ 2) / S
    b.to_him = yaw_to(b.x, b.y, ax, ay)
    b.facing_him = abs(adiff(b.to_him, b.face)) < 0x2000 * U
    b.dist_center = sqrt(b.x * b.x + b.y * b.y) / S
    b.to_center = yaw_to(b.x, b.y, 0.0, 0.0)
end

-- (fire: ready again once FIRE_GAP has gone by since the last)
local function fire_ready(b) return os.clock() >= (b.fire_next or 0.0) end
local function fired(b) b.fire_next = os.clock() + FIRE_GAP * (0.8 + math.random() * 0.4) end

-- his next move: by chance, from his stage's moves, whatever the distance ("make his moves happen randomly instead of
-- being dependant on distance from bowser", 2026-10-14; Mario 64's bowser_bitdw_actions etc. chose by distance and
-- facing). His fire waits for FIRE_GAP; the move he has just made is less likely again.
local MOVES = {
    bitdw = { walk = 2.0, breath = 2.0, spit = 2.0, charge = 2.0, quickjump = 2.0, dance = 0.3 },
    bitfs = { walk = 1.5, teleport = 2.0, spit = 2.0, charge = 2.0, bigjump = 1.5, breath = 1.0 },
    bits = { walk = 1.5, spit = 2.0, sky = 2.0, breath = 1.5, bigjump = 1.5, charge = 2.0 },
}
-- (the final fight's floors, each with more: the first his own moves, the sprint (a charge two or three times over) and
-- the fire snipe; the second the arena's tilt (his big jump) and the meteor shower; the third his shadow clone and the
-- teleport - "the first floor will be 1.0x speed or just normal bowser he will have 2 new moves", 2026-11-03)
local PANCAKE_MOVES = {
    { walk = 1.5, spit = 1.8, sky = 1.5, breath = 1.5, bigjump = 1.0, charge = 2.0, snipe = 2.2 },
    -- (the big jump that tilts it the least likely of all: "make bowsers tilt attack the least likey one to trigger")
    -- (and his big jump's shockwave back, the stage shaken and him knocked over: "during phase 2 I want bowsers shockwave
    -- attack when he jumps to shake the stage and knock mario over", 2026-11-04 - the tilt now a jump of its own)
    { walk = 1.2, spit = 1.4, sky = 1.0, breath = 1.2, bigjump = 1.8, tiltjump = 0.5, charge = 1.8, snipe = 1.8, meteor = 2.2 },
    { walk = 1.0, spit = 1.2, sky = 1.0, breath = 1.0, bigjump = 1.4, charge = 1.6, snipe = 1.6, meteor = 1.6,
      clone = 2.4, teleport = 2.0 },
}
local FIRE_MOVES = { breath = true, spit = true, sky = true, snipe = true, meteor = true }
-- (the sprint's runs, each quicker than the last: his charge's speed times this, by run - the floor's own speed on top,
-- M.PC.speeds. The last 1.5, not 1.7: "the main problem is the last sprint", "maybe instead of 1.7x turn it to 1.5x",
-- 2026-11-04)
local SPRINT_MULT = { 1.0, 1.3, 1.5 }
-- (the last floor's own: there his runs came to 1.4, 1.8 and 2.1 times his charge with the floor's 1.4 on top - "bowsers
-- back to back tackle is too fast", "on last stage", 2026-11-04; then 1.4, 1.5, 1.7 and "bowser 3 tackle still too fast":
-- now the floor's speed taken back out of it, 1.0, 1.1, 1.2 times his run in all)
-- (and then "just change 1.7x to 1.5x": 1.4, 1.45, 1.5 in all; then "he is still too fast XD" - the tackle runs, picked:
-- 1.0, 1.1, 1.2 in all, the floor's own 1.4 taken back out of them)
local SPRINT_BY_FLOOR = { [3] = { 1.0 / 1.4, 1.1 / 1.4, 1.2 / 1.4 } }
-- (the move he has just made, how likely again: a quarter, then a tenth - "can we make the last used move rarer", 2026-10-26)
local LAST_ODDS = 0.1
-- (where on the far side he is flung to: the first spot on an outer piece, this far out (cm) and this far round (degrees)
-- from straight across - straight across is the seam between a pair of pieces, the star's own floor showing through)
local PIECE_R, PIECE_DA = { 1500.0, 1300.0, 1700.0 }, { 16.0, -16.0, 22.0, -22.0, 10.0, -10.0 }
local function choose(b)
    local st = stage(b)
    local fire = fire_ready(b)
    local list, total = {}, 0.0
    local moves = (b.pancake and PANCAKE_MOVES[b.lvl or 1]) or MOVES[st] or MOVES.bitdw
    for move, w in pairs(moves) do
        if FIRE_MOVES[move] and not fire then w = 0.0 end
        -- (one shadow at a time, and no snipe of his own while it is out: it may snipe)
        if M.clone and (move == "clone" or move == "snipe") then w = 0.0 end
        -- (and never the stage's tilt for his shadow: "ghost cant do the stage tilt move", 2026-11-04)
        if b.clone and (move == "tiltjump" or move == "bigjump") then w = 0.0 end
        -- (the move just made, LAST_ODDS as likely; the same three times running, never - a run of three charges
        -- came up by chance in the user's fight)
        if move == b.last_move then w = (move == b.last_move2) and 0.0 or w * LAST_ODDS end
        if w > 0.0 then list[#list + 1] = { move, w }; total = total + w end
    end
    table.sort(list, function(x, y) return x[1] < y[1] end)
    local r = math.random() * total
    for _, e in ipairs(list) do
        r = r - e[2]
        if r <= 0.0 then
            if FIRE_MOVES[e[1]] then fired(b) end
            b.last_move2, b.last_move = b.last_move, e[1]
            -- (the sprint: on the floors, his charge three times running - "sprinting back to back up to 3 times"; at
            -- random two or three, it was: "doesnt fire 3 times sometimes?", 2026-11-04)
            b.chain = (b.pancake and e[1] == "charge") and 3 or nil
            b.sprint_k = 1
            -- (the tilting jump: his big jump, the arena rocking after it in place of the shockwave)
            if e[1] == "tiltjump" then go(b, "bigjump"); b.tilt_jump = true; return end
            return go(b, e[1])
        end
    end
    b.last_move2, b.last_move = b.last_move, "walk"
    return go(b, "walk")
end

-- The Sky's outer pieces (platforms.lua B.bowser_plat): stood on one, out of a mine's flight or back up onto the stage,
-- he big-jumps in toward the middle and it falls behind him (bowser_act_jump_onto_stage: landed on a platform in the Sky,
-- BOWSER_ACT_BIG_JUMP; falling_bowser_plat_act_check: his big jump off it, it falls) - "he didnt jump after he got
-- damaged which usually makes the stage start to fall apart", 2026-11-02. True when he is off.
local function piece_jump(b)
    if stage(b) ~= "bits" or b.dead or (b.health or 0) <= 1 then return false end
    local PL = ctx.PLAT
    if not (PL and PL.bowser_piece_under) then return false end
    local ok, piece = pcall(PL.bowser_piece_under, b.x, b.y, b.z + 60.0)
    if not (ok and piece) then return false end
    go(b, "bigjump")
    b.breaking = piece
    b.last_move2, b.last_move = b.last_move, "bigjump"
    return true
end

-- landing hard (bowser_land): the jump-stop pose; in the Dark World it knocks him down if he is near
local function land_effects(b, ax, ay, world)
    set_anim(b, A.jump_stop)
    sfx("big_pound", 0.8)
    -- (the stage and the camera shake, the more the nearer: "when bowser lands from jump the level shakes and the
    -- player ragdolls unless you jumped", "no make the stage shake", "the camera shake would be cool too", 2026-10-14)
    if ctx.shake then ctx.shake(math.max(0.35, 1.0 - b.dist / 4000.0)) end
    -- (come down right on him, inside his body's reach: a stomp, which hurts and knocks him flat; "if bowser jumps on
    -- you it should ragdol the player". Mario 64's Dark World landing hurt anyone within 850: that is gone, the user
    -- took damage "even if you didnt get hit")
    if ctx.hurt and b.dist * S < 200.0 then
        ctx.hurt("stomp", "Bowser landing on him", ax - b.x, ay - b.y)
    elseif stage(b) == "bitdw" and b.dist < 2500.0 and ctx.knockdown then
        -- (anywhere else on the stage, on his feet: knocked flat, unhurt; in the air, he jumped it. The Sky has its
        -- shockwave to jump instead, the Fire Sea its tilting stage to slide down - knocked flat there, he lay through
        -- the tilt: "also ragdoling when bowser jumps", 2026-10-25)
        ctx.knockdown(ax - b.x, ay - b.y)
    end
end

local function physics(b)
    -- moves along his facing at fvel (cm a frame), falls (Mario 64: gravity 4 a frame), lands on what is under him
    local nx, ny = b.x + cos(math.rad(b.face)) * b.fvel, b.y + sin(math.rad(b.face)) * b.fvel
    b.x, b.y = nx, ny
    b.vz = b.vz - 4.0 * S
    b.z = b.z + b.vz
    local fz = ground(b.x, b.y, b.z - b.vz, 100.0)
    b.landed, b.on_ground = false, false
    if fz and b.z <= fz then
        if b.vz < -1.0 * S then b.landed, b.impact_vz = true, b.vz end
        b.z, b.vz, b.on_ground = fz, 0.0, true
    end
    b.floor = fz
end

-- the edge ahead (OBJ_MOVE_HIT_EDGE): no floor a step ahead, or one far below
local function edge_ahead(b)
    local ax, ay = b.x + cos(math.rad(b.face)) * 260.0, b.y + sin(math.rad(b.face)) * 260.0
    local fz = ground(ax, ay, b.z, 100.0)
    return (not fz) or fz < b.z - 200.0
end

-- the Fire Sea's arena rocking (platforms.lua's bowser_tilt)
local function arena_tilting()
    local p = ctx.PLAT and ctx.PLAT.bowser_arena
    return (p and p.tt) and true or false
end

-- Blown back by a bomb (bowser_fly_back_dead, bowser_act_hit_mine): up at 100 and off backward toward the middle - 200
-- when it ends him, 400 for the Sky's other hits - under Mario 64's own physics for him: gravity 4, his air drag
-- (drag strength 10: speed falls by speed^2 / 1000 a frame), 0.7 of his fall given back at each landing, slowed on
-- the ground; the first three landings thud and shake (bowser_bounce_effects). He slid along a fixed arc onto the very
-- middle in 1.2 s and stopped dead: "bowser doesnt bounce into the middle he basically just teleports to it",
-- 2026-10-15.
-- how far short of the middle he comes to rest (Mario 64 units), thrown back at v0 from d0 out, h0 up: fly_step's
-- own physics on a flat floor
local function fly_rest(v0, d0, h0, k)
    local x, vh, vz, z = 0.0, v0, 100.0, h0
    for _ = 1, 600 do
        vh = math.max(0.0, vh - vh * vh * k)
        x = x + vh
        vz = math.max(vz - 4.0, -75.0)
        z = z + vz
        if z <= 0.0 and vz <= 0.0 then
            z, vh, vz = 0.0, vh * 0.5, -vz * 0.7
            if vz < 12.0 then break end
        end
    end
    return d0 - x
end

-- `to_middle`: his air drag found that brings him to rest in the middle of the arena (his key comes out where he
-- lies, and it is to be in the middle: "the key doesnt land in the middle either", 2026-10-15; Mario 64's own drag
-- stops him metres short of it from a bomb at the edge, and no speed under 500 gets him there); else Mario 64's
-- (`aim`: { x, y } to come to rest at instead - the Sky's outer piece across from the mine)
local function fly_start(b, speed, to_middle, aim)
    local ax, ay = aim and aim[1] or 0.0, aim and aim[2] or 0.0
    local dir = yaw_to(b.x, b.y, ax, ay)
    local k = 0.001
    if to_middle or aim then
        local d0 = sqrt((b.x - ax) ^ 2 + (b.y - ay) ^ 2) / S
        local fz = ground(b.x, b.y, b.z, 200.0) or M.arena_z or b.z
        local h0 = math.max(0.0, (b.z - fz) / S)
        local lo, hi = 0.00002, 0.004
        for _ = 1, 30 do
            local mid = (lo + hi) * 0.5
            if fly_rest(speed, d0, h0, mid) > 0.0 then hi = mid else lo = mid end
        end
        k = (lo + hi) * 0.5
    end
    b.fly = { vh = speed * S, dir = dir, vz = 100.0 * S, lands = 0, k = k }
    b.face = dir + 180.0                -- (he flies backward, facing away from the middle)
    b.fvel, b.vz = 0.0, 0.0
end
-- one Mario 64 frame of it; true once he lies still
local function fly_step(b)
    local f = b.fly
    local v = f.vh / S
    v = math.max(0.0, v - v * v * f.k)
    f.vh = v * S
    b.x = b.x + cos(math.rad(f.dir)) * f.vh
    b.y = b.y + sin(math.rad(f.dir)) * f.vh
    f.vz = math.max(f.vz - 4.0 * S, -75.0 * S)
    b.z = b.z + f.vz
    local fz = ground(b.x, b.y, b.z, 200.0)
    if fz and b.z <= fz and f.vz <= 0.0 then
        b.z = fz
        f.lands = f.lands + 1
        if f.lands <= 3 then
            sfx("bowser_walk", 1.0)
            if f.lands == 1 then sfx("big_pound", 1.0) end
            if ctx.shake then pcall(ctx.shake, 0.35) end
        end
        f.vh = f.vh * 0.5               -- (the ground takes half his speed at each landing)
        f.vz = -f.vz * 0.7
        if f.vz < 12.0 * S then f.vz = 0.0; return true end
    elseif not fz and b.z < (b.hz or b.z) - 1500.0 * S then
        -- (gone past the edge: put down well in, as his leap back onto the stage would)
        b.x, b.y = b.x * 0.3, b.y * 0.3
        b.z = ground(b.x, b.y, (b.hz or b.z) + 400.0, 0.0) or b.hz or b.z
        return true
    end
    return false
end

-- (bowser_init_camera_actions) what he does while the entrance plays, and once it is over
local function camera_actions(b)
    local c = b.cam_act
    if c == "idle" then
        if b.act ~= "wait" then go(b, "wait") end
    elseif c == "walk" then
        if b.act ~= "intro" then go(b, "intro") end
    elseif b.stage == "bitfs" then
        go(b, "bigjump")                -- (in the Fire Sea he opens with a big jump that tilts the arena)
    else
        go(b, "default")
    end
end

-- one Mario 64 frame of his actions
local function step(b, world, ax, ay, az, pawn)
    sense(b, ax, ay, az)
    local st = stage(b)
    local act = b.act
    b.timer = b.timer + 1
    if act == "wait" then
        set_anim(b, A.idle)
        b.fvel = 0.0
        camera_actions(b)
    elseif act == "intro" then
        -- (bowser_act_intro_walk: looks up and walks a little, stops - sent by the entrance shot, then he waits
        -- again until his words are read)
        if b.sub == 0 then set_anim(b, A.look_up_walk); if near_end(b) then b.sub = 1 end
        elseif b.sub == 1 then set_anim(b, A.slow_gait); b.fvel = 3.0 * S; if near_end(b) then b.sub = 2 end
        else
            set_anim(b, A.look_down_stop); b.fvel = 0.0
            if near_end(b) then
                if b.cam_act == "walk" then b.cam_act = "idle" end
                camera_actions(b)
            end
        end
    elseif act == "default" then
        set_anim(b, A.idle)
        b.fvel = 0.0
        b.face = turn(b.face, b.to_him, (ctx.turn_speed or 105.0) / 30.0)
        -- (the final fight: not while the athlete is still coming down onto the floor he broke through to)
        if b.timer > 12 and not (M.catch and not b.clone) then choose(b) end    -- (a beat between moves: by chance, any distance)
    elseif act == "walk" then
        -- (bowser_act_walk_to_mario turns him at 0x200-0x400 a frame by stage and health; here at game.lua's
        -- G.BOWSER_TURN, the speed the user asked for)
        local step_deg = (ctx.turn_speed or 150.0) / 30.0
        b.face = turn(b.face, b.to_him, step_deg)
        if b.sub == 0 then
            set_anim(b, A.look_up_walk)
            if floor(b.af) >= 21 then b.fvel = 3.0 * S end
            if near_end(b) then b.sub, b.btimer = 1, 0 end
        elseif b.sub == 1 then
            set_anim(b, A.slow_gait)
            b.fvel = 3.0 * S
            if near_end(b) then
                b.btimer = b.btimer + 1
                if b.fire_sky then
                    if b.btimer > 4 then b.fire_sky = false end
                elseif abs(adiff(b.to_him, b.face)) < 0x2000 * U then
                    b.sub = 2
                end
            end
        else
            set_anim(b, A.look_down_stop)
            if floor(b.af) >= 20 then b.fvel = 0.0 end
            if near_end(b) then go(b, "default") end
        end
    elseif act == "breath" then
        -- (bowser_act_breath_fire, bhv_bowser_flame_spawn_loop: frames 46-84 of the breath, a flame every other
        -- frame, from his mouth as the breath moves it, sweeping to his side and back)
        b.fvel = 0.0
        if b.timer == 1 then sfx("bowser_inhale", 1.0) end
        set_anim(b, A.breath)
        local f = floor(b.af) + 1
        -- (drawing breath, he turns to him: a breath can come whichever way he faced, its moves being by chance)
        if f < 40 then b.face = turn(b.face, b.to_him, 0x300 * U) end
        if f > 45 and f < 85 then
            if ctx.hold_sfx then ctx.hold_sfx("loop_bowser_fire", 1.0) end
            local d = BREATH[f]
            if d and f ~= b.last_flame_f then
                b.last_flame_f = f
                local fx, fy = cos(math.rad(b.face)), sin(math.rad(b.face))
                local r = 40.0 * S
                for _ = 1, PLUME_PER do
                    local mx = b.x + fx * d[2] * S + (math.random() * 2.0 - 1.0) * r
                    local my = b.y + fy * d[2] * S + (math.random() * 2.0 - 1.0) * r
                    add_flame(world, "stream", mx, my, b.z + d[1] * S,
                        b.face - d[3] * U * PLUME_SWEEP + (math.random() * 2.0 - 1.0) * PLUME_JITTER, 3.0, false,
                        { pitch = d[4] + 0xC00, spd = PLUME_SPEED + math.random() * (PLUME_SPEED2 - PLUME_SPEED) })
                end
            end
        end
        if near_end(b) and b.timer > 20 then go(b, "default") end
    elseif act == "spit" then
        -- (bowser_act_spit_fire_onto_floor: a fireball onto the floor, one to three times; three when he is low)
        b.fvel = 0.0
        if b.timer == 1 then
            b.spits = (st == "bitdw") and 1 or ((ctx.wedges and ctx.wedges() < 4) and 3 or math.random(1, 3))
        end
        set_anim(b, A.breath_quick)
        b.face = turn(b.face, b.to_him, 0x200 * U)
        if at_frame(b, 5) then
            -- (obj_spit_fire: a fireball of 7, 200 up and 180 before him, rolling off at 30)
            local dir = math.rad(b.face)
            add_flame(world, "roller", b.x + cos(dir) * 180.0 * S, b.y + sin(dir) * 180.0 * S, b.z + 200.0 * S, b.face, 7.0,
                false, { speed = 30.0 })
        end
        if near_end(b) then
            b.sub = b.sub + 1
            b.af = 0.0
            if b.sub >= (b.spits or 1) then go(b, "default") end
        end
    elseif act == "sky" then
        -- (bowser_act_spit_fire_into_sky: flames up, raining down over the arena; the last one blue)
        b.fvel = 0.0
        set_anim(b, A.breath_up)
        local f = floor(b.af)
        if f > 24 and f < 36 and f ~= b.last_flame_f and (f % 2 == 1) then
            b.last_flame_f = f
            if ctx.hold_sfx then ctx.hold_sfx("loop_bowser_fire", 1.0) end
            -- (bhvBlueBowserFlame: 400 up and 100 before him, off at 35 and rising; the last one breaks into blue)
            local dir = math.rad(b.face)
            local r = 40.0 * S
            add_flame(world, "skyball", b.x + cos(dir) * 100.0 * S + (math.random() * 2.0 - 1.0) * r,
                b.y + sin(dir) * 100.0 * S + (math.random() * 2.0 - 1.0) * r, b.z + 400.0 * S, b.face, 3.0, false,
                { fwd = 35.0 * S, vz = 7.0 * S, grav = 1.0 * S, bluefloat = (f == 35) })
        end
        b.fire_sky = true
        if near_end(b) and b.timer > 20 then go(b, "default") end
    elseif act == "charge" then
        -- (bowser_act_charge_mario)
        -- (easier to dodge than Mario 64's, which runs at 50 and turns after him at 0x200 a frame: he takes aim as he
        -- winds up - the tell - then runs at 42 turning only 0x80 a frame, so a step aside takes him out of it; "you
        -- have to make bowsers run tackle easier to dodge", 2026-10-14)
        if b.sub == 0 then
            b.fvel = 0.0
            b.overrun = nil
            set_anim(b, A.run_start)
            b.face = turn(b.face, b.to_him, 0x400 * U)
            if near_end(b) then b.sub, b.btimer = 1, 0 end
        elseif b.sub == 1 then
            -- (the sprint: each run of it quicker than the last - "first time 1.0x next 1.3x next 1.7x", 2026-11-03)
            local SM = (b.pancake and SPRINT_BY_FLOOR[b.lvl or 1]) or SPRINT_MULT
            b.fvel = 42.0 * S * (b.clone and 1.0 or (SM[b.sprint_k or 1] or 1.0))
            set_anim(b, A.run)
            local R = b.pancake and M.PC.reach and M.PC.reach[b.lvl or 1]
            if b.overrun then
                -- (running on, straight: M.PC.reach)
                b.overrun = b.overrun - 1
                if b.overrun <= 0 then b.overrun, b.sub = nil, 2 end
            else
                if near_end(b) then
                    b.btimer = b.btimer + 1
                    if b.btimer >= 6 then b.sub = 2 end
                    if b.btimer >= 2 and abs(adiff(b.to_him, b.face)) > 0x2000 * U then b.sub = 2 end
                    if b.sub == 2 and R and R.overrun then b.sub, b.overrun = 1, R.overrun end
                end
                b.face = turn(b.face, b.to_him, 0x80 * U)
            end
        elseif b.sub == 2 then
            set_anim(b, A.run_slip)
            b.hold_last = true
            -- (a sprint's skid three times as short, its turn round two and a half times as quick: "also make him stop
            -- and turn faster", 2026-11-03)
            local R = b.pancake and M.PC.reach and M.PC.reach[b.lvl or 1]
            b.fvel = math.max(0.0, b.fvel - ((b.chain and b.chain > 1) and 3.0 or 1.0) * S * (R and R.skid or 1.0))
            if b.fvel <= 0.0 then b.sub, b.btimer, b.hold_last = 3, 0, false end
        else
            b.fvel = 0.0
            set_anim(b, A.run_stop)
            b.hold_last = true
            -- (stopped, he turns round to him again and is soon off: Mario 64 stands 30 frames here, still - "bowser
            -- pauses for a second and stops turning", 2026-10-14)
            -- (and after the last of them, round to him slowly - half his walking turn: a moment to get at his tail -
            -- "after the 3rd bowser charge he turns slowly", 2026-11-04)
            local tsp = (ctx.turn_speed or 105.0) / 30.0
            if b.chain and b.chain > 1 then tsp = 0x600 * U elseif b.chain then tsp = tsp * 0.5 end
            b.face = turn(b.face, b.to_him, tsp)
            if near_end(b) then
                b.btimer = b.btimer + 1
                -- (the sprint: straight into the next run, hardly a breath between - b.chain runs left)
                if b.chain and b.chain > 1 and b.btimer > 2 then
                    b.chain = b.chain - 1
                    b.sprint_k = (b.sprint_k or 1) + 1
                    b.sub, b.btimer, b.hold_last = 0, 0, false
                    sfx("bowser_roar", 0.6)
                elseif b.btimer > 8 then
                    b.chain = nil
                    go(b, "default")
                end
            end
        end
        if b.fvel > 0.0 and edge_ahead(b) then
            b.fvel = 0.0
            go(b, "edge")
        end
    elseif act == "edge" then
        -- (bowser_act_hit_edge, then turn_from_edge: teetering, then round)
        b.fvel = 0.0
        if b.sub == 0 then
            set_anim(b, A.edge_move)
            if near_end(b) then b.sub = 1 end
        elseif b.sub == 1 then
            set_anim(b, A.edge_stop)
            if near_end(b) then b.sub, b.timer = 2, 0 end
        else
            set_anim(b, (b.timer < 20) and A.look_up_walk or A.idle)
            b.face = b.face + ((b.chain and b.chain > 1) and 0x500 or 0x200) * U
            -- (a sprint goes on from the edge, once he has turned round)
            if b.chain and b.chain > 1 and b.timer >= 14 then
                b.chain = b.chain - 1
                b.sprint_k = (b.sprint_k or 1) + 1
                go(b, "charge")
            elseif b.timer >= 63 then
                b.chain = nil
                go(b, "default")
            end
        end
    elseif act == "quickjump" or act == "bigjump" then
        -- (bowser_act_quick_jump: at him, 60 up and 50 on; bowser_act_big_jump: straight up, 80; 70 in the Sky)
        if b.sub == 0 then
            b.fvel = 0.0
            set_anim(b, A.jump_start)
            b.face = turn(b.face, b.to_him, 0x400 * U)
            if floor(b.af) >= 11 then
                if act == "quickjump" then
                    b.vz, b.fvel = 60.0 * S, 50.0 * S
                else
                    b.vz = 80.0 * S
                    ctx.log("Bowser: big jump (%s, %d left, %.0f from him)", st, b.health or 0, b.dist or 0.0)
                    -- (the Sky: a hop on toward the middle when far out)
                    if st == "bits" and b.dist_center > 1000.0 then b.face, b.fvel = b.to_center, 20.0 * S end
                    if b.breaking then
                        local broke = ctx.PLAT and ctx.PLAT.break_bowser_piece and ctx.PLAT.break_bowser_piece(b.breaking)
                        b.breaking = nil
                        b.vz = 70.0 * S
                        -- (in to near the middle over the jump's 35 frames)
                        local r = sqrt(b.x * b.x + b.y * b.y)
                        b.face, b.fvel = b.to_center, math.max(0.0, (r - 150.0) / 35.0)
                        ctx.log("Bowser: off an outer piece - %s", broke and "it falls" or "it was going already")
                    end
                end
                b.sub = 1
            end
        elseif b.sub == 1 then
            set_anim(b, A.jump_start)
            b.hold_last = true
            if b.landed or (b.on_ground and b.timer > 8 and b.vz == 0.0) then
                b.fvel, b.hold_last = 0.0, false
                land_effects(b, ax, ay, world)
                b.sub = 2
                if act == "bigjump" then
                    -- (the final fight's second floor rocks as the Fire Sea's arena does, in place of the shockwave)
                    local rocks = not b.clone and (st == "bitfs" or (b.pancake and b.lvl == 2 and b.tilt_jump))
                    if st == "bits" and not rocks then add_wave(world, b.x, b.y, b.z) end
                    -- (the second floor's and the third's: the stage shaken hard, and him knocked over where he stands -
                    -- "stage three shockwaves dont shake stage and knock mario over", 2026-11-04)
                    if b.pancake and (b.lvl or 1) >= 2 and not rocks then
                        if ctx.shake then ctx.shake(1.0) end
                        if ctx.knockdown then ctx.knockdown(ax - b.x, ay - b.y) end
                    end
                    if rocks and ctx.PLAT and ctx.PLAT.tilt_arena then
                        ctx.PLAT.tilt_arena(b.y / S, -b.x / S)
                        sfx("big_pound", 1.0)
                    end
                end
            end
        else
            set_anim(b, A.jump_stop)
            b.face = turn(b.face, b.to_him, (ctx.turn_speed or 105.0) / 30.0)       -- (landed, turning to him)
            if near_end(b) then
                -- (the Fire Sea: he stands while the arena rocks, bowser_act_tilt_lava_platform)
                if act == "bigjump" and not b.clone and (st == "bitfs" or (b.pancake and b.lvl == 2 and b.tilt_jump)) and arena_tilting() then go(b, "tilt") else go(b, "default") end
            end
        end
    elseif act == "tilt" then
        b.fvel = 0.0
        set_anim(b, A.idle)
        if not arena_tilting() or b.timer > 200 then go(b, "default") end
    elseif act == "blink" then
        -- (down from a floor's fall: gone the moment he touches the stage, and back BLINK_T frames later on the far side
        -- of it from the athlete, on his feet and facing him - "when bowser touches the stage after a fall instantly make
        -- him teleport away", 2026-11-04. Hidden, nothing touches him.)
        b.fvel, b.vz = 0.0, 0.0
        local function poof(n, big)
            for _ = 1, n do
                local a, r = math.random() * 2.0 * pi, 60.0 + math.random() * (big and 220.0 or 140.0)
                add_flame(world, "puff", b.x + cos(a) * r, b.y + sin(a) * r, b.z + 40.0 + math.random() * (big and 320.0 or 200.0),
                    nil, (big and 4.0 or 3.0) + math.random() * 3.0, true)
            end
        end
        if b.sub == 0 then
            sfx("bowser_teleport", 1.0)
            poof(8, false)
            local top = b.hz or b.z
            -- (from the athlete through the middle and on: the far side; with him in the middle, the side away from him)
            local a = (ax * ax + ay * ay > 200.0 * 200.0) and math.atan(-ay, -ax) or math.atan(b.y - ay, b.x - ax)
            for _, r in ipairs(M.BLINK.r) do
                local tx, ty = cos(a) * r, sin(a) * r
                local tz = ground(tx, ty, top + 400.0, 0.0)
                if tz and abs(tz - top) < 300.0 then
                    b.x, b.y, b.z = tx, ty, tz
                    break
                end
            end
            set_anim(b, A.idle)
            b.hold_last = false
            b.hidden, b.sub, b.timer = true, 1, 0
        elseif b.sub == 1 then
            if b.timer >= M.BLINK.t then
                b.hidden, b.sub, b.timer = false, 2, 0
                b.face = b.to_him
                sfx("bowser_teleport", 1.0)
                poof(8, false)
                -- (just turned to metal on the last floor: shown here - M.metal_on)
                if b.metal_new then
                    b.metal_new = nil
                    sfx("bowser_roar", 1.0)
                    poof(14, true)
                end
            end
        else
            set_anim(b, A.idle)
            b.face = turn(b.face, b.to_him, (ctx.turn_speed or 105.0) / 30.0)
            if b.timer > 12 then go(b, "default") end
        end
    elseif act == "teleport" then
        -- (bowser_act_teleport: fades out, glides at him for a second, fades in)
        if b.sub == 0 then
            if b.timer == 1 then sfx("bowser_teleport", 1.0) end
            set_anim(b, A.idle)
            if b.timer > 8 then
                b.hidden, b.sub, b.btimer = true, 1, 30
                b.face = b.to_him
            end
        elseif b.sub == 1 then
            b.btimer = b.btimer - 1
            b.fvel = 100.0 * S
            if b.btimer <= 0 or (abs(adiff(b.to_him, b.face)) > 0x4000 * U and b.dist > 500.0) then
                b.fvel, b.sub, b.timer = 0.0, 2, 0
                b.face = b.to_him
                sfx("bowser_teleport", 1.0)
            end
        else
            b.fvel = 0.0
            b.hidden = false
            if b.timer > 8 then go(b, "default") end
        end
    elseif act == "dance" then
        b.fvel = 0.0
        set_anim(b, A.dance)
        if b.timer == 24 or b.timer == 42 or b.timer == 60 then sfx("bowser_walk", 1.0) end     -- (sBowserDanceStepNoises)
        if near_end(b) and b.timer > 10 then go(b, "default") end
    elseif act == "snipe" then
        -- The fire snipe (the final fight, 2026-11-03: "one long strip of fire that comes out the ground with a red tell at
        -- the base of the floor to let the player know where the attack will land"): he turns on him and draws breath, a
        -- red strip runs out along the floor from him past where the athlete stands, and a moment later fire bursts up
        -- out of the floor all along it, from him outward.
        b.fvel = 0.0
        set_anim(b, A.breath_quick)
        if b.sub == 0 then
            b.face = turn(b.face, b.to_him, 0x500 * U)
            if b.timer == 1 and not b.snipe_n then b.snipe_n = 1; sfx("bowser_inhale", 1.0) end
            -- (aimed the way he has turned by then, at 0x500 a frame - snapped round to him, at each of the four, he
            -- jerked about: "bowser fire snipe has bowser snapping around", 2026-11-04)
            if b.timer == 8 then snipe_aim(b, world, ax, ay) end
            if b.timer >= 8 + SNIPE_TELL then
                b.sub, b.timer = 1, 0
                sfx("en_flame_blown", 1.0)
                sfx("bowser_roar", 0.7)
            end
        else
            local sn = b.snipe
            if sn then
                for _ = 1, 3 do
                    sn.i = sn.i + 1
                    local p = sn.pts[sn.i]
                    if p then
                        local j = (math.random() - 0.5) * 50.0
                        add_flame(world, "jet", p[1] - sn.fy * j, p[2] + sn.fx * j, p[3], nil, 1.0, false, { grow = 8.0, hold = 14 })
                    end
                end
                if ctx.hold_sfx then ctx.hold_sfx("loop_bowser_fire", 1.0) end
                if sn.i >= #sn.pts then tell_strip_hide() end
                -- (the strip burns where it has come up, all of its width: its jets 1.9 m apart, each burning 55 cm
                -- round, left gaps to stand in untouched - "snipe attack doesnt do damage", 2026-11-04)
                local feet = az - 90.0
                for k = 1, math.min(sn.i, #sn.pts) do
                    local q = sn.pts[k]
                    local dx, dy = ax - q[1], ay - q[2]
                    -- (across the line and along it, half a step either side of this point)
                    local along = dx * sn.fx + dy * sn.fy
                    local across = -dx * sn.fy + dy * sn.fx
                    if abs(along) <= SNIPE_STEP * 0.6 and abs(across) <= SNIPE_W * 0.5 + 30.0
                        and feet < q[3] + 220.0 and feet > q[3] - 60.0 and ctx.hurt and not b.hurt_snipe then
                        b.hurt_snipe = true
                        ctx.hurt("fire", "Bowser's fire snipe", dx, dy)
                        break
                    end
                end
            end
            if b.timer > 26 then
                tell_strip_hide()
                b.snipe, b.hurt_snipe = nil, nil
                -- (and three more after it, each aimed again where the athlete is now - "make fire snipe trigger 3 more
                -- times following the player", 2026-11-04; his shadow's, the one)
                if not b.clone and (b.snipe_n or 1) < 4 then
                    b.snipe_n = (b.snipe_n or 1) + 1
                    b.sub, b.timer = 0, 0
                else
                    b.snipe_n = nil
                    go(b, "default")
                end
            end
        end
    elseif act == "meteor" then
        -- The meteor shower (the second floor on, 2026-11-03: "...then red blips will show on the ground for where the
        -- meteors will land"): fire breathed into the sky - his own breath_up, as his sky fire - a big fireball and three
        -- more up off the top of the screen, then the marks, then the meteors down onto them. ("I hate the meteor bowser
        -- animation", then "I still dont like the meteor animation on bowser", 2026-11-04: an arm turned bone by bone,
        -- then a roar and a hop; "Fire into the sky", picked.)
        b.fvel = 0.0
        if b.sub == 0 then
            set_anim(b, A.breath_up)
            b.face = turn(b.face, b.to_him, 0x300 * U)
            if b.timer == 1 then sfx("bowser_roar", 1.0) end
            local f = floor(b.af)
            if f >= 24 and f <= 36 then
                if ctx.hold_sfx then ctx.hold_sfx("loop_bowser_fire", 1.0) end
                if f ~= b.last_flame_f and f % 4 == 0 and not b.clone then
                    b.last_flame_f = f
                    local dir = math.rad(b.face)
                    local big = (f == 28)
                    add_flame(world, "upshot", b.x + cos(dir) * 100.0 * S, b.y + sin(dir) * 100.0 * S, b.z + 400.0 * S,
                        b.face, big and 6.0 or 3.0, false, { vz = 18.0 * S, acc = 2.0 * S, grow = big and 14.0 or 8.0 })
                    if big then sfx("en_flame_blown", 1.0) end
                end
            end
            if near_end(b) and b.timer > 20 then
                meteor_marks(b, world, ax, ay)
                b.sub, b.timer = 1, 0
            end
        elseif b.sub == 1 then
            set_anim(b, A.idle)
            b.face = turn(b.face, b.to_him, (ctx.turn_speed or 105.0) / 30.0)
            if b.timer >= METEOR_TELL then
                b.sub, b.timer = 2, 0
                meteor_fall(b, world)
            end
        else
            set_anim(b, A.idle)
            b.face = turn(b.face, b.to_him, (ctx.turn_speed or 105.0) / 30.0)
            if b.timer > 30 then go(b, "default") end
        end
    elseif act == "clone" then
        -- His shadow clone (the third floor, 2026-11-03: "another 50% opacity bowser spawns and can use 1 attack before
        -- disappearing"): a see-through Bowser by the athlete (M.clone_spawn, clone_step). Told first: round to him, a
        -- snap of his fingers (sfx bowser_snap, tools/snap_sfx.py) and a purple glow about him (M.aura_on) - M.SNAP.tell
        -- frames - then the shadow, and his laugh ("bowser should play a short animation to let the player know that he's
        -- spawning", then "maybe like a finger snap then a purple hue around main bowser", 2026-11-04)
        b.fvel = 0.0
        set_anim(b, A.idle)
        b.face = turn(b.face, b.to_him, 0x300 * U)
        -- (the snap seen: one arm up to his shoulder over M.SNAP.snap frames - M.arm_turn, by b.arm - flicked at the snap,
        -- sparks off the hand, then down again; and heard, on a player of its own to its end - a short sound, it was
        -- cut off by the fight's next: "I didnt here a snap and saw no bowser snapping animation", 2026-11-04)
        -- (up over M.SNAP.up frames and held there till the snap - "still no snap noise or animation", 2026-11-04: it was
        -- up and down again in two thirds of a second at the last floor's speed)
        local t = b.timer
        if t < M.SNAP.up then
            local k = t / M.SNAP.up
            b.arm = M.SNAP.arm * k * k * (3.0 - 2.0 * k)
        elseif t < M.SNAP.snap then
            b.arm = M.SNAP.arm
        elseif t < M.SNAP.snap + 4 then
            b.arm = M.SNAP.arm - 0.15 * (t - M.SNAP.snap) / 4.0
        elseif t < M.SNAP.snap + 20 then
            b.arm = (M.SNAP.arm - 0.15) * (1.0 - (t - M.SNAP.snap - 4) / 16.0)
        else
            b.arm = nil
        end
        if b.timer == M.SNAP.snap then
            ctx.log("final fight: his snap (the arm at %.2f, the hand %s)", b.arm or 0.0, M.hand_at and "seen" or "not seen")
            local SX = package.loaded["sfx"]
            if SX and SX.play then pcall(SX.play, "bowser_snap", 1.0, true) else sfx("bowser_snap", 1.0) end
            local h = M.hand_at
            if h then
                for _ = 1, 6 do
                    local a = math.random() * 2.0 * pi
                    add_flame(world, "puff", h[1] + cos(a) * 25.0, h[2] + sin(a) * 25.0, h[3], nil, 2.5 + math.random() * 1.5, true)
                end
            end
            if M.aura_on then M.aura_on(b, world) end
            -- (and the purple on the floor where it will stand - M.glow_at)
            b.clone_at = M.clone_spot and M.clone_spot(b, ax, ay) or nil
            if b.clone_at and M.glow_at then pcall(M.glow_at, world, b.clone_at[1], b.clone_at[2], b.clone_at[3]) end
        end
        if b.timer == M.SNAP.tell then
            if M.aura_off then M.aura_off() end
            if M.clone_spawn then M.clone_spawn(b, world, ax, ay, b.clone_at) end
            sfx("bowser_laugh", 1.0)
        end
        if b.timer > M.SNAP.tell + 16 then go(b, "default") end
    elseif act == "shatter" then
        -- his third hit on a floor: down where he came to rest, the floor shaking under them both; then it breaks, and he
        -- falls with it onto the next (pancake_break), where he gets up again
        b.fvel = 0.0
        if b.sub == 0 then
            set_anim(b, A.flip)
            b.hold_last = true
            if b.timer % 8 == 1 then
                if ctx.shake then ctx.shake(0.45) end
                sfx("bowser_plat", 0.9)
            end
            if b.timer >= 40 then
                pancake_break(b, world)
                b.sub, b.timer, b.vz, b.on_ground = 1, 0, 0.0, false
            end
        else
            -- (down on his back all the way, and slowly, the updraft under him too - "make bowser fall way slower also
            -- after the 3rd crack keep bowser on his back until he lands", 2026-11-03; up off his back once down)
            set_anim(b, A.flip)
            b.hold_last = true
            local cap = M.updraft_fall(b.z - floor_top(b.lvl)) * 0.75 / 30.0
            if b.timer > 12 and b.vz < -cap then b.vz = -cap + 4.0 * S end
            if b.on_ground and b.timer > 6 and b.z < floor_top(b.lvl) + 300.0 then
                b.hz = b.z
                M.arena_z = b.z
                sfx("big_pound", 1.0)
                if ctx.shake then ctx.shake(0.9) end
                ctx.log("final fight: Bowser down on floor %d", b.lvl or 0)
                -- (the last floor: Metal Bowser, from here - M.metal_on; seen as he comes back, "blink")
                if b.lvl == 3 and not b.metal and M.metal_on then
                    pcall(M.metal_on, b, world)
                    b.metal_new = true
                end
                -- (and gone the moment he touches it, back on the far side - "blink"; he got up where he came down)
                go(b, "blink")
            elseif b.timer > 900 then
                b.x, b.y, b.z, b.vz = 0.0, 0.0, floor_top(b.lvl), 0.0
            end
        end
    elseif act == "thrown" then
        -- (bowser_act_thrown: shaking in the air, bouncing; up again once still)
        if b.sub == 0 then
            set_anim(b, A.shaking)
            if b.landed and b.timer > 1 then
                b.btimer = b.btimer + 1
                if b.btimer < 4 then sfx("bowser_walk", 1.0) end
                -- (a bounce: up again at under half the speed he came down, three times at most, sliding on less each
                -- time; the first jolts the stage and the camera, as Mario 64's CAM_EVENT_BOWSER_THROW_BOUNCE does -
                -- "bowser needs to bounce after being thrown and hitting the ground", 2026-10-14)
                local up = -(b.impact_vz or 0.0) * 0.45
                if b.btimer <= 3 and up > 6.0 * S then
                    b.vz, b.on_ground = up, false
                    b.fvel = b.fvel * 0.6
                    if b.btimer == 1 and ctx.shake then ctx.shake(0.3) end
                else
                    b.fvel = b.fvel * 0.4
                end
            end
            if b.on_ground and b.timer > 4 then b.fvel, b.sub = 0.0, 1 end
        else
            set_anim(b, A.stand_up)
            if near_end(b) then go(b, "default") end
        end
    elseif act == "hitmine" then
        -- (bowser_act_hit_mine: thrown up and back toward the middle, flipping; bounces; gets up)
        if b.sub == 0 then
            set_anim(b, A.flip)
            b.hold_last = true
            if not b.fly then fly_start(b, 400.0, false, b.fly_aim); b.fly_aim = nil end
            local done = fly_step(b) or b.timer > 300
            -- (the final fight: the floor cracks where he first comes down - "the crack in the stage should form from the
            -- first bounce", 2026-11-04, it formed where he came to rest; or there, if he never touched down)
            local cracked = b.fly and b.fly.cracked
            if b.pancake and b.fly and not cracked and (b.fly.lands or 0) >= 1 then
                b.fly.cracked, cracked = true, true
                pancake_crack(b, world, b.shatter)
            end
            if done then
                b.fly = nil
                b.vz, b.fvel = 0.0, 0.0
                b.sub, b.hold_last = 2, false
                -- (at its third hit it breaks - "shatter")
                if b.pancake and not cracked then pancake_crack(b, world, b.shatter) end
                if b.shatter then
                    b.shatter = nil
                    go(b, "shatter")
                    b.hold_last = true
                end
            end
        else
            set_anim(b, A.stand_up_from_flip)
            if near_end(b) then
                if b.health == 1 and st == "bits" then go(b, "dance")
                elseif not piece_jump(b) then go(b, "default") end
            end
        end
    elseif act == "fallen" then
        -- (bowser_act_jump_onto_stage: out of sight, then a great leap back onto the arena)
        if b.sub == 0 then
            b.hidden = true
            b.fx, b.fy = b.x, b.y
            -- (where he lands: on the stage, part way in toward its middle from where he went off)
            local k = (st == "bits" and b.health <= 1) and 0.2 or 0.45      -- (the Sky's outer pieces gone: well in)
            b.tx, b.ty = b.x * k, b.y * k
            b.tz = ground(b.tx, b.ty, b.hz + 400.0, 0.0) or b.hz
            b.fz = b.tz - 1200.0
            if b.timer > 15 then b.sub, b.timer, b.hidden = 1, 0, false; set_anim(b, A.jump_start); b.hold_last = true end
        elseif b.sub == 1 then
            local k = math.min(1.0, b.timer / 40.0)
            b.x, b.y = b.fx + (b.tx - b.fx) * k, b.fy + (b.ty - b.fy) * k
            b.z = b.fz + (b.tz - b.fz) * k + sin(k * pi) * 1500.0
            b.vz, b.fvel = 0.0, 0.0
            b.face = b.to_center
            if k >= 1.0 then
                b.z, b.sub, b.hold_last = b.tz, 2, false
                land_effects(b, ax, ay, world)
                if st == "bits" then add_wave(world, b.x, b.y, b.z) end
                if st == "bitfs" and ctx.PLAT and ctx.PLAT.tilt_arena then ctx.PLAT.tilt_arena(b.y / S, -b.x / S) end
            end
        else
            set_anim(b, A.jump_stop)
            b.face = turn(b.face, b.to_him, (ctx.turn_speed or 105.0) / 30.0)       -- (landed, turning to him)
            if near_end(b) and not piece_jump(b) then go(b, "default") end
        end
    end
end

-- a bomb within reach of him as he flies (bowser_check_hit_mine: 800 units)
local MINE_DOWN, MINE_UP = 800.0, 1100.0      -- ("not by much but definitely more": the ball reached 800 over it)
local function hit_mine(b, world)
    for _, bm in ipairs(ctx.bombs() or {}) do
        -- (the final fight: only his own floor's)
        if not bm.gone and (not b.pancake or not bm.floor or bm.floor == b.lvl) then
            -- (Mario 64's 800 round it, but a column: thrown high he went over the ball and the mine never went off -
            -- "bowser can be thrown over bombs, bombs hitboxes should go up more", 2026-11-02. MINE_DOWN under it to
            -- MINE_UP over it, Mario 64 units)
            local d = sqrt((b.x - bm.x) ^ 2 + (b.y - bm.y) ^ 2) / S
            local h = (b.z - bm.z) / S
            if d < 800.0 and h > -MINE_DOWN and h < MINE_UP then
                bm.gone = true
                pcall(function() bm.inst.actor:SetActorHiddenInGame(true) end)
                if ctx.explode then ctx.explode(world, bm) end
                return true
            end
        end
    end
    return false
end

-- the hold (Mario 64's ACT_PICKING_UP_BOWSER, ACT_HOLDING_BOWSER, ACT_RELEASING_BOWSER), with his weight
-- (2026-10-14: "add more weight to grabbing and spinning bowser. he's as light as a feather and spins very fast"):
-- a heave of half a second, dragging him in to arm's length; then each frame's turn (the camera, or the stick
-- going round) adds only a 128th of itself to his swing, at most 0x80 a frame, up to 0x1000 a frame (675 degrees
-- a second); no turning and he winds down by 64 a frame; left still for 120 frames he is dropped. Let go flat out
-- and he flies much further (Mario 64's throw is 2.5 times as hard above 90).
local SPIN_MAX, SPIN_ACC, SPIN_DRAG = 0x1000 * U, 0x80 * U, 64 * U
local HEAVE = 15                -- (frames of the heave before he can be swung)
local function held(b, dt, world, pawn, ax, ay)
    local lib = ctx.lib
    b.ht = (b.ht or 0.0) + dt
    b.hf = (b.hf or 0) + 1
    if b.hold then
        pcall(function()
            local cm = pawn.CharacterMovement
            if cm.MovementMode ~= 0 then cm:SetMovementMode(0, 0) end
            cm:StopMovementImmediately()
            pawn:K2_SetActorLocation(b.hold, false, {}, true)
        end)
        ax, ay = b.hold.X - ctx.OFFSET.X, b.hold.Y - ctx.OFFSET.Y
    end
    -- this frame's turn: the camera (the mouse), or the way the stick/keys point going round
    local cam, inp = nil, nil
    pcall(function() cam = lib.controller():GetControlRotation().Yaw end)
    pcall(function()
        local v = pawn:GetLastMovementInputVector()
        if v.X * v.X + v.Y * v.Y > 0.04 then inp = math.deg(atan(v.Y, v.X)) end
    end)
    local function turned(now, before) if not (now and before) then return 0.0 end; return adiff(now, before) end
    local dc, di = turned(cam, b.cam_prev), turned(inp, b.inp_prev)
    b.cam_prev, b.inp_prev = cam, inp
    local dturn = (abs(dc) > abs(di)) and dc or di
    local steering = (inp ~= nil) or abs(dc) > 0.3
    if b.hf > HEAVE and steering then
        b.spin = math.max(-SPIN_MAX, math.min(SPIN_MAX, b.spin + math.max(-SPIN_ACC, math.min(SPIN_ACC, dturn / 128.0))))
    elseif b.spin > 0.0 then
        b.spin = math.max(0.0, b.spin - SPIN_DRAG)
    else
        b.spin = math.min(0.0, b.spin + SPIN_DRAG)
    end
    b.swing = b.swing + b.spin
    local cx, cy = cos(math.rad(b.swing)), sin(math.rad(b.swing))
    -- (the heave: dragged in from where he stood to arm's length)
    local reach = 260.0
    if b.hf <= HEAVE then reach = b.grab_d + (260.0 - b.grab_d) * (b.hf / HEAVE) end
    b.x, b.y = ax + cx * reach, ay + cy * reach
    b.face = b.swing
    pcall(function() pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = b.swing, Roll = 0.0 }, false) end)
    -- (Mario 64: a whoosh each time round, once he is going)
    b.whoosh = (b.whoosh or 0.0) + abs(b.spin)
    if b.whoosh >= 360.0 then
        b.whoosh = b.whoosh - 360.0
        if abs(b.spin) >= 0x100 * U then sfx("bowser_spin", 0.6 + 0.4 * abs(b.spin) / SPIN_MAX) end
    end
    -- (grabbed, then shaking in the athlete's hands)
    if b.anim_id == A.grabbed and near_end(b) then set_anim(b, A.shaking)
    elseif b.anim_id ~= A.shaking then set_anim(b, A.grabbed) end
    -- (left still too long, he is dropped)
    if b.spin == 0.0 then b.still = (b.still or 0) + 1 else b.still = 0 end
    -- (let go: STORROR's push (Y), or A as well - a fresh press since he was grabbed: "yea add it to a as well",
    -- 2026-10-14)
    local a_now = false
    pcall(function()
        local pc = lib.controller()
        a_now = pc:IsInputKeyDown({ KeyName = FName("Gamepad_FaceButton_Bottom") }) or pc:IsInputKeyDown({ KeyName = FName("SpaceBar") })
    end)
    local a_press = a_now and b.a_prev == false
    b.a_prev = a_now
    if (b.hf > HEAVE and (ctx.pushed(pawn) or a_press)) or b.still > 120 then let_go(b, pawn, ax, ay, false) end
end

-- Bowser out of his hands: thrown (a push, or left still too long), or dropped (`dropped`: burnt while swinging him;
-- Mario 64 throws a dropped Bowser the same way, at the swing he had)
let_go = function(b, pawn, ax, ay, dropped)
    do
        local v = abs(b.spin) / SPIN_MAX
        -- (he flies on the way he is from the athlete as he is let go, as Mario 64 throws him: the swing aims it, not
        -- the camera, and no help onto the bombs - "it should throw him where you swing him not aimlock onto bombs",
        -- 2026-10-14)
        local aim = b.swing
        -- (how far: with the swing; flat out, much further. Lobbed: up at LOB degrees and down that far off, at
        -- his own gravity; it went in a flat line, Mario 64's way, and the user wanted a lob, 2026-10-14)
        -- (further since: a full spin carried him 18 m, and the bombs on the star's points are 27 m from the middle -
        -- "cant seem to throw bowser far enough sometimes", 2026-11-02; Mario 64 throws him 2.5 times as fast at the top
        -- of the swing. Now 22 m flat out: from the middle he comes down by a bomb)
        local range = 300.0 + 1300.0 * v
        if v > 0.94 then range = range * 1.4 end
        local v0 = sqrt(range * 4.0 * S / sin(math.rad(2.0 * LOB)))
        b.face, b.fvel, b.vz = aim, v0 * cos(math.rad(LOB)), v0 * sin(math.rad(LOB))
        b.x, b.y = ax + cos(math.rad(aim)) * 260.0, ay + sin(math.rad(aim)) * 260.0
        b.hold, b.held = nil, false
        b.landed, b.on_ground = false, false       -- (not the landing from before he was picked up: that took his speed)
        go(b, "thrown")
        sfx(v > 0.3 and "king_throw" or "bowser_walk")
        -- (act_holding_bowser: let go spinning at 0xE00 a frame or more, "So long-a Bowser!", else "Here we go!"; dropped,
        -- the burn has its own cry)
        if not dropped then sfx((abs(b.spin) >= 0xE00 * U) and "mario_so_longa_bowser" or "mario_here_we_go", 1.0) end
        pcall(function() pawn.CharacterMovement:SetMovementMode(1, 0) end)
        ctx.log("Bowser %s at %.0f degrees a second", dropped and ("dropped (" .. (type(dropped) == "string" and dropped or "burnt") .. ")") or "let go", abs(b.spin) * 30.0)
    end
end

-- His death (bowser_act_dead): flies back onto the middle, lies down, twirls away; his key or star
-- The final fight's end (its last floor's third hit - "next after the final throw in stage 3 the stage breaks again
-- bowser defeated floating down where mario can talk to him while riding on wind after talking to him he gets turned in
-- to a mega star made of rainbow material", 2026-11-04): thrown down onto the floor as at any hit, the floor cracking
-- and shaking under him, then breaking - its pieces, and no floor under it now - and the two of them falling: he on his
-- back, slowly; the athlete in the wind (catch_tick's `hover`: held FINALE.hover under it, never down). Down at the
-- athlete's height he floats, drifting in to him; near (FINALE.near, Mario 64 units), his words (bowser_beaten_final);
-- then he is a mega star (M.mega_star), hung there in the wind to be taken - the Grand Star's own: the ending.
M.FINAL_TEXT = { intro = 4, beaten = 3 }              -- (pages: exporter/finalx.py)
-- (`lift`: the athlete held that much higher than Bowser's float - he hung a little under him: "mario floats a little
-- bit under bowser, bring him up", 2026-11-04. The mega star: out of him and over to `star_out` past him on the way
-- from the athlete, as a boss's star comes out on a stage - game.lua fly_star's "coords": a turn, an arc, its jingle, a
-- bounce - and not to be taken till its jingle is done, `star_ready` s on; taken from `reach` x its size, not 95:
-- "star audio doesnt finish and player auto grabs it, make the star bounce like it does on stage", 2026-11-04)
M.FINALE = { hover = 1800.0, near = 900.0, drift = 150.0, keep = 380.0, star_scale = 5.0, lift = 180.0,
             star_out = 700.0, star_up = 150.0, star_ready = 6.3, reach = 60.0, reach_h = 70.0 }
function M.pancake_break_last(b, world)
    local PL = ctx.PLAT
    local cur = PL and PL.pancakes and PL.pancakes[3]
    if cur then
        if PL.pancake_solid then PL.pancake_solid(cur, false) end
        cur.gone = true
        pcall(function() cur.actor:SetActorHiddenInGame(true) end)
    end
    for _, bm in ipairs((ctx.bombs and ctx.bombs()) or {}) do
        if bm.floor == 3 and not bm.gone then
            bm.gone = true
            pcall(function() bm.inst.actor:SetActorHiddenInGame(true) end)
        end
    end
    tell_strip_hide()
    debris_start(3)
    if M.clone and M.clone_gone then pcall(M.clone_gone) end
    if M.aura and M.aura_off then pcall(M.aura_off) end
    sfx("pyramid_explode", 1.0)
    sfx("gate_break", 1.0)
    if ctx.shake then ctx.shake(1.0) end
    M.catch = { t0 = os.clock(), top = floor_top(3) - M.FINALE.hover + M.FINALE.lift, hover = true }
    local G = package.loaded["game"]
    if G then G.no_fall_until = os.clock() + 8.0 end
    ctx.log("final fight: the last floor broke - Bowser beaten, both in the wind")
end
function M.finale_step(b, world, ax, ay)
    local F = b.fin
    if not F then
        F = { phase = 0, t = 0 }
        b.fin = F
        -- (his clear time: not from here, but from the mega star taken - ending.lua E.start: "final bowser clear time
        -- should only show after player picks up rainbow star", 2026-11-04)
        -- (his cry as the last hit lands - the lay-down's own, which this end of his has no lay-down for: "no bowser
        -- moan on final hit", 2026-11-04)
        sfx("bowser_defeated", 1.0)
    end
    F.t = F.t + 1
    local top = floor_top(3)
    if F.phase == 0 then
        -- (thrown down onto the floor, as at any hit - the floor cracking where he comes down)
        set_anim(b, A.flip_down)
        b.hold_last = true
        if not b.fly then fly_start(b, 200.0, true) end
        local done = fly_step(b) or F.t > 300
        if b.fly and not b.fly.cracked and (b.fly.lands or 0) >= 1 then
            b.fly.cracked = true
            pancake_crack(b, world, true)
        end
        if done then
            b.fly, b.vz, b.fvel = nil, 0.0, 0.0
            F.phase, F.t = 1, 0
        end
    elseif F.phase == 1 then
        -- (the floor shaking under him, then gone)
        set_anim(b, A.flip)
        b.hold_last = true
        if F.t % 8 == 1 then
            if ctx.shake then ctx.shake(0.45) end
            sfx("bowser_plat", 0.9)
        end
        if F.t >= 40 then
            M.pancake_break_last(b, world)
            F.phase, F.t, F.vz, F.hz = 2, 0, 0.0, top - M.FINALE.hover
        end
    elseif F.phase == 2 then
        -- (down on his back, slowly, the wind under him too, to beside the athlete's height)
        set_anim(b, A.flip)
        b.hold_last = true
        local cap = M.updraft_fall(b.z - F.hz) * 0.75 / 30.0
        F.vz = math.max(F.vz - 1.5 * S, -cap)
        b.z = b.z + F.vz
        if b.z <= F.hz + 100.0 then F.phase, F.t = 3, 0 end
    elseif F.phase == 3 or F.phase == 4 then
        -- (floating there, turning to him, drifting in to him; his words once near)
        set_anim(b, A.flip)
        b.hold_last = true
        local base = F.hz + 100.0
        b.z = base + sin(F.t * 0.05) * 30.0
        local dx, dy = ax - b.x, ay - b.y
        local dd = sqrt(dx * dx + dy * dy)
        if dd > M.FINALE.keep then
            local step = math.min(dd - M.FINALE.keep, M.FINALE.drift / 30.0)
            b.x, b.y = b.x + dx / dd * step, b.y + dy / dd * step
        end
        b.face = turn(b.face, b.to_him, 0x200 * U)
        if F.phase == 3 and F.t > 30 and b.dist < M.FINALE.near and not words then
            words_start(b, world)
            F.phase = 4
        elseif F.phase == 4 and words and words.b == b and words_tick(FRAME) then
            -- (his words done: a mega star)
            F.phase, F.t = 5, 0
            if ctx.MUSIC and ctx.MUSIC.play then pcall(ctx.MUSIC.play, nil) end
            sfx("bowser_explode", 1.0)
            for _ = 1, 18 do
                local a, r = math.random() * 2.0 * pi, 40.0 + math.random() * 260.0
                add_flame(world, "puff", b.x + cos(a) * r, b.y + sin(a) * r, b.z + math.random() * 320.0,
                    nil, 4.0 + math.random() * 4.0, true)
            end
            b.hidden = true
            -- (out of him, over to further off than he floated, at the athlete's height - for him to fly into it)
            local ex, ey = b.x - ax, b.y - ay
            local ed = math.max(1.0, sqrt(ex * ex + ey * ey))
            local hz = (M.catch and M.catch.top or b.z) + M.FINALE.star_up
            M.mega_star(world, b.x + ex / ed * M.FINALE.star_out, b.y + ey / ed * M.FINALE.star_out, hz, { b.x, b.y, b.z + 120.0 })
        end
    end
end
-- The mega star he becomes (finale): a Grand Star - taking it starts the ending, game.lua update_stars - FINALE.star_scale
-- times a star's size, taken from as far as it is big (its `reach`), its faces rainbow (textures/rainbow_star.png,
-- tools/rainbow_star_tex.py; its eyes as they are), the rainbow running over it (M.mega_tick)
M.mega = nil
function M.mega_star(world, x, y, z, from)
    -- (the star's own model, not the see-through one game.lua gives a star already won: on that one face, untextured,
    -- the rainbow did not show - "its not a rainbow star", 2026-11-04)
    -- (`from`: where it comes out - him - for it to fly over to its place, game.lua G.add_star / fly_star)
    local o = { pos = { x, y, z }, id = 0, model = "star", from = from }
    local ok, st = pcall(ctx.add_star, world, o)
    if not (ok and st) then return end
    st.grand = true
    local sc = M.FINALE.star_scale
    st.reach, st.reach_h, st.spin = M.FINALE.reach * sc, M.FINALE.reach_h * sc, 120.0
    st.ready_at = os.clock() + M.FINALE.star_ready
    pcall(function() st.inst.actor:SetActorScale3D({ X = sc, Y = sc, Z = sc }) end)
    local mid = ctx.lib.get_mid(world, "opaque", "rainbow_star", 0.95)
    if mid and st.inst and st.inst.data then
        for i, part in ipairs(st.inst.data.parts) do
            local comp = st.inst.comps[i]
            for _, sec in ipairs(part.sections or {}) do
                if comp and not (sec.texture or ""):find("eye") then pcall(function() comp:SetMaterial(sec.id, mid) end) end
            end
        end
    end
    M.mega = { st = st, mid = mid, t = 0.0, world = here_world() }
    if ctx.MUSIC and ctx.MUSIC.preload then pcall(ctx.MUSIC.preload, "event_victory") end
    ctx.log("final fight: Bowser a mega star")
end
function M.mega_tick(dt)
    local m = M.mega
    if not m then return end
    if m.world ~= here_world() or m.st.taken then M.mega = nil; return end
    m.t = m.t + dt
    if m.mid then
        local off = { R = (m.t * 0.12) % 40.0, G = (m.t * 0.05) % 40.0, B = 1.0, A = 1.0 }
        pcall(function() m.mid:SetVectorParameterValue(FName("BaseColorTexture_OffsetScale"), off) end)
    end
end

local function dead(b, world, ax, ay)
    if b.pancake then return M.finale_step(b, world, ax, ay) end
    b.timer = b.timer + 1
    if b.sub == 0 then
        set_anim(b, A.flip_down)
        b.hold_last = true
        if not b.fly then fly_start(b, 200.0, true) end
        if fly_step(b) or b.timer > 300 then
            -- (still at last: he lies where he came to rest, and his cry with it - the lay-down's own sound)
            b.fly = nil
            b.tx, b.ty, b.tz = b.x, b.y, b.z
            b.sub, b.timer = 1, 0
            set_anim(b, A.lay_down)
        end
    elseif b.sub == 1 then
        set_anim(b, A.lay_down)
        b.hold_last = true
        -- (until the athlete comes up to him, or a few seconds)
        -- (bowser_dead_wait_for_mario: until the athlete is within 700 and faces him, however long; then his words,
        -- DIALOG_119/120/121 - the end came after 6 s whatever he did, and without them: "no bowser text when you
        -- walk up to him", 2026-10-15)
        if not words and b.timer > 45 and b.dist < 700.0 then
            local facing = false
            pcall(function()
                local pawn = ctx.lib.pawn()
                local l = pawn:K2_GetActorLocation()
                local to = yaw_to(l.X - ctx.OFFSET.X, l.Y - ctx.OFFSET.Y, b.x, b.y)
                facing = abs(adiff(pawn:K2_GetActorRotation().Yaw, to)) < 0x2000 * U
            end)
            if facing then words_start(b, world) end
        end
        if words and words.b == b and words_tick(FRAME) then
            b.sub, b.timer = 2, 0
            if ctx.MUSIC and ctx.MUSIC.play then pcall(ctx.MUSIC.play, nil) end
            if b.stage == "bits" then
                -- (bowser_dead_final_stage_ending: the Grand Star comes out of him where he lies)
                M.grand_star(world, b.tx, b.ty, b.tz)
            else
                sfx("bowser_explode", 1.0)
            end
        end
    elseif b.sub == 2 then
        local f = b.timer
        local sxz = math.max(0.2, 1.0 - 0.02 * f)
        local sy = (sxz > 0.2) and 1.0 or math.max(0.0, 1.0 - 0.01 * (f - 40.0))
        if sxz < 0.8 then b.spinv = (b.spinv or 0.0) + 0x80 * U end
        b.face = b.face + (b.spinv or 0.0)
        if sxz <= 0.2 then b.z = b.z + 20.0 * S end
        pcall(function() b.inst.actor:SetActorScale3D({ X = sxz, Y = sxz, Z = sy }) end)
        if sy < 0.5 then
            b.sub = 3
            b.hidden = true
            local keyn = (b.stage == "bitdw") and 1 or ((b.stage == "bitfs") and 2 or nil)
            if keyn then M.drop_key(world, b, keyn) end
            ctx.log("Bowser gone: his %s", keyn and ("key " .. keyn) or "Grand Star")
        end
    end
end

-- The Grand Star (grand_star.inc.c): out where he lay, spinning for 70 frames; then a leap (up at 80, gravity 2)
-- and a hop (60) to hang 200 above where it came out; only then can it be taken
-- (out 90 cm up, not 30: at twice a star's size it reaches 84 cm under its middle, and came out half in the floor -
-- "grand star spawns halfway in the floor", 2026-11-02. It still comes to rest where it did, 1.8 m up: GRAND_REST)
local GRAND_UP, GRAND_REST = 90.0, 240.0 * S
function M.grand_star(world, x, y, z)
    local o = { pos = { x, y, z + GRAND_UP }, id = 0 }
    local ok, st = pcall(ctx.add_star, world, o)
    if not (ok and st) then return end
    st.hidden = true                         -- (game.lua's stars leave a hidden one alone: posed here until it settles)
    st.grand = true                          -- (taking it starts the ending)
    -- (twice a star's size, as bhv_grand_star_loop draws it - cur_obj_scale(2.0): "star kinda seems small", 2026-11-02)
    pcall(function() st.inst.actor:SetActorScale3D({ X = 2.0, Y = 2.0, Z = 2.0 }) end)
    M.grand = { st = st, t = 0, act = 0, sub = 0, x = x, y = y, z = z + GRAND_UP, home = z + GRAND_UP, rest = z + GRAND_REST,
                vz = 0.0, yaw = 0.0 }
    sfx("star_appears2", 1.0)
    -- (the victory tune opened now, while all is quiet, to start the moment it is taken: music.lua M.preload)
    if ctx.MUSIC and ctx.MUSIC.preload then pcall(ctx.MUSIC.preload, "event_victory") end
end
local function update_grand()
    local g = M.grand
    if not g then return end
    g.t = g.t + 1
    g.yaw = g.yaw + 0x400 * U
    if g.act == 0 then
        if g.t > 70 then g.act, g.t, g.vz = 1, 0, 80.0 * S; sfx("grand_star", 1.0) end
    elseif g.act == 1 then
        g.vz = g.vz - 2.0 * S
        g.z = g.z + g.vz
        if g.sub == 0 then
            if g.z < g.home then g.z, g.vz, g.sub = g.home, 60.0 * S, 1; sfx("grand_star_jump", 1.0) end
        elseif g.vz < 0.0 and g.z < (g.rest or (g.home + 200.0 * S)) then
            g.z, g.act = g.rest or (g.home + 200.0 * S), 2
            sfx("grand_star_jump", 1.0)
            -- (now it can be taken - a moment after it has come to rest, not the instant it stops: taken as it stopped,
            -- it looked still bouncing - "can pick up the star early should have to wait for it to stop bouncing",
            -- 2026-11-02. Mario 64 holds Mario in the star's cutscene till then)
            g.st.x, g.st.y, g.st.z, g.st.hidden = g.x, g.y, g.z, false
            g.st.ready_at = os.clock() + 1.0
            M.grand = nil
            return
        end
    end
    pcall(ctx.lib.set_pose, g.st.inst, g.x + ctx.OFFSET.X, g.y + ctx.OFFSET.Y, g.z + ctx.OFFSET.Z, g.yaw)
end

-- His key (bowser_key.inc.c): out of him up where he vanished, still spinning as he was (slowing to 0x400 a
-- frame), a hop of 70 then falling (gravity 4), bouncing three times (KEY_BOUNCE of its speed back, a clink each time),
-- then it lies; half size, stood upright (roll -0x4000: its shaft lies along its x) and drawn 165 up. Only then can it
-- be taken ("it should only be grabable when it stops bouncing. also the key only bounces twice", 2026-10-14: at
-- 0.7 a bounce it went on in ever smaller hops for seconds).
local KEY_YOFF = 165.0
-- (three bounces: "key only bounces twice instead of 3 times", 2026-10-15 - Mario 64 gives back 0.7 of its fall at each
-- landing and goes on in ever smaller hops; here the third one ends it)
local KEY_BOUNCE = { 0.7, 0.6, 0.45 }
function M.drop_key(world, b, keyn)
    local o = { pos = { b.x, b.y, b.z + KEY_YOFF * S }, id = 0, model = "geo_bowser_key_geo", keyn = keyn }
    if not ctx.actor_data(o.model) then o.model, o.keyn = nil, nil end
    local ok, st = pcall(ctx.add_star, world, o)
    sfx("bowser_key", 1.0)
    if not (ok and st) then return end
    st.hidden = true                         -- (game.lua's stars leave a hidden one alone: moved here until it lies)
    if o.keyn then
        st.roll, st.spin = 90.0, 0x400 * U * 30.0
        pcall(function() st.inst.actor:SetActorScale3D({ X = 0.5, Y = 0.5, Z = 0.5 }) end)
    end
    M.key = { st = st, x = b.x, y = b.y, z = b.z, vz = 70.0 * S, yaw = b.face, spin = math.max(0x400 * U, abs(b.spinv or 0.0)),
              roll = st.roll or 0.0, t = 0 }
    M.key_star, M.key_danced = st, nil
    -- (a burst of sparkles where it comes out)
    local O = ctx.OFFSET
    for _ = 1, 12 do
        local a = math.random() * 2.0 * pi
        spark_add(world, b.x + O.X + cos(a) * 80.0, b.y + O.Y + sin(a) * 80.0, b.z + KEY_YOFF * S + O.Z, 1.4,
            (math.random() - 0.3) * 5.0)
    end
end
local function update_key()
    local k = M.key
    if not k then return end
    k.t = k.t + 1
    if k.spin > 0x400 * U then k.spin = math.max(0x400 * U, k.spin - 0x100 * U) end
    k.yaw = k.yaw + k.spin
    k.vz = math.max(k.vz - 4.0 * S, -75.0 * S)
    k.z = k.z + k.vz
    -- (sparkles round it as it comes down: spawn_sparkle_particles(3, 200, 80, -60), two a frame here)
    pcall(function()
        local world, O = ctx.lib.world(), ctx.OFFSET
        for _ = 1, 2 do
            local a, r = math.random() * 2.0 * pi, math.random() * 150.0
            spark_add(world, k.x + O.X + cos(a) * r, k.y + O.Y + sin(a) * r, k.z + KEY_YOFF * S + O.Z + 60.0, 1.0, -1.0)
        end
    end)
    local fz = ground(k.x, k.y, k.z, 60.0) or M.arena_z
    if k.z <= fz then
        k.z = fz
        k.bounces = k.bounces or 0
        if k.vz < -6.0 * S and k.bounces < #KEY_BOUNCE and k.t < 300 then
            k.bounces = k.bounces + 1
            k.vz = -k.vz * KEY_BOUNCE[k.bounces]
            sfx("key_bounce", 1.0)              -- (Mario 64's clink is as loud at every landing)
        else
            sfx("key_bounce", 1.0)
            -- (it lies: now it can be taken, spinning on as game.lua's stars do)
            local st = k.st
            st.x, st.y, st.z = k.x, k.y, fz + KEY_YOFF * S
            if st.spin and st.spin > 0.0 then st.t = (k.yaw % 360.0) / st.spin end
            st.hidden = false
            M.key = nil
        end
    end
    pcall(function()
        k.st.inst.actor:K2_TeleportTo({ X = k.x + ctx.OFFSET.X, Y = k.y + ctx.OFFSET.Y, Z = k.z + KEY_YOFF * S + ctx.OFFSET.Z },
            { Pitch = 0.0, Yaw = k.yaw, Roll = k.roll })
    end)
end

-- a hit: a bomb went off on him
local function hit(b, world)
    b.health = b.health - 1
    sfx("bowser_bomb", 1.0)
    ctx.log("Bowser hit by a bomb (%d left)", b.health)
    b.fx, b.fy, b.fz = b.x, b.y, b.z
    if b.health <= 0 then
        -- back onto the middle of the arena
        b.tx, b.ty = 0.0, 0.0
        b.tz = ground(0.0, 0.0, b.hz + 400.0, 0.0) or b.hz
        go(b, "dead")
        b.dead = true
    elseif b.pancake then
        -- (the final fight's floors: back onto the middle, the floor cracking where he lands - at its third hit,
        -- breaking: "shatter")
        b.chain = nil
        b.tx, b.ty, b.fly_aim = b.x * 0.15, b.y * 0.15, nil
        b.tz = ground(b.tx, b.ty, b.hz + 400.0, 0.0) or b.hz
        b.shatter = (b.health % M.PC.per == 0) or nil
        go(b, "hitmine")
    else
        -- thrown up and back over the middle (Mario 64: off backward at 400 toward it), landing near it: in the Sky
        -- the outer pieces fall away at his last hit, so never out there
        b.tx, b.ty, b.fly_aim = b.x * 0.15, b.y * 0.15, nil
        -- (the Sky, hits left: flung on across the middle onto an outer piece on the far side - Mario 64's flight off a
        -- mine, 400 on toward the middle and past it - where he big-jumps off it: piece_jump)
        if b.stage == "bits" and b.health >= 2 and ctx.PLAT and ctx.PLAT.bowser_piece_under then
            local opp = math.atan(-b.y, -b.x)
            for _, rr in ipairs(PIECE_R) do
                for _, da in ipairs(PIECE_DA) do
                    if not b.fly_aim then
                        local a = opp + math.rad(da)
                        local fx, fy = cos(a) * rr, sin(a) * rr
                        local okp, piece = pcall(ctx.PLAT.bowser_piece_under, fx, fy, b.hz + 400.0)
                        if okp and piece then b.tx, b.ty, b.fly_aim = fx, fy, { fx, fy } end
                    end
                end
            end
        end
        b.tz = ground(b.tx, b.ty, b.hz + 400.0, 0.0) or b.hz
        go(b, "hitmine")
    end
end

-- the athlete takes his tail (a push from behind him, or close at his side), or runs into him
local function touch(b, pawn, ax, ay, az)
    -- (nor as he falls with the broken floor - his tail taken in the air, both fell glitching: 2026-11-04)
    if b.hidden or b.dead or b.act == "thrown" or b.act == "hitmine" or b.act == "fallen" or b.act == "shatter" then return end
    -- (nothing touches before his words are read: no grab, no bump)
    if b.cam_act and b.cam_act ~= "end" then return end
    local d = sqrt((ax - b.x) ^ 2 + (ay - b.y) ^ 2)
    local fx, fy = cos(math.rad(b.face)), sin(math.rad(b.face))
    local behind = ((ax - b.x) * fx + (ay - b.y) * fy) < 0
    -- (how far round to his back he is: 1 straight behind him, 0 at his side, -1 before his face)
    local rear = -((ax - b.x) * fx + (ay - b.y) * fy) / math.max(d, 1.0)
    if pawn and d < 480.0 and abs(az - 90.0 - b.z) < 400.0 and ctx.pushed(pawn) then
        -- (his tail only from behind, within 75 degrees of straight behind him: "im able to grab it in front of
        -- him", 2026-10-14 - it took any push within 4.2 m, his face included)
        -- (and not before the fight has begun: in his wait and his intro walk he could be grabbed and thrown onto a
        -- bomb before he had made a move - "bowser is vulnerable in the first 4 seconds of the fight", 2026-10-14)
        local BN = package.loaded["burn"]
        if rear > 0.26 and b.act ~= "wait" and b.act ~= "intro" and not (BN and BN.active) then
            b.held, b.ht, b.hf, b.spin, b.cam_prev, b.inp_prev, b.still, b.whoosh = true, 0.0, 0, 0.0, nil, nil, 0, 0.0
            b.held_at = os.clock()
            b.a_prev = nil                  -- (an A already down as he grabs does not throw)
            b.swing, b.grab_d = yaw_to(ax, ay, b.x, b.y), math.max(150.0, math.min(480.0, d))
            set_anim(b, A.grabbed)
            b.hold = nil
            pcall(function() local l = pawn:K2_GetActorLocation(); b.hold = { X = l.X, Y = l.Y, Z = l.Z } end)
            pcall(function() pawn.CharacterMovement:StopMovementImmediately() end)
            pcall(function() pawn.CharacterMovement:SetMovementMode(0, 0) end)
            sfx("bowser_tail", 1.0)
            sfx("mario_hrmm", 1.0)              -- (act_picking_up_bowser: SOUND_MARIO_HRMM; "add the audio for grabbing bowsers tail")
            ctx.log("Bowser's tail grabbed")
            return
        end
    end
    -- his body: 2 m round his middle, level with him (Mario 64: two wedges, and knocked back)
    if d < 200.0 and az > b.z - 50.0 and az < b.z + 380.0 then
        -- (coming down on him from a jump: a stomp, which knocks him flat; running into him in a charge: a ram, which
        -- sends him flying, his way and away from him: "if bowser charges and knocks into you your charater gets sent
        -- flying and ragdolled", 2026-10-14)
        local kind = "body"
        local hx, hy = ax - b.x, ay - b.y
        if not b.on_ground and b.vz < 0.0 then
            kind = "stomp"
        elseif b.act == "charge" and b.fvel > 15.0 * S then
            -- (any touch while he runs at him: a narrower ram, 160 cm, never fired - the first frame of contact, at
            -- 200, was always a plain bump, and its second of grace swallowed the ram; "his tackles arnt ragdolling
            -- the player", 2026-10-14)
            kind = "ram"
            local f, dd = math.rad(b.face), math.max(1.0, sqrt(hx * hx + hy * hy))
            hx, hy = cos(f) + hx / dd * 0.6, sin(f) + hy / dd * 0.6
            -- (a sprint that has caught him ends with this run - missing, it goes on: "if bowser hits you with a tackle
            -- he will stop the back to back tackles, but if he doesnt he continues", 2026-11-04)
            b.chain = nil
        else
            -- (the athlete in the air, jumping into him: knocked flat and thrown back off him - "when jumping into
            -- bowsers idle state have the player ragdol and get bumped off", 2026-10-14; on foot, a plain bump)
            local mode = 1
            pcall(function() mode = pawn.CharacterMovement.MovementMode end)
            if pawn and mode ~= 1 then kind = "jumpin" end
        end
        if ctx.hurt then ctx.hurt(kind, (kind == "ram") and "Bowser's charge" or "Bowser", hx, hy) end
        -- (and solid: between hurts, still shoved out of him)
        -- (only when well inside him, and just enough to part them: not a launch off the arena)
        b.shove_t = (b.shove_t or 0) - 1
        if pawn and b.shove_t <= 0 and d < 160.0 then
            b.shove_t = 6
            local k = 350.0 / math.max(d, 1.0)
            pcall(ctx.lib.bounce, pawn, (ax - b.x) * k, (ay - b.y) * k, 0.0)
        end
    end
end

-- ------------------------------------------------------------ his entrance (camera.c CUTSCENE_ENTER_BOWSER_ARENA)
-- Mario 64 opens every Bowser fight with a shot of him: 180 frames in which the camera looks from beside him to
-- where Mario lands, then (from frame 40) swings round onto him as he looks up and walks out, the ground shaking
-- under his steps; then his words in a dialog box, a page for each A. Only after the last page does the fight
-- begin. Until then he cannot be grabbed or bumped into, and the athlete waits without controls ("bowser is still
-- vulrable in the first 4 seconds add the cutscene with the text", 2026-10-14).
local SHOT_FRAMES = 180
local CUT_FOV = 45.0                    -- (Mario 64's, top to bottom)
local ASPECT = 16.0 / 9.0
local PAGES = { bitdw = 2, bitfs = 2, bits = 3 }        -- DIALOG_067, 092, 093 (exporter/bowserintrox.py)
local PAGE_W, PAGE_H = 1440.0, 1080.0   -- (the game's 320x240 screen on a 1920x1080 one)
local PAGE_MIN = 0.35                   -- s a page is up before A turns it
local BLEND_BACK = 20.0 / 30.0          -- (cutscene_bowser_arena_end: transition_next_state(c, 20))

local cut = nil

local function sins(u) return sin(u * 2.0 * pi / 65536.0) end
local function coss(u) return cos(u * 2.0 * pi / 65536.0) end

-- (cutscene_bowser_arena_set_pos) the camera: c.dist from him, c.pitch up, round from his facing at the start by 45
-- degrees; (cutscene_bowser_arena_set_focus) what it looks at: c.oz before him along that facing, c.oy up
local function cut_pos(c)
    local p, y, d = math.rad(c.pitch * U), math.rad(c.face0 + 45.0), c.dist * S
    return c.bx + d * cos(p) * cos(y), c.by + d * cos(p) * sin(y), c.bz + d * sin(p)
end
local function cut_focus(c)
    local f = math.rad(c.face0)
    return c.bx - c.oz * S * cos(f), c.by - c.oz * S * sin(f), c.bz + c.oy * S
end

local function cut_pages(world, stage, prefix, count)
    prefix, count = prefix or "bowser_dialog_", count or PAGES[stage] or 0
    local pc = ctx.lib.controller()
    local function cls(p) return StaticFindObject(p) end
    _G.SM64_WORDS_SERIAL = (_G.SM64_WORDS_SERIAL or 0) + 1
    local n = tostring(_G.SM64_WORDS_SERIAL)
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("SM64BowserWords" .. n))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("SM64BowserWordsTree" .. n))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SM64BowserWordsCanvas" .. n))
    tree.RootWidget = canvas
    local pages = {}
    for i = 1, count do
        local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("SM64BowserWordsImg" .. n .. "_" .. i))
        local tex = ctx.lib.texture(world, prefix .. stage .. "_" .. i)
        if tex then img:SetBrushFromTexture(tex, false) end
        local slot = canvas:AddChildToCanvas(img)
        slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
        slot:SetAlignment({ X = 0.5, Y = 0.5 })
        slot:SetSize({ X = PAGE_W, Y = PAGE_H })
        slot:SetPosition({ X = 0.0, Y = 0.0 })
        img:SetRenderOpacity(0.0)
        pages[i] = img
    end
    w:AddToViewport(60)
    return { widget = w, pages = pages }
end

-- His controls off for the entrance, as the pause screen and the burn hold them: the pawn's input, his moving, and
-- every STORROR part that takes buttons (Parkour! has the jump) under a lock of this name. DisableInput alone left
-- him walking about and jumping on A ("the charater was moving around during the cutscene", "when pressing a it
-- was making the charater jump", 2026-10-14).
local LOCK = "SM64BowserEntrance"
local function cut_lock(c, on)
    local pc, pawn = ctx.lib.controller(), ctx.lib.pawn()
    if not (pc and pawn) then return end
    if on then
        if not c.locked then
            c.locked = true
            pcall(function() pc:SetIgnoreMoveInput(true) end)      -- (a count in the engine: once on, once off)
            c.parts = {}
            local ok, cs = pcall(FindAllOf, "HITSActorComponentWithInput")
            local mine = pawn:GetAddress()
            for i = 1, (ok and cs and #cs or 0) do
                pcall(function()
                    local o = cs[i]
                    if o:IsValid() and o:GetOwner():GetAddress() == mine then c.parts[#c.parts + 1] = o end
                end)
            end
            pcall(function()
                for _, comp in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
                    local o = comp:get()
                    local cn = o:GetClass():GetFName():ToString()
                    if cn == "LocomotionComponent" then c.loco = o elseif cn == "ParkourComponent" then c.parkour = o end
                end
            end)
            pcall(function() pawn.CharacterMovement:StopMovementImmediately() end)
            ctx.log("Bowser's entrance: his controls held (%d parts, locomotion %s, parkour %s)", #c.parts, tostring(c.loco ~= nil), tostring(c.parkour ~= nil))
        end
        -- (and again every tenth of a second: the pause screen gives the input back when it shuts)
        pcall(function() pawn:DisableInput(pc) end)
        for _, o in ipairs(c.parts or {}) do
            pcall(function() if o:IsValid() then o:EnableComponentInput(FName(LOCK), false) end end)
        end
        if c.loco then
            pcall(function()
                if c.loco:IsValid() then
                    c.loco:EnableLocomotionInputCallback(FName(LOCK), false)
                    c.loco:EnableAdvancedLocomotionInput(FName(LOCK), false)
                end
            end)
        end
        -- (the jump, and every other parkour move, have their own switch; presses already queued are dropped:
        -- "charater is still jumping during cutscene", 2026-10-14)
        if c.parkour then
            pcall(function()
                if c.parkour:IsValid() then
                    c.parkour:EnableAllParkourInputs(FName(LOCK), false)
                    c.parkour:ClearInputQueue()
                end
            end)
        end
    elseif c.locked then
        c.locked = false
        for _, o in ipairs(c.parts or {}) do
            pcall(function() if o:IsValid() then o:EnableComponentInput(FName(LOCK), true) end end)
        end
        if c.loco then
            pcall(function()
                if c.loco:IsValid() then
                    c.loco:EnableLocomotionInputCallback(FName(LOCK), true)
                    c.loco:EnableAdvancedLocomotionInput(FName(LOCK), true)
                end
            end)
        end
        if c.parkour then
            pcall(function()
                if c.parkour:IsValid() then
                    c.parkour:ClearInputQueue()
                    c.parkour:EnableAllParkourInputs(FName(LOCK), true)
                end
            end)
        end
        pcall(function() pc:SetIgnoreMoveInput(false) end)
        pcall(function() pawn:EnableInput(pc) end)
    end
end

-- His words when he is beaten (bowser_dead_default_stage_ending, bowser_dead_final_stage_ending): the pages one by one
-- on A, his controls held and the music down while they are up, as for his entrance's words.
local BEATEN_PAGES = { bitdw = 2, bitfs = 4, bits = 3 }            -- DIALOG_119, 120, 121
words = nil
words_start = function(b, world)
    if words then return end
    local c = { b = b, world = world:GetAddress(), page = 0, page_t = 0.0, relock = 0.1 }
    if b.pancake then
        pcall(function() c.ui = cut_pages(world, "final", "bowser_beaten_", M.FINAL_TEXT.beaten) end)
    else
        pcall(function() c.ui = cut_pages(world, b.stage, "bowser_beaten_", BEATEN_PAGES[b.stage]) end)
    end
    cut_lock(c, true)
    local MU = ctx.MUSIC
    if MU and MU.set_volume and MU.volume then c.vol = MU.volume; pcall(MU.set_volume, MU.volume * 0.4) end
    local pad = package.loaded["pad"]
    if pad then pcall(pad.reset) end
    words = c
    ctx.log("Bowser beaten: his words")
end
words_stop = function(quiet)
    local c = words
    words = nil
    if not c then return end
    local same = false
    pcall(function() same = ctx.lib.world():GetAddress() == c.world end)
    if quiet or not same then return end
    if c.ui then pcall(function() c.ui.widget:RemoveFromParent() end) end
    cut_lock(c, false)
    local MU = ctx.MUSIC
    if MU and MU.set_volume and c.vol then pcall(MU.set_volume, c.vol) end
end
-- a Mario 64 frame of them; true once the last page has gone
words_tick = function(dt)
    local c = words
    if not c then return true end
    local here = nil
    pcall(function() here = ctx.lib.world():GetAddress() end)
    if here ~= c.world then words_stop(true); return true end
    c.relock = c.relock - dt
    if c.relock <= 0.0 then c.relock = 0.1; cut_lock(c, true) end
    local pages = c.ui and c.ui.pages or {}
    if c.page == 0 then
        c.page, c.page_t = 1, 0.0
        if pages[1] then pcall(function() pages[1]:SetRenderOpacity(1.0) end) end
        sfx("menu_message_appear", 1.0)
        return #pages == 0 and (words_stop(false) or true) or false
    end
    c.page_t = c.page_t + dt
    local pad = package.loaded["pad"]
    if not (pad and c.page_t >= PAGE_MIN and pad.pressed("ok")) then return false end
    if pages[c.page] then pcall(function() pages[c.page]:SetRenderOpacity(0.0) end) end
    c.page, c.page_t = c.page + 1, 0.0
    if pages[c.page] then
        pcall(function() pages[c.page]:SetRenderOpacity(1.0) end)
        sfx("menu_message_next_page", 1.0)
        return false
    end
    sfx("menu_message_disappear", 1.0)
    words_stop(false)
    ctx.log("Bowser beaten: his words read")
    return true
end

local function cut_start(b, world, pawn)
    local pc = ctx.lib.controller()
    if not (world and pawn and pc) then return false end
    local c = { b = b, world = world:GetAddress(), phase = "shot", f = 0, t = 0.0,
                face0 = b.face, dist = 430.0, pitch = 0xD90, oy = 120.0, oz = -800.0, sine = 0,
                bx = b.x, by = b.y, bz = b.z,
                pshake = 0.0, pphase = 0, pdecay = 0, pvel = 0, fshake = 0.0, fphase = 0, fdecay = 0, fvel = 0 }
    c.px, c.py, c.pz = cut_pos(c)
    c.fx, c.fy, c.fz = cut_focus(c)
    c.ppx, c.ppy, c.ppz, c.pfx, c.pfy, c.pfz = c.px, c.py, c.pz, c.fx, c.fy, c.fz
    local O = ctx.OFFSET
    local ok = pcall(function()
        c.cam = ctx.lib.camera(world, "bowser_entrance",
            { X = c.px + O.X, Y = c.py + O.Y, Z = c.pz + O.Z }, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
    end)
    if not (ok and c.cam and c.cam:IsValid()) then return false end
    -- (the final fight's own - exporter/finalx.py: "also his beginning text needs to be ... you may have peach and your
    -- puny power star ...", 2026-11-04)
    if b.pancake then
        pcall(function() c.ui = cut_pages(world, "final", "bowser_dialog_", M.FINAL_TEXT.intro) end)
    else
        pcall(function() c.ui = cut_pages(world, b.stage) end)
    end
    cut_lock(c, true)
    c.relock = 0.1
    pcall(function() pc:SetViewTargetWithBlend(c.cam, 0.0, 0, 0.0, false) end)
    cut = c
    M.cutscene = true
    ctx.log("Bowser's entrance: started (%s)", tostring(b.stage))
    return true
end

-- over, or the scene went: everything back. quiet = the world went, touch nothing
M.cut_state = function() return cut end
local function cut_stop(quiet)
    local c = cut
    cut = nil
    M.cutscene = false
    if not c then return end
    if c.b and c.b.cam_act ~= "end" then c.b.cam_act = "end" end
    if quiet then return end
    local same = false
    pcall(function() same = ctx.lib.world():GetAddress() == c.world end)
    if not same then return end
    local pc, pawn = ctx.lib.controller(), ctx.lib.pawn()
    cut_lock(c, false)
    if c.phase ~= "back" and pc and pawn then
        pcall(function() pc:SetViewTargetWithBlend(pawn, 0.0, 0, 0.0, false) end)
    end
    if c.ui then pcall(function() c.ui.widget:RemoveFromParent() end) end
    -- (its camera stays: lib.camera)
end
M.cut_stop = cut_stop

-- (shake_camera_pitch, shake_camera_fov) the shakes, a Mario 64 frame on
local function cut_shakes(c)
    if c.pshake ~= 0.0 then
        c.pphase = c.pphase + c.pvel
        c.pshake = math.max(0.0, c.pshake - c.pdecay)
    end
    if c.fshake ~= 0.0 then
        c.fphase = c.fphase + c.fvel
        c.fshake = math.max(0.0, c.fshake - c.fdecay)
    end
end
local function pitch_shake(c, mag, decay, vel) if c.pshake < mag then c.pshake, c.pdecay, c.pvel = mag, decay, vel end end
local function fov_shake(c, amp, decay, vel) if amp > c.fshake then c.fshake, c.fdecay, c.fvel = amp, decay, vel end end

-- one Mario 64 frame of the shot (cutscene_bowser_arena), before his own frame
local function cut_frame(b)
    local c = cut
    if not c or c.b ~= b then return end
    cut_shakes(c)
    if c.phase ~= "shot" then return end
    local f = c.f
    c.ppx, c.ppy, c.ppz, c.pfx, c.pfy, c.pfz = c.px, c.py, c.pz, c.fx, c.fy, c.fz
    if f == 40 then b.cam_act = "walk" end                       -- (cutscene_bowser_area_start_bowser_walking)
    if f == 145 then fov_shake(c, 0x400, 0x20, 0x4000) end       -- (cutscene_bowser_area_shake_fov: preset 2)
    if f >= 40 then
        c.px, c.py, c.pz = cut_pos(c)
        c.bx, c.by, c.bz = b.x, b.y, b.z
        if f <= 99 then c.oz = c.oz + (0.0 - c.oz) * 0.05 end   -- (pan_left)
        if f >= 100 then                                        -- (adjust_offsets)
            c.pitch = c.pitch + math.modf((0x6C8 - c.pitch) / 30)
            c.oz = c.oz + (-200.0 - c.oz) * 0.02
            c.dist = c.dist + (550.0 - c.dist) * 0.02
        end
        if f <= 140 then                                        -- (focus_sine)
            local want = sins(c.sine) * 120.0 + 120.0
            c.sine = c.sine - 0x200
            c.oy = c.oy + (want - c.oy) * 0.5
        end
        c.fx, c.fy, c.fz = cut_focus(c)
    end
    if f == 60 or f == 82 or f == 109 or f == 127 then          -- (cutscene_shake_explosion)
        pitch_shake(c, 0x60, 0x8, 0x4000)
        fov_shake(c, 0x100, 0x30, 0x8000)
    end
    c.f = f + 1
    if c.f >= SHOT_FRAMES then
        -- (cutscene_bowser_arena_dialog: his words, DIALOG_067/092/093)
        c.phase, c.page, c.page_t = "words", 0, 0.0
        c.ppx, c.ppy, c.ppz, c.pfx, c.pfy, c.pfz = c.px, c.py, c.pz, c.fx, c.fy, c.fz
        local pad = package.loaded["pad"]
        if pad then pcall(pad.reset) end
    end
end

-- every tick: the camera where the shot has it, the pages, and the way back to the game
local function cut_tick(b, dt, pawn)
    local c = cut
    if not c then return end
    local here = nil
    pcall(function() here = ctx.lib.world():GetAddress() end)
    if here ~= c.world then cut_stop(true); return end
    if c.b ~= b then cut_stop(false); return end
    c.t = c.t + dt
    local pc = ctx.lib.controller()
    if c.phase ~= "back" then
        c.relock = (c.relock or 0.1) - dt
        if c.relock <= 0.0 then c.relock = 0.1; cut_lock(c, true) end
        -- (and kept where he first stood: should any STORROR move still get through the locks, he is put back; 60 cm
        -- of room, his standing animation alone shifts him 20-odd)
        if pawn then
            pcall(function()
                local l = pawn:K2_GetActorLocation()
                if not c.pin then
                    if pawn.CharacterMovement.MovementMode == 1 then c.pin = { X = l.X, Y = l.Y, Z = l.Z } end
                elseif (l.X - c.pin.X) ^ 2 + (l.Y - c.pin.Y) ^ 2 > 60.0 * 60.0 or l.Z > c.pin.Z + 25.0 then
                    pawn:K2_TeleportTo(c.pin, pawn:K2_GetActorRotation())
                    pawn.CharacterMovement:StopMovementImmediately()
                    if not c.pinned then c.pinned = true; ctx.log("Bowser's entrance: he moved, put back") end
                end
            end)
        end
    end
    if c.phase == "words" then
        local pages = c.ui and c.ui.pages or {}
        if c.page == 0 then
            c.page, c.page_t = 1, 0.0
            if pages[1] then pcall(function() pages[1]:SetRenderOpacity(1.0) end) end
            sfx("menu_message_appear", 1.0)
            sfx("bowser_laugh", 1.0)                    -- (play_dialog_sound: his speaker, BOWS2)
        else
            c.page_t = c.page_t + dt
            local pad = package.loaded["pad"]
            local a = pad and c.page_t >= PAGE_MIN and pad.pressed("ok")
            if a or #pages == 0 then
                if pages[c.page] then pcall(function() pages[c.page]:SetRenderOpacity(0.0) end) end
                c.page, c.page_t = c.page + 1, 0.0
                if pages[c.page] then
                    pcall(function() pages[c.page]:SetRenderOpacity(1.0) end)
                    sfx("menu_message_next_page", 1.0)
                else
                    -- (cutscene_bowser_arena_end: the box goes, the camera eases back to him over 20 frames, he
                    -- has his controls, and Bowser fights)
                    sfx("menu_message_disappear", 1.0)
                    c.phase, c.back_t = "back", 0.0
                    b.cam_act = "end"
                    if pc and pawn then
                        -- (he and the game's camera turned to Bowser, so the camera comes back behind him looking
                        -- at Bowser, not into Bowser's shell from behind his back)
                        pcall(function()
                            local l = pawn:K2_GetActorLocation()
                            local yaw = yaw_to(l.X - ctx.OFFSET.X, l.Y - ctx.OFFSET.Y, b.x, b.y)
                            pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false)
                            pc:SetControlRotation({ Pitch = -10.0, Yaw = yaw, Roll = 0.0 })
                        end)
                        cut_lock(c, false)
                        pcall(function() pc:SetViewTargetWithBlend(pawn, BLEND_BACK, 4, 2.0, false) end)
                    end
                    ctx.log("Bowser's entrance: over, the fight begins")
                end
            end
        end
    elseif c.phase == "back" then
        c.back_t = c.back_t + dt
        if c.back_t > BLEND_BACK + 0.15 then cut_stop(false) end
        return
    end
    -- the camera, between the shot's last two frames
    local k = (c.phase == "shot") and math.min(1.0, (b.acc or 0.0) / FRAME) or 1.0
    local px, py, pz = c.ppx + (c.px - c.ppx) * k, c.ppy + (c.py - c.ppy) * k, c.ppz + (c.pz - c.ppz) * k
    local fx, fy, fz = c.pfx + (c.fx - c.pfx) * k, c.pfy + (c.fy - c.pfy) * k, c.pfz + (c.fz - c.pfz) * k
    local dx, dy, dz = fx - px, fy - py, fz - pz
    local yaw, pitch = math.deg(atan(dy, dx)), math.deg(atan(dz, sqrt(dx * dx + dy * dy)))
    pitch = pitch + c.pshake * sins(c.pphase) * U
    local fov = CUT_FOV + coss(c.fphase) * c.fshake / 256.0
    local O = ctx.OFFSET
    pcall(function()
        c.cam:K2_TeleportTo({ X = px + O.X, Y = py + O.Y, Z = pz + O.Z }, { Pitch = pitch, Yaw = yaw, Roll = 0.0 })
        if not c.fov or abs(fov - c.fov) > 0.01 then
            c.fov = fov
            c.cam.CameraComponent:SetFieldOfView(2.0 * math.deg(math.atan(math.tan(math.rad(fov / 2.0)) * ASPECT)))
        end
    end)
end

-- ------------------------------------------------------------ sparkles (actors/sparkle: six pictures, two frames each)
-- Mario 64's key throws sparkles as it comes down (spawn_sparkle_particles) and the key dance has them round Mario
-- (the user's reference video, 2026-10-15). A pool, used again and again: actors made and destroyed by the dozen came
-- before a crash once.
local spark = { world = nil, free = {}, live = {} }
spark_add = function(world, x, y, z, size, vz)
    local here = world:GetAddress()
    if spark.world ~= here then spark.world, spark.free, spark.live = here, {}, {} end
    if #spark.live >= 40 then return end
    local sp = table.remove(spark.free)
    if not sp then
        local q = ctx.lib.quad_actor(world, { X = x, Y = y, Z = z }, 22.0, "ending_sparkle_0", "alpha")
        if not q then return end
        local pmc = nil
        pcall(function() pmc = q:GetComponentByClass(StaticFindObject("/Script/ProceduralMeshComponent.ProceduralMeshComponent")) end)
        sp = { actor = q, pmc = pmc }
    else
        pcall(function() sp.actor:SetActorHiddenInGame(false) end)
    end
    sp.x, sp.y, sp.z, sp.t, sp.size, sp.k = x, y, z, 0, size or 1.0, -1
    sp.vx, sp.vy = (math.random() - 0.5) * 6.0, (math.random() - 0.5) * 6.0
    sp.vz = vz or (1.5 + math.random() * 2.0)
    spark.live[#spark.live + 1] = sp
end
-- a Mario 64 frame of them
spark_step = function(world)
    if #spark.live == 0 then return end
    local cx, cy, cz = ctx.lib.camera_location({ X = 0.0, Y = 0.0, Z = 0.0 })
    local keep = {}
    for _, sp in ipairs(spark.live) do
        sp.t = sp.t + 1
        if sp.t > 12 then
            pcall(function() sp.actor:SetActorHiddenInGame(true) end)
            spark.free[#spark.free + 1] = sp
        else
            sp.x, sp.y, sp.z = sp.x + sp.vx, sp.y + sp.vy, sp.z + sp.vz
            local k = floor(sp.t / 2) % 6
            if sp.pmc and k ~= sp.k then
                sp.k = k
                pcall(function()
                    local mid = ctx.lib.get_mid(world, "alpha", "ending_sparkle_" .. k)
                    if mid then sp.pmc:SetMaterial(0, mid) end
                end)
            end
            local dx, dy, dz = cx - sp.x, cy - sp.y, cz - sp.z
            local rot = { Pitch = -math.deg(atan(dz, sqrt(dx * dx + dy * dy))), Yaw = math.deg(atan(dy, dx)) + 180.0, Roll = 0.0 }
            local sc = sp.size * (1.0 - sp.t / 16.0)
            pcall(function()
                sp.actor:K2_TeleportTo({ X = sp.x, Y = sp.y, Z = sp.z }, rot)
                sp.actor:SetActorScale3D({ X = sc, Y = sc, Z = sc })
            end)
            keep[#keep + 1] = sp
        end
    end
    spark.live = keep
end
local function spark_clear()
    local here = nil
    pcall(function() here = ctx.lib.world():GetAddress() end)
    if spark.world == here then
        for _, sp in ipairs(spark.live) do ctx.lib.destroy(sp.actor) end
        for _, sp in ipairs(spark.free) do ctx.lib.destroy(sp.actor) end
    end
    spark.world, spark.free, spark.live = nil, {}, {}
end
M.spark_clear = spark_clear

-- ------------------------------------------------------------ the key's dance (CUTSCENE_KEY_DANCE)
-- Taken, the key goes up over his head, spinning, sparkles round him, and the camera cuts: close up from before him,
-- low from his right, from above (tilted), then from further out before him (camera.c's cvar offsets, by his facing);
-- then the screen closes to black round him and he leaves the course. Before, the key just went and he was sent out
-- 3 s later. ("watch the fight and try to match the cutscene", the user's reference video, 2026-10-15)
local DANCE_SHOTS = {   -- from frame: camera offset, focus offset (Mario 64 units: x his left, y up, z behind him), roll
    { 0, { 38, 171, -248 }, { -57, 51, 187 }, 0 },
    { 20, { -178, 62, -132 }, { 299, 91, 58 }, 0 },
    { 35, { 89, 373, -304 }, { 0, 127, 0 }, 0x2800 },
    { 52, { 135, 158, -673 }, { -20, 135, -198 }, 0 },
}
local DANCE_K = 1.1             -- cm a Mario 64 unit for these shots: the athlete stands half again Mario's height
-- (Mario 64 goes out at the dance's 80th frame - general_star_dance_handler; with the corkscrew the screen closes as
-- he lands from it instead, below)
local DANCE_FRAMES = 80
local IRIS_TIME = 32.0 / 30.0   -- (WARP_OP_STAR_EXIT: the screen closes on him over 32 frames)
local dance = nil
local dance_cork_end            -- (below, with his corkscrew)

local function iris_ui(world)
    local pc = ctx.lib.controller()
    local function cls(p) return StaticFindObject(p) end
    _G.SM64_IRIS_SERIAL = (_G.SM64_IRIS_SERIAL or 0) + 1
    local n = tostring(_G.SM64_IRIS_SERIAL)
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("SM64Iris" .. n))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("SM64IrisTree" .. n))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SM64IrisCanvas" .. n))
    tree.RootWidget = canvas
    local ui = { widget = w, bars = {} }
    local function image(name, file)
        local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("SM64Iris" .. name .. n))
        local tex = ctx.lib.texture(world, file)
        if tex then img:SetBrushFromTexture(tex, false) end
        return img, canvas:AddChildToCanvas(img)
    end
    local _, hole = image("Hole", "iris_hole")
    hole:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
    hole:SetAlignment({ X = 0.5, Y = 0.5 })
    ui.hole = hole
    -- (black all round the hole: left, right, above, below)
    for i, a in ipairs({ { 0.0, 0.0, 0.5, 1.0 }, { 0.5, 0.0, 1.0, 1.0 }, { 0.0, 0.0, 1.0, 0.5 }, { 0.0, 0.5, 1.0, 1.0 } }) do
        local _, s = image("Bar" .. i, "black")
        s:SetAnchors({ Minimum = { X = a[1], Y = a[2] }, Maximum = { X = a[3], Y = a[4] } })
        ui.bars[i] = s
    end
    local size = { X = 1920.0, Y = 1080.0 }
    pcall(function()
        local WLL = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        local vs, sc = WLL:GetViewportSize(world), WLL:GetViewportScale(world)
        if vs and sc and sc > 0 then size = { X = vs.X / sc, Y = vs.Y / sc } end
    end)
    ui.full = math.max(size.X, size.Y) * 1.6
    w:AddToViewport(70)
    return ui
end
-- the hole `d` across (slate units); the bars close in to its edges
local function iris_set(ui, d)
    local r = d * 0.5
    pcall(function()
        ui.hole:SetSize({ X = d, Y = d })
        ui.bars[1]:SetOffsets({ Left = 0.0, Top = 0.0, Right = r, Bottom = 0.0 })
        ui.bars[2]:SetOffsets({ Left = r, Top = 0.0, Right = 0.0, Bottom = 0.0 })
        ui.bars[3]:SetOffsets({ Left = 0.0, Top = 0.0, Right = 0.0, Bottom = r })
        ui.bars[4]:SetOffsets({ Left = 0.0, Top = r, Right = 0.0, Bottom = 0.0 })
    end)
end

local function dance_stop(quiet)
    local c = dance
    dance = nil
    if not c then return end
    local same = false
    pcall(function() same = ctx.lib.world():GetAddress() == c.world end)
    if quiet or not same then return end
    if c.ui then pcall(function() c.ui.widget:RemoveFromParent() end) end
    if dance_cork_end then dance_cork_end(c, true) end
    cut_lock(c, false)
    local pc, pawn = ctx.lib.controller(), ctx.lib.pawn()
    if pc and pawn then pcall(function() pc:SetViewTargetWithBlend(pawn, 0.0, 0, 0.0, false) end) end
    -- (its camera stays: lib.camera)
end
M.dance_stop = dance_stop
M.dance_state = function() return dance end            -- (tests)

-- the key `st` was just taken (game.lua's stars): the dance, then out of the course by its "got a star" way
function M.key_dance(st)
    if dance then return end
    local world, pc, pawn = ctx.lib.world(), ctx.lib.controller(), ctx.lib.pawn()
    if not (world and pc and pawn) then return end
    local G = package.loaded["game"]
    if G then G.star_exit_at = nil end                       -- (the dance sends him out itself)
    local c = { world = world:GetAddress(), st = st, f = 0, t = 0.0, relock = 0.1, phase = "dance" }
    pcall(function()
        local l = pawn:K2_GetActorLocation()
        c.feet = { X = l.X, Y = l.Y, Z = l.Z - 90.0 }
        c.face = pawn:K2_GetActorRotation().Yaw
    end)
    if not c.feet then return end
    c.head = c.feet.Z + 165.0
    pcall(function() c.head = pawn.Mesh:GetSocketLocation(FName("head")).Z end)
    -- (the key from behind him, low, at a tenth of its size)
    c.key = { n = 0, a = c.face + 180.0, d = 100.0, h = 30.0, yaw = c.face, scale = 0.1, x = 0.0, y = 0.0 }
    c.at = { X = c.feet.X, Y = c.feet.Y }
    c.cork = { wait = 0.0 }
    pcall(function() pawn.CharacterMovement:StopMovementImmediately() end)
    cut_lock(c, true)
    pcall(function()
        c.cam = ctx.lib.camera(world, "key_dance", c.feet, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
        c.cam.CameraComponent:SetFieldOfView(2.0 * math.deg(math.atan(math.tan(math.rad(22.5)) * ASPECT)))
        pc:SetViewTargetWithBlend(c.cam, 0.0, 0, 0.0, false)
    end)
    -- the key over his head again, spinning
    pcall(function() st.inst.actor:SetActorHiddenInGame(false) end)
    for _ = 1, 12 do spark_add(world, c.feet.X, c.feet.Y, c.feet.Z + 150.0, 1.4, 2.0 + math.random() * 3.0) end
    dance = c
    ctx.log("key dance")
end

-- His corkscrew as he takes the key, in place of Mario's star dance ("when picking up the key make the charater do a
-- corkscrew", 2026-10-15): STORROR's own cork, its montage asset played on him - not a dynamic montage made from a
-- sequence, which the engine can free under STORROR's feet (the "0x60" crash). Only once he is on the ground and
-- none of STORROR's moves is playing (a montage of ours over one of its moves left him stuck running, 2026-10-14);
-- not at all if that takes over half a second. 2.7 s: it lands as the screen starts to close. On the spot: the take
-- carried him 6 m across the floor ("you need to freeze the player", 2026-10-15), so his root motion is ignored
-- (ERootMotionMode 1) while it plays, then put back as it was (STORROR's own: 2, from everything).
-- (take 3823: a standing take-off, no run-up, his pelvis up to 146 cm at 0.7 s and down by 1.2 s; 4140 never left the
-- ground - his pelvis stayed under 95 cm - and jittered back and forth: "its still really cooked". Scan: corkscan.lua)
local CORK = "/SPP/SPPCharacter/Animation/Flip/Cork/MontageFlipCork_3823_SPPFlipsKelan_frames_0-68026.MontageFlipCork_3823_SPPFlipsKelan_frames_0-68026"
-- (in slow motion, 25% slower, and the screen closing as he lands - 1.35 s into the take - not after he has stood
-- about: "but it ends quickly", "he just starts standing there", "maybe just slow down the corkscrew by 25% and close
-- once it ends like slowmo", 2026-10-15)
local CORK_RATE = 0.75
local CORK_LAND = 1.35
local function dance_cork(c, pawn, dt)
    local k = c.cork
    if k and k.ai then
        k.t = k.t + dt
        if k.t >= k.len + 0.1 then dance_cork_end(c) end
    end
    if not k or k.done then return end
    k.wait = k.wait + dt
    if k.wait > 0.5 then k.done = true; ctx.log("key dance: no corkscrew (he was still busy)"); return end
    local ready = false
    pcall(function()
        local busy = false
        local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
        if m and m:IsValid() then busy = true end
        ready = pawn.CharacterMovement.MovementMode == 1 and not busy
    end)
    if not ready then return end
    k.done = true
    local mont = ctx.lib.try_load(CORK)
    if not mont then ctx.log("key dance: no corkscrew (its montage is missing)"); return end
    local len = 0.0
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        k.ai, k.rmm = ai, ai.RootMotionMode
        -- (as STORROR's own emote: played with Montage_Play, STORROR stops it before the next frame - game.lua's
        -- G.play_emote, 2026-10-23)
        local G = package.loaded["game"]
        if G and G.play_emote then len = G.play_emote(pawn, ai, mont, CORK_RATE, 0.0)
        else len = ai:Montage_Play(mont, CORK_RATE, 0, 0.0, true) end
        ai.RootMotionMode = 1
    end)
    k.playing = len and len > 0.0
    k.mont, k.len, k.t = mont, (len or 0.0) / CORK_RATE, 0.0
    if not k.playing then dance_cork_end(c) end
    ctx.log("key dance: corkscrew %s (%.2f s, root motion was %s)", k.playing and "on" or "would not play", len or 0.0,
        tostring(k.rmm))
end
-- his root motion back as it was, once the cork is over (or the dance is)
dance_cork_end = function(c, stop)
    local k = c and c.cork
    if not (k and k.ai and k.rmm) then return end
    local ai, rmm = k.ai, k.rmm
    k.ai, k.rmm = nil, nil
    pcall(function()
        if not ai:IsValid() then return end
        -- (the screen is black: the rest of the take, his standing up, is cut, so he cannot be carried after it)
        if stop and k.mont and ai:Montage_IsPlaying(k.mont) then ai:Montage_Stop(0.1, k.mont) end
        ai.RootMotionMode = rmm
    end)
end
-- the dance is over (the screen starts to close): as he lands from the corkscrew, or Mario 64's 80 frames without one
local function dance_done(c, f)
    local k = c.cork
    if k and k.playing then return (k.t or 0.0) * CORK_RATE >= CORK_LAND end
    if k and not k.done then return false end              -- (still waiting to start it)
    return f >= DANCE_FRAMES
end

-- The key as Mario 64 sends it up for the dance (bhvCelebrationStar with the key: BUGFIX_STAR_BOWSER_KEY): round him
-- from behind, 45 degrees a frame on a circle 100 across (widening 1 a frame, then from its 36th closing in by 20 a
-- frame), rising 5 and turning 22.5 a frame at a tenth of its size, a sparkle falling from it each frame; from its 42nd
-- frame it grows from nothing to 0.3 over 10 frames, still turning, then turns to face as he faces and stays over his
-- head. (It was the dropped key's own size, stuck 55 cm over his head, its shaft through him.) Heights are stretched a
-- little so that at its full size its shaft's tip clears his head.
local KEY_TIP = 318.0           -- (the key's model: the shaft runs 318 out along its x from the bow at its origin)
local function dance_key_frame(c, world)
    local k = c.key
    k.n = k.n + 1
    if k.n <= 41 then
        k.x, k.y = cos(math.rad(k.a)) * k.d * 0.5, sin(math.rad(k.a)) * k.d * 0.5
        k.h = k.h + 5.0
        k.yaw = k.yaw - 22.5
        k.a = k.a - 45.0
        k.scale = 0.1
        k.d = k.n <= 35 and k.d + 1.0 or k.d - 20.0
    elseif k.n <= 51 then
        k.scale = (k.n - 42) / 30.0
        k.yaw = k.yaw - 22.5
    else
        k.yaw = c.face + 180.0           -- (its face, the model's z, his way: Unreal's -x here)
    end
    local K = DANCE_K
    local top = (c.head - c.feet.Z) + 20.0 + KEY_TIP * 0.3 * K       -- (where it ends: its tip 20 cm over his head bone)
    local kz = (top - 30.0 * K) / 205.0
    local p = { X = c.at.X + k.x * K, Y = c.at.Y + k.y * K, Z = c.feet.Z + 30.0 * K + (k.h - 30.0) * kz }
    local sc = math.max(0.001, k.scale * K / S)
    pcall(function()
        local actor = c.st.inst.actor
        actor:K2_TeleportTo(p, { Pitch = 0.0, Yaw = k.yaw, Roll = c.st.roll or 0.0 })
        actor:SetActorScale3D({ X = sc, Y = sc, Z = sc })
    end)
    if k.n <= 35 then spark_add(world, p.X, p.Y, p.Z, 1.2, -15.0 * K) end
end

-- where the dance's camera stands for a shot: (x his left, y up, z behind him) about his feet, in his facing
local function dance_point(c, o)
    local f = math.rad(c.face)
    local fx, fy = cos(f), sin(f)
    local rx, ry = -fy, fx                 -- (his right)
    local k = DANCE_K
    return { X = c.feet.X + (fx * -o[3] + rx * -o[1]) * k, Y = c.feet.Y + (fy * -o[3] + ry * -o[1]) * k, Z = c.feet.Z + o[2] * k }
end

-- every tick
local function dance_tick(dt)
    local c = dance
    if not c then return end
    local here = nil
    pcall(function() here = ctx.lib.world():GetAddress() end)
    if here ~= c.world then dance_stop(true); return end
    local world, pawn = ctx.lib.world(), ctx.lib.pawn()
    c.t = c.t + dt
    c.relock = c.relock - dt
    if c.relock <= 0.0 then c.relock = 0.1; cut_lock(c, true) end
    dance_cork(c, pawn, dt)
    pcall(function() local l = pawn:K2_GetActorLocation(); c.at = { X = l.X, Y = l.Y } end)
    local f = math.floor(c.t * 30.0)
    -- the shot for this frame
    local shot = DANCE_SHOTS[1]
    for _, s in ipairs(DANCE_SHOTS) do if f >= s[1] then shot = s end end
    if shot ~= c.shot then
        c.shot = shot
        -- (each cut set on where he is and the way he faces by then: the cork carries and turns him)
        c.feet.X, c.feet.Y = c.at.X, c.at.Y
        pcall(function() c.face = pawn:K2_GetActorRotation().Yaw end)
        local p, q = dance_point(c, shot[2]), dance_point(c, shot[3])
        local dx, dy, dz = q.X - p.X, q.Y - p.Y, q.Z - p.Z
        pcall(function()
            c.cam:K2_TeleportTo(p, { Pitch = math.deg(atan(dz, sqrt(dx * dx + dy * dy))), Yaw = math.deg(atan(dy, dx)),
                Roll = shot[4] * U })
        end)
    end
    -- the key round him and up over his head, a Mario 64 frame at a time
    while c.key.n <= f do
        dance_key_frame(c, world)
        spark_step(world)
    end
    c.f = f
    if c.phase == "dance" and dance_done(c, f) then
        c.phase, c.iris_t = "iris", 0.0
        -- (WARP_OP_STAR_EXIT: Mario's head closes in on him over 32 frames - transition.lua's, the shape Mario 64
        -- uses; the course goes behind the black and the next place opens as its arrival does)
        local T = package.loaded["transition"]
        if T then
            c.phase = "closing"
            T.close("mario", 32, function()
                dance_stop(false)
                pcall(function() c.st.inst.actor:SetActorHiddenInGame(true) end)
                local G = package.loaded["game"]
                pcall(function()
                    local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
                    if pawn.CharacterMovement.MovementMode == 5 and not (m and m:IsValid()) and G and G.reset_athlete then
                        G.reset_athlete(pawn, "after the key's corkscrew")
                    end
                end)
                local w = G and G.warp and G.warp[0xF0]
                if w then pcall(G.goto_scene, w.scene, w.node) else T.open("star", 16) end
            end)
            return
        end
        pcall(function() c.ui = iris_ui(world) end)
        if c.ui then iris_set(c.ui, c.ui.full) end
    elseif c.phase == "iris" then
        c.iris_t = c.iris_t + dt
        local k = math.max(0.0, 1.0 - c.iris_t / IRIS_TIME)
        if c.ui then iris_set(c.ui, c.ui.full * k) end
        if c.iris_t >= IRIS_TIME + 0.15 then
            -- black: held there by the camera while the course goes, then lifted in the next place
            local pcm = nil
            pcall(function() pcm = ctx.lib.controller().PlayerCameraManager end)
            pcall(function() pcm:StartCameraFade(1.0, 1.0, 0.0, { R = 0.0, G = 0.0, B = 0.0, A = 1.0 }, false, true) end)
            dance_stop(false)
            pcall(function() c.st.inst.actor:SetActorHiddenInGame(true) end)
            local G = package.loaded["game"]
            -- (left in STORROR's flying mode by the cork with nothing playing - the stuck-running state: its reset)
            pcall(function()
                local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
                if pawn.CharacterMovement.MovementMode == 5 and not (m and m:IsValid()) and G and G.reset_athlete then
                    G.reset_athlete(pawn, "after the key's corkscrew")
                end
            end)
            local w = G and G.warp and G.warp[0xF0]
            if w then pcall(G.goto_scene, w.scene, w.node) end
            pcall(function() pcm:StartCameraFade(1.0, 0.0, 0.8, { R = 0.0, G = 0.0, B = 0.0, A = 1.0 }, false, false) end)
        end
    end
end

-- Every tick: b his record (from the scene), dt seconds; (ax, ay, az) the athlete (scene cm, his middle)
-- His raised arm for the meteor shower: his arm's shoulder (the model's part ARM_PART, bone 11 - one of the two arm
-- chains, bones 10-16) turned about its own y by up to ARM_DEG, `b.arm` (0..1, under 0 down past it) of the way, on top
-- of the pose his animation gives it. (Unreal's rotator and quaternion, as FRotator::Quaternion / FQuat::Rotator.)
local ARM_PART, ARM_AXIS, ARM_DEG = 12, 2, 140.0        -- (its own y, 140: up and out to his side)
-- (and then about its own z, -70: on up, the hand by his head - "there needs to be a clear sign hand goes up than slams
-- into ground", 2026-11-04: by y alone it stopped at his shoulder; past 150 it swung back down)
local ARM_AXIS2, ARM_DEG2 = 3, -70.0
local HAND_PART = 15                                    -- (the hand at the end of that arm: where his fireball is held)
local function r2q(r)
    local p, y, ro = math.rad(r.Pitch) * 0.5, math.rad(r.Yaw) * 0.5, math.rad(r.Roll) * 0.5
    local SP, CP, SY, CY, SR, CR = sin(p), cos(p), sin(y), cos(y), sin(ro), cos(ro)
    return { CR * SP * SY - SR * CP * CY, -CR * SP * CY - SR * CP * SY, CR * CP * SY - SR * SP * CY, CR * CP * CY + SR * SP * SY }
end
local function q2r(q)
    local x, y, z, w = q[1], q[2], q[3], q[4]
    local sing = z * x - w * y
    local yaw = math.deg(atan(2 * (w * z + x * y), 1 - 2 * (y * y + z * z)))
    local pitch, roll
    if sing < -0.4999995 then pitch = -90.0; roll = -yaw - 2 * math.deg(atan(x, w))
    elseif sing > 0.4999995 then pitch = 90.0; roll = yaw - 2 * math.deg(atan(x, w))
    else pitch = math.deg(math.asin(2 * sing)); roll = math.deg(atan(-2 * (w * x + y * z), 1 - 2 * (x * x + y * y))) end
    return { Pitch = pitch, Yaw = yaw, Roll = roll }
end
local function qmul(a, b)
    return { a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2], a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
             a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4], a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3] }
end
function M.arm_turn(b)
    local comp = b.inst and b.inst.comps and b.inst.comps[ARM_PART]
    if not comp then return end
    local r = comp.RelativeRotation
    local base = r2q({ Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll })
    local h = math.rad(ARM_DEG * b.arm) * 0.5
    local e = { 0.0, 0.0, 0.0, cos(h) }
    e[ARM_AXIS] = sin(h)
    local q = qmul(base, e)
    if ARM_AXIS2 and b.arm > 0.0 then
        local h2 = math.rad(ARM_DEG2 * b.arm) * 0.5
        local e2 = { 0.0, 0.0, 0.0, cos(h2) }
        e2[ARM_AXIS2] = sin(h2)
        q = qmul(q, e2)
    end
    comp:K2_SetRelativeRotation(q2r(q), false, {}, true)
    -- (where his hand is: his fireball held there - update_flames' "hand")
    pcall(function()
        local hp = b.inst.comps[HAND_PART]
        local l = hp and hp:K2_GetComponentLocation()
        if l then M.hand_at = { l.X - ctx.OFFSET.X, l.Y - ctx.OFFSET.Y, l.Z - ctx.OFFSET.Z } end
    end)
end

function M.update(b, dt, world, pawn, ax, ay, az, grounded)
    if not b.stage then M.new(b, ctx.scene_name()) end
    -- (his entrance, when he is new to the arena; without a camera the fight simply begins)
    if b.cam_act == "idle" and not cut and not b.cut_tried then
        b.cut_tried = true
        if not cut_start(b, world, pawn) then b.cam_act = "end"; ctx.log("Bowser's entrance: no camera, skipped") end
    end
    M.bowser, M.arena_z = b, b.hz or b.z
    local c0 = os.clock()
    if world then pcall(M.flames_ahead, world) end
    -- (the frame times seen in the fight, for its hitches - read and reset from outside: the longest, how many over 50 ms,
    -- and the fight's own dearest tick, each with what he was doing)
    local PF = M.perf or { max = 0.0, slow = 0, cost = 0.0 }
    M.perf = PF
    if dt > PF.max then PF.max, PF.max_act = dt, b.act end
    if dt > 0.05 then PF.slow = PF.slow + 1 end
    -- (the final fight: quicker on each floor down - M.PC.speeds; and the floor he is on is the athlete's floor too:
    -- under it by 9 m and more he has fallen off - game.lua's fall-out takes 12 m under its lowest floor)
    b.acc = (b.acc or 0.0) + dt * (b.speed or 1.0)
    -- (his shadow on its own clock, at 1.0 whatever the floor's - M.clone_step: "the ghost bowser should be purely 1.0x
    -- speed", 2026-11-04)
    if M.clone then M.clone.acc = math.min((M.clone.acc or 0.0) + dt, 4.0 * FRAME) end
    if b.pancake then
        local G = package.loaded["game"]
        if G then
            G.pancake_floor = b.lvl
            if G.floor then G.floor.min_z = floor_top(b.lvl) - ((b.fin and b.fin.phase >= 2) and 6000.0 or 900.0) end
        end
        if not M.debris then pcall(debris_build, world) end
        if not (M.air and M.air.world == here_world() and (#M.air.list >= M.AIRBOMB.n or M.air.short)) then pcall(air_build, world) end
        if not M.expo then expo(true) end
        if not b.eyes and M.eyes_on then pcall(M.eyes_on, b, world) end
        if not (M.ghosts and M.ghosts.world == here_world() and M.ghosts.done) and M.ghosts_build then pcall(M.ghosts_build, world) end
        pcall(M.liquid_tick, world, dt)
        -- (the run's chrome sky over the last fight too - game.lua G.chrome_sky_up: "wheres the new texture for the
        -- backround that we made?", 2026-11-03)
        if G and G.chrome_sky_up and not (M.sky and M.sky.world == here_world()) then
            local L = G.RUN_LAVA and G.RUN_LAVA.bitdw
            local K = L and L.chrome and L.chrome.sky
            -- (its picture with the stars and ribbons below the horizon too - tools/final_sky_tex.py: in the run the lava
            -- hides that half, black; here the floors hang in the open - "also the backround is half black", 2026-11-04)
            if K then
                local K2 = {}
                for k, v in pairs(K) do K2[k] = v end
                K2.tex = "final_sky"
                K = K2
            end
            local ok, a = false, nil
            if K then ok, a = pcall(G.chrome_sky_up, K) end
            M.sky = { world = here_world(), actor = (ok and a) or false }
            ctx.log("final fight: the chrome sky %s", (ok and a) and "up" or "not made")
        end
    end
    pcall(catch_tick, pawn, world, dt)
    if M.air then pcall(air_tick, world, dt, ax, ay, az) end
    pcall(debris_tick, dt)
    pcall(puffs_tick, dt)
    local n = 0
    local steps = math.min(4, math.floor(b.acc / FRAME))
    while b.acc >= FRAME and n < 4 do
        b.acc = b.acc - FRAME
        n = n + 1
        b.dpx, b.dpy, b.dpz = b.x, b.y, b.z            -- (where this step starts: he is drawn eased from here, below)
        if b.dead then
            sense(b, ax, ay, az)
            dead(b, world, ax, ay)
        elseif b.held then
            -- (hurt while he swings him - anything that counts, health.lua M.last_hurt: Bowser is dropped, as the flame
            -- drops him - "if players damaged while holding bowsers tail the player should drop bowser", 2026-11-02)
            local HP = _G.HEALTH
            if HP and HP.last_hurt and HP.last_hurt > (b.held_at or 0.0) then
                let_go(b, pawn, ax, ay, "hurt")
            else
                held(b, FRAME, world, pawn, ax, ay)
            end
        else
            cut_frame(b)
            step(b, world, ax, ay, az, pawn)
            if b.act ~= "hitmine" and b.act ~= "fallen" then physics(b) end
            if b.act == "thrown" and hit_mine(b, world) then hit(b, world) end
            -- off the arena: in the lava, or fallen far (bowser_check_fallen_off_stage)
            -- (while the Fire Sea's arena rocks, its low side drops far: only the lava counts)
            local low = arena_tilting() and (b.z < b.hz - 2000.0 * S)
                or (not arena_tilting() and (b.z < b.hz - 1000.0 * S or (b.landed and b.floor and b.floor < b.hz - 300.0)))
            if not b.dead and b.act ~= "fallen" and b.act ~= "hitmine" and b.act ~= "shatter" and low then
                go(b, "fallen")
            end
            touch(b, pawn, ax, ay, az)
        end
        if M.clone and M.clone_step then M.clone_step(world, ax, ay, az, pawn) end
        advance_anim(b)
        update_grand()
        update_key()
        if not dance then spark_step(world) end
        -- (his key taken: its dance)
        if M.key_star and M.key_star.taken and not M.key_danced then M.key_danced = true; M.key_dance(M.key_star) end
        update_flames(world, ax, ay, az, grounded, n >= steps)
        update_waves(ax, ay, az, grounded)
    end
    if b.acc > FRAME then b.acc = 0.0 end
    if cut then cut_tick(b, dt, pawn) end
    -- (what a tick costs, in ms, smoothed: to keep an eye on the flames)
    M.cost = (M.cost or 0.0) * 0.95 + (os.clock() - c0) * 1000.0 * 0.05
    do
        local ms = (os.clock() - c0) * 1000.0
        if ms > PF.cost then PF.cost, PF.cost_act = ms, b.act end
    end
    -- drawn where he is, his pose
    b.yaw = b.face + 180.0
    pcall(function() b.inst.actor:SetActorHiddenInGame(b.hidden == true) end)
    if not b.hidden then
        -- (eased between his last two steps, as the other creatures are: put where each 30th of a second left him, he
        -- went down a fall in jerks - "when bowser falls in the final bowser from the stage he also twitches",
        -- 2026-11-06. A jump of over 3 m in a step - a blink, his leap back - is drawn where it lands)
        local dx, dy, dz = b.x, b.y, b.z
        if b.dpx then
            local ex, ey, ez = b.x - b.dpx, b.y - b.dpy, b.z - b.dpz
            if ex * ex + ey * ey + ez * ez < 300.0 * 300.0 then
                local k = math.max(0.0, math.min(1.0, b.acc / FRAME))
                dx, dy, dz = b.dpx + ex * k, b.dpy + ey * k, b.dpz + ez * k
            end
        end
        ctx.lib.set_pose(b.inst, dx + ctx.OFFSET.X, dy + ctx.OFFSET.Y, dz + ctx.OFFSET.Z, b.yaw)
        local a = anim_data(b, b.anim_id)
        if a and (floor(b.af) ~= b.inst.last_fi or b.arm or b.arm_was) then ctx.lib.pose(b.inst, a, b.af) end
        if b.arm then pcall(M.arm_turn, b) end
        b.arm_was = b.arm
    end
    if M.aura and M.aura_draw then pcall(M.aura_draw, b, dt) end
    if b.metal and M.metal_tick then pcall(M.metal_tick, b) end
    if M.mega and M.mega_tick then pcall(M.mega_tick, dt) end
    if M.glow and M.glow_tick then pcall(M.glow_tick, b, dt) end
    -- (his shadow, drawn the same way)
    local c = M.clone
    if c and c.inst then
        c.yaw = c.face + 180.0
        pcall(function() c.inst.actor:SetActorHiddenInGame(c.hidden == true) end)
        if not c.hidden then
            ctx.lib.set_pose(c.inst, c.x + ctx.OFFSET.X, c.y + ctx.OFFSET.Y, c.z + ctx.OFFSET.Z, c.yaw)
            local a = anim_data(c, c.anim_id)
            if a and floor(c.af) ~= c.inst.last_fi then ctx.lib.pose(c.inst, a, c.af) end
        end
    end
    if dance then dance_tick(dt) end
end

-- His shadow clone (the third floor - "finally bowser unlocks shadow clone justu, another 50% opacity bowser spawns and
-- can use 1 attack before disappearing", 2026-11-03): a second Bowser, see-through at half, stood 9 m from the athlete
-- off to one side of the real one; it makes one of his moves - a sprint, his breath, a fireball or the snipe - and is
-- gone. It hurts as he does; its tail cannot be taken, and bombs do nothing to it.
-- Metal Bowser (the last floor, from his landing on it - "when bowser lands on the final floor stage 3 turn bowser into
-- metal bowser kinda like metal mario cap does", "also give him purple eyes", "give the ghost the chrome look too",
-- 2026-11-04): every face of him chrome (textures/metal_bowser.png, tools/metal_bowser_tex.py), his eyes purple in
-- chrome (bowser_eye_metal_0/1), in materials of his own - shiny where the sun lights him (`metallic`, `rough`) - and
-- the chrome slid as the camera and he turn, `slide` pictures a turn, for its shine to move as Metal Mario's does.
-- (Mario 64's own metal picture is a chrome ball laid on by facing, worked out afresh each frame; his 1888 corners so,
-- every frame, would cost the fight its speed.) His shadow the same, see-through (M.clone_spawn).
M.METAL = { tex = "metal_bowser", metallic = 0.55, rough = 0.3, slide = 1.0,
            eyes = { ["actors__bowser__bowser_eye_left_0.rgba16"] = "bowser_eye_metal_0",
                     ["actors__bowser__bowser_eye_left_1.rgba16"] = "bowser_eye_metal_1",
                     -- (RENDER 96's model: its own eye, an eyeball - the chrome is on the face round it)
                     ["actors__bowser__bowser_eye_left.rgba32"] = "bowser_eye_r96_purple" } }
local function metal_tex(sec) return M.METAL.eyes[sec.texture or ""] or M.METAL.tex end
-- His eyes purple the whole final fight (the skin round them as it is - tools/metal_bowser_tex.py's bowser_eye_purple),
-- and on the last floor, Metal Bowser's, glowing: their purple alone (bowser_eye_glow) in the material's emission,
-- `glow` times over, pulsing - "also make his eye purple through the fight on stage 3 make his eyes glow", 2026-11-04.
M.EYES = { purple = { ["actors__bowser__bowser_eye_left_0.rgba16"] = "bowser_eye_purple_0",
                      ["actors__bowser__bowser_eye_left_1.rgba16"] = "bowser_eye_purple_1",
                      ["actors__bowser__bowser_eye_left.rgba32"] = "bowser_eye_r96_purple" },
           glow_tex = { ["actors__bowser__bowser_eye_left_0.rgba16"] = "bowser_eye_glow_0",
                        ["actors__bowser__bowser_eye_left_1.rgba16"] = "bowser_eye_glow_1",
                        ["actors__bowser__bowser_eye_left.rgba32"] = "bowser_eye_r96_glow" },
           glow = 6.0, pulse = 0.35 }
-- the layer his face's sections are drawn in, as add_sections draws them
local function eye_layer(sec)
    local L = ctx.lib
    local layer = sec.layer or "opaque"
    if layer == "opaque" and L.lit_on and L.lit_on() then layer = "lit" end
    return layer
end
function M.eyes_on(b, world)
    if b.eyes or not (b.inst and b.inst.data) then return end
    b.eyes = true
    for i, part in ipairs(b.inst.data.parts) do
        local comp = b.inst.comps[i]
        for _, sec in ipairs(part.sections or {}) do
            local tex = M.EYES.purple[sec.texture or ""]
            if comp and tex then
                local mid = ctx.lib.get_mid(world, eye_layer(sec), tex, 0.96)
                if mid then pcall(function() comp:SetMaterial(sec.id, mid) end) end
            end
        end
    end
end
-- (the glow put on a Metal Bowser eye material: its picture in the emission, kept for the pulse - M.metal_tick)
local function eye_glow(world, mid, sec, list)
    local gt = M.EYES.glow_tex[sec.texture or ""]
    if not (mid and gt) then return end
    local tex = ctx.lib.texture(world, gt)
    if not tex then return end
    pcall(function() mid:SetTextureParameterValue(FName("EmissiveTexture"), tex) end)
    list[#list + 1] = mid
end
function M.metal_on(b, world)
    if b.metal or not (b.inst and b.inst.data) then return end
    local L = ctx.lib
    local lit = L.lit_on and L.lit_on()
    local mats, slide, glow = {}, {}, {}
    for i, part in ipairs(b.inst.data.parts) do
        local comp = b.inst.comps[i]
        for _, sec in ipairs(part.sections or {}) do
            if comp then
                local tex = metal_tex(sec)
                local layer = sec.layer or "opaque"
                if layer == "opaque" and lit then layer = "lit" end
                local key = layer .. "|" .. tex
                local mid = mats[key]
                if mid == nil then
                    mid = L.get_mid(world, layer, tex, 0.97) or false
                    if mid and layer == "lit" then
                        pcall(function()
                            mid:SetScalarParameterValue(FName("MetallicFactor"), M.METAL.metallic)
                            mid:SetScalarParameterValue(FName("RoughnessFactor"), M.METAL.rough)
                        end)
                    end
                    mats[key] = mid
                    if mid and tex == M.METAL.tex then slide[#slide + 1] = mid end
                    if mid and tex ~= M.METAL.tex then eye_glow(world, mid, sec, glow) end
                end
                if mid then pcall(function() comp:SetMaterial(sec.id, mid) end) end
            end
        end
    end
    -- (every one kept here is on his faces: kept alive by them)
    b.metal = { slide = slide, glow = glow, world = here_world() }
    if M.ghost_metal then pcall(M.ghost_metal, world) end
    ctx.log("final fight: Metal Bowser (%d materials)", #slide)
end
function M.metal_tick(b)
    local m = b.metal
    if not (m and m.world == here_world()) then return end
    local yaw, pitch = 0.0, 0.0
    pcall(function()
        local r = ctx.lib.controller().PlayerCameraManager:GetCameraRotation()
        yaw, pitch = r.Yaw, r.Pitch
    end)
    local k = M.METAL.slide / 360.0
    local off = { R = ((yaw - (b.face or 0.0)) * k) % 40.0, G = (pitch * k) % 40.0, B = 1.0, A = 1.0 }
    for _, mid in ipairs(m.slide) do
        pcall(function() mid:SetVectorParameterValue(FName("BaseColorTexture_OffsetScale"), off) end)
    end
    -- (his eyes' glow, pulsing)
    local g = M.EYES.glow * (1.0 - M.EYES.pulse + M.EYES.pulse * (0.5 + 0.5 * sin(os.clock() * 5.0)))
    local col = { R = g, G = g, B = g, A = 1.0 }
    for _, mid in ipairs(m.glow or {}) do
        pcall(function() mid:SetVectorParameterValue(FName("EmissiveFactor"), col) end)
    end
end
-- The ghost's two Bowsers made once a fight, ahead, one a frame from its start, and kept - hidden between - for every
-- snap: the purple about him (M.aura) and his shadow (M.clone). Made new at each snap, their see-through material loaded
-- again from disk each time, they froze the fight a fifth of a second and more ("lag when bowser snaps finger and ghost
-- bowser spawns", 2026-11-04). His shadow chrome from his own turn to metal (M.metal_on).
M.ghosts = nil
function M.ghosts_build(world)
    local G2 = M.ghosts
    if not (G2 and G2.world == here_world()) then
        G2 = { world = here_world() }
        M.ghosts = G2
    end
    if G2.done then return end
    local data = ctx.actor_data("bowser")
    if not data then G2.done = true; return end
    local O = ctx.OFFSET
    local away = { X = O.X, Y = O.Y, Z = O.Z - 60000.0 }
    if not G2.aura then
        local inst = ctx.lib.make_instance(world, data, away, 0.0, M.AURA.scale)
        if not inst then G2.done = true; return end
        pcall(function() inst.actor:SetActorHiddenInGame(true) end)
        G2.aura = { inst = inst, mids = M.aura_skin(world, inst) }
        return
    end
    if not G2.clone then
        local inst = ctx.lib.make_instance(world, data, away, 0.0, 1.0)
        if inst then
            pcall(function() inst.actor:SetActorHiddenInGame(true) end)
            pcall(ctx.lib.see_through, world, inst, 0.5, true)
            G2.clone = { inst = inst, metal = false }
        end
        G2.done = true
        ctx.log("final fight: the ghost's two Bowsers made ahead")
    end
end
-- (the purple about him all one purple: his copy's faces plain white under the see-through purple - with his own
-- pictures, his orange under it came out red: "when bowser snaps his fingers he turns red?", 2026-11-04)
function M.aura_skin(world, inst)
    local parts = {}
    for i, part in ipairs(inst.data.parts) do
        local secs = {}
        for j, sec in ipairs(part.sections or {}) do secs[j] = { id = sec.id, texture = "aura_white" } end
        parts[i] = { sections = secs }
    end
    local mids = {}
    pcall(function() mids = ctx.lib.see_through(world, { data = { parts = parts }, comps = inst.comps }, 0.0, true) or {} end)
    return mids
end
-- (his shadow's kept Bowser turned chrome, see-through: his pictures swapped as his were - M.METAL)
function M.ghost_metal(world)
    local G2 = M.ghosts
    local gc = G2 and G2.world == here_world() and G2.clone
    if not gc or gc.metal then return end
    gc.metal = true
    local parts = {}
    for i, part in ipairs(gc.inst.data.parts) do
        local secs = {}
        for j, sec in ipairs(part.sections or {}) do secs[j] = { id = sec.id, texture = metal_tex(sec) } end
        parts[i] = { sections = secs }
    end
    pcall(ctx.lib.see_through, world, { data = { parts = parts }, comps = gc.inst.comps }, 0.5, true)
end
local CLONE_MOVES = { "charge", "breath", "spit", "snipe" }
-- The purple about him as he calls up his shadow (the "clone" act): a copy of him a little bigger, see-through and
-- purple, drawn where he is in his pose, pulsing - gone as the shadow comes, or if he is stopped first.
M.AURA = { scale = 1.08, alpha = 0.42, col = { 0.75, 0.25, 1.0 } }
-- The purple on the floor where his shadow will stand: a glow there from his snap (textures/ghost_glow.png,
-- tools/ghost_glow_tex.py), turning and pulsing, till `after` s after the shadow has come - or at once if he is stopped
-- first - then out over `fade` s ("also add a purple hue around the area that the ghost bowser spawns", 2026-11-04).
-- One for the fight, moved to each spot, hidden between. `r`: its half-width, cm.
M.GLOW = { r = 330.0, alpha = 0.9, after = 1.0, fade = 0.5, spin = 40.0 }
M.glow = nil
function M.glow_at(world, x, y, z)
    local O = ctx.OFFSET
    local G = M.glow
    if not (G and G.world == here_world()) then
        local actor = ctx.lib.spawn_actor(world, { X = x + O.X, Y = y + O.Y, Z = z + O.Z + 7.0 }, 0.0)
        local pmc = actor and ctx.lib.add_pmc(actor)
        if not pmc then return end
        pcall(function() pmc:SetCollisionEnabled(0); pmc:SetCastShadow(false) end)
        local r = M.GLOW.r
        ctx.lib.add_sections(world, pmc, { { id = 0, layer = "translucent", texture = "ghost_glow", nverts = 4, ntris = 4,
            pos = { -r, -r, 0, r, -r, 0, r, r, 0, -r, r, 0 },
            uv = { 0, 0, 1, 0, 1, 1, 0, 1 }, col = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
            nrm = { 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1 }, idx = { 0, 2, 1, 0, 3, 2, 0, 1, 2, 0, 2, 3 } } })
        -- (a material of its own, to fade: on the glow's face, so kept alive by it)
        local mid = ctx.lib.get_mid(world, "translucent", "ghost_glow", 0.98)
        if mid then pcall(function() pmc:SetMaterial(0, mid) end) end
        G = { world = here_world(), actor = actor, mid = mid }
        M.glow = G
    end
    G.x, G.y, G.z = x, y, z
    pcall(function() G.actor:K2_SetActorLocation({ X = x + O.X, Y = y + O.Y, Z = z + O.Z + 7.0 }, false, {}, true) end)
    pcall(function() G.actor:SetActorHiddenInGame(false) end)
    G.t, G.on, G.left, G.hold = 0.0, true, nil, 0.0
end
function M.glow_tick(b, dt)
    local G = M.glow
    if not (G and G.on) then return end
    if G.world ~= here_world() then M.glow = nil; return end
    G.t = G.t + dt
    if not G.left then
        if M.clone then G.left, G.hold = G.t, M.GLOW.after
        elseif b.act ~= "clone" then G.left, G.hold = G.t, 0.0 end
    end
    local a = math.min(1.0, G.t / 0.2) * (0.75 + 0.25 * sin(G.t * 9.0))
    if G.left then
        local o = (G.t - G.left - G.hold) / M.GLOW.fade
        if o >= 1.0 then
            G.on = false
            pcall(function() G.actor:SetActorHiddenInGame(true) end)
            return
        end
        if o > 0.0 then a = a * (1.0 - o) end
    end
    if G.mid then
        pcall(function() G.mid:SetVectorParameterValue(FName("BaseColorFactor"), { R = 1.0, G = 1.0, B = 1.0, A = a * M.GLOW.alpha }) end)
    end
    pcall(function() G.actor:K2_SetActorRotation({ Pitch = 0.0, Yaw = (G.t * M.GLOW.spin) % 360.0, Roll = 0.0 }, false) end)
end
M.aura = nil
function M.aura_on(b, world)
    if M.aura then return end
    local G2 = M.ghosts
    if G2 and G2.world == here_world() and G2.aura then
        for _, mid in ipairs(G2.aura.mids) do
            pcall(function() mid:SetVectorParameterValue(FName("BaseColorFactor"), { R = 1.0, G = 1.0, B = 1.0, A = 0.0 }) end)
        end
        pcall(function() G2.aura.inst.actor:SetActorHiddenInGame(false) end)
        M.aura = { inst = G2.aura.inst, mids = G2.aura.mids, t = 0.0, world = here_world(), kept = true }
        return
    end
    local data = ctx.actor_data("bowser")
    if not data then return end
    local O = ctx.OFFSET
    local inst = ctx.lib.make_instance(world, data, { X = b.x + O.X, Y = b.y + O.Y, Z = b.z + O.Z }, b.face + 180.0, M.AURA.scale)
    if not inst then return end
    local mids = {}
    pcall(function() mids = ctx.lib.see_through(world, inst, 0.0, true) or {} end)
    M.aura = { inst = inst, mids = mids, t = 0.0, world = here_world() }
end
function M.aura_off()
    local a = M.aura
    M.aura = nil
    if a and a.world == here_world() then
        pcall(function() a.inst.actor:SetActorHiddenInGame(true) end)
        if not a.kept then pcall(ctx.lib.destroy, a.inst.actor) end
    end
end
function M.aura_draw(b, dt)
    local a = M.aura
    if not a then return end
    if a.world ~= here_world() then M.aura = nil; return end
    if b.act ~= "clone" or b.hidden then M.aura_off(); return end
    a.t = a.t + dt
    local k = math.min(1.0, a.t / 0.12)
    local al = M.AURA.alpha * k * (0.8 + 0.2 * sin(a.t * 14.0))
    local C = M.AURA.col
    local col = { R = C[1], G = C[2], B = C[3], A = al }
    for _, mid in ipairs(a.mids) do pcall(function() mid:SetVectorParameterValue(FName("BaseColorFactor"), col) end) end
    local O = ctx.OFFSET
    ctx.lib.set_pose(a.inst, b.x + O.X, b.y + O.Y, b.z + O.Z, b.yaw)
    local an = anim_data(b, b.anim_id)
    if an and floor(b.af) ~= a.inst.last_fi then ctx.lib.pose(a.inst, an, b.af) end
end
-- where his shadow will stand: off to one side of the athlete, on the floor (or halfway in to the middle)
function M.clone_spot(b, ax, ay)
    local top = b.hz or b.z
    local side = (math.random() < 0.5) and 1.0 or -1.0
    local a = math.atan(ay - b.y, ax - b.x) + side * math.rad(80.0 + math.random() * 40.0)
    local x, y = ax + cos(a) * 900.0, ay + sin(a) * 900.0
    local z = ground(x, y, top + 150.0, 0.0)
    if not z or z < top - 300.0 then
        x, y = ax * 0.5, ay * 0.5
        z = ground(x, y, top + 150.0, 0.0) or top
    end
    return { x, y, z }
end
function M.clone_spawn(b, world, ax, ay, at)
    if M.clone then return end
    local data = ctx.actor_data("bowser")
    if not data then return end
    local top = b.hz or b.z
    at = at or M.clone_spot(b, ax, ay)
    local x, y, z = at[1], at[2], at[3]
    local O = ctx.OFFSET
    local G2 = M.ghosts
    local gc = G2 and G2.world == here_world() and G2.clone
    if gc and not gc.busy then
        -- (the kept one - M.ghosts_build)
        if b.metal then M.ghost_metal(world) end
        gc.busy = true
        local inst = gc.inst
        ctx.lib.set_pose(inst, x + O.X, y + O.Y, z + O.Z, 0.0)
        pcall(function() inst.actor:SetActorHiddenInGame(false) end)
        local c = { inst = inst, x = x, y = y, z = z, face = yaw_to(x, y, ax, ay), fvel = 0.0, vz = 0.0, stage = "bits",
                    pancake = true, lvl = b.lvl, clone = true, health = 1, hz = top, hidden = false, cam_act = "end",
                    world = here_world(), acc = 0.0, kept = true }
        go(c, CLONE_MOVES[math.random(1, #CLONE_MOVES)])
        set_anim(c, A.idle)
        c.chain, c.sprint_k = nil, 1
        M.clone = c
        sfx("bowser_teleport", 1.0)
        ctx.log("final fight: his shadow - %s", c.act)
        return
    end
    local inst = ctx.lib.make_instance(world, data, { X = x + O.X, Y = y + O.Y, Z = z + O.Z }, 0.0, 1.0)
    if not inst then return end
    if b.metal then
        -- (Metal Bowser's shadow chrome too, his pictures swapped as his were - M.METAL)
        local parts = {}
        for i, part in ipairs(inst.data.parts) do
            local secs = {}
            for j, sec in ipairs(part.sections or {}) do secs[j] = { id = sec.id, texture = metal_tex(sec) } end
            parts[i] = { sections = secs }
        end
        pcall(ctx.lib.see_through, world, { data = { parts = parts }, comps = inst.comps }, 0.5, true)
    else
        pcall(ctx.lib.see_through, world, inst, 0.5, true)
    end
    local c = { inst = inst, x = x, y = y, z = z, face = yaw_to(x, y, ax, ay), fvel = 0.0, vz = 0.0, stage = "bits",
                pancake = true, lvl = b.lvl, clone = true, health = 1, hz = top, hidden = false, cam_act = "end",
                world = here_world(), acc = 0.0 }
    go(c, CLONE_MOVES[math.random(1, #CLONE_MOVES)])
    set_anim(c, A.idle)
    -- (one run of its sprint, not two: "ghost bowser can only charge once as well", 2026-11-04)
    c.chain, c.sprint_k = nil, 1
    M.clone = c
    sfx("bowser_teleport", 1.0)
    ctx.log("final fight: his shadow - %s", c.act)
end
function M.clone_gone()
    local c = M.clone
    M.clone = nil
    if not c then return end
    sfx("bowser_teleport", 0.8)
    if c.world == here_world() then
        pcall(function() c.inst.actor:SetActorHiddenInGame(true) end)
        if c.kept then
            local G2 = M.ghosts
            if G2 and G2.clone and G2.clone.inst == c.inst then G2.clone.busy = false end
        else
            pcall(ctx.lib.destroy, c.inst.actor)
        end
    end
end
function M.clone_step(world, ax, ay, az, pawn)
    local c = M.clone
    if not c then return end
    if c.world ~= here_world() then M.clone = nil; return end
    -- (a frame of its own only as its clock has one: called at each of Bowser's, quicker on the lower floors)
    if (c.acc or 0.0) < FRAME then return end
    c.acc = c.acc - FRAME
    step(c, world, ax, ay, az, pawn)
    if c.act ~= "hitmine" then physics(c) end
    advance_anim(c)
    -- (its body: a bump, or a ram as it runs - never its tail)
    if not c.hidden then
        local d = sqrt((ax - c.x) ^ 2 + (ay - c.y) ^ 2)
        if d < 200.0 and az > c.z - 50.0 and az < c.z + 380.0 and ctx.hurt then
            local kind = (c.act == "charge" and c.fvel > 15.0 * S) and "ram" or "body"
            local hx, hy = ax - c.x, ay - c.y
            if kind == "ram" then
                local f, dd = math.rad(c.face), math.max(1.0, sqrt(hx * hx + hy * hy))
                hx, hy = cos(f) + hx / dd * 0.6, sin(f) + hy / dd * 0.6
                c.chain = nil                   -- (his shadow's sprint too: ended by a hit)
            end
            ctx.hurt(kind, "Bowser's shadow", hx, hy)
        end
    end
    -- its one move made (back to standing about), or off the floor: gone
    if c.act == "default" or c.timer > 450 or c.z < (c.hz or c.z) - 600.0 then M.clone_gone() end
end
M.dance_tick = function(dt) if dance then dance_tick(dt) end end      -- (tests: the dance away from Bowser)

return M
