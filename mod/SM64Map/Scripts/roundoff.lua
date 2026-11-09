-- STORROR's roundoff, not cut short: the cause, fixed at its root (2026-10-22).
--
-- At the start of a roundoff STORROR finds where he will land (a trace down ahead of him) and keeps it as the motion
-- warp target "RoundOffLanding", pinned to the floor component it hit (bFollowComponent; TargetRelativeTransform = the
-- spot relative to that component). The target's cached Location, though, is the component's own origin. At 80% of
-- the roundoff (1.26 s) STORROR then drops him into its fall (ParkourComponent StartFallingCallback) unless he is near
-- that cached point. STORROR's own floors are blocks with their origin at the floor, so it works there; the mod's
-- floor is one component per level with its origin at the level's zero, so the roundoff was cut wherever the floor is
-- far from that height (BBH's yard, 1.5 m under it: every one; BBH's rooms, at it: none; the slab tested 2026-10-17,
-- origin at the floor: none).
--
-- So while a roundoff plays, the cached Location is set to where the target really is (the component's place + its
-- relative offset). Nothing else of STORROR's is touched: the roundoff, its turn, landing and chaining are its own.
-- Verified on the user's play: 13 of 13 on the yard floor whole (before: 14 of 14 cut); the one cut left was a real
-- fall off something 3.4 m up. The old catcher (it played the rest of a cut roundoff by hand - "its floating") is in
-- roundoff.catcher_2026-10-22.lua.
local lib = require("lib")
local log = lib.log
local M = { enabled = true }

-- (the catcher's hooks may still be registered from an earlier copy of this module: they do nothing now)
_G.SM64_ROUNDOFF_CUT, _G.SM64_ROUNDOFF_LAND = nil, nil

local MW_CLASS = "MotionWarpingComponent"
local mw = nil                  -- { pawn = address, comp }

local function warping(pawn)
    local a = pawn:GetAddress()
    if mw and mw.pawn == a and mw.comp:IsValid() then return mw.comp end
    mw = nil
    for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
        local o = c:get()
        if o:GetClass():GetFName():ToString() == MW_CLASS then mw = { pawn = a, comp = o }; return o end
    end
end

local function set_landing(pawn)
    local comp = warping(pawn)
    if not comp then return false end
    local done = false
    comp.WarpTargets:ForEach(function(_, e)
        local t = e:get()
        -- (every target pinned to a floor, not the roundoff's own alone: its "Landing" kept the floor's origin too, and
        -- the roundoff was cut at 80% again - "the fix is def not okay the roundoffs are still broken", 2026-11-06)
        if not t.bFollowComponent then return end
        local c = t.Component:Get()
        if not (c and c:IsValid()) then return end
        local cl, cr, cs = c:K2_GetComponentLocation(), c:K2_GetComponentRotation(), c:K2_GetComponentScale()
        -- (the mod's floors are never turned or scaled; anything else is left as STORROR made it)
        if math.abs(cr.Pitch) + math.abs(cr.Yaw) + math.abs(cr.Roll) > 0.01 then return end
        if math.abs(cs.X - 1.0) + math.abs(cs.Y - 1.0) + math.abs(cs.Z - 1.0) > 0.001 then return end
        local rel = t.TargetRelativeTransform.Translation
        local x, y, z = cl.X + rel.X, cl.Y + rel.Y, cl.Z + rel.Z
        local l = t.Location
        if t.Name:ToString() == "RoundOffLanding" then done = true end
        if math.abs(l.X - x) + math.abs(l.Y - y) + math.abs(l.Z - z) > 0.5 then
            t.Location = { X = x, Y = y, Z = z }
        end
    end)
    return done
end

function M.update(dt, pawn)
    if not (M.enabled and pawn) then return end
    local ai = pawn.Mesh:GetAnimInstance()
    local m = ai and ai:GetCurrentActiveMontage()
    if not (m and m:IsValid()) then return end
    if not m:GetFName():ToString():find("^MontageFlipRoundOff_%d") then return end
    -- (STORROR sets the target ~0.4 s in and may set it again; each tick of a roundoff is checked)
    set_landing(pawn)
end

function M.clear() end
function M.forget() mw = nil end

return M
