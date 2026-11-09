-- SM64Map dialog box: one of Mario 64's messages (create_dialog_box, render_dialog_box), page by page, as the game
-- shows them: its see-through black box and white letters, where the message's own numbers put it on the 320 x 240
-- screen (pictures made from the ROM's font by exporter/dialogx.py: textures/dlg_<n>_<page>.png, data/dialogs.lua).
-- A turns the page (after a moment, as Mario 64 waits for the box to open), and closes it after the last; the
-- athlete's controls are held meanwhile and nothing hurts him (Mario 64 stops time for a message). A question (M.ask)
-- has two answers on its last page, an arrow by one: left and right move it, A gives it.
local lib = require("lib")
local pad = require("pad")
local log = lib.log
local M = { active = false }

local data, st = nil, nil
local PAGE_MIN = 0.3
local LOCK = "SM64Dialog"

local function sound(name) local S = package.loaded["sfx"]; if S then pcall(S.play, name) end end

-- the athlete's controls held (A is STORROR's jump: its parkour inputs have their own switch, and so does its walking
-- and running - its locomotion's, which went on while a sign was read: "when reading signs lock the charater",
-- 2026-10-16). `again`: held once
-- more while open - not the move input, which the engine counts (each "on" needs its own "off": held every tenth
-- of a second, it stayed held after the box closed)
local function lock(on, again)
    local pc, pawn = lib.controller(), lib.pawn()
    if not (pc and pawn) then return end
    if not again then pcall(function() pc:SetIgnoreMoveInput(on) end) end
    pcall(function() if on then pawn:DisableInput(pc) else pawn:EnableInput(pc) end end)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            local cname = o:GetClass():GetFName():ToString()
            if cname == "ParkourComponent" then
                o:ClearInputQueue()
                o:EnableAllParkourInputs(FName(LOCK), not on)
            elseif cname == "LocomotionComponent" then
                o:EnableLocomotionInputCallback(FName(LOCK), not on)
                o:EnableAdvancedLocomotionInput(FName(LOCK), not on)
            end
        end
    end)
    if on and not again then
        pcall(function() pawn.CharacterMovement:StopMovementImmediately() end)
        -- (and STORROR's locomotion told to start afresh: it keeps the last stick it was given and runs on it with its
        -- inputs off - held from a run, he ran on through Lakitu's words on the bridge: "when lakitu starts talking to
        -- you on the bridge the player can still move during dialog", 2026-10-20)
        local G = package.loaded["game"]
        if G and G.reset_athlete then pcall(G.reset_athlete, pawn, "held for a message") end
    elseif on then
        -- (held still across the ground while it is open: anything still carrying him along is stopped; a fall goes on)
        pcall(function()
            local cm = pawn.CharacterMovement
            local v = cm.Velocity
            if cm.MovementMode == 1 and (v.X * v.X + v.Y * v.Y) > 30.0 * 30.0 then cm.Velocity = { X = 0.0, Y = 0.0, Z = v.Z } end
        end)
    end
end

-- (`seq`: a box put together from several messages, page by page - { { id, page, box } ... } - else `id`'s own pages)
local function build(world, pc, id, count, box, choice, var, seq)
    local function cls(p) return StaticFindObject(p) end
    _G.SM64_DIALOG_SERIAL = (_G.SM64_DIALOG_SERIAL or 0) + 1
    local n = tostring(_G.SM64_DIALOG_SERIAL)
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("SM64Dialog" .. n))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("SM64DialogTree" .. n))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SM64DialogCanvas" .. n))
    tree.RootWidget = canvas
    local size = { X = 1920.0, Y = 1080.0 }
    pcall(function()
        local WLL = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        local vs, sc = WLL:GetViewportSize(world), WLL:GetViewportScale(world)
        if vs and sc and sc > 0 then size = { X = vs.X / sc, Y = vs.Y / sc } end
    end)
    local px = size.Y / 240.0
    local x0 = (size.X - 320.0 * px) / 2.0
    local pages = {}
    for i = 1, count do
        local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("SM64DialogPage" .. n .. "_" .. i))
        -- (a message with a number in, the star doors' "You need [%] more Stars": its page for that number,
        -- exporter/doornumx.py)
        local vnum = (type(var) == "number" or type(var) == "string") and var or nil
        local e = seq and seq[i]
        local pid, pno, pb = e and e.id or id, e and e.page or i, e and e.box or box
        local tex = vnum and lib.texture(world, "dlg_" .. pid .. "_" .. pno .. "_" .. vnum) or lib.texture(world, "dlg_" .. pid .. "_" .. pno)
        if tex then img:SetBrushFromTexture(tex, false) end
        local slot = canvas:AddChildToCanvas(img)
        slot:SetAnchors({ Minimum = { X = 0.0, Y = 0.0 }, Maximum = { X = 0.0, Y = 0.0 } })
        slot:SetPosition({ X = x0 + pb[1] * px, Y = pb[2] * px })
        slot:SetSize({ X = (pb[3] - pb[1]) * px, Y = (pb[4] - pb[2]) * px })
        img:SetRenderOpacity(i == 1 and 1.0 or 0.0)
        pages[i] = img
    end
    -- (times drawn into it: `var` { fill = { "1'54\"20", ... } }, one a line from data.fills[id] - letter by letter in the
    -- box's own lettering, tools/race_dialogs.py's dlg_glyph_*: the race's old and new times, race.lua)
    local fill = type(var) == "table" and var.fill or nil
    local at_fill = data and data.fills and data.fills[id]
    if fill and at_fill then
        local NAME = { ["'"] = "apos", ['"'] = "quote", ["."] = "dot", [":"] = "colon" }
        local k = 0
        for li, text in ipairs(fill) do
            local x, y = at_fill.x, at_fill.y[li]
            if y then
                for ch in tostring(text):gmatch(".") do
                    local name = NAME[ch] or ("d" .. ch)
                    local tex = lib.texture(world, "dlg_glyph_" .. name)
                    if tex then
                        k = k + 1
                        local g = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("SM64DialogGlyph" .. n .. "_" .. k))
                        g:SetBrushFromTexture(tex, false)
                        local gs = canvas:AddChildToCanvas(g)
                        gs:SetAnchors({ Minimum = { X = 0.0, Y = 0.0 }, Maximum = { X = 0.0, Y = 0.0 } })
                        gs:SetPosition({ X = x0 + x * px, Y = y * px })
                        gs:SetSize({ X = 8.0 * px, Y = 16.0 * px })
                    end
                    x = x + ((data.glyphs and data.glyphs[name]) or 7)
                end
            end
        end
    end
    local arrow, at = nil, nil
    if choice then
        -- (render_dialog_triangle_choice: by the first answer or the second, on the last page)
        arrow = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("SM64DialogArrow" .. n))
        local tex = lib.texture(world, "dlg_triangle")
        if tex then arrow:SetBrushFromTexture(tex, false) end
        local slot = canvas:AddChildToCanvas(arrow)
        slot:SetAnchors({ Minimum = { X = 0.0, Y = 0.0 }, Maximum = { X = 0.0, Y = 0.0 } })
        slot:SetSize({ X = 8.0 * px, Y = 8.0 * px })
        at = function(sel) slot:SetPosition({ X = x0 + choice[sel] * px, Y = choice[3] * px }) end
        at(1)
        arrow:SetRenderOpacity(count == 1 and 1.0 or 0.0)
    end
    w:AddToViewport(65)
    return { widget = w, pages = pages, arrow = arrow, arrow_at = at }
