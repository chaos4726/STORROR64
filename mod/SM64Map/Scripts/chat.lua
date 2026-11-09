-- SM64Map: chat in a multiplayer game ("add a chat function for multiplayer by pressing enter on the keyboard",
-- 2026-11-04). In someone's game (mp.lua), Enter on the keyboard opens a line to type in at the bottom left - the keys
-- to it while it is up, so he stands still - and Enter again sends it to everyone in the game (mp.lua's events, "chat");
-- Escape, or an empty line, closes it unsent. The game's lines above it, name and words, each for KEEP s then fading
-- over FADE; while typing, all of the latest MAX. Ticked from mp.lua M.tick.
local lib = require("lib")
local log = lib.log

local M = {}
M.KEEP, M.FADE, M.MAX, M.LEN = 12.0, 1.5, 7, 120
M.WHITE, M.MINE = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }, { R = 1.0, G = 0.92, B = 0.35, A = 1.0 }

local ui = nil              -- { world, widget, lines = { TextBlock }, box, open, opened_at, shown = {} }
local lines = {}            -- { text, t, mine }
local was_enter = false

local function cls(p) return StaticFindObject(p) end
local function alive(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

local function build()
    local pc, world = lib.controller(), lib.world()
    if not (pc and world) then return nil end
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("SM64Chat"))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("SM64ChatTree"))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SM64ChatCanvas"))
    tree.RootWidget = canvas
    local vb = StaticConstructObject(cls("/Script/UMG.VerticalBox"), canvas, FName("SM64ChatLines"))
    local s = canvas:AddChildToCanvas(vb)
    s:SetAnchors({ Minimum = { X = 0.0, Y = 1.0 }, Maximum = { X = 0.0, Y = 1.0 } })
    s:SetAlignment({ X = 0.0, Y = 1.0 })
    s:SetAutoSize(true)
    s:SetPosition({ X = 40.0, Y = -150.0 })
    local tl = {}
    for i = 1, M.MAX do
        local t = StaticConstructObject(cls("/Script/UMG.TextBlock"), vb, FName("SM64ChatLine" .. i))
        pcall(function() t:SetText(FText("")) end)
        pcall(function() t:SetShadowOffset({ X = 2.0, Y = 2.0 }) end)
        pcall(function() t:SetShadowColorAndOpacity({ R = 0.0, G = 0.0, B = 0.0, A = 0.9 }) end)
        pcall(function() t:SetRenderOpacity(0.0) end)
        local ts = vb:AddChildToVerticalBox(t)
        pcall(function() ts:SetPadding({ Left = 0.0, Top = 2.0, Right = 0.0, Bottom = 2.0 }) end)
        tl[i] = t
    end
    local box = StaticConstructObject(cls("/Script/UMG.EditableTextBox"), canvas, FName("SM64ChatBox"))
    local bs = canvas:AddChildToCanvas(box)
    bs:SetAnchors({ Minimum = { X = 0.0, Y = 1.0 }, Maximum = { X = 0.0, Y = 1.0 } })
    bs:SetAlignment({ X = 0.0, Y = 1.0 })
    bs:SetPosition({ X = 40.0, Y = -100.0 })
    bs:SetSize({ X = 720.0, Y = 42.0 })
    pcall(function() box:SetHintText(FText("Say something...   (Enter: send   Esc: close)")) end)
    pcall(function() box.RevertTextOnEscape = true end)
    pcall(function() box.ClearKeyboardFocusOnCommit = true end)
    pcall(function() box:SetVisibility(1) end)                  -- (collapsed till Enter)
    w:AddToViewport(60)
    log("chat: on the screen")
    return { world = world:GetAddress(), widget = w, lines = tl, box = box, open = false, opened_at = 0.0, shown = {} }
end

