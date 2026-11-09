# r96_fences.py : 3D fences for RENDER 96. Render96 has no fence models - Mario 64's fences, railings and rope rails are
# see-through pictures on flat faces - so each is made solid here: its faces put twice, a thickness apart (front and
# back), and side walls round the picture's solid part between them, coloured by its edge and shaded by the way they
# face. Written to data_r96/fences_<scene>.lua, put in place of the scene's own fence sections by lib.load_data while
# RENDER 96 is on (lib.r96_fences). ("including 3d fences add all the 3d models exept for player charater 3d models",
# 2026-10-31)
#
# The solid part: the picture's alpha (the Render 96 picture's where there is one, at the original's size) where the
# faces lie. The export cut every face at the picture's repeats, each piece's UVs brought back into 0..1: the pieces of
# one panel are joined again here - one plane, one picture mapping, found from each piece's corners - and drawn into one
# grid of the picture's pixels, so the pieces' shared edges get no walls and the panel's ends do. Its outline traced
# and smoothed (half a pixel), each edge a wall. Upright faces only; the rest kept as they were.
#
# The file: per fence picture, the scene's sections it replaces (id, triangle count - checked before it is used) and
#   groups = { nx, ny, nz, h, r, g, b, sign, ... }  the plane's normal, half the thickness, the walls' colour, and
#            which way the outlines go round
#   caps   = { section id, triangle, group, ... }    each face kept (once: the export drew most twice, back to back)
#   rest   = { section id, triangle, ... }          the faces not upright, kept as they were
#   loops  = { group, n, x, y, z, u, v (n times), ... }   each outline: its corners on the plane and where the picture
#            is read for them; a wall from each corner to the next, its outside cross(next - this, normal) times the
#            group's sign (lib makes each corner's two, the thickness apart, and the walls between)
#   groups also carry each panel's picture mapping: O, du, dv (the point at UV 0,0 and the steps of one repeat)
#
# Turned fences (TURN): a cut-out baluster pushed out flat stood as an angled slab from the side - "fences look extremely
# wierd wrong", 2026-10-31, the castle's balustrade from below. Their posts are turned instead - each row of the post's
# outline (the Render 96 picture's, at 4x the original's size) a ring as wide as it, as deep as wide - and their rails,
# the rows solid right across, made round bars along the panel. The faces then show only what is left (a copy of the
# picture without them: <picture>.rest in textures_r96), and only that is walled.
#   W, H        the original picture's size (the units below are its pixels)
#   caps_tex    the faces' picture ("" - none left: no faces)
#   posts      = { { cx, y, r, y, r, ... }, ... }   each post's middle and its rings, down it
#   place      = { group, post, ku, kv, ... }       a post put at repeat (ku, kv) of a panel
#   rails      = { group, y0, y1, u0, u1, deep, ... }   a round bar between rows y0, y1 from u0 to u1, in the panel's
#                pixels, its depth (half) - more than its height for a handrail
import os, re, sys, math, collections
import numpy as np
from PIL import Image

MOD = r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map"
DATA = os.path.join(MOD, "Scripts", "data")
OUT = os.environ.get("R96_FENCES_OUT") or os.path.join(MOD, "Scripts", "data_r96")
TEX, TEX96 = os.path.join(MOD, "textures"), os.path.join(MOD, "textures_r96")