end

-- Show message `id` (its number: DIALOG_0xx); `done()` once it is read. False when there is no such message.
-- `ask`: a question - done(1) for its first answer, done(2) for its second.
-- Who speaks a message (audio/external.c sDialogSpeaker, sDialogSpeakerVoice, played by play_dialog_sound as the box
-- opens): their voice, and for Bowser's messages (the castle's welcome, the star doors) his tune under it; the cap
-- switches' messages get the puzzle jingle. (King Bob-omb's and Ukiki's are voiced where they speak, bobomb.lua and
-- enemies.lua.) (Every box opened in silence but for its own sound, 2026-10-15.)
local VOICE = {
    tuxie = "talk_penguin_yell", bows1 = "bowser_intro_laugh", koopa = "talk_koopa", boo = "en_boo_laugh_long",
    bomb = "talk_bobomb_buddy", bows2 = "bowser_laugh", grunt = "talk_boss_grunt", wiglr = "talk_wiggler", yoshi = "talk_yoshi",
    -- (the ghost racer's, Metal Mario talking as under water: tools/racer_voice.py - "next can you give the charater a
    -- voice when you talk to him, maybe like a sound of someone talking in water", 2026-10-27)
    racer = "talk_racer_1",
}
-- (his, one take a box as each comes up - three takes about, the one before cut short: he talks his way through)
local RACER_TAKES = 3
local function racer_voice(page)
    local S = package.loaded["sfx"]
    if not S then return end
    for i = 1, RACER_TAKES do pcall(S.stop, "talk_racer_" .. i) end
    if page then pcall(S.play, "talk_racer_" .. ((page - 1) % RACER_TAKES + 1)) end
end
local SPEAKER = { [9001] = "racer", [9002] = "racer", [9003] = "racer", [9004] = "racer", [9005] = "racer", [9006] = "racer" }    -- (the race's own: race.lua)
for id = 9100, 9399 do SPEAKER[id] = "racer" end      -- (and the eighteen ghosts' own words, tools/race_dialogs.py)
for id, who in pairs({ [1] = "bomb", [2] = "bomb", [3] = "bomb", [4] = "bomb", [5] = "koopa", [6] = "koopa", [7] = "koopa",
                       [9] = "koopa", [21] = "bows1", [22] = "bows1", [23] = "bows1", [24] = "bows1", [25] = "bows1",
                       [26] = "bows1", [27] = "bows1", [28] = "bows1", [29] = "bows1", [37] = "tuxie", [41] = "koopa",
                       [47] = "bomb", [55] = "tuxie", [56] = "tuxie", [57] = "tuxie", [58] = "tuxie", [59] = "tuxie",
                       [67] = "bows2", [85] = "boo", [90] = "bows2", [92] = "bows2", [93] = "bows2", [98] = "boo",
                       [99] = "boo", [105] = "bomb", [106] = "bomb", [107] = "boo", [108] = "boo", [114] = "grunt",
                       [115] = "grunt", [117] = "grunt", [118] = "grunt", [132] = "tuxie", [150] = "wiglr",
                       [151] = "wiglr", [152] = "wiglr", [161] = "yoshi", [168] = "wiglr" }) do
    SPEAKER[id] = who
end

-- (`var`: the number a message shows in its "[%]", Mario 64's dialog variable - the star doors')
function M.open(id, done, ask, var)
    if data == nil then
        data = lib.load_data("data.dialogs") or false
        -- (and the mod's own, past Mario 64's numbers: data/dialogs_extra.lua - the ghost racer's, tools/race_dialogs.py)
        local ex = data and lib.load_data("data.dialogs_extra")
        if ex then
            for k, t in pairs(ex) do
                data[k] = data[k] or {}
                for id, v in pairs(t) do data[k][id] = v end
            end
        end
    end
    -- (`id` may be a list: one box of their pages in turn, the question - if it asks - the last one's. The ghost racers'
    -- words are put together so: race.lua, "every ghost runners dialog should be different and dependant on ghosts you
    -- beat before", 2026-11-05)
    local seq, last = nil, id
    local count, box
    if type(id) == "table" then
        seq = {}
        for _, one in ipairs(id) do
            local c = data and data.pages and data.pages[one]
            local b = data and data.boxes and data.boxes[one]
            if c and b then
                for pg = 1, c do seq[#seq + 1] = { id = one, page = pg, box = b } end
                last = one
            end
        end
        if #seq == 0 then return false end
        count, box, id = #seq, seq[1].box, seq[1].id
    else
        count = data and data.pages and data.pages[id]
        box = data and data.boxes and data.boxes[id]
    end
    local choice = ask and data and data.choices and data.choices[last] or nil
    local world, pc = lib.world(), lib.controller()
    if not (count and box and world and pc) then return false end
    M.close(true)
    local ok, ui = pcall(build, world, pc, id, count, box, choice, var, seq)
    if not ok then log("dialog %d: %s", id, tostring(ui)); return false end
    st = { world = world:GetAddress(), id = id, ui = ui, count = count, page = 1, t = 0.0, relock = 0.1, done = done,
           sel = choice and 1 or nil }
    lock(true)
    pad.reset()
    sound("menu_message_appear")
    local who = SPEAKER[id]
    if who then sound(VOICE[who]) end
    if who == "bows1" then sound("koopa_message") end
    if id == 10 or id == 11 or id == 12 then sound("puzzle_jingle") end
    M.active = true
    log("dialog %d (%d page%s)", id, count, count == 1 and "" or "s")
    return true
end

-- Mario 64's questions (create_dialog_box_with_response): Koopa the Quick's race, the penguin's, Ukiki's
function M.ask(id, done) return M.open(id, done, true) end

function M.close(quiet)
    local s = st
    st = nil
    M.active = false
    if not s then return end
    local same = false
    pcall(function() same = lib.world():GetAddress() == s.world end)
    if not same then return end
    if s.ui then pcall(function() s.ui.widget:RemoveFromParent() end) end
    lock(false)
    if not quiet and s.done then pcall(s.done, s.sel) end
end

function M.forget() st = nil; M.active = false end

function M.tick(dt)
    local s = st
    if not s then return end
    local here = nil
    pcall(function() here = lib.world():GetAddress() end)
    if here ~= s.world then st = nil; M.active = false; return end
    s.t = s.t + dt
    s.relock = s.relock - dt
    if s.relock <= 0.0 then s.relock = 0.1; lock(true, true) end      -- (the pause screen gives the controls back)
    local HP = _G.HEALTH
    if HP then HP.grace = math.max(HP.grace or 0.0, 0.3) end
    if s.sel and s.page == s.count then
        -- (handle_menu_scrolling, MENU_SCROLL_HORIZONTAL: left and right, or a push of the stick, between the two)
        local d = 0
        if pad.pressed("left") then d = -1 elseif pad.pressed("right") then d = 1 end
        local sx = pad.sticks()
        if math.abs(sx) > 0.6 then
            if not s.stick then s.stick, d = true, (sx > 0 and 1 or -1) end
        else
            s.stick = nil
        end
        local n = math.max(1, math.min(2, s.sel + d))
        if n ~= s.sel then
            s.sel = n
            sound("menu_change_select")
            pcall(s.ui.arrow_at, n)
        end
    end
    -- (Y turns the page as A does, and answers on a question's last page: it skipped the whole message, and as Y is
    -- also what opens a sign, a sign was shut again at once - "presssing Y makes you exit signs instead of scrolling to
    -- the next message", 2026-10-16)
    local pressed = false
    if s.t >= PAGE_MIN then
        local okp = pad.pressed("ok")
        local skp = pad.pressed("skip")
        pressed = okp or skp
    end
    if not pressed then return end

    pcall(function() s.ui.pages[s.page]:SetRenderOpacity(0.0) end)
    s.page, s.t = s.page + 1, 0.0
    if s.page <= s.count then
        pcall(function() s.ui.pages[s.page]:SetRenderOpacity(1.0) end)
        if s.page == s.count and s.ui.arrow then pcall(function() s.ui.arrow:SetRenderOpacity(1.0) end) end
        sound("menu_message_next_page")
        if SPEAKER[s.id] == "racer" then racer_voice(s.page) end
        return
    end
    sound("menu_message_disappear")
    if SPEAKER[s.id] == "racer" then racer_voice(nil) end
    -- (only the box's own moment: a longer grace - after a hit - is not cut short)
    if HP and (HP.grace or 0.0) <= 0.3 then HP.grace = 0.0 end
    M.close(false)
end

return M
