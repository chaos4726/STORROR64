-- SM64Map "now playing": while STORROR's pause menu is up, a line at the bottom of the screen names the music that was
-- playing when the game was paused - the level's tune, or the one over it (a Piranha Plant's lullaby, the merry-go-
-- round) when that is the louder - and who made it: "in the pause menu I want a music prober. so I can see exactly what
-- player during a level or when standing next to a paranha plant", 2026-11-01. Ticked from msettings.lua.
local lib = require("lib")
local log = lib.log
local M = {}

-- the remix files (music_remix/<key>.mp3) and who made them - as MUSIC_CREDITS.md, matched to the files by length
M.CREDIT = {
    event_boss = { "Stage Boss - Super Mario 64 Remix", "SaMiX" },
    ["event_boss@bbh"] = { "Final Big Boo (Orchestral Remix)", "ReOST" },
    ["event_boss@lll"] = { "Big Bully (Rock Remix)", "ReOST" },
    ["event_boss@sl"] = { "Chill Bully (Metal Remix)", "ReOST" },
    ["event_boss@ssl"] = { "Eyerock (Metal Remix)", "ReOST" },
    ["event_boss@thi_3"] = { "Wiggler (Electronic Remix)", "ReOST" },
    ["event_boss@wf"] = { "Whomp King (Orchestral Remix)", "ReOST" },
    event_credits = { "Super Mario 64 - Staff Roll [Remix]", "Qumu" },
    event_endless_stairs = { "Super Mario 64 | Endless Stairs (Piano Cover)", "CrazyGroupTrio" },
    event_merry_go_round = { "Super Mario 64 Remastered - Merry Go Round", "DeathlyHand" },
    event_metal_cap = { "Metallic Mario (New Remix) | Super Smash Bros. Ultimate [FANMADE]", "0retro0" },
    event_piranha_plant = { "Super Mario 64 - Piranha Plant's Lullaby (cover)", "MerryberryMusic" },
    event_powerup = { "SM64 - Powerful Mario (Joshua Milo Remake)", "Joshua Milo" },
    intro_new_file = { "Super Mario 64 - Opening (Orchestral remake/remix)", "Diego Leal E." },
    level_boss_koopa = { "Super Mario 64 - Koopa's Theme Remix", "AJ DiSpirito" },
    ["level_boss_koopa@bowser_2"] = { "Bowser's Theme (AKA Koopa's Theme) Remix | Super Mario 64", "Kunning Fox" },
    level_boss_koopa_final = { "Super Mario 64 - Ultimate Bowser Epic Orchestral Remix", "TLB Orchestration" },
    level_grass = { "SM64 - Bob-Omb Battlefield (Joshua Milo Remix) | FUNK", "Joshua Milo" },
    ["level_grass@thi"] = { "Slider (Tiny-Huge Island) - Super Mario 64", "SiIvaGunner" },
    ["level_grass@ttm"] = { "Tall, Tall Mountain (Bluegrass Remix)", "ReOST" },
    ["level_grass@wf"] = { "Whomp's Fortress (Orchestral Remix)", "ReOST" },
    level_hot = { "Shifting Sand Land Remix - (Lethal Lava Land)", "Xilore Inaba" },
    ["level_hot@ssl"] = { "Super Mario 64 - Sand Shifting Land [HQ Remix] by Baf", "Super 0'Brothers" },
    level_inside_castle = { "Super Mario 64 - Inside the Castle Walls Remix", "AJ DiSpirito" },
    level_koopa_road = { "The Road To Koopa - Arrangement ~ Super Mario 64", "Nanashima" },
    ["level_koopa_road@bitfs"] = { "Bowser in the Fire Sea (Symphonic Metal Remix)", "ReOST" },
    ["level_koopa_road@bits"] = { "Ultimate Bowser (Bleeding Ink Remix - Bowser In the Sky)", "Hyperactive" },
    -- (the Bowser run's Sky: "also use the unused bowser final song", 2026-11-03 - its file named no artist)
    ["level_koopa_road@run_sky"] = { "Ultimate Final Bowser (Orchestral Metal Hybrid Halloween Remix)", "Super Mario 64" },
    level_slide = { "Super Mario 64 - Tick Tock Clock / Slider Race [HQ Remix] by Baf", "Super 0'Brothers" },
    ["level_slide@ccm"] = { "Cool, Cool Slide (Orchestral Remix)", "ReOST" },
    ["level_slide@pss"] = { "Super Mario 64 music - Peach's Slide (frosty remake)", "Nate" },
    ["level_slide@race"] = { "Cosmic Clones | The Super Mario Galaxy REMIX", "Eyem" },
    ["level_slide@rr"] = { "Rainbow Ride (Orchestral Remix)", "ReOST" },
    ["level_slide@totwc"] = { "Super Mario 64 - Powerful Mario (Wing Cap / Vanish Cap) [Remix]", "Qumu" },
    ["level_slide@vcutm"] = { "Super Mario 64 - Powerful Mario (Wing Cap / Vanish Cap) [Remix]", "Qumu" },
    ["level_slide@ttm"] = { "Tall, Tall Slide (Bluegrass Remix)", "ReOST" },
    ["level_slide@wmotr"] = { "Wing Mario (Orchestral Remix)", "ReOST" },
    level_snow = { "Super Mario 64 - Cool Cool Mountain [HQ Remix]", "Super 0'Brothers" },
    ["level_snow@sl"] = { "Super Mario Galaxy 2 64 - Snowman's Land (Fanmade)", "marionose1" },
    level_spooky = { "Big Boo's Haunt - Dark Ambient Remix (Super Mario 64)", "Scott Arc" },
    level_underground = { "Super Mario 64 [Remix] - Hazy Maze Cave (HD Remake)", "BlueJackG Channel" },
    ["level_underground@cotmc"] = { "Cavern of the Metal Cap", "ReOST" },
    ["level_underground@sl_2"] = { "Inside the Igloo (Orchestral Remix)", "ReOST" },
    ["level_underground@thi_3"] = { "Wiggler's Cave (Electronic Remix)", "ReOST" },
    ["level_underground@wdw"] = { "Super Mario 64 - Wet-Dry World Remake", "MJS Remakes" },
    level_water = { "Super Mario 64 HD - Dire, Dire Docks", "Tee Lopes" },
    ["level_water@jrb"] = { "Jolly Roger Bay [Remix] (Super Mario 64)", "Watercrate" },
    ["level_water@sa"] = { "SM64: Last Impact OST - Secret Aquarium (Mario Sunshine - Sky and Sea N64 remix)", "Kaze Emanuar" },
    menu_game_over = { "Super Mario World - Game Over [SM64 Style]", "@random_remixer" },
}

-- Mario 64's own tunes, by name, where no remix plays
M.ORIGINAL = {
    level_grass = "Main Theme", level_inside_castle = "Inside the Castle Walls", level_water = "Dire, Dire Docks",
    level_hot = "Lethal Lava Land", level_snow = "Snow Mountain", level_slide = "Slider", level_spooky = "Haunted House",
    level_underground = "Hazy Maze Cave", level_koopa_road = "Koopa's Road", level_boss_koopa = "Koopa's Theme",
    level_boss_koopa_final = "Ultimate Koopa", menu_star_select = "Star Select", menu_game_over = "Game Over",
    event_boss = "Stage Boss", event_powerup = "Powerful Mario", event_metal_cap = "Metallic Mario",
    event_piranha_plant = "Piranha Plant's Lullaby", event_merry_go_round = "Merry-Go-Round",
    event_endless_stairs = "Endless Stairs", event_cutscene_lakitu = "Lakitu", event_victory = "Ultimate Koopa Clear",
    event_ending = "Ending", event_credits = "Staff Roll", intro_new_file = "Opening",
}

local REMIX_DIR = lib.MOD_DIR .. "music_remix\\"
local EXT = { ".mp3", ".m4a", ".ogg", ".wav" }
local function exists(key)
    for _, e in ipairs(EXT) do
        local f = io.open(REMIX_DIR .. key .. e, "rb")
        if f then f:close(); return true end
    end
    return false
end

-- the remix file a tune plays from here, as music.lua's file_for looks it up: <tune>@<context>, @<scene>, @<scene
-- without _N>, <tune>
local function remix_key(name)
    local base, ctx = name:match("^(.-)@(.+)$")
    base = base or name
    local G = package.loaded["game"]
    local sc = G and G.name
    local tries = {}
    if ctx then tries[#tries + 1] = base .. "@" .. ctx end
    if sc then
        tries[#tries + 1] = base .. "@" .. sc
        local s2 = sc:gsub("_%d+$", "")
        if s2 ~= sc then tries[#tries + 1] = base .. "@" .. s2 end
    end
    tries[#tries + 1] = base
    for _, k in ipairs(tries) do if exists(k) then return k, base end end
    return nil, base
end

-- "Song - Artist" for a tune name as it plays now
function M.describe(name)
    if not name then return nil end
    if name == "ambience" then
        -- (no tune - the castle grounds: the outdoors' sounds, the user's remix of them with REMIX MUSIC on)
        local MU = package.loaded["music"]
        if MU and MU.remix then return "Flowers (Nature Sounds)", "Dennis Korn Music" end
        return "Super Mario 64 - the castle grounds' birds and water", "original"
    end
    local MU = package.loaded["music"]
    local base = name:match("^(.-)@") or name
    if MU and MU.remix then
        local key
        key, base = remix_key(name)
        local c = key and M.CREDIT[key]
        if c then return c[1], c[2] end
    end
    return "Super Mario 64 - " .. (M.ORIGINAL[base] or base), "original"
end

-- what is playing: the level's tune, or the one over it when that is the louder
function M.current()
    local MU = package.loaded["music"]
    if not MU then return nil end
    local main, over, over_vol = MU.current, nil, 0.0
    if MU.now_playing then
        local ok, np = pcall(MU.now_playing)
        if ok and np then main, over, over_vol = np.main or main, np.over, np.over_vol or 0.0 end
    end
    if over and over_vol >= 0.5 then return over end
    if main then return main end
    -- (no tune: the outdoors' sounds, where they play - music.lua's ambience; before a restart has given music.lua
    -- now_playing's ambience, the castle grounds by name)
    local amb = nil
    if MU.now_playing then pcall(function() amb = MU.now_playing().ambience end) end
    if amb == nil then
        local G = package.loaded["game"]
        if G and (G.name == "grounds") then amb = "castle_grounds" end
    end
    if amb then return "ambience" end
    return nil
end

local ui = nil
local function remove()
    if ui then pcall(function() if ui.widget:IsValid() then ui.widget:RemoveFromParent() end end) end
    ui = nil
end

local function build(song, artist)
    local pc = lib.controller()
    if not pc then return nil end
    local function cls(p) return StaticFindObject(p) end
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("SM64NowPlaying"))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("SM64NowPlayingTree"))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SM64NowPlayingCanvas"))
    tree.RootWidget = canvas
    local row = StaticConstructObject(cls("/Script/UMG.HorizontalBox"), canvas, FName("SM64NowPlayingRow"))
    local slot = canvas:AddChildToCanvas(row)
    slot:SetAnchors({ Minimum = { X = 0.0, Y = 1.0 }, Maximum = { X = 0.0, Y = 1.0 } })
    slot:SetAlignment({ X = 0.0, Y = 1.0 })
    -- (low, under STORROR's own line of the PC's graphics card and build at the bottom left: it lay over it - "music
    -- and pc stats layered on top eachother, move the music down a bit", 2026-11-01)
    slot:SetPosition({ X = 48.0, Y = -2.0 })
    slot:SetAutoSize(true)
    local function text(name, s, col)
        local t = StaticConstructObject(cls("/Script/UMG.TextBlock"), row, FName(name))
        pcall(function() t:SetText(FText(s)) end)
        pcall(function() t:SetColorAndOpacity({ SpecifiedColor = col, ColorUseRule = 0 }) end)
        pcall(function() t:SetShadowOffset({ X = 2.0, Y = 2.0 }) end)
        pcall(function() t:SetShadowColorAndOpacity({ R = 0.0, G = 0.0, B = 0.0, A = 0.8 }) end)
        row:AddChildToHorizontalBox(t)
        return t
    end
    text("SM64NowPlayingHead", "NOW PLAYING   ", { R = 0.75, G = 0.75, B = 0.75, A = 1.0 })
    local ts = text("SM64NowPlayingSong", song, { R = 1.0, G = 1.0, B = 1.0, A = 1.0 })
    local ta = text("SM64NowPlayingArtist", "   " .. artist, { R = 1.0, G = 0.85, B = 0.1, A = 1.0 })
    w:AddToViewport(30000)
    return { widget = w, song = ts, artist = ta, key = song .. "|" .. artist }
end

-- every tick (msettings.lua): shown while the pause menu is up, its words kept to what plays
function M.tick()
    local P = package.loaded["pause"]
    local up = false
    pcall(function() up = (P.tab() ~= nil) or P.open == true end)
    if not up then remove(); return end
    local name = M.current()
    local song, artist = M.describe(name)
    if not song then remove(); return end
    local key = song .. "|" .. artist
    if ui and not (ui.widget:IsValid() and ui.widget:IsInViewport()) then ui = nil end
    if ui and ui.key == key then return end
    remove()
    local ok, r = pcall(build, song, artist)
    if ok then ui = r else log("now playing: %s", tostring(r)) end
end

return M
