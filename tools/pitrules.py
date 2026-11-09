import sys, math
sys.path.insert(0, 'X:/mashup-work/tools')
import luadata
d = luadata.load('E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/Scripts/data/scene_castle.lua')
cx, cy = 3243.0, -4134.75
for i, m in enumerate(d.get('floors', [])):
    p = m['pos']; idx = m['idx']
    keys = {k: v for k, v in m.items() if k not in ('pos', 'idx')}
    hits = []
    for t in range(0, len(idx), 3):
        a, b, c = [int(idx[t + j]) * 3 for j in range(3)]
        ax, ay, az, bx, by, bz, qx, qy, qz = p[a], p[a+1], p[a+2], p[b], p[b+1], p[b+2], p[c], p[c+1], p[c+2]
        d0 = (bx - ax) * (qy - ay) - (qx - ax) * (by - ay)
        if abs(d0) < 1e-6: continue
        l1 = ((bx - cx) * (qy - cy) - (qx - cx) * (by - cy)) / d0
        l2 = ((qx - cx) * (ay - cy) - (ax - cx) * (qy - cy)) / d0
        l3 = 1 - l1 - l2
        if l1 >= 0 and l2 >= 0 and l3 >= 0: hits.append(round(l1 * az + l2 * bz + l3 * qz, 1))
    print(i, keys, 'zs', sorted(set(round(p[j], 0) for j in range(2, len(p), 3)))[:6], 'under the pit:', hits)
