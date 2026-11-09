"""Bake sun shadows into a scene's vertex colours ("next I want to work on shadows, I want them baked into the game",
2026-10-30: the level and its fixed objects baked; moving things get real-time shadows separately).

The sun's rays are parallel, so the whole level is drawn once into a shadow map seen from the sun (orthographic, each
texel keeping the nearest-to-the-sun depth), and every vertex is darkened by how much of the sun it can see there (a
3x3 soft sample). Mario 64's levels are coarse - Bob-omb Battlefield's field is a few huge triangles - so a triangle
whose inside is not all lit or all shaded is split in four, again and again down to MIN_EDGE, until each piece is even:
a tree's shadow in the middle of the field gets its shape.

Usage: python tools/shadowbake.py <scene> [--png]
Writes Scripts/data/shadow_<scene>.lua: replacement sections (by id) that game.lua swaps in as the scene loads.
"""
import os
import math
import sys
import time

import numpy as np
from lupa import LuaRuntime

MOD = os.environ.get("SM64_MOD", r"E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map")
DATA = MOD + "/Scripts/data"

SUN_ELEVATION = 65.0        # degrees over the horizon: high, a little to the side (the user's pick, 2026-10-30)
SUN_AZIMUTH = 35.0          # degrees, in the scene's X-Y plane
SHADE = 0.58                # colour kept in full shadow
TEXEL = 6.0                 # cm, the shadow map's resolution
BIAS = 6.0                  # cm, depth bias (on top of the normal offset)
NORMAL_OFFSET = 5.0         # cm, receivers sampled this far out along their normal
MIN_EDGE = 22.0             # cm, no piece is split below this
SAMPLE_STEP = 30.0          # cm, how close the samples inside a triangle are when checking it is even
MAX_SPLIT = 9               # times a triangle may be split (each split halves its edges)


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


def load_scene(scene):
    L = LuaRuntime()
    with open(f"{DATA}/scene_{scene}.lua", encoding="utf-8") as f:
        return L.execute(f.read())


def sun_basis():
    el, az = math.radians(SUN_ELEVATION), math.radians(SUN_AZIMUTH)
    d = np.array([math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)])
    up = np.array([0.0, 0.0, 1.0])
    u = np.cross(up, d); u /= np.linalg.norm(u)
    v = np.cross(d, u); v /= np.linalg.norm(v)
    return d, u, v


