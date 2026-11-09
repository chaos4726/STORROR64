-- SM64Map: what he wears held on STORROR's CHARACTER screen until the player picks something ("hovering over other
-- charaters removes all the mario cloths", "make sure selected clothing items and faces stay on until the player
-- selects something", 2026-11-01).
--
-- STORROR previews whatever the cursor rests on: it writes that face or cloth into his player state's editor data and
-- runs CharacterEditorComponent:UpdateCharacterFromPlayerState on him - his face swapped, the mod's Mario clothes and
-- look gone with it. Here, while its menu is up, each of those updates is given the values he wore as the menu came up
-- (written in as it starts) and STORROR's own put back as it ends: he stays as he is, and STORROR, finding its data as
-- it left it, does not try again (with its data left changed, it ran the update every frame). A pick - STORROR's
-- SelectedCallbackFromDelegate, A or a click on a tile - takes the picked value for that part, read from STORROR's
-- data a moment after (the tile picked is the one the cursor rests on). A face picked: the Mario look off first (his
-- hair shown before the face changes: hidden hair under a changed face crashed the game), and on again for Max.
local lib = require("lib")
local log = lib.log

local M = {}
M.ON = true
-- (STORROR's grids watched for its picks; off with the CHARACTER tab made anew - charmenu.lua: its grids are gone)
M.WATCH = true

local FIELDS = { "SelectedCharacter", "TorsoClothing", "LegsClothing", "FeetClothing", "BodyType" }
-- (the grid's Parameter, ECharacterParameter: 4 top, 5 bottom, 6 shoes, 7 face)
local PARAM_FIELD = { [4] = "TorsoClothing", [5] = "LegsClothing", [6] = "FeetClothing", [7] = "SelectedCharacter" }
local BASE_FACE = "Max"               -- (Max is Mario: charpick.lua)
local PICK_READ = 0.15                -- (a pick's value read this long after STORROR's pick)

local committed = nil                 -- what he wears, read while the menu is shut
local hold = nil                      -- field -> value, while STORROR's menu is up
local saved = nil                     -- STORROR's own values over one of its updates
local picks = {}                      -- { field, t } waiting to be read
local picked = {}                     -- field -> true: picked this time the menu is up
local look_at = nil                   -- when to put the Mario look on again (Max picked)
local closed_t = 0.0
local hooked = false
-- (STORROR's menu shut: it runs an update or two on him as it goes - 0.1 s and 0.7 s after - with the face its cursor
-- rested on, Sacha seen a second before Mario was put back; held through that, then its data left as he is)
local RELEASE = 1.3
local release_t = 0.0

local function edata()
    local d = nil
    pcall(function() d = lib.pawn().PlayerState.PlayerModel.RepCharacterEditorData end)
    return d
end
local function read(d)
    local t = {}
    for _, f in ipairs(FIELDS) do pcall(function() t[f] = d[f]:ToString() end) end
    return t
end
-- (the update's component his: not a figure's)
local function on_him(ctx)
    local yes = false
    pcall(function()
        local pawn = lib.pawn()
        yes = pawn ~= nil and ctx:get():GetOuter():GetAddress() == pawn:GetAddress()
    end)
    return yes
end

-- STORROR's update run on him by the mod (the held values go in through the hook)
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

local function before_update(ctx)
    saved = nil
    if not (M.ON and hold and on_him(ctx)) then return end
    local d = edata()
    if not d then return end
    local cur = read(d)
    for f, v in pairs(hold) do
        if cur[f] and cur[f] ~= v then
            saved = saved or {}
            saved[f] = cur[f]
            pcall(function() d[f] = v end)
        end
    end
end
local function after_update(ctx)
    if not on_him(ctx) then return end
    if saved then
        local d = edata()
        if d then for f, v in pairs(saved) do pcall(function() d[f] = v end) end end
        saved = nil
    end
    -- (the mod's own clothes on him again at once: STORROR's update put its own back)
    if hold then
        local CL = package.loaded["clothpick"]
        if CL and CL.put_back then pcall(CL.put_back, lib.pawn()) end
    end
end

local function on_pick(ctx)
    if not hold then return end
    local p = nil
    pcall(function() p = ctx:get().Parameter end)
    local f = p and PARAM_FIELD[tonumber(p)]
    if f then picks[#picks + 1] = { field = f, t = os.clock() } end
end

-- STORROR's picks seen on its grids: the tick (SavedIcon) on its tiles moving to another - A on a tile with the pad
-- never reaches SelectedCallbackFromDelegate ("selecting other charaters doesnt hold though it switches back to mario",
-- 2026-11-01). Its own tiles only (not the mod's clothes buttons); a grid's tick taken as it stands for SETTLE after
-- the grid shows (STORROR moves it about by itself then). The value: STORROR's data at that moment - the tile the
-- cursor rests on, the one A was pressed on.
-- ("stuck on wario charater", 2026-11-01: a pick made in the first second the CHARACTER tab was up - the menu opened,
-- Luigi picked and the menu shut inside three seconds - was taken for STORROR's own settling and missed; his tick then
-- stood on Luigi with Wario held, and Luigi picked again moved no tick. Now: the grids watched from the menu's
-- opening, ten times a second and once more as it shuts; and on the face grid the face its tick is on IS the face -
-- whenever it is not the one held, that one is taken.)
local SETTLE = 1.0
local grids = {}                      -- by address: { obj, name, field, saved, since }
local grid_find_t = 0.0
local watch_t = 0.0
-- (and the cursor: the tile picked out - it marks itself selected - or the one under the mouse; for ours its option)
local function tile_ticked(g, ours)
    local idx, k, item = 0, 0, nil
    local cur, cur_ours, hov, hov_ours = nil, nil, nil, nil
    local rh = g.Grid.RowHolder
    for r = 0, rh:GetChildrenCount() - 1 do
        local row = rh:GetChildAt(r)
        if row and row:IsValid() then
            for c = 0, row:GetChildrenCount() - 1 do
                local it = row:GetChildAt(c)
                if it and it:IsValid() then
                    local a = it:GetAddress()
                    local ok1, sel = pcall(function() return it:GetSelected() end)
                    local ok2, hv = pcall(function() return it:IsHovered() end)
                    if ok1 and sel and not cur then cur, cur_ours = a, ours[a] or false end
                    if ok2 and hv and not hov then hov, hov_ours = a, ours[a] or false end
                    if not ours[a] then
                        k = k + 1
                        local ok, v = pcall(function() return it.SavedIcon:IsVisible() end)
                        if ok and v then idx, item = k, it end
                    end
                end
            end
        end
    end
    if not cur then cur, cur_ours = hov, hov_ours end
    return idx, item, cur, cur_ours
end
local function watch_grids(dt, force)
    local now = os.clock()
    grid_find_t = grid_find_t - dt
    if grid_find_t <= 0 then
        grid_find_t = 0.5
        for _, g in ipairs(FindAllOf("SPPGridTabWidgetBP_C") or {}) do
            pcall(function()
                if not g:IsValid() then return end
                local a = g:GetAddress()
                if grids[a] then return end
                local n = g:GetFName():ToString()
                if n:find("^Default__") then return end
                local f = PARAM_FIELD[tonumber(g.Parameter)]
                if f then grids[a] = { obj = g, name = n, field = f } end
            end)
        end
    end
    local CL = package.loaded["clothpick"]
    local ours = (CL and CL.ours_keys and CL.ours_keys()) or {}
    for a, e in pairs(grids) do
        local ok = pcall(function()
            local g = e.obj
            if not (g:IsValid() and g:GetFName():ToString() == e.name) then grids[a] = nil; return end
            if not g:IsVisible() then e.since = nil; return end
            if not e.since then e.since = now end
            local s, item, cur, cur_ours = tile_ticked(g, ours)
            -- (where the cursor was the frame before: STORROR may move its picking-out as it moves its tick)
            local prev_ours = e.cur_ours
            e.cur_ours = cur_ours
            -- (the face grid: the face of the ticked tile, taken when it is not the one held)
            if e.field == "SelectedCharacter" then
                local C = package.loaded["charpick"]
                local f = item and C and C.tile_face and C.tile_face(item:GetAddress())
                if f and hold and f ~= hold.SelectedCharacter and now - e.since >= 0.5 and not e.asked then
                    e.asked = f
                    picks[#picks + 1] = { field = e.field, t = now - PICK_READ - 0.01, value = f }
                end
                if f == (hold and hold.SelectedCharacter) then e.asked = nil end
                return
            end
            if e.saved == nil or e.saved == 0 or now - e.since < SETTLE then e.saved = s; return end
            if s ~= 0 and s ~= e.saved then
                e.saved = s
                -- (the cursor on one of ours as STORROR's tick moved: A on ours - STORROR picks one of its own instead)
                local who = prev_ours or cur_ours or nil
                picks[#picks + 1] = { field = e.field, t = now - PICK_READ - 0.01, ours = who }
                log("character hold: %s - STORROR's tick moved to its tile %d; the cursor was on %s (now %s)", e.field, s,
                    prev_ours and ("the mod's " .. prev_ours) or "one of STORROR's", cur_ours and ("the mod's " .. cur_ours)
                    or "one of STORROR's")
            end
        end)
        if not ok then grids[a] = nil end
    end
end

local function hook()
    hooked = true
    local ok, err = pcall(function()
        RegisterHook("/Script/SPP.CharacterEditorComponent:UpdateCharacterFromPlayerState",
            function(ctx) pcall(before_update, ctx) end,
            function(ctx) pcall(after_update, ctx) end)
    end)
    if not ok then log("character hold: no update hook (%s)", tostring(err)) end
    pcall(function()
        RegisterHook("/Script/HITS_UI.HITSPauseMenuWidgetUI:SelectedCallbackFromDelegate", function(ctx)
            pcall(on_pick, ctx)
        end)
    end)
end

-- a face picked: the look off (his hair shown) before the face changes, the face changed, the look on again for Max
local function take_face(v)
    if hold.SelectedCharacter == v then return end
    local L = package.loaded["mariolook"]
    if L and L.on() then pcall(L.remove) end
    log("character hold: face %s picked (was %s)", v, tostring(hold.SelectedCharacter))
    hold.SelectedCharacter = v
    -- (charpick.lua: the face chosen as the menu shuts - Max is Mario, Benj Luigi, Toby Wario, Drew Waluigi; any other
    -- the look off and no character put back)
    local C = package.loaded["charpick"]
    if C and C.mx then C.mx.pick, C.mx.pick_at = v, nil end
    local ch = C and C.CHAR_OF and C.CHAR_OF[v]
    if C and C.set_face then pcall(C.set_face, ch) end
    update_him()
    look_at = ch and (os.clock() + 0.6) or nil
    -- (his clothes left as they are: "every piece of clothing changes on charater select please fix that",
    -- 2026-11-01 - a character's clothes are its own buttons, clothpick.lua)
end

-- the picks waiting, each read a moment after (its value, or STORROR's data for it then)
local function take_picks()
    local now = os.clock()
    while #picks > 0 and now - picks[1].t > PICK_READ do
        local p = table.remove(picks, 1)
        local v = p.value
        if not v then
            local d = edata()
            v = d and read(d)[p.field]
        end
        if v then
            picked[p.field] = true
            local CL = package.loaded["clothpick"]
            local ours = (p.field ~= "SelectedCharacter") and p.ours or nil
            if ours then
                -- (STORROR's tick moved with the cursor on one of the mod's buttons: A on that one - STORROR picked one
                -- of its own instead; it is left out, ours put on: clothpick.lua)
                picked[p.field] = nil
                pcall(CL.choose_key, ours)
                log("character hold: %s - A on the mod's %s, STORROR's %s left out", p.field, ours, v)
            elseif p.field == "SelectedCharacter" then
                take_face(v)
            else
                -- (updated even when STORROR's own value is the same: the mod's cloth over it comes off - clothpick)
                log("character hold: %s %s picked (was %s)", p.field, v, tostring(hold[p.field]))
                hold[p.field] = v
                update_him()
            end
        end
    end
end

-- every tick, from charpick.lua (menu_open: STORROR's menu is up)
function M.tick(dt, menu_open)
    if not hooked then hook() end
    if not M.ON then hold = nil; return end
    if not menu_open then
        if hold then
            if release_t == 0.0 and M.WATCH then pcall(watch_grids, dt, true) end
            release_t = release_t + dt
            pcall(take_picks)
            if release_t < RELEASE then return end
            -- (the menu shut a moment ago: STORROR's data left as he is)
            local d = edata()
            if d then
                local cur = read(d)
                for f, v in pairs(hold) do if cur[f] ~= v then pcall(function() d[f] = v end) end end
            end
            -- (and what he wears now is what the next opening holds: the menu up again at once read the data before it
            -- was read afresh - the top just picked was put back to the old one, 2026-11-01)
            committed = {}
            for f, v in pairs(hold) do committed[f] = v end
            log("character hold: off (%s)", tostring(hold.SelectedCharacter))
            -- (`picked` kept till the menu is up again: clothpick.lua reads it as the menu shuts)
            hold, picks, look_at = nil, {}, nil
            closed_t = 0.0
        end
        closed_t = closed_t + dt
        if closed_t > 2.0 then
            local d = edata()
            if d then committed = read(d) end
        end
        return
    end
    release_t = 0.0
    if not hold then
        local d = edata()
        hold = {}
        for f, v in pairs(committed or (d and read(d)) or {}) do hold[f] = v end
        picks, picked, grids = {}, {}, {}
        log("character hold: on (%s, %s %s %s)", tostring(hold.SelectedCharacter), tostring(hold.TorsoClothing),
            tostring(hold.LegsClothing), tostring(hold.FeetClothing))
    end
    if M.WATCH then pcall(watch_grids, dt) end
    pcall(take_picks)
    local now = os.clock()
    if look_at and now > look_at then
        look_at = nil
        local L = package.loaded["mariolook"]
        local C = package.loaded["charpick"]
        local ch = C and C.CHAR_OF and C.CHAR_OF[hold.SelectedCharacter or ""]
        if L and ch and not L.on() then
            if L.set_char then L.set_char(ch) end
            pcall(L.apply)
        end
    end
end

-- a value held from now on (charmenu.lua: a slot's choice put on him while the menu is up)
function M.set_held(f, v) if hold and f then hold[f] = v end end

-- while STORROR's menu is up: the face he shows (nil otherwise)
function M.face() return hold and hold.SelectedCharacter or nil end
function M.holding() return hold ~= nil end
-- (clothpick.lua: the mod's own cloth chosen on that part - STORROR's pick of it no longer counts; and a pick of one
-- of STORROR's own seen by it - its tick hidden under ours, so not seen here - read at once)
function M.unpick(field) if field then picked[field] = nil end end
function M.pick_now(field)
    if hold and field then picks[#picks + 1] = { field = field, t = os.clock() - PICK_READ - 0.01 } end
end
-- a part picked this time the menu is up ("TorsoClothing", ...)
function M.picked(field) return picked[field] == true end

-- (the map gone - STORROR reloaded it with its menu up: what this keeps of it dropped untouched, main.lua's watch on the
-- map - "crash" twice, 2026-11-03, a moment into the game after that reload: an object of the gone map reached for)
-- (its watch on STORROR's grids above all: their widgets went with that menu)
function M.forget()
    hold, saved, look_at = nil, nil, nil
    picks, picked, grids = {}, {}, {}
    release_t, closed_t = 0.0, 0.0
end

return M
