#!/usr/bin/env python3
"""Mario 64's moving textures that are drawn as meshes of their own (game/moving_texture.c gMovtexNonColored):
the castle grounds' waterfall, Tall Tall Mountain's waterfalls, the lava of Lethal Lava Land and of Bowser in the
Fire Sea, the sand and quicksand of Shifting Sand Land, the water of the Cavern of the Metal Cap. The level
geometry the mod draws leaves them out, as the game draws them separately.

Writes data/movtex.lua: by scene, a list of { verts (scene space, flat x,y,z), uv (texture tiles, flat u,v),
tris (0-based), speed (tiles a frame the texture slides along u), color {r,g,b,a}, texture }, and copies the
textures they use (movtex_<name>.png) from the player's own copy.

Usage: python movtexx.py   (SM64_DECOMP and SM64_OUT as for build_all.py)"""
import os, re, sys, glob, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sm64x as X
import warpx as W
from sm64x import SCALE

OUT = os.environ.get('SM64_OUT', 'out')
DATA = os.path.join(OUT, 'Scripts', 'data')
TEXD = os.path.join(OUT, 'textures')
D = X.D

TEXTURE_IDS = ['texture_waterbox_water', 'texture_waterbox_mist', 'texture_waterbox_jrb_water',
               'texture_waterbox_unknown_water', 'texture_waterbox_lava', 'ssl_quicksand', 'ssl_pyramid_sand',
               'ttc_yellow_triangle']
TEXTURE_ENUM = {'TEXTURE_WATER': 0, 'TEXTURE_MIST': 1, 'TEXTURE_JRB_WATER': 2, 'TEXTURE_UNK_WATER': 3,
                'TEXTURE_LAVA': 4, 'TEX_QUICKSAND_SSL': 5, 'TEX_PYRAMID_SAND_SSL': 6, 'TEX_YELLOW_TRI_TTC': 7}
H = r'(0x[0-9a-fA-F]+|\d+)'
ENTRY = re.compile(r'\{\s*(MOVTEX_\w+)\s*,\s*(\w+)\s*,\s*(\d+)\s*,\s*(\w+)\s*,\s*(\w+)\s*,\s*(\w+)\s*,\s*(\w+)\s*,\s*' +
                   H + r'\s*,\s*' + H + r'\s*,\s*' + H + r'\s*,\s*' + H + r'\s*,\s*(LAYER_\w+)\s*\}')


def ue(x, y, z):
    return [-z * SCALE, x * SCALE, y * SCALE]


def num(s):
    return int(s, 0)


def find_array(sym):
    """(path, body) of the C array `sym` in the levels or bin sources"""
    pat = re.compile(r'\b' + re.escape(sym) + r'\s*\[\s*\]\s*=\s*\{(.*?)\n\};', re.S)
    for path in glob.glob(os.path.join(D, 'levels', '**', '*.c'), recursive=True) + glob.glob(os.path.join(D, 'bin', '*.c')):
        with open(path, encoding='utf-8', errors='replace') as f:
            src = f.read()
        if sym not in src:
            continue
        m = pat.search(src)
        if m:
            return path, m.group(1)
    return None, None


def texture_png(sym):
    path, body = find_array(sym)
    if not body:
        return None
    m = re.search(r'#include\s+"([^"]+)\.inc\.c"', body)
    if not m:
        return None
    png = os.path.join(D, m.group(1) + '.png')
    if not os.path.exists(png):
        base, ext = m.group(1).split('.', 1)
        alt = os.path.join(D, base + '_us.' + ext + '.png')
        png = alt if os.path.exists(alt) else None
    return png


def scene_of(path):
    rel = os.path.relpath(path, os.path.join(D, 'levels')).replace('\\', '/').split('/')
    folder = rel[0]
    area = int(rel[2]) if len(rel) > 2 and rel[1] == 'areas' and rel[2].isdigit() else 1
    return W.scene_name(folder, area)


# which draw call each list of moving textures belongs to (moving_texture.c)
DRAWN_BY = {'gMovtexNonColored': ('geo_movtex_draw_nocolor',),
            'gMovtexColored': ('geo_movtex_draw_colored', 'geo_movtex_draw_colored_no_update'),
            'gMovtexColored2': ('geo_movtex_draw_colored_2_no_update',)}