# the fence pictures and their thickness, in the original picture's pixels
FENCES = {
    "textures__grass__wf_textures.0A000.rgba16": 5,          # wooden post-and-rail fence (WF, THI, WDW)
    "levels__castle_grounds__0.rgba16": 8,                   # the castle grounds' log fence
    "textures__snow__ccm_textures.05800.rgba16": 5,          # Cool, Cool Mountain's picket fence
    "levels__bob__0.rgba16": 4,                              # Bob-omb Battlefield's post and ring fence
    "textures__generic__bob_textures.08800.rgba16": 4,       # Bob-omb Battlefield's bars
    "levels__bbh__2.rgba16": 2,                              # Big Boo's Haunt's iron fence
    "textures__spooky__bbh_textures.08000.rgba16": 3,        # Big Boo's Haunt's balcony railings
    "textures__mountain__ttm_textures.08000.rgba16": 3,      # Tall, Tall Mountain's rope fence
    "textures__mountain__ttm_textures.0A000.rgba16": 3,      # Tall, Tall Mountain's rope rails
    "textures__snow__ccm_textures.06800.rgba16": 2,          # Cool, Cool Mountain's rope rails
    "textures__sky__rr_textures.05000.rgba16": 5,            # Bowser's courses' wooden rails
    "textures__fire__lll_textures.00800.rgba16": 2,          # Lethal Lava Land's grid fence
    "textures__sky__rr_textures.03800.rgba16": 1,            # the sky courses' grating
    "textures__grass__wf_textures.00000.rgba16": 2,          # Whomp's and Wet-Dry's grid fences
    "levels__bitfs__0.rgba16": 2,                            # Bowser in the Fire Sea's grid
    "textures__inside__inside_castle_textures.08800.rgba16": 6,   # the castle's balustrades
}
# (Jolly Roger Bay's jrb_textures.06000 left out: hanging weed, not a rail)
# the pictures whose posts are turned and rails made round (the rest pushed out flat)
TURN = {"textures__inside__inside_castle_textures.08800.rgba16", "levels__castle_grounds__0.rgba16"}
SUB = 4                # turned posts read at this many times the original picture's size
RAIL_FILL = 0.85       # a row this full right across: a rail
# rails that posts stand under (a handrail): as deep as the widest post end touching it, and a little more - the round
# handrail was narrower than the balusters' tops, and they showed beside it from above
RAIL_COVER = {"textures__inside__inside_castle_textures.08800.rgba16"}
UPRIGHT = 0.3          # faces whose normal's height is under this: upright
MAX_CELLS = 4_000_000  # a panel's grid bigger than this: its faces thickened, no walls (logged)
FIT = 0.03             # a piece belongs to a panel when its corners' UVs are the panel's to this (0..1 a repeat)
SMOOTH = 0.9           # outlines smoothed to this (pixels): their 1-pixel steps made slopes - at 0.55 a baluster's
                       # curve stood as a stack of dark ledges
READ_IN = 1.0          # the walls' colour read this far in from the edge (pixels): Mario 64's pictures have a dark
                       # outline, and the walls took it

def nums(s):
    return [float(x) for x in s.split(",") if x.strip()]

SEC = re.compile(r'\{\s*id = (\d+),\s*layer = "(\w+)",\s*texture = "([^"]*)",\s*nverts = (\d+),\s*ntris = (\d+),\s*'
                 r'pos = \{([^}]*)\},\s*uv = \{([^}]*)\},\s*col = \{([^}]*)\},\s*nrm = \{([^}]*)\},\s*idx = \{([^}]*)\}')

masks = {}
def mask_of(tex):
    if tex in masks:
        return masks[tex]
    o = Image.open(os.path.join(TEX, tex + ".png")).convert("RGBA")
    p96 = os.path.join(TEX96, tex + ".png")
    src = Image.open(p96).convert("RGBA") if os.path.exists(p96) else o
    a = np.array(src.resize(o.size, Image.BILINEAR))[:, :, 3] > 127
    masks[tex] = a
    return a

