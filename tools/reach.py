"""Reachability over a scene's collision (scene cm, z up), for the athlete.

    python tools/reach.py bbh                     # the athlete: climbs 160, vaults railings, 2 m running jumps
    python tools/reach.py ssl --up 160 250 --gap  # more than one climb height; for what is not reached, the gap
    python tools/reach.py ssl_2 --start node:20   # start at a warp node instead of the spawn (or x,y,z)

Walks a grid of columns: each column's standable floors (walkable: normal z >= 0.5, i.e. 60 degrees as the mod sets
STORROR's walkable angle; headroom --head to the next surface above; not instant-death quicksand). From a floor a
neighbour column's floor can be reached if it is at most UP higher (a step, a jump, a climb) and at most --down lower
(a drop), with no wall between at body height over the higher of the two (--vault: low walls are gone over); --leap:
running jumps across gaps. Targets come from the scene's data - stars, secrets, red coins, ! boxes, poles - and from
EXTRA below, which also adds floors (moving platforms) and links (elevators) the collision does not have.
"""
import argparse
import math
import re
from collections import deque

DATA = r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map\Scripts\data"
S = 0.75

# per scene: extra floor boxes (x0, y0, x1, y1, top), links ((x, y, z) <-> (x, y, z)) and targets {name: (x, y, z)}
EXTRA = {
    "bbh": {
        # the hall's three steps (bhvHiddenStaircaseStep / bhvBooStaircase), tops measured standing on them
        "boxes": [(-763, 530, -613, 930, 149), (-613, 530, -463, 930, 304), (-463, 530, -313, 930, 459),
                  # the steps added up the far right room to the 3rd floor landing (game.lua G.EXTRA_OBJECTS.bbh)
                  (-376, 2325, -224, 2555, 920), (-376, 2110, -224, 2340, 1075), (-376, 1895, -224, 2125, 1230),
                  # the mesh elevator, up and down
                  (-4200, -2390, -3900, -2090, -154), (-4200, -2390, -3900, -2090, -1770)],
        # the mesh elevator outside: Mario 64's -205 down to -2360 (bhvMeshElevator, sElevatorHeights[4])
        "links": [((-4050, -2239, -154), (-4050, -2239, -1770))],
        "targets": {
            "bbh:0 hall star (act 1, from the Big Boo)": (-188, 735, 825),
            "bbh:1 merry-go-round star (act 2, from the Big Boo)": (-154, -1200, -1575),
            "bbh:4 balcony star (act 5, from the Big Boo)": (-1425, 525, 2400),
            "bbh:5 big Mr. I star (act 6)": (240, 1027, 1500),
            "big Mr. I": (249, 692, 1306),
        },
    },
    "ssl_2": {
        # the four moving pyramid walls (bhvSSLMovingPyramidWall): lifts 460 x 95, tops 384 over their origin, which goes
        # 512 Mario units (384 cm) down from its place and back: a floor at each end, joined
        "boxes": [(1500, 597, 1960, 691, 1445), (1500, 597, 1960, 691, 1829), (1500, 501, 1960, 595, 1445), (1500, 501, 1960, 595, 1829),
                  (1500, 1058, 1960, 1152, 1925), (1500, 1058, 1960, 1152, 2309), (1500, 962, 1960, 1056, 1925), (1500, 962, 1960, 1056, 2309),
                  # the pyramid elevator (bhvPyramidElevator): at the top hole, and down at 128
                  (-576, -384, 192, 384, 3916), (-576, -384, 192, 384, 288),
                  # the first Grindel (bhvGrindel, thwomp.lua): down, its top 338 over the floor - between the upper path's
                  # two halves, 142 under them
                  (-239, 2305, 97, 2641, 338),
                  # the two poles' tops (a perch to leap from)
                  (-2210, 2090, -2090, 2210, 1250), (-1058, -60, -938, 60, 3320)],
        "links": [((1730, 644, 1445), (1730, 644, 1829)), ((1730, 548, 1445), (1730, 548, 1829)),
                  ((1730, 1105, 1925), (1730, 1105, 2309)), ((1730, 1009, 1925), (1730, 1009, 2309)),
                  ((-192, 0, 3916), (-192, 0, 288)),
                  # the poles: climbed from their foot to their top
                  ((-2150, 2150, 480), (-2150, 2150, 1250)), ((-998, 0, 2400), (-998, 0, 3320))],
    },
    "ssl": {
        "targets": {
            # the four pillars about the pyramid (platforms.lua PYRAMID_PILLARS: Mario 64's pillar touch detectors)
            "pillar 1 top": (-573, 1342, 768 + 60), "pillar 2 top": (1934, 1342, 672 + 60),
            "pillar 3 top": (1934, -4412, 768 + 60), "pillar 4 top": (-573, -4412, 768 + 60),
            # where Klepto's star goes when he is hit (enemies.lua KLEPTO_STAR_AT: Mario 64's (-5550, 300, -930))
            "Klepto's star (act 1)": (697, -4162, 225),
        },
    },
}