def movtex_ids():
    """MOVTEX_... name -> its number (moving_texture.h: (n | MOVTEX_AREA_X))"""
    with open(os.path.join(D, 'src', 'game', 'moving_texture.h'), encoding='utf-8') as f:
        h = f.read()
    area = {k: int(v, 0) << 8 for k, v in re.findall(r'#define\s+(MOVTEX_AREA_\w+)\s+\((0x[0-9a-fA-F]+|\d+)\s*<<\s*8\)', h)}
    ids = {}
    for k, n, a in re.findall(r'#define\s+(\w+)\s+\(\s*(0x[0-9a-fA-F]+|\d+)\s*\|\s*(MOVTEX_AREA_\w+)\s*\)', h):
        ids[k] = int(n, 0) | area[a]
    return ids


def drawn_in():
    """(draw function, number) -> the scene whose geometry calls it"""
    out = {}
    for path in glob.glob(os.path.join(D, 'levels', '*', 'areas', '*', 'geo.inc.c')):
        with open(path, encoding='utf-8', errors='replace') as f:
            t = f.read()
        for n, fn in re.findall(r'GEO_ASM\(\s*(0x[0-9a-fA-F]+|\d+)\s*,\s*(geo_movtex_draw_\w+)\s*\)', t):
            out[(fn, int(n, 0))] = scene_of(path)
    return out


def object_instances():
    """(draw function, number) -> [(scene, x, y, z, yaw degrees)]: moving textures drawn by an object's model rather than
    by the level (SSL's quicksand pits: special objects special_level_geo_03/04 placed in the area's collision data,
    their models' geo calling geo_movtex_draw_colored_2_no_update) - one copy at each place the game puts one"""
    with open(os.path.join(D, 'include', 'special_presets.inc.c'), encoding='utf-8', errors='replace') as f:
        preset_model = dict(re.findall(r'\{\s*(special_\w+)\s*,\s*\w+\s*,\s*\w+\s*,\s*(MODEL_\w+)', f.read()))
    out = {}
    for lvl_dir in glob.glob(os.path.join(D, 'levels', '*')):
        script = os.path.join(lvl_dir, 'script.c')
        if not os.path.exists(script):
            continue
        with open(script, encoding='utf-8', errors='replace') as f:
            model_geo = {m: g for m, g in re.findall(r'LOAD_MODEL_FROM_GEO\(\s*(MODEL_\w+)\s*,\s*(\w+)\s*\)', f.read())}
        geo_calls = {}
        for gpath in glob.glob(os.path.join(lvl_dir, '**', 'geo.inc.c'), recursive=True):
            with open(gpath, encoding='utf-8', errors='replace') as f:
                t = f.read()
            for sym, body in re.findall(r'const GeoLayout (\w+)\[\]\s*=\s*\{(.*?)\n\};', t, re.S):
                calls = [(fn, int(n, 0)) for n, fn in re.findall(r'GEO_ASM\(\s*(0x[0-9a-fA-F]+|\d+)\s*,\s*(geo_movtex_draw_\w+)\s*\)', body)]
                if calls:
                    geo_calls[sym] = calls
        for cpath in glob.glob(os.path.join(lvl_dir, 'areas', '*', 'collision.inc.c')):
            area = int(os.path.basename(os.path.dirname(cpath)))
            scene = W.scene_name(os.path.basename(lvl_dir), area)
            with open(cpath, encoding='utf-8', errors='replace') as f:
                t = f.read()
            for preset, x, y, z, yaw in re.findall(r'SPECIAL_OBJECT(?:_WITH_YAW)?\(\s*/\*preset\*/\s*(\w+)\s*,\s*/\*pos\*/\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)(?:\s*,\s*/\*yaw\*/\s*(-?\d+))?', t):
                geo = model_geo.get(preset_model.get(preset))
                for key in geo_calls.get(geo, []):
                    out.setdefault(key, []).append((scene, int(x), int(y), int(z), int(yaw or 0) * 360.0 / 256.0))
    return out