class ShadowMap:
    def __init__(self, d, u, v, pts):
        self.d, self.u, self.v = d, u, v
        pu, pv = pts @ u, pts @ v
        self.u0, self.v0 = pu.min() - 50.0, pv.min() - 50.0
        self.w = int((pu.max() - self.u0 + 50.0) / TEXEL) + 2
        self.h = int((pv.max() - self.v0 + 50.0) / TEXEL) + 2
        self.depth = np.full((self.h, self.w), -1e12, dtype=np.float64)

    def raster(self, tris, uvs=None, mask=None):
        """tris: (n, 3, 3) world points of occluding triangles; with uvs (n, 3, 2) and mask (a picture's solid texels,
        h x w booleans) only where the picture is solid - a tree's leaves, a fence's bars"""
        u, v, d = self.u, self.v, self.d
        P = tris.reshape(-1, 3)
        TU = ((P @ u - self.u0) / TEXEL).reshape(-1, 3)
        TV = ((P @ v - self.v0) / TEXEL).reshape(-1, 3)
        TD = (P @ d).reshape(-1, 3)
        for k in range(len(tris)):
            x, y, z = TU[k], TV[k], TD[k]
            x0, x1 = max(int(math.floor(x.min())), 0), min(int(math.ceil(x.max())), self.w - 1)
            y0, y1 = max(int(math.floor(y.min())), 0), min(int(math.ceil(y.max())), self.h - 1)
            if x1 < x0 or y1 < y0:
                continue
            den = (y[1] - y[2]) * (x[0] - x[2]) + (x[2] - x[1]) * (y[0] - y[2])
            if abs(den) < 1e-9:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            a = ((y[1] - y[2]) * (gx - x[2]) + (x[2] - x[1]) * (gy - y[2])) / den
            b = ((y[2] - y[0]) * (gx - x[2]) + (x[0] - x[2]) * (gy - y[2])) / den
            c = 1.0 - a - b
            inside = (a >= -1e-6) & (b >= -1e-6) & (c >= -1e-6)
            if not inside.any():
                continue
            if mask is not None and uvs is not None:
                tuv = uvs[k]
                su = a * tuv[0][0] + b * tuv[1][0] + c * tuv[2][0]
                sv = a * tuv[0][1] + b * tuv[1][1] + c * tuv[2][1]
                mh, mw = mask.shape
                ix = np.floor(su * mw).astype(np.int64) % mw
                iy = np.floor(sv * mh).astype(np.int64) % mh
                inside &= mask[iy, ix]
                if not inside.any():
                    continue
            dep = a * z[0] + b * z[1] + c * z[2]
            sub = self.depth[y0:y1 + 1, x0:x1 + 1]
            np.maximum(sub, np.where(inside, dep, -1e12), out=sub)

    def lit(self, pts, nrm, facing_too=True):
        """fraction of the sun seen at each point (n, 3), its normal (n, 3): 3x3 samples round its texel (and, with
        facing_too, the face's own turn from the sun)"""
        d = self.d
        facing = nrm @ d
        p = pts + nrm * NORMAL_OFFSET
        tu = (p @ self.u - self.u0) / TEXEL
        tv = (p @ self.v - self.v0) / TEXEL
        dep = p @ d
        # (a surface steep to the sun changes depth fast across a texel - and the 3x3 sample reaches a texel further:
        # its bias grows with the slope, or it shades itself in stripes - "acne")
        c = np.clip(np.abs(facing), 0.05, 1.0)
        bias = BIAS + np.minimum(TEXEL * 2.5 * np.sqrt(1.0 - c * c) / c, 80.0)
        out = np.zeros(len(pts))
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                ix = np.clip(np.floor(tu).astype(int) + dx, 0, self.w - 1)
                iy = np.clip(np.floor(tv).astype(int) + dy, 0, self.h - 1)
                out += (self.depth[iy, ix] <= dep + bias)
        out /= 9.0
        if not facing_too:
            return out
        # (a face turned from the sun is in its own shade, softly as it turns away)
        turn = np.clip(facing / 0.15, 0.0, 1.0)
        return np.minimum(out, turn)


_masks = {}


def tex_mask(name):
    """a picture's solid texels (alpha over half), or None: drawn whole"""
    if name in _masks:
        return _masks[name]
    m = None
    try:
        from PIL import Image
        im = np.array(Image.open(f"{MOD}/textures/{name}.png").convert("RGBA"))
        m = im[:, :, 3] > 127
    except Exception:
        m = None
    _masks[name] = m
    return m


S = 0.75


def sins(a):
    return math.sin(a * math.pi / 32768.0)


def coss(a):
    return math.cos(a * math.pi / 32768.0)


def axes(pitch, yaw, roll):
    """platforms.lua's axes: an object's forward, right and up in the scene, from its Mario 64 angles"""
    sx, cx = sins(pitch), coss(pitch)
    sy, cy = sins(yaw), coss(yaw)
    sz, cz = sins(roll), coss(roll)
    exx, exy, exz = cy * cz + sx * sy * sz, cx * sz, -sy * cz + sx * cy * sz
    eyx, eyy, eyz = -cy * sz + sx * sy * cz, cx * cz, sy * sz + sx * cy * cz
    ezx, ezy, ezz = cx * sy, -sx, cx * cy
    return np.array([ezz, -ezx, -ezy]), np.array([-exz, exx, exy]), np.array([-eyz, eyx, eyy])


def sec_arrays(sec):
    pos = np.array(lua_list(sec["pos"]), dtype=np.float64).reshape(-1, 3)
    idx = np.array(lua_list(sec["idx"]), dtype=np.int64).reshape(-1, 3)
    uv = np.array(lua_list(sec["uv"]), dtype=np.float64).reshape(-1, 2)
    return pos, idx, uv


