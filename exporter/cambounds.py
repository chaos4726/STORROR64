# cambounds.py: SM64's camera-only walls (SURFACE_CAMERA_BOUNDARY) in each collision source, as triangle ranges in the
# order export_collision writes them - data/camera_bounds.lua (game.lua keeps the camera inside them). The first one,
# 2026-10-19, was lost; written again 2026-11-01 for the installer: its output, the same.
import os, sys
sys.argv = [sys.argv[0], 'none-only']
import build_all as BA
import sm64x as X

# (the sources it was made for: Snowman's Land's has some too, left out then and so now)
SOURCES = ['cotmc_seg7_collision_level', 'inside_castle_seg7_area_3_collision']
out = ['-- SM64\'s camera-only walls (SURFACE_CAMERA_BOUNDARY) in each collision source: { total triangles, {first, count}, ... }',
       '-- (0-based triangle numbers in the exported order). Made by cambounds.py, 2026-10-19.', 'return {']
for name in SOURCES:
    verts, groups, water = X.parse_collision(BA.db, name)
    n, runs = 0, []
    for g in groups:
        if g['surface'] in X.SKIP_SURFACES:
            continue
        k = len(g['tris'])
        if g['surface'] == 'SURFACE_CAMERA_BOUNDARY' and k:
            if runs and runs[-1][0] + runs[-1][1] == n:
                runs[-1][1] += k
            else:
                runs.append([n, k])
        n += k
    out.append('  ["%s"] = { total = %d, %s },' % (name, n, ', '.join('{ %d, %d }' % (a, b) for a, b in runs)))
out += ['}', '']
p = os.path.join(BA.DATA, 'camera_bounds.lua')
open(p, 'w', encoding='utf-8', newline='\n').write('\n'.join(out))
print('wrote', p)
