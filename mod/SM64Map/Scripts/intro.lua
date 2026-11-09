-- SM64Map: Mario 64's opening for a brand new file, with the STORROR athlete in Mario's place.
--
-- As the game plays it: Peach stands in the sky while her letter fades in; the camera flies down and round
-- the castle behind Lakitu; a pipe rises from the grass; the athlete jumps out of it; and then the game is
-- the player's. The camera's path, Lakitu's, Peach, the letter and the timings are the game's own, worked
-- out from the player's copy by the exporter (introx.py -> data/intro.lua, 30 frames a second). It
-- cannot be skipped. (Mario 64 ends the scene with a message about its controls. They are not this
-- game's controls, and the message is left out: MESSAGE below brings it back.)
--
-- Laid out for a 16:9 screen: the game's 4:3 picture stands in the middle of it, its full height.
local lib = require("lib")
local pad = require("pad")
local log = lib.log
local okM, MUSIC = pcall(require, "music")
if not okM then MUSIC = nil end
-- The scene's sound: Peach's jingle and her voice reading the letter, Lakitu's flying music and the sounds of
-- the flight, the pipe and the jump, all in one recording made from the player's own copy of the game by
-- sm64audio (Mario 64's own sound engine, timed to this scene's frames): music/intro_new_file.m4a.
local SOUNDTRACK = "intro_new_file"

local I = { active = false }

local OFFSET = lib.OFFSET
local sin, cos, tan, atan, sqrt, floor, abs, rad, deg = math.sin, math.cos, math.tan, math.atan, math.sqrt, math.floor, math.abs, math.rad, math.deg
local max, min = math.max, math.min

local ASPECT = 16.0 / 9.0
local JUMP_UP = 900.0               -- how hard the athlete comes out of the pipe (cm a second, upward; the
                                    -- game's pull is 1500): well clear of the pipe, and a clean landing
local JUMP_FORWARD = 120.0          -- and forward (toward the camera, which watches from in front of the pipe)
local PIPE_PULL = 1.6               -- at the pipe the camera stands this many times further back than Mario 64's,
                                    -- so that a full-size athlete jumping out does not come through it
local CAMERA_ROOM = 380.0           -- and never nearer him than this (cm)
-- The front flip out of the pipe. STORROR's own flips are its animation system's to start (asking it for one
-- from here is ignored while he is in the air), so the flip is made here: his body is turned once round,
-- head first, about his middle, while he is in the air, and put back exactly as it was before he lands.
local FLIP_AFTER, FLIP_TIME = 0.12, 0.85    -- seconds after leaving the pipe it starts, and how long it takes
local FLIP = false                  -- OFF: turning his body by hand makes STORROR's physics treat it as a crash,
                                    -- and he lands in a heap. Kept for when there is a way to ask STORROR itself.
local RETURN_BLEND = 2.2            -- seconds the camera takes to come round behind the athlete at the end,
                                    -- easing out of the scene's camera and into the game's (not a straight swing)
local MESSAGE = false               -- whether the message at the pipe is shown
local BURIED = 500.0                -- how far under the grass the athlete waits for his moment
local AFTER_PIPE = 20.0             -- frames from the pipe having gone to the camera coming back
local BLEND = "/InterchangeAssets/gltf/MaterialInstances/MI_Unlit_Blend.MI_Unlit_Blend"     -- a see-through material, for Peach's fading
-- The sky behind the letter. The scene opens looking almost straight up, where the mod's sky has only its
-- plain top colour; Mario 64 shows the top of its sky picture there, clouds and all. So for the letter a
-- sheet of the sky picture stands far behind Peach, filling the view, and fades once the camera tilts down.
local SKY_D = 60000.0               -- how far away it stands (cm)
local SKY_FADE_FROM, SKY_FADE_TO = 62.0, 52.0      -- it fades as the camera tilts down from this steep (degrees) to this
local SHOT_W, SHOT_H = 1440.0, 1080.0       -- the game's 320x240 screen on a 1920x1080 one
local LETTER_LEFT = -240.0          -- the letter sits this much left of where the game puts it: on a wide screen
                                    -- there is room for it beside Peach instead of over her face

-- (the game draws Peach's eyes and mouth with their pictures held at the edges, not repeated)
lib.CLAMP["actors__peach__peach_eye_mostly_open.rgba16"] = true
lib.CLAMP["actors__peach__peach_lips.rgba16"] = true
-- (and her crown: its jewel picture held at the edges, gold past it - wrapped, the crown, whose coordinates run well
-- past the picture, showed jewels repeated all over it: "peaches crown texture is messed up", 2026-11-01)
lib.CLAMP["actors__peach__peach_crown_jewel.rgba16"] = true

local st = nil

-- ------------------------------------------------------------ the front flip
local spin = nil                    -- { mesh, loc, quat, t0 } while one is under way

local function to_quat(r)           -- an engine rotation (degrees) as a quaternion (x, y, z, w)
    local p, y, ro = rad(r.Pitch) / 2.0, rad(r.Yaw) / 2.0, rad(r.Roll) / 2.0
    local sp, cp, sy, cy, sr, cr = sin(p), cos(p), sin(y), cos(y), sin(ro), cos(ro)
    return { cr * sp * sy - sr * cp * cy, -cr * sp * cy - sr * cp * sy, cr * cp * sy - sr * sp * cy, cr * cp * cy + sr * sp * sy }
end

local function to_rot(q)
    local x, y, z, w = q[1], q[2], q[3], q[4]
    local sp = 2.0 * (w * y - z * x)
    local pitch = deg(math.asin(max(-1.0, min(1.0, sp))))
    local yaw = deg(atan(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z)))
    local roll = deg(atan(2.0 * (w * x + y * z), 1.0 - 2.0 * (x * x + y * y)))
    return { Pitch = pitch, Yaw = yaw, Roll = roll }
end

local function qmul(a, b)
    return { a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2],
             a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
             a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4],
             a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3] }
