p = 'fp.lua'
s = open(p, encoding='utf-8').read()


def rep(old, new):
    global s
    assert s.count(old) == 1, old[:80]
    s = s.replace(old, new)


rep('''-- Knocked down (STORROR's ragdoll and get-up, ragdoll.lua's knock-downs): the view at his eyes went into the floor
-- with his head ("if the player ragdolls the camera ends up in the floor", 2026-10-22). While he is down the view is
-- STORROR's own camera behind him, his head shown; back to his eyes DOWN_AFTER after he is up, DOWN_BLEND seconds each way.
local DOWN_AFTER, DOWN_BLEND = 0.3, 0.3
local down_t, down_view, back_blend = nil, false, nil
''', '''-- Knocked down (STORROR's ragdoll and get-up, ragdoll.lua's knock-downs): the view at his eyes went into the floor
-- with his head ("if the player ragdolls the camera ends up in the floor", 2026-10-22). Still first person - STORROR's
-- camera behind him was tried and taken out the same day: "I dont want ragdolling to default to 3rd person? this is a
-- 1st person only mode". While he is down, and DOWN_AFTER after: the view the player's own, not tumbled with his head;
-- the eyes eased after his head (DOWN_EYES a second) and kept DOWN_FLOOR over the floor.
local DOWN_AFTER, DOWN_EYES, DOWN_FLOOR = 0.3, 8.0, 30.0
local down_t = nil
''')

# swept: from a given point (down: his head lifted off the floor)
rep('''local function swept(pawn, p)
    local out = p
    pcall(function()
        local h = pawn.Mesh:GetSocketLocation(FName("Head"))''', '''local function swept(pawn, p, from)
    local out = p
    pcall(function()
        local h = from or pawn.Mesh:GetSocketLocation(FName("Head"))''')

rep('''-- Every tick of the game. `on`: the switch, and nothing else holding the camera.
function M.update(dt, pawn, on)''', '''-- (down: the point `p` (world cm) kept DOWN_FLOOR over the floor under it)
local function lifted(p)
    local G = package.loaded["game"]
    if not (type(G) == "table" and G.floor_z) then return p end
    local O = lib.OFFSET
    local fz = G.floor_z(p.X - O.X, p.Y - O.Y, p.Z - O.Z + 50.0)
    if fz and p.Z - O.Z < fz + DOWN_FLOOR then return { X = p.X, Y = p.Y, Z = fz + DOWN_FLOOR + O.Z } end
    return p
end

-- Every tick of the game. `on`: the switch, and nothing else holding the camera.
function M.update(dt, pawn, on)''')

rep('''    -- knocked down: STORROR's own camera till he is up (see DOWN_AFTER)
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
''', '''    -- knocked down (see DOWN_AFTER)
    local down = false
    do
        local now = os.clock()
        if down_now(pawn) or (down_t and not head_up(pawn)) then down_t = now end
        down = down_t ~= nil and now - down_t < DOWN_AFTER
        if down_t and not down then down_t = nil end
    end
''')

rep('''    if not sw and not climbing and sliding_now(pawn) then slide_t = now_s end''',
    '''    if not sw and not climbing and not down and sliding_now(pawn) then slide_t = now_s end''')

rep('''    elseif climbing then
        -- (the view is the player's alone while he climbs''', '''    elseif climbing or down then
        -- (the view is the player's alone while he climbs''')

rep('''    if sw or climbing or sliding then''', '''    if sw or climbing or sliding or down then''')

rep('''        elseif sliding then
            -- (over the middle of him, steady''', '''        elseif down then
            k = 1.0 - math.exp(-DOWN_EYES * step)
            kz = k
        elseif sliding then
            -- (over the middle of him, steady''')

rep('''        cam:K2_TeleportTo(swept(pawn, want), r)
    end)''', '''        if down then
            -- (from his head lifted off the floor, out to the eyes lifted too: his body round his head may be anywhere)
            local from = lifted(pawn.Mesh:GetSocketLocation(FName("Head")))
            want = lifted({ X = eye.X + off_eye.X, Y = eye.Y + off_eye.Y, Z = eye.Z + off_eye.Z })
            cam:K2_TeleportTo(swept(pawn, want, from), r)
        else
            cam:K2_TeleportTo(swept(pawn, want), r)
        end
    end)''')

rep('''    if not same then pcall(function() pc:SetViewTargetWithBlend(cam, back_blend or 0.0, 0, 0.0, false) end) end
    back_blend = nil''', '''    if not same then pcall(function() pc:SetViewTargetWithBlend(cam, 0.0, 0, 0.0, false) end) end''')

rep('''    if not (was_on and valid(cam)) or down_view then return false end''',
    '''    if not (was_on and valid(cam)) then return false end''')

rep('''    slide_t, slide_pitch, down_t, down_view, back_blend = nil, nil, nil, false, nil''',
    '''    slide_t, slide_pitch, down_t = nil, nil, nil''')

open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('patched')
