# The HUD's star counter rainbow once Final Bowser's rainbow star is the file's (health.lua M.star_rainbow_tick: "after
# the player collects the rainbow star make the star counter star in hud rainbow", 2026-11-04): hud_star_rb_0..11 from
# hud_star.png - its shading and outline kept, its colour the rainbow across it on the slant, each picture the rainbow
# moved on a twelfth, for the HUD to step through. Made for textures/ (Mario 64's, ROM-locked in a release:
# release/locked_list.txt) and textures_r96/.
# python -P tools/hud_star_rainbow_tex.py <mod dir>
import sys, os
import numpy as np
from PIL import Image

N = 12
mod = sys.argv[1]
for sub in ("textures", "textures_r96"):
    src = os.path.join(mod, sub, "hud_star.png")
    if not os.path.exists(src):
        continue
    im = np.asarray(Image.open(src).convert("RGBA")).astype(np.float64) / 255.0
    h, w = im.shape[:2]
    rgb, a = im[..., :3], im[..., 3]
    val = rgb.max(axis=2)                                   # (its shading: the outline dark, the face bright)
    lit = a > 0.05
    vmax = max(1e-6, np.percentile(val[lit], 95)) if lit.any() else 1.0
    v = np.clip(val / vmax, 0.0, 1.0)
    # (its highlights - near white in the yellow star - kept pale)
    sat0 = rgb.max(axis=2) - rgb.min(axis=2)
    pale = np.clip(1.0 - sat0 / max(1e-6, np.percentile(sat0[lit], 60) if lit.any() else 1.0), 0.0, 1.0)
    y, x = np.mgrid[0:h, 0:w]
    u = (x / w * 0.9 + y / h * 0.6)
    for k in range(N):
        hue = (u + k / N) % 1.0
        s = 0.9 * (1.0 - 0.75 * pale)
        h6 = hue * 6.0
        i = np.floor(h6).astype(int) % 6
        f = h6 - np.floor(h6)
        p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
        out = np.zeros((h, w, 3))
        for j, (r_, g_, b_) in enumerate(((v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q))):
            m = i == j
            out[m, 0], out[m, 1], out[m, 2] = r_[m], g_[m], b_[m]
        img = np.dstack([out, a])
        Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(mod, sub, "hud_star_rb_%d.png" % k))
    print(sub, w, "x", h, ":", N, "pictures")
