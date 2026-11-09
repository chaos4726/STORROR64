# slidex.py: Mario 64's slide surfaces for every scene -> data/slides.lua (the user, 2026-10-16: "add all the slide
# surfaces"). A floor slides Mario where mario_floor_is_slippery says so (mario.c -> INPUT_ABOVE_SLIDE): by its
# surface class (mario_get_floor_class) - very slippery (ice, very slippery...) over 10 degrees, slippery over 20,
# default over 38, not slippery never. The slide courses (TERRAIN_SLIDE: pss, ccm_2, ttm_2-4) are left out: game.lua
# makes every slope of theirs a slide already. Each scene's slide floors in scene space, as export_collision puts its
# terrain (to_ue, no offset) - game.lua takes them out of the scene's own collision and gives them a collision piece of
# their own that STORROR cannot stand on, so its own slope slide takes him down them.
#   SM64_DECOMP=X:/mashup-work/sm64decomp SM64_OUT=<mod dir> python slidex.py
import os, re, math
import build_all as B
import sm64x as X
import sm64scenes as S

VERY = {'SURFACE_VERY_SLIPPERY', 'SURFACE_ICE', 'SURFACE_HARD_VERY_SLIPPERY', 'SURFACE_NOISE_VERY_SLIPPERY_73',
        'SURFACE_NOISE_VERY_SLIPPERY_74', 'SURFACE_NOISE_VERY_SLIPPERY', 'SURFACE_NO_CAM_COL_VERY_SLIPPERY'}
SLIP = {'SURFACE_SLIPPERY', 'SURFACE_NOISE_SLIPPERY', 'SURFACE_HARD_SLIPPERY', 'SURFACE_NO_CAM_COL_SLIPPERY'}
NOT = {'SURFACE_NOT_SLIPPERY', 'SURFACE_HARD_NOT_SLIPPERY', 'SURFACE_SWITCH'}
# Railings, ledges and wall tops left standable (the user, 2026-10-16: "why is the charater sliding off of railings in
# the castle?" - Mario 64 makes them slippery so Mario cannot stand on them; STORROR's athlete balances on them): a
# patch of slide floor narrower than THIN across is left out, and inside the castle there are none at all (its slippery
# floors are the staircase banisters and ramps, nothing to slide down)
THIN = 120.0
NO_SLIDES = {'castle', 'castle2', 'castle3'}
# ...and every slide triangle narrower than THIN_TRI from above, on its own: the fences' bevelled tops (two 45 degree
# faces, ~20 units across each) run joined to the hills, so a patch of them is not narrow - "can you turn off sliding
# on all fences even the ones in bomb omb battlefield"; real slopes' triangles are 50 and more across
THIN_TRI = 45.0
# Snow slopes that slide from 5 degrees, not 10: Cool, Cool Mountain's mountainside is "very slippery" snow at 5-10
# degrees, where Mario 64's Mario stands but slides the moment he crouches, dives or lands from a dive
# (mario_floor_is_slope's 5 for that class) - its paths stay walkable, not slippery. The athlete has no dive slide:
# "next the charater doesnt slide down the mountain", 2026-10-18.
VERY_LIM = {'ccm': 5.0}
# Slopes left walkable where he asked (x, y, z middle, across, up/down - Mario 64 units; a slide triangle whose middle is
# inside stays a floor): CCM's slippery 25-degree rise by the snowball snowman's patch at the mountain's foot, "this
# areas making the player slide fix it", 2026-10-18
KEEP_WALKABLE = {'ccm': [(2840.0, -2600.0, 2760.0, 500.0, 400.0)]}
# (what export_collision leaves out, and the vanish-cap walls build_all exports apart)
LEFT_OUT = set(X.SKIP_SURFACES) | {'SURFACE_VANISH_CAP_WALLS'}


def slide_area(level, area):
    t = open(os.path.join(X.D, 'levels', level, 'script.c'), encoding='utf-8', errors='replace').read()
    for m in re.finditer(r'\bAREA\s*\(\s*(?:/\*[^*]*\*/)?\s*(\d+)(.*?)END_AREA', t, re.S):
        if int(m.group(1)) == area:
            return 'TERRAIN_SLIDE' in m.group(2)
    return False


