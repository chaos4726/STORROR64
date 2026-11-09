import sys, math
sys.path.insert(0, 'X:/mashup-work/tools')
import luadata
d = luadata.load('X:/mashup-work/export_chk/Scripts/data/scene_castle.lua')
for si, m in enumerate(d['sections']):
    if m.get('layer') in ('opaque',):
        continue
    p = m['pos']; n = len(p) // 3
    near = [v for v in range(n) if math.hypot(p[3*v] - 1512, p[3*v+1] - 1930) < 900 and 200 < p[3*v+2] < 700]
    if near:
        cols = m.get('col', [])
        alphas = sorted(set(round(cols[4*v+3], 3) for v in near)) if cols else []
        rgb = sorted(set(tuple(round(c, 2) for c in cols[4*v:4*v+3]) for v in near))[:4] if cols else []
        print(si, m.get('layer'), m.get('texture'), 'verts near', len(near), 'of', n, 'alpha', alphas[:6], 'rgb', rgb)
