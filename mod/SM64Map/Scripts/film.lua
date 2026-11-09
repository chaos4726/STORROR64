-- SM64Map: STORROR's own start film, and its music.
--
-- STORROR plays a film behind its start screen. Here the same film plays behind Mario's head on the title
-- screen and goes on, without a break, inside the frame of the file select; its soundtrack is the music
-- of both. It is played straight from the game's own Movies folder: nothing is copied.
--
-- A film needs a player and a "media texture" for the player to draw into. The player is made here; the
-- texture has to be one the game already has loaded, because one made from a script never gets a
-- surface to draw on. The engine's spare one (CommonUI's default) is borrowed for it.
local lib = require("lib")
local log = lib.log

local F = {}

local FILES = { "spp_start_cinematic.mp4", "spp_start_cinematic_sd.mp4" }
local TEXTURE = "/CommonUI/DefaultMediaTexture.DefaultMediaTexture"
local VOLUME = 0.8
-- The film opens with the word STORROR across half its width for two seconds, and closes with it for four.
-- Whoever shows the film keeps the word out of sight for those spells, which run together when the film
-- goes round (see F.growth).
F.LENGTH = 94.59                    -- seconds, start to finish
F.WORD_GONE, F.WORD_BACK = 2.4, 89.2        -- the word is up before the first and after the second
F.ZOOM = 1.1                        -- seconds a screen takes to open the film up again, or to close it down

local film, serial = nil, 0         -- the player and how it is getting on
local speaker = nil                 -- the actor its sound comes from
local tended = 0.0

