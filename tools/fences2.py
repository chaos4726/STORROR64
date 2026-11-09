# fences2.py <scene...>: single upright walls whose top edge is open (no floor on or just beside it) with ground
# 25-160 cm below the top on BOTH sides - fences STORROR could vault if they had a top
import re, sys, math
D = r"E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/Scripts/data/"
CELL = 200.0
for scene in sys.argv[1:]:
    try: s = open(D + "scene_%s.lua" % scene, encoding="utf-8", errors="replace").read()
    except OSError: print(scene, "no data"); continue
    c = s[s.find("collision = {"):]
    tris = []
    for m in re.finditer(r"pos = \{([^}]*)\},\s*idx = \{([^}]*)\}", c):
        pos = [float(x) for x in m.group(1).split(",") if x.strip()]
        idx = [int(x) for x in m.group(2).split(",") if x.strip()]
        for t in range(0, len(idx) - 2, 3):
            tris.append([tuple(pos[idx[t + k] * 3: idx[t + k] * 3 + 3]) for k in range(3)])
    walls, floors, fgrid = [], [], {}
    for v in tris:
        (ax, ay, az), (bx, by, bz), (cx, cy, cz) = v
        ux, uy, uz = bx - ax, by - ay, bz - az; wx, wy, wz = cx - ax, cy - ay, cz - az
        nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
        L = math.sqrt(nx * nx + ny * ny + nz * nz)
        if L < 1e-6: continue
        if abs(nz / L) < 0.45: walls.append(v)
        else:
            floors.append(v)
            for i in range(int(min(ax, bx, cx) // CELL), int(max(ax, bx, cx) // CELL) + 1):
                for j in range(int(min(ay, by, cy) // CELL), int(max(ay, by, cy) // CELL) + 1):
                    fgrid.setdefault((i, j), []).append(v)
    def floor_in(x, y, z0, z1):
        for v in fgrid.get((int(x // CELL), int(y // CELL)), []):
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
    ecount = {}
    for v in walls:
        for k in range(3):
            e = tuple(sorted((key(v[k]), key(v[(k + 1) % 3]))))
            ecount[e] = ecount.get(e, 0) + 1
    out, total = [], 0.0
    for v in walls:
        for k in range(3):
            p, q, r = v[k], v[(k + 1) % 3], v[(k + 2) % 3]
            e = tuple(sorted((key(p), key(q))))
            L = math.hypot(q[0] - p[0], q[1] - p[1])
            if ecount[e] != 1 or L < 40: continue
            t = ((r[0] - p[0]) * (q[0] - p[0]) + (r[1] - p[1]) * (q[1] - p[1])) / (L * L)
            if not (r[2] < p[2] + (q[2] - p[2]) * t - 20): continue        # a top edge
            ex, ey = (q[0] - p[0]) / L, (q[1] - p[1]) / L; nx, ny = ey, -ex
            mx, my, mz = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2, (p[2] + q[2]) / 2
            if any(floor_in(mx + nx * d * sg, my + ny * d * sg, mz - 10, mz + 40) for sg in (1, -1) for d in (5, 20, 40)): continue
            low = all(floor_in(mx + nx * 40 * sg, my + ny * 40 * sg, mz - 160, mz - 25) for sg in (1, -1))
            if low: out.append((round(mx), round(my), round(mz), round(L))); total += L
    if len(sys.argv) == 2:
        for o in out: print("   at %d,%d top %d, %d cm long" % o)
    print("%-8s %3d open-topped fence edges, %5.0f m in all%s" % (scene, len(out), total / 100, ("  e.g. " + "; ".join("%d,%d,%d" % o[:3] for o in out[:3])) if out else ""))
