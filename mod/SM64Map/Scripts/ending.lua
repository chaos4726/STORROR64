-- SM64Map: Mario 64's ending, after the Grand Star.
--
-- As the game plays it (mario_actions_cutscene.c, level_update.c, levels/ending): the Grand Star taken, the
-- victory tune plays while the camera circles him, he rises away and the screen goes white; then the credits,
-- twenty shots of the courses, each with Mario standing where the game puts him and the camera flying its own
-- path; partway into each shot the picture shrinks to a corner and the names are lettered beside it; then the
-- cake, "The End", and Mario's thanks. The shots, paths, names and cake come from the player's own copy of the
-- game (endingx.py -> data/ending.lua, textures/ending_*.png); the tunes and voice are rendered from it by
-- sm64audio. Between the white and the credits, Peach's scene in front of the castle (end_peach_cutscene_*): the
-- great star over the door, Peach freed from the stained glass, floating down, and her words to him, with her
-- voice and the game's lines; the athlete stands in for Mario (who in the game also takes his cap off, gets a
-- kiss and does a little dance: the athlete just stands and listens).
--
-- Laid out for a 16:9 screen, as the opening is: the game's 4:3 picture stands in the middle, its full height.
local lib = require("lib")
local pad = require("pad")
local log = lib.log
local okM, MUSIC = pcall(require, "music")
if not okM then MUSIC = nil end

local E = { active = false }

local OFFSET = lib.OFFSET
local sin, cos, tan, atan, sqrt, floor, abs, rad, deg = math.sin, math.cos, math.tan, math.atan, math.sqrt, math.floor, math.abs, math.rad, math.deg
local max, min = math.max, math.min

local ASPECT = 16.0 / 9.0
local PX = 1080.0 / 240.0               -- the game's pixels to the screen's (its 240 lines are the screen's height)
local FADE_FRAMES = 20                  -- (WARP_OP_CREDITS_NEXT: 20 frames to black, and 20 back)
local CAKE_VOICE = 6.0                  -- (levels/ending/script.c: 60 + 120 frames, the voice after the cake is up)

local st = nil
-- (his Wing Cap, defined below with the castle grounds' part; named here, for the Grand Star's start uses it first - it
-- was called there before it was made, and the ending never started: "it didnt start the peach outro?", 2026-11-04)
local wing_cap
local function valid(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end
local function G() return package.loaded["game"] end
local function sfx(name, v) local S = package.loaded["sfx"]; if S then pcall(S.play, name, v) end end

-- ------------------------------------------------------------ what is on the screen
local serial = 0
-- (the skip prompt's size on a 1920x1080 screen: its 102 x 13 game pixels at three quarters of PX)
local SKIP_W, SKIP_H = 102.0 * PX * 0.75, 13.0 * PX * 0.75
local SKIP_HOLD = 1.0               -- s of Start held that skip the rest
-- (her lines changed for the story: ending_sub_story_<n>.png in place of ending_sub_<n>.png - exporter/finalx.py)
local STORY_SUBS = { [1] = "ending_sub_story_1", [4] = "ending_sub_story_4", [7] = "ending_sub_story_7" }
local function build_ui(pc, world, shots)
    local function cls(p) return StaticFindObject(p) end
    serial = serial + 1
    local n = "SM64End" .. serial
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName(n))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName(n .. "Tree"))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName(n .. "Canvas"))
    tree.RootWidget = canvas
    local count = 0
    -- (every piece is placed about the middle of the screen, in a 1920x1080 screen's units)
    local function piece(file, wd, ht, x, y, colour)
        count = count + 1
        local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName(n .. "Img" .. count))
        if file then
            local tex = lib.texture(world, file)
            if tex then img:SetBrushFromTexture(tex, false) end
        end
        if colour then img:SetColorAndOpacity(colour) end
        local slot = canvas:AddChildToCanvas(img)
        slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
        slot:SetAlignment({ X = 0.0, Y = 0.0 })
        slot:SetSize({ X = wd, Y = ht })
        slot:SetPosition({ X = x, Y = y })
        img:SetRenderOpacity(0.0)
        return img, slot
    end
    local black = { R = 0.0, G = 0.0, B = 0.0, A = 1.0 }
    local ui = { widget = w, bars = {}, pages = {} }
    -- the frame round the shrunken picture: four black bars (well past the screen's edges)
    for i = 1, 4 do
        local img, slot = piece(nil, 10, 10, 0, 0, black)
        ui.bars[i] = { img = img, slot = slot }
    end
    for i = 1, #shots do ui.pages[i] = piece("ending_credits_" .. i, 1440.0, 1080.0, -720.0, -540.0) end
    ui.subs = {}
    for i = 0, 8 do ui.subs[i] = piece(STORY_SUBS[i] or ("ending_sub_" .. i), 1440.0, 1080.0, -720.0, -540.0) end
    -- the cake, its black surround, and the screen-wide black and white for the fades
    ui.cake_back = piece(nil, 4000.0, 3000.0, -2000.0, -1500.0, black)
    ui.cake = piece("ending_cake", 1440.0, 1080.0, -720.0, -540.0)
    ui.black = piece(nil, 4000.0, 3000.0, -2000.0, -1500.0, black)
    ui.white = piece(nil, 4000.0, 3000.0, -2000.0, -1500.0, { R = 1.0, G = 1.0, B = 1.0, A = 1.0 })
    -- (and over it all, at the bottom right, "HOLD START TO SKIP" in the dialog font - textures/ending_skip.png, 102 x 13
    -- of the game's pixels - shown while it can be: E.tick)
    ui.skip = piece("ending_skip", SKIP_W, SKIP_H, 960.0 - SKIP_W - 48.0, 540.0 - SKIP_H - 40.0)
    w:AddToViewport(70)
    return ui
end

local function show(img, a) if img then pcall(function() img:SetRenderOpacity(a) end) end end

-- the picture's window: the game's whole 320x240 at a = 0, shrunk to 60% and moved to its corner at a = 40
-- (act_credits_cutscene: actionState 0..40). Returns the window (the game's pixels): centre, half size.
local function window(shot, a)
    local hw, hh = 160.0 - 1.6 * a, 120.0 - 1.2 * a
    local cx = 160.0 + (shot.right and 1.0 or -1.0) * 0.896 * a
    local cy = 120.0 + (shot.down and 1.0 or -1.0) * 0.792 * a
    return cx, cy, hw, hh
end

local function frame_bars(ui, cx, cy, hw, hh)
    -- (the game's pixels to the screen's, about its middle)
    local x0, x1 = (cx - hw - 160.0) * PX, (cx + hw - 160.0) * PX
    local y0, y1 = (cy - hh - 120.0) * PX, (cy + hh - 120.0) * PX
    local far = 3000.0
    local r = {
        { -far, -far, 2 * far, far + y0 },            -- above
        { -far, y1, 2 * far, far },                   -- below
        { -far, y0, far + x0, y1 - y0 },              -- left
        { x1, y0, far, y1 - y0 },                     -- right
    }
    for i, b in ipairs(ui.bars) do
        pcall(function()
            b.slot:SetPosition({ X = r[i][1], Y = r[i][2] })
            b.slot:SetSize({ X = max(0.0, r[i][3]), Y = max(0.0, r[i][4]) })
            b.img:SetRenderOpacity(1.0)
        end)
    end
end

-- ------------------------------------------------------------ the athlete held for the scenes
local function hold_athlete(at, yaw, hidden)
    local pawn, pc = lib.pawn(), lib.controller()
    if not pawn then return end
    pcall(function() pawn:DisableInput(pc) end)
    pcall(function() pawn:SetActorHiddenInGame(hidden == true) end)
    pcall(function()
        pawn:K2_TeleportTo({ X = at[1] + OFFSET.X, Y = at[2] + OFFSET.Y, Z = at[3] + OFFSET.Z + 92.0 }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 })
        local cm = pawn.CharacterMovement
        cm:SetMovementMode(0, 0)
        cm:StopMovementImmediately()
    end)
end

-- on his feet where a scene puts him: dropped onto the ground there, the game's physics and his idle running, and
-- the player's to walk about (pinning him, as hold_athlete does, would freeze him in mid-air)
local function stand_athlete(at, yaw)
    local pawn, pc = lib.pawn(), lib.controller()
    if not pawn then return end
    -- (the player's: STORROR's own controls, all of them, 2026-10-14 "Bring back full controls in cutscenes")
    pcall(function() pawn:EnableInput(pc) end)
    pcall(function() pawn:SetActorHiddenInGame(false) end)
    pcall(function()
        local cm = pawn.CharacterMovement
        cm.GravityScale = 1.0
        pawn:K2_TeleportTo({ X = at[1] + OFFSET.X, Y = at[2] + OFFSET.Y, Z = at[3] + OFFSET.Z + 100.0 }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 })
        cm:StopMovementImmediately()
        cm:SetMovementMode(3, 0)            -- (falling: he lands, and stands)
    end)
    -- (STORROR's fall begun again here, a metre up: after Final Bowser's outro - in the air from his broken floor all
    -- through it - it took his landing in front of the castle for a great drop and threw him down flailing, 2026-11-04)
    local g = G()
    if g and g.parkour_reset then pcall(g.parkour_reset, pawn) end
end

-- his animation runs every frame, seen or not (STORROR skips it while he is off the screen; three crashes in the
-- ending came in it when it ran again after a scene had gone, 2026-10-14)
local function keep_animating(s)
    if s.anim_kept then return end
    s.anim_kept = true
    local pawn = lib.pawn()
    if not pawn then return end
    pcall(function()
        local cls = StaticFindObject("/Script/Engine.SkeletalMeshComponent")
        local n, was = 0, {}
        for _, c in ipairs(pawn:K2_GetComponentsByClass(cls)) do
            local o = c:get()
            pcall(function()
                was[#was + 1] = tostring(o.VisibilityBasedAnimTickOption)
                o.VisibilityBasedAnimTickOption = 0          -- (AlwaysTickPoseAndRefreshBones)
                o.bEnableUpdateRateOptimizations = false
                n = n + 1
            end)
        end
        log("ending: his animation runs always (%d meshes, were %s)", n, table.concat(was, ","))
    end)
end

-- nothing in the scenes may hurt him, drown him or count him fallen
local function keep_safe()
    local HP = _G.HEALTH
    if HP then
        HP.health, HP.hurt, HP.dead_t, HP.grace = HP.MAX, 0, nil, 9999.0
        HP.hud_off = true
    end
    local g = G()
    if g then
        g.no_fall_until = os.clock() + 5.0
        g.air = false
        g.warp_cool = max(g.warp_cool or 0.0, 0.5)      -- (no warp, painting or death floor takes him out of a scene)
    end
end

-- His stick the way the ending's camera looks, every frame of Peach's scene and the credits, whatever else turned it -
-- the player's own camera stick, STORROR's camera coming round behind him: put right only when the shot itself turned,
-- in a held shot it stayed turned and pushed him back toward the camera - "the joystick is supposed to line up with the
-- camera but somehow it gets inverted during", 2026-11-02
local function align_controls(s)
    local yaw = s.cam_yaw
    if not yaw then return end
    pcall(function()
        local pc = lib.controller()
        local r = pc:GetControlRotation()
        if abs((r.Yaw - yaw + 540.0) % 360.0 - 180.0) > 1.0 then
            pc:SetControlRotation({ Pitch = r.Pitch, Yaw = yaw, Roll = 0.0 })
        end
    end)
end
local function set_camera(s, px, py, pz, fx, fy, fz, vfov, ox, oy)
    local dx, dy, dz = fx - px, fy - py, fz - pz
    local yaw, pitch = deg(atan(dy, dx)), deg(atan(dz, sqrt(dx * dx + dy * dy)))
    s.cam_yaw = yaw
    if not s.ctrl_yaw or abs((yaw - s.ctrl_yaw + 540.0) % 360.0 - 180.0) > 3.0 then
        s.ctrl_yaw = yaw
        pcall(function()
            local pc = lib.controller()
            local r = pc:GetControlRotation()
            pc:SetControlRotation({ Pitch = r.Pitch, Yaw = yaw, Roll = 0.0 })
        end)
    end
    pcall(function()
        s.cam:K2_TeleportTo({ X = px + OFFSET.X, Y = py + OFFSET.Y, Z = pz + OFFSET.Z }, { Pitch = pitch, Yaw = yaw, Roll = 0.0 })
        local c = s.cam.CameraComponent
        -- (the game's zoom is the angle top to bottom; the engine's is side to side)
        c:SetFieldOfView(2.0 * deg(atan(tan(rad(vfov / 2.0)) * ASPECT)))
        c.OffCenterProjectionOffset = { X = ox or 0.0, Y = oy or 0.0 }
    end)
end

-- ------------------------------------------------------------ walking him about in a cutscene
-- The stick (or WASD / the arrows) walks him, forward being into the picture whichever way the scene's camera looks.
-- STORROR's own controls stay off (its moves work the game's camera, and with the scene's camera showing they brought
-- the game down twice), and with them off it holds his walking speed at nothing: so he walks by a walk cycle of its
-- own (DrewWalkStraightCycle, whose steps carry him), turned the way he is pushed, on its FullBody slot.
local WALK_ANIM, WALK_RATE = "DrewWalkStraightCycle", 2.2
local walk_seq = nil
local function walk_tick(s, dt)
    local pc, pawn = lib.controller(), lib.pawn()
    if not (pc and pawn and s.cam_yaw) then return end
    local function key(n)
        local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(n) }) end)
        return ok and v == true
    end
    local function ax(n)
        local ok, v = pcall(function() return pc:GetInputAnalogKeyState({ KeyName = FName(n) }) end)
        if ok and type(v) == "number" and abs(v) > 0.2 then return v end
        return 0.0
    end
    local x, y = ax("Gamepad_LeftX"), ax("Gamepad_LeftY")
    if key("W") or key("Up") then y = y + 1.0 end
    if key("S") or key("Down") then y = y - 1.0 end
    if key("D") or key("Right") then x = x + 1.0 end
    if key("A") or key("Left") then x = x - 1.0 end
    local moving = (x * x + y * y) > 0.04
    if moving then
        local a = rad(s.cam_yaw)
        local dx, dy = cos(a) * y - sin(a) * x, sin(a) * y + cos(a) * x
        local want = deg(atan(dy, dx))
        local cur = 0.0
        pcall(function() cur = pawn:K2_GetActorRotation().Yaw end)
        local d = (want - cur + 540.0) % 360.0 - 180.0
        local step = 600.0 * (dt or 0.016)
        if d > step then d = step elseif d < -step then d = -step end
        pcall(function() pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = cur + d, Roll = 0.0 }, false) end)
    end
    if moving and not s.walking then
        s.walking = true
        pcall(function()
            if not (walk_seq and walk_seq:IsValid()) then
                walk_seq = nil
                for _, o in ipairs(FindAllOf("AnimSequence") or {}) do
                    local ok, n = pcall(function() return o:GetFName():ToString() end)
                    if ok and n == WALK_ANIM then walk_seq = o; break end
                end
            end
            if walk_seq then
                pawn.Mesh:GetAnimInstance():PlaySlotAnimationAsDynamicMontage(walk_seq, FName("FullBody"), 0.2, 0.2, WALK_RATE, 1000, -1.0, 0.0)
            end
        end)
    elseif not moving and s.walking then
        s.walking = false
        pcall(function() pawn.Mesh:GetAnimInstance():StopSlotAnimation(0.25, FName("FullBody")) end)
    end