local function valid(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

local function movies_dir()
    local root = lib.MOD_DIR:gsub("\\", "/"):gsub("/Binaries/.*$", "")
    return root .. "/Content/Movies/"
end

-- Make sure the film is open, to start playing `delay` seconds from now (at once if it is playing already:
-- then it simply carries on). Returns true if there is a film to show.
function F.start(world, delay)
    local ok, res = pcall(function()
        local mt = lib.try_load(TEXTURE)
        local MP = StaticFindObject("/Script/MediaAssets.MediaPlayer")
        if not (mt and MP and MP:IsValid()) then return false end
        if film and film.path and valid(film.mp) then return true end
        if not (film and valid(film.mp)) then
            serial = serial + 1
            local outer = StaticFindObject("/Engine/Transient")
            if not (outer and outer:IsValid()) then outer = world end
            film = { mp = StaticConstructObject(MP, outer, FName("SM64Film" .. serial)) }
        end
        local mp = film.mp
        if not valid(mp) then return false end
        pcall(function() mp.PlayOnOpen = false end)         -- it waits for its moment (see F.tick)
        pcall(function() mt.AutoClear = true; mt.ClearColor = { R = 0.0, G = 0.0, B = 0.0, A = 1.0 } end)
        mt:SetMediaPlayer(mp)
        -- SetMediaPlayer only makes a note of the player; it does not keep it. Left at that, the engine
        -- throws the player away at its first clean-up (about a minute in) and the next call on it brings
        -- the game down. Written into the texture's own MediaPlayer property, it is kept.
        mt.MediaPlayer = mp
        film.started, film.path, film.play_t, film.err = false, nil, nil, nil
        film.due = os.clock() + (delay or 0.0)
        for _, name in ipairs(FILES) do
            local path = movies_dir() .. name
            local f = io.open(path, "rb")
            if f then
                f:close()
                if mp:OpenFile(path) then
                    film.path = path
                    log("film: playing %s", name)
                    break
                end
            end
        end
        return film.path ~= nil
    end)
    if not ok then log("film: none (%s)", tostring(res)) end
    return ok and res == true
end

-- A material that shows the film, for a mesh section in this world (a new one each time it is asked for).
function F.material(world)
    local ok, m = pcall(function()
        local mt = lib.try_load(TEXTURE)
        local spec = lib.init_materials(world).opaque
        local parent = lib.try_load(spec.path)
        local KML = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
        serial = serial + 1
        local mid = KML:CreateDynamicMaterialInstance(world, parent, FName("SM64FilmMat" .. serial .. "_" .. math.floor(os.clock() * 1000)), 0)
        mid:SetTextureParameterValue(FName(spec.param), mt)
        return mid
    end)
    if ok and m then return m end
    if not ok then log("film: no material (%s)", tostring(m)) end
    return nil
end

-- Where the film's sound comes from: an actor of its own, so the music carries on from one screen to the
-- next while everything else of the screen is taken down. Each screen puts it straight ahead of its camera.
function F.speaker(world, loc)
    if not (film and valid(film.mp)) then return end
    local ok, err = pcall(function()
        local addr = world:GetAddress()
        if speaker and speaker.world == addr and valid(speaker.actor) then
            speaker.actor:K2_TeleportTo(loc, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
            return
        end
        local a = lib.spawn_actor(world, loc, 0.0)
        if not a then return end
        lib.keep[a:GetAddress()] = true                 -- (not to be cleared away with a scene)
        local MSC = StaticFindObject("/Script/MediaAssets.MediaSoundComponent")
        local comp = a:AddComponentByClass(MSC, false, {
            Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = 0.0, Y = 0.0, Z = 0.0 },
            Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }, false)
        comp:SetMediaPlayer(film.mp)
        comp.MediaPlayer = film.mp                      -- (kept here too, for the same reason as above)
        comp:SetVolumeMultiplier(VOLUME)
        speaker = { actor = a, world = addr, comp = comp }
    end)
    if not ok then log("film: no sound (%s)", tostring(err)) end
end

-- Every tick while a screen shows the film (more than once a tick does no harm). Four times a second it
-- sets the film going when its moment has come, starts it again from the top if it has stopped (left to
-- itself it ends on a black screen), and keeps count of where in the film the player is.
function F.tick()
    if not (film and film.path) then return end
    local now = os.clock()
    if now - tended < 0.25 then return end
    tended = now
    pcall(function()
        local mp = film.mp
        if not mp:IsValid() then film.path = nil; return end
        if not film.started then
            if now >= film.due and mp:IsReady() then
                mp:SetLooping(true)
                mp:Play()
                film.started, film.play_t = true, now
            end
        elseif not mp:IsPlaying() and not mp:IsPreparing() and not mp:IsBuffering() then
            if mp:IsReady() then
                mp:Rewind()
                mp:Play()
                film.play_t = now
            else
                mp:OpenFile(film.path)              -- the player let go of the file: open it again
                film.started, film.play_t = false, nil
            end
        elseif mp:IsPlaying() then
            -- The player says where in the film it is (to the nearest picture). The mod's own count of
            -- the time is nudged to agree with it, so anything timed to the film (the head's nodding)
            -- stays on the beat however long the film took to get going or to go round.
            local ticks = mp:GetTime().Ticks
            if type(ticks) == "number" then
                local err = (ticks / 1e7 + 0.017) - ((now - film.play_t) % F.LENGTH)
                if err > F.LENGTH / 2.0 then err = err - F.LENGTH elseif err < -F.LENGTH / 2.0 then err = err + F.LENGTH end
                film.play_t = film.play_t - ((math.abs(err) > 0.25) and err or err * 0.3)
                film.err = err
            end
        end
    end)
end

-- Seconds into the film, or nil if it is not playing. It plays in real time, so the clock is enough.
function F.time()
    if not (film and film.started and film.play_t) then return nil end
    return (os.clock() - film.play_t) % F.LENGTH
end

-- How much of the film may be seen: 0 while the word STORROR is on it, 1 the rest of the time, eased
-- over F.ZOOM seconds at each end. (0 too while it has yet to start.)
function F.growth()
    local at = F.time()
    if not at then return 0.0 end
    local g
    if at < F.WORD_GONE or at >= F.WORD_BACK then g = 0.0
    elseif at < F.WORD_GONE + F.ZOOM then g = (at - F.WORD_GONE) / F.ZOOM
    elseif at < F.WORD_BACK - F.ZOOM then g = 1.0
    else g = (F.WORD_BACK - at) / F.ZOOM end
    return g * g * (3.0 - 2.0 * g)
end

-- Stop the film and its music (a level is starting).
function F.stop()
    if film and film.mp then pcall(function() if film.mp:IsValid() then film.mp:Close() end end) end
    if film then film.path, film.started, film.play_t = nil, false, nil end
    if speaker then
        pcall(function()
            -- (its actor belongs to a map: after a change of map it has gone with it and is not touched)
            if speaker.world == lib.world():GetAddress() and speaker.actor:IsValid() then
                lib.keep[speaker.actor:GetAddress()] = nil
                speaker.actor:K2_DestroyActor()
            end
        end)
        speaker = nil
    end
end

-- The film's sound turned down to `k` (0..1) of its usual level, for fading it out.
function F.set_volume(k)
    if speaker and speaker.comp then
        pcall(function() if speaker.comp:IsValid() then speaker.comp:SetVolumeMultiplier(VOLUME * k) end end)
    end
end

function F.state() return film end     -- (tests)

-- The map went (main.lua FORGET_ON_MAP): its player and its speaker dropped without touching them (the speaker was the
-- gone map's, and the player, kept by the speaker's sound, may have gone with it).
-- (a new map can sit where the old one was, its address the same, and its players were taken for this map's: the
-- intro's first sound reached for a freed one after STORROR's menu reloaded the map - "crash", 2026-11-03)
function F.forget() film, speaker = nil, nil end

return F
