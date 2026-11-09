p = r'X:\mashup-work\enemies.lua'
s = open(p, encoding='utf-8').read()
def rep(a, b):
    global s
    assert s.count(a) == 1, (a[:80], s.count(a))
    s = s.replace(a, b, 1)
# init: a spawner waits hidden
rep('''    -- (the other Klepto, acts 2 to 6: after Mario's cap - mariocap.lua)''', '''    -- (a Scuttlebug spawner: nothing to see till it throws its Scuttlebug out - scuttlebug.inc.c)
    if o.type == "bhvScuttlebugSpawn" then
        e.sp = "wait"
        pcall(function() inst.actor:SetActorHiddenInGame(true) end)
    end
    -- (the other Klepto, acts 2 to 6: after Mario's cap - mariocap.lua)''')
# step: the spawner's wait and the throw
rep('''local function step_walker(e, m, pawn, world)''', '''-- A Scuttlebug spawner (bhv_scuttlebug_spawn_loop, HMC): unseen where it stands, and still; 30 frames on, with Mario
-- between 500 and 1500 off, out comes its Scuttlebug with its alert - up at 80 and on at 30 toward him - which from
-- then on is a Scuttlebug like any. (It was drawn as one and walked about from the start: one stepped off its ledge,
-- 33 m over the cave floor, and fell for good, 2026-10-18.)
local function spawner_wait(e, m)
    e.sp_t = (e.sp_t or 0) + 1
    if e.sp_t > 30 and m.dist > 500.0 and m.dist < 1500.0 then
        e.sp = "out"
        pcall(function() e.inst.actor:SetActorHiddenInGame(false) end)
        e.yaw = s16(m.angle)
        e.vy, e.fvel, e.ground = 80.0, 30.0, false
        sound("en_scuttlebug_alert", loudness(e, m))
        return false
    end
    return true
end

local function step_walker(e, m, pawn, world)
    if e.sp == "wait" and spawner_wait(e, m) then return end''')
open(p, 'w', encoding='utf-8').write(s)
print('ok')
