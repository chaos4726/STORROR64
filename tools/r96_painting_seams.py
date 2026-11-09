"""r96_painting_seams.py: the Render 96 paintings' middle seam taken out ("here is a seam its not just this picture either
others have this seam as well please fix them", then "still a seam btw", 2026-11-01).
Mario 64 draws each painting from two pictures, its top and bottom halves; Render 96 redrew them apart, and the bottom
half begins with a band that repeats the top half's last rows (8 of 512 in most: its row 263 is the top's 255) - joined,
the band shows twice and the picture jumps across the middle (the snowman painting's tree leaves broke there). Where the
band is found (rows matching with no sideways shift, closer than the picture's own row-to-row change), the two copies are
blended into one and the painting stretched back to its size (by under 2%). Where none is found, the step across the
join is shared out over a band either side instead. Always from the originals, kept in textures_r96_paint_orig.
python tools/r96_painting_seams.py   (from X:/mashup-work)"""
import glob
import os
import shutil

import numpy as np
from PIL import Image

MOD = r"E:\SteamLibrary\steamapps\common\STORROR Parkour Pro\STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map"
R96 = os.path.join(MOD, "textures_r96")
ORIG = os.path.join(MOD, "textures_r96_paint_orig")
BAND = 24
RATIO = 1.8
os.makedirs(ORIG, exist_ok=True)


def overlap(a, m):
    """the repeated band under the join: (dy, ref) - the bottom half's row m + dy is the top's row m - ref (the top's last
    row or two can be odd ones out: Whomp's Fortress's), or None"""
    h, w = a.shape[:2]
    x0, x1 = int(w * 0.12), int(w * 0.88)
    step = np.abs(a[m, x0:x1, :3] - a[m - 1, x0:x1, :3]).mean()
    best = None
    for ref in (1, 2, 3):
        top = a[m - ref, x0:x1, :3]
        own = max(np.abs(a[m - ref, x0:x1, :3] - a[m - ref - 1, x0:x1, :3]).mean(), 0.5)
        for dy in range(1, max(4, h // 32)):
            e = np.abs(a[m + dy, x0:x1, :3] - top).mean()
            # (and the row before it, matching the top's row before - not one row alike by chance)
            e2 = np.abs(a[m + dy - 1, x0:x1, :3] - a[m - ref - 1, x0:x1, :3]).mean()
            score = max(e, e2) / own
            if best is None or score < best[0]:
                best = (score, dy, ref, max(e, e2))
    score, dy, ref, e = best
    # (close: nearer than the picture's own change from row to row - or, where that is next to nothing (a flat wall),
    # than a third of the jump across the join)
    if not (score <= 0.75 or e <= 0.3 * step):
        return None
    return dy, ref


def ease(a, m):
    """the step at the join shared out over BAND rows either side (smoothed along the row, so it does not streak)"""
    h, w = a.shape[:2]
    band = max(4, BAND * h // 512)
    d = (a[m] + a[m + 1]) * 0.5 - (a[m - 1] + a[m - 2]) * 0.5
    k = max(3, w // 64)
    ker = np.ones(2 * k + 1) / (2 * k + 1)
    for c in range(a.shape[2]):
        d[:, c] = np.convolve(np.pad(d[:, c], k, mode="edge"), ker, mode="valid")
    out = a.copy()
    for i in range(band):
        f = 0.5 * (1.0 - i / band)
        out[m - 1 - i] += d * f
        out[m + i] -= d * f
    return out


def seam(img):
    a = np.asarray(img.convert("RGB")).astype(np.float64)
    h, w = a.shape[:2]
    x0, x1 = int(w * 0.15), int(w * 0.85)
    rd = np.abs(np.diff(a[:, x0:x1], axis=0)).mean(axis=(1, 2))
    return rd[h // 2 - 1] / max(np.median(rd), 0.5)


for p in sorted(glob.glob(os.path.join(R96, "painting_*.png"))):
    name = os.path.basename(p)
    src = os.path.join(ORIG, name)
    if not os.path.exists(src):
        shutil.copy2(p, src)
    im = Image.open(src)
    mode = im.mode
    a = np.asarray(im.convert("RGBA")).astype(np.float64)
    h, w = a.shape[:2]
    if h < 64:
        continue
    m = h // 2
    before = seam(im)
    found = overlap(a, m)
    if found is not None:
        dy, ref = found
        n = dy + 1                                      # (rows the two copies share)
        top, bot = a[:m - ref + 1], a[m:]               # (the top's odd last rows, if any, left out)
        t0 = top.shape[0]
        keep_top = top[:t0 - n]
        blend = np.empty((n, w, 4))
        for i in range(n):
            t = (i + 0.5) / n
            blend[i] = top[t0 - n + i] * (1.0 - t) + bot[i] * t
        out = np.concatenate([keep_top, blend, bot[n:]], axis=0)
        img = Image.fromarray(out.round().clip(0, 255).astype(np.uint8), "RGBA").resize((w, h), Image.LANCZOS)
        how = "band of %d rows shown twice, made one%s" % (n, (" (%d odd row(s) out)" % (ref - 1)) if ref > 1 else "")
    elif before >= RATIO:
        img = Image.fromarray(ease(a, m).round().clip(0, 255).astype(np.uint8), "RGBA")
        how = "no band found: the step eased"
    else:
        img = Image.fromarray(a.round().clip(0, 255).astype(np.uint8), "RGBA")
        how = "no seam"
    if mode == "RGB":
        img = img.convert("RGB")
    img.save(p)
    print("%-24s %dx%d seam %.1f -> %.1f  %s" % (name, w, h, before, seam(img), how))
