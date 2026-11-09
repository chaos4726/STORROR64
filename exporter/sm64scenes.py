#!/usr/bin/env python3
"""Higher level exporters built on sm64x: static models, animated actors, levels."""
import os, re, math
from collections import OrderedDict
import sm64x as X
from sm64x import (xf_identity, xf_mul, xf_translate, xf_scale, xf_rotate_deg, to_int, try_int,
                   split_args, match_close, strip_comments, SCALE, layer_name, Mesh, GfxState,
                   interp_dl, finish_sections, rot_to_ue_quat, sm64_euler_col)

D = X.D


def num(s, default=0):
    v = try_int(s)
    return default if v is None else v


def draw_dl(db, mesh, textures, layer, dl, xf, cum=1.0):
    dl = dl.strip()
    if dl in ('NULL', '0', ''):
        return
    mesh.xf = xf
    mesh.cum = cum
    X.interp_dl(db, dl, GfxState(), mesh, layer_name(layer), textures)


# ----------------------------------------------------------------- static flatten
def walk_static(db, nodes, xf, mesh, textures, cum=1.0, seen=None):
    seen = seen if seen is not None else set()
    range_done = False
    for n in nodes:
        c, a = n['cmd'], n['args']
        cx, dl, layer = xf, None, 'LAYER_OPAQUE'
        kids = n['children']
        if c == 'GEO_DISPLAY_LIST':
            layer, dl = a[0], a[1]
        elif c == 'GEO_TRANSLATE_NODE':
            cx = xf_mul(xf, xf_translate(num(a[1]), num(a[2]), num(a[3])))
        elif c == 'GEO_TRANSLATE_NODE_WITH_DL':
            cx = xf_mul(xf, xf_translate(num(a[1]), num(a[2]), num(a[3]))); layer, dl = a[0], a[4]
        elif c == 'GEO_ROTATION_NODE':
            cx = xf_mul(xf, xf_rotate_deg(*[num(v) * 360.0 / 65536 for v in a[1:4]]))
        elif c == 'GEO_ROTATION_NODE_WITH_DL':
            cx = xf_mul(xf, xf_rotate_deg(*[num(v) * 360.0 / 65536 for v in a[1:4]])); layer, dl = a[0], a[4]
        elif c == 'GEO_TRANSLATE_ROTATE':
            cx = xf_mul(xf, xf_mul(xf_translate(num(a[1]), num(a[2]), num(a[3])),
                                   xf_rotate_deg(*[num(v) * 360.0 / 65536 for v in a[4:7]])))
        elif c == 'GEO_TRANSLATE_ROTATE_WITH_DL':
            cx = xf_mul(xf, xf_mul(xf_translate(num(a[1]), num(a[2]), num(a[3])),
                                   xf_rotate_deg(*[num(v) * 360.0 / 65536 for v in a[4:7]]))); layer, dl = a[0], a[7]
        elif c == 'GEO_SCALE':
            cx = xf_mul(xf, xf_scale(num(a[1], 65536) / 65536.0))
        elif c == 'GEO_SCALE_WITH_DL':
            cx = xf_mul(xf, xf_scale(num(a[1], 65536) / 65536.0)); layer, dl = a[0], a[2]
        elif c == 'GEO_ANIMATED_PART':
            cx = xf_mul(xf, xf_translate(num(a[1]), num(a[2]), num(a[3]))); layer, dl = a[0], a[4]
        elif c in ('GEO_BRANCH', 'GEO_BRANCH_AND_LINK'):
            tgt = a[-1].strip()
            if tgt not in seen and db.has('geo', tgt):
                seen.add(tgt)
                walk_static(db, X.parse_geo(db, tgt)['children'], xf, mesh, textures, cum, seen)
            continue
        elif c == 'GEO_SWITCH_CASE':
            kids = kids[:1]
        elif c == 'GEO_RENDER_RANGE':
            if range_done:
                continue
            range_done = True
        if dl:
            draw_dl(db, mesh, textures, layer, dl, cx)
        if kids:
            walk_static(db, kids, cx, mesh, textures, cum, seen)


