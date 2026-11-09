# icex.py: Mario 64's ice for every scene -> data/ice.lua (the user, 2026-10-26: "next player sliding on ice"). Its
# SURFACE_ICE floors that are not slides already (slidex.py takes those steeper than the class lets Mario stand) - the
# flat ice, where Mario 64's Mario walks but skids: apply_slope_decel's very slippery 0.2 of the braking. (Only the ice
# itself: the rest of its class - "very slippery" bits in Tiny-Huge Island, Shifting Sand Land, the Fire Sea - is no
# ice to look at, and would have been more slippery spots out of nowhere.) game.lua gives him little grip on them. The
# slide courses (TERRAIN_SLIDE) and the castle's floors left out, as slidex.py leaves them. Scene space (to_ue).
#   SM64_DECOMP=X:/mashup-work/sm64decomp SM64_OUT=<mod dir> python icex.py
import os, math
import build_all as B
import sm64x as X
import sm64scenes as S
import slidex as SX


# (Tiny-Huge Island's "ice": hidden floors far under its sea, nothing drawn on them - left out)
ICE_SKIP = {'thi', 'thi_2'}


def ice_of(sym, name=None):
    verts, groups, _ = X.parse_collision(B.db, sym)
    pos, idx, vmap, n = [], [], {}, 0
    for g in groups:
        st = g['surface']
        if st != 'SURFACE_ICE':
            continue
        lim = SX.VERY_LIM.get(name, 10.0)
        for (a, b, c) in g['tris']:
            A, Bv, C = verts[a], verts[b], verts[c]
            ux, uy, uz = Bv[0] - A[0], Bv[1] - A[1], Bv[2] - A[2]
            vx, vy, vz = C[0] - A[0], C[1] - A[1], C[2] - A[2]
            nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            l = math.sqrt(nx * nx + ny * ny + nz * nz)
            if l == 0.0:
                continue
            ny /= l
            # (a floor, no steeper than its class lets Mario stand: steeper is a slide - slidex.py)
            if ny < 0.01 or math.degrees(math.acos(min(1.0, ny))) > lim:
                continue
            for vi in (a, b, c):
                if vi not in vmap:
                    vmap[vi] = len(vmap)
                    x, y, z = verts[vi]
                    pos += list(X.to_ue(x, y, z, X.SCALE))
                idx.append(vmap[vi])
            n += 1
    return {'ntris': n, 'pos': pos, 'idx': idx} if n else None


def main():
    out = {}
    for name, level, area in B.all_scenes():
        try:
            blocks = S.area_blocks(level).get(area)
        except Exception as e:
            print('!!', name, e)
            continue
        if not blocks or not blocks['terrain'] or SX.slide_area(level, area) or name in SX.NO_SLIDES or name in ICE_SKIP:
            continue
        s = ice_of(blocks['terrain'], name)
        if s:
            out[name] = s
            print('%-12s %4d ice tris' % (name, s['ntris']))
    path = os.path.join(os.environ.get('ICE_OUT') or B.DATA, 'ice.lua')
    X.write_lua(path, out)
    print('wrote', path, len(out), 'scenes')


if __name__ == '__main__':
    main()