# Things that never move: their models cast baked shadows too ("alot of the stuff in the level has no shadows",
# 2026-10-30). What moves, breaks or goes - see-saws, lifts, boxes, enemies - gets real-time shadows instead.
FIXED_PLATFORMS = {"static", "wpost", "cannon", "wbomb_cannon", "grill_door", "purple_switch"}
# (game.lua's G.TREE_MOVES: a tree the mod moved - from x, y to x, y, z, scene cm)
TREE_MOVES = {"bob": [(-2829.0, 3156.0, -3079.0, 3504.0, 753.0)]}


def object_occluders(d, scene, sun_d):
    """(tris, uvs, mask) groups for the fixed objects: platforms, the chain chomp's post, trees (their picture turned
    to the sun, its whole outline), props"""
    groups = []
    L = LuaRuntime()
    tpls = d["templates"]
    trees = d["tree_templates"]
    objs = [d["objects"][i] for i in range(1, len(d["objects"]) + 1)]

    def add_sections(sections, place):
        for i in range(1, len(sections) + 1):
            sec = sections[i]
            if sec["layer"] not in ("opaque", "alpha"):
                continue
            pos, idx, uv = sec_arrays(sec)
            if len(idx) == 0:
                continue
            w = place(pos)
            mask = tex_mask(sec["texture"]) if sec["layer"] == "alpha" else None
            groups.append((w[idx], uv[idx], mask))

    def plat_place(o_pos, o_ang, o_scale):
        x, y, z = (o_pos[i] for i in (1, 2, 3))
        ang = [o_ang[i] for i in (1, 2, 3)] if o_ang else [0, 0, 0]
        u = 65536.0 / 360.0
        f, r, up = axes(math.floor(ang[0] * u + 0.5), math.floor(ang[1] * u + 0.5), math.floor(ang[2] * u + 0.5))
        sc = [o_scale[i] for i in (1, 2, 3)] if o_scale else [1.0, 1.0, 1.0]
        us = np.array([sc[2], sc[0], sc[1]])
        origin = np.array([-z * S, x * S, y * S])

        def place(pos):
            lp = pos * us
            return origin + lp[:, 0:1] * f + lp[:, 1:2] * r + lp[:, 2:3] * up
        return place

    def tree_place(x, y, z):
        h = np.array([sun_d[0], sun_d[1], 0.0])
        h /= np.linalg.norm(h)
        side = np.array([-h[1], h[0], 0.0])
        upz = np.array([0.0, 0.0, 1.0])
        origin = np.array([x, y, z])
        return lambda pos: origin + pos[:, 0:1] * h + pos[:, 1:2] * side + pos[:, 2:3] * upz

    def prop_place(x, y, z, yaw_deg):
        yaw = math.radians(yaw_deg or 0.0)
        cy, sy = math.cos(yaw), math.sin(yaw)
        origin = np.array([x, y, z])
        return lambda pos: origin + np.stack([pos[:, 0] * cy - pos[:, 1] * sy, pos[:, 0] * sy + pos[:, 1] * cy, pos[:, 2]], 1)

    n_plat = n_tree = n_prop = 0
    for o in objs:
        kind = o["kind"]
        if kind == "platform" and o["bhv"] in FIXED_PLATFORMS and o["tpl"] and tpls[o["tpl"]]:
            t = tpls[o["tpl"]]
            if t["sections"]:
                add_sections(t["sections"], plat_place(o["pos"], o["ang"], o["scale"]))
                n_plat += 1
        elif kind == "chain_chomp" and o["post_tpl"] and tpls[o["post_tpl"]] and o["sm64"]:
            add_sections(tpls[o["post_tpl"]]["sections"], plat_place(o["sm64"], None, None))
            n_plat += 1
        elif kind == "tree" and trees and o["geo"] and trees[o["geo"]]:
            x, y, z = (o["pos"][i] for i in (1, 2, 3))
            for mv in TREE_MOVES.get(scene, []):
                if abs(x - mv[0]) < 5.0 and abs(y - mv[1]) < 5.0:
                    x, y, z = mv[2], mv[3], mv[4]
            add_sections(trees[o["geo"]], tree_place(x, y, z))
            n_tree += 1
        elif kind == "prop" and o["actor"]:
            try:
                with open(f"{DATA}/actor_{o['actor']}.lua", encoding="utf-8") as fa:
                    ad = L.execute(fa.read())
            except Exception:
                continue
            parts = ad["parts"] if ad and ad["parts"] else None
            if parts:
                x, y, z = (o["pos"][i] for i in (1, 2, 3))
                place = prop_place(x, y, z, o["yaw"])
                plist = [parts[i] for i in range(1, len(parts) + 1)]
                # (each part at its offset, added up through its parents - parent -1 the root)
                offs = []
                for pt in plist:
                    off = np.array([pt["off"][i] for i in (1, 2, 3)], dtype=np.float64) if pt["off"] else np.zeros(3)
                    par = pt["parent"]
                    if par is not None and par >= 0 and par < len(offs):
                        off = off + offs[par]
                    offs.append(off)
                for pt, off in zip(plist, offs):
                    if pt["sections"]:
                        add_sections(pt["sections"], lambda pos, off=off: place(pos + off))
                n_prop += 1
    print(f"fixed objects: {n_plat} platforms, {n_tree} trees, {n_prop} props")
    return groups


