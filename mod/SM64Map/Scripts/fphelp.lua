-- STORROR First Person: WHAT EACH SETTING DOES - the last row on the FIRST PERSON tab opens a panel on the right of the
-- screen with every setting and what it does, group by group as the tab has them ("make one more button all the way at
-- the bottom, this button will pull up a dialog explaining exactly what each setting does", 2026-11-09).
-- A widget of the mod's own (a dark panel, a scroll box, one text); scrolled by the mouse wheel over it or the right
-- stick; shut when its row is switched off, or the tab or the menu is left.
local lib = require("lib")
local log = lib.log
local M = { open = false }

local TEXT = [[
WHAT EACH SETTING DOES
(scroll: mouse wheel over this, or the right stick)

[PRESETS]
PRESET - Puts on a whole set of settings at once. Moving it changes the settings below; CUSTOM means none.
  DEFAULT - everything as it starts. MIRROR'S EDGE - lively. STEADY - as still as it goes. BODY CAM - your saved body cam setup.
  GOPRO - a wide fisheye from up on your head, a little shake. CINEMATIC - narrower, smoothed, film bars, blur, breathing.
  COMPETITIVE - no motion or effects, crosshair and speedometer. INTENSE - every speed and landing effect turned up.
  GHOST - no body at all, a crosshair. COMFORT - for motion sickness: still, level, upright through flips.
  RANDOM - every setting at random, picked again each time you move onto it.

[VIEW]
FIRST PERSON - First person on or off. Also F5, or both sticks clicked, when FIRST/THIRD PERSON BUTTON is on.
FIELD OF VIEW - How wide you see, 60 to 179 degrees.
WIDEN POV - STORROR's drone fisheye on your view. 50% is the drone's strength; below 0 it bends the other way. A strong fisheye with a very wide field of view blurs the middle of the screen.
DRONE FISHEYE - Turning it on sets FIELD OF VIEW to 100 and WIDEN POV to 50, like the drone camera, and adds its dark edges. You can still change both afterwards.
NEAR CLIP - How close to your eyes things are still drawn, 1 to 20 cm. Lower shows your arms and walls closer up; higher cuts them off sooner.
FLASHLIGHT - A light shining from your eyes where you look. L turns it on and off too.
FLASHLIGHT BRIGHTNESS - How bright it is.

[EFFECTS]
SPEED FOV - The view widens the faster you go, falling included, up to 30 degrees more.
SPEED EFFECTS - The faster you go, the darker the screen's edges and the more the colours split at them.
MOTION BLUR - 0% none, 50% the engine's normal amount, 100% double.
JUMP FOV KICK - The view widens for a moment as you jump, up to 12 degrees.
LANDING IMPACT - The camera dips and shakes when you land; the harder the fall, the harder the landing.
LEAN - The view tilts into turns while you run, up to 8 degrees.
WALL RUN TILT - The view leans away from a wall you run along, up to 12 degrees.
BREATHING - Standing still, the view slowly rises and falls. Multiplied by MOTION: none at MOTION 0%.
LOOK DOWN IN AIR - The view tips down while you're in the air, so you see where you'll land (up to 300%: 75 degrees).
SPRINT HANDS - At a sprint the camera moves forward and down and tips down, so your hands are in view (up to 300%).
SPRINT SHAKE - A small, quick shake of the camera as you get up to a full sprint.

[HEAD]
MOTION - 0%: the camera sits still on your body, no head bob. 100%: it follows your head exactly. Flips, rolls, climbs and swings always follow your body.
FOLLOW FLIPS - On: the view turns over with flips, rolls, vaults and pole swings. Off: it stays upright.
HEAD LOCK - How much of looking up and down is taken away: 0% the full range, 100% the view stays level.
LOOK SMOOTHING - 0%: your look is raw. Higher eases it; 100% is slow and cinematic. Your body's turns are not smoothed.

[RUBBERBAND] (your head pulled back to where your body faces; all of it lets go while you're in the air and takes back over when you land)
RUBBERBAND X - Left and right. 0%: free. Higher: turning away from your body gets harder the further you go. 100%: your head can't leave your body's direction.
RUBBERBAND Y - The same for up and down, pulled back to level.
RUBBERBAND STRENGTH - How hard it resists.
RUBBERBAND CENTER SPEED - How fast the view comes back to the middle after you let go of the right stick: 0 never, 100 at once.
RUBBERBAND CENTER DELAY - On: it waits a moment (0.6 s) before coming back.

[CAMERA POSITION]
CAMERA X / Y / Z - Moves the camera from your eyes, up to 100 cm each way: X forward (+) or back, Y right (+) or left, Z up (+) or down.

[HUD]
CROSSHAIR DOT - A crosshair in the middle of the screen.
CROSSHAIR SIZE - Its size, in pixels.
CROSSHAIR COLOR - White, green, red, yellow, cyan or magenta.
CROSSHAIR SHAPE - A dot, a cross, or both.
SPEEDOMETER - Your speed, falling included, low on the screen: off, km/h or mph.
CINEMATIC BARS - Black bars at the top and bottom of the screen; 100% is a widescreen film frame.
HIDE HUD - Hides STORROR's hints, compass, stamina and score while in first person.

[CONTROLS]
STICK TURN RATE - How fast the controller's right stick turns the view. The mouse isn't changed.
LOOK UP/DOWN SPEED - How fast you look up and down, apart from left and right (mouse and stick).
INVERT LOOK UP/DOWN - Up is down, in first person only.
RIGHT STICK TURNS BODY - On: standing, your body turns with your view. Off: you turn your head only.
LEFT STICK STEERS - On: STORROR's own steering - point the stick straight back and you turn around, the camera swinging round with you. Off: your body keeps facing where you look, the stick moves you sideways, and pulling it back backs you up facing forward.
FIRST/THIRD PERSON BUTTON - On: F5, or clicking both sticks together, switches first person on and off.
THIRD PERSON IN BAILS - On: STORROR's own camera while you bail and get back up.

[BODY] (hidden from your own view only - your shadow stays)
HIDE HEAD - Your head and hair.
HIDE ARMS - Your forearms and hands.
HIDE STOMACH - The strip of stomach above your pants.
HIDE SHIRT / HIDE PANTS / HIDE SHOES - That piece of clothing.

[HIDE WHEN] (all of you disappears, and comes back a moment after)
HIDE BODY IN FLIPS - While you flip in the air (turned over more than 110 degrees).
HIDE BODY IN ROLLS - While you roll.
HIDE BODY IN VAULTS - While you vault.
HIDE BODY WHEN RUNNING - While you run along the ground, faster than a walk.
HIDE BODY WHEN STANDING - While you stand still.

[HELP]
WHAT EACH SETTING DOES - Opens this. Switch it off, or leave the tab, to close it.
]]

local function alive(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end
local function cls(path) return StaticFindObject(path) end

local panel = nil                -- { w = the widget, sb = its scroll box, shown = bool }
local scroll = 0.0
local RIGHT_KEY = { KeyName = FName("Gamepad_RightY") }

local function build()
    local pc = lib.controller()
    if not pc then return nil end
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("None"))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("None"))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("None"))
    tree.RootWidget = canvas
    local function place(x, y, sx, sy, child)
        local s = canvas:AddChildToCanvas(child)
        s:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
        s:SetAlignment({ X = 0.5, Y = 0.5 })
        s:SetPosition({ X = x, Y = y })
        s:SetSize({ X = sx, Y = sy })
    end
    -- (a dark panel on the right half of the screen, the settings column on the left still seen)
    local bg = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("None"))
    pcall(function() bg:SetColorAndOpacity({ R = 0.0, G = 0.0, B = 0.0, A = 0.85 }) end)
    place(450.0, 0.0, 860.0, 900.0, bg)
    local sb = StaticConstructObject(cls("/Script/UMG.ScrollBox"), canvas, FName("None"))
    place(450.0, 0.0, 800.0, 850.0, sb)
    local tb = StaticConstructObject(cls("/Script/UMG.TextBlock"), sb, FName("None"))
    pcall(function() local f = tb.Font; f.Size = 15; tb:SetFont(f) end)
    pcall(function() tb:SetColorAndOpacity({ SpecifiedColor = { R = 0.95, G = 0.95, B = 0.95, A = 1.0 }, ColorUseRule = 0 }) end)
    pcall(function() tb:SetAutoWrapText(true) end)
    local text = TEXT
    if _G.FP_MASHUP then
        text = text:gsub("\nFIRST PERSON %- [^\n]*", ""):gsub("\nFIRST/THIRD PERSON BUTTON %- [^\n]*", "")
    end
    tb:SetText(FText(text))
    sb:AddChild(tb)
    pcall(function() w:SetVisibility(1) end)                       -- (collapsed till opened)
    w:AddToViewport(200)
    log("help: the panel made")
    return { w = w, sb = sb, shown = false }
