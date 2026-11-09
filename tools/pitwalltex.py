import sys, math
sys.path.insert(0, 'X:/mashup-work/tools')
import luadata
from collections import Counter
d = luadata.load('E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/Scripts/data/scene_castle.lua')
cx, cy = 3243.0, -4134.75
for si, m in enumerate(d['sections']):
    p, nrm, uv = m['pos'], m.get('nrm', []), m.get('uv', [])
    n = len(p) // 3
    walls = 0; zs = []
    ex = []
    for v in range(n):
        x, y, z = p[3*v], p[3*v+1], p[3*v+2]
        if math.hypot(x - cx, y - cy) < 1500 and 530 < z < 1200 and nrm and abs(nrm[3*v+2]) < 0.2:
            walls += 1; zs.append(z)
            if len(ex) < 2: ex.append((v, x, y, z, uv[2*v], uv[2*v+1]))
    if walls:
        print(si, m.get('texture'), 'wall verts', walls, 'z %.0f..%.0f' % (min(zs), max(zs)), ex)
