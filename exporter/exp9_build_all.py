#!/usr/bin/env python3
"""Build all data for the Storror SM64Map mod from the decomp (+ user's ROM textures)."""
import os, re, sys, math, json, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sm64x as X
import sm64scenes as S
from sm64x import SCALE, to_int, try_int

OUT = os.environ.get('SM64_OUT', '/home/claude/sm64work/out')
DATA = os.path.join(OUT, 'Scripts', 'data')
TEXD = os.path.join(OUT, 'textures')

db = X.DB()
textures = {}

TREE_GEOS = {'special_bubble_tree': 'bubbly_tree_geo', 'special_spiky_tree': 'spiky_tree_geo',
             'special_snow_tree': 'snow_tree_geo', 'special_palm_tree': 'palm_tree_geo'}
DOOR_PRESETS = {
    'special_wooden_door': 'wooden', 'special_wooden_door_warp': 'wooden', 'special_metal_door': 'metal',
    'special_metal_door_warp': 'metal', 'special_castle_door': 'castle', 'special_castle_door_warp': 'castle',
    'special_haunted_door': 'wooden'}
DOOR_GEOS = {'castle': 'castle_door_geo', 'metal': 'metal_door_geo', 'wooden': 'wooden_door_geo',
             'key': 'key_door_geo'}


def ue(x, y, z):
    return [-z * SCALE, x * SCALE, y * SCALE]


def parse_model_geo_map(level):
    m = {}
    for path in (os.path.join(X.D, 'levels', level, 'script.c'), os.path.join(X.D, 'levels', 'scripts.c')):
        t = X.strip_comments(open(path, encoding='utf-8', errors='replace').read())
        for mm in re.finditer(r'LOAD_MODEL_FROM_GEO\s*\(\s*(\w+)\s*,\s*(\w+)\s*\)', t):
            m.setdefault(mm.group(1), mm.group(2))
    return m


def preset_table():
    """macro preset -> (bhv, model) from macro_presets.inc.c"""
    t = X.strip_comments(open(os.path.join(X.D, 'include', 'macro_presets.inc.c'), encoding='utf-8').read())
    names = re.search(r'enum\s+\w*\s*\{(.*?)\}', X.strip_comments(open(os.path.join(X.D, 'include', 'macro_presets.h'), encoding='utf-8').read()), re.S)
    return t, names


def goomba_group(preset):
    if preset == 'macro_goomba_triplet_spawner':
        return 3
    if preset == 'macro_goomba_quintuplet_spawner':
        return 5
    if preset in ('macro_goomba', 'macro_huge_goomba', 'macro_tiny_goomba'):
        return 1
    return 0


def clip_tree_section(sec):
    """Clip a (UV-extrapolated) sprite triangle to the 0..1 texture square so it works with wrapping textures."""
    n = sec['nverts']
    P = [sec['pos'][i * 3:i * 3 + 3] for i in range(n)]
    U = [sec['uv'][i * 2:i * 2 + 2] for i in range(n)]
    poly = [P[i] + U[i] for i in range(n)]  # 5 floats

    def clip(poly, axis, val, keep_ge):
        out = []
        for i in range(len(poly)):
            a, b = poly[i], poly[(i + 1) % len(poly)]
            da = (a[3 + axis] - val) * (1 if keep_ge else -1)
            db_ = (b[3 + axis] - val) * (1 if keep_ge else -1)
            if da >= 0:
                out.append(a)
            if (da >= 0) != (db_ >= 0):
                t = da / (da - db_)
                out.append([a[k] + (b[k] - a[k]) * t for k in range(5)])
        return out
    poly = clip(poly, 0, 0.0, True); poly = clip(poly, 0, 1.0, False)
    poly = clip(poly, 1, 0.0, True); poly = clip(poly, 1, 1.0, False)
    if len(poly) < 3:
        return None
    sec = dict(sec)
    sec['nverts'] = len(poly)
    sec['pos'] = [round(c, 3) for v in poly for c in v[:3]]
    sec['uv'] = [round(c, 4) for v in poly for c in v[3:5]]
    sec['col'] = [1] * (4 * len(poly))
    sec['nrm'] = [-1, 0, 0] * len(poly)
    idx = []
    for i in range(1, len(poly) - 1):
        idx += [0, i, i + 1]
    sec['idx'] = idx
    sec['ntris'] = len(poly) - 2
    return sec