end

local function spin_set(mesh, loc, rot)
    pcall(function() mesh:K2_SetRelativeLocationAndRotation(loc, rot, false, {}, true) end)
end

local function spin_start(pawn, t0)
    local mesh = pawn.Mesh
    if not (mesh and mesh:IsValid()) then return end
    local l, r = mesh.RelativeLocation, mesh.RelativeRotation
    spin = { mesh = mesh, loc = { X = l.X, Y = l.Y, Z = l.Z }, rot = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll }, t0 = t0 }
    spin.quat = to_quat(spin.rot)
end

local function spin_end()
    if spin then spin_set(spin.mesh, spin.loc, spin.rot) end
    spin = nil
end

-- (every tick) the body turned the right amount: head forward and down, once round, about his middle (the
-- actor's own centre; the body hangs below it by its own offset, which is turned with it)
local function spin_tick(now)
    if not spin then return end
    if not pcall(function() return spin.mesh:IsValid() end) then spin = nil; return end
    local k = (now - spin.t0 - FLIP_AFTER) / FLIP_TIME
    if k < 0.0 then return end
    if k >= 1.0 then spin_end(); return end
    local e = k * k * (3.0 - 2.0 * k)
    local a = -2.0 * math.pi * e                    -- about his right-hand axis: forward over
    local qs = { 0.0, sin(a / 2.0), 0.0, cos(a / 2.0) }
    local L = spin.loc
    local c, sn = cos(a), sin(a)
    -- (turning the offset by the same angle about the actor's y axis)
    local loc = { X = L.X * c + L.Z * sn, Y = L.Y, Z = -L.X * sn + L.Z * c }
    spin_set(spin.mesh, loc, to_rot(qmul(qs, spin.quat)))
end

-- (tests) a jump and a flip on the spot
function I.flip_test()
    local pawn = lib.pawn()
    if not pawn then return false end
    pcall(function()
        local l = pawn:K2_GetActorLocation()
        pawn:K2_TeleportTo({ X = l.X, Y = l.Y, Z = l.Z + 30.0 }, pawn:K2_GetActorRotation())
        pawn.CharacterMovement:SetMovementMode(3, 0)
    end)
    lib.bounce(pawn, JUMP_FORWARD, 0.0, JUMP_UP)
    spin_start(pawn, os.clock())
    return true
end

local function valid(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end
local function wpos(p, i) return { X = p[i] + OFFSET.X, Y = p[i + 1] + OFFSET.Y, Z = p[i + 2] + OFFSET.Z } end

-- ------------------------------------------------------------ what is on the screen: the letter, the message
local serial = 0
local function build_ui(pc, world, pages)
    local function cls(p) return StaticFindObject(p) end
    serial = serial + 1
    local n = tostring(serial)
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("SM64Intro" .. n))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("SM64IntroTree" .. n))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SM64IntroCanvas" .. n))
    tree.RootWidget = canvas
    local count = 0
    local function shot(file, dx)
        count = count + 1
        local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("SM64IntroImg" .. n .. "_" .. count))
        local tex = lib.texture(world, file)
        if tex then img:SetBrushFromTexture(tex, false) end
        local slot = canvas:AddChildToCanvas(img)
        slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
        slot:SetAlignment({ X = 0.5, Y = 0.5 })
        slot:SetSize({ X = SHOT_W, Y = SHOT_H })
        slot:SetPosition({ X = dx or 0.0, Y = 0.0 })
        img:SetRenderOpacity(0.0)
        return img
    end
    local ui = { widget = w, letter = shot("intro_letter", LETTER_LEFT), pages = {}, letter_a = 0.0, page = 0 }
    for i = 1, pages do ui.pages[i] = shot("intro_dialog_" .. i) end
    w:AddToViewport(60)
    return ui
