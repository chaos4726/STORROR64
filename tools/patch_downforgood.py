p = r'X:/mashup-work/game_cur.lua'
s = open(p, encoding='utf-8').read()


def rep(a, b):
    global s
    assert s.count(a) == 1, (s.count(a), a[:80])
    s = s.replace(a, b)


rep('''function G.knock_down(pawn, vx, vy, vz)
    if not pawn then return end
    local pk = parkour(pawn)
    local ok = pk and pcall(function()
        pk:StartRagdoll(1.0, false)
        pawn.Mesh:AddImpulse({ X = vx, Y = vy, Z = vz }, FName("pelvis"), true)
    end)
    if not ok then lib.bounce(pawn, vx, vy, vz) return end      -- no ragdoll to be had: at least throw him
    G.getup_at, G.getup_tries = os.clock() + 2.2, 0
end

function G.get_up(pawn)
    local pk = pawn and parkour(pawn)
    if pk then pcall(function() pk:TryGetupFromRagdoll() end) end
end''', '''function G.knock_down(pawn, vx, vy, vz)
    if not pawn then return end
    local pk = parkour(pawn)
    local ok = pk and pcall(function()
        pk:StartRagdoll(1.0, false)
        pawn.Mesh:AddImpulse({ X = vx, Y = vy, Z = vz }, FName("pelvis"), true)
    end)
    if not ok then lib.bounce(pawn, vx, vy, vz) return end      -- no ragdoll to be had: at least throw him
    if G.down_for_good then return end
    G.getup_at, G.getup_tries = os.clock() + 2.2, 0
end

function G.get_up(pawn)
    if G.down_for_good then return end
    local pk = pawn and parkour(pawn)
    if pk then pcall(function() pk:TryGetupFromRagdoll() end) end
end

-- Out of power he stays down till the screen has closed on him ("when you loose all your health you cant stand back
-- up", 2026-10-15): no get-up of the mod's (its timer, ragdoll.lua's A), and STORROR's own inputs off. Ended by the
-- death's warp, any arrival, any new scene.
local DOWN_SOURCE = "sm64_out_of_power"
function G.set_down_for_good(on, pawn)
    on = on and true or nil
    if (G.down_for_good or nil) == on then return end
    G.down_for_good = on
    if on then G.getup_at = nil end
    pawn = pawn or lib.pawn()
    local pk = pawn and parkour(pawn)
    if pk then pcall(function() pk:EnableAllParkourInputs(FName(DOWN_SOURCE), not on) end) end
    log("out of power: %s", on and "down for good" or "free to get up again")
end''')
rep('''            G.knock_down(pawn, 0, 0, 300)
            G.getup_at = nil                -- he stays down until the level restarts''',
    '''            G.knock_down(pawn, 0, 0, 300)
            G.set_down_for_good(true, pawn)     -- he stays down until the screen has closed on him''')
rep('''    if HP then HP.health, HP.hurt, HP.mend, HP.grace, HP.dead_t = 0x100, 0, 0, 0.0, nil end
    if pawn then G.get_up(pawn) end
    local w = G.warp[0xF1]''', '''    if HP then HP.health, HP.hurt, HP.mend, HP.grace, HP.dead_t = 0x100, 0, 0, 0.0, nil end
    G.set_down_for_good(false, pawn)
    if pawn then G.get_up(pawn) end
    local w = G.warp[0xF1]''')
rep('''local function settle(pawn)
    pcall(function() pawn.CharacterMovement.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 } end)''',
    '''local function settle(pawn)
    if G.set_down_for_good then G.set_down_for_good(false, pawn) end
    pcall(function() pawn.CharacterMovement.Velocity = { X = 0.0, Y = 0.0, Z = 0.0 } end)''')
rep('''    G.destroy_scene()
    G.name, G.data = name, data''', '''    G.destroy_scene()
    if G.set_down_for_good then pcall(G.set_down_for_good, false) end
    G.name, G.data = name, data''')
open(p, 'w', encoding='utf-8', newline='\n').write(s)

p = r'X:/mashup-work/ragdoll.lua'
s = open(p, encoding='utf-8').read()
rep('''    if now and not s.held and s.t > MIN_DOWN then''', '''    -- (not out of power: then he stays down till the screen closes, game.lua G.set_down_for_good)
    local G = package.loaded["game"]
    if now and not s.held and s.t > MIN_DOWN and not (G and G.down_for_good) then''')
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('ok')
