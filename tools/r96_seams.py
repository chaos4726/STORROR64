"""r96_seams.py: the Render 96 pictures made to meet themselves where the levels repeat them ("still got squares showing in
textures", 2026-10-31). Render 96's pictures were redrawn from Mario 64's small ones without making their edges meet: drawn
side by side across a floor, each repeat showed as a line - the floors looked like big squares. (Mario 64's own are drawn
from tiled copies, lib.lua M.tiles; Render 96's as they are.)
Which pictures repeat, and which way: the levels' own faces (data/scene_*.lua) - a face whose u (or v) runs across a whole
number repeats there. Each such edge whose two sides disagree (more than SEAM times the picture's own pixel-to-pixel
change) is blended over a thin band: the rows (or columns) near one edge eased toward their opposites across the wrap,
the two edges meeting in the middle. The originals kept in textures_r96_seams_orig (run again: starts from those).
python tools/r96_seams.py [--dry]   (from X:/mashup-work)"""
import glob
import os
import shutil
import sys

import lupa.lua54 as lua54
import numpy as np
from PIL import Image

MOD = r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map"
R96 = os.path.join(MOD, "textures_r96")
ORIG = os.path.join(MOD, "textures_r96_seams_orig")
DATA = os.path.join(MOD, "Scripts", "data")
SEAM = 1.8
MARGIN = 0.05
DRY = "--dry" in sys.argv

# ---- which pictures repeat, and which way
L = lua54.LuaRuntime()
rep_u, rep_v = {}, {}
for f in sorted(glob.glob(os.path.join(DATA, "scene_*.lua"))):
    try:
        d = L.eval("loadfile")(f)()
    except Exception:
        continue
    secs = d["sections"]
    if not secs:
        continue
    for k in range(1, len(secs) + 1):
        s = secs[k]
        tex = s["texture"]
        # (solid and see-through faces only: a cut-out's edges blended would change where it is cut)
        if s["layer"] not in ("opaque", "lit", "translucent"):
            continue
        uv, idx = s["uv"], s["idx"]
        if not tex or not uv or not idx:
            continue
        n = len(idx)
        U = [uv[i] for i in range(1, len(uv) + 1)]
        I = [idx[i] for i in range(1, n + 1)]
        cu = cv = 0
        for t in range(0, n - 2, 3):
            a, b, c = I[t], I[t + 1], I[t + 2]
            us = (U[a * 2], U[b * 2], U[c * 2])
            vs = (U[a * 2 + 1], U[b * 2 + 1], U[c * 2 + 1])
            # (a face running at least MARGIN of a repeat past an edge: not the half-pixel overshoot of a face that shows
            # the picture once - its trim's edge left sharp)
            if np.floor(min(us) + MARGIN) != np.floor(max(us) - MARGIN):
                cu += 1
            if np.floor(min(vs) + MARGIN) != np.floor(max(vs) - MARGIN):
                cv += 1
        rep_u[tex] = rep_u.get(tex, 0) + cu
        rep_v[tex] = rep_v.get(tex, 0) + cv

# ---- the pictures' edges
os.makedirs(ORIG, exist_ok=True)
fixed = 0
for tex in sorted(set(rep_u) | set(rep_v)):
    ru, rv = rep_u.get(tex, 0), rep_v.get(tex, 0)
    if ru == 0 and rv == 0:
        continue
    path = os.path.join(R96, tex + ".png")
    if not os.path.exists(path):
        continue
    src = os.path.join(ORIG, tex + ".png")
    if not os.path.exists(src):
        if not DRY:
            shutil.copy2(path, src)
        else:
            src = path
    im = Image.open(src)
    mode = im.mode
    a = np.asarray(im.convert("RGBA")).astype(np.float64)
    h, w = a.shape[:2]
    rgb = a[..., :3]
    out = a.copy()
    did = []
    # (u runs along the picture's width: its left and right edges meet)
    inner_x = max(np.abs(np.diff(rgb, axis=1)).mean(), 0.5)
    inner_y = max(np.abs(np.diff(rgb, axis=0)).mean(), 0.5)
    lr = np.abs(rgb[:, 0] - rgb[:, -1]).mean() / inner_x
    tb = np.abs(rgb[0, :] - rgb[-1, :]).mean() / inner_y
    if ru > 0 and lr > SEAM:
        B = max(4, w // 32)
        src_cols = out.copy()
        for i in range(B):
            wgt = 0.5 * (1.0 - i / B)
            left, right = src_cols[:, i], src_cols[:, w - 1 - i]
            out[:, i] = left * (1 - wgt) + right * wgt
            out[:, w - 1 - i] = right * (1 - wgt) + left * wgt
        did.append("left/right %.1f" % lr)
    if rv > 0 and tb > SEAM:
        B = max(4, h // 32)
        src_rows = out.copy()
        for i in range(B):
            wgt = 0.5 * (1.0 - i / B)
            top, bot = src_rows[i], src_rows[h - 1 - i]
            out[i] = top * (1 - wgt) + bot * wgt
            out[h - 1 - i] = bot * (1 - wgt) + top * wgt
        did.append("top/bottom %.1f" % tb)
    if did:
        fixed += 1
        print("%-55s %4dx%-4d repeats u%d v%d: %s" % (tex, w, h, ru, rv, ", ".join(did)))
        if not DRY:
            img = Image.fromarray(out.round().clip(0, 255).astype(np.uint8), "RGBA")
            if mode == "RGB":
                img = img.convert("RGB")
            img.save(path)
print("%s: %d pictures' seams blended" % ("dry run" if DRY else "done", fixed))
