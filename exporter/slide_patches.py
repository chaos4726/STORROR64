# slide_patches.py: the slide floors of a scene grouped into connected patches, each with its size across (the narrow
# way, flat) - railing tops are long and thin, real slopes are wide
import math, collections, sys
import build_all as B, sm64x as X, sm64scenes as S
import slidex as SX

def patches(name):
    for n, level, area in B.all_scenes():
        if n != name: continue
        blocks = S.area_blocks(level).get(area)
        verts, groups, _ = X.parse_collision(B.db, blocks['terrain'])
        tris = []
        for g in groups:
            st = g['surface']
            if st in SX.LEFT_OUT or st in SX.NOT: continue
            lim = 10.0 if st in SX.VERY else (20.0 if st in SX.SLIP else 38.0)
            for (a, b, c) in g['tris']:
                A, Bv, C = verts[a], verts[b], verts[c]
                ux, uy, uz = [Bv[i] - A[i] for i in range(3)]; vx, vy, vz = [C[i] - A[i] for i in range(3)]
                nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
                l = math.sqrt(nx * nx + ny * ny + nz * nz)
                if l == 0: continue
                if ny / l < 0.01 or math.degrees(math.acos(min(1, ny / l))) <= lim: continue
                tris.append((tuple(A), tuple(Bv), tuple(C), st, math.degrees(math.acos(min(1, ny / l)))))
        # union by shared vertex positions
        parent = list(range(len(tris)))
        def f(i):
            while parent[i] != i: parent[i] = parent[parent[i]]; i = parent[i]
            return i
        byv = collections.defaultdict(list)
        for i, t in enumerate(tris):
            for v in t[:3]: byv[v].append(i)
        for lst in byv.values():
            for j in lst[1:]: parent[f(j)] = f(lst[0])
        groups2 = collections.defaultdict(list)
        for i in range(len(tris)): groups2[f(i)].append(i)
        out = []
        for g in groups2.values():
            pts = [(v[0], v[2]) for i in g for v in tris[i][:3]]
            mx = sum(p[0] for p in pts) / len(pts); mz = sum(p[1] for p in pts) / len(pts)
            sxx = sum((p[0] - mx) ** 2 for p in pts); szz = sum((p[1] - mz) ** 2 for p in pts); sxz = sum((p[0] - mx) * (p[1] - mz) for p in pts)
            th = 0.5 * math.atan2(2 * sxz, sxx - szz)
            ax, az = math.cos(th), math.sin(th)
            along = [(p[0] - mx) * ax + (p[1] - mz) * az for p in pts]
            across = [-(p[0] - mx) * az + (p[1] - mz) * ax for p in pts]
            out.append(dict(n=len(g), idx=g, length=max(along) - min(along), width=max(across) - min(across),
                            centre=(round(mx), round(sum(v[1] for i in g for v in tris[i][:3]) / (3 * len(g))), round(mz)),
                            kinds=sorted(set(tris[i][3].replace('SURFACE_', '') for i in g)),
                            ang=sorted(set(round(tris[i][4]) for i in g))))
        return tris, out
    return [], []

if __name__ == '__main__':
    for name in sys.argv[1:]:
        tris, ps = patches(name)
        print('==', name, len(tris), 'tris', len(ps), 'patches')
        for p in sorted(ps, key=lambda p: p['width']):
            print('  w %5.0f  len %5.0f  n %3d  at %s  %s %s' % (p['width'], p['length'], p['n'], p['centre'], p['kinds'], p['ang']))
