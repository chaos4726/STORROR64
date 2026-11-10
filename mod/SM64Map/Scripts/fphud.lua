-- STORROR First Person: on the screen in first person ("add all of it", 2026-11-09 - from a list):
--   CROSSHAIR DOT: a small dot in the middle of the screen - a widget of the mod's own (a canvas, a dark square and a
--     light one over it), shown in first person while no menu is up
--   HIDE HUD: STORROR's HUD (its layer manager's LayerHUD: hints, compass, stamina, scoring, name tags, help) not seen
--     in first person; seen again as soon as first person goes or the switch is off
local lib = require("lib")
local log = lib.log
local M = {}

local function setting(k, d) local C = _G.FP_CFG; if C then return C.num(k) end; return d end
local function alive(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end
local function cls(path) return StaticFindObject(path) end

-- ------------------------------------------------------------------ the crosshair
-- (its look the player's: CROSSHAIR SIZE in px, CROSSHAIR COLOR, CROSSHAIR SHAPE - a dot, a cross, or both - "all of it",
-- 2026-11-09, from a list; made again when one of them changes. Every piece has a dark edge round it.)
local DOT_EDGE = 2.0
local COLORS = { [0] = { 1.0, 1.0, 1.0 }, { 0.2, 1.0, 0.3 }, { 1.0, 0.2, 0.2 }, { 1.0, 0.9, 0.2 }, { 0.2, 0.9, 1.0 }, { 1.0, 0.3, 0.9 } }
local dot = nil                               -- { w = the widget, world = its world's address, shown = bool, sig = its look }

local function cross_sig()
    return string.format("%d|%d|%d", setting("cross_size", 4), setting("cross_color", 0), setting("cross_shape", 0))
end

-- a widget of our own on the screen: a UserWidget, its tree, a canvas filling it (nothing named: the engine names them)
local function new_canvas()
    local pc = lib.controller()
    if not pc then return nil end
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("None"))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("None"))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("None"))
    tree.RootWidget = canvas
    return w, canvas
end

