-- SM64Map music credits: the castle grounds' first sign (the one by the start, Mario 64's DIALOG_167) shows every
-- remix the mod plays and who made it, all in one window - "on the first sign in the game I want you to add all the
-- music here in one window", 2026-11-01. A see-through black box as Mario 64's messages have, the list in two columns
-- scaled to fit it; A or B shuts it. The athlete is held while it is up, as for any sign (dialog.lua).
local lib = require("lib")
local pad = require("pad")
local log = lib.log
local M = { active = false }

-- { place, song, artist } - as the user's list, MUSIC_CREDITS.md; a heading where place is a string alone
M.LIST = {
    "MENUS AND CUTSCENES",
    { "Opening", "Opening (Orchestral remake/remix)", "Diego Leal E." },
    { "Pause menu", "File Select (Anthony Greninger Cover Remix)", "Anthonys Melodies" },
    { "Star fanfare", "Course Clear (MIDI Remix)", "Flaming Leo Music" },
    { "Game over", "Super Mario World - Game Over [SM64 Style]", "@random_remixer" },
    { "Credits", "Staff Roll [Remix]", "Qumu" },
    "CASTLE",
    { "Inside the castle", "Inside the Castle Walls Remix", "AJ DiSpirito" },
    { "Endless Stairs", "Endless Stairs (Piano Cover)", "CrazyGroupTrio" },
    { "Outside", "Flowers (Nature Sounds)", "Dennis Korn Music" },
    "COURSES",
    { "Bob-omb Battlefield", "Bob-Omb Battlefield (Joshua Milo Remix) | FUNK", "Joshua Milo" },
    { "Whomp's Fortress", "Whomp's Fortress (Orchestral Remix)", "ReOST" },
    { "Jolly Roger Bay", "Jolly Roger Bay [Remix]", "Watercrate" },
    { "Cool, Cool Mountain", "Cool Cool Mountain [HQ Remix]", "Super 0'Brothers" },
    { "Its slide", "Cool, Cool Slide (Orchestral Remix)", "ReOST" },
    { "Big Boo's Haunt", "Big Boo's Haunt - Dark Ambient Remix", "Scott Arc" },
    { "Merry-go-round", "Super Mario 64 Remastered - Merry Go Round", "DeathlyHand" },
    { "Hazy Maze Cave", "Hazy Maze Cave (HD Remake)", "BlueJackG Channel" },
    { "Lethal Lava Land", "Shifting Sand Land Remix - (Lethal Lava Land)", "Xilore Inaba" },
    { "Shifting Sand Land", "Sand Shifting Land [HQ Remix] by Baf", "Super 0'Brothers" },
    { "Dire, Dire Docks", "Super Mario 64 HD - Dire, Dire Docks", "Tee Lopes" },
    { "Snowman's Land", "Super Mario Galaxy 2 64 - Snowman's Land (Fanmade)", "marionose1" },
    { "The igloo", "Inside the Igloo (Orchestral Remix)", "ReOST" },
    { "Wet-Dry World", "Wet-Dry World Remake", "MJS Remakes" },
    { "Tall, Tall Mountain", "Tall, Tall Mountain (Bluegrass Remix)", "ReOST" },
    { "Its slide", "Tall, Tall Slide (Bluegrass Remix)", "ReOST" },
    { "Tiny-Huge Island", "Slider (Tiny-Huge Island)", "SiIvaGunner" },
    { "Wiggler's cave", "Wiggler's Cave (Electronic Remix)", "ReOST" },
    { "Tick Tock Clock", "Tick Tock Clock / Slider Race [HQ Remix] by Baf", "Super 0'Brothers" },
    { "Rainbow Ride", "Rainbow Ride (Orchestral Remix)", "ReOST" },
    "SECRET STAGES",
    { "Peach's Secret Slide", "Peach's Slide (frosty remake)", "Nate" },
    { "Wing Cap / Vanish Cap towers", "Powerful Mario (Wing Cap / Vanish Cap) [Remix]", "Qumu" },
    { "Wing Mario Over the Rainbow", "Wing Mario (Orchestral Remix)", "ReOST" },
    { "Cavern of the Metal Cap", "Cavern of the Metal Cap", "ReOST" },
    { "Secret Aquarium", "Last Impact OST - Secret Aquarium (Sky and Sea N64 remix)", "Kaze Emanuar" },
    "BOWSER",
    { "Bowser in the Dark World", "The Road To Koopa - Arrangement", "Nanashima" },
    { "Bowser in the Fire Sea", "Bowser in the Fire Sea (Symphonic Metal Remix)", "ReOST" },
    { "Bowser in the Sky", "Ultimate Koopa (Orchestra Arrangement)", "YoshiDude12" },
    { "1st Bowser fight", "Koopa's Theme Remix", "AJ DiSpirito" },
    { "2nd Bowser fight", "Bowser's Theme (AKA Koopa's Theme) Remix", "Kunning Fox" },
    { "Final Bowser fight", "Ultimate Bowser Epic Orchestral Remix", "TLB Orchestration" },
    "BOSSES",
    { "King Bob-omb and others", "Stage Boss - Super Mario 64 Remix", "SaMiX" },
    { "Whomp King", "Whomp King (Orchestral Remix)", "ReOST" },
    { "Big Bully", "Big Bully (Rock Remix)", "ReOST" },
    { "Chill Bully", "Chill Bully (Metal Remix)", "ReOST" },
    { "Eyerok", "Eyerock (Metal Remix)", "ReOST" },
    { "Wiggler", "Wiggler (Electronic Remix)", "ReOST" },
    { "Final Big Boo", "Final Big Boo (Orchestral Remix)", "ReOST" },
    "CAPS AND EVENTS",
    { "Wing Cap / Vanish Cap", "Powerful Mario (Joshua Milo Remake)", "Joshua Milo" },
    { "Metal Cap", "Metallic Mario (New Remix) | Smash Ultimate [FANMADE]", "0retro0" },
    { "Piranha Plant", "Piranha Plant's Lullaby (cover)", "MerryberryMusic" },
    { "Race against the ghost", "Cosmic Clones | The Super Mario Galaxy REMIX", "Eyem" },
}

