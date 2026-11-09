-- SM64Map screen transitions: Mario 64's shapes (render_textured_transition) closing the screen in on its middle
-- (WARP_TRANSITION_FADE_INTO_*) or opening it out from there (FADE_FROM_*). Shapes: "bowser" (a death), "circle"
-- (a fall off a course, doors), "star" (most arrivals), "mario" (a star's exit) - masks made from the game's own
-- transition pictures by exporter/irisx.py (textures/iris_<shape>.png: black, the shape see-through).
-- The screen stays black after a close until open() (or clear()); a scene can be rebuilt behind it.
local lib = require("lib")
local M = {}

local cur = nil         -- { ui, shape, t, dur, dir = "close"/"open", done }

local function texture_ok(world, file) return lib.texture(world, file) end

-- the picture: the mask in the middle, black bars all round it; or, for "white" and "black" (Mario 64's
-- WARP_TRANSITION_FADE_INTO_COLOR: teleports, paintings, the special warps), the whole screen in that colour, faded
local COLOURS = { white = true, black = true }
local function make_ui(shape)
    local world, pc = lib.world(), lib.controller()
    if not (world and pc) then return nil end
    local function cls(p) return StaticFindObject(p) end
    _G.SM64_TRANS_SERIAL = (_G.SM64_TRANS_SERIAL or 0) + 1
    local n = tostring(_G.SM64_TRANS_SERIAL)
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("SM64Trans" .. n))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("SM64TransTree" .. n))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SM64TransCanvas" .. n))
    tree.RootWidget = canvas
    local ui = { widget = w, bars = {}, shape = shape }
    if COLOURS[shape] then
        local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("SM64TransFill" .. n))
        local tex = texture_ok(world, shape)
        if tex then img:SetBrushFromTexture(tex, false) end
        local slot = canvas:AddChildToCanvas(img)
        slot:SetAnchors({ Minimum = { X = 0.0, Y = 0.0 }, Maximum = { X = 1.0, Y = 1.0 } })
        slot:SetOffsets({ Left = 0.0, Top = 0.0, Right = 0.0, Bottom = 0.0 })
        ui.fill, ui.full = img, 1.0
        ui.world = world:GetAddress()
        w:AddToViewport(80)
        return ui
    end
    local function image(name, file)
        local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("SM64Trans" .. name .. n))
        local tex = texture_ok(world, file)
        if tex then img:SetBrushFromTexture(tex, false) end
        return img, canvas:AddChildToCanvas(img)
    end
    local img, hole = image("Hole", "iris_" .. shape)
    hole:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
    hole:SetAlignment({ X = 0.5, Y = 0.5 })
    ui.hole, ui.img = hole, img
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
    -- (wide open: the shape well past the screen's corners - the circle and Mario's head fill only part of their square)
    ui.full = math.max(size.X, size.Y) * 2.6
    ui.world = world:GetAddress()
    w:AddToViewport(80)
    return ui
end

-- the shape `d` across (slate units); the bars close in to its edges. (A colour: `d` of `full` is see-through.)
local function set_size(ui, d)
    if ui.fill then
        pcall(function() ui.fill:SetRenderOpacity(1.0 - math.max(0.0, math.min(1.0, d))) end)
        return
    end
    local r = d * 0.5
    pcall(function()
        ui.hole:SetSize({ X = d, Y = d })
        ui.bars[1]:SetOffsets({ Left = 0.0, Top = 0.0, Right = r, Bottom = 0.0 })
        ui.bars[2]:SetOffsets({ Left = r, Top = 0.0, Right = 0.0, Bottom = 0.0 })
        ui.bars[3]:SetOffsets({ Left = 0.0, Top = 0.0, Right = 0.0, Bottom = r })
        ui.bars[4]:SetOffsets({ Left = 0.0, Top = r, Right = 0.0, Bottom = 0.0 })
    end)
end

local function drop()
    local c = cur
    cur = nil
    if c and c.ui then pcall(function() c.ui.widget:RemoveFromParent() end) end
end

local function same_world(c)
    local here = nil
    pcall(function() here = lib.world():GetAddress() end)
    return c and c.ui and c.ui.world == here
end

-- Close the screen in on its middle in `shape` over `frames` 30ths of a second; done() once it is black.
function M.close(shape, frames, done)
    drop()
    local ok, ui = pcall(make_ui, shape)
    if not (ok and ui) then lib.log("transition: no picture (%s)", tostring(ui)); if done then done() end; return end
    set_size(ui, ui.full)
    cur = { ui = ui, shape = shape, t = 0.0, dur = (frames or 16) / 30.0, dir = "close", done = done }
end

-- Open the screen out from its middle in `shape` (from black: from a close, or straight away).
function M.open(shape, frames)
    drop()
    local ok, ui = pcall(make_ui, shape)
    if not (ok and ui) then return end
    set_size(ui, 0.0)
    cur = { ui = ui, shape = shape, t = 0.0, dur = (frames or 16) / 30.0, dir = "open" }
end

-- black now (a scene is being swapped behind it)
function M.black()
    if cur and cur.dir == "close" and cur.t >= cur.dur then return end
    drop()
    local ok, ui = pcall(make_ui, "circle")
    if ok and ui then set_size(ui, 0.0); cur = { ui = ui, shape = "circle", t = 1.0, dur = 1.0, dir = "close" } end
end

function M.busy() return cur ~= nil end
function M.is_black() return cur ~= nil and cur.dir == "close" and cur.t >= cur.dur end

function M.clear() drop() end
-- the map went: its widget with it, forget it untouched
function M.forget() cur = nil end

function M.tick(dt)
    local c = cur
    if not c then return end
    if not same_world(c) then cur = nil; return end
    if c.dir == "close" and c.t >= c.dur then return end       -- (held black)
    c.t = math.min(c.dur, c.t + dt)
    local k = c.t / c.dur
    if c.dir == "close" then
        set_size(c.ui, c.ui.full * (1.0 - k))
        if k >= 1.0 then
            local done = c.done
            c.done = nil
            if done then pcall(done) end
        end
    else
        set_size(c.ui, c.ui.full * k)
        if k >= 1.0 then drop() end
    end
end

return M
