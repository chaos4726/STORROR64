#!/usr/bin/env python3
"""How Mario arrives at each warp node of each scene: the node's object behaviour, which Mario 64 turns into his
spawn type (area.c sWarpBhvSpawnTable -> level_update.c: out of a painting face down after a death, dropping in
from above, launched out, out of a pipe ...). Writes <SM64_OUT>/Scripts/data/spawns.lua:
{ [scene] = { [node id] = "bhvPaintingDeathWarp", ... } }. The scene files only keep a rough kind per node."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sm64x as X
import sm64scenes as S
import warpx as W

OUT = os.environ.get('SM64_OUT', '/home/claude/sm64work/out')
DATA = os.path.join(OUT, 'Scripts', 'data')
SKIP = {'menu', 'intro', 'ending'}


def main():
    out = {}
    for const, folder in W.LEVELS.items():
        if folder in SKIP or not os.path.exists(os.path.join(X.D, 'levels', folder, 'script.c')):
            continue
        try:
            areas = S.area_blocks(folder)
            entries = X.parse_objects(folder)
        except Exception as e:
            print('!! skipped', folder, e)
            continue
        for area in sorted(areas):
            name = W.scene_name(folder, area)
            nodes = {}
            for o in entries:
                if o.get('area') != area or o.get('bhv') not in W.NODE_BHV:
                    continue
                nid = W.bparam_byte(o['bparam'], 2)
                if nid is not None and nid not in nodes:
                    nodes[nid] = o['bhv']
            if nodes:
                out[name] = nodes
    os.makedirs(DATA, exist_ok=True)
    X.write_lua(os.path.join(DATA, 'spawns.lua'), out)
    print('spawns for', len(out), 'scenes')
    for k in ('castle', 'grounds', 'bowser', 'bitdw', 'bob'):
        print(k, out.get(k))


if __name__ == '__main__':
    main()