end

function M.set_open(on)
    M.open = on and true or false
    if M.open then scroll = 0.0 end
end

-- every frame: `tab_open` the FIRST PERSON tab is the one shown
function M.tick(dt, tab_open)
    if M.open and not tab_open then M.open = false end            -- (the tab or the menu left: shut)
    if M.open and not (panel and alive(panel.w)) then
        local ok, p = pcall(build)
        panel = ok and p or nil
        if not ok then log("help: no panel (%s)", tostring(p)); M.open = false end
    end
    if not (panel and alive(panel.w)) then return end
    if panel.shown ~= M.open then
        pcall(function() panel.w:SetVisibility(M.open and 0 or 1) end)   -- (seen and hit, for the wheel; or collapsed)
        panel.shown = M.open
        if M.open then pcall(function() panel.sb:SetScrollOffset(0.0) end) end
    end
    if not M.open then return end
    -- (the right stick scrolls it)
    pcall(function()
        local pc = lib.controller()
        local y = pc:GetInputAnalogKeyState(RIGHT_KEY)
        if type(y) == "number" and math.abs(y) > 0.2 then
            local most = panel.sb:GetScrollOffsetOfEnd()
            scroll = math.max(0.0, math.min(most, panel.sb:GetScrollOffset() - y * 900.0 * (dt or 0.016)))
            panel.sb:SetScrollOffset(scroll)
        end
    end)
end

-- (a new map: the panel was the old map's controller's - made again when wanted)
function M.forget() panel = nil; M.open = false end

return M
