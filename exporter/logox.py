"""The title logo: Mario 64's own 3D logo, drawn from the player's copy of the game, with the word MARIO
taken out and the STORROR wordmark set in its place: SUPER STORROR 64.

The logo is a model in the game's intro level (levels/intro/leveldata.c). This reads its display list,
splits it into letters (pieces that share no corner), keeps the row that says SUPER and the 64, and draws
them the way the game's camera sees them. The wordmark is a picture supplied by the user (white on
black); it is given the logo's wooden sides so that it sits in the same block of letters."""
import os, re, math, sys
import numpy as np
from PIL import Image

D = os.environ.get('SM64_DECOMP', 'X:/mashup-work/sm64decomp')
INTRO = os.path.join(D, 'levels', 'intro')


def us_text():
    """leveldata.c as the US game is built: of every #if block, the #else half"""
    keep, out, mode = True, [], None
    for line in open(os.path.join(INTRO, 'leveldata.c'), encoding='utf-8', errors='replace'):
        s = line.strip()
        if s.startswith('#if'):
            mode, keep = 'if', False
        elif s.startswith('#else') and mode:
            keep = True
        elif s.startswith('#endif') and mode:
            mode, keep = None, True
        elif keep:
            out.append(line)
    return re.sub(r'//[^\n]*', '', ''.join(out))


def parse(t):
    vtx, dls = {}, {}
    for m in re.finditer(r'const\s+Vtx\s+(\w+)\s*\[\s*\]\s*=\s*\{(.*?)\};', t, re.S):
        rows = []
        for r in re.finditer(r'\{\{\{\s*(-?\d+),\s*(-?\d+),\s*(-?\d+)\s*\},\s*\w+,\s*\{\s*(-?\d+),\s*(-?\d+)\s*\},\s*\{\s*(\w+),\s*(\w+),\s*(\w+),\s*(\w+)\s*\}\}\}', m.group(2)):
            g = r.groups()
            rows.append([int(g[0]), int(g[1]), int(g[2]), int(g[3]), int(g[4])] + [int(v, 0) for v in g[5:9]])
        vtx[m.group(1)] = rows
    for m in re.finditer(r'const\s+Gfx\s+(\w+)\s*\[\s*\]\s*=\s*\{(.*?)\n\};', t, re.S):
        dls[m.group(1)] = re.findall(r'\b(gs\w+)\s*\(([^;]*?)\),?\s*\n', m.group(2) + '\n')
    return vtx, dls


def triangles(vtx, dls, name='intro_seg7_dl_logo'):
    """[(v0, v1, v2, texture or None)], a vertex being [x, y, z, s, t, r, g, b, a]"""
    out = []
    st = {'tex': None, 'on': False, 'buf': {}}

    def run(n):
        for cmd, args in dls[n]:
            a = [x.strip() for x in args.split(',')]
            if cmd == 'gsSPDisplayList':
                run(a[0])
            elif cmd == 'gsDPSetTextureImage':
                st['tex'] = a[3]
            elif cmd == 'gsSPTexture':
                st['on'] = a[4] == 'G_ON'
            elif cmd == 'gsSPVertex':
                src, n_, v0 = vtx[a[0]], int(a[1], 0), int(a[2], 0)
                for i in range(n_):
                    st['buf'][v0 + i] = src[i]
            elif cmd in ('gsSP1Triangle', 'gsSP2Triangles'):
                ids = [int(x, 0) for x in a]
                for k in ((0, 1, 2),) if cmd == 'gsSP1Triangle' else ((0, 1, 2), (4, 5, 6)):
                    out.append((st['buf'][ids[k[0]]], st['buf'][ids[k[1]]], st['buf'][ids[k[2]]], st['tex'] if st['on'] else None))
    run(name)
    return out


