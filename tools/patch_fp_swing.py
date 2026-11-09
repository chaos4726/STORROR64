import sys
for p in ['fp.lua', 'standalone_fp/StorrorFirstPerson/Scripts/fp.lua']:
    s = open(p, encoding='utf-8').read()

    def rep(old, new):
        global s
        assert s.count(old) == 1, (p, old[:70])
        s = s.replace(old, new)

    rep('''    -- (swinging on a bar or a pole - STORROR's own movement mode for it, custom (6), no move playing - it turns the whole
    -- of him round the bar, and the view went round with him up to 115 degrees and back: "when pole swinging the camera
    -- shakes hard and you can see the body", 2026-10-22. The view the player's, as he climbs.)
    pcall(function() if pawn.CharacterMovement.MovementMode == 6 then climbing = true end end)
''', '''    -- (swinging on a bar or a pole - STORROR's own movement mode for it, custom (6), no move playing: it turns the whole
    -- of him round the bar. His chest's turn taken into the view whipped it round and back up to 115 degrees, "when pole
    -- swinging the camera shakes hard and you can see the body"; then held level, the eyes sat in his chest at the top of
    -- each swing, "the eyes dont follow the head on the pole", 2026-10-22. So: the view the player's, swung with him by
    -- the swing itself - his whole body's turn about the bar, a smooth pendulum - and the eyes in front of his swung face.
    -- See SWING_FOLLOW.)
    local swinging = false
    pcall(function()
        if pawn.CharacterMovement.MovementMode == 6 then
            local m = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
            swinging = not (m and m:IsValid())
        end
    end)
''')
    rep('''    elseif climbing or flying then''', '''    elseif climbing or flying or swinging then''')
    rep('''    if sw or climbing or sliding or flying then''', '''    if sw or climbing or sliding or flying or swinging then''')
    rep('''    if angle_of(turned) > 0.05 then view = normalize(mul(turned, view)) end
''', '''    if angle_of(turned) > 0.05 then view = normalize(mul(turned, view)) end
    -- the swing: his turn about the bar from how he hung at its start, eased (SWING_FOLLOW), back to none once off it
    do
        local target = { x = 0, y = 0, z = 0, w = 1 }
        if swinging then
            pcall(function()
                local ar = pawn:K2_GetActorRotation()
                if not swing_yaw then swing_yaw = ar.Yaw end
                target = normalize(mul(quat(ar.Pitch, ar.Yaw, ar.Roll), inv(quat(0.0, swing_yaw, 0.0))))
            end)
        else
            swing_yaw = nil
        end
        local rate = swinging and SWING_FOLLOW or SWING_LEAVE
        swung = swung and toward(swung, target, 1.0 - math.exp(-rate * step)) or target
        if angle_of(swung) > 0.05 then view = normalize(mul(swung, view)) end
    end
''')
    rep('''    local face = quat(0.0, rot.Yaw, 0.0)
    if angle_of(turned) > 0.05 then face = normalize(mul(turned, face)) end
''', '''    local face = quat(0.0, rot.Yaw, 0.0)
    if angle_of(turned) > 0.05 then face = normalize(mul(turned, face)) end
    if swung and angle_of(swung) > 0.05 then face = normalize(mul(swung, face)) end
''')
    rep('''local FLY_AHEAD = 18.0''', '''local SWING_FOLLOW, SWING_LEAVE = 14.0, 6.0  -- how fast the view takes up his swing on a bar, and lets it go after (per second)
local swing_yaw, swung = nil, nil           -- the way he faced as the swing began; the swing as the view has it
local FLY_AHEAD = 18.0''')
    open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('patched')
