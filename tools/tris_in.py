# tris_in.py <scene> x0 x1 y0 y1 z0 z1: the collision triangles inside a box, with their facing
import re, sys, math
D = r"E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/Scripts/data/"
sc = sys.argv[1]; x0, x1, y0, y1, z0, z1 = [float(a) for a in sys.argv[2:8]]
s = open(D + "scene_%s.lua" % sc, encoding="utf-8", errors="replace").read()
c = s[s.find("collision = {"):]
n = 0
for m in re.finditer(r"pos = \{([^}]*)\},\s*idx = \{([^}]*)\}", c):
    pos = [float(x) for x in m.group(1).split(",") if x.strip()]
    idx = [int(x) for x in m.group(2).split(",") if x.strip()]
    for t in range(0, len(idx) - 2, 3):
        v = [tuple(pos[idx[t + k] * 3: idx[t + k] * 3 + 3]) for k in range(3)]
        cx, cy, cz = [sum(p[i] for p in v) / 3 for i in range(3)]
        if not (x0 <= cx <= x1 and y0 <= cy <= y1 and z0 <= cz <= z1): continue
        (ax, ay, az), (bx, by, bz), (qx, qy, qz) = v
        ux, uy, uz = bx - ax, by - ay, bz - az; wx, wy, wz = qx - ax, qy - ay, qz - az
        nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
        L = math.sqrt(nx * nx + ny * ny + nz * nz) or 1
        # (the scene is Mario 64 mirrored: the true facing is minus the cross product)
        nx, ny, nz = -nx / L, -ny / L, -nz / L
        kind = "floor" if nz > 0.45 else ("ceiling" if nz < -0.45 else "wall")
        print("%-7s facing (%5.2f,%5.2f,%5.2f)  %s" % (kind, nx, ny, nz, " ".join("(%.0f,%.0f,%.0f)" % p for p in v)))
        n += 1
print(n, "triangles")
