"""Mario's head from the title screen, read from the game's own "dynlists" (src/goddard/dynlists).

The head is six shapes (face, two eyes, two eyebrows, mustache), each a list of points, a list of
triangles naming a material, and the materials' colours. Parts of the skin are tied to joints by weights
(0-100): pulling a joint pulls its points along by that much. This writes all of it as data/mario_head.lua
in the head's own coordinates (x to the viewer's right, y up, z toward the viewer)."""
import os, re, math, sys
import sm64x as X

DL = os.path.join(X.D, 'src', 'goddard', 'dynlists')


def _text(name):
    return X.strip_comments(open(os.path.join(DL, name), encoding='utf-8', errors='replace').read())


def _arrays(t):
    """every `s16 name[][3]` / `u16 name[][4]` array of a file -> {name: [[...], ...]}"""
    out = {}
    for m in re.finditer(r'static\s+[su]16\s+(\w+)\s*\[\s*\]\s*\[\s*(\d)\s*\]\s*=\s*\{(.*?)\};', t, re.S):
        rows = [[int(v, 0) for v in re.findall(r'-?(?:0x[0-9A-Fa-f]+|\d+)', r)] for r in re.findall(r'\{([^{}]*)\}', m.group(3))]
        out[m.group(1)] = rows
    return out


def _calls(body):
    """the macro calls of a dynlist, in order: [(name, [args])]"""
    return [(m.group(1), [a.strip() for a in m.group(2).split(',')] if m.group(2).strip() else [])
            for m in re.finditer(r'\b([A-Z][A-Za-z]+)\(([^()]*)\)', body)]


def shapes():
    out = {}
    for fname in ('dynlist_mario_face.c', 'dynlists_mario_eyes.c', 'dynlists_mario_eyebrows_mustache.c'):
        t = _text(fname)
        arrays = _arrays(t)
        info = {m.group(1): m.group(2) for m in re.finditer(r'struct\s+Gd(?:Vtx|Face)Data\s+(\w+)\s*=\s*\{[^}]*?,\s*(\w+)\s*\}', t)}
        for m in re.finditer(r'struct\s+DynList\s+(\w+)\s*\[\s*\d*\s*\]\s*=\s*\{(.*?)\n\};', t, re.S):
            links, mtls, cur, shape = [], {}, None, None
            for name, a in _calls(m.group(2)):
                if name == 'LinkWithPtr':
                    links.append(arrays[info[a[0].lstrip('&')]])
                elif name == 'SetId':
                    cur = int(a[0], 0)
                elif name == 'SetDiffuse' and cur is not None:
                    mtls[cur] = [float(v) for v in a]
                elif name == 'MakeDynObj' and a[0] == 'D_SHAPE':
                    shape = a[1]
            if shape and len(links) == 2:
                out[shape] = {'verts': links[0], 'faces': links[1], 'mtls': mtls}
    return out


# ---------------------------------------------------------------- the head code's own rotations
def rot(axis, deg):
    """row-vector rotation matrix, as gd_create_rot_matrix builds it"""
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    x, y, z = axis
    k = 1.0 - c
    return [[k * x * x + c, k * x * y + s * z, k * x * z - s * y],
            [k * x * y - s * z, k * y * y + c, k * y * z + s * x],
            [k * x * z + s * y, k * y * z - s * x, k * z * z + c]]


def mmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def euler(r):
    """gd_rot_mat_about_vec: about X, then Y, then Z (row vectors, so the product in that order)"""
    m = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    for axis, ang in (((1, 0, 0), r[0]), ((0, 1, 0), r[1]), ((0, 0, 1), r[2])):
        if ang != 0.0:
            m = mmul(m, rot(axis, ang))
    return m


def apply(v, m, t=(0, 0, 0)):
    return [sum(v[k] * m[k][j] for k in range(3)) + t[j] for j in range(3)]


