"""Mario 64's enemies, for the mod's enemies.lua (asked 2026-10-14: "work on adding all the enemies to the game").

Each enemy the level places (by its level script or its macro objects) becomes a scene object
    {kind="enemy", type=<behaviour>, pos, sm64, yaw, geo, scale, bp}
and each model they use is exported once as actor "geo_<geo name>" with the animations its behaviour script loads
(LOAD_ANIMATIONS). How each behaviour moves and fights is the game's side (Scripts/enemies.lua)."""
import os, re
import sm64x as X

# the behaviours enemies.lua knows (behaviour -> the model it uses when the level does not say)
ENEMY_BHVS = {
    'bhvScuttlebug': 'MODEL_SCUTTLEBUG', 'bhvSpindrift': 'MODEL_SPINDRIFT', 'bhvSmallBully': 'MODEL_BULLY',
    'bhvBigBully': 'MODEL_BULLY_BOSS', 'bhvBigBullyWithMinions': 'MODEL_BULLY_BOSS', 'bhvChuckya': 'MODEL_CHUCKYA',
    'bhvHeaveHo': 'MODEL_HEAVE_HO', 'bhvKoopa': 'MODEL_KOOPA_WITH_SHELL', 'bhvPokey': 'MODEL_POKEY_HEAD',
    'bhvUkiki': 'MODEL_UKIKI', 'bhvMontyMole': 'MODEL_MONTY_MOLE', 'bhvMrBlizzard': 'MODEL_MR_BLIZZARD',
    'bhvSkeeter': 'MODEL_SKEETER', 'bhvFlyGuy': 'MODEL_FLYGUY', 'bhvSwoop': 'MODEL_SWOOP', 'bhvSnufit': 'MODEL_SNUFIT',
    'bhvKlepto': 'MODEL_KLEPTO', 'bhvBoo': 'MODEL_BOO', 'bhvGhostHuntBoo': 'MODEL_BOO', 'bhvBalconyBigBoo': 'MODEL_BOO',
    'bhvGhostHuntBigBoo': 'MODEL_BOO', 'bhvCirclingAmp': 'MODEL_AMP', 'bhvHomingAmp': 'MODEL_AMP',
    'bhvPiranhaPlant': 'MODEL_PIRANHA_PLANT', 'bhvFirePiranhaPlant': 'MODEL_PIRANHA_PLANT',
    'bhvFireSpitter': 'MODEL_BOWLING_BALL', 'bhvEnemyLakitu': 'MODEL_ENEMY_LAKITU', 'bhvMrI': 'MODEL_MR_I',
    'bhvThwomp': 'MODEL_THWOMP', 'bhvSmallWhomp': 'MODEL_WHOMP', 'bhvWhompKingBoss': 'MODEL_WHOMP',
    'bhvUnagi': 'MODEL_UNAGI', 'bhvBubba': 'MODEL_BUBBA', 'bhvSushiShark': 'MODEL_SUSHI',
    'bhvBigChillBully': 'MODEL_BIG_CHILL_BULLY', 'bhvSmallChillBully': 'MODEL_CHILL_BULLY', 'bhvBulletBill': 'MODEL_BULLET_BILL',
    'bhvCloud': 'MODEL_FWOOSH', 'bhvSLSnowmanWind': None, 'bhvMerryGoRoundBooManager': None, 'bhvBigBoulderGenerator': None, 'bhvMoneybagHidden': 'MODEL_YELLOW_COIN', 'bhvWaterBombSpawner': None, 'bhvPitBowlingBall': 'MODEL_BOWLING_BALL', 'bhvMantaRay': 'MODEL_MANTA_RAY', 'bhvJetStreamRingSpawner': None, 'bhvSnowmansBottom': 'MODEL_CCM_SNOWMAN_BASE',
    'bhvSnowmansHead': 'MODEL_CCM_SNOWMAN_HEAD', 'bhvBookendSpawn': None, 'bhvTweester': 'MODEL_TWEESTER', 'bhvEyerokBoss': None, 'bhvWaterLevelDiamond': 'MODEL_WDW_WATER_LEVEL_DIAMOND', 'bhvMips': 'MODEL_MIPS', 'bhvRacingPenguin': 'MODEL_PENGUIN', 'bhvMadPiano': 'MODEL_MAD_PIANO', 'bhvHauntedChair': 'MODEL_HAUNTED_CHAIR', 'bhvFlyingBookend': 'MODEL_BOOKEND',
    'bhvBooWithCage': 'MODEL_BOO', 'bhvBooInCastle': 'MODEL_BOO_CASTLE', 'bhvCourtyardBooTriplet': 'MODEL_BOO',
    'bhvFallingPillar': 'MODEL_JRB_FALLING_PILLAR', 'bhvBouncingFireball': None,
    'bhvSeaweed': 'MODEL_SEAWEED', 'bhvClamShell': 'MODEL_CLAM_SHELL', 'bhvFlamethrower': None,
    'bhvWigglerHead': 'MODEL_WIGGLER_HEAD', 'bhvScuttlebugSpawn': 'MODEL_SCUTTLEBUG', 'bhvFlame': 'MODEL_RED_FLAME',
    'bhvSmallPenguin': 'MODEL_PENGUIN', 'bhvTuxiesMother': 'MODEL_PENGUIN', 'bhvToadMessage': 'MODEL_TOAD',
    'bhvUkikiCage': None,
}

