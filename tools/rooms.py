"""Bounds of each room of an area (collision triangles grouped by the area's RoomData), Mario 64 units and scene cm.
python tools/rooms.py castle_inside 2"""
import re
import sys

lvl, area = sys.argv[1], sys.argv[2]
base = 'sm64decomp/levels/%s/areas/%s/' % (lvl, area)
col = open(base + 'collision.inc.c').read()
verts = [tuple(int(v) for v in m.groups()) for m in re.finditer(r'COL_VERTEX\((-?\d+),\s*(-?\d+),\s*(-?\d+)\)', col)]
tris = []
for m in re.finditer(r'COL_TRI(?:_SPECIAL)?\((\d+),\s*(\d+),\s*(\d+)', col):
    tris.append(tuple(int(v) for v in m.groups()))
body = open(base + 'room.inc.c').read().split('{', 1)[1]
body = re.sub(r'//.*', '', body)
rooms = [int(v) for v in re.findall(r'\d+', body)]
print(len(verts), 'verts', len(tris), 'tris', len(rooms), 'room entries')
box = {}
for t, r in zip(tris, rooms):
    b = box.setdefault(r, [1e9, -1e9, 1e9, -1e9, 1e9, -1e9])
    for i in t:
        x, y, z = verts[i]
        b[0], b[1] = min(b[0], x), max(b[1], x)
        b[2], b[3] = min(b[2], y), max(b[3], y)
        b[4], b[5] = min(b[4], z), max(b[5], z)
for r in sorted(box):
    b = box[r]
    print('room %2d  x %6d..%6d  y %6d..%6d  z %6d..%6d   scene x %.0f..%.0f y %.0f..%.0f' % (
        r, b[0], b[1], b[2], b[3], b[4], b[5], -b[5] * .75, -b[4] * .75, b[0] * .75, b[1] * .75))
