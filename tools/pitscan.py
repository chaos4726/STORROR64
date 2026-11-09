import sys, math
sys.path.insert(0, 'X:/mashup-work/tools')
import luadata
from collections import Counter
d = luadata.load('E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/Scripts/data/scene_castle.lua')
cx, cy, R = 3243.0, -4134.75, 450.0
print('sections', len(d['sections']), 'collision meshes', len(d['collision']), 'floors', len(d.get('floors', [])))
for kind, meshes in (('sec', d['sections']), ('col', d['collision']), ('floors', d.get('floors', []))):
    for si, m in enumerate(meshes):
        p = m['pos']; n = len(p) // 3
        zs = Counter()
        for v in range(n):
            x, y, z = p[3*v], p[3*v+1], p[3*v+2]
            if math.hypot(x - cx, y - cy) < R and 200 < z < 700:
                zs[round(z, 1)] += 1
        if zs:
            print(kind, si, m.get('texture') or m.get('source') or m.get('type'), dict(zs))
print('--- detail')
for kind, meshes, idxs in (('sec', d['sections'], [14, 0]), ('col', d['collision'], [0])):
    for si in idxs:
        m = meshes[si]; p = m['pos']; n = len(p) // 3
        near = [v for v in range(n) if math.hypot(p[3*v] - cx, p[3*v+1] - cy) < R and 200 < p[3*v+2] < 700]
        print(kind, si, 'verts', near)
        for v in near:
            extra = ''
            if 'uv' in m: extra += ' uv %.3f %.3f' % (m['uv'][2*v], m['uv'][2*v+1])
            if 'col' in m: extra += ' col %.2f %.2f %.2f' % tuple(m['col'][4*v:4*v+3])
            print('   %d (%.1f, %.1f, %.1f)%s' % (v, p[3*v], p[3*v+1], p[3*v+2], extra))
        idx = m['idx']
        tris = [tuple(idx[t:t+3]) for t in range(0, len(idx), 3) if any(i in near for i in idx[t:t+3])]
        print('  tris', tris)
