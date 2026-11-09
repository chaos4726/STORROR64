#!/usr/bin/env python3
"""
sm64x.py - converts SM64 decomp data (textures extracted from the user's own ROM)
into Lua tables for the Storror "SM64Map" UE4SS mod.

Coordinate mapping (SM64 -> Unreal): X = -z, Y = x, Z = y, then * SCALE.
"""
import os, re, sys, math, shutil
from collections import OrderedDict
from PIL import Image

D = os.environ.get("SM64_DECOMP", "/home/claude/sm64work/decomp")
SCALE = float(os.environ.get('SM64_SCALE', '0.75'))
# G_TEXTURE_GEN laid on as a sphere map, by each corner's normal as if seen from the front (s from its x, t from its y -
# the N64's way: the pictures made for it bright at their bottom, lit from above), and a decal one drawn in the picture's
# own colour. Only for the Render96 models (tools/r96_models.py sets it): their gold, metal and shine are all such maps,
# and laid on by their stored UVs - or tinted by whatever light came before them - the door stars came out red and half
# the keyhole black ("stars on doors showing red", "key doors missing texture", 2026-10-31). Mario 64's own export as it was.
SPHERE = os.environ.get('SM64_TEXGEN_SPHERE') == '1'
# A picture bigger than its material says (gsDPSetTileSize) by a whole number of times - an HD one in the material's
# place - its UVs laid on as the material's size, as the PC port lays them: Render96's snow and spiky tree trunks are
# 1024 pictures in 512 materials, and laid on as 1024 they took the picture's empty top - "snow trees missing tree",
# 2026-10-31. Only for the Render96 models (tools/r96_models.py sets it).
HD_TILE = os.environ.get('SM64_HD_TILE') == '1'



# ----------------------------------------------------------------- C helpers
def _us_defines():
    """The macros the US game's data is built with: VERSION_US, and config.h's BUGFIX_* (each an expression of
    VERSION_*), evaluated."""
    d = {'VERSION_US': 1, 'VERSION_JP': 0, 'VERSION_EU': 0, 'VERSION_SH': 0, 'VERSION_CN': 0}
    p = os.path.join(D, 'include', 'config.h')
    if os.path.exists(p):
        for m in re.finditer(r'^#define\s+(BUGFIX_\w+)\s+(.+)$', open(p, encoding='utf-8', errors='replace').read(), re.M):
            v = _eval_cond(m.group(2), d)
            if v is not None:
                d[m.group(1)] = int(v)
    return d


def _eval_cond(expr, d):
    """A preprocessor condition over known macros (defined(X), X, !, ||, &&, numbers), or None when it names
    anything else"""
    e = re.sub(r'defined\s*\(\s*(\w+)\s*\)', lambda m: ' 1 ' if d.get(m.group(1)) else ' 0 ', expr)
    e = re.sub(r'defined\s+(\w+)', lambda m: ' 1 ' if d.get(m.group(1)) else ' 0 ', e)
    for name in set(re.findall(r'\b[A-Za-z_]\w*\b', e)):
        if name not in d:
            return None
    e = re.sub(r'\b[A-Za-z_]\w*\b', lambda m: ' %d ' % d[m.group(0)], e)
    e = e.replace('||', ' or ').replace('&&', ' and ')
    e = re.sub(r'!(?!=)', ' not ', e)
    try:
        return bool(eval(e, {'__builtins__': {}}, {}))
    except Exception:
        return None


_US = None


def us_only(t):
    """C source as the US game is built: of each #if/#ifdef/#ifndef block over VERSION_* or BUGFIX_* macros, only
    the half the US build takes (both halves were read before 2026-10-15: JP and US vertices, collision and objects
    side by side - JRB's star box held a loose JP star and a Wing Cap). Blocks over anything else are left whole."""
    global _US
    if '#if' not in t:
        return t
    if _US is None:
        _US = _us_defines()
    out, stack = [], []            # each: [resolved?, this branch on?, a branch taken?]
    for line in t.split('\n'):
        s = line.strip()
        if s.startswith('#if'):
            if s.startswith('#ifdef'):
                c = _eval_cond('defined(%s)' % s[6:].strip(), _US)
            elif s.startswith('#ifndef'):
                c = _eval_cond('!defined(%s)' % s[7:].strip(), _US)
            else:
                c = _eval_cond(s[3:], _US)
            if c is None:
                stack.append([False, True, True])
                out.append(line)
            else:
                stack.append([True, c, c])
                out.append('')
            continue
        if stack and (s.startswith('#elif') or s.startswith('#else') or s.startswith('#endif')):
            top = stack[-1]
            if not top[0]:
                out.append(line)
                if s.startswith('#endif'):
                    stack.pop()
                continue
            if s.startswith('#elif'):
                c = _eval_cond(s[5:], _US)
                c = bool(c) and not top[2]
                top[1], top[2] = c, top[2] or c
            elif s.startswith('#else'):
                top[1], top[2] = not top[2], True
            else:
                stack.pop()
            out.append('')
            continue
        out.append(line if all(e[1] for e in stack) else '')
    return '\n'.join(out)