def tile_alpha(sections):
    """Masked/translucent widget materials clamp UVs, so split repeating (wrapped) UVs into unit-UV tiles."""
    out = []
    for sec in sections:
        U = sec['uv']
        if sec.get('layer') != 'alpha' or sec['nverts'] == 0:
            out.append(sec); continue
        us, vs = U[0::2], U[1::2]
        if max(us) - min(us) <= 1.02 and max(vs) - min(vs) <= 1.02 and min(us) > -0.05 and max(us) < 1.05 and min(vs) > -0.05 and max(vs) < 1.05:
            out.append(sec); continue
        P, C, N, idx = sec['pos'], sec['col'], sec['nrm'], sec['idx']
        npos, nuv, ncol, nnrm, nidx = [], [], [], [], []

        def vert(i):  # attrs: pos3, uv2, col4, nrm3
            return P[i * 3:i * 3 + 3] + U[i * 2:i * 2 + 2] + C[i * 4:i * 4 + 4] + N[i * 3:i * 3 + 3]

        def clip(poly, axis, val, keep_ge):
            res = []
            for k in range(len(poly)):
                a, b = poly[k], poly[(k + 1) % len(poly)]
                da = (a[3 + axis] - val) * (1 if keep_ge else -1)
                db_ = (b[3 + axis] - val) * (1 if keep_ge else -1)
                if da >= 0:
                    res.append(a)
                if (da >= 0) != (db_ >= 0):
                    t = da / (da - db_)
                    res.append([a[q] + (b[q] - a[q]) * t for q in range(len(a))])
            return res
        for t in range(0, len(idx), 3):
            tri = [vert(i) for i in idx[t:t + 3]]
            u0 = math.floor(min(v[3] for v in tri) + 1e-4); u1 = math.ceil(max(v[3] for v in tri) - 1e-4)
            v0 = math.floor(min(v[4] for v in tri) + 1e-4); v1 = math.ceil(max(v[4] for v in tri) - 1e-4)
            for iu in range(u0, max(u1, u0 + 1)):
                for iv in range(v0, max(v1, v0 + 1)):
                    poly = clip(tri, 0, iu, True); poly = clip(poly, 0, iu + 1, False)
                    poly = clip(poly, 1, iv, True); poly = clip(poly, 1, iv + 1, False)
                    if len(poly) < 3:
                        continue
                    base = len(npos) // 3
                    for v in poly:
                        npos += [round(x, 3) for x in v[0:3]]
                        nuv += [round(min(max(v[3] - iu, 0.0), 1.0), 4), round(min(max(v[4] - iv, 0.0), 1.0), 4)]
                        ncol += v[5:9]
                        nnrm += v[9:12]
                    for k in range(1, len(poly) - 1):
                        nidx += [base, base + k, base + k + 1]
        sec = dict(sec)
        sec.update(pos=npos, uv=nuv, col=ncol, nrm=nnrm, idx=nidx, nverts=len(npos) // 3, ntris=len(nidx) // 3)
        out.append(sec)
    return out


def two_sided_alpha(sections, eps=0.6):
    """Masked sections render black from behind; add an explicit back-facing copy, nudged slightly backwards."""
    out = []
    for sec in sections:
        out.append(sec)
        if sec.get('layer') != 'alpha':
            continue
        P = sec['pos']; U = sec['uv']; C = sec['col']; idx = sec['idx']
        npos, nuv, ncol, nnrm, nidx = [], [], [], [], []
        for t in range(0, len(idx), 3):
            a, b, c = idx[t:t + 3]
            pa, pb, pc = [P[i * 3:i * 3 + 3] for i in (a, b, c)]
            e1 = [pb[k] - pa[k] for k in range(3)]; e2 = [pc[k] - pa[k] for k in range(3)]
            n = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]]
            l = math.sqrt(sum(x * x for x in n)) or 1.0
            n = [x / l for x in n]
            base = len(npos) // 3
            for i in (a, c, b):  # reversed winding
                npos += [round(P[i * 3 + k] + n[k] * eps, 3) for k in range(3)]
                nuv += U[i * 2:i * 2 + 2]
                ncol += C[i * 4:i * 4 + 4]
                nnrm += [-n[0], -n[1], -n[2]]
            nidx += [base, base + 1, base + 2]
        back = dict(sec)
        back.update(pos=npos, uv=nuv, col=ncol, nrm=nnrm, idx=nidx, nverts=len(npos) // 3, ntris=len(nidx) // 3)
        out.append(back)
    for i, sec in enumerate(out):
        sec['id'] = i
    return out


def lift_decals(sections, eps=1.5):
    """Push decal layers a little off the surface they sit on (kills z-fighting / flicker)."""
    for sec in sections:
        if 'decal' not in sec.get('layer', ''):
            continue
        P = sec['pos']; idx = sec['idx']
        acc = [[0.0, 0.0, 0.0] for _ in range(sec['nverts'])]
        cnt = [0] * sec['nverts']
        for t in range(0, len(idx), 3):
            a, b, c = idx[t:t + 3]
            pa, pb, pc = [P[i * 3:i * 3 + 3] for i in (a, b, c)]
            e1 = [pb[k] - pa[k] for k in range(3)]; e2 = [pc[k] - pa[k] for k in range(3)]
            n = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]]
            l = math.sqrt(sum(x * x for x in n)) or 1.0
            for i in (a, b, c):
                for k in range(3):
                    acc[i][k] += -n[k] / l  # engine-front side is opposite the cross product
                cnt[i] += 1
        for i in range(sec['nverts']):
            l = math.sqrt(sum(x * x for x in acc[i])) or 1.0
            for k in range(3):
                P[i * 3 + k] = round(P[i * 3 + k] + acc[i][k] / l * eps, 3)
    return sections


