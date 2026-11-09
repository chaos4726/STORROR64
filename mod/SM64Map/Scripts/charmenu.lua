-- SM64Map: the CHARACTER tab made anew ("just remake the entire charater menu so that it actually works", "make a brand
-- new menu", "remove charater top bottom shoes", "make it 4 slots that allows the player to cycle through the cloths",
-- "1 for the head, one for the chest, one for the legs, one for the feet", 2026-11-01).
--
-- STORROR's CHARACTER tab (MultiPageCharacterEditorWidgetBP_C: its sub-tabs Character, Top, Bottom, SHOES, each a grid
-- of tiles) gets a page of ours as a sub-tab of its own, picked, the four hidden and shut off and its sub-tab row out of
-- sight: STORROR's grids are gone from it, and the tab itself stays STORROR's (the pad's LT/RT reach it). Our page is
-- one of STORROR's audio pages, bare (as MARIO SETTINGS'), with four rows of its MUSIC row's kind: HEAD, CHEST, LEGS,
-- FEET. Up/Down picks a row, Left/Right goes through its choices - round from the last to the first - and he is
-- dressed in each as it comes up (a moment after the row stops). Each slot's choices: the mod's own (the characters'
-- and their clothes) and STORROR's own (its faces and clothes tables). What he wears is kept in character.lua beside the
-- save files and put back on him at a new start.
local lib = require("lib")
local log = lib.log

local M = {}
M.ON = true

local SUB_ID = "MarioSlots"
local PAGE_CLASS = "/SPP/UI/PauseMenu/Audio/CommonAudioMenuWidget.CommonAudioMenuWidget_C"
local STORROR_SUBS = { "Character", "Top", "Bottom", "SHOES" }
local FILE = lib.MOD_DIR .. "character.lua"
local SETTLE = 0.25                  -- (a choice put on once the row has stood this long on it)

