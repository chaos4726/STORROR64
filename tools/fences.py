# fences.py <scene>: thin low walls in a scene's collision (two faces back to back, under 160 cm tall over the ground
# beside them) and whether a floor caps them (STORROR needs a top to vault)
import re, sys, math
D = r"E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/Scripts/data/"
s = open(D + "scene_%s.lua" % sys.argv[1], encoding="utf-8", errors="replace").read()
c = s[s.find("collision = {"):]
tris = []
for m in re.finditer(r"pos = \{([^}]*)\},\s*idx = \{([^}]*)\}", c):
    pos = [float(x) for x in m.group(1).split(",") if x.strip()]
    idx = [int(x) for x in m.group(2).split(",") if x.strip()]
    for t in range(0, len(idx) - 2, 3):
        tris.append([tuple(pos[idx[t + k] * 3: idx[t + k] * 3 + 3]) for k in range(3)])
walls, floors = [], []
for v in tris:
    (ax, ay, az), (bx, by, bz), (cx, cy, cz) = v
    ux, uy, uz = bx - ax, by - ay, bz - az; wx, wy, wz = cx - ax, cy - ay, cz - az
    nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
    L = math.sqrt(nx * nx + ny * ny + nz * nz)
    if L < 1e-6: continue
    nx, ny, nz = nx / L, ny / L, nz / L
    if abs(nz) < 0.45: walls.append((v, (nx, ny), min(p[2] for p in v), max(p[2] for p in v)))
    elif -nz > 0.45 or nz > 0.45: floors.append(v)
def floor_at(x, y, zmax):
    best = None
    for v in floors:
        (ax, ay, az), (bx, by, bz), (cx, cy, cz) = v
        d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(d) < 1e-9: continue
        l1 = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / d
        l2 = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / d
        l3 = 1 - l1 - l2
        if l1 >= -1e-3 and l2 >= -1e-3 and l3 >= -1e-3:
            z = l1 * az + l2 * bz + l3 * cz
            if z <= zmax and (best is None or z > best): best = z
    return best
found = []
for i, (v, n, z0, z1) in enumerate(walls):
    mx = sum(p[0] for p in v) / 3; my = sum(p[1] for p in v) / 3
    # the face's own ground: in front of it
    g = floor_at(mx + n[0] * 30, my + n[1] * 30, z1 + 5)
    if g is None: continue
    h = z1 - g
    if not (25 <= h <= 160): continue
    # a back face within 40 cm behind it, facing the other way
    back = None
    for j, (v2, n2, a0, a1) in enumerate(walls):
        if j == i or n[0] * n2[0] + n[1] * n2[1] > -0.9: continue
        m2x = sum(p[0] for p in v2) / 3; m2y = sum(p[1] for p in v2) / 3
        d = (mx - m2x) * n[0] + (my - m2y) * n[1]
        side = abs((mx - m2x) * -n[1] + (my - m2y) * n[0])
        if 0 <= d <= 40 and side < 150 and abs(a1 - z1) < 20: back = (j, d); break
    if not back: continue
    th = back[1]
    cxp, cyp = mx - n[0] * th / 2, my - n[1] * th / 2
    top = floor_at(cxp, cyp, z1 + 5)
    capped = top is not None and abs(top - z1) < 15
    found.append((round(mx), round(my), round(z1), round(h), round(th), capped))
seen = set()
out = []
for f in found:
    k = (f[0] // 150, f[1] // 150)
    if k in seen: continue
    seen.add(k); out.append(f)
print("%s: %d thin low walls (%d places); uncapped %d, capped %d" % (sys.argv[1], len(found), len(out),
      sum(1 for f in out if not f[5]), sum(1 for f in out if f[5])))
for f in out[:12]: print("  at %d,%d top %d, %d cm over the ground, %d cm thick, %s" % (f[0], f[1], f[2], f[3], f[4], "capped" if f[5] else "NO TOP"))
