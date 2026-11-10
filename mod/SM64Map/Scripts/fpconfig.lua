-- STORROR First Person: the mod's settings, kept in its settings.txt - a line each, key=value. The FIRST PERSON switch
-- (first_person) and the FIRST PERSON tab's settings (2026-11-09: "start adding all of our new settings" - the ones
-- promised in Discord, 2026-10-22: FOV, angle of view, widen the POV, rubberbanding, motion, lock the head up).
local M = {}

local DEFAULTS = {
    first_person = 1,
    fov = 105,          -- FIELD OF VIEW, degrees across (up to 179: a flat picture cannot show 180)
    speed_fov = 0,      -- SPEED FOV: percent of the most the view widens at full speed (0 off)
    widen = 0,         -- WIDEN POV: STORROR's fisheye on the first-person camera (percent; 50 is the drone's)
    rubber = 50,        -- RUBBERBANDING: how loosely the camera trails the body (0 tight, 50 as it was, 100 loose)
    motion = 100,       -- MOTION: how much of the head's bob as he moves the camera takes (percent)
    -- RUBBERBAND X, Y, STRENGTH: the head pulled back to where his body faces (percent; X 50 and STRENGTH 25 as it was)
    rb_x = 50, rb_y = 0, rb_strength = 25, rb_center = 25, rb_delay = 0, rstick_body = 1,
    stick_rate = 100,   -- STICK TURN RATE: how fast the stick turns the view, percent of STORROR's own
    left_steers = 1,    -- LEFT STICK STEERS: the left stick turns him the way he runs (1, STORROR's own), or he faces the view (0)
    follow_flips = 1,   -- FOLLOW FLIPS: the view turns with his flips, rolls, vaults and swings (1) or not (0)
    drone_fish = 0,     -- DRONE FISHEYE: the drone's fisheye on the first-person view, as strong as the drone has it (1)
    -- CAMERA X, Y, Z: the camera moved from his eyes, cm - forward, right, up ("add an x y and z axis that the player
    -- can move the camera/head around with", 2026-11-09)
    cam_x = 0, cam_y = 0, cam_z = 0,
    head_lock = 0,      -- HEAD LOCK: percent of the look up and down taken away - 100 keeps the view level (a switch at
                        -- first: "make the head lock a slider ... 100% ... perfectly horizontal and 0 would be full range")
    -- HIDE ARMS, SHIRT, PANTS, SHOES: that part of him not seen by the player ("a toggle for each body part to make it
    -- invisable in the players eyes", 2026-11-09)
    hide_arms = 0, hide_stomach = 0, hide_shirt = 0, hide_pants = 0, hide_shoes = 0,
    flip_hide = 0, roll_hide = 0, vault_hide = 0, -- HIDE BODY IN FLIPS / ROLLS / VAULTS: all of him gone meanwhile
    run_hide = 0,       -- HIDE BODY WHEN RUNNING: all of him gone while he runs on the ground
    stand_hide = 0,     -- HIDE BODY WHEN STANDING: all of him gone while he stands still
    -- ("all of it", 2026-11-09 - from a list:)
    cross_size = 4, cross_color = 0, cross_shape = 0,  -- the crosshair: px, WHITE.., DOT / CROSS / DOT + CROSS
    speedo = 0,         -- SPEEDOMETER: 0 off, 1 km/h, 2 mph
    speed_fx = 0, motion_blur = 0, jump_kick = 0,      -- percent
    near_clip = 3,      -- NEAR CLIP: cm from the eyes the picture starts
    wall_tilt = 0, breathing = 0, look_smooth = 0,     -- percent
    pitch_rate = 100, invert_y = 0,                    -- LOOK UP/DOWN SPEED percent, INVERT LOOK UP/DOWN
    view_key = 1, bail_third = 0,                      -- FIRST/THIRD PERSON BUTTON, THIRD PERSON IN BAILS
    sprint_shake = 0, flashlight = 0, flash_bright = 50, bars = 0,  -- ("sprint shake, flashlight, and cinematic bars")
    hide_head = 1,      -- HIDE HEAD: his head, hair, brows and beard hidden (1, as always), or shown (0)
    -- the feel of moving and the screen (fp.lua, fphud.lua; "add all of it", 2026-11-09): percent, or 1/0
    impact = 0, lean = 0, air_look = 0, sprint_hands = 0, crosshair = 0, hide_hud = 0,
    preset = 0,         -- PRESET: the last one put on (0 CUSTOM - none)
}
-- (ANGLE OF VIEW was a tilt of the camera at first, 2026-11-09, then a lens's focal length - and then taken out: "angle
-- of view and field of view are the same thing", "just remove angle of view make field of view go up to 200". MOTION was
-- the share of the flips the view took - "that only meant for head bobbing and camera movement ... flips should be its
-- own switch".)
-- (LOCK HEAD UP, lock_up, taken out: "remove lock head up", 2026-11-09)
local ORDER = { "first_person", "fov", "speed_fov", "widen", "rubber", "motion", "rb_x", "rb_y", "rb_strength", "rb_center", "rb_delay", "stick_rate", "rstick_body", "cam_x", "cam_y", "cam_z", "left_steers", "follow_flips",
                "drone_fish", "head_lock", "hide_arms", "hide_stomach", "hide_head", "hide_shirt", "hide_pants", "hide_shoes", "flip_hide", "roll_hide", "vault_hide", "run_hide", "stand_hide",
                "cross_size", "cross_color", "cross_shape", "speedo", "speed_fx", "motion_blur", "jump_kick", "near_clip",
                "wall_tilt", "breathing", "look_smooth", "pitch_rate", "invert_y", "view_key", "bail_third", "sprint_shake", "flashlight", "flash_bright", "bars",
                "impact", "lean", "air_look", "sprint_hands", "crosshair", "hide_hud", "preset" }
M.DEFAULTS = DEFAULTS

-- PRESETS (the PRESET row): DEFAULT every setting as it starts (FIRST PERSON itself left as it is); MIRROR'S EDGE lively -
-- the speed, the landings, the lean, the hands, a dot, no HUD; STEADY as still as it goes ("add all of it", 2026-11-09)
-- BODY CAM: the user's own settings as they had them ("add what settings I have now as a body cam preset", 2026-11-09,
-- copied from their settings.txt at 22:37) - low on the chest, a wider lens, every feel at full, the shirt and HUD off
M.PRESET_NAMES = { [0] = "CUSTOM", [1] = "DEFAULT", [2] = "MIRROR'S EDGE", [3] = "STEADY", [4] = "BODY CAM",
                   -- ("also add a bunch of presets", then "make a preset that is just random, so everytime you go to the
                   -- random preset it toggles everything randomly", 2026-11-09 - RANDOM is fpsettings.lua's: no list)
                   [5] = "GOPRO", [6] = "CINEMATIC", [7] = "COMPETITIVE", [8] = "INTENSE", [9] = "GHOST", [10] = "COMFORT",
                   [11] = "RANDOM" }
M.RANDOM = 11
local function with(over)
    local t = {}
    for k, v in pairs(DEFAULTS) do if k ~= "first_person" and k ~= "preset" then t[k] = v end end
    for k, v in pairs(over or {}) do t[k] = v end
    return t
end
M.PRESETS = {
    [1] = with(nil),
    -- (MIRROR'S EDGE saved from the player's settings at 2026-11-10 00:04: "save the options for mirrors edge preset")
    [2] = with({ fov = 136, speed_fov = 55, widen = -10, rubber = 50, motion = 70, rb_x = 0, rb_y = 0,
                 rb_strength = 25, rb_center = 25, rb_delay = 0, stick_rate = 100, rstick_body = 1, cam_x = 0,
                 cam_y = 0, cam_z = 0, left_steers = 1, follow_flips = 1, drone_fish = 0, head_lock = 0,
                 hide_arms = 0, hide_stomach = 0, hide_head = 1, hide_shirt = 0, hide_pants = 0, hide_shoes = 0,
                 flip_hide = 0, roll_hide = 0, vault_hide = 0, run_hide = 0, stand_hide = 0, cross_size = 4,
                 cross_color = 0, cross_shape = 0, speedo = 0, speed_fx = 30, motion_blur = 10, jump_kick = 25,
                 near_clip = 3, wall_tilt = 65, breathing = 50, look_smooth = 0, pitch_rate = 100, invert_y = 0,
                 view_key = 1, bail_third = 0, sprint_shake = 35, flashlight = 1, flash_bright = 50, bars = 0,
                 impact = 60, lean = 40, air_look = 100, sprint_hands = 60, crosshair = 1,
                 hide_hud = 1 }),
    [3] = with({ fov = 105, motion = 0, follow_flips = 0, rb_x = 0, rb_y = 0, rb_center = 0 }),
    -- GOPRO: a wide fisheye from up on the head, a little shake and lean
    [5] = with({ fov = 120, widen = 40, cam_x = 4, cam_z = 8, speed_fov = 30, impact = 60, lean = 30, sprint_shake = 30,
                 hide_hud = 1 }),
    -- CINEMATIC: narrower, eased, film bars, blur and breathing, no HUD
    [6] = with({ fov = 85, look_smooth = 60, bars = 100, motion = 60, lean = 40, wall_tilt = 40, breathing = 50,
                 motion_blur = 50, speed_fov = 20, impact = 30, hide_hud = 1 }),
    -- COMPETITIVE: clean and still - no motion or effects, the crosshair and the speedometer, the HUD kept
    [7] = with({ fov = 110, motion = 0, follow_flips = 0, impact = 0, lean = 0, air_look = 0, sprint_hands = 0,
                 speed_fov = 0, rb_x = 0, rb_y = 0, rb_center = 0, crosshair = 1, speedo = 1 }),
    -- INTENSE: every effect of speed and landing up high
    [8] = with({ fov = 105, speed_fov = 100, speed_fx = 70, jump_kick = 70, impact = 100, lean = 80, wall_tilt = 80,
                 sprint_shake = 60, motion_blur = 40, sprint_hands = 60, air_look = 50 }),
    -- GHOST: no body at all, the crosshair to aim by
    [9] = with({ hide_head = 1, hide_arms = 1, hide_stomach = 1, hide_shirt = 1, hide_pants = 1, hide_shoes = 1,
                 crosshair = 1 }),
    -- COMFORT: for motion sickness - still, level, upright through flips, no effects
    [10] = with({ fov = 100, motion = 0, follow_flips = 0, impact = 0, lean = 0, air_look = 0, sprint_hands = 0,
                  speed_fov = 0, rb_x = 0, rb_y = 0, rb_center = 0, crosshair = 1 }),
    -- (BODY CAM saved again from the player's settings at 23:28: "save this body cam preset again", 2026-11-09)
    [4] = with({ fov = 99, speed_fov = 80, widen = 65, rubber = 50, motion = 100, rb_x = 50, rb_y = 0,
                 rb_strength = 25, rb_center = 25, rb_delay = 0, stick_rate = 95, rstick_body = 1, cam_x = -6,
                 cam_y = 8, cam_z = -24, left_steers = 1, follow_flips = 1, drone_fish = 1, head_lock = 55,
                 hide_arms = 0, hide_stomach = 0, hide_head = 1, hide_shirt = 1, hide_pants = 0, hide_shoes = 0,
                 flip_hide = 0, roll_hide = 0, vault_hide = 0, run_hide = 0, stand_hide = 0, cross_size = 4,
                 cross_color = 0, cross_shape = 0, speedo = 0, speed_fx = 0, motion_blur = 20, jump_kick = 100,
                 near_clip = 5, wall_tilt = 40, breathing = 100, look_smooth = 20, pitch_rate = 100, invert_y = 0,
                 view_key = 1, bail_third = 0, impact = 55, lean = 100, air_look = 100,
                 sprint_hands = 100, crosshair = 0, hide_hud = 1 }),
}
function M.apply_preset(n)
    local t = M.PRESETS[n]
    if not t then return end
    for k, v in pairs(t) do M.set(k, v) end
end

local file, values, save_at = nil, {}, nil

function M.load(path)
    file = path
    values = {}
    local f = io.open(path, "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*([%-%d%.]+)")
        if k and tonumber(v) then values[k] = tonumber(v) end
    end
    f:close()
end

function M.num(k)
    local v = values[k]
    if v == nil then v = DEFAULTS[k] end
    return v or 0
end

function M.save()
    if not file then return end
    local out = {}
    for _, k in ipairs(ORDER) do
        local v = M.num(k)
        out[#out + 1] = k .. "=" .. (v == math.floor(v) and string.format("%d", v) or string.format("%.3f", v))
    end
    local f = io.open(file, "w")
    if f then f:write(table.concat(out, "\n") .. "\n"); f:close() end
end

-- set (kept on disk a moment after it stops changing, or at once: `now`)
function M.set(k, v, now)
    if values[k] == v then return end
    values[k] = v
    if now then save_at = nil; M.save() else save_at = os.clock() + 0.6 end
end

function M.tick()
    if save_at and os.clock() >= save_at then save_at = nil; M.save() end
end

return M
