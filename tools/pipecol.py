import sys, math
sys.path.insert(0, 'X:/mashup-work/tools')
import luadata
from collections import Counter
scene = sys.argv[1] if len(sys.argv) > 1 else 'bitdw'
d = luadata.load('E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/Scripts/data/scene_%s.lua' % scene)
pipes = [o for o in d['objects'] if o.get('kind') == 'pipe']
print('pipes', [o['pos'] for o in pipes])
for pp in pipes:
    px, py, pz = pp['pos']
    for kind, meshes in (('sec', d['sections']), ('col', d['collision'])):
        for si, m in enumerate(meshes):
            p, idx = m['pos'], m['idx']
            hits = Counter()
            for t in range(0, len(idx), 3):
                vs = [int(idx[t + j]) for j in range(3)]
                xs = [p[3*v] for v in vs]; ys = [p[3*v+1] for v in vs]; zs = [p[3*v+2] for v in vs]
                # triangle's xy box overlaps the column, and it is not the pipe itself
                if max(xs) < px - 80 or min(xs) > px + 80 or max(ys) < py - 80 or min(ys) > py + 80: continue
                if min(zs) > pz + 5: continue
                hits[(round(min(zs)), round(max(zs)))] += 1
            if hits:
                print(kind, si, m.get('texture') or m.get('source'), dict(sorted(hits.items(), key=lambda kv: -kv[0][0])[:8]))
print('--- detail')
px, py, pz = pipes[0]['pos']
for kind, meshes, si in (('sec', d['sections'], 15), ('col', d['collision'], 1)):
    m = meshes[si]; p, idx = m['pos'], m['idx']; nrm = m.get('nrm')
    for t in range(0, len(idx), 3):
        vs = [int(idx[t + j]) for j in range(3)]
        xs = [p[3*v] for v in vs]; ys = [p[3*v+1] for v in vs]; zs = [p[3*v+2] for v in vs]
        if max(xs) < px - 80 or min(xs) > px + 80 or max(ys) < py - 80 or min(ys) > py + 80: continue
        if min(zs) > pz + 5: continue
        if max(zs) - min(zs) > 1: continue
        print(kind, si, [(round(p[3*v], 1), round(p[3*v+1], 1), round(p[3*v+2], 1)) for v in vs], 'nrm', [round(nrm[3*v+2], 2) for v in vs] if nrm else '')
