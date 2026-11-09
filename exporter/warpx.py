"""Mario 64's warps, read from the level scripts: which scene every door, painting, pipe and exit leads
to and the exact spot the player arrives at. Also the parts of a level's collision that are not walls
and floors but rules: lava and the planes that mean falling out of the level."""
import os, re, math
import sm64x as X
from sm64x import SCALE, to_int, try_int


def levels():
    """LEVEL_XXX -> level folder, from levels/level_defines.h"""
    t = open(os.path.join(X.D, 'levels', 'level_defines.h'), encoding='utf-8', errors='replace').read()
    return {m.group(1): m.group(2) for m in
            re.finditer(r'DEFINE_LEVEL\(\s*"[^"]*"\s*,\s*(\w+)\s*,\s*\w+\s*,\s*(\w+)', t)}


LEVELS = levels()
SCENE_NAMES = {('castle_grounds', 1): 'grounds', ('castle_inside', 1): 'castle', ('castle_inside', 2): 'castle2',
               ('castle_inside', 3): 'castle3', ('castle_courtyard', 1): 'courtyard', ('bowser_1', 1): 'bowser'}


def scene_name(folder, area):
    return SCENE_NAMES.get((folder, area)) or (folder if area == 1 else '%s_%d' % (folder, area))


def scene_of(level_const, area):
    folder = LEVELS.get(level_const.strip())
    return scene_name(folder, area) if folder else None


WARP_NAMED = {'WARP_NODE_SUCCESS': 0xF0, 'WARP_NODE_DEATH': 0xF1, 'WARP_NODE_TOTWC': 0xF2, 'WARP_NODE_WARP_FLOOR': 0xF3}


def warp_id(s):
    s = s.strip()
    if s in WARP_NAMED:
        return WARP_NAMED[s]
    m = re.fullmatch(r'WARP_NODE_([0-9A-Fa-f]{2})', s)
    if m:
        return int(m.group(1), 16)
    return try_int(s)


def bparam_byte(bparam, n):
    """Byte n (1 = highest) of a behaviour parameter written as BPARAMn(x) | ... or as a plain number."""
    m = re.search(r'BPARAM%d\(\s*([^)]+?)\s*\)' % n, bparam)
    if m:
        v = warp_id(m.group(1))
        return v if v is not None else 0
    if 'BPARAM' in bparam:
        return 0
    v = try_int(bparam)
    return ((v >> (8 * (4 - n))) & 0xFF) if v is not None else 0


# behaviours that mark a place the player can arrive at, and how he arrives there
NODE_BHV = {
    'bhvDoorWarp': 'door',
    'bhvSpinAirborneWarp': 'air', 'bhvSpinAirborneCircleWarp': 'air', 'bhvAirborneWarp': 'air',
    'bhvAirborneStarCollectWarp': 'air', 'bhvAirborneDeathWarp': 'air', 'bhvHardAirKnockBackWarp': 'air',
    'bhvFlyingWarp': 'fly', 'bhvSwimmingWarp': 'ground',
    'bhvLaunchStarCollectWarp': 'ground', 'bhvLaunchDeathWarp': 'ground', 'bhvDeathWarp': 'ground',
    'bhvPaintingStarCollectWarp': 'ground', 'bhvPaintingDeathWarp': 'ground', 'bhvInstantActiveWarp': 'ground',
    'bhvWarp': 'trigger', 'bhvFadingWarp': 'fading', 'bhvWarpPipe': 'pipe',
    # (Tall, Tall Mountain's slide ends at a podium with a hole in its top: down the hole, back up the mountain. It
    # was only solid, and the slide had no way out, 2026-10-15.)
    'bhvExitPodiumWarp': 'trigger',
}


def warp_tables(entries, area):
    """(warps, painting warps) of one area: lists of {id, scene, node}"""
    warps, pwarps = [], []
    for e in entries:
        if e.get('area') != area or 'warp' not in e:
            continue
        a = e['args']
        if len(a) < 4:
            continue
        wid, node = warp_id(a[0]), warp_id(a[3])
        dest_area = try_int(a[2])
        scene = scene_of(a[1], dest_area) if dest_area is not None else None
        if wid is None or node is None or scene is None:
            continue
        (pwarps if e['warp'] == 'PAINTING_WARP_NODE' else warps).append({'id': wid, 'scene': scene, 'node': node})
    return warps, pwarps


