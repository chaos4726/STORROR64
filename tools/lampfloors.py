"""The floors of the enclosed levels without Mario 64 rooms (caves, the pyramid, the clock, the slides ...), for the
lamps (Scripts/lamps.lua): each area's floor triangles in the mod's scene centimetres, all one room (1) - as
tools/roomx.py writes data/rooms.lua, but a file of their own, so that rooms.lua's culling never sees them.
The scene is (-z, x, y) x 0.75 of Mario 64's (x, y, z). Floors only (normal's y over 0.01, as Mario 64's find_floor).
("all enclosed levels need lamps and correct lighting", 2026-10-31)
python tools/lampfloors.py   (from X:/mashup-work)"""
import os
import re

LEVELS = {
    'cotmc': 'cotmc/areas/1', 'vcutm': 'vcutm/areas/1', 'pss': 'pss/areas/1', 'sa': 'sa/areas/1', 'ttc': 'ttc/areas/1',
    'ssl_2': 'ssl/areas/2', 'ssl_3': 'ssl/areas/3', 'lll_2': 'lll/areas/2', 'ccm_2': 'ccm/areas/2', 'sl_2': 'sl/areas/2',
    'ttm_2': 'ttm/areas/2', 'ttm_3': 'ttm/areas/3', 'ttm_4': 'ttm/areas/4', 'thi_3': 'thi/areas/3', 'jrb_2': 'jrb/areas/2',
    'ddd_2': 'ddd/areas/2', 'wdw_2': 'wdw/areas/2',
}
U = 0.75
OUT = os.path.join(os.environ.get("SM64_MOD", r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map"), r"Scripts/data/lamp_floors.lua")


def parse(area):
    col = open(os.path.join(os.environ.get('SM64_DECOMP', 'sm64decomp'), 'levels/%s/collision.inc.c' % area)).read()
    col = col[:col.index('COL_END')]        # (the area's own; objects' collision may follow in the same file)
    verts = [tuple(int(v) for v in m.groups()) for m in re.finditer(r'COL_VERTEX\(\s*(-?\d+),\s*(-?\d+),\s*(-?\d+)\s*\)', col)]
    tris = [tuple(int(v) for v in m.groups()) for m in re.finditer(r'COL_TRI(?:_SPECIAL)?\(\s*(\d+),\s*(\d+),\s*(\d+)', col)]
    return verts, tris


def main():
    out = ['-- The enclosed levels\' floors for the lamps (tools/lampfloors.py), one room each, in scene cm.',
           '-- Each scene: a flat list, ten numbers a triangle: x1 y1 z1 x2 y2 z2 x3 y3 z3 room.', 'return {']
    for name, area in LEVELS.items():
        verts, tris = parse(area)
        flat, nfloor = [], 0
        for (a, b, c) in tris:
            p = [verts[a], verts[b], verts[c]]
            ux, uy, uz = p[1][0] - p[0][0], p[1][1] - p[0][1], p[1][2] - p[0][2]
            vx, vy, vz = p[2][0] - p[1][0], p[2][1] - p[1][1], p[2][2] - p[1][2]
            nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            mag = (nx * nx + ny * ny + nz * nz) ** 0.5
            if mag == 0 or ny / mag <= 0.01:
                continue
            for (x, y, z) in p:
                flat += ['%g' % (-z * U), '%g' % (x * U), '%g' % (y * U)]
            flat.append('1')
            nfloor += 1
        lines = ['    ' + ','.join(flat[k:k + 30]) + ',' for k in range(0, len(flat), 30)]
        out.append('  %s = {' % name)
        out += lines
        out.append('  },')
        print(name, len(tris), 'tris,', nfloor, 'floors')
    out.append('}')
    open(OUT, 'w', encoding='utf-8').write('\n'.join(out) + '\n')


main()
