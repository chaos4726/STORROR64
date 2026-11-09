#!/usr/bin/env python3
"""Build all data for the Storror SM64Map mod from the decomp (+ user's ROM textures)."""
import os, re, sys, math, json, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sm64x as X
import sm64scenes as S
import warpx as W
import platx as P
import envx as E
import waterx as WX
import enemyx as EN
from sm64x import SCALE, to_int, try_int

OUT = os.environ.get('SM64_OUT', '/home/claude/sm64work/out')
DATA = os.path.join(OUT, 'Scripts', 'data')
TEXD = os.path.join(OUT, 'textures')

db = X.DB()
# textures that differ between regions are stored as <name>_us.<format>.png: use the one that exists
for _sym, _png in list(db.tex.items()):
    if not os.path.exists(os.path.join(X.D, _png)):
        _base, _ext = _png.split('.', 1)
        if os.path.exists(os.path.join(X.D, _base + '_us.' + _ext)):
            db.tex[_sym] = _base + '_us.' + _ext
textures = {}
used_props = set()
BHV_COLLISION = X.behavior_collisions()
# behaviours that have a collision model but are not part of the level's shape (handled elsewhere, or not solid scenery)
NOT_SCENERY = {'bhvDoor', 'bhvStarDoor', 'bhvDoorWarp', 'bhvBowser', 'bhvKoopaShell', 'bhvExclamationBox', 'bhvBreakableBox',
               'bhvHiddenObject', 'bhvCapSwitch', 'bhvPushableMetalBox'}

TREE_GEOS = {'special_bubble_tree': 'bubbly_tree_geo', 'special_spiky_tree': 'spiky_tree_geo',
             'special_snow_tree': 'snow_tree_geo', 'special_palm_tree': 'palm_tree_geo'}
DOOR_PRESETS = {
    'special_wooden_door': 'wooden', 'special_wooden_door_warp': 'wooden', 'special_metal_door': 'metal',
    'special_metal_door_warp': 'metal', 'special_castle_door': 'castle', 'special_castle_door_warp': 'castle',
    'special_haunted_door': 'wooden'}
DOOR_GEOS = {'castle': 'castle_door_geo', 'metal': 'metal_door_geo', 'wooden': 'wooden_door_geo',
             'key': 'key_door_geo'}


# ---- things Mario 64 places in a level besides its geometry
COIN_FORMATIONS = {'macro_coin_line_horizontal': (0, False), 'macro_coin_ring_horizontal': (2, False), 'macro_coin_arrow': (4, False),
                   'macro_coin_line_horizontal_flying': (0, True), 'macro_coin_line_vertical_flying': (1, True),
                   'macro_coin_ring_horizontal_flying': (2, True), 'macro_coin_ring_vertical_flying': (3, True),
                   'macro_coin_arrow_flying': (4, True)}
COIN_ARROW = [(0, -150), (0, -50), (0, 50), (0, 150), (-50, 100), (-100, 50), (50, 100), (100, 50)]
SINGLE_PICKUPS = {'macro_yellow_coin_1': {'kind': 'coin', 'value': 1}, 'macro_yellow_coin_2': {'kind': 'coin', 'value': 1},
                  'macro_red_coin': {'kind': 'coin', 'value': 2, 'red': True},
                  'macro_blue_coin': {'kind': 'coin', 'value': 5, 'blue': True},
                  'macro_1up': {'kind': 'oneup'}, 'macro_1up_2': {'kind': 'oneup'}, 'macro_1up_3': {'kind': 'oneup'},
                  'macro_recovery_heart': {'kind': 'heart'},
                  # (the sliding 1-up chases him down its slide: game.lua; the moving blue coin waits where it is)
                  'macro_1up_sliding': {'kind': 'oneup', 'slide': True}, 'macro_moving_blue_coin': {'kind': 'coin', 'value': 5, 'blue': True, 'slide': True}}
PROP_PRESETS = {'macro_wooden_signpost': 'signpost'}
PROP_GEOS = {'signpost': 'wooden_signpost_geo', 'star': 'star_geo',
             # the cannon in its hole once a Bob-omb Buddy has opened it, and its barrel (cannon.inc.c; platforms.lua B.cannon)
             'cannon_base': 'cannon_base_geo', 'cannon_barrel': 'cannon_barrel_geo', 'heart': 'heart_geo'}
# every kind of door Mario 64 has, by the model it uses; each is exported as actor "door_<style>"
DOOR_STYLE_BY_GEO = {'castle_door_geo': 'castle', 'metal_door_geo': 'metal', 'wooden_door_geo': 'wooden',
                     'wooden_door2_geo': 'wooden', 'key_door_geo': 'key', 'castle_door_0_star_geo': 'star0',
                     'castle_door_1_star_geo': 'star1', 'castle_door_3_stars_geo': 'star3',
                     'hazy_maze_door_geo': 'hmc', 'haunted_door_geo': 'haunted', 'cabin_door_geo': 'cabin'}
DOOR_GEOS.update({'star0': 'castle_door_0_star_geo', 'star1': 'castle_door_1_star_geo', 'star3': 'castle_door_3_stars_geo',
                  'hmc': 'hazy_maze_door_geo', 'haunted': 'haunted_door_geo', 'cabin': 'cabin_door_geo'})
SPECIALS = W.special_presets()
BURNING = ('SURFACE_BURNING',)
DEATH = ('SURFACE_DEATH_PLANE',)
level_props = {}        # prop actor name -> geo, for models that only one level has (star doors and the like)
enemy_geos = {}         # enemy model geo -> its animation table (enemyx.py), exported as actor "geo_<geo>"