-- the slots: STORROR's field each sets; their choices - a face (HEAD), one of the mod's clothes (`ours`, clothpick.lua's
-- key) or one of STORROR's own (`row`, its table's row name)
M.SLOTS = {
    { label = "HEAD", field = "SelectedCharacter", pkey = "head", opts = {
        { name = "MARIO", face = "Max" }, { name = "LUIGI", face = "Benj" }, { name = "WARIO", face = "Toby" },
        { name = "WALUIGI", face = "Drew" }, { name = "SACHA", face = "Sacha" },
        -- (the secrets Final Bowser opens, among each slot's own - secrets.lua: "???" till then, and not to be worn -
        -- caps.lua M.parts / M.hat: "it should be in the 4 slots in parts just like other cloths shoes pants shirt and
        -- head", 2026-11-04. On the head: Mario's face, in the skin; or Mario crowned)
        { name = "GHOST RUNNER", face = "Max", part = "ghost", secret = "ghost_runner" },
        { name = "RAINBOW", face = "Max", part = "rainbow", secret = "rainbow_skin" },
        { name = "CROWN", face = "Max", part = "ghost", hat = "crown", secret = "crown" } } },
    { label = "CHEST", field = "TorsoClothing", slot = "torso", pkey = "chest", opts = {
        { name = "MARIO SHIRT", ours = "torso" }, { name = "LUIGI SHIRT", ours = "torso_luigi" },
        { name = "WARIO SHIRT", ours = "torso_wario" }, { name = "WALUIGI SHIRT", ours = "torso_waluigi" },
        { name = "WHITE T-SHIRT", row = "White" }, { name = "BLACK T-SHIRT", row = "Black" },
        { name = "GREY T-SHIRT", row = "Grey" }, { name = "BLUE T-SHIRT", row = "Blue" },
        { name = "DRIZZLE WHITE", row = "DrizzleWhite" }, { name = "DRIZZLE BLACK", row = "DrizzleBlack" },
        -- (over what he wears there: the GHOST RUNNER's with its backpack)
        { name = "GHOST RUNNER", part = "ghost", secret = "ghost_runner" }, { name = "RAINBOW", part = "rainbow", secret = "rainbow_skin" } } },
    { label = "LEGS", field = "LegsClothing", slot = "legs", pkey = "legs", opts = {
        { name = "BROTHERS JEANS", ours = "legs" }, { name = "WARIO PANTS", ours = "legs_wario" },
        { name = "WALUIGI PANTS", ours = "legs_waluigi" },
        { name = "BLACK JOGGERS", row = "Black" }, { name = "GREY JOGGERS", row = "Grey" },
        { name = "BEIGE JOGGERS", row = "Beige" }, { name = "KHAKI JOGGERS", row = "Khaki" },
        { name = "GHOST RUNNER", part = "ghost", secret = "ghost_runner" }, { name = "RAINBOW", part = "rainbow", secret = "rainbow_skin" } } },
    { label = "FEET", field = "FeetClothing", slot = "feet", pkey = "feet", opts = {
        { name = "BROTHERS SHOES", ours = "feet" }, { name = "WARIO SHOES", ours = "feet_wario" },
        { name = "WALUIGI SHOES", ours = "feet_waluigi" },
        { name = "BLUE RUNNERS", row = "Blue" }, { name = "BLACK RUNNERS", row = "Black" },
        { name = "BLACK GUM RUNNERS", row = "BlackGum" }, { name = "WHITE RUNNERS", row = "White" },
        { name = "WHITE GUM RUNNERS", row = "WhiteGum" },
        { name = "GHOST RUNNER", part = "ghost", secret = "ghost_runner" }, { name = "RAINBOW", part = "rainbow", secret = "rainbow_skin" } } },
}
local function SECRETS() local ok, S = pcall(require, "secrets"); return ok and S or nil end
local function hidden(o) if not o.secret then return false end; local S = SECRETS(); return not (S and S.has(o.secret)) end
local function CAPSM() return package.loaded["caps"] end
local CHAR_OF = { Max = "mario", Benj = "luigi", Toby = "wario", Drew = "waluigi" }

local function alive(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end
local function MS() return package.loaded["msettings"] end
local function CL() return package.loaded["clothpick"] end
local function CH() return package.loaded["charhold"] end
local function LOOK() return package.loaded["mariolook"] end

local function edata()
    local d = nil
    pcall(function() d = lib.pawn().PlayerState.PlayerModel.RepCharacterEditorData end)
    return d
end
local function field(f)
    local CHm = CH()
    if f == "SelectedCharacter" and CHm and CHm.face then
        local hf = CHm.face()
        if hf then return hf end
    end
    local v = nil
    pcall(function() v = edata()[f]:ToString() end)
    return v
end

-- STORROR's update run on him (charhold.lua gives it the held values while its menu is up)
local function update_him()
    local pawn = lib.pawn()
    if not pawn then return end
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetClass():GetFName():ToString() == "CharacterEditorComponent" then o:UpdateCharacterFromPlayerState() end
        end
    end)
end
local function set_field(f, v)
    local d = edata()
    if not d then return end
    local CHm = CH()
    if CHm and CHm.set_held then pcall(CHm.set_held, f, v) end
    pcall(function() d[f] = v end)
    update_him()
end

-- ------------------------------------------------------------------ what he wears, kept
local saved = nil
local function load_saved()
    local f = io.open(FILE, "r")
    if not f then return nil end
    local src = f:read("a"); f:close()
    local fn = load(src, "character", "t", {})
    local ok, t = pcall(fn or function() end)
    return (ok and type(t) == "table") and t or nil
end
local function save_now()
    local t = {}
    for _, s in ipairs(M.SLOTS) do t[s.field] = field(s.field) end
    -- (the skins on his parts and his hat: caps.lua)
    local C = package.loaded["caps"]
    for _, s in ipairs(M.SLOTS) do if s.pkey then t["Skin_" .. s.pkey] = (C and C.parts and C.parts[s.pkey]) or "none" end end
    t.Hat = (C and C.hat) or "none"
    local f = io.open(FILE, "w")
    if not f then log("could not write %s", FILE); return end
    local parts = {}
    for k, v in pairs(t) do parts[#parts + 1] = string.format("%s = %q", k, v or "") end
    f:write("-- SM64Map: what he wears, from the CHARACTER tab's slots (written by the mod)\nreturn { ",
        table.concat(parts, ", "), " }\n")
    f:close()
    saved = t
end

-- ------------------------------------------------------------------ the slots' choices put on him
local look_at, look_char = nil, nil
local function set_face(face)
    if field("SelectedCharacter") == face then return end
    local L = LOOK()
    -- (the look off first - his hair shown before the face changes: hidden hair under a changed face crashed the game)
    if L and L.on() then pcall(L.remove) end
    set_field("SelectedCharacter", face)
    local ch = CHAR_OF[face]
    local C = package.loaded["charpick"]
    if C and C.set_face then pcall(C.set_face, ch) end
    if C and C.mx then C.mx.pick, C.mx.pick_at = face, nil end
    look_at, look_char = ch and (os.clock() + 0.6) or nil, ch
end

local function current(s)
    -- (a skin on the slot's part, or the crown on his head: that one)
    local C = CAPSM()
    -- (the hat first: the CROWN is the GHOST RUNNER's head with it)
    if s.pkey == "head" and C and C.hat then for i, o in ipairs(s.opts) do if o.hat == C.hat then return i end end end
    local pk = C and C.parts and s.pkey and C.parts[s.pkey]
    if pk then for i, o in ipairs(s.opts) do if o.part == pk and not o.hat then return i end end end
    if s.field == "SelectedCharacter" then
        local f = field(s.field)
        for i, o in ipairs(s.opts) do if o.face == f then return i end end
        return 1
    end
    local CLm = CL()
    local k = CLm and CLm.chosen_in and CLm.chosen_in(s.slot)
    if k then
        for i, o in ipairs(s.opts) do if o.ours == k then return i end end
    end
    local v = field(s.field)
    for i, o in ipairs(s.opts) do if o.row and o.row == v then return i end end
    return 1
end

local function put_on(s, i)
    local o = s.opts[i]
    if not o then return end
    if hidden(o) then log("character tab: %s - %s is still a secret", s.label, o.name); return end
    -- (the slot's part's skin, and on the head the hat: as the choice has them - none for the slot's own clothes)
    do
        local C = CAPSM()
        if C and C.set_part and s.pkey then pcall(C.set_part, s.pkey, o.part) end
        if C and C.set_hat and s.pkey == "head" then pcall(C.set_hat, o.hat) end
        if C and C.skin_refresh and not o.part then pcall(C.skin_refresh) end
    end
    if o.part and not o.face then
        -- (a skin over what he wears there: his clothes as they are)
        log("character tab: %s - %s", s.label, o.name)
        if not M.human_kept() then save_now() end
        return
    end
    if o.face then
        set_face(o.face)
    elseif o.ours then
        local CLm = CL()
        if CLm and CLm.choose_key then pcall(CLm.choose_key, o.ours) end
    else
        local CLm = CL()
        if CLm and CLm.unchoose_slot then pcall(CLm.unchoose_slot, s.slot) end
        if field(s.field) ~= o.row then set_field(s.field, o.row) else update_him() end
    end
    log("character tab: %s - %s", s.label, o.name)
    if not M.human_kept() then save_now() end
end

-- ------------------------------------------------------------------ the page
-- (by the CHARACTER tab's page's address: { cw, page, name, rows = { slot index -> row }, shown = { i -> choice } })
local PAGES = _G.SM64_CHARMENU or {}
_G.SM64_CHARMENU = PAGES
local WRAP = 1                        -- (the slider's ends beyond the choices: stepping onto one goes round)

-- Each slot shown as a card: the choice's name over its photo ("I want photos of the cloths with the name above them
-- instead of just text", 2026-11-01). The mod's own from its button pictures (textures/), STORROR's own from the
-- pictures its old tiles wore (its grids are still made, out of sight: their tiles' pictures, by name).
local OURS_PHOTO = {
    torso = "shirt_thumb.png", torso_luigi = "shirt_thumb_luigi.png", torso_wario = "shirt_thumb_wario.png",
    torso_waluigi = "shirt_thumb_waluigi.png", legs = "jeans_thumb.png", legs_wario = "jeans_thumb_wario.png",
    legs_waluigi = "jeans_thumb_waluigi.png", feet = "shoes_thumb.png", feet_wario = "shoes_thumb_wario.png",
    feet_waluigi = "shoes_thumb_waluigi.png",
}
local FACE_PHOTO = { Max = "mario_face_thumb.png", Benj = "luigi_face_thumb.png", Toby = "wario_face_thumb.png",
                     Drew = "waluigi_face_thumb.png", Sacha = "@SachaThumbnail" }
local ROW_PHOTO = {
    TorsoClothing = { White = "WhitePhaseShirtThumb2", Black = "BlackHandShirtThumbnail", Grey = "GreyHandShirtThumbnail",
                      Blue = "BlueHandShirtThumbnail", DrizzleWhite = "DrizzleWhiteShirtThumbnail",
                      DrizzleBlack = "DrizzleBlackShirtThumbnail" },
    LegsClothing = { Black = "BlackJoggersThumbnail", Grey = "WhiteJoggersThumbnail", Beige = "BeigeJoggersThumbnail",
                     Khaki = "KhakiJoggersThumbnail" },
    FeetClothing = { Blue = "BlueRunners", Black = "BlackRunners", BlackGum = "BlackGumRunners", White = "WhiteRunners",
                     WhiteGum = "WhiteGumRunners" },
}
local PHOTO = 150                     -- (its size, in the menu's own units: 1920 x 1080 across the screen)
local files_tex, files_world = {}, nil
local storror_tex, scan_t = {}, 0.0
local function file_tex(file)
    local w = lib.world()
    local wa = w and w:GetAddress()
    if wa ~= files_world then files_tex, files_world = {}, wa end
    local t = files_tex[file]
    if alive(t) then return t end
    -- (kept by lib's holder: made once, not each time the tab comes back)
    t = lib.file_texture(w, "textures\\" .. file)
    if alive(t) then files_tex[file] = t; return t end
    return nil
end
-- STORROR's pictures, by name: looked for on its tiles (a second apart at most)
local function storror_photo(name)
    local t = storror_tex[name]
    if alive(t) then return t end
    if os.clock() < scan_t then return nil end
    scan_t = os.clock() + 1.0
    for _, g in ipairs(FindAllOf("SPPGridTabWidgetBP_C") or {}) do
        pcall(function()
            if not g:IsValid() then return end
            local rh = g.Grid.RowHolder
            for r = 0, rh:GetChildrenCount() - 1 do
                local row = rh:GetChildAt(r)
                for c = 0, row:GetChildrenCount() - 1 do
                    local it = row:GetChildAt(c)
                    pcall(function()
                        local ro = it.Thumbnail.Brush.ResourceObject
                        if ro and ro:IsValid() then storror_tex[ro:GetFName():ToString()] = ro end
                    end)
                end
            end
        end)
    end
    t = storror_tex[name]
    return alive(t) and t or nil
end
local SKIN_PHOTO = { ghost = "skin_ghost_thumb.png", rainbow = "skin_rainbow_thumb.png", crown = "hat_crown_thumb.png" }
local function photo_of(s, o)
    local key = nil
    -- (the secrets: a photo of him in the whole skin, framed on the slot's own part as the clothes' photos are - head,
    -- chest, pants, feet: textures/skin_<skin>_<part>_thumb.png, taken in the game - "a photo of the head chest pants and
    -- feet", 2026-11-04)
    if o.secret then key = hidden(o) and "skin_locked_thumb.png" or string.format("skin_%s_%s_thumb.png", o.hat or o.part, s.pkey or "head")
    elseif o.face then key = FACE_PHOTO[o.face]
    elseif o.ours then key = OURS_PHOTO[o.ours]
    else key = ROW_PHOTO[s.field] and ROW_PHOTO[s.field][o.row] end
    if not key then return nil end
    if key:sub(1, 1) == "@" then return storror_photo(key:sub(2)) end
    if not key:find("%.png$") then return storror_photo(key) end
    return file_tex(key)
end

-- the card in a row, made once: the row's own value box (its text, msettings own_value) holds the name over the photo;
-- its unseen slider's box narrowed, so that the card stands by the slot's name
local CARDS = _G.SM64_CHARCARDS or {}
_G.SM64_CHARCARDS = CARDS
local function card_of(row, tv)
    local key = row:GetAddress()
    local c = CARDS[key]
    if c and alive(c.img) and alive(c.vb) then return c end
    CARDS[key] = nil
    local sbox = tv:GetParent()
    if not (alive(sbox) and sbox:GetClass():GetFName():ToString() == "SizeBox") then return nil end
    local WT = row.WidgetTree
    local vb = StaticConstructObject(StaticFindObject("/Script/UMG.VerticalBox"), WT, FName("MarioCard"))
    local img = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), WT, FName("MarioPhoto"))
    if not (alive(vb) and alive(img)) then return nil end
    sbox:SetContent(vb)
    local ts = vb:AddChildToVerticalBox(tv)
    pcall(function() ts:SetHorizontalAlignment(2) end)                -- (centred)
    pcall(function() ts:SetPadding({ Left = 0.0, Top = 6.0, Right = 0.0, Bottom = 4.0 }) end)
    pcall(function() tv:SetJustification(1) end)
    local is = vb:AddChildToVerticalBox(img)
    pcall(function() is:SetHorizontalAlignment(2) end)
    pcall(function() is:SetPadding({ Left = 0.0, Top = 0.0, Right = 0.0, Bottom = 10.0 }) end)
    pcall(function() img:SetDesiredSizeOverride({ X = PHOTO, Y = PHOTO }) end)
    pcall(function() img:SetVisibility(4) end)                        -- (seen, not hit-tested)
    pcall(function() vb:SetVisibility(4) end)
    pcall(function() sbox:SetWidthOverride(360) end)
    pcall(function()
        local sb0 = WT:FindWidget(FName("SizeBox_0"))
        if alive(sb0) then sb0:SetWidthOverride(40) end
    end)
    c = { vb = vb, img = img, shown = nil }
    CARDS[key] = c
    log("character tab: a card on a row")
    return c
end

local function text_of(row, s, i)
    local MSm = MS()
    local tv = nil
    if MSm and MSm.own_value then local ok, t = pcall(MSm.own_value, row); if ok then tv = t end end
    tv = tv or row.SliderValue
    local want = "<  " .. (hidden(s.opts[i]) and "???" or s.opts[i].name) .. "  >"
    pcall(function() if tv:GetText():ToString() ~= want then tv:SetText(FText(want)) end end)
    -- (and its photo under it)
    local okc, c = pcall(card_of, row, tv)
    if okc and c then
        local o = s.opts[i]
        local shown = hidden(o) and "?" or o
        if c.shown ~= shown then
            local t = photo_of(s, o)
            if t then
                pcall(function() c.img:SetBrushFromTexture(t, false) end)
                pcall(function() c.img:SetDesiredSizeOverride({ X = PHOTO, Y = PHOTO }) end)
                c.shown = shown
            end
        end
    end
end
local function slider_at(row, i)
    pcall(function() if math.abs(row.Slider:GetValue() - i) > 0.01 then row.Slider:SetValue(i) end end)
end

-- the page in one CHARACTER tab: made once; each look, STORROR's four sub-tabs hidden and shut off, ours picked, the
-- sub-tab row out of sight
local function setup(cw)
    local sub, asw = cw.MenuTabBar, cw.AnimatedSwitcher
    if not (alive(sub) and alive(asw)) then return end
    local key = cw:GetAddress()
    local e = PAGES[key]
    if e and not (alive(e.page) and e.name == cw:GetFName():ToString()) then PAGES[key] = nil; e = nil end
    if not alive(sub:GetTabButtonBaseByID(FName(SUB_ID))) then
        local ref = sub:GetTabButtonBaseByID(FName("Character"))
        if not alive(ref) then return end
        local WBL = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        local cls = StaticFindObject(PAGE_CLASS)
        if not alive(cls) then pcall(function() cls = LoadAsset(PAGE_CLASS) end) end
        if not (WBL and alive(cls)) then return end
        local page = WBL:Create(lib.world(), cls, ref:GetOwningPlayer())
        if not alive(page) then return end
        if asw:GetChildIndex(page) < 0 then asw:AddChild(page) end
        sub:RegisterTab(FName(SUB_ID), ref:GetClass(), page, -1)
        e = { cw = cw, page = page, name = cw:GetFName():ToString(), rows = nil, shown = {} }
        PAGES[key] = e
        log("character tab: the slots page on %s", e.name)
    end
    for _, id in ipairs(STORROR_SUBS) do
        pcall(function()
            local b = sub:GetTabButtonBaseByID(FName(id))
            if alive(b) and (b:GetIsEnabled() or b:GetVisibility() ~= 1) then
                sub:SetTabVisibility(FName(id), 1)
                sub:SetTabEnabled(FName(id), false)
            end
        end)
    end
    if sub:GetSelectedTabId():ToString() ~= SUB_ID then sub:SelectTabByID(FName(SUB_ID), true) end
    if sub:GetVisibility() ~= 1 then sub:SetVisibility(1) end
    -- the rows: once the page's own are there to make ours from; its own put away and out of its buttons
    if e and not e.rows then
        local MSm = MS()
        local part = MSm and MSm.part
        if not part then return end
        local box, mus = part(e.page, "VerticalBox"), part(e.page, "MusicVolumeSlider")
        if not (alive(box) and alive(mus)) then return end
        local WBL = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        local g = box.ButtonGroup
        for i = 0, box:GetChildrenCount() - 1 do
            local c = box:GetChildAt(i)
            if alive(c) then
                c:SetVisibility(1)
                pcall(function() if alive(g) and g:FindButtonIndex(c) >= 0 then g:RemoveWidget(c) end end)
            end
        end
        local ms = mus.Slot
        local rows = {}
        for si, s in ipairs(M.SLOTS) do
            local r = WBL:Create(lib.world(), mus:GetClass(), mus:GetOwningPlayer())
            r.SettingsName = FText(s.label)
            local slot = box:AddChildToVerticalBox(r)
            pcall(function()
                slot:SetPadding(ms.Padding); slot:SetHorizontalAlignment(ms.HorizontalAlignment)
                slot:SetVerticalAlignment(ms.VerticalAlignment); slot:SetSize(ms.Size)
            end)
            pcall(function() r.Title:SetText(FText(s.label)) end)
            -- (its places: the choices, and one beyond each end to go round; the bar of dots and the slider unseen -
            -- only the choice's name, as MARIO SETTINGS' ON/OFF rows show theirs)
            pcall(function() local b = r.Slider; b:SetMinValue(1 - WRAP); b:SetMaxValue(#s.opts + WRAP); b:SetStepSize(1.0) end)
            pcall(function() r.ProgressBar:SetVisibility(1) end)
            pcall(function() r.Slider:SetRenderOpacity(0.0) end)
            pcall(function() r.SliderSpeedRatio = mus.SliderSpeedRatio end)
            if alive(g) then g:AddWidget(r) end
            local i = current(s)
            slider_at(r, i)
            text_of(r, s, i)
            e.shown[si] = i
            rows[si] = r
        end
        if alive(g) then pcall(function() g:SelectButtonAtIndex(0, false) end) end
        e.rows = rows
        log("character tab: HEAD, CHEST, LEGS, FEET on %s", e.name)
    end
end

-- the CHARACTER tabs up now (each of STORROR's top tab bars' pages)
local function character_tabs()
    local out = {}
    for _, bar in ipairs(FindAllOf("PauseMenuTabBarBP_C") or {}) do
        pcall(function()
            if not bar:IsValid() or bar:GetFName():ToString():find("^Default__") then return end
            local sw = bar:GetLinkedSwitcher()
            if not alive(sw) then return end
            for i = 0, sw:GetChildrenCount() - 1 do
                local c = sw:GetChildAt(i)
                if alive(c) and c:GetClass():GetFName():ToString() == "MultiPageCharacterEditorWidgetBP_C" then
                    out[#out + 1] = { bar = bar, cw = c }
                end
            end
        end)
    end
    return out
end

-- The page's look ("remove the head chest legs and feet on the left side of the screen, bring the selection up and to
-- the left a tiny bit", 2026-11-01): the slot names' box collapsed and STORROR's mark by them unseen; the cards a
-- little up and to the left (the column moved as drawn - a render translation, the keys and the mouse with it); the
-- card of the slot picked out full, the others dimmed - with the names gone, that shows which one Left/Right moves.
local MOVE_X, MOVE_Y = 110.0, 70.0
local DIM = 0.45
local function style_page(e)
    local box = e.page.VerticalBox
    if not alive(box) then return end
    if not e.moved then
        pcall(function() box:SetRenderTranslation({ X = -MOVE_X, Y = -MOVE_Y }) end)
        e.moved = true
    end
    local g = box.ButtonGroup
    local sel = (alive(g) and g:GetSelectedButtonIndex()) or 0
    -- (the rows past FEET - SKIN and HAT - drawn as a second column, to the left of the first and level with HEAD and
    -- CHEST: under FEET they were off the bottom of the screen - "I dont see the ghost runner skin in there",
    -- 2026-11-04. Drawn there only - a render translation - the pad's Up/Down order is the same)
    if #e.rows > 4 and not e.col2 then
        pcall(function()
            local r1 = e.rows[1]
            local h = r1:GetDesiredSize().Y
            local pd = r1.Slot.Padding
            h = h + (pd.Top or 0.0) + (pd.Bottom or 0.0)
            if h > 10.0 then
                for si = 5, #e.rows do
                    if alive(e.rows[si]) then e.rows[si]:SetRenderTranslation({ X = -430.0, Y = -4.0 * h }) end
                end
                e.col2 = h
            end
        end)
    end
    for si, row in ipairs(e.rows) do
        if alive(row) then
            pcall(function()
                local hb = row.Title:GetParent()
                if alive(hb) and hb:GetVisibility() ~= 1 then hb:SetVisibility(1) end
            end)
            pcall(function()
                local m = row.WidgetTree:FindWidget(FName("SelectorImage"))
                if alive(m) and m:GetRenderOpacity() > 0.0 then m:SetRenderOpacity(0.0) end
            end)
            local c = CARDS[row:GetAddress()]
            if c and alive(c.vb) then
                local want = (si - 1 == sel) and 1.0 or DIM
                pcall(function() if math.abs(c.vb:GetRenderOpacity() - want) > 0.01 then c.vb:SetRenderOpacity(want) end end)
            end
        end
    end
end

-- each frame the menu is up: our rows read (a choice put on once its row has stood a moment), the keys' focus on our
-- page while its tab is on
local pend = {}                       -- slot index -> { i, t }
local function read_rows(open_t)
    local now = os.clock()
    for key, e in pairs(PAGES) do
        pcall(function()
            if not (alive(e.page) and e.rows) then return end
            if not e.page:IsVisible() then return end
            pcall(style_page, e)
            -- (the keys to our page: STORROR's many-page widget gives the page none of its own)
            if not e.page:HasFocusedDescendants() then
                local box = e.page.VerticalBox
                local g = alive(box) and box.ButtonGroup
                local i = (g and g:GetSelectedButtonIndex()) or 0
                if i < 0 or i >= #e.rows then i = 0 end
                local r = e.rows[i + 1]
                if alive(r) then r:SetFocus() end
            end
            for si, s in ipairs(M.SLOTS) do
                local row = e.rows[si]
                if alive(row) then
                    local v = math.floor(row.Slider:GetValue() + 0.5)
                    -- (as the menu opens: shown as he is, whatever the page does to its rows as it fills them)
                    if open_t < 0.4 then
                        v = current(s)
                        slider_at(row, v)
                    end
                    -- (round from either end)
                    -- (the way it moved, before it goes round)
                    local prev = e.shown[si] or v
                    local dir = (v < prev) and -1 or 1
                    if v < 1 then v = #s.opts; slider_at(row, v) elseif v > #s.opts then v = 1; slider_at(row, v) end
                    -- (a secret not yet open is not there at all - passed over the way he moved: "dont ruin the suprise by
                    -- having other hidden skins showing", 2026-11-04)
                    if s.opts[v] and hidden(s.opts[v]) then
                        local guard = 0
                        while s.opts[v] and hidden(s.opts[v]) and guard < #s.opts do
                            v = v + dir
                            if v < 1 then v = #s.opts elseif v > #s.opts then v = 1 end
                            guard = guard + 1
                        end
                        slider_at(row, v)
                    end
                    if v ~= e.shown[si] then
                        e.shown[si] = v
                        pend[si] = { i = v, t = now }
                    end
                    text_of(row, s, v)
                end
            end
        end)
    end
    for si, p in pairs(pend) do
        if now - p.t >= SETTLE then
            pend[si] = nil
            local s = M.SLOTS[si]
            if current(s) ~= p.i or s.field == "SelectedCharacter" then pcall(put_on, s, p.i) end
        end
    end
end

-- ------------------------------------------------------------------ every tick (from charpick.lua)
local was_open, open_t, look_t = false, 0.0, 0.0
local restore_t, restored_for = 0.0, nil
function M.tick(dt, menu_open)
    if not M.ON then return end
    -- (charhold.lua keeps holding him as he is while the menu is up - its watch on STORROR's grids off: they are gone)
    local CHm = CH()
    if CHm then CHm.WATCH = false end
    if menu_open then
        if not was_open then open_t, look_t = 0.0, 0.0 end
        open_t = open_t + dt
        look_t = look_t - dt
        if look_t <= 0 then
            look_t = (open_t < 1.5) and 0.05 or 0.5
            for _, t in ipairs(character_tabs()) do pcall(setup, t.cw) end
        end
        pcall(read_rows, open_t)
    else
        -- (the menu shut: a choice still waiting put on now)
        if was_open then
            for si, p in pairs(pend) do pcall(put_on, M.SLOTS[si], p.i) end
            pend = {}
        end
        -- (a new start: what he wore put back on him, once he has stood a moment)
        local pawn = lib.pawn()
        local pa = pawn and pawn:GetAddress()
        if pa and pa ~= restored_for then
            restore_t = restore_t + dt
            if restore_t > 2.0 then
                restored_for, restore_t = pa, 0.0
                saved = saved or load_saved()
                if M.human_kept() then
                    -- (HUMAN MODE: the plain athlete again, not what he wears as Mario: M.human_tick)
                    pcall(M.wear_human)
                elseif saved then
                    for _, s in ipairs(M.SLOTS) do
                        local want = saved[s.field]
                        if want and want ~= "" and field(s.field) ~= want then
                            if s.field == "SelectedCharacter" then set_face(want) else set_field(s.field, want) end
                            log("character tab: %s put back (%s)", s.label, want)
                        end
                    end
                else
                    save_now()
                end
                -- (and the skins on his parts and his hat, as long as their secrets are open)
                if saved and not M.human_kept() then
                    local C = CAPSM()
                    for _, s in ipairs(M.SLOTS) do
                        local want = s.pkey and saved["Skin_" .. s.pkey]
                        if want and want ~= "none" and C and C.set_part then
                            for _, o in ipairs(s.opts) do
                                if o.part == want and not hidden(o) then pcall(C.set_part, s.pkey, want); log("character tab: %s put back (%s)", s.label, o.name) end
                            end
                        end
                    end
                    local hw = saved.Hat
                    if hw and hw ~= "none" and C and C.set_hat then
                        for _, o in ipairs(M.SLOTS[1].opts) do if o.hat == hw and not hidden(o) then pcall(C.set_hat, hw) end end
                    end
                end
            end
        end
    end
    was_open = menu_open
    if not menu_open then pcall(M.human_tick, dt) end
    -- (a character's look on again once its face is on)
    if look_at and os.clock() > look_at then
        look_at = nil
        local L = LOOK()
        if L and look_char and not L.on() then
            if L.set_char then L.set_char(look_char) end
            pcall(L.apply)
        end
    end
end

-- ------------------------------------------------------------------ HUMAN MODE: a plain athlete
-- "on startup of human mode turn mario fx sound all the way down and start the character as sacha white t-shirt black
-- joggers and white runners", 2026-11-03. A file in HUMAN MODE (menu.lua M.human_on) plays as STORROR's Sacha in a
-- white T-shirt, black joggers and white runners - none of the mod's clothes, no Mario look - with MARIO FX (Mario's
-- voice and sounds: menu.lua's jump_voice) at nothing. What he was before - his face, his rows, the mod's clothes on
-- him, MARIO FX - is kept in character_human.lua and given back as a file without it is played (kept on disk: a restart
-- between gives it back all the same). Changed in the CHARACTER tab meanwhile, it is not kept as Mario's (put_on).
M.HUMAN = { face = "Sacha", TorsoClothing = "White", LegsClothing = "Black", FeetClothing = "White" }
local HFILE = lib.MOD_DIR .. "character_human.lua"
local HROWS = { "TorsoClothing", "LegsClothing", "FeetClothing" }
local HSLOTS = { "torso", "legs", "feet" }
local human, human_read = nil, false
local human_t = 0.0
local function human_load()
    if human_read then return end
    human_read = true
    local f = io.open(HFILE, "r")
    if not f then return end
    local src = f:read("a"); f:close()
    local fn = load(src, "character_human", "t", {})
    local ok, t = pcall(fn or function() end)
    if ok and type(t) == "table" then human = t end
end
local function human_save()
    if not human then os.remove(HFILE); return end
    local f = io.open(HFILE, "w")
    if not f then log("could not write %s", HFILE); return end
    local function q(v) return v and string.format("%q", v) or "nil" end
    local ours = {}
    for _, k in ipairs(HSLOTS) do ours[#ours + 1] = string.format("%s = %s", k, q(human.ours and human.ours[k] or nil)) end
    local rows = {}
    for _, r in ipairs(HROWS) do rows[#rows + 1] = string.format("%s = %s", r, q(human.rows and human.rows[r] or nil)) end
    f:write("-- SM64Map: what he was before HUMAN MODE made him a plain athlete (written by the mod)\nreturn { face = ",
        q(human.face), ", fx = ", tostring(human.fx or 1.0), ", ours = { ", table.concat(ours, ", "), " }, rows = { ",
        table.concat(rows, ", "), " } }\n")
    f:close()
end
function M.human_kept() human_load(); return human ~= nil end

-- Sacha in a white T-shirt, black joggers and white runners
function M.wear_human()
    local CLm = CL()
    for _, k in ipairs(HSLOTS) do if CLm and CLm.unchoose_slot and CLm.chosen_in and CLm.chosen_in(k) then pcall(CLm.unchoose_slot, k) end end
    set_face(M.HUMAN.face)
    for _, r in ipairs(HROWS) do if field(r) ~= M.HUMAN[r] then set_field(r, M.HUMAN[r]) end end
end

function M.human_tick(dt)
    local MN = _G.MENU
    if not (MN and MN.state == "game" and MN.human_on and lib.pawn()) then human_t = 0.0; return end
    -- (a moment into the file first: his body and STORROR's data for it there)
    human_t = human_t + (dt or 0.016)
    if human_t < 1.0 then return end
    human_load()
    local want = MN.human_on()
    if want and not human then
        local CLm = CL()
        human = { face = field("SelectedCharacter"), ours = {}, rows = {}, fx = MN.jump_voice and MN.jump_voice() or 1.0 }
        for _, k in ipairs(HSLOTS) do human.ours[k] = CLm and CLm.chosen_in and CLm.chosen_in(k) or nil end
        for _, r in ipairs(HROWS) do human.rows[r] = field(r) end
        -- (already the plain athlete - dressed so by hand before this came - then Mario is what a file without HUMAN MODE
        -- gives back: his face, shirt, jeans and shoes, and his sounds)
        if human.face == M.HUMAN.face then
            human = { face = "Max", ours = { torso = "torso", legs = "legs", feet = "feet" }, rows = {}, fx = 1.0 }
        end
        if not human.fx or human.fx <= 0.0 then human.fx = 1.0 end
        human_save()
        M.wear_human()
        -- (MARIO FX no longer turned down for it: "wheres the mario sounds in settings for gamemode human?", "fix the mario
        -- audio", 2026-11-04 - left where the player has it)
        log("HUMAN MODE: a plain athlete - Sacha, white T-shirt, black joggers, white runners")
    elseif not want and human then
        local h = human
        human = nil
        human_save()
        if h.face and h.face ~= "" then set_face(h.face) end
        for _, r in ipairs(HROWS) do
            local v = h.rows and h.rows[r]
            if v and v ~= "" and field(r) ~= v then set_field(r, v) end
        end
        local CLm = CL()
        for _, k in ipairs(HSLOTS) do
            local key = h.ours and h.ours[k]
            if key and CLm and CLm.choose_key then pcall(CLm.choose_key, key) end
        end
        if MN.set_jump_voice then pcall(MN.set_jump_voice, h.fx or 1.0) end
        save_now()
        log("HUMAN MODE off: back as he was (%s), MARIO FX %.2f", tostring(h.face), h.fx or 1.0)
    end
end

return M
