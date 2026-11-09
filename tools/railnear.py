# railnear.py <scene> x y [r]: every open top edge of a wall near (x, y) and what each fence test says about it
import re, sys, math
D = r"E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/Scripts/data/"
scene, X, Y = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]); R = float(sys.argv[4]) if len(sys.argv) > 4 else 600
s = open(D + "scene_%s.lua" % scene, encoding="utf-8", errors="replace").read()
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
    (walls if abs(nz / L) < 0.45 else floors).append(v)
def floor_in(x, y, z0, z1):
    for v in floors:
        (ax, ay, az), (bx, by, bz), (cx, cy, cz) = v
        d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(d) < 1e-9: continue
        l1 = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / d
        l2 = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / d
        l3 = 1 - l1 - l2
        if l1 >= -1e-4 and l2 >= -1e-4 and l3 >= -1e-4:
            z = l1 * az + l2 * bz + l3 * cz
            if z0 <= z <= z1: return True
    return False
key = lambda p: (round(p[0], 1), round(p[1], 1), round(p[2], 1))
ec = {}
for v in walls:
    for k in range(3):
        e = tuple(sorted((key(v[k]), key(v[(k + 1) % 3])))); ec[e] = ec.get(e, 0) + 1
seen = set()
for v in walls:
    for k in range(3):
        p, q, r = v[k], v[(k + 1) % 3], v[(k + 2) % 3]
        mx, my, mz = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2, (p[2] + q[2]) / 2
        if math.hypot(mx - X, my - Y) > R: continue
        L = math.hypot(q[0] - p[0], q[1] - p[1])
        if L < 1: continue
        t = ((r[0] - p[0]) * (q[0] - p[0]) + (r[1] - p[1]) * (q[1] - p[1])) / (L * L)
        top = r[2] < p[2] + (q[2] - p[2]) * t - 20
        if not top: continue
        e = tuple(sorted((key(p), key(q))))
        if e in seen: continue
        seen.add(e)
        ex, ey = (q[0] - p[0]) / L, (q[1] - p[1]) / L; nx, ny = ey, -ex
        capped = any(floor_in(mx + nx * d * sg, my + ny * d * sg, mz - 10, mz + 40) for sg in (1, -1) for d in (5, 20, 40))
        both = all(floor_in(mx + nx * 40 * sg, my + ny * 40 * sg, mz - 160, mz - 25) for sg in (1, -1))
        print("(%5.0f,%5.0f,%4.0f)-(%5.0f,%5.0f,%4.0f) len %4.0f shared %d floor-at-top %s ground-both-sides %s" % (p[0], p[1], p[2], q[0], q[1], q[2], L, ec[e], capped, both))