def star_id(bparam):
    m = re.search(r'STAR_INDEX_ACT_(\d+)', bparam)
    if m:
        return int(m.group(1)) - 1
    v = try_int(bparam)
    return ((v >> 24) & 0xFF) if v is not None else 0


def coin_formation(mo, shape, flying):
    """The coins of a bhvCoinFormation, placed as coin.inc.c's spawn_coin_in_formation places them."""
    out = []
    yaw = math.radians(mo['yaw'])
    for i in range(8):
        px = py = pz = 0.0
        ground = not flying
        if shape == 0:
            if i > 4: continue
            pz = 160 * (i - 2)
        elif shape == 1:
            if i > 4: continue
            ground = False
            py = 160 * i * 0.8
        elif shape == 2:
            px, pz = math.sin(i * math.pi / 4) * 300, math.cos(i * math.pi / 4) * 300
        elif shape == 3:
            ground = False
            px, py = math.cos(i * math.pi / 4) * 200, math.sin(i * math.pi / 4) * 200 + 200
        else:
            px, pz = COIN_ARROW[i]
        wx = pz * math.sin(yaw) + px * math.cos(yaw)
        wz = pz * math.cos(yaw) - px * math.sin(yaw)
        o = {'kind': 'coin', 'value': 1, 'pos': ue(mo['x'] + wx, mo['y'] + py, mo['z'] + wz)}
        if ground: o['ground'] = True
        out.append(o)
    return out


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


_ball_paths = None


def ball_path(stype):
    """the path a bowling ball of this kind rolls (bowling_ball.inc.c bowling_ball_set_waypoints), as [x, y, z] points"""
    global _ball_paths
    if _ball_paths is None:
        _ball_paths = {}
        def traj(path, name):
            t = open(os.path.join(X.D, path), encoding='utf-8').read()
            m = re.search(re.escape(name) + r'\[\]\s*=\s*\{(.*?)\};', t, re.S)
            return [[int(a), int(b_), int(c)] for a, b_, c in
                    re.findall(r'TRAJECTORY_POS\(\s*\d+\s*,\s*(?:/\*.*?\*/)?\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*\)', m.group(1))] if m else []
        _ball_paths[0] = traj('levels/bob/areas/1/trajectory.inc.c', 'bob_seg7_metal_ball_path0')
        _ball_paths[1] = traj('levels/ttm/areas/1/trajectory.inc.c', 'ttm_seg7_trajectory_070170A0')
        _ball_paths[2] = traj('levels/bob/areas/1/trajectory.inc.c', 'bob_seg7_metal_ball_path1')
        _ball_paths[3] = traj('src/game/behaviors/bowling_ball.inc.c', 'sTHIHugeMetalBallTraj')
        _ball_paths[4] = traj('src/game/behaviors/bowling_ball.inc.c', 'sTHITinyMetalBallTraj')
        _ball_paths['ktq_bob'] = traj('levels/bob/areas/1/trajectory.inc.c', 'bob_seg7_trajectory_koopa')
        _ball_paths['ktq_thi'] = traj('levels/thi/areas/1/trajectory.inc.c', 'thi_seg7_trajectory_koopa')
        _ball_paths['penguin'] = traj('levels/ccm/areas/2/trajectory.inc.c', 'ccm_seg7_trajectory_penguin_race')
        _ball_paths['snowman'] = traj('levels/ccm/areas/1/trajectory.inc.c', 'ccm_seg7_trajectory_snowman')
    return _ball_paths.get(stype) or []


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