def strip_comments(t):
    t = re.sub(r'/\*.*?\*/', '', t, flags=re.S)
    t = re.sub(r'//[^\n]*', '', t)
    return us_only(t)


def match_close(s, i, open_ch, close_ch):
    depth = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c == open_ch:
            depth += 1
        elif c == close_ch:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError("unbalanced " + open_ch)


def split_args(s):
    out, depth, cur = [], 0, []
    for ch in s:
        if ch in '({[':
            depth += 1
        elif ch in ')}]':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(''.join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    last = ''.join(cur).strip()
    if last or out:
        out.append(last)
    return out


CAST = re.compile(r'\((?:s|u)(?:8|16|32)\)\s*')


def to_int(s):
    s = CAST.sub('', s.strip())
    try:
        return int(s, 0)
    except ValueError:
        pass
    try:
        return int(eval(s, {"__builtins__": {}}, {}))
    except Exception:
        raise ValueError("cannot parse int: " + s)


def try_int(s, default=None):
    try:
        return to_int(s)
    except Exception:
        return default


def s8(v):
    v &= 0xFF
    return v - 256 if v > 127 else v


# ----------------------------------------------------------------- source index
class DB:
    VTX = re.compile(r'(?:static\s+)?const\s+Vtx\s+(\w+)\s*\[\s*\]\s*=\s*\{')
    GFX = re.compile(r'(?:static\s+)?const\s+Gfx\s+(\w+)\s*\[\s*\]\s*=\s*\{')
    COL = re.compile(r'const\s+Collision\s+(\w+)\s*\[\s*\]\s*=\s*\{')
    GEO = re.compile(r'const\s+GeoLayout\s+(\w+)\s*\[\s*\]\s*=\s*\{')
    LIGHT = re.compile(r'(?:static\s+)?const\s+Lights1\s+(\w+)\s*=\s*gdSPDefLights1\s*\(([^)]*)\)')
    TEX = re.compile(r'const\s+Texture\s+(\w+)\s*\[\s*\]\s*=\s*\{\s*#include\s+"([^"]+?)\.inc\.c"')
    ANIM = re.compile(r'static\s+const\s+struct\s+Animation\s+(\w+)\s*=\s*\{')
    S16 = re.compile(r'static\s+const\s+s16\s+(\w+)\s*\[\s*\]\s*=\s*\{')
    U16 = re.compile(r'static\s+const\s+u16\s+(\w+)\s*\[\s*\]\s*=\s*\{')
    ANIMPTRS = re.compile(r'const\s+struct\s+Animation\s*\*\s*const\s+(\w+)\s*\[\s*\]\s*=\s*\{')

    def __init__(self):
        self.src = {}      # kind -> name -> (file, start_of_body) ; body found lazily
        self.text = {}
        self.cache = {}
        self.light = {}
        self.tex = {}
        for kind in ('vtx', 'gfx', 'col', 'geo', 'anim', 's16', 'u16', 'animptrs'):
            self.src[kind] = {}
        pats = [('vtx', self.VTX), ('gfx', self.GFX), ('col', self.COL), ('geo', self.GEO),
                ('anim', self.ANIM), ('s16', self.S16), ('u16', self.U16), ('animptrs', self.ANIMPTRS)]
        for root in ('levels', 'actors', 'textures'):
            base = os.path.join(D, root)
            for dp, dn, fn in os.walk(base):
                for f in fn:
                    if not f.endswith('.c'):
                        continue
                    path = os.path.join(dp, f)
                    t = strip_comments(open(path, encoding='utf-8', errors='replace').read())
                    if not re.search(r'const\s+(Vtx|Gfx|Collision|GeoLayout|Lights1|Texture|struct\s+Animation|s16|u16)', t):
                        continue
                    self.text[path] = t
                    for kind, rx in pats:
                        for m in rx.finditer(t):
                            self.src[kind].setdefault(m.group(1), (path, m.end() - 1))
                    for m in self.LIGHT.finditer(t):
                        self.light.setdefault(m.group(1), [try_int(x, 0) for x in split_args(m.group(2))])
                    for m in self.TEX.finditer(t):
                        self.tex.setdefault(m.group(1), m.group(2) + '.png')
        # textures named in bin/*.c (texture_metal_hole, bin/sky.c: the flamethrower holes in BitDW, BitFS, BitS, RR -
        # never found, they drew white: "no hole on the flamer", 2026-10-17)
        bbase = os.path.join(D, 'bin')
        for f in sorted(os.listdir(bbase)) if os.path.isdir(bbase) else []:
            if f.endswith('.c'):
                t = strip_comments(open(os.path.join(bbase, f), encoding='utf-8', errors='replace').read())
                for m in self.TEX.finditer(t):
                    self.tex.setdefault(m.group(1), m.group(2) + '.png')
        # shared texture banks: <bank>_09XXXXXX -> textures/<bank>/*.XXXXX.<fmt>.png
        trx = re.compile(r'\.([0-9A-F]{5})\.\w+\.png$')
        tbase = os.path.join(D, 'textures')
        for bank in sorted(os.listdir(tbase)):
            bp = os.path.join(tbase, bank)
            if not os.path.isdir(bp):
                continue
            for f in sorted(os.listdir(bp)):
                m = trx.search(f)
                if m:
                    sym = '%s_09%06X' % (bank, int(m.group(1), 16))
                    self.tex.setdefault(sym, 'textures/%s/%s' % (bank, f))

    def body(self, kind, name):
        key = (kind, name)
        if key in self.cache:
            return self.cache[key]
        if name not in self.src[kind]:
            raise KeyError("%s %s not found" % (kind, name))
        path, i = self.src[kind][name]
        t = self.text[path]
        j = match_close(t, i, '{', '}')
        b = t[i + 1:j]
        self.cache[key] = b
        return b

    def has(self, kind, name):
        return name in self.src[kind]

    # --- parsed forms
    def vtx(self, name):
        key = ('vtxp', name)
        if key in self.cache:
            return self.cache[key]
        b = self.body('vtx', name)
        out = []
        rx = re.compile(r'\{\{\{\s*(-?\w+)\s*,\s*(-?\w+)\s*,\s*(-?\w+)\s*\}\s*,\s*\w+\s*,\s*\{\s*(-?\w+)\s*,\s*(-?\w+)\s*\}\s*,\s*\{([^}]*)\}\s*\}\s*\}')
        for m in rx.finditer(b):
            c = [to_int(x) for x in m.group(6).split(',')]
            out.append((to_int(m.group(1)), to_int(m.group(2)), to_int(m.group(3)),
                        to_int(m.group(4)), to_int(m.group(5)), c[0] & 255, c[1] & 255, c[2] & 255, c[3] & 255))
        self.cache[key] = out
        return out

    def commands(self, kind, name, prefix):
        """Generic macro list: [(macro, [args...])]"""
        key = (kind + 'cmds', name)
        if key in self.cache:
            return self.cache[key]
        b = self.body(kind, name)
        out = []
        rx = re.compile(r'\b(' + prefix + r'\w*)\s*\(')
        pos = 0
        while True:
            m = rx.search(b, pos)
            if not m:
                break
            j = match_close(b, m.end() - 1, '(', ')')
            out.append((m.group(1), split_args(b[m.end():j])))
            pos = j + 1
        self.cache[key] = out
        return out

    def tex_dims(self, sym):
        png = self.tex.get(sym)
        if not png:
            return None
        p = os.path.join(D, png)
        if not os.path.exists(p):
            return None
        key = ('texdim', p)
        if key not in self.cache:
            with Image.open(p) as im:
                self.cache[key] = im.size
        return self.cache[key]


# ----------------------------------------------------------------- transforms (SM64 space)
def xf_identity():
    return ([[1, 0, 0], [0, 1, 0], [0, 0, 1]], [0, 0, 0])


def xf_apply(xf, p):
    R, T = xf
    return tuple(R[i][0] * p[0] + R[i][1] * p[1] + R[i][2] * p[2] + T[i] for i in range(3))


def xf_apply_dir(xf, d):
    R, _ = xf
    v = [R[i][0] * d[0] + R[i][1] * d[1] + R[i][2] * d[2] for i in range(3)]
    l = math.sqrt(sum(c * c for c in v)) or 1.0
    return tuple(c / l for c in v)


def xf_mul(a, b):
    """a * b : apply b first, then a"""
    Ra, Ta = a
    Rb, Tb = b
    R = [[sum(Ra[i][k] * Rb[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    T = [sum(Ra[i][k] * Tb[k] for k in range(3)) + Ta[i] for i in range(3)]
    return (R, T)


def xf_translate(x, y, z):
    return ([[1, 0, 0], [0, 1, 0], [0, 0, 1]], [x, y, z])


def xf_scale(sc):
    return ([[sc, 0, 0], [0, sc, 0], [0, 0, sc]], [0, 0, 0])


def sm64_euler_col(rx, ry, rz):
    """SM64 mtxf_rotate_xyz: returns the 3x3 rotation acting on COLUMN vectors. Angles in radians."""
    sx, cx, sy, cy, sz, cz = math.sin(rx), math.cos(rx), math.sin(ry), math.cos(ry), math.sin(rz), math.cos(rz)
    A = [[cy * cz, cy * sz, -sy],
         [sx * sy * cz - cx * sz, sx * sy * sz + cx * cz, sx * cy],
         [cx * sy * cz + sx * sz, cx * sy * sz - sx * cz, cx * cy]]
    return [[A[j][i] for j in range(3)] for i in range(3)]   # transpose


def xf_rotate_deg(rx, ry, rz):
    return (sm64_euler_col(math.radians(rx), math.radians(ry), math.radians(rz)), [0, 0, 0])


P = [[0, 0, -1], [1, 0, 0], [0, 1, 0]]   # SM64 -> UE axes


def mat_to_quat(R):
    t = R[0][0] + R[1][1] + R[2][2]
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        w = 0.25 * s
        x = (R[2][1] - R[1][2]) / s
        y = (R[0][2] - R[2][0]) / s
        z = (R[1][0] - R[0][1]) / s
    elif R[0][0] > R[1][1] and R[0][0] > R[2][2]:
        s = math.sqrt(1.0 + R[0][0] - R[1][1] - R[2][2]) * 2
        w = (R[2][1] - R[1][2]) / s
        x = 0.25 * s
        y = (R[0][1] + R[1][0]) / s
        z = (R[0][2] + R[2][0]) / s
    elif R[1][1] > R[2][2]:
        s = math.sqrt(1.0 + R[1][1] - R[0][0] - R[2][2]) * 2
        w = (R[0][2] - R[2][0]) / s
        x = (R[0][1] + R[1][0]) / s
        y = 0.25 * s
        z = (R[1][2] + R[2][1]) / s
    else:
        s = math.sqrt(1.0 + R[2][2] - R[0][0] - R[1][1]) * 2
        w = (R[1][0] - R[0][1]) / s
        x = (R[0][2] + R[2][0]) / s
        y = (R[1][2] + R[2][1]) / s
        z = 0.25 * s
    return (x, y, z, w)


def rot_to_ue_quat(Rcol):
    """SM64-space rotation (column convention) -> UE-space quaternion (x,y,z,w)."""
    PR = [[sum(P[i][k] * Rcol[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    Rue = [[sum(PR[i][k] * P[j][k] for k in range(3)) for j in range(3)] for i in range(3)]   # P R P^T
    return mat_to_quat(Rue)


# ----------------------------------------------------------------- display list interpreter
class Mesh:
    """Triangles grouped by (layer, texture) into deduplicated sections."""

    def __init__(self, scale=SCALE, cum=1.0, xf=None):
        self.sections = OrderedDict()
        self.scale = scale
        self.cum = cum   # extra uniform scale (geo scale nodes)
        self.xf = xf     # optional (R, T): p' = R p + T in SM64 space (R may include scale)

    def section(self, layer, tex):
        k = (layer, tex)
        if k not in self.sections:
            self.sections[k] = {'layer': layer, 'texture': tex, 'map': {}, 'pos': [], 'uv': [], 'col': [], 'nrm': [], 'idx': []}
        return self.sections[k]


class GfxState:
    def __init__(self):
        self.vbuf = [None] * 64
        self.tex_sym = None
        self.tex_on = True
        self.lighting = True
        self.light = None     # name
        self.amb = (0x7f, 0x7f, 0x7f)
        self.diff = (0xff, 0xff, 0xff)
        self.dir = (0x28, 0x28, 0x28)
        self.prim = None
        # the environment colour's alpha, which a "fade" combine mode (G_CC_SHADEFADEA, MODULATERGBFADEA, DECALFADEA ...)
        # multiplies into everything drawn: the castle aquarium's glass at 100 of 255, Wing Mario's clouds at 128...
        # (the alpha was dropped and they came out solid, 2026-10-15)
        self.env_a = 255
        self.fade = False
        # a decal combine mode (G_CC_DECALRGB, DECALRGBA, DECALFADE...) draws the texture alone: the vertex colours
        # (or the light) are not in it - the giant pole's yellow ball came out dark red, near black (2026-10-15)
        self.decal = False
        self.tile = None      # (the material's own picture size, gsDPSetTileSize: HD_TILE)
        self.texgen = False   # (environment-mapped - G_TEXTURE_GEN: the star's gold. Its texture cannot be laid on
                              # here as the N64 lays it, by the view; lit, it at least has a shape - left lit)


def parse_vtx_ref(s):
    s = s.strip().lstrip('&').strip()
    m = re.match(r'(\w+)\s*(?:\+\s*(\d+))?$', s)
    if m:
        return m.group(1), int(m.group(2) or 0)
    m = re.match(r'(\w+)\s*\[\s*(\d+)\s*\]$', s)
    if m:
        return m.group(1), int(m.group(2))
    raise ValueError("vtx ref " + s)


def png_key(png):
    """texture key: path without .png, slashes -> '__'."""
    return png[:-4].replace('/', '__')


def interp_dl(db, name, st, mesh, layer, textures, depth=0):
    if depth > 24 or not db.has('gfx', name):
        return False
    for cmd, a in db.commands('gfx', name, 'gs'):
        if cmd == 'gsSPEndDisplayList':
            return True
        elif cmd == 'gsSPDisplayList':
            interp_dl(db, a[0].lstrip('&').strip(), st, mesh, layer, textures, depth + 1)
        elif cmd == 'gsSPBranchList':
            interp_dl(db, a[0].lstrip('&').strip(), st, mesh, layer, textures, depth + 1)
            return True
        elif cmd == 'gsSPVertex':
            nm, off = parse_vtx_ref(a[0])
            n = to_int(a[1]); v0 = to_int(a[2])
            arr = db.vtx(nm)
            for i in range(min(n, len(arr) - off)):       # (hoot_seg5_vertex_05003668: "too large of a size", 12 for 6)
                # (and which part loaded it: a skinned join's triangles use corners its parent's list loaded -
                # emit_tri, mesh.rebase)
                st.vbuf[v0 + i] = (nm, off + i, arr[off + i], getattr(mesh, 'part', None))
        elif cmd in ('gsSP1Triangle', 'gsSP2Triangles'):
            tris = [(a[0], a[1], a[2])]
            if cmd == 'gsSP2Triangles':
                tris.append((a[4], a[5], a[6]))
            for t in tris:
                emit_tri(db, st, mesh, layer, [to_int(x) for x in t], textures)
        elif cmd in ('gsSPSetGeometryMode', 'gsSPClearGeometryMode'):
            if 'G_LIGHTING' in a[0]:
                st.lighting = (cmd == 'gsSPSetGeometryMode')
            if 'G_TEXTURE_GEN' in a[0]:
                st.texgen = (cmd == 'gsSPSetGeometryMode')
        elif cmd == 'gsSPGeometryMode':
            if 'G_LIGHTING' in a[1]:
                st.lighting = True
            elif 'G_LIGHTING' in a[0]:
                st.lighting = False
        elif cmd == 'gsSPTexture':
            st.tex_on = 'G_ON' in a[4] or a[4].strip() == '1'
        elif cmd == 'gsDPSetTextureImage':
            st.tex_sym = a[3].lstrip('&').strip()
            st.tile = None
        elif cmd == 'gsDPSetTileSize':
            try:
                lrs, lrt = to_int(a[3]), to_int(a[4])
                st.tile = ((lrs >> 2) + 1, (lrt >> 2) + 1)
            except Exception:
                st.tile = None
        elif cmd == 'gsDPSetEnvColor':
            try:
                st.env_a = to_int(a[3])
            except Exception:
                pass
        elif cmd == 'gsDPSetCombineMode':
            st.fade = 'FADEA' in a[0]
            st.decal = 'DECAL' in a[0]
        elif cmd in ('gsDPLoadTextureBlock', 'gsDPLoadTextureBlock_4b'):
            st.tex_sym = a[0].lstrip('&').strip()
            st.tile = None
        elif cmd == 'gsSPLight':
            m = re.match(r'&?\s*(\w+)\.(l|a)', a[0].strip())
            if m and m.group(1) in db.light:
                L = db.light[m.group(1)]
                if m.group(2) == 'a':
                    st.amb = tuple(L[0:3])
                else:
                    st.diff = tuple(L[3:6])
                    st.dir = tuple(L[6:9])
                st.light = m.group(1)
        elif cmd == 'gsSPSetLights1':
            nm = a[0].strip()
            if nm in db.light:
                L = db.light[nm]
                st.amb = tuple(L[0:3]); st.diff = tuple(L[3:6]); st.dir = tuple(L[6:9]); st.light = nm
    return False


def to_ue(x, y, z, s):
    return (-z * s, x * s, y * s)


def emit_tri(db, st, mesh, layer, ids, textures):
    verts = [st.vbuf[i] for i in ids]
    if any(v is None for v in verts):
        return
    tex_sym = st.tex_sym if st.tex_on else None
    tex_key = None
    dims = None
    if tex_sym and tex_sym in db.tex:
        dims = db.tex_dims(tex_sym)
        if dims and HD_TILE and st.tile:
            tw, th = st.tile
            if tw > 0 and th > 0 and dims[0] % tw == 0 and dims[1] % th == 0 and dims[0] // tw == dims[1] // th > 1:
                dims = (tw, th)
        if dims:
            tex_key = png_key(db.tex[tex_sym])
            textures[tex_key] = db.tex[tex_sym]
    sec = mesh.section(layer, tex_key)
    s = mesh.scale * mesh.cum
    xfk = id(mesh.xf)
    fa = (st.env_a / 255.0) if st.fade else 1.0
    for (nm, idx, v, src) in verts:
        dec = st.decal and dims is not None and (not st.texgen or SPHERE)
        sph = SPHERE and st.texgen and st.lighting and dims is not None
        # (a corner another part loaded - fast64's skinned joins, Render96's Dorrie's neck: "dori is missing its neck
        # texture", 2026-10-31 - moved into this part's frame as the model stands; it goes with this part)
        cur = getattr(mesh, 'part', None)
        rb = (0.0, 0.0, 0.0)
        if src is not None and cur is not None and src != cur and getattr(mesh, 'rebase', None):
            rb = mesh.rebase(src, cur)
        key = (nm, idx, st.lighting, st.light, tex_key, xfk, fa, dec, sph, src if rb != (0.0, 0.0, 0.0) else None)
        li = sec['map'].get(key)
        if li is None:
            li = len(sec['map'])
            sec['map'][key] = li
            x, y, z, u, vv, r, g, b, a = v
            x, y, z = x + rb[0], y + rb[1], z + rb[2]
            if mesh.xf is not None:
                x, y, z = xf_apply(mesh.xf, (x, y, z))
            px, py, pz = to_ue(x, y, z, s)
            sec['pos'] += [px, py, pz]
            if sph:
                gx, gy, gz = s8(r) / 127.0, s8(g) / 127.0, s8(b) / 127.0
                if mesh.xf is not None:
                    gx, gy, gz = xf_apply_dir(mesh.xf, (gx, gy, gz))
                gl = math.sqrt(gx * gx + gy * gy + gz * gz) or 1.0
                sec['uv'] += [0.5 + 0.48 * gx / gl, 0.5 + 0.48 * gy / gl]
            elif dims:
                sec['uv'] += [u / 32.0 / dims[0], vv / 32.0 / dims[1]]
            else:
                sec['uv'] += [0.0, 0.0]
            if st.lighting:
                nx, ny, nz = s8(r) / 127.0, s8(g) / 127.0, s8(b) / 127.0
                dx, dy, dz = [s8(c) / 127.0 for c in st.dir]
                dl = math.sqrt(dx * dx + dy * dy + dz * dz) or 1.0
                dot = max(0.0, (nx * dx + ny * dy + nz * dz) / dl)
                col = [min(1.0, (st.amb[i] + st.diff[i] * dot) / 255.0) for i in range(3)]
                if dec:
                    col = [1.0, 1.0, 1.0]
                sec['col'] += col + [fa]
                if mesh.xf is not None:
                    nx, ny, nz = xf_apply_dir(mesh.xf, (nx, ny, nz))
                sec['nrm'] += [-nz, nx, ny]
            elif dec:
                sec['col'] += [1.0, 1.0, 1.0, a / 255.0 * fa]
                sec['nrm'] += [0.0, 0.0, 1.0]
            else:
                sec['col'] += [r / 255.0, g / 255.0, b / 255.0, a / 255.0 * fa]
                sec['nrm'] += [0.0, 0.0, 1.0]
        sec['idx'].append(li)


def finish_sections(mesh):
    out = []
    for i, ((layer, tex), sec) in enumerate(mesh.sections.items()):
        out.append({'id': i, 'layer': layer, 'texture': tex,
                    'nverts': len(sec['map']), 'ntris': len(sec['idx']) // 3,
                    'pos': sec['pos'], 'uv': sec['uv'], 'col': sec['col'], 'nrm': sec['nrm'], 'idx': sec['idx']})
    return out


LAYER_NAMES = {
    'LAYER_FORCE': 'opaque', 'LAYER_OPAQUE': 'opaque', 'LAYER_OPAQUE_DECAL': 'opaque_decal',
    'LAYER_OPAQUE_INTER': 'opaque', 'LAYER_ALPHA': 'alpha', 'LAYER_TRANSPARENT': 'translucent',
    'LAYER_TRANSPARENT_DECAL': 'translucent_decal', 'LAYER_TRANSPARENT_INTER': 'translucent',
}


def layer_name(s):
    return LAYER_NAMES.get(s.strip(), 'opaque')


# ----------------------------------------------------------------- geo layouts
def parse_geo(db, name):
    """Return a tree: root {'children':[nodes]}; a node = {'cmd','args','children'}.
    OPEN after CLOSE re-opens the same owner node (as the SM64 engine does)."""
    cmds = db.commands('geo', name, 'GEO_')
    root = {'cmd': 'ROOT', 'args': [], 'children': []}
    stack = []
    cur = root
    last = root
    for cmd, a in cmds:
        if cmd == 'GEO_OPEN_NODE':
            stack.append(cur)
            cur = last
            continue
        if cmd == 'GEO_CLOSE_NODE':
            if stack:
                last = cur
                cur = stack.pop()
            continue
        if cmd in ('GEO_END', 'GEO_RETURN'):
            continue
        node = {'cmd': cmd, 'args': a, 'children': []}
        cur['children'].append(node)
        last = node
    return root


def collect_level_dls(db, geo_name, seen=None, with_scale=False):
    """flat list of (layer, dl) for an area/level geo layout, following GEO_BRANCH; with_scale: (layer, dl, scale), the
    GEO_SCALE nodes over it multiplied (THI's tiny island draws the huge one's lists at 19660/65536 - left out, its
    picture came out three times its collision's size, 2026-10-29)"""
    seen = seen or set()
    out = []

    def walk(node, k):
        for ch in node['children']:
            c = ch['cmd']
            kk = k
            if c == 'GEO_DISPLAY_LIST':
                ly, dl = layer_name(ch['args'][0]), ch['args'][1].strip()
                out.append((ly, dl, k) if with_scale else (ly, dl))
            elif c in ('GEO_SCALE', 'GEO_SCALE_WITH_DL'):
                kk = k * to_int(ch['args'][1]) / 65536.0
                if c == 'GEO_SCALE_WITH_DL':
                    ly, dl = layer_name(ch['args'][0]), ch['args'][2].strip()
                    out.append((ly, dl, kk) if with_scale else (ly, dl))
            elif c in ('GEO_BRANCH', 'GEO_BRANCH_AND_LINK'):
                tgt = ch['args'][-1].strip()
                if tgt not in seen and db.has('geo', tgt):
                    seen.add(tgt)
                    walk(parse_geo(db, tgt), k)
            walk(ch, kk)
    walk(parse_geo(db, geo_name), 1.0)
    return out


# ----------------------------------------------------------------- collision
def parse_collision(db, name):
    cmds = db.commands('col', name, 'COL_')
    verts, groups, cur = [], [], None
    water = []
    for c, a in cmds:
        if c == 'COL_VERTEX':
            verts.append(tuple(to_int(x) for x in a[:3]))
        elif c == 'COL_TRI_INIT':
            cur = {'surface': a[0].strip(), 'tris': [], 'force': []}
            groups.append(cur)
        elif c in ('COL_TRI', 'COL_TRI_SPECIAL'):
            cur['tris'].append(tuple(to_int(x) for x in a[:3]))
            # (a special triangle's fourth number: the horizontal wind's direction >> 8, a moving quicksand's...)
            cur['force'].append(to_int(a[3]) if c == 'COL_TRI_SPECIAL' and len(a) > 3 else 0)
        elif c == 'COL_WATER_BOX':
            water.append([to_int(x) for x in a[:6]])
    return verts, groups, water


# (SURFACE_HORIZONTAL_WIND is floor in Mario 64 - find_floor skips none of these kinds but the intangible: it was left
# out from the start, and the windy floors of BitS, RR, SL and THI were holes, 2026-10-15)
SKIP_SURFACES = ('SURFACE_DEATH_PLANE', 'SURFACE_VERTICAL_WIND', 'SURFACE_INTANGIBLE')


def export_collision(db, name, offset=(0, 0, 0), scale=SCALE, yaw=0.0, only=None, skip=()):
    """`only`: just these surface types; `skip`: all but these (the vanish-cap walls are exported apart, 2026-10-15)"""
    verts, groups, water = parse_collision(db, name)
    if yaw:
        cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        verts = [(x * cy + z * sy, y, -x * sy + z * cy) for (x, y, z) in verts]
    pos, idx, vmap = [], [], {}
    n_tris = 0
    surf = {}
    for g in groups:
        if g['surface'] in SKIP_SURFACES or g['surface'] in skip or (only is not None and g['surface'] not in only):
            continue
        for (a, b, c) in g['tris']:
            for vi in (a, b, c):
                if vi not in vmap:
                    vmap[vi] = len(vmap)
                    x, y, z = verts[vi]
                    pos += list(to_ue(x + offset[0], y + offset[1], z + offset[2], scale))
                idx.append(vmap[vi])
            n_tris += 1
            surf[g['surface']] = surf.get(g['surface'], 0) + 1
    wb = [{'id': w[0], 'x1': w[1] * scale, 'z1': w[2] * scale, 'x2': w[3] * scale, 'z2': w[4] * scale, 'y': w[5] * scale} for w in water]
    return {'source': name, 'ntris': n_tris, 'pos': pos, 'idx': idx, 'surfaces': surf, 'water': wb}


# ----------------------------------------------------------------- level scripts / objects
OBJ_RX = re.compile(r'\b(OBJECT|OBJECT_WITH_ACTS)\s*\(')
AREA_RX = re.compile(r'\b(AREA|END_AREA)\s*\(')
MACRO_RX = re.compile(r'\b(MACRO_OBJECT|MACRO_OBJECT_WITH_BHV_PARAM)\s*\(')


def acts_mask(expr):
    """OBJECT_WITH_ACTS's acts (ACT_1 | ACT_3, ALL_ACTS, or a number) as a bit mask of acts 1-6"""
    expr = expr.strip()
    if 'ALL_ACTS' in expr:
        return 0x3F
    m = 0
    for n in re.findall(r'ACT_(\d)', expr):
        m |= 1 << (int(n) - 1)
    if m == 0:
        v = try_int(expr)
        m = (v & 0x3F) if v is not None else 0x3F
    return m


def parse_objects(level):
    """Objects, warps and macro tables of a level's script.c, each tagged with the area it belongs to.
    A level script is several arrays; the ones an area pulls in with JUMP_LINK hold most of its objects,
    so those are attributed to the area that links them."""
    p = os.path.join(D, 'levels', level, 'script.c')
    t = strip_comments(open(p, encoding='utf-8', errors='replace').read())
    rx = re.compile(r'\b(OBJECT_WITH_ACTS|OBJECT|AREA|END_AREA|WARP_NODE|PAINTING_WARP_NODE|MACRO_OBJECTS|JUMP_LINK|MARIO_POS)\s*\(')
    funcs, links = {}, []
    for fm in re.finditer(r'const\s+LevelScript\s+(\w+)\s*\[\s*\]\s*=\s*\{', t):
        end = match_close(t, fm.end() - 1, '{', '}')
        body = t[fm.end():end]
        entries, area, pos = [], 0, 0
        while True:
            m = rx.search(body, pos)
            if not m:
                break
            j = match_close(body, m.end() - 1, '(', ')')
            a_ = split_args(body[m.end():j])
            k = m.group(1)
            if k == 'AREA':
                area = to_int(a_[0])
            elif k == 'END_AREA':
                area = 0
            elif k in ('OBJECT', 'OBJECT_WITH_ACTS'):
                try:
                    e = {'area': area, 'model': a_[0], 'x': to_int(a_[1]), 'y': to_int(a_[2]), 'z': to_int(a_[3]),
                         'ax': to_int(a_[4]), 'ay': to_int(a_[5]), 'az': to_int(a_[6]), 'bparam': a_[7], 'bhv': a_[8]}
                    if k == 'OBJECT_WITH_ACTS' and len(a_) > 9:
                        e['acts'] = acts_mask(a_[9])
                    entries.append(e)
                except Exception:
                    pass
            elif k == 'WARP_NODE' or k == 'PAINTING_WARP_NODE':
                entries.append({'area': area, 'warp': k, 'args': a_})
            elif k == 'MACRO_OBJECTS':
                entries.append({'area': area, 'macro_table': a_[0]})
            elif k == 'JUMP_LINK' and area:
                links.append((area, a_[0].strip()))
            pos = j + 1
        funcs[fm.group(1)] = entries
    out = [e for es in funcs.values() for e in es if e['area']]
    for area, target in links:
        for e in funcs.get(target, []):
            if not e['area']:
                out.append(dict(e, area=area))
    return out


def behavior_collisions():
    """behavior name -> the collision model it loads (data/behavior_data.c)."""
    t = strip_comments(open(os.path.join(D, 'data', 'behavior_data.c'), encoding='utf-8', errors='replace').read())
    out = {}
    for m in re.finditer(r'const\s+BehaviorScript\s+(\w+)\s*\[\s*\]\s*=\s*\{', t):
        end = match_close(t, m.end() - 1, '{', '}')
        c = re.search(r'LOAD_COLLISION_DATA\(\s*(\w+)\s*\)', t[m.end():end])
        if c:
            out[m.group(1)] = c.group(1)
    return out


def parse_macro_objects(level, area_dir):
    p = os.path.join(D, 'levels', level, 'areas', str(area_dir), 'macro.inc.c')
    if not os.path.exists(p):
        return []
    t = strip_comments(open(p, encoding='utf-8', errors='replace').read())
    out = []
    pos = 0
    rx = re.compile(r'\b(MACRO_OBJECT_WITH_BHV_PARAM|MACRO_OBJECT)\s*\(')
    while True:
        m = rx.search(t, pos)
        if not m:
            break
        j = match_close(t, m.end() - 1, '(', ')')
        a = split_args(t[m.end():j])
        try:
            out.append({'preset': a[0], 'yaw': to_int(a[1]), 'x': to_int(a[2]), 'y': to_int(a[3]), 'z': to_int(a[4]),
                        'bparam': a[5] if len(a) > 5 else '0'})
        except Exception:
            pass
        pos = j + 1
    return out


# ----------------------------------------------------------------- Lua writer
def lua_num(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, int):
        return str(v)
    s = ('%.4f' % v).rstrip('0').rstrip('.')
    return s if s not in ('-0', '') else '0'


def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def to_lua(v, indent=0, flat_threshold=24):
    pad = '  ' * indent
    if v is None:
        return 'nil'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return lua_num(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, (list, tuple)):
        if all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in v):
            return '{' + ','.join(lua_num(x) for x in v) + '}'
        inner = (',\n' + pad + '  ').join(to_lua(x, indent + 1) for x in v)
        return '{\n' + pad + '  ' + inner + '\n' + pad + '}'
    if isinstance(v, dict):
        items = []
        for k, x in v.items():
            if x is None:
                continue
            kk = k if re.match(r'^[A-Za-z_]\w*$', str(k)) else '[%s]' % (lua_str(k) if isinstance(k, str) else k)
            items.append('%s = %s' % (kk, to_lua(x, indent + 1)))
        return '{\n' + pad + '  ' + (',\n' + pad + '  ').join(items) + '\n' + pad + '}'
    raise TypeError(type(v))


def write_lua(path, value, header=''):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write('-- generated by sm64x.py from the user\'s own SM64 ROM; do not edit\n' + header)
        f.write('return ' + to_lua(value) + '\n')


def copy_textures(textures, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    n = 0
    for key, png in textures.items():
        src = os.path.join(D, png)
        dst = os.path.join(out_dir, key + '.png')
        if os.path.exists(src):
            shutil.copyfile(src, dst)
            n += 1
    return n
