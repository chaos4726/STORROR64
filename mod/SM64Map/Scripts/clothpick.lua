-- SM64Map: clothes of our own on STORROR's CHARACTER screen (the user, 2026-10-16: "next the pants I want them to look
-- like jeans"). As the Mario face (charpick.lua): STORROR's option tables take no new rows, so a button of its own kind
-- is put in the tab's grid by hand, and - A in its menu reaching nothing the mod can see - an option is picked by
-- leaving the menu with its button picked out, and dropped by leaving it on another of the tab's buttons (once the
-- picking-out has moved that visit) or by STORROR's tick moving to another of them. The choice is kept in clothes.lua
-- beside the save files and put back whenever STORROR has put its own on (at a new start, on shutting its menu).
--
-- JEANS (the BOTTOM tab): STORROR's own jogger cloth with a denim of ours - its cotton material
-- (Cotton_Natural_Rough_MAT, master DadoClothMasterMat: colour = BaseColor texture x Tint, tiled UV Amount times) with
-- our denim picture (textures/denim.png) and a light tint. (The game's own 6K denim is a streamed texture: black in
-- that material. The T-shirt material's "PrintColor" is its whole colour map, laid on the shirt's own layout.)
local lib = require("lib")
local log = lib.log

local M = {}

local FILE = lib.MOD_DIR .. "clothes.lua"
local JEANS_TINT = 1.0               -- (as bright as the overalls' denim on him, measured on screen)
local COTTON = "/SPP/MetaHumanAdHoc/Clothing/Torso/HoodieV1/Cotton_Natural_Rough_MAT.Cotton_Natural_Rough_MAT"

local textures = {}                      -- by file: { obj, name, world }
local function here() local w = lib.world(); return w and w:GetAddress() end
local function keep(o) return { obj = o, name = o:GetFName():ToString(), world = here() } end
local function alive(k)
    if not k or k.world ~= here() then return nil end
    local ok, same = pcall(function() return k.obj:IsValid() and k.obj:GetFName():ToString() == k.name end)
    return (ok and same) and k.obj or nil
end
local function texture(file)
    local t = alive(textures[file])
    if t then return t end
    t = lib.file_texture(lib.world(), "textures\\" .. file)      -- (kept: made once - lib.lua)
    if not (t and t:IsValid()) then return nil end
    textures[file] = keep(t)
    return t
end
local function component(actor, name)
    local found = nil
    pcall(function()
        for _, c in ipairs(actor:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o:GetFName():ToString() == name then found = o end
        end
    end)
    return found
end

-- the denim on a figure's legs (the athlete's, or the menu's mannequin's): one material on every slot; returns its name
local function jeans_on(actor, prev, file)
    local lc = component(actor, "LegsCloth")
    local den = texture(file or "jeans_mario.png")
    local base = lib.try_load(COTTON)
    if not (lc and den and base) then return nil end
    local name = nil
    pcall(function()
        local mid = lc:CreateDynamicMaterialInstance(0, base, FName("None"))
        if not (mid and mid:IsValid()) then return end
        mid:SetTextureParameterValue(FName("BaseColor"), den)
        mid:SetVectorParameterValue(FName("Tint"), { R = JEANS_TINT, G = JEANS_TINT * 1.03, B = JEANS_TINT * 1.06, A = 1.0 })
        -- (jeans_mario.png is laid on the joggers' own layout - stitched seams and hems, make_mario_textures.py - so
        -- once across, the fabric's own bumps turned down to suit: "add the same detail to the front and pants")
        mid:SetScalarParameterValue(FName("UV Amount"), 1.0)
        mid:SetScalarParameterValue(FName("NormalStrength"), 0.12)
        for i = 1, lc:GetNumMaterials() - 1 do lc:SetMaterial(i, mid) end
        name = mid:GetFName():ToString()
    end)
    return name
end
-- (still ours on the athlete's legs: STORROR has not put its own on)
local function jeans_still(actor, name)
    local lc = component(actor, "LegsCloth")
    local ok, same = pcall(function() return lc:GetMaterial(0):GetFName():ToString() == name end)
    return ok and same
end
-- off again: STORROR's cotton put back if ours is still on (an asset, never gone)
local function jeans_off(actor, name)
    if not jeans_still(actor, name) then return end
    local lc = component(actor, "LegsCloth")
    local base = lib.try_load(COTTON)
    if lc and base then pcall(function() for i = 0, lc:GetNumMaterials() - 1 do lc:SetMaterial(i, base) end end) end
end

-- BROWN SHOES (the SHOES tab, "next the brown shoes"): STORROR's black running shoe material (M_shs_runningshoes_Black,
-- master M_fabric_simpler) with its colours turned brown: upper, its accents, the sole, the laces
local SHOES = "/SPP/MetaHumans/Common/Materials/RunningShoes/M_shs_runningshoes_Black.M_shs_runningshoes_Black"
local BROWN = { { 0.16, 0.065, 0.022 }, { 0.09, 0.036, 0.012 }, { 0.035, 0.018, 0.008 }, { 0.20, 0.09, 0.035 } }
local function shoes_on(actor, prev, cols)
    local ft = component(actor, "Feet")
    local base = lib.try_load(SHOES)
    if not (ft and base) then return nil end
    local name = nil
    local c = cols or BROWN
    pcall(function()
        local mid = ft:CreateDynamicMaterialInstance(0, base, FName("None"))
        if not (mid and mid:IsValid()) then return end
        mid:SetVectorParameterValue(FName("diffuse_color_1"), { R = c[1][1], G = c[1][2], B = c[1][3], A = 1.0 })
        mid:SetVectorParameterValue(FName("diffuse_color_2"), { R = c[2][1], G = c[2][2], B = c[2][3], A = 1.0 })
        mid:SetVectorParameterValue(FName("B_diffuse_color_1"), { R = c[3][1], G = c[3][2], B = c[3][3], A = 1.0 })
        mid:SetVectorParameterValue(FName("C_color"), { R = c[4][1], G = c[4][2], B = c[4][3], A = 1.0 })
        name = mid:GetFName():ToString()
    end)
    return name
end
local function shoes_still(actor, name)
    local ft = component(actor, "Feet")
    local ok, same = pcall(function() return ft:GetMaterial(0):GetFName():ToString() == name end)
    return ok and same
end
local function shoes_off(actor, name)
    if not shoes_still(actor, name) then return end
    local ft = component(actor, "Feet")
    local base = lib.try_load(SHOES)
    if ft and base then pcall(function() ft:SetMaterial(0, base) end) end
end

-- MARIO SHIRT (the TOP tab: "a longsleeve and white gloves with the overalls and buttons for the chest"): two
-- pictures painted on the layouts exported from the game (make_mario_textures.py). The T-shirt's material
-- (MI_Phase_White, master DadoClothORMSplitMasterMat: its "PrintColor" is the shirt's whole colour map) with
-- shirt_mario.png - red, the overalls' bib, straps, gold buttons. The body's skin (M_BodySynthesized, "Color_MAIN")
-- with body_mario.png - his forearms red (long sleeves), his hands white (gloves, bending with his fingers).
local SHIRT = "/SPP/SPPCharacter/Clothing/Materials/TShirtLegacy/TShirtLungerGraphicsHand/MI_Phase_White.MI_Phase_White"
local skins = {}                         -- our skin material's name -> { comp, orig }: the skin it went over
local function body_comp(actor)
    return component(actor, "CharacterMesh0") or component(actor, "Body")
end
local function mat_name(comp, i)
    local ok, n = pcall(function() return comp:GetMaterial(i):GetFName():ToString() end)
    return ok and n or nil
end
local function shirt_on(actor, prev, shirt_file, body_file)
    local tc, bc = component(actor, "TorsoCloth"), body_comp(actor)
    local base, shirt_tex, skin_tex = lib.try_load(SHIRT), texture(shirt_file or "shirt_mario.png"), texture(body_file or "body_mario.png")
    if not (tc and bc and base and shirt_tex and skin_tex) then return nil end
    local p1, p2 = nil, nil
    if prev then p1, p2 = prev:match("^(.-)|(.*)$") end
    local n1, n2 = p1, p2
    -- (each part put on again only where STORROR has put its own back)
    if not (p1 and mat_name(tc, 0) == p1) then
        pcall(function()
            local mid = tc:CreateDynamicMaterialInstance(0, base, FName("None"))
            mid:SetTextureParameterValue(FName("PrintColor"), shirt_tex)
            n1 = mid:GetFName():ToString()
            -- (its other slots - the inside, seen up the sleeves when his arms go up - the same: "white textures
            -- showing by the elbows when the arms raise")
            for i = 1, tc:GetNumMaterials() - 1 do tc:SetMaterial(i, mid) end
        end)
    end
    if not (p2 and mat_name(bc, 0) == p2) then
        pcall(function()
            local orig = bc:GetMaterial(0)
            local mid = bc:CreateDynamicMaterialInstance(0, orig, FName("None"))
            mid:SetTextureParameterValue(FName("Color_MAIN"), skin_tex)
            -- (Toby's body - Wario's - wears STORROR's simplified skin, its colour a BaseColor picture with no
            -- Color_MAIN: his arms stayed bare, no sleeves or gloves, 2026-11-01)
            local has_main = false
            pcall(function()
                local t = orig:K2_GetTextureParameterValue(FName("Color_MAIN"))
                has_main = t ~= nil and t:IsValid()
            end)
            if not has_main then mid:SetTextureParameterValue(FName("BaseColor"), skin_tex) end
            n2 = mid:GetFName():ToString()
            skins[n2] = { comp = bc, orig = orig }
        end)
    end
    if not (n1 and n2) then return nil end
    return n1 .. "|" .. n2
end
local function shirt_still(actor, name)
    if not name then return false end
    local p1, p2 = name:match("^(.-)|(.*)$")
    return mat_name(component(actor, "TorsoCloth"), 0) == p1 and mat_name(body_comp(actor), 0) == p2
end
local function shirt_off(actor, name)
    if not name then return end
    local p1, p2 = name:match("^(.-)|(.*)$")
    local tc, bc = component(actor, "TorsoCloth"), body_comp(actor)
    -- (the skin's own material back only while ours is still on it - ours holds it as its parent; once STORROR has
    -- changed the body it may be gone: putting a gone material on crashed the game, 22:25)
    local sk = skins[p2]
    if sk and bc and mat_name(bc, 0) == p2 then pcall(function() bc:SetMaterial(0, sk.orig) end) end
    skins[p2] = nil
    local base = lib.try_load(SHIRT)
    if tc and base and mat_name(tc, 0) == p1 then pcall(function() tc:SetMaterial(0, base) end) end
end

-- our options, by STORROR's tab (the grid's Parameter: 4 torso, 5 legs, 6 feet)
-- (and Luigi's, Wario's and Waluigi's - "make 3 other charaters and all they're clothing", 2026-11-01: their tops,
-- Wario's and Waluigi's trousers and shoes - Luigi wears Mario's jeans and brown shoes; pictures from
-- make_character_textures.py. One of ours on each part at a time: `slot`.)
local function shirt_of(c) return function(a, p) return shirt_on(a, p, "shirt_" .. c .. ".png", "body_" .. c .. ".png") end end
local function jeans_of(c) return function(a, p) return jeans_on(a, p, "jeans_" .. c .. ".png") end end
local function shoes_of(cols) return function(a, p) return shoes_on(a, p, cols) end end
local GREEN_SHOES = { { 0.030, 0.17, 0.040 }, { 0.018, 0.10, 0.024 }, { 0.008, 0.035, 0.010 }, { 0.045, 0.22, 0.06 } }
local ORANGE_SHOES = { { 0.50, 0.16, 0.015 }, { 0.32, 0.10, 0.010 }, { 0.07, 0.025, 0.005 }, { 0.58, 0.22, 0.03 } }
local OPTIONS = {
    { key = "torso", slot = "torso", param = 4, label = "MARIO SHIRT", thumb = "shirt_thumb.png", on = shirt_on, still = shirt_still, off = shirt_off },
    { key = "legs", slot = "legs", param = 5, label = "JEANS", thumb = "jeans_thumb.png", on = jeans_on, still = jeans_still, off = jeans_off },
    { key = "feet", slot = "feet", param = 6, label = "BROWN SHOES", thumb = "shoes_thumb.png", on = shoes_on, still = shoes_still, off = shoes_off },
    { key = "torso_luigi", slot = "torso", param = 4, label = "LUIGI SHIRT", thumb = "shirt_thumb_luigi.png", on = shirt_of("luigi"), still = shirt_still, off = shirt_off },
    { key = "torso_wario", slot = "torso", param = 4, label = "WARIO SHIRT", thumb = "shirt_thumb_wario.png", on = shirt_of("wario"), still = shirt_still, off = shirt_off },
    { key = "legs_wario", slot = "legs", param = 5, label = "WARIO PANTS", thumb = "jeans_thumb_wario.png", on = jeans_of("wario"), still = jeans_still, off = jeans_off },
    { key = "feet_wario", slot = "feet", param = 6, label = "WARIO SHOES", thumb = "shoes_thumb_wario.png", on = shoes_of(GREEN_SHOES), still = shoes_still, off = shoes_off },
    { key = "torso_waluigi", slot = "torso", param = 4, label = "WALUIGI SHIRT", thumb = "shirt_thumb_waluigi.png", on = shirt_of("waluigi"), still = shirt_still, off = shirt_off },
    { key = "legs_waluigi", slot = "legs", param = 5, label = "WALUIGI PANTS", thumb = "jeans_thumb_waluigi.png", on = jeans_of("waluigi"), still = jeans_still, off = jeans_off },
    { key = "feet_waluigi", slot = "feet", param = 6, label = "WALUIGI SHOES", thumb = "shoes_thumb_waluigi.png", on = shoes_of(ORANGE_SHOES), still = shoes_still, off = shoes_off },
}
local OPT = {}
for _, o in ipairs(OPTIONS) do OPT[o.key] = o end
-- each character's clothes (put on when its face is picked: M.dress_char)
local OUTFIT = {
    mario = { "torso", "legs", "feet" },
    luigi = { "torso_luigi", "legs", "feet" },
    wario = { "torso_wario", "legs_wario", "feet_wario" },
    waluigi = { "torso_waluigi", "legs_waluigi", "feet_waluigi" },
}

local loaded = false
local chosen = {}                        -- key -> true
local function load_choice()
    loaded = true
    local f = io.open(FILE, "r")
    -- (a new player's clothes: Mario's shirt, overalls and shoes - "Under Character Mario head chest pants and shoes
    -- should also be on", 2026-11-01)
    if not f then chosen = { torso = true, legs = true, feet = true }; return end
    local src = f:read("a"); f:close()
    local fn = load(src, "clothes", "t", {})
    local ok, data = pcall(fn or function() end)
    if ok and type(data) == "table" then for k, v in pairs(data) do if v == true and OPT[k] then chosen[k] = true end end end
    -- (one of ours on each part: the first in OPTIONS kept)
    local taken = {}
    for _, o in ipairs(OPTIONS) do
        if chosen[o.key] then
            if taken[o.slot] then chosen[o.key] = nil else taken[o.slot] = true end
        end
    end
end
local function save_choice()
    local f = io.open(FILE, "w")
    if not f then log("could not write %s", FILE); return end
    local parts = {}
    for k, v in pairs(chosen) do if v then parts[#parts + 1] = string.format("%s = true", k) end end
    f:write("-- SM64Map: clothes of ours chosen on STORROR's CHARACTER screen (written by the mod)\nreturn { ",
        table.concat(parts, ", "), " }\n")
    f:close()
end

local state = {}                         -- per option key
local function st(o)
    local s = state[o.key]
    if not s then s = { find_t = 0.0, figure_t = 0.0 }; state[o.key] = s end
    return s
end

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

local function add_button(o, s, g)
    local list = buttons(g)
    if #list == 0 then return end
    local first = list[1].it
    -- (STORROR's own tiles only: not our other buttons already in this grid)
    local ours = M.ours_set and M.ours_set() or {}
    s.others = {}
    for _, b in ipairs(list) do
        if not ours[b.it:GetAddress()] then s.others[#s.others + 1] = keep(b.it) end
    end
    local t = texture(o.thumb)
    if not t then return end
    local row = list[#list].row
    if row:GetChildrenCount() >= list[1].row:GetChildrenCount() then
        local nr = nil
        pcall(function()
            nr = StaticConstructObject(StaticFindObject("/Script/UMG.HorizontalBox"), g.Grid.RowHolder:GetOuter())
            g.Grid.RowHolder:AddChild(nr)
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
    s.item = keep(it)
    s.item_grid = g:GetAddress()
    s.saved_seen = nil
    log("character screen: %s button added", o.label)
end

local function the_grid(o, s, dt)
    local g = alive(s.grid)
    if g then
        local ok, vis = pcall(function() return g:IsVisible() end)
        if ok and vis then return g end
    end
    s.find_t = s.find_t - dt
    if s.find_t > 0 then return nil end
    s.find_t = 0.3
    s.grid = nil
    for _, x in ipairs(FindAllOf("SPPGridTabWidgetBP_C") or {}) do
        local ok, yes = pcall(function() return x.Parameter == o.param and x:IsVisible() end)
        if ok and yes then s.grid = keep(x); return x end
    end
    return nil
end

-- (Mario's comes off only when STORROR's own tick moves from one of its buttons to another - an A press on another -
-- once the menu has stood open SETTLE seconds: opening, STORROR moves its tick and its picking-out about by itself, and
-- that dropped the Mario clothes - "when in the menu its starts on another panel so when you leave it turns off the
-- mario cloths", 2026-10-17. Leaving the menu on another button no longer drops it.)
-- (charhold.lua holds what he wears on STORROR's CHARACTER screen until a pick: a STORROR cloth picked on our tab
-- takes ours off - at once on him, chosen no more as the menu shuts)
local SLOT_FIELD = { torso = "TorsoClothing", legs = "LegsClothing", feet = "FeetClothing" }
local FIELD_OF = {}
for _, o in ipairs(OPTIONS) do FIELD_OF[o.key] = SLOT_FIELD[o.slot] end
local function hold_picked(o)
    local CH = package.loaded["charhold"]
    return CH and CH.picked and CH.picked(FIELD_OF[o.key]) or false
end
local function holding()
    local CH = package.loaded["charhold"]
    return CH and CH.holding and CH.holding() or false
end
-- ours chosen and on him now: the other of ours on that part off first (charhold no longer counts a pick of
-- STORROR's own there)
local function choose(o, pawn)
    for _, q in ipairs(OPTIONS) do
        if q ~= o and q.slot == o.slot and chosen[q.key] then
            chosen[q.key] = nil
            local qs = st(q)
            if pawn and qs.applied then pcall(q.off, pawn, qs.applied) end
            qs.applied = nil
        end
    end
    local s = st(o)
    chosen[o.key] = true; save_choice()
    s.dropped = nil
    local CH = package.loaded["charhold"]
    if CH and CH.unpick then pcall(CH.unpick, FIELD_OF[o.key]) end
    if pawn then
        local pa = pawn:GetAddress()
        if s.applied_pawn ~= pa or not s.applied or not o.still(pawn, s.applied) then
            s.applied = o.on(pawn, (s.applied_pawn == pa) and s.applied or nil)
            s.applied_pawn = pa
        end
    end
end
local closed_t, was_open = 0.0, false
local SETTLE, open_t = 1.5, 0.0
local check_t = 0.0             -- (whether STORROR has put its own back is looked at twice a second, not every frame:
                                -- each look walks his components - 0.85 ms a frame, "Im started to get some stuttering")

-- every tick, from pause.lua (menu_open: STORROR's menu is up)
function M.tick(dt, menu_open)
    if not loaded then load_choice() end
    local pawn = lib.pawn()
    if menu_open then closed_t = 0.0 else closed_t = closed_t + dt end
    if menu_open then open_t = open_t + dt else open_t = 0.0 end
    local shut_now = was_open and not menu_open
    was_open = menu_open
    check_t = check_t - dt
    local checking = check_t <= 0.0
    -- (STORROR's own grids - our buttons on them, watched every frame the menu is up - only while they are the CHARACTER
    -- tab's: charmenu.lua's slots page is it now, the grids hidden and shut off, and the watch was 1.5 ms a frame of a
    -- pause - "it still loses about 40fps", 2026-11-04)
    local CMN = package.loaded["charmenu"]
    local grids = not (CMN and CMN.ON)

    for _, o in ipairs(OPTIONS) do
        local s = st(o)
        -- the menu just shut: the button picked out last decides
        if shut_now then
            if (s.dropped or hold_picked(o)) and chosen[o.key] then
                chosen[o.key] = nil; save_choice()
                if pawn and s.applied then pcall(o.off, pawn, s.applied) end
                s.applied = nil
                log("character screen: STORROR's tick moved off it - %s off", o.label)
            end
            s.dropped = nil
            s.last_focus, s.focus_prev, s.moved = nil, nil, false
        end
        -- on the athlete, outside the menu: put (back) on whenever STORROR's own is on
        -- (and in the menu while charhold holds him as he is - he is what the CHARACTER screen shows now)
        if chosen[o.key] and pawn and ((not menu_open and closed_t > 0.6) or (menu_open and holding() and not s.dropped
            and not hold_picked(o))) and check_t <= 0.0 then
            local pa = pawn:GetAddress()
            if s.applied_pawn ~= pa or not s.applied or not o.still(pawn, s.applied) then
                s.applied = o.on(pawn, (s.applied_pawn == pa) and s.applied or nil)
                s.applied_pawn = pa
                if s.applied then log("character screen: %s on", o.label) end
            end
        end

        if menu_open and grids then
            local g = the_grid(o, s, dt)
            if not g then s.vis_since = nil end
            if g then
                local it = alive(s.item)
                if it and s.item_grid ~= g:GetAddress() then it = nil end
                if it then
                    local ok, parent = pcall(function() return it:GetParent() end)
                    if not (ok and parent and parent:IsValid()) then it = nil end
                end
                if not it then add_button(o, s, g); it = alive(s.item) end
                -- Ours chosen by a click on it, and on him at once - not by the cursor resting on it ("when hovering over
                -- mario items it instantly switches instead of being a click", 2026-11-01). STORROR's grid knows only its
                -- own tiles, so a click on ours reaches nothing of its; the button itself reads pressed while the mouse
                -- button is down on it. STORROR's own tiles pick on a second click (the first only picks them out): its
                -- tick moving to another takes ours off and its cloth on (charhold.lua sees it: hold_picked); a click on
                -- the tile its tick is already on - which does not move - does the same (charhold pick_now).
                if it then
                    local now_t = os.clock()
                    if not s.vis_since then s.vis_since = now_t end
                    local settled = open_t >= SETTLE and now_t - s.vis_since > 0.6
                    local CH = package.loaded["charhold"]
                    local okp, pr = pcall(function() return it:IsPressed() end)
                    pr = (okp and pr) and true or false
                    if pr and not s.pressed and settled and not chosen[o.key] then
                        choose(o, pawn)
                        log("character screen: %s clicked - chosen, on him", o.label)
                    end
                    s.pressed = pr
                    s.opress = s.opress or {}
                    for i, k in ipairs(s.others or {}) do
                        local b = alive(k)
                        local bp = false
                        if b then
                            local okb, v = pcall(function() return b:IsPressed() and b.SavedIcon:IsVisible() end)
                            bp = (okb and v) and true or false
                        end
                        if bp and not s.opress[i] and settled and chosen[o.key] then
                            chosen[o.key] = nil; save_choice()
                            if pawn and s.applied then pcall(o.off, pawn, s.applied) end
                            s.applied = nil
                            if CH and CH.pick_now then pcall(CH.pick_now, FIELD_OF[o.key]) end
                            log("character screen: one of STORROR's clicked - %s off", o.label)
                        end
                        s.opress[i] = bp
                    end
                    if chosen[o.key] and hold_picked(o) then
                        chosen[o.key] = nil; save_choice()
                        if pawn and s.applied then pcall(o.off, pawn, s.applied) end
                        s.applied = nil
                        log("character screen: one of STORROR's picked - %s off", o.label)
                    end
                end
                if it then
                    -- (what is picked out; STORROR's tick moving to another of its buttons)
                    local okh, hm = pcall(function() return it:IsHovered() end)
                    local now = (okh and hm) and "ours" or nil
                    local saved = nil
                    for i, k in ipairs(s.others or {}) do
                        local b = alive(k)
                        if b then
                            local okb, hb = pcall(function() return b:IsHovered() end)
                            if okb and hb and not now then now = i end
                            local okv, v = pcall(function() return b.SavedIcon:IsVisible() end)
                            if okv and v then saved = i end
                        end
                    end
                    if now ~= nil and open_t < SETTLE then s.focus_prev = now
                    elseif now ~= nil then
                        if s.focus_prev ~= nil and now ~= s.focus_prev then s.moved = true end
                        s.focus_prev = now
                        if s.moved then s.last_focus = (now == "ours") and "ours" or "other" end
                    end
                    if s.saved_seen == nil or open_t < SETTLE or s.saved_seen == 0 then s.saved_seen = saved or 0
                    elseif saved and saved ~= s.saved_seen then
                        -- (STORROR's tick moved: whether that was a pick of its own or A on ours is charhold.lua's to
                        -- say - by where the cursor was - and a pick of its own reaches here as hold_picked; a drop
                        -- here as well took ours off after A on ours, "every time I try this I cant select what I want")
                        s.saved_seen = saved
                    end
                    -- (the mannequin the screen shows wears ours while its button is picked out)
                    if now == "ours" then
                        s.figure_t = s.figure_t - dt
                        if s.figure_t <= 0 then
                            s.figure_t = 0.3
                            for _, f in ipairs(FindAllOf("PlayerMannequinBP_C") or {}) do
                                local okv, hid = pcall(function() return f.bHidden end)
                                if okv and not hid then
                                    local fa = f:GetAddress()
                                    if s.dressed ~= fa or not o.still(f, s.dressed_name) then
                                        s.dressed, s.dressed_name = fa, o.on(f)
                                    end
                                end
                            end
                        end
                    elseif now ~= nil then
                        s.dressed = nil
                    end
                    -- (its name while picked out; its tick while chosen)
                    pcall(function()
                        if now == "ours" then g.Grid.SelectedItemNameDisplay:SetText(FText(o.label)) end
                    end)
                    pcall(function() it.SavedIcon:SetVisibility(chosen[o.key] and 4 or 1) end)
                end
            end
        end
    end
    if checking then check_t = 0.5 end
end

-- The pad's A on one of our buttons ("cant pick waluigi shirt", 2026-11-01): it never reaches our button - STORROR's
-- grid knows only its own tiles - and STORROR picks one of its own instead (its tick went back and forth between two of
-- its tops at each press). So STORROR's tick moving while the cursor is on one of ours (it marks itself selected) is
-- A on ours: charhold.lua asks here, puts ours on (M.choose_key) and leaves STORROR's own pick out.
function M.focused_option(field)
    for _, o in ipairs(OPTIONS) do
        if FIELD_OF[o.key] == field then
            local s = state[o.key]
            local it = s and alive(s.item)
            if it then
                local ok, on = pcall(function() return it:IsVisible() and (it:GetSelected() or it:IsHovered()) end)
                if ok and on then return o.key end
            end
        end
    end
    return nil
end
-- (charmenu.lua's slots) which of ours is on a part ("torso", "legs", "feet"), and all of ours on it taken off
function M.chosen_in(slot)
    if not loaded then load_choice() end
    for _, o in ipairs(OPTIONS) do if o.slot == slot and chosen[o.key] then return o.key end end
    return nil
end
function M.unchoose_slot(slot)
    if not loaded then load_choice() end
    local pawn = lib.pawn()
    local any = false
    for _, o in ipairs(OPTIONS) do
        if o.slot == slot and chosen[o.key] then
            chosen[o.key] = nil
            any = true
            local s = st(o)
            if pawn and s.applied then pcall(o.off, pawn, s.applied) end
            s.applied = nil
        end
    end
    if any then save_choice() end
end

-- the mod's buttons in STORROR's grids now: address -> option key
function M.ours_keys()
    local t = {}
    for _, o in ipairs(OPTIONS) do
        local s = state[o.key]
        local it = s and alive(s.item)
        if it then t[it:GetAddress()] = o.key end
    end
    return t
end
function M.choose_key(k)
    local o = OPT[k]
    if not o then return end
    if not loaded then load_choice() end
    choose(o, lib.pawn())
    log("character screen: %s picked (A on it) - chosen, on him", o.label)
end

-- a character's clothes all put on (its face picked: charhold.lua)
function M.dress_char(ch)
    local keys = OUTFIT[ch]
    if not keys then return end
    if not loaded then load_choice() end
    local pawn = lib.pawn()
    for _, k in ipairs(keys) do
        local o = OPT[k]
        if o and not chosen[k] then choose(o, pawn) end
    end
    log("character screen: %s's clothes on", ch)
end

-- the mod's buttons in STORROR's grids now, by address (charhold.lua watches the tick on STORROR's own tiles only)
function M.ours_set()
    local t = {}
    for _, o in ipairs(OPTIONS) do
        local s = state[o.key]
        local it = s and alive(s.item)
        if it then t[it:GetAddress()] = true end
    end
    return t
end

-- ours put back on him at once after STORROR's update has put its own on (charhold.lua, while its menu is up) - not a
-- part whose STORROR cloth was picked meanwhile
function M.put_back(pawn)
    if not (pawn and pawn:IsValid()) then return end
    if not loaded then load_choice() end
    local pa = pawn:GetAddress()
    for _, o in ipairs(OPTIONS) do
        local s = st(o)
        if chosen[o.key] and not s.dropped and not hold_picked(o) then
            if s.applied_pawn ~= pa or not s.applied or not o.still(pawn, s.applied) then
                s.applied = o.on(pawn, (s.applied_pawn == pa) and s.applied or nil)
                s.applied_pawn = pa
            end
        end
    end
end

-- (the map gone - STORROR reloaded it with its menu up: what this keeps of it dropped untouched, main.lua's watch on the
-- map - "crash" twice, 2026-11-03, a moment into the game after that reload: an object of the gone map reached for)
-- (each option's grid and buttons, and the skins ours went over; the player's choices kept)
function M.forget()
    state, skins = {}, {}
    closed_t, was_open = 0.0, false
end

return M
