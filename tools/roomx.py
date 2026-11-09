"""Mario 64's rooms (levels/*/areas/*/room.inc.c: a room number for each collision triangle, in collision order) for the
levels that have them, as the floor triangles of each room in the mod's scene centimetres: Scripts/data/rooms.lua.
The scene is (-z, x, y) x 0.75 of Mario 64's (x, y, z). Floors only (normal's y over 0.01, as Mario 64's find_floor).
python tools/roomx.py   (from X:/mashup-work)"""
import os
import re

LEVELS = {'bbh': 'bbh/areas/1', 'castle': 'castle_inside/areas/1', 'castle2': 'castle_inside/areas/2',
          'castle3': 'castle_inside/areas/3', 'hmc': 'hmc/areas/1'}
U = 0.75
OUT = os.path.join(os.environ.get("SM64_MOD", r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map"), r"Scripts/data/rooms.lua")


def parse(area):
    col = open(os.path.join(os.environ.get('SM64_DECOMP', 'sm64decomp'), 'levels/%s/collision.inc.c' % area)).read()
    col = col[:col.index('COL_END')]        # (the area's own; objects' collision may follow in the same file)
    verts = [tuple(int(v) for v in m.groups()) for m in re.finditer(r'COL_VERTEX\(\s*(-?\d+),\s*(-?\d+),\s*(-?\d+)\s*\)', col)]
    tris = []
    # (COL_TRI and COL_TRI_SPECIAL, in file order - the order Mario 64 loads them and reads their rooms)
    for m in re.finditer(r'COL_TRI(?:_SPECIAL)?\(\s*(\d+),\s*(\d+),\s*(\d+)', col):
        tris.append(tuple(int(v) for v in m.groups()))
    rooms_src = open(os.path.join(os.environ.get('SM64_DECOMP', 'sm64decomp'), 'levels/%s/room.inc.c' % area)).read()
    body = rooms_src[rooms_src.index('{') + 1:rooms_src.rindex('}')]
    body = re.sub(r'//[^\n]*', '', body)
    rooms = [int(v) for v in re.findall(r'-?\d+', body)]
    return verts, tris, rooms


def main():
    out = ['-- Mario 64\'s rooms, floor triangles by room in scene cm (tools/roomx.py from sm64decomp room.inc.c).',
           '-- Each scene: a flat list, ten numbers a triangle: x1 y1 z1 x2 y2 z2 x3 y3 z3 room.', 'return {']
    for name, area in LEVELS.items():
        verts, tris, rooms = parse(area)
        assert len(rooms) >= len(tris), (name, len(rooms), len(tris))
        flat, nfloor = [], 0
        for i, (a, b, c) in enumerate(tris):
            p = [verts[a], verts[b], verts[c]]
            ux, uy, uz = p[1][0] - p[0][0], p[1][1] - p[0][1], p[1][2] - p[0][2]
            vx, vy, vz = p[2][0] - p[1][0], p[2][1] - p[1][1], p[2][2] - p[1][2]
            nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            mag = (nx * nx + ny * ny + nz * nz) ** 0.5
            if mag == 0 or ny / mag <= 0.01:
                continue
            for (x, y, z) in p:
                flat += ['%g' % (-z * U), '%g' % (x * U), '%g' % (y * U)]
            flat.append(str(rooms[i]))
            nfloor += 1
        lines = []
        for k in range(0, len(flat), 30):
            lines.append('    ' + ','.join(flat[k:k + 30]) + ',')
        out.append('  %s = {' % name)
        out += lines
        out.append('  },')
        print(name, len(tris), 'tris,', nfloor, 'floors, rooms', sorted(set(rooms[:len(tris)])))
    out.append('}')
    open(OUT, 'w', encoding='utf-8').write('\n'.join(out) + '\n')


main()
