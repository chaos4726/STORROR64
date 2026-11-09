# r96_stardoor.py : the castle's big star doors (the 8, 30, 50 and 70 star doors, to Bowser) for RENDER 96. Render96 has
# no model of them - they are two flat leaves with a star painted across them (castle_geo_000F00: castle_inside 5 and 6,
# half a star each) - "bowser doors not 3d", 2026-10-31. Made here from Mario 64's leaf and Render96's star door: the
# leaf's faces plain wood (castle_inside 7, the rest of the leaf's), and on each face half of Render96's gold 3D star
# (door_star0's - the numbered doors' have the number cut into it - its knobs left off), as big as the painted one and where it was, cut at the leaves' seam and
# closed there. The other leaf is the same model turned round, so the two halves make one star.
# Written to data_r96/actor_stardoor_castle_geo_000F00.lua (lib.load_data takes it while RENDER 96 is on).
import os, math, collections
import lupa

SCR = r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map\Scripts"
OUT = os.path.join(SCR, "data_r96", "actor_stardoor_castle_geo_000F00.lua")
WOOD = "levels__castle_inside__7.rgba16"
# (the leaf in red metal - Render96's metal door plate in red, tools/r96_redmetal.py: "bowser door should be some sort of
# red metal", 2026-10-31 - its faces and its edges)
METAL = "stardoor_red_metal"
PAINTED = {"levels__castle_inside__5.rgba16", "levels__castle_inside__6.rgba16"}
GOLD = "actors__door__door_knob_gold.rgba32"
# the painted star on the leaf (from castle_inside 5's yellow, mapped onto the face): its tip 97.5 cm in from the seam,
# 119 cm tall about 99 cm up
SEAM, TALL, MIDZ = 59.25, 119.0, 99.0

L = lupa.LuaRuntime()
def load(path):
    return L.eval("loadfile")(path)()