turned = {}
def turn_of(tex):
    """a turned fence picture's posts, rails, and what is left of it: (posts, rails, rest mask at 1x, caps texture)"""
    if tex in turned:
        return turned[tex]
    o = Image.open(os.path.join(TEX, tex + ".png")).convert("RGBA")
    W, H = o.size
    p96 = os.path.join(TEX96, tex + ".png")
    hd = Image.open(p96).convert("RGBA") if os.path.exists(p96) else o
    W4, H4 = W * SUB, H * SUB
    m4 = np.array(hd.resize((W4, H4), Image.BILINEAR))[:, :, 3] > 127
    fill = m4.mean(1)
    railrow = fill >= RAIL_FILL
    # (a rail's soft edge rows, wider than the posts though not full: the rail's too - left on a post they made it too
    # wide to turn, and the grounds' log posts came out boxes)
    part = fill[(fill > 0) & ~railrow]
    if part.size:
        base = float(np.median(part))
        grow = True
        while grow:
            grow = False
            for r in range(H4):
                if not railrow[r] and fill[r] > base * 1.2 + 0.02 and (
                        (r > 0 and railrow[r - 1]) or (r + 1 < H4 and railrow[r + 1])):
                    railrow[r] = True
                    grow = True
    rails = []
    r = 0
    while r < H4:
        if railrow[r]:
            r1 = r
            while r1 < H4 and railrow[r1]:
                r1 += 1
            rails.append((r / SUB, r1 / SUB))
            r = r1
        else:
            r += 1
    post = m4 & ~railrow[:, None]
    strip = np.tile(post, (1, 3))
    lab = np.zeros(strip.shape, np.int32)
    handled = np.zeros_like(m4)
    handled[railrow, :] = True
    posts = []
    n = 0
    for y0, x0 in zip(*np.nonzero(strip)):
        if lab[y0, x0]:
            continue
        n += 1
        stack = [(y0, x0)]
        lab[y0, x0] = n
        cells = []
        while stack:
            y, x = stack.pop()
            cells.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < H4 and 0 <= xx < 3 * W4 and strip[yy, xx] and not lab[yy, xx]:
                    lab[yy, xx] = n
                    stack.append((yy, xx))
        xs = [c[1] for c in cells]
        mid = (min(xs) + max(xs)) / 2.0
        if not (W4 <= mid < 2 * W4):
            continue                       # (the copies of it in the next repeats)
        rows = collections.defaultdict(list)
        for y, x in cells:
            rows[y].append(x)
        ok = len(rows) >= 4 * SUB
        prof = []
        for y in sorted(rows):
            xs = sorted(rows[y])
            if xs[-1] - xs[0] + 1 != len(xs):
                ok = False                 # (two runs in a row: not a turned post)
                break
            prof.append((y, xs[0], xs[-1] + 1))
        if not ok:
            continue
        if max(x1 - x0 for _, x0, x1 in prof) > 0.6 * W4:
            continue
        cx = float(np.median([(x0 + x1) / 2.0 for _, x0, x1 in prof]))
        # (its rings: each row's half-width about the middle, top and bottom closed; smoothed to a quarter pixel)
        pts = [(prof[0][0], (prof[0][2] - prof[0][1]) / 2.0)]
        pts += [(y + 0.5, (x1 - x0) / 2.0) for y, x0, x1 in prof]
        pts += [(prof[-1][0] + 1, (prof[-1][2] - prof[-1][1]) / 2.0)]
        pts = simplify(pts, 0.25 * SUB)
        ring = []
        for y, rr in pts:
            ring += [y / SUB, rr / SUB]
        cells1 = sorted(set((y // SUB, (x - W4) // SUB) for y, x in cells))
        posts.append(dict(cx=(cx - W4) / SUB, ring=ring, cells=cells1))
        for y, x in cells:
            handled[y, x % W4] = True
    rest4 = m4 & ~handled
    rest1 = rest4.reshape(H, SUB, W, SUB).mean((1, 3)) >= 0.5
    caps_tex = ""
    if rest1.sum() > 0.02 * max(1, (m4.reshape(H, SUB, W, SUB).mean((1, 3)) >= 0.5).sum()):
        # (the faces' copy of the picture: the turned and round parts cut out of it)
        caps_tex = tex + ".rest"
        big = hd.copy()
        hm = Image.fromarray((handled * 255).astype(np.uint8)).resize(big.size, Image.NEAREST)
        hm = np.array(hm) > 127
        a = np.array(big)
        a[hm, 3] = 0
        Image.fromarray(a).save(os.path.join(TEX96, caps_tex + ".png"))
    else:
        rest1 = np.zeros_like(rest1)
    # (each rail's depth: its own half-height, or for a handrail the widest post end touching it)
    rails2 = []
    for y0, y1 in rails:
        rd = (y1 - y0) / 2.0
        if tex in RAIL_COVER:
            # (as deep as the widest of a post's top or foot within 5 pixels of the rail: the balusters' capitals stood
            # out round the rail, their tops read dark from above - "can see the inside of the fence", 2026-10-31)
            for pt in posts:
                ring = pt["ring"]
                for k in (0, len(ring) - 2):
                    if abs(ring[k] - y0) < 1.0 or abs(ring[k] - y1) < 1.0:
                        for j in range(0, len(ring), 2):
                            if abs(ring[j] - ring[k]) <= 5.0:
                                rd = max(rd, ring[j + 1] + 0.5)
        rails2.append((y0, y1, rd))
    turned[tex] = (posts, rails2, rest1, caps_tex)
    return turned[tex]

def loops_of(R):
    """the outlines of a grid's solid cells, as closed loops of grid corners (x right, y down), the solid on the left of
    each step as cross(step, toward solid) < 0"""
    nxt = collections.defaultdict(list)
    rows, cols = R.shape
    # across: line y = r between rows r-1 and r
    up, dn = R[:-1, :], R[1:, :]
    for r, c in zip(*np.nonzero(up & ~dn)):
        nxt[(c, r + 1)].append((c + 1, r + 1))            # solid above: walk +x
    for r, c in zip(*np.nonzero(~up & dn)):
        nxt[(c + 1, r + 1)].append((c, r + 1))            # solid below: walk -x
    lf, rt = R[:, :-1], R[:, 1:]
    for r, c in zip(*np.nonzero(lf & ~rt)):
        nxt[(c + 1, r + 1)].append((c + 1, r))            # solid on the left (x smaller): walk -y
    for r, c in zip(*np.nonzero(~lf & rt)):
        nxt[(c + 1, r)].append((c + 1, r + 1))            # solid on the right: walk +y
    loops = []
    for start in list(nxt.keys()):
        while nxt.get(start):
            loop = [start]
            p = nxt[start].pop()
            while p != start:
                loop.append(p)
                if not nxt.get(p):
                    break
                p = nxt[p].pop()
            loops.append(loop)
    return loops

def simplify(pts, eps):
    """Douglas-Peucker on an open polyline"""
    if len(pts) < 3:
        return pts
    a, b = np.array(pts[0], float), np.array(pts[-1], float)
    ab = b - a
    L = np.hypot(*ab)
    P = np.array(pts[1:-1], float)
    if L < 1e-9:
        d = np.hypot(*(P - a).T)
    else:
        d = np.abs(ab[0] * (P[:, 1] - a[1]) - ab[1] * (P[:, 0] - a[0])) / L
    i = int(np.argmax(d))
    if d[i] > eps:
        left = simplify(pts[:i + 2], eps)
        right = simplify(pts[i + 1:], eps)
        return left[:-1] + right
    return [pts[0], pts[-1]]

def simplify_loop(loop, eps):
    if len(loop) < 4:
        return loop
    a = np.array(loop[0], float)
    far = int(np.argmax([np.hypot(p[0] - a[0], p[1] - a[1]) for p in loop]))
    first = simplify(loop[:far + 1], eps)
    second = simplify(loop[far:] + [loop[0]], eps)
    return first[:-1] + second[:-1]

def build(scene):
    s = open(os.path.join(DATA, "scene_%s.lua" % scene), encoding="utf-8", errors="replace").read()
    cut = s.find("collision = {")
    vis = s[:cut] if cut >= 0 else s
    by_tex = collections.defaultdict(list)
    for m in SEC.finditer(vis):
        if m.group(3) in FENCES:
            by_tex[m.group(3)].append(m)
    entries, report, nverts = [], [], 0
    for tex, ms in by_tex.items():
        mask = mask_of(tex)
        H, W = mask.shape
        turn = turn_of(tex) if tex in TURN else None
        if turn:
            mask = turn[2]                 # (only what is left of it walled)
        drop, rest, tris = [], [], []
        for m in ms:
            sid = int(m.group(1))
            drop.append((sid, int(m.group(5))))
            P = np.array(nums(m.group(6))).reshape(-1, 3); UV = np.array(nums(m.group(7))).reshape(-1, 2)
            C = np.array(nums(m.group(8))).reshape(-1, 4)
            I = [int(x) for x in nums(m.group(10))]
            for t in range(len(I) // 3):
                ia, ib, ic = I[t * 3], I[t * 3 + 1], I[t * 3 + 2]
                a, b, c = P[ia], P[ib], P[ic]
                n = np.cross(b - a, c - a)
                L = np.linalg.norm(n)
                if L < 1e-9:
                    continue
                n = n / L
                if abs(n[2]) >= UPRIGHT:
                    rest.append((sid, t))
                    continue
                uv = np.array([UV[ia], UV[ib], UV[ic]])
                uva = abs((uv[1, 0] - uv[0, 0]) * (uv[2, 1] - uv[0, 1]) - (uv[2, 0] - uv[0, 0]) * (uv[1, 1] - uv[0, 1])) / 2
                tris.append(dict(sid=sid, t=t, p=np.array([a, b, c]), uv=uv, col=(C[ia] + C[ib] + C[ic]) / 3.0, n=n,
                                 area=L / 2, uva=uva))
        if not tris:
            continue          # (none upright: left as it is)
        # (a face drawn twice - back to back, or twice over - kept once)
        cells, keep = {}, []
        for tr in tris:
            cen = tr["p"].mean(0)
            ucen = tr["uv"].mean(0)
            k = tuple(np.floor(cen / 2.0).astype(int))
            twin = False
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for dz in (-1, 0, 1):
                        for o in cells.get((k[0] + dx, k[1] + dy, k[2] + dz), ()):
                            if (np.linalg.norm(o[0] - cen) < 1.5 and abs(np.dot(o[1], tr["n"])) > 0.99
                                    and abs(o[2] - tr["area"]) < 0.05 * tr["area"] + 1e-6 and np.linalg.norm(o[3] - ucen) < 0.02):
                                twin = True
                                break
                        if twin: break
                    if twin: break
                if twin: break
            if not twin:
                cells.setdefault(k, []).append((cen, tr["n"], tr["area"], ucen))
                keep.append(tr)
        # (the planes: normal one way, and distance)
        planes = collections.defaultdict(list)
        for tr in keep:
            n = tr["n"]
            sg = 1.0
            for comp in n:
                if abs(comp) > 0.02:
                    sg = 1.0 if comp > 0 else -1.0
                    break
            tr["nc"] = n * sg
            planes[(tuple(np.round(n * sg * 50).astype(int)), int(round(np.dot(n * sg, tr["p"][0]) / 3.0)))].append(tr)
        # (the panels in each plane: one picture mapping, the biggest piece's; each smaller piece in the first whose
        # mapping puts its corners at its own UVs give or take whole repeats)
        groups = []
        for _, members in planes.items():
            members.sort(key=lambda tr: -tr["uva"])
            panels = []
            for tr in members:
                placed = False
                for pn in panels:
                    O, du, dv, G = pn["O"], pn["du"], pn["dv"], pn["Ginv"]
                    rel = tr["p"] - O
                    pred = (rel @ np.array([du, dv]).T) @ G.T          # (3, 2) the panel's UVs at the corners
                    diff = pred - tr["uv"]
                    k = np.round(diff[0])
                    if np.all(np.abs(diff - k) < FIT):
                        tr["uv2"] = tr["uv"] + k
                        pn["m"].append(tr)
                        placed = True
                        break
                if placed:
                    continue
                if tr["uva"] < 1e-4:
                    tr["uv2"] = None
                    groups.append(dict(m=[tr], O=None))
                    continue
                a, b, c = tr["p"]
                (ua, va), (ub, vb), (uc, vc) = tr["uv"]
                du1, dv1, du2, dv2 = ub - ua, vb - va, uc - ua, vc - va
                det = du1 * dv2 - du2 * dv1
                e1, e2 = b - a, c - a
                dPdu = (e1 * dv2 - e2 * dv1) / det
                dPdv = (e2 * du1 - e1 * du2) / det
                O = a - ua * dPdu - va * dPdv
                Gm = np.array([[dPdu @ dPdu, dPdu @ dPdv], [dPdv @ dPdu, dPdv @ dPdv]])
                tr["uv2"] = tr["uv"].copy()
                pn = dict(O=O, du=dPdu, dv=dPdv, Ginv=np.linalg.inv(Gm), m=[tr])
                panels.append(pn)
            groups.extend(panels)
        thick = FENCES[tex]
        gdata, caps, loops, nwalls = [], [], [], 0
        place, rails = [], []
        for gi, pn in enumerate(groups):
            m = pn["m"]
            nc = m[0]["nc"]
            if pn["O"] is not None:
                px = min(np.linalg.norm(pn["du"]) / W, np.linalg.norm(pn["dv"]) / H)
            else:
                px = math.sqrt(m[0]["area"]) / 16.0
            h = 0.5 * thick * px
            col = np.mean([tr["col"] for tr in m], axis=0)
            if pn["O"] is not None:
                frame = tuple(pn["O"]) + tuple(pn["du"]) + tuple(pn["dv"])
            else:
                frame = (0.0,) * 9
            gdata.append((nc[0], nc[1], nc[2], h, col[0], col[1], col[2], 1.0) + frame)
            if not (turn and not turn[3]):
                for tr in m:
                    caps.append((tr["sid"], tr["t"], gi))
            if pn["O"] is None:
                continue
            O, du, dv = pn["O"], pn["du"], pn["dv"]
            uvs = np.array([tr["uv2"] for tr in m])           # (n, 3, 2)
            i0 = int(math.floor(uvs[:, :, 0].min() * W)) - 1
            i1 = int(math.ceil(uvs[:, :, 0].max() * W)) + 1
            j0 = int(math.floor(uvs[:, :, 1].min() * H)) - 1
            j1 = int(math.ceil(uvs[:, :, 1].max() * H)) + 1
            if (i1 - i0) * (j1 - j0) > MAX_CELLS:
                report.append("  %s: a panel %dx%d pixels - no walls" % (tex, i1 - i0, j1 - j0))
                continue
            cov = np.zeros((j1 - j0, i1 - i0), bool)
            for tuv in uvs:
                x = tuv[:, 0] * W; y = tuv[:, 1] * H
                xa, xb = max(i0, int(math.floor(x.min()))), min(i1, int(math.ceil(x.max())) + 1)
                ya, yb = max(j0, int(math.floor(y.min()))), min(j1, int(math.ceil(y.max())) + 1)
                if xb <= xa or yb <= ya:
                    continue
                gx, gy = np.meshgrid(np.arange(xa, xb) + 0.5, np.arange(ya, yb) + 0.5)
                (x0, y0), (x1, y1), (x2, y2) = zip(x, y)
                d = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
                if abs(d) < 1e-12:
                    continue
                l0 = ((y1 - y2) * (gx - x2) + (x2 - x1) * (gy - y2)) / d
                l1 = ((y2 - y0) * (gx - x2) + (x0 - x2) * (gy - y2)) / d
                l2 = 1.0 - l0 - l1
                e = -1e-6
                cov[ya - j0:yb - j0, xa - i0:xb - i0] |= (l0 >= e) & (l1 >= e) & (l2 >= e)
            if turn:
                # (the posts whose cells the panel mostly covers, at each repeat; the rails along the runs it covers)
                posts_t, rails_t = turn[0], turn[1]
                for kv in range(int(math.floor(j0 / H)) - 1, int(math.ceil(j1 / H)) + 1):
                    for ku in range(int(math.floor(i0 / W)) - 1, int(math.ceil(i1 / W)) + 1):
                        for ci, pt in enumerate(posts_t):
                            hit = tot = 0
                            for y, x in pt["cells"]:
                                yy, xx = kv * H + y - j0, ku * W + x - i0
                                tot += 1
                                if 0 <= yy < cov.shape[0] and 0 <= xx < cov.shape[1] and cov[yy, xx]:
                                    hit += 1
                            if tot and hit >= 0.5 * tot:
                                place.append((gi, ci, ku, kv))
                    for ry0, ry1, rd in rails_t:
                        jm = int(math.floor((ry0 + ry1) / 2.0)) + kv * H
                        if not (j0 <= jm < j1):
                            continue
                        row = cov[jm - j0]
                        xs = np.flatnonzero(np.diff(np.concatenate(([0], row.astype(np.int8), [0]))))
                        for a_, b_ in zip(xs[0::2], xs[1::2]):
                            rails.append((gi, ry0 + kv * H, ry1 + kv * H, i0 + a_, i0 + b_, rd))
            jj = (np.arange(j0, j1) % H)[:, None]
            ii = (np.arange(i0, i1) % W)[None, :]
            reg = np.pad(cov & mask[jj, ii], 1)
            if not reg.any():
                continue
            # (grid corner (x, y) of the padded grid is pixel corner (i0 + x - 1, j0 + y - 1); the outlines go round with
            # the solid on their left in the grid - their outside cross(next - this, normal) times this, the same for all)
            sign = None
            for loop in loops_of(reg):
                pts = simplify_loop(loop, SMOOTH)
                if len(pts) < 3:
                    continue
                k = len(pts)
                corners = []
                for q in range(k):
                    (xp, yp), (xc, yc), (xn, yn) = pts[q - 1], pts[q], pts[(q + 1) % k]
                    # (toward the solid from each of the corner's two edges, and between them: the picture read
                    # READ_IN in)
                    sx = sy = 0.0
                    for (xa_, ya_), (xb_, yb_) in (((xp, yp), (xc, yc)), ((xc, yc), (xn, yn))):
                        dx, dy = xb_ - xa_, yb_ - ya_
                        Ld = math.hypot(dx, dy) or 1.0
                        sx += dy / Ld; sy += -dx / Ld
                    Ls = math.hypot(sx, sy) or 1.0
                    sx, sy = sx / Ls * READ_IN, sy / Ls * READ_IN
                    u = (i0 + xc - 1) / W; v = (j0 + yc - 1) / H
                    p3 = O + u * du + v * dv
                    corners.append((p3, (i0 + xc - 1 + sx) / W, (j0 + yc - 1 + sy) / H))
                if sign is None:
                    # (the first wall's outside, from the grid: away from the solid)
                    (xa_, ya_), (xb_, yb_) = pts[0], pts[1]
                    dx, dy = xb_ - xa_, yb_ - ya_
                    o3 = -(du * (dy / W) + dv * (-dx / H))
                    sign = 1.0 if np.cross(corners[1][0] - corners[0][0], nc) @ o3 >= 0 else -1.0
                loops.append((gi, corners))
                nwalls += k
            if sign is not None:
                g = gdata[gi]
                gdata[gi] = g[:7] + (sign,) + g[8:]
        e = dict(tex=tex, drop=drop, groups=gdata, caps=caps, rest=rest, loops=loops, W=W, H=H)
        if turn:
            e.update(caps_tex=turn[3], posts=turn[0], place=place, rails=rails)
        entries.append(e)
        nv = len(caps) * 6 + nwalls * 2
        if turn:
            nv += sum(len(turn[0][q[1]]["ring"]) // 2 * 10 + 2 for q in place) + len(rails) * 22
        nverts += nv
        report.append("  %s: %d faces (%d kept), %d panels, %d walls -> %d verts" % (
            tex, len(tris), len(keep), len(groups), nwalls, nv) + (" (%d posts turned, %d rails)" % (len(place), len(rails)) if turn else ""))
    return entries, report, nverts

def fmt(x, nd):
    s = ("%." + str(nd) + "f") % x
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s

def write(scene, entries):
    out = ["-- made by tools/r96_fences.py from scene_%s.lua: its fences made solid for RENDER 96 (lib.r96_fences); do not edit" % scene,
           "return {"]
    for e in entries:
        out.append('  { texture = "%s", W = %d, H = %d,' % (e["tex"], e["W"], e["H"]))
        if "posts" in e:
            out.append('    caps_tex = "%s",' % e["caps_tex"])
            out.append("    posts = {%s}," % ",".join("{%s,%s}" % (fmt(q["cx"], 3), ",".join(fmt(v, 3) for v in q["ring"])) for q in e["posts"]))
            out.append("    place = {%s}," % ",".join("%d,%d,%d,%d" % q for q in e["place"]))
            out.append("    rails = {%s}," % ",".join("%d,%s,%s,%s,%s,%s" % (r[0], fmt(r[1], 3), fmt(r[2], 3), fmt(r[3], 2), fmt(r[4], 2), fmt(r[5], 3)) for r in e["rails"]))
        out.append("    drop = {%s}," % ",".join("%d,%d" % d for d in e["drop"]))
        out.append("    groups = {%s}," % ",".join(",".join(fmt(v, 3) for v in g[:8]) + "," + ",".join(fmt(v, 4) for v in g[8:]) for g in e["groups"]))
        out.append("    caps = {%s}," % ",".join("%d,%d,%d" % c for c in e["caps"]))
        out.append("    rest = {%s}," % ",".join("%d,%d" % r for r in e["rest"]))
        parts = []
        for gi, corners in e["loops"]:
            parts.append("%d,%d" % (gi, len(corners)))
            parts += ["%s,%s,%s,%s,%s" % (fmt(p[0], 1), fmt(p[1], 1), fmt(p[2], 1), fmt(u, 4), fmt(v, 4)) for p, u, v in corners]
        out.append("    loops = {%s} }," % ",".join(parts))
    out += ["}", ""]
    body = "\n".join(out)
    open(os.path.join(OUT, "fences_%s.lua" % scene), "w", encoding="utf-8", newline="\n").write(body)
    return len(body)

def main(scenes):
    os.makedirs(OUT, exist_ok=True)
    total = 0
    for scene in scenes:
        entries, report, nv = build(scene)
        if not entries:
            continue
        size = write(scene, entries)
        total += nv
        print("%s: %d verts, %d KB" % (scene, nv, size // 1024))
        for line in report:
            print(line)
    print("all:", total, "verts")

if __name__ == "__main__":
    names = sys.argv[1:]
    if not names:
        names = sorted(f[6:-4] for f in os.listdir(DATA) if re.fullmatch(r"scene_\w+\.lua", f))
    main(names)
