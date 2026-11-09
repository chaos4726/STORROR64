# tile_textures.py : for every solid level texture, a copy of it repeated N x N (textures/<name>.x<N>.png) and the table
# of N (Scripts/data/texture_tiles.lua). The glTF materials the mod draws with wrap a picture in the shader, without the
# blur carrying over the picture's edge: every repeat showed as a square ("squares in the floor and wall", 2026-10-30).
# Drawn from a copy N times over (lib.lua M.TILES), a piece of level whose picture repeats no more than N times across it
# (its UVs moved by whole repeats to start at 0 - lib.add_sections) shows no edge at all.
import glob, math, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from pngtile import read_png, write_png
from lupa.lua54 import LuaRuntime

MOD = os.environ.get("SM64_MOD", r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map")
DATA = os.path.join(MOD, "Scripts", "data")
TEX = os.path.join(MOD, "textures")
CAP = 1024                       # the copies' largest side, pixels

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
        if s["layer"] not in ("opaque", "opaque_decal") or s["uv"] is None or not s["texture"]:
            continue
        uv, n = s["uv"], s["nverts"]
        if not n:
            continue
        us = [uv[i * 2 + 1] for i in range(n)]
        vs = [uv[i * 2 + 2] for i in range(n)]
        sp = max(math.ceil(max(us)) - math.floor(min(us)), math.ceil(max(vs)) - math.floor(min(vs)))
        span[s["texture"]] = max(span.get(s["texture"], 0), sp)

table, pixels, made = {}, 0, 0
for tex, sp in sorted(span.items()):
    src = os.path.join(TEX, tex + ".png")
    if sp <= 1 or not os.path.exists(src):
        continue
    try:
        w, h, rows = read_png(src)
    except Exception as e:
        print("unreadable", tex, e)
        continue
    n = min(sp + 1, CAP // max(w, h))
    if n < 2:
        continue
    out = []
    for _ in range(n):
        for r in rows:
            out.append(bytes(r) * n)
    write_png(os.path.join(TEX, "%s.x%d.png" % (tex, n)), w * n, h * n, out)
    table[tex] = n
    pixels += w * n * h * n
    made += 1

with open(os.path.join(DATA, "texture_tiles.lua"), "w", encoding="utf-8", newline="\n") as fh:
    fh.write("-- SM64Map: each solid level texture's copy repeated N x N (textures/<name>.x<N>.png) - tools/tile_textures.py, lib.lua M.TILES\nreturn {\n")
    for tex in sorted(table):
        fh.write('  ["%s"] = %d,\n' % (tex, table[tex]))
    fh.write("}\n")
print("textures tiled:", made, "of", len(span), " all copies together: %.0f MB in memory" % (pixels * 4 / 1e6))