def block(s, key):
    """the text of a top-level `key = ...` entry of a scene file"""
    i = s.find("\n  %s = " % key)
    if i < 0:
        return ""
    m = re.search(r"\n  [a-z_]+ = ", s[i + 5:])
    return s[i:i + 5 + (m.start() if m else len(s))]


def tris_of(pos, idx):
    out = []
    for t in range(0, len(idx) - 2, 3):
        a, b, c = idx[t:t + 3]
        out.append((tuple(pos[a * 3:a * 3 + 3]), tuple(pos[b * 3:b * 3 + 3]), tuple(pos[c * 3:c * 3 + 3])))
    return out


def nums(text):
    return [float(v) for v in text.split(",") if v.strip()]


def load_scene(name):
    s = open(f"{DATA}\\scene_{name}.lua", encoding="utf-8").read()
    sc = {"name": name}
    m = re.search(r"spawn = \{\s*pos = \{([^}]*)\}", s)
    sc["spawn"] = tuple(nums(m.group(1))) if m else None
    sc["nodes"] = {int(m.group(1)): tuple(nums(m.group(2)))
                   for m in re.finditer(r"id = (\d+),\s*pos = \{([^}]*)\}", block(s, "nodes"))}
    # the level's collision (every entry of its list; the objects' templates come later in the file)
    tris = []
    for m in re.finditer(r"pos = \{([^}]*)\},\s*idx = \{([^}]*)\}", block(s, "collision")):
        tris += tris_of(nums(m.group(1)), [int(v) for v in nums(m.group(2))])
    sc["tris"] = tris
    # tagged floors (quicksand, sinking sand, instant warps)
    sc["tagged"] = []
    for m in re.finditer(r'tag = "([^"]+)",\s*ntris = \d+,\s*pos = \{([^}]*)\},\s*idx = \{([^}]*)\}', block(s, "floors")):
        for t in tris_of(nums(m.group(2)), [int(v) for v in nums(m.group(3))]):
            sc["tagged"].append((m.group(1), t))
    # targets from the objects: name -> (x, y, z, lo, hi): reached if a reached floor within 110 cm across is lo..hi
    # under it
    tg = {}
    objs = block(s, "objects")
    for m in re.finditer(r"\{\s*kind = \"([a-z_]+)\",(.*?)\n    \}", objs, re.S):
        kind, body = m.group(1), m.group(2)
        p = re.search(r"pos = \{([^}]*)\}", body)
        if not p:
            continue
        x, y, z = nums(p.group(1))[:3]
        idm = re.search(r"\bid = (\d+)", body)
        sid = idm.group(1) if idm else "?"
        if kind in ("star", "red_coin_star", "secret_star"):
            tg[f"{name}: {kind} {sid}"] = (x, y, z, -100.0, 320.0)
        elif kind == "secret_trigger" and '"star"' in body:
            tg[f"{name}: secret at {x:.0f} {y:.0f} {z:.0f}"] = (x, y, z, -100.0, 250.0)
        elif kind == "coin" and "red = true" in body:
            tg[f"{name}: red coin at {x:.0f} {y:.0f} {z:.0f}"] = (x, y, z, -100.0, 250.0)
        elif kind == "box" and "bhvExclamationBox" in body:
            pre = re.search(r'preset = "([^"]+)"', body)
            tg[f"{name}: {pre.group(1) if pre else 'box'} at {x:.0f} {y:.0f} {z:.0f}"] = (x, y, z, -100.0, 400.0)
        elif kind == "pole":
            tg[f"{name}: pole at {x:.0f} {y:.0f} {z:.0f}"] = (x, y, z, -100.0, 200.0)
    for k, v in EXTRA.get(name, {}).get("targets", {}).items():
        tg[k] = (v[0], v[1], v[2], -100.0, 320.0)
    sc["targets"] = tg
    return sc


