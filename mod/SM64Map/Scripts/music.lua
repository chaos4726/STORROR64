-- SM64Map music: each level's own tune.
--
-- A scene names the Mario 64 sequence it plays ("level_grass", "level_inside_castle", ...). The mod
-- carries no music of its own: it plays <mod>/music/<name>.mp3 (or .wav, .m4a) if that file is there,
-- on a loop, through the game's own media player, and is silent for a tune that has no file.
local lib = require("lib")
local log = lib.log
local M = { current = nil, volume = 0.55, user = 1.0 }
M.BASE = M.volume       -- (the tune's own level, before anything turns it down for a while: intro.lua starts at it)
-- M.user: the player's own setting for Mario 64's music in the game (STORROR's Settings > Audio, MARIO 64 MUSIC:
-- msettings.lua), 0..1 on top of M.volume, which the game itself turns down and back (the pause screen). The title's
-- film music is film.lua's, and not this. (2026-10-15: "One new music slide for mario music INGAME only.")
-- (M.full: what plays is a cutscene's whole soundtrack - the new file's opening: Peach's voice, her jingle, Lakitu's
-- flight and its sounds - not a level's tune, and the in-game slider leaves it be. At the slider's 0.20 the castle
-- grounds' birds and waterfall, at full, buried it: "during the peach intro to the game is missing music", 2026-10-18)
local function vol() return M.volume * (M.full and 1.0 or (M.user or 1.0)) end
-- (the level's own sounds of the outdoors - the grounds' breeze, birds and waterfall - follow the same setting:
-- "also tie the outside sounds 'birds chirping and shit' to the mario music", 2026-10-22; loops.lua's too)
local function amb_user() return M.user or 1.0 end

local DIR = lib.MOD_DIR .. "music\\"

-- Where each level tune loops: its file runs a little past `from`, and on reaching it the player is sent back to `to`,
-- the same place one time round the tune earlier - so it plays on as Mario 64's own loop does, intro once. (They were
-- 150 s recordings that started over from the top, intro and all, every two and a half minutes.) Found by
-- X:/mashup-work/sm64audio/findloop.py + looppoints.py from 400 s renders: `to` is where the two times round agree
-- best (Mario 64's engine puts notes on ~16 ms steps, so a second time round can be a step off).
local LOOPS = {
    level_boss_koopa = { from = 238.042, to = 38.250 },     -- (match 1.0000)
    level_boss_koopa_final = { from = 91.883, to = 34.000 },     -- (match 1.0000)
    level_grass = { from = 122.025, to = 54.250 },     -- (match 0.9956)
    level_hot = { from = 104.655, to = 41.000 },     -- (match 0.9172)
    level_inside_castle = { from = 126.071, to = 65.000 },     -- (match 1.0000)
    level_koopa_road = { from = 218.867, to = 151.500 },     -- (match 0.9653)
    level_slide = { from = 145.329, to = 71.250 },     -- (match 0.9602)
    level_snow = { from = 166.850, to = 79.250 },     -- (match 1.0000)
    level_spooky = { from = 351.404, to = 184.500 },     -- (match 0.9919)
    level_underground = { from = 205.875, to = 119.500 },     -- (match 0.9965)
    level_water = { from = 178.975, to = 89.000 },     -- (match 0.9930)
    -- (the tunes over a level's: a boss fight's, and the secondary player's lullaby and merry-go-round)
    event_boss = { from = 105.392, to = 65.500 },     -- (match 0.9214)
    event_merry_go_round = { from = 165.879, to = 51.000 },     -- (match 0.9903)
    event_piranha_plant = { from = 104.812, to = 37.500 },     -- (match 0.9952)
    -- (the endless stairs' tune, rendered from the ROM 2026-11-01 - only its remix was there, so with REMIX MUSIC off
    -- the stairs were silent: "Endless Stairs but nothing else")
    event_endless_stairs = { from = 109.050, to = 37.250 },     -- (match 1.0000)
}
local EXT = { ".mp3", ".wav", ".m4a" }
local st = nil
local missing = {}

-- Remixes (Settings > Audio, REMIX MUSIC - msettings.lua, kept with the save files: "also we are going to need a new
-- music slider", 2026-11-01): with it on, a tune is played from <mod>/music_remix/<name> where there is one there
-- (tools/import_music.py puts them there under the tunes' names), else from music/ as ever. A remix loops whole: the
-- loop points (LOOPS) are the originals'.
local REMIX_DIR = lib.MOD_DIR .. "music_remix\\"
M.remix = false
pcall(function()
    local f = io.open(lib.MOD_DIR .. "saves.lua", "r")
    if f then
        local t = f:read("a")
        f:close()
        if t and t:match("remix_music%s*=%s*1") then M.remix = true end
    end
end)

local function valid(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

-- The file to play for a tune, whether it is a remix, and the tune's own name. A tune many levels share - Mario 64's
-- Slider - may have a remix for one level of its own (the user's list, 2026-11-01: Peach's Slide for the secret slide,
-- Cool Cool Slide, Tall Tall Slide, Rainbow Ride's, Wing Mario's, Powerful Mario for the cap towers, "Cosmic Clones as
-- race music against ghost"): music_remix/<tune>@<scene> - or @<scene> without its _2/_3, Tall Tall Mountain's three
-- slide parts as one - and a context's, asked for as "<tune>@<context>" (race.lua's ghost race: level_slide@race);
-- music_remix/<tune> for every other place. Mario 64's own (music/<tune>) when there is no remix or REMIX MUSIC is off.
local function file_for(name)
    local base, ctx = name:match("^(.-)@(.+)$")
    base = base or name
    if M.remix then
        local names = {}
        if ctx then names[#names + 1] = base .. "@" .. ctx end
        local G = package.loaded["game"]
        local sc = G and G.name
        if sc then
            names[#names + 1] = base .. "@" .. sc
            local s2 = sc:gsub("_%d+$", "")
            if s2 ~= sc then names[#names + 1] = base .. "@" .. s2 end
        end
        names[#names + 1] = base
        for _, n in ipairs(names) do
            for _, e in ipairs(EXT) do
                local path = REMIX_DIR .. n .. e
                local f = io.open(path, "rb")
                if f then f:close(); return path, true, base end
            end
        end
    end
    for _, e in ipairs(EXT) do
        local path = DIR .. base .. e
        local f = io.open(path, "rb")
        if f then f:close(); return path, false, base end
    end
    return nil
end
-- (a tune that has a file to play, as things are set)
function M.has(name) return file_for(name) ~= nil end

-- the player and the component that turns what it plays into sound; made once per map
local function ensure()
    local world = lib.world()
    if not world then return nil end
    local addr = world:GetAddress()
    if st and st.world == addr and valid(st.mp) and valid(st.comp) then return st end
    st = nil
    local MP = StaticFindObject("/Script/MediaAssets.MediaPlayer")
    local MSC = StaticFindObject("/Script/MediaAssets.MediaSoundComponent")
    if not (valid(MP) and valid(MSC)) then return nil end
    local actor = lib.spawn_actor(world, { X = lib.OFFSET.X, Y = lib.OFFSET.Y, Z = lib.OFFSET.Z + 2000.0 }, 0.0)
    if not actor then return nil end
    pcall(function() lib.keep[actor:GetAddress()] = true end)
    local mp = StaticConstructObject(MP, actor, FName("SM64MusicPlayer"))
    local comp = actor:AddComponentByClass(MSC, false, {
        Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = 0.0, Y = 0.0, Z = 0.0 },
        Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }, false)
    if not (valid(mp) and valid(comp)) then return nil end
    pcall(function() comp:SetMediaPlayer(mp) end)
    -- (SetMediaPlayer does not keep the player from the engine's clean-up; the component's own property does)
    pcall(function() comp.MediaPlayer = mp end)
    pcall(function() comp:SetVolumeMultiplier(vol()) end)
    -- (the top priority: the engine plays only so many sounds at once and drops the least of them)
    pcall(function() comp.AudioComponent.Priority = 100.0 end)
    pcall(function() comp.AudioComponent.bAlwaysPlay = true end)
    st = { world = addr, actor = actor, mp = mp, comp = comp }
    return st
end

-- Play the tune `name` on a loop (nil = silence), or just once with `once`; `full`: a cutscene's soundtrack (M.full).
-- Asking for the tune already playing changes nothing.
-- (the ending's own tunes, and only those, while it plays: the credits' shots are the levels, and in Big Boo's Haunt's
-- the boss's tune came up over them - "during ghost scene it changes to boss music", 2026-11-02)
local ENDING_TUNES = { event_victory = true, event_ending = true, event_credits = true }
local function ending_on() local EN = package.loaded["ending"]; return EN ~= nil and EN.active == true end
function M.play(name, once, full)
    if name and not ENDING_TUNES[name] and ending_on() then return false end
    local s = ensure()
    if not s then return false end
    -- (the same tune in another level may be another file - Slider's remixes, file_for: the same file goes on as it is)
    local path, remixed, base = nil, false, name
    if name then path, remixed, base = file_for(name) end
    if name == M.current and s.playing == name and s.path == path then return true end
    M.current = name
    M.full = full == true
    pcall(function() s.comp:SetVolumeMultiplier(vol() * (s.duck or 1.0) * (M.lvl_gain or 1.0)) end)
    -- (the tune opened ahead, M.preload: started where it waits, at once)
    local pre = s.pre
    s.pre = nil
    if pre and name and pre.name == name and pre.path == path then
        local okp = pcall(function()
            s.mp:SetLooping(not once)
            s.mp.PlayOnOpen = true
            s.mp:Play()
        end)
        if okp then
            s.playing, s.once, s.path = name, once, path
            s.loop, s.seeking = (not once and not remixed) and LOOPS[base or name] or nil, nil
            log("music: %s (opened ahead)", name)
            return true
        end
    end
    if pre then pcall(function() s.mp.PlayOnOpen = true end) end
    pcall(function() s.mp:Close() end)
    s.playing, s.path = nil, nil
    if not name then return true end
    if not path then
        if not missing[name] then
            missing[name] = true
            log("music: no file for %s in %s", name, DIR)
        end
        return false
    end
    local ok, opened = pcall(function()
        s.mp:SetLooping(not once)
        return s.mp:OpenFile(path)
    end)
    if ok and opened then
        s.playing, s.once, s.path = name, once, path
        s.loop, s.seeking = (not once and not remixed) and LOOPS[base or name] or nil, nil
        log("music: %s%s", name, remixed and (" (remix: " .. (path:match("[^\\]+$") or path) .. ")") or "")
        return true
    end
    log("music: could not open %s (%s)", path, tostring(opened))
    return false
end

-- A tune opened ahead and held at its start, so that M.play starts it the moment it is asked for: opening a file takes the
-- player a moment, and the Grand Star's victory tune came in late after the grab - "outro music doesnt start soon
-- enough", 2026-11-02. Only while nothing plays; any other M.play forgets it.
function M.preload(name)
    local s = ensure()
    if not (s and name) or s.playing then return false end
    local path = file_for(name)
    if not path then return false end
    local ok, opened = pcall(function()
        s.mp.PlayOnOpen = false
        s.mp:SetLooping(false)
        return s.mp:OpenFile(path)
    end)
    if ok and opened then
        s.pre = { name = name, path = path }
        log("music: %s opened ahead", name)
        return true
    end
    pcall(function() s.mp.PlayOnOpen = true end)
    return false
end

function M.set_volume(v)
    M.volume = v
    if st and valid(st.comp) then pcall(function() st.comp:SetVolumeMultiplier(vol() * (st.duck or 1.0) * (M.lvl_gain or 1.0)) end) end
end

-- REMIX MUSIC turned: what is playing starts again from the other folder (where it has a file there)
function M.set_remix(on)
    on = on and true or false
    if M.remix == on then return end
    M.remix = on
    log("music: remixes %s", on and "on" or "off")
    local s = st
    if s and s.playing and valid(s.mp) then
        local name, once = s.playing, s.once
        s.playing, M.current = nil, nil
        M.play(name, once, M.full)
    end
    if M.amb_again then pcall(M.amb_again) end
    if M.pause_refresh then pcall(M.pause_refresh) end
end

-- the player's setting (0..1): straight away on what is playing
function M.set_user(u)
    M.user = math.max(0.0, math.min(1.0, u or 1.0))
    if st and valid(st.comp) then pcall(function() st.comp:SetVolumeMultiplier(vol() * (st.duck or 1.0) * (M.lvl_gain or 1.0)) end) end
    -- (a second tune over it takes it up on its next tick)
    pcall(M.hush, M.amb_hush)           -- (and the outdoors' sounds, straight away too)
end

-- A second tune over the level's (Mario 64's play_secondary_music: a sleeping Piranha Plant's lullaby, BBH's
-- merry-go-round): whatever wants one asks each frame, M.want_secondary(name, vol, bg) with its volume and how much
-- of the level's tune stays under it (0..1); M.tick fades them there, and back when nothing asks.
local sec, wanted = nil, nil
local cur = { name = nil, vol = 0.0, bg = 1.0 }
-- what plays now, for nowplaying.lua: the level's tune, and the one over it with its loudness (0..1)
function M.now_playing()
    local ak = nil
    if M.ambience_now then pcall(function() ak = M.ambience_now() end) end
    return { main = M.current, over = cur and cur.name or nil, over_vol = cur and cur.vol or 0.0, ambience = ak }
end

function M.want_secondary(name, vol, bg)
    if ending_on() then return end                  -- (no second tune over the ending's: M.play)
    -- (asked at the creatures' 30 a second, ticked every frame: an ask holds for a moment)
    local now = os.clock()
    if not wanted or now - wanted.at > 0.1 or vol >= wanted.vol then wanted = { name = name, vol = vol, bg = bg, at = now } end
end

local function sec_player(world, addr)
    if sec and sec.world == addr and valid(sec.mp) and valid(sec.comp) then return sec end
    sec = nil
    local MP = StaticFindObject("/Script/MediaAssets.MediaPlayer")
    local MSC = StaticFindObject("/Script/MediaAssets.MediaSoundComponent")
    if not (valid(MP) and valid(MSC)) then return nil end
    local actor = lib.spawn_actor(world, { X = lib.OFFSET.X, Y = lib.OFFSET.Y, Z = lib.OFFSET.Z + 2400.0 }, 0.0)
    if not actor then return nil end
    pcall(function() lib.keep[actor:GetAddress()] = true end)
    local mp = StaticConstructObject(MP, actor, FName("SM64SecondaryPlayer"))
    local comp = actor:AddComponentByClass(MSC, false, {
        Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = 0.0, Y = 0.0, Z = 0.0 },
        Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }, false)
    if not (valid(mp) and valid(comp)) then return nil end
    pcall(function() comp:SetMediaPlayer(mp) end)
    pcall(function() comp.MediaPlayer = mp end)             -- (keeps the player alive)
    pcall(function() comp:SetVolumeMultiplier(0.0) end)
    sec = { world = addr, mp = mp, comp = comp, v = 0.0 }
    return sec
end

local function toward(v, t, step) if v < t then return math.min(t, v + step) end return math.max(t, v - step) end

-- The level's tune turned down for `secs` under a jingle played as a sound (Mario 64's play_power_star_jingle and
-- play_toads_jingle: the background music held at 20 of its 127 while the jingle plays on the other player)
local dip = nil
function M.dip(secs, level) dip = { till = os.clock() + secs, level = level or 0.16, set = nil } end

-- the level tune at its loop point: back one time round (see LOOPS)
local function keep_looping(s)
    if not (s and s.loop and valid(s.mp)) then return end
    local t = nil
    pcall(function() t = s.mp:GetTime().Ticks / 1e7 end)
    if not t then return end
    -- (a seek takes a moment to land, and the clock reads the old place till then: asked again every frame, it never
    -- landed and the tune stuck at the loop point)
    if s.seeking then
        if t < s.loop.from - 1.0 or os.clock() > s.seeking then s.seeking = nil end
        return
    end
    if t < s.loop.from then return end
    local back = s.loop.to + (t - s.loop.from)
    pcall(function() s.mp:Seek({ Ticks = math.floor(back * 1e7) }) end)
    s.seeking = os.clock() + 1.5
end

-- A tune that should go round and round but has stopped - the end of its file reached and the player not starting it
-- again - started again from its top, after a second of silence, unless the game is paused ("where'd the music go",
-- "might have to repeat the music", 2026-11-03). `s`: the player's state.
function M.keep_playing(s)
    if not (s and s.playing and not s.once and s.path and valid(s.mp)) or M.paused then
        if s then s.stopped_at = nil end
        return
    end
    local on = true
    pcall(function() on = s.mp:IsPlaying() end)
    if on then s.stopped_at = nil; return end
    s.stopped_at = s.stopped_at or os.clock()
    if os.clock() - s.stopped_at < 1.0 then return end
    s.stopped_at = nil
    local ok = pcall(function() s.mp:SetLooping(true); s.mp:OpenFile(s.path) end)
    log("music: %s had stopped - started again (%s)", tostring(s.playing), tostring(ok))
end

function M.tick(dt)
    if M.pause_watch then pcall(M.pause_watch) end
    pcall(M.keep_playing, st)
    -- (the remixed outdoors - itself a piece of music, "Flowers": out while a tune plays on the main player - a cap's, a
    -- star's - and back after; two songs at once over the castle grounds, "when picking up cap theres two songs playing at
    -- the same time", 2026-11-02. Mario 64's own birds stay under. M.amb_tune: its share, through M.hush)
    do
        local a = M.ambience_now and M.ambience_now()
        local tune = false
        if a and a:find("(remix)", 1, true) and st and st.playing and valid(st.mp) then
            pcall(function() tune = st.mp:IsPlaying() end)
        end
        local f0 = M.amb_tune or 1.0
        local f = toward(f0, tune and 0.0 or 1.0, (dt or 0.0) / 0.8)
        if f ~= f0 then M.amb_tune = f; if M.hush then pcall(M.hush, M.amb_hush) end end
    end
    pcall(keep_looping, st and st.playing and st or nil)
    pcall(keep_looping, sec)
    if dip then
        local under = os.clock() < dip.till
        local want = under and dip.level or 1.0
        if dip.set ~= want and st and valid(st.comp) then
            dip.set = want
            pcall(function() st.comp:SetVolumeMultiplier(vol() * want * (st.duck or 1.0)) end)
        end
        if not under then dip = nil end
    end
    local w = wanted
    if w and os.clock() - w.at > 0.2 then w, wanted = nil, nil end
    local world = lib.world()
    if not world then return end
    local addr = world:GetAddress()
    if sec and sec.world ~= addr then
        -- (a new map: the old player is only forgotten)
        sec, cur = nil, { name = nil, vol = 0.0, bg = 1.0 }
    end
    if w and cur.name and w.name ~= cur.name then w = nil end      -- (the one playing fades out first)
    if w and not cur.name then
        local s = sec_player(world, addr)
        local path, remixed, base = nil, false, w.name
        if s then path, remixed, base = file_for(w.name) end
        if not path then return end
        local ok, opened = pcall(function() s.mp:SetLooping(true); return s.mp:OpenFile(path) end)
        if not (ok and opened) then return end
        s.loop, s.seeking = (not remixed) and LOOPS[base or w.name] or nil, nil
        cur.name = w.name
        log("music: %s over the level's", w.name)
    end
    if not cur.name then return end
    local step = dt / 1.5
    cur.vol = toward(cur.vol, w and w.vol or 0.0, step)
    cur.bg = toward(cur.bg, w and w.bg or 1.0, step)
    if sec and valid(sec.comp) and math.abs(sec.v - cur.vol) > 0.01 then
        sec.v = cur.vol
        pcall(function() sec.comp:SetVolumeMultiplier(vol() * cur.vol) end)
    end
    if st and valid(st.comp) and math.abs((st.duck or 1.0) - cur.bg) > 0.01 then
        st.duck = cur.bg
        pcall(function() st.comp:SetVolumeMultiplier(vol() * cur.bg) end)
    end
    if not w and cur.vol <= 0.0 and cur.bg >= 1.0 then
        -- (logged: the two crashes of 2026-10-17 05:18 and 05:26 both came seconds after a Piranha Plant's lullaby ended)
        log("music: %s over the level's - off", tostring(cur.name))
        if sec then pcall(function() sec.mp:Close() end) end
        if st and valid(st.comp) then st.duck = 1.0; pcall(function() st.comp:SetVolumeMultiplier(vol()) end) end
        cur.name = nil
        if sec then sec.loop = nil end
    end
end

-- The castle grounds' waterfall: its roar on a loop of its own (<mod>/ambience/waterfall.m4a), at `v` (0..1) of
-- full; the scenery sets it by how near the athlete is. nil stops it.
local fall = nil
function M.waterfall(v)
    local world = lib.world()
    if not world then return end
    local addr = world:GetAddress()
    if v == nil then
        -- (a player of a map that has gone is only forgotten: touching it can bring the game down)
        if fall and fall.world ~= addr then fall = nil end
        if fall then pcall(function() fall.mp:Close() end); fall.playing = false end
        return
    end
    if not (fall and fall.world == addr and valid(fall.mp) and valid(fall.comp)) then
        fall = nil
        local MP = StaticFindObject("/Script/MediaAssets.MediaPlayer")
        local MSC = StaticFindObject("/Script/MediaAssets.MediaSoundComponent")
        if not (valid(MP) and valid(MSC)) then return end
        local actor = lib.spawn_actor(world, { X = lib.OFFSET.X, Y = lib.OFFSET.Y, Z = lib.OFFSET.Z + 2300.0 }, 0.0)
        if not actor then return end
        pcall(function() lib.keep[actor:GetAddress()] = true end)
        local mp = StaticConstructObject(MP, actor, FName("SM64WaterfallPlayer"))
        local comp = actor:AddComponentByClass(MSC, false, {
            Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = 0.0, Y = 0.0, Z = 0.0 },
            Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }, false)
        if not (valid(mp) and valid(comp)) then return end
        pcall(function() comp:SetMediaPlayer(mp) end)
        pcall(function() comp.MediaPlayer = mp end)
        fall = { world = addr, mp = mp, comp = comp, playing = false, v = -1.0 }
    end
    if not fall.playing then
        -- (.wav where the installer rendered it from the player's ROM: its .m4a only where the mod was made)
        local path = lib.MOD_DIR .. "ambience\\waterfall.m4a"
        local fm = io.open(path, "rb")
        if fm then fm:close() else path = lib.MOD_DIR .. "ambience\\waterfall.wav" end
        local ok, opened = pcall(function() fall.mp:SetLooping(true); return fall.mp:OpenFile(path) end)
        fall.playing = ok and opened and true or false
    end
    if math.abs(v - fall.v) > 0.02 then
        fall.v = v
        pcall(function() fall.comp:SetVolumeMultiplier(v * (M.amb_hush or 1.0) * amb_user()) end)
    end
end

-- A level's ambience, under its music: <mod>/ambience/<name>.m4a on a loop through a player of its own (the castle
-- grounds have no music in Mario 64, only the breeze and the birds). nil = none.
M.amb_volume = 1.0
local amb = nil
function M.ambience_now() return amb and amb.playing or nil end   -- (nowplaying.lua)
local AMB_DIR = lib.MOD_DIR .. "ambience\\"
-- (with REMIX MUSIC on, <mod>/ambience_remix/<name>.m4a where there is one: outside, "Flowers (Nature Sounds)" by
-- Dennis Korn in place of Mario 64's birds - "\"Flowers (Nature Sounds)\" - Dennis Korn as outside ambiance",
-- 2026-11-01; made a seamless loop at the birds' loudness)
local AMB_REMIX_DIR = lib.MOD_DIR .. "ambience_remix\\"
local function amb_file(name)
    -- (the ending's scenes - Peach's on the castle grounds: Mario 64's own birds, never the remixed outdoors - "can hear
    -- castle grounds music in the peach ending. should only use mario 64's original ambiance during", 2026-11-02)
    local EN = package.loaded["ending"]
    if M.remix and not (EN and EN.active) then
        local rp = AMB_REMIX_DIR .. name .. ".m4a"
        local f = io.open(rp, "rb")
        if f then f:close(); return rp, true end
    end
    -- (.wav where the installer rendered it from the player's ROM)
    local p = AMB_DIR .. name .. ".m4a"
    local f = io.open(p, "rb")
    if f then f:close(); return p, false end
    return AMB_DIR .. name .. ".wav", false
end

function M.ambience(name)
    local world = lib.world()
    if not world then return false end
    local addr = world:GetAddress()
    if not (amb and amb.world == addr and valid(amb.mp) and valid(amb.comp)) then
        amb = nil
        local MP = StaticFindObject("/Script/MediaAssets.MediaPlayer")
        local MSC = StaticFindObject("/Script/MediaAssets.MediaSoundComponent")
        if not (valid(MP) and valid(MSC)) then return false end
        local actor = lib.spawn_actor(world, { X = lib.OFFSET.X, Y = lib.OFFSET.Y, Z = lib.OFFSET.Z + 2200.0 }, 0.0)
        if not actor then return false end
        pcall(function() lib.keep[actor:GetAddress()] = true end)
        local mp = StaticConstructObject(MP, actor, FName("SM64AmbiencePlayer"))
        local comp = actor:AddComponentByClass(MSC, false, {
            Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = 0.0, Y = 0.0, Z = 0.0 },
            Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }, false)
        if not (valid(mp) and valid(comp)) then return false end
        pcall(function() comp:SetMediaPlayer(mp) end)
        pcall(function() comp.MediaPlayer = mp end)             -- (as above: keeps the player alive)
        pcall(function() comp:SetVolumeMultiplier(M.amb_volume * (M.amb_hush or 1.0) * amb_user() * (M.amb_tune or 1.0)) end)
        amb = { world = addr, mp = mp, comp = comp }
    end
    local path, remixed = nil, false
    if name then path, remixed = amb_file(name) end
    local key = name and (name .. (remixed and " (remix)" or "")) or nil
    if key == amb.playing then return true end
    pcall(function() amb.mp:Close() end)
    amb.playing, amb.name = nil, nil
    if not name then return true end
    local f = io.open(path, "rb")
    if not f then log("ambience: no file %s", path); return false end
    f:close()
    local ok, opened = pcall(function()
        amb.mp:SetLooping(true)
        return amb.mp:OpenFile(path)
    end)
    if ok and opened then amb.playing, amb.name = key, name; log("ambience: %s", key); return true end
    log("ambience: could not open %s (%s)", path, tostring(opened))
    return false
end

-- (the ambience playing, again from the folder REMIX MUSIC now picks: M.set_remix)
function M.amb_again()
    if amb and amb.name then M.ambience(amb.name) end
end

-- The pause tune: with REMIX MUSIC on, while the game is paused - STORROR's menu up or Mario 64's pause screen
-- (pause.lua M.menu_up / M.open) - <mod>/music_remix/menu_pause plays on a player of its own, on a loop, and the
-- level's tune is held where it was and goes on from there after. ("Super Mario 64 - File Select (Anthony Greninger
-- Cover Remix) as pause menu music", 2026-11-01.) Mario 64 has no pause tune: with REMIX MUSIC off, its own way - the
-- level's tune on, quieter (pause.lua MUSIC_DOWN).
local PAUSE_TUNE = "menu_pause"
local pz = nil
M.paused = false
local function pause_file()
    for _, e in ipairs(EXT) do
        local path = REMIX_DIR .. PAUSE_TUNE .. e
        local f = io.open(path, "rb")
        if f then f:close(); return path end
    end
    return nil
end
local function pause_player()
    local world = lib.world()
    if not world then return nil end
    local addr = world:GetAddress()
    if pz and pz.world == addr and valid(pz.mp) and valid(pz.comp) then return pz end
    pz = nil
    local MP = StaticFindObject("/Script/MediaAssets.MediaPlayer")
    local MSC = StaticFindObject("/Script/MediaAssets.MediaSoundComponent")
    if not (valid(MP) and valid(MSC)) then return nil end
    local actor = lib.spawn_actor(world, { X = lib.OFFSET.X, Y = lib.OFFSET.Y, Z = lib.OFFSET.Z + 2600.0 }, 0.0)
    if not actor then return nil end
    pcall(function() lib.keep[actor:GetAddress()] = true end)
    local mp = StaticConstructObject(MP, actor, FName("SM64PausePlayer"))
    local comp = actor:AddComponentByClass(MSC, false, {
        Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = 0.0, Y = 0.0, Z = 0.0 },
        Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }, false)
    if not (valid(mp) and valid(comp)) then return nil end
    pcall(function() comp:SetMediaPlayer(mp) end)
    pcall(function() comp.MediaPlayer = mp end)             -- (keeps the player alive)
    pcall(function() comp.AudioComponent.Priority = 100.0 end)
    pcall(function() comp.AudioComponent.bAlwaysPlay = true end)
    pz = { world = addr, mp = mp, comp = comp, on = false, v = -1.0 }
    return pz
end
-- (as loud as the level's tune is set - MARIO 64 MUSIC - not the quieter level the pause turns that down to)
local function pause_vol() return M.user or 1.0 end

-- The fades ("make the transition of music smoother", 2026-11-01): paused, the level's tune goes out over PAUSE_OUT
-- seconds and is held once silent, the pause tune comes in over PAUSE_IN, and the ambience and the waterfall go out
-- with the level's (outside, the nature sounds went on under the pause tune: "its playing double music in the menu");
-- back in the game, the pause tune goes out over PAUSE_OUT and the level's tune - on again where it was held - and the
-- ambience come back in over PAUSE_IN. M.lvl_gain: the level tune's share (its volume everywhere is times it).
local PAUSE_IN, PAUSE_OUT = 1.0, 0.6
M.lvl_gain = 1.0
local pgain, again, amb_was, last_t, lvl_held = 0.0, 1.0, nil, nil, false
local lvl_up = false            -- (the tune's player turned back up for this opening: M.pause_watch)

-- every tick (music.lua's tick, and msettings.lua's while paused - game.lua's stops short of ours then): paused or not
-- (pause.lua), and the fades a step on
function M.pause_watch()
    local now = os.clock()
    local dt = last_t and math.min(0.1, math.max(0.0, now - last_t)) or 0.0
    last_t = now
    local P = package.loaded["pause"]
    local paused = false
    if P then
        paused = P.open == true
        if not paused and P.menu_up then
            local ok, up = pcall(P.menu_up)
            paused = ok and up == true
        end
    end
    -- (in multiplayer the game goes on under the menus, its tune too: pause.lua M.online)
    if paused and P and P.online and P.online() then paused = false end
    M.paused = paused
    -- (the opening intro has the sound to itself: a pause tune still going from the file select shut at once, and
    -- nothing put back that the pause had turned down - its fading out brought the outdoors' sounds back up over the
    -- intro and set the intro's tune to the music slider: "outside music plays over intro music", "music conflicts",
    -- 2026-11-01)
    do
        local IN = package.loaded["intro"]
        if IN and IN.active then
            if pz and pz.on then pcall(function() pz.mp:Close() end); pz.on = false end
            pgain, again, amb_was, lvl_held = 0.0, 1.0, nil, false
            -- (and the tune's own player turned back up with it: the pause fades it to nothing, and quit from the pause
            -- to the file select that fade was never undone - the opening's tune, started under it, played silent:
            -- "music is gone again", 2026-11-09)
            if M.lvl_gain ~= 1.0 or not lvl_up then
                M.lvl_gain = 1.0
                if st and valid(st.comp) then
                    pcall(function() st.comp:SetVolumeMultiplier(vol() * (st.duck or 1.0)) end)
                    lvl_up = true
                end
            end
            return
        end
        lvl_up = false
    end
    local path = (paused and M.remix) and pause_file() or nil
    local p = pz
    if path then
        p = pause_player()
        if p and not p.on then
            local ok, opened = pcall(function()
                p.comp:SetVolumeMultiplier(0.0)
                p.mp:SetLooping(true)
                return p.mp:OpenFile(path)
            end)
            if ok and opened then
                p.on, p.v, pgain = true, 0.0, 0.0
                if amb_was == nil then amb_was = M.amb_hush or 1.0 end
                log("music: %s (remix) - paused", PAUSE_TUNE)
            else
                log("music: could not open %s", path)
            end
        end
    end
    local want = (path and p and p.on) and 1.0 or 0.0
    -- the pause tune in, or out and shut
    if p and p.on then
        pgain = toward(pgain, want, dt / ((want > 0.0) and PAUSE_IN or PAUSE_OUT))
        local v = pause_vol() * pgain
        if valid(p.comp) and math.abs((p.v or -1.0) - v) > 0.002 then
            p.v = v
            pcall(function() p.comp:SetVolumeMultiplier(v) end)
        end
        if want == 0.0 and pgain <= 0.0 then
            pcall(function() p.mp:Close() end)
            p.on = false
            log("music: %s off - the level's tune goes on", PAUSE_TUNE)
        end
    end
    -- the level's tune out and held, or on again and in
    local lt = (want > 0.0) and 0.0 or 1.0
    local g = toward(M.lvl_gain, lt, dt / ((lt > 0.0) and PAUSE_IN or PAUSE_OUT))
    if st and st.playing and valid(st.mp) then
        if want > 0.0 and g <= 0.0 then
            local playing = false
            pcall(function() playing = st.mp:IsPlaying() end)
            if playing then pcall(function() st.mp:Pause() end); lvl_held = true end
        elseif want == 0.0 and lvl_held then
            pcall(function() st.mp:Play() end)
            lvl_held = false
        end
    end
    if g ~= M.lvl_gain then
        M.lvl_gain = g
        if st and valid(st.comp) then pcall(function() st.comp:SetVolumeMultiplier(vol() * (st.duck or 1.0) * g) end) end
    end
    -- the ambience and the waterfall with it
    if amb_was then
        local at = (want > 0.0) and 0.0 or 1.0
        local a = toward(again, at, dt / ((at > 0.0) and PAUSE_IN or PAUSE_OUT))
        if a ~= again then
            again = a
            if M.hush then pcall(M.hush, amb_was * a) end
        end
        if at > 0.0 and again >= 1.0 then amb_was = nil end
    end
end
-- (REMIX MUSIC turned while paused: on or off at once - a step now, the rest each tick)
function M.pause_refresh() M.pause_watch() end

-- The ambience and the waterfall turned down to `f` (0..1) of what they are, under a cutscene's soundtrack (the new
-- file's opening); 1 = back.
M.amb_hush = 1.0
function M.hush(f)
    M.amb_hush = f or 1.0
    if amb and valid(amb.comp) then pcall(function() amb.comp:SetVolumeMultiplier(M.amb_volume * M.amb_hush * amb_user() * (M.amb_tune or 1.0)) end) end
    if fall and valid(fall.comp) and fall.v >= 0.0 then pcall(function() fall.comp:SetVolumeMultiplier(fall.v * M.amb_hush * amb_user()) end) end
end

-- The map went (main.lua FORGET_ON_MAP): every player of the gone map - the tune's, the second one's, the falls', the
-- outdoors', the pause tune's - dropped without touching it; the next of each is made in the new map.
-- (a new map can sit where the old one was, its address the same, and its players were taken for this map's: the
-- intro's first sound reached for a freed one after STORROR's menu reloaded the map - "crash", 2026-11-03)
function M.forget() st, sec, wanted, fall, amb, pz = nil, nil, nil, nil, nil, nil end

return M