def export_scene(name, level, area, spawn_sm64=None, spawn_yaw=0, extra_tree=True, skip_geo=False):
    blocks = S.area_blocks(level)[area]
    print('== scene', name, level, 'area', area, blocks)
    mesh = S.export_level_base(db, blocks['geo'], textures)
    mgmap = parse_model_geo_map(level)
    specials = S.parse_specials(db, blocks['terrain']) if blocks['terrain'] else []
    objects = []
    nodes = []
    tree_templates = {}
    templates = {}          # moving platforms: model + collision in the model's own space
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
        elif pr in DOOR_PRESETS or SPECIALS.get(pr, {}).get('bhv') in ('bhvDoor', 'bhvDoorWarp'):
            spd = SPECIALS.get(pr, {})
            style = DOOR_STYLE_BY_GEO.get(mgmap.get(spd.get('model'))) or DOOR_PRESETS.get(pr, 'wooden')
            warp = spd.get('bhv') == 'bhvDoorWarp' or pr.endswith('_warp')
            d = {'kind': 'door', 'style': style, 'pos': ue(*pos), 'yaw': -(sp['yaw'] * 360.0 / 256),
                 'warp': warp, 'param': sp['param']}
            if warp:
                d['node'] = sp['param'] & 0xFF
                nodes.append({'id': sp['param'] & 0xFF, 'pos': ue(*pos), 'yaw': d['yaw'], 'kind': 'door'})
            elif spd.get('param'):
                d['need'] = spd['param']
            objects.append(d)
        elif pr == 'special_mine':
            # the bombs round Bowser's first arena (his second and third have them as objects)
            objects.append({'kind': 'bowser_bomb', 'pos': ue(*pos)})
        elif pr == 'special_bowser':
            objects.append({'kind': 'bowser', 'pos': ue(*pos), 'yaw': -(sp['yaw'] * 360.0 / 256)})
    # level script objects
    for o in S.parse_objects_for_area(level, area) if hasattr(S, 'parse_objects_for_area') else []:
        pass
    extra_coll = []
    entries = X.parse_objects(level)
    warps, pwarps = W.warp_tables(entries, area)
    for o in entries:
        n0 = len(objects)
        acts = o.get('acts', 0x3F) if isinstance(o, dict) else 0x3F
        try:
            if o.get('area') != area or 'bhv' not in o:
                continue
            b = o['bhv']
            pos = (o['x'], o['y'], o['z'])
            # places the player can arrive at, and the things that send him somewhere when touched
            nkind = W.NODE_BHV.get(b)
            if nkind:
                nid = W.bparam_byte(o['bparam'], 2)
                nodes.append({'id': nid, 'pos': ue(*pos), 'yaw': -o['ay'], 'kind': nkind})
                if nkind == 'trigger':
                    r = W.bparam_byte(o['bparam'], 1)
                    objects.append({'kind': 'warp', 'pos': ue(*pos), 'radius': (10000 if r == 0xFF else (r * 10 or 50)) * SCALE, 'node': nid})
                elif nkind == 'fading':
                    objects.append({'kind': 'fading_warp', 'pos': ue(*pos), 'node': nid})
                elif nkind == 'pipe':
                    objects.append({'kind': 'pipe', 'pos': ue(*pos), 'node': nid})
            loops = {'bhvWaterfallSoundLoop': 'waterfall', 'bhvSandSoundLoop': 'sand', 'bhvVolcanoSoundLoop': 'volcano',
                     'bhvBirdsSoundLoop': 'birds', 'bhvAmbientSounds': 'ambient'}
            if b in loops:
                objects.append({'kind': 'sound_loop', 'sound': loops[b], 'pos': ue(*pos), 'sm64': [o['x'], o['y'], o['z']]})
                continue
            if b == 'bhvBowserBomb':
                objects.append({'kind': 'bowser_bomb', 'pos': ue(*pos)})
                continue
            if b in ('bhvExclamationBox', 'bhvBreakableBox', 'bhvBreakableBoxSmall', 'bhvJumpingBox'):
                objects.append({'kind': 'box', 'type': b, 'pos': ue(*pos), 'sm64': [o['x'], o['y'], o['z']], 'yaw': -o['ay'],
                                'content': (P.bp_value(o.get('bparam', '0')) >> 16) & 0xFF,     # (#defines too: JRB's star box read as a Wing Cap, 2026-10-15)
                                'bp1': (P.bp_value(o.get('bparam', '0')) >> 24) & 0xFF})          # (a star box's star: this | the contents' own)
                continue
            if b in EN.ENEMY_BHVS and (b not in BHV_COLLISION or b == 'bhvSmallWhomp'):     # (a Whomp brings its own)
                eo = EN.enemy_object(db, b, o.get('model'), o['x'], o['y'], o['z'], o['ay'],
                                     P.bp_value(o.get("bparam", "0")), mgmap, ue, enemy_geos)
                if eo and b == 'bhvRacingPenguin':
                    # the Big Penguin Race (racing_penguin.inc.c): down CCM's slide, to the finish line
                    eo['race'] = {'path': ball_path('penguin'), 'flag': [-6500, -5836, -6400], 'star': [-7339, -5700, -6774],
                                  'agility': 11.0, 'id': star_id(o.get('bparam', '0')), 'idle': 3, 'run': 1, 'music': False,
                                  'scale': 4.0}
                if eo and b == 'bhvBigBoulderGenerator':
                    # (the rock it rolls: a model of the level's own)
                    rock = mgmap.get('MODEL_HMC_ROLLING_ROCK')
                    if rock:
                        eo['rock'] = rock
                        enemy_geos.setdefault(rock, None)
                if eo and b == 'bhvSnowmansBottom':
                    eo['path'] = ball_path('snowman')
                if eo and b == 'bhvKoopa' and ((eo['bp'] >> 16) & 0xFF) in (2, 3):
                    # Koopa the Quick: his race (sKoopaTheQuickProperties) and the flag (bhvKoopaRaceEndpoint)
                    thi = ((eo['bp'] >> 16) & 0xFF) == 3
                    eo['race'] = {'path': ball_path('ktq_thi' if thi else 'ktq_bob'),
                                  'flag': [7400, -1537, -6300] if thi else [3304, 4242, -4603],
                                  'star': [7100, -1300, -6000] if thi else [3030, 4500, -4600],
                                  'agility': 6.0 if thi else 4.0, 'id': star_id(o.get('bparam', '0'))}
                if eo:
                    objects.append(eo)
                continue
            # pieces of the level that the game places as objects: plain scenery, and solid things with a
            # collision model of their own (towers, platforms, gates). They are built in where they start.
            plats = P.make(db, level, o, mgmap, textures, templates,
                           lambda secs: lift_decals(two_sided_alpha(tile_alpha(secs))), BHV_COLLISION)
            if plats is not None:
                objects.extend(plats)
                continue
            geo = mgmap.get(o['model'])
            if geo and db.has('geo', geo) and b not in NOT_SCENERY:
                solid = BHV_COLLISION.get(b)
                if (b == 'bhvStaticObject' or solid) and acts != 0x3F:
                    tpl = P.template(db, textures, templates, lambda secs: lift_decals(two_sided_alpha(tile_alpha(secs))), geo, solid)
                    if tpl:
                        objects.append({'kind': 'platform', 'bhv': 'static', 'tpl': tpl, 'pos': [o['x'], o['y'], o['z']],
                                        'ang': [o['ax'], o['ay'], o['az']], 'bp': 0})
                        continue
                if b == 'bhvStaticObject' or solid:
                    S.walk_static(db, X.parse_geo(db, geo)['children'], S.rot_y_xf(o['ay'], pos), mesh, textures)
                    if solid:
                        try:
                            extra_coll.append(X.export_collision(db, solid, offset=pos, yaw=o['ay']))
                        except Exception as e:
                            print('   no collision for', b, solid, e)
                    continue
            if b == 'bhvGoomba':
                # (its size from its parameter, as the triplet spawner's: THI's lone huge one by the start came out a normal
                # goomba, 2026-10-29)
                bps = o.get('bparam', '0')
                g = {'kind': 'goomba', 'pos': ue(*pos), 'yaw': -o['ay']}
                if 'GOOMBA_SIZE_HUGE' in bps or 'GOOMBA_SIZE_TINY' in bps:
                    g['size'] = 'huge' if 'GOOMBA_SIZE_HUGE' in bps else 'tiny'
                objects.append(g)
            elif b in ('bhvDoor', 'bhvDoorWarp'):
                style = DOOR_STYLE_BY_GEO.get(geo) or ('key' if 'KEY_DOOR' in o['model'] else 'wooden')
                d = {'kind': 'door', 'style': style, 'model': o['model'], 'pos': ue(*pos), 'yaw': -o['ay'],
                     'warp': b == 'bhvDoorWarp', 'bparam': o['bparam']}
                b1 = W.bparam_byte(o['bparam'], 1)
                if b == 'bhvDoorWarp':
                    d['node'] = W.bparam_byte(o['bparam'], 2)
                    if b1: d['key'] = b1
                elif b1:
                    d['need'] = b1
                objects.append(d)
            elif b == 'bhvStarDoor':
                # the big star doors slide apart instead of swinging; their model belongs to the castle itself
                if geo and db.has('geo', geo):
                    level_props['stardoor_' + geo] = geo
                    objects.append({'kind': 'stardoor', 'actor': 'stardoor_' + geo, 'pos': ue(*pos), 'yaw': -o['ay'],
                                    'need': W.bparam_byte(o['bparam'], 1)})
            elif b == 'bhvBowser':
                objects.append({'kind': 'bowser', 'pos': ue(*pos), 'yaw': -o['ay']})
            elif b == 'bhvStar':
                objects.append({'kind': 'star', 'pos': ue(*pos), 'id': star_id(o.get('bparam', '0'))})
            elif b in ('bhvBoBBowlingBallSpawner', 'bhvTTMBowlingBallSpawner', 'bhvTHIBowlingBallSpawner'):
                stype = (P.bp_value(o.get('bparam', '0')) >> 16) & 0xFF
                path = ball_path(stype)
                if path:
                    objects.append({'kind': 'enemy', 'type': 'bhvBowlingBallSpawner', 'pos': ue(*pos), 'sm64': [o['x'], o['y'], o['z']],
                                    'yaw': 0, 'geo': 'bowling_ball_geo', 'bp': stype << 16, 'stype': stype, 'path': path,
                                    'period': 64 if b != 'bhvBoBBowlingBallSpawner' else 128, 'thi': b == 'bhvTHIBowlingBallSpawner'})
            elif b == 'bhvGoombaTripletSpawner':
                # (THI's: three goombas in a ring; huge ones by its parameter)
                bps = o.get('bparam', '0')
                size = 'huge' if 'GOOMBA_SIZE_HUGE' in bps else ('tiny' if 'GOOMBA_SIZE_TINY' in bps else 'normal')
                for i in range(3):
                    ang = 2 * math.pi * i / 3
                    objects.append({'kind': 'goomba', 'pos': ue(o['x'] + 300 * math.cos(ang), o['y'], o['z'] + 300 * math.sin(ang)),
                                    'yaw': 0, 'size': size, 'group': True})
            elif b == 'bhvHiddenStar':
                # the star five secrets bring out (hidden_star.inc.c)
                objects.append({'kind': 'secret_star', 'pos': ue(*pos), 'id': star_id(o.get('bparam', '0'))})
            elif b in ('bhvPoleGrabbing', 'bhvGiantPole', 'bhvDDDPole'):
                # poles Mario climbs (pole.inc.c, ddd_pole.inc.c; Scripts/poles.lua): their hitbox's height - a plain
                # one's from its second parameter byte (tenths), WF's giant pole 2100 with a yellow ball on top, DDD's
                # 800 (100 of it below its foot) sliding to and fro along its heading by 100 x its second byte
                bp2 = (P.bp_value(o.get('bparam', '0')) >> 16) & 0xFF
                pole = {'kind': 'pole', 'pos': ue(*pos), 'sm64': [o['x'], o['y'], o['z']], 'yaw': o['ay'],
                        'height': {'bhvGiantPole': 2100, 'bhvDDDPole': 800}.get(b, bp2 * 10), 'type': b}
                if b == 'bhvGiantPole':
                    pole['model'], pole['ball'] = 'geo_wf_geo_000AE0', 'geo_yellow_sphere_geo'
                elif b == 'bhvDDDPole':
                    pole['model'], pole['down'], pole['travel'] = 'geo_ddd_geo_000450', 100, 100 * bp2
                objects.append(pole)
            elif b == 'bhvPlaysMusicTrackWhenTouched':
                # music_touch.inc.c: the puzzle jingle the first time he comes within 200 (CCM's hidden spot)
                objects.append({'kind': 'jingle', 'pos': ue(*pos)})
            elif b == 'bhvHoot':
                # Hoot, WF's owl (hoot.inc.c): asleep in his tree, he carries the athlete about (Scripts/hoot.lua)
                objects.append({'kind': 'hoot', 'pos': ue(*pos), 'sm64': [o['x'], o['y'], o['z']]})
            elif b == 'bhvHiddenRedCoinStar':
                objects.append({'kind': 'red_coin_star', 'pos': ue(*pos), 'id': star_id(o.get('bparam', '0'))})
            elif b == 'bhvCCMTouchedStarSpawn':
                # Cool, Cool Mountain's slide star (spawn_star_exit.inc.c): once he has been down the slide (area 2),
                # coming back out by the cabin brings it out of (2780, y+100, 4666) over to (2500, -4350, 5750)
                objects.append({'kind': 'slide_star', 'pos': ue(2780, o['y'] + 100, 4666), 'to': ue(2500, -4350, 5750),
                                'id': star_id(o.get('bparam', '0'))})
            elif b in ('bhvManyBlueFishSpawner', 'bhvFewBlueFishSpawner', 'bhvChirpChirp') and level != 'castle_grounds':
                # (the castle grounds' lake fish are groundsx.py's)
                # schools of blue fish (fish.inc.c): many 20, few 5; the Chirp Chirps circling
                n = 20 if b == 'bhvManyBlueFishSpawner' else (5 if b == 'bhvFewBlueFishSpawner' else 8)
                objects.append({'kind': 'fish_school', 'pos': ue(*pos), 'count': n})
            elif b == 'bhvTankFishGroup':
                # the castle aquarium's fish (blue_fish.inc.c bhv_tank_fish_group_loop): fifteen spawned (0x300, 0, -200)
                # from the group in its own frame, each moved up to 200 about it
                ya = math.radians(o['ay'])
                rx, rz = 300.0, -200.0
                cx, cz = o['x'] + rx * math.cos(ya) + rz * math.sin(ya), o['z'] - rx * math.sin(ya) + rz * math.cos(ya)
                objects.append({'kind': 'tank_fish', 'pos': ue(cx, o['y'], cz), 'count': 15})
            elif b == 'bhvFishSpawner':
                # the Secret Aquarium's two schools (fish.inc.c bhv_fish_spawner_loop: FISH_SPAWNER_BP_MANY_BLUE 0,
                # FEW_BLUE 1, MANY_CYAN 2, FEW_CYAN 3 - many 20, few 5; drawn as the blue fish, 2026-10-15: it had none)
                bp2 = W.bparam_byte(o.get('bparam', '0'), 2)
                objects.append({'kind': 'fish_school', 'pos': ue(*pos), 'count': 5 if bp2 in (1, 3) else 20})
            elif b == 'bhvBowserCourseRedCoinStar':
                # (a star that does not take him out of the course)
                objects.append({'kind': 'red_coin_star', 'pos': ue(*pos), 'id': star_id(o.get('bparam', '0')), 'noexit': True})
            elif b in ('bhvYellowCoin', 'bhvOneCoin'):
                objects.append({'kind': 'coin', 'value': 1, 'pos': ue(*pos)})
            elif b == 'bhvRedCoin':
                objects.append({'kind': 'coin', 'value': 2, 'red': True, 'pos': ue(*pos)})
            elif b in ('bhv1Up', 'bhv1UpWalking', 'bhv1UpRunningAway'):
                objects.append({'kind': 'oneup', 'pos': ue(*pos)})
            elif b == 'bhvRecoveryHeart':
                objects.append({'kind': 'heart', 'pos': ue(*pos)})
            elif b in ('bhvBobombBuddy', 'bhvBobombBuddyOpensCannon'):
                # (one per spot: the level has a buddy per act at the same place)
                if not any(q.get('kind') == 'bobomb_buddy' and q.get('sm64') == [o['x'], o['y'], o['z']] for q in objects):
                    objects.append({'kind': 'bobomb_buddy', 'pos': ue(*pos), 'sm64': [o['x'], o['y'], o['z']], 'yaw': -o['ay'],
                                    'opens': b == 'bhvBobombBuddyOpensCannon'})
            elif b == 'bhvKingBobomb':
                objects.append({'kind': 'king_bobomb', 'pos': ue(*pos), 'sm64': [o['x'], o['y'], o['z']], 'yaw': -o['ay'],
                                'star': star_id(o.get('bparam', '0'))})
            elif b == 'bhvMessagePanel':
                objects.append({'kind': 'prop', 'actor': 'signpost', 'pos': ue(*pos), 'yaw': -o['ay']})
                used_props.add('signpost')
        finally:
            if acts != 0x3F:
                for ob in objects[n0:]:
                    ob['acts'] = acts

    # macro objects
    if blocks['macro']:
        for mo in X.parse_macro_objects(level, area):
            pr = mo['preset']
            if pr in COIN_FORMATIONS:
                objects.extend(coin_formation(mo, *COIN_FORMATIONS[pr]))
            elif pr in SINGLE_PICKUPS:
                po = dict(SINGLE_PICKUPS[pr], pos=ue(mo['x'], mo['y'], mo['z']))
                if po.get('slide'):
                    po['yaw'] = mo['yaw']
                objects.append(po)
            elif pr in PROP_PRESETS:
                objects.append({'kind': 'prop', 'actor': PROP_PRESETS[pr], 'pos': ue(mo['x'], mo['y'], mo['z']), 'yaw': -mo['yaw']})
                used_props.add(PROP_PRESETS[pr])
            mp = EN.macro_presets().get(pr)
            if mp and mp[0] in ('bhvExclamationBox', 'bhvBreakableBox', 'bhvBreakableBoxSmall', 'bhvJumpingBox'):
                objects.append({'kind': 'box', 'type': mp[0], 'pos': ue(mo['x'], mo['y'], mo['z']), 'sm64': [mo['x'], mo['y'], mo['z']],
                                'yaw': -mo['yaw'], 'content': P.bp_value(mp[2]) if mp[2] not in ('', '0') else 0, 'preset': pr})
            if mp and mp[0] in EN.ENEMY_BHVS and mp[0] not in BHV_COLLISION:
                # (as Mario 64 makes behaviour parameters of a macro's: the preset's own, else the macro's low byte,
                # as the second byte; the macro's high byte as the third)
                mparam = P.bp_value(mo.get('bparam', '0')) if mo.get('bparam', '0') not in ('0', '') else 0
                pparam = P.bp_value(mp[2]) if mp[2] not in ('', '0') else 0
                if pparam:
                    mparam = (mparam & 0xFF00) + (pparam & 0xFF)
                bp = ((mparam & 0xFF) << 16) + (mparam & 0xFF00)
                eo = EN.enemy_object(db, mp[0], mp[1], mo['x'], mo['y'], mo['z'], mo['yaw'], bp, mgmap, ue, enemy_geos)
                if eo:
                    eo['preset'] = pr
                    objects.append(eo)
            if pr == 'macro_bobomb_buddy_opens_cannon_1':
                # the pink bob-omb by a closed cannon (opening it is not built)
                objects.append({'kind': 'bobomb_buddy', 'pos': ue(mo['x'], mo['y'], mo['z']), 'sm64': [mo['x'], mo['y'], mo['z']],
                                'yaw': -mo['yaw'], 'opens': True})
            if pr.startswith('macro_fish_spawner_'):
                objects.append({'kind': 'fish_school', 'pos': ue(mo['x'], mo['y'], mo['z']), 'count': 20 if 'many' in pr else 5})
            if pr == 'macro_seaweed_bundle':
                # (seaweed.inc.c: four seaweeds, each turned and sized its own way)
                for rot, sc3 in (((5500, 14523, 9600), (1.0, 1.0, 1.0)), ((6102, 41800, 0), (0.8, 0.9, 0.8)),
                                 ((8700, 40500, 4100), (0.8, 0.8, 0.8)), ((9500, 57236, 0), (1.2, 1.2, 1.2))):
                    eo = EN.enemy_object(db, 'bhvSeaweed', 'MODEL_SEAWEED', mo['x'], mo['y'], mo['z'], 0, 0, mgmap, ue, enemy_geos)
                    if eo:
                        eo['rot'], eo['sc3'] = list(rot), list(sc3)
                        objects.append(eo)
            if pr == 'macro_koopa_shell_underwater':
                # the Koopa shell lying under water (koopa_shell_underwater.inc.c): grabbed while swimming, a fast swim
                objects.append({'kind': 'water_shell', 'pos': ue(mo['x'], mo['y'], mo['z'])})
            if pr == 'macro_hidden_blue_coin':
                objects.append({'kind': 'coin', 'value': 5, 'blue': True, 'lurk': 'blue', 'pos': ue(mo['x'], mo['y'], mo['z'])})
            elif pr == 'macro_hidden_1up':
                need = (P.bp_value(mo.get('bparam', '0')) if mo.get('bparam', '0') not in ('', '0') else 0) & 0xFF
                objects.append({'kind': 'oneup', 'lurk': 'oneup', 'need': need, 'pos': ue(mo['x'], mo['y'], mo['z'])})
            elif pr == 'macro_hidden_1up_in_pole':
                # mushroom_1up.inc.c: a 1-up hidden at the top of a pole, out once both its marks on the pole (there and
                # 200 below) are passed - climbing it (Scripts/poles.lua)
                objects.append({'kind': 'oneup', 'lurk': 'oneup', 'need': 2, 'pos': ue(mo['x'], mo['y'] + 50, mo['z'])})
                for dy in (0, -200):
                    objects.append({'kind': 'secret_trigger', 'what': 'oneup', 'pos': ue(mo['x'], mo['y'] + dy, mo['z'])})
            elif pr in ('macro_hidden_1up_trigger', 'macro_hidden_star_trigger'):
                objects.append({'kind': 'secret_trigger', 'what': 'oneup' if '1up' in pr else 'star', 'pos': ue(mo['x'], mo['y'], mo['z'])})
            if mp and mp[0] in P.MACRO_PLATFORMS:
                # moving pieces placed by macro (Tick Tock Clock's machinery). Mario 64 turns the macro's parameter
                # into behaviour parameters: the preset's own (if any) or the macro's low byte as the second byte,
                # its high byte as the third
                mparam = P.bp_value(mo.get('bparam', '0')) if mo.get('bparam', '0') not in ('', '0') else 0
                pparam = P.bp_value(mp[2]) if mp[2] not in ('', '0') else 0
                if pparam:
                    mparam = (mparam & 0xFF00) + (pparam & 0xFF)
                bp = ((mparam & 0xFF) << 16) + (mparam & 0xFF00)
                po = {'bhv': mp[0], 'model': mp[1], 'x': mo['x'], 'y': mo['y'], 'z': mo['z'], 'ax': 0, 'ay': mo['yaw'], 'az': 0,
                      'bparam': str(bp)}
                plats = P.make(db, level, po, mgmap, textures, templates,
                               lambda secs: lift_decals(two_sided_alpha(tile_alpha(secs))), BHV_COLLISION)
                if plats:
                    objects.extend(plats)
            if pr in ('macro_bobomb', 'macro_bobomb_stationary'):
                objects.append({'kind': 'bobomb', 'pos': ue(mo['x'], mo['y'], mo['z']), 'sm64': [mo['x'], mo['y'], mo['z']],
                                'yaw': -mo['yaw'], 'stationary': pr == 'macro_bobomb_stationary'})
            if pr == 'macro_chain_chomp':
                # the chain chomp: it brings its wooden post (a platform template: the post sinks when pounded)
                # and its chain (actors chain_chomp and chain_ball); the game drops both to the floor
                post = P.template(db, textures, templates, lambda secs: lift_decals(two_sided_alpha(tile_alpha(secs))),
                                  'wooden_post_geo', 'poundable_pole_collision_06002490')
                objects.append({'kind': 'chain_chomp', 'pos': ue(mo['x'], mo['y'], mo['z']), 'sm64': [mo['x'], mo['y'], mo['z']],
                                'yaw': -mo['yaw'], 'post_tpl': post})
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
    paintings = S.export_paintings(db, blocks['geo'], TEXD, {p['id']: p for p in pwarps}) if level == 'castle_inside' else []
    # (the walls only a Vanish Cap lets him through - VCUTM, WDW's town, SL's igloo, DDD's cages, BBH: apart, so the
    # game can let him through them while he wears it)
    VANISH = ('SURFACE_VANISH_CAP_WALLS',)
    coll = X.export_collision(db, blocks['terrain'], skip=VANISH) if blocks['terrain'] else None
    vanish = X.export_collision(db, blocks['terrain'], only=VANISH) if blocks['terrain'] else None
    if vanish:
        vanish.pop('water', None)
        if not vanish['idx']:
            vanish = None
    floors = W.rule_floors(db, blocks['terrain']) if blocks['terrain'] else []
    # where a fresh start puts the player: the level's own way in (warp node 0x0A), else what was asked for
    if spawn_sm64 is None:
        # (not a spot that sends him somewhere else the moment he stands on it)
        standable = [n for n in nodes if n['kind'] in ('air', 'ground', 'fly')]
        entry = next((n for n in standable if n['id'] == 0x0A), None) or (standable[0] if standable else None)
        mp = W.mario_pos(level)
        if entry:
            spawn = {'pos': entry['pos'], 'yaw': entry['yaw'], 'snap': True}
        elif mp and mp[0] == area:
            spawn = {'pos': ue(*mp[2]), 'yaw': -mp[1], 'snap': True}
        else:
            spawn = {'pos': [0, 0, 0], 'yaw': 0, 'snap': True}
    else:
        spawn = {'pos': ue(*spawn_sm64), 'yaw': -spawn_yaw}
    trees_xyz = [tuple(o['pos']) for o in objects if o.get('kind') == 'tree']
    if coll is not None and trees_xyz:
        r = 16.0 * SCALE / 0.75
        coll_list = [coll, trunk_collision(trees_xyz, radius=r, height=420.0 * SCALE / 0.75)]
    else:
        coll_list = [coll] if coll else []
    for c in extra_coll:
        c.pop('water', None)
        coll_list.append(c)
    scene = {
        'name': name, 'level': level, 'area': area, 'scale': SCALE,
        'spawn': spawn,
        'sections': sections,
        'collision': coll_list,
        'vanish_walls': vanish,
        'water': water_boxes(level, area, coll['water'] if coll else []),
        'objects': objects,
        'paintings': paintings,
        'tree_templates': tree_templates,
        'templates': templates,
        'sky': E.area_sky(db, blocks['geo']),
        'music': E.area_music(level, area),
        'warps': warps,
        'nodes': nodes,
        'floors': floors,
        'pwarps': pwarps,
        'instant': W.instant_warps(level, area),
        'whirlpools': whirlpools(level, area),
    }
    if level == 'castle_inside' and area == 3:
        # the DDD painting's floor (ddd_warp.inc.c bhv_ddd_warp_loop): an object's collision, not the level's - its
        # three painting strips just behind the painting and floor round them, and the same 2073.6 further back once
        # "Board Bowser's Sub" is won. (Never exported: the DDD painting could not be entered, 2026-10-15.)
        dw = {}
        for key, sym in (('front', 'inside_castle_seg7_collision_ddd_warp'), ('back', 'inside_castle_seg7_collision_ddd_warp_2')):
            c = X.export_collision(db, sym)
            c.pop('water', None)
            dw[key] = {'collision': c, 'floors': W.rule_floors(db, sym)}
        scene['ddd_warp'] = dw
    if coll:
        coll.pop('water', None)
    print('   sections', len(sections), 'tris', sum(s['ntris'] for s in sections), 'collision tris', coll['ntris'] if coll else 0,
          'objects', len(objects), 'specials', len(specials))
    return scene