def thin_tris(tris):
    """The tris (each three (x, y, z) corners) in patches narrower than THIN across, flat - joined where they share a
    corner, their narrow way found from the spread of their corners."""
    import collections
    parent = list(range(len(tris)))

    def f(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    byv = collections.defaultdict(list)
    for i, t in enumerate(tris):
        for v in t:
            byv[v].append(i)
    for lst in byv.values():
        for j in lst[1:]:
            parent[f(j)] = f(lst[0])
    patches = collections.defaultdict(list)
    for i in range(len(tris)):
        patches[f(i)].append(i)
    thin = set()
    for i, (a, b, c) in enumerate(tris):
        area2 = abs((b[0] - a[0]) * (c[2] - a[2]) - (c[0] - a[0]) * (b[2] - a[2]))
        longest = max(math.dist((a[0], a[2]), (b[0], b[2])), math.dist((b[0], b[2]), (c[0], c[2])),
                      math.dist((a[0], a[2]), (c[0], c[2])))
        if area2 / max(longest, 1.0) < THIN_TRI:
            thin.add(i)
    for g in patches.values():
        pts = [(v[0], v[2]) for i in g for v in tris[i]]
        mx = sum(p[0] for p in pts) / len(pts)
        mz = sum(p[1] for p in pts) / len(pts)
        sxx = sum((p[0] - mx) ** 2 for p in pts)
        szz = sum((p[1] - mz) ** 2 for p in pts)
        sxz = sum((p[0] - mx) * (p[1] - mz) for p in pts)
        th = 0.5 * math.atan2(2 * sxz, sxx - szz)
        across = [-(p[0] - mx) * math.sin(th) + (p[1] - mz) * math.cos(th) for p in pts]
        if max(across) - min(across) < THIN:
            thin.update(g)
    return thin


def slides_of(sym, name=None):
    verts, groups, _ = X.parse_collision(B.db, sym)
    pos, idx, vmap, n, kinds = [], [], {}, 0, {}
    picked = []
    for g in groups:
        st = g['surface']
        if st in LEFT_OUT or st in NOT:
            continue
        lim = VERY_LIM.get(name, 10.0) if st in VERY else (20.0 if st in SLIP else 38.0)
        for (a, b, c) in g['tris']:
            A, Bv, C = verts[a], verts[b], verts[c]
            ux, uy, uz = Bv[0] - A[0], Bv[1] - A[1], Bv[2] - A[2]
            vx, vy, vz = C[0] - A[0], C[1] - A[1], C[2] - A[2]
            nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            l = math.sqrt(nx * nx + ny * ny + nz * nz)
            if l == 0.0:
                continue
            ny /= l
            # (a floor - facing up, as find_floor takes it - steeper than its class lets Mario stand)
            if ny < 0.01 or math.degrees(math.acos(min(1.0, ny))) <= lim:
                continue
            mx, my, mz = (A[0] + Bv[0] + C[0]) / 3.0, (A[1] + Bv[1] + C[1]) / 3.0, (A[2] + Bv[2] + C[2]) / 3.0
            if any((mx - kx) ** 2 + (mz - kz) ** 2 < kr * kr and abs(my - ky) < kh
                   for kx, ky, kz, kr, kh in KEEP_WALKABLE.get(name, [])):
                continue
            picked.append((a, b, c, st))
    thin = thin_tris([tuple(tuple(verts[v]) for v in t[:3]) for t in picked])
    for i, (a, b, c, st) in enumerate(picked):
        if i in thin:
            continue
        for vi in (a, b, c):
            if vi not in vmap:
                vmap[vi] = len(vmap)
                x, y, z = verts[vi]
                pos += list(X.to_ue(x, y, z, X.SCALE))
            idx.append(vmap[vi])
        n += 1
        k = 'very slippery' if st in VERY else ('slippery' if st in SLIP else 'steep')
        kinds[k] = kinds.get(k, 0) + 1
    return {'ntris': n, 'pos': pos, 'idx': idx, 'kinds': kinds} if n else None


def main():
    out = {}
    for name, level, area in B.all_scenes():
        try:
            blocks = S.area_blocks(level).get(area)
        except Exception as e:
            print('!!', name, e)
            continue
        if not blocks or not blocks['terrain'] or slide_area(level, area) or name in NO_SLIDES:
            continue
        s = slides_of(blocks['terrain'], name)
        if s:
            out[name] = s
            print('%-12s %4d slide tris %s' % (name, s['ntris'], s['kinds']))
    X.write_lua(os.path.join(B.DATA, 'slides.lua'), out)
    print('wrote', os.path.join(B.DATA, 'slides.lua'), len(out), 'scenes')


if __name__ == '__main__':
    main()