def master():
    """nets and joints of dynlist_mario_master, as a flat list of dicts in order"""
    t = _text('dynlist_mario_master.c')
    items, cur, depth_joint = [], None, 0
    net = None
    for name, a in _calls(t):
        if name == 'MakeNetWithSubGroup':
            net = {'kind': 'skin', 'name': a[0], 'joints': []}
            items.append(net)
            cur = net
        elif name == 'EndNetWithSubGroup':
            net, cur = None, None
        elif name == 'MakeAttachedJoint' and net is not None:
            cur = {'name': a[0], 'weights': []}
            net['joints'].append(cur)
        elif name == 'MakeDynObj':
            if a[0] == 'D_NET':
                cur = {'kind': 'net', 'name': a[1]}
                items.append(cur)
            else:
                cur = None
        elif cur is not None:
            if name == 'AttachTo':
                cur['parent'] = a[1]
            elif name == 'SetSkinShape':
                cur['skin'] = a[0]
            elif name == 'SetShapePtr':
                cur['shape'] = a[0]
            elif name == 'SetRotation':
                cur['rot'] = [float(v) for v in a]
            elif name == 'SetAttachOffset':
                cur['off'] = [float(v) for v in a]
            elif name == 'SetSkinWeight':
                cur['weights'].append((int(a[0], 0), float(a[1])))
    return items


FRIENDLY = [('RIGHT_EYELID', 'eyelid_r'), ('LEFT_EYELID', 'eyelid_l'), ('RIGHT_JAW', 'cheek_r'), ('LEFT_JAW', 'cheek_l'),
            ('NOSE', 'nose'), ('RIGHT_EAR', 'ear_r'), ('LEFT_EAR', 'ear_l'), ('RIGHT_LIP_CORNER', 'lip_r'),
            ('LEFT_LIP_CORNER', 'lip_l'), ('UNKNOWN_140', 'chin'), ('CAP', 'cap'),
            ('RIGHT_EYEBROW_RPART', 'brow_r_out'), ('RIGHT_EYEBROW_LPART', 'brow_r_in'), ('RIGHT_EYEBROW_MPART', 'brow_r_mid'),
            ('LEFT_EYEBROW_LPART', 'brow_l_out'), ('LEFT_EYEBROW_RPART', 'brow_l_in'), ('LEFT_EYEBROW_MPART', 'brow_l_mid'),
            ('LEFT_MUSTACHE', 'mustache_l'), ('RIGHT_MUSTACHE', 'mustache_r')]
SHAPE_KEYS = {'DYNOBJ_MARIO_FACE_SHAPE': 'face', 'DYNOBJ_MARIO_RIGHT_EYE_SHAPE': 'eye_r', 'DYNOBJ_MARIO_LEFT_EYE_SHAPE': 'eye_l',
              'DYNOBJ_MARIO_RIGHT_EYEBROW_SHAPE': 'brow_r', 'DYNOBJ_MARIO_LEFT_EYEBROW_SHAPE': 'brow_l',
              'DYNOBJ_MARIO_MUSTACHE_SHAPE': 'mustache'}


# ---------------------------------------------------------------- the cap, turned back to front
# Mario's cap is part of his face shape: a dome, a peak at the front and the M on a white disc. Turned
# round properly the dome would cover his eyes (it comes down to his neck at the back), so the dome stays
# where it is and the things that tell which way a cap faces change ends instead. The peak comes off the
# front and goes on at the back. The front gets what the back of a snapback has: the arched opening, the
# plastic strap across the bottom of it with its row of holes, and the maker's label at the strap's end.
# All of it is tied to the cap's joint, so it moves with the cap when the cap is pulled.
CAP, EMBLEM = 7, 3
BRIM = (306, 201, 230, 335, 202, 75, 305, 56, 402, 54)       # the points of the peak
RIM_TOP = (186, 421, 420, 422, 155)                          # the cap's front edge above the peak, left to right
RIM_ENDS = (304, 121)                                        # where that edge runs on to at the sides
RIM_LOW = (403, 338, 129, 50, 55)                            # and the edge below the peak
OPENING, STRAP, STRAP_UNDER, HOLE, LABEL = 8, 9, 10, 11, 12  # new materials
CAP_COLOURS = {OPENING: [0.30, 0.0, 0.0],                    # his hair, in the shade of the cap
               STRAP: [0.82, 0.05, 0.06], STRAP_UNDER: [0.62, 0.02, 0.04],
               HOLE: [0.36, 0.0, 0.01], LABEL: [0.96, 0.96, 0.92]}
RIM_Y = 385.0                       # how far down the front of the cap comes
ARCH_HALF, ARCH_TOP = 122.0, 628.0  # the opening: half its width, and the top of its arch
STRAP_Y = (388.0, 442.0)            # the strap, bottom and top
STRAP_END = 58.0                    # the top half of the strap runs from the left to here, the under half goes on
PEAK_AT, PEAK_TILT = (0.0, 44.0, -585.0), 30.0     # where the peak joins the back of the cap, and its droop