def main():
    with open(os.path.join(D, 'src', 'game', 'moving_texture.c'), encoding='utf-8') as f:
        src = f.read()
    out, used = {}, {}
    ids, where, inst = movtex_ids(), drawn_in(), object_instances()
    lists = sorted((src.index(k + '[]'), k) for k in DRAWN_BY if k + '[]' in src)
    for m in ENTRY.finditer(src):
        mid, tex, count, tris_sym, _begin, _end, dl_sym, r, g, b, a, layer = m.groups()
        owner = [k for at, k in lists if at < m.start()]
        fns = DRAWN_BY[owner[-1]] if owner else ()
        tpath, tbody = find_array(tris_sym)
        _, dbody = find_array(dl_sym)
        if not (tbody and dbody):
            print('!! not found:', mid, tris_sym, dl_sym)
            continue
        speed = num(re.search(r'MOV_TEX_SPD\(\s*(-?\d+)\s*\)', tbody).group(1))
        verts, uv, raw = [], [], []
        I = r'\s*(-?\d+)\s*'
        for v in re.finditer(r'MOV_TEX_(TRIS|ROT_TRIS|LIGHT_TRIS)\(' + I + r'(?:,' + I + r')*\)', tbody):
            # (MOV_TEX_TRIS: x, y, z, s, t; the lit ones carry a normal or a light level before s, t)
            vals = [int(q) for q in re.findall(r'-?\d+', v.group(0)[v.group(0).index('(') + 1:])]
            x, y, z, s, t = vals[0], vals[1], vals[2], vals[-2], vals[-1]
            verts += ue(x, y, z)
            raw.append((x, y, z))
            uv += [s, t]
        tris = []
        for t in re.finditer(r'gsSP2Triangles\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*\w+\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)', dbody):
            tris += [int(q) for q in t.groups()]
        for t in re.finditer(r'gsSP1Triangle\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)', dbody):
            tris += [int(q) for q in t.groups()]
        tid = TEXTURE_ENUM.get(tex)
        tsym = TEXTURE_IDS[tid] if tid is not None else None
        tname = 'movtex_' + tsym if tsym else None
        if tsym and tsym not in used:
            used[tsym] = texture_png(tsym)
        # (Mario 64 counts texture steps of 32 texels: in tiles of the picture that is 32 / its size)
        ku, kv = 1.0, 1.0
        if tsym and used.get(tsym):
            from PIL import Image
            w, h = Image.open(used[tsym]).size
            ku, kv = 32.0 / w, 32.0 / h
        uv = [q * (ku if i % 2 == 0 else kv) for i, q in enumerate(uv)]
        speed = speed * ku
        places = next((inst[(fn, ids[mid])] for fn in fns if mid in ids and (fn, ids[mid]) in inst), None)
        if places:
            # (an object's: a copy at each of its places, turned by its yaw)
            import math
            for sc, px, py, pz, yaw in places:
                c, sn = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
                vv = []
                for x, y, z in raw:
                    vv += ue(px + x * c + z * sn, py + y, pz - x * sn + z * c)
                out.setdefault(sc, []).append({
                    'id': '%s@%d,%d,%d' % (mid, px, py, pz), 'verts': vv, 'uv': uv, 'tris': tris, 'speed': speed / 1024.0,
                    'color': [num(r) / 255.0, num(g) / 255.0, num(b) / 255.0, num(a) / 255.0],
                    'texture': tname, 'translucent': layer != 'LAYER_OPAQUE' and num(a) < 255})
                print('  %-36s %-12s at %d,%d,%d  %s' % (mid, sc, px, py, pz, tname))
            continue
        # (the scene whose geometry draws it; else the one whose files hold it)
        scene = next((where[(fn, ids[mid])] for fn in fns if mid in ids and (fn, ids[mid]) in where), None) or scene_of(tpath)
        out.setdefault(scene, []).append({
            'id': mid, 'verts': verts, 'uv': uv, 'tris': tris, 'speed': speed / 1024.0,
            'color': [num(r) / 255.0, num(g) / 255.0, num(b) / 255.0, num(a) / 255.0],
            'texture': tname, 'translucent': layer != 'LAYER_OPAQUE' and num(a) < 255})
        print('  %-36s %-12s %2d verts %2d tris, speed %4d, alpha %3d  %s' % (mid, scene, len(verts) // 3, len(tris) // 3,
                                                                          speed, num(a), tname))
    X.write_lua(os.path.join(DATA, 'movtex.lua'), out,
                header='-- (this file: the moving-texture meshes Mario 64 draws apart from its levels; movtexx.py)\n')
    os.makedirs(TEXD, exist_ok=True)
    for tsym, png in used.items():
        if png:
            shutil.copy(png, os.path.join(TEXD, 'movtex_' + tsym + '.png'))
            print('texture', tsym, '<-', os.path.relpath(png, D))
        else:
            print('!! no picture for', tsym)


if __name__ == '__main__':
    main()
