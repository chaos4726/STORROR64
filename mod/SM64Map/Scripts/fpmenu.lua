-- STORROR First Person: the FIRST PERSON tab on STORROR's menu, between CONTROLS and SETTINGS ("first I want to work on
-- a new menu, first person should be in-between settings and controls", 2026-11-09).
--
-- STORROR's menu bar (PauseMenuTabBarBP_C, made afresh each time a menu opens and thrown away as it shuts) builds its
-- tabs from a list on the bar - Tabs: for each tab its id, its title (the name over the row), its button's kind, its
-- page's kind and its icon. Every bar is copied from one template, MenuPresenterBP's own (TEMPLATE). FIRST PERSON goes
-- on that template's list, between CONTROLS and SETTINGS, so that STORROR makes our tab itself on every bar, as it
-- makes its own: its icon in the row, its name over it, its place for LT/RT. An eye its icon (ui/first_person_icon.png,
-- drawn in the style of STORROR's own white icons); its page one of STORROR's Camera pages, the page's own rows put
-- away, and fpsettings.lua puts the FIRST PERSON switch on it, as on Settings > Camera; the first person settings to
-- come go there too.
-- (Put on each bar from outside as it was made - RegisterTab - the tab took every icon off the row, turned LT/RT about
-- and crashed the game as the menu shut, 2026-11-09: "all the icons disappeared", "hitting lt makes it go right".)
--
-- The list is grown by one on its own (UE4SS grows an array written one past its end, with its new place zeroed, and
-- may move it to do so), then SETTINGS is copied whole into the new last place, and the place it was in is made ours
-- field by field. Done once a session; looked at again now and then, in case the template is ever made anew.
-- No widget of a menu is kept from one look to the next: the menus are found afresh each time.
local lib = require("lib")
local log = lib.log
local M = {}

local TAB_ID, TAB_TITLE = "FirstPerson", "FIRST PERSON"
local BEFORE = "Settings"                             -- (ours goes in the place SETTINGS has, SETTINGS after it)
local TEMPLATE = "/SPP/UI/PauseMenu/MenuPresenterBP.MenuPresenterBP_C:WidgetTree.MenuTabBar"
local PAGE_CLASS = "/SPP/UI/PauseMenu/CameraMenu/SPPCameraSettingsWidgetBP.SPPCameraSettingsWidgetBP_C"
local PAGE_NAME = "SPPCameraSettingsWidgetBP_C"
M.icon_file = nil                                     -- (main.lua: the icon's full path)
M.enabled = true
-- (the Super Mario 64 mashup - fpextra.lua - sets this: true only while a first-person file is being played; the tab
-- is put on the list the first time it is, and on every other menu it is hidden and can't be picked: "the way I want
-- it added to mario is only in the first person mode. should not appear anywhere else", 2026-11-10. nil: always.)
M.active = nil


local look_t, check_t = 0.0, 0.0
local patched = false
local failed = false

local function alive(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

-- our tab on a bar shown and pickable, or hidden and not (only touched when it is not already so)
local function show_tab(bar, on)
    local id = FName(TAB_ID)
    local b = bar:GetTabButtonBaseByID(id)
    if not alive(b) then return end
    local seen = b:GetVisibility() ~= 1
    if seen == on then return end
    bar:SetTabVisibility(id, on and 0 or 1)           -- (visible, or collapsed)
    bar:SetTabEnabled(id, on)
end

-- the ids on a bar's list, in order (never read past its end: UE4SS grows an array read out of range)
local function ids_on(bar)
    local t = {}
    pcall(function()
        local tabs = bar.Tabs
        local n = #tabs
        for i = 1, n do t[i] = tabs[i].Name:ToString() end
    end)
    return t
end

-- ours on the template's list, before SETTINGS (returns a word for the log)
local function patch(tmpl)
    local ids = ids_on(tmpl)
    for _, id in ipairs(ids) do if id == TAB_ID then return "there" end end
    local at = nil
    for i, id in ipairs(ids) do if id == BEFORE then at = i end end
    if not at then return "no " .. BEFORE .. " on the list (" .. table.concat(ids, ",") .. ")" end
    local cls = StaticFindObject(PAGE_CLASS)
    if not alive(cls) then pcall(function() cls = LoadAsset(PAGE_CLASS) end) end
    if not alive(cls) then return "no page class" end
    local tex = nil
    if M.icon_file then
        pcall(function()
            local KRL = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
            tex = KRL:ImportFileAsTexture2D(lib.world(), M.icon_file)
        end)
    end
    if not alive(tex) then return "no icon" end
    local n = #ids
    local tabs = tmpl.Tabs
    -- (one place more, alone: nothing of the array held while it may move)
    tabs[n + 1] = nil
    tabs = tmpl.Tabs
    if #tabs ~= n + 1 then return "the list did not grow" end
    -- (each place from `at` on moved one along, from the end back: whole copies, the game's own)
    for i = n, at, -1 do
        local list = tmpl.Tabs
        list[i + 1] = list[i]
    end
    -- (and the place SETTINGS was in made ours: SETTINGS' button kind kept, as every tab's is the same)
    local list = tmpl.Tabs
    local e = list[at]
    e.Name = FName(TAB_ID)
    e.Title = FText(TAB_TITLE)
    e.ContentClass = cls
    e.Icon = tex
    -- (the icon kept by the list: a texture kept by Lua alone can be collected under it)
    return "added: " .. table.concat(ids_on(tmpl), ",")
end

-- our page on a menu bar: the Camera page among the bar's own pages (STORROR's own Camera page is further down,
-- inside its SETTINGS tab's page)
local function our_page(bar)
    local found = nil
    pcall(function()
        local sw = bar:GetLinkedSwitcher()
        for i = 0, sw:GetChildrenCount() - 1 do
            local c = sw:GetChildAt(i)
            if alive(c) and c:GetClass():GetFName():ToString() == PAGE_NAME then found = c end
        end
    end)
    return found
end

-- Smaller, so that more is seen at once ("make the settings smaller so more fits on screen", 2026-11-09): the page's
-- whole column drawn at SHRINK from its top left (each row on its own was put back by STORROR's row animations), and the
-- room it takes in the page's scrolling box cut to match (its slot's bottom padding), so the scrolling goes by what is seen.
local SHRINK = 0.65
local cut = {}                              -- the padding last put, by page address
local function smaller(page, box)
    box:SetRenderTransformPivot({ X = 0.0, Y = 0.0 })
    box:SetRenderScale({ X = SHRINK, Y = SHRINK })
    local h = box:GetDesiredSize().Y
    if not (h and h > 1.0) then return end
    local want = -(1.0 - SHRINK) * h
    local key = page:GetAddress()
    if cut[key] and math.abs(cut[key] - want) < 1.0 then return end
    box.Slot:SetPadding({ Left = 0.0, Top = 0.0, Right = 0.0, Bottom = want })
    cut[key] = want
end

-- the page's own rows (STORROR's camera settings) put away on our page: not seen, not among the column's buttons. Ours
-- (fpsettings.lua's) stay. And its divider, the white line down the page's edge, put away too: with the backdrop off it
-- stood alone over the game ("also this white strip", 2026-11-09).
local FOCUS_FOR = 1.0
local focus_until = 0.0
local function give_focus(page)
    if not (alive(page) and page:IsVisible()) or page:HasFocusedDescendants() then return end
    local box = page.VerticalBox
    if not alive(box) then return end
    local g = box.ButtonGroup
    if not alive(g) or g:GetButtonCount() == 0 then return end
    local i = g:GetSelectedButtonIndex()
    if i < 0 or i >= g:GetButtonCount() then i = 0 end
    local row = g:GetButtonBaseAtIndex(i)
    if alive(row) and row:IsVisible() then row:SetFocus() end
end

local function hide_theirs(page)
    pcall(function()
        local root = page.WidgetTree.RootWidget
        for i = 0, root:GetChildrenCount() - 1 do
            local c = root:GetChildAt(i)
            if alive(c) and c:GetClass():GetFName():ToString() == "MenuVerticalSeparatorBP_C" and c:GetVisibility() ~= 1 then
                c:SetVisibility(1)                                                 -- (collapsed)
            end
        end
    end)
    local box = nil
    pcall(function() box = page.VerticalBox end)
    if not alive(box) then return end
    local S = package.loaded["fpsettings"]
    local g = box.ButtonGroup
    for i = 0, box:GetChildrenCount() - 1 do
        local c = box:GetChildAt(i)
        if alive(c) and not (S and S.is_row and S.is_row(c)) then
            if c:GetVisibility() ~= 1 then c:SetVisibility(1) end                 -- (collapsed)
            pcall(function() if alive(g) and g:FindButtonIndex(c) >= 0 then g:RemoveWidget(c) end end)
        end
    end
    pcall(smaller, page, box)
end

-- STORROR's menu backdrop - the dark, scratched picture behind its menu - is not a widget: it is a post-process volume
-- in the level, HITSBackgroudActorBP (sic), whose material the menu fades in. Switched off while FIRST PERSON is the tab
-- open, so that the game, seen first person, shows behind it ("Specifically for the first person menu I want to remove
-- the backround in the menu, the black overlay", 2026-11-09); put back as another tab is picked, and a moment after the
-- menu shuts (once its own fade has run). With the menu shut it stands on, at full weight - its material hides it - so
-- putting back what it had is right either way. (Found by the Super Mario 64 mashup, pause.lua, 2026-10-14.)
local BACKDROP = "HITSBackgroudActorBP_C"
local held = {}                 -- the backdrops switched off, by address: { en, w } as they were
local fp_on, shut_t = false, nil

-- the backdrops of the map we are in (found afresh at most once a second: a search of the whole game, and asked every
-- frame while FIRST PERSON is open - "we need to optimize", 2026-11-09; forgotten with the map)
local bd_list, bd_t = nil, 0.0
local function backdrops()
    if bd_list and os.clock() - bd_t < 1.0 then return bd_list end
    local out, here = {}, nil
    pcall(function() here = lib.world():GetAddress() end)
    for _, a in ipairs(FindAllOf(BACKDROP) or {}) do
        pcall(function()
            if a:IsValid() and a:GetOuter():GetOuter():GetAddress() == here then out[#out + 1] = a end   -- (actor, level, world)
        end)
    end
    bd_list, bd_t = out, os.clock()
    return out
end

local function backdrop_off()
    for _, a in ipairs(backdrops()) do
        pcall(function()
            local key = a:GetAddress()
            -- (found already off - by this, before a reload of it - it is noted as it stands with the menu shut, on at
            -- full weight: noted off, it was put back off and every other tab lost its backdrop, 2026-11-09)
            if not held[key] then
                local en, w = a.bEnabled, a.BlendWeight
                if not en and w < 0.001 then en, w = true, 1.0 end
                held[key] = { en = en, w = w }
            end
            if a.bEnabled then a.bEnabled = false end
            if a.BlendWeight ~= 0.0 then a.BlendWeight = 0.0 end
        end)
    end
end

local function backdrop_back()
    if next(held) == nil then return end
    for _, a in ipairs(backdrops()) do
        pcall(function()
            local h = held[a:GetAddress()]
            if h then
                if a.bEnabled ~= h.en then a.bEnabled = h.en end
                if a.BlendWeight ~= h.w then a.BlendWeight = h.w end
            end
        end)
    end
    held = {}
    log("menu: the menu backdrop put back")
end

-- every frame while FIRST PERSON is open: the backdrop kept off; ten times a second while a menu is up: which tab is
-- open, and our page's own rows put away; every few seconds: the template's list seen to
function M.tick(dt)
    if not M.enabled then return end
    if fp_on then pcall(backdrop_off) end
    check_t = check_t - dt
    if check_t <= 0 and not failed and M.active ~= false then
        check_t = patched and 5.0 or 0.5
        local tmpl = StaticFindObject(TEMPLATE)
        if alive(tmpl) then
            local ok, res = pcall(patch, tmpl)
            if not ok then
                failed = true
                log("menu: the FIRST PERSON tab not put on STORROR's list (%s)", tostring(res))
            elseif res ~= "there" then
                log("menu: %s", res)
                patched = res:find("^added") ~= nil
                if not patched then failed = true end
            else
                patched = true
            end
        end
    end
    look_t = look_t - dt
    if look_t > 0 then return end
    -- (ten times a second with a menu up; with none, only to see one open: the bars are found by a search of the whole
    -- game - "we need to optimize", 2026-11-09)
    look_t = M.is_menu_up and 0.1 or 0.3
    local menu_up, on, on_page = false, false, nil
    for _, bar in ipairs(FindAllOf("PauseMenuTabBarBP_C") or {}) do
        pcall(function()
            if not bar:IsValid() or bar:GetFName():ToString():find("^Default__") then return end
            local sw = bar:GetLinkedSwitcher()
            if not alive(sw) then return end                               -- (the template: no switcher)
            local sel = bar:GetSelectedTabId():ToString()
            if sel ~= "None" then menu_up = true end
            local page = our_page(bar)
            if sel == TAB_ID then on = true; on_page = page end
            -- (STORROR's rows on our page kept hidden while a menu is up - not with none: 52 rows gone through ten times
            -- a second for nothing)
            if page and sel ~= "None" then hide_theirs(page) end
            if M.active ~= nil and patched then pcall(show_tab, bar, M.active) end
        end)
    end
    M.is_menu_up = menu_up                  -- (fphud.lua: no crosshair dot over a menu)
    -- (the controller's focus given to our page as the tab comes on: STORROR gives it to its own tabs' pages only, and the
    -- pad could not go down the rows till the page was clicked - "on controller I cant go down the options for some
    -- reason, I have to click on the page first", 2026-11-09. For FOCUS_FOR only, and only while nothing on the page has
    -- it: given for longer, the Mario mashup's focus missed the page and picked a tab.)
    M.tab_open = on                         -- (fphelp.lua: its panel only while FIRST PERSON is the tab shown)
    if on and not fp_on then focus_until = os.clock() + FOCUS_FOR end
    if on and on_page and os.clock() < focus_until then pcall(give_focus, on_page) end
    if on then
        if not fp_on then log("menu: FIRST PERSON open - the menu backdrop off") end
        fp_on, shut_t = true, nil
        pcall(backdrop_off)
    else
        fp_on = false
        if menu_up then
            shut_t = nil
            pcall(backdrop_back)
        elseif next(held) ~= nil then
            shut_t = shut_t or os.clock()
            if os.clock() - shut_t > 1.0 then shut_t = nil; pcall(backdrop_back) end
        end
    end
end

-- (a new map: its backdrop is a new one; the old one's not touched again)
function M.forget() held, fp_on, shut_t = {}, false, nil; bd_list = nil end

M.TAB_ID = TAB_ID
M.our_page = our_page
M.ids_on = ids_on
M.TEMPLATE = TEMPLATE
return M