local function add(name, text, mine)
    lines[#lines + 1] = { text = tostring(name) .. ": " .. tostring(text), t = os.clock(), mine = mine }
    while #lines > 40 do table.remove(lines, 1) end
end

-- (free to type: playing, no menu, message or cutscene up)
local function free()
    local MN, G = _G.MENU, package.loaded["game"]
    if not (MN and MN.state == "game") then return false end
    if G and (G.cutscene or G.pending or G.warping) then return false end
    local D, MPM, P = package.loaded["dialog"], package.loaded["mpmenu"], package.loaded["pause"]
    if D and D.active then return false end
    if MPM and (MPM.active or MPM.open_now) then return false end
    if P and P.active then return false end
    local open = false
    pcall(function()
        for _, wd in ipairs(FindAllOf("MenuPresenterBP_C") or {}) do
            if wd:IsValid() and wd:GetFullName():find("Transient", 1, true) and wd:IsActivated() then open = true end
        end
    end)
    return not open
end

local function wbl() return StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end
local function open_box()
    ui.open, ui.opened_at = true, os.clock()
    pcall(function() ui.box:SetText(FText("")) end)
    pcall(function() ui.box:SetVisibility(0) end)
    local pc = lib.controller()
    pcall(function() wbl():SetInputMode_UIOnlyEx(pc, ui.box, 0, false) end)
    pcall(function() ui.box:SetKeyboardFocus() end)
end
local function close_box()
    ui.open = false
    pcall(function() ui.box:SetVisibility(1) end)
    local pc = lib.controller()
    pcall(function() wbl():SetInputMode_GameOnly(pc, false) end)
end

local function send(text)
    text = tostring(text or ""):gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    text = text:sub(1, M.LEN)
    local MP = package.loaded["mp"]
    if MP and MP.send_event then MP.send_event("chat", text) end
    add((MP and MP.status and MP.status.myname) or "You", text, true)
    log("chat: sent %q", text)
end

function M.on_chat(from, body)
    local MP = package.loaded["mp"]
    local name = tostring(from)
    for _, m in ipairs((MP and MP.status and MP.status.members) or {}) do if m.id == from then name = m.name end end
    local text = tostring(body or ""):gsub("[%c]", " "):sub(1, M.LEN)
    if text == "" then return end
    add(name, text, false)
    local SX = package.loaded["sfx"]
    if SX and SX.play then pcall(SX.play, "menu_message_appear", 0.6) end
end

local function draw()
    local now = os.clock()
    local first = math.max(1, #lines - M.MAX + 1)
    for i = 1, M.MAX do
        local L = lines[first + i - 1]
        local t = ui.lines[i]
        local want, a, col = "", 0.0, M.WHITE
        if L then
            want, col = L.text, L.mine and M.MINE or M.WHITE
            local age = now - L.t
            a = ui.open and 1.0 or math.max(0.0, math.min(1.0, (M.KEEP + M.FADE - age) / M.FADE))
        end
        local sh = ui.shown[i]
        if not sh or sh.text ~= want then
            pcall(function() t:SetText(FText(want)) end)
            pcall(function() t:SetColorAndOpacity({ SpecifiedColor = col, ColorUseRule = 0 }) end)
            sh = { text = want, a = -1.0 }
            ui.shown[i] = sh
        end
        if math.abs(sh.a - a) > 0.02 then
            sh.a = a
            pcall(function() t:SetRenderOpacity(a) end)
        end
    end
end

function M.tick(dt)
    local MP = package.loaded["mp"]
    if MP and MP.on_event and MP.on_event.chat ~= M.on_chat then MP.on_event.chat = M.on_chat end
    local in_game = MP and MP.in_lobby and MP.in_lobby()
    local world = lib.world()
    if not world then return end
    if ui and (ui.world ~= world:GetAddress() or not alive(ui.widget) or not alive(ui.box)) then ui = nil end
    if not ui then
        if not in_game then return end
        ui = build()
        if not ui then return end
    end
    local pc = lib.controller()
    local enter = false
    pcall(function() enter = pc:IsInputKeyDown({ KeyName = FName("Enter") }) end)
    local pressed = enter and not was_enter
    was_enter = enter
    if not ui.open then
        if pressed and in_game and free() then open_box() end
    else
        -- (its keyboard focus gone: Enter sent it, or Escape put it back empty - or the game took the screen away)
        local focused = true
        pcall(function() focused = ui.box:HasKeyboardFocus() end)
        if (not focused and os.clock() - ui.opened_at > 0.2) or not in_game then
            local text = ""
            pcall(function() text = ui.box:GetText():ToString() end)
            close_box()
            if in_game then send(text) end
        end
    end
    draw()
end

-- (a new map: its widget went with it)
function M.forget() ui = nil end

return M
