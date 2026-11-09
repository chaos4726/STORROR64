#!/usr/bin/env python3
"""Mario 64's butterflies: the model and its two animations (data/actor_butterfly.lua), and where every butterfly
of the game sits (data/butterflies.lua, by scene: `single` for bhvButterfly objects, which rest on the ground and
flutter after Mario; `triplet` for the butterfly_triplet presets, three that scatter when he comes close, one of
which may turn into a 1-up, or, where `bombs` is set, into a bomb).

Usage: python butterflyx.py   (SM64_DECOMP and SM64_OUT as for build_all.py)"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sm64x as X
import sm64scenes as S
import warpx as W
from sm64x import SCALE

OUT = os.environ.get('SM64_OUT', 'out')
DATA = os.path.join(OUT, 'Scripts', 'data')
TEXD = os.path.join(OUT, 'textures')
D = X.D

NUM = r'(-?\d+)'
SINGLE = re.compile(r'OBJECT\s*\(\s*/\*model\*/\s*MODEL_BUTTERFLY\s*,\s*/\*pos\*/\s*' + NUM + r'\s*,\s*' + NUM + r'\s*,\s*' + NUM +
                    r'.*?bhvButterfly\s*\)')
TRIPLET = re.compile(r'MACRO_OBJECT\s*\(\s*/\*preset\*/\s*(macro_butterfly_triplet\w*)\s*,\s*/\*yaw\*/\s*' + NUM +
                     r'\s*,\s*/\*pos\*/\s*' + NUM + r'\s*,\s*' + NUM + r'\s*,\s*' + NUM)


def ue(x, y, z):
    return [-z * SCALE, x * SCALE, y * SCALE]


def placements():
    out = {}
    levels = os.path.join(D, 'levels')
    for folder in sorted(os.listdir(levels)):
        script = os.path.join(levels, folder, 'script.c')
        if not os.path.exists(script):
            continue
        # (the levels that have them keep their butterflies in their one area)
        with open(script, encoding='utf-8', errors='replace') as f:
            for m in SINGLE.finditer(f.read()):
                x, y, z = (int(v) for v in m.groups())
                out.setdefault(W.scene_name(folder, 1), {'single': [], 'triplet': []})['single'].append(ue(x, y, z))
        areas = os.path.join(levels, folder, 'areas')
        if not os.path.isdir(areas):
            continue
        for area in sorted(os.listdir(areas)):
            macro = os.path.join(areas, area, 'macro.inc.c')
            if not (area.isdigit() and os.path.exists(macro)):
                continue
            with open(macro, encoding='utf-8', errors='replace') as f:
                for m in TRIPLET.finditer(f.read()):
                    preset, _yaw, x, y, z = m.groups()
                    out.setdefault(W.scene_name(folder, int(area)), {'single': [], 'triplet': []})['triplet'].append(
                        {'pos': ue(int(x), int(y), int(z)), 'bombs': not preset.endswith('no_bombs')})
    return out


def main():
    db = X.DB()
    for sym, png in list(db.tex.items()):
        if not os.path.exists(os.path.join(D, png)):
            base, ext = png.split('.', 1)
            if os.path.exists(os.path.join(D, base + '_us.' + ext)):
                db.tex[sym] = base + '_us.' + ext
    textures = {}
    anims = S.anim_table(db, 'butterfly_seg3_anims_030056B0')
    actor = S.export_actor(db, 'butterfly_geo', anims, textures)
    X.write_lua(os.path.join(DATA, 'actor_butterfly.lua'), actor)
    print('actor butterfly: parts', len(actor['parts']), 'anims', len(actor['anims']),
          'frames', [a.get('frames') for a in actor['anims']])
    where = placements()
    X.write_lua(os.path.join(DATA, 'butterflies.lua'), where,
                header='-- (this file: where Mario 64 puts its butterflies, by scene; butterflyx.py)\n')
    for scene, w in where.items():
        print('  %-14s %2d single, %d triplets' % (scene, len(w['single']), len(w['triplet'])))
    print('textures copied:', X.copy_textures(textures, TEXD))


if __name__ == '__main__':
    main()
