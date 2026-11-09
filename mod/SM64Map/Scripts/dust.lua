-- SM64Map: dust at the athlete's feet, where Mario 64 kicks it up (PARTICLE_DUST, mario_actions_moving.c):
--   - landing while still going (common_landing_action: forward speed over 16 a frame),
--   - setting off with the stick well ahead of his speed (act_walking: intendedMag - forwardVel > 16),
--   - stopping from a run (act_braking, act_turning_around),
--   - sliding (common_slide_action: every frame of it).
-- STORROR's running measured for it: 0 to 530 cm/s in 0.4 s, a run of about 560, and a stop drops him to 270 in a
-- frame and to nothing over a quarter second after. One puff a Mario 64 frame (30 a second) while it lasts; the puffs
-- themselves are envfx.lua's (M.dust). ("adding upgrading and improving", 2026-10-18.)
local lib = require("lib")

local M = { enabled = true }

local OFFSET = lib.OFFSET
local FRAME = 1.0 / 30.0
local LAND_SPEED = 16.0 * 30.0 * 0.75   -- cm/s: 16 a frame
local START_TOP = 300.0                 -- cm/s: setting off, under this - about half his run, as 16 is half Mario's 32
local START_GAIN = 20.0                 -- cm/s gained in a Mario frame, at least
local BRAKE_FROM = 350.0                -- cm/s: running at least this fast,
local BRAKE_DROP = 100.0                -- and this much lost in a Mario frame: a stop
local BRAKE_FOR = 0.3                   -- s of dust after it, while he still slides along
local MOVING = 40.0                     -- cm/s: slower than this, nothing

local st = { acc = 0.0, falling = false, fspeed = nil, land = 0, brake = 0.0 }

local function montage(pawn)
    local name = ""
    pcall(function()
        local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
        if m and m:IsValid() then name = m:GetFName():ToString() end
    end)
    return name
end

-- nothing while he swims, rides, climbs, hangs, flies, is carried, or a scene, a menu or a death has him
local function held(G)
    local HP = _G.HEALTH
    local MN = _G.MENU
    if G.swim or G.cutscene or G.dying or G.pending or G.star_dance_st then return true end
    if (HP and HP.dead_t) or (MN and MN.state and MN.state ~= "game") then return true end
    local PA = package.loaded["pause"]
    if PA and (PA.open or (PA.menu_up and PA.menu_up())) and not (PA.online and PA.online()) then return true end
    local P = G.PLAT
    if P and P.in_cannon then return true end
    for _, name in ipairs({ "climb", "poles", "flight", "hoot", "squish" }) do
        local m = package.loaded[name]
        if m and m.active and m.active() then return true end
    end
    local SH = package.loaded["shell"]
    if SH and SH.riding and SH.riding() then return true end
    return false
end

function M.forget() st = { acc = 0.0, falling = false, fspeed = nil, land = 0, brake = 0.0 } end

function M.tick(dt, pawn)
    if not (M.enabled and pawn) or dt <= 0.0 then return end
    local G = package.loaded["game"]
    local EF = package.loaded["envfx"]
    if not (G and EF and EF.dust) then return end
    local v, falling, mode = nil, false, 0
    pcall(function()
        local cm = pawn.CharacterMovement
        v = pawn:GetVelocity()
        falling = cm:IsFalling()
        mode = cm.MovementMode
    end)
    if not v then return end
    local hs = math.sqrt(v.X * v.X + v.Y * v.Y)
    local ground = not falling and mode == 1
    -- (down from a fall, still going: three puffs, a frame apiece)
    if st.falling and ground and hs > LAND_SPEED then st.land = 3 end
    st.falling = falling
    if held(G) then st.land, st.brake, st.fspeed = 0, 0.0, nil; return end
    st.acc = st.acc + dt
    if st.acc < FRAME then return end
    st.acc = math.min(st.acc - FRAME, FRAME)
    local prev = st.fspeed or hs
    st.fspeed = hs
    local gain = hs - prev
    local l = pawn:K2_GetActorLocation()
    local x, y = l.X - OFFSET.X, l.Y - OFFSET.Y
    local feet = l.Z - OFFSET.Z - (G.half or 90.0)
    local fz = G.floor_z and G.floor_z(x, y, feet + 40.0)
    local near = fz and feet - fz < 30.0
    -- (in water to his ankles: its own splashes there, wade_splash)
    for _, r in ipairs(G.water_rects or {}) do
        if x > r.x0 and x < r.x1 and y > r.y0 and y < r.y1 and feet < r.z + 5.0 and (not fz or r.z > fz) then
            st.land, st.brake = 0, 0.0
            return
        end
    end
    local puff = false
    if st.land > 0 then
        st.land = st.land - 1
        if ground then puff = true end
    end
    if ground and prev > BRAKE_FROM and gain < -BRAKE_DROP then st.brake = BRAKE_FOR end
    if st.brake > 0.0 then
        st.brake = st.brake - FRAME
        if not ground then st.brake = 0.0
        elseif hs > MOVING and gain < 5.0 then puff = true end
    end
    if ground and hs > MOVING and hs < START_TOP and gain > START_GAIN then puff = true end
    -- (sliding: STORROR's slide on a slope is a fall with its own montage, the slide courses' slide is slide.lua's)
    if near and hs > MOVING then
        local SL = package.loaded["slide"]
        if montage(pawn):find("Slide") or (SL and SL.active and SL.active()) then puff = true end
    end
    if puff and EF.dust then pcall(EF.dust, x, y, (near and fz) or feet) end
end

return M