def export_static_model(db, geo_name, textures, xf=None, mesh=None):
    mesh = mesh or Mesh()
    walk_static(db, X.parse_geo(db, geo_name)['children'], xf or xf_identity(), mesh, textures)
    return mesh


# ----------------------------------------------------------------- actors
class ActorBuilder:
    def __init__(self, db, textures, switch=0):
        self.db = db
        self.switch = switch        # which child of a GEO_SWITCH_CASE to draw (a ! box's colour)
        self.textures = textures
        self.parts = []
        self.bone = 0
        self.raw_w = []             # (each part's place as the model stands, SM64 units times scale: skinned joins)
        self.last_vbuf = None       # (the vertex cache carried from one part's list to the next, as the N64 keeps it)

    def add_part(self, parent, off, bone=None, billboard=False, rot=None, name=''):
        # off in SM64 units already multiplied by cumulative scale
        p = {'name': name or ('p%d' % len(self.parts)), 'parent': parent,
             'off': [-off[2] * SCALE, off[0] * SCALE, off[1] * SCALE],
             'bone': bone, 'billboard': billboard, 'sections': []}
        if rot is not None:
            p['rot'] = list(rot_to_ue_quat(rot))
        self.parts.append(p)
        base = self.raw_w[parent] if parent is not None and 0 <= parent < len(self.raw_w) else (0.0, 0.0, 0.0)
        self.raw_w.append((base[0] + off[0], base[1] + off[1], base[2] + off[2]))
        return len(self.parts) - 1

    def attach_dl(self, part, layer, dl, cum):
        if dl.strip() in ('NULL', '0', ''):
            return
        mesh = Mesh(cum=cum)
        mesh.part = part
        k = cum if cum else 1.0
        def rebase(src, cur, k=k):
            a, b = self.raw_w[src], self.raw_w[cur]
            return ((a[0] - b[0]) / k, (a[1] - b[1]) / k, (a[2] - b[2]) / k)
        mesh.rebase = rebase
        mesh.xf = None
        mesh.cum = cum
        st = GfxState()
        if self.last_vbuf is not None:
            st.vbuf = list(self.last_vbuf)
        X.interp_dl(self.db, dl.strip(), st, mesh, layer_name(layer), self.textures)
        self.last_vbuf = st.vbuf
        secs = finish_sections(mesh)
        for s in secs:
            self.parts[part]['sections'].append(s)

    def walk(self, nodes, parent, cum):
        db = self.db
        range_done = False
        for n in nodes:
            c, a, kids = n['cmd'], n['args'], n['children']
            if c == 'GEO_SCALE':
                # (a scale of 0 is set while the game runs, by the GEO_ASM before it: the snufit's body. Drawn at 1.)
                v = num(a[1], 65536)
                self.walk(kids, parent, cum * (v if v != 0 else 65536) / 65536.0)
                continue
            if c == 'GEO_SWITCH_CASE':
                i = self.switch if self.switch < len(kids) else 0
                self.walk(kids[i:i + 1], parent, cum)
                continue
            if c == 'GEO_RENDER_RANGE':
                if range_done:
                    continue
                range_done = True
                self.walk(kids, parent, cum)
                continue
            if c in ('GEO_BRANCH', 'GEO_BRANCH_AND_LINK'):
                tgt = a[-1].strip()
                if db.has('geo', tgt):
                    self.walk(X.parse_geo(db, tgt)['children'], parent, cum)
                continue
            if c == 'GEO_ANIMATED_PART':
                off = [num(a[1]) * cum, num(a[2]) * cum, num(a[3]) * cum]
                part = self.add_part(parent, off, bone=self.bone)
                self.bone += 1
                self.attach_dl(part, a[0], a[4], cum)
                self.walk(kids, part, cum)
                continue
            if c in ('GEO_BILLBOARD', 'GEO_BILLBOARD_WITH_PARAMS', 'GEO_BILLBOARD_WITH_PARAMS_AND_DL'):
                # Mario 64 draws a billboard at the object's own scale only: the model's GEO_SCALE above it does not
                # reach it (rendering_graph_node.c geo_process_billboard rebuilds the matrix, then scales it by the
                # object's scale). Goombas' faces and bob-ombs' bodies came out 3 to 4 times too small without this.
                # (Render96's are written GEO_BILLBOARD_WITH_PARAMS(layer, x, y, z): not known, they were walked
                # through at the model's quarter size - Chuckya's body and hands a quarter of theirs, its eyes hanging
                # off on their own: "chuckyas messed up", 2026-10-31.)
                off = [0, 0, 0]
                if c != 'GEO_BILLBOARD':
                    off = [num(a[1]) * cum, num(a[2]) * cum, num(a[3]) * cum]
                part = self.add_part(parent, off, billboard=True)
                if c.endswith('_AND_DL'):
                    self.attach_dl(part, a[0], a[4], 1.0)
                self.walk(kids, part, 1.0)
                continue
            if c in ('GEO_TRANSLATE_NODE', 'GEO_TRANSLATE_NODE_WITH_DL'):
                off = [num(a[1]) * cum, num(a[2]) * cum, num(a[3]) * cum]
                part = self.add_part(parent, off)
                if c.endswith('_WITH_DL'):
                    self.attach_dl(part, a[0], a[4], cum)
                self.walk(kids, part, cum)
                continue
            if c in ('GEO_ROTATION_NODE', 'GEO_ROTATION_NODE_WITH_DL'):
                rot = sm64_euler_col(*[math.radians(num(v) * 360.0 / 65536) for v in a[1:4]])
                part = self.add_part(parent, [0, 0, 0], rot=rot)
                if c.endswith('_WITH_DL'):
                    self.attach_dl(part, a[0], a[4], cum)
                self.walk(kids, part, cum)
                continue
            if c in ('GEO_TRANSLATE_ROTATE', 'GEO_TRANSLATE_ROTATE_WITH_DL'):
                # (Render96's models place limbs with these - an offset and a turn, its angles in degrees
                # (geo_layout.c read_vec3s_angle) - on a part of their own above the limb's. Walked through as nothing,
                # the penguin's other flipper and both feet sat at its middle: "penguin is still messed up", 2026-11-02)
                off = [num(a[1]) * cum, num(a[2]) * cum, num(a[3]) * cum]
                rot = sm64_euler_col(*[math.radians(num(v)) for v in a[4:7]])
                part = self.add_part(parent, off, rot=rot)
                if c.endswith('_WITH_DL'):
                    self.attach_dl(part, a[0], a[7], cum)
                self.walk(kids, part, cum)
                continue
            if c == 'GEO_DISPLAY_LIST':
                part = self.add_part(parent, [0, 0, 0])
                self.attach_dl(part, a[0], a[1], cum)
                self.walk(kids, part, cum)
                continue
            if c == 'GEO_SCALE_WITH_DL':
                part = self.add_part(parent, [0, 0, 0])
                self.attach_dl(part, a[0], a[2], cum * num(a[1], 65536) / 65536.0)
                self.walk(kids, part, cum)
                continue
            self.walk(kids, parent, cum)