local YELLOW = { R = 1.0, G = 0.85, B = 0.1, A = 1.0 }
local WHITE = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
local GREY = { R = 0.75, G = 0.75, B = 0.75, A = 1.0 }
local LOCK = "SM64Credits"
local st = nil

local function sound(name) local S = package.loaded["sfx"]; if S then pcall(S.play, name) end end

-- the athlete held, as dialog.lua holds him for a message
local function lock(on)
    local pc, pawn = lib.controller(), lib.pawn()
    if not (pc and pawn) then return end
    pcall(function() pc:SetIgnoreMoveInput(on) end)
    pcall(function() if on then pawn:DisableInput(pc) else pawn:EnableInput(pc) end end)
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            local cname = o:GetClass():GetFName():ToString()
            if cname == "ParkourComponent" then
                o:ClearInputQueue()
                o:EnableAllParkourInputs(FName(LOCK), not on)
            elseif cname == "LocomotionComponent" then
                o:EnableLocomotionInputCallback(FName(LOCK), not on)
                o:EnableAdvancedLocomotionInput(FName(LOCK), not on)
            end
        end
    end)
    if on then pcall(function() pawn.CharacterMovement:StopMovementImmediately() end) end
end

local function cls(p) return StaticFindObject(p) end

local serial = 0
local function text(outer, s, color)
    serial = serial + 1
    local t = StaticConstructObject(cls("/Script/UMG.TextBlock"), outer, FName("SM64CreditsText" .. serial))
    pcall(function() t:SetText(FText(s)) end)
    pcall(function() t:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 }) end)
    return t
end