def collision_pick(db, name, pick, offset=(0, 0, 0), scale=SCALE, yaw=0.0):
    """The triangles of a collision model whose surface type passes `pick`, in scene coordinates."""
    verts, groups, _water = X.parse_collision(db, name)
    if yaw:
        cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        verts = [(x * cy + z * sy, y, -x * sy + z * cy) for (x, y, z) in verts]
    pos, idx, vmap = [], [], {}
    n = 0
    for g in groups:
        if not pick(g['surface']):
            continue
        for tri in g['tris']:
            for vi in tri:
                if vi not in vmap:
                    vmap[vi] = len(vmap)
                    x, y, z = verts[vi]
                    pos += list(X.to_ue(x + offset[0], y + offset[1], z + offset[2], scale))
                idx.append(vmap[vi])
            n += 1
    if not n:
        return None
    return {'source': name, 'ntris': n, 'pos': pos, 'idx': idx}


def special_presets():
    """special preset -> (model, behaviour), from include/special_presets.inc.c"""
    t = X.strip_comments(open(os.path.join(X.D, 'include', 'special_presets.inc.c'), encoding='utf-8', errors='replace').read())
    out = {}
    for m in re.finditer(r'\{\s*(special_\w+)\s*,\s*\w+\s*,\s*(\w+)\s*,\s*(\w+)\s*,\s*(\w+)\s*\}', t):
        out[m.group(1)] = {'param': try_int(m.group(2)) or 0, 'model': m.group(3), 'bhv': m.group(4)}
    return out


def mario_pos(level):
    """(area, yaw, (x, y, z)) from the level script's MARIO_POS, or None"""
    t = X.strip_comments(open(os.path.join(X.D, 'levels', level, 'script.c'), encoding='utf-8', errors='replace').read())
    m = re.search(r'MARIO_POS\(\s*(\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)', t)
    if not m:
        return None
    return int(m.group(1)), int(m.group(2)), (int(m.group(3)), int(m.group(4)), int(m.group(5)))


MOVING_SAND = ('SURFACE_SHALLOW_MOVING_QUICKSAND', 'SURFACE_MOVING_QUICKSAND', 'SURFACE_DEEP_MOVING_QUICKSAND',
               'SURFACE_INSTANT_MOVING_QUICKSAND')
SINKING = {'SURFACE_SHALLOW_QUICKSAND': '10', 'SURFACE_SHALLOW_MOVING_QUICKSAND': '25', 'SURFACE_QUICKSAND': '60',
           'SURFACE_MOVING_QUICKSAND': '60', 'SURFACE_DEEP_QUICKSAND': 'deep', 'SURFACE_DEEP_MOVING_QUICKSAND': 'deep'}
OTHER_PAINTING_WARPS = {'SURFACE_TTC_PAINTING_1': 0xF4, 'SURFACE_TTC_PAINTING_2': 0xF5, 'SURFACE_TTC_PAINTING_3': 0xF6,
                        'SURFACE_WOBBLING_WARP': 0xFD}