def whirlpools(level, area):
    """the area's WHIRLPOOL commands (level script): Mario 64 units, strength (+ pulls in, - pushes off: a jet
    stream), and when it is there (0 always, 1 before Bowser 2 is beaten, 2 after, 3 from act 2)"""
    path = os.path.join(X.D, 'levels', level, 'script.c')
    if not os.path.exists(path):
        return []
    t = X.strip_comments(open(path, encoding='utf-8', errors='replace').read())
    out = []
    for m in re.finditer(r'AREA\(\s*(\d+)\s*,.*?END_AREA\(\)', t, re.S):
        if int(m.group(1)) != area:
            continue
        for w in re.finditer(r'WHIRLPOOL\(\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*\)', m.group(0)):
            i, cond, x, y, z, st = (int(v) for v in w.groups())
            out.append({'pos': [x, y, z], 'strength': st, 'cond': cond})
    return out


def water_boxes(level, area, boxes):
    """the area's water boxes, each with how Mario 64 draws it and whether it is water or gas; their pictures
    copied as textures/movtex_<name>.png"""
    WX.annotate(level, area, boxes)
    os.makedirs(TEXD, exist_ok=True)
    for b in boxes:
        png = WX.picture(b['tex'])
        dst = os.path.join(TEXD, 'movtex_' + WX.PICTURES[b['tex']] + '.png')
        if png and not os.path.exists(dst):
            shutil.copy(png, dst)
    return boxes


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
    print('== actor bob-ombs')
    actors['bobomb'] = S.export_actor(db, 'black_bobomb_geo', table_for('bobomb_seg8_anims'), textures)
    actors['bobomb_buddy'] = S.export_actor(db, 'bobomb_buddy_geo', table_for('bobomb_seg8_anims'), textures)
    actors['king_bobomb'] = S.export_actor(db, 'king_bobomb_geo', table_for('king_bobomb_seg5_anims'), textures)
    # the explosion: seven pictures, shown in turn on a quad (its geo switches between them)
    for i in range(7):
        src = os.path.join(X.D, 'actors', 'explosion', 'explosion_%d.rgba16.png' % i)
        if os.path.exists(src):
            os.makedirs(TEXD, exist_ok=True)
            shutil.copy(src, os.path.join(TEXD, 'actors__explosion__explosion_%d.rgba16.png' % i))
    print('== actor bowser bomb')
    actors['bowser_bomb'] = S.export_actor(db, 'bowser_bomb_geo', [], textures)
    print('== actor boxes')
    for i in range(4):          # the ! box's four colours: red (wing cap), green (metal), blue (vanish), yellow
        actors['exbox_%d' % i] = S.export_actor(db, 'exclamation_box_geo', [], textures, switch=i)
    # (its geo's switch, oAnimState: 1 the cork box's plain cork - breakable_box_init sets it - and 0 the crazy box's face;
    # the cork boxes all wore the face - "also this random box here?", 2026-10-28)
    actors['cork_box'] = S.export_actor(db, 'breakable_box_geo', [], textures, switch=1)
    actors['crazy_box'] = S.export_actor(db, 'breakable_box_geo', [], textures, switch=0)
    print('== actor chain chomp')
    actors['chain_chomp'] = S.export_actor(db, 'chain_chomp_geo', table_for('chain_chomp_seg6_anims'), textures)
    actors['chain_ball'] = S.export_actor(db, 'metallic_ball_geo', [], textures)
    for geo, anim_sym in EN.EXTRA_MODELS.items():
        if enemy_geos.get(geo) is None:
            enemy_geos[geo] = anim_sym
    for geo, anim_sym in sorted(enemy_geos.items()):
        if db.has('geo', geo):
            print('== enemy model', geo, anim_sym)
            try:
                actors['geo_' + geo] = S.export_actor(db, geo, anim_tables.get(anim_sym, []) if anim_sym else [], textures)
            except Exception as e:
                print('   !! enemy model failed', geo, e)
    print('== actor bowser')
    bt = table_for('bowser_seg6_anims')
    pick = list(range(27))      # (all of them, in Mario 64's order: bowser_fight.lua uses its numbers)
    actors['bowser'] = S.export_actor(db, 'bowser_geo_no_shadow' if db.has('geo', 'bowser_geo_no_shadow') else 'bowser_geo',
                                      [bt[i] for i in pick if i < len(bt)], textures)
    actors['bowser']['anim_ids'] = [i for i in pick if i < len(bt)]
    for name, geo in list(PROP_GEOS.items()) + list(level_props.items()):
        if db.has('geo', geo):
            print('== prop', name)
            actors[name] = S.export_actor(db, geo, [], textures)
    return actors


