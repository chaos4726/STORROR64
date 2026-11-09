-- SM64Map sound effects: short Mario 64 sounds, played once.
--
-- Like the music, the sounds are the player's own: rendered from their ROM by sm64audio (X:\mashup-work) into
-- <mod>/sfx/<name>.wav. They play through the game's media player. A few players take turns, so a sound can
-- start while the last one is still going (a click straight after a click).
local lib = require("lib")
local log = lib.log
local M = { volume = 0.8 }

local DIR = lib.MOD_DIR .. "sfx\\"
local PLAYERS = 4
local st = nil
local missing = {}

local function valid(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

-- the players and the components that turn what they play into sound; made once per map
local function ensure()
    local world = lib.world()
    if not world then return nil end
    local addr = world:GetAddress()
    if st and st.world == addr then
        local ok = true
        for _, p in ipairs(st.players) do if not (valid(p.mp) and valid(p.comp)) then ok = false end end
        if ok then return st end
    end
    st = nil
    local MP = StaticFindObject("/Script/MediaAssets.MediaPlayer")
    local MSC = StaticFindObject("/Script/MediaAssets.MediaSoundComponent")
    if not (valid(MP) and valid(MSC)) then return nil end
    local actor = lib.spawn_actor(world, { X = lib.OFFSET.X, Y = lib.OFFSET.Y, Z = lib.OFFSET.Z + 2100.0 }, 0.0)
    if not actor then return nil end
    pcall(function() lib.keep[actor:GetAddress()] = true end)
    local s = { world = addr, actor = actor, players = {}, next = 1 }
    for i = 1, PLAYERS do
        local mp = StaticConstructObject(MP, actor, FName("SM64SoundPlayer" .. i))
        local comp = actor:AddComponentByClass(MSC, false, {
            Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = 0.0, Y = 0.0, Z = 0.0 },
            Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }, false)
        if not (valid(mp) and valid(comp)) then return nil end
        pcall(function() comp:SetMediaPlayer(mp) end)
        -- (SetMediaPlayer does not keep the player from the engine's clean-up; the component's own property does)
        pcall(function() comp.MediaPlayer = mp end)
        pcall(function() comp:SetVolumeMultiplier(M.volume) end)
        pcall(function() mp:SetLooping(false) end)
        s.players[i] = { mp = mp, comp = comp }
    end
    st = s
    return st
end

-- The player now playing (or last played) sound `name`, or nil: its media player `mp` and sound component `comp`.
function M.player_of(name)
    for _, p in ipairs(st and st.players or {}) do if p.name == name then return p end end
    return nil
end

