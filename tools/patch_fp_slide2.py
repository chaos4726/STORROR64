import sys
p = 'fp.lua'
s = open(p, encoding='utf-8').read()


def rep(old, new):
    global s
    assert s.count(old) == 1, old[:70]
    s = s.replace(old, new)


rep('''local swim_last = nil                       -- the heading last tick, { yaw, pitch }
''', '''local swim_last = nil                       -- the heading last tick, { yaw, pitch }
-- Sliding (STORROR's slope slide, and slide.lua carrying him on along a flat): "sliding in first person is very hard
-- because the camera keeps moving around" (2026-10-21), then "the camera just goes everywhere because sometimes the
-- charater spins around while sliding" (2026-10-22). His slide pose leans and sways him (taken for a flip: the view
-- tipped and rolled with him), STORROR spins him round on the slope, his head swings up to 60 cm about him, STORROR
-- tips the view down as he goes, and the view was kept to the way his body faced. While he slides the view is the
-- player's and level: no body turn, not kept to his facing; the pitch held unless the right stick moves it; left alone
-- for SLIDE_DELAY, it comes round to the way he is going (SLIDE_FOLLOW a second, at most SLIDE_MAX degrees a second);
-- the eyes steady over the middle of him, SLIDE_ABOVE over his head's height, risen to quickly and let down slowly.
-- (Tried 2026-10-21 for every move, it tipped flips - his stance was measured in the slide pose; now only while he
-- slides, and his stance is not measured then.)
local SLIDE_DELAY, SLIDE_FOLLOW, SLIDE_MAX = 0.3, 3.0, 150.0
local SLIDE_ABOVE, SLIDE_RISE, SLIDE_SINK = 12.0, 10.0, 2.5
local SLIDE_LINGER = 0.6                    -- seconds still taken as sliding after it (a bump's hop mid-slide)
local slide_t, slide_pitch = nil, nil       -- when last seen sliding; the pitch held
-- Knocked down (STORROR's ragdoll and get-up, ragdoll.lua's knock-downs): the view at his eyes went into the floor
-- with his head ("if the player ragdolls the camera ends up in the floor", 2026-10-22). While he is down the view is
-- STORROR's own camera behind him, his head shown; back to his eyes DOWN_AFTER after he is up, DOWN_BLEND seconds each way.
local DOWN_AFTER, DOWN_BLEND = 0.3, 0.3
local down_t, down_view, back_blend = nil, false, nil
''')

rep('''local function keep_in_front(pc, pawn, rot, grounded, dt)
''', '''-- sliding: STORROR's slope slide, or slide.lua carrying him
local function sliding_now(pawn)
    local yes = false
    pcall(function()
        local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
        local n = (m and m:IsValid()) and m:GetFName():ToString():lower() or ""
        yes = n:find("fallingslide_slope") ~= nil
    end)
    if not yes then
        local S = package.loaded["slide"]
        if type(S) == "table" and S.active then
            local ok, a = pcall(S.active)
            yes = ok and a == true
        end
    end
    return yes
end

-- the view while he slides (returns the control rotation to use): see SLIDE_DELAY
local function slide_view(pc, pawn, dt)
    local step = math.max(dt or 0.016, 0.001)
    local rot = pc:GetControlRotation()
    local yaw, pitch = rot.Yaw, wrap(rot.Pitch)
    if math.abs(analog(pc, "Gamepad_RightY")) > 0.15 or math.abs(analog(pc, "MouseY")) > 0.0 or not slide_pitch then
        slide_pitch = pitch
    end
    pitch = slide_pitch
    local looking = math.abs(analog(pc, "Gamepad_RightX")) > 0.15 or math.abs(analog(pc, "MouseX")) > 0.0
    if looking then quiet = 0.0 else quiet = quiet + step end
    if quiet >= SLIDE_DELAY then
        local v = pawn:GetVelocity()
        if v.X * v.X + v.Y * v.Y > 150.0 * 150.0 then
            local d = wrap(math.atan(v.Y, v.X) * R2D - yaw)
            local turn = d * (1.0 - math.exp(-SLIDE_FOLLOW * step))
            local most = SLIDE_MAX * step
            if turn > most then turn = most elseif turn < -most then turn = -most end
            yaw = yaw + turn
        end
    end
    local kept = { Pitch = pitch, Yaw = yaw, Roll = 0.0 }
    pcall(function() pc:SetControlRotation(kept) end)
    return kept
end

-- down: STORROR's ragdoll or get-up playing, or ragdoll.lua's knock-down
local function down_now(pawn)
    local yes = false
    pcall(function()
        local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
        local n = (m and m:IsValid()) and m:GetFName():ToString():lower() or ""
        yes = n:find("ragdoll") ~= nil or n:find("getup") ~= nil
    end)
    if not yes then
        local R = package.loaded["ragdoll"]
        if type(R) == "table" and R.active == true then yes = true end
    end
    return yes
end
-- his head up off the floor as he stands (lying, between his ragdoll and his get-up, no montage plays)
local function head_up(pawn)
    local ok, up = pcall(function()
        local h = pawn.Mesh:GetSocketLocation(FName("Head"))
        local G = package.loaded["game"]
        local O = lib.OFFSET
        local fz = G and G.floor_z and G.floor_z(h.X - O.X, h.Y - O.Y, h.Z - O.Z)
        if not fz then return true end
        return (h.Z - O.Z) - fz > 110.0
    end)
    return (not ok) or up == true
end

local function keep_in_front(pc, pawn, rot, grounded, dt)
''')