def parse_int_list(text):
    out = []
    for tok in re.findall(r'-?0x[0-9A-Fa-f]+|-?\d+', text):
        out.append(int(tok, 0))
    return out


def parse_animation(db, sym):
    b = db.body('anim', sym)
    a = split_args(b)
    flags = a[0]
    loop_start = num(a[3]); loop_end = num(a[4])
    values = parse_int_list(db.body('s16', a[6].strip()))
    indices = parse_int_list(db.body('u16', a[7].strip()))
    values = [v - 65536 if v > 32767 else v for v in values]
    return {'flags': flags, 'loopStart': loop_start, 'loopEnd': loop_end, 'values': values, 'indices': indices,
            'numparts': len(indices) // 6 - 1}


def sample(anim, comp_pair_index, frame):
    ind = anim['indices']
    count = ind[comp_pair_index * 2]
    offset = ind[comp_pair_index * 2 + 1]
    i = frame if frame < count else count - 1
    return anim['values'][offset + i]


def bake_animation(anim, nbones, trans_scale):
    frames = max(1, anim['loopEnd'])
    trans, rot = [], {b: [] for b in range(nbones)}
    for f in range(frames):
        tx, ty, tz = sample(anim, 0, f), sample(anim, 1, f), sample(anim, 2, f)
        trans += [-tz * trans_scale, tx * trans_scale, ty * trans_scale]
        for b in range(nbones):
            if b >= anim['numparts']:
                rot[b] += [0, 0, 0, 1]
                continue
            base = 3 + b * 3
            rx = sample(anim, base, f) * 2 * math.pi / 65536
            ry = sample(anim, base + 1, f) * 2 * math.pi / 65536
            rz = sample(anim, base + 2, f) * 2 * math.pi / 65536
            rot[b] += list(rot_to_ue_quat(sm64_euler_col(rx, ry, rz)))
    return {'frames': frames, 'loopStart': anim['loopStart'], 'loopEnd': anim['loopEnd'], 'flags': anim.get('flags', 0),
            'trans': trans, 'rot': [rot[b] for b in range(nbones)]}


def anim_table(db, table_sym):
    out = []
    for t in re.findall(r'&?\s*(\w+)', db.body('animptrs', table_sym)):
        if db.has('anim', t):
            out.append(t)
    return out


def export_actor(db, geo_name, anim_syms=(), textures=None, switch=0):
    textures = textures if textures is not None else {}
    ab = ActorBuilder(db, textures, switch)
    ab.walk(X.parse_geo(db, geo_name)['children'], -1, 1.0)
    # root cumulative scale for translation: use first animated part's scale (approximation = scale node at top)
    cum0 = 1.0
    for n in X.parse_geo(db, geo_name)['children']:
        pass
    # find first GEO_SCALE value on the path to the first animated part
    def find_scale(nodes, cum):
        for n in nodes:
            if n['cmd'] == 'GEO_SCALE':
                cum2 = cum * num(n['args'][1], 65536) / 65536.0
            else:
                cum2 = cum
            if n['cmd'] == 'GEO_ANIMATED_PART':
                return cum
            # (into branches too: toad, moneybag, eyerok's hands and Mr. Blizzard scale, then branch to their parts - their
            # root translation came out unscaled and they floated, 2026-10-18)
            if n['cmd'] in ('GEO_BRANCH', 'GEO_BRANCH_AND_LINK') and db.has('geo', n['args'][-1].strip()):
                r = find_scale(X.parse_geo(db, n['args'][-1].strip())['children'], cum2)
                if r is not None:
                    return r
            r = find_scale(n['children'], cum2)
            if r is not None:
                return r
        return None
    cum0 = find_scale(X.parse_geo(db, geo_name)['children'], 1.0) or 1.0
    anims = []
    for sym in anim_syms:
        try:
            an = parse_animation(db, sym)
            anims.append(dict(name=sym, **bake_animation(an, ab.bone, cum0 * SCALE)))
        except Exception as e:
            print('  anim failed', sym, e)
    return {'parts': ab.parts, 'nbones': ab.bone, 'anims': anims, 'cum': cum0}


# ----------------------------------------------------------------- levels
def area_blocks(level):
    """{area_index: {'geo':..., 'terrain':..., 'macro':...}} from script.c"""
    p = os.path.join(D, 'levels', level, 'script.c')
    t = strip_comments(open(p, encoding='utf-8', errors='replace').read())
    out = {}
    pos = 0
    for m in re.finditer(r'\bAREA\s*\(([^)]*)\)', t):
        a = split_args(m.group(1))
        idx = to_int(a[0]); geo = a[1].strip()
        end = t.find('END_AREA', m.end())
        block = t[m.end():end]
        terr = re.search(r'\bTERRAIN\s*\(\s*(?:/\*[^*]*\*/)?\s*(\w+)\s*\)', block)
        macro = re.search(r'\bMACRO_OBJECTS\s*\(\s*(\w+)\s*\)', block)
        out[idx] = {'geo': geo, 'terrain': terr.group(1) if terr else None, 'macro': macro.group(1) if macro else None}
    return out


SPECIAL_RX = re.compile(r'\b(SPECIAL_OBJECT_WITH_YAW_AND_PARAM|SPECIAL_OBJECT_WITH_YAW|SPECIAL_OBJECT)\s*\(')


def parse_specials(db, terrain_sym):
    b = db.body('col', terrain_sym)
    out = []
    pos = 0
    while True:
        m = SPECIAL_RX.search(b, pos)
        if not m:
            break
        j = match_close(b, m.end() - 1, '(', ')')
        a = split_args(b[m.end():j])
        kind = m.group(1)
        d = {'preset': a[0].strip(), 'x': num(a[1]), 'y': num(a[2]), 'z': num(a[3]), 'yaw': 0, 'param': 0}
        if kind != 'SPECIAL_OBJECT':
            d['yaw'] = num(a[4])
        if kind == 'SPECIAL_OBJECT_WITH_YAW_AND_PARAM':
            d['param'] = num(a[5])
        out.append(d)
        pos = j + 1
    return out


def rot_y_xf(yaw_deg, pos):
    th = math.radians(yaw_deg)
    c, s = math.cos(th), math.sin(th)
    R = [[c, 0, s], [0, 1, 0], [-s, 0, c]]
    return (R, [pos[0], pos[1], pos[2]])


def export_level_base(db, geo_name, textures):
    mesh = Mesh()
    for layer, dl, k in X.collect_level_dls(db, geo_name, with_scale=True):
        mesh.xf = None
        mesh.cum = k                   # (a GEO_SCALE over it: THI's tiny island)
        interp_dl(db, dl, GfxState(), mesh, layer, textures)
    return mesh


def crossed_billboard(db, geo_name, textures, pos, mesh):
    """Bake a billboard sprite model as two crossed quads (viewable from all sides)."""
    for yaw in (0, 90):
        xf = rot_y_xf(yaw, pos)
        walk_static(db, X.parse_geo(db, geo_name)['children'], xf, mesh, textures)


# ----------------------------------------------------------------- paintings
PAINTING_ORDER = ['bob', 'ccm', 'wf', 'jrb', 'lll', 'ssl', 'hmc', 'ddd', 'wdw', 'thi_tiny', 'ttm', 'ttc', 'sl', 'thi_huge']


def collect_painting_ids(db, geo_name, seen=None):
    seen = seen if seen is not None else set()
    ids = set()

    def walk(node):
        for ch in node['children']:
            c = ch['cmd']
            if c == 'GEO_ASM' and len(ch['args']) >= 2 and 'geo_painting_draw' in ch['args'][1]:
                m = re.search(r'PAINTING_ID\(\s*(\d+)', ch['args'][0])
                if m:
                    ids.add(int(m.group(1)))
            elif c in ('GEO_BRANCH', 'GEO_BRANCH_AND_LINK'):
                tgt = ch['args'][-1].strip()
                if tgt not in seen and db.has('geo', tgt):
                    seen.add(tgt)
                    walk(X.parse_geo(db, tgt))
            walk(ch)
    walk(X.parse_geo(db, geo_name))
    return ids


def export_paintings(db, geo_name, out_tex_dir, pwarps=None):
    from PIL import Image
    ids = collect_painting_ids(db, geo_name)
    path = os.path.join(D, 'levels', 'castle_inside', 'painting.inc.c')
    t = strip_comments(open(path, encoding='utf-8', errors='replace').read())
    out = []
    for m in re.finditer(r'struct\s+Painting\s+(\w+)\s*=\s*\{', t):
        name = m.group(1)
        j = match_close(t, m.end() - 1, '{', '}')
        tok = [x for x in split_args(t[m.end():j])]
        try:
            pid = to_int(tok[0]); img_count = to_int(tok[1]); ptype = tok[2]
            rot_pitch = float(tok[7].rstrip('f')); rot_yaw = float(tok[8].rstrip('f'))
            pos = [float(tok[9].rstrip('f')), float(tok[10].rstrip('f')), float(tok[11].rstrip('f'))]
            tex_sym = tok[29].strip(); size = float(tok[38].rstrip('f'))
            tw = to_int(tok[30]); th = to_int(tok[31])
        except Exception as e:
            print('  painting parse failed', name, e)
            continue
        # the level's geometry names paintings by their place in the castle's list, not by their own id
        if name not in [PAINTING_ORDER[k] + '_painting' for k in ids if k < len(PAINTING_ORDER)]:
            continue
        # texture array -> images
        am = re.search(r'Texture\s*\*\s*const\s+' + re.escape(tex_sym) + r'\s*\[\s*\]\s*=\s*\{(.*?)\}', t, re.S)
        syms = [x.strip() for x in am.group(1).split(',') if x.strip()] if am else []
        imgs = []
        for sy in syms:
            png = db.tex.get(sy)
            if png and os.path.exists(os.path.join(D, png)):
                imgs.append(Image.open(os.path.join(D, png)).convert('RGBA'))
        if not imgs:
            print('  painting has no images', name, syms)
            continue
        # images are listed bottom first; stack vertically with last (top) on top
        w = imgs[0].width
        total_h = sum(i.height for i in imgs)
        canvas = Image.new('RGBA', (w, total_h))
        y = 0
        for im in reversed(imgs):
            canvas.paste(im, (0, y)); y += im.height
        key = 'painting_' + name.replace('_painting', '')
        os.makedirs(out_tex_dir, exist_ok=True)
        canvas.save(os.path.join(out_tex_dir, key + '.png'))
        th_ = math.radians(rot_yaw)
        c, s_ = math.cos(th_), math.sin(th_)
        ph_ = math.radians(rot_pitch)
        cp, sp = math.cos(ph_), math.sin(ph_)
        # the painting's own axes after Mario 64 turns it: R_y(yaw) * R_x(pitch)
        def turn(v):
            x, y, z = v[0], v[1] * cp - v[2] * sp, v[1] * sp + v[2] * cp
            return (x * c + z * s_, y, -x * s_ + z * c)
        right, up, normal = turn((1, 0, 0)), turn((0, 1, 0)), turn((0, 0, 1))
        def corner(a, b):
            return tuple(pos[k] + right[k] * a + up[k] * b for k in range(3))
        corners = [corner(0, 0), corner(size, 0), corner(size, size), corner(0, size)]
        def ue(p):
            return [-p[2] * SCALE, p[0] * SCALE, p[1] * SCALE]
        # a painting's three strips use warp nodes id*3 .. id*3+2 of its area; all three lead to one place
        pw = (pwarps or {}).get(pid * 3)
        target = pw['scene'] if pw else (PAINTING_ORDER[pid] if pwarps is None and pid < len(PAINTING_ORDER) else None)
        out.append({'name': name.replace('_painting', ''), 'id': pid, 'target': target, 'node': pw['node'] if pw else None,
                    'texture': key, 'corners': [round(v, 2) for c_ in corners for v in ue(c_)],
                    'normal': [round(-normal[2], 4), round(normal[0], 4), round(normal[1], 4)], 'size': size * SCALE})
        print('  painting', name, 'id', pid, 'size', size, 'images', len(imgs), 'canvas', canvas.size)
    return out