-- The players made ahead of the first sound in a map (title.lua: his "Hello!" lost its start, played the frame they
-- were made).
-- (and each started on a moment of silence, sfx/silence.wav: a player's first sound after the game starts came out
-- silent for its first half second or so - recorded from the game's own sound at boot, his "Hello!" was only "-llo",
-- 2026-10-20 - a sound played once they are going is heard whole)
function M.warm()
    local s = ensure()
    if not s then return false end
    local path = DIR .. "silence.wav"
    local f = io.open(path, "rb")
    if not f then return true end
    f:close()
    -- (one player a frame, M.prime_tick: all four opened in one frame made the title's start stutter, "2nd menu starts up
    -- laggy", 2026-10-20)
    s.prime = {}
    for _, p in ipairs(s.players) do s.prime[#s.prime + 1] = p; p.busy_till = os.clock() + 1.0 end
    return true
end
function M.prime_tick()
    local s = st
    local q = s and s.prime
    if not (q and #q > 0) then return end
    local p = table.remove(q, 1)
    pcall(function() p.comp:SetVolumeMultiplier(0.0) end)
    local ok = pcall(function() p.mp:OpenFile(DIR .. "silence.wav") end)
    p.name, p.busy_till = ok and "silence" or nil, ok and (os.clock() + 0.45) or nil
end

-- How long a sound runs, from its file's header. A long one - a fanfare, a jingle - keeps its player till its end, so
-- the next few short sounds do not cut it off ("when picking up a star the audio cuts out", 2026-10-17: the star's
-- fanfare went with the third sound after it - his landing, the dance's voice, a splash).
local LONG = 1.5
local lengths = {}
local function length_of(path)
    local n = lengths[path]
    if n then return n end
    n = 0.0
    local f = io.open(path, "rb")
    if f then
        local h = f:read(44)
        local size = f:seek("end")
        f:close()
        if h and #h >= 36 and size then
            local ch = h:byte(23) + h:byte(24) * 256
            local rate = h:byte(25) + h:byte(26) * 256 + h:byte(27) * 65536 + h:byte(28) * 16777216
            local bits = h:byte(35) + h:byte(36) * 256
            if ch > 0 and rate > 0 and bits > 0 then n = (size - 44) / (rate * ch * bits / 8) end
        end
    end
    lengths[path] = n
    return n
end

-- Mario's own voice - every "mario_" clip, and his words on the title, the file select and the ending - is as loud as
-- the player's MARIO FX setting (Settings > Audio, msettings.lua; kept by menu.lua as `jump_voice`; 0 = not heard): the
-- factor for sound `name`, 1 for any other. (Once only the jumps' voice was, each place applying it itself; his hurts,
-- falls and deaths were as loud as ever - "make sure mario sounds are tied to our audio slide", 2026-10-27)
M.MARIO_VOICE = { title_hello = true, menu_lets_a_go = true, thank_you = true }
function M.mario_fx(name)
    if not (name:sub(1, 6) == "mario_" or M.MARIO_VOICE[name]) then return 1.0 end
    -- (none while the opening intro holds him out of sight before his jump out of the pipe: intro.lua I.quiet)
    local IN = package.loaded["intro"]
    if IN and IN.quiet and IN.quiet() then return 0.0 end
    local MN = _G.MENU
    return (MN and MN.jump_voice and MN.jump_voice()) or 1.0
end

-- The enemies' sounds - every "en_" clip and these, Mario 64's enemies' own (their steps, their calls, their hits and
-- deaths, Bowser's) - as loud as the player's ENEMIES VOLUME setting (Mario settings, msettings.lua; kept by menu.lua as
-- `enemies_volume`; 0 = not heard): the factor for sound `name` ("file@tag" for a held sound's own player), 1 for any
-- other. ("also in mario settings we need a enemies volume slider", 2026-11-03)
M.ENEMY_SOUNDS = {
    goomba_walk = true, goomba_stomp = true, goomba_stomp_huge = true,
    bobomb_walk = true, loop_fuse = true, explosion = true,
    king_death = true, king_grab = true, king_hurt = true, king_jump = true, king_step = true, king_throw = true,
    king_voice = true,
    bowser_bomb = true, bowser_defeated = true, bowser_explode = true, bowser_inhale = true, bowser_intro_laugh = true,
    bowser_laugh = true, bowser_roar = true, bowser_spin = true, bowser_tail = true, bowser_teleport = true,
    bowser_walk = true, loop_bowser_fire = true,
    chomp_hop = true, chomp_lunge = true, bubba_chomp = true, piano_chomp = true,
    whomp_short = true, whomp_step = true,
    wiggler_attacked = true, wiggler_jump = true, wiggler_step_high = true, wiggler_step_low = true,
    loop_amp = true, loop_chuckya = true, loop_heaveho = true, loop_mri = true, loop_lakitu = true,
    skeeter_skate = true, grindel_roll = true, spindel_roll = true, haunted_chair = true, bookend_open = true,
    blizzard_alert = true, wbomb_bounce = true, wbomb_drop = true, wbomb_splash = true,
}
function M.enemy_fx(name)
    local base = name:match("^(.-)@") or name
    if not (base:sub(1, 3) == "en_" or M.ENEMY_SOUNDS[base]) then return 1.0 end
    local MN = _G.MENU
    return (MN and MN.enemies_volume and MN.enemies_volume()) or 1.0
end

-- Every other sound - not Mario's voice (M.mario_fx), not an enemy's (M.enemy_fx): coins, boxes, doors, platforms,
-- pipes, stars, the menus - as loud as the player's GENERAL SOUNDS setting (Mario settings, msettings.lua; kept by
-- menu.lua as `general_volume`; 0 = not heard): the factor for sound `name` ("file@tag" for a held one), 1 for Mario's
-- and the enemies' ("also mario settings also needs general sounds slider like coins and hat boxes slider", 2026-11-03)
function M.general_fx(name)
    local base = name:match("^(.-)@") or name
    if base:sub(1, 6) == "mario_" or M.MARIO_VOICE[base] or base:sub(1, 3) == "en_" or M.ENEMY_SOUNDS[base] then return 1.0 end
    local MN = _G.MENU
    return (MN and MN.general_volume and MN.general_volume()) or 1.0
end

-- Play the sound `name` (<mod>/sfx/<name>.wav) once, at loudness `v` (0..1, default 1: a sound far off is quieter).
-- `keep`: its player kept for it to its end, however short (a long one's always is) - the next sounds go to the others:
-- the four were all walking Bob-ombs and the chain chomp's hops in Bob-omb Battlefield, and the race's flag pole's
-- twang and the 1-up as it is taken cut each other off ("metal pole and 1up sound counteract eachother they should play
-- at the same time though", 2026-10-27)
function M.play(name, v, keep)
    local k = M.mario_fx(name) * M.enemy_fx(name) * M.general_fx(name)
    if k <= 0.01 then return false end                  -- (turned all the way down: Mario's voice, the enemies', the rest)
    v = (v or 1.0) * k
    local path = DIR .. name .. ".wav"
    -- (a remix of the sound, with REMIX MUSIC on, where there is one - sfx_remix/<name>.wav: the star's fanfare, "Super
    -- Mario 64 - Course Clear (MIDI Remix)", 2026-11-01)
    do
        local MU = package.loaded["music"]
        if MU and MU.remix then
            local rp = lib.MOD_DIR .. "sfx_remix\\" .. name .. ".wav"
            local rf = io.open(rp, "rb")
            if rf then rf:close(); path = rp end
        end
    end
    local f = io.open(path, "rb")
    if not f then
        if not missing[name] then missing[name] = true; log("sfx: no file for %s in %s", name, DIR) end
        return false
    end
    f:close()
    local s = ensure()
    if not s then return false end
    -- (the next player not still busy with a long sound; all of them busy, the next anyway)
    local now = os.clock()
    local p = nil
    for _ = 1, #s.players do
        local q = s.players[s.next]
        s.next = s.next % #s.players + 1
        if not (q.busy_till and now < q.busy_till) then p = q; break end
    end
    if not p then p = s.players[s.next]; s.next = s.next % #s.players + 1 end
    local len = length_of(path)
    p.busy_till = (len > LONG or keep) and (now + len) or nil
    pcall(function() p.comp:SetVolumeMultiplier(M.volume * (v or 1.0)) end)
    local ok, opened = pcall(function() return p.mp:OpenFile(path) end)    -- (opening it starts it)
    if not (ok and opened) then log("sfx: could not open %s (%s)", path, tostring(opened)) end
    p.name = name
    return ok and opened
end

-- A sound started with M.play stopped before its end (the blue coin switch's ticking once its coins are all taken).
function M.stop(name)
    local s = st
    if not s then return end
    for _, p in ipairs(s.players) do
        if p.name == name then
            pcall(function() p.mp:Close() end)
            p.name, p.busy_till = nil, nil
        end
    end
end

-- ------------------------------------------------------------ held sounds
-- Sounds that go on for as long as something keeps them going, as Mario 64 asks for them again every frame (a
-- lift's hum, a seesaw's creak): M.hold(name, v) every tick at loudness v (0..1), then M.update_held(dt) once a
-- tick. Each has a looping player of its own (<mod>/sfx/<name>.wav, made to loop without a seam); one no longer
-- held fades out and stops. Its players belong to the map they were made in and are never touched after it.
local held = {}                     -- name -> { v, want, mp, comp, on, world }
local HELD_FADE = 8.0               -- per second
-- A held sound's own loudness and speed, set by what makes it and kept till changed: name -> { v = 0..1, rate = 1 its
-- own }. A name "file@tag" is the sound file's own player for one maker of it - a Heave-Ho's whirr each its own, slowing
-- and fading as it runs down ("when he starts running out of energy, the audio emitting from him should slow to a stop",
-- 2026-10-28).
M.tune = {}

function M.hold(name, v)
    local h = held[name]
    if not h then h = { v = 0.0, want = 0.0 }; held[name] = h end
    local tu = M.tune[name]
    if tu then v = (v or 0.0) * (tu.v or 1.0) end
    v = (v or 0.0) * M.enemy_fx(name) * M.general_fx(name)     -- (an enemy's hum: ENEMIES VOLUME; any other: GENERAL SOUNDS)
    if v > h.want then h.want = v end
end

local function held_player(s, h, name)
    local MP = StaticFindObject("/Script/MediaAssets.MediaPlayer")
    local MSC = StaticFindObject("/Script/MediaAssets.MediaSoundComponent")
    if not (valid(MP) and valid(MSC) and valid(s.actor)) then return false end
    local mp = StaticConstructObject(MP, s.actor, FName("SM64HeldSound_" .. name:gsub("[^%w_]", "_")))
    local comp = s.actor:AddComponentByClass(MSC, false, {
        Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = 0.0, Y = 0.0, Z = 0.0 },
        Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }, false)
    if not (valid(mp) and valid(comp)) then return false end
    pcall(function() comp:SetMediaPlayer(mp) end)
    pcall(function() comp.MediaPlayer = mp end)                 -- (keeps the player from the engine's clean-up)
    pcall(function() comp:SetVolumeMultiplier(0.0) end)
    h.mp, h.comp, h.on, h.world = mp, comp, false, s.world
    return true
end

function M.update_held(dt)
    M.held_at = os.clock()             -- (intro.lua: run by it when nothing else has this frame)
    local step = math.min(1.0, HELD_FADE * (dt or 0.016))
    local s = nil
    for name, h in pairs(held) do
        local want = h.want
        h.want = 0.0
        h.v = h.v + (want - h.v) * step
        if want > 0.0 or h.on then
            s = s or ensure()
            if not s then return end
            -- (another map: its players went with the old one, untouched)
            if h.world ~= s.world then h.mp, h.comp, h.on, h.world = nil, nil, false, nil end
            if want > 0.0 and not h.on then
                local path = DIR .. (name:match("^(.-)@") or name) .. ".wav"
                local f = io.open(path, "rb")
                if not f then
                    if not missing[name] then missing[name] = true; log("sfx: no file for %s in %s", name, DIR) end
                elseif h.mp or held_player(s, h, name) then
                    f:close()
                    local ok, opened = pcall(function()
                        h.mp:SetLooping(true)
                        return h.mp:OpenFile(path)
                    end)
                    h.on = ok and opened or false
                    h.rate = 1.0
                    if not h.on then log("sfx: could not open %s (%s)", path, tostring(opened)) end
                end
            end
            if h.on then
                if want <= 0.0 and h.v < 0.01 then
                    pcall(function() h.mp:Close() end)
                    h.on, h.v = false, 0.0
                else
                    pcall(function() h.comp:SetVolumeMultiplier(M.volume * h.v) end)
                    -- (its speed, M.tune's: the media player's own rate)
                    local tu = M.tune[name]
                    local rate = tu and tu.rate or 1.0
                    if math.abs(rate - (h.rate or 1.0)) > 0.02 then
                        if pcall(function() h.mp:SetRate(rate) end) then h.rate = rate end
                    end
                end
            end
        end
    end
end

-- Every held sound stopped at once (the game paused, the scene gone).
function M.quiet_held()
    local s = nil
    for _, h in pairs(held) do
        h.want, h.v = 0.0, 0.0
        if h.on then
            s = s or ensure()
            if s and h.world == s.world then pcall(function() h.mp:Close() end) end
            h.on = false
        end
    end
end

-- The map went (main.lua FORGET_ON_MAP): the sounds' players and the held sounds' dropped without touching them.
-- (a new map can sit where the old one was, its address the same, and its players were taken for this map's: the
-- intro's first sound reached for a freed one after STORROR's menu reloaded the map - "crash", 2026-11-03)
function M.forget()
    st = nil
    M.forget_held()
end

-- The map went: forget the held sounds' players without touching them.
function M.forget_held()
    for _, h in pairs(held) do h.mp, h.comp, h.on, h.world, h.v, h.want = nil, nil, false, nil, 0.0, 0.0 end
end

-- Get the players ready ahead of time, so the first sound is not late.
function M.prepare() return ensure() ~= nil end

return M
