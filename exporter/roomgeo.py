# roomgeo.py <level> <area>: which of Mario 64's rooms each triangle of a scene's level model is drawn in - the area
# geo's GEO_SWITCH_CASE(n, geo_switch_area) draws only the branch of Mario's room (room = branch + 1). Written to
# data/room_tris_<scene>.lua as { [centroid "x,y,z" to 0.1 cm] = rooms bitmask }; rooms.lua splits the scene's
# sections by it and shows only his room's ("theres a bunch of holes through the map that show the lower part of the
# map instead of being blackend out", 2026-10-19: every room was drawn at once).
import os, sys
level, area = sys.argv[1], int(sys.argv[2])
scene = sys.argv[3] if len(sys.argv) > 3 else level
sys.argv = [sys.argv[0], 'none-only']
import build_all as BA
import sm64x as X
import sm64scenes as S
db = BA.db
blocks = S.area_blocks(level)[area]
root = X.parse_geo(db, blocks['geo'])
branches = []
def find(node):
    for ch in node['children']:
        if ch['cmd'] == 'GEO_SWITCH_CASE' and 'geo_switch_area' in ch['args'][-1]:
            for k in ch['children']:
                if k['cmd'] in ('GEO_BRANCH', 'GEO_BRANCH_AND_LINK'):
                    branches.append(k['args'][-1].strip())
            return True
        if find(ch):
            return True
    return False
find(root)
print('rooms', len(branches))
# the water boxes geo_movtex_draw_water_regions draws, by its parameter (moving_texture.c's quad collections: each
# draws the boxes of its own ids) - and the rooms whose branch has it
MOVTEX_IDS = {0x0701: [0], 0x0702: [50, 51]}
water = {}
def movtex_in(geo, seen=None):
    seen = seen if seen is not None else set()
    out = []
    def walk(node):
        for ch in node['children']:
            if ch['cmd'] == 'GEO_ASM' and 'geo_movtex_draw_water_regions' in ch['args'][-1]:
                out.append(int(ch['args'][0].strip(), 0))
            elif ch['cmd'] in ('GEO_BRANCH', 'GEO_BRANCH_AND_LINK'):
                t = ch['args'][-1].strip()
                if t not in seen and db.has('geo', t):
                    seen.add(t)
                    walk(X.parse_geo(db, t))
            walk(ch)
    walk(X.parse_geo(db, geo))
    return out
for r, br in enumerate(branches, 1):
    for prm in movtex_in(br):
        for wid in MOVTEX_IDS.get(prm, []):
            water[wid] = water.get(wid, 0) | (1 << (r - 1))
print('water rooms', {k: [r + 1 for r in range(len(branches)) if v >> r & 1] for k, v in water.items()})
fin = lambda secs: BA.lift_decals(BA.two_sided_alpha(BA.tile_alpha(secs)))
keys = {}
total = 0
for r, br in enumerate(branches, 1):
    mesh = X.Mesh()
    for layer, dl in X.collect_level_dls(db, br):
        mesh.xf = None
        mesh.cum = 1.0
        X.interp_dl(db, dl, X.GfxState(), mesh, layer, BA.textures)
    secs = fin(X.finish_sections(mesh))
    n = 0
    for sec in secs:
        P = [float(X.lua_num(v)) for v in sec['pos']]
        idx = sec['idx']
        for t in range(0, len(idx), 3):
            a, b, c = idx[t] * 3, idx[t + 1] * 3, idx[t + 2] * 3
            cx = (P[a] + P[b] + P[c]) / 3.0
            cy = (P[a + 1] + P[b + 1] + P[c + 1]) / 3.0
            cz = (P[a + 2] + P[b + 2] + P[c + 2]) / 3.0
            k = '%.1f,%.1f,%.1f' % (cx, cy, cz)
            keys[k] = keys.get(k, 0) | (1 << (r - 1))
            n += 1
    total += n
    print(' room', r, br, 'tris', n)
out = os.path.join(BA.DATA, 'room_tris_%s.lua' % scene)
with open(out, 'w', encoding='utf-8', newline='\n') as f:
    f.write('-- made by roomgeo.py: Mario 64 rooms of the scene\'s triangles (centroid -> rooms bitmask)\n')
    f.write('return { rooms = %d, tris = {\n' % len(branches))
    for k, m in keys.items():
        f.write('["%s"]=%d,\n' % (k, m))
    f.write('}, water = {\n')
    for k, m in water.items():
        f.write('[%d]=%d,\n' % (k, m))
    f.write('} }\n')
print('wrote', out, len(keys), 'keys of', total, 'tris')
