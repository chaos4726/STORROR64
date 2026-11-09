"""What each floor of each scene sounds like underfoot, Mario 64's way (mario.c mario_get_terrain_sound_addend: the
floor's surface type sorted into default / hard / slippery / very slippery / noisy, then sTerrainSounds by the area's
TERRAIN_TYPE), as STORROR's footstep surface types - only the floors that differ from the scene's own (game.lua
G.SURFACE_OF, else concrete). Out: Scripts/data/surfaces.lua, ten numbers a triangle (scene cm) and its type.
python tools/surfx.py   (from X:/mashup-work)"""
import os
import re
import sys
sys.path.insert(0, 'tools')
import luadata

U = 0.75
OUT = os.path.join(os.environ.get("SM64_MOD", r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map"), r"Scripts/data/surfaces.lua")
SCENES = os.path.join(os.environ.get("SM64_MOD", r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map"), r"Scripts/data/scenes.lua")
# game.lua G.SURFACE_OF
SCENE_DEFAULT = {'bob': 3, 'thi': 3, 'thi_2': 3, 'thi_3': 3, 'grounds': 3, 'ccm': 4, 'sl': 4, 'sl_2': 4, 'wmotr': 4,
                 'ssl': 2, 'bbh': 6}
SCENE_DEFAULT.pop('wmotr')

FLOOR_SOUND = {}
for t in ('SURFACE_NOT_SLIPPERY', 'SURFACE_HARD', 'SURFACE_HARD_NOT_SLIPPERY', 'SURFACE_SWITCH'):
    FLOOR_SOUND[t] = 1
for t in ('SURFACE_SLIPPERY', 'SURFACE_HARD_SLIPPERY', 'SURFACE_NO_CAM_COL_SLIPPERY'):
    FLOOR_SOUND[t] = 2
for t in ('SURFACE_VERY_SLIPPERY', 'SURFACE_ICE', 'SURFACE_HARD_VERY_SLIPPERY', 'SURFACE_NOISE_VERY_SLIPPERY_73',
          'SURFACE_NOISE_VERY_SLIPPERY_74', 'SURFACE_NOISE_VERY_SLIPPERY', 'SURFACE_NO_CAM_COL_VERY_SLIPPERY'):
    FLOOR_SOUND[t] = 3
for t in ('SURFACE_NOISE_DEFAULT', 'SURFACE_NOISE_SLIPPERY'):
    FLOOR_SOUND[t] = 4
QUICKSAND = re.compile(r'QUICKSAND')

D, GRASS, WATER, STONE, SPOOKY, SNOW, ICE, SAND = range(8)
TERRAIN_SOUNDS = {          # sTerrainSounds: default, hard, slippery, very slippery, noisy default, noisy slippery
    'TERRAIN_GRASS': (D, STONE, GRASS, GRASS, GRASS, D),
    'TERRAIN_STONE': (STONE, STONE, STONE, STONE, GRASS, GRASS),
    'TERRAIN_SNOW': (SNOW, ICE, SNOW, ICE, STONE, STONE),
    'TERRAIN_SAND': (SAND, STONE, SAND, SAND, STONE, STONE),
    'TERRAIN_SPOOKY': (SPOOKY, SPOOKY, SPOOKY, SPOOKY, STONE, STONE),
    'TERRAIN_WATER': (D, STONE, GRASS, ICE, STONE, ICE),
    'TERRAIN_SLIDE': (STONE, STONE, STONE, STONE, ICE, ICE),
}


# Mario 64's sound -> STORROR's footstep surface (1 concrete, 2 dirt, 3 grass, 4 gravel, 5 metal, 6 wood)
def storror(sound, terrain):
    if sound == D:
        return 3 if terrain == 'TERRAIN_GRASS' else 2
    return {GRASS: 3, WATER: 1, STONE: 1, SPOOKY: 6, SNOW: 4, ICE: 1, SAND: 2}[sound]


def terrain_of(level, area):
    src = open(os.path.join(os.environ.get('SM64_DECOMP', 'sm64decomp'), 'levels/%s/script.c' % level)).read()
    cur, out = None, {}
    for line in src.splitlines():
        m = re.search(r'AREA\(/\*index\*/\s*(\d+)', line)
        if m:
            cur = int(m.group(1))
        m = re.search(r'TERRAIN_TYPE\(/\*terrainType\*/\s*(TERRAIN_[A-Z]+)', line) or re.search(r'(TERRAIN_[A-Z]+)', line)
        if m and cur is not None and 'TERRAIN_TYPE' in line:
            out[cur] = m.group(1)
    return out.get(area, 'TERRAIN_STONE')


def floors(level, area):
    path = os.path.join(os.environ.get('SM64_DECOMP', 'sm64decomp'), 'levels/%s/areas/%d/collision.inc.c' % (level, area))
    col = open(path).read()
    col = col[:col.index('COL_END')]
    verts = [tuple(int(v) for v in m.groups()) for m in re.finditer(r'COL_VERTEX\(\s*(-?\d+),\s*(-?\d+),\s*(-?\d+)\s*\)', col)]
    surf = None
    out = []
    for line in col.splitlines():
        m = re.search(r'COL_TRI_INIT\(\s*([A-Z_0-9]+)', line)
        if m:
            surf = m.group(1)
            continue
        m = re.search(r'COL_TRI(?:_SPECIAL)?\(\s*(\d+),\s*(\d+),\s*(\d+)', line)
        if m and surf:
            p = [verts[int(g)] for g in m.groups()]
            ux, uy, uz = p[1][0] - p[0][0], p[1][1] - p[0][1], p[1][2] - p[0][2]
            vx, vy, vz = p[2][0] - p[1][0], p[2][1] - p[1][1], p[2][2] - p[1][2]
            nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            mag = (nx * nx + ny * ny + nz * nz) ** 0.5
            if mag and ny / mag > 0.01:
                out.append((p, surf))
    return out


def main():
    scenes = luadata.load(SCENES)
    lines = ['-- What the floors sound of underfoot where it is not the scene\'s own (tools/surfx.py, Mario 64\'s',
             '-- mario_get_terrain_sound_addend): per scene, ten numbers a triangle: x1 y1 z1 x2 y2 z2 x3 y3 z3 type.',
             'return {']
    for e in scenes:
        name, level, area = e['name'], e['level'], int(e['area'])
        try:
            fl = floors(level, area)
        except (OSError, ValueError):
            continue
        terrain = terrain_of(level, area)
        sounds = TERRAIN_SOUNDS.get(terrain, TERRAIN_SOUNDS['TERRAIN_STONE'])
        default = SCENE_DEFAULT.get(name, 1)
        flat, counts = [], {}
        for p, surf in fl:
            if QUICKSAND.search(surf):
                kind = storror(SAND, terrain)
            else:
                kind = storror(sounds[FLOOR_SOUND.get(surf, 0)], terrain)
            counts[kind] = counts.get(kind, 0) + 1
            if kind == default:
                continue
            for (x, y, z) in p:
                flat += ['%g' % (-z * U), '%g' % (x * U), '%g' % (y * U)]
            flat.append(str(kind))
        if not flat:
            print('%-10s %-15s all %d' % (name, terrain, default))
            continue
        lines.append('  %s = {' % name)
        for k in range(0, len(flat), 30):
            lines.append('    ' + ','.join(flat[k:k + 30]) + ',')
        lines.append('  },')
        print('%-10s %-15s default %d, floors by type %s' % (name, terrain, default, dict(sorted(counts.items()))))
    lines.append('}')
    open(OUT, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')


main()
