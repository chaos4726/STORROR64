-- SM64Map: Mario 64's other enemies (asked 2026-10-14, overnight: "work on adding all the enemies to the game").
--
-- Every enemy a level places comes from the exporter as {kind="enemy", type=<its behaviour>, sm64, yaw, geo, scale,
-- bp} (exporter/enemyx.py), its model as actor "geo_<geo>". Mario 64 gives each its own behaviour code; here they
-- are sorted into a handful of kinds that move and fight the way theirs do, each with its own numbers below (speeds
-- in Mario 64 units a frame, at 30 frames a second, as chomp.lua and bobomb.lua):
--   walker   wanders near home, gives chase when the athlete comes close (scuttlebugs, spindrifts, koopas, skeeters,
--            pokeys, spinies, and with a twist bullies, chuckyas and heave-hos)
--   flyer    hovers near home and flies at him (fly guys, swoopers, snufits, klepto)
--   boo      comes after him only while he looks away
--   amp      circles its spot (or homes in), crackling; it cannot be beaten
--   piranha  sleeps until he is near, then bites (fire piranhas spit fire)
--   spitter  stands and shoots at him (fire spitters, Mr. Blizzard, Monty Mole, Mr. I)
--   lakitu   floats over him and throws spinies down
--   npc      stands about (penguins, Toads)
--   decor    a torch flame: burns to the touch
-- Touching one costs its damage and knocks the athlete down; landing on one that can be stomped squashes it, and
-- his attacks (STORROR's push and drop kick) beat the ones that can be beaten. Beaten ones leave coins and come back
-- once he has gone 3000 units away; the bosses among them (big bully, big boos, Whomp King, Wiggler) take several
-- hits and leave their star.
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET

local M = { list = {}, shots = {}, cages = {}, kinds = { enemy = true } }
-- (far creatures drawn less often: beyond this (Mario 64 units, squared - 19 m) from him, every this many frames)
M.LOD_NEAR2, M.LOD_EVERY = 2500.0 * 2500.0, 3
-- (and beyond this - 60 m - every this many)
-- (every 4th: at every 8th they stood still a while and jumped on - "enemies freezing randomly", 2026-11-04)
M.LOD_FAR2, M.LOD_EVERY_FAR = 8000.0 * 8000.0, 4
local S = 0.75
local STEP = 1 / 30
local H = {}

local sqrt, sin, cos, atan, floor, abs, pi, max, min = math.sqrt, math.sin, math.cos, math.atan, math.floor, math.abs, math.pi, math.max, math.min

function M.setup(h) H = h end

-- ------------------------------------------------------------ the kinds of enemy
-- speed / chase: walking and chasing speed; range: how near before it notices him; home: how far it wanders;
-- r, h: its body (radius, height above where it stands); dmg: wedges of power a touch costs; stomp / beat: whether
-- landing on it / attacking it beats it; coins; hits: how many to beat it (bosses); star: leaves the level's star
-- (index from its behaviour parameter) when beaten; snd: its sounds; anim: which of its animations to play
-- (walk, chase, idle, attack: 0-based, as Mario 64 numbers them); fly: height it hovers above home.
local T = {
    -- (met as a goomba is, goomba_box below - "scuttlebugs need goomba hitbox as well", 2026-10-20)
    bhvScuttlebug = { k = "walker", speed = 5, chase = 16, range = 1000, home = 900, r = 130, h = 140, dmg = 1, stomp = true, beat = true, coins = 3,
                      goomba_box = true, wall_r = 80, noshove = true,
                      snd = { alert = "en_scuttle_alert", walk = "en_scuttle_walk", death = "en_dying" }, anim = { walk = 0 } },
    bhvScuttlebugSpawn = { k = "walker", speed = 5, chase = 16, range = 1000, home = 900, r = 130, h = 140, dmg = 1, stomp = true, beat = true, coins = 3,
                      goomba_box = true, wall_r = 80, noshove = true,
                      snd = { alert = "en_scuttle_alert", walk = "en_scuttle_walk", death = "en_dying" }, anim = { walk = 0 } },
    -- (goomba_box: met as a goomba is - see touch; bounce: landed on, Mario 64's INT_SUBTYPE_TWIRL_BOUNCE sends him up 80
    -- a frame, about 6 m, where a stomp is 30 - "these guys need the goomba hitbox also make it if you jump on them it
    -- make you go high up", 2026-10-18)
    bhvSpindrift = { k = "walker", speed = 4, chase = 10, range = 1200, home = 1200, r = 100, h = 160, dmg = 2, stomp = true, beat = true, coins = 3, twirl = 45.0,   -- (sSpindriftHitbox; twirl: twirl.lua bounce_twirl - 45 not Mario 64's 80, see the Fly Guy's)
                     -- (wall_r: bhvSpindrift's SET_OBJ_PHYSICS wall hitbox, 30 - without, they walked through SL's igloo's
                     -- walls: "enemies going through ice walls", 2026-10-26)
                     goomba_box = true, bounce = 1320, noshove = true, wall_r = 30,
                     spin = true, snd = { death = "en_dying" }, anim = { walk = 0 } },
    bhvSmallBully = { k = "walker", bully = true, speed = 5, chase = 20, range = 1000, home = 1000, r = 115, h = 160, dmg = 0, coins = 1,
                      snd = { walk = "en_bully_walk", hit = "en_bully_hit", death = "en_bully_die" }, anim = { walk = 0, chase = 1 } },
    -- (the big bullies' model is drawn twice the small one's already - bully_boss_geo's own scale, 0.75 to 0.375 - and
    -- was doubled again: "he seems very big", 2026-10-19. Its hitbox as the small one's to Mario 64's: 115 round, 235 high)
    bhvBigBully = { k = "walker", bully = true, scale = 1.0, speed = 5, chase = 20, range = 1500, home = 1500, r = 180, h = 300, dmg = 0, coins = 0,
                    boss = true, star = true, snd = { walk = "en_bully_walk", hit = "en_big_bully_hit", death = "en_bully_die" }, anim = { walk = 0, chase = 1 } },
    bhvBigChillBully = { k = "walker", bully = true, scale = 1.0, speed = 5, chase = 20, range = 1500, home = 1500, r = 250, h = 320, dmg = 0, coins = 0,
                         boss = true, star = true, snd = { walk = "en_bully_walk", hit = "en_big_bully_hit", death = "en_bully_die" }, anim = { walk = 0, chase = 1 } },
    bhvSmallChillBully = { k = "walker", bully = true, speed = 5, chase = 20, range = 1500, home = 1500, r = 140, h = 220, dmg = 0, coins = 1,
                           snd = { walk = "en_bully_walk", hit = "en_bully_hit", death = "en_bully_die" }, anim = { walk = 0, chase = 1 } },
    -- (bhv_koopa_init: cur_obj_scale(3.0f); at 1.5 "he's really small", 2026-10-16)
    KoopaTheQuick = { k = "ktq", scale = 3.0, nodrop = false, r = 100, h = 160, anim = { idle = 7, walk = 9 } },
    bhvTweester = { k = "tweester", anim = {} },
    bhvCloud = { k = "fwoosh", nodrop = true, anim = {} },
    bhvSLSnowmanWind = { k = "wind" },
    bhvEyerokBoss = { k = "eyerok", boss = true },
    EyerokHand = { k = "eyerok_hand", boss = true, anim = { idle = 2 } },
    bhvWaterLevelDiamond = { k = "diamond", nodrop = true, anim = {} },
    bhvMips = { k = "mips", boss = true, wades = true, anim = { idle = 0, walk = 1 } },  -- (wades: walk's water rule)
    bhvMadPiano = { k = "piano", nodrop = false, anim = { idle = 0, walk = 1 } },
    bhvHauntedChair = { k = "chair", nodrop = true, anim = { idle = 0 } },
    bhvFlyingBookend = { k = "chair", book = true, nodrop = true, anim = { idle = 1 } },
    bhvBulletBill = { k = "bullet", scale = 0.4, nodrop = true, anim = {} },
    bhvBigBullyWithMinions = { k = "walker", bully = true, scale = 1.0, speed = 5, chase = 20, range = 1500, home = 1500, r = 180, h = 300, dmg = 0, coins = 0,
                    boss = true, star = true, snd = { walk = "en_bully_walk", hit = "en_big_bully_hit", death = "en_bully_die" }, anim = { walk = 0, chase = 1 } },
    -- (twice its model's size: bhv_chuckya_loop's cur_obj_scale(2.0f) - "chuckyas are small", 2026-10-27. Its hitbox,
    -- the script's SET_HITBOX(150, 100), is not scaled with it: hit_s. And slow to turn after him, a quarter of the
    -- walkers' 0x800 a frame - Mario 64's turns 0x400 standing and not at all as it charges (chuckya_act_0); at 0x800 it
    -- kept him in front of it, never got behind to pick up: "lower chuckyas turning speed", 2026-10-27)
    -- (and kept off the level's walls, its body's breadth from them - wall_r: without, it walked through the thin ones,
    -- 2026-10-28)
    bhvChuckya = { k = "walker", thrower = true, scale = 2.0, hit_s = 1.0, turn = 0x200, speed = 6, chase = 12, range = 1200, home = 1000, r = 150, h = 200, dmg = 0, beat = true, coins = 5,
                   wall_r = 120,
                   snd = { loop = "loop_chuckya", death = "en_chuckya_death", throw = "king_throw" }, anim = { walk = 4, attack = 1 } },
    -- (a wind-up toy of its own - M.step_heaveho - at twice its model's size, Mario 64's hitbox (SET_HITBOX(120, 100))
    -- and wall hitbox (200): "chuckyas are small, move fast, and go through walls" - the Heave-Hos, 2026-10-28)
    bhvHeaveHo = { k = "heaveho", tosser = true, scale = 2.0, speed = 10, chase = 10, range = 1500, home = 1000, r = 120, h = 100, dmg = 0, coins = 0,
                   wall_r = 200, wall_slide = true, edge_look = 120.0, sinks = true,
                   snd = { loop = "loop_heaveho", throw = "en_heaveho_toss" }, anim = { walk = 0 } },
    -- (beaten - squashed out of his shell, or a tiny one - he leaves a blue coin: sKoopaHitbox's loot of -1, which
    -- obj_spawn_loot_coins makes a bhvSpawnedBlueCoin. A yellow one before - "dont the turtles usually drop a blue
    -- coin", 2026-10-29)
    bhvKoopa = { k = "walker", scale = 1.5, speed = 4, chase = 4, range = 0, home = 1500, r = 100, h = 160, dmg = 1, stomp = true, beat = true, coins = 0,
                 blue_coin = true, flee = true, sinks = true, buoy = 2.0,          -- (bhvKoopa's buoyancy 2: walk)
                 snd ={ walk = "en_koopa_walk", hit = "en_koopa_hit", death = "en_koopa_death" }, anim = { walk = 9 } },
    bhvPokey = { k = "walker", speed = 3, chase = 6, range = 1200, home = 900, r = 90, h = 300, dmg = 1, stomp = true, beat = true, coins = 0, blue_coin = true,
                 snd = { death = "en_pokey_death" }, anim = {} },
    -- (sinks, buoy: in water down to its floor, slowly - bhvSpiny's buoyancy 2 against its gravity 4; walk)
    bhvSpiny = { k = "walker", speed = 4, chase = 12, range = 1500, home = 3000, r = 90, h = 120, dmg = 1, stomp = false, beat = true, coins = 0,
                 sinks = true, buoy = 2.0, snd = { death = "en_dying" }, anim = { walk = 0 } },
    -- (met as a goomba is - goomba_box, noshove: "they need goomba hitbox", 2026-10-28; its walls: step_skeeter)
    bhvSkeeter = { k = "skeeter", speed = 10, chase = 20, range = 500, home = 1000, r = 180, h = 100, dmg = 2, stomp = true, beat = true, coins = 3,
                   goomba_box = true, noshove = true, wall_r = 180,
                   -- (into the water off the shore, as Mario 64's walk in and skate: walk's water rule took the water's
                   -- edge for a drop, and one making for its home on the water turned back at it, again and again -
                   -- "skeeters still getting stuck", 2026-10-28; step_skeeter floats it on the top once in)
                   wades = true,
                   snd = { walk = "en_skeeter_walk", death = "en_snufit_death" }, anim = { walk = 2, idle = 3 } },
    bhvUkiki = { k = "walker", harmless = true, speed = 8, chase = 0, range = 0, home = 800, r = 80, h = 120, dmg = 0, coins = 0,
                 snd = { walk = "en_ukiki" }, anim = { walk = 0 } },
    -- (bounce: Mario 64's twirl bounce off a Fly Guy, as the Spindrift's - "you should get a big jump up when killing a
    -- shyguy", 2026-10-23)
    bhvFlyGuy = { k = "flyguy", scale = 1.5, r = 70, h = 60, dmg = 2, stomp = true, beat = true, coins = 2, nodrop = true, twirl = 45.0,   -- (sFlyGuyHitbox; twirl: twirl.lua bounce_twirl - 45, some 6 m up: Mario 64's 80 took him 25 m, "shyguy launches player wayy to high", 2026-11-07)
                  goomba_box = true, noshove = true, bounce = 1320,
                  snd = { death = "en_koopa_death", shoot = "en_flame_blown" }, anim = { walk = 0 } },
    -- (and the Swoops: met as a Fly Guy is - "our rule with shyguys where if you jump in the air it will kill them however
    -- being on the ground will damage the player. that needs installed in bats and snufits", 2026-10-25)
    bhvSwoop = { k = "swoop", r = 100, h = 80, dmg = 1, stomp = true, beat = true, coins = 1, nodrop = true,     -- (sSwoopHitbox)
                 shyguy = true, noshove = true, bounce = 1320,
                 snd = { alert = "en_swoop", death = "en_swoop_death" }, anim = { walk = 0, idle = 1 } },
    -- (shyguy: met as a Fly Guy is - beaten when he meets it off the ground, with the twirl bounce; on his feet it hurts
    -- and knocks him flying; never shoved - "we also need to apply the same logic of shy guys to the floating shooting
    -- guys", 2026-10-25)
    bhvSnufit = { k = "snufit", r = 100, h = 60, dmg = 2, beat = true, stomp = true, coins = 2, nodrop = true, goomba_box = true,   -- (sSnufitHitbox)
                  shyguy = true, noshove = true, bounce = 1320,
                  snd = { death = "en_snufit_death", shoot = "en_snufit_shoot" }, anim = {} },
    bhvKlepto = { k = "flyer", circle = 600, speed = 12, range = 0, home = 3000, fly = 600, r = 150, h = 120, dmg = 0, coins = 0,
                  two_sided = { ["actors__klepto__klepto_wing.rgba16"] = true, ["actors__klepto__klepto_wing_flap.rgba16"] = true },
                  afar = true, stay = true,
                  snd = { alert = "en_klepto" }, anim = { walk = 0 } },
    -- (Boos: touched where their body is - r 40 / h 120, the big ones 200 / 360; Mario 64's 140 round hurt him from a
    -- step and a half away, "fix boo collisions", 2026-10-17 - and beaten only from behind: no stomp)
    bhvBoo = { k = "boo", speed = 6, range = 1500, home = 2000, fly = 100, r = 40, h = 120, dmg = 2, beat = true, coins = 1,
               snd = { alert = "en_boo_laugh", death = "en_dying" }, anim = {} },
    -- (the castle's Boo, bhv_boo_in_castle_loop: there only from 12 stars; it waits, laughs as he comes near and flies off
    -- toward the courtyard, fading - harmless, nothing to touch)
    bhvBooInCastle = { k = "boo", guide = true, scale = 2.0, speed = 0, range = 0, home = 0, fly = 0, r = 0, h = 120, dmg = 0,
                       coins = 0, snd = { alert = "en_boo_laugh_long" }, anim = {} },
    -- (the Boo with Big Boo's Haunt in its cage: twice the size, boo_with_cage_act_0's oBooBaseScale 2 - it was a Boo's
    -- own size, "the level boo isnt big", 2026-10-22; the cage keeps its own, obj_copy_pos_and_angle)
    bhvBooWithCage = { k = "boo", cage = true, scale = 2.0, speed = 6, range = 1500, home = 2000, fly = 100, r = 40, h = 120, dmg = 2, beat = true,
                       coins = 0, snd = { alert = "en_boo_laugh", death = "en_dying" }, anim = {} },
    bhvCourtyardBooTriplet = { k = "boo", triplet = true, speed = 6, range = 1500, home = 2000, fly = 100, r = 40, h = 120, dmg = 2,
                               beat = true, coins = 1, snd = { alert = "en_boo_laugh", death = "en_dying" }, anim = {} },
    bhvGhostHuntBoo = { k = "boo", speed = 6, range = 1500, home = 2000, fly = 100, r = 40, h = 120, dmg = 2, beat = true, coins = 1,
               snd = { alert = "en_boo_laugh", death = "en_dying" }, anim = {} },
    bhvBalconyBigBoo = { k = "boo", scale = 3.0, boss = true, star = true, hits = 3, speed = 5, range = 2500, home = 3000, fly = 100, r = 200, h = 360, dmg = 2,
               beat = true, coins = 0, snd = { alert = "en_boo_laugh_long", hit = "en_boo_bounce", death = "en_dying" }, anim = {} },
    bhvGhostHuntBigBoo = { k = "boo", scale = 3.0, boss = true, star = true, hits = 3, speed = 5, range = 2500, home = 3000, fly = 100, r = 200, h = 360, dmg = 2,
               beat = true, coins = 0, snd = { alert = "en_boo_laugh_long", hit = "en_boo_bounce", death = "en_dying" }, anim = {} },
    bhvCirclingAmp = { k = "amp", speed = 0, range = 0, home = 0, fly = 0, r = 100, h = 140, dmg = 1, coins = 0, snd = { loop = "loop_amp" }, anim = { walk = 0 } },
    bhvHomingAmp = { k = "amp", homing = true, speed = 6, range = 1200, home = 1600, fly = 0, r = 100, h = 140, dmg = 1, coins = 0, snd = { loop = "loop_amp" }, anim = { walk = 0 } },
    -- (knock 0.35: a bite knocks him flat with a small bump - "if they hit you make it bump and ragdol you", "a small
    -- bump", 2026-10-17)
    bhvPiranhaPlant = { k = "piranha", knock = 0.35, r = 120, h = 300, dmg = 3, beat = true, stomp = true, coins = 0, blue_coin = true, range = 1200,   -- (piranha_plant_act_shrink_and_die: cur_obj_spawn_loot_blue_coin)
                        snd = { bite = "en_piranha_bite", death = "en_piranha_dying", wake = "en_piranha_appear" }, anim = { idle = 8, attack = 0 } },
    -- (harmless to touch: its flames are its only attack - "remove the fire plants hitbox", "they're only attack will be
    -- the fire they shoot", 2026-10-29. Punched or landed on, beaten as ever.)
    bhvFirePiranhaPlant = { k = "piranha", fire = true, harmless = true, knock = 0.35, r = 120, h = 300, dmg = 2, beat = true, stomp = true, coins = 1, range = 2000,
                        snd = { death = "en_piranha_dying", wake = "en_piranha_appear", shoot = "en_flame_blown" }, anim = { idle = 0, attack = 2 } },
    -- (fire_spitter.inc.c: no hitbox of its own - nothing to touch or beat; where the level puts it, no gravity; drawn
    -- 40 up at a fifth of the bowling ball's size. It was drawn whole, sunk to its middle in the floor, throwing plain
    -- fireballs: "in vanish cap under the moat fix the flame guys", 2026-10-19)
    bhvFireSpitter = { k = "firespit", nodrop = true, scale = 0.4, r = 0, h = 40, dmg = 0, coins = 0,
                       snd = { shoot = "en_flame_blown" }, anim = {} },
    bhvMrBlizzard = { k = "blizzard", r = 65, h = 170, dmg = 2, coins = 3, hop_g = 1.5625,    -- (sMrBlizzardHitbox)
                      snd = { shoot = "en_snowman_bounce", death = "en_snowman_explode" }, anim = { idle = 0 } },
    bhvMontyMole = { k = "mole", r = 70, h = 50, dmg = 2, coins = 0, nodrop = true,           -- (sMontyMoleHitbox)
                     snd = { shoot = "en_mole_attack", alert = "en_mole_appear", death = "en_dying" }, anim = { idle = 1 } },
    -- (Mr. I stays where the level puts it - no gravity in mr_i.inc.c: LLL's, up on its column at 307, was dropped to
    -- the lava under it, "fix the eye", 2026-10-19)
    bhvMrI = { k = "spitter", shot = "ball", rate = 70, range = 1500, r = 150, h = 260, dmg = 1, beat = false, coins = 0, blue_coin = true, look = true, nodrop = true,
               snd = { shoot = "en_mri_shoot", death = "en_mri_death", loop = "loop_mri" }, anim = {} },
    bhvEnemyLakitu = { k = "lakitu", speed = 8, range = 2500, home = 6000, fly = 500, r = 120, h = 160, dmg = 1, beat = true, stomp = true, coins = 5,
                       hit_air = true,                   -- (jumped into from below as well: touch, sEnemyLakituHitbox)
                       snd ={ loop = "loop_lakitu", shoot = "en_lakitu_throw", death = "en_dying" }, anim = { walk = 0 } },
    -- (his head met as a goomba is, by sWigglerHitbox at his size - 60 round, 50 high, hurting within 30 round, 40 high:
    -- "give the head of the wiggler the goomba hitbox", 2026-10-29; his back, touch's by_body)
    bhvWigglerHead = { k = "walker", boss = true, star = true, hits = 3, scale = 4.0, speed = 5, chase = 9, range = 2000, home = 2500, r = 200, h = 300, dmg = 1,
                       stomp = true, coins = 0, goomba_box = { r = 60.0, h = 50.0, hr = 30.0, hh = 40.0 }, turn_k = 30.0, accel = 1.0,
                       -- (his own sounds, made from the ROM: stomped (SOUND_OBJ_WIGGLER_ATTACKED, the last stomp too), his
                       -- steps (LOW_PITCH, HIGH_PITCH once stomped), his hop into the last phase (WIGGLER_JUMP), his shrink
                       -- (ENEMY_DEFEAT_SHRINK), and a bounce off his back (SOUND_ACTION_BOUNCE_OFF_OBJECT) - he had a
                       -- Koopa's hit and nothing else, "no sound queues when fighting him", "no footsteps as well", 2026-10-29)
                       snd = { hit = "wiggler_attacked", final = "wiggler_attacked", death = "en_shrink", walk = "wiggler_step_low",
                               walk_angry = "wiggler_step_high", last_phase = "wiggler_jump", back = "bounce_off",
                               squish = "goomba_stomp_huge" }, anim = { walk = 0 } },
    bhvSmallWhomp = { k = "whomp", hits = 1, r = 0, h = 430, coins = 5, snd = { death = "en_thwomp" }, anim = { walk = 0 } },
    bhvWhompKingBoss = { k = "whomp", king = true, boss = true, star = true, hits = 3, scale = 2.0, r = 0, h = 860, coins = 0,
                         snd = { hit = "whomp_short", death = "king_death" }, anim = { walk = 0 } },
    bhvUnagi = { k = "npc", r = 300, h = 300, dmg = 3, anim = { idle = 0 } },
    bhvBubba = { k = "bubba", r = 300, h = 200, dmg = 1, anim = {}, nodrop = true },     -- (sBubbaHitbox; never beaten)
    bhvSushiShark = { k = "sushi", r = 200, h = 150, dmg = 3, anim = { idle = 0 }, nodrop = true },
    bhvSmallPenguin = { k = "penguin", r = 0, h = 0, dmg = 0, anim = { idle = 0 } },
    -- (scale 4: tuxies_mother_act_0's cur_obj_scale(4.0f) - she was baby-sized, "the mamma penguin is really small",
    -- 2026-10-18)
    bhvTuxiesMother = { k = "npc", r = 0, h = 0, dmg = 0, anim = { idle = 0 }, scale = 4.0 },
    -- (ANIMATE(6) in bhvToadMessage. `face`: his idle pose holds his head a little round to one side, and turned to the
    -- athlete he looked past him - "toads are ... not looking at player correctly", 2026-10-18 - so he turns that much
    -- further)
    bhvToadMessage = { k = "npc", r = 0, h = 0, dmg = 0, anim = { idle = 6 }, face = -0x1400 },
    bhvSeaweed = { k = "decor", drop = true, two_sided = true, anim = { idle = 0 } },
    bhvClamShell = { k = "clam", r = 150, h = 80, dmg = 2, anim = { idle = 0 } },
    bhvFlamethrower = { k = "thrower" },
    bhvFallingPillar = { k = "pillar" },
    bhvBowlingBallSpawner = { k = "balls" },
    bhvBouncingFireball = { k = "spout" },
    bhvFlame = { k = "decor", r = 60, h = 100, dmg = 1, burn = true, anim = {} },
}
M.TYPES = T

-- ------------------------------------------------------------ Mario 64's arithmetic
local function sins(a) return sin(a * pi / 32768.0) end
local function coss(a) return cos(a * pi / 32768.0) end
-- BBH's Boos and Big Boos (boo.inc.c): the minions counted, the Big Boos' stars where Mario 64 puts them
local function copy_type(t, extra)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    for k, v in pairs(extra) do c[k] = v end
    return c
end
T.bhvGhostHuntBoo.minion, T.bhvGhostHuntBoo.stay = "ghost", true
T.bhvGhostHuntBigBoo.waits, T.bhvGhostHuntBigBoo.star_at = "ghost", { 980.0, 1100.0, 250.0 }
T.bhvBalconyBigBoo.star_at = { 700.0, 3200.0, 1900.0 }
T.bhvMerryGoRoundBooManager = { k = "boo_mgr" }
T.bhvBookendSpawn = { k = "book_spawn" }
T.bhvSnowmansBottom = { k = "snow_body", nodrop = true, scale = 0.4, anim = {} }
T.bhvSnowmansHead = { k = "snow_head", nodrop = true, scale = 0.7, anim = {} }
T.SnowmanWhole = { k = "snow_whole", nodrop = true, anim = {} }
T.bhvMantaRay = { k = "manta", nodrop = true, scale = 2.5, anim = { idle = 0 } }
T.bhvJetStreamRingSpawner = { k = "ring_spawner" }
T.WaterRing = { k = "ring", nodrop = true, anim = { idle = 0 } }
T.bhvBigBoulderGenerator = { k = "boulder_gen", afar = true }    -- (it sends them down to him from afar too)
T.BigBoulder = { k = "boulder", nodrop = true, anim = {}, snd = { loop = "loop_snow_roll" } }
T.bhvPitBowlingBall = { k = "boulder", nodrop = true, anim = {}, snd = { loop = "loop_snow_roll" } }
T.bhvWaterBombSpawner = { k = "wbomb_spawner" }
T.CageUkiki = { k = "cage_ukiki", nodrop = true, anim = { idle = 0 } }
-- (and the cap one, step_cap_ukiki - kept off the walls, 30 round, as cur_obj_resolve_wall_collisions keeps him)
T.CapUkiki = setmetatable({ k = "cap_ukiki", wall_r = 30 }, { __index = T.bhvUkiki })
T.WaterBomb = { k = "wbomb", nodrop = true, anim = {} }
-- (met as a goomba is, and so landed on only - goomba_box, noshove: sMoneybagHitbox is INTERACT_BOUNCE_TOP, as
-- sGoombaHitbox - "they also need the same hitboxes as goombas", 2026-10-26)
T.bhvMoneybagHidden = { k = "moneybag", stay = true, r = 120, h = 120, dmg = 2, beat = true, stomp = true, coins = 5,
                        goomba_box = true, noshove = true,
                        snd = { death = "splat" }, anim = { idle = 0 } }
T.bhvMerryGoRoundBoo = copy_type(T.bhvBoo, { minion = "mgr", stay = true, range = 2500, home = 3000 })
T.bhvMerryGoRoundBigBoo = copy_type(T.bhvGhostHuntBigBoo, { waits = false, star_at = { -1600.0, -2100.0, 205.0 } })
-- What the bosses say (handle_special_dialog_text and their behaviours): Wiggler greets him (DIALOG_150), has a word
-- after each stomp (151, 168) and his last (152), each a second after the hit; the Whomp King's last words (115; his
-- greeting is step_whomp's). And where their stars go (spawn_default_star).
T.bhvWigglerHead.words = { start = 150, hits = { 151, 168 }, beaten = 152, delay = 30 }
T.bhvWigglerHead.star_at = { 0.0, 2048.0, 0.0 }
T.bhvWhompKingBoss.words = { beaten = 115, delay = 0 }
T.bhvWhompKingBoss.star_at = { 180.0, 3880.0, 340.0 }
T.bhvBigBully.star_at = { 0.0, 950.0, -6800.0 }
T.bhvBigBullyWithMinions.star_at = { 3700.0, 600.0, -5500.0 }
T.bhvBigChillBully.star_at = { 130.0, 1600.0, -4335.0 }
-- (bosses with no words of their own to start the boss tune - it starts once he is in their range: the user's remixes
-- for the Big Bully, the Chill Bully and the final Big Boo, music_remix/event_boss@<scene>, 2026-11-01)
T.bhvBigBully.boss_tune, T.bhvBigBullyWithMinions.boss_tune, T.bhvBigChillBully.boss_tune = true, true, true
T.bhvBalconyBigBoo.boss_tune = true

local function atan2s(y, x) return atan(x, y) * 32768.0 / pi end
local function s16(a) a = floor(a) % 65536; if a >= 32768 then a = a - 65536 end; return a end
local function turn_toward(cur, target, inc)
    local d = s16(target - cur)
    if d > inc then return s16(cur + inc), false end
    if d < -inc then return s16(cur - inc), false end
    return s16(target), true
end
local function approach(v, target, step)
    if v < target then return min(target, v + step) end
    return max(target, v - step)
end

local function to_scene(x, y, z) return -z * S, x * S, y * S end
local function floor_y(x, y, z)
    if not H.floor_z then return nil end
    local sx, sy = to_scene(x, 0, z)
    local fz = H.floor_z(sx, sy, (y + 250.0) * S)
    return fz and fz / S or nil
end

local function sfx() return package.loaded["sfx"] end
local function sound(name, v)
    local SFX = sfx()
    if name and SFX and (v or 1.0) > 0.02 then pcall(SFX.play, name, v) end
end
local function loudness(e, m, reach)
    local dx, dy, dz = e.x - m.x, e.y - m.y, e.z - m.z
    local k = 1.0 - sqrt(dx * dx + dy * dy + dz * dz) / (reach or 4000.0)
    if k <= 0.0 then return 0.0 end
    return k ^ 1.5
end

-- ------------------------------------------------------------ the athlete
local function attack_of(pawn)
    local name, addr = nil, nil
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        if not (ai and ai:IsValid()) then return end
        local mt = ai:GetCurrentActiveMontage()
        if mt and mt:IsValid() then name, addr = mt:GetFName():ToString(), mt:GetAddress() end
    end)
    if not (name and (name:find("Attack") or name:lower():find("kick") or name:lower():find("push"))) then return nil end
    local air = false
    pcall(function() air = pawn.CharacterMovement:IsFalling() end)
    return { name = name, addr = addr, air = air }
end

local function hurt(e, m, pawn, wedges, why, power, whole)
    local HP = _G.HEALTH
    if HP and (HP.grace > 0 or HP.dead_t) then return false end
    if M.vanished() then return false end
    local G = package.loaded["game"]
    if G and G.getup_at then return false end
    -- (nor while he is down or getting up, nor till he has been on his feet M.REGRAB_GRACE - M.update's M.down_at: a
    -- Skeeter knocked him down again as his get-up began, over and over - "skeeters can combo the player before able to
    -- even stand", 2026-10-28)
    if os.clock() - (M.down_at or -99.0) < M.REGRAB_GRACE then return false end
    if HP and wedges and wedges > 0 then HP.damage(wedges, why) end
    local dx, dz = m.x - e.x, m.z - e.z
    local d = sqrt(dx * dx + dz * dz)
    if d < 1.0 then dx, dz, d = 1.0, 0.0, 1.0 end
    power = power or 1.0
    -- (400 on and 300 up: about 2.5 m - 800 and 450 threw him some 7 m, where Mario 64's knockback is 16 a frame, a
    -- metre or two along the ground: "why is everything in the game doing so much knockback?", 2026-10-31)
    if H.knock_down then pcall(H.knock_down, pawn, -dz / d * 400.0 * power, dx / d * 400.0 * power, 300.0 * power, whole) end
    return true
end

-- Set alight, as Mario 64's flames do (INTERACT_FLAME: Mario burns - burn.lua's run - and the burn is what costs him,
-- not the touch). (fx, fz): the flame, Mario 64 units - he leaps away from it. ("also its doesnt trigger our on fire
-- animation", 2026-10-17: the flamethrower only knocked him down.)
-- (fire does nothing to him under the metal cap - or the vanish cap: Mario 64's interact_flame; "when walking through
-- fire with metal cap you shouldnt be damaged", 2026-10-17)
function M.fireproof()
    local C = package.loaded["caps"]
    return (C and C.on and (C.on("metal") or C.on("vanish"))) and true or false
end
-- (and no harm from them at all under the vanish cap - not hurt, not knocked down: Mario 64's
-- take_damage_and_knock_back, interact_snufit_bullet, interact_shock leave him be while he wears it -
-- "when invis capped enemies should not be able to ragdol the player", 2026-10-26. Stomped, kicked, shoved, grabbed and thrown as ever.)
function M.vanished()
    local C = package.loaded["caps"]
    return (C and C.on and C.on("vanish")) and true or false
end
local function set_alight(e, m, pawn, why, fx, fz)
    if M.fireproof() then return false end
    local B, R = package.loaded["burn"], package.loaded["ragdoll"]
    -- (not turned: Mario 64's interact_flame leaves his facing, and he hops and runs on the way he was going. Turned
    -- away from the flame that touched him he went back into the stream - its flames fly on along it, and the one that
    -- caught him was often past him already: "it turns you around in the wrong direction", 2026-10-17)
    local dx, dy = nil, nil
    if B and B.active then pcall(B.start, dx, dy); return true end
    if R and R.active then return false end
    local HP = _G.HEALTH
    if HP and (HP.grace > 0 or HP.dead_t) then return false end
    local G = package.loaded["game"]
    if G and G.getup_at then return false end
    if os.clock() - (M.down_at or -99.0) < M.REGRAB_GRACE then return false end      -- (down or just up: as hurt)
    if not (B and B.start) then return hurt(e, m, pawn, 1, why, 0.6) end
    -- (in the water it goes out on him: interact_flame - swimming or deep in it, no burn and no cry; burn.lua M.in_water)
    if B.in_water and B.in_water(pawn) then sound("en_flame_blown", 0.8); return false end
    log("set alight by %s", why)
    sound("mario_burn", 1.0)
    pcall(B.start, dx, dy)
    return true
end

M.set_alight = set_alight          -- (platforms.lua's fire bars: set alight, as here)

-- ------------------------------------------------------------ adding them
local function instance(world, data, x, y, z, yaw, scale)
    local sx, sy, sz = to_scene(x, y, z)
    return lib.make_instance(world, data, { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z }, -yaw * 360.0 / 65536.0, scale or 1.0)
end

local function star_index(bp) return ((bp or 0) >> 24) & 0xFF end

-- A torch flame: Mario 64 draws it as a picture facing the camera, eight pictures in turn (two frames each), tinted
-- red-orange (or blue) by the game; the tinted pictures are textures/flame_red_N.png and flame_blue_N.png.
local FLAME_HALF = 25.0 * 7.0 * S          -- its quad, at its scale of 7, in cm
-- (RENDER 96's fire on Mario 64's own torches - scale 7 - this much of burn.lua's usual size: at that it stood 3 m tall and
-- as wide, "flames in hallway of basement are huge", 2026-11-06. The mod's own smaller wall torches as they were.)
M.TORCH_FIRE = 0.45
local function add_flame(world, o, t)
    local x, y, z = o.sm64[1], o.sm64[2], o.sm64[3]
    local color = (o.geo and o.geo:find("blue")) and "blue" or "red"
    local sx, sy, sz = to_scene(x, y, z)
    local e = { t = t, type = o.type, o = o, x = x, y = y, z = z, hx = x, hy = y, hz = z, yaw = 0, fvel = 0.0, vy = 0.0,
                timer = math.random(0, 15), f = 0, action = "home", ground = true, scale = 1.0, sk = 1.0, hp = 1, quads = {}, ang = 0 }
    -- (its size its object's scale: Mario 64's are 7; the mod's own wall torches smaller - game.lua G.EXTRA_HALLS)
    local half = 25.0 * (tonumber(o.scale) or 7.0) * S
    for i = 0, 7 do
        -- (Mario 64's own flame: its eight 32x32 pictures as it draws them, G_CC_FADEA - each one's brightness times the
        -- red flame's (255, 50, 0), its alpha times 200 of 255; the blue's (100, 100, 255) - made smooth at 128, as the
        -- console filters them: the painted flames it had were not its own, "thats not the original texture", and its own
        -- 32x32 ones drawn unfiltered were "a giant orange blob on the wall", 2026-10-18)
        local q = lib.quad_actor(world, { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z }, half, "flame_orig_" .. color .. "_" .. i, "translucent")
        if q then pcall(function() q:SetActorHiddenInGame(true) end) end
        -- (RENDER 96: the fire in the round - burn.lua fire3d_on - on the first picture only, that one always shown
        -- (render_flame): one on each of the eight, swapped two frames apart, the one coming in was still turned as it
        -- was when last seen and jumped - "also very glitchy/ stutter", 2026-11-06)
        e.fseed = e.fseed or math.random() * 6.28
        if i == 0 then
            local BU = package.loaded["burn"]
            if BU and BU.fire3d_on and q then
                local ok, pmc = pcall(BU.fire3d_on, world, q, half, color == "blue", e.fseed,
                    (tonumber(o.scale) or 7.0) >= 5.0 and M.TORCH_FIRE or 1.0)
                if ok and pmc then e.fire3d = true end
            end
        end
        e.quads[i] = q
    end
    e.prev = { x, y, z }
    M.list[#M.list + 1] = e
end

-- A Piranha Plant's two leaves on the ground (piranha_plant_seg6_dl_06015480: G_CULL_BACK cleared, both sides drawn):
-- each one-sided here - one faces down - and right on the floor; they were not to be seen ("parana plant leaves
-- textures are missing", 2026-10-17). Each leaf gets its reversed twin, and both are lifted 2.5 cm off the floor.
local function fix_leaves(data)
    if data.leaves_done then return end
    data.leaves_done = true
    for _, part in ipairs(data.parts or {}) do
        for _, sec in ipairs(part.sections or {}) do
            if sec.texture and sec.texture:find("piranha_plant_leaf", 1, true) then
                local n = sec.nverts
                local pos, nrm, uv, col, idx = sec.pos, sec.nrm, sec.uv, sec.col, sec.idx
                for i = 0, n - 1 do pos[i * 3 + 3] = pos[i * 3 + 3] + 2.5 end
                for i = 0, n - 1 do
                    pos[#pos + 1], pos[#pos + 2], pos[#pos + 3] = pos[i * 3 + 1], pos[i * 3 + 2], pos[i * 3 + 3] - 0.3 * (nrm[i * 3 + 3] or 1.0)
                    nrm[#nrm + 1], nrm[#nrm + 2], nrm[#nrm + 3] = -(nrm[i * 3 + 1] or 0.0), -(nrm[i * 3 + 2] or 0.0), -(nrm[i * 3 + 3] or 1.0)
                    uv[#uv + 1], uv[#uv + 2] = uv[i * 2 + 1], uv[i * 2 + 2]
                    for c = 1, 4 do col[#col + 1] = col[i * 4 + c] end
                end
                local m = #idx
                for t = 0, m // 3 - 1 do
                    idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = idx[t * 3 + 1] + n, idx[t * 3 + 3] + n, idx[t * 3 + 2] + n
                end
                sec.nverts, sec.ntris = n * 2, (sec.ntris or (m // 3)) * 2
            end
        end
    end
end

-- Models Mario 64 draws from both sides (seaweed's ribbons): seen from behind, the engine's cut-out material showed
-- them black. Each triangle gets a reversed twin a hair behind it, facing the other way.
-- (`only`: those textures alone - Klepto's wings, drawn both ways by Mario 64 (gsSPClearGeometryMode(G_CULL_BACK)) and
-- seen from behind not at all: "next the vulture needs work", 2026-10-23)
local function make_two_sided(data, only)
    if data.two_sided_done then return end
    data.two_sided_done = true
    for _, part in ipairs(data.parts or {}) do
        for _, sec in ipairs(part.sections or {}) do
          if not only or only[sec.texture or ""] then
            local n = sec.nverts
            local pos, nrm, uv, col, idx = sec.pos, sec.nrm, sec.uv, sec.col, sec.idx
            for i = 0, n - 1 do
                local nx, ny, nz = nrm[i * 3 + 1] or 0.0, nrm[i * 3 + 2] or 0.0, nrm[i * 3 + 3] or 1.0
                pos[#pos + 1] = pos[i * 3 + 1] - nx * 0.4
                pos[#pos + 1] = pos[i * 3 + 2] - ny * 0.4
                pos[#pos + 1] = pos[i * 3 + 3] - nz * 0.4
                nrm[#nrm + 1], nrm[#nrm + 2], nrm[#nrm + 3] = -nx, -ny, -nz
                uv[#uv + 1], uv[#uv + 2] = uv[i * 2 + 1], uv[i * 2 + 2]
                for c = 1, 4 do col[#col + 1] = col[i * 4 + c] end
            end
            local m = #idx
            for t = 0, m // 3 - 1 do
                idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = idx[t * 3 + 1] + n, idx[t * 3 + 3] + n, idx[t * 3 + 2] + n
            end
            sec.nverts = n * 2
            sec.ntris = (sec.ntris or m // 3) * 2
          end
        end
    end
end

-- (a flamethrower's flames cut short, by level and place: LLL's, the one by the middle, reached 10.7 m across the
-- way - Mario 64's - "one of the burners flames also extend too far and needs to be decrease", 2026-10-19)
-- (then all of LLL's, the volcano's too: "the burner still reached me", 2026-10-19)
local THROWER_REACH = { ["lll:0:-2048"] = 0.6, ["lll_2:2943:10"] = 0.6, ["lll_2:-2759:-1108"] = 0.6, ["lll_2:-2472:-1605"] = 0.6 }
local function add_thrower(world, o, t)
    local x, y, z = o.sm64[1], o.sm64[2], o.sm64[3]
    local e = { t = t, type = o.type, o = o, x = x, y = y, z = z, hx = x, hy = y, hz = z,
                yaw = s16(-(o.yaw or 0.0) * 65536.0 / 360.0), fvel = 0.0, vy = 0.0, timer = 0, f = 0, action = "home",
                ground = true, scale = 1.0, sk = 1.0, hp = 1, bp2 = ((o.bp or 0) >> 16) & 0xFF, act = 0, at = 0,
                flames = {}, thrower = true }
    e.prev = { x, y, z }
    do
        local G = package.loaded["game"]
        e.reach = THROWER_REACH[string.format("%s:%d:%d", tostring(G and G.name), floor(x + 0.5), floor(z + 0.5))]
    end
    if o.path then
        -- a bowling ball spawner (bowling_ball.inc.c): its kind's reach and odds
        e.balls, e.path, e.period, e.stype = {}, o.path, o.period or 128, o.stype or 0
        e.reach = ({ [0] = 7000.0, 8000.0, 6000.0, 12000.0, 12000.0 })[e.stype] or 7000.0
        e.odds = ({ [0] = 2.0, 1.0, 2.0, 1.5, 1.5 })[e.stype] or 2.0
        e.v0 = ({ [0] = 20.0, 10.0, 20.0, 25.0, 10.0 })[e.stype] or 20.0
        e.size = (e.stype == 4) and 0.3 or 1.0
        e.near = o.thi and 800.0 or 1000.0
    end
    M.list[#M.list + 1] = e
    return e
end

-- A flamethrower carried by something else - RR's turning bridge (bhv_rr_rotating_bridge_platform_loop runs
-- bhv_flamethrower_loop on it); `bp2` its kind (1 blue); its owner moves it (x, y, z, yaw: Mario 64 units)
function M.attach_thrower(world, x, y, z, yaw, bp2)
    local e = add_thrower(world, { type = "bhvFlamethrower", sm64 = { x, y, z }, yaw = 0, bp = (bp2 or 0) << 16 }, T.bhvFlamethrower)
    e.yaw = yaw
    return e
end

-- Moved for a course's race star only (game.lua G.extra_act): { [scene] = { [type] = { dx, dz } } }, Mario 64 units.
-- Big Boo's Haunt's piano stood 1.2 m from the race's first flag: 2.5 m further off, the way it already stood from it
-- ("specifically for this star can you move the piano away from the first checkpoint a little", 2026-11-06).
M.RACE_MOVES = { bbh = { bhvMadPiano = { 97.0, -319.0 } } }
function M.add(world, o)
    local t = (o.race and T.KoopaTheQuick) or T[o.type]     -- (Koopa the Quick, and CCM's racing penguin)
    if not (t and o.sm64) then return end
    do
        local G = package.loaded["game"]
        local mv = G and G.extra_act and M.RACE_MOVES[G.name or ""] and M.RACE_MOVES[G.name or ""][o.type]
        if mv then
            -- (a copy of it moved: the level's own data left as it is)
            o = setmetatable({ sm64 = { o.sm64[1] + mv[1], o.sm64[2], o.sm64[3] + mv[2] } }, { __index = o })
        end
    end
    -- (the courtyard Boo with Big Boo's Haunt in its cage only from 12 stars - bhv_boo_with_cage_init,
    -- SPAWN_CASTLE_BOO_STAR_REQUIREMENT: "next doors and locations should be locked until you have the required
    -- stars/keys", 2026-10-20)
    if o.type == "bhvBooWithCage" then
        local MN = _G.MENU
        if ((MN and MN.star_count and MN.star_count()) or 0) < 12 then return end
    end
    if o.type == "bhvFlame" then return add_flame(world, o, t) end
    if o.type == "bhvEyerokBoss" then
        -- the boss itself has no body: its two hands (eyerok_spawn_hand: 500 to either side, 300 ahead)
        local x, y, z = o.sm64[1], o.sm64[2], o.sm64[3]
        local boss = { t = t, type = o.type, o = o, x = x, y = y, z = z, hx = x, hy = y, hz = z, yaw = 0, timer = 0, f = 0,
                       action = "home", hp = 1, scale = 1.0, sk = 1.0, nomodel = true, hands = {}, act = "sleep", at = 0, turn = 0 }
        boss.prev = { x, y, z }
        for _, side in ipairs({ -1, 1 }) do
            local data = H.actor_data and H.actor_data(side < 0 and "geo_eyerok_left_hand_geo" or "geo_eyerok_right_hand_geo")
            local hx, hz = x - 500.0 * side, z + 300.0
            local hy = floor_y(hx, y + 600.0, hz) or y
            local yaw0 = s16(-0x4000 * side)
            local inst = data and instance(world, data, hx, hy, hz, yaw0, 1.5)
            if inst then
                local h = { t = T.EyerokHand, type = "EyerokHand", o = o, inst = inst, x = hx, y = hy, z = hz, hx = hx, hy = hy, hz = hz,
                            yaw = yaw0, yaw0 = yaw0, timer = 0, f = 0, action = "home", hp = 4, scale = 1.5, sk = 1.5,
                            fvel = 0.0, vy = 0.0, ground = true, boss = boss, state = "sleep", st = 0 }
                h.prev = { hx, hy, hz }
                M.list[#M.list + 1] = h
                boss.hands[#boss.hands + 1] = h
            end
        end
        M.list[#M.list + 1] = boss
        return boss
    end
    if o.type == "bhvSLSnowmanWind" or o.type == "bhvMerryGoRoundBooManager" or o.type == "bhvBookendSpawn"
       or o.type == "bhvJetStreamRingSpawner" or o.type == "bhvBigBoulderGenerator" or o.type == "bhvWaterBombSpawner" then
        local x, y, z = o.sm64[1], o.sm64[2], o.sm64[3]
        local w = { t = t, type = o.type, o = o, x = x, y = y, z = z, hx = x, hy = y, hz = z, yaw = s16(-(o.yaw or 0.0) * 65536.0 / 360.0),
                    timer = 0, f = 0, action = "home", hp = 1, scale = 1.0, sk = 1.0, nomodel = true }
        w.prev = { x, y, z }
        M.list[#M.list + 1] = w
        return w
    end
    if o.type == "bhvFlamethrower" or o.type == "bhvBouncingFireball" or o.type == "bhvBowlingBallSpawner" then
        local e = add_thrower(world, o, t)
        return e
    end
    -- the castle's star givers are there only when the file has the stars for them: a Toad with a star to give from
    -- 12, 25 and 35 (bhv_toad_message_init), Mips from 15 for his first star and from 50 for his second, gone once
    -- both are won (bhv_mips_init): his first won, he is not there again until 50 ("make sure after the player grabs
    -- the star from the rabbit he doesnt repsawn until you get 50 stars", 2026-10-19)
    if o.type == "bhvBooInCastle" then
        local MN = _G.MENU
        if ((MN and MN.star_count and MN.star_count()) or 0) < 12 then return end      -- (SPAWN_CASTLE_BOO_STAR_REQUIREMENT)
    end
    if o.type == "bhvToadMessage" or o.type == "bhvMips" then
        local MN = _G.MENU
        local stars = (MN and MN.star_count and MN.star_count()) or 0
        local function won(n) return MN and MN.has_star and MN.has_star("castle:" .. n) end
        if o.type == "bhvToadMessage" then
            local need = ({ [82] = 12, [76] = 25, [83] = 35 })[((o.bp or 0) >> 24) & 0xFF]
            if need and stars < need then return end
        elseif stars >= 15 and not won(3) then o.mips_star = 3
        elseif stars >= 50 and not won(4) then o.mips_star = 4
        else return end
    end
    local data = o.geo and H.actor_data and H.actor_data("geo_" .. o.geo)
    if not data then log("enemy %s: no model (%s)", tostring(o.type), tostring(o.geo)); return end
    if t.two_sided then make_two_sided(data, type(t.two_sided) == "table" and t.two_sided or nil) end
    if t.k == "piranha" then fix_leaves(data) end
    local x, y, z = o.sm64[1], o.sm64[2], o.sm64[3]
    local flies = (t.k == "flyer" or t.k == "boo" or t.k == "amp" or t.k == "lakitu")
    if not flies and not t.nodrop and (t.k ~= "decor" or t.drop) then
        local fy = floor_y(x, y, z)
        if fy and fy > y - 600.0 then y = fy end
    end
    local scale = (o.race and o.race.scale) or t.scale or o.scale or 1.0
    -- (a script's SCALE(0, 0) - bhvSwoop's: it starts at nothing and grows itself, swoop_act_idle - is its size at the
    -- start, not its size: taken as that, the Swoops were drawn at nothing for good - "bats are invisable", 2026-10-20)
    if scale == 0 then scale = 1.0 end
    if o.type == "bhvFirePiranhaPlant" then scale = ((o.bp or 0) >> 16 & 0xFF) ~= 0 and 2.0 or 0.5 end
    -- (the tiny island's Koopa - KOOPA_BP_TINY, bhv_koopa_init: 0.8 its size, 1.6/3 its agility - was drawn at the
    -- full 1.5, as big as the huge island's, 2026-10-29)
    local tiny_koopa = o.type == "bhvKoopa" and (((o.bp or 0) >> 16) & 0xFF) == 4
    if tiny_koopa then scale = 0.8 end
    local yaw = s16(-(o.yaw or 0.0) * 65536.0 / 360.0)
    local inst = instance(world, data, x, y, z, yaw, scale)
    if not inst then return end
    local e = { t = t, type = o.type, o = o, inst = inst, x = x, y = y, z = z, hx = x, hy = y, hz = z, yaw = yaw,
                fvel = 0.0, vy = 0.0, timer = math.random(0, 60), f = math.random(0, 20), action = "home", ground = true,
                scale = scale, hp = t.hits or 1, sk = scale, ang = math.random(0, 65535) }
    if tiny_koopa then e.agility = 1.6 / 3.0 end
    -- (a fire piranha plant starts down in the ground, out of sight - step_fire_piranha; the giant ones, beaten, stay so
    -- for the visit, as Mario 64's OBJ_FLAG_PERSISTENT_RESPAWN keeps them: the star wants five)
    if t.k == "piranha" and t.fire then
        e.fp = { act = "hide", frac = 0.0, t = 0, shown = 0.0 }
        pcall(function() inst.actor:SetActorHiddenInGame(true) end)
        if ((o.bp or 0) >> 16) & 0xFF ~= 0 then e.stay = true end
    end
    -- (posed at once as render() poses it, its walk: one far off is not updated, and was left in the model's bind pose -
    -- the Chuckya lay on its side half in the ground till he came near, 2026-10-29)
    if data.anims and #data.anims > 0 then
        local ta = t.anim or {}
        pcall(lib.pose, inst, data.anims[(ta.walk or ta.idle or 0) + 1] or data.anims[1], e.f)
    end
    -- (Koopa the Quick's finish flag - bhvKoopaRaceEndpoint's child, bhvKoopaFlag: dropped to the floor at the line,
    -- waving; it was never there - "add ... the flag at the end of the level", 2026-10-16)
    if o.race and o.type ~= "bhvRacingPenguin" and o.race.flag and H.actor_data then
        local fd = H.actor_data("geo_koopa_flag_geo")
        local f = o.race.flag
        if fd and not fd.ball_done then
            fd.ball_done = true
            -- (the banner seen from both sides, as Mario 64 draws it - G_CULL_BACK off: "the back of the flag is
            -- invisable"; and a gold ball over the pole's top - its gold cap is flat and the pole's width: "the flag is
            -- missing the ball at the top", 2026-10-16)
            make_two_sided(fd)
            local pole = fd.parts[2]
            if pole and pole.sections and pole.sections[1] then
                local top = -1e9
                for i = 2, #pole.sections[1].pos, 3 do top = max(top, pole.sections[1].pos[i]) end
                local R, cy = 24.0, top + 18.0
                local pos, nrm, uv, col, idx = {}, {}, {}, {}, {}
                local RINGS, SEGS = 6, 10
                for r = 0, RINGS do
                    local th = pi * r / RINGS
                    for sgi = 0, SEGS do
                        local ph = 2.0 * pi * sgi / SEGS
                        local nx, ny, nz = sin(th) * cos(ph), cos(th), sin(th) * sin(ph)
                        pos[#pos + 1], pos[#pos + 2], pos[#pos + 3] = nx * R, cy + ny * R, nz * R
                        nrm[#nrm + 1], nrm[#nrm + 2], nrm[#nrm + 3] = nx, ny, nz
                        uv[#uv + 1], uv[#uv + 2] = 0.0, 0.0
                        local k = 0.65 + 0.35 * max(0.0, ny * 0.7 + nx * 0.3)
                        col[#col + 1], col[#col + 2], col[#col + 3], col[#col + 4] = 0.87 * k, 0.62 * k, 0.12 * k, 1.0
                    end
                end
                for r = 0, RINGS - 1 do
                    for sgi = 0, SEGS - 1 do
                        local a = r * (SEGS + 1) + sgi
                        local b = a + SEGS + 1
                        idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = a, a + 1, b
                        idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = a + 1, b + 1, b
                    end
                end
                local maxid = 0
                for _, sec in ipairs(pole.sections) do maxid = max(maxid, sec.id or 0) end
                pole.sections[#pole.sections + 1] = { id = maxid + 1, layer = "opaque", pos = pos, nrm = nrm, uv = uv, col = col,
                                                      idx = idx, nverts = #pos // 3, ntris = #idx // 3 }
            end
        end
        if fd then
            local fy = floor_y(f[1], f[2] + 100.0, f[3]) or f[2]
            e.flag = instance(world, fd, f[1], fy, f[3], 0, 1.0)
            local fx, fyy, fz = to_scene(f[1], fy, f[3])
            e.flag_at, e.flag_f = { fx + OFFSET.X, fyy + OFFSET.Y, fz + OFFSET.Z }, 0
        end
    end
    if t.k == "whomp" then
        -- the slab of whomp_seg6_collision_06020A0C: 300 wide, from 50 to 430 up, 100 deep behind its face
        local pmc = lib.add_pmc(inst.actor)
        if pmc then
            local pos = {}
            for _, c in ipairs({ { -150, 50, -100 }, { 150, 50, -100 }, { 150, 430, -100 }, { -150, 430, -100 },
                                  { -150, 50, -3 }, { 150, 50, -3 }, { 150, 430, -3 }, { -150, 430, -3 } }) do
                pos[#pos + 1] = -c[3] * S; pos[#pos + 1] = c[1] * S; pos[#pos + 1] = c[2] * S
            end
            -- (each face wound to face out: wound inward, he walked into it and could not get out - "im stuck inside a
            -- walking thwomp" - and fell through its back as it lay flat - "the whomp has no collision on its back",
            -- 2026-10-17)
            local idx = { 0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, 0, 5, 4, 0, 1, 5, 3, 6, 2, 3, 7, 6, 0, 7, 3, 0, 4, 7, 1, 6, 5, 1, 2, 6 }
            lib.add_collision(pmc, { { pos = pos, idx = idx, source = "whomp" } })
            e.slab = pmc
        end
    end
    if o.type == "bhvToadMessage" then
        -- (Mario 64 keeps Mario out of a Toad - check_npc_talk's push_mario_out_of_object, a hitbox 80 round and 100
        -- high, + Mario's 37: here a solid eight-sided post that keeps the athlete as far off; 2026-10-15)
        local pmc = lib.add_pmc(inst.actor)
        if pmc then
            local pos, idx, n, r, h = {}, {}, 8, 70.0, 110.0
            for i = 0, n - 1 do
                local a = i * 2.0 * math.pi / n
                local cx, cz = math.cos(a) * r, math.sin(a) * r
                for _, yy in ipairs({ 0.0, h }) do
                    pos[#pos + 1] = -cz * S; pos[#pos + 1] = cx * S; pos[#pos + 1] = yy * S
                end
            end
            local function tri(a, b, c)         -- (both ways round: a one-sided face can be walked through from behind)
                idx[#idx + 1] = a; idx[#idx + 1] = b; idx[#idx + 1] = c
                idx[#idx + 1] = a; idx[#idx + 1] = c; idx[#idx + 1] = b
            end
            for i = 0, n - 1 do
                local j = (i + 1) % n
                tri(2 * i, 2 * j, 2 * j + 1)
                tri(2 * i, 2 * j + 1, 2 * i + 1)
                if i > 0 and i < n - 1 then tri(1, 2 * i + 1, 2 * j + 1) end
            end
            lib.add_collision(pmc, { { pos = pos, idx = idx, source = "toad" } })
        end
    end
    -- the courtyard's Boo triplets: two more round the first (sCourtyardBooTripletPositions)
    if t.triplet and not o.second then
        for _, d in ipairs({ { 210, 110, 210 }, { -210, 70, -210 } }) do
            local o2 = {}
            for k, v in pairs(o) do o2[k] = v end
            o2.second, o2.sm64 = true, { o.sm64[1] + d[1], o.sm64[2] + d[2], o.sm64[3] + d[3] }
            pcall(M.add, world, o2)
        end
    end
    -- the courtyard Boo's cage, carried until it is beaten
    if t.cage then
        local cdata = H.actor_data and H.actor_data("geo_haunted_cage_geo")
        e.cage = cdata and instance(world, cdata, x, y, z, 0, 1.0) or nil
        e.warp = ((o.bp or 0) >> 16) & 0xFF
    end
    -- turned and sized as the level sets them (seaweed)
    if o.rot then e.yaw, e.pitch, e.roll = s16(o.rot[2]), o.rot[1], o.rot[3] end
    if t.k == "clam" then o.sc3 = o.sc3 or { 1.0, 1.5, 1.0 } end          -- (clam.inc.c: half as tall again)
    if o.sc3 then
        e.sc3 = o.sc3
        pcall(function() inst.actor:SetActorScale3D({ X = o.sc3[3] * scale, Y = o.sc3[1] * scale, Z = o.sc3[2] * scale }) end)
    end
    if t.k == "decor" and data.anims and #data.anims > 0 then e.f = math.random(0, 80) end
    -- circling amps: the radius by their parameter (Mario 64: 200, 300, 400 units)
    if o.type == "bhvCirclingAmp" then e.radius = ({ [0] = 200, 300, 400, 0 })[((o.bp or 0) >> 16) & 3] or 200 end
    -- (where on it it starts, if its object says: the Bowser run's doubled Amps half a turn from their twins - game.lua
    -- G.gauntlet_objects - not on top of them)
    if o.start_ang then e.ang0 = o.start_ang end
    -- CCM's snowman's head: with its star had (and another act), the whole snowman stands there (bhv_snowmans_head_init)
    if t.k == "snow_head" then
        local G, MN = package.loaded["game"], _G.MENU
        local sid = star_index(o.bp)
        if MN and MN.has_star and G and MN.has_star(tostring(G.name) .. ":" .. sid) and G.act ~= sid + 1 then
            e.x, e.y, e.z, e.action = -4230.0, -994.0, 1813.0, "done"
            local bd = H.actor_data and H.actor_data("geo_ccm_geo_0003F0")
            local binst = bd and instance(world, bd, -4230.0, -1344.0 + 180.0, 1813.0, 0, 1.0)
            if binst then
                local w = { t = T.SnowmanWhole, type = "SnowmanWhole", o = o, inst = binst, x = -4230.0, y = -1344.0 + 180.0, z = 1813.0,
                            hx = -4230.0, hy = -1344.0, hz = 1813.0, yaw = 0, timer = 0, f = 0, action = "home", hp = 1, scale = 1.0, sk = 1.0 }
                w.prev = { w.x, w.y, w.z }
                M.list[#M.list + 1] = w
            end
        end
    end
    if t.k == "snow_body" then e.gy, e.y = e.y, e.y + 180.0 * scale end
    -- (the cage Ukiki: the one with no cap to steal)
    if o.type == "bhvUkiki" and ((o.bp or 0) >> 16) & 0xFF == 0 then e.t, e.st = T.CageUkiki, "wait" end
    -- (the eel with the star on its tail: bhv_unagi_init, second parameter byte 1)
    if o.type == "bhvUnagi" and ((o.bp or 0) >> 16) & 0xFF == 1 then e.unagi, e.star_held = true, true end
    -- (the eel of the sunken ship: second parameter byte 0 in act 1 - in the ship till it is roused - and 2 after, already
    -- out swimming the bay: M.step_unagi_ship)
    if o.type == "bhvUnagi" and ((o.bp or 0) >> 16) & 0xFF ~= 1 then
        e.unagi_ship = (((o.bp or 0) >> 16) & 0xFF == 0) and "ship" or "path"
    end
    if o.type == "bhvUnagi" then
        local okc, nc = pcall(M.unagi_solid, e)
        log("the eel: %s", okc and (tostring(nc) .. " parts solid") or ("not solid: " .. tostring(nc)))
    end
    -- (Klepto with the course's star in his talons: bhv_klepto_init, its second parameter byte)
    if o.type == "bhvKlepto" and ((o.bp or 0) >> 16) & 0xFF ~= 0 then e.star_held = true end
    -- (a Scuttlebug spawner: nothing to see till it throws its Scuttlebug out - scuttlebug.inc.c)
    if o.type == "bhvScuttlebugSpawn" then
        e.sp = "wait"
        pcall(function() inst.actor:SetActorHiddenInGame(true) end)
    end
    -- (the other Klepto, acts 2 to 6: after Mario's cap - mariocap.lua)
    if o.type == "bhvKlepto" and ((o.bp or 0) >> 16) & 0xFF == 0 then e.cap_klepto = true end
    -- (Tall Tall Mountain's other Ukiki, UKIKI_BP_CAP: grabbed, he takes Mario's cap - mariocap.lua)
    if o.type == "bhvUkiki" and ((o.bp or 0) >> 16) & 0xFF == 1 then e.cap_ukiki, e.t = true, T.CapUkiki end
    if o.type == "bhvPitBowlingBall" then
        -- (rolling to and fro in its pit: gravity 12, no friction, 28 wherever the floor is flat)
        e.gy = floor_y(x, y, z) or y
        e.vx, e.vz, e.vy, e.grav, e.flat, e.lift, e.reach, e.dmg, e.keep, e.stuck = 0.0, 28.0, 0.0, 12.0, 28.0, 130.0, 200.0, 2, true, 0
        e.y, e.action = e.gy + 130.0, "roll"
    end
    -- LLL's "Bully the Bullies" (bhv_big_bully_with_minions_init): the big bully waits up high, unseen, over three small
    -- bullies it puts on the platform below; all three knocked off, a jingle, and 90 frames on it drops in. (It walked
    -- about from the start, with no minions.)
    if o.type == "bhvBigBullyWithMinions" then
        e.action, e.minions_left = "waiting", 3
        pcall(function() inst.actor:SetActorHiddenInGame(true) end)
        for _, mp in ipairs({ { 4454.0, -5426.0 }, { 3840.0, -6041.0 }, { 3226.0, -5426.0 } }) do
            pcall(M.add, world, { type = "bhvSmallBully", sm64 = { mp[1], 307.0, mp[2] }, yaw = 0, geo = "bully_geo", scale = 1,
                                  bp = 0, minion_boss = e })
        end
    end
    if o.minion_boss then e.from = "minion" end
    -- Wiggler's tail: three body segments behind the head (wiggler_init_segments; each one's walk a step apart)
    if o.type == "bhvWigglerHead" then
        local bd = H.actor_data and H.actor_data("geo_wiggler_body_geo")
        if bd then
            e.segs, e.body = { [0] = { x = x, y = y, z = z, pitch = 0, yaw = yaw } }, {}
            for i = 1, 3 do
                e.segs[i] = { x = x, y = y, z = z, pitch = 0, yaw = yaw }
                local bi = instance(world, bd, x, y, z, yaw, scale)
                if bi then e.body[i] = { inst = bi, f = (23 * i) % 26 } end
            end
        end
        -- (yellow again: his pictures' materials are shared and kept between visits, red from the last fight)
        e.red = true
        pcall(M.wiggler_red, e, false)
    end
    -- Chuckya: the King's hold (bobomb.lua M.hold), its own reach - bhvChuckyaAnchorMario 150 out - and throw (Mario 64's
    -- 40 on and 40 up, a little short of the King's 50 and 50: 560 and 545 here, and "chukyas throw is weak", 2026-10-27 -
    -- half as much again, 840 and 820, a little over the King's; that flew him some 14 m and 3.4 m up, where Mario 64's
    -- carries Mario 6 m and 1.5 m up: "shuckyas launch player further then normal", 2026-10-31 - 620 and 600, about 7.6 m
    -- and 1.8 m up, a little over Mario 64's)
    if o.type == "bhvChuckya" then e.hands, e.hold_out, e.hold_up, e.throw_out, e.throw_up = {}, 120.0, 190.0, 620.0, 600.0 end
    -- Fwoosh: its face twice its size in a cloud of five puffs (cloud_act_spawn_parts: the cloud at 3, its parts at 2/3 of it)
    if o.type == "bhvCloud" then
        e.cloud_s = 2.0
        pcall(function() inst.actor:SetActorScale3D({ X = 2.0, Y = 2.0, Z = 2.0 }) end)
        e.sk = 2.0
    end
    -- Pokey: its head on four body parts, all five three times their size, 120 apart (pokey_act_uninitialized)
    if o.type == "bhvPokey" then
        local bd = H.actor_data and H.actor_data("geo_pokey_body_part_geo")
        pcall(function() inst.actor:SetActorScale3D({ X = 3.0, Y = 3.0, Z = 3.0 }) end)
        e.sk = 3.0
        e.pk, e.parts = { n = 5, bottom = 1.0, regrow = 0, t = 0 }, {}
        for i = 1, 4 do e.parts[i] = bd and instance(world, bd, x, y + (4 - i) * 120.0, z, yaw, 3.0) or nil end
    end
    -- Mr. Blizzard (bhv_mr_blizzard_init): buried in the snow, 200 down - or, MR_BLIZZARD_STYPE_JUMPING, out and hopping
    if o.type == "bhvMrBlizzard" then
        local jumping = (((o.bp or 0) >> 16) & 0xFF) == 1
        e.bz = { act = jumping and "jump" or "spawn", t = 0, gy = jumping and 24.0 or -200.0, gyv = 0.0, wait = 0,
                 diz = 0.0, dizv = 0.0, scale = 1.0, home_d = 0, tyaw = yaw }
        e.pitch, e.roll, e.gfx_y = 0, 0, e.bz.gy
        if not jumping then e.bz_hidden = true; pcall(function() inst.actor:SetActorHiddenInGame(true) end) end
        -- (MR_BLIZZARD_STYPE_CAP: the one who wears Mario's cap when the file says he has it - mariocap.lua)
        e.cap_bz = (((o.bp or 0) >> 16) & 0xFF) == 2
    end
    -- a Monty Mole: in no hole yet, hidden (bhvMontyMole HIDE()); MONTY_MOLE_BP_GENERIC (bp 2nd byte 1) throws rocks
    if o.type == "bhvMontyMole" then
        e.ml = { act = "select", t = 0, grav = 0.0, rock = (((o.bp or 0) >> 16) & 0xFF) == 1 }
        e.ml_hidden = true
        pcall(function() inst.actor:SetActorHiddenInGame(true) end)
    end
    -- Bubba: its open mouth (bubba_geo's second case, oAnimState 1), drawn in its place while it bites
    if o.type == "bhvBubba" then
        local od = H.actor_data and H.actor_data("geo_bubba_open")
        e.open = od and instance(world, od, x, y, z, yaw, scale) or nil
        if e.open then pcall(function() e.open.actor:SetActorHiddenInGame(true) end) end
        e.pitch, e.bb = 0, { act = 0, t = 0, spd = 0.0, tyaw = yaw, tpitch = 0, yv = 0, pv = 0, wt = 0, chomp = 0, mouth = 0 }
    end
    -- a Big Boo that waits for its Boos to be beaten
    if t.waits then
        e.action = "waiting"
        pcall(function() inst.actor:SetActorHiddenInGame(true) end)
    end
    e.prev = { x, y, z }
    -- (a tornado at its own size from the first: left as made - the whole model - till it was first looked at, near him)
    if t.k == "tweester" and M.tweester_size then pcall(M.tweester_size, e, M.TWEESTER_SEEN and 1.0 or 0.0) end
    M.list[#M.list + 1] = e
end

M.boos_beaten = {}

function M.clear()
    do local SH = package.loaded["shock"]; if SH then pcall(SH.forget) end end
    for _, e in ipairs(M.list) do
        if e.inst then lib.destroy(e.inst.actor) end
        if e.open then lib.destroy(e.open.actor) end
        for _, p in ipairs(e.cloud or {}) do lib.destroy(p.actor) end
        for _, w in ipairs(e.wpool or {}) do lib.destroy(w.inst.actor) end
        for _, q in pairs(e.quads or {}) do if q then lib.destroy(q) end end
        for _, q in pairs(e.pool or {}) do if q then lib.destroy(q) end end
        for _, b in ipairs(e.balls or {}) do lib.destroy(b.inst and b.inst.actor) end
        if e.star_inst then lib.destroy(e.star_inst.actor) end
        if e.cap_inst then lib.destroy(e.cap_inst.actor) end      -- (Mario's cap on Klepto, Ukiki or Mr. Blizzard)
        if e.flag then lib.destroy(e.flag.actor) end
        -- (Wiggler's tail and Pokey's body: left standing by a reset of the scene's creatures before, 2026-10-29)
        for _, b in pairs(e.body or {}) do lib.destroy(b.inst and b.inst.actor) end
        for _, p in pairs(e.parts or {}) do lib.destroy(p and p.actor) end
    end
    for _, s in ipairs(M.shots) do
        if s.inst then lib.destroy(s.inst.actor) end
        if s.quad then lib.destroy(s.quad) end
    end
    for _, e in ipairs(M.list) do if e.cage then lib.destroy(e.cage.actor) end end
    for _, c in ipairs(M.cages) do lib.destroy(c.inst and c.inst.actor) end
    -- (a Chuckya holding him lets go: the hold has his controls)
    for _, e in ipairs(M.list) do
        if e.held then
            local BO = package.loaded["bobomb"]
            if BO and BO.hold then pcall(BO.hold.release, e, lib.pawn(), nil) end
        end
    end
    if M.lifting then pcall(M.chuckya_let_go, M.lifting, lib.pawn()) end      -- (and one he carries)
    M.lifting = nil
    M.list, M.shots, M.cages, M.boos_beaten = {}, {}, {}, {}
    M.mole_holes, M.mole_streak = nil, 0
    M.boo_stairs = nil
    M.fpp_killed = 0
end

function M.forget()
    do local SH = package.loaded["shock"]; if SH then pcall(SH.forget) end end
    if M.lifting then pcall(M.chuckya_let_go, M.lifting, lib.pawn()) end
    M.lifting = nil
    M.list, M.shots, M.cages, M.boos_beaten, M.fpp_killed, M.boo_stairs = {}, {}, {}, {}, 0, nil end

-- a dropped Boo cage: it falls to the ground; stepped into, it takes the athlete where its warp node goes (BBH)
local function step_cage(c, m)
    if c.state == "fall" then
        c.vy = math.max(c.vy - 4.0, -75.0)
        c.y = c.y + c.vy
        local fy = floor_y(c.x, c.y + 200.0, c.z)
        if fy and c.y <= fy and c.vy < 0.0 then
            c.y, c.vy, c.state = fy, 0.0, "ground"
            sound("box_land", loudness(c, m, 3000.0))
        end
    elseif c.state == "ground" then
        local dx, dz = m.x - c.x, m.z - c.z
        if dx * dx + dz * dz < 140.0 * 140.0 and m.feet > c.y - 60.0 and m.feet < c.y + 300.0 then
            c.state = "used"
            local G = package.loaded["game"]
            local w = G and G.warp and G.warp[c.warp]
            log("into the Boo's cage: warp %s", tostring(c.warp))
            if w then
                -- (sucked in as Mario is - up, somersaulting, and shrinking into it head first - then the screen goes
                -- white and the star select comes up, as at a painting: twirl.lua M.into_cage)
                local function go()
                    if G.warp_out then G.warp_out("shrink", w.scene, w.node, nil, true) end
                    if not (G.warping or G.pending) then G.goto_scene(w.scene, w.node) end
                end
                local okt, TW = pcall(require, "twirl")
                local sx, sy, sz = to_scene(c.x, c.y, c.z)
                if not (okt and TW.into_cage and TW.into_cage(lib.pawn(), sx, sy, sz, go)) then go() end
            end
        end
    end
end

-- ------------------------------------------------------------ moving
-- along its yaw with gravity onto the floor; a walker stops at ledges and walls (returns true if it landed)
local function walk(e, gravity, careful)
    local x0, z0 = e.x, e.z
    local nx, nz = e.x + e.fvel * sins(e.yaw), e.z + e.fvel * coss(e.yaw)
    e.edge = false
    local fy = floor_y(nx, max(e.y, e.y + e.vy), nz)
    if careful and e.ground and e.fvel ~= 0.0 then
        -- (looked for the way it is going - backwards too, knocked back - and as far out as it is big, `edge_look`: a
        -- Heave-Ho at twice its size went over with half of it past the edge - "Heave ho's fall off ledges", 2026-10-28)
        local look = ((e.t and e.t.edge_look) or 50.0) * (e.fvel > 0.0 and 1.0 or -1.0)
        local ahead = floor_y(nx + look * sins(e.yaw), e.y, nz + look * coss(e.yaw))
        if not ahead or ahead < e.y - 100.0 or ahead > e.y + 100.0 then nx, nz, fy, e.edge = e.x, e.z, floor_y(e.x, e.y, e.z), true end
    end
    -- (and the water kept out of: from dry ground its edge is an edge, as a drop is; one already in it - set down there,
    -- its spot over the water - floats on it as Mario 64's walkers do (their buoyancy), never down on its floor. Snowman's
    -- Land's Spindrifts walked its lake's floor under the water: "enemies in water as well", then "keep them out of it",
    -- 2026-10-26. Not MIPS, who wades: `wades`. `sinks`: kept out of it from dry ground too, but one under it - the water
    -- come up over it - stays down on its floor where it was: WDW's Heave-Hos rose to the top and floated there,
    -- "heave hos floating on water" / "should stay where they were", 2026-10-28.)
    local G = package.loaded["game"]
    local under = false
    if G and G.water_at and not (e.t and e.t.wades) then
        local function wet(x, z, f)
            local sx, sy = to_scene(x, 0, z)
            local top = G.water_at(sx, sy)
            if top and (not f or top / S > f + 1.0) then return top / S end
            return nil
        end
        local wtop = wet(nx, nz, fy)
        if wtop and e.ground and (nx ~= e.x or nz ~= e.z) and not wet(e.x, e.z, floor_y(e.x, e.y, e.z)) then
            nx, nz, fy, e.edge = e.x, e.z, floor_y(e.x, e.y, e.z), true
        elseif wtop and not (e.t and e.t.sinks) then
            fy = wtop
        end
        under = wtop ~= nil and e.y < wtop
    end
    -- (`buoy`: a `sinks` one under the water sinks slower - Mario 64's buoyancy against its gravity, cur_obj_move_y: the
    -- Spinies' and Koopas' 2 of 4, so down at 2 more a frame each frame, to the floor. They floated on top before:
    -- "little shell enemys dont sink into the water", 2026-10-29)
    if under and e.t and e.t.buoy then gravity = (gravity or 4.0) - e.t.buoy end
    e.x, e.z = nx, nz
    -- (its wall hitbox, where it has one - cur_obj_resolve_wall_collisions: walls spanning 10 over its feet push it out to
    -- t.wall_r from them; walking into one, it turns away along it, as update_angle_from_move_flags has it. Without, the
    -- Scuttlebugs walked through the maze's walls - the floor runs on under them: "scuttle bugs walk through walls",
    -- 2026-10-20)
    local wr = e.t and e.t.wall_r
    if wr and H.wall_near then
        local sx, sy, sz = to_scene(e.x, e.y + 10.0, e.z)
        local hit, px, py = H.wall_near(sx, sy, sz, wr * S, 5.0 * S)
        if hit and (px ~= 0.0 or py ~= 0.0) then
            local mx, mz = py / S, -px / S                  -- (the push in Mario 64's x and z)
            e.x, e.z = e.x + mx, e.z + mz
            local wall = s16(atan2s(mz, mx))
            -- (`wall_slide`: not turned off it - it slides along it, as cur_obj_move_standard has Mario 64's: a Heave-Ho
            -- after him beyond a wall was turned off it here and back to him by its own step, every frame - "heave ho's
            -- glitch tf out when hitting walls", 2026-10-28)
            if abs(s16(wall - e.yaw)) > 0x4000 and not (e.t and e.t.wall_slide) then e.yaw = turn_toward(e.yaw, wall, 0x200 * 4) end
        end
        -- (and the moving platforms' sides, as walls: platforms.lua's own boxes, which the level's walls know nothing of -
        -- a step toward one's side, within its wall hitbox, is not taken, and it turns away; a step away from it is. Not
        -- over its top, where it would stand on it. "still going through platforms" - the Heave-Hos, 2026-10-28)
        local PL = package.loaded["platforms"]
        if PL and PL.solid_near and (e.x ~= x0 or e.z ~= z0) then
            local px, py, pz = to_scene(e.x, e.y + 10.0, e.z)
            local okp, hit, ux, uy = pcall(PL.solid_near, px, py, pz, wr * S, 40.0)
            if okp and hit then
                local mx, mz = uy, -ux                          -- (the way out of it, Mario 64's x and z)
                if (e.x - x0) * mx + (e.z - z0) * mz < 0.0 then
                    e.x, e.z = x0, z0
                    local away = s16(atan2s(mz, mx))
                    if abs(s16(away - e.yaw)) > 0x4000 and not e.t.wall_slide then e.yaw = turn_toward(e.yaw, away, 0x200 * 4) end
                end
            end
        end
        -- (and a wall's push not taken over a drop: pushed out along a ledge, a walker went off it)
        if careful and e.ground and (e.x ~= x0 or e.z ~= z0) then
            local f2 = floor_y(e.x, e.y, e.z)
            if not f2 or f2 < e.y - 100.0 then e.x, e.z, fy, e.edge = x0, z0, floor_y(x0, e.y, z0), true end
        end
    end
    e.vy = max(e.vy - (gravity or 4.0), -75.0)
    local ny = e.y + e.vy
    local landed = false
    if fy and ny <= fy then
        if not e.ground then landed = true end
        ny, e.vy, e.ground = fy, 0.0, true
    else
        e.ground = false
    end
    e.y = ny
    return landed
end

-- flying straight toward a point, at most `speed` a frame
local function fly_to(e, tx, ty, tz, speed)
    local dx, dy, dz = tx - e.x, ty - e.y, tz - e.z
    local d = sqrt(dx * dx + dy * dy + dz * dz)
    if d < 1.0 then return d end
    local k = min(1.0, speed / d)
    e.x, e.y, e.z = e.x + dx * k, e.y + dy * k, e.z + dz * k
    e.yaw = turn_toward(e.yaw, s16(atan2s(dz, dx)), 0x800)
    return d
end

-- ------------------------------------------------------------ shots (fire, snowballs, rocks, Mr. I's)
local function shoot(world, e, m, kind)
    local dx, dy, dz = m.x - e.x, (m.y) - (e.y + e.t.h * 0.6), m.z - e.z
    local d = sqrt(dx * dx + dy * dy + dz * dz)
    if d < 1.0 then return end
    local speed = (kind == "fire") and 30.0 or 40.0
    local s = { kind = kind, x = e.x, y = e.y + e.t.h * 0.6, z = e.z, vx = dx / d * speed, vy = dy / d * speed + ((kind == "ball") and 6.0 or 0.0),
                vz = dz / d * speed, life = 120, dmg = e.t.dmg > 0 and e.t.dmg or 1, from = e }
    if kind == "fire" then
        -- (a flame: Mario 64's own, its eight pictures in turn facing the camera, as the fire spitters' are - the red
        -- flame model it was drawn with showed nothing: "when shooting a flame its invisable", 2026-10-27)
        local sx, sy, sz = to_scene(s.x, s.y, s.z)
        s.quad = lib.quad_actor(world, { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z }, 25.0 * S, "flame_sm64_red_0", "translucent")
        do local BU = package.loaded["burn"]; if BU and BU.fire3d_on and s.quad then pcall(BU.fire3d_on, world, s.quad, 25.0 * S, false, nil) end end
        s.frame = 0
    else
        local data = H.actor_data and H.actor_data("geo_bowling_ball_geo")
        if data then s.inst = instance(world, data, s.x, s.y, s.z, 0, 0.25) end
    end
    M.shots[#M.shots + 1] = s
    sound(e.t.snd and e.t.snd.shoot, loudness(e, m))
end

local function step_shots(m, pawn)
    for i = #M.shots, 1, -1 do
        local s = M.shots[i]
        s.life = s.life - 1
        if s.kind == "ball" then s.vy = s.vy - 1.0 end
        if s.kind == "snowball" then
            -- (bhvMrBlizzardSnowball: gravity 3, drag 10 across)
            s.vy = math.max(-78.0, s.vy - 3.0)
            local v = sqrt(s.vx * s.vx + s.vz * s.vz)
            if v > 0.001 then
                local k = math.max(0.0, v - v * v * 0.001) / v
                s.vx, s.vz = s.vx * k, s.vz * k
            end
        end
        if s.kind == "rock" then
            -- (bhvMontyMoleRock: gravity 4, drag 10 across)
            s.vy = math.max(-78.0, s.vy - 4.0)
            local v = sqrt(s.vx * s.vx + s.vz * s.vz)
            if v > 0.001 then
                local k = math.max(0.0, v - v * v * 0.001) / v
                s.vx, s.vz = s.vx * k, s.vz * k
            end
        end
        local ox, oy, oz = s.x, s.y, s.z
        s.x, s.y, s.z = s.x + s.vx, s.y + s.vy, s.z + s.vz
        -- (into a wall, it is gone: the shots' OBJ_MOVE_HIT_WALL - Big Boo's Haunt's Mr. I hit him through the wall of
        -- the next room, 2026-10-18)
        local into_wall = false
        do
            local G = package.loaded["game"]
            if G and G.wall_cut then
                local ax, ay, az = to_scene(ox, oy, oz)
                local bx, by, bz = to_scene(s.x, s.y, s.z)
                local okc, cut = pcall(G.wall_cut, ax, ay, az, bx, by, bz)
                into_wall = okc and cut < 1.0
            end
        end
        local dx, dy, dz = m.x - s.x, m.y - s.y, m.z - s.z
        local hit = not into_wall and dx * dx + dy * dy + dz * dz < 110.0 * 110.0
        local fy = floor_y(s.x, s.y + 50.0, s.z)
        if hit then
            if s.kind == "fire" then
                -- (a flame sets him alight, as Mario 64's interact_flame does - burn.lua's running and hopping: "the fire
                -- should trigger our on fire state", 2026-10-27. Not under the metal or the vanish cap: set_alight)
                set_alight(s, m, pawn, "a flame shot", s.x, s.z)
            else
                hurt(s, m, pawn, s.dmg, "a shot", 0.8)
            end
        end
        if hit or into_wall or s.life <= 0 or (fy and s.y < fy - 20.0) then
            if s.inst then lib.destroy(s.inst.actor) end
            if s.quad then lib.destroy(s.quad) end
            table.remove(M.shots, i)
        end
    end
end

-- LLL's tumbling bridge (bully_act_level_death: the Big Bully's fall puts up bhvLLLTumblingBridge at (0, 154, -5631)):
-- nine planks 128 apart along z from -512, in three steps of 150 down from 450 up - the way up to its star on the column.
-- Each tumbles as he stands on it, and is back once he is 1200 away, as the other levels' are (in Mario 64 LLL's never
-- come back: "the platforms dont respawn?", 2026-10-19). (The star came with nothing to reach it by: "after
-- defeating the big bully the stairs dont spawn", 2026-10-19.)
local LLL_PLANK = "lll_geo_000B80|lll_seg7_collision_0701D21C"
function M.lll_bridge(world)
    local G = package.loaded["game"]
    local PL = package.loaded["platforms"]
    local tpls = G and G.data and G.data.templates
    if not (PL and PL.add and tpls and tpls[LLL_PLANK]) then log("LLL bridge: no plank to build it of"); return end
    local n = 0
    for i = 0, 8 do
        local y = 154.0 + 450.0 - 150.0 * (floor(i / 3) + 1)
        local ok, p = pcall(PL.add, world, { kind = "platform", bhv = "tumble_plank", tpl = LLL_PLANK, pos = { 0.0, y, -5631.0 - 512.0 + 128.0 * i },
                                             ang = { 0, 0, 0 }, bp = 0, delay = 30 }, tpls)
        if ok and p then n = n + 1 end
    end
    log("LLL bridge: %d planks up to the Big Bully's star", n)
end

-- ------------------------------------------------------------ being beaten
local function boss_music(on)
    local MUSIC = package.loaded["music"]
    if not (MUSIC and MUSIC.play) or (M.boss_music or false) == on then return end
    M.boss_music = on
    if on then pcall(MUSIC.play, "event_boss")
    else pcall(MUSIC.play, (_G.SM64 and _G.SM64.data and _G.SM64.data.music) or nil) end
end

-- The camera of Mario 64's CUTSCENE_DIALOG on whoever speaks (cur_obj_update_dialog_with_cutscene: the Whomp King,
-- Koopa the Quick, Wiggler, Eyerok, the snowmen, the penguins, Ukiki, Mips - as King Bob-omb has had it; game.lua
-- G.dialog_cut): over the athlete's shoulder, the speaker in the picture. Its size from its hitbox (a slab like the Whomp
-- King, with no round, by its height).
local function talk_cam(e)
    local G = package.loaded["game"]
    if not (e and G and G.dialog_cut) then return end
    local t = e.t or {}
    local sx, sy, sz = to_scene(e.x, e.y, e.z)
    local h = (t.h or 100.0) * S
    local r = math.max((t.r or 0.0) * (e.scale or t.scale or 1.0), (t.h or 0.0) * 0.4) * S
    pcall(G.dialog_cut, sx, sy, sz, h, r)
end

-- Mario 64's messages (dialog.lua, through game.lua's G.say): done() once read; e: who says it, with the cutscene
local function say(id, done, e)
    local G = package.loaded["game"]
    if G and G.say then
        local ok = G.say(id, done)
        if ok and e then talk_cam(e) end
        return ok
    end
    if done then done() end
    return false
end

-- A question (game.lua G.ask): done(1) or done(2), its answer; e as for say
local function ask(id, done, e)
    local G = package.loaded["game"]
    if G and G.ask then
        local ok = G.ask(id, done)
        if ok and e then talk_cam(e) end
        return ok
    end
    if done then done(1) end
    return false
end

-- A boss's words, as Mario 64 has them (t.words): his greeting once the athlete comes near (start; the boss tune once
-- it is read, handle_special_dialog_text), and the word due after a hit (e.words_due, `n` frames on)
local function words_tick(e, m)
    local w = e.t.words
    e.seen = (e.seen or 0) + 1                  -- (not in the scene's first moment: the athlete maybe not yet put down)
    -- (and on his feet: Mario 64 starts it once Mario can talk, not in the air - Wiggler greeted him halfway down the
    -- drop into his room and held him there, 2026-10-29. Nor while he is still arriving: held still in the air for the
    -- screen's opening he is not falling, game.lua G.entry till he lands)
    local Gw = package.loaded["game"]
    -- (his feet, as Mario 64's oPosY: by his middle he was 7 cm in reach from the red coin cave's high platform, under
    -- Wiggler's room, and Wiggler talked to him through the ceiling, 2026-10-29)
    if w.start and not e.greeted and e.seen > 15 and m.dist < (w.near or 1500.0) and (m.feet or m.y - 120.0) > e.y - 300.0 and not m.air
        and not (Gw and Gw.entry) then
        e.greeted = true
        log("%s: his greeting", e.type)
        say(w.start, function() boss_music(true) end, e)
        return
    end
    local due = e.words_due
    if due then
        due.n = due.n - 1
        if due.n <= 0 then e.words_due = nil; say(due.id, due.done, e) end
    end
end

local finish
-- (the coins it leaves: given again after it comes back only if he did not pick them up - game.lua drop_loot)
local function loot(e, n, sx, sy, sz, blue)
    local G = package.loaded["game"]
    if G and G.drop_loot then pcall(G.drop_loot, e, n, sx, sy, sz, blue); return end
    for _ = 1, n do pcall(H.spawn_coin, sx, sy, sz, blue) end
end

local function beaten(e, m, world, how)
    local t = e.t
    if how == "pushed" or how == "kicked" then
        -- (bounce_back_from_attack: a punch or kick that lands - the tiny triangles and SOUND_ACTION_HIT_2)
        local EF = package.loaded["envfx"]
        if EF and EF.hit then
            local sx, sy, sz = to_scene(m.x + 100.0 * sins(m.facing), m.y, m.z + 100.0 * coss(m.facing))
            pcall(EF.hit, sx, sy, sz, m.facing)
        end
        sound("hit_punch", 1.0)
        -- (and the camera's little jolt with it: set_camera_shake_from_hit(SHAKE_ATTACK))
        local G = package.loaded["game"]
        if G and G.shake_camera then pcall(G.shake_camera, 0.5) end
    end
    local w = t.words
    e.hp = e.hp - 1
    if e.hp > 0 then
        sound(t.snd and t.snd.hit, 1.0)
        e.flinch = 30
        if t.k == "boo" and t.boss then pcall(M.boo_hit_start, e, m) end
        -- (Wiggler, angry: faster with each stomp - sWigglerSpeeds, 16 then 30 then 40 a frame)
        if e.type == "bhvWigglerHead" then e.chase_v = ({ [2] = 30.0, [1] = 40.0 })[e.hp] end
        log("%s hit (%d left)", e.type, e.hp)
        local line = w and w.hits and w.hits[(t.hits or 1) - e.hp]
        -- (and no further hit till his words are read and 60 frames more: Wiggler - wiggler_act_jumped_on, then his walk's
        -- first 60 frames only obj_check_attacks. One drop onto him counted all three, bounce after bounce, 2026-10-29)
        if t.boss then e.immune, e.immune_t = (line ~= nil) or nil, (line == nil) and 90 or nil end
        local left = e.hp
        if line then e.words_due = { id = line, n = w.delay or 30, done = function()
            e.immune, e.immune_t = nil, 60
            -- (Wiggler's last phase, once the second stomp's words are read: turned red, with his hop's sound -
            -- wiggler_act_jumped_on's SOUND_OBJ_WIGGLER_JUMP; "he doesnt turn red on last phase", 2026-10-29)
            if left == 1 and e.type == "bhvWigglerHead" then
                pcall(M.wiggler_red, e, true)
                sound(t.snd and t.snd.last_phase, 1.0)
                -- (and his little hop into it: 70 up, 10 on - "no little jump", 2026-10-29)
                e.vy, e.fvel, e.ground = 70.0, 10.0, false
                log("Wiggler: his last phase (red, a hop)")
            end
        end } end
        return
    end
    sound(t.snd and t.snd.final, 1.0)           -- (the last stomp's own sound, before his last words: Wiggler's)
    if w and w.beaten then
        -- (his last words before he goes; the boss tune fades for them)
        e.action, e.timer = "words", 0
        e.words_due = { id = w.beaten, n = w.delay or 0, done = function()
            -- (Wiggler shrinks to a little one instead, then the star - M.wiggler_shrink)
            if e.type == "bhvWigglerHead" then e.action, e.timer, e.fvel = "shrink", 0, 0.0; return end
            finish(e, m, world, how)
        end }
        log("%s beaten (%s): his last words", e.type, how)
        return
    end
    finish(e, m, world, how)
end
finish = function(e, m, world, how, keep)          -- (keep: he stays - Wiggler, shrunk: his star and loot only)
    local t = e.t
    -- (its flames go out with it: jumped into, a Fly Guy's last flame - spat as he came at it - burnt him all the same,
    -- "fire shyguy can hurt the player while jumping", 2026-10-27)
    for i = #M.shots, 1, -1 do
        local s = M.shots[i]
        if s.from == e and s.kind == "fire" then
            if s.quad then lib.destroy(s.quad) end
            table.remove(M.shots, i)
        end
    end
    if e.lifted then M.chuckya_let_go(e, nil) end                -- (a Chuckya beaten in his hands: let go)
    if not keep then
        sound((t.snd and t.snd.death) or "en_dying", loudness(e, m, 6000.0))
        e.action, e.timer = "dying", 0
    end
    -- (and its white puff, spawn_mist_particles: envfx.lua - not a bully knocked into the lava or off the edge)
    local EF = package.loaded["envfx"]
    if EF and EF.poof and how ~= "knocked off" and not keep then
        local sx, sy, sz = to_scene(e.x, e.y + (t.h or 100.0) * 0.5 * (e.scale or 1.0), e.z)
        pcall(EF.poof, sx, sy, sz, math.max(0.6, math.min(2.5, (e.scale or 1.0) * (t.h or 100.0) / 120.0)))
    end
    if e.type == "bhvKoopa" and not (e.o and e.o.race) and not e.bare then
        -- (koopa.inc.c: knocked out of his shell, a Koopa leaves it lying there - a shell to surf on, shell.lua. Mario 64's
        -- Koopa runs on without it - M.koopa_shell_off; a tiny one, or one beaten some other way, leaves it here. One
        -- already out of his leaves none)
        local G = package.loaded["game"]
        if G and G.give_shell then
            local sx, sy, sz = to_scene(e.x, e.y, e.z)
            pcall(G.give_shell, sx, sy, sz + 60.0)
        end
    end
    if t.minion then
        M.boos_beaten[t.minion] = (M.boos_beaten[t.minion] or 0) + 1
        log("%s Boos beaten: %d", t.minion, M.boos_beaten[t.minion])
    end
    if e.type == "bhvGhostHuntBigBoo" and t.waits == "ghost" then
        -- (big_boo_act_4: then, 60 frames on, once he is within 600 of the hall's foot, the staircase comes up)
        M.boo_stairs = { t = 0 }
    end
    if e.type == "bhvGhostHuntBoo" then
        -- (boo_act_4: each of the hunt's Boos has a word as it goes, DIALOG_107; the last one, 108 - and out comes
        -- the Big Boo)
        say((M.boos_beaten.ghost or 0) >= 5 and 108 or 107)
    end
    if e.cage then
        M.cages[#M.cages + 1] = { inst = e.cage, x = e.x, y = e.y, z = e.z, vy = 60.0, state = "fall", warp = e.warp }
        e.cage = nil
        sound("puzzle_jingle", 1.0)
    end
    local ncoins = t.coins or 0
    -- (a Boo in BBH carries a blue coin, not a yellow one: every Boo spawns its bhvCoinInsideBoo, which in LEVEL_BBH takes
    -- the blue coin's model and is worth 5 - with a yellow one each there were not 100 coins to be had: "theres not
    -- enough coins to get the 100 coin star in boos world", 2026-10-22)
    local blue_boo = false
    if t.k == "boo" and not t.boss and ncoins > 0 then
        local G = package.loaded["game"]
        if G and G.level_of and G.name and G.level_of(G.name) == "bbh" then blue_boo, ncoins = true, 0 end
    end
    if blue_boo and H.spawn_coin then
        local sx, sy, sz = to_scene(e.x, e.y + 60.0, e.z)
        loot(e, 1, sx, sy, sz, true)
    end
    -- (a giant fire piranha plant - bp's upper half set - leaves two: bhv_fire_piranha_plant_init)
    if e.type == "bhvFirePiranhaPlant" and (((e.o and e.o.bp) or 0) >> 16) & 0xFFFF ~= 0 then ncoins = 2 end
    if ncoins > 0 and H.spawn_coin then
        local sx, sy, sz = to_scene(e.x, e.y + 60.0, e.z)
        loot(e, min(ncoins, 5), sx, sy, sz)
    end
    -- (a Mr. I or a Pokey's head: a blue coin - oNumLootCoins -1, bhvMrIBlueCoin; not the big Mr. I, whose is a star)
    if t.blue_coin and H.spawn_coin and not (e.type == "bhvMrI" and ((e.o.bp or 0) >> 16) & 0xFF ~= 0) then
        local sx, sy, sz = to_scene(e.x, e.y + 60.0, e.z)
        loot(e, 1, sx, sy, sz, true)
    end
    if t.star then
        local G = package.loaded["game"]
        if G and G.add_star then
            local at = t.star_at
            local sx, sy, sz = to_scene(at and at[1] or e.hx, at and at[2] or (e.hy + 500.0), at and at[3] or e.hz)
            local fx, fy, fz = to_scene(e.x, e.y + 100.0 * (e.scale or 1.0), e.z)
            pcall(G.add_star, world, { kind = "star", pos = { sx, sy, sz }, id = star_index(e.o.bp), from = { fx, fy, fz } })
        end
        if e.type == "bhvBigBully" then pcall(M.lll_bridge, world) end
    end
    -- (a big bully's minion: one fewer for it to wait for)
    local boss = e.o and e.o.minion_boss
    if boss and boss.minions_left then
        boss.minions_left = boss.minions_left - 1
        log("a minion bully knocked off (%d left)", boss.minions_left)
    end
    -- (stars of their own - THI's "Pluck the Piranha Flower": the fifth of its five giant fire piranha plants gives it,
    -- fire_piranha_plant.inc.c; BBH's "Eye to Eye in the Secret Room": the big Mr. I's, mr_i.inc.c. Neither had one:
    -- the two stars could not be won)
    local bp2 = ((e.o and e.o.bp or 0) >> 16) & 0xFF
    if bp2 ~= 0 and (e.type == "bhvFirePiranhaPlant" or e.type == "bhvMrI") then
        local at
        if e.type == "bhvFirePiranhaPlant" then
            M.fpp_killed = (M.fpp_killed or 0) + 1
            log("giant fire piranha plant %d of 5", M.fpp_killed)
            if M.fpp_killed == 5 then at = { -6300.0, -1850.0, -6300.0 } end
        else
            at = { 1370.0, 2000.0, -320.0 }
        end
        local G = package.loaded["game"]
        if at and G and G.add_star then
            local sx, sy, sz = to_scene(at[1], at[2], at[3])
            local fx, fy, fz = to_scene(e.x, e.y + 100.0, e.z)
            local ok, st = pcall(G.add_star, world, { kind = "star", pos = { sx, sy, sz }, id = star_index(e.o.bp), from = { fx, fy, fz } })
            if ok and st and G.star_cutscene then pcall(G.star_cutscene, st) end
        end
    end
    if t.boss and M.boss_music then boss_music(false) end
    log("%s beaten (%s)", e.type, how)
end

-- ------------------------------------------------------------ the kinds
local function wander(e, m, careful)
    local t = e.t
    local hx, hz = e.hx - e.x, e.hz - e.z
    if hx * hx + hz * hz > t.home * t.home or e.edge then
        e.want = s16(atan2s(hz, hx))
    elseif e.timer % 75 == 0 then
        e.want = s16(e.yaw + math.random(-0x4000, 0x4000))
    end
    if e.want then e.yaw = turn_toward(e.yaw, e.want, t.turn_k and math.max(0x40, floor(t.turn_k * t.speed)) or 0x300) end   -- (t.turn_k: step_walker)
    e.fvel = t.accel and approach(e.fvel, t.speed * (e.agility or 1.0), t.accel) or t.speed * (e.agility or 1.0)   -- (t.accel: step_walker)
end

-- Pokey's stack (bhv_pokey_body_part_update): part i (0 the head) stands 120 x (alive - i) - 240 + 120 x the bottom
-- part's size over its foot - lifted here by half a part, the parts' pictures being centred - and sways 6 round it
local POKEY_LIFT = 78.0
local function pokey_h(e, i) return POKEY_LIFT + 120.0 * (e.pk.n - i) - 240.0 + 120.0 * e.pk.bottom end
local function pokey_sway(e, i)
    local a = i * 0x4000 + floor(e.pk.t) * 0x800
    return coss(a) * 6.0, sins(a) * 6.0
end
local function render_pokey(e, x, y, z)
    local dying = e.action == "dying"
    for i = 1, 4 do
        local pi = e.parts[i]
        if pi then
            local on = i <= e.pk.n - 1 and not (dying and e.timer >= 2 * (5 - i))
            if on ~= pi.on then pi.on = on; pcall(function() pi.actor:SetActorHiddenInGame(not on) end) end
            if on then
                local ox, oz = pokey_sway(e, i)
                local sx, sy, sz = to_scene(x + ox, y + pokey_h(e, i), z + oz)
                lib.set_pose(pi, sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z, -e.yaw * 360.0 / 65536.0)
                local k = (i == e.pk.n - 1) and 3.0 * math.max(0.01, e.pk.bottom) or 3.0
                if k ~= pi.k then pi.k = k; pcall(function() pi.actor:SetActorScale3D({ X = k, Y = k, Z = k }) end) end
                pcall(lib.face_camera, pi, sx + OFFSET.X, sy + OFFSET.Y)
            end
        end
    end
end
-- each frame (Mario 64 grows a lost part back from the bottom after 100 frames, pokey_act_wander; not here: lost is lost)
local function pokey_step(e)
    local pk = e.pk
    pk.t = pk.t + 1
    pk.bottom = math.min(1.0, pk.bottom + 0.1)
    if e.action == "dying" then return end
    -- (no growing back: what is knocked off stays off - "make them not regenerate", 2026-10-20)
    pk.regrow = 0
end
-- Pokey met: an attack knocks off the part at his height - the head, from its bottom up, beats it; landing on the head
-- does too; walking into it hurts (sPokeyBodyPartHitbox: 40 round x its size)
local function touch_pokey(e, m, pawn, attack, new_attack, world)
    local pk = e.pk
    local dx, dz = m.x - e.x, m.z - e.z
    local d2 = dx * dx + dz * dz
    local head = e.y + pokey_h(e, 0)
    local top = head + POKEY_LIFT
    local reach = 120.0 + 70.0
    -- (a drop kick too: it starts well out of reach and comes flying in, so the kick still under way counts when it gets
    -- there - once a second - as the big bully takes one: "make pokeys drop kickable", 2026-10-20)
    if (pk.hit_cool or 0) > 0 then pk.hit_cool = pk.hit_cool - 1 end
    local kick = attack ~= nil and attack.air and (pk.hit_cool or 0) <= 0
    if (new_attack or kick) and d2 < (reach + 80.0) ^ 2 and m.y > e.y - 150.0 and m.y < top + 150.0 then
        pk.hit_cool = 30
        -- (and a moment after it, still in it as his kick carries him through, it does not hurt him)
        e.touch_cool = math.max(e.touch_cool or 0, 45)
        if m.y > head - POKEY_LIFT or pk.n <= 1 then beaten(e, m, world, attack.air and "kicked" or "pushed"); return end
        -- (two parts at a hit, down to his head: "make it so when you hit a bokey they lose two spike balls", 2026-10-20)
        pk.n, pk.regrow = math.max(1, pk.n - 2), 0
        sound("en_pokey_death", loudness(e, m))
        local EF = package.loaded["envfx"]
        if EF and EF.poof then
            local sx, sy, sz = to_scene(e.x, math.max(e.y + POKEY_LIFT, m.y), e.z)
            pcall(EF.poof, sx, sy, sz, 0.8)
        end
        log("Pokey: a part knocked off (%d left)", pk.n)
        return
    end
    if m.falling and d2 < 160.0 * 160.0 and m.feet > top - 140.0 and m.feet < top + 120.0 then
        if pawn then lib.bounce(pawn, 0, 0, 620) end
        beaten(e, m, world, "stomped")
        return
    end
    if d2 > reach * reach or m.y < e.y - 120.0 or m.feet > top then return end
    -- (met in the middle of one of his attacks - the drop kick that knocked a part off going on into it - it hurts him
    -- no more than Mario 64's Pokey hurts a punching or kicking Mario: "drop kicking pokeys damages the player",
    -- 2026-10-23, the next frame of the kick took him for walking into it)
    if attack then return end
    if (e.touch_cool or 0) > 0 then return end
    e.touch_cool = 20
    hurt(e, m, pawn, e.t.dmg or 1, "Pokey", 1.0)
end

-- Chuckya holding him (chuckya_act_1): lifted into its arms, it turns round with him (0x800 a frame) for 10-40 frames
-- and till there is floor ahead, then throws him on frame 18 of its throw; ten pushes of the stick (or A) and he wriggles
-- free. Let go if it is beaten or he dies.
local function chuckya_hold_step(e, m, pawn)
    local BO = package.loaded["bobomb"]
    local G = package.loaded["game"]
    if not (BO and BO.hold) then e.held = nil; return end
    if (G and G.dying) or e.action == "dying" or e.action == "gone" then BO.hold.release(e, pawn, nil); e.anim_i = nil; return end
    e.fvel = 0.0
    e.hold_t = e.hold_t + 1
    if e.sub == 0 then
        if e.hold_t >= 10 then e.sub, e.hold_t, e.anim_i = 1, 0, 1 end
    elseif e.sub == 1 then
        if BO.hold.wriggled(e.held) then e.held.esc = e.held.esc + 1 end
        if e.held.esc > 10 then
            BO.hold.release(e, pawn, "drop")
            e.grab_cool, e.anim_i = 60, nil
            log("the athlete wriggled free of Chuckya")
            return
        end
        e.yaw = s16(e.yaw + 0x800)
        e.spin_n = e.spin_n - 1
        local ahead = floor_y(e.x + 300.0 * sins(e.yaw), e.y + 150.0, e.z + 300.0 * coss(e.yaw))
        if e.spin_n < -16 or (e.spin_n < 0 and ahead and ahead > e.y - 150.0) then e.sub, e.hold_t, e.anim_i = 2, 0, 3 end
    else
        if e.hold_t == 18 then
            sound(e.t.snd.throw, 1.0)
            BO.hold.release(e, pawn, "throw")
            e.grab_cool, e.anim_i = 60, nil
            log("Chuckya threw the athlete")
        end
    end
end

-- A Scuttlebug spawner (bhv_scuttlebug_spawn_loop, HMC): unseen where it stands, and still; 30 frames on, with Mario
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
        sound("en_scuttle_alert", loudness(e, m))
        return false
    end
    return true
end

-- A bully in the lava (bully.inc.c: its floor SURFACE_BURNING - bully_act_lava_death, obj_lava_death): it sinks 10 a
-- frame for 30 frames, smoking and sizzling every 8, and is gone - a minion counted, the big one's star as when it is
-- knocked off. Only one knocked in: on its own it keeps off the lava. ("if they fall in the lava they die", 2026-10-19:
-- they stood on it.)
local function bully_on_lava(e)
    local G = package.loaded["game"]
    if not (G and G.lava_z) then return false end
    local sx, sy, sz = to_scene(e.x, e.y, e.z)
    local lz = G.lava_z(sx, sy, sz + 30.0)
    return lz ~= nil and sz <= lz + 10.0
end
-- A bully sees him only once he is on its platform - his floor (under him, in the air or not) at its height, and floor
-- all the way between them, none of it lava: "I want a new rule for bullies they cant see you until your on
-- platform", 2026-11-06. Looked at every `every` frames while he is in its range; off its platform it goes home.
-- (`delay`: and only that many seconds after he gets onto it, every bully - "then make their detection delayed by 1
-- second this should be for every bully in the game", 2026-11-06)
M.BULLY_PLAT = { every = 5, step = 50.0, dz = 60.0, delay = 1.0 }
function M.bully_same_platform(e, m)
    local G = package.loaded["game"]
    if not (G and G.floor_z) then return true end
    local P = M.BULLY_PLAT
    local bx, by, bz = to_scene(e.x, e.y, e.z)
    local mx, my = to_scene(m.x, m.y, m.z)
    local function solid(x, y)
        local f = G.floor_z(x, y, bz + 80.0)
        if not f or math.abs(f - bz) > P.dz then return false end
        if G.lava_z and G.lava_z(x, y, bz + 80.0) then return false end
        return true
    end
    local d = math.sqrt((mx - bx) ^ 2 + (my - by) ^ 2)
    local n = math.max(1, math.floor(d / P.step))
    for i = 1, n do
        local k = i / n
        if not solid(bx + (mx - bx) * k, by + (my - by) * k) then return false end
    end
    return true
end
local function bully_sink(e, m, world)
    e.lava_t = e.lava_t + 1
    e.fvel, e.vy = 0.0, 0.0
    if e.lava_t > 30 then
        e.lava_t = nil
        beaten(e, m, world, "knocked off")
        return
    end
    e.y = e.y - 10.0
    if e.lava_t % 8 == 1 then
        sound("en_flame_blown", loudness(e, m))
        local EF = package.loaded["envfx"]
        if EF and EF.poof then
            local sx, sy, sz = to_scene(e.x, e.y + 60.0, e.z)
            pcall(EF.poof, sx, sy, sz, 0.8 * (e.scale or 1.0))
        end
    end
end

-- The athlete picking up a Chuckya (interact_grabbable: once it is not facing him his punch picks it up,
-- able_to_grab_object - from in front it grabs him first, check_object_grab_mario). A heavy thing, as King Bob-omb is:
-- lifted over his head (ACT_PICKING_UP, ACT_HOLD_HEAVY_IDLE), carried, and thrown the way he faces on a new press
-- (ACT_HEAVY_THROW - bobomb.lua's lock and carry). Thrown, 20 on and 50 up (cur_obj_get_thrown_or_placed), it is gone
-- where it lands, hits a wall or meets the water, with its five coins (chuckya_act_2); let go of, it drops so. ("you have
-- to be able to pickup chukyas", 2026-10-27)
M.CHUCKYA_LIFT = { steps = 12, up = 250.0, ahead = 40.0 }   -- (frames up into his hands; its feet over his, Mario units)
function M.chuckya_lift(e, m, pawn)
    local BO = package.loaded["bobomb"]
    local G = package.loaded["game"]
    if not (pawn and BO and BO.hold and BO.hold.lock and BO.hold.carry) or e.held or e.lifted or M.lifting then return false end
    if G and (G.carried or G.dying or G.getup_at) then return false end
    e.lifted = { t = 0, from = { e.x, e.y, e.z }, h = {} }
    M.lifting = e
    BO.hold.lock(e.lifted.h, pawn, true)
    e.fvel, e.vy, e.ground, e.action, e.anim_i = 0.0, 0.0, false, "lifted", 2
    sound("king_grab", 1.0)
    log("the athlete picked up a Chuckya")
    return true
end
-- (let go of: his controls his own again)
function M.chuckya_let_go(e, pawn)
    local L = e.lifted
    e.lifted = nil
    if M.lifting == e then M.lifting = nil end
    local BO = package.loaded["bobomb"]
    pawn = pawn or lib.pawn()
    if L and pawn and BO and BO.hold and BO.hold.lock then pcall(BO.hold.lock, L.h, pawn, false) end
end
function M.chuckya_lifted(e, m, pawn)
    local BO = package.loaded["bobomb"]
    local G = package.loaded["game"]
    local L, C = e.lifted, M.CHUCKYA_LIFT
    L.t = L.t + 1
    e.anim_i = 2
    e.fvel, e.vy, e.ground = 0.0, 0.0, false
    local k = min(1.0, L.t / C.steps)
    k = k * k * (3.0 - 2.0 * k)
    local tx, ty, tz = m.x + sins(m.facing) * C.ahead, m.feet + C.up, m.z + coss(m.facing) * C.ahead
    local f = L.from
    e.x, e.y, e.z = f[1] + (tx - f[1]) * k, f[2] + (ty - f[2]) * k, f[3] + (tz - f[3]) * k
    e.yaw = turn_toward(e.yaw, m.facing, 0x1000)
    local drop = not pawn or (G and G.dying)
    local throw = false
    if not drop and L.t >= C.steps then throw = BO.hold.carry(L.h, pawn) end
    if drop or throw then
        M.chuckya_let_go(e, pawn)
        e.action, e.timer, e.yaw, e.ground = "thrown", 0, m.facing, false
        if throw then
            e.fvel, e.vy = 20.0, 50.0
            sound("king_throw", 1.0)
            log("the athlete threw a Chuckya")
        end
    end
end
function M.chuckya_thrown(e, m, world)
    e.anim_i = 2
    local landed = walk(e, 4.0, false)
    local wall = false
    if H.wall_near and e.timer > 1 then
        local sx, sy, sz = to_scene(e.x, e.y + 10.0, e.z)
        wall = H.wall_near(sx, sy, sz, 30.0 * S, 5.0 * S) and true or false
    end
    if landed or wall or (e.ground and e.timer > 2) then
        e.anim_i = nil
        finish(e, m, world, "thrown")
    elseif e.y < e.hy - 3000.0 then
        -- (thrown off into the void: gone, back as the beaten are)
        e.anim_i, e.action = nil, "gone"
        pcall(function() e.inst.actor:SetActorHiddenInGame(true) end)
    end
end

-- A Koopa knocked out of his shell (koopa.inc.c shelled_koopa_attack_handler, koopa_unshelled_update): landed on,
-- pushed or kicked, a Koopa of his full size loses it - its sound (SOUND_OBJ_KOOPA_DAMAGE), the shell left lying where
-- he was (shell.lua: one to ride), and he is drawn without it (koopa_without_shell_geo, made from the ROM - exporter/
-- koopax.py). On his back he slides to a stop from the knock (anim 2, slowing 0.5 a frame), gets up (anim 6) and runs
-- (anim 3, at 20) away from the athlete - toward his shell once the athlete is 800 off, or when it lies the way he is
-- running anyway, turning 0x600 a frame - and from within 600 of it, at full speed and facing it, dives for it
-- (anim 5): reached with the athlete 200 or more from it, it is his again. No shell lying free (the athlete on it),
-- he runs about. Landed on out of it, he is squashed (koopa_touch). He was beaten at the first stomp before: "when
-- squishing a turtle they dont come out of they're shell", 2026-10-29. (A tiny Koopa is beaten, as Mario 64's.)
-- (in a block of its own: the module is at Lua's 200 locals)
do
local function koopa_anim_len(e, i)
    local a = e.inst and e.inst.data and e.inst.data.anims and e.inst.data.anims[i + 1]
    return (a and a.frames) or 20
end

local function koopa_nearest_shell(e)
    local SH = package.loaded["shell"]
    if not (SH and SH.free) then return nil end
    local best, bd = nil, 1e18
    for _, sh in ipairs(SH.free()) do
        local x, y, z = sh.y / S, sh.z / S, -sh.x / S        -- (scene cm -> Mario 64 units)
        local dx, dy, dz = x - e.x, y - e.y, z - e.z
        local d2 = dx * dx + dy * dy + dz * dz
        if d2 < bd then best, bd = { sh = sh, x = x, y = y, z = z, d = sqrt(d2) }, d2 end
    end
    return best
end

-- back in his shell: its model again (the one he was made with), walking
function M.koopa_shell_on(e, world)
    if not e.bare then return end
    local ni = e.shelled_data and instance(world or lib.world(), e.shelled_data, e.x, e.y, e.z, e.yaw, e.scale)
    if ni then lib.destroy(e.inst.actor); e.inst = ni end
    e.bare, e.anim_i, e.count = nil, nil, nil
end

-- out of it (false: not one to lose it - a tiny Koopa, one already out, one racing - beaten instead)
function M.koopa_shell_off(e, m, world, how)
    if e.bare or (e.scale or 1.0) <= 0.8 or (e.o and e.o.race) then return false end
    local bd = H.actor_data and H.actor_data("geo_koopa_without_shell_geo")
    if not bd then return false end
    local ni = instance(world or lib.world(), bd, e.x, e.y, e.z, e.yaw, e.scale)
    if not ni then return false end
    sound(e.t.snd and e.t.snd.hit, loudness(e, m))
    -- (the shell where he was, down on the floor)
    local SH, G = package.loaded["shell"], package.loaded["game"]
    if SH and SH.add then
        local sx, sy, sz = to_scene(e.x, e.y, e.z)
        local fz = (G and G.floor_z and G.floor_z(sx, sy, sz + 60.0)) or sz
        pcall(SH.add, sx, sy, fz)
    end
    e.shelled_data = e.shelled_data or e.inst.data
    lib.destroy(e.inst.actor)
    e.inst = ni
    e.bare, e.action, e.at, e.count, e.fleeing = true, "lying", 0, 0, nil
    e.fvel = 20.0
    -- (knocked from the side: sent away from him; landed on: the way he was going)
    if how ~= "stomped" then e.yaw = s16(m.angle + 0x8000) end
    e.anim_i, e.f = 2, 0
    log("a Koopa knocked out of his shell (%s)", how)
    return true
end

function M.koopa_bare_step(e, m, world)
    local t = e.t
    e.at = (e.at or 0) + 1
    local shell = koopa_nearest_shell(e)
    if e.action == "lying" or e.action == "dive" then
        -- (koopa_unshelled_act_dive: his shell reached - the athlete not on or by it - and it is his again)
        if e.action == "dive" and e.at > 10 and shell and shell.d < 80.0 then
            local mx, mz, my = m.x - shell.x, m.z - shell.z, m.feet - shell.y
            local SH = package.loaded["shell"]
            if mx * mx + my * my + mz * mz > 200.0 * 200.0 and SH and SH.take and SH.take(shell.sh) then
                M.koopa_shell_on(e, world)
                e.action, e.fvel = "home", e.fvel * 0.5
                log("a Koopa back in his shell")
                return
            end
        end
        if e.fvel > 0.0 then
            local ai = (e.action == "lying") and 2 or 5
            if e.anim_i ~= ai then e.anim_i, e.f = ai, 0 end
            e.f = min(e.f + 1.0, koopa_anim_len(e, ai) - 1)
            if e.ground ~= false then e.fvel = approach(e.fvel, 0.0, 0.5) end
        elseif (e.count or 0) > 0 then
            e.count = e.count - 1
        else
            if e.anim_i ~= 6 then e.anim_i, e.f = 6, 0 end
            e.f = e.f + 1.0
            if e.f >= koopa_anim_len(e, 6) - 1 then e.action, e.anim_i, e.f, e.turn_t = "run", 3, 0, 0 end
        end
        walk(e, 4.0, false)
        return
    end
    -- running (koopa_unshelled_act_run)
    e.action = "run"
    if e.anim_i ~= 3 then e.anim_i, e.f = 3, 0 end
    e.f = e.f + 1.0
    local fi = floor(e.f) % koopa_anim_len(e, 3)
    if t.snd and t.snd.walk and (fi == 0 or fi == 6) then sound(t.snd.walk, loudness(e, m, 2500.0)) end
    local away = s16(m.angle + 0x8000)
    local target
    if shell then
        target = s16(atan2s(shell.z - e.z, shell.x - e.x))
    else
        e.turn_t = (e.turn_t or 0) - 1
        if e.edge or e.turn_t <= 0 or not e.want then
            e.want = s16(e.yaw + (math.random(0, 1) == 0 and -0x2000 or 0x2000))
            e.turn_t, e.edge = math.random(30, 80), nil
        end
        target = e.want
    end
    if m.dist > 800.0 or (shell and abs(s16(target - away)) < 0x2000) then
        e.yaw = turn_toward(e.yaw, target, 0x600)
    else
        e.yaw = turn_toward(e.yaw, away, 0x600)
    end
    e.fvel = approach(e.fvel, 20.0, 1.0)
    -- (a shot at his shell: at full speed, within 600 and facing it - a dive, his speed up a fifth and up by a 20th of
    -- the way to it)
    if e.fvel >= 20.0 and shell and shell.d < 600.0 and abs(s16(target - e.yaw)) < 0xC00 then
        e.yaw = target
        e.action, e.at, e.count = "dive", 0, 20
        e.fvel, e.vy, e.ground = e.fvel * 1.2, shell.d / 20.0, false
        e.anim_i, e.f = 5, 0
    end
    walk(e, 4.0, true)
end
end

local function step_walker(e, m, pawn, world)
    if e.lava_t then bully_sink(e, m, world); return end
    if e.sp == "wait" and spawner_wait(e, m) then return end
    local t = e.t
    if e.grab_cool and e.grab_cool > 0 then e.grab_cool = e.grab_cool - 1 end
    if e.held then chuckya_hold_step(e, m, pawn); return end
    if e.lifted then M.chuckya_lifted(e, m, pawn); return end
    if e.action == "thrown" then M.chuckya_thrown(e, m, world); return end
    if e.bare then M.koopa_bare_step(e, m, world); return end          -- (a Koopa out of his shell)
    local sees = (t.range or 0) > 0 and m.dist < t.range and abs(m.y - e.y) < 500.0
    if sees and t.bully then
        e.plat_t = (e.plat_t or 0) - 1
        if e.plat_t <= 0 then
            e.plat_t = M.BULLY_PLAT.every
            local okp, on = pcall(M.bully_same_platform, e, m)
            e.plat_ok = (not okp) or on
        end
        sees = e.plat_ok
    end
    if t.bully then
        if sees then
            e.plat_since = e.plat_since or os.clock()
            sees = os.clock() - e.plat_since >= (M.BULLY_PLAT.delay or 1.0)
        else
            e.plat_since = nil
        end
    end
    if t.flee and not e.knocked and not (e.flinch and e.flinch > 0) then
        -- (koopa_check_run_from_mario / koopa_shelled_act_run_from_mario: a Koopa he comes within 300 of, facing him,
        -- turns tail and runs at 17; a second on, once he is 800 off, it slows to a stop and walks again)
        if not e.fleeing and m.dist < 300.0 and abs(s16(m.angle - e.yaw)) < 0x3000 then e.fleeing, e.flee_t = true, 0 end
        if e.fleeing then
            e.flee_t = e.flee_t + 1
            if e.flee_t > 30 and m.dist > 800.0 then
                e.fvel = approach(e.fvel, 0.0, 1.0)
                if e.fvel == 0.0 then e.fleeing, e.anim_i = nil, nil end
            else
                e.yaw = turn_toward(e.yaw, s16(m.angle + 0x8000), 0x400)
                e.fvel = approach(e.fvel, 17.0 * (e.agility or 1.0), 1.0)
                e.anim_i = 1
            end
            e.action = "flee"
            walk(e, 4.0, true)
            e.f = e.f + 1.0
            local fi = floor(e.f) % 12
            if t.snd and t.snd.walk and (fi == 0 or fi == 6) then sound(t.snd.walk, loudness(e, m, 2500.0)) end
            return
        end
    end
    if e.flinch and e.flinch > 0 then
        e.flinch = e.flinch - 1
        e.fvel = approach(e.fvel, 0.0, 2.0)
    elseif e.knocked then
        -- a bully pushed away: slides, then comes back for more
        e.fvel = approach(e.fvel, 0.0, 1.0)
        if e.fvel <= 0.5 then e.knocked = nil end
    elseif sees then
        if e.action ~= "chase" then sound(t.snd and t.snd.alert, loudness(e, m)); e.action = "chase" end
        local tr = t.turn or (t.spin and 0x400 or 0x800)
        -- (t.turn_k: turned by that times his speed a frame - Wiggler's 30, wiggler_act_walk's yawTurnSpeed; he turned
        -- 0x800 a frame before, "wiggler also turns to fast", 2026-10-29)
        if t.turn_k then tr = math.max(0x40, floor(t.turn_k * (e.chase_v or t.chase))) end
        e.yaw = turn_toward(e.yaw, m.angle, tr)
        -- (t.accel: up to speed by that much a frame - Wiggler's obj_forward_vel_approach(speed, 1.0); off at full speed
        -- the moment his words were read before, "he starts moving instantly after the dialog", 2026-10-29)
        e.fvel = t.accel and approach(e.fvel, e.chase_v or t.chase, t.accel) or (e.chase_v or t.chase)
    else
        e.action = "home"
        wander(e, m, true)
    end
    local ox, oz = e.x, e.z
    walk(e, 4.0, not e.knocked)
    if e.pk then pokey_step(e) end
    -- a bully knocked off into the void is gone; into the lava, it sinks (bully_sink); walking, it keeps off the lava
    if t.bully then
        if e.y < e.hy - 1500.0 then
            beaten(e, m, world, "knocked off")
        elseif (e.type == "bhvBigChillBully" or e.type == "bhvSmallChillBully") and e.y < 1030.0 then
            -- (bully_step: a chill bully under 1030 - off its ice, into SL's freezing water - sinks and is gone as one in
            -- the lava. It walked on along the lake's bottom: "frozen bully not dying on ice", 2026-10-31)
            e.lava_t = 0
            sound(t.snd and t.snd.death, loudness(e, m))
            log("a chill bully in the freezing water")
        elseif bully_on_lava(e) then
            if e.knocked or not e.ground then
                e.lava_t = 0
                sound(t.snd and t.snd.death, loudness(e, m))
                log("a bully in the lava")
            else
                e.x, e.z = ox, oz
                e.yaw = s16(e.yaw + 0x8000)
                -- (where it was is lava too: it is in it - landed there once its knock-back was over - and burns,
                -- not turned round on the lava for ever: "bully not burning in lava", 2026-11-06)
                if bully_on_lava(e) then
                    e.lava_t = 0
                    sound(t.snd and t.snd.death, loudness(e, m))
                    log("a bully in the lava (stood in it)")
                end
            end
        end
    end
    e.f = e.f + (e.fvel > 1.0 and 1.0 or 0.5)
    local fi = floor(e.f) % 20
    -- (walk_angry: his steps once hit - Wiggler's high pitch, bhv_wiggler_update)
    local ws = t.snd and ((t.snd.walk_angry and e.hp < (t.hits or 1)) and t.snd.walk_angry or t.snd.walk)
    if ws and e.fvel > 1.0 and (fi == 0 or fi == 10) then sound(ws, loudness(e, m, 2500.0)) end
end

-- Mario's cap held by someone (Klepto in his talons, Mr. Blizzard on his head): drawn there, or put away
local function cap_shown_on(e, world, on, x, y, z, yaw, scale)
    if not on then
        if e.cap_inst then lib.destroy(e.cap_inst.actor); e.cap_inst = nil end
        return
    end
    if not e.cap_inst then
        local data = H.actor_data and H.actor_data("cap_red")
        if data then e.cap_inst = instance(world, data, x, y, z, 0, scale or 1.3) end
    end
    if e.cap_inst and not (e.type == "bhvKlepto" and M.klepto_hold(e, e.cap_inst)) then
        local sx, sy, sz = to_scene(x, y, z)
        lib.set_pose(e.cap_inst, sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z, yaw or 0.0)
    end
end


-- Klepto (klepto.inc.c), Shifting Sand Land's condor, flown as Mario 64 flies him ("he doesnt follow the correct flight
-- path", 2026-10-23): a speed along his heading and pitch (obj_compute_vel_from_move_pitch), turned toward a point he
-- circles - his aim swung off it by 90 degrees less atan(radius, distance - radius), so he goes round it
-- (klepto_circle_target), turning up to 0.03 of the gap times his speed, 400 to 700 a frame - climbing to its height and
-- now and then gliding down a little (klepto_anim_dive), banked into his turns (obj_roll_to_match_yaw_turn). Holding the
-- star (act 1) or Mario's cap, he goes round one of three places over the desert's pillars (sKleptoTargetPositions) and
-- every 10 to 20 seconds - or him more than 2000 off, toward the one nearest him - flies to another, 400 higher for each
-- place passed till halfway (klepto_change_target, _approach_target). The cap Klepto (acts 2 on) goes round his place;
-- Mario within 1000 of it, he turns to him and dives, and takes his cap. Hit (an attack within his reach, or jumped up
-- into from below), he lets what he holds go - the star flies to (-5550, 300, -930) - and is knocked back (struck,
-- retreat), circles a while and - the star's - flies off up and is gone, or - the cap's - is back at his place.
-- Active however far off (OBJ_FLAG_ACTIVE_FROM_AFAR: "he freezes when your too far away from him").
-- Not Mario 64's choice of place, though: there he goes to the one nearest Mario whenever Mario is 2000 off, and with
-- the athlete on the fourth pillar - none of the three places by it - he went round the next pillar for good ("just
-- spinning around one pillar", 2026-10-23). Here he goes all the way round the four pillars in turn, a fourth place by
-- the fourth pillar (as the others are by theirs), 5 to 10 seconds at each. The cap Klepto (acts 2 on) goes round them
-- so too, not round his own place: and only with the athlete on top of one of the pillars - Mario 64's four spots to
-- stand on, the pyramid's puzzle - does he come for him, from wherever he is, round him, the dive and the cap taken;
-- off the top, he leaves him be ("he can only steal marios hat on top of the pillars", 2026-10-23).
local KLEPTO_TARGETS = { { 2200.0, 1250.0, -2820.0 }, { -6200.0, 1250.0, -2800.0 }, { -6200.0, 1250.0, 1150.0 },
                         { 2200.0, 1250.0, 1150.0 } }
local KLEPTO_STAR_AT = { -5550.0, 300.0, -930.0 }
-- What he holds, in his talons (klepto_geo: under the last of the empty parts on his right leg - part p10 - a quarter
-- size, then (300, 300, 0) along it - geo_offset_klepto_held_object - and turned 180 and 270 degrees, x then y,
-- GEO_TRANSLATE_ROTATE: the star's face along the part, upside down to it), not hung under him: fixed to that part, it
-- goes with his legs as he flaps. The star's and the cap's models here have their quarter size in them already
-- (star_geo, marios_cap_geo), so they go on at their own size - a star as big as any other ("hes not carrying the star
-- corretly", 2026-10-23: a quarter of that, the wrong way round). The turn, in the scene's axes: half round (1, -1, 0).
M.KLEPTO_HELD = { Translation = { X = 0.0, Y = 75.0 * S, Z = 75.0 * S },
                  Rotation = { X = 0.70710678, Y = -0.70710678, Z = 0.0, W = 0.0 },
                  Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }
function M.klepto_hold(e, held)
    if not (held and held.actor and e.inst and e.inst.comps) or held.in_talons then return held and held.in_talons end
    local c = e.inst.comps[11]
    if not c then return false end
    local ok = pcall(function()
        held.actor:K2_AttachToComponent(c, FName("None"), 0, 0, 0, false)
        held.actor:K2_SetActorRelativeTransform(M.KLEPTO_HELD, false, {}, true)
    end)
    held.in_talons = ok
    return ok
end
local klepto_drop, step_klepto, klepto_cap_drop, step_klepto_cap
do
    local function rnd(base, span) return base + math.random(0, span - 1) end      -- (random_linear_offset)
    local function kl(e, hold, act)
        if e.kl then return e.kl end
        -- (at his flying speed from the first: from Mario 64's standstill he crept about his place for half a minute -
        -- "klepto isnt flying around anymore", 2026-10-23)
        e.kl = { speed = 40.0, myaw = e.yaw or 0, mpitch = 0, fyaw = e.yaw or 0, fpitch = 0, froll = 0, face = true,
                 hx = e.hx, hy = e.hy, hz = e.hz, sx = e.hx, sy = e.hy, sz = e.hz, tnum = 0, f8 = 0.0, fc = 0.0,
                 tchange = 0, timer = 0, u1ae = 0, sub = 0, vy = 0.0, fvel = 0.0, anim = 0, af = 0, hold = hold, act = act }
        return e.kl
    end
    local function go(k, act) k.act, k.timer, k.sub = act, 0, 0 end
    -- (his animations: 0 flapping, 1 struck, 2 up out of a dive, 3 into one, 4 diving, 5 out of a glide, 6 into one -
    -- all but the flapping and the dive played once, held on their last frame)
    local function alen(e, n)
        local an = e.inst and e.inst.data and e.inst.data.anims and e.inst.data.anims[n + 1]
        return (an and an.frames) or 30
    end
    local function anim(k, n) if k.anim ~= n then k.anim, k.af = n, 0 end end
    local function at_end(e, k) return k.af >= alen(e, k.anim) - 1 end
    local function anim_if_end(e, k, n)                     -- (cur_obj_set_anim_if_at_end)
        if at_end(e, k) then anim(k, n); return true end
        return false
    end
    local function anim_settle(e, k)                        -- (klepto_set_and_check_if_anim_at_end)
        if k.anim == 6 then anim_if_end(e, k, 5)
        elseif k.anim == 5 then if anim_if_end(e, k, 0) then k.af = 9 end
        else return true end
        return false
    end
    -- (oKleptoDistanceToTarget, _PitchToTarget, _YawToTarget: to his "home", the place he is after)
    local function home_calc(e, k)
        local dx, dz = k.hx - e.x, k.hz - e.z
        k.dist = sqrt(dx * dx + dz * dz)
        k.p2h = s16(atan2s(k.dist, e.y - k.hy))
        k.yaw2t = s16(atan2s(dz, dx))
    end
    local function change_target(e, m, k)
        local n = (k.tnum + 1) % #KLEPTO_TARGETS       -- (the next pillar round)
        k.f8 = 400.0
        k.tnum = n
        local T = KLEPTO_TARGETS[n + 1]
        k.hx, k.hy, k.hz = T[1], T[2] + k.f8, T[3]
        k.fc = sqrt((k.hx - e.x) ^ 2 + (k.hz - e.z) ^ 2) / 2.0
    end
    -- (klepto_anim_dive: now and then, his way level or down, a glide - wings out, a little down - of 2 to 4 seconds)
    local function anim_dive(e, k)
        if k.u1ae > 0 then
            if k.p2h < -400 then k.u1ae = 0
            else
                if k.anim == 0 then
                    if k.af == 9 then anim(k, 6) end
                else
                    k.u1ae = k.u1ae - 1
                    if k.u1ae == 0 then k.u1ae = -rnd(60, 60) end
                end
                k.mpitch = turn_toward(k.mpitch, 400, 10)
            end
        else
            k.mpitch = turn_toward(k.mpitch, k.p2h, 600)
            if anim_settle(e, k) then
                if k.u1ae ~= 0 then k.u1ae = k.u1ae + 1
                elseif k.p2h > -100 then k.u1ae = rnd(60, 60) end
            end
        end
        k.fpitch = turn_toward(k.fpitch, 0, 1000)
    end
    local function circle(e, m, k, radius, tspeed)
        if k.act == "circle" and (k.hold or k.tour) and k.timer >= k.tchange then
            change_target(e, m, k)
            k.tchange = rnd(150, 150)
            go(k, "approach")
            return
        end
        local turn = s16(0x4000 - atan2s(radius, k.dist - radius))
        if s16(k.myaw - k.yaw2t) < 0 then turn = -turn end
        k.yaw2t = s16(k.yaw2t + turn)
        anim_dive(e, k)
        local t2 = floor(abs(s16(k.yaw2t - k.myaw)) * (0.03 * k.speed))
        t2 = max(400, min(700, t2))
        k.myaw = turn_toward(k.myaw, k.yaw2t, t2)
        k.speed = approach(k.speed, tspeed, (k.speed > 50.0) and 2.0 or 0.05)
    end
    local function approach_target(e, k, tspeed)
        if k.dist < 1800.0 then go(k, "circle"); return end
        if k.fc > 0.0 then
            k.fc = k.fc - k.fvel
            if k.fc <= 0.0 then k.hy = k.hy - k.f8 end
        end
        anim_dive(e, k)
        k.myaw = turn_toward(k.myaw, k.yaw2t, 400)
        k.speed = approach(k.speed, tspeed, 0.05)
    end
    local function target_mario(e, m, k)
        k.dist = sqrt((m.x - e.x) ^ 2 + (m.z - e.z) ^ 2)
        k.p2h = s16(atan2s(k.dist, (e.y - 250.0) - m.feet))
        k.yaw2t = m.angle
        k.u1ae = -60
    end
    -- (the athlete on top of a pillar: the pyramid's four, platforms.lua's PYRAMID_PILLARS - Mario 64's spots to stand
    -- on, their tops 1024 up, the second 896 - on its top or just up off it)
    local PILLAR_TOPS = { { 1789, 1024, 764 }, { 1789, 896, -2579 }, { -5883, 1024, -2579 }, { -5883, 1024, 764 } }
    local function on_pillar(m)
        for _, q in ipairs(PILLAR_TOPS) do
            if abs(m.x - q[1]) < 200.0 and abs(m.z - q[3]) < 200.0 and m.feet > q[2] - 50.0 and m.feet < q[2] + 200.0 then
                return true
            end
        end
        return false
    end
    -- (back round the pillars: the one he was at)
    local function tour_resume(k)
        local T = KLEPTO_TARGETS[k.tnum + 1]
        k.hx, k.hy, k.hz, k.face = T[1], T[2], T[3], true
        k.tchange = rnd(150, 150)
        go(k, "circle")
    end
    local function held_draw(e, world)
        local k = e.kl
        if k.hold == "star" then
            if not e.star_inst then
                local data = H.actor_data and H.actor_data("star")
                if data then e.star_inst = instance(world, data, e.x, e.y - 90.0, e.z, 0, 1.0) end
            end
            if e.star_inst and not M.klepto_hold(e, e.star_inst) then
                local sx, sy, sz = to_scene(e.x, e.y - 90.0, e.z)
                lib.set_pose(e.star_inst, sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z, 0.0)
            end
        elseif e.star_inst then
            lib.destroy(e.star_inst.actor)
            e.star_inst = nil
        end
        cap_shown_on(e, world, k.hold == "cap", e.x, e.y - 90.0, e.z, 0.0)
    end
    -- (hit: obj_set_knockback_action's 50 away from him and 30 up, falling - oGravity -2 - till his struck animation ends)
    local function struck_start(e, m, k)
        k.hold = nil
        k.myaw = s16(m.angle + 0x8000)
        k.fvel, k.vy, k.face = 50.0, 30.0, false
        go(k, "struck")
        anim(k, 1)
        sound("en_klepto", 1.0)
    end
    -- (hit holding nothing - an attack as he dives at him: knocked back all the same, as Mario 64's is; not while
    -- thrown back already)
    M.klepto_knock = function(e, m)
        local k = e.kl
        if not k or k.act == "struck" or k.act == "retreat" then return end
        struck_start(e, m, k)
        log("Klepto: hit, knocked back")
    end
    local function fly(e, m, world)
        local k = e.kl
        k.timer = k.timer + 1
        if k.hold then k.held_t = (k.held_t or 999) + 1 end
        home_calc(e, k)
        if k.act == "struck" then
            -- (klepto_act_struck_by_mario: turned round to him as he falls; then off up)
            k.fpitch = turn_toward(k.fpitch, 0, 800)
            k.fyaw = turn_toward(k.fyaw, s16(k.myaw + 0x8000), 800)
            k.froll = turn_toward(k.froll, 0, 800)
            k.vy = max(-75.0, k.vy - 2.0)
            if k.af >= alen(e, 1) - 2 then
                k.mpitch = s16(-atan2s(k.fvel, k.vy))
                k.speed = sqrt(k.fvel * k.fvel + k.vy * k.vy)
                k.hx, k.hy, k.hz = e.x, e.y + 500.0, e.z
                go(k, "retreat")
            end
        else
            k.fvel = k.speed * coss(k.mpitch)
            k.vy = -k.speed * sins(k.mpitch)
            -- (the cap Klepto going round: the athlete on a pillar top, his cap on, and he comes for it)
            if k.tour and not k.hold and (k.act == "circle" or k.act == "approach") and on_pillar(m) then
                local MC = package.loaded["mariocap"]
                if MC and MC.on_head and MC.on_head() then
                    target_mario(e, m, k)
                    go(k, "turn")
                    k.face = false
                    sound("en_klepto", loudness(e, m))
                end
            end
            local a = k.act
            if a == "circle" then
                circle(e, m, k, 300.0, 40.0)
            elseif a == "approach" then
                approach_target(e, k, 50.0)
            elseif a == "wait" then
                -- (klepto_act_wait_for_mario: round his place; at it, and Mario within 1000 of him, he turns to him)
                if k.dist < 1000.0 then
                    target_mario(e, m, k)
                    if k.dist < 1000.0 then go(k, "turn"); k.face = false; sound("en_klepto", loudness(e, m)) end
                end
                circle(e, m, k, 300.0, 40.0)
            elseif a == "turn" then
                -- (klepto_act_turn_toward_mario: round him at 1000, facing him; lined up, 800 off, the dive)
                target_mario(e, m, k)
                if anim_settle(e, k) and at_end(e, k) and k.dist > 800.0 and (k.dist < 1500.0 or not k.tour)
                    and abs(s16(m.angle - k.fyaw)) < 0x800 and k.p2h < 0x400 then
                    sound("en_klepto", loudness(e, m))
                    go(k, "dive")
                    k.myaw, k.face = k.fyaw, true
                    anim(k, 3)
                elseif k.tour and not on_pillar(m) then
                    tour_resume(k)                      -- (off the pillar top: let be)
                elseif not k.tour and k.dist > 4000.0 then
                    -- (him gone far off: back to his place)
                    k.hx, k.hy, k.hz, k.face = k.sx, k.sy, k.sz, true
                    go(k, "wait")
                end
                circle(e, m, k, 1000.0, 40.0)
                k.fyaw = turn_toward(k.fyaw, m.angle, 1000)
            elseif a == "dive" then
                -- (klepto_act_dive_at_mario: down at him at 60 - his cap taken on the way past - and up again)
                k.speed = approach(k.speed, 60.0, 10.0)
                if k.anim == 2 then
                    if anim_if_end(e, k, 0) then
                        if k.hold then
                            k.tchange = 0
                            go(k, "circle")
                        elseif k.tour then
                            tour_resume(k)
                        else
                            k.hx, k.hy, k.hz = k.sx, k.sy, k.sz
                            go(k, "wait")
                        end
                    end
                else
                    local dy = e.y - m.feet
                    if k.anim == 3 then anim_if_end(e, k, 4)
                    elseif k.vy > 0.0 and dy > 200.0 then anim(k, 2) end
                    k.p2h = -0x3000
                    if not k.hold then
                        local lat = sqrt((m.x - e.x) ^ 2 + (m.z - e.z) ^ 2)
                        if k.sub == 0 then
                            k.p2h = s16(atan2s(lat, e.y - m.feet))
                            k.yaw2t = m.angle
                            if dy < 160.0 then k.sub = 1 end
                        end
                        local MC = package.loaded["mariocap"]
                        if lat < 200.0 and dy > 40.0 and dy < 260.0 and (on_pillar(m) or not k.tour) and MC and MC.lose_to
                            and MC.lose_to("klepto") then
                            k.hold, k.held_t = "cap", 0
                            sound("en_klepto", 1.0)
                            log("Klepto took Mario's cap")
                        end
                    end
                end
                k.mpitch = turn_toward(k.mpitch, k.p2h, 600)
                k.fpitch = turn_toward(k.fpitch, k.mpitch, 600)
                k.myaw = turn_toward(k.myaw, k.yaw2t, 600)
            elseif a == "retreat" then
                -- (klepto_act_retreat: up 500 over where he was thrown to, turned back the way he goes)
                anim(k, 0)
                k.speed = approach(k.speed, 40.0, 10.0)
                k.mpitch = turn_toward(k.mpitch, k.p2h, 1000)
                k.fpitch = turn_toward(k.fpitch, k.mpitch, 1000)
                k.myaw = turn_toward(k.myaw, k.yaw2t, 600)
                local done
                k.fyaw, done = turn_toward(k.fyaw, k.myaw, 1000)
                if done and k.fpitch == k.mpitch then
                    k.hy, k.u1ae, k.face = 1500.0, -100, true
                    go(k, "reset")
                end
            elseif a == "reset" then
                -- (klepto_act_reset_position: ten seconds round about, then - the star's - away up and gone, or - the
                -- cap's - back at his place to wait for Mario)
                if k.timer < 300 then
                    circle(e, m, k, 300.0, 20.0)
                elseif e.star_held ~= nil then
                    k.hx, k.hz, k.hy = -2000.0, -1000.0, 9999.0
                    home_calc(e, k)
                    k.dist = 9999.0
                    if e.y > 5000.0 then
                        e.action = "gone"
                        pcall(function() e.inst.actor:SetActorHiddenInGame(true) end)
                        return
                    end
                    approach_target(e, k, 20.0)
                elseif k.tour then
                    tour_resume(k)
                else
                    k.hx, k.hy, k.hz = k.sx, k.sy, k.sz
                    go(k, "wait")
                end
            end
        end
        -- (obj_roll_to_match_yaw_turn: banked into his turn)
        k.froll = turn_toward(k.froll, max(-0x3000, min(0x3000, s16(k.myaw - k.yaw2t))), 600)
        -- (OBJ_FLAG_SET_FACE_YAW_TO_MOVE_YAW: his face along his way, but while he turns to Mario or is thrown)
        if k.face then k.fyaw = k.myaw end
        -- (cur_obj_move_standard: on along his way, stopped by the ground)
        e.x = e.x + k.fvel * sins(k.myaw)
        e.z = e.z + k.fvel * coss(k.myaw)
        e.y = e.y + k.vy
        local fy = floor_y(e.x, e.y, e.z)
        if fy and e.y < fy then
            e.y = fy
            if k.vy < 0.0 then k.vy = 0.0 end
        end
        e.yaw, e.pitch, e.roll = k.fyaw, k.fpitch, k.froll
        e.anim_i, e.f = k.anim, k.af
        local len = alen(e, k.anim)
        if k.anim == 0 or k.anim == 4 then k.af = (k.af + 1) % len else k.af = min(k.af + 1, len - 1) end
        held_draw(e, world)
    end

    klepto_drop = function(e, m, world)
        local k = kl(e, "star", "circle")
        e.star_held = false
        if e.star_inst then lib.destroy(e.star_inst.actor); e.star_inst = nil end
        struck_start(e, m, k)
        local G = package.loaded["game"]
        if G and G.add_star then
            local sx, sy, sz = to_scene(KLEPTO_STAR_AT[1], KLEPTO_STAR_AT[2], KLEPTO_STAR_AT[3])
            local fx, fy, fz = to_scene(e.x, e.y - 60.0, e.z)
            local ok, st = pcall(G.add_star, world, { kind = "star", pos = { sx, sy, sz }, id = star_index(e.o.bp), from = { fx, fy, fz } })
            if ok and st and G.star_cutscene then pcall(G.star_cutscene, st) end
        end
        log("Klepto: hit, he lets the star go")
    end
    step_klepto = function(e, m, pawn, world)
        if e.action == "gone" then return end
        kl(e, e.star_held and "star" or nil, "circle")
        fly(e, m, world)
    end
    klepto_cap_drop = function(e, m, world)
        local k = kl(e, nil, "wait")
        local MC = package.loaded["mariocap"]
        if MC and MC.drop then
            local sx, sy, sz = to_scene(e.x, e.y - 60.0, e.z)
            pcall(MC.drop, sx, sy, sz, math.random(0, 359), 150.0, 0.0)
        end
        struck_start(e, m, k)
        cap_shown_on(e, world, false)
        log("Klepto: hit, he lets Mario's cap go")
    end
    step_klepto_cap = function(e, m, pawn, world)
        local MC = package.loaded["mariocap"]
        local holding = MC and MC.held_by and MC.held_by("klepto")
        local k = kl(e, holding and "cap" or nil, "circle")
        k.tour = true
        -- (the cap gone from him some other way: holding nothing, on round the pillars)
        if k.hold == "cap" and not holding then
            k.hold = nil
            if k.act == "circle" or k.act == "approach" then tour_resume(k) end
        end
        fly(e, m, world)
    end
end

local function step_flyer(e, m, pawn, world)
    if e.type == "bhvKlepto" and e.star_held ~= nil then return step_klepto(e, m, pawn, world) end
    if e.type == "bhvKlepto" and e.cap_klepto then return step_klepto_cap(e, m, pawn, world) end
    local t = e.t
    e.bob = (e.bob or 0) + 1
    local sees = (t.range or 0) > 0 and m.dist < t.range
    local hx, hz = e.x - e.hx, e.z - e.hz
    local leash = hx * hx + hz * hz < t.home * t.home
    if t.circle then
        e.ang = (e.ang + 0x100) % 65536
        fly_to(e, e.hx + t.circle * sins(e.ang), e.hy + t.fly + 60.0 * sins(e.bob * 400), e.hz + t.circle * coss(e.ang), t.speed)
    elseif t.swoop then
        if sees and leash then
            if e.action ~= "chase" then sound(t.snd.alert, loudness(e, m)); e.action = "chase" end
            fly_to(e, m.x, m.y, m.z, t.speed)
        else
            e.action = "home"
            fly_to(e, e.hx, e.hy, e.hz, t.speed * 0.5)
        end
    elseif sees and leash then
        e.action = "chase"
        fly_to(e, m.x, m.y + 60.0, m.z, t.speed)
        if t.shooter or (e.o.preset == "macro_fire_fly_guy") then
            e.cool = (e.cool or 60) - 1
            if e.cool <= 0 then e.cool = 75; shoot(world, e, m, t.shooter and "ball" or "fire") end
        end
    else
        e.action = "home"
        fly_to(e, e.hx, e.hy + t.fly + 40.0 * sins(e.bob * 600), e.hz, t.speed * 0.5)
    end
    e.f = e.f + 1.0
end

-- A Boo flies the way it faces and turns only a little each frame (boo_chase_mario: cur_obj_rotate_yaw_toward, 0x180
-- and up to 0x7F more, its own; then cur_obj_move_using_fvel) - it used to fly straight at him and whip round to face
-- him, 0x800 a frame ("they need turn radius turned down", 2026-10-17)
local function boo_fly(e, target_yaw, ty, speed, turn)
    local ox, oy, oz = e.x, e.y, e.z
    e.yaw = turn_toward(e.yaw, target_yaw, turn)
    e.x, e.z = e.x + sins(e.yaw) * speed, e.z + coss(e.yaw) * speed
    e.y = approach(e.y, ty, 4.0)
    -- (never through a floor: Mario 64's Boos move with cur_obj_move_standard, standing them on the floor under them and
    -- stopping them at walls. Coming down to his height they sank through the courtyard's raised ground and BBH's floors -
    -- "boos going through floors", "boos still going through floor", 2026-10-22. Its lowest point - 55 under its middle,
    -- times its size, drawn its graph offset up - is kept on the floor, looked for from 150 over its middle (looked for
    -- from its middle, ground it was already in went unseen); a rise of more than 60 at once is a wall and stops it.)
    if H.floor_z then
        local k = e.scale or e.t.scale or 1.0
        local gy = M.BOO_GFX_Y and M.BOO_GFX_Y[e.type] or 30.0
        if gy == "big" then gy = 60.0 * k end
        local lift = 55.0 * k - gy
        local function floor_at(x, z)
            local sx, sy = to_scene(x, 0.0, z)
            local fz = H.floor_z(sx, sy, (max(oy, e.y) + gy + 150.0) * S)
            return fz and fz / S + lift
        end
        local need = floor_at(e.x, e.z)
        if need and need - max(oy, e.y) > 60.0 then
            e.x, e.z = ox, oz
            need = floor_at(ox, oz)
        end
        if need and e.y < need then e.y = need end
    end
end

-- A Big Boo's turn a frame by his health, Mario 64's own (big_boo_act_1: 0x180, 0x240, 0x300 as he weakens) - after
-- "increase his turn radius" (taken as slower, then twice Mario 64's: the user's turn radius is how fast he turns) and
-- "decrease boos turn radius", 2026-10-22
M.BOO_TURN = { [3] = 0x180, [2] = 0x240, [1] = 0x300 }
-- the other Boos': 0x180 and up to 0x7F more, its own (boo_act_1)
M.BOO_TURN_MIN, M.BOO_TURN_VAR = 0x180, 0x7F

-- A Big Boo hit and not beaten (big_boo_act_3, big_boo_update_during_nonlethal_hit): half a size smaller in a puff of
-- mist, he flies off the way the athlete faces - 48 a frame, slowing to nothing over 32 frames (D_8032F0CC over 5000,
-- times 40: 524 in all) - spinning a whole turn round and a whole turn over as he goes (the same table, 65536 in all,
-- added to his facing and his roll); then 16 frames shaking his head (big_boo_shake_after_hit), untouchable throughout,
-- and back to the way he was going. He only stood there before: "big boo doesnt flip when you attack him and get flung
-- around", 2026-10-22.
M.BOO_HIT_V = { 6047, 5664, 5292, 4934, 4587, 4254, 3933, 3624, 3329, 3046, 2775, 2517, 2271, 2039, 1818, 1611, 1416,
                1233, 1063, 906, 761, 629, 509, 402, 308, 226, 157, 100, 56, 25, 4, 0 }
function M.boo_hit_start(e, m)
    e.boo_hit = { t = 0, dir = m.facing, before = e.yaw }
    e.pitch, e.pp, e.roll = 0, 0, 0
    local k = math.max(1.0, (e.scale or e.t.scale or 3.0) - 0.5)
    e.scale = k
    pcall(function() e.inst.actor:SetActorScale3D({ X = k, Y = k, Z = k }) end)
    local EF = package.loaded["envfx"]
    if EF and EF.poof then
        local sx, sy, sz = to_scene(e.x, e.y + 60.0 * k, e.z)
        pcall(EF.poof, sx, sy, sz, 2.0)
    end
end
function M.boo_hit_step(e, m)
    local h, V = e.boo_hit, M.BOO_HIT_V
    local i = h.t
    if i < 32 then
        local v = V[i + 1] / 5000.0 * 40.0
        e.x, e.z = e.x + sins(h.dir) * v, e.z + coss(h.dir) * v
        e.y = e.y + coss(s16(i * 0x800 + 0x800))
        e.yaw, e.roll, e.pitch, e.pp = s16(e.yaw + V[i + 1]), s16((e.roll or 0) + V[i + 1]), 0, 0
    elseif i < 48 then
        e.yaw = s16(e.yaw + floor(coss(s16(i * 0x2000 - 0x3E000)) * 0x400))
    else
        e.yaw, e.boo_hit, e.pitch, e.pp, e.roll = h.before, nil, nil, nil, nil
        return
    end
    h.t = i + 1
end

-- A Big Boo's touch: his power taken and he is thrown away from the Boo, ragdolled - the whole of him given the push,
-- as a blast throws him ("when getting damaged by him make it bump the player", then "also ragdoll the player",
-- 2026-10-22). Harder than a plain enemy's knock-down, so it reads as a bump.
function M.boo_bump(e, m, pawn)
    local HP = _G.HEALTH
    if HP and (HP.grace > 0 or HP.dead_t) then return false end
    local G = package.loaded["game"]
    if G and (G.getup_at or G.dying or (G.intangible and G.intangible())) then return false end
    if M.vanished() then return false end
    if HP and (e.t.dmg or 0) > 0 then HP.damage(e.t.dmg, (e.type:gsub("^bhv", ""))) end
    if not pawn then return true end
    local bx, bz = m.x - e.x, m.z - e.z
    local bd = sqrt(bx * bx + bz * bz)
    if bd < 1.0 then bx, bz, bd = sins(e.yaw), coss(e.yaw), 1.0 end
    -- (550 on and 350 up, about 4 m: 1100 and 550 threw him some 12 m - "why is everything in the game doing so much knockback?", 2026-10-31)
    if H.knock_down then pcall(H.knock_down, pawn, -bz / bd * 550.0, bx / bd * 550.0, 350.0, true) end
    log("%s bumped him", e.type)
    return true
end

-- the castle's Boo (bhv_boo_in_castle_loop): waits, half see-through, turned to him; within 1000 it laughs and flies off
-- (up to 32 a frame, 1 more each frame) toward (-1000, -9000), past z -5000 fading 20 of 255 a frame, and is gone
local function step_castle_boo(e, m, pawn, world)
    local t = e.t
    e.bob = (e.bob or 0) + 1
    if e.action ~= "away" then
        e.action = "wait"
        e.alpha = 180.0 / 255.0
        e.yaw = turn_toward(e.yaw, m.angle, 0x5A8)
        e.y = e.hy + 10.0 * sins(e.bob * 0x400)
        if m.dist < 1000.0 then
            e.action, e.v = "away", 0.0
            sound(t.snd.alert, loudness(e, m))
        end
        return
    end
    e.v = min(32.0, (e.v or 0.0) + 1.0)
    e.yaw = turn_toward(e.yaw, s16(atan2s(-9000.0 - e.z, -1000.0 - e.x)), 0x5A8)
    e.x, e.z = e.x + sins(e.yaw) * e.v, e.z + coss(e.yaw) * e.v
    if e.z < -5000.0 then e.alpha = max(0.0, (e.alpha or 1.0) - 20.0 / 255.0) end
    if (e.alpha or 1.0) <= 0.0 then e.action, e.timer = "gone", 0 end
end

local function step_boo(e, m, pawn, world)
    local t = e.t
    if t.guide then return step_castle_boo(e, m, pawn, world) end
    if e.boo_hit then M.boo_hit_step(e, m); return end
    e.turn = e.turn or (M.BOO_TURN_MIN + math.random(0, M.BOO_TURN_VAR))
    local turn = (t.boss and M.BOO_TURN[e.hp or 3]) or e.turn
    e.bob = (e.bob or 0) + 1
    -- (boo_vanish_or_appear: it hides - fades to 40 of 255 and cannot be touched - only while it faces him, within 30
    -- degrees, and he faces it, the two facings 151 degrees or more apart; behind it, he can get at it)
    local faces_him = abs(s16(m.angle - e.yaw)) <= 0x1568
    local he_faces = abs(s16(e.yaw - m.facing)) >= 0x6B58
    local watched = faces_him and he_faces
    local sees = m.dist < t.range
    if sees and not watched and (e.alpha or 1.0) > 180.0 / 255.0 then
        if e.action ~= "chase" then sound(t.snd.alert, loudness(e, m)); e.action = "chase" end
        -- (boo_chase_mario: with him over 1500 across from its place it turns back to it; and it comes down or up to him
        -- - 50 over his feet - only while it is between 100 under them and 500 over them (a caged one 100 over), and he
        -- is on the ground. Before, it went straight at him at any height: the balcony's Big Boo came down into the yard,
        -- 2026-10-18)
        local hx, hz = m.x - e.hx, m.z - e.hz
        local yaw = (hx * hx + hz * hz > 1500.0 * 1500.0) and s16(atan2s(e.hz - e.z, e.hx - e.x)) or m.angle
        local ty = e.y
        if not m.air then
            local dy = e.y - m.feet
            if dy > (t.cage and 100.0 or -100.0) and dy < 500.0 then ty = m.feet + 50.0 end
        end
        boo_fly(e, yaw, ty, t.speed, turn)
    elseif sees then
        -- (looked at, it stops and turns to him; coming back into sight, it stops till it is whole again)
        e.action = watched and "shy" or "appear"
        e.yaw = turn_toward(e.yaw, m.angle, turn)
    else
        e.action = "home"
        local dx, dz = e.hx - e.x, e.hz - e.z
        local hy = e.hy + t.fly + 40.0 * sins(e.bob * 500)
        if dx * dx + dz * dz > 100.0 * 100.0 then
            boo_fly(e, s16(atan2s(dz, dx)), hy, t.speed * 0.5, turn)
        else
            e.y = approach(e.y, hy, 4.0)
        end
    end
    -- (boo_approach_target_opacity_and_update_scale: hiding, it fades to 40 of 255, 20 a frame; else back to whole)
    local want = (sees and watched) and (40.0 / 255.0) or 1.0
    e.alpha = approach(e.alpha or 1.0, want, 20.0 / 255.0)
end

-- Amps (amp.inc.c). A circling one goes round its spot 0x400 a frame, bobbing 30 (0x8B0 a frame); one with no circle
-- turns to watch him (0x1000), bobbing 20 (0x458). A homing one is not there till he comes within 800 of its spot, then
-- grows into being over 30 frames and sets off at 90: it turns after him (0x400, at 10 a frame), and once it points at
-- him dashes (15 a frame) 30 frames, keeping 150 over his feet (rising to 250 while it turns); 1500 from its spot it
-- gives up, flies on 150 frames and is gone back to it. Either, having shocked him, holds still and harmless 90
-- frames (amp_attack_cooldown_loop - "also stop the amp from moving", 2026-10-17). Before, all of them only drifted
-- about: "next the shock guys need work".
local function step_amp(e, m, pawn, world)
    local t = e.t
    local function show(on)
        if e.amp_shown == on then return end
        e.amp_shown = on
        if e.inst then pcall(function() e.inst.actor:SetActorHiddenInGame(not on) end) end
    end
    local function grow(k)
        if e.amp_k == k then return end
        e.amp_k = k
        local sz = (e.sk or 1.0) * k
        if e.inst then pcall(function() e.inst.actor:SetActorScale3D({ X = sz, Y = sz, Z = sz }) end) end
    end
    e.phase = (e.phase or 0) + 1
    e.at = (e.at or 0) + 1
    if not e.amp_st then
        e.amp_st, e.at = t.homing and "inactive" or "idle", 0
        if t.homing then show(false); grow(0.1); e.avg_y = e.hy else e.ang = e.ang0 or math.random(0, 65535) end
    end
    local st = e.amp_st
    if st == "cool" then
        e.fvel = 0.0
        if e.at > 90 then e.amp_st, e.at = t.homing and "chase" or "idle", 0 end
    elseif t.homing then
        local hx, hy, hz = m.x - e.hx, m.feet - e.hy, m.z - e.hz
        local from_home = sqrt(hx * hx + hy * hy + hz * hz)
        if st == "inactive" then
            if from_home < 800.0 then e.amp_st, e.at = "appear", 0; show(true); grow(0.1) end
        elseif st == "appear" then
            e.yaw = turn_toward(e.yaw, m.angle, 0x1000)
            if e.at < 30 then grow(0.1 + 0.9 * e.at / 30.0) end
            if e.at > 90 then grow(1.0); e.amp_st, e.at, e.phase = "chase", 0, 0 end
        elseif st == "chase" then
            if abs(s16(m.angle - e.yaw)) < 0x400 then e.locked, e.lock_t = true, 0 end
            e.lock_t = (e.lock_t or 0) + 1
            if e.locked then
                e.fvel = 15.0
                if e.avg_y > m.feet + 150.0 then e.avg_y = e.avg_y - 10.0 else e.avg_y = m.feet + 150.0 end
                if e.lock_t > 30 then e.locked = false end
            else
                e.fvel = 10.0
                e.yaw = turn_toward(e.yaw, m.angle, 0x400)
                if e.avg_y < m.feet + 250.0 then e.avg_y = e.avg_y + 10.0 end
            end
            e.x, e.z = e.x + sins(e.yaw) * e.fvel, e.z + coss(e.yaw) * e.fvel
            e.y = e.avg_y + sins(e.phase * 0x400) * 20.0
            if from_home > 1500.0 then e.amp_st, e.at = "giveup", 0 end
        elseif st == "giveup" then
            e.fvel = 15.0
            e.x, e.z = e.x + sins(e.yaw) * e.fvel, e.z + coss(e.yaw) * e.fvel
            if e.at > 150 then
                e.x, e.y, e.z, e.fvel, e.avg_y, e.locked = e.hx, e.hy, e.hz, 0.0, e.hy, false
                show(false); grow(0.1)
                e.amp_st, e.at = "inactive", 0
            end
        end
    elseif (e.radius or 0) > 0 then
        e.ang = (e.ang + 0x400) % 65536
        e.x, e.z = e.hx + e.radius * sins(e.ang), e.hz + e.radius * coss(e.ang)
        e.y = e.hy + coss(e.phase * 0x8B0) * 30.0
        e.yaw = s16(e.ang + 0x4000)
    else
        e.yaw = turn_toward(e.yaw, m.angle, 0x1000)
        e.y = e.hy + coss(e.phase * 0x458) * 20.0
    end
    e.f = e.f + ((st == "cool") and 3.0 or 1.0)
end

-- THI's fire piranha plants (fire_piranha_plant.inc.c): down in the ground, out of sight and not to be touched, till he
-- comes within 800 of one (and no nearer than 100) - two at most out at once, each a while (100 frames) down first;
-- then it grows (4% of its size a frame), turns to him for 50 frames, spits a flame at its animation's frame 56, and
-- after 80 frames shrinks back down. Touchable from half its size. (They stood out all the time and spat from 2000
-- off, 2026-10-29.)
local function step_fire_piranha(e, m, pawn, world)
    local t = e.t
    local fp = e.fp
    if not fp then fp = { act = "hide", frac = 0.0, t = 0 }; e.fp = fp end
    fp.t = fp.t + 1
    local dy = m.y - e.y
    local d3 = sqrt(m.dist * m.dist + dy * dy)
    local out = 0
    for _, o in ipairs(M.list) do
        if o ~= e and o.fp and o.fp.out and o.action ~= "dying" and o.action ~= "gone" then out = out + 1 end
    end
    if fp.act == "hide" then
        fp.frac, fp.tangible = math.max(0.0, fp.frac - 0.04), false
        e.anim_i = t.anim.idle
        if fp.frac <= 0.0 then
            fp.out = false
            if out < 2 and fp.t > 100 and d3 > 100.0 and d3 < 800.0 then
                sound(t.snd.wake, loudness(e, m))
                fp.act, fp.t, fp.out = "grow", 0, true
                e.yaw, e.f = s16(m.angle), 0.0
            end
        end
    else
        e.anim_i = 4
        if fp.frac < 1.0 then
            fp.frac = math.min(1.0, fp.frac + 0.04)
            if fp.frac > 0.5 then fp.tangible = true end
        elseif fp.t > 80 then
            fp.act, fp.t = "hide", 0
            e.anim_i, e.f = t.anim.idle, 0.0
        elseif fp.t < 50 then
            e.yaw = turn_toward(e.yaw, m.angle, 0x400)
        elseif floor(e.f) == 56 then
            shoot(world, e, m, "fire")
            -- (from its mouth, 140 out and 30 up at its size - obj_spit_fire - at him)
            local sh = M.shots[#M.shots]
            if sh and sh.from == e then
                local k = e.scale or 1.0
                sh.x, sh.y, sh.z = e.x + sins(e.yaw) * 140.0 * k, e.y + 30.0 * k, e.z + coss(e.yaw) * 140.0 * k
                local dx, dy2, dz = m.x - sh.x, (m.y + 80.0) - sh.y, m.z - sh.z
                local d = sqrt(dx * dx + dy2 * dy2 + dz * dz)
                if d > 1.0 then sh.vx, sh.vy, sh.vz = dx / d * 30.0, dy2 / d * 30.0, dz / d * 30.0 end
            end
        end
    end
    -- (its size as it grows and shrinks; out of sight at nothing)
    local sc = (e.scale or 1.0) * fp.frac
    if sc ~= fp.shown then
        fp.shown = sc
        pcall(function()
            if sc <= 0.001 then e.inst.actor:SetActorHiddenInGame(true)
            else
                e.inst.actor:SetActorHiddenInGame(false)
                e.inst.actor:SetActorScale3D({ X = sc, Y = sc, Z = sc })
            end
        end)
    end
    e.action = fp.out and "aim" or "sleep"
    e.f = e.f + 1.0
end

local function step_piranha(e, m, pawn, world)
    local t = e.t
    if t.fire then return step_fire_piranha(e, m, pawn, world) end
    -- (piranha_plant_act_sleep: asleep, it wakes only for him within 400 moving faster than 10 a frame - 225 cm/s - or
    -- off the ground (mario_moving_fast_enough_to_make_piranha_plant_bite); tiptoeing up to it, it sleeps on. Awake, it
    -- bites till he is 500 away. "make sure they dont wake up if you walk up to them slowly", 2026-10-17)
    local level = abs(m.y - e.y) < 300.0
    local bites
    if t.fire then
        bites = level and m.dist < 400.0
    elseif e.action == "bite" then
        bites = level and m.dist < 500.0
    else
        bites = level and m.dist < 400.0 and ((m.speed or 0.0) > 225.0 or m.air)
    end
    if bites then
        if e.action ~= "bite" then sound(t.snd.wake, loudness(e, m)); e.action = "bite" end
        e.yaw = turn_toward(e.yaw, m.angle, 0x800)
        e.anim_i = t.anim.attack
        if e.timer % 20 == 0 then sound(t.snd.bite, loudness(e, m)) end
    elseif t.fire and m.dist < t.range then
        e.action = "aim"
        e.yaw = turn_toward(e.yaw, m.angle, 0x400)
        e.anim_i = t.anim.attack
        e.cool = (e.cool or 40) - 1
        if e.cool <= 0 then e.cool = 70; shoot(world, e, m, "fire") end
    else
        e.action = "sleep"
        e.anim_i = t.anim.idle
        -- its lullaby, the level's tune fading out under it (play_secondary_music(SEQ_EVENT_PIRANHA_PLANT, 0, 255))
        if not t.fire and m.dist < 1000.0 and abs(m.y - e.y) < 800.0 then
            local MUSIC = package.loaded["music"]
            if MUSIC and MUSIC.want_secondary then MUSIC.want_secondary("event_piranha_plant", 1.0, 0.0) end
        end
    end
    e.f = e.f + 1.0
end

local function step_spitter(e, m, pawn, world)
    local t = e.t
    local before = e.yaw
    -- (Mr. I's eye follows him closely: obj_turn_toward_object 0x800 then 0x400 a frame)
    e.yaw = turn_toward(e.yaw, m.angle, (e.type == "bhvMrI") and 0xC00 or (t.look and 0x200 or 0x600))
    if e.type == "bhvMrI" and e.action ~= "dying" and e.action ~= "gone" then
        -- (mr_i_act_2: run round it and its eye turns after him; a whole turn the same way without stopping, inside 120
        -- frames, and it is dizzy and beaten - blue coin, or the big one's star)
        local d = s16(before - e.yaw)
        -- (a step with no turn changes nothing here: two steps can fall in one game tick, his place the same for both;
        -- Mario 64's one step a frame starts again on it)
        if m.dist > 800.0 then
            e.spin, e.spin_dir = 0, 0
        elseif d == 0 then
            -- (nothing)
        elseif d > 0 then
            e.spin = ((e.spin_dir or 0) > 0) and ((e.spin or 0) + d) or 0
            e.spin_dir = 1
        else
            e.spin = ((e.spin_dir or 0) < 0) and ((e.spin or 0) - d) or 0
            e.spin_dir = -1
        end
        if (e.spin or 0) == 0 then e.spin_t = 120 end
        e.spin_t = (e.spin_t or 120) - 1
        if e.spin_t <= 0 then e.spin_t, e.spin = 120, 0 end
        if (e.spin or 0) > 65536 then
            e.spin = 0
            log("Mr. I: circled, dizzy")
            beaten(e, m, world, "circled")
            return
        end
    end
    if m.dist < t.range then
        if e.action ~= "aim" then sound(t.snd.alert, loudness(e, m)); e.action = "aim" end
        e.cool = (e.cool or 30) - 1
        if e.cool <= 0 then e.cool = t.rate; shoot(world, e, m, t.shot) end
    else
        e.action = "home"
    end
    e.f = e.f + 1.0
end

-- A fire spitter (fire_spitter.inc.c): it shrinks slowly to a fifth of the ball; 150 frames on, the athlete within 800,
-- it swells and shrinks (obj_grow_then_shrink) and, going under 0.15 on the way down, spits a flame at him - Mario 64's
-- bhvSmallPiranhaFlame at 5, drawn as Bowser's fireball is (bowser_fight.lua's "roller": its eight pictures, at
-- Bowser's share of the size, "repurpose bowsers flame", 2026-10-19): out at 20 and down a sixteenth of a turn, slowing
-- to 15 and then turning after him (0x200 a frame), along the floor; gone 1500 out, at a wall or in water; shedding a
-- rising, shrinking puff every 8 to 23 frames. It sets him alight.
local SPIT_LOOK = 0.45                  -- (bowser_fight.lua's LOOK: every one of his flames at this share of its size)
local function step_firespit(e, m, pawn, world)
    if not e.sflames then e.sflames, e.puffs, e.act, e.at, e.gfx_y = {}, {}, 0, 0, 40.0 end
    e.at = e.at + 1
    local sk0 = e.sk
    local G = package.loaded["game"]
    if e.act == 0 then
        e.sk = approach(e.sk, 0.2, 0.002)
        local sx, sy, sz = to_scene(e.x, e.y, e.z)
        local top = G and G.water_at and G.water_at(sx, sy)
        -- (within 1200, not Mario 64's 800: the athlete half again Mario's size, and RR's spitter on its ledge 7.3 m over
        -- the one under it, 975 off, never woke for him there - "fire not coming out of this fire spitter", 2026-11-02)
        if e.at > 150 and m.dist < 1200.0 and not (top and sz < top) then e.act, e.at, e.vel, e.gt = 1, 0, 0.05, 0 end
    else
        e.yaw = m.angle
        if e.gt < 2 then
            e.sk = e.sk + e.vel
            e.vel = e.vel - 0.01
            if e.vel > -0.03 then e.gt = 0 end
        elseif e.gt > 10 then
            e.sk = approach(e.sk, 0.1, 0.05)
            if e.sk == 0.1 then
                e.act, e.at = 0, 0
            elseif e.vel ~= 0.0 and e.sk < 0.15 then
                e.vel = 0.0
                sound(e.t.snd.shoot, loudness(e, m))
                e.sflames[#e.sflames + 1] = { x = e.x, y = e.y, z = e.z, yaw = e.yaw, speed = 20.0, went = 0.0, t = 0,
                                              s = 5.0, sy = 1.0 + 0.7 * (math.random() - 0.5), puff_t = 0, puff_at = 1 }
            end
        end
        e.gt = e.gt + 1
    end
    if e.sk ~= sk0 and e.inst then
        local k = e.sk
        pcall(function() e.inst.actor:SetActorScale3D({ X = k, Y = k, Z = k }) end)
    end
    for i = #e.sflames, 1, -1 do
        local f = e.sflames[i]
        f.t = f.t + 1
        f.speed = approach(f.speed, 15.0, 0.6)
        if f.speed == 15.0 then f.yaw = turn_toward(f.yaw, s16(atan2s(m.z - f.z, m.x - f.x)), 0x200) end
        -- (down a sixteenth of a turn as Mario 64's, or steeper - toward his middle - with him under it: from a ledge over
        -- him it went out level over his head into the wall beyond - "actually its just shooting into the wall",
        -- 2026-11-02. At most 80 degrees down)
        local dh = sqrt((m.x - f.x) ^ 2 + (m.z - f.z) ^ 2)
        local pitch = math.atan((f.y - (m.y + 75.0)), dh)
        pitch = math.max(math.pi / 8.0, math.min(math.rad(80.0), pitch))
        local fwd, vy = f.speed * math.cos(pitch), -f.speed * math.sin(pitch)
        local nx, ny, nz = f.x + fwd * sins(f.yaw), f.y + vy, f.z + fwd * coss(f.yaw)
        local dead = false
        -- (the floor under it no higher than a step over it: floor_y looks 250 over what it is given, so from 150 under
        -- the flame - floors up to 100 over it. Asked from 100 over, it took what was up to 3.5 m over it for the floor,
        -- a step too high, and the flame went the frame it was spat: RR's spitter under its overhang, 2.4 m up - "no fire
        -- coming out of this fire spitter", 2026-11-02)
        local fy = floor_y(nx, f.y - 150.0, nz)
        if fy and fy > f.y + 78.0 then dead = true end                  -- (a step too high: a wall)
        if not dead and G and G.wall_cut then
            local ax, ay, az = to_scene(f.x, f.y + 30.0, f.z)
            local bx, by, bz = to_scene(nx, f.y + 30.0, nz)
            local okc, cut = pcall(G.wall_cut, ax, ay, az, bx, by, bz)
            if okc and cut < 1.0 then dead = true end
        end
        if fy and ny < fy then ny = fy end
        f.x, f.y, f.z = nx, ny, nz
        local wx, wy, wz = to_scene(f.x, f.y, f.z)
        local top = G and G.water_at and G.water_at(wx, wy)
        if top and wz < top then dead = true end
        f.went = f.went + f.speed
        if f.went > 1500.0 then dead = true end
        -- (its hitbox, sPiranhaPlantFireHitbox at its size: 10 round, 20 high, 10 down - at the size it is drawn)
        local k = f.s * SPIT_LOOK
        local dx, dz = m.x - f.x, m.z - f.z
        if not dead and pawn and dx * dx + dz * dz < (10.0 * k + 37.0) ^ 2 and m.feet < f.y + 10.0 * k and m.y + 150.0 > f.y - 10.0 * k then
            set_alight(e, m, pawn, "a fire spitter", f.x, f.z)
        end
        -- (bhvFlyguyFlame: shed from its middle, rising and shrinking by 0.6 a frame)
        f.puff_t = f.puff_t + 1
        if f.puff_t > f.puff_at then
            f.puff_t, f.puff_at = 0, math.random(8, 23)
            e.puffs[#e.puffs + 1] = { x = f.x, y = f.y + 15.0 * f.sy * f.s * SPIT_LOOK, z = f.z, s = f.s, vy = 0.0 }
        end
        if dead then table.remove(e.sflames, i); sound("en_flame_blown", 0.5 * loudness(e, m)) end
    end
    for i = #e.puffs, 1, -1 do
        local p = e.puffs[i]
        p.vy = p.vy + 2.0
        p.y = p.y + p.vy
        p.s = p.s - 0.6
        if p.s <= 0.0 then table.remove(e.puffs, i) end
    end
    e.f = e.f + 1.0
end

local function step_lakitu(e, m, pawn, world)
    local t = e.t
    e.bob = (e.bob or 0) + 1
    local hx, hz = m.x - e.hx, m.z - e.hz
    if m.dist < t.range and hx * hx + hz * hz < t.home * t.home then
        fly_to(e, m.x + 300.0 * sins(e.bob * 120), m.y + t.fly, m.z + 300.0 * coss(e.bob * 120), t.speed)
        e.cool = (e.cool or 90) - 1
        local n = 0
        for _, x in ipairs(M.list) do if x.from == e and x.action ~= "gone" and x.action ~= "dying" then n = n + 1 end end
        if e.cool <= 0 and n < 3 then
            e.cool = 150
            local data = H.actor_data and H.actor_data("geo_spiny_geo")
            if data then
                local fy = floor_y(e.x, e.y, e.z) or (m.y - 120.0)
                -- (let go from under him and falling, as Mario 64's Lakitu throws it, down into any water to sink there -
                -- it was put on the floor under him, and over the sea floated up on top of the water: "little shell enemys
                -- dont sink into the water", 2026-10-29)
                local sp = { t = T.bhvSpiny, type = "bhvSpiny", o = { bp = 0 }, x = e.x, y = max(fy, e.y - 60.0), z = e.z, hx = e.x, hy = fy, hz = e.z,
                             yaw = m.angle, fvel = 0.0, vy = 0.0, timer = 0, f = 0, action = "home", ground = false, scale = 1.0, sk = 1.0, hp = 1, from = e, ang = 0 }
                sp.inst = instance(world, data, sp.x, sp.y, sp.z, sp.yaw, 1.0)
                if sp.inst then sp.prev = { sp.x, sp.y, sp.z }; M.list[#M.list + 1] = sp end
                sound(t.snd.shoot, loudness(e, m))
            end
        end
    else
        fly_to(e, e.hx, e.hy + t.fly, e.hz, t.speed)
    end
    e.f = e.f + 1.0
end

-- The eel of Jolly Roger Bay's act 2 (unagi.inc.c, "Can the Eel Come Out to Play?" - its star was nowhere: the eel
-- only lay there): in its hole in the rock it creeps out to the mouth (10 a frame from 800 in); the athlete within 1000
-- of its head, it lunges and swims out along its path (jrb_seg7_trajectory_unagi_2: 10 a frame, turning 120 and
-- tipping 50 a frame at most), back into the rock at the end and so to its hole. Its body bites (3 wedges) all along
-- it, 300 apart; the star rides on the tail, 1200 behind its middle - touched, it is off (spawn_default_star to
-- 6833, -3654, 2230, with its cutscene).
local UNAGI_PATH = { { 5381.0, 0.0, 2758.0 }, { 5803.0, -3130.0, 3036.0 }, { 4876.0, -3045.0, 2706.0 }, { 4313.0, -3246.0, 2736.0 },
                     { 3792.0, -3413.0, 3668.0 }, { 4971.0, -3130.0, 3688.0 }, { 5392.0, -3130.0, 3326.0 }, { 6341.0, -3130.0, 2450.0 },
                     { 9431.0, -3130.0, 1400.0 } }
local UNAGI_STAR_AT = { 6833.0, -3654.0, 2230.0 }
-- a point along its body, k units ahead of its middle (bhv_unagi_subobject_loop)
local function unagi_point(e, k)
    local p = e.pitch or 0
    local h = coss(s16(floor(p / 2))) * k
    return e.x + h * sins(e.yaw), e.y - k * sins(p) * 1.13, e.z + h * coss(e.yaw)
end
-- Its idle (bhvUnagi's ANIMATE(6), all it does in the ship and in its hole) with the sway taken up UNAGI_SWAY times:
-- Mario 64's turns each part only about 3 degrees, and the eel looked frozen ("unagi is frozen", 2026-10-18). Each
-- part's turn from its mean pose made that many times as big; made once, kept as the model's last animation.
M.UNAGI_SWAY = 3.0
function M.unagi_idle(e)
    local d = e.inst.data
    if d.unagi_idle then return d.unagi_idle end
    local a = d.anims and d.anims[7]
    if not a then return 6 end
    local function qmul(ax, ay, az, aw, bx, by, bz, bw)
        return aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
               aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz
    end
    local k = M.UNAGI_SWAY
    local out = { frames = a.frames, hold = a.hold, trans = a.trans, rot = {} }
    for b, r in pairs(a.rot) do
        local n = #r // 4
        local mx, my, mz, mw = 0.0, 0.0, 0.0, 0.0
        for f = 0, n - 1 do
            local x, y, z, w = r[f * 4 + 1], r[f * 4 + 2], r[f * 4 + 3], r[f * 4 + 4]
            if x * r[1] + y * r[2] + z * r[3] + w * r[4] < 0 then x, y, z, w = -x, -y, -z, -w end
            mx, my, mz, mw = mx + x, my + y, mz + z, mw + w
        end
        local l = sqrt(mx * mx + my * my + mz * mz + mw * mw)
        if l < 1e-9 then
            out.rot[b] = r
        else
            mx, my, mz, mw = mx / l, my / l, mz / l, mw / l
            local q = {}
            for f = 0, n - 1 do
                local dx, dy, dz, dw = qmul(-mx, -my, -mz, mw, r[f * 4 + 1], r[f * 4 + 2], r[f * 4 + 3], r[f * 4 + 4])
                if dw < 0 then dx, dy, dz, dw = -dx, -dy, -dz, -dw end
                local s = sqrt(dx * dx + dy * dy + dz * dz)
                if s > 1e-7 then
                    local ang = 2.0 * atan(s, dw) * k
                    local sn = sin(ang / 2.0) / s
                    dx, dy, dz, dw = dx * sn, dy * sn, dz * sn, cos(ang / 2.0)
                end
                q[f * 4 + 1], q[f * 4 + 2], q[f * 4 + 3], q[f * 4 + 4] = qmul(mx, my, mz, mw, dx, dy, dz, dw)
            end
            out.rot[b] = q
        end
    end
    d.anims[#d.anims + 1] = out
    d.unagi_idle = #d.anims - 1
    return d.unagi_idle
end
-- Solid, each part of it as drawn, moving as it is posed ("also please add collision and damage to unagi",
-- 2026-10-18: Mario 64's eel has only its hitboxes, and the athlete swam through it). Not the camera's: it would pull
-- in to him whenever the eel came between.
function M.unagi_solid(e)
    local n = 0
    for i, p in ipairs(e.inst.data.parts) do
        local comp = e.inst.comps[i]
        if comp and p.sections and #p.sections > 0 and not p.billboard then
            local col = {}
            for _, sec in ipairs(p.sections) do col[#col + 1] = { pos = sec.pos, idx = sec.idx, source = "unagi" } end
            lib.add_collision(comp, col)
            pcall(function() comp:SetCollisionEnabled(3) end)
            pcall(function() comp:SetCollisionResponseToChannel(4, 0) end)
            n = n + 1
        end
    end
    return n
end
-- Its bite, from its body as drawn (Mario 64: eight hitboxes, 300 apart along a straight line from its middle, 150
-- round - the model's curve and sway left them behind): points along each part's bone, 30 apart, as thick as that
-- part, against the athlete's capsule (15 cm round, 71 cm up and down from his middle). Within 2000 of its middle.
M.UNAGI_REACH = 10.0             -- (cm past the eel's skin that still bites)
function M.unagi_bite(e, m, pawn)
    if (e.touch_cool or 0) > 0 or not pawn or m.dist > 2000.0 then return false end
    local d = e.inst.data
    if not d.unagi_samples then
        local out = {}
        for i, p in ipairs(d.parts) do
            local y0, y1, r, n = 1e9, -1e9, 0.0, 0
            for _, sec in ipairs(p.sections or {}) do
                local P = sec.pos
                for j = 1, #P, 3 do
                    n = n + 1
                    y0, y1 = min(y0, P[j + 1]), max(y1, P[j + 1])
                    r = max(r, sqrt(P[j] * P[j] + P[j + 2] * P[j + 2]))
                end
            end
            if n > 0 then
                local ys, c = {}, max(2, math.ceil((y1 - y0) / 30.0) + 1)
                for j = 0, c - 1 do ys[#ys + 1] = y0 + (y1 - y0) * j / (c - 1) end
                out[#out + 1] = { i = i, ys = ys, r = r }
            end
        end
        d.unagi_samples = out
    end
    if not e.unagi_k then
        local k = 1.0
        pcall(function() k = e.inst.actor:GetActorScale3D().X end)
        e.unagi_k = k
    end
    local k = e.unagi_k
    local c = pawn:K2_GetActorLocation()
    local lo, hi = c.Z - 71.0, c.Z + 71.0
    for _, s in ipairs(d.unagi_samples) do
        local comp = e.inst.comps[s.i]
        if comp then
            local o, rv = comp:K2_GetComponentLocation(), comp:GetRightVector()
            local reach = s.r * k + 15.0 + M.UNAGI_REACH
            for _, y in ipairs(s.ys) do
                local px, py, pz = o.X + rv.X * y * k, o.Y + rv.Y * y * k, o.Z + rv.Z * y * k
                local dx, dy, dz = px - c.X, py - c.Y, pz - max(lo, min(hi, pz))
                if dx * dx + dy * dy + dz * dz < reach * reach then
                    e.touch_cool = 30
                    hurt(e, m, pawn, 3, "the eel", 1.0)
                    return true
                end
            end
        end
    end
    return false
end
local function step_unagi(e, m, pawn, world)
    e.at = (e.at or 0) + 1
    e.f = e.f + 1.0
    local hx, hy, hz = unagi_point(e, 900.0)
    local near = sqrt((m.x - hx) ^ 2 + (m.y - hy) ^ 2 + (m.z - hz) ^ 2)
    if e.action == "home" then
        e.action, e.f4, e.yaw0, e.at = "hole", -800.0, e.yaw, 0
    end
    if e.action == "hole" then
        -- (unagi_act_3)
        e.anim_i = M.unagi_idle(e)
        e.pitch = 0
        if e.f4 < 0.0 then e.f4 = min(0.0, e.f4 + 10.0); e.at = 0
        elseif e.at > 60 and near < 1000.0 then
            e.action, e.at, e.anim_i, e.f = "lunge", 0, 5, 0
            sound("en_unagi", loudness(e, m))
        end
    elseif e.action == "lunge" then
        e.anim_i = 5
        e.f4 = min(300.0, e.f4 + 20.0)
        if e.at > 24 then
            if near < 1200.0 then
                e.action, e.at, e.wp, e.fvel, e.anim_i, e.f = "swim", 0, 1, 30.0, 1, 0
            else
                e.action, e.at = "hole", 0
                e.f4 = 0.0
            end
        end
    elseif e.action == "swim" then
        -- (unagi_act_1_4 with cur_obj_follow_path)
        local p0, p1 = UNAGI_PATH[e.wp], UNAGI_PATH[e.wp + 1]
        if not p1 then
            e.action, e.f4, e.yaw, e.pitch, e.at, e.fvel = "hole", -800.0, e.yaw0, 0, 0, 0.0
        else
            local dx, dy, dz = p1[1] - e.x, p1[2] - e.y, p1[3] - e.z
            if (p1[1] - p0[1]) * dx + (p1[2] - p0[2]) * dy + (p1[3] - p0[3]) * dz <= 0.0 or dx * dx + dy * dy + dz * dz < 250.0 * 250.0 then
                e.wp = e.wp + 1
            end
            local tyaw = s16(atan2s(dz, dx))
            local tpitch = s16(atan2s(sqrt(dx * dx + dz * dz), -dy))
            e.yaw = turn_toward(e.yaw, tyaw, 120 * 4)
            e.pitch = turn_toward(e.pitch or 0, tpitch, 50 * 4)
            e.fvel = e.fvel + ((10.0 - e.fvel) > 0 and min(0.2, 10.0 - e.fvel) or max(-0.2, 10.0 - e.fvel))
            e.x = e.x + e.fvel * sins(e.yaw) * coss(e.pitch)
            e.y = e.y - e.fvel * sins(e.pitch)
            e.z = e.z + e.fvel * coss(e.yaw) * coss(e.pitch)
            e.anim_i = ((e.at // 54) % 2 == 0) and 2 or 3
        end
    end
    if e.action == "hole" or e.action == "lunge" then
        e.x, e.y, e.z = e.hx + e.f4 * sins(e.yaw0), e.hy, e.hz + e.f4 * coss(e.yaw0)
    end
    -- its bite, all along it as drawn
    M.unagi_bite(e, m, pawn)
    -- the star on its tail
    local tx, ty, tz = unagi_point(e, -1200.0)
    if e.star_held then
        if (m.x - tx) ^ 2 + (m.y - ty) ^ 2 + (m.z - tz) ^ 2 < 230.0 * 230.0 then
            e.star_held = false
            if e.star_inst then lib.destroy(e.star_inst.actor); e.star_inst = nil end
            local G = package.loaded["game"]
            if G and G.add_star then
                local sx, sy, sz = to_scene(UNAGI_STAR_AT[1], UNAGI_STAR_AT[2], UNAGI_STAR_AT[3])
                local fx, fy, fz = to_scene(tx, ty, tz)
                local ok, st = pcall(G.add_star, world, { kind = "star", pos = { sx, sy, sz }, id = star_index(e.o.bp), from = { fx, fy, fz } })
                if ok and st and G.star_cutscene then pcall(G.star_cutscene, st) end
            end
            log("the eel: its tail touched, the star is off")
        else
            if not e.star_inst then
                local data = H.actor_data and H.actor_data("star")
                if data then e.star_inst = instance(world, data, tx, ty, tz, 0, 1.0) end
            end
            if e.star_inst then
                local sx, sy, sz = to_scene(tx, ty, tz)
                lib.set_pose(e.star_inst, sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z, (e.at * 11.25) % 360.0)
            end
        end
    end
end

-- The eel of the sunken ship (unagi.inc.c, second parameter byte 0 and 2; "add unagi to guard the ship ... you have to go
-- to him then surface then go back down for him to leave the ship", 2026-10-18 - it only lay there, flat, inside the
-- hull). In act 1 it waits in the ship, its head up out of it (pitch -7600); once Mario has come within 700 of its head
-- (unagi_act_0's oSubAction) and then is more than 4500 from it - up at the surface - it leaves the ship: from the start
-- of jrb_seg7_trajectory_unagi_1 round the bay, 10 a frame, turning 120 and tipping 50 a frame at most, round and round.
-- In acts 3 to 6 it is out swimming from the first. Its body bites all along it (3 wedges, as the cave eel's).
M.UNAGI_SHIP_PATH = { { 5300.0, -3800.0, 1200.0 }, { 3700.0, -3600.0, 1700.0 }, { 3400.0, -3400.0, 3500.0 },
                      { 3900.0, -3600.0, 4400.0 }, { 5300.0, -3800.0, 4400.0 }, { 6200.0, -4000.0, 2700.0 } }
function M.step_unagi_ship(e, m, pawn, world)
    e.at = (e.at or 0) + 1
    e.f = e.f + 1.0
    local P = M.UNAGI_SHIP_PATH
    local function leave()
        e.unagi_ship, e.wp, e.fvel, e.at, e.bite_t, e.f4 = "path", 1, 0.0, 0, nil, 0.0
        e.x, e.y, e.z = P[1][1], P[1][2], P[1][3]
        e.pitch = 0
        e.yaw = s16(atan2s(P[2][3] - P[1][3], P[2][1] - P[1][1]))
    end
    if e.unagi_ship == "path" and not e.wp then leave() end
    if e.unagi_ship == "ship" then
        e.pitch = -7600
        local hx, hy, hz = unagi_point(e, 900.0)
        local near = sqrt((m.x - hx) ^ 2 + (m.y - hy) ^ 2 + (m.z - hz) ^ 2)
        -- (its idle, swaying - bhvUnagi's ANIMATE(6), never changed while it waits in the ship, taken up: M.unagi_idle -
        -- and with him within 900 of its head it snaps at him out of the hole, as the cave's eel lunges from its own:
        -- anim 5, its head out 150 and back, then a second and a half before the next; "unagi is frozen", 2026-10-18)
        if e.bite_t then
            e.bite_t = e.bite_t + 1
            e.anim_i = 5
            e.f4 = 150.0 * sin(pi * min(1.0, e.bite_t / 23.0))
            if e.bite_t >= 23 then e.bite_t, e.f4, e.bite_cool = nil, 0.0, 45 end
        else
            e.anim_i = M.unagi_idle(e)
            e.bite_cool = max(0, (e.bite_cool or 0) - 1)
            if near < 900.0 and e.bite_cool <= 0 then
                e.bite_t, e.f = 0, 0.0
                sound("en_unagi", loudness(e, m))
            end
        end
        local f4 = e.f4 or 0.0
        e.x = e.hx + f4 * coss(e.pitch) * sins(e.yaw)
        e.y = e.hy - f4 * sins(e.pitch)
        e.z = e.hz + f4 * coss(e.pitch) * coss(e.yaw)
        if near < 700.0 and not e.roused then
            e.roused = true
            sound("en_unagi", loudness(e, m))
            log("the ship's eel: he has seen Mario")
        end
        if e.roused and m.dist > 4500.0 then
            leave()
            log("the ship's eel leaves the ship")
        end
    elseif e.unagi_ship == "path" then
        local p0, p1 = P[e.wp], P[e.wp + 1]
        if not p1 then e.wp, p0, p1 = 1, P[1], P[2] end
        local dx, dy, dz = p1[1] - e.x, p1[2] - e.y, p1[3] - e.z
        if (p1[1] - p0[1]) * dx + (p1[2] - p0[2]) * dy + (p1[3] - p0[3]) * dz <= 0.0 or dx * dx + dy * dy + dz * dz < 250.0 * 250.0 then
            e.wp = e.wp + 1
            if e.wp >= #P then e.wp = 1 end          -- (round again: its path's end comes back to its start)
        end
        local tyaw = s16(atan2s(dz, dx))
        local tpitch = s16(atan2s(sqrt(dx * dx + dz * dz), -dy))
        e.yaw = turn_toward(e.yaw, tyaw, 120 * 4)
        e.pitch = turn_toward(e.pitch or 0, tpitch, 50 * 4)
        e.fvel = (e.fvel or 0.0) + ((10.0 - (e.fvel or 0.0)) > 0 and min(0.2, 10.0 - (e.fvel or 0.0)) or max(-0.2, 10.0 - (e.fvel or 0.0)))
        e.x = e.x + e.fvel * sins(e.yaw) * coss(e.pitch)
        e.y = e.y - e.fvel * sins(e.pitch)
        e.z = e.z + e.fvel * coss(e.yaw) * coss(e.pitch)
        e.anim_i = ((e.at // 54) % 2 == 0) and 2 or 3
        if e.at % 54 == 6 then sound("en_unagi", loudness(e, m) * 0.6) end
    end
    -- its bite, all along it as drawn
    M.unagi_bite(e, m, pawn)
end

-- The way into the sunken ship in act 1: jrb_seg7_collision_in_sunken_ship's warp floor (bhvInSunkenShip, at 5385,
-- -5520, 2428, turned 0xE958 / 0xEE6C / 0x0C80) in the hole the eel lies in, Mario 64's WARP_NODE_WARP_FLOOR to the
-- ship's inside, closing in a circle over 20 frames (WARP_OP_WARP_FLOOR) - only once the eel has left it ("add the
-- teleport to the ship. but only when the eel is not in it", 2026-10-18). The hole is lower than the athlete is tall,
-- so his middle in it or up to 100 out of its mouth will do. (The hole's own frame: its rows, Mario 64 units.)
M.SHIP_HOLE = { at = { 5385.0, -5520.0, 2428.0 },
                rows = { { 0.9326, 0.2565, 0.2538 }, { -0.0639, 0.8097, -0.5834 }, { -0.3552, 0.5279, 0.7715 } },
                x0 = 277.0, x1 = 542.0, y0 = 759.0, y1 = 1084.0, z0 = -409.0, z1 = 0.0 }
function M.ship_warp(m, pawn)
    local G = package.loaded["game"]
    if not (G and G.name == "jrb" and G.act == 1 and G.warp and G.warp[0xF3]) then return end
    if G.warping or G.pending or G.dying or (G.warp_cool or 0) > 0 then return end
    for _, e in ipairs(M.list) do
        if e.unagi_ship == "ship" then return end          -- (the eel still in it)
    end
    local h, R = M.SHIP_HOLE, M.SHIP_HOLE.rows
    local dx, dy, dz = m.x - h.at[1], m.y - h.at[2], m.z - h.at[3]
    local lx = dx * R[1][1] + dy * R[1][2] + dz * R[1][3]
    local ly = dx * R[2][1] + dy * R[2][2] + dz * R[2][3]
    local lz = dx * R[3][1] + dy * R[3][2] + dz * R[3][3]
    if lx > h.x0 and lx < h.x1 and ly > h.y0 and ly < h.y1 and lz > h.z0 and lz < h.z1 then
        local w = G.warp[0xF3]
        log("into the sunken ship by its warp floor (%.0f, %.0f, %.0f in the hole)", lx, ly, lz)
        G.warp_out("door", w.scene, w.node)
    end
end

local function step_npc(e, m, pawn, world)
    if e.unagi then return step_unagi(e, m, pawn, world) end
    if e.unagi_ship then return M.step_unagi_ship(e, m, pawn, world) end
    e.f = e.f + 1.0
    if e.type == "bhvToadMessage" then
        -- (bhv_toad_message_loop: a Toad stands see-through - 81 of 255 - till he comes within 600; then it comes whole,
        -- 6 a frame; once he is 700 off it fades back)
        e.toad_st, e.alpha = e.toad_st or "faded", e.alpha or (81.0 / 255.0)
        if e.toad_st == "faded" then
            if m.dist < 600.0 then e.toad_st = "up" end
        elseif e.toad_st == "up" then
            e.alpha = math.min(1.0, e.alpha + 6.0 / 255.0)
            if e.alpha >= 1.0 then e.toad_st = "whole" end
        elseif e.toad_st == "whole" then
            if m.dist > 700.0 then e.toad_st = "down" end
        else
            e.alpha = math.max(81.0 / 255.0, e.alpha - 6.0 / 255.0)
            if e.alpha <= 81.0 / 255.0 then e.toad_st = "faded" end
        end
    end
    if e.t.r == 0 and m.dist < 800.0 then e.yaw = turn_toward(e.yaw, s16(m.angle + (e.t.face or 0)), 0x200) end
    if e.type == "bhvTuxiesMother" and not e.reunited then
        -- (tuxies_mother_act_2: her baby still lost, she says so as he comes up, DIALOG_057; again once he has been
        -- away)
        local carrying = false
        for _, x in ipairs(M.list) do if x.carried then carrying = true end end
        if m.dist > 450.0 then
            e.spoke = nil
        elseif not e.spoke and not carrying and m.dist < 300.0 and abs(m.y - e.y) < 200.0 then
            e.spoke = true
            say(57, nil, e)
        end
    end
end

-- A small Whomp (whomp.inc.c): patrols 700 from home and turns about; seeing the athlete in front it hurries, and
-- close up it rears, hops and falls flat on its face onto him (crushed: three wedges). It lies a while (three
-- seconds), then gets up again. Stood on as it lies there it gives a coin; a drop kick on its back (Mario's ground
-- pound) breaks it, for five coins. Its body is solid: a slab that tips over with it.
local function whomp_go(e, act) e.action, e.at, e.sub = act, 0, 0 end
local function step_whomp(e, m, pawn, world)
    e.pitch, e.pv = e.pitch or 0, e.pv or 0
    local t, sc = e.t, e.scale or 1.0
    if e.action == "home" then whomp_go(e, t.king and "wait" or "patrol"); e.pitch, e.pv = 0, 0 end
    e.at = (e.at or 0) + 1
    local a, rate = e.action, 1.0
    e.anim_i = 0
    if a == "wait" then
        -- the King on his summit, until the athlete comes up to him
        e.x, e.z, e.fvel, rate = e.hx, e.hz, 0.0, 0.0
        if m.dist < 1000.0 and m.y > e.y - 300.0 and not e.greeting and e.at > 15 then
            -- (whomp_act_0: his DIALOG_114 first; the boss tune once it is read)
            e.greeting = true
            log("the Whomp King: his greeting")
            talk_cam(e)
            say(114, function()
                e.greeting = nil
                boss_music(true)
                sound("whomp_short", 1.0)
                whomp_go(e, "chase")
            end)
        end
    elseif a == "chase" then
        e.fvel = 3.0
        e.yaw = turn_toward(e.yaw, m.angle, 0x200)
        if e.at > 30 and abs(s16(m.angle - e.yaw)) < 0x2000 then
            if m.dist < 1500.0 then e.fvel, rate = 9.0, 3.0 end
            if m.dist < 300.0 * sc then whomp_go(e, "rear"); e.f = 0 end
        end
        if m.y < e.y - 1000.0 then
            boss_music(false)
            e.x, e.y, e.z, e.yaw = e.hx, e.hy, e.hz, s16(-(e.o.yaw or 0.0) * 65536.0 / 360.0)
            whomp_go(e, "wait")
        end
    elseif a == "patrol" then
        e.fvel = 3.0
        local hx, hz = e.x - e.hx, e.z - e.hz
        if hx * hx + hz * hz > 700.0 * 700.0 then
            whomp_go(e, "turn")
        elseif abs(s16(m.angle - e.yaw)) < 0x2000 and abs(m.y - e.y) < 400.0 then
            if m.dist < 1500.0 then e.fvel, rate = 9.0, 3.0 end
            if m.dist < 300.0 then whomp_go(e, "rear"); e.f = 0 end
        end
    elseif a == "turn" then
        if e.sub == 0 then
            e.fvel = 0.0
            if e.at > 32 then e.sub = 1 else e.yaw = s16(e.yaw + 0x400) end
        else
            e.fvel = 3.0
            if e.at > 43 then whomp_go(e, "patrol") end
        end
    elseif a == "rear" then
        e.fvel, e.anim_i = 0.0, 1
        local an = e.inst.data.anims and e.inst.data.anims[2]
        if e.f >= ((an and an.frames) or 15) - 2 then whomp_go(e, "jump") end
    elseif a == "jump" then
        e.anim_i = 1
        if e.at == 1 then e.vy = 40.0 end
        if e.at > 8 then
            e.pv = e.pv + 0x100
            e.pitch = e.pitch + e.pv
            if e.pitch > 0x4000 then e.pitch, e.pv = 0x4000, 0; whomp_go(e, "fall") end
        end
    elseif a == "fall" then
        e.anim_i = 1
        if e.ground then
            sound("en_whomp", loudness(e, m, 5000.0))
            -- what it fell on: from 50 to 430 in front of where it stood, 150 either side
            local dx, dz = m.x - e.x, m.z - e.z
            local along = dx * sins(e.yaw) + dz * coss(e.yaw)
            local side = dx * coss(e.yaw) - dz * sins(e.yaw)
            if along > 0.0 and along < 470.0 * sc and abs(side) < 190.0 * sc and m.feet < e.y + 150.0 * sc and m.feet > e.y - 150.0 then
                -- squished flat under it, as under a Thwomp (squish.lua): its face over him rises as it stands up again,
                -- along x tan of its lean - "please add the same squish mechanic with the walking whomp", 2026-10-17
                local SQ = package.loaded["squish"]
                local floor_z = nil
                pcall(function() floor_z = pawn:K2_GetActorLocation().Z - 88.0 end)
                local reach = along * S
                local started = SQ and pawn and floor_z and SQ.start(pawn, {
                    bottom = function()
                        local th = (0x4000 - (e.pitch or 0x4000)) * pi / 32768.0
                        if th >= 1.45 then return floor_z + 100000.0 end
                        return floor_z + reach * math.tan(math.max(0.0, th))
                    end,
                    grounded = not m.air, what = t.king and "King Whomp" or "a whomp" })
                if not started then
                    local HP = _G.HEALTH
                    if HP and HP.grace <= 0 and not HP.dead_t and not M.vanished() then
                        HP.damage(3, "a whomp")
                        local fx, fz = sins(e.yaw), coss(e.yaw)
                        if H.knock_down and pawn then pcall(H.knock_down, pawn, -fz * 400.0, fx * 400.0, 320.0) end   -- (was 700, 500: "why is everything in the game doing so much knockback?", 2026-10-31)
                    end
                end
            end
            -- (the King's slam: the screen shakes - cur_obj_shake_screen(SHAKE_POS_SMALL) - and, standing near, the
            -- athlete is thrown off his feet: "when he falls make the screen shake and the player fall", 2026-10-17)
            if t.king then
                local G = package.loaded["game"]
                if G and G.shake_stage then pcall(G.shake_stage, 1.0) end
                local SQ = package.loaded["squish"]
                local squished = SQ and SQ.active and SQ.active()
                if not squished and not m.air and m.dist < 1500.0 and pawn and H.knock_down then
                    pcall(H.knock_down, pawn, 0.0, 0.0, 150.0)
                    log("King Whomp's slam: the athlete off his feet")
                end
            end
            whomp_go(e, "down")
        end
    elseif a == "down" then
        e.fvel, e.anim_i = 0.0, 1
        if e.sub ~= 10 then
            -- stood on: the athlete on its back, near its top (100 up), over its length
            local dx, dz = m.x - e.x, m.z - e.z
            local along = dx * sins(e.yaw) + dz * coss(e.yaw)
            local side = dx * coss(e.yaw) - dz * sins(e.yaw)
            local top = 100.0 * sc
            local on = along > 30.0 * sc and along < 450.0 * sc and abs(side) < 170.0 * sc and m.feet > e.y + top - 60.0
                       and m.feet < e.y + top + (e.kicked and 350.0 or 120.0)
            -- (a jump landing on its back does it too - Mario 64's ground pound: "moving thwomps should be killable by
            -- jumpin on they're backs", 2026-10-17)
            -- (beaten - the King, hit - only by landing on its back out of a jump, from over it - 20 up, the King 60 - not
            -- for a hop or a climb up there, nor for passing over it in the air: his three hits came while the athlete
            -- stood on him, "make sure the player jumps on his back before it counts as a hit"; the small ones died with
            -- him only jumping past, "the players not actually landing on the thwomps but they die", 2026-10-17)
            if m.air then e.air_peak = math.max(e.air_peak or -1.0e9, m.feet) end
            local landed = on and e.was_air and not m.air and (e.air_peak or -1.0e9) > e.y + top + (t.king and 60.0 or 20.0)
            if not m.air then e.air_peak = nil end
            e.was_air = m.air
            if on and not e.on_said then
                e.on_said = true
                log("whomp: on its back (air %s, falling %s, kicked %s)", tostring(m.air), tostring(m.falling), tostring(e.kicked))
            elseif not on then
                e.on_said = nil
            end
            if t.king then
                -- the King: a drop kick on his back hurts him; he shakes, and gets up
                if e.sub == 1 then
                    e.shake = (e.shake or 0) + 1
                    e.y = e.y + ((e.shake % 2 == 1) and 8.0 or -8.0)
                    if e.shake >= 10 then e.sub = 10 end
                elseif on and (e.kicked or landed) then
                    e.kicked = nil
                    sound("king_death", 1.0)
                    beaten(e, m, world, landed and "jumped on" or "drop kicked")
                    if e.action == "dying" or e.action == "words" then return end
                    e.sub, e.shake = 1, 0
                end
            elseif on then
                if e.kicked or landed then
                    e.kicked = nil
                    beaten(e, m, world, landed and "jumped on" or "drop kicked")
                    return
                elseif e.sub == 0 then
                    if H.spawn_coin then
                        local sx, sy, sz = to_scene(m.x, m.feet + 60.0, m.z)
                        pcall(H.spawn_coin, sx, sy, sz)
                    end
                    e.sub = 1
                end
            elseif e.sub == 1 then
                e.sub = 0
            end
            if e.at > 100 and not (t.king and e.sub == 1) then e.sub = 10 end
        elseif e.pitch > 0 then
            e.pitch = max(0, e.pitch - 0x200)
        else
            e.pitch = 0
            whomp_go(e, t.king and "chase" or "patrol")
        end
    end
    e.kicked = nil
    if a == "jump" or a == "fall" then
        -- (in the air: straight up and down)
        e.vy = e.vy - 4.0
        local ny = e.y + e.vy
        local fy = floor_y(e.x, max(e.y, ny) + 100.0, e.z)
        if fy and ny <= fy then e.y, e.vy, e.ground = fy, 0.0, true else e.y, e.ground = ny, false end
    elseif e.fvel ~= 0.0 then
        walk(e, 4.0, true)
        if e.edge and a == "patrol" then whomp_go(e, "turn") end
        if e.edge and a == "chase" then e.fvel = 0.0 end
    end
    -- its pounding steps: at the frames its feet come down
    e.f = e.f + rate
    local an = e.inst.data.anims and e.inst.data.anims[e.anim_i + 1]
    local len = (an and an.frames) or 50
    if e.anim_i == 0 then
        local fi = floor(e.f) % len
        local pf = floor(e.f - rate) % len
        if e.fvel > 0.0 and ((pf > fi) or (pf < 23 and fi >= 23)) then sound("whomp_step", loudness(e, m, 3000.0)) end
    elseif e.f > len - 1 then
        e.f = len - 1
    end
end

-- A clam (clam.inc.c): shut, it bites what touches it; when the athlete has been near a while (150 frames) it opens
-- for 150 frames with a breath of bubbles, then shuts again
local function step_clam(e, m)
    e.at = (e.at or 0) + 1
    local an = e.inst.data.anims or {}
    if e.action == "home" then e.action, e.at, e.f = "shut", 0, 0 end
    if e.action == "shut" then
        e.anim_i = 0
        local len = (an[1] and an[1].frames) or 30
        if e.f < 25 then
            e.f = e.f + 1
            if e.f >= 25 then sound("clam_shut", loudness(e, m, 2000.0)); e.at, e.biting = 0, true end
        else
            if e.f < len - 1 then e.f = e.f + 1 end
            if e.at > 150 and m.dist < 500.0 then
                e.action, e.at, e.f = "open", 0, 0
                sound("clam_open", loudness(e, m, 2000.0))
            end
        end
    else
        e.anim_i = 1
        local len = (an[2] and an[2].frames) or 40
        if e.f < len - 1 then e.f = e.f + 1 end
        if e.f >= 30 then e.biting = false end
        if e.at > 150 then e.action, e.at, e.f = "shut", 0, 0 end
    end
end

-- A flamethrower: near the athlete (2000) it throws a flame every frame for 74 frames (each living 15, the last ones
-- less), then rests 60. Flames go up 95 a frame (parameter 4), along its yaw (0, 1 blue; 2 slower), or along the floor (3).
local function step_thrower(e, m, pawn)
    e.at = e.at + 1
    if e.act == 0 then
        if m.dist < 2000.0 then e.act, e.at = 1, 0 end
    elseif e.act == 1 then
        local life
        if e.at < 60 then life = 15 elseif e.at < 74 then life = 75 - e.at else e.act, e.at = 2, 0 end
        if life then
            if e.bp2 == 3 then life = floor(life / 1.2) end
            if e.reach then life = math.max(1, floor(life * e.reach + 0.5)) end
            local r = function() return (math.random() * 2.0 - 1.0) * 10.0 end
            e.flames[#e.flames + 1] = { x = e.x + r(), y = e.y + r(), z = e.z + r(), t = 0, life = life,
                                        vel = (e.bp2 == 2) and 50.0 or 95.0, k = math.random(0, 7), yaw = e.yaw }
        end
    elseif e.at > 60 then
        e.act, e.at = 0, 0
    end
    local HP = _G.HEALTH
    for i = #e.flames, 1, -1 do
        local f = e.flames[i]
        f.sc = (e.bp2 == 2) and (f.t * (f.vel - 6.0) / 100.0 + 2.0) or (f.t * (f.vel - 20.0) / 100.0 + 1.0)
        if e.bp2 == 4 then
            f.y = f.y + f.vel
        else
            -- (each flame keeps the way it was thrown: spawn_object_relative gives it the thrower's angle then)
            f.x, f.z = f.x + f.vel * sins(f.yaw or e.yaw), f.z + f.vel * coss(f.yaw or e.yaw)
            if e.bp2 == 3 then
                f.y = f.y - 28.0
                local fy = floor_y(f.x, f.y + 200.0, f.z)
                if fy and f.y - 25.0 * f.sc < fy then f.y = fy + 25.0 * f.sc end
            end
        end
        -- (its hitbox: 50 round, 25 high, 25 down; the athlete is about 40 round)
        local dx, dz = m.x - f.x, m.z - f.z
        if pawn and dx * dx + dz * dz < 90.0 * 90.0 and f.y + 25.0 > m.feet and f.y - 50.0 < m.y + 120.0 then
            set_alight(e, m, pawn, "a flamethrower", f.x, f.z)
        end
        f.t = f.t + 1
        if f.t > f.life then table.remove(e.flames, i) end
    end
end

-- JRB's falling pillar (falling_pillar.inc.c): the athlete within 1300, it creaks round toward a point 500 in front
-- of him for 10 frames, then topples; along its length (300, 700, 1100, 1500 up) it hits for three wedges; flat,
-- it is gone with a crash
local function step_pillar(e, m, pawn)
    e.at = (e.at or 0) + 1
    e.pitch = e.pitch or 0
    if e.action == "home" then
        e.pitch = 0                                 -- (back up after a respawn)
        if m.dist < 1300.0 then
            e.myaw, e.fvel, e.action, e.at, e.pv, e.pacc = m.angle, 1.0, "turn", 0, 0.0, 0.0
            sound("pound_rock", loudness(e, m, 3000.0))
        end
        return
    end
    e.x, e.z = e.x + e.fvel * sins(e.myaw), e.z + e.fvel * coss(e.myaw)
    local tx, tz = m.x + sins(m.facing) * 500.0, m.z + coss(m.facing) * 500.0
    if e.action == "turn" then
        local want = s16(atan2s(tz - e.z, tx - e.x))
        local d = s16(want - e.yaw)
        if abs(d) <= 0x400 then e.yaw = want else e.yaw = s16(e.yaw + ((d > 0) and 0x400 or -0x400)) end
        if e.at > 10 then e.action = "fall" end
    elseif e.action == "fall" then
        e.pacc = e.pacc + 4.0
        e.pv = e.pv + e.pacc
        e.pitch = e.pitch + e.pv
        for i = 0, 3 do
            local up = i * 400.0 + 300.0
            local hx = sins(e.pitch) * sins(e.yaw) * up + e.x
            local hy = coss(e.pitch) * up + e.y
            local hz = sins(e.pitch) * coss(e.yaw) * up + e.z
            local dx, dz = m.x - hx, m.z - hz
            if dx * dx + dz * dz < 190.0 * 190.0 and m.y > hy - 150.0 - 120.0 and m.feet < hy + 150.0 then
                hurt(e, m, pawn, 3, "a falling pillar", 1.0)
            end
        end
        if e.pitch > 0x3900 then
            sound("big_pound", loudness(e, m, 5000.0))
            e.action, e.timer = "gone", 0
            pcall(function() e.inst.actor:SetActorHiddenInGame(true) end)
        end
    end
end

-- LLL's bouncing fireball (bouncing_fireball.inc.c): the athlete within 2000, a burst of eleven flames, shrinking,
-- hops out of the lava (up 30, then hops of 50 at 30 along); then it rests 100-200 frames. The first flame sets him
-- alight (bhvBouncingFireballFlame: INTERACT_FLAME - it only knocked him down: "the jumping fires should catch the
-- player on fire", 2026-10-19).
local function step_spout(e, m, pawn)
    e.at = e.at + 1
    if e.act == 0 then
        if m.dist < 2000.0 then e.act, e.at = 1, 0 end
    elseif e.act == 1 then
        local k = e.at - 1
        e.flames[#e.flames + 1] = { x = e.x, y = e.y, z = e.z, t = 0, vy = 30.0, fv = 0.0, sc = (10 - k) * 0.5, k = k % 8,
                                    hot = (k == 0), stage = 0 }
        if e.at > 10 then e.act, e.at, e.rest = 2, 0, math.random() * 100.0 end
    elseif e.at > e.rest + 100 then
        e.act, e.at = 0, 0
    end
    for i = #e.flames, 1, -1 do
        local f = e.flames[i]
        f.t = f.t + 1
        f.vy = f.vy - 4.0
        f.x, f.z = f.x + f.fv * sins(e.yaw), f.z + f.fv * coss(e.yaw)
        f.y = f.y + f.vy
        local fy = floor_y(f.x, f.y + 100.0, f.z)
        local landed = fy and f.y <= fy
        if landed then
            f.y = fy
            if f.stage == 0 then f.stage, f.vy, f.fv = 1, 50.0, 30.0
            elseif f.t > 100 then f.t = 999
            else f.vy = 50.0 end
        end
        if f.hot and pawn then
            local dx, dz = m.x - f.x, m.z - f.z
            if dx * dx + dz * dz < 90.0 * 90.0 and f.y + 25.0 > m.feet and f.y - 50.0 < m.y + 120.0 then
                set_alight(e, m, pawn, "a bouncing fireball", f.x, f.z)
            end
        end
        if f.t > 300 then table.remove(e.flames, i) end
    end
end

-- how hard a rolling iron ball throws him (x 800 out, x 450 up, all of him at once)
local BALL_KNOCK = 2.2
-- The balls a spawner lets go (bowling_ball.inc.c, Mario 64's object_step): out of the spawner - in the hill, where
-- its path starts - at its kind's speed (BoB's 20 a frame), steered along the path (cur_obj_follow_path; turning
-- 0x400 a frame), gravity 5.5 (75 at most), and on the ground the floor's tilt pulling it along as any object's
-- (calc_new_obj_vel_and_pos_y: n_xz * (nx^2 + nz^2) * gravity * 2 a frame) with no friction, 70 a frame at most;
-- two wedges; gone at the path's end. ("make sure the big balls that come down the mountain spawn in the hill also
-- make sure they are the correct speed", 2026-10-16: their floor was looked for from 550 above - over the spawner
-- that is the hill's outside, so they came out on top of it - and they gathered speed along the path by 5.5 x the
-- slope's sine, about twice Mario 64's on its gentle slopes.)
local BALL_G = 5.5
local function ball_floor(b, x, z)
    -- (find_floor: the highest floor at most 78 above it; its normal in Mario 64's axes)
    if H.floor_normal then
        local sx, sy, sz = to_scene(x, b.gy + 78.0, z)
        local fz, n1, n2, n3 = H.floor_normal(sx, sy, sz)
        if fz then return fz / S, n2, n3, -n1 end
    end
    return floor_y(x, b.gy + 78.0 - 250.0, z), 0.0, 1.0, 0.0
end
local function ball_follow(b, path)
    local p0, p1 = path[b.wi], path[b.wi + 1]
    if not p1 then return true end
    local ox, oy, oz = p1[1] - b.x, p1[2] - b.gy, p1[3] - b.z
    b.tyaw = s16(atan2s(oz, ox))
    -- (past the waypoint: the next; the path's last reached, the end)
    if (p1[1] - p0[1]) * ox + (p1[2] - p0[2]) * oy + (p1[3] - p0[3]) * oz <= 0.0 then
        b.wi = b.wi + 1
        if not path[b.wi + 1] then return true end
    end
    return false
end
local function ball_step(b, path)
    -- object_step
    local vx, vz = b.fv * sins(b.yaw), b.fv * coss(b.yaw)
    local fy, fnx, fny, fnz = ball_floor(b, b.x + vx, b.z + vz)
    b.vy = max(-75.0, min(75.0, b.vy - BALL_G))
    b.gy = b.gy + b.vy
    if fy and b.gy < fy then
        b.gy = fy
        b.vy = (b.vy < -17.5) and -(b.vy / 2.0) or 0.0
    end
    if fy and b.gy >= fy and b.gy < fy + 37.0 then
        local k = (fnx * fnx + fnz * fnz) * BALL_G * 2.0
        vx, vz = vx + fnx * k, vz + fnz * k
        if abs(vx) < 1e-6 then vx = 0.0 end
        if abs(vz) < 1e-6 then vz = 0.0 end
        if vx ~= 0.0 or vz ~= 0.0 then b.yaw = s16(atan2s(vz, vx)) end
        b.fv = sqrt(vx * vx + vz * vz)
    end
    b.x, b.z = b.x + b.fv * sins(b.yaw), b.z + b.fv * coss(b.yaw)
    -- bhv_bowling_ball_roll_loop
    local done = ball_follow(b, path)
    b.yaw = turn_toward(b.yaw, b.tyaw, 0x400)
    if b.fv > 70.0 then b.fv = 70.0 end
    return done
end
local function step_balls(e, m, pawn, world)
    e.at = (e.at + 1) % 256
    -- (bhv_generic_bowling_ball_spawner_loop: none while he is within 1000 or above it)
    if not (m.dist < e.near or e.y < m.feet) and e.at % e.period == 0 and m.dist < e.reach
       and floor(math.random() * e.odds) == 0 and #e.balls < 6 then
        local data = H.actor_data and H.actor_data("geo_bowling_ball_geo")
        local inst = data and instance(world, data, e.x, e.y, e.z, 0, e.size)
        if inst then
            local b = { inst = inst, x = e.x, gy = e.y, z = e.z, vy = 0.0, wi = 1, fv = e.v0, yaw = 0 }
            ball_follow(b, e.path)
            b.yaw = b.tyaw or 0                     -- (bhv_bowling_ball_initialize_loop)
            e.balls[#e.balls + 1] = b
        end
    end
    local r = 128.0 * e.size
    for bi = #e.balls, 1, -1 do
        local b = e.balls[bi]
        b.px, b.pz, b.pgy = b.x, b.z, b.gy
        if ball_step(b, e.path) then
            lib.destroy(b.inst.actor)
            table.remove(e.balls, bi)
        elseif pawn then
            b.y = b.gy
            local hx, hz = m.x - b.x, m.z - b.z
            if hx * hx + hz * hz < (100.0 + 40.0) ^ 2 and m.feet < b.gy + 150.0 + r and m.y + 120.0 > b.gy then
                -- (thrown away from the ball, not its spawner; hard, all of him: "you have to up the knockback on the
                -- balls")
                hurt(b, m, pawn, 2, "a rolling ball", BALL_KNOCK, true)
            end
        end
    end
end

-- Koopa the Quick (koopa.inc.c koopa_the_quick_*)
local function ktq_music(name)
    local MUSIC = package.loaded["music"]
    if MUSIC and MUSIC.play then pcall(MUSIC.play, name or ((_G.SM64 and _G.SM64.data and _G.SM64.data.music) or nil)) end
end
-- What the racers say (koopa.inc.c sKoopaTheQuickProperties, racing_penguin.inc.c): the question - "yes" and the race
-- is on, "no" and he asks again two seconds on - and after it, once he has stopped and the athlete comes up to him,
-- how it went: won (then the star, out of him), lost, or cheated (Koopa: shot from a cannon; the penguin: two seconds
-- in the air at once)
local RACE_WORDS = {
    bob = { ask = 5, win = 7, lose = 41, cheat = 6 },
    thi = { ask = 9, win = 31, lose = 41, cheat = 6 },
    penguin = { ask = 55, win = 56, lose = 37, cheat = 132 },
}
local function race_words(e)
    if e.type == "bhvRacingPenguin" then return RACE_WORDS.penguin end
    local G = package.loaded["game"]
    local lv = G and G.level_of and G.level_of(G.name) or ""
    return RACE_WORDS[lv] or RACE_WORDS.bob
end

-- The Big Penguin Race (racing_penguin.inc.c), on its own: it rode Koopa the Quick's walk - hopping at every dip,
-- through the slide's walls, off the end of the world after the race. Now as Mario 64's: he asks when the athlete is
-- within 400 and not below him; "yes", a hop (60 up), the gun at 50 frames, off at 20; down the path on his belly,
-- turning 15 x his speed a frame toward the next point, his speed weighed against the athlete's height - more than 100
-- above him (the athlete ahead), it climbs toward 0.1 x (1000 + the drop), else it sinks to 70 (60 from point 35 on),
-- never above 150 - with gravity 8, walls 300 round, tilted to the floor. Past the last point he slides on till a wall
-- stops him (a pound), gets up, waddles round to face +Z (yaw 0) and waits; the athlete within 400, his say (won 056,
-- cheated 132, lost 037) and the star for a fair win. The athlete wins by crossing the line (within 1000 of it, past it)
-- before he is at the bottom; two seconds in the air at once, or the shortcut, is cheating (STORROR's slide is a fall:
-- only off the floor counts as air).
local function step_rpenguin(e, m, pawn, world)
    local R = e.o.race
    local W = { ask = 55, win = 56, lose = 37, cheat = 132 }
    e.at = (e.at or 0) + 1
    e.f = (e.f or 0.0) + 1.0
    local a = e.action
    if a == "home" or a == nil then e.action, a, e.at = "wait", "wait", 0 end
    -- (walls round him: pushed out of them, true if one was there - Mario 64's, at his feet + 10, only walls that rise
    -- there: cur_obj_resolve_wall_collisions)
    local function walls(r)
        if not H.wall_near then return false end
        local sx, sy, sz = to_scene(e.x, e.y + 10.0, e.z)
        local hit, px, py = H.wall_near(sx, sy, sz, r * S, 2.0)
        if hit and (px ~= 0.0 or py ~= 0.0) then e.x, e.z = e.x + py / S, e.z - px / S end
        return hit
    end
    -- (cur_obj_move_standard: along his yaw, gravity 8 a frame; on a downslope he keeps to the floor at speed)
    local function move()
        e.x, e.z = e.x + e.fvel * sins(e.yaw), e.z + e.fvel * coss(e.yaw)
        local hit = e.fvel > 0.0 and walls(300.0)
        e.vy = max((e.vy or 0.0) - 8.0, -75.0)
        local fy = floor_y(e.x, max(e.y, e.y + e.vy), e.z)
        local ny = e.y + e.vy
        if fy and (ny <= fy or (e.ground and e.vy <= 0.0 and e.y - fy < max(30.0, e.fvel * 0.8))) then
            e.y, e.vy, e.ground = fy, 0.0, true
        else
            e.y, e.ground = ny, false
        end
        -- (cur_obj_align_gfx_with_floor: tilted to the slope under him)
        local ahead = floor_y(e.x + 80.0 * sins(e.yaw), e.y + 100.0, e.z + 80.0 * coss(e.yaw))
        local behind = floor_y(e.x - 80.0 * sins(e.yaw), e.y + 100.0, e.z - 80.0 * coss(e.yaw))
        local tp = 0
        if e.ground and ahead and behind then tp = s16(atan2s(160.0, behind - ahead)) end
        e.pitch = turn_toward(e.pitch or 0, max(-0x1800, min(0x1800, tp)), 0x300)
        return hit
    end
    -- (lost below the course - no floor under him - back on it: where he was going; past the line, at his path's last
    -- point and stopped. Put back on the line at speed, he slid off the bottom again and again, flickering between the
    -- two - "when the penguin finishes the slide he glitches out and starts teleporting like crazy", 2026-10-18)
    if e.y < R.flag[2] - 1200.0 then
        if a == "race" then
            local p = R.path[e.wp + 1] or R.path[#R.path]
            e.x, e.y, e.z, e.vy = p[1], p[2] + 50.0, p[3], 0.0
        else
            local p = R.path[#R.path]
            e.x, e.y, e.z, e.vy, e.fvel = p[1], p[2] + 50.0, p[3], 0.0, 0.0
            if a == "finish" then e.f = 0.0 end
        end
        e.prev = e.prev and { e.x, e.y, e.z } or nil
        log("the racing penguin: back on the course")
    end
    if a == "wait" then
        e.fvel, e.anim_i = 0.0, 3
        e.yaw = turn_toward(e.yaw, m.angle, 0x400)
        if (e.cool or 0) > 0 then
            e.cool = e.cool - 1
        elseif not e.asking and e.at > 15 and m.dist < 400.0 + 120.0 and abs(m.feet - e.y) < 400.0 and m.feet - e.y > -20.0 then
            e.asking = true
            talk_cam(e)
            ask(W.ask, function(answer)
                e.asking = nil
                if answer == 1 then
                    e.action, e.at, e.wp, e.cheat, e.air_n, e.won, e.reached, e.weighted = "start", 0, 1, nil, 0, nil, nil, 0.0
                    e.vy, e.ground = 60.0, false
                    sound("race_fanfare", 1.0)
                    log("the racing penguin: the race is on")
                else
                    e.cool = 60
                end
            end)
        end
        move()
    elseif a == "start" then
        -- (racing_penguin_act_prepare_for_race: round to face +X, the gun at 50 frames)
        e.anim_i = 3
        e.yaw = turn_toward(e.yaw, 0x4000, 2500)
        if e.at == 50 then sound("race_gun", 1.0) end
        if e.at > 50 then e.action, e.at, e.fvel, e.f = "race", 0, 20.0, 0.0 end
        move()
    elseif a == "race" then
        local path = R.path
        local last, target = path[e.wp], path[e.wp + 1]
        local ox, oy, oz = target[1] - e.x, target[2] - e.y, target[3] - e.z
        local px, py, pz = target[1] - last[1], target[2] - last[2], target[3] - last[3]
        local tyaw = s16(atan2s(oz, ox))
        if px * ox + py * oy + pz * oz <= 0.0 then
            e.wp = e.wp + 1
            if not path[e.wp + 1] then
                e.reached, e.action, e.at = true, "finish", 0
                log("the racing penguin: at the bottom%s", e.won and ", beaten" or " first")
            end
        end
        if e.action == "race" then
            local dy = e.y - m.feet
            local lo = 70.0
            local from = e.wp - 1          -- (the last point's number, from 0)
            if dy < 100.0 or from >= 35 then
                if from >= 35 then lo = 60.0 end
                e.weighted = approach(e.weighted or 0.0, -500.0, 100.0)
            else
                e.weighted = approach(e.weighted or 0.0, 1000.0, 30.0)
            end
            local want = max(lo, min(150.0, 0.1 * (e.weighted + dy)))
            e.fvel = approach(e.fvel, want, 0.4)
            e.yaw = turn_toward(e.yaw, tyaw, floor(15.0 * e.fvel))
        end
        e.anim_i = 1
        local SFX = sfx()
        if SFX and SFX.hold then pcall(SFX.hold, "loop_rough_slide", 0.6 * loudness(e, m, 4000.0)) end
        -- (the athlete off the floor two seconds at once; or by the shortcut)
        local afy = floor_y(m.x, m.feet, m.z)
        local off = m.air and (not afy or m.feet - afy > 80.0)
        e.air_n = off and (e.air_n or 0) + 1 or 0
        if e.air_n > 60 and not e.cheat then e.cheat = true; log("the racing penguin: he saw that") end
        local cx, cy, cz = m.x + 6393.0, m.feet + 716.0, m.z - 7503.0
        if not e.cheat and cx * cx + cy * cy + cz * cz < 500.0 * 500.0 then
            e.cheat = true
            log("the racing penguin: he took the shortcut")
        end
        move()
    elseif a == "finish" then
        -- (racing_penguin_act_finish_race: on till a wall - or the floor's end - stops him; up off his belly)
        if e.fvel > 0.0 then
            e.anim_i = 1
            local nx, nz = e.x + (e.fvel + 150.0) * sins(e.yaw), e.z + (e.fvel + 150.0) * coss(e.yaw)
            local fy = floor_y(nx, e.y + 100.0, nz)
            local edge = not fy or fy < e.y - 300.0
            local hit = (not edge) and move()
            if (hit and e.at > 5) or edge or e.at > 150 then
                if hit then sound("big_pound", loudness(e, m, 4000.0)) end
                e.fvel, e.f = 0.0, 0.0
            end
        else
            e.anim_i = 2
            move()
            if e.f >= 24.0 then e.action, e.at, e.f = "final", 0, 0.0 end
        end
    elseif a == "final" then
        -- (racing_penguin_act_show_final_text: round to face +Z, then his say when the athlete is near; the star)
        if not e.told then
            local y0 = e.yaw
            e.yaw = turn_toward(e.yaw, 0, 200)
            if e.yaw == 0 and y0 == 0 then
                e.fvel, e.anim_i = 0.0, 3
                if m.dist < 400.0 + 120.0 and abs(m.feet - e.y) < 400.0 then
                    e.told = true
                    local won = e.won and not e.cheat
                    local id = (e.won and e.cheat) and W.cheat or (won and W.win or W.lose)
                    log("the racing penguin: after the race, dialog %d", id)
                    talk_cam(e)
                    say(id, function()
                        local G = package.loaded["game"]
                        if won and G and G.add_star then
                            local sx, sy, sz = to_scene(R.star[1], R.star[2], R.star[3])
                            local fx, fy, fz = to_scene(e.x, e.y + 200.0, e.z)
                            pcall(G.add_star, world, { kind = "star", pos = { sx, sy, sz }, id = R.id, from = { fx, fy, fz } })
                        end
                    end)
                end
            else
                -- (waddling round on the spot's floor: never off its edge)
                local fy = floor_y(e.x + 60.0 * sins(e.yaw), e.y + 100.0, e.z + 60.0 * coss(e.yaw))
                e.fvel, e.anim_i = (fy and fy > e.y - 100.0) and 4.0 or 0.0, 0
                local fi = floor(e.f) % 20
                if fi == 1 or fi == 11 then sound("big_penguin_walk", loudness(e, m, 2500.0)) end
            end
        else
            e.fvel, e.anim_i = 0.0, 3
        end
        move()
    end
    -- (bhv_penguin_race_finish_line_update: the athlete within 1000 of the line and past it, before he is at the bottom)
    if (a == "race" or a == "finish") and not e.reached and not e.won then
        local f = R.flag
        local ax, ay, az = m.x - f[1], m.feet - f[2], m.z - f[3]
        if ax * ax + ay * ay + az * az < 1000.0 * 1000.0 and az < 0.0 then
            e.won = true
            sound("race_fanfare", 1.0)
            log("the racing penguin: beaten to the line%s", e.cheat and " (cheating)" or "")
        end
    end
    -- (cur_obj_push_mario_away_from_cylinder 200 x 200 - not while they race: sliding at speed beside him, the
    -- shove put the athlete in the air and over the slide's edge, twice a race - "the slide is glitchin out",
    -- 2026-10-18, once the penguin could get down it)
    local dx, dz = m.x - e.x, m.z - e.z
    local d = sqrt(dx * dx + dz * dz)
    if d < 200.0 and m.feet < e.y + 200.0 and m.feet > e.y - 60.0 and pawn and a ~= "race" and a ~= "start" then
        local k = 200.0 - d
        local ux, uz = (d > 1.0) and dx / d or sins(e.yaw), (d > 1.0) and dz / d or coss(e.yaw)
        pcall(function()
            local l, r = pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation()
            pawn:K2_TeleportTo({ X = l.X - uz * k * S, Y = l.Y + ux * k * S, Z = l.Z }, r)
        end)
    end
    e.pushed = nil
end

-- Talking to Koopa the Quick ("standing next to him triggered his dialog make sure you actually stand in front of him
-- then press y to talk to him", 2026-10-16): within 400, before him (within 50 degrees of the way he faces), turned to
-- him, and a new press of Y (or E). True to talk.
local function ktq_talk(e, m)
    local down = false
    pcall(function()
        local pc = lib.controller()
        for _, k in ipairs({ "Gamepad_FaceButton_Top", "E" }) do
            if pc:IsInputKeyDown({ KeyName = FName(k) }) then down = true end
        end
    end)
    local fresh = down and not e.y_was
    e.y_was = down
    if not fresh then return false end
    if m.dist > 400.0 + 120.0 or abs(m.feet - e.y) > 300.0 then return false end
    if abs(s16(m.angle - e.yaw)) > 0x3000 then return false end            -- (before him: 67 degrees either side)
    if abs(s16(m.facing - s16(m.angle + 0x8000))) > 0x4000 then return false end
    return true
end

M.KTQ_SPEED = { thi = 0.88 }     -- Koopa the Quick's racing speed against Mario 64's, by scene (step_ktq)
local function step_ktq(e, m, pawn, world)
    if e.type == "bhvRacingPenguin" then return step_rpenguin(e, m, pawn, world) end
    local R = e.o.race
    e.at = (e.at or 0) + 1
    -- (his animation run a frame a step but in the race, where it goes by his speed: standing he was a statue -
    -- "koopa the quick is animationless frozen like a statue", 2026-10-16)
    if e.action ~= "race" then e.f = (e.f or 0.0) + 1.0 end
    -- (his flag waving: its pose set and the actor nudged so it shows)
    if e.flag and e.flag_at then
        e.flag_f = e.flag_f + 1
        local an = e.flag.data.anims and e.flag.data.anims[1]
        pcall(lib.set_pose, e.flag, e.flag_at[1], e.flag_at[2], e.flag_at[3], 0.0)
        if an then pcall(lib.pose, e.flag, an, e.flag_f) end
    end
    local a = e.action
    if a == "home" then e.action, a, e.at = "wait", "wait", 0 end
    if a == "wait" then
        e.fvel, e.anim_i = 0.0, R.idle or 7
        -- (koopa_the_quick_act_wait_before_race: he stands as he was put - he turned to the athlete wherever he was -
        -- and faces him only while he asks: DIALOG_FLAG_TURN_TO_MARIO)
        if e.asking then e.yaw = turn_toward(e.yaw, m.angle, 0x400) end
        if (e.cool or 0) > 0 then
            e.cool = e.cool - 1
        elseif not e.asking and e.at > 15 and ktq_talk(e, m) then
            e.asking = true
            talk_cam(e)
            ask(race_words(e).ask, function(answer)
                -- (the Y that answered still held: not a new press to ask again - "stuck in sign", 2026-10-16)
                e.asking, e.y_was = nil, true
                if answer == 1 then
                    e.action, e.at, e.wp, e.cheat, e.air_n = "start", 0, 1, nil, 0
                    local PL = package.loaded["platforms"]
                    if PL then PL.shot_from_cannon = nil end
                    sound("race_fanfare", 1.0)              -- (play_race_fanfare, for the "yes")
                    log("%s: the race is on", e.type)
                else
                    e.cool = 60
                end
            end)
        end
    elseif a == "start" then
        e.anim_i = R.idle or 7
        if e.at == 50 then
            sound("race_gun", 1.0)
            if R.music ~= false then ktq_music("level_slide") end
            e.action, e.at, e.fvel = "race", 0, 0.0
            -- (Koopa the Quick's race is timed on the HUD, TIME 0'00"00, from the gun till the athlete reaches the
            -- flag: level_control_timer SHOW/START here, STOP at bhv_koopa_race_endpoint_update. Not the penguin's.)
            if e.type ~= "bhvRacingPenguin" then e.clock = 0.0 end
        end
    elseif a == "race" then
        local path = R.path
        local last, target = path[e.wp], path[e.wp + 1]
        if not target then
            e.action, e.at = "stop", 0
        else
            local ox, oy, oz = target[1] - e.x, target[2] - e.y, target[3] - e.z
            local px, py, pz = target[1] - last[1], target[2] - last[2], target[3] - last[3]
            if px * ox + py * oy + pz * oz <= 0.0 then e.wp = e.wp + 1 end
            local yaw_to = s16(atan2s(oz, ox))
            local pitch_to = s16(atan2s(sqrt(ox * ox + oz * oz), -oy))
            local agility = R.agility
            e.yaw = turn_toward(e.yaw, yaw_to, floor(agility * 150.0))
            -- (Koopa the Quick a little slower than Mario 64's where M.KTQ_SPEED says: "koopas a little too fast" - Tiny-Huge
            -- Island's, 2026-10-29)
            local G = package.loaded["game"]
            local sk = (e.type ~= "bhvRacingPenguin" and M.KTQ_SPEED[(G and G.name) or ""]) or 1.0
            local want = agility * 6.0 * (1.0 + sins(pitch_to)) * sk
            e.fvel = approach(e.fvel, want, agility * 0.1 * 30.0 / 30.0)
            e.anim_i = R.run or 9
            if e.type == "bhvRacingPenguin" and e.won == nil then
                e.air_n = m.air and (e.air_n or 0) + 1 or 0
                if e.air_n > 60 and not e.cheat then e.cheat = true; log("the racing penguin: he saw that") end
                -- (bhv_penguin_race_shortcut_check_update: coming within 500 of the shortcut's marker is cheating too)
                local cx, cy, cz = m.x + 6393.0, m.y + 716.0, m.z - 7503.0
                if not e.cheat and cx * cx + cy * cy + cz * cz < 500.0 * 500.0 then
                    e.cheat = true
                    log("the racing penguin: he took the shortcut")
                end
            end
            -- (moved along his path as Mario 64's path-follower keeps him on it: forward at his speed the way he faces,
            -- drawn back toward the line when he drifts more than 60 off it; his feet on the floor under him while it is
            -- near the path's own height - up ledges and down dips with it - and his hop where the ground ahead drops
            -- away (a high one from his 8th point on); never down into a pit beside it. Walls and a floor-only walk left
            -- him stuck on ledges, in pits and inside the mountain: "koopa is getting stuck a lil bit again", 2026-10-16)
            local nx, nz = e.x + e.fvel * sins(e.yaw), e.z + e.fvel * coss(e.yaw)
            local vx, vz = target[1] - last[1], target[3] - last[3]
            local L2 = vx * vx + vz * vz
            local t = L2 > 0.0 and max(0.0, min(1.0, ((nx - last[1]) * vx + (nz - last[3]) * vz) / L2)) or 0.0
            local lx, lz = last[1] + vx * t, last[3] + vz * t
            local py = last[2] + (target[2] - last[2]) * t
            local ox, oz = nx - lx, nz - lz
            local off = sqrt(ox * ox + oz * oz)
            if off > 60.0 then
                local k = min(12.0, off - 60.0) / off
                nx, nz = nx - ox * k, nz - oz * k
            end
            e.x, e.z = nx, nz
            local fy = floor_y(e.x, max(e.y, py) + 50.0, e.z)
            local near = fy and fy > py - 250.0 and fy < py + 250.0
            if e.ground and e.vy <= 0.0 then
                local ahead = floor_y(e.x + 60.0 * sins(e.yaw), max(e.y, py) + 50.0, e.z + 60.0 * coss(e.yaw))
                if not ahead or ahead < e.y - 100.0 then
                    e.vy, e.ground = ((e.wp or 1) - 1 >= 8) and 80.0 or 40.0, false
                elseif near then
                    e.y = fy
                else
                    e.y = py
                end
            end
            if not e.ground or e.vy > 0.0 then
                e.vy = max(e.vy - 6.0, -75.0)
                local ny = e.y + e.vy
                if near and ny <= fy and e.vy <= 0.0 then
                    e.y, e.vy, e.ground = fy, 0.0, true
                elseif ny < py - 300.0 then
                    e.y, e.vy, e.ground = py, 0.0, true
                else
                    e.y = ny
                end
            end
            -- (and should he still get nowhere - not 150 nearer his next point in 10 s - on to it)
            do
                local dx, dz = target[1] - e.x, target[3] - e.z
                local d = sqrt(dx * dx + dz * dz)
                if not e.best_d or e.best_wp ~= e.wp or d < e.best_d - 150.0 then
                    e.best_d, e.best_wp, e.best_at = d, e.wp, e.at
                elseif e.at - e.best_at > 300 then
                    e.x, e.y, e.z, e.vy, e.ground = target[1], target[2] + 30.0, target[3], 0.0, false
                    e.best_d = nil
                    log("Koopa the Quick: stuck 10 s - on to point %d", e.wp + 1)
                end
            end
            -- (lost below his path - a wall pushed him into the mountain, where there is no floor, and he fell out of
            -- the world: "koopa the quick got lost on the way to the top", 2026-10-16 - back where he was going from)
            if e.y < math.min(last[2], target[2]) - 700.0 then
                e.x, e.y, e.z, e.vy, e.ground = last[1], last[2] + 30.0, last[3], 0.0, false
                log("Koopa the Quick: back on his path at point %d", e.wp)
            end
            -- (a teleport mid-race - a warp, a pipe, put back after a fall - is cheating, as the cannon is: "make sure
            -- the player cant cheat by using the teleports", 2026-10-16)
            if e.mprev and e.won == nil then
                local jx, jy, jz = m.x - e.mprev[1], m.y - e.mprev[2], m.z - e.mprev[3]
                if (jx * jx + jz * jz > 900.0 * 900.0 or jy > 900.0) and not e.cheat then
                    e.cheat = true
                    log("Koopa the Quick: the athlete teleported - cheating")
                end
            end
            e.mprev = { m.x, m.y, m.z }
            local fi = floor(e.f) % 20
            if fi == 2 or fi == 17 then sound("ktq_step", loudness(e, m, 2500.0)) end
            e.f = e.f + e.fvel * 0.09
        end
    elseif a == "stop" then
        e.fvel = approach(e.fvel, 0.0, 1.0)
        e.anim_i = (e.fvel > 0.5) and (R.run or 9) or (R.idle or 7)
        if e.fvel <= 0.5 and e.won ~= nil then
            -- (koopa_the_quick_act_after_race: stopped, he waits for him and says how it went; a fair win, the star)
            e.yaw = turn_toward(e.yaw, m.angle, 0x400)
            if not e.told and ktq_talk(e, m) then
                e.told = true
                local W = race_words(e)
                local won = e.won and not e.cheat
                local id = (e.won and e.cheat) and W.cheat or (won and W.win or W.lose)
                log("%s: after the race, dialog %d", e.type, id)
                talk_cam(e)
                say(id, function()
                    local G = package.loaded["game"]
                    if won and G and G.add_star then
                        local sx, sy, sz = to_scene(R.star[1], R.star[2], R.star[3])
                        local fx, fy, fz = to_scene(e.x, e.y + 200.0, e.z)
                        pcall(G.add_star, world, { kind = "star", pos = { sx, sy, sz }, id = R.id, from = { fx, fy, fz } })
                    end
                end)
            end
        end
        walk(e, 6.0, false)
    end
    -- the race clock: running till he is at the flag, then left showing his time
    if e.clock and not e.clock_done then
        e.clock = e.clock + 1.0 / 30.0
        local f = R.flag
        local ax, az = m.x - f[1], m.z - f[3]
        if ax * ax + az * az < 400.0 * 400.0 and abs(m.y - f[2]) < 600.0 then
            e.clock_done = true
            log("%s's race: his time %.2f s", e.type, e.clock)
        end
        local HP = _G.HEALTH
        if HP then HP.clock = e.clock end
    end
    -- (solid, as Mario 64 pushes Mario out of his hitbox - 60 round at his scale of 3, with Mario's 37: he was walked
    -- through, "koopa has no colissions", 2026-10-16)
    do
        local R = 60.0 * (e.scale or 3.0) + 37.0
        local dx, dz = m.x - e.x, m.z - e.z
        local d = sqrt(dx * dx + dz * dz)
        if pawn and d < R and m.feet < e.y + 300.0 and m.feet > e.y - 80.0 then
            if d < 1.0 then dx, dz, d = sins(e.yaw), coss(e.yaw), 1.0 end
            local out = (R - d + 1.0) * S
            local ux, uz = dx / d, dz / d
            pcall(function()
                local l = pawn:K2_GetActorLocation()
                pawn:K2_SetActorLocation({ X = l.X - uz * out, Y = l.Y + ux * out, Z = l.Z }, true, {}, false)
            end)
        end
    end
    -- the flag: whoever comes within 400 of it first
    if (a == "race" or a == "stop") and e.won == nil then
        local f = R.flag
        local ax, az = m.x - f[1], m.z - f[3]
        local kx, kz = e.x - f[1], e.z - f[3]
        -- (the penguin's finish line, bhv_penguin_race_finish_line_update: within 1000 of it and past it)
        local ay = m.y - f[2]
        local line = e.type == "bhvRacingPenguin" and ax * ax + ay * ay + az * az < 1000.0 * 1000.0 and az < 0.0
        if line or (ax * ax + az * az < 400.0 * 400.0 and abs(m.y - f[2]) < 600.0) then
            -- (bhv_koopa_race_endpoint_update: there first, the fanfare; his star waits for his words)
            e.won = true
            local PL = package.loaded["platforms"]
            if PL and PL.shot_from_cannon and e.type ~= "bhvRacingPenguin" then e.cheat = true end
            ktq_music(nil)
            sound("race_fanfare", 1.0)
            log("%s: beaten to the flag%s", e.type, e.cheat and " (cheating)" or "")
        elseif a == "stop" or kx * kx + kz * kz < 200.0 * 200.0 then
            e.won = false
            ktq_music(nil)
            log("Koopa the Quick: he got there first")
        end
    end
    e.pushed = nil
end

-- Mips' ten paths round the basement (inside_castle_seg7_trajectory_mips), Mario 64 units
local MIPS_PATHS = {
    { { -1831, -1177, -1178 }, { -1810, -1177, 284 }, { -2210, -1192, 715 }, { -3505, -1279, 715 }, { -3968, -1279, -31 }, { -4021, -1381, -1242 } },
    { { -3674, -1379, -962 }, { -3813, -1279, -41 }, { -3628, -1279, 755 }, { -2210, -1192, 715 }, { -1810, -1177, 284 }, { -1842, -1177, -1078 }, { -1604, -1177, -1445 } },
    { { -1463, -1210, -2231 }, { -1515, -1279, -3094 } },
    { { -2019, -1279, -3077 }, { -2559, -1279, -3043 }, { -2957, -1279, -2747 }, { -3031, -1262, -1947 }, { -2846, -1262, -1321 } },
    { { -3005, -1197, -1874 }, { -2967, -1279, -2582 }, { -2559, -1279, -3043 }, { -1984, -1262, -3068 }, { -1432, -1262, -3038 } },
    { { -1387, -1254, -2541 }, { -1541, -1177, -1446 } },
    { { -894, -1223, -1421 }, { -306, -1279, -1601 }, { -192, -1279, -2196 } },
    { { -187, -1279, -1662 }, { -805, -1238, -1406 }, { -1549, -1177, -1446 } },
    { { -1092, -1279, -3188 }, { -593, -1279, -3175 }, { -200, -1279, -2940 }, { -216, -1279, -2139 } },
    { { -214, -1279, -2432 }, { -160, -1283, -2900 }, { -640, -1283, -3220 }, { -1469, -1279, -3108 } },
}

-- (bhv_mips_find_furthest_waypoint_to_mario: of the paths starting within 800 of him, the one whose start is
-- furthest from the athlete)
local function mips_pick(e, m)
    local best, bd = nil, -10000.0
    for i, p in ipairs(MIPS_PATHS) do
        local w = p[1]
        local dx, dy, dz = w[1] - e.x, w[2] - e.y, w[3] - e.z
        if dx * dx + dy * dy + dz * dz < 800.0 * 800.0 then
            local d = (w[1] - m.x) ^ 2 + (w[3] - m.z) ^ 2
            if bd < d then best, bd = i, d end
        end
    end
    return best
end

-- (cur_obj_follow_path, as Mips runs it: the waypoint after the last one he passed - after the end of the path he
-- last ran, the new path's start; his very first time, his path's second - is passed once the way from the last one
-- to it and from him to it no longer agree. He heads straight at it, no turning. true at the end of the path)
local function mips_follow(e)
    local path = MIPS_PATHS[e.mpath]
    local lp, li = e.mprev_p or path, e.mprev_i or 1
    local last = lp[li]
    local tp, ti = lp, li + 1
    if not lp[ti] then tp, ti = path, 1 end
    local w = tp[ti]
    local ox, oy, oz = w[1] - e.x, w[2] - e.y, w[3] - e.z
    e.yaw = s16(atan2s(oz, ox))
    if (w[1] - last[1]) * ox + (w[2] - last[2]) * oy + (w[3] - last[3]) * oz <= 0.0 then
        e.mprev_p, e.mprev_i = tp, ti
        if not tp[ti + 1] then return true end
    end
    return false
end

-- Mips, as Mario 64's (mips.inc.c): he waits; the athlete within 500, he runs one of his paths round the basement
-- (40 a frame, 45 for the second star) and waits at its end; with no path starting near him, he stops for good. He
-- had fled straight away from the athlete instead, "he doesnt follow the correct pathing", 2026-10-19. A push close
-- by catches him, and he leaves his star
local function step_mips(e, m, pawn, world)
    e.at = (e.at or 0) + 1
    if e.action == "held" then e.caught = nil; e.f = e.f + 1.0; return end
    if e.caught then
        -- (mips_held: caught, he has his say - DIALOG_084, or 162 for the second star - and his star comes out of
        -- him; then he is gone)
        e.caught = nil
        local n = e.o.mips_star or 3
        local G = package.loaded["game"]
        local sx, sy, sz = to_scene(e.x, e.y, e.z)
        e.action, e.fvel, e.anim_i = "held", 0.0, 0
        log("Mips caught")
        local function give()
            e.action, e.timer = "dying", 0
            if n ~= 0 and G and G.gift_star then pcall(G.gift_star, n, { sx, sy, sz }) end
        end
        if not say(n == 4 and 162 or 84, give, e) then give() end
        return
    end
    if e.action == "home" or e.action == "idle" then
        -- (bhv_mips_act_wait_for_nearby_mario)
        e.action, e.anim_i, e.fvel = "idle", 0, 0.0
        walk(e, 4.0)
        if m.dist < 500.0 then
            local i = mips_pick(e, m)
            if i then
                e.mpath, e.action, e.anim_i = i, "path", 1
            else
                e.action = "stay"            -- (MIPS_ACT_WAIT_FOR_ANIMATION_DONE, then idle for good)
            end
        end
    elseif e.action == "path" then
        -- (bhv_mips_act_follow_path)
        local at_end = mips_follow(e)
        e.fvel = (e.o.mips_star == 4) and 45.0 or 40.0
        walk(e, 4.0)
        if at_end then e.action, e.anim_i, e.fvel = "idle", 0, 0.0 end
        if e.at % 10 == 0 then
            -- (each stride in the water - his feet under its top - a splash and the water's sound, as Mario 64's: the
            -- shallow water splash and SOUND_OBJ_MIPS_RABBIT_WATER; "he also doesnt react to the water", 2026-10-19)
            local G = package.loaded["game"]
            local sx, sy, sz = to_scene(e.x, e.y, e.z)
            local top = G and G.water_at and G.water_at(sx, sy)
            if top and sz < top then
                sound("step_water", 0.7 * loudness(e, m, 2000.0))
                local EF = package.loaded["envfx"]
                if EF and EF.wade_splash then pcall(EF.wade_splash, sx, sy, top) end
            else
                sound("en_koopa_walk", 0.4 * loudness(e, m, 2000.0))
            end
        end
    else
        e.anim_i, e.fvel = 0, 0.0
        walk(e, 4.0)
    end
    e.f = e.f + ((e.action == "path") and 1.5 or 1.0)
end

-- a baby penguin: carried in front of the athlete once picked up; the lost one, brought to its mother, wins her star
local function step_penguin(e, m, pawn, world)
    -- (hurt while he holds it - a hit, a burn, knocked flat - he lets go of it, as Mario 64's hurt actions drop what
    -- Mario holds: "if you get damaged while holding him it should make you drop him", 2026-10-18)
    if e.carried and not e.toggle then
        local HP = _G.HEALTH
        local B, R = package.loaded["burn"], package.loaded["ragdoll"]
        local hurt = (HP and ((HP.hurt or 0) > 0 or HP.dead_t or (e.hp_seen and HP.health < e.hp_seen - 8)))
            or (B and B.active) or (R and R.active)
        if hurt then e.toggle = true; log("the baby penguin: dropped (hurt)") end
        e.hp_seen = HP and HP.health or nil
    end
    if e.toggle then
        e.toggle = nil
        e.carried = not e.carried
        sound(e.carried and "en_penguin" or "box_land", 0.8)
        if not e.carried then
            e.x, e.z = m.x + sins(m.facing) * 120.0, m.z + coss(m.facing) * 120.0
            e.y = floor_y(e.x, m.y + 100.0, e.z) or e.y
            e.vy, e.ground, e.paction, e.pt, e.hp_seen = 0.0, false, 0, 0, nil
        end
    end
    if e.carried then
        e.x, e.y, e.z = m.x + sins(m.facing) * 60.0, m.y + 40.0, m.z + coss(m.facing) * 60.0
        e.yaw = m.facing
        if not e.home_again then
            for _, mo in ipairs(M.list) do
                local near = mo.type == "bhvTuxiesMother" and (mo.x - e.x) ^ 2 + (mo.z - e.z) ^ 2 < 400.0 * 400.0 and abs(mo.y - e.y) < 400.0
                -- (tuxies_mother_act_1: hers if its number is hers; another baby - DIALOG_059, "that's not my baby", and
                -- it is put down there and then. It did nothing: "giving the other baby penguin to the mom does
                -- nothing", 2026-10-18. Taken off a good way, she says it again if it comes back.)
                local mine = (((e.o.bp or 0) >> 16) & 0xFF) == (((mo.o.bp or 0) >> 16) & 0xFF)
                if mo.type == "bhvTuxiesMother" and not near and e.wrong_told
                    and (mo.x - e.x) ^ 2 + (mo.z - e.z) ^ 2 > 700.0 * 700.0 then e.wrong_told = nil end
                if near and not mine and not e.wrong_told and not mo.reunited then
                    e.wrong_told, e.toggle = true, true
                    talk_cam(e)
                    say(59, nil, mo)
                    log("the wrong baby penguin brought to its mother")
                end
                if near and mine then
                    e.home_again, e.carried, mo.reunited = true, false, true
                    e.x, e.y, e.z = mo.x + 150.0, mo.y, mo.z
                    -- (tuxies_mother_act_1: her thanks, DIALOG_058, then her star out of her, over to where Mario 64
                    -- sends it)
                    talk_cam(e)
                    say(58, function()
                        local G = package.loaded["game"]
                        if G and G.add_star then
                            local sx, sy, sz = to_scene(3167.0, -4300.0, 5108.0)
                            local fx, fy, fz = to_scene(mo.x, mo.y + 200.0, mo.z)
                            pcall(G.add_star, world, { kind = "star", pos = { sx, sy, sz }, id = ((mo.o.bp or 0) >> 24) & 0xFF,
                                                       from = { fx, fy, fz } })
                        end
                    end)
                    sound("right_answer", 1.0)
                    log("the lost baby penguin is back with its mother")
                end
            end
        end
    else
        -- (free, as Mario 64's small penguin (tuxie.inc.c small_penguin_act_0/1/2/5): he stands, then waddles over to
        -- the athlete - from 600 off, within 1000 - and keeps 300 away, backing off if he comes nearer; by his mother
        -- he potters round her. Each time he stops he takes a new step speed, distance and turn, as Mario 64's does.
        -- He stood still, only turning: "baby penguin doesnt move", 2026-10-18.)
        local mother, md = nil, nil
        for _, mo in ipairs(M.list) do
            if mo.type == "bhvTuxiesMother" then
                local d = sqrt((mo.x - e.x) ^ 2 + (mo.z - e.z) ^ 2)
                if not md or d < md then mother, md = mo, d end
            end
        end
        local act = e.paction or 0
        e.pt = (e.pt or 0) + 1
        local function go(n) e.paction, e.pt = n, 0 end
        if act == 0 then
            e.anim_i = 3
            if e.pt == 1 then
                e.pturn = floor(math.random() * 0x400)
                e.pdist = math.random() * 100.0
                e.pspeed = math.random()
                e.fvel = 0.0
                if mother and md < 1000.0 then go(5) end
            end
            if (e.paction or 0) == 0 then
                if m.dist < 1000.0 and m.dist > (e.pdist or 0.0) + 600.0 then go(1)
                elseif m.dist < (e.pdist or 0.0) + 300.0 then go(2) end
            end
        elseif act == 1 then
            e.anim_i = 0
            e.fvel = (e.pspeed or 0.0) + 3.0
            e.yaw = turn_toward(e.yaw, m.angle, (e.pturn or 0) + 0x600)
            if m.dist < (e.pdist or 0.0) + 300.0 or m.dist > 1100.0 then go(0) end
        elseif act == 2 then
            e.anim_i = 0
            e.fvel = (e.pspeed or 0.0) + 3.0
            e.yaw = turn_toward(e.yaw, s16(m.angle + 0x8000), (e.pturn or 0) + 0x600)
            if e.pt == 1 and mother and md < 1000.0 then go(5)
            elseif m.dist > (e.pdist or 0.0) + 500.0 then go(0) end
        elseif act == 5 then
            e.anim_i = 0
            if mother then
                e.fvel = (m.dist < 1000.0) and 2.0 or 0.0
                local to = s16(atan2s(mother.z - e.z, mother.x - e.x))
                e.yaw = turn_toward(e.yaw, (md > 200.0) and to or s16(to + 0x8000), 0x400)
            else
                go(0)
            end
        end
        e.vy = e.vy or 0.0
        walk(e, 4.0, true)
        -- (walls round him: pushed out, Mario 64's at his feet + 10)
        if H.wall_near and e.fvel > 0.0 then
            local sx, sy, sz = to_scene(e.x, e.y + 10.0, e.z)
            local hit, px, py = H.wall_near(sx, sy, sz, 50.0 * S, 2.0)
            if hit and (px ~= 0.0 or py ~= 0.0) then e.x, e.z = e.x + py / S, e.z - px / S end
        end
        if e.fvel > 0.0 and e.edge then e.yaw = s16(e.yaw + 0x4000) end      -- (not off a ledge: round it)
        if e.fvel > 0.0 and e.f % 10 == 0 then sound("big_penguin_walk", 0.2 * loudness(e, m, 1500.0)) end
    end
    e.f = e.f + 1
end

-- WDW's water level crystals (wdw_water_level.inc.c): touched, the water runs to the crystal's height
local function step_diamond(e, m)
    local G = package.loaded["game"]
    if not (G and G.water_level and G.water_level()) then return end
    local dx, dz = m.x - e.x, m.z - e.z
    local touching = dx * dx + dz * dz < 160.0 * 160.0 and m.feet < e.y + 200.0 and m.y + 120.0 > e.y - 100.0
    if e.action == "home" then e.action = "idle" end
    if e.action == "idle" then
        if touching and not G.water_changing then
            e.action, G.water_changing = "change", true
            sound("water_trig", 1.0)
        end
    elseif e.action == "change" then
        local lvl = G.water_level()
        local new = lvl + math.max(-10.0, math.min(10.0, e.hy - lvl))
        G.set_water_level(new)
        e.yaw = s16(e.yaw + 0x800)
        local SFX = package.loaded["sfx"]
        if SFX and SFX.hold then SFX.hold("loop_water_drain", 0.8) end
        if new == e.hy then e.action = "spun" end
    elseif not touching then
        e.action, G.water_changing = "idle", false
    end
end

-- wind: the athlete pushed `k` units a frame toward yaw `dir` (moved, as a treadmill moves him)
-- 20 frames blown, and the wind takes Mario's cap off him (act_getting_blown's actionTimer, mario_blow_off_cap): the
-- frames counted while it keeps blowing on him, started again once it has stopped for half a second
-- (counted from the wind first catching him and on after it stops, as act_getting_blown's actionTimer runs on through
-- his being blown back: counting only the frames it blew, Fwoosh's 12-frame puff never took the cap - "you said it knocks
-- off the cap which it doesnt seem to do", 2026-10-27. Called each frame with no `dir` to look at the clock)
local blown = { at = 0.0 }
local function blown_cap(dir)
    local now = os.clock()
    if dir then
        if not blown.start or now - blown.at > 0.5 then blown.start, blown.done = now, false end
        blown.at, blown.dir = now, dir
        local MC = package.loaded["mariocap"]
        if MC then MC.blown_at = now end        -- (while he is blown, the cap is not his for the touching)
        return
    end
    if blown.start and not blown.done and now - blown.start >= 20.0 / 30.0 then
        blown.done = true
        local MC = package.loaded["mariocap"]
        if MC and MC.blow_off then
            -- (the way he is blown, in the scene's own turning: Mario 64's x, z are the scene's y, -x)
            pcall(MC.blow_off, lib.pawn(), math.deg(math.atan(sins(blown.dir), -coss(blown.dir))))
        end
    end
end

local function push_athlete(dir, k)
    local pawn = lib.pawn()
    if not pawn then return end
    local dx, dz = sins(dir) * k, coss(dir) * k
    pcall(function()
        local l, r = pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation()
        pawn:K2_TeleportTo({ X = l.X - dz * S, Y = l.Y + dx * S, Z = l.Z }, r)
    end)
end

-- The wind seen (strong_wind_particle.inc.c, spawned by cur_obj_spawn_strong_wind_particles): every other frame a
-- mist puff three times its size out of the blower (within 50 of it), at 100 a frame along its aim, spread up to
-- 6000 either way, for 15 frames, 100/255 opaque. A pool of eight per blower, shown and hidden in turn. (The
-- snowman's breath and Fwoosh's blew unseen, 2026-10-15.)
local function wind_puffs(e, yaw, ox, oy, oz)
    if e.wpool == nil then
        e.wpool = {}
        local mist = H.actor_data and H.actor_data("mist")
        local world = lib.world()
        if mist and world then
            for i = 1, 8 do
                local p = lib.make_instance(world, mist, { X = OFFSET.X, Y = OFFSET.Y, Z = OFFSET.Z }, 0.0, 3.0)
                if p then
                    p.moves = true
                    pcall(lib.see_through, world, p, 100.0 / 255.0)
                    pcall(function() p.actor:SetActorHiddenInGame(true) end)
                    e.wpool[#e.wpool + 1] = { inst = p, life = 0 }
                end
            end
        end
    end
    e.wind_t = (e.wind_t or 0) + 1
    if e.wind_t % 2 ~= 0 then return end
    for _, w in ipairs(e.wpool) do
        if w.life <= 0 then
            local a = yaw + (math.random() * 2.0 - 1.0) * 6000.0
            w.life = 15
            w.x = (ox or e.x) + (math.random() - 0.5) * 100.0
            w.y = (oy or e.y) + (math.random() - 0.5) * 100.0
            w.z = (oz or e.z) + (math.random() - 0.5) * 100.0
            w.vx, w.vz = sins(a) * 100.0, coss(a) * 100.0
            w.shown = false
            break
        end
    end
end

local function move_wind_puffs(e)
    for _, w in ipairs(e.wpool or {}) do
        if w.life > 0 then
            w.life = w.life - 1
            w.x, w.z = w.x + w.vx, w.z + w.vz
        end
    end
end

-- (billboards: each puff's face, its -x side, turned to the camera)
local function render_wind_puffs(e, cx, cy, cz)
    for _, w in ipairs(e.wpool) do
        if w.life > 0 then
            local sx, sy, sz = to_scene(w.x, w.y, w.z)
            sx, sy, sz = sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z
            local dx, dy, dz = cx - sx, cy - sy, cz - sz
            pcall(function()
                w.inst.actor:K2_TeleportTo({ X = sx, Y = sy, Z = sz },
                    { Pitch = -math.deg(atan(dz, sqrt(dx * dx + dy * dy))), Yaw = math.deg(atan(dy, dx)) + 180.0, Roll = 0.0 })
                if not w.shown then w.shown = true; w.inst.actor:SetActorHiddenInGame(false) end
            end)
        elseif w.shown then
            w.shown = false
            pcall(function() w.inst.actor:SetActorHiddenInGame(true) end)
        end
    end
end

-- (strong_wind_particle.inc.c: the breath's puffs die within 300 of the big penguin's middle - a point 60 behind
-- and 100 aside of him - so whoever has him between themselves and the snowman is not blown)
local function penguin_shields(e, m)
    local PL = package.loaded["platforms"]
    if not (PL and PL.list) then return false end
    for _, p in ipairs(PL.list) do
        if p.o and p.o.bhv == "walk_penguin" then
            local wx = p.x + sins(0xDBB0) * 60.0 + 100.0 * sins(0x1BB0)
            local wz = p.z + coss(0xDBB0) * 60.0 + 100.0 * coss(0x1BB0)
            local ax, az = m.x - e.x, m.z - e.z
            local len = sqrt(ax * ax + az * az)
            if len > 1.0 then
                local ux, uz = ax / len, az / len
                local qx, qz = wx - e.x, wz - e.z
                local along = qx * ux + qz * uz
                if along > 0.0 and along < len and abs(qx * uz - qz * ux) < 300.0 then return true end
            end
        end
    end
    return false
end

-- Blown off: Mario 64's strong wind (interact_strong_wind, act_getting_blown) throws him back off his feet - backward at
-- 24 a frame and 12 up, faster by 6 a frame to 60, then easing to 16, his fall a tenth of its weight and heavier as he
-- drops (0.05 a frame toward the whole) - where the athlete was only shoved along the ground and walked on against it:
-- "when being pushed of the mountain by the wind it doesnt blow the charater off", 2026-10-26. A Mario 64 unit a frame is
-- 22.5 cm/s. His lighter fall is an upward nudge a step, not a change of the engine's gravity, so nothing is left behind
-- if the steps stop. Over when he lands. (Fields of M: this file is at Lua's 200 locals.)
function M.blow_athlete(dir)
    if M.blow then return end
    local pawn = lib.pawn()
    if not pawn then return end
    local G = package.loaded["game"]
    if G and (G.swim or G.carried) then return end
    local cm = pawn.CharacterMovement
    if cm.MovementMode == 0 then return end                 -- (limp: his body is the engine's)
    local b = { dir = dir, v = 24.0 * 22.5, st = 0, t = 0, g = 0.1 }
    M.blow = b
    pcall(function() pawn:LaunchCharacter({ X = -coss(dir) * b.v, Y = sins(dir) * b.v, Z = 12.0 * 22.5 }, true, true) end)
    sound("mario_waaaooow", 1.0)
    log("blown off by the wind")
end
function M.blow_step()
    local b = M.blow
    if not b then return end
    b.t = b.t + 1
    local pawn = lib.pawn()
    local cm = pawn and pawn.CharacterMovement
    if not cm or b.t > 180 or (b.t > 6 and cm.MovementMode ~= 3) then M.blow = nil; return end
    if b.st == 0 then
        b.v = b.v + 6.0 * 22.5
        if b.v >= 60.0 * 22.5 then b.v, b.st = 60.0 * 22.5, 1 end
    elseif b.v > 16.0 * 22.5 then
        b.v = math.max(16.0 * 22.5, b.v - 0.8 * 22.5)
    end
    pcall(function()
        local v = cm.Velocity
        if v.Z < 0.0 and b.g < 1.0 then b.g = math.min(1.0, b.g + 0.05 / 4.0) end
        local lift = (1.0 - b.g) * 980.0 * cm.GravityScale * STEP
        cm.Velocity = { X = -coss(b.dir) * b.v, Y = sins(b.dir) * b.v, Z = v.Z + lift }
    end)
end

-- The breath's reach either side of where it is aimed: Mario 64's puffs turn by up to 12 x 500 / 2 off it
-- (strong_wind_particle.inc.c, random_f32_around_zero) - aimed at him no further than 0x1500 off the snowman's own way,
-- so the bridge's whole middle was blown, the penguin the only shelter; counted by the aim alone, a third of it was not:
-- "the hitbox isnt correct able to stand in the open and not get knocked off", 2026-10-26.
-- Then the whole of what is before him: from beside the bridge's middle a cone of 46 degrees round his aim left its two
-- ends calm, stood on in the open - "able to stand in open without penguin", 2026-10-26. 90 each way (0x1500 + this =
-- 0x4000): behind the penguin is the only shelter on it.
M.WIND_SPREAD = 0x4000 - 0x1500
-- ...and as far as it pushes: the last metre and a half at each end of the bridge calm (1206 and 1274 from him - its
-- middle 571), to start from - with no word first (DIALOG_153 left out: "getting blown off the second dialog ends, lets
-- just remove the dialog", 2026-10-26), it blew from the moment he came near. Its puffs seen out to Mario 64's 1500.
M.WIND_REACH = 1050.0
-- SL's snowman's breath across the ice bridge
local function step_wind(e, m)
    blown_cap(nil)
    M.blow_step()
    move_wind_puffs(e)
    -- (Mario 64's snowman speaks first, DIALOG_153, and only then blows - left out here: M.WIND_REACH)
    local away = s16(m.angle)
    local off = s16(away - e.yaw)
    if m.dist < 1500.0 and abs(m.y - e.y) < 500.0 then
        -- (bhv_sl_snowman_wind_loop: aimed at him, but no more than 0x1500 off its own way - here as far as it blows,
        -- M.WIND_SPREAD, the puffs seen where he is blown)
        local lim = 0x1500 + M.WIND_SPREAD
        wind_puffs(e, e.yaw + math.max(-lim, math.min(lim, off)))
    end
    if m.dist < M.WIND_REACH and abs(m.y - e.y) < 500.0 and abs(off) < 0x1500 + M.WIND_SPREAD and not penguin_shields(e, m) then
        push_athlete(away, 9.0)
        M.blow_athlete(away)
        blown_cap(away)
        local SFX = package.loaded["sfx"]
        if SFX and SFX.hold then SFX.hold("loop_wind", 0.8) end
    end
end

-- TTM's Fwoosh
M.FWOOSH_PUSH = 20.0            -- (Mario 64 units a frame, its puff's shove: step_fwoosh - 4.5 m/s, still under his run;
                                -- at 12, 2.7 m/s, it was barely felt: "stronger", 2026-10-27)
local function step_fwoosh(e, m)
    blown_cap(nil)
    move_wind_puffs(e)
    e.at = (e.at or 0) + 1
    e.circ = (e.circ or 0) + 0xC8
    e.x, e.z = e.hx + 100.0 * coss(e.circ), e.hz + 100.0 * sins(e.circ)
    e.y = e.hy + 2.0 * coss(e.at * 0x800) * 3.0 + 36.0
    if m.dist > 2500.0 then e.blow, e.near = nil, 0; return end
    e.yaw = turn_toward(e.yaw, m.angle, 0x200)
    if e.blow then
        e.grow = e.grow - 0.005
        e.sk = math.max(1.0, (e.sk or 3.0) + e.grow)
        if e.grow < -0.16 then
            e.blow, e.near = nil, 0
        elseif e.grow < -0.1 then
            -- the puff: blown back (and seen: out of his mouth, 120 in front of him and 50 down, as he is scaled) - 12 a
            -- frame, about 2.7 m/s, slower than he runs: steered and run against, a metre's shove if he stands. At 30 (6.8
            -- m/s) it carried him off the path whatever he did - "need to be able to control player in wind", Tall Tall
            -- Mountain, 2026-10-26.
            if m.dist < 1500.0 then push_athlete(m.angle, M.FWOOSH_PUSH); blown_cap(m.angle) end
            local k = e.sk or 3.0
            wind_puffs(e, e.yaw, e.x + sins(e.yaw) * 120.0 * k, e.y - 50.0 * k, e.z + coss(e.yaw) * 120.0 * k)
            local SFX = package.loaded["sfx"]
            if SFX and SFX.hold then SFX.hold("loop_blow_wind", loudness(e, m, 3000.0)) end
        end
    else
        e.sk = approach(e.sk or 3.0, 3.0, 0.012)
        if m.dist < 1000.0 then
            e.near = (e.near or 0) + 1
            if e.near > 100 then e.blow, e.grow = true, 0.14 end
        else
            e.near = 0
        end
    end
    pcall(function() e.inst.actor:SetActorScale3D({ X = e.sk, Y = e.sk, Z = e.sk }) end)
end

-- SSL's tornado
local function tweester_size(e, pre)
    local sc = pre * 0.4
    local t = e.stimer or 0
    local sx = ((coss(t) + 1.0) * 0.5 * 0.3 + 1.0) * sc
    local sy = ((-coss(t) + 1.0) * 0.5 * 0.5 + 0.5) * sc
    e.stimer = t + 0x200
    e.yaw = s16(e.yaw + 0x2C00)
    pcall(function() e.inst.actor:SetActorScale3D({ X = math.max(sx, 0.01), Y = math.max(sx, 0.01), Z = math.max(sy, 0.01) }) end)
end
-- (seen coming: grown from nothing once he is within `TWEESTER_SEE` (Mario 64 units - its own 1500, 11 m, left it unseen
-- till he was on it: "tornados are invisible sometimes", 2026-11-07), and gone again only after it has thrown him, or
-- once he is far off; with him out of its reach it waits at home, turning, not gone - always there it never spun nor
-- went: "not spinning now they never go away", 2026-11-07)
M.TWEESTER_SEE = 4000.0
M.TWEESTER_SEEN = false
M.tweester_size = tweester_size
local function step_tweester(e, m, pawn)
    e.at = (e.at or 0) + 1
    local reach = (((e.o.bp or 0) >> 16) & 0xFF) * 100.0
    local hx, hz = m.x - e.hx, m.z - e.hz
    local him_home = sqrt(hx * hx + hz * hz)
    local see = M.TWEESTER_SEE or 1500.0
    if e.action == "home" or e.action == "hidden" then
        e.action = "hidden"
        e.x, e.y, e.z = e.hx, e.hy, e.hz
        tweester_size(e, 0.0)
        if m.dist < see then e.action, e.at = "grow", 0 end
    elseif e.action == "grow" then
        tweester_size(e, e.at / 60.0)
        if e.at >= 60 then e.action, e.at = "chase", 0 end
    elseif e.action == "chase" then
        local SFX = package.loaded["sfx"]
        if SFX and SFX.hold then SFX.hold("loop_wind", loudness(e, m, 3000.0)) end
        local wait = false
        if him_home < reach and not e.thrown then
            e.yaw0 = turn_toward(e.yaw0 or 0, m.angle, 0x200)
        elseif (e.x - e.hx) ^ 2 + (e.z - e.hz) ^ 2 < 200.0 * 200.0 then
            -- (home: having thrown him, it shrinks away - and comes again; else it waits there for him, turning)
            if e.thrown then e.action, e.at = "shrink", 0 end
            wait = true
        else
            local ang = s16(atan2s(e.hz - e.z, e.hx - e.x))
            e.yaw0 = turn_toward(e.yaw0 or 0, ang, 0x200)
        end
        if m.dist > see + 1000.0 then e.action, e.at = "shrink", 0 end
        if not wait then
            local nx, nz = e.x + 20.0 * sins(e.yaw0), e.z + 20.0 * coss(e.yaw0)
            local fy = floor_y(nx, e.y + 200.0, nz)
            if fy and abs(fy - e.y) < 200.0 then e.x, e.z, e.y = nx, nz, fy end
        end
        tweester_size(e, 1.0)
        -- caught (its hitbox: 1500 round by its width scale, 0.4 grown): up it and out of the top twirling, steered
        -- down slowly (twirl.lua) - how Mario reaches Shifting Sand Land's pillars
        local dx, dz = m.x - e.x, m.z - e.z
        if pawn and not e.thrown and dx * dx + dz * dz < 600.0 * 600.0 and m.feet < e.y + 800.0 and m.y > e.y - 100.0 then
            e.thrown = true
            sound("en_swoop", 1.0)
            local okt, TW = pcall(require, "twirl")
            if okt and TW and TW.catch then
                TW.catch(pawn, function() return to_scene(e.x, e.y, e.z) end,
                    function() return 4000.0 * ((-coss(e.stimer or 0) + 1.0) * 0.5 * 0.5 + 0.5) * 0.4 end)
            else
                pcall(lib.bounce, pawn, 0.0, 0.0, 1400.0)
                local G = package.loaded["game"]
                if G then G.no_fall_until, G.air = os.clock() + 8.0, false end
            end
            log("caught by a tornado")
        end
    elseif e.action == "shrink" then
        tweester_size(e, math.max(0.0, (60 - e.at) / 60.0))
        if e.at > 60 and (him_home > 2500.0 or e.at > 360) then e.action, e.thrown = "hidden", nil end
    end
end

-- Eyerok and his hands: eyerok.lua, Mario 64's fight ported whole (its helpers from here, M.EYX)
M.EYX = { sound = sound, floor_y = floor_y, hurt = hurt, say = say, talk_cam = talk_cam, boss_music = boss_music,
          to_scene = to_scene, log = log }
local function step_eyerok(e, m, pawn, world)
    local EY = package.loaded["eyerok"] or require("eyerok")
    return EY.step_boss(e, m, pawn, world, M.EYX)
end
local function step_eyerok_hand(h, m, pawn)
    local EY = package.loaded["eyerok"] or require("eyerok")
    return EY.step_hand(h, m, pawn, M.EYX)
end

-- BBH's merry-go-round Boos (bhv_merry_go_round_boo_manager_loop): within 1000 of it, a Boo comes out every two
-- seconds while fewer than two are about, five in all; the five beaten, the puzzle jingle and the Big Boo
local function spawn_boo(world, mgr, ty)
    local o = { type = ty, sm64 = { mgr.x, mgr.y, mgr.z }, yaw = mgr.o.yaw, geo = "boo_geo", bp = mgr.o.bp }
    local ok, err = pcall(M.add, world, o)
    if not ok then log("%s: %s", ty, tostring(err)) end
end
local function step_boo_mgr(e, m, pawn, world)
    e.at = (e.at or 0) + 1
    if e.done or m.dist >= 1000.0 or e.at < 60 then return end
    e.at = 0
    local killed = M.boos_beaten.mgr or 0
    e.spawned = e.spawned or 0
    if killed >= 5 then
        e.done = true
        spawn_boo(world, e, "bhvMerryGoRoundBigBoo")
        sound("puzzle_jingle", 1.0)
        log("the merry-go-round's Big Boo comes out")
    elseif e.spawned < 5 and e.spawned - killed < 2 then
        e.spawned = e.spawned + 1
        spawn_boo(world, e, "bhvMerryGoRoundBoo")
    end
end

-- a bookend shot out at him, already on its way (Mario 64's flying bookend in its action 3)
function M.spawn_bookend(world, x, y, z, yaw, from)
    local o = { type = "bhvFlyingBookend", sm64 = { x, y, z }, yaw = -(yaw * 360.0 / 65536.0), geo = "bookend_geo", bp = 0 }
    local n = #M.list
    M.add(world, o)
    local b = M.list[#M.list]
    if #M.list > n and b.type == "bhvFlyingBookend" then
        b.action, b.at, b.from = "rise", 25, from or true
        return b
    end
end
-- BBH's library: bookends shoot out of the shelves he faces (bhv_bookend_spawn_loop: within 600, it facing him)
local function step_book_spawn(e, m, pawn, world)
    e.at = (e.at or 0) + 1
    if e.at > 40 and m.dist < 600.0 and abs(s16(m.angle - e.yaw)) < 0x2000 then
        local n = 0
        for _, b in ipairs(M.list) do if b.from == e and b.action ~= "gone" then n = n + 1 end end
        if n < 2 then
            e.at = 0
            M.spawn_bookend(world, e.x, e.y, e.z, e.yaw, e)
            sound("en_default_death", loudness(e, m, 2000.0))
        end
    end
end

-- CCM's snowman (snowman.inc.c)
local SNOW_SPOT = { -4230.0, -1344.0, 1813.0 }
local function snow_head()
    for _, h in ipairs(M.list) do if h.type == "bhvSnowmansHead" then return h end end
end
local function snow_scale(e)
    pcall(function() e.inst.actor:SetActorScale3D({ X = e.sk, Y = e.sk, Z = e.sk }) end)
    e.y = e.gy + 180.0 * e.sk
end
-- (a built snowman pushes him off its sides: cur_obj_push_mario_away_from_cylinder)
local function snow_push(e, m, r, top)
    local dx, dz = m.x - e.x, m.z - e.z
    local d = sqrt(dx * dx + dz * dz)
    if d < r and m.feet < top and m.y > top - 900.0 then push_athlete(m.angle, math.min(30.0, r - d)) end
end
local function step_snow_body(e, m, pawn, world)
    e.at = (e.at or 0) + 1
    e.sk = e.sk or 0.4
    local a = e.action
    if a == "home" then e.action, a = "wait", "wait" end
    if a == "wait" then
        if m.dist < 400.0 and not e.talking then
            -- (bhv_snowmans_bottom_loop: his DIALOG_110 first, then down he rolls)
            e.talking = true
            talk_cam(e)
            say(110, function()
                e.talking = nil
                e.action, e.at = "ready", 0
            end)
        end
        return
    elseif a == "ready" then
        -- (a moment after his words before he goes, for the athlete to get out of the way and away: it rolled the frame
        -- the message shut, and ran him over - "the snowball starts going the second the dialog ends instead of giving
        -- the player a second", 2026-10-18)
        if e.at >= 45 then
            e.action, e.at, e.fvel, e.wp, e.cp = "roll", 0, 10.0, 1, false
            log("the snowman's body starts to roll")
        end
        return
    elseif a == "missed" then
        -- (create_respawner: back at the top once he is far away)
        local dx, dz = m.x - e.hx, m.z - e.hz
        if dx * dx + dz * dz > 3000.0 * 3000.0 then
            e.x, e.z, e.gy, e.sk, e.pitch, e.action = e.hx, e.hz, e.hy, 0.4, 0, "wait"
            snow_scale(e)
            pcall(function() e.inst.actor:SetActorHiddenInGame(false) end)
        end
        return
    elseif a == "built" then
        snow_push(e, m, 210.0, e.gy + 550.0)
        return
    end
    -- the checkpoint on the way down (bhvSnowmansBodyCheckpoint): he went by it
    if not e.cp then
        local dx, dy, dz = m.x + 402.0, m.y - 461.0, m.z + 2898.0
        if dx * dx + dy * dy + dz * dz < 800.0 * 800.0 then e.cp = true end
    end
    if a == "roll" or a == "free" then
        local SFX = package.loaded["sfx"]
        if SFX and SFX.hold then SFX.hold("loop_snow_roll", loudness(e, m, 4000.0)) end
        if a == "roll" then
            local wp = e.o.path and e.o.path[e.wp]
            if not wp then
                -- the end of its path: on to the head's spot (Mario 64's goes on as it was going, or at Mario if he came
                -- by the checkpoint and is ahead of it, and mostly rolled off the mountain: "the snowball needs to reach
                -- the snowman", 2026-10-18)
                e.action, e.at, a = "free", 0, "free"
            else
                -- (cur_obj_follow_path: a waypoint is reached once it is passed, the way from the last one to it
                -- and from the body to it no longer the same way)
                local dx, dz = wp[1] - e.x, wp[3] - e.z
                local pw = e.o.path[e.wp - 1] or { e.hx, e.hy, e.hz }
                if (wp[1] - pw[1]) * dx + (wp[3] - pw[3]) * dz <= 0.0 then e.wp = e.wp + 1 end
                e.want = s16(atan2s(dz, dx))
            end
        end
        if a == "free" then e.want = s16(atan2s(SNOW_SPOT[3] - e.z, SNOW_SPOT[1] - e.x)) end
        e.yaw = turn_toward(e.yaw, e.want or e.yaw, 0x400)
        e.fvel = math.min(70.0, e.fvel + 1.0)
        -- (on along the ground; a floor more than 100 up is a wall)
        local nx, nz = e.x + e.fvel * sins(e.yaw), e.z + e.fvel * coss(e.yaw)
        local fy = floor_y(nx, e.gy - 150.0, nz)            -- (floor_y looks from 250 above)
        if fy and fy > e.gy - 80.0 and (e.vy or 0.0) >= 0.0 then
            e.x, e.z, e.gy, e.vy = nx, nz, fy, 0.0
        else
            e.x, e.z = nx, nz
            e.vy = (e.vy or 0.0) - 10.0
            e.gy = e.gy + e.vy
            local f2 = floor_y(e.x, e.gy - e.vy - 150.0, e.z)
            if f2 and e.gy < f2 then e.gy, e.vy = f2, 0.0 end
            -- (slipped through the ground on its way down: back onto its path, where the ground is)
            local wp = a == "roll" and e.o.path and (e.o.path[e.wp] or e.o.path[#e.o.path])
            if wp and e.gy < wp[2] - 600.0 then
                e.x, e.z, e.vy = wp[1], wp[3], 0.0
                e.gy = floor_y(wp[1], wp[2] + 100.0, wp[3]) or wp[2]
            elseif not wp and e.gy < SNOW_SPOT[2] - 1500.0 then
                e.action = "missed"
                pcall(function() e.inst.actor:SetActorHiddenInGame(true) end)
                log("the snowman's body fell out of the level")
                return
            end
        end
        e.sk = math.min(1.0, e.sk + e.fvel * 0.0001)
        e.pitch = s16((e.pitch or 0) + floor(e.fvel * 100.0 / e.sk))
        snow_scale(e)
        -- run over: three wedges
        local dx, dz = m.x - e.x, m.z - e.z
        if pawn and dx * dx + dz * dz < (210.0 * e.sk + 40.0) ^ 2 and m.feet < e.gy + 350.0 * e.sk and m.y > e.gy - 50.0
           and (e.touch_cool or 0) <= 0 and not (a == "roll" and e.wp <= 1 and e.at < 60) then      -- (not as it sets off)
            e.touch_cool = 30
            hurt(e, m, pawn, 3, "the snowman's body", 1.3)
        end
        -- at the head's spot: it bounces up, and the head jumps onto it (snowmans_bottom_act_2)
        local sx, sy, sz = e.x - SNOW_SPOT[1], e.gy - SNOW_SPOT[2], e.z - SNOW_SPOT[3]
        if a == "free" and sx * sx + sy * sy + sz * sz < 300.0 * 300.0 then
            e.action, e.at, e.vy, e.fvel = "land", 0, 80.0, 15.0
            e.yaw = s16(atan2s(SNOW_SPOT[3] - e.z, SNOW_SPOT[1] - e.x))
            sound("snowman_bounce", 1.0)
            local h = snow_head()
            if h and h.action ~= "done" then h.action, h.vy = "jump", 100.0 end
            log("the snowman's body has reached its head")
        elseif a == "free" and e.at >= 200 then
            e.action = "missed"
            pcall(function() e.inst.actor:SetActorHiddenInGame(true) end)
            log("the snowman's body missed its head")
        end
    elseif a == "land" then
        e.x, e.z = e.x + e.fvel * sins(e.yaw), e.z + e.fvel * coss(e.yaw)
        e.vy = e.vy - 10.0
        e.gy = e.gy + e.vy
        local fy = floor_y(e.x, e.gy + 300.0, e.z)
        if fy and e.gy <= fy and e.vy < 0 then
            e.gy, e.x, e.z, e.fvel, e.action = fy, SNOW_SPOT[1], SNOW_SPOT[3], 0.0, "built"
        end
        snow_scale(e)
    end
end
local function step_snow_head(e, m, pawn, world)
    local a = e.action
    if a == "home" then e.action, a = "wait", "wait" end
    if a == "wait" and not e.said then
        -- (bhv_snowmans_head_loop: faced within 400, the head asks for his body, DIALOG_109)
        local look = s16(m.facing - (m.angle + 0x8000))
        if m.dist < 400.0 and abs(look) < 0x3000 then e.said = true; say(109, nil, e) end
    end
    if a == "jump" then
        e.y, e.vy = e.y + e.vy, e.vy - 5.0
        if e.vy <= 0 then e.action = "fall" end
    elseif a == "fall" then
        e.y, e.vy = e.y + e.vy, e.vy - 5.0
        if e.y < -994.0 then
            e.y, e.action = -994.0, "whole"
            e.x, e.z = SNOW_SPOT[1], SNOW_SPOT[3]
            sound("snowman_explode", 1.0)
            sound("puzzle_jingle", 1.0)
        end
    elseif a == "whole" then
        -- he faces it, close by: the star (DIALOG_111, spawn_default_star)
        local look = s16(m.facing - (m.angle + 0x8000))
        if m.dist < 700.0 and abs(look) < 0x3000 then
            e.action = "done"
            log("the snowman has its head back")
            talk_cam(e)
            say(111, function()
                local G = package.loaded["game"]
                if G and G.add_star then
                    local sx, sy, sz = to_scene(-4700.0, -1024.0, 1890.0)
                    local fx, fy, fz = to_scene(e.x, e.y + 200.0, e.z)
                    pcall(G.add_star, world, { kind = "star", pos = { sx, sy, sz }, id = star_index(e.o.bp), from = { fx, fy, fz } })
                end
            end)
        end
    end
    if a == "done" or a == "whole" then snow_push(e, m, 180.0, e.y + 150.0) end
    -- (on its body it is drawn 110 up, Mario 64's oGraphYOffset for the head: without it the head sank half into the
    -- body - "snowman not sitting correctly", 2026-10-18. Waiting on its own it sits as it was.)
    local up = (e.action == "jump" or e.action == "fall" or e.action == "whole" or e.action == "done") and 110.0 or 0.0
    e.gfx_y = up
end
local function step_snow_whole(e, m) snow_push(e, m, 210.0, e.hy + 550.0) end

-- DDD's rings (water_ring.inc.c): the manta's, and the jet stream's
local MANTA_PATH = { { -4500, -1380, -40 }, { -4120, -2240, 740 }, { -3280, -3080, 1040 }, { -2240, -3320, 720 },
                     { -1840, -3140, -280 }, { -2320, -2480, -1100 }, { -3220, -1600, -1360 }, { -4180, -1020, -1040 } }
local function ring_spawn(world, sp, x, y, z, yaw, pitch, normal)
    local data = H.actor_data and H.actor_data("geo_water_ring_geo")
    local inst = data and instance(world, data, x, y, z, yaw, 0.1)
    if not inst then return end
    sp.next_index = (sp.next_index or 0) + 1
    local r = { t = T.WaterRing, type = "WaterRing", o = { bp = 0 }, inst = inst, x = x, y = y, z = z, hx = x, hy = y, hz = z,
                yaw = yaw, pitch = pitch, timer = 0, f = 0, action = "home", hp = 1, scale = 1.0, sk = 1.0, from = sp,
                index = sp.next_index, normal = normal, at = 0, avg = 0.1,
                ph = { math.random(0x1000, 0x2000), math.random(0x1000, 0x2000), math.random(0x1000, 0x2000) } }
    r.prev = { x, y, z }
    M.list[#M.list + 1] = r
end
local function ring_front(r, m)
    local n = r.normal
    return (r.x - m.x) * n[1] + (r.y - (m.y - 40.0)) * n[2] + (r.z - m.z) * n[3]
end
local function step_ring(r, m, pawn, world)
    r.at = r.at + 1
    r.f = r.f + 1.0
    local sp = r.from
    if r.action == "home" then r.action, r.front = "out", ring_front(r, m) end
    if r.action == "out" then
        local life
        if sp.jet then
            r.avg = r.at / 225.0 * 3.0 + 0.5
            r.y = r.y + 10.0
            r.yaw = s16(r.yaw + 0x100)
            life = 225 + 33
        else
            r.avg = math.min(1.3, r.at / 50.0 * 1.3 + 0.1)
            life = 150 + 74
        end
        -- through it: in front of it before, behind it now, close to its middle
        local fr = ring_front(r, m)
        local dx, dy, dz = r.x - m.x, r.y - (m.y - 40.0), r.z - m.z
        if dx * dx + dy * dy + dz * dz < ((r.avg + 0.2) * 120.0) ^ 2 and r.front * fr < 0.0 then
            if r.index == (sp.last or -1) + 1 or (sp.got or 0) == 0 then
                sp.got = (sp.got or 0) + 1
                if sp.got < 6 then sound("secret_" .. sp.got, 1.0) end
                -- (its count in orange, 40 under the ring's middle: spawn_orange_number)
                local EF = package.loaded["envfx"]
                if EF and EF.number then
                    local nx, ny, nz = to_scene(r.x, r.y - 40.0, r.z)
                    pcall(EF.number, sp.got, nx, ny, nz)
                end
                sp.last = r.index
                log("ring %d of 5", sp.got)
            else
                sp.got = 0
            end
            r.action, r.at = "got", 0
        end
        r.front = fr
        if r.at > life then r.dead = true end
    elseif r.action == "got" then
        r.avg = r.avg + 0.2
        if r.at > 20 then r.dead = true end
    end
    -- (it wobbles as it goes: water_ring_set_scale)
    local sx = sins(r.ph[1]) * 0.1 + r.avg
    local sy = sins(r.ph[2]) * 0.5 + r.avg
    local sz = sins(r.ph[3]) * 0.1 + r.avg
    r.ph[1], r.ph[2], r.ph[3] = r.ph[1] + 0x1700, r.ph[2] + 0x1700, r.ph[3] + 0x1700
    pcall(function() r.inst.actor:SetActorScale3D({ X = sz, Y = sx, Z = sy }) end)
end
-- five in a row: the star
local function rings_star(sp, world, x, y, z)
    if (sp.got or 0) >= 5 and not sp.done then
        sp.done = true
        local G = package.loaded["game"]
        if G and G.add_star then
            local sx, sy, sz = to_scene(x, y, z)
            pcall(G.add_star, world, { kind = "star", pos = { sx, sy, sz }, id = star_index(sp.o.bp), from = { sx, sy, sz } })
        end
        log("five rings: the star")
    end
end
local function step_ring_spawner(e, m, pawn, world)
    e.jet = true
    e.at = (e.at or -1) + 1
    if e.at == 300 then e.at = 0 end
    if not e.done and m.dist < 6000.0 and (e.at == 0 or e.at == 50 or e.at == 150 or e.at == 200 or e.at == 250) then
        ring_spawn(world, e, e.x, e.y, e.z, 0, 0x8000, { 0.0, 1.0, 0.0 })
    end
    rings_star(e, world, 3400.0, -3200.0, -500.0)
end
local function step_manta(e, m, pawn, world)
    e.f = e.f + 1.0
    e.wp = e.wp or 1
    e.mp = e.mp or 0
    local wp = MANTA_PATH[e.wp]
    local pw = MANTA_PATH[e.wp - 1] or MANTA_PATH[#MANTA_PATH]
    local dx, dy, dz = wp[1] - e.x, wp[2] - e.y, wp[3] - e.z
    if (wp[1] - pw[1]) * dx + (wp[2] - pw[2]) * dy + (wp[3] - pw[3]) * dz <= 0.0 then
        e.wp = e.wp % #MANTA_PATH + 1
    end
    local ty = s16(atan2s(dz, dx))
    local tp = s16(atan2s(sqrt(dx * dx + dz * dz), dy))
    e.yaw = turn_toward(e.yaw, ty, 0x80)
    e.mp = turn_toward(e.mp, tp, 0x80)
    -- (it tilts as it turns)
    if e.yaw ~= ty then e.roll = math.max(-0x4000 / 3, (e.roll or 0) - 91) else e.roll = math.min(0x4000 / 3, (e.roll or 0) + 91) end
    e.pitch = -e.mp
    local cp = coss(e.mp)
    e.x, e.y, e.z = e.x + 10.0 * cp * sins(e.yaw), e.y + 10.0 * sins(e.mp), e.z + 10.0 * cp * coss(e.yaw)
    -- its rings, behind it
    e.at = (e.at or -1) + 1
    if e.at == 300 then e.at = 0 end
    if not e.done and (e.at == 0 or e.at == 50 or e.at == 150 or e.at == 200 or e.at == 250) then
        local bx, by, bz = e.x + 200.0 * sins(e.yaw + 0x8000), e.y + 10.0 + 200.0 * sins(e.mp), e.z + 200.0 * coss(e.yaw + 0x8000)
        ring_spawn(world, e, bx, by, bz, e.yaw, s16(e.pitch + 0x4000), { cp * sins(e.yaw), sins(e.mp), cp * coss(e.yaw) })
    end
    rings_star(e, world, -3180.0, -3600.0, 120.0)
end

-- DDD's sushi sharks (sushi.inc.c bhv_sushi_shark_loop): round and round their place, 1700 out and 0x80 a frame,
-- facing the way they swim, bobbing 200 about their depth under the water there (their place's height is that depth:
-- -270 the near one, -4270 the deep one); a splash of water every 16 frames. (They stood still before - the near one
-- right where DDD puts him down, biting him as he came in.)
local function step_sushi(e, m, pawn, world)
    e.f = e.f + 1.0
    local a = e.swim_a or 0
    local G = package.loaded["game"]
    local wl = G and G.water_at and (G.water_at(to_scene(e.x, 0, e.z)) or G.water_at(to_scene(e.hx, 0, e.hz)))
    local w = wl and wl / S or 0.0
    e.x = e.hx + sins(a) * 1700.0
    e.z = e.hz + coss(a) * 1700.0
    e.y = w + e.o.sm64[2] + sins(a) * 200.0
    e.yaw = s16(a + 0x4000)
    e.swim_a = (a + 0x80) % 65536
    e.sound_t = ((e.sound_t or 0) + 1) % 16
    if e.sound_t == 0 then
        local v = loudness(e, m, 3000.0)
        if v > 0.02 then sound("sushi_water", v) end
    end
end

-- THI's Bubba (bubba.inc.c), the great fish: it wanders the sea round its place at 5 (a new heading every 3-7 s,
-- turned 45 degrees; back toward its place when 2000 from it), and once he is within 2000 (and it has wandered a
-- second) it hunts him at 20, heading and pitching for a point 120 over his feet - swinging wide round him while he
-- faces away from it. Within 500 and facing him it stops and turns on him; 10 frames on it lunges at 40, pitched up,
-- and its mouth is open for the last 15 frames: if he is then right before it (within 250, in line with its mouth)
-- it swallows him (ACT_EATEN_BY_BUBBA: a life gone); then the chomp. Its body bumped otherwise is a wedge and a push
-- (INTERACT_CLAM_OR_BUBBA); nothing he does hurts it. Out of the water it falls (gravity 4); it keeps 150 over the
-- sea floor.
local function smooth_turn(vel, ang, target, minv, maxv)
    -- (obj_smooth_turn: the turn speed eases toward 5% of what is left, 10 a frame; at least 50, at most 2000)
    vel = approach(vel, s16(target - ang) * 0.05, 10.0)
    local sp = math.max(minv, math.min(maxv, abs(vel)))
    return vel, turn_toward(ang, target, sp)
end
M.BUBBA_WALL = 200.0          -- its wall hitbox, Mario 64 units round its middle
-- Its open mouth as drawn (bubba_open at its size, 0.5: 4.5 m long, the mouth the lower front of it, 145-293 ahead of
-- its middle and 30-250 under it, 250 across), Mario 64 units at that size: a ball `r` round, `ahead` of its middle and
-- `down` under it, turned and pitched with it (nose down as its pitch grows - e.vy is speed x -sin(pitch)).
M.BUBBA_MOUTH = { ahead = 220.0, down = 140.0, r = 150.0 }
function M.bubba_in_mouth(e, m)
    local Mo = M.BUBBA_MOUTH
    local k = (e.scale or 0.5) / 0.5
    local cy, sy, cp, sp = coss(e.yaw), sins(e.yaw), coss(e.pitch or 0), sins(e.pitch or 0)
    local fx, fy, fz = sy * cp, -sp, cy * cp            -- its heading
    local ux, uy, uz = sy * sp, cp, cy * sp             -- its up
    local mx = e.x + (fx * Mo.ahead - ux * Mo.down) * k
    local my = e.y + (fy * Mo.ahead - uy * Mo.down) * k
    local mz = e.z + (fz * Mo.ahead - uz * Mo.down) * k
    -- (his body: the core of his capsule, feet to head less its 47 round, and that 47 round it)
    local feet = m.feet or (m.y - 120.0)
    local py = math.max(feet + 47.0, math.min(m.y + 73.0, my))
    local dx, dy, dz = m.x - mx, py - my, m.z - mz
    return dx * dx + dy * dy + dz * dz < (Mo.r * k + 47.0) ^ 2
end
local function step_bubba(e, m, pawn, world)
    local B = e.bb
    B.t = B.t + 1
    e.f = e.f + 1.0
    local G = package.loaded["game"]
    local wl = G and G.water_at and G.water_at(to_scene(e.x, 0, e.z))
    local water = wl and wl / S or nil
    local feet = m.y - 120.0
    local dx, dz = m.x - e.x, m.z - e.z
    local horiz = sqrt(dx * dx + dz * dz)
    local dist = sqrt(dx * dx + dz * dz + (feet - e.y) ^ 2)
    -- (Mario is small: for the bite, the nearer of the athlete's feet and middle)
    local bite = math.min(dist, sqrt(dx * dx + dz * dz + (m.y - e.y) ^ 2))
    local ang = s16(atan2s(dz, dx))
    -- (obj_turn_pitch_toward_mario(120): as if from 120 under itself)
    local p104 = s16(atan2s(horiz, (e.y - 120.0) - feet))
    -- (in line with him, mouth open, close: swallowed)
    -- (or his body in its open mouth as it is drawn, M.bubba_in_mouth: Mario 64's test is made for Mario, small and
    -- measured at his feet, and the athlete swam into the open mouth and out again unharmed - "sometimes when bubba
    -- attacks and the player goes inside his mouth the player wont die", 2026-10-29)
    local in_line = abs(s16(ang - e.yaw)) < 0x1000 and abs(s16(p104 + 0x800 - e.pitch)) < 0x2000 and bite < 250.0
    if B.mouth ~= 0 and (in_line or M.bubba_in_mouth(e, m)) then
        local HP = _G.HEALTH
        -- (interact_clam_or_bubba swallows him before any check of his invincibility: blinking is no help - only the
        -- long untouchable spells, test and story, are)
        -- (not again while the last swallow is still ending - him out of sight, G.hide_athlete: its death clears HP.dead_t a
        -- moment before its warp, and a Bubba there with its mouth open swallowed him a second time, his power refilled
        -- for the castle taken again - he drowned the moment he next swam, a second life, 2026-10-29)
        if HP and not HP.dead_t and (HP.grace or 0) < 60.0 and not (G and (G.dying or G.cutscene or G.athlete_hidden or G.down_for_good))
           and not B.ate then
            B.ate = true
            sound("bubba_chomp", 1.0)
            log("Bubba: swallowed the athlete")
            HP.kill("eaten by Bubba")
            -- (and he is gone from sight, inside it, till the death warp: act_eaten_by_bubba - game.lua G.hide_athlete)
            if G and G.hide_athlete then pcall(G.hide_athlete, true, "swallowed by Bubba") end
        end
    end
    -- (treat_far_home_as_mario: strayed too far, home is what it goes for; he far from its home, it pays him no mind)
    local function far(thr)
        local hx, hy, hz = e.hx - e.x, e.hy - e.y, e.hz - e.z
        if sqrt(hx * hx + hy * hy + hz * hz) > thr then
            ang, dist = s16(atan2s(hz, hx)), 25000.0
        else
            local mx, my, mz = e.hx - m.x, e.hy - feet, e.hz - m.z
            if sqrt(mx * mx + my * my + mz * mz) > thr then dist = 20000.0 end
        end
    end
    if B.act == 0 then
        far(2000.0)
        B.mouth = 0
        local lx, lz = e.hx - e.x, e.hz - e.z
        B.tpitch = s16(atan2s(sqrt(lx * lx + lz * lz), e.y - e.hy))
        B.spd = approach(B.spd, 5.0, 0.5)
        -- (into a wall: turned off it - its heading mirrored in the wall, cur_obj_reflect_move_angle_off_wall - and nothing
        -- else till it has come round to within 800 of that (bubba_act_0's oBubbaUnkFC). Without it, it wandered on into
        -- the island's rock and pressed along it: "bubbas pathing is off he's always swimming into a wall", 2026-10-29)
        if B.turning then
            if abs(s16(e.yaw - B.tyaw)) < 800 then B.turning = false end
        else
            if dist >= 25000.0 then B.tyaw, B.wt = ang, math.random(20, 50) end
            if B.hit_wall then
                B.turning, B.tyaw = true, M.skeeter_reflect(e.yaw, B.wall_yaw)
            elseif B.t > 30 and dist < 2000.0 then
                B.act, B.t = 1, 0
            elseif B.wt > 0 then
                B.wt = B.wt - 1
            else
                B.tyaw, B.wt = s16(e.yaw + (math.random(0, 1) == 0 and -0x2000 or 0x2000)), math.random(100, 200)
            end
        end
    else
        far(2500.0)
        if dist > 2500.0 then
            B.act, B.t = 0, 0
        elseif B.chomp ~= 0 then
            B.chomp = B.chomp - 1
            if B.chomp == 0 then
                sound("bubba_chomp", loudness(e, m))
                B.act, B.t, B.ate = 0, 0, nil
            elseif B.chomp < 15 then
                B.mouth = 1
            elseif B.chomp == 20 then
                -- (the lunge: pitched up the more the deeper it is)
                local depth = (water or e.y) - e.y
                B.tpitch = s16(B.tpitch - s16(10000 - floor(20.0 * depth)))
                e.pitch, B.spd, B.mouth = B.tpitch, 40.0, 0
                e.fvel, e.vy = B.spd * coss(e.pitch), B.spd * -sins(e.pitch)
            else
                B.tyaw, B.tpitch = ang, p104
                e.yaw = turn_toward(e.yaw, B.tyaw, 400)
                e.pitch = turn_toward(e.pitch, B.tpitch, 400)
            end
        else
            if abs(s16(m.facing - ang)) < 0x3000 then
                local off = s16(0x4000 - atan2s(800.0, dist - 800.0))
                if s16(e.yaw - ang) < 0 then off = -off end
                B.tyaw = s16(ang + off)
            else
                B.tyaw = ang
            end
            B.tpitch = p104
            if dist < 500.0 and abs(s16(e.yaw - ang)) < 3000 and abs(s16(B.tpitch - e.pitch)) < 3000 then
                B.chomp, B.spd, B.mouth = 30, 0.0, 1
            else
                B.spd = approach(B.spd, 20.0, 0.5)
            end
        end
    end
    -- moving (cur_obj_move_standard): in the water by its heading and pitch, out of it by its own speed; drag on the
    -- way across (v x v x 0.001 a frame) and gravity 4 down always (it has no buoyancy). In the water it rises no
    -- higher than the surface, and leaves it only coming up through it faster than 5 - the lunge near the top throws
    -- it out; then it falls back in with a splash.
    if not B.air then
        B.pv, e.pitch = smooth_turn(B.pv, e.pitch, B.tpitch, 50, 2000)
        B.yv, e.yaw = smooth_turn(B.yv, e.yaw, B.tyaw, 50, 2000)
        e.fvel, e.vy = B.spd * coss(e.pitch), B.spd * -sins(e.pitch)
    else
        B.spd = sqrt(e.fvel * e.fvel + e.vy * e.vy)
        e.pitch = turn_toward(e.pitch, s16(-atan2s(e.fvel, e.vy)), 400)
        B.pv = 0
    end
    local fv = abs(e.fvel)
    fv = math.max(0.0, fv - fv * fv * 0.001)
    e.fvel = e.fvel < 0.0 and -fv or fv
    e.vy = math.max(-78.0, e.vy - 4.0)
    e.x, e.y, e.z = e.x + e.fvel * sins(e.yaw), e.y + e.vy, e.z + e.fvel * coss(e.yaw)
    -- (the level's walls push it out to M.BUBBA_WALL from them, and it slides along them, as cur_obj_move_standard's
    -- wall check does - walls spanning its middle. It had none and swam through the island's rock: "the fish guys going
    -- through walls", 2026-10-29)
    if H.wall_near then
        local sx, sy, sz = to_scene(e.x, e.y + 10.0, e.z)
        local hit, px, py = H.wall_near(sx, sy, sz, M.BUBBA_WALL * S, 5.0 * S)
        B.hit_wall = hit and (px ~= 0.0 or py ~= 0.0)
        if B.hit_wall then
            local mx, mz = py / S, -px / S                  -- (the push, Mario 64's x and z: out along the wall's face)
            e.x, e.z = e.x + mx, e.z + mz
            B.wall_yaw = s16(atan2s(mz, mx))                -- (oWallAngle, for the turn off it next frame)
        end
    end
    -- (its sway as it swims, quicker the faster it goes: the render's)
    B.ph = (B.ph or 0.0) + 0.12 + abs(B.spd or 0.0) * 0.012
    if not B.air then
        if water and e.y >= water then
            if B.surface and e.vy > 5.0 then
                B.air, B.surface = true, false
            else
                e.y, e.vy, B.surface = water, 0.0, true
            end
        else
            B.surface = false
        end
    elseif water and e.y < water then
        B.air = false
        local EF = package.loaded["envfx"]
        if EF and EF.splash then pcall(EF.splash, to_scene(e.x, water, e.z)) end
        sound("water_plunge", loudness(e, m))
    end
    -- (it keeps 150 over the floor: oFloorHeight + 150. Thrown up onto land it lies there, sliding to a stop; and then,
    -- unlike Mario 64's - which never steers out of the water, and stays beached - it flops back toward its place)
    local fy = floor_y(e.x, e.y + 300.0, e.z)
    if fy and e.y < fy + 150.0 then
        e.y = fy + 150.0
        if e.vy < 0.0 then e.vy = 0.0 end
        if B.air then
            e.fvel = approach(e.fvel, 0.0, 2.0)
            B.beached = (B.beached or 0) + 1
            if B.beached > 45 then
                e.yaw = turn_toward(e.yaw, s16(atan2s(e.hz - e.z, e.hx - e.x)), 0x400)
                e.fvel, e.vy = 15.0, (B.beached % 15 == 0) and 25.0 or e.vy
            end
        end
    else
        B.beached = 0
    end
end

-- TTM's Monty Moles (monty_mole.inc.c). Mario 64 puts them nowhere (0,0,0): they live in the level's nine holes
-- (bhvMontyMoleHole, drawn as the scene's static decals). A mole picks a free hole between its least distance and
-- 1500 from him (the rock thrower 200 out; the other 100, or 500 while he runs) and comes up there facing him: rising
-- slowly to 50 over it, or (close by, half the time) jumping out and landing on it. Up, the thrower takes out a rock
-- and lobs it at him if he is before it (40 on, up by his distance); then it waits (up to 80 frames, less once he is
-- near and before it), jumps up and dives back into the hole, and the hole rests a second. Hit or stomped it vanishes
-- in a puff and is soon out of another hole; eight in a row (each within 1500 of the last) give a 1-up. Its side
-- touched: 2 wedges.
local MOLE_ANIM = { [0] = 12, [1] = 12, [2] = 10, [3] = 80, [4] = 14, [8] = 20, [9] = 1 }
local function mole_holes()
    if M.mole_holes then return M.mole_holes end
    local G = package.loaded["game"]
    local holes = {}
    for _, o in ipairs((G and G.data and G.data.objects) or {}) do
        if o.tpl and o.tpl:find("monty_mole_hole", 1, true) and o.pos then
            holes[#holes + 1] = { x = o.pos[1], y = o.pos[2], z = o.pos[3], free_t = 0.0 }
        end
    end
    M.mole_holes = holes
    log("Monty Moles: %d holes", #holes)
    return holes
end
local function mole_show(e, on)
    if e.ml_hidden == (not on) then return end
    e.ml_hidden = not on
    pcall(function() e.inst.actor:SetActorHiddenInGame(not on) end)
end
local function mole_dirt(e)
    local EF = package.loaded["envfx"]
    if EF and EF.poof then
        local sx, sy, sz = to_scene(e.x, e.y + 20.0, e.z)
        pcall(EF.poof, sx, sy, sz, 0.5)
    end
end
local function mole_hide(e)
    -- (monty_mole_hide_in_hole: the hole rests 30 frames; the mole looks for another)
    local L = e.ml
    if L.hole then L.hole.taken, L.hole.free_t = nil, os.clock() + 1.0 end
    L.hole, L.act, L.t, L.grav, e.vy, e.pitch = nil, "select", 0, 0.0, 0.0, 0
    mole_show(e, false)
end
local function mole_rock(world, e, m)
    -- (monty_mole_rock_act_held: thrown 40 on, up by his distance - at most 600 - and aimed a little to its left)
    local d = math.min(600.0, m.dist)
    local yaw = s16(e.yaw + 500 - d * 0.1)
    local s = { kind = "rock", x = e.x, y = e.y + 40.0, z = e.z, vx = 40.0 * sins(yaw), vy = d * 0.08 + 8.0, vz = 40.0 * coss(yaw),
                life = 150, dmg = 1 }
    local data = H.actor_data and H.actor_data("geo_bowling_ball_geo")
    if data then s.inst = instance(world, data, s.x, s.y, s.z, 0, 0.12) end
    M.shots[#M.shots + 1] = s
end
local function step_mole(e, m, pawn, world)
    local L = e.ml
    L.t = L.t + 1
    e.f = e.f + 1.0
    local function go(act) L.act, L.t, e.f = act, 0, 0.0 end
    local fy = L.hole and L.hole.y or e.y
    local ang = s16(atan2s(m.z - e.z, m.x - e.x))
    if L.act == "select" then
        local mind = 200.0
        if not L.rock then
            local run = 0.0
            pcall(function() local v = pawn:GetVelocity(); run = sqrt(v.X * v.X + v.Y * v.Y) / S / 30.0 end)
            mind = (run < 8.0) and 100.0 or 500.0
        end
        local feet = m.y - 120.0
        local now, free = os.clock(), {}
        for _, h in ipairs(mole_holes()) do
            if not h.taken and now >= h.free_t then
                local d = sqrt((h.x - m.x) ^ 2 + (h.y - feet) ^ 2 + (h.z - m.z) ^ 2)
                if d < 1500.0 and d > mind then free[#free + 1] = { h, d } end
            end
        end
        if #free > 0 then
            local pick = free[math.random(1, #free)]
            local h = pick[1]
            h.taken, L.hole = true, h
            sound("en_mole_appear", loudness(e, m))
            e.x, e.y, e.z, e.pitch = h.x, h.y, h.z, 0
            e.yaw = s16(atan2s(m.z - h.z, m.x - h.x))
            e.prev = { e.x, e.y, e.z }
            if pick[2] > 500.0 or mind > 100.0 or math.random(0, 1) == 0 then
                go("rise"); e.vy, L.grav = 3.0, 0.0
            else
                go("jump_out"); e.vy, L.grav = 50.0, -4.0
            end
            mole_dirt(e)
            mole_show(e, true)
        end
        return
    elseif L.act == "rise" then
        e.anim_i = 1
        if e.y - fy >= 49.0 then
            e.y, e.vy = fy + 50.0, 0.0
            if (L.t % 12) >= 11 then go("spawn_rock") end
        end
    elseif L.act == "spawn_rock" then
        e.anim_i = 2
        if L.t >= MOLE_ANIM[2] then
            if L.rock and abs(s16(ang - e.yaw)) < 0x4000 then go("throw") else go("begin_jump") end
        end
    elseif L.act == "throw" then
        e.anim_i = 8
        if L.t == 10 then
            sound("en_mole_attack", loudness(e, m))
            mole_rock(world, e, m)
        end
        if L.t >= MOLE_ANIM[8] - 1 then go("begin_jump") end
    elseif L.act == "begin_jump" then
        e.anim_i = 3
        if L.t >= MOLE_ANIM[3] or (m.dist < 1000.0 and abs(s16(e.yaw - ang)) < 0x4000) then
            go("jump_into"); e.vy, L.grav = 40.0, -6.0
        end
    elseif L.act == "jump_into" then
        e.anim_i = 0
        e.f = math.min(e.f, MOLE_ANIM[0] - 1)
        e.pitch = s16(-atan2s(e.vy, -4.0))
        if e.vy < 0.0 and e.y - fy < 120.0 then
            go("hide"); L.grav = 0.0
            mole_dirt(e)
        end
    elseif L.act == "hide" then
        e.anim_i = 1
        e.vy = approach(e.vy, -4.0, 0.5)
    elseif L.act == "jump_out" then
        if e.vy > 0.0 then
            e.anim_i = 9
        else
            e.anim_i = 4
            e.f = math.min(e.f, MOLE_ANIM[4] - 1)
            if e.y - fy < 50.0 then
                e.y = fy + 50.0
                go("begin_jump"); e.vy, L.grav = 0.0, 0.0
            end
        end
    end
    e.vy = e.vy + L.grav
    e.y = e.y + e.vy
    if e.y <= fy then
        e.y = fy
        if L.act == "hide" then mole_hide(e) end
    end
end

-- Snufits (snufit.inc.c): they hang in the air where they are, drifting round a 100 circle; within 800 of him they
-- turn to face him (pitching up to 45 degrees), and after a moment (his distance / 10 frames) draw in a breath and fire
-- three pellets three frames apart, straight along their aim at 40, puffing out as they go (1 wedge each; gone on a
-- floor or 1500 from him). Hit or stomped (INTERACT_HIT_FROM_BELOW): two coins. Touched: 2 wedges.
local function step_snufit(e, m, pawn, world)
    local S2 = e.sn
    if not S2 then
        S2 = { act = "idle", t = 0, circ = 0, per = 0, base = 0, bullets = 0, recoil = 0, clock = math.random(0, 1000) }
        e.sn = S2
    end
    S2.t = S2.t + 1
    S2.clock = S2.clock + 1
    e.f = e.f + 1.0
    local feet = m.y - 120.0
    local dx, dz = m.x - e.x, m.z - e.z
    local dist = sqrt(dx * dx + dz * dz + (feet - e.y) ^ 2)
    local ang = s16(atan2s(dz, dx))
    if dist < 800.0 then
        local p = s16(atan2s(sqrt(dx * dx + dz * dz), (e.y - 120.0) - feet))
        e.pitch = turn_toward(e.pitch or 0, p, 2000)
        e.pitch = math.max(-0x2000, math.min(0x2000, e.pitch))
        e.yaw = turn_toward(e.yaw, ang, 2000)
    else
        e.pitch = turn_toward(e.pitch or 0, 0, 0x200)
        e.yaw = s16(e.yaw + 200)
    end
    if S2.act == "idle" then
        if S2.t > floor(dist / 10.0) and dist < 800.0 then
            S2.per = turn_toward(S2.per, 0, 1500)
            S2.base = S2.base + math.max(-15, math.min(15, 600 - S2.base))
            if S2.per == 0 and S2.base == 600 then S2.act, S2.t, S2.bullets = "shoot", 0, 0 end
        else
            S2.circ = (S2.circ + 400) % 65536
        end
    else
        S2.per = turn_toward(S2.per, -0x8000, 3000)
        S2.base = S2.base + math.max(-20, math.min(20, 167 - S2.base))
        if (S2.per % 65536) == 0x8000 and S2.base == 167 then
            S2.act, S2.t = "idle", 0
        elseif S2.bullets < 3 and S2.t >= 3 then
            S2.bullets, S2.t, S2.recoil = S2.bullets + 1, 0, -30
            sound("en_snufit_shoot", loudness(e, m))
            -- (bhvSnufitBalls: from 40 before it and 20 down, straight on at 40 along its aim)
            local cp = coss(e.pitch)
            local s = { kind = "pellet", x = e.x + 40.0 * sins(e.yaw) * cp, y = e.y - 20.0, z = e.z + 40.0 * coss(e.yaw) * cp,
                        vx = 40.0 * cp * sins(e.yaw), vy = -40.0 * sins(e.pitch), vz = 40.0 * cp * coss(e.yaw), life = 60, dmg = 1 }
            local data = H.actor_data and H.actor_data("geo_bowling_ball_geo")
            if data then s.inst = instance(world, data, s.x, s.y, s.z, 0, 0.1) end
            M.shots[#M.shots + 1] = s
        end
    end
    S2.recoil = approach(S2.recoil, 0.0, 3.0)
    e.x = e.hx + 100.0 * coss(S2.circ)
    e.y = e.hy + 8.0 * coss(4000 * S2.clock)
    e.z = e.hz + 100.0 * sins(S2.circ)
    -- (its body swells as it breathes in - geo_snufit_scale_body, the round body alone up to full size; past it the whole
    -- of it grows, cur_obj_scale)
    local body = S2.base + 666 + S2.base * coss(S2.per)
    local k = (body > 1000) and ((body - 1000) / 1000.0 + 1.0) or 1.0
    if not S2.k or abs(k - S2.k) > 0.02 then
        S2.k = k
        local sk = (e.sk or 1.0) * k
        pcall(function() e.inst.actor:SetActorScale3D({ X = sk, Y = sk, Z = sk }) end)
    end
    -- (and its mouth out in front of its mask - geo_snufit_move_mask: 180 ahead and 32 down in the model's quarter scale,
    -- back 30 at each shot. Drawn inside its head, with its eyes' picture wrapped, it looked contorted: "fix the shyguys
    -- they are contorted", 2026-10-20)
    local inst = e.inst
    if inst then
        local bs = math.min(body, 1000) / 1000.0
        local mz = (180.0 + S2.recoil) * 0.25
        if S2.bs ~= bs or S2.mz ~= mz then
            S2.bs, S2.mz = bs, mz
            for i, p in ipairs(inst.data.parts) do
                local c = inst.comps[i]
                if c and p.billboard then
                    pcall(function() c:SetRelativeScale3D({ X = bs, Y = bs, Z = bs }) end)
                elseif c and i == 1 and #p.sections == 0 and p.parent < 0 then
                    pcall(function() c:K2_SetRelativeLocation({ X = -mz * S, Y = 0.0, Z = -32.0 * 0.25 * S }, false, {}, false) end)
                end
            end
        end
    end
end

-- HMC's Swoops (swoop.inc.c): one hangs upside down at its place under the ceiling, growing back to its size;
-- once he is within 1500 and it has turned to face him it lets go with a screech, rights itself, and flies at him at 10,
-- dropping 10 a frame till it is no more than 200 over him; there it levels out, doubles its speed, and goes on
-- straight (weaving a little) - turned back off walls - till he is 2000 from it and from its place: then it is back
-- under the ceiling. Hit from below, punched or stomped: a coin; touched: a wedge.
local function step_swoop(e, m, pawn, world)
    local W = e.sw
    if not W then
        W = { act = "idle", scale = 0.0, fvel = 0.0, vy = 0.0, bonk = 0, tyaw = e.yaw, clock = math.random(0, 1000) }
        e.sw, e.pitch, e.roll = W, 0, 0x8000
    end
    W.clock = W.clock + 1
    e.f = e.f + 1.0
    local feet = m.y - 120.0
    local ang = s16(atan2s(m.z - e.z, m.x - e.x))
    if W.act == "idle" then
        e.anim_i = 1
        e.roll = 0x8000
        W.scale = math.min(1.0, W.scale + 0.05)
        if W.scale >= 1.0 and m.dist < 1500.0 then
            e.yaw = turn_toward(e.yaw, ang, 800)
            if e.yaw == ang then
                sound("en_swoop", loudness(e, m))
                W.act, W.vy, W.level = "move", -12.0, nil
            end
        end
    else
        e.anim_i = 0
        if W.fvel == 0.0 then
            e.roll = turn_toward(e.roll, 0, 2500)
            if e.roll == 0 then W.fvel, W.vy = 10.0, -10.0 end
        else
            local hx, hy, hz = e.hx - m.x, e.hy - feet, e.hz - m.z
            if sqrt(hx * hx + hy * hy + hz * hz) > 2000.0 and m.dist > 2000.0 then
                -- (cur_obj_mario_far_away: back under the ceiling, to grow again)
                e.x, e.y, e.z = e.hx, e.hy, e.hz
                e.prev = { e.x, e.y, e.z }
                W.act, W.scale, W.fvel, W.vy, e.roll, e.pitch, W.level = "idle", 0.0, 0.0, 0.0, 0, 0, nil
            else
                if W.bonk > 0 then
                    W.bonk = W.bonk - 1
                elseif W.vy ~= 0.0 and not W.level then
                    W.tyaw = ang
                    if e.y < feet + 200.0 then
                        W.vy = approach(W.vy, 0.0, 0.5)
                        if W.vy == 0.0 then W.fvel, W.level = W.fvel * 2.0, true end
                    else
                        W.vy = approach(W.vy, -10.0, 0.5)
                    end
                elseif W.level then
                    -- (and from then on up or down after him, to his chest: Mario 64's dives once and flies on level -
                    -- "bats cant fly up or down", 2026-10-31)
                    local want = math.max(-8.0, math.min(8.0, (feet + 110.0 - e.y) * 0.06))
                    W.vy = approach(W.vy, want, 0.6)
                end
                local tp = s16(-atan2s(W.fvel, W.vy))
                if tp == 0 then tp = floor(W.fvel * 500) end
                e.pitch = turn_toward(e.pitch, tp, 140)
                e.yaw = turn_toward(e.yaw, s16(W.tyaw + floor(3000 * coss(4000 * W.clock))), 1200)
                local want = math.max(-0x3000, math.min(0x3000, s16(e.yaw - W.tyaw)))
                e.roll = s16(turn_toward(e.roll, want, 500) + floor(1000 * coss(20000 * W.clock)))
            end
        end
    end
    -- moving: straight along its heading; a wall ahead (the floor there over it) turns it back
    if W.act == "move" then
        local nx, nz = e.x + W.fvel * sins(e.yaw), e.z + W.fvel * coss(e.yaw)
        local ahead = floor_y(nx, e.y + 60.0, nz)
        if W.fvel > 0.0 and ahead and ahead > e.y - 20.0 then
            W.tyaw, W.bonk = s16(e.yaw + 0x8000), 30
        else
            e.x, e.z = nx, nz
        end
        e.y = e.y + W.vy
        -- (never above where it hangs, under the ceiling)
        if W.level and e.hy and e.y > e.hy then e.y = e.hy; W.vy = math.min(W.vy, 0.0) end
        -- (and the walls themselves: pushed back out of one and turned round - the floor-ahead test above missed walls
        -- with no floor over them, and it flew through the cave's: "bats go through walls", 2026-10-31)
        if H.wall_near then
            local sx, sy, sz = to_scene(e.x, e.y + 40.0, e.z)
            local hit, px, py = H.wall_near(sx, sy, sz, 70.0 * S, 5.0 * S)
            if hit and (px ~= 0.0 or py ~= 0.0) then
                e.x, e.z = e.x + py / S, e.z - px / S
                if W.bonk == 0 then W.tyaw, W.bonk = s16(e.yaw + 0x8000), 30 end
            end
        end
        local fy = floor_y(e.x, e.y + 60.0, e.z)
        if fy and e.y < fy + 20.0 then e.y = fy + 20.0 end
    end
    -- (its size: grown back from nothing under the ceiling)
    local k = (e.sk or 1.0) * math.max(0.01, W.scale)
    if not W.k or abs(k - W.k) > 0.01 then
        W.k = k
        pcall(function() e.inst.actor:SetActorScale3D({ X = k, Y = k, Z = k }) end)
    end
end

-- Fly Guys (fly_guy.inc.c): one bobs where it is till he is within 2000 (or it has strayed 2000 from its place: then
-- its place is what it goes for); it turns to him and comes on at 10, and once it faces him and is 400 over him or
-- 400 from him it dives at him at 25 - aimed a little under him - rights itself, banks, and climbs back to 200 over
-- him, to come again. A fire one (macro_fire_fly_guy) instead half the time stops, swells and spits a flame down at
-- him. He is beyond 2000: it slows and hovers. Stomped or hit: two coins; touched: 2 wedges.
local function step_flyguy(e, m, pawn, world)
    local F = e.fg
    if not F then
        F = { act = "idle", fvel = 0.0, vy = 0.0, osc = math.random(0, 64), roll_t = 0, t = 0, cool = 0,
              fire = (e.o and e.o.preset == "macro_fire_fly_guy") or ((((e.o and e.o.bp) or 0) >> 16) & 0xFF) ~= 0 }
        e.fg, e.pitch, e.roll = F, 0, 0
    end
    F.t = F.t + 1
    if F.cool > 0 then F.cool = F.cool - 1 end
    e.f = e.f + 1.0
    local feet = m.y - 120.0
    local ang = s16(atan2s(m.z - e.z, m.x - e.x))
    local dist = m.dist
    -- (treat_far_home_as_mario(2000))
    local hx, hy, hz = e.hx - e.x, e.hy - e.y, e.hz - e.z
    if sqrt(hx * hx + hy * hy + hz * hz) > 2000.0 then ang, dist = s16(atan2s(hz, hx)), 25000.0 end
    local near = dist >= 25000.0 or dist < 2000.0
    if F.act == "idle" then
        F.fvel = 0.0
        F.vy = approach(F.vy, 0.0, 0.5)
        if near then
            e.yaw = turn_toward(e.yaw, ang, 0x300)
            if e.yaw == ang then F.act, F.t = "approach", 0 end
        elseif F.t > 60 then
            F.act, F.t = "approach", 0
        end
    elseif F.act == "approach" then
        if near then
            F.fvel = approach(F.fvel, 10.0, 0.5)
            e.yaw = turn_toward(e.yaw, ang, 0x200)
            -- (and up or down as it comes, to 250 over him - home's height when it has strayed: Mario 64's only climbs
            -- after a dive, and with him up on something, more than 400 off, it hung below him for good - "shy guys
            -- cant fly up or down", 2026-10-31)
            local want = (dist < 25000.0) and (feet + 250.0) or e.hy
            F.vy = approach(F.vy, math.max(-8.0, math.min(8.0, (want - e.y) * 0.05)), 0.5)
            -- (and not again for a while after a flame - F.cool: straight back at him it spat one every 0.8 s, where
            -- Mario 64's first grows back to its size, fly_guy_act_idle - "fire shyguy spamming fire", 2026-10-27)
            if abs(s16(ang - e.yaw)) < 0x2000 and (e.y - feet > 400.0 or dist < 400.0) and dist < 25000.0 and F.cool <= 0 then
                if F.fire and math.random(0, 1) == 1 then
                    F.act, F.t = "fire", 0
                else
                    -- (aimed as if from 200 over itself: a little under him)
                    local dx, dz = m.x - e.x, m.z - e.z
                    local p = s16(atan2s(sqrt(dx * dx + dz * dz), (e.y + 200.0) - feet))
                    F.act, F.t, F.lp = "lunge", 0, p
                    F.fvel, F.vy = 25.0 * coss(p), 25.0 * -sins(p)
                    F.decel = -F.vy / 30.0
                end
            end
        else
            F.fvel = approach(F.fvel, 0.0, 0.2)
            F.vy = approach(F.vy, 0.0, 0.5)
            if F.fvel == 0.0 then F.act, F.t = "idle", 0 end
        end
    elseif F.act == "lunge" then
        if F.vy < 0.0 then
            F.vy = F.vy + F.decel
            e.pitch = turn_toward(e.pitch, F.lp, 0x400)
            F.troll = 0x1000 * math.random(0, 2) - 0x1000
        else
            e.pitch = turn_toward(e.pitch, 0, 0x100)
            e.roll = turn_toward(e.roll, F.troll or 0, 300)
            e.yaw = s16(e.yaw - floor(e.roll / 4))
            if e.y < feet + 200.0 then
                F.vy = approach(F.vy, 20.0, 0.5)
            else
                F.vy = approach(F.vy, 0.0, 0.5)
                if F.vy == 0.0 then
                    if e.roll == 0 then F.act, F.t = "approach", 0 end
                    F.troll = 0
                end
            end
        end
    elseif F.act == "fire" then
        F.fvel = 0.0
        e.yaw = turn_toward(e.yaw, ang, 0x800)
        if e.yaw ~= ang then
            F.t = 0
        else
            -- (obj_grow_then_shrink: it swells, spits at the top of it, and shrinks back)
            local k = (F.t < 12) and (1.0 + 0.2 * F.t / 12.0) or math.max(1.0, 1.2 - 0.2 * (F.t - 12) / 12.0)
            if not F.k or abs(F.k - k) > 0.02 then
                F.k = k
                local sk = (e.sk or 1.5) * k
                pcall(function() e.inst.actor:SetActorScale3D({ X = sk, Y = sk, Z = sk }) end)
            end
            if F.t == 12 then
                F.cool = 90                                     -- (3 s before it comes at him again)
                shoot(world, e, m, "fire")
                local sh = M.shots[#M.shots]
                if sh and sh.kind == "fire" then sh.dmg = 1 end      -- (its flame: a wedge)
            end
            if F.t >= 24 then F.act, F.t = "idle", 0 end
        end
    end
    -- moving: along its heading; a wall ahead turns it back
    F.osc = F.osc + 1
    local nx, nz = e.x + F.fvel * sins(e.yaw), e.z + F.fvel * coss(e.yaw)
    local ahead = floor_y(nx, e.y + 60.0, nz)
    if F.fvel > 0.0 and ahead and ahead > e.y - 10.0 then
        e.yaw = s16(e.yaw + 0x8000)
    else
        e.x, e.z = nx, nz
    end
    -- (not up through a ceiling: a surface over it within reach of the climb)
    if F.vy > 0.0 then
        local over = floor_y(e.x, e.y + F.vy + 120.0, e.z)
        if over and over > e.y + 40.0 then F.vy = 0.0 end
    end
    e.y = e.y + F.vy + coss(0x400 * F.osc) * 1.5
    local fy = floor_y(e.x, e.y + 60.0, e.z)
    if fy and e.y < fy + 30.0 then e.y = fy + 30.0; if F.vy < 0.0 then F.vy = 0.0 end end
end

-- Mr. Blizzard (mr_blizzard.inc.c), CCM and SL. Buried under the snow, he makes a snowball and waits; within 1000 of
-- him he bursts up out of the snow in a spray (bouncing up in steps of 42 and 47) and stands facing him, turning up
-- to 0x600 a frame - lobbing a snowball whenever he is before him (a second apart: 40 on, up by his distance, gravity
-- 3; a wedge). Run round him faster than he can turn and he grows dizzy and wobbles; dizzy enough (tipped past 0x3000)
-- he topples, and after a second shrinks away for three coins - back in the snow once he is 1000 off. (Here a hit or
-- a stomp topples him as well.) Beyond 1500 he spins back down into the snow. The CCM pair (STYPE_JUMPING) only hop
-- about their place. Touched: 2 wedges.
local BZ_ANIM = { [0] = 14, [1] = 22 }
local function bz_show(e, on)
    if e.bz_hidden == (not on) then return end
    e.bz_hidden = not on
    pcall(function() e.inst.actor:SetActorHiddenInGame(not on) end)
end
local function bz_spray(e, up)
    local EF = package.loaded["envfx"]
    if EF and EF.poof then
        local sx, sy, sz = to_scene(e.x, e.y + (up or 0.0), e.z)
        pcall(EF.poof, sx, sy, sz, 0.9)
    end
end
local function bz_topple(e, m)
    local B = e.bz
    -- (mr_blizzard_act_death: wearing Mario's cap, he lets it fall - 105 up on him, 10 a frame off to a side)
    if e.cap_bz and e.cap_inst then
        local MC = package.loaded["mariocap"]
        cap_shown_on(e, lib.world(), false)
        if MC and MC.drop then
            local sx, sy, sz = to_scene(e.x, e.y + (B.gy or 0.0) + 105.0, e.z)
            pcall(MC.drop, sx, sy, sz, math.random(0, 359), 225.0, 200.0)
        end
        log("Mr. Blizzard: toppled, he lets Mario's cap fall")
    end
    B.act, B.t, B.fell = "death", 0, nil
    if B.diz == 0.0 then B.diz, B.dizv = (math.random(0, 1) == 0) and -1.0 or 1.0, 0.0 end
    log("Mr. Blizzard: toppled")
end
local BLIZZ_HOP = 43.75        -- (Mario 64 units a frame up, the CCM snowmen's hops: Mario 64's 50, about 2 m; 70, about 4.6 m.
                                -- Then as high, floating longer - 1.9 s in the air, not 1.2 - with their own gravity in the
                                -- air, T.bhvMrBlizzard.hop_g: "make the snowmen jump for longer", "the two fuckers on the
                                -- bridge", 2026-11-05)
local function step_blizzard(e, m, pawn, world)
    local B = e.bz
    B.t = B.t + 1
    -- (Mario's cap on his head while the file says he has it, and he is up out of the snow)
    if e.cap_bz then
        local MC = package.loaded["mariocap"]
        local has = MC and MC.held_by and MC.held_by("blizzard")
        local up = has and not e.bz_hidden and B.act ~= "death"
        cap_shown_on(e, world, up, e.x, e.y + (B.gy or 0.0) + 150.0 * (B.scale or 1.0), e.z, -(e.yaw or 0) * 360.0 / 65536.0)
    end
    e.f = e.f + 1.0
    local feet = m.y - 120.0
    local ang = s16(atan2s(m.z - e.z, m.x - e.x))
    local function go(act) B.act, B.t, e.f = act, 0, 0.0 end
    -- (run round him three times, close, and he gets dizzy and topples over, dead - as Mr. I does when Mario circles
    -- him: "when you spin around him 3 times he falls over and dies", 2026-10-18. Turns the other way count back; off
    -- more than 700, the count starts again.)
    if not e.bz_hidden and B.act ~= "death" and B.act ~= "spawn" and B.act ~= "hide" and B.gy >= 0.0 then
        if m.dist < 700.0 then
            if B.ring_a then B.ring_sum = (B.ring_sum or 0) + s16(ang - B.ring_a) end
            B.ring_a = ang
            if abs(B.ring_sum or 0) >= 3 * 65536 then
                B.ring_sum, B.ring_a = 0, nil
                log("Mr. Blizzard: run round three times")
                bz_topple(e, m)
            end
        else
            B.ring_sum, B.ring_a = 0, nil
        end
    end
    -- (and making or throwing a snowball, up out of the snow, he keeps turning to him and leaning with the laps too)
    if (B.act == "throw" or (B.act == "spawn" and B.gy >= 0.0)) and not e.bz_hidden then
        e.yaw = turn_toward(e.yaw, ang, 0x2000)
        B.diz, B.dizv = (B.ring_sum or 0) / (3.0 * 65536.0) * 0x2800, 0.0
    end
    if B.act == "spawn" then
        -- (mr_blizzard_act_spawn_snowball: his snowball made, he waits buried, or turns to face him again)
        e.anim_i = 0
        if B.t >= BZ_ANIM[0] - 1 then
            if B.gy < 0.0 then go("hide") else go("rotate") end
        end
    elseif B.act == "hide" then
        if m.dist < 1000.0 then
            sound("snow_sand2", loudness(e, m))                     -- (SOUND_OBJ_SNOW_SAND2)
            go("rise")
            e.yaw, B.gyv = ang, 42.0
            bz_spray(e, 0.0)
            bz_show(e, true)
        else
            bz_show(e, false)
        end
    elseif B.act == "rise" then
        if B.wait > 0 then
            B.wait = B.wait - 1
        else
            B.gy = B.gy + B.gyv
            if B.gy > 24.0 then
                e.y = e.y + B.gy - 24.0
                B.gy = 24.0
                bz_spray(e, 20.0)
                go("rotate")
                e.vy = B.gyv
            else
                B.gyv = B.gyv - 10.0
                if B.gyv < 0.0 then B.gyv, B.wait = 47.0, 5 end
            end
        end
    elseif B.act == "rotate" then
        -- (he keeps his eyes on the athlete however fast he runs round him - Mario 64's 0x600 a frame, on the ground
        -- only, lost him: "snowman still looses track of player when spinning around him", 2026-10-18 - and leans more
        -- with each time round, his dizziness the laps run (B.ring_sum, above), till at three he goes over)
        e.yaw = turn_toward(e.yaw, ang, 0x2000)
        B.diz = (B.ring_sum or 0) / (3.0 * 65536.0) * 0x2800
        B.dizv = 0.0
        if e.ground then
            if B.diz == 0.0 and m.dist > 1500.0 then
                go("burrow"); B.dizv = 300.0
            elseif B.t > 60 and abs(s16(ang - e.yaw)) < 0x800 then
                go("throw")
            end
        end
    elseif B.act == "throw" then
        e.anim_i = 1
        if B.t == 7 then
            -- (bhv_mr_blizzard_snowball: thrown 40 on, up by his distance - at most 800 - aimed a little to one side)
            sound("en_scuttle_alert", loudness(e, m))               -- (SOUND_OBJ2_SCUTTLEBUG_ALERT, as Mario 64's throw)
            local d = math.min(800.0, m.dist)
            local yaw = s16(e.yaw + 4000 - d * 4.0)
            local s = { kind = "snowball", x = e.x + 60.0 * sins(e.yaw), y = e.y + 150.0, z = e.z + 60.0 * coss(e.yaw),
                        vx = 40.0 * sins(yaw), vy = -20.0 + d * 0.075, vz = 40.0 * coss(yaw), life = 120, dmg = 1 }
            local data = H.actor_data and H.actor_data("geo_white_particle_geo")
            if data then s.inst = instance(world, data, s.x, s.y, s.z, 0, 2.0) end
            M.shots[#M.shots + 1] = s
        end
        if B.t >= BZ_ANIM[1] - 1 then go("spawn") end
    elseif B.act == "burrow" then
        B.diz = B.diz + B.dizv
        B.dizv = B.dizv + (B.diz < 0.0 and 150.0 or -150.0)
        B.gy = approach(B.gy, -200.0, 4.0)
        if B.gy <= -200.0 then
            go("spawn"); B.diz, B.dizv = 0.0, 0.0
        end
    elseif B.act == "death" then
        if abs(B.diz) >= 0x4000 then
            B.diz = (B.diz < 0.0) and -0x4000 or 0x4000
            if B.dizv ~= 0.0 then sound("snow_sand1", loudness(e, m)); B.dizv = 0.0 end      -- (SOUND_OBJ_SNOW_SAND1)
        else
            B.dizv = B.dizv + (B.diz < 0.0 and -40.0 or 40.0)
            B.diz = B.diz + B.dizv
        end
        if B.t >= 30 then
            if B.t == 30 then sound("en_shrink", loudness(e, m)) end
            if B.scale > 0.0 then
                B.scale = B.scale - 0.03
                if B.scale <= 0.0 then
                    B.scale = 0.0
                    bz_show(e, false)
                    if H.spawn_coin then
                        local sx, sy, sz = to_scene(e.x, e.y + 60.0, e.z)
                        loot(e, 3, sx, sy, sz)
                    end
                end
            elseif m.dist > 1000.0 then
                -- (back in the snow, buried)
                e.x, e.y, e.z = e.hx, e.hy, e.hz
                e.prev = { e.x, e.y, e.z }
                go("spawn")
                B.scale, B.gy, B.diz, B.dizv = 1.0, -200.0, 0.0, 0.0
            end
        end
    elseif B.act == "jump" then
        -- (mr_blizzard_act_jump: hops 10 on and BLIZZ_HOP up, turning back once 700 from his place)
        if B.wait > 0 then
            e.yaw = turn_toward(e.yaw, B.tyaw, 3400)
            B.wait = B.wait - 1
            if B.wait == 0 then
                sound("blizzard_alert", loudness(e, m))             -- (SOUND_OBJ_MR_BLIZZARD_ALERT)
                -- (higher than Mario 64's 50 and 25 - twice as high: "make snowmen jump higher", 2026-10-18)
                if B.home_d > 700 then
                    B.tyaw, e.vy, B.wait, B.home_d = s16(B.tyaw + 0x8000), BLIZZ_HOP * 0.5, 30, 0
                    e.ground = false
                else
                    e.fvel, e.vy, e.ground = 10.0, BLIZZ_HOP, false
                end
            end
        elseif e.ground and not B.landed then
            B.landed = true
            sound("snow_sand1", loudness(e, m))
            if B.home_d ~= 0 then
                local hx, hz = e.x - e.hx, e.z - e.hz
                B.home_d = floor(sqrt(hx * hx + hz * hz))
            else
                B.home_d = 700
            end
            e.fvel, B.wait = 0.0, 15
        end
        if not e.ground then B.landed = nil end
    end
    -- moving: falling and walking with gravity 4 (cur_obj_move_standard); hidden, he stays put
    -- (a hop in the air: his own lighter gravity, t.hop_g - the same height, longer up there)
    if B.act ~= "hide" and B.act ~= "spawn" or B.gy >= 0.0 then
        walk(e, (B.act == "jump" and not e.ground and e.t and e.t.hop_g) or 4.0, false)
    end
    -- (his tilt and his height in the snow: oFaceAngleRoll = dizziness; oGraphYOffset)
    e.roll = s16(floor(B.diz))
    e.gfx_y = B.gy + abs(20.0 * sins(e.roll)) - 40.0 * (1.0 - B.scale)
    local k = (e.sk or 1.0) * math.max(0.01, B.scale)
    if not B.k or abs(k - B.k) > 0.01 then
        B.k = k
        pcall(function() e.inst.actor:SetActorScale3D({ X = k, Y = k, Z = k }) end)
    end
end

-- WDW's Skeeters (skeeter.inc.c bhv_skeeter_update): on the water they float on its surface, turning slowly to a new
-- heading, and then skate off in a lunge (80, slowing 0.8 a frame) - heading home once 1000 from it, else a little to
-- one side. Ashore (skeeter_act_walk / _idle) they walk at 10 - their legs as fast as they go, 0.12 a frame for each
-- of its speed - turning 45 degrees now and then, or stand a while; within 500 of him they come for him at 20, while
-- he is within 1000 of their home (treat_far_home_as_mario). Its wall hitbox, 180 (bhvSkeeter's SET_OBJ_PHYSICS):
-- a wall turns it off it, as Mario 64's, ashore and on the water ("they also go through walls", and "also not moving
-- correctly" - ashore it slid about in the water's skating pose, 2026-10-28).
-- (on M, not file locals: the file is at Lua's 200)
M.SKEETER_WALL = 180.0
function M.skeeter_wall(x, y, z)
    if not H.wall_near then return nil end
    local sx, sy, sz = to_scene(x, y + 10.0, z)
    local hit, px, py = H.wall_near(sx, sy, sz, M.SKEETER_WALL * S, 5.0 * S)
    if hit and (px ~= 0.0 or py ~= 0.0) then
        local mx, mz = py / S, -px / S                  -- (the push out of it, Mario 64's x and z: the way its face looks)
        return mx, mz, s16(atan2s(mz, mx))
    end
    return nil
end
-- (and a moving platform's side, as a wall: platforms.lua's own boxes - the level's walls have none of them; "skeeters
-- still going through platforms", 2026-10-28. Not over its top, where it would stand on it.)
function M.skeeter_plat(x, y, z)
    local PL = package.loaded["platforms"]
    if not (PL and PL.solid_near) then return nil end
    local sx, sy, sz = to_scene(x, y + 10.0, z)
    local ok, hit, ux, uy = pcall(PL.solid_near, sx, sy, sz, M.SKEETER_WALL * S, 40.0)
    if ok and hit then
        local mx, mz = uy, -ux                          -- (the way out, Mario 64's x and z)
        return mx, mz, s16(atan2s(mz, mx))
    end
    return nil
end
-- (cur_obj_reflect_move_angle_off_wall)
function M.skeeter_reflect(yaw, wall) return s16(wall - s16(yaw - wall) + 0x8000) end
-- A heading for its next skate on the water (surface `w`) with room for it: `want`, or the nearest turn off it with
-- open water 150, 400 and 700 out - no wall, platform side, shore or edge of the water. Aimed home past the shore or a
-- wall, it skated, bounced straight back and aimed the same way again, stuck where it was: "trying to skeet and not
-- being able to", 2026-10-28. None open: `want`.
function M.skeeter_open(e, want, w)
    local G = package.loaded["game"]
    local function open(yaw)
        for _, d in ipairs({ 150.0, 400.0, 700.0 }) do
            local x, z = e.x + d * sins(yaw), e.z + d * coss(yaw)
            if M.skeeter_wall(x, w, z) or M.skeeter_plat(x, w, z) then return false end
            local fy = floor_y(x, w + 100.0, z)
            if fy and fy > w - 30.0 then return false end
            if G and G.water_at and not G.water_at(to_scene(x, 0, z)) then return false end
        end
        return true
    end
    for i = 0, 8 do
        for _, sgn in ipairs(i == 0 and { 1 } or { 1, -1 }) do
            local yaw = s16(want + sgn * i * 0x1000)
            if open(yaw) then return yaw end
        end
    end
    return want
end
function M.step_skeeter_land(e, m, near, strayed, home_yaw)
    local L = e.sk_l
    if not L then
        -- (off the water, or new: still a moment first - skeeter_act_lunge ends in _idle, which stops it dead ashore)
        L = { act = "idle", t = 0, tyaw = e.yaw, v = 10.0, wait = math.random(0, 30) }
        e.sk_l = L
        e.fvel = 0.0
    end
    L.t = L.t + 1
    e.action = near and "chase" or "home"
    if L.act == "idle" then
        e.anim_i, e.fvel = 3, 0.0
        e.f = e.f + 1.0
        if L.t > L.wait then L.act, L.t = "walk", 0 end
    else
        -- (turning off a wall or an edge it stops to turn, and goes that way a while, `clear`, before it looks for him or
        -- its home again: turned straight back to him, it walked into the same wall over and over - "scuttlebugs walking
        -- into walls", 2026-10-28)
        e.fvel = approach(e.fvel, L.away and 0.0 or L.v, L.away and 2.0 or 0.4)
        if L.away then
            -- (obj_resolve_collisions_and_turn: turning off a wall or an edge, till it faces where it means to)
            if abs(s16(L.tyaw - e.yaw)) < 0x400 then L.away, L.clear = false, 45 end
        else
            local clear = (L.clear or 0) > 0
            if clear then L.clear = L.clear - 1 end
            if strayed and not clear then L.tyaw, L.wait = home_yaw, math.random(20, 50) end
            if near and not clear then
                L.tyaw, L.v = m.angle, 20.0
            elseif near then
                L.v = 20.0
            else
                L.v = 10.0
                if L.wait > 0 then
                    L.wait = L.wait - 1
                elseif math.random(0, 3) ~= 0 then
                    L.tyaw = s16(e.yaw + (math.random(0, 1) == 0 and -0x2000 or 0x2000))
                    L.wait = math.random(100, 200)
                else
                    L.act, L.t, L.wait = "idle", 0, math.random(100, 200)
                end
            end
        end
        e.yaw = turn_toward(e.yaw, L.tyaw, 0x400)
        e.anim_i = 2
        local f0 = e.f
        e.f = e.f + 0.12 * e.fvel
        if floor(e.f / 10.0) ~= floor(f0 / 10.0) then sound(e.t.snd.walk, loudness(e, m, 2500.0)) end
    end
    -- (obj_bounce_off_walls_edges_objects: a wall ahead, off it as a ball would; an edge, back the way it came)
    if e.fvel > 0.0 then
        local nx, nz = e.x + e.fvel * sins(e.yaw), e.z + e.fvel * coss(e.yaw)
        local _, _, wall = M.skeeter_wall(nx, e.y, nz)
        local plat = false
        if not wall then _, _, wall = M.skeeter_plat(nx, e.y, nz); plat = wall ~= nil end
        if wall and abs(s16(wall - e.yaw)) > 0x4000 then
            L.tyaw, L.away = M.skeeter_reflect(e.yaw, wall), true
            if plat then e.fvel = 0.0 end               -- (a platform's side: no step into it - walk keeps off the level's walls only)
        end
    end
    walk(e, 4.0, true)
    if e.edge and not L.away then L.tyaw, L.away = s16(e.yaw + 0x8000), true end
end
local function step_skeeter(e, m, pawn, world)
    local G = package.loaded["game"]
    local wl = G and G.water_at and G.water_at(to_scene(e.x, 0, e.z))
    local w = wl and wl / S or nil
    local fy = floor_y(e.x, e.y + 100.0, e.z)
    -- (on the water wherever its top is over the floor at all, however shallow - cur_obj_move_y floats it there, and
    -- only a floor up out of the water takes it ashore. Kept to 30 deep, it walked about in WDW's shallows with its
    -- glide's speed: "skeeters still walking on water", "instead of skeeting", 2026-10-28)
    local on_water = w and (not fy or fy < w) and e.y <= w + 60.0
    -- (treat_far_home_as_mario(1000): strayed 1000 from home, home is the way; him 1000 from its home, it lets him be)
    local hx, hy, hz = e.hx - e.x, e.hy - e.y, e.hz - e.z
    local far = hx * hx + hy * hy + hz * hz > 1000.0 * 1000.0
    local ax, ay, az = e.hx - m.x, e.hy - m.feet, e.hz - m.z
    local near = not far and ax * ax + ay * ay + az * az <= 1000.0 * 1000.0 and m.dist < 500.0
    if not on_water then
        e.sk_w = nil
        return M.step_skeeter_land(e, m, near, far, s16(atan2s(hz, hx)))
    end
    e.sk_l = nil
    e.action = "home"
    local K = e.sk_w
    if not K then
        K = { act = "idle", t = 0, tyaw = e.yaw, yv = 0, wait = math.random(0, 30) }
        e.sk_w = K
    end
    K.t = K.t + 1
    e.y, e.vy, e.ground = w, 0.0, false
    if K.act == "idle" then
        e.anim_i, e.fvel = 1, 0.0
        e.f = e.f + 1.0
        -- (a second still, not two, and a turn of more than a quarter round made up to four times as fast: turned back
        -- off the shore, it sat turning on the spot five and six seconds - "skeeters still getting stuck", 2026-10-28)
        if K.t > 30 then
            local far_round = abs(s16(K.tyaw - e.yaw)) > 0x4000
            K.yv, e.yaw = smooth_turn(K.yv, e.yaw, K.tyaw, far_round and 200 or 50, far_round and 800 or 200)
            if e.yaw == K.tyaw then
                if K.wait > 0 then
                    K.wait = K.wait - 1
                else
                    sound("skeeter_skate", loudness(e, m))          -- (SOUND_OBJ_WALKING_WATER)
                    K.act, K.t, e.fvel, K.yv = "lunge", 0, 80.0, 0
                    e.f = 0.0                                       -- (its push, from the start)
                end
            end
        end
    else
        -- (its one push and then a glide: Mario 64's lunge animation is a one-shot of 20 frames, ANIM_FLAG_NOLOOP, held
        -- on its last as it slows - looped, it paddled all the way: "skeeters not gliding like they should on water",
        -- "they get like a boost", 2026-10-28)
        e.anim_i = 0
        e.f = math.min(e.f + 1.0, 19.0)
        e.fvel = approach(e.fvel, 0.0, 0.8)
        if e.fvel == 0.0 then
            e.f = 0.0
            local want = far and s16(atan2s(hz, hx)) or s16(e.yaw + (math.random(0, 1) == 0 and -1 or 1) * math.random(0, 0x1FFF))
            K.tyaw = M.skeeter_open(e, want, w)
            K.act, K.t, K.wait = "idle", 0, math.random(0, 30)
        end
    end
    -- (cur_obj_move_standard's drag - bhvSkeeter's 10: each of its x and z speeds less its square x 0.001 every frame,
    -- as well as the 0.8 - its glide some 1100, a second and a half, where without it went 4000: "its going way too
    -- far", 2026-10-28)
    local vx, vz = e.fvel * sins(e.yaw), e.fvel * coss(e.yaw)
    vx = vx - (vx > 0.0 and 1.0 or -1.0) * min(abs(vx), vx * vx * 0.001)
    vz = vz - (vz > 0.0 and 1.0 or -1.0) * min(abs(vz), vz * vz * 0.001)
    if K.act == "lunge" then e.fvel = sqrt(vx * vx + vz * vz) end
    -- along its heading; a wall (its wall hitbox) or the shore (the floor there above the water) turns it back, slowed
    -- (skeeter_act_lunge: off a wall as a ball would, at 0.3 the speed)
    local nx, nz = e.x + vx, e.z + vz
    local _, _, wall = M.skeeter_wall(nx, w, nz)
    if not wall then _, _, wall = M.skeeter_plat(nx, w, nz) end     -- (and the moving platforms' sides: floating ones)
    local ahead = floor_y(nx, w + 100.0, nz)
    local wet = G.water_at(to_scene(nx, 0, nz))
    if e.fvel > 0.0 and wall and abs(s16(wall - e.yaw)) > 0x4000 then
        e.yaw, e.fvel = M.skeeter_reflect(e.yaw, wall), e.fvel * 0.3
    elseif e.fvel > 0.0 and ((ahead and ahead > w - 30.0) or not wet) then     -- (the shore, or the water's edge)
        e.yaw, e.fvel = s16(e.yaw + 0x8000), e.fvel * 0.3
    else
        e.x, e.z = nx, nz
    end
end

-- WDW's Heave-Hos (heave_ho.inc.c), a wind-up toy: wound up, it walks at 10 after him for 150 frames, turning 0x400 a
-- frame, then runs down - slower and slower to a tenth of that over the next 152 - stops and winds itself up again (its
-- walk turned backwards in fits for 118 frames, D_8032F460), and off again; him 1000 from its home, home is the way.
-- Having thrown him (touch's toss) it plays its throw and winds up. Walls (wall_r 200) and edges keep it in (walk).
M.HH_WIND = { 30, 42, 52, 64, 74, 86, 96, 108, 118 }     -- (still till the first, winding till the next, and so on)
-- (how far from its home he can be and it still comes for him: Mario 64's 1000 lost him at once - "chukya loses sight
-- of the player very easily" - the Heave-Hos, 2026-10-28)
M.HH_LEASH = 2500.0
-- (its throw, back over it and up (touch), cm/s: Mario 64's 45 back and 95 up (bhv_heave_ho_throw_mario_loop) under its
-- gravity of 4 a frame fly Mario 8.5 m up and 16 m on; under the engine's 980 cm/s2 the same flight is 1290 up and 610
-- back. 2200 and 700 flew him some 25 m up and 30 m on: "shuckyas launch player further then normal", "still launching
-- the player far as fuck", 2026-10-31 - WDW's Heave-Hos.)
M.HH_THROW_OUT, M.HH_THROW_UP = 610.0, 1290.0
M.REGRAB_GRACE = 1.5            -- s on his feet after a knock-down before a Chuckya grabs him again (touch)
function M.step_heaveho(e, m, pawn, world)
    local W = e.hh
    if not W then W = { act = 1, t = 0 }; e.hh = W end
    if (e.touch_cool or 0) == 19 and W.act ~= 3 then W.act, W.t, e.f = 3, 0, 0.0 end     -- (just thrown him)
    W.t = W.t + 1
    if W.act == 1 then
        e.fvel, e.anim_i, e.action = 0.0, 2, "home"
        local wind = M.HH_WIND
        if W.t >= wind[#wind] then
            W.act, W.t, e.f = 2, 0, 0.0
        else
            for i = 1, #wind do
                if W.t < wind[i] then
                    if i % 2 == 0 then e.f = e.f - 1.0 end    -- (its key turning: its walk backwards)
                    break
                end
            end
        end
    elseif W.act == 3 then
        e.fvel, e.anim_i = 0.0, 1
        e.f = e.f + 1.0
        if W.t >= 22 then W.act, W.t, e.f = 1, 0, 0.0 end
    else
        local k = 1.0
        if W.t > 150 then
            k = (302 - W.t) / 152.0
            if k < 0.1 then k = 0.1; W.act, W.t = 1, 0 end
        end
        local want = m.angle
        local hx, hz = e.hx - m.x, e.hz - m.z
        if hx * hx + hz * hz > M.HH_LEASH * M.HH_LEASH then
            want, e.action = s16(atan2s(e.hz - e.z, e.hx - e.x)), "home"
        else
            e.action = "chase"
        end
        e.yaw = turn_toward(e.yaw, want, floor(0x400 * k))
        e.fvel, e.anim_i = 10.0 * k, 0
        e.f = e.f + k
    end
    -- (its whirr its own - SOUND_AIR_HEAVEHO_MOVE as it goes - running down with it: slower and quieter as it slows,
    -- still as it winds up and as it throws; "when he starts running out of energy, the audio emitting from him should
    -- slow to a stop", 2026-10-28)
    local SFX = package.loaded["sfx"]
    if SFX and SFX.tune then
        if not e.loop_name then
            M.hh_n = (M.hh_n or 0) + 1
            e.loop_name = e.t.snd.loop .. "@" .. M.hh_n
        end
        local k = (W.act == 2) and (e.fvel / 10.0) or 0.0
        SFX.tune[e.loop_name] = { v = math.min(1.0, k / 0.6), rate = math.max(0.2, k) }
    end
    walk(e, 4.0, true)
end

-- HMC's boulders (boulder.inc.c)
local function step_boulder_gen(e, m, pawn, world)
    e.at = ((e.at or -1) + 1) % 256
    -- (Mario 64's bhv_big_boulder_generator_loop: one every 64 frames with him within 6000, every 128 farther - they
    -- roll on down to him at the slope's foot, 75 m off; sent only within 60 m, they stopped there: "boulders not
    -- respawning", 2026-10-25. Not once he is right by it, nor from across the level.)
    if m.dist < 1500.0 or m.dist > 15000.0 or e.at % (m.dist < 6000.0 and 64 or 128) ~= 0 then return end
    local data = e.o.rock and H.actor_data and H.actor_data("geo_" .. e.o.rock)
    local inst = data and instance(world, data, e.x, e.y + 270.0, e.z, 0, 1.5)
    if not inst then return end
    local yaw = math.random(0, 4095)
    local b = { t = T.BigBoulder, type = "BigBoulder", o = { bp = 0 }, inst = inst, x = e.x, y = e.y + 270.0, z = e.z, gy = e.y,
                hx = e.x, hy = e.y, hz = e.z, yaw = yaw, pitch = 0, timer = 0, f = 0, action = "roll", hp = 1, scale = 1.5, sk = 1.5,
                vx = 40.0 * sins(yaw), vz = 40.0 * coss(yaw), vy = 0.0, from = e, stuck = 0 }
    b.prev = { b.x, b.y, b.z }
    M.list[#M.list + 1] = b
end
-- BoB's pit balls (bowling_ball.inc.c bhv_bob_pit_bowling_ball_loop: object_step with gravity 12 and no friction):
-- on the ground the floor's tilt pulls them along - Mario 64's calc_new_obj_vel_and_pos_y, n_xz * (nx^2 + nz^2) *
-- gravity * 2 a frame - a dead flat floor sets them to 28 the way they go, and they bounce off walls at full speed.
-- (They lost 70 % at each wall and were braked three times as hard on the slopes: "the 2 balls in the pit they dont
-- reach the corner".)
local function step_pit_ball(b, m, pawn)
    local nx, nz = b.x + b.vx, b.z + b.vz
    local fy = floor_y(nx, b.gy - 100.0, nz)                -- (a floor no more than 150 above: else a wall)
    local wall = not fy and floor_y(nx, b.gy + 600.0, nz)
    if not wall and H.wall_near then
        local sx, sy, sz = to_scene(nx, b.gy, nz)
        local hit, px, py = H.wall_near(sx, sy, sz + 60.0, 100.0 * S)
        if hit and (px ~= 0.0 or py ~= 0.0) then wall = { py, -px } end     -- (its push, Mario 64's x and z)
    end
    if wall then
        -- off the wall, its speed kept: reflected about the wall's face, or straight back if that is unknown
        local wx, wz = (type(wall) == "table") and wall[1] or 0.0, (type(wall) == "table") and wall[2] or 0.0
        local wl = sqrt(wx * wx + wz * wz)
        if wl > 0.001 then
            wx, wz = wx / wl, wz / wl
            local dot = b.vx * wx + b.vz * wz
            if dot < 0.0 then b.vx, b.vz = b.vx - 2.0 * dot * wx, b.vz - 2.0 * dot * wz end
        else
            b.vx, b.vz = -b.vx, -b.vz
        end
        b.stuck = b.stuck + 1
    else
        b.x, b.z = nx, nz
        b.stuck = 0
    end
    local z, n1, n2, n3 = nil, 0.0, 0.0, 1.0
    if H.floor_normal then
        local sx, sy, sz = to_scene(b.x, b.gy, b.z)
        z, n1, n2, n3 = H.floor_normal(sx, sy, sz + 150.0 * S)
    end
    fy = z and z / S or floor_y(b.x, b.gy - 100.0, b.z)
    if fy and b.gy <= fy + 5.0 then
        if b.vy < -10.0 then sound("grindel_roll", loudness(b, m, 4000.0)) end
        b.gy, b.vy = fy, 0.0
        if z then
            -- (the floor's normal in Mario 64's axes: x = the scene's y, z = minus the scene's x)
            local fnx, fny, fnz = n2, n3, -n1
            local k = (fnx * fnx + fnz * fnz) * (b.grav or 12.0) * 2.0
            b.vx, b.vz = b.vx + fnx * k, b.vz + fnz * k
            if abs(fnx) < 1e-4 and abs(fnz) < 1e-4 then
                b.vx, b.vz = (b.flat or 28.0) * sins(b.yaw), (b.flat or 28.0) * coss(b.yaw)
            end
        end
    else
        b.vy = max(b.vy - (b.grav or 12.0), -75.0)
        b.gy = b.gy + b.vy
        if fy and b.gy < fy then b.gy = fy end
    end
    local sp = sqrt(b.vx * b.vx + b.vz * b.vz)
    if sp > 1.0 then b.yaw = s16(atan2s(b.vz, b.vx)) end
    b.y = b.gy + (b.lift or 130.0)
    -- run over: thrown hard, all of him
    local dx, dz = m.x - b.x, m.z - b.z
    local reach = b.reach or 200.0
    if pawn and dx * dx + dz * dz < reach * reach and m.feet < b.gy + reach * 1.5 and m.y > b.gy - 50.0 and (b.touch_cool or 0) <= 0 then
        b.touch_cool = 30
        hurt(b, m, pawn, b.dmg or 2, "a bowling ball", BALL_KNOCK, true)
    end
end

-- (a boulder is solid: whenever it reaches him he is thrown hard and limp - all of him, ragdolled - away from it and on
-- the way it rolls; hurt only out of his grace, and thrown again while down: it went through him once he had been hit -
-- "boulders should have collision that should bump hard and ragdoll the player", 2026-10-19)
-- (halved, 2.0 before: since ragdoll.lua gives his body the push in full it threw him across the level - "bomb omb
-- chainchomp and big balls do significantly more knockback then usual", 2026-10-30)
local BOULDER_KNOCK = 0.55      -- (was 1.0: "why is everything in the game doing so much knockback?", 2026-10-31)
local function boulder_bump(b, m, pawn)
    local HP = _G.HEALTH
    if HP and HP.dead_t then return end
    if M.vanished() then return end
    local G = package.loaded["game"]
    if HP and HP.grace <= 0 and not (G and G.getup_at) then HP.damage(b.dmg or 3, "a boulder") end
    local dx, dz = m.x - b.x, m.z - b.z
    local d = sqrt(dx * dx + dz * dz)
    if d < 1.0 then dx, dz, d = sins(b.yaw), coss(b.yaw), 1.0 end
    local k = 800.0 * BOULDER_KNOCK
    local vx, vz = dx / d * k + b.vx * 30.0 * S, dz / d * k + b.vz * 30.0 * S
    if H.knock_down then pcall(H.knock_down, pawn, -vz, vx, 450.0 * BOULDER_KNOCK, true) end
    log("a boulder ran into him")
end

-- HMC's boulders as Mario 64 rolls them (boulder_act_1: object_step_without_floor_orient - obj_find_wall,
-- turn_obj_away_from_steep_floor, calc_new_obj_vel_and_pos_y - gravity 8, friction 0.999, its rolling hitbox 210 round
-- and 350 high): out of any wall within its 210 at half its height and turned off it at full speed, so it zigzags down
-- between the walls; a steep floor ahead and above it a wall too; down the slope by the floor's tilt; a hard landing
-- bounces it. (Taken for a wall only where a floor stood over it, at its middle, it rolled through the walls and off
-- its way: "boulders going through wall not using correct path", 2026-10-25.)
M.BOULDER_R, M.BOULDER_MID = 210.0, 175.0            -- (fields: the chunk's locals are full)
local function step_boulder(b, m, pawn)
    if b.keep then return step_pit_ball(b, m, pawn) end
    local grav = b.grav or 8.0
    local nx, nz = b.x + b.vx, b.z + b.vz
    local walled = false
    -- (its walls: pushed out, its way mirrored off them)
    if H.wall_near then
        local sx, sy, sz = to_scene(nx, b.gy, nz)
        local hit, px, py = H.wall_near(sx, sy, sz + M.BOULDER_MID * S, (b.radius or M.BOULDER_R) * S, 1.0)
        if hit and (px ~= 0.0 or py ~= 0.0) then
            local wx, wz = py / S, -px / S                      -- (the push in Mario 64's x and z)
            nx, nz = nx + wx, nz + wz
            local wl = sqrt(wx * wx + wz * wz)
            local ux, uz = wx / wl, wz / wl
            local dot = b.vx * ux + b.vz * uz
            if dot < 0.0 then b.vx, b.vz = b.vx - 2.0 * dot * ux, b.vz - 2.0 * dot * uz end
            walled = true
        end
    end
    -- (the floor where it goes: no more than 78 over it)
    local z, n1, n2, n3 = nil, 0.0, 0.0, 1.0
    if H.floor_normal then
        local sx, sy, sz = to_scene(nx, b.gy, nz)
        z, n1, n2, n3 = H.floor_normal(sx, sy, sz + 78.0 * S)
    end
    if not z then
        -- (none under it: a pit - Mario 64's death floor down there is not in the scene's floors (the exporter leaves them
        -- out) - so it goes on over the edge and falls, till it is gone under -1000. Turned round there as off the edge
        -- of the world, it rocked at the pit's edge for good: "boulders stuck here", 2026-10-25.)
        b.x, b.z = nx, nz
        b.vy = max(-75.0, b.vy - grav)
        b.gy = b.gy + b.vy
        b.stuck = 0
    else
        local fy = z / S
        local fnx, fny, fnz = n2, n3, -n1                       -- (the floor's normal in Mario 64's axes)
        if fny < 0.5 and fy > b.gy then
            -- (a steep floor ahead, over it: turned off it as off a wall)
            local l = sqrt(fnx * fnx + fnz * fnz)
            if l > 1e-6 then
                local ux, uz = fnx / l, fnz / l
                local dot = b.vx * ux + b.vz * uz
                if dot < 0.0 then b.vx, b.vz = b.vx - 2.0 * dot * ux, b.vz - 2.0 * dot * uz end
            else
                b.vx, b.vz = -b.vx, -b.vz
            end
            b.stuck = b.stuck + 1
        else
            b.x, b.z = nx, nz
            b.stuck = 0                                         -- (rolling on, along a wall or not)
            b.vy = max(-75.0, min(75.0, b.vy - grav))
            b.gy = b.gy + b.vy
            if b.gy < fy then
                b.gy = fy
                if b.vy < -17.5 then
                    b.vy = -b.vy / 2.0
                    sound("grindel_roll", loudness(b, m, 4000.0))
                else
                    b.vy = 0.0
                end
            end
            if b.gy >= fy and b.gy < fy + 37.0 then
                -- (down the slope: the floor's tilt pulls it on, gravity * 2 at most; friction 0.999, none on a near wall)
                local L = fnx * fnx + fny * fny + fnz * fnz
                local k = (fnx * fnx + fnz * fnz) / L * grav * 2.0
                b.vx, b.vz = b.vx + fnx * k, b.vz + fnz * k
                local fr = (fny < 0.2) and 0.0 or 0.999
                if b.flat and abs(fnx) < 1e-4 and abs(fnz) < 1e-4 then
                    b.vx, b.vz, fr = b.flat * sins(b.yaw), b.flat * coss(b.yaw), 1.0
                end
                b.vx, b.vz = b.vx * fr, b.vz * fr
            end
        end
    end
    local sp = sqrt(b.vx * b.vx + b.vz * b.vz)
    if sp > 70.0 then b.vx, b.vz, sp = b.vx * 70.0 / sp, b.vz * 70.0 / sp, 70.0 end
    if sp > 1.0 then b.yaw = s16(atan2s(b.vz, b.vx)) end
    if not b.flat then b.pitch = s16(b.pitch + floor(sp * 100.0 / 1.5)) end
    b.y = b.gy + (b.lift or 270.0)
    -- run over: three wedges
    local dx, dz = m.x - b.x, m.z - b.z
    local reach = b.reach or 355.0
    if pawn and dx * dx + dz * dz < reach * reach and m.feet < b.gy + reach * 1.5 and m.y > b.gy - 50.0 and (b.touch_cool or 0) <= 0 then
        b.touch_cool = 30
        boulder_bump(b, m, pawn)
    end
    if not b.keep and (b.gy < -1000.0 or b.stuck > 40 or b.timer > 30 * 60) then b.dead = true end
end

-- BoB's water bombs (water_bomb.inc.c)
local function step_wbomb_spawner(e, m, pawn, world)
    if e.bomb then return end
    local reach = 50.0 * (((e.o.bp or 0) >> 16) & 0xFFFF) + 200.0
    local dx, dz = m.x - e.x, m.z - e.z
    if dx * dx + dz * dz > reach * reach or m.y - e.y > 1000.0 then return end
    if (e.wait or 0) > 0 then e.wait = e.wait - 1; return end
    local data = H.actor_data and H.actor_data("geo_water_bomb_geo")
    if not data then return end
    -- (ahead of him, the faster he runs the farther)
    local spd = 0.0
    pcall(function() local v = pawn:GetVelocity(); spd = math.sqrt(v.X * v.X + v.Y * v.Y) / S / 30.0 end)
    local d = 28.0 * spd + 100.0
    local bx, bz = m.x + d * sins(m.facing), m.z + d * coss(m.facing)
    local inst = instance(world, data, bx, e.y + 2000.0, bz, 0, 1.0)
    if not inst then return end
    local b = { t = T.WaterBomb, type = "WaterBomb", o = { bp = 0 }, inst = inst, x = bx, y = e.y + 2000.0, z = bz, hx = bx, hy = e.y, hz = bz,
                yaw = 0, timer = 0, f = 0, action = "drop", hp = 1, scale = 1.0, sk = 1.0, vy = -40.0, fvel = 0.0, bounces = 0,
                stretch = 0.0, from = e }
    b.prev = { b.x, b.y, b.z }
    M.list[#M.list + 1] = b
    e.bomb, e.wait = b, math.random(0, 50)
    sound("wbomb_drop", loudness(b, m, 3000.0) * 2.0)
end
local function wbomb_burst(b, m)
    sound("wbomb_splash", loudness(b, m, 3000.0))
    b.dead = true
    if b.from then b.from.bomb = nil end
end
local function step_wbomb(b, m, pawn)
    b.x, b.z = b.x + b.fvel * sins(b.yaw), b.z + b.fvel * coss(b.yaw)
    b.vy = math.max(-75.0, b.vy - 4.0)
    b.y = b.y + b.vy
    local fy = floor_y(b.x, b.y - b.vy, b.z)
    local G = package.loaded["game"]
    local wl = G and G.water_at and G.water_at(to_scene(b.x, 0, b.z))
    if wl and b.y * S < wl then wbomb_burst(b, m); return end
    if fy and b.y <= fy then
        b.y = fy
        if not b.ground then
            b.ground, b.bounces = true, b.bounces + 1
            if b.bounces < 3 then sound("wbomb_bounce", loudness(b, m, 3000.0)) end
            b.yaw, b.fvel, b.sspeed = s16(m.angle), 10.0, -40.0
        end
        -- (squashed on the ground, then up again: less each time)
        b.sspeed = b.sspeed + 15.0 - b.bounces * 2.8
        b.stretch = b.stretch + b.sspeed * 0.01
        if b.stretch < -0.8 or b.bounces >= 3 then wbomb_burst(b, m); return end
        if b.stretch > 0.1 then b.vy = 1.8 * b.sspeed end
    else
        b.stretch = approach(b.stretch, 0.0, 0.008)
        b.ground = false
    end
    local sy = b.stretch + 1.0
    local sx = 1.0 - b.stretch
    pcall(function() b.inst.actor:SetActorScale3D({ X = sx, Y = sx, Z = sy }) end)
    -- caught: a wedge, and it bursts
    local dx, dz = m.x - b.x, m.z - b.z
    if pawn and dx * dx + dz * dz < 140.0 * 140.0 and m.feet < b.y + 75.0 and m.y > b.y - 75.0 then
        hurt(b, m, pawn, 1, "a water bomb", 1.0)
        wbomb_burst(b, m)
        return
    end
    if b.timer > 30 * 20 then wbomb_burst(b, m) end
end

-- SL's Moneybags (moneybag.inc.c)
-- (its coin: Mario 64's yellow coin, four pictures facing the camera shown in turn as the level's own coins are -
-- game.lua's PICKUPS - not yellow_coin_geo drawn as a model, white and flat with one of its frames standing out of it
-- like a stick: "coin purse enemy is messed up wrong coin, coin not spinning", 2026-10-26)
-- (fields of M, not locals: this file is at Lua's 200 locals)
M.MONEYBAG_COIN = { "coin_front", "coin_tilt_right", "coin_side", "coin_tilt_left" }
function M.moneybag_coin(e, world, show)
    -- (RENDER 96: Render96's 3D coin, spun as the level's coins are - game.lua G.COIN3D, pickup_quads: "money purse dont
    -- have the updated render 96 coin in them", 2026-10-31)
    local G = package.loaded["game"]
    if show and e.coin3d == nil and not e.coin_q then
        e.coin3d = false
        local d = lib.R96 and G and G.COIN3D and H.actor_data and H.actor_data(G.COIN3D.coin)
        if d then
            local sx, sy, sz = to_scene(e.x, e.y, e.z)
            local inst = lib.make_instance(world, d, { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + 24.0 + OFFSET.Z - G.COIN3D_MID }, 0.0, 1.0)
            if inst then
                pcall(lib.pose, inst, nil, 0)
                e.coin3d = inst
            end
        end
    end
    if e.coin3d then
        local sx, sy, sz = to_scene(e.x, e.y, e.z)
        pcall(function()
            if show then
                e.coin3d.actor:K2_TeleportTo({ X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + 24.0 + OFFSET.Z - G.COIN3D_MID },
                    { Pitch = 0.0, Yaw = (os.clock() * G.COIN3D_SPIN) % 360.0, Roll = 0.0 })
            end
            if e.coin3d_h ~= (not show) then
                e.coin3d_h = not show
                e.coin3d.actor:SetActorHiddenInGame(not show)
            end
        end)
        return
    end
    if show and not e.coin_q then
        local sx, sy, sz = to_scene(e.x, e.y, e.z)
        e.coin_q, e.coin_h = {}, {}
        for i, tex in ipairs(M.MONEYBAG_COIN) do
            e.coin_q[i] = lib.quad_actor(world, { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + 24.0 + OFFSET.Z }, 24.0, tex, "alpha") or false
            e.coin_h[i] = false
        end
        pcall(lib.twin_group, e.coin_q)             -- (one shadow for its pictures in turn)
    end
    if not e.coin_q then return end
    local frame = show and (floor(os.clock() * 15.0) % 4 + 1) or 0
    local sx, sy, sz = to_scene(e.x, e.y, e.z)
    local wx, wy, wz = sx + OFFSET.X, sy + OFFSET.Y, sz + 24.0 + OFFSET.Z
    local yaw = 0.0
    if show then
        local cx, cy = lib.camera_location({ X = wx, Y = wy, Z = wz })
        yaw = math.deg(math.atan(cy - wy, cx - wx)) + 180.0
    end
    for i, q in ipairs(e.coin_q) do
        if q then
            pcall(function()
                if i == frame then q:K2_TeleportTo({ X = wx, Y = wy, Z = wz }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 }) end
                local hide = i ~= frame
                if e.coin_h[i] ~= hide then e.coin_h[i] = hide; q:SetActorHiddenInGame(hide) end
            end)
        end
    end
end
local function step_moneybag(e, m, pawn, world)
    e.f = e.f + 1.0
    e.st = e.st or "coin"
    if e.st == "coin" then
        if not e.coin_hid then
            e.coin_hid = true
            pcall(function() e.inst.actor:SetActorHiddenInGame(true) end)
        end
        M.moneybag_coin(e, world, true)
        if m.dist < 400.0 then
            local data = H.actor_data and H.actor_data("geo_moneybag_geo")
            local bag = data and instance(world, data, e.x, e.y, e.z, e.yaw, 1.0)
            if not bag then return end
            pcall(function() e.inst.actor:SetActorHiddenInGame(true) end)
            M.moneybag_coin(e, world, false)
            e.coin_inst, e.inst = e.inst, bag
            e.st, e.js, e.vy, e.fvel, e.anim_i, e.f = "move", "landing", 0.0, 0.0, 0, 0.0
            e.home0, e.home = { e.x, e.z }, { e.x, e.z }
            sound("vanish", loudness(e, m, 2000.0))
            log("Moneybags!")
        end
        return
    end
    -- falling and landing (gravity 3)
    e.x, e.z = e.x + e.fvel * sins(e.yaw), e.z + e.fvel * coss(e.yaw)
    e.vy = e.vy - 3.0
    e.y = e.y + e.vy
    local fy = floor_y(e.x, e.y - e.vy, e.z)
    local landed = false
    if fy and e.y <= fy then e.y, e.vy, landed = fy, 0.0, true end
    e.aloft = not landed                -- (mid-hop: no harm in it - touch)
    e.at = (e.at or 0) + 1
    local dh0x, dh0z = m.x - e.home0[1], m.z - e.home0[2]
    local him_far = dh0x * dh0x + dh0z * dh0z > 800.0 * 800.0
    if e.st == "move" then
        -- (wandering about its spot: obj_return_and_displace_home)
        if math.random(0, 49) == 0 then
            e.home = { e.home0[1] + math.random(-200, 200), e.home0[2] + math.random(-200, 200) }
        end
        e.yaw = turn_toward(e.yaw, s16(atan2s(e.home[2] - e.z, e.home[1] - e.x)), 0x140)
        if landed and e.js == "landing" then
            if math.random(0, 5) == 1 then e.js, e.at = "walk", 0 else e.js, e.at = "prepare", 0 end
        end
        if landed and him_far then e.st, e.js = "home", "landing" end
    elseif e.st == "home" then
        e.yaw = turn_toward(e.yaw, s16(atan2s(e.home0[2] - e.z, e.home0[1] - e.x)), 0x800)
        if landed and e.js == "landing" then e.js = "walk_home" end
        local dx, dz = e.home0[1] - e.x, e.home0[2] - e.z
        if dx * dx + dz * dz < 100.0 * 100.0 then
            -- a coin again
            sound("vanish", loudness(e, m, 2000.0))
            pcall(function() e.inst.actor:SetActorHiddenInGame(true) end)
            lib.destroy(e.inst.actor)
            e.inst, e.coin_inst = e.coin_inst, nil             -- (its model kept hidden: the coin's pictures come back)
            e.x, e.y, e.z, e.st, e.fvel = e.hx, e.hy, e.hz, "coin", 0.0
            return
        end
        if not him_far then e.st, e.js = "move", "landing" end
    end
    -- its hops (moneybag_jump)
    local js = e.js
    if js == "prepare" then
        e.anim_i = 1
        if e.at == 5 then e.fvel, e.vy = 20.0, 40.0 end
        if e.at >= 12 then e.js = "jump"; sound("boing2", loudness(e, m, 2000.0)) end
    elseif js == "jump" then
        e.anim_i = 2
        if landed and e.at > 14 then e.fvel, e.vy, e.js = 0.0, 0.0, "landing" end
    elseif js == "walk" then
        e.anim_i, e.fvel = 4, 10.0
        if e.at > 60 then e.js, e.fvel = "landing", 0.0 end
    elseif js == "walk_home" then
        e.anim_i, e.fvel = 4, 5.0
    else
        e.anim_i = 0
    end
end

-- TTM's cage Ukiki (ukiki_act_go_to_cage)
local CAGE_PATH = { { 1011, 2306, -285 }, { 1151, 2304, -510 }, { 1723, 1861, -964 }, { 2082, 1775, -1128 }, { 2489, 1717, -1141 },
                    { 2662, 1694, -1140 }, { 2902, 1536, -947 }, { 2946, 1536, -467 }, { 2924, 1536, 72 }, { 2908, 1536, 536 },
                    { 2886, 1536, 783 } }
local function step_cage_ukiki(e, m, pawn, world)
    e.f = e.f + 1.0
    if e.uheld then M.ukiki_held(e, m, pawn); return end      -- (in his hands)
    local PL = package.loaded["platforms"]
    local cage = PL and PL.ukiki_cage
    local walk = T.bhvUkiki and T.bhvUkiki.anim or {}
    if e.st == "wait" then
        -- (taunting where he waits, as both of Mario 64's Ukikis do (idle_ukiki_taunt): itching, screeching twice over,
        -- clapping, a handstand, a few of each. With no idle of his own he took animation 0 - his run - and ran on the
        -- spot: "monkey running in place on the mountain", 2026-11-02)
        local TAUNT = { 9, 4, 5, 10 }           -- (UKIKI_ANIM_ITCH, _SCREECH, _JUMP_CLAP, _HANDSTAND)
        if not e.ctaunt then e.ctaunt, e.ctn, e.ctdo = math.random(1, 4), 0, math.random(2, 5) end
        local an = TAUNT[e.ctaunt]
        if e.anim_i ~= an then e.anim_i, e.f = an, 0.0 end
        local A = e.inst and e.inst.data and e.inst.data.anims and e.inst.data.anims[an + 1]
        if e.f >= ((A and A.frames) or 30) - 1 then
            e.f, e.ctn = 0.0, e.ctn + 1
            local k = e.ctaunt
            if k == 1 or k == 4 or (k == 2 and e.ctn >= e.ctdo * 2) or (k == 3 and e.ctn >= e.ctdo) then e.ctaunt = nil end
        end
        if m.dist < 800.0 then e.yaw = turn_toward(e.yaw, m.angle, 0x400) end
        return
    end
    e.at = (e.at or 0) + 1
    if e.st == "go" then
        e.wp = e.wp or 1
        local wp = CAGE_PATH[e.wp]
        if not wp then
            -- (ukiki_act_go_to_cage: there, his DIALOG_080, then up onto the cage)
            e.st = "words"
            talk_cam(e)
            say(80, function()
                e.st, e.at = "jump", 0
                e.jx, e.jy, e.jz = e.x, e.y, e.z
            end)
            return
        end
        local pw = CAGE_PATH[e.wp - 1] or { e.hx, e.hy, e.hz }
        local dx, dz = wp[1] - e.x, wp[3] - e.z
        if (wp[1] - pw[1]) * dx + (wp[3] - pw[3]) * dz <= 0.0 then e.wp = e.wp + 1 end
        e.yaw = turn_toward(e.yaw, s16(atan2s(dz, dx)), 0x800)
        e.x, e.z = e.x + 20.0 * sins(e.yaw), e.z + 20.0 * coss(e.yaw)
        e.y = floor_y(e.x, e.y + 100.0, e.z) or approach(e.y, wp[2], 20.0)
        e.anim_i = walk.run or walk.walk or 0
    elseif e.st == "jump" then
        -- (a leap onto the cage's top, 30 frames)
        if not cage then e.st = "gone"; return end
        local k = math.min(1.0, e.at / 30.0)
        local tx, ty, tz = cage.x, cage.y + 300.0, cage.z
        e.x, e.z = e.jx + (tx - e.jx) * k, e.jz + (tz - e.jz) * k
        e.y = e.jy + (ty - e.jy) * k + 400.0 * sins(floor(k * 0x8000))
        if k >= 1.0 then
            e.st, e.at, cage.st = "spin", 0, "spin"
            sound("en_ukiki", 1.0)
        end
    elseif e.st == "spin" or e.st == "ride" then
        e.x, e.y, e.z = cage.x, cage.y + 300.0, cage.z
        if e.st == "spin" then
            e.yaw = s16(e.yaw + 0x800)
            if e.at > 32 then e.st, cage.st = "ride", "fall" end
        elseif cage.st == "hide" then
            e.dead = true
        end
    end
end

-- TTM's cap Ukiki (ukiki.inc.c, UKIKI_CAP). With Mario's own cap on his head he comes for it: runs to him when he is
-- 700 to 1000 off, turns to face him nearer, and stands taunting him there - itching, screeching, clapping, a handstand
-- (idle_ukiki_taunt) - till he is grabbed: grabbed, he has the cap (touch, mariocap.lua) and leaps off over him with it.
-- Without it (or under a wing, metal or vanish cap) he keeps away: within 300 he runs off, at 0.9 of Mario's speed, and
-- backed against a wall or an edge with him coming fast, jumps over him. Down the mountain below 1550 under he runs
-- home (Mario 64's line is 1550 under, 2 under his ledge - and the ledge comes out a unit or two lower here: he was
-- forever going home and never came for the cap, "monkey still not trying to steal hat", 2026-10-27: 150 under his place
-- instead); Mario 2000 from him and from his place, he is back there. (He wandered about his place like a Goomba and never
-- came near: "monkey not following the correct path also not trying to steal marios hat", 2026-10-27)
-- (in a block of its own, as M.step_cap_ukiki: the file is at Lua's 200 locals)
do
local UK = { RUN = 0, SCREECH = 4, JUMP_CLAP = 5, LAND = 7, JUMP = 8, ITCH = 9, HANDSTAND = 10, TURN = 11 }
local function uk_anim(e, n) if e.anim_i ~= n then e.anim_i, e.f = n, 0 end end
local function uk_frames(e)
    local an = e.inst and e.inst.data and e.inst.data.anims and e.inst.data.anims[(e.anim_i or 0) + 1]
    return (an and an.frames) or 30
end
-- (does_mario_have_normal_cap_on_head)
local function uk_mario_capped()
    local MC, C = package.loaded["mariocap"], package.loaded["caps"]
    if not (MC and MC.on_head and MC.on_head()) then return false end
    if C and C.on and (C.on("wing") or C.on("metal") or C.on("vanish")) then return false end
    return true
end
-- Ukiki in his hands (bhv_ukiki_loop's HELD_HELD, UKIKI_ANIM_HELD). Either is picked up as a baby penguin is - pushed
-- on foot within reach - and carried before him; pushed again, put down; hurt, he lets go. The cap one, held
-- (cap_ukiki_held_loop): with Mario's cap, he gives it back (DIALOG_101); with Mario wearing it, he snatches it
-- (DIALOG_100), and put down he is off over him with it. Held on after his words either way: Mario 64 lets him go there
-- (mario_retrieve_cap's drop, INT_SUBTYPE_DROP_IMMEDIATELY), and as the cap is always on one of them he was never carried
-- - "not able to pickup the monkey", 2026-10-27. The cage one (cage_ukiki_held_loop): his DIALOG_079 - "yes", and he is
-- off to his cage; "no", held on. ("supposed to be able to grab monkeys", 2026-10-27: a push at either only set off his
-- words, and never took hold of him)
M.UKIKI_HOLD = { ahead = 70.0, up = -50.0, reach = 220.0 }   -- (Mario units: before him, his feet from the athlete's middle)
function M.ukiki_let_go(e, how)
    local Hd = e.uheld
    e.uheld = nil
    if Hd then
        -- (put down before him where there is floor near his own - else at his feet)
        local px, pz = (Hd.mx or e.x) + (Hd.sx or 0.0) * 120.0, (Hd.mz or e.z) + (Hd.sz or 0.0) * 120.0
        local fy = Hd.feet and floor_y(px, Hd.feet + 100.0, pz)
        if fy and fy > Hd.feet - 150.0 then
            e.x, e.y, e.z = px, fy, pz
        elseif Hd.mx then
            e.x, e.z = Hd.mx, Hd.mz
            e.y = floor_y(e.x, Hd.feet + 100.0, e.z) or Hd.feet
        end
        e.vy, e.fvel, e.ground = 0.0, 0.0, false
        if e.anim_i == 12 then e.anim_i, e.f = nil, 0 end
        log("Ukiki put down")
    end
    if e.cap_ukiki then
        e.ua, e.ut, e.taunt = (how == "stole") and "stole" or "idle", 0, nil
    elseif how == "go" then
        e.st, e.at = "go", 0
    elseif e.st ~= "go" then
        e.st = "wait"
    end
end
function M.ukiki_grab(e, m)
    local G = package.loaded["game"]
    if e.uheld or M.lifting or (G and (G.carried or G.dying or G.getup_at or G.swim)) then return false end
    for _, x in ipairs(M.list) do if x ~= e and (x.carried or x.toggle or x.uheld) then return false end end
    e.uheld = { t = 0 }
    e.fvel, e.vy, e.ground = 0.0, 0.0, false
    sound("en_ukiki", 1.0)
    local MC = package.loaded["mariocap"]
    if e.cap_ukiki then
        log("the athlete picked up the cap Ukiki")
        if MC and MC.held_by and MC.held_by("ukiki") then
            e.uheld.talk = true
            say(101, function()
                MC.retrieve()
                e.scool = 300
                log("Ukiki gave Mario's cap back")
                if e.uheld then e.uheld.talk = nil end
            end, e)
        elseif MC and MC.lose_to and uk_mario_capped() and MC.lose_to("ukiki") then
            e.uheld.talk = true
            log("Ukiki took Mario's cap")
            say(100, function()
                e.scool = 300
                if e.uheld then e.uheld.talk, e.uheld.stole = nil, true else M.ukiki_let_go(e, "stole") end
            end, e)
        end
    elseif e.st == "wait" then
        log("the athlete picked up the cage Ukiki")
        e.st, e.uheld.talk = "asking", true
        ask(79, function(answer)
            if e.uheld then e.uheld.talk = nil end
            if answer == 1 then
                log("the Ukiki is off to the cage")
                M.ukiki_let_go(e, "go")
            elseif e.uheld then
                e.st = "held"
            else
                e.st = "wait"
            end
        end, e)
    end
    return true
end
function M.ukiki_held(e, m, pawn)
    local Hd, C = e.uheld, M.UKIKI_HOLD
    Hd.t = Hd.t + 1
    -- (hurt while he holds him - a hit, a burn, knocked flat, dying, in the water - let go, as Mario 64's hurt actions
    -- drop what Mario holds)
    local HP, G = _G.HEALTH, package.loaded["game"]
    local B, R = package.loaded["burn"], package.loaded["ragdoll"]
    local hurt = (HP and ((HP.hurt or 0) > 0 or HP.dead_t or (Hd.hp and HP.health < Hd.hp - 8))) or (B and B.active)
        or (R and R.active) or not pawn or (G and (G.dying or G.swim))
    Hd.hp = HP and HP.health or nil
    local sx, sz = sins(m.facing), coss(m.facing)
    Hd.mx, Hd.mz, Hd.sx, Hd.sz, Hd.feet = m.x, m.z, sx, sz, m.feet
    e.x, e.y, e.z = m.x + sx * C.ahead, m.y + C.up, m.z + sz * C.ahead
    e.yaw = m.facing
    if e.anim_i ~= 12 then e.anim_i, e.f = 12, 0 end
    if hurt and not Hd.talk then
        log("Ukiki: let go, hurt")
        M.ukiki_let_go(e, e.cap_ukiki and (Hd.stole and "stole" or "idle") or "wait")
    end
end

function M.step_cap_ukiki(e, m, pawn, world)
    e.f = e.f + 1.0
    if e.uheld then M.ukiki_held(e, m, pawn); return end      -- (in his hands)
    if e.scool and e.scool > 0 then e.scool = e.scool - 1 end
    local near_end = e.f >= uk_frames(e) - 1
    local capped = uk_mario_capped()
    e.ua = e.ua or "idle"
    e.ut = (e.ut or 0) + 1
    local function go(a) e.ua, e.ut = a, 0 end
    -- (handle_cap_ukiki_reset: Mario 2000 from him and from his place - back home)
    local hdx, hdy, hdz = m.x - e.hx, m.y - e.hy, m.z - e.hz
    if m.dist > 2000.0 and hdx * hdx + hdy * hdy + hdz * hdz > 2000.0 * 2000.0 then
        if e.x ~= e.hx or e.z ~= e.hz then e.x, e.y, e.z, e.fvel, e.vy = e.hx, e.hy, e.hz, 0.0, 0.0; go("idle") end
        e.anim_i = UK.ITCH
        return
    end
    local a = e.ua
    if a == "idle" then
        e.fvel = 0.0
        if not e.taunt then e.taunt, e.tn, e.tdo = math.random(1, 4), 0, math.random(2, 5) end
        local an = ({ UK.ITCH, UK.SCREECH, UK.JUMP_CLAP, UK.HANDSTAND })[e.taunt]
        if e.anim_i ~= an then
            uk_anim(e, an)
            near_end = false
            if e.taunt == 2 then sound("en_ukiki", loudness(e, m)) end
        end
        if near_end then
            e.f, e.tn = 0, e.tn + 1
            if e.taunt == 1 or e.taunt == 4 or (e.taunt == 2 and e.tn >= e.tdo * 2) or (e.taunt == 3 and e.tn >= e.tdo) then e.taunt = nil end
        end
        if capped then
            -- (rested since the last time: in at him for the cap - "monkey still not trying to steal hat", 2026-10-27;
            -- Mario 64's waits to be grabbed)
            if (e.scool or 0) <= 0 and m.dist < 1500.0 and abs(m.feet - e.y) < 400.0 then go("run")
            elseif m.dist > 700.0 and m.dist < 1000.0 then go("run")
            elseif m.dist <= 700.0 and m.dist > 200.0 and abs(s16(m.angle - e.yaw)) > 0x1000 then go("turn") end
        elseif m.dist < 300.0 then go("run") end
        if e.y < e.hy - 150.0 then go("home") end
        walk(e, 4.0, true)
    elseif a == "turn" then
        -- (ukiki_act_turn_to_mario: round to him at 0x800, creeping on at 2 to 5)
        if e.ut == 1 then e.fvel = 2.0 + math.random() * 3.0 end
        uk_anim(e, UK.TURN)
        e.yaw = turn_toward(e.yaw, m.angle, 0x800)
        if e.yaw == m.angle then go("idle"); e.taunt = nil end
        if capped then
            if m.dist > 500.0 then go("run") end
        elseif m.dist < 300.0 then go("run") end
        walk(e, 4.0, true)
    elseif a == "run" then
        -- (ukiki_act_run: to him for the cap, from him without it; till 350 to 450 off - nearer or further - then he turns)
        local flee = not capped
        local goal = flee and s16(m.angle + 0x8000) or m.angle
        if e.ut == 1 then e.range = 350.0 + math.random() * 100.0 end
        uk_anim(e, UK.RUN)
        e.yaw = turn_toward(e.yaw, goal, 0x800)
        -- (cur_obj_set_vel_from_mario_vel(20, 0.9): 0.9 of Mario's speed, never under 18)
        e.fvel = min(60.0, max(18.0, (m.speed or 0.0) / S / 30.0 * 0.9))
        local ox, oz = e.x, e.z
        walk(e, 4.0, true)
        local moved = sqrt((e.x - ox) ^ 2 + (e.z - oz) ^ 2)
        if flee then
            if m.dist > e.range then go("turn") end
        elseif (e.scool or 0) <= 0 then
            -- (up to him: the cap snatched off his head - DIALOG_100 - and off over him with it; 10 s before the next try)
            if m.dist < 140.0 and abs(m.feet - e.y) < 150.0 then
                local MC = package.loaded["mariocap"]
                if MC and MC.lose_to and MC.lose_to("ukiki") then
                    sound("en_ukiki", 1.0)
                    say(100, nil, e)
                    e.scool = 300
                    log("Ukiki snatched Mario's cap")
                    go("stole")
                else
                    e.scool = 90
                end
            end
        elseif m.dist < e.range then go("turn") end
        -- (cornered - a wall or an edge - with him on him fast or in the air: over him)
        if flee and m.dist < 200.0 and (e.edge or moved < e.fvel * 0.5) and ((m.speed or 0.0) > 10.0 * S * 30.0 or m.air) then
            e.yaw = e.edge and s16(e.yaw + 0x8000) or m.angle
            go("jump")
        end
        if e.y < e.hy - 150.0 then go("home") end
    elseif a == "stole" then
        -- (UKIKI_TEXT_STOLE_CAP: off over him the way he faces from, else to one side or the other, where there is floor)
        for _, d in ipairs({ 0x8000, 0x4000, -0x4000 }) do
            local yaw = s16(m.facing + d)
            local fy = floor_y(e.x + 150.0 * sins(yaw), e.y + 50.0, e.z + 150.0 * coss(yaw))
            if fy and fy > e.y - 100.0 then e.yaw = yaw; break end
        end
        go("jump")
    elseif a == "jump" then
        -- (ukiki_act_jump: up at 45 to 55, on at 10, untouchable till he lands)
        if e.ut == 1 then
            e.vy, e.ground, e.landed = 45.0 + math.random() * 10.0, false, nil
            uk_anim(e, UK.JUMP)
        end
        if not e.landed then
            e.fvel = 10.0
            walk(e, 4.0, false)
            if e.ut > 1 and e.ground then e.landed, e.fvel = true, 0.0; uk_anim(e, UK.LAND) end
        elseif near_end then
            e.landed = nil
            go("run")
        end
    elseif a == "home" then
        -- (ukiki_act_return_home: straight for his place at 10)
        uk_anim(e, UK.RUN)
        e.yaw = s16(atan2s(e.hz - e.z, e.hx - e.x))
        e.fvel = 10.0
        walk(e, 4.0, true)
        if e.y > e.hy - 150.0 then go("idle") end
    end
end
end

-- BBH's mad piano
local function step_piano(e, m, pawn)
    e.at = (e.at or 0) + 1
    e.myaw = e.myaw or s16(e.yaw + 0x4000)
    local moved = e.lastm and ((m.x - e.lastm[1]) ^ 2 + (m.z - e.lastm[2]) ^ 2) > 10.0 * 10.0
    e.lastm = { m.x, m.z }
    if e.action == "home" or e.action == "wait" then
        e.action, e.anim_i, e.fvel, e.chomp = "wait", 0, 0.0, nil
        if m.dist < 500.0 then
            e.near = (e.near or 0) + 1
            if e.near > 20 and moved then e.action, e.at = "attack", 0 end
        else
            e.near = 0
        end
    else
        e.anim_i = 1
        if m.dist < 500.0 then e.at = 0 end
        if e.at > 80 then
            e.action, e.fvel = "wait", 0.0
        else
            e.myaw = turn_toward(e.myaw, m.angle, 400)
            e.fvel = 5.0
            e.x, e.z = e.x + e.fvel * sins(e.myaw), e.z + e.fvel * coss(e.myaw)
            -- (Mario 64 keeps it within 400 of its place; there it stood pressed on nothing he could see - "also
            -- pianos gettings stuck on something", 2026-10-22. It goes three times as far now, and the room's walls
            -- stop it - a wall within 150 pushes it back off, as cur_obj_resolve_wall_collisions does.)
            local dx, dz = e.x - e.hx, e.z - e.hz
            local d = sqrt(dx * dx + dz * dz)
            local leash = M.PIANO_LEASH or 1200.0
            if d > leash then e.x, e.z = e.hx + dx * leash / d, e.hz + dz * leash / d end
            if H.wall_near then
                local sx, sy, sz = to_scene(e.x, e.y + 10.0, e.z)
                local hit, px, py = H.wall_near(sx, sy, sz, 150.0 * S, 5.0 * S)
                if hit and (px ~= 0.0 or py ~= 0.0) then e.x, e.z = e.x + py / S, e.z - px / S end
            end
            -- (once a loop of its bite - cur_obj_play_sound_at_anim_range(0, 0, ...) - on a count of its own: e.at goes
            -- back to 0 every frame he is near, and the chomp played every frame - "the paino's audio overlaps hundreds
            -- of times", 2026-10-22)
            e.chomp = (e.chomp or -1) + 1
            local an = e.inst and e.inst.data and e.inst.data.anims and e.inst.data.anims[2]
            local loop = (an and an.frames and an.frames > 4) and an.frames or 16
            if e.chomp % loop == 0 then sound("piano_chomp", loudness(e, m, 2500.0)) end
            local hx, hz = m.x - e.x, m.z - e.z
            if pawn and hx * hx + hz * hz < 240.0 * 240.0 and m.feet < e.y + 150.0 and m.y + 120.0 > e.y then
                hurt(e, m, pawn, 3, "the mad piano", 1.0)
            end
        end
    end
    e.yaw = s16(e.myaw - 0x4000)
    e.f = e.f + 1
end

-- BBH's haunted chair and flying bookends: near the athlete they come alive and throw themselves at him
local function step_chair(e, m, pawn)
    e.at = (e.at or 0) + 1
    local book = e.t.book
    if e.action == "home" then e.action, e.at, e.pitch, e.roll, e.wake, e.sk = "wait", 0, 0, 0, 0, e.scale end
    if e.action == "wait" then
        if m.dist < (book and 400.0 or 500.0) then
            e.wake = e.wake + 1
            if book then sound("bookend_open", loudness(e, m, 2000.0)); e.action, e.at = "rise", 0
            elseif e.wake > 1 then e.action, e.at = "rattle", 0 end
        end
    elseif e.action == "rattle" then
        -- (it shakes on the spot, a step each way every eight frames)
        if floor(e.at / 8) % 2 == 1 then
            e.pitch, e.roll = 200, 200
            if e.at % 8 == 0 then sound("chair_move", loudness(e, m, 2000.0)) end
        else
            e.pitch, e.roll = 0, 0
        end
        if e.at > 30 then e.action, e.at = "rise", 0 end
    elseif e.action == "rise" then
        if e.at < 50 then e.y = e.y + (book and 0.0 or 6.0) end
        e.pitch = book and 0 or -4000 * math.min(1.0, e.at / 30.0)
        if book and e.at >= 20 then e.sk = math.min(3.0, (e.sk or 1.0) + 0.2) end
        e.yaw = turn_toward(e.yaw, m.angle, 1000)
        if e.at > (book and 30 or 70) then
            sound(book and "en_swoop" or "haunted_chair", loudness(e, m, 3000.0))
            local dx, dy, dz = m.x - e.x, (m.y + 60.0) - e.y, m.z - e.z
            local d = math.max(1.0, sqrt(dx * dx + dy * dy + dz * dz))
            e.vx, e.vy3, e.vz = dx / d * 50.0, dy / d * 50.0, dz / d * 50.0
            e.action, e.at = "fly", 0
        end
    elseif e.action == "fly" then
        e.x, e.y, e.z = e.x + e.vx, e.y + e.vy3, e.z + e.vz
        local hx, hy, hz = m.x - e.x, m.y - e.y, m.z - e.z
        if pawn and hx * hx + hz * hz < 110.0 * 110.0 and abs(hy) < 150.0 then
            hurt(e, m, pawn, 2, book and "a flying bookend" or "a haunted chair", 1.0)
            e.at = 999
        end
        local fy = floor_y(e.x, e.y + 50.0, e.z)
        if e.at > 60 or (fy and e.y < fy) then
            sound("en_dying", loudness(e, m, 3000.0))
            e.action, e.timer = "dying", 0
        end
    end
    if e.sk and e.inst then pcall(function() e.inst.actor:SetActorScale3D({ X = e.sk, Y = e.sk, Z = e.sk }) end) end
    e.f = e.f + 1
end

-- (blown up - into a wall, at its flight's end, after it hit him: Mario 64's explosion where it is, and it is gone; a
-- while on it is back in its cannon unseen. It used to slide back to the cannon in plain sight: "the bullet bill doesnt
-- despawn rather I can see it get magnetted back to the cannon", 2026-10-17)
local function bullet_blow(e, m)
    sound("explosion", loudness(e, m, 4000.0))
    local BO = package.loaded["bobomb"]
    if BO and BO.explode_at then pcall(BO.explode_at, lib.world(), e.x, e.y - 100.0, e.z) end
    if e.inst then pcall(function() e.inst.actor:SetActorHiddenInGame(true) end) end
    e.action, e.at, e.fvel = "reload", 0, 0.0
end

-- WF's Bullet Bill (bullet_bill.inc.c)
local function step_bullet(e, m, pawn)
    e.at = (e.at or 0) + 1
    e.yaw0 = e.yaw0 or e.yaw
    local a = e.action
    if a == "reload" then
        -- (gone a couple of seconds; meanwhile back in its cannon, then seen again)
        e.x, e.y, e.z, e.yaw, e.pitch, e.roll = e.hx, e.hy, e.hz, e.yaw0, nil, nil
        if e.at > 60 then
            if e.inst then pcall(function() e.inst.actor:SetActorHiddenInGame(false) end) end
            e.action, e.at = "wait", 0
        end
        return
    elseif a == "home" then
        e.x, e.y, e.z, e.yaw, e.fvel, e.pitch, e.roll = e.hx, e.hy, e.hz, e.yaw0, 0.0, nil, nil
        e.action, e.at = "wait", 0
        return
    elseif a == "wait" then
        if abs(s16(m.angle - e.yaw)) < 0x2000 and m.dist > 400.0 and m.dist < 1500.0 then e.action, e.at = "fire", 0 end
        return
    elseif a == "fire" then
        if e.at < 40 then e.fvel = 3.0
        elseif e.at < 50 then e.fvel = (e.at % 2 == 1) and 3.0 or -3.0
        else
            e.fvel = 30.0
            if m.dist > 300.0 then e.yaw = turn_toward(e.yaw, m.angle, 0x100) end
            if e.at == 50 then sound("cannon", loudness(e, m, 4000.0)) end
            local fy = floor_y(e.x, e.y + 400.0, e.z)
            -- (into a wall it blows up - bullet_bill_act_2, OBJ_MOVE_HIT_WALL - once out of its cannon; it flew on through
            -- the level's walls: "fazing through walls", 2026-10-17)
            local wall = false
            if e.at > 62 and H.wall_near then
                local sx, sy, sz = to_scene(e.x, e.y, e.z)
                local okw, hit = pcall(H.wall_near, sx, sy, sz, 55.0)
                wall = okw and hit or false
                local PL = package.loaded["platforms"]
                if not wall and PL and PL.solid_at then
                    local okp, hp = pcall(PL.solid_at, sx, sy, sz, 40.0)
                    wall = okp and hp or false
                end
            end
            if e.at > 150 or wall or (e.at > 70 and fy and fy > e.y + 40.0) then
                bullet_blow(e, m)
                return
            end
        end
        local dx, dz = m.x - e.x, m.z - e.z
        if pawn and dx * dx + dz * dz < 110.0 * 110.0 and m.feet < e.y + 80.0 and m.y + 120.0 > e.y - 60.0 then
            -- (it launches him: his whole body thrown away from it and up - "bullet bills should launch you", 2026-10-17)
            hurt(e, m, pawn, 2, "Bullet Bill", 2.2, true)
            e.action, e.at = "hit", 0
        end
    else
        -- struck: flung up, tumbling, and blown up
        e.fvel, e.y = -30.0, e.y + 20.0
        e.pitch, e.roll = (e.pitch or 0) + 0x1000, (e.roll or 0) + 0x1000
        if e.at > 30 then bullet_blow(e, m); return end
    end
    e.x, e.z = e.x + e.fvel * sins(e.yaw), e.z + e.fvel * coss(e.yaw)
end

local STEPS = { walker = step_walker, whomp = step_whomp, clam = step_clam, thrower = step_thrower, pillar = step_pillar,
                bullet = step_bullet, ktq = step_ktq, piano = step_piano, chair = step_chair, mips = step_mips,
                penguin = step_penguin, diamond = step_diamond, eyerok = step_eyerok, eyerok_hand = step_eyerok_hand,
                tweester = step_tweester, wind = step_wind, fwoosh = step_fwoosh, boo_mgr = step_boo_mgr, book_spawn = step_book_spawn,
                snow_body = step_snow_body, snow_head = step_snow_head, snow_whole = step_snow_whole,
                manta = step_manta, ring = step_ring, ring_spawner = step_ring_spawner,
                boulder_gen = step_boulder_gen, boulder = step_boulder,
                wbomb_spawner = step_wbomb_spawner, wbomb = step_wbomb, moneybag = step_moneybag, cage_ukiki = step_cage_ukiki, cap_ukiki = M.step_cap_ukiki,
                spout = step_spout, balls = step_balls, flyer = step_flyer, boo = step_boo, amp = step_amp, piranha = step_piranha,
                spitter = step_spitter, firespit = step_firespit, lakitu = step_lakitu, npc = step_npc, sushi = step_sushi, bubba = step_bubba,
                mole = step_mole, snufit = step_snufit, swoop = step_swoop, flyguy = step_flyguy, blizzard = step_blizzard,
                skeeter = step_skeeter, heaveho = M.step_heaveho,
                decor = function(e) e.f = e.f + 1 end }

-- ------------------------------------------------------------ the athlete meets one
-- The shelled Koopa, boxed as the goombas are (the user, 2026-10-17: "give him the same hitbox as goombas and
-- collision"; game.lua G.goomba_contact/goomba_push): Mario 64's own boxes (koopa.inc.c sKoopaHitbox, scaled by its
-- size, Mario 37 round) - its hitbox 60 round and 40 high to land on (reaching STOMP_UP times up, as the goombas'),
-- its hurtbox 40 round, 30 high. Landed on (in the air, coming down, his feet over its foot inside the hitbox, or
-- gone past its top since the last frame): beaten and he bounces. Pushed or drop-kicked within reach: beaten. Any
-- other touch of the hurtbox hurts him. On the ground its body is solid: he is pushed out to its edge.
local KOOPA_STOMP_UP = 2.5
local KOOPA_PLAYER_R = 37.0
local function koopa_touch(e, m, pawn, attack, new_attack, world)
    local t = e.t
    local s = e.scale or t.scale or 1.0
    local dx, dz = m.x - e.x, m.z - e.z
    local d = sqrt(dx * dx + dz * dz)
    local base = e.y
    local feet, head = m.feet, m.y + 120.0
    local hit_r, hit_h = 60.0 * s + KOOPA_PLAYER_R, 40.0 * s * KOOPA_STOMP_UP
    local hurt_r, hurt_h = 40.0 * s + KOOPA_PLAYER_R, 30.0 * s
    local pf = e.pf
    e.pf = feet
    -- (knocked out of his shell: nothing to meet for his first 10 frames on his back or diving - cur_obj_become_intangible)
    if e.bare and (e.action == "lying" or e.action == "dive") and (e.at or 0) <= 10 then return end
    -- an attack (push or drop kick) within an arm's reach of its body: out of his shell (M.koopa_shell_off), or beaten
    if new_attack and attack and d < hurt_r + 110.0 and feet < base + hit_h + 60.0 and head > base then
        local how = attack.air and "kicked" or "pushed"
        if M.koopa_shell_off(e, m, world, how) then return end
        beaten(e, m, world, how)
        return
    end
    -- landed on
    if m.falling and d < hit_r and head > base
       and ((feet > base and feet < base + hit_h) or (pf and pf >= base + hit_h and feet < base + hit_h)) then
        if pawn then lib.bounce(pawn, 0, 0, 620) end
        if M.koopa_shell_off(e, m, world, "stomped") then return end
        beaten(e, m, world, "stomped")
        return
    end
    -- its body: hurts him, and is solid on the ground
    if d < hurt_r and feet < base + hurt_h and head > base then
        if (e.touch_cool or 0) <= 0 then
            e.touch_cool = 20
            hurt(e, m, pawn, t.dmg or 1, "a Koopa", 1.0)
        end
        local G = package.loaded["game"]
        if pawn and not m.air and not (G and (G.dying or (G.intangible and G.intangible()))) then
            if d < 1.0 then dx, dz, d = sins(e.yaw or 0), coss(e.yaw or 0), 1.0 end
            local out = (hurt_r - d + 1.0) * S
            local ux, uz = dx / d, dz / d
            pcall(function()
                local l = pawn:K2_GetActorLocation()
                -- (Mario 64 x, z -> this scene's y, -x)
                pawn:K2_SetActorLocation({ X = l.X - uz * out, Y = l.Y + ux * out, Z = l.Z }, true, {}, false)
            end)
        end
    end
end

-- A goomba's boxes (game.lua G.goomba_contact: sGoombaHitbox at a goomba's size, 1.5, with Mario's 37 round): landed on
-- from above - his feet in its box to land on, 2.5 times its height, or gone through its top since the last frame -
-- or touched in its smaller hurtbox. (base: its foot, Mario 64 units.) Returns stomp, hurt.
-- (box: another's own hitbox met by the goomba's rules - a type's goomba_box as a table, { r, h, hr, hh } at its size:
-- Wiggler's head, "give the head of the wiggler the goomba hitbox", 2026-10-29)
M.GOOMBA_BOX = { r = 72.0, h = 50.0, hr = 42.0, hh = 40.0, s = 1.5 }
-- twirl.lua, loaded if need be: only a tornado or the Boo's cage loaded it before, so after a restart a Spindrift's or a
-- Fly Guy's stomp found it missing and gave a plain bounce - "player doesnt spin when jumping on the flower enemies",
-- "like the shyguys", 2026-11-07
function M.twirl_mod()
    local ok, TW = pcall(require, "twirl")
    return ok and type(TW) == "table" and TW or nil
end

function M.goomba_box(e, m, base, box)
    local b = type(box) == "table" and box or M.GOOMBA_BOX
    local gs = b.s or e.scale or 1.0
    local hit_r, hit_h = b.r * gs + 37.0, b.h * gs * 2.5
    local hurt_r, hurt_h = b.hr * gs + 37.0, b.hh * gs
    local dx, dz = m.x - e.x, m.z - e.z
    local d = sqrt(dx * dx + dz * dz)
    local head, pf = m.y + 120.0, e.pf
    e.pf = m.feet
    local stomp = m.falling and d < hit_r and head > base
        and ((m.feet > base and m.feet < base + hit_h) or (pf and pf >= base + hit_h and m.feet < base + hit_h))
    local hurt = not stomp and d < hurt_r and m.feet < base + hurt_h and head > base
    return stomp and true or false, hurt and true or false
end

local function touch(e, m, pawn, attack, new_attack, world)
    do local G = package.loaded["game"]; if G and G.cutscene then return end end   -- (the ending: creatures take no notice of him)
    local t = e.t
    if t and t.tosser and m.body then m = m.body end       -- (down: a Heave-Ho meets his body where it lies, M.update)
    if e.action == "dying" or e.action == "gone" then return end
    if e.small then return end          -- (Wiggler, beaten and little: nothing to meet - M.wiggler_shrink)
    if e.lifted or e.action == "thrown" then return end        -- (a Chuckya in his hands, or thrown)
    if e.immune_t then e.immune_t = e.immune_t - 1; if e.immune_t <= 0 then e.immune_t = nil end end
    if e.fp and not e.fp.tangible then return end          -- (a fire piranha plant down in the ground or still growing)
    if e.sp == "wait" then return end          -- (a Scuttlebug spawner not yet thrown out: nothing there to touch)
    if t.k == "amp" then
        -- (sAmpHitbox: its hurtbox 50 round, 60 high from 40 under its middle - INTERACT_SHOCK; nothing to meet while
        -- out of sight, growing, giving up or holding still after a shock. shock.lua does the rest.)
        local s0 = e.amp_st
        if s0 == "cool" or s0 == "inactive" or s0 == "appear" or s0 == "giveup" then return end
        local dx, dz = m.x - e.x, m.z - e.z
        if dx * dx + dz * dz > (50.0 + 47.0) ^ 2 or m.feet > e.y + 20.0 or m.feet + 240.0 < e.y - 40.0 then return end
        local okr, SH = pcall(require, "shock")
        if okr and SH and SH.start(e, m, pawn) then e.amp_st, e.at, e.fvel = "cool", 0, 0.0 end
        return
    end
    if e.type == "bhvFlame" then
        -- (a torch's flame, INTERACT_FLAME: set alight and running - burn.lua - met anywhere in the flame as it is drawn,
        -- 7 times its 50-unit picture: Mario 64's own hitbox, 50 round at its middle, was missed running into the fire,
        -- and touched it only knocked him down - "running into them doesnt trigger the on fire state", 2026-10-18;
        -- then smaller, to the fire itself: "decrease the flames hitbox as well", 2026-10-19)
        local half = 25.0 * ((e.o and tonumber(e.o.scale)) or 7.0)
        local dx, dz = m.x - e.x, m.z - e.z
        if dx * dx + dz * dz > (half * 0.3 + 37.0) ^ 2 or m.feet > e.y + half * 0.45 or m.y + 80.0 < e.y - half * 0.6 then return end
        if (e.touch_cool or 0) > 0 then return end
        e.touch_cool = 30
        set_alight(e, m, pawn, "a flame", e.x, e.z)
        return
    end
    if t.k == "moneybag" and (e.st or "coin") == "coin" then return end      -- (a coin until he comes near)
    if t.k == "cage_ukiki" then
        -- pushed (Mario grabs him): picked up, and his DIALOG_079 - M.ukiki_grab; pushed again, put down
        if e.uheld then
            if new_attack and attack and not attack.air and e.uheld.t > 10 and not e.uheld.talk then M.ukiki_let_go(e, "wait") end
        elseif e.st == "wait" and new_attack and attack and not attack.air and m.dist < M.UKIKI_HOLD.reach
               and abs(m.y - e.y) < 250.0 then
            M.ukiki_grab(e, m)
        end
        return
    end
    if t.k == "whomp" then
        if new_attack and attack and attack.air and e.action == "down" then e.kicked = true end
        return
    end
    if t.k == "thrower" or t.k == "spout" or t.k == "pillar" or t.k == "balls" or t.k == "bullet" or (t.k == "clam" and not e.biting) then return end
    if t.k == "ktq" then
        if new_attack and attack and not attack.air then e.pushed = true end
        return
    end
    if t.k == "piano" or t.k == "chair" or t.k == "diamond" or t.k == "eyerok" or t.k == "tweester" or t.k == "wind"
       or t.k == "fwoosh" or t.k == "boo_mgr"
       or t.k == "book_spawn" or t.k == "snow_body" or t.k == "snow_head" or t.k == "snow_whole"
       or t.k == "manta" or t.k == "ring" or t.k == "ring_spawner" or t.k == "boulder_gen" or t.k == "boulder"
       or t.k == "wbomb_spawner" or t.k == "wbomb" then return end
    if e.unagi or e.unagi_ship then return end      -- (its bites and its tail: step_unagi, M.step_unagi_ship)
    if e.pk then touch_pokey(e, m, pawn, attack, new_attack, world); return end
    if e.bb and e.bb.mouth ~= 0 then return end     -- (Bubba's open mouth: a bite, not a bump - step_bubba)
    if e.bz then
        -- (Mr. Blizzard: nothing to meet while buried or going; touched, 2 wedges - INTERACT_MR_BLIZZARD. Here a hit or a
        -- stomp topples him too)
        local B = e.bz
        if e.bz_hidden or B.act == "death" or B.act == "spawn" or B.gy < -100.0 then return end
        local dx, dz = m.x - e.x, m.z - e.z
        local d2 = dx * dx + dz * dz
        local reach = 65.0 + 70.0
        local base = e.y - 24.0
        local hit = new_attack and d2 < (reach + 80.0) ^ 2 and m.y > base - 150.0 and m.y < base + 170.0 + 200.0
        local stomp = m.falling and d2 < 110.0 * 110.0 and m.feet > base + 100.0 and m.feet < base + 170.0 + 120.0
        if hit or stomp then
            if stomp and pawn then lib.bounce(pawn, 0, 0, 620) end
            bz_topple(e, m)
            return
        end
        if d2 > reach * reach or m.y < base - 120.0 or m.feet > base + 170.0 then return end
        if (e.touch_cool or 0) > 0 then return end
        e.touch_cool = 20
        hurt(e, m, pawn, 2, "Mr. Blizzard", 1.0)
        return
    end
    if e.ml then
        -- (a Monty Mole: none to meet down a hole; INTERACT_BOUNCE_TOP - hit or landed on, it is gone into the ground;
        -- its side touched, 2 wedges)
        if e.ml.act == "select" then return end
        local dx, dz = m.x - e.x, m.z - e.z
        local d2 = dx * dx + dz * dz
        local reach = 70.0 + 70.0
        -- (landed on and touched as a goomba is: goomba_box - "shy guys and gophers need goomba hitbox", 2026-10-20; and
        -- only landed on beats it, not a shove: "jump on only to kill")
        local hit = false
        local stomp, touched = M.goomba_box(e, m, e.y)
        if hit or stomp then
            if stomp and pawn then lib.bounce(pawn, 0, 0, 620) end
            sound("en_dying", loudness(e, m))
            local EF = package.loaded["envfx"]
            if EF and EF.poof then
                local sx, sy, sz = to_scene(e.x, e.y + 40.0, e.z)
                pcall(EF.poof, sx, sy, sz, 0.8)
            end
            -- (eight in a row, each within 1500 of the last: a 1-up)
            local last = M.mole_last
            if (M.mole_streak or 0) ~= 0 and last then
                local lx, ly, lz = e.x - last[1], e.y - last[2], e.z - last[3]
                if sqrt(lx * lx + ly * ly + lz * lz) < 1500.0 then
                    if M.mole_streak == 7 then
                        sound("puzzle_jingle", 1.0)
                        local G = package.loaded["game"]
                        local sx, sy, sz = to_scene(e.x, e.y, e.z)
                        if G and G.add_pickup then pcall(G.add_pickup, { kind = "oneup", pos = { sx, sy, sz + 60.0 } }) end
                        log("Monty Moles: eight in a row, a 1-up")
                    end
                else
                    M.mole_streak = 0
                end
            end
            M.mole_streak = (M.mole_streak or 0) + 1
            M.mole_last = { e.x, e.y, e.z }
            log("Monty Mole %s (%d in a row)", stomp and "stomped" or "hit", M.mole_streak)
            mole_hide(e)
            return
        end
        if not touched then return end
        if (e.touch_cool or 0) > 0 then return end
        e.touch_cool = 20
        hurt(e, m, pawn, 2, "Monty Mole", 1.0)
        return
    end
    if e.type == "bhvKlepto" and e.star_held then
        -- (Klepto lets the star go at a touch: Mario 64 takes any attack, and any touch in the air - jumped up into or
        -- landed on, INTERACT_HIT_FROM_BELOW - and here any at all, on foot too: "make sure when coming near to klepto
        -- he drops the star", 2026-10-23. Where he is: his body and the star from 100 under his middle to 260 over it,
        -- his wings 250 out; the athlete 240 tall from his feet)
        local dx, dz = m.x - e.x, m.z - e.z
        local d2 = dx * dx + dz * dz
        -- (and roomier, his wings and all: "gotta make it easier to hit klepto", 2026-10-23)
        local touching = d2 < 320.0 * 320.0 and m.feet < e.y + 300.0 and m.feet + 240.0 > e.y - 150.0
        local struck = new_attack and d2 < 450.0 * 450.0 and m.feet < e.y + 450.0 and m.feet + 240.0 > e.y - 300.0
        if touching or struck then klepto_drop(e, m, world) end
        return
    end
    -- The cap Ukiki (ukiki.inc.c cap_ukiki_held_loop): grabbed - a push at him, as the athlete takes hold of things - he
    -- is picked up (M.ukiki_grab): with Mario's cap he gives it back (DIALOG_101, mario_retrieve_cap); with it on Mario's
    -- head he snatches it (DIALOG_100) and is off over him with it. Pushed again, put down.
    if e.cap_ukiki then
        local MC = package.loaded["mariocap"]
        local has = MC and MC.held_by and MC.held_by("ukiki")
        cap_shown_on(e, world, has, e.x, e.y + 85.0, e.z, -(e.yaw or 0) * 360.0 / 65536.0, 0.9)
        if e.uheld then
            if new_attack and attack and not attack.air and e.uheld.t > 10 and not e.uheld.talk then
                M.ukiki_let_go(e, e.uheld.stole and "stole" or "idle")
            end
        elseif new_attack and attack and not attack.air and m.dist < M.UKIKI_HOLD.reach and abs(m.y - e.y) < 250.0
               and e.ua ~= "jump" then
            M.ukiki_grab(e, m)
        end
        return
    end
    if e.type == "bhvKlepto" and e.cap_klepto then
        -- (the cap Klepto, as the star's: holding the cap, he lets it go at any touch - on foot or in the air - once he
        -- has had it a second and a half, not as he takes it; at an attack, at once. Holding nothing, an attack knocks
        -- him back. His reach, wings and all, roomier than Mario 64's: "gotta make it easier to hit klepto", 2026-10-23)
        local k = e.kl
        if k and k.act ~= "struck" and k.act ~= "retreat" then
            local dx, dz = m.x - e.x, m.z - e.z
            local d2 = dx * dx + dz * dz
            local touching = d2 < 320.0 * 320.0 and m.feet < e.y + 300.0 and m.feet + 240.0 > e.y - 150.0
            local struck = new_attack and d2 < 450.0 * 450.0 and m.feet < e.y + 450.0 and m.feet + 240.0 > e.y - 300.0
            if k.hold == "cap" then
                if struck or (touching and (k.held_t or 999) > 45) then klepto_cap_drop(e, m, world) end
            elseif struck and M.klepto_knock then
                M.klepto_knock(e, m)
            end
        end
        return
    end
    if t.k == "eyerok_hand" then
        local EY = package.loaded["eyerok"]
        if EY then EY.touch(e, m, pawn, attack, new_attack) end
        return
    end
    if t.k == "penguin" then
        local dx, dz = m.x - e.x, m.z - e.z
        local d2 = dx * dx + dz * dz
        if new_attack and attack and not attack.air then
            if e.carried then
                e.toggle = true
            elseif d2 < 220.0 * 220.0 and abs(m.y - e.y) < 250.0 then
                -- (one at a time: none picked up while he holds one or one is being taken this frame, and of two in
                -- reach only the nearer - "you can pick up 2 penguinz at a time", 2026-10-18)
                local busy = false
                for _, x in ipairs(M.list) do
                    if x ~= e and x.t.k == "penguin" then
                        if x.carried or x.toggle then busy = true end
                        local ex, ez = m.x - x.x, m.z - x.z
                        if ex * ex + ez * ez < d2 and abs(m.y - x.y) < 250.0 then busy = true end
                    end
                end
                if not busy then e.toggle = true end
            end
        end
        return
    end
    if t.k == "mips" then
        local dx, dz = m.x - e.x, m.z - e.z
        if new_attack and attack and not attack.air and dx * dx + dz * dz < 220.0 * 220.0 and abs(m.y - e.y) < 250.0 then
            e.caught = true
        end
        return
    end
    if e.type == "bhvKoopa" and not (e.o and e.o.race) then koopa_touch(e, m, pawn, attack, new_attack, world); return end
    if (t.r or 0) <= 0 then return end
    -- (a Boo he is looking at is all but invisible and cannot be touched, either way: cur_obj_become_intangible)
    if t.k == "boo" and ((e.alpha or 1.0) < 0.5 or e.boo_hit) then return end
    local s = e.scale or 1.0
    local r, h = t.r, t.h
    local dx, dz = m.x - e.x, m.z - e.z
    local d2 = dx * dx + dz * dz
    local reach = r + 70.0
    -- (a Boo's own two sizes, times its size (sBooHitbox, sBooGivingStarHitbox): it is hit within 140 and hurts only
    -- within 40. With one reach for both, 40 + 70 hurt and 190 hit, coming at its back he was hurt before he was near
    -- enough to push it - "boos have a small hitbox on they're back", 2026-10-22)
    local hit_reach = reach + 80.0
    if t.k == "boo" then reach, hit_reach = 40.0 * s + 45.0, 140.0 * s + 80.0 end
    local base = e.y
    if t.k == "flyer" or t.k == "boo" or t.k == "amp" or t.k == "lakitu" then base = e.y - h * 0.4 end
    -- an attack (push or drop kick) within reach. (A bully takes one still under way, once in a second: a drop kick
    -- starts well out of reach and comes flying in - only its first frame counted, and it bumped him off instead:
    -- "make the big bully drop kickable", 2026-10-19)
    if t.bully and (e.hit_cool or 0) > 0 then e.hit_cool = e.hit_cool - 1 end
    local bully_hit = t.bully and attack ~= nil and (e.hit_cool or 0) <= 0 and not e.lava_t
    if (new_attack or bully_hit) and d2 < hit_reach ^ 2 and m.y > base - 150.0 and m.y < base + h + 200.0 then
        if t.bully then
            -- pushed or kicked: a bully goes flying the way he hits it (the big one less far: bully_knock_back's
            -- 3392 over its radius)
            e.hit_cool = 30
            e.yaw, e.fvel, e.vy, e.knocked, e.ground = m.facing, t.boss and 30.0 or 45.0, 25.0, true, false
            sound(t.snd.hit, loudness(e, m))
            if t.boss then e.hp = e.hp end
            return
        end
        -- (a Boo only from behind: a push or a kick at its back - "make sure they can only die from pushing them from
        -- behind", 2026-10-17; from the front it is a touch, and hurts)
        -- (and not those met as a goomba is, but for the Snufits: landed on, as a goomba is squashed, and nothing else -
        -- "every enemy other than shyguy with the goomba hitbox make it jump on only to kill. should not be able to
        -- shove them", 2026-10-20; a thrown box still beats them, as it does a goomba)
        -- (a Chuckya, pushed on foot from its side or back as he faces it, is picked up - M.chuckya_lift; from in front
        -- it grabs him, below, as Mario 64's does, and comes to no harm. A drop kick beats it, as before)
        if t.thrower and not attack.air then
            if abs(s16(m.angle - e.yaw)) >= 0x2AAA and abs(s16(m.facing - m.angle - 0x8000)) < 0x4000
               and M.chuckya_lift(e, m, pawn) then return end
        elseif t.beat and not t.noshove and not (t.k == "boo" and abs(s16(m.angle - e.yaw)) <= 0x4000) then
            beaten(e, m, world, attack.air and "kicked" or "pushed")
            return
        end
    end
    -- (a Fly Guy is met as a goomba is - game.lua G.goomba_contact: Mario 64's boxes, sFlyGuyHitbox being much as
    -- sGoombaHitbox, scaled by its size, with Mario's 37 round; its box to land on reaching 2.5 times its height, and a
    -- fast fall through its top still a stomp - "give the flutter guys the same hit box as goombas", 2026-10-18)
    -- (and a Spindrift: both at a goomba's own size, 1.5)
    -- (and Scuttlebugs, Snufits: "scuttlebugs need goomba hitbox as well", "shy guys and gophers need goomba hitbox",
    -- 2026-10-20)
    -- Fly Guys ("shy guy needs reworked. if the player jumps into him he dies if the players standing and shyguy hits the
    -- player it bumps and ragdolls the player", 2026-10-22): met while he is off the ground - a jump, a fall or one of
    -- STORROR's flips (flying mode), from any side - it is beaten, landed on from above with a bounce; met on his feet,
    -- it hurts him and knocks him flying, ragdolled (M.boo_bump, as Big Boo's). Reach: the goomba box's, 72 round
    -- times its size + 37 and 2.5 times its height up to land on; on foot its smaller hurt box.
    if t.k == "flyguy" or t.shyguy then
        local gs = 1.5
        local dx2, dz2 = m.x - e.x, m.z - e.z
        local d = sqrt(dx2 * dx2 + dz2 * dz2)
        local head = m.y + 120.0
        if m.air or m.mode == 5 then
            if d < 72.0 * gs + 37.0 and head > base and m.feet < base + 50.0 * gs * 2.5 then
                local from_above = m.falling and m.feet > base + h * 0.5
                -- (the big bounce whichever way he took it out in the air - jumped into it as well as landed on; out of
                -- one of STORROR's flips (flying mode) its move cleared first, or its root motion held him to its arc)
                -- (`t.twirl`: into a twirl instead, spinning and steered down - twirl.lua bounce_twirl: "make the player
                -- spin if they jump on the flower enemy and shyguy", 2026-11-07)
                local TW = t.twirl and M.twirl_mod()
                local twirled = false
                if pawn and TW and TW.bounce_twirl then
                    local okt, r = pcall(TW.bounce_twirl, pawn, t.twirl)
                    twirled = okt and r
                end
                if pawn and not twirled then
                    if m.mode == 5 then
                        local G = package.loaded["game"]
                        if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
                        pcall(function()
                            local cm = pawn.CharacterMovement
                            local v = cm.Velocity
                            cm:SetMovementMode(3, 0)
                            cm.Velocity = { X = v.X, Y = v.Y, Z = t.bounce or 620 }
                        end)
                    else
                        lib.bounce(pawn, 0, 0, t.bounce or 620)
                    end
                end
                beaten(e, m, world, from_above and "stomped" or "jumped into")
            end
            return
        end
        if d < 42.0 * gs + 37.0 and m.feet < base + 40.0 * gs and head > base then
            if (e.touch_cool or 0) > 0 then return end
            e.touch_cool = 30
            M.boo_bump(e, m, pawn)
        end
        return
    end
    -- (t.hit_air: met while he is in the air - jumped up into, landed on, or in one of STORROR's flips - it is beaten, as
    -- Mario 64's INTERACT_HIT_FROM_BELOW takes Lakitu from below as well as above (his rise stopped short there: here
    -- he goes on up; landed on, he bounces). On the ground it hurts as before. Only landed on before - "make jumping into
    -- lakitos kill them", 2026-10-29)
    if t.hit_air and (m.air or m.mode == 5) and d2 < reach * reach and m.y > base - 120.0 and m.feet < base + h then
        if pawn and m.falling then lib.bounce(pawn, 0, 0, t.bounce or 620) end
        beaten(e, m, world, m.falling and "stomped" or "jumped into")
        return
    end
    -- Wiggler's body segments (20 round and high x his size - INTERACT_BOUNCE_TOP): touched, or landed on
    local by_body, on_back = false, false
    if e.segs and e.action ~= "dying" then
        local sz = 20.0 * (e.scale or 1.0)
        local br = sz + 50.0
        for i = 1, 3 do
            local sg = e.segs[i]
            local bx, bz = m.x - sg.x, m.z - sg.z
            local b2 = bx * bx + bz * bz
            if b2 < br * br then
                -- (landed on from above, as a goomba's top - over half its height and up to 2.5 times it: a bounce, no
                -- harm either way - "you should also bounce off the back of wiggler if you jump on it but do no damage",
                -- 2026-10-29; it hurt him before. Nearer it than his head's middle: his head's stomp box, 2 m round,
                -- takes in the first two segments, and landing on his back hit him instead - "cant bounce off his back")
                if m.falling and m.feet > sg.y + sz * 0.5 and m.feet < sg.y + sz * 2.5 + 40.0 and b2 < d2 then on_back = i
                elseif m.y > sg.y - 120.0 and m.feet < sg.y + sz + 40.0 then by_body = true end
            end
        end
    end
    if on_back then
        if pawn then lib.bounce(pawn, 0, 0, t.bounce or 620) end
        sound(t.snd and t.snd.back, 1.0)
        e.touch_cool = 20          -- (and no hurt from the tail as he goes up off it)
        log("Wiggler: bounced off his back (segment %d)", on_back)
        return
    end
    local fg_stomp, fg_hurt = nil, nil
    if t.goomba_box then fg_stomp, fg_hurt = M.goomba_box(e, m, base, t.goomba_box) end
    -- landed on from above
    if (fg_stomp == nil and m.falling and d2 < (r + 40.0) ^ 2 and m.feet > base + h * 0.5 and m.feet < base + h + 120.0) or fg_stomp then
        if t.stomp then
            -- (`t.twirl`: bounced up that fast into a twirl, spinning and steered down - twirl.lua bounce_twirl: Spindrift,
            -- the Fly Guy - "make the player spin if they jump on the flower enemy and shyguy", 2026-11-07)
            local TW = t.twirl and M.twirl_mod()
            local twirled = false
            if pawn and TW and TW.bounce_twirl then
                local okt, r = pcall(TW.bounce_twirl, pawn, t.twirl)
                twirled = okt and r
            end
            if pawn and not twirled then lib.bounce(pawn, 0, 0, t.bounce or 620) end
            -- (t.snd.squish: the squash under his feet with the stomp - Wiggler's, "also no squish sound", 2026-10-29;
            -- only the bounce off him while he is getting over the last one)
            if t.snd and t.snd.squish then sound((e.immune or e.immune_t) and t.snd.back or t.snd.squish, 1.0) end
            if e.immune or e.immune_t then return end          -- (a boss still getting over the last one: a bounce, no hit)
            beaten(e, m, world, "stomped")
            return
        end
    end
    if fg_hurt == false and not by_body then return end
    if fg_hurt == nil and not by_body and (d2 > reach * reach or m.y < base - 120.0 or m.feet > base + h) then return end
    if (e.touch_cool or 0) > 0 then return end
    e.touch_cool = 20
    if t.harmless then return end
    if t.bully then
        -- (interact_bully: no harm - he is thrown back off it, bully_knock_back, and it back a little the other way; it
        -- knocked him flat before, "make bullys bump the player", 2026-10-19. As the Bomps' bump: STORROR's own moves
        -- cleared, falling, his speed set)
        if e.lava_t then return end
        local G = package.loaded["game"]
        local HP = _G.HEALTH
        if pawn and not (HP and HP.dead_t) and not (G and (G.getup_at or G.dying)) then
            local bx, bz = m.x - e.x, m.z - e.z
            local bd = sqrt(bx * bx + bz * bz)
            if bd < 1.0 then bx, bz, bd = sins(e.yaw), coss(e.yaw), 1.0 end
            -- (a shove, not a launch: 950 out and 380 up threw him "way to hard", 2026-10-19)
            local k = t.boss and 1.25 or 1.0
            if G and G.parkour_reset then pcall(G.parkour_reset, pawn) end
            pcall(function()
                local cm = pawn.CharacterMovement
                cm:SetMovementMode(3, 0)
                cm.Velocity = { X = -bz / bd * 400.0 * k, Y = bx / bd * 400.0 * k, Z = 220.0 }
            end)
            sound(t.snd.hit, loudness(e, m))
            e.yaw, e.fvel, e.knocked = s16(atan2s(-bz, -bx)), 15.0, true
            log("a bully bumped him")
        end
    elseif t.thrower then
        -- (check_object_grab_mario: facing him, within 60 degrees, it grabs him; from behind nothing - chuckya_act_1 then
        -- holds him out before it, turns round with him and throws him)
        local BO = package.loaded["bobomb"]
        local G = package.loaded["game"]
        -- (and not till he has been up on his feet M.REGRAB_GRACE: picked up again the moment his get-up began - "chuckyas
        -- dont give player enough time to stand before picking player up again", 2026-10-28; M.update's M.down_at)
        if BO and BO.hold and pawn and not e.held and not M.lifting and (e.grab_cool or 0) <= 0 and not (G and (G.carried or G.getup_at or G.dying))
           and os.clock() - (M.down_at or -99.0) > M.REGRAB_GRACE
           and abs(s16(m.angle - e.yaw)) < 0x2AAA then
            e.sub, e.hold_t, e.spin_n = 0, 0, 10 + math.random(0, 30)
            BO.hold.grab(e, pawn)
            e.fvel, e.anim_i = 0.0, 0
            sound("king_grab", 1.0)
            log("Chuckya grabbed the athlete")
        end
    elseif t.tosser then
        sound(t.snd.throw, 1.0)
        local G = package.loaded["game"]
        -- (the Heave-Ho: thrown back over it, the way it is not facing, his whole body at once and high - Mario 64's 45 back
        -- and 95 up; his hips alone thrown, the rest of him held them down: "next it should ragdoll and launch the player way
        -- higher", "it should launch the player in the opposite way its facing", 2026-10-28)
        if e.type == "bhvHeaveHo" then
            -- (and again while he is still down - met where his body lies, touch's m.body: "heave hos cant chain throw
            -- the player in the ragdol state", 2026-10-28; Mario 64's tosses him again whenever he lands on one)
            if H.knock_down and not (G and G.down_for_good) then
                pcall(H.knock_down, pawn, coss(e.yaw) * M.HH_THROW_OUT, -sins(e.yaw) * M.HH_THROW_OUT, M.HH_THROW_UP, true)
            end
        elseif not (G and G.getup_at) and H.knock_down then pcall(H.knock_down, pawn, -coss(e.yaw) * 600.0, sins(e.yaw) * 600.0, 3200.0) end
    elseif t.k == "piranha" and e.action == "sleep" then
        -- (asleep it does no harm: piranha_plant_act_sleep sets oDamageOrCoinValue 0)
    elseif t.k == "boo" and t.boss and (t.dmg or 0) > 0 then
        M.boo_bump(e, m, pawn)
    elseif t.k == "moneybag" and e.aloft then
        -- (Moneybags mid-hop does no harm, only on the ground - landed on or kicked as ever: "coin purses should only be
        -- able to damage the player if they're on the ground", 2026-10-26)
    elseif (t.dmg or 0) > 0 and not (t.burn and M.fireproof()) then
        hurt(e, m, pawn, t.dmg, e.type:gsub("^bhv", ""), t.knock or (t.burn and 0.6 or 1.0))
    end
end

-- ------------------------------------------------------------ every tick
local acc = 0.0
local last_attack, pending = nil, nil

local function render_flame(e, cx, cy, cz)
    -- (RENDER 96's fire: the one picture it stands on shown, never swapped - the fire flickers by itself, burn.lua)
    if e.fire3d then
        if e.shown ~= 0 then
            for i = 0, 7 do
                local q = e.quads[i]
                if q then pcall(function() q:SetActorHiddenInGame(i ~= 0) end) end
            end
            e.shown = 0
        end
        return
    end
    local frame = floor(e.timer / 2) % 8
    local sx, sy, sz = to_scene(e.x, e.y, e.z)
    sx, sy, sz = sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z
    local dx, dy, dz = cx - sx, cy - sy, cz - sz
    local yaw = math.deg(atan(dy, dx)) + 180.0
    local pitch = -math.deg(atan(dz, sqrt(dx * dx + dy * dy)))
    for i = 0, 7 do
        local q = e.quads[i]
        if q then
            pcall(function()
                if i == frame then
                    q:SetActorHiddenInGame(false)
                    q:K2_SetActorRotation({ Pitch = pitch, Yaw = yaw, Roll = 0.0 }, false)
                elseif i == e.shown then
                    q:SetActorHiddenInGame(true)
                end
            end)
        end
    end
    e.shown = frame
end

-- (a flamethrower: all its flames drawn - one a frame, each living 15: 16 at most. With 10 the five furthest out were
-- not drawn but burnt him all the same, "the flame doesnt extend far enough to account for its hitbox", 2026-10-17. And
-- Mario 64's own flame for it - its eight pictures, the game's flat red-orange (blue) at 200 of 255: "the fire texture
-- isnt original")
-- (a fire spitter's flames: each spitter keeps one flame's eight pictures - one shown at a time, two frames each, as
-- Bowser's turn through theirs - and four puffs, each a picture of its own; one flame at a time is all it throws)
local function render_spit(e, cx, cy, cz)
    if not e.spool then
        if #e.sflames == 0 then return end
        local world = lib.world()
        local sx, sy, sz = to_scene(e.x, e.y, e.z)
        e.spool, e.ppool = {}, {}
        for i = 0, 7 do
            local q = lib.quad_actor(world, { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z }, 25.0 * S, "flame_sm64_red_" .. i, "translucent")
            if q then pcall(function() q:SetActorHiddenInGame(true) end) end
            e.fseed = e.fseed or math.random() * 6.28
            do local BU = package.loaded["burn"]; if BU and BU.fire3d_on and q then pcall(BU.fire3d_on, world, q, 25.0 * S, false, e.fseed) end end
            e.spool[i] = q or false
        end
        for i = 1, 4 do
            local q = lib.quad_actor(world, { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z }, 25.0 * S, "flame_sm64_red_" .. ((i * 3) % 8), "translucent")
            if q then pcall(function() q:SetActorHiddenInGame(true) end) end
            do local BU = package.loaded["burn"]; if BU and BU.fire3d_on and q then pcall(BU.fire3d_on, world, q, 25.0 * S, false, nil) end end
            e.ppool[i] = q or false
        end
    end
    local function place(q, x, y, z, k, kx, kz)
        local px, py, pz = to_scene(x, y, z)
        px, py, pz = px + OFFSET.X, py + OFFSET.Y, pz + OFFSET.Z
        local dx, dy, dz = cx - px, cy - py, cz - pz
        local yaw = math.deg(atan(dy, dx)) + 180.0
        local pitch = -math.deg(atan(dz, sqrt(dx * dx + dy * dy)))
        q:K2_TeleportTo({ X = px, Y = py, Z = pz }, { Pitch = pitch, Yaw = yaw, Roll = 0.0 })
        q:SetActorScale3D({ X = k, Y = kx, Z = kz })
    end
    local f = e.sflames[1]
    local frame = f and (floor(f.t / 2) % 8) or -1
    for i = 0, 7 do
        local q = e.spool[i]
        if q then
            pcall(function()
                if i == frame then
                    local k = math.max(0.05, f.s * SPIT_LOOK)
                    -- (bhv_small_piranha_flame_loop: drawn a little taller or wider each time, 15 a size up)
                    local r = math.random() - 0.5
                    place(q, f.x, f.y + 15.0 * f.sy * k, f.z, k, k * (1.0 - 0.2 * r), k * f.sy * (1.0 + 0.3 * r))
                    if e.sshown ~= i then q:SetActorHiddenInGame(false) end
                elseif i == e.sshown then
                    q:SetActorHiddenInGame(true)
                end
            end)
        end
    end
    e.sshown = frame
    local n = #e.puffs
    for i = 1, 4 do
        local q = e.ppool[i]
        local p = e.puffs[n - i + 1]
        if q then
            pcall(function()
                if p then
                    local k = math.max(0.05, p.s * SPIT_LOOK)
                    place(q, p.x, p.y, p.z, k, k, k)
                    if i > (e.pshown or 0) then q:SetActorHiddenInGame(false) end
                elseif i <= (e.pshown or 0) then
                    q:SetActorHiddenInGame(true)
                end
            end)
        end
    end
    e.pshown = math.min(n, 4)
end

-- Mr. I's iris (mr_i.inc.c bhv_mr_i_body_loop, mr_i_iris_geo): the eyeball is a picture facing the camera; its iris a
-- 100-unit square of its own on the eyeball's face, 100 out from its middle (100 up) along the way the eye looks - its
-- yaw, as it turns after him, and up or down at him - turned to look that way. It was never drawn: a white ball,
-- "his eye isnt facing the player correctly", 2026-10-19.
-- (Render 96's Mr. I: one 3D eyeball, its iris on it, its middle the model's own - drawn at his feet, half in what he
-- stands on, with the flat iris hanging over it on its own and his shots coming out above both: "mr I is bugged",
-- 2026-10-31. Put up where Mario 64's eyeball has its middle, a quarter bigger - Mario 64's picture is some 185 across,
-- Render 96's ball 150 - turned up or down at him as the flat iris was; the flat iris not drawn.)
M.EYE3D_K = 1.25
function M.mri_eye3d(e)
    local d = e.inst and e.inst.data
    if e.eye3d_of ~= d then
        e.eye3d_of, e.eye3d = d, false
        for _, p in ipairs((d and d.parts) or {}) do
            for _, sec in ipairs(p.sections or {}) do
                if sec.texture == "actors__mr_i_eyeball__eyeball.rgba32" then e.eye3d = true end
            end
        end
    end
    return e.eye3d
end
local function render_iris(e, a, m)
    local hide = e.action == "dying" or e.action == "gone"
    if M.mri_eye3d(e) then
        if e.iris and e.iris_shown then e.iris_shown = false; pcall(function() e.iris:SetActorHiddenInGame(true) end) end
        local sc = e.scale or 1.0
        e.gfx_y, e.gfx_y_eye = 100.0 * sc, true
        local k = (e.sk or sc) * M.EYE3D_K
        -- (not turned to the camera, as Mario 64's flat eyeball is - game.lua's BEHAVIOUR_BILLBOARDS: the 3D eye looked
        -- at his camera, not where Mr. I looks. Its parts put back in the model's own frame, once)
        if not e.eye3d_bb then
            e.eye3d_bb = true
            for _, p in ipairs(e.inst.data.parts or {}) do p.billboard = false end
            for _, c in ipairs(e.inst.comps or {}) do
                pcall(function()
                    c:SetAbsolute(false, false, false)
                    c.RelativeRotation = { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }
                end)
            end
            e.inst.bb_abs = nil
        end
        local pitch = 0.0
        if not hide then
            local pr = e.prev
            local x, y, z = pr[1] + (e.x - pr[1]) * a, pr[2] + (e.y - pr[2]) * a, pr[3] + (e.z - pr[3]) * a
            local dx, dz = m.x - x, m.z - z
            local up = ((m.feet or m.y) + 120.0) - (y + 100.0 * sc)
            pitch = math.deg(atan(up, math.max(sqrt(dx * dx + dz * dz), 1.0)))
        end
        -- (the model's front is its -X: a pitch up turns +X up, so the front up is the pitch down)
        pcall(function()
            e.inst.actor:K2_SetActorRotation({ Pitch = -pitch, Yaw = -e.yaw * 360.0 / 65536.0, Roll = 0.0 }, false)
            e.inst.actor:SetActorScale3D({ X = k, Y = k, Z = k })
        end)
        return
    elseif e.gfx_y_eye then
        e.gfx_y, e.gfx_y_eye = nil, nil
    end
    if not e.iris then
        if hide then return end
        local world = lib.world()
        local sx, sy, sz = to_scene(e.x, e.y, e.z)
        e.iris = lib.quad_actor(world, { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z }, 50.0 * S * (e.scale or 1.0),
            "actors__mr_i_iris__mr_i_iris_open.rgba16", "alpha") or false
        e.iris_shown = true
    end
    if not e.iris then return end
    if hide then
        if e.iris_shown then e.iris_shown = false; pcall(function() e.iris:SetActorHiddenInGame(true) end) end
        return
    end
    local sc = e.scale or 1.0
    local pr = e.prev
    local x, y, z = pr[1] + (e.x - pr[1]) * a, pr[2] + (e.y - pr[2]) * a, pr[3] + (e.z - pr[3]) * a
    local cy = y + 100.0 * sc                                   -- (the eyeball's middle)
    local hx, hz = sins(e.yaw), coss(e.yaw)
    local dx, dz = m.x - x, m.z - z
    local flat = sqrt(dx * dx + dz * dz)
    local up = ((m.feet or m.y) + 120.0) - cy
    local pitch = atan(up, math.max(flat, 1.0))                 -- (radians, up toward him)
    local cp, sp = math.cos(pitch), math.sin(pitch)
    local ix, iy, iz = x + hx * cp * 101.0 * sc, cy + sp * 101.0 * sc, z + hz * cp * 101.0 * sc
    local wx, wy, wz = to_scene(ix, iy, iz)
    -- (its face, the quad's -X side, out along the look: the actor's +X back into the eye)
    local lx, ly, lz = to_scene(hx * cp, sp, hz * cp)
    lx, ly, lz = lx / S, ly / S, lz / S                         -- (to_scene scales: back to a unit way)
    local yaw = math.deg(atan(-ly, -lx))
    local pit = -math.deg(math.asin(math.max(-1.0, math.min(1.0, lz))))
    pcall(function()
        e.iris:K2_TeleportTo({ X = wx + OFFSET.X, Y = wy + OFFSET.Y, Z = wz + OFFSET.Z }, { Pitch = pit, Yaw = yaw, Roll = 0.0 })
        if not e.iris_shown then e.iris_shown = true; e.iris:SetActorHiddenInGame(false) end
    end)
end

local THROWER_POOL = 16
local function render_thrower(e, cx, cy, cz)
    local world = lib.world()
    -- (the bouncing fireballs' too - LLL's jumping fire was drawn in the painted flames: "some fires dont have the right
    -- textures", "the jumping fire", 2026-10-19)
    local orig = e.t.k == "thrower" or e.t.k == "spout"
    local color = (e.bp2 == 1) and "blue" or "red"
    if not e.pool then
        if #e.flames == 0 then return end
        e.pool, e.shown_n, e.qframe = {}, 0, {}
        local sx, sy, sz = to_scene(e.x, e.y, e.z)
        for i = 1, (e.t.k == "spout") and 11 or THROWER_POOL do
            -- (one picture to a slot, for good: the flames move through the slots a frame at a time and so turn through
            -- the pictures. Swapped on the slots instead, the pictures not on one were held by Lua alone, freed by the
            -- engine, and a SetMaterial with a freed one brought the game down - 2026-10-17)
            local tex = (orig and "flame_sm64_" or "flame_") .. color .. "_" .. ((i - 1) % 8)
            local q = lib.quad_actor(world, { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z }, 25.0 * S,
                                     tex, orig and "translucent" or "alpha")
            if q then pcall(function() q:SetActorHiddenInGame(true) end) end
            do local BU = package.loaded["burn"]; if BU and BU.fire3d_on and q then pcall(BU.fire3d_on, world, q, 25.0 * S, color == "blue", nil) end end
            e.pool[i] = q or false
        end
    end
    local n = #e.flames
    for i = 1, #e.pool do
        local q = e.pool[i]
        local f = e.flames[n - i + 1]
        if q then
            pcall(function()
                if f then
                    local sx, sy, sz = to_scene(f.x, f.y, f.z)
                    sx, sy, sz = sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z
                    local dx, dy, dz = cx - sx, cy - sy, cz - sz
                    local yaw = math.deg(atan(dy, dx)) + 180.0
                    local pitch = -math.deg(atan(dz, sqrt(dx * dx + dy * dy)))
                    q:K2_TeleportTo({ X = sx, Y = sy, Z = sz }, { Pitch = pitch, Yaw = yaw, Roll = 0.0 })
                    q:SetActorScale3D({ X = math.max(f.sc, 0.05), Y = math.max(f.sc, 0.05), Z = math.max(f.sc, 0.05) })
                    if i > e.shown_n then q:SetActorHiddenInGame(false) end
                elseif i <= e.shown_n then
                    q:SetActorHiddenInGame(true)
                end
            end)
        end
    end
    e.shown_n = math.min(n, #e.pool)
end

-- A Lakitu's cloud (cloud.inc.c, CLOUD_BP_LAKITU_CLOUD at twice size): five mist puffs, two thirds of the cloud's size,
-- 25 out round him at his heading plus a fifth of a turn each, 11, 8, 12, 8, 9 up, all bobbing along (1, 1, 1) once
-- in 32 frames; billboards. Gone when he is. (He flew bare, 2026-10-15.)
local PUFF_UP = { 11, 8, 12, 8, 9 }
local function render_cloud(e, a, cx, cy, cz)
    if e.cloud == nil then
        e.cloud = {}
        local mist = H.actor_data and H.actor_data("mist")
        if not mist then return end
        local world = lib.world()
        local sx, sy, sz = to_scene(e.x, e.y, e.z)
        for i = 1, 5 do
            local p = lib.make_instance(world, mist, { X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z }, 0.0, e.cloud_s or 4.0 / 3.0)
            if p then p.moves = true; e.cloud[#e.cloud + 1] = p end
        end
    end
    local pr = e.prev
    local x, y, z = pr[1] + (e.x - pr[1]) * a, pr[2] + (e.y - pr[2]) * a, pr[3] + (e.z - pr[3]) * a
    local s = e.cloud_s or 4.0 / 3.0                -- (bhv_cloud_part_update: 2/3 of the cloud's size - Lakitu's 2, Fwoosh's 3)
    e.puff_t = (e.puff_t or 0) + 1
    for i, p in ipairs(e.cloud) do
        local k = i - 1
        local ang = e.yaw + 0x10000 // 5 * k
        local off = 2.0 * coss(0x800 * e.puff_t + 0x4000 * k) * s
        local sx, sy, sz = to_scene(x + 25.0 * s * sins(ang) + off, y + off + s * PUFF_UP[i], z + 25.0 * s * coss(ang) + off)
        sx, sy, sz = sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z
        local dx, dy, dz = cx - sx, cy - sy, cz - sz
        pcall(function()
            p.actor:K2_TeleportTo({ X = sx, Y = sy, Z = sz },
                { Pitch = -math.deg(atan(dz, sqrt(dx * dx + dy * dy))), Yaw = math.deg(atan(dy, dx)) + 180.0, Roll = 0.0 })
        end)
    end
end

local function cloud_gone(e)
    if e.cloud and not e.cloud_hidden then
        e.cloud_hidden = true
        for _, p in ipairs(e.cloud) do pcall(function() p.actor:SetActorHiddenInGame(true) end) end
    end
end

-- Wiggler's tail (wiggler_update_segments): segment 0 is the head; each next one stays 35 x his size behind the one
-- before, turning after it when it turns more than 45 degrees, kept on the floor; drawn with its walk, which runs with
-- his speed (0.06 x it). Gone with him.
-- Wiggler angry, his last phase: his yellow skin red - the two segment pictures his head and tail are drawn with,
-- swapped for red copies of them (textures/..._red: their hue turned 34 degrees down, made from the ROM's own; their
-- materials are shared, so all of him at once, his eyes, nose and flower as they were - the cut-out material has no
-- colour to tint by). Mario 64 keeps him yellow; the later games' angry Wiggler is red - "he doesnt turn red on last
-- phase", 2026-10-29.
M.WIGGLER_RED = { ["actors__wiggler__wiggler_segment_left_side.rgba16"] = "actors__wiggler__wiggler_segment_left_side_red.rgba16",
                  ["actors__wiggler__wiggler_segment_right_side.rgba16"] = "actors__wiggler__wiggler_segment_right_side_red.rgba16" }
function M.wiggler_red(e, on)
    if (e.red or false) == on then return end
    e.red = on
    local world = lib.world()
    local insts = { e.inst }
    for _, b in pairs(e.body or {}) do insts[#insts + 1] = b.inst end
    local done = {}
    for _, inst in ipairs(insts) do
        if inst and inst.data and inst.comps then
            for i, part in ipairs(inst.data.parts) do
                local comp = inst.comps[i]
                for _, sec in ipairs(part.sections or {}) do
                    local red = sec.texture and M.WIGGLER_RED[sec.texture]
                    if comp and red then
                        pcall(function()
                            if not comp:IsValid() then return end
                            local mat = comp:GetMaterial(sec.id)
                            if not (mat and mat:IsValid()) then return end
                            local key = mat:GetAddress()
                            if done[key] then return end
                            done[key] = true
                            local tex = lib.texture(world, on and red or sec.texture)
                            if tex and tex:IsValid() then
                                mat:SetTextureParameterValue(FName("SlateUI"), tex)
                                mat:SetTextureParameterValue(FName("BaseColorTexture"), tex)
                            end
                        end)
                    end
                end
            end
        end
    end
end

-- Wiggler beaten (wiggler_act_shrink): 20 frames still, then his shrink's sound and down from his size 4 to 1 by 0.1 a
-- frame, his tail drawn in with him; then the star (finish, kept) and he walks on, a little one, at sWigglerSpeeds' 2 a
-- frame after the athlete, harmless (Mario 64's cur_obj_become_intangible). Mario 64 then drops him through the floor
-- to below 1700; here he stays on the arena, in sight - "doesnt turn into a small wiggle after beating him", 2026-10-29.
function M.wiggler_shrink(e, m, world)
    local t = e.t
    e.timer = e.timer + 1
    e.fvel = 0.0
    if e.timer < 20 then return end
    if e.timer == 20 then sound(t.snd and t.snd.death, 1.0) end
    local k = max(1.0, (e.scale or 4.0) - 0.1)
    e.scale, e.sk = k, k
    pcall(function() if e.inst.actor:IsValid() then e.inst.actor:SetActorScale3D({ X = k, Y = k, Z = k }) end end)
    for _, b in pairs(e.body or {}) do
        pcall(function() if b.inst.actor:IsValid() then b.inst.actor:SetActorScale3D({ X = k, Y = k, Z = k }) end end)
    end
    if k <= 1.0 then
        e.small, e.chase_v, e.agility, e.action = true, 2.0, 0.4, "home"
        finish(e, m, world, "stomped", true)
        log("Wiggler shrunk: a little one now")
    end
end

local function render_wiggler_body(e, x, y, z)
    local segs = e.segs
    local hide = e.action == "dying" or e.action == "gone"
    if hide ~= e.body_hidden then
        e.body_hidden = hide
        for _, b in pairs(e.body) do pcall(function() b.inst.actor:SetActorHiddenInGame(hide) end) end
    end
    if hide then return end
    segs[0].x, segs[0].y, segs[0].z, segs[0].yaw, segs[0].pitch = x, y, z, e.yaw, 0
    local len = 35.0 * (e.scale or 1.0)
    for i = 1, 3 do
        local p, s = segs[i - 1], segs[i]
        local dx, dy, dz = s.x - p.x, s.y - p.y, s.z - p.z
        local dyaw = s16(atan2s(-dz, -dx) - p.yaw)
        if dyaw > 0x2000 then dyaw = 0x2000 elseif dyaw < -0x2000 then dyaw = -0x2000 end
        s.yaw = s16(p.yaw + dyaw)
        local dxz = sqrt(dx * dx + dz * dz)
        local dpitch = s16(atan2s(dxz, dy) - p.pitch)
        if dpitch > 0x2000 then dpitch = 0x2000 elseif dpitch < -0x2000 then dpitch = -0x2000 end
        s.pitch = s16(p.pitch + dpitch)
        s.y = len * sins(s.pitch) + p.y
        local h = len * coss(s.pitch)
        s.x, s.z = p.x - h * sins(s.yaw), p.z - h * coss(s.yaw)
        local fy = floor_y(s.x, s.y + 60.0, s.z)
        if fy and s.y < fy then s.y = fy end
        local b = e.body[i]
        if b then
            local bx, by, bz = to_scene(s.x, s.y, s.z)
            lib.set_pose(b.inst, bx + OFFSET.X, by + OFFSET.Y, bz + OFFSET.Z, -s.yaw * 360.0 / 65536.0)
            local data = b.inst.data
            if data.anims and data.anims[1] then pcall(lib.pose, b.inst, data.anims[1], (e.f or 0) + b.f) end     -- (the head's walk, a step apart)
            pcall(lib.face_camera, b.inst, bx + OFFSET.X, by + OFFSET.Y)
        end
    end
end

-- Boos drawn above where they are, as Mario 64 draws them (oGraphYOffset): the Boos 30, the castle's and the courtyard
-- cage-carrier 60, the Big Boos 60 times their size. Drawn where they were, the cage the courtyard Boo carries - which
-- stays where the Boo is - sat in the middle of its body, in front of its face ("faces still missing", 2026-10-22).
M.BOO_GFX_Y = { bhvBooInCastle = 60.0, bhvBooWithCage = 60.0, bhvGhostHuntBigBoo = "big", bhvBalconyBigBoo = "big",
                    bhvMerryGoRoundBigBoo = "big" }
local function render(e, a)
    local pr = e.prev
    local x, y, z = pr[1] + (e.x - pr[1]) * a, pr[2] + (e.y - pr[2]) * a, pr[3] + (e.z - pr[3]) * a
    -- (e.gfx_y: oGraphYOffset - Mr. Blizzard in the snow. Not e.gy: that is the ground under the pit balls, boulders and
    -- the snowman's body, and drawn on top of it they hung that high over it - the user: "bolders floating above the bowl")
    local gy = e.gfx_y
    if gy == nil and e.t.k == "boo" then
        gy = M.BOO_GFX_Y[e.type] or 30.0
        if gy == "big" then gy = 60.0 * (e.scale or e.t.scale or 3.0) end
    end
    local sx, sy, sz = to_scene(x, y + (gy or 0.0), z)
    lib.set_pose(e.inst, sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z, -e.yaw * 360.0 / 65536.0)
    if e.pitch then
        local p = (e.pp or e.pitch) + (e.pitch - (e.pp or e.pitch)) * a
        local r = -(e.roll or 0) * 360.0 / 65536.0
        local yw = -e.yaw * 360.0 / 65536.0
        -- (Bubba: one stiff piece with no animation - Mario 64's is as stiff, its mouth all that moves - so it sways as
        -- it swims, swung side to side and rolled a little, the more beached: "also no animations on him", 2026-10-29.
        -- Its open mouth takes the same turn.)
        if e.bb and e.bb.ph then
            local k = ((e.bb.beached or 0) > 0) and 2.0 or 1.0
            yw = yw + math.sin(e.bb.ph) * 7.0 * k
            r = r + math.sin(e.bb.ph - 0.8) * 4.0 * k
        end
        pcall(function() e.inst.actor:K2_SetActorRotation({ Pitch = p * 360.0 / 65536.0, Yaw = yw, Roll = r }, false) end)
    end
    local data = e.inst.data
    if data.anims and #data.anims > 0 then
        local t = e.t
        local i = e.anim_i or ((e.action == "chase" and t.anim.chase) or t.anim.walk or t.anim.idle or 0)
        local anim = data.anims[i + 1] or data.anims[1]
        -- (posed again only when its clip or frame has changed - they change in its steps, 30 a second: each part of each
        -- one was set again every frame, 0.4 ms of every frame for Whomp's Fortress's six - "when I entered the level it
        -- was 120 fps now its 80", 2026-11-05)
        if e.posed_anim ~= anim or e.posed_f ~= e.f or e.posed_inst ~= e.inst then
            e.posed_anim, e.posed_f, e.posed_inst = anim, e.f, e.inst
            pcall(lib.pose, e.inst, anim, e.f)
        end
    end
    if e.cloud_s then
        -- (Fwoosh's face in front of its puffs, toward the camera: bhv_cloud_part_update puts it out at the cloud's
        -- radius; the puffs are see-through mist, and from the side they hid it)
        pcall(function()
            local ccx, ccy, ccz = lib.camera_location({ X = sx + OFFSET.X, Y = sy + OFFSET.Y, Z = sz + OFFSET.Z })
            local dx, dy, dz = ccx - (sx + OFFSET.X), ccy - (sy + OFFSET.Y), ccz - (sz + OFFSET.Z)
            local d = sqrt(dx * dx + dy * dy + dz * dz)
            if d > 1.0 then
                local k = 25.0 * e.cloud_s * S * 1.2 / d
                e.inst.actor:K2_SetActorLocation({ X = sx + OFFSET.X + dx * k, Y = sy + OFFSET.Y + dy * k, Z = sz + OFFSET.Z + dz * k }, false, {}, true)
            end
        end)
    end
    pcall(lib.face_camera, e.inst, sx + OFFSET.X, sy + OFFSET.Y)
    if e.open then
        local open = e.bb.mouth ~= 0
        if open ~= e.open_shown then
            e.open_shown = open
            pcall(function() e.inst.actor:SetActorHiddenInGame(open) end)
            pcall(function() e.open.actor:SetActorHiddenInGame(not open) end)
        end
        if open then
            lib.set_pose(e.open, sx + OFFSET.X, sy + OFFSET.Y, sz + OFFSET.Z, -e.yaw * 360.0 / 65536.0)
            pcall(function() e.open.actor:K2_SetActorRotation(e.inst.actor:K2_GetActorRotation(), false) end)
        end
    end
    if e.held then
        local BO = package.loaded["bobomb"]
        if BO and BO.hold then pcall(BO.hold.place, e, lib.pawn(), sx, sy, sz, e.yaw, a) end
    end
    if e.type == "bhvToadMessage" and e.alpha then
        -- (a Toad: see-through materials while it is faded or fading - the opacity as a colour, sRGB - its own again once
        -- whole, as translucent parts do not sort against each other)
        if e.alpha >= 0.999 then
            if e.fade_mids then
                e.fade_mids, e.alpha_set = nil, nil
                local world = lib.world()
                for i, part in ipairs(e.inst.data.parts) do
                    local comp = e.inst.comps[i]
                    for _, sec in ipairs(part.sections or {}) do
                        local clamp = sec.texture and lib.CLAMP[sec.texture]
                        local mid = lib.get_mid(world, sec.layer, clamp and lib.clamp_file(sec.texture) or sec.texture)
                        if comp and mid then pcall(function() comp:SetMaterial(sec.id, mid) end) end
                    end
                end
            end
        else
            local f = 1.055 * e.alpha ^ (1.0 / 2.4) - 0.055
            if not e.fade_mids then e.fade_mids = lib.see_through(lib.world(), e.inst, f) or {}; e.alpha_set = f end
            if math.abs(f - (e.alpha_set or -1.0)) > 0.01 then
                e.alpha_set = f
                for _, mid in ipairs(e.fade_mids) do
                    pcall(function() mid:SetVectorParameterValue(FName("BaseColorFactor"), { R = 1.0, G = 1.0, B = 1.0, A = f }) end)
                end
            end
        end
    end
    if e.t.k == "boo" then pcall(M.boo_look, e, e.alpha or 1.0) end
    if e.segs then pcall(render_wiggler_body, e, x, y, z) end
    if e.pk then
        -- (the head on top of the stack, swaying with it)
        local ox, oz = pokey_sway(e, 0)
        local hx, hy, hz = to_scene(x + ox, y + pokey_h(e, 0), z + oz)
        lib.set_pose(e.inst, hx + OFFSET.X, hy + OFFSET.Y, hz + OFFSET.Z, -e.yaw * 360.0 / 65536.0)
        pcall(lib.face_camera, e.inst, hx + OFFSET.X, hy + OFFSET.Y)
        pcall(render_pokey, e, x, y, z)
    end
end

-- The athlete never left inside a Whomp's slab. Its collision is moved by teleporting it (walking, turning, falling
-- flat), so it could close round him - "im stuck in a thwomp" (2026-10-15, WF: it fell on him while he was still
-- unhurtable from a Piranha Plant, so nothing threw him out from under it). Mario 64 pushes Mario out of a moving
-- surface; here, whenever his body is inside the slab, he is put out through its nearest face (onto its back when it
-- lies flat), never down into the ground.
local SLAB = { x0 = 2.25, x1 = 75.0, y0 = -112.5, y1 = 112.5, z0 = 37.5, z1 = 322.5 }   -- (the slab, cm, its own frame)
local BODY_R, BODY_HALF = 15.0, 86.0    -- (his capsule)
local function out_of_slab(e, pawn)
    local pmc = e.slab
    if not (pmc and pmc:IsValid()) then return end
    local SQ = package.loaded["squish"]
    if SQ and SQ.active and SQ.active() then return end          -- (squished under it: held there till it stands up)
    local c = pawn:K2_GetActorLocation()
    local o, f, r, u, sc = pmc:K2_GetComponentLocation(), pmc:GetForwardVector(), pmc:GetRightVector(), pmc:GetUpVector(), pmc:K2_GetComponentScale()
    local s = math.max(0.01, sc.X)
    -- (only truly inside: his middle 5 cm and more in. With 15 cm round him counted too, standing against it or on its
    -- back he was put out a centimetre at a time, every step - and a jump onto its back never landed, 2026-10-17. Its
    -- faces wound outward now, its own collision keeps him out.)
    local pad = -5.0 / s
    -- for each face (its own frame: axis, sign, bound): how far to move him for every point of him to be out that way
    local faces = { { "x", -1, SLAB.x0 }, { "x", 1, SLAB.x1 }, { "y", -1, SLAB.y0 }, { "y", 1, SLAB.y1 }, { "z", -1, SLAB.z0 }, { "z", 1, SLAB.z1 } }
    local need, inside = { 0, 0, 0, 0, 0, 0 }, false
    for _, k in ipairs({ -1.0, -0.5, 0.0, 0.5, 1.0 }) do
        local dx, dy, dz = c.X - o.X, c.Y - o.Y, c.Z + k * (BODY_HALF - BODY_R) - o.Z
        local l = { x = (dx * f.X + dy * f.Y + dz * f.Z) / s, y = (dx * r.X + dy * r.Y + dz * r.Z) / s, z = (dx * u.X + dy * u.Y + dz * u.Z) / s }
        if l.x > SLAB.x0 - pad and l.x < SLAB.x1 + pad and l.y > SLAB.y0 - pad and l.y < SLAB.y1 + pad
           and l.z > SLAB.z0 - pad and l.z < SLAB.z1 + pad then
            inside = true
            for i, fc in ipairs(faces) do
                local d = fc[2] > 0 and (fc[3] + pad - l[fc[1]]) or (l[fc[1]] - (fc[3] - pad))
                if d > need[i] then need[i] = d end
            end
        end
    end
    if not inside then return end
    local best, bd = nil, math.huge
    for i, fc in ipairs(faces) do
        local ax = fc[1] == "x" and f or (fc[1] == "y" and r or u)
        local wz = ax.Z * fc[2]
        if wz > -0.5 and need[i] < bd then best, bd = i, need[i] end
    end
    if not best then return end
    local fc = faces[best]
    local ax = fc[1] == "x" and f or (fc[1] == "y" and r or u)
    local m = (bd + 1.0) * s * fc[2]
    pawn:K2_TeleportTo({ X = c.X + ax.X * m, Y = c.Y + ax.Y * m, Z = c.Z + ax.Z * m }, pawn:K2_GetActorRotation())
    if not e.slab_said or os.clock() - e.slab_said > 2.0 then
        e.slab_said = os.clock()
        log("whomp: the athlete was inside its slab - put out %.0f cm (%s%s face)", bd * s, fc[2] > 0 and "+" or "-", fc[1])
    end
end

-- Time stopped by a message (no steps): only their camera-facing parts turned to the camera (as bobomb.lua's)
function M.reface()
    for _, e in ipairs(M.list) do
        if e.inst and e.action ~= "gone" then
            local sx, sy = to_scene(e.x, e.y, e.z)
            pcall(lib.face_camera, e.inst, sx + OFFSET.X, sy + OFFSET.Y)
            -- (face_camera only writes the parts' rotation; the actor's move applies it - and in a message nothing
            -- moves, so the turn never showed: King Bob-omb squashed edge-on in his talk, 2026-10-16. Nudged in place.)
            pcall(function()
                local l = e.inst.actor:K2_GetActorLocation()
                lib.set_pose(e.inst, l.X, l.Y, l.Z - (e.inst.nudge or 0.0), e.inst.yaw or 0.0)
            end)
        end
    end
end

-- BBH's staircase (big_boo_act_4 spawning bhvBooStaircase): three steps added to the platforms, at the Big Boo's spot
-- (973, 0, 717) and 200 either side
function M.stairs_tick(m, world)
    local s = M.boo_stairs
    s.t = s.t + 1
    if s.t <= 60 then return end
    local dx, dy, dz = m.x - 973.0, m.y, m.z - 626.0
    if dx * dx + dy * dy + dz * dz > 600.0 * 600.0 then return end
    M.boo_stairs = nil
    local PL, G = package.loaded["platforms"], package.loaded["game"]
    local templates = G and G.data and G.data.templates
    if not (PL and PL.add and templates and world) then return end
    for _, st in ipairs({ { 0, 717.0 }, { 1, 517.0 }, { 2, 917.0 } }) do
        local o = { kind = "platform", bhv = "boo_stairs", tpl = "geo_bbh_0005B0|bbh_seg7_collision_staircase_step",
                    pos = { 973.0, 0.0, st[2] }, ang = { 0, 0, 0 }, bp = st[1] << 16 }
        local ok, err = pcall(PL.add, world, o, templates)
        if not ok then log("BBH staircase: %s", tostring(err)) end
    end
    log("BBH: the staircase comes up")
end

-- Mario 64's rooms (rooms.lua): in Big Boo's Haunt, the castle and Hazy Maze Cave these take the room of the floor
-- under where they start (bhv_init_room). A Boo is there only with Mario in its very room (boo_should_be_active) and is
-- back at its place when it comes again; the others stand still and out of sight while he is not in their room or one
-- through a door from it (cur_obj_enable_rendering_if_mario_in_room). Before, the balcony's Big Boo came down through the
-- ceiling after him in the hall below (2026-10-18).
M.ROOMED = { bhvBoo = "boo", bhvBooInCastle = "boo", bhvBooWithCage = "boo", bhvGhostHuntBigBoo = "boo", bhvGhostHuntBoo = "boo",
             bhvBalconyBigBoo = "boo", bhvMrI = "near", bhvScuttlebug = "near", bhvSwoop = "near", bhvFlyGuy = "near",
             bhvSnufit = "near", bhvHauntedChair = "near", bhvMadPiano = "near", bhvFlyingBookend = "near" }
function M.room_away(e)
    local how = M.ROOMED[e.type]
    if not how then return false end
    local R = package.loaded["rooms"]
    local G = package.loaded["game"]
    if not (R and G and G.name and R.has(G.name)) then return false end
    if e.room == nil then
        -- (this runs outside the steps' pcall: nothing here may throw)
        local ok, r = pcall(function()
            local sx, sy, sz = to_scene(e.hx or e.x, e.hy or e.y, e.hz or e.z)
            return R.at(G.name, sx, sy, sz + 10.0)
        end)
        e.room = (ok and r) or 0
    end
    local away = not ((how == "boo") and R.same(e.room) or (how ~= "boo" and R.with_mario(e.room)))
    if away ~= (e.room_hid or false) then
        e.room_hid = away or nil
        -- (Mario 64 puts a Boo back at its place when he leaves its room (boo_act_0) - and its room 10's whenever he
        -- opens a door - but here it waits where it is, out of sight, and goes on from there when he is back: every door
        -- he opened snapped the Boo upstairs back to its place - "everytime the door triggers the boo teleports back to
        -- where he spawns", 2026-10-22. One beaten, or not yet out - the hall's Big Boo before its five - stays unseen.)
        local hide = away or e.action == "gone" or e.action == "waiting"
        if e.inst then pcall(function() e.inst.actor:SetActorHiddenInGame(hide) end) end
    end
    return away
end

-- A Boo drawn solid, as exported, or see-through while it fades (game.lua G.boo_body_first: each section twice, solid
-- and see-through, its body in one part and its face in another): the see-through sections given their materials once,
-- when it is first drawn, and kept; after that only which set is shown changes. The face is drawn after the body: its
-- white as faint as the body, then the eyes and mouth over it at five times that: at a hiding Boo's 40 of 255 its dark
-- eyes and mouth were lost in the body's white ("his face is missing while invis", "you didnt fix the face still????",
-- 2026-10-22).
function M.boo_look(e, a)
    local inst = e.inst
    local parts = inst and inst.data and inst.data.parts
    if not (parts and inst.comps and inst.data.boo_split) then return end
    local fading = a < 0.99
    if not e.boo_mids then
        -- (one see-through material for the body, one for each picture of the face, put on their sections for good)
        e.boo_mids = { body = {}, face = {}, base = {} }
        local world = lib.world()
        local parent = lib.try_load("/InterchangeAssets/gltf/MaterialInstances/MI_Unlit_Blend.MI_Unlit_Blend")
        local KML = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
        local made = {}
        for pi, part in ipairs(parts) do
            local comp = inst.comps[pi]
            for _, sec in ipairs(part.sections or {}) do
                if comp and parent and sec.boo_role == "see_through" then
                    local key = pi .. "|" .. tostring(sec.texture) .. (sec.boo_base and "|base" or "")
                    local mid = made[key]
                    if not mid then
                        pcall(function()
                            mid = KML:CreateDynamicMaterialInstance(world, parent, FName(string.format("SM64Boo_%d_%d", os.time(), math.random(1, 1e9))), 0)
                            if sec.texture then
                                -- (the base: the picture over white, made once beside it as "<name>.base.png")
                                local file = lib.clamp_file(sec.texture)
                                local tex = lib.texture(world, sec.boo_base and (file .. ".base") or file)
                                if tex then mid:SetTextureParameterValue(FName("BaseColorTexture"), tex) end
                            end
                        end)
                        made[key] = mid
                        if mid then
                            local list = (pi == 1) and e.boo_mids.body or (sec.boo_base and e.boo_mids.base or e.boo_mids.face)
                            list[#list + 1] = mid
                        end
                    end
                    if mid then pcall(function() comp:SetMaterial(sec.id, mid) end) end
                end
            end
        end
        if inst.comps[2] then pcall(function() inst.comps[2]:SetTranslucentSortPriority(1) end) end
        e.alpha_set = nil
    end
    local mode = fading and "fading" or "solid"
    if e.boo_mode ~= mode then
        e.boo_mode = mode
        for pi, part in ipairs(parts) do
            local comp = inst.comps[pi]
            for _, sec in ipairs(part.sections or {}) do
                if comp and sec.boo_role then
                    pcall(function() comp:SetMeshSectionVisible(sec.id, (sec.boo_role == "see_through") == fading) end)
                end
            end
        end
    end
    if fading and math.abs(a - (e.alpha_set or -1.0)) > 0.01 then
        e.alpha_set = a
        for _, list in ipairs({ e.boo_mids.body, e.boo_mids.base or {} }) do
            for _, mid in ipairs(list) do
                pcall(function() mid:SetVectorParameterValue(FName("BaseColorFactor"), { R = 1.0, G = 1.0, B = 1.0, A = a }) end)
            end
        end
        local fa = math.min(1.0, a * 5.0)
        for _, mid in ipairs(e.boo_mids.face) do
            pcall(function() mid:SetVectorParameterValue(FName("BaseColorFactor"), { R = 1.0, G = 1.0, B = 1.0, A = fa }) end)
        end
    end
end

-- The ending's credits: its camera, often far from him - he stands aside, out of the picture: in THI's shot 68 m off,
-- in CCM's last 58 m - and the creatures it looks at were neither stepped nor drawn, so stood in the shape they are made
-- in, unposed: the penguin's feet off his body, THI's goombas on their sides, CCM's snowman - "penguin goombas and
-- snowman messed up during outro", 2026-11-02. Then those within VIEW_NEAR of the camera (Mario 64's units) go on as if
-- near him, drawn every frame. (view: the camera's place, in M.update; nil out of the ending)
M.VIEW_NEAR = 15000.0
function M.near_view(e, v)
    local dx, dy, dz = v.x - e.x, v.y - e.y, v.z - e.z
    return dx * dx + dy * dy + dz * dz < M.VIEW_NEAR * M.VIEW_NEAR
end

function M.update(dt, px, py, pz)
    do local SH = package.loaded["shock"]; if SH and SH.active then pcall(SH.tick, dt) end end     -- (an Amp's shock)
    if #M.list == 0 and #M.shots == 0 then return end
    local world = lib.world()
    local pawn = lib.pawn()
    local sx, sy, sz = px - OFFSET.X, py - OFFSET.Y, pz - OFFSET.Z
    local m = { x = sy / S, y = sz / S, z = -sx / S }
    m.feet = m.y - 120.0
    local view = nil
    do
        local EN = package.loaded["ending"]
        if EN and EN.active then
            local okc, vx, vy, vz = pcall(lib.camera_location, { X = px, Y = py, Z = pz })
            if okc and vx and vy and vz then
                local qx, qy, qz = vx - OFFSET.X, vy - OFFSET.Y, vz - OFFSET.Z
                view = { x = qy / S, y = qz / S, z = -qx / S }
            end
        end
    end
    m.facing = 0
    pcall(function() m.facing = s16((180.0 - pawn:K2_GetActorRotation().Yaw) * 65536.0 / 360.0) end)    -- (he faces +X)
    m.falling = false
    pcall(function() m.falling = pawn.CharacterMovement:IsFalling() and pawn:GetVelocity().Z < -50.0 end)
    pcall(function() m.air = pawn.CharacterMovement:IsFalling() end)
    pcall(function() m.mode = pawn.CharacterMovement.MovementMode end)
    pcall(function() local v = pawn:GetVelocity(); m.speed = sqrt(v.X * v.X + v.Y * v.Y) end)
    -- (him down - knocked flat, limp, or on his way up: when, for a Chuckya's grab (M.REGRAB_GRACE), and where his body
    -- lies, m.body, for a Heave-Ho's toss (touch) - his capsule stays where he went down)
    do
        local G = package.loaded["game"]
        local RG = package.loaded["ragdoll"]
        local down = (G and G.getup_at) and true or false
        if not down and RG and RG.limp then
            local okl, l = pcall(RG.limp)
            down = (okl and l) and true or false
        end
        if not down and pawn then
            pcall(function()
                local mt = pawn.Mesh:GetAnimInstance():GetCurrentActiveMontage()
                if mt and mt:IsValid() then
                    local nm = mt:GetFName():ToString()
                    if nm:find("Getup") or nm:find("Ragdoll") then down = true end
                end
            end)
        end
        if down then
            M.down_at = os.clock()
            if pawn then
                pcall(function()
                    local pv = pawn.Mesh:GetSocketLocation(FName("pelvis"))
                    local bx, by, bz = pv.X - OFFSET.X, pv.Y - OFFSET.Y, pv.Z - OFFSET.Z
                    local b = {}
                    for k, v in pairs(m) do b[k] = v end
                    b.x, b.z, b.feet = by / S, -bx / S, bz / S - 30.0
                    b.y = b.feet + 120.0
                    m.body = b
                end)
            end
        end
    end
    local attack = pawn and attack_of(pawn) or nil
    if attack ~= nil and attack.addr ~= last_attack then pending = attack end
    last_attack = attack and attack.addr or nil
    acc = acc + dt
    for _, e in ipairs(M.list) do
        if e.held then
            local BO = package.loaded["bobomb"]
            if BO and BO.hold then BO.hold.set_dt(dt) end
            break
        end
    end
    local n = 0
    while acc >= STEP and n < 4 do
        acc = acc - STEP
        n = n + 1
        if M.boo_stairs then pcall(M.stairs_tick, m, world) end
        for _, e in ipairs(M.list) do
            e.prev[1], e.prev[2], e.prev[3] = e.x, e.y, e.z
            e.pp = e.pitch
            local dx, dy, dz = m.x - e.x, m.y - e.y, m.z - e.z
            m.dist = sqrt(dx * dx + dy * dy + dz * dz)
            m.angle = s16(atan2s(dz, dx))
            if e.touch_cool and e.touch_cool > 0 then e.touch_cool = e.touch_cool - 1 end
            if e.action == "dying" then
                e.timer = e.timer + 1
                -- (one made without a size of its own - Lakitu's Spiny - at its own size: beaten by a thrown box, its
                -- squash failed every frame and stopped every creature after it in the list, 2026-11-02)
                local sk = e.sk or e.scale or 1.0
                local k = max(0.05, 1.0 - e.timer / 10.0) * sk
                pcall(function() e.inst.actor:SetActorScale3D({ X = sk, Y = sk, Z = k }) end)
                if e.timer >= 10 then
                    e.action = "gone"
                    pcall(function() e.inst.actor:SetActorHiddenInGame(true) end)
                end
            elseif e.action == "waiting" and e.minions_left then
                -- (the big bully with minions: dropped in 90 frames after the last of them, the puzzle jingle first)
                if e.minions_left <= 0 then
                    e.release = (e.release or 0) + 1
                    if e.release == 1 then sound("puzzle_jingle", 1.0) end
                    if e.release > 90 then
                        e.action, e.vy, e.ground = "home", 0.0, false
                        -- (its home now the platform it lands on: 1500 under its place up high read as knocked off)
                        local fy = floor_y(e.x, e.y, e.z)
                        if fy then e.hy = fy end
                        pcall(function() e.inst.actor:SetActorHiddenInGame(false) end)
                        log("the big bully drops in")
                    end
                end
            elseif e.action == "waiting" then
                -- a Big Boo that comes out once its five Boos are beaten (big_boo_act_0)
                if (M.boos_beaten[e.t.waits] or 0) >= 5 then
                    e.action = "home"
                    pcall(function() e.inst.actor:SetActorHiddenInGame(false) end)
                    sound("puzzle_jingle", 1.0)
                    log("the Big Boo comes out")
                end
            elseif e.action == "gone" then
                -- back once he is far away (bosses, counted Boos and Lakitu's spinies stay beaten)
                local hx, hz = m.x - e.hx, m.z - e.hz
                -- (and no Boo: Mario 64's Boos make no respawner - only Bob-ombs, small boxes, the snowman and Yoshi do -
                -- and BBH's came back after every door, 3000 being one room off: "ghost respawning everytime door opens",
                -- 2026-10-22)
                if not e.t.boss and not e.t.stay and not e.stay and not e.from and e.t.k ~= "boo" and hx * hx + hz * hz > 3000.0 * 3000.0 then
                    e.x, e.y, e.z, e.action, e.hp, e.timer = e.hx, e.hy, e.hz, "home", e.t.hits or 1, 0
                    if e.bare then pcall(M.koopa_shell_on, e, world) end          -- (a Koopa back in his shell)
                    -- (a Pokey back whole, all his parts on: "make sure when the pokey respawns he has his spike balls",
                    -- 2026-10-20)
                    if e.pk then e.pk.n, e.pk.bottom, e.pk.regrow, e.pk.hit_cool = 5, 1.0, 0, 0 end
                    pcall(function() e.inst.actor:SetActorScale3D({ X = e.sk, Y = e.sk, Z = e.sk }) end)
                    pcall(function() e.inst.actor:SetActorHiddenInGame(false) end)
                end
            elseif e.action == "words" then
                e.f = e.f + 1.0                         -- (still, until his last words are read)
                if e.words_due then pcall(words_tick, e, m) end
            elseif e.action == "shrink" then
                local oks, errs = pcall(M.wiggler_shrink, e, m, world)          -- (Wiggler beaten, getting little)
                if not oks and not e.broken_s then e.broken_s = true; log("wiggler shrink: %s", tostring(errs)) end
            elseif M.room_away(e) then
                -- (in another room than his: still, and out of sight)
            elseif m.dist < 6000.0 or (view and M.near_view(e, view)) or e.t.afar or e.balls or e.t.k == "ktq" or e.carried or e.t.k == "snow_body" or e.t.k == "ring" or e.t.k == "manta" or e.t.k == "boulder" or e.t.k == "wbomb" or e.t.k == "cage_ukiki" or e.t.k == "sushi" or e.t.k == "mole" then  -- (KTQ races on, far or near; a carried penguin goes with him)         -- (a ball spawner's balls roll down to him from afar)
                e.timer = e.timer + 1
                if e.t.words and not e.broken_w then
                    local okw, errw = pcall(words_tick, e, m)
                    if not okw then e.broken_w = true; log("enemy %s words: %s", e.type, tostring(errw)) end
                end
                if e.t.boss_tune and not e.tuned and not M.boss_music and m.dist < (e.t.range or 1500.0)
                    and math.abs(m.y - e.y) < 800.0 then
                    e.tuned = true
                    pcall(boss_music, true)
                end
                local fn = STEPS[e.t.k]
                local ok, err = pcall(fn, e, m, pawn, world)
                if not ok and not e.broken then e.broken = true; log("enemy %s: %s", e.type, tostring(err)) end
                if pawn then
                    local okt, errt = pcall(touch, e, m, pawn, pending or attack, pending ~= nil, world)
                    if not okt and not e.broken_t then e.broken_t = true; log("enemy %s touch: %s", e.type, tostring(errt)) end
                end
            end
        end
        pcall(step_shots, m, pawn)
        if pawn and M.ship_warp then pcall(M.ship_warp, m, pawn) end
        for _, c in ipairs(M.cages) do pcall(step_cage, c, m) end
        for i = #M.list, 1, -1 do
            local e = M.list[i]
            if e.dead then
                if e.inst then lib.destroy(e.inst.actor) end
                table.remove(M.list, i)
            end
        end
        pending = nil
    end
    if acc > STEP then acc = 0.0 end
    local a = acc / STEP
    local SFX = sfx()
    local cx, cy, cz = lib.camera_location({ X = px, Y = py, Z = pz })
    for _, e in ipairs(M.list) do
        if e.action ~= "gone" and e.action ~= "waiting" and not e.broken and not e.room_hid then
            local dx, dz = m.x - e.x, m.z - e.z
            local d2 = dx * dx + dz * dz
            if e.nomodel then
                -- (nothing to draw)
            elseif e.balls then
                for _, b in ipairs(e.balls) do
                    if SFX and SFX.hold then SFX.hold("loop_snow_roll", loudness(b, m, 3000.0)) end
                    local gy = b.gy and (b.pgy and (b.pgy + (b.gy - b.pgy) * a) or b.gy) or b.y
                    local bx, by, bz = b.px and (b.px + (b.x - b.px) * a) or b.x, gy, b.pz and (b.pz + (b.z - b.pz) * a) or b.z
                    local sx2, sy2, sz2 = to_scene(bx, by + 128.0 * e.size, bz)
                    pcall(lib.set_pose, b.inst, sx2 + OFFSET.X, sy2 + OFFSET.Y, sz2 + OFFSET.Z, 0.0)
                    pcall(lib.face_camera, b.inst, sx2 + OFFSET.X, sy2 + OFFSET.Y)
                end
            elseif e.thrower then
                pcall(render_thrower, e, cx, cy, cz)
                if e.act == 1 and SFX and SFX.hold and d2 < 3000.0 * 3000.0 then SFX.hold("loop_fire", loudness(e, m, 3000.0)) end
            elseif e.quads then
                if d2 < 9000.0 * 9000.0 then pcall(render_flame, e, cx, cy, cz) end
            elseif d2 < 9000.0 * 9000.0 or (view and M.near_view(e, view)) then
                -- (far ones drawn every M.LOD_EVERY frames - their moves are Mario 64's 30 a second all the same: the
                -- creatures took 1 ms of every frame, "just in general" laggy, 2026-10-31)
                -- (and up or down from him too, the Bowser run's level a tower; over M.LOD_FAR2, every M.LOD_EVERY_FAR -
                -- "I want a significant boost in fps", 2026-11-03)
                e.lod_n = (e.lod_n or 0) + 1
                local ldy = m.y - (e.y or m.y)
                local d3 = d2 + ldy * ldy
                local every = (d3 > M.LOD_FAR2) and M.LOD_EVERY_FAR or M.LOD_EVERY
                if d3 < M.LOD_NEAR2 or e.lod_n >= every or view then
                    e.lod_n = 0
                    pcall(render, e, a)
                end
                if e.sflames then pcall(render_spit, e, cx, cy, cz) end
                if e.type == "bhvMrI" then pcall(render_iris, e, a, m) end
                if e.slab and pawn and e.action ~= "dying" and d2 < 800.0 * 800.0 then pcall(out_of_slab, e, pawn) end
                -- (beaten, its body is no longer there to stand on or bump into: "make sure when he dies the collision
                -- disappears with him", 2026-10-17)
                if e.slab and not e.slab_off and (e.action == "dying" or e.action == "gone") then
                    e.slab_off = true
                    local pmc = e.slab
                    pcall(function() if pmc:IsValid() then pmc:SetCollisionEnabled(0) end end)
                end
                if e.t.k == "lakitu" or e.t.k == "fwoosh" then
                    if e.action == "dying" then cloud_gone(e) else pcall(render_cloud, e, a, cx, cy, cz) end
                end
            end
            if e.t.snd and e.t.snd.loop and SFX and SFX.hold and d2 < 3000.0 * 3000.0 and e.action ~= "dying" then
                SFX.hold(e.loop_name or e.t.snd.loop, loudness(e, m, 2500.0))      -- (loop_name: its own player, sfx.lua M.tune)
            end
        end
    end
    for _, e in ipairs(M.list) do
        if e.cloud and (e.action == "gone" or e.broken) then cloud_gone(e) end
        if e.wpool then pcall(render_wind_puffs, e, cx, cy, cz) end
    end
    for _, c in ipairs(M.cages) do
        local sx2, sy2, sz2 = to_scene(c.x, c.y, c.z)
        pcall(lib.set_pose, c.inst, sx2 + OFFSET.X, sy2 + OFFSET.Y, sz2 + OFFSET.Z, 0.0)
    end
    for _, e in ipairs(M.list) do
        if e.cage and e.action ~= "gone" then
            local sx2, sy2, sz2 = to_scene(e.x, e.y, e.z)
            pcall(lib.set_pose, e.cage, sx2 + OFFSET.X, sy2 + OFFSET.Y, sz2 + OFFSET.Z, -e.yaw * 360.0 / 65536.0)
        end
    end
    for _, s in ipairs(M.shots) do
        if s.inst then
            local sx2, sy2, sz2 = to_scene(s.x, s.y, s.z)
            pcall(function() s.inst.actor:K2_TeleportTo({ X = sx2 + OFFSET.X, Y = sy2 + OFFSET.Y, Z = sz2 + OFFSET.Z }, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }) end)
            pcall(lib.face_camera, s.inst, sx2 + OFFSET.X, sy2 + OFFSET.Y)
        end
        if s.quad then
            -- (a flame: facing the camera, at the Fly Guy's 2.5 times a small flame's size - obj_spit_fire's scale, its
            -- full size, about as big as the Fly Guy: at the spitters' 0.45 of it, "the fire is very very small",
            -- 2026-10-27 - its picture the next of eight every two frames)
            pcall(function()
                local sx2, sy2, sz2 = to_scene(s.x, s.y, s.z)
                local px, py, pz = sx2 + OFFSET.X, sy2 + OFFSET.Y, sz2 + OFFSET.Z
                local dx, dy, dz = cx - px, cy - py, cz - pz
                local yaw = math.deg(atan(dy, dx)) + 180.0
                local pitch = -math.deg(atan(dz, sqrt(dx * dx + dy * dy)))
                s.quad:K2_TeleportTo({ X = px, Y = py, Z = pz }, { Pitch = pitch, Yaw = yaw, Roll = 0.0 })
                local k = 2.5
                if not s.sized then s.sized = true; s.quad:SetActorScale3D({ X = k, Y = k, Z = k }) end
                local frame = floor((120 - s.life) / 2) % 8
                if frame ~= s.frame then
                    s.frame = frame
                    local mesh = s.quad:GetComponentByClass(StaticFindObject("/Script/ProceduralMeshComponent.ProceduralMeshComponent"))
                    local mid = lib.get_mid(lib.world(), "translucent", "flame_sm64_red_" .. frame)
                    if mesh and mid then mesh:SetMaterial(0, mid) end
                end
            end)
        end
    end
end

-- A water bomb fired from a cannon (water_bomb_cannon.inc.c bhv_bubble_cannon_barrel_loop, platforms.lua
-- B.wbomb_cannon): from (x, y, z) along yaw at fvel, vy up (Mario 64 units); then as any water bomb
-- A bob-omb gone off at (x, y, z) - Mario 64 units - its blast `r` round (bobomb.lua blast): a Pokey in it, any part of
-- him, is blown apart at once ("throwing a bombomb at pokeys should insta kill them", 2026-10-20). How many.
function M.blast_at(x, y, z, r)
    local world, n = lib.world(), 0
    for _, e in ipairs(M.list) do
        if e.pk and e.action ~= "dying" and e.action ~= "gone" then
            local dx, dz = x - e.x, z - e.z
            local top = e.y + pokey_h(e, 0) + POKEY_LIFT
            if dx * dx + dz * dz < (r + 90.0) ^ 2 and y > e.y - r and y < top + r then
                pcall(beaten, e, { x = x, y = y, z = z, facing = 0, dist = 0.0 }, world, "blown up")
                log("Pokey blown up by a bob-omb")
                n = n + 1
            end
        end
    end
    return n
end

-- Hit by something thrown (boxes.lua's small box, 2026-10-17: "when you throw it at enemies or boxes they dont break
-- die"): every enemy a hit beats within `reach` of (x, y, z) - Mario units - its body's own size added: beaten as by a
-- punch (a bully knocked away the way it flew, `yaw`). m: the athlete (for how loud). How many it hit.
function M.hit_at(x, y, z, reach, yaw, m)
    local world, n = lib.world(), 0
    for _, e in ipairs(M.list) do
        local t = e.t
        if t and e.action ~= "dying" and e.action ~= "gone" and (t.beat or t.bully) and (t.r or 0) > 0 and not e.unagi
           and not (t.k == "boo" and ((e.alpha or 1.0) < 0.5 or e.boo_hit or abs(s16(s16(atan2s(z - e.z, x - e.x)) - e.yaw)) <= 0x4000)) then
            local s = t.hit_s or e.scale or 1.0
            local h = (t.h or 100.0) * s
            local base = e.y
            if t.k == "flyer" or t.k == "boo" or t.k == "amp" or t.k == "lakitu" then base = e.y - (t.h or 100.0) * 0.4 end
            local dx, dz = x - e.x, z - e.z
            local r = t.r * s + reach
            if dx * dx + dz * dz < r * r and y > base - reach and y < base + h + reach then
                n = n + 1
                if t.bully then
                    e.yaw, e.fvel, e.vy, e.knocked, e.ground = yaw or e.yaw, 45.0, 25.0, true, false
                    sound(t.snd and t.snd.hit, loudness(e, m or e))
                else
                    pcall(beaten, e, m or { x = x, y = y, z = z, facing = yaw or 0 }, world, "hit")
                end
                log("%s hit by a thrown box", e.type)
            end
        end
    end
    return n
end

function M.launch_wbomb(world, x, y, z, yaw, fvel, vy)
    local data = H.actor_data and H.actor_data("geo_water_bomb_geo")
    if not (data and world) then return nil end
    local inst = instance(world, data, x, y, z, 0, 1.0)
    if not inst then return nil end
    local b = { t = T.WaterBomb, type = "WaterBomb", o = { bp = 0 }, inst = inst, x = x, y = y, z = z, hx = x, hy = y, hz = z,
                yaw = yaw, timer = 0, f = 0, action = "drop", hp = 1, scale = 1.0, sk = 1.0, vy = vy, fvel = fvel, bounces = 0,
                stretch = 0.0 }
    b.prev = { x, y, z }
    M.list[#M.list + 1] = b
    return b
end

return M