_scripts = None


def bhv_script(name):
    """the behaviour script's text (data/behavior_data.c)"""
    global _scripts
    if _scripts is None:
        t = X.strip_comments(open(os.path.join(X.D, 'data', 'behavior_data.c'), encoding='utf-8', errors='replace').read())
        _scripts = {}
        for m in re.finditer(r'const\s+BehaviorScript\s+(\w+)\s*\[\]\s*=\s*\{(.*?)\n\};', t, re.S):
            _scripts[m.group(1)] = m.group(2)
    return _scripts.get(name, '')


def bhv_anims(name):
    m = re.search(r'LOAD_ANIMATIONS\s*\(\s*oAnimations\s*,\s*(\w+)\s*\)', bhv_script(name))
    return m.group(1) if m else None


# behaviours that load their animations in code rather than in their script
CODE_ANIMS = {'bhvUkiki': 'ukiki_seg5_anims_05015784', 'bhvWhompKingBoss': 'whomp_seg6_anims_06020A04',
              'bhvSmallWhomp': 'whomp_seg6_anims_06020A04'}


def bhv_scale(name):
    m = re.search(r'\bSCALE\s*\(\s*\w+\s*,\s*(\d+)\s*\)', bhv_script(name))
    return (int(m.group(1)) / 100.0) if m else 1.0


_presets = None


def macro_presets():
    """macro preset -> (behaviour, model, param)"""
    global _presets
    if _presets is None:
        t = X.strip_comments(open(os.path.join(X.D, 'include', 'macro_presets.inc.c'), encoding='utf-8').read())
        raw = open(os.path.join(X.D, 'include', 'macro_presets.inc.c'), encoding='utf-8').read()
        _presets = {}
        for m in re.finditer(r'/\*\s*(macro_\w+)\s*\*/\s*\{\s*(\w+)\s*,\s*(\w+)\s*,\s*([^}]*)\}', raw):
            _presets[m.group(1)] = (m.group(2), m.group(3), m.group(4).strip())
    return _presets


def enemy_object(db, bhv, model, x, y, z, yaw, bp, mgmap, ue, used):
    """the scene object for one enemy, or None; `used` collects geo -> animation table for the models"""
    if bhv not in ENEMY_BHVS:
        return None
    model = model if model and model != 'MODEL_NONE' else ENEMY_BHVS.get(bhv)
    geo = mgmap.get(model) if model else None
    if geo and not db.has('geo', geo):
        geo = None
    if geo:
        anims = bhv_anims(bhv) or CODE_ANIMS.get(bhv)
        if used.get(geo) is None:
            used[geo] = anims
    return {'kind': 'enemy', 'type': bhv, 'pos': ue(x, y, z), 'sm64': [x, y, z], 'yaw': -yaw,
            'geo': geo, 'scale': bhv_scale(bhv), 'bp': bp}


# models the game spawns itself (Lakitu's spinies), exported whether a level places them or not
EXTRA_MODELS = {'spiny_geo': 'spiny_seg5_anims_05016EAC', 'red_flame_geo': None, 'bowling_ball_geo': None,
                'haunted_cage_geo': None, 'eyerok_left_hand_geo': 'eyerok_seg5_anims_050116E4',
                'eyerok_right_hand_geo': 'eyerok_seg5_anims_050116E4', 'water_ring_geo': 'water_ring_seg6_anims_06013F7C',
                'water_bomb_geo': None, 'moneybag_geo': 'moneybag_seg6_anims_06005E5C',
                'bowser_key_geo': None, 'hoot_geo': 'hoot_seg5_anims_05005768',
                'wf_geo_000AE0': None, 'ddd_geo_000450': None, 'yellow_sphere_geo': None,
                'wiggler_body_geo': 'wiggler_seg5_anims_0500C874', 'pokey_body_part_geo': None}     # (poles: Scripts/poles.lua)
