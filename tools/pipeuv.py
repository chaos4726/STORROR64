import sys, math
sys.path.insert(0, 'X:/mashup-work/tools')
import luadata
d = luadata.load('E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/Scripts/data/scene_bitdw.lua')
px, py, pz = 5.25, 5112.0, 2145.0
m = d['sections'][20]; p, uv, col, nrm = m['pos'], m['uv'], m['col'], m['nrm']
seen = set()
for v in range(len(p) // 3):
    a, b, c = p[3*v] - px, p[3*v+1] - py, p[3*v+2]
    r = math.hypot(a, b)
    if r < 80 and pz - 5 <= c <= pz + 160:
        ang = round(math.degrees(math.atan2(b, a)))
        key = (ang, round(c))
        if key in seen: continue
        seen.add(key)
        print('inner ang %4d z %5.0f uv %.3f %.3f col %.2f nrm %.2f %.2f %.2f' % (ang, c, uv[2*v], uv[2*v+1], col[4*v], nrm[3*v], nrm[3*v+1], nrm[3*v+2]))
m = d['sections'][22]; print('sec22', m.get('layer'), [round(x, 2) for x in m['col'][:8]], m['pos'][:12])