def sample_points(a, b, c):
    """points spread inside a triangle about SAMPLE_STEP apart (its corners, edge midpoints, centre, and a grid)"""
    e = max(np.linalg.norm(b - a), np.linalg.norm(c - b), np.linalg.norm(a - c))
    n = max(2, int(e / SAMPLE_STEP))
    pts = []
    for i in range(n + 1):
        for j in range(n + 1 - i):
            s, t = i / n, j / n
            pts.append(a + (b - a) * s + (c - a) * t)
    return np.array(pts)


def bake_section(sm, sec):
    pos = np.array(lua_list(sec["pos"]), dtype=np.float64).reshape(-1, 3)
    nrm_l = lua_list(sec["nrm"])
    nrm = np.array(nrm_l, dtype=np.float64).reshape(-1, 3) if nrm_l else np.tile([0.0, 0.0, 1.0], (len(pos), 1))
    uv = np.array(lua_list(sec["uv"]), dtype=np.float64).reshape(-1, 2)
    col = np.array(lua_list(sec["col"]), dtype=np.float64).reshape(-1, 4)
    idx = np.array(lua_list(sec["idx"]), dtype=np.int64).reshape(-1, 3)
    # (new vertices: lists, attributes interpolated)
    P, N, U, C = list(pos), list(nrm), list(uv), list(col)
    out_tris = []
    mid_cache = {}

    def mid(i, j):
        key = (min(i, j), max(i, j))
        if key in mid_cache:
            return mid_cache[key]
        P.append((P[i] + P[j]) * 0.5)
        n = N[i] + N[j]
        ln = np.linalg.norm(n)
        N.append(n / ln if ln > 1e-9 else N[i])
        U.append((U[i] + U[j]) * 0.5)
        C.append((C[i] + C[j]) * 0.5)
        mid_cache[key] = len(P) - 1
        return mid_cache[key]

    def tri_normal(i, j, k):
        # (the scene's triangles wind the other way round from Mario 64's - its x, z made the scene's y, -x - so the
        # face's side is taken from its corners' own normals)
        n = np.cross(P[j] - P[i], P[k] - P[i])
        ln = np.linalg.norm(n)
        if ln <= 1e-9:
            return np.array([0.0, 0.0, 1.0])
        n = n / ln
        if n @ (N[i] + N[j] + N[k]) < 0.0:
            n = -n
        return n

    stack = [(int(t[0]), int(t[1]), int(t[2]), 0) for t in idx]
    while stack:
        i, j, k, depth = stack.pop()
        a, b, c = P[i], P[j], P[k]
        edge = max(np.linalg.norm(b - a), np.linalg.norm(c - b), np.linalg.norm(a - c))
        split = False
        if depth < MAX_SPLIT and edge > MIN_EDGE * 2.0:
            pts = sample_points(a, b, c)
            tn = tri_normal(i, j, k)
            # (split where a cast shadow's edge crosses it - not for a face's smooth turn from the sun, which its
            # corners' colours already blend; nor on a face turned away, all in shade anyway)
            if tn @ sm.d > 0.05:
                f = sm.lit(pts, np.tile(tn, (len(pts), 1)), facing_too=False)
                split = (f.max() - f.min()) > 0.2
        if split:
            ij, jk, ki = mid(i, j), mid(j, k), mid(k, i)
            stack += [(i, ij, ki, depth + 1), (ij, j, jk, depth + 1), (ki, jk, k, depth + 1), (ij, jk, ki, depth + 1)]
        else:
            out_tris.append((i, j, k))
    # (only the vertices still used, renumbered)
    used = sorted({v for t in out_tris for v in t})
    remap = {v: n for n, v in enumerate(used)}
    P2 = np.array([P[v] for v in used]); N2 = np.array([N[v] for v in used])
    U2 = np.array([U[v] for v in used]); C2 = np.array([C[v] for v in used])
    lit = sm.lit(P2, N2)
    k = SHADE + (1.0 - SHADE) * lit
    C2[:, 0:3] *= k[:, None]
    tris = [(remap[a], remap[b], remap[c]) for a, b, c in out_tris]
    return P2, N2, U2, C2, tris, len(pos), float((lit < 0.5).mean())


