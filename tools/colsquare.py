import sys, math
sys.path.insert(0, 'X:/mashup-work/tools')
import luadata
scene = sys.argv[1]
d = luadata.load('E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/Scripts/data/scene_%s.lua' % scene)
px, py, pz = [o for o in d['objects'] if o.get('kind') == 'pipe'][0]['pos']
H = 78.0
def tri_in_square(pts):
    # sample: does the triangle cover any of a grid of points inside the square?
    hits = 0
    (ax, ay), (bx, by), (cx, cy) = pts
    d0 = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
    if abs(d0) < 1e-9: return 0
    for i in range(-6, 7):
        for j in range(-6, 7):
            x, y = px + i * H / 6, py + j * H / 6
            l1 = ((bx - x) * (cy - y) - (cx - x) * (by - y)) / d0
            l2 = ((cx - x) * (ay - y) - (ax - x) * (cy - y)) / d0
            if l1 >= -1e-6 and l2 >= -1e-6 and 1 - l1 - l2 >= -1e-6: hits += 1
    return hits
for kind, meshes in (('sec', d['sections']), ('col', d['collision'])):
    for si, m in enumerate(meshes):
        p, idx = m['pos'], m['idx']
        for t in range(0, len(idx), 3):
            vs = [int(idx[t + j]) for j in range(3)]
            zs = [p[3*v+2] for v in vs]
            if max(zs) - min(zs) > 1 or min(zs) > pz + 5 or min(zs) < pz - 1600: continue
            h = tri_in_square([(p[3*v], p[3*v+1]) for v in vs])
            if h: print(kind, si, m.get('texture') or m.get('source'), 'z', round(zs[0]), 'covers', h, 'of 169 grid points')
for o in d['objects']:
    if o.get('pos') and math.hypot(o['pos'][0] - px, o['pos'][1] - py) < 900 and o.get('kind') not in ('coin',):
        print('obj', {k: v for k, v in o.items() if k in ('kind', 'bhv', 'pos', 'node', 'actor')})
for n in d.get('nodes', []):
    if math.hypot(n['pos'][0] - px, n['pos'][1] - py) < 1500: print('node', n)