def letters(tris):
    """the logo's separate pieces: triangles grouped by shared corners -> [[triangle index, ...], ...]"""
    parent = list(range(len(tris)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    seen = {}
    for i, t in enumerate(tris):
        for v in t[:3]:
            key = (v[0], v[1], v[2])
            if key in seen:
                a, b = find(i), find(seen[key])
                if a != b:
                    parent[a] = b
            else:
                seen[key] = i
    groups = {}
    for i in range(len(tris)):
        groups.setdefault(find(i), []).append(i)
    return list(groups.values())


# ---------------------------------------------------------------- drawing
FOVY = 45.0
CAM_Z = 3200.0


class Canvas:
    def __init__(self, w, h, zoom=1.0, shift=(0.0, 0.0)):
        self.w, self.h = w, h
        self.f = (h / 2.0) / math.tan(math.radians(FOVY / 2.0)) * zoom     # pixels per unit at distance 1
        self.shift = shift
        self.rgb = np.zeros((h, w, 3), np.float32)
        self.cover = np.zeros((h, w), np.float32)
        self.depth = np.full((h, w), np.inf, np.float32)

    def project(self, x, y, z):
        d = CAM_Z - z
        return self.w / 2.0 + x * self.f / d + self.shift[0], self.h / 2.0 - y * self.f / d + self.shift[1], d

    def triangle(self, t, textures):
        (x0, y0, d0), (x1, y1, d1), (x2, y2, d2) = (self.project(*v[:3]) for v in t[:3])
        area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if abs(area) < 1e-9:
            return
        xa, xb = max(0, int(math.floor(min(x0, x1, x2)))), min(self.w - 1, int(math.ceil(max(x0, x1, x2))))
        ya, yb = max(0, int(math.floor(min(y0, y1, y2)))), min(self.h - 1, int(math.ceil(max(y0, y1, y2))))
        if xa > xb or ya > yb:
            return
        px, py = np.meshgrid(np.arange(xa, xb + 1) + 0.5, np.arange(ya, yb + 1) + 0.5)
        w0 = ((x1 - px) * (y2 - py) - (x2 - px) * (y1 - py)) / area
        w1 = ((x2 - px) * (y0 - py) - (x0 - px) * (y2 - py)) / area
        w2 = 1.0 - w0 - w1
        inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not inside.any():
            return
        # perspective-correct: interpolate over 1/depth
        i0, i1, i2 = w0 / d0, w1 / d1, w2 / d2
        inv = i0 + i1 + i2
        depth = 1.0 / np.where(inv == 0, 1e-9, inv)
        zb = self.depth[ya:yb + 1, xa:xb + 1]
        hit = inside & (depth < zb)
        if not hit.any():
            return
        b0, b1, b2 = i0 * depth, i1 * depth, i2 * depth
        v0, v1, v2 = t[0], t[1], t[2]
        col = np.stack([(b0 * v0[5 + k] + b1 * v1[5 + k] + b2 * v2[5 + k]) / 255.0 for k in range(3)], -1)
        tex = textures.get(t[3])
        if tex is not None:
            th, tw = tex.shape[:2]
            u = (b0 * v0[3] + b1 * v1[3] + b2 * v2[3]) / 32.0 - 0.5
            v = (b0 * v0[4] + b1 * v1[4] + b2 * v2[4]) / 32.0 - 0.5
            ui, vi = np.floor(u).astype(int), np.floor(v).astype(int)
            fu, fv = (u - ui)[..., None], (v - vi)[..., None]
            s = (tex[vi % th, ui % tw] * (1 - fu) * (1 - fv) + tex[vi % th, (ui + 1) % tw] * fu * (1 - fv)
                 + tex[(vi + 1) % th, ui % tw] * (1 - fu) * fv + tex[(vi + 1) % th, (ui + 1) % tw] * fu * fv)
            col = col * s
        self.rgb[ya:yb + 1, xa:xb + 1][hit] = col[hit]
        self.cover[ya:yb + 1, xa:xb + 1][hit] = 1.0
        zb[hit] = depth[hit]

    def image(self):
        a = np.clip(self.cover, 0, 1)[..., None]
        return Image.fromarray((np.concatenate([np.clip(self.rgb, 0, 1), a], -1) * 255 + 0.5).astype(np.uint8), 'RGBA')


def load_textures():
    out = {}
    for sym, f in (('intro_seg7_texture_0', '0.rgba16.png'), ('intro_seg7_texture_1', '1.rgba16.png')):
        out[sym] = np.asarray(Image.open(os.path.join(INTRO, f)).convert('RGB'), np.float32) / 255.0
    return out


def wordmark(path, width):
    """the user's wordmark as (white face, alpha mask) at `width` pixels across"""
    im = Image.open(path).convert('RGB')
    lum = im.convert('L')
    box = lum.point(lambda v: 255 if v > 40 else 0).getbbox()
    lum = lum.crop(box)
    h = round(lum.height * width / lum.width)
    return lum.resize((width, h), Image.LANCZOS)


def build(out_path, wordmark_path, W=1920, H=1080, ss=2, zoom=1.0, word_scale=1.0, word_dy=0.0, word_dx=0.0, depth_px=None,
          show_mario=False):
    tris = triangles(*parse(us_text()))
    groups = letters(tris)
    tex = load_textures()
    # which pieces are which: by where their middle sits in the logo
    info = []
    for g in groups:
        pts = [v for i in g for v in tris[i][:3]]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        info.append({'tris': g, 'cx': (min(xs) + max(xs)) / 2, 'cy': (min(ys) + max(ys)) / 2,
                     'x0': min(xs), 'x1': max(xs), 'y0': min(ys), 'y1': max(ys)})
    ymid = sum(i['cy'] * len(i['tris']) for i in info) / sum(len(i['tris']) for i in info)
    return tris, info, tex, ymid


if __name__ == '__main__':
    tris, info, tex, ymid = build(None, None)
    print(len(tris), 'triangles in', len(info), 'pieces; middle height', round(ymid))
    for i in sorted(info, key=lambda i: (-round(i['cy'] / 150), i['cx'])):
        print('  %4d tris  x %6.0f..%6.0f  y %6.0f..%6.0f' % (len(i['tris']), i['x0'], i['x1'], i['y0'], i['y1']))