def fmt(arr, nd):
    return ",".join(f"{x:.{nd}f}".rstrip("0").rstrip(".") if isinstance(x, float) else str(x) for x in arr)


def main():
    scene = sys.argv[1]
    png = "--png" in sys.argv
    t0 = time.time()
    d = load_scene(scene)
    secs = [d["sections"][i] for i in range(1, len(d["sections"]) + 1)]
    sd, su, sv = sun_basis()
    occ, allp, cut = [], [], []
    for s in secs:
        pos, idx, uv = sec_arrays(s)
        allp.append(pos)
        if s["layer"] == "opaque":
            occ.append(pos[idx])
        # (the level's own cut-out pieces - fences, grates - neither cast nor take shadows: their bars threw striped ones
        # and shaded themselves - "fences give off they're very own shadows very weird", 2026-10-30)
    sm = ShadowMap(sd, su, sv, np.concatenate(allp))
    sm.raster(np.concatenate(occ))
    for tris, uvs, mask in cut + object_occluders(d, scene, sd):
        sm.raster(tris, uvs, mask)
    print(f"shadow map {sm.w}x{sm.h} ({time.time() - t0:.1f}s)")
    if png:
        from PIL import Image
        dep = sm.depth.copy()
        m = dep > -1e11
        lo, hi = dep[m].min(), dep[m].max()
        img = np.zeros_like(dep); img[m] = (dep[m] - lo) / (hi - lo) * 255
        Image.fromarray(img.astype(np.uint8)[::-1]).save(f"X:/mashup-work/shots/shadowmap_{scene}.png")
    out = []
    tv0 = tv1 = 0
    for s in secs:
        if s["layer"] != "opaque":
            continue
        P, N, U, C, tris, n0, dark = bake_section(sm, s)
        tv0 += n0; tv1 += len(P)
        out.append((s["id"], P, N, U, C, tris))
        print(f"  section {s['id']} {s['layer']} {s['texture']}: {n0} -> {len(P)} verts, {dark * 100:.0f}% in shade")
    with open(f"{DATA}/shadow_{scene}.lua", "w", encoding="utf-8", newline="\n") as f:
        f.write(f"-- generated by tools/shadowbake.py: sun shadows baked into {scene}'s colours "
                f"(sun {SUN_ELEVATION:.0f} deg up, {SUN_AZIMUTH:.0f} round; shade {SHADE})\n")
        f.write("return {\n  sections = {\n")
        for sid, P, N, U, C, tris in out:
            f.write(f"    [{sid}] = {{ nverts = {len(P)}, ntris = {len(tris)},\n")
            f.write("      pos = {" + ",".join(f"{x:.2f}" for x in P.reshape(-1)) + "},\n")
            f.write("      nrm = {" + ",".join(f"{x:.3f}" for x in N.reshape(-1)) + "},\n")
            f.write("      uv = {" + ",".join(f"{x:.4f}" for x in U.reshape(-1)) + "},\n")
            f.write("      col = {" + ",".join(f"{x:.3f}" for x in C.reshape(-1)) + "},\n")
            f.write("      idx = {" + ",".join(str(i) for t in tris for i in t) + "} },\n")
        f.write("  },\n}\n")
    print(f"{scene}: {tv0} -> {tv1} verts in {len(out)} sections ({time.time() - t0:.1f}s)")


if __name__ == "__main__":
    main()