def normal(t):
    (ax, ay, az), (bx, by, bz), (cx, cy, cz) = t
    ux, uy, uz = bx - ax, by - ay, bz - az
    wx, wy, wz = cx - ax, cy - ay, cz - az
    nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
    l = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    # (the scene's axes are Mario 64's mirrored - x from -z - so every triangle's winding is flipped: the normal is
    # the other way)
    return -nx / l, -ny / l, -nz / l


class Grid:
    def __init__(self, tris, cell=200.0):
        self.cell, self.map = cell, {}
        for i, t in enumerate(tris):
            xs, ys = [p[0] for p in t], [p[1] for p in t]
            for gx in range(int(math.floor(min(xs) / cell)), int(math.floor(max(xs) / cell)) + 1):
                for gy in range(int(math.floor(min(ys) / cell)), int(math.floor(max(ys) / cell)) + 1):
                    self.map.setdefault((gx, gy), []).append(i)

    def near(self, x, y):
        return self.map.get((int(math.floor(x / self.cell)), int(math.floor(y / self.cell))), [])

    def along(self, x0, y0, x1, y1):
        out = set()
        n = int(max(abs(x1 - x0), abs(y1 - y0)) / (self.cell * 0.5)) + 1
        for k in range(n + 1):
            f = k / n
            out.update(self.near(x0 + (x1 - x0) * f, y0 + (y1 - y0) * f))
        return out


def z_at(t, x, y):
    """the triangle's height over (x, y), or None if (x, y) is not inside it (seen from above)"""
    (ax, ay, az), (bx, by, bz), (cx, cy, cz) = t
    d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(d) < 1e-9:
        return None
    l1 = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / d
    l2 = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / d
    l3 = 1.0 - l1 - l2
    if l1 < -1e-6 or l2 < -1e-6 or l3 < -1e-6:
        return None
    return l1 * az + l2 * bz + l3 * cz


