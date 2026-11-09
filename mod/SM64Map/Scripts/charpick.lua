-- SM64Map: the Mario face on STORROR's CHARACTER screen (the user, 2026-10-16: "add the new face to the charater
-- screen"). STORROR's face grid (SPPGridTabWidgetBP_C, Parameter SelectedCharacter) is built by its C++ from the
-- CE_PlayableCharacters table, which takes no new rows from here (UE4SS's AddRow needs a struct copy this engine does
-- not give it). So a sixth button is put in the grid by hand: STORROR's own grid item (SPPGridItem_C), the size of the
-- others, with a picture of the Mario face. A press on it (any button's press goes through
-- CommonButtonBase:HandleButtonClicked) puts the look on (mariolook.lua) over the face he has; a press on any other
-- face takes it off. The choice is kept in look.lua beside the save files and put back on whenever there is a new
-- athlete. (Never call a STORROR button's HandleButtonClicked from here: pressing Sacha's that way, to switch the face
-- under the look, crashed the game, 2026-10-16 22:04.)
local lib = require("lib")
local log = lib.log

local M = {}

local FILE = lib.MOD_DIR .. "look.lua"
local THUMB = lib.MOD_DIR .. "textures\\mario_face_thumb.png"
local FACE_PARAM = 7                 -- (ECharacterParameter::SelectedCharacter, the grid's Parameter)
local BASE_THUMB = "SachaThumbnail"  -- (the face the look is fitted to: its button's picture)
local DELAY = 0.4                    -- (seconds after a press: STORROR's own change of face goes first)
-- Mario's face is Max Cave's (the user: "make marios face max caves face"): picked, the athlete is switched to Max
-- through STORROR's own UpdateCharacterFromPlayerState once its menu is shut - before his hair is hidden, never while
-- it is (a face swapped under hidden hair, then the hair shown: the crash of 22:09)
local BASE_FACE = "Max"
local ACCEPT = { "Gamepad_FaceButton_Bottom", "Enter", "SpaceBar", "LeftMouseButton" }

local face = nil                     -- "mario" or nil: the player's choice
local loaded = false
local item, grid, tex = nil, nil, nil   -- { obj, name, world } each
local face_items = {}                -- addresses of the face grid's own buttons
local item_grid = nil                -- the grid our button is in (STORROR builds the grids anew each time its menu opens)
local others = {}                    -- the grid's own face buttons (kept), watched for presses
local was_down = {}                  -- (a button held down last tick, by address)
local chosen_sel = nil               -- STORROR's SelectedCharacter when Mario was chosen: another face picked changes it
local figure, figure_t = nil, 0.0    -- STORROR's menu mannequin (the CHARACTER screen shows it), and when to look
local want_switch = false            -- (Max's face to be put on first)
local switched_for = nil             -- (the athlete it was tried on: once each)
local accept_was = false
local was_sel, was_hov = {}, {}        -- (a button's selected / picked-out state last tick, by address)
local closed_t = 0.0                   -- (how long STORROR's menu has been shut)
local press_t = 99.0                   -- (since our button's press)
local sel_seen = nil
local menu_sel = nil                   -- (STORROR's face as it stood in the menu: a change is a face picked)
local switch_t = 0.0                   -- (till Max's face may be put on again)
local was_open = false                 -- (STORROR's menu up last tick)
local last_focus = nil                 -- "mario" / "other": the face button last picked out in the menu
local focus_prev, moved = nil, false    -- (the button picked out last tick; whether it has moved this visit)
local saved_seen = nil                 -- (which of STORROR's face buttons carries its tick - its saved face - by place)
-- (Mario's comes off only when STORROR's own tick moves from one of its buttons to another - an A press on another -
-- once the menu has stood open SETTLE seconds: opening, STORROR moves its tick and its picking-out about by itself, and
-- that dropped the Mario clothes - "when in the menu its starts on another panel so when you leave it turns off the
-- mario cloths", 2026-10-17. Leaving the menu on another button no longer drops it.)
local SETTLE, open_t = 1.5, 0.0
local last_hover = nil               -- (this visit's last button picked out: "mario" or a face's number)
local hover_moved = false            -- (and whether the cursor has moved in this visit)
local base_item = nil
local pending, pending_t = nil, 0.0  -- "on" / "off" / "base", and when
local find_t = 0.0
local hooked = false
local pawn_since, pawn_seen = 0.0, nil

local function ML() return package.loaded["mariolook"] or require("mariolook") end
local function here() local w = lib.world(); return w and w:GetAddress() end

local function load_choice()
    loaded = true
    local f = io.open(FILE, "r")
    -- (a new player's face: Mario's - "Under Character Mario head chest pants and shoes should also be on", 2026-11-01)
    if not f then face = "mario"; return end
    local src = f:read("a"); f:close()
    local fn = load(src, "look", "t", {})
    local ok, data = pcall(fn or function() end)
    if ok and type(data) == "table" and type(data.face) == "string" and (data.face == "mario"
        or (M.FACE_OF and M.FACE_OF[data.face])) then face = data.face end
end
local function save_choice()
    local f = io.open(FILE, "w")
    if not f then log("could not write %s", FILE); return end
    f:write("-- SM64Map: the face chosen on STORROR's CHARACTER screen (written by the mod)\nreturn { face = ",
        face and string.format("%q", face) or "nil", " }\n")
    f:close()
end

-- (an object kept from an earlier tick, still the same one on this map)
local function alive(k)
    if not k or k.world ~= here() then return nil end
    local ok, same = pcall(function() return k.obj:IsValid() and k.obj:GetFName():ToString() == k.name end)
    return (ok and same) and k.obj or nil
end
local function keep(o) return { obj = o, name = o:GetFName():ToString(), world = here() } end

local function thumb()
    local t = alive(tex)
    if t then return t end
    local world = lib.world()
    t = lib.file_texture(world, "textures\\mario_face_thumb.png")      -- (kept: made once - lib.lua)
    if not (t and t:IsValid()) then return nil end
    tex = keep(t)
    return t
end

-- the face grid's buttons, row by row
local function buttons(g)
    local out = {}
    pcall(function()
        local rh = g.Grid.RowHolder
        for r = 0, rh:GetChildrenCount() - 1 do
            local row = rh:GetChildAt(r)
            for c = 0, row:GetChildrenCount() - 1 do out[#out + 1] = { row = row, it = row:GetChildAt(c) } end
        end
    end)
    return out
end

-- our button in the face grid: STORROR's own kind, sized and spaced as the first, the Mario picture on it
local function add_button(g)
    local list = buttons(g)
    if #list == 0 then return end
    local first = list[1].it
    face_items, base_item, others = {}, nil, {}
    for _, b in ipairs(list) do
        face_items[b.it:GetAddress()] = true
        others[#others + 1] = keep(b.it)
        pcall(function()
            local ro = b.it.Thumbnail.Brush.ResourceObject
            if ro and ro:IsValid() and ro:GetFName():ToString() == BASE_THUMB then base_item = keep(b.it) end
        end)
    end
    local t = thumb()
    if not t then return end
    local rh = g.Grid.RowHolder
    local row = list[#list].row
    -- (a full last row: a new row under it, as the grid's own)
    if row:GetChildrenCount() >= list[1].row:GetChildrenCount() then
        local nr = nil
        pcall(function()
            nr = StaticConstructObject(StaticFindObject("/Script/UMG.HorizontalBox"), rh:GetOuter())
            rh:AddChild(nr)
        end)
        if not (nr and nr:IsValid()) then return end
        row = nr
    end
    local it = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):Create(lib.world(), g.Grid.ItemClass, lib.controller())
    if not (it and it:IsValid()) then return end
    pcall(function()
        local th = it.Thumbnail
        if th and th:IsValid() then
            th:SetBrushFromTexture(t, false)
            th:SetDesiredSizeOverride({ X = first.Thumbnail.Brush.ImageSize.X, Y = first.Thumbnail.Brush.ImageSize.Y })
        end
        local mb, fb = it.ThumbnailBox, first.ThumbnailBox
        if mb and mb:IsValid() and fb and fb:IsValid() then
            mb:SetWidthOverride(fb.WidthOverride); mb:SetHeightOverride(fb.HeightOverride)
        end
        local sv = it.SavedIcon
        if sv and sv:IsValid() then sv:SetVisibility(1) end
    end)
    local slot = row:AddChildToHorizontalBox(it)
    pcall(function() slot:SetPadding(first.Slot.Padding) end)
    item = keep(it)
    item_grid = g:GetAddress()
    saved_seen = nil
    log("character screen: Mario face button added")
end

-- the face grid shown now (looked for a few times a second while STORROR's menu is up)
local function face_grid(dt)
    local g = alive(grid)
    if g then
        local ok, vis = pcall(function() return g:IsVisible() end)
        if ok and vis then return g end
    end
    find_t = find_t - dt
    if find_t > 0 then return nil end
    find_t = 0.3
    grid = nil
    for _, x in ipairs(FindAllOf("SPPGridTabWidgetBP_C") or {}) do
        local ok, yes = pcall(function() return x.Parameter == FACE_PARAM and x:IsVisible() end)
        if ok and yes then grid = keep(x); return x end
    end
    return nil
end

-- Mario's off: another face pressed (A, or a click, on one of STORROR's own) - "cant disable mario character now",
-- 2026-10-18: it waited for STORROR's saved-face tick to move, which it did not always do, and on leaving the menu he
-- was switched back to Max with the look on
local function mario_off(why)
    if not face then return end
    face = nil; save_choice()
    local look = ML()
    for _, a in ipairs(look.dressed_list()) do pcall(look.undress, a) end
    pending, pending_t = "off", DELAY
    log("character screen: %s - Mario's off", why)
end

-- (the button is ours / one of the face grid's own)
local function on_press(btn)
    local it = alive(item)
    if not it then return end
    local a = btn:GetAddress()
    if a == it:GetAddress() then
        if face then return end
        face = "mario"; save_choice()
        local sel = nil
        pcall(function() sel = lib.pawn().PlayerState.PlayerModel.RepCharacterEditorData.SelectedCharacter:ToString() end)
        press_t = 0.0           -- (put on once the menu is shut: there his hair is shown, and hidden only outside it)
        log("character screen: Mario face chosen (face now %s)", tostring(sel))
    elseif face_items[a] then
        mario_off("another face pressed")
    end
end

-- STORROR's own pick on its face grid - HITSPauseMenuWidgetUI:SelectedCallbackFromDelegate(the item's name), what its
-- grid runs on A or a click - even on the face already saved: Max, under Mario, changes nothing else STORROR shows
-- ("now cant choose max", "not working", 2026-10-18: A in its menu reaches no key the mod can read). Only the face
-- grid's (not the shirts'), and never with our button the one picked out.
local function picked(widget, name)
    local okp, face_grid_w = pcall(function() return widget.Parameter == FACE_PARAM end)
    if not (okp and face_grid_w) then return end
    local it = alive(item)
    local on_ours = false
    if it then pcall(function() on_ours = it:IsHovered() end) end
    log("character screen: STORROR's pick %s%s", tostring(name), on_ours and " (the Mario button picked out)" or "")
    -- (Max's tile is Mario's: a face is chosen by this - A or a click on its tile - only; looking along the faces
    -- chooses nothing, "make sure selected clothing items and faces stay on until the player selects something",
    -- 2026-11-01. Taken as the menu shuts: max_tick)
    if M.MAX_IS_MARIO then
        M.mx = M.mx or { open_t = 0.0, pick = nil, was_open = false, switch_t = 0.0, wait = 0.0 }
        M.mx.pick_at = os.clock()           -- (the face it gives read a moment after, once STORROR has put it on)
        return
    end
    if on_ours then return end
    mario_off("picked " .. tostring(name))
end

local function hook()
    hooked = true
    pcall(function()
        RegisterHook("/Script/HITS_UI.HITSPauseMenuWidgetUI:SelectedCallbackFromDelegate", function(ctx, item_name)
            local w, n = nil, nil
            pcall(function() w = ctx:get() end)
            pcall(function() n = item_name:get():ToString() end)
            if w then pcall(picked, w, n) end
        end)
    end)
    pcall(function()
        RegisterHook("/Script/CommonUI.CommonButtonBase:HandleButtonClicked", function(ctx)
            pcall(function() on_press(ctx:get()) end)
        end)
    end)
    pcall(function()
        RegisterHook("/Script/CommonUI.CommonButtonBase:BP_OnClicked", function(ctx)
            pcall(function() on_press(ctx:get()) end)
        end)
    end)
end

-- every tick, from pause.lua (menu_open: STORROR's menu is up)
function M.tick(dt, menu_open)
    if not loaded then load_choice() end
    if not hooked then hook() end
    local look = ML()

    -- the look on a new athlete (a little after he is there), or off a gone map's untouched
    local pawn = lib.pawn()
    local pa = pawn and pawn:GetAddress()
    if pa ~= pawn_seen then pawn_seen, pawn_since = pa, 0.0 else pawn_since = pawn_since + dt end
    if look.on() and look.world_addr() ~= here() then look.forget() end
    local sel = nil
    pcall(function() sel = pawn.PlayerState.PlayerModel.RepCharacterEditorData.SelectedCharacter:ToString() end)
    if menu_open then closed_t = 0.0 else closed_t = closed_t + dt end
    if menu_open then open_t = open_t + dt else open_t = 0.0 end
    if sel ~= sel_seen then log("character screen: face %s -> %s (menu %s)", tostring(sel_seen), tostring(sel), tostring(menu_open)); sel_seen = sel end
    press_t = press_t + dt

    -- (SelectedCharacter follows the face picked out in the menu - STORROR's preview - and goes back to the saved one
    -- when the menu shuts: it tells nothing of a pick. A pick is seen in the menu, below.)
    -- The menu just shut with our button picked out: Mario it is (A on it reaches nothing the mod can see, but
    -- sometimes its selected state turning over - so leaving the menu on it picks it too)
    if was_open and not menu_open then
        if (last_focus == "mario" or last_hover == "mario") and not face then
            face = "mario"; save_choice()
            press_t = 0.0
            log("character screen: menu shut on the Mario button - Mario face chosen")
        -- (shut with one of STORROR's faces the one picked out and kept - its SelectedCharacter stays as it was left,
        -- not Max's - Mario's off: the player was in and out in two seconds, too quick for any press to be seen,
        -- "mario charater still not being removed", 2026-10-18)
        elseif face and last_hover ~= nil and last_hover ~= "mario" and sel and (sel ~= BASE_FACE or hover_moved) then
            -- (Max himself - the face Mario is made on, where the menu opens with Mario chosen - only once the player
            -- has moved the cursor in this visit: shutting it straight away keeps Mario; "now cant choose max")
            mario_off("menu shut on " .. tostring(sel))
        end
        last_focus, focus_prev, moved, last_hover, hover_moved = nil, nil, false, nil, false
        for _, a in ipairs(look.dressed_list()) do pcall(look.undress, a) end
    end
    was_open = menu_open

    -- Out of the menu, Mario chosen: the face is Max's (STORROR may set its own on shutting the menu - our button is
    -- none of its - so a second after, it is looked at and Max's put back through STORROR's own
    -- UpdateCharacterFromPlayerState, his hair shown first: a face is never swapped under hidden hair)
    if face and pawn and not menu_open and closed_t > 1.0 and pawn_since > 1.0 and not pending and sel and sel ~= BASE_FACE then
        if look.on() and look.hair_hidden() then
            pcall(look.show_hair)
        elseif switch_t <= 0 then
            switch_t = 5.0
            local ok, err = pcall(function()
                pawn.PlayerState.PlayerModel.RepCharacterEditorData.SelectedCharacter = BASE_FACE
                for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
                    local o = c:get()
                    if o:GetClass():GetFName():ToString() == "CharacterEditorComponent" then o:UpdateCharacterFromPlayerState() end
                end
            end)
            log("character screen: Mario's face - %s switched to %s (%s)", sel, BASE_FACE, ok and "ok" or tostring(err))
            pending, pending_t = "on", 0.8
        end
    end
    switch_t = switch_t - dt

    if pending then
        pending_t = pending_t - dt
        if pending_t <= 0 then
            local what = pending
            pending = nil
            if what == "on" then
                if face and pawn and not menu_open then pcall(look.apply) end
            elseif what == "off" then
                if not face then
                    local was = look.on()
                    pcall(look.remove)           -- (his hair to its own length again)
                    for _, a in ipairs(look.dressed_list()) do pcall(look.undress, a) end
                    -- (Max himself: no face swapped, so his hair is shown if the look left it hidden - safe here, where
                    -- a hair shown after a swap made under it is not)
                    local shown = false
                    if sel == BASE_FACE and pawn then
                        pcall(function()
                            for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/HairStrandsCore.GroomComponent"))) do
                                local o = c:get()
                                if o:GetFName():ToString() == "HairGroom" and not o:IsVisible() then o:SetHiddenInGame(false, false); shown = true end
                            end
                        end)
                    end
                    log("character screen: Mario look off (it was %s, face %s%s)", was and "on" or "off", tostring(sel),
                        shown and ", his hair shown" or "")
                end
            end
        end
    elseif face and pawn and not menu_open and closed_t > 1.0 and pawn_since > 1.0 and sel == BASE_FACE
        and (not look.on() or look.pawn_addr() ~= pa) then
        pcall(look.apply)
    end

    -- (his hair: shown while STORROR's menu is up - the only place a face is swapped, and a face swapped under hidden
    -- hair then shown crashed the game, 22:09 - and hidden again once it is shut)
    if menu_open then
        if look.on() and look.hair_hidden() then pcall(look.show_hair) end     -- (the old button way: M.MAX_IS_MARIO false)
    elseif face and look.on() and closed_t > 1.5 and sel == BASE_FACE and not look.hair_hidden() and not pending then
        pcall(look.hide_hair)
    end

    if not menu_open then return end
    local g = face_grid(dt)
    if not g then return end
    local it = alive(item)
    if it and item_grid ~= g:GetAddress() then it = nil end
    if it then
        local ok, parent = pcall(function() return it:GetParent() end)
        if not (ok and parent and parent:IsValid()) then it = nil end
    end
    if not it then add_button(g); it = alive(item) end
    if not it then return end
    -- (what is picked out; and STORROR's tick moving to another of its faces - a face picked there: Mario's off)
    local okh, hm = pcall(function() return it:IsHovered() end)
    local now = (okh and hm) and "mario" or nil
    local saved = nil
    for i, k in ipairs(others) do
        local b = alive(k)
        if b then
            local okb, hb = pcall(function() return b:IsHovered() end)
            if okb and hb and not now then now = i end
            local okv, v = pcall(function() return b.SavedIcon:IsVisible() end)
            if okv and v then saved = i end
        end
    end
    if now ~= nil then
        -- (a move counted only after the first half second: the grid settling on the saved face as it opens flickered
        -- the cursor, read as a move, and shutting it then picked Max over Mario - "when you exit the screen it chooses
        -- max face instead of mario face", 2026-10-18)
        if last_hover ~= nil and now ~= last_hover and open_t >= 0.5 then hover_moved = true end
        last_hover = now                                -- (the last one picked out, from the start: the menu-shut test)
    end
    -- (the button picked out: counted once it has been moved in this visit - the menu opens on the saved face)
    if now ~= nil and open_t < SETTLE then focus_prev = now
    elseif now ~= nil then
        if focus_prev ~= nil and now ~= focus_prev then moved = true end
        focus_prev = now
        if moved then last_focus = (now == "mario") and "mario" or "other" end
    end
    -- (the menu's mannequin - the figure the CHARACTER screen shows - wears the look while our button is picked out:
    -- the one shown only; STORROR makes a new one at each visit and hides the old)
    -- (found afresh a few times a second, never kept between ticks: STORROR throws the old ones away)
    if now == "mario" then
        figure_t = figure_t - dt
        if figure_t <= 0 then
            figure_t = 0.3
            local f = nil
            for _, o in ipairs(FindAllOf("PlayerMannequinBP_C") or {}) do
                local okv, hid = pcall(function() return o.bHidden end)
                if okv and not hid then f = o end
            end
            local fa = f and f:GetAddress()
            for _, a in ipairs(look.dressed_list()) do
                if a ~= fa then pcall(look.undress, a) end
            end
            if f and not look.dressed(fa) then pcall(function() look.dress(f, f.Body) end) end
        end
    elseif now ~= nil then
        for _, a in ipairs(look.dressed_list()) do pcall(look.undress, a) end
    end
    if saved_seen == nil or open_t < SETTLE or saved_seen == 0 then saved_seen = saved or 0
    elseif saved and saved ~= saved_seen then
        saved_seen = saved or 0
        last_focus = "other"
        if face then
            face = nil; save_choice()
            for _, a in ipairs(look.dressed_list()) do pcall(look.undress, a) end
            pending, pending_t = "off", DELAY
            log("character screen: STORROR's tick moved to face %d - Mario's off", saved or 0)
        end
    end
    -- (presses: STORROR's own buttons do not go through HandleButtonClicked where the hook can see them - "clicking on
    -- other faces doesnt get rid of the mario face" - so each button's held state is watched)
    -- (and A / Enter / Space / the mouse's button going down while a button is the one picked out)
    local pc = lib.controller()
    local acc = false
    for _, k in ipairs(ACCEPT) do
        local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(k) }) end)
        if ok and v == true then acc = true end
    end
    local acc_edge = acc and not accept_was
    accept_was = acc
    local function down(b, mine)
        local ok, v = pcall(function() return b:IsPressed() end)
        local a = b:GetAddress()
        local edge = ok and v == true and not was_down[a]
        was_down[a] = ok and v == true
        local okh, h = pcall(function() return b:IsHovered() end)
        h = okh and h == true
        if not edge and acc_edge then edge = h end
        -- (a press on a picked-out button turns its selected state over - A on it, with the game seeing no A: the
        -- probe of 2026-10-16 22:14 - while being picked out sets it with the picking)
        local oks, sl = pcall(function() return b:GetSelected() end)
        sl = oks and sl == true
        if not edge and mine and h and was_hov[a] and was_sel[a] ~= nil and sl ~= was_sel[a] then edge = true end
        was_sel[a], was_hov[a] = sl, h
        return edge
    end
    if down(it, true) then on_press(it) end
    for _, k in ipairs(others) do
        local b = alive(k)
        if b and down(b) and open_t >= 0.3 then mario_off("another face pressed") end
    end
    -- (its name over the athlete while it is the one picked out, as the others'; its tick on it while it is chosen)
    pcall(function()
        if it:IsHovered() then
            g.Grid.SelectedItemNameDisplay:SetText(FText("MARIO"))
            local tl = g.Grid.SelectedItemTaglineDisplay
            if tl and tl:IsValid() then tl:SetText(FText("")) end
        end
    end)
    pcall(function() it.SavedIcon:SetVisibility(face and 4 or 1) end)
end

-- Max is Mario ("can you just replace the mario charter with max", 2026-10-18): no button of the mod's own. STORROR's
-- own Max tile wears the Mario picture and is called MARIO, and Max picked is Mario - his SelectedCharacter Max (it
-- follows the face picked out in the menu and stays as it is left): the look on him out of the menu; any other face,
-- no look. Nothing of the player's presses to guess at, which the menu keeps from the mod. (The sixth button, the old
-- way: M.MAX_IS_MARIO = false.)
M.MAX_IS_MARIO = true
-- The other characters on STORROR's faces, as Max is Mario ("make 3 other charaters and all they're clothing, Luigi
-- as Benj, toby as wario, Drew as waluigi", 2026-11-01): each face's tile wears its character's picture and, while it
-- is the face shown, its name; that face picked is that character - its look on him (mariolook.lua M.CHARS) and its
-- clothes (clothpick.lua M.dress_char, from charhold.lua's pick).
M.CHAR_OF = { Max = "mario", Benj = "luigi", Toby = "wario", Drew = "waluigi" }
M.FACE_OF = { mario = "Max", luigi = "Benj", wario = "Toby", waluigi = "Drew" }
local CHAR_NAME = { mario = "MARIO", luigi = "LUIGI", wario = "WARIO", waluigi = "WALUIGI" }
local char_tex = {}                  -- character -> its tile picture (kept)
local function char_thumb(c)
    if c == "mario" then return thumb() end
    local t = alive(char_tex[c])
    if t then return t end
    t = lib.file_texture(lib.world(), "textures\\" .. c .. "_face_thumb.png")      -- (kept: made once - lib.lua)
    if not (t and t:IsValid()) then return nil end
    char_tex[c] = keep(t)
    return t
end
local max_tiles = {}                 -- (the characters' tiles in the grid shown: address -> character)
local tile_faces = {}                -- (each face tile's face - Max, Sacha, ... - by address: charhold.lua)
function M.tile_face(addr) return tile_faces[addr] end
-- the face chosen, from charhold.lua as a face is picked (a character's name, or nil for STORROR's own)
function M.set_face(f)
    if face ~= f then face = f; save_choice() end
end
local thumbs_told = false
local function max_tile_tick(g, shown)
    local names = {}
    for _, b in ipairs(buttons(g)) do
        local a = b.it:GetAddress()
        if not max_tiles[a] then
            local c, size, n = nil, nil, ""
            pcall(function()
                local br = b.it.Thumbnail.Brush
                local ro = br.ResourceObject
                n = (ro and ro:IsValid()) and ro:GetFName():ToString() or ""
                local who = n:match("^(%a+)Thumbnail$")
                c = who and M.CHAR_OF[who]
                size = { X = br.ImageSize.X, Y = br.ImageSize.Y }
            end)
            names[#names + 1] = n
            local who = n:match("^(%a+)Thumbnail$")
            if who then tile_faces[a] = who end
            local t = c and char_thumb(c)
            if t then
                max_tiles[a] = c
                pcall(function()
                    b.it.Thumbnail:SetBrushFromTexture(t, false)
                    if size then b.it.Thumbnail:SetDesiredSizeOverride(size) end
                end)
                log("character screen: %s's tile is %s's", n, c)
            end
        end
    end
    if not thumbs_told and #names > 0 then
        thumbs_told = true
        log("character screen: the face tiles' pictures: %s", table.concat(names, ", "))
    end
    -- (its name while its face is the one shown - not while the mouse pointer merely rests on the tile: the name read
    -- MARIO over Sacha)
    if shown and CHAR_NAME[shown] then
        local here_too = false
        for _, c in pairs(max_tiles) do if c == shown then here_too = true end end
        if here_too then
            pcall(function()
                g.Grid.SelectedItemNameDisplay:SetText(FText(CHAR_NAME[shown]))
                local tl = g.Grid.SelectedItemTaglineDisplay
                if tl and tl:IsValid() then tl:SetText(FText("")) end
            end)
        end
    end
end

-- Mario kept (2026-10-25, "mario charater keeps coming off and switching to sacha"): STORROR's face grid lands on
-- Sacha's tile a moment after its menu opens, and its SelectedCharacter follows it; shut then, he was left Sacha and the
-- look came off. The player's choice is kept (look.lua): only a face picked out by the player - after M.PICK_AFTER in
-- the menu - and the menu shut on it changes it; Mario kept and another face on him, Max is put back.
M.PICK_AFTER = 0.8
M.KEEP_WAIT = 1.5

-- His hair in STORROR's menu: shown on its CHARACTER tab only - the face is swapped there, and never under hidden hair -
-- once that tab has been on a moment (the menu passes through it as it opens); on the other tabs hidden, the face still
-- a while: it stuck out of his cap in the pause menu, "also in pause menu the hair will stick out of marios hat",
-- 2026-11-01. (He is hidden on CHARACTER anyway: STORROR's figure stands in for him - pause.lua figure_place.)
local hair_tab = { on_t = 0.0, off_t = 0.0, sel = nil, sel_t = 0.0 }
local function menu_hair(dt, look, sel)
    local P = package.loaded["pause"]
    local tab = nil
    if P and P.tab then pcall(function() tab = P.tab() end) end
    local H = hair_tab
    -- (held as he is while the menu is up - charhold.lua - he is what the CHARACTER screen shows: his hair under the
    -- cap on every tab; a face changes only by a pick, the look taken off first, his hair with it)
    local CH = package.loaded["charhold"]
    if CH and CH.holding and CH.holding() then
        if look.on() and not look.hair_hidden() then pcall(look.hide_hair) end
        return
    end
    if tab == "Character" then H.on_t, H.off_t = H.on_t + dt, 0.0 else H.on_t, H.off_t = 0.0, H.off_t + dt end
    if sel ~= H.sel then H.sel, H.sel_t = sel, 0.0 else H.sel_t = H.sel_t + dt end
    if not look.on() then return end
    if H.on_t > 0.4 then
        if look.hair_hidden() then pcall(look.show_hair) end
    elseif H.off_t > 0.5 and H.sel_t > 1.0 then
        if not look.hair_hidden() then pcall(look.hide_hair) end
    end
end
local function max_tick(dt, menu_open)
    local look = ML()
    local pawn = lib.pawn()
    local pa = pawn and pawn:GetAddress()
    local X = M.mx
    if not X then X = { open_t = 0.0, pick = nil, was_open = false, switch_t = 0.0, wait = 0.0 }; M.mx = X end
    if not loaded then load_choice() end
    if pa ~= pawn_seen then pawn_seen, pawn_since = pa, 0.0 else pawn_since = pawn_since + dt end
    if look.on() and look.world_addr() ~= here() then look.forget() end
    local sel = nil
    pcall(function() sel = pawn.PlayerState.PlayerModel.RepCharacterEditorData.SelectedCharacter:ToString() end)
    if menu_open and not X.was_open then X.open_t, X.pick = 0.0, nil end
    if menu_open then X.open_t = X.open_t + dt; closed_t = 0.0 else closed_t = closed_t + dt end
    if sel ~= sel_seen then
        log("character screen: face %s -> %s (menu %s, %.1fs in)", tostring(sel_seen), tostring(sel), tostring(menu_open),
            menu_open and X.open_t or closed_t)
        -- (a face only looked at - STORROR's preview follows the cursor - is no pick: picks come from STORROR's own pick
        -- on the tile, picked(), the face read here a moment after)
        sel_seen = sel
    end
    if X.pick_at and os.clock() - X.pick_at > 0.2 then
        X.pick, X.pick_at = sel, nil
        log("character screen: %s picked", tostring(sel))
    end
    if X.was_open and not menu_open and X.pick then
        local f = M.CHAR_OF[X.pick or ""]
        if f ~= face then face = f; save_choice() end
        log("character screen: shut on %s - %s chosen", X.pick, f or X.pick)
        X.pick = nil
    end
    X.was_open = menu_open
    X.switch_t = X.switch_t - dt
    X.wait = X.wait - dt
    if not menu_open then
        -- (STORROR's menu just shut, charhold still holding him: the face he shows - its data says the face its cursor
        -- was on, and Luigi's cap went on Wario a moment)
        local CH = package.loaded["charhold"]
        local hf = CH and CH.face and CH.face()
        if hf then sel = hf end
    end
    local ch = M.CHAR_OF[sel or ""]          -- (the character STORROR's face is, if any)
    local mario = ch ~= nil
    if menu_open then
        -- (his hair shown on the CHARACTER tab - the only place a face is swapped: a face swapped under hidden hair,
        -- then shown, crashed the game - and hidden on the others: menu_hair)
        menu_hair(dt, look, sel)
        local g = face_grid(dt)
        if g then pcall(max_tile_tick, g, ch) end
        -- (the menu's figure dressed as Mario while Max is the face shown; found afresh, STORROR makes new ones)
        figure_t = figure_t - dt
        if figure_t <= 0 then
            figure_t = 0.3
            local f = nil
            if mario then
                for _, o in ipairs(FindAllOf("PlayerMannequinBP_C") or {}) do
                    local okv, hid = pcall(function() return o.bHidden end)
                    if okv and not hid then f = o end
                end
            end
            local fa = f and f:GetAddress()
            for _, a in ipairs(look.dressed_list()) do if a ~= fa then pcall(look.undress, a) end end
            if f and not look.dressed(fa) then pcall(function() look.dress(f, f.Body) end) end
        end
        return
    end
    if next(max_tiles) then max_tiles = {} end
    if next(tile_faces) then tile_faces = {} end
    if #look.dressed_list() > 0 then for _, a in ipairs(look.dressed_list()) do pcall(look.undress, a) end end
    if mario and pawn and closed_t > 1.0 and pawn_since > 1.0 and X.wait <= 0 then
        if face ~= ch then face = ch; save_choice() end
        if not look.on() or look.pawn_addr() ~= pa or (look.char and look.char() ~= ch) then
            if look.set_char then look.set_char(ch) end
            pcall(look.apply)
            log("character screen: %s - %s's look on", tostring(sel), ch)
        elseif closed_t > 1.5 and not look.hair_hidden() then
            pcall(look.hide_hair)
        end
    elseif face and M.FACE_OF[face] and ch ~= face and sel and pawn and closed_t > M.KEEP_WAIT and pawn_since > 1.0 then
        -- (Mario kept: Max put back through STORROR's own UpdateCharacterFromPlayerState - the look off first, his hair
        -- shown: a face is never swapped under hidden hair - and the look on again a second after)
        if X.switch_t <= 0 then
            X.switch_t, X.wait = 5.0, 1.0
            if look.on() then pcall(look.remove) end
            local ok, err = pcall(function()
                pawn.PlayerState.PlayerModel.RepCharacterEditorData.SelectedCharacter = M.FACE_OF[face]
                for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
                    local o = c:get()
                    if o:GetClass():GetFName():ToString() == "CharacterEditorComponent" then o:UpdateCharacterFromPlayerState() end
                end
            end)
            log("character screen: %s kept - %s switched back to %s (%s)", face, tostring(sel), M.FACE_OF[face], ok and "ok" or tostring(err))
        end
    elseif not mario and look.on() and closed_t > M.KEEP_WAIT then
        pcall(look.remove)
        log("character screen: %s - Mario's look off", tostring(sel))
    end
end

local button_tick = M.tick
function M.tick(dt, menu_open)
    -- (and the look hidden in first person: mariolook.lua M.view_tick)
    local L = package.loaded["mariolook"]
    if L and L.view_tick then pcall(L.view_tick) end
    -- (what he wears held on STORROR's CHARACTER screen until a pick: charhold.lua)
    local okH, CH = pcall(require, "charhold")
    if okH and CH and CH.tick then pcall(CH.tick, dt, menu_open) end
    -- (the CHARACTER tab made anew: its four slots - charmenu.lua)
    local okC, CMN = pcall(require, "charmenu")
    if okC and CMN and CMN.tick then pcall(CMN.tick, dt, menu_open) end
    if M.MAX_IS_MARIO then return max_tick(dt, menu_open) end
    return button_tick(dt, menu_open)
end

function M.choice()
    if M.MAX_IS_MARIO then return M.CHAR_OF[sel_seen or ""] or face end
    if not loaded then load_choice() end
    return face
end

-- (the map gone - STORROR reloaded it with its menu up: what this keeps of it dropped untouched, main.lua's watch on the
-- map - "crash" twice, 2026-11-03, a moment into the game after that reload: an object of the gone map reached for)
-- (the player's choice, `face`, kept)
function M.forget()
    item, grid, tex = nil, nil, nil
    face_items, others, was_down, was_sel, was_hov = {}, {}, {}, {}, {}
    max_tiles, tile_faces = {}, {}
    item_grid, figure, base_item, pending = nil, nil, nil, nil
    figure_t, was_open = 0.0, false
    focus_prev, last_hover, saved_seen, sel_seen, menu_sel = nil, nil, nil, nil, nil
    if M.mx then M.mx.was_open = false end
end

return M