rep('''    was_on = true
    -- (set again every few seconds''', '''    was_on = true
    -- knocked down: STORROR's own camera till he is up (see DOWN_AFTER)
    do
        local now = os.clock()
        if down_now(pawn) or (down_t and not head_up(pawn)) then down_t = now end
        if down_t and now - down_t < DOWN_AFTER then
            if not down_view then
                down_view = true
                pcall(function() pc:SetViewTargetWithBlend(pawn, DOWN_BLEND, 0, 0.0, false) end)
                if valid(head) then pcall(function() head:SetHiddenInGame(false, false) end) end
                head = nil
                hide_body(pawn, false)
                if pitch_was then
                    pcall(function() pc.PlayerCameraManager.ViewPitchMin = pitch_was end)
                    pitch_was = nil
                end
                log("first person: down - STORROR's camera till he is up")
            end
            move_facing, last_d, active, eyes, turned, slide_t = nil, nil, 0.0, nil, nil, nil
            return
        end
        down_t = nil
        if down_view then
            down_view, back_blend = false, DOWN_BLEND
            log("first person: up again")
        end
    end
    -- (set again every few seconds''')

rep('''    local rot
    if sw then
        move_facing = nil
        rot = swim_view(pc, sw, dt)
    elseif climbing then''', '''    -- sliding (see SLIDE_DELAY)
    local now_s = os.clock()
    if not sw and not climbing and sliding_now(pawn) then slide_t = now_s end
    local sliding = slide_t ~= nil and now_s - slide_t < SLIDE_LINGER
    if slide_t and not sliding then
        -- (off the slide: he faces the way the view looks, so it is not swung round to where he faced before)
        slide_t, slide_pitch, recentering, quiet = nil, nil, false, 0.0
        pcall(function()
            local y = pc:GetControlRotation().Yaw
            if math.abs(wrap(y - facing_of(pawn))) > 45.0 then
                pawn:K2_SetActorRotation({ Pitch = 0.0, Yaw = y, Roll = 0.0 }, false)
                facing = y
            end
        end)
    end
    local rot
    if sw then
        move_facing = nil
        rot = swim_view(pc, sw, dt)
    elseif sliding then
        swim_last, move_facing, recentering = nil, nil, false
        rot = slide_view(pc, pawn, dt)
    elseif climbing then''')

rep('''    if sw or climbing then
        last_d, active = nil, 0.0          -- (his laid-out, rocking swimming body is not a flip; nor a climb's bend)''',
    '''    if sw or climbing or sliding then
        last_d, active = nil, 0.0          -- (his laid-out, rocking swimming body is not a flip; nor a climb's bend, nor his slide pose)''')

rep('''    local rel = { X = eye.X - loc.X, Y = eye.Y - loc.Y, Z = eye.Z - loc.Z }
''', '''    local rel = { X = eye.X - loc.X, Y = eye.Y - loc.Y, Z = eye.Z - loc.Z }
    if sliding then rel = { X = 0.0, Y = 0.0, Z = rel.Z + SLIDE_ABOVE } end
''')

rep('''        if climbing then
            k = 1.0 - math.exp(-CLIMB_FOLLOW * step)
            kz = 1.0 - math.exp(-CLIMB_FOLLOW_UP * step)
        elseif rolling then''', '''        if climbing then
            k = 1.0 - math.exp(-CLIMB_FOLLOW * step)
            kz = 1.0 - math.exp(-CLIMB_FOLLOW_UP * step)
        elseif sliding then
            -- (over the middle of him, steady: up at once, so never inside him as he sits up, down slowly)
            k = 1.0 - math.exp(-FOLLOW_GROUND * step)
            kz = 1.0 - math.exp(-((rel.Z > eyes.Z) and SLIDE_RISE or SLIDE_SINK) * step)
        elseif rolling then''')

rep('''    if not same then pcall(function() pc:SetViewTargetWithBlend(cam, 0.0, 0, 0.0, false) end) end''',
    '''    if not same then pcall(function() pc:SetViewTargetWithBlend(cam, back_blend or 0.0, 0, 0.0, false) end) end
    back_blend = nil''')

rep('''    move_facing = nil
end

-- (for checking''', '''    move_facing = nil
    slide_t, slide_pitch, down_t, down_view, back_blend = nil, nil, nil, false, nil
end

-- (for checking''')
open(p, 'w', encoding='utf-8', newline='\n').write(s)

p = 'mariolook.lua'
s = open(p, encoding='utf-8').read()
rep('''            fp = (cam.X - hs.X) ^ 2 + (cam.Y - hs.Y) ^ 2 + (cam.Z - hs.Z) ^ 2 < 45.0 * 45.0''',
    '''            -- (within 100 cm: sliding, fp.lua's eyes sit over the middle of him, up to 60 cm from his swinging head)
            fp = (cam.X - hs.X) ^ 2 + (cam.Y - hs.Y) ^ 2 + (cam.Z - hs.Z) ^ 2 < 100.0 * 100.0''')
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('patched')
