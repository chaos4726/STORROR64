# railgeo.py <scene> <texture part>: the triangles drawn with that texture, as upright panels (bottom line, height)
import re, sys, math
D = r"E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/Scripts/data/"
s = open(D + "scene_%s.lua" % sys.argv[1], encoding="utf-8", errors="replace").read()
sec = s[:s.find("collision = {")]
blocks = re.split(r"\n    \{\n", sec)
panels = []
for b in blocks:
    m = re.search(r'texture = "([^"]*)"', b)
    if not m or sys.argv[2] not in m.group(1): continue
    pm = re.search(r"\bpos = \{([^}]*)\}", b); im = re.search(r"\bidx = \{([^}]*)\}", b)
    pos = [float(x) for x in pm.group(1).split(",") if x.strip()]
    idx = [int(x) for x in im.group(1).split(",") if x.strip()]
    for t in range(0, len(idx) - 2, 3):
        v = [tuple(pos[idx[t + k] * 3: idx[t + k] * 3 + 3]) for k in range(3)]
        (ax, ay, az), (bx, by, bz), (cx, cy, cz) = v
        ux, uy, uz = bx - ax, by - ay, bz - az; wx, wy, wz = cx - ax, cy - ay, cz - az
        nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
        L = math.sqrt(nx * nx + ny * ny + nz * nz)
        panels.append((v, nz / L if L else 0))
print(len(panels), "triangles")
up = [p for p in panels if abs(p[1]) < 0.3]
print(len(up), "upright")
for v, nz in up[:400:8]:
    zs = sorted(p[2] for p in v)
    xy = sorted(set((round(p[0]), round(p[1])) for p in v))
    print("  %s  z %d..%d" % (xy, zs[0], zs[-1]))

# panels by their upright plane: (normal angle, offset) -> extent along it and in height
groups = {}
for v, nz in up:
    (ax, ay, az), (bx, by, bz), (cx, cy, cz) = v
    ux, uy = bx - ax, by - ay; wx, wy = cx - ax, cy - ay
    # horizontal direction of the panel: its longest horizontal edge
    best = max(((v[i], v[j]) for i, j in ((0, 1), (1, 2), (0, 2))), key=lambda e: math.hypot(e[1][0] - e[0][0], e[1][1] - e[0][1]))
    dx, dy = best[1][0] - best[0][0], best[1][1] - best[0][1]
    L = math.hypot(dx, dy)
    if L < 5: continue
    ang = math.degrees(math.atan2(dy, dx)) % 180
    nx, ny = -dy / L, dx / L
    off = nx * ax + ny * ay
    if ang > 179: ang -= 180
    k = (round(ang / 3), round(off / 10))
    g = groups.setdefault(k, {"ang": ang, "off": off, "t0": 1e9, "t1": -1e9, "z0": 1e9, "z1": -1e9, "n": 0, "dir": (dx / L, dy / L)})
    ex, ey = g["dir"]
    for p in v:
        t = p[0] * ex + p[1] * ey
        g["t0"], g["t1"] = min(g["t0"], t), max(g["t1"], t)
        g["z0"], g["z1"] = min(g["z0"], p[2]), max(g["z1"], p[2])
    g["n"] += 1
print("panel lines:")
for k, g in sorted(groups.items(), key=lambda kv: -kv[1]["n"]):
    ex, ey = g["dir"]; nx, ny = -ey, ex
    a = (nx * g["off"] + ex * g["t0"], ny * g["off"] + ey * g["t0"]); b = (nx * g["off"] + ex * g["t1"], ny * g["off"] + ey * g["t1"])
    print("  %4d tris  (%6.0f,%6.0f)-(%6.0f,%6.0f) len %5.0f  z %5.0f..%5.0f" % (g["n"], a[0], a[1], b[0], b[1], g["t1"] - g["t0"], g["z0"], g["z1"]))