end

-- ------------------------------------------------------------ starting
-- Called when a brand new file has just been put into the castle grounds. Returns true if the opening is on.
function I.start()
    I.stop()
    local world, pc, pawn = lib.world(), lib.controller(), lib.pawn()
    if not (world and pc and pawn) then return false end
    local data = lib.load_data("data.intro")
    if not (data and data.cam and data.frames and data.frames > 10) then return false end
    local s = { data = data, world = world:GetAddress(), f = 0.0, t = 0.0, look = nil, fov = nil }

    -- the athlete waits out of sight where the pipe will come up, and does not answer the controls
    pcall(function()
        local cm = pawn.CharacterMovement
        cm:StopMovementImmediately()
        cm:SetMovementMode(0, 0)
    end)
    pcall(function() pawn:SetActorHiddenInGame(true) end)
    pcall(function() pawn:DisableInput(pc) end)
    -- (hiding him is not enough: the game shows him again by itself. He waits under the grass.)
    s.hole = { X = data.start[1] + OFFSET.X, Y = data.start[2] + OFFSET.Y, Z = data.start[3] + OFFSET.Z - BURIED }
    -- (Being moved sets a character falling again, so he is stopped after the move, not before.)
    pcall(function()
        pawn:K2_TeleportTo(s.hole, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
        local cm = pawn.CharacterMovement
        cm:SetMovementMode(0, 0)
        cm:StopMovementImmediately()
    end)
    if _G.SM64 then _G.SM64.no_fall_until = os.clock() + 3600.0 end       -- (none of this is a fall)

    local cam = lib.camera(world, "intro", wpos(data.cam, 1), { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
    if not valid(cam) then
        log("intro: no camera")
        pcall(function() pawn:SetActorHiddenInGame(false); pawn:EnableInput(pc); pawn.CharacterMovement:SetMovementMode(3, 0) end)
        return false
    end
    s.cam = cam
    pcall(function() pc:SetViewTargetWithBlend(cam, 0.0, 0, 0.0, false) end)

    local okw, ui = pcall(build_ui, pc, world, data.dialog_pages or 0)
    if okw then s.ui = ui else log("intro: no letter (%s)", tostring(ui)) end

    -- Lakitu and the pipe, both out of sight until their moment
    local function actor(name, at)
        local d = lib.load_data("data.actor_" .. name)
        if not d then return nil end
        local inst = lib.make_instance(world, d, at, 0.0, 1.0)
        if inst then
            inst.moves = true                       -- (it is placed from here every frame)
            pcall(function() inst.actor:SetActorHiddenInGame(true) end)
        end
        return inst
    end
    -- the sky sheet, square to the camera's first view
    pcall(function()
        local C = data.cam
        local px, py, pz, fx, fy, fz = C[1], C[2], C[3], C[4], C[5], C[6]
        local dx, dy, dz = fx - px, fy - py, fz - pz
        local yaw, pitch = atan(dy, dx), atan(dz, sqrt(dx * dx + dy * dy))
        local cp, sp, cy, sy = cos(pitch), sin(pitch), cos(yaw), sin(yaw)
        local F, R, U = { cp * cy, cp * sy, sp }, { -sy, cy, 0.0 }, { -sp * cy, -sp * sy, cp }
        local w, h = SKY_D * 1.8, SKY_D * 1.5           -- (big enough that its edge never shows before it has faded)
        local at = { X = px + F[1] * SKY_D + OFFSET.X, Y = py + F[2] * SKY_D + OFFSET.Y, Z = pz + F[3] * SKY_D + OFFSET.Z }
        local a = lib.spawn_actor(world, at, 0.0)
        local pmc = a and lib.add_pmc(a)
        if not pmc then lib.destroy(a); return end
        pcall(function() pmc:SetCollisionEnabled(0) end)
        pcall(function() pmc:SetCastShadow(false) end)
        local function corner(i, j) return { X = R[1] * w * i + U[1] * h * j, Y = R[2] * w * i + U[2] * h * j, Z = R[3] * w * i + U[3] * h * j } end
        local verts = { corner(-1, 1), corner(1, 1), corner(1, -1), corner(-1, -1) }
        local n = { X = -F[1], Y = -F[2], Z = -F[3] }
        local c = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
        -- (the upper part of the sky picture, its clouds: not the sea along its bottom)
        local uvs = { { X = 0.0, Y = 0.0 }, { X = 1.7, Y = 0.0 }, { X = 1.7, Y = 0.55 }, { X = 0.0, Y = 0.55 } }
        lib.create_section(pmc, 0, verts, { 0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2 }, { n, n, n, n }, uvs, { c, c, c, c }, false)
        local KML = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
        local mid = KML:CreateDynamicMaterialInstance(world, lib.try_load(BLEND), FName("SM64IntroSky" .. floor(os.clock() * 1000)), 0)
        local skyname = (_G.SM64 and _G.SM64.data and _G.SM64.data.sky) or "water"
        local tex = lib.texture(world, "sky_" .. skyname)
        if tex then mid:SetTextureParameterValue(FName("BaseColorTexture"), tex) end
        pmc:SetMaterial(0, mid)
        s.sky, s.sky_mid, s.sky_a = a, mid, 1.0
    end)
    s.lakitu = actor("lakitu", wpos(data.cam, 1))
    -- (his cloud, intro_lakitu.inc.c -> bhvCloud: five mist puffs; he flew bare, 2026-10-15)
    s.lakitu_cloud = {}
    for i = 1, 5 do
        local p = actor("mist", wpos(data.cam, 1))
        if p then
            pcall(function() p.actor:SetActorScale3D({ X = 4.0 / 3.0, Y = 4.0 / 3.0, Z = 4.0 / 3.0 }) end)
            s.lakitu_cloud[#s.lakitu_cloud + 1] = p
        end
    end
    s.pipe = actor("pipe", wpos(data.pipe.pos, 1))
    s.lakitu_on, s.pipe_on = false, false
    -- Peach: she holds the last pose of her animation, as she does in the game
    if data.peach then
        s.peach = actor("peach", wpos(data.peach.pos, 1))
        if s.peach then
            local anim = s.peach.data.anims and s.peach.data.anims[1]
            if anim then lib.pose(s.peach, anim, anim.frames - 1) end
            local P = data.peach
            pcall(function()
                s.peach.actor:K2_TeleportTo(wpos(P.pos, 1), { Pitch = P.rot[1], Yaw = P.rot[2], Roll = P.rot[3] })
                s.peach.actor:SetActorHiddenInGame(false)
            end)
            s.peach_a = 1.0
        end
    end

    if _G.HEALTH then _G.HEALTH.hud_off = true end
    if _G.MENU and _G.MENU.hide_game_ui then pcall(_G.MENU.hide_game_ui) end
    -- (once, the 50 s it lasts, at its own level - not the in-game music slider's - with the grounds' birds and
    -- waterfall off till it ends: see music.lua M.full. They were a quarter loud, and the outdoors' remix - the
    -- nature sounds - came through over it: "outside music plays over intro music", 2026-11-01)
    if MUSIC then pcall(MUSIC.play, SOUNDTRACK, true, true); if MUSIC.hush then pcall(MUSIC.hush, 0.0) end end
    -- (with REMIX MUSIC on, the remix is music only: the scene's own sounds - Peach's "Dear Mario", Lakitu's flight,
    -- the pipe, his "Yahoo!", his landing and "Ha-ha!" - with it from sfx/intro_sfx.wav, the same timeline rendered
    -- from the ROM by sm64audio without the music (sm64audio/intro_sfx_timeline.txt), started with it, in step:
    -- "you can use this video for an example of whats supposed to happen", 2026-11-01)
    s.sfx_track = false
    pcall(function()
        local SFX = package.loaded["sfx"]
        if MUSIC and MUSIC.remix and SFX and SFX.play then s.sfx_track = SFX.play("intro_sfx", 1.0, true) and true or false end
    end)
    pad.reset()
    st = s
    I.active = true
    log("intro: started (%d frames)", data.frames)
    return true
end

-- ------------------------------------------------------------ ending
local function release(s, blend)
    local pc, pawn = lib.controller(), lib.pawn()
    if pawn then
        pcall(function() pawn:SetActorHiddenInGame(false) end)
        if pc then pcall(function() pawn:EnableInput(pc) end) end
        if not s.jumped then
            -- (skipped before he came out of the pipe: he simply stands where the pipe would have been)
            pcall(function()
                pawn:K2_TeleportTo({ X = s.data.start[1] + OFFSET.X, Y = s.data.start[2] + OFFSET.Y, Z = s.data.start[3] + OFFSET.Z + 120.0 },
                    { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
                pawn.CharacterMovement.GravityScale = 1.0
                pawn.CharacterMovement:SetMovementMode(3, 0)
            end)
        end
        if _G.SM64 then _G.SM64.no_fall_until = os.clock() + 2.0 end
        if pc then pcall(function() pc:SetViewTargetWithBlend(pawn, blend, (blend > 0.0) and 4 or 0, 2.0, false) end) end
    end
    if _G.HEALTH then _G.HEALTH.hud_off = false end
    if _G.MENU and _G.MENU.show_game_ui then pcall(_G.MENU.show_game_ui) end
    -- and the level's own tune takes over (and the birds and the waterfall come back)
    if MUSIC then
        if MUSIC.hush then pcall(MUSIC.hush, 1.0) end
        pcall(MUSIC.play, (_G.SM64 and _G.SM64.data and _G.SM64.data.music) or nil)
    end
end

function I.stop()
    local s = st
    st = nil
    I.active = false
    if not s then return end
    if s.sfx_track then pcall(function() package.loaded["sfx"].stop("intro_sfx") end) end
    if s.ui then pcall(function() s.ui.widget:RemoveFromParent() end) end
    local same = false
    pcall(function() same = lib.world():GetAddress() == s.world end)
    if same then
        release(s, s.blend or 0.0)
        -- (the camera is left for the blend to finish from; a scene being cleared away takes it with it)
        s.old_cam = s.cam
        lib.destroy(s.lakitu and s.lakitu.actor)
        for _, p in ipairs(s.lakitu_cloud or {}) do lib.destroy(p.actor) end
        lib.destroy(s.pipe and s.pipe.actor)
        lib.destroy(s.peach and s.peach.actor)
        lib.destroy(s.sky)
        local cam = s.cam
        if s.blend and s.blend > 0.0 then I.leftover = { cam = cam, at = os.clock() + s.blend + 0.5 }
        end                             -- (its camera stays: lib.camera)
    end
    log("intro: over")
end

-- ------------------------------------------------------------ every frame
local function lerp(a, i, j, t, k) return a[i + k] + (a[j + k] - a[i + k]) * t end

local function turn(a, b, t)            -- from angle a toward b the short way round
    local d = (b - a + 180.0) % 360.0 - 180.0
    return a + d * t
end

function I.tick(dt)
    spin_tick(os.clock())
    if I.leftover and os.clock() >= I.leftover.at then
        I.leftover = nil                -- (its camera stays: lib.camera)
    end
    local s = st
    if not (s and I.active) then return end
    local world, pc, pawn = lib.world(), lib.controller(), lib.pawn()
    if not (world and pc and pawn) or world:GetAddress() ~= s.world then
        st = nil
        I.active = false
        if _G.HEALTH then _G.HEALTH.hud_off = false end
        return
    end
    local data = s.data
    s.t = s.t + dt

    -- (the Mario face and clothes put on him while he waits out of sight under the pipe: their tick is the pause menu's,
    -- which the game's own tick runs, and that does not run through the intro - on a new install he came out of the pipe
    -- as STORROR's athlete and only turned into Mario after the intro: "when the player came out the pipe he didnt look
    -- like mario", 2026-11-09)
    do
        local CP, CL = package.loaded["charpick"], package.loaded["clothpick"]
        if CP and CP.tick then pcall(CP.tick, dt, false) end
        if CL and CL.tick then pcall(CL.tick, dt, false) end
    end

    local last = data.frames - 1
    if not s.talking then s.f = min(s.f + dt * data.fps, last) end
    local f = s.f
    local i = min(floor(f), last)
    local j = min(i + 1, last)
    local t = f - i

    -- the camera
    local C = data.cam
    local a, b = i * 7, j * 7
    local px, py, pz = lerp(C, a, b, t, 1), lerp(C, a, b, t, 2), lerp(C, a, b, t, 3)
    local fx, fy, fz = lerp(C, a, b, t, 4), lerp(C, a, b, t, 5), lerp(C, a, b, t, 6)
    local fov = lerp(C, a, b, t, 7)
    if f >= data.pipe_shot_at then
        -- at the pipe the camera looks up as he comes out: never below a point that follows his height
        local loc = pawn:K2_GetActorLocation()
        local feet = loc.Z - OFFSET.Z - (s.half or 90.0)
        local ground = data.start[3]
        local want = ground + 60.0 + (max(feet, ground) - ground) * 1.1
        s.look = s.look or (ground + 105.0)
        s.look = s.look + (want - s.look) * (1.0 - 0.6 ^ (dt * 30.0))
        if s.jumped and fz < s.look then fz = s.look end
    end
    if f >= data.pipe_shot_at then
        -- (drawn back level, never lower than Mario 64 has it: drawn back along its line of sight it would
        -- go under the grass when it looks up)
        px, py = fx + (px - fx) * PIPE_PULL, fy + (py - fy) * PIPE_PULL
        if s.jumped then
            local loc = pawn:K2_GetActorLocation()
            local ox, oy = px - (loc.X - OFFSET.X), py - (loc.Y - OFFSET.Y)
            local d = sqrt(ox * ox + oy * oy)
            if d < CAMERA_ROOM and d > 1.0 then
                px, py = (loc.X - OFFSET.X) + ox / d * CAMERA_ROOM, (loc.Y - OFFSET.Y) + oy / d * CAMERA_ROOM
            end
        end
    end
    local dx, dy, dz = fx - px, fy - py, fz - pz
    local yaw, pitch = deg(atan(dy, dx)), deg(atan(dz, sqrt(dx * dx + dy * dy)))
    s.cam_pitch = pitch
    s.cam_at = { px, py, pz }
    pcall(function()
        s.cam:K2_TeleportTo({ X = px + OFFSET.X, Y = py + OFFSET.Y, Z = pz + OFFSET.Z }, { Pitch = pitch, Yaw = yaw, Roll = 0.0 })
        if not s.fov or abs(fov - s.fov) > 0.02 then
            s.fov = fov
            -- (the game's zoom is the angle top to bottom; the engine's is side to side)
            s.cam.CameraComponent:SetFieldOfView(2.0 * deg(atan(tan(rad(fov / 2.0)) * ASPECT)))
        end
    end)
    -- (the view kept on its camera till it ends: Start still opens STORROR's menu for a moment - shut at once, pause
    -- is blocked here (game.lua G.pause_info) - and the menu going hands the view back to him)
    pcall(function()
        local vt = pc:GetViewTarget()
        if s.cam and s.cam:IsValid() and not (vt and vt:IsValid() and vt:GetAddress() == s.cam:GetAddress()) then
            pc:SetViewTargetWithBlend(s.cam, 0.0, 0, 0.0, false)
        end
    end)

    -- the letter
    if s.ui then
        local L = data.letter
        local tau = f - L.at
        local alpha = 0.0
        if tau >= 0.0 and tau < L.fade then alpha = (tau + 1.0) / L.fade
        elseif tau >= L.fade and tau <= L.hold then alpha = 1.0
        elseif tau > L.hold and tau < L.hold + L.fade then alpha = 1.0 - (tau - L.hold) / L.fade end
        alpha = max(0.0, min(1.0, alpha)) * L.alpha
        if abs(alpha - s.ui.letter_a) > 0.004 then
            s.ui.letter_a = alpha
            pcall(function() s.ui.letter:SetRenderOpacity(alpha) end)
        end
    end

    -- Peach: there while the letter is, and then she fades as the camera draws back
    if s.peach then
        local P = data.peach
        local a = 1.0 - (f - P.fade_at) / P.fade_frames
        a = max(0.0, min(1.0, a))
        if a < 1.0 and not s.peach_mids then
            -- (solid things cannot fade: for this last second her parts are given see-through materials)
            s.peach_mids = {}
            pcall(function()
                local parent = lib.try_load(BLEND)
                local KML = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
                local by_tex = {}
                for i, part in ipairs(s.peach.data.parts) do
                    local comp = s.peach.comps[i]
                    for _, sec in ipairs(part.sections or {}) do
                        local key = tostring(sec.texture)
                        local mid = by_tex[key]
                        if not mid then
                            mid = KML:CreateDynamicMaterialInstance(world, parent, FName("SM64PeachFade" .. #s.peach_mids .. "_" .. floor(os.clock() * 1000)), 0)
                            if sec.texture then
                                local tex = lib.texture(world, lib.clamp_file(sec.texture))
                                if tex then mid:SetTextureParameterValue(FName("BaseColorTexture"), tex) end
                            end
                            by_tex[key] = mid
                            s.peach_mids[#s.peach_mids + 1] = mid
                        end
                        if comp then comp:SetMaterial(sec.id, mid) end
                    end
                end
            end)
        end
        if a ~= s.peach_a then
            s.peach_a = a
            if a <= 0.0 then
                pcall(function() s.peach.actor:SetActorHiddenInGame(true) end)
                lib.destroy(s.peach.actor)
                s.peach = nil
            else
                for _, mid in ipairs(s.peach_mids or {}) do
                    pcall(function() mid:SetVectorParameterValue(FName("BaseColorFactor"), { R = 1.0, G = 1.0, B = 1.0, A = a }) end)
                end
            end
        end
    end

    -- the sky behind the letter fades as the camera tilts down to the castle
    if s.sky then
        local a = 1.0
        if f >= data.fly_at then a = max(0.0, min(1.0, (s.cam_pitch - SKY_FADE_TO) / (SKY_FADE_FROM - SKY_FADE_TO))) end
        if a ~= s.sky_a then
            s.sky_a = a
            if a <= 0.0 then
                lib.destroy(s.sky)
                s.sky = nil
            else
                pcall(function() s.sky_mid:SetVectorParameterValue(FName("BaseColorFactor"), { R = 1.0, G = 1.0, B = 1.0, A = a }) end)
            end
        end
    end

    -- (the flight's wind, the pipe and his "Yahoo!" are in Mario 64's own recording of the scene, not in the remix that
    -- plays instead with REMIX MUSIC on: played here then - "wind sound on the intro I mean also no pipe and mario sound
    -- when hopping out the pipe", 2026-11-01)
    local own_sfx = false
    pcall(function() own_sfx = MUSIC and MUSIC.remix and not s.sfx_track and true or false end)
    local SFX = package.loaded["sfx"]
    if own_sfx and SFX and f >= data.lakitu_from and f < data.lakitu_until and SFX.hold then
        -- (loop_wind: loop_lakitu.wav is all but silent - its loudest -29 dB - "still no whooshing sound on lakito")
        pcall(SFX.hold, "loop_wind", 0.6)
    end
    -- (held sounds are started and faded by sfx.update_held, which the game's own tick - not running through the
    -- intro - calls: called here when it has not been this frame)
    if SFX and SFX.update_held and os.clock() - (SFX.held_at or 0.0) > 0.004 then pcall(SFX.update_held, dt) end

    -- the athlete stays out of sight until the pipe is up
    if not s.jumped then
        s.hide_t = (s.hide_t or 0.0) + dt
        if s.hide_t > 0.2 then
            s.hide_t = 0.0
            pcall(function()
                pawn:SetActorHiddenInGame(true)
                local l = pawn:K2_GetActorLocation()
                local cm = pawn.CharacterMovement
                if abs(l.Z - s.hole.Z) > 50.0 or abs(l.X - s.hole.X) > 50.0 or abs(l.Y - s.hole.Y) > 50.0 then
                    pawn:K2_TeleportTo(s.hole, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
                    cm:SetMovementMode(0, 0)
                    cm:StopMovementImmediately()
                elseif cm.MovementMode ~= 0 then
                    cm:SetMovementMode(0, 0)
                    cm:StopMovementImmediately()
                end
            end)
        end
    end

    -- Lakitu
    if s.lakitu then
        local on = f >= data.lakitu_from and f < data.lakitu_until
        if on ~= s.lakitu_on then
            s.lakitu_on = on
            pcall(function() s.lakitu.actor:SetActorHiddenInGame(not on) end)
            for _, p in ipairs(s.lakitu_cloud or {}) do pcall(function() p.actor:SetActorHiddenInGame(not on) end) end
        end
        if on then
            local Lk = data.lakitu
            local n = #Lk // 6
            local li = min(floor(f - data.lakitu_from), n - 1)
            local lj = min(li + 1, n - 1)
            local lt = (f - data.lakitu_from) - li
            local a6, b6 = li * 6, lj * 6
            local anim = s.lakitu.data.anims and s.lakitu.data.anims[1]
            lib.pose(s.lakitu, anim, f - data.lakitu_from)
            pcall(function()
                s.lakitu.actor:K2_TeleportTo(
                    { X = lerp(Lk, a6, b6, lt, 1) + OFFSET.X, Y = lerp(Lk, a6, b6, lt, 2) + OFFSET.Y, Z = lerp(Lk, a6, b6, lt, 3) + OFFSET.Z },
                    { Pitch = turn(Lk[a6 + 4], Lk[b6 + 4], lt), Yaw = turn(Lk[a6 + 5], Lk[b6 + 5], lt), Roll = turn(Lk[a6 + 6], Lk[b6 + 6], lt) })
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
        end
    end

    -- the pipe: up out of the grass, and down again once he has landed
    if s.pipe then
        local P = data.pipe
        if not s.pipe_on and f >= P.at and not s.pipe_gone then
            s.pipe_on = true
            pcall(function() s.pipe.actor:SetActorHiddenInGame(false) end)
        end
        if s.sink_from and f >= s.sink_from and not s.sink_heard then
            s.sink_heard = true
            if own_sfx and SFX then pcall(SFX.play, "pipe_enter") end
        end
        if s.pipe_on then
            local up = min(P.rise, (f - P.at) * P.rise / P.rise_frames)
            -- (only once its moment has come: sink_from is set 12 frames ahead, and before it this pushed the pipe UP
            -- by as much - "the pipe jumps up a bit for some reason during the scene", 2026-11-01)
            if s.sink_from and f > s.sink_from then up = up - (f - s.sink_from) * P.sink_per_frame end
            if up ~= s.pipe_up then
                s.pipe_up = up
                pcall(function()
                    s.pipe.actor:K2_TeleportTo({ X = P.pos[1] + OFFSET.X, Y = P.pos[2] + OFFSET.Y, Z = P.pos[3] + OFFSET.Z + up },
                        { Pitch = 0.0, Yaw = P.yaw, Roll = 0.0 })
                end)
            end
            if s.sink_from and up <= -10.0 then
                s.pipe_on, s.pipe_gone, s.gone_f = false, true, f
                pcall(function() s.pipe.actor:SetActorHiddenInGame(true) end)
            end
        end
    end

    -- the athlete comes out of the pipe
    if not s.half then
        s.half = 90.0
        pcall(function() s.half = pawn.CapsuleComponent.CapsuleHalfHeight end)
        if type(s.half) ~= "number" or s.half < 20.0 then s.half = 90.0 end
    end
    if not s.jumped and f >= data.jump_at then
        s.jumped, s.jump_t = true, s.t
        if own_sfx and SFX then pcall(SFX.play, "pipe_exit"); pcall(SFX.play, "mario_yahoo") end
        pcall(function()
            pawn:K2_TeleportTo({ X = data.start[1] + OFFSET.X, Y = data.start[2] + OFFSET.Y, Z = data.start[3] + OFFSET.Z + s.half + 20.0 },
                { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
            pc:SetControlRotation({ Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
            pawn:SetActorHiddenInGame(false)
            local cm = pawn.CharacterMovement
            cm.GravityScale = 1.0
            cm:SetMovementMode(3, 0)
        end)
        lib.bounce(pawn, JUMP_FORWARD, 0.0, JUMP_UP)
        if FLIP then spin_start(pawn, os.clock()) end
        if _G.SM64 then _G.SM64.no_fall_until = os.clock() + 4.0 end
    elseif s.jumped and not s.landed and s.t - s.jump_t > 0.4 then
        local falling = true
        pcall(function() falling = pawn.CharacterMovement:IsFalling() end)
        if not falling then
            s.landed = true
            s.sink_from = f + 12.0                  -- (a moment to land in, as Mario has)
        end
    end
    if _G.HEALTH and _G.HEALTH.hud_off and f >= data.hud_at then _G.HEALTH.hud_off = false end

    -- the message at the pipe: a page at a time, and then the game is the player's
    if not MESSAGE then
        if (s.pipe_gone and f >= s.gone_f + AFTER_PIPE) or f >= last then
            s.blend = RETURN_BLEND
            I.stop()
        end
    elseif s.ui and f >= data.dialog_at and #s.ui.pages > 0 then
        if not s.talking then
            s.talking = true
            s.ui.page = 1
            pcall(function() s.ui.pages[1]:SetRenderOpacity(1.0) end)
            pad.reset()
        elseif pad.pressed("ok") then
            pcall(function() s.ui.pages[s.ui.page]:SetRenderOpacity(0.0) end)
            s.ui.page = s.ui.page + 1
            if s.ui.pages[s.ui.page] then
                pcall(function() s.ui.pages[s.ui.page]:SetRenderOpacity(1.0) end)
            else
                s.blend = RETURN_BLEND
                I.stop()
                return
            end
        end
    elseif f >= last and not s.talking then
        s.blend = RETURN_BLEND
        I.stop()
    end
end

function I.state() return st end       -- (tests)

-- Mario's voice kept quiet while the intro holds the athlete out of sight at the pipe - its holding him there read as
-- jumps, and his jump voice was heard over the scene: "can hear mario jumping in bnackround", 2026-11-01 (sfx.lua)
function I.quiet()
    return I.active and st ~= nil and not st.jumped
end

return I
