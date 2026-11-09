-- SM64Map: the sounds Mario 64's levels keep going from fixed spots (bhvWaterfallSoundLoop, bhvSandSoundLoop,
-- bhvVolcanoSoundLoop, bhvBirdsSoundLoop, bhvAmbientSounds): Tall, Tall Mountain's and the Cavern of the Metal Cap's
-- waterfalls, Shifting Sand Land's moving sand, Lethal Lava Land's volcano, the courtyard's birds and breeze (asked
-- 2026-10-14 overnight: "all the audio from the original mario 64"). Each is a held, looping sound (sfx.lua),
-- louder the nearer the athlete. (The castle grounds have their own, in scenery.lua and music.lua.)
local lib = require("lib")
local OFFSET = lib.OFFSET

local M = { list = {}, kinds = { sound_loop = true } }
local S = 0.75
-- the loop each plays and how far it carries (Mario 64 units)
local SOUNDS = {
    waterfall = { "loop_waterfall", 4500.0 }, sand = { "loop_sand", 3500.0 }, volcano = { "loop_volcano", 12000.0 },
    birds = { "loop_birds", 7000.0 }, ambient = { "loop_outdoors", 20000.0 },
}

function M.setup() end

function M.add(world, o)
    local G = package.loaded["game"]
    if G and G.name == "grounds" then return end
    local s = SOUNDS[o.sound or ""]
    if s and o.sm64 then M.list[#M.list + 1] = { name = s[1], reach = s[2], x = o.sm64[1], y = o.sm64[2], z = o.sm64[3] } end
end

function M.clear() M.list = {} end
function M.forget() M.list = {} end

function M.update(dt, px, py, pz)
    if #M.list == 0 then return end
    local SFX = package.loaded["sfx"]
    if not (SFX and SFX.hold) then return end
    local mx, my, mz = (py - OFFSET.Y) / S, (pz - OFFSET.Z) / S, -(px - OFFSET.X) / S
    for _, l in ipairs(M.list) do
        local dx, dy, dz = l.x - mx, l.y - my, l.z - mz
        local k = 1.0 - math.sqrt(dx * dx + dy * dy + dz * dz) / l.reach
        -- (at the player's MARIO 64 MUSIC setting, as the outdoors' other sounds: music.lua)
        local MU = package.loaded["music"]
        local u = (type(MU) == "table" and MU.user) or 1.0
        if k > 0.0 then SFX.hold(l.name, k ^ 1.5 * u) end
    end
end

return M
