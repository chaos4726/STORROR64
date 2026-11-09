"""smooth_classic.py: the classic look's level pictures redrawn smooth ("Smooth classic look", 2026-10-31).
With RENDER 96 off the levels wear Mario 64's own pictures, mostly 32 x 32: stretched over a floor every pixel showed as a
square, and - the glTF materials wrap a picture in their own sums, so the blur never carries over its edge - every repeat
showed as a line, wherever a surface was not drawn from a tiled copy (Snowman's Land's see-through pool ice: "render 96 is
off right now and the seems are showing").
Each picture used by the levels' solid and see-through faces (data/scene_*.lua) is made SCALE times bigger, smoothly
(bicubic, wrapped round its edges first so its repeats still meet), and repeated N x N in one copy, as many as its
widest face needs and CAP allows (lib.lua M.TILES: the face's UVs moved to start at 0, the copy drawn at 1/N) - even N = 1:
the smooth picture alone. Writes textures/<name>.x<N>.png and Scripts/data/texture_tiles.lua; the old copies and table
are moved to textures_tiles_orig (python tools/smooth_classic.py, from X:/mashup-work).
Cut-out faces (fences, leaves) keep Mario 64's own: smoothed, their edges would blur."""
import glob
import math
import os
import shutil

import numpy as np
from PIL import Image
from lupa.lua54 import LuaRuntime

MOD = os.environ.get("SM64_MOD", r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map")
DATA = os.path.join(MOD, "Scripts", "data")
TEX = os.path.join(MOD, "textures")
OLD = os.path.join(MOD, "textures_tiles_orig")
SCALE = 4
CAP = 1024
PAD = 4
LAYERS = ("opaque", "opaque_decal", "translucent", "translucent_decal")

L = LuaRuntime(unpack_returned_tuples=True)
span = {}
for f in sorted(glob.glob(os.path.join(DATA, "scene_*.lua"))):
    try:
        d = L.execute(open(f, encoding="utf-8").read())
    except Exception as e:
        print("skip", os.path.basename(f), e)
        continue
    secs = d["sections"]
    if secs is None:
        continue
    for k in range(1, len(secs) + 1):
        s = secs[k]
        if s["layer"] not in LAYERS or s["uv"] is None or not s["texture"]:
            continue
        uv, n = s["uv"], s["nverts"]
        if not n:
            continue
        us = [uv[i * 2 + 1] for i in range(n)]
        vs = [uv[i * 2 + 2] for i in range(n)]
        sp = max(math.ceil(max(us)) - math.floor(min(us)), math.ceil(max(vs)) - math.floor(min(vs)), 1)
        span[s["texture"]] = max(span.get(s["texture"], 0), sp)

# (and the pictures the mod draws on surfaces of its own: the water boxes - game.lua add_water's WATER_TEX - and Mario
# 64's moving textures, data/movtex.lua: their repeats showed as squares across the water, "theres still seams" - the
# strip of Snowman's Land's pool under the brick wall, 2026-10-31. Repeated as often as CAP allows.)
EXTRA = ["water_surface2", "movtex_texture_waterbox_jrb_water", "movtex_texture_waterbox_mist",
         "movtex_texture_waterbox_lava", "movtex_texture_waterbox_unknown_water", "movtex_texture_waterbox_water",
         "movtex_ssl_pyramid_sand", "movtex_ssl_quicksand", "movtex_ttc_yellow_triangle"]
for name in EXTRA:
    span[name] = max(span.get(name, 0), 64)

# (the old copies and table kept - on the first run; after it, the copies made before are this tool's own: gone)
first = not os.path.exists(os.path.join(OLD, "texture_tiles.lua"))
os.makedirs(OLD, exist_ok=True)
for p in glob.glob(os.path.join(TEX, "*.x[0-9]*.png")):
    dst = os.path.join(OLD, os.path.basename(p))
    if first and not os.path.exists(dst):
        shutil.move(p, dst)
    else:
        os.remove(p)
tt = os.path.join(DATA, "texture_tiles.lua")
if os.path.exists(tt) and not os.path.exists(os.path.join(OLD, "texture_tiles.lua")):
    shutil.copy2(tt, os.path.join(OLD, "texture_tiles.lua"))


def smooth(img):
    """SCALE x bigger, bicubic, wrapped round: the picture padded with its own opposite edges, scaled, cut back"""
    a = np.asarray(img.convert("RGBA"))
    h, w = a.shape[:2]
    p = np.pad(a, ((PAD, PAD), (PAD, PAD), (0, 0)), mode="wrap")
    big = Image.fromarray(p, "RGBA").resize(((w + 2 * PAD) * SCALE, (h + 2 * PAD) * SCALE), Image.BICUBIC)
    return big.crop((PAD * SCALE, PAD * SCALE, (PAD + w) * SCALE, (PAD + h) * SCALE))


table, pixels, made = {}, 0, 0
for tex, sp in sorted(span.items()):
    src = os.path.join(TEX, tex + ".png")
    if not os.path.exists(src):
        continue
    try:
        img = Image.open(src)
        img.load()
    except Exception as e:
        print("unreadable", tex, e)
        continue
    w, h = img.size
    if max(w, h) * SCALE > CAP:
        continue                    # (already big: left as it is)
    sm = smooth(img)
    sw, sh = sm.size
    n = max(1, min(sp + 1, CAP // max(sw, sh)))
    out = Image.new("RGBA", (sw * n, sh * n))
    for i in range(n):
        for j in range(n):
            out.paste(sm, (i * sw, j * sh))
    out.save(os.path.join(TEX, "%s.x%d.png" % (tex, n)))
    table[tex] = n
    pixels += sw * n * sh * n
    made += 1

with open(tt, "w", encoding="utf-8", newline="\n") as fh:
    fh.write("-- SM64Map: each level texture's smooth copy (%dx, bicubic), repeated N x N (textures/<name>.x<N>.png) - "
             "tools/smooth_classic.py, lib.lua M.TILES\nreturn {\n" % SCALE)
    for tex in sorted(table):
        fh.write('  ["%s"] = %d,\n' % (tex, table[tex]))
    fh.write("}\n")
print("smooth copies:", made, "of", len(span), " all together: %.0f MB in memory" % (pixels * 4 / 1e6))