local function build()
    local world, pc = lib.world(), lib.controller()
    if not (world and pc) then return nil end
    serial = serial + 1
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("SM64Credits" .. serial))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("SM64CreditsTree" .. serial))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SM64CreditsCanvas" .. serial))
    tree.RootWidget = canvas
    -- (the box: Mario 64's see-through black, most of the screen)
    local bg = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("SM64CreditsBox" .. serial))
    pcall(function() bg:SetColorAndOpacity({ R = 0.0, G = 0.0, B = 0.0, A = 0.88 }) end)
    local bs = canvas:AddChildToCanvas(bg)
    bs:SetAnchors({ Minimum = { X = 0.06, Y = 0.05 }, Maximum = { X = 0.94, Y = 0.95 } })
    bs:SetOffsets({ Left = 0.0, Top = 0.0, Right = 0.0, Bottom = 0.0 })
    -- (the list, scaled to fit inside it)
    local sb = StaticConstructObject(cls("/Script/UMG.ScaleBox"), canvas, FName("SM64CreditsScale" .. serial))
    pcall(function() sb:SetStretch(2) end)                                   -- (scale to fit)
    local ss = canvas:AddChildToCanvas(sb)
    ss:SetAnchors({ Minimum = { X = 0.08, Y = 0.07 }, Maximum = { X = 0.92, Y = 0.93 } })
    ss:SetOffsets({ Left = 0.0, Top = 0.0, Right = 0.0, Bottom = 0.0 })
    local all = StaticConstructObject(cls("/Script/UMG.VerticalBox"), sb, FName("SM64CreditsAll" .. serial))
    sb:AddChild(all)
    all:AddChildToVerticalBox(text(all, "NEW MUSIC BY", YELLOW))
    all:AddChildToVerticalBox(text(all, " ", WHITE))
    local cols = StaticConstructObject(cls("/Script/UMG.HorizontalBox"), all, FName("SM64CreditsCols" .. serial))
    all:AddChildToVerticalBox(cols)
    -- (two columns: the list split at the heading nearest its middle)
    local n, split = #M.LIST, 1
    for i, e in ipairs(M.LIST) do
        if type(e) == "string" and i <= n // 2 + 4 then split = i end
    end
    local col = nil
    for i, e in ipairs(M.LIST) do
        if i == 1 or i == split then
            col = StaticConstructObject(cls("/Script/UMG.VerticalBox"), cols, FName("SM64CreditsCol" .. serial .. "_" .. i))
            local hs = cols:AddChildToHorizontalBox(col)
            pcall(function() hs:SetPadding({ Left = 0.0, Top = 0.0, Right = 60.0, Bottom = 0.0 }) end)
        end
        if type(e) == "string" then
            if i > 1 and i ~= split then col:AddChildToVerticalBox(text(col, " ", WHITE)) end
            col:AddChildToVerticalBox(text(col, e, YELLOW))
        else
            local row = StaticConstructObject(cls("/Script/UMG.HorizontalBox"), col, FName("SM64CreditsRow" .. serial .. "_" .. i))
            col:AddChildToVerticalBox(row)
            row:AddChildToHorizontalBox(text(row, e[1] .. ":  ", GREY))
            row:AddChildToHorizontalBox(text(row, e[2], WHITE))
            row:AddChildToHorizontalBox(text(row, "  -  " .. e[3], YELLOW))
        end
    end
    -- (and thanks to Render 96: "also on the first sign a thank you to render 96 and its developer for the assets,
    -- textures and 3d models", 2026-11-01)
    all:AddChildToVerticalBox(text(all, " ", WHITE))
    all:AddChildToVerticalBox(text(all, "SPECIAL THANKS", YELLOW))
    do
        local row = StaticConstructObject(cls("/Script/UMG.HorizontalBox"), all, FName("SM64CreditsThanks" .. serial))
        all:AddChildToVerticalBox(row)
        row:AddChildToHorizontalBox(text(row, "Render 96", YELLOW))
        row:AddChildToHorizontalBox(text(row, "  and its developers, for the textures, 3D models and assets", WHITE))
    end
    -- ("also add a thank you to all the music composers for their hard work", 2026-11-01)
    all:AddChildToVerticalBox(text(all, "Every composer and remixer above, thank you for your hard work and your music", WHITE))
    all:AddChildToVerticalBox(text(all, " ", WHITE))
    all:AddChildToVerticalBox(text(all, "A / B  next", GREY))
    w:AddToViewport(30000)                 -- (over the HUD and STORROR's trick text)
    return { widget = w, world = world:GetAddress() }
end

-- The second window: Render 96's team, as the user gave it - "next after the music screen", 2026-11-01. Sections of
-- { name, what they did }, in three columns.
M.R96 = {
    { "CORE TEAM / LEADS", {
        { "DorfDork", "Project lead, coder" },
        { "KiritoDev", "Lead coder (translations, Switch port, Luigi code)" },
        { "PokeHeadroom", "HD Texture Pack lead" },
        { "Roovahlees", "HD Texture Pack lead, VGTP Twitter" },
        { "Fanamel", "Texture research lead, spreadsheet maintainer" } } },
    { "TEXTURE RESEARCH & CONTRIBUTION", {
        { "CharlyCN", "Found matches, WDW skybox source" },
        { "JY (jycompany_)", "Found matches, added textures" },
        { "Deefor", "Found matches" },
        { "Uh-Huh", "Found matches" },
        { "Pik", "Found matches" },
        { "Threeplanet (TPlanet66)", "Added textures" },
        { "TheExpectedknight", "Added textures" },
        { "granvillimus", "Added textures" },
        { "dokotroopi", "Added textures" },
        { "MtH", "Added textures" },
        { "Clamibalism", "Contributor" },
        { "Ayekerik", "Contributor" } } },
    { "ART & PAINTING", {
        { "Nicobros", "Painted artwork" },
        { "YinyangGio1987", "WDW render painting" },
        { "Bradley", "Jolly Roger Bay painting" },
        { "Nugget", "Tiny-Huge Island painting" },
        { "Maz", "Luigi key" },
        { "Maxigamer (MaxiGamerWiiU)", "Fonts & HUD elements" },
        { "P3ST", "Placeholder assets" },
        { "ThaGurlTilly", "Art (banner)" },
        { "fuzzedmarz", "Art (banner)" },
        { "AndratVA", "Art (banner)" },
        { "Tanooki98", "Art (banner)" } } },
    { "WIKI & TEXTURE PRESERVATION", {
        { "Leonard85026417", "Texture matches (Sonic Adventure 2, etc.), VGTP maintainer" },
        { "TechnoCookie", "Texture matches (Tekken, etc.)" },
        { "B_squo", "Texture matches (Mario Kart Wii, etc.)" },
        { "Stevie2049", "Wrote texture pages" },
        { "mrwater79321297", "High Quality SM64 Render Collection" },
        { "Fluvian (64History)", "Contributor" } } },
    { "CODE", {
        { "fgsfds", "Coder" },
        { "abandon.ware", "Coder" },
        { "AndresL64", "Coder" },
        { "AranAxuXB", "Coder" } } },
    { "TECHNICAL / OTHER", {
        { "GhostlyDark", "Technical oversight" },
        { "Dario (DarioSamo)", "Ray Tracing fork (separate project, not official Render96)" } } },
}
local R96_COLUMNS = { { 1, 2 }, { 3, 5 }, { 4, 6 } }     -- (which sections in which column)

local function build_r96()
    local world, pc = lib.world(), lib.controller()
    if not (world and pc) then return nil end
    serial = serial + 1
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("SM64CreditsR96" .. serial))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("SM64CreditsR96Tree" .. serial))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("SM64CreditsR96Canvas" .. serial))
    tree.RootWidget = canvas
    local bg = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("SM64CreditsR96Box" .. serial))
    pcall(function() bg:SetColorAndOpacity({ R = 0.0, G = 0.0, B = 0.0, A = 0.88 }) end)
    local bs = canvas:AddChildToCanvas(bg)
    bs:SetAnchors({ Minimum = { X = 0.06, Y = 0.05 }, Maximum = { X = 0.94, Y = 0.95 } })
    bs:SetOffsets({ Left = 0.0, Top = 0.0, Right = 0.0, Bottom = 0.0 })
    local sb = StaticConstructObject(cls("/Script/UMG.ScaleBox"), canvas, FName("SM64CreditsR96Scale" .. serial))
    pcall(function() sb:SetStretch(2) end)
    local ss = canvas:AddChildToCanvas(sb)
    ss:SetAnchors({ Minimum = { X = 0.08, Y = 0.07 }, Maximum = { X = 0.92, Y = 0.93 } })
    ss:SetOffsets({ Left = 0.0, Top = 0.0, Right = 0.0, Bottom = 0.0 })
    local all = StaticConstructObject(cls("/Script/UMG.VerticalBox"), sb, FName("SM64CreditsR96All" .. serial))
    sb:AddChild(all)
    all:AddChildToVerticalBox(text(all, "RENDER 96 - TEXTURES, 3D MODELS AND ASSETS", YELLOW))
    all:AddChildToVerticalBox(text(all, "Thank you to everyone who made it", WHITE))
    all:AddChildToVerticalBox(text(all, " ", WHITE))
    local cols = StaticConstructObject(cls("/Script/UMG.HorizontalBox"), all, FName("SM64CreditsR96Cols" .. serial))
    all:AddChildToVerticalBox(cols)
    for ci, secs in ipairs(R96_COLUMNS) do
        local col = StaticConstructObject(cls("/Script/UMG.VerticalBox"), cols, FName("SM64CreditsR96Col" .. serial .. "_" .. ci))
        local hs = cols:AddChildToHorizontalBox(col)
        pcall(function() hs:SetPadding({ Left = 0.0, Top = 0.0, Right = 60.0, Bottom = 0.0 }) end)
        for k, si in ipairs(secs) do
            local sec = M.R96[si]
            if k > 1 then col:AddChildToVerticalBox(text(col, " ", WHITE)) end
            col:AddChildToVerticalBox(text(col, sec[1], YELLOW))
            for j, e in ipairs(sec[2]) do
                local row = StaticConstructObject(cls("/Script/UMG.HorizontalBox"), col,
                    FName("SM64CreditsR96Row" .. serial .. "_" .. si .. "_" .. j))
                col:AddChildToVerticalBox(row)
                row:AddChildToHorizontalBox(text(row, e[1], WHITE))
                row:AddChildToHorizontalBox(text(row, "  -  " .. e[2], GREY))
            end
        end
    end
    all:AddChildToVerticalBox(text(all, " ", WHITE))
    all:AddChildToVerticalBox(text(all, "A / B  close", GREY))
    w:AddToViewport(30000)
    return { widget = w, world = world:GetAddress() }
