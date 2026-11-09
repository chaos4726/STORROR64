"""Tiny-Huge Island's tiny island drawn at its own size (2026-10-29).

Area 2 draws the huge island's own display lists under GEO_SCALE(0x00, 19660) - 0.3 of them (thi/areas/2/geo.inc.c).
The scene export left that scale out: data/scene_thi_2.lua's picture was the huge island at full size, its collision
the tiny one's - he walked on nothing anyone could see, inside a mountain 3 times too big, and the summit's pool hung in
the sky. Each of its level sections starts with the huge island's own vertices (the islet MODEL_LEVEL_GEOMETRY_03, the
area's decals and the pipes come after, or on their own, at the tiny island's size already): those are scaled by
19660/65536 here, everything else left as it is.

Run: python tools/thi_tiny_scale.py <Scripts/data folder>
"""
import re, sys, os
K = 19660.0 / 65536.0
d = sys.argv[1]
huge = open(os.path.join(d, "scene_thi.lua"), encoding="utf-8", newline="").read()
path = os.path.join(d, "scene_thi_2.lua")
tiny = open(path, encoding="utf-8", newline="").read()
assert "-- (picture scaled to the tiny island" not in tiny, "already done"
POS = re.compile(r'pos = \{([^}]*)\}')
TEX = re.compile(r'texture = "([^"]*)"')


def sections(s):
    """(start of the sections, [(texture or None, pos match)]) - every section has one pos list; one has no texture"""
    i = s.find("sections = {"); j = s.find("collision = {")
    out, prev = [], 0
    for m in POS.finditer(s, i, j):
        t = TEX.search(s, prev, m.start())
        out.append((t.group(1) if t else None, m))
        prev = m.end()
    return out


def fmt(v):
    t = ("%.4f" % v).rstrip("0").rstrip(".")
    return "0" if t in ("-0", "") else t


hs = sections(huge)
ts = sections(tiny)
out, last, n_scaled = [], 0, 0
for k, (tex, m) in enumerate(ts):
    vals = [float(x) for x in m.group(1).split(",")]
    tv = [tuple(vals[q:q + 3]) for q in range(0, len(vals), 3)]
    hv = []
    if k < len(hs) and hs[k][0] == tex:
        hvals = [float(x) for x in hs[k][1].group(1).split(",")]
        hv = [tuple(hvals[q:q + 3]) for q in range(0, len(hvals), 3)]
    n = 0
    while n < len(hv) and n < len(tv) and tv[n] == hv[n]:
        n += 1
    if n == 0:
        continue
    new = [c * K for v in tv[:n] for c in v] + [c for v in tv[n:] for c in v]
    out.append(tiny[last:m.start(1)]); out.append(",".join(fmt(c) for c in new)); last = m.end(1)
    n_scaled += n
    print("%-45s %5d of %5d vertices scaled" % (tex or "(no texture)", n, len(tv)))
out.append(tiny[last:])
s = "".join(out)
s = s.replace("return {", "-- (picture scaled to the tiny island's size, its GEO_SCALE: tools/thi_tiny_scale.py, 2026-10-29)\nreturn {", 1)
open(path, "w", encoding="utf-8", newline="").write(s)
print("written", path, n_scaled, "vertices")