def seg_hits(t, p, q):
    """segment p-q crosses triangle t (Moller-Trumbore)"""
    (ax, ay, az), (bx, by, bz), (cx, cy, cz) = t
    dx, dy, dz = q[0] - p[0], q[1] - p[1], q[2] - p[2]
    e1 = (bx - ax, by - ay, bz - az)
    e2 = (cx - ax, cy - ay, cz - az)
    h = (dy * e2[2] - dz * e2[1], dz * e2[0] - dx * e2[2], dx * e2[1] - dy * e2[0])
    a = e1[0] * h[0] + e1[1] * h[1] + e1[2] * h[2]
    if abs(a) < 1e-9:
        return False
    f = 1.0 / a
    s = (p[0] - ax, p[1] - ay, p[2] - az)
    u = f * (s[0] * h[0] + s[1] * h[1] + s[2] * h[2])
    if u < 0.0 or u > 1.0:
        return False
    qv = (s[1] * e1[2] - s[2] * e1[1], s[2] * e1[0] - s[0] * e1[2], s[0] * e1[1] - s[1] * e1[0])
    v = f * (dx * qv[0] + dy * qv[1] + dz * qv[2])
    if v < 0.0 or u + v > 1.0:
        return False
    tt = f * (e2[0] * qv[0] + e2[1] * qv[1] + e2[2] * qv[2])
    return 0.0 <= tt <= 1.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scene")
    ap.add_argument("--up", type=float, nargs="+", default=[160.0], help="climb heights to try (cm)")
    ap.add_argument("--down", type=float, default=800.0)
    ap.add_argument("--cell", type=float, default=50.0)
    ap.add_argument("--head", type=float, default=160.0)
    ap.add_argument("--leap", type=float, default=200.0, help="running jumps across gaps up to this many cm (0: none)")
    ap.add_argument("--leap-up", type=float, default=50.0, help="how much higher a running jump may land (a caught ledge)")
    ap.add_argument("--no-vault", action="store_true", help="railings and other low walls block (else they are vaulted)")
    ap.add_argument("--start", action="append", help="spawn (default), node:<id> or x,y,z - may be given more than once")
    ap.add_argument("--climbs", action="store_true", help="list the climbs over 2 m on the way to each target")
    ap.add_argument("--gap", action="store_true", help="for each target not reached: the smallest climbs that would reach it")
    ap.add_argument("--gap-low", type=int, default=0, help="with --gap: list this many of the lowest floors that lead to it")
    ap.add_argument("--only", default="", help="only targets whose name holds this")
    ap.add_argument("--probe", action="append", help="x,y: list the floors near there and which are reached")
    a = ap.parse_args()
    sc = load_scene(a.scene)
    tris = sc["tris"]
    ex = EXTRA.get(a.scene, {})
    norms = [normal(t) for t in tris]
    floors = [i for i, n in enumerate(norms) if n[2] >= 0.5]
    over = [i for i, n in enumerate(norms) if abs(n[2]) >= 0.1]     # anything over him that takes headroom
    walls = [i for i, n in enumerate(norms) if abs(n[2]) < 0.5]
    gf, go, gw = Grid([tris[i] for i in floors]), Grid([tris[i] for i in over]), Grid([tris[i] for i in walls])
    tagged = sc["tagged"]
    gt = Grid([t for _, t in tagged])
    allp = [p for t in tris for p in t]
    x0, x1 = min(p[0] for p in allp), max(p[0] for p in allp)
    y0, y1 = min(p[1] for p in allp), max(p[1] for p in allp)
    C = a.cell
    nx, ny = int((x1 - x0) / C) + 1, int((y1 - y0) / C) + 1

    def cxy(i, j):
        return x0 + (i + 0.5) * C, y0 + (j + 0.5) * C

    def tag_at(x, y, h):
        for k in gt.near(x, y):
            z = z_at(tagged[k][1], x, y)
            if z is not None and abs(z - h) < 2.0:
                return tagged[k][0]
        return None

    # each column's floors (sorted), with headroom, without the quicksand that swallows him at once
    col, warps = {}, {}
    for i in range(nx):
        for j in range(ny):
            x, y = cxy(i, j)
            hs = sorted({round(z, 1) for k in gf.near(x, y) for z in [z_at(tris[floors[k]], x, y)] if z is not None})
            for b in ex.get("boxes", []):
                if b[0] <= x <= b[2] and b[1] <= y <= b[3]:
                    hs = sorted(set(hs) | {float(b[4])})
            if not hs:
                continue
            ups = sorted(z for k in go.near(x, y) for z in [z_at(tris[over[k]], x, y)] if z is not None)
            keep = []
            for h in hs:
                tg = tag_at(x, y, h)
                if tg and tg.startswith("quicksand"):
                    continue
                if tg and tg.startswith("instant:"):
                    warps[(i, j, h)] = tg
                above = [z for z in ups if z > h + 5.0]
                if not above or above[0] - h >= a.head:
                    keep.append(h)
            if keep:
                col[(i, j)] = keep
    # hangable ceilings (hang.lua): hanging, his feet 185 under one; taken hold of from a floor up to 300 under it (a
    # jump into it), moved along under it, let go of to drop
    hang = set()
    hang_tris = [t for tg, t in tagged if tg == "hang"]
    if hang_tris:
        gh = Grid(hang_tris)
        for i in range(nx):
            for j in range(ny):
                x, y = cxy(i, j)
                for k in gh.near(x, y):
                    c = z_at(hang_tris[k], x, y)
                    if c is not None:
                        feet = round(c - 185.0, 1)
                        col[(i, j)] = sorted(set(col.get((i, j), [])) | {feet})
                        hang.add((i, j, feet))
    print(f"{a.scene}: {len(tris)} tris, {nx}x{ny} columns, {sum(len(v) for v in col.values())} standable floors, {len(hang)} hanging spots")

    wall_cache = {}

    def clear(p, q):
        key = (round(p[0]), round(p[1]), round(p[2]), round(q[0]), round(q[1]), round(q[2]))
        r = wall_cache.get(key)
        if r is None:
            r = not any(seg_hits(tris[walls[k]], p, q) for k in gw.along(p[0], p[1], q[0], q[1]))
            wall_cache[key] = r
        return r

    def walls_ok(u, v):
        (x, y), (x2, y2) = cxy(u[0], u[1]), cxy(v[0], v[1])
        top = max(u[2], v[2])
        hb = min(150.0, a.head - 10.0)
        # (a low wall - a railing - is vaulted: clear at body height is enough)
        low = (not a.no_vault) or clear((x, y, top + 60.0), (x2, y2, top + 60.0))
        return low and clear((x, y, top + hb), (x2, y2, top + hb))

    def node_at(x, y, z, up=60.0):
        i, j = int((x - x0) / C), int((y - y0) / C)
        best = None
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                for h in col.get((i + di, j + dj), []):
                    if h <= z + up and (best is None or h > best[2]):
                        best = (i + di, j + dj, h)
        return best

    def gap(seen, UP, tx, ty, tz, lo, hi, r=110.0):
        goal = {(i, j, h) for (i, j), hs in col.items() for h in hs
                if (cxy(i, j)[0] - tx) ** 2 + (cxy(i, j)[1] - ty) ** 2 <= r * r and lo <= tz - h <= hi}
        back = set(goal)
        dq = deque(goal)
        while dq:
            v = dq.popleft()
            for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nb = (v[0] + di, v[1] + dj)
                for g in col.get(nb, []):
                    u = (nb[0], nb[1], g)
                    dz = v[2] - g
                    if u in back or dz > UP or -dz > a.down:
                        continue
                    if walls_ok(u, v):
                        back.add(u)
                        dq.append(u)
        cands = []
        for v in back:
            for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nb = (v[0] + di, v[1] + dj)
                for g in col.get(nb, []):
                    u = (nb[0], nb[1], g)
                    if u in seen and v[2] - g > UP and walls_ok(u, v):
                        cands.append((v[2] - g, u, v))
        cands.sort()
        if a.gap_low:
            lows = sorted(back, key=lambda n: n[2])[:a.gap_low]
            print("        lowest floors that lead to it:", [(round(cxy(n[0], n[1])[0]), round(cxy(n[0], n[1])[1]), n[2]) for n in lows])
        return len(back), cands

    starts = []
    for st in (a.start or ["spawn"]):
        if st == "spawn":
            p = sc["spawn"]
        elif st.startswith("node:"):
            p = sc["nodes"][int(st[5:])]
        else:
            p = tuple(float(v) for v in st.split(","))
        n = node_at(p[0], p[1], p[2], 0.0)
        print("start", st, p, "->", n)
        if n:
            starts.append(n)
    for UP in a.up:
        seen = set(starts)
        parent = {s: None for s in starts}
        dq = deque(starts)

        def reach(n, frm):
            if n not in seen:
                seen.add(n)
                parent[n] = frm
                dq.append(n)

        while dq:
            i, j, h = dq.popleft()
            x, y = cxy(i, j)
            for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nb = (i + di, j + dj)
                for g in col.get(nb, []):
                    dz = g - h
                    if dz > UP or -dz > a.down:
                        continue
                    n = (nb[0], nb[1], g)
                    if n not in seen and walls_ok((i, j, h), n):
                        reach(n, (i, j, h))
            # (up into a hangable ceiling over him, or let go of it onto what is under him)
            for g in col.get((i, j), []):
                n = (i, j, g)
                if n in seen or g == h:
                    continue
                if (n in hang and 0.0 < g - h <= 115.0) or ((i, j, h) in hang and 0.0 < h - g <= a.down):
                    reach(n, (i, j, h))
            # (a running jump across a gap, up to --leap, landing at most --leap-up higher)
            if a.leap > 0:
                k = int(a.leap / C)
                for di in range(-k, k + 1):
                    for dj in range(-k, k + 1):
                        if max(abs(di), abs(dj)) < 2 or (di * di + dj * dj) * C * C > a.leap * a.leap:
                            continue
                        nb = (i + di, j + dj)
                        for g in col.get(nb, []):
                            if g - h > a.leap_up or h - g > a.down:
                                continue
                            n = (nb[0], nb[1], g)
                            if n in seen:
                                continue
                            x2, y2 = cxy(*nb)
                            top = max(h, g)
                            if clear((x, y, top + 60.0), (x2, y2, top + 60.0)) and clear((x, y, top + 150.0), (x2, y2, top + 150.0)):
                                reach(n, (i, j, h))
            for l0, l1 in ex.get("links", []):
                for s0, s1 in ((l0, l1), (l1, l0)):
                    if node_at(*s0) == (i, j, h):
                        n1 = node_at(*s1)
                        if n1:
                            reach(n1, (i, j, h))
        print(f"\nUP {UP:.0f} cm: {len(seen)} floors reached")
        hit = sorted({warps[n] for n in seen if n in warps})
        if hit:
            print("  warp floors reached:", hit)

        def under(tx, ty, tz, lo, hi, r=110.0):
            best = None
            for (i, j, h) in seen:
                x, y = cxy(i, j)
                if (x - tx) ** 2 + (y - ty) ** 2 <= r * r and lo <= tz - h <= hi:
                    if best is None or tz - h < best[0]:
                        best = (tz - h, (i, j, h))
            return best

        def path_climbs(n):
            out = []
            while parent.get(n):
                pn = parent[n]
                if n[2] - pn[2] > 200.0:
                    out.append((round(cxy(pn[0], pn[1])[0]), round(cxy(pn[0], pn[1])[1]), pn[2], n[2]))
                n = pn
            return out

        for pr in (a.probe or []):
            px, py = (float(v) for v in pr.split(","))
            here = sorted({h for (i, j), hs in col.items() for h in hs
                           if (cxy(i, j)[0] - px) ** 2 + (cxy(i, j)[1] - py) ** 2 <= 150.0 ** 2})
            got = sorted({h for (i, j, h) in seen if (cxy(i, j)[0] - px) ** 2 + (cxy(i, j)[1] - py) ** 2 <= 150.0 ** 2})
            print(f"  probe {pr}: floors {here}, reached {got}")
        for name, (tx, ty, tz, lo, hi) in sc["targets"].items():
            if a.only and a.only not in name:
                continue
            b = under(tx, ty, tz, lo, hi)
            print(f"  {'OK ' if b else 'NO '} {name}" + (f" ({b[0]:.0f} cm over the floor)" if b else ""))
            if b and a.climbs:
                print("        climbs over 2 m on the way:", path_climbs(b[1]))
            if not b and a.gap:
                nb, cands = gap(seen, UP, tx, ty, tz, lo, hi)
                print(f"        {nb} floors lead to it; smallest climbs into them from what is reached:")
                shown = set()
                for dz, u, v in cands:
                    key = (round(cxy(u[0], u[1])[0] / 200.0), round(cxy(u[0], u[1])[1] / 200.0), round(u[2] / 50.0))
                    if key in shown:
                        continue
                    shown.add(key)
                    print(f"          +{dz:.0f} cm: from {cxy(u[0], u[1])[0]:.0f} {cxy(u[0], u[1])[1]:.0f} {u[2]:.0f} up to {v[2]:.0f}")
                    if len(shown) >= 6:
                        break


if __name__ == "__main__":
    main()