def tolist(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []

door = load(os.path.join(SCR, "data", "actor_stardoor_castle_geo_000F00.lua"))
star = load(os.path.join(SCR, "data_r96", "actor_door_star0.lua"))   # (its star whole: the 1 and 3 doors cut theirs for the number)

# Render96's gold: the door's knobs and its stars (front and back), apart by what joins them
gold = None
for pi in range(1, len(star.parts) + 1):
    for si in range(1, len(star.parts[pi].sections) + 1):
        s = star.parts[pi].sections[si]
        if s.texture == GOLD:
            gold = s
P = tolist(gold.pos); UV = tolist(gold.uv); C = tolist(gold.col); N = tolist(gold.nrm); I = tolist(gold.idx)
nv = len(P) // 3
parent = list(range(nv))
def find(a):
    while parent[a] != a:
        parent[a] = parent[parent[a]]
        a = parent[a]
    return a
byp = {}
for v in range(nv):
    k = tuple(round(x, 1) for x in P[v * 3:v * 3 + 3])
    if k in byp:
        parent[find(v)] = find(byp[k])
    else:
        byp[k] = v
for t in range(0, len(I), 3):
    a, b, c = I[t:t + 3]
    parent[find(b)] = find(a); parent[find(c)] = find(a)
comps = collections.defaultdict(list)
for t in range(0, len(I), 3):
    comps[find(I[t])].append(I[t:t + 3])
stars = {}
for root, tris in comps.items():
    vs = sorted(set(v for tr in tris for v in tr))
    xs = [P[v * 3] for v in vs]; ys = [P[v * 3 + 1] for v in vs]; zs = [P[v * 3 + 2] for v in vs]
    if max(zs) - min(zs) < 40:
        continue                          # (a knob)
    side = -1 if sum(xs) / len(xs) < 0 else 1
    stars.setdefault(side, []).append((tris, vs))
print("stars found:", {k: sum(len(t) for t, _ in v) for k, v in stars.items()})

def bounds(parts):
    vs = [v for _, vv in parts for v in vv]
    return ([min(P[v * 3 + k] for v in vs) for k in range(3)], [max(P[v * 3 + k] for v in vs) for k in range(3)])

out_secs = []
for side, parts in sorted(stars.items()):
    lo, hi = bounds(parts)
    yc, zc = (lo[1] + hi[1]) / 2.0, (lo[2] + hi[2]) / 2.0
    s = TALL / (hi[2] - lo[2])
    base = hi[0] if side < 0 else lo[0]          # (the star's back, on the door's face)
    face = 11.25 * side
    def xf(v):
        x, y, z = P[v * 3:v * 3 + 3]
        return [face + (x - base) * s, SEAM + (y - yc) * s, MIDZ + (z - zc) * s]
    pos, uv, col, nrm, idx = [], [], [], [], []
    def put(p, t, c, n):
        pos.extend(p); uv.extend(t); col.extend(c); nrm.extend(n)
        return len(pos) // 3 - 1
    cut = []                                     # (the edges the seam cuts, for closing it)
    for tris, _ in parts:
        for tr in tris:
            poly = [(xf(v), UV[v * 2:v * 2 + 2], C[v * 4:v * 4 + 4], N[v * 3:v * 3 + 3]) for v in tr]
            # (the half on this leaf's side of the seam: y up to SEAM)
            outp = []
            for i in range(3):
                a, b = poly[i], poly[(i + 1) % 3]
                # (cut a hair inside the seam: the star's middle line lies on it, and its edges there were no cut)
                ina, inb = a[0][1] <= SEAM - 0.01, b[0][1] <= SEAM - 0.01
                if ina:
                    outp.append(a)
                if ina != inb:
                    f = (SEAM - 0.01 - a[0][1]) / (b[0][1] - a[0][1])
                    lerp = lambda p, q: [p[k] + (q[k] - p[k]) * f for k in range(len(p))]
                    m = (lerp(a[0], b[0]), lerp(a[1], b[1]), lerp(a[2], b[2]), lerp(a[3], b[3]))
                    m[0][1] = SEAM
                    outp.append(m)
            if len(outp) < 3:
                continue
            on = [q[0] for q in outp if abs(q[0][1] - SEAM) < 1e-6]
            if len(on) == 2 and on[0] == on[1]:
                on = []
            if len(on) == 2:
                cut.append((on[0], on[1]))
            ids = [put(*q) for q in outp]
            for k in range(1, len(ids) - 1):
                idx += [ids[0], ids[k], ids[k + 1]]
    # (the seam closed: the cut edges joined into loops, each a fan from its middle, facing across the seam)
    ends = collections.defaultdict(list)
    key = lambda p: (round(p[0], 2), round(p[2], 2))
    for a, b in cut:
        ends[key(a)].append((a, b)); ends[key(b)].append((b, a))
    used, loops = set(), []
    for a, b in cut:
        if (key(a), key(b)) in used:
            continue
        loop = [a]
        cur, nxt = a, b
        used.add((key(a), key(b))); used.add((key(b), key(a)))
        for _ in range(10000):
            loop.append(nxt)
            if key(nxt) == key(loop[0]):
                break
            cand = [q for q in ends[key(nxt)] if (key(nxt), key(q[1])) not in used]
            if not cand:
                break
            cur, nxt = nxt, cand[0][1]
            used.add((key(cur), key(nxt))); used.add((key(nxt), key(cur)))
        if len(loop) >= 4:
            loops.append(loop[:-1] if key(loop[-1]) == key(loop[0]) else loop)
    for loop in loops:
        cx = sum(p[0] for p in loop) / len(loop); cz = sum(p[2] for p in loop) / len(loop)
        m = put([cx, SEAM, cz], [0.98, 0.5], [1.0, 1.0, 1.0, 1.0], [0.0, 1.0, 0.0])
        ids = [put(list(p), [0.98, 0.5], [1.0, 1.0, 1.0, 1.0], [0.0, 1.0, 0.0]) for p in loop]
        for k in range(len(ids)):
            a, b = ids[k], ids[(k + 1) % len(ids)]
            # (turned to face +y, across the seam)
            ax, az = pos[a * 3] - cx, pos[a * 3 + 2] - cz
            bx, bz = pos[b * 3] - cx, pos[b * 3 + 2] - cz
            # normal y of (a - m) x (b - m) = az*bx - ax*bz
            # (the engine draws a face from the side its (b - a) x (c - a) points away from)
            if az * bx - ax * bz >= 0:
                idx += [m, b, a]
            else:
                idx += [m, a, b]
    out_secs.append(dict(layer="opaque", texture=GOLD, pos=pos, uv=uv, col=col, nrm=nrm, idx=idx))
    print("side", side, "scale %.2f" % s, "verts", len(pos) // 3, "tris", len(idx) // 3, "seam loops", len(loops))
    if len(stars) == 1:
        # (Render96's star door has its star on one face only; the big door had it painted on both: the other face's
        # the same star turned through the leaf - x mirrored, its triangles' order turned to face out)
        mpos = list(pos)
        for k in range(0, len(mpos), 3):
            mpos[k] = -mpos[k]
        mnrm = list(nrm)
        for k in range(0, len(mnrm), 3):
            mnrm[k] = -mnrm[k]
        midx = []
        for k in range(0, len(idx), 3):
            midx += [idx[k], idx[k + 2], idx[k + 1]]
        out_secs.append(dict(layer="opaque", texture=GOLD, pos=mpos, uv=list(uv), col=list(col), nrm=mnrm, idx=midx))

def fnum(x):
    s = "%.4f" % x
    s = s.rstrip("0").rstrip(".") if "." in s else s
    return "0" if s in ("-0", "") else s

lines = ["-- made by tools/r96_stardoor.py from Mario 64's big star door and Render96's star door; do not edit", "return {", "  parts = {"]
for pi in range(1, len(door.parts) + 1):
    p = door.parts[pi]
    secs = []
    for si in range(1, len(p.sections) + 1):
        s = p.sections[si]
        tex = s.texture
        secs.append(dict(layer=s.layer, texture=METAL if (tex in PAINTED or tex == WOOD) else tex, pos=tolist(s.pos), uv=tolist(s.uv), col=tolist(s.col),
                         nrm=tolist(s.nrm), idx=[int(x) for x in tolist(s.idx)]))
    if pi == 1:
        secs += out_secs
    lines += ["    {", '      name = "%s",' % p.name, "      parent = %d," % p.parent,
              "      off = {%s}," % ",".join(fnum(x) for x in tolist(p.off)), "      billboard = false,", "      sections = {"]
    for k, s in enumerate(secs):
        lines += ["        {", "          id = %d," % k, '          layer = "%s",' % s["layer"], '          texture = "%s",' % s["texture"],
                  "          nverts = %d," % (len(s["pos"]) // 3), "          ntris = %d," % (len(s["idx"]) // 3),
                  "          pos = {%s}," % ",".join(fnum(x) for x in s["pos"]), "          uv = {%s}," % ",".join(fnum(x) for x in s["uv"]),
                  "          col = {%s}," % ",".join(fnum(x) for x in s["col"]), "          nrm = {%s}," % ",".join(fnum(x) for x in s["nrm"]),
                  "          idx = {%s}" % ",".join(str(int(x)) for x in s["idx"]), "        },"]
    lines += ["      }", "    },"]
lines += ["  },", "  nbones = %d," % (door.nbones or 0), "  anims = {},", "  cum = %s" % fnum(door.cum or 1), "}", ""]
open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("wrote", OUT)
