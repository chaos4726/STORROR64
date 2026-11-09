# test_area.py: the ragdoll test area in the castle grounds ("make a test area, some stairs to fall down a plink machine,
# and some moving parts to knock the player around", 2026-10-29), written to data/test_area.lua as platform templates
# and objects (game.lua G.add_test_area, platforms.lua B.test_*): a floor plate on the flat east of the castle, a
# staircase up to a landing, a plinko chute (a slab at 50 degrees with pegs) down from it, a spinning bar and a sliding
# ram on the plate, trip plates that knock him down the stairs and into the chute, and a warp pipe each end (one by the
# grounds' start) to get there and back.
#
# Units: Mario 64's (x, y up, z); a template's geometry is written in the scene's own (X = -z * 0.75, Y = x * 0.75,
# Z = y * 0.75, cm). Faces wound as the level's are (the cross product against the outward normal).
#
# Run: python tools/test_area.py <path to Scripts/data/test_area.lua>
import math, sys

S = 0.75
WOOD = "levels__castle_grounds__0.rgba16"
TILE = "textures__outside__castle_grounds_textures.05800.rgba16"
RED = "textures__outside__castle_grounds_textures.06000.rgba16"
PIPE_SIDE = "actors__warp_pipe__warp_pipe_side.rgba16"
PIPE_TOP = "actors__warp_pipe__warp_pipe_top.rgba16"
TILE_CM = 128.0                      # one repeat of a picture

# ---------------------------------------------------------------- geometry
def scene(p):
    return (-p[2] * S, p[0] * S, p[1] * S)

def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def mul(a, k): return (a[0] * k, a[1] * k, a[2] * k)
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def norm(a):
    l = math.sqrt(dot(a, a))
    return (a[0] / l, a[1] / l, a[2] / l) if l > 1e-9 else (0.0, 0.0, 1.0)

