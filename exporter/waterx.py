"""How Mario 64 draws and treats each water box of an area (game/moving_texture.c geo_movtex_draw_water_regions,
get_quad_collection_from_id; game/surface_collision find_water_level / find_poison_gas_level).

An area's geometry names the quad collections it draws its boxes with (GEO_ASM(param, geo_movtex_draw_water_regions));
each collection gives a box id its texture (water, JRB's water, mist, lava) and alpha; HMC's maze mist is drawn
yellow and SSL's tox box mist red. Boxes numbered 50 and up are never water; of those, 50, 60, ... are poison gas.

looks(level, area) -> {box id: {'tex': 'water'|'jrb'|'mist'|'lava'|'unk', 'alpha': 0..1, 'tint': [r,g,b],
                                'gas': bool, 'swim': bool, 'mist_until': star key or None}}"""
import os, re, glob
import sm64x as X

D = X.D
TEX_NAMES = {'TEXTURE_WATER': 'water', 'TEXTURE_JRB_WATER': 'jrb', 'TEXTURE_MIST': 'mist', 'TEXTURE_LAVA': 'lava',
             'TEXTURE_UNK_WATER': 'unk'}
# the pictures, by the names the game looks them up by (textures/<name>.png)
PICTURES = {'jrb': 'texture_waterbox_jrb_water', 'mist': 'texture_waterbox_mist', 'lava': 'texture_waterbox_lava',
            'unk': 'texture_waterbox_unknown_water', 'water': 'texture_waterbox_water'}
_cache = {}


def _sources():
    if 'src' not in _cache:
        texts = {}
        for p in glob.glob(os.path.join(D, 'levels', '**', '*.c'), recursive=True):
            with open(p, encoding='utf-8', errors='replace') as f:
                texts[p] = f.read()
        with open(os.path.join(D, 'src', 'game', 'moving_texture.c'), encoding='utf-8') as f:
            mt = f.read()
        with open(os.path.join(D, 'src', 'game', 'moving_texture.h'), encoding='utf-8') as f:
            h = f.read()
        sw = mt[mt.index('void *get_quad_collection_from_id'):]
        sw = sw[:sw.index('\n}\n')]
        case = dict(re.findall(r'case\s+(\w+):\s*return\s+(\w+);', sw))
        area = {k: int(v, 0) << 8 for k, v in re.findall(r'#define\s+(MOVTEX_AREA_\w+)\s+\((0x[0-9a-fA-F]+|\d+)\s*<<\s*8\)', h)}
        ids = {k: int(n, 0) | area[a]
               for k, n, a in re.findall(r'#define\s+(\w+)\s+\(\s*(0x[0-9a-fA-F]+|\d+)\s*\|\s*(MOVTEX_AREA_\w+)\s*\)', h)}
        _cache['src'] = (texts, case, {v: k for k, v in ids.items() if k in case})
    return _cache['src']


def _array(texts, sym):
    pat = re.compile(r'\b' + re.escape(sym) + r'\s*\[\s*\]\s*=\s*\{(.*?)\};', re.S)
    for t in texts.values():
        if sym in t:
            m = pat.search(t)
            if m:
                return m.group(1)
    return None


def looks(level, area):
    texts, case, byval = _sources()
    geo = os.path.join(D, 'levels', level, 'areas', str(area), 'geo.inc.c')
    out = {}
    if not os.path.exists(geo):
        return out
    with open(geo, encoding='utf-8', errors='replace') as f:
        g = f.read()
    for n in re.findall(r'GEO_ASM\(\s*(0x[0-9a-fA-F]+|\d+)\s*,\s*geo_movtex_draw_water_regions', g):
        name = byval.get(int(n, 0))
        body = name and _array(texts, case[name])
        if not body:
            continue
        tint = [1.0, 1.0, 0.0] if name == 'HMC_MOVTEX_TOXIC_MAZE_MIST' else (
            [1.0, 0.0, 0.0] if name == 'SSL_MOVTEX_TOXBOX_QUICKSAND_MIST' else [1.0, 1.0, 1.0])
        for bid, dsym in re.findall(r'\{\s*(-?\d+)\s*,\s*(\w+)\s*\}', body):
            bid = int(bid)
            if dsym == 'NULL' or bid in out:
                continue
            d = _array(texts, dsym) or ''
            tm = re.search(r'MOV_TEX_DEFINE\(\s*(\w+)', d)
            am = re.search(r'MOV_TEX_ALPHA\(\s*(\w+)', d)
            out[bid] = {'tex': TEX_NAMES.get(tm.group(1), 'water') if tm else 'water',
                        'alpha': round(int(am.group(1), 0) / 255.0, 3) if am else 0.59, 'tint': tint,
                        # (JRB's mist over the bay is gone once its first star is had: geo_movtex_draw_water_regions)
                        'mist_until': 'jrb:0' if name == 'JRB_MOVTEX_INITIAL_MIST' else None}
    return out


def annotate(level, area, boxes):
    """the scene's water boxes, each with how it looks and what it is"""
    lk = looks(level, area)
    for b in boxes:
        bid = b.get('id', 0)
        info = lk.get(bid, {'tex': 'water', 'alpha': 0.59, 'tint': [1.0, 1.0, 1.0], 'mist_until': None})
        b['tex'], b['alpha'] = info['tex'], info['alpha']
        if info['tint'] != [1.0, 1.0, 1.0]:
            b['tint'] = info['tint']
        if info['mist_until']:
            b['mist_until'] = info['mist_until']
        # (find_water_level: below 50 only; find_poison_gas_level: 50 and up, a multiple of 10)
        b['swim'] = bid < 50 and info['tex'] != 'lava'
        if bid >= 50 and bid % 10 == 0:
            b['gas'] = True
    return boxes


def picture(kind):
    """the decomp's png for a water texture kind"""
    sym = PICTURES.get(kind)
    texts, _, _ = _sources()
    body = sym and _array(texts, sym)
    if body is None:
        for p in glob.glob(os.path.join(D, 'bin', '*.c')):
            with open(p, encoding='utf-8', errors='replace') as f:
                t = f.read()
            m = re.search(r'\b' + re.escape(sym) + r'\s*\[\s*\]\s*=\s*\{(.*?)\};', t, re.S)
            if m:
                body = m.group(1)
                break
    m = body and re.search(r'#include\s+"([^"]+)\.inc\.c"', body)
    if not m:
        return None
    png = os.path.join(D, m.group(1) + '.png')
    if not os.path.exists(png):
        base, ext = m.group(1).split('.', 1)
        alt = os.path.join(D, base + '_us.' + ext + '.png')
        png = alt if os.path.exists(alt) else None
    return png
