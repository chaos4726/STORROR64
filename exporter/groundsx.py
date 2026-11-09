#!/usr/bin/env python3
"""The castle grounds' living scenery, from the player's own copy: the waving flags on the towers, the bird flocks,
the fish in the lake, Yoshi on the roof, the waterfall's mist and sound, and the hidden 1-ups.

Writes data/actor_castle_flag.lua, actor_birds.lua, actor_blue_fish.lua, actor_yoshi.lua (models and animations)
and data/grounds_life.lua (where each thing is, in scene space; yaws in degrees).

Usage: python groundsx.py   (SM64_DECOMP and SM64_OUT as for build_all.py)"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sm64x as X
import sm64scenes as S
from sm64x import SCALE

OUT = os.environ.get('SM64_OUT', 'out')
DATA = os.path.join(OUT, 'Scripts', 'data')
TEXD = os.path.join(OUT, 'textures')
D = X.D

ACTORS = {
    'castle_flag': ('castle_grounds_geo_000660', 'castle_grounds_seg7_anims_flags'),
    'birds': ('birds_geo', 'birds_seg5_anims_050009E8'),
    'blue_fish': ('fish_geo', 'blue_fish_seg3_anims_0301C2B0'),
    'yoshi': ('yoshi_geo', 'yoshi_seg5_anims_05024100'),
}
N = r'\s*(-?\d+)\s*'
OBJ = re.compile(r'OBJECT\s*\(\s*/\*model\*/\s*(\w+)\s*,\s*/\*pos\*/' + N + ',' + N + ',' + N +
                 r',\s*/\*angle\*/' + N + ',' + N + ',' + N + r',\s*/\*bhvParam\*/\s*([^,]+?)\s*,\s*/\*bhv\*/\s*(\w+)\s*\)')
MAC = re.compile(r'MACRO_OBJECT(?:_WITH_BHV_PARAM)?\s*\(\s*/\*preset\*/\s*(\w+)\s*,\s*/\*yaw\*/' + N + r',\s*/\*pos\*/' + N + ',' + N + ',' + N)


def ue(x, y, z):
    return [-z * SCALE, x * SCALE, y * SCALE]


def main():
    db = X.DB()
    for sym, png in list(db.tex.items()):
        if not os.path.exists(os.path.join(D, png)):
            base, ext = png.split('.', 1)
            if os.path.exists(os.path.join(D, base + '_us.' + ext)):
                db.tex[sym] = base + '_us.' + ext
    textures = {}
    for name, (geo, anims) in ACTORS.items():
        actor = S.export_actor(db, geo, S.anim_table(db, anims), textures)
        X.write_lua(os.path.join(DATA, 'actor_%s.lua' % name), actor)
        print('actor %-12s parts %2d anims %d frames %s' % (name, len(actor['parts']), len(actor['anims']),
                                                          [a.get('frames') for a in actor['anims']]))
    with open(os.path.join(D, 'levels', 'castle_grounds', 'script.c'), encoding='utf-8') as f:
        script = f.read()
    with open(os.path.join(D, 'levels', 'castle_grounds', 'areas', '1', 'macro.inc.c'), encoding='utf-8') as f:
        macros = f.read()
    life = {'flags': [], 'bird_flocks': [], 'fish_schools': [], 'mist': [], 'waterfall_sound': [], 'yoshi': [],
            'hidden_1up_pole': [], 'hidden_1up_triggers': [], 'hidden_1up': []}
    for m in OBJ.finditer(script):
        model, x, y, z, ax, ay, az, bparam, bhv = m.groups()
        p = ue(int(x), int(y), int(z))
        yaw = -int(ay)
        if bhv == 'bhvCastleFlagWaving':
            life['flags'].append({'pos': p, 'yaw': yaw})
        elif bhv == 'bhvBird':
            life['bird_flocks'].append({'pos': p})
        elif bhv == 'bhvManyBlueFishSpawner':
            life['fish_schools'].append({'pos': p, 'count': 20})
        elif bhv == 'bhvWaterMist2':
            life['mist'].append({'pos': p})
        elif bhv == 'bhvWaterfallSoundLoop':
            life['waterfall_sound'].append({'pos': p})
        elif bhv == 'bhvYoshi':
            life['yoshi'].append({'pos': p})
    for m in MAC.finditer(macros):
        preset, yaw, x, y, z = m.groups()
        p = ue(int(x), int(y), int(z))
        if preset == 'macro_hidden_1up_in_pole':
            life['hidden_1up_pole'].append({'pos': p})
        elif preset == 'macro_hidden_1up_trigger':
            life['hidden_1up_triggers'].append({'pos': p})
        elif preset == 'macro_hidden_1up':
            life['hidden_1up'].append({'pos': p})
    X.write_lua(os.path.join(DATA, 'grounds_life.lua'), life,
                header='-- (this file: the castle grounds\' living scenery, from the level script; groundsx.py)\n')
    for k, v in life.items():
        print('  %-20s %d' % (k, len(v)))
    print('textures copied:', X.copy_textures(textures, TEXD))


if __name__ == '__main__':
    main()