class Template:
    def __init__(self):
        self.sections = {}           # texture -> { pos, uv, col, nrm, idx }
        self.cpos, self.cidx = [], []

    def tri(self, tex, a, b, c, n):
        """one triangle, corners in Mario 64 local units, n its outward normal (Mario 64 axes); wound as the level's"""
        A, B, C, N = scene(a), scene(b), scene(c), norm(scene(n))
        if dot(cross(sub(B, A), sub(C, A)), N) > 0:
            B, C = C, B
        sec = self.sections.setdefault(tex, {"pos": [], "uv": [], "col": [], "nrm": [], "idx": []})
        # (the picture laid along two axes across the face)
        t1 = norm(cross(N, (0.0, 0.0, 1.0) if abs(N[2]) < 0.9 else (0.0, 1.0, 0.0)))
        t2 = cross(N, t1)
        base = len(sec["pos"]) // 3
        for P in (A, B, C):
            sec["pos"] += [P[0], P[1], P[2]]
            sec["uv"] += [dot(P, t1) / TILE_CM, dot(P, t2) / TILE_CM]
            sec["col"] += [1.0, 1.0, 1.0, 1.0]
            sec["nrm"] += [N[0], N[1], N[2]]
        sec["idx"] += [base, base + 1, base + 2]
        cb = len(self.cpos) // 3
        for P in (A, B, C):
            self.cpos += [P[0], P[1], P[2]]
        self.cidx += [cb, cb + 1, cb + 2]

    def quad(self, tex, a, b, c, d, n):
        self.tri(tex, a, b, c, n)
        self.tri(tex, a, c, d, n)

    def box(self, tex, center, u, v, w, hu, hv, hw, top_tex=None):
        """a box: center, unit axes u v w, half sizes along them"""
        U, V, W = mul(u, hu), mul(v, hv), mul(w, hw)
        def corner(su, sv, sw): return add(add(add(center, mul(U, su)), mul(V, sv)), mul(W, sw))
        faces = [
            (u, [corner(1, -1, -1), corner(1, 1, -1), corner(1, 1, 1), corner(1, -1, 1)]),
            (mul(u, -1), [corner(-1, -1, -1), corner(-1, -1, 1), corner(-1, 1, 1), corner(-1, 1, -1)]),
            (v, [corner(-1, 1, -1), corner(-1, 1, 1), corner(1, 1, 1), corner(1, 1, -1)]),
            (mul(v, -1), [corner(-1, -1, -1), corner(1, -1, -1), corner(1, -1, 1), corner(-1, -1, 1)]),
            (w, [corner(-1, -1, 1), corner(1, -1, 1), corner(1, 1, 1), corner(-1, 1, 1)]),
            (mul(w, -1), [corner(-1, -1, -1), corner(-1, 1, -1), corner(1, 1, -1), corner(1, -1, -1)]),
        ]
        for n, cs in faces:
            t = top_tex if (top_tex and n == v) else tex
            self.quad(t, cs[0], cs[1], cs[2], cs[3], n)

    def prism(self, tex, base, axis, r, h, sides=6):
        """a prism standing on `base` along `axis` (unit), radius r, height h"""
        axis = norm(axis)
        t1 = norm(cross(axis, (1.0, 0.0, 0.0) if abs(axis[0]) < 0.9 else (0.0, 0.0, 1.0)))
        t2 = cross(axis, t1)
        lo, hi = [], []
        for i in range(sides):
            a = 2.0 * math.pi * i / sides
            rim = add(mul(t1, r * math.cos(a)), mul(t2, r * math.sin(a)))
            lo.append(add(base, rim))
            hi.append(add(add(base, rim), mul(axis, h)))
        top = add(base, mul(axis, h))
        for i in range(sides):
            j = (i + 1) % sides
            n = norm(sub(mul(add(lo[i], lo[j]), 0.5), base))
            self.quad(tex, lo[i], lo[j], hi[j], hi[i], n)
            self.tri(tex, top, hi[i], hi[j], axis)
            self.tri(tex, base, lo[j], lo[i], mul(axis, -1))

    def lua(self, source):
        secs = []
        for i, (tex, s) in enumerate(self.sections.items()):
            secs.append('{ id = %d, layer = "opaque", texture = "%s", nverts = %d, ntris = %d, pos = {%s}, uv = {%s}, col = {%s}, nrm = {%s}, idx = {%s} }'
                        % (i, tex, len(s["pos"]) // 3, len(s["idx"]) // 3, nums(s["pos"]), nums(s["uv"]), nums(s["col"]), nums(s["nrm"]), nums(s["idx"])))
        coll = '{ source = "%s", ntris = %d, pos = {%s}, idx = {%s} }' % (source, len(self.cidx) // 3, nums(self.cpos), nums(self.cidx))
        return "{ sections = {%s}, collision = %s }" % (",".join(secs), coll)

def nums(a):
    out = []
    for v in a:
        if isinstance(v, int):
            out.append(str(v))
        else:
            s = ("%.2f" % v).rstrip("0").rstrip(".")
            out.append(s if s not in ("", "-0") else "0")
    return ",".join(out)

X, Y, Z = (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)

def simple_box(tex, sx, sy, sz, top_tex=None):
    """a box standing on its origin (its foot's middle), sx by sy by sz"""
    t = Template()
    t.box(tex, (0.0, sy / 2.0, 0.0), X, Y, Z, sx / 2.0, sy / 2.0, sz / 2.0, top_tex)
    return t

# ---------------------------------------------------------------- the pieces
templates, objects = {}, []

def place(tpl, bhv, pos, **extra):
    o = {"kind": "platform", "bhv": bhv, "tpl": tpl, "pos": list(pos), "ang": [0, 0, 0], "bp": 0}
    o.update(extra)
    objects.append(o)

# the plate: 2600 by 1800, 80 thick, its top at PLATE_Y
OX, PLATE_Y, OZ = 3600.0, 940.0, -5000.0
# (thick: a ragdoll at 9 m/s went through a 40-thin slab and into an 80-thin plate, 2026-10-29)
templates["test_plate"] = simple_box(TILE, 2600.0, 200.0, 1800.0)
place("test_plate", "static", (OX + 1300.0, PLATE_Y - 200.0, OZ))

# the stairs: 30 steps up toward +x, 25 up and 35 on each (19 by 26 cm), 400 wide; from x 3800 to 4850
t = Template()
for i in range(30):
    h = (i + 1) * 25.0
    t.box(WOOD, (i * 35.0 + 17.5, h / 2.0, 0.0), X, Y, Z, 17.5, h / 2.0, 200.0)
templates["test_stairs"] = t
STAIRS_X = OX + 200.0
place("test_stairs", "static", (STAIRS_X, PLATE_Y, OZ))
LAND_Y = PLATE_Y + 750.0

# the landing: 500 by 600, 750 tall, from x 4850 to 5350
templates["test_landing"] = simple_box(TILE, 500.0, 750.0, 600.0, WOOD)
LAND_X0 = STAIRS_X + 1050.0
place("test_landing", "static", (LAND_X0 + 250.0, PLATE_Y, OZ))

# the chute: a slab from the landing's far edge, +x and down at 50 degrees, 980 long (750 down, 630 on), 900 wide, 40
# thick, walls 120 up each side; pegs (six-sided, 35 round, 100 tall) in five rows across it, every other row staggered
ANG = math.radians(50.0)
D = (math.cos(ANG), -math.sin(ANG), 0.0)            # down the slab
N = (math.sin(ANG), math.cos(ANG), 0.0)             # out of its top
t = Template()
L = 980.0
t.box(TILE, add(mul(D, L / 2.0), mul(N, -60.0)), D, N, Z, L / 2.0, 60.0, 450.0)
for side in (-1.0, 1.0):
    t.box(TILE, add(add(mul(D, L / 2.0), mul(N, 40.0)), mul(Z, side * 470.0)), D, N, Z, L / 2.0, 80.0, 20.0)
for row in range(5):
    s = 200.0 + row * 160.0
    cols = [-320.0, -160.0, 0.0, 160.0, 320.0] if row % 2 == 0 else [-240.0, -80.0, 80.0, 240.0]
    for z in cols:
        t.prism(WOOD, add(mul(D, s), mul(Z, z)), N, 35.0, 100.0)
templates["test_chute"] = t
CHUTE_X0 = LAND_X0 + 500.0
place("test_chute", "static", (CHUTE_X0, LAND_Y, OZ))

# the trip plates: thin red plates; stood on, they knock him down the way they point (platforms.lua B.test_trip)
templates["test_trip"] = simple_box(RED, 120.0, 8.0, 500.0)
place("test_trip", "test_trip", (LAND_X0 + 60.0, LAND_Y, OZ), dir=[-1.0, 0.0], hx=60.0, hz=250.0)      # the stairs' top
place("test_trip", "test_trip", (CHUTE_X0 - 60.0, LAND_Y, OZ), dir=[1.0, 0.0], hx=60.0, hz=250.0, speed=450.0, up=250.0)      # the chute's top: less than the stairs', into the pegs not over them

# the spinning bar on its post (B.test_bar): 700 long, 60 up off the plate, round it goes
templates["test_bar"] = simple_box(WOOD, 80.0, 80.0, 700.0)
templates["test_post"] = simple_box(TILE, 70.0, 60.0, 70.0)
BAR = (OX + 400.0, PLATE_Y, OZ + 600.0)
place("test_post", "static", BAR)
place("test_bar", "test_bar", (BAR[0], BAR[1] + 60.0, BAR[2]), half=350.0, rate=0x140)

# the ram (B.test_ram): 300 by 200 by 260, sliding along x, 400 each way
templates["test_ram"] = simple_box(WOOD, 300.0, 200.0, 260.0, TILE)
place("test_ram", "test_ram", (CHUTE_X0 + 350.0, PLATE_Y, OZ - 650.0), span=400.0, hx=150.0, hz=130.0, h=200.0)

# the pipes: an eight-sided ring, 154 round and 205 tall (Mario 64's warp pipe), 30 thick, a floor inside at its foot
t = Template()
R, r, H = 154.0, 124.0, 205.0
def ring(k, rad): a = 2.0 * math.pi * k / 8.0; return (rad * math.cos(a), 0.0, rad * math.sin(a))
for k in range(8):
    j = (k + 1) % 8
    o0, o1, i0, i1 = ring(k, R), ring(j, R), ring(k, r), ring(j, r)
    n = norm(add(o0, o1))
    t.quad(PIPE_SIDE, o0, o1, add(o1, (0, H, 0)), add(o0, (0, H, 0)), n)
    t.quad(PIPE_SIDE, add(i0, (0, H, 0)), add(i1, (0, H, 0)), add(i1, (0, 10.0, 0)), add(i0, (0, 10.0, 0)), mul(n, -1))
    t.quad(PIPE_TOP, add(o0, (0, H, 0)), add(o1, (0, H, 0)), add(i1, (0, H, 0)), add(i0, (0, H, 0)), Y)
    t.tri(PIPE_SIDE, (0.0, 10.0, 0.0), add(i0, (0, 10.0, 0)), add(i1, (0, 10.0, 0)), Y)
templates["test_pipe"] = t
AREA_PIPE = (OX + 2450.0, PLATE_Y, OZ + 700.0)
START_PIPE = (-1861.0, 260.0, 4664.0)              # by the grounds' start
place("test_pipe", "static", AREA_PIPE)
# (the way back only - its pipe takes him to the grounds' start; no pipe there leads in: "this was supposed to be a test
# area why does it have a pipe that leads to it?", 2026-10-29. Node 91 is where he arrives when put here by hand.)
pipes = [{"kind": "pipe", "pos": list(scene(AREA_PIPE)), "node": 91}]
warps = [{"id": 91, "scene": "grounds", "node": 90}]
nodes = [{"id": 90, "pos": list(scene(START_PIPE)), "yaw": 0, "kind": "ground"}, {"id": 91, "pos": list(scene(AREA_PIPE)), "yaw": 90, "kind": "pipe"}]

# ---------------------------------------------------------------- written out
def lua_val(v):
    if isinstance(v, bool): return "true" if v else "false"
    if isinstance(v, (int, float)):
        s = ("%.2f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)
        return s if s not in ("", "-0") else "0"
    if isinstance(v, str): return '"%s"' % v
    if isinstance(v, list): return "{" + ",".join(lua_val(x) for x in v) + "}"
    if isinstance(v, dict): return "{ " + ", ".join("%s = %s" % (k, lua_val(x)) for k, x in v.items()) + " }"
    raise TypeError(v)

out = ["-- The ragdoll test area in the castle grounds, made by tools/test_area.py (2026-10-29); do not edit", "return {", "  grounds = {", "    templates = {"]
for k, tpl in templates.items():
    out.append('      ["%s"] = %s,' % (k, tpl.lua(k)))
out.append("    },")
out.append("    objects = {")
for o in objects + pipes:
    out.append("      %s," % lua_val(o))
out.append("    },")
out.append("    warps = {" + ",".join(lua_val(w) for w in warps) + "},")
out.append("    nodes = {" + ",".join(lua_val(n) for n in nodes) + "},")
out.append("  },")
out.append("}")
path = sys.argv[1]
open(path, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
tris = sum(len(t.cidx) // 3 for t in templates.values())
print("wrote", path, len(templates), "templates,", len(objects) + len(pipes), "objects,", tris, "triangles")