local function build_dot()
    local world = lib.world()
    if not world then return nil end
    local w, canvas = new_canvas()
    if not w then return nil end
    local size = math.max(2.0, math.min(24.0, setting("cross_size", 4)))
    local c = COLORS[math.floor(setting("cross_color", 0) + 0.5)] or COLORS[0]
    local shape = math.floor(setting("cross_shape", 0) + 0.5)
    local function rect(x, y, sx, sy, col)
        local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("None"))
        pcall(function() img:SetColorAndOpacity(col) end)
        local s = canvas:AddChildToCanvas(img)
        s:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
        s:SetAlignment({ X = 0.5, Y = 0.5 })
        s:SetPosition({ X = x, Y = y })
        s:SetSize({ X = sx, Y = sy })
    end
    local parts = {}
    if shape ~= 1 then parts[#parts + 1] = { 0.0, 0.0, size, size } end                -- (the dot)
    if shape >= 1 then                                                                  -- (the cross: four arms)
        local len, th = size * 1.5, math.max(2.0, math.floor(size / 3.0 + 0.5))
        local off = size * 0.6 + len / 2.0 + (shape == 2 and size * 0.5 or 0.0)
        parts[#parts + 1] = { off, 0.0, len, th }; parts[#parts + 1] = { -off, 0.0, len, th }
        parts[#parts + 1] = { 0.0, off, th, len }; parts[#parts + 1] = { 0.0, -off, th, len }
    end
    local edge = { R = 0.0, G = 0.0, B = 0.0, A = 0.6 }
    local main = { R = c[1], G = c[2], B = c[3], A = 0.9 }
    for _, q in ipairs(parts) do rect(q[1], q[2], q[3] + DOT_EDGE * 2.0, q[4] + DOT_EDGE * 2.0, edge) end
    for _, q in ipairs(parts) do rect(q[1], q[2], q[3], q[4], main) end
    pcall(function() w:SetVisibility(1) end)                      -- (collapsed till wanted)
    w:AddToViewport(40)
    log("hud: crosshair on the screen (%s)", cross_sig())
    return { w = w, world = world:GetAddress(), shown = false, sig = cross_sig() }
end

local function dot_tick(want)
    -- (its look changed: the old one taken off the screen, made again)
    if dot and alive(dot.w) and dot.sig ~= cross_sig() then
        pcall(function() dot.w:RemoveFromParent() end)
        dot = nil
    end
    if want and not (dot and alive(dot.w)) then
        local ok, d = pcall(build_dot)
        dot = ok and d or nil
        if not ok then log("hud: no crosshair (%s)", tostring(d)) end
    end
    if dot and alive(dot.w) and dot.shown ~= want then
        pcall(function() dot.w:SetVisibility(want and 3 or 1) end)  -- (seen, never hit; or collapsed)
        dot.shown = want
    end
end

-- ------------------------------------------------------------------ the speedometer
-- (SPEEDOMETER: his whole speed, falling included, low in the middle of the screen, in km/h or mph - "all of it",
-- 2026-11-09, from a list; written ten times a second. Along the ground only at first: "mph doesnt keep track of falling
-- speed".)
local speedo, speedo_t = nil, 0.0             -- { w, tb = its text, shown = bool, last = the text written }

local function build_speedo()
    local w, canvas = new_canvas()
    if not w then return nil end
    local tb = StaticConstructObject(cls("/Script/UMG.TextBlock"), canvas, FName("None"))
    pcall(function() local f = tb.Font; f.Size = 26; tb:SetFont(f) end)
    pcall(function() tb:SetColorAndOpacity({ SpecifiedColor = { R = 1.0, G = 1.0, B = 1.0, A = 0.9 }, ColorUseRule = 0 }) end)
    pcall(function() tb:SetShadowOffset({ X = 1.5, Y = 1.5 }) end)
    pcall(function() tb:SetShadowColorAndOpacity({ R = 0.0, G = 0.0, B = 0.0, A = 0.8 }) end)
    pcall(function() tb:SetJustification(1) end)                                     -- (centred)
    local s = canvas:AddChildToCanvas(tb)
    s:SetAnchors({ Minimum = { X = 0.5, Y = 1.0 }, Maximum = { X = 0.5, Y = 1.0 } })
    s:SetAlignment({ X = 0.5, Y = 1.0 })
    s:SetPosition({ X = 0.0, Y = -150.0 })
    s:SetAutoSize(true)
    pcall(function() w:SetVisibility(1) end)
    w:AddToViewport(41)
    log("hud: speedometer on the screen")
    return { w = w, tb = tb, shown = false, last = nil }
end

local function speedo_tick(dt, want, unit)
    if want and not (speedo and alive(speedo.w)) then
        local ok, d = pcall(build_speedo)
        speedo = ok and d or nil
        if not ok then log("hud: no speedometer (%s)", tostring(d)) end
    end
    if not (speedo and alive(speedo.w)) then return end
    if speedo.shown ~= want then
        pcall(function() speedo.w:SetVisibility(want and 3 or 1) end)
        speedo.shown = want
    end
    if not want then return end
    speedo_t = speedo_t - (dt or 0.016)
    if speedo_t > 0 then return end
    speedo_t = 0.1
    local p = lib.pawn()
    if not p then return end
    local cms = 0.0
    pcall(function() local v = p:GetVelocity(); cms = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end)
    local text = (unit == 2) and string.format("%d MPH", math.floor(cms * 0.0223694 + 0.5))
        or string.format("%d KM/H", math.floor(cms * 0.036 + 0.5))
    if text ~= speedo.last then
        pcall(function() speedo.tb:SetText(FText(text)) end)
        speedo.last = text
    end
end

-- ------------------------------------------------------------------ cinematic bars
-- (CINEMATIC BARS: black bars top and bottom, each up to BARS_MOST of the screen's height at 100% - a 2.39:1 film frame
-- on a 16:9 screen - "cinematic bars", 2026-11-09; under the crosshair and the speedometer)
local BARS_MOST = 0.128
local bars = nil                              -- { w, top = its slot, bottom = its slot, f = the share set, shown = bool }

local function build_bars()
    local w, canvas = new_canvas()
    if not w then return nil end
    local function bar()
        local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("None"))
        pcall(function() img:SetColorAndOpacity({ R = 0.0, G = 0.0, B = 0.0, A = 1.0 }) end)
        local s = canvas:AddChildToCanvas(img)
        s:SetPosition({ X = 0.0, Y = 0.0 })
        s:SetSize({ X = 0.0, Y = 0.0 })
        return s
    end
    local b = { w = w, top = bar(), bottom = bar(), f = nil, shown = false }
    pcall(function() w:SetVisibility(1) end)
    w:AddToViewport(30)
    log("hud: cinematic bars on the screen")
    return b
end

local function bars_tick(want, f)
    if want and not (bars and alive(bars.w)) then
        local ok, b = pcall(build_bars)
        bars = ok and b or nil
        if not ok then log("hud: no cinematic bars (%s)", tostring(b)) end
    end
    if not (bars and alive(bars.w)) then return end
    if want and bars.f ~= f then
        -- (stretched across, as tall as the share: anchored to the screen's own edges, so any screen size)
        pcall(function() bars.top:SetAnchors({ Minimum = { X = 0.0, Y = 0.0 }, Maximum = { X = 1.0, Y = f } }) end)
        pcall(function() bars.bottom:SetAnchors({ Minimum = { X = 0.0, Y = 1.0 - f }, Maximum = { X = 1.0, Y = 1.0 } }) end)
        bars.f = f
    end
    if bars.shown ~= want then
        pcall(function() bars.w:SetVisibility(want and 3 or 1) end)
        bars.shown = want
    end
end

-- ------------------------------------------------------------------ the HUD
local hud, hud_t, hud_hidden = nil, 0.0, false   -- (STORROR's LayerHUD, looked for again now and then)

local function find_hud()
    local WBL = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local list = {}
    WBL:GetAllWidgetsOfClass(lib.world(), list, cls("/Script/UMG.UserWidget"), true)
    for i = 1, #list do
        local w = list[i]
        pcall(function() if w.get then w = w:get() end end)
        if alive(w) and w:GetClass():GetFName():ToString():find("LayerManager") then
            local found = nil
            local function walk(x, depth)
                if found or depth > 4 or not alive(x) then return end
                if x:GetFName():ToString() == "LayerHUD" then found = x; return end
                local n = 0
                pcall(function() n = x:GetChildrenCount() end)
                for k = 0, n - 1 do local c = nil; pcall(function() c = x:GetChildAt(k) end); walk(c, depth + 1) end
            end
            walk(w.WidgetTree.RootWidget, 0)
            if found then return found end
        end
    end
    return nil
end

local function hud_tick(dt, want)
    hud_t = hud_t - (dt or 0.016)
    if not alive(hud) then
        if not want and not hud_hidden then return end
        if hud_t > 0 then return end
        hud_t = 2.0
        local ok, h = pcall(find_hud)
        hud = ok and h or nil
        if not hud then return end
    end
    if hud_hidden ~= want then
        pcall(function() hud:SetRenderOpacity(want and 0.0 or 1.0) end)
        hud_hidden = want
        log("hud: STORROR's HUD %s", want and "hidden" or "shown again")
    end
end

-- every frame: `fp_on` first person is the view, `menu_up` a menu of STORROR's is open
function M.tick(dt, fp_on, menu_up)
    pcall(dot_tick, fp_on and not menu_up and setting("crosshair", 0) >= 0.5)
    local unit = math.floor(setting("speedo", 0) + 0.5)
    pcall(speedo_tick, dt, fp_on and not menu_up and unit > 0, unit)
    local bf = math.max(0.0, math.min(1.0, setting("bars", 0) / 100.0)) * BARS_MOST
    pcall(bars_tick, fp_on and not menu_up and bf > 0.0005, bf)
    pcall(hud_tick, dt, fp_on and setting("hide_hud", 0) >= 0.5)
end

-- (a new map: the dot is the old map's, not touched again; STORROR's HUD is its game's, kept - hidden or not)
-- (STORROR's HUD too: a new map's is a new one - the old one never touched again)
function M.forget() dot = nil; speedo = nil; bars = nil; hud, hud_hidden = nil, false end

return M