# scenes whose start point was chosen by hand; every other scene starts at its level's own way in
FIXED_START = {'grounds': ((-1328, 260, 4664), 180), 'castle': ((-1023, 100, 1152), 180),
               'bob': ((-6558, 200, 6464), 135), 'bowser': ((0, 307, 0), 180)}
SKIP_LEVELS = ('ending',)


def all_scenes():
    """(scene name, level folder, area) for every area of every level of the game"""
    out = []
    for const, folder in W.LEVELS.items():
        if folder in SKIP_LEVELS or not os.path.exists(os.path.join(X.D, 'levels', folder, 'script.c')):
            continue
        try:
            areas = S.area_blocks(folder)
        except Exception as e:
            print('!! no areas for', folder, e)
            continue
        for area in sorted(areas):
            out.append((W.scene_name(folder, area), folder, area))
    return out


def main():
    only = set(sys.argv[1:])
    os.makedirs(DATA, exist_ok=True)
    index, failed = [], []
    for name, level, area in all_scenes():
        index.append({'name': name, 'level': level, 'area': area})
        if only and name not in only and level not in only:
            continue
        try:
            fixed = FIXED_START.get(name)
            scene = export_scene(name, level, area, *fixed) if fixed else export_scene(name, level, area)
        except Exception as e:
            import traceback
            traceback.print_exc()
            failed.append((name, str(e)))
            continue
        X.write_lua(os.path.join(DATA, 'scene_%s.lua' % name), scene)
        print('wrote scene', name)
    X.write_lua(os.path.join(DATA, 'scenes.lua'), index)
    os.makedirs(TEXD, exist_ok=True)
    E.write_colors(TEXD)
    rom = os.environ.get('SM64_ROM')
    if rom and os.path.exists(rom):
        print('skies from the ROM:', E.extract_skies(rom, TEXD))
    if failed:
        print('!! FAILED scenes:', failed)
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