def trunk_collision(trees, radius=16.0, height=420.0, sides=14):
    """Capped prism standing on each tree base (UE scene coordinates)."""
    pos, idx = [], []
    for (tx, ty, tz) in trees:
        base = len(pos) // 3
        for ring, z in enumerate((tz - 6.0, tz + height)):
            for k in range(sides):
                a = 2 * math.pi * k / sides
                pos += [round(tx + radius * math.cos(a), 2), round(ty + radius * math.sin(a), 2), round(z, 2)]
        for k in range(sides):
            k2 = (k + 1) % sides
            b0, b1, t0, t1 = base + k, base + k2, base + sides + k, base + sides + k2
            idx += [b0, t0, b1, b1, t0, t1]
        # top cap fan
        pos += [round(tx, 2), round(ty, 2), round(tz + height, 2)]
        c = len(pos) // 3 - 1
        for k in range(sides):
            idx += [c, base + sides + k, base + sides + (k + 1) % sides]
    idx = idx + [i for t in range(0, len(idx), 3) for i in (idx[t], idx[t + 2], idx[t + 1])]  # both windings
    return {'source': 'trunks', 'ntris': len(idx) // 3, 'pos': pos, 'idx': idx, 'surfaces': {}, 'water': []}


def export_scene(name, level, area, spawn_sm64, spawn_yaw, extra_tree=True, skip_geo=False):
    blocks = S.area_blocks(level)[area]
    print('== scene', name, level, 'area', area, blocks)
    mesh = S.export_level_base(db, blocks['geo'], textures)
    mgmap = parse_model_geo_map(level)
    specials = S.parse_specials(db, blocks['terrain']) if blocks['terrain'] else []
    objects = []
    tree_templates = {}
    # specials -> baked statics / objects
    for sp in specials:
        pos = (sp['x'], sp['y'], sp['z'])
        pr = sp['preset']
        if pr in TREE_GEOS and db.has('geo', TREE_GEOS[pr]):
            g = TREE_GEOS[pr]
            if g not in tree_templates:
                tm = X.Mesh()
                tm.xf = None; tm.cum = 1.0
                S.walk_static(db, X.parse_geo(db, g)['children'], S.rot_y_xf(0, (0, 0, 0)), tm, textures)
                tree_templates[g] = two_sided_alpha([c for c in (clip_tree_section(q) for q in X.finish_sections(tm)) if c])
            objects.append({'kind': 'tree', 'geo': g, 'pos': ue(*pos)})
        elif pr.startswith('special_level_geo_'):
            model = 'MODEL_LEVEL_GEOMETRY_' + pr.split('_')[-1]
            geo = mgmap.get(model)
            if geo and db.has('geo', geo):
                S.walk_static(db, X.parse_geo(db, geo)['children'], S.rot_y_xf(sp['yaw'] * 360.0 / 256, pos), mesh, textures)
        elif pr in DOOR_PRESETS:
            objects.append({'kind': 'door', 'style': DOOR_PRESETS[pr], 'pos': ue(*pos), 'yaw': -(sp['yaw'] * 360.0 / 256),
                            'warp': pr.endswith('_warp'), 'param': sp['param']})
        elif pr == 'special_bowser':
            objects.append({'kind': 'bowser', 'pos': ue(*pos), 'yaw': -(sp['yaw'] * 360.0 / 256)})
    # level script objects
    for o in S.parse_objects_for_area(level, area) if hasattr(S, 'parse_objects_for_area') else []:
        pass
    for o in X.parse_objects(level):
        if o.get('area') != area or 'bhv' not in o:
            continue
        b = o['bhv']
        pos = (o['x'], o['y'], o['z'])
        if b == 'bhvGoomba':
            objects.append({'kind': 'goomba', 'pos': ue(*pos), 'yaw': -o['ay']})
        elif b in ('bhvDoor', 'bhvStarDoor', 'bhvDoorWarp'):
            style = 'key' if 'KEY_DOOR' in o['model'] else ('star' if 'STAR_DOOR' in o['model'] else 'wooden')
            objects.append({'kind': 'door', 'style': style, 'model': o['model'], 'pos': ue(*pos), 'yaw': -o['ay'],
                            'warp': b == 'bhvDoorWarp', 'bparam': o['bparam']})
        elif b == 'bhvBowser':
            objects.append({'kind': 'bowser', 'pos': ue(*pos), 'yaw': -o['ay']})
    # macro objects
    if blocks['macro']:
        for mo in X.parse_macro_objects(level, area):
            n = goomba_group(mo['preset'])
            if n == 1:
                objects.append({'kind': 'goomba', 'pos': ue(mo['x'], mo['y'], mo['z']), 'yaw': 0,
                                'size': 'huge' if 'huge' in mo['preset'] else ('tiny' if 'tiny' in mo['preset'] else 'normal')})
            elif n > 1:
                for i in range(n):
                    ang = 2 * math.pi * i / n
                    objects.append({'kind': 'goomba', 'pos': ue(mo['x'] + 220 * math.cos(ang), mo['y'], mo['z'] + 220 * math.sin(ang)),
                                    'yaw': 0, 'size': 'normal', 'group': True})
    sections = lift_decals(two_sided_alpha(tile_alpha(X.finish_sections(mesh))))
    paintings = S.export_paintings(db, blocks['geo'], TEXD) if level == 'castle_inside' else []
    coll = X.export_collision(db, blocks['terrain']) if blocks['terrain'] else None
    trees_xyz = [tuple(o['pos']) for o in objects if o.get('kind') == 'tree']
    if coll is not None and trees_xyz:
        r = 16.0 * SCALE / 0.75
        coll_list = [coll, trunk_collision(trees_xyz, radius=r, height=420.0 * SCALE / 0.75)]
    else:
        coll_list = [coll] if coll else []
    scene = {
        'name': name, 'level': level, 'scale': SCALE,
        'spawn': {'pos': ue(*spawn_sm64), 'yaw': -spawn_yaw},
        'sections': sections,
        'collision': coll_list,
        'water': coll['water'] if coll else [],
        'objects': objects,
        'paintings': paintings,
        'tree_templates': tree_templates,
    }
    if coll:
        coll.pop('water', None)
    print('   sections', len(sections), 'tris', sum(s['ntris'] for s in sections), 'collision tris', coll['ntris'] if coll else 0,
          'objects', len(objects), 'specials', len(specials))
    return scene


def export_actors():
    actors = {}
    anim_tables = {n: S.anim_table(db, n) for n in db.src['animptrs']}

    def table_for(prefix):
        for n in anim_tables:
            if n.startswith(prefix):
                return anim_tables[n]
        return []

    print('== actor goomba')
    actors['goomba'] = S.export_actor(db, 'goomba_geo', table_for('goomba_seg8_anims'), textures)
    for sty, geo in DOOR_GEOS.items():
        if db.has('geo', geo):
            print('== actor door', sty)
            actors['door_' + sty] = S.export_actor(db, geo, table_for('door_seg3_anims'), textures)
    print('== actor bowser')
    bt = table_for('bowser_seg6_anims')
    pick = [12, 13, 19, 6, 9, 8, 2, 10]
    actors['bowser'] = S.export_actor(db, 'bowser_geo_no_shadow' if db.has('geo', 'bowser_geo_no_shadow') else 'bowser_geo',
                                      [bt[i] for i in pick if i < len(bt)], textures)
    actors['bowser']['anim_ids'] = [i for i in pick if i < len(bt)]
    return actors


def main():
    only = set(sys.argv[1:])
    os.makedirs(DATA, exist_ok=True)
    scenes = {}
    if not only or 'grounds' in only:
        scenes['grounds'] = export_scene('grounds', 'castle_grounds', 1, (-1328, 260, 4664), 180)
    if not only or 'castle' in only:
        scenes['castle'] = export_scene('castle', 'castle_inside', 1, (-1023, 100, 1152), 180)
    if not only or 'bob' in only:
        scenes['bob'] = export_scene('bob', 'bob', 1, (-6558, 200, 6464), 135)
    if not only or 'bowser' in only:
        scenes['bowser'] = export_scene('bowser', 'bowser_1', 1, (0, 307, 0), 180)
    for k, v in scenes.items():
        X.write_lua(os.path.join(DATA, 'scene_%s.lua' % k), v)
        print('wrote scene', k)
    if not only or 'actors' in only:
        actors = export_actors()
        for k, v in actors.items():
            X.write_lua(os.path.join(DATA, 'actor_%s.lua' % k), v)
            print('wrote actor', k, 'parts', len(v['parts']), 'anims', len(v['anims']))
    n = X.copy_textures(textures, TEXD)
    shutil.copy(os.path.join(X.D, 'textures', 'segment2', 'segment2.11C58.rgba16.png'), os.path.join(TEXD, 'water_surface.png'))
    print('textures copied:', n, 'of', len(textures))


if __name__ == '__main__':
    main()
