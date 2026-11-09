-- SM64Map: settings of the mod's own in STORROR's Settings menu.
--
-- STORROR's Settings > Audio page (CommonAudioMenuWidget) is a column of its sliders (HITSSliderWidget: a title, the
-- slider, its value and a bar). Under its MUSIC slider go more of the same, ours:
--   MARIO 64 MUSIC     how loud Mario 64's music is in the game (music.lua M.set_user). The title's film music is not
--                      Mario 64's, and not touched. (2026-10-15: "One new music slide for mario music INGAME only.")
--   REMIX MUSIC        ON: remixes of Mario 64's tunes, where music_remix/ has one (music.lua M.set_remix); OFF: Mario
--                      64's own. ("also we are going to need a new music slider", 2026-11-01)
--   MARIO FX           how loud Mario's voice is: all of it (sfx.lua M.mario_fx) - his jumps' "Yah!", "Hoo-hoo!",
--                      "Yahoo!", his hurts, falls and deaths, his words on the title and the ending; all the way down,
--                      not heard (2026-10-15: "an option to turn off mario jumping noises in audio settings"; once
--                      MARIO JUMP VOICE, for the jumps alone - 2026-10-27: "make sure mario sounds are tied to our audio
--                      slide", "you could also rename it mario fx").
--   GENERAL SOUNDS     how loud every other sound is - coins, ! boxes, doors, platforms, pipes, stars, the menus
--                      (sfx.lua M.general_fx); all the way down, not heard ("also mario settings also needs general
--                      sounds slider like coins and hat boxes slider", 2026-11-03).
--   ENEMIES VOLUME     how loud the enemies are: their steps, calls, hits and deaths, Bowser's too (sfx.lua
--                      M.enemy_fx); all the way down, not heard ("also in mario settings we need a enemies volume
--                      slider", 2026-11-03).
-- Settings > Graphics (CommonGraphicSettingsMenuWidget), under its SHADOWS:
--   REAL TIME SHADOWS  ON: the levels lit, everything casting its real shadow; OFF: Mario 64's own look, its round
--                      shadows (game.lua G.set_realtime_shadows). One of STORROR's sliders with two places, OFF and ON -
--                      its own ON/OFF rows keep their choices where the mod cannot write them. ("it should be mario
--                      shadows off. it should be real time shadows on", 2026-10-30)
--   RENDER 96          ON: the Render 96 HD texture pack's pictures in place of Mario 64's (lib.lua M.set_r96 - the
--                      Render96 team's, made into textures_r96/ by tools/r96_build.py); OFF: Mario 64's own. Turned
--                      live. ("next I want another graphics option called render 96", 2026-10-31)
-- All of them now on one page: the MARIO SETTINGS tab of STORROR's menu (mario_tabs), not under Audio and Graphics.
-- All kept with the save files (menu.lua), for every file alike.
--
-- Nothing of STORROR's menu is kept here between looks: the pages and the rows are found afresh each time.
local lib = require("lib")
local log = lib.log
local M = {}

local function music() return package.loaded["music"] end
local function menu() return _G.MENU end
local function sfx(name, v) local S = package.loaded["sfx"]; if S then pcall(S.play, name, v) end end

-- the pages ours go on: the page's class, the row of its own ours stand under, and ours in order. All of Mario's on one
-- page of their own, the MARIO SETTINGS tab on STORROR's top bar beside MARIO 64, CHARACTER, CONTROLS and SETTINGS ("I
-- also want a mario settings menu including all of marios settings", "I actually want you to make a new top tab",
-- 2026-11-01) - they were under Settings > Audio's MUSIC and Settings > Graphics' SHADOWS. (`mario`: the page is ours,
-- made for the tab - mario_pages - not found among STORROR's.)
local PAGES = {
    { class = "CommonAudioMenuWidget_C", mario = true, under = "MusicVolumeSlider", rows = {
        { label = "MARIO 64 MUSIC",
          get = function(MN) return MN.mario_music and MN.mario_music() end,
          set = function(MN, v) if MN.set_mario_music then MN.set_mario_music(v) end end,
          apply = function(v) local MU = music(); if MU and MU.set_user then MU.set_user(v) end end },
        -- (ON: the remixes in music_remix/ where there are any, Mario 64's own for the rest - music.lua M.set_remix)
        { label = "REMIX MUSIC", toggle = true,
          get = function(MN) return MN.remix_music and MN.remix_music() end,
          set = function(MN, v) if MN.set_remix_music then MN.set_remix_music(v) end end,
          apply = function(v) local MU = music(); if MU and MU.set_remix then MU.set_remix(v >= 0.5) end end },
        { label = "MARIO FX", was = "MARIO JUMP VOICE",
          get = function(MN) return MN.jump_voice and MN.jump_voice() end,
          set = function(MN, v) if MN.set_jump_voice then MN.set_jump_voice(v) end end,
          -- (once it has stopped moving, a jump's "Hoo!" as loud as it is now set - kept first: sfx.lua's own factor - as a
          -- volume is tried)
          kept = function(v) if v > 0.01 then sfx("mario_hoo") end end },
        { label = "ENEMIES VOLUME",
          get = function(MN) return MN.enemies_volume and MN.enemies_volume() end,
          set = function(MN, v) if MN.set_enemies_volume then MN.set_enemies_volume(v) end end,
          -- (once it has stopped moving, a Goomba's call as loud as it is now set)
          kept = function(v) if v > 0.01 then sfx("en_goomba_alert") end end },
        { label = "GENERAL SOUNDS",
          get = function(MN) return MN.general_volume and MN.general_volume() end,
          set = function(MN, v) if MN.set_general_volume then MN.set_general_volume(v) end end,
          -- (once it has stopped moving, a coin as loud as it is now set)
          kept = function(v) if v > 0.01 then sfx("coin") end end },
        { label = "REAL TIME SHADOWS", toggle = true,
          get = function(MN) return MN.realtime_shadows and MN.realtime_shadows() end,
          set = function(MN, v) if MN.set_realtime_shadows then MN.set_realtime_shadows(v) end end,
          apply = function(v)
              local G = package.loaded["game"]
              if G and G.set_realtime_shadows then G.set_realtime_shadows(v >= 0.5) end
          end },
        { label = "RENDER 96", toggle = true,
          get = function(MN) return MN.render96 and MN.render96() end,
          set = function(MN, v) if MN.set_render96 then MN.set_render96(v) end end,
          apply = function(v) if lib.set_r96 then lib.set_r96(v >= 0.5) end end },
        -- (the HUD's TIME, the run's clock: the file select's TIMER switch - "add a timer off switch in mario settings",
        -- 2026-11-01; on at once as it is flipped)
        { label = "TIMER", toggle = true,
          get = function(MN) return MN.timer_setting and MN.timer_setting() end,
          set = function(MN, v) if MN.set_timer then MN.set_timer(v) end end,
          apply = function(v) local MN = menu(); if MN and MN.set_timer then MN.set_timer(v) end end },
        -- (GORE - the HUMAN secret, Final Bowser beaten in a HUMAN file: secrets.lua - a gruesome death in any mode as
        -- the power runs out, no one-hit death; not on the page till then: "a new setting in the settings that allows the
        -- player to be gored in any mode just without the one tap", 2026-11-04)
        { label = "GORE", toggle = true,
          shown = function() local ok, S = pcall(require, "secrets"); return ok and S and S.has("gore") end,
          get = function() local ok, S = pcall(require, "secrets"); return (ok and S and S.gore_setting()) and 1.0 or 0.0 end,
          set = function(_, v) local ok, S = pcall(require, "secrets"); if ok and S then S.set_gore_any(v >= 0.5) end end },
        -- (the two modes, HUMAN and IRONMAN, are not here: they are the file select's, beside FIRST PERSON, and a file
        -- keeps its own for good - "once its on a file it cant be removed unless deleted", 2026-11-02)
    } },
}

-- The MARIO SETTINGS tab: on each of STORROR's top tab bars (its pause menu's, its main menu's - PauseMenuTabBarBP_C, with
-- its page switcher), a tab of the same kind as theirs right after MARIO 64, Mario's cap badge its icon. Its content one
-- of STORROR's SETTINGS (MultiPageSettingsMenuWidget) made for it - a top tab's content is such a many-page widget, which
-- hands the keys and the mouse to its page; a bare page there took none (2026-11-01) - held on its AUDIO page with its
-- other pages' tabs hidden and shut off and its tab row out of sight (mario_multi). On that audio page its own rows put
-- away (collapsed, out of the column's buttons - hide_theirs) and ours on it. All kept in _G (a reload of this file does
-- not make the tab twice).
local TAB_ID, TAB_TITLE, TAB_AT = "MarioSettings", "MARIO SETTINGS", 2
-- The Mario rows on STORROR's own SPOTS tab, not a tab of ours ("put it in the spots tab", 2026-11-01): a tab put in by
-- the mod is one STORROR's menu does not know - the pad's LT/RT and its focus stopped at it. SPOTS' page (its travel
-- page, a many-page widget: ESTATE and CITY) takes ours as a page of its own, picked, ESTATE and CITY hidden and shut
-- off, its tab row out of sight (mario_spots); SPOTS named MARIO SETTINGS in the tab row.
local IN_SPOTS = false      -- (back to MARIO SETTINGS a tab of its own beside SPOTS: "WHERE DID THE MARIO SETTINGS GO ...
                             -- GO BACK", 2026-11-01)
local SPOTS_SUB = "MarioSettings"
-- (SPOTS keeps its own name; the Mario page is a tab under it, MARIO 64, in SPOTS' own row where ESTATE and CITY were -
-- "wheres the mario 64 tab that should be under the SPOTS tab", "nope bring back the spots tab", 2026-11-01)
local SPOTS_SUB_TITLE = "MARIO 64"
if IN_SPOTS then TAB_ID = "SPOTS"; TAB_TITLE = "SPOTS" end
local MULTI_CLASS = "/SPP/UI/PauseMenu/Settings/MultiPageSettingsMenuWidget.MultiPageSettingsMenuWidget_C"
-- (the tab's content a bare audio page again, not a SETTINGS many-page widget of our own: with that, the keyboard's Z
-- and C left the tab but the gamepad's LT and RT did not - "still cant leave mario menu via ltrt", 2026-11-01. STORROR's
-- many-page widgets take the pad's page keys themselves and pass them to its menu, which does not know ours. The bare
-- page takes the keys once its row has focus - mario_focus.)
local BARE = true
local PAGE_CLASS = "/SPP/UI/PauseMenu/Audio/CommonAudioMenuWidget.CommonAudioMenuWidget_C"
local SUB_KEEP, SUB_HIDE = "Audio", { "GRAPHICS", "Gameplay", "UI", "Camera", "Exit" }
local TOP_IDS = { "ADVENTURE", "SPOTS", "Character", "ONLINE", "Controls", "Settings" }    -- (STORROR's own top tabs)
local tab_colors                                  -- (below: the tab row's colours)
local MW = _G.SM64_MARIO_MULTI or {}           -- (our many-page widgets, by address)
_G.SM64_MARIO_MULTI = MW
local TAB_ICON = "textures_r96\\actors__mario_cap__mario_cap_logo.rgba16.png"
local MP = _G.SM64_MARIO_PAGES or {}
_G.SM64_MARIO_PAGES = MP
-- (the bars with the tab, by address: their title - the bar's Title, over its tabs - is STORROR's from its own list of
-- tabs, which ours is not on; ours is put there while it is the one on: mario_title)
local MB = _G.SM64_MARIO_BARS or {}
_G.SM64_MARIO_BARS = MB
local tab_icon = nil
local function alive(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end
-- the tab on one bar (its menu's), if it is not there yet
local function mario_tab_on(bar)
    local WBL = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local cpath = BARE and PAGE_CLASS or MULTI_CLASS
    local cls = StaticFindObject(cpath)
    if not alive(cls) then pcall(function() cls = LoadAsset(cpath) end) end
    if not (WBL and alive(cls)) then return end
        do
            if not bar:IsValid() or bar:GetFName():ToString():find("^Default__") then return end
            local sw = bar:GetLinkedSwitcher()
            if not alive(sw) then return end                           -- (the template's: no switcher)
            local have = bar:GetTabButtonBaseByID(FName(TAB_ID))
            if alive(have) then MB[bar:GetAddress()] = bar; return end
            local ref = bar:GetTabButtonBaseByID(FName("Settings"))
            if not alive(ref) then return end
            local page = WBL:Create(lib.world(), cls, ref:GetOwningPlayer())
            if not alive(page) then return end
            -- (the page into the menu's page switcher: RegisterTab does not put it there, and a tab whose page is not
            -- among the switcher's shows the page before it)
            if sw:GetChildIndex(page) < 0 then sw:AddChild(page) end
            local cur = bar:GetSelectedTabId()
            -- (each tab's on/off and shown/hidden as they are, put back after: with ours put in, STORROR's own hidden
            -- tabs' state moved one along - ONLINE shown, CONTROLS hidden and shut off, 2026-11-01)
            local was = {}
            for _, id in ipairs(TOP_IDS) do
                pcall(function()
                    local tb = bar:GetTabButtonBaseByID(FName(id))
                    if alive(tb) then was[id] = { en = tb:GetIsEnabled(), vis = tb:GetVisibility() } end
                end)
            end
            bar:RegisterTab(FName(TAB_ID), ref:GetClass(), page, TAB_AT)
            local b = bar:GetTabButtonBaseByID(FName(TAB_ID))
            -- (and its button straight after MARIO 64's among the bar's buttons, which Z and C step through: RegisterTab
            -- puts it last there, after SETTINGS, whatever place it is given. The ones after MARIO 64 off and back on
            -- after it; the tab that was on, on again.)
            pcall(function()
                local g, spots = bar.TabButtonGroup, bar:GetTabButtonBaseByID(FName("SPOTS"))
                if not (alive(g) and alive(b) and alive(spots)) then return end
                local si, mi = g:FindButtonIndex(spots), g:FindButtonIndex(b)
                if si < 0 or mi < 0 or mi == si + 1 then return end
                local after = {}
                for i = si + 1, g:GetButtonCount() - 1 do
                    local x = g:GetButtonBaseAtIndex(i)
                    if alive(x) and x:GetAddress() ~= b:GetAddress() then after[#after + 1] = x end
                end
                g:RemoveWidget(b)
                for _, x in ipairs(after) do g:RemoveWidget(x) end
                g:AddWidget(b)
                for _, x in ipairs(after) do g:AddWidget(x) end
                local id = cur and cur:ToString() or "None"
                if id ~= "None" then bar:SelectTabByID(cur, true) end
            end)
            for id, st in pairs(was) do
                pcall(function()
                    local tb = bar:GetTabButtonBaseByID(FName(id))
                    if not alive(tb) then return end
                    if tb:GetIsEnabled() ~= st.en then pcall(function() bar:SetTabEnabled(FName(id), st.en) end) end
                    if tb:GetVisibility() ~= st.vis then pcall(function() bar:SetTabVisibility(FName(id), st.vis) end) end
                    -- (and on the button itself, should the bar's own calls land on another)
                    if tb:GetIsEnabled() ~= st.en then tb:SetIsEnabled(st.en) end
                    if tb:GetVisibility() ~= st.vis then tb:SetVisibility(st.vis) end
                end)
            end
            if alive(b) then
                pcall(function() b["Button Text"] = TAB_TITLE end)
                pcall(function() b.ButtonTextLabel:SetText(FText(TAB_TITLE)) end)
                if not alive(tab_icon) then
                    pcall(function()
                        tab_icon = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary"):ImportFileAsTexture2D(lib.world(),
                            lib.MOD_DIR .. TAB_ICON)
                    end)
                end
                if alive(tab_icon) then pcall(function() b.Icon:SetBrushFromTexture(tab_icon, false) end) end
            end
            if BARE then MP[#MP + 1] = page else MW[page:GetAddress()] = page end
            MB[bar:GetAddress()] = bar
            log("settings: the %s tab on %s (%d tabs)", TAB_TITLE, bar:GetFName():ToString(), bar:GetTabCount())
        end
end
-- our page on SPOTS' travel page (one bar's menu): made once, a page of the travel page's own switcher and a tab of
-- its own row; each look, ESTATE and CITY hidden and shut off, ours picked, that row out of sight
local function mario_spots(bar)
    if not bar:IsValid() or bar:GetFName():ToString():find("^Default__") then return end
    local sw = bar:GetLinkedSwitcher()
    if not alive(sw) then return end
    local tw = nil
    for i = 0, sw:GetChildrenCount() - 1 do
        local c = sw:GetChildAt(i)
        if alive(c) and c:GetClass():GetFName():ToString() == "MultiPageTravelMenuWidget_C" then tw = c end
    end
    if not alive(tw) then return end
    MB[bar:GetAddress()] = bar
    local sub, asw = tw.MenuTabBar, tw.AnimatedSwitcher
    if not (alive(sub) and alive(asw)) then return end
    local have = sub:GetTabButtonBaseByID(FName(SPOTS_SUB))
    if not alive(have) then
        local ref = sub:GetTabButtonBaseByID(FName("Estate"))
        if not alive(ref) then return end
        local WBL = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        local cls = StaticFindObject(PAGE_CLASS)
        if not alive(cls) then pcall(function() cls = LoadAsset(PAGE_CLASS) end) end
        if not (WBL and alive(cls)) then return end
        local page = WBL:Create(lib.world(), cls, ref:GetOwningPlayer())
        if not alive(page) then return end
        if asw:GetChildIndex(page) < 0 then asw:AddChild(page) end
        sub:RegisterTab(FName(SPOTS_SUB), ref:GetClass(), page, -1)
        MP[#MP + 1] = page
        log("settings: the Mario page on SPOTS (%d of its tabs)", sub:GetTabCount())
    end
    for _, id in ipairs({ "Estate", "city" }) do
        pcall(function()
            local b = sub:GetTabButtonBaseByID(FName(id))
            if alive(b) and (b:GetIsEnabled() or b:GetVisibility() ~= 1) then
                sub:SetTabVisibility(FName(id), 1)
                sub:SetTabEnabled(FName(id), false)
            end
        end)
    end
    if sub:GetSelectedTabId():ToString() ~= SPOTS_SUB then sub:SelectTabByID(FName(SPOTS_SUB), true) end
    -- (SPOTS' row seen - put away before - with ours named MARIO 64 in it)
    if sub:GetVisibility() == 1 then sub:SetVisibility(4) end
    pcall(function()
        local b = sub:GetTabButtonBaseByID(FName(SPOTS_SUB))
        if not alive(b) then return end
        -- (its button into the row with ESTATE's and CITY's: STORROR puts its own there, not one put in after)
        local row = sub.TabBarContent
        if alive(row) and row:GetChildIndex(b) < 0 then
            local sl = row:AddChildToHorizontalBox(b)
            pcall(function()
                local est = sub:GetTabButtonBaseByID(FName("Estate"))
                local es = est.Slot
                sl:SetPadding(es.Padding)
                sl:SetVerticalAlignment(es.VerticalAlignment)
                sl:SetHorizontalAlignment(es.HorizontalAlignment)
            end)
        end
        local lab = b.ButtonTextLabel
        if alive(lab) and lab:GetText():ToString() ~= SPOTS_SUB_TITLE then
            lab:SetText(FText(SPOTS_SUB_TITLE))
            pcall(function() b["Button Text"] = SPOTS_SUB_TITLE end)
        end
    end)
end
-- Mario 64's pause screen in the SPOTS tab (pause.lua draws it under STORROR's menu while SPOTS is on): "now IN THE
-- SPOTS TAB, just like when you press START on a nintendo 64 controller and it pulls up the mario 64 menu", "try to make
-- as original as humanly possible", 2026-11-01. STORROR's menu keeps every key from the mod while it is up, but its own
-- rows move with them: SPOTS' page holds three of ours, unseen, the middle one picked - the pick stepping to the one
-- over it is Up, to the one under it Down, its slider pushed right is A; each put back at once (m64_spots, spots_input).
local SPOTS_M64 = true
local M64_SUB = "Mario64"
local CTL = _G.SM64_SPOTS_CTL or {}           -- (by page address: { page, rows })
_G.SM64_SPOTS_CTL = CTL
local ctl_ev = { up = 0, down = 0, ok = 0 }
function M.spots_input()
    local e = { up = ctl_ev.up, down = ctl_ev.down, ok = ctl_ev.ok }
    ctl_ev.up, ctl_ev.down, ctl_ev.ok = 0, 0, 0
    return e
end
local m64_spots                                 -- (below: it wants the slider helpers)
local function mario_tabs()
    for _, bar in ipairs(FindAllOf("PauseMenuTabBarBP_C") or {}) do
        pcall(IN_SPOTS and mario_spots or mario_tab_on, bar)
        if SPOTS_M64 and not IN_SPOTS and m64_spots then pcall(m64_spots, bar) end
    end
end
-- Our page given the keys as our tab comes on: STORROR's menu hands them to its own tabs' pages only, so up/down and
-- left/right reached nothing on ours (2026-11-01). Its picked row - the first if none - is given focus whenever nothing
-- on the page has it, for FOCUS_FOR seconds after our tab comes on (STORROR's switch of tab takes the focus back a
-- moment after it lands), and only while the page is up and seen. Not for good: given focus every frame, a focus that
-- missed the page landed on a tab button in the tab row and picked that tab - MARIO SETTINGS went on by itself to MARIO
-- 64 and its pause screen ("make it so its possible to switch out of mario settings still", 2026-11-01).
local FOCUS_FOR = 1.0
local tab_on, focus_left = {}, {}
local function mario_focus(bar, addr)
    if os.clock() > (focus_left[addr] or 0) then return end
    local sw = bar:GetLinkedSwitcher()
    if not alive(sw) then return end
    local content = sw:GetActiveWidget()
    if not alive(content) then return end
    local page = nil
    local inner = nil
    pcall(function() inner = content.AnimatedSwitcher end)
    if MW[content:GetAddress()] or (IN_SPOTS and alive(inner)) then
        local asw = inner
        if alive(asw) then page = asw:GetActiveWidget() end
        local mine = false
        for _, q in ipairs(MP) do if alive(q) and alive(page) and q:GetAddress() == page:GetAddress() then mine = true end end
        if not mine and not MW[content:GetAddress()] then page = nil end
    else
        for _, q in ipairs(MP) do
            if alive(q) and q:GetAddress() == content:GetAddress() then page = content end
        end
    end
    if not alive(page) or not page:IsVisible() then return end
    if page:HasFocusedDescendants() then return end
    local box = page.VerticalBox                          -- (part() is further down)
    if not alive(box) then return end
    local g = box.ButtonGroup
    if not alive(g) or g:GetButtonCount() == 0 then return end
    local i = g:GetSelectedButtonIndex()
    if i < 0 or i >= g:GetButtonCount() then i = 0 end
    local row = g:GetButtonBaseAtIndex(i)
    if alive(row) and row:IsVisible() then row:SetFocus() end
end

-- STORROR's own SETTINGS opened on the page the player last left it on: a new one opens where the last of its kind was
-- put - ours, held on AUDIO - so it opened on AUDIO, not GRAPHICS (2026-11-01). The first look at each new one puts it
-- back (GRAPHICS till the player has left it on another); after that it is the player's.
local settings_seen = {}
local function settings_sub(bar)
    local sw = bar:GetLinkedSwitcher()
    if not alive(sw) then return end
    local st = sw:GetActiveWidget()
    if not alive(st) or MW[st:GetAddress()] then return end
    local sub = st.MenuTabBar
    if not alive(sub) then return end
    local cur = sub:GetSelectedTabId():ToString()
    if cur == "None" then return end
    local key, name = st:GetAddress(), st:GetFName():ToString()
    if settings_seen[key] ~= name then
        settings_seen[key] = name
        local want = _G.SM64_SETTINGS_SUB or "GRAPHICS"
        if cur ~= want and alive(sub:GetTabButtonBaseByID(FName(want))) then
            sub:SelectTabByID(FName(want), true)
            cur = want
        end
    end
    _G.SM64_SETTINGS_SUB = cur
end

-- the bar's title MARIO SETTINGS while our tab is on, and the keys to its page (every frame the menu is up)
local function mario_title()
    for addr, bar in pairs(MB) do
        local ok = pcall(function()
            if not bar:IsValid() then MB[addr] = nil; return end
            local sel = bar:GetSelectedTabId():ToString()
            if tab_colors then pcall(tab_colors, bar, false) end
            local on = sel == TAB_ID
            if on and not tab_on[addr] then focus_left[addr] = os.clock() + FOCUS_FOR end
            tab_on[addr] = on
            if sel == "Settings" then pcall(settings_sub, bar) end
            if not on then return end
            local t = bar.Title
            if t and t:IsValid() and t:GetText():ToString() ~= TAB_TITLE then t:SetText(FText(TAB_TITLE)) end
            pcall(mario_focus, bar, addr)
        end)
        if not ok then MB[addr] = nil end
    end
end
-- each of our many-page widgets on its AUDIO page alone: the others' tabs hidden and shut off (the bumpers pass them
-- by), its tab row out of sight, back on AUDIO if it opens on another; that AUDIO page among ours (MP). `full`: the
-- tabs and the row seen to as well (each look); otherwise only which page is on (every frame the menu is up).
local function mario_multi(full)
    for addr, mw in pairs(MW) do
        local ok = pcall(function()
            if not mw:IsValid() then MW[addr] = nil; return end
            local sub = mw.MenuTabBar
            if not alive(sub) then return end
            if full then
                for _, id in ipairs(SUB_HIDE) do
                    pcall(function() sub:SetTabVisibility(FName(id), 1) end)          -- (collapsed)
                    pcall(function() sub:SetTabEnabled(FName(id), false) end)
                end
                if sub:GetVisibility() ~= 1 then sub:SetVisibility(1) end
            end
            if sub:GetSelectedTabId():ToString() ~= SUB_KEEP then
                local b = sub:GetTabButtonBaseByID(FName(SUB_KEEP))
                if alive(b) then sub:SelectTabByID(FName(SUB_KEEP), true) end
            end
            if full then
                local asw = mw.AnimatedSwitcher
                if not alive(asw) then return end
                for i = 0, asw:GetChildrenCount() - 1 do
                    local w = asw:GetChildAt(i)
                    if alive(w) and w:GetClass():GetFName():ToString() == "CommonAudioMenuWidget_C" then
                        local known = false
                        for _, q in ipairs(MP) do if alive(q) and q:GetAddress() == w:GetAddress() then known = true end end
                        if not known then MP[#MP + 1] = w; log("settings: the %s tab's audio page", TAB_TITLE) end
                    end
                end
            end
        end)
        if not ok then MW[addr] = nil end
    end
end
-- STORROR's tabs that are to be seen - MARIO 64, CHARACTER, CONTROLS, SETTINGS and ours - on and shown, each look: with
-- ours put in, one of them was now and then left hidden and shut off (CONTROLS: the bumpers went from CHARACTER straight
-- to SETTINGS, 2026-11-01), as the mod's own hiding of ADVENTURE and ONLINE and ours land in either order. (ADVENTURE
-- and ONLINE stay pause.lua's to hide.)
local TOP_SHOWN = { "SPOTS", "Character", "Controls", "Settings", TAB_ID }
local function keep_tabs()
    for addr, bar in pairs(MB) do
        pcall(function()
            if not bar:IsValid() or bar:GetSelectedTabId():ToString() == "None" then return end
            for _, id in ipairs(TOP_SHOWN) do
                local tb = bar:GetTabButtonBaseByID(FName(id))
                if alive(tb) and (not tb:GetIsEnabled() or tb:GetVisibility() == 1) then
                    pcall(function() bar:SetTabEnabled(FName(id), true) end)
                    pcall(function() bar:SetTabVisibility(FName(id), 4) end)
                    if not tb:GetIsEnabled() then tb:SetIsEnabled(true) end
                    if tb:GetVisibility() == 1 then tb:SetVisibility(4) end
                    log("settings: %s tab shown again", id)
                end
            end
        end)
    end
end
-- the tab row's names: the tab that is on in the title's colour, the rest in white (every frame the menu is up, and
-- whenever the row is seen to: `force`). The names are ours (LABELS, by bar), not STORROR's buttons - see menu_layout.
local last_sel = {}
local LABELS = {}                                 -- (by bar address: { sig, list of { id, w } })
function tab_colors(bar, force)
    local key = bar:GetAddress()
    local L = LABELS[key]
    if not L then return end
    local sel = bar:GetSelectedTabId():ToString()
    if not force and last_sel[key] == sel then return end
    last_sel[key] = sel
    local on_col = nil
    pcall(function()
        local c = bar.Title.ColorAndOpacity.SpecifiedColor
        on_col = { R = c.R, G = c.G, B = c.B, A = c.A }
    end)
    on_col = on_col or { R = 0.9, G = 1.0, B = 0.15, A = 1.0 }
    local off_col = { R = 1.0, G = 1.0, B = 1.0, A = 0.75 }
    for _, e in ipairs(L.list) do
        if alive(e.w) then
            local want = (e.id == sel) and on_col or off_col
            pcall(function() e.w:SetColorAndOpacity({ SpecifiedColor = want, ColorUseRule = 0 }) end)
        end
    end
end

-- STORROR's menu laid out clear of Mario 64's HUD (lives, coins and stars along the top, the TIME under the stars) -
-- "ui's in front of eachother, also no way to see other menu options. move storrors hud down", 2026-11-01:
--   its tab bar (the tab's name, and under it LT, the tabs, RT) and the page under it moved down (MenuVerticalBox's top
--   padding: BAR_DOWN); its card of the player's name, level and XP at the top right moved down past the TIME
--   (CARD_DOWN, drawn lower);
--   each tab's name shown on its button in the row between LT and RT (STORROR has them collapsed and the icons hidden:
--   only the tab on was named, in the title), apart by TAB_GAP each side; the hidden tabs' buttons stay collapsed.
-- (units: the menu's own 1920x1080 layout, scaled to the window)
-- (40 further down than at first: the power meter still came over the tabs' names - "slight UI overlap", then "actually
-- bring the menu down", 2026-11-02)
local BAR_DOWN, CARD_DOWN, TAB_GAP = 110, 120, 18
local laid = _G.SM64_MENU_LAID or {}              -- (menus laid out, by bar address: the bar's full name; kept in _G,
_G.SM64_MENU_LAID = laid                          -- a reload of this file must not move an open menu down twice)
local function menu_layout(bar)
    local full = bar:GetFullName()
    local key = bar:GetAddress()
    if laid[key] ~= full then
        local tc = bar:GetParent()                                          -- TabbarContainer
        if not alive(tc) then return end
        local vb = tc:GetParent()                                           -- MenuVerticalBox
        if not alive(vb) then return end
        local vs = vb.Slot
        if alive(vs) then
            local P = vs.Padding
            vs:SetPadding({ Left = P.Left, Top = P.Top + BAR_DOWN, Right = P.Right, Bottom = P.Bottom })
        end
        local mo = vb:GetParent()                                           -- MainOverlay
        if alive(mo) then
            for i = 0, mo:GetChildrenCount() - 1 do
                local c = mo:GetChildAt(i)
                if alive(c) and c:GetClass():GetFName():ToString() == "HITSScaledContainer" then
                    c:SetRenderTranslation({ X = 0.0, Y = CARD_DOWN })
                end
            end
        end
        laid[key] = full
        log("settings: STORROR's menu moved down clear of Mario 64's HUD")
    end
    -- (the tabs' names: every look - our tab comes after the first. STORROR makes a button for each tab but puts none
    -- of them in the row between LT and RT, TabBarContent; a name of each shown tab goes there, in the order LT and RT
    -- step through, the tab that is on in the title's colour, the rest in white. Names only - text, a copy of a tab
    -- button's own (its look) - not the buttons: with STORROR's buttons themselves in the row, its menu's focus fell on
    -- them and picked MARIO 64 the moment the menu opened ("still not able to leave the mario menu", 2026-11-01).)
    -- (and the big title over the row, the open tab's name again, put away - "remove the upper setting bar",
    -- 2026-11-01: the row names every tab and lights the open one. Its box collapsed, the row goes up in its place.)
    pcall(function()
        local t = bar.Title
        if not alive(t) then return end
        local box = t:GetParent()
        if alive(box) then
            if box:GetVisibility() ~= 1 then box:SetVisibility(1) end
        elseif t:GetVisibility() ~= 1 then
            t:SetVisibility(1)
        end
    end)
    -- (STORROR's travel page - SPOTS' own: its ESTATE and CITY tabs and the black box of the place's picture - put away,
    -- collapsed, so nothing of it can be picked either: "now remove the city and estate setting as well as the black
    -- box", 2026-11-01. The SPOTS tab itself stays.)
    if not IN_SPOTS and not SPOTS_M64 then
        pcall(function()
            local sw = bar:GetLinkedSwitcher()
            if not alive(sw) then return end
            for i = 0, sw:GetChildrenCount() - 1 do
                local c = sw:GetChildAt(i)
                if alive(c) and c:GetClass():GetFName():ToString() == "MultiPageTravelMenuWidget_C" then
                    if c:GetVisibility() ~= 1 then c:SetVisibility(1); log("settings: SPOTS' travel page put away") end
                end
            end
        end)
    end
    local row, g = nil, nil
    pcall(function() row = bar.TabBarContent end)
    pcall(function() g = bar.TabButtonGroup end)
    if not (alive(row) and alive(g)) then return end
    local info = {}
    pcall(function()
        local tabs = bar.Tabs
        for i = 1, #tabs do
            local e = tabs[i]
            info[e.Name:ToString()] = e.Title:ToString()
        end
    end)
    info[TAB_ID] = TAB_TITLE
    -- (SPOTS, with Mario 64's pause screen in it, named MARIO 64: "also rename spots to Mario 64", 2026-11-01)
    if SPOTS_M64 then info["SPOTS"] = "MARIO 64" end
    -- (the shown tabs in order: each button of the group, by its tab)
    local by_addr = {}
    for id, _ in pairs(info) do
        pcall(function()
            local b = bar:GetTabButtonBaseByID(FName(id))
            if alive(b) then by_addr[b:GetAddress()] = id end
        end)
    end
    local shown, tmpl = {}, nil
    for i = 0, g:GetButtonCount() - 1 do
        local b = g:GetButtonBaseAtIndex(i)
        if alive(b) then
            local id = by_addr[b:GetAddress()]
            if id and b:GetVisibility() ~= 1 then shown[#shown + 1] = id end
            if not tmpl then pcall(function() if alive(b.ButtonTextLabel) then tmpl = b.ButtonTextLabel end end) end
        end
    end
    local sig = table.concat(shown, ",")
    local key = bar:GetAddress()
    local L = LABELS[key]
    local fresh = not (L and L.full == full and L.sig == sig and row:GetChildrenCount() == #L.list)
    if fresh and tmpl then
        row:ClearChildren()                               -- (STORROR's buttons, if an earlier fill put them there)
        local list = {}
        for _, id in ipairs(shown) do
            local w = StaticConstructObject(tmpl:GetClass(), bar.WidgetTree, FName("None"), 0, 0, false, false, tmpl)
            if alive(w) then
                pcall(function() w:SetText(FText(info[id] or id)) end)
                pcall(function() w:SetVisibility(4) end)                     -- (seen, never hit or focused)
                local sl = row:AddChildToHorizontalBox(w)
                if alive(sl) then
                    pcall(function() sl:SetPadding({ Left = TAB_GAP, Top = 0.0, Right = TAB_GAP, Bottom = 0.0 }) end)
                    pcall(function() sl:SetVerticalAlignment(2) end)                  -- (centred)
                end
                list[#list + 1] = { id = id, w = w }
            end
        end
        LABELS[key] = { full = full, sig = sig, list = list }
        log("settings: STORROR's tab row named (%s)", sig)
        tab_colors(bar, true)
    end
    -- (the row as it stands on screen, for Mario 64's pause screen to draw the same over itself - pause.lua tab_row: its
    -- names, their look, where it is and how big - so that the MARIO 64 tab does not seem to leave STORROR's menu)
    -- (its box in STORROR's own 1920x1080 layout, which it scales to the window: across, centred; its middle 63 under
    -- the top of the moved-down bar - measured, 2026-11-01: the engine's geometry of it reads back empty here)
    pcall(function()
        local d = row:GetDesiredSize()
        if not (d and d.X > 1.0) then return end
        local vp = { X = 960.0 - d.X / 2.0, Y = 63.0 + BAR_DOWN - d.Y / 2.0 }
        local vp2 = { X = vp.X + d.X, Y = vp.Y + d.Y }
        local lsz = d
        local names = {}
        for _, id in ipairs(shown) do names[#names + 1] = { id = id, title = info[id] or id } end
        local style = nil
        pcall(function() style = tmpl.Style end)
        local oc = nil
        pcall(function()
            local c = bar.Title.ColorAndOpacity.SpecifiedColor
            oc = { R = c.R, G = c.G, B = c.B, A = c.A }
        end)
        _G.SM64_TABROW = { design = true, x = vp.X, y = vp.Y, w = vp2.X - vp.X, h = vp2.Y - vp.Y, lw = lsz.X, lh = lsz.Y,
                           names = names, style = style, textcls = tmpl and tmpl:GetClass() or nil, gap = TAB_GAP,
                           on_col = oc }
    end)
end
-- (pause.lua, the moment it sees a menu just opened: the tab and the layout in at once, so that the menu can open on
-- our tab and is not seen laid out as STORROR has it)
function M.ensure_tab(bar)
    pcall(IN_SPOTS and mario_spots or mario_tab_on, bar)
    if SPOTS_M64 and not IN_SPOTS and m64_spots then pcall(m64_spots, bar) end
    pcall(menu_layout, bar)
    return alive(bar:GetTabButtonBaseByID(FName(TAB_ID)))
end
M.TAB_ID = TAB_ID
local function menu_layouts()
    for addr, bar in pairs(MB) do
        pcall(function()
            if not bar:IsValid() or bar:GetSelectedTabId():ToString() == "None" then return end
            menu_layout(bar)
        end)
    end
end
local function mario_pages()
    local out = {}
    for i = #MP, 1, -1 do
        if alive(MP[i]) then out[#out + 1] = MP[i] else table.remove(MP, i) end
    end
    return out
end

local ROWS = {}
for _, pg in ipairs(PAGES) do
    for i, r in ipairs(pg.rows) do
        r.page, r.i = pg, i
        r.last_value, r.save_at = nil, nil
        ROWS[#ROWS + 1] = r
    end
end

local look_t, poll_t, applied = 0.0, 0.0, false
local tried = {}                        -- pages a row was tried on, by page and row (one try each)
local was_open, hold_until = false, 0.0
local quick_until = 0.0

-- STORROR's menu up (pause.lua's test): only then can the slider have been moved by the player. (Read with the menu
-- shut, a page on its way out read 0 - the setting went to 0 by itself a minute after a level loaded, 2026-10-15.)
local function storror_menu_open()
    local open = false
    pcall(function()
        for _, w in ipairs(FindAllOf("MenuPresenterBP_C") or {}) do
            if w:IsValid() and w:GetFullName():find("Transient", 1, true) and w:IsActivated() then open = true end
        end
    end)
    return open
end

-- a row's setting: a toggle's is 0 or 1
local function setting(r)
    local MN = menu()
    local v = (MN and r.get(MN)) or 1.0
    if r.toggle then v = (v >= 0.5) and 1.0 or 0.0 end
    return v
end

-- the slider's own value, 0..1 of its range
local function norm(slider, v)
    local lo, hi = 0.0, 1.0
    pcall(function() lo, hi = slider.MinValue, slider.MaxValue end)
    if hi - lo <= 0 then return v end
    return (v - lo) / (hi - lo)
end
local function denorm(slider, u)
    local lo, hi = 0.0, 1.0
    pcall(function() lo, hi = slider.MinValue, slider.MaxValue end)
    return lo + u * (hi - lo)
end

local function text_of(t)
    local ok, s = pcall(function() return t:ToString() end)
    return ok and s or ""
end

-- the row titled `label` in that page's column, or nil. (A row added under its old title, `was`, is given its new one:
-- MARIO FX, once MARIO JUMP VOICE - a page made before the rename had it so)
local function ours(box, label)
    local was = nil
    for _, r in ipairs(ROWS) do if r.label == label then was = r.was end end
    local found = nil
    pcall(function()
        for i = 0, box:GetChildrenCount() - 1 do
            local c = box:GetChildAt(i)
            if c and c:IsValid() then
                local t = text_of(c.SettingsName)
                if t == label then
                    found = c
                elseif was and t == was then
                    found = c
                    pcall(function() c.SettingsName = FText(label) end)
                    pcall(function() c.Title:SetText(FText(label)) end)
                end
            end
        end
    end)
    return found
end

-- a widget of the page by name: its variable, or else from its tree
local function part(page, name)
    local w = nil
    pcall(function() w = page[name] end)
    if w and pcall(function() return w:IsValid() end) and w:IsValid() then return w end
    pcall(function() w = page.WidgetTree:FindWidget(FName(name)) end)
    if w and pcall(function() return w:IsValid() end) and w:IsValid() then return w end
    return nil
end

-- a slider of STORROR's to make ours from and to write our numbers as it does: the page's MUSIC, or any of its sliders
-- that is up (the graphics page has none of its own)
local function template(page)
    local mus = part(page, "MusicVolumeSlider")
    if mus then return mus end
    for _, pg in ipairs(FindAllOf("CommonAudioMenuWidget_C") or {}) do
        if pg:IsValid() and not pg:GetFName():ToString():find("^Default__") then
            local m = part(pg, "MusicVolumeSlider")
            if m then return m end
        end
    end
    return nil
end

-- what a row stands under: the page's own row for the first, the row before it for the rest
local function anchor_of(page, box, r)
    if r.i > 1 then
        local prev = ours(box, r.page.rows[r.i - 1].label)
        if prev then return prev end
    end
    return part(page, r.page.under)
end

-- ours among the page's rows that can be picked (the column's button group: up/down, the mouse over it, the mark by
-- it), straight after the row it stands under. (Only in the column, the row was there and could not be picked:
-- 2026-10-15 "I cant hover over it".) The group is checked again while the page is up, in case STORROR makes it
-- afresh.
local function enlist(box, row, anchor, label)
    local g = box.ButtonGroup
    if not (g and g:IsValid()) or g:FindButtonIndex(row) >= 0 then return end
    local mi = g:FindButtonIndex(anchor)
    local after = {}
    if mi >= 0 then
        for i = mi + 1, g:GetButtonCount() - 1 do after[#after + 1] = g:GetButtonBaseAtIndex(i) end
    end
    for _, b in ipairs(after) do g:RemoveWidget(b) end
    g:AddWidget(row)
    for _, b in ipairs(after) do g:AddWidget(b) end
    log("settings: %s can be picked (row %d of %d)", label, g:FindButtonIndex(row), g:GetButtonCount())
end

-- A toggle's ON or OFF: a text of its own in the place of the row's number (a copy of it - same look - put in the
-- number's box, the number taken out). On the audio page STORROR writes every slider's number back as a percentage
-- each frame, so ON/OFF written into the number itself showed 0% and 100% (2026-11-01, the MARIO SETTINGS page);
-- its own text it leaves alone. By row, kept in _G (a reload of this file finds them).
local VALS = _G.SM64_ONOFF or {}
_G.SM64_ONOFF = VALS
local function own_value(row)
    local key = row:GetAddress()
    local have = VALS[key]
    if have and have:IsValid() then return have end
    VALS[key] = nil
    local sv = row.SliderValue
    if not (sv and sv:IsValid()) then return nil end
    local box = sv:GetParent()
    if not (box and box:IsValid()) then return nil end
    if box:GetClass():GetFName():ToString() ~= "SizeBox" then return nil end
    local sl = sv.Slot
    local pad, ha, va = nil, nil, nil
    if sl and sl:IsValid() then
        local P = sl.Padding
        pad = { Left = P.Left, Top = P.Top, Right = P.Right, Bottom = P.Bottom }
        ha, va = sl.HorizontalAlignment, sl.VerticalAlignment
    end
    local tb = StaticConstructObject(sv:GetClass(), row.WidgetTree, FName("MarioOnOff"), 0, 0, false, false, sv)
    if not (tb and tb:IsValid()) then return nil end
    local ns = box:SetContent(tb)
    if ns and ns:IsValid() and pad then
        pcall(function() ns:SetPadding(pad) end)
        pcall(function() ns:SetHorizontalAlignment(ha) end)
        pcall(function() ns:SetVerticalAlignment(va) end)
    end
    pcall(function() tb:SetVisibility(4) end)                         -- (seen, not hit-tested)
    VALS[key] = tb
    log("settings: own ON/OFF text on a row")
    return tb
end
M.own_value = own_value

-- the bar and the number of our row at `u` (0..1), the number written as STORROR's MUSIC writes its own; a toggle's
-- as ON or OFF
function M.show(row, mus, u, r)
    pcall(function() row.ProgressBar.ProgressValue = u end)          -- (HITSBrushProgressBar: a row of dots, lit to it)
    if r and r.toggle then
        pcall(function()
            local ok, tv = pcall(own_value, row)
            tv = (ok and tv) or row.SliderValue
            tv:SetText(FText(u >= 0.5 and "ON" or "OFF"))
        end)
        return
    end
    pcall(function()
        local theirs = text_of(mus.SliderValue:GetText())
        local tv = tonumber(theirs:match("[%d%.]+") or "")
        local tu = norm(mus.Slider, mus.Slider:GetValue())
        local txt
        if tv and tu > 0.001 then
            local scale = tv / tu                                  -- (their number per whole of the range)
            txt = theirs:gsub("[%d%.]+", string.format(scale >= 10 and "%d" or "%.1f", scale >= 10 and math.floor(u * scale + 0.5) or u * scale), 1)
        else
            txt = string.format("%d", math.floor(u * 100 + 0.5))
        end
        row.SliderValue:SetText(FText(txt))
    end)
end

-- one under `anchor`: the same kind of row as STORROR's MUSIC, ours to say
local function add(page, r, anchor)
    log("settings: adding %s", r.label)
    local box, mus = part(page, "VerticalBox"), template(page)
    if not (box and box:IsValid() and mus and mus:IsValid() and anchor and anchor:IsValid()) then return nil end
    local WBL = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local row = WBL:Create(lib.world(), mus:GetClass(), mus:GetOwningPlayer())
    if not (row and row:IsValid()) then return nil end
    row.SettingsName = FText(r.label)
    -- (a panel's "insert at" cannot be called from here: the rows under the anchor come off, ours goes on the end, and
    -- they go back on after it, as they were - every row of the page has no padding of its own)
    local at = box:GetChildIndex(anchor)
    if at < 0 then
        -- (not one of the column's own rows: ours at the bottom)
        at = box:GetChildrenCount() - 1
        log("settings: %s - the row it goes under is not in the column; at the bottom", r.label)
    end
    local after = {}
    for i = at + 1, box:GetChildrenCount() - 1 do after[#after + 1] = box:GetChildAt(i) end
    for _, c in ipairs(after) do box:RemoveChild(c) end
    local slot = box:AddChildToVerticalBox(row)
    for _, c in ipairs(after) do box:AddChildToVerticalBox(c) end
    pcall(function()
        local ms = anchor.Slot                                 -- (laid out as the row it stands under)
        slot:SetPadding(ms.Padding)
        slot:SetHorizontalAlignment(ms.HorizontalAlignment)
        slot:SetVerticalAlignment(ms.VerticalAlignment)
        slot:SetSize(ms.Size)
    end)
    pcall(enlist, box, row, anchor, r.label)
    pcall(function() row.Title:SetText(FText(r.label)) end)
    if r.toggle then
        -- (two places, OFF and ON: left and right flip it. Its bar of dots and its slider not seen - the slider still
        -- takes left, right and the mouse - only ON or OFF, as the page's own rows show theirs: "why is it a slider?",
        -- 2026-10-30. STORROR's own ON/OFF rows take their choices from its code alone: one of ours would be empty.)
        pcall(function() local b = row.Slider; b:SetMinValue(0.0); b:SetMaxValue(1.0); b:SetStepSize(1.0) end)
        pcall(function() row.ProgressBar:SetVisibility(1) end)        -- (collapsed)
        pcall(function() row.Slider:SetRenderOpacity(0.0) end)
    else
        pcall(function()
            local a, b = mus.Slider, row.Slider
            b:SetMinValue(a.MinValue); b:SetMaxValue(a.MaxValue); b:SetStepSize(a.StepSize)
        end)
    end
    -- (how fast left and right move it, as MUSIC's: plain values only - a look at the row's sounds, empty, took the
    -- game down)
    pcall(function() row.SliderSpeedRatio = mus.SliderSpeedRatio end)
    pcall(function() row.bRightStickSliderNavigation = mus.bRightStickSliderNavigation end)
    local u = setting(r)
    -- (the value set on the slider alone, and its bar and number by hand, as STORROR's MUSIC shows them: its own
    -- "value changed" is not called from here)
    pcall(function() row.Slider:SetValue(denorm(row.Slider, u)) end)
    M.show(row, mus, u, r)
    log("settings: %s slider added (%.2f)", r.label, u)
    return row
end

-- the page's own rows (STORROR's audio sliders) put away on our page: not seen, not among the column's buttons
local function hide_theirs(page, box)
    local mine = {}
    for _, r in ipairs(ROWS) do
        local row = ours(box, r.label)
        if row then mine[row:GetAddress()] = true end
    end
    local g = box.ButtonGroup
    for i = 0, box:GetChildrenCount() - 1 do
        local c = box:GetChildAt(i)
        if c and c:IsValid() and not mine[c:GetAddress()] then
            if c:GetVisibility() ~= 1 then c:SetVisibility(1) end         -- (collapsed)
            pcall(function() if g and g:IsValid() and g:FindButtonIndex(c) >= 0 then g:RemoveWidget(c) end end)
        end
    end
end

-- one of our rows on a page that is up: held at the setting a moment as the menu opens, then read. Each of our rows on
-- its own: STORROR keeps more than one of a page (the main menu's, the pause menu's), each with ours on it - read
-- against each other, one at ON and the other at OFF flipped the setting four times a second (2026-10-30). A row the
-- player moves sets it; the others are shown as it is.
local function read_row(page, box, r, open)
    local row = ours(box, r.label)
    if not row then return end
    if not open then return end                                        -- (shut: not touched at all)
    local mus = template(page)
    local key = page:GetFName():ToString()
    r.seen = r.seen or {}
    if r.last_value == nil then r.last_value = setting(r) end
    local function put(v)
        if math.abs(norm(row.Slider, row.Slider:GetValue()) - v) > 0.001 then row.Slider:SetValue(denorm(row.Slider, v)) end
        pcall(M.show, row, mus, v, r)
        r.seen[key] = v
    end
    if r.toggle then r.rows = r.rows or {}; r.rows[key] = row end      -- (its ON/OFF kept on it every frame: M.tick)
    if os.clock() < hold_until then put(r.last_value); return end
    local u = norm(row.Slider, row.Slider:GetValue())
    if r.toggle then u = (u >= 0.5) and 1.0 or 0.0 end                -- (only its two places: anywhere else, the nearer)
    local before = r.seen[key]
    if before == nil then put(r.last_value); return end                -- (first look at it: shown as the setting is)
    if math.abs(u - before) > 0.001 then
        r.last_value = u
        r.save_at = os.clock() + (r.toggle and 0.1 or 0.6)             -- (kept once it has stopped moving)
        if r.apply then
            local ok, err = pcall(r.apply, u)
            if not ok then log("settings: %s: %s", r.label, tostring(err)) end
        end
        put(u)
    elseif math.abs(u - r.last_value) > 0.001 or (r.toggle and math.abs(norm(row.Slider, row.Slider:GetValue()) - u) > 0.001) then
        put(r.last_value)                                              -- (set on another of ours, or between places)
    end
end

-- Every frame: the settings put on once; a few times a second, STORROR's pages looked for (ours added to them), and
-- while they are up, our rows read
-- SPOTS' page set up for Mario 64's screen (one bar's menu): our page of three unseen rows a page of SPOTS' travel page
-- and a tab of its own row, ESTATE and CITY hidden and shut off, ours picked, that row out of sight
m64_spots = function(bar)
    if not bar:IsValid() or bar:GetFName():ToString():find("^Default__") then return end
    local sw = bar:GetLinkedSwitcher()
    if not alive(sw) then return end
    local tw = nil
    for i = 0, sw:GetChildrenCount() - 1 do
        local c = sw:GetChildAt(i)
        if alive(c) and c:GetClass():GetFName():ToString() == "MultiPageTravelMenuWidget_C" then tw = c end
    end
    if not alive(tw) then return end
    if tw:GetVisibility() == 1 then tw:SetVisibility(4) end                  -- (put away before: seen again)
    local sub, asw = tw.MenuTabBar, tw.AnimatedSwitcher
    if not (alive(sub) and alive(asw)) then return end
    if not alive(sub:GetTabButtonBaseByID(FName(M64_SUB))) then
        local ref = sub:GetTabButtonBaseByID(FName("Estate"))
        if not alive(ref) then return end
        local WBL = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        local cls = StaticFindObject(PAGE_CLASS)
        if not alive(cls) then pcall(function() cls = LoadAsset(PAGE_CLASS) end) end
        if not (WBL and alive(cls)) then return end
        local page = WBL:Create(lib.world(), cls, ref:GetOwningPlayer())
        if not alive(page) then return end
        if asw:GetChildIndex(page) < 0 then asw:AddChild(page) end
        sub:RegisterTab(FName(M64_SUB), ref:GetClass(), page, -1)
        CTL[page:GetAddress()] = { page = page, rows = nil, name = page:GetFName():ToString() }
        log("settings: Mario 64's pause screen's page on SPOTS")
    end
    for _, id in ipairs({ "Estate", "city" }) do
        pcall(function()
            local b = sub:GetTabButtonBaseByID(FName(id))
            if alive(b) and (b:GetIsEnabled() or b:GetVisibility() ~= 1) then
                sub:SetTabVisibility(FName(id), 1)
                sub:SetTabEnabled(FName(id), false)
            end
        end)
    end
    if sub:GetSelectedTabId():ToString() ~= M64_SUB then sub:SelectTabByID(FName(M64_SUB), true) end
    if sub:GetVisibility() ~= 1 then sub:SetVisibility(1) end
    -- (the page's rows: once its own are there to make ours from - three of the MUSIC row's kind, unseen; its own put
    -- away and out of its buttons)
    for addr, e in pairs(CTL) do
        pcall(function()
            local page = e.page
            if not page:IsValid() or page:GetFName():ToString() ~= e.name then CTL[addr] = nil; return end
            if e.rows then return end
            local box = part(page, "VerticalBox")
            local mus = part(page, "MusicVolumeSlider")
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
            local rows = {}
            for i = 1, 3 do
                local r = WBL:Create(lib.world(), mus:GetClass(), mus:GetOwningPlayer())
                r.SettingsName = FText("SM64 PAUSE " .. i)
                box:AddChildToVerticalBox(r)
                pcall(function() local b = r.Slider; b:SetMinValue(0.0); b:SetMaxValue(1.0); b:SetStepSize(0.1); b:SetValue(0.5) end)
                r:SetRenderOpacity(0.0)
                if alive(g) then g:AddWidget(r) end
                rows[i] = r
            end
            if alive(g) then g:SelectButtonAtIndex(1, false) end
            e.rows = rows
            log("settings: Mario 64's pause screen's rows on SPOTS")
        end)
    end
end

-- each frame the menu is up: the picks and pushes on our unseen rows, as Up, Down and A for pause.lua (M.spots_input),
-- each put back at once; and the keys' focus on the middle row for a moment after the tab comes on
local spots_on_t = {}
local function spots_read()
    -- (only while SPOTS is the tab on: STORROR's switcher leaves the pages of the other tabs "visible", and this page took
    -- the keys' focus back from the ONLINE tab's multiplayer screen every frame - "no way to select the options",
    -- 2026-11-01)
    local P = package.loaded["pause"]
    local tab = nil
    pcall(function() tab = P.tab() end)
    if tab ~= "SPOTS" then return end
    for addr, e in pairs(CTL) do
        pcall(function()
            local page = e.page
            if not (e.rows and page:IsValid() and page:IsVisible()) then spots_on_t[addr] = nil; return end
            local box = part(page, "VerticalBox")
            local g = box and box.ButtonGroup
            if not alive(g) then return end
            local mid = e.rows[2]
            if not spots_on_t[addr] then spots_on_t[addr] = os.clock() end
            -- (the keys' focus on the middle row whenever SPOTS is up and the page has none: STORROR gives its pages
            -- theirs as the tab comes on, ours not - Up and Down did nothing till it had it)
            if not page:HasFocusedDescendants() then pcall(function() mid:SetFocus() end) end
            if page:GetRenderOpacity() > 0.0 then page:SetRenderOpacity(0.0) end   -- (all of it unseen: its line too)
            local sel = g:GetSelectedButtonIndex()
            local i0 = g:FindButtonIndex(e.rows[1])
            local i2 = g:FindButtonIndex(e.rows[3])
            local i1 = g:FindButtonIndex(mid)
            if sel == i0 then ctl_ev.up = ctl_ev.up + 1 elseif sel == i2 then ctl_ev.down = ctl_ev.down + 1 end
            if sel ~= i1 and i1 >= 0 then g:SelectButtonAtIndex(i1, false) end
            local v = mid.Slider:GetValue()
            if v > 0.55 then ctl_ev.ok = ctl_ev.ok + 1 end
            if math.abs(v - 0.5) > 0.01 then mid.Slider:SetValue(0.5) end
        end)
    end
end

-- The bottom bar's BACK (B) reads SELECT while the MARIO 64 tab is up - there B shuts the menu and takes the choice the
-- hand points at - and BACK again on every other tab: "at the bottom right it says back B, change it to select B",
-- "only on mario 64 menu though", 2026-11-01. (STORROR's bottom-bar text, SaveChangeStyle; looked for twice a second
-- at most when not yet found.)
local back_txt, back_look = nil, 0.0
local function spots_shown()
    for _, e in pairs(CTL) do
        local ok, v = pcall(function() return e.page:IsValid() and e.page:IsVisible() end)
        if ok and v then return true end
    end
    return false
end
local function back_label(m64)
    -- (the one on the screen: STORROR makes a new bottom bar each time its menu opens, the old ones left about unseen)
    local seen = false
    pcall(function() seen = back_txt:IsValid() and back_txt:IsVisible() end)
    if not seen then
        if back_txt then pcall(function() if back_txt:IsValid() and back_txt:GetText():ToString() == "SELECT" then back_txt:SetText(FText("BACK")) end end) end
        back_txt = nil
        if not m64 or os.clock() < back_look then return end
        back_look = os.clock() + 0.5
        for _, t in ipairs(FindAllOf("CommonTextBlock") or {}) do
            if t and t:IsValid() then
                local ok, hit = pcall(function()
                    local s = t:GetText():ToString()
                    return (s == "BACK" or s == "SELECT") and t:IsVisible()
                        and t:GetClass():GetFName():ToString():find("SaveChangeStyle", 1, true) ~= nil
                end)
                if ok and hit then back_txt = t; break end
            end
        end
        if not back_txt then return end
    end
    local want = m64 and "SELECT" or "BACK"
    local ok, s = pcall(function() return back_txt:GetText():ToString() end)
    if ok and s ~= want and (s == "BACK" or s == "SELECT") then pcall(function() back_txt:SetText(FText(want)) end) end
end

function M.tick(dt)
    -- (the pause tune - music.lua M.pause_watch - looked to from here too: this runs while the game is paused, when
    -- game.lua's tick stops short of the music's own)
    do
        local MU = package.loaded["music"]
        if MU and MU.pause_watch then pcall(MU.pause_watch) end
        -- (and the pause menu's "now playing" line: nowplaying.lua)
        local okN, NP = pcall(require, "nowplaying")
        if okN and NP and NP.tick then pcall(NP.tick) end
        -- (and the multiplayer screen in the ONLINE tab: mpmenu.lua)
        local okP, MPM = pcall(require, "mpmenu")
        if okP and MPM and MPM.tick then pcall(MPM.tick) end
    end
    if _G.MSET_OFF then return end                                    -- (dev: hands off)
    if not applied then
        local MN, MU = menu(), music()
        if MN and MU and MU.set_user then
            for _, r in ipairs(ROWS) do
                if r.apply then
                    local ok, err = pcall(r.apply, setting(r))
                    if not ok then log("settings: %s: %s", r.label, tostring(err)) end
                end
            end
            applied = true
        end
    end
    for _, r in ipairs(ROWS) do
        if r.save_at and os.clock() >= r.save_at then
            r.save_at = nil
            local MN = menu()
            if MN and r.last_value then pcall(r.set, MN, r.last_value) end
            if r.kept and r.last_value then pcall(r.kept, r.last_value) end
            log("settings: %s %.2f kept", r.label, r.last_value or -1)
        end
    end
    -- (a toggle's ON or OFF, every frame the menu is up: STORROR's own slider code writes its number there - 0 or 100 -
    -- whenever it is moved, "it should be on or off not 0 or 100", 2026-10-30)
    if was_open then
        if SPOTS_M64 then spots_read() end
        -- (the tab STORROR's menu is on - pause.lua M.tab: a page's own IsVisible stays true on the other tabs)
        do
            local P = package.loaded["pause"]
            local on = false
            pcall(function() on = P and P.tab and P.tab() == "SPOTS" end)
            pcall(back_label, SPOTS_M64 and on and true or false)
        end
        mario_title()
        mario_multi(false)
        for _, r in ipairs(ROWS) do
            if r.toggle and r.rows then
                for key, row in pairs(r.rows) do
                    local alive = false
                    pcall(function()
                        if not row:IsValid() then return end
                        alive = true
                        local want = (norm(row.Slider, row.Slider:GetValue()) >= 0.5) and "ON" or "OFF"
                        local okv, tv = pcall(own_value, row)
                        tv = (okv and tv) or row.SliderValue
                        if text_of(tv:GetText()) ~= want then tv:SetText(FText(want)) end
                    end)
                    if not alive then r.rows[key] = nil end
                end
            end
        end
    end
    -- (its searches for STORROR's menu - every 0.1 s, a hitch of up to 20 ms - only while pause.lua says the menu is up
    -- or about to be: "next we have to do major optimization", 2026-11-01)
    do
        local P = package.loaded["pause"]
        local ok, maybe = pcall(function() return P.menu_maybe() end)
        if not was_open and ok and maybe == false then return end
    end
    look_t, poll_t = look_t - dt, poll_t - dt
    if look_t > 0 and poll_t > 0 then return end
    local looking = look_t <= 0
    if looking then look_t = 0.5 end
    poll_t = 0.1
    -- (the sliders are the player's only while the menu is up; as it opens, ours are set to the settings and held there
    -- a moment, whatever the menu does to its rows as it fills them)
    local open = storror_menu_open()
    if open and not was_open then
        hold_until = os.clock() + 0.4
        -- (a menu just up: looked at every tenth of a second for a moment, so that the tab and the layout are in before
        -- it is seen)
        quick_until = os.clock() + 1.5
        looking = true
    end
    if looking and os.clock() < quick_until then look_t = 0.1 end
    was_open = open
    if looking then pcall(mario_tabs); pcall(mario_multi, true); pcall(keep_tabs); pcall(menu_layouts) end
    for _, pg in ipairs(PAGES) do
        for _, page in ipairs((pg.mario and mario_pages()) or FindAllOf(pg.class) or {}) do
            pcall(function()
                if not page:IsValid() or page:GetFName():ToString():find("^Default__") then return end
                local box = part(page, "VerticalBox")
                if not box then return end
                local key = page:GetFName():ToString()
                for _, r in ipairs(pg.rows) do
                    local row = ours(box, r.label)
                    -- (tried once a slider of STORROR's to make it from is up: the graphics page has none of its own)
                    if not row and looking and not tried[key .. "|" .. r.label] and (not r.shown or r.shown()) and template(page) then
                        tried[key .. "|" .. r.label] = true
                        local ok, res = pcall(add, page, r, anchor_of(page, box, r))
                        if not ok then log("settings: %s not added (%s)", r.label, tostring(res)) end
                        row = ok and res or nil
                    end
                    if row and open and looking then pcall(enlist, box, row, anchor_of(page, box, r), r.label) end
                    local ok, err = pcall(read_row, page, box, r, open)
                    if not ok and not r.err then r.err = true; log("settings: %s: %s", r.label, tostring(err)) end
                end
                if pg.mario and looking then pcall(hide_theirs, page, box) end
            end)
        end
    end
end

M.part = part
M.add = function(page, i)
    local r = ROWS[i or 1]
    return add(page, r, anchor_of(page, part(page, "VerticalBox"), r))
end

-- (a new map: nothing of the old one is held)
function M.forget() end

return M