def _front(tris, x, y):
    """how far forward the surface is at (x, y) as seen from the front, or None if it is not there"""
    best = None
    for a, b, c in tris:
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-9:
            continue
        l0 = ((b[1] - c[1]) * (x - c[0]) + (c[0] - b[0]) * (y - c[1])) / den
        l1 = ((c[1] - a[1]) * (x - c[0]) + (a[0] - c[0]) * (y - c[1])) / den
        l2 = 1.0 - l0 - l1
        if l0 >= -1e-6 and l1 >= -1e-6 and l2 >= -1e-6:
            z = l0 * a[2] + l1 * b[2] + l2 * c[2]
            if best is None or z > best:
                best = z
    return best


def backwards_cap(d):
    face = d['shapes']['face']
    V, F = face['verts'], face['faces']
    P = [[V[i * 3], V[i * 3 + 1], V[i * 3 + 2]] for i in range(len(V) // 3)]
    tris = [[F[t], F[t + 1], F[t + 2], F[t + 3]] for t in range(0, len(F), 4)]
    cap = next(j for j in d['joints'] if j['name'] == 'cap')
    # (these are the points of this game's own head; anything else and the cap is left alone)
    assert all(P[i][2] > 450 for i in BRIM) and all(abs(P[i][1] - 383) < 1 for i in RIM_LOW[1:4])
    weights = dict(zip(cap['weights'][0::2], cap['weights'][1::2]))
    tot = sum(weights.values())
    cap['handle'] = [round(sum(P[i][k] * w for i, w in weights.items()) / tot, 2) for k in range(3)]

    def point(x, y, z, tied=True):
        P.append([x, y, z])
        if tied:
            weights[len(P) - 1] = 100.0
        return len(P) - 1

    def outward(m, a, b, c):
        """a face, wound the way the head's own are: its front away from the middle of the head"""
        pa, pb, pc = P[a], P[b], P[c]
        u = [pb[k] - pa[k] for k in range(3)]
        v = [pc[k] - pa[k] for k in range(3)]
        n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        if n[0] * n[0] + n[1] * n[1] + n[2] * n[2] < 1e-6:
            return
        mid = [(pa[k] + pb[k] + pc[k]) / 3.0 for k in range(3)]
        if n[0] * mid[0] + n[1] * (mid[1] - 194.0) + n[2] * mid[2] < 0:
            b, c = c, b
        tris.append([m, a, b, c])

    # the peak comes off, and the M with it
    brim = set(BRIM)
    peak = [t for t in tris if brim & set(t[1:])]
    tris[:] = [t for t in tris if not (brim & set(t[1:]))]
    for t in tris:
        if t[0] == EMBLEM:
            t[0] = CAP

    # (the corners the peak grew out of, at the temples, are drawn in to the line of the cap)
    for i, side in ((RIM_LOW[0], -1.0), (RIM_LOW[-1], 1.0)):
        P[i] = [side * 326.0, 313.0, 282.0]

    # where it was, the front of the cap now comes straight down to a rim, with a ledge under it
    wall = [point(P[i][0], RIM_Y, P[i][2]) for i in RIM_TOP]
    for i in range(len(RIM_TOP) - 1):
        outward(CAP, RIM_TOP[i], wall[i], wall[i + 1])
        outward(CAP, RIM_TOP[i], wall[i + 1], RIM_TOP[i + 1])
    outward(CAP, RIM_ENDS[0], wall[0], RIM_TOP[0])
    outward(CAP, RIM_ENDS[1], RIM_TOP[-1], wall[-1])
    under = [point(P[i][0], RIM_Y, P[i][2]) for i in RIM_TOP]
    top = [RIM_ENDS[0]] + under + [RIM_ENDS[1]]
    low = list(RIM_LOW)
    for a, b, c in ((top[0], low[0], low[1]), (top[0], low[1], top[1]), (top[1], low[1], top[2]), (top[2], low[1], low[2]),
                    (top[2], low[2], top[3]), (top[3], low[2], top[4]), (top[4], low[2], low[3]), (top[4], low[3], top[5]),
                    (top[5], low[3], top[6]), (top[6], low[3], low[4])):
        outward(CAP, a, b, c)

    # everything else is laid on the front of the cap: each point as far forward as the cap is there, and a little more
    front = [[P[t[1]], P[t[2]], P[t[3]]] for t in tris if t[0] == CAP]

    def lay(x, y, lift):
        z = None
        for dy in (0.0, 2.0, 5.0, 10.0, -2.0, -5.0):
            z = _front(front, x, y + dy)
            if z is not None:
                break
        return point(x, y, (z if z is not None else 300.0) + lift)

    def sheet(m, rows, lift):
        """rows of (x, y), the same number in each, joined up into a surface"""
        ids = [[lay(x, y, lift) for x, y in row] for row in rows]
        for r in range(len(ids) - 1):
            for c in range(len(ids[r]) - 1):
                outward(m, ids[r][c], ids[r + 1][c], ids[r + 1][c + 1])
                outward(m, ids[r][c], ids[r + 1][c + 1], ids[r][c + 1])

    def disc(m, x, y, r, lift, n=8):
        mid = lay(x, y, lift)
        ring = [lay(x + r * math.cos(2 * math.pi * k / n), y + r * math.sin(2 * math.pi * k / n), lift) for k in range(n)]
        for k in range(n):
            outward(m, mid, ring[k], ring[(k + 1) % n])

    def across(x0, x1, n):
        return [x0 + (x1 - x0) * k / n for k in range(n + 1)]

    # the opening: straight sides and a round top
    spring = ARCH_TOP - ARCH_HALF
    ys = [RIM_Y + 2.0 + (spring - RIM_Y - 2.0) * k / 6 for k in range(7)]
    ys += [spring + ARCH_HALF * math.sin(math.radians(a)) for a in (12, 24, 36, 48, 60, 72, 82, 90)]
    rows = []
    for y in ys:
        half = ARCH_HALF if y <= spring else math.sqrt(max(0.0, ARCH_HALF ** 2 - (y - spring) ** 2))
        rows.append([(x, y) for x in across(-half, half, 10)])
    sheet(OPENING, rows, 6.0)

    # the strap: the under half comes from the right, the top half from the left and ends rounded over it
    y0, y1 = STRAP_Y
    ymid, r = (y0 + y1) / 2.0, (y1 - y0) / 2.0
    sheet(STRAP_UNDER, [[(x, y) for x in across(STRAP_END - 30.0, ARCH_HALF, 6)] for y in across(y0 + 5.0, y1 - 5.0, 3)], 11.0)
    rows = []
    for a in (-90, -60, -35, -12, 12, 35, 60, 90):
        y = ymid + r * math.sin(math.radians(a))
        end = STRAP_END - r + r * math.cos(math.radians(a))
        rows.append([(x, y) for x in across(-ARCH_HALF, STRAP_END - r, 8)] + [(end, y)])
    sheet(STRAP, rows, 17.0)
    for k in range(5):
        disc(HOLE, -64.0 + 23.5 * k, ymid, 7.0, 21.0)
    for x in (80.0, 103.0):
        disc(HOLE, x, ymid, 4.4, 15.0, 6)
    # the label, folded over the strap where it leaves the cap
    sheet(LABEL, [[(x, y) for x in across(-ARCH_HALF - 4.0, -ARCH_HALF + 32.0, 2)] for y in across(y0 - 3.0, y1 + 14.0, 3)], 24.0)

    # the peak goes on at the back: turned half way round, hung from the back of the cap, drooping
    c, sn = math.cos(math.radians(PEAK_TILT)), math.sin(math.radians(PEAK_TILT))
    root = [0.0, 415.0, 300.0]
    copies = {}
    for t in peak:
        ids = []
        for i in t[1:]:
            if i not in copies:
                x, y, z = -(P[i][0] - root[0]) * 0.86, P[i][1] - root[1], -(P[i][2] - root[2])
                copies[i] = point(x + PEAK_AT[0], y * c + z * sn + PEAK_AT[1], -y * sn + z * c + PEAK_AT[2], tied=False)
            ids.append(copies[i])
        tris.append([CAP] + ids)

    face['verts'] = [round(v, 2) for p in P for v in p]
    face['faces'] = [v for t in tris for v in t]
    face['mtls'].update(CAP_COLOURS)
    cap['weights'] = [v for i in sorted(weights) for v in (i, weights[i])]
    return d


def build(plain=False):
    """`plain`: the head as the game has it, cap the right way round"""
    sh = shapes()
    items = master()
    by_name = {it['name']: it for it in items}
    out_shapes, joints, pivots = {}, [], {}

    # where each plain net sits in the head (they only ever hang off the head itself, unrotated in practice)
    def net_offset(name):
        it = by_name.get(name)
        if not it or name == 'DYNOBJ_MARIO_MAIN_NET':
            return [0.0, 0.0, 0.0]
        return it.get('off', [0.0, 0.0, 0.0])

    shape_offset = {}
    for it in items:
        if it['kind'] == 'net' and it.get('shape') in SHAPE_KEYS and it['name'] != 'DYNOBJ_MARIO_MAIN_NET':
            shape_offset[SHAPE_KEYS[it['shape']]] = (it, net_offset(it['name']))

    for key, sname in SHAPE_KEYS.items():
        s = sh[key]
        verts = [list(map(float, v)) for v in s['verts']]
        if sname in ('eye_r', 'eye_l'):
            # an eye hangs on a joint at the middle of the head: vertex -> joint -> its skin net -> head
            enet, _ = shape_offset[sname]
            joint_name = enet['parent']
            skin = next(it for it in items if it['kind'] == 'skin' and it['joints'] and it['joints'][0]['name'] == joint_name)
            mj, mn = euler(skin['joints'][0].get('rot', [0, 0, 0])), euler(skin.get('rot', [0, 0, 0]))
            verts = [apply(apply(v, mj), mn, skin['off']) for v in verts]
            pivots[sname] = skin['off']
        elif sname in shape_offset:
            off = shape_offset[sname][1]
            verts = [[v[0] + off[0], v[1] + off[1], v[2] + off[2]] for v in verts]
        out_shapes[sname] = {'verts': [round(c, 2) for v in verts for c in v],
                             'faces': [c for f in s['faces'] for c in f],
                             'mtls': {k: v for k, v in s['mtls'].items()}}

    for it in items:
        if it['kind'] != 'skin' or not it['joints']:
            continue
        skin_shape = SHAPE_KEYS.get(it.get('skin'))
        parent_off = net_offset(it.get('parent', ''))
        base = [it['off'][k] + parent_off[k] for k in range(3)]
        mn = euler(it.get('rot', [0, 0, 0]))
        frame, pos = mn, base
        for j in it['joints']:
            # each joint sits at its offset in the frame of the one before it
            pos = [pos[k] + apply(j.get('off', [0, 0, 0]), frame)[k] for k in range(3)]
            frame = mmul(euler(j.get('rot', [0, 0, 0])), frame)
            if not j['weights']:
                continue
            nm = next((f for pat, f in FRIENDLY if pat in j['name']), j['name'].replace('DYNOBJ_MARIO_', '').lower())
            joints.append({'name': nm, 'shape': skin_shape, 'pivot': [round(c, 2) for c in pos],
                           'weights': [c for vw in j['weights'] for c in (vw[0], vw[1])]})
    d = {'shapes': out_shapes, 'joints': joints, 'eye_pivots': pivots}
    if not plain:
        try:
            backwards_cap(d)
        except (AssertionError, StopIteration, IndexError) as e:
            print('!! the cap is not as expected; left as it is', repr(e))
    return d


if __name__ == '__main__':
    d = build()
    for k, s in d['shapes'].items():
        v = s['verts']
        xs, ys, zs = v[0::3], v[1::3], v[2::3]
        print('%-9s %4d verts %4d faces  x %6.0f..%6.0f  y %6.0f..%6.0f  z %6.0f..%6.0f  mtls %s' % (
            k, len(v) // 3, len(s['faces']) // 4, min(xs), max(xs), min(ys), max(ys), min(zs), max(zs), sorted(s['mtls'])))
    fv, ff = d['shapes']['face']['verts'], d['shapes']['face']['faces']
    for side, sign in (('viewer right (+x)', 1), ('viewer left (-x)', -1)):
        pts = [[fv[i * 3 + k] for k in range(3)] for t in range(0, len(ff), 4) if ff[t] == 4 for i in ff[t + 1:t + 4]]
        pts = [p for p in pts if p[0] * sign > 0]
        print('eye white, %s: centre (%.0f, %.0f, %.0f) from %d points' % (
            side, sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts), sum(p[2] for p in pts) / len(pts), len(pts)))
    for j in d['joints']:
        w = j['weights']
        sv = d['shapes'][j['shape']]['verts']
        tot = sum(w[1::2])
        c = [sum(sv[w[i] * 3 + k] * w[i + 1] for i in range(0, len(w), 2)) / tot for k in range(3)]
        print('%-12s on %-8s %3d points  pivot (%6.0f,%6.0f,%6.0f)  handle (%6.0f,%6.0f,%6.0f)' % (
            j['name'], j['shape'], len(w) // 2, j['pivot'][0], j['pivot'][1], j['pivot'][2], c[0], c[1], c[2]))
    out = os.environ.get('SM64_OUT')
    if out:
        X.write_lua(os.path.join(out, 'Scripts', 'data', 'mario_head.lua'), d)
        print('wrote mario_head.lua')
