-- Mario 64's caps on STORROR's athlete (interaction.c interact_cap): out of a ! box once its cap switch is pressed.
--   vanish  20 s: through the vanish-cap walls (the cages of VCUTM, WDW's town, SL's igloo, DDD and BBH), enemies can't
--           hurt him; he is drawn as a see-through ghost
--   metal   40 s: enemies, fire and the like can't hurt him, and in water he does not swim: he sinks (slowly) and
--           walks the bottom, losing no breath; drawn as a grey statue
--   wing    60 s: (no flying for the athlete) holding A in the air he glides, falling slowly
-- Each with its tune (SEQ_EVENT_POWERUP, SEQ_EVENT_METAL_CAP) over the level's, the star sound and "Here we go!".
-- The metal look is a copy of his meshes posed by his own (as mirror.lua's reflection) in the engine's grey grid
-- material - a statue - drawn while his own are hidden; the vanish look is him flickering every other frame, half
-- there. His own materials are never touched (no material the mod has renders on his skinned meshes as wanted: the
-- glTF ones multiply in the MetaHuman's vertex-colour masks, green; others fall back to the grey grid). Falls still
-- hurt. (Caps gave three coins, 2026-10-15.)
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET
-- Caps together, as Mario 64's are (interact_cap: m->flags |= capFlag; one timer, the longer of the two): wing and
-- metal, metal and vanish, all three - "you cant combo hat powers, flying cap invis and metal cap together",
-- 2026-10-23. M.kinds: the caps on; M.kind: the last taken (nil: none on).
local M = { kind = nil, kinds = {}, left = 0.0 }

-- (the metal cap 40 s, twice Mario 64's 600 frames: "its too short a duration", 2026-10-18 - down to Jolly Roger Bay's
-- jet stream from its box and in to the star took longer than that)
local TIME = { vanish = 20.0, metal = 40.0, wing = 60.0 }
local TUNE = { vanish = "event_powerup", metal = "event_metal_cap", wing = "event_powerup" }
local IDENT = { Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = 0.0, Y = 0.0, Z = 0.0 },
                Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }
local H = {}            -- set by game.lua: music_back(), vanish_walls(on), busy(), level(), under_water(),
                        -- above_floor(), parkour_reset(), swimming(), stop_swim()
local look = nil        -- the metal statue: { world, pawn, actor, hidden = {components} }
local wlook = nil       -- the wing cap on his head: { world, pawn, actor }
local glide = false
local slowed, softened = false, false    -- (this fall was slowed by the cap; its landing already softened)
local was_under = false                 -- (under the water last tick: metal, falling in, he goes straight down)
local flick = nil       -- the vanish cap's flicker: { pawn, comps, on }
local GRID = "/Engine/EngineMaterials/WorldGridMaterial.WorldGridMaterial"

local function sfx(name) local S = package.loaded["sfx"]; if S then pcall(S.play, name) end end

function M.setup(helpers) H = helpers or {} end

-- the metal cap statue's own picture and its repeats on his body and clothes ("why is nothing else textured other than
-- the hat nose and stash?", 2026-10-18: Mario 64's metal picture, as on his cap; the plain chrome grey was metal_body.png)
M.METAL_TEX = "textures/metal_body_sm64.png"        -- (that picture, its colours kept and toned for the engine reading it as linear)
M.METAL_UV = 2.0                                    -- (1 "kinda zoomed in", 4 "to small")

function M.on(kind)
    if kind == nil then return M.kind ~= nil end
    return M.kinds[kind] == true
end

-- what the cap keeps off him (health.lua asks): everything but a fall
function M.shield(why)
    if not (M.kinds.metal or M.kinds.vanish) then return false end
    why = tostring(why or "")
    return not why:find("drop")
end

local function comps_of(pawn, path)
    local out = {}
    local cls = StaticFindObject(path)
    if not (cls and cls:IsValid()) then return out end
    for _, c in ipairs(pawn:K2_GetComponentsByClass(cls)) do
        local o = c:get()
        if o and o:IsValid() then out[#out + 1] = o end
    end
    return out
end

local function drop_look(restore)
    local l = look
    look = nil
    if not l then return end
    local w = lib.world()
    if not (w and w:GetAddress() == l.world) then return end
    if restore then
        -- (each as it was: the look's hiding put back, not everything shown - the Mario look keeps some hidden, and
        -- they all came back after a metal cap: "it bugged out marios original cloths", 2026-10-17)
        for i, c in ipairs(l.hidden) do
            local was = (l.was == nil) or l.was[i]
            if was then pcall(function() c:SetVisibility(true, false) end) end
        end
        -- (his cloth started over where he is: hidden 20 s, it came back bunched up)
        local G = package.loaded["game"]
        if G and G.reset_cloth then pcall(G.reset_cloth, lib.pawn()) end
    end
    if l.metal then
        local ML = package.loaded["mariolook"]
        if ML and ML.paint then pcall(ML.paint, nil) end
    end
    pcall(function() lib.keep[l.actor:GetAddress()] = nil end)
    lib.destroy(l.actor)
end

-- The Wing Cap on his head while it lasts ("make the wing cap better", 2026-10-16): Mario 64's own cap model, wings
-- and all, on his head bone - its X up the neck, Y forward, Z to his left; the cap's up is its Z, its peak -X - at a
-- human head's size.
local WING_SCALE = 0.45
local WING_AT = { X = 12.5, Y = 1.5, Z = 0.0 }               -- cm along the head bone: up, forward, left
local WING_TURN = { Pitch = 0.0, Yaw = -90.0, Roll = 90.0 }
local function wing_look(world, pawn)
    local data = H.actor_data and H.actor_data("cap_wing")
    if not data then return end
    local body = pawn.Mesh
    local inst = lib.make_instance(world, data, body:K2_GetComponentLocation(), 0.0, WING_SCALE)
    if not inst then return end
    local a = inst.actor
    pcall(function() a:SetActorEnableCollision(false) end)
    lib.keep[a:GetAddress()] = "cap"             -- (a scene load's sweep leaves it: it goes with the cap)
    a:K2_AttachToComponent(body, FName("head"), 0, 0, 0, false)
    pcall(function()
        a.RootComponent.RelativeLocation = WING_AT
        a.RootComponent.RelativeRotation = WING_TURN
        a.RootComponent:SetRelativeScale3D({ X = WING_SCALE, Y = WING_SCALE, Z = WING_SCALE })
    end)
    wlook = { world = world:GetAddress(), pawn = pawn:GetAddress(), actor = a }
end
local function drop_wing()
    local l = wlook
    wlook = nil
    if not l then return end
    local w = lib.world()
    if not (w and w:GetAddress() == l.world) then return end
    pcall(function() lib.keep[l.actor:GetAddress()] = nil end)
    lib.destroy(l.actor)
end

-- his meshes copied, posed by his own, in `mid`, following his body; his own hidden meanwhile (grooms too: a bald
-- statue or ghost - hair has its own shaders)
local function make_look(kind)
    local world, pawn = lib.world(), lib.pawn()
    if not (world and pawn) then return end
    if kind == "wing" then drop_wing(); return wing_look(world, pawn) end
    if kind ~= "metal" then return end
    drop_look(true)
    local mid = lib.try_load(GRID)
    if not mid then return end
    local skel = comps_of(pawn, "/Script/Engine.SkeletalMeshComponent")
    local body
    for _, c in ipairs(skel) do if c:GetFName():ToString() == "CharacterMesh0" then body = c end end
    if not body then return end
    local a = lib.spawn_actor(world, body:K2_GetComponentLocation(), 0.0)
    if not a then return end
    pcall(function() a:SetActorEnableCollision(false) end)
    lib.keep[a:GetAddress()] = "cap"             -- (a scene load's sweep leaves it: it goes with the cap)
    a:K2_AttachToComponent(body, FName("None"), 2, 2, 2, false)
    local scls = StaticFindObject("/Script/Engine.SkeletalMeshComponent")
    -- (each piece silver in a copy of his own material for it - they render on his skinned meshes, where the engine's
    -- grid stood in for anything else: Mario 64's metal picture for its colour, metal and shine up where the material
    -- has them; "also we gotta work on the metal cap look", 2026-10-17. The grid only if that fails.)
    -- (`M.LOOK_STYLE`, while a skin makes it: its picture, tint, metal and shine - the RAINBOW skin's; else the metal cap's)
    local ST = M.LOOK_STYLE or {}
    local metal_tex = nil
    pcall(function()
        metal_tex = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary"):ImportFileAsTexture2D(world,
            lib.MOD_DIR .. (ST.tex or M.METAL_TEX))
    end)
    local SILVER = ST.tint or { R = 0.62, G = 0.64, B = 0.70, A = 1.0 }
    local function paint(c, src)
        for i = 0, c:GetNumMaterials() - 1 do
            local ok = false
            if metal_tex and src then
                ok = pcall(function()
                    local base = src:GetMaterial(i)
                    -- (from the material under his: CreateDynamicMaterialInstance on a material that is already one
                    -- of those gave the copy his very own, and the silver went onto his clothes - "marios cloths are
                    -- still messed up", 2026-10-17)
                    local guard = 0
                    while base and base:IsValid() and base:GetClass():GetFName():ToString() == "MaterialInstanceDynamic" and guard < 8 do
                        base = base.Parent; guard = guard + 1
                    end
                    if not (base and base:IsValid()) then error("none") end
                    local m = c:CreateDynamicMaterialInstance(i, base, FName("None"))
                    for _, n in ipairs({ "Color_MAIN", "PrintColor", "BaseColor", "BaseColorTexture", "Diffuse", "diffuse",
                                         "Albedo", "BaseColorMap", "Color", "diffuse_texture", "Diffuse_Texture" }) do
                        m:SetTextureParameterValue(FName(n), metal_tex)
                    end
                    for _, n in ipairs({ "Tint", "diffuse_color_1", "diffuse_color_2", "B_diffuse_color_1", "C_color", "ColorFabric" }) do
                        m:SetVectorParameterValue(FName(n), SILVER)
                    end
                    m:SetScalarParameterValue(FName("Metallic"), ST.metallic or 1.0)
                    m:SetScalarParameterValue(FName("Roughness"), ST.rough or 0.25)
                    m:SetScalarParameterValue(FName("UV Amount"), ST.uv or M.METAL_UV)
                end)
            end
            if not ok then pcall(function() c:SetMaterial(i, mid) end) end
        end
        -- (whenever the sun casts shadows - real-time shadows on it is part of his: lib.lit_on)
        pcall(function() c:SetCastShadow(true) end)
    end
    local cb
    for _, src in ipairs(skel) do
        pcall(function()
            local c = a:AddComponentByClass(scls, true, IDENT, false)
            if not (c and c:IsValid()) then return end
            local asset = src:GetSkinnedAsset()
            if asset and asset:IsValid() then c:SetSkinnedAssetAndUpdate(asset, true) end
            c:K2_AttachToComponent(a.RootComponent, FName("None"), 2, 2, 2, false)
            -- (all led by his body, the one that is animated: his shoes follow footik's copy of it, and a copy led by
            -- them - a follower's follower - was never posed: "the feet are disconnected from the player", 2026-10-17)
            c:SetLeaderPoseComponent(body, true, false)
            pcall(function() c.VisibilityBasedAnimTickOption = 0 end)
            paint(c, src)
            -- (the shoes: their material takes colours only, and came out flat grey - the jeans' cotton with the metal
            -- picture, as the cloth: "hat nose mustash and shoes still not textures correctly during metal cap")
            if src:GetFName():ToString() == "Feet" then
                local cot = StaticFindObject("/SPP/MetaHumanAdHoc/Clothing/Torso/HoodieV1/Cotton_Natural_Rough_MAT.Cotton_Natural_Rough_MAT")
                if cot and cot:IsValid() and metal_tex then
                    for i = 0, c:GetNumMaterials() - 1 do
                        pcall(function()
                            local m = c:CreateDynamicMaterialInstance(i, cot, FName("None"))
                            m:SetTextureParameterValue(FName("BaseColor"), metal_tex)
                            m:SetVectorParameterValue(FName("Tint"), ST.cloth or { R = 1.0, G = 1.02, B = 1.08, A = 1.0 })
                            m:SetScalarParameterValue(FName("UV Amount"), ST.uv or M.METAL_UV)
                            m:SetScalarParameterValue(FName("NormalStrength"), 0.15)
                        end)
                    end
                end
            end
            if src == body then cb = c end
        end)
    end
    local ccls = StaticFindObject("/Script/ChaosClothAssetEngine.ChaosClothComponent")
    local hide = {}
    for _, src in ipairs(comps_of(pawn, "/Script/Engine.PrimitiveComponent")) do
        local cname = src:GetClass():GetFName():ToString()
        if cname:find("ClothComponent") and ccls and ccls:IsValid() then
            pcall(function()
                local c = a:AddComponentByClass(ccls, true, IDENT, false)
                if not (c and c:IsValid()) then return end
                c:K2_AttachToComponent(cb or a.RootComponent, FName("None"), 2, 2, 2, false)
                local asset = src:GetAsset()
                if asset and asset:IsValid() then c:SetAsset(asset) end
                c:SetLeaderPoseComponent(body, true, false)
                paint(c, src)
                -- (the shirt's own material took the metal picture nowhere: the jeans' cotton, which does, for all cloth)
                local cot = StaticFindObject("/SPP/MetaHumanAdHoc/Clothing/Torso/HoodieV1/Cotton_Natural_Rough_MAT.Cotton_Natural_Rough_MAT")
                if cot and cot:IsValid() and metal_tex then
                    for i = 0, c:GetNumMaterials() - 1 do
                        pcall(function()
                            local m = c:CreateDynamicMaterialInstance(i, cot, FName("None"))
                            m:SetTextureParameterValue(FName("BaseColor"), metal_tex)
                            m:SetVectorParameterValue(FName("Tint"), ST.cloth or { R = 1.0, G = 1.02, B = 1.08, A = 1.0 })
                            m:SetScalarParameterValue(FName("UV Amount"), ST.uv or M.METAL_UV)
                            m:SetScalarParameterValue(FName("NormalStrength"), 0.15)
                        end)
                    end
                end
            end)
            hide[#hide + 1] = src
        elseif cname:find("SkeletalMeshComponent") or cname:find("GroomComponent") then
            hide[#hide + 1] = src
        end
    end
    local was = {}
    for i, c in ipairs(hide) do
        local ok, v = pcall(function() return c:IsVisible() end)
        was[i] = (not ok) or v
        pcall(function() c:SetVisibility(false, false) end)
    end
    -- (Mario's cap, nose and mustache metal too)
    local ML = package.loaded["mariolook"]
    local pm = nil
    -- (plain silver: the pieces the mod makes have no layout for Mario 64's metal picture to lie on - it showed as a
    -- smear of one of its colours)
    pcall(function() pm = lib.get_mid(world, "opaque", "metal_silver") end)
    if ML and ML.paint then pcall(ML.paint, pm or mid) end
    look = { world = world:GetAddress(), pawn = pawn:GetAddress(), actor = a, hidden = hide, was = was, metal = true }
end

local function stop_flicker()
    local f = flick
    flick = nil
    if not f then return end
    local w = lib.world()
    if not (w and w:GetAddress() == f.world) then return end
    for _, c in ipairs(f.comps) do pcall(function() c:SetVisibility(true, false) end) end
    if f.actor then pcall(function() f.actor:SetActorHiddenInGame(false) end) end
end

local function start_flicker()
    stop_flicker()
    local world, pawn = lib.world(), lib.pawn()
    if not (world and pawn) then return end
    -- (metal on as well: the statue, whole, hidden and shown on the clock - 10 times a second each way, so each time
    -- it is shown it stays drawn a few frames. Flickered every frame, piece by piece or whole, it was never seen at all:
    -- "completely invisable when collecting 2 caps", "you didnt fix it still completely invis"; steady, it was no ghost:
    -- "okay you gotta make the charater invis as well", 2026-10-23)
    if look and look.actor then
        -- (Mario's cap, nose and mustache - metal too, on his head, not the statue's - with it)
        local ML = package.loaded["mariolook"]
        local parts = {}
        if ML and ML.pmcs then for _, c in ipairs(ML.pmcs()) do parts[#parts + 1] = c end end
        flick = { world = world:GetAddress(), pawn = pawn:GetAddress(), comps = parts, actor = look.actor, on = true, timed = true }
        return
    end
    local comps = {}
    local statue = nil
    for _, src in ipairs(comps_of(pawn, "/Script/Engine.PrimitiveComponent")) do
        local cname = src:GetClass():GetFName():ToString()
        if cname:find("SkeletalMeshComponent") or cname:find("ClothComponent") or cname:find("GroomComponent") then
            comps[#comps + 1] = src
        end
    end
    -- (Mario's cap, nose and mustache flicker with him)
    local ML = package.loaded["mariolook"]
    if ML and ML.pmcs then for _, c in ipairs(ML.pmcs()) do comps[#comps + 1] = c end end
    flick = { world = world:GetAddress(), pawn = pawn:GetAddress(), comps = comps, actor = statue, on = true }
end

-- (`quiet`: put on without its fanfare, his "Here we go!" or its tune, for `secs` - the ending's wing cap: ending.lua)
function M.give(kind, quiet, secs)
    if not TIME[kind] then return end
    local had = M.kinds[kind]
    M.kinds[kind] = true
    M.kind, M.left = kind, math.max(M.left or 0.0, secs or TIME[kind])
    M.level = H.level and H.level() or nil
    if not quiet then
        sfx("star_sound")
        sfx("mario_here_we_go")
        local MU = package.loaded["music"]
        if MU and MU.play then pcall(MU.play, TUNE[kind], true) end
    end
    if kind == "vanish" and H.vanish_walls then pcall(H.vanish_walls, false) end
    if kind == "metal" and H.swimming and H.swimming() and H.stop_swim then
        pcall(H.stop_swim)
        -- (straight down from where he swam: the swim's way and speed gone)
        pcall(function() local cm = lib.pawn().CharacterMovement; cm.Velocity = { X = 0.0, Y = 0.0, Z = math.min(0.0, cm.Velocity.Z) } end)
    end
    if kind == "metal" then
        -- (the flicker off his own meshes first: the statue keeps which were shown, to put back after)
        local flickering = flick ~= nil
        pcall(stop_flicker)
        -- (the skin's parts off first: the cap's statue is all of him, and puts back what it found shown)
        if M._parts_off then pcall(M._parts_off) end
        if not (had and look) then pcall(make_look, "metal") end
        if flickering or M.kinds.vanish then pcall(start_flicker) end
    elseif kind == "wing" then
        if not (had and wlook) then pcall(make_look, "wing") end
    else
        pcall(start_flicker)
    end
    local on = {}
    for _, k in ipairs({ "wing", "metal", "vanish" }) do if M.kinds[k] then on[#on + 1] = k end end
    log("cap: %s on for %.0f s (on: %s)", kind, M.left, table.concat(on, " + "))
end

-- ------------------------------------------------------------------ the secrets' skins and crown (secrets.lua)
-- The skins, each opened by Final Bowser (secrets.lua), worn part by part - his head, his chest (his shirt, and his arms
-- with it), his legs, his feet: charmenu.lua's HEAD, CHEST, LEGS and FEET, among their clothes - "it should be in the 4
-- slots in parts just like other cloths shoes pants shirt and head", 2026-11-04. Each part's meshes copied over it, posed
-- by his own and in the skin's look, his own hidden under (make_parts_look, as the metal cap's statue is made) -
--   ghost    the GHOST RUNNER: the race's ghost racer - the metal cap's statue (make_look: his meshes in chrome, no
--            hair), Mario's cap in chrome with its nose and mustache off (SKIN_HIDE: mariolook.lua's pieces 0 and 1, as
--            race.lua's RACER_HIDE), and the racer's backpack, its star turning in it and its drawstrings (race.lua
--            M.pack_on) - "I want it to be the ghost runner skin. back pack and all", 2026-11-04
--   rainbow  the RAINBOW skin: the statue in the rainbow (textures/rainbow_skin.png, tools/rainbow_skin_tex.py), his
--            look's pieces too - "a rainbow skin for beating ironman mode and human mode together"
-- and the hat (charmenu.lua's HEAD, CROWN): `crown` the CROWN - gold, its points jewelled, on his head in place of Mario's
-- cap (tools/crown_tex.py's pictures) - "a secret unlock for iron man mode a crown". Only looks: the metal cap's powers
-- come only with the cap. Kept up by M.update (skin_keep) every frame.
M.parts, M.hat = {}, nil         -- (each part's skin: head, chest, legs, feet -> "ghost" or "rainbow"; the hat)
-- (each part's meshes, by name: his body - his arms and hands - with his chest; his hair, brows and beard with his head)
M.SKIN_LOD = 2                    -- (the copies' detail: SetForcedLOD, 2 = its LOD 1)
M.PART_COMPS = { head = { Head = true }, chest = { TorsoCloth = true, CharacterMesh0 = true }, legs = { LegsCloth = true },
                 feet = { Feet = true } }
local COTTON = "/SPP/MetaHumanAdHoc/Clothing/Torso/HoodieV1/Cotton_Natural_Rough_MAT.Cotton_Natural_Rough_MAT"
M.SKIN_HIDE = { [0] = true, [1] = true }
M.SKIN_STYLE = {
    -- (the metal cap's own; his eyes metal too, shining - "also make his eyes metal", 2026-11-04)
    ghost = { eyes_metal = { R = 0.78, G = 0.80, B = 0.86, A = 1.0 } },
    -- (the Final Bowser floors' rainbow liquid, flowing: its pictures stepped through, `frames` - tools/
    -- rainbow_skin_frames.py - and his look's pieces in the floors' own, slid and coloured as theirs are: "for the rainbow
    -- skin make it look like the final bowser stage, and have it move like it too", 2026-11-04)
    rainbow = { tex = "textures/rainbow_skin_h000.png", tint = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }, metallic = 0.2,
                rough = 0.35, uv = 1.0, cloth = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }, pieces = "rainbow_skin_h000",
                frames = { n = 192, fps = 16.0, name = "rainbow_skin_h%03d", load = 8 },   -- (24 a second: at 12 it stepped, "the fps
                -- on the moving texture is very low", 2026-11-04)
                -- (his eyes purple, not in the liquid - the head's eye materials, slots 3 and 4, as mariolook.lua colours
                -- Mario's blue: "give the player purple eyes on the rainbow skin", 2026-11-04)
                eyes = { R = 0.3, G = 0.05, B = 0.6, A = 1.0 }, eye_glow = { R = 16.0, G = 3.0, B = 34.0, A = 1.0 },   -- ("make eyes glow more", 2026-11-04)
                -- (and glowing: a ball of purple light over each eye, on his eye bones - "make the eyes glow a bit too",
                -- "also eyes not glowing purple", 2026-11-04; the pieces' picture zoomed to `piece_scale`)
                piece_scale = 1.0 },
}
-- the crown: its band's radius, height and points (cm), where it sits on his head bone (up, forward, left), its turn
-- (on top of the GHOST RUNNER's chrome cap - the CROWN is that head with it: "for the crown have a metal hat like the
-- ghost runner that the crown sits on top of", "or just use the metal head", 2026-11-04 - where the cap's dome is its
-- band's width across: mariolook.lua M.CAP, 8 + 11.4 up, 9.9 to the side)
-- (tipped down to his left and over that way, hanging off his head: "have the crown tilt to the side a bit", "tilt it
-- to the left side", "so it kinda hangs off the head", 2026-11-04)
-- (and fitted to the cap: wider and straighter, lower, its foot on the dome all round - "needs to conform to the hat a
-- bit more", 2026-11-04)
-- (hanging from the middle of his head: tipped 40 degrees down his left side - the roll, about the way he faces; the
-- pitch only turned it round its own middle and it sat flat: "it should tilt kinda like its hanging from the middle of
-- the head", "go back to how you had it", 2026-11-04)
M.CROWN = { r = 7.4, h = 2.8, points = 5, tip = 3.6, flare = 1.06, at = { X = 15.0, Y = 0.6, Z = -5.4 },
            turn = { Pitch = 0.0, Yaw = -90.0, Roll = 130.0 }, jewel = 0.9 }
local skin = { pack = nil, star = nil, pawn = nil, t = 0.0, yaw = 0.0, pieces = nil, pieces_style = nil, rebuild_at = nil,
               crown = nil, crown_pawn = nil, cap_hidden = nil }
local plook = nil       -- the parts' copies: { world, pawn, actor, hidden = {components}, was, sig }
local function skin_alive(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end
local function skin_pack_drop()
    if skin.star and skin.star.actor then
        pcall(function() lib.keep[skin.star.actor:GetAddress()] = nil end)
        pcall(lib.destroy, skin.star.actor, false)
    end
    if skin.pack then
        pcall(function() lib.keep[skin.pack:GetAddress()] = nil end)
        pcall(lib.destroy, skin.pack, false)
    end
    skin.pack, skin.star, skin.pawn, skin.pieces, skin.star_mid = nil, nil, nil, nil, nil
end
-- (the crown: a band flaring a little, `points` points up from it, a jewel on each - built once a scene)
local function crown_make(world, pawn)
    local C = M.CROWN
    local function sec(id, tex) return { id = id, layer = "opaque", texture = tex, pos = {}, uv = {}, col = {}, nrm = {}, idx = {}, nverts = 0, ntris = 0 } end
    local gold, gem = sec(0, "crown_gold"), sec(1, "crown_jewel")
    local function vert(s, x, y, z, nx, ny, nz, u, v)
        local P, N, U, K = s.pos, s.nrm, s.uv, s.col
        P[#P + 1], P[#P + 2], P[#P + 3] = x, y, z
        N[#N + 1], N[#N + 2], N[#N + 3] = nx, ny, nz
        U[#U + 1], U[#U + 2] = u, v
        K[#K + 1], K[#K + 2], K[#K + 3], K[#K + 4] = 1.0, 1.0, 1.0, 1.0
        s.nverts = s.nverts + 1
        return s.nverts - 1
    end
    local function quad(s, a, b, c, dd) local I = s.idx; I[#I + 1], I[#I + 2], I[#I + 3] = a, b, c; I[#I + 1], I[#I + 2], I[#I + 3] = a, c, dd; s.ntris = s.ntris + 2 end
    local function tri3(s, a, b, c) local I = s.idx; I[#I + 1], I[#I + 2], I[#I + 3] = a, b, c; s.ntris = s.ntris + 1 end
    local n = C.points * 6
    local function ring(r, z, side, u)
        local ids = {}
        for i = 0, n do
            local t = i / n * 2.0 * math.pi
            local cx, cy = math.cos(t), math.sin(t)
            ids[i] = vert(gold, cx * r, cy * r, z, cx * side, cy * side, 0.0, i / n, u)
        end
        return ids
    end
    -- (the band: outside and inside, from its foot to its top, the top flared)
    local o0, o1 = ring(C.r, 0.0, 1.0, 0.0), ring(C.r * C.flare, C.h, 1.0, 1.0)
    local i0, i1 = ring(C.r - 0.35, 0.0, -1.0, 0.0), ring(C.r * C.flare - 0.35, C.h, -1.0, 1.0)
    for i = 0, n - 1 do
        quad(gold, o0[i], o0[i + 1], o1[i + 1], o1[i])
        quad(gold, i0[i + 1], i0[i], i1[i], i1[i + 1])
    end
    -- (the points: a flat spike each, both faces, from the band's top)
    local R = C.r * C.flare
    for p = 0, C.points - 1 do
        local t0 = (p + 0.5) / C.points * 2.0 * math.pi
        local w = math.pi / C.points * 0.8
        local ax, ay = math.cos(t0 - w), math.sin(t0 - w)
        local bx, by = math.cos(t0 + w), math.sin(t0 + w)
        local cx, cy = math.cos(t0), math.sin(t0)
        for _, side in ipairs({ 1.0, -1.0 }) do
            local rr = R + (side < 0 and -0.35 or 0.0)
            local a = vert(gold, ax * rr, ay * rr, C.h, cx * side, cy * side, 0.0, 0.0, 0.0)
            local b = vert(gold, bx * rr, by * rr, C.h, cx * side, cy * side, 0.0, 1.0, 0.0)
            local c = vert(gold, cx * (rr + 0.6), cy * (rr + 0.6), C.h + C.tip, cx * side, cy * side, 0.0, 0.5, 1.0)
            if side > 0 then tri3(gold, a, b, c) else tri3(gold, b, a, c) end
        end
        -- (its jewel: a small diamond on the band below the point, facing out)
        local jr, jz, j = C.r * (1.0 + (C.flare - 1.0) * 0.5) + 0.25, C.h * 0.5, C.jewel
        local tx, ty = -cy, cx
        local top = vert(gem, cx * jr, cy * jr, jz + j, cx, cy, 0.0, 0.5, 0.0)
        local bot = vert(gem, cx * jr, cy * jr, jz - j, cx, cy, 0.0, 0.5, 1.0)
        local lft = vert(gem, cx * jr + tx * j, cy * jr + ty * j, jz, cx, cy, 0.0, 0.0, 0.5)
        local rgt = vert(gem, cx * jr - tx * j, cy * jr - ty * j, jz, cx, cy, 0.0, 1.0, 0.5)
        local mid = vert(gem, cx * (jr + 0.5), cy * (jr + 0.5), jz, cx, cy, 0.0, 0.5, 0.5)
        tri3(gem, top, lft, mid); tri3(gem, lft, bot, mid); tri3(gem, bot, rgt, mid); tri3(gem, rgt, top, mid)
    end
    local body = pawn.Mesh
    local a = lib.spawn_actor(world, body:K2_GetComponentLocation(), 0.0)
    if not a then return nil end
    pcall(function() a:SetActorEnableCollision(false) end)
    local pmc = lib.add_pmc(a)
    if not pmc then lib.destroy(a); return nil end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    lib.add_sections(world, pmc, { gold, gem })
    pcall(function() pmc:SetCastShadow(true) end)
    lib.keep[a:GetAddress()] = "skin"
    a:K2_AttachToComponent(body, FName("head"), 0, 0, 0, false)
    pcall(function()
        a.RootComponent.RelativeLocation = C.at
        a.RootComponent.RelativeRotation = C.turn
    end)
    return a
end
local function crown_drop()
    if skin.crown then
        pcall(function() lib.keep[skin.crown:GetAddress()] = nil end)
        pcall(lib.destroy, skin.crown, false)
    end
    skin.crown, skin.crown_pawn = nil, nil
    if skin.cap_hidden then
        skin.cap_hidden = nil
        local ML = package.loaded["mariolook"]
        if ML and ML.show_cap then pcall(ML.show_cap, true) end
    end
end
local function hat_keep(world, pawn, pa)
    if M.hat ~= "crown" then if skin.crown or skin.cap_hidden then crown_drop() end; return end
    if not (skin_alive(skin.crown) and skin.crown_pawn == pa) then
        crown_drop()
        local ok, a = pcall(crown_make, world, pawn)
        if ok and a then skin.crown, skin.crown_pawn = a, pa; log("skin: the CROWN on him") else log("skin: the crown: %s", tostring(a)) end
    end
    -- (hidden from first person's view and under the Wing Cap; the cap under it is the GHOST RUNNER head's)
    local fp = false
    local FPV = package.loaded["fp"]
    if FPV and FPV.on then local ok, on = pcall(FPV.on); fp = ok and on == true end
    local hide = fp or wlook ~= nil
    if skin.crown and hide ~= (skin.crown_hidden or false) then
        skin.crown_hidden = hide
        pcall(function() skin.crown:SetActorHiddenInGame(hide) end)
    end
end
-- the parts' copies taken off, his own shown again as they were (`restore`)
local function plook_drop(restore)
    local l = plook
    plook = nil
    if not l then return end
    local w = lib.world()
    if not (w and w:GetAddress() == l.world) then return end
    for _, c in ipairs(l.shade or {}) do pcall(function() c:SetCastHiddenShadow(false) end) end
    if restore then
        for i, c in ipairs(l.hidden) do
            if l.was[i] then pcall(function() c:SetVisibility(true, false) end) end
        end
        local G = package.loaded["game"]
        if G and G.reset_cloth then pcall(G.reset_cloth, lib.pawn()) end
    end
    pcall(function() lib.keep[l.actor:GetAddress()] = nil end)
    lib.destroy(l.actor)
end
-- (before the metal cap's whole statue: its own hides all of him, and must find his own shown - game.lua's give)
M._parts_off = function() plook_drop(true); skin.pieces = nil end
local function make_parts_look(world, pawn, parts)
    local want = {}
    for part, kind in pairs(parts) do
        for n in pairs(M.PART_COMPS[part] or {}) do want[n] = kind end
    end
    if not next(want) then return end
    local skel = comps_of(pawn, "/Script/Engine.SkeletalMeshComponent")
    local body
    for _, c in ipairs(skel) do if c:GetFName():ToString() == "CharacterMesh0" then body = c end end
    if not body then return end
    local a = lib.spawn_actor(world, body:K2_GetComponentLocation(), 0.0)
    if not a then return end
    pcall(function() a:SetActorEnableCollision(false) end)
    lib.keep[a:GetAddress()] = "skin"
    a:K2_AttachToComponent(body, FName("None"), 2, 2, 2, false)
    local KRL = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
    local texs, anim = {}, {}
    -- (a material's picture parameters that took `tex` - for a skin whose picture moves: anim, stepped by skin_keep)
    local function took(m, tex, names)
        local got = {}
        for _, n in ipairs(names) do
            local ok, v = pcall(function() return m:K2_GetTextureParameterValue(FName(n)) end)
            if ok and v and v:IsValid() and v:GetAddress() == tex:GetAddress() then got[#got + 1] = n end
        end
        if #got > 0 then anim[#anim + 1] = { mid = m, names = got } end
    end
    local function tex_of(kind)
        if texs[kind] == nil then
            local st = M.SKIN_STYLE[kind] or {}
            local t = nil
            pcall(function() t = KRL:ImportFileAsTexture2D(world, lib.MOD_DIR .. (st.tex or M.METAL_TEX)) end)
            texs[kind] = t or false
        end
        return texs[kind] or nil
    end
    local function paint(c, src, kind)
        local st = M.SKIN_STYLE[kind] or {}
        local tex = tex_of(kind)
        local tint = st.tint or { R = 0.62, G = 0.64, B = 0.70, A = 1.0 }
        local eyes = (st.eyes or st.eyes_metal) and src:GetFName():ToString() == "Head"
        for i = 0, c:GetNumMaterials() - 1 do
            pcall(function()
                local base = src:GetMaterial(i)
                local guard = 0
                while base and base:IsValid() and base:GetClass():GetFName():ToString() == "MaterialInstanceDynamic" and guard < 8 do
                    base = base.Parent; guard = guard + 1
                end
                if not (base and base:IsValid() and tex) then error("none") end
                -- (the eyes glowing purple - the head's slots 3 and 4 in a light of their own - and what lies over them, the
                -- tear film and the eyes' shadow (2, 5, 7), left his own: painted in the liquid they hid the eyes - "players
                -- eyes still not glowing purple", 2026-11-04)
                if eyes and st.eyes_metal and (i == 3 or i == 4) then
                    local mm = lib.get_mid(world, "lit", "metal_silver", 0.96)
                    if not mm then error("no metal") end
                    mm:SetScalarParameterValue(FName("MetallicFactor"), 1.0)
                    mm:SetScalarParameterValue(FName("RoughnessFactor"), 0.15)
                    mm:SetVectorParameterValue(FName("BaseColorFactor"), st.eyes_metal)
                    c:SetMaterial(i, mm)
                    return
                end
                if eyes and (i == 3 or i == 4) then
                    local gm = lib.get_mid(world, "lit", st.eye_tex or "eye_glow_purple", 0.97)
                    if not gm then error("no glow") end
                    local gt = lib.texture(world, st.eye_tex or "eye_glow_purple")
                    if gt then gm:SetTextureParameterValue(FName("EmissiveTexture"), gt) end
                    gm:SetVectorParameterValue(FName("EmissiveFactor"), st.eye_glow or { R = 4.8, G = 0.9, B = 10.0, A = 1.0 })
                    gm:SetVectorParameterValue(FName("BaseColorFactor"), st.eyes)
                    c:SetMaterial(i, gm)
                    return
                end
                if eyes and (i == 2 or i == 5 or i == 7) then
                    c:SetMaterial(i, src:GetMaterial(i))
                    return
                end
                local m = c:CreateDynamicMaterialInstance(i, base, FName("None"))
                local TN = { "Color_MAIN", "PrintColor", "BaseColor", "BaseColorTexture", "Diffuse", "diffuse",
                             "Albedo", "BaseColorMap", "Color", "diffuse_texture", "Diffuse_Texture" }
                for _, n in ipairs(TN) do
                    m:SetTextureParameterValue(FName(n), tex)
                end
                if st.frames then took(m, tex, TN) end
                for _, n in ipairs({ "Tint", "diffuse_color_1", "diffuse_color_2", "B_diffuse_color_1", "C_color", "ColorFabric" }) do
                    m:SetVectorParameterValue(FName(n), tint)
                end
                m:SetScalarParameterValue(FName("Metallic"), st.metallic or 1.0)
                m:SetScalarParameterValue(FName("Roughness"), st.rough or 0.25)
                m:SetScalarParameterValue(FName("UV Amount"), st.uv or M.METAL_UV)
            end)
        end
        -- (no shadow of their own, and a lighter detail level: each copy's own real-time shadow took the game from 122
        -- to 75 frames a second - "also very laggy", 2026-11-04. His shadow is his own hidden meshes': below)
        pcall(function() c:SetCastShadow(false) end)
        pcall(function() c:SetForcedLOD(M.SKIN_LOD) end)
    end
    -- (cloth and shoes: the jeans' cotton with the picture, which takes it - as the metal cap's statue does)
    local function cotton(c, kind)
        local st = M.SKIN_STYLE[kind] or {}
        local tex = tex_of(kind)
        local cot = StaticFindObject(COTTON)
        if not (cot and cot:IsValid() and tex) then return end
        for i = 0, c:GetNumMaterials() - 1 do
            pcall(function()
                local m = c:CreateDynamicMaterialInstance(i, cot, FName("None"))
                m:SetTextureParameterValue(FName("BaseColor"), tex)
                if st.frames then anim[#anim + 1] = { mid = m, names = { "BaseColor" } } end
                m:SetVectorParameterValue(FName("Tint"), st.cloth or { R = 1.0, G = 1.02, B = 1.08, A = 1.0 })
                m:SetScalarParameterValue(FName("UV Amount"), st.uv or M.METAL_UV)
                m:SetScalarParameterValue(FName("NormalStrength"), 0.15)
            end)
        end
    end
    local scls = StaticFindObject("/Script/Engine.SkeletalMeshComponent")
    local cb, names = nil, {}
    local made = {}         -- (each piece and the part of his it copies: footik.lua leads them through a swim, M.skin_parts)
    for _, src in ipairs(skel) do
        local nm = src:GetFName():ToString()
        local kind = want[nm]
        if kind then
            pcall(function()
                local c = a:AddComponentByClass(scls, true, IDENT, false)
                if not (c and c:IsValid()) then return end
                local asset = src:GetSkinnedAsset()
                if asset and asset:IsValid() then c:SetSkinnedAssetAndUpdate(asset, true) end
                c:K2_AttachToComponent(a.RootComponent, FName("None"), 2, 2, 2, false)
                c:SetLeaderPoseComponent(body, true, false)
                pcall(function() c.VisibilityBasedAnimTickOption = 0 end)
                paint(c, src, kind)
                if nm == "Feet" then cotton(c, kind) end
                if src == body then cb = c end
                names[#names + 1] = nm
                made[#made + 1] = { c = c, nm = nm }
            end)
        end
    end
    local ccls = StaticFindObject("/Script/ChaosClothAssetEngine.ChaosClothComponent")
    local hide = {}
    for _, src in ipairs(comps_of(pawn, "/Script/Engine.PrimitiveComponent")) do
        local cname = src:GetClass():GetFName():ToString()
        local nm = src:GetFName():ToString()
        local kind = want[nm]
        if kind and cname:find("ClothComponent") and ccls and ccls:IsValid() then
            pcall(function()
                local c = a:AddComponentByClass(ccls, true, IDENT, false)
                if not (c and c:IsValid()) then return end
                c:K2_AttachToComponent(cb or a.RootComponent, FName("None"), 2, 2, 2, false)
                local asset = src:GetAsset()
                if asset and asset:IsValid() then c:SetAsset(asset) end
                c:SetLeaderPoseComponent(body, true, false)
                -- (no cloth sim of its own: skinned to his body as it moves - a second simulation of his shirt on the
                -- copy blew it up to many times his size and slowed the game: "the cloths expand to 20x its size",
                -- "also very laggy", 2026-11-04)
                pcall(function() c:SetEnableSimulation(false) end)
                paint(c, src, kind)
                cotton(c, kind)
                names[#names + 1] = nm
                made[#made + 1] = { c = c, nm = nm }
            end)
            hide[#hide + 1] = src
        elseif kind and cname:find("SkeletalMeshComponent") then
            hide[#hide + 1] = src
        elseif parts.head and cname:find("GroomComponent") then
            hide[#hide + 1] = src
        end
    end
    local was, shade = {}, {}
    for i, c in ipairs(hide) do
        local ok, v = pcall(function() return c:IsVisible() end)
        was[i] = (not ok) or v
        pcall(function() c:SetVisibility(false, false) end)
        -- (his own meshes, hidden under it, still cast his shadow - not his hair)
        local cn = ""
        pcall(function() cn = c:GetClass():GetFName():ToString() end)
        if not cn:find("Groom") then
            pcall(function() c:SetCastHiddenShadow(true) end)
            shade[#shade + 1] = c
        end
    end
    plook = { world = world:GetAddress(), pawn = pawn:GetAddress(), actor = a, hidden = hide, was = was, shade = shade,
              anim = anim, comps = made }
    log("skin: parts on him - %s", table.concat(names, ", "))
end
local function parts_sig()
    local P = M.parts
    return table.concat({ P.head or "-", P.chest or "-", P.legs or "-", P.feet or "-" }, ",")
end
local function skin_keep(dt, pawn)
    if not pawn then return end
    local world = lib.world()
    if not world then return end
    local pa = pawn:GetAddress()
    pcall(hat_keep, world, pawn, pa)
    local ML = package.loaded["mariolook"]
    -- (the metal cap's whole statue over him meanwhile: the parts made again after it)
    if M.kinds.metal or not next(M.parts) then
        if plook then plook_drop(true) end
        if skin.pack then skin_pack_drop() end
        if not next(M.parts) and skin.pieces_style then
            -- (his look's own pieces again: made anew, out of the skin's paint)
            skin.pieces_style, skin.pieces = nil, nil
            if ML and ML.on and ML.on() and ML.apply then pcall(ML.apply) end
        end
        return
    end
    local sig = parts_sig()
    if skin.rebuild_at and os.clock() >= skin.rebuild_at then
        skin.rebuild_at = nil
        if plook then plook_drop(true) end
    end
    if not (plook and plook.pawn == pa and plook.world == world:GetAddress() and plook.sig == sig) then
        -- (not while footik.lua's copy of his body has him - its own copy, painted with his sleeves and gloves, showed
        -- through: "marios red shirt and white gloves showing through the ghost runner skin", 2026-11-04. It lets him
        -- go while a skin is on: M.parts_on)
        -- (made all the same while he swims: footik.lua then leads its pieces by the swim's body, M.skin_follow)
        local FT = package.loaded["footik"]
        local fs = FT and FT.debug and FT.debug()
        local SWk = package.loaded["swim"]
        local swimming = SWk and SWk.active and SWk.active()
        if fs and fs.on and not swimming then return end
        if plook then plook_drop(true) end
        local ok, err = pcall(make_parts_look, world, pawn, M.parts)
        if not ok then log("skin: the parts: %s", tostring(err)) end
        if plook then plook.sig = sig end
        skin.pieces = nil
    end
    -- (his head's skin on his look's pieces - again whenever they are made anew; the GHOST RUNNER's nose and mustache
    -- off - and his own look back when his head has none)
    local hk = M.parts.head
    skin.t = skin.t + dt
    if ML and skin.t >= 0.5 then
        skin.t = 0.0
        local list = (ML.pmcs and ML.pmcs()) or {}
        local key = list[1] and list[1]:GetAddress() or nil
        if key and (key ~= skin.pieces or hk ~= skin.pieces_style) then
            if hk then
                local pm = nil
                -- (the RAINBOW's its own each time - a new key: lib.get_mid's kept one may be one thrown away)
                skin.piece_n = (skin.piece_n or 0) + 1
                pcall(function() pm = lib.get_mid(world, "opaque", (M.SKIN_STYLE[hk] and M.SKIN_STYLE[hk].pieces) or "metal_silver", (hk == "rainbow") and (0.5 + (skin.piece_n % 40) * 0.01) or nil) end)
                if pm and ML.paint then pcall(ML.paint, pm) end
                -- (the RAINBOW's liquid laid by where each corner faces, as Mario 64's chrome is - the pieces' own UVs
                -- have no layout for it, and it lay smeared: "the hat nos and stash are messed up too", 2026-11-04)
                if hk == "rainbow" and pm and ML.lay_all then pcall(ML.lay_all, pm) end
                -- (the GHOST RUNNER's in Metal Mario's own picture, laid the same way - by where they face, its brim was
                -- one dark spot: "brim of metal cap is not correct", 2026-11-04)
                if hk == "ghost" and ML.lay_all then
                    local cm = lib.get_mid(world, "opaque", "actors__mario__mario_metal.rgba16")
                    if cm then pcall(ML.lay_all, cm, 30.0) end
                end
                skin.piece_mid = (hk == "rainbow") and pm or nil
                skin.pieces = key
                skin.chrome_until = os.clock() + 1.0
            elseif skin.pieces_style and ML.apply and ML.on and ML.on() then
                -- (his look made afresh, out of the skin's paint - only while it is on: a face with none of its own, as
                -- Sacha, was given Mario's again, his hair hidden under it - "why is sacha bald?", 2026-11-04)
                pcall(ML.apply)
                skin.pieces = nil
            end
            skin.pieces_style = hk
        end
    end
    -- (the chrome laid on his look's pieces once, for a moment after they are painted - not as the camera turns, as
    -- the metal cap's 40 s do: walking, his head's bob had it redone every frame and the game fell from 120 frames a
    -- second to 80 - "when you start walking the fps falls to 80 tto 90", 2026-11-04. And the GHOST RUNNER's nose and
    -- mustache off after it, every frame while it is laid - laid, they come back: "flickering nose and stash" - and
    -- else only if shown)
    local laying = os.clock() < (skin.chrome_until or 0.0)
    -- (the GHOST RUNNER's cap: laid once with the rest, above - no camera-turned chrome on it)
    -- (the RAINBOW: its pictures, held on hidden faces of their own so the engine keeps them - one only on a material
    -- for a moment would be thrown away between - loaded a few a frame, then stepped through on every material that
    -- took them; his look's pieces in the floors' liquid, slid and coloured round as the floors' are: bowser_fight.lua
    -- M.liquid_tick)
    local RB = M.SKIN_STYLE.rainbow
    local rb_on = false
    for _, k in pairs(M.parts) do if k == "rainbow" then rb_on = true end end
    local FR = RB and RB.frames
    local wa = world:GetAddress()
    if FR and rb_on then
        local fr = skin.fr
        if not (fr and fr.world == wa) then fr = { world = wa, next = 0, actors = {} }; skin.fr = fr end
        if fr.next < FR.n then
            local secs = {}
            for k = fr.next, math.min(FR.n - 1, fr.next + FR.load - 1) do
                secs[#secs + 1] = { id = #secs, layer = "opaque", texture = string.format(FR.name, k),
                                    pos = { 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0 }, uv = { 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 },
                                    col = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }, nrm = { 0, 0, 1, 0, 0, 1, 0, 0, 1 },
                                    idx = { 0, 1, 2 }, nverts = 3, ntris = 1 }
            end
            pcall(function()
                local h = lib.spawn_actor(world, { X = lib.OFFSET.X, Y = lib.OFFSET.Y, Z = lib.OFFSET.Z - 90000.0 }, 0.0)
                if not h then return end
                lib.keep[h:GetAddress()] = "skin"
                pcall(function() h:SetActorEnableCollision(false) end)
                local pmc = lib.add_pmc(h)
                if pmc then lib.add_sections(world, pmc, secs) end
                pcall(function() h:SetActorHiddenInGame(true) end)
                fr.actors[#fr.actors + 1] = h
            end)
            fr.next = fr.next + FR.load
            if fr.next >= FR.n then log("skin: the RAINBOW's %d pictures in", FR.n) end
        elseif plook and plook.anim and #plook.anim > 0 then
            local k = math.floor(os.clock() * FR.fps) % FR.n
            if k ~= skin.fk or plook ~= skin.fk_look then
                skin.fk, skin.fk_look = k, plook
                local tex = lib.texture(world, string.format(FR.name, k))
                if tex and tex:IsValid() then
                    for _, e in ipairs(plook.anim) do
                        if e.mid and e.mid:IsValid() then
                            for _, n in ipairs(e.names) do pcall(function() e.mid:SetTextureParameterValue(FName(n), tex) end) end
                        end
                    end
                end
            end
        end
    elseif skin.fr and not rb_on then
        for _, h in ipairs(skin.fr.actors) do
            pcall(function() lib.keep[h:GetAddress()] = nil end)
            pcall(lib.destroy, h, false)
        end
        skin.fr = nil
    end
    -- (the pieces' liquid moved only while it is on the pieces it was laid on: a material on no face is thrown away)
    local cur = nil
    if hk == "rainbow" and ML and ML.pmcs then
        local l1 = ML.pmcs()[1]
        cur = l1 and l1:IsValid() and l1:GetAddress() or nil
    end
    if hk == "rainbow" and cur and cur == skin.pieces and skin.pieces_style == "rainbow" and FR then
        local pm = skin.piece_mid
        if pm and pm:IsValid() and skin.fr and skin.fr.next >= FR.n then
            local k = math.floor(os.clock() * FR.fps) % FR.n
            if k ~= skin.pk_k or pm ~= skin.pk_mid then
                skin.pk_k, skin.pk_mid = k, pm
                local tex = lib.texture(world, string.format(FR.name, k))
                if tex and tex:IsValid() then pcall(function() pm:SetTextureParameterValue(FName("BaseColorTexture"), tex) end) end
                local sc = RB.piece_scale or 1.0
                pcall(function() pm:SetVectorParameterValue(FName("BaseColorTexture_OffsetScale"), { R = 0.0, G = 0.0, B = sc, A = sc }) end)
                pcall(function() pm:SetVectorParameterValue(FName("BaseColorFactor"), { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }) end)
            end
        end
    end
    -- (the RAINBOW's glowing eyes: on his own head's eye bones - hidden, it is still posed - built once a scene,
    -- hidden in first person)
    local want_glow = hk == "rainbow" and RB.glow
    if want_glow and not (skin.glow and skin.glow.pawn == pa and skin_alive(skin.glow[1])) then
        if skin.glow then for _, a in ipairs(skin.glow) do pcall(function() lib.keep[a:GetAddress()] = nil end); pcall(lib.destroy, a, false) end end
        skin.glow = nil
        pcall(function()
            local head = nil
            for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.SkeletalMeshComponent"))) do
                local o = c:get()
                if o:GetFName():ToString() == "Head" then head = o end
            end
            if not head then return end
            local G2 = RB.glow
            local function ball()
                local sec = { id = 0, layer = "lit", texture = G2.tex, pos = {}, uv = {}, col = {}, nrm = {}, idx = {}, nverts = 0, ntris = 0 }
                local nu, nv = 12, 8
                for j = 0, nv do
                    local v = -math.pi / 2.0 + j / nv * math.pi
                    for i = 0, nu do
                        local u = i / nu * 2.0 * math.pi
                        local nx, ny, nz = math.cos(v) * math.cos(u), math.cos(v) * math.sin(u), math.sin(v)
                        local P, N, U, K = sec.pos, sec.nrm, sec.uv, sec.col
                        P[#P + 1], P[#P + 2], P[#P + 3] = nx * G2.r, ny * G2.r, nz * G2.r
                        N[#N + 1], N[#N + 2], N[#N + 3] = nx, ny, nz
                        U[#U + 1], U[#U + 2] = i / nu, j / nv
                        K[#K + 1], K[#K + 2], K[#K + 3], K[#K + 4] = 1.0, 1.0, 1.0, 1.0
                        sec.nverts = sec.nverts + 1
                    end
                end
                for j = 0, nv - 1 do
                    for i = 0, nu - 1 do
                        local a0, b0 = j * (nu + 1) + i, (j + 1) * (nu + 1) + i
                        local I = sec.idx
                        I[#I + 1], I[#I + 2], I[#I + 3] = a0, b0 + 1, b0
                        I[#I + 1], I[#I + 2], I[#I + 3] = a0, a0 + 1, b0 + 1
                        sec.ntris = sec.ntris + 2
                    end
                end
                return sec
            end
            local list = { pawn = pa }
            for _, bone in ipairs({ "FACIAL_L_Eye", "FACIAL_R_Eye" }) do
                local a = lib.spawn_actor(world, head:GetSocketLocation(FName(bone)), 0.0)
                if a then
                    pcall(function() a:SetActorEnableCollision(false) end)
                    lib.keep[a:GetAddress()] = "skin"
                    local pmc = lib.add_pmc(a)
                    if pmc then
                        pcall(function() pmc:SetCollisionEnabled(0) end)
                        lib.add_sections(world, pmc, { ball() })
                        pcall(function() pmc:SetCastShadow(false) end)
                    end
                    a:K2_AttachToComponent(head, FName(bone), 2, 2, 2, false)
                    list[#list + 1] = a
                end
            end
            local gm = lib.get_mid(world, "lit", G2.tex)
            if gm then
                local tex = lib.texture(world, G2.tex)
                if tex then pcall(function() gm:SetTextureParameterValue(FName("EmissiveTexture"), tex) end) end
                pcall(function() gm:SetVectorParameterValue(FName("EmissiveFactor"), G2.emissive) end)
            end
            skin.glow = list
            log("skin: the RAINBOW's eyes glowing (%d)", #list)
        end)
    elseif not want_glow and skin.glow then
        for _, a in ipairs(skin.glow) do pcall(function() lib.keep[a:GetAddress()] = nil end); pcall(lib.destroy, a, false) end
        skin.glow = nil
    end
    if skin.glow then
        local fp = false
        local FPV = package.loaded["fp"]
        if FPV and FPV.on then local ok, on = pcall(FPV.on); fp = ok and on == true end
        if fp ~= (skin.glow.fp or false) then
            skin.glow.fp = fp
            for _, a in ipairs(skin.glow) do pcall(function() a:SetActorHiddenInGame(fp) end) end
        end
    end
    skin.hide_t = (skin.hide_t or 0.0) + dt
    if hk == "ghost" and ML and ML.pmcs and (laying or skin.hide_t >= 0.25) then
        skin.hide_t = 0.0
        for _, pmc in ipairs(ML.pmcs()) do
            for id in pairs(M.SKIN_HIDE) do
                pcall(function() if pmc:IsMeshSectionVisible(id) then pmc:SetMeshSectionVisible(id, false) end end)
            end
        end
    end
    -- (the GHOST RUNNER's backpack, with his chest)
    if M.parts.chest ~= "ghost" then
        if skin.pack then skin_pack_drop() end
    elseif not (skin_alive(skin.pack) and skin.pawn == pa) then
        skin_pack_drop()
        local R = package.loaded["race"]
        if R and R.pack_on then
            local ok, pk, star = pcall(R.pack_on, world, pawn)
            if ok and pk then
                skin.pack, skin.star, skin.pawn = pk, star, pa
                pcall(function() lib.keep[pk:GetAddress()] = "skin" end)
                if star and star.actor then pcall(function() lib.keep[star.actor:GetAddress()] = "skin" end) end
                -- (its star rainbow, as Bowser's mega star, the colours running: "also make the star in the bag
                -- rainbow", 2026-11-04 - its eyes as they are)
                if star and star.data then
                    local mid = nil
                    pcall(function() mid = lib.get_mid(world, "opaque", "rainbow_star", 0.92) end)
                    if mid then
                        for i, part in ipairs(star.data.parts) do
                            local comp = star.comps[i]
                            for _, sec in ipairs(part.sections or {}) do
                                if comp and not (sec.texture or ""):find("eye") then pcall(function() comp:SetMaterial(sec.id, mid) end) end
                            end
                        end
                        skin.star_mid = mid
                    end
                end
                log("skin: the GHOST RUNNER's backpack on him")
            elseif not ok then
                log("skin: the backpack: %s", tostring(pk))
            end
        end
    end
    if skin.star and skin.star.actor then
        skin.yaw = (skin.yaw + 90.0 * dt) % 360.0
        pcall(function() skin.star.actor:K2_SetActorRelativeRotation({ Pitch = 0.0, Yaw = skin.yaw, Roll = 0.0 }, false, {}, true) end)
        if skin.star_mid and skin.star_mid:IsValid() then
            skin.rb_t = (skin.rb_t or 0.0) + dt
            local off = { R = (skin.rb_t * 0.12) % 40.0, G = (skin.rb_t * 0.05) % 40.0, B = 1.0, A = 1.0 }
            pcall(function() skin.star_mid:SetVectorParameterValue(FName("BaseColorTexture_OffsetScale"), off) end)
        end
    end
end
-- (any part in a skin: footik.lua lets him go meanwhile, as under the metal cap)
function M.parts_on() return next(M.parts) ~= nil end
-- (the skin's pieces as made, { c, nm } - the copy and the name of the part of his it copies - for footik.lua to lead
-- through a swim: "swimming animation doesnt take hold sometimes", 2026-11-07, in the GHOST RUNNER skin)
function M.skin_parts()
    return plook and plook.comps or nil
end
-- (the GHOST RUNNER's backpack, or nil - footik.lua holds it to the swim's body through a swim: "bag not attached")
function M.skin_pack()
    return skin.pack
end
-- (and his own parts under the skin hidden again - footik.lua, letting him go after a swim, shows his body and head)
function M.skin_rehide()
    local l = plook
    if not l then return end
    for _, x in ipairs(l.hidden or {}) do pcall(function() x:SetVisibility(false, false) end) end
end
-- (in a pause too - game.lua's tick, and M.update with it, stands still under the menus: the CHARACTER tab's choices on
-- him as they are picked, not once the menu shuts - "as your changing through them the outfits should stick",
-- 2026-11-04. footik.lua's copy let go first, as its own tick would)
function M.skin_tick(dt, pawn)
    if next(M.parts) then
        local FT = package.loaded["footik"]
        local fs = FT and FT.debug and FT.debug()
        if fs and fs.on and FT.update then pcall(FT.update, dt, pawn) end
    end
    if next(M.parts) or M.hat or skin.pack or skin.crown or plook or skin.pieces_style then pcall(skin_keep, dt, pawn) end
end
-- one part's skin ("ghost", "rainbow", or nil / "none" for none)
function M.set_part(part, kind)
    if kind == "none" then kind = nil end
    if not M.PART_COMPS[part] or M.parts[part] == kind then return end
    M.parts[part] = kind
    log("skin: %s %s", part, tostring(kind or "none"))
end
-- (all four at once)
function M.set_skin(kind) for _, p in ipairs({ "head", "chest", "legs", "feet" }) do M.set_part(p, kind) end end
function M.set_hat(kind)
    if kind == "none" then kind = nil end
    if M.hat == kind then return end
    M.hat = kind
    log("skin: hat %s", tostring(kind or "none"))
end
-- (his clothes changed: the parts' copies made again from them, `after` s on)
function M.skin_refresh(after)
    if next(M.parts) then skin.rebuild_at = os.clock() + (after or 0.6) end
end

-- the cap off: `quiet`, no tune back (another cap or the scene going)
function M.stop(quiet)
    if not M.kind then return end
    local had = M.kinds
    M.kind, M.kinds, M.left = nil, {}, 0.0
    if had.vanish and H.vanish_walls then pcall(H.vanish_walls, true) end
    if glide then
        glide = false
        pcall(function() lib.pawn().CharacterMovement.GravityScale = 1.0 end)
    end
    stop_flicker()
    drop_look(true)
    drop_wing()
    if not quiet and H.music_back then pcall(H.music_back) end
    local off = {}
    for _, k in ipairs({ "wing", "metal", "vanish" }) do if had[k] then off[#off + 1] = k end end
    log("cap: %s off", table.concat(off, " + "))
end

-- (a new map: his look's actor went with it)
function M.forget() look, wlook, glide, flick, slowed, softened = nil, nil, false, nil, false, false; M.kind, M.kinds, M.left = nil, {}, 0.0 end

function M.update(dt, pawn)
    if next(M.parts) or M.hat or skin.pack or skin.crown or plook or skin.pieces_style then pcall(skin_keep, dt, pawn) end
    if not M.kind then return end
    M.left = M.left - dt
    if M.left <= 0.0 then M.stop(false); return end
    if look and pawn and pawn:GetAddress() ~= look.pawn then drop_look(false); pcall(make_look, "metal") end
    if wlook and pawn and pawn:GetAddress() ~= wlook.pawn then drop_wing(); pcall(make_look, "wing") end
    -- (the Wing Cap hidden from first person's view, as mariolook.lua hides his own cap: on his head bone it sat in the
    -- camera - "when using wing cap the hats in the camera", 2026-10-22)
    if wlook and wlook.actor then
        local FPV = package.loaded["fp"]
        local fp = false
        if FPV and FPV.on then
            local ok, on = pcall(FPV.on)
            fp = ok and on == true
        end
        if fp ~= (wlook.fp_hidden or false) then
            wlook.fp_hidden = fp
            pcall(function() wlook.actor:SetActorHiddenInGame(fp) end)
        end
    end
    -- (the chrome on his cap, nose and mustache, laid again as the camera turns: mariolook.lua)
    if M.kinds.metal and look then
        local ML = package.loaded["mariolook"]
        if ML and ML.chrome_tick then pcall(ML.chrome_tick, dt) end
    end
    if flick and pawn then
        if pawn:GetAddress() ~= flick.pawn then flick = nil; pcall(start_flicker)
        else
            if flick.timed then
                local on = math.floor(os.clock() * 20.0) % 2 == 0
                if on ~= flick.on then
                    flick.on = on
                    pcall(function() flick.actor:SetActorHiddenInGame(not on) end)
                    for _, c in ipairs(flick.comps) do pcall(function() c:SetVisibility(on, false) end) end
                end
            else
                flick.on = not flick.on
                local on = flick.on
                for _, c in ipairs(flick.comps) do pcall(function() c:SetVisibility(on, false) end) end
                if flick.actor then pcall(function() flick.actor:SetActorHiddenInGame(not on) end) end
            end
        end
    end
    -- his fall slowed: the wing cap's glide (holding A while falling) and the metal cap's sinking in water (Mario 64's
    -- metal Mario sinks and walks the bottom). STORROR knocks him flat on landing from a big drop (from where its fall
    -- began, however slow): just above the floor its parkour state is reset (ParkourComponent SimpleReset), and the
    -- landing is a short one. Only for a fall the cap slowed - its own bails are left alone otherwise.
    if pawn and (M.kinds.wing or M.kinds.metal) then
        local pad = package.loaded["pad"]
        local falling, want, scale, cap = false, false, 1.0, 0.0
        pcall(function()
            local cm = pawn.CharacterMovement
            falling = cm:IsFalling()
            if not falling or (H.busy and H.busy()) then return end
            -- (metal in the water first: it sinks him, wing cap or not)
            if M.kinds.metal and H.under_water and H.under_water() then want, scale, cap = true, 0.35, -360.0
            elseif M.kinds.wing and pad and pad.down("ok") then want, scale, cap = true, 0.25, -300.0 end
        end)
        -- (metal, falling into the water: straight down - his way across gone as he goes in, Mario 64's
        -- act_metal_water_falling sinking at 16 a frame; "metal cap doesnt make the player fall straight down in water",
        -- 2026-10-18. A jump off the bottom keeps its push.)
        local entering = want and M.kinds.metal and not was_under
        was_under = M.kinds.metal and H.under_water and H.under_water() or false
        pcall(function()
            local cm = pawn.CharacterMovement
            if want then
                cm.GravityScale = scale
                local v = cm.Velocity
                if entering then cm.Velocity = { X = 0.0, Y = 0.0, Z = math.max(v.Z, cap) }
                elseif v.Z < cap then cm.Velocity = { X = v.X, Y = v.Y, Z = cap } end
            elseif glide then
                cm.GravityScale = 1.0
            end
        end)
        glide = want
        if want then slowed = true end
        if not falling then
            slowed, softened = false, false
        elseif slowed and not softened and H.above_floor and H.above_floor() < 60.0 and H.parkour_reset then
            softened = true
            pcall(H.parkour_reset)
        end
    end
end

return M
