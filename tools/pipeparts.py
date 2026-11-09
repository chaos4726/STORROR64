import sys, math
sys.path.insert(0, 'X:/mashup-work/tools')
import luadata
d = luadata.load('E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/Scripts/data/scene_%s.lua' % sys.argv[1])
px, py, pz = [o for o in d['objects'] if o.get('kind') == 'pipe'][0]['pos']
for kind, meshes in (('sec', d['sections']), ('col', d['collision'])):
    for si, m in enumerate(meshes):
        p, idx = m['pos'], m['idx']
        rs = []
        for t in range(0, len(idx), 3):
            vs = [int(idx[t + j]) for j in range(3)]
            pts = [(p[3*v] - px, p[3*v+1] - py, p[3*v+2]) for v in vs]
            if all(math.hypot(a, b) < 125 and pz - 5 <= c <= pz + 160 for a, b, c in pts):
                rs.append(tuple(sorted(set((round(math.hypot(a, b)), round(c)) for a, b, c in pts))))
        if rs:
            from collections import Counter
            print(kind, si, m.get('texture') or m.get('source'), len(rs), Counter(rs).most_common(6))