def rule_floors(db, terrain, offset=(0, 0, 0), scale=SCALE):
    """Floor triangles that mean something beyond being floor, grouped by what they mean:
    lava, death (the plane under a level), quicksand that swallows at once, warp (a floor that sends the
    player out of the level), paint:N (the floor behind painting strip N) and instant:N (walk on it and
    the next area takes over)."""
    verts, groups, _water = X.parse_collision(db, terrain)
    by_tag = {}
    for g in groups:
        s = g['surface']
        tag = None
        if s == 'SURFACE_BURNING':
            tag = 'lava'
        elif s == 'SURFACE_DEATH_PLANE':
            tag = 'death'
        elif s == 'SURFACE_VERTICAL_WIND':
            tag = 'vwind'                 # (a chasm's bottom, as the death plane - check_death_barrier - that blows up:
                                          # apply_vertical_wind; game.lua G.apply_vwind)
        elif s in ('SURFACE_INSTANT_QUICKSAND', 'SURFACE_INSTANT_MOVING_QUICKSAND'):
            tag = 'quicksand'
        elif s == 'SURFACE_WARP':
            tag = 'warp'
        elif s == 'SURFACE_HANGABLE':
            tag = 'hang'                  # (mesh ceilings he can hang from: Scripts/hang.lua)
        elif s in SINKING:
            tag = 'sink:' + SINKING[s]     # (sand he sinks in: Scripts/quicksand.lua)
        elif s == 'SURFACE_TIMER_START':
            tag = 'timer_start'           # (Princess's Secret Slide's clock: game.lua G.pss_floor)
        elif s == 'SURFACE_TIMER_END':
            tag = 'timer_end'
        elif s.startswith('SURFACE_PAINTING_WARP_'):
            tag = 'paint:%d' % (int(s[-2:], 16) - 0xD3)
        elif s in OTHER_PAINTING_WARPS:
            # (painting warps by other names - level_update.c get_painting_warp_node takes every floor type from 0xD3
            # to 0xFD: Tick Tock Clock's clock face and the "wobbling" pools into Rainbow Ride and Hazy Maze Cave.
            # They were missing: those three courses could not be entered, 2026-10-15)
            tag = 'paint:%d' % (OTHER_PAINTING_WARPS[s] - 0xD3)
        elif s.startswith('SURFACE_INSTANT_WARP_'):
            tag = 'instant:%d' % (int(s[-2:], 16) - 0x1B)
        if tag and s in MOVING_SAND:
            # (moving quicksand carries him along: each triangle its own way and speed - force's low byte the
            # direction >> 8, its high byte which of 12, 8, 4, 0 a frame: game.lua G.sand_push)
            for tri, f in zip(g['tris'], g.get('force') or [0] * len(g['tris'])):
                by_tag.setdefault('%s@%d' % (tag, f & 0xFFFF), []).append(tri)
            continue
        if s == 'SURFACE_HORIZONTAL_WIND':
            # (each triangle its own way: the wind's direction is its force << 8 - game.lua G.wind)
            for tri, f in zip(g['tris'], g.get('force') or [0] * len(g['tris'])):
                by_tag.setdefault('wind:%d' % (f & 0xFF), []).append(tri)
        if tag:
            by_tag.setdefault(tag, []).extend(g['tris'])
    out = []
    for tag, tris in sorted(by_tag.items()):
        pos, idx, vmap = [], [], {}
        for tri in tris:
            for vi in tri:
                if vi not in vmap:
                    vmap[vi] = len(vmap)
                    x, y, z = verts[vi]
                    pos += list(X.to_ue(x + offset[0], y + offset[1], z + offset[2], scale))
                idx.append(vmap[vi])
        out.append({'tag': tag, 'ntris': len(tris), 'pos': pos, 'idx': idx})
    return out


def instant_warps(level, area):
    """[{index, scene, area, move}] for the INSTANT_WARP commands of one area (move = displacement in scene units)"""
    t = X.strip_comments(open(os.path.join(X.D, 'levels', level, 'script.c'), encoding='utf-8', errors='replace').read())
    out = []
    for m in re.finditer(r'\bAREA\s*\(\s*(\d+)', t):
        if int(m.group(1)) != area:
            continue
        end = t.find('END_AREA', m.end())
        for w in re.finditer(r'INSTANT_WARP\(\s*(\w+)\s*,\s*(\w+)\s*,\s*(-?\w+)\s*,\s*(-?\w+)\s*,\s*(-?\w+)\s*\)', t[m.end():end]):
            idx, dest = try_int(w.group(1)), try_int(w.group(2))
            dx, dy, dz = (to_int(w.group(k)) for k in (3, 4, 5))
            if idx is None or dest is None:
                continue
            out.append({'index': idx, 'scene': scene_name(level, dest), 'same': dest == area,
                        'move': [-dz * SCALE, dx * SCALE, dy * SCALE]})
    return out
