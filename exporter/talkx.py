#!/usr/bin/env python3
"""What can be read or talked to in each scene, and its message: wooden signposts (macro_wooden_signpost and
bhvMessagePanel: the dialog in the behaviour parameter) and the castle's Toads (bhvToadMessage, BPARAM1). Writes
<SM64_OUT>/Scripts/data/talk.lua: { [scene] = { { kind = "sign"/"toad", pos = {x, y, z} (scene cm), yaw, dialog } } }.
Usage: python talkx.py   (SM64_DECOMP and SM64_OUT as for build_all.py)"""
import os
import re
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sm64x as X
import sm64scenes as S
import warpx as W

OUT = os.environ.get('SM64_OUT', 'out')
DATA = os.path.join(OUT, 'Scripts', 'data')
SCALE = 0.75


def ue(x, y, z):
    return [-z * SCALE, x * SCALE, y * SCALE]


def dialog_of(bparam):
    m = re.search(r'DIALOG_(\d+)', bparam or '')
    return int(m.group(1)) if m else None


out = {}
for const, folder in W.LEVELS.items():
    if folder in ('menu', 'intro', 'ending') or not os.path.exists(os.path.join(X.D, 'levels', folder, 'script.c')):
        continue
    try:
        areas = S.area_blocks(folder)
        entries = X.parse_objects(folder)
    except Exception as e:
        print('!! skipped', folder, e)
        continue
    for area in sorted(areas):
        name = W.scene_name(folder, area)
        things = []
        for o in entries:
            if o.get('area') != area:
                continue
            kind = {'bhvMessagePanel': 'sign', 'bhvToadMessage': 'toad'}.get(o.get('bhv'))
            d = dialog_of(o.get('bparam'))
            if kind and d is not None:
                things.append({'kind': kind, 'pos': ue(o['x'], o['y'], o['z']), 'yaw': -o['ay'], 'dialog': d})
            # Bob-omb Buddies (bobomb.inc.c): an adviser's message is its second parameter byte, one buddy per act at
            # the same spot; a cannon buddy says DIALOG_004/105 (BoB) or 047/106 and opens the course's cannons
            if o.get('bhv') == 'bhvBobombBuddy' and d is not None:
                things.append({'kind': 'buddy', 'pos': ue(o['x'], o['y'], o['z']), 'yaw': -o['ay'], 'dialog': d,
                               'acts': o.get('acts', 0x3F)})
            if o.get('bhv') == 'bhvBobombBuddyOpensCannon':
                things.append({'kind': 'cannon_buddy', 'pos': ue(o['x'], o['y'], o['z']), 'yaw': -o['ay'],
                               'acts': o.get('acts', 0x3F)})
        try:
            macros = X.parse_macro_objects(folder, area)
        except Exception:
            macros = []
        for mo in macros:
            d = dialog_of(mo.get('bparam'))
            if mo['preset'] == 'macro_wooden_signpost' and d is not None:
                things.append({'kind': 'sign', 'pos': ue(mo['x'], mo['y'], mo['z']), 'yaw': -mo['yaw'], 'dialog': d})
            # (the castle's wall signs, macro_sign_on_wall / bhvSignOnWall: no model - the plaque is in the wall's own
            # picture - read the same way, facing it)
            if mo['preset'] == 'macro_sign_on_wall' and d is not None:
                things.append({'kind': 'sign', 'wall': True, 'pos': ue(mo['x'], mo['y'], mo['z']), 'yaw': -mo['yaw'], 'dialog': d})
            if mo['preset'] == 'macro_bobomb_buddy_opens_cannon_1':
                things.append({'kind': 'cannon_buddy', 'pos': ue(mo['x'], mo['y'], mo['z']), 'yaw': -mo['yaw']})
        if things:
            out[name] = things
os.makedirs(DATA, exist_ok=True)
X.write_lua(os.path.join(DATA, 'talk.lua'), out)
print('scenes with signs or Toads:', len(out), sum(len(v) for v in out.values()), 'in all')
for k in ('bob', 'castle', 'grounds', 'wf', 'jrb', 'ccm'):
    print(k, [(t['kind'], t.get('dialog'), t.get('acts')) for t in out.get(k, []) if t['kind'] != 'sign'])