end
local function walk_stop(s)
    if s and s.walking then
        s.walking = false
        pcall(function() lib.pawn().Mesh:GetAnimInstance():StopSlotAnimation(0.2, FName("FullBody")) end)
    end
end

-- ------------------------------------------------------------ starting
-- Called when the Grand Star has been taken. Returns true if the ending is on.
function E.start()
    if st then return true end
    local world, pc, pawn = lib.world(), lib.controller(), lib.pawn()
    if not (world and pc and pawn) then return false end
    local data = lib.load_data("data.ending")
    if not (data and data.shots and #data.shots > 0) then log("ending: no data"); return false end
    local s = { data = data, world = world:GetAddress(), phase = "outro", t = 0.0, of = 0.0 }
    local cam = lib.camera(world, "ending", OFFSET, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
    if not valid(cam) then log("ending: no camera"); return false end
    s.cam = cam
    pcall(function() cam.CameraComponent.bConstrainAspectRatio = false end)
    local okw, ui = pcall(build_ui, pc, world, data.shots)
    if not okw then log("ending: no screen (%s)", tostring(ui)); return false end
    s.ui = ui
    keep_animating(s)
    -- where he stands: in the middle of the arena, as Mario 64 sets him down to hold the star up
    local loc = pawn:K2_GetActorLocation()
    s.centre = { loc.X - OFFSET.X, loc.Y - OFFSET.Y, loc.Z - OFFSET.Z - 92.0 }
    local g = G()
    -- (Final Bowser's mega star, taken in the wind over his broken last floor: the fight's hold on him - bowser_fight
    -- M.catch - let go, and the ending's own instead, where he took it (no floor to set him down on), till he flies off.
    -- Held by both, they fought over him all through the outro, and the climb watchdog respawned him in it - "player
    -- getting stuck during outro", 2026-11-04)
    local BF = package.loaded["bowser_fight"]
    local final = BF and BF.mega and BF.mega.st and BF.mega.st.taken and true or false
    if BF and BF.catch and BF.catch.hover then BF.catch = nil; s.hold_air = true end
    if g and g.bowser and not s.hold_air then s.centre[1], s.centre[2] = 0.0, 0.0 end
    stand_athlete(s.centre, 0.0)
    if s.hold_air then pcall(function() pawn:DisableInput(pc) end) end
    pcall(function() pawn:DisableInput(pc) end)            -- (the outro is the game's: he is the player's again after it)
    keep_safe()
    local star = g and g.actor_data and g.actor_data("star")
    if star then
        -- (the Grand Star he holds up: twice a star's size, as it lay in the arena - grand_star.inc.c)
        s.held_star = lib.make_instance(world, star, { X = loc.X, Y = loc.Y, Z = loc.Z + 125.0 }, 0.0, 2.0)
        if s.held_star then s.held_star.moves = true end
        -- (Bowser's mega star, rainbow, as he took it in the final fight - bowser_fight M.mega_star: its faces but its
        -- eyes - "its not a rainbow star", 2026-11-04)
        if s.held_star and s.held_star.data then
            local mid = lib.get_mid(world, "opaque", "rainbow_star", 0.94)
            for i, part in ipairs(s.held_star.data.parts) do
                local comp = s.held_star.comps[i]
                for _, sec in ipairs(part.sections or {}) do
                    if mid and comp and not (sec.texture or ""):find("eye") then pcall(function() comp:SetMaterial(sec.id, mid) end) end
                end
            end
        end
    end
    pcall(function()
        local cm = pc.PlayerCameraManager:GetCameraLocation()
        s.cam_at = { cm.X - OFFSET.X, cm.Y - OFFSET.Y, cm.Z - OFFSET.Z }
    end)
    if _G.MENU and _G.MENU.hide_game_ui then pcall(_G.MENU.hide_game_ui) end
    pcall(function() pc:SetViewTargetWithBlend(cam, 0.0, 0, 0.0, false) end)
    wing_cap(true)
    if MUSIC then pcall(MUSIC.play, "event_victory", true) end
    if g then g.music_override, g.cutscene = "event_victory", true end
    pad.reset()
    -- (the run's time at the Grand Star, shown through the ending under the meter, its clock still going at the top -
    -- "after picking up the star for bowser 3 dont stop the timer but show on screen the time it took to beat bowser
    -- 3", 2026-11-02: health.lua M.grand_time)
    -- (Final Bowser's: the clock stopped as he takes it - "after final bowser the timer can stop", 2026-11-04 - and his
    -- clear time shown from now on, not from his beating: "final bowser clear time should only show after player picks
    -- up rainbow star")
    local HP, MN = _G.HEALTH, _G.MENU
    if final and MN and MN.stop_timer then pcall(MN.stop_timer) end
    if final and MN and MN.set_rainbow_star then pcall(MN.set_rainbow_star) end
    -- (the secrets Final Bowser opens - for every file, secrets.lua - each told once back on the castle grounds: E.tick)
    if final then
        local okS, SE = pcall(require, "secrets")
        if okS and SE and SE.final_beaten then
            local human = MN and MN.human_on and MN.human_on() or false
            local iron = MN and MN.ironman_on and MN.ironman_on() or false
            local okN, new = pcall(SE.final_beaten, human, iron)
            -- (told once THE END is left or the credits skipped - E.stop - not before: "the secret unlock message should
            -- only show once you exit THE END screen or skipping credits", 2026-11-04)
            if okN and new and #new > 0 then E.secrets_pending = { list = new, human = human, iron = iron } end
        end
    end
    if HP and MN and MN.run_time then
        HP.grand_time = MN.run_time()
        HP.final_clear = final or nil
        log("ending: the run's time at the Grand Star, %.2f s%s", HP.grand_time, final and " (Final Bowser - the clock stopped)" or "")
    end
    st = s
    E.active = true
    log("ending: started")
    return true
end

-- ------------------------------------------------------------ the credits shots
-- Him through the credits and the waving: held where he stands (on the floor there), STORROR's movement and physics off
-- and an animation of its own on him (its idle; the waving's wave) - Mario 64's credits hold Mario too. Let fall and
-- walk, he went down in STORROR's own flail, and got up at once he was left in its "climbing into the sky" state: "mario
-- getting launched during waving scene, was getting launched in dire dire docks during cutscene", 2026-11-02. (A shot's
-- new scene ends any ragdoll he was in.)
local IDLE_ANIM = "Idle_0_DavidIdleSPPLocomotionWalk-009"
local function slot_anim(name, rate)
    local pawn = lib.pawn()
    if not pawn then return end
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        if not name then ai:StopSlotAnimation(0.2, FName("FullBody")); return end
        for _, o in ipairs(FindAllOf("AnimSequence") or {}) do
            local ok, n = pcall(function() return o:GetFName():ToString() end)
            if ok and n == name then
                ai:PlaySlotAnimationAsDynamicMontage(o, FName("FullBody"), 0.2, 0.2, rate or 1.0, 1000, -1.0, 0.0)
                break
            end
        end
    end)
end
local function held_at(at, yaw, anim)
    local g = G()
    local z = at[3]
    local fz = g and g.floor_z and g.floor_z(at[1], at[2], at[3] + 200.0)
    if fz and fz > at[3] - 400.0 then z = fz end
    hold_athlete({ at[1], at[2], z }, yaw, false)
    pcall(function() lib.pawn().CharacterMovement:StopMovementImmediately() end)
    slot_anim(anim or IDLE_ANIM)
    return { at[1], at[2], z }
end

-- The credits' shots his to play in: on his feet on the floor under the shot's place, the player's controls - "player
-- still stuck in credits" / "Let me move", 2026-11-04 - and put back there only if he falls far, is thrown up or flung,
-- or runs off out of the shot (E.tick, CREDITS_FREE). Where there is no floor under it within 30 m, held as before.
local CREDITS_FREE = { below = 800.0, above = 1500.0, away = 4000.0, up = 3000.0, fling = 4000.0 }
local function free_at(at, yaw)
    local g = G()
    local fz = g and g.floor_z and g.floor_z(at[1], at[2], at[3] + 200.0)
    if not (fz and fz > at[3] - 3000.0) then return nil end
    local z = fz
    slot_anim(nil)
    stand_athlete({ at[1], at[2], z }, yaw)
    return { at[1], at[2], z }
end

local function load_shot(s, i)
    walk_stop(s)
    local shot = s.data.shots[i]
    local g = G()
    if not g then return false end
    g.act_override = shot.act
    local ok, r = pcall(g.load_scene, shot.scene, true)
    if not (ok and r ~= false) then log("ending: shot %d (%s) did not load: %s", i, shot.scene, tostring(r)); return false end
    local free = free_at(shot.at, shot.yaw)
    if free then
        s.held = { at = free, yaw = shot.yaw, t = 0.0, free = true }
    else
        s.held = { at = held_at(shot.at, shot.yaw), yaw = shot.yaw, t = 0.0 }
    end
    keep_safe()
    s.shot, s.f, s.fading_in = i, 0.0, true
    log("ending: shot %d, %s (act %d)", i, shot.scene, shot.act)
    return true
end

local function credits_frame(s, dt)
    local data, shot = s.data, s.data.shots[s.shot]
    s.f = s.f + dt * data.fps
    local f = min(s.f, data.warp)
    local i = min(floor(f), data.warp)
    local j = min(i + 1, data.warp)
    local t = f - i
    local C = shot.cam
    local function L(k) return C[i * 6 + k] + (C[j * 6 + k] - C[i * 6 + k]) * t end
    -- the window: shrinking from frame SHOW, two steps a frame, to 40
    local a = min(40.0, max(0.0, (f - data.show) * 2.0))
    local cx, cy, hw, hh = window(shot, a)
    frame_bars(s.ui, cx, cy, hw, hh)
    -- the game's view squeezed into the window: here, a wider view whose window part is the game's, its centre
    -- moved to the window's
    local fh = hh / 120.0
    local vfov = 2.0 * deg(atan(tan(rad(data.fov / 2.0)) / fh))
    local ox = (cx - 160.0) * PX / 960.0
    local oy = (cy - 120.0) * PX / 540.0
    set_camera(s, L(1), L(2), L(3), L(4), L(5), L(6), vfov, ox, -oy)
    -- the names, from frame PROGRESS
    for k, page in ipairs(s.ui.pages) do
        if k == s.shot then show(page, min(1.0, max(0.0, (f - data.progress) / 8.0))) else show(page, 0.0) end
    end
    -- fading in after the load, out before the next
    local black = 0.0
    if s.f < FADE_FRAMES then black = 1.0 - s.f / FADE_FRAMES end
    if s.f > data.warp then black = min(1.0, (s.f - data.warp) / FADE_FRAMES) end
    show(s.ui.black, black)
    return s.f >= data.warp + FADE_FRAMES
end

-- ------------------------------------------------------------ the Grand Star outro (act_jumbo_star_cutscene)
-- In frames from the moment he has it: he stands with it held up (Mario 64: lands, raises it and spins round, 100
-- frames); then the take-off (MARIO_ANIM_FINAL_BOWSER_WING_CAP_TAKE_OFF): three jumps, each higher, "Yah!",
-- "Hoo-hoo!", "Yahoo!", moving on 32 a frame; on the third he does not come down but glides away with the star,
-- round and up over the arena on the game's own path (sJumboStarKeyframes) until frame 500 of the flight; the
-- screen goes white for Peach's scene. The camera is cutscene_grand_star's: round to his front while he holds it
-- up, behind and beside him in the air, then he flies on out of the picture.
local OUT = { takeoff = 100, fly = 194, white = 650, done = 694 }
-- the take-off's height (its root, in Mario's animation's units: a quarter of Mario 64's), frame by frame
local TAKEOFF_Y = {
    117, 117, 118, 310, 476, 618, 738, 838, 919, 983, 1033, 1070, 1095, 1112, 1122, 1126, 1127, 1124, 1114, 1095,
    1065, 1025, 971, 903, 820, 720, 601, 462, 303, 121, 119, 119, 121, 306, 473, 623, 755, 872, 973, 1061,
    1136, 1198, 1250, 1291, 1323, 1347, 1364, 1374, 1378, 1378, 1354, 1301, 1224, 1126, 1012, 886, 752, 615, 477, 345,
    221, 117, 117, 117, 117, 117, 301, 471, 625, 766, 894, 1009, 1112, 1203, 1283, 1352, 1412, 1463, 1505, 1538,
    1565, 1584, 1597, 1604, 1606, 1603, 1597, 1587, 1574, 1558, 1541, 1523, 1505, 1486,
}
local SHOUTS = { [3] = "mario_yah", [33] = "mario_wah", [66] = "mario_yahoo" }
-- (s, x, y, z): how fast each key is passed (1000ths a frame) and where it is, Mario 64's units
local JUMBO_KEYS = {
    { 20, 0, 678, -2916 }, { 30, 0, 680, -3500 }, { 40, 1000, 700, -4000 }, { 50, 2500, 750, -3500 },
    { 50, 3500, 800, -2000 }, { 50, 4000, 850, 0 }, { 50, 3500, 900, 2000 }, { 50, 2000, 950, 3500 },
    { 50, 0, 1000, 4000 }, { 50, -2000, 1050, 3500 }, { 50, -3500, 1100, 2000 }, { 50, -4000, 1150, 0 },
    { 50, -3500, 1200, -2000 }, { 50, -2000, 1250, -3500 }, { 50, 0, 1300, -4000 }, { 50, 2000, 1350, -3500 },
    { 50, 3500, 1400, -2000 }, { 50, 4000, 1450, 0 }, { 50, 3500, 1500, 2000 }, { 50, 2000, 1600, 3500 },
    { 50, 0, 1700, 4000 }, { 50, -2000, 1800, 3500 }, { 50, -3500, 1900, 2000 }, { 30, -4000, 2000, 0 },
    { 0, -3500, 2100, -2000 }, { 0, -2000, 2200, -3500 }, { 0, 0, 2300, -4000 },
}

-- anim_spline_poll, frame by frame, until it ends (or 500 frames): Mario 64's units
local function jumbo_path()
    local out, k, frac, state = {}, 1, 0.0, 1
    for _ = 1, 520 do
        local t = frac
        local ti = 1.0 - t
        local ti2, ti3, t2, t3 = ti * ti, ti * ti * ti, t * t, t * t * t
        local w
        if state == 1 then w = { ti3, t3 * 1.75 - t2 * 4.5 + t * 3.0, -t3 * (11 / 12) + t2 * 1.5, t3 / 6 }
        elseif state == 2 then w = { ti3 * 0.25, t3 * (7 / 12) - t2 * 1.25 + t * 0.25 + 7 / 12, -t3 * 0.5 + t2 * 0.5 + t * 0.5 + 1 / 6, t3 / 6 }
        elseif state == 3 then w = { ti3 / 6, t3 * 0.5 - t2 + 4 / 6, -t3 * 0.5 + t2 * 0.5 + t * 0.5 + 1 / 6, t3 / 6 }
        elseif state == 4 then w = { ti3 / 6, -ti3 * 0.5 + ti2 * 0.5 + ti * 0.5 + 1 / 6, ti3 * (7 / 12) - ti2 * 1.25 + ti * 0.25 + 7 / 12, t3 * 0.25 }
        else w = { ti3 / 6, -ti3 * (11 / 12) + ti2 * 1.5, ti3 * 1.75 - ti2 * 4.5 + ti * 3.0, t3 } end
        local x, y, z = 0.0, 0.0, 0.0
        for i = 1, 4 do
            local key = JUMBO_KEYS[k + i - 1] or JUMBO_KEYS[#JUMBO_KEYS]
            x, y, z = x + w[i] * key[2], y + w[i] * key[3], z + w[i] * key[4]
        end
        out[#out + 1] = { x, y, z }
        frac = frac + JUMBO_KEYS[k][1] / 1000.0
        if frac >= 1.0 then
            k, frac = k + 1, frac - 1.0
            if state == 5 then break
            elseif state == 3 then
                if (JUMBO_KEYS[k + 2] or { 0 })[1] == 0 then state = 4 end
            else state = state + 1 end
        end
    end
    return out
end

-- where he is at outro frame F (scene cm, his feet), and the way he is going (scene degrees)
local function outro_place(s, F)
    local c = s.centre
    if F < OUT.takeoff then return c[1], c[2], c[3], 0.0 end
    if F < OUT.fly then
        local f = F - OUT.takeoff
        local i = min(#TAKEOFF_Y - 1, floor(f))
        local t = f - i
        local y0 = TAKEOFF_Y[i + 1] + ((TAKEOFF_Y[i + 2] or TAKEOFF_Y[i + 1]) - TAKEOFF_Y[i + 1]) * t
        local on = 32.0 * max(0.0, f - 2.0) * 0.75
        return c[1] + on, c[2], c[3] + (y0 - TAKEOFF_Y[1]) * 0.25 * 0.75, 0.0
    end
    local path = s.jumbo_path
    local f = min(#path - 1.001, F - OUT.fly)
    local i = floor(f)
    local t = f - i
    local a, b = path[i + 1], path[min(#path, i + 2)]
    local x, y, z = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
    local sx, sy, sz = -z * 0.75 + c[1], x * 0.75 + c[2], y * 0.75 + (c[3] - 307.0 * 0.75)
    local dx, dy = -(b[3] - a[3]), b[1] - a[1]
    return sx, sy, sz, deg(atan(dy, dx))
end

-- a tune dying away over `sec` seconds, then stopping (its loudness set back for the next one)
local function fade_music(s, sec)
    if MUSIC and MUSIC.set_volume and not s.mfade then s.mfade = { t = 0.0, len = sec, base = MUSIC.volume } end
end
local function fade_music_tick(s, dt)
    local f = s.mfade
    if not f then return end
    f.t = f.t + dt
    local k = max(0.0, 1.0 - f.t / f.len)
    pcall(MUSIC.set_volume, f.base * k)
    if k <= 0.0 then
        pcall(MUSIC.play, nil)
        pcall(MUSIC.set_volume, f.base)
        s.mfade = nil
    end
end
E.fade_music_tick = fade_music_tick
-- (a fade still going as the next part's tune starts - the outro's into Peach's scene, hers into the credits - done
-- with there and then: let finish, its end stopped the new tune a moment after it began, and the credits' only came
-- back with the second shot's scene - "music is still delayed to start during outro ... credits", 2026-11-04)
local function fade_cancel(s)
    local f = s and s.mfade
    if not f then return end
    s.mfade = nil
    if MUSIC and MUSIC.set_volume then pcall(MUSIC.set_volume, f.base) end
end

-- laid out to fly: face down, head first (his mesh turned about its length), arms out (STORROR's falling animation)
local FLY_ANIM = "FallingInAir_68_Drew_131024_Falling-005_frames_338-1717"
local function fly_pose(on)
    local pawn = lib.pawn()
    if not pawn then return end
    pcall(function()
        local m = pawn.Mesh
        if on then
            m.RelativeRotation = { Pitch = 0.0, Yaw = -90.0, Roll = 80.0 }
            m.RelativeLocation = { X = 0.0, Y = 0.0, Z = -20.0 }
        else
            m.RelativeRotation = { Pitch = 0.0, Yaw = -90.0, Roll = 0.0 }
            m.RelativeLocation = { X = 0.0, Y = 0.0, Z = -86.0 }
        end
    end)
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        if on then
            for _, o in ipairs(FindAllOf("AnimSequence") or {}) do
                local ok, n = pcall(function() return o:GetFName():ToString() end)
                if ok and n == FLY_ANIM then
                    ai:PlaySlotAnimationAsDynamicMontage(o, FName("FullBody"), 0.3, 0.3, 1.0, 1000, -1.0, 0.0)
                    break
                end
            end
        else
            ai:StopSlotAnimation(0.25, FName("FullBody"))
        end
    end)
end

-- ------------------------------------------------------------ turning him about his own length (the glide's rolls)
-- (rotations as the engine composes them: FRotator <-> quaternion)
local function rot_quat(p, y, r)
    local sp, cp = sin(rad(p) / 2), cos(rad(p) / 2)
    local sy, cy = sin(rad(y) / 2), cos(rad(y) / 2)
    local sr, cr = sin(rad(r) / 2), cos(rad(r) / 2)
    return { cr * sp * sy - sr * cp * cy, -cr * sp * cy - sr * cp * sy, cr * cp * sy - sr * sp * cy, cr * cp * cy + sr * sp * sy }
end
local function quat_mul(a, b)
    return { a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2], a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
             a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4], a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3] }
end
local function quat_rot(q)
    local x, y, z, w = q[1], q[2], q[3], q[4]
    local sing = z * x - w * y
    local yaw = deg(atan(2 * (w * z + x * y), 1 - 2 * (y * y + z * z)))
    local pitch, roll
    if sing < -0.4999995 then pitch, roll = -90.0, -yaw - 2 * deg(atan(x, w))
    elseif sing > 0.4999995 then pitch, roll = 90.0, yaw - 2 * deg(atan(x, w))
    else pitch, roll = deg(math.asin(2 * sing)), deg(atan(-2 * (w * x + y * z), 1 - 2 * (x * x + y * y))) end
    return { Pitch = pitch, Yaw = yaw, Roll = roll }
end
local FLY_BASE = rot_quat(0.0, -90.0, 80.0)        -- (laid out flat, head first)
-- spun `a` degrees about his own length (his mesh's up, before he is laid out)
local function body_roll(a)
    local pawn = lib.pawn()
    if not pawn then return end
    local q = quat_mul(FLY_BASE, { 0.0, 0.0, sin(rad(a) / 2), cos(rad(a) / 2) })
    pcall(function() pawn.Mesh.RelativeRotation = quat_rot(q) end)
end
local function ease(t) t = max(0.0, min(1.0, t)); return t * t * (3.0 - 2.0 * t) end

-- ------------------------------------------------------------ sparkles (actors/sparkle: six pictures, two frames each)
local function sparkle_add(s, world, x, y, z)
    s.sparkles = s.sparkles or {}
    if #s.sparkles >= 24 then return end
    local q = lib.quad_actor(world, { X = x, Y = y, Z = z }, 22.0, "ending_sparkle_0", "alpha")
    if not q then return end
    local pmc = nil
    pcall(function() pmc = q:GetComponentByClass(StaticFindObject("/Script/ProceduralMeshComponent.ProceduralMeshComponent")) end)
    s.sparkles[#s.sparkles + 1] = { actor = q, pmc = pmc, x = x, y = y, z = z, t = 0,
        vx = (math.random() - 0.5) * 3.0, vy = (math.random() - 0.5) * 3.0, vz = 1.5 + math.random() * 2.0 }
end
local function sparkles_step(s, world)
    if not s.sparkles then return end
    local keep = {}
    local c = s.cam_at
    for _, sp in ipairs(s.sparkles) do
        sp.t = sp.t + 1
        if sp.t > 12 then
            lib.destroy(sp.actor)
        else
            sp.x, sp.y, sp.z = sp.x + sp.vx, sp.y + sp.vy, sp.z + sp.vz
            local k = floor(sp.t / 2) % 6
            if sp.pmc and sp.t % 2 == 0 then
                pcall(function()
                    local mid = lib.get_mid(world, "alpha", "ending_sparkle_" .. k)
                    if mid then sp.pmc:SetMaterial(0, mid) end
                end)
            end
            local yaw, pitch = 0.0, 0.0
            if c then
                local dx, dy, dz = c[1] + OFFSET.X - sp.x, c[2] + OFFSET.Y - sp.y, c[3] + OFFSET.Z - sp.z
                yaw, pitch = deg(atan(dy, dx)) + 180.0, -deg(atan(dz, sqrt(dx * dx + dy * dy)))
            end
            local sc = 1.0 - sp.t / 16.0
            pcall(function()
                sp.actor:K2_TeleportTo({ X = sp.x, Y = sp.y, Z = sp.z }, { Pitch = pitch, Yaw = yaw, Roll = 0.0 })
                sp.actor:SetActorScale3D({ X = sc, Y = sc, Z = sc })
            end)
            keep[#keep + 1] = sp
        end
    end
    s.sparkles = keep
end
local function sparkles_clear(s)
    for _, sp in ipairs(s.sparkles or {}) do lib.destroy(sp.actor) end
    s.sparkles = nil
end

local function outro_frame(s, dt)
    s.jumbo_path = s.jumbo_path or jumbo_path()
    local F0 = s.of
    s.of = s.of + dt * 30.0
    local F = s.of
    local function at(f) return F0 < f and F >= f end
    local pawn = lib.pawn()
    -- his part: held up and moved along, his own animation running (falling: in the air)
    if F >= OUT.takeoff then
        if not s.lifted then
            s.lifted = true
            pcall(function() pawn:DisableInput(lib.controller()) end)
        end
        local x, y, z, yaw = outro_place(s, F)
        local x2, y2, z2 = outro_place(s, F + 1.0)
        local tf = F - OUT.takeoff
        if tf >= 66 and tf < 92 then yaw = yaw + 360.0 * ease((tf - 66) / 24.0) end      -- (the third jump: a twist)
        pcall(function()
            local cm = pawn.CharacterMovement
            cm.GravityScale = 0.0
            pawn:K2_TeleportTo({ X = x + OFFSET.X, Y = y + OFFSET.Y, Z = z + OFFSET.Z + 92.0 }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 })
            if cm.MovementMode ~= 3 then cm:SetMovementMode(3, 0) end
            cm.Velocity = { X = (x2 - x) * 30.0, Y = (y2 - y) * 30.0, Z = (z2 - z) * 30.0 }
        end)
        local f = F - OUT.takeoff
        -- (as loud as MARIO FX, as all his voice is: sfx.lua)
        for k, name in pairs(SHOUTS) do if at(OUT.takeoff + k) then sfx(name, 1.0) end end
    end
    if F < OUT.takeoff then
        -- (holding it up he spins round twice, slowing to face the way he will go)
        local spin = 720.0 * ease((F - 15.0) / 75.0)
        if s.hold_air then
            -- (over no floor - Final Bowser's broken one: held where he took it, in the engine's flying, still)
            pcall(function()
                local cm, c = pawn.CharacterMovement, s.centre
                if cm.MovementMode ~= 5 then cm:SetMovementMode(5, 0) end
                cm.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 }
                pawn:K2_TeleportTo({ X = c[1] + OFFSET.X, Y = c[2] + OFFSET.Y, Z = c[3] + OFFSET.Z + 92.0 }, { Pitch = 0.0, Yaw = spin, Roll = 0.0 })
            end)
        else
            pcall(function() pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = spin, Roll = 0.0 }, false) end)
        end
    end
    if F >= OUT.fly and not s.flying then
        s.flying = true
        fly_pose(true)
    end
    if s.flying then
        -- (gliding: a bank that comes and goes, and every two and a half seconds a barrel roll)
        local f = F - OUT.fly
        local cyc = f % 75.0
        local roll = 22.0 * sin(f * 0.08)
        if cyc < 24.0 then roll = roll + 360.0 * ease(cyc / 24.0) end
        body_roll(roll)
    end
    -- the star, held up over him, turning (in the air, held out ahead of him)
    local loc = nil
    pcall(function() loc = pawn:K2_GetActorLocation() end)
    if s.held_star and loc then
        local whirl = (F * 22.0) % 360.0
        local bob = sin(F * 0.25) * 12.0
        local sx, sy, sz
        if s.flying then
            -- (held out ahead of him, circling round his line of flight)
            local _, _, _, yaw = outro_place(s, F)
            local a = rad(yaw)
            local o = F * 0.3
            local r = 28.0
            sx = loc.X + cos(a) * 125.0 - sin(a) * cos(o) * r
            sy = loc.Y + sin(a) * 125.0 + cos(a) * cos(o) * r
            sz = loc.Z + 15.0 + sin(o) * r + bob
        else
            sx, sy, sz = loc.X, loc.Y, loc.Z + 130.0 + bob
        end
        lib.set_pose(s.held_star, sx, sy, sz, whirl)
        local pulse = 1.0 + 0.12 * sin(F * 0.5)
        pcall(function() s.held_star.actor:SetActorScale3D({ X = pulse, Y = pulse, Z = pulse }) end)
        local world = lib.world()
        if world and floor(F) ~= floor(F0) and floor(F) % 2 == 0 then
            sparkle_add(s, world, sx + (math.random() - 0.5) * 40.0, sy + (math.random() - 0.5) * 40.0, sz + (math.random() - 0.5) * 40.0)
        end
    end
    if floor(F) ~= floor(F0) then sparkles_step(s, lib.world()) end
    -- the camera
    local px, py, pz = loc and loc.X - OFFSET.X or s.centre[1], loc and loc.Y - OFFSET.Y or s.centre[2], loc and loc.Z - OFFSET.Z - 92.0 or s.centre[3]
    local k = 1.0 - 0.9 ^ (dt * 30.0)
    local gx, gy, gz, fx, fy, fz
    if F < OUT.fly then
        -- (round to his front, 600 out and 150 up, a quarter turn off to the side; looking at him)
        local yaw = rad(0.0 + 35.0)
        gx, gy, gz = s.centre[1] + cos(yaw) * 450.0, s.centre[2] + sin(yaw) * 450.0, s.centre[3] + 170.0
        if F >= OUT.takeoff then
            -- (as he jumps off, the camera hangs back and turns after him)
            gx, gy, gz = s.cam_at[1], s.cam_at[2], s.cam_at[3]
        end
        fx, fy, fz = px, py, pz + 100.0 + (pz - s.centre[3]) * 0.3
    else
        -- (in the air: behind him and to his side, then dropping back as he flies on out of the picture)
        local f = F - OUT.fly
        local _, _, _, yaw = outro_place(s, F)
        local back = (f < 140) and 320.0 or (320.0 + (f - 140) * 3.0)
        local side = (f < 140) and 180.0 or (180.0 + (f - 140) * 2.0)
        local a = rad(yaw)
        gx = px - cos(a) * back - sin(a) * side
        gy = py - sin(a) * back + cos(a) * side
        gz = pz + 60.0 + max(0.0, f - 140) * 1.2
        fx, fy, fz = px, py, pz + 90.0
    end
    s.cam_at = s.cam_at or { gx, gy, gz }
    local kk = (F < OUT.fly) and k or (1.0 - 0.65 ^ (dt * 30.0))
    s.cam_at[1] = s.cam_at[1] + (gx - s.cam_at[1]) * kk
    s.cam_at[2] = s.cam_at[2] + (gy - s.cam_at[2]) * kk
    s.cam_at[3] = s.cam_at[3] + (gz - s.cam_at[3]) * kk
    s.cam_look = s.cam_look or { fx, fy, fz }
    s.cam_look[1] = s.cam_look[1] + (fx - s.cam_look[1]) * 0.5
    s.cam_look[2] = s.cam_look[2] + (fy - s.cam_look[2]) * 0.5
    s.cam_look[3] = s.cam_look[3] + (fz - s.cam_look[3]) * 0.5
    set_camera(s, s.cam_at[1], s.cam_at[2], s.cam_at[3], s.cam_look[1], s.cam_look[2], s.cam_look[3], 45.0)
    -- and the white, to Peach's scene, the tune dying away under it
    if at(OUT.white) then fade_music(s, (OUT.done - OUT.white) / 30.0) end
    show(s.ui.white, max(0.0, min(1.0, (F - OUT.white) / (OUT.done - OUT.white))))
    return F >= OUT.done
end

local function end_outro(s)
    if s.flying then fly_pose(false); s.flying = nil end
    sparkles_clear(s)
    if s.held_star then lib.destroy(s.held_star.actor); s.held_star = nil end
    local pawn = lib.pawn()
    pcall(function() pawn.CharacterMovement.GravityScale = 1.0 end)
end

-- ------------------------------------------------------------ Peach's scene (castle grounds; Mario 64's units)
local function sm(x, y, z) return -z * 0.75, x * 0.75, y * 0.75 end
local function sins16(a) return math.sin(a * math.pi / 32768.0) end
local function coss16(a) return math.cos(a * math.pi / 32768.0) end

-- Mario 64's ending on the castle grounds (act_end_peach_cutscene, and camera.c's sCutsceneEnding - the US version), as
-- the game runs it. data/ending_peach.lua, made by tools/ending_peach_cam.py from the decomp, has it frame by frame: the
-- camera's place, focus and zoom, his fall, Peach's descent, the birds' ways. "the peach outro is actually all wrong ...
-- please fix it to be like this" (a video of the game's own), 2026-11-02: its camera had been made up, the two Toads
-- and the birds were missing, and its last two steps - her "let's bake a delicious cake", the look up into the sky with
-- the birds, her "Mario!" as he runs in - were cut 470 frames short.
-- Frames F: 1 is the first of his landing (his fall comes before it, from F = 1 - land); the camera's frame is
-- F + land - 1.
local P = {
    star = 20, music = 110, white_in = 276, peach = 315, white_out = 319, descend = 630, beside = 1214, land_anim = 1236,
    talk = 1353, dialog2 = 1753, kiss = 1953, dialog3 = 2235, run_castle = 2585, last = 2680, black = 2975, done = 3035,
}
-- her lines: frame, line, how long it stays, her voice
-- (the Final Bowser story's: "You saved me again!", "And I baked another cake...", "...for you, Mario!" in place of the
-- power of the stars, something special and the cake to bake - exporter/finalx.py; her voice only where it says the
-- same: "peach say you saved me again and I baked another cake for you mario", 2026-11-04)
local LINES = {
    -- (and her new lines voiced: the user's own takes, pitched up - sfx/peach_saved_again etc., 2026-11-04)
    { 1503, 0, 30, "peach_mario" }, { 1563, 1, 65, "peach_saved_again" },
    { 1782, 2, 30, "peach_thanks_to_you" }, { 1828, 3, 30, "peach_thank_you" }, { 1883, 4, 60, "peach_another_cake" },
    { 2365, 7, 55, "peach_for_you_mario" },
    { 2680, 8, 40, "peach_mario2" },
}
-- the Toads either side of her (sEndLeftToadObj, sEndRightToadObj): where, their animation by her, and the one that
-- walks them back into the castle after her last words (bhv_end_toad_loop: 0 goes on to 1, 2 to 3; 1 and 3 hold)
local TOADS = { { x = -200.0, k = 4, walk = 0 }, { x = 200.0, k = 5, walk = 2 } }
local function toad_next(k) if k == 0 or k == 2 then return k + 1 end end
local TOAD_HOLD = { [1] = true, [3] = true }
-- (bhv_end_peach_loop: 0-2 and 6-7 go on to the next)
local function peach_next(k) if k < 3 or k == 6 or k == 7 then return k + 1 end end

-- an animation run on a frame (Mario 64's 30ths): `a` { k, f } on `inst`; at its end on to next_of(k) if there is one,
-- else held on its last frame (a no-loop one) or looped
local function anim_step(a, inst, next_of, holds)
    local an = inst and inst.data and inst.data.anims and inst.data.anims[(a.k or 0) + 1]
    if not an then return end
    a.f = (a.f or 0.0) + 1.0
    local last = max(1, (an.loopEnd or an.frames or 1)) - 1
    if a.f > last then
        local n = next_of and next_of(a.k)
        if n and inst.data.anims[n + 1] then
            a.k, a.f = n, 0.0
        elseif (holds and holds[a.k]) or (tonumber(an.flags) or 0) % 2 == 1 then
            a.f = last
        else
            a.f = an.loopStart or 0
        end
    end
end
local function anim_set(a, k) if a.k ~= k then a.k, a.f = k, 0.0 end end

-- end_obj_set_visual_pos: the floor under where its animation has carried it (its own way from its place, its turn 0),
-- looked for from 10 over its height down - never up onto a higher one. Mario 64 puts Peach and the Toads there every
-- frame of her last words, which walk them in through the castle's door, off its step: held at the step's height,
-- "peach still floats as she walks into the castle", 2026-11-02. Its new height in Mario 64's units, or nil.
local function visual_floor(inst, a, x, y, z)
    local an = inst and inst.data.anims[(a.k or 0) + 1]
    local tx, ty = 0.0, 0.0
    if an and an.trans then
        local f = floor(a.f or 0) % max(1, an.frames or 1)
        tx, ty = an.trans[f * 3 + 1] or 0.0, an.trans[f * 3 + 2] or 0.0
    end
    local g = G()
    if not (g and g.floor_z) then return nil end
    local sx, sy, sz = sm(x, y, z)
    local fz = g.floor_z(sx + tx, sy + ty, sz + 7.5)
    if not fz or fz > sz + 7.5 or fz < sz - 400.0 then return nil end
    return fz / 0.75
end

-- On past their walk's end, the way it took them - their last walk again, from where it left them - till they are in
-- through the castle's door (Mario 64's z -3155), and gone: Mario 64's narrower picture had lost them where they stop,
-- and the wider one showed them standing at its edge - "I can see peach and toads stop just outside the screen",
-- 2026-11-02. `w` { inst, a, z, gone }: z (Mario 64's) moved on by each walk's length.
local DOOR_Z = -3100.0
-- (the story's Peach: out of the castle's door, walking to where she stands - `from`, `to`, Mario 64 units along its z,
-- her visible place - in her own walk (3), turned round, ending `frames` before she would have come down beside him;
-- not freed from the star over the door and floating down: "instead of peach coming out of the star have her come out
-- of the castle", 2026-11-04)
-- She comes out as the flash fades (`at`, a frame of the scene; the flash's fade `fade` frames, not 192), watched by a
-- camera of her own (WALK_CAM: from the side of her way, Mario 64's units, her chest `up` over her feet - not the game's,
-- which followed her down out of the sky: "outro is using peach camera, it instead should show her coming out of the
-- castle", 2026-11-04); once she stands there, on at once to his coming to her side (P.beside), the game's wait for her
-- slow descent skipped.
local WALK_OUT = { from = DOOR_Z + 100.0, to = -1300.0, at = 365, fade = 70 }
local WALK_CAM = { from = { 380.0, 1130.0, -980.0 }, to = { 300.0, 1080.0, -760.0 }, up = 135.0, fov = 45.0, frames = 404 }
local function walk_on(w, walk_k)
    local an = w.inst and w.inst.data.anims[walk_k + 1]
    if not (an and an.trans) or w.a.k ~= walk_k or w.gone then return end
    local last = max(1, (an.loopEnd or an.frames or 1)) - 1
    if w.a.f >= last then
        w.z = w.z - ((an.trans[last * 3 + 1] or 0.0) - (an.trans[1] or 0.0)) / 0.75
        w.a.f = 0.0
    end
    local f = floor(w.a.f) % max(1, an.frames or 1)
    if w.z - (an.trans[f * 3 + 1] or 0.0) / 0.75 < DOOR_Z then
        w.gone = true
        pcall(function() w.inst.actor:SetActorHiddenInGame(true) end)
    end
end

local function place(inst, a, x, y, z)
    if not inst then return end
    pcall(function() lib.pose(inst, inst.data.anims[(a.k or 0) + 1], floor(a.f or 0)) end)
    local sx, sy, sz = sm(x, y, z)
    lib.set_pose(inst, sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z, 0.0)
end

-- generate_yellow_sparkles: two a frame on a sphere about the point, going round it
local function yellow_sparkles(s, x, y, z, r)
    s.spk_t, s.spk_p = s.spk_t or 0, s.spk_p or 0
    local ox = r * coss16(s.spk_t) * sins16(s.spk_p)
    local oy = r * sins16(s.spk_t)
    local oz = r * coss16(s.spk_t) * coss16(s.spk_p)
    local world = lib.world()
    for _, k in ipairs({ 1.0, -4.0 / 3.0 }) do
        local sx, sy, sz = sm(x + ox * k, y + oy * k, z + oz * k)
        sparkle_add(s, world, sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z)
    end
    s.spk_t, s.spk_p = (s.spk_t + 0x3800) % 0x10000, (s.spk_p + 0x6000) % 0x10000
end

-- the camera, from the game's own every frame - not blended across a cut
-- the Wing Cap on him, quietly (no fanfare, voice or tune), from the Grand Star to his landing: Mario 64 puts it on him
-- as he takes the star (jumbo_star_cutscene_falling) and again for his fall onto the castle grounds, and lets it run out
-- 60 frames after he lands (end_peach_cutscene_mario_landing) - "mario should also have wing cap on", 2026-11-02. Kept
-- through the castle grounds' loading (game.lua stops a cap that leaves its own course).
wing_cap = function(on)
    local C, g = package.loaded["caps"], G()
    if not C then return end
    if on then
        if not (C.on and C.on("wing")) then pcall(C.give, "wing", true, 600.0) end
        if g and g.level_of then C.level = g.level_of("grounds") end
    elseif C.on and C.on("wing") then
        pcall(C.stop, true)
    end
end
-- (the close look at him just after he lands - land_closeup, the camera's 3rd shot - from further back along its own
-- line: "you need to zoom out on the camera that comes right after mario lands", 2026-11-02)
local CLOSEUP_BACK = 1.8

local function track_camera(s, F)
    local ep = s.ep
    local cam = ep.cam
    local n = #cam // 7
    local c = max(0.0, min(n - 1.0, F + ep.land - 1))
    local i = floor(c)
    local j = min(i + 1, n - 1)
    local t = c - i
    if s.cuts[j] then t = 0.0 end
    local function C(k) local a, b = cam[i * 7 + k], cam[j * 7 + k]; return a + (b - a) * t end
    local px, py, pz = sm(C(1), C(2), C(3))
    local fx, fy, fz = sm(C(4), C(5), C(6))
    local sh = ep.shots or {}
    if sh[3] and sh[4] and c >= sh[3] and c < sh[4] then
        px, py, pz = fx + (px - fx) * CLOSEUP_BACK, fy + (py - fy) * CLOSEUP_BACK, fz + (pz - fz) * CLOSEUP_BACK
    end
    s.cam_at = { px, py, pz }
    -- (the game's whole 4:3 picture top to bottom, widened to the screen's sides - as the PC ports show it. Its own
    -- letterbox, sEndCutsceneVp, shows only the middle three quarters of that height: cropped so, every shot came out
    -- too close - "alot of camera angles need zoomed out", 2026-11-02)
    local vfov = C(7)
    set_camera(s, px, py, pz, fx, fy, fz, vfov)
    return c
end

-- the birds (bhvEndBirds1 over the castle as she wakes, gone at the next shot; bhvEndBirds2 off into the sky after her
-- last words), each on its way from the data, flapping
local function birds_frame(s, c)
    local ep, data = s.ep, s.bird_data
    if not (ep.birds and data) then return end
    s.birds = s.birds or {}
    local K = 360.0 / 65536.0
    for i, b in ipairs(ep.birds) do
        local live = s.birds[i]
        if live ~= false then
            local n = #b.way // 6
            local k = c - b.c0
            if k >= 0 and k < n then
                if not live then
                    local x, y, z = sm(b.way[1], b.way[2], b.way[3])
                    local inst = lib.make_instance(lib.world(), data, { X = x + OFFSET.X, Y = y + OFFSET.Y, Z = z + OFFSET.Z }, 0.0, 0.7)
                    live = { inst = inst }
                    if inst then inst.moves = true end
                    s.birds[i] = live
                    if b.sound then sfx("birds_fly_away", 1.0) end
                end
                if live.inst then
                    local w = b.way
                    local ci = floor(k)
                    local cj = min(ci + 1, n - 1)
                    local t = k - ci
                    local function W(m) local a, z2 = w[ci * 6 + m], w[cj * 6 + m]; return a + (z2 - a) * t end
                    local x, y, z = sm(W(1), W(2), W(3))
                    local pitch, yaw, roll = w[ci * 6 + 4], w[ci * 6 + 5], w[ci * 6 + 6]
                    pcall(function() lib.pose(live.inst, live.inst.data.anims[1], (b.f0 or 0) + k) end)
                    pcall(function()
                        live.inst.actor:K2_SetActorLocationAndRotation({ X = x + OFFSET.X, Y = y + OFFSET.Y, Z = z + OFFSET.Z },
                            { Pitch = pitch * K, Yaw = -yaw * K, Roll = -roll * K }, false, {}, true)
                    end)
                end
            elseif live and k >= n then
                if live.inst then lib.destroy(live.inst.actor) end
                s.birds[i] = false
            end
        end
    end
end

-- His fall into the ending, upright in STORROR's own fall (the one it plays as he drops off a ledge), looped on its
-- FullBody slot: held in the air with no movement of his own he had no pose at all, and came down twisted - "players
-- body contorted when coming down with wing cap", 2026-11-02. Off as he lands, STORROR's landing taking over.
local FALL_ANIM = "FallingInAir_40_Drew_131024_Falling-003_frames_829-1555"
local function fall_pose(on)
    local pawn = lib.pawn()
    if not pawn then return end
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        if on then
            for _, o in ipairs(FindAllOf("AnimSequence") or {}) do
                local ok, n = pcall(function() return o:GetFName():ToString() end)
                if ok and n == FALL_ANIM then
                    ai:PlaySlotAnimationAsDynamicMontage(o, FName("FullBody"), 0.2, 0.25, 1.0, 1000, -1.0, 0.0)
                    break
                end
            end
        else
            ai:StopSlotAnimation(0.25, FName("FullBody"))
        end
    end)
end

-- His run to her side (end_peach_cutscene_run_to_peach: across the bridge at 20 a frame, the camera following him) -
-- teleported there, it was seen: "can see the player getting teleported dont show it on screen fade to white if you
-- have to", 2026-11-02. Run from wherever he stands, STORROR's quick walk (its cutscene walk cycle, at its pace) on him
-- and his own movement off, so that he goes where he is put; too far for that, a white flash covers the move.
local RUN_ANIM, RUN_RATE = "DrewWalkStraightCycle", 2.2
local RUN_SPEED = 20.0 * 0.75                 -- (cm a frame)
local RUN_MAX = 1800.0                        -- (cm: further, the flash)
local RUN_ON = false                          -- (off: the flash always - see where it is decided)
local function run_pose(on)
    local pawn = lib.pawn()
    if not pawn then return end
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        if on then
            for _, o in ipairs(FindAllOf("AnimSequence") or {}) do
                local ok, n = pcall(function() return o:GetFName():ToString() end)
                if ok and n == RUN_ANIM then
                    ai:PlaySlotAnimationAsDynamicMontage(o, FName("FullBody"), 0.15, 0.25, RUN_RATE, 1000, -1.0, 0.0)
                    break
                end
            end
        else
            ai:StopSlotAnimation(0.25, FName("FullBody"))
        end
    end)
end
-- him put on the floor under `x, y` (scene), turned `yaw`: held (his own movement off) or stood there, his again
local function put_on_floor(x, y, z_from, yaw, held)
    local pawn, pc = lib.pawn(), lib.controller()
    if not pawn then return end
    local g = G()
    local fz = (g and g.floor_z and g.floor_z(x, y, z_from)) or z_from
    pcall(function()
        local cm = pawn.CharacterMovement
        if held then cm:SetMovementMode(0, 0) end
        pawn:K2_TeleportTo({ X = x + OFFSET.X, Y = y + OFFSET.Y, Z = fz + OFFSET.Z + 92.0 }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 })
        if not held then
            cm.GravityScale = 1.0
            cm:StopMovementImmediately()
            cm:SetMovementMode(1, 0)
            pawn:EnableInput(pc)
        end
    end)
end

local function start_peach_scene(s)
    local g = G()
    if not g then return false end
    local ep = lib.load_data("data.ending_peach")
    if not (ep and ep.cam and ep.land) then log("ending: no data for Peach's scene"); return false end
    s.ep = ep
    s.cuts = {}
    for _, c in ipairs(ep.shots or {}) do s.cuts[c] = true end
    g.act_override = nil
    local ok, r = pcall(g.load_scene, "grounds", true)
    if not (ok and r ~= false) then log("ending: the castle grounds did not load (%s)", tostring(r)); return false end
    -- (its tune from the scene's first frame, not 10 s in - it began with the scene and started over at P.music: "also
    -- ending music started very late", 2026-11-04)
    fade_cancel(s)
    if MUSIC then pcall(MUSIC.play, "event_ending", true) end
    s.music_on = true
    local world = lib.world()
    -- where he lands (Mario 64: under where he fell, in front of the castle), and where he goes
    local x0, y0 = sm(0.0, 0.0, 0.0)
    s.p_floor = (g.floor_z and g.floor_z(x0, y0, 20000.0)) or 0.0
    local x1, y1 = sm(0.0, 0.0, -1180.0)
    s.p_floor2 = (g.floor_z and g.floor_z(x1, y1, 20000.0)) or s.p_floor
    -- (up where his fall starts, held there: end_peach_cutscene_mario_falling, the wing cap fluttering him down)
    local fx, fy, fz = sm(0.0, ep.fall[1], 0.0)
    hold_athlete({ fx, fy, fz }, 0.0, false)
    fall_pose(true)
    wing_cap(true)
    s.falling = true
    keep_safe()
    -- the great star over the door (scale 3), Peach, the Toads: out of sight until their moments
    local star = g.actor_data and g.actor_data("star")
    if star then
        local sx, sy, sz = sm(0.0, 2528.0, -1800.0)
        s.jumbo = lib.make_instance(world, star, { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z }, 0.0, 3.0)
        if s.jumbo then s.jumbo.moves = true; pcall(function() s.jumbo.actor:SetActorHiddenInGame(true) end) end
        -- (rainbow, as Bowser's mega star - "the stars gold", 2026-11-04)
        if s.jumbo and s.jumbo.data then
            local mid = lib.get_mid(world, "opaque", "rainbow_star", 0.93)
            for i, part in ipairs(s.jumbo.data.parts) do
                local comp = s.jumbo.comps[i]
                for _, sec in ipairs(part.sections or {}) do
                    if mid and comp and not (sec.texture or ""):find("eye") then pcall(function() comp:SetMaterial(sec.id, mid) end) end
                end
            end
        end
    end
    local pd = lib.load_data("data.actor_peach_end")
    if pd then
        local px, py, pz = sm(0.0, 2428.0, -1300.0)
        s.peach = lib.make_instance(world, pd, { X = px + OFFSET.X, Y = py + OFFSET.Y, Z = pz + OFFSET.Z }, 0.0, 1.0)
        if s.peach then s.peach.moves = true; pcall(function() s.peach.actor:SetActorHiddenInGame(true) end) end
    end
    local td = g.actor_data and g.actor_data("geo_toad_geo")
    s.toads = {}
    for i, T in ipairs(TOADS) do
        local inst = nil
        if td then
            local tx, ty, tz = sm(T.x, 906.0, -1290.0)
            inst = lib.make_instance(world, td, { X = tx + OFFSET.X, Y = ty + OFFSET.Y, Z = tz + OFFSET.Z }, 0.0, 1.0)
            if inst then inst.moves = true; pcall(function() inst.actor:SetActorHiddenInGame(true) end) end
        end
        s.toads[i] = { inst = inst, x = T.x, y = 906.0, z = -1290.0, a = { k = T.k, f = 0.0 }, walk = T.walk }
    end
    s.bird_data = g.actor_data and g.actor_data("birds")
    s.p_y, s.pf, s.lines_on = 2428.0, 1.0 - ep.land, {}
    s.pa = { k = 4, f = 0.0 }
    s.peach_down, s.run, s.flash = nil, nil, nil
    s.pw = { inst = s.peach, a = s.pa, z = -1300.0 }
    s.phase, s.t = "peach", 0.0
    log("ending: Peach's scene (floor %.0f, by the door %.0f; his fall %d frames)", s.p_floor, s.p_floor2, ep.land)
    return true
end

-- (her walk out, watched: from beside her way, turning after her, drawing back a little as she comes)
local function walk_camera(s, F)
    local W, C = WALK_OUT, WALK_CAM
    if not s.door_y then
        local g = G()
        local x, y = sm(0.0, 0.0, W.from)
        local fz = g and g.floor_z and g.floor_z(x, y, 1500.0 * 0.75)
        s.door_y = fz and (fz / 0.75) or 900.0
    end
    local k = max(0.0, min(1.0, (F - W.at) / C.frames))
    k = k * k * (3.0 - 2.0 * k)
    local cx = C.from[1] + (C.to[1] - C.from[1]) * k
    local cy = C.from[2] + (C.to[2] - C.from[2]) * k
    local cz = C.from[3] + (C.to[3] - C.from[3]) * k
    local fz = s.walk_seen or W.from
    local fy = ((s.walk_seen and s.p_y) or s.door_y) + C.up
    -- (eased after her, not jerked along with her steps)
    local q = s.walk_focus
    if not q then q = { fy, fz }; s.walk_focus = q end
    q[1], q[2] = q[1] + (fy - q[1]) * 0.12, q[2] + (fz - q[2]) * 0.12
    local px, py, pz = sm(cx, cy, cz)
    local qx, qy, qz = sm(0.0, q[1], q[2])
    set_camera(s, px, py, pz, qx, qy, qz, C.fov)
end

local function peach_frame(s, dt)
    if s.skip_to then
        if s.pf < s.skip_to then log("ending: Peach there - on to him (%.0f frames skipped)", s.skip_to - s.pf); s.pf = s.skip_to end
        s.skip_to = nil
        s.walk_cam_done = true
    end
    local F0 = s.pf
    s.pf = s.pf + dt * 30.0
    local F = s.pf
    local function at(f) return F0 < f and F >= f end
    local steps = floor(F) - floor(F0)
    local ui = s.ui
    local ep = s.ep
    -- his fall, then his landing: the player's again
    if s.falling then
        if F < 1.0 then
            local gi = max(0, min(ep.land, floor(F + ep.land)))
            local fx, fy, fz = sm(0.0, ep.fall[gi + 1], 0.0)
            hold_athlete({ fx, fy, fz }, 0.0, false)
        else
            s.falling = false
            fall_pose(false)
            local x0, y0 = sm(0.0, 0.0, 0.0)
            stand_athlete({ x0, y0, s.p_floor }, 0.0)
            local g = G()
            if g and g.freeze then g.freeze(0.6) end    -- (held up until the grounds' floors take him)
        end
    end
    if at(P.star) and s.jumbo then pcall(function() s.jumbo.actor:SetActorHiddenInGame(false) end) end
    if at(P.star + 60) then wing_cap(false) end
    if at(P.music) and MUSIC and not s.music_on then pcall(MUSIC.play, "event_ending", true) end
    if at(P.white_in + 1) then sfx("star_appears2", 1.0) end
    -- the star spins over the door until the flash, sparkling
    if s.jumbo and F >= P.star and F < P.peach then
        local sx, sy, sz = sm(0.0, 2528.0, -1800.0)
        lib.set_pose(s.jumbo, sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z, (F * 0x400 * 360.0 / 65536.0) % 360.0)
        for _ = 1, steps do yellow_sparkles(s, 0.0, 2528.0, -1800.0, 250.0) end
    end
    -- the flash: up over 14 frames, the star gone and Peach and the Toads there behind it, down again over 192
    local white = 0.0
    if F >= P.white_in and F < P.white_out then white = min(1.0, (F - P.white_in) / 14.0) end
    if F >= P.white_out then white = max(0.0, 1.0 - (F - P.white_out) / ((WALK_OUT and WALK_OUT.fade) or 192.0)) end
    if s.flash then
        local k = F - s.flash.f0
        white = max(white, k < 5 and k / 5.0 or max(0.0, 1.0 - (k - 7.0) / 10.0))
        if k >= 5 and not s.flash.moved then
            s.flash.moved = true
            local bx, by = sm(0.0, 0.0, -1180.0)
            put_on_floor(bx, by, s.p_floor2 + 200.0, 0.0, false)
        end
        if k > 17 then s.flash = nil end
    end
    show(ui.white, white)
    if at(P.peach) then
        if s.jumbo then lib.destroy(s.jumbo.actor); s.jumbo = nil end
        if s.peach and not WALK_OUT then pcall(function() s.peach.actor:SetActorHiddenInGame(false) end) end
        for _, T in ipairs(s.toads) do
            if T.inst then pcall(function() T.inst.actor:SetActorHiddenInGame(false) end) end
        end
        anim_set(s.pa, 4)
    end
    -- her height: as the game's own (data/ending_peach.lua peach, her descent) - then on the floor, from her last words
    -- (smoothly between the game's frames, as the camera following her is: stepped 30 times a second she shook against
    -- it as she came down - "peach is glitching out while going to the ground", 2026-11-02. And only through her descent:
    -- set to its last height every frame after, it undid the floor under her walk between the game's frames.)
    if F >= P.peach and ep.peach and not s.peach_down and not WALK_OUT then
        local n = #ep.peach
        local kf = F - (ep.peach0 or P.peach)
        local k = floor(kf)
        if k >= n - 1 then
            s.p_y, s.peach_down = ep.peach[n], true
        elseif k >= 0 then
            local a, b = ep.peach[k + 1], ep.peach[k + 2]
            s.p_y = a + (b - a) * (kf - k)
        end
    end
    -- her sparkles, as she appears and comes down
    if F >= P.peach and F < P.beside and not WALK_OUT then
        for _ = 1, steps do
            if F < P.descend then yellow_sparkles(s, 0.0, 2628.0, -1300.0, 150.0)
            else yellow_sparkles(s, 0.0, s.p_y, -1300.0, 150.0) end
        end
    end
    if s.sparkles and steps > 0 then for _ = 1, steps do sparkles_step(s, lib.world()) end end
    -- (decided a moment early: far off, the flash comes up to white by the time he goes)
    if at(P.beside - 5) then
        local pawn = lib.pawn()
        local bx, by = sm(0.0, 0.0, -1180.0)
        local from = nil
        pcall(function() local l = pawn:K2_GetActorLocation(); from = { l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z } end)
        local d = from and sqrt((from[1] - bx) ^ 2 + (from[2] - by) ^ 2) or 1.0e9
        -- (the run is off - RUN_ON: moved there frame by frame, STORROR took him for falling and landing over and over,
        -- the mod's fling guard went off and his ragdoll took him through the floor - "player goes through floor",
        -- 2026-11-02. The white flash for every distance.)
        if RUN_ON and d <= RUN_MAX then
            s.run = { x0 = from[1], y0 = from[2], z = from[3], x1 = bx, y1 = by, d = d, f0 = P.beside,
                      yaw = deg(atan(by - from[2], bx - from[1])) }
        else
            s.flash = { f0 = F }
        end
    end
    if s.run and F >= s.run.f0 then
        local R = s.run
        if not R.going then
            R.going = true
            pcall(function() lib.pawn():DisableInput(lib.controller()) end)
            run_pose(true)
        end
        local k = (F - R.f0) * RUN_SPEED
        if k >= R.d then
            run_pose(false)
            put_on_floor(R.x1, R.y1, s.p_floor2 + 200.0, 0.0, false)
            s.run = nil
        else
            local x, y = R.x0 + (R.x1 - R.x0) * k / R.d, R.y0 + (R.y1 - R.y0) * k / R.d
            put_on_floor(x, y, R.z + 150.0, R.yaw, true)
            local g = G()
            local fz = g and g.floor_z and g.floor_z(x, y, R.z + 150.0)
            if fz then R.z = fz + 92.0 end
        end
    end
    if WALK_OUT and s.peach and at(WALK_OUT.at) then
        local an = s.peach.data.anims[4]
        s.walk_out = an and an.trans and true or nil
        if s.walk_out then
            anim_set(s.pa, 3)
            -- (her place along z: where she is seen, less the walk's own way from its first frame)
            s.pw.z = WALK_OUT.from - (an.trans[1] or 0.0) / 0.75
            pcall(function() s.peach.actor:SetActorHiddenInGame(false) end)
        end
    end
    if at(P.land_anim) then anim_set(s.pa, 5) end
    if at(P.talk) then anim_set(s.pa, 6) end
    if at(P.dialog2) then anim_set(s.pa, 9) end
    if at(P.kiss) then anim_set(s.pa, 10) end
    if at(P.dialog3) then
        anim_set(s.pa, 0)
        for _, T in ipairs(s.toads) do anim_set(T.a, T.walk) end
    end
    if F >= P.peach then
        for _ = 1, steps do
            anim_step(s.pa, s.peach, peach_next)
            if s.walk_out then
                -- (her walk's way on at each of its rounds; there, she stands - turned to him again)
                local an = s.peach.data.anims[4]
                local last = max(1, (an.loopEnd or an.frames or 1)) - 1
                if s.pa.f >= last then
                    s.pw.z = s.pw.z + ((an.trans[last * 3 + 1] or 0.0) - (an.trans[1] or 0.0)) / 0.75
                    s.pa.f = 0.0
                end
                local f = floor(s.pa.f) % max(1, an.frames or 1)
                local seen = s.pw.z + (an.trans[f * 3 + 1] or 0.0) / 0.75
                s.walk_seen = seen
                if seen >= WALK_OUT.to then
                    s.walk_out = nil
                    s.pw.z = WALK_OUT.to
                    s.walk_seen = WALK_OUT.to
                    anim_set(s.pa, 5)
                    -- (there: on to his coming to her, a moment on - the frames between skipped, next frame)
                    s.skip_to = P.beside - 6
                end
                -- (her feet on the floor she walks over: looked for from just over where they were - from her old
                -- descent's height, 2428, nothing was found, and she walked out high over the bridge)
                -- (and under where she is seen: turned round, her walk's way runs back from her place, so visual_floor -
                -- which adds it on forward - looked 6 to 9 m behind her, on the lower floor by the door, and she sank
                -- into the rise to the bridge: "peach is going through the floor", 2026-11-04)
                local y = nil
                do
                    local gg = G()
                    local fx, fy = sm(0.0, 0.0, s.walk_out and seen or s.pw.z)
                    local top = ((s.p_y < 1500.0) and (s.p_y + 40.0) or 1300.0) * 0.75
                    local fz = gg and gg.floor_z and gg.floor_z(fx, fy, top)
                    if fz and fz > top - 400.0 then y = fz / 0.75 end
                end
                if y then s.p_y = y elseif s.p_y >= 1500.0 then s.p_y = s.door_y or 906.0 end
            end
            for _, T in ipairs(s.toads) do anim_step(T.a, T.inst, toad_next, TOAD_HOLD) end
            if F >= P.dialog3 then
                walk_on(s.pw, 3)
                for _, T in ipairs(s.toads) do walk_on(T, T.walk + 1) end
            end
            -- (on the floor where their walks take them: dialog 3's end_obj_set_visual_pos)
            if F >= P.dialog3 then
                local y = visual_floor(s.peach, s.pa, 0.0, s.p_y, s.pw.z)
                if y then s.p_y = y end
                s.peach_floor = true
                for _, T in ipairs(s.toads) do
                    local ty = visual_floor(T.inst, T.a, T.x, T.y, T.z)
                    if ty then T.y = ty end
                end
            end
        end
        if s.walk_out then
            -- (turned round, her walk toward him: her walk is the one into the castle)
            pcall(function() lib.pose(s.peach, s.peach.data.anims[(s.pa.k or 0) + 1], floor(s.pa.f or 0)) end)
            local px, py, pz = sm(0.0, s.p_y, s.pw.z)
            lib.set_pose(s.peach, px + OFFSET.X, py + OFFSET.Y, pz + OFFSET.Z, 180.0)
        else
            place(s.peach, s.pa, 0.0, s.p_y, s.pw.z)
        end
        for _, T in ipairs(s.toads) do place(T.inst, T.a, T.x, T.y, T.z) end
    end
    -- (the music down to 40% under her words, from her first line to the star dance, as the game lowers it)
    if MUSIC and MUSIC.set_volume and not s.mfade then
        s.p_music = s.p_music or MUSIC.volume
        local duck = 1.0
        if F >= 1503 and F < 2233 then duck = 0.4 + 0.6 * max(0.0, 1.0 - (F - 1503) / 60.0)
        elseif F >= 2233 then duck = min(1.0, 0.4 + 0.6 * (F - 2233) / 60.0) end
        if not s.p_duck or abs(duck - s.p_duck) > 0.01 then
            s.p_duck = duck
            pcall(MUSIC.set_volume, s.p_music * duck)
        end
    end
    -- her lines: in over 5 frames, held, out over 5 (the two "Mario!" lines are different pictures)
    for _, Ln in ipairs(LINES) do
        local f0, k, dur, voice = Ln[1], Ln[2], Ln[3], Ln[4]
        -- (her voice files open with a third of a second of silence, so that nothing of her is lost while the player
        -- starts up: started that much early, her words still meet their line)
        if at(f0 - 10) and voice then sfx(voice, 1.25) end
        if F >= f0 - 1 and F < f0 + dur + 12 then
            local a = min(1.0, max(0.0, (F - f0) / 5.0))
            if F > f0 + dur + 5 then a = max(0.0, 1.0 - (F - f0 - dur - 5) / 5.0) end
            show(ui.subs[k], a)
        end
    end
    -- the camera, and the birds by it (her walk out: her own camera, from the flash till she is there)
    local c = track_camera(s, F)
    if WALK_OUT and F >= P.peach and F < P.beside and not s.walk_cam_done then walk_camera(s, F) end
    birds_frame(s, c)
    show(ui.black, max(0.0, min(1.0, (F - P.black) / (P.done - P.black))))
    if at(P.black) then fade_music(s, (P.done - P.black) / 30.0) end
    return F >= P.done
end

local function end_peach_scene(s)
    if s.p_music and MUSIC and MUSIC.set_volume and not s.mfade then pcall(MUSIC.set_volume, s.p_music) end
    if s.mfade and s.p_music then s.mfade.base = s.p_music end
    s.p_music, s.p_duck = nil, nil
    if s.jumbo then lib.destroy(s.jumbo.actor); s.jumbo = nil end
    if s.peach then lib.destroy(s.peach.actor); s.peach = nil end
    for _, T in ipairs(s.toads or {}) do if T.inst then lib.destroy(T.inst.actor) end end
    s.toads = nil
    for _, b in pairs(s.birds or {}) do if b and b.inst then lib.destroy(b.inst.actor) end end
    s.birds = nil
    pcall(sparkles_clear, s)
    if s.falling then s.falling = false; fall_pose(false) end
    wing_cap(false)
    if s.run then s.run = nil; run_pose(false) end
    if s.ui and s.ui.subs then for i = 0, 8 do show(s.ui.subs[i], 0.0) end end
    if s.ui then show(s.ui.white, 0.0) end
end

-- ------------------------------------------------------------ the end: all of them waving (act_end_waving_cutscene)
-- After the credits' last shot, back on the castle grounds: Mario, Peach and the two Toads before the door, waving at the
-- camera as it draws back over the bridge, and Lakitu with his camera coming by - 300 frames, then 60 to black and the
-- cake. "theres supposed to be a cutscene with mario peach and toads waving at camera then THE END", 2026-11-02. Its
-- camera and Lakitu's way from data/ending_peach.lua (wave).
-- Him: STORROR's figure facing the camera in its waving emote (the one with an arm up high, open-handed - picked from
-- pictures of all ten), looped, his controls off.
local WAVE_ANIM = "Emote_2088_EMOTES_-DREW"
local function wave_pose(on)
    local pawn = lib.pawn()
    if not pawn then return end
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        if on then
            for _, o in ipairs(FindAllOf("AnimSequence") or {}) do
                local ok, n = pcall(function() return o:GetFName():ToString() end)
                if ok and n == WAVE_ANIM then
                    ai:PlaySlotAnimationAsDynamicMontage(o, FName("FullBody"), 0.25, 0.25, 1.0, 1000, -1.0, 0.0)
                    break
                end
            end
        else
            ai:StopSlotAnimation(0.25, FName("FullBody"))
        end
    end)
end

local function start_wave(s)
    local g = G()
    local ep = s.ep or lib.load_data("data.ending_peach")
    local W = ep and ep.wave
    if not (g and W) then return false end
    s.ep = ep
    g.act_override = nil
    local ok, r = pcall(g.load_scene, "grounds", true)
    if not (ok and r ~= false) then log("ending: the castle grounds did not load for the waving (%s)", tostring(r)); return false end
    for _, b in ipairs(s.ui.bars) do show(b.img, 0.0) end
    for _, pg in ipairs(s.ui.pages) do show(pg, 0.0) end
    local world = lib.world()
    -- him: before the door, a little to Peach's side, turned to the camera (Mario 64's turned half round, 60 aside)
    local mx, my = sm(-60.0, 0.0, -1200.0)
    local mz = (g.floor_z and g.floor_z(mx, my, 20000.0)) or 680.0
    s.wave_at = held_at({ mx, my, mz }, 180.0, WAVE_ANIM)
    s.held = { at = s.wave_at, yaw = 180.0, t = 0.0, anim = WAVE_ANIM }
    s.wave_posed = false
    -- Peach and the Toads either side, all waving (their animations 11, 6 and 7)
    local pd = lib.load_data("data.actor_peach_end")
    if pd then
        local px, py, pz = sm(60.0, 906.0, -1180.0)
        s.wpeach = { inst = lib.make_instance(world, pd, { X = px + OFFSET.X, Y = py + OFFSET.Y, Z = pz + OFFSET.Z }, 0.0, 1.0),
                     x = 60.0, y = 906.0, z = -1180.0, a = { k = 11, f = 0.0 } }
        if s.wpeach.inst then s.wpeach.inst.moves = true end
    end
    local td = g.actor_data and g.actor_data("geo_toad_geo")
    s.wtoads = {}
    for _, T in ipairs({ { x = -180.0, k = 6 }, { x = 180.0, k = 7 } }) do
        local inst = nil
        if td then
            local tx, ty, tz = sm(T.x, 906.0, -1170.0)
            inst = lib.make_instance(world, td, { X = tx + OFFSET.X, Y = ty + OFFSET.Y, Z = tz + OFFSET.Z }, 0.0, 1.0)
            if inst then inst.moves = true end
        end
        s.wtoads[#s.wtoads + 1] = { inst = inst, x = T.x, y = 906.0, z = -1170.0, a = { k = T.k, f = 0.0 } }
    end
    s.lakitu_data = g.actor_data and g.actor_data("lakitu")
    s.phase, s.wf, s.t = "wave", 0.0, 0.0
    log("ending: all of them waving")
    return true
end

local function end_wave(s)
    if s.wpeach and s.wpeach.inst then lib.destroy(s.wpeach.inst.actor) end
    s.wpeach = nil
    for _, T in ipairs(s.wtoads or {}) do if T.inst then lib.destroy(T.inst.actor) end end
    s.wtoads = nil
    if s.lakitu and s.lakitu.actor then lib.destroy(s.lakitu.actor) end
    s.lakitu = nil
    if s.wave_posed then wave_pose(false); s.wave_posed = false end
end

local function wave_frame(s, dt)
    local W = s.ep.wave
    local f0 = s.wf
    s.wf = s.wf + dt * 30.0
    local f = s.wf
    local steps = floor(f) - floor(f0)
    -- him: landed, his controls off, into his wave
    if not s.wave_posed then s.wave_posed = true end
    -- them
    for _ = 1, steps do
        if s.wpeach then anim_step(s.wpeach.a, s.wpeach.inst, nil) end
        for _, T in ipairs(s.wtoads) do anim_step(T.a, T.inst, nil) end
    end
    if s.wpeach then place(s.wpeach.inst, s.wpeach.a, s.wpeach.x, s.wpeach.y, s.wpeach.z) end
    for _, T in ipairs(s.wtoads) do place(T.inst, T.a, T.x, T.y, T.z) end
    -- the camera, drawing back
    local cam = W.cam
    local n = #cam // 7
    local c = max(0.0, min(n - 1.0, f))
    local i = floor(c)
    local j = min(i + 1, n - 1)
    local t = c - i
    local function C(k) local a, b = cam[i * 7 + k], cam[j * 7 + k]; return a + (b - a) * t end
    local px, py, pz = sm(C(1), C(2), C(3))
    local fx, fy, fz = sm(C(4), C(5), C(6))
    s.cam_at = { px, py, pz }
    set_camera(s, px, py, pz, fx, fy, fz, C(7))
    -- Lakitu, from his frame on
    local L0 = W.lakitu0 or -1
    local nl = #(W.lakitu or {}) // 5
    if L0 >= 0 and f >= L0 and s.lakitu_data then
        local k = min(nl - 1.0, f - L0)
        local ki = floor(k)
        local kj = min(ki + 1, nl - 1)
        local kt = k - ki
        local w = W.lakitu
        local function Lw(m) local a, b = w[ki * 5 + m], w[kj * 5 + m]; return a + (b - a) * kt end
        local x, y, z = sm(Lw(1), Lw(2), Lw(3))
        if not s.lakitu then
            s.lakitu = lib.make_instance(lib.world(), s.lakitu_data, { X = x + OFFSET.X, Y = y + OFFSET.Y, Z = z + OFFSET.Z }, 0.0, 1.0)
            if s.lakitu then s.lakitu.moves = true end
        end
        if s.lakitu then
            local K = 360.0 / 65536.0
            local fp, fyaw = w[ki * 5 + 4], w[ki * 5 + 5]
            pcall(function() lib.pose(s.lakitu, s.lakitu.data.anims[1], f - L0) end)
            pcall(function()
                s.lakitu.actor:K2_SetActorLocationAndRotation({ X = x + OFFSET.X, Y = y + OFFSET.Y, Z = z + OFFSET.Z },
                    { Pitch = fp * K, Yaw = -fyaw * K, Roll = 0.0 }, false, {}, true)
            end)
        end
    end
    -- in from the credits' black over 20 frames; out to black over its last 60
    local black = max(0.0, 1.0 - f / FADE_FRAMES)
    if f >= (W.fade or 300) then black = min(1.0, (f - (W.fade or 300)) / ((W.frames or 360) - (W.fade or 300))) end
    show(s.ui.black, black)
    return f >= (W.frames or 360)
end

-- ------------------------------------------------------------ the end
local function release(s)
    local pc, pawn = lib.controller(), lib.pawn()
    walk_stop(s)
    if s.mfade and MUSIC and MUSIC.set_volume then pcall(MUSIC.set_volume, s.mfade.base); s.mfade = nil end
    if s.cake_music and MUSIC and MUSIC.set_volume then pcall(MUSIC.set_volume, s.cake_music) end
    pcall(end_peach_scene, s)
    pcall(end_wave, s)
    pcall(wing_cap, false)
    pcall(slot_anim, nil)
    pcall(end_outro, s)
    if s.ui then pcall(function() s.ui.widget:RemoveFromParent() end) end
    local g = G()
    if g then g.act_override, g.music_override, g.cutscene = nil, nil, nil end
    if pawn then
        pcall(function() pawn:SetActorHiddenInGame(false) end)
        if pc then pcall(function() pawn:EnableInput(pc) end) end
        if pc then pcall(function() pc:SetViewTargetWithBlend(pawn, 0.0, 0, 0.0, false) end) end
        pcall(function() pawn.CharacterMovement:SetMovementMode(1, 0) end)
    end
    local HP = _G.HEALTH
    if HP then HP.grace, HP.hud_off = 0.0, false end
    -- (its camera stays: lib.camera)
end

function E.stop()
    local s = st
    st = nil
    E.ended_at = os.clock()             -- (Start kept from STORROR's menu a moment after: game.lua G.pause_blocked)
    E.active = false
    -- (THE END left, or the credits skipped: the secrets it opened told now - secret_tick)
    if E.secrets_pending then E.secrets_due, E.secrets_pending = E.secrets_pending, nil end
    if _G.HEALTH then _G.HEALTH.grand_time, _G.HEALTH.final_clear = nil, nil end
    -- (STORROR's own HUD back - its score and stamina - as the opening gives it back: the ending took it at its start
    -- and never put it back, "also wheres the storror hud?", 2026-11-04)
    if _G.MENU and _G.MENU.show_game_ui then pcall(_G.MENU.show_game_ui) end
    if not s then return end
    local same = false
    pcall(function() same = lib.world():GetAddress() == s.world end)
    if same then release(s) end
    log("ending: over")
end

-- ------------------------------------------------------------ every frame
-- The skip's way out: the screen to black over SKIP_FADE s, the ending shut and the castle grounds loaded behind it,
-- held black SKIP_BLACK s, then opened over SKIP_OPEN s - "if the player skips cutscene fade to black for 3 seconds then
-- show when back at castle grounds", 2026-11-02. A black of its own over everything (the ending's own screen goes with
-- the ending), kept going by E.tick once the ending is over; him held still under it.
local SKIP_FADE, SKIP_BLACK, SKIP_OPEN = 0.5, 3.0, 0.5
local veil = nil                        -- { widget, img, t }
local function veil_make()
    local pc = lib.controller()
    if not pc then return nil end
    local function cls(p) return StaticFindObject(p) end
    serial = serial + 1
    local n = "SM64EndVeil" .. serial
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName(n))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName(n .. "Tree"))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName(n .. "Canvas"))
    tree.RootWidget = canvas
    local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName(n .. "Img"))
    img:SetColorAndOpacity({ R = 0.0, G = 0.0, B = 0.0, A = 1.0 })
    local slot = canvas:AddChildToCanvas(img)
    slot:SetAnchors({ Minimum = { X = 0.0, Y = 0.0 }, Maximum = { X = 1.0, Y = 1.0 } })
    slot:SetOffsets({ Left = 0.0, Top = 0.0, Right = 0.0, Bottom = 0.0 })
    w:AddToViewport(90)
    return { widget = w, img = img, t = 0.0 }
end
local function veil_tick(dt)
    local v = veil
    if not v then return end
    v.t = v.t + min(dt, 0.1)
    local a = 1.0
    if v.t > SKIP_BLACK then a = max(0.0, 1.0 - (v.t - SKIP_BLACK) / SKIP_OPEN) end
    pcall(function() v.img:SetRenderOpacity(a) end)
    if v.t < SKIP_BLACK then
        local g = G()
        if g and g.freeze and not g.pending then pcall(g.freeze, 0.3) end
    end
    if a <= 0.0 then
        pcall(function() v.widget:RemoveFromParent() end)
        veil = nil
        log("ending: the skip's black lifted")
    end
end

-- out of the ending onto the castle grounds, the file still his, its clock still going: the cake's way out, and the
-- skip's ("after the end credits put the player back at castle grounds", 2026-11-02; it went back to the file select)
local function out_to_grounds()
    E.stop()
    local g = G()
    local okg = g and g.goto_scene and pcall(g.goto_scene, "grounds", nil, {})
    if not okg then
        local MN = _G.MENU
        if MN and MN.back_to_menu then pcall(MN.back_to_menu) end
    end
end

-- (the secrets Final Bowser opened, told once he is back on the castle grounds - the ending and its black gone - one
-- message after another: DIALOG 9014-9017, tools/race_dialogs.py; secrets.lua M.MSG)
local function secret_tick()
    local due = E.secrets_due
    if not (due and due.list and #due.list > 0) or E.active or veil or E.secret_open then return end
    E.secret_at = E.secret_at or (os.clock() + 1.5)
    if os.clock() < E.secret_at then return end
    local g = G()
    if not g or g.pending or g.warping or g.dying or g.cutscene then return end
    local name = table.remove(due.list, 1)
    if #due.list == 0 then E.secrets_due = nil end
    E.secret_at = os.clock() + 0.6
    local okS, SE = pcall(require, "secrets")
    local id = okS and SE and SE.msg_for and SE.msg_for(name, due.human, due.iron)
    if id and g.say then
        E.secret_open = true
        local shown = false
        pcall(function() shown = g.say(id, function() E.secret_open = nil end) end)
        if not shown then E.secret_open = nil end
    end
    log("ending: the secret told - %s", tostring(name))
end
function E.tick(dt)
    if veil then veil_tick(dt) end
    pcall(secret_tick)
    local s = st
    if not (s and E.active) then return end
    local world = lib.world()
    if not world or world:GetAddress() ~= s.world then
        st, E.active = nil, false
        return
    end
    dt = min(dt, 0.1)
    s.t = s.t + dt
    keep_safe()
    keep_animating(s)
    fade_music_tick(s, dt)
    -- (skipped: the screen going to black, the music down with it; then out under the black)
    if s.skip_out then
        s.skip_out = s.skip_out + dt
        show(s.ui.black, min(1.0, s.skip_out / SKIP_FADE))
        show(s.ui.skip, 0.0)
        if s.skip_out >= SKIP_FADE then
            veil = veil_make()
            if veil then pcall(function() veil.img:SetRenderOpacity(1.0) end) end
            out_to_grounds()
        end
        return
    end
    -- Skipped from the start of Peach's words on, through the credits and the cake: Start held SKIP_HOLD s, the prompt
    -- at the bottom right meanwhile, brighter as it is held - "I also want a way to skip in ending. from the start of
    -- peaches speech by holding start. add something at the bottom right to notify the player they can skip the
    -- cutscene", 2026-11-02. (Start opens no menu in the ending: game.lua G.pause_blocked)
    do
        local can = (s.phase == "peach" and (s.pf or 0) >= P.talk) or s.phase == "credits" or s.phase == "wave"
            or s.phase == "cake"
        if can then
            if pad.down("start") then s.skip_t = (s.skip_t or 0.0) + dt else s.skip_t = 0.0 end
            show(s.ui.skip, 0.7 + 0.3 * min(1.0, s.skip_t / SKIP_HOLD))
            if s.skip_t >= SKIP_HOLD then
                log("ending: skipped (%s)", s.phase)
                s.skip_out = 0.0
                fade_music(s, SKIP_FADE)
                return
            end
        else
            s.skip_t = 0.0
            show(s.ui.skip, 0.0)
        end
    end
    if s.phase == "peach" or s.phase == "credits" then
        -- (a trail in the log of the moves he makes, kept through a crash: two crashes came while he was played in
        -- a cutscene, and this says which move it was if it happens again)
        pcall(function()
            local pawn = lib.pawn()
            local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
            local name = "none"
            pcall(function() if m and m:IsValid() then name = m:GetFName():ToString() end end)
            local mode = pawn.CharacterMovement.MovementMode
            local key = name .. "|" .. tostring(mode)
            if key ~= s.trail then
                s.trail = key
                log("ending: athlete %s, movement mode %s (%s %s)", name, tostring(mode), s.phase, tostring(s.shot or ""))
            end
        end)
    end
    if s.phase == "peach" or s.phase == "credits" then align_controls(s) end
    -- (held where he stands through the credits and the waving: put back there every half second - load_shot, held_at)
    if s.phase == "credits" and s.held and s.held.free then
        -- (free in the shot: back on his spot only if he fell far, was thrown up or flung, or ran off out of it)
        s.held.t = s.held.t + dt
        if s.held.t >= 0.25 then
            s.held.t = 0.0
            local a, CF = s.held.at, CREDITS_FREE
            local l, v = nil, nil
            pcall(function() local pw = lib.pawn(); l, v = pw:K2_GetActorLocation(), pw:GetVelocity() end)
            if l then
                local dx, dy, dz = l.X - OFFSET.X - a[1], l.Y - OFFSET.Y - a[2], l.Z - OFFSET.Z - 92.0 - a[3]
                local why = nil
                if dz < -CF.below then why = "fallen" elseif dz > CF.above then why = "up high"
                elseif dx * dx + dy * dy > CF.away * CF.away then why = "far off"
                elseif v and (v.Z > CF.up or v.X * v.X + v.Y * v.Y > CF.fling * CF.fling) then why = "flung" end
                if why then
                    log("ending: credits - he was %s; back on his spot", why)
                    stand_athlete(a, s.held.yaw)
                end
            end
        end
    elseif (s.phase == "credits" or s.phase == "wave") and s.held then
        s.held.t = s.held.t + dt
        if s.held.t >= 0.5 then
            s.held.t = 0.0
            local a = s.held.at
            hold_athlete({ a[1], a[2], a[3] }, s.held.yaw, false)
        end
    end
    if s.phase == "outro" then
        local ok, r = pcall(outro_frame, s, dt)
        if not ok then log("ending: the outro: %s", tostring(r)) end
        if not ok or r then
            end_outro(s)
            local g = G()
            if g then g.music_override = "event_ending" end
            if not start_peach_scene(s) then s.phase, s.pf = "peach", P.done end
        end
    elseif s.phase == "peach" then
        local done = true
        if s.pf < P.done then
            local ok, r = pcall(peach_frame, s, dt)
            if not ok then log("ending: Peach's scene: %s", tostring(r)) else done = r end
        end
        if done then
            end_peach_scene(s)
            s.phase, s.t = "credits", 0.0
            local g = G()
            if g then g.music_override = "event_credits" end
            fade_cancel(s)
            if MUSIC then pcall(MUSIC.play, "event_credits", true) end
            show(s.ui.black, 1.0)
            if not load_shot(s, 1) then s.phase = "cake"; s.t = 0.0 end
        end
    elseif s.phase == "credits" then
        if credits_frame(s, dt) then
            if s.shot < #s.data.shots then
                if not load_shot(s, s.shot + 1) then s.shot = s.shot + 1 end
            elseif not start_wave(s) then
                s.phase, s.t = "cake", 0.0
                for _, b in ipairs(s.ui.bars) do show(b.img, 0.0) end
                for _, p in ipairs(s.ui.pages) do show(p, 0.0) end
                show(s.ui.cake_back, 1.0)
                show(s.ui.black, 0.0)
                hold_athlete(s.data.shots[#s.data.shots].at, 0.0, false)     -- (the cake covers him)
            end
        end
    elseif s.phase == "wave" then
        local ok, r = pcall(wave_frame, s, dt)
        if not ok then log("ending: the waving: %s", tostring(r)) end
        if not ok or r then
            end_wave(s)
            s.phase, s.t = "cake", 0.0
            show(s.ui.cake_back, 1.0)
            show(s.ui.black, 0.0)
            if s.wave_at then hold_athlete(s.wave_at, 180.0, false) end     -- (the cake covers him)
        end
    elseif s.phase == "cake" then
        -- (levels/ending: 60 frames, then the cake fades in from black over 75; the voice 120 frames later)
        show(s.ui.cake_back, 1.0)
        show(s.ui.cake, min(1.0, max(0.0, (s.t - 2.0) / 2.5)))
        -- (the tune dies away as the cake comes up, and stops)
        if MUSIC and MUSIC.set_volume and not s.music_off then
            s.cake_music = s.cake_music or MUSIC.volume
            local k = max(0.0, 1.0 - s.t / 9.0)
            pcall(MUSIC.set_volume, s.cake_music * k)
            if k <= 0.0 then
                s.music_off = true
                pcall(MUSIC.play, nil)
                pcall(MUSIC.set_volume, s.cake_music)
            end
        end
        if s.t >= CAKE_VOICE and not s.voiced then
            s.voiced = true
            sfx("thank_you", 1.0)
        end
        -- (left by A or Start the skip's way: to black, held, then the castle grounds - "no fade to black on THE END
        -- screen when pressing a to leave", 2026-11-02)
        if s.t > CAKE_VOICE + 3.0 and (pad.pressed("ok") or pad.pressed("start")) then
            log("ending: THE END left")
            s.skip_out = 0.0
            fade_music(s, SKIP_FADE)
        end
    end
end

function E.state() return st end           -- (tests)
function E.skip_to(phase, shot)             -- (tests)
    local s = st
    if not s then return "not on" end
    s.t = 0.0
    if phase == "peach" then
        start_peach_scene(s)
    elseif phase == "wave" then
        if s.phase == "peach" then pcall(end_peach_scene, s) end
        start_wave(s)
    elseif phase == "credits" then
        s.phase = "credits"
        show(s.ui.white, 0.0)
        local g = G()
        if g then g.music_override = "event_credits" end
        load_shot(s, shot or 1)
    else
        s.phase = phase
    end
    return s.phase
end

return E
