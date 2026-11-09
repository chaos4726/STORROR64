import sys
sys.path.insert(0, 'X:/mashup-work/exporter')
import sm64x as X
db = X.DB()
import glob, re
for f in glob.glob('X:/mashup-work/sm64decomp/levels/*/areas/*/collision.inc.c'):
    t = open(f).read()
    if 'SURFACE_VERTICAL_WIND' not in t and 'SURFACE_HORIZONTAL_WIND' not in t:
        continue
    for m in re.finditer(r'const Collision (\w+)\[\]', t):
        name = m.group(1)
        try:
            verts, groups, water = X.parse_collision(db, name)
        except Exception as e:
            continue
        for g in groups:
            if g['surface'] in ('SURFACE_VERTICAL_WIND', 'SURFACE_HORIZONTAL_WIND'):
                ys = [verts[v][1] for tri in g['tris'] for v in tri]
                xs = [verts[v][0] for tri in g['tris'] for v in tri]
                zs = [verts[v][2] for tri in g['tris'] for v in tri]
                print(f.replace(chr(92), '/').split('levels/')[1].split('/collision')[0], g['surface'][8:], len(g['tris']), 'y %d..%d x %d..%d z %d..%d' % (min(ys), max(ys), min(xs), max(xs), min(zs), max(zs)))