end

function M.open(done, page)
    if M.active then return true end
    local ok, ui = pcall((page == 2) and build_r96 or build)
    if not (ok and ui) then log("music credits: could not open (%s)", tostring(ui)); return false end
    st = { ui = ui, t = 0.0, done = done, page = page or 1 }
    M.active = true
    lock(true)
    pad.reset()
    sound("menu_message_appear")
    log("music credits: open (%d lines)", #M.LIST)
    return true
end

function M.close()
    if not st then M.active = false; return end
    pcall(function() if st.ui.widget:IsValid() then st.ui.widget:RemoveFromParent() end end)
    local done = st.done
    st = nil
    M.active = false
    lock(false)
    sound("menu_message_disappear")
    if done then pcall(done) end
end

function M.tick(dt)
    if not st then M.active = false; return end
    local world = lib.world()
    if not world or world:GetAddress() ~= st.ui.world then st = nil; M.active = false; return end
    st.t = st.t + (dt or 0.016)
    if st.t < 0.4 then pad.reset(); return end
    if pad.pressed("ok") or pad.pressed("back") then
        if st.page == 1 then
            -- (on to the second window: Render 96's team)
            local ok, ui = pcall(build_r96)
            if ok and ui then
                pcall(function() if st.ui.widget:IsValid() then st.ui.widget:RemoveFromParent() end end)
                st.ui, st.page, st.t = ui, 2, 0.0
                pad.reset()
                sound("menu_message_next_page")
                return
            end
            log("music credits: Render 96's window: %s", tostring(ui))
        end
        M.close()
    end
end

return M
