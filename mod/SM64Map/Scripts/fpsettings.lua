-- STORROR First Person: the mod's rows on STORROR's Camera pages - the FIRST PERSON switch (once on Settings > Camera too), and on
-- the FIRST PERSON tab's page (fpmenu.lua) that switch and the tab's settings under it (fpconfig.lua: "start adding all
-- of our new settings", 2026-11-09).
--
-- The Camera page (SPPCameraSettingsWidgetBP) is a column of rows: sliders and switches. Ours are rows of the same kind as
-- its sliders (HITSSliderWidget, made from its CAMERA SHAKE row), put in under its last [PLAYER] row (CAMERA INVERT Y),
-- each under the one before.
--
-- Sliders: the row's own slider, set to our range and step; its bar of dots lit to the value; its number our own text,
-- written as the setting reads (a copy of the row's number put in its place: STORROR writes its rows' numbers itself,
-- as percentages). Moved by the player, the setting is set (and kept on disk a moment after it stops); the camera reads
-- it every frame.
--
-- Switches: what the player does to a switch never reaches a mod: the game fills its switches' choices and handles their
-- presses in its own code, and the menu keeps the pad and the keys to itself (tried every way, 2026-10-22: a switch of
-- the game's left empty did nothing, no call of any row could be caught, no key reached the game). A slider's value can
-- be read, though. So a switch of ours is a slider, two steps, its dotted bar and its number not shown, the slider itself
-- unseen but there to be moved - left/right on the pad or the keys - and over it a switch drawn from copies of CAMERA
-- INVERT Y's pieces, thumb along the track as the game's own sit (40.5 across when on). A click on the switch drawn
-- flips it too: an unseen button over it, watched every frame. ("make it a real switch", 2026-10-22.)
local lib = require("lib")
local log = lib.log
local M = {}

local function cfg() return _G.FP_CFG end

-- a distance in cm, signed (0 as is)
local function cm_text(v) return v == 0 and "0 CM" or string.format("%+d CM", v) end

-- (a switch row and a percent row, for the many alike)
local function switch_row(label, key)
    return { label = label, ours = true, switch = true,
             get = function() local C = cfg(); return C and C.num(key) >= 0.5 or false end,
             set = function(on) local C = cfg(); if C then C.set(key, on and 1 or 0) end end }
end
local function pct_row(label, key, min, max, step)
    return { label = label, ours = true, key = key, min = min or 0, max = max or 100, step = step or 5,
             text = function(v) return string.format("%d%%", v) end }
end
local function named(names) return function(v) return names[math.floor(v + 0.5)] or tostring(v) end end
local COLOR_NAMES = { [0] = "WHITE", "GREEN", "RED", "YELLOW", "CYAN", "MAGENTA" }
local SHAPE_NAMES = { [0] = "DOT", "CROSS", "DOT + CROSS" }
local SPEEDO_NAMES = { [0] = "OFF", "KM/H", "MPH" }

-- RANDOM, the last preset: every setting picked at random each time it is moved to (made below, after the rows)
local randomize = nil

-- the rows, in order. `ours`: on the FIRST PERSON tab's page only (else on every Camera page). Sliders: their setting
-- (fpconfig.lua's key), range, step, and how the number reads.
local ROWS = {
    -- (in groups, under headings of STORROR's own kind - "organize the settings", then "also organize again" once
    -- many more were added, 2026-11-09: the look, its effects, the head, the rubberband, the camera's place, the
    -- screen, the controls, the body, and when all of him is hidden)
    { label = "[PRESETS]", header = true, ours = true },
    -- (moved: that preset put on - every setting under it - "add all of it", 2026-11-09; fpconfig.lua's PRESETS)
    { label = "PRESET", ours = true, key = "preset", min = 0, max = 11, step = 1,
      text = function(v) local C = cfg(); return (C and C.PRESET_NAMES[math.floor(v + 0.5)]) or tostring(v) end,
      apply = function(v)
          local C = cfg(); if not C then return end
          local n = math.floor(v + 0.5)
          if n == C.RANDOM and randomize then randomize() else C.apply_preset(n) end
      end },
    { label = "[VIEW]", header = true, ours = true },
    -- (on the FIRST PERSON tab only - on SETTINGS > CAMERA too until "you can also remove first person in settings camera",
    -- 2026-11-10)
    -- (not in the Super Mario 64 mashup - `standalone`: there a file is first person for good)
    { label = "FIRST PERSON", ours = true, switch = true, standalone = true,
      get = function() return _G.FP_SETTING and _G.FP_SETTING.get() or false end,
      set = function(on) if _G.FP_SETTING then _G.FP_SETTING.set(on) end end },
    -- (up to 179: "make field of view go up to 200", 2026-11-09 - a flat picture cannot show 180 or more, its sides
    -- stretched out to nothing; past 180 it turns inside out)
    { label = "FIELD OF VIEW", ours = true, key = "fov", min = 60, max = 179, step = 1,
      text = function(v) return string.format("%d", v) end },
    -- (below 0 the fisheye the other way round - "widen pov should also be able to go negative", 2026-11-09)
    { label = "WIDEN POV", ours = true, key = "widen", min = -100, max = 100, step = 5,
      text = function(v) return string.format("%d%%", v) end },
    -- (LOCK HEAD UP - the view kept upright through flips - was here; taken out: "remove lock head up", 2026-11-09)
    -- (the drone's fisheye, as the drone has it, on the first-person view - "also add an option for the drone fisheye",
    -- 2026-11-09; fp.lua's DRONE_FISH)
    { label = "DRONE FISHEYE", ours = true, switch = true,
      get = function() local C = cfg(); return C and C.num("drone_fish") >= 0.5 or false end,
      -- (turned on: FIELD OF VIEW and WIDEN POV put at the drone camera's, 100 and 50 - the player's to change from there,
      -- "should still be able to mess with drone fisheyes fov and other settings", 2026-11-09)
      set = function(on)
          local C = cfg(); if not C then return end
          C.set("drone_fish", on and 1 or 0)
          if on then C.set("fov", 100); C.set("widen", 50) end
      end },
    { label = "NEAR CLIP", ours = true, key = "near_clip", min = 1, max = 20, step = 1,
      text = function(v) return string.format("%d CM", v) end },
    -- (a light from the eyes; L too - "flashlight", 2026-11-09)
    switch_row("FLASHLIGHT", "flashlight"),
    pct_row("FLASHLIGHT BRIGHTNESS", "flash_bright"),
    { label = "[EFFECTS]", header = true, ours = true },
    -- (the view wider the faster he runs: fp.lua's SPEED FOV - "Speed FOV", 2026-11-09)
    { label = "SPEED FOV", ours = true, key = "speed_fov", min = 0, max = 100, step = 5,
      text = function(v) return string.format("%d%%", v) end },
    pct_row("SPEED EFFECTS", "speed_fx"),
    pct_row("MOTION BLUR", "motion_blur"),
    pct_row("JUMP FOV KICK", "jump_kick"),
    -- (the feel of moving: fp.lua's LANDING IMPACT and on)
    { label = "LANDING IMPACT", ours = true, key = "impact", min = 0, max = 100, step = 5,
      text = function(v) return string.format("%d%%", v) end },
    { label = "LEAN", ours = true, key = "lean", min = 0, max = 100, step = 5,
      text = function(v) return string.format("%d%%", v) end },
    pct_row("WALL RUN TILT", "wall_tilt"),
    pct_row("BREATHING", "breathing"),
    -- (to 200%: "can you make look down in air go to 200% and sprint hands go to 200%", 2026-11-10)
    { label = "LOOK DOWN IN AIR", ours = true, key = "air_look", min = 0, max = 300, step = 5,
      text = function(v) return string.format("%d%%", v) end },
    { label = "SPRINT HANDS", ours = true, key = "sprint_hands", min = 0, max = 300, step = 5,
      text = function(v) return string.format("%d%%", v) end },
    pct_row("SPRINT SHAKE", "sprint_shake"),
    { label = "[HEAD]", header = true, ours = true },
    { label = "MOTION", ours = true, key = "motion", min = 0, max = 100, step = 5,
      text = function(v) return string.format("%d%%", v) end },
    { label = "FOLLOW FLIPS", ours = true, switch = true,
      get = function() local C = cfg(); return C and C.num("follow_flips") >= 0.5 or false end,
      set = function(on) local C = cfg(); if C then C.set("follow_flips", on and 1 or 0) end end },
    -- (how much of the look up and down is taken away: 100% keeps the view level - "make the head lock a slider",
    -- 2026-11-09)
    { label = "HEAD LOCK", ours = true, key = "head_lock", min = 0, max = 100, step = 5,
      text = function(v) return string.format("%d%%", v) end },
    pct_row("LOOK SMOOTHING", "look_smooth"),
    { label = "[RUBBERBAND]", header = true, ours = true },
    -- (the head pulled back to where his body faces: X left/right, Y up/down, STRENGTH how fast - "next rubberbanding on
    -- the x and y axis also add a slider for rubberbanding strength", 2026-11-09. The first RUBBERBANDING - how loosely
    -- the camera trails him - has no row now; its setting stays as it was left.)
    { label = "RUBBERBAND X", ours = true, key = "rb_x", min = 0, max = 100, step = 5,
      text = function(v) return string.format("%d%%", v) end },
    { label = "RUBBERBAND Y", ours = true, key = "rb_y", min = 0, max = 100, step = 5,
      text = function(v) return string.format("%d%%", v) end },
    { label = "RUBBERBAND STRENGTH", ours = true, key = "rb_strength", min = 0, max = 100, step = 5,
      text = function(v) return string.format("%d%%", v) end },
    { label = "RUBBERBAND CENTER SPEED", ours = true, key = "rb_center", min = 0, max = 100, step = 5,
      text = function(v) return string.format("%d%%", v) end },
    { label = "RUBBERBAND CENTER DELAY", ours = true, switch = true,
      get = function() local C = cfg(); return C and C.num("rb_delay") >= 0.5 or false end,
      set = function(on) local C = cfg(); if C then C.set("rb_delay", on and 1 or 0) end end },
    { label = "[CAMERA POSITION]", header = true, ours = true },
    -- (the camera moved from his eyes: X forward, Y right, Z up; up to 100 cm each way - "allow for up to 100 cm of xyz
    -- positioning", 2026-11-09)
    { label = "CAMERA X", ours = true, key = "cam_x", min = -100, max = 100, step = 1,
      text = cm_text },
    { label = "CAMERA Y", ours = true, key = "cam_y", min = -100, max = 100, step = 1,
      text = cm_text },
    { label = "CAMERA Z", ours = true, key = "cam_z", min = -100, max = 100, step = 1,
      text = cm_text },
    { label = "[HUD]", header = true, ours = true },
    -- (on the screen in first person: fphud.lua)
    { label = "CROSSHAIR DOT", ours = true, switch = true,
      get = function() local C = cfg(); return C and C.num("crosshair") >= 0.5 or false end,
      set = function(on) local C = cfg(); if C then C.set("crosshair", on and 1 or 0) end end },
    -- ("all of it", 2026-11-09, from a list: the crosshair's look, a speedometer, speed effects, motion blur, a kick of
    -- the field of view on jumps, how near the eyes the picture starts)
    { label = "CROSSHAIR SIZE", ours = true, key = "cross_size", min = 2, max = 24, step = 1,
      text = function(v) return string.format("%d PX", v) end },
    { label = "CROSSHAIR COLOR", ours = true, key = "cross_color", min = 0, max = 5, step = 1, text = named(COLOR_NAMES) },
    { label = "CROSSHAIR SHAPE", ours = true, key = "cross_shape", min = 0, max = 2, step = 1, text = named(SHAPE_NAMES) },
    { label = "SPEEDOMETER", ours = true, key = "speedo", min = 0, max = 2, step = 1, text = named(SPEEDO_NAMES) },
    pct_row("CINEMATIC BARS", "bars"),
    { label = "HIDE HUD", ours = true, switch = true,
      get = function() local C = cfg(); return C and C.num("hide_hud") >= 0.5 or false end,
      set = function(on) local C = cfg(); if C then C.set("hide_hud", on and 1 or 0) end end },
    { label = "[CONTROLS]", header = true, ours = true },
    -- (how fast the stick turns the view, left/right and up/down: 100% STORROR's own - "next add sensitity slider for
    -- joystick turn rate", 2026-11-09; fp.lua's stick_rate)
    { label = "STICK TURN RATE", ours = true, key = "stick_rate", min = 10, max = 300, step = 5,
      text = function(v) return string.format("%d%%", v) end },
    pct_row("LOOK UP/DOWN SPEED", "pitch_rate", 10, 300, 5),
    switch_row("INVERT LOOK UP/DOWN", "invert_y"),
    -- (on: the left stick turns him to run the way it is pushed, as STORROR does; off: he keeps facing where the view looks
    -- and the stick moves him sideways and back - "add an option for left joystick steers body", 2026-11-09)
    { label = "RIGHT STICK TURNS BODY", ours = true, switch = true,
      get = function() local C = cfg(); return C and C.num("rstick_body") >= 0.5 or false end,
      set = function(on) local C = cfg(); if C then C.set("rstick_body", on and 1 or 0) end end },
    { label = "LEFT STICK STEERS", ours = true, switch = true,
      get = function() local C = cfg(); return C and C.num("left_steers") >= 0.5 or false end,
      set = function(on) local C = cfg(); if C then C.set("left_steers", on and 1 or 0) end end },
    -- (PULL BACK TO STAND STILL was here: "instead of stopping the player by pulling back on the stick just make the
    -- turning cone way bigger", 2026-11-10 - fp.lua's TURN CONE)
    -- (F5, or both sticks clicked together; fpkeys.lua. QUICK TURN was here: "remove the quick turn", 2026-11-09)
    (function() local r = switch_row("FIRST/THIRD PERSON BUTTON", "view_key"); r.standalone = true; return r end)(),
    switch_row("THIRD PERSON IN BAILS", "bail_third"),
    { label = "[BODY]", header = true, ours = true },
    -- (his head, and his hair, brows and beard with it: hidden as it always was, unless set off)
    { label = "HIDE HEAD", ours = true, switch = true,
      get = function() local C = cfg(); return C and C.num("hide_head") >= 0.5 or false end,
      set = function(on) local C = cfg(); if C then C.set("hide_head", on and 1 or 0) end end },
    -- (each of his parts hidden from the player's own view - fp.lua's PART_SWITCHES)
    -- (his arms and his stomach each on its own - one piece in STORROR's mesh, parted by fp.lua's SKIN COPY: "make it
    -- seperate", 2026-11-09)
    { label = "HIDE ARMS", ours = true, switch = true,
      get = function() local C = cfg(); return C and C.num("hide_arms") >= 0.5 or false end,
      set = function(on) local C = cfg(); if C then C.set("hide_arms", on and 1 or 0) end end },
    { label = "HIDE STOMACH", ours = true, switch = true,
      get = function() local C = cfg(); return C and C.num("hide_stomach") >= 0.5 or false end,
      set = function(on) local C = cfg(); if C then C.set("hide_stomach", on and 1 or 0) end end },
    { label = "HIDE SHIRT", ours = true, switch = true,
      get = function() local C = cfg(); return C and C.num("hide_shirt") >= 0.5 or false end,
      set = function(on) local C = cfg(); if C then C.set("hide_shirt", on and 1 or 0) end end },
    { label = "HIDE PANTS", ours = true, switch = true,
      get = function() local C = cfg(); return C and C.num("hide_pants") >= 0.5 or false end,
      set = function(on) local C = cfg(); if C then C.set("hide_pants", on and 1 or 0) end end },
    { label = "HIDE SHOES", ours = true, switch = true,
      get = function() local C = cfg(); return C and C.num("hide_shoes") >= 0.5 or false end,
      set = function(on) local C = cfg(); if C then C.set("hide_shoes", on and 1 or 0) end end },
    { label = "[HIDE WHEN]", header = true, ours = true },
    -- (all of him gone while he flips in the air, or rolls, whatever the switches above say - "body parts to dissappear
    -- when flipping. So you can have all the body parts but when you flip they disappear", and "for front roll to just
    -- turn off the body completely", 2026-11-09)
    { label = "HIDE BODY IN FLIPS", ours = true, switch = true,
      get = function() local C = cfg(); return C and C.num("flip_hide") >= 0.5 or false end,
      set = function(on) local C = cfg(); if C then C.set("flip_hide", on and 1 or 0) end end },
    { label = "HIDE BODY IN ROLLS", ours = true, switch = true,
      get = function() local C = cfg(); return C and C.num("roll_hide") >= 0.5 or false end,
      set = function(on) local C = cfg(); if C then C.set("roll_hide", on and 1 or 0) end end },
    -- ("also add a toggle for invis when vaulting", 2026-11-09)
    { label = "HIDE BODY IN VAULTS", ours = true, switch = true,
      get = function() local C = cfg(); return C and C.num("vault_hide") >= 0.5 or false end,
      set = function(on) local C = cfg(); if C then C.set("vault_hide", on and 1 or 0) end end },
    -- ("add a go invisable when running toggle", 2026-11-09)
    { label = "HIDE BODY WHEN RUNNING", ours = true, switch = true,
      get = function() local C = cfg(); return C and C.num("run_hide") >= 0.5 or false end,
      set = function(on) local C = cfg(); if C then C.set("run_hide", on and 1 or 0) end end },
    -- ("and standing", 2026-11-09)
    { label = "HIDE BODY WHEN STANDING", ours = true, switch = true,
      get = function() local C = cfg(); return C and C.num("stand_hide") >= 0.5 or false end,
      set = function(on) local C = cfg(); if C then C.set("stand_hide", on and 1 or 0) end end },
    { label = "[HELP]", header = true, ours = true },
    -- (on: a panel with every setting and what it does - fphelp.lua; off, or the tab left, it shuts - "make one more
    -- button all the way at the bottom, this button will pull up a dialog explaining exactly what each setting does",
    -- 2026-11-09)
    { label = "WHAT EACH SETTING DOES", ours = true, switch = true,
      get = function() return _G.FP_HELP and _G.FP_HELP.open or false end,
      set = function(on) if _G.FP_HELP then _G.FP_HELP.set_open(on) end end },
}

-- RANDOM: every switch flipped a coin, every slider anywhere on its own range at its own steps - all but FIRST PERSON,
-- PRESET itself and the help; DRONE FISHEYE's own setting alone (its switch would put FIELD OF VIEW and WIDEN POV back)
randomize = function()
    local C = cfg(); if not C then return end
    local SKIP = { ["FIRST PERSON"] = true, ["PRESET"] = true, ["WHAT EACH SETTING DOES"] = true, ["DRONE FISHEYE"] = true }
    for _, spec in ipairs(ROWS) do
        if not spec.header and not SKIP[spec.label] and not (spec.standalone and _G.FP_MASHUP) then
            if spec.switch then
                pcall(spec.set, math.random() < 0.5)
            elseif spec.key then
                local n = math.floor((spec.max - spec.min) / spec.step + 0.5)
                C.set(spec.key, spec.min + math.random(0, n) * spec.step)
            end
        end
    end
    C.set("drone_fish", math.random() < 0.5 and 1 or 0)
    log("settings: RANDOM - every setting picked at random")
end

local THUMB_ON = 40.5                   -- how far the game's own switches put the thumb along when on
local HOLD = 0.6                        -- seconds a flip is held against the slider springing back
local OPEN_HOLD = 0.4                   -- seconds a new row is held at its setting as the page fills
local look_t, poll_t = 0.0, 0.0
local tried = {}                        -- pages a row was tried on, by page and label (one try each)
local rows = {}                         -- our rows, by address: { spec, g = the switch drawn (true till drawn), tv = own text }
local errored = false

local PANEL = StaticFindObject("/Script/UMG.PanelWidget")

local function alive(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

-- a widget of the page by name (its variable)
local function part(page, name)
    local w = nil
    pcall(function() w = page[name] end)
    if alive(w) then return w end
    return nil
end

-- ours titled `label` in that page's column, or nil
local function ours(box, label)
    local found = nil
    pcall(function()
        for i = 0, box:GetChildrenCount() - 1 do
            local c = box:GetChildAt(i)
            if alive(c) then
                local r = rows[c:GetAddress()]
                if r and r.spec.label == label then found = c end
            end
        end
    end)
    return found
end

-- the page is the FIRST PERSON tab's (fpmenu.lua's)
local function is_tab_page(page)
    local MENU = package.loaded["fpmenu"]
    if not (MENU and MENU.our_page) then return false end
    local yes = false
    pcall(function()
        local addr = page:GetAddress()
        for _, bar in ipairs(FindAllOf("PauseMenuTabBarBP_C") or {}) do
            local p = bar:IsValid() and MENU.our_page(bar) or nil
            if p and p:GetAddress() == addr then yes = true end
        end
    end)
    return yes
end

-- the panel holding `child` in the row's widgets, found by walking down from the row's root
local function holder(row, child)
    local want = child:GetAddress()
    local found = nil
    local function walk(w, depth)
        if found or depth > 10 or not alive(w) or not w:IsA(PANEL) then return end
        local n = 0
        pcall(function() n = w:GetChildrenCount() end)
        for i = 0, n - 1 do
            local c = nil
            pcall(function() c = w:GetChildAt(i) end)
            if alive(c) then
                if c:GetAddress() == want then found = w; return end
                walk(c, depth + 1)
            end
        end
    end
    local root = nil
    pcall(function() root = row.WidgetTree.RootWidget end)
    walk(root, 0)
    return found
end

-- the switch drawn over the row's unseen slider, from copies of CAMERA INVERT Y's pieces (once the game has built
-- that one's: it does when the page is first shown). Nothing of CAMERA INVERT Y's is moved or emptied.
local function build_graphic(row, real)
    if not (alive(real.ToggleTrack) and alive(real.ToggleThumb)) then return nil end
    local ov = holder(row, row.Slider)
    if not (ov and ov:GetClass():GetFName():ToString() == "Overlay") then
        log("settings: no place for the switch over the slider (%s)", ov and ov:GetClass():GetFName():ToString() or "none")
        return "failed"
    end
    local tree = row.WidgetTree
    local function copy(src) return StaticConstructObject(src:GetClass(), tree, FName("None"), 0, 0, false, false, src) end
    local function fresh(path) return StaticConstructObject(StaticFindObject(path), tree, FName("None"), 0, 0, false, false, nil) end
    local function slot_like(dst, src)
        pcall(function() dst:SetPadding(src.Padding) end)
        pcall(function() dst:SetHorizontalAlignment(src.HorizontalAlignment) end)
        pcall(function() dst:SetVerticalAlignment(src.VerticalAlignment) end)
    end
    local g = {}
    local w, h = real.Toggle_TrackWidth or 67.0, real.Toggle_TrackHeight or 32.0
    g.outer = fresh("/Script/UMG.SizeBox")
    g.outer:SetWidthOverride(w)
    g.outer:SetHeightOverride(h)
    local inner = fresh("/Script/UMG.Overlay")
    g.track = copy(real.ToggleTrack)
    g.on_l = copy(real.ToggleLabelOn)
    g.off_l = copy(real.ToggleLabelOff)
    g.tbox = fresh("/Script/UMG.SizeBox")
    g.tbox:SetWidthOverride(real.Toggle_ThumbSize or 21.0)
    g.tbox:SetHeightOverride(real.Toggle_ThumbSize or 21.0)
    g.thumb = copy(real.ToggleThumb)
    -- (an unseen button over it all: a click on the switch drawn)
    g.button = fresh("/Script/UMG.Button")
    local s
    s = inner:AddChildToOverlay(g.track); slot_like(s, real.ToggleTrack.Slot)
    s = inner:AddChildToOverlay(g.on_l); slot_like(s, real.ToggleLabelOn.Slot)
    s = inner:AddChildToOverlay(g.off_l); slot_like(s, real.ToggleLabelOff.Slot)
    s = inner:AddChildToOverlay(g.tbox); slot_like(s, real.ThumbSizeBox.Slot)
    g.tbox:AddChild(g.thumb)
    s = inner:AddChildToOverlay(g.button)
    pcall(function() s:SetHorizontalAlignment(0); s:SetVerticalAlignment(0) end)        -- (the whole switch)
    pcall(function() g.button:SetRenderOpacity(0.0) end)
    g.outer:AddChild(inner)
    -- (where it goes: beside the slider's ScaleBox, not in it. The ScaleBox fits what it holds to the row's height, so a
    -- switch put in with the slider came out about a third of its size - "tiny white boxes", 2026-11-09. Its SizeBox
    -- gets an overlay of ours holding the ScaleBox, as it sat, and the switch over it, in the row's own units.)
    local place = ov
    pcall(function()
        local sb = ov:GetParent()
        if not (alive(sb) and sb:GetClass():GetFName():ToString() == "ScaleBox") then return end
        local sz = sb:GetParent()
        if not (alive(sz) and sz:GetClass():GetFName():ToString() == "SizeBox") then return end
        local pad, ha, va = nil, 0, 0
        local sl = sb.Slot
        if alive(sl) then
            local P = sl.Padding
            pad = { Left = P.Left, Top = P.Top, Right = P.Right, Bottom = P.Bottom }
            ha, va = sl.HorizontalAlignment, sl.VerticalAlignment
        end
        local wrap = fresh("/Script/UMG.Overlay")
        if not alive(wrap) then return end
        sz:SetContent(wrap)                                   -- (the ScaleBox comes out of the SizeBox here...)
        local ss = wrap:AddChildToOverlay(sb)                 -- (...and goes straight into ours, placed as it was)
        if alive(ss) then
            if pad then pcall(function() ss:SetPadding(pad) end) end
            pcall(function() ss:SetHorizontalAlignment(ha) end)
            pcall(function() ss:SetVerticalAlignment(va) end)
        end
        place = wrap
    end)
    s = place:AddChildToOverlay(g.outer)
    pcall(function() s:SetHorizontalAlignment(1); s:SetVerticalAlignment(2) end)         -- (left, middle, as the game's own sit)
    g.lit, g.plain = real.Toggle_SelectedColor, real.Toggle_NormalColor
    log("settings: %s switch drawn", rows[row:GetAddress()] and rows[row:GetAddress()].spec.label or "?")
    return g
end

-- a switch row shown at `on`: its slider's own look away, the switch drawn at `on`, lit while the row is the one picked
-- (each piece put only when it changes: put every frame on 30-odd switches - their slider hidden, the thumb, four
-- colours - the page cost 6 ms a frame, "extreme lag", 2026-11-09)
local function show_switch(row, on)
    local r = rows[row:GetAddress()]
    if not r then return end
    local g = r.g
    if r.sw_g ~= g then r.sw_g, r.sw_hid, r.sw_on, r.sw_picked = g, nil, nil, nil end
    if not r.sw_hid then
        pcall(function() row.ProgressBar:SetRenderOpacity(0.0) end)
        pcall(function() row.SliderValue:SetRenderOpacity(0.0) end)
        pcall(function() row.Slider:SetRenderOpacity(0.0) end)
        r.sw_hid = true
    end
    if type(g) ~= "table" then return end
    if r.sw_on ~= on then
        pcall(function() g.tbox:SetRenderTranslation({ X = on and THUMB_ON or 0.0, Y = 0.0 }) end)
        r.sw_on = on
    end
    local picked = false
    pcall(function() picked = row:GetSelected() or row:IsHovered() end)
    if r.sw_picked == picked then return end
    r.sw_picked = picked
    local c = picked and g.lit or g.plain
    if c then
        local col = { R = c.R, G = c.G, B = c.B, A = c.A }
        for _, x in ipairs({ g.track, g.thumb }) do pcall(function() x:SetColorAndOpacity(col) end) end
        for _, x in ipairs({ g.on_l, g.off_l }) do pcall(function() x:SetColorAndOpacity({ SpecifiedColor = col, ColorUseRule = 0 }) end) end
    end
end

-- A slider row's number: a text of our own in the place of the row's (a copy of it - same look - put in the number's
-- box): STORROR writes its rows' numbers itself, as percentages, and would write over ours (the Super Mario 64 mashup's
-- MARIO SETTINGS page, 2026-11-01). Falls back to the row's own number.
local function own_text(row)
    local r = rows[row:GetAddress()]
    if r and alive(r.tv) then return r.tv end
    local sv = row.SliderValue
    if not alive(sv) then return nil end
    local box = sv:GetParent()
    if not (alive(box) and box:GetClass():GetFName():ToString() == "SizeBox") then return sv end
    local sl = sv.Slot
    local pad, ha, va = nil, nil, nil
    if alive(sl) then
        local P = sl.Padding
        pad = { Left = P.Left, Top = P.Top, Right = P.Right, Bottom = P.Bottom }
        ha, va = sl.HorizontalAlignment, sl.VerticalAlignment
    end
    local tb = StaticConstructObject(sv:GetClass(), row.WidgetTree, FName("None"), 0, 0, false, false, sv)
    if not alive(tb) then return sv end
    local ns = box:SetContent(tb)
    if alive(ns) and pad then
        pcall(function() ns:SetPadding(pad) end)
        pcall(function() ns:SetHorizontalAlignment(ha) end)
        pcall(function() ns:SetVerticalAlignment(va) end)
    end
    pcall(function() tb:SetVisibility(4) end)                         -- (seen, not hit-tested)
    if r then r.tv = tb end
    return tb
end

-- a slider row shown at `v`: its bar of dots lit to it, its number as the setting reads
local function show_slider(row, spec, v)
    pcall(function() row.ProgressBar.ProgressValue = (v - spec.min) / (spec.max - spec.min) end)
    pcall(function()
        local tv = own_text(row)
        local want = spec.text(v)
        if tv:GetText():ToString() ~= want then tv:SetText(FText(want)) end
    end)
end

local function snap(spec, v)
    v = math.max(spec.min, math.min(spec.max, v))
    return spec.min + math.floor((v - spec.min) / spec.step + 0.5) * spec.step
end

local function slider_setting(spec)
    local C = cfg()
    return snap(spec, C and C.num(spec.key) or spec.min)
end

-- ours among the rows that can be picked (the column's button group: up/down, the mouse over it), after `anchor`
local function enlist(box, row, anchor)
    local g = box.ButtonGroup
    if not alive(g) or g:FindButtonIndex(row) >= 0 then return end
    local mi = g:FindButtonIndex(anchor)
    local after = {}
    if mi >= 0 then
        for i = mi + 1, g:GetButtonCount() - 1 do after[#after + 1] = g:GetButtonBaseAtIndex(i) end
    end
    for _, b in ipairs(after) do g:RemoveWidget(b) end
    g:AddWidget(row)
    for _, b in ipairs(after) do g:AddWidget(b) end
end

-- one row, `spec`, put in straight after `anchor` in the page's column
-- A heading on the FIRST PERSON tab's page ("organize the settings", 2026-11-09): a copy of the page's own heading (its
-- [PLAYER] line, CommonTextBlock_1), our words in it, put in straight after `anchor` as the rows are.
local function add_heading(page, spec, anchor)
    local box = part(page, "VerticalBox")
    if not (box and alive(anchor)) then return nil end
    -- (the page's own heading: the first text line among its column's rows)
    local src = nil
    pcall(function()
        for i = 0, box:GetChildrenCount() - 1 do
            local c = box:GetChildAt(i)
            if not src and alive(c) and c:GetClass():GetFName():ToString():find("TextBlock") and not rows[c:GetAddress()] then src = c end
        end
    end)
    if not src then return nil end
    local t = StaticConstructObject(src:GetClass(), page.WidgetTree, FName("None"), 0, 0, false, false, src)
    if not alive(t) then return nil end
    rows[t:GetAddress()] = { spec = spec, header = true, name = t:GetFName():ToString() }
    pcall(function() t:SetText(FText(spec.label)) end)
    local at = box:GetChildIndex(anchor)
    local after = {}
    for i = at + 1, box:GetChildrenCount() - 1 do after[#after + 1] = box:GetChildAt(i) end
    for _, c in ipairs(after) do box:RemoveChild(c) end
    local slot = box:AddChildToVerticalBox(t)
    for _, c in ipairs(after) do box:AddChildToVerticalBox(c) end
    pcall(function()
        local ss = src.Slot
        slot:SetPadding(ss.Padding)
        slot:SetHorizontalAlignment(ss.HorizontalAlignment)
        slot:SetVerticalAlignment(ss.VerticalAlignment)
    end)
    pcall(function() t:SetVisibility(4) end)                          -- (seen, not hit-tested)
    -- (light: the page's own dark grey was lost over the game seen behind this page)
    pcall(function() t:SetColorAndOpacity({ SpecifiedColor = { R = 0.8, G = 0.8, B = 0.8, A = 1.0 }, ColorUseRule = 0 }) end)
    return t
end

-- (Each row drawn smaller, as first tried: STORROR's own row animations put their size back. The whole column is made
-- smaller instead - fpmenu.lua's hide_theirs.)
local SHRINK = 0.7
local function shrink(row, rr)
    if rr.shrunk then return end
    local h = 0
    pcall(function() h = row:GetDesiredSize().Y end)
    if not (h and h > 1.0) then return end
    pcall(function() row:SetRenderTransformPivot({ X = 0.0, Y = 0.0 }) end)
    pcall(function() row:SetRenderScale({ X = SHRINK, Y = SHRINK }) end)
    pcall(function()
        local sl = row.Slot
        local P = sl.Padding
        sl:SetPadding({ Left = P.Left, Top = P.Top, Right = P.Right, Bottom = P.Bottom - h * (1.0 - SHRINK) })
    end)
    rr.shrunk = true
end

local function add(page, spec, anchor)
    if spec.header then return add_heading(page, spec, anchor) end
    local box = part(page, "VerticalBox")
    local tmpl = part(page, "CameraShakeFactor")
    if not (box and tmpl and alive(anchor)) then return nil end
    local WBL = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local row = WBL:Create(lib.world(), tmpl:GetClass(), tmpl:GetOwningPlayer())
    if not alive(row) then return nil end
    rows[row:GetAddress()] = { spec = spec, g = spec.switch and true or nil, name = row:GetFName():ToString() }
    row.SettingsName = FText(spec.label)
    -- (put in straight after the anchor: the rows under it come off, ours goes on the end, and they go back on)
    local at = box:GetChildIndex(anchor)
    local after = {}
    for i = at + 1, box:GetChildrenCount() - 1 do after[#after + 1] = box:GetChildAt(i) end
    for _, c in ipairs(after) do box:RemoveChild(c) end
    local slot = box:AddChildToVerticalBox(row)
    for _, c in ipairs(after) do box:AddChildToVerticalBox(c) end
    pcall(function()
        local ts = anchor.Slot
        slot:SetPadding(ts.Padding)
        slot:SetHorizontalAlignment(ts.HorizontalAlignment)
        slot:SetVerticalAlignment(ts.VerticalAlignment)
        slot:SetSize(ts.Size)
    end)
    pcall(enlist, box, row, anchor)
    pcall(function() row.Title:SetText(FText(spec.label)) end)
    pcall(function() row.SliderSpeedRatio = tmpl.SliderSpeedRatio end)
    pcall(function() row.bRightStickSliderNavigation = tmpl.bRightStickSliderNavigation end)
    if spec.switch then
        pcall(function() row.Slider:SetMinValue(0.0); row.Slider:SetMaxValue(1.0); row.Slider:SetStepSize(1.0) end)
        pcall(function() row.Slider:SetValue(spec.get() and 1.0 or 0.0) end)
        show_switch(row, spec.get())
        log("settings: %s switch added (%s)", spec.label, spec.get() and "on" or "off")
    else
        pcall(function() row.Slider:SetMinValue(spec.min); row.Slider:SetMaxValue(spec.max); row.Slider:SetStepSize(spec.step) end)
        local v = slider_setting(spec)
        pcall(function() row.Slider:SetValue(v) end)
        show_slider(row, spec, v)
        log("settings: %s slider added (%s)", spec.label, spec.text(v))
    end
    return row
end

-- every frame, each of our rows on a page
local live = {}                         -- rows being watched: { row, page, ... }
local function watch_switch(r, addr)
    local spec, rr = rows[addr].spec, rows[addr]
    local on = spec.get() and true or false
    local g = rr.g
    local now = os.clock()
    -- (for HOLD after a flip, the slider held where the flip put it: the game's slider springs back a moment
    -- after it is moved, and that was taken for the player moving it back - flipped on, it was off again in a
    -- third of a second, "the cameras stuck in 3rd person mode", 2026-10-22)
    local held = r.flip_t and now - r.flip_t < HOLD
    -- a click on it
    if type(g) == "table" and g.button then
        local down = g.button:IsPressed()
        if down and not r.was_pressed and not held then
            on = not on
            spec.set(on)
            r.row.Slider:SetValue(on and 1.0 or 0.0)
            r.flip_t, held = now, true
            log("settings: %s %s (clicked)", spec.label, on and "on" or "off")
        end
        r.was_pressed = down
    end
    -- moved left or right
    local v = r.row.Slider:GetValue() >= 0.5
    if v ~= on then
        if not held and r.last ~= nil and v ~= r.last then                 -- (moved by the player)
            on = v
            spec.set(on)
            r.flip_t = now
            log("settings: %s %s (moved)", spec.label, on and "on" or "off")
        else
            r.row.Slider:SetValue(on and 1.0 or 0.0)                       -- (sprung back, or set elsewhere)
        end
    end
    r.last = on
    show_switch(r.row, on)
end

local function watch_slider(r, addr)
    local spec = rows[addr].spec
    local C = cfg()
    if not C then return end
    local now = os.clock()
    local v = snap(spec, r.row.Slider:GetValue())
    local cur = slider_setting(spec)
    if r.last == nil or now < r.hold_until then
        -- (first looks: shown as the setting is, whatever the page does to its rows as it fills)
        if math.abs(r.row.Slider:GetValue() - cur) > 1e-3 then r.row.Slider:SetValue(cur) end
        r.last = cur
    elseif math.abs(v - r.last) > 1e-3 then                                 -- (moved by the player)
        C.set(spec.key, v)
        if spec.apply then pcall(spec.apply, v) end
        r.last = v
        cur = v
    elseif math.abs(cur - r.last) > 1e-3 then                               -- (set elsewhere)
        r.row.Slider:SetValue(cur)
        r.last = cur
    end
    if r.shown ~= r.last then r.shown = r.last; show_slider(r.row, spec, r.last) end
end

local function watch_one(addr, r)
    local ok = pcall(function()
        if not (r.row:IsValid() and r.page:IsValid()) then live[addr], rows[addr] = nil, nil; return end
        if not rows[addr] then live[addr] = nil; return end
        if rows[addr].spec.switch then watch_switch(r, addr) else watch_slider(r, addr) end
    end)
    if not ok then live[addr], rows[addr] = nil, nil end
end

-- Each frame, in full, only the rows the player can be changing: the picked one and the one under the mouse, on each
-- page shown (its column's button group says which); the rows that were so last frame once more (their highlight put
-- back); and ROUND others in turn (a preset changing them, a click's first frame). All of them every frame - 55 rows -
-- cost 6 ms a frame with the menu up, "extreme lag", 2026-11-09. Without the group's answers, all of them as before.
local ROUND = 6
local turn_list, turn_i, turn_n, was_active, no_group = {}, 0, -1, {}, false
local turn_at = {}                       -- (each page's place in the column for the rows watched in turn, by address)
-- (the pages on the screen at the last look - page address to page - and only their rows watched: STORROR makes a new
-- page each time a tab is shown and throws the old one away with the menu still up; a row of a thrown-away page looked
-- at later, once the game had freed it, crashed the game - "crash", 2026-11-10)
local shown_pages = {}
local watch_skip = false
local function watch()
    -- (every row of ours, every other frame, as it was before 23:29: the cheaper ways tried since - only the picked and
    -- hovered rows by the column's button group, the rest in turn - were followed by the game crashing as the tab came up,
    -- four times, "crash", 2026-11-10. Every other frame keeps the cost down; switches repaint only on a change.)
    watch_skip = not watch_skip
    if watch_skip then return end
    for addr, r in pairs(live) do watch_one(addr, r) end
end

-- every frame: ours watched; a few times a second, STORROR's Camera pages looked for (ours added, the switches drawn)
function M.tick(dt)
    -- (only while one of STORROR's menus is up - fpmenu.lua tells: with the menu shut our 39 rows were still watched
    -- every frame and the pages looked for ten times a second, 2.4 ms a frame - "we need to optimize", 2026-11-09)
    local MENU = package.loaded["fpmenu"]
    if MENU and MENU.enabled and MENU.is_menu_up == false then
        -- (shut: nothing of the menu's kept - its pages found afresh when it opens again. Kept, unwatched while it was
        -- shut, STORROR freed them meanwhile and the first look at one as it opened again crashed the game, 2026-11-09)
        if next(live) ~= nil then live = {}; turn_list, turn_i, turn_n, was_active, turn_at = {}, 0, -1, {}, {} end
        shown_pages = {}
        return
    end
    watch()
    look_t, poll_t = look_t - dt, poll_t - dt
    if look_t > 0 and poll_t > 0 then return end
    local looking = look_t <= 0
    if looking then look_t = 0.5 end
    poll_t = 0.1
    local shown = {}
    for _, page in ipairs(FindAllOf("SPPCameraSettingsWidgetBP_C") or {}) do
        local ok, err = pcall(function()
            if not page:IsValid() or page:GetFName():ToString():find("^Default__") then return end
            if page:IsVisible() then shown[page:GetAddress()] = page end
            local box = part(page, "VerticalBox")
            if not box then return end
            local key = page:GetFName():ToString()
            local tab = is_tab_page(page)
            local real = part(page, "CameraInvertYNewSelector")
            local anchor = real
            local button_anchor = real              -- (the last row that can be picked: headings cannot)
            -- (our rows on the page, by label: the column gone through once - not once for each row, 55 times over ten
            -- times a second, 5 ms a frame with the menu up: "extreme lag", 2026-11-09)
            local by_label = {}
            pcall(function()
                for i = 0, box:GetChildrenCount() - 1 do
                    local c = box:GetChildAt(i)
                    local r = c and rows[c:GetAddress()]
                    -- (and that one, by its name: a widget of STORROR's made where one of ours was freed is not ours)
                    if r and r.name and c:GetFName():ToString() ~= r.name then rows[c:GetAddress()], r = nil, nil end
                    if r then by_label[r.spec.label] = c end
                end
            end)
            for _, spec in ipairs(ROWS) do
                if (not spec.ours or tab) and not (spec.standalone and _G.FP_MASHUP) then
                    local row = by_label[spec.label]
                    if not row and looking and anchor and not tried[key .. "|" .. spec.label] then
                        tried[key .. "|" .. spec.label] = true
                        local okr, res = pcall(add, page, spec, anchor)
                        if not okr then log("settings: %s not added (%s)", spec.label, tostring(res)) end
                        row = okr and res or nil
                    end
                    if row then
                        local addr = row:GetAddress()
                        local rr = rows[addr]
                        if rr.header then
                            anchor = row
                            goto next_spec
                        end
                        if looking and button_anchor then pcall(enlist, box, row, button_anchor) end
                        button_anchor = row
                        if rr.g == true and real then
                            local okb, g = pcall(build_graphic, row, real)
                            if okb and g then rr.g = g
                            elseif not okb then rr.g = "failed"; log("settings: switch not drawn (%s)", tostring(g)) end
                        end
                        if not live[addr] then
                            live[addr] = { row = row, page = page, page_addr = page:GetAddress(), was_pressed = false,
                                           last = nil, hold_until = os.clock() + OPEN_HOLD }
                        end
                        anchor = row
                    elseif not spec.header then
                        anchor = nil                    -- (the rest wait for this one; never for a heading)
                    end
                end
                ::next_spec::
            end
        end)
        if not ok and not errored then errored = true; log("settings: %s", tostring(err)) end
    end
    -- (only the rows of pages on the screen now kept - the others let go untouched: see shown_pages)
    shown_pages = shown
    for addr, r in pairs(live) do
        if not (r.page_addr and shown[r.page_addr]) then live[addr] = nil end
    end
end

-- (a new map: its pages may be new)
function M.forget() tried = {}; live = {}; turn_list, turn_i, turn_n, was_active, turn_at = {}, 0, -1, {}, {} end

-- `w` (a widget) is one of our rows (fpmenu.lua keeps them on the FIRST PERSON tab's page)
function M.is_row(w)
    local ok, yes = pcall(function() return rows[w:GetAddress()] ~= nil end)
    return ok and yes
end

return M
